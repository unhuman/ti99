---
name: CV2TI99
description: >-
  Port a ColecoVision game to the TI-99/4A by statically translating its Z80
  code (and the parts of the ColecoVision BIOS it uses) to TMS9900 assembly,
  built as a bank-switched cart sized to its measured code/data budget.
  Covers the inputs you must get first
  (the game ROM and the ColecoVision BIOS), the trace/annotate/translate/build/
  lockstep pipeline, the TI front end (TI994AVISION title rebrand, circled-X
  copyright, skippable title, entering the game from the option screen,
  keyboard mapping), game-over and black-screen handling, and the TMS9900
  speed techniques that actually paid off, including SDCC helpers, frame
  pacing and sprite presentation. Every task under it runs the automatic
  validate-then-optimize loop (§0): scripted gates on each build, speed
  measured against the Coleco, and profile-driven optimization as an initial-port
  acceptance requirement. A playable translation is an intermediate build;
  completion requires measured performance and a resolved bottleneck audit,
  without a separate optimization request. Load before starting or changing
  any ColecoVision-to-TI port (Decompiled/CVZaxxon is the worked example).
---

# CV2TI99: ColecoVision → TI-99/4A

Shared instructions for Claude and Codex; use this same folder from either
assistant. This skill covers static ROM translation, including SDCC-built
Coleco games. CVBasic source ports use the separate CVBasic skills.

**New-port output layout (2026-10-27):** reserve `build/` for current loadable
binaries only; generated assembly, symbols, logs, reports, captures and saved
experiments go under `artifacts/`. Read [build artifact layout](build-artifacts.md)
before copying template tooling. Existing projects and historical example paths
stay unchanged unless the user explicitly requests a migration.

**Optimization is mandatory during the initial port.** Read §0 before choosing
the runtime, renderer and memory layout. A working translation is an intermediate
result, not an acceptable finished game. Pursue the highest demonstrated
performance within the target hardware and agreed gameplay/presentation rules;
do not defer this work to a later user request. Review builds may be shown while
work continues, but must not be described as complete or fully optimized.

Keep cartridge execution ahead of time: generate native instructions and
immutable asset/descriptor tables during the build, not during gameplay.
For cartridge-size work, read
[Cartridge size without sacrificing runtime speed](optimization.md#cartridge-size-without-sacrificing-runtime-speed).
Audit repeated bank prefixes and exact bank lifetimes before replacing fast
immutable assets with runtime decompression. Treat an explicit cartridge-size
limit as a build gate alongside speed requirements; neither overrides the other
without a new user instruction. Pitfall II's current limit is exactly 128 KiB.
That section also covers encoding bank selection in aligned asset references
without enlarging tables, with native decode checks and whole-route timing.
When asked to remove JIT processing, inspect the cartridge separately from
the Python test emulator's instruction cache; changing host-side execution
does not improve TI hardware speed. Prefer immutable runtime code as well:
fixed workspace return branches can replace patched instruction operands.
For Carnival's confirmed flashing repair, read `bios-ports.md` section 9's
October 25 correction before changing frame commits.
Its recurrence also required prompt frame polls at safe native boundaries;
commit-only drawing cannot repair a frame interrupt serviced half a picture
late. Keep PLAY_SONGS/SOUND_MAN together when placing those polls.
Read the later Carnival rectangle-queue notes in `optimization.md` before
batching draw commands or reusing its bounded timer shortcut. Faster code
also changed interrupt phase; its write-entry poll is part of the repair.
Those notes also record the C24 rejection: a queued-read helper clobbered
BLWP's saved R15 status. Test the wrapper through RTWP and preserve its
return context even when memory/VDP comparisons pass.
For the normal-shooting freezes, static graphics expansion and trustworthy
speed comparisons, read `optimization.md`'s Carnival October 25 notes and
the updated `os7lib/README.md` workspace, bank, polling and sound-debt contracts.
For game-owned sound engines, bounded VRAM copies and constant decoder call
sites, read the Pitfall II sections in `optimization.md`; OS7 is not the
playback engine for every cartridge.
Pitfall's later direct-ROM band descriptors, native score updates and complete
checkpoint-return measurements are also in `optimization.md`. A hit countdown
alone does not measure the full return, and a requested faster animation needs
separate validation from ordinary gameplay throughput.
For all resolved Pitfall II work, use the
[Pitfall II resolved-work index](optimization.md#pitfall-ii-resolved-work-index).
It covers the retained renderer, sound, return and VDP changes, their proof
requirements, and rejected experiments; the game's validation report identifies
the currently accepted cartridge and its measured speed.
Before applying Joust's 30 Hz technique to Pitfall II, read the
[cadence comparison](optimization.md#pitfall-ii-a-30-fps-target-is-not-jousts-30-hz-conversion):
Pitfall already targets 30 Hz, so halving its drawing would target 15 fps.
Its later [original-rate movement split](optimization.md#pitfall-ii-original-rate-movement-rounds-5863)
uses a cumulative clock and bounded scenery omission while retaining renderer
side effects, sprite uploads and independent sound. That section supersedes
the earlier feasibility-only status and records the rejected row-identity cache.
Read the subsequent [return-camera correction](optimization.md#pitfall-ii-return-camera-correction-and-audiotitle-contracts-2026-10-26)
before reusing accelerated return batching: player/world/score agreement alone
missed an 8-bit screen-coordinate wrap. It also records the native music/SFX
volume policy and title-screen music-toggle contracts. Its audio correction
preserves complete effect envelopes: maximum loudness means a constant gain
per effect, not flattening every audible attenuation to zero. Compare complete
lifetimes against the original, including effect interruption and music mute.
For the MSX-derived Super River Raid comparison, read `optimization.md`'s
RAM ownership and display scheduling section and its linked executable study.
Fewer VDP transfers can help, but cache maintenance and displaced hot code
must also be included in the whole-game timing measurement.
For the complete set of resolved Carnival optimizations and repairs, use
[Carnival resolved-work index](optimization.md#carnival-resolved-work-index).
It routes to the static assets, queue/copy paths, timers, frame credit, sound,
freeze/menu and flicker contracts, with rejected alternatives kept explicit.
For guarded timer caches, menu-song shutdown, bounded capture sampling and
Super DK Junior's measured SAT timing, read [superdkjr.md](superdkjr.md).
For the MSX-derived River Raid comparison, RAM collision state, hidden display
buffers, and Joust's aligned staging/publication experiments, read
[vdp-ram.md](vdp-ram.md). It separates measured findings from proposed rewrites
and records the presentation regression in the faster alignment-only candidate.
Its [Joust resolved-work index](vdp-ram.md#joust-resolved-work-index) routes all
completed Joust optimizations, checker repairs and rejected experiments.
Its [implementation audit](vdp-ram.md#joust-implementation-audit-2026-10-27)
also covers change-density-based sprite uploads, bounded overlapping VRAM
copies, native queue flushing, input caching and retimed actor/phase coverage.
Joust's later [cohesive retiming findings](vdp-ram.md#joust-cohesive-retiming-findings-2026-10-26)
supersede the alternating-drawing contract when the user explicitly requests
one world update and picture every two video frames. They cover fixed-point
time steps, scheduled deadlines, native caller/return roots, sprite-buffer
swapping, state transitions between paired egg steps, interrupt-schedule
consistency and independent elapsed-time checks. Component proofs do not certify
the final cartridge's throughput; consult its current performance report.
When another port runs faster, compare its executing game loop even if only
its binary is available. Read [Cross-port loop comparison and acceleration](optimization.md#cross-port-loop-comparison-and-acceleration)
for River Raid's MSX-derived comparison: inclusive stage profiling, budgeted
terrain work, separate simulation/rendering schedules and RAM collision.
These are investigation strategies; the measured comparison is not an
implemented speed gain in our port. Preserve reusable findings in these shared
notes and keep artifact-specific traces and results in the game's DESIGN.md.

The two machines share the TMS9918A video chip and the SN76489 sound chip, so a
ColecoVision game can be translated instruction by instruction and keep its
graphics, sound and behaviour exactly. The CPU is the hard part: the TMS9900
runs about 1,850 instructions a frame from the TI's 8-bit memory against the
Z80's ~6,400, so a straight translation runs at roughly half speed and the work
after the first playable build is removing work, not re-encoding it
(`optimization.md`).

**Worked example: `Decompiled/CVZaxxon`** (local; `Decompiled/` is gitignored, so it
is not in git history). Copy its `tools/` and `src/` as the starting point; the
generic parts are `xlate.py`, `build.py`, `layout.py`, `lockstep.py`, `z80emu.py`,
`tiemu.py`/`ti99emu_base.py`/`vdp.py`, `insntest.py`, the speed tools and
`src/runtime.a99`/`src/sound.a99`. Game-specific: `tools/ann.py` (annotations),
`tools/screens.py` (title/option screen patches), `src/render.a99` and the `src/r*.a99`
regions. Read its `README.md` first.
**Newer, cleaner template: `Decompiled/RiverRaid`** (a $55AA game that calls the
BIOS): Joust's region map and far jumps plus Zaxxon's BIOS natives, the
vblank-deferred VDP queue, and the measurement and porting tools
(`ipass.py`, `zincl.py`, `xlatcost.py`, `routest.py`, `vtime.py`, `vregs.py`,
`pdist.py`, `gotest.py`). Start a new port from it. Its most optimized copy,
`Decompiled/RiverRaid.3` (Codex's rounds plus a third), adds the candidate
archive and holdout benchmark (`optstage.py`, `holdout.py`), the 22-gate
`nextverify.py`, the per-instruction cost listing `hotlst.py`, and the
row cache. `native-porting.md` sections 7-8 say what paid and what did not.
**For a cart that shows the BIOS title ($AA55 header) and uses OS7 (timers,
PUTOBJ/WRITER, the sound engine, POLLER), start from `Decompiled/Carnival`**
and read `bios-ports.md` first: config-driven tools (`src/game.a99`, the
`GAME` dict in `zplay.py`), the register-exact OS7 natives with the
build-time liveness check (`reglive.py`, `ann.NATIVE_EXACT`), the tick-based
speed tool `cspeed.py`, the beam checks `flashcheck.py --raced` /
`beamcheck.py`, scenario carts (`CV_SCENE`), and the vblank-committed VDP
queue.  Its sections are defects that cost real time; check each.
**Install the native OS7 library from `os7lib/`** (WRITER/PUTOBJ, TIME_MGR,
TEST_SIGNAL, SOUND_MAN, PLAY_SONGS and the TI vblank sound player) in every
such port before the first optimization round; its README is the checklist
and validation list, `bios-ports.md` §12 what it gained and why.

## 0. Default loop: validate, then optimize, without being asked

Every initial port includes performance architecture, measurement, optimization
and final qualification. Later game-code changes preserve or repeat the affected
checks. This work is already part of porting authorization; do not ask whether
to optimize or offer it as optional follow-up. Documentation-only work does not
require rebuilding unchanged cartridges.

1. **Budget and baseline first.** Before implementation, establish the original
   simulation and picture cadence, target hardware cycle budget, and relevant
   [strategy audit](optimization.md#initial-port-performance-acceptance).
   Reuse applicable native runtimes and proven techniques from the outset.
   For an existing port, record the current cart's SHA-256, gates and phase speed;
   for a new port, do this at the first executable build, before optimizing it
   (`speed.py ti|z80 ... --pass` on 3 seeds, plus `optstage.py bench`
   where the port has it). Adapt missing measurement tools from a working port
   and verify their game-specific addresses/coverage. The scripted performance
   and correctness gates are deliverables, like the cart.
2. **Validate every build automatically** with one command that exits
   nonzero on any failure (`nextverify.py`, or the port's equivalent; create
   one if missing): lockstep 0 diffs (scripted keys **and** random input),
   `insntest.py` after translator changes, `routest.py` for every touched
   native, `sprcheck.py`, video-timing/presentation, game-over/front-end
   (`gotest.py`). Each new gate gets a mutation self-test (§6). Run long
   suites against a frozen copy, so a rebuild cannot mix two carts.
3. **Optimize automatically, including the first port.** Measure against
   original elapsed gameplay speed and the agreed presentation cadence, with
   the same pass-keyed input and no unapproved fidelity regression. Record
   completed updates, complete pictures, movement/scroll progress, deadline
   misses and worst busy intervals; a faster average alone is insufficient.
   Exercise late/crowded/effect-heavy scenes as well as ordinary play.
   - profile (`hotlst.py`, `tiprof6.py`, `heavy3.py`) inclusively, rank costs,
     and inspect the actual slow intervals;
   - pick the largest *removable* work, using `optimization.md` and
     `native-porting.md` §7-8 as the menu of things that paid. Check
     the process ledger first (`artifacts/optimization/process-ledger.json`
     in new ports; retain existing projects' configured path) and do not retry a
     rejected idea unless something it depended on changed;
   - implement the most promising applicable change, keeping TI-only behavior
     switchable for exact comparison or independently proving authorized
     retiming against the original; do not let a patched oracle validate itself;
   - re-run step 2, then `optstage.py` + `holdout.py`: accept only if the
     total rises and no held-out workload falls more than 1%, without violating
     a hard cadence/presentation gate. Once frame-capped, measure reduced active
     work, improved worst-frame cost or increased timing headroom instead of
     demanding higher FPS. Record accept/reject with numbers; revert rejects;
   - repeat and audit other cost categories when one approach stops paying.
4. **Resolve remaining bottlenecks before declaring completion.** Meeting
   average target speed starts the headroom/worst-frame audit; it does not
   automatically end optimization. Two sub-1% gains, a failed experiment or a
   full hot-code area are not stop conditions. Inspect algorithmic work,
   mapping/bank overhead, static precomputation, transfer policy, layout and
   scheduling alternatives before concluding that a limit is binding.
   Every profile-supported candidate must be implemented and measured,
   rejected with measured evidence, or ruled out by a concrete contract/budget
   proof. Untested applicable ideas remain open work. Do not repeat rejected
   experiments unless a relevant assumption has changed.
   A proposal that needs an unapproved visible tradeoff, larger cart or new
   hardware does not prevent pursuing other authorized alternatives. Respect
   existing user decisions. If a required performance target remains unmet
   after those alternatives are exhausted, report the port as incomplete with
   the measured constraint and concrete options; do not label it acceptable
   merely because it runs or has improved. Only an explicit user decision can
   change that acceptance target.
5. **Qualify the final result.** Completion requires passing correctness and
   presentation gates, meeting the agreed performance requirements across the
   workload set, and a resolved strategy/bottleneck ledger with no known
   applicable, untested performance opportunity. Report the final ROM hash,
   gate summary, phase speed versus the original/baseline, worst-frame limits,
   and remaining irreducible costs with supporting evidence. Say "best measured
   under these constraints," not "absolute maximum proven." Optimize CPU work
   and timing headroom without accelerating gameplay beyond its intended rate.
   Start and play the final cart in your **own** Classic99 instance first
   (`probe99.ps1`), then load it for the user per §7. Warn before opening
   benchmark carts in a visible window (they look scrambled).

A correctness fix still runs the affected gates and production measurements.
If it regresses performance, resume the loop. A new material bottleneck or
newly applicable technique reopens the audit. Time/context limits or a missing
runtime check leave work explicitly incomplete; they do not establish maximum
performance or waive an acceptance gate.

**Joust worked checks (2026-10-25):** `Decompiled/joust/tools` now has a
plain Z80 interpreter with frozen opcode fingerprints (`check_reference.py`),
native liveness/entry/poll contracts (`contracts.py`), original-ROM native and
collision comparisons, and a gameplay benchmark that verifies menu selections.
Read the Joust sections in `optimization.md` and `native-porting.md` before
copying its checks. In particular, a shared template's profiler or sprite test
can still contain another game's addresses and silently measure the wrong work.

## 1. Inputs: get them before anything else

Stop and ask the user if any is missing. Never download ROMs; use the user's dumps.

| Input | What | Where it goes |
|---|---|---|
| Game ROM | the cartridge dump, `.col`/`.rom`, 8-32 KB, mapped at `$8000` (header `$AA55`/`$55AA` at `$8000`) | `roms/<game>.col` |
| ColecoVision BIOS | `coleco.rom`, 8 KB at `$0000-$1FFF`. The game calls it through the jump table at `$1F61-$1FFF`, and the BIOS draws the title screen and the option ("GAME_OPT") screen | `roms/coleco.rom` |
| TI toolchain | xdt99 (`xas99.py`), Python 3, Classic99 (the `Downloads` QI399.087 build) | see `CVZaxxon/README.md` |

Also ask for (or find) a reference video/description of the original if the user
wants extras (the Zaxxon explosion was specified from the arcade).

## 2. Pipeline

1. **Trace** (`tools/trace.py` → `disasm/cart.lst`, `disasm/bios.lst`): recursive
   disassembly from the reset vector, the NMI vector (`$8021` in the cart header
   → the game's NMI handler) and every BIOS entry the cart calls.
2. **Annotate** (`tools/ann.py`) what the tracer cannot see: computed jumps
   (`JP (HL)` tables, `JP_TARGET`), inline parameters after calls, data regions,
   `ICALL` (sound-effect routine pointers), BIOS routines to replace natively
   (`NATIVE`, `NATIVE_FLAGS` when the native returns flags), literal TMS9900
   patches (`PATCH`, keyed by Z80 address), hand-written regions (`ASM_REGIONS`).
3. **Translate** (`tools/xlate.py`): one Z80 instruction → a few TMS9900 ones.
   Register map: A = R1 high byte (low byte 0), BC/DE/HL/IX/IY = R2-R6, R7 = Z80
   SP + K (a real pointer into the stack), R8 = flags (canonical bits Z >2000,
   C >1000, S >8000, P >0400; flags stay in the TMS9900 status when the next use
   allows), BC'/DE'/HL' = R9/R10/R13, A' = R14, R11 = link, R12 = 0 (CRU base),
   R0/R15 scratch (the NMI path clobbers them). Memory: Z80 `$7000-$CFFF` →
   TI `>A000-FFFF` (K = >3000; RAM `$7000-$73FF` at `>A000`); BIOS `$0000-$1FFF`
   → `>2000-3FFF` (KB = >2000).
4. **Interrupt**: the TI has no NMI. The VDP interrupt is polled at loop heads
   (`TB 2 / JEQ $+6 / BLWP @NMIV`); the glue runs the game's NMI handler. Honour
   the game's own critical sections (Zaxxon: `RST 8` sets `$719E` bit 0 and the
   handler only marks the NMI pending).
5. **Build** (`tools/build.py`, `layout.py`, `screens.py`): non-inverted
   bank-switched cart (`_8`, 8 KB banks, select by writing `>6000+2n`); these
   examples use 128 KB. Size from the actual layout, not the original ROM size.
   The shared segment (`BANK ALL`) repeats in every bank; bank-independent
   helpers can instead live once in reserved RAM. Hot code
   goes to RAM (holes in the BIOS image and the cart image, copied from payload
   banks at boot) and the shared segment; cold code to banks via `FARCALL`. Hot vs
   cold comes from a profile of the Z80 reference (`build/prof_z80.json` in
   the historical example; `artifacts/reports/` in new ports).
6. **Validate, profile and optimize** through §0, including the remaining-cost
   audit. The first working cart is the baseline, not the end of this pipeline.
7. **Qualify and review** the final artifact under §6 and §7 only after §0's
   performance acceptance requirements are satisfied.

## 3. TI front end (do all of these in every port)

**Title screen (BIOS).** The BIOS boot screen says COLECOVISION and shows a
(c) line. Rebrand it to **TI994AVISION** in the same blocky multicolour font:
the BIOS builds the logo from 8x8 "pieces" (8 bytes each at `$14C3 + 8*i`), a
table at `$18A3` maps pieces onto patterns `$60-$8F`, and two name-table rows
(`$144D`, `$1463`) place them; letter colour comes from the pattern's colour
group. New glyphs (T, 9, 4, A) are drawn on the originals' grid and stored in
BIOS bytes nobody reads as data. The logo is one column narrower, so move the
TM (an `ann.PATCH` on the `LD DE` that positions it). **Replace the © glyph
(character `$1D`, BIOS font at `$158B`) with a circled X**:
`7E 81 A5 99 99 A5 81 7E`. All of this is `screens.bios_patches()`; every
patched range must be in `reserved_bios()` so the RAM image keeps it.
**Standard layout (user-approved, Carnival 2026-10-24):** the header's
"PRESENTS ..." and game-name lines centred vertically with one blank row
between (rows 11 and 13), the copyright on row 21, and **"<build year>
PORTED BY UNHUMAN"** centred on row 23 (move the copyright up a row if they
would touch).  `bios-ports.md` §11 has the patch points.

**Title hold.** The BIOS sits on the title for ~11 s (`$1968`, a 39 M T-state
busy loop). Replace it natively (`N_TITLEW`): 657 frames, **cut short by any key
or joystick input**, then wait (at most a second) for the release so the press
does not reach the option screen.

**Option screen (BIOS GAME_OPT).** Change "PRESS BUTTON ON KEYPAD." to
**"PRESS BUTTON ON KEYBOARD."**, centred, with "TO SELECT GAME OPTION," starting
in the same column (Zaxxon moved both strings into the BIOS's unused "TURN GAME
OFF" message at `$1479` and patched the pointers). Keys 1-8 pick the option
directly.

**Keyboard and joysticks** (`KSCAN` in `runtime.a99`, read through the
controller port emulation and the native POLLER):

| Coleco | TI |
|---|---|
| joystick 1 / 2 | TI joystick 1 / 2, or E S D X; controller 2 also follows joystick 1 |
| left fire | joystick fire, SPACE or Q |
| right fire (arm) | ENTER |
| keypad 0-9 | 0-9 |
| `*` | SHIFT 8, FCTN 8 (REDO) — check what the game uses it for |
| `#` | SHIFT 3, FCTN 9 (BACK) |

The keypad port reads active-low codes that the BIOS decodes through a table at
`$10F5` (index = complemented nibble; `*` reads 9 → `$0A`, `#` reads 6 → `$0B`).
**Put the whole decode table in `reserved_bios()`**: the profile only sees the
keys pressed while profiling, so the RAM copy otherwise holds zeros for the
others, and `*`/`#` silently stop working (that was the Zaxxon game-over bug).

**Entering the game.** Boot → title (skippable) → option screen → a digit
starts the game. Wait for the key's release between screens (§ti-input-screens
skill: a press that dismisses one screen must not act in the next).

## 4. Game over and black screens (TI players read a black screen as a crash)

ColecoVision games blank the display after an idle timeout (a screen saver).
On the TI this looks like a hang. In every port:

- **Game over must never go blank.** When the game-over timeout expires, go to
  the option (difficulty) screen instead of turning the display off.
- On the game-over screen, **FCTN 9 (BACK), FCTN 8 (REDO) and the fire button
  return to the option screen**; keep `*` (SHIFT 8) as "play again" if the
  original had it. Require a fresh press (the fire button is usually still held
  from play: clear the field / wait for a release first).
- **Option screen idle blanking**: find the BIOS/cart timeout that writes VDP
  register 1 with the display bit clear (Zaxxon `$C1C3`: `$82` into register 1,
  black into register 7) and remove it.
- **Slow full-screen clears** done byte by byte through the VRAM-write helper
  look like black/frozen screens on the TI (Zaxxon's clear took 31 frames vs 15
  on the Coleco). Make the fill native (one address set, then data writes,
  polling the frame every 32 bytes). Return exactly the registers and flags the
  original leaves (`NATIVE_FLAGS`).
- Implement these as `ann.PATCH` entries on the Z80 instructions (literal
  TMS9900) plus small natives, and say in the README that they differ from the
  original. They are TI-only behaviour: the lockstep must be able to switch them
  off (§6).
- One-player games: hide the second player's score if the original draws it
  (Zaxxon draws both rows).

## 5. Speed

This section is the menu for §0's optimization loop, which runs on its own.
Read `native-porting.md` (the measured budget, the porting process, the
tools and the rules) and `optimization.md` before optimizing. Summary of what paid off in Zaxxon,
largest first: native BIOS sound/poller/VRAM routines and the game's NMI glue;
a native playfield renderer with precomputed (planar) character tables and a
table-driven fast row path; compare-on-change caches (sprite-table dirty flags,
PLAY_SONGS per-channel inputs, controller debounce settle, keyboard decode);
TI-only renderer pacing (`RMINN`) so the picture never starves; reading the
controllers every other frame; native fills. Re-encoding translated code by hand
gave ~0: only removing work helps. Measure with `tools/speed.py ... --pass`
(input keyed to logic passes so both machines play the same game; frame-keyed
random input makes the machines play different games and gives misleading
ratios) and profile with `tools/tiprof6.py` (listing-based attribution).
The near-half-speed ceiling describes measured Zaxxon/River Raid translation
paths; profile each game's compiler/library overhead before assuming that limit.

For slow loading, houses, weather or flicker, read `optimization.md`'s
measurement workflow and Mean Santa sections. `Decompiled/MeanSanta` is the
worked example for SDCC natives, elapsed-frame waits and double-buffered sprite
tables. Exact lockstep, production video timing and gameplay throughput are
separate checks; passing one does not establish the others.

## 6. Verification (non-negotiable)

- `tools/lockstep.py` runs the TI build and the Z80 reference (`z80emu.py`) in
  lockstep from power-on: time is counted in poll-site visits ("ticks"), the
  interrupt is taken at the same poll site on both, and RAM (minus the stack),
  VRAM, VDP registers and the sound chip's registers are compared. 0 diffs is
  the bar for every change. `--keys 1@6000,#@150000,2@165000,*@250000` scripts the
  keypad through a game, game over, both exits and a second game; also run it
  with random joystick + fire input (both Coleco controllers mirrored, since the
  TI's controller 2 follows joystick 1), which reaches later parts of the game
  that no-input runs never see.
- **Every TI-only behaviour must be switchable** so lockstep stays exact: renderer
  pacing (`RMINN` = 0 via a hook at `RMINOK`), keyboard sampling (force a full
  scan on every read), extras like the explosion, HUD changes, game-over exits.
  The Z80 reference must run the same patched program if you patch the ROM.
- `tools/sprcheck.py`: the VRAM sprite table equals RAM after every copy (catches
  a store that changed the table without marking it dirty).
- `tools/insntest.py`: single translated instructions vs the Z80 with random inputs.
- `tools/routest.py ADDR` (RiverRaid): one routine from real captured states,
  the TI build's version (translated, native or region) against the Z80;
  the check for every native port (`native-porting.md` section 5).
- Test scripts that hook TI addresses must be **bank-aware**: a banked routine's
  address is reused by code in other banks (a hook on `$80B5` in bank 5 fired on
  other banks' code and made a working exit look broken).

## 7. Working practice

- Build both the cart and its docs together; keep `README.md` (controls, what
  differs from the original, measured speed) in sync with every change.
- For new ports, keep only current binary deliverables in `build/`; put support
  files and saved candidates under `artifacts/` per [build artifact layout](build-artifacts.md).
  Preserve existing projects' paths. Tell the user the current playable path.
  Respect the user's emulator use and existing authorization; do not ask again
  when control was already granted. Follow the repository's visible-review rule: newest
  production cart, ordinary starting conditions, verified path/hash.
- Another agent (Codex) may be working on the same folder: check file times and
  running processes before editing; never edit files another agent is changing.
- Pitfalls that cost real time are listed in `optimization.md` § Pitfalls.

For Pitfall II water/return work, read
[row streams, return scenery and proposal review](optimization.md#pitfall-ii-row-streams-return-scenery-and-proposal-review-2026-10-27).
It records accepted RAM ownership, sequential VDP writes, exact whole-scene
reuse, camera pairing, measured gains, remaining limits and rejected proposals.

Also read [water masking sprites and transfer ownership](optimization.md#pitfall-ii-water-masking-sprites-and-transfer-ownership-2026-10-27).
It covers the reproduced demo water-entry/waterfall strips, scenery-aligned SAT
publication, narrow sprite residency, decoder invalidation, and negative tests.

For subsequent speed work, read [swimming proposal validation](optimization.md#pitfall-ii-swimming-proposal-validation-2026-10-27).
It records fixed upload sequences, enemy-loop invariants, rejected RAM-directory
and waterfall caches, exact-versus-coarse scheduling, and profile attribution.
