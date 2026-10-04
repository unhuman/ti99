# Hard Hat Mack — Design (CVBasic, dual-target TI-99/4A + ColecoVision)

> **Current status (2026-10-02): TI-99/4A validation only; ColecoVision is paused at the user's request.**
> Section 16 supersedes earlier mechanics, budgets and verification notes.
> Older sections remain as implementation history; README describes current play.
> The construction title and hidden 838 setup are implemented; title music remains a design goal; repeat tours have two random enemies.

## Current performance budget

The renderer uses slots 0-17 for Mack, clothing, carried objects, actors and site
machinery. Not all are active on each site. The TMS9918 four-sprites-per-scanline
limit still applies; parked elevator cabins also have name-table backing.
Real-time FRAME delta, clamped to four, feeds a 9/8 accumulator: at most five
one-pixel world steps per pass. All gameplay movement now uses those steps.
Ordinary walking makes at most eleven tile reads per step (chain probes + feet +
torso); a spring ascent can make ten head probes per step. The intended ceiling
is **60 tile VPEEKs per pass**, including bolts, with no COINC calls. This is a
budget, not a measured throughput claim. Section 39 records the current
Classic99 timing samples. No RAM tile-map mirror; level data and graphics
remain in ROM/VRAM.

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
**wrench** (4,21) and **spray can** (20,16) = +200 each. Mack spawns at
(21,25), one cell right of his prior position; the spray can sits two cells
right of the middle pedestal (column 14), away from the spawn.
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
(4–20, homing in Mack's band). Mack spawns on the **right side of the 1st floor** (21,24),
one character to the right of the column-23 vertical support.

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

**The trampoline pads (chars 139-142)** are how you get up from the ground. Each
is two characters wide at row 22, one row above the ground, with the catch and
launch positions raised alongside the artwork. The current route
compresses the starting pad, bounces Mack across to the other pad, compresses
that pad, then launches him onto the opposite lower platform. Both compressions
share level one's four-pixel cap displacement and eight-step rebound. Landing
on either pad is never fatal. See §30 for the animation and validation.

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
2. **Historical workaround, removed in section 23:** the box on the conveyor could not be collected. The only way onto the belt was the chain at
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

## §21 Game-over input delay (2026-10-02)

The game-over wait is now 75 video frames (1.25 seconds at 60 Hz), reduced from
180 frames. The existing release-then-press requirement remains: holding Fire
through the delay does not dismiss the screen until it is released and pressed
again. The elevator-preservation regression stops at the updated delay boundary.

## §22 Chain access, machinery art and 838 setup (2026-10-02)

The Apple II longplay at 1:22-1:24 shows the bottom-right chain accessible from
clear ground, with the ground hazard farther left. Our flame occupied row 22,
column 23 directly under the chain. It now occupies column 21, leaving the chain
approach and the two-cell ground pail clear. Up can grab chains while jumping or
falling; Fire must be released first so jumping off does not immediately reattach.
The same head/torso probes serve grounded and airborne grabs on all three sites.
This is a port control choice; the recording does not expose the original inputs.

The level-2 spray can is a 200-point bonus, previously overwriting the right
machine's stand. It moves from row 22, column 17 to column 16. Both support cells
remain intact before and after collection. The top wrench remains a 200-point
bonus; its crane-top jump route is unchanged by this pass.

Level 2 now parks its smasher at pressy=104 (visible head y=112-115), rather than
hiding it above its character area. It still bottoms at y=132-135, moves one pixel
per step, and strikes at phase 28. The top hold spans the wraparound phase interval
56..127,0..8. Level 3 retains its visible y=48-51 top hold and full y=70-73 extension.
Both heads use white/magenta/light-red/dark-red rows that travel with the head.
The factory's extra two rows select matching colors by depth while preserving the
belt's rails, treads and support. Level-2 girder rivets occupy the middle two body
rows; all eight moving-girder offsets preserve those marks across tile boundaries.

GAME OVER has an eleven-by-three-character cleared area around its nine-letter
message, with one blank character on every side. Its input delay remains the new
75 frames (1.25 seconds at 60 Hz).

The title no longer offers Up/Down level selection. Fire starts three total lives
at level 1. The hidden sequence 8,3,8 opens lives 1-9 followed by level 1-3; valid
last input starts immediately. Invalid selections are ignored, held keys cannot
answer the next field, and an incorrect code digit resets the sequence. Choices
reset on the next game. Setup runs in the animation/title bank and unwinds through
the existing wrapper, restoring bank 1. The reserve hats move to row 1, columns
22-30, supporting eight starting reserves plus the earned extra life, without
overwriting scores or the level number.

Regression coverage includes the actual map's clear chain approach, grounded,
jumping and falling grabs, held-Fire rejection, complete ascent, spray-can pickup,
intact supports/pail, all 27 setup choices and matching reserve hats. Full-cycle
machinery tests verify visible top holds, continuous travel, colored tile seams,
lethal head bounds and retained conveyor pixels. New negative cases restore the
blocked chain, missing airborne catch, overlapping can, hidden head, incorrect
reserve count and repeated held digits; each must fail.

## §23 Repeat-tour enemies (2026-10-02)

Review of the Apple II longplay around 3:28-3:47 (stage 4), 7:00 (stage 7),
and 10:40 (stage 10) shows two roamers and different pairs, including matching
vandal/inspector types. The video establishes those combinations, not the random
number algorithm. This port independently draws each type when stage 4 or later
starts. The initial three sites retain their existing cast. Repeated sites have
two enemies, with no additional speed multiplier or third enemy.

The second enemy on site 1 starts on the second beam and runs its own copy of the
full serpentine walk/climb route, including the terminal-floor patrols. On site 2
it starts on the lower-right ledge, offset from the ground enemy, and shares the
existing chain route. Site 3 retains its left/right routes. Type choices control
the actual sprite shape and color independently of route ownership. Both actors
remain lethal and their positions/route state reset on death without rerolling.

Enemy updates and sprite drawing now reside in bank 2, with fixed wrappers that
restore bank 1; this leaves room for the second route's state and avoids the
unoptimized fixed-code address boundary. No extra sprite slots are required.
Tests execute the stage-3-to-4 transition, all four type pairs on all sites,
per-step movement, visits to every routed tier, both contact hazards, death reset,
and bank restoration. Negative cases remove the second-tour activation, force
identical types, and corrupt the second roamer's tier state; each must fail.

Final combined TI gate: 58 deliberately defective variants rejected; 61 GOSUB
targets unwind; 507 shortened branches verified (2,028 bytes saved). Fixed code
uses 21,730/24,336 bytes (2,606 free); unoptimized fixed code is 23,758 bytes
(578 free). Setup/assets have 124 bytes free; animation/title/enemy code has
1,712 bytes free. RAM use is 418 bytes; the packed cartridge remains 64 KB.
Assembly inspection confirms independent random draws, byte-safe input/reserve
arithmetic, aligned head-color offsets and fixed bank-switch wrappers.

Classic99 verified 838's sequential prompts and a nine-life level-2 start,
centered static/moving rivets, the clear spray-can placement, and visible colored
smasher top holds and full strokes. An isolated stage-4 review cartridge showed
the second roamer; production was restored immediately afterward. Whole-level
completion and precise original-machine pacing are not claimed from these
controlled checks. No Coleco build or runtime check was performed.

The final production cart also passed a one-life level-3 start, a complete
colored smasher-cycle capture, and a factory GAME OVER showing the full blank
margin. A fresh Fire returned to the normal title. This newest production cart
was left running in one Classic99 window.


## §23 Original challenge routes and richer audio (2026-10-02)

This supersedes the second-chain workaround in the July traversal audit and
sections 19-20's 128-step pincher timing. Reviewed the Apple II longplay at
1:33-1:36 and 2:05-3:13, plus the C64 longplay at 1:35-2:47. Both show the
factory belt's left escape chain and no chain at its right end. The Apple II
player waits on the right for touching jaws, then makes two quick jumps through
the opening. The [Apple II walkthrough](https://gamefaqs.gamespot.com/appleii/579172-hard-hat-mack/faqs/8818)
also describes jumping twice when the pinchers fully close.

- Removed the added column-10 chain on site 3. Keep the original column-4 escape
  chain and its head-only catch fix. Enter the belt from the rotating lift,
  collect the box while being carried toward the grinder, then climb out left.
  The source-driven route succeeds at nine of sixteen sampled smasher phases;
  mistimed launches remain lethal. This is a timing challenge, not a safe
  shortcut from the roof.
- Pincher positions and 32-pixel maximum opening are unchanged. Each of the
  seventeen poses now lasts three world steps instead of four: a 96-step cycle
  (~1.42 s), with immediate smooth reversal and closure impact at step 48.
  Both directions permit two jumps starting near closure, including a twelve
  world-step (~0.18 s) release/repress gap. The actual crane approach and right
  waiting patch remain covered by the existing live-hazard tests.
- Enemies use a 12-pixel body collision height rather than ten. An ordinary
  eleven-pixel-high jump cannot clear them; the body remains local to its floor.
  Jump clearance over gaps and movement momentum are unchanged.

Audio now allocates channel 0 to reward chimes, channel 1 to alternating boot
taps, chain clinks and metallic impacts, channel 2 to jump/death sweeps, and
channel 3 to noise. Pickups preserve a jump's pitch, lifetime and volume. Death
clears lower-priority tones and adds a noise tail. Stationary/blocked walking
does not trigger steps. Every envelope ages using elapsed video frames and
explicitly silences its channel; screen transitions clear all four counters.

The former four ascending beeps become three related, newly composed twelve-note
C-major fanfares with harmony, bass, light percussion, articulation and decay.
Site 1 uses brisk call-and-response (130 frames, ~2.17 s); site 2 answers with
a rising melody (122 frames, ~2.03 s); site 3 moves into a higher register with
a broader rhythm and longer final tonic (136 frames, ~2.27 s). All three share
the same key, accompaniment palette and final C, but have distinct melodies.
These are PSG arrangements for the port, not claimed transcriptions of either reference soundtrack. Audio envelope updates and the
completion score reside in TI bank 2; fixed wrappers restore bank 1. Pitch
multiplication compiles to word shifts, avoiding byte truncation and stale MPY
register state.

The checker executes all three scores, rejects identical site melodies, checks
all three pitched voices, duration and final note-offs, tests simultaneous pickups/jumps and death
priority, and rejects restored shortcuts, jumpable enemies and missing sound
channels. Validation results and runtime limits follow below.


Classic99 ran the actual completion handler for all three sites using an isolated
review cart with an Up-to-complete hook. Captures show sites 1 -> 2 -> 3 -> stage 4,
correct bonus/score advancement, the factory without the added chain, and the
second roamer on the repeated first site. The production cart was restored
immediately afterward. This verifies execution and screen transitions, not an
unassisted whole-level clear or a listening comparison with the originals.


Final TI gate: all 63 defect mutations rejected; all 65 GOSUB targets unwind;
504 shortened branches verified, saving 2,016 bytes. Fixed code uses
21,816/24,336 bytes (2,520 free); unoptimized fixed code uses 23,832 bytes
(504 free). Setup/assets have 129 bytes free and animation/audio code has
516 bytes free. RAM use is 448 bytes; the packed cart remains 64 KB. Both
bank images match their packed pages exactly. No Coleco build or runtime
check was performed, as requested.

The optimized production cart passed an 838 nine-life site-2 start. A 64-frame
capture shows continuous opening/closing, touching jaws and the clear right
waiting patch. Production SHA-256:
`05B1B5E3844DF4D09FC03DE50C001FF145C0768263863C2B937C80DDA56905A8`.
It is left on the normal title screen in one Classic99 window.


## §24 Reliable hold-to-drop jackhammer (2026-10-02)

Reproduced the reported failure in the actual input and actor routines: when
Mack stood near the drill's spawn, the 45-frame hold released it, then the next
pickup test immediately caught it again. The hold counter stayed saturated,
so holding Fire longer had no further effect. Catching a roaming drill after
an already-long button hold had the same saturated-counter problem.

Dropping now locks re-capture until Mack and the released drill separate beyond
the normal pickup bounds. A fresh pickup resets the hold counter. The drill
still returns to its start and resumes its route; no arbitrary pickup delay is
added. Initializing a level or respawning clears the separation lock. Hold Fire
(Tab in Classic99) for 45 video frames, about 0.75 seconds at 60 Hz; a short press
still jumps and does not release inventory.

The regression executes the shipped button block followed by the real actor
pickup routine, both near and away from the spawn, with 1-4-frame deltas. It
checks short presses, sustained holds, release without separation, re-capture
after separation, and picking up while Fire is already held. Four new defective
variants must fail, bringing the total to 67.


Classic99 level-1 review confirmed that a short Tab press retains the hammer
and a sustained hold releases it; the nearby loose brick can then be collected
while the drill resumes roaming. The first review accidentally selected site 3
and was discarded; the valid review explicitly starts site 1. The production
cart was restored immediately after each temporary review.

TI validation: all 67 defect mutations rejected, all 65 GOSUB targets unwind,
504 shortened branches verified. Fixed code is 21,830/24,336 bytes (2,506 free);
unoptimized code is 23,846 bytes (490 free). Setup/assets have 123 bytes free,
animation/audio has 472 bytes free, and RAM use is 450 bytes. The latest 64 KB
production cart has SHA-256
`BF189C2599D55A6C8A24AE3F62C12AB0FC10435B7C53CAA4C83FE0791AA2D392`.


## §25 Upper conveyor edge and construction title (2026-10-02)

The upper-right site-2 conveyor shifts one character (eight pixels) right:
bottom roller row 8/column 22, top roller row 6/column 26, with its support post
at column 26. The same level opcode draws the machine and records the riding
surface, now x=176..215, y=66..50. The lower conveyor is unchanged.

Walking or being carried beyond the high right-hand end is fatal immediately;
the shoe overlap with the girder below no longer turns this into a safe 22-pixel
drop. The rule runs after walking and conveyor transport, and only at this high
exit. A deliberate jump still leaves before the edge rule and can catch the
armed magnet. Tests execute passive and walking exits at both belt clock phases,
and two live-magnet jumps, while checking other floors/sites remain unaffected.

The new title uses matching gold HARD HAT and MACK lettering,
with full-height ordered gradients: white through light yellow to yellow over
all 28 rows of HARD HAT and all 35 rows of MACK. HARD HAT's letter
strokes align with eight-pixel character boundaries. MACK uses its original
115-pixel width: full ink scanlines keep two-color dithering, while partial
edge scanlines reserve black and use their dominant yellow-gradient shade.
The silhouette stays intact. It has
steel scaffolding, a hanging hook, stacked girders and Mack with the jackhammer
on a riveted beam. LAST SCORE and HIGH SCORE appear along the top. The credit
above the controls is exactly "2026 UNHUMAN and C&C AI"; PRESS FIRE TO START
is centered at the bottom. This replaces the old title/instruction
screen completely; Fire starts play directly. Controls are visible, and the 838 lives/level
setup remains hidden. The last completed game's score is saved before the
new-game score reset; the high score survives a lower-scoring next game. The
current game, last score and high score each retain their own 838 provenance.
Entering 838 marks the game even when choosing normal lives/level. Asterisks
appear beside the relevant title scores and the current score in the HUD. A higher normal score
clears the high-score marker; a tie preserves the original record and marker.
A new normal game clears only the current-game marker. Both scores
are session values, cleared when the cartridge is reset.

`assets/gentitle.py` is the editable pixel-art source. It generates 84 patterns,
per-scanline colors and a 768-byte name table; its gate checks the two-color
hardware limit, character ownership, clear score/control rows and stale outputs.
Title art occupies characters 128..211. `game_chars` reloads the original game
patterns/colors after leaving the title, and title sprites are hidden before
play or setup. The lowercase credit has an explicit white font palette.

The title and setup routines/art now occupy TI bank 3. The existing wrapper
restores setup bank 1 before reloading game art. The cart remains 64 KB; the
bank checker verifies all three data/code pages against the packed cart and
rejects a missing or corrupted title page. The source-driven UI regression
checks score persistence, printed labels/values/credit, normal starting state,
838 input, bank return and gameplay art restoration. Seventeen new faulty variants
bring the physics/UI gate to 84 rejected defects, including missing provenance,
leaked setup state, incorrectly replacing a tied record, score overflow and
incorrect score formatting/scaling. Coleco validation remains
paused at the user's request; its script includes the same generated-title gate
for its eventual rebuild.


Classic99 verified full-height gradient artwork, blank-padded 65540/100000
scores, 838 score markers, and an assisted 327675 record after game over. A
subsequent normal game removes the current/last marker while keeping the tied
assisted high-score marker. Gameplay shows bonus/current score/level only,
and starting play restores the playfield graphics. A separate one-life site-2
review confirmed passive travel off the shifted conveyor's end reaches GAME OVER.
Temporary review carts were restored immediately after captures.

TI validation: all 84 defect mutations rejected and all 70 GOSUB targets unwind.
The checked optimizer verifies 511 shortened branches. Fixed code is
22,122/24,336 bytes (2,214 free); unoptimized code is 24,166 bytes (170 free).
Setup/assets have 151 bytes free, animation/audio has 1,308, and title/setup
has 5,598; RAM use is 466 bytes. The cartridge remains 64 KB.


Scores, last score and high score now store units of five. Display divides the
stored value by two for the first five decimal digits and appends 0 or 5 for
the last digit, avoiding a 16-bit multiply overflow. Six-character score fields
use spaces before the first digit; zero is a single visible 0. Bonus uses four
space-padded digits. The HUD shows only bonus, current score in columns 10-15
(marker 16), and level after column 24. High score appears only on the title.
LAST SCORE starts at column 2 without space padding, with its marker directly
after the last digit. HIGH SCORE remains right-aligned in columns 24-29, with
its marker in column 30. The gameplay score remains right-aligned.

All awards preserve their displayed point values, including 25 and 35; the
one-time extra-life comparison is 1,400 stored units (7,000 points). A shared
addition routine saturates at 65,535 units (327,675 points), never wraps. The
bonus still counts actual points and is divided by five only when awarded.
Formatting lives in bank 3; its fixed wrapper restores bank 1, while the title
calls the formatter directly without changing its own bank. Regressions cover
0/5 endings, the old 65,535-point limit, maximum score, saturation, stale digits,
marker clearing, bonus scaling and the unchanged extra-life threshold.

Final production SHA-256:
`0CE82B25F6685B10AF86076C30796F1F08766228053F0AB079638972F9361156`.
The cart is left on the title in one Classic99 window with normal starts.


## §26 Elevator arrival and title refinements (2026-10-02)

LAST SCORE now begins directly at column 2 under its label without padding;
its 838 asterisk follows the final digit. Zero remains a single 0. HIGH SCORE
and the gameplay score retain right alignment. Both title lines now share the
full-height white/light-yellow/yellow dithered palette.

The [C64 reference at 38.92-39.45 seconds](https://www.youtube.com/watch?v=WSbEDNtmQWY&t=38)
shows two squash/rise cycles after the upward elevator ride, and another after
the downward trip around 44.8-45.3. Frame-by-frame review distinguishes half
crouch, deep crouch and upright poses. The extracted audio spectrum alternates
approximately 400 and 250 Hz during this cue. The Apple II clips' initial
level-one routes use chains/springs and do not establish a conflicting arrival
sequence; the clearly visible C64 arrivals guide this adaptation.

The port adds a 32-video-frame (0.53-second at 60 Hz) arrival dance, eight
four-frame poses, and seven alternating PSG notes (periods 280/447). This
matches the two-tone gesture rather than reproducing the SID timbre. Sound and
animation advance through each elapsed video frame, so multi-frame catch-up
does not lengthen the pause. Mack stays on the parked cabin floor while other
actors continue. Controls resume at the end; death and screen changes cancel
both the animation and sound. An empty summoned cabin does not trigger it.

Two editable crouch poses and their purple clothing overlays live in
`dance_bitmap` in the BASIC source. Bank 2 uploads the four 16x16 patterns once
per arrival (sprite patterns 27-30), reusing the original standing pose. The
white body and clothes animate together; soles remain on the floor. The
existing sprite slots and collision coordinates stay in use. Seven new
negative cases bring the gate to 91: missing arrival, movement during the
pause, incorrect timing, missing alternating pitch, empty-cabin activation,
missing rendering and missing cancellation. Both directions and 1/2/4-frame
updates are exercised.

Classic99's 36-frame review capture shows the occupied cabin reaching the
upper landing, two distinct crouch/rise cycles, then a stable standing pose
without a repeated dance. The title capture shows unpadded LAST SCORE 6170
and right-aligned HIGH SCORE 100000 with matching yellow gradients. The
production cart was restored immediately after the temporary ride setup.
Audio was checked from the reference spectrum and executed PSG events; live
emulator audio was not available for direct listening in this session.

Final TI checks: 91 defect mutations rejected, 71 GOSUB targets unwind, and
515 shortened branches verified. Fixed code is 22,196/24,336 bytes (2,140 free);
unoptimized code is 24,256 bytes (80 free). Setup/assets have 151 bytes free,
animation/audio 860, and title/setup 5,516. RAM use is 472 bytes; cart size 64 KB.
Production SHA-256: `86B690C42A11BD0B78DA7C15F185B906363B4C28935204D295B3F91D8C8804FC`.
The production cart is left running on its normal title in one Classic99 window.

The final production title was verified with Win32 PrintWindow. Desktop
CopyFromScreen captures intermittently returned black or incomplete areas;
PrintWindow confirmed the complete rendered title without changing the ROM.


## §27 Gameplay HUD alignment (2026-10-02)

The gameplay score starts at column 0 without a prefix or space padding; an
838 asterisk follows its last digit. Its seven-character area is cleared before
redrawing so shorter scores and unmarked games leave no stale digits/marker.
BONUS starts at column 11 and its four-character timer occupies columns 17-20,
centering the complete ten-character group on the 32-column display. All timer
updates, including countdown and respawn, use the new position.

LEVEL and the stage number end at column 31. The complete label starts at
column 25 for 1-9, 24 for 10-99, and 23 for 100-255. Clearing columns 23-31
handles a new one-digit game after a longer run. Reserve hats remain on row 1.
The title's LAST SCORE remains flush left and HIGH SCORE remains right-aligned;
the HUD's shared left-aligned formatter does not change that title alignment.
Existing layout checks now cover 1/9/10/99/100/255, six-digit scores with a
marker, zero values, stale text and the centered bonus. Two negative cases
reject the old bonus position and a broken two-digit level shift (93 total).

TI validation passed: all 93 defect mutations rejected, 73 GOSUB targets
unwind, and 516 shortened branches verified. Fixed code uses 22,236/24,336
bytes (2,100 free); the unoptimized image uses 24,300 (36 free). Setup/assets,
animation/audio and title banks have 199, 860 and 5,424 bytes free respectively.
RAM use is 474 bytes; the cartridge is 64 KB.

Classic99 captures verified the six-digit score with its 838 marker and LEVEL
100 in a temporary review cartridge, then the normal production level-one HUD.
The production cartridge is running in one Classic99 window with normal
starting conditions. SHA-256:
`60219ADE6A7E7DD900EF1B2F25737BCF678186D4F2F490FC02A50E651FCBE986`.

## §28 Original MACK width and trampoline compression (2026-10-02)

The saved initial title preview establishes MACK's original bounds: x=70..184,
y=76..110 (115x35 pixels). Those bounds and the five-pixel letter strokes are
restored, retaining white/light-yellow/yellow dithering. The HARD HAT line,
scenery and text layout stay as in §27. To respect two inks per character
scanline, partial MACK edge cells retain black and their dominant gradient
shade; full ink cells retain the ordered two-color dither. The generator gates
the complete original silhouette, yellow palette and retained dithering.

The Apple II all-levels reference (`zanShXo4btw`, approximately 8.44-8.68 s)
shows the trampoline cap sinking beneath Mack, then rebounding before his
ascent; it is still when unoccupied. Level one's spring now has five character
poses, with a connected white/magenta cap, exposed coil and fixed green base.
Characters 137/138 are its left/right halves. On impact, eight world steps
move the cap down four pixels and back up; Mack's soles follow the same
position, centered over the pad. This is about 0.12 seconds at the existing
67.5-step/s world rate, a hardware adaptation of the reference gesture rather
than an exact frame transcription. The existing launch sound starts on release.
The entry window and destination floors remain unchanged, including the top
floor's return to the bottom floor. Level three's spring transfers are unchanged.

The movement routine lives in bank 3, through a fixed wrapper that restores
bank 1. Animation uses the existing bank-2 machinery draw: upload two patterns
and two color tables only when the pose changes, after world simulation.
An ordinary idle frame performs no upload. Death restores the resting pose;
level initialization invalidates the pose cache. The editable generator also
regenerates the initial 137/138 art, avoiding different boot and resting poses.

Source-driven checks cover all five entry floors, foot/cap alignment, every
compression pose, colors, sound at launch, bank restoration, idle uploads,
death reset and 1/2/4-step render batches. Three deliberately broken variants
(missing compression, detached rider and frozen art) bring the gate to 96.
Classic99's 60-image capture shows impact, compression, rebound, ascent and
the stable resting cap. Its title capture confirms the restored MACK outline.
The temporary review cart was immediately replaced with production afterward.

TI build passed all 96 defect mutations and 74 returning GOSUB targets. The
511 verified short branches save 2,044 bytes: fixed code is 22,062/24,336 bytes
(2,274 free), with 24,106 bytes before optimization. Banks 1/2/3 retain
181/586/4,320 bytes respectively; RAM is 476 bytes and the cart is 64 KB.
Production SHA-256:
`EC409B96E6614D13249801B592B2AA77763B9392E846B08E27FF269689626DD4`.

## §29 Clearer starting position (2026-10-02)

Level one's spawn moves from column 23 to 24 (Mack x=180 to 188), then to 25
(x=196), one character farther right. His hat and torso remain clear against
black, and the same data drives respawn. The spray can moves from column 25 to
16, two characters right of the middle pedestal at column 14, avoiding overlap
with Mack at the start. The support's white/green palette is consistent with
the Apple II reference and is retained.

The complete TI build again passed all 96 defect mutations; memory and bank
budgets are unchanged from §28. The newest production cart is left in one
Classic99 window with normal starting conditions. SHA-256:
`9EAC44776631D5A41F1E69BBAB9AC454B733F94F09E6360A6A99774DEADE48AB`.

## §30 Level-three springs match level one (2026-10-02)

Both factory springs now occupy two characters on row 22, above the ground:
columns 10-11 on the left and 19-20 on the right (characters 139-142). Their
patterns and colors reuse level one's exact five poses, including the cap,
coil and fixed base. The left oil drums move to columns 8-9 to clear the pad;
the misplaced supports above the old springs are removed. Each spring caches
its pose independently, so only the occupied spring compresses and idle frames
perform no character uploads. Death restores both resting poses.

The shared compression routine moves Mack's soles with the cap for eight world
steps and sounds the launch cue on release. Level three compresses the first
spring, crosses in the existing 36-step arc, then compresses the opposite spring
before launching onto the opposite lower platform. Mack centers at x=80/152,
with resting soles at y=176. Falling catches and all four character halves use
the raised surface. The second launch begins horizontal movement after three
steps instead of five, clearing the girder underside and reaching the platform
from the higher spring. The two compressions and crossing take 52 world steps,
in addition to the initial fall and final platform jump.

Source-driven checks cover both directions, all four pad halves, both launch
sounds, rider/cap alignment, bank restoration, independent character/color
uploads, death reset and 1/2/4-step render batches. Five added defect mutations
reject lowered pads, missing drawing, failure to switch active pads, a skipped
second compression and the old launch delay (101 total). Classic99 captures
verified both complete routes, from falling onto the first spring through the
second rebound and a stable landing on the opposite platform. Each temporary
review cartridge was immediately replaced with normal production afterward.

The TI build passed all 101 defect mutations and 77 returning GOSUB targets.
Its 511 verified short branches save 2,044 bytes: fixed code is 21,984/24,336
bytes (2,352 free), with 24,028 bytes before optimization. Banks 1/2/3 retain
125/378/3,960 bytes respectively; RAM is 480 bytes and the cartridge is 64 KB.
The latest production cart is running in one Classic99 window with normal
starting conditions. SHA-256:
`0577245DD847264BD019C89547408DDE75B43BD3BFD95EE73965C7CC57C83A34`.

## §31 Blocks, girders and factory scenery (2026-10-02)

This pass follows the user's detailed art corrections and the saved Apple II
and C64 longplays. The Apple II overview at 1:30-3:20 confirms the green/blue
second-site girders, cabinet, buckets, axles and flashing IN arrows. The new
processor output is an adaptation of the visible box-to-rivet gesture, not a
claim of frame-exact timing across those different ports.

Level-one blocks use identical eight-pixel red faces and white borders when
loose and placed. The carried block uses complementary red-fill and white-edge
sprites (slots 1 and 14, patterns 28 and 96). Slot 14 is otherwise unused on
level one and is hidden when not carrying a block. Riveted plugs retain their
logical state but use the ordinary girder's exact pattern and colors. Girder
rivets occupy the central scanlines 3-4 on all sites. Level two uses bright
green bodies with blue rivets and one-pixel blue upper/lower edges, including
all sixteen pre-shifted slices of the moving crane beam.

Lunch pails are 16x12 pixels in a two-by-two character footprint, anchored to
the same floor. The added upper row holds the handle. Either lower half
collects the pail and clears all four cells without touching the supporting
girder. The bottom-right chain moves from column 23 to 26; the roamer's climb
turn moves with it. A two-by-two pump at rows 18-19, columns 24-25, follows the
crane's position and direction, remaining still when the crane is still. Bonus
tools remain collectible. The pincers skip one clock count in each sixteen,
reducing their smooth full cycle from 96 to 90 world steps (about 6.7% faster).
The existing closure-launch, two-jump and twelve-step re-press margins still
pass in both directions; the safe patch remains unchanged.

Both smashers share a five-pixel head instead of four, predominantly white
with a gray detail row. Its added pixel extends upward; the bottom still
finishes immediately above the girder/belt. The parked position moves down
one pixel so all five rows remain exposed. The piston, belt overlays and
visible-contact collision checks remain synchronized.

Level three has one 16-pixel bucket per side instead of two repeated cans.
The 32x32 central cabinet has a blue body, white perimeter, gridded window and
white-framed red door. Closed green oval processors have white rims, with no
lettering or painted openings inside them. Separate IN/down-arrow graphics
at rows 19-20 flash every 32 world steps. Rounded 16x16 axles cap the platform
mechanism at rows 7-8 and 17-18, centered on its existing circulation path.

Box delivery keeps its forty-step fall and original scoring. On reaching the
processor it counts the box, waits ten world steps, then ejects a small white
rivet toward that side's bucket for sixteen steps. Six rising steps and ten
descending steps form the arc. The saved input side determines the output,
even if Mack has moved elsewhere. A pending output prevents another delivery;
the final box completes the level only after its rivet enters the bucket.
Mechanical clacks mark ejection and arrival. This output is decorative and
has no enemy hitbox.

`assets/genfixtures.py` owns editable blocks, girder colors, pails and scenery;
`genconveyors.py` owns their existing animated machinery. Both regenerate
their BASIC tables and reject stale output. Extra fixtures and their upload
routines occupy bank 3. Character codes 96-127 are borrowed from unused
lowercase text during play; the title explicitly restores its original a/d/n
glyphs and white colors for the existing credit. Original startup sprite and
route data remain in bank 1. The checker now derives art-label bank ownership
from BANK declarations and checks uploads against the active page, including
the startup sprite tables. Seven new negative cases bring the total to 108.

Validation: the TI build rejected all 108 defect mutations and verified all
83 GOSUB targets return. Its 515 checked short branches save 2,060 bytes;
fixed code is 22,294/24,336 bytes (2,042 free). The unoptimized comparison is
24,354 bytes, 18 over the limit, so this version requires the default checked
optimizer. Banks 1/2/3 have 129/378/2,220 bytes free; RAM is 488 bytes and the
cartridge remains 64 KB. Packed banks match their assembled data exactly.

Classic99 captures verified the loose/placed/riveted block appearances, both
sites' white smashers, green girders, taller pails, pump, cabinet, axles and
flashing IN arrows. Separate left/right delivery captures show clean falling
boxes, the processing pause and rivets landing inside the correct buckets.
The title capture confirms its original credit remains intact. Temporary
review cartridges were replaced with production immediately after each run.
The newest normal production cartridge is running in one Classic99 window.
SHA-256: `FE0AB6567229D2A09C51DB9D074A494C9612097DF6F251BF3E4DFE6975D885E4`.


## 32. Boarding, girder spacing, receiver and end-screen feedback (2026-10-02)

The previous scenery pass is committed as `2049d7e`. The reported simultaneous
block/hammer was a brief overlap with the independently roaming drill. Both
pickup orders still require empty hands. The loose drill is occluded within
18 horizontal / 12 vertical pixels of a live block-carrying Mack; its route
and ownership continue unchanged. Clearing and changing inventory explicitly
clears the block outline. The complete renderer lives in bank 3 and restores
bank 1, leaving room in the fixed area for the new end-screen routines.

The Apple II video at 1:30 (site two), 2:40 (site three) and 3:35 (repeated
site one) shows grouped pairs of centered rivets separated by plain beam
lengths. Previously every character repeated a rivet. Codes 128-130 are now
plain; code 134 is a riveted section with the current site's palette. Three
32-column masks preserve pair spacing across split runs and repaired holes.
This is a grid adaptation of the reference, rather than a pixel-for-pixel
transcription of its wider screen. At this stage, level-one column 11 repaired
into its pair and column 18 into a plain section; section 33 records the
subsequent one-character shift requested during play review. The five-cell moving beam has paired
ends and a plain center, with all eight vertical offsets kept continuous.
Its plain slices borrow 96-111 only on site two; site initialization restores
the factory cabinet before site three. Elevator floor/spring codes and all
platform collision ranges remain intact.

An armed elevator now uses the same support test for starting as for landing.
Every supported horizontal position snaps to the cabin center and starts the
trip, including the far-left landing that used to strand Mack. Arrival still
requires leaving and reboarding; the dance and jump exit remain unchanged.

The site-two receiver is a white rounded body with a dark open mouth, side
outlet, magenta collar and green foot. Its lower halves are distinct characters
162/163. The duplicate machine at columns 17-18 is removed. The concrete keeps
its belt speed and 317-step release cadence, then stops horizontal drift at
x=80 and descends into the opening. Its last visible footprint is x=85..90,
y=169..174; phase 60 removes both the sprite and its collision. The receiver's
ground hazard ends at x=95 instead of extending beyond the body to x=103.
Lunch pails retain their 16x12 size and pickup footprint, with smaller handles,
domed white lids, two red panels, a white center strap and inset white detail.

Completion transfers 100 displayed bonus points per tick (20 stored score
units), with an exact final partial award and saturation at the score limit.
Both score and bonus update per tick. A one-frame tone and two quiet frames
separate updates; the existing level-specific fanfare follows the zero display.
GAME OVER uses elapsed video frames: a fresh Fire is accepted after 75 frames,
and 600 frames returns to the title regardless of held/released input. Frame
wrap and early/held Fire are covered. The title's own release gate prevents
an automatic new game from the same held button.

Validation: the TI build passed all 124 defect mutations, with 90 returning
GOSUB targets and 514 verified short branches. Fixed code occupied
22,190/24,336 bytes; RAM was 534 bytes. The checks cover both pickup orders,
sprite transitions, all 32 elevator endpoint/position combinations, every
girder placement, all eight moving-beam offsets, receiver entry, exact bonus
awards/ticks, and timeout/input traces across FRAME wrap. The score formatter
also has an assembly gate for the TI word-mask bug documented in CLAUDE.md.
A controlled completion capture confirms 5,000 bonus points transfer to a
displayed score of 5,000 with a zero remaining bonus.


## 33. Rivet alignment and linked factory machinery (2026-10-03)

Level one's left rivet pair stays at columns 4-5. The other pairs move one
character right to 11-12, 17-18 and 24-25. Repairs use the same column mask,
so both existing hole columns now become dotted girder cells. The regression
fixture also repairs plain columns to ensure ordinary beam lengths remain
plain. Other levels' masks and all elevator behavior are preserved.

A fresh review of the saved Apple II and C64 longplays showed capped feeds,
sloping white shoulders and front details on the two bottom processors.
Their forty-by-sixteen footprint now uses those features, green front panels
and magenta details. The IN lettering and arrow shift four pixels right inside
the existing custom characters, centering both over the actual feed cap.
The generator checks pixel centers including the label/map offset. Flash
timing, delivery lips, processing delay and the box-to-rivet route retain
their behavior. The central blue cabinet is unchanged.

The middle platform drive now animates its two chain runs in opposite
directions: left down, right up. White link highlights move with the green
links. Both rounded end wheels use eight counterclockwise spoke poses.
Chain position comes directly from the paddle phase (one pixel per world
step); the wheels advance a pose every four world steps. Cached phases avoid
redundant uploads when stopped, and catch-up frames select the actual current
position instead of accumulating visual drift. Ordinary climbing chains are
unchanged. The initial chain art matches the first animation phase.

New short effects accompany block placement, elevator/platform-drive motion,
concrete entering the receiver, box processing and a rivet arriving in its
bucket. Movement ratchets are quieter than impacts. They use the existing
short-effect channels, respect death and longer effects, and leave jump and
reward voices alone. Existing frame-based envelopes explicitly silence them.
The effect generator occupies bank 2; bucket arrival requests its sound only
after the factory renderer returns to fixed code, then restores bank 1.
This keeps the unoptimized TI assembly within its address window.

Source-executing checks cover two full paddle circuits at render batches of
one, two and four world steps; linked chain/color movement; wheel poses;
stationary redraws; sound priorities, note-offs and bank restoration. Five
new negative cases bring the regression suite to 129 deliberately broken
variants. Classic99 captures show the new processor shapes and different
chain/spoke positions while the paddles circulate. Audio was checked through
sound-event and envelope assertions, not a listening comparison to the
original. No uninterrupted whole-level clear is claimed.


Final TI validation: all 129 defect mutations rejected; all 92 GOSUB targets
return. The 521 checked short branches save 2,084 bytes. Fixed code occupies
22,416/24,336 bytes (1,920 free); RAM is 540 bytes. Banks 1/2/3 have
191/110/244 bytes free, and the packed 64 KB cartridge matches all three
assembled banks. Final Classic99 review confirms the shifted level-one rivet
pairs and centered flashing processor labels. Temporary review carts were
restored immediately after capture. Production retains normal level-one,
three-life starting conditions. Cartridge SHA-256:
`845675455001CAFD430D1746307A31E741624FC25E57B150DC7B46CB71E3BEBE`.


## 34. Bonus ticker and conveyor-box position (2026-10-03)

The original completion tick used a single WAIT before silencing its tone.
Because WAIT waits for the next frame boundary, that can be much less than a
full frame. A louder, longer pitched replacement was rejected during live
review as too aggressive. The final effect is a short white-noise tick on
channel 3 (noise setting 5, volume 7), held across two frame boundaries and
silenced for two more. This guarantees at least one complete frame of sound
and a distinct quiet gap; no sustained tone accompanies the count. Each tick
still transfers exactly 100 displayed points, with partial awards and score
saturation unchanged. Fifty ticks now use 200 WAITs before the fanfare.
The completion test's input trace includes this longer sequence, and the
pulse-duration negative case brings the suite to 130 mutations.

The level-three conveyor box moves from row 8, column 7 to column 6, one
character left of the smasher. It occupies its own cell, so the former
post-pickup piston-cell repair is removed. The source-executing checks cover
the full smasher cycle, box collection/clearing, unchanged piston and belt,
and the timed lift-to-box-to-escape-chain route. Restoring the old placement
is a rejected mutation.

The apparent second smasher below level two's bottom-right girder is the
crane pump, beside the chain. Its four piston poses follow crane height and
direction; a parked crane intentionally leaves the pump still. It is scenery,
not another crushing hazard. Its placement and behavior are unchanged.


Validation: the TI build passed its 130 mutation cases and 92 returning
GOSUB targets. The final noise-only tuning also passed the bonus/completion
checks and both silence/short-pulse mutations. Classic99's PSG log records
50 separate two-frame noise pulses at amplitude 37/255 for a 5,000-point
bonus; the rejected loud tone logged 189/255. This verifies emitted sound
states, without claiming a transcription of the original game's sound.
Fixed code is 22,418/24,336 bytes (1,918 free), with 521 verified short
branches saving 2,084 bytes. RAM remains 540 bytes; banks 1/2/3 retain
191/166/244 bytes. The normal production TI cartridge SHA-256 is
`C42D7B900B8CD069167BF03852FED7E096D92C395781604C906B17BCC90EF436`.

Classic99 captures verify the box clear of the smasher and the right-hand
pump changing piston position as the crane moves. The temporary active-crane
review cart was replaced with the newest normal production cart; its title
screen is running for review.


## 35. Continuous pedestals and floor-mounted crane pump (2026-10-03)

Level one's three bottom supports previously repeated the same flared
8-pixel foot in two rows. Each now uses a complete 8x16 drawing: white
bearing plate, narrow stem with small magenta collars, and one broad white
foot. Their columns (6, 14 and 23), girder positions and pass-through behavior
are unchanged. Rows 22 and 23 use distinct characters 120 and 121.

The apparent extra smasher hanging beside the bottom-right chain is replaced
by an enclosed floor-mounted pump. It moves from rows 18-19 to rows 21-22,
columns 24-25. The white casing, dark blue cylinder, visible reciprocating
piston, ventilation marks and mounting feet distinguish it from the exposed
crushing heads. The chain at column 26, fire at column 21, pickups and all
collision rules stay in place. The pump remains decorative and follows crane
height/direction; it remains still while the crane is parked.

The art generator owns both assets. Initialization switches codes 120-123
between level-one supports and the other sites' pump art, including deaths
and repeated level cycles. The existing fixture check now exercises 1/2/3/1
initialization, all three pedestal placements, pump floor placement, clear
space below the hanging girder, and pump motion. Repeated support tops and
restoring the hanging pump placement are rejected mutations (132 total).


## 36. Mack's running cycle (2026-10-03)

The former animation alternated a mostly rigid standing body with wider
feet, using the video-frame clock. Mack now cycles through passing, extended
stride, passing, and bent-knee recovery. The three distinct drawings have
opposing arm swings and visibly different foot positions. The passing pose
also serves as idle; stopping immediately returns to it. Every pose retains
the same forward-facing head, 12-pixel height and ground contact. Left-facing
art mirrors the complete right-facing figure; mirroring is not used to fake
another beat within one direction.

The existing eight-pixel footstep counter selects a pose every two pixels
walked. Passive conveyor travel does not animate the legs. Running speed,
jump/fall poses, collision bounds and elevator arrival dance are unchanged.
The generator owns the editable composite drawings and splits them into
complementary white and purple sprite layers. Patterns 31-34 hold the extra
right/left recovery pairs; dance retains 27-30. Sprite slots remain 0 and 8,
so the animation adds no sprites to a scanline.

Checks execute the actual draw statements across both directions, all eight
walking phases, idle and airborne states. They resolve sprite uploads from
the source, reject overlapping pattern allocations or color layers, and
confirm that video-frame changes cannot advance the run cycle. Art checks
measure the complete two-color figures, require at least 20 changed pixels
between the three drawings, and preserve head orientation and floor contact.
Missing recovery uploads, mismatched clothes and restoring the video clock
are rejected mutations (135 total including the pedestal/pump checks).


Validation for sections 35-36: the complete TI build passed all 135 defect
mutations and 92 returning GOSUB targets. Its 521 verified short branches
save 2,084 bytes. Fixed code occupies 22,454/24,336 bytes (1,882 free);
banks 1/2/3 retain 45/166/120 bytes, and RAM uses 538 bytes. The new sprite
pairs add 128 asset bytes without adding scanline sprites. Generated TI
assembly uses byte masks for the distance phases and keeps both layer
selections together.

Classic99 captures show all three continuous pedestals, the enclosed pump
on the floor with clear space beneath the right-hand girder, and the new
running poses facing both directions. A temporary active-crane cart verified
pump motion, then was immediately replaced with the normal production cart.
Normal level-one/three-life starting conditions are preserved. These checks
do not claim an uninterrupted three-level clear or original-hardware timing.
Final production SHA-256: `C398ED32A49D3FBF8C478818D0B1C649FBA1F90ECA9D456155AAA29D27A87841`.


## 37. Processor discharge outlets (2026-10-03)

Each level-three rivet processor now has a bucket-facing discharge nozzle:
a dark throat, white attachment and lower lip. Only the inward upper corner
is replaced (row 21, column 7 on the left processor, column 24 on the right).
The two mirrored nozzle characters use site-specific codes 120/121, restored
on level changes alongside the existing pedestal and crane-pump variants.
The feed caps, green fronts, IN labels and bucket positions remain intact.

The former rivet started above the machine shoulder. Its visible pixels now
start inside the black outlet: sprite origin (52,165) on the left and
(188,165) on the right. It travels horizontally for six world steps before
falling one pixel per step into the bucket. Horizontal speed, ten-step
processing pause, sixteen-step output duration, scoring and completion
handoff are unchanged. The generator owns both outlet patterns and colors.

The fixture check resolves the visible rivet bitmap against each outlet's
actual pattern/color pixels, verifies the mounting edge and lower lip,
and follows the full trajectory into both buckets. Restoring the old height,
erasing the nozzle, and dropping the rivet too fast are rejected mutations
(138 total). Source conditions remain normal level one with three lives;
separate review cartridges loop each processor's output for visual capture.


Validation: the TI build passed all 138 defect mutations and 92 returning
GOSUB targets. Classic99 captures verify both outlet directions from emergence
to bucket entry; each temporary looping review cart was immediately replaced
with production. The final normal cartridge is running at the title screen.
Fixed code remains 22,454/24,336 bytes, with 521 verified short branches;
RAM remains 538 bytes. Banks 1/2/3 retain 45/166/48 bytes. Production SHA-256:
`92E85C7BB386AB453C258088B620810DC740BE84039385A9F700035AC1727FF4`.


## 38. Processor artwork from the supplied screenshot (2026-10-03)

The user's Apple II screenshot supersedes the earlier green-fronted cabinet
and projecting rectangular nozzles. Each processor now has a low white
housing outline, blue central panel, red side shading, a broad white feed
cap and angled oval outlet shoulders. The drawing follows the reference's
silhouette and white/red/blue palette within the TMS9918 two-ink-per-row
constraint. Both shoulder details are part of the full machine drawing;
the inward discharge uses the existing site-specific upper characters and
continues into the lower housing tile. Machine footprint, centered flashing
IN labels, bucket positions and hazards remain unchanged.

The smaller outlet mouths sit three pixels lower. The rivet sprite begins
at y=168 (visible rows 172-176) inside the dark throat, rises diagonally
for eight world steps, then falls two pixels per step into its bucket.
Both complete 40-by-16 machine drawings are identical, with the same
angled shoulders on both ends. The left machine ejects rightward from
x=52; the right one ejects leftward from x=189. The sixteen-step output
sequence, processing pause, horizontal speed, scoring and final-delivery
handoff remain unchanged. Both full outlet heights are decoded in the fixture
checks, including the lower lips and attachments; both trajectories still
end inside their buckets. Missing-outlet, floating-origin and overshooting
mutations continue to fail. No additional character codes or ROM space are
needed for the new artwork.


## 39. TI runtime optimization and furnace cycle (2026-10-03)

The earlier rendering loop discarded game time on a busy factory screen:
120 instrumented updates used 769 video frames, with 292 discarded by the
four-frame catch-up cap. Increasing that cap alone to eight reduced the
update rate further (60 updates in 588 frames, 119 discarded), so this
pass first removes work rather than simply allowing longer catch-up loops.
These are Classic99 normal-speed measurements, not original-hardware claims.

Dynamic character uploads now target the actual Graphics II screen thirds.
The factory belt uploads its flat tile and animated rollers in the middle
third; the construction belts upload four changing tiles, leaving their
static support posts alone. Smasher
heads cross the appropriate two thirds, while their belt feet, pinchers,
springs, pump, drive chains, wheels and flashing IN labels upload only where
they appear. The standing-player animation sweep checks a maximum of
312 transferred bytes per factory update and 328 per construction-site update. Character
patterns and their colors retain matching phases, and stopped art stays cached.

The main loop waits only if no video frame has elapsed. Simulation retains
one-pixel movement/collision steps and its 9/8 fractional clock, with the
existing four-frame pause cap. Site-specific dispatch skips absent machinery,
and an idle processor returns before changing banks. Factory paddle positions
come from generated ROM tables with repeated phase-offset tails, loaded into
four direct slots; all 224 phases and four paddles are checked against the
original rectangular route. No extra sprite layers or frame-skipping collision
rules are introduced. Elevator behavior and the synchronized rider clocks
are preserved.

A fourth cartridge bank holds the paddle tables and animated machinery art.
The cartridge still occupies 64 KB. The processor output routine moves to the
audio/actors bank to make space for targeted scenery uploads; wrappers restore
bank 1. Physics tests now reject calls to code in the wrong bank, as well as
wrong-bank data reads, and model actual VRAM addresses and source byte offsets.
The bank checker validates all four exact packed banks, including truncation
and corruption cases. `assets/genmotion.py` owns the paddle tables and runs
in the existing build scripts.

Level two's upper-right furnace is one two-character blue cabinet with white
nozzle collars, supported across columns 28 and 29 by a continuous girder.
Two jets extend sixteen pixels and retract in one-pixel increments every two
world steps, repeating every 64 steps. Their four character cells use a cached
32-byte pattern transfer in the top third. The collision envelope follows the
current flame height and cabinet, rather than killing anywhere above the
right-hand edge. Tests cover full support, distinct cabinet halves, all flame
heights, repeated cycles, visible/collision agreement and safe space above
the retracted flames.

Controlled idle comparisons use 60-update samples at normal Classic99 speed,
with the same temporary input suppression and death suppression in both carts.
The HUD prints elapsed video frames and discarded frames once per sample;
no per-frame debug text is drawn. These are frame-counter-derived update rates,
not a guarantee of constant FPS during every route or an input-latency trace.
Production retains normal controls, deaths, three lives and level-one entry.

| Site | Before: video frames / discarded | After: video frames / discarded | Updates/sec before / after |
| --- | --- | --- | --- |
| 1 | 154 / 0 | 73 / 0 | 23.4 / 49.3 |
| 2 | 290 / 50 | 225 / 4 | 12.4 / 16.0 |
| 3 | 381 / 144 | 253 / 15 | 9.4 / 14.2 |

The final factory sample includes animated conveyor rollers. Its discarded
fraction falls from 37.8% to 5.9%; this brings world motion much closer to
its intended 67.5 steps/second without widening the catch-up cap. Busy gameplay
can still exceed that cap, so this is an improvement rather than a claim that
all slowdown is eliminated. Earlier exploratory captures included normal input
and death states; the table above is the controlled comparison used for handoff.

Runtime captures also show the full furnace support with both retracted and
extended jets, matching processor housings, and rivets at the angled discharge
ports. Every temporary capture cart is replaced with production immediately
afterward. Coleco builds and original-hardware timing remain deferred.

The physics harness now caches immutable literal DATA for the exact source
variant and advances a READ cursor, avoiding repeated parsing of unrelated art
after every RESTORE. An original/shifted-spawn/original test proves that the
cache cannot hide a source mutation. All 146 defect cases remain active; the
reversed-paddle case now reverses the ROM lookup rather than replacing the
removed arithmetic routine. The full gate reports mutation progress.

Production handoff verified on 2026-10-04: the faster review source and
`src/HARDHAT.bas` have identical SHA-256 hashes. The apparent regression was
the older production cartridge being restored after temporary review captures.
The full TI build now passes all behavior checks and rejects all 146 defect
mutations, then regenerates the canonical `src/HARDHAT_8.bin`. It verifies
519 shortened branches, uses 536 RAM bytes and 22,324/24,336 fixed bytes,
and leaves 25/4,742/64/1,120 bytes in banks 1 through 4 respectively.
The 64 KB production cartridge SHA-256 is
`09D53304CDE9D8362A33F6478A7FD1D5473E62E666609B6CA809FCA611F8074D`.
That exact canonical path was loaded in the isolated Classic99 review window;
title and normal level-one gameplay were captured with normal CPU throttling
selected and overdrive disabled. The production cartridge remains running.

## 40. Factory conveyor balance and quicker downstrokes (2026-10-04)

The level-three flat conveyor now carries Mack one pixel left per world step,
matching his one-pixel walking speed. Right input cancels the drift on every
step; neutral input travels left one pixel and left input travels two. The
treads and rollers advance one animation pixel per step as well. Level-two
diagonal belts retain their existing half-rate travel and slag synchronization.
The walking regression runs the actual Mack state machine at both clock
parities and verifies position, support and animation phase.

The earlier faster smasher drops preserve impact/sound beats (phases 28 and 44),
short bottom dwell, existing return speeds and 128-step period. Contact follows
each head's rendered position. Tests check downstroke duration, complete travel,
directional step limits, impact phase and the top pause. The live factory-box
route remains reachable and requires timing. Right input also balances at the
last roller, using Mack's supported foot before the walking step.

The two repeated hazard pictures at the left end of the factory belt are now
one two-character wall spark emitter. Eight generated frames send three white,
yellow and orange trails outward from a fixed wall/nozzle, continuously keeping
the dangerous endpoint visible. The two halves use separate character codes;
the existing hazardous footprint and escape chain are retained. Only sixteen
pattern bytes are transferred when the pose changes; colors upload once. The
312-byte factory graphics budget remains enforced for existing art, with a
separately checked 16-byte allowance for this added animation. Five new defect
mutations reject the old half-speed factory belt, a walk-off at the right roller,
either old slow downstroke, and sparks uploaded to the wrong third.

Level two's furnace support explicitly uses two centered-rivet tiles, preserving
its full two-character width and the green/blue girder colors. A new negative
case rejects a plain support; the existing half-supported case still fails.
The complete gate now contains 152 defect mutations.

The subsequent reference image replaces the temporary twin upward jets with a
two-by-two-character magenta/white furnace, green caps and a left-facing outlet.
Its flame extends into columns 26/27, projects horizontally for six pixels,
then curls upward. The existing 64-step extend/retract cycle is retained.
Collision checks the curved flame band intersecting Mack's narrow torso and
the cabinet separately, including clear space beneath the upward curl. Generated
pixels and contact are compared throughout the cycle. The riveted support
remains under both cabinet columns.

The decorative pump beside the bottom-right chain is removed, including its
four map cells, generator artwork, animation tables and runtime uploads. The
level-two fixture animation bank call is skipped entirely. Tests require an
empty chain approach and reject restoration of the removed machine.

The title girder now uses paired rivet columns 4/5, 11/12, 17/18 and 24/25,
matching level one's spacing, with plain cells between groups. Its dimensions,
colors and lettering remain unchanged.

Mack's three running drawings now use clearer planted-foot, extended-stride
and lifted-heel poses. The head has an asymmetric hat brim, face/eye and purple
hair at the back. Both white and purple layers mirror exactly for left-facing
walking and jumping. Leftward airborne art occupies sprite patterns 140/144,
loaded once from bank four; the original running slots and cadence are retained.
Jump takeoff updates facing from its chosen direction, including spring launches.
The animation check verifies both layers, every direction and airborne state,
and the new loader's bank restoration. A missing-left-jump mutation raises the
complete gate to 153 defect cases.
The shared hazard cells are restored when a site initializes, so factory sparks
cannot replace the level-two obstacle art on a later circuit. The added
cross-level restoration mutation brings the final total to 154.
The added fixed code exposed the first-pass assembler's 16-bit address limit
before branch shortening. The reserve-lives painter now lives in bank two,
behind a fixed wrapper that restores bank one. This infrequent HUD operation
creates room without moving work from the gameplay loop. A separate compiler
and assembler preflight confirms the unshortened image fits the address window.

Final TI validation on 2026-10-04 passes all gameplay sweeps and rejects all 154
defect mutations. Assembly verifies 524 shortened branches (2,096 bytes saved),
with 22,460/24,336 fixed bytes, 546 RAM bytes and 30/4,372/522/734 spare bytes in
banks one through four. The first unshortened image is still close to the 16-bit
address boundary (24,556 bytes); future fixed-code growth needs an early assembly
preflight, even though the optimized runtime has 1,876 fixed bytes free.
The 64 KB production ROM SHA-256 is
`9B39CA1F203A12E2D3A39C9AB2917E5BCE2389968736FD15B60A98AE909A2594`.
Classic99 at normal CPU speed shows the spaced title rivets, the supported
reference-style furnace through its extension cycle, the cleared chain approach,
and the factory wall sparks. Level review used the production 838 menu; the same
production cartridge was then reset to its normal title screen for handoff.
The emulator captures supplement the routine-level tests; they are not complete
uninterrupted clears of all three sites. Coleco remains deferred as requested.

## 41. 838 selection feedback and furnace flame shape (2026-10-04)

After the final 838 digit selects a starting level, the number is printed beside
the prompt and held on screen for 45 video frames before normal level
initialization clears the setup. The setup regression checks the lives range
across all six stage choices and requires the selected number to have been shown.

The level-two furnace plume now grows from a narrow nozzle into a broad,
irregular tongue, then tapers and curls upward at its leading edge. Warm red and
yellow edging surrounds a brighter yellow/white core. Each extension depth has
its own changing outline, so the returning cycle animates the turbulent tongues
as well as the reach. The art generator and physics gate check full-width
emission, non-uniform flame thickness and shape variation; hazard timing and
collision bounds remain tied to the existing extension cycle.

## 42. Quicker smasher drops and cycling fire colors (2026-10-04)

Both smasher downstrokes are a little faster while their upward motion remains
unchanged. Level two reaches its girder in eight world steps using mostly
two-pixel moves; level three reaches its belt in eighteen, with occasional
two-pixel moves. Both still strike on phases 28 and 44, respectively, so the
bottom dwell, sound cue and return schedule stay intact. The machinery checker
asserts the shorter descent and rejects the prior slow rates.

The furnace flame cycles four red-heavy orange/yellow palettes, each with a
white-hot core, every eight world steps. Red shades occupy at least half of
every eight-character color band. Its color table changes independently of the
shape animation and transfers only when the palette changes. The art and
runtime checks require four distinct palettes, red-dominant bands and all four
states to reach the flame color table.

## 43. Faster TI build gates (2026-10-04)

The TI build starts all eight source/art checks together; each writes to its own
log, and the build reports every failed check with its output tail. The physics
checker keeps its full behavioral sweeps and all known-bad variants, but
checks independent variants in a pool capped at four workers. Immutable BASIC
control-flow indexes are reused for VMs running the same source variant. No
regression case is skipped or relaxed; the red-density check brought the gate
to 156 defective variants before the latest input and launcher checks.

The full build also exposed the first-pass assembler's fixed-address boundary
in the shared HUD. TI now calls its HUD renderer in bank two, switching to the
score bank only for formatting and restoring the caller bank before returning.
This preserves the existing four bank selections per frame while the Coleco
HUD remains on its original path. The TI image assembles before branch
shortening again, then verifies 524 shortened branches and packs within budget.

## 44. TI title hotkeys, six-stage 838 and Level 1 launcher (2026-10-04)

During TI gameplay, F8/REDO and F9/BACK return to the title. The TI keyboard
scanner reports FCTN separately from the underlying digit, so the shortcut
requires the FCTN modifier together with 8 or 9; ordinary number entry remains
unchanged. Both keys also dismiss the game-over hold. Coleco code is excluded
from this behavior.

The 838 level prompt now accepts 1-6. Choices 1-3 start the corresponding site;
4-6 start the same sites on the second tour, including the two roaming enemies
on stage 4/Level 1. The selected stage remains visible during the existing
feedback pause and is retained in the HUD progression.

Level 1 now has a fixed two-character-wide, two-row launcher at the upper-right
end of the top girder. Editable two-ink artwork in `genfixtures.py` gives it a
white cap, magenta housing and green inspection window. Rivets begin just
outside its left-facing outlet, so the existing projectile visibly originates
from machinery instead of empty space.

At a parked elevator, either horizontal direction now re-arms and starts the
next ride while holding Mack at the cabin's x-position. The wider elevator
support probe remains available for falling/landing boardings. Regression
checks exercise both nudge directions, all six stage choices, both TI function
keys, launcher placement and the projectile's origin. The keyboard check also
accepts the TI scanner's FCTN matrix value for REDO/BACK. The physics gate now
rejects 164 deliberately broken variants.

The completed TI build uses 554 bytes of RAM, verifies 526 shortened branches,
and leaves 1,894 bytes in the fixed area. Data, animation, title and motion
banks retain 10, 3,810, 328 and 544 bytes, respectively. Classic99 confirmed
both F8 and F9 return from live play to the title, and a stage-4 setup displayed
two roaming enemies on level 1. Production SHA-256:
`ECEC6DA90DC327D435CF69A931E103D7364E6D899CD8CCD53EB13DDAF741A2E5`.
