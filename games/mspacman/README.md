# Ms. Pac-Man (`MSPAC`)

A from-scratch Ms. Pac-Man for XB256, built **incrementally** — see `DESIGN.md` (§12 is the step
roadmap). Sprites (Ms. Pac-Man, ghosts, fruit) at `CALL MAGNIFY(3)` (double-size, 4 chars each),
moved with `CALL LOCATE` (never `MOTION`), 1-char-thick walls, and `CALL LINK("FLICK")` sprite
rotation so >4 sprites on a line don't vanish. Replaces the broken `mspacman-old/`.

- **Source:** `src/MSPAC.ti99`
- **Current step:** **Step 3a — data-driven maze** (autotiled thin walls + per-maze color;
  Ms. Pac-Man navigates it). Press **Q** to quit.
- **Status:** awaiting interpreted run + compile.

## Step 3a — what you should see / test
A **real maze** drawn from a `DATA` grid: **pink** thin (4px) walls (mask-autotiled so corners,
T-junctions and crossings connect cleanly), **white dots** in every corridor, 4 bigger **power
pellets**, and the HUD `MAZE 1 DOTS 290`. **Ms. Pac-Man** starts upper-left and drives around with
**E/S/D/X** or **joystick 1** — gliding, turning at cells, blocked by every wall.
- The maze takes a few seconds to draw interpreted (it decodes 22×32 cells); **instant compiled**.
- Walls should form continuous thin lines (autotiling working); dots white vs. pink walls (color
  split working).
- This proves the **multi-maze architecture**: a maze = a `DATA` grid + a wall color, drawn by
  `GOSUB 800`. Adding mazes later (incl. a TI-themed one) = another grid + color.

**Deferred to Step 3b:** eating dots, score, win-on-clear, and tunnels/wrap. **Step 4** brings the
ghosts back (with a proper pen) + flicker. (Ghost/fruit sprites are temporarily removed so 3a
focuses on the maze.)

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
