# CVBasic TMS9900 backend — jump codegen problems in large programs

Two related findings in the CVBasic `--ti994a` → xas99 → linkticart pipeline, both pointing at
how the TMS9900 backend emits **jumps/branches**. Finding **A** is a clean, minimal, reproducible
assembler error you can build in seconds. Finding **B** is the harder one that motivated this
report: a *silent* runtime corruption in a large real program that assembles without any error.
They look like two faces of the same codegen path (relative `JMP` vs. long `B @label`).

Distinct from the already-known `<cmp> AND <cmp>` miscompile — no compound comparisons are involved
in either case here.

## Toolchain / environment
- **CVBasic** v0.9.2 (Mar/12/2026), `--ti994a` ("Compilation finished for TI-99/4A (support by
  tursilion)").
- **Assembler:** xas99 (xdt99), `xas99.py -b -R`.
- **Cart packer:** `linkticart.py` → 32 KB cart; program in the first three 8 KB banks (8112
  payload bytes/bank after an 80-byte header; runtime copies the 3 banks to RAM at `>A000` and
  runs from RAM — no runtime bank switching).
- **Emulator:** Classic99 QI399.087, `classic99.exe -rom CART_8.bin`.

---

## Finding A — CVBasic emits an out-of-range relative `JMP` for a far label (reproducible)

**`crashbug-bigcode.bas` fails to assemble** with:

```
***** Error: Out of range: CV4 +/- -0x7ffe
***** Error: Out of range: CV6 +/- -0x7ffd
***** Error: Out of range: CV8 +/- -0x7ffc
***** Error: Out of range: CV10 +/- -0x7ffb
***** Error: Out of range: CV12 +/- -0x7ffa
***** Error: Out of range: CV15 +/- -0x7ff9
6 Errors found.
```

`CVn` are CVBasic-generated internal labels. When a routine grows large, the backend emits a
**PC-relative `JMP CVn`** (TMS9900 `JMP` reaches only ±254 bytes) to a label that is now tens of KB
away, instead of promoting it to a long `B @CVn`. xas99 catches the gross overflow and refuses.

`crashbug-bigcode.bas` is `crashbug-base.bas` with ~1450 straight-line `VPOKE #va,128` statements
inserted into one routine so that routine spans the 8 KB bank boundary. That's an artificial way to
force a far intra-routine jump, but it is a real backend bug: **the backend should emit `B @label`
for any jump whose displacement can exceed ±254 bytes**, and it doesn't. This is the cheapest lead
to chase because the assembler pinpoints the exact labels.

**Repro:**
```
cvbasic --ti994a crashbug-bigcode.bas crashbug-bigcode.a99 <lib>/
xas99.py -b -R crashbug-bigcode.a99      # → "Out of range: CVn" errors, no .bin produced
```

---

## Finding B — silent runtime corruption of a large program that assembles clean

**Symptom.** A `GOSUB`-called init routine paints a screen by reading a `DATA BYTE` opcode stream
and writing tiles with many `VPOKE`s (a few dozen, tight `READ`/dispatch/`VPOKE` loop, interrupts
enabled throughout). Once the compiled **program exceeds ~16.3 KB** (spills into the 3rd cart
bank), this routine gets **silently corrupted partway through**: it stops mid-stream, never
returns, the caller (`main_loop`) never runs, and the screen shows only partially-painted (and
sometimes garbled) structure. **No assembler error, no runtime error** — the CPU wanders off a wild
branch. Below ~16.3 KB the identical source runs perfectly. The ColecoVision (Z80) build of the
same source is unaffected.

**The unusual property: the failure WANDERS with code layout, non-monotonically.**
Program size (`.bin` length − 16384) vs. outcome, measured during development:

| program size | banks | result |
|---|---|---|
| 16,336 | 3 | **runs** |
| 16,474 | 3 | crashes (init corrupts) |
| 16,558 | 3 | crashes |
| 16,696 | 3 | crashes (gets further, then corrupts) |
| 16,932 | 3 | **runs** |
| 16,976 | 3 | **runs** |
| 17,736 | 3 | crashes |

Making the program *smaller* can move the crash *earlier*; slightly larger can make it work again.
Adding/removing ~100–300 bytes anywhere (a `DATA` block, the interrupt music player, a sprite def)
shifts whether it crashes and how far the init gets. That is the signature of a
**code-position-dependent bug** — a specific emitted branch that is wrong for its final address —
which is exactly what Finding A shows the backend is capable of, only here it lands at a
displacement xas99 does **not** reject (so it assembles, then jumps wrong at runtime).

**What was ruled out (with evidence):**
- **Not `<cmp> AND/OR <cmp>`** — every condition is a nested single-comparison `IF`.
- **Not a `DATA` desync** — every handler's `READ BYTE` count was hand-verified against the data.
- **Not the `ON x GOTO` dispatch** — read the listing; the `ci / jl / srl / sla / mov @table(r1) /
  b *r0` sequence is correct and falls through to the default for out-of-range indices.
- **Not `VPOKE` with an expression operand** — all `VPOKE` operands are plain variables
  (`#va = expr : ch = expr : VPOKE #va,ch`), register-direct, no push/pop window.
- **Not array OOB** — indices are within their `DIM` sizes.
- **Not a linkticart bank-split error** — the flat `.bin` → packed cart mapping is clean (cart
  offset = program offset + 80×(bank+1)); the runtime's copy-3-banks-to-`>A000` reconstructs the
  flat image exactly. A larger working program (Structris, ~24 KB, full 3 banks, *with* the music
  player) runs fine, so 3-bank size per se is not it.
- **Not a suppressed assembler warning** — re-ran xas99 on the crashing build with stderr visible:
  zero warnings, zero errors. So unlike Finding A this displacement is *not* caught.

**Minimal-reproduction attempts (all negative — documents the search):**
- A from-scratch minimal program with the same *shape* (DATA-driven `VPOKE` init + 12-way `ON GOTO`
  dispatch) **runs at every size tested** from 16.5 KB to 18.5 KB — the simple code never lands a
  bad displacement. (`crashbug-base.bas` is that minimal program; padding it out with inert `DATA`
  across the whole 16.5–18.5 KB range still RUNS — it does not by itself reproduce Finding B.)
- Placing the `DATA` block itself in the 3rd bank (RESTORE/READ from a high address): **runs**.
- Bulking a routine to span the bank boundary: this is Finding A — it converts the silent case into
  a *caught* out-of-range error, strongly suggesting the same root cause.

## What it looks like / best lead
TMS9900 `JEQ/JNE/JL/JMP` are PC-relative ±254 bytes; far jumps need `B @label`. Finding A proves the
backend will emit a relative `JMP` to a far label instead of a long branch. Finding B is the same
failure at a displacement that happens to encode as an in-range (but wrong-target) relative jump,
so the assembler passes it and the CPU branches into garbage — and because the displacement depends
on final addresses, it wanders with layout. **The most direct fix path is to audit where the backend
chooses `JMP`/`Jcc` vs `B @` and always use the long form when the target's displacement is not
provably within ±254 bytes** (or when the target label's address isn't yet resolved at emit time).

## Package contents
- `README.md` — this report.
- `crashbug-base.bas` — minimal base program (CLS + build routine reading a DATA opcode stream + a
  12-way `ON GOTO` dispatch + char defs + main-loop marker). Assembles and runs; pad it with inert
  `DATA` to sweep sizes — it keeps running (shows the shape that does *not* trip Finding B).
- `crashbug-bigcode.bas` / `.a99` — **Finding A reproducer**: the base with ~1450 inline `VPOKE`s in
  one routine; `xas99.py -b -R crashbug-bigcode.a99` reports the `Out of range: CVn` errors above.

I can also provide (from the real program that exhibits Finding B) a matched **run vs. crash** pair
of `.a99` listings + carts differing only by a small `DATA` change, and bisect to the exact
opcode/address where the crashing build diverges — say what would be most useful.
