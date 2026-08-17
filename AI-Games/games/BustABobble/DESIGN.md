# BUST-A-BOBBLE — Design

> CVBasic game, **dual-target**: TI-99/4A (native TMS9900 cartridge ROM, `--ti994a`) **and**
> ColecoVision (native Z80 ROM, CVBasic default target) from the same `src/BUSTABOB.bas` —
> not an XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic
> hazard list (`CLAUDE.md` §3A, restated as §14 here) is binding. Sibling CVBasic projects:
> `games/RallyX`, `games/Structris`, `games/HardHatMack`, `games/Astiroids`.

This document describes the game to be built. Once code exists, `src/BUSTABOB.bas` is the source
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
        |   the field spans the FULL well, so bubbles    |  row 6-7  : "ROUND" + number
        |   touch the walls; the walls live in the same  |  row 10-11: "NEXT" + next-bubble well
        |   row buffer and shake WITH the field, so the  |  row 15   : "TIME"
        |   whole assembly slides as one unit (§8) and   |  row 16   : drop-timer gauge, 8 chars
        |   nothing outside the blit needs erasing       |  row 18   : lives / spares (§12)
        |                                                |  row 20-22: BUB (mascot, decor) - unbuilt
row 0  : CEILING BAR (solid, full well width)
rows 1-19: play area  (grid row r occupies char rows 1+top+2r and 1+top+2r+1)
row 20 : DEATH LINE (dashed rule). A bubble whose bottom reaches row 20 ends the game.
rows 21-23: launcher deck — dragon sprite, loaded bubble, aim guide dots
```

> **The diagram above is current as of the timer/lives build.** It previously still described the
> pre-build-3 geometry ("at rest the field is inset 8 px each side… the walls themselves never
> redraw"), which the revision notes above it had already reversed, and it placed `TIME` on row 13
> and lives on row 23. Both were wrong in the shipped ROM. Corrected rather than annotated, so §3
> reads as one description instead of a stale picture with fixes stacked on top.

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

**Bubble stamp:** 8 colours × 4 quadrant chars = **32 chars**, codes 128–159, loaded by a single
`DEFINE CHAR 128,32,bub_pat`.

```
colour k occupies codes 128+4k .. 131+4k
    +0 top-left    +1 top-right
    +2 bottom-left +3 bottom-right
```

### One hue per ball, shaded by dither — and why it had to become that

**Every bubble is a single colour, dithered.** This started as *two-tone* shading (a lit shade over
a base shade, solid sphere) and that turned out to be a **gameplay** bug, not a style choice:

> A two-tone ball is identified by a **pair** of colours, and this palette does not contain eight
> well-separated pairs. Red was medium-red over light-red and "orange" was dark-red over the *same*
> light-red — one shade apart in the body, identical on top. In play they were the same ball.
> Four touching "reds" refused to pop; sampling the pixels showed two of them were the other
> colour. **The match logic was correct the whole time** (verified against a reference hex flood
> fill over 4,000 random fields — zero mismatches); the palette was lying to the player.

One hue per ball removes the failure mode by construction: there is nothing left to confuse but the
hue itself. The eight are **one per hue family the TMS9918 offers**, in their brightest variant,
because dithering darkens. There is no orange on this hardware — dark red was only ever standing in
for it, and that substitution is what caused the bug.

**Shading comes from pixel density instead.** Solid at the top, then checks against black that thin
out going down, with the **outline always solid** so a sparse ball still reads as a circle rather
than a cloud. On a display that allows two colours per line, density is the *only* way to get a
gradient out of one colour.

**Density is per colour, and it is the tool for separating close colours.** More lit pixels reads
brighter. White and grey are only 51 levels apart per channel (255 vs 204) and at equal density
they read as the same ball, so white runs **light** and grey runs **heavy**:

| k | Bubble | TMS | density | lit px | apparent |
|---|--------|-----|---------|--------|----------|
| 1 | red     | 9 light red    | normal | 132 | 83 |
| 2 | green   | 3 light green  | normal | 132 | 88 |
| 3 | blue    | 5 light blue   | normal | 132 | 70 |
| 4 | yellow  | 11 light yellow| normal | 132 | 105 |
| 5 | cyan    | 7 cyan         | normal | 132 | 96 |
| 6 | magenta | 13 magenta     | normal | 132 | 70 |
| 7 | grey    | 14 grey        | **heavy** | 88 | 70 |
| 8 | white   | 15 white       | **light** | 191 | 190 |

White ends up **2.2× denser** than grey — far more separation than their hues could ever give.
Ramps live in `DITHER` in `genart.py`: a list of `(up_to_row, modulus)`, where a pixel survives when
`(x + y) % modulus == 0`, so modulus 1 is solid, 2 half, 4 a quarter.

Background for every bubble line is **1 (black)** — the well interior colour. No cell ever contains
two different bubbles (bubbles are 2 chars wide on a 2-char pitch and always char-aligned, §2), so
there is no seam case to handle.

`assets/prevcolours.py` renders all eight side by side with their pixel counts — the pair a level
rarely shows together is impossible to judge from a level render.

Other characters: font (32–95), wall/brick (160), death-line dash (161), pop-burst frames
(164–175, §9). Total well under 256.

Other characters: font (32–95, reused from the repo's mini-font approach), wall column, ceiling
bar, death-line rule, HUD frame, launcher deck. Total well under 256.

---

## 5. Sprites

All 16×16, `SPRITE FLICKER` **off**, unused slots parked at **y = 209** (never 208 — 208
terminates the TMS9918 sprite list; repo memory `tms9918-sprite-y-208-terminates`).

**Three patterns per colour**, so 24 in all plus the guide dot: `3k` = colour *k+1*'s **cap**,
`3k+1` its **body**, `3k+2` the **full** ball. Frame numbers are `def × 4`, so colour *k* uses
`(k−1)×12` for the cap, `+4` for the body, `+8` for the full; the dot is pattern 24, frame 96.

| Slot | What | Pattern | Colour |
|------|------|---------|--------|
| 0 | flying bubble — base body | `(k−1)×12 + 4` | base shade of k |
| 1 | flying bubble — lit cap | `(k−1)×12` | lit shade of k |
| 2,3 | next bubble (parked under NEXT in the HUD) | same pair | shades of next k |
| 4,5,6 | aim guide dots | 96 | white |
| 8…19 | **falling orphans** (§9), one sprite each | `(k−1)×12 + 8` (full) | base shade of that bubble |

A TMS9918 sprite is single-coloured, so the flying bubble is **two overlaid sprites at the same
position**: lit upper cap over base lower body. That makes the in-flight bubble pixel-identical to
the same bubble once it sticks and becomes characters — the seam that usually gives away a
char/sprite hybrid. The cap/body split has to be **per colour** because `litrows` is (§4): a shared
pair would split at the wrong row and the match would break the instant the ball landed.

The **full** pattern exists for falling debris. Drawing debris with the *body* pattern — which by
definition starts below the highlight — made the falling bubbles look like bottom halves. Full also
keeps each falling bubble at **one** sprite rather than two, which halves the slots used and keeps
them off each other's scanlines (only four sprites show per line).

Cost: 25 patterns × 32 bytes = **800 bytes** of the 2 KB sprite pattern table.

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

**RESOLVED (2026-08-15): all 30 are transcribed.** The Puzzle Bobble / Bust-A-Move FAQ v1.24
(neo-geo.com wiki) draws every round on the same 8/7 staggered grid the hardware uses, so the
transcription is cell-for-cell rather than by eye — the method repo memory
`transcribe-reference-png-at-cell-grid` insists on. Pipeline:

```
assets/arcade-stages.txt        the 30 shapes, transcribed, with per-round colour counts
assets/transcribe_stages.py     assigns concrete colours -> levels.txt
assets/genlevels.py             levels.txt -> src/levels.bas
```

**What is authentic and what is not.** The FAQ's legend defines `a`–`d` as colours that matter
strategically, `X` as an attack-spot hint, and **`O` as "ball of any colour"**. So the source pins
down *shape* completely and *colour* only where it mattered to the strategy it was describing:

- **Authentic:** every round's shape — which cells hold a bubble — and its colour count.
- **Assigned:** the colour of every `O`/`X`. `transcribe_stages.py` gives them
  `((c >> 1) + r) mod N + 1`, i.e. horizontal **pairs** of a colour shifting one step per row.
  Pairs matter: a lone bubble needs two more of its colour to pop, so a field of noise plays badly
  while banded pairs mean most shots have a target. Letters keep their identity, so cells the
  source marked as the same colour stay the same colour.

### ✱ OPEN: the colour assignment builds too many pre-made groups

Measured across the 30 rounds: **85 pre-existing connected groups of 3+**, and round 1 starts with
**90% of its bubbles already sitting in one**. Round 8 is 80%; round 9 contains a group of ten.

A pre-made group looks poppable and is not — match detection only runs when a bubble *sticks*, so a
group that was already there just sits. That is correct Puzzle Bobble behaviour and the arcade does
it too (round 1's own `aabbccdd` over `aabbccd` stacks each colour into a 4-group). But at this
density it reads as the game being broken, and it cost a play-test session chasing a match bug that
did not exist.

The cause is the banding rule above. Same-colour **pairs are exactly what you want** — a pair gives
a shot somewhere useful to land, and completing it pops. **Triples are the problem.** Horizontal
pairs shifting one row per step do not just make pairs; they stack into 3s and 4s.

**Fix, not yet applied:** colour the `O` cells one at a time and reject any colour that would join
**two or more** already-placed same-coloured neighbours. That keeps pairs everywhere and stops
groups forming. Leave cells the source marked `a`–`d` alone — those pre-made groups are the
arcade's own. Pure change to `transcribe_stages.py`; no game code moves.

Re-colouring a round from a screenshot means editing one file and regenerating; no code moves.
Level data is read **once at round start**, never during a frame, so it may live in a ROM bank if
the fixed area gets tight (§13) — it does not currently need to.

### 7a. Every round is proven winnable — `assets/solvelevels.py`

A round here can be impossible in a way a random-bubble game never can. The shot sequence is
**fixed** (§11), so the player cannot wait for the colour they need: if a round's 32 shots and its
layout cannot be made to clear, no amount of skill fixes it, and **nothing else in the build would
notice**. The colours are assigned by a script (above), so this is not a theoretical risk — it is
the exact thing that assignment could break.

`assets/solvelevels.py` re-implements the game and searches each round for a clearing line.

**It plays the round as shipped, not a tidy model of it.** It reads `src/levels.bas` and
`src/art.bas` — the `DATA BYTE` blocks that go in the cartridge, so the packer is validated too —
and re-implements the source's own rules, quirks included:

- the 8.8 fixed-point flight at 5 px/frame, wall planes at 6144 / 34816, unsigned compares
- `coltest`'s 3×3 candidate scan with the **pixel** accept `dx² + dy² < 196`
- `do_snap`'s nearest-free-cell-by-Manhattan, ties broken by scan order
- the ceiling shortcut — `bpy <= top*8+16` sticks in row 0 via `snap_col` and **overwrites**
  whatever is there, because that is what the source does
- `pick_next`'s forward walk with substitution over still-present colours
- the drop clock in frames, drops landing **mid-flight**, and `check_death`'s `top + 2r >= 18`

**Time is charged against the round, generously.** Real play gets the pop and orphan animations
free — the main loop is not running during them, so `#dropt` never ticks, and the catch-up
afterwards is clamped to 4 frames (`#fd`). The checker charges the full 4 every shot *and* every
aiming frame, since the launcher turns one step per frame.

**Result: all 30 rounds are winnable, none by more than a fraction of the time available.**
28 of 30 clear before the ceiling drops even once; rounds 3, 5 and 30 take one drop. **No winning
line anywhere uses the ceiling-overwrite quirk**, so nothing here rests on it.

The margin was then stress-tested by charging the player extra dead frames per shot:

| Dithering charged per shot | Rounds proven winnable |
|---|---|
| 0 (fires the instant it can) | 30 / 30 |
| 1 s | 30 / 30, ≤ 4 ceiling drops |
| 2 s, 4 s, 8 s | **29 / 30** — only round 30 fails, and identically at all three |

So the verdict does not depend on the timing model at all: it survives an eight-second-per-shot
player. Round 30 having the only real margin is the one place the difficulty ramp is doing its job
(§11b), and the failure is the *drop timer*, not the layout — the checker reports which, by
re-running with the clock off.

**Checked against the real machine, not just against itself.** A faithful-looking simulator that
quietly disagrees with the cartridge would prove nothing, so its predictions were compared with
Classic99 running the built ROM:

| Prediction | On hardware |
|---|---|
| round 1 opens holding colour 3, NEXT shows 3 | NEXT is blue ✓ |
| straight up (aim 31) → grid (4,3), char cell r9 c8 | blue lands char r9 c8 ✓ |
| after that shot, NEXT becomes colour 4 | NEXT is yellow ✓ |
| full left (aim 0 — 80° off vertical, zigzagging off **both** walls the whole way up) → grid (5,2), one cell **left** of where a straight shot goes | lands char col 7, not col 9 ✓ |

The last row is the one that matters: aim 0 and aim 31 land in the same cell on an empty round 1,
so the test was repeated from a board where they differ. A wrong wall plane or a bounce that failed
to flip direction would have put that ball against a wall, not one cell over.

**Honest about its limits.** Finding a line *proves* a round winnable. Failing to find one does
not prove the opposite — the search is a beam search, not exhaustive — so failures are reported as
`UNPROVEN`, re-run four times wider, and then re-run with the clock disabled to say whether the
obstacle is the timer or the layout/colours.

**It cannot go stale silently.** The checker hard-codes the game's constants, so `check_source_drift()`
re-reads `BUSTABOB.bas` on every run and aborts if `HITD2`, `LAUNCHX/Y`, `DEATHROW`, `CEILROW`, the
two wall-plane literals, the `* 15` quarter-seconds conversion, or the `#fd` clamp have moved.
Without that it would happily keep validating a game that no longer exists.

```
python3 assets/solvelevels.py                    all 30, exit 1 if any is unproven
python3 assets/solvelevels.py --level 1 --replay one winning line, shot by shot, with boards
python3 assets/solvelevels.py --probe 1          where all 63 aims land the round's first shot
python3 assets/solvelevels.py --overhead 120     stress the drop clock
python3 assets/solvelevels.py --report           WALKTHROUGH.md + walkthrough.json for all 30
python3 assets/walkthroughhtml.py                walkthrough.json -> a shareable HTML round book
```

### The walkthrough falls out of the proof

`--report` writes the lines the solver found as a readable document: each round's opening board,
its fixed shot sequence, and a table of every shot — ball colour, **aim as a step count off
vertical** with the wall banks called out, the cell it lands in, what it pops or drops, and how many
bubbles are left. Because the aim is what the player physically holds the stick to reach, that is
the number the table gives (63 positions, 31 either side, one step ≈ 2.6°, and it **persists between
shots**, so the counts are absolute).

`walkthroughhtml.py` turns the same JSON into a self-contained page that draws the boards in the
game's real colours at the real hex stagger, every round to the same depth with the death line
marked so headroom is comparable round to round.

**Report lines are chosen for brevity, which the proof does not care about.** A win is a win at any
length, but a 45-shot line is a bad walkthrough, so `--report` runs a **ladder of beam widths and
keeps the shortest**. That is not cosmetic: a wider beam is *not* reliably better here — it explores
a different region — so round 3 came out at 45 shots at beam 48, **73** at beam 150 and 37 at beam
400, and round 5 went 41 → 17. Taking the best of a ladder got round 3 to 28.

Run it after **any** change to `levels.txt`, `transcribe_stages.py`, the aim table, or the
collision constants — those are exactly the edits that can make a round unwinnable without
producing a single visible symptom.

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

### The two animations

**Popped bubbles burst.** Three dissolve frames — the sphere solid, then holed on a checker, then
sparse specks — flashing white, yellow, grey. Chars 164–175, **one set shared by all colours**: a
pop is a bright flash and reads fine without carrying the bubble's hue, which would otherwise cost
eight times the characters. Painted with VPOKEs over **only the marked cells**, so it is a handful
of writes rather than a field redraw. Two frames each, ~0.1 s.

**Orphans fall away as SPRITES**, one per bubble, using the full-ball pattern (§5), at slightly
different speeds (`6 + (i AND 3)` px/frame) so a row of them spreads out instead of sliding as a
slab — which also keeps them off each other's scanlines. They run to ~0.45 s and are hidden at
y = 209 when they pass the bottom.

Sprites are what make this affordable: **one `SPRITE` call each per frame with the VDP erasing for
us, against 8 VPOKEs each** for the character equivalent, which is far past what a frame carries.
Capped at **12** animated orphans (12 slots, 8…19); a larger drop still *scores* in full, it simply
does not animate every bubble.

The field is redrawn **without** the orphans before the fall starts, so they drop over a clean
board. That is also why this can't reuse §8's slide: there the whole field moves, here the
remaining anchored bubbles must stay exactly where they are.

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

### Title screen

Boot goes to a title: all eight bubble colours on two decorative rows, the game name, the credit
line, and **last score + high score across the top row** (same trailing-zero convention as the HUD,
§11a). Fire starts a game, and a **release is required first** so a button still held from the
previous game cannot skip through. Typing **8 3 8** opens a round selector — two digits, 01–30,
echoed as typed — the same secret the other games in this repo use, and likewise not advertised on
screen. The chosen round lasts **one game**; returning to the title always resets to round 1.

**Two of the creature pace either side of the name**, at 2×, as 16×16 sprites (patterns 25–26, two
walk frames). Three things make it cheap and keep it honest:

- **One shape, two sizes.** `genart.py` emits the 8×8 HUD life icon *and* the 16×16 walking pair from
  a single 8-byte definition, the big one being the small one with every pixel doubled. The guy
  counting your spare lives and the guy on the title cannot drift apart, because there is only one
  of him. (Repo rule: scale art, never redraw it at a new size.)
- **One variable drives both.** The right-hand creature is mirrored, so they walk toward each other
  and back together. It is mirrored about the **text** centre (px 123.5, `231 - twx`), not the screen
  centre (128) — mirroring about the screen left clearances of 2 px and 11 px, which read as
  lopsided.
- **The patrol is bounded by the creature's RIGHT edge, not its left.** It is 16 px wide, so stopping
  `twx` at 51 keeps that edge at 67, clear of the "B" at px 72. Bounding the left edge instead had it
  walking across the first letter — visible immediately on screen, invisible in the arithmetic.

Only the legs differ between the two frames, so the cycle reads as walking rather than the whole
creature twitching.

Game over (lives exhausted) and clearing round 30 both return to the title. The high score
survives; the score does not. Both messages blank a one-character border before printing so they
read as a box over the bubble field.

### The ceiling drop is on a **timer**, not a shot count

> **What the arcade actually does — and it is not this.** The Puzzle Bobble FAQ v1.24 is explicit:
> *"the screen drops after a certain number of bubbles ("b") have been fired from the launcher"* —
> shots, not time. And the genuinely clever part: *"For each missing color, the screen drops every
> b − missing colors bubbles."* **The ceiling accelerates as you eliminate colours.** That is a
> self-balancing difficulty ramp — the closer you get to clearing a round, the harder it presses —
> and it is why the arcade stays tense on a nearly-empty board. There is also a fallback so a
> stalled game still progresses, and the warning is carried by the **music tempo**, which rises as
> the bubbles near the line, rather than by an alarm tone.
>
> This build uses a timer by explicit direction. The gap is worth knowing about because it bears
> directly on the difficulty problem in §11b: the arcade's colour-count rule solves the very thing
> a flat timer ramp cannot.

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
  > **This was aspirational until 2026-08-16 and the code did not do it.** The burst (6 frames) and
  > the orphan fall (27) run their own `WAIT` loops with the main loop stopped, so `#dropt` stood
  > still for both — better than half a second of free time on every popping shot, which is most of
  > them, handed over precisely when the player did something *good*. `anim_tick` now runs the
  > countdown and the gauge inside those loops. The **drop itself** is still deferred to the next
  > main-loop pass rather than fired from inside an animation: it would move the field out from
  > under a burst that is painted at fixed cells. Deferred by at most the rest of the animation,
  > never lost. Exactly the "silently gifts time" failure this bullet warned about, in the game the
  > bullet is describing.
- **The shake is the telegraph, and the timer is what makes it meaningful**: at
  `#dropt = SHAKELEAD` (12 frames) the shake starts, so the board is visibly shuddering for the
  0.3 s before it drops. With a shot-count drop the shake could only fire after a shot landed;
  on a timer it can warn at any moment, which is the arcade feel.
- HUD: an 8-character bar in the panel that empties as `#dropt` falls. Redrawn only when a segment
  changes — once per `droptime/8` ≈ 2.5 s, so its cost is nil.
- A secondary 10-second **shot** timer still auto-fires at the current aim, purely so a walked-away
  cabinet still reaches game over.

### Orphans fall RELATIVE to the shot, not by a global ceiling check

Puzzle Bobble's rule is that anything losing its connection to the ceiling falls, and the obvious
implementation is a global "not reachable from row 0" check after each pop. That is what this game
did, and it is wrong in one specific way: it also drops bubbles that were **already** detached
before the shot and had nothing to do with it.

Four of the transcribed arcade layouts contain detached pieces — rounds 9 (33% loose), **10 (90%)**,
15 (44%) and 20 (38%) — because the FAQ's ASCII diagrams do not preserve hex adjacency at the row
ends (§7a). On round 10 the entire cage is detached, so the first pop *anywhere* collapsed nineteen
bubbles at once, most of which never touched the popped group. It reads as the match logic being
broken, and it was reported as exactly that.

**The rule is now relative to the shot: a bubble falls only if it *was* hanging from the ceiling and
is not any more.** Implemented as grid bit 5, recomputed each shot by `save_anchors` before the
match fill; `drop_orphans` then requires bit 5 as well as "no longer reachable".

On a well-formed field the two rules are **identical** — a group loses the ceiling only if the
popped group was its last link — so the other 26 rounds are unaffected. Pre-detached scenery now
sits there and has to be cleared by matching it, which is why round 10 went from an 8-shot,
2.6-million-point collapse to a 43-shot grind. That is the honest cost of the layout; the levels
themselves are still malformed and fixing *them* is tracked separately in §7a.

### The drop-timer gauge and the lives creatures (built 2026-08-16)

**What the arcade actually does — researched, because the gauge is an invention.** The
Puzzle Bobble/Bust-A-Move FAQ v1.24 (the same source the layouts came from) is explicit that the
ceiling is driven by **shots, not time**, and that the count tightens as colours are eliminated:

> "If all eight colors are on the playfield, the screen drops after a certain number of bubbles
> ('b') have been fired from the launcher."
> "For each missing color, the screen drops every b−missing colors bubbles."
> "Also, after a certain amount of bubbles have been fired the level will drop anyway."

And the arcade shows **no gauge, bar or counter at all**. Its two cues are the playfield
**juddering** just before a drop, and the **music tempo rising** as the stack nears the death
line — note the second is a *danger* cue about the death line, not a drop countdown.

So this game already deviates twice, both deliberately: the drop is on a **timer** (§11), and it
gets a **visible gauge**. The justification for the gauge is that the timer deviation created a
problem the arcade does not have — a shot count is something the player can *see themselves*
by counting their own shots, whereas a wall clock is invisible, and the only cue was an alarm
1.3 s out. Without a gauge the pacing mechanic is unreadable.

**How it is drawn.** Eight characters on row 16, under the "TIME" label. Nine character shapes
give fill widths 0–8 px, so the gauge drains in **64 steps** rather than eight chunky ones. The
unfilled pixels are left clear and show the character's *background* colour, which is the grey
track — fill and track out of one character instead of two. Per-scan-line colour makes lines 0 and
7 black-on-black so the bar reads as 6 px tall inside an 8 px cell. It is redrawn only when the
pixel count changes (≤64 times per cycle, 8 `VPOKE`s each), not every frame.

The fill turns **red for the last quarter** of the gauge — 5 s at round 1, 3 s at round 30. Keying
it to the alarm instead put the colour change 1.3 s out, when only ~4 of 64 pixels were still lit:
there was no bar left to be red.

**The death line is YELLOW, and flashes RED when a bubble crosses it.** The 1.5 s pause in `do_dead`
was a tone over a frozen board with nothing to say *why* the round ended. The line now flashes for
that whole 1.5 s (90 frames, toggling every 8 — just under 4 flashes a second). One character's
colour alternates: `DEFINE COLOR 161,1,dash_colf`, 8 bytes a flip. `dash_col` is a label *inside*
`wall_col` rather than a copy, so `DEFINE COLOR 160,2,wall_col` still reads straight through both
characters.

Yellow at rest matters as much as red on death: the line was *dark red* at rest, which already read
as alarming and left the alarm state nowhere to go. Yellow → red says the line changed meaning — from
a boundary you are approaching to the rule you just broke — without a word of text.

**The line is drawn THROUGH the bubbles sitting on it.** A bubble on the death-line row hides the
line behind it, and by the time you are dying that is most of the line — so the flash the player is
meant to read is exactly the part covered up. Chars **186–217** are the eight bubbles again, each
carrying the line through its own middle: scan lines 2 and 5 cleared to black (a 1px spacer either
side) and 3–4 holding the line. `draw_row` selects them when the row-pair's top or bottom character
row *is* `DEATHROW` — which pair depends on the ceiling's parity, so all four quadrants have variants
and only one pair is ever used at a time.

Two details that make it work:
- The **colour is per scan line**, so lines 3–4 take the line colour and the rest stays the bubble's.
  That is what makes the flash a single `DEFINE COLOR 186,32,…` instead of a second set of patterns.
- Scan lines 3–4 carry the **dash pattern itself** (`$3C`), not the ball's pixels and not a solid bar.
  Two earlier versions were wrong: the ball's own dithered pixels made grey's line a row of stray
  dots (at that density only every eighth pixel is lit), and a solid bar read as a *different* line
  from the dashed one either side of the bubble. Using the dash keeps one continuous dashed line
  across the whole well — and it lands in phase for free, because bubbles are character-aligned (§2)
  and the dash is per character, so the dashes inside a bubble cannot drift against those outside it.
  Both mistakes were caught by rendering all eight colours offline from `art.bas` before running.

The line stays **geometrically straight** across the screen rather than being centred in each ball:
it is a real screen row, and bending it around the bubbles would read as a broken line, not a
crossed one.

> Built first as a flash of the **bubbles**, which was wrong twice over. It draws the eye to the
> wrong thing — the line is the rule that was broken, so the line is what should be lit — and
> recolouring all 32 bubble characters white leaves the ones that were *already* white or grey
> visibly unchanged, so it read as "some of the balls blink, not even all". The lesson is the
> second half: a flash implemented by forcing one colour is invisible on anything already near
> that colour, which on this palette is two of the eight.

**Lives are a little green creature, not a bubble.** The field is *made* of bubbles, so a bubble in
the HUD reads as ammunition. The creature's eyes are unlit pixels — a character is one colour per
scan line, so holes are the only way to draw a face at 8×8. It shows **spares** per `CLAUDE.md` §7A
(3 lives → 2 creatures), with the unsigned-underflow guard, and sits on **row 18**: the design said
row 23, which is the last row on the screen, in TV overscan on real hardware and clipped entirely
in Classic99 — the one element telling you how much game is left was the one you could not see.

> ⚠️ The gauge was built once and silently did not work: it sat full for the whole cycle and only
> flashed red. Cause was a **CVBasic codegen bug** — `MPY` on the TMS9900 overwrites `r0` with the
> product's high word, and the compiler kept assuming `r0` still held the multiplied variable, so
> `#bstep = #droprl` right after `#droprl = #droprl * 15` stored **zero**. Now recorded in
> `CLAUDE.md` §3A. It was found by *measuring the bar's pixel width from screenshots over a full
> cycle*, not by looking at it — the visual impression ("it wipes a few times") did not distinguish
> a broken gauge from a working one.

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

## 11b. Difficulty is not actually ramping — measured, open

Deriving grace time per round (`drops available × droptime`, where drops = `DEATHROW` minus the
lowest bubble's char row) says the ramp is not doing its job:

| | drops to death | grace, doing nothing | shots at 2.5 s |
|---|---|---|---|
| Round 1 | 12 | **240 s** | ~96 |
| Round 9 | 4 | 71 s | 28 |
| Round 16 | 12 | 189 s | 76 |
| Round 20 | 4 | 59 s | 24 |
| Round 30 | 6 | 72 s | 29 |

**Confirmed by actually playing them.** The winnability checker (§7a) plays every round out under
the real rules and reports how much of the clock a clearing line spends. At a realistic one second
of deliberation per shot, **29 of the 30 rounds finish having taken at most one ceiling drop** —
i.e. the timer never becomes a factor. Push it to *eight* seconds per shot and 29 of 30 are still
winnable. Only **round 30** is ever bounded by its timer. That is a much sharper statement of the
same problem than the idle-grace table below: the drop clock is not a difficulty dial at present,
it is a formality.

Mean **108 s of pure inactivity** before game over. Two problems: it is far too generous, and
**difficulty is dominated by each level's depth, not by the timer** — drops-to-death swings between
4 and 12 depending where the arcade layout starts, so a smooth 20 s → 12 s ramp is swamped and the
curve sawtooths. Round 26 is more forgiving than round 9.

Two candidate fixes, unresolved:

1. **Target grace time.** `droptime = target_grace(round) / drops_available(round)`, with
   `target_grace` ramping (150 s → 60 s) and `droptime` clamped 6–20 s. Makes the curve monotonic
   regardless of depth. Pure data change in `transcribe_stages.py`.
2. **The arcade's rule** (§11): drop on a shot count that *shrinks as colours are eliminated*. This
   is self-balancing by construction and does not care about level depth at all — a deep round with
   few colours presses hard, which is exactly right. Needs game code, not just data, and reverses
   the timer decision.

They are not exclusive: the shot count could stay the primary trigger with the existing timer as
the anti-idle fallback, which is what the arcade appears to do.

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
| `rowbuf(40)` — one row-pair blit source, **walls included** (§8) | 40 |
| `sc(8)` + `hs(8)` — score and high score, BCD digits (§11a) | 16 |
| `ofr/ofcl/ofk/ofxx/ofyy(12)` — falling orphans (§9) | 60 |
| `pres(9)`, `ad(6)` | 15 |
| scalars: `#bx #by #bdx #bdy`, `#dropt`, `#fd/#lf`, aim, top, shk, si, warn, sfx | ~55 |
| **Arrays + scalars** | **~282** |

**Measured after the fact: 487 B of 814 on ColecoVision, 498 B of 7,854 on TI** — the difference
above and the measured figure is CVBasic's own runtime. Comfortable on both, with Coleco at 60%.

Two decisions bought that headroom: building the blit source **one row-pair at a time** (§8)
rather than shadowing the name table (432 bytes), and deleting the hand-kept `colv`/`litv` colour
lookups, which were a second copy of the palette in `genart.py` — they desynced the moment it
changed, and `draw_sprites` now reads the generated `bub_base`/`bub_lit` tables from ROM (§14).

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
games/BustABobble/
  DESIGN.md  README.md
  src/BUSTABOB.bas          main source
  src/levels.bas           30 levels, generated -- never hand-edited
  src/aimtab.bas           64-entry aim table, generated
  src/music.bas            original BGM + danger variant
  assets/levels.txt        the 30 layouts, human-readable
  assets/genlevels.py  assets/genaim.py  assets/prevlevels.py
  build-ti.sh              cvbasic --ti994a -> xas99 -> linkticart -> BUSTABOB_8.bin
  build-coleco.sh          cvbasic -> gasm80 -> bustabob.rom
```

- **Build BOTH targets every time** (repo standing rule, memory `structris-build-both-targets`) —
  not just TI, and not just at the end.
- `#if TI994A` needs the **unhuman/CVBasic** fork; stock nanochess has no preprocessor.
- Delete any stale `BUSTABOB_b*.bin` before assembling — `linkticart` packs every bank file it
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

## 16a. Known problems — everything open, in one place

Found while building the winnability checker and the HUD (2026-08-16). Fixed items are listed too,
with where the detail lives, because several were invisible for a long time and the *way* they hid
is the reusable part.

### Open — level data

| # | Problem | Detail |
|---|---|---|
| 1 | ✅ **RESOLVED 2026-08-17 — four rounds shipped layouts detached from the ceiling** (9: 33% loose, **10: 90%**, 15: 44%, 20: 38%). The FAQ's ASCII diagrams do not carry hex adjacency at the row ends, so the transcription was faithful and still malformed. It broke three ways in turn — round 10 collapsing on the first pop, then bubbles shot onto the loose pieces never falling, then **round 20 becoming unwinnable** (22 of 29 bubbles unclearable even with the clock off). Fixed in the DATA: `transcribe_stages.py`'s `anchor()` pass adds the fewest cells that re-attach every piece — **14 cells across the four stages** (+2/+4/+3/+5), colours chosen so the repair does not hand out free pops. `--anchors` now reports zero, and with nothing detached the scenery set is empty and the drop rule degenerates to the stock Puzzle Bobble rule. | §7a, §11 |
| 2 | **Too many pre-made groups** — 85 pre-existing 3+ clusters across the 30 rounds; round 1 starts with 90% of its bubbles in one. They look poppable and are not, because matches are only tested when a bubble lands. Fix identified, not applied. | §7 |
| 3 | **Difficulty does not ramp.** Measured by playing every round out: at a realistic 1 s per shot, 29 of 30 finish having taken at most one ceiling drop. Push to *eight* seconds a shot and 29 of 30 still win. **Round 30 is the only round the drop clock ever constrains.** The timer is not a difficulty dial today, it is a formality. | §11b |

**No orphan rule could fix all three symptoms, because they were all the same bad data.** Each row
below is a rule that was actually built and run against all 30 rounds — this is measured, not argued:

| Orphan rule | Round 10 collapse | Bubble shot onto scenery falls | Round 20 |
|---|---|---|---|
| Global "not reachable from row 0" (original) | **broken** — one pop drops 19 | yes | winnable |
| "Was anchored before this shot" (attempt 1) | fixed | **broken** — can never fall | winnable |
| Ceiling + surviving scenery (attempt 2) | fixed | fixed | **unwinnable** |
| **Repair the layouts** (shipped) | n/a — nothing detached | n/a | winnable in 17 |

Chasing it in the drop rule was three attempts at the wrong layer. With the layouts repaired the
scenery set is empty on every round, so the rule degenerates to the stock Puzzle Bobble rule and the
special cases stop existing. The repair is deterministic and lives in `transcribe_stages.py`'s
`anchor()`, so it re-derives from `arcade-stages.txt` rather than being hand-patched into the data.

**The generalisable lesson:** three separate gameplay bugs, reported over three sessions and each
looking like a different bug in the *engine*, were one malformed input. When a rule needs a special
case to cope with the data, check the data.

### Open — not yet built

| # | Item | Detail |
|---|---|---|
| 4 | **Music does not fit** the fixed area any more after art growth. Plan: levels + music into one bank together, never separate. | §13 |
| 5 | **The danger state** (arcade raises the music tempo as the stack nears the line) is unbuilt. The death line flashes once a bubble has *crossed* it, but there is still no cue for danger *approaching*. | §11 |
| 6 | **BUB mascot**, rows 20–22, unbuilt. | §3 |

### Open — engine limits worth knowing

| # | Limit | Detail |
|---|---|---|
| 7 | **More than 4 sprites on a scanline still drop out.** Raising the orphan-fall cap 12→24 stopped bubbles *vanishing*, but a wide row of falling debris can still have some invisible for a frame or two until the staggered speeds spread them. `SPRITE FLICKER` stays off deliberately. | §5 |
| 8 | **A drop is deferred, never fired mid-animation** — it would move the field out from under a burst painted at fixed cells. Deferred by at most the rest of the animation. | §11 |

### Fixed this session — and how each one hid

| Problem | How it hid |
|---|---|
| **Orphans fell globally**, dropping bubbles unrelated to the pop; then the first fix inverted it and a bubble shot *onto* scenery could never fall | Looked like broken match logic. Both directions had to be reported from play before the rule was right (§11) |
| **Drop-timer gauge never drained**, sat full and only flashed red | A CVBasic codegen bug: `MPY` clobbers `r0` with the product's high word, so `#bstep = #droprl` right after a multiply stored **0**. Silent at compile *and* run time; found by measuring the bar's pixel width across a cycle, not by looking at it. Now `CLAUDE.md` §3A |
| **The drop clock paused** for the burst and the orphan fall — half a second free on every popping shot | §11 already *claimed* it never paused. The doc was aspirational and the code did not do it |
| **Big drops made bubbles disappear** instead of falling | The 12-sprite cap did not skip the animation, it deleted them — and drop_orphans walks top-down, so the ones that vanished were always the lowest, where the eye is |
| **"TIME" label over empty space; lives never drawn** | `prevlevels.py` mocks the *design*, so the preview PNGs showed a timer and lives the ROM never had |
| **Colour legend said "7 white 8 orange"** | There is no orange ball — 7 is grey, 8 is white. A walkthrough would have sent a reader hunting for a bubble that does not exist |
| **§3's screen diagram was stale** | It described pre-build-3 geometry with the corrections stacked in notes *above* it, and put TIME/lives on rows the ROM does not use |

---

## 17. Status

**2026-08-16 (build 8) — one hue per ball.** The two-tone palette was causing a *gameplay* fault,
not just an aesthetic one: red and "orange" shared a cap and differed by one body shade, so four
touching "reds" would not pop because two of them were a different colour. Every bubble is now a
single hue shaded by dither (§4), with density as the per-colour knob that separates white from
grey (2.2× denser). Title screen: SCORE flush left, HI flush right.

Two things were *proved* rather than assumed along the way, and both are worth keeping:
- **The match flood fill is correct** — 0 mismatches against a reference hex BFS over 4,000 random
  fields. That permanently rules it out as a suspect; the palette was the liar both times.
- **`assets/prevcolours.py`** renders all eight bubbles side by side with pixel counts, because the
  confusable pair is precisely the one a level render rarely shows together.

**Open, newly measured:** §7's pre-made-group problem — 85 pre-existing 3+ groups across the 30
rounds, round 1 at 90%. Fix identified, not applied.

**2026-08-15 (build 7) — animation, art, title screen.** Committed as `3e8a073`, `4149ec7`.

- **Pops burst and orphans fall** (§9). Sprites make the fall affordable — one call each per frame
  against 8 VPOKEs for characters. Debris needed a **full-ball** pattern; drawn with the body
  pattern it looked like bottom halves.
- **Cyan, magenta and grey are dithered** (§4) — the three that were all using white and competing.
  Grey is the case that matters: hardware has one grey, so density is the only way to two tones.
- **Title screen** with fire-to-start, 8-3-8 round select, and last/high score on the top row (§11).
- **Two duplication bugs, same shape.** The shot sequence used a polynomial whose parity was fixed,
  so **half of every palette was unreachable in all 30 rounds** (round 1 dealt only two colours);
  and the palette lived in two places, so the flying bubble and the landed bubble disagreed. Both
  fixed at the root: a generated table with a build-failing guard, and one source of truth for the
  palette. `prevlevels.py` imports from `genart.py` for the same reason.

**Budgets: TI fixed area 19,552 B of 24,336 — 4,784 free (80.3%).** Art grew ~2.8 KB this pass, so
**music no longer fits in the fixed area**; the plan is §13's (levels + music into ONE bank
together, never separate — a thinly-used bank doubled RALLY-X's cart). ColecoVision RAM 487 of 814.

**Open:** the difficulty ramp (§11b — measured, two candidate fixes, unresolved); whether the
quarter-density dither band shimmers in motion on a real display; music; the lives/spares HUD.

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
round-clear slide are all in `src/BUSTABOB.bas`. Both targets build from the one source.

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
