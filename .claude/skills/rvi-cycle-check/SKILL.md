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
- `--summary` — insert a short (~5-line) **effect-summary header block** at the
  top of the draw function, auto-derived from the analysis: the main components
  (rupture-only vs + horizontal RVI, scanlines/row, rows, lines, PAL/vsync), a
  one-line gloss of the SETUP / LOOP / FIXUP sections (which CRTC registers each
  touches, loop trip count and per-iteration cost, any `JSR`s the loop calls),
  and a GOTCHA line for things the reader must respect — balanced branches that
  must stay cycle-aligned, soft-window cycle drift, `(zp),Y` page crossings, or
  cycle-exact per-scanline writes. Delimited by `\\ [effect-summary]` …
  `\\ [/effect-summary]` and replaced in place on re-runs (idempotent). Needs a
  `vertical` config block.
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
- `subroutine_cycles` — map of `"<label>": <total cycles>` for `JSR <label>`
  calls the analyser should charge at a fixed cost (the whole call: 6c JSR +
  body + its RTS). Use for **calibrated / external** delay routines such as
  `cycles_wait_128` (a 128c spin). Local straight-line subroutines that are
  *not* listed are followed automatically and costed phase-accurately (their
  stretched accesses depend on the entry parity), so you only list routines the
  analyser can't see or shouldn't inline. A `JSR` to an unknown routine falls
  back to the flat 6c instruction cost.
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
  counter is decremented more than once per iteration (trips = init / decs); and
  **increment-to-wrap** loops (`ldx #N … inx … bne` with no compare, exiting when
  the counter rolls 255→0, trips = (256 − init) / incs — the loop counter is the
  register incremented immediately before the back-branch, so a second `inx/iny`
  used as a data index elsewhere in the body doesn't confuse detection, e.g.
  checker-zoom: `ldx #2 … iny … inx : bne here` → 254 trips).
  Override with `vertical.loop_iterations` if auto-detection fails.
- **`{` / `}`** anonymous-block delimiters and `\{` / `\}` are zero-cost.
- **Decimal zero-page operands** (e.g. `BIT 0` = `BIT zp` 3c, not `BIT abs` 4c).
- **Conditional assembly** `IF / ELIF / ELSE / ENDIF` (nested) is evaluated
  against the symbol table, so lines in a false branch are dropped instead of
  double-counted. Supports the comparison operators (`= <> != <= >= < >`) and
  bare expressions (non-zero = true). A condition that can't be evaluated (a
  symbol not in `symbols`) defaults to *active* (include the body). Provide the
  switch symbols in the config `symbols` (e.g. `"SMILEY_DEBUG_RASTERS": 0`) so a
  `IF DEBUG … ELSE … ENDIF` costs only the taken branch — essential for a
  balanced-diamond check whose arm contains an `IF/ELSE`.
- **`JSR` into a subroutine** — charged as the whole call (6c JSR + body + RTS),
  not a flat 6c. A configured `subroutine_cycles` entry gives a fixed total (for
  calibrated/external spins like `cycles_wait_128` = 128c); otherwise a local
  straight-line routine is **inline-walked** at its actual call-site phase, so
  its stretched accesses are costed correctly. Those subroutine body lines also
  get their own per-line `; Nc` annotations (corrected against any stale hand
  comments) — at the phase of the real call site — and a corrected **total
  comment** on the routine's closing `}` (or RTS line): `\\ total = <body>c body
  + 6c JSR = <call>c`, the full call cost matching what the caller's `JSR` line
  shows (convention as in `cycles_wait_128`'s `= 128c`). An existing total comment
  is replaced in place — both the `total = …` form and a bare arithmetic
  `a + b = Nc` form (idempotent). If a routine is called from two different phases
  its costs differ; the tool flags this and annotates the body / total using the
  first call site (e.g. copper_set_charrow: 179c setup vs 180c loop). A sub with a
  **balanced if/else branch** is inlined too (see below). A sub whose cost is *not*
  deterministic (an unbalanced branch, an unconditional `JMP`/`BRA`, or an early
  `RTS` in one arm) can't be inlined — give it a fixed `subroutine_cycles` cost;
  the tool still corrects its end-total comment from that, but can't re-annotate
  its body per-line.
- **Balanced if/else inside a subroutine** — a forward conditional branch whose
  two arms reach a common merge label at **equal cost** is resolved: arm A =
  fall-through (branch not-taken, 2c), arm B = the branch taken (3c). Both arms'
  bodies get per-line `; Nc` annotations (the conditional split shows the
  not-taken 2c), and the routine's single deterministic cost feeds its total and
  the caller's `JSR`. Handles the `Bcc skip / … / BEQ merge / .skip … / .merge`
  shape (e.g. copper_accumulate, 38c) that the plain BRA-merge diamond detector
  misses. Unbalanced arms → not inlined (configure a fixed cost).
- **Soft-window rupture loops** — when an effect has *no* `exact_completion`
  register constraints (all `before_row_end`), a rupture loop whose length is
  **not** an exact scanline multiple is reported as a per-iteration **drift WARN**
  (e.g. plasma's 513c = 4 scanlines +1c → the CRTC address writes creep one cycle
  per row), not a hard ERROR. For cycle-exact effects a non-multiple is still an
  ERROR.

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

**Visible-line estimate — mind the SETUP and FIXUP rows.** Displayed rows are not
just the loop. These rupture effects are **pipelined**: the draw writes each
row's R12/R13 one frame *ahead* (a setup R12/R13 write only relatches for the
loop's first row). So the **SETUP frame displays one extra row** showing the
address latched by the previous **tick** (the update fn always primes R12/R13) →
**+1 displayed row** the loop math misses. This holds whether or not the draw
*also* writes R12/R13 in setup — so the tool now adds it for every such effect
(labelled "1 row from tick"). The **fixup/tail relatch can add yet another
displayed row** depending on exactly how it rewrites R12/R13 — not determinable
from the draw routine alone, so the estimate flags it as a possible `+1 row`
rather than asserting it. (e.g. kefrens/twister 256, parallax 256, plasma 260,
each possibly +1 row more from the fixup.)

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
- **plasma** (`just-rasters`, BeebAsm) — vertical rupture with **multi-scanline
  rows** (R9=3 → 4 scanlines/row, R4=0), so each of the 63 loop iterations is a
  whole char row (4 PAL lines). Loop body calls `JSR plasma_set_charrow` (inlined,
  phase-accurate) and `JSR cycles_wait_128` ×3 (configured 128c). Frame 312, vsync
  280. Surfaces a **+1c/iteration soft-window drift** (loop = 513c vs 512c) because
  `plasma_set_charrow` truly costs 49c (author's comments assumed 42–46c).
- **parallax** (`just-rasters`, BeebAsm) — vertical rupture, 4 scanlines/row ×
  62 rows, **shadow/main-RAM parallax**: each loop row rewrites R12/R13 *and*
  toggles the video page via `&FE34` (ACCCON bit 2 — **not** stretched, flat 4c).
  Loop calls `JSR cycles_wait_128` ×3. The three `vram_table_*` sub-tables are
  64 bytes each packed after one `PAGE_ALIGN`, so all fit in one page (Y≤63 never
  crosses) — asserted via `page_aligned_symbols`. Frame 312, vsync 280; same
  +1c/iteration soft-window drift (loop = 513c).
- **copper** (`just-rasters`, BeebAsm) — vertical rupture + **per-row ULA palette
  copper** (16× `STA &FE21` per row — `&FE20–3F`, **not** stretched, flat 4c/8c).
  Two same-file subs, both inlined: `copper_set_charrow` (the author's `172c` is
  really **179c**/setup, **180c**/loop — called at two phases, flagged) and
  `copper_accumulate` (a **balanced if/else** `BCC/BEQ` branch — fully inlined at
  **38c**; the author's `36c` is 2c low). Setup lands *exactly* on 512c, which
  first exposed the inserted-boundary-marker `[vert]` idempotence case (now fixed).
  Frame 312, vsync 280, +1c/iteration drift.
- **checker-zoom** (`just-rasters`, BeebAsm) — vertical rupture (R9=0/R4=0, 1
  scanline/row × 254 rows), with a per-row `STA &FE20` mode/parity write and a
  **balanced `BCC/BRA`-merge diamond** in the loop body (both paths 15c — the
  parity-wrap arm vs a 6×`NOP` no-wrap arm). Its loop is the **increment-to-wrap**
  idiom `LDX #2 … INX : BNE here` (254 trips), which the trip-count detector now
  recognises. Loop is exactly 128c. Frame 312, vsync 280.
- **logo** (`just-rasters`, BeebAsm) — vertical rupture (R9=0, 1 scanline/row ×
  254 rows) that rewrites R12/R13 **and** the ULA palette every row via a
  **fall-through subroutine pair**: `logo_set_white` (4× `STA &FE21` copper) has
  no `RTS` and falls through into `logo_set_charrow` (R12/R13 rewrite), so
  `JSR logo_set_white` is inlined as the combined 117c chain. Loop `LDX #1 …
  CPX #255 : BNE here` (254 trips, compare pattern). +1c/iteration soft-window
  drift (loop = 129c). Frame 312, vsync 280. The summary's per-row-CRTC-write
  detection scans the loop body *and its called subs*, so it correctly reports
  "per-row R12/R13 address rewrite" even though the writes are inside a sub.

## Per-line-only mode (`"vertical": null`)

Set `vertical` to `null` in the config to run **horizontal per-line cycle
annotation only** — per-instruction `; Nc` costs — and skip the PAL-frame
analysis, the `[vert]` boundary tags, and the effect summary entirely. Use this
for effects that **don't fit the single-rupture-loop model**: the vertical check
picks the one largest-iter loop and multiplies only *that* by its trip count, so
any effect with several significant loops would be mis-summed and report a bogus
"312 OK". In this mode, prefer `--annotate-missing` **without**
`--add-running-totals`, because the `<== Nc` running totals depend on a correct
cumulative count, which those extra loops break.

- **vblinds** (`just-rasters`, BeebAsm) — the worked example of this mode. It's a
  **fixed-duration buffer-fill**, not a per-scanline rupture: `linear_to_screen_loop`
  (×80 over the 160-byte buffer) + `JSR vblinds_draw_row` (14× the constant-time
  `vblinds_draw_bar`) + a `.here` timing loop (×93). `draw_bar` is constant-time
  in `bar_max` (loop1 does `width` iters, loop2 the remaining `bar_max-width`, so
  the total is always `bar_max` = 40, fixed in `vblinds_init`); the walker can't
  resolve its two-loop shape, so it's pinned via `subroutine_cycles`
  (`vblinds_draw_bar: 674`) and `draw_row` then inlines to 9829c. Per-instruction
  costs are exact; a `[cycle-note]` header in the source records that cumulative
  timing isn't modelled and the first tail-frame CRTC write is phase-approximate.
- **smiley** (`just-rasters`, BeebAsm) — the trickiest so far. A **smooth-scrolling
  status split** that builds a custom PAL frame from a display cycle (R4=27,
  R6=`smiley_visible`, **R5=`smiley_line` vertical-adjust** for sub-row smooth
  scroll) + a vsync cycle, all with **data-dependent register values** and a
  data-dependent display-loop trip count (`224 - smiley_line`); the frame stays
  312 *by design* (R5 vadj trades off against the trip count). Runs in
  per-line-only mode (`"vertical": null`) with three wait loops
  (`cycles_wait_128` ×8/×8/×32, pinned via `subroutine_cycles`). The property
  that **does** matter and is checked: the `loop_display` **balanced diamond** —
  the black-out arm (write `PAL_black` to `&FE21`, which contains a
  `IF SMILEY_DEBUG_RASTERS … ELSE … ENDIF`) vs the `NOP` arm — is verified at
  **17c both paths** so the raster stays stable whichever rows are blacked out.
  This is the effect that motivated conditional-assembly evaluation (with
  `SMILEY_DEBUG_RASTERS=FALSE` the debug arm must not be counted). Display loop
  is 127c (−1c/scanline soft drift).

## Control-flow tracing mode (`"trace_execution": true`)

For horizontal-RVI effects whose scanlines are stitched together with jumps
(jmp-into-loop, out-of-line computed SMC dispatch) the naive linear walk
mis-tracks the running total. Opt into an **execution-order trace** that follows
control flow: unconditional `jmp/bra` (incl. a `.label JMP target` computed
dispatch — a representative target is followed), traces exactly one pass of a
counted loop via a visited-set, then resumes on the loop-exit path with the
branch-taken cum. Per-line costs come from the same helpers, so numbers match;
only the *path* differs. Also handles BeebAsm scope-prefixed labels `.*name` /
`.^name`.

The corpus's **`; +N (cum)`** annotation style (per-line increment + inline
running total) is supported via `"annotation_format": "increment"`: the tool
compares each instruction's `+N` to the computed cost and each `(cum)` to the
computed running total (mod scanline), flagging mismatches. Because authors
often *group* two source lines' cycles onto one `+N` at a label split, the
per-line `+N` is advisory in this mode and the **running total `(cum)` is the
authoritative check**.

- **funky-fresh / fx-vertical-stretch** (`funky-fresh`, BeebAsm) — the first
  effect of this corpus and the motivator for trace mode. Variable-R0 horizontal
  RVI vertical stretch: reprograms R0 (scanline length) / R9 per scanline via a
  jmptab-driven computed `JMP scanlineN`, entered mid-loop by `jmp right_in_there`.
  The trace reproduces the author's `(cum)` across the whole path (setup →
  dispatch → loop @ HCC=19 → tail @ HCC=17 → rts) and found a real bug: the
  running totals on lines 216–218 read `47/49/54` but should be `49/51/56`
  (self-corrected at line 221), plus a `+9` per-line typo at line 232 where the
  cumulative `(98)` is nonetheless right. `_FX_VERT_STRETCH_REMOVE_RVI=FALSE`
  makes the teletext `IF/ELSE` arms compile to `WAIT_CYCLES`, handled by
  conditional-asm eval. **Frame validated**: `trace_frame_check` confirms
  312 lines (setup 2 + loop 118×2 + free-run tail (R4+1)×(R9+1)=74) and vsync at
  PAL line 272 (visible 238 + R7=17 × 2). The trip count (118) is config-supplied
  because `row_count` is set in the update function, out of the draw's sight.

- **funky-fresh / fx-checker-zoom** (`funky-fresh`, BeebAsm) — same RVI dispatch
  family, simpler control flow (no mid-loop entry, no teletext). Adds
  `WAIT_SCANLINES_ZERO_X n` / `WAIT_SCANLINES_PRESERVE_REGS n` = n whole scanlines.
  Frame validates (312, vsync 272). The tool found its `(cum)` running totals were
  extensively mis-copied from the vertical-stretch template: a `+4`→`+6` typo at
  line 215 (cascading through 226) and whole tail blocks (236–238, 256–259) with
  totals from the wrong effect — all corrected to verified values. The dispatch
  reaches `jmpinstruc` at HCC=100 (1c shorter path than vertical-stretch); the
  stretched `STA &FE01` in `scanline0` **resyncs to 108** regardless, so the 1c is
  absorbed (a nice illustration of the stretch-barrier property).

### Trace-mode frame check (`trace_frame_check`)

For a traced RVI effect, set a `vertical` block with `frame_lines`,
`target_vsync_pal_line`, `setup_scanlines`, `loop_iterations`,
`loop_scanlines_each`. The visible region is code-driven and cycle-exact
(validated per-line by the trace); the tail is CRTC free-run from the FINAL
latched R4/R9 ((R4+1)×(R9+1) scanlines) with vsync at row R7. The tool checks
`setup + iters×each + tail == frame_lines` and the vsync line. `setup_scanlines`
and `loop_iterations` are config-supplied because the trip count is often
data-dependent (set outside the draw).

## Known limitations / not yet done

- **Multi-loop fixed-duration effects** (e.g. vblinds) are not summed for
  vertical/PAL-frame validation — the model multiplies only one rupture loop by
  its trip count. Such effects use per-line-only mode (`"vertical": null`) above.
  A future enhancement could accumulate every loop's `iter_len × trips` (plus the
  straight-line remainder) to validate the whole function's total.

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
