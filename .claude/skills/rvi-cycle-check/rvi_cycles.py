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
    elif re.fullmatch(r"\d+", base_op):     # decimal literal address (e.g. BIT 0)
        addr = int(base_op)
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
        elif name in symbols:
            # resolved constant (e.g. `foo = locals_start + 1`): zp if < &100
            width = "zp" if symbols[name] <= 0xFF else "abs"
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
        self.odd_stretch = False   # a stretched access on this line cost only +1
        self.izy_pagecross = False # an (zp),Y read that may cross a page


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
        # An effect is "soft-window" if NONE of its CRTC register constraints
        # demand cycle-exact completion (all are before_row_end). For such
        # vertical-rupture effects the rupture loop only needs to be ~N scanlines;
        # a near-miss is per-iteration drift (WARN), not a hard timing ERROR.
        self.soft_window = not any("exact_completion" in c
                                   for c in self.reg_constraints.values())
        self.func = cfg.get("function", "fx_draw_function")
        self.end_label = cfg.get("end_label")
        self.origin = cfg.get("origin", None)
        self.page_aligned = set(cfg.get("page_aligned_symbols", []))
        self.page_align_macros = set(cfg.get("page_align_macros", []))
        # JSR <name> total cost (the 6c JSR + body + its RTS) for calibrated /
        # external routines we don't want to (or can't) inline-walk. Local
        # straight-line subroutines are followed automatically (phase-accurate).
        self.subroutine_cycles = dict(cfg.get("subroutine_cycles", {}))

        self.findings = []          # global findings
        self.reg_writes = []        # recorded CRTC value writes (reg,val,cum,lineno)
        self.label_cum = {}         # label -> cum at that point
        self.label_pc = {}          # label -> pc offset
        self.loops = []             # backward-branch loops: label,label_cum,iter_len,lineno
        self.total_cum = None       # cumulative cycles at end of function (RTS)
        self.sub_lines = {}         # lineno -> SrcLine for inlined subroutine bodies
        self.sub_phase_conflict = set()  # subroutine labels walked at >1 phase
        self._scan_top_level()

    def add(self, sev, msg):
        self.findings.append((sev, msg))

    def _report_loop(self, lbl, iter_len, lineno):
        """Record a backward-branch loop and judge its length. A multiple of the
        scanline is OK. A near-miss is a hard ERROR for cycle-exact effects, but
        only a drift WARNING for soft-window vertical-rupture effects."""
        self.loops.append({"label": lbl, "label_cum": self.label_cum[lbl],
                           "iter_len": iter_len, "lineno": lineno})
        rem = iter_len % self.scanline
        if rem == 0:
            self.add("OK", f"loop to .{lbl} iteration = {iter_len}c "
                     f"({iter_len // self.scanline} scanline(s))")
            return
        drift = rem if rem <= self.scanline // 2 else rem - self.scanline
        nearest = round(iter_len / self.scanline)
        if self.soft_window:
            self.add("WARN", f"loop to .{lbl} (line {lineno}) iteration = {iter_len}c "
                     f"= {nearest} scanlines {drift:+d}c ({drift:+d}c/iteration drift). "
                     "Soft-window rupture: tolerable, but the CRTC address writes creep "
                     "relative to the row each iteration (cumulative drift over the loop).")
        else:
            self.add("ERROR", f"loop to .{lbl} (line {lineno}) iteration = {iter_len}c, "
                     f"not a multiple of {self.scanline}c")

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
            if s in self.page_align_macros:        # e.g. PAGE_ALIGN == ALIGN &100
                prev_align256 = True
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
        # end: an explicit end_label if configured, else the next sibling
        # routine (`.fx_*_function` / `.fx_end`), else the function's own
        # top-level RTS/JMP (depth 0 w.r.t. `{}`).
        end = len(self.lines)
        depth = 0
        for i in range(start + 1, len(self.lines)):
            s = self.lines[i].strip()
            if self.end_label and re.match(r"^\.%s\b" % re.escape(self.end_label), s):
                end = i
                break
            if not self.end_label:
                if re.match(r"^\.fx_\w+_function\b", s) or s.startswith(".fx_end"):
                    end = i
                    break
                for st in split_statements(split_comment(self.lines[i])[0]):
                    st = st.strip()
                    depth += st.count("{") - st.count("}")
                    if depth <= 0 and re.match(r"(?i)^(rts|rti)\b", st):
                        end = i + 1
                        break
                if end != len(self.lines):
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

        # Index-based walk so FOR..NEXT bodies can be replayed (the assembler
        # unrolls them; we re-walk the body `iters` times for correct cycles).
        sl_by_idx = {}
        for_stack = []          # (body_start_idx, remaining_iterations)
        diamond = None          # active balanced if/else, see below
        pending_loopback = None # (loop_label, loop_line) for a Bcc/JMP loop tail
        idx = start
        while idx < end:
            if idx in sl_by_idx:
                sl = sl_by_idx[idx]
            else:
                sl = SrcLine(idx + 1, self.lines[idx])
                sl_by_idx[idx] = sl
                src_lines.append(sl)
            sl.cum_before = cum
            sl.cum_after = cum      # default (overwritten below for code lines)
            code = sl.code
            stripped = code.strip()

            # FOR var,a,b[,c] : push a replay frame (count handled at NEXT)
            mFor = re.match(r"(?i)^FOR\s+\w+\s*,(.+)$", stripped)
            if mFor and ":" not in code:
                iters = self._for_iter_count(mFor.group(1))
                for_stack.append([idx + 1, iters])
                idx += 1
                continue
            if re.match(r"(?i)^NEXT\b", stripped) and ":" not in code and for_stack:
                frame = for_stack[-1]
                frame[1] -= 1
                if frame[1] > 0:
                    idx = frame[0]          # replay the body
                else:
                    for_stack.pop()
                    idx += 1
                continue

            # --- balanced if/else "diamond" -------------------------------
            # A forward conditional branch with an unconditional BRA/JMP before
            # its target is an if/else: two paths that must take equal cycles.
            # We walk path A (fall-through to the BRA), then path B (target ->
            # merge), check they are balanced, and use one cost for the total.
            mBr = re.match(r"(?i)^(b[a-z][a-z])\s+([A-Za-z_]\w*)\s*$", stripped)
            if (diamond is None and mBr and mBr.group(1).lower() != "bra"
                    and mBr.group(1).lower() in BRANCHES):
                L = self._find_label_line(mBr.group(2), idx + 1, end)
                jmp = None
                for j in range(idx + 1, L) if L else []:
                    mj = re.match(r"(?i)^(bra|jmp)\s+([A-Za-z_]\w*)\s*$",
                                  split_comment(self.lines[j])[0].strip())
                    if mj:
                        # only a diamond if the unconditional jump goes FORWARD
                        # (to a merge); a backward jump is a loop-back, not a merge.
                        mt = self._find_label_line(mj.group(2), start, end)
                        if mt is not None and mt >= L:
                            jmp = (j, mj.group(2))
                        break
                if L is not None and jmp is not None:
                    cum += 2                      # branch not-taken (path A)
                    sl.line_cost = 2
                    sl.cum_after = cum
                    diamond = {"entry": cum - 2, "L": L, "costA": None,
                               "phase": "A", "merge": None, "br_line": sl.lineno}
                    idx += 1
                    continue
            if diamond and diamond["phase"] == "A":
                mJ = re.match(r"(?i)^(bra|jmp)\s+([A-Za-z_]\w*)\s*$", stripped)
                if mJ:
                    cum += 3                      # BRA/JMP taken
                    sl.line_cost = 3
                    sl.cum_after = cum
                    diamond["costA"] = cum - diamond["entry"]
                    diamond["merge"] = self._find_label_line(mJ.group(2), start, end)
                    diamond["phase"] = "B"
                    cum = diamond["entry"] + 3    # path B begins (branch taken)
                    idx = diamond["L"]
                    continue
            if (diamond and diamond["phase"] == "B"
                    and diamond["merge"] is not None and idx == diamond["merge"]):
                costB = cum - diamond["entry"]
                if diamond["costA"] == costB:
                    self.add("OK", f"balanced branch at line {diamond['br_line']}: "
                             f"both paths {costB}c")
                else:
                    self.add("ERROR", f"UNBALANCED branch at line {diamond['br_line']}: "
                             f"path A {diamond['costA']}c vs path B {costB}c "
                             "(scanline timing will vary)")
                cum = diamond["entry"] + diamond["costA"]
                diamond = None
                # fall through to process the merge label line normally

            # --- loop-exit idiom: `Bcc EXIT` ; backward `JMP/BRA LOOP` ; `.EXIT`
            # (counter loops like `DEC c / BEQ done / JMP here / .done`). The
            # conditional is the loop exit (not-taken inside the loop, 2c); the
            # JMP is the loop-back.
            if diamond is None and pending_loopback is None:
                mCond = re.match(r"(?i)^(b[a-z][a-z])\s+([A-Za-z_]\w*)\s*$", stripped)
                if (mCond and mCond.group(1).lower() != "bra"
                        and mCond.group(1).lower() in BRANCHES):
                    jline = None
                    for j in range(idx + 1, end):
                        jc = split_comment(self.lines[j])[0].strip()
                        if jc:
                            jline = jc
                            break
                    mj = re.match(r"(?i)^(bra|jmp)\s+([A-Za-z_]\w*)\s*$", jline or "")
                    lt = self._find_label_line(mj.group(2), start, end) if mj else None
                    if mj and lt is not None and lt < idx:      # backward loop-back
                        cum += 2                                 # cond not-taken (in-loop)
                        sl.line_cost = 2
                        sl.cum_after = cum
                        pending_loopback = (mj.group(2), lt)
                        idx += 1
                        continue
            if pending_loopback is not None:
                mJ = re.match(r"(?i)^(bra|jmp)\s+([A-Za-z_]\w*)\s*$", stripped)
                if mJ:
                    loop_lbl = pending_loopback[0]
                    pending_loopback = None
                    cum += 3                                     # JMP/BRA cost
                    sl.line_cost = 3
                    sl.cum_after = cum
                    if loop_lbl in self.label_cum:
                        iter_len = cum - self.label_cum[loop_lbl]
                        self._report_loop(loop_lbl, iter_len, sl.lineno)
                    pending_adjust = -2   # exit: skip JMP (-3), cond taken vs not-taken (+1)
                    idx += 1
                    continue

            # statements separated by ':' (quote-aware)
            raw_stmts = split_statements(code)
            for raw_stmt in raw_stmts:
                st = raw_stmt.strip()
                if st == "" or st in ("{", "}", "\\{", "\\}"):
                    continue   # anonymous-block delimiters: zero cost
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

                # JSR to a known/local routine: charge the whole call (JSR + body
                # + RTS), following local straight-line subroutines at the current
                # cum so their stretched accesses are phase-accurate. Unknown
                # routines fall through to the flat 6c default below.
                if mnem == "jsr":
                    msub = re.match(r"^([A-Za-z_]\w*)", operand)
                    cc = self._call_cost(msub.group(1), cum) if msub else None
                    if cc is not None:
                        cost, note = cc
                        sl.has_instr = True
                        cum += cost
                        pc += 3
                        sl.line_cost += cost
                        continue

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
                if note.startswith("stretched(+1)"):
                    sl.odd_stretch = True

                # Branch accounting: the per-line cost above is the TAKEN cost
                # (convention).  For a backward branch that forms a loop, check
                # the iteration length using the taken cum, then back out 1c so
                # the linear walk continues on the not-taken (fall-through) path.
                if mnem in BRANCHES:
                    tgt = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)", operand.strip())
                    lbl = tgt.group(1) if tgt else None
                    if lbl in self.label_cum and self.label_cum[lbl] <= cum:
                        iter_len = cum - self.label_cum[lbl]
                        self._report_loop(lbl, iter_len, sl.lineno)
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
            idx += 1

        if pending_adjust:
            cum += pending_adjust
        self.total_cum = cum
        self.src_lines = src_lines
        self.func_range = (start, end)
        self._post_checks()
        return src_lines

    def _find_label_line(self, name, lo, hi):
        """Index of the line defining `.name` within [lo, hi), or None."""
        for i in range(lo, hi):
            if re.match(r"^\.%s\b" % re.escape(name), self.lines[i].strip()):
                return i
        return None

    def _call_cost(self, label, cum, depth=0):
        """Total cost of `JSR label`: the 6c JSR + the subroutine body + its RTS.

        Resolution order: a configured fixed cost (subroutine_cycles) wins;
        otherwise the local label is inline-walked from `cum+6` so stretched
        accesses inside it are phase-accurate. Returns (cost, note) or None if
        the routine can't be resolved (caller then uses the flat 6c default)."""
        if label in self.subroutine_cycles:
            c = self.subroutine_cycles[label]
            return c, f"call {label} ({c}c, configured)"
        li = self._find_label_line(label, 0, len(self.lines))
        if li is None:
            return None
        body, ok = self._walk_subroutine(li + 1, cum + 6, depth, label)
        if not ok:
            return None
        return 6 + body, f"call {label} ({6 + body}c, inlined)"

    def _record_sub_line(self, idx, line_cost, odd_stretch, has_instr, label):
        """Record per-line cost for an inlined subroutine body line (1-based idx+1),
        so rewrite() can annotate it. If the same line is reached at a different
        cost (subroutine called from two phases), flag a conflict and keep the
        first recording."""
        ln = idx + 1
        prev = self.sub_lines.get(ln)
        if prev is None:
            sl = SrcLine(ln, self.lines[idx])
            sl.line_cost = line_cost
            sl.odd_stretch = odd_stretch
            sl.has_instr = has_instr
            self.sub_lines[ln] = sl
        elif prev.line_cost != line_cost or prev.odd_stretch != odd_stretch:
            self.sub_phase_conflict.add(label)

    def _walk_subroutine(self, start_idx, cum, depth=0, label=None):
        """Walk a straight-line subroutine body, summing cycle cost (incl. the
        terminating RTS) from starting cum `cum`. Handles FOR/NEXT replay, stretch
        phase, and nested JSRs (recursively). Records per-line costs (for
        annotation) keyed by source line. Returns (cost, ok); ok=False if the
        body contains control flow we don't model (branch/JMP) or is malformed."""
        if depth > 6:
            return 0, False
        total = 0
        for_stack = []
        idx = start_idx
        guard = 0
        while idx < len(self.lines):
            guard += 1
            if guard > 5000:
                return total, False
            code = split_comment(self.lines[idx])[0]
            stripped = code.strip()
            mFor = re.match(r"(?i)^FOR\s+\w+\s*,(.+)$", stripped)
            if mFor and ":" not in code:
                for_stack.append([idx + 1, self._for_iter_count(mFor.group(1))])
                idx += 1
                continue
            if re.match(r"(?i)^NEXT\b", stripped) and ":" not in code and for_stack:
                fr = for_stack[-1]
                fr[1] -= 1
                if fr[1] > 0:
                    idx = fr[0]
                else:
                    for_stack.pop()
                    idx += 1
                continue
            line_cost = 0
            line_odd = False
            line_has_instr = False
            done = None             # set to (total, ok) when an RTS/control-flow ends the body
            for st in split_statements(code):
                st = st.strip()
                if st == "" or st in ("{", "}", "\\{", "\\}"):
                    continue
                if st.startswith("."):
                    ml = re.match(r"^\.[A-Za-z_]\w*", st)
                    st = st[ml.end():].strip() if ml else ""
                    if st == "":
                        continue
                if re.match(r"(?i)^(IF|ELIF|ELSE|ENDIF|ERROR|PRINT|ALIGN|EQU[BWDS]"
                            r"|SKIP|MACRO|ENDMACRO|FOR|NEXT|ORG|GUARD)\b", st):
                    continue
                mIns = re.match(r"^([A-Za-z]{3})\b(.*)$", st)
                if not mIns:
                    return total, False
                mnem = mIns.group(1).lower()
                operand = mIns.group(2).strip()
                if mnem in ("rts", "rti"):
                    line_cost += 6
                    line_has_instr = True
                    total += 6
                    done = (total, True)
                    break
                if mnem in BRANCHES or mnem == "jmp":
                    return total, False
                if mnem == "jsr":
                    ms = re.match(r"^([A-Za-z_]\w*)", operand)
                    sc = self._call_cost(ms.group(1), cum, depth + 1) if ms else None
                    if sc is None:
                        return total, False
                    line_cost += sc[0]
                    line_has_instr = True
                    total += sc[0]
                    cum += sc[0]
                    continue
                try:
                    mode, base, addr = classify(mnem, operand, self.symbols, self.zp_symbols)
                except CostError:
                    return total, False
                cost, note, _ = self._cost_with_stretch(mnem, mode, base, addr, operand, cum, 0)
                line_cost += cost
                line_has_instr = True
                if note.startswith("stretched(+1)"):
                    line_odd = True
                total += cost
                cum += cost
            if line_has_instr:
                self._record_sub_line(idx, line_cost, line_odd, True, label)
            if done is not None:
                return done
            idx += 1
        return total, False

    def _for_iter_count(self, rest):
        """Iteration count of `FOR var,a,b[,c]` from the part after the var."""
        parts = [p.strip() for p in rest.split(",")]
        try:
            a = eval_expr(parts[0], self.symbols)
            b = eval_expr(parts[1], self.symbols)
            c = eval_expr(parts[2], self.symbols) if len(parts) > 2 else 1
        except (CostError, IndexError):
            return 1
        if c == 0:
            return 1
        return max(0, (b - a) // c + 1)

    def detect_trip_count(self, loop):
        """Best-effort loop trip count. Handles two patterns:
          1. explicit compare:  ldx #INIT ... inx/dex ... cpx #CMP : bne
          2. decrement-to-zero:  (lda #N:sta MEM | ldx #N) ... dec MEM/dex : bne
        Returns int trips or None."""
        start, end = self.func_range
        loop_line = next((i for i in range(start, end)
                          if re.match(r"^\.%s\b" % re.escape(loop["label"]),
                                      self.lines[i].strip())), None)
        if loop_line is None:
            return None
        branch_idx = loop["lineno"] - 1     # lineno is 1-based; self.lines is 0-based
        body = range(loop_line, branch_idx + 1)

        def stmts(i):
            return [s.strip() for s in split_statements(split_comment(self.lines[i])[0])]

        reg = cmp_val = step = None
        dec_counts = {}         # counter ('x'/'y' or memory) -> decrements per iter
        has_exit_cond = False   # a beq/bne somewhere in the body (the exit test)
        for i in body:
            for st in stmts(i):
                m = re.match(r"(?i)^(cpx|cpy)\b\s*#(.+)$", st)
                if m:
                    reg = m.group(1).lower()[-1]
                    try:
                        cmp_val = eval_expr(m.group(2), self.symbols)
                    except CostError:
                        cmp_val = None
                for mn, s in (("inx", ("x", +1)), ("iny", ("y", +1)),
                              ("dex", ("x", -1)), ("dey", ("y", -1))):
                    if re.match(r"(?i)^%s\b" % mn, st):
                        step = s
                        if s[1] == -1:
                            dec_counts["x" if mn == "dex" else "y"] = \
                                dec_counts.get("x" if mn == "dex" else "y", 0) + 1
                md = re.match(r"(?i)^dec\s+([A-Za-z_]\w*)", st)
                if md:
                    dec_counts[md.group(1)] = dec_counts.get(md.group(1), 0) + 1
                if re.match(r"(?i)^(beq|bne)\b", st):
                    has_exit_cond = True

        # pattern 1: explicit compare
        if reg is not None and cmp_val is not None and step is not None:
            init = self._find_imm_init(start, loop_line, "ld%s" % reg)
            if init is not None:
                return (cmp_val - init) if step[1] == +1 else (init - cmp_val)

        # pattern 2: decrement-to-zero. trips = initial counter value / decrements
        # per iteration (the loop may be unrolled and decrement more than once).
        if dec_counts and has_exit_cond:
            counter = max(dec_counts, key=dec_counts.get)
            ndecs = dec_counts[counter]
            if counter in ("x", "y"):
                init = self._find_imm_init(start, loop_line, "ld%s" % counter)
            else:
                init = self._find_mem_init(start, loop_line, counter)
            if init is not None and ndecs > 0:
                return init // ndecs
        return None

    def _find_imm_init(self, lo, hi, mnem):
        """Last `<mnem> #N` immediate load before line hi -> N."""
        init = None
        for i in range(lo, hi):
            for st in split_statements(split_comment(self.lines[i])[0]):
                m = re.match(r"(?i)^%s\b\s*#(.+)$" % mnem, st.strip())
                if m:
                    try:
                        init = eval_expr(m.group(1), self.symbols)
                    except CostError:
                        pass
        return init

    def _find_mem_init(self, lo, hi, mem):
        """Last `lda #N ... sta MEM` (or `stz MEM`) before line hi -> N.
        The lda may be on an earlier line than the sta, so track across lines."""
        init = None
        last_imm = None
        for i in range(lo, hi):
            for st in split_statements(split_comment(self.lines[i])[0]):
                st = st.strip()
                m = re.match(r"(?i)^lda\s*#(.+)$", st)
                if m:
                    try:
                        last_imm = eval_expr(m.group(1), self.symbols)
                    except CostError:
                        last_imm = None
                if re.match(r"(?i)^stz\s+%s\b" % re.escape(mem), st):
                    init = 0
                elif re.match(r"(?i)^sta\s+%s\b" % re.escape(mem), st) and last_imm is not None:
                    init = last_imm
        return init

    # mnemonics whose indexed/indirect-Y READ costs +1c on a page cross
    PAGECROSS_READS = {"lda", "ldx", "ldy", "cmp", "cpx", "cpy",
                       "adc", "sbc", "and", "ora", "eor", "bit"}

    def _check_page_cross(self, mnem, mode, operand, sl):
        """Indexed reads (abs,X / abs,Y / (zp),Y) cost +1c on a page cross.
        abs,X/Y into a table is a static, fixable concern (page-align the table).
        (zp),Y depends on the runtime pointer+Y, so it's a soft call-out: it only
        breaks cycle-exactness for RVI CRTC writes, not for vertical-rupture
        effects whose register writes just need to land within the scanline."""
        if mnem not in self.PAGECROSS_READS:
            return
        if mode == "izy":
            sl.izy_pagecross = True
            sl.flags.append(("INFO",
                f"{mnem} {operand}: (zp),Y may cross a page (+1c, runtime-dependent). "
                "Fine for vertical-rupture (no cycle-exact CRTC writes); verify if "
                "this is on a cycle-exact RVI path."))
            return
        if mode not in ("abx", "aby"):
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

# Marker noting a stretched access that cost only +1c (began on an odd cycle, so
# the usual +2 stretch was reduced to +1). Phase-sensitive - worth calling out.
ODD_MARK = " (odd stretch +1)"
ODD_MARK_RE = re.compile(r"\s*\(odd stretch \+1\)")


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
        if sl.odd_stretch:
            mark += "  [odd stretch +1]"
        if ann is not None and ann != sl.line_cost:
            mark += f" <-- annotated {ann}c, true {sl.line_cost}c (will fix; barriers unaffected)"
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
    if an.sub_lines:
        out.append("")
        out.append("## Inlined subroutine per-line costs (phase = actual call site)")
        for ln in sorted(an.sub_lines):
            sl = an.sub_lines[ln]
            ann = existing_perline(sl.comment)
            mark = "  [odd stretch +1]" if sl.odd_stretch else ""
            if ann is not None and ann != sl.line_cost:
                mark += f" <-- annotated {ann}c, true {sl.line_cost}c"
            out.append(f"  line {ln:>4}:  {sl.line_cost:>3}c  {sl.code.strip()}{mark}")
        if an.sub_phase_conflict:
            out.append(f"  NOTE: {', '.join(sorted(an.sub_phase_conflict))} called at "
                       ">1 phase; per-line costs vary by call site (annotation uses the first).")
    return "\n".join(out)


XPAGE_MARK = "  [xpage] may cross page +1c"
XPAGE_MARK_RE = re.compile(r"\s*\[xpage\][^\n]*")


def rewrite(an, scanline, annotate_missing=False, add_running_totals=False,
            note_page_cross=False, vann=None):
    """Return new full-file text with updated per-line and running comments.

    Rules (conservative - only touch numbers, never prose):
      * a `<== Nc` running-total marker -> updated to the computed cum.
      * a `; Nc` per-line cost number   -> updated to the computed line cost.
      * a code line with cost > 0 and NO comment at all (annotate_missing) -> `; Nc`.
      * a blank line after a code block (add_running_totals) -> insert `\\\\ <== Nc`.
      * an (zp),Y page-cross read (note_page_cross) -> append a `[xpage]` note.
    Prose comments without a number are left untouched.
    """
    lines = list(an.lines)
    # function body lines plus any inlined-subroutine body lines (the latter get
    # per-line `; Nc` cost annotations too, but no running totals).
    by_lineno = {sl.lineno: sl for sl in an.src_lines}
    for ln, sl in an.sub_lines.items():
        by_lineno.setdefault(ln, sl)
    for lineno, sl in by_lineno.items():
        raw = lines[lineno - 1]
        code, comment, idx = split_comment(raw)
        if RUNNING_RE.search(comment):
            # A `<== 128c/0c` marker on a line whose cum is NOT on a boundary is a
            # mid-block "wrap" marker (the count just wrapped past 128) -> leave it.
            is_wrap = (re.search(r"<==\s*%dc\s*/\s*0c" % scanline, comment)
                       and sl.cum_after % scanline != 0)
            if not is_wrap:
                new_comment = RUNNING_RE.sub("<== " + render_running(sl.cum_after, scanline), comment)
                lines[lineno - 1] = raw[:idx] + new_comment
        elif PERLINE_RE.search(comment):
            if sl.line_cost > 0:
                # strip any stale odd-stretch marker first (idempotent), then
                # re-insert it right after the count if still applicable.
                stripped = XPAGE_MARK_RE.sub("", ODD_MARK_RE.sub("", comment))
                repl = f"; {sl.line_cost}c" + (ODD_MARK if sl.odd_stretch else "")
                new_comment = PERLINE_RE.sub(repl, stripped, count=1)
                if note_page_cross and sl.izy_pagecross:
                    new_comment = new_comment.rstrip() + XPAGE_MARK
                lines[lineno - 1] = raw[:idx] + new_comment
        elif annotate_missing and sl.has_instr and not sl.is_wait and sl.line_cost > 0:
            mark = ODD_MARK if sl.odd_stretch else ""
            extra = XPAGE_MARK if (note_page_cross and sl.izy_pagecross) else ""
            if comment == "":
                lines[lineno - 1] = code.rstrip() + "\t\t; " + f"{sl.line_cost}c" + mark + extra
            else:
                # existing `;` PROSE comment with no `; Nc` cost: insert the cost
                # right after the `;` -> `; Nc <prose>` (normalised spacing so the
                # update path is idempotent). `\\`-style comments are left alone.
                m = re.match(r"^;\s*(.*)$", comment)
                if m:
                    new_comment = ("; " + f"{sl.line_cost}c" + mark + extra
                                   + " " + m.group(1)).rstrip()
                    lines[lineno - 1] = raw[:idx] + new_comment

    # Vertical [vert] markers are length-preserving, so apply them here (before
    # any line insertion below) using the original line numbers.
    if vann:
        apply_vertical_annotations(lines, vann)

    # Running-total insertions, keyed by "insert this text BEFORE line N".
    inserts = {}

    def already_marker(lineno):
        return 1 <= lineno <= len(lines) and RUNNING_RE.search(split_comment(lines[lineno - 1])[1])

    wrap_lines = set()

    def add_insert(lineno, cum, force_boundary=False):
        if already_marker(lineno):
            return                       # idempotent: a marker is already here
        lst = inserts.setdefault(lineno, [])
        if force_boundary:
            # a scanline-wrap marker supersedes a plain block-end total at the
            # same spot (it carries the same info plus the boundary crossing).
            wrap_lines.add(lineno)
            lst[:] = [t for t in lst if "/" in t]   # drop plain block-end totals
            text = "\t\\\\ <== " + render_running(scanline, scanline)
        else:
            if lineno in wrap_lines:
                return                   # a wrap marker already covers this line
            text = "\t\\\\ <== " + render_running(cum, scanline)
        if text not in lst:
            lst.append(text)

    if add_running_totals:
        by_lineno_sl = {sl.lineno: sl for sl in an.src_lines}
        # (a) end of each code block: before the blank line that follows code
        prev_code = None
        for sl in an.src_lines:
            code, comment, _ = split_comment(lines[sl.lineno - 1])
            if code.strip() == "" and comment.strip() == "":      # blank
                if prev_code is not None:
                    add_insert(sl.lineno, prev_code.cum_after)
                    prev_code = None
            elif code.strip():
                prev_code = sl if (sl.has_instr or sl.line_cost > 0) else None
            elif comment.strip():
                prev_code = None
        # (b) where the running count wraps 128c/0c mid-block: after the crossing
        #     line, with no surrounding blank.
        for sl in an.src_lines:
            if (sl.cum_before is not None
                    and sl.cum_after // scanline > sl.cum_before // scanline):
                add_insert(sl.lineno + 1, sl.cum_after, force_boundary=True)
        # (c) start and end of every loop
        for loop in an.loops:
            li = an._find_label_line(loop["label"], *an.func_range)
            if li is not None and (li + 1) in by_lineno_sl:
                add_insert(li + 2, by_lineno_sl[li + 1].cum_after)        # after label
            bsl = by_lineno_sl.get(loop["lineno"])
            if bsl is not None:
                add_insert(loop["lineno"] + 1, bsl.cum_after)             # after branch

    out = []
    for i, line in enumerate(lines):
        for t in inserts.get(i + 1, []):
            out.append(t)
        out.append(line)
    for t in inserts.get(len(lines) + 1, []):
        out.append(t)
    return "\n".join(out) + "\n"


# ----------------------------------------------------------------------------

VERT_MARK_RE = re.compile(r"\s*(?:\\\\ )?\[vert\][^\n]*$")

def apply_vertical_annotations(lines, ann):
    """Add idempotent `\\\\ [vert] ...` markers to the given line numbers, in
    place on the `lines` list (length-preserving). Only annotates lines with no
    existing `;`/`<==` comment (so we never clobber horizontal cost comments);
    other target lines are left to the report."""
    for lineno, note in ann.items():
        if lineno < 1 or lineno > len(lines):
            continue
        raw = VERT_MARK_RE.sub("", lines[lineno - 1])
        code, comment, idx = split_comment(raw)
        if comment.strip() == "":
            # comment-free line: add a standalone [vert] comment
            lines[lineno - 1] = code.rstrip() + "\t\t\\\\ [vert] " + note
        elif RUNNING_RE.search(comment):
            # a `<== ...0c` scanline-boundary marker: append alongside it
            lines[lineno - 1] = raw.rstrip() + "  [vert] " + note
        # else: a real cost/prose comment -> leave it (covered by the report)
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True, help="JSON config for the effect")
    ap.add_argument("--file", help="override source file from config")
    ap.add_argument("--write", action="store_true", help="rewrite comments in place")
    ap.add_argument("--out", help="write rewritten file here instead of in place (for diffing)")
    ap.add_argument("--annotate-missing", action="store_true",
                    help="also ADD a ; Nc cost comment to instruction lines that have none")
    ap.add_argument("--add-running-totals", action="store_true",
                    help="insert a \\\\ <== Nc running total on blank lines after code blocks")
    ap.add_argument("--note-page-cross", action="store_true",
                    help="append a [xpage] note to (zp),Y reads that may cross a page")
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

    vann = {}
    if cfg.get("vertical"):
        from crtc_vertical import analyse_vertical
        vF, vann, vS = analyse_vertical(an, cfg["vertical"])
        print("\n## Vertical (PAL frame) structure")
        for line in vS:
            print(f"  {line}")
        print("\n## Vertical validation")
        for sev, msg in vF:
            print(f"  [{sev}] {msg}")

    if args.write or args.out:
        newtext = rewrite(an, an.scanline, annotate_missing=args.annotate_missing,
                          add_running_totals=args.add_running_totals,
                          note_page_cross=args.note_page_cross, vann=vann)
        target = Path(args.out) if args.out else src_path
        target.write_text(newtext)
        print(f"\n[written] {target}")


if __name__ == "__main__":
    main()
