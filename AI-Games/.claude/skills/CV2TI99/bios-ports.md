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
but A), N_PLAYSNG (IY kept), N_027F SOUND_MAN, N_02D6, N_0295 SASSIGN,
N_012F, N_00FC, N_01E9, N_01A6, N_0190, plus WRITE_VRAM, READ_VRAM, FILL,
WRITE_REGISTER (A = C when B = 1), RAND.  These are the shared OS7 library
for every BIOS port (`src/runtime.a99`, "Hot leaf helpers" onward); copy
them, keep the routest runs.  Limit: the translator keeps Z C S P but not
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
register write is queued (QBUF, 896 bytes at >AC80); TICKD marks complete
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
