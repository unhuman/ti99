# JOUST

Williams' 1982 *Joust*, for the **TI-99/4A** and **ColecoVision**, in CVBasic from one
source. You ride a flapping ostrich; enemy knights ride buzzards. **The higher lance
wins.** The loser becomes an egg — and an egg you leave alone hatches back into a knight
one tier meaner.

## Status

**Phases 1-7 of 8 build and run on both targets.** See `DESIGN.md` §14 for the phase
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
| 8 | Egg & Survival waves, bonuses | **next** |

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

Three lives; the HUD shows **spares**, so a fresh game shows two icons and the last life
shows none.

## Build

```
./build-ti.sh        ->  src/JOUST_8.bin    Classic99 / js99er
./build-coleco.sh    ->  src/joust.rom      CoolCV / blueMSX
```

Both scripts run the truncation gate (`tools/bigvar.py`, `tools/bigconst.py`) and
`tools/gosubtrace.py` **before** compiling, so an 8-bit overflow or a `GOSUB` that cannot
reach a `RETURN` fails the build rather than shipping.

Art is generated: `assets/genart.py` → `src/art.bas`. Edit the ASCII in the generator, not
the emitted bytes — it also does the TMS9918 quadrant interleave, which is not something
to do by hand.

## Sizes

| target | used | free |
|---|---|---|
| TI-99/4A program image | 21,974 / 24,336 | 2,362 |
| ColecoVision ROM | 16,384 | — |
| ColecoVision RAM | 604 / 814 | 210 |

## Speed

**CPU is the binding limit, not the VDP.** `DESIGN.md` §1a-1c has the measured
numbers; the short version is that six knights of CVBasic physics do not fit in a
TI-99 frame, and the loop runs at **~15 passes/sec on wave 1 and ~10 on wave 12**.

Islands are indexed **by character row** (`ir1/ir2/ir3`) rather than scanned, which
is what makes the per-actor test O(1) — see §1b, including why the same saving must
*not* be taken by testing on alternate frames.

`lprate` draws the measured passes/sec as two digits at row 0 column 20. **It is a
temporary probe** and comes out once the frame rate is settled.
