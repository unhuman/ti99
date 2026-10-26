# ColecoVision VDP timing: first reads and streams

Read this when porting or optimizing VRAM access, reusing Parsec's harness, or
investigating graphics that work in an emulator but fail on a console. These
rules concern the TMS9918A-family interface at the standard Coleco Z80 clock;
derive timings again for another clock or video chip.

## What the Parsec report established

On 2026-10-25 a user reported an NTSC ColecoVision with an SD-card cartridge:
the player moved to the top before FIRE, then the sky became persistent colored
dots while terrain and HUD remained readable. The tested cartridge model and
ROM hash were not supplied. Do not treat the repository baseline as a confirmed
copy of the friend's ROM, or assume the SD cartridge caused the problem.

The saved repository release read star pixels only 18 Z80 T-states after
read-address setup, and sprite/motion data after 19 T. Its audit allowed any
address-to-data interval after 8 T; the shared emulator filled the read buffer
instantly. Consequently, both timing checks and exact state comparison missed
the missing wait. A deliberately delayed-prefetch model reproduced the paired
symptoms with that saved ROM. A stale coordinate moves a sprite; a stale pixel
read that is modified and written back corrupts the background persistently.
This is evidence for the mechanism, not cycle-exact reproduction of the photo.

The repair adds waits without changing input rules, movement algorithms or
memory layout. Native-only coverage was insufficient: ordinary startup also
found translated player-Y read `>BAA2` at 27 T after a `MOV R0,R0` became a
shorter Z80 load. That source address is Parsec-specific; identify equivalent
paths from each new port's generated assembly and runtime trace.

## Timing contract

Read-address setup initiates a VRAM fetch. The chip must become ready and obtain
a memory access window before the CPU consumes the result. Treating its roughly
2-µs internal delay as the complete active-display latency is unsafe. The
[TI data manual, section 2.1.5 and table 2-2](https://peacockmedia.software/tms/TMS9918datasheet.pdf#page=13)
describes the internal delay plus the mode-dependent window wait. The table's
Graphics I/II bound motivates the conservative 29-T gate at the Coleco clock.

| Interval | Existing conservative audit policy |
|---|---|
| Completed read-address command → first data read | At least 29 T while display enabled |
| Consecutive streamed VRAM data accesses | At least 29 T while display enabled |
| Write-address setup → first data access | 8-T setup allowance; this command does not prefetch |
| Access with display disabled | Existing 8-T minimum; keep interface setup requirements |

Parsec conservatively applies 29 T throughout display-enabled operation, even
in vertical blank. A faster path needs proof that the entire transfer stays
inside the allowed window; an interrupt occurring once is insufficient proof.
Do not generalize the write-address allowance to read commands, discard an
unfinished memory transfer, or let an intervening control command erase its
required spacing. Register and status operations have distinct semantics.

Measure intervals at consistent emulated I/O events, and inspect the emitted
instructions behind a short interval. Preserve bank/PC and actual/required
cycles in failures. Check startup, UI, sprite attributes and motion, stars,
pixel read/modify/write, and any other reader actually present in the port.
Original TMS9900 instruction timing is not preserved by static translation.
Keep interrupt/address atomicity checks separate: correct spacing cannot stop
an ISR from changing the address between setup and data.

## Regression design for future ports

- Run the assembled release routines with directed inputs that reach common,
  wrapping and boundary paths. Log first-read count/minimum independently of
  streamed-access count/minimum; extensive writes do not prove reader coverage.
- Add a negative control that moves an actual `IN` ahead of its waits, removes
  the wait, or runs an immutable known-bad ROM. Reject the offending interval,
  not merely a failure to boot. A synthetic 21-T stream check alone cannot
  demonstrate coverage of first-read prefetch.
- Run ordinary power-on and screen transitions, leave the game idle before
  FIRE, then play with normal inputs and its own initialized VRAM. Observe the
  real game-start event and sprite state; do not inject flags or copy reference
  VRAM to manufacture entry. Parsec checks 180 idle frames with both player SAT
  Y bytes remaining 80, but a new port must derive its own expected behavior.
- If the emulator prefetches instantly, an explicitly adversarial late-buffer
  mode can expose reliance on premature reads. Keep it distinct from the exact
  semantic oracle and label its limits. It does not establish exact silicon
  timing or replace a console retest.
- Re-run semantic parity, production timing, RAM/ROM budgets and matching
  gameplay-speed phases after inserting waits. Bind evidence to the final ROM
  hash. If a changed replay no longer reaches a required event, retain the
  failure and improve the input route; preserve the coverage threshold and
  verify an independent route rather than relaxing the requirement.

## Reusable implementation and evidence

Adapt the current [prefetch_test.py](../../../Decompiled/CV_Target/Parsec/tools/prefetch_test.py)
and [video_test.py](../../../Decompiled/CV_Target/Parsec/tools/video_test.py),
not an older copy of the instantaneous-prefetch harness. Symbol names, sprite
tables, input routes, expected coordinates and coverage counts are game-specific.
The fast assembled-path gate belongs in the build; the ordinary replay and
production audit belong in full verification.

Parsec commands, from `Decompiled/CV_Target/Parsec/` with its normal toolchain:

```bash
python3.9 -B tools/prefetch_test.py build/parsec.rom --replay
python3.9 -B tools/video_test.py build/parsec.rom --frames 3600 --seed 3
python3.9 -B tools/verify.py --full
```

The 2026-10-25 repaired release is SHA-256
`e089f25d0bcc651e28b960d2541443432d27a461f49f468fdf6b4a6be78b3f69`.
All 20 automated checks passed after a documented coverage-only replay rerun.
Directed first-read checks cover 9,840 reads with minimum 30 T and reject actual
early-IN mutations. The delayed-read replay has no stale fetches; the
3,600-frame production audit covers 1,026,850 data accesses and 77,771 first
reads, with 30-T minima. A second input seed also passes. These are historical
measurements for this hash, not universal thresholds for another game.

See [Parsec DESIGN](../../../Decompiled/CV_Target/Parsec/DESIGN.md#first-read-latency-on-physical-colecovision-2026-10-25)
for the implementation and [review notes](../../../Decompiled/CV_Target/Parsec/REVIEW_NOTES.md#ntsc-hardware-timing-repair-2026-10-25)
for validation, speed and artifact locations. Physical-console retest remains
pending as of 2026-10-26; automated success must not be recorded as hardware confirmation.
