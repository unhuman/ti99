# Ms. Pac-Man — Design

> Built **incrementally** (see Roadmap §12). Each step compiles and runs on its own. The
> architecture below is fixed up front so every later step drops in cleanly. Platform rules:
> repo `CLAUDE.md`. Replaces the broken `mspacman-old/`.

## 1. Concept & objective
- Classic Ms. Pac-Man: clear the maze of dots while evading four ghosts; power pellets let you
  eat frightened ghosts; fruit gives bonus points; lives + levels.
- Win a level: all dots + power pellets eaten. Lose: ghost catches Ms. Pac-Man with no lives left.

## 2. Architecture (the load-bearing decisions)

**Screens.** Maze on **Screen2** (`CHAR2` chars). **Sprite patterns are Screen1 `CALL CHAR`
definitions** (per XB256: sprites always use Screen1 patterns, even displayed over Screen2). So
two independent char tables — no conflict if codes overlap.

**Sprites — `CALL MAGNIFY(3)`** (double-size, *un*magnified → 16×16 px box, 4 chars each). The 4
chars are in TI quadrant order: **base = top-left, base+1 = bottom-left, base+2 = top-right,
base+3 = bottom-right**; the **base char code must be a multiple of 4**. MAGNIFY is global (all
sprites). **We draw only ~12×12 of art centered in the 16px box (a 2px transparent ring all
around)** so actors look ~12px and barely overhang the thin walls — there is no 12px hardware
sprite, so this is how we get the size. Each sprite is one `CALL CHAR(base,"<64 hex>")`. Roster
(keep numbers low for flicker):

| # | Sprite | Base char | Notes |
|---|--------|-----------|-------|
| #1 | Ms. Pac-Man | 96 | player |
| #2–#5 | Ghosts | 100 (shared pattern, different colors) | |
| #6 | Fruit | 104 | |

**Movement — `CALL LOCATE` only, never `CALL MOTION`.** All sprites are created with **zero
velocity** (`CALL SPRITE(...,0,0)`): that registers them "in motion" so the flicker routine sees
them, but they never drift. We set position every frame with `CALL LOCATE(#n,dotrow,dotcol)` —
fully deterministic, no runaway sprites.

**Coordinate mapping.** Maze cell `(R,C)` in screen char coords → sprite top-left in dot (pixel)
coords:

```
Y = (R-1)*8 - 3      X = (C-1)*8 - 3        (TI dot coords are 1-based; -3, not -4)
```

This centers the ~12px art on the actor's corridor cell; the art overhangs the **4px** walls by
only ~2 px each side, landing in the wall's transparent margin (misses the bar). Dot coords are
1..192 (row) / 1..256 (col). The movement code converts back the same way
(`C=INT((X+11)/8)`, aligned when `(X+3) mod 8 = 0`) so display and `GCHAR` collision agree.
Screen center is **col 16.5** — pen + Blinky are centered there (half-cell columns).

**Walls — thin 4px bars** (not solid blocks), drawn from a small **tile set** in `CHAR2`: h-bar
`0000FFFFFFFF0000`, v-bar `3C3C3C3C3C3C3C3C`, and 4 corners (codes 128–133). A 4px bar centered
in its 8px cell leaves a 2px margin each side, which the sprite overhang falls into.

**Color allocation (TMS9918A: 2 colors/cell, 1 color per set-of-8; sprites independent — see
`CLAUDE.md` §4).** One colored element per cell; each element in its own set:

| Element | Codes | COLOR2 set | Color |
|---------|-------|-----------|-------|
| Wall tiles | 128–135 | 13 | light blue (6) |
| Dots | 136–143 | 14 | white (16) |
| Power pellets | 144–151 | 15 | white/pink |
| Pen door / specials | 152–159 | 16 | pink (14) |

Sprites use `CALL CHAR` codes 96–107 + per-sprite colors, separate from all the above.

**Grid movement model** (steps 2+). Sprites step cell-to-cell along corridors; a turn is only
allowed at a cell center where the perpendicular lane is open; tunnels wrap at the screen edges.
Collisions/eating are tested on the **cell the sprite center occupies** (`GCHAR`), not pixels.

**Flicker / "sprite rotation"** (step 4+). `CALL LINK("FLICK")` rotates sprites so >4 on a line
all show (flickering). Requires the highest-numbered sprite in motion — already satisfied by our
`,0,0` velocities. **Compiled: FLICK is in RUNTIME10, free.** **Interpreted test: must
`OLD DSK1.HMFLICKER` then MERGE the program (never `NEW`)** so the routine is embedded.
Avoid CRAWL/CHSETD/speech/disk while flickering (possible memory conflicts per the docs).

## 3. Controls
ESDX diamond (`E`=69 up, `S`=83 left, `D`=68 right, `X`=88 down) **and** `CALL JOYST(1,X,Y)`.

## 4. Sprite art (placeholder hex — refined later)
~12×12 art centered in the 16px box (2px transparent ring), split into the 4 quadrant chars (see
§2 ordering). Pac mouth-right, ghost blob with eyes, cherry. Each sprite's 4 chars are defined
with a **single `CALL CHAR`** (one 64-hex string =
4 consecutive chars — see `CLAUDE.md` §4). Exact bytes are in `src/MSPAC.ti99`. Art polish (Ms. Pac
bow, animation frames, direction-facing) is a later step.

## 5. Game-state variables (short integers)
`PR,PC` Pac cell; `PD` Pac direction (0=none,1=up,2=left,3=right,4=down); per-ghost `GR(),GC(),GD()`;
`SC` score; `LV` lives; `DT` dots remaining; `K,S` input; `DR,DC` computed pixel coords; `G` GCHAR.
(`SC` may be renamed if the assembler flags it — see `CLAUDE.md` §6 reserved prefixes.)

## 6. Sound
Eat-dot blip, power-pellet, eat-ghost, death, fruit, level-start jingle — via `CALL SOUND`
(later optionally compiled to XB256 sound lists).

## 7. Memory & stack notes
≤6 sprites + small arrays + a DATA maze map. Maze map kept in `DATA`, `READ` once at level start.
Comfortably within budget.

## 8. Compiler-safety
Per `CLAUDE.md` §6: integer/fixed-point, `INT()` on `/`, `IRND`/`INT(RND*N)` for randomness,
`DELAY`/`SYNC` timing, no trailing `::`, no block `IF`, dot-free disk names, Screen2, `-X` output.

## 9. Build & run
Disk name **`MSPAC`**. Standard lifecycle (`CLAUDE.md` §8); see `README.md`. From step 4, the
interpreted-test boot changes to the HMFLICKER merge flow (§2).

## 10. Acceptance criteria
Per step (§12). Overall: plays like Ms. Pac-Man, compiles clean, `-X` runs identically.

## 11. Out of scope (for now)
Multiple maze layouts, cut-scenes, high-score table, two-player.

## 12. Incremental roadmap

Each step is a self-contained, compilable milestone. Build → test interpreted → compile `-X` →
confirm → next. Steps **1–2 are done**.

### Step 1 — Sprite + coordinate foundation ✅ DONE
Screen2; thin-wall playfield + 3-ghost pen; MAGNIFY(3) ~12px sprites; static placement; color
allocation. Validated MAGNIFY(3), quadrant order, colors, and the 1-based coordinate mapping.

### Step 2 — Player movement (`LOCATE`) ✅ DONE
Ms. Pac-Man glides via `LOCATE` under ESDX/joystick; buffered turns at cell boundaries; `GCHAR`
wall collision (maze-agnostic). Validated the movement engine.

### Step 3 — Real maze + dots  *(next)*
- **Goal:** replace the placeholder border/pen with a real, symmetric Ms.-Pac-style maze, fill it
  with dots, eat them, score, win on clear.
- **Tasks:** (a) **expand the wall tile set** — add T-junctions and a cross to the current
  h-bar/v-bar/4-corners, all 4px/blue/one set; (b) **maze as `DATA` strings** (one per row; each
  char a tile: wall-kind / dot / power-pellet / empty / door / tunnel), `READ` once and render via
  `HCHAR`/the tiles; (c) **dots** one per corridor cell (white) + **4 power pellets** (bigger,
  own set) at the corners; (d) **eating** — when Pac's cell holds a dot, blank it, `SC=SC+10`,
  decrement `DT`, blip; (e) **score/lives HUD**; **win** when `DT=0`; (f) **tunnels** — side gaps
  + wrap (deferred from Step 2; handle the left-edge so sprite X never goes invalid, or use
  `EARLYC`).
- **Decisions/risks:** maze layout (custom, fits 32×~22, symmetric about col 16.5); the tunnel
  edge-coordinate handling; later, optionally bake the rendered maze into a `COMPRESS`/`CWRITE`
  DATA blob for instant load. Power-pellet *effect* is Step 6 — here they're just big dots.
- **Validates:** maze representation + eating + win.

### Step 4 — Ghosts move + flicker
- **Goal:** the four ghosts leave the pen and chase; touching Pac costs a life.
- **Tasks:** (a) **generalize the movement engine** into a reusable routine driven by per-ghost
  state arrays (`GR()/GC()/GD()` + pixel pos); (b) **ghost AI** — start scatter/chase: each ghost
  has a target tile and picks the legal turn at each intersection that best reduces distance,
  **no reversing**; refine toward the classic 4 personalities; (c) **pen-exit sequencing** (one at
  a time through the door; door blocks Pac) + grid-snap on exit (pen starts are half-cell);
  (d) **`CALL LINK("FLICK")`** sprite rotation now that 5+ sprites can share a line —
  interpreted test needs the **HMFLICKER merge** boot (§2), free when compiled; (e) **collision**
  (Pac↔ghost) via `COINC` or cell match → trigger death (lives handled in Step 7).
- **Decisions/risks:** stack/speed with 4 movers — keep the engine a single shared `GOSUB`, arrays
  not strings (`CLAUDE.md` §5); flicker memory caveats (no CRAWL/CHSETD/speech while flickering).
- **Validates:** flicker + multi-sprite gameplay + AI.

### Step 5 — Fruit
- Ms.-Pac-style **roaming fruit**: enters from a tunnel after N dots, wanders the maze via the
  shared movement engine, exits; eating it scores a bonus; flicker-rotated. *(Could swap with
  Step 6 — power pellets are more central; fruit is lower-priority.)*

### Step 6 — Power pellets + frightened ghosts
- Eating a power pellet flips ghosts to **frightened**: change sprite color (blue, flashing white
  near the end), reverse + slow them, let Pac eat them for **200/400/800/1600**; an eaten ghost
  becomes "eyes" that return to the pen and respawn. Frightened **timer**; shrinks per level.

### Step 7 — Lives, levels, sound & polish
- **Lives** (start 3) shown on the HUD; death animation; respawn Pac + reset ghosts; **game over**
  at 0. **Levels:** clear → refill maze, faster ghosts, shorter fright time. **Sound:** waka,
  pellet, eat-ghost, death, fruit, start jingle — via `CALL SOUND`, or compiled **sound lists**
  (`SLCOMPILER`/`PLAY`) for background music + effects. **Polish:** Ms. Pac-Man **facing +
  mouth animation** (`CALL PATTERN` swaps direction frames), the bow, ghost eyes, attract mode.

## 13. Maze system (multi-maze, for changing mazes)

**Authoring → offline autotile → DATA.** Each maze is a plain symbol grid (`#`=wall, `.`=dot,
`o`=power pellet, space=empty). A generator (awk; see project history) **autotiles** each wall by
its 4-neighbor mask (N=1,E=2,S=4,W=8) and **flood-fills**, converting any unreachable dot to a
space (so no maze can trap dots). It emits one `DATA` string per row using this encoding:

| Char in DATA | Meaning | Screen char code |
|--------------|---------|------------------|
| `a`–`p` | wall tile (mask 0–15) | `128 + (ASC-97)` |
| `.` | dot | 144 |
| `O` | power pellet | 152 |
| space | empty path | 32 |

**16 wall tiles (codes 128–143)** are line-drawing pieces: a 4px center block plus 4px arms toward
each connected neighbor (mask 5 = vbar, 10 = hbar, 3/6/9/12 = corners, 7/11/13/14 = T, 15 = cross,
0 = isolated). Drawn 4px-thin so the 12px sprite overhang clears them (§2).

**Color (per maze).** Walls live in `COLOR2` sets 13–14, dots in set 15, pellets in set 16. A maze
changes color by re-setting sets 13–14 only. `DRAWMAZE` (`GOSUB 800`) picks the maze: `IF MZ=n THEN
RESTORE <line> :: WC=<color>`, then reads + renders 22 rows (screen rows 2–23) and counts dots.
Adding a maze = a new `DATA` block + a new `IF MZ=` line. Interpreted draw takes a few seconds;
instant compiled (optionally cache later with `COMPRESS`/`CWRITE`).

**Maze 1 source grid** (left 16 cols; full row = `L + reverse(L)`, symmetric about col 16.5):
```
################   #.###.#.###.#.#   #.#####.#.###.#   ###.#.###.#.#.#
#o....#.....#..    #...#.#...#.#.#   #.....#.#.#...#   #...#.#...#.#.#
#.###.#.###.#.#    ###.#.###.#.#.#   #####.#.#.#.#.#   #.###.#.###.#.#
#...#.#...#.#.#     #...#...#...#..   #  ..........#    #o....#.....#..
###.#.###.#.#.#    #.#####.#.###.#   #  ##.####.##.#   #.############
#...#...#...#..     #.....#.#.#...#   #  ..........#   ################
#.#####.#.###.#    #####.#.#.#.#.#   #####.#.#.#.#.#
```
(read top-to-bottom, left-to-right = rows 1–22). Regenerate the `DATA` if this changes.
