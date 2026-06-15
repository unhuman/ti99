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
The **classic maze** (transcribed from the user-supplied reference, adapted to the TI's landscape
screen), drawn from a `DATA` grid centered at screen cols 3–30: **pink** thin (4px) walls
(mask-autotiled), **white dots** in the corridors, 4 corner **power pellets**, **side tunnels**
that wrap left↔right, and a central **ghost house**. HUD `MAZE 1 DOTS 212`. The compact house has
an **empty 2-cell door**, an **empty interior**, and a **dot-free open ring all the way around it**
(an "open square"). **3 ghosts sit in the house with the red one (Blinky) on top of the gate**, the
cherry just below the house in the open ring, and **Ms. Pac-Man** drives
with **E/S/D/X** or **joystick 1** — gliding, turning at cells, blocked by every wall, wrapping
through the tunnel.
- **Verified** (offline flood-fill): 212 dots, no dead ends, no "double-dot" parallel lanes, no
  sealed-off pockets, all dots reachable, and **zero dots inside the house or its surrounding ring**.
- The reference is portrait (28×31); the TI is landscape (32×24), so height was compressed
  (doubled wall rows + extra ghost-house rows dropped) and it's centered with 2-col tunnel-wrap
  margins.
- Multi-maze architecture still holds: a maze = a `DATA` grid + a wall color via `GOSUB 800`.
- Draws in a few seconds interpreted; **instant compiled**.

**Deferred to Step 3b:** eating dots, score, win-on-clear, tunnels/wrap. **Step 4:** ghosts start
moving (AI) + flicker.

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
