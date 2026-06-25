# Ms. Pac-Man — CVBasic, faithful 1-shot port of the XB game

A direct CVBasic translation of `games/mspacman/src/MSPAC.ti99` (XB256), as opposed to the
ground-up `games/mspacman-cv` rewrite. The **maze layouts are reused verbatim** (the four `DATA`
strings), and the movement + ghost-AI logic is ported line-for-line.

Compiles clean: `cvbasic --ti994a mspac.bas mspac.a99` (then `xas99` + `linkticart.py`; see
`../mspacman-cv/README.md` for the full build chain).

## Translation map (XB → CVBasic)
- `M$()` wall cache → `VPEEK`/`VPOKE` of the screen (VRAM `$1800`); `scr(r,c)` = `DEF FN`.
- `CALL LOCATE/SPRITE` → `SPRITE n, sy-2, sx-1, frame, colour`; TI colour N → CVBasic N-1.
- `::` → `:`; XB block `IF` clauses → CVBasic `IF…THEN`/`END IF`.
- Ghost target distance: XB's `SG*dist` signed-compare → a `flee` flag (max vs min distance);
  squared differences forced to 16-bit so negative diffs don't wrap before squaring.
- Sprite art is the **actual TI art**, converted from the XB `CALL CHAR` quadrant hex
  (TL,BL,TR,BR interleaved to 16×16 rows).

## Known simplifications (not yet faithful)
- **Sound** uses an SFX-duration timer (CVBasic `SOUND` plays until silenced): dot waka, frighten
  warble, descending ghost-eat sweep, fruit chime + roam blip, an eye "pew" on turns, and a 3-voice
  original start jingle (12 chords, melody + harmony + bass) played once when a game begins.
- **Scoring** (HUD appends a `0`, so score = `#pt`×10): dot 10, power pellet 50, ghosts
  200/400/800/1600, fruit 100/200/500/700/1000/2000/5000, extra life at 10000 (three-bell sound).
- **Presentation:** data-driven start tune (`jingle_data`), 1-second "get ready" hold (`ready`)
  after a respawn and after the tune, blinking energizers (char 152 toggled), and a 2-frame ghost
  walk animation (sprite defs 5 and 10, alternated by `#fc`). Game over clears all sprites.
- Sprite draw offset (`sy-2, sx-1`) may need a ±1 tweak after eyeballing on hardware.

## Implemented since the first port
- Per-level **fruit shapes** (cherry…banana) via runtime `DEFINE SPRITE`; **level-clear flash**
  (sprites + sound cleared first); **death spin** animation; **8-3-8** title cheat (LEVEL/LIVES select).
- **Per-maze wall colour** (`setwc` + four `DEFINE COLOR` tables, walls 128–143 and the `+` cross):
  maze 1 magenta, 2 light blue, 3 light red, 4 dark blue — the XB `WC` palette (TI 14/6/10/5 →
  CV 13/5/9/4). Applied in `drawmaze` and restored during the level-clear flash.
- Ghosts: **reverse-on-energizer** (except already-scared), no reverse while scared, no reverse
  while exiting the pen (`gx<>121 AND gy<>77`).
- Ghost speed: distinct **Blinky > Pinky > Inky > Clyde** ranking via per-ghost caps `spc()`
  (Blinky 40≈100%, Pinky 16≈94%, Inky 12≈92%, Clyde 10≈90%); base `sp()` rises +4/level to each cap.
  **Cruise Elroy**: Blinky takes extra move-steps as the maze empties (`dt<30` every other frame,
  `dt<10` every frame), becoming the closer. A level-wide overdrive still boosts all chasers at `le>9`.
- **Timer audit:** every value that exceeds 255 is 16-bit (`#fc #ft #fb #mt #fw`). CVBasic 8-bit
  vars wrap at 256, which silently broke the scatter/chase (`mt=800→32`), fright (`fb=300→44`), and
  fruit-timeout (`fw>400`, never true) timers when ported from XB.

## Status
One-shot port; compiles. Runtime-tested by the user. Fixed after first run: real sprite art,
animated title (Pac + ghosts), sprites hidden on title entry/exit (no more game-over pollution),
removed the colour-table poke that corrupted the screen, and corrected collision/AI distance math
(CVBasic 8-bit subtraction wraps — `ABS()` over it and squaring negative diffs were both wrong).
