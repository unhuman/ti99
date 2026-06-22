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

| # | Sprite | Base char(s) | Notes |
|---|--------|-----------|-------|
| #1 | Ms. Pac-Man | 96 R / 100 L / 104 U / 108 D / 112 closed / 120 left-closed / 136,140 death-shrink | direction-facing + mouth animation; `CALL PATTERN` only on change. **Left needs its own closed frame (120 = mirror of 112)** so the bow stays on the back of her head when she chomps facing left (otherwise the mirrored-bow open frame flashes against the shared closed frame). **Up-facing (104) = down-frame (108) flipped vertically** so the bow sits on the *back* (bottom) of her head, not over her mouth. There's no spare slot for an up-closed frame, so **up-facing skips the chomp toggle** (line 423 forces `PP=104` even on the closed half-cycle) — the alternative would flash the bow-top closed circle (112) against the bow-bottom open frame |
| #2–#5 | Ghosts | 116 body (always) / 124 eyes / 132 blank | per-sprite color (`GC()`, `170`): Blinky **dark red 7** (was medium-red 9 — too close to the orange ghost), Pinky magenta 14, Inky cyan 8, Sue **dark-yellow 11** (the TI's nearest "orange"; was light-red 10, which vanished into Maze 3's light-red walls — so Pac moved to light-yellow 12 to free 11 for Sue); frightened dark-blue 5 (flashing white near timeout). **Feet wiggle by redefining foot chars 117+119 with `CALL CHAR`** so the sprite name never changes (avoids racing `FLICK`) |
| #6 | Fruit | **128 (single slot, redefined per level)** | roaming bonus fruit, created on demand. All shapes (cherry/strawberry/orange/pretzel/apple/pear/banana) share char 128; `GOSUB 1160` `CALL CHAR`s the level's shape into 128 + sets the color (`FFL`) **and point value (`FFP`)** — so the fruit set is unlimited without consuming char slots. Arcade value schedule by level: **cherry 100, strawberry 200, orange 500, pretzel 700, apple 1000, pear 2000, banana 5000** (level 7+); eating adds `FFP` (`771 PT=PT+FFP`). **Past the banana (level 8+) the fruit shape+value is chosen at random** (`1160`: `CALL LINK("IRND",7,FL)`), like the arcade's post-board mix. Fruit collision uses the **same window as ghosts** (`DX+DY<8`, line 434) — the earlier loosened `<14` let it be eaten from too far away |

> **Sprite char codes must stay ≤143.** `CALL CHAR` rejects higher codes (`BAD VALUE` interpreted;
> *silent VDP-motion-table corruption compiled* — ghosts get phantom velocities). The char table
> 96–143 is full, so distinct sprites must reuse freed slots — but **anything that's only shown one
> at a time (like the per-level fruit) can share a single slot and be `CALL CHAR`-redefined on the
> fly** instead of burning a slot per variant. `CALL LINK("CHAR2",…)` (Screen2 maze tiles) is
> unaffected — it spans the full 0–255.

All sprite art is reduced to **~10×10** centered in the 16px box (3px transparent margin each
side), generated from ASCII grids by `assets/spritegen.pl` (quadrant-ordered TI hex). Ms. Pac-Man
carries a small bow on her head (same color as her body — TI sprites are single-color).

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
Screen center is **col 16.5** (sprite X=121) — the pen interior, Blinky, and Ms. Pac-Man's start
all sit here, directly stacked. Ms. Pac-Man's movement grid only *stops* (turn-checks run) at
whole-cell positions (`SX≡5 mod 8`: 109/117/125/133...); a half-cell start needs a one-time
**kickoff** so the alignment check is ever reached at all — `CD` is initialized to a default
direction (4=right, or 3=left if the player is already holding left at boot) instead of 0, so she
immediately drifts ~4px to the nearest aligned cell, where normal turn-checking takes over. (A
sprite that starts unaligned **and** has `CD=0` would never move and never realign — `CD` would
never update from `DD` — so this kickoff is required for *any* sprite that starts at a half-cell
and is meant to move, including ghosts once Step 4 gives them AI.)

**Walls — thin 4px bars** (not solid blocks), drawn from a small **tile set** in `CHAR2`: h-bar
`0000FFFFFFFF0000`, v-bar `3C3C3C3C3C3C3C3C`, and 4 corners (codes 128–133). A 4px bar centered
in its 8px cell leaves a 2px margin each side, which the sprite overhang falls into.

**Color allocation (TMS9918A: 2 colors/cell, 1 color per set-of-8; sprites independent — see
`CLAUDE.md` §4).** One colored element per cell; each element in its own set:

| Element | Codes | COLOR2 set | Color |
|---------|-------|-----------|-------|
| Wall tiles (16 autotile masks) | 128–143 | 13–14 | maze color `WC` (pink/magenta=14 for Maze 1) |
| Dots | 144 | 15 | white (16) |
| Power pellets | 152 | 16 | **white (16), blinking** — set 16 fg toggled white↔transparent each ~4 frames (`435`/`436`) so the energizers pulse like the arcade |
| Pen door | 160 | 17 | white (16) |

Sprites use `CALL CHAR` codes 96–107 + per-sprite colors, separate from all the above.

**Grid movement model** (steps 2+). Sprites step cell-to-cell along corridors; tunnels wrap at the
screen edges. Collisions/eating are tested on the **cell the sprite center occupies** (`GCHAR`),
not pixels. **Ghosts** turn only at a cell center where the perpendicular lane is open.

**Ms. Pac-Man moves in two 1px sub-steps per frame** (lines 315/350–392 — same 2px/frame cruise,
but 1px resolution lets her sit at any offset). Each sub-step: if she's exactly centered she eats,
takes a square turn / wall-stop, and steps 1px; otherwise she may **corner-cut**.
**Cornering (her edge over the ghosts).** When a perpendicular turn is buffered into an open lane
and she is within **2px** of the upcoming center, she takes a **diagonal jump**: snap onto the new
lane (`JD` px) *and* jump `JD` px into the new direction in one sub-step, then `CD=DD` (lines
370–384). Head-start scales with how early you commit — `JD=2` → ~3px net gain (the early-input
case), `JD=1` → ~1px. The jumped-over intersection cell is eaten (`381`, with `EA=0` so the cut
keeps its speed). 1px sub-steps mean an odd-px cut still re-aligns at the next intersection (no
grid desync — verified by simulation). Ghosts don't corner, so she pulls ahead through turns.
**Stuck → stop, keep facing.** When her direction is blocked at a center and no new direction is
queued, she **stops** (`CD=0`, line 364). Her sprite frame is driven by a separate **heading** `HD`
(`419 IF CD<>0 THEN HD=CD`), not `CD`, so a stopped Pac **keeps facing the way she was last moving**
instead of snapping to face right. A nudge in any open direction resumes movement.

**Flicker / "sprite rotation"** (step 4+). `CALL LINK("FLICK")` rotates sprites so >4 on a line
all show (flickering). Requires the highest-numbered sprite in motion — already satisfied by our
`,0,0` velocities. **Compiled: FLICK is in RUNTIME10, free.** **Interpreted test: must
`OLD DSK1.HMFLICKER` then MERGE the program (never `NEW`)** so the routine is embedded.
Avoid CRAWL/CHSETD/speech/disk while flickering (possible memory conflicts per the docs).

## 3. Controls
ESDX diamond (`E`=69 up, `S`=83 left, `D`=68 right, `X`=88 down) **and** `CALL JOYST(1,X,Y)`. The
four keyboard checks, four joystick checks, and the reversal test are each folded into one
nested/`OR` line (`300`-`315`) to save compiler labels (≈one label per source line).

**Title screen (`1200`-`1243`).** Boot (`155`) and game-over (`1120`) both `GOSUB 1200`, so play
always opens on an **animated title** — Ms. Pac-Man glides left across the top, four ghosts glide
across the middle (both frame-animated), over `MS. PAC-MAN` / `2026 UNHUMAN` / controls / `PRESS FIRE
TO BEGIN`. The **most-recent score is drawn at `DISPLAY AT(1,1)`** (`1200`) — the *same row-1 spot the
HUD uses* (`708`), so it doesn't jump when play starts; a fresh boot shows `SCORE 00` (`PT=0`). The
wait loop **drains the launch key** (`WT`) before accepting a fresh fire / Space / Enter (else the
fast compiled build skips the title).

**`8-3-8` level select (cheat).** Typing `8 3 8` on the title (`CS` state machine, `1224`-`1227`,
keyed off `CALL KEY` *codes*) opens `LEVEL: 1-0` (`1230`-`1236`); a digit `1`-`9` / `0`(=10) sets the
start level. A **second prompt `LIVES: 1-9`** (`1237`-`1243`) then sets the starting lives the same
way. Both `LE` and `LV` are defaulted on the title (`1200`: `LE=1, LV=3`) and flow into the game, so
maze / fruit / ghost-speed / fright (`158`, `170`, `174`-`175`) scale for the chosen `LE` and the run
begins with the chosen `LV`. See README for per-feature detail and §8 for the compiler land-mines it
exposed.

## 4. Sprite art (placeholder hex — refined later)
~12×12 art centered in the 16px box (2px transparent ring), split into the 4 quadrant chars (see
§2 ordering). Pac mouth-right, ghost blob with eyes, cherry. Each sprite's 4 chars are defined
with a **single `CALL CHAR`** (one 64-hex string =
4 consecutive chars — see `CLAUDE.md` §4). Exact bytes are in `src/MSPAC.ti99`. Art polish (Ms. Pac
bow, animation frames, direction-facing) is a later step.

## 5. Game-state variables (short integers)
`PR,PC` Pac cell; `PD` Pac direction (0=none,1=up,2=left,3=right,4=down); per-ghost `GR(),GC(),GD()`;
`PT` score/points (`SC` is compiler-reserved — see `CLAUDE.md` §6 — so we use `PT`); `LV` lives;
`DT` dots remaining; `K,S` input; `DR,DC` computed pixel coords; `G` GCHAR.

## 6. Sound
Eat-dot blip, power-pellet, eat-ghost, death, fruit, level-start jingle — via `CALL SOUND`
(later optionally compiled to XB256 sound lists).

## 7. Memory & stack notes
≤6 sprites + small arrays + a DATA maze map. Maze map kept in `DATA`, `READ` once at level start.
Comfortably within budget.

## 8. Compiler-safety
Per `CLAUDE.md` §6: integer/fixed-point, `INT()` on `/`, `IRND`/`INT(RND*N)` for randomness,
`DELAY`/`SYNC` timing, no trailing `::`, no block `IF`, dot-free disk names, Screen2, `-X` output.

**Compiler label budget.** The XB compiler emits ≈one label per source line and has a finite table;
near it, the *last* code region's jumps start corrupting. Merge contiguous plain (non-`IF`)
statement lines with `::` to shed labels with zero behaviour change — that's free headroom (we used
it on the input block, sprite/char setup, COLOR2 and the jingle).

**Compiler jump-codegen hazards** (found building the `8-3-8` select; recorded in CLAUDE.md §2): this
compiler silently miscompiles some conditional jumps near program end. A bare single small-constant
comparison (`IF K<1` / `K>0 THEN <line>`) can come out comparing the *wrong variable*; a short
backward `GOTO`/`ELSE` whose target line **immediately follows another jump target** resolves to a
garbage label (→ `undefined symbol`, or a silent jump into unrelated code). Use compound `OR`
conditions, no standalone short backward `GOTO` (fold into `ELSE`), and put a buffer line before any
loop-back target. Verify by decoding the generated assembly (`MSPAC.TXT`, a DV80 TIFILES file).

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
- Eating a power pellet flips ghosts to **frightened** (`774`): blue, flashing white near the end,
  slowed, eaten for **200/400/800/1600**; an eaten ghost becomes "eyes" that return to the pen and
  respawn. Frightened **timer**; shrinks per level.
- **Reversal (arcade rule, `775`/`776`, applied *before* the frighten at `777`):** only ghosts in
  **normal** (chase/scatter) mode turn 180° on the pellet — gated `GS=0` **and** `GX<>121`, so a
  ghost mid-exit on the **gate column keeps climbing out** instead of being flipped back into the pen
  and bouncing (same guard the scatter/chase mode-switch reversal at `1173`/`1174` uses). Ghosts that
  are **already blue do not reverse again**; eyes are unaffected.
- **Eating a ghost** freezes the game ~0.5 s with a descending warble (`797`) before play resumes,
  like the arcade's pause on a ghost-eat.

### Step 7 — Lives, levels, sound & polish
- **Lives** (start 3, or the 838-cheat value) shown on the HUD. **The HUD is left intact through a
  death** — lives only visibly drop when play resumes (`GOSUB 708` at respawn). **Game over** (`LV<=0`)
  shows `GAME OVER` in a **centered black box** (`1111`: `FOR J=10 TO 14 :: CALL HCHAR(J,9,32,16)`)
  held **3 s** (`1112`), then returns to the title. **Levels:** clear → refill maze, faster ghosts,
  shorter fright time. **Sound:** waka, pellet, eat-ghost, death, fruit, start jingle — via
  `CALL SOUND`, or compiled **sound lists** (`SLCOMPILER`/`PLAY`). **Polish:** Ms. Pac-Man **facing +
  mouth animation**, the bow, ghost eyes, attract mode.

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
| `D` | ghost-house door | 160 |
| `+` | **thin 4-way cross** (custom hand-placed junction) | 168 |
| space | empty path | 32 |

**16 wall tiles (codes 128–143)** are line-drawing pieces: a 4px center block plus 4px arms toward
each connected neighbor (mask 5 = vbar, 10 = hbar, 3/6/9/12 = corners, 7/11/13/14 = T, 15 = cross,
0 = isolated). Drawn 4px-thin so the 12px sprite overhang clears them (§2). **Note `p` (mask 15)
is drawn *solid* on purpose** — it doubles as the interior of the 3-wide side-pocket walls (`hpn`).

**Custom tiles — `CHAR2` has the whole 0–255, so we are nowhere near a limit.** When the 16
autotile masks can't express a junction cleanly, hand-place a custom tile instead of compromising.
The first is **`+` = a *thin* 4-way cross at code 168** (`3C3CFFFFFFFF3C3C`), used where a hollow
box must connect to a 2-wide wall leg without the solid `p` poking a corner into the maze (maze 2,
line 9108, cols 8 & 21). Adding a custom maze tile = **four small edits**: (1) `CALL
LINK("CHAR2",code,pat$)` in the char-setup block; (2) give it the wall color by assigning its
`COLOR2` set to `WC` in `DRAWMAZE` (168 is in **set 18**, currently otherwise unused); (3) a
`IF P$="<sym>" THEN CD=code` arm in the render loop (a non-`.`/`O` symbol so it isn't counted as a
dot); (4) place the symbol in the `DATA`. **Critical:** if the tile is a wall, its color set must
also be toggled in the **end-of-level flash** (lines 1134/1135 set 13/14/**18** white↔`WC`), or it
sits static while the maze flashes.

`mazegen.pl` now **auto-emits `+` for any mask-15 cell with an open diagonal** (a solid `p` is the
only tile that fills its own corners, so it pokes a pixel into the maze at an inside corner). `p` is
kept only where all diagonals are wall — i.e. a genuine thick-wall interior like the `hpn`
side-pockets. So new mazes are poke-free out of the autotiler.

**Color (per maze).** Walls live in `COLOR2` sets 13–14, dots in set 15, pellets in set 16. A maze
changes color by re-setting sets 13–14 only. `DRAWMAZE` (`GOSUB 800`) picks the maze with **`ON MZ
GOSUB 8001,8002,8003,8004`** — each tiny per-maze stub just does `RESTORE <data-line> :: WC=<color>`:

| Maze | DATA block | `WC` | Color | Tunnels | Levels |
|------|-----------|------|-------|---------|--------|
| 1 | 9001–9022 | 14 | magenta/pink | 2 (rows 7,13) | 1–2 |
| 2 | 9101–9122 | 6  | light blue   | 2 (rows 2,17) | 3–5 |
| 3 | 9201–9222 | 10 | light red/orange | **1** (row 7) | 6–9 |
| 4 | 9301–9322 | 5  | dark blue    | 2 (rows 11 & 13, flanking the pen) | 10–13 |
| random | — | — | — | — | 14+ (one of 1–4, re-rolled each level) |

It reads + renders 22 rows (screen rows 3–24, leaving rows 1–2 as a HUD strip) and counts dots.
**`MZ` is chosen at level start** by a small sub (`GOSUB 1155`, from both the start `158` and the
level-advance `1140`): the known arcade order for levels 1–13 (`MZ=1 :: IF LE>=3…>=6…>=10` — nested
`IF`s, monotonic thresholds), then **random** for level 14+
(`IF LE>=14 THEN CALL LINK("IRND",4,MZ) :: MZ=MZ+1`).
Adding a maze = a new `DATA` block + one more entry in the `ON MZ GOSUB` list. Interpreted draw
takes a few seconds; instant compiled (optionally cache later with `COMPRESS`/`CWRITE`).

**Single-tunnel mazes.** The tunnel auto-detect (§ above) records the first empty-col-1 row as
`TY1`, the second as `TY2`. Maze 3 has only **one** tunnel (authentic), so `815` resets both to 0
and `831` falls back `IF TY2=0 THEN TY2=TY1` — roaming fruit then enters and targets the same
tunnel row instead of reading a stale `TY2` from the previous maze.

**Mazes 3 & 4 are authentic arcade layouts** (`assets/maze3-arcade.txt`, `maze4-arcade.txt`, from
shaunlebron/pacman-mazegen "MS. PAC-MAN (3)"/"(4)" — pulled via raw `curl`, since the summarizing
web-fetch corrupts ASCII; verified by diffing extracted mazes 1&2 byte-for-byte against the trusted
local files). Each 28×31 source was first collapsed to 28×22 by `assets/collapse2.pl` (drop doubled
wall-rows, carve the **fixed pen box** into grid rows 9–12 cols 10–19 so the ghost house stays put,
widen tunnels, place 4 energizers), then **hand-refined** to their current form (maze 3 grew a
taller symmetric pen with open lanes above *and* below it; maze 4's two tunnels were separated to
rows 11 & 13) and autotiled by `mazegen.pl`. Current validated figures (decode the in-file `DATA`
→ `mazegen.pl`): **maze 3 = 246 dots+pellets, maze 4 = 212**; both symmetric, 0 unreachable.
`assets/maze3grid.txt`/`maze4grid.txt` are the `#/./o` grids (decoded from the live `DATA`; they
round-trip back to it exactly through `mazegen.pl`).

**Tunnels are generic — no per-maze hardcoding.**
- *Wrap:* walls bound the actors everywhere except at the tunnel mouths, so a single edge test
  (`IF SX<13 THEN SX=229 ELSE IF SX>229 THEN SX=13`, and the ghost/fruit equivalents) wraps
  correctly for *any* maze — the only places X can reach the edge are the tunnels the author drew.
- *Tunnel Y (for fruit targeting):* detected **while rendering** — any row whose **column 1 is
  empty** is a tunnel row; the render loop records the first as `TY1`, the second as `TY2` (pixel
  Y = `(MR+1)*8-3`). Roaming fruit enters at one and aims for the other (`FTR/FTC`), so fruit
  works on a new maze with **zero** tunnel constants. Maze 1's tunnels are at DATA rows 7/13;
  Maze 2's at rows 2/17 — handled automatically.

**Tooling: `assets/mazegen.pl`.** Authoritative offline autotiler + validator (replaces the old
awk). Input is a plain 28×22 `#/./o/D/space` grid; it emits the encoded `DATA` lines, **flood-fills
from Ms. Pac-Man's start** (DATA row 17 col 14) clearing any unreachable dot, and **checks
left/right symmetry** about col 16.5. Used to fix Maze 2's hand-refactored tiles deterministically.

**Maze 2** (levels 3+) is the second authentic arcade layout, source `assets/maze2-arcade.txt`
(28×31, shaunlebron/pacman-mazegen "MS. PAC-MAN (2)"), collapsed to 28×22 and adapted the same way
as Maze 1 (same ghost-house box position — *the arcade keeps the pen in place across mazes*; only
the surrounding corridors and tunnel rows change). Verified: 220 dots+pellets, 0 unreachable,
symmetric. Drawn in maze color set 6 (`WC=6`).

**Maze 1 is the authentic arcade layout**, not generated — see `README.md` and
`assets/maze1-arcade.txt` (the source 28×31 arcade grid, from shaunlebron/pacman-mazegen). The
28×31 grid is collapsed to **28×22** by merging each pair of doubled wall-rows into one (shape
preserved, only the vertical scale changes), then autotiled + encoded to `DATA` per the table
above. It **verifies** (offline flood-fill): 224 dots+pellets, 0 unreachable, all sprites on legal
cells.

**Ghost-house pen** (DATA rows 10–12, cols 11–18): a 1-row interior (row 11, cols 12–17 — **6
cells wide**) behind a 2-cell door (row 10, cols 14–15, drawn as the white `D` tile, code 160).
This interior is wider than earlier draft mazes, which fits the 3 starting ghosts spread out
evenly with equal margins from each side wall, plus Blinky positioned directly above the door,
centered at col 16.5 (sprite X=121) — Ms. Pac-Man starts at the same X, directly below him, and a
default initial direction (§2) carries her off that half-cell start to the first aligned cell.

Additional mazes can still use a generated-block-maze approach (per-band horizontal corridors,
staggered vertical gaps, paddock stamp, dead-end-fill, etc.) if desired — that generator is not
part of this repo but the `DATA` encoding above is generator-agnostic.
