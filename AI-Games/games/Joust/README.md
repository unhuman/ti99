# JOUST

Williams' 1982 *Joust*, for the **TI-99/4A** and **ColecoVision**, in CVBasic from one
source. You ride a flapping ostrich; enemy knights ride buzzards. **The higher lance
wins.** The loser becomes an egg — and an egg you leave alone hatches back into a knight
one tier meaner.

## Status

**All 8 phases build and run on both targets.** See `DESIGN.md` §14 for the phase
plan; §0 records the arcade research the design is built on, including where sources
disagreed.

| phase | content | state |
|---|---|---|
| 1 | Flight, islands, lava, wrap, HUD, title | built |
| 2 | Knights, altitude combat, eggs, hatching | built |
| 3 | Waves, scoring, spare lives | built |
| 4 | Arcade font | built |
| 5 | Lava troll (wave 3+) | built |
| 6 | Island erosion (bridge w3, ledges w6+) | built |
| 7 | Pterodactyl (wave 8, and slow waves) | built |
| 8 | Egg & Survival waves, bonuses | built |
| 9 | Arcade look, feel and sound: rock ledges, lava pit, score in the base, two-colour knights with running/skid/flap frames, momentum and skids, swept sound effects | built |

## Controls

| Action | TI-99/4A | ColecoVision |
|---|---|---|
| Flap | Fire, or space | Fire |
| Steer | Joystick 1 left/right | Joystick 1 left/right |
| Start | Fire on the title | Fire |
| **Start at a chosen wave** | type `8` `3` `8` on the title | `8` `3` `8` |

`838` opens a two-digit wave selector -- handy for reaching the parts of the game
that are otherwise a long way in: the **lava troll** appears at wave 3, the
**bridges burn** at wave 3, **Hunters** at 4, the **pterodactyl** at 8, ledges start
vanishing at 6, and **Shadow Lords** not until 16. It is not captioned on the title;
there is no room for a caption, which is why it is written down here.

**Flap is edge-triggered** — holding fire does not hover; each press is one impulse.
**It plays on momentum, like the arcade**: let go and the bird keeps going. On a ledge
the stick runs, and pushing against the run skids. In the air the stick turns you to
face; flap with it held to build speed that way.
**Nothing reads the vertical axis**: on the TI it shares a line with ALPHA LOCK, which
reports a direction that never releases.

## Scoring

| | |
|---|---|
| Bounder / Hunter / Shadow Lord | 500 / 750 / 1500 |
| Pterodactyl | 1000 |
| Egg, 1st / 2nd / 3rd / 4th+ this wave | 250 / 500 / 750 / 1000 |
| Egg caught in mid-air | **+500** |
| Survival wave completed intact | 3000 |
| Extra bird | every 20,000 |

Three lives; the HUD shows **spares**, right-justified, so a fresh game shows two icons
and the last life shows none.

**Egg waves** (5, 10, 15...) start with twelve eggs waiting on the ledges and no knights.
Every few seconds one of them stirs, cracks and hatches, so collect them first.
**Survival waves** (2, then 10, 15...) pay 3000 if you finish them without losing a bird.
Each wave opens with a banner naming it.

## Build

```
./build-ti.sh        ->  src/JOUST_8.bin    Classic99 / js99er
./build-coleco.sh    ->  src/joust.rom      CoolCV / blueMSX
```

Both need the **`preprocessor-if` branch of unhuman/CVBasic** (`#if TI994A` selects the
TI's hand-written array copies in `k_one`/`e_one`). The TI script also runs
`tools/isrpatch.py` between `cvbasic` and `xas99`; it trims the vblank interrupt (§1c)
and fails the build if the handler text it expects has changed.

Both scripts run the truncation gate (`tools/bigvar.py`, `tools/bigconst.py`) and
`tools/gosubtrace.py` **before** compiling, so an 8-bit overflow or a `GOSUB` that cannot
reach a `RETURN` fails the build rather than shipping.

Art is generated: `assets/genart.py` → `src/art.bas`. Edit the ASCII in the generator, not
the emitted bytes — it also does the TMS9918 quadrant interleave, which is not something
to do by hand.

## Sizes

| target | used | free |
|---|---|---|
| TI-99/4A fixed program image | 23,742 / 24,336 | 594 |
| TI-99/4A data bank 1 (art, font, tables) | 2,470 / 8,192 | 5,722 |
| ColecoVision ROM | 24,576 (14,280 used) | — |
| ColecoVision RAM | 678 / 814 | 136 |

## Speed

**The game runs a fixed 30 Hz tick on both machines**: one pass of the main loop every
two frames (`main_tick`), and every speed, gravity and timer is per pass. Measured in
play it holds 30 passes/sec on every wave from 1 to 16, on the TI and on ColecoVision;
the only dips are the death animation. `DESIGN.md` §1c has the numbers and what it took.

It used to run as fast as the work allowed, which on the TI was **15 passes/sec on
wave 1 and 10 by wave 12**, so the whole game slowed down as the arena filled. On
ColecoVision the same loop ran anywhere from 30 to 60, two to four times faster than the
TI and changing with the action.

Islands are indexed **by character row** (`ir1/ir2/ir3`) rather than scanned, which
is what makes the per-actor test O(1) — see §1b, including why the same saving must
*not* be taken by testing on alternate frames.
