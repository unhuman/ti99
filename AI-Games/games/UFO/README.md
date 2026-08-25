# UFO!

Ed Averett's 1981 **UFO!** (Magnavox Odyssey²; *Satellite Attack* on Philips Videopac),
for the **TI-99/4A** and **ColecoVision**, in CVBasic from one source.

You fly an Earth Federation cruiser ringed by a **force field**. The field is your armour,
your ammunition and your best weapon all at once — and you only have one of it. Fire and
you cannot ram; ram and you cannot fire; either way you spend the next three seconds slow
and mortal.

## Status

**Phases 1-6 of 8 build and run on both targets.** See `DESIGN.md` §14 for the phase plan; §0 records the research the
design is built on, including where sources disagreed and which readings we took.

| phase | content | state |
|---|---|---|
| 1 | Space, ship, 8-way movement, wraparound, HUD, title | **built** |
| 2 | Force field: charge, drain, recharge, half speed, armed rule | **built** |
| 3 | Clockwise gun drift, laser | **built** |
| 4 | Drifters, ram kill, laser kill, death | **built** |
| 5 | Hunter-Killers and Light-speed Starships | **built** |
| 6 | Chain reactions | **built** |
| 7 | Death sequence, game over, high score | — |
| 8 | `838` setup, sound, difficulty | — |

## Controls

| Action | TI-99/4A | ColecoVision |
|---|---|---|
| Move (8-way) | Joystick 1 | Joystick 1 |
| Fire | Fire, or space | Fire |
| Start | Fire on the title | Fire |
| **Setup** | type `8` `3` `8` on the title | `8` `3` `8` |

`838` picks **ships (1-9)** and starting difficulty. The default is **one ship**, which is
what the cartridge gave you.

**Nothing reads the vertical axis for menus** — on the TI it shares a line with ALPHA LOCK,
which reports a direction that never releases.

## The force field

| | |
|---|---|
| Armed | **only at full charge** — full, or vulnerable. There is no in-between |
| Firing | costs a third of the field |
| Ramming | kills the enemy and empties the field |
| Recharge | about three seconds, and you move at **half speed** the whole time |
| Colour | black when empty, climbing to blue, **flashing cyan when armed** |

Watch the ring, not the score.

## Scoring

| | |
|---|---|
| Drifting satellite | **1** |
| Hunter-Killer | **3** |
| Light-speed Starship | **10** |

Faithful to the cartridge — a strong game reads about 60. Every kill launches **three
missiles**, which can kill other enemies and cascade, so the big scores come from chains.

## Build

```
./build-ti.sh        ->  src/UFO_8.bin    Classic99 / js99er
./build-coleco.sh    ->  src/ufo.rom      CoolCV / blueMSX
```

Both scripts run the truncation gates (`tools/bigvar.py`, `tools/bigconst.py`) and
`tools/gosubtrace.py` **before** compiling, so an 8-bit overflow or a `GOSUB` that cannot
reach a `RETURN` fails the build rather than shipping.

Art is generated: `assets/genart.py` → `src/art.bas`, `assets/genfont.py` → `src/font.bas`.
Edit the ASCII in the generators, not the emitted bytes — they also do the TMS9918 quadrant
interleave, which is not something to do by hand.

## Sizes

| target | used | free |
|---|---|---|
| TI-99/4A program image | 13,384 / 24,336 | 10,952 |
| ColecoVision ROM | 16,384 | — |
| ColecoVision RAM | 545 / 814 | 269 |

## Notes

The satellites are drawn by flipping between a `+` and a `×` — that is **the original's own
trick** for faking rotation on hardware that had none, and reproducing it is most of why the
game reads as *UFO!* rather than as a generic shooter.

The gun does not point where you push. It creeps **clockwise** around the ring toward your
heading and never takes the short way, so it is usually aimed at where you were. That is
faithful, it is the most-complained-about thing in every review of the original, and it is
the reason ramming is the real tactic.
