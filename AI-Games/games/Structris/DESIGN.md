# Structris — Design

> CVBasic game, **dual-target**: TI-99/4A (native TMS9900 bank-switched cartridge ROM, `--ti994a`)
> **and** ColecoVision (native Z80 ROM, CVBasic's default target) from the *same* `STRUCTRS.bas` —
> not an XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic notes
> in `games/Astiroids/DESIGN.md` §12 (unsigned compares/divides, `ABS`, sprite wrap, char colors)
> apply here too. Sibling CVBasic projects: `games/Astiroids`, `games/Adventire`,
> `games/mspacman-cv-xb-port`.
>
> **No cross-platform pacing tricks needed** (unlike Astiroids' `pacen`): the main loop does
> trivial per-frame work (one sprite, a handful of scalar updates), so both machines finish it well
> within a single 60Hz NTSC vblank and a plain `WAIT` gives the same real-world tick rate on both —
> same pattern as `games/Adventire`. The $1800 name table (written directly by
> `redraw_col`/`draw_borders`) is the standard CVBasic screen layout on both targets, so no
> platform `#IF` branching was needed anywhere in the source.
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
  animates each piece as 1–3 bars **falling from the top of the shaft to their landing row**, and
  turns "row cleared" into an explicit compaction step. The original's help text ("FINISHED ROWS
  FALL AWAY") describes exactly this outcome, so the reinterpretation matches the stated design
  even though the mechanism differs.

## 1. Concept & Objective

- Columns of blocks grow from the floor, one piece at a time, aimed at wherever you're standing.
- You stand on top of the stack and move along its ragged skyline: left/right to change columns,
  up to climb higher into the open shaft, down to duck into a valley between taller neighbors.
- A piece that lands on your cell buries you — unless there's room to climb up and out of its way,
  which happens automatically. If there's nowhere to climb to, you're crushed: game over.
- Clear enough rows (every column built up past a shared threshold, which then "falls away" and
  compacts the stack back down) to advance a level. Ten levels, each with a narrower shaft and
  faster, more frequent pieces. Clear level 10 and you win.

## 2. Controls (joystick 1)

| Action | Input | Behavior |
|---|---|---|
| Move left / right | `cont1.left` / `cont1.right` | Step one column, only if that column isn't taller than your current row (can't walk through rock). |
| Climb up | `cont1.up` | Step one row up the shaft (always legal while not at the ceiling). |
| Duck down | `cont1.down` | Step one row down, only while still above your column's stack top. |
| Start / restart | `cont1.button` | Starts the game from the title screen; restarts (level 1) from the game-over or win screen. |

Movement is debounced to one step per ~6 frames so repeated taps feel controllable rather than
input-mashy; CVBasic has no built-in key-repeat delay, so this game rolls its own via a per-frame
countdown (`move_cd`).

## 3. Screen & HUD

- **Mode:** CVBasic **default startup mode** (no `MODE` statement — see the header warning about
  `MODE 2`) — 32×24 text grid at VRAM `$1800`, 8×8 background tiles with per-row `DEFINE COLOR`
  colors, ASCII font preloaded, sprite plane independent of the tile colors.
- **Row 0 (HUD):** `LV 03  CLR 05/09` — current level, rows cleared / rows needed this level.
- **Rows 1–16:** the shaft. Row 1 is the ceiling; row 16 is the lowest playable row (directly above
  the floor).
- **Row 17:** floor border (`HLIN`-equivalent solid row) plus one column of vertical border tile on
  each side of the shaft, redrawn whenever the shaft width changes at a level-up.
- **Rows 19–22:** message area — level-up banner, "OOPS!" / game-over stats, win screen, title
  screen help text. Reuses the same rows so nothing needs to be laid out twice.

## 4. Playfield & Column Model

- `W` = shaft width in columns, `W = MAX(5, 11 - LV)` (10 at level 1, floors at 5 from level 6 on).
  Shaft is centered: left margin `ML = (32 - W) / 2`; column `c` (1..W) occupies text column
  `ML + c`.
- `SHAFT_H = 16` (fixed — only width shrinks with level, not height; two knobs shrinking at once
  made early playtesting math confusing, and width alone already scales difficulty well).
- `H(1..W)`: current stack height of each column, in rows, counted from the floor. A cell at row
  `r` in column `c` is filled when `r > SHAFT_H - H(c)`. The lowest empty row (where a piece —or
  the player— can rest) is `SHAFT_H - H(c)`.
- `MH = SHAFT_H - 3` — a column at or above this height is "topped out" and skipped by the
  targeting logic (§5) so pieces don't pile past the ceiling.
- Player position `(PCOL, PROW)`: `PCOL` in `1..W`, `PROW` in `1..SHAFT_H`. Never below its
  column's surface (`PROW <= SHAFT_H - H(PCOL)`), enforced by the movement rules in §2 and the
  push rule in §6.

## 5. Piece Catalog & Targeting AI (ported from the original)

Every piece is 1–3 adjacent columns (`X-1, X, X0` — wait: `X-1, X, X+1`) receiving height deltas
`BL, B0, BR` (0–3 rows each) simultaneously. Target column `X` is chosen, then its shape is picked
purely from how its two neighbors compare to it — this is what makes the game feel like it's
"aiming" at your gaps.

**Targeting:** `X` starts at the player's own column, clamped to `1..W`. If `H(X) >= MH`, scan
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

## 6. Falling, Collision, and the Push Rule

- **The piece falls as a rigid unit.** Its up-to-3 bars share one fall counter (`plead`,
  advancing one row per `FRAMES_PER_ROW = MAX(2, 8 - LV/2)` frames — faster at higher levels) and
  all land **simultaneously** the moment the piece bottom (the center bar) reaches the center
  column's surface (`ptarget = SHAFT_H - H(X)`). Each side bar rides `baroff` rows higher — exactly
  its column's height advantage (`hl`/`hr`), which is the same number the shape was *selected*
  against (§5) — so at landing every bar is flush with its own column's surface at the same
  instant: the piece slots into the terrain like a pre-fit tetromino, never "compacting" against
  it bar-by-bar. This works because the shape table guarantees a side gets a bar **only** when its
  true height difference is 0–3 (a clamped-to-3 side always has a 0 delta), so a rigid perfect fit
  always exists. The staggered *entry* from the ceiling (side bars appearing `baroff` rows behind
  the center) is the direct analogue of the original's `SL`/`SR` scan-line delay counters.
- An earlier draft dropped each bar independently onto its own column (each with its own landing
  row) — pieces visibly broke apart mid-fall and "squished" onto the stack one column at a time.
  If piece behavior ever regresses to that, this shared-counter design is what got lost.
- **Every frame**, after advancing animation, check whether the player's cell `(PCOL, PROW)` is
  currently filled — by settled stack (`PROW > SHAFT_H - H(PCOL)`) or by a falling bar passing
  through this frame. If so:
  - If `PROW > 1` and row `PROW-1` is clear, push the player up one row (`PROW = PROW - 1`) and
    re-check (a fast piece can require more than one push in a frame).
  - If no row remains above (`PROW` would go below 1), it's **game over** ("OOPS!").
- **`H(c)` is hard-capped at `SHAFT_H`** the moment a landing would push it over (`IF H(cc) >
  SHAFT_H THEN H(cc) = SHAFT_H`). This isn't cosmetic: `H` is a plain (8-bit **unsigned**, CVBasic's
  default variable size) column, and `bartarget = SHAFT_H - H(neighbor)` is computed for a bar's
  *neighbor* column, which — unlike the target column itself — is never gated by `MH` and can in
  principle keep absorbing `BL`/`BR` hits past `SHAFT_H`. Without the cap, that subtraction goes
  negative and wraps to a huge unsigned value (~250), which `barlead` (which only ever counts up to
  ~`SHAFT_H`) can never reach — that one bar animates forever, `busy` never clears, and no further
  piece ever spawns. Found by simulating the (fixed) logic in Python outside the CVBasic toolchain
  after an initial playtest reported the TI build going fully unresponsive after a few pieces.
- This single rule covers both "a piece falls through the row you're standing in" (mid-fall
  collision, the primary way the original kills you) and "a piece lands and its final height
  reaches your feet" (post-landing collision) — no special-casing needed for the two cases.

## 7. Colors & Tiles

- Eight consecutive solid tiles, chars **128–135**: chars 128–134 are the seven piece colors
  `c1..c7` (red, light green, yellow, cyan, blue, dark red, gray on black), char 135 is the
  white-on-black border/floor tile. All eight share one `filled_bitmap` pattern; colors come from
  one `DEFINE COLOR 128,8,tile_colors` block (8 per-row color bytes per char, `fg*16+bg`), same as
  every other CVBasic game in this repo. A cell's char code is simply `128 + colorindex - 1`.
- **Per-cell colors — the screen is the color model.** There is no per-column color variable:
  when a bar lands, only its *newly added* cells are painted in the piece's color, so every settled
  cell permanently keeps the color of the piece that created it (pieces visibly hold their shape
  instead of the whole column repainting — the original's look). The falling-bar animation repaints
  only the *empty* region above the settled stack, and row-clear compaction shifts cells down with
  `VPEEK`/`VPOKE` so colors move with their cells.
- **Landing erases before it paints.** The bar's last animation frame sits one row above its
  landing cells; landing first blanks the whole empty region above the new stack top, *then*
  paints the new cells — otherwise every landed bar leaves a floating ghost cell that compaction
  later shifts into the stack (seen in play-testing). Related quirk: **CVBasic `FOR` checks its
  limit at the bottom**, so an empty range (`FOR r = 1 TO 0`) still runs once — both landing loops
  and the compaction shift are guarded with IFs for the column-full / full-clear edge cases.
- The standard preloaded ASCII font (chars 32–127) covers all HUD/message text — no `DEFINE CHAR`
  needed for text.
- Player sprite art is a full **16×16 `BITMAP` block** (climber in the top-left 8×8, rest
  transparent): CVBasic sprite definitions are always 32 bytes, so an 8-row bitmap would make
  `DEFINE SPRITE` read on into the following data (visible as garbage pixels beside the player —
  seen in emulator testing).
- Player: single 8×8 sprite (no magnification — a shaft column is exactly one 8px tile wide, and
  magnifying the player would make it wider than the column it stands in), solid white, transparent
  background. Independent of the tile color budget (sprite plane rule, CLAUDE.md §4).

## 8. Row Clearing & Leveling

- `RG = 4 + LV` rows required to advance (5 at level 1, up to 14 at level 10).
- After a piece lands, `newmin = MIN(H(1..W))`. If `newmin > 0`: `RD = RD + newmin`, then
  subtract `newmin` from every `H(c)` (the completed rows "fall away" — direct nod to the
  original's help-screen wording). On screen, each column's cells are shifted down `newmin` rows
  with `VPEEK`/`VPOKE` (preserving per-piece cell colors, §7) and the vacated top rows blanked.
  A piece still in flight gets `ptarget += newmin` so it lands on the compacted surface instead
  of floating. The player's `PROW` doesn't change (they don't fall with the compaction — they were
  standing above the cleared rows, not on them), which reads on screen as the player gaining
  clearance, a small reward beat for clearing rows.
- When `RD >= RG`: level-up banner, `LV = LV + 1`, `RD = 0`, all `H(c) = 0`, shaft re-centered for
  the new (possibly narrower) `W`, player recentered at the new floor. If `LV > 10`: win screen.

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
- [x] Pieces visibly fall, target the player's column, keep per-piece colors/shapes on the
      stack, and use the shape/color catalog from §5. (TI verified in Classic99.)
- [x] Player sprite moves with the joystick; push-up rule works (player rides a bar falling
      through their column and ends standing on it). (TI verified in Classic99.)
- [ ] Rows compact and count toward level-up; level-up narrows the shaft and speeds up play.
      (Code-verified + simulated; not yet observed in emulator.)
- [ ] Reaching level 11 shows the win screen; getting buried shows "OOPS!" with a restart prompt.
      (OOPS observed; win screen not yet.)
- [ ] TI-99 and ColecoVision builds feel the same speed (no pacing drift between platforms).
