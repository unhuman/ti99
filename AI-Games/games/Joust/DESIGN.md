# JOUST — Design

A CVBasic port of Williams' 1982 *Joust*, dual-target **TI-99/4A + ColecoVision**.
You ride a flapping ostrich; enemy knights ride buzzards. Whoever's lance is **higher**
at the moment of contact wins. The loser becomes an **egg**, which hatches back into a
knight — one tier meaner — if you leave it too long.

**Single player only.** The arcade's Gladiator and Team waves are two-player constructs
and have no meaning here; §11 records what they were and what replaces them.

---

## 0. Research base

Numbers below are from the **original arcade instruction card** unless marked otherwise.
Where sources disagree, the instruction card wins and the conflict is noted in place.

| fact | source |
|---|---|
| Bounder 500, Hunter 750, Shadowlord 1500, Pterodactyl 1000 | instruction card |
| Eggs 250 / 500 / 750 / 1000 thereafter, **+500 caught in mid-air** | instruction card |
| Survival wave bonus 3000; extra bird every 20,000 | instruction card |
| Lava Troll from **wave 3**, escape by flapping quickly | instruction card |
| Pterodactyls debut **wave 8**, earlier if a wave drags | instruction card |
| Islands vanish on some waves and **return on the next Egg wave** | instruction card |
| Bridge over the lava burns away wave 3; ledges start vanishing wave 6 | StrategyWiki |
| Egg waves are wave 5 and every 5th, starting with 12 eggs | StrategyWiki |
| Waves 1-15 Bounders + Hunters; **Shadow Lord debuts wave 16** | StrategyWiki |
| Pterodactyl dies only to a lance in the **open mouth** | Wikipedia |
| Troll's reach lengthens and grip strengthens as waves pass | Joustmaster wiki |

> **Conflict, recorded not hidden:** one summary says Hunters appear from wave 4, another
> that waves 1-15 are "Bounders and Hunters" without a start wave. We use **Hunters from
> wave 4**, which satisfies both.

---

## 1. Performance budget (decided before line 1 — `CLAUDE.md` §5A)

| question | answer |
|---|---|
| Loop | **Real-time, fixed 30 Hz tick**: one pass every two frames (§1c) |
| Max moving sprites | **22 slots** — player and 6 knights as rider + mount pairs (14), 4 eggs, rescue bird, troll hand and arm, pterodactyl. `SPRITE FLICKER ON` shares a crowded scanline round everybody (§13) |
| Per-actor work | **O(1)**: add velocity, clamp, **row-indexed** island test, test lava |
| Enemy AI | **Reactive, no search**; each knight thinks one tick in four |
| VDP reads per frame | **Zero.** No `GCHAR`, no `COINC`; islands are a RAM table |
| Collisions | player↔knights, player↔eggs, player↔pterodactyl, player↔hand. Knight↔knight is **not** tested (they pass through, as in the arcade) |

### 1a. What actually costs — measured, not estimated

**CPU is the binding limit, not the 4-sprites-per-scanline rule.** An earlier version of
this section claimed the opposite and it sent four optimisation passes at the wrong
target. The numbers below come from counting instructions in the **generated `.a99`**,
and they agree with the on-screen loop-rate probe to within a frame.

A TI-99 frame buys roughly **2,000 instructions** once VDP wait states are paid.

| | static instructions | ×N | share |
|---|---|---|---|
| `k_body` — knight physics + AI | 813 | ×6 | **4,878 (44%)** |
| `k_one` — scalar cache in/out | 137 | ×6 | 822 |
| `c_knight` | 119 | ×6 | 714 |
| `e_body` | 176 | ×4 | 704 |
| everything else | | | ~4,100 |
| **total** | | | **~11,200 → 5.6 frames/pass → ~11 passes/sec** |

Two conclusions that were **not** obvious and each cost a session to learn:

- **Sprite output is free and there is nothing to batch.** `SPRITE n,y,x,f,c` never
  touches the VDP: it writes four bytes to a RAM mirror (`update_sprite`, 8
  instructions) and the vblank ISR blits all 128 bytes **every frame whether you wrote
  any or not** (`cvbasic_9900_prologue.asm:813`). Measured here: 22 `SPRITE` statements,
  140 generated instructions, mean 6.4 — all 15 sprites we push cost ~225 instructions,
  **2% of the frame.** CVBasic has no bulk-sprite statement and does not need one.
- **Almost all of `k_body` was one loop** — the island test, below.

### 1b. Islands are indexed by row, not scanned

Every actor used to test its y against all ten islands every frame. Even with a y-gate
that is ~60 instructions × 10 = ~600 per actor, and with six knights, four eggs (twice
each), the player (three times) and the rescue bird that is **~180 island iterations a
frame** — more than the whole frame budget.

**Every `ply()` is a multiple of 8**, so an island's surface lies in exactly one
character row, and at most three islands share a row (the base and both bridges sit on
row 21). `ir1/ir2/ir3(32)` index a row straight to its islands, rebuilt in
`set_islands` after every erosion change. The scan becomes three array reads.

This is **exact, not an approximation**: every action inside the loop body re-tests its
own band, so the old gate was purely an early-out. That distinction is the whole point —
an earlier attempt to halve the same cost by testing on **alternate frames** was *not*
exact. The vertical clamp is 1150 in 8.8, i.e. 4.5 px/frame, so two frames is 9 px
against an 8 px band, and knights fell straight through ledges.

Three details that are not optional:

- The row **above** the feet is consulted when the feet sit exactly on a row boundary.
  The landing band is `[kpt, kpt+8]` — nine values — and a nine-wide band straddles two
  rows precisely then. Dropping it silently narrows the band.
- **Routing keeps the classic scan and its own y-gate** (`k_route`). It wants every
  island *between* a knight and a target below it, which is a range, not a row. Without
  its own gate it would be slower than the loop this replaced, because `k_isl` has none —
  the row lookup *is* its gate.
- The player's three loops and the rescue bird's are **body-span ranges** over 2-3 rows
  and run once each per frame, so they keep the scan. Converting them buys little.

Converted: the ×6 knight loop and both ×4 egg loops — ~100 of the ~130 per-frame
iterations. Wave 1 went from ~12 to ~15 passes/sec.

### 1c. The fixed 30 Hz tick

The loop used to run as fast as the work allowed: **15 passes/sec on wave 1, 10 by
wave 12** on the TI, and 30-60 on ColecoVision. Every speed is per pass, so the game
slowed down as the arena filled and the two machines played at different speeds. It now
runs **one pass every two frames** (`main_tick` waits until `FRAME` has moved on by 2
since the pass began) and holds that on every wave on both machines. The constants
were rescaled for it (§3).

Measured in a cycle-counting emulator (TMS9900 with the >A000 RAM's wait states, and a
Z80 for ColecoVision), driving real play on waves 1, 3, 8, 12 and 16: 30 passes/sec
throughout, dipping only in the death animation. An artificial worst case, six live
knights plus four eggs and the pterodactyl at once, runs at 24-28.

What it took on the TI, in order of what it bought:

| change | where |
|---|---|
| **The vblank interrupt was 37% of the CPU.** CVBasic's handler copies all 128 sprite bytes and scans the whole keyboard every frame (~18,500 cycles). `tools/isrpatch.py` makes it copy only when the game publishes a finished pass (`sprok`: 2 every frame, 1 once, 0 hold), using CVBasic's `SPRITE FLICKER` path, which starts one slot later on each copy over all 32 slots (so the rotation advances once per pass) — patched to walk the slots with a stride of 7, as ColecoVision's runtime already does, so neighbouring slots are spread through the priority order instead of the same two staying hidden for most of a second, and skip the keyboard unless `kbscan` is set (title and 838 screens only). Publishing once per pass also means a half-drawn pass is never shown. | build-ti.sh step 2 |
| **One loop over the knights instead of three.** Movement, the joust and the draw now all run in `k_one` on the scalar copy; `collide` and `draw_knights` (two more loops re-reading the arrays) are gone. Eggs likewise in `e_one`. | `k_one`, `e_one` |
| **The scalar copy in and out is hand-written on the TI**: one indexed `MOVB`/`MOV` per field instead of ~130 cycles of index arithmetic each. The `#else` side is the same in BASIC, which is what ColecoVision compiles. | `#if TI994A` in `k_one`, `e_one` |
| **Each knight thinks one tick in four** (target, separation, routing), staggered by slot. Movement is every tick. The old halving keyed on `FRAME` parity, which never changes when a pass takes an even number of frames, so half the knights never re-targeted at all; it now uses a tick counter. | `k_move`, `k_body` |
| Island rows: an empty row costs one read (`ir1 = 255` means the whole row is empty), and the player's three island scans became one row-indexed pass (`p_isls`). | `k_isl3` callers, `p_isls` |
| Per-tier speed limits computed once per wave (`set_ktop`); facing and frame held as pattern offsets; the joust's horizontal reject done inline before the `GOSUB`. | `set_ktop`, `k_one` |

The loop-rate probe (`lprate`) has been removed now that the rate is settled.

---

## 2. Screen & platform layout

32×24 characters, 256×192 pixels.

```
rows 0-20  sky: rock ledges, knights, eggs, pterodactyl; base ledge on row 21
rows 22-23 cols 5-25: the rock base, with the score (col 9) and SPARE lives
           (col 17) set into it, as in the arcade
rows 22-23 cols 0-4, 26-31: the lava pit -- flames (4 frames, cycled every
           5 passes by redefining two characters) over molten rock
```
The ledges are drawn as rock: a yellow top edge over two shades of red rock with a
jagged underside. The base and lava rows are drawn once by `draw_field`; only the
two flame characters change after that (`lava_tick`), so the animation costs two
8-byte `DEFINE CHAR`s every 5 passes.

Horizontal **wrap** is free: `#px` is 8.8 fixed point, so 256 px × 256 = 65536 and the
16-bit variable wraps by itself. The top of the screen is a **ceiling** you bump against.

### The nine islands — MEASURED, not invented

`assets/refmap.py` downloads an arcade screenshot, classifies every pixel as rock or
lava by colour, and prints the spans scaled from Williams' native 292×240 to our
256×192. The layout below is that measurement.

```
y 40   ###  left                                  right  ###     two TOP ledges, at the edges
y 56          ######## middle ledge ########
y 88                              #### right, upper ####          overhangs the one below
y104   #### left ledge                    right, lower ####
y160   ################ FLOOR, FULL WIDTH ################
              \______ solid rock only in the middle ______/
       ~~~~~~                                        ~~~~~~       LAVA, at the EDGES
```

| # | name | x1 | x2 | surface y | notes |
|---|---|---|---|---|---|
| 0 | base | 40 | 199 | 160 | the solid middle |
| 1 | **bridge-left** | 0 | 39 | 160 | **burns at wave 3** |
| 2 | **bridge-right** | 200 | 255 | 160 | **burns at wave 3** |
| 3 | ledge-left | 0 | 47 | 104 | |
| 4 | ledge-right-lower | 208 | 255 | 104 | |
| 5 | ledge-right-upper | 168 | 215 | 88 | **overhangs #4** |
| 6 | ledge-middle | 72 | 143 | 56 | |
| 7 | ledge-top-left | 0 | 23 | 40 | |
| 8 | ledge-top-right | 232 | 255 | 40 | |

> **THE FLOOR IS FULL WIDTH AND THE LAVA IS AT THE EDGES.** The first, hand-written
> version of this table put the gap in the **middle** and had no bridges at all, so the
> player fell straight through the centre of the world on wave 1. In the arcade the floor
> spans the whole screen for waves 1-2 — you can walk over the lava — and the solid rock
> beneath it only spans the middle, so when the **end** sections burn away at wave 3 the
> lava is exposed at the **left and right edges**.

**The two right-hand ledges overlap in x on purpose**: the upper overhangs the lower, and
crossing the lower one halts you against it. That is arcade behaviour, and it is what
makes the right side awkward to leave.

**Islands are SOLID IN EVERY DIRECTION**, for the player and for knights alike. You
cannot rise through one: the head bumps its underside (`ply + 8`, one character row
thick) and upward motion stops dead. This is what makes the layout dictate the fight —
you must fly *around*, and a knight above you cannot be escaped by rising through the
floor he is standing on. Knights obey the same rule, because an enemy that can pass
through a platform the player cannot reads as cheating.

### Erosion

`plon()` is a per-island present flag, recomputed at every wave start **before** the field
is drawn. Deterministic, never random — a player must be able to learn the layout.

- **Waves 1-2**: everything present; the floor is continuous and the lava unreachable.
- **Wave 3**: both bridges burn, permanently. The lava at each edge is now live, and so
  is the lava troll.
- **Wave 6+**: one further ledge goes each wave, cycling islands 3→4→5→6.
- **Every Egg wave (5, 10, 15…) restores every island**, exactly as the arcade does.

---

## 3. Physics (8.8 fixed point)

Position and velocity are `#px/#py`, `#vx/#vy`, all ×256. Screen position is `#px / 256`,
which compiles to a shift, never a divide.

All per **pass** (30 a second, §1c).

| constant | value | meaning |
|---|---|---|
| `GRAV` | 11 | added to `#vy` each pass |
| flap impulse | 200 | subtracted from `#vy` per press, upward speed capped at 550 (2.1 px/pass) — bare literals, not `CONST`s |
| terminal fall | 590 | ~2.3 px/pass |
| `ACCX` | 13 | horizontal acceleration while running (stick held on the ground) |
| top speed | 550 | ~2.1 px/pass; knights get 430 + 70 × tier, plus 4.5 per aggression step (`set_ktop`) |
| skid | 30 | per-pass braking when the stick is pushed against the run (|vx| > 40) |
| flap steer | 120 | added to `#vx` in the stick's direction on each flap, clamped to 550 |

**Signed velocity in an unsigned world.** Every `#var` comparison compiles unsigned
(`CLAUDE.md` §3A), so velocities are stored **+32768 biased**: "rising" is `#vy < 32768`
and no comparison ever crosses zero. Position updates use `#py = #py + #vy` then
`#py = #py - 32768`, which is correct on either side of the bias because 16-bit
arithmetic wraps.

**Flap is edge-triggered** — holding fire does not hover. Each press is one impulse.

**Momentum is the arcade's feel.** There is no friction: let go of the stick and the bird
keeps its speed, in the air and on the ground. On a ledge the stick runs (accelerates)
and pushing against the run skids to a stop. In the air the stick only turns the bird to
face; speed changes come from flapping with the stick held, each beat adding 120 in that
direction. So reversing in flight takes several beats, as it does in the arcade.

---

## 4. The player

- Two sprites: a **white** rider in slot 0, drawn 4 px above a **yellow** ostrich in
  slot 1. The pair is one 16×20 figure (§13).
- Eight mount frames per facing: stand, four running beats, skid, wings up, wings down.
  A flap shows wings down for 10 passes, then up. On the ground the run beats advance
  with speed (one beat per 4 passes, twice as fast above 300) and a footfall clicks on
  two of them; a skid shows the skid frame and squeals. In the air: wings up falling,
  down rising.
- **Spawn invulnerability** 180 passes (6 s), shown by flashing. Without it a knight parked on
  the spawn point is an unavoidable death.
- Steering is **left/right only**. Nothing reads the vertical axis: on the TI it shares a
  line with ALPHA LOCK and reports a direction that never releases (`CLAUDE.md` §3A).

**Contact resolution** — boxes overlap when `|dx| < 12` and `|dy| < 12`:
- player higher by ≥ 4 px → knight unhorsed
- knight higher by ≥ 4 px → player dies
- within 4 px → **bounce**, both reverse `#vx`, nobody dies

---

## 5. Knights

| tier | colour | score | top speed | flap cooldown | debut |
|---|---|---|---|---|---|
| Bounder | red | 500 | 430 | 28 passes | wave 1 |
| Hunter | grey | 750 | 500 | 20 | **wave 4** |
| Shadow Lord | blue | 1500 | 570 | 12 | **wave 16** |

Shadow Lords fly **higher** by preference — they bias their flap threshold upward, which
is what makes them dangerous rather than merely fast.

**Materialising** takes 36 passes (1.2 s) on a free pad, with a new knight allowed every
24 passes (40 at the start of a wave). It shimmers through white, cyan, magenta and
light blue, one colour a pass, to a rising tone. It used to blink white for 4 seconds
with 1.7 s between knights, which read as slow.

### The three tiers fly differently — this is the character of the game

Not one homing rule with the speed turned up. From the arcade behaviour (Joustmaster
wiki, Wikipedia):

| tier | behaviour |
|---|---|
| **Bounder** | "flies around the environment **randomly**, occasionally reacting to the protagonist" |
| **Hunter** | "**seeks** the player's character in an effort to collide" |
| **Shadow Lord** | "flies quickly and closer to the **top** of the screen", and the arcade AI makes it **fly higher when close to the player** to improve its odds |

Implemented as one shared flight routine steering toward a per-knight **target**
`(ktx, kty)`; only the *choice of target* differs by tier, so the cost stays O(1):

- **Bounder** re-rolls a destination every 22-51 of its think ticks (3-7 s), and **only one roll in four is
  the player**. It reads as a creature going about its business that sometimes notices
  you. Explicitly **not a patrol** — pacing back and forth along a platform is what makes
  an enemy look like furniture.
- **Hunter** targets the player's x and **one notch above** his y: level flight into a
  joust is a coin toss, so it wants the high side of the contact.
- **Shadow Lord** targets the player but lives in the **top third**, and drops its target
  altitude *further* when within 48 px. **The climb is the attack** — altitude decides the
  joust, so closing high is aggression, not retreat.

Steering always takes **the shorter way round the wrap**; chasing across the middle when
the screen edge is nearer is the tell of an AI that does not know the screen wraps.

Difficulty is flap eagerness, top speed and target choice — never fleeing, which reads as
broken AI rather than as an easier game (`CLAUDE.md` §3A).

> **The tier speeds (430 / 500 / 570 now, 400 / 490 / 580 when this was found) must be 16-bit.** Written as a plain
> `ktop = 400 + tier*90` the 400 truncated to 144, giving 144 / 234 / 68 — **the Shadow
> Lord would have been the slowest enemy in the game**, the same inversion that shipped in
> RALLY-X. `tools/bigvar.py` caught it before the first build of this code.

Knights **pass through each other**; only player↔knight is resolved.

**Wave composition** (1-player):

```
wave 1-3    3,4,4 Bounders
wave 4-15   4-5, Bounders + Hunters, Hunter share rising
wave 16+    Shadow Lords enter, one more each wave until all are Lords
```

Cap at **4 simultaneous** knights (sprite slots 1-4); the wave's remaining knights spawn
as earlier ones die.

---

## 6. Eggs

An unhorsed knight leaves an egg carrying his momentum. It falls, lands, rests, then
**cracks** (flashing) and hatches into a knight **one tier higher** — the arcade's real
pressure: ignoring eggs escalates the wave.

| collected | value |
|---|---|
| 1st in wave | 250 |
| 2nd | 500 |
| 3rd | 750 |
| 4th onward | 1000 |
| **caught in mid-air** | **+500 bonus** |

The mid-air bonus is the skill reward and is implemented precisely: `gst = 1`
(airborne) at the moment of pickup, not resting, and only after the egg's grace period
(a grey egg cannot be collected at all). The ladder itself is one routine, `egg_award`,
shared by sprite eggs, ledge eggs (§9) and a man run down on foot.

---

## 7. Pterodactyl

- **Pterodactyl waves are 8, 13, 18...**: one arrives 10 seconds in. On any other wave
  it comes only once the wave has dragged past 60 seconds — the arcade's anti-camping
  device.
- Enters from the screen edge **away from the player** at the player's altitude and flies
  **one way only**, 2 px a pass, wrapping round the screen; it never turns back. It
  follows the player's altitude, not their x. It screeches every 64 passes.
- **It rests after a kill either way**: shot down, the next one waits 30 seconds; when it
  kills the player it leaves with them and stays away 20 seconds. It used to come straight
  back, which made shooting it pointless and a death a trap.
- **Invincible except** to a lance in the **open mouth**: the player must be
  approximately level (`|dy| < 4`) and closing head-on, i.e. facing it. Any other contact
  kills the player.
- Worth **1000**. Its animation alternates mouth open/closed; only the open frame is
  vulnerable, which is what makes the kill a timing feat rather than a coin flip.
- One at a time. If a wave drags further, another follows.

---

## 8. Lava troll

- **From wave 3.** A hand rises from a lava pit when the player flies low over it.
- If it grabs you it drags you down; **flap rapidly to escape**. Each flap adds to an
  escape counter; the hand wins if the counter does not fill before it reaches the lava.
- **Reach lengthens and grip strengthens with the wave number** — reach grows a few
  pixels per wave, escape requires more flaps.
- Being pulled under is a death.
- Rendered as sprite 10 plus a stretched arm; the hand only exists while grabbing or
  reaching, so it costs a sprite slot only when active.

---

## 9. Waves

| wave | type | what it means here |
|---|---|---|
| 1 | normal | 3 Bounders, all islands, no troll |
| **2** | **Survival** | 3000 bonus if completed without losing a bird |
| **3** | normal | **bridge burns away**; **lava troll active** |
| 4 | normal | **Hunters debut** |
| **5** | **Egg wave** | starts with **12 eggs** on the ledges; **all islands restored** |
| 6 | normal | **islands begin vanishing**, one more per wave |
| 7 | normal | |
| **8** | **Pterodactyl** | pterodactyl debuts; also triggered by any slow wave |
| 9 | normal | |
| **10** | **Survival + Egg** | every 5th is an Egg wave; every 5th also Survival |
| 11-15 | normal | Hunter share rising |
| **16** | normal | **Shadow Lord debuts**, one more each wave after |
| 20, 25… | Egg + Survival | pattern repeats |

**Survival is wave 2 and every 5th from 10.** **Egg is wave 5 and every 5th.** They
coincide from wave 10 on; the wave is then both, and both bonuses can be earned.

Every wave opens with a **banner** in the open sky of rows 10-11 (`WAVE n`, plus `EGG
WAVE`, `SURVIVAL WAVE` or `EGG AND SURVIVAL`). It is background, so the knights fly over
it, and `main` clears it after 90 passes (3 s).

**Survival.** `do_death` sets `wlost`; when the wave ends, `new_wave` pays 3000 if the
wave was a Survival wave and `wlost` is still clear (and the bird is not dying on that
very pass), showing `SURVIVAL BONUS 3000` for two seconds before the next wave is drawn.

**Egg waves start with no knights and 12 eggs on the ledges.** There are only four egg
sprites, and a sprite costs a slot on every scanline it crosses, so the waiting eggs are
**characters** (`EGGCH`, 137) at twelve fixed spots (`teg_col`/`teg_row`,
each directly above a ledge, clear of every pad and of the banner rows). `teg_tick` runs
only while any are left:

- touching one collects it on the normal egg ladder (centre-to-centre within 10 px, the
  same test as a sprite egg);
- every few seconds (`tegt`: 150 passes before the first, then 120 − wave, at least 60),
  while an egg sprite is free, the next waiting egg **stirs**: its character goes and a
  resting sprite egg takes its place, cracking almost at once and hatching six seconds
  later into a Bounder on foot, whom the rescue bird then collects;
- while any are left the wave is not over (`mnl`).

So an Egg wave is a race to collect them before they wake, and an ignored one fills the
arena with Bounders exactly as an ignored egg does in any other wave.

---

## 10. Scoring

| event | points |
|---|---|
| Bounder | 500 |
| Hunter | 750 |
| Shadow Lord | 1500 |
| Pterodactyl | 1000 |
| Egg, 1st/2nd/3rd/4th+ in wave | 250 / 500 / 750 / 1000 |
| Egg caught in mid-air | +500 |
| Survival wave completed intact | 3000 |
| **Extra bird** | every **20,000** |

`#score` stores **tens of points** — every award is a multiple of 50, so it is exact, and
16 bits then reaches 655,350. The HUD appends the trailing zero.

**The extra bird** is checked in `prt_score`, because every award ends by printing the
score: when `#score` reaches `#nxtb` (2000 tens at the start), a life is added (up to 9)
and `#nxtb` moves on by 2000. It stops at 65535 rather than wrapping, which would award a
bird on every point from then on.

**Lives: 3 total, HUD shows SPARES** — two icons at the start, none on the last life
(`CLAUDE.md` §7A). `lives` is unsigned 8-bit, so the decrement is guarded: a bare
`lives - 1` at zero wraps to 255 and lights every icon exactly when there are none. The
four icon cells (columns 26-29) are **right-justified**, so the last spare sits in column
29 and the row empties from the left; the test is `slot + spares > 3`, never
`slot >= 4 - spares`, since extra birds can take the spares past four.

---

## 11. Not ported, and why

| arcade feature | disposition |
|---|---|
| Gladiator wave (wave 4, every 5th, 2P) | **Omitted** — two-player only |
| Team wave (2P cooperative scoring) | **Omitted** — two-player only |
| Second player (blue knight on a stork) | **Omitted** — one joystick's worth of game |
| Pterodactyl-farming bug (turn to face for unlimited spawns) | **Not reproduced.** It is a bug, not a feature |

The 3000 Survival bonus is kept in its **one-player** meaning: finish the wave without
being dismounted.

---

## 12. The arcade font

The stock CVBasic font is a generic 8×8 and reads nothing like Williams' hardware. A
dedicated font is part of this port, generated by `assets/genfont.py` into `src/font.bas`:

- **Characters 32-90 only** (space, digits, `A`-`Z`, and `&-.!/`), the set the game
  actually prints — 59 characters × 8 bytes = 472 bytes, which belongs in a bank on TI.
- **Bold, to match the logo**: two-pixel uprights, up to 7×7 inside the 8×8 (M and W need
  seven), with a blank column and row for spacing. Each glyph is shaded like the logo,
  yellow at the top to red at the foot, by `font_col` (`DEFINE COLOR 32,59`).
- Digits are the distinctive part and get drawn first, since the score is the text most
  on screen.
- Loaded with `DEFINE CHAR 32,59,font_bitmaps` at startup, after which every `PRINT`
  uses it with no further cost.

---

## 12b. Title, difficulty, 838 and game over

- **Title**: the JOUST logo (160×24 px, generated by `genart.py` into 36 tiles at
  characters 160+, shaded white-hot to dark red down its rows), *THE HIGHER LANCE
  WINS*, the player and a Bounder facing off on a ledge, the controls, the difficulty
  line and *PRESS FIRE TO START*.
- **Difficulty** follows CLAUDE.md 7A: `1 EASY  2 MEDIUM  3 HARD` with the chosen one in
  cyan brackets (`(` and `)` are recoloured at boot and printed nowhere else). Keys 1-3
  pick it, left/right steps it, fire starts; the 3 inside 8-3-8 is the cheat, not HARD.
  `diff` is set to MEDIUM once at boot and persists. It shifts knight aggression two waves
  either way (`agg = wave + 2·diff − 2`, clamped 1-20) and the Hunter debut (wave 5 / 4 / 3).
- **838** asks for mounts (1-9, the lives the game starts with) and a starting wave
  (01-99), and flags the game (`chtd`) for a star at the end.
- **Game over** prints *THY GAME IS OVER* over the arena in the clear rows 10-12, with the
  difficulty played below it (starred for an 838 game), and returns to the title.
- The title, 838 and game-over screens, `draw_field` and `draw_plat` are **code in bank 1**
  on the TI, after the data: they run once a wave or less, and bank 1 is always selected,
  so calls in and out need no switching. That freed ~2 KB of the fixed area.

## 13. Sprites & characters

### Sprites (16×16, `DEFINE SPRITE n` counts whole sprites; pattern = n×4)

**Every knight is two sprites, rider over mount**, so the rider can carry the tier's
colour (red Bounder, grey Hunter, blue Shadow Lord) over a yellow ostrich or green
buzzard. `assets/genart.py` draws each figure once on a 16×20 canvas and splits it:
the mount is canvas rows 4-19 drawn at (x, y), the rider rows 0-15 at (x, y-4), and the
build fails if a pixel belongs to both (with flicker either layer may be on top).

| n | pattern | what |
|---|---|---|
| 0-7 | 0-28 | ostrich facing **right**: stand, run ×4, skid, wings up, wings down |
| 8-15 | 32-60 | the same facing **left** (the VDP cannot mirror) |
| 16-23 / 24-31 | 64-124 | buzzard, right / left, same eight frames |
| 32-33 | 128,132 | rider, right / left |
| 34-35 | 136,140 | egg, cracked egg |
| 36-37 | 144,148 | unhorsed knight on foot, right / left |
| 38-39 | 152,156 | troll hand, troll arm |
| 40-43 | 160-172 | pterodactyl: shut R, open R, shut L, open L |

Slots: 0-1 player (rider, mount); 2-13 knights (rider 2+2k, mount 3+2k); 14-17 eggs;
18 rescue bird; 19-20 troll hand and arm; 21 pterodactyl; 22-31 always hidden.
`SPRITE FLICKER ON` rotates the copy so a line with more than four sprites flickers
instead of losing the same ones every frame.

### Characters

| code | count | what |
|---|---|---|
| 128 | 3 | rock ledge: left cap, middle, right cap |
| 131 | 2 | lava flames (two phases of the same 4-frame cycle, `flame0-3`) |
| 133 | 1 | molten rock under the flames |
| 134 | 1 | spare-life icon |
| 135 | 1 | spawn pad |
| 136 | 1 | rock of the base |
| 137 | 1 | egg waiting on a ledge (Egg waves, §9) |
| 138-139 | 2 | base: left and right slope |
| 140 | 1 | second ledge-middle texture, so long ledges are not one repeated tile |
| 141-145 | 5 | ledge undersides, in the row below the surface: taper left/right (one column from an end), medium (two), deep ×2 (three or more) |
| 160-195 | 36 | title logo tiles (title screen only) |

**Ledges are flat on top and hang like lumps of rock.** `draw_plat` draws the surface row
the full width, with tapered end caps, and an underside row below it that deepens toward
the middle, picked per column by distance from the nearer end. A ledge running off a
screen edge (it wraps round) is treated as continuing three more columns, so it does not
taper at the edge; the floor (base and bridges) never tapers. Collision is unchanged: a
ledge is still its one 8 px surface row.

**The art and its data live in bank 1 on the TI.** The cart is banked (`BANK ROM 128`,
`BANK SELECT 1` at the top, all `DATA` after `BANK 1`); bank 1 stays selected, so
the code reads it like ordinary ROM. `build-ti.sh` checks the fixed area from
`BANK_0_FREE` in the listing and bank 1 from `BANK_1_FREE`. ColecoVision is
unbanked, within its 32 KB window.

### Sound

Effects are rows of `#sfxt` (channel, start divisor, per-pass step, volume, passes,
volume drop, chained effect) started by `sfn = SFX_x : GOSUB sfx_play` and stepped by
`sfx_tick` once a pass, which also sends every note-off. The sweep is what makes them
read as the arcade's sounds rather than beeps: flap is a burst of low noise, footfalls
click, a skid squeals, lances meeting clank (tone + noise), a defeated knight's note
falls away, an egg pickup chirps upward, a knight materialising shimmers, the
pterodactyl screeches, and its death is a long dive. Channel 3 (noise) is changed
volume-only while it decays, since rewriting its type restarts the noise.

---

## 14. Implementation phases

Deliberately incremental — each phase is playable and independently verifiable.

| phase | content | acceptance |
|---|---|---|
| **1** | Flight, islands, lava, wrap, HUD, title | Flap/fall/land on all islands; lava kills |
| **2** | Knights, altitude combat, eggs, hatching | Higher lance wins; eggs hatch a tier up |
| **3** | Waves, scoring, spares, extra life | Wave advances only when nothing remains |
| **4** | **Arcade font** | Score and titles in the Williams face |
| **5** | **Lava troll** (wave 3+) | Grabs low flight; flapping escapes; reach grows |
| **6** | **Island erosion** (wave 3 bridge, 6+ ledges) | Deterministic; Egg wave restores all |
| **7** | **Pterodactyl** (wave 8 + slow-wave trigger) | Only the open mouth kills it |
| **8** | **Egg & Survival waves**, bonuses | 12 eggs on wave 5; 3000 bonuses paid |

All eight phases are built.

---

## 15. Compiler-safety checklist

- [ ] No `<cmp> AND <cmp>` / `OR` — nested `IF`s (9900 backend miscompiles them)
- [ ] No `%` — `AND 7`
- [ ] No plain variable over 255; no `CONST` over 255 (**`TRUNCATION.md`**, gated by
      `tools/bigvar.py` + `bigconst.py` in both build scripts)
- [ ] Every `DATA BYTE` block **even** in length (`TRUNCATION.md` §1d)
- [ ] `DIM a(N)` is 0..N-1 — size for the real max index
- [ ] Sprites hidden at **209**, never 208
- [ ] No `GOSUB` exited by `GOTO` (`tools/gosubtrace.py`, in both build scripts)
- [ ] `VPOKE` operands precomputed into plain vars
- [ ] Never `MODE 2`
- [ ] Every sound has an explicit note-off and a decay counter ticked after **every** `WAIT`

## 16. Build & run

```
./build-ti.sh        -> src/JOUST_8.bin   (Classic99 / js99er)
./build-coleco.sh    -> src/joust.rom     (CoolCV / blueMSX)
```

Both scripts run the truncation gate and `gosubtrace` **before** compiling, and the TI
script checks the 24,336-byte cap with the `>6000`→`>A000` offset subtracted.

## 17. Acceptance criteria

1. Flap lifts; released, you fall to a terminal velocity and hold it.
2. Horizontal wrap is seamless both ways.
3. Landing works on every island; rising through one from below does not.
4. Lava kills; the bridge makes wave 1-2 crossable on foot and wave 3+ not.
5. The higher lance always wins; level lances bounce both.
6. An uncollected egg hatches one tier higher.
7. Mid-air egg catches pay the extra 500.
8. The troll's reach visibly grows with the wave; rapid flapping escapes it.
9. The pterodactyl dies **only** to a level, head-on lance in the open mouth.
10. Egg waves start with 12 eggs and restore every island.
11. HUD shows **spares**; no 255-icon wrap at zero lives.
12. Extra bird at 20,000.
13. Both targets build clean; `romcheck`/size guard report nothing truncated.
14. One loop pass per vblank with 11 actors live.

---

**Sources:** [Joust instruction card](http://amigan.1emu.net/kolsen/instructions/joust.html) ·
[StrategyWiki walkthrough](https://strategywiki.org/wiki/Joust/Walkthrough) ·
[Wikipedia](https://en.wikipedia.org/wiki/Joust_(video_game)) ·
[Joustmaster wiki](https://joustmaster.com/joust-wiki/)
