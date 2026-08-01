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
  **Difficulty ramps** over rounds on four dials (car count, speed, how often they actually chase
  you, and the head start you get) instead of opening at full tilt. Crashing destroys **both**
  cars with a BANG, twin blasts and a border strobe; enemies that meet each other bump, spin and
  leave in different directions, and can never share a cell. Background music plays on two
  channels with an engine buzz on a third. See `DESIGN.md` §17.
  **Speed:** the loop was profiled on Classic99 and rebuilt from **8.2** game-loop passes/sec to
  **one pass per vblank** — 59.7/sec parked, 52.6/sec while driving with the camera panning. Game
  speed no longer varies with load either: the old `#fd` clamp discarded real time whenever the
  loop was busy, which is why the enemy cars appeared to speed up while the player sat still.
  See `DESIGN.md` §1a for the measurements and the two pacing rules.
  Deferred: in-game music, maps 2–4, rocks, per-round flag sets, Coleco runtime pass. TI cart is **banked** (`BANK ROM 128`: bank 0 code+logical map, bank 1
  char map, bank 2 art/tables); Coleco builds flat. Building this flushed out three CVBasic
  TMS9900 codegen bugs (8-bit×big-constant → 0, dotted-constant folding truncates, CONST>255
  truncates) — documented in `DESIGN.md` §14 with workarounds in the source.
- **Controls:** TI: joystick 1 or E/S/D/X, fire or `Q` = smoke. Coleco: stick + left button.
- **Build:** `assets/genmap.py` → `src/map1.bas`, then CVBasic → xas99 → linkticart
  (`build-cvbasic-game` skill): `build/RALLYX_8.bin` (Classic99) and `build/rallyx.rom`
  (ColecoVision). Build **both** targets every time.

See `DESIGN.md` for the full spec (screen layout, char/sprite tables, AI, scoring, budgets).
