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
  were — the game was outrunning the arcade; the halving is done at the fixed-point scale.
  The **speed ramp climbs half as fast as it used to and now caps BELOW the player** (92% at
  round 9, was 125%): chasers can no longer outrun you in a straight line, which is the arcade
  relationship — the maze corners you, the cars don't outpace you. Round 1's speed is unchanged.
  **Cornering is no longer one-sided** either: the enemies' rotation is cosmetic, so a player who
  rotated in place was the only car paying for a corner — ~18 px of lost ground each time, which
  is what made round 4 unwinnable. A 90° turn now commits the heading at the junction and sweeps
  the sprite round **while the car drives on**, exactly as the enemies do; only a 180° reverse
  still rotates in place. The stick is **held, not queued**: centring it cancels a pending turn,
  so the car no longer turns off on its own long after you let go — hold the direction as you
  reach the junction. **Rocks** (lethal grey boulders) arrive from
  round 2, one more each round to 16 — the dial that keeps the curve climbing after speed, pursuit
  and car count have all maxed out. Placement is generated with a reachability proof so no round
  can be rocked into being unwinnable. **Challenging stages** (rounds 3, 7, 11 …) park the red cars
  until your tank runs dry, and a **crash ends the stage** — it costs a car and moves you on to the
  next round with the flag points you banked but no completion or fuel bonus, so the bonus round is
  no longer the most forgiving round in the game. Crashing destroys **both**
  cars with a BANG, twin blasts and a border strobe; enemies that meet each other bump, spin and
  leave in different directions, and can never share a cell — nor **overlap in pixels**, which is
  a stricter thing and was the bug the old cell-based check kept missing. Below full aggression a
  car takes a less direct line at you rather than driving away, so early rounds are gentler
  without the cars ever looking like they have stopped chasing. Background music is the New
  Rally-X theme read straight from the MIDI, on two channels with an engine buzz on a third (its
  pitch follows the heading), and is **on by default** — press `1` on the title to turn it off. It
  plays at **180 BPM**, deliberately quicker than the file's own 151: the tempo is a whole number
  of frames, so the choices are 150, 180 and 225, and 180 is the one that reads as a chase without
  turning into a gallop. The radar marks each flag in its **pennant
  colour** (ordinary yellow, special red, lucky cyan) and **flashes the special one**, which the
  arcade does and which also stops it reading as one of the red enemy dots. See `DESIGN.md` §17.
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
  positions; challenging-stage fuel too generous for its own wake-the-cars rule. TI cart is
  **banked and 64 KB** (banks 1–4 = the four char maps, bank 5 = art/tables/title); Coleco is
  128 KB, the floor `BANK ROM` allows. ROM is three separate budgets and only the 24,336-byte
  fixed area is scarce (185 B free) — see `DESIGN.md` §13; `assets/romcheck.py` audits every
  build after a silent truncation cost the music its last seven bars. Building this flushed out three CVBasic
  TMS9900 codegen bugs (8-bit×big-constant → 0, dotted-constant folding truncates, CONST>255
  truncates) — documented in `DESIGN.md` §14 with workarounds in the source.
- **Controls:** TI: joystick 1 or E/S/D/X, fire or `Q` = smoke. Coleco: stick + left button.
  On the title screen: `1` toggles the music, `8` `3` `8` opens the hidden setup (cars + start
  level).
- **Build:** `assets/genmap.py` → `src/map1.bas`, then CVBasic → xas99 → linkticart
  (`build-cvbasic-game` skill): `build/RALLYX_8.bin` (Classic99) and `build/rallyx.rom`
  (ColecoVision). Build **both** targets every time.

See `DESIGN.md` for the full spec (screen layout, char/sprite tables, AI, scoring, budgets).
