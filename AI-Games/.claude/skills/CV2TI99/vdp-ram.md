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

This section describes the historical alternating-drawing variant, before the
cohesive conversion below. Those transfer experiments preserved its cadence and
the original-cadence cart. The first 600-update diagnostic counted 4,609 VDP data reads: measure
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
| Historical alternating drawing/simulation split | Earlier Joust timing notes in `optimization.md`; original-ROM logic/VRAM/sound comparisons and explicit drawing-state exclusions in `check30.py`; superseded by the cohesive mode below |
| Keep the 838 interface outside gameplay work | [838 memory lifetimes](optimization.md#joust-838-setup-title-work-and-memory-lifetimes); bank budget, persistent fields, keyboard edges, visible range glyphs, ordinary restart and the original 99-to-50 level cycle |
| Repair measurement and checker assumptions | Main-loop pass accounting, verified menu state, successor register mappings, latest-accepted video baseline, BLWP return profiling and required failing mutations |
| Reject whole-game or presentation regressions | Larger shared-code layouts, direct sprite unroll/staging, and alignment-only beam regression remain recorded; `ram-burst` was superseded and `ram-transfer` qualified once as `ram-vdp-final` |
| Cohesive dt=2 integration, fractional movement, timers and swept contacts | [Cohesive retiming](#joust-cohesive-retiming-findings-2026-10-26); `check_dt2.py`, `check_paired_horizontal.py`, `check_timing_helpers.py`, `check_sweep.py`, `check_world_contacts.py`, `check_swept_route.py` |
| Cumulative deadlines, elapsed-frame sound, VDP status credit and cosmetic clocks | Same retiming notes; `check_clock.py`, `check_cadence.py`, `check_flash30.py`; require one picture per completed update and retain busy-frame debt |
| Sprite rider artwork, every-update actor coverage and native drawing driver | Same retiming notes and [implementation audit](#joust-implementation-audit-2026-10-27); `check_rider_art.py`, `check_rider_native.py`, `check_draw_loop.py`, `check_cohesive.py`; preserve contact side effects and disclose sprite crowding |
| Selective 60 Hz uploads versus 30 Hz first-difference bursts and buffer role swaps | [Implementation audit](#joust-implementation-audit-2026-10-27); `sprcheck.py`, 60 Hz `check_video.py`, 30 Hz `check_cadence.py`; CPU comparison cost and beam timing matter as well as byte counts |
| Native actor/control/scan/sound paths, RNG parity, lookup tables and register reuse | Retiming notes; `check_physics.py`, `check_horizontal.py`, `check_free_flight.py`, `check_control.py`, `check_enemy.py`, `check_actor_pattern.py`, `check_bounded_scans.py`, `check_sound_channel.py`, `check_random.py`; complete caller state and live outputs |
| Late-workload RAM mapping, native caller roots, branch/poll metadata and minimal NMI | Retiming notes; `contracts.py`, `check_hand.py`, `check_air_control.py`, `check_nmi.py`, long `lockstep.py` runs; keep profile/source addresses, return linkage and both shortcut schedules consistent |
| Paired egg state transitions and independent mutation oracles | Retiming notes; `check_egg_transitions.py`; recheck state after each substep and mutate a fresh decoder instance |
| Bounded VRAM copies, native queue flushing and cached input scanning | [Implementation audit](#joust-implementation-audit-2026-10-27); preserve overlap propagation, buffer ownership, original queue outputs and modal keyboard edges |

A full name-table mirror and a second **VDP-resident** SAT remain unimplemented
experiments. The cohesive cart does use two existing CPU-RAM staging buffers;
their role swap is not a second VDP table. It publishes every complete update.
A smaller VDP byte count alone does not prove a new architecture improves Joust.

## Joust cohesive retiming findings (2026-10-26)

The user explicitly requested a different contract from the historical
`ram-vdp-final` alternate cart: one complete world update and picture per two
NTSC frames, with movement and timers covering those two frames. The old
44-logic-update/22-picture result is not a 30 FPS, full-speed result. Keep that
older cart and its tick-for-tick oracle as historical evidence; a retimed game
needs a new executable timing contract, not relaxed old lockstep exclusions.
The corrected cohesive cartridge completed qualification; its frozen evidence
and measured timing limits are in [PERFORMANCE.md](../../../Decompiled/joust/PERFORMANCE.md).
Component proofs alone do not certify another build's throughput.

- Count completed main-loop updates and complete publications separately,
  require a one-to-one relationship for a cohesive mode, and measure elapsed
  hardware-model frames. At 59.94 Hz, the target is approximately 29.97 complete
  updates/pictures per second. Two source frames per update establish the
  intended time quantum; they do not prove the CPU meets its deadline.
- Doubling the final pixel displacement is insufficient when movement has a
  fractional accumulator, alternating phase limits, walking alignment or thin
  contact bands. The initial exact two-substep vertical prototype still missed
  the CPU budget. Joust now has an explicitly retimed, single semi-implicit
  Euler step: velocity retains its original units, acceleration and impulse
  decay advance two frames, and displacement consumes twice the velocity.
  Its 5,000 independent equation/native/source fixtures and 44 equal-real-time
  constant-velocity cases are separate from the 1,836 horizontal comparisons.
  Horizontal fractional/walking phases still need their compact paired math.
  Do not repeat whole AI/object scans merely to advance two frames. Saturating countdowns must
  detect crossing zero, including the original zero-as-256 convention.
- Schedule the next deadline from the previous deadline. Scheduling it from
  the actual late completion permanently adds lateness. Do not rebase after a
  small backlog: that discards simulated time. Use a wide enough deadline to
  prevent an eight-bit signed difference turning a backlog into a long wait;
  explicit modal waits invalidate the gameplay schedule. Test counter wrap,
  late arrivals and deliberate three-frame-increment mutations in assembled
  code. Keep sound's elapsed-frame servicing separate from the world quantum.
- A destructive VDP status read can consume an unserviced F bit. Audit all
  status readers, credit the consumed event exactly once when production
  pacing is active, and preserve the unmodified deterministic oracle when
  pacing is disabled. A second read must not credit the same event. This is
  distinct from two vblanks coalescing while F remains set. Joust's instrumented
  gameplay trace found no such coalescing; measured CPU overruns remained real.
- Treat address-indexed memory profiles as evidence tied to source bytes.
  Moving generated helpers in ROM padding invalidates the previous address
  meanings. Regenerate the profile and clear stale helper entries; where all
  indirect operands are provably actor/timer RAM, record that explicit region
  proof. Stale evidence caused an incorrect mapping and expensive dynamic maps.
- Profile the exact slow interval, not just a whole workload or its largest
  routine-name bucket. Joust's final level-99 slowdown came from the lava hand,
  absent from the ordinary placement profile. Its IX/IY records and saved
  actor/sprite pointers are all game RAM; an explicit AE83-AFDD region contract
  removed repeated MAPV calls and recovered roughly six video frames over the
  600-update workload. The generator checks the pointer-producer bytes and
  external entries; 3,000 complete source/TI fixtures cover 61 observed access
  sites. Keep the nearby ROM pattern-table helper outside the RAM annotation.
- Include handwritten callers in single-caller return optimization. A Z80
  routine with one apparent caller can also be called by native assembly.
  Replacing its RET with a jump to the apparent caller leaked the native
  caller's saved link. Joust now excludes declared runtime calls from that
  transformation and tests the actual stack, registers and RAM on return.
- Native-to-native calls also need explicit allocation roots when their source
  bodies have been pruned. `ASM_REQUIRED` retains the two-frame integration
  core. Distinguish that from a partial ASM region's original return ABI:
  Joust's RNG remains a leaf, so adding a non-leaf link push leaked a word.
  Assert the leaf classification and test the complete call/return path.
- Large upward steps can bypass a terrain routine's broad-phase Y band, even
  when its narrow ceiling predicate has a crossing test. Joust's added route
  checks crossed planes against the original horizontal ranges and platform
  enable bits, then lets the original contact routine perform the response.
  The 5,000 independent route fixtures and 49 complete movement/contact cases
  cover disabled platforms, clipping, and steps through an entire band.
- Two sprite staging buffers can exchange roles after publication instead of
  copying the newly published bytes into a separate mirror. Keep both buffers
  at matching parity, track the valid prefix, and invalidate it whenever a
  shared-buffer user runs. Joust preserves exact SAT order, VRAM contents,
  final address and read buffer, with changing/repeated-frame and canary tests.
- Remove unreachable variant-specific runtime paths at assembly time. Shared
  ROM occupies the same space in every bank: removing Joust's unused 60 Hz
  delta writer from the 30 Hz runtime recovered more cold-code capacity than
  the byte count of a single copy suggests. Rebuild and measure placement.
- Reduce arithmetic only after deriving its live result. Joust's RNG feedback
  is the parity of state bits 15, 13, 4 and 0; the intermediate byte rotations'
  A/flags are overwritten before use. All 65,536 feedback states and 5,000
  complete routine comparisons validate the replacement. Preserve the refresh
  input sites so deterministic entropy injection still tests the real routine.
- Exact native hot paths include the original horizontal/vertical arithmetic,
  complete outer collision loop, enemy entry/timers/flap decision, inactive or
  not-yet-due sound channels, empty egg scans, standing-foot identity and guarded
  free-flight/floor contacts. Verify complete caller/tail state, not just a
  fragment's output. Preserve the level-three floor exception, clipping and
  negative velocity at a standing contact. Sound fixtures compare output bytes.
- An EXX-heavy helper can update alternate registers directly if every primary
  and alternate result is derived and checked. Joust's platform-color helper
  retains the exact RNG calls, then publishes alternate DE/HL directly; its
  queue loop preserves alternate BC, queue byte order and the original poll.
  Proof includes 5,000 complete color fixtures and 1,000 full descriptor/queue
  fixtures. An assembled RNG-mask mutation verifies that the oracle rejects a
  missing feedback tap.
- Give cosmetic phases a publication clock and duration a simulation clock.
  Joust's flash effect advances duration by two but draws one phase per picture.
  Advance its six-group column selector by ONE: adding two while drawing once
  aliases half the groups. A 512-state assembled/source check covers all timer
  values and all six phases. The effect's completion must share the main frame
  deadline; an embedded one-frame wait previously reset a 77-frame backlog in
  the level-99 trace. Do not dismiss such debt as an FPS accounting difference.
- Native ASM text is not automatically branch-relaxed. Expanded regions need
  explicit long branches. Compare poll sites against analysis with native
  regions disabled; do not assume both ends of a source loop require polls.
- Fuse wrappers only after proving their return convention. Joust's one-frame
  vertical path enters the original core with its caller link already saved;
  its contact wrapper shares the actor's final return. A leaf can save its link
  only around its rare nested call, as the dt=2 core does for a player flap
  sound. Compare the complete movement/contact tail, including stack depth.
- Cache a saved loop register in a genuinely unused native register when the
  callee and interrupt handler preserve it. Joust's drawing driver keeps BC in
  R8 across `N_RIDER`, avoiding a stack round trip. This depends on both bodies,
  not merely on the source routine's advertised return flags.
- Cache an invariant comparison byte in a free register across a bounded
  scan. Joust's SAT builder holds hidden-Y `$EF` once for its 22 slots instead
  of reading a ROM constant for every comparison. Preserve the writer's
  register reload and test changing sprite order and shared-buffer reuse.
  Likewise, choose actor quantum before storing it once, and put the cheapest
  common failure predicate first in a swept-contact guard. Measure these in
  the late busy interval: averages with idle frame waits can hide their value.
- A tiny immutable lookup can replace repeated flag branches without changing
  artwork. Joust's airborne pattern selector uses four-entry direction/hidden
  tables and then adds the flap offset. All 8,192 flag/control/impulse/animation
  fixtures check RAM and the original A/BC/DE/HL outputs. TMS9900 indexed
  addressing cannot use R0 as the index register.
- A guarded closed-form calculation can replace two small arithmetic steps.
  With zero horizontal residue, no screen seam and airborne speed 4..8,
  Joust's paired displacement is exactly 2, 3 or 4 pixels. Keep low-speed
  accumulation, walking alignment, early clock and clipping on the general
  path. Test both routes and ensure a loop-count mutation actually reaches
  the loop after adding the shortcut.
- Reordering broad-phase predicates can make an exhausted scan's accumulator
  differ while preserving every contact. Joust's 30 Hz scan tests X first;
  it retains both polls and the first eligible contact. Check the retimed
  source exactly and independently compare contact selection, RAM and live
  outputs with the unmodified ROM. Do not relax contact A or live registers.
- Held-direction countdown shortcuts require proof that neither timer expires
  during the update. Check quantum 1/2 at every production actor entry and
  cover zero-as-256, saturation, turning, hanging and grounded states. On the
  TMS9900, C/CB compares the **source against the destination**; reversing its
  operands caused a real countdown error caught by full movement fixtures.
- The full drawing driver, sound command decoder, screen-wrap movement,
  spawn-clearance scan and enemy-promotion scan can be native while retaining
  the original state machine. Tests must include returned registers, byte
  wrap, ordered PSG output, all actor slots, VDP state and rare exits. A scan's
  scratch register is not necessarily initialized on its first iteration:
  moving a DE assignment to every exit broke Joust's first-contact result.
- Specialize a minimal interrupt handler in its own workspace when its entire
  contract is known. Joust's original NMI only increments $600B and reads VDP
  status. Direct GLUEWS execution preserves all MAINWS registers and status,
  increments the runtime clock once and clears the latch with the status read.
  `check_nmi.py` compares 512 cases against the original handler, including
  counter wrap and every executable cartridge bank; removing frame credit
  from the assembled code must fail. Payload banks are data, not executable
  runtime copies.
- Variant-specific polls belong in explicit metadata. Joust's `.POLL` ASM
  directive emits only the region's declared service points; the two variants
  need different polls in the same pattern-selector body. Region ASM is not
  passed through the runtime's `.IFEQ` preprocessor. Assert poll ownership and
  external entries against source analysis with native regions disabled.
- A shortcut must share its interrupt schedule with the full path. Joust's
  held-control shortcut bypassed the airborne entry polls at 8661/86D5;
  standalone register/RAM fixtures passed, but long lockstep diverged. The
  resolved implementation coalesces those two polls on **both** paths between
  the surrounding 8589/85CF service points, retaining 86BD. The named contract
  checks the exact removed set; 8,192 steering fixtures measure a maximum
  1,312 cycles against a 2,500-cycle bound (under 1/20 video frame). Preserve
  long same-schedule comparisons after changing poll ownership.
- A routine oracle must respect optimized return linkage. Joust's single-
  caller egg scan can return through an inlined jump to its caller, so a
  synthetic BL-to-sentinel test continued into gameplay and waited forever.
  Compare the full scan from its source entry to its source RET boundary;
  retain live-register/RAM and bank-stack checks. A FARJ tail may leave a
  different selected bank. The assembled off-by-one starting-pointer mutation
  must still fail; do not repair such harness failures by shortening coverage.
- A word comparison does not require writing both sprite bytes. The 60 Hz
  writer now distinguishes high-only, low-only and both-byte changes, tracks
  the actual VDP output address, and still refreshes the final read buffer.
  Validate exact SAT order/content and production beam exposure separately.
  Earlier paired writes passed content tests but increased active-display
  writes in one workload; that candidate was rejected.
- Mutation tests must hit live code in each variant. The sprite variant made
  the old tile-renderer carry mutation unreachable, and adding a new entry
  instruction moved an alignment mutation's operand. Verify opcodes/labels
  before patching the actual binary. Benchmark hashes must be captured at load
  and checked again at completion, not read only after a potentially concurrent
  rebuild. Freeze source, ROM, profiles and disassembly for final qualification.
- Paired substeps must re-check state transitions between calls. Joust's egg
  landing changes its 13-byte record from velocity/residue into tile position
  and a hatch timer. An unconditional second physics call interpreted the new
  fields as motion and could leave an unsupported egg image. After the first
  call, continue only while active and still flying; hatching likewise stops
  after deletion or animation completion. The 288 landing and 36 hatch cases
  compare original guarded two-frame execution, the retimed source, and the
  assembled TI caller-to-continuation span. The old unconditional call must
  fail an explicit mutation. Native-to-retimed lockstep alone cannot detect a
  semantic mistake shared by both implementations.
- Immutable decode-data caches also affect mutation tests even without JIT.
  Apply source-ROM mutations before the first execution in a fresh emulator,
  or explicitly invalidate the relevant cache through its supported API.
  Otherwise a test may execute its already-decoded good instruction after the
  backing ROM bytes have changed, falsely reporting that the mutation survived.
- Track new high-RAM timing fields explicitly. A broad stack-byte exclusion in
  lockstep must not hide PH/publication/quantum corruption. Production stack
  instrumentation found `>F3E4` as the deepest point in the measured workloads;
  current timing fields end at `>F3DD`. Recheck deeper game states before
  claiming a universal lifetime proof.
- Compare rendered RGB pixels, not palette indices, when testing a tile-to-
  sprite substitution: TMS9918 indices 0 and 1 can both display black. Joust's
  isolated rider oracle matches all 256 position/direction cases. This does
  not prove crowded scenes equivalent: added sprites still compete for the
  four-per-line hardware limit. Test that tradeoff separately and disclose it.

Game-specific experimental rates, final qualification and artifact hashes
belong in Joust's `PERFORMANCE.md`; component tests alone are not release proof.

## Joust implementation audit (2026-10-27)

These strategies are present in the current source. This audit fills gaps in
the reusable notes; it does not claim additional speed gains or a new build.

- **Choose the upload policy for the actual change density.** The 60 Hz SAT
  writer compares aligned words and writes only changed high/low bytes. The
  30 Hz sprite renderer changes many records per picture: `NS30CMP` stops at
  the first difference and sends the complete compacted prefix through
  `NSFULL`, using eight-byte bursts and an exact tail. An identical picture
  sends only its final byte to restore the VDP address/read buffer. Prefix
  growth forces a complete upload; shared-buffer use invalidates `SATLEN`.
  `SATCUR` exchanges the CPU buffers after either path, removing the mirror
  copy. This deliberately trades more writes on changed pictures for less
  comparison/address-setup work. Measure total CPU time and presentation;
  the 60 Hz policy is not automatically the faster policy for the 30 Hz scene.
  The implementation is `src/runtime.a99`, checked by `sprcheck.py` and the
  variant-specific production timing gates. Do not extend the 60 Hz beam
  result into a claim of identical 30 Hz display exposure.
- **Amortize VDP address setup without changing overlapping-copy semantics.**
  `N_C327` batches VRAM-to-VRAM copying through the existing 256-byte `VBUF`.
  Each piece is bounded by the remaining count and the nonzero forward
  source/destination distance modulo 16 KiB. Otherwise buffering a whole
  overlapping copy would replace the original repeating-byte propagation
  with snapshot-copy behavior. Preserve zero-as-65,536, wrapping, final flags,
  pointers and VDP state; invalidate the sprite mirror before reusing `VBUF`.
  `N_98A4` similarly walks the existing character queue natively, setting one
  VDP address per run and streaming its bytes, including a one-byte fast path.
  Preserve the original queue terminator/reset and returned B/C/D/E values.
  These are existing runtime paths, not newly benchmarked changes. Reuse or
  modification needs directed overlap/queue boundary tests in addition to
  whole-game lockstep; the current native coordinate/transfer gate alone does
  not establish exhaustive coverage of these two helpers.
- **Cache input decoding while retaining sampling and key edges.** Joust's
  `CTRL` rescans every fourth emulated port read. `KSCAN` samples joysticks,
  modifiers and fire columns each scan, other digit columns on alternate
  scans, and reuses decoded outputs only when the raw snapshot is unchanged.
  The modal 838 interface forces all digit columns and uses a fresh press
  after each transition. Thus input caching and title latency have separate
  contracts. Keep controller 2 independent, initialize the cache, and test
  held/released digits and Enter through real keyboard input (`check838.py`).
  Do not infer that increasing the sampling interval is a free speed gain.
- **Retiming requires auditing phase coverage as well as displacement.**
  `tools/cohesive30.py` visits all six enemies and draws every active rider
  on each complete 30 Hz update. It adjusts phase masks/autoflap, spawn/death
  countdowns and egg service so a clock advancing by two cannot permanently
  skip an odd phase. Sprite order/rotation uses the picture counter. The
  sprite fallback also removes redundant tile-head pattern uploads while
  retaining footprint/contact work. Use `check_cohesive.py`, timing, drawing,
  art and contact checks together; simply halving a loop rate cannot establish
  full-speed play. The exact paired-vertical prototype was superseded by the
  measured dt=2 integration because repeating full physics exceeded the budget.

Preserve the distinction between rejected and unimplemented ideas: larger hot
layouts, direct-unroll finalists and alignment-only staging were measured and
rejected; a full RAM name-table mirror was deferred after the sparse-read and
hot-code-budget audit, not implemented and benchmarked. The user-selected
sprite renderer is an accepted speed/crowding tradeoff, not an exact crowded
pixel equivalent. Record new proposals and their results in the game's ledger
before promoting them to these shared accepted strategies.
