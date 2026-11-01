# CV2TI99: TMS9900 speed techniques and pitfalls

Lessons from Zaxxon, Joust, River Raid and Mean Santa. Measurements below
belong to the named game, not every translated ROM. Zaxxon busy play went
from ~45% to ~93% of the ColecoVision's logic rate (95% of its scroll rate).
Numbers use 50,050 TI cycles per frame unless noted.

## Initial-port performance acceptance

Optimization is part of building the first acceptable port. Establish the
hardware/cadence budget before choosing the renderer and RAM layout; then use
the first working translation as a measured baseline. Apply relevant proven
strategies during that initial work, not after presenting the port as finished.
The controlling completion criteria are in `SKILL.md` §0.

Maintain a game-specific strategy ledger alongside the candidate results. For
each applicable area below, record the measured cost or budget, candidate,
status, artifact/evidence and remaining action. Mark an area inapplicable only
with an implementation-specific reason. A proposal is not an optimization
result, and two small gains do not establish that other approaches are exhausted.

| Area to audit | Evidence needed before closing it |
|---|---|
| Execution/runtime overhead | Actual hot paths, BIOS versus game-owned routines, repeated mapping, argument/register shuffling, bank calls and interrupt work; consider native algorithms and proven direct RAM mappings |
| Drawing and VDP traffic | Inclusive preparation/publication cost, every writer and cache invalidator, change density, overlap semantics, burst/tail costs, beam exposure and final VDP state; compare delta writes with complete bursts |
| Static work and memory ownership | Immutable assets/lookup/descriptor opportunities, exact expansion cost, cache lifetimes, scratchpad allocation and hot-code displacement; include cold-fill and invalidation overhead |
| Game-loop scheduling | Original update/picture clocks, all actor/effect phases, timer/state transitions, accumulated debt and sound/input service; independently validate any user-authorized retiming |
| Code placement and capacity | Actual allocatable areas, branch reservations, shared bytes repeated in every bank, runtime roots and return contracts; full RAM calls for a layout/work audit, not automatic completion |
| Worst workloads and apparent saturation | Directed late/crowded/special-mode coverage, slow-interval profiles, active cycles excluding intentional waits, deadline misses and recovery; unchanged capped FPS can conceal useful headroom gains |

Resolve each profile-supported opportunity by a measured candidate or a
concrete exclusion proof. Continue where another applicable approach remains;
do not require experiments contradicted by existing evidence. Below-target
performance remains unfinished unless the user explicitly changes the target.
Meeting target still requires this remaining-cost audit; preserve the intended
gameplay speed while reducing CPU work and busy-frame stalls.

The final evidence must identify the exact ROM, accepted and rejected
candidates, representative/held-out workloads, original-speed comparison,
picture cadence, worst-frame behavior, timing assumptions, and verification
limits. No finite search proves a global mathematical optimum: document the
best demonstrated implementation and why no known applicable opportunity
remains. This requirement prevents an early handoff without inventing proof
that all possible algorithms have been exhausted.

## Cartridge size without sacrificing runtime speed

Treat file size as a bank-layout measurement, not the amount of original game
code. Count occupied banks, power-of-two padding, repeated shared prefixes,
boot-time RAM images, native action streams and expanded immutable assets
separately. Preserve the fast representation until an alternative meets the
same correctness, pacing and per-phase timing gates. A small compressed archive
is not a directly executable cartridge, and an old small but slower build is
not a size optimization of the current game.

Pitfall II's `compact512-r92` experiment starts from `title-credit-r91`:
73 occupied 8 KiB banks rounded to 128 banks / 1 MiB. The prepared-band family
alone used 51 banks: one index, two group tables and 48 record banks. Each
record bank carried only eight 256-byte records above a repeated 6 KiB prefix.
Most prefix code cannot execute while these particular data banks are selected.

Audit the **complete selected-bank lifetime** before reclaiming that prefix:
entry instruction after the bank write, every branch/call/return, data constants,
scratchpad transfer loop, interrupt policy, and bank restoration on success and
fallback. Do not infer unused code from a sampled execution profile. Pitfall's
record-bank windows are PBASSET's header/fill path and RCUCOPY/OWCOPY/VCOPY;
hardware interrupts remain disabled and there is no software NMI poll in these
windows. Preserve START/header, their complete live spans and BC01. Other asset
banks retain their full prefix: generated native actions call original helpers
with broader lifetimes and cannot inherit this exception without another audit.

Retaining eight 256-byte pages leaves 24 record pages per bank, reducing the
48 record banks to 16. Index and group banks keep their existing layout.
The packed descriptor is `(bank << 5) | page`; the pixel/header bytes, direct
ROM-to-VDP transfers, row identities and RAM allocations stay unchanged.
This produces 41 occupied banks rounded to 64 / **512 KiB**. There is no runtime
decompressor, new cache, artwork change, or cartridge-side JIT. Decode adds one
two-bit-longer shift on a prepared-record lookup; compare complete timed routes
because even tiny instruction changes can alter frame phase.
Keep replacement instructions the same encoded length where possible, so a
layout optimization does not unnecessarily move hot code. All 4,565 original-
address C/Z labels stayed at their r91 addresses in this compact build. Rebuilding
with `PF_COMPACT_BANDS=0` reproduces the r91 cartridge byte for byte.

Keep the proof executable: `tools/compact_banks.py` checks assembled symbol
spans, fingerprints the audited source paths and compares every retained page
and all 377 record headers/pixels/identities in the actual ROM. Changes to those
source paths require a renewed audit. `check_prepared_bands.py` checks every
instruction while a record bank is selected across its full 12,288-case original
ROM matrix. The compact gate rejects damaged code/data, forbidden record pages,
overlapping symbols, escaped execution and enabled interrupts. Preserve existing
wrong-descriptor/final-byte/restore-bank negative controls. `compare_compact.py`
binds the final complete suite, size and normal/water/return timings to the exact
artifact; current results live in the game's VALIDATION.md.

The later 128 KiB requirement supersedes that 512 KiB layout. A hard user
budget must become an assertion on the final loadable image. Removing padding
alone cannot reach it; do not report a smaller archive as a smaller cartridge.
The historical full-prefix comparison switch lives in frozen snapshots, not
the current 128 KiB builder.

For a tighter representation, deduplicate at the smallest reusable boundaries:
535 exact pixel rows replace 377 whole seven-row payloads; eighteen endpoint
headers are shared separately; ten native action sequences replace copies in
85 renderer records. Static pose groups collapse only after proving that no
dynamic map type selects them. Keep pixels uncompressed for gameplay reads.
The packed word offset in a 128 KiB image fits sixteen bits and also supplies
an exact row identity, removing a separate identity lookup.

Thin banks can retain only their reset header when all reads execute in
resident RAM and restore the caller before returning. Reserve those helpers
outside every mutable cache and exclude their bytes from translated placement.
Audit their complete instruction sequence, disabled interrupts, scratchpad
transfer targets and restoration; exercise an execution guard while selected.
Native action banks still need their full shared prefix because their helpers
have broader call lifetimes. Small row references may live in unused prepared
slot payload space, but generic fills retain ownership of their mutable bytes.
Poison only unused payload bytes in the no-pixel-staging test; independently
mutate the live descriptor and actual ROM row to prove the oracle observes them.

Boot-only compression is separate from gameplay/JIT. Pitfall's LZSS restores
preassembled native code and retained source data before gameplay, using a
scratchpad decoder whose lifetime ends before helper workspaces are initialized.
Bound source/output extents and compare every native-decoded RAM byte against
the assembled image *before* subsequent runtime-variable initialization.
A Python decompressor round-trip alone cannot validate the native decoder.
Measure gameplay and startup independently, retain named phase holdouts, and
reject a size-compliant candidate that fails the unchanged performance gates.
Reduce the new lookup cost before accepting a compact representation. Read a
renderer action and all row bytes in one bank visit, retain its action only
under the existing scene-local record identity, and bypass pose-group indirection
only for source-proven static map types. Small endpoint headers can share spare
space in a full-prefix action bank: fetch root and endpoint together, then
restore the caller. The root check still applies. A first upload may capture the
final byte for later resident hits only after both old residency claims were
cleared; compare real pixel writes and all final cursor/read-buffer effects.
A complete prepared-row replay can run from reserved expansion RAM, keeping
the selected data bank across row ownership checks and scratchpad transfers.
The fallback must leave before any selection; every successful path restores
the caller before returning to cartridge code. Bound and fingerprint the entire
RAM stream, extend the selected-bank execution guard, and retest full original
band matrices. Include displaced translated code in placement and timing:
resident loops trade RAM/hot-code capacity for fewer bank transitions.
Current acceptance and timing evidence are in Pitfall's VALIDATION.md.

The initial 128 KiB Pitfall r103 implementation is 75% smaller than `compact512-r93`.
It reaches 90.29% of original swimming speed, 0.51–0.58% slower than that baseline.
Five-level returns are 102.16%/106.14% of original, but 1.08%/3.61% slower than
the 512 KiB build and fail its retained 1% elapsed-time regression limits.
Record size compliance, runtime correctness and performance acceptance as
separate outcomes; this is not a fully accepted speed optimization. Keep the
failed performance result visible. All 86 runtime gates pass on the selected
128 KiB ROM, including four long exact replays; those do not waive the speed
failure. Repeated-row source-address caching and
64-byte hot-chunk merging did not improve these routes; the selected runtime
restores the simpler resident stream and 128-byte merging. The game's experiment
ledger preserves those rejected candidates and the exact selected ROM hash.

When a representation changes, update test observers to decode the actual ROM
record; keep the original emulator output as the oracle. A cached action entry
must match the cached row identity too. Reject deliberately stale row/action
identities and malformed guards. A standalone observer correction can reuse
completed unchanged gates only with an explicit named manifest comparison,
identical ROM and shared inputs, a completed corrected gate, and retained
original failure logs. Any runtime change requires a fresh full suite.

Alignment can make a cheaper descriptor without increasing its width. Pitfall's
32-byte-aligned pixel rows leave five low address bits available: its r104
two-byte reference combines the CPU address with twice the bank number there.
Two masks and an add recover the address and bank-select port, avoiding the
whole-cart pointer shifts. Keep physical word offsets in packing metadata
distinct from serialized aligned references. Both assembled decode paths pass
all 4,096 aligned bank/address pairs, with four wrong-mask mutations rejected.
Setup drops 160 to 84 cycles (changed rows) and 200 to 106 (final-row word),
while RAM code shrinks 14 bytes and the cartridge stays 128 KiB. The qualified
routes improve swimming 0.145% to 90.42% of original speed, and deep
returns 0.36%/1.47% to 102.53%/107.69% of original, versus r103. All 86 runtime
gates and retained r103 speed limits pass. The old 512 KiB down-return limit
and full-speed swimming remain unmet. Retain original output, caller-bank restoration and VDP
final-byte tests; local cycle savings alone do not establish gameplay speed.

## Measure the problem before choosing a fix

- Report both the improvement over the named previous build and current speed
  relative to the original cartridge (original = 100%), as the user requested.
  Keep ordinary play, troublesome modes and deliberately accelerated animations
  separate. For equal work, speed gain is previous time/current time minus one;
  elapsed-time reduction is one minus current time/previous time. Do not call a
  50% shorter wait a 50% speed increase. Label estimates and unmatched workloads.
- Record the original ROM and candidate TI hashes, CPU/VDP timing model and
  production pacing mode. Measure loading separately from steady gameplay;
  include the user's troublesome scenes and modes, plus held-out seeds.
  Exercise real menu/scene initialization and assert gameplay coverage so an
  idle title or failed transition cannot pass a speed gate.
- Count completed logic passes, movement/scroll progress and pass-length
  distributions on both machines with the same input sequence keyed to logic
  passes. Profile expensive passes as well as averages. Use emulated hardware
  cycles and memory wait states, not host runtime or an overclocked emulator.
  Use the timing model's actual frame period; 50,000 versus 50,050 cycles
  drifts enough to invalidate beam-phase checks. Label nominal 60 Hz rates.
- Measure **presentation separately**: log VRAM writes to the currently
  visible sprite attribute table (SAT), VDP table switches relative to the
  beam, and which completed sprite-priority phases actually appear. Logic
  throughput alone misses tearing and skipped alternating groups. Preserve
  the original sprite count, priority rotation and hardware scanline limit.
- Keep exact synchronized lockstep and production timing tests separate.
  Disabling TI pacing for lockstep also disables the scheduling being tuned.
  Accept candidates against correctness, throughput and presentation gates;
  a display repair can justify a measured cycle cost. Recheck the complete
  game after placement changes, even when the isolated routine got faster.
- Tie results to the artifact tested. Do not rebuild underneath running
  checks; use a frozen build copy when necessary. Gates must require coverage,
  exit nonzero on failure and reject a known bad behavior. Re-run affected
  checks after a fix, retain required final replay gates, and distinguish
  earlier results from final-ROM evidence. Verify the final cart in Classic99;
  a screenshot proves the loaded scene, not its speed or absence of flicker.

## The cost model

- Every memory access outside the 256-byte scratchpad (`>8300-83FF`) and the
  console ROM costs 4 wait states: cartridge ROM, 32K RAM, VDP and sound ports
  alike. Code in ROM and code in 32K RAM run at the same speed; only scratchpad
  code is faster (no fetch waits), and it is tiny.
- Zaxxon's straight-line translation was already about one TMS9900
  instruction per Z80 instruction; hand re-encoding its collision probe gained
  ~0. Profile the actual path: SDCC arithmetic loops, packed-argument wrappers,
  repeated address mapping and bank saves can still dominate other games.
  Remove that work or replace the algorithm, rather than just spelling the
  same operations in native assembly.
- Find it with `tools/tiprof6.py` (where a frame in flight goes, by source file
  and label, from the listing) and `tools/heavy3.py` / step-pass profiles (the
  passes that took two frames). Older profilers charged code that follows a
  file in memory to that file's last label: check attributions that look odd.
  Miner's `mprof.py` charged every ASM region to "rt" under mnemonic names:
  its sprite renderer showed 8k cycles a pass and really cost 23.5k. Charge
  native regions by the assembler's symbol file (`-E` `.equ`). Charge
  translated code by `labels.json`'s Z80 addresses: placement interleaves
  chunks, so the nearest label is wrong for it.
- **Even gameplay: compare pass-length distributions, then profile only
  the slow passes.** An average speed-up can leave the stutters. Run the same
  pass-keyed game on both machines and print the median, p90, p99, the max
  and the slow share for each (Miner: `passdist.py ti|z80 PASSES SEED`).
  Then add up the profile over slow passes only, against the others
  (`slowprof.py`). Miner's TI slow passes were HUD digit redraws: 3.5-5x
  the median against the Coleco's 2.3-3x. A PACE burst in the bitmap block
  draw (one address set per table for a block inside one character) and a
  native digit loop brought them to 2.5x or less. The bar is the original's
  own ratio, not a flat line.
- **The hot area fills, and a bigger native then pushes hot code into
  banks.** When the RAM and shared-segment areas are full, each larger region
  or PACE path displaces the lowest-ranked translated chunks. Miner's
  renderer fast path saved 3k cycles a pass, but the build went from 5 cold
  banks to 6, and `$BA07` rose from 1.2k to 4.0k cycles a pass. Watch the build's
  cold-instruction count and re-measure the whole game, not just the routine.
  Free room by giving no heat to Z80 code the TI never runs in play: code a
  native inlines, and translated paths that only run with PACE off
  (`ann.TI_DEAD`, read by `build.classify`). Keep the PACE entry patch itself
  hot (`HOT_ROUTINES`).
- **Profile and measure every level, not just the first.** Miner's
  placement profile came from level-1 play. Level 1 then ran at 41% of the
  Coleco and levels 4-7 and 11 at 29-32%: their routines sat in cold banks
  behind `FARCALL`, and their data went through `MAPV`. With one Z80
  profile session per level (the level index poked where the level is
  built), every level ran at 38-56%. Keep a per-level speed table
  (Miner: `levels.py`, with a `--level L` option on every speed, profile
  and routine-test tool). Level-specific code is invisible otherwise:
  Miner's level 7 spent 20% of each pass on one 3 x 5 block draw (`$CDC3`)
  that level 1 never calls. A caller count (`callers.py ADDR --level L`:
  return addresses and argument bytes) found it.
- **Count the workload before restructuring a loop.** Miner's renderer
  walks 16 objects, but play has 8 sprites: the player's 4 and an enemy's
  1. Hoisting per-object constants out of the sprite loop saved nothing
  for one-sprite objects. What paid: work done once per call instead of
  once per object (the object end writes, only the last one's survive), a
  stride instead of a pointer table, and skipping the SAT address set when
  the VDP is already at the slot (7 of 8 sprites; clear the flag in any poll
  that runs the NMI). 20.5k -> 15.9k cycles a call.
- **A producer dirty marker should track a change, not every repeated store.**
  Miner's vulnerable enemies repeatedly write their existing colour pointer.
  Marking their whole state handler dirty removed useful SAT cache hits:
  level 2 regressed from 322 to 332 frames for 300 updates even though other
  levels improved. Marking pose changes and comparing those repeated colour
  stores before invalidating brought that case to 315 frames. Test the actual
  update followed by rendering, audit every writer/reset, and include a
  deliberately omitted marker. A safe cache can still be slower overall.
- **A loop of general calls with constant ROM arguments is a fill.**
  Miner's bitmap clear called the block draw 192 times with a 32 x 1 block of
  zeros: 2.1M cycles, 42 frames per death and level start. As a PACE fill
  (256 bytes per poll, the VDP address set again after each poll), followed
  by the loop's last iteration through the real routine for its exact end
  state (RAM, VDP address, registers), it costs 0.43M. Miner's death then
  took as long as the Coleco's.
- **A native's branch into a cold bank needs a far jump.** The build check
  rejects `B @Zxxxx` into another bank. Write `BLWP @FARJV / DATA
  Zxxxx,FBZxxxx` and make the build emit `FB` symbols for the far jumps that
  regions write themselves, not only for the ones the translator emits
  (Miner's prize-hit path `$AB1A`).
- **A routine test with PACE must match how PACE runs.** A routine that only
  a PACE-replaced caller calls (Miner's `$BEE9`, under the audio sequencer)
  never runs with PACE on, so its `--pace` test fails by construction. Exclude
  that test and say why; don't loosen the compare.
- **Scratchpad RAM (`>8300-83FF`) is the only fast memory, so spend it by
  measurement.** It is on the 16-bit bus with no wait states. Each instruction
  word fetched or data word touched there saves 4 cycles. Everything else
  (cart ROM, banks, 32K RAM) runs at one speed. So moving more of the game
  "into RAM" does nothing once hot code is out of cold banks: check that first
  by charging play cycles to memory areas. In Miner at round 9, every play
  cycle outside the shared segment ran from RAM (round 10's bigger natives
  then pushed some into banks; see above). Code in the shared bank window at `>6000` is
  as fast as RAM. Then choose what to put in the scratchpad:
  1. **Inventory it.** The workspaces (`MAINWS >8300`, `GLUEWS`, `HELPWS`,
     `MAPWS`) and runtime variables (`>8360-839F`) are fixed. Template loops
     (`SPVC`/`SPWC` at `>83A0`, `SPRD` at `>83E0`) are copied in at boot even
     in ports that never call them. In Miner nothing called `VCOPY`/`VREAD`,
     which left 64 bytes free. Grep the generated `.a99` for their callers
     before assuming the space is taken.
  2. **Count data waits before moving data.** Patch the emulator's `rw`/`ww`
     to count accesses per game-RAM word in play (Miner:
     `artifacts/tmp/ramhits.py`). All of Miner's game-RAM accesses cost 3,330
     wait cycles a pass, 3.6% of play. The busiest single area was the Z80
     stack (about 1%). So relocating game variables is a small lever.
  3. **The stack only fits if its proven depth fits.** Miner's Z80 stack
     reached 34 bytes below `$63FF` in one random game, more than the 32
     contiguous free bytes. It stayed in game RAM. Measure `sp_min` over long
     runs and every level before moving a stack. An overflow there writes into
     `>8400`, the sound chip.
  4. **Put the tightest inner loops there.** Instruction fetches are most of
     the 8-bit penalty (in Miner, 47% of play cycles were `MOV`/`MOVB`). Code
     running in the scratchpad gains about 30% on that loop alone: a 10-30
     byte block copy, VDP transfer loop or pixel/row loop that runs hundreds of
     times a frame. Running it in a separate workspace (BLWP) costs more than
     it saves; per-run workspace switches lost in Pitfall II.
  5. **Record each attempt with numbers** (whole-pass cycles, not the loop's
     own) in the process ledger; rejected placements included.
- Measure speed with `tools/speed.py ti|z80 3000 <seed> - --pass` on both
  machines (logic passes and scroll steps per 100 frames in flight). Use input
  keyed to logic passes; frame-keyed random input lets the slower machine play a
  different game.

## What paid off (largest first)

1. **Native BIOS services**: the sound engine (SOUND_MAN, PLAY_SONGS, PLAY_IT,
   SOUND_INIT, TURN_OFF_SOUND), the controller POLLER and decoder, the VRAM
   read/write/fill helpers, the game's NMI glue, the VDP-address helpers.
   Keep the BIOS's data layout in Z80 RAM (the game reads it) and match every
   register and flag the original returns (`NATIVE_FLAGS`).
2. **A native renderer for the game's character-mapped playfield**, drawing a
   whole row between interrupt polls, with the row's constants computed once per
   segment (`RSETUP`).
3. **Precomputed character tables** for the renderer's per-character math
   ((pattern byte mod L) + H), built by `build.py` from the ROM and loaded into
   RAM. Lay them out **planar** (column c of tile t at `base + 256c + t`, base on
   a 256 boundary): moving a map byte into the pointer register's low byte
   (`MOVB *R15,@>8309`) selects the tile with no shifts or adds, and a tile row is
   four indexed `MOVB @n(R4),*R11`.
4. **Table-driven row geometry**: one table indexed by the row's remaining length
   gives the middle tile-row count, the last tile row's length, the last tile
   row's map offset and the row's share, so the common row has no per-tile end
   checks; enter unrolled 4-instruction sequences at a computed offset for the
   partial first/last tile rows. Fall back to the general path for the rare rows
   (map end, wrapping positions, short rows). Route resumed rows (after a yield)
   through the same fast path (+1%).
5. **TI-only renderer pacing** (`RMINN`): a coroutine renderer that yields at
   every frame end starves on the slower CPU (the playfield never appears).
   Owe each slice a share of the scroll step before it may yield; 0 restores the
   original yields and is what the lockstep uses.
6. **Compare-on-change caches** (each exact, each cheap to check):
   - sprite attribute table: copy to VRAM only after a store that changed it
     (translated stores to the table compare first and set a dirty flag; a
     partial copy when only the player's fields changed);
   - PLAY_SONGS: per channel, remember the data-area pointer, status and the
     frequency/volume bytes last sent; skip the channel when unchanged (+0.6%);
   - POLLER: once two polls have seen the same raw inputs and enable flags,
     every debounce has settled and further polls are no-ops (detect a BIOS
     controller-init by its zeroed raw bytes);
   - keyboard scan: skip the decode when no column changed;
   - a subsystem's inputs shadow (Zaxxon `$D3DC`: skip when x, y, z unchanged).
7. **Read the controllers every other frame** when the logic runs at about that
   rate; rescan the keyboard every few port reads.
8. **Native fills/copies** for loops that call a 1-byte VRAM write per element
   (Zaxxon's screen clear: 31 frames → 3-4).
9. Translation-level wins: `RST 8` (call with NMI held off) as a plain call
   where the handler would only defer; leaf-routine relaxation; constant
   propagation of `OUT (C)` ports; peepholes (ANDI/ORI constants, INC/DEC via AI);
   VDP copy loops in scratchpad (4 bytes per iteration).

## Build-space rules

- Every cold bank repeats the shared segment, so the largest cold routine (a
  connected control-flow cluster, Zaxxon 1.9 KB) must fit in one bank beside it.
  Growth of the shared segment breaks placement silently-looking ("cold cluster
  larger than a bank"): `build.py` retries with a larger hot margin.
- Emit only the byte constants (`BCxx`) that something references.
- Free RAM only through an explicit ownership map and build reservation
  (Zaxxon moved a RAM code area's start to reserve `>AC00-AC3F`). Account for
  workspaces, stacks, cache reset paths, trampoline tails and high-water marks.
  Apparently unused bytes can belong to another subsystem: Mean Santa's first
  input cache overlapped its sound cache and regressed performance.
- Report useful code/data, repeated shared bytes, boot payloads and packaging
  padding separately. A 32 KiB Z80 ROM does not imply a 32 KiB TI translation,
  but a large padded cart is not proof the useful content needs that size.
  Moving common helpers from every bank to one reserved, always-visible RAM
  copy reduced Mean Santa from 256 to 128 KiB, including expanded graphics.
  Check bank visibility/capacity and remeasure after repacking.
- Count usable headroom from placement areas, not just emitted RAM bytes.
  Pitfall's placer reserves long branch forms before relaxation; unused bytes
  inside those reservations are not a new contiguous allocation. Its later
  build reports over 1 KiB less emitted RAM code than capacity while the
  largest allocatable RAM fragment is only six bytes. Repacking requires
  renewed branch/bank validation and whole-game timing measurements.

## Sound: decouple it from game speed, and make it cheaper

Sound is both a fidelity problem and a CPU cost, and one native engine can fix
both.

- **Find the sound clock first.** BIOS games step sound from the NMI
  (OS7 `SOUND_MAN`/`PLAY_SONGS`): port those as the native OS7 library
  (`os7lib/`, `bios-ports.md` §12), and the tempo stays real-time. Games with
  no frame wait often step sound once per *pass* of the game loop instead.
  Miner 2049er's sequencer `$BE8F` runs its effect handlers once a pass. The
  ColecoVision itself runs it at a load-dependent ~89 Hz, and a TI that runs
  passes at a third of that speed stretches every sweep (the user heard the
  stomp as "garbled"). Optimizing gameplay alone never fixes it until the
  port reaches full speed.
- **Check what gameplay reads from the sound state before retiming it.**
  Miner's gameplay reads channel-claim flags (`$62D8-$62DA`, so Bob's own
  tones only sound on a free channel), an effect toggle (`$62EA`, copied into a
  trigger) and an "all effects finished" flag (`$62DE`, a condition at
  `$B95B`). Stepping that state at another rate changes the game. Cross-
  reference every load of the sound RAM outside the engine (Miner:
  `artifacts/tmp/sndxref.py`) and treat each one as gameplay.
- **Split it: an exact instance for gameplay, an audio instance for the
  ear.** Keep the original stepping of the state that gameplay reads, with
  its chip writes suppressed (with `PACE` = 0 the lockstep sees the original
  exactly). Run a second instance on a TI-only copy of the state, driven by a
  real-time clock at the original's rate, with its own writes going to the
  chip. Mirror gameplay's trigger stores into the copy. Write the engine once
  as a native taking a base register (`@off(Rb)`), so both instances share the
  code.
- **Measure the original's step rate in play, not overall.** Time only the
  intervals between consecutive passes that are shorter than two frames
  (deaths and level transitions are not play). Miner: 1.51-1.55 steps a
  vblank (92 Hz) on 3 seeds, 1.29-1.87 between the 10th/90th percentiles.
- **Find what "garbled" is before choosing a clock.** Miner's handlers share
  a channel by round robin: two active effects take alternate steps. At 92 Hz
  they blend; at a third of that each holds ~30 ms and warbles. A Z80-side
  census (which handlers are active together per pass) showed the footstep
  overlapping the stomp, but only for 6 of its 77 passes. Most of the fault
  was the sweep running 2.8x too long, which any real-time clock fixes.
- **The real-time clock: the vblank, made reliable.** Check first whether
  the game enables its NMI at all (Miner: the reference took 0 NMIs, so the
  TI glue never ran and polled vblanks never arrived). Then check whether the
  game uses the VDP status value. Miner's eight `IN A,($A1)` all discard it
  (they only reset the address latch, and its address writes are always
  pairs). So the port drops them (a speed gain in the renderer and block-draw
  loops). With `PACE` it forces VDP register 1's interrupt-enable bit where
  the game writes register 1, and GLUE becomes a TI-only vblank: it reads the
  status (dropping INT) and owes `SQRATE`/100 steps a vblank. With no other
  status reader, the polls (~23 a frame in play, gaps under one frame) catch
  every vblank. Lockstep runs with `PACE` = 0 and compares VDP registers, so
  the forced bit can't leak into it. Two steps owed in one vblank run back to
  back, so a mux still alternates at ~30 Hz; sub-frame steps would need a
  check at every poll (~1.4% of the CPU here).
- **Do not use the TMS9901 timer as the clock.** When the decrementer
  runs, the timer takes over INT3, the CRU line that carries the keyboard
  row with the joystick FIRE button. Reading it also needs a mode switch.
- **The cost cuts both ways.** At the original rate the audio instance runs
  ~3x as often as the per-pass engine did, so a translated engine there would
  slow gameplay (Miner: ~6k TI cycles a step at 89 Hz ≈ 18% of the CPU). Make
  the exact instance native too: in Miner the translated `$BE8F` path was
  6.2% of play cycles (3.19 TI cycles per T-state). The native runs at 1.64
  and the audio copy's vblank work is ~3%. The finished change ran 3% *faster*
  than the cart before it (344/365/371 frames for 200 passes, was
  356/376/383). Measure it in the pass benchmark, which is where "doesn't
  affect gameplay" is proved, together with lockstep.
- **A native that replaces a TI-only path needs its own differential
  test**, because lockstep runs with `PACE` = 0 and never executes it. Miner's
  `routest.py --pace` runs the pass step against the Z80 routine on captured
  states. It ignores only the chip's RAM copy and requires no sound bytes.
  Prove register liveness at the return. In Miner only DE and IY reach code
  that might read them; the renderer sets everything else. The first version
  got E wrong: `$8024` leaves E = `$80 | channel << 5`, without the divisor
  nibble. 14 of 300 samples caught it.
- **Gameplay-driven tones** (Miner's footstep calls `$BDE7`/`$BE05`/`$BE23`)
  stay per pass, gated by the exact instance's claims, as the original. No
  chip gate is needed while the exact instance steps slower than the audio
  one: its claims outlast the audio copy's, so the two never fight over a
  channel.
- **Work words of a native must be in RAM, not in the shared segment.**
  Runtime code runs from cartridge ROM; a `DATA 0` used as a return slot
  there reads back garbage, and the step returned into its own workspace.
- Keep the SN76489 latch rule (a data byte without a latch goes to the last
  latched register) when two producers share the chip: write each register as
  one complete latch+data sequence from one producer at a time.

## Pitfalls (each cost real time)

- **A value kept in a register across a deferral must survive every path.**
  The fast path stored the row's start offset in R1 to write `$71A9` at the end
  of the row; the strip-change code that runs at some row starts reloads R1, so
  a row that also yielded resumed at a garbage VRAM address and drew map rows
  over the score, the altimeter and the playfield. No-input lockstep runs never
  hit it; a lockstep with random joystick input found it at once.
- **Lockstep with input**: the no-input game crashes early in level 1. Also run
  random joystick + fire input (mirror it onto both Coleco controllers when the
  TI's controller 2 follows joystick 1), for millions of ticks.
- TMS9900: R0 cannot be an index register (`@T(R0)` means absolute `@T`); word
  operations ignore address bit 0 (odd addresses read the word below); `LI`, `MOV`
  and most instructions set the status bits, so nothing may sit between a test and
  its jump; `C`/`CB` compare unsigned with `JH/JL/JHE/JLE`, signed with `JGT/JLT`.
- xas99: a comment needs **two or more spaces** after the operand, or it is read
  as part of it.
- VDP: the address is low byte then high byte (`| >40` for writes); after the
  first control byte the low byte is already live, so a data write between the
  two lands at old-high/new-low. Reading the status register resets the
  control-byte latch: never take the interrupt between the two address bytes.
- Keypad decode table (`$10F5`) must be fully copied into RAM (`reserved_bios`);
  partially-profiled BIOS data silently becomes zeros.
- Test hooks on banked addresses must check the bank.
- Bash heredocs eat backslashes in Python patch scripts (`\\b` became a literal
  backspace in a regex); edit Python with the Write/Edit tools.
- The lockstep's TI side must reproduce the original's timing model: interrupts
  only at poll sites, `$C5E5`-style delays one vblank per visit, the title hold
  skipped on both sides, and every TI-only feature switched off.
- **`xlate.find_push` follows only the linear predecessor (Miner 2049er,
  2026-10-28).** A `POP AF` at a loop head was matched only with the `PUSH AF`
  before the loop, so the push on the back edge saved A but not the flags.
  Miner's score add (`POP AF / ADC / DAA / PUSH AF / JP NZ` over 4 BCD bytes)
  lost its decimal carry: 280 + 150 scored 330, found by random-input
  lockstep after 4,500 exact frames. `Decompiled/Miner2049er/tools/xlate.py`
  has `find_pushes` (every predecessor path, stack depth tracked, falling back
  to the linear match). Every port that copied the template's `xlate.py`
  (Carnival, CVZaxxon, joust, MeanSanta, Pitfall2, RiverRaid, StarWars,
  SuperDKJr) still has the linear version: a loop that carries flags on the
  stack would be silently wrong there. Port the fix and rebuild to check
  whether any generated `PUSH AF` changes.

## Pitfalls found porting Joust (Decompiled/joust)

- **A game that never calls the BIOS needs none of it.** A `$55AA` header
  skips the BIOS title; Joust's NMI is `$0066 -> $8021`.  Trace from the
  start vector and `$8021` only, and use the freed >2000-3FFF.
- **More code than RAM + one bank: place cold code by chunk, not cluster.**
  Joust's 24 KB of logic is one cluster of tail jumps.  A jump into another
  cold chunk is a far jump; every call from banked code restores its bank
  (CALLSV / FARCALL); `LD SP` resets the bank stack.
- **A far jump must keep R11 and the status.** `BL @FARJMP` broke leaf
  routines (return address in R11) and flags carried in the status: the
  game froze entering level 1.  Use `BLWP` and set the caller's R14.
- **Conditional returns are flow `cret`.**  xlate's return analysis only
  counted `ret`, so `RET NZ` handed its caller stale flags (Joust went to a
  hidden options screen).  Fixed in joust/tools/xlate.py.
- **ADC HL,rr with a carry-in: add the carry after.**  `INC HL` then
  `A HL,HL` gave 2HL+2 for ADC HL,HL (Joust's random seed).  Insntest skips
  carry-in cases it cannot set up; the lockstep found it.
- **TB 2 is active low**: EQ means no interrupt pending (a HALT loop must
  spin on JEQ).
- **Lockstep: stop both machines at the same point of a poll site.**  The
  Z80 side must not execute the poll site's instruction after the target
  tick; the TI has run only its TB 2.  Otherwise a store there reads as a
  divergence.
- **Two simultaneous players: controller 2 must not follow joystick 1.**
- **A frame wait that always waits for a fresh vblank** halves the speed
  once a pass overruns: start the next pass if a vblank already came, and
  catch the per-pass sound driver up per missed frame (Joust N_PACE).
- **Measure the drawing share INCLUSIVELY before deciding on it.** A flat
  profile charged Joust's VDP helpers (sprite upload, VRAM queue, pattern
  copies) with 14% and nearly ruled out cheaper drawing; timing each
  main-loop call from call site to call site showed the translated code
  that prepares the drawing ($9574) at about 40%, plus 6% for the upload.
- **Historical approach: draw every other tick, keep the logic per tick.**
  This describes the superseded Joust variant; the current `build30` uses
  [cohesive dt=2 updates](vdp-ram.md#joust-cohesive-retiming-findings-2026-10-26).
  It was not a full-speed 30-picture result when CPU-limited.
  Instead of scaling
  speeds and timers for a 30 Hz game (dozens of constants, each a
  divergence), Joust's `build30` patches the Z80 ROM (`tools/hz30.py`) so
  ticks alternate: A = upload + flush + logic, B = logic + drawing. Every
  tick keeps its frame wait and sound run, so rules and sound stay exact
  and only the picture is 30 Hz: 44 -> about 60 ticks per 100 frames.
  Find what the logic reads from the drawing's output and keep that part
  running every tick (Joust: `$93DB`, each player's screen address). Prove it
  with a side-by-side Z80 comparison (`tools/check30.py`): RAM every tick
  minus the drawing-only fields, VRAM after each shared flush, the sound
  byte stream. The RNG reads `LD A,R`, so both runs must set R from the
  tick number. Mutants dropping the `$93DB` run, or drawing on the wrong
  tick, must fail.

## Pitfalls found porting River Raid (Decompiled/RiverRaid)

- **A `$55AA` game can still use the BIOS.**  River Raid skips the BIOS
  title but calls the sound engine, POLLER and VRAM routines.  Start from
  the Joust tools (region map, MAPV, far jumps) and add the BIOS back:
  `is_rom` covers $0000-$1FFF, `ann.BIOS_USED` entries, a KB region, and
  Zaxxon's natives (same offsets if RAM and cart share K = >3000).
- **Initialise KPAD to $0F.**  KSCAN only decodes on a change, so a
  never-touched keyboard left KPAD = 0, which the port reports as keypad
  key 0: River Raid's pause.  The first lockstep compare caught it
  (POLLER's raw bytes $73F0/1 = $8F instead of $80).
- **MIRROR the BIOS idle-channel byte for the native sound engine.**  It
  reads channel data as `@K(R5)`, and an idle channel points at BIOS
  $024C, so $024C + K must hold that byte; with BIOS data at KB the TI byte
  there is something else, and every idle channel played junk at full
  volume.  Reserve it so no code lands on it.
- **Computed jumps through data tables.**  Record targets with a hook run
  (`tools/ijumps.py`), then read the tables themselves for the ones play
  never reached (River Raid's object type records give three handler
  words each).  A per-site compare chain (`CI R0,>t / JEQ Zt`) beats the
  global JPLOOK search.
- **INC A / SUB n before DAA** are BCD adds/subtracts too (`BCDSV`).
- **A conditional return may write R8 on its way out**: the "flag saved
  in R8 but R8 is overwritten" check must ignore `cret`, whose
  canonicalising lines are skipped on the fall-through path.
- **The OUTI/INI loops of WRITE_VRAM/READ_VRAM ran through MAPV** (their
  pointer can be ROM or RAM): 28% of the TI's time before the natives.
- **A slower pass moves the game's vblank work into the picture.**  A
  game that waits for the frame and then uploads sprites / switches VDP
  registers does that in vblank on the Coleco; on the TI the wait often
  returns late and the same writes tear the screen (River Raid's scroll
  switches the pattern table every step).  Measure with a beam-position
  log of VRAM/register writes on both machines (RiverRaid `tools/vtime.py`,
  `tools/vregs.py`), then queue those writes when the wait was late and
  send them from the frame handler at the next vblank (`DEFON`/`GLUE`).
  Only accesses that could observe the queue wait for it; make every BIOS
  VDP routine native first so no poll falls inside a VDP sequence, and keep
  polls in hand-written loops or the handler arrives too late.
- **Uneven pass lengths read as jerking.**  At 1-2 frames a pass the
  scroll speed alternates; holding every pass to two frames is smooth but
  slower (River Raid `build.py --even`).  Offer both.

## Cross-port loop comparison and acceleration

River Raid's supplied MSX-derived TI port (`SRR11_8.bin`) exposed useful
optimization strategies for our Coleco-derived TI port (investigated October
25, recorded here October 26, 2026). Another port's source is not required:
disassemble its binary, locate the executing loop, and instrument call sites
and returns. Compare **work per gameplay update and how often it runs**,
not just instruction counts or ROM size. Different original platforms can
also mean different game rules; retain our original ROM as the behavior oracle.

Measure normal and accelerated play separately. Both River Raid scroll
controllers advance their four-phase scroll every update at speed 4, every
second update at speed 2, and every fourth at speed 1. Acceleration therefore
requires more scrolling work per gameplay update. A normal-speed average can
hide precisely the path that misses its frame budget while accelerating.

**Measured evidence, not an implemented optimization:** in a 150-video-frame
Up + Fire probe, our port completed 111 updates and 111 sprite uploads; SRR
completed 146 updates and 45 sprite refreshes. Our inclusive scroll stage
used 29.72% of elapsed cycles, objects plus sprite construction 31.00%, and
the frame wait only 1.41%. Short 300-frame opening probes measured 43.4 versus
56.8 accelerated gameplay updates/s, about 31% higher throughput for SRR.
These are nominal-60-Hz, separately initialized samples, not synchronized
whole-game comparisons or evidence that our port has gained 31%. Do not add
inclusive stage costs to flat subsystem percentages, or compare an upload-only
call with another port's combined sprite construction/upload as equal work.

Investigate these mechanisms when the profile supports them:

- **Batch row work before redesigning the renderer.** Our `$8BD5/$8C02`
  scroll path repeatedly sets up rows and preserves original compatibility
  state. Investigate grouped queue records/transfers and moving loop-invariant
  setup outside the row loop. Preserve observable intermediate state and safe
  IRQ service points. Measure the whole game after placement changes.
- **Prepare terrain within a budget.** SRR uses resumable row generation,
  RAM name tables and chunked uploads. Spread preparation ahead of need;
  publish only a complete display state at a safe video boundary. Establish
  buffer ownership and worst-case completion time, including bridge changes.
- **Separate gameplay from sprite construction.** SRR's update runs apart
  from its age/workload-controlled sprite refresh, which has a four-update
  age limit. Our `$AFEA` performs gameplay as well as sprite construction;
  skipping it would skip simulation. Keep input, movement, collision and
  sound on their proper clocks. Optimize descriptor work, then investigate
  independent presentation while retaining sprite priority and visibility.
- **Remove rendering dependencies from collision before deferring it.**
  SRR's sampled gameplay performed zero VDP data reads. Our original pixel
  tests can force queued video work to finish. Investigate authoritative RAM
  terrain and immutable pattern data, starting with guarded cache hits and
  exact fallbacks. Audit every writer, phase change and invalidation; test
  cold/warm caches and pending queues. Zero reads alone does not establish
  the other port's collision algorithm. The earlier slow byte-shadow trial
  remains rejected; a different RAM representation needs its own measurement.
- **Measure presentation independently of throughput.** During accelerated
  SRR play, logical scroll steps continued while visible pattern phases were
  often combined into larger row steps. Fewer displayed phases can improve
  tick rate while reducing smoothness. First seek gains preserving complete
  two-pixel phases; treat phase skipping or reduced sprite cadence as an
  explicit presentation tradeoff. Check input-to-display latency, scroll
  displacement, sprite-priority phases and beam timing, not just tick counts.

For River Raid, prioritize the scroll batch experiment and sprite-descriptor
work as smaller changes; the larger opportunity is budgeted rendering with
independent simulation, enabled by correct RAM collision. These are candidates,
not promised gains. Benchmark normal and accelerated modes, retain the original
gameplay oracle and production presentation gates, and include bonus, bridge,
death and restart transitions. The reported bonus corruption remains unresolved;
passing short headless traces does not clear it or qualify SRR as a correctness
oracle. Use original-emulator review as well as headless tests.

Local evidence and reproduction commands:
[River Raid DESIGN.md](../../../Decompiled/RiverRaid/DESIGN.md#october-25-2026-comparison-with-super-river-raid-11),
`Decompiled/RiverRaid/build/msx-comparison-20261025/`, and
`scratchpad/{compare_srr,trace_srr_loop}.py` under that game. Preserve new reusable
loop/scheduling findings in the shared skill; keep full disassembly, hashes and
candidate results in the game directory.

## Mean Santa: elapsed frames and complete sprite presentation

`Decompiled/MeanSanta/DESIGN.md` records the implementation and measured
limits; its `README.md` gives commands for that tool version. In 600-frame
runs, weather reached nominal 60 updates/s and houses 59.8-60, with no visible
SAT writes, active-display switches or skipped completed priority phases.
Loading fell from 303 to 53 frames. These are measured workloads, not a claim
that every possible scene fits one frame.

- **A frame spent doing work counts toward the gameplay wait.** A wait that
  always demands a fresh vblank adds an extra frame after an overrun. Track
  serviced frames so an elapsed frame satisfies the main `delay(1)`, while two
  updates cannot consume the same frame. Keep intentional title, respawn and
  other multi-frame delays. Test early, already-late and counter-wrap cases.
- **Pending does not mean freshly entered vblank.** An IRQ already pending
  when polled may be near the end of blanking. An early upload is safe only
  when its full budget fits after an observed fresh edge. Split long native or
  straight-line paths with production service points outside NMI code and
  VDP transactions, preserving live flags/registers. Retain the synchronized
  poll schedule in exact replay mode; test production latency independently.
- **A status read can erase an unserviced frame.** A long VRAM fill can cross
  vblank, then clear the VDP interrupt with its final status read before the
  software poll sees it. Where the contract permits, service the pending
  frame before that destructive read. Test a fill straddling the edge and a
  mutation that restores the lost interrupt; do not poll mid address/data
  transaction.
- **Prepare a hidden SAT and publish it atomically in vblank.** Prove both
  buffers fit unused VRAM, including any library terminator beyond 128
  attribute bytes. Switch register 5 before lengthy input/sound service.
  Use that game's VRAM map; Mean Santa's spare table address is not portable.
  Check initialization, ordinary uploads and any partial-copy paths.
- **Publish a completed pending table before reusing its buffer.** In a
  late-to-early transition, preparing the next table first can overwrite an
  undisplayed priority group. Mean Santa reached 60 logic updates/s while
  this still dropped snow phases. Test consecutive distinct groups and their
  visible order, not only total uploads. An early upload must replay the
  original call's observable register results without uploading twice.

Mean Santa's `tools/speed.py --video --require-clean-sprites` checks actual
presentation alongside throughput (use the README's full scene commands).
`tools/check_pacing.py` exercises assembled waits, boundary sprite records,
consecutive priority phases and the fill/status edge, and rejects missing-wait,
hidden-Y, skipped-phase and lost-edge mutations. Adapt these properties to the
port; do not copy its speed floor, scene IDs or memory addresses blindly.

## Mean Santa: compiler overhead and immutable assets

- Replace expensive library algorithms with native operations when their
  entire observable contract is known: unsigned division including zero
  divisors; small power-of-two remainders with the required signed fallback;
  direct tile reads and clipped row/block copies; sprite/object loops that
  avoid repeated packed-argument and pointer shuffling. Keep RNG order, byte
  wrap, hidden-Y boundaries, colours, capacity and priority rotation exact.
- Fold SDCC address sequences only when flags are dead and no internal entry,
  poll, patch or bank boundary can enter the fold. Instruction tests must
  execute the complete folded sequence. Remove a bank-save frame only after
  checking every callee and tail-jump path; a helper's common return is not
  proof that all paths preserve the bank.
- Reduce NMI saves from a transitive clobber audit, not the handler's first
  few instructions. Scan physical input once and derive the original outputs.
  An unchanged-input cache must still replay outputs if game initialization
  cleared their RAM; unchanged input does not imply valid destination bytes.
- Predecode immutable graphics with the original decoder at build time when
  that removes loading work. Vary initial destination contents to establish
  independence, compare all decoded bytes, and budget expanded assets plus
  a bank-safe transfer trampoline. Preserve ROM bytes used as data even if
  disassembly labels them code: Mean Santa's colour cycle reads one such
  boundary byte before wrapping.

For SDCC stack representation and original-ROM routine comparisons, follow
[native-porting.md](native-porting.md), sections 3-5. The game's isolated
native/collision/tile tests are executable examples; keep the original ROM
as the gameplay oracle and validate intentional TI-only changes separately.

## Pitfall II: complete asset tables and return lifetimes (2026-10-25)

- Profile inclusive game stages as well as flat labels; native helpers and
  nested decoder work otherwise hide the cost of their caller. Timing hooks
  must inspect backing memory without charging CPU read cycles.
- Walk the original control flow for return-discarding POPs, including POP BC
  and conditional calls. Pitfall II has six such families. Protect their
  entries and every caller from bank wrappers, and check bank-stack neutrality
  at each completed game update. Add a no-progress watchdog to speed tests.
- Expand complete immutable pose tables, not sampled frames. Preserve actual
  variable output lengths, masks, final pointers, stack state and all drawing
  actions. Put expanded bytes in dedicated banks with the complete shared
  prefix; restore the entry bank on hit and fallback. Reserve the asset window
  during placement, not only after assembly.
- A perfect hash still needs the full source pointer checked. Test all valid
  keys, unknown keys with the same hash, and corrupted target/data mutations.
  The same approach can remove long computed-dispatch comparison chains.
- Reusing a RAM row requires proof its bytes still exist. Pitfall II permits
  reuse only within one validated scene, clears the identity at entry, still
  executes every dynamic drawing action, and checks destination bytes in the
  oracle. A persistent identity without writer tracking is unsafe.
- Retest layout changes on startup, unusual movement and held-out routes.

## Pitfall II: native sound and bounded VRAM copies (2026-10-25)

- Distinguish the shipped cartridge from the oracle's host implementation.
  Pitfall II already ran static TMS9900 instructions with no runtime JIT.
  Python opcode caches in the reference/test emulators are test acceleration;
  removing them does not reduce TI cycles. Build-time decoder compilation is
  also ahead of time, even when the original asset format is called bytecode.
- A game-owned music engine needs its own native port. Pitfall's reachable
  `$AC86-$AF3D` sound path now has native SFX dispatch, five effect handlers,
  channel initialization, duration lookup, three-channel update and rhythm.
  An unused OS7 source file is not evidence that OS7 runs in the cartridge.
  Check the actual call graph and assembly coverage, retain every ordered PSG
  write and original tick, and compare complete RAM/register boundary state.
- Sound fixtures need initialized song pointers. A synthetic playing flag
  with zero channel pointers is not a valid playback state. Capture initialized
  entries, assert that invariant, then vary effect timers, pause, mute and song
  initialization. Keep cold-start paths in complete replays. Pitfall's checker
  covers 1,885 states and rejects altered SFX and rhythm output bytes.
- Replace byte-at-a-time VRAM copies with bounded read/write bursts only
  after proving source/destination bounds and overlap direction. Forward
  overlap must retain the original propagation semantics; wrap and zero-count
  semantics must also retain their fallback. A 32-byte scratch buffer in proven
  unused cache padding avoids consuming another workspace or code region.
  Invalidate destination residency before writing, preserve VDP read-ahead and
  final address state, and poll NMI only between completed transactions. Never
  re-enter a helper workspace while its registers or buffer remain live.
  Test both overlap directions, boundaries, wrapping, canaries and corrupted
  source/invalidation/oversized-burst mutations against the original.
- For tiny constant decoder calls, even a hash lookup and bank switch can
  dominate useful work. Compile fixed call sites to direct native stores only
  when the generator verifies the original instruction bytes, inputs, decoded
  lengths and continuation. Preserve returned pointers/registers and an exact
  replay path. Test each region before its caller can overwrite bad bytes;
  Pitfall checks both six-byte seed pairs with randomized surrounding RAM.
- Recheck throughput after these changes. Pitfall's renderer remained about
  56% of inclusive river work before this pass; making sound fully native did
  not by itself yield a large gameplay speedup. Report startup and sustained
  swimming separately, and do not count fresh-edge presentation waits as work
  that can simply be removed. Final measurements belong in the game's
  `OPTIMIZATION.md`, `VALIDATION.md` and hash-bound experiment ledger.
  Fresh TI heat failed startup despite passing assembly/source gates. Word
  RAM decoding also passed correctness but had no useful speed gain; both
  experiments were rejected and retained in the ledger.

See `Decompiled/Pitfall2/VALIDATION.md` and its hash-bound experiment ledger.
Full original speed remains unmet; do not transfer its rates or addresses to
another game. Original CPU, RAM, VRAM and ordered sound writes remain oracles.


## Pitfall II: direct uploads, scores and complete checkpoint returns (2026-10-25)

- Immutable expanded graphics can remain in ROM. Store a checked pointer,
  bank and final byte in the cache entry instead of copying the same payload
  into RAM before every upload. Generic mutable streams still need RAM storage.
  Restore the caller bank on both uploads and resident hits; audit the live
  backing bytes and mutate the descriptor actually used by the fast path.
  Corrupting an obsolete staging buffer no longer tests that path. Pitfall's
  direct-band candidate passed all 62 existing gates.
- A frequently repeated decimal score operation can dominate a return
  animation. Pitfall subtracts nine from six unpacked decimal digits at each
  travel step. A guarded native borrow operation and two six-byte score
  uploads replace repeated generic BCD work and individual character writes.
  Keep zero saturation, leading blanks, invalid-digit/argument fallback,
  returned registers, both-table invalidation and VDP side effects. `VCOPY`
  clobbers R1 with its computed branch entry; explicitly restore the final A
  byte. The 701 score fixtures include output, borrow and invalidation mutations.
- Measure the entire state lifetime. Pitfall's `$7063` countdown ends before
  checkpoint travel; `$7050` bit 6 covers both. A one-frame minimum does not
  imply one-frame throughput when rendering already exceeds that budget.
  The user explicitly authorized faster automatic return. The accepted build
  batches two complete player steps per publication and checks termination
  before the second step. This is an intentional animation change, not a
  general permission to omit gameplay work or accelerate normal movement.
- Compare every internal movement/score step when batching an animation.
  A publication-level trace will intentionally have fewer samples. Use the
  same explicit controller direction through the automatic interval: a
  pass-keyed random script can leave different directions held when manual
  control resumes, producing an apparent endpoint mismatch. Test normal,
  exact-mode and completion guards, including deliberately bypassed guards.
  After this behavior change, whole-publication throughput mixes different
  amounts of manual and automatic play. Compare equal normal-play prefixes
  and sustained water routes separately; retain longer production replays.
- Native far-call descriptors must resolve hot as well as cold targets.
  A label moving into RAM does not make its old cold-bank symbol valid.
  Preserve raw near-branch checks and original C-call/Z-tail conventions.
- Fixed call sites can remove a general helper's count/alignment/loop work.
  Pitfall clears 12 bytes and 16 bytes at two constant, aligned frame-buffer
  addresses. Direct word stores reduce the measured block from 1,796 to 674
  cycles. Check the original call-site bytes, all incoming C-register values,
  flags, stack neutrality and randomized neighboring RAM; an out-of-range
  store must fail. Put the common inactive-return guard before the exact-mode
  check when both paths have equivalent results. Re-measure placement: the
  first batching layout regressed a normal-play holdout by 1.346% and was
  rejected against its unchanged 1% limit.
- Distinguish slow regression execution from slow emulated hardware. Lowering
  Cygwin workers to BelowNormal caused severe starvation behind other builds;
  bounded worker counts were more useful here. Judge ROM speed in emulated
  cycles/frames, and change only this task's processes when managing host load.

The combined Pitfall follow-up passed 66 gates, including four long exact
replays, both sustained water routes and the complete return journey with
both completion directions. Five equal normal-play prefixes retain the
unchanged per-phase regression limits. Current timing and remaining limits belong in
`Decompiled/Pitfall2/VALIDATION.md` and its hash-bound experiment ledger.

## Joust: remove work and measure the actual game (2026-10-25)

For the subsequent MSX-derived River Raid comparison and Joust RAM/VDP follow-up,
read [vdp-ram.md](vdp-ram.md). It covers simulation versus publication cadence,
logical collision state, aligned word staging, and why fewer total writes can
still increase active-display exposure.

- Distinguish the static TI cart from the reference emulator. Joust's cart
  never used a JIT; its old Python reference generated and cached instruction
  closures. An ordinary interpreter with a cache of decoded instruction data
  removes that machinery without claiming a hardware speedup. Keep mutable RAM
  instructions uncached. Freeze register, memory, VDP, I/O and cycle fingerprints
  before replacement; Joust checks 7,144 opcode/state cases plus stale-RAM and
  deliberately wrong-result cases.
- Count completed main-loop passes, not every call to a shared wait routine.
  Joust's C343 also runs during menus and deaths. Its replacement front end
  waits at E0CA, not the unused original menu at 806F; an otherwise plausible
  game-over test watched the latter and timed out. Verify the selected difficulty
  and player count in game RAM before measuring. Use equal completed workloads,
  pass-keyed input and optionally pass-keyed entropy when the original mixes
  instruction counts into RNG; also test the unmodified production RNG path.
  Short runs can look much faster because they omit the expensive later scene.
- Inline bit/word arithmetic can remove expensive byte-register shuffling:
  Joust's tile-address calculation, rider pattern upload, queued character
  append, and clipped-character ownership test all benefited. Preserve split
  transfers at Graphics II screen thirds, modulo byte arithmetic, returned
  pointers, and the exact live flags. A collision scan must preserve its polls
  as well as distances and branch destinations.
- Scratchpad code must have a lifetime and an owner. Joust reuses the boot
  copier at >83A0 only after payload installation and uses >83E0 beyond MAPWS.
  Build checks prove both loop images fit without overlapping workspaces or
  uploader scratch. Transfer loops still need count/tail/wrap tests; zero byte
  counts may mean 256 transfers, not zero. The October 26 follow-up fits eight
  indirect-port writes into the former four-byte loop's reservation; see
  [vdp-ram.md](vdp-ram.md#eight-byte-scratchpad-transfers-without-extra-scratchpad-ram).
- Shared hot code consumes space in every cold bank. Increase placement caps
  only in isolated builds and measure both layouts; a faster helper can move
  enough surrounding code to erase its gain. Keep a hard cart-size gate and a
  hash-bound experiment ledger, including rejected layouts.
- Check sprite byte order against the original routine across every priority
  rotation and hidden-Y boundary. Count writes against production beam timing
  separately; exact lockstep cannot prove tear-free presentation. Joust's
  existing active-display SAT writes remain an explicit limitation.

Use `Decompiled/joust/DESIGN.md`, `tools/bench.py`, `tools/optstage.py` and
`tools/nextverify.py` for the port-specific commands and final evidence. Do not
copy Joust's menu addresses, 128 KiB budget or performance numbers to another
port.


### Joust 838 setup: title work and memory lifetimes

Keep title-only interfaces out of the gameplay hot segment when a spare bank
fits the existing cartridge. Joust's inline 838 setup uses bank 15 with a shared
BLWP trampoline that preserves registers/status and returns to the correct bank.
Budget that bank explicitly so payload placement cannot consume it. Bind both
the start address and its bank; an address alone is not a valid far target.

Audit existing buffers before treating a gap as unused RAM. Joust's F500-F5FF
already belongs to a VRAM copy buffer. A modal title workspace can share its
lifetime, but selected mounts and a pending flag must survive startup copies;
they were moved beyond the measured scratchpad fill-loop end. Test initialized
game RAM, not merely the displayed digits, and assert assembled region bounds.

Key edges and release barriers matter at both transitions. The activation 8
must not also answer the mounts prompt. Two digits and digit+Enter need the same
numeric interpretation, with explicit zero/empty behavior. Consume Cancel until
release before resuming the original menu: Joust's # key also exits that menu.
Its checked original HL allocation supplies the highlighted player/difficulty
choice; the setup must preserve that choice. See `tools/check838.py` for real
keyboard-input tests and an assembled invalid-level mutation.

Check the original successor rule as well as the selected starting level.
Joust explicitly maps 99 -> 50 at B978-B982; its level byte is at 61CA.
The 838 interface exposes that existing 50-99 repeat cycle. Do not mistake it
for a decimal-input or retiming defect. `tools/check_level_cycle.py` compares
all 99 valid levels with the unmodified original on both TI variants and rejects
an assembled mutation changing the wrap destination. Extending the displayed
level count would be a separate behavior change requiring a table/difficulty
audit, not just removal of the wrap branch.

Check actual title glyph patterns when adding range prompts. Joust leaves the
hyphen, question-mark and underscore tiles blank in the relevant font third.
Install bounded modal glyphs and restore them on cancel; testing name-table
bytes alone cannot prove that punctuation is visible. For odd-offset fields,
use MOVB: a TMS9900 word store aligns its address down and corrupts the adjacent
character.


### Joust sprite mirror: preserve the VDP read buffer

Faster CPU work can move SAT writes into active display even when completed
VRAM contents are exact. The two-player held-out workloads caught that on both
Joust variants. A direct unroll and plain staging burst did not cure it. The
retained uploader stages the original compacted/rotated stream, compares word
pairs with its last published prefix, and writes changed pairs. Prefix growth
forces a full upload. Bound both buffers, invalidate before any lifetime reuse,
and reject untracked writes while the mirror is valid. Joust shares VBUF with
C327 and title UI, so those boundaries explicitly invalidate SATLEN.

Skipping every unchanged byte is subtly wrong: the TMS9918 data port refreshes
its read buffer on writes. The last byte must be republished even on an unchanged
picture, along with the original final address. The original-ROM oracle caught
this. Test consecutive cached calls, growing/shrinking tables, hidden sprites,
all rotations, canaries and invalidation mutations. Count logical upload calls
rather than writes to the first SAT address; then assert full published bytes,
mirror coherence, address and read buffer at each return. Keep raw active-display
write counts and the original no-increase threshold.

## Carnival: static work and freeze regressions (2026-10-25)

Carnival already translated Z80 code ahead of time. Its cartridge has no
interpreter or JIT. The retained optimization expands two fixed RLE streams
(3,520 bytes) at build time, validates all five constant call sites, and uploads
bounded slices from a ROM data bank through scratchpad code. It also predecodes
the fixed 13-child gallery tree into compact descriptors. Preserve dynamic
frames, positions, clipping, register/flag exits and original RAM bookkeeping.
The 128 KB cart size is unchanged. Compare bank placement and whole-game speed:
a 1,032-byte unrolled gallery was worse than the retained 266-byte table.

The retained object path also removes smaller, repeated setup costs. OB0
inlines the common signed divide-by-eight/range check and calls CLMP only
when saturation is needed; only the clamped low byte is live at these sites.
The generic complex-object O4L loop maps its lists to TI pointers once, then
uses byte auto-increment loads and a register counter instead of repeated
indexed translations and a memory decrement. Preserve byte-packed fields,
the zero-count/256-component case, child status writes, alternate-register
results and the caller's original bookkeeping. Validate the generated and
generic paths against captured BIOS states, including clipping boundaries.
Carnival's `src/os7obj.a99` combines these with game-specific OGL dispatch;
copying that file alone into a generic port is not a complete integration.

Keep these correctness contracts when reusing the code:

- **Confirmed flashing fix:** WEND publishes a completed batch; frame service
  sends it. ONTIME records tick entry and can be stale by writer completion.
  Do not reintroduce that immediate flush. The user confirmed this removes
  prior-state flashes. `commitcheck.py` executes the assembled path at four
  beam phases; the prior ROM is its negative control.
- **Elapsed-frame credit:** a destructive status read outside the tick can
  consume the VDP frame bit after GLUE has serviced it. Keep TICKFR, cleared
  at boot, as the serviced FRAMEC value consumed by TICKD. FRDUE credits a
  different FRAMEC before the game's wait test, gated on PACE; equality means
  no new credit. This avoids waiting another frame for work already elapsed.
  Poll before FILL_VRAM clears status, then preserve the original returned
  status. Do not use POLLN/ONTIME as permission to flush. `framecheck.py`
  executes equal, changed, wrapped and exact-mode cases plus 11 bulk fill
  lengths/wrap cases; its mutation removes the credit. Keep TICKFR's reserved
  word distinct from SNDBNK and the asset uploader workspace.
- **Flashing recurrence and poll latency:** retain commit-only WEND and make
  TICKD commit-only too. Long natives can delay GLUE even with correct commit
  boundaries. Carnival adds PACE-only service between objects and before
  READ_VRAM, TIME_MGR and the foreground PLAY_SONGS/SOUND_MAN pair. Insert
  polls only where R0/R15 are scratch, no queue cursor is live, and no VDP
  address/data transaction has begun. The later write-entry poll brings this
  to six boundaries; `drawpollcheck.py` executes all six and removes each poll
  in its mutation control.
- **Keep the sound pair together:** polling between PLAY_SONGS and SOUND_MAN
  let one skip on zero debt and the other run after the poll added debt.
  The rejected candidate accumulated 20 frames of PLAY_SONGS drift. Poll
  before PLAY_SONGS instead; background SNDRUN calls PSREAL directly.
  `sndpaircheck.py` injects an arriving frame with zero debt and requires
  both halves once. The preceding candidate is a negative control.
- **Measure visible effects, retain raw timing:** record active-display
  pattern switches separately from switches after the beam reaches affected
  pixels. Carnival's corrected build switched at lines 0/13 in two replays,
  but rendering before/after proved its first changed pixel was at line 64.
  This is a measured pre-gallery interval, not an allowance for tearing.
  Keep the zero unsafe-switch limit, raw counts, old failures and missing-poll
  mutation. Whole-band A-B-A and mixed-row counts remain separate checks.
- **Full queue:** QFLUSH clobbers R2/R3/R15. SATCK must preserve its pending
  length, destination and caller status. A lost length of zero decremented
  to FFFF and ran through RAM. `queuefullcheck.py` forces the full-queue path
  with 4-, 7- and 128-byte sprites and rejects the zero-length mutation.
- **Sound workspace re-entry:** retain the original 02EE poll for ordinary
  SOUND_MAN calls, including deterministic-harness poll metadata. Background
  sound already owns GLUE's return context; a nested BLWP corrupts that context
  before SNDIN can prevent another sound run. SNDWP (>A452, clear at boot and
  on return) guards this poll and selects fixed return LWPI instructions.
  `sndpollcheck.py` checks deferred background edges and ordinary frame delivery.
  `sndruncheck.py`, `sndtempo.py` and their mutations remain required.
- **Sound debt must not be discarded:** a long note parser can hold SNDIN
  over several serviced frames. Capping SNDDUE at two permanently loses
  updates and slows music. Retain the owed count while SNDIN/SNDBSY blocks
  re-entry, then consume it through the normal service paths. Carnival's
  assembled `snddebtcheck.py` tests both blockers and rejects the clamp;
  the unchanged `sndtempo.py` drift limit remains two frames.
- **Sound bank restoration:** CPU registers and workspace are not the entire
  interrupted state. Carnival's sound fragments left bank 6 selected after
  interrupting game code in bank 7; the correct return PC then resumed the
  wrong instructions. SNDRUN now saves CURBNK in SNDBNK (>F042, explicitly
  reserved) and restores the hardware selector plus CURBNK before returning.
  >AFFA is SNDDE, not free storage. `sndbankcheck.py` tests both callers/all
  16 banks and a missing-restoration mutation. The live sound checker also
  compares bank state and the far-call stack pointer.
- **No runtime code patching:** the sound return stores its caller in data,
  not SNRWP+2. `staticcheck.py` compares executed RAM opcodes and operands to
  the boot image; its mutation must be detected. Host-emulator implementation
  details do not run on TI hardware and are not hardware optimization claims.
- **Trustworthy comparisons:** production randomness includes video timing.
  Carnival's corrected `--stable-rng` installs before game entry, writes the
  active LD A,R helper workspace, and measures from the option keypress.
  Writing MAINWS early was ineffective because the helper overwrote it;
  discard older supposedly matched runs. `rngcheck.py` executes that store and
  rejects the wrong-workspace override. Keep production replays separately.
- **End-to-end transitions:** leaving the game-over loop is insufficient.
  Require a visible selection screen and a successful next-game start.
  Carnival's October 26 input policy keeps game over visible indefinitely:
  remove both the TI automatic return and the original idle blanking timer,
  retaining fresh-fire debouncing and replay/BACK/REDO controls. The focused
  GOTEST guard fits the retired timeout slot, preserving existing code layout.
  `gotest.py --idle` waits 70 seconds and rejects both automatic-exit and
  timed-blanking mutations; see `bios-ports.md` section 10.
  Carnival left DEFER enabled after gameplay, but its menu input loop never
  called WRITER: the final display-on command stayed queued. Patch 8110 sends
  the completed static menu before input polling; this does not change WEND.
  The regression compares all menu names with startup and plays another 300
  ticks. Its mutation drops menu completion. Scratchpad mutations must use
  the emulator bus (or the correct scratchpad offset), not the expansion array.

Use `Decompiled/Carnival/DESIGN.md` for artifact hashes and measurements.
Validate a frozen ROM/source snapshot; do not rebuild beneath running tests.

## Pitfall II resolved-work index

Use this index with the [round-by-round record](../../../Decompiled/Pitfall2/OPTIMIZATION.md),
[implementation contracts](../../../Decompiled/Pitfall2/DESIGN.md) and
[current validation](../../../Decompiled/Pitfall2/VALIDATION.md). The current
ROM hash, frozen snapshots and `build/optimization/process-ledger.json` decide
what shipped. Historical intermediate gains are not current performance claims.

| Resolved work | Reusable contract and evidence |
|---|---|
| Native copy/read/fill/clear, literal/RLE decoding, map/destination/pitch setup and four-way scratchpad comparisons (rounds 1–15) | Preserve caller ABI, flags, alternate registers, zero counts, overlap and VDP read-ahead; compare captured native entries and long exact replays. Per-run workspace switching lost more than it saved. |
| Four band-cache slots and full mutable-program keys (3b–9) | Four competing bands thrashed three slots. Include the complete second mutable program through `$71D7`; equal keys alone do not prove that cached or displayed bytes still exist. `check_bandcache.py` and `check_residency.py` cover both proofs. |
| Fresh-vblank publication and elapsed-frame pacing (13–15) | Count rendering time toward the original minimum, but still publish complete SAT/name-table state on a fresh blank. Removing the presentation wait is not an optimization. Keep modeled active-write, payload and pacing checks. |
| Static map bits, graphics expansion, pattern setup, music channel, precise residency invalidation and reclaimed RAM (16–28) | Generate immutable work from the ROM, invalidate once per bounded decoder transaction, bypass unrelated SAT/gap writes, and prove cache/stack lifetimes before reusing padding. Blanket invalidation was slower. |
| Prepared rows/bands, native asset-bank action sequences, direct keys/aliases, scene proofs and unrolled row uploads (29–35) | Enumerate every map/phase/platform pose, retain ordered dynamic drawing, guard the complete scene once, and fall back on a failed proof. `check_scene_matrix.py`, `check_renderer.py` and all 12,288 `check_prepared_bands.py` fixtures cover this design. That historical larger-cart authorization is superseded by Pitfall's explicit 128 KiB limit; it never authorized larger carts for another port. |
| River freeze and return-discarding bank wrappers (37–45) | Audit all six original control-flow families, including conditional calls and POP BC. Never add a bank continuation where the source discards a caller return. Check stack neutrality every update across both 900-update river routes, not only a short-run high-water mark. |
| Complete swimming/platform assets, fixed RAM programs, within-scene row reuse and enemy dispatch (38–45) | Expand complete tables and check actual lengths, masks, pointers and bank restoration. A perfect hash still checks the full source identity. Reuse RAM only within its proven lifetime and execute every dynamic action. See the earlier complete-asset section and asset/dispatch gates. |
| Native game-owned music/SFX, bounded 32-byte VRAM copies and constant seed stores (46–48) | Use the native-sound/bounded-copy section above. Preserve ordered PSG writes and original cadence; prove overlap/wrap behavior and poll only between complete transactions. Tests cover 1,885 sound states, 56 copy fixtures and 80 fixed-seed comparisons. Cartridge execution was already static; host opcode caches are not cartridge JIT. |
| Direct ROM band descriptors, native decimal score borrow, faster complete returns and fixed frame clears (49–53) | Use the direct-upload/return section above. Mutate the descriptor actually consumed, preserve every internal return/score step, check completion before batching another step, and keep normal movement single-step. Compare both held directions and equal normal-play prefixes. |
| Phase-wide fixed-pattern residency and finer placement search (54–57) | Use the RAM-ownership section below and accepted round-57 record. Keep immutable payloads in ROM and compact source identities in CPU RAM, invalidate every overlapping writer, preserve final-byte VDP effects, and measure all phases after placement. Source identity must distinguish different streams at the same destination. |
| Original-rate movement and bounded scenery omission (58–61) | Use the original-rate section below. Preserve cumulative two-frame movement deadlines, fresh SAT publication, unfinished-table ownership, renderer side effects and independent audio. Keep native scene, clock, river, exact and production-video gates. |
| Bank-qualified fixture exits, asset-window overflow and rejected row identities (59–63) | Compare `(bank, PC)` at banked exits. Verify generator size plus assembled symbol/data extents. Canonical immutable row IDs can avoid pixel comparisons, but round 63 still fails full-return timing; do not ship it based only on lower traffic. |
| Compact prepared-record banks (92–93) | See [Cartridge size without sacrificing runtime speed](#cartridge-size-without-sacrificing-runtime-speed). Reclaim only pages outside a completely audited bank lifetime, pin the source paths, guard executed instructions and restore both success/fallback banks. 1 MiB becomes 512 KiB while retaining the existing renderer; compare normal, water and complete-return timing. |

The early renderer contract also explains why simply retaining a decoded band
is insufficient: its mutable input key, CPU payload lifetime and VRAM residency
are three separate properties. Prepared immutable descriptors can eliminate a
CPU copy, while a resident hit can eliminate most VDP writes; neither permits
omitting ordered dynamic actions or final data-port effects.

Keep rejected findings accessible: three-slot thrashing; single-comparison
scratchpad loops; incorrect native leaf ABI; TI-heat placements that slowed
startup or failed it; broad invalidation; shared allocation that displaced hot
code; unsafe bank wrappers; word decoding with no useful gain; return batching
that regressed a normal holdout; and row/narrow-pattern caches that reduced
traffic but slowed normal play. Reconsider one only when its underlying
assumptions change. Do not hide a failed report behind a later checker rerun.

Resolved checker hazards include invalid uninitialized song fixtures, dead
flag comparisons, a mutation aimed at obsolete staging RAM, hooks that did not
fire after changing PC, negative tests whose fast path bypassed the subject,
and captured-VRAM restores retaining stale ownership. Require subject coverage,
known-bad mutations, completion markers and matching hashes. Frozen, disjoint
successful subsets may form a full suite; interrupted checks must be rerun and
cannot count as passes. Read profiling arrays passively so observation adds no
emulated memory cycles.

Always report both throughput improvement over a named accepted TI baseline
and current throughput as a percentage of the original (100% = original).
Separate equal-work normal routes, swimming-only intervals, approach-inclusive
river routes and the complete automatic return. For identical work, improvement
is `100 * (old_time / new_time - 1)`; this is different from percentage time
saved. State whether timing is modeled or measured on physical hardware.

## RAM ownership and display scheduling: the MSX-derived River Raid comparison

The [October 25 executable comparison](../../../Decompiled/RiverRaid/DESIGN.md#october-25-2026-comparison-with-super-river-raid-11)
studies the supplied TI Super River Raid 1.1 binary and our Coleco-derived TI
port. It does not assume access to the other author's source or attribute all
differences to the MSX original. Its sampled gameplay made no VDP data reads,
prepared terrain incrementally, and separated simulation from conditional
sprite construction/refresh. One 150-frame opening diagnostic counted 146
updates and 45 refreshes there, versus 111 updates and 111 uploads in our port.
These are diagnostic workloads, not synchronized gameplay-equivalence tests.

Apply the architectural lesson: keep authoritative logical data in CPU RAM or
immutable ROM tables; use the VDP for publishing completed pictures. Distinguish
logical terrain from visible and pending terrain before removing VDP reads or
deferring graphics. Reuse row pointers or compact residency identities where
they avoid extra copies. A byte-for-byte VRAM mirror previously slowed River
Raid; the proposed word/block arrays and explicit lifetime ownership are a
different design that still needs measurement. Preserve input, simulation,
collision and sound progression. Do not silently copy the other port's skipped
visual phases or reduced sprite refresh cadence.

Pitfall II round 54 is a useful negative control: 215 normalized row shapes plus
phase bits exactly represented 535 rows. Per-table RAM identities cut a measured
water interval's scenery writes from 30,772 to 7,616 (75.25%) and total writes
from 71,176 to 48,020 (32.53%). All 67 correctness gates passed, but a matched
normal route fell from 41.3793 to 40.6504 updates/100 frames (1.76% slower),
exceeding the unchanged 1% limit. Its water gains were only about 0.8–1.0%.
The candidate is rejected; retain the frozen evidence instead of presenting
write-count reductions as gameplay speed gains. Bookkeeping and hot-code
placement can cancel most of the saved port traffic.

Pitfall rounds 55/56 cached only the common water pattern/colour pair. Both
passed focused cache, invalidation and presentation checks, but normal seed 1
regressed 2.55% / 2.95% against round 53. Round 56 improved the two water routes
by about 3.2–3.3%, to about 68% of original speed, but is still rejected.
Keeping one phase fast is insufficient when ordinary scrolling uses others;
measure the added lookup/invalidation work on every writer and every phase.

The placement search itself had a 512-byte discontinuity after its 1,536-byte
hot-code margin. Continuing in 64-byte steps placed more useful code in RAM
and shared ROM without changing cartridge size. That alone did not rescue the
narrow cache: the round-56 holdout still failed. Record the chosen margin in
the budget and retain whole-game holdouts; a tighter packing is not proof of
speed. Do not infer that adding ROM banks supplies more always-visible code.

For an immutable pattern cache, track source identity as well as destination
and byte count. Revoke it before every overlapping direct, bulk, fill, copy or
interpreter write, including physical wrap. Audit the low-address and colour
pattern regions in interpreter guards; an old name-table-only fast rejection
can bypass new invalidation. Restoring captured VRAM in the test harness is an
external writer too and must revoke claims unless a test explicitly preserves
the matching VRAM. An unchanged transfer still writes its final byte to retain
the VDP data-port read buffer and final address. Test source changes at the
same destination, cold/warm paths, exclusive interval ends, wrap, canaries,
actual masked interpreter writes and missing-invalidation/final-byte mutations.

Preserve helper register contracts explicitly. A range invalidator needs the
exclusive end recomputed if alignment/type guards reused that scratch register
(caught in Pitfall's archived round-54 development build). Do not keep a pending
cache-key pointer in a register that an overlapping-name invalidator clobbers.
Nested `BL` helpers also need their return link saved without disturbing a
caller-owned workspace. Assembled-path fixtures must exercise the fallback as
well as the cache hit, since a working hot case can hide broken range setup.

### Carnival: rectangle queues and interrupt phase (October 25 follow-up)

Profile complete expensive ticks as well as averages. Carnival's `tickprof.py`
chains the real tick hook and separates intervals longer than 1.5 video periods
from busy work exceeding one period. It accounts for the final hook instruction
separately and asserts that its intervals reproduce the benchmark's cycle total.
The baseline's long ticks were dominated by gallery object drawing; shaving
the idle wait would not remove that work.

The gallery can enqueue one eight-byte rectangle reference instead of one
six-byte record per row. Keep width, starting VRAM address, immutable source,
height and source stride. The writer still sends the same rows in the same
order, including the final VDP address and read-buffer value. Queued VRAM reads
must expand rectangles too, including clipped intersections and later writes.
Carnival uses tag `>9000|width`; `>8r00|value` remains a register command.
Do not borrow a bit from a fill count: large fills can already use those bits.

Its fixed 32-store copy body enters at the last `width` instructions; no
instruction is created or patched at runtime. QFLUSH saves its return in R10,
allowing R11 to retain that entry address. Preserve the existing R5-R8/R9
contract within the rectangle loop (R9 is the enclosing flush's endpoint).
`rectcheck.py` executes all widths 1..32, four heights, two source
strides and six read intersections against ordinary row records. Mutations
corrupt the stride and omit an actual assembled store. The live fast-path
test compares expanded transactions, remaining RAM and alternate registers
when two correct queue representations have different bytes.

**Exercise the BLWP wrapper through RTWP.** Carnival C24 passed all 54
headless checks yet stopped at an incomplete gallery in Classic99. The
rectangle read overlay had borrowed HELPWS R15 for width. R15 was the saved
caller status; RTWP restored the width as status, accidentally enabling
console hardware interrupts. The direct-helper fixture checked memory and
video but skipped this return. C25 packs height/width into R1 and leaves
R13-R15 intact. `rectcheck.py` now executes QOVLK through RTWP and checks
the restored WP/status; that test rejects the unchanged C24 ROM.
`irqcheck.py` also checks the interrupt mask at every production instruction,
with a return-status mutation. Do not assume a headless model will reproduce
the downstream console interrupt damage. Preserve R13 (WP), R14 (PC) and
R15 (status) in any BLWP workspace, including callees reached through BL.
The visible original-emulator run is an independent acceptance gate.

Keep the cartridge budget explicit. Putting new helpers in the repeated
shared segment first required an extra cold bank, doubling packaging to
256 KB. Moving the rectangle copier and read-overlay code to reserved,
bank-independent RAM kept Carnival at 128 KB. Moving unchanged queue code
alone produced no speed gain. Its build now rejects images above 128 KB.

A smaller TEST_SIGNAL cache path computes `3*A` instead of reserving the
128-byte offset table. It is guarded by the cached last entry and timer-number
bound, and retains the original walk otherwise. Only INIT_TIMER may replace
the table base, and it must invalidate the cached bound. Reject a zero cached
base explicitly: timer zero plus a zero base otherwise equals the zero bound
and falsely passes the cache test. The original 7,175 fixtures supplied a base
even for their cold cases and missed this; captured BIOS calls found it.
The extended 8,967 comparisons include both words zero and a mutation removing
that actual guard, alongside warm, boundary and invalidation cases. Audit the
table-base ownership assumption again in another game.

Keep native scheduling tests separate from algorithm comparisons. Adding the
write-entry poll made a generic clone alone service a pending frame, changing
sound RAM before it produced identical queued writes. Carnival's fast-path
fixture bypasses that same entry poll on both clones, including fallbacks,
while comparing all other RAM and the drawing results. The assembled poll
test, production beam/queue/sound tests and mutation checks retain full polling.
The diagnostic `--include-entry-polls` preserves the old fixture. Do not mask
sound-memory differences or disable production polling to make this pass.

**Fewer cycles can expose a later display switch.** The first combined
candidate reached about 56.2 ticks/s but failed a production replay: its
pattern switch occurred at beam line 91 after the first changed pixel on
line 64. Faster timer work shifted a write-heavy path across vblank, and the
next translated-loop poll arrived too late. Service before N_WRVRAM opens
its VDP transaction, with R0/R15 scratch and no live queue cursor. Keep the
commit-only WEND/TICKD behavior and sound-pair boundary. Both 1,200-frame
replays then had zero active-display pattern switches. Retain the failed
candidate as evidence; do not relax the zero unsafe-switch gate to retain
its slightly higher score. Final acceptance still requires the frozen suite,
held-out performance, shooting and bear checks documented by the game.

### Carnival: applying the River Raid RAM/VDP findings

Measure CPU work around port traffic before allocating a mirror. Carnival's
`vramprof.py` hooks the real benchmark after warm-up, counts VDP bytes and
inclusive READ_VRAM cycles, and classifies reads by source/destination/caller
and pending-queue coverage. Its host-side queue inspection restores the cycle
counter: the emulator's memory/register accessors themselves charge cycles.
The profile must reproduce the uninstrumented workload's elapsed cycles.

In the C25 300-tick steady seed-1 sample, 1,893 VDP bytes were read and 6,597
written. Six gallery rows accounted for 72 reads of 26 bytes; the complete
read path cost about 1.9% of elapsed cycles. No full row was already covered
by pending writes, and only four single-byte collision reads were covered.
That evidence does not justify a general "read entirely from the queue"
shortcut or a full VRAM mirror. A different workload still needs its own
profile. The River Raid study's zero-read architecture depends on explicit
ownership of logical terrain; it is not a drop-in cache for arbitrary BIOS
reads. Keep visual cadence and animation phases unchanged unless authorized.

Two small alternatives use the existing RAM representation:

- **Batch mutable RAM copies.** An immutable body of eight MOVB stores reduces
  loop overhead in queued uploads. Enter at the last `count & 7` stores for
  the first partial group, then run full groups. Keep count 1..255 guards,
  even queue-end padding, BIOS output registers and commit boundaries.
  Gallery shifts use an odd RAM source and an even queue destination, so
  blindly replacing MOVB with MOV word copies is incorrect. `ramcopycheck.py`
  executes all 510 supported count/parity pairs and checks payload, header,
  queue ownership, unchanged VRAM and register results. Its negative control
  removes an actual assembled store; when the code is in cartridge space,
  mutate the active ROM bank, not the expansion-RAM array.
- **Reject disjoint queued writes early.** In the read overlay, calculate the
  queued entry's endpoint once and skip it if it ends at/before the requested
  start or starts at/after the requested end. Retain chronological overwrite
  order and clipping for intersections, including rectangles. TMS9900 C
  compares the source against the destination; operand reversal can silently
  invert the rejection. Retain the QOVLK-through-RTWP return-context test.

C26 passed 58 production gates, the bear suite and visible Classic99 play.
Its three-seed matched steady rate rose from 56.2452 to 56.6982 ticks/s
(0.8054%); six loading-inclusive seeds improved 0.3456% overall, with one
0.1476% slower seed within the unchanged 1% bound. The matched diagnostic
retained the same VDP read/write counts. Final hashes and evidence remain in
Carnival's DESIGN.md and validation ledger. Do not infer a 60-update rate
from a local copy-loop improvement or a lower VDP byte count.

### Carnival resolved-work index

Use this index when carrying all resolved work into another session. The
linked sections contain the implementation contracts; Carnival's DESIGN.md
and experiment ledger retain artifact hashes, workload definitions and the
accepted/rejected status of each build.

| Resolved area | Canonical guidance and executable evidence |
|---|---|
| Register-exact native OS7, ROM row references, sprite shadow and sound scheduling | [BIOS ports](bios-ports.md), [OS7 integration](os7lib/README.md); `reglive`, `routest`, `fastpath`, `qcheck`, `sndclose` |
| Build-time RLE expansion, fixed gallery descriptors, inline clipping and native pointer loops; immutable cartridge code | [Static work and freeze regressions](#carnival-static-work-and-freeze-regressions-2026-10-25); `assetcheck`, `gallerycheck`, `routest`, `staticcheck` |
| Elapsed-frame credit and bulk fill sizes/wrap | Same static-work section; `framecheck` and its missing-credit mutation |
| Completed-batch publication, six safe frame polls and sound-pair ordering | Same static-work section and [rectangle/phase follow-up](#carnival-rectangle-queues-and-interrupt-phase-october-25-follow-up); `commitcheck`, `drawpollcheck`, `sndpaircheck`, `flushtrace`, raced `flashcheck` |
| Full-queue freeze, background workspace re-entry, interrupted ROM-bank restoration and retained sound debt | Same static-work section; `queuefullcheck`, `sndpollcheck`, `sndbankcheck`, `snddebtcheck`, live sound/tempo checks |
| Complete game-over menu and next-game start; delayed bear collision confirmation | [BIOS ports](bios-ports.md); `gotest`, `bearverify`/`bearhit` |
| Rectangle references, immutable row copier, compact guarded timer cache, BLWP return context and 128 KB placement | Rectangle/phase follow-up; `rectcheck`, `check_timers`, `irqcheck`, build budget gate |
| River Raid comparison applied to queued RAM copies and disjoint-read rejection | [RAM/VDP application](#carnival-applying-the-river-raid-ramvdp-findings); `vramprof`, `ramcopycheck`, existing rectangle/queue checks |
| Matched RNG and complete-tick cost accounting | Static-work and rectangle/phase sections; `rngcheck`, `cspeed`, `tickprof` |

Keep the rejected approaches discoverable: the larger unrolled gallery hurt
placement; the large timer offset table regressed speed; moving unchanged
queue code into RAM gave no gain; polling between the sound pair lost updates;
clamping sound debt lost music; faster drawing without the write-entry poll
switched after changed pixels; a zero-base timer cache returned a false hit;
and borrowing BLWP R15 produced an incomplete gallery despite passing the old
headless suite. The River Raid byte-for-byte mirror and Pitfall II residency
cache also show why fewer VDP accesses alone are not acceptance evidence.

## Accepted Pitfall II phase cache (round 57)

The retained implementation extends immutable 48-byte pattern/colour residency
to all sixteen eligible phase destinations. A 64-byte CPU-RAM source-identity
table occupies audited cache padding; original-derived payloads stay in ROM.
Name/SAT-only writes bypass the pattern invalidation scan. Every overlapping
writer, fallback, wrap and captured-VRAM restore revokes the relevant claim.
Source replacement and final-byte VDP side effects are required, not optional.

All 67 gates pass, including 192 byte/boundary repairs, 244 interval/wrap cases,
natural claim/write audits and missing-invalidation/final-byte mutations.
Compared with accepted round 53, normal play improves 3.5–8.7%
(6.28% aggregate), reaching 84.7–88.3% of original
(86.69% aggregate). Water improves 3.7–3.8%, reaching
68.2% of original. The already-accelerated complete return improves
2.0%, reaching 138.1%
of original return speed. Report these separately; ordinary play remains below
the original. Measurements are emulated hardware timing, not physical testing.
The water-route numbers include the approach. Swimming-only throughput improves
4.7–4.8%, at 65.1% of original, over 618 identical intervals.
The matched 120-update river sample reduces total VDP writes from
71,176 to 60,037
(15.65% fewer).

SHA-256 `f456024c786c699f16168a9a7c4171e5c366aefb44973d8fc03895869c289090`; evidence is in
`Decompiled/Pitfall2/snapshots/pattern-phases-r57` and its canonical validation
report. Current live visual/listening review was blocked by Computer Use app
approval timing out. The unchanged native sound engine and static execution
remain; this pass neither removes a cartridge JIT nor introduces one.
<!-- end Pitfall II round 57 -->

## Pitfall II: a 30 fps target is not Joust's 30 Hz conversion

Historical round-57 feasibility analysis. The original-rate implementation
and measured results below supersede its feasibility-only status.

Check the original simulation and publication rates before applying Joust's
historical alternate-drawing technique. That Joust version alternated
upload/flush and drawing over 60 Hz logic ticks. Joust's later
[cohesive dt=2 conversion](vdp-ram.md#joust-cohesive-retiming-findings-2026-10-26)
supersedes it with one world update and picture every two physical frames.
Pitfall II already targets roughly 30 normal logic updates
and pictures per second; every-other-update drawing would instead target
15 pictures/second. A 30 fps cap cannot repair missed two-frame deadlines.

Accepted round 57 averages 26.05 nominal fps in matched normal play and 19.38
while swimming (60 Hz normalization). That is 86.69% / 65.13% of original
speed, after gains of 6.28% / 4.70–4.81% over round 53. Restoring the original
rates needs another 15.36% / 53.53% throughput gain. These are derived from
existing hash-bound measurements, not a new 30 fps implementation or guarantee.
The sampled river renderer accounts for 51.08% of inclusive stage time;
publication's 18.97% includes waiting and is not wholly removable work.

The transferable principle is separate simulation, graphics preparation and
publication while preserving their data dependencies. Pitfall already has
hidden name tables; adding another buffer or skipping every other drawing is
not automatically useful. Investigate changed-region preparation and coherent
two-frame publication, retaining CPU-side state, every logic/sound step and
the existing cache ownership proofs. Require per-update deadline distributions,
original-ROM state comparisons and whole-game holdouts; averages alone cannot
prove steady 30 fps. See the [game's feasibility review](../../../Decompiled/Pitfall2/DESIGN.md#30-fps-feasibility-and-the-joust-comparison-2026-10-26)
and `build/optimization/30fps-feasibility.json`. The round-54 row cache remains
rejected; a new architecture must address its overhead and hot-code displacement.

## Pitfall II original-rate movement (rounds 58–63)

The user selected restoring original Coleco movement speed, not fixed double
velocity. Accepted **round 61** is SHA-256
`5f6a3d8e50d9b1c08a75672429633588c900a7fb50167ae94ef03e961e82fa4d`.
Compared with accepted round 57, five equal 300-update normal routes improve
13.19–18.03% (15.36% aggregate) and reach **100% of original movement speed**.
Swimming itself improves 11.03–11.16%, reaching **72.32–72.40% of original**,
about 21.5 updates/second at nominal 60 Hz. Including the approach gives a
different result: +13.69–13.78%, at 77.56–77.63% of original. The authorized
complete return takes 5.126 seconds versus 5.076 previously and 7.012 original:
0.97% less throughput than round 57, still 136.80% of original. Its elapsed-time
increase stays within the unchanged 1% regression bound. These figures are
emulated hardware timing, not physical-hardware measurements or a guarantee
of steady 30 full scenery redraws/second. The current validation report and
`build/optimization/motion-metrics.json` contain the paired evidence.

**Use an original-rate movement clock, not doubled deltas.** Normal PWAIT
advances the cumulative deadline by two serviced video frames per update.
When at least three frames late, the next update can omit scenery preparation;
never do so twice consecutively. Discard debt of eight or more frames after
startup/pause instead of bursting through overdue work. All publications still
use a fresh blank and a full 124-byte SAT payload. Every normal collision,
player/enemy and logical-counter step runs once. Music and SFX remain on their
video interrupt clock; there is no doubled sound service. Victory keeps its
old two-frame minimum because its counter drives sound, and automatic return
keeps its separate authorized one-frame/two-player-call policy. Exact replay
retains the original behavior. Cumulative rate and interval distributions both
matter: achieving the original average does not imply even two-frame gaps.

**Retain non-visual renderer effects and table ownership.** Simply bypassing
CB3B2 loses platform movement, background sprites and scroll maintenance.
The main-loop-only split preserves platform phase/direction and bounces,
background SAT records across every visible map band, waterfall sprite-pattern
updates and the original scroll-maintenance tail. After omitted scenery,
republish the visible table rather than flipping to unfinished hidden content.
The next full update prepares that table before a later flip. Keep the general
CB3B2 entry intact; the optimized entry uses cold bank descriptors and FARCALL/
FARJV. Four words in audited slot-2 padding (`>AD94..>AD9B`) hold clock/mode
state. The native helper borrows the idle presentation workspace while keeping
BLWP return context. Renderer registers/scratch are dead at the specific main
join, not necessarily for other callers.

Validation includes all **75 gates**, four 300,000-tick exact replays, 1,122
assembled clock cases and mutations, 15,360 original/native scene fixtures
covering all map indices and platform bounces, and a 900-update river comparison
with 492 full scenes and 407 scenery omissions (22 with camera maintenance).
Every compared trajectory, background sprite, sprite pattern and completed
scenery picture agrees. Independent production checks reject consecutive
omissions, excessive movement rate and unfinished-table flips, while retaining
zero modeled active-display SAT/table writes and complete sound cadence.
An additional 320 register-poison cases exercise sampled original renderer
exits; label this sampled liveness evidence, not a whole-map proof. The normal
prefix and complete-return comparisons retain the existing per-phase limits.

**Static expansion still needs bank extent proof.** Three waterfall streams
bring the fixed asset set to 27. The two frame alternatives and overlapping
sprite stream must preserve their original order. Round 60's 256-entry hash
overflowed the 2 KiB asset window; the listing parser silently dropped bytes
beyond `>8000`, so inspecting only parsed addresses falsely passed. Native
asset comparisons caught the error. Reject that candidate's favorable timing.
Round 61 uses a 128-entry rotate-right-by-ten hash with full source-key checks,
asserts generator size, and verifies FASREC/FASEND bounds and actual listed data
length. A hash collision check alone does not prove assets fit the bank.

**Banked fixture exits need both coordinates.** A round-59 frame-clear check
stopped at the correct numeric PC in the wrong bank, halfway through the clear.
`routest.py` now accepts `(bank, PC)` and rejects bank-window numeric-only stops.
Retain original output/canary comparisons and the correctly sized corruption
hook after adding the motion region. Do not weaken assertions to accommodate
an incorrectly selected endpoint.

**Row identities are a rejected follow-up, not shipped code.** Round 62 added
128 bytes of row-owner words in existing padding, initially keyed by prepared
source. Reversed TMS9900 `C` operands made invalidation return early; the positive
external-writer repair test caught it. C compares source relative to destination.
Round 63 fixes this and stores canonical classes in seven spare bytes of each
immutable prepared-record header. Uniform upper name bits are combined with a
class of normalized row bytes; mixed rows have distinct classes. The generator
proves every complete key maps to exactly one 32-byte payload, including equal
rows in different records. This avoids VRAM readback and pixel comparisons.
Every overlapping generic/interpreter/decoder transaction writer still revokes
claims, captured VRAM restores clear them, and the final byte retains cursor/
read-buffer semantics. Owner storage must not overlap motion words, mutable
payloads, descriptors or other cache keys. Warm reuse, external repair, a real
missing-invalidation mutation, 244 interval/wrap cases and natural claim/write
audits pass after the correction.

Despite correct ownership, round 63 takes 5.176 seconds for the complete return,
1.97% longer than round 57, beyond the unchanged 1% bound. Its river scene probe
improves swimming to 74.48% of original (+14.35% vs round 57), and all five normal
prefixes reach original speed, but it remains **rejected for return regression**.
Invalidation overhead and displaced hot code count in the end-to-end budget.
This differs from round 54's pixel-comparison cache, but neither is accepted.
Reconsider only with a changed cost/placement design and all phase holdouts.

Round 58's stationary-camera split and round 59's scroll-tail split are
superseded; round 60 is rejected for asset corruption; round 61 is accepted;
round 62 is rejected for invalidation; round 63 is rejected for return timing.
Artifact hashes and completion reports live in Pitfall's OPTIMIZATION.md and
process ledger. The production ROM has normal starts and is hash-matched in
the owned Classic99 launcher; current capture was black and activation failed,
so live visual/listening review remains incomplete. Do not report a successful
launch/hash check as evidence of visible playback or audible music.

### Pitfall II return-camera correction and audio/title contracts (2026-10-26)

**Correction to the return claims above:** round 61's player-only batching is
unsafe on deep vertical returns. The original camera moves two pixels once per
loop; two player calls can move four. The byte holding screen Y eventually wraps
while world position, checkpoint termination and score still match. A named
five-level upward-return fixture reproduces the floating pose: the old TI build
ends with unwrapped Y -200 and displayed Y 56; the original ends at Y 80, on the
checkpoint. Earlier first-return trajectory tests excluded camera and screen Y
and therefore missed this defect. Do not restore unrestricted player-only
batching, even if its timing is favorable.

A conservative guard permits the extra player call only when $7031 requests
no scrolling. Candidate `camera-audio-menu-r64` passes upward/downward deep
returns, final camera/player state, independently evolved scenery, and a jump
after return. This is a correctness reference, not evidence that long vertical
returns are fast. A faster design must advance camera phases with player steps,
retain the intermediate B3D4 pattern/colour maintenance, and handle the camera's
band-alignment stop: if the camera did not execute its extra phase, a newly
scrolling player cannot take an extra step. Measure this separately from normal
movement and sound clocks. Final release timing belongs in the game's current
VALIDATION.md, not an extrapolation from the old broken return.

**Music/SFX balance belongs at the native output boundary.** Preserve the
original channel records, note/counter clocks, pitches, noise commands, register
exits and ordered writes. The requested production mix adds six attenuation
steps to music (cap at 14), and preserves 15 as explicit silence. The original
policy of mapping every audible effect volume to zero was incorrect: it erased
the gold/checkpoint/landing/balloon envelopes. Effects 2–5 already peak at zero;
retain all their attenuation values. Jump alone has constant attenuation 4 and
can receive a fixed four-step gain at its dedicated output site. PACE=0 retains
the exact original byte stream. Test all 16 attenuation values and all channels, initialized song
states, rhythm, all five effects, effect ownership and music-off behavior.
The ordered production oracle transforms only volume bytes according to the
original writer's music/effect ownership; it never patches the original ROM.
Also compare complete effect lifetimes and interruptions: a one-tick test whose
oracle implements the same wrong gain policy cannot establish sound fidelity.

The October 27 gold-pickup report demonstrated that blind spot in the shipped
r88 mixer. `check_sound_sequences.py` rejects that artifact with 2,640 bad
updates across 9,975 original-ROM sequence fixtures. It discovers each effect's
peak over its complete original lifetime, then permits only that constant gain.
All five commands are covered: jump (1), treasure/gold (2), balloon pop/release
(3), landing (4), checkpoint (5). The six gameplay request sites are audited so
a new trigger cannot silently escape coverage. Five song selections, music
mute, pause/resume and every ordered effect-interruption pair are exercised.
Keep its flattened-gold and wrong-noise negative controls. User listening
confirmed the repaired gold sound; ordered PSG comparison is the evidence for
the other effects, not a claim of physical-hardware listening.
For the hot output path, effects that already peak at full volume need no
normalization work: send their original byte directly. Keep the one constant
jump gain in a dedicated helper instead of branching on effect identity for
every fading sample. This saves mixer instructions without new state storage, skipped
sound ticks or reordered writes. It is a correctness repair with unchanged
measured water/normal/return throughput versus r88, not a claimed speed gain.

**Title controls need the game's character encoding and physical matrix.**
Pitfall's title names are ASCII OR >80, not raw ASCII. TI keyboard STCR row 0
is bit >0100 in the byte-high register; M is column 3, row 0. Debounce M without
dismissing the title, retain the held-entry/release guards, and carry the original
$7029 bit 1 into gameplay so effects remain enabled. Title state words at
>AFD4 and >AFD6 sit outside the fixed-pattern keys ending at >AFD4 exclusive.
Pitfall's later title-credit layout moves both the name-table picture and its
two black masking sprites up two rows. Perform that layout once per title
entry; music-toggle redraws must not shift it again. Its bounded VRAM copy is
banked, so the title uses FARCALL and restores its caller bank. The title gate
compares the assembled display with the original pre-layout snapshot through
multiple toggles. This startup-only layout adds no gameplay rendering work.
It can still change code placement and the gameplay-entry frame phase. The r91
title build's two water routes took
1372/1373 frames versus r89's 1367/1367 (0.36%/0.44% slower; 90.82%/90.75% of
original speed). Its normal-route setup grew from 126 to 128 frames, and 1891
original-address labels moved in the assembled layout; their separate timing
contributions have not been isolated. Keep the existing per-phase 1% limits
and report the measured cost instead of assuming that unchanged gameplay source means
unchanged timing. The old r89 title is rejected by the new layout comparison.

The reported short red strip just above the left edge of the Activision logo
also appears in the unmodified Coleco water-route capture
(`scratchpad/motion-r63-z80-end.png`). Compare such details with the original
before erasing scenery or attributing them to an optimization. This observation
does not excuse the separately reproduced return-camera corruption.

### Pitfall II row streams, return scenery and proposal review (2026-10-27)

Read the current `Decompiled/Pitfall2/VALIDATION.md` for the qualified artifact;
intermediate round numbers below identify mechanisms, not release approval.

- The round-63 row cache was revisited only after changing its cost. Round 67
  removes the speculative VDP address setup before checking row ownership and
  omits the final-byte rewrite when the last changed row already supplied it.
  Round 70 also keeps consecutive changed rows in one autoincrementing VDP
  stream. A hit breaks contiguity; the next miss must establish a fresh address.
  `check_row_owners.py` deliberately suppresses that first setup and must fail.
- A row identity fits a word: canonical class in the high byte and the first
  name's upper two bits in the low byte. Write that low byte directly into
  **HELPWS R3's low byte**, then mask the word; do not shift eight places just
  to move a byte between halves. This is workspace-specific, not a general
  permission to hard-code main-workspace addresses in BLWP helpers.
- Owner tables use `>AB94-ABD3` and `>AD9C-ADDB`, already reserved cache padding.
  Immutable row pixels remain in ROM. Two 64-byte identities avoid a 1,536-byte
  mirror of the two name tables. Keep all writer, wrap, final-address/read-buffer,
  original-output and external-repair checks; memory savings alone prove no gain.
- The corrected camera return can use the existing bounded scenery split:
  retain both camera/player phases, intermediate pattern/colour maintenance,
  platform/background-sprite state and a complete fresh SAT; alternate full and
  reduced scenery preparation. Normal movement and sound keep their clocks.
  A former test prohibited *all* return scenery omissions. The new named
  `PWRWAIT` exception instead rejects consecutive omissions, stale-table flips,
  duplicate-frame uploads, return clock debt and victory omissions. Deep up/down
  landing and post-return jump oracles remain mandatory.
- Music mixing can use dead R8 instead of saving/restoring the live R15 channel
  pointer. Prove rhythm return/effect-entry flags dead in the original control
  graph, restore the channel's original final flags, and retain all ordered PSG
  fixtures. A smaller helper can still change placement or frame rounding;
  report whole-game measurements rather than its instruction savings.

The guideline review covered native BIOS/game sound, ahead-of-time assets,
planar/geometry tables, ownership caches, controller scan caching, native bulk
transfers, scratchpad loops, translation peepholes, placement, RAM collision,
resumable preparation and independent presentation. Pitfall already implements
the first groups. The measured follow-up targets row publication and return
scenery. A full VRAM mirror, extra sprite omissions, faster audio clocks and
blanking the display during play are not implemented shortcuts. Expanded TI
RAM is already substantially occupied by translated code and source tables;
nominal free byte totals are not contiguous allocatable space.

Research against the [TI TMS9918A data manual, sections 2.1.3–2.1.6](https://peacockmedia.software/tms/TMS9918datasheet.pdf)
confirms that sequential writes reuse the auto-incremented address and that
active-display access may require eight microseconds. Avoid redundant setup
and transfers; do not simply remove transfer spacing. The existing scratchpad
copier remains unchanged by the row-stream work.

An original-ROM-only 900-update probe found 678 consecutive identical
backgrounds, including 422 of 618 swimming scenes. This supports investigating
whole-scene identity reuse, **not** assuming that unchanged coordinates prove
unchanged pixels. Reuse must track pattern/colour and name-table writers,
physical wrap, platform pose/advance, camera alignment and displayed-table
ownership. Compare every reused visible picture against independently evolved
original pixels; do not classify it as an intentionally omitted scene and skip
the comparison. `tools/probe_scene_identity.py` records the research separately
from any cartridge speed claim. Round 71 is the bounded follow-up experiment;
consult the game's validation/ledger before treating it as qualified.

**Qualified follow-up:** `scene-reuse-r71` (`b9b2821f33128703cba963fccf19f24502f2135c35f3a91b743b1f678a4047ad`) completed all 79 gates.
Water is 82.03-82.08% of original, +13.30-13.50% versus r61;
normal prefixes remain 100%. Natural return is 4.3244s,
+18.53% versus r61 and 162.16% of original.
Deep camera fixtures are separate in the game's VALIDATION.md. Full original
water speed remains unmet. The whole-scene oracle compared
309 exact reuses with zero differences;
this is actual runtime evidence, separate from the earlier source-only survey.

Water-entry visual reports require evidence beyond completed-state equality.
At r71, three directed background scanline traces did not reproduce Pitfall's
later black-line report. The sprite-inclusive demo investigation below resolves
both reported cases. Retain each probe's limits in VALIDATION.md. Sample visible
intermediate frames, distinguish background from
sprites and display enable, and record fetch-model limits; neither a clean
completed scene nor an approximate scanline trace proves all transient pixels
correct. Do not disable an otherwise qualified cache without reproducing the
defect or obtaining a concrete failing fixture.

Scene key/valid/hit words use `>ABD4-ABDD`, after the low row-owner table and
before cached descriptors. Guard stationary swimming, camera map/alignment,
fine phase, platform pose and advance. Name/pattern/colour writers and restored
external VRAM revoke the claim. SAT and sprite-pattern traffic does not. The
explicit hit marker makes the oracle compare the displayed picture even when
the full renderer is bypassed. Repeated exact reuse is distinct from consecutive
intentional omissions; do not relax the latter's clock/publication tests.

### Pitfall II water masking sprites and transfer ownership (2026-10-27)

The later unattended-demo reproductions **do** explain the reported narrow
black strips. The initial water entry had 16-by-2-pixel gaps and the waterfall
descent had 16-by-1-pixel gaps. Background-only pictures matched the source;
the missing cyan pixels came from background sprites whose coordinates had
advanced while the displayed name table was intentionally held. Completed-state
equality and background-only scanline probes cannot detect this mismatch.
Compare sprite-inclusive intermediate pictures with original beam pictures
having the same tile background. Preserve the separate full-screen map-transition
blanking case rather than counting it as this defect.

Treat scenery and its masking sprites as one publication unit. Keep the last
complete picture's 16 background SAT bytes in reserved RAM, and publish them
with that picture when scenery is held. The first 108 SAT bytes (Harry and
enemies) stay current. Pitfall's direct publisher sends 108 current bytes and
16 saved bytes in one autoincrementing VDP stream; all 124 bytes still finish
inside fresh vblank. Logical SAT RAM remains untouched. This is cheaper than
swapping those 16 bytes into RAM before upload and restoring them afterward.
Moving the swap after the fresh edge alone did not recover the lost throughput.
`blackline_publication_gate.py` independently remembers complete-picture sprites,
checks fresh foreground bytes and logical RAM, and rejects redirecting the held
transfer to the newly advanced coordinates. `check_sat_publication.py` checks
the original register/flags ABI, byte order, cursor and read-buffer effects.
Exact replay keeps the original transfer primitive. Consult the game's current
VALIDATION.md for the qualified ROM, measurements and remaining model limits.

The saved background SAT occupies **>AFEA-AFF9**, after the prepared-band
descriptor at slot+480..489. The three Harry pattern identities occupy only
**>AFDA-AFDF**. Do not mistake the entire tail of a cache slot for unused RAM:
the descriptors split its padding. Source identities for the three fixed
32-byte destinations >3FA0, >3FC0 and >3FE0 suppress unchanged swimming uploads
while retaining the final VDP byte/address/read-buffer contract. Every overlapping
writer must revoke them, including the old six-span direct walking writer,
masked/literal/repeated interpreter runs, larger overlapping assets, wrapped
VRAM writes and externally restored VRAM. The interpreter's former sprite-range
invalidation exemption becomes unsafe when adding sprite ownership. For bounded
1..128-byte runs wholly within the sprite tail, directly clearing the three tiny
keys is cheaper than entering the general scenery invalidator; crossing/wrapped
ranges retain the general path. Boundary, masked-writer and mutation tests are
mandatory. A previously passing water route did not expose the missing masked
writer guard in the first experimental cache.

Also correct the earlier whole-scene ownership claim: the 48-byte fast asset's
FASCHECK miss had bypassed RCRANGE and left MCVALID valid. Clear MCVALID on the
miss only; an actual resident hit leaves the picture unchanged. An assembled
reproducer and a missing-clear mutation prove this contract. This was a separate
defect: repairing it alone did **not** remove the narrow water strips.

Once the exact scene key proves unchanged camera/map alignment, fine phase,
platform pose and no pending platform advance, its saved background sprite
geometry can also replace the four-band geometry walk. Retain current-phase
waterfall pattern animation and scroll maintenance. Compare the restored logical
records against the unmodified complete renderer, including all map rows and
waterfall cases; a missing-copy mutation must fail. Never apply this shortcut to
an ordinary coarse omission whose geometry has changed.

### Qualified Pitfall II water follow-up: rounds 72–79 (2026-10-27)

Qualified artifact `sat-fixed-r79`, SHA `5de3f4f06edf548eee62fa9f046488a394fa72eb422f135a66220696f8e8f3b7`. All 83 gates pass.
Swimming improves 9.84–9.91% versus r71 and reaches 90.16–90.16%
of original. Normal per-phase holdouts pass unchanged; full water speed remains
unmet. Natural/deep return measurements and correctness costs are in VALIDATION.md.
Both reproduced demo black-strip cases are fixed by matching held scenery with
its masking sprites. Source gameplay RAM and sound clocks remain unchanged.

Natural return is 4.3244s and 162.16% of original:
left-held throughput is unchanged versus r71; right-held is 0.39% lower.
Synthetic deep up/down return throughput is 0.72%/1.48% lower than r71, at
102.16%/108.49% of original. The four-frame deep-down cost is a documented
display-repair tradeoff, permitted by the measurement contract above. The
existing deep-return r66 reference and 1% limit remain; all normal per-phase
holdouts pass their unchanged limits. Do not describe this as a universal gain.

- Round 72, `fine-placement-r72`: **superseded**. Finer hot placement: water 1507 frames; focused checks passed.
- Round 73, `swim-pattern-r73`: **reject-invalidation-defect**. Sprite residency missed overlapping literal/repeat decoder writes; new positive repair gate rejected it.
- Round 74, `water-alignment-r74`: **superseded-correctness-reference**. Correct decoder invalidation and held-background sprite swapping; expensive water/return paths.
- Round 75, `blank-alignment-r75`: **superseded**. Move swap after fresh blank; both black-strip cases fixed, but unnecessary copy overhead remains.
- Round 76, `swim-invalidation-r76`: **superseded**. Bounded sprite-only decoder clears three keys inline; restores most return performance.
- Round 77, `split-sat-r77`: **superseded**. Direct 108+16 SAT publication: water 1391 frames; both visual cases fixed.
- Round 78, `scene-state-r78`: **reject-normal-transition-regression**. Exact-scene geometry reuse saves 1.48% busy cycles, no frame gain; seed-3 transition 57.68ms versus 39.98ms r71 fails unchanged 1% gate. Broad qualification stopped.
- Round 79, `sat-fixed-r79`: **accept**. Fixed full-SAT path avoids generic transfer setup, unrolls retained geometry copy; all 83 gates and normal per-phase holdouts pass.

The final full-SAT fast path saves 16 masking bytes with eight unrolled word
copies, then writes 124 bytes directly. Held publication writes 108+16 bytes.
Fixed validated SAT destinations need neither generic RAM mapping nor scenery
residency invalidation. Preserve exact mode's generic original primitive and
prove all registers, flags, source RAM, write order and final VDP state.

Run normal per-phase comparisons before lengthy qualification: r78's average
speed concealed a one-frame transition regression. Do not accept fewer VDP
writes or lower busy-cycle totals as proof of faster gameplay. Keep failed
candidates and report visual-correction costs separately from optimization.

### Pitfall II swimming proposal validation (2026-10-27)

Fixed, source-proven upload sequences can bypass generic descriptor hashing,
argument mapping and repeated bank selection. Pitfall's right-swim sequence
writes three disjoint 32-byte destinations; the left sequence writes one.
Generate descriptor offsets from the same immutable asset list, select the
asset bank once, and retain each slot's existing ownership key. A warm slot
still writes its final byte to reproduce the VDP cursor/read buffer. Preserve
original saved-stack locations, nonlocal return pops, interpreter bookkeeping,
caller bank, registers and flags. PACE=0 retains the literal original sequence.
`check_swim_upload.py` compares cold, warm and externally repaired sequences
with original code and rejects a stale ownership claim. Small helper-cycle
savings alone do not establish faster movement.

The enemy-loop experiment retains all four original records, checked dispatch,
handler calls/stores and the poll at A596. A fixed 48-byte clear and fewer
pointer/count shuffles remove overhead without skipping enemy updates. Odd
record fields still require byte accesses. Clear the byte-high accumulator's
low byte explicitly; do not rely on a previous translated helper to do it.
Keep isolated A56F comparisons, dispatch alias/mutation fixtures and full exact
replays. The combined directory/enemy candidate failed normal holdouts; test
such mechanisms independently before concluding that either is worthwhile.

The proposed RAM band directory was implemented in prepared-slot padding:
24 packed descriptors cover four phases and six poses. Only prepared kind 2
may expose that directory; a generic fill reuses those bytes for its mutable
key. Revoke the old slot kind before overwriting it, and publish its row tag
last. All descriptors and wrong-phase mutations were checked. Nevertheless,
r81's cold-fill cost and r83's swimming-only variant failed unchanged normal
per-phase limits. They are rejected, not production features or permission
to reuse those bytes in the current build.

Partially overlapping immutable waterfall assets cannot own their entire
spans independently: >3F20..3F67 and >3F60..3F9F disagree in the shared eight
bytes. The experiment owned only the independent prefix/tail and rewrote the
overlap on every original call. Warm pairs used 17 data writes instead of 136,
with original output and final VDP state at each call boundary. General,
literal/repeat, masked and wrapped writers still invalidated the independent
claims. This passed its overlap and broken-writer tests but failed whole-game
normal timing. Moving its continuation beside data in the already-selected
asset bank preserved RAM/hot-code capacity but did not rescue that result.
Rounds 84-86 remain rejected; fewer VDP writes are not proof of faster play.

Exact scene reuse and a coarse scenery omission need distinct histories.
A scheduler-only distinction (r85) changed no measured water frames because
pending omissions bypassed the exact-identity test. The follow-up checks the
complete scene key before consuming that allowance, and permits a later
coarse omission only after full or proven-exact scenery. Return/victory rules,
two-frame movement deadlines, pause-debt reset, fresh publication and the
unfinished-table guard remain. Extend the renderer fixtures to pending=0/1,
compare every exact reused picture against the independent source renderer,
and retain mutations rejecting consecutive *coarse* omissions. Qualification
and speed of the follow-up are recorded in the game's VALIDATION.md.

For profiling, a nearest-CALL-address grouping is a heuristic, not a call
stack. Cartridge entry/main-loop instructions below the first cartridge CALL
target must not be charged to the last BIOS routine (formerly 1FDC). Use
bank-qualified, non-invasive stage hooks for inclusive renderer/player/enemy
costs and separate the mandatory publication wait. Confirm instrumented and
plain replays have identical cycles, frame totals and trajectories before
using that profile. Original-ROM records and frozen candidate hashes remain
the source of speed claims.

Visual regression summaries must require the candidate to cover the known
reproduction's update window. A clean waterfall capture at updates 1200-1250
did not cover the prior failing 1250-1310 window. `blackline_summary.py` now
requires every original reproduction update in the candidate capture; the
wrong-window negative case fails before the matched-window comparison passes.
Fewer sampled video frames are legitimate when the same updates execute faster;
omitting the problematic updates is not.

### Qualified swimming follow-up r88 (2026-10-27)

Accepted `exact-first-r88`, SHA `8e99933ff8ea6336923ac569d582729778fce8af663374b880db94d416ddd87b`: all 84 gates pass.
Swimming improves **1.10% versus r79**, reaching **91.15% of original**.
Normal prefixes remain **100% of original**, with unchanged per-phase holdouts.
Natural and deep returns pass their r79 1% limits; detailed ratios are in
VALIDATION.md. Both reproduced black-strip cases remain absent. Full original
water speed is still unmet.

r87 isolated the native enemy loop from rejected cache changes: 1371/1372 water
frames and passing normal holdouts. r88 adds exact-scene priority: 1367/1367.
It retains the fixed swimming upload and native enemy work, and rejects the RAM
directory, waterfall ownership and scheduler-only variants. No speed claim is
inferred from fewer VDP writes. Profiling remains dominated by full scenery work.

## Star Wars: hand-written natives, boot-built VRAM shadows (2026-10-29)

`Decompiled/StarWars` (trench 11.4 -> 14.8 passes per 100 frames, r17-r20;
ColecoVision 20.9). Its DESIGN.md has the per-round details.

- **A native rewritten from translated code must keep the translator's
  masking.** The translator chooses each indexed access's addressing from
  the profile (`RAMMIR` masks with `ANDI >03FF`; `DYN` maps). `$9E5F`'s
  native accessed `(IX+n)` unmasked. After a hit (`$AAD5`), IX can sit near
  `$73FA`, whose `(IX+8)` is the RAM mirror `$7002`. The TI wrote `>A402`
  instead, and lockstep failed at tick 148000. The same call's game-over
  path leaves IY in the cartridge ROM (`$B1E9`). Unmasked `(IY+n)` writes
  then land in the TI's RAM copy of hot code (a `B @...` operand), and the
  cart crashes after game over. The translated original had the same latent
  fault; no profiled run had reached it. The fix is an exact slow mode after
  any call that can move the index registers: copy the object's bytes into
  buffers from where the Z80 would read them (RAM through its mirrors,
  otherwise 0), and write back to RAM only (ROM writes are dropped, as on
  the ColecoVision).
- **Check hot code integrity after rare paths.** `gotest.py` now compares
  every listed RAM code byte with the listing after each game over. Its
  self-test flips one hot byte. It caught the r18 cart, which every other
  gate passed.
- **A VRAM table the cart builds once at boot can live in a spare ROM bank.**
  `$9212` read 4 x 64 bytes a pass back from VRAM `$20A0-$27FF` (built at
  power-on by WRITE_VRAM plus the BIOS reflect/rotate generators). A RAM copy
  had been rejected for want of 2 KB. `build.py` instead runs the Z80
  reference to the end of the boot routine and stores the bytes in the top
  of a spare bank. The rest of that bank stays a bank-0 copy, so a
  power-up there still boots: the TI cart's START selects bank 0 at once. A
  PACE-only `PATCH` skips the read and copies from the bank. The copy
  routine (and the VCOPY it calls) must sit below the shadow and must not
  poll while the bank is in. The gate checks the bank, VRAM at every call,
  and the source's alignment for the word copy (+3.5% trench).
- **Pre-decode small immutable scripts at build time.** `$9BC1`'s stroke
  scripts packed a character and a step index into each byte, and read the
  step table as odd-address byte pairs. Decoded into aligned words in the
  runtime (`build.py` regenerates them from the cartridge and stops on a
  mismatch), its loop went from about 410 to 300 cycles a character.
- **A status read the callers never use is removable per call site.**
  Every translated `call $A000` (one-byte VRAM fill) went through
  READ_REGISTER (a poll plus a status read, about 150 cycles). After proving
  A dead at each return site (`ann.py` lists them), the translated sites use
  the natives' PACE variant, which skips the read.
- **Rejected, measured:** clearing only the used name cells (147 of 768 at the
  flip: logging every writer costs about what the bulk clear does); copying
  from an empty cell's pattern 0 (0.3 times a pass); thinning polls (258 a
  pass, about 2%).
- **A shadow sized from observed reads needs a fallback for the rest.**
  Star Wars' first shadow covered `$20A0-$27FF`, the range three seeds of
  the Z80 reference read. A later gate run on a faster cart (different
  frame phase) reached `$2080`. The shadow's bank then held code there, so
  that object would have drawn 32 bytes of code as its pattern. The fix:
  widen the shadow to everything constant after boot (`$2020-$27FF`), and
  send any other source, or an odd one, through the original read. A
  scratch cart that forced 188 fallbacks proved that path. Keep the range
  check in the gate. It caught a fault that every lockstep (PACE off)
  and routest missed.
- **When a game runs inside its NMI and moves the world once per picture,
  a slower picture is slow motion. Clock the world, not the drawing.**
  Star Wars' trench draws the whole hidden page and steps the walls once a
  pass. Every exact-cadence optimization left it at 71% of the ColecoVision.
  The two world-clock updates were pure state: a spawn counter (`$71A1`)
  and a per-wall z step (`$97E9`). They now run once per 4.78 elapsed
  vblanks (the Coleco's pass time), 1-3 times a pass with the remainder
  carried, while drawing stays at one picture per pass. The trench run
  went from 1988 to 1459 frames (Coleco 1405). Keep it PACE-only, so the
  lockstep stays exact. Gate it on a game-level duration against the
  original (`retimecheck.py`), and make its mutation force one step a pass.
  The objects ($9E5F, sprite state only) took the same clock at 1.3 updates
  a vblank, with 0 allowed per call: forcing at least one overshot (140 vs
  130), because the TI's calls arrive in bursts within a pass.
  A replaced leaf can become a non-leaf once patched (the translator then
  pushes R11), so check the generated entry the native's return relies on.

### Star Wars r24-r25 (2026-10-30): placement, bank and measurement lessons

- **A polled-NMI glue must restore the selected bank before RTWP.** The
  game's NMI handler can far-jump into a bank and return to hot code
  without unwinding the bank stack. RTWP then resumes the interrupted
  banked code at the right address in the wrong bank. Star Wars restarted
  at wave 0 after every death-star kill once placement put the polled loop
  ($A585, bank 7) and the handler's far jump in different banks. Keep
  `CURBNK` in the glue frame and reselect it on the way out. Lockstep and
  every routine test passed; only a game-level gate (`killcheck.py`: force
  the kill, require the next wave) saw it. Placement changes can expose
  this, so rerun such gates after any change that moves code.
- **Z80-profile heat of code a native bypasses still claims hot RAM.**
  Placement ranked by Z80 heat kept the exact (lockstep-only) body of a new
  PACE native hot. That pushed a surface loop into a bank: far jumps
  (`FARJK`) went from 0.4k to 10k cycles a pass, and the surface dropped
  25% while the native's own routine got faster. Zero the heat of
  bypassed ranges (`ann.PACE_BYPASS`). End the patched chunk there
  (`CHUNK_BREAK`) and continue with a farify-able jump (`GOTO` in patch
  files, not a raw `B @label`). After every new native, diff a flat
  all-cycles profile against the previous cart in every phase. A faster
  routine with a slower phase means placement changed.
- **Instrumentation that reads through the emulator's bus perturbs the
  run.** `m.rb`/`m.rw` charge wait-state cycles, so a tracer reading RAM
  each instruction (or even each frame) shifted the kill frame and hid
  the failure it was chasing. Read the RAM arrays directly (`m.exp`) and
  first check the instrumented run reproduces the gate's numbers (same
  kill frame, same verdict). Snapshot a short ring buffer at the events of
  interest instead of keeping millions of instructions.
- **Compare per-pass cost against the same workload only.** Different
  carts play different games once timing differs, so per-label costs move
  by ±1k. Judge on several seeds and on the totals, not on one label.
- **A VDP byte costs about 30 cycles even from the scratchpad** (MOVB to
  the port reads and writes the destination over the 8-bit bus). Count
  bytes before rewriting a VDP-bound loop: Star Wars' 768-byte clear is
  at that floor, and the remaining trench cost is spread over natives
  whose time is mostly 8-bit code-fetch and operand wait states.

### Miner 2049er rounds 14-15 (2026-10-30): many small natives, measured per level

Mean speed over 11 levels went 48.6 -> 58.0 -> 67.5% of the Coleco (the
game is CPU-bound on both machines, so every cycle shows). What paid:
- **Check for `EXX` / `EX AF,AF'` before saving R9/R10/R13/R14.** When the
  cartridge never uses the alternate registers they are free scratch in
  every native; Miner's renderer and block draw saved and restored them
  on every call for nothing.
- **Unrolled loops know per-iteration constants.** The renderer's scan of
  16 objects at `$6034 + 29k` knows each IX's parity, so it calls the even
  or odd compare block directly (no `SRL/JOC` per object) with a plain `BL`
  (no trampoline or saved next address). Free a link register by moving a
  hoisted value elsewhere if needed.
- **Hoist rare invalidation flags out of per-object paths** when nothing
  can set them during the loop (prove it: Miner's NMI only reads the VDP
  status). Apply them once before the loop by poisoning each cache entry.
- **Defer per-hit bookkeeping to its one consumer.** Only the last object's
  sprite bytes were needed at the end; a hit now records its entry pointer
  and the end reads the bytes from the cache.
- **Translated compare chains for `JP (HL)`** cost ~36 cycles per earlier
  case; a native with a branch table by index (4-byte `B @Z...` stubs,
  unlabelled lines so the build's bank check still sees them) removes the
  last levels' penalty.
- **Small wrappers called every pass add up**: Miner's footstep sound
  wrapper (`$BDE7`: test, three pushes, two calls) was ~500 cycles
  translated; as a leaf native that tail-jumps to the volume write, ~240.
- **Gate scope**: routines never entered on level 1 need level-only routest
  jobs, and routines that write the sound chip by design need `--ignore
  SOUND` on *every* `--pace` job, including the per-level ones.

### Star Wars r26-r28: lost vblanks inflate speed, and repeated uploads (2026-10-30)

- **A native that removes polls can look faster by losing time.** Star
  Wars' HUD template folded constant writes into one 768-byte clear; the
  writes it replaced had held polls, so the stretch around the clear ran
  past two vblanks and 23 of 900 were never serviced (`FRAMEC` 877).
  Pictures per 100 frames rose, but only because the elapsed-time world
  clock and the music lost those ticks; retimecheck caught it (trench run
  1495 frames against 1405). After any change that removes polls, compare
  serviced vblanks with emulated frames and record lost edges (a vblank
  arriving while the status flag is still set). Poll between segments
  of a long native VDP stream, and reload the VDP address afterwards.
- **Cache repeated uploads by destination.** The trench rewrote four
  64-byte object shapes per pass into fixed slots of a double-buffered
  pattern table; 75-84% equalled what the slot held two passes before.
  Key the cache on (slot, immutable source), prove from a VRAM-writer
  census that nothing else writes the slots during the phase, and
  invalidate on the shared write routines that phase setups use. A hit
  still sends the last byte, so the final VDP address and read buffer
  match the full copy. Mutation (always hit) must fail the frame-level
  VRAM comparison.
- **Measure the cart you think you are measuring.** The port's speed tool
  takes `--build-dir`; an environment variable read by the other tools was
  silently ignored, so two frozen carts compared as identical. Seed noise
  is about 1.5% per 900-frame trench run: gains of 1-2% need cycle
  counts per pass (inclusive profiler), not pictures per 100 frames.
- **A byte op's status covers only the high byte.** Miner's sound-trigger
  fast path ORed five bytes as `MOV / SOC / SOCB` and branched on the
  `SOCB`: a trigger in a low byte (`$62E3`, the enemy-kill sound) read as
  none and the user heard silence. End a multi-byte OR test with a word op.
  And give TI-only state (here the audible sound copy) its own gate:
  `routest`/lockstep compare game RAM and passed the defect
  (`Decompiled/Miner2049er/tools/sqtrigcheck.py` runs the real code over
  every trigger combination).
