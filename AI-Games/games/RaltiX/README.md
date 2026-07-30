# RaltiX

Clone of Namco's **New Rally-X** (1981) for TI-99/4A **and** ColecoVision, written in CVBasic
(native code — not an XB256 game). Drive the blue car through a big scrolling maze (32×56
cells, transcribed from the arcade map rip), grab all 10 flags — one **S**pecial (doubles later
flags), one **L**ucky (fuel bonus) — dodge the red chase cars, lay smoke screens, watch the
radar on the right, and don't run out of fuel.

- **Status:** 🎮 Playable — M1–M3 emulator-verified in Classic99, M4 core in (title, rounds,
  challenge stages, jingles). The world renders at **2×2 chars per maze cell** (16-px roads —
  the 16×16 car fills its lane; the viewport shows 12×12 cells, so the radar matters).
  Deferred: in-game music, maps 2–4, rocks, per-round flag sets, Coleco runtime pass (see
  `DESIGN.md` §17). TI cart is **banked** (`BANK ROM 128`: bank 0 code+logical map, bank 1
  char map, bank 2 art/tables); Coleco builds flat. Building this flushed out three CVBasic
  TMS9900 codegen bugs (8-bit×big-constant → 0, dotted-constant folding truncates, CONST>255
  truncates) — documented in `DESIGN.md` §14 with workarounds in the source.
- **Controls:** TI: joystick 1 or E/S/D/X, fire or `Q` = smoke. Coleco: stick + left button.
- **Build:** `assets/genmap.py` → `src/map1.bas`, then CVBasic → xas99 → linkticart
  (`build-cvbasic-game` skill): `build/RALTIX_8.bin` (Classic99) and `build/raltix.rom`
  (ColecoVision). Build **both** targets every time.

See `DESIGN.md` for the full spec (screen layout, char/sprite tables, AI, scoring, budgets).
