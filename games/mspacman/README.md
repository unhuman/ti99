# Ms. Pac-Man (`MSPAC`)

A from-scratch Ms. Pac-Man for XB256, built **incrementally** — see `DESIGN.md` (§12 is the step
roadmap). Sprites (Ms. Pac-Man, ghosts, fruit) at `CALL MAGNIFY(3)` (double-size, 4 chars each),
moved with `CALL LOCATE` (never `MOTION`), 1-char-thick walls, and `CALL LINK("FLICK")` sprite
rotation so >4 sprites on a line don't vanish. Replaces the broken `mspacman-old/`.

- **Source:** `src/MSPAC.ti99`
- **Current step:** **Step 7 (in progress) — lives, respawn, game over** (on top of Steps 1-4, 6).
  Press **fire** (or Space/Enter) to start. She starts aimed **left** and moving.
- **Status:** awaiting interpreted run + compile.

## Step 3a — what you should see / test
The **authentic Ms. Pac-Man Maze 1** (the pink maze), drawn from a `DATA` grid occupying screen
rows 3–24 / cols 3–30 (rows 1–2 are reserved for the score/info HUD): **pink** thin (4px) walls
(mask-autotiled), **white dots** in the corridors, 4 corner **white power pellets that blink**
(`COLOR2` set 16 toggled white↔transparent on the `M=0`/`M=4` animation phase, lines 435-436, like
the arcade energizers), the **inset
"waist"** with **two tunnel pairs** (that wrap left↔right), and the central **ghost house**. HUD
`MAZE 1 DOTS 224`. **3 ghosts sit in the house with the red one (Blinky) on top of the gate**, the
cherry just below the house, and **Ms. Pac-Man** drives with **E/S/D/X** or **joystick 1** —
gliding, turning at cells, blocked by every wall, wrapping through either tunnel. **When she runs
straight into a wall** with no new direction queued, she **stops** (line 364) — and **keeps facing
the way she was last heading** (a separate `HD` heading drives the sprite frame, line 419/421, so
stopping no longer snaps her to face right). A nudge in any open direction starts her again.
- **Cornering.** Ms. Pac-Man moves in two 1px sub-steps per frame (same 2px cruise) and can
  **cut corners**: queue a turn into an open lane and, within 2px of the intersection, she takes a
  diagonal jump onto the new lane instead of squaring the turn at the center — the earlier you
  commit, the bigger the head start (~3px if early, ~1px if late). The cut cell is still eaten and
  the 1px sub-steps keep her on the grid. **Ghosts turn squarely**, so cornering is how she pulls
  ahead in a chase (lines 315/350–392; see DESIGN "Grid movement model").
- **Source of truth:** `assets/maze1-arcade.txt` (the full 28×31 arcade layout, from
  shaunlebron/pacman-mazegen). The TI version collapses the doubled wall-rows (31→22 rows) to fit
  the 24-row screen — the *shape is preserved exactly*, only the vertical scale changes.
- **Verified** (offline flood-fill, straight from the encoded `DATA`): 224 dots+pellets, all 28
  wide, **0 unreachable**, every sprite on a legal cell.
- **Resolved (per review):** the dead-end stubs beside the ghost-house box now zigzag through to
  the corridor above (matching the arcade), the wall gaps above the top tunnel and the lower power
  pellets are closed, and the redundant inner wall row below the lower power pellets was collapsed
  out (22 rows total, freeing a screen row).
- **Resolved (per review):** the maze grid shifted down one more screen row (now rows 3–24),
  freeing a **2-row HUD strip** at the top for score/info; dots were cleared from the entire
  ghost-house box surround (above the gate, both flanking columns the full height of the box
  including the diagonal corners, and the row below the box) and the tunnel mouths were widened by
  one more cell on each side of both wrap-around rows — 262 → 224 dots+pellets.
- **Resolved (per review):** the ghost-house gate is now drawn as a **white horizontal door tile**
  (code 160, its own `COLOR2` set 17), and the wall-check (`GOSUB 700`) blocks Ms. Pac-Man from
  entering the door cells or the pen interior — the ghost box is now off-limits to the player.
- **Resolved (per review):** the pen's interior (DATA row 11, cols 12–17 — **6 cells wide**) is
  wider than earlier drafts, so the **3 starting ghosts are now spread evenly across it** with
  equal margins from each side wall (sprite X = 105/121/137).
- **Resolved (per review):** Ms. Pac-Man starts **directly below Blinky** — both sit at sprite
  X=121, the maze's true center (screen col 16.5, directly over the pen door). Pac-Man's movement
  grid only stops on whole-cell columns (X≡5 mod 8), so on the very first frame she's given a
  default direction (right, or left if the player is already holding left) that carries her ~4px
  to the nearest aligned cell before normal turn-checking takes over.
- Multi-maze architecture: a maze = a `DATA` grid + a wall color, selected by `ON MZ GOSUB
  8001,8002,8003,8004` inside `GOSUB 800`. **All four authentic arcade mazes are in**, each from
  shaunlebron/pacman-mazegen ("MS. PAC-MAN (1)–(4)", `assets/maze1..4-arcade.txt`), all sharing the
  **same ghost-house box position** (the arcade keeps the pen in place; only the corridors and
  tunnel rows move). `MZ` is picked at level start by a small sub (`GOSUB 1155`, called from both
  the start `158` and the level-advance `1140`): the **known arcade order for levels 1–13, then
  random** from level 14 on (`IF LE>=14 THEN CALL LINK("IRND",4,MZ) :: MZ=MZ+1`):

  | Maze | Levels | Color | Tunnels | Dots |
  |------|--------|-------|---------|------|
  | 1 | 1–2 | pink (14) | 2 | 224 |
  | 2 | 3–5 | light blue (6) | 2 | 220 |
  | 3 | 6–9 | orange (10) | **1** (single wrap) | 246 |
  | 4 | 10–13 | dark blue (5) | 2 (rows 11 & 13, flank the pen) | 212 |
  | random | 14+ | — | — | one of mazes 1–4, re-rolled each level |

  Maze 3 has a single tunnel (authentic), so the fruit code falls back `TY2=TY1` when only one is
  found. `assets/mazegen.pl` autotiles + validates (symmetry, reachability); `assets/collapse2.pl`
  did the initial 28×31→28×22 collapse (drop doubled rows, carve the fixed pen box, widen tunnels,
  place energizers). The real arcade data was pulled via raw `curl` — the summarizing web-fetch
  corrupts ASCII (proven by diffing). **Mazes 3 & 4 have since been hand-refined** (maze 3 grew a
  taller symmetric pen with open lanes above and below it; maze 4's tunnels were split to rows 11 &
  13); both re-validate symmetric, 0 unreachable. `assets/maze3grid.txt`/`maze4grid.txt` are the
  `#/./o` grids decoded from the live `DATA` (they round-trip back to it exactly through `mazegen.pl`).
- Draws in a few seconds interpreted; **instant compiled**.

**Tunnels are generic — no per-maze constants.** Walls bound the actors everywhere *except* at the
tunnel mouths, so one edge test (`SX<13 → 229`, and the ghost/fruit equivalents) wraps any maze
correctly. The fruit-target tunnel rows (`TY1`/`TY2`) are **auto-detected while rendering** — any
row with an empty column 1 is a tunnel — so Maze 1 (rows 7/13) and Maze 2 (rows 2/17) both just
work. (Old per-row Y=61/109 hardcoding is gone.)

## Step 3b — eating, score, win-on-clear
As Ms. Pac-Man's cell-centered (`GOSUB 750`), the cell she's sitting on is checked: a **dot** (10
pts) or **power pellet** (50 pts) is blanked, a short blip plays (`CALL SOUND`), `DOTS` ticks down
from 224, and the HUD (`LEVEL n DOTS nnn SCORE nnnn`) is redrawn. When `DOTS` reaches **0**, the
maze **flashes and advances to the next level** (see "Level progression" under Step 7) rather than
ending.

**Score is stored ÷10 to dodge the 16-bit overflow.** The score `PT` is a TI integer (max
**32767**); a long game (banana fruit = 5000, ghost chains = 1600, etc.) would wrap. Since *every*
Ms. Pac-Man award is a multiple of 10, `PT` holds the value **÷10** internally (dot `+1`, pellet
`+5`, fruit `+10…+500`, ghosts `+20/40/80/160`) and the HUD appends a trailing `0` at render time
(`708`: `STR$(PT)&"0"`). Lossless, and it raises the real ceiling to a **327,670** displayed score.

**Instant reversal.** Ms. Pac-Man can reverse direction immediately, even mid-corridor between
cells — lines 311-314 check whether the newly-pressed direction is the exact opposite of her
current direction and, if so, flip `CD` and move right away, bypassing the cell-alignment/wall
check entirely (the cell behind her is always open — she just came from it). This is the classic
"shake the joystick" evasion move now that ghosts actively chase.

## Step 4 — ghosts move + flicker
The movement engine is now **generalized into a shared subroutine** (`GOSUB 710`), driven by
per-ghost state arrays `GX()/GY()/GD()`. **All 4 ghosts chase Ms. Pac-Man**: each frame, once
cell-aligned, a ghost looks at every open neighbor cell (`GOSUB 760`, never reversing unless it's
a dead end) and picks the one whose squared distance to Ms. Pac-Man's current cell (`PR,PC`,
computed once per frame at line 422) is smallest — a greedy "always close the gap" chase, the same
target-tile approach the arcade uses before the scatter/personality layers are added. Movement
itself is still `CALL LOCATE`, same as Ms. Pac-Man. All four use the same rightward kickoff
(`GD()=4`) so none of them freeze on their half-cell start.

**Ghost roster (pen, left to right): #4 Inky, #3 Pinky, #5 Sue**, with **#2 Blinky** already
above the door. Pinky sits centered under the door (X=121, same column as Blinky) since she's
released first.

**Pen-exit via dot counter + timer fallback.** `EC` counts dots+pellets eaten (224 total). Each
ghost has a release threshold `RT(GI)`: Blinky `RT=0` (released immediately), Pinky `RT=10`,
Inky `RT=30`, Sue `RT=60`. A ghost is released once `EC>=RT(GI)` **or** a per-ghost frame counter
`FC` (incremented once per main-loop pass, line 431, capped at 30000 so it can't wrap negative)
reaches `TM(GI)` (Pinky 150, Inky 300, Sue 450) — so a ghost still emerges on a timer even if
Ms. Pac-Man stalls and doesn't eat enough dots. `FC`/`TM` are loop-iteration counts, not real
seconds, so the pacing will differ interpreted vs. compiled — tune `TM()` after watching both.

The door is a **one-way exit lane centered on X=121**. Ghosts use a separate wall-check
(`GOSUB 760`), identical to the player's (`GOSUB 700`) except it drops the pen-interior exclusion
(line 706 — that exists only to keep Ms. Pac-Man out of the ghost box) and **always** blocks the
door tile (line 765) — ghosts never "decide" to step onto it via the normal turn-check.

Instead, exiting is its own special case (lines 713-714), reusing the same trick that lets
Ms. Pac-Man and Blinky start on the half-cell X=121 (the true screen-center, straddling the door's
two cells): X=121 is never cell-aligned, so a ghost there always skips the turn-decision and just
keeps moving in its current direction. While wandering the pen row, a **released** ghost
(`EC>=RT(GI)`) that happens to pass through X=121 is redirected to move *up* — and because X=121
never realigns, it keeps drifting straight up, perfectly centered in the 2-cell door, with no
wall-check at all. Once it clears the door into the open corridor (`BY=77`), it picks a random
left/right "kickoff" — 2 frames later it lands on an aligned cell (X=117 or 125), where it
immediately finds the wall above the door and turns into the corridor, exactly like normal
wandering.

Because the wall-check always blocks the door as a target, a ghost that has exited (or Blinky, who
starts outside) can never head back down through it via the normal turn-check — **ghosts cannot
re-enter the pen** during normal wandering; only the dedicated X=121 lane passes through. (Step 6
below adds the one exception: an *eaten* ghost becomes "eyes" whose target **is** the pen, and
reuses this same lane in reverse to get back in.)

**Collision ("CAUGHT!").** Each frame, after the ghosts move, Ms. Pac-Man's pixel position
(`SX,SY`) is compared directly against every ghost's pixel position (`GX()/GY()`): `DX,DY` are the
absolute differences, and if **`DX+DY<8`** (a **Manhattan/diamond** test, line 428), `GOSUB 780`
dispatches on that ghost's state (normal ghosts trigger `GOSUB 1100`, "CAUGHT!" + lose a life —
see Step 7; frightened/eyes ghosts are handled differently — see Step 6 below). This runs every
frame (not gated by cell-alignment), so it triggers as soon as the sprites meaningfully overlap
rather than only when they land in the same cell.

> The diamond test replaced an earlier **box** test (`DX<=10 AND DY<=10`) that was too sensitive
> when cornering: the box's diagonal corners counted a *cell-diagonal* near-miss (`DX≈DY≈8`,
> ~11px apart) as a hit. `DX+DY` keeps head-on behavior but tightens diagonally, so rounding a
> corner past a ghost no longer grazes you. `8` is the tunable "amount"; lower = less sensitive
> (requires more overlap before a hit). **The roaming fruit uses the same `DX+DY<8`** (line 434)
> as the ghosts — the earlier looser `<14` let it be eaten from a tile away, which felt wrong.

**Sprite rotation (`FLICK`).** With 4 chasing ghosts, Ms. Pac-Man, and the fruit all sharing the
screen, more than 4 sprites can land on the same scanline — the TMS9918A only renders 4 per line,
so without help the 5th+ would simply vanish. `CALL LINK("FLICK")` (line 167) is called once at
setup: it installs an interrupt-driven rotation of the sprite table so every sprite gets its turn,
trading a slight flicker for "everyone is visible." Toggled off with `CALL LINK("FLICKX")` if ever
needed (not currently used).

**Implemented:** shared array-driven movement engine for all 4 ghosts; open-cell turning and
dead-end reversal; tunnel wrap (both Ms. Pac-Man and ghosts); a ghost-specific wall-check;
dot-counter + timer-fallback pen release; the X=121 exit lane; greedy chase AI (closest-distance
turn toward Ms. Pac-Man's cell, no reversing except dead ends); Pac-Man↔ghost collision dispatch
(normal ghosts end the program — no lives yet; Step 6 adds frightened/eyes handling);
`CALL LINK("FLICK")` sprite rotation; instant-reversal for Ms. Pac-Man.
**Deferred (not debt — just not started yet):** **scatter mode + the 4 distinct ghost
personalities** (Pinky/Inky/Sue target tiles, periodic scatter-to-corners); **wrap-aware chase
targeting** — `DS(DR)` (line 728)
is plain `(TR-PR)^2+(TC-PC)^2` using screen columns 3-30, so the two tunnel mouths (C≈3 and C≈30)
look 27 columns apart even though they're adjacent via the wrap. A ghost near one mouth therefore
reads Ms. Pac-Man wrapping to the other mouth as "ran far away" and routes back into the maze
instead of following through the tunnel. Fix is a wrap-aware distance term for tunnel-row
candidates — bundle with the scatter/personality targeting rework above.

**FLICK sprite-overlap priority** — `CALL LINK("FLICK")` rotates which physical sprite slot each
of our 6 logical sprites occupies so everyone gets a turn on-screen, but that rotation also
reshuffles which sprite the TMS9918A draws on top when two overlap. So when, say, a ghost and
Ms. Pac-Man overlap, which one visually covers the other can flip frame-to-frame as the rotation
cycles — there's no way to pin "Ms. Pac-Man always on top" (or any fixed order) with this routine.
Cosmetic quirk of the >4-sprites-per-line workaround; revisit only if a custom/priority-aware
flicker scheme is ever justified.

**FLICK-induced glitches even at ≤4 sprites/line** — per `SpriteFlickerRoutine.pdf`, FLICK's
interrupt handler unconditionally rewrites/rotates the sprite attribute table in VDP RAM on
*every* VBLANK, regardless of how many sprites actually share a scanline. Our main loop also
writes that same table up to 5x/frame (`CALL LOCATE` for Ms. Pac-Man + 4 ghosts, lines 420/748).
The VDP address pointer is a single stateful register and a multi-byte `CALL LOCATE` write isn't
atomic — if the VBLANK interrupt lands mid-write, the interrupted write can land at the wrong VDP
address for that frame, producing a brief glitch. This looks like an inherent property of this
"proof of concept" interrupt routine rather than something fixable in `MSPAC.ti99` itself
(`CALL LINK("FREEZE")`/`("THAW")` don't apply here — per `XB256.pdf` p.10 they only pause/resume
XB256's *automatic* velocity-driven sprite motion, and all our sprites are created with `,0,0`
velocity and moved exclusively via `CALL LOCATE`, so there's nothing for FREEZE/THAW to batch). If
worth chasing later: compare on real hardware or another emulator, since "in emulation" may point
at a Classic99-specific timing quirk rather than the routine itself.

## Step 6 — power pellets + frightened ghosts
Two new per-ghost arrays drive the new behavior: `GS()` (state — 0=chase, 1=frightened,
2=eyes-returning) and `GC()` (each ghost's normal color, for restoring afterward), plus two shared
scalars `FT` (frightened-timer countdown) and `EG` (combo counter for escalating scores). The
ghost movement routine (formerly `GOSUB 710`) is generalized and relocated to **`GOSUB 1000`**.

**Frighten-all trigger.** Eating a power pellet (line 752) calls `GOSUB 774`: every ghost not
currently "eyes" is set to `GS=1` (frightened) and turned dark blue (`CALL COLOR(#n,5)`); the shared
timer/combo are (re)set to `FT=FB, EG=0`. **Reversal follows the arcade rule** (`775`/`776`, gated on
`GS=0` **and** `GX<>121` and applied *before* the frighten at `777`): a ghost in **normal**
(chase/scatter) mode turns 180° when the pellet is eaten — *except* one on the **gate column**
(`BX=121`), so a ghost mid-exit keeps climbing out instead of being flipped back into the pen and
bouncing (same guard the mode-switch reversal at `1173`/`1174` uses). A ghost that is
**already blue does not reverse again** — a second
pellet mid-fright just refreshes the timer/combo. Eyes-state ghosts are unaffected and keep heading
home. (The scatter/chase mode-switch reversal at `1173`/`1174` likewise only flips `GS=0` ghosts, so
blue ghosts never reverse there either.) During frightened movement the flee logic (`SG=-1`) excludes
the reverse direction, so blue ghosts otherwise only reverse on a dead end.

**Half-speed + flash (1001-1005).** While `GS=1`, a ghost moves only on odd `FC` frames (half
speed) and stays dark blue until the last 90 frames of `FT`, when it flashes blue/white every ~4
frames (`FT mod 8 < 4`). When `FT` reaches 0, the ghost reverts to `GS=0` and its `GC()` color.

**Unified pathfinding (1015-1035).** The same greedy "pick the open non-reversing neighbor closest
to a target tile" algorithm now drives all three states via a target `(TGR,TGC)` and a sign `SG`:
chase (`GS=0`) targets Ms. Pac-Man's cell with `SG=1` (minimize distance); frightened (`GS=1`)
keeps that target but flips `SG=-1` (flee — maximize distance); eyes (`GS=2`) retargets the pen
staging cell `(row 11, col 16)` with `SG=1`.

**Eyes return to the pen (1008-1011, 1051-1052).** Eyes reuse the X=121 exit lane in reverse:
pathfinding steers toward the staging cell `BX=117,BY=77`; on arrival it's nudged right onto the
never-aligned `X=121` half-cell (1011), then turned down through the door (1010), drifting
unobstructed (no wall-check applies on X=121) into the pen. On reaching the pen center
`BX=121,BY=93`, line 1008 jumps to **1051-1052** (placed after the routine's `RETURN` at 1050, so
normal pathfinding's fallthrough to 1041 never touches it): eyes respawn — `GS=0`, color/pattern
restored — the door lane is claimed (`DG=GI`), and the ghost walks straight back out (`BD=1`,
`GOTO 1041`), the same lane a freshly-released ghost uses for its first exit.

**Frightened ghosts stay confined (1008).** A ghost with `GS=1` (frightened/blue) can never
trigger line 1008, even at the pen center while otherwise "released" — the jump condition requires
`GS=2` (eyes) or `GS=0` (normal chase). A frightened ghost at the pen center instead falls through
to the unified pathfinding (1012-1035) with `SG=-1` (flee); since the door tile is always blocked
for normal pathfinding (line 765), it can never pick the door and stays inside the pen, blue,
until `FT` reaches 0 and it reverts to `GS=0` (1001) — this is what stops a newly-frightened pen
ghost from being force-ejected and "un-frightening" mid-exit.

**One ghost through the door at a time (`DG` lock, 999/1008/1009).** A new lock variable `DG`
("door-gate", line 169) restricts the X=121 exit lane to one ghost at a time: line 1008 additionally
requires `DG=0` (lane free) or `DG=GI` (this ghost already owns it) before jumping to 1051-1052,
which claims `DG=GI`. The lock holder drifts up the lane for up to 8 frames until `BY=77`, where
line 1009 releases it (`DG=0`) as it picks its random left/right kickoff into the corridor — only
then can the next waiting ghost claim the lane. A self-correcting check at line 999 (run for every
ghost, every frame, before the state machine) clears `DG` early if its holder's state changes
mid-lane (e.g. re-frightened by another pellet eaten while exiting), so the lock can never
permanently stick. Ghosts denied the lane just keep drifting in their current direction until they
realign and re-path, then try again.

**Eating a frightened ghost (780-798).** The collision check (line 428, now `GOSUB 780`)
dispatches on `GS()`: `GS=0` is `CAUGHT!` (`GOSUB 1100` — see Step 7); `GS=2` (eyes) has no
effect; `GS=1` calls `GOSUB 790`. **Ties favor Ms. Pac-Man:** the pellet-eat (line 321) is
cell-centered while the collision is pixel-based, so on the exact frame she *moves onto* a power
pellet that a chase ghost also occupies, `321` (pre-move) would miss it and she'd be `CAUGHT`. So
`781` re-checks her current cell first — if it's a power pellet (`GCHAR=152`) it `GOSUB 750`s to eat
it, which frightens every ghost (`774`, now looped on `GJ` so it can't clobber the collision loop's
`GI`); `782` then re-dispatches, eating the now-`GS=1` ghost instead of dying. Pellet-then-ghost in
one motion. `GS=1` scores **200/400/800/1600** by `EG` (incrementing it) —
stored as `+20/40/80/160` since `PT` is ÷10 (see Step 3b) — turns
the ghost white (`CALL COLOR(#n,16)`), sets `GS=2`, swaps its sprite pattern to a dedicated
**eyeballs** shape (`CALL CHAR(108,...)`, via `CALL PATTERN(#n,108)`), redraws the HUD, and then
**freezes the whole game for ~0.5 s** (`797`: four descending tones 1600→700 Hz + a short `DELAY`)
with the eaten ghost held as eyes — the arcade's eat-pause. On respawn (line 1051) the pattern is
swapped back to the normal ghost shape (`CALL PATTERN(#n,100)`) along with the color/state reset.

**Implemented:** frightened/eyes ghost state machine; power-pellet-triggered fright with reversal
and re-trigger; half-speed + blue/flash while frightened; unified chase/flee/eyes-return
pathfinding; escalating eat-ghost scoring (200/400/800/1600) with eyes + pen respawn; dedicated
eyeballs sprite (codes 108-111) while a ghost is "eyes"; frightened ghosts stay confined to the pen
instead of being force-ejected; `DG` door-lane lock so released/respawned ghosts exit the pen one
at a time, spread apart.
**Deferred:** the fright timer shrinking per level — per `DESIGN.md` §12, levels aren't
implemented yet; revisit with Step 7.

> Architecture note: mazes are authored as plain `#/./o` grids and **autotiled offline** (the
> generator computes each wall's neighbor-mask → tile), so the TI just blits tile codes. The
> readable source grid lives in `DESIGN.md`/the generator; the `.ti99` holds the encoded `DATA`.

## Step 7 (in progress) — lives, respawn, game over
A scalar `LV` (lives, **defaulted to 3 on the title at `1200`**, overridable by the cheat) and a
shared HUD subroutine (`GOSUB 708`/`709`) drive the HUD: row 1 shows `SCORE nnnnn0`, row 2 shows
`LIVES n LEVEL n` (rows 1-2 are the dedicated HUD strip, never touched by `DRAWMAZE`). The places
that used to redraw the HUD inline (initial setup, eat-dot, eat-ghost) all `GOSUB 708`.

**Caught → lose a life (`GOSUB 1100`).** On a normal-ghost collision (`GS=0`), the catching ghost
**sits on her for ~1 s** (`CALL LINK("DELAY",1000)`), then `LV=LV-1`, the ghosts hide and she does
the death spin. **The HUD is left intact through the death** (no blanking) — the lives count only
visibly drops when play resumes, where the respawn's `GOSUB 708` (`1117`) redraws it. **No message on
a normal death.** On game over (`LV<=0`) a **centered black box** is drawn
(`1111`: `FOR J=10 TO 14 :: CALL HCHAR(J,9,32,16)`) with `GAME OVER` in it, held **3 s** (`1112`),
then the **title screen** takes over (which is where you press fire to restart). Respawn (and game
start) face **left**.

**Respawn.** If lives remain, Ms. Pac-Man and all 4 ghosts are reset to **exactly their
game-start state** — same positions (`SX=121,SY=141` / the pen layout), same directions (`CD=4`,
`GD()=4`), `GS()=0` with colors/patterns restored (`CALL COLOR`/`CALL PATTERN(...,116)`), the
roaming fruit (if any) removed, and the shared timers `FT`, `EG`, `EC`, `FC` all back to 0 — i.e.
the ghost pen-release schedule restarts from scratch, same as a fresh game. Only `PT` (score),
`DT` (dots remaining), `FN` (fruits already spawned) and the maze itself are preserved. The HUD is
redrawn (now showing the decremented `LIVES`) and play resumes from the main loop.

**Implemented:** `LV` lives counter (HUD); `GAME OVER` messaging (no message on a normal death); full Pac+ghost
respawn-to-start-state on a non-fatal catch; `GAME OVER` + `END` at 0 lives.

**Bonus Ms. Pac-Man at 10,000 points (once per game).** Every frame the main loop checks
`IF PT>=1000 AND BG=0` (10,000 displayed = `PT>=1000` since the score is stored ÷10) and, the first
time it trips, `GOSUB 785`: sets the one-shot flag `BG=1`, `LV=LV+1`, redraws the HUD (`GOSUB 708`,
so the new `LIVES` count shows immediately), then rings a **3-chime bell** (`1568 Hz` dings with
short silent gaps via sequential blocking `CALL SOUND`s). `BG` resets to 0 only on a full game
restart (line 157), never on level-advance or respawn — so the award is strictly once per game.

### Step 7 polish — art, animation, sound, roaming fruit
- **~10×10 sprites + bow + directions.** All sprite art was redrawn to ~10×10 centered in the 16px
  box (3px transparent margin, up from 2px), generated from readable ASCII grids by
  `assets/spritegen.pl` (it emits the quadrant-ordered TI hex). Ms. Pac-Man now has **four
  direction-facing frames** (right 96 / left 100 / up 104 / down 108) plus a **closed-mouth full
  circle** (112); each main-loop pass picks the frame from her direction `CD` (line 421) and
  toggles open↔closed every ~8 frames while moving (lines 423-424) for a chomp animation. She wears
  a small **bow** on her head (same yellow as her body — TI sprites are single-color).
  - *Left-facing needs its own closed frame.* `pac_l` (100) is `pac_r` mirrored, so its bow lands
    on the right; the shared closed circle (112) keeps the bow on the left, so chomping left made
    the bow flash side-to-side. Fix: a dedicated **left-closed frame at char 120** (the closed
    circle mirrored, bow on the right), used in place of 112 when `CD=3` (line 423) — so the bow
    stays put on the back of her head. (Centering the bow also stops the flash but looked wrong.)
  - *Up-facing keeps the bow on the back of her head.* The up frame (`pac_u`, char 104) is the
    **down frame flipped vertically**, so the mouth opens up and the bow rides on the *bottom* (the
    back of her head) instead of over her mouth. There's no free slot for an up-*closed* frame, so
    rather than flash the bow-top closed circle (112) against the bow-bottom open frame, **up-facing
    skips the chomp toggle** — line 423 forces `PP=104` on the closed half-cycle when `CD=1`
    (`ELSE IF CD=1 THEN PP=104`). So she glides upward with her mouth open and the bow correctly
    behind; the other three directions still chomp.
- **Ghost wiggle (animated via char data, not sprite name).** All four ghosts keep the **same
  sprite pattern (116) for their whole life**; the bottom-feet wiggle is done by **redefining the
  two foot quadrant chars (117 + 119) in place** with `CALL CHAR` every phase change (lines
  435-436, `FC` mod 8 = 0 → feet A, = 4 → feet B). Because the ghosts' sprite *name* never changes,
  there is **no per-sprite `CALL PATTERN` write to race `FLICK`** (see the boot-flicker note below).
  Eyes are the one exception (sprite name 124, set when eaten / restored to 116 on respawn).
- **Distinct pellet sound.** A plain dot now plays a short high blip (`CALL SOUND(40,1400,2)`,
  line 753, guarded to `G=144`); a **power pellet** plays a separate lower energizer chord
  (`CALL SOUND(220,165,2,110,4)`, line 779) when it frightens the ghosts.
- **Start jingle.** A short **original** arcade-style ascending fanfare (`GOSUB 710`, lines
  711-718) plays once at boot, after the maze/sprites/HUD are up. (It's an original composition in
  the spirit of an arcade intro, not a copy of any licensed tune.)
- **Animated title screen (`GOSUB 1200`).** Boot runs the title before anything else (`155`) and
  game-over returns to it (`1120`), so every game starts here. It shows `MS. PAC-MAN` / `2026
  UNHUMAN` / the controls / `PRESS FIRE TO BEGIN`, plus the **most-recent score** drawn at
  `DISPLAY AT(1,1)` (`1200`) — the *same row-1 position the HUD uses* (`708`), so it doesn't jump
  when play starts; first game shows `SCORE 00` (`PT=0`). All title content sits **2 rows lower than
  the score** (text rows 7/9/16/19, sprites at dot-rows 21/89) so nothing overlaps the row-1 score;
  `PRESS FIRE TO BEGIN` stays pinned at the bottom (row 24). It animates **Ms. Pac-Man gliding left across the top and
  four ghosts gliding across the middle**, both **frame-animated** (Pac chomps via `CALL PATTERN`,
  the ghosts wiggle their feet via the same 117/119 `CALL CHAR` foot-swap used in-game). The wait
  loop **drains the launch key first** (the `WT` flag ignores the key still held from launching the
  program, then takes a fresh press) — without it the fast compiled build skipped the title. Fire
  (`CALL KEY(1)`=18) / Space / Enter starts; on exit it `DELSPRITE(ALL)`s the title sprites, clears,
  and returns into game setup.
- **`8-3-8` level-select cheat.** On the title, pressing **8, 3, 8** in sequence (a tiny `CS` state
  machine in the wait loop — keyed off `CALL KEY` *codes*, since the status `S` is unreliable after
  mixing `CALL KEY(0)`/`CALL KEY(1)`) opens a `LEVEL: 1-0` prompt. Enter `1`–`9` (or `0` = 10) and
  the game **starts on that level with the correct difficulty**: maze (`158`), fruit (`GOSUB 1160`),
  ghost speed (`SP+LE-1`, `174`) and fright duration (`FB-(LE-1)*40`, `175`) are all scaled for `LE`,
  which now flows from the title (`157` no longer resets it). The select loop **drains the held `8`**
  first (so it isn't read as level 8), then reads a fresh digit. A **second prompt `LIVES: 1-9`**
  (`1237`-`1242`) then sets the starting `LV` the same way (drain the held level digit, read `1`–`9`);
  like `LE`, `LV` is defaulted on the title (`1200`) and flows into the game, so the cheat's level
  **and** lives both carry over.
  - *Compiler land-mine this feature exposed (verified by decoding the generated `MSPAC.TXT`):* the
    XB compiler silently **miscompiles some conditional jumps** in this tail-of-program region. A
    single small-constant test (`IF K<1` / `IF K>0`) came out comparing the **wrong variable**
    (`S` instead of `K`); a short backward `GOTO`/`ELSE` to **a line that immediately follows another
    jump target** resolved to a garbage label (→ `undefined symbol`, or a silent jump into the ghost
    code at `L1024`). Fixes, all now in the level-select: **use compound `OR` conditions**
    (`IF K<48 OR K>57 …`), **no standalone short backward `GOTO`** (fold the loop-back into `ELSE`),
    and **keep a loop-back target off any line sitting right after a jump target** (a buffer
    `DISPLAY` line between the cheat's target `1230` and the drain read `1232`). Recorded in
    CLAUDE.md §2 for future games.
- **When the game ends it returns to the title:** the game-over path (`1120`) calls the same title
  routine, so every game is preceded by the title and a fresh fire-press; `DELSPRITE(ALL)` clears the
  finished game's sprites so the title is clean.
- **Death animation.** On a fatal catch (`GOSUB 1100`), the roaming fruit is removed
  (`CALL DELSPRITE(#6)`) and all four ghosts are made **transparent** (swapped to a blank pattern,
  char 132) — so they vanish without deleting the sprites or touching `FLICK` (avoids the
  delete/re-create + flicker-toggle that was crashing). Ms. Pac-Man then **spins 3 full turns**
  clockwise (right→down→left→up frames, 12 steps) while a **deepening whirr** descends from ~860 Hz
  to ~200 Hz (one tone per step; the paired 1-tick `CALL SOUND` blocks for timing — compiler-safe).
  A **normal death shows no message** and respawns; **game over** (`LV<=0`) draws the centered
  `GAME OVER` black box for 3 s, then the title. On respawn the ghosts get their normal
  pattern/color/position back and play resumes. (`FLICK` stays on throughout — Pac spins at screen row ~19, clear of the
  pen rows, so it never collides with the transparent ghosts on a scanline.)
- **Shrink-and-vanish.** After the 3 spins, Ms. Pac-Man **shrinks** through a closed circle (112) →
  medium dot (136) → small dot (140) → gone (transparent 132), each step ~110 ms with the whirr
  finishing its descent (200 → 110 Hz), so she collapses to nothing before the `CAUGHT!`/`GAME
  OVER` message. On respawn her pattern is restored to 96.
- **Game over → title screen.** When the last life is lost, `GAME OVER` shows briefly, then the
  game-over routine (`GOSUB 1120`) returns to the **title screen** (`GOSUB 1200`) and waits for
  fire. One press starts a **fresh game** — full lives, score 0, refilled maze. The restart is done
  **without `GOTO`-ing out of the nested death `GOSUB`**: the
  game-over routine sets a `RG` (restart) flag and `RETURN`s cleanly up through the call stack and
  out of the collision `FOR` loop; only then, at the bare main-loop level (line 437), does
  `IF RG=1 THEN 157` jump back to the new-game init. That keeps the GOSUB/FOR control stack from
  leaking across repeated games (a deep `GOTO` would orphan stack frames and eventually overflow).
  (The Q-to-quit feature was removed to save program space; a maze-clear still advances/ends.)
- **Boot-corruption fix.** The garbage-ghost-frame-at-boot (which "self-corrected" as play began)
  was the **per-frame `CALL PATTERN` ghost-wiggle racing `FLICK`**. `FLICK` rewrites the sprite
  *attribute* table every VBLANK, and it *preserves* each sprite's name byte as it rotates — so the
  static-named ghosts of Steps 4–6 never corrupted. The Step-7 wiggle added a `CALL PATTERN` that
  *writes* the name byte every frame; when that write collided with a `FLICK` rotation (worst at
  boot, three ghosts clustered in the pen), the name byte landed wrong → a garbage frame until the
  next repaint. Fix: **never change the ghost name at runtime** — keep all ghosts on 116 and animate
  by redefining the foot chars (117/119) with `CALL CHAR`, which writes the *pattern* table that
  `FLICK` never touches (2 small writes per phase change vs. 4 name-writes per frame). `FLICK` is
  also enabled **last** in setup (after sprites/HUD/jingle/fire-press) so no setup write races it.
  Pac's own direction/mouth `CALL PATTERN` is now gated to only fire when his pattern actually
  changes (line 424). If any residual flicker still remains, it's the documented `FLICK`
  proof-of-concept limitation rather than a pattern-write race.
- **Roaming fruit (replaces the static middle fruit).** Sprite #6 is no longer parked under the
  pen; instead, when the dots-remaining count hits **154** or **54** (≈70 / 170 eaten of 224), a
  fruit (~10×10, shape per level) is spawned at a **random tunnel mouth** (`GOSUB 720`) and created
  on demand. It moves at **25% speed** (one 2px step every 4th frame, line 433) and **heads for the
  tunnel on the opposite side of the screen** — at spawn it records a target `(FTR,FTC)` = the
  opposite-column / opposite-row tunnel mouth (line 723-724), then each move (`GOSUB 730`) picks the
  open, non-reversing turn that most reduces distance to that target (reusing the ghost wall-check
  `GOSUB 760`). Because it follows the corridors it still **weaves** across, but it always exits the
  far side rather than the side it entered; it **despawns** (`CALL DELSPRITE(#6)`) when it walks off
  that tunnel edge (a `FW>400` move count is a stuck-fruit safety). A **light, intermittent
  bounce blip** plays as it travels (every 6th move, quiet/short, line 731). Eating it (overlap
  check line 434 → `GOSUB 770`) scores **+100** and plays a chime; **dying while it's out forfeits
  it** (the caught routine removes it). At most **2** fruits per maze (`FN`).
  - *Flicker caveat:* `FLICK` caches its sprite range at call time (when only #1–#5 exist), so the
    on-demand #6 isn't flicker-rotated; it could blink only in the rare case it shares a scanline
    with 4 other actors. No correctness impact; revisit if it's visually distracting.

**Also implemented this pass:** press-fire-to-start attract gate; a spin + deepening-whirr death
animation (ghosts/fruit hidden) before respawn/game-over; reduced ghost-wiggle attribute writes to
cut FLICK boot flicker.

### Speed tuning + pen-lane fix
- **Ms. Pac-Man slows while eating.** On the frame she's cell-aligned over a dot/pellet, the eat
  routine sets `EA=1` (line 752); the four move statements (400-403) are gated `AND EA=0`, so that
  step's 2px move is skipped. `EA` resets each frame at line 300. Net effect: ~80% speed through
  dot corridors (one paused frame per cell), full speed once a corridor is cleared — like the
  arcade's eat-slowdown. (`EA` only sets when a dot/pellet is actually present, so empty corridors
  and tunnels run full speed.)
- **Per-ghost speed + tunnel 50%.** Ghosts now move slower than full and at **different base
  speeds** via a frame-skip period `SP(GI)` (line 167: Blinky 6→83%, Pinky/Inky 5→80%, Clyde
  4→75%): a `GS=0` ghost skips its move when `FC mod SP(GI)=0` (line 1007). Frightened ghosts and
  ghosts **in a tunnel** (tunnel row + outer columns, `BX<45 OR BX>197`) drop to **50%** by
  skipping even frames (line 1006); **eyes** returning home are exempt (full speed, arcade-style).
  `SP()` values are the tuning knobs.
- **Pen-lane off-screen bug fixed.** A ghost on the never-aligned `X=121` exit lane moves purely by
  direction with no wall checks; a **frightened** ghost reversed onto that lane had no end-stop
  (lines 1008/1009 only redirect `GS=0`/eyes), so it ran clear off the top or bottom of the screen.
  Added a **lane clamp** (lines 1046-1047): any ghost moving vertically (`BD=1/2`) at `X=121` that
  overshoots `[77,93]` is snapped back and reversed — so a stuck/frightened ghost **bounces in the
  pen** until it's eligible to exit, instead of leaving the screen. (The `BD=1/2` guard means a
  ghost merely crossing column 16 *horizontally* is unaffected.) The tunnel-wrap was folded into a
  single nested `IF` (line 1045) to make room without renumbering the 1051/1052 jump targets.

### Ghost personalities + scatter/chase modes
The greedy "pick the open non-reversing turn that minimizes distance to a target tile" pathfinder
is unchanged; what changed is **how each ghost's target is chosen** (`GOSUB 1180`, line 1018):
- **Frightened** (`GS=1`) → target Ms. Pac-Man but flip the sign `SG=-1` (flee). **Eyes**
  (`GS=2`) → the pen. These take priority over mode/personality.
- **Mode** (`MO`, global) alternates **scatter** (0) ↔ **chase** (1) on a frame timer `MT`
  (line 439: scatter ~7s/280 frames, chase ~20s/800). On every switch (`GOSUB 1170`) all
  out-of-pen chasing ghosts **reverse direction** — the arcade's signature tell.
- **Scatter** → each ghost heads for its own corner (`SR()/SC()`): Blinky top-right, Pinky
  top-left, Inky bottom-right, Clyde bottom-left.
- **Chase personalities** (line 1184-1193):
  - **Blinky** (#2/`GI=1`) — Ms. Pac-Man's exact cell (direct pursuit).
  - **Pinky** (#3/`GI=2`) — **4 tiles ahead** of her in her current direction (`CD`) — the
    ambusher.
  - **Inky** (#4/`GI=3`) — take the tile **2 ahead** of her, then **double the vector from
    Blinky** through it (`2*P2 − Blinky`) — a flanker whose aim depends on Blinky's position.
  - **Clyde** (#5/`GI=4`) — Ms. Pac-Man when **>8 tiles** away, but his own bottom-left corner
    when within 8 (squared-distance ≤64) — shy.

`MO`/`MT` reset to scatter on a new game and on each level (death/respawn leaves the timer
running, arcade-style). All integer math; targets can sit off-map (that's fine — they're just
distance anchors), and `BS` (line 1030) was widened to 20000 so a far target never leaves a ghost
without a move.

> **Still single-maze:** only Maze 1 exists; "levels" reuse it with faster ghosts / shorter
> fright / new fruit. Multiple layouts and background music remain optional future steps.

### Level progression
Clearing the maze (`DOTS`→0) no longer ends the game or prints "MAZE CLEARED!". Instead the eat
routine just flags `NX=1` (line 755); the main loop notices it at the bare top level
(line 438 → `GOSUB 1130`) so the advance happens with a clean stack, not nested inside the eat
`GOSUB`. The advance routine (1130-1145):
- **Flashes the maze** — ghosts/fruit hidden, then the wall `COLOR2` sets (13-14) toggle
  white↔maze-color **4 times** (~0.2s each, lines 1133-1136).
- **Speeds up the ghosts** — each `SP(GI)` += 1 (fewer skip frames = faster), capped at 10 (line
  1137).
- **Shortens fright** — the fright base `FB` -= 40 (floor 140); power pellets now set `FT=FB`
  (line 779) instead of a fixed 300, so blue time shrinks each level.
- **Changes the fruit** — all fruit shapes share **one char slot (128)**, and `GOSUB 1160` `CALL
  CHAR`s the level's shape into 128, sets the color (`FFL`) **and the point value (`FFP`)**:
  1 cherry 100 · 2 strawberry 200 · 3 orange 500 · 4 pretzel 700 · 5 apple 1000 · 6 pear 2000 ·
  7+ banana 5000 (the authentic arcade Ms. Pac-Man schedule; spawn uses `FFC`=128/`FFL`, line 723).
  Eating it adds `FFP` (`771 PT=PT+FFP`). Because the shape is redefined on the
  fly rather than living in its own slot, the fruit set is unlimited — add a shape by adding one
  `IF LE=… THEN CALL CHAR(128,…) :: FFL=… :: FFP=…` line. Shapes are generated by
  `assets/spritegen.pl`.
  (**Sprite char codes must stay ≤143** — `CALL CHAR` rejects higher codes: interpreted `BAD
  VALUE`; **compiled, no range check, the write overflows the pattern table into the VDP sprite
  *motion* table and gives ghosts phantom velocities.** Sharing one slot for the per-level fruit
  freed two slots: **120** now holds Ms. Pac-Man's **left-closed-mouth frame** and **140** restored
  the death-shrink's small frame.)
- **Refills and resets** — `GOSUB 800` redraws the maze (dots back to 224, `DT` recounted),
  Pac + ghosts return to start, timers/`FA`/`FN` cleared. `LE` shows in the HUD (`LEVEL n`).

`LE`/`FB`/`SP()` reset to level-1 values only on a full game restart (the `GOTO 157` entry, which
also clears `NX`), so they persist across lost lives within a game but start fresh after game over.

**Deferred:** background music — per `DESIGN.md` §12, this remains for a later pass. (The
per-level fruit-value schedule is now implemented; a **second maze** (Maze 2) is in — see the
multi-maze note below.)

## Build & run (Classic99, `JUWEL7` = DSK1)
Same lifecycle that worked for Dot Muncher (`CLAUDE.md` §8). Reminders that bit us before:
- **DSK1 must have "Write DV80 as Windows Text" enabled** (so the assembler can read the
  `RUNTIME*` libraries the compiler's `COPY` pulls in — a DSR error there means it's off).
- **Compiler/assembler output names must be dot-free** (`MSPAC-S`, `MSPAC-O` — never `MSPAC.TXT`).

1. Boot XB256, `NEW`, paste `src/MSPAC.ti99`, `RUN` — verify the Step-1 picture above.
2. `SAVE DSK2.MSPAC` → `SAVE DSK2.MSPAC-M,MERGE`.
3. **COMPILER**: in `MSPAC-M`, out **`MSPAC-S`**, runtime on DSK1, not low memory → Proceed.
4. **ASSEMBLER**: object **`MSPAC-O`** → `0000 ERRORS`.
5. **LOADER**: save **`MSPAC-X`** → `RUN`. Confirm it matches the interpreted run.

> **Note for step 4+ (flicker):** to test flicker *interpreted*, don't paste into a fresh `NEW`
> session — instead `OLD DSK1.HMFLICKER`, then MERGE `MSPAC-M` into it (never `NEW`), so the
> flicker routine stays embedded. Compiled builds get `FLICK` automatically from RUNTIME10.
