# PUZZLE BOBBLE — Design

> CVBasic game, **dual-target**: TI-99/4A (native TMS9900 cartridge ROM, `--ti994a`) **and**
> ColecoVision (native Z80 ROM, CVBasic default target) from the same `src/PUZBOBL.bas` —
> not an XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic
> hazard list (`CLAUDE.md` §3A, restated as §14 here) is binding. Sibling CVBasic projects:
> `games/RallyX`, `games/Structris`, `games/HardHatMack`, `games/Astiroids`.

This document describes the game to be built. Once code exists, `src/PUZBOBL.bas` is the source
of truth; keep this file in sync with any behaviour change (repo standing rule).

---

## 0. Provenance

Clone of Taito's **Puzzle Bobble** / *Bust-A-Move* (1994): a hexagonally-packed field of coloured
bubbles hangs from a ceiling; a launcher at the bottom fires a bubble along an aimed ray that
bounces off the side walls and sticks on first contact. Three or more of a colour in contact pop,
and any bubble no longer connected to the ceiling falls. The ceiling descends on a timer.
Clear the field to advance; let a bubble cross the death line and you lose.

**30 static levels**, played in fixed order. Layouts are *data*, not code (§7).

---

## 1. Performance Budget (decide-before-code, per repo mandate `CLAUDE.md` §5A)

This is a cheap game for this hardware, and the budget is what keeps it that way.

- **Moving objects during play: one.** The flying bubble. Everything else on screen is static
  characters or a parked sprite. There is no AI, no scrolling camera, and no per-frame pathfind.
  The FRAME-delta feedback loop that cost RALLY-X a session (`CLAUDE.md` §3A) does not arise:
  the loop is a fixed one-pass-per-vblank `WAIT` loop with a fixed pixel step.
- **Sprites: 9 max, 1 moving.** Flying bubble = 2 overlaid sprites (base shade + lit cap, §5),
  next bubble = 2, launcher dragon = 2, aim guide = 3 dots. Never more than 4 on a scanline.
  `SPRITE FLICKER` stays **off** (repo memory: it rotates all 32 slots including the player).
- **Per-frame VDP reads: zero.** The field lives in a 96-byte RAM array; nothing is ever
  `VPEEK`ed back out of the name table. Contrast `mspacman-cv-xb-port`, which reads the maze
  from VRAM because Coleco RAM was too tight — here the field is small enough to mirror.
- **Per-frame VDP writes during flight: ~9 sprite attribute updates.** Nothing else.
- **Field redraws are event-driven, never per-frame**, and are budgeted at **≤512 bytes of VDP
  writes in a single frame** — under the 576-byte `SCREEN` blit RALLY-X already performs in one
  frame on both targets (`games/RallyX/DESIGN.md` §3). Redraw events: a bubble sticks, a group
  pops, the ceiling drops, each shake phase, each slide step.
- **Flood fill runs at most twice per shot**, never during flight, and is hidden under the pop
  animation. Budgeted at ≤2 frames (§9).
- **Loop is real-time, `WAIT`-paced, one pass per vblank.** Both targets are 60 Hz, so a fixed
  per-frame pixel step needs no rate scaling — no `pacen`, no FRAME-delta accumulator.

---

## 2. The geometry decision everything else falls out of

**Every bubble is 2×2 characters and every bubble is character-aligned, in every state the field
can be in.** This is the load-bearing decision. It is what makes shake, ceiling-drop and the
round-clear slide all cost one blit each instead of a pattern-table rebuild.

| Quantity | Value | Why |
|---|---|---|
| Bubble size | 16×16 px = **2×2 chars** | one sprite, one 2×2 char stamp |
| Column pitch | 16 px = **2 chars** | |
| Odd-row horizontal offset | 8 px = **exactly 1 char** | hex stagger stays char-aligned |
| Row pitch | 16 px = **2 char rows** | |
| **Ceiling descent step** | **8 px = 1 char row** | half a row pitch — the field stays char-aligned |
| Shake amplitude | ±8 px = **±1 char** | ditto |

The ceiling drop is where the character alignment could have broken, and it doesn't. Dropping the
field by one *character* row (8 px) translates the whole field as a rigid body by one name-table
row. Every bubble's top-left corner is still on a character boundary; relative row offsets are
unchanged; **no pattern needs redefining and no shifted char variants exist.** Two drops equal one
bubble row of lost headroom.

Had the drop been a sub-character distance (4 px, or a "true hex" 12–14 px row pitch), a character
cell would contain the bottom of one bubble and the top of another — two different colours in one
cell, needing a pattern *and* colour variant per ordered colour pair. That is a combinatorial
explosion and the reason this design does not chase true hex packing.

**The cost of the 16-px row pitch:** diagonal neighbours sit √(8²+16²) ≈ 17.9 px apart rather than
16, so tightly-drawn circles would show small diamond gaps. Fix it in the art, not the geometry:
draw bubbles filling their 16×16 cell (a rounded, slightly-squared sphere) so neighbours meet.

> **Superseded (build 3):** the "cost of the 16-px row pitch" paragraph below still holds, but the
> paragraph about 8 px of slack does not — the walls move with the field now (§8), so the field
> spans the full well and bubbles reach the walls.

**Field origin.** The field's on-screen position is a single pair of variables:

```
fx  = field left edge, in CHARACTER columns   (shake varies this: FXBASE-1 / FXBASE / FXBASE+1)
top = ceiling offset,  in CHARACTER rows      (drop and round-clear slide increment this)

grid cell (r,c) draws at  char row = CEILROW + top + 2*r
                          char col = fx + 2*c + (r AND 1)
grid cell (r,c) centre at well-pixel  x = 8 + 16*c + 8*(r AND 1)
                                      y = (CEILROW + top + 2*r)*8 + 8
```

Everything in §8, §10 and §11 is a consequence of those four lines.

---

## 3. Screen Layout (32×24, CVBasic default mode — never `MODE 2`)

> **Revised 2026-08-15 (build 5).** The drop telegraph is now primarily **audio**: a two-tone
> alarm (660/880 Hz, 4 beeps/sec) starts 80 frames before the drop, and the board gives a single
> nudge right-and-back 20 frames before it. Every shake phase is a full field redraw, so the
> shake's cost scaled with its length — audio costs the loop nothing, so the warning got longer
> *and* cheaper. The HUD is **left-justified on column 22**, the column the score digits already
> start at, so labels align with their values (this reverses the right-justification below).
> Movement and every timer are paced by **elapsed frames**, not loop passes.

> **Revised 2026-08-15 (build 3).** The well no longer carries 8 px of slack each side. The
> field spans the **full** well so **bubbles touch the walls**, and the walls shake *with* the
> field — they live in the same row buffer (§8), so the whole assembly slides as one unit. The
> board occupies columns 0–19 (18 chars of wall+field, ±1 char of shake travel) and the HUD is
> **right-justified** into columns 20–31 with one column of space at the right edge.
> The block below describes the superseded layout and is kept for the reasoning about slack.

```
col:  0 | 1 ................................ 18 | 19 | 20 ........... 31
      W |          WELL INTERIOR (18 chars = 144 px)   W |   HUD PANEL (12 chars)
      A |                                              A |
      L |   grid columns 0..7 at 16 px pitch           L |  row 0    : "1UP"
      L |   even rows: 8 bubbles spanning 128 px       L |  row 1    : score, 8 digits (§11a)
        |   odd rows : 7 bubbles, +8 px offset           |  row 3    : "HI"
        |                                                |  row 4    : high score, 8 digits
        |   at rest the field is inset 8 px each side    |  row 6-7  : "ROUND" + number
        |   -> that 8 px of slack each side is exactly   |  row 9-10 : "NEXT" + next-bubble well
        |      the shake travel, so bubbles never        |  row 13   : "TIME"
        |      overlap the walls and the walls           |  row 14   : drop-timer bar, 8 chars
        |      themselves never redraw                   |  row 17-21: BUB (mascot, decor)
        |                                                |  row 23   : lives / spares (§12)
row 0  : CEILING BAR (solid, full well width)
rows 1-19: play area  (grid row r occupies char rows 1+top+2r and 1+top+2r+1)
row 20 : DEATH LINE (dashed rule). A bubble whose bottom reaches row 20 ends the game.
rows 21-23: launcher deck — dragon sprite, loaded bubble, aim guide dots
```

- Well interior is **18 chars (144 px)** rather than the field's 128 px. That extra 8 px each side
  is deliberate: it is the shake travel. It means the shake never has to move or redraw the wall
  columns, which keeps a shake phase inside the 512-byte frame budget.
- Ball bounce planes are the well interior edges: bubble centre x is clamped to `[8, 136]` in
  well-pixel space (bubble radius 8).
- Playable depth: with `top = 0`, grid rows 0..9 fit above the death line. The grid array carries
  **12** rows so attachments below the initial fill and a few ceiling drops have somewhere to go.

---

## 4. Characters (CVBasic `DEFINE CHAR` / `DEFINE COLOR`, per-8×1-line colour)

The default CVBasic mode gives **one foreground/background pair per character scan line** —
confirmed in `games/Structris/src/STRUCTRS.bas`, whose `DEFINE COLOR 128,11,tile_colors` is backed
by 11×8 colour bytes. That is what makes a shaded sphere possible in characters.

**Bubble stamp:** 8 colours × 4 quadrant chars = **32 chars**, codes 128–159.

```
colour k occupies codes 128+4k .. 131+4k
    +0 top-left    +1 top-right
    +2 bottom-left +3 bottom-right
```

**Shading without breaking the 2-colour rule.** Each bubble colour is a *(lit, base)* pair. Pixel
rows 0–5 of the sphere use the lit shade, rows 6–15 the base shade. Every character scan line
therefore contains exactly two colours — one bubble shade and the well background (black) — and is
always legal. No cell ever contains two different bubbles, because bubbles are 2 chars wide on a
2-char pitch and always char-aligned (§2), so there is no seam case to handle.

| k | Bubble | base (fg, rows 6-15) | lit (fg, rows 0-5) |
|---|--------|----------------------|--------------------|
| 0 | red    | 8 medium red   | 9 light red    |
| 1 | green  | 12 dark green  | 3 light green  |
| 2 | blue   | 4 dark blue    | 5 light blue   |
| 3 | yellow | 10 dark yellow | 11 light yellow|
| 4 | cyan   | 7 cyan         | 15 white       |
| 5 | magenta| 13 magenta     | 15 white       |
| 6 | white  | 14 gray        | 15 white       |
| 7 | orange | 6 dark red     | 9 light red    |

Background for every bubble line is **1 (black)** — the well interior colour.

Colours 6 and 7 are the least distinguishable pair on a composite TV; early rounds use k=0..2,
and §7's per-level colour count keeps 7 and 8 colours to the last third of the game.

Other characters: font (32–95, reused from the repo's mini-font approach), wall column, ceiling
bar, death-line rule, HUD frame, launcher deck. Total well under 256.

---

## 5. Sprites

All 16×16, `SPRITE FLICKER` **off**, unused slots parked at **y = 209** (never 208 — 208
terminates the TMS9918 sprite list; repo memory `tms9918-sprite-y-208-terminates`).

| Slot | What | Pattern | Colour |
|------|------|---------|--------|
| 0 | flying bubble — lit cap | 2 patterns/colour, see below | lit shade of k |
| 1 | flying bubble — base body | | base shade of k |
| 2,3 | next bubble (parked in the HUD well) | same pair | shades of next k |
| 4,5 | launcher dragon | fixed | white + green |
| 6,7,8 | aim guide dots | 4×4 dot | white |

A TMS9918 sprite is single-coloured, so the flying bubble is **two overlaid sprites at the same
position**: one carrying the lit upper cap, one the base lower body. That makes the in-flight
bubble pixel-identical to the same bubble once it sticks and becomes characters — the seam that
usually gives away a char/sprite hybrid. Cost: 8 colours × 2 patterns × 32 bytes = 512 bytes of
sprite pattern table (of 2 KB available).

---

## 6. Aiming, with no trigonometry

CVBasic has no `SIN`/`COS` and no floating point. Aim is a **table lookup**, generated offline.

- Aim index `aim` runs **−31 … +31** (63 positions). `am = ABS(aim)` indexes the table;
  the sign selects direction. Straight up is `aim = 0`; the extremes are ±80° from vertical.
- Table `aimtab`: **32 entries × 2 words = 128 bytes**, generated by `assets/genaim.py`:

```
  entry am:  theta = am * 80 / 31   degrees
             dxmag = INT(SPEED * sin(theta) * 256)     ' 8.8 fixed point, always POSITIVE
             dymag = INT(SPEED * cos(theta) * 256)     ' 8.8 fixed point, always POSITIVE
  SPEED = 5.0 px/frame  ->  am=0: (0,1280)   am=8: (451,1198)
                            am=16:(845,961)  am=24:(1129,603)   am=31:(1260,222)
```

- **Both magnitudes are stored positive and direction is a separate flag** (`bdir`: 0 = left,
  1 = right; vertical is always up). This is not a stylistic choice: CVBasic compiles every
  `#var` comparison as **unsigned** (repo memory `cvbasic-unsigned-16bit-compares`), so a signed
  velocity would silently misbehave at every sign test. A wall bounce is `bdir = 1 - bdir`.
- **The aim guide is three dots**, placed at `origin + n*(dx,dy)*8` for n = 1,2,3 using the same
  table — no rotated-arrow artwork, no second table, 3 sprites. (The arcade draws a rotating
  pointer on the launcher; 32 rotation patterns would cost 1 KB of sprite table for no gameplay
  gain. If the dots read poorly in play, that is the fallback.)
- Aim moves 1 index per frame while left/right is held, 2 per frame after ~20 frames of hold.

`aimtab` is read during flight, so it stays in the **fixed ROM area**, never a bank.

---

## 7. The 30 levels

**Encoding.** One nibble per cell, 0 = empty, 1–8 = colour k+1. 8 cells per row = 4 bytes/row,
**11 rows** per level (the deepest arcade opening fill) = **44 bytes/level**, ×30 = **1,320 bytes**.
Odd rows use only columns 0–6; column 7's nibble is always 0 there.

**Shot sequence.** Each level also carries its **fixed 32-entry bubble sequence** (§11), nibble-
packed, 16 bytes/level = 480 bytes total. Levels are puzzles, not slot machines.

Plus a 30-entry metadata table, 2 bytes each (60 bytes):

| Byte | Field | Range |
|---|---|---|
| 0 | colour count in play this round | 3–8 |
| 1 | `droptime` — ceiling-drop period in **quarter-seconds** | 80 (20 s) down to 48 (12 s) |

Per level: 44 B layout + 16 B sequence = 60 B, ×30 = **1,800 B**, plus 60 B metadata.

**Authoring path** (mirrors how RALLY-X handles mazes — `games/RallyX/assets/maze1.txt` +
`transcribe2.py`):

```
assets/levels.txt      30 human-readable ASCII blocks, one char per cell ('.'=empty, '1'..'8')
assets/genlevels.py    levels.txt -> src/levels.bas (DATA BYTE, nibble-packed) + metadata table
assets/prevlevels.py   renders all 30 to a PNG contact sheet, using the real DEFINE CHAR/COLOR
                       data, so layouts are reviewed offline rather than by replaying the game
                       (repo memory: render-level-offline-to-compare-art)
```

**Open decision — where the 30 layouts come from.** Two paths, and this one is yours to pick:
1. **Transcribed** from arcade reference screenshots at the cell grid, the way HARD HAT MACK's
   levels were done (repo memory `transcribe-reference-png-at-cell-grid` — eyeballing was rejected
   twice there; measuring worked first try). Needs 30 reference images dropped in `assets/`.
2. **Original** 30 layouts authored in `levels.txt`, hand-tuned for a difficulty ramp.

The encoding, the generator and the game code are identical either way, so this does not block
starting. Level data is read **once at round start**, never during a frame, so it may live in a
ROM bank if the fixed area gets tight (§13).

---

## 8. The one rendering primitive

`SCREEN` copies a rectangle from CPU memory to the name table, and CVBasic's manual (line 1118)
confirms **the source may be an 8-bit array**, i.e. RAM. That gives one routine that draws the
field, and shake / drop / slide are just different arguments to it.

```
DIM rowbuf(36)              ' 18 chars wide x 2 rows -- one grid row-pair, walls-to-walls

draw_row(r):
    build rowbuf from grid row r:
        clear all 36 bytes to BLANK
        for c = 0 to 7:
            k = grid(r*8+c)
            if k <> 0:
                p  = 2*c + (r AND 1) + 1      ' +1 = the 8 px rest inset (shake slack)
                p  = p + shk                  ' shk = -1 / 0 / +1, the shake phase
                ch = BUBBASE + (k-1)*4
                rowbuf(p)      = ch     : rowbuf(p+1)    = ch+1
                rowbuf(18+p)   = ch+2   : rowbuf(18+p+1) = ch+3
    #dr = CEILROW + top + 2*r
    if #dr <= 22:  SCREEN rowbuf, 0, #dr*32 + WELLCOL, 18, 2, 18
    if #dr  = 23:  SCREEN rowbuf, 0, #dr*32 + WELLCOL, 18, 1, 18     ' clipped, slide only
    ' #dr >= 24 : off screen, skip
```

- **36 bytes of VDP per grid row.** A full field redraw is 12 rows × 36 = **432 bytes**, inside
  the 512-byte single-frame budget, and below the 576 bytes RALLY-X blits in one frame today.
- The blit is always 18 wide and always lands at the same screen column, so cells the field
  *vacated* when it shook are covered by the blanks in `rowbuf`. Nothing needs a separate erase.
- The walls are outside the blit and never move (§3).
- **RAM cost: 36 bytes.** The alternative — a full 18×24 name-table shadow — would be 432 bytes,
  over half of ColecoVision's ~781 free bytes. Building one row-pair at a time and blitting
  immediately costs 36 bytes instead, which is what keeps the Coleco build comfortable (§13).

### The three motions

| Motion | Implementation | Timing |
|---|---|---|
| **Shake** (telegraph before a drop) | `shkb` cycles **LEFT / CENTRE / RIGHT / CENTRE**; full redraw per phase | **1 frame per phase**, 16 phases = 4 cycles ≈ 0.27 s |
| **Ceiling drop** | `top = top + 1`, **fill** the vacated row with brick, full redraw | one redraw + a "clunk" sound |
| **Round-clear slide** | `top = top + 1` repeatedly, clipped at row 23, brick filling in behind | **1 frame per step**, ~27 steps ≈ 0.45 s |

**The walls live in the row buffer.** `rowbuf` is 20 chars × 2 rows; the wall characters sit at
buffer indices `shkb` and `shkb+17`, and the field starts one char inside at `shkb+1`. So walls
and bubbles slide as **one unit**, nothing outside the blit ever needs erasing, and the field can
span the full well — which is what lets bubbles touch the walls. The ceiling is the same 18 chars
wide and shakes with them.

The shake passes through the **centre** each way rather than slamming between extremes, and ends
centred on the frame the ceiling drops.

Cost: a full redraw is now 12 row-pairs × 40 B + the ceiling rows ≈ **500 B per frame** during the
shake. RALLY-X blits 576 B in one frame, so this is inside proven territory, but it is sustained
for 16 frames and is **the first thing to measure on ColecoVision** — a dropped burst here shows
as a torn field, not an error.

That is the whole of §8's payoff: your three motions are one code path with a different loop
around it. None of them touches the pattern table, and none of them is a per-frame cost.

### The game stays playable through the shake

The shake does **not** stop the world. The flying bubble is a sprite, positioned independently of
the field blit, so it keeps moving while the field redraws underneath it; aim and fire stay live.
The drop-timer therefore never has to be paused during play at all (§11) — which removes an entire
category of bug, since a paused-timer design has to get every pause and resume right or it
silently gifts or steals the player's clock.

Two consequences, both deliberate:

- **The shake is render-only. `shk` is excluded from the collision geometry**, which always uses
  the rest position. So the pixel formulas in §2 stay exactly as written for physics, and `shk` is
  added only inside `draw_row`. A bubble in flight is never knocked 8 px sideways by a cosmetic
  shudder, and a shot aimed before the shake lands where it was aimed. The alternative — feeding
  `shk` into the cell centres so collision matches the shaking pixels — is *more* physically honest
  and is the wrong call: 8 px is half a bubble, and no player will perceive an 8 px discrepancy
  during a 0.3 s shudder, but every player will perceive "my shot went in the wrong hole."
- **The drop is not render-only.** `top` is real geometry, so a bubble in flight when the ceiling
  drops genuinely has 8 px less to travel. That is correct — the board actually moved.

**VDP budget is what sets the shake's pace.** A phase is a 432-byte field redraw, and a playable
shake adds ~9 sprite writes on top. At 3 frames per phase that is ~147 bytes/frame sustained,
comparable to RALLY-X's proven 576 bytes per ~5 frames. At 2 frames per phase it would be ~220
bytes/frame sustained, which is past anything measured on either target. **Measure this on
ColecoVision first** — a dropped-write burst here shows up as a torn field, not an error.

---

## 9. Grid, neighbours, and the two flood fills

```
DIM grid(96)        ' 8 columns x 12 rows, 0 = empty, 1..8 = colour k+1
                    ' index = r*8 + c    (DIM in CVBasic is 0..N-1 -- these are 0..95)
                    ' bit 6 = MARK flag, used by both fills; bits 0-3 carry the colour
```

**Hex neighbours** (offset-rows layout; derived, not guessed — a cell at even-row column `c`
sits at x = 16c, and an odd row's column `c'` at x = 8+16c', so 8 px separations are c'=c−1 and
c'=c):

```
same row      : (r, c-1) (r, c+1)
r EVEN (x=16c): (r-1,c-1) (r-1,c) (r+1,c-1) (r+1,c)
r ODD  (x=8+16c): (r-1,c) (r-1,c+1) (r+1,c) (r+1,c+1)
```

Every neighbour index is clamped to `0<=r<=11, 0<=c<=7` **before** it touches `grid()` — a
one-past-end array write is silent on TI but **black-screens ColecoVision** (repo memory
`cvbasic-array-oob-coleco-fatal`).

**Fill 1 — the match group.** Seed = the cell the bubble just stuck to. Mark all connected cells
of the *same colour*. If ≥3 marked, pop them.

**Fill 2 — orphans.** Only runs if fill 1 popped. Mark every occupied cell in the topmost occupied
row (the cells touching the ceiling), then propagate to any adjacent *occupied* cell regardless of
colour. Every occupied cell left unmarked has lost its anchor and drops.

**Both use one routine, and it uses no stack.** A queue would be the fast way, but a worst-case
queue is ~96 bytes and Coleco has ~781 total. Instead: repeat a full scan of the 96 cells, marking
any cell adjacent to a marked one, until a pass changes nothing. Worst case ~12 passes ×
96 cells × 6 neighbours ≈ 7 k checks, once per shot, hidden under the pop animation — budgeted at
≤2 frames. If it measures slower than that, the fallback is a 32-entry explicit stack (32 bytes),
which the RAM budget in §13 can absorb.

**Popped bubbles** get a 3-frame sparkle-erase (pattern swap on their own char codes, not a
name-table rewrite). **Orphaned bubbles** mid-round get the same sparkle. Only the round-clear
case slides the field bodily off the bottom, because only there is the whole field falling —
that is what §8's slide is for, and rendering a mid-round partial drop the same way would be
wrong (the remaining anchored bubbles must not move).

---

## 10. Flight and sticking

Bubble state, all 8.8 fixed point in 16-bit `#vars`, all magnitudes **positive** (§6):

```
#bx #by   bubble centre, well-pixel space x256
#bdx #bdy step magnitudes from aimtab
bdir      0 = moving left, 1 = moving right   (vertical is always up)
```

Per frame while in flight:

```
1. #by = #by - #bdy
2. if bdir = 1 then #bx = #bx + #bdx  else  #bx = #bx - #bdx
3. wall bounce:  if #bx < 8*256   then #bx = 8*256   : bdir = 1 : sfx bounce
                 if #bx > 136*256 then #bx = 136*256 : bdir = 0 : sfx bounce
4. ceiling:      if pixel y <= ceiling+8  -> stick at grid row 0
5. collision:    nearest cell (r,c) from the §2 formulas, then test the 7 candidates
                 (r,c) + its 6 neighbours; for each OCCUPIED one:
                     dx = |bubble x - cell centre x| ; dy = |bubble y - cell centre y|
                     if dx*dx + dy*dy < 196   ->  HIT      (14 px, i.e. r1+r2 minus a little)
6. on HIT: snap to the nearest FREE cell among the same 7 candidates, by |dx|+|dy|
           (Manhattan is sufficient to rank 7 candidates and needs no multiply)
```

**The collision test is on pixels, not cells.** A grid-occupancy test would be wrong here for the
same reason it was wrong in RALLY-X: a 16-px actor on a 16-px grid straddles two cells for its
whole traverse, so a cell test reads clean while things visibly overlap (repo memory
`grid-cell-check-misses-pixel-overlap`, `CLAUDE.md` §3A). The cell index is used only to *find
candidates*; the accept/reject is `dx² + dy² < 14²`.

**No sub-stepping needed.** Maximum speed is 8 px/frame and the hit radius is 14 px, so the bubble
cannot pass through a bubble between two tests. If a later round wants speed > 13, sub-step.

**Nearest-cell rounding** (both are shifts — CVBasic compiles `%` to a real `DIV` even by a power
of two, repo memory `cvbasic-modulo-compiles-to-div`, so there is no modulo anywhere in this game):

```
py = (bubble pixel y) - (CEILROW + top)*8
r  = (py + 8) >> 4                                   ' + 8 rounds to nearest
px = (bubble pixel x) - 8 - 8*(r AND 1)
c  = (px + 8) >> 4
```

---

## 11. Round flow

```
round_start:  load level r from levels.bas -> grid()   (bank-switched read if banked)
              top = 0 : shk = 0 : si = 0 : #dropt = droptime(r)
              draw full field, HUD, launcher ; take current + next from the SEQUENCE
loop (one pass per vblank):
              #dropt = #dropt - 1
              IF #dropt = SHAKELEAD THEN begin shake telegraph (§8)
              IF #dropt = 0 THEN top = top + 1 : clunk : #dropt = droptime(r)
              aim input -> guide dots ; fire
              flight (§10) until stick                        ' timer keeps running
              fill 1 -> pop group if >= 3 -> fill 2 -> drop orphans -> score (§11a)
              IF field empty:  ROUND CLEAR -> §8 slide -> next round
              IF any occupied cell's bottom char row >= DEATHROW: GAME OVER
```

### The ceiling drop is on a **timer**, not a shot count

`#dropt` counts down one per loop pass — and the loop is exactly one pass per vblank (§1), so a
pass is a frame and the timer is real seconds with no calibration needed on either target.

- `droptime` is per level, stored as a byte in **quarter-seconds** (15-frame units): 20 s = 80 at
  round 1, ramping to about 12 s = 48 by round 30. A byte holds up to 63 s, ample.
- **The timer never pauses during play** — not for the shake, not for the drop, not for the pop and
  orphan animations. It stops only on the round-clear slide (the round is already won) and on
  pause. This is possible because the game stays playable throughout the shake (§8), and it is
  worth doing for its own sake: a design that pauses and resumes a clock has to get every
  transition right or it silently gifts or steals time, and that bug is invisible until someone
  notices a round feels long.
- **The shake is the telegraph, and the timer is what makes it meaningful**: at
  `#dropt = SHAKELEAD` (12 frames) the shake starts, so the board is visibly shuddering for the
  0.3 s before it drops. With a shot-count drop the shake could only fire after a shot landed;
  on a timer it can warn at any moment, which is the arcade feel.
- HUD: an 8-character bar in the panel that empties as `#dropt` falls. Redrawn only when a segment
  changes — once per `droptime/8` ≈ 2.5 s, so its cost is nil.
- A secondary 10-second **shot** timer still auto-fires at the current aim, purely so a walked-away
  cabinet still reaches game over.

### The bubble sequence is pre-ordained per level, not random

Your instinct is right, and it is the difference between a puzzle and a slot machine: a fixed
sequence makes a level a *solvable, learnable, replayable* problem, and it is the only way two
players can compare scores on round 12 meaningfully. It also removes the RNG from the one place it
would be most infuriating — being handed a useless colour on the last shot.

- Each level carries a **32-entry sequence**, nibble-packed (16 bytes/level, 480 bytes for all 30).
- The index wraps with `si = (si + 1) AND 31` — a mask, not a modulo (CVBasic compiles `%` to a
  real `DIV`; there is no `%` anywhere in this game).
- **Deterministic substitution, never a dead colour.** If the sequence's next colour is no longer
  present on the field, walk *forward* through the sequence to the first entry whose colour is
  present; if none of the 32 qualify, take the lowest-numbered colour present. Deterministic, so
  the level still replays identically, and it cannot hand out an unusable bubble.
- `NEXT` shows the upcoming entry after the same filter, so the preview never lies.

Danger state (any bubble within 2 rows of the death line): the HUD flashes and the music switches
to its faster variant.

---

## 11a. Scoring, and why the score is not a 16-bit variable

**Every award in this game is a multiple of 10**, so the score is stored in **units of 10** and
displayed with a literal trailing `0`. RALLY-X already uses this trick (`#score is in units of 10`,
`RALLYX.bas:1073`); here it is not a nicety but structural, because the numbers are enormous.

| Event | Points | **Units of 10** |
|---|---|---|
| each bubble in a popped group | 10 | 1 |
| the *i*-th bubble in a drop | 20 × 2^(i−1), i capped at 17 | **2^i** |
| round clear | *nothing extra* — see below | |

The units-of-10 value of the *i*-th dropped bubble is exactly **2^i**. At the documented cap
(i = 17) that is 2^17 = 131,072 units = **1,310,720 points**, which matches the published maximum
for a drop exactly. That is a satisfying check that the units conversion is right.

**No separate round-clear bonus.** Clearing a round means the last shot orphaned everything left,
so the clear *is* a huge drop and the drop table already pays it. Adding a flat bonus on top would
dilute the one skill the game is actually about: setting up the last shot to drop the most bubbles.

### The one thing to verify against a real machine

Two readings of the drop rule are in circulation and they differ by a lot:

| | Rule | 17 bubbles | Can exceed 1,310,720 in one drop? |
|---|---|---|---|
| **(A)** | award is a **total keyed on the count**: 20 × 2^(n−1) | 1,310,720 | no, ever |
| **(B)** | award is the **sum** of per-bubble values, each capped at i = 17 | 2,621,420 | yes |

Reading (A) matches "one dropped bubble scores 20; two score 40; three score 80 … up to 17 or more
which scores 1,310,720." Reading (B) matches "single-shot clears rocket past 1.3 million up to 5+
million points per board." **Build (B)** — it is the larger case, so a representation that survives
it survives (A) too, and switching is a one-line change:

```
' (B) summed, the default:   FOR i = 1 TO ndrop : GOSUB add_drop : NEXT i
' (A) total keyed on count:  i = ndrop : GOSUB add_drop           ' no loop
```

Same table, same add routine, one loop. Resolve it later against a real board; nothing else moves.

### Representation: BCD digits, not a `#var`

A 16-bit `#var` cannot hold this score, and neither can a 16-bit *award*. A single capped
per-bubble award is already 131,072 units — past 65,535 before the score is even touched. The
Twin Galaxies arcade record is **30,331,990** (note the trailing zero), and reading (B) makes a
big board worth several million on its own.

```
DIM sc(8)     ' score,      8 BCD digits, sc(0) most significant .. sc(7) least
DIM hs(8)     ' high score, same
' displayed as the 8 digits followed by a literal "0"  ->  9 shown digits, max 999,999,990
```

- `add_drop` adds a **6-digit BCD constant** read from a 17-entry ROM table (2, 4, 8 … 131072 —
  17 × 6 = **102 bytes**) into `sc()`, right to left with carry. No division, no 32-bit
  arithmetic, no overflow, and the digits are already characters to print.
- A pop of *n* bubbles adds *n* units — the same routine with a one-digit addend.
- **Carry out of the top digit clamps to 999,999,990 rather than rolling.** Rolling to zero on a
  great run is the failure the units-of-10 trick exists to prevent; clamping degrades gracefully.
- Redraw the HUD only from the most significant digit that changed, so a routine 1-unit pop
  rewrites one character, not nine.

---

## 12. Controls & lives

| Action | TI-99/4A | ColecoVision | Notes |
|---|---|---|---|
| Aim left / right | `S` / `D`, or joystick 1 L/R | joystick 1 L/R | 1 index/frame, 2 after ~20 frames held |
| Fire | space / fire | fire button | |
| Pause | `P` | `1` | |

**Lives indicator shows SPARES** — reserves *excluding* the life being played, per the binding repo
convention (`CLAUDE.md` §7A). A fresh 3-life game shows **two** icons; the last life shows none.
Guard the decrement: `IF lives > 0 THEN spare = lives - 1` — these are unsigned 8-bit vars and a
bare `lives - 1` at zero wraps to 255 and lights every icon exactly when the player has none.

`8 3 8` on the title opens the setup screen (repo convention, as in RALLY-X / Astiroids): starting
round and number of bubbles/lives. That screen asks for **total** lives, not spares.

---

## 13. Memory Budget

**RAM** (the binding target is ColecoVision, ~781 bytes free after CVBasic's own use):

| Item | Bytes |
|---|---|
| `grid(96)` — field, colour + mark bit | 96 |
| `rowbuf(36)` — one row-pair blit source | 36 |
| `sc(8)` + `hs(8)` — score and high score, BCD digits (§11a) | 16 |
| scalars: `#bx #by #bdx #bdy`, `#dropt`, aim, top, shk, si, round, lives, sfx state | ~46 |
| flood-fill stack **if** the scan proves too slow (§9 fallback) | +32 |
| **Total** | **~194 (226 worst case)** |

Comfortable on both targets. The single decision that bought this was building the blit source one
row-pair at a time (§8) rather than shadowing the name table (432 bytes).

**ROM.** Start **unbanked** and watch the fixed-area cap of 24,336 bytes with
`games/RallyX/assets/romcheck.py`, which runs on any build. Estimated: levels + sequences 1,860 B
+ aim table 128 B + drop-score BCD table 102 B + char/sprite patterns ~1.3 KB + font/HUD ~0.5 KB
+ music 2–4 KB + code ~8–12 KB.

If the fixed area does get tight, move **levels and music together into one bank** — they are both
read outside the frame loop. Do not move them into separate banks: a thinly-used bank doubled
RALLY-X's cart to 128 KB, and cart size rounds up to a power of two (`CLAUDE.md` §3A). And do not
"optimise" by converting banked data into code — that spends the scarce budget to save the
abundant one, which is exactly the change that silently cut seven bars off RALLY-X's music.

---

## 14. CVBasic hazards that specifically bite this game

Restated from `CLAUDE.md` §3A because each one has a concrete landing site here.

| Hazard | Where it lands |
|---|---|
| **`#var` comparisons are unsigned** | velocity sign. Solved structurally by storing magnitudes + `bdir` (§6). Also every `dx`/`dy` in §10 is an absolute value before comparison. |
| **`<cmp> AND <cmp>` miscompiles on TI** (stale register, 0.9.2 backend) | the collision accept, the neighbour clamps, the death-line test. **Nest single-comparison `IF`s everywhere** — there must not be one compound comparison in this source. |
| **`%` compiles to a real `DIV`** | row parity and cell index. Use `AND 1` and `>> 4` only (§10). No `%` in this game, anywhere. |
| **`DIM a(N)` is 0..N-1**; OOB write black-screens Coleco | `grid(96)`, `rowbuf(36)`. Clamp r and c before every index (§9). |
| **8-bit var × constant > 255 compiles to `CLR`** | `#dr*32` — 32 is safe, but the *product* exceeds 255, so the destination must be a 16-bit `#var`. Check the generated `.a99` for the blit offset arithmetic. |
| **`CONST` > 255 silently becomes ZERO** — ✱ HIT THIS ✱ | The four 8.8 fixed-point positions (launcher `80*256`, `176*256`; wall planes `16*256`, `144*256`) were `CONST`s. Every one compiled to `clr` / `ci r0,0`: the ball launched from 0,0 and neither wall bounced. Written as **bare literals** at each use site they compile correctly. The distinction is CONST vs literal, not the value. |
| **`VPOKE` is a RAW VRAM address; name table is `$1800`** — ✱ HIT THIS ✱ | Every HUD/wall `VPOKE` went to 0..767, which is the **pattern table** — it corrupted the character set. Symptom was junk tiling the whole screen, no walls, garbled digits. `SCREEN`'s target offset *is* name-table-relative, which is why the bubbles were right all along. Add 6144 as its own step. |
| **`DEFINE COLOR` needs 8 bytes per char** — ✱ HIT THIS ✱ | `DEFINE COLOR 32,16,txt_col` reads **128** bytes; supplying 16 made it read 112 bytes of following ROM as colour data, so the text came out in random colours. |
| **`SOUND` takes a 10-bit DIVISOR, smaller = higher** — ✱ HIT THIS ✱ | Four effects were written above 1023 and silently masked (bounce 1400, pop 1800/2400, chime 1200), and both round-transition sweeps were inverted — a "descending" tone written as a decreasing argument rises. The ceiling clunk at 140 was a ~800 Hz *ping*. Nothing errors. |
| **A per-pass counter is not a clock** — ✱ HIT THIS ✱ | Ball movement, the drop timer and the alarm interval all decrement by `fd` now. Anything counted per pass slows exactly when the loop is busy — worst for a warning cue. And once a timer steps by a variable delta, parity logic (`#dropt AND 1`) freezes on an even delta: the shake needed its own phase counter. |
| **Sound latches — needs an explicit note-off** — ✱ HIT THIS ✱ | Effects sustained forever. Each effect is now one tone plus a decay counter ticked after **every** `WAIT`, including inside the round-clear slide and death pause, which don't run the main loop. Two `SOUND`s on one channel cancel; two-note effects use two channels. |
| **A landed sprite must be parked immediately** | `after_stick` runs both flood fills and a full redraw with **no `WAIT`**, so the in-flight sprite sat on top of the character bubble it had just become — a doubled bubble that lingered. `do_stick` hides sprites 0/1 before doing any of that work. |
| **VDP writes are buffered; bursts silently drop** | field redraw is 432 B in one frame — under RALLY-X's proven 576 B, but verify on Coleco specifically, and never issue two full redraws in one frame. |
| **`VPOKE` operands race the ISR on TI** | precompute into plain vars: `#va = expr : ch = expr : VPOKE #va, ch`. Mostly avoided — this game blits rather than pokes. |
| **Sprite y = 208 terminates the sprite list** | park unused sprites at 209. |
| **`SPRITE FLICKER` is all-or-nothing** | leave it off; ≤4 sprites per line by construction (§5). |
| **8-bit `FOR` to 255 loops forever** | n/a, but every loop bound built from a subtraction must be proven non-negative. |
| **No `MODE 2`** | default startup mode + `DEFINE CHAR`/`DEFINE COLOR` (§4). |
| **CVBasic has no local variables** | prefix every scratch temp per routine (`fl_`, `dr_`, `hit_`) and grep the name before adding it. A temp named `#hi` once clobbered a HIGH SCORE every frame. |

---

## 15. Build

```
games/PuzzleBobble/
  DESIGN.md  README.md
  src/PUZBOBL.bas          main source
  src/levels.bas           30 levels, generated -- never hand-edited
  src/aimtab.bas           64-entry aim table, generated
  src/music.bas            original BGM + danger variant
  assets/levels.txt        the 30 layouts, human-readable
  assets/genlevels.py  assets/genaim.py  assets/prevlevels.py
  build-ti.sh              cvbasic --ti994a -> xas99 -> linkticart -> PUZBOBL_8.bin
  build-coleco.sh          cvbasic -> gasm80 -> puzbobl.rom
```

- **Build BOTH targets every time** (repo standing rule, memory `structris-build-both-targets`) —
  not just TI, and not just at the end.
- `#if TI994A` needs the **unhuman/CVBasic** fork; stock nanochess has no preprocessor.
- Delete any stale `PUZBOBL_b*.bin` before assembling — `linkticart` packs every bank file it
  finds and a leftover inflates the page count.
- Finish every session with Classic99 left **running the newest build** (repo standing rule).

---

## 16. Acceptance Criteria

- [ ] Builds clean for **both** TI-99/4A and ColecoVision; TI fixed area under 24,336 B.
- [ ] **Alignment invariant:** at every value of `top` and `shk`, every bubble's top-left corner
      lies on a character boundary. Verified by an offline render (`prevlevels.py`) at
      `top = 0..3` × `shk = -1,0,+1`, not by eye in the emulator.
- [ ] Ceiling drop moves the field **exactly 8 px (one character row)**, and the field looks
      identical before and after apart from the translation — no pattern rebuild, no flicker.
- [ ] Shake is visibly left-right, ~0.3 s, and always immediately precedes a drop.
- [ ] **The game is fully playable through the shake** — a bubble in flight keeps moving, aim and
      fire stay live, and a shot fired just before a shake lands in the same cell it would have
      without the shake (shake is render-only, §8).
- [ ] The shake does not tear the field on ColecoVision at 3 frames per phase (the VDP-burst
      limit is the pacing constraint here, not the CPU).
- [ ] Round clear: last group pops, orphans lose their anchor, and the remaining field slides
      down and off the bottom edge before the next round loads.
- [ ] Ceiling drop fires on the **timer**, not a shot count: standing still with the launcher idle
      still drops the ceiling on schedule, and the timer bar matches a stopwatch.
- [ ] The timer runs continuously through the shake, the drop and every animation — it stops only
      on the round-clear slide and on pause.
- [ ] **Determinism:** playing round 1 twice with identical inputs produces an identical bubble
      sequence and an identical final score. No `RANDOM` anywhere in the shot path.
- [ ] The `NEXT` preview always matches the bubble actually loaded, including after the
      absent-colour substitution.
- [ ] **Scoring:** a 3-bubble pop pays 30. A drop of exactly 17 bubbles pays 1,310,720 under
      reading (A) / 2,621,420 under reading (B) — whichever is built, verified against a
      hand-computed value.
- [ ] Score displays 9 digits with a fixed trailing `0`, and **clamps** at 999,999,990 instead of
      rolling to zero (force it with a debug award).
- [ ] Bank shots off both walls land where the guide dots predict.
- [ ] A bubble never visually overlaps another bubble or a wall — asserted on **pixels**
      (`|dx| < 16` and `|dy| < 16` between any two placed bubbles), never on cell indices.
- [ ] Three-of-a-colour pops; a group of two does not; orphans always fall.
- [ ] The next-bubble colour is always a colour still present on the field.
- [ ] Lives indicator shows **spares** — 3 lives shows 2 icons, last life shows 0, no 255-icon
      underflow at game over.
- [ ] All 30 rounds reachable and completable via the `8 3 8` starting-round selector.
- [ ] Loop holds one pass per vblank during flight on **real-hardware-speed** settings, measured
      against a host clock (`games/RallyX/DESIGN.md` §1a method), not judged from emulator feel.
- [ ] ColecoVision RAM headroom verified — no black screen after extended play (the Coleco
      signature for an array overrun).

---

## 17. Status

**2026-08-15 (build 5) — pacing, audio and HUD.** All from play-testing:
- **Everything that moves is paced by elapsed frames** (`fd = FRAME - #lf`, clamped 4), not loop
  passes. A shake phase is a full redraw, so passes were overrunning the frame and the ball
  visibly slowed whenever the board shook. Sub-stepping is safe here — a step is a move plus one
  ~9-cell test, trivial beside a redraw.
- **The drop telegraph is now audio-led**: a two-tone alarm 80 frames ahead, then a single
  right-and-back nudge at 20 frames. The shake was the expensive part of the warning and is now
  the decorative part of it.
- **The shake is driven by a phase counter, not `#dropt AND 1`.** Once `#dropt` decremented by a
  variable delta, an even delta froze the parity and the board would have stopped wiggling.
- **Sound values were wrong in two ways** (§14) — the argument is a 10-bit divisor where smaller
  is higher, so four effects were masked past 1023 and both sweeps were inverted.
- **HUD left-justified on column 22**, aligning labels with the score digits beneath them; round
  number and NEXT bubble centred on px 192.
- Round-clear close ~0.23 s with a descending sweep; reveal ~0.4 s with a rising one.
- Level 2 is temporarily a copy of level 1 so the close/reveal can be watched end to end.

**2026-08-15 (build 3) — presentation pass.** From play-testing feedback:
- **Walls moved into the row buffer**, so the field spans the full well and **bubbles touch the
  walls**; the walls and ceiling shake with the field as one unit (§8). Wall planes are now the
  edge-column centres (24 and 136).
- **Shake is 1 frame per phase** and cycles LEFT / CENTRE / RIGHT / CENTRE, passing through the
  rest position instead of slamming between extremes.
- **The descending ceiling fills in with brick** instead of leaving a blank gap, and the ceiling
  is the same width as the walls (it used to overhang by a char each side). Bricks are grey.
- **Sprites update at the top of the loop, right at vblank.** Updating them after the collision
  work let the retrace land between the body and cap writes, so the in-flight ball did not match
  the loaded and landed ones.
- **HUD right-justified** to column 30, one column of space at the edge; NEXT label sits directly
  above its bubble.
- **Round-clear slide is 3× faster** (1 frame per step, ~0.45 s).

TI fixed area now **14,380 B of 24,336 — 9,956 free**.

**2026-08-15 (later) — playable on TI-99/4A.** Round 1 renders and plays: aim, fire, wall
bounces, sticking, match-3 pops, orphan drops, scoring, the drop timer, the shake and the
round-clear slide are all in `src/PUZBOBL.bas`. Both targets build from the one source.

- **TI fixed area: 13,916 B of 24,336 — 10,420 free.** `assets/romcheck.py` runs inside
  `build-ti.sh` every build. Note the raw `.bin` starts at `>6000`, so its total size is *not* the
  number to compare (getting that wrong reads as a 5,964-byte overflow on a build with 10 KB free).
- **ColecoVision RAM: 354 B of 814.** Comfortable, as §13 predicted.
- Four bugs found by running it, all now in §14 marked ✱ HIT THIS ✱ — `CONST` > 255 becoming zero,
  `VPOKE` writing to the pattern table, `DEFINE COLOR` under-sized data, and latched sound.

Not yet built: title screen, `8 3 8` setup, music, the danger state, lives/spares HUD, and the
pop/orphan sparkle (bubbles currently vanish without an animation).

**2026-08-15 — design + level 1 + the asset pipeline.**

Done:
- `assets/levels.txt` — the authoring format, with **level 1** defined (24 bubbles, 3 colours,
  symmetric, blue core under a green shell so the player's first drop is a visible one).
- `assets/genlevels.py` → `src/levels.bas`: 1,320 B layouts + 480 B sequences + 60 B metadata =
  **1,860 B** for all 30 rounds. Undefined rounds emit as placeholders so the table is always 30
  entries and the game's indexing never depends on how many are authored.
- `assets/prevlevels.py` → `level-01.png` (full screen mock) and `alignment.png`.
- **The alignment invariant is now checked, not asserted.** `prevlevels.py` renders the field at
  `top = 0..3` × `shk = −1/0/+1` with the 8×8 character lattice overlaid, *and* verifies it
  numerically over `top = 0..5`: **0 violations**. That is the claim §2 rests on, and it now has
  a test rather than an argument.

Open:
- **§7** — whether the 30 layouts are transcribed from arcade reference shots or authored fresh.
  Level 1 is provisional either way; layouts are data, so replacing it changes no code.
- **§11a** — reading (A) vs (B) of the drop-scoring rule. Build (B); one line switches it.
- **Bubble art**: the preview draws a fairly round 16×16 sphere, which leaves small diamond gaps
  between diagonal neighbours (they sit 17.9 px apart, §2). Squaring the profile off slightly
  closes them. Decide when the real `DEFINE CHAR` data is authored — `INSET` in `prevlevels.py`
  is the knob, and the preview is the fastest way to judge it.
