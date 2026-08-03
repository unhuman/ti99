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
- **The radar canvas is wiped at the start of every round** (re-`DEFINE`d from `radar_zero`/
  `radar_base` while bank 5 is selected) before this round's flags are baked. It used to be
  zeroed only once at boot, so each round inherited the previous round's flag dots — and since
  every round is now a different maze with different flag cells, those stale dots read as flags
  you could collect but never needed.
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

- **Four mazes**, all transcribed at the cell grid from the arcade rips (§0), cycling with the
  round: `mz = (rnd - 1) AND 3`.
- **One encoding, not two.** Each maze is a single 68×116 CHAR map (`src/map2_1..4.bas`, 7,888 B
  each), walls pre-edged with quadrant variants, stride 68. The separate logical map is **gone**:
  map2 already encodes cell type in its top-left quadrant — road cells are plain ROAD in all four,
  trees TREE, walls the edged 96–111 — so the same `>= ROADCH` test works and `probe` reads it at
  `row*136 + col*2`. That saves 1,972 B per maze and is what let four of them fit.
- **One maze per ROM bank** (1–4); art, radar tables and the item lists share bank 5. `mz` selects
  both the bank and which `map2_n` the `SCREEN` blits name. **Banking is on for BOTH targets** now:
  four maps do not fit ColecoVision's 32 K flat ROM, so it uses Opcode's Megacart mapper (128 K).
- **Item lists are per maze** (`src/items.bas`, generated by `assets/genmaps4.py`): 10 flag cells,
  the player start, and four enemy spawns, 30 bytes per maze back to back — `round_init` restores
  to the first and skips `mz` blocks. Maze 1's start is **pinned** to the hand-found arcade
  position (35,22); mazes 2–4 have theirs searched for (road, clear run north, four road cells
  three rows south). Flag positions use maze 1's ten as a **distribution template**, each snapped
  to the nearest road cell — the arcade rips only show 4–7 flags on maps 2–4 and no start at all,
  so those cannot be transcribed directly.
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
- **Difficulty ramps on three dials together** (round 1 used to open with three cars at 83 % of
  the player's speed all beelining from a 3 s head start):

  | dial | round 1 | ramp |
  |---|---|---|
  | car count (`nen`) | **3** (the arcade count) | 4 from round 5 |
  | speed (`espd`) | 1.75 px/f | +0.25 a round, capped at 3.75 |
  | smarts (`eagg`) | 3 decisions in 8 taken direct | +1 a round, always from round 6 |
  | head start (`scti`) | 5 s of scatter | −0.5 s a round, floor 2 s |

  **`eagg` never makes a car flee.** It used to: below full aggression a car reused the scatter
  inversion and drove *away* from the player for that decision. That does not play as "easier",
  it plays as the cars being broken and refusing to chase, which is exactly how it was reported.
  A slack decision now closes on the **shorter** axis instead of the longer one — the car still
  comes at you every time, it just takes the less direct line, loses ground in the open and is
  much easier to shake round a corner. Real fleeing is left to the scatter phase, where it is
  deliberate and time-boxed. Because a slack decision still pursues, the floor was widened
  (`4 + rnd` → `2 + rnd`) so the ramp still has somewhere to climb from.
- At each cell center pick: prefer the axis with the larger gap to the player if open, else the
  other axis, else keep straight, else any open ≠ reverse, else reverse — **and every one of
  those is validated**, including the dead-end reverse. In **scatter** the preferences invert.
  Stunned (smoke) = 90-step spin.
- **Two cars can never occupy one cell. This is a hard invariant, and it is easy to break:**
  - Every heading a car commits to — from the AI, from a bump, or from the dead-end fallback —
    goes through `probe_free` first. The dead-end case used to assign reverse unconditionally on
    the reasoning that "the cell you came from is always open"; true of walls, false of cars.
  - `probe_free` rejects a cell another car is **driving into**, not just one it is standing in.
    A car only starts occupying a cell once it fully arrives, so two cars approaching the same
    empty cell from opposite sides were both cleared to enter it.
  - A car with nothing open at all is **cornered**: it spins on the spot and re-decides when a
    neighbour clears, instead of driving into an occupied cell.
- **Measure overlap in PIXELS, not cells.** The cell-overlap probe read a clean 0 for sessions
  while cars were still visibly stacked, because logically they *were* in different cells — it
  was measuring the wrong thing. A 16-px car straddles two cells for its whole traverse, so the
  test that matters is `|dx| < 16 AND |dy| < 16` on `#ex`/`#ey`. Same probe, same 30 s route,
  same pass count: **15 overlapping passes of 318 → 0** at round 6, and **5 of 783 → 0** at
  round 1, with mean chase distance holding at 4 cells (round 6) and improving 10 → 6 (round 1).
- **Bumps are visible** (`ebump`). When a car's first choice is refused by another *car* rather
  than a wall, both spin for `BUMPFR` steps and leave in **different** directions: straight back
  if that is open, else any other open heading, and the second car may not reuse the first's
  choice. Order matters — the first car's heading is committed *before* the second picks (so the
  second sees the reservation), and both are stunned only *afterwards* (a stunned car reserves
  nothing, so stunning them up front made the pair invisible to each other for exactly the two
  picks that must not clash). `pfhit` is latched on entry because `probe_free` overwrites it.
- **Enemies advance in cell-bounded chunks** (`emove_n`), not one subroutine call per pixel: a
  car moves straight to the next 16-px boundary or to the end of this frame's travel, whichever
  comes first, and only stops to run the AI on a boundary. Each enemy also completes a whole
  frame's travel before the next one starts, rather than being interleaved pixel-by-pixel; the
  no-stacking guarantee is unaffected because `probe_free` compares **cell** coordinates and a
  car occupies its cell for many pixels. This was the single largest cost in the loop (§1a).
- **Every car's cell is cached** in `ecra`/`ecca` as an **anchor**: it moves only when the car
  fully *arrives* on a boundary, never mid-transit. Recomputing it from raw pixels every chunk is
  asymmetric — a car moving **up or left** crosses into the next cell's pixel range after ONE
  pixel of travel, so it reported the new cell while its 16-px body still covered nearly all of
  the old one. That released the old cell to another car and the two visibly sat on top of each
  other. Holding the anchor until arrival makes a car in transit reserve both the cell it is
  leaving and the one it is entering (`pf_ahead`) — which is what its body actually covers. Two
  cars cannot double-book the destination either, because they decide one at a time inside the
  `FOR i` loop, so the second sees the first already holding it.
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
- **Which flag is S and which is L is rolled each round** (`sidx`/`lidx`). The ten POSITIONS stay
  as transcribed from the arcade map — they are spread deliberately — but the roles move, so a
  round cannot be memorised as "the double is always in the top right".
- **S doubles what comes AFTER it, not itself.** `#val` is doubled before `sgot` is set, which is
  the arcade rule.
- **Out of fuel is not fatal**: speed halves to 1.5 px/f, smoke is refused (it costs 96 fuel),
  the engine drops to its idle note, and the round continues — as in the arcade, where running
  dry leaves you crawling until something catches you.
- Values: 1st flag 100, then 200, 300 … (per pickup order, capped 1000). After collecting **S**,
  every later flag's value is **doubled**. **L** additionally pays `remaining fuel bar px × 10`.
- Collecting all 10 ends the round: round card, **fuel bonus**, jingle, next round.
- **Fuel bonus** pays what is left in the tank on the lucky flag's scale (bar pixels x 10, so a
  full tank is 640). It is TALLIED rather than handed over: one unit at a time moves out of the
  gauge into the score, the bar visibly empties, and each tick blips at a falling pitch (on for
  a frame, off for a frame -- a held tone just smears into a siren). ~2 s for a full tank.
  The music and engine are stopped at the top of `round_done` so the tally and jingle have the
  sound chip to themselves; `round_init` starts the music again.
- **The lucky flag pays POINTS, not fuel** — verified: it *"gives bonus points based on how much
  fuel the player has"*. It never refills the tank.
- **A new car starts the stage fresh** — the arcade rule, verified against the Rally-X
  references. Losing a life **resets the fuel gauge to full**, sends **the next flag back to
  100**, and **cancels the special's doubling**. Collected flags stay collected: it is the
  SCORING that resets, which is why `vstep` (value progression, per life) is separate from
  `nfl` (flags collected, per round). All three live in `restart`, and `round_init` falls
  through to it, so one copy covers both a new round and a new car.
  (An earlier version kept all three across a death on the reasoning that it should not
  retroactively punish banked flags. The arcade does exactly the opposite, and the reset is
  also what stops a deliberate crash being a cheap refuel.)
- **Dying DOES cancel owed smoke.** A press queues `SMKPUFF` puffs that are laid one per cell as
  the car drives on; `restart` clears `smkq` (and sets `btnp`) so a respawned car never trails
  smoke the player did not ask for, and a fire button still held from the crash does not fire.
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

## 8a. Sound channel budget

The SN76489 has three tone channels plus a noise channel, and everything here
depends on this split:

| channel | use |
|---|---|
| 0, 1 | background music — **our own player**, not CVBasic's `PLAY`; OFF by default |
| 2 | flag blip, round-clear jingle, game-over sting |
| 3 | engine buzz, and the crash boom that overrides it |

**The engine note is periodic noise at the LOWEST rate (control 2, ~116 Hz).** Channel 3's control
byte picks the source in bit 2 (0–3 periodic, 4–7 white) and the shift rate in the low two bits
(0 = clk/512, 1 = clk/1024, 2 = clk/2048; **3 is unusable here** — it follows channel 2, the SFX
channel, so the engine would change pitch under every flag blip). Periodic noise repeats every 15
shifts, so the audible pitch is clk/(rate × 15): rate 1 is ~233 Hz, rate 2 ~116 Hz. It ran at
rate 1, and 233 Hz of constant buzz is a whine rather than a motor.

**Driving and idling share the note — it is one car with one engine.** What separates them is
loudness and steadiness: driving is a steady 11, idling **chugs** between 9 and 6 every `ENGCHG`
6 frames (~10 Hz), frame-delta paced like every other timer here. A stopped car still has an
engine, and an idle is the same motor turning over slowly and unevenly, so a lumpy quiet version
of the driving note is what it should be. An earlier cut gave the stopped state **white** noise
to keep it clear of the driving note; that distinguished the two fine but stopped sounding like
an engine at all — it was a hiss.

Note the pitch floor: periodic rate 2 is as low as this can go. Rate 3 clocks the noise from
channel 2, which is the SFX channel, so borrowing it would make the engine change pitch under
every flag blip. Anything lower has to come from **volume** — but mind the scale:
SN76489 volume is **logarithmic**, roughly 2 dB a step. A first cut chugged 5/2 against a driving
11, i.e. 12–18 dB down, which is not "quiet" but inaudible, and came back as "there is no sound".
9/6 is 4–10 dB down: clearly under the driving note and clearly still an engine.

**Music is OFF by default, toggled with `1` on the title screen** (`musen`, shown as
`1 MUSIC ON/OFF` under PRESS FIRE). Nothing is competing for a channel — music is on 0/1 and the
engine is noise on 3 — but the two still fight for the ear, and the busy mix is why the engine
read as inaudible. Off is the better default for a game whose signature sound is the engine;
anyone who wants the tune presses one key. `musen` is a **preference**, so unlike the 838
settings it is set once at boot and survives game over. `mus_start` simply refuses to start the
player when it is 0. The toggle key is `1`, which is not part of the 838 sequence and so cannot
interfere with it (verified: 8-3-8 still opens setup after toggling).

**We drive the music ourselves** (`mus_tick`). CVBasic's PSG `PLAY` writes the volume registers
from envelope tables baked into the shared prologue, so a game cannot turn it down — and this tune
has to sit UNDER the engine and the effects. Ours sets volume explicitly: melody `MUSVOL` 6, bass
`MUSBAS` 5, against an engine at 11. The song is the **original tune restored note for note** (a C-F-G-C arpeggio run) plus an
answering phrase in the same style that drops to the relative minor and climbs back to resolve —
32 notes over 64 steps, twice the length at the same character. `MUSTICK` 7 with two steps per
note reproduces the original's 0.24 s note. A previous attempt replaced the tune with four
contrasting sections and was worse; extending it beat replacing it. The bass plays at the
WRITTEN pitch, not the two-octaves-down the original asked for: the SN76489 bottoms out near
110 Hz, so those notes were silent and the tune was effectively melody-only. Data is
`assets/genmusic.py` → `src/music.bas`, note indices into a table of 16-bit SN76489 dividers, and
it **must live in TI bank 0** because the player runs every frame while a maze bank is selected.

The **music data must live in TI bank 0**. The player refills the sound registers from the vblank
ISR, which can fire at any point, including while gameplay has bank 1 (map2) or bank 2 (art)
selected; bank 0 is the only one mapped the whole time.

The **engine** is channel 3 in *periodic* mode (control 0–3), which is a buzz rather than a hiss.
It is re-issued only when the car's state changes — rolling / parked-or-turning — so the hot loop
pays two compares, not a sound write per frame.

## 9. Collisions & Lives

- Player vs enemy: pixel boxes within 12 px on both axes ⇒ **crash**. **Both cars are destroyed:**
  every sprite is parked, **BANG** is stamped on the wreck (one char row up, so the blast does not
  sit across the letters), two explosions flash out — one at each car — the border strobes for
  ~0.2 s, and the boom is on the noise channel. Lose a life, enemies rehome to spawns, player
  restarts at the start cell — flags stay collected, but fuel, flag value and the S multiplier all
  reset (§7). 3 lives; game over card → title.
- **The collision test runs inside both movement loops, after every chunk** — not once per pass.
  Detection needs `|dx| < 12` on both axes, a 24-px window, and the pair closes up to 3 + 3.75 px
  per frame, so a single end-of-pass sample let a fast pair jump clean through each other. That
  was the "player drove through an enemy car" bug. `hitf` is cleared before anything moves and
  acted on once at the end of the pass, so a hit found mid-movement still unwinds cleanly.
- **Game over tears the playfield down in two stages**, so neither screen is drawn over
  leftovers. `hide_spr` parks all five car sprites at y=209 *before* the GAME OVER card, so the
  wreck and the chasers do not sit frozen underneath it; then, after the sting, `clear_view`
  blanks the 24×24 viewport before jumping to `title`, so the title is not printed over a stale
  maze. `clear_view` writes one row per frame — 24 chars is already a sizeable buffered burst,
  and bursts past the per-frame budget are dropped silently. (y=209, never 208: 208 is the
  sprite-list terminator and would blank every sprite after it too.)
- Player vs rock (rounds ≥2): same as a crash.
- Enemies ignore rocks/flags/each other.

## 9a. 838 setup mode

Type **8, 3, 8** on the title screen to open a hidden setup with two questions:

- **CARS 1-10, 0=10** — starting lives
- **LEVEL 1-10, 0=10** — starting round

The settings last for **one game only** — `game_over` puts them back to 3 cars from round 1, so a
new game off the title is always the standard one.

Answers are single digits read with `CONT1.KEY`, which returns 0-9 on **both** targets (the
ColecoVision keypad and the TI keyboard) and 15 for nothing pressed, so the same code serves
both. The watcher is edge-triggered — the key must be released between digits or one press
reads as several. Starting above round 1 also re-phases `rc3`, the 0..3 challenging-stage
phase, so a mid-game start still lands the bonus round on the same ABSOLUTE schedule (start at
round 5 and the next stage is still round 7, not five rounds later). The phase is `(rnd - 3)
mod 4`, written as `(rnd + 1) mod 4` so every intermediate stays positive — these are unsigned
8-bit vars, and `rnd - 3` at round 1 would wrap to 254 and take 63 trips round the wrap loop.

## 10. Rounds & Challenge Stages

**Challenging stage — rounds 3, 7, 11, 15 … (researched, not assumed).** Wikipedia: *"The third
level and every fourth thereafter is a bonus round"*, and *"in these bonus rounds, the red cars
remain idle and will not chase the player unless their fuel is empty."* This was previously
every **third** round, which is wrong.

The red cars are **present but STILL**, and they wake up when the tank runs dry — that is the
answer to "when do they activate": the stage is a race to clear the flags before your own fuel
arms the thing chasing you. `chal` gates `emove_n` on `#fuel > 0`.

**`chal` gates their MOVEMENT ONLY — never their hitbox.** It used to gate `ckhit` as well,
making a parked car scenery you could drive straight through. That is wrong on the arcade (an
idle red car still kills you) and it looked like a bug besides. Verified in-game: driving into
the parked row at round 3 now costs a life per car.

Regular rounds reuse the four maps cyclically with per-round flag/spawn lists and rising
speeds/counts (3 chasers from round 1, a 4th from round 5 — difficulty scales **speed and
smarts, never count beyond 4**). Clearing a challenging stage pays a 1,000-unit bonus on top of
the usual fuel bonus, and the stage opens with a "CHALLENGING STAGE" card.

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

## 17. Status (2026-08-01, latest) — crash graphic, score popup, chase fixes

- **BANG is a graphic** (§9): a starburst with the lettering embedded, generated by
  `assets/genbang.py`, in **one 2×2 cell** — two animation frames at chars 16–23.
- **The explosion is CHARACTERS, not sprites.** It belongs to the roadway: a sprite is placed
  in screen pixels, so it slid out of register with the maze the moment anything scrolled.
  Animating costs four `VPOKE`s (swap which frame's codes are on the name table). The burst
  origin is the car's own top-left character — the car is 2×2, so no centring offset.
- **Flag values pop up** in a 2×2 box (§7) — the value over `x2` when the special is doubling it.
  The box is **composed in RAM at pickup**, not fixed art: 16×16 px has room for four 4-px
  columns only, so a 3×5 mini font is blitted into four characters and uploaded with
  `DEFINE CHAR …,VARPTR`. That reserves four character codes instead of one tile per value.
  The mini font lives in **TI bank 0** — gameplay reads it with bank 1 or 2 selected. The box is
  anchored to the **flag's map cell**, so it scrolls with the road and stays where the flag was.
- **Custom art must stay clear of char 32.** A first cut put the burst at chars 16–33, which
  redefined **SPACE** — `CLS` fills the screen with it and every `PRINT` pads with it, so the
  panel's blank cells turned into tan starburst rubble. Burst now sits at 16–27 and the popup
  glyphs at 130–140, in the gap between the lives icon (129) and the radar canvas (144).
- **Cars no longer spin on contact.** Meeting another car parked one of them for 64 steps, and
  since the pack converges they met constantly — which read as "going crazy and not chasing".
  Meeting a car now just turns it, with a short heading commitment so it does not immediately
  walk back into the same jam. Measured: **0 stunned passes** over 637 (was routinely stunned).
- **`eagg` floor raised 3 → 5.** At 3-in-8 pursuit the cars deliberately headed away five times
  in eight; that does not read as "easier", it reads as broken.
- ColecoVision ROM is now **32 KB — the flat maximum**. Anything further needs `BANK ROM`.

## 17b. Status (2026-08-02) — the overlap the cell probe could not see

- **Fixed: cars overlapping.** Not a new AI hole — a MEASUREMENT hole. Every previous pass was
  verified against a cell-overlap probe that read 0, while the cars on screen were still stacked,
  because the cached cell was released mid-transit: moving up or left, a car reported the next
  cell after one pixel of travel while its body still covered the old one. Two cars in genuinely
  different cells, overlapping by up to 15 px. The cell cache is now an **anchor** that only moves
  on arrival (§6). Measured with a PIXEL-overlap probe on a fixed 30 s route: **15/318 passes
  → 0** at round 6, **5/783 → 0** at round 1.
- **Fixed: cars "not chasing".** Below full aggression `eagg` reused the scatter inversion and
  sent the car *away* from the player. It now takes the shorter axis instead — always closing,
  just less directly (§6). Mean chase distance at round 1: **10 → 6 cells**, on the same route
  with the same pass count. The floor was widened `4 + rnd` → `2 + rnd` to keep a real ramp now
  that a slack decision still pursues.
- **Engine pitch dropped an octave.** It was periodic noise at shift rate 1 (~233 Hz) — a whine,
  not a motor. Now rate 2 (~116 Hz), the lowest periodic pitch available without borrowing the
  SFX channel; the stalled variant moved to white noise at the same rate (§8a). Verified in the
  generated `.a99` that both branches emit the intended control bytes (2 and 6).
- **Challenging stage corrected to the arcade schedule and rules.** It fired every *third* round;
  the arcade is *"the third level and every fourth thereafter"* — 3, 7, 11, 15. And `chal` gated
  the enemy **hitbox** as well as their movement, so a parked red car was scenery you could drive
  straight through; the arcade lets an idle car kill you. Movement only now (§10). The activation
  rule was already right: they wake when the tank runs dry.
- **3 chasers from round 1**, not 2. Both Rally-X and New Rally-X run three from the start;
  opening with 2 read as under-populated rather than easy. The 4th now arrives at round 5. Early
  mercy comes from the speed dial, not from leaving a car out.
- **Music is off by default**, toggled with `1` on the title (§8a). It never shared a channel with
  the engine, but it crowded it; off is the right default for this game.
- Both targets rebuilt; 838 setup verified still reachable after using the new toggle key.

## 17a. Status (2026-08-01) — difficulty, collisions, audio

- **Difficulty ramps** on four dials instead of opening at full tilt (§6).
- **Fixed: the player could drive through an enemy car.** The hit test sampled only the end of
  each pass; it now runs inside both movement loops after every chunk (§9).
- **Fixed: two enemies could share a cell and thrash.** Three separate holes — an unvalidated
  dead-end reverse, two cars cleared into the same empty cell because neither occupied it yet,
  and `ebump` stunning both cars before picking their headings, which hid them from each other
  (§6). Verified with an assertion build that checks every enemy pair every pass at round 9
  (4 cars, top speed, full aggression): **0 violations over 351 passes with 28 bumps taken**.
  The same probe reported 3 violations before the fixes and 1 after the first two, which is why
  all three were needed.
- **Crash is now a real event** (§9): both cars destroyed, BANG on the wreck, twin blasts, border
  strobe, noise-channel boom.
- **Audio**: looping background music on channels 0–1, engine buzz on 3, effects on 2 (§8a).
- Loop rate unchanged by all of the above: still **1.00 pass per vblank** (59.6/sec measured).

## 17a. Status (2026-08-01, later) — performance pass: 8.2 → 60 passes/sec

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
- **Game over cleans up after itself** (§9): sprites hidden before the GAME OVER card, viewport
  wiped before the title returns. Verified across the whole death → card → title → new game
  cycle: no cars under the card, no maze behind the title, and the maze repaints correctly when
  a new game starts.

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
