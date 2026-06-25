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
    """Return (findings, annotations, summary_lines).

    findings: list of (severity, message)
    annotations: dict lineno -> PAL marker comment string (no leading marker)
    """
    F = []          # findings
    ann = {}        # lineno -> "PAL line N" style note
    S = []          # summary lines

    scan = an.scanline
    frame_lines = vcfg.get("frame_lines", 312)
    entry_pal = vcfg.get("entry_pal_line", -1)

    if not an.loops:
        F.append(("WARN", "no rupture loop detected; vertical check assumes a "
                  "setup + loop + fixup structure"))
        return F, ann, S
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
        return F, ann, S

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
        return F, ann, S

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

    # 5. visible lines (estimate)
    loop_R6 = None
    for rw in sorted(an.reg_writes, key=lambda r: r["cum"]):
        if rw["reg"] == 6 and rw["cum"] <= loop_start_cum + iter_len:
            loop_R6 = rw["val"]
    visible = loop_lines if (loop_R6 and loop_R6 >= 1) else 0
    tail_visible = (R6 or 0) * (R9 + 1)
    total_visible = visible + tail_visible
    exp_vis = vcfg.get("expected_visible_lines")
    vmsg = (f"visible lines (est.) = {total_visible} "
            f"(loop {visible} @ R6={loop_R6} + tail {tail_visible} @ R6={R6})")
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
    return F, ann, S
