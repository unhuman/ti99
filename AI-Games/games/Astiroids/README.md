# Astiroids — CVBasic, TI-99/4A

Classic Asteroids clone: rotate, thrust through inertial space, shoot the rocks, dodge the flying
saucer, survive. Built in **CVBasic** (`--ti994a`) as a native TMS9900 **bank-switched cartridge
ROM** (not an XB256/compiler game). Full spec in [`DESIGN.md`](DESIGN.md).

## Play

- Large → 2 medium → 2 small → gone. Clear the wave to advance (one more rock each wave, cap 6).
- A **UFO** appears periodically and shoots as it crosses — one bullet at a time, each flying the
  full width before it reloads. The large saucer aims at you 20% of the time, the small one 40%
  (small saucers are faster and jumpier, and their bullets fly faster too). Shoot it for
  200 / 1,000 points; it explodes when hit. Its bullets — and the saucer itself — can also shatter
  asteroids. **Don't fly into it:** crashing into the saucer kills you (and destroys it).
- Saucers appear often; if you stop shooting or stall on a wave, the **stall watchdog** brings them
  out even faster to pressure you.
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
  (ship + flame + 4 bullets + UFO + UFO bullet + 24-asteroid pool). Custom flicker: the ship is
  pinned to slot 0 (never flickers); every other sprite's slot is rotated each frame so the crowd
  flickers instead of the same ones vanishing.
- **Fixed-point ×64** positions for sub-pixel inertia; 16-step rotation via a sin/cos table.
- **Explosions in place** — a dead entity's slot plays the shared 4-frame blast, then frees itself.
- Per-frame software movement (no `CALL MOTION` in CVBasic); native TMS9900 speed handles it.
- **Cross-platform pacing, per-machine native rate:** the TI-99 naturally runs the main loop at
  **20fps** (measured with an on-screen loop counter; heavy per-frame sprite work spills past two
  60Hz frames), while ColecoVision holds a solid **30fps**. Rather than throttling Coleco down to
  the TI's rate, each machine runs its *own* native tick rate (`pacen`: 3 VDP frames/tick on TI,
  2 on Coleco -- a **required** compile-time constant, `-Dpacen=N`; see `build-ti.sh` /
  `build-coleco.sh`), and every frame-counted duration and per-tick velocity/cap in the game is
  rescaled from `pacen` so real-world game speed matches on both. Two formulas, both exact at
  `pacen=3` (so the TI build is unaffected): a *duration* (cooldown, lifetime, timer) scales by
  `*3/pacen`; a *per-tick increment* (velocity, a cap, a sound sweep step) scales by `*pacen/3`.
  Two genuine duty-cycle cadences (the thrust ramp, the rotation step) use a small phase
  accumulator instead of a scaled constant, since they're "how often", not "how much". Coleco now
  gets real benefit from its extra headroom (smoother motion) instead of just idling. Full
  derivation in `DESIGN.md` §14.
- Watch the CVBasic traps documented in `DESIGN.md` §12 (unsigned 16-bit compare **and** divide,
  `ABS` on 8-bit, sprite edge wrap, 8-byte bitmap char colors).

## Status

Playable — first complete version. Title screen, waves, UFO (large/small) with explosions,
scoring, extra lives, persistent session high score.

## Build

One `.bas` source, two targets — sprite magnification is set with the portable `VDP(1)=$E3`, so
nothing in the source is TI- vs Coleco-specific.

**TI-99/4A** (→ `src/ASTIROIDS_8.bin`, load in **Classic99** / **js99er**):

```
bash games/Astiroids/build-ti.sh
```

**ColecoVision** (→ `src/astiroids.rom`, load in **CoolCV** / **blueMSX**):

```
bash games/Astiroids/build-coleco.sh
```

Both scripts pass a **required** `-Dpacen=N` build-time constant (3 for TI, 2 for Coleco -- see
"How it's built" above); don't build `ASTIROIDS.bas` with the generic shared
`.claude/skills/build-cvbasic-game/build.sh`, which doesn't pass it (compile fails loudly if
`pacen` is missing, rather than risking a silent runtime divide-by-zero). The Coleco path compiles
with the default CVBasic target (no `--ti994a`) and assembles with `gasm80` (nanochess's Z80
assembler) straight to a 16 KB `.rom`. It fits ColecoVision's 1 KB RAM (757 of 814 bytes used).
All generated artifacts (`.a99`/`.bin`/`.txt`/`_8.bin` for TI, `.asm`/`.rom`/`.lst`/`.sym` for
Coleco) are git-ignored.
