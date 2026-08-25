# UFO! — Design

A CVBasic port of **Ed Averett's *UFO!*** (Magnavox Odyssey², 1981; sold in Europe as
*Satellite Attack*, Videopac 26), dual-target **TI-99/4A + ColecoVision** from one source.

You command an Earth Federation battle cruiser ringed by a **force field**. The field is your
armour, your ammunition and your best weapon at the same time — and spending it on any one of
those denies you the other two. That single tension is the whole game, and everything below
exists to serve it.

**Single player.** One life by default, faithful to the cartridge; `838` on the title opens a
setup screen that will give you up to nine.

---

## 0. Research base

*UFO!* has no instruction card in this repo and the manual scan on archive.org is unreachable
from this machine (connection refused; GameFAQs blocks fetches — see the
`gamefaqs-403s-webfetch` note). Everything below is from **secondary sources that agree with
each other**, cited per line. Where they disagree, the conflict is recorded rather than
smoothed over.

| fact | source |
|---|---|
| Ed Averett, 1981; "Earth Federation robot-controlled battle cruiser" | Wikipedia; manual blurb |
| Laser fires in **15 directions**, shown by a white dot in the force field | Wikipedia |
| The ship is ringed by **15 dots** that deplete when you fire and recharge over time | Wikipedia |
| The ring **destroys enemies and absorbs enemy missiles on contact** | Wikipedia |
| Ship travels at **half speed while recharging**, and is **vulnerable until fully recharged** | manual summary |
| Field colour runs **black (empty) to blue (full)** | manual summary |
| The shield absorbs **exactly one hit**, then takes ~**3 seconds** to recharge | odyssey2.info |
| Firing drops the shield, so good players barely fire and **ram instead** | odyssey2.info; bestretrogames |
| Three enemies: random drifter **1 pt**, Hunter-Killer **3**, Light-speed Starship **10** | Wikipedia; manual summary |
| Hunter-Killers **detect the player and link with another of their type** | manual summary |
| A destroyed enemy **launches three missiles in different directions** to make chain reactions | Wikipedia |
| Satellites fake their spin by **cycling the O2's built-in plus and multiply characters** | Video Game Critic |
| On death the ship **sparks and colour-cycles** before exploding, and you keep control | odyssey2.info |
| **Eight-way movement, no turn/thrust, no inertia** | bestretrogames; GameFAQs |
| One life; short sessions | odyssey2.info |

> **CONFLICT — which way the gun turns.** Wikipedia and Gaming After 40 both say the aiming dot
> rotates *toward* the direction the ship is moving. bestretrogames says it "rotates **clockwise**
> slowly around the ship, aligning with your travel direction by the time you've usually moved
> elsewhere." All three agree it *chases* your heading; they differ on whether it may take the
> short way round.
> **We build clockwise-only.** It is the literal reading of the third source, and it is the best
> explanation of why every reviewer without exception calls the aiming maddening.

> **DEVIATION — 15 dots become 15 units of charge shown as 8 dots.** A 16×16 sprite cannot
> resolve 15 separate dots on a ~13 px circle; they merge into a solid outline. The charge
> level is instead carried by the **colour ramp the manual itself describes** (black to blue),
> which is cheaper *and* closer to the source than counting pixels would be. The internal
> resolution stays 15 so the "deplete when you fire, recharge over time" rule keeps its grain.

> **DEVIATION — 15 firing directions become 16.** Fifteen is an odd number for a table and
> almost certainly an artifact of how the original packed its ring. Sixteen gives 22.5° steps,
> a power-of-two index, and no modulo (which compiles to a real `DIV` here — `CLAUDE.md` §3A).

**Worth verifying if you have the manual:** the recharge time, and whether firing costs a fixed
fraction of the field or a fixed number of dots. Those are the two numbers this design guesses
at, and both are tuning constants in one place (§3).

---

## 1. Performance budget (decided before line 1 — `CLAUDE.md` §5A)

| question | answer |
|---|---|
| Loop | **Real-time**, one `WAIT` per frame |
| Max simultaneously-moving sprites | **21** — ship, ring, gun dot, 2 lasers, 8 enemies, 8 missiles |
| `MOTION` vs `LOCATE` | N/A (CVBasic); every actor is a position + velocity add, **O(1)** |
| Enemy AI | **Reactive, no search.** Drifters and missiles have *zero* AI — constant velocity. Hunter-Killers do two compares, on alternate frames |
| Per-frame VDP reads | **Zero.** No `GCHAR`, no `COINC`, no `VPEEK` — there is no terrain to consult |
| Collisions | ring vs enemies (8), ship vs missiles (8), lasers vs enemies (16 worst case, usually 0) |

**Why this game is cheap, stated plainly:** *UFO!* has **no terrain**. Joust's frame went to
~180 island-row tests because every actor had to ask the world where the ground was; here the
world is empty and wraparound is free. Predicted **~2,400 instructions/frame, about 1.2 frames
per pass**, against Joust's measured ~11,200.

That is a *prediction*. Phase 1 ships a temporary two-digit loop-rate probe and it gets read
**before** phases 4-6 add the actors. If it comes in far off, the enemy cap is the dial — and
because dual-target parity is a requirement, any reduction would be proposed as a `#if TI994A`
split rather than taken from both.

### 1a. Fixed point, and why wraparound is free

Positions are **8.8 fixed point** in `#vars` (whole pixels in the high byte). Velocities are
**biased by +32768** so no comparison ever crosses zero — every `#var` compare in CVBasic is
**unsigned** (`CLAUDE.md` §3A). This is Joust's convention, adopted here from line 1 rather
than retrofitted.

- **X wraps for free.** 256 px × 256 = 65536, which overflows 16 bits *exactly*. Add the
  velocity and the wrap has already happened. No test, no branch, no cost.
- **Y needs one test**, because the play band is 160 px, not 256. Two unsigned compares against
  the band ends per actor per frame — about 20 instructions × 17 actors, roughly 340, which is
  the largest piece of per-actor overhead in the game and still cheap.

  The tracked position is the sprite's **top-left**, and the band is **16..175**, so a 16 px
  sprite still finishes on screen at 191. Sizing the band 16..191 instead would let an actor's
  bottom half hang off the screen at the moment it wraps, which reads as the object being eaten
  rather than as it crossing a seam.

### 1b. Sprite slots and the four-per-scanline rule

`SPRITE FLICKER OFF` — CVBasic's flicker is all-or-nothing and would strobe the player.

| slot | actor |
|---|---|
| 0 | ship |
| 1 | force-field ring |
| 2 | gun dot |
| 3-4 | lasers |
| 5-12 | enemies |
| 13-20 | missiles |

The VDP drops the **highest-numbered** sprites on an over-subscribed scanline, so the player's
three sprites are never the ones that vanish. But those three all sit at the *same* y — they
overlap by construction — so they consume three of the four slots on every scanline the player
occupies, and a fourth object at the player's height would be dropped **exactly when it matters
most**.

The fix, from phase 4, is the **slot rotation** already proven in `ASTIROIDS.bas:1201`: rotate
which enemy holds which slot each frame, so a crowded scanline *flickers* rather than making one
specific object invisible.

---

## 2. Screen

256×192, black space. Rows 0-1 are the HUD; the play band is **top-left y 16..175** (160 px, so
a 16 px sprite still ends on screen at 191), and every actor wraps within it.

```
 0  SCORE 0047                    HI 0210
 1                                   ^ ^      <- spares, only when ships > 1
 2   .              *                    .
 3          x                 .
 4                     . . o . .              o = gun dot (the laser's direction)
 5      .            .    .-.    .
 6                   .   (   )   .   x        ( ) = ship, . = force field
 7         *         .    '-'    .
 8                     . . . . .        .
 9              x                  *
...
23        .          *              x
```

Stars are **static characters**, not sprites — painted once and never touched again. They cost
nothing per frame and they are what makes wraparound legible; without a fixed reference the
player cannot tell that they moved.

---

## 3. The force field — the mechanic everything hangs off

One variable, `shld` = **0..15**.

| rule | behaviour | constant |
|---|---|---|
| **Armed** | only at `shld = 15`. Not "mostly charged" — full, or vulnerable | `SHMAX = 15` |
| **Fire** | costs 5, so three shots empties it and *one* shot leaves you naked ~1 s | `SHFIRE = 5` |
| **Absorb** | a missile or enemy body striking an armed ship: the enemy dies, `shld = 0` | — |
| **Struck unarmed** | death | — |
| **Recharge** | +1 every 12 frames, so 0 to full in ~3 s, matching the review | `SHTICK = 12` |
| **Speed** | full at 15, **half** below — you are slowest exactly when you are vulnerable | §4 |

Those six lines are the game. The field cannot be spent twice: shoot and you cannot ram, ram and
you cannot shoot, and either way you spend three seconds slow and mortal. Reviewers describe
good players as barely firing at all, and if this design is right that should emerge on its own
rather than needing to be taught.

**Render.** One ring sprite, **4 rotation phases** — the shimmer the sources describe, with the
"two rapidly circling dots" from Gaming After 40 baked into the phases (free: the phases exist
anyway). Charge is the sprite **colour**:

| `shld` | colour | reads as |
|---|---|---|
| 0 | hidden | no field at all |
| 1-5 | dark blue | barely there |
| 6-10 | medium blue | coming back |
| 11-14 | light blue | almost |
| 15 | **cyan, flashing white** | **armed** — unmistakable at a glance |

The flash at full charge is not decoration. "Armed" is a binary state with lethal consequences,
and the player must be able to read it in peripheral vision while dodging.


### 3a. Two ranges, and which one applies

Contact is tested at **two** radii, and which one is in play is the whole game:

| state | radius | outcome |
|---|---|---|
| **Armed** | `RAMR` = 14 px — the field's own radius | the enemy dies, `shld` drops to 0 |
| **Not armed** | `HULLR` = 9 px — the bare hull | **you die** |

So an unarmed ship can slip past at a distance that would have been a kill a moment earlier.
That asymmetry is what makes the recharge *tense* rather than merely inconvenient — the field
is not a damage buffer, it is a bigger and more dangerous silhouette that you sometimes have.

X folds mod 256, because the world genuinely is 256 wide. **Y cannot**: the band is 160, so an
8-bit difference of 97 is ambiguous between +97 and −159. Y is ordered first (`IF a >= b`) and
then folded over the band, which costs one branch and is unambiguous.

---

## 4. Movement, aiming and firing

**Movement is 8-way with no inertia** — the ship stops when you do. Diagonals are scaled so a
diagonal is not faster than a straight line:

| | armed (`shld` = 15) | recharging |
|---|---|---|
| straight | 384 (1.5 px/frame) | 192 (0.75) |
| diagonal | 272 per axis (about 1.5 total) | 136 |

**Aiming.** `aim` = 0..15, sixteen 22.5° steps, index 0 = up, increasing clockwise.

While the ship is moving, `aim` advances **clockwise by one step every 5 frames** until it
equals the joystick heading, then stops. **It never reverses and never takes the short way** —
a heading one step counter-clockwise of the gun costs *fifteen* steps to reach, about 1.2
seconds, and during that sweep the gun points at everything except what you want. This is
deliberate (§0), and it is the reason ramming becomes the real tactic.

The **gun dot** is drawn at `shipx + adx(aim)`, `shipy + ady(aim)` from a 16-entry signed offset
table — the same construction as `ASTIROIDS.bas:158-165`.

**Firing** costs 5 shield and launches a laser along `#vxt(aim)`, `#vyt(aim)`, a 16-entry signed
velocity table built the same way as `ASTIROIDS.bas:110-117`. Those tables are precomputed for a
reason recorded there and worth repeating: **CVBasic's 16-bit divide is unsigned**, so deriving
a negative component at runtime turns it into a huge positive one.

Two laser slots, 4 px/frame, about a 40-frame life.

---

## 5. Enemies

Eight slots, shared by all three types.

| enemy | pts | behaviour |
|---|---|---|
| **Drifter** | 1 | Constant random velocity, wraps forever. **Zero AI** |
| **Hunter-Killer** | 3 | Nudges velocity toward the player — two compares, alternate frames. On acquiring you, a second Hunter **links** and converges too |
| **Light-speed Starship** | 10 | Crosses fast and fires **guided** missiles that steer toward you |

**Speed is the balance.** The Hunter-Killer moves at **1.25 px/frame** against the player's
**1.5 armed** and **0.75 recharging**. So a Hunter is slower than you while your field is up and
faster than you the moment you spend it — you can outrun one only by being armed, which is
exactly the thing you have to give up in order to shoot at it. Starships and missiles both run
at 2 px/frame and cannot be outrun at all; they are problems you solve by not being there.

**Colour says which is which**, and the Hunter changes colour when it acquires you:

| enemy | colour |
|---|---|
| Drifter | light green |
| Hunter-Killer, unaware | magenta |
| Hunter-Killer, **locked on** | light red |
| Light-speed Starship | amber |
| Missile | white |

**Art: the plus/multiply alternation is the original's own trick.** Averett faked rotation on
hardware that had none by flipping between the console's built-in `+` and `×` characters.
Reproducing that exactly — two patterns, swapped every few frames — is most of why this will
read as *UFO!* rather than as a generic shooter, and it costs 64 bytes.

Hunter-Killers use the same two patterns in a hotter colour, so the thing chasing you is
recognisably the same species as the thing drifting past.

---

## 6. Missiles and chain reactions

Eight slots, 2 px/frame, about a 60-frame life, and the cheapest actor in the game: add
velocity, wrap, test one collision.

**Every destroyed enemy launches three missiles on diverging headings.** Those missiles can kill
other enemies, and each of those launches three more. Chain reactions are the scoring engine and
the reason the missile pool is 8 rather than 4.

At 1/3/10 points a chain is **legible** — you watch the score tick up one kill at a time and can
see the cascade travel. This is exactly what a ×100 scale would have destroyed, and it is why
faithful scoring was the right call rather than merely the authentic one.

---

## 7. Scoring

| | |
|---|---|
| Drifter | **1** |
| Hunter-Killer | **3** |
| Light-speed Starship | **10** |

Faithful to the cartridge. A strong game reads about 60. Session high score persists on the
title screen until power-off, as in Astiroids.

---

## 8. Difficulty

`diff` 1..9, starting at 1 and stepping up roughly every 30 seconds. It raises the **spawn
rate**, the **proportion of Hunter-Killers and Starships**, and enemy **speed** — never the
arena, and never the player's disadvantage directly.

Per `CLAUDE.md` §3A, a difficulty dial must never invert the goal: enemies always visibly
attack. Hunters get *better at pursuing*, not more numerous but passive.

`838` sets the starting `diff` as well as the ship count.

The mix at each end:

| difficulty | drifter | Hunter-Killer | Starship |
|---|---|---|---|
| 1 | 13/20 | 5/20 | **2/20** |
| 9 | 5/20 | 13/20 | **2/20** |

Spawn interval runs 92 frames down to 28. **The Starship stays flat at 2 in 20 at every
difficulty** — it is meant to be an event, and an event that happens constantly is just weather.

### 8a. Death, and why you keep the stick

The original lets the player go on steering through the entire destruction — the ship "starts
sparking and changing color furiously" before it explodes, and you are still flying it. That is
reproduced here: `dying` counts 48 frames during which the hull cycles colours, the arena keeps
moving, you keep control, and a descending sweep plays underneath. Only then does it explode.

It matters more than it sounds. You are not watching a cutscene — you are watching your own ship
come apart underneath you while you still have the stick, which is a materially different feeling
from a freeze-and-explode.

Collision is gated on `dying` so the ship cannot die twice, and the death sound owns channel 0
outright for the duration.

### 8b. Respawn clears the missiles, not the satellites

Wiping the arena would make every death a free reset. Leaving the missiles would make the next
one a lottery, because a guided missile already in the air cannot be dodged from a standing
start in the middle of the screen. So missiles go, satellites stay.

---

## 9. Sprites and characters

`DEFINE SPRITE` art is generated by `assets/genart.py` — ASCII in, TMS9918 quadrant interleave
out. **Edit the ASCII, never the emitted bytes.**

| art | patterns | notes |
|---|---|---|
| ship | 1 | small, centred in the 16×16 cell |
| force-field ring | 4 | rotation phases; charge is colour, not pattern |
| gun dot | 1 | 4×4 blob centred |
| satellite | 2 | the `+` / `×` pair (§5) |
| starship | 2 | saucer, two frames |
| laser | 1 | short bolt |
| missile | 1 | 2×2 dot |
| explosion | 3 | shared by every death |

Font: `assets/genfont.py`, adapted from Joust's — a heavy squared arcade face, characters 32-90
only, 8 bytes each.

---

## 10. Sound

`SOUND ch, divisor, vol`. **The second argument is a 10-bit divisor, not a frequency** — max
1023, and *smaller is higher* (`CLAUDE.md` §3A). Every effect gets an explicit note-off or it
sustains forever, and a two-note effect needs two channels, because two `SOUND`s on one channel
just cancel.

| event | shape |
|---|---|
| Laser | short high blip |
| Ram / field absorb | dull thud plus a click of static |
| Enemy destroyed | short noise burst |
| Chain reaction | the same burst, pitch rising per link |
| Field fully recharged | **a soft two-note rise** — an audible "you are armed again" |
| Death | descending sweep (an *increasing* divisor) over the spark animation |

The recharge cue earns its channel: the player is watching enemies, not their own ring.

---

## 11. Controls

| Action | TI-99/4A | ColecoVision |
|---|---|---|
| Move (8-way) | Joystick 1 | Joystick 1 |
| Fire | Fire, or space | Fire |
| Start | Fire on the title | Fire |
| Setup | type `8` `3` `8` on the title | `8` `3` `8` |

**ALPHA LOCK, and why this game cannot dodge it.** On the TI the ALPHA LOCK key shares a line
with the joystick's vertical axis: latched down, the console reports an up or down direction
that is **never released**. Every other game in this repo sidesteps it by never reading the
vertical axis — but *UFO!* is a multidirectional shooter, and a ship that cannot fly up is not
the game.

So the vertical axis is read, and the title screen **says so out loud** on the TI build
(`#if TI994A`): `TI-99: ALPHA LOCK MUST BE UP`. That is what TI cartridges of the era did, and
it is the honest fix — the alternative is a ship that flies off on its own with nothing on
screen explaining why.

**The `838` setup screen is still driven by number keys**, with the key printed beside each
field, because a *menu* has no such excuse.

---

## 12. Hazards this game walks into

Each is silent, and each has cost a session before (`CLAUDE.md` §3A):

- **`CONST` > 255 truncates**; bare literals do not. Every screen offset is a bare literal.
  `tools/bigconst.py` fails the build.
- **A plain var is 8-bit** — `tools/bigvar.py` fails the build.
- **`<cmp> AND <cmp>` is miscompiled on the 9900.** Every collision test here is two-axis, so
  this comes up on nearly all of them. Nest single-comparison `IF`s.
- **`MPY` clobbers r0** — never read a 16-bit var immediately after multiplying it.
- **Keep every `DATA BYTE` block even**, or every word table after it silently misaligns.
- **`%` compiles to a real `DIV`** — hand-convert. The 16-direction index is masked (`AND 15`).
- **A `GOSUB` left by `GOTO` leaks the stack** — invisible on TI, fatal on Coleco.
  `tools/gosubtrace.py` fails the build.
- **Sprite y = 208 terminates the sprite list** — the play band tops out at 191, and dead
  actors park at 209.

---

## 13. Build

```
./build-ti.sh        ->  src/UFO_8.bin    Classic99 / js99er
./build-coleco.sh    ->  src/ufo.rom      CoolCV / blueMSX
```

Both run `bigvar.py`, `bigconst.py`, `gosubtrace.py` and `assets/checklayout.py` **before**
compiling, so a truncation, a leaking `GOSUB` or a broken screen layout fails the build rather
than shipping. The TI script reports fixed-area bytes free against the 24,336-byte cap.

**`checklayout.py` earns its place.** A `PRINT AT` that runs past column 31 wraps onto the next
row and overwrites it; a HUD `VPOKE` can land inside a label another routine printed. Both are
arithmetic on a bare offset, so neither is visible in the source. The `838` screen shipped its
difficulty digit into the middle of the word `DIFFICULTY`, which reads as a typo in the label
rather than as a misplaced value.

Note what the first version of that checker got wrong, because it generalises: it compared
writes only against strings under the **same label**, and the setup screen prints its text in
`setup838` but writes its digits in `su_draw` — so it passed the exact bug it was written for.
Rows only mean the same thing within one *screen*, and the screen boundaries are not derivable
from the source, so they are declared in a table at the top of the file.

---

## 14. Phase plan

| phase | content | state |
|---|---|---|
| 1 | Space, starfield, ship, 8-way movement, wraparound, HUD, title, **loop probe** | **built** |
| 2 | Force field: ring, charge, drain, recharge, half speed, colour ramp, armed rule | **built** |
| 3 | Clockwise gun drift, gun dot, laser fire and flight | **built** |
| 4 | Drifters: plus/multiply spin, spawning, ram kill, laser kill, player death | **built** |
| 5 | Hunter-Killers (with linking) and Light-speed Starships with guided missiles | **built** |
| 6 | Chain reactions — three missiles per kill | **built** |
| 7 | Death sequence (sparking colour-cycle, control retained), game over, high score | **built** |
| 8 | `838` setup (ships 1-9, starting difficulty), sound, difficulty escalation | **built** |

Each phase builds and runs on **both** targets before the next begins.

Phases 2 and 3 were built together: firing is what drains the field, so a shield with nothing
to spend it on cannot be tested, and a gun with no cost attached is not the mechanic.

---

## 15. Acceptance criteria

- [ ] Both targets build; TI reports bytes free; all three gates pass
- [ ] The ship visibly **slows** while recharging
- [ ] A ram kills an enemy and drops the field to zero
- [ ] One shot leaves the player visibly vulnerable for about a second
- [ ] The gun visibly **lags**, and only ever turns one way
- [ ] A kill launches three missiles, and a cascade is possible and visible
- [ ] Wraparound reads correctly against the static starfield on both axes
- [ ] `838` sets ships 1-9 and starting difficulty
- [ ] Loop rate measured, recorded in §1, and acceptable on **both** targets
- [ ] Temporary loop probe removed before the game is called done
