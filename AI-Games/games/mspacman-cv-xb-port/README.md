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
- **Sound** is minimal (a few `SOUND` blips), not the XB jingles.
- **Per-maze wall colour** — all mazes render in one colour. (Recolouring needs four
  `DEFINE COLOR` tables or a verified colour-table address; the earlier VRAM-poke hack corrupted
  the display and was removed.)
- **Death / level-clear animations** are brief, and the **8-3-8 level/lives cheat** is omitted.
- Sprite draw offset (`sy-2, sx-1`) may need a ±1 tweak after eyeballing on hardware.

## Status
One-shot port; compiles. Runtime-tested by the user. Fixed after first run: real sprite art,
animated title (Pac + ghosts), sprites hidden on title entry/exit (no more game-over pollution),
removed the colour-table poke that corrupted the screen, and corrected collision/AI distance math
(CVBasic 8-bit subtraction wraps — `ABS()` over it and squaring negative diffs were both wrong).
