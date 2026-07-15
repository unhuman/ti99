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
> construction. (Verified in
> Classic99: the near-idle game-over loop blinks at exactly 60Hz — 532.8ms vs 533.3 expected — and
> gameplay fall rate measures ~60 game-px/s within screenshot-timing error.)
>
> **Per-target level-up flush (`#if TI994A` wipe / `#else` bake+drain).** `flush_level` hides the
> player + pieces (shared), then clears the shaft interior under a descending tone — but the clear
> itself diverges by target, for a **speed** reason, not just size:
> - **ColecoVision** does the full **drain**: it first **bakes** each still-falling piece into
>   piece-colour tiles (`128 + colour − 1`) where it hangs so the piece rides down *with* the stack,
>   then shifts the whole shaft interior down one row per frame so everything vanishes just above the
>   mountain. The per-frame row-shift is a VPEEK+VPOKE of every interior cell (~sh·sh·W VDP
>   round-trips) — cheap on the Z80.
> - **TI-99** does a lighter **wipe**: blank the interior one row at a time from the top downward
>   (no shift, no VPEEK), under the same descending tone. In-flight pieces just vanish (already
>   hidden). The full drain crawls on the slower TMS9900 (too many VDP round-trips per frame), so TI
>   takes the cheap wipe instead; it also keeps the bake out of the TI cart, which it can't spare.
>
> The shared `hide_sprites` before and `SOUND 2,,0` + `RETURN` after keep the divergence to just the
> clear body. The TI build fits (~114 B free) with two behaviour-preserving size opts: `draw_stage`
> loops the per-column `scol` instead of duplicating the flare logic, and the four pair-tile
> `DEFINE COLOR` calls merge into one `DEFINE COLOR 139,56,pcc1` (the fork accepts a colour count > 16
> — verified: char 194 colours correctly). The game-over text is a single line to save more.
>
> Both keep the walls-collapse afterward. This split needs the **forked cvbasic**
> (`unhuman/CVBasic`), which adds `#if/#elif/#else/#endif` keyed on a constant and **auto-defines a
> machine-name constant**, so `--ti994a` sets `TI994A = 1` and ColecoVision leaves it undefined — no
> `-D` needed (`build-ti.sh` passes only `--ti994a`). Stock nanochess CVBasic has no preprocessor
> and will not build this source.
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
  compacts the stack back down) to advance a level. Ten levels, each with a narrower shaft, a
  higher row goal, **and pieces falling faster** (ramping from half speed at level 1 up to the
  tuned level-10 speed, which is unchanged from before). Clear level 10 and you win.

## 2. Controls (joystick 1)

| Action | Input | Behavior |
|---|---|---|
| Move left / right | `cont1.left` / `cont1.right` | Slide `PSPD = 2` px per frame **× `#fd`** (frame-delta paced, capped at ×2 → max 4 px/step), only into free space (settled stack **and** falling pieces block, pixel-exact — the original tests `SCRN`, which sees both). The `#fd` scaling keeps the cursor at ColecoVision real-time speed when the TMS9900 drops a frame (see §6); a single destination check per axis, no per-pixel loop. |
| Climb up | `cont1.up` | Slide up at the same `PSPD × #fd` step, if the space above is free. |
| Duck down | `cont1.down` | Slide down at the same `PSPD × #fd` step, if the space below is free. |
| Slow cursor (precision) | **hold** `cont1.button` **during play** | Moves the **cursor** at half speed — the falling pieces are untouched — so you can thread a narrow gap without overshooting. Implemented in `handle_input` by halving the player's `pfd` (with an `smrem` odd-frame carry so it's *exactly* half, not lossy); the pieces stay full speed because they key off `#fd` in `main_loop`, which is not touched. Releasing FIRE snaps back to full speed. |
| Start | `cont1.button` | Starts the game from the title screen. From the game-over or win screen, fire returns to the **title** (not straight into a new game). Fire double-duties as the in-play slow-cursor hold, but `game_over_rel`/`win_rel`/`title_rel` each wait for a **release** before accepting a press, so a button held for precision at the moment of death can't skip the terminal screen into a new game. |
| 838 setup | keys `8`,`3`,`8` on the title | Opens the setup screen (same hidden convention as Astiroids): press `1`–`9` for the starting level, or `0` for level 10 — the game begins immediately. The choice lasts **one game only** — every return to the title resets the starting level to 1, so re-enter 838 to pick again. Room is reserved for more 838 options later. |

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
- **HUD = sidebars** (the shaft is centered, so columns 0–8 / 25–31 are free even at the level-1
  width), inset one row/column from the corners for breathing room. Left: three labeled blocks —
  `SCORE` at row 1 with the 5-digit value under it (row 2), `LEVEL` at row 4 with the level
  number under it (row 5), `CLEAR` at row 7 with the cleared/needed fraction under it (row 8).
  Right: a mirrored `HIGH` block (rows 1–2, right-aligned) with the session high score. Labels
  print once per level (`init_level`, which also prints the `HIGH` value — it only changes at a
  game over/win); `draw_hud` refreshes only the left-side values.
- **Rows 18–22:** message area — level-up banner (row 19), game-over "OOPS!  BURIED!" (single line,
  row 19) + "PRESS FIRE" (row 22), win screen, title screen help text. The game-over line carries no
  level number (the `LEVEL` HUD already shows it). Reuses the same rows so nothing needs to be laid
  out twice.

## 4. Playfield & Column Model

- `W` = shaft width in columns, `W = MAX(6, 16 - LV)` — **15 at level 1**, narrowing one column
  per level to **6 at level 10** (one wider than the original at both ends, for fairer play).
  Shaft is centered: left margin `ML = (32 - W) / 2`; column `c` (1..W) occupies text column
  `ML + c`.
- **The STAGE** (per the original): the game lives on a black-and-white checkered **mountain**
  (4×4-px squares, chars 137/138) — narrow at the top (one lip column beyond each wall, where the
  walls stand and the stack rests) and **flaring outward one column per side on every row** all the
  way down to the floor (row 17), a full triangle. As the shaft shortens each level (`sh` rises)
  the mountain **grows taller and its base wider**, filling the space below instead of floating up
  as a thin pedestal with black beneath it. The stage top **rises half a character per level**,
  shortening the fall. The playable height
  `sh = SHAFT_H - LV/2` loses a full row on each even level (16 rows at level 1 down to 11 at
  level 10), and on **even levels the whole floor is additionally shifted down half a character**
  (`hoff = 4` px, folded into `sh1`, landing targets `ptpx`, and the player clamps — pieces and
  player genuinely get the extra half-row of fall). The stage's top row on even levels is a
  half-checker tile (char 138, top 4 px empty, phase-opposed so the pattern continues into the
  full tiles below), and the two wall-base columns use the **wall-seam tile (char 202: white top
  half over the checker's bottom half)** so the white walls meet the checker with no black gap;
  `SHAFT_H = 16` is just the level-1 maximum, `mh = sh - 3` the per-level top-out threshold.
  `draw_stage` renders the whole flare; the per-column `scol` (used by the wall animation) draws
  the identical shape one column at a time.
- **Half-shifted stack rendering (even levels): landed cells are architecturally split across
  two character rows.** Char row `j` shows cell `j`'s color in its top half over cell `j+1`'s in
  its bottom half. All 56 combinations live in chars **139–194** (one shared solid pattern;
  per-ROW color bytes provide the split — top value A ∈ {empty, 7 colors} × bottom B ∈ {7
  colors}), with the char code itself encoding both colors (`139 + A*7 + B-1`), so landing
  paint and row-clear shifting decode neighbors straight from VPEEK — **no RAM mirror**. Chars
  **195–201** are the stage-seam tiles (piece color over the checker's top half). Row-clear on
  even levels is still a plain char copy (shifting `(cell j, cell j+1)` pairs down `m` rows is
  shifting chars) except the seam row, which is rebuilt by decoding the char that lands there
  (read *before* the copy clobbers it). Odd levels keep the simple one-cell-one-char path.
- During the level-transition wall animation the old shaft **closes** (old geometry), the play
  band is wiped, `calc_geom` switches to the new level, and the walls **open** to the new
  positions while the new (raised, flared) stage is **revealed column by column behind the growing
  gap** — so the new layer eases in instead of snapping when `init_level` repaints it. The old
  stage's **flared wings** (the angled cells outside the walls) are erased UP FRONT, before the
  collapse — the close phase only tracks the lip as the walls march in, so without this the wings
  lingered as leftover angled artifacts during the collapse. Vacated columns are erased with **true
  spaces** (not the black interior tile) so the win/game-over full-screen recolors show no leftover
  black artifacts; the wipe clears the tower band (rows 0–17) plus the wings (stage rows only, so
  the sidebar HUD is never touched).
- **Two height arrays.** `H(1..W)` is the *settled* stack; `HF(1..W)` is the *forecast* — settled
  plus every in-flight piece's booking. Targeting and shape selection read `HF`, so a piece
  spawned while others are mid-flight aims at and fits the surface as it *will* be; landing moves
  the booking from `HF` into `H`. (The original updates its `H()` at emission time for exactly
  this reason.) A cell at row `r` in column `c` is settled-filled when `r > SHAFT_H - H(c)`.
  These column-indexed arrays (`H`, `HF`, and the surface-pixel `sh1`) must be dimensioned for the
  **maximum** width, `W = 15` at level 1 — i.e. `DIM …(16)` (indices 0..15, 0 unused). Sizing them
  to a smaller max (they were `DIM …(15)` when `W` topped out at 14) makes the level-1 init loop and
  the `HF(x+1)` neighbour read write **one element past** the array. On the TI's roomy RAM that
  overflow is absorbed silently; on the ColecoVision's **781-byte** RAM it clobbers adjacent state
  and the ROM boots to a **black screen** — the regression from widening the shaft to `16 - LV`.
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
- **Fall speed ramps across levels, computed in `calc_geom`** (pure function of `LV`, alongside
  `W`/`sh`/`RG`): `fpr = 8 + (10 - LV) * 8 / 9`, giving `fpr` = 16,15,14,13,12,11,10,9,8,8 for
  levels 1-10 (bigger `fpr` = slower; `fpr=8` = 1 px/frame). **Level 10's speed is unchanged from
  before** — only levels 1-9 are slower than they used to be — so this is safe against the
  original reason a full-range ramp was rejected: ramping the *top* level's fall made it literally
  impossible (pieces dropping faster than the player can escape). Difficulty still also comes from
  the rising row goal (`RG`) and the narrowing shaft. Pieces advance by the same per-frame pixel
  delta, dealt by an
  accumulator (`acc += 8 * #fd` per pass, `#fd` = elapsed-frame count; while `acc >= fpr` move
  1 px) — scaling by `#fd` keeps the same real-world speed when the TMS9900 drops a frame. **`#fd`
  is computed once per pass in `main_loop`** (`FRAME - #lf`, clamped ≤ 4) and shared by both the
  falling pieces and the player cursor (§2), so the two scale identically under load — without this
  the pieces stayed frame-paced but the fixed-step cursor slowed down, making TI scenarios
  unescapable that ColecoVision (no frame drops) could clear. Because
  every piece moves the same `dy`, separations never
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
  `blink_player`) until fire returns to the title. On the win screen the player sprite is hidden
  during the game-area collapse and fireworks (see below), then **reappears blinking, horizontally
  centered and 6 rows above vertical center** (`blink_player` reused, `PX`/`PY` reassigned to
  `126`/`47`) once the
  "CONGRATULATIONS" banner is up, until fire returns to the title.
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

- Tile inventory: chars **128–134** are the seven piece colors `c1..c7` (red, light green,
  yellow, cyan, blue, dark red, **magenta** on black — c7/magenta is the "straight bar" piece,
  `$D1` tile / VDP colour 13; a cell's char code is `128 + colorindex - 1` on
  odd levels), char **135** the white border tile, char **136 a black-on-black tile for every
  empty shaft-interior cell** (instead of space, so the playfield stays black under the
  win/game-over recolors), chars **137/138** the stage checker (full/half), chars **139–194**
  the even-level split-pair tiles, **195–201** the stage-seam tiles, and char **202** the
  wall-seam tile (white top over checker, for the even-level wall base) (§4). Colors are per-row
  `DEFINE COLOR` bytes (`fg*16+bg`), same as every other CVBasic game in this repo.
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
- When `RD >= RG`: level-up banner — **"LEVEL UP!"**, except beating level 10 (`LV = 10` checked
  *before* the `LV = LV + 1` that decides the win path) shows **"YOU WIN"** instead, since that
  transition skips straight to the win screen rather than a normal level-up — then (unless
  `LV > 10` → win screen) the **level-up flush**
  (`flush_level`) followed by the **wall animation**. The flush hides the player + pieces (shared),
  then clears the shaft interior under a **descending tone** (channel 2, `#fq = 200 + (sh−f)·50`)
  that silences when done — content clearing just above the mountain top (rows `0..sh−1`; the
  foundation `sh..17` is never touched). The clear itself is per-target (`#if TI994A` / `#else`):
  **ColecoVision** first **bakes** each still-falling piece into piece-colour tiles (`128 + colour −
  1`) where it hangs so it drains with the stack, then **drains** the whole interior down one row per
  frame; the **TI-99** does a lighter **wipe** — blank the interior one row at a time from the top
  downward (no VPEEK row-shift), each row held ~4–5 frames (alternating, avg 4.5) for a comfortable
  pace, because the full
  drain's per-frame VDP round-trips crawl on the TMS9900 (and the bake would overflow the TI cart).
  Same tone on both.
- Then the **wall animation**:
  sprites hide, the cleared shaft blanks, both walls march inward column-by-column until they
  meet in the middle over a rising run of notes, pause, then march back **out to the next
  level's narrower, re-centered positions** with a second rising run and a two-note ta-da. As the
  walls open, the new (raised, flared) **stage is revealed column by column behind the growing
  gap** (`scol` per column), so the new layer eases in rather than snapping. `init_level` then
  redraws the fresh level over the animation's end state (identical geometry, so the hand-off is
  seamless), with `LV = LV + 1`, `RD = 0`, all `H(c) = 0`, and the player's 4-px bar **recentered
  between the walls** at the new floor.
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
  turn red while the board keeps its piece colors and the buried player keeps blinking. Win: the
  **game area collapses first** — `GOSUB wall_close` (the level-up wall animation's close phase,
  extracted into its own subroutine and reused here with no reopen): walls march to center over
  the mountain, the flared wings/lip erase, and the whole shaft wipes to blank — while the **HUD
  sidebar (SCORE/HIGH/LEVEL/CLEAR + values) is left completely untouched**, and there is **no
  full-screen `CLS`** at this point (`wall_close` only ever touches the shaft/wing columns, by
  construction of the same `li`/`ri` margins it's always used with at level-up). The player sprite
  is hidden along with the piece sprites (`wall_close`'s `hide_sprites` call) — it does not stay
  visible through this phase. Then **fireworks span the full screen width** — five rockets, each a
  rising white spark (with a rising whistle) that pops into the same 4-frame expansion animation
  (reusing defs 7–10, four tightly-overlapped sprites per shell) in its own color
  (yellow/green/red/blue/white) with a noise pop; with the shaft gone there is no exclusion zone to
  dodge, so burst positions are drawn from the whole visible width. Only then the full **dark-green
  victory banner** (`txt_green`, `$FC`): `CLS` (the *only* full clear in the sequence, and the first
  point anything other than the collapse has touched the sidebar) and the message (with the final
  score) prints on the solid green field, followed by the player sprite reappearing, **blinking,
  horizontally centered and 6 character rows above vertical center** (`PX = 126`, `PY = 47`, tuned
  to clear the banner text) (the old version printed over leftover playfield tiles and read
  as garbage). The **title screen restores** the normal white-on-black text colors (`txt_white`,
  `$F1`) before printing anything, hides all 7 sprites, and shows the **last score in the
  top-left corner, digits only** (`00000` on the initial title; `#score` isn't reset until a
  game starts) plus the **session high score top-right, right-justified** (`HI XXXXX`, `#hi` —
  updated at every game over/win, persists until power-off like Astiroids' high score).

## 9. Sound & Music (SN76489)

- **Per-level background music**: CVBasic's interrupt-driven player in `PLAY SIMPLE NO DRUMS`
  mode. **Each level has its own original tune** (`tune1`..`tune10`); `start_music` selects one
  by `LV` with a single-comparison `IF` chain (`PLAY` needs a constant label). `tune1` (level 1)
  is a 16-bar A-minor folk-dance loop — piano melody over a pumping root–fifth bass, eighth-note
  rows at 10 ticks (~150 BPM), `MUSIC REPEAT`. `tune2`..`tune10` are 8-bar loops built from chord
  progressions (arpeggiated melody + om-pah bass) in escalating keys/modes (D minor, E phrygian,
  G major, C dorian, A harmonic minor, F# minor, B phrygian, E harmonic minor, A minor) at rising
  tempos (10 → 6 ticks), so the score gets faster and darker as levels climb. A `MUSIC` row is a
  fixed 4 bytes, so the ten tunes cost ~2.8 KB of ROM. **This is a big chunk of the single-bank
  budget** (see §10 — the TI-99 single-bank ceiling is 24,336 B, not the 32 KB cart size): the
  program sits **124 B** under the line (after the slow-cursor hold + title hint and the per-level
  speed ramp spent most of the original ~200 B margin, the win-screen collapse-then-fireworks
  change net *reclaimed* space — removing the shaft-avoidance clamp and a now-redundant sprite-hide
  loop saved more than the new `wall_close` split/call and center-blink code cost — and the
  level-10 "YOU WIN" banner text spent some of it back), so **the tunes are not to be shortened
  without explicit approval, and every build must report free bytes** (§10).
  **CVBasic note syntax puts the sharp
  AFTER the octave** (`A4#`, not `A#4` — cvbasic.c note parser), octaves 2–6 (plus C7).
  `start_music` is called after the countdown at game start and again at each level-up; music
  stops (`PLAY OFF`) at level-up, game over, and win.
- **Get-ready countdown** (game start only, `countdown`): a "3", "2", "1" centered on the **tower's
  pixel centre** (cell `ML + (W+2)/2`, row `sh/2`) — the game window, not the screen column, so it
  no longer drifts a column left on some widths — one second each with a rising beep on channel 2.
  When the "1" clears, `start_music` plays the level's tune and the piece stream begins on the next
  main-loop pass (the fall pacer's `#lf` frame stamp is reset first, so the wait doesn't cause a
  catch-up jump). Between levels there is no countdown — the wall animation is the "get ready" beat.
- **Hard-won lesson: once `PLAY SIMPLE`/`FULL` is selected, the interrupt player rewrites its
  channels (0+1 for SIMPLE) EVERY frame forever — even after `PLAY OFF`** (confirmed in
  `cvbasic_9900_prologue.asm`: `music_hardware` is gated only on `music_mode`, which no
  statement clears). Any direct `SOUND 0`/`SOUND 1` write gets stomped within a frame and can
  latch into a stuck high-pitched tone (heard during the wall animation). Therefore **every
  direct sound effect in this game lives on channel 2** (free in SIMPLE mode) with noise on
  channel 3 (free with NO DRUMS).
- Move: short blip (channel 2, throttled). Piece landing: low thud (channel 2). Row(s)
  cleared: a **crunch** — low 140 Hz thump (channel 2) under a white-noise burst (channel 3)
  whose tail switches noise type mid-decay for a rougher texture.
- Level up: the wall-animation rising runs (articulated per step — the note is cut mid-step,
  otherwise the run smears into one continuous beep) + a two-note ta-da (channel 2).
- Game over: explosion noise (channel 3) + descending tone (channel 2). Fireworks: rising
  whistle (channel 2) + noise pops (channel 3).

## 10. Build & Run

Same `src/STRUCTRS.bas` builds both targets; only the toolchain differs. **Both use the forked
`cvbasic` at `unhuman/CVBasic`** — it adds the `#if/#elif/#else/#endif` preprocessor and
auto-defines a machine-name constant, which the source relies on to pick the level-up clear per
target — TI wipe / ColecoVision bake+drain (`#if TI994A`, see the header note). `--ti994a` sets `TI994A=1`; the Coleco build
leaves it undefined; **no `-D` is passed** (the auto-define would just "constant redefined"). Stock
nanochess CVBasic has no preprocessor and cannot build this source.

- **TI-99/4A:** `bash build-ti.sh` — `cvbasic --ti994a` → `xas99` → `linkticart` →
  `src/STRUCTRS_8.bin`. Load in Classic99 or js99er. (Equivalently:
  `bash .claude/skills/build-cvbasic-game/build.sh games/Structris/src/STRUCTRS.bas "STRUCTRIS"`.)
- **ColecoVision:** `bash build-coleco.sh` — `cvbasic` (Coleco is CVBasic's default target, no
  `--ti994a`) → `gasm80` → `src/structrs.rom`. Load in CoolCV or blueMSX. Compiles with 216 of 814
  RAM bytes used — comfortable headroom on Coleco's 1KB.

- **TI-99 single-bank ROM ceiling — 24,336 bytes (HARD, silently enforced).** CVBasic's TI-99
  runtime copies the whole program into the 24 KB RAM bank at `>A000` at startup, so a non-banked
  cart holds exactly **3 loader pages × 8112 = 24,336 B**. `linkticart.py` writes those three pages
  and **silently discards any excess with no error** — the truncated tail is real char/sprite/DATA
  bytes, which shows up as sprites that don't display and severe visual corruption (and it shifts
  with *any* code change, so it masquerades as a random/heisenbug). **Always report free bytes after
  a build:** `24336 - (len(open('STRUCTRS.bin','rb').read()) - 16384)` must be ≥ 0 (target ≥ ~200 B
  margin). The program currently sits **124 B** under (the slow-cursor hold + title hint and the
  per-level speed ramp had driven this down to 54 B; the win-screen collapse-then-fireworks change
  net reclaimed space — a removed shaft-avoidance clamp and a redundant sprite-hide loop outweighed
  the new `wall_close` split/call and center-blink code — before the "YOU WIN" banner-text branch
  spent some of that back), still **below** the ~200 B target — reclaim before adding new code. To
  reclaim space, cut **code / non-music DATA**
  first (the 128–136 tiles share one `DEFINE CHAR`; `fill_interior`/`hide_sprites` GOSUBs; char 202
  reuses `bnd_pat`; paint code hoists `mc`/`pcp`); the ~2.8 KB of tunes are **off-limits without
  explicit approval**. (32 KB is the *cart* size — headers + padding — NOT the usable program size.)

Compiling only proves the source is well-formed; gameplay must be verified by actually running the
ROM (see `.claude/skills/verify` guidance).

## 11. Acceptance Criteria

- [x] Compiles clean on **both** targets: TI-99 (`build-ti.sh` → `STRUCTRS_8.bin`) and
      ColecoVision (`build-coleco.sh` → `structrs.rom`).
- [x] Title screen shows controls/help (incl. "HOLD FIRE: SLOW CURSOR"); FIRE starts level 1.
      (TI verified in Classic99 — driven + screenshotted via the scripted harness; CV pending user
      verification.)
- [ ] **Holding FIRE during play halves the cursor speed only** (the falling pieces keep full
      speed); releasing restores full speed; a button held when buried does **not** skip the
      game-over screen into a new game. (Code-verified + builds clean; not yet observed in emulator.)
- [ ] **Piece fall speed ramps 1→10**: level 1 falls at half the level-10 speed, easing up level by
      level to the (unchanged) level-10 speed by level 9, holding there at level 10. (Code-verified
      + builds clean; not yet observed in emulator.)
- [x] **Beating level 10 collapses the game area (`wall_close`, no reopen) before the fireworks**:
      walls march to center, mountain/wings erase, shaft wipes blank — HUD sidebar and score
      untouched, no `CLS` at this point; the level-up banner shows **"YOU WIN"** in place of
      "LEVEL UP!" for this transition. Fireworks then burst across the **full screen width** (no
      shaft to dodge). Player sprite reappears **blinking, horizontally centered and 6 rows above
      vertical center** once the "CONGRATULATIONS" banner is up. (TI verified in Classic99 via a
      scratch probe build that jumps straight to `level_up`/`win_screen` at level 10: confirmed the
      "YOU WIN" text, the shaft/walls/mountain fully collapsing with the HUD sidebar untouched, and
      fireworks launching across the full width with no exclusion zone; the emulator process
      exited partway through a later run before the final banner+blink frame was captured, so that
      exact frame is unconfirmed — not yet established whether this was a real bug or an unrelated
      emulator/automation flake. Level-up's `wall_anim` behavior after the `wall_close` split has
      not yet been directly re-verified in the emulator.)
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
- [x] Getting buried shows "OOPS!  BURIED!" (single line, no level number) with a blinking player;
      fire returns to the **title**. The
      win screen collapses the game area, runs fireworks, then shows a dark-green banner with
      white text and a blinking centered player, and the title restores normal colors after it.
      (TI verified in Classic99 — the win screen via a scratch probe build that jumps straight to
      it, prior to the game-area-collapse change; a full played-through win with the collapse has
      not been performed.)
- [x] 838 on the title opens the setup screen; a digit picks the starting level (0 = 10) and the
      game begins at once — the choice lasts **one game only** (every return to the title resets to
      level 1). Verified in Classic99: 838→4 starts at level 4, and after being buried, fire →
      title → fire starts a fresh game at **level 1**.
- [x] The **stage is a flared mountain** — narrow top under the walls, flaring one column per side
      every row down to a wide base at the floor, so it grows taller/wider each level (verified at
      levels 7 and 10 and across forced level-up transitions with no wing artifacts); the white
      walls meet the checker with no black gap on even levels (wall-seam char 202). During a
      level-up the new mountain is revealed as the walls open, with no snap. The player's bar starts
      **centered between the walls, one cell (8 px) up off the floor**, and the OOPS!/LEVEL UP!
      messages are centered
      under the tower. (TI verified in
      Classic99 at levels 1/4/6 and across chained level-ups.)
- [x] **Level-up flush (per-target clear, `#if TI994A` wipe / `#else` bake+drain):** both clear the
      shaft interior just above the mountain under a descending tone; **ColecoVision** bakes the
      still-falling pieces into their colors then **drains** the whole stack down and out, while the
      **TI-99** does a lighter **wipe** (blank one row at a time, no VPEEK row-shift) because the full
      drain crawls on the TMS9900. Foundation never disturbed, walls collapse after. (Coleco verified
      in CoolCV across many fast level-ups with no freeze — an 8-bit underflow that hung it at "LEVEL
      UP" is fixed. TI verified in Classic99: mountain, solid +
      pair-tile colors at levels 1/2, 114 B free.)
- [x] A game starts with a **3-2-1 countdown** (rising beeps, centered over the shaft); when the
      "1" clears, the level's tune and the piece stream begin. **Each level plays its own tune**
      (`tune1`..`tune10`). (TI verified in Classic99: countdown 3→2→1→gameplay; both builds compile
      with all ten tunes — TI 32 KB cart, Coleco 24 KB ROM.)
- [x] TI-99 and ColecoVision run the same real-world speed: the fall is FRAME-delta paced, and
      Classic99 measurements confirm 60Hz (blink probe 532.8ms/533.3 expected; fall rate ~60px/s
      within measurement error). CV still needs its user-side CoolCV pass.
