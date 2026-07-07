# Structris — Design

> CVBasic game, **dual-target**: TI-99/4A (native TMS9900 bank-switched cartridge ROM, `--ti994a`)
> **and** ColecoVision (native Z80 ROM, CVBasic's default target) from the *same* `STRUCTRS.bas` —
> not an XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic notes
> in `games/Astiroids/DESIGN.md` §12 (unsigned compares/divides, `ABS`, sprite wrap, char colors)
> apply here too. Sibling CVBasic projects: `games/Astiroids`, `games/Adventire`,
> `games/mspacman-cv-xb-port`.
>
> **TI-99 frame budget & time-based pacing.** The TMS9900 backend is slow enough that the naive
> per-frame loop missed vblanks (the TI ran ~20% slower than ColecoVision and stuttered). Two
> answers, both in the source: (1) hot paths precompute everything at spawn/landing (`bpx0/bpx1`
> per-bar pixel bounds, `sh1` per-column surface pixels, `pfr/pcv/ptpx/pgate` per-piece constants,
> a maintained `nact` count, row-clear only on landing frames, banded row-clear shift), so
> `rect_test` and the per-frame piece loop are compares/adds only; and (2) the fall accumulator is
> scaled by the elapsed `FRAME` delta (clamped to 4), so any frame that still slips becomes a 1-px
> catch-up step instead of a slowdown — both machines run the same real-world speed by
> construction. No platform `#IF` branching is needed anywhere in the source. (Verified in
> Classic99: the near-idle game-over loop blinks at exactly 60Hz — 532.8ms vs 533.3 expected — and
> gameplay fall rate measures ~60 game-px/s within screenshot-timing error.)
>
> **Do not use CVBasic `MODE 2` (hard-won lesson).** The first cut of this game used `MODE 2` with
> group colors poked at `$2010+`, exactly as the CVBasic manual describes. It compiled clean on
> both targets and rendered **broken on both**: on the TI-99 the custom tiles (pieces, borders)
> were invisible — the game "ran" but pieces landed unseen until a mystery OOPS — and on
> ColecoVision (CoolCV) the screen was blank with eventual garbage. Every working CVBasic game in
> this repo (Astiroids, Adventire, Ms. Pac-Man) uses the **default startup mode** (no `MODE` call
> at all) with `DEFINE CHAR` + `DEFINE COLOR` (8 per-row color bytes per char), and that pattern
> works on both machines. This game now does the same.
>
> **CVBasic 0.9.2 TI-99 codegen bug: comparison AND/OR comparison (hard-won lesson #2).**
> `IF PROW >= tlo AND PROW <= thi THEN …` compiles **wrong on the TMS9900 backend** (fine on Z80):
> the emitted short-circuit sets the first comparison's result in `r1` only on the *true* path;
> on the false path `r1` keeps a stale value from earlier code, and the final bitwise AND tests
> `cond2 AND garbage`. In this game that made `check_player` see a collision the instant the first
> piece spawned → instant "OOPS" on TI while the identical ROM logic played fine on ColecoVision.
> Confirmed by reading the generated `STRUCTRS.a99` listing (the broken `seto r1`/`clr r0`
> mismatched-register pattern at the `PROW >= tlo AND PROW <= thi` site) and by emulator bisection
> in Classic99 (frame-counter probes froze at exactly frame 21, the first spawn). Note
> `IF cont1.left AND PCOL > 1` compiles via a different, correct push/pop path — the bug only hits
> **pure comparison-AND/OR-comparison** shapes. **Rule: in this repo's CVBasic games, never write
> `<cmp> AND <cmp>` / `<cmp> OR <cmp>` in a condition — nest single-condition IFs instead.**
> Every condition in `STRUCTRS.bas` is single-comparison for this reason.

This document describes the game **as built**. Source of truth is `src/STRUCTRS.bas`; keep this
file in sync with any behavior change.

## 0. Provenance

Structris is Martin Haye's 2010 Apple II game (Applesoft BASIC + a 6502 scroll routine),
introduced at KansasFest — "an inverted Tetris": the computer builds the structure and throws
pieces at *you*; you dodge, climb, and duck to avoid getting buried. Original source:
`github.com/martinhaye/structris` (`Structris.asb`).

This port is a **faithful reinterpretation**, not a transliteration:

- **Ported verbatim:** the piece catalog (7 shapes/colors, ~19 concrete height-delta variants) and
  the neighbor-height-driven targeting rule (§5) — this *is* Structris' personality, so it's taken
  directly from the original's `ON HL*4+HR+1 GOTO …` table (lines 920–1645 of `Structris.asb`).
- **Reinterpreted:** the original's screen renderer is a continuous full-screen scroll driven by a
  hand-written 6502 routine (`CALL SC`) that we don't have full disassembly for, and it packs
  "row cleared" detection into hardware-specific low-res color reads. The TI-99 has no equivalent
  primitive, and CVBasic gives us a plain 32×24 tile grid instead — so this port models the
  structure directly as **per-column integer heights** (matching the original's own `H(I)` array),
  animates each piece as **one magnified sprite falling pixel-by-pixel from above the shaft to its
  landing row** (converted to background characters on landing), and turns "row cleared" into an
  explicit compaction step. The original's help text ("FINISHED ROWS
  FALL AWAY") describes exactly this outcome, so the reinterpretation matches the stated design
  even though the mechanism differs.

## 1. Concept & Objective

- Columns of blocks grow from the floor, a continuous **stream** of pieces (up to `MAXP = 6` in
  flight at once, `PGAP = 11` clear *pixels* between them — the original emits pieces 4 scan
  lines apart at 3 scan lines per cell row, ≈1.33 rows ≈ 11 px at 8 px/row) aimed at wherever
  you're standing. Falling pieces are **sprites descending 1 pixel at a time** (§6).
- You stand on top of the stack and move along its ragged skyline: left/right to change columns,
  up to climb higher into the open shaft, down to duck into a valley between taller neighbors.
- A piece descending into your cell **forces you down**; when the cell below you is blocked (the
  stack, the floor, or another piece), you're **smashed**: game over. You cannot ride a piece out
  from underneath — move *aside* before it reaches you.
- Clear enough rows (every column built up past a shared threshold, which then "falls away" and
  compacts the stack back down) to advance a level. Ten levels, each with a narrower shaft and
  faster pieces. Clear level 10 and you win.

## 2. Controls (joystick 1)

| Action | Input | Behavior |
|---|---|---|
| Move left / right | `cont1.left` / `cont1.right` | Slide `PSPD = 2` px per frame, only into free space (settled stack **and** falling pieces block, pixel-exact — the original tests `SCRN`, which sees both). |
| Climb up | `cont1.up` | Slide 2 px/frame upward, if the space above is free. |
| Duck down | `cont1.down` | Slide 2 px/frame downward, if the space below is free. |
| Start | `cont1.button` | Starts the game from the title screen. From the game-over or win screen, fire returns to the **title** (not straight into a new game). |
| 838 setup | keys `8`,`3`,`8` on the title | Opens the setup screen (same hidden convention as Astiroids): press `1`–`9` for the starting level, or `0` for level 10 — the game begins immediately. The choice persists for later games this session. Room is reserved for more 838 options later. |

**Movement is smooth pixels, like the falling pieces** — the player is a free `(PX,PY)` pixel
rect, not a cell occupant; horizontal and vertical axes are independent so the player can slide
along a surface while climbing or ducking. The move blip is throttled to one per 8 frames
(`move_cd`) so continuous movement doesn't buzz.

## 3. Screen & HUD

- **Mode:** CVBasic **default startup mode** (no `MODE` statement — see the header warning about
  `MODE 2`) — 32×24 text grid at VRAM `$1800`, 8×8 background tiles with per-row `DEFINE COLOR`
  colors, ASCII font preloaded, sprite plane independent of the tile colors. Plus `VDP(1) = $E3`
  + `SPRITE FLICKER OFF`: **2× sprite magnification** (16×16 defs render 32×32), the same setup
  as `games/Astiroids`.
- **Rows 0–15 (screen):** the shaft — shaft row `r` (1..16) renders at screen row `r-1`, so the
  shaft **ceiling is the screen top**: a piece sprite slides in smoothly from above the display
  (the VDP's $E0–$FF "negative Y" band) instead of popping out from under a text row.
- **Row 16:** floor border plus one column of vertical border tile on each side of the shaft,
  redrawn whenever the shaft width changes at a level-up.
- **HUD = a left sidebar** (the shaft is centered, so columns 0–8 are free even at the level-1
  width), inset one row/column from the corner for breathing room — three labeled blocks:
  `SCORE` at row 1 with the 5-digit value under it (row 2), `LEVEL` at row 4 with the level
  number under it (row 5), `CLEAR` at row 7 with the cleared/needed fraction under it (row 8).
  Labels print once per level (`init_level`); `draw_hud` refreshes only the values.
- **Rows 18–22:** message area — level-up banner (row 19), game-over "OOPS!"/stats/prompt (rows
  18/20/22, leaving row 23 as bottom breathing room), win screen, title
  screen help text. Reuses the same rows so nothing needs to be laid out twice.

## 4. Playfield & Column Model

- `W` = shaft width in columns, `W = MAX(5, 15 - LV)` — **14 at level 1** (the original's
  `W = 15 - LV` exactly), narrowing one column per level to 5 at level 10.
  Shaft is centered: left margin `ML = (32 - W) / 2`; column `c` (1..W) occupies text column
  `ML + c`.
- `SHAFT_H = 16` (fixed — only width shrinks with level, not height; two knobs shrinking at once
  made early playtesting math confusing, and width alone already scales difficulty well).
- **Two height arrays.** `H(1..W)` is the *settled* stack; `HF(1..W)` is the *forecast* — settled
  plus every in-flight piece's booking. Targeting and shape selection read `HF`, so a piece
  spawned while others are mid-flight aims at and fits the surface as it *will* be; landing moves
  the booking from `HF` into `H`. (The original updates its `H()` at emission time for exactly
  this reason.) A cell at row `r` in column `c` is settled-filled when `r > SHAFT_H - H(c)`.
- `MH = SHAFT_H - 3` — a column whose *forecast* is at or above this is "topped out" and skipped
  by the targeting logic (§5) so pieces don't pile past the ceiling.
- Player position `(PX, PY)`: **free pixels** (bar left edge / top, shaft-pixel space = screen
  space), clamped to the shaft interior. Movement into any occupied space is blocked pixel-exactly
  (`rect_test`: settled stack + all falling bars vs. the 4×2 player rect). Piece targeting reads
  the column under the bar's center pixel.

## 5. Piece Catalog & Targeting AI (ported from the original)

Every piece is 1–3 adjacent columns (`X-1, X, X0` — wait: `X-1, X, X+1`) receiving height deltas
`BL, B0, BR` (0–3 rows each) simultaneously. Target column `X` is chosen, then its shape is picked
purely from how its two neighbors compare to it — this is what makes the game feel like it's
"aiming" at your gaps.

**Targeting:** `X` starts at the player's own column, clamped to `1..W`. If `HF(X) >= MH` (all
height reads in targeting and shape lookup use the **forecast** `HF`, §4), scan
outward (`X+1, X-1, X+2, …`) for the nearest column still under `MH`. At the edges (`X=1` or
`X=W`), there's no real neighbor on that side — rather than reading a sentinel array slot (the
original's `H(0)=H(W+1)=-9` trick, which drifts over a long game since nothing ever resets it),
this port special-cases it directly: the missing side's `HL`/`HR` is just fixed at `3` ("very
different"), and that side's bar is skipped entirely rather than applied to a nonexistent column.
Earlier drafts clamped `X` to `2..W-1` to dodge the sentinel issue, but that meant the two edge
columns could only ever be a *neighbor*, never the direct target — and the shape table always
gives `BL`/`BR = 0` on a "very different" side, so an edge column that ever fell behind could
never grow again, permanently killing that column and, with it, any chance of `MIN(H) > 0` (see
§8) — rows could never clear. Letting `X` reach `1` and `W` directly (so the edge column gets
built via its own `B0`) fixes this.

**Shape lookup:** `HL = H(X-1) - H(X)`, clamped: if `HL < 0` or `HL > 3` then `HL = 3` (a neighbor
that's *much shorter* is treated the same as *much taller* — only "close" vs. "very different"
matters). Same for `HR = H(X+1) - H(X)`. Index `= HL*4 + HR` (0–15) selects a group from the table
below; a group with more than one entry picks uniformly at random (`RANDOM(n)`) each time, exactly
reproducing the original's variety within a given neighbor-height situation.

| HL,HR | BL,B0,BR variants (color) |
|---|---|
| 0,0 | (1,1,2)c1 / (2,1,1)c2 / (1,2,1)c6 / (1,1,1)c7 horiz |
| 0,1 | (1,2,1)c4 |
| 0,2 | (0,3,1)c2 |
| 0,3 | (3,1,0)c1 / (1,3,0)c2 / (2,2,0)c3 |
| 1,0 | (1,2,1)c5 |
| 1,1 | (1,2,1)c6 |
| 1,2 | (2,2,0)c4 / (1,3,0)c6 |
| 1,3 | (2,2,0)c4 / (1,3,0)c6 |
| 2,0 | (1,3,0)c1 |
| 2,1 | (1,3,0)c1 |
| 2,2 | (1,3,0)c1 / (0,3,1)c2 |
| 2,3 | (1,3,0)c1 |
| 3,0 | (0,3,1)c1 / (0,1,3)c2 / (0,2,2)c3 |
| 3,1 | (0,2,2)c5 / (0,3,1)c6 |
| 3,2 | (0,3,1)c2 |
| 3,3 | (0,3,0)c7 vert |

(Transcribed directly from `Structris.asb` lines 1200–1645's `ON HL*4+HR+1 GOTO …` table into the
`shape_data:` DATA statements in `STRUCTRS.bas`; that file is the source of truth if this table
and the code ever drift.)

Colors `c1..c7` map to seven distinct background-tile colors (§7); `c7` pieces are always either
pure horizontal (`1,1,1`) or pure vertical (`0,3,0`) bars.

## 6. The Stream, Falling, and the Smash Rule

- **Every falling piece is ONE 2×-magnified sprite, falling 1 pixel at a time.** The enabling
  invariant, verified against the whole shape table: **every piece fits a 3×3-cell box**
  (`baroff + barht ≤ 3` for all ~19 variants — the original's shape comments are all 3-row
  pictures), i.e. ≤24×24 px, inside one 32×32 magnified sprite (16×16 def, one cell = 4 def px).
  At spawn the piece's def (`1+p`, 32 bytes at `$3800 + (1+p)*32`) is composed directly in VRAM:
  columns `x-1`/`x`/`x+1` at def-x 0–3/4–7/8–11 (left byte = `$F0`/`$0F` nibbles, right byte =
  `$F0`), art **bottom-aligned** so a bar `(off,ht)` covers def rows `16-(off+ht)*4 .. 15-off*4`.
  Sprite X = the left-*neighbor* column's edge (`psx(p) = (ML+x-1)*8`; that third of the def is
  transparent when `x = 1`); sprite Y = `ppy(p) - 33` (piece bottom minus the 32-px box, minus
  the VDP's off-by-one), whose 8-bit wrap gives the smooth partial entry from above the screen
  top. While falling the piece touches **no tiles at all**; when it lands the sprite is hidden
  (`Y = $D1`) and its cells are painted as background characters in the same frame. Sprite
  budget: player (slot/def 0) + 6 pieces = 7; the ≥11-px gap means two pieces' 32-px boxes never
  share a scanline, so the worst case is 2 sprites on a line (one piece + the player) — no
  flicker rotation needed (`SPRITE FLICKER OFF`, repo convention).
- **Fall speed.** All pieces advance by the same per-frame pixel delta, dealt by an accumulator
  (`acc += 8` per frame; while `acc >= fpr` move 1 px) — i.e. 8 px (one row) every
  `fpr = MAX(2, 8 - LV/2)` frames, the exact average speed of the old one-row-per-`fpr`-frames
  step (level 1: exactly 1 px/frame). Because every piece moves the same `dy`, separations never
  change. A new piece spawns (re-aimed at the player's current column) the moment the newest one
  has fully entered plus `PGAP = 11` clear pixels; the first piece after a lull waits out a short
  `spawn_timer`. This mirrors the original's back-to-back emission (its state machine restarts
  the instant a piece finishes emitting, giving a ~1.33-row ≈ 11-px gap).
- **Each piece falls as a rigid unit.** Its up-to-3 bars share the piece's pixel position
  (`ppy(p)` = piece bottom, shaft top = 0) and all land **simultaneously** the moment the piece
  bottom reaches the center column's *booked* surface (`ppy >= ptarget(p)*8`, with
  `ptarget(p) = SHAFT_H - HF(X)` at spawn). Each side bar rides `baroff` rows higher — exactly
  its column's height advantage (`hl`/`hr`), the same number the shape was *selected* against
  (§5) — so at landing every bar is flush with its own column's surface at the same instant: the
  piece slots into the terrain like a pre-fit tetromino, never "compacting" against it
  bar-by-bar. This works because the shape table guarantees a side gets a bar **only** when its
  true height difference is 0–3 (a clamped-to-3 side always has a 0 delta), so a rigid perfect
  fit always exists. `rect_test` (movement blocking + the smash rule) is **pixel-exact**: bar
  `(off,ht)` occupies shaft pixels `[ppy-(off+ht)*8, ppy-off*8)`, tested for overlap against the
  player's 4×2 rect (each subtraction guarded against unsigned wrap). It also reports the deepest
  overlapping bar bottom (`rbb`), which drives the push-down.
- An earlier draft dropped each bar independently onto its own column (each with its own landing
  row) — pieces visibly broke apart mid-fall and "squished" onto the stack one column at a time.
  If piece behavior ever regresses to that, this shared-counter design is what got lost.
- **Forced down and smashed — pixel-exact.** Every frame, if a falling bar overlaps the player's
  4×2 rect, the player's top is snapped **down** to the deepest overlapping bar's bottom; if the
  pushed rect no longer fits — past the floor, into the settled stack, or into another piece —
  they are **smashed**: game over ("OOPS!"). This is the original's rule (Structris.asb 125–135:
  cell filled → below filled means death, else `CY = CY + 1`), made survivable at pixel scale:
  the 2-px-tall bar **rides down inside a stream gap** (~11 px of air) and can still slip out
  sideways — being confined is an escape opportunity, not instant death — but the gap between a
  landing piece and the surface closes to nothing, so standing under a landing is still fatal.
  (An earlier draft pushed the player *up*, letting them surf descending pieces — far too
  forgiving, and backwards from the original.) On the game-over screen the player sprite is
  **not removed** — it stays where they were buried, **blinking** (~half-second period,
  `blink_player`) until fire returns to the title; on the win screen it stays visible, steady.
- **Buried in settled cells is also death.** At fall speeds above 1 px/frame (level 2+, `dy` up
  to 4) a piece can jump from just-above-the-player straight to its landing in one step: it
  converts to background characters *while overlapping the player*, and no falling bar remains to
  push them. `check_player` therefore also smashes a player whose rect overlaps the **settled**
  stack (`qf` set with `rbb = 0`). Without this, the player was silently trapped alive inside the
  stack — unable to move, immune to every later piece (their column tops out and is skipped by
  targeting), riding level completions all the way to a free win (seen in play).
- **`H(c)`/`HF(c)` are hard-capped at `SHAFT_H`** the moment a booking or landing would push them
  over. This isn't cosmetic: heights are plain 8-bit **unsigned** values and `SHAFT_H - H` row
  math would wrap to ~250 if a neighbor column (never gated by `MH`) grew past the top — an
  uncatchable landing target that froze the whole piece pipeline in an early build.

## 7. Colors & Tiles

- Nine consecutive solid tiles, chars **128–136**: chars 128–134 are the seven piece colors
  `c1..c7` (red, light green, yellow, cyan, blue, dark red, gray on black), char 135 is the
  white-on-black border/floor tile, and char **136 is a black-on-black tile used for every empty
  shaft-interior cell** (instead of space) so the playfield background stays black when the
  win/game-over themes recolor the ASCII set. All nine share one `filled_bitmap` pattern; colors
  come from one `DEFINE COLOR 128,9,tile_colors` block (8 per-row color bytes per char,
  `fg*16+bg`), same as every other CVBasic game in this repo. A cell's char code is simply
  `128 + colorindex - 1`.
- **Per-cell colors — the screen is the color model.** There is no per-column color variable:
  when a piece lands, only its *newly added* cells are painted in the piece's color, so every
  settled cell permanently keeps the color of the piece that created it (pieces visibly hold their
  shape instead of the whole column repainting — the original's look). Falling pieces never touch
  the tiles (they're sprites, §6), so there is nothing to erase at landing — the old tile-animation
  ghost-cell problem is gone by construction. Row-clear compaction shifts cells down with
  `VPEEK`/`VPOKE` so colors move with their cells. Sprite colors for the falling pieces come from
  a small `colv(1..7)` map holding the same seven hues as the tiles.
- **CVBasic `FOR` checks its limit at the bottom**, so an empty range (`FOR r = 1 TO 0`) still
  runs once — the landing paint loop and the compaction shift are guarded with IFs for the
  column-full / full-clear edge cases.
- The standard preloaded ASCII font (chars 32–127) covers all HUD/message text — no `DEFINE CHAR`
  needed for text.
- Player sprite art is a full **16×16 `BITMAP` block** (rest transparent): CVBasic sprite
  definitions are always 32 bytes, so an 8-row bitmap would make `DEFINE SPRITE` read on into the
  following data (visible as garbage pixels beside the player — seen in emulator testing).
- Player: a **bar, 2×1 def px** in the def's top-left corner — **4×2 screen px** under the global
  2× magnification — solid white, at its free pixel position (`SPRITE 0, PY-1, PX`). The squeeze
  is the design: 2 px tall fits through the ~11-px stream gaps (§6). Independent of the tile
  color budget (sprite plane rule, CLAUDE.md §4).

## 8. Row Clearing & Leveling

- `RG = 5 + LV*2` rows required to advance — 7 at level 1, rising by 2 per level to 25 at
  level 10.
- **Scoring** (`#score`, 16-bit, reset at `new_game` so it spans all 10 levels): **1 point per
  landed piece**, plus a line-clear bonus by *simultaneous* rows — **10** for 1 row, **50** for 2,
  **100** for 3. Three is the true maximum: clears run after every landing, so the bonus is capped
  by what the *lowest* column can gain in one frame — one bar, height ≤ 3 (a second piece's bar in
  the same column always lands ≥ `PGAP` = 11 px of travel later than the first's, and 11 px > the
  max per-frame fall of 4 px, so same-column same-frame landings are impossible). Shown in the
  sidebar's top-left corner, updated at every landing/clear, and repeated on the win banner.
- After a piece lands, `newmin = MIN(H(1..W))`. If `newmin > 0`: `RD = RD + newmin`, then
  subtract `newmin` from every `H(c)` (the completed rows "fall away" — direct nod to the
  original's help-screen wording). On screen, each column's cells are shifted down `newmin` rows
  with `VPEEK`/`VPOKE` (preserving per-piece cell colors, §7) and the vacated top rows blanked.
  Every piece still in flight gets `ptarget(p) += newmin` (and `HF` drops with `H`) so it lands
  on the compacted surface instead
  of floating. The player's `PY` doesn't change (they don't fall with the compaction — they were
  standing above the cleared rows, not on them), which reads on screen as the player gaining
  clearance, a small reward beat for clearing rows.
- When `RD >= RG`: level-up banner, `LV = LV + 1`, `RD = 0`, all `H(c) = 0`, shaft re-centered for
  the new (possibly narrower) `W`, player recentered at the new floor. If `LV > 10`: win screen.
- **Terminal screens** — both recolor the ASCII set (chars 32–95) in four 16-char `DEFINE COLOR`
  chunks (16 is the repo's proven runtime-recolor size, from Ms. Pac-Man's maze recolor; all rows
  are one byte, so a single 128-byte table serves all four chunks), both prompt just
  **"PRESS FIRE"** (no reason given), and fire → **title** from both. Game over opens with an
  **explosion centered on the player**: the player sprite vanishes and four debris sprites
  (slots 7–10) play a **4-frame expansion animation** (defs 7–10, one per 10 frames over ~0.7 s:
  tight nucleus → small burst → mid spread → full shrapnel field — the particles start packed
  together and spread apart *within* the defs). The sprites themselves barely drift (1 px every
  5 frames, 8 px total) so the cloud stays anchored and reads as one cohesive blast, with a
  white→yellow→red→dark-red ramp and a three-pulse noise burst. Only then does the text go
  **white-on-dark-red** (`txt_red`, `$F6`) — the HUD/message area and the field around the shaft
  turn red while the board keeps its piece colors and the buried player keeps blinking. Win: a
  full **dark-green victory banner** (`txt_green`, `$FC`) — the board is cleared and the message
  prints on the solid green field (the old version printed over leftover playfield tiles and read
  as garbage). The **title screen restores** the normal white-on-black text colors (`txt_white`,
  `$F1`) before printing anything, and hides all 7 sprites.

## 9. Sound (SN76489)

- Move: short blip (channel 0).
- Piece landing: low thud per bar (channel 1).
- Row(s) cleared: short ascending jingle scaled by rows cleared.
- Level up: fanfare (channels 0+1).
- Game over: descending tone + noise channel hit.

## 10. Build & Run

Same `src/STRUCTRS.bas` builds both targets; only the toolchain differs.

- **TI-99/4A:** `bash build-ti.sh` — `cvbasic --ti994a` → `xas99` → `linkticart` →
  `src/STRUCTRS_8.bin`. Load in Classic99 or js99er. (Equivalently:
  `bash .claude/skills/build-cvbasic-game/build.sh games/Structris/src/STRUCTRS.bas "STRUCTRIS"`.)
- **ColecoVision:** `bash build-coleco.sh` — `cvbasic` (Coleco is CVBasic's default target, no
  `--ti994a`) → `gasm80` → `src/structrs.rom`. Load in CoolCV or blueMSX. Compiles with 216 of 814
  RAM bytes used — comfortable headroom on Coleco's 1KB.

Compiling only proves the source is well-formed; gameplay must be verified by actually running the
ROM (see `.claude/skills/verify` guidance — this game has not yet been played in an emulator on
either platform).

## 11. Acceptance Criteria

- [x] Compiles clean on **both** targets: TI-99 (`build-ti.sh` → `STRUCTRS_8.bin`) and
      ColecoVision (`build-coleco.sh` → `structrs.rom`).
- [x] Title screen shows controls/help; FIRE starts level 1. (TI verified in Classic99 —
      driven + screenshotted via the scripted harness; CV pending user verification.)
- [x] Pieces fall as **single magnified sprites, 1 px at a time** (sub-cell offsets visible
      between snapshots; smooth entry from above the screen top), target the player's column,
      convert flush to per-piece colored characters on landing, and use the shape/color catalog
      from §5. (TI verified in Classic99.)
- [x] Player renders as a 4×2 bar moving **smoothly in pixels** (2 px/frame, independent axes,
      pixel-exact blocking) and can survive inside the gaps between falling pieces; the smash
      rule still kills a player who stays under a landing piece; up to 6 pieces stream
      simultaneously with ~11-px gaps. (TI verified in Classic99: smooth climb/slide, player
      alive mid-stream between pieces, AFK player buried → OOPS.)
- [ ] Rows compact and count toward level-up; level-up narrows the shaft and speeds up play.
      (Code-verified + simulated; not yet observed in emulator.)
- [x] Getting buried shows "OOPS!" with a blinking player; fire returns to the **title**. The
      win screen is a dark-green banner with white text, and the title restores normal colors
      after it. (TI verified in Classic99 — the win screen via a scratch probe build that jumps
      straight to it; a full played-through win has not been performed.)
- [x] 838 on the title opens the setup screen; a digit picks the starting level (0 = 10) and the
      game begins at once — verified starting at level 5 (LV05, CLR00/09, 10-column shaft).
- [x] TI-99 and ColecoVision run the same real-world speed: the fall is FRAME-delta paced, and
      Classic99 measurements confirm 60Hz (blink probe 532.8ms/533.3 expected; fall rate ~60px/s
      within measurement error). CV still needs its user-side CoolCV pass.
