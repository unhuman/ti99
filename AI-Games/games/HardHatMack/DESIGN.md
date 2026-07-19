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
2. **Lunch Break** — collect 6 lunchboxes across a 4-tier site, then ride up under the armed
   electromagnet before falling into the incinerator.
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
channel (cols 29–30). The trampoline is ONE character tall** (a low cap on the 1st floor — jumpable-over),
with a generous catch (any part of Mack over the channel counts); entry rows round to real
floor rows so the bounce delivers **exactly one level above the floor you came from** (top
floor → rides down to the 1st floor). As Mack drifts left out of the channel onto the floor he
**flips to face left** (the way he's going) so he doesn't moon-walk off the trampoline. **Rivets** are thrown from above at Mack's position and
hop down the building (left-only, one bounce per floor, passing through after each bounce);
contact kills. Vandal patrols the 4th floor (2–12); OSHA patrols the 1st floor's left side
(4–20, homing in Mack's band). Mack spawns on the **right side of the 1st floor** (21,25).

### Level 2 — "Lunch Break" (M4 — layout drawn, mechanics in progress)
**Drawn (verified in Classic99, transcribed from `assets/HHM-CV-Level2.png`):** a central
**crane pole** down col 16 (art) with the **electromagnet head** (2-char, chars 176–177) on top
at row 2; girder-variant (129) platforms on tiers rows **5/9/13/17/21** — a top-center crane
platform (r5), left/right platforms on r9/r13/r17, a center platform crossing the pole (r13),
r21 platforms, and the **ground** (row 23); **6 lunch pails** (char 183) on the r9/r13/r17
platforms (cols 4 and 27); two **diagonal conveyors** (char 156, drawn by the new **op 6**
diagonal run — upper-right escalator, lower-left belt); the **incinerator** pot (hazard char
164) bottom-center on the ground; a vandal patrolling r13. Traversal is via **two long side
chains** (cols 6 and 25) — a simplification; the authentic conveyor/springboard traversal and
the crane are a later pass. Collecting all 6 pails (`ob_pail` → `nlbr` → `lvdone`) clears it.
**Still to do:** magnet endgame (ride up off a top platform when armed), functional/moving
conveyors, springboards, refined traversal, and enemy tuning.

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
