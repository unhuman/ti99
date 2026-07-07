# Structris — CVBasic, TI-99/4A & ColecoVision

"Inverted Tetris": the machine builds the structure and throws pieces at *you*. Climb, duck, and
dodge along the skyline of a growing stack of blocks — don't get buried. Built in **CVBasic**,
**dual-target** from one source: TI-99/4A (native TMS9900 bank-switched cartridge ROM, `--ti994a`)
and ColecoVision (native Z80 ROM, CVBasic's default target) — not an XB256/compiler game.
Full spec in [`DESIGN.md`](DESIGN.md).

Original concept, piece catalog, and neighbor-height targeting AI: **Martin Haye**, 2010 (Apple II
/ Applesoft BASIC), introduced at KansasFest — [github.com/martinhaye/structris](https://github.com/martinhaye/structris).

## Play

- You stand on top of the block stack. Pieces (1-3 columns wide) fall from the ceiling, aimed at
  wherever you're standing, and permanently add to the stack's height where they land.
- Move left/right along the skyline, climb up into open shaft, or duck down into a valley between
  taller neighbors — whatever it takes to not be under a piece when it lands, or under the row a
  neighbor's build-up cell reaches.
- If a piece reaches your cell and there's nowhere left to climb, you're buried: game over.
- Every column built up past a shared height threshold "falls away" (the completed rows compact
  out) and counts toward the level. Clear enough rows and the level advances: the shaft narrows,
  pieces come faster. Survive all 10 levels to win.

## Controls (joystick 1)

| Action | Input |
|---|---|
| Move column | Joystick left / right |
| Climb / duck | Joystick up / down |
| Start / restart | Button |

## How it's built

- CVBasic **default video mode** (no `MODE` call — `MODE 2` compiles but renders broken on both
  machines; see `DESIGN.md` header) with 8 solid tiles at chars 128–135: seven piece colors plus
  the white border, colored per-character via `DEFINE COLOR` like every other CVBasic game in this
  repo. Player is a single un-magnified 8×8 sprite (a shaft column is exactly one tile wide).
- The **piece catalog and targeting AI are ported directly** from the original's
  `ON HL*4+HR+1 GOTO …` table: pieces are picked by comparing a target column's height to its two
  neighbors, so every piece **fits the terrain perfectly** — it falls from the ceiling as one
  rigid tetromino-like shape (all columns sharing a single fall counter) and slots flush onto the
  skyline in one landing. See `DESIGN.md` §5–6 for the full table and what got reinterpreted
  (the Apple II renderer's continuous hardware scroll has no TI-99 equivalent).
- A single push-or-die rule covers both "a piece falls through your row" and "a piece lands on your
  feet": every frame, if the player's cell is occupied, try to bump them up one row; no room left
  means game over.
- **No cross-platform pacing tricks** (unlike `games/Astiroids`' `pacen`): the main loop's per-frame
  work is trivial (one sprite, a few scalar updates), so both machines finish it comfortably inside
  one 60Hz NTSC vblank and a plain `WAIT` gives the same real-world speed on both — same approach
  as `games/Adventire`. No `#IF` platform branching needed anywhere in `STRUCTRS.bas`.

## Build

- **TI-99/4A:** `bash build-ti.sh` → `src/STRUCTRS_8.bin` (load in Classic99 or js99er).
- **ColecoVision:** `bash build-coleco.sh` → `src/structrs.rom` (load in CoolCV or blueMSX).

## Status

**TI-99 build verified playing in Classic99** (scripted emulator run: title → fire → pieces fall
with per-piece colors, joystick movement, push-up rule, idle player eventually buried → OOPS).
ColecoVision build compiles clean and shares all the same game logic; needs a CoolCV pass.

Two toolchain landmines were found (and are documented in `DESIGN.md`'s header): CVBasic's
`MODE 2` renders broken on both machines (use the default mode + `DEFINE COLOR`), and the
CVBasic 0.9.2 **TI-99 backend miscompiles `<comparison> AND <comparison>` conditions**
(stale-register AND → the original instant-OOPS bug) — every condition in this game is written
as nested single-comparison IFs.
