# Astiroids — CVBasic, TI-99/4A

Classic Asteroids clone: rotate, thrust through inertial space, shoot the rocks, dodge the flying
saucer, survive. Built in **CVBasic** (`--ti994a`) as a native TMS9900 **bank-switched cartridge
ROM** (not an XB256/compiler game). Full spec in [`DESIGN.md`](DESIGN.md).

## Play

- Large → 2 medium → 2 small → gone. Clear the wave to advance (one more rock each wave, cap 6).
- A **UFO** appears periodically and fires a steady stream as it crosses. The large saucer aims at
  you 20% of the time, the small one 40% (small saucers are faster and jumpier). Shoot it for
  200 / 1,000 points; it explodes when hit. Its bullets — and the saucer itself — can also shatter
  asteroids. **Don't fly into it:** crashing into the saucer kills you (and destroys it).
- Saucers appear often and fire continuously; if you stop shooting or stall on a wave, the
  **stall watchdog** brings them out even faster to pressure you.
- Bullets carry the ship's momentum (forward shots are faster). 3 lives; extra life every 10,000
  points. High score persists for the session.
- Clearing a wave gives a couple seconds of free flight (ship not re-centered) to reposition
  before the next wave spawns.
- A deep heartbeat quickens as the field thins out.
- **838 setup:** type `8 3 8` on the keyboard at the title to open a setup screen — pick the number
  of ships (1–9) and the starting level (1–9) with the number keys, then FIRE to begin. A plain
  FIRE (no code) starts a normal 3-ships / level-1 game.

## Controls (joystick 1)

| Action | Input |
|---|---|
| Rotate left / right | Joystick left / right |
| Thrust | Joystick up |
| Fire (max 4 bullets) | Button |
| Hyperspace (no protection) | Joystick down |

## How it's built

- **VDP 2× magnification** — 16×16 sprite art renders 32×32; all 32 hardware sprite slots used
  (ship + flame + 4 bullets + UFO + UFO bullet + 24-asteroid pool). `SPRITE FLICKER ON`.
- **Fixed-point ×64** positions for sub-pixel inertia; 16-step rotation via a sin/cos table.
- **Explosions in place** — a dead entity's slot plays the shared 4-frame blast, then frees itself.
- Per-frame software movement (no `CALL MOTION` in CVBasic); native TMS9900 speed handles it.
- Watch the CVBasic traps documented in `DESIGN.md` §12 (unsigned 16-bit compare **and** divide,
  `ABS` on 8-bit, sprite edge wrap, 8-byte bitmap char colors).

## Status

Playable — first complete version. Title screen, waves, UFO (large/small) with explosions,
scoring, extra lives, persistent session high score.

## Build

```
bash .claude/skills/build-cvbasic-game/build.sh games/Asteroids/src/ASTIROIDS.bas "ASTIROIDS"
```

Produces `src/ASTIROIDS_8.bin` — load it in **Classic99** or **js99er** as a cartridge ROM.
(Generated `.a99`/`.bin`/`.txt`/`_8.bin` artifacts are git-ignored.)
