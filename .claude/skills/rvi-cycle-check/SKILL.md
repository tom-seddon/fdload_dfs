---
name: rvi-cycle-check
description: >-
  Validate and re-annotate cycle-exact 6845 CRTC ("RVI") raster code in this BBC
  Master demo. Use when asked to check, validate, or update the cycle-count
  comments of an RVI draw routine (e.g. fx_draw_function), confirm the critical
  CRTC register writes land on their required cycle, check the 128c-per-scanline
  invariant, or after editing such a routine. Horizontal/timing correctness only
  (vertical/structural rules are not yet implemented).
---

# RVI cycle check

Static analyser + comment rewriter for the cycle-exact CRTC raster code used by
the RVI effects in this repo. It reproduces the hand cycle-counting, validates
the critical register writes, and updates the `; Nc` per-line and `\\ <== Nc`
running-total comments so they don't have to be maintained by hand.

**Scope (v1): horizontal / per-scanline timing correctness only.** It does NOT
yet validate vertical structure (total line count == 312, vsync/R7 placement,
the special last-scanline-of-last-row CRTC behaviour). Don't claim those are
checked.

## When to use

- "Check/validate the cycle counts in `fx_draw_function`."
- "Update the cycle comments after I changed the draw routine."
- "Did I break a critical CRTC register write / the 128c invariant?"
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

Flags: `--annotate-missing` also ADDs `; Nc` to instruction lines that have no
comment (default off — respects the author's sparse style). `--file` overrides
the source path in the config.

## Per-effect config

`config/<effect>.json` (see `config/x-rotator.json`):

- `file`, `function` — source file and the routine to analyse.
- `entry_phase` — cumulative cycle at function entry. **0** = entered at the
  start of a scanline (VC=0 HC=0 SC=0), an even / 1 MHz boundary. Different
  effects can now align the CRTC/CPU clocks differently; if a routine is entered
  in another state it must be documented and set here.
- `scanline_cycles` — 128 (2 MHz, non-interlaced, 64 us line).
- `symbols` — values for assembler constants the analyser can't see (e.g.
  `SHORTEN_BY_ROWS`).
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

## Interpreting the report

- **Per-line table:** `cum` (running total mod scanline), `cost` (computed),
  `ann` (existing comment). A `<--` note means the hand number differs from the
  true cost; these are corrected on rewrite and (unless an `[ERROR]` says
  otherwise) are harmless phase differences.
- **Invariants & register writes:** `[OK]`/`[ERROR]` for loop = 128c and each R0
  landing; `[ASK]` for an undocumented register; `[ERROR]` for a bugged page
  guard (`IF HI(x) <> HI(x)`).

## Known limitations / not yet done

- Vertical/structural correctness (312-line total, R7/vsync, last-row behaviour)
  — planned next.
- Page-cross detection needs `origin`; otherwise reported as disabled.
- BeebAsm-subset parser (the constructs used by the draw routines), not a full
  assembler. RMW-to-stretched-address and forward conditional branches are
  flagged rather than fully modelled.
- 64tass `.s65` effects are not yet covered (x-rotator is BeebAsm `.asm`).
