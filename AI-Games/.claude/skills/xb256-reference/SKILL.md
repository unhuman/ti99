---
name: xb256-reference
description: >-
  TI Extended BASIC language rules and the XB256 CALL LINK capability map for
  TI-99/4A games built with XB256 + the XB compiler: statement separators,
  IF/THEN/ELSE semantics, subprogram argument passing, Screen2 character vs
  sprite pattern tables, the TMS9918A two-colours-per-cell model, MAGNIFY
  sprite sizes, 1-based coordinates, scrolling and sound routines. Load this
  when writing or debugging an XB256 game (games/dotmuncher, games/mspacman) --
  it is NOT needed for the CVBasic games, which are the bulk of this repo.
---

# XB256 / TI Extended BASIC reference

Moved out of the always-loaded `CLAUDE.md` so it costs nothing in the CVBasic
sessions that make up most work here. The mandates, compiler landmines,
performance budget and per-game lifecycle stayed in `CLAUDE.md`.

## 3. TI Extended BASIC Language Rules (honor these exactly)

- **Multi-statement lines** use **`::`** as the separator: `CALL CLEAR :: A=1 :: B=2`.
- **`IF … THEN … ELSE`** — four forms: `IF cond THEN line#|stmt [ELSE line#|stmt]`.
  - THEN and ELSE clauses may each be several `::`-separated statements; they run **only** if
    their clause is taken.
  - **Everything after `THEN` up to `ELSE` is the true-branch; everything after `ELSE` to
    end-of-line is the false-branch.** There is **no unconditional fall-through** on the same
    physical line — to run something always, put it on the next line.
  - Numeric truthiness: any nonzero value is true (`IF A THEN …`).
  - A THEN/ELSE clause **cannot contain** `DATA DEF DIM FOR NEXT OPTION BASE SUB SUBEND`.
- **Subprograms:** `CALL name(args)` with `SUB name(params)` … `SUBEND` (and `SUBEXIT` for early
  return). Placed **after** the main program.
  - Simple variables and **whole arrays** pass **by reference** (changes propagate back);
    expressions/constants pass **by value**. Force by-value with extra parens: `CALL S((A))`.
  - Local variables persist between calls. Named subprograms consume stack and the compiler
    shortens their names to 6 chars — see §5/§2.

---

## 4. XB256 Capability Map — `CALL LINK("…")`

Default to **Screen2** (the reason we use XB256). Routines we actually use:

- **Screens:** `SCRN1` (standard XB screen) · `SCRN2` (256 definable chars; up to 28
  double-size sprites using Screen1 patterns) · `SCREEN`(color) (saved/restored per screen).
- **Chars & colors — two separate tables, don't mix them up:**

  | What you're drawing | Define pattern with | Set color with |
  |---------------------|---------------------|----------------|
  | **Screen2 background** (maze, HUD tiles, dots — anything drawn with `HCHAR`/`VCHAR`/`PRINT`/`DISPLY`) | `CALL LINK("CHAR2",code,pat$)` | `CALL LINK("COLOR2",set,fg,bg)`  (set 0–31, `INT((code-24)/8)`; 81 = all) |
  | **Sprites** (`CALL SPRITE`) | **`CALL CHAR`** (Screen1 table) | the color arg in `CALL SPRITE` / `CALL COLOR(#n,fg)` |

  This is an **XB256 rule, not a style choice**: sprites read the **Screen1** pattern table, so
  `CHAR2` has no effect on them — use `CALL CHAR` for sprite shapes.
  - **`CALL CHAR` defines up to 4 consecutive chars in one call** — the pattern string holds up to
    **64 hex digits** = four 16-hex (8-byte) characters, written to `code, code+1, code+2, code+3`
    (a short string zero-pads the rest of its char). So a whole 4-char MAGNIFY-3 sprite is **one
    line**: `CALL CHAR(96,"<64 hex>")` defines 96–99. Use this — it's less code. (`CHAR2` defines
    up to **8** per call and its strings can be much longer.)
  - **Quadrant order** for double-size sprites: base = TL, +1 = BL, +2 = TR, +3 = BR.
  - **"base ÷ 4" is a *sprite* rule, not a `CALL CHAR` rule.** `CALL CHAR` may start at any code,
    but a **MAGNIFY-3/4 sprite's base char must be a multiple of 4** (hardware masks the low 2
    bits). Put sprite bases on 4-boundaries (96, 100, 104, …).
  - Also: `CHPAT2` (read pattern), `CHSET2`/`CHSETL`/`CHSETD` (restore default / large caps /
    lowercase-with-descenders; also build inverse-video chars 160–255).
- **Color model (TMS9918A hardware — plan maze colors around this):**
  - **Each character cell shows exactly 2 colors** — one foreground (the lit dots) + one
    background — and color is assigned **per character set of 8 codes**, not per character
    (`COLOR2 set = INT((code-24)/8)`). So: **one colored element per cell** (a cell is wall, *or*
    dot, *or* pellet — never two differently-colored things), and put each distinctly-colored
    element in its **own set of 8** (wall set ≠ dot set ≠ pellet set). With 32 sets there's room.
  - **Sprites are an independent plane**: each sprite has its own foreground color and a
    transparent background, and does **not** consume a cell's 2-color budget — a sprite overlapping
    a wall just paints its own color on top.
- **Sprite sizes are hardware-fixed (`CALL MAGNIFY`, global — all sprites one size, no mixing):**
  1 = 8×8 (1 char) · 2 = 16×16 (1 char, blocky) · 3 = 16×16 (4 chars) · 4 = 32×32 (4 chars).
  **There is no 12px sprite.** To make a sprite *look* smaller, draw partial art inside a 16px
  MAGNIFY-3 box and leave the rest 0 (transparent). Geometry rule of thumb on an 8px grid: a
  sprite whose art is `W` px wide overhangs a flanking wall by `(W-8)/2` px per side; with **4px
  wall bars centered in their cells**, a 12px sprite's 2px overhang lands in the wall's transparent
  margin and misses the bar. Zero overlap needs 8px art (MAGNIFY 1) or 2-cell-wide corridors.
- **Coordinates are 1-based** (this bites — get it wrong and everything is 1px off). Sprite
  dot-row/col 1 = the **top-left pixel**; char cell `(R,C)` starts at pixel `((R-1)*8+1)`. To
  **center a 16px sprite box on cell `(R,C)`**: `Y=(R-1)*8-3`, `X=(C-1)*8-3` (the `-3`, not `-4`,
  is the 1-based correction). Use the *same* offset when converting a sprite's pixel position back
  to a cell for `GCHAR` wall checks, or display and collision will disagree. The 32-col screen's
  true center is **col 16.5** (between 16 and 17) — center symmetric layouts/sprites there. `WINDOW`(r1,c1,r2,c2) · `SCRLUP/SCRLDN/SCRLLF/SCRLRT` (add any arg = circular) ·
  pixel scroll `SCPXRT/SCPXLF/SCPXUP/SCPXDN`(ascii,len,#px) — parallax-capable · `CRAWL`(str$)
  (Star-Wars text crawl, Screen2).
- **Misc:** `IRND`(limit,var) fast random · `DELAY`(ms) · `SYNC` (with `CALL LOAD(-1,N)`) ·
  `DISPLY`(row,col,str[,dir,rep]) true 32-column print, any direction (col 1 = real column 1) ·
  `VREAD`/`VWRITE`/`CWRITE` (VDP RAM; `CWRITE` writes COMPRESS strings) · `PLAY`(addr) sound
  lists · `FREEZE`/`THAW` (stage many sprites, then start them together) · `HILITE`(r,c,len)
  inverse-video toggle · `EARLYC`(sprite) early clock / left-edge fade.
- **Asset pipeline (fast loading):** `COMPRESS` utility → MERGE `DATA` strings → `CWRITE` to
  blit screens/characters/colors/sound tables into VDP almost instantly. `SLCOMPILER` /
  `SLCONVERT` convert `CALL SOUND` music into compact **sound tables** that `PLAY` in the
  background while the game runs (two simultaneous players: music + effects).
- **Compiler note:** the compiler bakes XB256 in (it strips `LINK` and treats it like a `CALL`),
  **except** `CAT`, `RUN`, `RUNL1`, `SAVEIV`, `ST2VDP` — don't rely on those in compiled code.
