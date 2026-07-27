# Hard Hat Mack — Design (CVBasic, dual-target TI-99/4A + ColecoVision)

> **Hard-won CVBasic lessons this game obeys** (inherited from Structris/Astiroids — see
> `games/Astiroids/DESIGN.md` §12 and `games/Structris/DESIGN.md` header for the war stories):
>
> - **Default video mode + `DEFINE CHAR`/`DEFINE COLOR`; never `MODE 2`** (compiles clean,
>   renders broken on both targets). Colors are per-character, 8 bytes per char.
> - **Never `<cmp> AND <cmp>` / `<cmp> OR <cmp>` in an IF** — CVBasic 0.9.2's TMS9900 backend
>   miscompiles it (stale-register AND). Nest single-comparison IFs.
> - **All `#var` comparisons are unsigned** — no negative math; compute deltas branch-first
>   (`IF a > b THEN d = a - b ELSE d = b - a`).
> - **`%` compiles to a real DIV** even for powers of 2 — use `AND` masks.
> - **8-bit `FOR` with bound 255 wraps forever**; guard bounds built from unsigned subtraction.
> - **`DIM n(N)` declares N elements, indices `0..N-1`** — size every array to its **largest
>   index plus one**. `DIM jtab(15)` for the 16-step jump arc is the single most expensive bug in
>   this game's history: the arc's last step (`jtab(15)`, taken on **every** jump) read one byte
>   past the array, i.e. whatever variable the compiler placed next in RAM. That byte is usually
>   ≥128 and reads as a harmless small downward `dy`, so most jumps looked fine; when it was
>   small, `dv = 128 - v` became huge and the ascent branch ran dozens of pixels **in a single
>   sub-step** — Mack rocketing from the bottom beam to the top of the screen, "seizing" in
>   mid-air, or dying on an impossible landing. Because the culprit is a *neighbouring variable*,
>   the symptom **changed character every time an unrelated edit shifted the variable layout**,
>   which is exactly what made it look like a physics bug and sent several plausible-but-wrong
>   fixes (jump watchdog, fire-button cooldown, head-bump changes) into the code and back out
>   again. Suspect array sizing first whenever behaviour moves when you edit something unrelated.
> - **Array out-of-bounds is Coleco-FATAL** (781 free RAM bytes) — size arrays exactly.
> - **`SPRITE FLICKER` is all-or-nothing** (rotates the player too) — roll our own slot rotation.
> - **`DEF FN` substitutes arguments TEXTUALLY, with no implicit parens.** `VADDR(r + 1,c)`
>   against a body `$1800 + r * 32 + c` expands to `$1800 + r + 1*32 + c` — silently wrong
>   (found live in M1: the springboard coil painted at row 2 instead of 22). **Parenthesize
>   every argument use in every FN body**: `DEF FN VADDR(r,c) = $1800 + (r) * 32 + (c)`.
> - **`VPOKE` operands must be PLAIN VARIABLES on the TI target.** An expression operand
>   (`VPOKE VADDR(r,c),T_BRICK + k`) compiles to a push/pop on the simulated r10 stack around
>   the WRTVRM call, and that window randomly loses a race against the vblank ISR — the return
>   stack corrupts and the program jumps wild at the next RETURN, at a **build-address-dependent,
>   wandering** spot with no error (cost a long bisect in M2). Always
>   `#va = <addr> : ch = <val> : VPOKE #va,ch`, stepping with `#va = #va + 1`. Expression args
>   to `VPEEK`/`TILE` reads and `SPRITE` are fine (heavily exercised in working builds).
> - **`ON <var> GOTO` is 0-BASED** (value 0 selects the first label) — classic-BASIC 1-based
>   assumptions silently dispatch off by one. Subtract first: `t = t - 1 : ON t GOTO …`.
> - **TI single-bank cart cap: 24,336 program bytes** (`linkticart` silently truncates).
>   `build-ti.sh` measures `HARDHAT.bin − 16384` and fails the build past the cap; free bytes
>   are reported on every build.
> - **`WAIT` once per frame + FRAME-delta pacing** (`#fd = FRAME − #lf`, clamped to 4): missed
>   vblanks become catch-up steps, so TI-99 and ColecoVision run the same real-world speed. The
>   frame delta is then scaled to **9/8 pace** through an accumulator (`#hd = #hacc/8` after
>   `#hacc += #fd*9`). Mack (`mack_step`, 1 px/step) **and** the characters (`actors_step`, 1
>   px/step) both advance **`#hd` px per pass**, so the player and the bad guys move at **identical
>   speed**; collision + the bonus clock run once per pass in `actors_move`. Input/HUD update every
>   frame. **Exception:** the falling rivet (`bolt_move`) is called every frame ungated (original
>   full speed). The jump advances one step per sub-step like WALK, so a jump's **sideways drift
>   stays at full walk speed** (it must not slow mid-air).
> - Music via `PLAY SIMPLE NO DRUMS` (interrupt player owns channels 0+1); **all gameplay SFX
>   on channel 2**, noise on channel 3.
> - The **`unhuman/CVBasic` fork** is required: `--ti994a` auto-defines `TI994A=1` for `#if`
>   splits (stock nanochess has no preprocessor). No `-D` flag is passed.

## §0 Provenance

Adaptation of **Hard Hat Mack** (Electronic Arts, 1983; Apple II original by **Michael Abbot
and Matthew Alexander**; one of EA's five launch titles). Visual/layout reference: the
**ColecoVision version** (`assets/HHM-CV-Level1.png`, `HHM-CV-Level2.png`) — it shares our
TMS9918 VDP, so layouts and palette duplicate near-exactly. Apple II/Atari shots
(`HHMTitle.png`, `HHMlevel1-3`) remain as secondary reference for the title screen and
level 3. Original code was not consulted; all code and art here are original. Credit line:
`(C) 1983 MICHAEL ABBOT` on the title plus this repo's standard `2026 UNHUMAN AND CLAUDE`.

## §1 Concept & Objective

Three-screen construction-site platformer. Walk, climb, and jump through each screen's chore
while dodging the **vandal**, the **OSHA man**, and (level 1) **thrown bolts**:

1. **Beams and Bolts** — carry 4 loose girder pieces into the 4 floor gaps, then grab the
   roaming jackhammer (it can never be put down) and walk it over each filled gap to rivet it.
2. **Lunch Break** — collect 6 lunchboxes across a 3-tier site, then ride up under the armed
   electromagnet. (The Apple II original threatens an incinerator at the bottom; the ColecoVision
   reference we build to has none, so ours has none either — see §7 Level 2.)
3. **Rivet Works** — carry 6 steel boxes (one at a time) to either machine marked **IN**.

Clearing level 3 loops the game harder: **faster and more targeted, never more enemies**
(house rule — see §10 Difficulty loop).

## §2 Controls (joystick 1)

- **Left/Right** — walk. **Up/Down** — climb ladders (and enter pater-noster zones, L3).
- **Fire** — jump. Direction held at takeoff sets the fixed horizontal momentum of the arc.
- Title: **FIRE** starts; **8-3-8** on the keypad opens level select (repo convention).

## §3 Screen & HUD

32×24 chars; row 0 is the HUD (`B:` bonus, `S:` score, `H:` hi-score, `L`n level, `M`n lives —
the Apple II right sidebar folds in here); playfield rows 1–23. The Apple II playfield is
~30.5×22.5 tiles, so layouts transcribe nearly 1:1 onto our 32×23.

Sprites are **16×16 with NO magnification** (`VDP(1) = $E2`): floor rows are 4 cells (32 px)
apart and the original's actors stand about half that. (Structris/Astiroids use `$E3` 2× for
32-px actors — wrong scale here.) **All humanoid characters + the jackhammer are drawn 12 px
tall, bottom-anchored** in the 16×16 box (top 4 rows blank, feet on row 15): this leaves ~11 px
of head room under the floor above so the jump can arc a proper 10 px instead of a 7-px flat
hop. Feet stay on row 15, so floor math is unchanged; collision boxes compare sprite-tops for
both parties, so the uniform 4-px art shift cancels and needs no retuning.

## §4 Tiles, collision, level data

**VRAM is the collision map**: the painter VPOKEs chars into the name table and physics reads
them back with `VPEEK` — no RAM shadow (Coleco 1 KB). Collision class = char-code band:

| Band | Codes | Meaning |
|------|-------|---------|
| Solid | 128–151 | girders (blue 128 / purple 129 / orange-L3 130), FILLED gap 131, RIVETED gap 132, street 133, pillar 134, elevator 135–136, springboard 137–138 (+ L2/L3 solids as built) |
| Ladder | 152–155 | ladder 152; pater-noster up/down zones (L3, as built) |
| Conveyor | 156–163 | belt L/R × 2 animation frames (L2/L3) |
| Hazard | 164–171 | incinerator, flame lip, grinder — touch = death |
| Decor/pickups | 172+ | chain 172, lunchbox 183–184, girder piece 185–186, steel box 187–188 |

Gap state is pure tile rewrite: OPEN (void, fall-through) → FILLED (131) → RIVETED (132).

**Level data = opcode segment stream** (`DATA BYTE`, one stream per level, ~60–90 bytes each),
decoded by one interpreter at `init_level`:

| Op | Payload | Meaning |
|----|---------|---------|
| 0 | — | end of stream |
| 1 | row,col,len,type | horizontal run (0 girderA, 1 girderB, 2 street, 3 orange) |
| 2/3/4 | col,top,height | vertical run: ladder / chain / pillar |
| 5 | type,… | object: 1 gap(row,col) · 2 girder piece(row,col) · 3 jackhammer(row,cmin,cmax) · 6 elevator(col,rtop,rbot) · 7 springboard(row,col) · 11 vandal(frow,cmin,cmax) · 12 OSHA(frow,cmin,cmax) · 13 Mack spawn(row,col) · 14 bolt column(col) |

Ladders/chains are drawn **before** platforms so beams paint over them: visually the beams
cross in front (like the original) and the crossing cell stays solid for walkers.

## §5 Mack — physics (M2, per the approved plan)

Pixel coords, feet-anchored: feet on floor row `r` ⇒ sprite top `my = r*8−16`; centered on
col `c` ⇒ `mx = c*8−4`. Tile probes: foot `(my+16, mx+8)`, sides at `my+8`. All movement ×`#hd`.

States: **WALK** (1 px/step — same speed as the characters; conveyor drift ±1) · **CLIMB**
(1 px/step, snap `mx = col*8−4`, exit at floor rows) · **JUMP** (a **round parabola, apex 11 px** — the ceiling
max. Characters are drawn **12 px tall, bottom-anchored** (see §5), so Mack's head sits at `my+4`
and the head-bump probe is `TILE(mx+8, my+3)` — ~11 px head room under the 32-px-spaced floor
above (a full-height 16-px sprite had only ~7 px and its jump bonked the ceiling + truncated to
~1 cell). 16 steps: 8 up then 8 down (steep at launch/landing, flat over the top). Horizontal
momentum is set by the direction **held** at takeoff: **none = straight up-and-down** (lands in
place), left/right = 1 px/step drift = a full **16-px span = 2 cells** (measured) at walk speed;
index-driven, no signed compares) · **FALL** (dy 1,2,3,3…; **fatal past
20 px**) ·
**RIDE** (y follows platform: elevator, crane beam, magnet, pater-noster) · **TRAMP**
(scripted trampoline-channel ride) · **DEAD**.

Carrying (`carry`: 0 none / 1 girder / 2 jackhammer / 3 steel box) renders as **sprite 1
held in front of Mack** on his facing side (both the girder brick and the jackhammer) — shares
Mack's scanlines, never flickers apart. Girder auto-deposits over an OPEN gap; the jackhammer
is dropped only by a **long FIRE hold** (which resets it to its start), and Mack can jump while
carrying either; boxes auto-deliver at an IN hopper. Lunchboxes are instant char pickups.

## §6 Enemies & hazards (M3)

6 moving sprites max: Mack (slot 0) + carry overlay (slot 1) fixed; vandal / OSHA / bolt /
level-special (jackhammer, magnet head, rivet flash) rotate through slots 2–5 per frame
(`(i+rot) AND 3`) — own rotation, never `SPRITE FLICKER`.

- **Vandal**: patrols data-baked bounds, brief random pauses. Contact = death.
- **OSHA man**: same patrol; steps toward Mack when Mack is in his floor band (±8 px).
- **Rivets (L1)**: one sprite, thrown from above at Mack's position (spawn = his x + 48). It
  drifts **only left — never right, never re-aims** — bounces **once** on each floor it
  meets, then passes **through** that floor to keep descending; despawns off the bottom or
  the left edge. Loop ≥1: shorter throw interval.
- **Static hazards** are chars (band 164–171): incinerator, grinder — zero sprites, zero AI.
- Collision = bounding boxes sized to the **visible art**, not the sprite cell (deaths need
  real pixel contact): vandal/OSHA 8×10, rivet 6×8; the jackhammer grab is generous at 10×12.
  Branch-first deltas, nested single-compare IFs.

## §7 Levels

### Level 1 — "Beams and Bolts" (as built from the ColecoVision reference, running in Classic99)
Transcribed from `assets/HHM-CV-Level1.png` + user mechanics notes, then shifted **1 col right**.
5 girder floors rows **5/9/13/17/21**, spanning **cols 3–26** (blue body, red stripes top and
bottom). **No ladders: Mack climbs the hanging CHAINS** (cyan, 1 cell, climb band), hung from
the girder **edges**: beam1↔beam2 and beam3↔beam4 on the **left** (col 3), beam2↔beam3 on the
**right** (col 26); the top chain beam4↔beam5 is the exception at **col 21**. Arriving at a floor
pops Mack off the chain unless he is actively climbing toward more chain. The tall dotted columns
at cols **6 and 23** are support **braces — art only**, with pedestal bases (art) under the
bottom girder at cols 6/14/23.
**Holes to plug are 1 cell wide**, stacked on the left at **col 11** for beams 1/2/3 (rows
21/17/13) plus beam 4's hole at **col 18** (row 9) — matched by **4 brick stacks** at (8,9),
(12,9), (16,9) and (20,21). Deposit from either lip; walking the plug with the jackhammer
rivets it instantly on contact. Falling into an open hole is a fatal one-floor drop. Bonus
**wrench** (4,21) and **spray can** (20,25) = +200 each.
(Floors are numbered bottom-up: 1st = row 21 … 5th/top = row 5.)
Chains hang **2 cells** from the upper girder's underside and do **not** touch the girder
below — climbing off the bottom end is a short safe drop; grabbing upward reaches them via a
torso-then-head probe with a one-cell side grace. The jump is a round 11-px-apex arc (the
12-px-tall characters give the head room the 32-px floor gap otherwise wouldn't); held left/right
it travels a measured **16 px = 2 cells** (clears a 1-cell hole), and with **no direction held it
goes straight up and down**, landing in place.
Jackhammer roams a fixed serpentine route and is carried **in front of Mack** in his facing
direction, and **keeps hammering while carried** (its two frames animate the same as when it
roams — it doesn't freeze in his hands); **a carried brick is held in front too** (not overhead).
Mack can **jump while carrying** the hammer or a brick (FIRE always jumps); a **long HOLD of FIRE
(~0.75 s)** releases the jackhammer and warps it back to its start with its route pattern reset. **Elevator** (16×4
sprite platform, cols 1–2): **no button** —
it auto-starts the moment Mack is **fully aboard** (snap-centered on the 16px platform) while
armed, then travels non-stop at 1 px/frame between the **1st and 4th floors** (rows 21 ↔ 9),
Mack locked aboard, and parks. It arms on boarding, clears when a trip starts, and re-arms only
after he steps off and fully back on (the FAQ's exit-to-re-activate rule), so it never makes an
immediate return trip; the shaft is an open pit when the platform is elsewhere. **Right side:
every floor (cols 3–26) ends at a 2-cell jumpable gap (cols 27–28) before the trampoline
channel (cols 29–30). The trampoline is ONE character tall** (a low cap on the 1st floor — jumpable-over).

**Reaching the trampoline is a jump you can miss.** There is exactly **one** catch, in `st_fall`,
and it requires both:
- **x** — Mack's 12-px art (`mx+2 … mx+13`) must overlap the **pad itself**, with 4 px of grace
  (`trxl = trx − 4`). Walking off the beam edge leaves him well short, so **walking off the right
  edge is fatal** and getting across is a deliberate, late jump. Measured window on the bottom
  beam: taking off from roughly the last cell and a half works; jumping a cell early misses and
  kills you.
- **y** — only once he is genuinely **below the bottom beam** (`fy > trmy = trby − 8`), so a jump
  arc merely passing over the channel is not captured mid-air (being snapped to the pad with
  steering locked reads as a second, uncontrollable jump bolted onto the first).

Two earlier versions of this were wrong in opposite directions. Keying the catch off `trx` while
Mack loses support at `mx+8` left a 10-px band with no floor *and* no trampoline, so walking right
died every time and the respawn put him back on beam 1 — which reads as *"he teleports, falls from
up high, and lands right back where he started."* Widening the zone to the whole channel fixed that
but made the entire right side risk-free. The pad-overlap test is the middle: no dead band, no free
ride.

Entry rows round to real
floor rows so the bounce delivers **exactly one level above the floor you came from** (top
floor → rides down to the 1st floor). As Mack drifts left out of the channel onto the floor he
**flips to face left** (the way he's going) so he doesn't moon-walk off the trampoline. **Rivets** are thrown from above at Mack's position and
hop down the building (left-only, one bounce per floor, passing through after each bounce);
contact kills. Vandal patrols the 4th floor (2–12); OSHA patrols the 1st floor's left side
(4–20, homing in Mack's band). Mack spawns on the **right side of the 1st floor** (21,25).

### Level 2 — "Lunch Break" (M4 — layout transcribed from the reference)

**The layout below is MEASURED, not eyeballed.** `assets/HHM-CV-Level2.png` is 384x288 = exactly
1.5x the 256x192 screen, so it maps 1:1 onto the 32x24 cell grid; every coordinate here comes from
classifying the dominant colour of each cell and then zooming individual props to the pixel.

| Element | Cells (row, col) |
|---|---|
| Top crane platform | row 5, cols 11–13 and 15–17 (split by the cable) |
| Tier beams | rows 9 / 13 / 17, cols **2–10** (left) and **18–26** (right) |
| Crane cable | col 14, rows 3–19 |
| Crane beam (moving) | **cols 12–16**, centred on the cable |
| Conveyor A (upper right) | bottom drum (8,21) → top drum (6,25), post col 25 rows 7–8 |
| Conveyor B (lower left) | bottom drum (22,5) → top drum (20,9), post col 9 rows 21–22 |
| Chain (climbable) | col 23, rows 18–21 |
| Ground | row 23, cols 2–29 |
| Machine cabinet | col 29, rows 4–5, on a one-cell ledge at (6,29) |
| Plank stacks (decor) | (18, 2–5) and (12, 7) |
| Cement mixers (decor) | (22, 10–11) and (22, 17–18) |
| Electromagnet | row 4, above the shaft |
| Mack spawn | ground, col 3 |

**Prizes — one per tier end, each a DIFFERENT item** (`ob_pail` takes a `kind` byte 0–5 → lunch pail
183, toolbox 184, wrench 186, spray can 187, hard hat 188, brick 185): (8,6) (8,19) (12,4) (12,19)
(16,2) (16,19). They sit one row **above** the beam so they rest **on** the girder — drawing them
into the beam row punched a hole in the girder *and* sat a row below `take_item`'s torso probe,
which made them uncollectable. All six count toward `nlbr`; collecting them all arms the magnet.

**Corrections made 2026-07-26 after a cell-by-cell re-check against the reference:**
- The slab at (18, 2–5) was painted as a **girder**, handing the player a whole extra platform. In
  the reference it is a **stack of planks** — light-blue/white banded decor (char 172, pass-through).
  A second, one-cell stack sits at (12,7).
- The crane beam was **6 cells (11–16)**, which put it half a cell left of the cable it rides. The
  reference beam is **5 cells (12–16)**, centred on col 14. `beam_sup`'s span moved with it (x 96–135).
- The lower-left prize was at (16,5); the reference pail is at (16, 2–3).
- A sixth prize sat on the ground at (22,3) — where the reference puts **Mack**, not a prize. It moved
  to the upper-right tier (8,19), which had none, keeping the one-per-tier rule.
- Mack spawned at col 7 (mid-conveyor); the reference starts him at **col 3**.
- The chain ran rows 18–22; the reference is 18–21.
- The **incinerator** at (22, 19–20) is **not in the ColecoVision reference** and has been removed;
  the reference has a second round machine at (22, 17–18), which is now drawn there. (The Apple II
  original does have an incinerator — say the word and it comes back.)
- Added the **machine cabinet** at the top right (col 29, rows 4–5) and its ledge, which was missing.

**Known remaining cosmetic gaps vs the reference** (reported, not yet built): the cement mixers are
one cell tall where the reference draws them two; the small white props at (16,5) and (16,8), the
blue case + green hat at (16, 21–22), the barrel at (22,20) and the red device at (22,14) are absent;
the reference's top-right enemy is a red crab sprite where ours is the vandal patrolling the right
mid tier.

**Conveyor machines** (op 6, payload `row, col, h`) are built from 5 chars (156–160): **cyan roller
drums** at both ends, a **white belt with dark oval holes**, and a **yellow support post** under the
top drum. **Geometry is measured:** the reference conveyor is exactly **2:1** with its drums 4 cols /
2 rows apart, so op 6 puts the top drum at `(r−h, c+2h)` and draws each belt cell on the **exact line
between the two drums** — belt and drums cannot disagree. **Three belt chars, so the band is never
clipped:** the band drops 4 px per cell, so on alternate columns its centre lands *on* a cell
boundary; with only two chars that half fell outside the cell and vanished (the visible gaps). Now
`156` = band centred in the cell, and a straddling column draws **both** halves (`157` upper +
`158` lower). It **animates**: every 2 passes `DEFINE CHAR 156,4` advances through 8 phases
(`belt_anim0..7`) — belt slices rotated 1 px/phase **and** the drum spoke rotated to match, so the
whole machine moves. 8 phases = one full rotation = a seamless loop.

**Belt RIDE** (`conv_sup`, hooked wherever `beam_sup` is — walk / jump-land / fall-land): each belt is
stored as a **pixel SURFACE line** from `(cvx0,cvy0)` up to `(cvx1,cvy1)`. Standing near that line both
holds Mack up and carries him **up-and-right** (mx +1/pass, `my` snapped to the line), and it **stops
conveying at the top drum** so he stands there and chooses when to jump. This replaced tile-probing,
which dropped him through the gaps between diagonally-staggered belt cells.

**The centre is the moving CRANE BEAM (op 5 sub 10) — not chains.** It is drawn from **16 pre-shifted
girder chars (192–207)**, so moving it is pure **name-table placement**: nothing rewrites a pattern or
colour entry at runtime, which is what used to tear and flash. `beam_draw` runs **first in the loop,
inside vblank**, and skips entirely on dwell frames. `beam_move` steps `bmy` 2 px/pass over rows
48↔168. Mack **jumps on and off** across the side gaps; `beam_sup` (pixel check, x 96–135, `bmy`±4)
supports him and `bonbeam` carries him.

**Routes up from the ground:** the chain at col 23 (reachable standing on the ground, since it hangs
to row 21) reaches the lower-right tier; the lower-left conveyor lifts to (20,9), from where the
crane beam is a jump away at its low point.

**Element art matched to the reference** (patterns/colours extracted from the PNG at TI-pixel
resolution): the lunch pail is a domed **white** lid + gray latch band over a **red** body; each
platform is a **solid full-height red(2px)/blue(4px)/red(2px)** girder — no dash-holes; **ground** is
green grass over yellow-olive; the **magnet** is a white horseshoe with red pole tips.

**Still to do:** the magnet endgame has never been observed to fire, and the full six-prize clear has
not been played end to end.

### Level 3 — "Rivet Works" (M5)
Orange girders. Full-width top girder; top-left conveyor running **left into a grinder**
(escape = ladder above it; a steel box rides the belt); central **pater-noster** as an
escalator field (up zone / down zone, ledge exits — flagged simplification of the moving
cars); mid + lower tiers; two **IN** hoppers flanking a decorative processor door at the
bottom; springboard stools. 6 boxes carried one at a time to either hopper. Vandal guards the
left-tier box; OSHA patrols the right tier.

## §8 Scoring, lives, bonus

Girder deposited 100 · gap riveted 200 · lunchbox 300 · steel box delivered 500 · level
complete + remaining BONUS. BONUS starts 4600 (L1) / 5000 (L2/L3) and drops 100 per 60-frame
tick (floor 0). 3 lives; extra life at 10,000 (one-time). Death = tumble + jingle, respawn at
the level spawn **with level state intact**; 0 lives → GAME OVER → hi-score (session RAM) →
title.

**On death the roamers reset to their opening mark.** Both the vandal (`vx0/vy0/vb0`, route step
and direction cleared) and the drill (`jhx0/jhy0/jhb0`) return to where the level data placed
them, so a fresh life always starts from the same picture. Without it a villain parked on or next
to the spawn point could kill the new life the instant it appeared. Level *progress* (filled and
riveted gaps, claimed prizes) is still kept — only the moving actors rewind; anything Mack was
carrying returns to its original cell as before.

## §9 Sound (M6)

`PLAY SIMPLE NO DRUMS`; title tune loops on ch 0+1 (~1 KB budget); jingles for level start /
death / complete; SFX ch 2 (pickup, deposit, jump blips), noise ch 3 (rivet drill, grinder).
**No in-game music** (the original had none; ambience via SFX).

## §10 Difficulty loop (after L3) — faster + more targeted, NEVER more enemies

| Parameter | Loop 0 | Loop n≥1 |
|-----------|--------|----------|
| Enemy step | every 2nd frame | every frame (n≥2: 3 px/2 frames) |
| Bolt interval | 240 f | −60 f per loop, floor 90 |
| Bolt targeting | random drop column | column nearest Mack; n≥2 timed to intersect his walk |
| OSHA homing band | ±8 px | ±16 px, homing step every frame |
| Bonus tick | 60 f | 45 f |
| Enemy count | 2 per level | **unchanged** (user rule) |

## §11 Build & Run

- **TI-99/4A:** `bash build-ti.sh` — forked `cvbasic --ti994a` → `xas99` → `linkticart` →
  `src/HARDHAT_8.bin` (Classic99/js99er). The script **fails the build** if the program
  exceeds 24,336 bytes and prints free bytes every run. If bash chokes on cygwin DLLs, run the
  three stages from PowerShell (see `.claude/skills/build-cvbasic-game/SKILL.md`); use
  `C:\cygwin64\bin\python3.9.exe` with `/cygdrive/...` script paths.
- **ColecoVision:** `bash build-coleco.sh` — `cvbasic` (default target) → `gasm80` →
  `src/hardhat.rom` (CoolCV/blueMSX).
- `src/classic99.ini` points Classic99's cart MRU at `HARDHAT_8.bin`.

**Status / milestones:** M1 ✅ skeleton + render (CV reference) · M2 ✅ physics + actors,
user-tuned across several play rounds (chains, button elevator, bottom trampoline, parabola
jump, per-art hit boxes, airborne pose) · **M3 ✅ Level 1 player-verified working** (2026-07-19:
fill/rivet/deaths/scoring/extra life/brick-restore/game over, plus 12-px characters, rounded
apex-11 jump, no-button elevator, bottom trampoline, 3/4 pace with equal player/enemy speed —
all confirmed in play; polish items may follow) · **M4 🔨 Level 2 LAYOUT drawn + verified**
(2026-07-19: crane pole + magnet, tiered platforms, 6 lunch pails, 2 diagonal conveyors via new
op 6, incinerator, side chains; L1 still renders clean at 18,008 B — magnet endgame + moving
conveyors + traversal next) · M5 level 3 · M6 title/sound/loop/docs.
**Blocker note:** builds whose TI program exceeds **16,224 bytes** (into cart bank 3) fail
to boot when launched via `classic99 -rom` (QI399.087) — the cart image itself is verified
byte-correct, and even Structris's July-15 verified 3-bank cart now black-screens the same
way. Runtime-test 3-bank builds by loading the cart through Classic99's **Cartridge menu**
(or js99er). `build-ti.sh` prints the bank count and warns.

## §12 Acceptance criteria

- [ ] Compiles clean on both targets; TI program ≤ 24,336 bytes (guarded).
- [x] Level 1 renders per the reference screenshot (floors, gaps, ladders, chains, pieces,
      elevator, springboard, pillars, HUD) — Classic99 verified.
- [ ] Mack walks/climbs/jumps/falls with fall-death; elevator + springboard work.
- [ ] Level 1 completable end-to-end (fill 4 gaps, rivet with jackhammer); every death mode
      triggers (gap fall, edge fall, vandal, OSHA, bolt).
- [ ] Level 2 completable (6 lunchboxes + magnet escape); incinerator kills.
- [ ] Level 3 completable (6 boxes into IN machines); grinder conveyor kills.
- [ ] Loop past level 3 is faster with aimed bolts and the same enemy count.
- [ ] Title screen with credits + 8-3-8 level select; hi-score persists for the session.
- [ ] Both targets verified in emulators (Classic99 / CoolCV).

#### Falling — one rule for every surface (fixed 2026-07-25)

`land_chk` is the single landing verdict: a landing reached from a **jump or a fall** is fatal when
the drop from the arc's **apex** (`fcy`) exceeds `FATALFALL`. It is applied to *every* catch — solid
girder, crane beam, conveyor belt, elevator. Three bugs came out of not having this:

- Only plain solid ground was checked, so riding a long fall down onto the **moving crane beam** (or
  onto a belt) was a free save from any height.
- A **jump** landing was never checked at all, so jumping off a high ledge was safe while merely
  walking off a low one was fatal — the conveyor inconsistency.
- `fcy` was reset when the jump arc ran out, so a long drop was measured only from that point and
  undercounted. It now holds the apex: set at takeoff and tracked while rising.

`FATALFALL = 26` px, chosen to sit between two real distances in the level geometry: **22 px** (off
the top of a conveyor onto the platform its own drum stands on — must survive, it's the only way off)
and **32 px** (a whole storey, tiers/floors being 4 rows apart — must stay fatal).

#### Level 2 endgame — the electromagnet (2026-07-25)

The magnet is the win condition, not the last pickup. It hangs **dead** at the top of the crane until
every prize is claimed (`nlbr` reaches 0 → `mgarm = 1`); then it **tracks back and forth along the top**
(`mag_move`, cols 10↔24, 1 cell / 3 passes). Riding the upper conveyor to its top drum and **jumping
into the magnet** as it passes gets Mack caught (`mag_catch`: airborne only, head reaching the magnet's
underside with his centre beneath its 2-cell span) → `lvdone`. The magnet's row is clear of the crane
cable, so moving it needs no cable restore (unlike the beam, which does).

## §13 Target change — ColecoVision only (2026-07-26)

Development is now **ColecoVision-only**. The TI-99/4A build was hitting its **24,336-byte
single-bank cart ceiling** (2,185 bytes free with level 3, the title screen, and music still
unwritten — roughly 3 KB of work that does not fit), so every change was being fought against the
byte counter. The Coleco ROM has room to finish the game properly, and it is also the machine the
layout references come from, so "match the reference exactly" is native there.

- **Build:** `bash build-coleco.sh` → `src/hardhat.rom` (load in ColEm or CoolCV).
- `build-ti.sh` still exists and the source is still free of TI-specific constructs, but the TI
  build is **no longer verified each change** and will stop fitting; treat it as retired.
- **Review loop:** a level-start ROM (e.g. `src/hardhat_l2.rom`, gitignored) is built by flipping
  `lv` so a reviewer doesn't replay earlier levels; the committed source keeps `lv = 1`.
- **Emulator note:** both ColEm and CoolCV render at a fixed zoom that crops the bottom rows in a
  small window — maximize to see rows 20-23.

### Level 3 — "Rivet Works" (M5, first pass 2026-07-26)

Layout transcribed from `assets/HHM-Level3.png` at its cell grid (the reference is the Apple II
shot; playfield cols 2-29, beam rows 5/9/13/17, ground 23 — the same 4-row spacing as level 1).
Beams are **orange** (op 1 type 3). Drawn: top beam cols 2-29; upper-right beam 21-29; mid beams
2-10 and 21-29; **split** lower beams 2-4 / 7-10 and 21-25 / 27-29; ground 2-29; the top-left
conveyor machine; chains off the beams at cols 4, 9, 28, 29.

**Pater-noster (simplification, flagged):** the reference's vertical loop-lift is drawn as a twin
shaft at cols 15-16 and made **climbable** (chain band), which delivers the same vertical traversal
without a whole new ride state. Worth revisiting if it should carry the player automatically.

**Objective:** six **steel boxes** (carryables, counted by `nbox` in `ob_brick`) must each be carried
to either **IN hopper** (char 191, op 1 type 8) at the bottom — cols 4-7 and 24-27. Walking onto a
hopper while carrying delivers it (`deliver_box`, +500); six delivered sets `lvdone`. Clearing L3
loops back to level 1.

**Not yet done:** the grinder at the conveyor's end (riding it to the end should kill), the central
processor door as decor, IN-hopper "chomp" animation, and a play-through to confirm every box is
reachable.
