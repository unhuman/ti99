# Hard Hat Mack — Design (CVBasic, dual-target TI-99/4A + ColecoVision)

> **Current status (2026-10-01): both ColecoVision and TI-99/4A are required.**
> Section 16 supersedes earlier mechanics, budgets and verification notes.
> Older sections remain as implementation history; README describes current play.
> Title/838, music and loop difficulty described as design goals are not implemented.

## Current performance budget

The renderer uses slots 0-17 for Mack, clothing, carried objects, actors and site
machinery. Not all are active on each site. The TMS9918 four-sprites-per-scanline
limit still applies; parked elevator cabins also have name-table backing.
Real-time FRAME delta, clamped to four, feeds a 9/8 accumulator: at most five
one-pixel world steps per pass. All gameplay movement now uses those steps.
Ordinary walking makes at most eleven tile reads per step (chain probes + feet +
torso); a spring ascent can make ten head probes per step. The intended ceiling
is **60 tile VPEEKs per pass**, including bolts, with no COINC calls. This is a
budget, not a measured throughput claim; CPU timing on busy levels still needs
profiling. No RAM tile-map mirror; level data and graphics remain in ROM/VRAM.

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
> - **Compare art against the reference with an OFFLINE RENDERER, not the emulator.** ColEm draws
>   at a fixed large scale and the whole 256×192 screen does not fit this desktop, so screenshots
>   were always clipped and art work was being judged from fragments. A ~200-line Python script
>   (`scratchpad/render.py`) parses the `CONST`s, the `DEFINE CHAR`/`DEFINE COLOR` tables and a
>   level's opcode stream straight out of `HARDHAT.bas`, builds the 32×24 name table and paints it
>   with the TMS9918 palette — the exact screen, instantly, with no emulator. Stacking that against
>   the reference at the same scale (`scratchpad/side.py`) is what finally made the art differences
>   obvious. Verify on the emulator afterwards; iterate on the renderer.
> - **Sprite y = 208 (`$D0`) TERMINATES the sprite attribute list.** It is not an off-screen row —
>   the VDP stops scanning there, so *every higher-numbered sprite vanishes*. Park unused sprites at
>   **209**, and make sure no computed y can land on 208. This bit us for a long time in a way that
>   looked like anything but a sprite bug: the elevator is hidden by setting `ely = 209`, and the
>   draw call wrote `ely - 1` = **208**, so on every level without an elevator (2 and 3) all 29
>   sprites after it were silently dead. The level-2 vandal was invisible for weeks and a newly
>   added sprite simply never appeared. Symptom to remember: *a sprite you just added doesn't draw,
>   and neither do any others above it in slot order* — look for a 208 in a lower slot.
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
~1 cell). 32 steps: 8 up, 16 at the apex, then 8 down. Horizontal
momentum is set by the direction **held** at takeoff: **none = straight up-and-down** (lands in
place), left/right = 1 px/step drift = a full **32-px span = 4 cells** at walk speed;
index-driven, no signed compares) · **FALL** (dy 1,2,3,3…; **fatal past
26 px**) ·
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
| Conveyor B (lower left) | bottom drum (22,**6**) → top drum (20,**10**), post col 10 rows 21–22 — the whole lower machine group sits one column right of the reference; see "Routes up" below |
| Chain (climbable) | col 23, rows 18–21 |
| Ground | row 23, cols 2–29 |
| Machine cabinet | col 29, rows 4–5, on a one-cell ledge at (6,29) |
| Plank stacks (decor) | (18, 2–5) and (12, 7) |
| Cement mixers (decor) | (22, **11–12**) and (22, 17–18) — the left one moved with its belt |
| Electromagnet | row 4, above the shaft |
| Mack spawn | ground, col 3 |

**The pickup test is a RANGE over the whole band 183–188** (`T_LBOXL … T_HAT`), not a list of char
codes. It used to be four equality tests — 183/185/186/187 — which silently omitted the **toolbox
(184)** and the **hard hat (188)**. Two of level 2's six prizes could be walked over forever, so the
level could never be cleared. A list drifts out of step with the prize table; a range cannot.

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

**Conveyor art pass 2026-07-29:** the belt was a pair of thin rails broken at x=0 and x=4 of every
cell, which read as a line of loose dashes rather than one machine. It is now a **solid 4-px band
with a dark tread notch every 4 px that travels with the animation phase**, and the rollers are
**filled discs with a spoke cut out of them** instead of open rings. All eight phases (plus the
static table) are generated by `scratchpad/genbelt.py` rather than hand-authored, so the rails
cannot drift out of alignment between phases.

**The cement mixers are two cells tall** (2026-07-29): the round drum (chars 189/190) sits on a
**stand** (char 162) rather than being a lone blob on the grass. The stand is deliberately
*symmetric* so one character serves both columns — the decor band was full and only two codes were
left, and spending one on each half would have cost the level-3 oil drums.

**Known remaining cosmetic gaps vs the reference** (reported, not built): the small white props at
(16,5) and (16,8), the blue case + green hat at (16, 21–22), the barrel at (22,20) and the red
device at (22,14) are absent; the reference's top-right enemy is a red crab sprite where ours is the
vandal patrolling the right mid tier. **The decor character band (172–191) is now full**, so any
further props need a code freed or a per-level `DEFINE CHAR` swap in `init_level`.

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
holds Mack up and carries him **up-and-right** (mx +1/pass, `my` snapped to the line) all the way
through the rollers and off the end. This replaced tile-probing, which dropped him through the gaps
between diagonally-staggered belt cells.

**The crane cable hangs from above the beam only.** The cable is what the bar is suspended from, so
`beam_draw` pays it out and reels it in: a vacated cell in col 14 gets cable if it is now *above* the
bar and nothing if it is below. (Restoring it unconditionally drew rope underneath the beam.) Because
char cells can only end on an 8-px boundary, the last stretch is a **sprite** (`cable_bitmap`, slot 7)
whose bottom edge sits exactly on `bmy` and travels with the beam — without it the rope visibly
detached from the bar between cell rows.

**The centre is the moving CRANE BEAM (op 5 sub 10) — not chains.** It is drawn from **16 pre-shifted
girder chars (192–207)**, so moving it is pure **name-table placement**: nothing rewrites a pattern or
colour entry at runtime, which is what used to tear and flash. `beam_draw` runs **first in the loop,
inside vblank**, and skips entirely on dwell frames. `beam_move` steps `bmy` 1 px/pass over rows
48↔168. Mack **jumps on and off** across the side gaps; `beam_sup` (pixel check, art overlapping
x 96–135, `bmy`±4) supports him and `bonbeam` carries him.

**Routes up from the ground:** the chain at col 23 (reachable standing on the ground, since it hangs
to row 21) reaches the lower-right tier; the lower-left conveyor lifts you to its top roller, from
where the crane beam is a **timed** jump away as it passes.

**Making that jump possible again took three fixes (2026-07-26), and all three were needed:**
1. **The belt runs through its rollers and off the end.** Conveying used to quit 6 px early,
   parking Mack *mid-drum* — which both cost him the reach he needed and made the whole ride
   passive and safe. The machine now keeps feeding him: ride to the top and **jump off in time, or
   be tipped over the roller into the bins below**. (Support ends one pixel past the top drum, so
   the pass after the roller simply drops him. The fall is ~21 px, under `FATALFALL`, so it costs
   you the climb rather than a life.)
2. **Land by overlap, not by centre.** `beam_sup` required Mack's midpoint to clear the beam's left
   edge. With the beam correctly narrowed to the reference's 5 cells, that left the jump **one pixel**
   short. Any overlap of his 12-px art (`mx+2 … mx+13`) now counts — landing on a platform's edge is
   what a player expects. The sticky-ride check uses the same rule, or he would slide off the edge he
   is allowed to land on.
3. **The lower machine group moved one column right** (belt, post and mixer together). At the
   reference's cols 5/9 the roller is 17 px from the beam against a 16-px jump, so even after (1) and
   (2) the margin was 3 px — inside the noise of which sub-step the belt parks him on. Shifted, the
   park is `mx = 78` and the landing clears by 11 px. This is a deliberate, acknowledged one-cell
   deviation from the reference, taken because the alternative is a route that cannot be walked.

**The crane beam travels 1 px/pass, not 2.** At 2 px it covered 120 px/s — faster than Mack falls —
so a beam on its way *up* outran his descent and slipped through the ±4 px catch window entirely: the
jump only worked if you happened to meet the beam coming *down*. At 1 px the window is twice as
forgiving in both directions, and the ride reads better. Verified in a scripted run: ride up, wait,
jump right, and `bonbeam` latches with Mack riding at the beam's surface.

**Element art matched to the reference** (patterns/colours extracted from the PNG at TI-pixel
resolution): the lunch pail is a domed **white** lid + gray latch band over a **red** body; each
platform is a **solid full-height red(2px)/blue(4px)/red(2px)** girder — no dash-holes; **ground** is
green grass over yellow-olive; the **magnet** is a white horseshoe with red pole tips.

**Thrown rivets are level 1 only** (`bolon`, set in `init_level`). They used to fall on every screen
because `bolt_move` spawned off a bare timer; levels 2 and 3 have their own hazards and nobody up top
to throw them.

**Still to do:** the magnet endgame has never been observed to fire, and the full six-prize clear has
not been played end to end.

### Level 3 — "Rivet Works" (M5 — transcribed from the reference 2026-07-26)

**Measured, not eyeballed.** `assets/HHM-Level3.png` is a 1280×720 capture; the playfield rect is
x 98…1086, y 41…708, which lands the beams on rows **5 / 9 / 13 / 17** with the ground at 23 —
the same lattice as levels 1 and 2. Every coordinate below came from classifying the dominant
colour of each cell on that grid and then zooming individual props to the pixel.

| Element | Cells (row, col) |
|---|---|
| Top beam | row 5, cols 2–29 (full width) |
| Flat conveyor | row 9, cols 2–11, running **LEFT** |
| Grinder | row 8, cols 2–3 (torso height over the belt's end) |
| Upper-right beam | row 9, cols 21–29 |
| Mid beams | row 13, cols 2–10 and 21–29 |
| Lower beams | row 17, cols 2–4, 7–10, 21–24, 27–29 |
| Pater-noster shaft | cols 15–16 |
| Step-off stubs | (10, 17–18) (12, 13–14) (14, 17–18) (16, 13–14) |
| Chains | col 4 and col 24 rows 6–7; col 9 and col 29 rows 14–16 |
| Ground | row 23, cols 2–29 |
| IN machines | rows 22, cols 3–7 and 24–28 |
| Processor door | cols 14–17, rows 19–22 (decor) |
| Trampoline pads | **row 23**, cols 11 and 20 |
| Steel boxes | (4,12) (8,7 — on the belt) (12,4) (12,28) (16,8) (16,22) |

**Girder colour:** level 3's beams are an **orange-striped blue** bar in the reference, not the
red-striped one of levels 1–2. Char 130 is now the same full-height shape as 129 with dark-yellow
stripes (the closest the TMS9918 gets to that orange). It used to render as a solid red slab.

**The flat conveyor (op 9)** is new: `row, col, length, direction`. The op-6 machine is inherently
diagonal and could not express this belt, which is horizontal and runs **into** the grinder.
`cvdir()` carries the direction per belt, so `conv_sup` pushes left or right accordingly; the
surface line is recorded flat (`cvy0 = cvy1`), which makes the slope term zero and needs no other
change. **Riding to the end kills you** — the grinder sits at torso height over the belt's left
end. Because the belt path returns early from `st_walk`, the hazard *and* pickup probes are
repeated inside it; without that the grinder could not kill and the box riding the belt could not
be grabbed.

**The trampoline pads (T_PAD, char 139)** are how you get up from the ground. They are **solid and
sit IN the ground row** — drawn one row higher they'd be at Mack's waist and he would walk straight
through them, since it is the *foot* probe that triggers a pad. Standing on one launches him
immediately with the `spr2` arc (now ×5, ~55 px — ×3 fell short of a beam), steerable by holding a
direction at the moment of launch; the pads sit two cells out from the beam they serve. Landing on
a pad is **never** fatal, or the ~55 px descent would read as a killing fall. Verified: step on the
left pad holding left → lands on the lower-left beam (feet row 17).

**The pater-noster** stays the flagged simplification — a climbable shaft rather than moving cars —
with the reference's step-off stubs built as real ledges. **Deviation:** the reference runs it
rows 8–17 between two cars and expects the pads to be the only way off the ground; ours is carried
down through the processor door to the ground so the shaft is also enterable from below, and up to
the full-width top beam. It reads as the lift descending into the machine.

6 boxes carried one at a time to either **IN** hopper. Vandal patrols the lower-left beams, OSHA
the lower-right.

**Art pass 2026-07-29** (measured against the reference with the offline renderer):
- **Pater-noster** was a cyan chain; it is now a **white-walled tube with two green rails**
  (chars 153/154, both inside the climb band so the shaft still works as the way between floors).
- **Chains** are green on level 3 (char 155, its own colour) — level 1's cyan chains are untouched.
- **Steel boxes** were level 1's red brick stacks; they are now **white crates with a green lid and
  a magenta face** (char 182, placed one below the lunchbox so the pickup band stays the single
  contiguous range 182–188). `ob_brick` picks the crate on level 3 only.
- **Processor door** is a blue frame around an orange panel (char 173) instead of a yellow tile.
- **Trampoline pads** gained the pinched stand the reference draws under them (char 179).
- **Flat belt** is one solid bar rather than a row of separate blocks.
- **Girders** are orange-striped blue, not a solid red slab.

**Closed 2026-07-29:** the **flat belt animates** — the phase tables were widened from 4 chars to 6
(156–161), so char 161 rides the same clock as the diagonal belts and its tread notches travel left
with them; the **grinder** is a toothed wheel throwing orange sparks instead of a plain block; and
the reference's two pairs of **oil drums** now stand on the ground at cols 9–10 and 21–22.

**Traversal audit 2026-07-29 — the level was NOT completable; three things were wrong.**

1. **Every side beam was a one-way trap.** The step-off stubs were 2 cells at 13–14 / 17–19, which
   left them *three* cells from the beams — unreachable with a 2-cell jump — and the beams had no
   other route back. You could bounce up to a beam off a pad and then had no way down that wasn't
   a fatal drop. The stubs are **4 cells** now (11–14 left, 17–20 right), which puts each one a
   single jump from its beam while still inside the chain-grab probe of the shaft. The left stubs
   overhang the beam below them, so coming back is just walking off the edge and dropping a row.
2. **The box on the conveyor could not be collected.** The only way onto the belt was the chain at
   col 4 — its *left* end — but the belt runs left, so you arrived already past the box at col 7
   with nothing ahead but the grinder. Worse, you cannot walk right against the belt (the drag
   exactly cancels a walk step). A **second chain at col 10** drops you on the far end, so it is
   the gauntlet it was meant to be: ride left over the box, then climb out on the col-4 chain
   before the teeth.
3. **The trampoline pads were an infinite bounce.** With no direction held a pad throws you
   straight up and you land back on it — and they sit at cols 11 and 20, right across the walk
   between the shaft and the IN machines. Pads now use the same arm/disarm rule as the elevator
   (`padok`): fire on arrival, re-arm only once Mack is off the tile again.

**Verified by measurement** (spawn on the tile, drive one input, read `mx`/`my` back off a debug
HUD): ground → shaft → top beam (feet land on row 5); mid-left beam → row-12 stub and back; row-14
stub → mid-right beam; pad → lower-left beam.

**Still unverified:** the belt gauntlet end-to-end and a full six-box clear — the machine locked
mid-run and the emulator cannot be driven from a locked session.

## §8 Scoring, lives, bonus

Girder deposited 100 · gap riveted 200 · lunchbox 300 · steel box delivered 500 · level
complete + remaining BONUS. BONUS starts 5000 on every level/life and drops 100 per 120 world steps
(floor 0, death on reaching zero). 3 lives; extra life at 10,000 (one-time). **`lives` is the SPARE count, not the total** — it starts at **2** for three plays, and game over fires on dying with it at 0, so `hud_lives` draws `IF i + lives > 2`, right-justifying two hats on a fresh game. That is the repo convention (`CLAUDE.md` §7A: the indicator shows reserves, excluding the life being played). Stated explicitly because the `IF i < lives` pattern looks like the anti-convention bug at a glance and has already been misread once. Death = tumble + jingle, respawn at
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

## §11 Historical build notes (current commands: README and section 14)

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

## §13 Historical retirement (2026-07-26; reversed by section 14)

Development was temporarily **ColecoVision-only**. This decision is withdrawn; see section 14. The TI-99/4A build was hitting its **24,336-byte
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


## §14 Playability repair and dual-target restoration (2026-10-01)

**Decision: repair the existing core; retain the maps and art.** The concrete
faults below do not require discarding the level transcription work. This is a
playability repair, not a claim of complete original-game fidelity.

The baseline TI program measured **25,222 bytes**, 886 over the 24,336-byte
fixed-area cap. `BANK ROM 128` / `BANK SELECT 1` / `BANK 1`, gated to TI, now put
all level/graphic data into physical page 3. It stays selected for the entire
game. Three loader pages plus one data page produce a **32 KB cart**. Coleco
remains an ordinary unbanked ROM. `checkbank.py` checks exact page equality in
the packed cart, the terminal data marker, and the 8 KB bound, with negative
cases for truncation, oversize and corruption. Fixed-area size is checked before
packing using the repository's existing `banksize.py`.

### Budgets at the first repair (superseded by section 15)

| Target / area | Used | Available / free |
|---|---:|---:|
| TI fixed program | 23,330 B | 1,006 B free of 24,336 |
| TI data page (excluding trailer) | 2,560 B | 5,630 B free of 8,190 |
| TI compiler-reported variables | 308 B | 7,546 B free of 7,854 |
| Coleco ROM output | 24,576 B | 8,192 B below standard 32 KB limit |
| Coleco compiler-reported variables | 297 B | 517 B free of 814 |

### Movement and lifecycle changes

- The 16-step jump only reached the enemy's 10-pixel vertical clearance for
  three steps, too briefly to cross its 15-pixel horizontal contact interval.
  A normal jump now holds its 11-pixel apex for 16 extra steps. Total duration
  is 32 world steps (about 0.47 seconds at the target 67.5 steps/s), travelling
  32 pixels with a direction held at launch. The stationary jump remains
  stationary. A ceiling bump cancels the hold; spring jumps retain their
  original 16-step arc. This deliberately changes the earlier 16-pixel tuning.
- The BASIC-executing test finds 5, 15 and 25 safe integer launch positions
  against stationary, half-speed and full-speed approaching enemies in its
  fixture. The old arc has no usable window and must fail the test.
- Airborne momentum continues after the table finishes. Walking off an edge
  captures the held direction; dropping down a chain has no sideways momentum.
- Fire jumps off chains and parked elevators too. This provides a way to leave
  the level-3 shaft at its intermediate ledges; a complete traversal still needs
  runtime verification. Moving elevator rides remain locked until arrival.
- `world_step` advances Mack, the drill/vandal routes, patrols/collisions, bolts,
  crane beam, magnet and elevator together. The bonus loses 100 every 120 world
  steps (about 1.78 seconds at target rate). Thus a light and heavy loop pass no
  longer changes platform/hazard speeds relative to Mack. The four-frame catch-up
  clamp remains; if a pass exceeds it the whole simulation slows together.
  Conveyor animation and sound/death/hammer-hold counters still use loop passes;
  these are not claimed as frame-calibrated timings.
- Fatal landings now set S_DEAD through an ordinary returning GOSUB. Subsequent
  substeps cannot overwrite a pending death with a safe landing. The earlier
  comment that calling `mack_die` unbalanced the return stack was incorrect:
  it returns normally. Elevator support is refreshed before deciding a fall's
  landing state, and death detaches Mack from the crane beam.
- New games restart at level 1, without inheriting the game-over level. Level
  initialization resets frame accumulation and the Fire edge. Old sprites are
  hidden before repaint; noise and tone effects are silenced between screens.
- The long-hold counter saturates instead of wrapping; a right-edge bolt spawn
  clamps before adding 48, avoiding byte overflow. Lost steel boxes return as
  steel boxes. Spare hats are right-justified, and bonus zero kills immediately.

- Level-1 gap filling is explicitly limited to level 1. Otherwise the gap
  coordinates left in memory consume steel boxes on level 3, making its six-box
  objective impossible. The checker verifies both rejection on level 3 and a
  successful level-1 deposit with the same coordinates.
- The lives HUD uses its own loop index. Awarding an extra life during a pickup
  must not overwrite the pickup routine's global index; the checker executes
  the score-to-HUD call chain and verifies that the index survives.

### Verification and remaining work

Both target builds run `checkphysics.py`, the truncation gates and `gosubtrace`.
The new checker executes the shipped BASIC routines (including byte wrapping),
with tile fixtures and absent conveyor/crane probes, and rejects unknown executed
statements. It covers ordinary jumps, one-cell holes from both sides, jumping
from chains/parked elevators, fall momentum, fatal landing persistence and the
shared movement call schedule. Six bad mutations must fail, including stale gap consumption and HUD index clobbering. It does not model
the compiler, CPU timing, full moving-platform geometry, or whole-level routes.

TI boot and a Fire jump were smoke tested in Classic99 using the production
cart. Full play-throughs, busy-level timing measurements and Coleco runtime
verification remain open. No title/838 screen, music, escalating difficulty or
moving pater-noster has been added by this repair. The old M1-M6 notes above
are historical/design material; README lists the current user-visible behavior.

Use `tools/hardhat-dev.ps1 BuildAll` for sequential builds and `LaunchTI` for
Classic99 with the project's input profile and a reported production ROM hash.

## §15 Three-site mechanics and presentation repair (2026-10-01)

This section supersedes earlier descriptions of the title, site-2 prizes,
site-3 shaft, sprite allocation, audio timing and current budgets. Both TI-99/4A
and ColecoVision remain required targets of the shared CVBasic source.

**Reference scope:** the supplied [Apple II video](https://www.youtube.com/watch?v=HwHZ-18Zgvg)
is 89 seconds and shows only site 1. It supports the white hat/purple clothing,
green/white columns and elevator cage. Existing `HHM-CV-Level2.png` and
`HHM-Level3.png` supply the later visual references. Later-site movement is
checked against the implemented geometry, not inferred from that video.

### Changes

- The title defaults to site 1 and offers up/down starting-site selection.
  Fire must be released before starting. Game over returns here; high score
  survives. Three starting lives and normal site progression remain.
- Site 2 has six red/white, two-cell lunch pails; collection erases both halves.
  Its lower conveyor and mixer return to reference columns 5/9 and 10/11.
  `belt_surface` follows the actual 2:1 incline with flat roller ends, clamps
  both ends, and avoids multiply/divide register hazards. Crane drawing follows
  simulation so the bar and rider use the same current position.
- Site 3 has two circulating 24-pixel paddles instead of a ladder and fixed
  stubs. A 240-step rectangular circuit runs from (96,144) up to (96,64), across
  to (136,64), down to (136,144), and back. The second paddle is 120 steps ahead.
  `beam_sup` dispatches to paddle support on site 3; `beam_move` carries a rider
  horizontally and vertically. Fire detaches the rider. The site-2 sticky
  support shortcut is disabled for these narrower paddles. Shaft tiles 208/209
  are scenery; ordinary chains remain climbable.
- Sprite 8 adds purple clothing to Mack's white hat/skin/boots; sprite 9 draws
  the cage. Slots 10-13 draw paddles. Teardown hides slots 0-13. Patterns 15-19
  contain matching clothing poses, 20 the paddle, 21 the cage. Machine tiles
  210-219 form each broad IN hopper; 220-223 form the door. Ground-level delivery
  regions are independent of the artwork's character codes.
- Frame-clocked sound envelopes provide jump/spring sweeps, two-pitch pickups,
  a falling death tone and a four-note clear phrase, all with note-offs. These
  are PSG adaptations, not a verified transcription of Apple II sound. Hammer
  holds and death pauses also use frame deltas. Conveyor pattern animation
  remains one phase per animation tick to avoid aliasing.
- Setup/parser code moved into the permanently selected TI asset page; runtime
  movement remains fixed. No bank switching occurs during play.

### Current budgets

| Area | Used | Free / limit |
|---|---:|---:|
| TI fixed program | 20,936 B | 3,400 B / 24,336 B |
| TI setup/assets, excluding trailer | 7,817 B | 373 B / 8,190 B |
| TI variables | 326 B | 7,528 B / 7,854 B |
| Coleco ROM | 24,576 B | 8,192 B / 32,768 B |
| Coleco variables | 318 B | 496 B / 814 B |

The permanent page is now the tight budget. Additional setup/art must pass
`checkbank.py`; a successful compiler exit is insufficient.

### Verification and limits

Both target builds pass their gates. TI assembly was inspected for the 16-bit
second-paddle phase addition and belt surface routine. The checker now executes
real moving-surface routines rather than stubs. It parses all three level streams
into a name table, checks every pail/box objective, two lift circuits, twelve
transfers to side platforms and both spring entries, plus the earlier movement,
inventory and frame-delta sound tests. Nine negative mutations must fail,
including bad belt-end geometry, rider drift and a missing sound note-off.
Transfer tests place Mack at controlled takeoff positions; these are not full
autonomous play-throughs.

All three sites were rendered in Classic99 and CoolCV. Title selection works
on both; TI checks include conveyor traversal and a spring launch onto the
lower-left site-3 platform. Full uninterrupted clears, hardware timing profiles
and listening comparisons remain outstanding. The conveyor box on site 3 is
still stationary; escalating loop difficulty and original music remain open.

`LaunchTI` leaves one production Classic99 instance at the normal title with
site 1 selected. Later sites can be reviewed through the production title,
without source edits or special starting-level cartridges. `LaunchColeco` uses
the locally installed CoolCV. Its SDL input needs scan codes and extended arrow
flags when driven through Windows key events; virtual-key-only events can
deliver no game input despite a live, correctly captured emulator.

## §16 All-level reference and playability corrections (2026-10-01)

This section supersedes sections 14-15 where they disagree. Changes remain shared
between ColecoVision and TI-99/4A. The previous repair is commit 0649a17; this pass
follows the newly supplied longplay and direct playtesting feedback.

### Evidence and its limits

The [Apple II longplay](https://www.youtube.com/watch?v=zanShXo4btw) shows the first
site at 0:07, lunch site at 0:50, and factory at 2:18. Sequences around 0:51-0:54
show the first conveyor/crane entry; 2:36-2:38 show crates dropping from a floor
lip into a processor; 2:18-2:46 show the factory start, paddles and chain descents.
The [original C64 card](https://www.mocagh.org/ea/hhmack-refcard.pdf) confirms the
single extra-life award at 7,000 points. It describes a different port, so its
details do not automatically override the video or user requests.

The video has no input overlay and cannot prove how a released joystick affects
an airborne character. Our earlier code deliberately copied walking direction
into locked fall momentum. That caused the reported sliding falls. Walk-offs now
fall vertically on every site, including leaving a parked elevator or chain.
Deliberate jumps retain their chosen direction through their remaining descent.
This distinction is tested, rather than claimed as an exact reconstruction of
the original keyboard controls.

The magnet stays parked until all six lunch pails are collected, as requested.
Bonus tools are optional. Earlier video observations suggested continuous magnet
movement; they are not the behavior selected here. The crane waits for its first
rider, then continues its cycle.

### Site mechanics

- **Site 1:** repositioned pieces, an independent 18-waypoint drill circuit,
  fixed upper-right rivet thrower with speed/bounce variants, and a jump-operated
  bell that summons/reverses the elevator. The vandal begins on the bottom beam
  and surveys it before climbing. Death restores deposited but unriveted pieces
  to their own pickup slots; riveted gaps remain. Piece pickup/filling/riveting
  award 10/25/35 points; ringing the bell gives 10.
- **Site 2:** pails occupy upper-left, both middle, both lower and ground
  positions. Added optional bonuses, timed pincers, pounder, hazardous mid-left
  obstruction, dynamite, furnace and vat. Concrete drops from the spigot,
  travels with the belt and falls toward the vat; it is absent for half the
  128-step cycle. The old backwards/upwards trajectory blocked entry. The enemy
  walks and climbs between ground and lower-right tier. After the sixth pail,
  the magnet moves, catches airborne Mack and carries him to the crane top.
- **Site 3:** Mack begins upper-right. Four 16-pixel paddles follow a 224-step
  loop: (104,64) down to (104,144), right to (136,144), up to (136,64), then left.
  They are spaced 56 steps apart. The shaft is scenery. Boxes auto-drop from
  the lips of the lower-floor gaps and visibly fall into the processors;
  walking on the ground is not a delivery method. A box awards 25 for pickup,
  25 for dropping and 25 for processing. Springs transfer Mack across the site
  and launch him onto the opposite lower platform. The toilet, processors and
  conveyor crusher are hazards. The conveyor crate stays stationary, as shown
  in the video. Both enemies patrol and climb between their two side tiers.

Stage numbers continue 4, 5, 6 when the sites repeat. Increased enemy counts and
full later-loop escalation remain unimplemented. This pass does not claim exact
original jump timing, rivet trajectories, music or PSG sound matching.

### Movement and rendering corrections

The reported upper-left factory soft-lock was reproduced at `(mx,my)=(28,58)`
while carrying a box. `st_walk` grabbed the short chain using `my+1`, but the
following `st_climb` only checked `my+7` and `my+15`; both missed the chain at
`my=57`, leaving Mack stuck. Ascent now also checks `my+1`. A regression runs
the head-only grab all the way to the roof, with a carried box, and rejects the
old missing-head-probe variant.

Normal jumps retain the previous repair's 32-step, 11-pixel arc/hold. A ceiling
collision now caps height while preserving horizontal clearance time. Previously
it removed the hold and shortened the jump so much that Mack could not cross
from the lower conveyor to the crane. The spring ascent clears the opposite
ledge before drifting outward, avoiding an underside collision. Spring capture
also runs when a falling step crosses its height, before a ground hazard kills.

A parked elevator draws its cabin as four background characters as well as
sprites. `elev_back` remembers their VRAM address, erases them when movement
starts, and repaints at the next stop. Tiles reuse the editable `cage_bitmap`
through `DEFINE CHAR`; placement accounts for its left/right column byte order.
There is no duplicate generated art table. The shaft cells are otherwise empty,
so erasing them does not destroy chains or platforms. Character codes are outside
the solid band; boarding still uses the elevator's geometric support.

Patterns 22-24 hold the steel box, magnet and pounder. Character 224 is the bell,
225-226 the pincers, and 227-230 the parked cabin. The magnet's stem is part of
its own sprite and stays below the HUD; the separate cable overlapped the score.
Teardown hides all slots through 17 and resets per-level machinery state.

### Budgets and verification

| Area | Used | Free / limit |
|---|---:|---:|
| TI fixed program | 24,246 B | 90 B / 24,336 B |
| TI setup/assets, excluding trailer | 8,008 B | 182 B / 8,190 B |
| TI variables | 408 B | 7,446 B / 7,854 B |
| Coleco ROM | 24,576 B | 8,192 B / 32,768 B |
| Coleco variables | 398 B | 416 B / 814 B |

Both builds pass truncation, return-stack and physics checks. The TI packer
verifies exact preservation of the permanent asset page. TI assembly inspection
covered the cabin address, four-paddle phase and coordinate calculations. Cabin
addressing uses shifts and a full-word 6144 addition, without stale MPY state.

The BASIC interpreter executes source routines and actual maps, rejects unknown
executed statements, and supports indexed READs and deterministic random choices.
Expressions are compiled once per interpreter; values and array reads remain live.

Coverage includes all objectives, death rollback, safe/lethal hazard windows,
magnet arming and final ride, drill/enemy routes, 448 rider steps, twelve outward
platform transfers, both spring transfers, jump clearance, vertical walk-offs
on all three sites, sound note-offs, and cabin paint/erase at both stops. A live
level-2 route walks from the production spawn, jumps onto the belt and then onto
the crane with all hazards/enemies enabled: seven of eight sampled hazard phases
succeed. The six factory side tiers are swept at fourteen lift phases each for
transfers onto the paddles; each has at least two successful sampled phases.
Eighteen deliberate bad mutations must fail, including restored walk-off drift,
the short ceiling jump and failure to erase the cabin.

All three screens were inspected in Classic99 and CoolCV during this repair.
Controlled movement tests do not establish uninterrupted whole-level clears,
CPU performance on original hardware or a listening comparison. The production
title permits later-site review without altered starting cartridges.


## §17 Conveyor, pincer, collision and visual review (2026-10-01)

This section supersedes conflicting details in §16. The additional reference is
[the C64 longplay](https://www.youtube.com/watch?v=WSbEDNtmQWY), 3:21 long. Review
covered the loose/carried girders and elevator (0:16-0:55), conveyor entry and
machinery (1:02-1:51), magnet finish (2:06), and factory transfers and deliveries
(2:17-3:00). The Apple II recording was rechecked at 0:07-0:13, 0:52-0:55,
1:25-1:27, and 2:36-2:38. Local frame sheets and measurements are in ignored
`scratchpad/hhm-review/`; downloaded videos are not repository assets.

### What the footage supports

Loose girders are narrow diagonal pieces with bright metal edges and a colored
web, rather than irregular red lumps. The redesigned one-cell pickup preserves
its established collection location and adds that readable silhouette. The C64
conveyors have continuous white rails and circular rollers; the factory belt has
a straight framed track. `assets/genconveyors.py` generates eight distinct tread
and roller phases without changing the belt geometry. The generator also supplies
the paired pincers and rejects stale or damaged generated data during each build.

At Apple II 0:52-0:55 the nozzle releases a lump downward. It lands **on top** of
the belt, travels toward the upper roller, then arcs toward the vat. The former
trajectory put its visible lower edge below the belt, and used the tiny rivet
sprite. Two dedicated six-pixel lump frames now tumble above the surface. The
surface regression compares the rendered lower edge with the actual `belt_surface`
routine throughout the roll, permitting at most one pixel of rounding difference.
The nozzle is visible above its release point. Only one lump is active at a time:
this is an intentional playability adaptation; the recordings sometimes show two.

At Apple II 1:25-1:27 the pincers are a **pair of sliding jaws**, opening a gap and
then meeting, not a single stationary block. They now occupy five characters
at row 16, columns 5-9. Four positions move both jaws inward and outward; the two
lethal regions follow the drawn jaws. The open center is safe, as is a jump that
visibly clears them. White tips and green feet make the motion readable. Pattern
uploads happen only when the pincer pose changes and require no sprites.

### Speed review

Video pixels are not directly interchangeable with our 256×192 coordinates.
Measured on 512×384 decoded frames, the Apple II carried-Mack position moves about
48 pixels left from 0:10.0 to 0:10.5 over a roughly 292-pixel beam span. Scaling
that span to our 192-pixel girder gives about 63 pixels/second. C64 0:17.0-0:17.5
moves about 36 pixels over a roughly 250-pixel span, or about 55 pixels/second on
the same basis. The ports therefore do not supply one identical speed target.
Keep the established 67.5-pixel/second walk/chain pace, close to the Apple II sample,
instead of globally slowing the already improved controls to the C64 recording.
These estimates use visible positions and layout normalization, not original code.

The Apple II lump takes roughly 0.8-1.0 seconds to traverse its lower belt; ours
previously took about 0.4 seconds. Belt transport and lump rolling now advance one
pixel per **two** world steps. The belt pattern phase uses the same clock and is
reversed on the factory belt. Normal walking input adds Mack's own motion, so he
can walk against or with a conveyor. The eight-phase animation advances at most
three phases across a clamped four-frame catch-up pass, below the half-cycle alias
threshold; no separate render-pass timer controls its speed.

Apple II 2:36.25-2:36.75 shows a delivered box falling visibly from the lower gap
toward the processor. Ours crossed its 40-pixel path in fourteen steps, about 0.21
seconds. It now descends one pixel per world step, taking 40 steps/about 0.59 s.

Current nominal rates at 60 Hz NTSC (world clock = 9/8 video frames):

| Actor or item | Rate / duration | Status |
|---|---|---|
| Mack walking, climbing, deliberate jump drift | 67.5 px/s | retained; Apple II comparison above |
| Normal jump | 32 steps / 0.474 s, 11-pixel apex | retained gameplay adaptation |
| Site-1 vandal and independent drill | 67.5 px/s along their routes | retained; common world clock |
| Site-2/3 enemies, walking and climbing | 33.75 px/s | retained, tested half-rate |
| Elevator and crane | 67.5 px/s when active | retained, tested |
| Factory paddles | 67.5 px/s, 224-step / 3.32 s circuit | retained, corner/rider tests |
| Unarmed magnet / static pickups | stationary | intentional user-requested magnet rule |
| Armed magnet search / carrying Mack | 33.75 / 67.5 px/s | retained, tested |
| Conveyors and rolling lumps | 33.75 px/s | corrected from full-rate transport |
| Lump drop / final descent | 33.75 / 67.5 px/s | corrected; 136 active + 120 quiet steps |
| Pincers | 96-step / 1.42 s cycle | four poses, symmetric opening/closing |
| Site-2 pounder | 67.5 px/s moving; 128-step cycle | retained; corrected contact position |
| Site-3 pounder | 22.5 px/s descent, 128-step cycle | retained; corrected contact position |
| Thrown rivet | 67.5 or 135 px/s left; 135 px/s vertical | retained variants; corrected visible bounce/contact |
| Delivered factory box | 67.5 px/s / about 0.59 s | corrected from 202.5 px/s |
| Site-3 spring transfer | 36 steps / 0.53 s, then ascent | retained route adaptation |

A source-executing gate verifies movement budgets under 1-, 2-, 4-frame and mixed
frame passes, plus walking, enemy walking/climbing, elevator, crane, magnet, belt
and box-drop rates. Existing tests cover jump duration, drill route, spring paths
and paddle circuits. This validates this implementation's rates; it does not claim
that every original autonomous actor has been timed precisely from the recordings.

### Lethal collision regions and elevator lifecycle

No supplied video exposes the original internal hitbox dimensions. Contact timing
can reveal suspicious behavior, but cannot prove the original collision algorithm.
The audit instead checks our source-defined lethal bounds against our actual art.
`mack_hit` compares distances between reference points: `hbw`/`hbh` are thresholds,
**not** the width/height of a sprite. Its hazard reference point must align with
Mack's visible torso. Reusing raw sprite origins misplaced the small rivet, and
adding eight to the pounder origin displaced its lethal region below its head.

The revised rivet thresholds are 4×7 (distance limits), lump 5×7, pounder 6×8 and
each jaw 4×6 (revised in §18). The pounder's narrow support stem is scenery; its striking head is
lethal. A sweep checks every nearby integer Mack position against bounds extracted
from the editable hazard bitmap, rejects kills across empty space, and also checks
that direct contact remains lethal. The jaw bounds come from all five generated
character tiles. This is forgiving body-box collision, not expensive per-pixel
runtime collision. Enemy distance limits remain 8×10; their bottom-anchored art
already matches Mack's vertical origin. Static scenery and fatal falls retain
their existing rules; these have not been reconstructed from original machine code.
Rivet floor detection now uses the visible bottom at `by+9`, rather than the empty
bottom of its 16-pixel sprite cell.

The parked elevator paints a 2×3 character area: four cage cells plus two floor
cells. Both erase at the remembered old address when movement starts. Floor cells
236-237 reuse the existing platform art, in the pass-through scenery range; using
solid codes 135-136 would bypass geometric elevator boarding. Regression coverage
walks onto the character-backed floor and verifies that the trip actually starts.
Game over hides actors and redraws the elevator pair, preserving a full frozen
cabin even between cell-aligned stops. Both parked endpoints and a moving position
are covered. Cage/floor pixels are shared with their normal sprite art.

### Build and runtime verification

The new art uses character codes 231-232 (spigot), 238-242 (pincers), 236-237
(parked floor), and sprite patterns 25-26 (lumps); parked cage codes remain 227-230.
The permanent data bank remains selected throughout gameplay. Conveyor animation
uses an indexed pointer into contiguous 48-byte frames, replacing eight repeated
branches. TI assembly was checked: both animation offsets use the low product word
and add the correct bank label, without stale-register multiplication state.

The TI build reuses Keystone Kapers' conservative short-branch optimizer. It first
assembles unoptimized code, shortens only proven in-range branches, reassembles,
and verifies every changed opcode/destination and the full address shift map.
The fixed-size cap and exact packed-bank verification remain mandatory; no budget
threshold was relaxed. The shared compiler is unchanged. Proven unused historical
route assignments were also removed.

Runtime review also exposed an initial crane-cable gap: the cable stream ended at
row 12 while the parked beam started at row 20. It now reaches row 19, and a
source-executing check verifies continuity over a full up/down trip.

| Area | Used | Free / limit |
|---|---:|---:|
| TI fixed program, optimized | 22,278 B | 2,058 B / 24,336 B |
| TI fixed program, before branch shortening | 24,290 B | 46 B / 24,336 B |
| TI permanent setup/assets, excluding trailer | 8,108 B | 82 B / 8,190 B |
| TI variables | 402 B | 7,452 B / 7,854 B |
| Coleco ROM | 24,576 B | 8,192 B / 32,768 B |
| Coleco variables | 389 B | 425 B / 814 B |

The short-branch pass verifies 503 replacements, saving 2,012 bytes. Its need for
a valid first assembly still limits future unoptimized growth; the optimized free
space should not be mistaken for unconstrained room to add BASIC code.

Both builds pass all gates and 28 deliberate defect mutations. Six of eight
sampled immediate spawn-to-conveyor-to-crane runs succeed with live hazards;
the others require waiting for the nozzle's quiet interval. The threshold remains
at least six successes. All six factory lift-entry tiers retain usable windows.
Controlled tests also verify complete parked-floor erasure, actual boarding,
correct moving/parked elevator display at game over, visible hazard bounds,
conveyor animation direction, box-drop speed and continuous crane cable.

Classic99 and CoolCV review covers the new girders, paired pincer poses and conveyor
art. The parked elevator remains complete on the observed TI game-over screen.
A full uninterrupted clear, exact original hitbox reconstruction, comparative
listening test and physical-hardware performance measurements remain unverified.
The latest production TI cartridge is the handoff, with normal title selection.

## §18 Block shapes, pincer passage and activity audio (2026-10-02)

User review rejected the thin diagonal loose-piece glyph. Character 185 now has
a broad seven-row brick face, staggered joints and a white top edge. The carried
block already used a broad brick silhouette. Shape takes priority over the
earlier attempt at diagonal red/white striping.

The previous pincer art did not actually close: its tips stopped four pixels
apart, and the fully open gap was only sixteen pixels. Five character cells now
give a 32-pixel open gap, with tips meeting at adjacent pixels 19 and 20 in the
closed pose. Each jaw moves sixteen pixels. Character codes 238-242 avoid the
parked elevator floor at 236-237. Collision references follow the jaw motion;
the distance thresholds are now 4×6, allowing a slight shoe/edge graze while
keeping body contact lethal. The earlier 5×8 bounds made the approach from a
crane level with the ledge impossible even with the jaws fully open.

The byte clock wraps after 256 world steps (about 3.79 seconds at 60 Hz): poses
advance every sixteen steps, pause closed for 32 steps and remain fully open
across the wrap for 160 steps (about 2.37 seconds). This gives time to jump over one jaw, land in
the opening, and jump over the other. The regression uses the real level-2
ledge and overhead platform, with live pincer timing, in both directions and at
eight starting phases. At least three phases must permit the complete two-jump
crossing; forcing the jaws shut must fail. Art checks require an actual touching
closed pose and at least 32 clear pixels when open. A second test starts on
the moving crane at heights 128, 136 and 144 and requires six of eight launch
phases to permit both jumps across the ledge. This reproduces the actual crane
approach, rather than only starting Mack on the ledge.

The conveyor and concrete movement speeds are unchanged, following the user's
correction. Release spacing changes from 256 to **317 world steps** (about 4.70
seconds), with the same 136 visible steps and 181 quiet steps. The word-sized
clock avoids byte wrap. The crane completes a trip in 238 steps, so the release
phase now shifts 79 steps relative to its trip instead of only eighteen. A live
five-trip simulation verifies both occupied and quiet belt intervals at repeated
crane arrivals; restoring the old release period is rejected.

Activity audio adds short noise-channel shoe scuffs every eight pixels of active
walking, jackhammer chatter every eight world steps while held, rivet bounce
clacks, pincer closure and pounder strike cues. Existing tone-channel jump,
pickup, score and death effects continue independently. Footsteps last two video
frames; mechanical clacks last three. The longer riveting noise takes priority.
Standing, pushing against a boundary, jumping, or passive conveyor transport
does not produce footsteps. Frame-delta decay and `quiet_screen` explicitly
silence the noise channel, including transitions and game over. These are PSG
adaptation cues, not a verified transcription of original audio.

Sound decay now runs at frame start, before new events. Previously a busy pass
could subtract four elapsed frames from a just-started two-frame effect and
silence it before the next vertical blank. A test executes the real frame-start
and render-tail paths and rejects that ordering. Machine impacts may replace a
footstep; the longer riveting effect retains priority.

Holding Fire for 45 video frames (0.75 seconds at 60 Hz) releases the jackhammer
and returns it to its spawn; this existing control is now explicit in README.
Eight identical collision/death call sequences share `hazard_hit`, preserving
the collision logic while reclaiming fixed-program space for sound.

Both current platform builds pass all gates and **36 deliberate defect mutations**.
The source-driven crane approach passes six of eight sampled phases at each of
the three heights, with live hazards. TI assembly review confirms the 317-step
word comparison, division into a byte phase, jaw offset multiplication and
40-byte animation stride use the correct values. No movement-speed constants
changed. Classic99 and CoolCV show the new block shape; a CoolCV capture of a
full pincer cycle confirms touching tips and the extended open pause. Full
uninterrupted clears, physical-hardware timing and listening-based audio balance
remain unverified.

| Current area | Used | Remaining |
|---|---:|---:|
| TI fixed program, optimized | 22,428 B | 1,908 B |
| TI fixed program, unoptimized | 24,452 B | 116 B over the normal cap |
| TI permanent setup/assets | 8,182 B | 8 B |
| TI variables | 406 B | 7,448 B |
| Coleco ROM | 24,576 B | 8,192 B |
| Coleco variables | 393 B | 421 B |

The optimizer verifies 506 branches, saving 2,024 bytes. The first assembly still
fits the address space, but the unoptimized comparison build intentionally fails
the unchanged 24,336-byte production gate. Pincer-clock initialization moved to
a small fixed-area routine to keep the expanded artwork inside its data bank.

## §19 Continuous pincers and character smasher (2026-10-02)

This supersedes §18's long open hold. The pincers now have **17 distinct poses**,
one for every pixel of their sixteen-pixel travel. The 128-world-step triangular
cycle moves one pixel every four steps, closes completely and reverses without
an endpoint dwell. A full cycle takes about 1.90 seconds at 60 Hz. The maximum
opening remains 32 pixels; the forgiving 4×6 body-contact limits are unchanged.
The closure sound occurs at step 64. A source-driven regression verifies all
seventeen poses, unit movement, wrap continuity and no five-step plateau.

Both smashers use six background characters (243-248): level 2 places them in
rows 14-16, columns 23-24; level 3 in rows 6-8, columns 7-8. Their heads now span
fourteen pixels across the two character columns, with a centered piston.
The mounting bracket stays below the upper beam and its piston lengthens
downward. The striking head retains level 2's 32-position stroke and level 3's
16-position stroke. On level 2, the upper beam conceals the retracted head and
the lower floor clips its bottom; level 3's head stays visible throughout.
Sprite 14 is hidden on both levels, freeing that scanline slot. Only visible head contact is lethal: a retracted
head, shaft or contact outside the exposed vertical region cannot kill Mack.
Tests cover every smasher pose and nearby player height, actual pattern/color
uploads, shaft continuity, lethal head contact and bank restoration.

The horizontal hit threshold widens from six to eight pixels and shifts to the
centered head on both sites; vertical motion/timing remains unchanged. Tests
require lethal contact at both outer edges as well as the center. On level 3,
the conveyor box remains in front of the machine until collected. The renderer
restores its background cell after pickup, without changing other boxes or the
item's collision/pickup rules. The old narrow smasher sprite is no longer used.

Traversal checks retain the previous numeric acceptance gates. The continuous
cycle requires timing rather than exploiting the former long pause. For the
crane approach, tests try immediate departure and waiting on the *moving* crane
until it is eight pixels above the ledge; six of eight phases must succeed from
each initial height. All clocks and hazards remain live during that wait.

The additional animation frames and rendering routine occupy TI bank 2. A fixed
wrapper selects it, calls the renderer, then restores bank 1 before returning.
Bank 1 still holds level data, setup and other assets. Both pages are checked
byte-for-byte against the packed image; missing or damaged animation pages fail.
The TI cartridge is now padded to 64 KB using the existing banked-cart hardware
and linker. The fixed-program cap remains 24,336 bytes and neither data page may
exceed 8,190 bytes. Coleco retains its unbanked configuration; validation of that
target is deferred at the user's request while TI gameplay is being refined.

Latest TI validation: all 42 defect mutations were rejected, all source-driven
physics checks passed, and 53 GOSUB targets passed return-stack checks. The
optimized fixed program uses 22,336 of 24,336 bytes (2,000 free); setup/assets
use 8,050 of 8,190 (140 free), and animation uses 4,054 of 8,190 (4,136 free).
RAM use is 408 bytes. All 507 optimized short branches were verified. Generated
assembly correctly writes level 3's restored machine cell at VRAM address 6407.
Classic99 captures of the latest production cart show level 3's wide head in
retracted and extended positions, with a connected piston and the conveyor box
preserved in front. This is a visual smoke check, not a whole-level clear or a
measurement on original hardware. Current-pass builds and runtime review are
TI-only; no claim of current Coleco validation is made.

## §20 Squeezer clearance and complete smasher strokes (2026-10-02)

This supersedes §19's squeezer placement and smasher travel. The old closed pose
joined only the upper three rows of the jaws; its lower half still had a gap.
All six visible rows now meet. The open gap stays 32 pixels. One-pixel movement
still takes four world steps, with no added endpoint hold: the cycle is 128 steps,
about 1.90 seconds at the nominal 67.5 world steps per second. The contact box
is unchanged. In addition to the existing passage and crane-entry gates, the
checker requires both two-jump directions to succeed across a roughly half-second
launch window while opening, including a 12-step (~178 ms) stationary pause
between landing and pressing jump again. All world hazards advance during this
test. Restoring the lower jaw gap must fail the art regression.

The Apple II longplay at 1:33-1:36 shows the crane-to-right-ledge staging, jump
into the opening, and second jump toward the pail. The pair now occupies row 16,
columns 4-8 (pixels 32-71), leaving sixteen clear pixels at the ledge's right end
(72-87). The previous columns 5-9 left only eight pixels. Collision references
move left by the same eight pixels. Tests require that full waiting space and
verify stationary survival there throughout a complete jaw cycle. The lower
ledge also supports a shoe still touching its right edge, rather than requiring
the sprite midpoint to remain above it; a position with both shoes beyond the
edge must remain unsupported.

The crane-entry test now follows the complete intended journey: leave the rising
girder as it reaches the lower ledge, stop at the right waiting spot, wait until
the jaws visibly open, and make two jumps with a short re-press pause. It verifies
the pail is actually collected. All actors and hazards run, across three starting
girder heights and eight jaw phases; the existing six-of-eight gate is retained.
The old test's immediate two jumps from the crane skipped the waiting spot.

The rising girder could pass through Mack during the jump's apex hold because
landing checks ran only during descent. `beam_move` now catches a surface crossing
at the feet during the apex/fall, then carries him normally. It rejects approaches
from underneath and positions outside the drawn span, and leaves the upward part
of takeoff alone. Tests cover both girder edges and several heights, plus negative
underside/outside cases. Removing the moving-surface catch or shoe-edge support
must fail; moving the jaws back to the old cramped position must also fail.

The level-2 head previously sank into the girder at the end of its stroke;
level 3 stopped seven pixels above its belt and teleported upward. The new
stroke limits put each four-pixel head directly on its supporting surface:

| Property | Level 2 | Level 3 |
| --- | --- | --- |
| Head top, retracted / extended | 104 / 132 | 48 / 70 |
| Extended head bottom / surface top | 135 / 136 | 73 / 74 |
| Moving speed, down and up | 1 px/world step | 1 px/2 world steps |
| Nominal moving speed at 60 Hz | 67.5 px/s | 33.75 px/s |
| Time to full extension | 28 steps (~0.415 s) | 44 steps (~0.652 s) |
| Repeating cycle | 128 steps (~1.90 s) | 128 steps (~1.90 s) |

Level 2 retains its prior moving speed. Level 3 completes the longer stroke in
roughly its former descent time, then visibly retracts at the same speed.
These are port tuning choices, not measurements of the original game's speed.
Impact sound occurs when the head first reaches the surface (phase 28 or 44).
Tests sample the complete cycle, reject return jumps, verify actual head contact
and ensure the full-extension dwell is at most ten steps.

Level 3 adds characters 249-250 at row 9, columns 7-8. Their top two rows carry
the last two pixels of head travel; the lower six rows retain the conveyor's
eight animation phases and its original support geometry. Generated pattern
and color data live in the animation bank. The nearby collectible remains in
front of the piston until picked up. No player speed, jump arc, belt speed or
glop timing was changed. Validation remains TI-only.

The extra collision code exposed the documented TI first-assembly limit:
unoptimized fixed code crossed the 16-bit address boundary before branch
shortening could run, despite space in the final optimized image. The unchanged
title-screen body now lives alongside the animation code in bank 2. Its fixed
wrapper selects that bank and restores bank 1 on return. This leaves the gameplay
code fixed, preserves normal title/start-site selection and avoids changing the
compiler or relaxing a size gate.

Final TI validation: all 49 defect mutations were rejected; all platform,
inventory, physics and sound checks passed; all 54 GOSUB targets unwind. The
517 verified short-branch optimizations save 2,068 bytes. Fixed code is
22,102/24,336 bytes (2,234 free); the unoptimized comparison is 24,170 bytes
(166 free). Setup/assets use 8,060/8,190 bytes (130 free), and the animation/title
bank uses 5,268/8,190 (2,922 free). RAM use is 414 bytes; the cart remains 64 KB.
The generated TI assembly was inspected for the swept-contact comparisons,
title bank selection/restoration, and conveyor/head frame offsets.

Classic99 captures of the production cart show complete jaw closure, the wider
right waiting area, both smasher strokes and retraction, and the level-3 head
touching the belt rail without erasing it. The title can still select both sites.
The complete pail journey is covered by source-executed regression tests; this
runtime visual review does not claim a manual whole-level clear. The newest
production cart was left running on level 2 in one Classic99 window. No Coleco
build or runtime check was performed for this pass.
