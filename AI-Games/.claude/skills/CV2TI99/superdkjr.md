# Super DK Junior: native speed, sound transitions and VDP evidence

These lessons come from `Decompiled/SuperDKJr` on 2026-10-25. Its cartridge
is statically translated TMS9900; host emulator instruction caches are not
cartridge JIT work. Game-specific addresses below are examples, not defaults
for another port. Keep current artifact hashes and results in the game's
README/DESIGN and `build/optimization/process-ledger.json`.

## GAME OVER input contract (October 26)

The user explicitly requested that GAME OVER remain until input. This
supersedes the historical 600/601-frame automatic-return results below.
Fresh fire and FCTN 8/9 open options; SHIFT 8 (`*`) restarts the same game.
Fire held from play must be released before another press is accepted.
Keep the `$81B7` production guard as well: removing the TI auto-return alone
would still expose the original roughly 131-second screen-blanking path.
`PACE=0` retains the original-ROM behavior for synchronized comparisons.

The old timer's 22-byte slot becomes a branch to input scanning plus 18
reserved bytes. This keeps all runtime/translated labels and hot-code
placement unchanged. The wait-entry timestamp is diagnostic only. Avoid
turning a requested menu-duration change into an unmeasured gameplay relayout.

The natural GAME OVER regression checks 900 frames of held fire and 9,000
idle frames, directly exercises the original countdown expiry without
blanking, crosses the 16-bit frame-clock wrap, compares the visible name
table throughout, and verifies explicit input still exits afterward.
Restoring the actual old timeout instructions must fail that same idle check.
Branch arrival alone is insufficient for restart: require subsequent visible
actor updates, as in the prior same-game regression.

Distinguish the final all-players-out screen (`$8CED`: 12-byte GAME OVER
overlay on the playfield) from the centered 18-byte PLAYER 1/2 transition
messages (`$8CFF/$8D10`). The first idle fixture incorrectly required the
transition screen and was corrected against the final overlay's original
ROM text. The next fixture completed 9,000 stable idle frames but assumed
that interval would expire the original screen saver. It counts loop
iterations, so original-machine elapsed time is not a TI frame deadline.
Keep the full idle interval, then seed `$705C..705E` to 1/1/1 at the real
`$8194` entry and verify the resulting `$81B7` expiry. A mutation removing
the production blanking guard must turn the display off and fail the same
idle assertion. Keep both failed fixture logs and rerun provenance; do not
silently drop the visible-message assertion or shorten the idle duration.

The input-only build preserves the measured 95.579399% active Coleco rate
(three seeds, 1,500 frames each) and both strict 600-frame SAT samples:
3,489/26,112 active bytes for one player; 4,092/26,112 with two pads.
This is a requested behavior change with unchanged gameplay performance,
not a new speed or flicker optimization. The `gameover-input` archive keeps
its binary/layout comparison and measurement evidence.

Final qualification passes 41 audited gates and 200,000 synchronized ticks
with zero differences. Corrected idle seed 7 retains the full 9,000-frame
wait, executes one directed countdown expiry, crosses the frame-clock wrap,
accepts late fire and rejects both timer/blanking mutations. All remaining
rendered pixels match the initial GAME OVER capture after idle, expiry and
clock wrap (`idle-image-proof.json`, 12 colors). All
7,646 equates and 6,298 translated addresses are unchanged. The final source
and evidence archive is `build/optimization/gameover-input-final-verified/`;
`build/verify-gameover-input/evidence.json` records the fixture corrections.

## Native work that paid

- Batch consecutive idle actors only when no poll, callee or other observer
  can see their intermediate scratch stores. Super DK Junior's thirteen-actor
  region advances IX/IY/B for each actor, but writes the final scratch bytes
  once. Preserve active dispatch, register results and the final idle case.
- Reuse a timer manager's cached base and conservative end bound. Prove who
  writes the table pointer and who extends the table: here INIT_TIMER must
  invalidate the bound, while REQUEST_SIGNAL only extends it. Keep the exact
  original walk for cold, relocated, shortened and out-of-range cases.
- A fixed twelve-sprite scan can eliminate per-entry index arithmetic and
  loop control. Preserve `<64`, the count>=4 output, BC/DE/IX and CP-4 flags;
  this is a CPU optimization, not permission to omit sprites or rotation phases.
- Produce canonical Z80 flags and useful native status with the same operation
  where possible. `LI R1,0` produces A=0 and EQ; `CLR R8` preserves the NE from
  `LI R1,>0100`. Check both flag representations, including every early return.
- For TEST_SIGNAL's B=A, C=0 result, clearing BC before copying A into B is
  cheaper than a later indexed byte subtraction on C. This does not depend on
  the unused low byte of A. Keep the fallback's residual-count behavior exact;
  all 7,175 boundary/cache cases still pass. The measured additional gain was
  only 0.14%, but every holdout improved against the music-fixed baseline.
- A larger cache can lose: 64 predecoded timer pointers used 128 extra RAM
  bytes and reduced the aggregate rate by 0.025%. Retain rejected measurements;
  do not retry the idea without a changed dependency or cost model.

The first combined round improved active-play throughput from 90.9% to 94.6%
of the Coleco rate (about 4.1% faster), with 6–8% gains on three held-out
workloads. It retained a 128 KiB cartridge. Those are workload measurements,
not a full-speed guarantee for every level.

The menu-shutdown follow-up plus the smaller timer change measured 95.42% on
the same main benchmark. Its two-player holdout fell from 93.87% to 91.26%
after the requested earlier shutdown changed transition timing. Keep that
correctness change separate from the timer optimization, which passed the
unchanged holdout threshold against the music-fixed baseline. Do not report
an aggregate improvement as a gain on every workload.

## Kill the producer and the chip when leaving a music screen

Super DK Junior starts two songs while waiting for a game choice. The original
reset happens later in setup; selecting a game must stop them at the selection
boundary. The TI patch at `$8170` reuses SOUND_INIT before loading `$723E`.
It retires the song areas, resets channel pointers and noise state, invalidates
PLAY_SONGS caches, and writes all four PSG attenuations to silence. Preserve the
selected option in A and live registers. Keep the reset free of polls so no
sound tick observes half-reset state; PACE=0 retains the original oracle path.

TURN_OFF_SOUND alone only mutes the chip. Active song data can make the next
PLAY_SONGS tick audible again. Conversely, clearing producer state alone can
leave the chip's final note latched. Cached output must agree with both.

`tools/check_menu_sound.py` boots the actual menu and tests all eight choices
at three musical phases. It checks silence before setup, inactive producers,
idle channel pointers, invalidated caches, sixteen later sound ticks, and
audible level sound after each selection. It rejects the old ROM, a skipped
reset and a chip-only mute. Check an interval for level sound: a tune can finish
before the first actor update, so requiring one arbitrary instruction to be
audible is a false failure. Never patch the test ROM's start state to make this
transition pass.

## VDP findings and limits

Exact lockstep with PACE=0 does not test production beam timing. Measure actual
writes while the display is enabled, using the current R5 SAT base and the
address before the VDP auto-increments it. Count complete four-byte records and
retain the original sprite count and priority rotation.

On the 600-frame seed-1 workload, the first optimization round retained 25,984
SAT bytes and 6,496 complete records; active-display writes fell from 20.90%
to 13.97%. Writes still occur during active display: this is an improvement,
not evidence of zero tearing or all-scene safety. `tools/check_video.py` keeps
the production replay separate from synchronized correctness comparisons.
For deferred flushes, also read `bios-ports.md` section 9: a tick starting on
time does not make a later flush safe after lengthy rendering.
The follow-up ROM measured 13.72% active-display SAT writes on the same
600-frame workload; active writes remain a documented limitation.

## A sudden READY screen may be an input command, not collision physics

Super DK Junior's prototype checks keypad `$7006` at `$82D9`: 0 completes a
round and 1 loses a life. The latter discards a return and reaches READY without
the normal `$A89C`/`$AF28` death-song wait. Executing it during a natural jump
lost one life and reached READY in three frames. Normal scripted water death
waited 76 frames on both TI and Coleco; that original routine has no separate
death animation. Trace restart/outcome paths before changing fall thresholds.

Subsequent user-requested change: production TI play now ignores keypad 1.
The `$82DF` patch returns normally for A=1 with PACE enabled, after the original
`RET NC` has already returned on ordinary input. Key 1 remains valid in the
menu; PACE=0 retains the original oracle and key 0 is unchanged. Test all 256
values in both modes, the retained continuation/bank stack, and held/repeated
presses during natural walking and jumping. A guard-bypass mutation must fail.
This removes an unwanted feature without claiming it caused the user's reset.

A delayed review-script `1` intended for the option screen can trigger this
shortcut if the user starts playing first. Foreground verification only proves
the window, not the game's state. SuperDKJr's launcher now loads for review
without delayed selection/movement probes; run those probes headlessly. This
was a plausible mechanism for the user's report, not a captured reproduction
of their particular input. Preserve that distinction in the diagnosis.

Check actual geometry and controller decode separately. The directed test
executes both binaries against level-1 ROM-table endpoints and the strict
three-pixel rope catch band (1,683 cases), rejecting a widened band. The input
test executes POLLER against CRU input for 160 movement/fire combinations,
checks real digit commands, and rejects a mutated no-key code that decodes as
1. This narrows the cause without weakening the original fall/death rules.

## Checks and profiling that remain trustworthy

- Test caches cold and warm. Resetting every isolated sample can silently send
  all calls through the fallback. Execute the actual cache producer and
  invalidator as well as seeding boundary states; mutate both. Patch cold code
  in its selected ROM bank, not the emulator's RAM array. Timer tests cover all
  256 indices, seven status combinations, exact registers and both flag forms.
- Bound capture memory with a reproducible reservoir over the full replay;
  preserve the first entry, use a separate RNG, and snapshot only retained
  states. TEST_SIGNAL produced over 450,000 entries; storing every RAM/VRAM
  snapshot before sampling used several GiB without improving coverage.
- A computed-call target may have only a Z entry. For `$99A3`, use that entry
  with the continuation already on the stack. Do not invent a C label or skip
  the routine. Record harness fixes and rerun affected checks explicitly.
- Assert complete replay length, positive coverage and every reported failure.
  A parser looking only for a bracketed diff missed an unlisted `runaway`.
  Keep named existing instruction exceptions narrow and mutation-test parsers.
- Preflight the interpreter dependencies needed at the end of a long check.
  Python 3.12 lacked Pillow and failed game-over PNG output; rerunning the five
  unchanged cases under Python 3.9 passed. Record the dependency failure and
  rerun explicitly; do not call the original suite invocation clean.
- Check inherited tools before trusting them: `speed.py`, `hotlst.py` and
  `tifunc.py` can retain River Raid's `$8589`. This game measures actor entry
  `$9995` with actor-keyed input. `hotlst.py` now uses `cspeed.py`. Label maps
  must reset at BANK/AORG boundaries; otherwise PLAY_IT can appear expensive
  because unrelated code inherited its name. Use actual instruction costs
  before choosing a native replacement.


## Native byte thresholds and production layout (2026-10-25)

The updated Joust arithmetic guidance yielded four smaller-cost comparisons
in SuperDKJr's actor/rope native regions. For a register whose high byte is the
original byte, unsigned `< k` and `>= k` are exactly word `< (k << 8)` and
`>= (k << 8)`, regardless of the scratch low byte. Replacing `CB R0,@BCxx` with
`CI R0,>xx00` saves 12 cycles in this port's bus model and keeps the four-byte
instruction size. This does **not** apply naively to byte equality or strict
`>` comparisons. Test the actual assembled branch for every 16-bit value;
`check_native_bounds.py` covers 262,144 cases and rejects a +1 low-byte operand
mutation at each site. Update the catch-band mutation to target the new operand.

A lower routine cost need not produce a useful whole-game gain: actor samples
fall from 14,537 to 14,287 cycles/call, but active-play throughput rises only
0.0054% vs the key-removal-only build (95.581% of Coleco, 57.330 nominal updates/s).
The candidate is 128 KiB, with 194 runtime bytes free. Do not call this a large
new speedup or a JIT removal; the cartridge was already static native code.

Keep production beam checks even for an input-only change: the first key-1
removal enlarged a hot chunk and changed placement. Its active SAT-write
fraction rose from 13.724% to 13.997%. The native-comparison candidate retained
the requested input behavior and passed the unchanged threshold at 13.362%
(3,489 / 26,112 bytes; 6,528 records; 600 frames, seed 1). Active writes remain;
lockstep accuracy is not a zero-tearing guarantee. ROM hash:
`ccb393b5d10f71331213017a1375b9b2867209fb7d8fb528f04b2b1226129911`.

Apply other-game tips only after checking active paths. SuperDKJr has no
background SNDRUN call and does not activate the inherited TICKDV/DEFER queue;
Carnival's sound/queue fixes are not automatically fixes for this game. A sprite
mirror needs its own bounded buffer lifetime, invalidation and TMS9918 final
address/read-buffer contracts, even when unchanged bytes are skipped.

With the original implicit-mirror input driver, held-out active rates
(games 2/7/4, seeds 4/5/6) are 93.144%, 91.608%,
and 93.660%, respectively: all improve over both the key-removal-only
intermediate and menu/timer handoff. The ledger retains the failed intermediate
video measurement. The prior timer-clear round and this native-comparison round
both gain under 1% on the primary benchmark, satisfying the skill stopping rule.

Benchmark input contract: check actual selected skill/player bytes $723D/$723E
at the first actor entry. Do not infer an idle second player from a J1-only
host driver: KSCAN deliberately ORs controller 1 into controller 2 at KS7
because players take turns. A new check executes all ten direction/fire states
through POLLER with both explicit J2 input and implicit J1 mirroring, and rejects
wrong-mode and removed-native-mirror mutations. The explicit two-pad replay is
recorded as `active-players-v2`; compare only runs using the same input protocol.
`check_video.py --game` also covers a two-player beam-timing workload.

The explicit two-pad game-7 replay is a separate timing protocol: menu/timer
baseline 91.678420%, key-removal intermediate 92.067989%, native comparisons
91.948658%. The candidate is 0.129611% below the intermediate, within the
unchanged 1% holdout gate, and above the prior handoff. Preserve the original
implicit-mirror results as historical evidence; do not call them invalid input
or mix protocols. The actual selected RAM values are skill 3 / two players on
both reference and TI. Single-player input scheduling is unchanged.

The explicit two-pad beam check passes against the prior handoff at 600 frames,
seed 5: 4,092 / 26,112 active SAT bytes (15.670956%) versus 4,221 / 26,048
(16.204699%). Both write during active display. The benchmark-input gate passes
10 direction/fire states and rejects wrong mode / removed native mirror.

Final verification: `build/verify-native-compare/evidence.json` audits 40 gates
on the retained ccb393b5 ROM. The frozen 39-gate suite passes in one invocation;
the benchmark-input gate was added while it ran and passes separately against
byte-identical production artifacts. Five 40,000-tick replays observe zero
differences (200,000 ticks total). Instruction testing covers 4,528 instructions
with only the four existing random-operand exceptions 1332/1B64/8276/8391.
All five natural game-over cases pass; idle returns after 601 frames and blanks
for one redraw frame. Idle-menu and same-game-restart captures were inspected.
The visible review cart's hash matches the audit. Final sources and supporting
measurements are in `build/optimization/native-final-verified/`.

## User-requested death animation

The prototype's `$AF28` song-14 wait had no death animation. A requested
arcade-inspired extension can reuse resident Junior poses 10/11: wide eyes,
alternating arms, a brief hop/hover, then an accelerating drop. Update only
the three RAM SAT records and let the normal NMI uploader send them. This
adds neither pattern uploads nor regular-play hooks, preserves collision
coordinates/rules and fits the existing approximately 76-frame jingle pause.
Keep PACE=0's original wait/poll for the ROM oracle. Clamp display coordinates
for water/top-edge deaths and hide below-screen sprites with Y=195; Y=208
would terminate the entire SAT. Check actual visible poses, timer wrap, one
life consumed, and visible respawn, plus a bypass-animation mutation.

Test return stacks at equivalent call boundaries. Comparing BSP inside
`$AF28` with BSP after its caller returns falsely reports a leak because
CALLSV/FARCALL legitimately holds a six-byte bank frame during the call.
Compare immediately before CALL `$A8A4` with its continuation `$A8A7`.
Qualify hooks and code mutations by bank when the animation is cold.

Do not let busy-wait profile heat consume hot RAM merely because an animation
wait loop executes often. The first hot build lost 0.701009% active throughput
with changed placement and death-wait timing (not independently isolated).
The banked experiment also exposed `xlate.py`'s
ASM `@CALL` bug: `cur` is a tuple containing a mutable list; use
`cur[1].extend(...)` for FARCALL/CALLSV, not `cur[1] += ...` (which attempts
tuple assignment after mutating the list). Full isolated verification trees
must include `disasm/coverage.json`, which the instruction checker reads.

The retained death animation uses 272 bytes of unused bank-0 tail plus a
24-byte RAM dispatcher, preserving all 6,298 original translated instruction
addresses. An equal-sized BL replaces the first instruction at `$AF28`.
The dispatcher retains that instruction in oracle mode; production FARCALLs
the animation and skips the stationary wait only after bank restoration.
Derive the song entry's bank selector from placement, and assert that tail
code overlaps neither shared ROM nor the bank end. The 128 KiB cart has 170
runtime bytes free; no additional normal-gameplay hook runs.

Results for `ef0c17d2...`: primary active rate 95.579399% versus 95.581122%
before the feature, a 0.001803% relative decrease. Held-out game 2/7/4 changes
are 0%, -0.507614%, +0.233372%, within the unchanged 1% gate. The one-player
600-frame SAT result is exactly unchanged at 3,489/26,112 active bytes;
two-player is likewise unchanged at 4,092/26,112. Both retain 6,528 complete
records. Active-display writes remain, so do not describe this as tear-free.

Retain unsuccessful experiments in the ledger. Hot/cold animation placement,
actor-state fusion, FF-status word compares, and a sprite-loop word decrement
all failed the unchanged two-player video comparison, even when local cycle
counts improved. Revert those code changes rather than accepting an isolated
instruction-cost win. The bank-0 layout above passes both video comparisons;
this is a requested presentation feature with preserved measured speed, not
another optimization success. Existing diminishing-return stopping criteria
still apply to further performance work.

The final feature ROM passes all 41 gates in one isolated invocation; the
audit is `build/verify-death-flail-sidecar/evidence.json`. Five 40,000-tick
oracle replays produce zero differences. Production animation checks cover
natural water death, both edges and frame wrap: all four take 76 frames,
consume one reserve, restore the caller's stacks and reach a visible next
life. The bypass mutation is rejected. Native Classic99 captures confirm
flailing and respawn. The 4,527-instruction gate has only the four existing
named random-operand exceptions. Preserve these limits rather than claiming
exhaustive play coverage. Final sources and evidence are archived under
`build/optimization/death-animation-final-verified/`.

Game-over restart capture must wait for a real actor update and an enabled
display; an arbitrary 60-frame delay can capture the legitimate setup blank.
`gotest.py` now checks this and can run its five independent cases in parallel
without changing seeds or coverage. For the Python 3.9 host, validate optional
`nargs='*'` positional choices explicitly: argparse's `choices` rejects the
empty list. The review launcher records its own PID and start time, so it
does not close another game's emulator; `-CaptureOnly` verifies/captures that
instance without reloading it or sending gameplay keys.

## Transition message centering

READY and GAME OVER for both players share `$8D4D LD HL,$01C0`, the row
offset added to the name table and original column. The requested centering
is a cosmetic `screens.cart_patches()` immediate change at `$8D4E` to `$0160`
(row 11 instead of 14, 24 pixels upward). The reference receives the same
documented presentation patch; the original ROM on disk stays untouched.
It changes exactly one byte in the 128 KiB TI cartridge and preserves all
6,298 translated addresses, instruction cycles and 170-byte runtime margin.
Check all four messages, since they share this positioning helper, and inspect
the actual rendered screen. Avoid a new per-frame hook for a fixed coordinate.

The four before/after image comparisons preserve every pixel after the
24-pixel translation. Native Classic99 READY was also inspected. The three-seed
benchmark is exactly unchanged at 95.579399% of Coleco active throughput; both
600-frame one-/two-player VDP comparisons are likewise exactly unchanged
(3,489 and 4,092 active bytes respectively, each out of 26,112 with 6,528
complete records). The earlier optimization stopping condition still applies.

Final centered-message ROM `8ae59cfe...` passes all 41 existing gates in one
isolated run; `build/verify-ready-center/evidence.json` audits five 40,000-tick
replays with zero differences. All 68 game/compiler/test Python and assembly
sources match the frozen run. The row change adds no gate exception. The
original 32 KiB ROM retains SHA-256 `70f1ed6190c8d647ce57d4235f98f13d2712ec22a41f6e4f5afd579357be5744`.

## Applying the MSX-derived River Raid comparison (2026-10-26)

Read `Decompiled/RiverRaid/DESIGN.md`, "October 25, 2026: comparison with
Super River Raid 1.1", including its focused loop follow-up. The supplied
MSX-derived TI binary uses RAM terrain, larger word/block transfers, budgeted
preparation, hidden terrain/SAT buffers with IRQ publication, and less frequent
sprite refresh than simulation. These are measured architectural differences;
they are not interchangeable implementations of the Coleco game's rules.

SuperDKJr already tests collision against CPU-side geometry. Its unchanged
`8ae59cfe...` baseline reproduces 95.579399% active Coleco throughput. A neutral
600-frame seed-1 VDP diagnostic observes 128 data reads, 42,741 writes and
423 calls of the 16-entry sprite uploader, including transitions. The SAT base
is >1F80. Thus a large collision mirror or copied River Raid row cache is not
an established opportunity here. Retain the trace at
`build/optimization/river-ram-baseline/vdp-diagnostic.json` and its producer
`scratchpad/river_vdp_probe.py`.

**Instrumentation must not alter CPU time.** The emulator's `rw()` and `reg()`
bus helpers charge cycles even when called by a diagnostic hook. Inspect raw
RAM/scratch storage for passive probes. The first probe accidentally changed
actor timing; its overwritten exploratory output is not accepted evidence.
The corrected probe reproduces the unchanged benchmark's 222 actor entries
and 221/236 active intervals.

**Word transfers require actual alignment and full input bounds.** The RAM
priority table begins at odd $72A7. An odd-aligned immutable source permits a
byte peel, six aligned word copies, and a final byte. Odd rotation offsets
need a byte fallback. Include all output bytes explicitly: the generic routine
tester's broad stack exclusion overlaps the last five priority-table bytes.
The first draft shortened the upward table too far for offset 13. Full-byte
tests also exposed the older region's unsupported 254/255 addition wrap;
the exact experiment supplies the original 0/1 starting entries. Preserve
this finding when revisiting that region; do not copy the rejected draft.

The combined exact candidate `river-word-exact` (`9029483d...`) passes 768
order and 48 upload oracle fixtures and rejects alignment/endian mutations,
but is **rejected**: 94.995422% active throughput (-0.610986% relative) and
two-player active SAT writes 4,288/26,304 (16.301703%), versus baseline
4,092/26,112 (15.670956%). It shifts placement as well as instruction costs;
do not blame one factor without isolation. The earlier incomplete
`river-word-copy` draft measured 95.822338% and passed both short video tests,
but failed the full input contract and must not be shipped. Keep its apparent
speed win separate from a correct accepted optimization.

The isolated `river-word-pointers` (`522306c1...`) is also **rejected**.
Replacing three aligned little-endian byte-pair loads with MOV/SWPB saves
144 cycles per 16-sprite upload (4,646 -> 4,502) and preserves all 6,298
translated addresses. Its 196,608 assembled pointer-value cases and 48
original-BIOS uploads pass; wrong-source/omitted-swap mutants fail. Nevertheless
active throughput is 94.926883% (-0.682695% relative), and one-player active
SAT writes rise to 3,588/26,048 (13.774570%). This demonstrates a timing/route
regression even without global placement changes; local cycle savings alone
remain insufficient. Its two-player video improvement does not override the
failed one-player gate. Keep all three candidate archives and ledger decisions.

The exact combined candidate additionally fails the game-4/seed-6 holdout:
92.134545% versus 93.878794%. Its long frozen suite was stopped after rejection;
the passing boundary fixtures are not a full release qualification. No new
regression exception or relaxed timing threshold was introduced.

The stronger `river-sprite-constants` (`863fb7fe...`) is **rejected as a speed
optimization** as well. Build-checked immutable header pointers ($8002/$8004)
can replace repeated decoding with LI; the dynamic aligned VRAM pointer still
uses MOV/SWPB. This saves 244 cycles per 16-entry upload (4,646 -> 4,402),
preserves all 6,298 translated addresses and fits the original 128 KiB cart
and 170-byte runtime margin. Tests execute all 65,536 dynamic pointer values,
48 original-BIOS uploads and reject two changed-header mutations plus wrong
source and omitted swap. Both 600-frame video samples improve: one player
3,321/25,984 (12.780942%), two players 4,004/26,112 (15.333946%). However, the
unchanged three-seed active benchmark falls to 94.993695% (-0.612792%
relative). A tiny local CPU reduction is not grounds to replace the faster
production replay with it. No completed priority group was intentionally
skipped in any of these experiments.

**Resolved outcome:** restore the centered-message production ROM
`8ae59cfe2ed3703f5d715d41eb151a4d34959483b59f3a84ba79b0df2640767a` and its
original source/41-gate suite. The fresh baseline remains 95.579399% active
Coleco throughput (57.328688 nominal updates/s). These are rejected experiments,
not a new performance success; the existing diminishing-return stop remains
applicable. Revisit only with a changed scheduling or data-layout dependency,
not another sweep of instruction timing to tune these same replay phases.

The restoration audit checks all 68 code/tool files and all seven build
artifacts against the baseline, plus its historical 41-gate artifact hash.
It does not claim the full suite was rerun on unchanged bytes. Isolated
reruns of all three exact candidate fixture suites are stored with each
candidate. Their first reconstruction omitted `tools/roms/994arom.bin`;
copy the tool-emulator ROM directory as well as the game's `roms/`, and keep
that dependency failure distinct from a game/test failure. Final evidence:
`build/optimization/river-comparison-final/`, with
`river-restoration-proof.json` and all four rejected candidate snapshots.

**Hidden SAT publication is a separate unfinished architectural candidate.**
Do not copy SRR's VRAM addresses or throttle sprite construction automatically.
Audit every writer and the complete table (including unchanged tail entries),
publish only completed state at a proven safe time, and retain every completed
priority phase until displayed. A polled NMI can start late; two buffers alone
do not prove a safe register switch. SuperDKJr's inherited DEFER/TICKD machinery
is inactive in ordinary gameplay, so enabling it requires a new lifecycle and
timing contract, not only replacing the uploader's destination address.
