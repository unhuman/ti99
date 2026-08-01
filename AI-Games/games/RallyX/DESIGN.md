# RALLY-X — Design

> CVBasic game, **dual-target**: TI-99/4A (native TMS9900 bank-switched cartridge ROM, `--ti994a`)
> **and** ColecoVision (native Z80 ROM, CVBasic default target) from the same `src/RALLYX.bas` —
> not an XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic
> hazard list at the end of this file (§14) is binding here. Sibling CVBasic projects:
> `games/Structris`, `games/HardHatMack`, `games/Astiroids`, `games/mspacman-cv-xb-port`.

This document describes the game to be built. Source of truth once code exists is
`src/RALLYX.bas`; keep this file in sync with any behavior change.

## 0. Provenance

RALLY-X is a clone of Namco's **New Rally-X** (1981) — the balanced revision of Rally-X (1980):
drive a car through a large scrolling maze of roads, collect the 10 flags before fuel runs out,
dodge the pursuing red cars, drop smoke screens to shake them. A radar panel on the right shows
the whole map. New Rally-X mazes are documented as "mostly identical to Rally-X with some blocks
changed into roads and different flag/rock locations" — the maze here is **transcribed at the
cell grid** (32×56 corridor units, measured 24 px pitch) from the vgmaps.com `Rally-X-Level1.png`
rip (in `assets/`, with the transcription script `assets/transcribe2.py` and its output
`assets/maze1.txt` / visual check `assets/maze1-render.png`). Gameplay rules follow New Rally-X:
special (S) flag doubles later flags, lucky (L) flag pays a fuel bonus, challenge stages, fewer
red cars, upbeat music.

## 1. Performance Budget (decide-before-code, per repo mandate)

- **Sprites: 5** — player car + up to 4 enemy cars, all moving. Flags and smoke are *characters*
  (§17b), painted by `draw_view` in the same frame as the pan blit. Enemy sprite slots rotate
  order every frame (our own rotation, never `SPRITE FLICKER`) so a 5-on-a-scanline pileup
  degrades to flicker, not vanishing.
- **Motion:** all actors repositioned per frame by CPU (`SPRITE` statements) — native code
  affords this (proven by Ms. Pac-Man CV / Structris). No `LOCATE`-analog concerns in CVBasic.
- **Per-frame VDP round-trips: ~0 reads.** All collision (walls, flags, smoke, cars) is computed
  from the **ROM map + small RAM lists**, never `VPEEK` of the playfield. Writes per frame:
  5 sprite attribute updates + (on camera-step frames only) one `SCREEN` blit of the 24×24
  viewport + ≤10 overlay `VPOKE`s.
- **Camera `SCREEN` blit** (576 B) happens at most once per ~3 frames (8-px char pan at
  3 px/frame car speed), never per frame. The flag/smoke overlay pokes follow it with **no**
  `WAIT` in between, so blit and overlay land in the same frame's buffered batch — the `WAIT`
  that used to sit there is exactly what made char flags strobe (§17b).
- **Radar refresh at ~10 Hz** (every 6 frames): re-plot ≤5 mover dots as pattern-table `VPOKE`s
  (a handful of bytes each). Flag dots are baked once per round.
- **Enemy AI: reactive, intersection-only.** Direction is chosen only when an enemy reaches a
  cell center (~every 4-8 frames per enemy), by comparing positions — no search, no pathfinding.
- Loop is real-time 60 Hz with **FRAME-delta pacing** (Structris pattern) so TI-99 and
  ColecoVision run the same real-world speed even if a frame slips.

### 1a. Measured cost, and the two rules that follow from it

Measured on Classic99 (real TI-99 timing) by counting game-loop passes against a host clock over
12 s, crash disabled so every run stays in the same game state. The honest metric is
**passes ÷ `FRAME` ticks**, which is independent of host-clock error: 1.00 means one pass per
vblank, i.e. a true 60 Hz.

| build | parked | driving (camera panning) | `#fd` |
|---|---|---|---|
| original | 8.2/sec | — | pinned at the clamp, 4 |
| after round 1 | 25.7/sec | — | ~2.3 |
| **now** | **59.7/sec** (1.00 pass/frame) | **52.6/sec** (0.88 pass/frame) | **1.00 – 1.14** |

`FRAME` advanced at a true 59–60 Hz in every run, so no vblanks were ever being lost — the loop
was simply doing too much work per pass.

What the profiling actually found, in order (each by building a variant with one subsystem
disabled and re-measuring):

| term | cost | what it was |
|---|---|---|
| enemy pixel-walk | 13.6 ms | one subroutine call **per pixel** per enemy |
| player `at_center` | 12.1 ms | 10-flag scan on **every aligned pixel step** |
| `ckhit` + smoke ageing + fuel bar | 5.4 ms | ran unconditionally |
| radar tick | 4.2 ms | `dot_addr` re-derived for all 10 flags per tick |
| `evis` + `update_cam` | — | camera-origin multiplies redone per enemy per pass |

Two things were **not** the problem, both of which looked like the obvious suspect first:
the 576-byte camera `SCREEN` blit (`draw_view` was not called *at all* during the slow runs), and
the enemy AI (`eai` measured 0.56 calls per pass at 1.55 probes each — it is genuinely
intersection-only, as designed).

> **Rule 1 — anything whose cost scales with `#fd` is on a feedback loop.** FRAME-delta pacing
> multiplies per-pass work by the delta, so an expensive pass raises `#fd`, which makes the next
> pass more expensive again; the old loop sat pinned at its clamp and never recovered. Per-pixel
> work is exactly this shape, so **everything that moves is O(cells crossed), never O(pixels
> travelled)** — `drive_step` and `emove_n` both walk boundary to boundary.
>
> **Rule 2 — the clamp discards real time, so it must never fire in normal play.** Clamping `#fd`
> to 4 while the loop wanted 7–8 meant the world advanced at roughly *half* real time whenever
> the loop was busy and at full speed whenever it was not. That is why **the enemy cars visibly
> sped up while the player was parked** and the screen was not scrolling: not an enemy bug, a
> pacing bug. With movement now O(cells) a large delta is both cheap and safe (nothing can tunnel
> — every step tests walls at each boundary), so the clamp is 16, far above anything ordinary
> play reaches. Any timer counted in *passes* has the same disease: `sct` (scatter) and `sfxt`
> (flag blip) were decremented by 1 per pass and so drifted with the frame rate; both are now
> `#fd`-scaled.

`WAIT` quantises a pass to a whole frame, so the loop rate can only be 60, 30, 20… — there is no
"45 fps". A body that overruns one frame by even a little costs a full second frame, which is why
the last few milliseconds were worth chasing rather than settling at 2 frames per pass.

## 2. Screen Layout (32×24, CVBasic default mode — never `MODE 2`)

The world renders at **2×2 characters per maze cell** (16-px roads): the 16×16 car exactly
fills a lane, and the viewport shows only a 12×12-cell window of the 32×56 maze — which makes
the radar genuinely necessary.

```
cols 0–23: scrolling maze viewport (24×24 chars = a 12×12-CELL window on the map)
cols 24–31: panel
  rows 0–1: "1UP" + score (6 digits)     rows 2–3: "HI" + high score
  row  4:   blank
  rows 5–18: RADAR (8×14 chars = 64×112 px; the whole 32×56-unit map at 2 px per unit)
  row 19:   blank
  row 20:   "FUEL" label   row 21: fuel bar (8 chars, 64 px)
  row 22:   lives (car icons)            row 23: round number
```

## 3. The Map

- **Logical maze: 32×56 cells** (1 cell = 2×2 chars = 16 px), transcribed from the arcade rip,
  stored with a 1-cell tree border in **two ROM encodings** (both generated by
  `assets/genmap.py` from `assets/maze1.txt`):
  - `map1` (`src/map0.bas`, **TI bank 0** so gameplay PEEKs never bank-switch): 34×58 logical
    bytes — wall 96 / tree 112 / road 113; collision, AI, and radar all read this.
  - `map2` (`src/map2.bas`, **TI bank 1**, selected during gameplay): 68×116 chars, 2×2 per
    cell, walls pre-edged with quadrant variants, stride 68 — the `SCREEN` blit source.
  Both are **immutable in ROM** — flags/smoke/rocks are overlays (small RAM lists), which is
  what lets ColecoVision's ~1 KB RAM fit.
- **Viewport blit:** `SCREEN map2, camr*68+camc, 0, 24, 24, 68` on camera-step frames (camera
  in **char units**, panning 1 char = 8 px per step for smoothness), then a `WAIT`, then the
  overlay draws (each live flag/smoke inside the window: 4 VPOKEs, its 2×2 quadrants).
- Map pixel space: cell (r,c) spans 16 px from (c*16, r*16) (bordered coordinates; playable
  cells are r=1..56, c=1..32).
- Later rounds: transcribe `Rally-X-Level2/3/4.png` the same way (M4). If ROM gets tight,
  fall back to fewer maps + per-round flag lists.
- **Round 1 item data (bordered coords = transcribed +1):** flags at (13,13), (18,23), (23,18),
  (26,25), (28,8), (36,14), (39,7), (39,29), (46,4), (46,14), (54,22) — 11 transcribed positions:
  8 become regular flags, one **S** (transcribed at (8,28)), one **L** (chosen from the list),
  and one dropped → 10 flags total, New Rally-X style. Player start (23,15) heading **right**
  (the start corridor is horizontal — walls sit directly above and below); enemy spawns
  (6,24), (22,31), (28,18), (36,2). No rocks in round 1 (the rip shows none).

## 4. Character Set (codes; CVBasic `DEFINE CHAR`/`DEFINE COLOR`, per-row colors)

| Codes | What | Colors (fg on bg) |
|-------|------|-------------------|
| 0–11 | flag F/S/L 2×2 quadrant chars — **unused since flags became sprites** (§5); kept so `SMOKECH` stays at 12 and the set is one `DEFINE CHAR 0,16` | — |
| 12–15 | smoke cloud, 2×2 quadrants (three lobes over a flat base, built by `genmap.py`) | white on tan — **one colour in all four quadrants**; the first version was white on the top two chars and grey on the bottom two, which read as a two-tone ball rather than a cloud |
| 32–95 | stock ASCII (HUD text, title) | white on black |
| 96–111 | wall **quadrant** chars, 4 variants per corner (each quadrant needs only its 2 road-facing edge bits: TL 96+N+2W, TR 100+N+2E, BL 104+S+2W, BR 108+S+2E; 2-px road-side inset), baked into `map2` offline by `genmap.py` | green on tan |
| 112 | tree (border; tiles as 4 blobs per border cell) | light green circles on dark green |
| 113 | road (solid) | tan on tan |
| 120–128 | fuel bar fill levels 0–8 px | yellow on black |
| 129 | mini car icon (lives) | blue on black |
| 144–255 | **radar canvas**, one code per radar cell (8×14 = 112, code = 144 + (row−5)*8 + col−24) | per-row colors set at plot time; base white dots on dark blue |

(Rock art is deferred with rocks themselves — round 1 has none.)

Radar plotting writes the pattern table **directly per screen third** (the code appears at
exactly one screen position, so only that third's bank is written): pattern byte address =
`third*$800 + code*8 + row`, color likewise at `$2000 + ...`. Flag dots (2×2 px, yellow rows)
are baked at round start; mover dots (player = always drawn, cycling white/black, enemies = red) are erased by
re-deriving the baked pattern from the flag list (no RAM radar copy), then OR-ing the new dot.

## 5. Sprites (16×16, MAG default double-size)

Sprite **pattern defs**: 0–7 = the car's eight headings (N, NE, E, SE, S, SW, W, NW — the
`ang` variable indexes this directly, sprite name = `ang*4`), 8–9 = explosion, 10 = flag.

| # | What | Notes |
|---|------|-------|
| 0 | player car | eight heading frames, light blue; becomes the explosion frames (defs 8–9) on crash |
| 1–4 | enemy red cars | same art recolored red, own visual heading `eang`; slots rotated every frame; hidden at **y=209** when off-viewport |
| 5–14 | the 10 flags (def 10) | F light yellow, S red, L white. **Sprites, not chars** — camera-pan blits can't flicker them, and pickup just stops drawing them. Higher slot numbers than the actors, so a 4-per-scanline overflow drops a flag rather than a car. Hidden at y=209 when taken or off-window (row 0 is skipped so `y−1` can't wrap to 255). |

Art: top-down Formula-1 — narrow nose, four protruding wheels, wide midsection, rear wing —
drawn **~12×12 inside the 16×16 sprite box**. The smaller footprint is deliberate: a 12-long,
9-wide car spans (12+9)/√2 ≈ 14.8 px on the diagonal, so the 45° frames fit without clipping
their wheels (at a full 16 px they clipped and read as a blob).

`assets/gencar.py` draws **one shape definition at all eight headings** rather than rotating a
bitmap or hand-drawing the diagonals — rotating pixel art 45° turns to mush at this size, and
hand-drawn diagonals look like a different vehicle. The shape is defined in car space (u along
the axis, v across it); wheels are placed as axis-aligned 3×3 blocks at the rotated wheel
positions, because rotated wheel *boxes* smear while square blocks read as wheels at every
angle. Wheels sit far enough outboard to leave a 1-px gap beside the body, or the car reads as
a solid bar. The generator prints an ASCII preview of all 8 frames plus the `DATA BYTE` lines.

8 heading frames shared by player and enemies (recolored per sprite) + 2 explosion frames +
1 flag pennant = 11 16×16 patterns (32 B each) in ROM. **Sprite byte order is left half rows
0–15 then right half rows 0–15** — don't reorder.

## 6. Movement & Camera

- Positions are **map-pixel** 16-bit vars (cell = 16 px); on-screen sprite pos = map px −
  camera char × 8 (the 16-px sprite exactly fills a lane — no centering offset). Speeds are
  1/8-px-per-frame fixed point: an accumulator adds `speed` each frame, the car moves whole
  pixels when it overflows (FRAME-delta scaled).
- **Player:** always moves in its heading; the stick sets a **queued direction**. Base speed
  3 px/frame; low fuel (<25%) drops to 2.25, empty fuel crawls at 1.5.
- **Turning is a rotation, never a flip** (the Rally-X handling model, and the reason for the
  eight heading frames). The car has a logical `dir` (0–3) and a visual `ang` (0–7, 45° steps).
  Requesting a new direction starts a turn: `ang` steps one notch every `TURNRT` (3) frames
  toward the target, taking the short way round, and **the car does not advance while it
  turns** — it rotates on the spot. Movement resumes, and `dir` is committed, only when `ang`
  reaches the target. So a 90° turn takes 6 frames and a **180° reverse takes 12, visibly
  sweeping through the sideways heading** instead of snapping from up to down. A 90° turn still
  waits for a cell centre with that way open (`at_center`); a reverse may start anywhere, since
  the cell behind is by definition open.
- **The player walks cell boundary to cell boundary** (`drive_step`'s `pm_top` loop), exactly
  like `emove_n`: it jumps straight to the next 16-px boundary or to the end of the frame's
  travel, whichever comes first. Every decision the car makes happens on a centre, so nothing is
  lost by skipping the gaps, and movement cost stops scaling with `#fd` (§1a rule 1). There is
  no longer a per-pixel `move1px`, and the `#dx`/`#dy` step vector and `set_dir` went with it —
  each of the four headings moves its own coordinate directly.
- **`at_center` splits per-cell from per-step work.** Flag pickup and laying a queued puff are
  per-CELL and live in `enter_cell`, reached only when `(cr,cc)` differs from `(lcr,lcc)`. The
  turn/wall probes are per-step, but are themselves skipped while `(cell, dir, qdir)` are all
  unchanged (`pqd`/`pdr`) — a car pinned against a wall stays cell-aligned indefinitely, so
  without those two guards the 10-flag scan and both probes re-ran on every pixel step of every
  frame (§1a).
- **Enemies turn too** but keep moving while they do (`eang` eases toward `edir*2` on the same
  3-frame clock). Their AI only ever picks 90° changes, so a visible sweep is enough — stopping
  them dead mid-turn would make them trivial to escape.
- **Enemies:** 2.5 px/frame at round 1 (`espd = 18 + rnd*2` eighth-px units), +0.25/round to a
  3.75 cap. At each cell center pick: prefer the axis with the larger gap to the player if
  open, else the other axis, else keep straight, else any open ≠ reverse (reverse only at dead
  ends). **Enemies never stack:** every candidate direction must pass `probe_free`, which
  requires the target cell to be road *and* unoccupied by another active enemy — so the car
  that would have driven into an occupied cell is the one that turns away, since the test runs
  as it chooses. In **scatter** (round start ~3 s, and after a crash) the preferences invert — they
  head away. Stunned (smoke) = 90-frame stop.
- **Enemies advance in cell-bounded chunks** (`emove_n`), not one subroutine call per pixel: a
  car moves straight to the next 16-px boundary or to the end of this frame's travel, whichever
  comes first, and only stops to run the AI on a boundary. Each enemy also completes a whole
  frame's travel before the next one starts, rather than being interleaved pixel-by-pixel; the
  no-stacking guarantee is unaffected because `probe_free` compares **cell** coordinates and a
  car occupies its cell for many pixels. This was the single largest cost in the loop (§1a).
- **Every car's cell is cached** in `ecra`/`ecca`, updated alongside `#ex`/`#ey` on every move.
  `probe_free` consults all four cars for each candidate direction, so deriving the cells there
  meant ~24 divisions per AI decision. The AI's last-resort scan also skips `p1`/`p2`, which it
  has already tried — of the four headings only one is ever actually new there, and re-probing
  the other three took the worst case from 4 probes to 7 exactly when cars are boxed in.
- **Camera** (in map2 **char** units, col 0..44, row 0..92): dead zone keeps the car's screen
  char within cols/rows 10–13; crossing it pans the camera 1 char (8 px) toward the car
  (clamped), triggering the viewport blit — the pan stays 8 px even though cells are 16 px,
  which keeps the scroll as smooth as before the 2× scale. `update_cam` returns immediately when
  the car has not moved (it is a pure function of the car's position), and the camera origin in
  pixels is computed once per pass into `#cx8`/`#cy8` rather than re-derived inside `evis` for
  every enemy.

## 7. Flags, Fuel, Scoring

- 10 flags/round: 8 regular + **S** + **L** (positions §3). Pickup = car's cell == flag cell.
- Values: 1st flag 100, then 200, 300 … (per pickup order, capped 1000). After collecting **S**,
  every later flag's value is **doubled**. **L** additionally pays `remaining fuel bar px × 10`.
- Collecting all 10 ends the round: short jingle, round card, next round (no fuel bonus beyond L).
- **Fuel:** 768 units ≈ 64 px bar; drains 1 unit/4 frames (~51 s), plus 8 per smoke puff.
  Empty ⇒ crawl speed, no smoke; you can still finish the round.
- Extra life at 20,000 (once). Score/HI 6 digits, persistent HI per session.

## 8. Smoke Screen — arcade rules

Researched rather than invented ([StrategyWiki Rally-X](https://strategywiki.org/wiki/Rally-X)
and [New Rally-X](https://strategywiki.org/wiki/New_Rally-X)): **one button press releases
exactly three puffs** behind the car — it is *not* a stream you hold down — and each use costs
a big slice of fuel; the guides warn that using it more than about once every 30 s means
running dry before all ten flags.

So: fire is **edge-triggered** (`smoke_fire` on the rising edge only), charges `SMKCOST` 96
fuel up front out of a 768 tank (8 uses if you never drove), and queues `SMKPUFF` 3 puffs.
Queued puffs are laid one per cell as the car leaves it, producing the arcade's short trail.
No fuel, no smoke. `MAXSMK` 6 puff slots hold two deployments in flight; the oldest slot is
recycled beyond that. Each puff lives `SMKTTL` 150 frames (2.5 s).

**Puffs age by the frame delta, not a flat 1 per pass** — the loop does not run at a steady
60 Hz, and a flat decrement measured ~30 ticks in 4 seconds, leaving puffs on screen roughly 8×
too long. The whole ageing pass is skipped while `nsmk` (live puff count) is 0, which is most
of the time.

**An expired puff restores just its own 2×2 block** via `cell_restore` — a 2×2 `SCREEN` blit
straight out of `map2`, four bytes instead of the 576-byte full-window `draw_view` repaint that
used to fire up to six times per deployment, each one a whole frame stalled with interrupts off.
Blitting from the map (rather than poking `ROADCH` into all four quadrants, which is what an
earlier targeted erase did) is what makes it correct: road cells that sit against a wall carry
pre-edged art, and a flat road poke flattened that edging. Cells that are off-window are simply
skipped — nothing of them is on screen, and the next pan calls `draw_view`, which only ever
paints puffs that are still live. `take_flag` uses the same routine for the picked-up flag's
cell, which fixes the same latent edging loss there.

An enemy whose cell holds smoke is stunned `SPINFR` 96 frames and **spins**: while stunned its
visual heading advances a notch every tick, so it whirls through ~4 revolutions before its
heading settles and it drives on.

## 9. Collisions & Lives

- Player vs enemy: same cell, or pixel boxes within 12 px on both axes ⇒ **crash**: explosion
  animation + descending boom, lose a life, enemies rehome to spawns, player restarts at the
  start cell (flags/fuel keep their state). 3 lives; game over card → title.
- Player vs rock (rounds ≥2): same as a crash.
- Enemies ignore rocks/flags/each other.

## 10. Rounds & Challenge Stages

Sequence: round 1, 2 → **challenge** → 3, 4 → challenge → … Regular rounds reuse the maps
cyclically (map1 now; L2–L4 transcriptions in M4) with per-round flag/spawn/rock lists and
rising speeds/enemy counts (round 1 = 3 chasers of the 4 spawns, later rounds 4 — difficulty
scales **speed, never count beyond 4**). **Challenge stage:** no enemies, fixed fuel, all 10
flags placed dense; collect everything before fuel empties for a 10,000 bonus (arcade-style
"CHALLENGING STAGE" card, its own tune).

## 11. Sound & Music

CVBasic `MUSIC` (2 melody channels) + channel 3/noise reserved for SFX:
- Main theme: New Rally-X-style upbeat loop (original transcription, short 8-bar loop).
- Challenge theme, round-start jingle, round-clear jingle, game-over sting.
- SFX: flag blip, smoke hiss (noise burst), crash boom (descending noise), low-fuel beep
  (replaces music when fuel <25%, arcade-style).

## 12. Controls

- TI-99/4A: joystick 1 (or E/S/D/X), fire (or `Q`) = smoke. `FCTN-=` resets (runtime standard).
- ColecoVision: stick + left button = smoke. `8 3 8` is NOT used; title starts on fire/button.

## 13. Memory Budget

- **RAM (Coleco ~781 B free is the binding constraint):** actor state (~40 B), flag list
  (10×3 B), smoke list (6×3 B), camera/score/round vars (~40 B) — ≪ 200 B. **No map copy, no
  radar copy** (both re-derived from ROM; radar erase re-bakes from the flag list). Each flag's
  radar dot address + mask are cached once per round (`#fda`/`fdm`, 30 B) so the erase does not
  re-run `dot_addr` ten times per tick. Coleco reports 314/814 B used.
- **ROM (TI, banked — `BANK ROM 128`):** bank 0 = code + logical map1 (~2 K; the fixed area
  caps at 24,336 B); bank 1 = map2 doubled char map (7,888 B, selected during gameplay);
  bank 2 = art/tiles/radar tables/item lists (selected only during init and round setup —
  `round_init` and `rehome` switch to 2 for their `READ`s and back to 1). Coleco builds flat
  (~24 K). Report free bytes every build. Extra maps would need further banks.

## 14. CVBasic hazard rules (binding, from sibling games + this one)

Never `MODE 2`. Never `<cmp> AND/OR <cmp>` on TI — nest IFs. `VPOKE`/`VPEEK` operands
precomputed into plain vars (ISR race). `%` by power of two → `AND`. `#var` compares are
unsigned — split at 32768. `DIM a(N)` is 0..N−1; size for the real max (OOB is Coleco-fatal).
8-bit `FOR` to 255 wraps forever. Hide sprites at y=209. `ON GOTO` is 0-based. `DEF FN` args
textual — parenthesize in body. Computed `FOR 1 TO 0` runs once. Dual-target: build **both**
machines every time; `#if TI994A` (unhuman/CVBasic fork) for splits.

**Found while building this game (all confirmed by reading the generated `.a99`). Three of
these are one family — a constant > 255 silently truncated to 8 bits — hitting three different
syntax shapes:**
- **8-bit var × large constant miscompiles to 0 on the TMS9900 backend** — `th * 2048.` emitted
  a plain `CLR` (the radar-dot third offset was always 0, all dots invisible). Small powers of
  two (`* 8.`, `* 32.`) and `* 34.` compile fine. Workaround: 16-bit intermediate or an
  IF-ladder (`dot_addr` does the latter).
- **Dotted constant folded with another constant truncates to 8 bits** — `#va = $1800 + 728.`
  compiled to `li r0,6360` ($1800 + 728 AND 255 = $1800 + 216): the lives icons drew 16 rows
  high (row 6) and the fuel bar (`$1800 + 696.`) drew over radar row 5. Var-times-dotted-const
  (`rw * 32.`) is fine; it's the *pure constant fold* that breaks. Workaround: precompute the
  folded value yourself (`#va = 6872` in `draw_lives`, `#va = 6840` in `fuel_bar`).
- **A `CONST` > 255 truncates to 8 bits when used** — `CONST FUELMAX = 768` then
  `#fuel = FUELMAX` compiled to `clr @cvb__FUEL` (768 AND 255 = 0): the game started with zero
  fuel, permanent crawl speed, and smoke silently disabled. Bare 16-bit literals are fine
  (`#fuel = 768` emits `li r0,768`). Rule: no `CONST` > 255 in TI-targeted CVBasic — use
  literals or a `#var`.
- **VDP writes (`VPOKE`/`PRINT`) are buffered per frame and bursts silently drop** — the radar
  init's ~1,900-VPOKE loop lost most writes (partial blue canvas, missing FUEL label). Pace
  bursts with `WAIT` (≤ a few dozen buffered ops per frame); `draw_view` also WAITs between
  the `SCREEN` blit and the overlay pokes. TI `DEFINE CHAR`/`DEFINE COLOR` are synchronous
  immediate copies — safe in bulk; radar canvas init uses them from generated ROM tables
  (`radar_zero`/`radar_base` in `src/tiles.bas`).
- **TI cart banking**: fixed area caps at 24,336 B; this game exceeded it in M2. Layout per
  §13: bank 0 code + logical map, bank 1 map2 (gameplay-selected), bank 2 everything else
  (init/round-setup-selected). Coleco builds flat — every `BANK` statement is inside
  `#if TI994A`. `build-ti.sh` auto-detects the `_b0.bin` multi-bank output and refuses a
  >24,336 single-bank binary instead of letting linkticart silently truncate it.

## 15. Build

```
assets/genmap.py  →  src/map0.bas (logical 34×58) + src/map2.bas (chars 68×116)
                     + src/tiles.bas (wall quadrants, flag/smoke 2×2 art, radar tables)
cvbasic --ti994a src/RALLYX.bas → xas99 → linkticart → src/RALLYX_8.bin   (Classic99)
cvbasic          src/RALLYX.bas → gasm80              → src/rallyx.rom    (ColecoVision)
```
via the `build-cvbasic-game` skill / `build-ti.sh` + `build-coleco.sh` like the sibling games.

## 16. Acceptance Criteria

1. Viewport scrolls the transcribed maze correctly in all 4 directions; walls match
   `assets/maze1-render.png` cell-for-cell; car cannot enter walls/trees.
2. Car drives always-forward with queued turns taken at intersections; reverse immediate.
3. All 10 flags collectible; values 100…1000, S doubles, L pays fuel bonus; round ends on 10.
4. Radar shows the whole maze area with flag dots (disappearing on pickup), colour-cycling (white/black) player
   dot, red enemy dots — positions match reality (verify by screenshot probe).
5. Fuel bar drains; smoke drops puffs, costs fuel, stuns enemies; empty fuel = crawl.
6. Enemies chase (reactive), crash costs a life, 3 lives, game over → title, HI persists.
7. Challenge stage after every 2 regular rounds, no enemies, bonus on completion.
8. Both targets build; TI single-bank with free bytes reported; same real-world speed on both
   (FRAME-delta pacing); no hazard-rule violations (§14).

## 17. Status (2026-08-01, later) — performance pass: 8.2 → 60 passes/sec

Full measurements and the two rules they establish are in **§1a**. Summary:

- **The loop now runs one pass per vblank** — 59.7 passes/sec parked, 52.6 while driving with the
  camera panning continuously, against **8.2** before. `#fd` stays between 1.00 and 1.14 and is
  never clamped.
- **Game speed no longer depends on frame rate.** The reported "enemy cars move faster when the
  screen is not scrolling" was a pacing bug, not an enemy bug: the `#fd` clamp of 4 discarded
  real elapsed time whenever the loop wanted a bigger delta, so the world ran at ~half speed
  while busy and full speed while parked. Movement is now O(cells crossed), which makes a large
  delta cheap and safe, so the clamp sits at 16 and ordinary play never reaches it. `sct` and
  `sfxt`, which counted passes rather than frames, are `#fd`-scaled for the same reason.
- **Everything that moves walks boundary to boundary** — `drive_step` (new `pm_top` loop, no more
  per-pixel `move1px`) and `emove_n`. Wall integrity re-verified with an assertion build that
  checks all four corners of the car's 16-px box every pass: **0 violations** over a 20-leg route
  driven into walls in all four directions.
- Cheaper per pass: cached enemy cells (`ecra`/`ecca`), hoisted camera origin (`#cx8`/`#cy8`),
  `update_cam` early-out when the car has not moved, cached flag radar addresses, smoke ageing
  skipped when no puff is live, AI last-resort scan no longer re-probes `p1`/`p2`.

## 17b. Status (2026-08-01) — arcade-accuracy pass

Driven by reference screenshots supplied in review (kept in `assets/`):
- **Start position matches the arcade**: the player faces **up** a clear corridor at bordered
  cell (35,22) with the three chasers lined up in a row **behind** him (row 38, cols 19/22/25),
  each on road with road to the north so they come straight at him. Found by searching the
  transcribed maze for a cell with a clear run north and a spread of road cells to the south.
- **Flags are CHARACTERS again.** As sprites they were drawn with the wrong pattern name (24 =
  an SE *car* frame — a renumbering slip, which is why they looked like cars), read badly
  against the road, and drifted off the cell grid. The original char flicker is gone because
  the `WAIT` that used to sit between the viewport blit and the overlay pokes is gone: both now
  land in the same frame's buffered batch. Flag colours changed for contrast on the tan road —
  white F, light-red S, cyan L (yellow-on-tan was nearly invisible).
- **Smoke is a puff-ball, not a cloud** (§4/§8), traced from the arcade shot, and follows the
  arcade's three-puffs-per-press rule with a real fuel cost.
- **Extra lives are little yellow cars**, the car silhouette at 8×8, matching the arcade.
- **Enemies spin when smoked** instead of freezing.

## 17c. Status (2026-07-30) — renamed to RALLY-X, cars turn properly

- **Renamed** RaltiX → **RALLY-X** everywhere: folder `games/RallyX`, source `RALLYX.bas`,
  outputs `RALLYX_8.bin` / `rallyx.rom`, cart menu label `RALLY-X`, title screen `* RALLY-X *`.
- **Cars rotate instead of flipping** (§6) — eight heading frames, in-place turn, 180° sweeps
  through the sideways heading. Verified in Classic99: a captured mid-turn frame shows a
  diagonal heading, and after a reverse the car ends up facing the opposite way and drives on.
- **Car art redrawn ~12×12 inside the 16×16 box** (§5) so the 45° frames don't clip; one shape
  definition drawn at all 8 angles by `assets/gencar.py`.
- **Enemies never stack** — `probe_free` rejects a cell already occupied by another enemy, so
  the car that would have overlapped turns away instead.
- **Smoke clouds are puffy and one colour** (§4): three lobes over a flat base, white in all
  four quadrant chars. The old version split white over grey across the quadrant boundary,
  which read as a two-tone ball.
- **Radar player dot cycles white/black** instead of blinking on and off — a dot that vanishes
  half the time is hard to track. The flip is driven by its own `BLINKRT` (30-frame) counter in
  the main loop, not by the 5-mover round-robin. Verified: the dot is present in both phases.
- **Fixed: the car could drive through walls** (regression from the turn work). When a 90° turn
  started at a cell centre, `at_center` returned early but `move1px` still ran its remaining
  pixel steps for that frame **in the old direction**, so the turn finished 1–3 px off the
  grid. From then on the car's cross-axis coordinate was never a multiple of 16, `at_center`
  never fired again, `blocked` stayed 0 — and the car drove over everything. Fix: starting a
  turn sets `blocked = 1`, pinning the car on the centre for the rest of the frame (`turn_step`
  clears it when the turn ends). Verified by sampling the four corners of the car's own 16-px
  cell (art-free, since the car is 12 px) after three turn-heavy routes: road on all of them.

## 17d. Status (2026-07-29, later)

**Review fixes:**
- **Flags are now SPRITES (slots 5–14), not characters** — that is what caused the reported
  flicker: a char flag had to be re-poked after every camera-pan blit (which repaints the whole
  window with road), and the poke landed a frame later, so at ~3 pans/second the flags strobed.
  As sprites they ride above the chars untouched, pickup needs no char erase, and `draw_view`
  got cheaper. Priority is correct by slot number: player (0) and enemies (1–4) outrank flags,
  so the 4-per-scanline limit drops a flag, never an actor.
- **The car could escape the window (reported: "exited on the left … flipped to the right side").**
  Root cause found in `update_cam`: it panned at most ±1 char per iteration, but on a pan frame
  the blit stalls the loop 2–3 frames and FRAME-delta catch-up moves the car up to 12 px while
  the camera moves 8 — so the car slowly outran the window, the **unsigned** dead-zone compare
  wrapped, and the sprite flipped to the far edge. Now the camera is computed as an allowed
  **range** (`camc ∈ [carchar−13, carchar−10]`), snapping any distance in one step, with the
  subtraction clamped at 0 before use (near the left/top edge the car char is as low as 2, so
  `carchar−13` would wrap to ~65525). Verified with a min/max screen-position probe over a long
  multi-turn drive: the car stayed at screen chars 11–13 / 10–13, never leaving the dead zone.
  A first attempt at this reused one variable for both the car char and the new camera value, so
  the second bound compared the camera against itself+10, always fired, and dragged the camera
  10 chars back — the camera then ran away from a parked car. Separate lo/hi/snapshot vars fix it.
- **Real car art**: 16×16 top-down F1 (narrow nose, four protruding wheels, wide midsection,
  rear wing) from `assets/gencar.py`, replacing the placeholder. The `up` design is
  left-right symmetric so its rotations stay readable, and wheels come out 2×4 travelling
  vertically / 4×2 horizontally. Enemies share the art recoloured red.

**Follow-up: the freeze was real, and it was a variable-name collision.** The camera rewrite
above used `#hi` as scratch for its upper bound — and **`#hi` is the high score**, so
`update_cam` overwrote it every single frame. The visible symptom was a garbled high score
(reported from play), and because `take_flag` then saw `#score > #hi` on essentially every
pickup it re-drew the HI field constantly; the game went on to lock up. Renamed the camera
bounds to `#cblo`/`#cbhi`. Verified: the exact route that previously froze (zero changed
pixels across 2 s) now runs with 317 k changed pixels and a stable `1UP 100 / HI 5000` panel.

Two lessons recorded: **prefix scratch variables per-routine** (`#cb…` for camera bounds) in a
language with only global variables, and treat "a displayed value is garbage" as naming the
corrupted variable — that report localised the bug immediately after a long, and largely
wasted, emulator bisection.

**Also fixed:** `prt_score`/`prt_hi` printed numbers with no fixed width and only two trailing
spaces, so a value needing fewer digits than the previous draw (e.g. `#score` back to 0 on a
new game) left the old value's right-hand digits on screen. Both now blank the 8-char panel
field before printing.

**Harness note:** Classic99 screenshot capture requires an interactive, unlocked desktop, and
the emulator must be given foreground by a real mouse click (`SetForegroundWindow` alone is
refused for a background process — keystrokes then go elsewhere and the cart never starts,
which mimics a freeze). Capture rects must also be clamped to the virtual screen. The working
probe is `scratchpad/probe5.ps1`.

## 17e. Status (2026-07-29)

**2×-scale world shipped:** the game now renders 2×2 chars per maze cell (16-px roads; the car
fills its lane; 12×12-cell viewport), per review feedback — verified in Classic99: title →
fire → play, flag pickup, big 2×2 smoke puffs, queued turn + camera pan, wall stop, radar
intact. TI cart went to three data banks for it (§13).

Earlier status (2026-07-28):

**M1–M3 built and emulator-verified; M4 core built.** Verified in Classic99 by scripted
screenshot probes: scrolling/camera/walls/turns (M1); flags, pickup+scoring (100 shown), radar
canvas with flag dots + blinking player dot, fuel drain, HUD (M2); enemy pursuit + crash +
respawn + scatter (sct telemetry), smoke puffs (nsm/fuel/ttl telemetry), enemy radar dots,
fuel bar, lives icons (M3); title → fire → fresh game flow and an on-screen chasing red car
(M4). Round-clear, challenge-stage and game-over paths are code-complete (crash/rehome/reset
verified; full multi-round session not yet manually played through).

**Deferred (next session):** in-game background music (jingles exist; the continuous New
Rally-X theme needs `PLAY`-vs-SFX channel budgeting), maps 2–4 transcription (bank 1 is full —
needs BANK 2+ and bank-switch discipline around map reads), rocks (no rocks in round 1),
smoke-puff animation frame, per-round flag-position variation (currently every round reuses
the round-1 flag set), Coleco emulator gameplay pass (`rallyx.rom` builds; only TI was
runtime-tested).
