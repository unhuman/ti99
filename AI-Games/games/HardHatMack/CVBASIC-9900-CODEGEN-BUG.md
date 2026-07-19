# CVBasic TMS9900 backend — layout-sensitive corruption of a large program

**Reporter context:** building a TI-99/4A game with the CVBasic → xas99 →
linkticart pipeline. This report is about a *suspected code-generation / layout bug in the
TMS9900 backend* (or its interaction with xas99/linkticart), distinct from the known
`<cmp> AND <cmp>` miscompile.

## Toolchain / environment
- **CVBasic** v0.9.2 (Mar/12/2026), compiled with `--ti994a`. "Compilation finished for
  TI-99/4A (support by tursilion)."
- **Assembler:** xas99 (xdt99), `xas99.py -b -R`.
- **Cart packer:** `linkticart.py` → 32 KB cart, program in the first three 8 KB banks
  (8112 payload bytes/bank after an 80-byte header; runtime copies the 3 banks to RAM at
  `>A000` and runs from RAM — no bank switching at runtime).
- **Emulator:** Classic99 QI399.087, launched `classic99.exe -rom CART_8.bin`.

## Symptom
A `GOSUB`-called initialization routine paints the level by reading a `DATA BYTE` opcode
stream and writing tiles to the name table with many `VPOKE`s (a few dozen, in a tight
`READ`/dispatch/`VPOKE` loop; interrupts enabled the whole time). Once the compiled
**program exceeds ~16.3 KB** (i.e. it spills into the 3rd cart bank), this routine gets
**silently corrupted partway through**: it stops mid-stream, never returns, `main_loop`
never runs, and the screen shows only partially-painted (and sometimes garbled) structure.
No assembler error, no runtime error — the CPU just wanders off (a wild branch; the routine
does not simply fall through to `RETURN`, because the caller's code never executes).

Below ~16.3 KB (2 banks) the identical source runs perfectly. The ColecoVision (Z80) build of
the same source is unaffected.

## The key, unusual property: the failure WANDERS with code layout, non-monotonically
Measured program sizes (bytes of program, i.e. `.bin` length − 16384) and outcome:

| program size | banks | result |
|---|---|---|
| 16,336 | 3 | **runs** |
| 16,474 | 3 | crashes (init corrupts) |
| 16,558 | 3 | crashes |
| 16,696 | 3 | crashes (gets further, then corrupts) |
| 16,932 | 3 | **runs** |
| 16,976 | 3 | **runs** |
| 17,736 | 3 | crashes |

So it is **not** a clean size threshold — making the program *smaller* can move the crash
*earlier*, and slightly larger can make it work again. Adding/removing ~100–300 bytes anywhere
(a `DATA` block, the interrupt music player, a sprite definition) shifts whether it crashes and
how far the init gets. This is the signature of a **code-position-dependent bug** — a specific
emitted branch/instruction that is wrong (or gets placed wrong) depending on its address.

Removing `PLAY SIMPLE NO DRUMS` (i.e. dropping the interrupt-driven music player, which reduces
both program size and per-frame ISR work) makes the init get noticeably *further* before
corrupting — consistent with either the size shift or an interrupt-timing interaction.

## What I ruled out (with evidence)
- **Not the `<cmp> AND <cmp>` / `<cmp> OR <cmp>` miscompile.** Every condition in the program is
  a nested single-comparison `IF` — there are no compound comparisons.
- **Not a `DATA` stream desync.** Every opcode handler's `READ BYTE` count was hand-verified
  against the data; the stream is well-formed.
- **Not the `ON x GOTO` dispatch.** I read the generated listing: the jump table and the
  `ci / jl / srl / sla / mov @table(r1) / b *r0` sequence are correct, and it safely falls
  through to the default label for out-of-range indices.
- **Not `VPOKE` with an expression operand.** All `VPOKE` operands are plain variables
  (`#va = expr : ch = expr : VPOKE #va,ch`), which compile register-direct with no push/pop
  window. (Expression-operand `VPOKE`s were a separate problem I'd already converted away from.)
- **Not array out-of-bounds.** Array indices are within their `DIM` sizes.
- **Not a linkticart bank-split error.** I diffed the flat `.bin` against the packed cart:
  the mapping is clean (cart offset = program offset + 80×(bank+1)), so the runtime's
  copy-3-banks-to-`>A000` reconstructs the flat image exactly. A large working program
  (Structris, ~24 KB, full 3 banks, *with* the music player) runs fine, so 3-bank size per se
  is not the problem.

## What it looks like
A branch/jump whose *emitted target or encoding depends on the code's final address*
(the TMS9900 `JEQ/JNE/JL/JMP` are PC-relative ±254 bytes; long branches use `B @label`). The
"build-address-dependent, wanders with layout" behavior matches a codegen path that emits a
short relative jump where a long branch is needed (or vice-versa), or a table/offset computed
against the wrong address, only in certain layouts. I have not isolated a minimal reproducer —
because the trigger is a specific address landing, a minimal program is hard to make crash.

## What would help you isolate it
I can provide, for the author:
- The full `.bas`, and a **matched pair** of `.a99` listings + `_8.bin` carts: one size that
  **runs** (e.g. 16,336 B) and one that **crashes** (e.g. 16,558 B), differing only by a small
  `DATA` change.
- The exact opcode/instruction where the crashing build stops (I can bisect it to the address
  with VRAM-marker probes and read out the divergent instruction in the listing).

The most direct lead is a **listing-level diff of the running vs. crashing build at the point
of divergence** — the corrupted build should contain one branch whose target is wrong for its
address. Happy to run any probes you suggest in Classic99.
