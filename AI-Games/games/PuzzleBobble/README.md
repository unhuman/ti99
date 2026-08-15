# Puzzle Bobble — CVBasic, TI-99/4A & ColecoVision

Clone of Taito's **Puzzle Bobble** / *Bust-A-Move* (1994). A hex-packed field of coloured bubbles
hangs from the ceiling; aim the launcher at the bottom and fire a bubble along a ray that bounces
off the side walls and sticks on first contact. Three or more of a colour in contact pop, and any
bubble that loses its connection to the ceiling falls. The ceiling descends on a timer.
Clear the field to advance — let a bubble cross the death line and the round is over.

**30 static levels**, played in fixed order. Dual-target from one source: TI-99/4A (native TMS9900
cartridge ROM, `--ti994a`) and ColecoVision (native Z80 ROM) — not an XB256/compiler game.

Full spec: [`DESIGN.md`](DESIGN.md).

## Status

**Playable on TI-99/4A — round 1** (2026-08-15). Aim, fire, wall bounces, sticking, match-3 pops,
orphan drops, scoring, the drop timer, the board shake and the round-clear slide all work. Both
targets build from one source. TI fixed area **13,916 B of 24,336** (10,420 free, checked by
`assets/romcheck.py` on every build); ColecoVision RAM **354 B of 814**.

Only round 1 is authored, so rounds 2+ are empty placeholders and self-clear. Not yet built: title
screen, `8 3 8` setup, music, danger state, lives HUD, and the pop/drop sparkle.

**Design + level 1 + asset pipeline** (2026-08-15).

`assets/levels.txt` holds the authoring format with round 1 defined; `genlevels.py` packs all 30
rounds into `src/levels.bas` (1,860 bytes) and `prevlevels.py` renders them as full screen mocks.
The character-alignment invariant the whole design rests on is **checked, not just claimed** —
rendered at 4 ceiling offsets × 3 shake phases with the character lattice overlaid, and verified
numerically (0 violations). See `assets/level-01.png` and `assets/alignment.png`.

Open: whether the 30 layouts are transcribed from arcade reference screenshots at the cell grid or
authored fresh (`DESIGN.md` §7), and which of two circulating readings of the drop-scoring rule is
correct (`DESIGN.md` §11a — one line switches it). Neither blocks starting; layouts are data.

## Controls

| Action | TI-99/4A | ColecoVision |
|---|---|---|
| Aim left / right | `S` / `D`, or joystick 1 L/R | joystick 1 L/R |
| Fire | space, or fire | fire button |
| Pause | `P` | `1` |
| Setup (starting round, lives) | type `8` `3` `8` on the title | `8` `3` `8` |

The ceiling descends on a **timer**, not a shot count — 20 s at round 1, down to 12 s by round 30.
The warning is **audio-led**: a two-tone alarm starts ~1.3 s ahead, then the board gives one nudge
right-and-back just before the drop. Every shake phase is a full field redraw, so the shake's cost
scales with its length while audio costs the loop nothing — the warning got longer *and* cheaper.

**The game stays playable throughout**: the flying bubble is a sprite and moves independently of
the field redraw, so aim and fire stay live and the clock never pauses. The shake is render-only,
so a shot fired just before one still lands exactly where it was aimed. Everything that moves —
and every timer — is paced by **elapsed frames**, not loop passes, so a pass that overruns its
frame doesn't slow the game down.

## How it's built

The whole design hangs off one geometric decision: **every bubble is 2×2 characters and stays
character-aligned in every state the field can reach.** Bubbles are 16×16 on a 16-px pitch, the
hex stagger is exactly 8 px (one character), and — the part that matters — the **ceiling descends
8 px, one character row, at a time**. That translates the field by one name-table row as a rigid
body: no shifted pattern variants, no cell ever holding two different bubbles, no pattern-table
rebuild.

Which means the three motions in the game are all the *same* operation with a different
destination offset on a `SCREEN` blit sourced from a 36-byte RAM buffer:

| Motion | What changes |
|---|---|
| Board **shake** before a drop | the column origin, ±1 char, cycling LEFT/CENTRE/RIGHT/CENTRE one frame per phase (~0.27 s) — game stays playable throughout |
| Ceiling **drop** | the row origin, +1 char, with grey brick filling in behind it |
| Round-clear **slide** (the remaining bubbles scroll down past the bottom) | the row origin again, repeatedly, clipped at row 23 (~0.45 s) |

**The walls live in that same row buffer**, at indices `shkb` and `shkb+17`, with the field one
char inside. So walls, ceiling and bubbles slide as a single unit, nothing outside the blit ever
needs erasing, and the field spans the full well — which is what lets bubbles touch the walls.

A full field redraw is 12 row-pairs × 36 bytes = **432 bytes of VDP in one frame** — under the
576-byte blit RALLY-X already does per frame on both machines.

The rest is cheap by construction: one moving object, nine sprites, zero per-frame VDP reads
(the field is a 96-byte RAM array), no trigonometry (a 128-byte aim table generated offline, with
magnitudes stored positive and direction as a flag, because CVBasic compares `#var`s unsigned),
and no modulo anywhere (CVBasic compiles `%` to a real `DIV`, so row parity is `AND 1` and cell
index is `>> 4`). Total RAM ≈ 182 bytes, which fits ColecoVision's ~781 with room to spare.

The in-flight bubble is **two overlaid sprites** — lit cap and base body — so it is pixel-identical
to the same bubble once it sticks and becomes characters.

**Levels are puzzles, not slot machines.** Each round carries a fixed 32-entry shot sequence
alongside its layout, so a round is a solvable, learnable, comparable problem. A colour no longer
on the field is substituted deterministically, so the sequence can never hand out a dead bubble
and the round still replays identically.

**Scoring is why the score is a BCD digit array rather than a variable.** Popping pays 10 a bubble;
dropping pays 20 for the first bubble and doubles from there, capped at 1,310,720 — so a single
award can exceed a 16-bit integer before the score is even touched, and the arcade record is
30,331,990. Every award is a multiple of 10, so the score is stored in units of 10 and displayed
with a fixed trailing `0`: 8 stored digits become 9 shown, and a carry off the top clamps at
999,999,990 instead of rolling to zero.

## Build

- **TI-99/4A:** `bash build-ti.sh` → `src/PUZBOBL_8.bin` (load in Classic99 or js99er)
- **ColecoVision:** `bash build-coleco.sh` → `src/puzbobl.rom` (load in CoolCV or blueMSX)

> Requires the forked `cvbasic` (`unhuman/CVBasic`) for `#if TI994A`. Build **both** targets on
> every change. TI fixed-area budget is a hard 24,336 bytes — check it with
> `games/RallyX/assets/romcheck.py` after every build; `linkticart` truncates past it silently.
