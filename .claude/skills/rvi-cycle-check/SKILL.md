---
name: rvi-cycle-check
description: >-
  Validate and re-annotate cycle-exact 6845 CRTC ("RVI") raster code in this BBC
  Master demo. Use when asked to check, validate, or update the cycle-count
  comments of an RVI draw routine (e.g. fx_draw_function), confirm the critical
  CRTC register writes land on their required cycle, check the 128c-per-scanline
  invariant, verify vertical/PAL-frame correctness (312 lines, single vsync at
  the right position, vertical rupture), or after editing such a routine.
---

# RVI cycle check

Static analyser + comment rewriter for the cycle-exact CRTC raster code used by
the RVI effects in this repo. It reproduces the hand cycle-counting, validates
the critical register writes, updates the `; Nc` per-line and `\\ <== Nc`
running-total comments, and checks **vertical / PAL-frame correctness** (312
lines, a single vsync in the right place, the vertical-rupture structure).

Two passes:
- **Horizontal** (`rvi_cycles.py`): per-scanline cycle timing — the 128c
  invariant, 1MHz stretch, critical R0 landing cycles, page-cross hazards.
- **Vertical** (`crtc_vertical.py`, runs when the config has a `vertical`
  block): the PAL frame — line total, vsync placement, rupture sanity, visible
  lines. See "Vertical check" below for its model and current limits.

## When to use

- "Check/validate the cycle counts in `fx_draw_function`."
- "Update the cycle comments after I changed the draw routine."
- "Did I break a critical CRTC register write / the 128c invariant?"
- "Is the frame still 312 lines / is vsync in the right place?"
- Proactively, right after editing an RVI draw routine.

## How to run

Report first (never edit silently):

```bash
python .claude/skills/rvi-cycle-check/rvi_cycles.py \
  --config .claude/skills/rvi-cycle-check/config/<effect>.json
```

Show the user the report (per-line table + invariants + register summary).
Then, to preview the exact edits as a diff before touching the file:

```bash
python .../rvi_cycles.py --config .../<effect>.json --out <scratchpad>/preview.asm
git --no-pager diff --no-index -- <source>.asm <scratchpad>/preview.asm
```

Only after the user confirms, apply in place:

```bash
python .../rvi_cycles.py --config .../<effect>.json --write
```

Write flags (all opt-in; default just updates existing numbers + adds `[vert]`):
- `--annotate-missing` — ADD `; Nc` to instruction lines that have no comment.
- `--add-running-totals` — insert `\\ <== Nc` running totals (for effects that
  don't already have them): before the blank line that closes each code block;
  at the **start and end of every loop**; and at each **128c/0c wrap** mid-block
  (a `\\ <== 128c/0c` line right after the crossing instruction, no surrounding
  blank). Idempotent — wrap markers are preserved, never re-numbered or doubled.
- `--note-page-cross` — append an `[xpage]` note to `(zp),Y` reads that may cross
  a page (see below).
- `--file` overrides the source path in the config.

## Per-effect config

`config/<effect>.json` (see `config/x-rotator.json`):

- `file`, `function` — source file and the routine to analyse.
- `end_label` — label that marks the end of the function (e.g. the next routine
  like `kefrens_kill`). If omitted, the analyser stops at the next
  `.fx_*_function`/`.fx_end` or the function's own top-level `RTS`/`JMP`.
- `entry_phase` — cumulative cycle at function entry. **0** = entered at the
  start of a scanline (VC=0 HC=0 SC=0), an even / 1 MHz boundary. Different
  effects can now align the CRTC/CPU clocks differently; if a routine is entered
  in another state it must be documented and set here.
- `scanline_cycles` — 128 (2 MHz, non-interlaced, 64 us line).
- `symbols` — values for assembler constants/symbols the analyser can't see
  (e.g. `SHORTEN_BY_ROWS`, `screen_base_addr`, and ZP bases like `locals_start`,
  `writeptr`). A symbol that resolves `< &100` makes operands that use it (incl.
  `foo = locals_start + N` defines) count as **zero-page**. Use this for effects
  that reference shared definitions from another file.
- `page_align_macros` — names of macros equivalent to `ALIGN &100` (e.g.
  `["PAGE_ALIGN"]`), so labels after them are detected as page-aligned.
- `register_constraints` — per-CRTC-register rules (see below).
- `origin` — optional absolute address of the function; enables branch
  page-cross detection. Null → branch page-cross detection is disabled (reported).
- `page_aligned_symbols` — tables asserted to be page-aligned (`&XX00`).
  Indexed reads into these are treated as safe (no page-cross penalty). The
  analyser also auto-detects any `.label` immediately preceded by `ALIGN &100`.
  List any table that is page-aligned only indirectly (e.g. it follows another
  256-byte table) — note this is an assertion: if you later change the table
  layout, update the list.

### register_constraints

Keyed by CRTC register number:

- `"exact_completion": [c0, c1, ...]` — the register VALUE write (`sta/stz
  &fe01`) must complete at one of these cumulative cycles (mod scanline).
  Used for **R0** (horizontal total) which must land on a CRTC character
  boundary. E.g. x-rotator: `[0, 96]`.
- `"min_value_for_hsync": N` — informational: R0 < hsync pos (R2) produces no
  hsync that segment (intended for the short 2-char rows).
- `"before_row_end": true` — soft window: must be set before the row ends, not
  at an exact cycle (R9 / R12 / R13 / R4 / R6 / R7).

If the analyser meets a CRTC register write with no constraint defined, it emits
an `[ASK]` finding — stop and ask the user what the constraint is, then add it
to the config. New effects abusing different registers will extend this list.

## The cycle model (what the script implements)

- **2 MHz CPU, 128 cycles per 64 us scanline**, non-interlaced. Scanline start
  = cumulative cycle 0 = a 1 MHz boundary (modelled as an even cycle).
- **1 MHz cycle stretching.** Accesses to stretched SHEILA peripherals complete
  on the next 1 MHz boundary with a minimum +1 stretch:
  `end = next_even(cum + base + 1); cost = end - cum`.
  - Stretched ranges: `&FC00-&FDFF` (FRED/JIM), `&FE00-&FE1F` (CRTC/ACIA/Serial),
    `&FE40-&FE7F` (System+User VIA), `&FEC0-&FEDF` (ADC).
  - **NOT stretched:** `&FE20-&FE3F` (Video ULA, ROMSEL, **ACCCON `&FE34`**),
    `&FE80+` (FDC, Econet, Tube), all RAM/ROM. So `sta &fe34` is a flat 4c.
  - Reference: `llm-beeb-wiki/wiki/timing/cycle-stretching.md`.
- **Odd-stretch marker.** A stretched access beginning on an odd cycle costs
  only **+1** instead of the usual +2 (the stretch is "reduced", 2->1). These
  are phase-sensitive, so the rewriter tags them with `(odd stretch +1)` right
  after the count (e.g. `stz &fe00 ; 5c (odd stretch +1)`). The marker is
  idempotent: it is removed automatically if a later edit makes the access +2.
- **Re-sync property (important).** Because a stretched write always finishes on
  an even boundary, a +/-1 error in the *non-stretched* code before it is often
  absorbed — the barrier doesn't move. So:
  - The **running totals at stretched CRTC writes** (and the R0 landing cycles)
    are the ground truth that matters for hardware.
  - Some hand `; Nc` per-line numbers are off by 1 (e.g. `sta abs,X` is 5c not
    4c; a stretched write from an odd start is 5c not 6c) yet the effect still
    works. The tool corrects the per-line number and tells you when a difference
    is **harmless** (absorbed; barriers still valid) vs **harmful** (a barrier
    lands on the wrong cycle → reported as `[ERROR]`).
- **Indexed-read page crossings.** `lda/cmp/adc/... abs,X`, `abs,Y` and
  `(zp),Y` reads cost **+1c on a page cross**, and the cross depends on the
  index — so a table that isn't page-aligned makes the timing **data-dependent**,
  which breaks cycle-exactness. The analyser warns for any such read whose table
  isn't provably page-aligned (`ALIGN &100` or `page_aligned_symbols`). Stores
  (`sta/stz abs,X/Y`) are a fixed 5c with no penalty.
- **Branches:** counted as **taken (3c)** for the per-line cost and loop-
  iteration check; a backward (loop) branch's fall-through exit is **not-taken
  (2c)**, so the code after the loop starts 1c earlier. **Page-boundary crossings
  are errors** (hard to reason about from source) — flagged when `origin` is set;
  if ever intentional, document it visibly at both branch and target.
- **`WAIT_CYCLES n`:** trusted as `n`. **Self-modified instructions:** counted
  at static cost.

## 65C02 base costs

Standard 65C02/65C12 timings (`sta abs,X` / `sta abs,Y` = 5c fixed; `lda abs,X`
4c +1 page-cross; `lda (zp),Y` 5c; RMW pays the stretch twice — flagged if it
hits a stretched address). The script tells zero-page from absolute operands by
scanning the source's `ORG <&100` region for ZP labels; add others via
`extra_zp_symbols`.

## Code structures handled

- **`FOR n,a,b[,c] … NEXT`** — the assembler unrolls these; the analyser replays
  the body the right number of times (so `FOR n,1,7,1 : NOP : NEXT` = 14c).
- **Balanced if/else "diamond"** — a forward conditional branch whose target is
  preceded by an unconditional `BRA/JMP` (e.g. `BCS right … BRA continue / .right
  … .continue`). The analyser walks one path, checks **both paths are equal
  cycles** (an `UNBALANCED` mismatch is an ERROR), and uses one cost — it does
  not double-count. Simple forward skips (no `BRA` before the target) are not
  treated as diamonds (still flagged as approximate).
- **Loop shapes** — backward conditional branch (`… : bne loop`), and the
  **loop-exit idiom** `Bcc EXIT / JMP|BRA LOOP / .EXIT` (a forward conditional
  exit + unconditional backward jump, e.g. `DEC c / BEQ done / JMP here / .done`).
- **Loop trip counts** — `ldx #N … inx/dex … cpx #M : bne`; decrement-to-zero
  loops (`lda #N : sta MEM … dec MEM …`), including loops **unrolled** so the
  counter is decremented more than once per iteration (trips = init / decs).
  Override with `vertical.loop_iterations` if auto-detection fails.
- **`{` / `}`** anonymous-block delimiters and `\{` / `\}` are zero-cost.
- **Decimal zero-page operands** (e.g. `BIT 0` = `BIT zp` 3c, not `BIT abs` 4c).

## Indexed-read page crossings

- **`abs,X` / `abs,Y` into a table** — a static, fixable concern: a page cross
  adds +1c and varies by index, breaking cycle-exactness. WARN unless the table
  is provably page-aligned (`ALIGN &100`, a `page_align_macros` macro, or
  `page_aligned_symbols`).
- **`(zp),Y`** — the cross depends on the runtime pointer+Y, so it's a soft INFO
  call-out, **not** an auto-corrected cost. It only breaks cycle-exactness on an
  RVI path with cycle-exact CRTC writes; for a **vertical-rupture** effect (no
  per-scanline CRTC writes, registers just need to land within the scanline) it's
  harmless. `--note-page-cross` adds an `[xpage]` comment in the source to record
  this. When the tool flags one, mention it and confirm with the user.

## Interpreting the report

- **Per-line table:** `cum` (running total mod scanline), `cost` (computed),
  `ann` (existing comment). A `<--` note means the hand number differs from the
  true cost; these are corrected on rewrite and (unless an `[ERROR]` says
  otherwise) are harmless phase differences.
- **Invariants & register writes:** `[OK]`/`[ERROR]` for loop = 128c and each R0
  landing; `[ASK]` for an undocumented register; `[ERROR]` for a bugged page
  guard (`IF HI(x) <> HI(x)`).

## Vertical check (PAL frame)

Runs when the config has a `vertical` block. A non-interlaced PAL frame is **312
lines** and must contain **exactly one vsync**, stable frame-to-frame (typically
PAL line 272 = R7 34×8, or 280 = 35×8).

**Model.** Each executed 128c scanline = one PAL line of real time (guaranteed by
the horizontal pass). The routine is **setup → rupture loop → fixup → free-run
after RTS**:
- The **rupture loop** sets `R4` small (vertical total < vsync) so the CRTC frame
  ends mid-TV-frame, relatching R12/R13 each line (vertical rupture). `R7` is
  parked out of reach (e.g. 255), so **vsync can't fire in the loop** — which is
  why the data-dependent per-line `R9` doesn't affect the line/vsync totals.
- The **tail** (data-independent) restores a normal CRTC frame: `tail_lines =
  (R4+1)*(R9+1) + R5`, vsync at row `R7` → PAL line `tail_start + R7*(R9+1)`.
- **Entry is at PAL line −1** (the previous frame's last line). Cycle counts are
  "lines since entry"; add `entry_pal_line` to get frame-relative numbers. (This
  −1 offset is why a naïve count comes out at 313/273 instead of 312/272.)

> **If the PAL line counts don't add up (total ≠ 312, vsync off by a constant),
> the FIRST thing to check is when the draw function is entered.** A wrong
> `entry_pal_line` shifts every frame-relative number by that constant. Entry is
> typically −1, 0, or −2 depending on how much CRTC setup time is needed before
> line 0. If the source doesn't document the entry scanline, **ask the user** —
> don't guess; set `entry_pal_line` from their answer.

**Checks:** frame total == `frame_lines` (312); exactly one vsync at
`target_vsync_pal_line`; tail frame closes on the frame boundary (fixed point);
rupture sanity (R7 parked / loop R4 < R7); visible-line estimate (R6); **stale
`start of scanline N` prose** (warns when a hand comment disagrees with the
computed PAL line — e.g. a comment written for a different `SHORTEN_BY_ROWS`).

**PAL-line annotations.** On `--write` the rewriter adds idempotent `[vert]`
markers: the function-entry and loop-label lines get a `\\ [vert] ...` comment,
and each new PAL scanline start in the setup/fixup is tagged on its `<== ...0c`
boundary line, e.g. `\\ <== 128c/0c  [vert] PAL line 247`. Inside the loop one
source line stands for `trips` lines, so the loop label carries the range.

**Config `vertical` block:** `entry_pal_line` (−1), `frame_lines` (312),
`target_vsync_pal_line` (272/280), `entry_R5` (0), `loop_iterations` (null →
auto-detect from the induction variable), `expected_visible_lines` (optional).

**CRTC facts applied** (`llm-beeb-wiki/.../crtc-6845-advanced.md`): the Last-Line
condition `C9==R9 AND C4==R4` is evaluated only while `C0<2`; late R4/R9 writes
don't change that scanline's verdict; R0=1 micro-scanlines are too short to
commit the verdict (extra dummy scanline). Vsync fires when `C4==R7`; if R7 is
unreachable there is no vsync that frame.

**Vertical limitations (current):** the rupture-loop *interior* is not simulated
char-by-char (per-line R9 is data-dependent) — it's modelled as N full PAL lines
with vsync blocked, which is sufficient for the line-total / vsync / fixed-point
checks but **not** for verifying per-line R12/R13 *address* selection or exact
intra-line CRTC scanline emission. The tail uses CRTC row math, not a full
char-level Last-Line/dummy-scanline simulation. For effects with **no R0 writes**
(pure vertical rupture, e.g. kefrens) there's no R0 tail anchor, so the tail
start uses a `frame_lines − tail_lines` fallback — the **vsync-position** check
is the stronger guard there. In-source `\\ [vert]` PAL-line annotations are added
only to comment-free lines; the full breakdown is in the report.

## Effects validated

- **x-rotator** (`fdload_dfs`, BeebAsm) — horizontal RVI + per-line rupture,
  entry at PAL line −1. Frame 312, vsync 272.
- **kefrens** (`just-rasters`, BeebAsm) — pure vertical rupture (R9=0/R4=0, no
  horizontal RVI), entry at PAL line 0, memory-counter loop, balanced left/right
  bar branches. Frame 312, vsync 280. The canonical "311-line rebalance" case.
- **twister** (`just-rasters`, BeebAsm) — vertical rupture, entry at PAL line 0,
  shadow/main RAM toggle via `&FE34` (ACCCON, not stretched), **2×-unrolled loop**
  with a `BEQ done / JMP here` tail (127×2 = 254 lines). Frame 312, vsync 280.

## Known limitations / not yet done

- Per-line R12/R13 address-selection correctness and full char-level CRTC
  scanline emission (dummy-scanline / C0<2 modelling) — the vertical check covers
  line-total / vsync / fixed-point, not address or exact emission.
- Page-cross detection needs `origin`; otherwise reported as disabled.
- BeebAsm-subset parser (the constructs used by the draw routines), not a full
  assembler. RMW-to-stretched-address is flagged rather than fully modelled;
  forward conditional branches are only handled as balanced diamonds (with a
  `BRA/JMP` before the target) — other shapes are flagged as approximate.
- For pure-vertical-rupture effects the no-R0 tail anchor uses a fallback (see
  Vertical limitations) — could be strengthened by cross-checking against the
  function's executed line count.
- 64tass `.s65` effects are not yet covered (x-rotator and kefrens are BeebAsm).
