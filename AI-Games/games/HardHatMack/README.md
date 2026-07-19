# Hard Hat Mack (TI-99/4A + ColecoVision, CVBasic)

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

**Status:** in development — **Level 1 works (player-verified).** Walking, chain climbing,
rounded jump (12-px characters for head room), no-button elevator, bottom trampoline, vandal +
roaming jackhammer on fixed routes, bolts, gap-fill + rivet — all laid out from the
**ColecoVision version** (same VDP — chains are the climbable element, the tall columns are
decorative pillars). OSHA/second enemy is held for the post-loop difficulty ramp. Next: polish
items, then Level 2. See `DESIGN.md` §11 for the milestone list.

## Build

- TI-99/4A: `bash build-ti.sh` → `src/HARDHAT_8.bin` (load in Classic99 or js99er).
  Includes a hard guard against the 24,336-byte single-bank cart cap.
- ColecoVision: `bash build-coleco.sh` → `src/hardhat.rom` (load in CoolCV or blueMSX).

Both builds share the single source `src/HARDHAT.bas` and require the **`unhuman/CVBasic`
fork** (auto-defines `TI994A=1` under `--ti994a`). Reference screenshots (ColecoVision
primary, Apple II/Atari secondary) live in `assets/`.
