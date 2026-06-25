#!/usr/bin/env python3
"""
rvi_cycles.py  --  Cycle-exact validator / comment-rewriter for BBC RVI raster code.

Statically analyses a single BeebAsm function (default: fx_draw_function) that
abuses the 6845 CRTC ("RVI"), and:

  * computes the true cycle cost of every line, applying the 1 MHz cycle-stretch
    model for accesses to stretched SHEILA peripherals (CRTC / VIA / FRED / JIM),
  * tracks the running per-scanline cumulative cycle count (128 c per 64 us line),
  * validates the cycle-exact critical CRTC register writes (e.g. R0 landing on
    its required character boundary) and the 128 c-per-scanline invariant,
  * flags page-boundary branch crossings and bugged page guards,
  * reports discrepancies vs the existing hand-written `; Nc` / `\\ <== Nc`
    comments, separating HARMFUL drift (shifts a stretched-write barrier) from
    HARMLESS drift (absorbed by the next stretch re-sync),
  * with --write, rewrites the per-line cost comments and `\\ <== Nc` running
    totals in place.

This is a STATIC analyser of a constrained BeebAsm subset, not a full assembler.

See SKILL.md for the model write-up.  Run with --help.
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ----------------------------------------------------------------------------
# 1 MHz cycle stretching
#
# A 2 MHz CPU access to a 1 MHz ("stretched") peripheral completes on the next
# 1 MHz boundary, with a minimum of +1 stretch cycle.  We model a 1 MHz boundary
# as an *even* cumulative cycle (scanline start = cum 0 = boundary).
#
#   end = cum + base + 1            (minimum one stretch)
#   if end is not on a boundary: end += 1
#   cost = end - cum
#
# Crucially this means the access always finishes on an even cycle, so a +/-1
# error in the non-stretched code before it is absorbed: the barrier does not
# move.  That property is what makes the running totals robust.
#
# Stretched address ranges (Master 128 / B), per the cycle-stretching wiki:
#   &FC00-&FDFF  FRED / JIM (1 MHz bus)
#   &FE00-&FE1F  CRTC / ACIA / Serial ULA / STATID
#   &FE40-&FE7F  System VIA / User VIA
#   &FEC0-&FEDF  ADC
# NOT stretched: &FE20-&FE3F (Video ULA, ROMSEL, ACCCON), &FE80+ (FDC, Econet,
# Tube), all RAM/ROM.
# ----------------------------------------------------------------------------

STRETCHED_RANGES = [
    (0xFC00, 0xFDFF),
    (0xFE00, 0xFE1F),
    (0xFE40, 0xFE7F),
    (0xFEC0, 0xFEDF),
]


def is_stretched(addr):
    if addr is None:
        return False
    return any(lo <= addr <= hi for lo, hi in STRETCHED_RANGES)


def stretch_cost(cum, base):
    """Cost of a single-bus-access stretched instruction starting at `cum`."""
    end = cum + base + 1
    if end % 2 != 0:        # not on a 1 MHz (even) boundary yet
        end += 1
    return end - cum


# ----------------------------------------------------------------------------
# 65C02 base cycle costs (no stretch).  Keyed by (mnemonic, mode).
# Modes: imp, acc, imm, zp, zpx, zpy, abs, abx, aby, izp, izy, izx, rel
# ----------------------------------------------------------------------------

IMPLIED_2 = {"clc", "sec", "cli", "sei", "clv", "cld", "sed", "nop",
             "tax", "tay", "txa", "tya", "tsx", "txs", "inx", "iny",
             "dex", "dey"}
PUSH_3 = {"pha", "php", "phx", "phy"}
PULL_4 = {"pla", "plp", "plx", "ply"}
BRANCHES = {"bcc", "bcs", "beq", "bne", "bmi", "bpl", "bvc", "bvs", "bra"}
RMW = {"asl", "lsr", "rol", "ror", "inc", "dec", "trb", "tsb"}

# base cost tables for the common (non-RMW) ops
BASE = {
    "imm": 2, "zp": 3, "zpx": 4, "zpy": 4,
    "abs": 4, "abx": 4, "aby": 4,
    "izp": 5, "izy": 5, "izx": 6,
}
# RMW are pricier
RMW_BASE = {"zp": 5, "zpx": 6, "abs": 6, "abx": 7}
STORE_INDEXED = {"sta", "stz"}   # abs,X / abs,Y stores are fixed 5c (no page discount)


class CostError(Exception):
    pass


# ----------------------------------------------------------------------------
# Tiny expression evaluator for immediates / WAIT_CYCLES / config values.
# Handles &hex / $hex, decimal, +-*/, parentheses, and known symbol map.
# Unknown symbols -> raises (caller decides).
# ----------------------------------------------------------------------------

def eval_expr(expr, symbols):
    expr = expr.strip()
    if not expr:
        raise CostError("empty expression")
    # hex: &xx or $xx -> decimal, up front, so 'x' can't be seen as an identifier
    s = re.sub(r"[&$]([0-9A-Fa-f]+)", lambda m: str(int(m.group(1), 16)), expr)
    # replace remaining identifiers with their symbol values
    def repl(m):
        name = m.group(0)
        if name in symbols:
            return str(symbols[name])
        raise CostError(f"unknown symbol '{name}'")
    s = re.sub(r"[A-Za-z_][A-Za-z0-9_]*", repl, s)
    if not re.fullmatch(r"[0-9+\-*/() ]+", s):
        raise CostError(f"unsafe expression '{expr}'")
    try:
        return int(eval(s, {"__builtins__": {}}, {}))
    except Exception as e:
        raise CostError(f"cannot evaluate '{expr}': {e}")


# ----------------------------------------------------------------------------
# Parsing
# ----------------------------------------------------------------------------

COMMENT_RE = re.compile(r"[;\\]")   # BeebAsm comments start with ; or \

def split_statements(code):
    """Split a code string on ':' but not inside double-quoted strings."""
    out, cur, inq = [], [], False
    for ch in code:
        if ch == '"':
            inq = not inq
            cur.append(ch)
        elif ch == ":" and not inq:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def split_comment(line):
    """Return (code, comment_text, comment_char_index) ; comment includes marker."""
    m = COMMENT_RE.search(line)
    if not m:
        return line, "", -1
    idx = m.start()
    return line[:idx], line[idx:], idx


def parse_operand_mode(mnem, operand):
    """Return (mode, addr_or_None, raw) for an operand string.

    addr is the absolute numeric address if it is a literal &/$ hex (used for
    stretch detection); None for symbolic operands (region looked up by caller).
    """
    operand = operand.strip()
    if operand == "" :
        return "imp", None
    if operand.lower() == "a":
        return "acc", None
    if operand.startswith("#"):
        return "imm", None
    # indirect forms
    if operand.startswith("(") :
        inner = operand
        if re.search(r"\)\s*,\s*[yY]$", inner):
            return "izy", None
        if re.search(r",\s*[xX]\s*\)$", inner):
            return "izx", None
        return "izp", None
    # indexed?
    mIdx = re.match(r"^(.*?)\s*,\s*([xXyY])$", operand)
    index = None
    base_op = operand
    if mIdx:
        base_op = mIdx.group(1).strip()
        index = mIdx.group(2).lower()
    addr = None
    mhex = re.fullmatch(r"[&$]([0-9A-Fa-f]+)", base_op)
    if mhex:
        addr = int(mhex.group(1), 16)
    return ("__indexed__" if index else "__plain__", addr, base_op, index)


def classify(mnem, operand, symbols, zp_symbols):
    """Return (mode, base_cost_before_stretch, addr_for_stretch, info).

    Resolves zp vs abs for symbolic operands using zp_symbols.
    """
    mnem = mnem.lower()
    p = parse_operand_mode(mnem, operand)
    mode = p[0]
    addr = p[1]

    # implied / accumulator
    if mode == "imp":
        if mnem in IMPLIED_2:
            return "imp", 2, None
        if mnem in PUSH_3:
            return "imp", 3, None
        if mnem in PULL_4:
            return "imp", 4, None
        if mnem in ("rts", "rti"):
            return "imp", 6, None
        if mnem == "brk":
            return "imp", 7, None
        raise CostError(f"unknown implied mnemonic '{mnem}'")
    if mode == "acc":
        return "acc", 2, None      # asl a / lsr a / inc a ... 65C02
    if mode == "imm":
        return "imm", 2, None

    # branches
    if mnem in BRANCHES:
        return "rel", 2, None      # +1 taken handled by caller

    if mnem in ("jmp",):
        if operand.strip().startswith("("):
            return "ind", 6, None
        return "abs3", 3, None
    if mnem in ("jsr",):
        return "abs3", 6, None

    # indirect zp forms
    if mode in ("izp", "izy", "izx"):
        if mnem == "sta" and mode == "izy":
            return mode, 6, None
        return mode, BASE[mode], None

    # plain or indexed memory operand: decide zp vs abs
    base_op = p[2] if len(p) > 2 else operand
    index = p[3] if len(p) > 3 else None

    # determine width: literal hex addr, or symbol region
    width = None
    if addr is not None:
        width = "zp" if addr <= 0xFF else "abs"
    else:
        sym = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", base_op)
        name = sym.group(1) if sym else None
        if name in zp_symbols:
            width = "zp"
        else:
            width = "abs"   # default assumption for non-ZP symbols

    if index:
        if width == "zp":
            m = "zpx" if index == "x" else "zpy"
        else:
            m = "abx" if index == "x" else "aby"
    else:
        m = width

    if mnem in RMW:
        if m not in RMW_BASE:
            raise CostError(f"RMW {mnem} mode {m} not tabled")
        return m, RMW_BASE[m], addr
    # stores to abs,X/abs,Y are fixed 5c
    if mnem in STORE_INDEXED and m in ("abx", "aby"):
        return m, 5, addr
    if m not in BASE:
        raise CostError(f"{mnem} mode {m} not tabled")
    return m, BASE[m], addr


# ----------------------------------------------------------------------------
# Statement / line model
# ----------------------------------------------------------------------------

class Stmt:
    def __init__(self, text):
        self.text = text.strip()
        self.cost = 0
        self.mnem = None
        self.operand = None
        self.note = ""        # analyser annotation (e.g. stretched, taken)
        self.is_label = False
        self.is_directive = False
        self.kind = None      # 'instr','label','wait','directive','blank'


class SrcLine:
    def __init__(self, lineno, raw):
        self.lineno = lineno
        self.raw = raw.rstrip("\n")
        self.code, self.comment, self.comment_idx = split_comment(self.raw)
        self.stmts = []
        self.line_cost = 0
        self.cum_before = None
        self.cum_after = None
        self.flags = []       # (severity, message)
        self.has_instr = False
        self.is_wait = False


# ----------------------------------------------------------------------------
# Analyser
# ----------------------------------------------------------------------------

class Analyser:
    def __init__(self, cfg, srctext):
        self.cfg = cfg
        self.lines = srctext.splitlines()
        self.symbols = dict(cfg.get("symbols", {}))
        self.zp_symbols = set(cfg.get("extra_zp_symbols", []))
        self.entry_phase = cfg.get("entry_phase", 0)
        self.scanline = cfg.get("scanline_cycles", 128)
        self.reg_constraints = {int(k): v for k, v in cfg.get("register_constraints", {}).items()}
        self.func = cfg.get("function", "fx_draw_function")
        self.origin = cfg.get("origin", None)
        self.page_aligned = set(cfg.get("page_aligned_symbols", []))

        self.findings = []          # global findings
        self.reg_writes = []        # recorded CRTC value writes
        self.label_cum = {}         # label -> cum at that point
        self.label_pc = {}          # label -> pc offset
        self._scan_top_level()

    def add(self, sev, msg):
        self.findings.append((sev, msg))

    def _scan_top_level(self):
        """Collect ZP symbols (ORG <0x100 ... GUARD), page-aligned labels
        (.label immediately after ALIGN &100) and top-level NAME=expr."""
        in_zp = False
        prev_align256 = False
        for raw in self.lines:
            code, _, _ = split_comment(raw)
            s = code.strip()
            if not s:
                continue
            mAlign = re.match(r"(?i)^ALIGN\s+(.+)$", s)
            if mAlign:
                try:
                    prev_align256 = (eval_expr(mAlign.group(1), self.symbols) == 0x100)
                except CostError:
                    prev_align256 = False
                continue
            mAnyLbl = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*)\b", s)
            if mAnyLbl and prev_align256:
                self.page_aligned.add(mAnyLbl.group(1))
            if not mAnyLbl:
                prev_align256 = False
            mOrg = re.match(r"(?i)^ORG\s+(.+)$", s)
            if mOrg:
                try:
                    val = eval_expr(mOrg.group(1), self.symbols)
                    in_zp = val < 0x100
                except CostError:
                    in_zp = False
                continue
            if re.match(r"(?i)^GUARD\b", s):
                # GUARD sets an assembly limit; it does NOT end the ORG region.
                continue
            if in_zp:
                mLbl = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*)\b", s)
                if mLbl:
                    self.zp_symbols.add(mLbl.group(1))
            # NAME = expr  (constants)
            mDef = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", s)
            if mDef and not s.startswith("."):
                name, expr = mDef.group(1), mDef.group(2)
                try:
                    self.symbols[name] = eval_expr(expr, self.symbols)
                except CostError:
                    pass

    def extract_function(self):
        start = None
        for i, raw in enumerate(self.lines):
            if raw.strip().startswith(".%s" % self.func):
                start = i
                break
        if start is None:
            raise SystemExit(f"function .{self.func} not found")
        # end: next .fx_*_function label, or .fx_end / .<func>_done? Use next
        # top-level .fx_..._function (other than ours) or .fx_end.
        end = len(self.lines)
        for i in range(start + 1, len(self.lines)):
            s = self.lines[i].strip()
            if re.match(r"^\.fx_\w+_function\b", s) or s.startswith(".fx_end"):
                end = i
                break
        return start, end

    def analyse(self):
        start, end = self.extract_function()
        cum = self.entry_phase
        pc = 0  # byte offset from function start
        if self.origin is not None:
            pc = self.origin
        src_lines = []
        last_imm = None         # value of most recent lda #imm
        selected_reg = None     # last value written to &fe00
        pending_adjust = 0      # deferred fall-through (-1) applied at next real code

        for i in range(start, end):
            sl = SrcLine(i + 1, self.lines[i])
            src_lines.append(sl)
            sl.cum_before = cum
            code = sl.code

            # statements separated by ':' (quote-aware)
            raw_stmts = split_statements(code)
            for raw_stmt in raw_stmts:
                st = raw_stmt.strip()
                if st == "":
                    continue
                # label
                if st.startswith("."):
                    mLbl = re.match(r"^\.([A-Za-z_][A-Za-z0-9_]*)", st)
                    if mLbl:
                        self.label_cum[mLbl.group(1)] = cum
                        self.label_pc[mLbl.group(1)] = pc
                    rest = st[mLbl.end():].strip() if mLbl else ""
                    if rest == "":
                        continue
                    st = rest  # label followed by instruction on same stmt
                # directives we treat as zero-cost (but inspect some)
                mDir = re.match(r"(?i)^(IF|ELIF|ELSE|ENDIF|ERROR|PRINT|ALIGN|EQU[BWDS]|SKIP|MACRO|ENDMACRO|FOR|NEXT|ORG|GUARD)\b", st)
                if mDir:
                    self._inspect_directive(st, sl)
                    continue
                # WAIT_CYCLES n
                mWait = re.match(r"(?i)^WAIT_CYCLES\s+(.+)$", st)
                if mWait:
                    if pending_adjust:
                        cum += pending_adjust
                        pending_adjust = 0
                    try:
                        n = eval_expr(mWait.group(1), self.symbols)
                    except CostError as e:
                        sl.flags.append(("ERROR", f"WAIT_CYCLES arg: {e}"))
                        n = 0
                    cum += n
                    sl.line_cost += n
                    sl.is_wait = True
                    continue
                # instruction
                mIns = re.match(r"^([A-Za-z]{3})\b(.*)$", st)
                if not mIns:
                    sl.flags.append(("WARN", f"unparsed statement '{st}'"))
                    continue
                mnem = mIns.group(1).lower()
                operand = mIns.group(2).strip()

                # track immediates for register/value reporting
                if mnem == "lda" and operand.startswith("#"):
                    try:
                        last_imm = eval_expr(operand[1:], self.symbols)
                    except CostError:
                        last_imm = None

                if pending_adjust:
                    cum += pending_adjust
                    pending_adjust = 0

                try:
                    mode, base, addr = classify(mnem, operand, self.symbols, self.zp_symbols)
                except CostError as e:
                    sl.flags.append(("ERROR", f"{st}: {e}"))
                    continue
                sl.has_instr = True
                self._check_page_cross(mnem, mode, operand, sl)

                cost, note, bytelen = self._cost_with_stretch(
                    mnem, mode, base, addr, operand, cum, pc)
                cum += cost
                pc += bytelen
                sl.line_cost += cost

                # Branch accounting: the per-line cost above is the TAKEN cost
                # (convention).  For a backward branch that forms a loop, check
                # the iteration length using the taken cum, then back out 1c so
                # the linear walk continues on the not-taken (fall-through) path.
                if mnem in BRANCHES:
                    tgt = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", operand.strip())
                    lbl = tgt.group(1) if tgt else None
                    if lbl in self.label_cum and self.label_cum[lbl] <= cum:
                        iter_len = cum - self.label_cum[lbl]
                        if iter_len % self.scanline != 0:
                            self.add("ERROR", f"loop to .{lbl} (line {sl.lineno}) "
                                     f"iteration = {iter_len}c, not a multiple of {self.scanline}c")
                        else:
                            self.add("OK", f"loop to .{lbl} iteration = {iter_len}c "
                                     f"({iter_len // self.scanline} scanline(s))")
                        pending_adjust = -1   # fall-through is not-taken (deferred)
                    elif lbl is not None:
                        sl.flags.append(("WARN", f"forward branch to .{lbl} counted as "
                                         "taken; linear walk may be inaccurate past here"))

                # CRTC register-select / value-write tracking
                stretched_addr = addr if addr is not None else self._sym_addr(operand)
                if mnem in ("sta", "stz") and stretched_addr == 0xFE00:
                    selected_reg = 0 if mnem == "stz" else last_imm
                    pending_select_imm = None
                elif mnem in ("sta", "stz") and stretched_addr == 0xFE01:
                    val = 0 if mnem == "stz" else last_imm
                    self._record_reg_write(selected_reg, val, cum, sl)

            sl.cum_after = cum

        self.src_lines = src_lines
        self.func_range = (start, end)
        self._post_checks()
        return src_lines

    # mnemonics whose indexed/indirect-Y READ costs +1c on a page cross
    PAGECROSS_READS = {"lda", "ldx", "ldy", "cmp", "cpx", "cpy",
                       "adc", "sbc", "and", "ora", "eor", "bit"}

    def _check_page_cross(self, mnem, mode, operand, sl):
        """Indexed reads (abs,X / abs,Y / (zp),Y) cost +1c AND become
        data-dependent if the table crosses a 256-byte page. Require the table
        to be provably page-aligned; otherwise warn."""
        if mnem not in self.PAGECROSS_READS:
            return
        if mode not in ("abx", "aby", "izy"):
            return
        base = re.sub(r"\s*,\s*[xXyY]\s*$", "", operand.strip())
        base = base.lstrip("(").rstrip(")")
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", base)
        if not m:
            return                      # literal/expression base - can't reason
        name = m.group(1)
        if name in self.page_aligned:
            return                      # asserted/known page-aligned -> safe
        sl.flags.append(("WARN",
            f"{mnem} {operand}: indexed read into '{name}' which is not known to "
            f"be page-aligned. A page cross adds +1c AND varies by index (breaks "
            f"cycle-exactness). Use ALIGN &100 or add '{name}' to "
            f"page_aligned_symbols in the config."))

    def _sym_addr(self, operand):
        m = re.match(r"^[&$]([0-9A-Fa-f]+)", operand.strip())
        if m:
            return int(m.group(1), 16)
        return None

    def _cost_with_stretch(self, mnem, mode, base, addr, operand, cum, pc):
        note = ""
        bytelen = self._bytelen(mode)
        # branch taken handling
        if mode == "rel":
            # default: count as taken (3c)
            cost = base + 1
            note = "taken"
            # page-cross detection
            tgt = self._branch_target(operand)
            if tgt is not None and self.origin is not None:
                after = pc + 2
                if (after & 0xFF00) != (tgt & 0xFF00):
                    cost += 1
                    note = "taken+pagecross"
            return cost, note, bytelen
        # stretched memory access?
        if is_stretched(addr):
            cost = stretch_cost(cum, base)
            note = f"stretched(+{cost - base})"
            return cost, note, bytelen
        return base, note, bytelen

    def _bytelen(self, mode):
        return {
            "imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2,
            "abs": 3, "abx": 3, "aby": 3, "abs3": 3, "ind": 3,
            "izp": 2, "izy": 2, "izx": 2, "rel": 2,
        }.get(mode, 3)

    def _branch_target(self, operand):
        name = operand.strip()
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", name)
        if m and m.group(1) in self.label_pc:
            return self.label_pc[m.group(1)]
        return None

    def _record_reg_write(self, reg, val, cum, sl):
        rec = {"reg": reg, "val": val, "cum": cum, "lineno": sl.lineno}
        self.reg_writes.append(rec)
        if reg is None:
            sl.flags.append(("WARN", "CRTC value write with unknown selected register"))
            return
        c = self.reg_constraints.get(reg)
        if c is None:
            sl.flags.append(("ASK", f"R{reg} write not in config register_constraints -please define its constraint"))
            return
        cyc = cum % self.scanline
        if "exact_completion" in c:
            targets = c["exact_completion"]
            ok = cyc in targets
            valstr = f"={val}" if val is not None else ""
            if ok:
                sl.flags.append(("OK", f"R{reg}{valstr} write completes at {cyc}c (allowed {targets})"))
            else:
                sl.flags.append(("ERROR", f"R{reg}{valstr} write completes at {cyc}c, REQUIRED {targets}"))
            if "min_value_for_hsync" in c and val is not None and val < c["min_value_for_hsync"]:
                sl.flags.append(("INFO", f"R{reg}={val} < hsync pos {c['min_value_for_hsync']} (no hsync this segment -intended for short rows)"))
        elif c.get("before_row_end"):
            sl.flags.append(("INFO", f"R{reg} write at {cyc}c (soft window: before row end)"))

    def _inspect_directive(self, st, sl):
        # detect bugged page guard:  IF HI(x) <> HI(x)  (same expr both sides)
        mIf = re.match(r"(?i)^IF\s+(.+?)\s*(<>|!=)\s*(.+)$", st)
        if mIf:
            lhs = mIf.group(1).strip()
            rhs = mIf.group(3).strip()
            if lhs == rhs:
                sl.flags.append(("ERROR", f"page guard compares identical expressions ({lhs} <> {rhs}) -can never fire; likely a typo"))

    def _post_checks(self):
        # Loop-iteration checks are done inline during analyse() (so the
        # taken/not-taken cum split is handled correctly).  Reserved for future
        # whole-function invariants (e.g. total line count == 312).
        pass


# ----------------------------------------------------------------------------
# Existing-comment comparison + rewriting
# ----------------------------------------------------------------------------

PERLINE_RE = re.compile(r";\s*(\d+)\s*c\b", re.IGNORECASE)
RUNNING_RE = re.compile(r"<==\s*(\d+)\s*c(?:\s*/\s*0c)?", re.IGNORECASE)


def existing_perline(comment):
    m = PERLINE_RE.search(comment)
    return int(m.group(1)) if m else None


def existing_running(comment):
    m = RUNNING_RE.search(comment)
    return int(m.group(1)) if m else None


def render_running(cum, scanline):
    v = cum % scanline
    if v == 0:
        return f"{scanline}c/0c"
    return f"{v}c"


def build_report(an):
    out = []
    out.append(f"# RVI cycle analysis: .{an.func}")
    out.append(f"  entry phase = {an.entry_phase}c, scanline = {an.scanline}c, "
               f"origin = {an.origin if an.origin is not None else 'unknown (page-cross detection disabled)'}")
    out.append("")
    out.append("## Per-line (computed vs annotated)")
    out.append(f"{'line':>5}  {'cum':>7}  {'cost':>5}  {'ann':>4}  source")
    for sl in an.src_lines:
        if sl.line_cost == 0 and not sl.flags and not sl.code.strip():
            continue
        ann = existing_perline(sl.comment)
        run_ann = existing_running(sl.comment)
        mark = ""
        if ann is not None and ann != sl.line_cost:
            mark = f" <-- annotated {ann}c, true {sl.line_cost}c (will fix; barriers unaffected)"
        cumstr = render_running(sl.cum_after, an.scanline)
        anns = str(ann) if ann is not None else "-"
        srctxt = sl.code.strip()
        if not srctxt and run_ann is not None:
            srctxt = sl.comment.strip()
        line = f"{sl.lineno:>5}  {cumstr:>7}  {sl.line_cost:>4}c  {anns:>4}  {srctxt}{mark}"
        out.append(line)
        if run_ann is not None and run_ann != (sl.cum_after % an.scanline) and not (run_ann == an.scanline and sl.cum_after % an.scanline == 0):
            out.append(f"        >>> running-total marker says <== {run_ann}c, computed {cumstr}  (CHECK)")
        for sev, msg in sl.flags:
            out.append(f"        [{sev}] {msg}")
    out.append("")
    out.append("## Invariants & register writes")
    for sev, msg in an.findings:
        out.append(f"  [{sev}] {msg}")
    out.append("")
    out.append("## CRTC register write summary")
    for rw in an.reg_writes:
        reg = rw["reg"]
        cyc = rw["cum"] % an.scanline
        valstr = f"={rw['val']}" if rw["val"] is not None else ""
        out.append(f"  line {rw['lineno']:>4}: R{reg}{valstr} completes at {cyc}c")
    return "\n".join(out)


def rewrite(an, scanline, annotate_missing=False):
    """Return new full-file text with updated per-line and running comments.

    Rules (conservative - only touch numbers, never prose):
      * a `<== Nc` running-total marker -> updated to the computed cum.
      * a `; Nc` per-line cost number   -> updated to the computed line cost.
      * a code line with cost > 0 and NO comment at all -> append `; Nc`.
    Prose comments without a number are left untouched.
    """
    lines = list(an.lines)
    by_lineno = {sl.lineno: sl for sl in an.src_lines}
    for lineno, sl in by_lineno.items():
        raw = lines[lineno - 1]
        code, comment, idx = split_comment(raw)
        if RUNNING_RE.search(comment):
            new_comment = RUNNING_RE.sub("<== " + render_running(sl.cum_after, scanline), comment)
            lines[lineno - 1] = raw[:idx] + new_comment
        elif PERLINE_RE.search(comment):
            if sl.line_cost > 0:
                new_comment = PERLINE_RE.sub(f"; {sl.line_cost}c", comment, count=1)
                lines[lineno - 1] = raw[:idx] + new_comment
        elif (annotate_missing and sl.has_instr and not sl.is_wait
              and code.strip() and comment == ""):
            lines[lineno - 1] = code.rstrip() + "\t\t; " + f"{sl.line_cost}c"
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True, help="JSON config for the effect")
    ap.add_argument("--file", help="override source file from config")
    ap.add_argument("--write", action="store_true", help="rewrite comments in place")
    ap.add_argument("--out", help="write rewritten file here instead of in place (for diffing)")
    ap.add_argument("--annotate-missing", action="store_true",
                    help="also ADD a ; Nc cost comment to instruction lines that have none")
    args = ap.parse_args()

    cfg_path = Path(args.config)
    cfg = json.loads(cfg_path.read_text())
    src_path = Path(args.file or cfg["file"])
    if not src_path.is_absolute():
        # resolve relative to repo root (cwd) then to config dir
        cand = Path.cwd() / src_path
        src_path = cand if cand.exists() else (cfg_path.parent / src_path)

    srctext = src_path.read_text()
    an = Analyser(cfg, srctext)
    an.analyse()

    print(build_report(an))

    if args.write or args.out:
        newtext = rewrite(an, an.scanline, annotate_missing=args.annotate_missing)
        target = Path(args.out) if args.out else src_path
        target.write_text(newtext)
        print(f"\n[written] {target}")


if __name__ == "__main__":
    main()
