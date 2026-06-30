"""
crtc_vertical.py -- vertical (PAL-frame) correctness check for RVI draw routines.

Builds on the horizontal Analyser (rvi_cycles.py). A non-interlaced PAL frame is
312 raster lines and must contain exactly one vsync pulse, in a stable position
(typically PAL line 272 = R7 34*8, or 280 = 35*8).

Model (see SKILL.md for the long form):
  * Each executed 128c scanline = one PAL line of real time (the horizontal pass
    guarantees 128c/line).  So PAL lines emitted by the function =
    real_function_cum / 128, where the loop body is replayed `trips` times.
  * During the rupture loop, R7 is parked out of reach (e.g. 255), so vsync
    CANNOT fire there -- the data-dependent per-line R9 is therefore irrelevant
    to vsync/line-total correctness.
  * The vsync and the frame total are fixed by the data-independent tail: after
    the loop the fixup restores a normal CRTC frame (R0 full width, R4/R9/R7/R5),
    which free-runs after RTS.  Tail frame = (R4+1)*(R9+1)+R5 lines, vsync at
    row R7 -> PAL line tail_start + R7*(R9+1).

CRTC facts applied (crtc-6845-advanced wiki):
  * Last-Line (C9==R9 AND C4==R4) is evaluated only while C0<2; late R4/R9 writes
    don't change that scanline's verdict (the "1 line over" hazard).
  * R0=1 micro-scanlines are too short to commit the verdict -> a dummy scanline.
  * Vsync fires when C4==R7; if R7 is unreachable, no vsync that frame.

What this version checks: frame line total == 312, exactly one vsync at the
expected PAL line, the tail frame closing the frame (fixed point), rupture
sanity (R7 unreachable / R4<R7 during the loop), and a visible-line estimate.
Exact char-level dummy-scanline accounting and per-line address (R12/R13)
correctness are deferred (documented in SKILL.md).
"""

import re


def build_effect_summary(an, vcfg):
    """Return a short (~5-line) human summary of the effect for a header block at
    the top of the draw function: main components (rupture / RVI, scanlines per
    row, rows), a one-line gloss of setup / loop / fixup, and any gotchas the
    reader should know (cycle-aligned branches, cycle drift, page crossings).

    Auto-derived from the analysis; keep it terse. Returns a list of body lines
    (no comment markers)."""
    from rvi_cycles import split_comment, split_statements
    import re as _re

    scan = an.scanline
    frame_lines = vcfg.get("frame_lines", 312)
    if not an.loops:
        return ["EFFECT : no rupture loop detected -- summary unavailable"]

    loop = max(an.loops, key=lambda L: L["iter_len"])
    iter_len = loop["iter_len"]
    lines_each = iter_len // scan
    loop_start_cum = loop["label_cum"] - an.entry_phase
    trips = vcfg.get("loop_iterations") or an.detect_trip_count(loop) or 0

    # registers written in setup (<= loop start) vs fixup (> loop end)
    def regset(pred):
        return sorted({rw["reg"] for rw in an.reg_writes
                       if rw["reg"] is not None and pred(rw["cum"])})
    setup_regs = regset(lambda c: c <= loop_start_cum)
    fixup_regs = regset(lambda c: c > loop_start_cum + iter_len)

    # R9 in force during the loop -> scanlines per row
    loop_R9 = 0
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 9 and rw["cum"] <= loop_start_cum and rw["val"] is not None:
            loop_R9 = rw["val"]
    spr = loop_R9 + 1
    rows_per_iter = max(1, lines_each // spr)
    rows = trips * rows_per_iter
    total_loop_lines = trips * lines_each

    # final tail frame regs
    final = {}
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] is not None:
            final[rw["reg"]] = rw["val"]

    # palette "copper": repeated writes to the ULA palette (&FE20-3F) per row,
    # in the function body or any inlined subroutine.
    s, e = an.func_range
    pal_writes = 0
    scan_src = [an.lines[i] for i in range(s, e)] + [sl.code for sl in an.sub_lines.values()]
    for ln in scan_src:
        for st in split_statements(split_comment(ln)[0]):
            if _re.search(r"(?i)\bst[az]\s+&fe2[0-9a-f]\b", st):
                pal_writes += 1

    kind = "Vertical Rupture" if an.soft_window else "Vertical Rupture + horizontal RVI"
    if pal_writes >= 4:
        kind += f" + per-row ULA palette ({pal_writes}x &FE2x copper)"
    rvi = "no per-scanline CRTC writes" if an.soft_window else "per-scanline R0 (cycle-exact)"
    vsync = vcfg.get("target_vsync_pal_line")
    vtxt = f", vsync PAL {vsync}" if vsync is not None else ""

    setup_lines = loop_start_cum / scan
    fixup_cum = (an.total_cum - an.entry_phase) - (loop_start_cum + iter_len)
    fixup_lines = fixup_cum / scan

    # JSR calls inside the loop body (for the LOOP gloss)
    lbl_line = an._find_label_line(loop["label"], s, e)
    jsrs = []
    if lbl_line is not None:
        for i in range(lbl_line, loop["lineno"]):
            for st in split_statements(split_comment(an.lines[i])[0]):
                m = _re.match(r"(?i)^jsr\s+([A-Za-z_]\w*)", st.strip())
                if m:
                    jsrs.append(m.group(1))
    jcount = {}
    for j in jsrs:
        jcount[j] = jcount.get(j, 0) + 1
    jtxt = ", ".join((f"{c}x JSR {n}" if c > 1 else f"JSR {n}") for n, c in jcount.items())
    loop_calls = f" -- calls {jtxt}" if jtxt else " -- straight-line"

    unroll = f", {rows_per_iter} rows/iter (unrolled)" if rows_per_iter > 1 else ""

    def rlist(rs):
        return "/".join(f"R{r}" for r in rs) if rs else "none"

    out = []
    out.append(f"EFFECT : {kind} -- {spr} scanlines/row x {rows} rows "
               f"({total_loop_lines} lines){unroll}; PAL {frame_lines}{vtxt}; {rvi}")
    out.append(f"SETUP  : ~{setup_lines:.1f} lines -- rupture CRTC regs {rlist(setup_regs)} "
               "set, padded to the scanline boundary")
    out.append(f"LOOP   : {trips}x @ {iter_len}c ({lines_each} line/iter){loop_calls}")
    out.append(f"FIXUP  : ~{fixup_lines:.1f} lines -- tail CRTC frame {rlist(fixup_regs)} "
               "restored, RTS; free-runs to the frame boundary")

    # --- gotchas -------------------------------------------------------------
    gotchas = []
    for sev, msg in an.findings:
        if sev == "ERROR" and "UNBALANCED" in msg:
            gotchas.append("UNBALANCED branch -- scanline timing varies (see report)")
        elif sev == "OK" and "balanced branch" in msg:
            mm = _re.search(r"both paths (\d+)c", msg)
            gotchas.append(f"balanced branch ({mm.group(1)}c/path)" if mm else
                           "balanced branch")
        elif sev == "WARN" and "drift" in msg:
            mm = _re.search(r"=\s*(\d+)c\s*=\s*(\d+) scanlines ([+-]\d+)c", msg)
            if mm:
                gotchas.append(f"loop {mm.group(1)}c = {mm.group(2)} scanlines {mm.group(3)}c "
                               "-> CRTC address writes drift each row (soft window, tolerable)")
            else:
                gotchas.append("loop length not an exact scanline multiple -> cycle drift")
    if any(sl.izy_pagecross for sl in an.src_lines):
        gotchas.append("(zp),Y read in the loop may cross a page (+1c); fine for a "
                       "soft-window rupture, not for cycle-exact RVI")
    if not an.soft_window:
        gotchas.append("per-scanline CRTC writes are cycle-exact -- keep the loop body "
                       "timing exact (see per-line totals)")
    if gotchas:
        out.append("GOTCHA : " + gotchas[0])
        out.extend("         " + g for g in gotchas[1:])
    else:
        out.append("GOTCHA : none -- timing is robust (stretch re-sync absorbs +/-1c)")
    return out


def _final_registers(reg_writes):
    """Last written value of each CRTC register, in cum order."""
    final = {}
    for rw in sorted(reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] is not None:
            final[rw["reg"]] = rw["val"]
    return final


def _first_unreachable_r7(reg_writes):
    """Was R7 ever parked out of reach (large) during the routine?"""
    for rw in reg_writes:
        if rw["reg"] == 7 and rw["val"] is not None and rw["val"] >= 250:
            return rw["val"]
    return None


def analyse_vertical(an, vcfg):
    """Return (findings, annotations, summary_lines, vbound).

    findings: list of (severity, message)
    annotations: dict lineno -> PAL marker comment string (no leading marker)
    vbound: data the rewriter needs to tag INSERTED scanline-boundary markers with
            the same `[vert] PAL line N` note used for pre-existing markers (so the
            first --write pass is already idempotent).
    """
    F = []          # findings
    ann = {}        # lineno -> "PAL line N" style note
    S = []          # summary lines
    vbound = {}     # {entry_pal, scan, loop_label_line, branch_line, extra}

    scan = an.scanline
    frame_lines = vcfg.get("frame_lines", 312)
    entry_pal = vcfg.get("entry_pal_line", -1)

    if not an.loops:
        F.append(("WARN", "no rupture loop detected; vertical check assumes a "
                  "setup + loop + fixup structure"))
        return F, ann, S, vbound
    loop = max(an.loops, key=lambda L: L["iter_len"])
    iter_len = loop["iter_len"]
    loop_lines_each = iter_len // scan

    trips = vcfg.get("loop_iterations")
    trip_src = "config"
    if trips is None:
        trips = an.detect_trip_count(loop)
        trip_src = "auto-detected"
    if trips is None:
        F.append(("ASK", "could not determine loop trip count; set "
                  "vertical.loop_iterations in the config"))
        return F, ann, S, vbound

    # --- line accounting -----------------------------------------------------
    loop_start_cum = loop["label_cum"] - an.entry_phase
    setup_lines = loop_start_cum / scan
    loop_lines = trips * loop_lines_each
    single_walk_cum = an.total_cum - an.entry_phase
    fixup_cum = single_walk_cum - (loop_start_cum + iter_len)
    real_function_cum = single_walk_cum + (trips - 1) * iter_len
    function_pal_lines = real_function_cum / scan
    free_run_lines = frame_lines - function_pal_lines

    S.append(f"entry PAL line       : {entry_pal}")
    S.append(f"setup                : {setup_lines:g} line(s)  ({loop_start_cum}c)")
    S.append(f"loop                 : {trips} x {loop_lines_each} = {loop_lines} line(s)  "
             f"(trip count {trip_src})")
    S.append(f"fixup (to RTS)       : {fixup_cum / scan:g} line(s)  ({fixup_cum}c)")
    S.append(f"function total       : {function_pal_lines:g} PAL line(s)")
    S.append(f"free-run after RTS   : {free_run_lines:g} line(s)")

    # --- tail normal frame & vsync ------------------------------------------
    final = _final_registers(an.reg_writes)
    R4 = final.get(4)
    R9 = final.get(9)
    R7 = final.get(7)
    R6 = final.get(6)
    R5 = final.get(5, vcfg.get("entry_R5", 0))
    R0 = final.get(0)
    S.append(f"final regs at RTS    : R0={R0} R4={R4} R5={R5} R6={R6} R7={R7} R9={R9}")

    if R4 is None or R9 is None or R7 is None:
        F.append(("WARN", "final R4/R9/R7 not all set in the routine; cannot model "
                  "the tail frame"))
        return F, ann, S, vbound

    tail_lines = (R4 + 1) * (R9 + 1) + R5
    S.append(f"tail normal frame    : (R4+1)*(R9+1)+R5 = ({R4}+1)*({R9}+1)+{R5} = {tail_lines} line(s)")

    # Tail frame begins at the last full-width R0 write (rupture ends there).
    # NOTE: the function enters at PAL line `entry_pal` (e.g. -1 = the previous
    # frame's last line). Cycle counts measure lines SINCE ENTRY; add entry_pal
    # to get frame-relative PAL line numbers (frame is lines 0..frame_lines-1).
    tail_start_write = None
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 0 and rw["val"] is not None and rw["val"] >= 95:
            if rw["cum"] > loop_start_cum + iter_len:   # in the fixup
                tail_start_write = rw
    if tail_start_write is not None:
        tail_start_cum = (tail_start_write["cum"] - an.entry_phase) + (trips - 1) * iter_len
        tail_start_pal = tail_start_cum / scan + entry_pal      # frame-relative
    else:
        tail_start_pal = frame_lines - tail_lines
    S.append(f"tail frame starts at : PAL line {tail_start_pal:g} "
             f"(entry at PAL line {entry_pal})")

    # --- validations ---------------------------------------------------------
    # 1. total lines
    total = tail_start_pal + tail_lines
    if abs(total - frame_lines) < 1e-6:
        F.append(("OK", f"frame total = {total:g} lines == {frame_lines}"))
    else:
        F.append(("ERROR", f"frame total = {total:g} lines, expected {frame_lines} "
                  f"(tail starts {tail_start_pal:g} + tail {tail_lines})"))

    # 2. fixed point: tail frame must end exactly at the frame boundary
    if abs((tail_start_pal + tail_lines) % frame_lines) > 1e-6:
        F.append(("ERROR", "tail frame does not end on the frame boundary; CRTC "
                  "state will not be consistent frame-to-frame (not a fixed point)"))

    # 3. exactly one vsync, reachable, at expected line
    parked = _first_unreachable_r7(an.reg_writes)
    if parked:
        F.append(("OK", f"R7 parked at {parked} during rupture -> vsync blocked in "
                  "the loop (no spurious vsync)"))
    if R7 > R4:
        F.append(("ERROR", f"final R7={R7} > R4={R4}: vsync row never reached in the "
                  "tail frame -> NO vsync this frame (invalid PAL signal)"))
    else:
        vsync_pal = tail_start_pal + R7 * (R9 + 1)
        target = vcfg.get("target_vsync_pal_line")
        msg = f"single vsync at PAL line {vsync_pal:g} (R7={R7}, row {R7} of tail)"
        if target is None:
            F.append(("OK", msg))
        elif abs(vsync_pal - target) < 1e-6:
            F.append(("OK", msg + f" == target {target}"))
        else:
            F.append(("ERROR", msg + f", but target is {target}"))
        S.append(f"vsync                : PAL line {vsync_pal:g}")
        # annotate the vsync line if it lands in the free-run we can't mark a
        # specific source line; note it in the summary only.

    # 4. rupture sanity: R4 during loop must be < R7-at-the-time (it ruptures
    #    before vsync). We know R4 was set small (e.g. 0) before the loop.
    loop_R4 = None
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 4 and rw["cum"] <= loop_start_cum:
            loop_R4 = rw["val"]
    if loop_R4 is not None:
        if parked and loop_R4 < parked:
            F.append(("OK", f"loop R4={loop_R4} < parked R7={parked}: frame ruptures "
                      "before vsync row (correct rupture)"))
        S.append(f"loop R4              : {loop_R4} (vertical total-1 during rupture)")

    # 5. visible lines (estimate). Displayed rows come from more than the loop:
    #    * The SETUP frame displays one row too. These rupture effects are
    #      pipelined -- the draw writes each row's R12/R13 one frame AHEAD (so a
    #      setup R12/R13 write relatches only for the loop's first row). The setup
    #      frame therefore shows the address latched by the previous *tick*
    #      (update fn always primes R12/R13) -> +1 displayed row the loop math
    #      misses. This holds whether or not the draw also writes R12/R13 in setup.
    #    * The FIXUP / tail relatch can add yet another displayed row depending on
    #      exactly how it rewrites R12/R13 -- not determinable from the draw alone.
    loop_R6 = None
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 6 and rw["cum"] <= loop_start_cum + iter_len:
            loop_R6 = rw["val"]
    visible = loop_lines if (loop_R6 and loop_R6 >= 1) else 0
    tail_visible = (R6 or 0) * (R9 + 1)

    setup_R6 = None
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 6 and rw["cum"] <= loop_start_cum:
            setup_R6 = rw["val"]
    row_lines = R9 + 1
    setup_visible = row_lines if (setup_R6 and setup_R6 >= 1) else 0
    total_visible = setup_visible + visible + tail_visible

    parts = []
    if setup_visible:
        parts.append(f"setup {setup_visible} (1 row from tick)")
    parts.append(f"loop {visible} @ R6={loop_R6}")
    parts.append(f"tail {tail_visible} @ R6={R6}")
    caveat = f"; fixup relatch may add +{row_lines} (1 row)" if setup_visible else ""
    exp_vis = vcfg.get("expected_visible_lines")
    vmsg = f"visible lines (est.) = {total_visible} ({' + '.join(parts)}){caveat}"
    if exp_vis is None:
        F.append(("INFO", vmsg))
    elif total_visible == exp_vis:
        F.append(("OK", vmsg + f" == expected {exp_vis}"))
    else:
        F.append(("WARN", vmsg + f", expected {exp_vis}"))

    # --- PAL-line annotations at section boundaries --------------------------
    start, end = an.func_range
    ann[start + 1] = f"enter PAL line {entry_pal}"
    # each iteration emits one full PAL line; the first displayed line is the
    # next line boundary after the (mid-line) loop label -> round up.
    loop_first = round(loop_start_cum / scan + entry_pal)
    loop_label_line = next((i + 1 for i in range(start, end)
                            if re.match(r"^\.%s\b" % re.escape(loop["label"]),
                                        an.lines[i].strip())), loop["lineno"])
    ann[loop_label_line] = (f"loop x{trips}: PAL lines {loop_first}.."
                            f"{loop_first + loop_lines - 1}")
    if tail_start_write is not None:
        ann[tail_start_write["lineno"]] = f"tail frame start @ PAL line {tail_start_pal:g}"
    if R7 is not None and R7 <= R4:
        r7_line = max((rw["lineno"] for rw in an.reg_writes if rw["reg"] == 7),
                      default=None)
        if r7_line:
            ann[r7_line] = f"R7={R7}: vsync @ PAL line {tail_start_pal + R7 * (R9 + 1):g}"

    # Mark the start of each new PAL scanline in the setup/fixup regions. These
    # are the `<== ...0c` running-total boundaries (cum hits a multiple of 128).
    # Inside the loop one source line stands for `trips` lines, so it's covered
    # by the loop-range annotation above and skipped here.
    branch_line = loop["lineno"]
    extra = (trips - 1) * iter_len
    # Same data the rewriter uses to tag INSERTED boundary markers identically.
    vbound.update(entry_pal=entry_pal, scan=scan,
                  loop_label_line=loop_label_line, branch_line=branch_line,
                  extra=extra)
    pal_points = {start + 1: entry_pal, loop_label_line: loop_first}
    for sl in an.src_lines:
        if loop_label_line <= sl.lineno <= branch_line:
            continue
        if sl.cum_after is None or sl.cum_after % scan != 0 or sl.cum_after == 0:
            continue
        if "<==" not in sl.comment:
            continue
        real_cum = sl.cum_after + (extra if sl.lineno > branch_line else 0)
        pal = real_cum // scan + entry_pal
        ann[sl.lineno] = f"PAL line {pal}"
        pal_points[sl.lineno] = pal

    # Catch stale hand-written "start of scanline N" prose: compare N against the
    # nearest computed PAL point.
    for sl in an.src_lines:
        m = re.search(r"(?i)start of scanline\s+(-?\d+)", sl.comment)
        if not m or not pal_points:
            continue
        claimed = int(m.group(1))
        near = min(pal_points, key=lambda L: abs(L - sl.lineno))
        if abs(near - sl.lineno) > 12:
            continue
        computed = pal_points[near]
        if claimed != computed:
            F.append(("WARN", f"stale comment (line {sl.lineno}): 'scanline {claimed}' "
                      f"but the computed PAL line here is {computed}"))
    return F, ann, S, vbound
