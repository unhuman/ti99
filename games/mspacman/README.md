# Ms. Pac-Man (`MSPAC`)

A from-scratch Ms. Pac-Man for XB256, built **incrementally** — see `DESIGN.md` (§12 is the step
roadmap). Sprites (Ms. Pac-Man, ghosts, fruit) at `CALL MAGNIFY(3)` (double-size, 4 chars each),
moved with `CALL LOCATE` (never `MOTION`), 1-char-thick walls, and `CALL LINK("FLICK")` sprite
rotation so >4 sprites on a line don't vanish. Replaces the broken `mspacman-old/`.

- **Source:** `src/MSPAC.ti99`
- **Current step:** **Step 2 — player movement** (Step 1 geometry + Ms. Pac-Man moves under
  `CALL LOCATE`). Press **Q** to quit.
- **Status:** awaiting interpreted run + compile.

## Step 2 — what you should see / test
The Step-1 playfield (thin blue border + 3-ghost pen with red on top, white sample dots, static
ghosts + cherry), but now **Ms. Pac-Man moves** with **E/S/D/X** (up/left/right/down) or
**joystick 1**:
- She **glides** smoothly (2 px/frame) and only **turns at cell boundaries** (no mid-cell turns).
- A pressed direction is **buffered**: she keeps going until that direction opens up, then turns.
- **Walls block her** — she stops cleanly aligned against the border and the ghost pen, never
  overlapping into a wall bar.
- The other sprites (ghosts, cherry) stay put; dots aren't eaten yet.

If she's offset by a cell or doesn't line up with walls, it's the one shared centering constant
(`-4` / `+12` in the cell↔pixel math) — tell me and I'll nudge it.

**Deferred on purpose:** tunnel wrap (comes with the real maze, Step 3), Ms. Pac-Man facing her
direction of travel (art polish, Step 7), and blocking her from entering the pen door (Step 4,
when ghosts need the door).

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
