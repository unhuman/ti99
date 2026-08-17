# Bust-A-Bobble — CVBasic, TI-99/4A & ColecoVision

*The name is a play on the game's two: Taito shipped it as **Puzzle Bobble** in Japan and
**Bust-A-Move** in the West.*

Clone of Taito's **Puzzle Bobble** / *Bust-A-Move* (1994). A hex-packed field of coloured bubbles
hangs from the ceiling; aim the launcher at the bottom and fire a bubble along a ray that bounces
off the side walls and sticks on first contact. Three or more of a colour in contact pop, and any
bubble that loses its connection to the ceiling falls. The ceiling descends on a timer.
Clear the field to advance — let a bubble cross the death line and the round is over.

**30 static levels**, played in fixed order. Dual-target from one source: TI-99/4A (native TMS9900
cartridge ROM, `--ti994a`) and ColecoVision (native Z80 ROM) — not an XB256/compiler game.

Full spec: [`DESIGN.md`](DESIGN.md).

## Status

**Playable on TI-99/4A, all 30 rounds** (2026-08-16). Title screen with fire-to-start and an
`8 3 8` round selector; aim, fire, wall bounces, sticking, match-3 pops with a burst animation,
orphans falling away, scoring, the drop timer with its two-tone alarm, the board shake, and the
round-clear close/reveal. Both targets build from one source.

TI fixed area **22,658 B of 24,336 — 1,678 free** (checked by `assets/romcheck.py` on every
build); ColecoVision RAM **576 B of 814**.

The title screen has **two of the little green creature pacing either side of the name**, at 2× —
the same creature that counts your spare lives, generated from one 8×8 definition at both sizes so
they can never drift apart.

The **death line is yellow, and flashes red** when a bubble crosses it — including *through* the
bubbles sitting on it, which would otherwise hide the very thing the player needs to see. Those
bubbles are drawn from a variant character set carrying the dash through their middle with a 1px
black spacer either side, so the line stays one continuous dashed rule across the whole well
(`DESIGN.md` §11).

The HUD now carries a **drop-timer gauge** (8 chars, 64 steps, red for the last quarter) and
**spare lives as little green creatures** — see `DESIGN.md` §11. The arcade has neither: it drops
the ceiling on a *shot count* and shows no gauge at all, so both are deliberate additions that pay
for this game's timer-based drop being otherwise invisible.

Not yet built: music, the danger state, and the BUB mascot. ⚠️ Art growth means **music no
longer fits in the fixed area** — `DESIGN.md` §13 has the plan (levels + music into one bank
together, never separate).

Two open items, both measured and both pure data changes:
- **Difficulty does not ramp** (`DESIGN.md` §11b). Round 1 gives 240 s of doing nothing; the mean
  across 30 rounds is 108 s. Worse, difficulty is dominated by each level's *depth* rather than the
  timer, so the curve sawtooths — round 26 is more forgiving than round 9. The solver sharpens
  this: played out for real, **round 30 is the only round the drop clock ever constrains**.
- **Too many pre-made groups** (`DESIGN.md` §7). 85 pre-existing 3+ clusters across the 30 rounds,
  round 1 at 90% of its bubbles. They look poppable and aren't, because matches are only checked
  when a bubble lands. Fix identified.

**All 30 rounds are proven winnable.** Because the shot sequence is fixed, a round *can* be
impossible and nothing else in the build would notice, so `assets/solvelevels.py` re-implements the
game from the shipped `src/levels.bas` and `src/art.bas` (real fixed-point flight, real pixel
collision, real snap tie-breaks, real substitution rule, real drop clock) and searches each round
for a clearing line. It finds one for all 30, re-verified after the layout repair below.

`--anchors` additionally proves **no round ships a bubble that hangs from nothing**, which is the
defect that made rounds 9/10/15/20 misbehave three different ways before it was fixed at source
(`DESIGN.md` §16a).

`check_source_drift()` re-reads `BUSTABOB.bas` each run so the checker cannot go stale against a
tuned constant, and its predictions were **checked against Classic99 running the built cartridge** —
including an 80° shot that zigzags off both walls, which lands one cell left of a straight shot
exactly as simulated.

Because the solver has the lines, it can also hand them over. `solvelevels.py --report` writes
`assets/WALKTHROUGH.md` — every round's opening board, its fixed shot sequence, and a shot-by-shot
table giving the ball, the **aim as a step count off vertical** (with wall banks called out), where
it lands, and what it pops or drops; `assets/walkthroughhtml.py` renders the same data as a
shareable page with the boards in the game's real colours. Both are **generated on demand and not
checked in**: they are derived from the level data and the game's rules, so a committed copy goes
stale the moment a rule changes and then confidently describes shots that no longer work.

**Verified rather than assumed:** the character-alignment invariant the whole design rests on is
rendered at 4 ceiling offsets × 3 shake phases with the lattice overlaid and checked numerically
(0 violations); and the match flood fill is compared against a reference hex BFS over 4,000 random
fields (0 mismatches). The latter earned its keep — two separate "matches aren't popping" reports
turned out to be the *palette*, not the logic.

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
the field redraw, so aim and fire stay live. The clock never pauses — including through the burst
and the orphan fall, which used to stop it dead for half a second on every popping shot. The shake is render-only,
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
destination offset on a `SCREEN` blit sourced from a 40-byte RAM buffer:

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

The in-flight bubble is **two overlaid sprites** — cap and body — so it is pixel-identical to the
same bubble once it sticks and becomes characters. Falling debris uses a third, full-ball pattern:
drawn with the body pattern alone it looked like bottom halves.

**Every bubble is one hue, shaded by dithering** — solid at the top, then checks against black that
thin out downward, with the outline always solid. That is not a style choice, it is a bug fix. Two-
tone balls are identified by a *pair* of colours and this palette has no eight well-separated pairs:
red and "orange" shared a cap and differed by one body shade, so four touching "reds" wouldn't pop
because two were a different colour. One hue per ball removes the confusion by construction.
Density is per colour and is what separates close colours — white runs 2.2× denser than grey, which
their hues alone could never manage.

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

- **TI-99/4A:** `bash build-ti.sh` → `src/BUSTABOB_8.bin` (load in Classic99 or js99er)
- **ColecoVision:** `bash build-coleco.sh` → `src/bustabob.rom` (load in CoolCV or blueMSX)

> Requires the forked `cvbasic` (`unhuman/CVBasic`) for `#if TI994A`. Build **both** targets on
> every change. TI fixed-area budget is a hard 24,336 bytes — check it with
> `games/RallyX/assets/romcheck.py` after every build; `linkticart` truncates past it silently.
