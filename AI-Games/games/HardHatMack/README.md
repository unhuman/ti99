# Hard Hat Mack (ColecoVision, CVBasic)

Faithful adaptation of the 1983 Electronic Arts / Apple II classic by Michael Abbot and
Matthew Alexander. Three construction-site screens:

1. **Beams and Bolts** — carry girder pieces into the 4 floor gaps, then rivet them with the
   jackhammer (once grabbed, it never lets go).
2. **Lunch Break** — collect 6 lunchboxes, then ride up under the electromagnet before the
   incinerator gets you.
3. **Rivet Works** — feed 6 steel boxes to the machines marked **IN**.

Dodge the **vandal**, the **OSHA man**, and **thrown bolts**. After level 3 the game loops
**faster with better-aimed hazards** (never more enemies).

**Controls:** joystick 1 — left/right walk, up/down climb, **fire** jumps. Title: fire to
start; `8-3-8` opens level select.

**Status:** in development, **ColecoVision-only** (see `DESIGN.md` §13). **Level 1 plays** —
walking, chain climbing, rounded jump, no-button elevator, bottom trampoline, vandal +
roaming jackhammer on fixed routes, bolts, gap-fill + rivet — all laid out from the
**ColecoVision version** (same VDP). **Level 2** is laid out cell-for-cell from the reference:
tiered beams, split top platform, full-height crane cable, two conveyor machines, six distinct
prizes, and the moving-magnet endgame. **Level 3** has a first-pass layout (pater-noster shaft,
six steel boxes, two IN hoppers) but has not been played through yet. Next: verify Level 3,
title screen, music. See `DESIGN.md` §11.

The **jump** is fixed as of 2026-07-26. Every "the jump is a mess" symptom — Mack rocketing to
the top of the screen, seizing in mid-air, dying on landing, or teleporting and reappearing a
floor lower — came from one line: `DIM jtab(15)` for a 16-step arc, so the last step of every
jump read a neighbouring variable as its `dy`. See the `DIM n(N)` note in `DESIGN.md`'s lessons
header; it is the reason the symptom kept changing shape whenever unrelated code moved.

## Build

- **ColecoVision (current target): `bash build-coleco.sh` → `src/hardhat.rom`** (ColEm / CoolCV).
  The TI-99/4A build (`build-ti.sh`) is retired -- it no longer fits the 24,336-byte single-bank cart cap. See DESIGN.md §13.


The build uses `src/HARDHAT.bas` with the **`unhuman/CVBasic`
fork**. Reference screenshots (ColecoVision level 1-2, Apple II level 3 + title)
live in `assets/`.
