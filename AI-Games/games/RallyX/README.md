# RALLY-X

Clone of Namco's **New Rally-X** (1981) for TI-99/4A **and** ColecoVision, written in CVBasic
(native code — not an XB256 game). Drive the blue car through a big scrolling maze (32×56
cells, transcribed from the arcade map rip), grab all 10 flags — one **S**pecial (doubles later
flags), one **L**ucky (fuel bonus) — dodge the red chase cars, lay smoke screens, watch the
radar on the right, and don't run out of fuel.

- **Status:** 🎮 Playable — M1–M3 emulator-verified in Classic99, M4 core in (title, rounds,
  challenge stages, jingles). The world renders at **2×2 chars per maze cell** (16-px roads —
  the 16×16 car fills its lane; the viewport shows 12×12 cells, so the radar matters).
  Flags and smoke are characters (drawn by `draw_view` in the same frame as the pan blit, which
  is what stopped them flickering), the car is a proper top-down F1 with **eight heading frames**
  that **rotate in place** (a reverse sweeps around instead of flipping — the Rally-X handling
  model), enemies turn too and never stack on one cell, smoke puffs are puff-balls of one colour,
  and the radar's player dot cycles white/black instead of blinking out. Game over hides the cars
  before the GAME OVER card and wipes the maze before the title returns.
  **Difficulty ramps** over rounds on four dials (car count, speed, how directly they come at
  you, and the head start you get) instead of opening at full tilt. Round 1 opens with the
  arcade's **three** chasers; a fourth joins at round 5. **Vehicle speeds are half** what they
  were — the game was outrunning the arcade; the halving is done at the fixed-point scale so the
  per-round ramp is unchanged, just at half scale. **Rocks** (lethal grey boulders) arrive from
  round 2, one more each round to 16 — the dial that keeps the curve climbing after speed, pursuit
  and car count have all maxed out. Placement is generated with a reachability proof so no round
  can be rocked into being unwinnable. Crashing destroys **both**
  cars with a BANG, twin blasts and a border strobe; enemies that meet each other bump, spin and
  leave in different directions, and can never share a cell — nor **overlap in pixels**, which is
  a stricter thing and was the bug the old cell-based check kept missing. Below full aggression a
  car takes a less direct line at you rather than driving away, so early rounds are gentler
  without the cars ever looking like they have stopped chasing. Background music is on two
  channels with an engine buzz on a third, and is **off by default** — press `1` on the title to
  turn it on. See `DESIGN.md` §17.
  **Pacing:** the loop is held to a fixed **30 Hz** (two frames a pass) rather than running at
  whatever the body costs — `WAIT` quantises to whole frames, so an unpaced loop oscillates
  between 2, 3 and 4+ and the irregular step size is what reads as stutter. Parked it is
  essentially locked; driving still has a tail owned by the camera pan blit. See `DESIGN.md`
  §10a for the measured per-subsystem costs.
  **Speed:** the loop was profiled on Classic99 and rebuilt from **8.2** game-loop passes/sec to
  **one pass per vblank** — 59.7/sec parked, 52.6/sec while driving with the camera panning. Game
  speed no longer varies with load either: the old `#fd` clamp discarded real time whenever the
  loop was busy, which is why the enemy cars appeared to speed up while the player sat still.
  See `DESIGN.md` §1a for the measurements and the two pacing rules.
  Open: **ColecoVision has never been run** (it builds every time, but only TI has been
  runtime-tested); late-round frame pacing (~3 frames per pass at round 9); per-round flag
  positions; challenging-stage fuel too generous for its own wake-the-cars rule. TI cart is **banked** (`BANK ROM 128`: bank 0 code+logical map, bank 1
  char map, bank 2 art/tables); Coleco builds flat. Building this flushed out three CVBasic
  TMS9900 codegen bugs (8-bit×big-constant → 0, dotted-constant folding truncates, CONST>255
  truncates) — documented in `DESIGN.md` §14 with workarounds in the source.
- **Controls:** TI: joystick 1 or E/S/D/X, fire or `Q` = smoke. Coleco: stick + left button.
  On the title screen: `1` toggles the music, `8` `3` `8` opens the hidden setup (cars + start
  level).
- **Build:** `assets/genmap.py` → `src/map1.bas`, then CVBasic → xas99 → linkticart
  (`build-cvbasic-game` skill): `build/RALLYX_8.bin` (Classic99) and `build/rallyx.rom`
  (ColecoVision). Build **both** targets every time.

See `DESIGN.md` for the full spec (screen layout, char/sprite tables, AI, scoring, budgets).
