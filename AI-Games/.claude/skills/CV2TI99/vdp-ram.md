# VDP and RAM findings from the MSX-derived River Raid comparison

Read this when considering RAM collision data, bulk transfers, or separate
simulation and display schedules. The evidence is the October 25, 2026 section
of [River Raid's design](../../../Decompiled/RiverRaid/DESIGN.md), including its
fixed-ROM hashes, executed call-site traces, and reproduction commands. The
comparison used the supplied TI Super River Raid 1.1 executable, which credits
an MSX conversion. It did not have that author's source or original MSX ROM.

The shared architectural findings and proposed River Raid experiments are
maintained in [optimization.md](optimization.md), in its River Raid comparison
and RAM/VDP sections. They cover authoritative RAM collision state, budgeted
preparation, conditional sprite refresh, hidden buffers and publication,
preserved simulation clocks, and the rejected byte-shadow/cache experiments.
Treat those proposals separately from implemented and measured improvements.
The notes below add the results specific to applying that guidance to Joust.

## Joust follow-up: alignment and publication contracts

Joust's existing 30 Hz variant already separates some drawing from simulation.
Preserve both its cadence and the original-cadence cart while trying cheaper
transfers. The first 600-update diagnostic counted 4,609 VDP data reads: measure
the likely saving before evicting hot code for a complete 768-byte name mirror.
Sprite staging/publication took nearly 10% of that sampled runtime.

The original sprite records begin at an odd address and have a four-byte
stride. Moving their temporary destination to the same odd parity permits
`MOVB`, aligned `MOV`, `MOVB` for each record. A larger contiguous prefix can
use one byte, several words, and one byte. A word access to an odd address
silently aligns down: replacing byte copies with words without peeling the
prefix is wrong. The comparison/mirror pass must peel its own prefix too.
Assert both parities, full buffer ends, and canaries; retain a mutation that
deliberately breaks destination parity.

An unchanged sprite table still needs its final VDP address and read-buffer
value restored. However, if the final changed pair already wrote the final
byte, that work is complete. Track the actual output pointer and skip the
redundant final write only in that case. An odd tail can update the mirror and
be sent once. Preserve the original complete VRAM result and byte order on
growth, shrink, rotation, hidden sprites, and shared-buffer invalidation.

Alignment alone was rejected: its 60 Hz seed-1 replay reduced total SAT writes
but increased active-display bytes from 829 to 864. Faster CPU work changes
beam phase. Compare video exposure against the **latest accepted** cart, not
only the older, slower pre-optimization baseline. Joust's `check_video.py
--baseline final-delta` and sprite mutation checks record this distinction.

### Eight-byte scratchpad transfers without extra scratchpad RAM

Joust's four-byte loops used absolute `@VDPWD` operands. Loading that port
address into R8 allows two-byte `MOVB` instructions: eight writes plus count,
branch and return still fit in the same 24-byte loop image. Every caller must
set the port register, accept its clobber, and use a multiple-of-eight count.
The generic native helpers retain their byte fallback for other counts. A
full sprite upload rounds its burst down and sends the remaining 0-7 bytes
explicitly; merely changing the old four-byte mask would truncate that tail.

Keep the original zero-count meanings (256 or 65,536, depending on the helper),
returned registers/flags, wrap and final VDP state. Joust's native oracle tests
both sides of eight/sixteen-byte boundaries, and mutations change the copied
scratchpad loop's decrement from eight to four. Sprite tests cover the actual
odd-sized streams. The original scratchpad ownership checks still apply;
growing a loop into a BLWP workspace or the persistent 838 fields is invalid.
These loops retain the legacy COPY4SP/FILL4SP entry labels for existing tooling;
their current transfer size is eight bytes.

Check data-port spacing after changing addressing modes or unroll size. The
assembled Joust loops measured minimum intervals of 36 TI cycles for copy and
26 for fill in the cycle model (`scratchpad/transfer_spacing.py`). Those are
model results, not physical-hardware measurements or universal loop budgets.

The fully measured `ram-transfer` result gains 1.04% / 0.25% over the 60/30 Hz
`final-delta` carts. Its active-display SAT bytes are 773/971 (60 Hz seeds 1/19)
and 400/629 (30 Hz), versus 829/1016 and 472/646 before. The intermediate
`ram-burst` measured 0.87% / 0.07% and was superseded before full qualification.
Use the final hash-bound reports in `Decompiled/joust/build*/optimization/
ram-vdp-final/` for release validation: all 13 standard and 16 alternate gates
passed, including eight 200,000-tick original-ROM locksteps with zero differences.
No further drawing phases were skipped,
and no full RAM name-table mirror or second SAT was added to Joust.

Profile BLWP helpers with their saved return PC (R14) and caller workspace
(R13), not R11. Joust's first diagnostic falsely attributed later work to LDIR
by using an ordinary BL return convention. The corrected probe reproduced the
same gameplay rate and measured only 260,210 LDIR cycles instead of the false
3,470,346; the read counts and sprite measurements were unaffected. Keep the
invalid diagnostic named as such, rather than using it to prioritize a rewrite.

## Joust resolved-work index

This index covers the completed optimization work, its checker repairs, and
rejected experiments. Game-specific results and artifact hashes remain in
[Joust's design](../../../Decompiled/joust/DESIGN.md) and
[performance record](../../../Decompiled/joust/PERFORMANCE.md).

| Resolved work | Reusable contract and evidence |
|---|---|
| Remove the reference emulator's generated instruction closures | [Joust optimization notes](optimization.md#joust-remove-work-and-measure-the-actual-game-2026-10-25); frozen opcode/state fingerprints, mutable-RAM and wrong-result checks |
| Native screen arithmetic, rider pattern upload, character queue/ownership and collision scan | Same optimization notes and [native contracts](native-porting.md#joust-entries-physical-register-joins-and-executable-contracts-2026-10-25); live flags, Graphics II splits, original polls, executable routine/region oracles |
| Scratchpad bulk copies/fills and the eight-byte follow-up | [Eight-byte transfers](#eight-byte-scratchpad-transfers-without-extra-scratchpad-ram); ownership, count/tail/wrap boundaries, register contracts and stride mutations |
| Sprite ordering, changed-pair mirror and final read-buffer restoration | [Sprite mirror contract](optimization.md#joust-sprite-mirror-preserve-the-vdp-read-buffer) and [alignment/publication](#joust-follow-up-alignment-and-publication-contracts); parity, canaries, growth/shrink, invalidation and production beam checks |
| Preserve the 30 Hz drawing/simulation split | Earlier Joust timing notes in `optimization.md`; original-ROM logic/VRAM/sound comparisons and explicit drawing-state exclusions in `check30.py` |
| Keep the 838 interface outside gameplay work | [838 memory lifetimes](optimization.md#joust-838-setup-title-work-and-memory-lifetimes); bank budget, persistent fields, keyboard edges, visible range glyphs and ordinary restart |
| Repair measurement and checker assumptions | Main-loop pass accounting, verified menu state, successor register mappings, latest-accepted video baseline, BLWP return profiling and required failing mutations |
| Reject whole-game or presentation regressions | Larger shared-code layouts, direct sprite unroll/staging, and alignment-only beam regression remain recorded; `ram-burst` was superseded and `ram-transfer` qualified once as `ram-vdp-final` |

A full name-table mirror, a second SAT and additional skipped drawing phases
remain unimplemented experiments. A smaller VDP byte count alone does not prove
they improve Joust.
