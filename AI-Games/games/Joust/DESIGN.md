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
| Loop | **Real-time**, one `WAIT` per frame, 60 Hz both targets |
| Max moving sprites | **11** — player, 4 knights, 4 eggs, pterodactyl, troll hand |
| Per-actor work | **O(1)**: add velocity, clamp, test ≤6 platforms, test lava |
| Enemy AI | **Reactive, no search** — two comparisons per knight |
| VDP reads per frame | **Zero.** No `GCHAR`, no `COINC`; platforms are a 6-entry RAM table |
| Collisions | player↔4 knights, player↔4 eggs, player↔pterodactyl, player↔hand. Knight↔knight is **not** tested (they pass through, as in the arcade) |

**The binding limit is 4 sprites per scanline, not CPU.** `SPRITE FLICKER` is
all-or-nothing in CVBasic and would strobe the player too, so it stays **off** and the
player is **sprite 0** — the VDP drops the highest-numbered sprites, so slot 0 can never
be the one that disappears. Slot order: player 0, knights 1-4, eggs 5-8, pterodactyl 9,
troll hand 10.

---

## 2. Screen & platform layout

32×24 characters, 256×192 pixels.

```
row  0   SCORE 000000                      ♦♦     <- score, SPARE lives
rows 1-19  sky: platforms, knights, eggs, pterodactyl
row  20  lava surface (2-frame animation)
rows 21-23  lava body, and where the troll hand rises from
```

Horizontal **wrap** is free: `#px` is 8.8 fixed point, so 256 px × 256 = 65536 and the
16-bit variable wraps by itself. The top of the screen is a **ceiling** you bump against.

### The six islands (pixels)

| # | name | x1 | x2 | surface y | notes |
|---|---|---|---|---|---|
| 0 | floor-left | 0 | 95 | 160 | |
| 1 | floor-right | 160 | 255 | 160 | |
| 2 | **bridge** | 96 | 159 | 160 | **burns away permanently at wave 3** |
| 3 | lower-left | 16 | 79 | 120 | |
| 4 | lower-right | 176 | 239 | 120 | |
| 5 | mid-left | 56 | 119 | 80 | |
| 6 | upper-right | 144 | 207 | 40 | |

Seven entries, `DIM 8` (sized past the real max index, per `CLAUDE.md` §3A).

**Erosion.** `plon()` is a per-island present/absent flag.
- Wave 1-2: all present. The bridge lets you walk across the lava.
- **Wave 3**: the bridge burns away. From here the floor has a lava gap in the middle.
- **Wave 6+**: one further island vanishes each wave, chosen from islands 3-6 in a fixed
  rotation so the layout is *deterministic*, never random — a player must be able to
  learn it.
- **Every Egg wave restores every island**, exactly as the arcade does.

---

## 3. Physics (8.8 fixed point)

Position and velocity are `#px/#py`, `#vx/#vy`, all ×256. Screen position is `#px / 256`,
which compiles to a shift, never a divide.

| constant | value | meaning |
|---|---|---|
| `GRAV` | 24 | added to `#vy` each frame |
| flap impulse | 660 | `#vy` set to −660 (2.6 px/frame up) — a bare literal, not a `CONST` |
| terminal fall | 700 | ~2.7 px/frame |
| `ACCX` | 20 | horizontal acceleration while steering |
| top speed | 512 | 2 px/frame; knights get 400 + 90 × tier |
| `FRIC` | 10 | decay when not steering |

**Signed velocity in an unsigned world.** Every `#var` comparison compiles unsigned
(`CLAUDE.md` §3A), so velocities are stored **+32768 biased**: "rising" is `#vy < 32768`
and no comparison ever crosses zero. Position updates use `#py = #py + #vy` then
`#py = #py - 32768`, which is correct on either side of the bias because 16-bit
arithmetic wraps.

**Flap is edge-triggered** — holding fire does not hover. Each press is one impulse.

---

## 4. The player

- Sprite 0, **yellow**. Four frames: wings up, mid, down, skid.
- Frame follows vertical motion, not a timer: rising → up, falling → mid, grounded and
  steering → skid.
- **Spawn invulnerability** ~90 frames, shown by flashing. Without it a knight parked on
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
| Bounder | red | 500 | 400 | 26 frames | wave 1 |
| Hunter | grey | 750 | 490 | 19 | **wave 4** |
| Shadow Lord | blue | 1500 | 580 | 12 | **wave 16** |

Shadow Lords fly **higher** by preference — they bias their flap threshold upward, which
is what makes them dangerous rather than merely fast.

**AI, two comparisons per knight per frame:**
1. Is the player above me, and has my flap cooldown expired → flap.
2. Steer toward the player's x, **by the shorter way round the wrap**.

That is all of it. Difficulty is flap eagerness and top speed — never fleeing, which reads
as broken AI rather than as an easier game (`CLAUDE.md` §3A).

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

The mid-air bonus is the skill reward and is worth implementing precisely: `est() = 1`
(falling) at the moment of pickup, not resting.

---

## 7. Pterodactyl

- **Debuts wave 8**, and appears in *any* wave that drags past a time limit — the
  arcade's anti-camping device.
- Enters from a screen edge at the player's altitude and **homes**, faster than any
  knight, wrapping horizontally.
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

**Survival is wave 2 and every 5th.** **Egg is wave 5 and every 5th.** They coincide from
wave 10 on; the wave is then both, and both bonuses can be earned.

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

**Lives: 3 total, HUD shows SPARES** — two icons at the start, none on the last life
(`CLAUDE.md` §7A). `lives` is unsigned 8-bit, so the decrement is guarded: a bare
`lives - 1` at zero wraps to 255 and lights every icon exactly when there are none.

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
- Williams' style: **narrow, heavy, squared-off** capitals on a 5×7 cell inside the 8×8,
  with one blank column at the right for letter spacing and one blank row at the bottom.
- Digits are the distinctive part and get drawn first, since the score is the text most
  on screen.
- Loaded with `DEFINE CHAR 32,59,font_bitmaps` at startup, after which every `PRINT`
  uses it with no further cost.

---

## 13. Sprites & characters

### Sprites (16×16, `DEFINE SPRITE n` counts whole sprites; pattern = n×4)

| n | pattern | what |
|---|---|---|
| 0-3 | 0,4,8,12 | mount facing **right**: wings up, mid, down, skid |
| 4-7 | 16,20,24,28 | the same four facing **left** (the VDP cannot mirror) |
| 8 | 32 | egg |
| 9 | 36 | unhorsed knight, on foot |
| 10-11 | 40,44 | pterodactyl, mouth **closed** / **open** |
| 12 | 48 | troll hand |

### Characters

| code | count | what |
|---|---|---|
| 128 | 3 | island: left cap, middle, right cap |
| 131 | 2 | lava surface, 2 animation frames |
| 133 | 1 | lava body |
| 134 | 1 | spare-life icon |
| 135 | 1 | troll arm segment (the stretch below the hand) |

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

Phases 1-3 are written; 4-8 are the outstanding work.

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
