# JOUST

Williams' 1982 *Joust*, for the **TI-99/4A** and **ColecoVision**, in CVBasic from one
source. You ride a flapping ostrich; enemy knights ride buzzards. **The higher lance
wins.** The loser becomes an egg — and an egg you leave alone hatches back into a knight
one tier meaner.

## Status

**Phases 1-3 of 8 build and run on both targets.** See `DESIGN.md` §14 for the phase
plan; §0 records the arcade research the design is built on, including where sources
disagreed.

| phase | content | state |
|---|---|---|
| 1 | Flight, islands, lava, wrap, HUD, title | built |
| 2 | Knights, altitude combat, eggs, hatching | built |
| 3 | Waves, scoring, spare lives | built |
| 4 | Arcade font | **next** |
| 5 | Lava troll (wave 3+) | to do |
| 6 | Island erosion (bridge w3, ledges w6+) | to do |
| 7 | Pterodactyl (wave 8, and slow waves) | to do |
| 8 | Egg & Survival waves, bonuses | to do |

## Controls

| Action | TI-99/4A | ColecoVision |
|---|---|---|
| Flap | Fire, or space | Fire |
| Steer | Joystick 1 left/right | Joystick 1 left/right |
| Start | Fire on the title | Fire |

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
| TI-99/4A program image | 10,892 / 24,336 | 13,444 |
| ColecoVision ROM | 8,192 | — |
| ColecoVision RAM | 230 / 814 | 584 |

Plenty of room for phases 4-8 on both machines — unusually comfortable for this repo.
