# Ports of BIOS-heavy ($AA55) Coleco games — the Carnival lessons

`Decompiled/Carnival` (October 2026) is the template for a cart that shows the
BIOS title and option screen and leans on OS7 (timers, PUTOBJ/WRITER, the
sound engine, POLLER).  Its tools are config-driven: copy the folder, then
change `roms/`, the ROM name in `tools/*.py` (`sed s/carnival.col/.../`),
`src/game.a99` (menu name, controller map `CMAP` = the word at `$8008`, the
game-over timeout), `tools/ann.py` and `tools/zplay.py`'s `GAME` dict.
Everything below was a real defect or a real cost in Carnival; each has a
check that finds it and a remedy.  Run the checks on every new port.

## 1. Triage first (all queue ROMs: 2,600 frames each in z80emu)

Log IN/OUT ports outside $80/$A0/$C0/$E0 (Adam/SGM use $3F, $50-$53, $7F),
PCs executed outside ROM, writes outside RAM, and screenshots at fixed
frames.  `scratchpad/triage.py` in Carnival.  None of the October queue
(Carnival, DK-Adam, Miner 2049er, Pitfall II, Star Wars, Subroc, Super DK,
Super DK Jr.) touched Adam or SGM hardware in that run.

## 2. Natives must leave every register the game can read

**Defect.**  The Zaxxon/River Raid natives (POLLER, PLAY_IT, SOUND_MAN,
PLAY_SONGS) restored only the registers those games used.  Carnival passes
whatever B the frame tick left into PUTOBJ, which stores it for mobile
objects: wrong drawings ("glitches") and a lockstep divergence.  The old
native PLAY_SONGS also clobbered IY.

**Check.**  `tools/reglive.py`: register liveness over the translator's
graph; `build.py check_natives()` runs it on every build.  Each native
declares `ann.NATIVE_EXACT` (registers it leaves exactly as the original),
`NATIVE_USE` (its inputs) and `NATIVE_DEF` (registers it always writes).  A
native whose call site has a live register outside NATIVE_EXACT is turned
back into the translated original automatically, and the build says so.
`routest.py ADDR` compares every register against the Z80 on real states.

**Remedy.**  Write natives that reproduce the BIOS's exit registers (they
are deterministic: e.g. POLLER's B C DE HL IX IY follow from the two
players' flags and the raw bytes).  Carnival's exact set: N_POLLER (all
but A), N_PLAYSNG (IY kept), N_027F SOUND_MAN (with $02D6, $012F, $00FC,
$01E9, $01A6 and $0190 fused inline; their separate natives were removed),
N_0295 SASSIGN, N_0F37 TIME_MGR, N_10CB TEST_SIGNAL, N_0679 WRITER (BC'
DE' HL' as the BIOS leaves them), plus WRITE_VRAM, READ_VRAM, FILL,
WRITE_REGISTER (A = C when B = 1), RAND.  These are the shared OS7 library
for every BIOS port: **`os7lib/` in this skill** (README there has the
integration checklist), with the VRAM/poller natives in Carnival's
`src/runtime.a99`; copy them, keep the routest runs.

**Per-site fallback.**  A native is now dropped only at the call sites
that need it dropped: `check_natives` puts the bad site in
`ann.NATIVE_SKIP` and `xlate.native_at(site, target)` translates that one
call to the original.  Before this, the WRITER's NMI-handler call site
(IY live) removed the native from the hot frame tick as well.  Limit: the translator keeps Z C S P but not
H N or bits 3/5, so `PUSH AF / POP BC` gives a different C unless a native
knows the flag byte (N_02D6 sets $42 on its only path).

## 3. LD A,R as a random number when the VDP interrupt is off

**Defect.**  The translation read the frame counter, which only the NMI
advances; Carnival never enables the VDP interrupt, so the value was always
0 and `LD A,R / CP 7` at $98D2 never let a duck dive.  First fix used BL,
which destroys R11 in leaf routines ($AB53 returned to itself: freeze).

**Remedy.**  `BLWP @LDARV` (runtime): with PACE a pseudo-random byte that
moves every call; with PACE = 0 a call count, and `lockstep.py` gives the
Z80 the same count at every `ED 5F` site.  **Never call a runtime helper
with BL from translated code**: a leaf's return address lives in R11.

## 4. A code address pushed as data must be in RAM or the shared segment

**Defect.**  The BIOS sound engine pushes its return ($03C6, $0461) before
jumping to a cart effect; Carnival pushes $A447 / $AA39 / ... before
`JP (IX)` / `JP (HL)` tables.  When the return point landed in a cold bank,
the RET ran whatever the current bank held there: freeze.

**Remedy / check.**  `build.py pushed_code()`: every CODEPTR_IMM /
CODEPTR_DATA value and ICALL return site is forced hot, and the build fails
if one is cold.  ICALL to a native target (e.g. $1F82 FILL) is `BL` + return
through the pushed address (xlate.icall).

## 5. Inline arguments: pass the original address

**Defect.**  Calls with inline bytes ($B305) preloaded a pointer to a *copy*
as label - K.  A routine whose access is mapped at run time (MAPV) took
that for a RAM mirror and read the stack: the bear's two halves drifted
apart a little on every hit.

**Remedy.**  xlate passes the bytes' own Z80 address (they stay protected
data in the cart image).  When an inline routine leaves by `EX DE,HL /
JP (HL)`, PATCH that jump as a return and list it in YIELD_AS_RET.

## 6. Lockstep blind spots fixed

- The stack exclusion had 64 bytes of slack below the lowest SP; game data
  sat there ($7360-$7390, the bear).  Exclude only the stack used.
- Lockstep from power-on rarely reaches later rounds: **scenario carts**,
  `CV_SCENE=name` (`screens.SCENES`): a cart patch applied to the TI build
  and the Z80 reference alike (Carnival `bear`: the dispatcher's play state
  runs the bear round).  Build them in a copy of the tree.
- Compare often (`--every 100`) to find the first divergence, then
  `--watch ADDR` (every write on both machines) and `--probe ADDR`
  (registers at a Z80 address on both).

## 7. Busy-wait delays

A Z80 delay loop ($A617: `SBC HL,DE / JR NZ`) runs ~3x longer translated and
drags whatever it paces (a jingle).  Replace it TI-only with a counted
native loop of the same duration; CARRY_IN for the SBC.

## 8. The frame tick: measure ticks, not frames

Carnival paces play, timers and music from one routine ($831C: poll the
VDP status, then WRITER, TIME_MGR, POLLER, PLAY_SONGS, SOUND_MAN).
`tools/cspeed.py`: ticks per frame on both machines with tick-keyed input,
`--profile N` attributes TI cycles to routines (translated, natives and
runtime).  Speed = this ratio; music tempo follows it.

## 9. VDP timing when a tick is longer than a frame

On the Coleco a tick's drawing lands inside one vblank; on the TI it
spreads over the visible frame.  Symptoms: the gallery row drawn with the
new pattern bank (R4) and the old names for one frame ("jumps and jumps
back"); sprite halves shown half moved; collision-based logic reacting a
tick late (a fired bullet still touching the gun collided after it passed
the height where the game ignores that, and vanished).

**Checks** (both proven against the defect):
- `tools/flashcheck.py --raced`: each character row rendered from VRAM as
  it is when the beam reaches it; counts rows that match neither the frame
  before nor after.  Coleco ~7 per 1,500 frames; Carnival went 29 -> 7.
- `tools/beamcheck.py`: where VRAM writes land relative to the beam.
- `scratchpad/hits3.py` (Carnival): every hit with the sprite pixels that
  overlapped in the frames before it.

**Remedy (runtime "Deferred VDP writes").**  With PACE every VRAM and
register write is queued (QBUF at >AC80; it ends at >AF80 since the os7 scratch took >AF80-AFFF); TICKD marks complete
ticks (QCMT); complete ticks go out only at a vblank: from GLUE on the VDP
interrupt (enabled TI-only by N_WRREG purely as a timer; the game's NMI is
not called unless the game enabled it; the status byte goes to STSHAD for
the game's next read), or at once when the tick's poll just waited for the
frame bit.  The WRITER's output goes out at its end on an on-time tick
(WEND), so sprites are not shown late.  A VRAM read does **not** flush: it
reads VRAM and overlays the queued writes (QOVL) — a flushing read sent
Carnival's gallery out one row at a time down the screen.  Sprite-table
writes go to a RAM shadow (SHAD) committed in one burst (SATCV).  Designs
that measured worse and were dropped: queueing only late ticks; flushing
at the next tick start; flushing from the interrupt without commit points.

**Collision-bit logic.**  Games that read the VDP collision bit (Carnival's
bear round) are sensitive to *when* sprites are shown relative to the game
logic; the Coleco itself shows the bear's halves overlapping in 38% of
frames.  Exactness here comes only from tick timing; the real cure is a
tick that fits in a frame.

**Until it fits, confirm the flag against the table the game last wrote.**
Carnival's bear round ($B1F1) takes any collision flag seen while the poll
waited as a hit when the bullet is above $A0.  On the Coleco that flag
comes from the picture of the sprite table the logic is now testing; on the
TI a 2-3 frame tick lets it come from an older picture.  The bullet was
still touching the gun, so the bear turned with the shot nowhere near him
(user report, 2026-10-25).  In the scenario cart only 5 of 22 flagged
collisions had two sprites touching in the current table.  The TI-only
remedy is runtime `BEARK` (PATCH $B1FA, under PACE).  When the flag is
set, it pixel-tests every pair of sprites before the $D0 end in the
shadow: VRAM, plus the queue, plus uncommitted changes.  16x16 patterns,
on-screen pixels only.  If no two touch, it returns as for a low bullet.
It runs only after a flag, so it costs nothing per frame.
`tools/bearhit.py` (on a `CV_SCENE=bear` build) requires the cart to score
a hit exactly when the Python pixel model says two sprites touch.  Its
`--mutate` (accept every flag) must fail.  **For any port of a game that
reads the collision bit: find every reader, and check whether the logic
pairs the flag with positions that may have moved since the picture.**

## 10. Game over must not wait for ever

Carnival waits for keypad `*`/`#` and blanks after 60 s.  TI-only GOFIRE
(runtime): a fresh fire press (released since the loop began) or
`GAMEGT` passes (~10 s) present `#` for six keypad reads; FCTN 8/9 read
as `#` already.  Patch the loop's start (clear GOREL/GOCNT) and its keypad
read.  An on-screen hint needs glyphs when the game has no ASCII font
(Carnival draws text with its own set): optional, place it where nothing
else draws.

## 11. Title screen (the standard for every BIOS-title port)

TI994AVISION logo as before; the header's two lines centred vertically
with one blank row between (`ann.TITLE_ROW1/2` = rows 11 and 13: PATCH
$13D4 / $13C2 and the same operands in `screens.z80_bios_patched`); the
copyright line stays on row 21; **"<build year> PORTED BY UNHUMAN"**
centred on row 23 (`screens.credit_lines`, runtime TCRED before the title
hold, TI-only).  If a game's lines would touch, move the copyright line up
one row so a blank row separates it from the credit.

## 12. The OS7 library in RAM and the shared segment, and what paid

Carnival, October 2026, 63.5% -> 76.4% of Coleco ticks, lockstep 0 diffs
throughout.  The code is `os7lib/`; this is why it is shaped as it is.

- **Translated BIOS is the cost.**  `cspeed.py --profile` put about half a
  tick inside the WRITER ($0679: PUTOBJ for every queued object), TIME_MGR
  and TEST_SIGNAL, at ~3 TI cycles per Z80 T-state.  The natives run at
  1.6-1.8.  Gains: native WRITER +7.6 points, TEST_SIGNAL shortcut +2.3,
  TI-only fast paths +2.4, timers +0.6.
- **Census the object kinds before writing PUTOBJ.**  `scratchpad/
  pathcensus.py` counts the BIOS instructions executed per path.  Carnival:
  type 0 is always drawn without a background save ((IX+5) bit 7 set) and
  never clipped; type 3 is always on screen; type 4 objects have ~13
  components.  Write natives for the kinds measured and tail-jump to the
  translated $06E3 for the rest (`HOT_ROUTINES`, `RUNTIME_CALLS`).  Other
  queue games: Super DK Jr. uses types 2 and 4; Super DK and DK-Adam use
  0, 3 and 4.
- **The RAM library overflowed silently.**  `>A460-AC00` filled and the
  next routine assembled into the sprite shadow and the queue; the cart
  built and drew garbage.  `build.runtime_size` now fails past `>AC00`.  The
  WRITER moved to the shared segment, which is repeated in every bank, so
  it costs cold-bank capacity: the hot margin had to grow (Carnival
  1062 -> 1536) and hot code shrank ~1.5 KB; the speed still rose.
- **Discount the heat a native removed.**  The Z80 profile still shows the
  BIOS ranges a native replaced as hot, so they took hot room for nothing.
  `zplay.py profile` writes each pc's native share
  (`prof_z80_native.json`) and `classify` scales it out for
  `ann.NATIVE_COVERS`.
- **Cache what the game asks repeatedly.**  TEST_SIGNAL walked the timer
  table from the start on every call; the game tests timers in table
  order, so `N_10CB` checks "same table, index within the last set-up
  length" (TSTAB, TSLAST, cleared by INIT_TIMER's PATCH) and indexes
  directly.  routest 300 samples, 0 differ.
- **TI-only fast paths need their own checker.**  QW (a name row straight
  into the queue) and PVF (a sprite entry straight into SHAD) run only
  with PACE on, so lockstep never sees them.  `fastpath.py` forks the
  machine at each visit, runs the fast path and N_WRVRAM from the same
  state and compares RAM, VRAM and VDP registers; its `--mutate` mode
  (drop the queue/shadow writes) must fail.
- **Attribute cycles by AORG.**  `cspeed.py`'s label map carried the last
  label across AORGs, billing the whole RAM library to whatever came before
  it; rank costs only after fixing attribution.
- **Left (Carnival, per frame):** the vblank sound ~7.8k cycles (data-area
  scan 1.4k, full register save 1.2k), POLLER 3.1k, TIME_MGR 2.6k, the
  translated REQUEST_SIGNAL $1053, and a ~21% frame wait when a tick
  overruns the frame.
- **Let the game's own call play the frame's sound** (SNDDUE, os7lib
  README). Before this, the vblank ran the engine every frame and saved
  and restored the game's registers each time, and the game's calls were
  stubs. Now the game's call plays the sound when one is due, and the
  vblank plays only what a long tick missed: +1.4 points. Gate:
  `sndtempo.py`, one run per owed vblank. The vblank run's register
  subset is proven by `sndclose.py`: nothing reachable uses EXX or EX AF.
- **Measure on many seeds, and profile the heavy ticks.** The same code
  swings about 1.5% per seed between builds, and 3 seeds once showed a
  gain as a loss. Most ticks are short and wait; the loss is the ~30% that
  take 1.5-2 frames. `tools/heavyprof.py` profiles those alone. Replay the
  measured tick times before building a scheduling change: the early
  WRITER simulated at +0.2% and was dropped.
