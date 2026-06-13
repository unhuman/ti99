# TI-99/4A Game Core Definition (XB256 + XB Compiler)

This repository builds games for the **TI-99/4A** in **TI Extended BASIC**, targeting Harry
Wilhelm's **XB Game Developer's Package** (the `JUWEL7/` folder): the **XB256** graphics/sound
extensions plus the **XB compiler** for arcade-class speed.

This file is the binding spec for **every** game in this repo. The toolchain is nuanced — the
compiler is integer-only and silently changes or drops many XB behaviors, and code must behave
**identically when interpreted in XB256 and after compilation**. Write to these limits from the
start; do not "write it twice."

> **Mandate (non-negotiable): every game targets XB256 *and* the XB compiler.**
> All code must run under **XB256** (load/test with XB256 active) and must be **compiler-safe**
> (§6). That means: use the XB256 `CALL LINK(...)` routines for what they cover (§4), stay on
> **Screen2** by default, and never use a construct the compiler rejects (§2) or a plain-XB idiom
> that only works interpreted. If a feature exists in both plain XB and XB256, prefer the XB256
> form. **One exception that is itself an XB256 rule:** *sprite patterns are defined with
> `CALL CHAR`, not `CHAR2`* — sprites read the Screen1 pattern table (see §4).

> **Golden rule:** Perfect the program in interpreted XB256 first, then compile. The compiler
> does almost no error checking and reports no line numbers at runtime — an undebugged program
> just "quits."

All facts here were taken from `JUWEL7/DOCS/` (`XB256.pdf`, `XB Compiler.pdf`, `Using XBGDP.pdf`)
and the TI Extended BASIC manual.

---

## 1. Toolchain & Target

- **Hardware model:** TI-99/4A console + **32K Memory Expansion (required)** + disk system.
  Extended BASIC cartridge. Use **XB 2.9 G.E.M.** *only* when making cartridges or when using
  `CALL PEEKV/POKEV/MOVE/STCR/LDCR`; otherwise plain TI Extended BASIC.
- **Dev environment:** **Classic99**, with the `JUWEL7` folder mounted as **DSK1**
  (Options → enable "Write DV80 as Windows Text"; leave "Write DF80…" off). Use **CPU overdrive**
  while compiling/assembling.
- **Default distribution target:** **XB loader (`-X`)** — the compiled program embedded in an XB
  loader, runnable/chainable from an XB menu. (Alternatives: `-E` EA5 for a standalone program;
  `.BIN` cartridge via `MAKECART8`/`MAKECARTG`, which needs XB 2.9 G.E.M. + Classic99
  QI399.055+.)
- **TI filename rule (important):** a TI disk filename **cannot contain a period** — `.` is the
  device separator (`DSK2.NAME`). So name compiler/assembler outputs with **hyphen suffixes, no
  dots** (`NAME-S`, `NAME-O`). A dotted name like `DSK2.MUNCH.TXT` is illegal and fails the OPEN
  with `I/O ERROR` (code 130, type 7). The `.TXT`/`.OBJ` forms shown in some Wilhelm docs are
  **only** valid on the Asm994a (Windows-text) path; on the bundled **TI assembler** path use
  dot-free names.
- **The 6-file pipeline** (mostly "press Enter"):

  | File | Meaning |
  |------|---------|
  | `NAME`     | XB/XB256 source program |
  | `NAME-M`   | same program saved in **MERGE** format (compiler input) |
  | `NAME-S`   | assembly **source** produced by the compiler (`-TXT` also fine; never `.TXT`) |
  | `NAME-O`   | assembled **object** code (`.OBJ` only on the Asm994a path) |
  | `NAME-E`   | compiled program, **EA5** format |
  | **`NAME-X`** | compiled program in an **XB loader** ← our default output |

  Flow: develop & test in XB256 → `SAVE` → `SAVE …-M,MERGE` → **Compiler** (output `NAME-S`) →
  **Assembler** (TI assembler → `NAME-O`, or Asm994a) → **Loader** (save `-X` / `-E`, or `RUN`).

---

## 2. Hard Compiler Constraints (integer-only) — drive all game math

- **Integers only, −32768…32767.** Overflow wraps: `200*200 = -25536`, `32767+1 = -32768`.
  Use **fixed-point** (e.g. store position×256, shift when reading) where you need fractions.
- **Division truncates.** Wrap **`INT()`** around any `/` or `SQR` in the XB source so the
  interpreted and compiled results match (e.g. `INT(5/2)` = 2 in both).
- **`RND` compiles to 0.** Always `INT(RND*N)` for a 0…N-1 result. Prefer
  `CALL LINK("IRND",limit,var)` (XB256) — same result *and* much faster. `RANDOMIZE` is a
  no-op (auto-seeded); for a repeatable sequence `CALL LOAD(-31808,n1,n2)`.
- **Delay loops do NOT translate** (`FOR I=1 TO 500::NEXT` ≈ seconds in XB, a blink compiled):
  - Timed delay: `CALL SOUND(ms,110,30)::CALL SOUND(1,110,30)` (the 2nd call blocks until the
    1st finishes), **or** `CALL LINK("DELAY",ms)` (1–30000 ms; sprites/sound keep running).
  - Fixed-period loop: `CALL LOAD(-1,N)` once, then `CALL LINK("SYNC")` just before the loop's
    `NEXT`/`GOTO` → each pass takes exactly N/60 s.
- **Not supported (will break / be dropped):** `SIN COS TAN ATN LOG EXP`, `DEF`, `IMAGE` &
  `DISPLAY USING`, `CALL ERR`. Trig workaround = precomputed **SINE255** string + `SEG$`/`ASC`
  (see `JUWEL7/SINE255` and XB Compiler.pdf p.7); `COS(a)=SIN(90-a)`.
- **Syntax landmines:**
  - **Never a trailing `::`** at the end of a line — it crashes the compiler.
  - User `SUB` names are truncated to the **first 6 letters** and must stay unique
    (`UPDATEWHITE`/`UPDATEBLACK` collide; `UPDATWHITE`/`UPDATBLACK` are fine).
  - **`RESTORE` must point to a `DATA` line, never a `REM`/`!`**. You cannot `GOTO` a `DATA` line.
  - `CALL LINK` name must be a **string constant** — `CALL LINK(A$,…)` will not compile right.
  - Keep `PRINT` lists to **≤20 items**. No `ON GOTO`/`ON GOSUB` **inside** an `IF/THEN/ELSE`.
  - `DISPLAY ERASE ALL` (with no print list) crashes the compiler — use `CALL CLEAR`.
- **Reserved names:** the compiler reserves ~1000 internal labels — `NC/NV/NA/SC/SV/SA…`,
  `L`+digit, and the full table on **XB Compiler.pdf p.12**. Game `SUB`/`CALL LINK` names must
  avoid these (and their 6-char truncations).
- **Supported and behaving like XB:** full `IF/THEN/ELSE` (incl. statement clauses),
  `FOR/NEXT/STEP`, `GOSUB/RETURN`, `ON GOTO/GOSUB`, arrays incl. **nested** `A(B(i))`,
  multi-assignment (`A,B,C=3`), string ops (`SEG$ POS LEN VAL STR$ CHR$ ASC RPT$ &`, 255-byte
  cap), `ACCEPT`/`DISPLAY AT`/`PRINT`, and the graphics/sound CALLs in §4. Up to three
  `DISPLAY,VARIABLE` files (`#1 #2 #3`) — `LINPUT`/`INPUT` for read, `ON ERROR line#` supported.

---

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

---

## 5. Memory Budget

- **Program space:** **24488 bytes** (drops to **17558** if XB256 is *packaged/merged* into the
  XB program rather than autoloaded).
- **Stack (VDP), reduced by XB256:** ≈ **9092** bytes at `CALL FILES(1)`, **8574** at `(2)`,
  **8056** at `(3)` — and less if you reserve a sound buffer with `CALL LINK("XB256",n)`.
- **Stack-saving conventions (adopt by default):**
  - Prefer **string constants** over string variables (`DISPLAY AT(1,1):"TEXT"` beats `A$="TEXT"`).
  - **Reuse one `A$`** when building/loading many strings; keep numeric var names short.
  - Keep bulk data in `DATA` and `READ` on demand instead of into string arrays.
  - Minimize **named subprograms** in hot paths; convert to `GOSUB`/`ON GOSUB` where possible.
- VDP memory map (for `VREAD/VWRITE/CWRITE`): screen image 0–767; sprite attr 768–879; sound
  buffer 2432–3071; Screen2 patterns 4096–6143; value stack 6176+. (Full map in XB256.pdf p.11.)

---

## 6. Compiler-Safe Coding Checklist

Every game's XB source must satisfy all of these so XB and compiled behavior match:

- [ ] Integer / fixed-point math only; explicit `INT()` on every `/` and `SQR`.
- [ ] Randomness via `INT(RND*N)` or `CALL LINK("IRND",…)`.
- [ ] Timing via `CALL LINK("DELAY",ms)` / paired `CALL SOUND` / `SYNC` — never raw `FOR/NEXT`.
- [ ] No trailing `::` on any line.
- [ ] `SUB`/`CALL LINK` names: unique in first 6 chars, not in the reserved list, `LINK` name a
      string constant.
- [ ] `RESTORE` targets a `DATA` line; no `GOTO` into `DATA`.
- [ ] No `SIN/COS/TAN/ATN/LOG/EXP/DEF/IMAGE/DISPLAY USING`; `CALL CLEAR` (not `DISPLAY ERASE ALL`).
- [ ] `PRINT` ≤20 items; no `ON GOTO/GOSUB` inside `IF/THEN/ELSE`.
- [ ] Default Screen2; output as `-X`.
- [ ] Fully debugged in interpreted XB256 **before** compiling.

---

## 7. Reference Assets (in repo)

- `JUWEL7/` demos to mine for patterns: `256DEMO`, `256DEMO2`, `APERTURE` (Adamantyr,
  compiler-compatible), `8QUEENS`, `HELLO`.
- `JUWEL7/SINE255` — trig workaround string. `JUWEL7/SOUNDLIB.txt`,
  `JUWEL7/TMLSOUNDPLAYER/`. `JUWEL7/FLICKERROUTINE/` — handles >4 sprites on one scan line
  (`CALL LINK("FLICK"/"FLICKX")`).
- `JUWEL7/DOCS/` — authoritative PDFs (XB256, XB Compiler, Using XBGDP, TI XB manual).
- Existing project material: `mspacman-old/`, `Adventure-Java/` (candidate first games).

---

## 8. Per-Game Structure & Lifecycle

Every game is built the same way — that consistency is the point.

**Folder layout** (`games/<name>/`):

```
games/<name>/
  DESIGN.md          # the spec — write BEFORE code (from templates/GAME-DESIGN-template.md)
  README.md          # one screen: concept, controls, status, build line
  src/<NAME>.ti99    # canonical paste-ready XB256 source (numbered listing)
  assets/            # COMPRESS DATA strings, char defs, sound lists (as created)
  build/             # -M .TXT .OBJ -E -X artifacts (git-ignored)
```

**Naming:** on-disk program name UPPERCASE and **≤8 chars** (TI filenames max 10; leaves room
for the `-M`/`-X` suffixes); folder name lowercase. Index every game in `GAMES.md`.

**Lifecycle — do these in order:**
1. Fill `DESIGN.md` from `templates/GAME-DESIGN-template.md`.
2. Author `src/<NAME>.ti99`, compiler-safe from line 1 (§6). Start from `templates/skeleton.ti99`.
3. Run **interpreted** in XB256 (Classic99, `JUWEL7` = DSK1); debug fully.
4. `SAVE DSKn.<NAME>` then `SAVE DSKn.<NAME>-M,MERGE`.
5. Compiler → Assembler → Loader; save **`<NAME>-X`**.
6. Run `<NAME>-X`; confirm it matches the interpreted behavior + the DESIGN acceptance criteria.
7. Commit `DESIGN.md`, `README.md`, and `src/`.
