# Ms. Pac-Man (`MSPAC`)

A from-scratch Ms. Pac-Man for XB256, built **incrementally** — see `DESIGN.md` (§12 is the step
roadmap). Sprites (Ms. Pac-Man, ghosts, fruit) at `CALL MAGNIFY(3)` (double-size, 4 chars each),
moved with `CALL LOCATE` (never `MOTION`), 1-char-thick walls, and `CALL LINK("FLICK")` sprite
rotation so >4 sprites on a line don't vanish. Replaces the broken `mspacman-old/`.

- **Source:** `src/MSPAC.ti99`
- **Current step:** **Step 6 (in progress) — power pellets + frightened ghosts** (on top of
  Steps 1-4). Press **Q** to quit.
- **Status:** awaiting interpreted run + compile.

## Step 3a — what you should see / test
The **authentic Ms. Pac-Man Maze 1** (the pink maze), drawn from a `DATA` grid occupying screen
rows 3–24 / cols 3–30 (rows 1–2 are reserved for the score/info HUD): **pink** thin (4px) walls
(mask-autotiled), **white dots** in the corridors, 4 corner **power pellets**, the **inset
"waist"** with **two tunnel pairs** (that wrap left↔right), and the central **ghost house**. HUD
`MAZE 1 DOTS 224`. **3 ghosts sit in the house with the red one (Blinky) on top of the gate**, the
cherry just below the house, and **Ms. Pac-Man** drives with **E/S/D/X** or **joystick 1** —
gliding, turning at cells, blocked by every wall, wrapping through either tunnel.
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
- Multi-maze architecture still holds: a maze = a `DATA` grid + a wall color via `GOSUB 800`.
- Draws in a few seconds interpreted; **instant compiled**.

Tunnel wrap is wired for **both** tunnel rows (Ms. Pac-Man's sprite Y = 61 and 109).

## Step 3b — eating, score, win-on-clear
As Ms. Pac-Man's cell-centered (`GOSUB 750`), the cell she's sitting on is checked: a **dot** (10
pts) or **power pellet** (50 pts) is blanked, a short blip plays (`CALL SOUND`), `DOTS` ticks down
from 224, and the HUD (`MAZE 1 DOTS nnn SCORE nnnn`) is redrawn. When `DOTS` reaches **0**,
`MAZE CLEARED!` is shown for 3 seconds and the program ends.

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
absolute differences, and if both are `<=10` (sprites overlapping by well over half their 16px
box), `GOSUB 780` dispatches on that ghost's state (Step 6: normal ghosts still end the run via
`GOSUB 770`/`CAUGHT!`; frightened/eyes ghosts are handled differently — see Step 6 below). This
runs every frame (not gated by cell-alignment), so it triggers as soon as the sprites visually
overlap rather than only when they land in the same cell. **Lives, respawn, and a real game-over
flow are Step 7**; for now a normal ghost touching Ms. Pac-Man simply ends the run.

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

## Step 6 (in progress) — power pellets + frightened ghosts
Two new per-ghost arrays drive the new behavior: `GS()` (state — 0=chase, 1=frightened,
2=eyes-returning) and `GC()` (each ghost's normal color, for restoring afterward), plus two shared
scalars `FT` (frightened-timer countdown) and `EG` (combo counter for escalating scores). The
ghost movement routine (formerly `GOSUB 710`) is generalized and relocated to **`GOSUB 1000`**.

**Frighten-all trigger.** Eating a power pellet (line 752) calls `GOSUB 774`: every ghost not
currently "eyes" is set to `GS=1` (frightened), turned dark blue (`CALL COLOR(#n,5)`), and has its
direction reversed (mirroring the dead-end-reversal pattern at lines 1016-1017); the shared
timer/combo are (re)set to `FT=300, EG=0`. A second pellet eaten mid-fright re-frightens,
re-reverses, and resets the timer/combo for any already-frightened ghosts too — eyes-state ghosts
are unaffected and keep heading home.

**Half-speed + flash (1001-1005).** While `GS=1`, a ghost moves only on odd `FC` frames (half
speed) and stays dark blue until the last 90 frames of `FT`, when it flashes blue/white every ~4
frames (`FT mod 8 < 4`). When `FT` reaches 0, the ghost reverts to `GS=0` and its `GC()` color.

**Unified pathfinding (1015-1035).** The same greedy "pick the open non-reversing neighbor closest
to a target tile" algorithm now drives all three states via a target `(TGR,TGC)` and a sign `SG`:
chase (`GS=0`) targets Ms. Pac-Man's cell with `SG=1` (minimize distance); frightened (`GS=1`)
keeps that target but flips `SG=-1` (flee — maximize distance); eyes (`GS=2`) retargets the pen
staging cell `(row 11, col 16)` with `SG=1`.

**Eyes return to the pen (1008-1011).** Eyes reuse the X=121 exit lane in reverse: pathfinding
steers toward the staging cell `BX=117,BY=77`; on arrival it's nudged right onto the never-aligned
`X=121` half-cell (1011), then turned down through the door (1010), drifting unobstructed (no
wall-check applies on X=121) into the pen. On reaching the pen center `BX=121,BY=93` (1008) the
ghost respawns — `GS=0`, color restored — and immediately re-enters the existing exit logic (the
same line also handles a freshly-released ghost's first exit), so it walks straight back out.

**Eating a frightened ghost (780-798).** The collision check (line 428, now `GOSUB 780`)
dispatches on `GS()`: `GS=0` is still `CAUGHT!` (`GOSUB 770`, unchanged); `GS=2` (eyes) has no
effect; `GS=1` calls `GOSUB 790`, which scores 200/400/800/1600 by `EG` (incrementing it), turns
the ghost white (`CALL COLOR(#n,16)`), sets `GS=2`, swaps its sprite pattern to a dedicated
**eyeballs** shape (`CALL CHAR(108,...)`, via `CALL PATTERN(#n,108)`), redraws the HUD, and plays
an eat blip. On respawn (line 1008) the pattern is swapped back to the normal ghost shape
(`CALL PATTERN(#n,100)`) along with the color/state reset.

**Implemented:** frightened/eyes ghost state machine; power-pellet-triggered fright with reversal
and re-trigger; half-speed + blue/flash while frightened; unified chase/flee/eyes-return
pathfinding; escalating eat-ghost scoring (200/400/800/1600) with eyes + pen respawn; dedicated
eyeballs sprite (codes 108-111) while a ghost is "eyes".
**Deferred:** the fright timer shrinking per level — per `DESIGN.md` §12, levels aren't
implemented yet; revisit with Step 7.

> Architecture note: mazes are authored as plain `#/./o` grids and **autotiled offline** (the
> generator computes each wall's neighbor-mask → tile), so the TI just blits tile codes. The
> readable source grid lives in `DESIGN.md`/the generator; the `.ti99` holds the encoded `DATA`.

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
