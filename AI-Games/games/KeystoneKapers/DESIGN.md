# Keystone Kapers — Design

A CVBasic port of **Garry Kitchen's *Keystone Kapers*** (Activision, Atari 2600, 1983;
AX-025), dual-target **TI-99/4A + ColecoVision** from one source.

Officer Keystone Kelly has Harry Hooligan cornered in Southwick's Emporium — a department
store **eight screens wide and four levels tall** — and fifty seconds to run him down before
he reaches the roof and vanishes. Kelly is fast. The store is long. Everything in it is in
the way.

**Single player.** One active Kop and three in reserve, faithful to the cartridge; `838` on
the title opens a setup screen for Kops and starting Krook.

---

## 0. Research base

The manual scan on archive.org is image-only (JPX streams, not OCR'd — confirmed by fetching
it), so the text below comes from the **AtariAge HTML manual**, the **Atari 5200 manual** at
atarihq, Wikipedia, PixelatedArcade and the activisionpatches strategy page. Where they
disagree the conflict is recorded rather than smoothed over — that is the rule that saved
Joust from shipping without a pterodactyl.

| fact | source |
|---|---|
| Garry Kitchen, Activision 1983; the store is **Southwick's Emporium** | Wikipedia |
| The store is **eight times wider** than the visible display; the view scrolls at the edges | PixelatedArcade |
| Escalators are at **alternating ends** of the map; the **elevator is in the centre** | PixelatedArcade |
| Kelly starts at the **first-floor entrance, lower right**; Harry at the **second-floor elevator door** | PixelatedArcade; activisionpatches ("centre of the second floor") |
| Kelly runs left/right on the stick; **jumps on the button**; button + direction = **long running jump** | AtariAge manual |
| Kelly **ducks when you pull the stick back** | AtariAge manual |
| **Push forward to step into an open elevator, pull back to step out** | AtariAge manual |
| Kelly **boards an escalator by touching it** | AtariAge manual |
| **Jump over** shopping carts, beach balls and cathedral radios | AtariAge manual; activisionpatches |
| **Duck under** toy biplanes | AtariAge manual; activisionpatches |
| A cart / ball / radio costs **9 seconds** | AtariAge manual; activisionpatches; atarihq |
| A **biplane costs a Kop** | activisionpatches; Wikipedia; atarihq |
| **50 seconds** per Krook | activisionpatches; Wikipedia |
| The timer **flashes when 9 seconds remain** | atarihq manual |
| Money bags and suitcases are **50 points each** | AtariAge manual; activisionpatches |
| Capture bonus = seconds remaining × **100 / 200 / 300** | AtariAge manual |
| **Three reserve Kops**; a bonus Kop **every 10,000 points**, three reserves maximum | AtariAge manual; atarihq |
| A Kop is lost to **time out, biplane, or Harry escaping off the roof** | atarihq manual |
| The scanner shows **all floors and the roof**: Kelly a **black dot**, the crook a **white dot**, the elevator a **grey square**, escalators **black slashes** | atarihq manual |
| **You are invincible inside the elevator, until you step out** | activisionpatches |
| Rising levels increase **obstacle speed** | activisionpatches |
| The store interior is flat **green**, floors are **thin light lines**, storefronts are plain blocks, the sky is **navy** with an orange skyline, the roof deck **grey**, Kelly **blue** | Atari 2600 screenshots, pixelatedarcade |

### 0a. The look is the ATARI 2600's, and it is measured

**The reference is the 2600 version** — the one this is a port of. Two earlier
attempts got it wrong in two different ways, and neither read as a colour bug;
both read as *a different game*:

1. **Dark blue store, from memory.** The store is green.
2. **The ColecoVision palette.** Tempting, because that machine has the same VDP
   and therefore literally the same sixteen colours, so it is the easiest thing
   to match. But it is a different-looking port: chunky floor treads, detailed
   shelving, a black sky with magenta buildings.

What the 2600 actually looks like, and what we now draw:

| element | 2600 | here |
|---|---|---|
| Store interior | flat medium green, wall to wall | `MGREEN` |
| Floors | thick **olive bars** with a light top edge | ← *corrected, see 0b* |
| Storefronts | blue counters on the floor + narrow white pillars | ← *corrected, see 0b* |
| Sky strip | blue-violet; orange skyline above the roof deck | **`CYAN`** + `MRED` — see 0c |
| Roof deck | grey | `GRAY`, and it now backs the whole roof band |
| Score | **white**; timer and Kop hats **black** | ← *corrected, see 0b* |

**Quiet blocks are still the thing.** Bright storefronts on a green field are
harsh and busy; the 2600's charm is that it is mostly flat green with a few calm
rectangles in it — *simple, and still pretty* — so detail works against it as
much as the wrong hue would. `assets/preview.py` renders a screen from the
shipped bytes so this can be checked in a second instead of through an emulator.

### 0b. Measured from gameplay VIDEO, which overturned part of 0a

Everything in 0a above was read off **static screenshots**, and three of its
rows were wrong. `assets/grabref.ps1` pulls frames from a gameplay recording
(and documents the three separate reasons the obvious command line fails on this
machine). Motion also settles things a screenshot cannot: which objects move,
how the scanner is furnished, and what the HUD does as the clock runs out.

**What the video corrected:**

- **The floors are not hairlines.** They are **thick olive/dark-yellow bars,
  about 5 px, with one lighter yellow row along the top edge** — substantial,
  and the strongest horizontal line in the picture. 0a asserted the opposite
  ("thin light lines… thick treads alone make the store read as the
  ColecoVision port") and built a rule on it. The rule was sound — the CV port
  *does* have chunkier treads — but the premise was not: the 2600's own floors
  are bars, not lines. **This is the one correction that changes how the store
  reads at a glance, so it is the reviewer's call, not an automatic edit.**
- **The score is white, not yellow**, and the **timer and the Kop hats are
  black**, all three sitting in the blue-violet sky strip. The hats are bowler
  silhouettes at the left, the timer immediately to their right.
- **The storefronts are two different shapes, not two blocks.** Wide **blue
  counters** stand *on* the floor bar (bottom-aligned, roughly a third of a
  screen wide, half a band tall), and separate **narrow white pillars** span a
  band's full height. 0a had them as two same-shaped rectangles.

**What the video confirmed or newly pinned down:**

| element | what it looks like |
|---|---|
| Elevator | a **dark-green shaft column** through all three shopping floors — not the roof — with a **pale cyan car** riding in it |
| Escalator | a dark-green outlined parallelogram with **white step dashes**, plus a horizontal landing rail at the top |
| Shopping cart | a **white wire basket** — a mesh of uprights between two rails — on a solid black wheeled base |
| Beach ball | a **solid red disc**, not a ring |
| Cathedral radio | **yellow**, an arched case widest at the foot with two small prongs on top |
| Toy biplane | **dark green** body with a **light-green** propeller — two sprites; drawn from above so it reads as an aircraft (0n) |
| Money bag / case | **yellow box with a black handle** |
| Scanner | green field, **yellow horizontal lines per floor**, **black diagonal slashes** for escalators, a **pale block** for the elevator, and a white dot per actor — exactly the furniture §6 draws |
| Low time | the HUD digits and the Kop hats **change colour** as the clock runs down |

The frames are not checked in — they are someone else's recording. `grabref.ps1`
regenerates them into a scratch directory on demand; the observations live here.

### 0d. Two colours per SCAN LINE, not per character

A character that must show both a floor bar and the escalator crossing it looked
impossible — four colours in one cell — so the flight was shortened to stay clear
of the bar, which dragged the handrail up away from the steps. That was wrong,
and the reviewer caught it: colour here is per **scan line**, and any one line of
that character needs only **two** — whatever the floor shows on that line, and
black for the flight.

So the cells that cross a floor get **composite** copies: the same pattern,
coloured line for line as the floor is. Black on yellow where they cross the
bar, black on green above and below it. The floor runs across underneath the
staircase instead of being punched through by it.

**The roof needs its own set.** It is not coloured like a shopping floor — its air
is grey and its "floor" is the white-topped deck — so the flight up from floor 3
has a second pair of composites. Only the west flight climbs to the roof, so only
it needs them.

**This pushed the store past the scanner's characters.** The canvas used to start
at 144 and the store table grew to 155. `genart.py` now *checks* that overlap and
fails with the list of bases to move, rather than letting two tables quietly
overwrite each other's patterns.

---

### 0e. A character number written by hand is a bug waiting for a rename

The character table is **generated and automatically de-duplicated**, so a code
is not a fact about the source — it is a *result*. Adding one character, or
merging two that happen to be identical, renumbers everything after it, and any
number written down by hand then points somewhere else with no error anywhere:

- `CONST CH_CASE = 113` shipped once. A renumbering had made 113 `EXITC`, so the
  second collectible drew an **exit door** in the aisle — a plausible-looking
  box, and nothing connecting it to a change made in another file.
- `CH_ECAR` and `CH_EDOOR` were **both one too high**, because `SHELFB` merged
  into `SHELFT` and `EDOOR` merged into `SHAFT`. The elevator shaft drew the
  *car* pattern on every floor and the open car drew an *escalator step*. That
  one sat in the shipped cart until a checker was written for it.
- The same class bites the `DEFINE CHAR 96,N,store_pat` count: a table that
  outgrows its load is simply not loaded, and the extra characters draw as
  whatever happened to be in VRAM.

**`assets/checkchars.py` checks every `CONST CH_<NAME>` against `CODES["<NAME>"]`
and both load counts against the table's real length**, and fails if it finds no
constants at all — a check that quietly stops applying is worse than one that
fails.

---

### 0f. The ride, the jump onto it, and the crook's speed -- all measured

**The rider was never on a step.** He moved at the staircase's slope, 2 px
along for 1 up, and the steps moved at the same rate -- and he still floated,
because the two were never put *in register*. The bottom tread sits 4 px above
the floor, and the whole staircase slides another 1 px up per animation phase,
so a rider boarding without that `+ escp` term starts up to 3 px out and stays
out for the entire ride. Nothing about that is visible in either file: the
rates match, the constants look right, and the rider simply travels beside the
steps.

The fix is to derive everything from **which step he is on**. The staircase is
a straight line, so a step 4 px higher is 8 px further along it, and one number
-- the step's height above the floor being left -- fixes the rider's x, his y,
and the rest of the ride:

```
west  klx = 99 - 2*height        east  klx = 140 + 2*height
```

Walking on, that step is the bottom one (`4 + escp` px up) and the feet have to
climb onto it: he rises 2 px a frame while the tread rises 1, so the gap closes
in `4 + escp` frames and he is riding it after that. `assets/checkride.py`
simulates every ride -- 3 floors x 2 directions x 4 phases x 4 ways on -- and
checks the pixel under his feet is the top of a tread in the bitmap that will
be on screen that frame.

**And matching the rates was still not enough, because they were two different
clocks.** The rider advanced by the frame delta -- `fdv` -- like everything
else in the loop, while `esc_tick` advanced the staircase by one phase per loop
*pass*. Those agree only while the loop keeps up. The moment a pass costs two
frames the rider travels 4 px along and 2 up while the staircase travels 2 and
1, and he climbs off the step he is standing on. It compounds across the ride:
his feet start planted on a tread and end floating several pixels above it.

**The obvious repair makes it worse, and that is the interesting part.**
Pacing the animation by `fdv` too locks the pair together and *aliases*: there
are four phases covering an 8 px period, so stepping by 2 flips the pattern
between two positions half a period apart -- direction unreadable -- and
stepping by 3 runs the sequence 0,3,2,1, which is the **wagon-wheel effect**.
The staircase visibly carries its steps *downward* while the rider goes up. A
4-phase cycle can only be stepped by one, whatever the frame rate.

So the animation is the clock, and **the rider is paced from it**: both advance
by a fixed 2-across-and-1-up per pass. That is the only arrangement in which
they cannot drift, and it is what "the player moves at the rate the steps carry
him" actually means. The price is that a ride takes 36 *passes* rather than 36
frames, so it slows when the loop does -- honest behaviour for a machine that
is carrying you, and the two screens with a staircase are the busiest in the
game (`esc_tick` alone rewrites 120 bytes of pattern table per pass).

`checkride.py` reads both clocks out of the source and fails if they differ, if
the phase is stepped by more than one, or if a foot leaves a tread at any of
frame deltas 1, 2 or 3. All three of those shipped at least once.

**And then it let him jump clean THROUGH the staircase.** Boarding required
his height to *cross* a step's exact height in one frame, which is too strict:
he covers 4 px a frame, so a given step is under him for about two frames of
the descent, and if his arc did not happen to pass through that step's own
height in those two he sailed over the whole flight and landed on the floor
beyond it. The rule is now the one a floor uses -- coming down, and at or below
the step. It cannot over-reach because only the bottom three steps are in
range at all.

**A jump at the staircase used to be cut short.** Boarding fired the moment he
entered the foot's 24 px zone, which zeroed his height in mid-air and dropped
him at the bottom of the flight -- so aiming a jump at the steps was strictly
worse than walking. Now the arc finishes and the staircase is simply what he
lands on: the step under him follows from his x, and he boards when his feet
*cross* its height coming down. Only the bottom three steps are within a 14 px
apex at 4 px a step, so it is a ladder rather than a divide.

**The crook was too slow, and by a measurable amount.** Tracked off the
reference video frame by frame, the 2600's Kelly covers **0.40 screen widths a
second** and its Harry **0.193** -- a ratio of **2.07**. Ours was 2.67. (The
absolute speeds cannot be copied: ours are ~2.3x the original's, because our
Kelly is charged three full traverses where the original's player picks a much
shorter path.) Harry is now 1.75 px/frame, a ratio of 2.29.

2.0 would match the original exactly and cannot be used. **Our** routes are not
the original's -- Kelly's is 1.95x Harry's -- so a speed ratio of 2.0 leaves him
5.2 s ahead at the escape edge, less than one beach ball. 1.75 leaves 10.1 s.

**That margin only became visible once the check stopped ignoring the lift.**
`checkchase.py` charged Kelly the full on-foot route and nothing else, which is
not a conservative assumption but a route no player takes: the shaft is on
screen 3, *on his way* from his spawn to floor 1's escalator, and it carries him
two floors. Modelling only the foot route made the chase look 5 s tighter than
it is -- and that phantom tightness was being used to argue the crook's speed
down. A check that is wrong in the safe direction still shapes the design, and
here it was shaping it wrongly.

**The scanner's surround is GREY, not black.** Also measured: the 2600 insets
its scanner in a grey band the width of the screen. It was briefly black, which
reads fine and is not the original.

---

### 0g. The run cycle, and what a symmetric leg costs

Measured off the reference video frame by frame: the original runs a **four-pose
cycle with a forward lean**, and the arms swing with it — a skin-coloured hand
appears beside the face on half the frames.

Ours was **two poses, and both were symmetric about the centre line**. A
symmetric leg says nothing about which way the figure is going, and mirroring
it for the other facing produces the identical pattern — so half the sprite
table was paying for nothing and the run read as a shuffle.

**Four poses cost two drawings.** In a side view, "left foot forward" is the
horizontal mirror of "right foot forward"; the facing lives in the hat, the
face and the tunic, not in the legs. So the cycle is

```
A, B, mirror(A), mirror(B)
```

and **the same four patterns serve both facings**, entered at a different point
— invisible, because the phase runs continuously anyway.

**The arms swing inside the tunic's own sprite.** A skin hand would be a fourth
box on those rows, and four is the entire per-line budget once Harry is on
screen (§5). Moving the *arms* into the blue tunic pattern costs one extra
pattern per facing and no boxes at all: the leading arm lifts on the two
full-stride frames and hangs on the passing frames.

**The cycle rate is matched to the speed, per character.** A pose has to cover
about a stride's worth of ground or the figure skates. Kelly runs 4 px/frame and
uses bits 2-3 of his counter (four frames a pose, 16 px); Harry runs 1.75 and
uses bits 3-4 (eight frames, 14 px).

**The crouch has a front now.** It was a symmetric blob, so mirroring it
produced a nearly identical shape and ducking read as being squashed rather
than as dropping into a crouch and still looking where you are going. The brim
is the tell: it reaches further forward than back, the head tucks behind it,
the back hunches over the leading knee and the feet trail.

**`assets/previewrun.py` renders the whole thing from the shipped bytes** —
every frame, both facings, both characters, plus the crouch — because a walk
cycle cannot be judged from a table of hex. And `assets/checkchars.py` now
covers the sprite numbers as well as the character ones: adding the four run
frames renumbered everything after them and pushed the obstacles up by two
sprites, so `DEFINE SPRITE 24,1,spr_cart` would have loaded the shopping cart
straight over Harry's third leg frame. Nothing in the build would have said a
word.

---

### 0h. The figures, transcribed onto the 2600's own pixel grid

§0g redrew the run cycle and it still did not look like the game. The reason is
that everything up to then had been drawn from an *impression* of the reference
rather than from a measurement of it, and the proportions were wrong in a way
that reads as a different character.

**Recovering the grid.** The only format the video offers is 480x360 for a
160x192 display, so neither pitch is an integer and — 2600 pixels being
famously non-square — the two are not the same. Both had to be measured:

- **Vertical** from the store: floor bars 51 video px apart, a band being 32
  scanlines, gives **1.594 px per scanline**.
- **Horizontal** from the sprite: a TIA player is exactly 8 clocks and his
  widest row is 20 px, so **2.5 px per clock**.

Sampling each native cell by vote (the encode is soft) then gives the real
bitmap. `assets/cmpref.py` keeps the transcription and squashes our 16x24
figure back down to their 8x19 to compare, because "does it look like the
video" is a question about the silhouette, not about our extra resolution.

**What the measurement said.** Kelly is 8 clocks by about 19 scanlines:

```
 0 ..KKKK..   crown, 4 of 8            9 .....BB.   a shoulder stub
 3 KKKKKKKK   brim, the FULL 8        10 .BBBBBB.   body, 6-7 of 8
 5 ..SSS...   face, 3 of 8            18 ...KKKKK   dark feet
```

**His head is 42% of his height** and the brim is a flat line right across him.
Ours was a small head on a long thin body with wire arms and separated legs — a
different character entirely. Harry measures the same way at about 17 scanlines
with the **face a third of him**, a flat white cap with one black band, a
striped body and legs that split wide.

Carrying those proportions onto our 24 px figures takes **15 of Kelly's 19 rows
to an exact match**; the four that differ are the bottom, where the reference
narrows to dark feet and we keep articulated legs — deliberate, because we have
twice the horizontal resolution and a four-frame cycle to animate.

**The crouch got a third sprite out of it.** It was two bands, hat and body
together in blue, which threw away the one feature that says Kelly at this
size. Three bands is three boxes on those eight rows; it is affordable because
obstacles are suppressed on Harry's floor, so no biplane ever appears there and
he need never duck level with the crook. **And in the air he now holds one
stride** — cycling the legs through a jump reads as running on nothing.

**Kelly's wider brim costs Harry two scanlines of stripe.** With the hat band
reaching y+5, the line where Kelly's brim is level with Harry's cap carries five
boxes. The VDP drops the highest-numbered, which is Harry's stripe sprite — the
degradation this layout was designed around from the start. `checkbands.py`
declares exactly that one droppable and fails on anything else, and it now
reads the pattern numbers by NAME from genart and the draw offsets out of
`KEYSTONE.bas`, because it had gone stale in both at once: reporting overlaps
that were not there while no longer checking the layout that was.

---

### 0j. The animation ran backwards, and one frame is not a facing

The figures were transcribed (§0h) and the run still looked wrong: he faced the
way he had come. The transcription was right; the *frame it came from* was not.

A single frame does not establish a facing. The one used was from a moment
where Kelly was **turning** -- his x wandered 240, 234, 234, 236, 234 -- and its
body leaned the other way from a real run. Building the base art on it meant
`kldir = 1` (right) selected a left-facing figure and the entire animation,
both directions, came out inverted.

The fix is a rule rather than a redraw: **take the frame from the middle of the
longest monotone run.** `dirs.py` searches for exactly that, and it finds a
127-frame rightward stretch. Transcribed from inside it, the right-facing
figure has the shoulder stub on the LEFT and the body inset a clock either
side. Laid out row-for-row against that, `cmpref.py` now reports **18 of 19
rows identical** -- the one that differs is the reference's dark feet, which a
single-colour legs sprite cannot do.

### 0k. The crouch bends over, and 11 px is the ceiling

The crouch was 8 px, which is not a crouch: there is no room at that height to
draw a figure bending in a *direction*, so it read as a squash however it was
mirrored. It is 11 px now -- rump high and behind, back sloping down and
forward, the black brim thrust out ahead, the face tucked under it.

**11 is a limit, not a preference,** and the reasoning generalises to any
duck-or-jump obstacle. Duckable means the obstacle's hitbox clears the crouch;
jumpable means it clears under the 14 px apex. Raising the crouch raises the
duckable floor, so past some height a band of beach-ball heights is *neither* --
an obstacle that cannot be avoided at all. A sweep of every crouch height
against every ball hitbox puts the break at 12, and shrinking the ball does not
move it: **the apex is what binds**, and the apex cannot rise because a 24 px
Kelly plus a 14 px jump already sits 2 px under the band ceiling.

The biplane is raised to match, which was the reviewer's suggestion and is what
buys the extra pixels: an 11 px crouch clears it, a 24 px standing Kop does not,
and a jump still cannot -- so it stays the one obstacle that must be ducked.
`assets/checkball.py` fails the build on any dead band, and it caught this at
16 px before it could ship.

It now flies at **16..22**, not 12..18. At 12 the crouch passed under it by a
single pixel, so a duck that plainly worked still looked like a squeak and a
duck one frame late was a hit -- the *window* was correct and the *reading* was
not. 16 is as high as it can go and still catch a 24 px standing Kop, and the
14 px apex is under it, so raising it costs nothing and buys five pixels of
visible daylight.

**The pose is a bend at the waist, and where the HEAD goes is the whole read.**
A squat keeps the head up and compresses the body under it; a bend puts the head
forward and down with the back gone horizontal above it and the legs still under
the hips, behind. The first eleven-pixel crouch had the head buried under a flat
slab of back with the legs splayed underneath, and it read as a dive -- which is
why "it is still a squish" survived the change from eight pixels to eleven. The
back is now a wedge high and to the **rear**, the hat is clear of it with a
crown and a brim projecting **forward** over the face, and the legs stay under
the hips. So the silhouette has a front and a back and points the way he faces.

**The reference could not settle this one.** About 2,700 sampled frames of the
longplay were searched for a ducking Kelly -- by figure height, by moving-blob
height, and by requiring the hat/face/tunic stack -- and the player never ducks
in any of them; the height sits at a flat 29 video px throughout. (The two
shortest hits were the Activision logo.) So unlike the run cycle (§0h) this pose
is reasoned from the mechanic, not transcribed, and it is recorded here so the
search is not run a third time.

### 0p. How the levels actually advance

Researched, not invented: two independent readings of the published level guides
agree on this table, and `assets/checklevels.py` now reads every threshold back
out of the source and fails the build if one moves.

| Krook | what changes |
|---|---|
| **1** | short beach balls, **and nothing else** |
| **2** | + cathedral radios |
| **3** | + shopping carts (slow) |
| **4** | + biplanes (slow) |
| **5** | the balls go **tall** -- they stop being jumpable and must be ducked |
| **6** | a **second** hazard per floor ("double radios") |
| **7** | carts get faster |
| **8+** | biplanes get faster; after this the levels stop changing |

**There are no biplanes on Krook 1**, which is the point of the whole ramp: the
one hazard that costs a *life* rather than nine seconds is the fourth thing the
player meets, not the first. Our previous model had the hazard *kind* fixed per
floor by a static table and only the *speed* ramping, so a new player met a
biplane on the first screen of the first round.

The static placement table stays -- it still decides *where* on each floor a
hazard sits. What is new is a gate on the way in: a hazard that has not arrived
yet becomes a **beach ball** rather than nothing, so a floor is never empty and
Krook 1 is exactly the "short balls" screen the guides describe.

#### Enemy speeds, per kind, from the video

One global `obsp` could not express this, because the original ramps carts and
biplanes on *different* rounds. Each kind now carries its own speed:

| kind | px per pass | why |
|---|---|---|
| beach ball | 2 | measured at 0.82 px/frame = 49 px/s |
| shopping cart | 2, then **3** from Krook 7 | measured at 0.80 (48 px/s) **and** 1.21 (73 px/s) |
| biplane | 2, then **3** from Krook 8 | same two speeds |
| cathedral radio | 0 | stationary |

The base of 2 is not a guess. Carts were tracked in the reference at 0.80 and
1.21 px/frame, and at this loop's ~25 passes a second those are **exactly 2 and
3 px per pass** -- so the two speeds the original puts on screen are the two
speeds here. The old ramp started at 1 (25 px/s), which was half the slowest
cart the reference ever showed.

#### Scoring

* time remaining x **100** on Krooks 1-9, x **200** on 10-15, x **300** from 16;
* money bags and suitcases **50** each;
* a spare Kop every **10,000** points.

The x100/x200/x300 bands now have two independent sources. The manual's own
wording suggests 1-8 / 9-16 / 17+ instead, and that disagreement is recorded in
section 0 -- the published guides win here because two of them agree.

#### The bonus is counted out, not awarded

Dropping the whole sum into the score in one frame tells the player a number.
Ticking the clock down a unit at a time -- score climbing, a beat under each
step -- tells them what the number was *for*, and it is the pay-off for every
second they saved. `bonus_count` does it in about a tenth of a second per unit.

It also **removed** code rather than adding it. The old `calc_bonus` summed the
bonus by repeated addition to dodge two hazards at once: `tsec * bmul` is an
8-bit product (a 50-unit capture in the x300 band pays 15,000, six times past a
byte), and multiplying properly lands on the MPY/r0 hazard where a 16-bit
variable read straight after being multiplied returns the product's high word.
Counting it out a unit at a time makes the loop the player watches *be* the
arithmetic, so there is no multiply to work around. It fixes the last-tick case
for free as well: `bn_loop` tests `tsec = 0` on entry, where the old
`FOR bi = 1 TO tsec` would have run its body once and paid a full multiplier for
no time at all.

#### The aeroplane is yellow, over black

Two sprites, and the trick is **priority**: a lower sprite number wins on the
TMS9918, and the body sits in slots 8-15 with the detail in 16-23. So the black
layer can only show through where the yellow has *nothing* -- which means the
cockpit is a **hole** in the body, filled from beneath, while the propeller
needs no hole because it hangs off the nose where the body has no pixels. The
detail being the low-priority half is deliberate: when Kelly, a plane and a high
ball share a scan line the VDP drops the highest-numbered sprite, so what
disappears is decoration and never the plane the player has to duck.

### 6a. The scanner: characters underneath, sprites on top

The instrument is split by what MOVES, and that turned out to be the whole
design.

| | drawn as | why |
|---|---|---|
| floor lines, flights, lift shaft | **characters** | fixed relative to the canvas; cost nothing to keep |
| the lift car | **characters**, redrawn on move | moves rarely, and only vertically |
| Kelly and Harry | **sprites** (24, 25) | move constantly, and need to be over everything |

Four rows a level, 4 px of grey margin top and bottom. Rows 0-2 are that
floor's **air** and row 3 is its **yellow line**, which nothing else touches.
The flights are a three-step diagonal down the air, leaning the way they climb;
the car is three pixels tall; and both actors are three-pixel sprites over the
top.

**Why sprites for the actors and nothing else.** A colour byte covers one 8x1
scan line of one CHARACTER, so a whole pixel row of this canvas can only be one
colour. As characters the Kop and the crook could therefore have a row each and
stood a single pixel high, and the two attempts to make them taller both cost
something else: five rows a level put the floor line on the escalator's grey
row and made the lift car -- also grey, also there -- vanish into it completely;
six rows took the margin and read as too big. Per-character colouring did work,
and it is what a sprite gives away for free.

As sprites they need no colour table, no erase and no priority arithmetic: they
draw over the furniture because sprites always do, and nothing shifts to make
room. **The blink went with it.** Kelly flashed only because two markers inside
one character merged into one colour; two sprites are two colours wherever they
stand. And the furniture is drawn ONCE rather than every tick, because there is
no longer a marker erase ANDing bits out of whatever it stood on.

It also removed code: `scan_mark`, `scan_wipe1`, `scan_set`, `scan_clr` and
`scan_addr` all existed to paint, erase or recolour a marker made of character
pixels. **790 bytes came back.**

One thing to watch, and it is the same class as the vanished lift car: the
Kop's marker is black and the flights are black, so where he stands on one --
the extreme end of a floor that has an escalator -- he is briefly invisible.
`checkscan.py` checks that the two SPRITE colours differ from each other; it
cannot check this one, because a sprite over a character is not something the
colour table knows about.

### 6b. What the crook does when he is cornered

He rides the flight that comes UP to his floor back DOWN, which Kelly cannot do
-- an escalator only goes up. Without it the chase always ended in the same
corner, and a crook with nowhere to go is not a chase.

Three things went wrong on the way, and all three have the same shape: **an
override that ignores the state it overrides will eventually contradict it in
full view.**

1. **He rode straight back up.** A flight's foot IS its boarding point, so
   landing there put him on the step he had just come down. He now runs for the
   far end and boards nothing while he does.
2. **He stood still instead of running.** The run override sat BELOW the two
   `IF hmv` movement blocks, where the only thing it could still reach was the
   animation counter: he faced the right way, played the run cycle and
   travelled zero pixels.
3. **He ran into the Kop without noticing, and turned round for no reason.**
   The override beat the flee as well as the climb, so he held one heading
   whatever Kelly did; and it was a count of passes, which expired mid-floor.
   It is a flag now, cleared by exactly two things the player can see: **the Kop
   arriving on his floor** (the flee outranks it) and **reaching the end wall**.

### 6c. Two arithmetic faults worth remembering

**The catch wrapped around the screen.** `coll_harry` centred both actors
before measuring:

```
kcx = klx + 8
hcx = hx + 8          ' hx reaches 253 -> 261 -> wraps to 5
```

Harry walks to x 253 before crossing a seam, so a Kop at the far LEFT measured
five pixels to a crook walking off the far RIGHT and arrested him across the
whole store. The `+ 8` cancels in a difference, so removing it fixes the wrap
and is less work. The obstacle test has the same shape but cannot reach it:
`obx` tops out at 240 and `klx` at `XWALL`.

**A ball at the top of its arc could be jumped.** The hitbox is the middle four
pixels of the eight-pixel art, so an apex of 8 put it at 10..14 against a jump
apex of exactly 14 -- and `kfh < oht` is false at 14 < 14. He cleared it by one
pixel of arithmetic, on the one arc a new player meets first. Nine makes it
11..15. `checkball.py` now reports the split cleanly: 25 of 32 frames jumpable
and 7 duckable on the low arc, which partition exactly, so the top of every arc
is a duck and no frame is free.

### 6d. Hazards stay on their own floor

The placement table used to pick a floor's hazard as `palette[lv][(scr+lv) % 3]`
-- it rotated by SCREEN, for variety across the store. All four bands are
visible at once here, so crossing a seam swapped the kinds in full view: the
balls being tracked on one floor became carts, and balls appeared a storey up.
It reads as objects teleporting between levels.

Each floor now owns one hazard for the whole store -- **balls on 1, radios on 2,
biplanes on 3, carts on the roof** -- and the variety comes from the Krook ramp
(0p), which brings them in one per round. Fixing this also uncovered a leftover
rule, `if lv == 3 and k not in (PLANE, NONE): k = NONE`, which had been silently
deleting every roof obstacle: the roof carts restored two revisions earlier had
never actually appeared.

### 0m. What the video actually measures

Everything below is measured off the longplay, not inferred. The calibration
first, because every number depends on it:

* the playfield is **456 video px** wide and that is our **256 px**;
* a band is **51 video px** tall and that is our **40**;
* the capture is **30 fps** against a 60 Hz console, so **one video frame is two
  console frames**.

#### The timer is not seconds -- it is a unit of about two seconds

It counts **50 down to 0**, and a unit lasts **59.75 video frames = 1.99 s**.
Measured twice, independently:

1. **Directly.** 50 at frame 360, 49 at 420, 48 at 480, 47 at 540, 46 at 599 --
   239 frames for four ticks.
2. **End to end.** Finding every frame whose timer reads 50 gives five round
   starts in the sample; the gaps are 83.8, 52.8, **98.5**, 65.8 and 82.7 s.
   A full 50-unit round at 1.99 s is **99.5 s**, and the longest observed round
   is 98.5 -- a round that nearly timed out. The short ones are Harry caught
   early.

So the manual's "50 seconds" is 50 *timer units*, and a round is about **100
seconds** of play. The digits are a count, not a clock.

#### The speeds already match -- because they are paced per PASS, not per frame

The reference Kelly covers **102 px/s**. Ours covers **~100 px/s**, and the
arithmetic that gets there is the thing to understand, because reading the
constant alone gives the wrong answer twice over:

> `WALKSP = 4` is **4 px per LOOP PASS**, and the loop runs at about **25
> passes a second**, not 60. So Kelly's real speed is 4 x 25 = 100 px/s.

An earlier draft of this section read `WALKSP = 4` as px per *frame*, concluded
we ran 2.35x too fast, and recommended no change on the grounds that a 2x-fast
clock cancelled it. **Both halves of that were wrong.** The speeds were never
fast; the clock alone was.

| object | reference px/frame | as a fraction of reference Kelly | ours, as a fraction of our Kelly |
|---|---|---|---|
| shopping cart, roof | 0.80 | 0.47 | 0.25 - 0.75 |
| shopping cart, floor 1 | 1.21 | 0.71 | (same range) |
| beach ball, horizontal | 0.82 | 0.48 | (same range) |

A cart runs at roughly half the player's speed in both games, so **the object
speeds need no change**. The **clock did**, and it was not cosmetic.

#### The clock was the one thing out of step, and it made the round unfinishable

Everything that moves is advanced once per loop pass. The timer is the one
thing paced by the frame **delta** -- i.e. in real seconds. At 60 frames a unit
a round was 50 real seconds, and Kelly's route to the roof takes **72**. The
clock ran out before either man could get near the roof, so every round ended
on a timeout and Harry's escape -- one of the game's two loss conditions --
could never happen at all.

`checkchase.py` reported this as healthy on every run, because it converted
both routes with `FPS = 60`. Halving a number on both sides of a comparison
leaves the comparison intact, which is exactly why the bug was invisible: the
margin between Kelly and Harry was right, and only their relationship to the
*clock* was wrong. It now models **25 passes/s** and reads `TICKFR` for the
real round length:

| | before (FPS=60) | now (25 passes/s, 120-frame unit) |
|---|---|---|
| Kelly to the roof | 30.1 s | **72.2 s** |
| Harry escapes at | 40.2 s | **96.4 s** |
| round length | 50 s | **100 s** |

And that is the reference: five measured rounds ran 83.8 / 52.8 / **98.5** /
65.8 / 82.7 s against a 100 s cap, with the longest one nearly timing out --
which is precisely a Harry who escapes at 96.4 s.

**The lesson for any future checker here:** a ratio test cannot catch a units
error. Both actors were converted with the same wrong constant, so every
*relative* assertion still passed; it took comparing them against something
measured in different units -- the clock -- for the mistake to show.

#### The advancement arithmetic, in the units that matter

At 102 px/s a reference screen takes 2.51 s, so a floor of eight screens is
about 20 s and a 100 s round buys **five floor-traverses**. Ours, at ~100 px/s
and a 100 s round: 2.56 s a screen, 20.5 s a floor -- **4.9 traverses**. The
same game. That is the number to hold constant if the speeds are ever retuned:
not px/frame, and not seconds, but *floor-traverses per round*.

Note what this makes fragile. Movement is per pass and the clock is per second,
so **the loop rate is a difficulty dial nobody declared**: at 20 passes/s (the
west screen) Kelly covers 80 px/s and the same round buys 3.9 traverses. Frame-
pacing the actors would remove that, at the cost of re-tuning every speed to
px/frame and re-deriving the chase; it is not done here, and this is where to
start if it ever is.

#### Objects on the roof

A shopping cart was tracked crossing the **roof** band at 0.80 px/frame, so the
roof is not a clear run -- it carries obstacles like any other floor, and 0k2's
first version (which emptied it) was wrong. Restored as **carts only**: a cart
costs time, and the roof is where the round is decided, so the one hazard that
costs a whole Kop stays off it.

#### What this pass did NOT establish

No ducking frame exists in the sample (0k), and the reference's own biplane is
a blob rather than an aeroplane (0n). Screens-per-floor and escalator placement
were not re-measured here; those remain as recorded in section 4.

### 0n. The aeroplane, and the policeman's helmet

**The plane is drawn from above.** Zoomed off the video the original is a small
dark-green body with a light-green dashed arc over it -- at 2600 resolution
that is all there was room for, and copied literally it reads as a bug. Three
attempts at a side-on biplane failed for a reason worth recording: a side view
needs two wings, two struts, a fuselage and a fin, and at sixteen pixels those
collapse into **three parallel bars that read as a grid**. From above an
aeroplane is one shape -- a long fuselage with swept wings and a nose that runs
out ahead of them -- and nothing else on screen resembles it.

**And it is two colours after all.** A TMS9918 sprite has one colour, so a
dark-green body with a light-green propeller takes two sprites, and all sixteen
slots were spoken for (0-3 Kelly, 4-7 Harry, 8-15 obstacles). The way through
is **priority**: the VDP drops the *highest-numbered* sprites on an overfull
scan line, so the propellers live in slots **16-23**. When Kelly, a plane and a
high beach ball share a line -- the only case that exceeds four -- what
disappears is a propeller, which is decoration, and never the plane the player
has to duck. The body no longer carries the prop, so it is one pattern per
facing instead of two, and the two prop phases cost only two patterns net.

**The Kop wears a custodian helmet.** The reference is inconsistent with
itself: the figure on the playfield wears a flat-brimmed bowler, while the HUD's
spare-Kop icons are unmistakable **bobby helmets** -- a tall dome with a boss on
the crown and a modest brim. Both now follow the HUD, because that is the one a
player reads as a policeman. The old HUD icon was a whole little figure and at
eight pixels it read as an animal; a silhouette that small has room for exactly
one idea, and the helmet is the one that says Kop.

### 0k2. Roof obstacles, and beams that reach the floor above

Two things the reviewer caught in the same pass, both of which are about what
the screen *says* rather than about what it computes.

**Carts on the roof, but not biplanes.** The roof band used to draw from a
palette of two biplanes, and emptying it entirely was an over-correction -- a
cart was later tracked crossing the roof in the reference (0m). It is still the
band where the chase is decided rather than survived, so the palette is carts
only: a cart costs nine seconds, a biplane costs a Kop, and a kill arriving in
that window turns the finish into a coin toss the player cannot see coming.

**Support beams have to reach the floor they hold up, and that floor is not in
their own band.** A beam fills its band's four air rows, so its top pixel sits
directly under the *slab row of the band above*; a slab row is five pixels of
bar over three of green (see `SLAB`), so every beam stopped three pixels short
of the bar. It did not read as a rounding error, it read as a beam that misses
the floor.

It cannot be drawn into either template. The beam belongs to the band below and
the row belongs to the band above, and the two templates are chosen
independently per screen, so **no template knows both**. So the band blits go
down first and `beam_tops` stamps the tops afterwards from a per-template column
table (`stor_pil`) -- the same shape as the escalator's head cap, and for the
same reason. The stamped character is `SLABP`: the floor bar with those three
green rows in the beam's grey instead.

Bands 0 and 1 only. Band 2's top row is the roof deck, which is grey over grey
with no green to bridge, and the roof has no band above it at all -- which is
exactly the two floors the reviewer named.

`assets/preview.py` models the stamp. A previewer that painted straight out of
the templates would still show the gap, which is the §0i lesson again: a check
narrower than the thing it checks reports success.

### 0l. The jump is ballistic

The stick used to steer him in mid-air, because the running block ran during
`ST_JUMP` like any other state. That is not a jump, it is flight -- and it also
let him flip which way he was *facing* halfway through an arc. The horizontal
direction is now latched at take-off (`kjdx`) and the stick ignored until he
lands.

---

### 0i. Why the escalator screens ran slow

Reported from play: on the two screens with a staircase the running looked
slower and the footsteps dragged, with the timer possibly unaffected.

All three parts of that are explained by one line. `esc_tick` is **the only
per-pass work unique to screens 0 and 7**, and it was rewriting all fifteen
animated cells — 120 bytes of pattern table — every pass. That pushes a pass
past one frame, so `fdv` rises above 1 there and nowhere else.

- The **timer is not slower**: `tick_timer` counts down by `fdv`.
- **Movement is not slower** either, for the same reason.
- But `kanim`, `sfw` (the footstep period), `hanim` and `sct` all counted
  **passes**, so the legs, the footsteps, Harry's legs and the radar all
  stretched out exactly where the loop was heaviest. They count `fdv` now.

And the cause itself is halved: only one flight direction is ever on screen —
screen 0 carries a west one, screen 7 an east one — so genart groups the moving
cells **west then east** and `esc_tick` writes only this screen's half. 72 bytes
on the west screen, 48 on the east, down from 120.

`escp` itself stays per-pass and must: a four-phase cycle stepped by more than
one aliases, and the rider is locked to it (§0f).

**AND THE WEST SCREEN COST HALF AS MUCH AGAIN, because it carries TWO
flights.** Not because two staircases are twice the work -- they share their
patterns -- but because the two cross *different surfaces*: floor 1's flight
crosses into a shop floor and floor 3's into the roof, so it needed both the
BAR composites and the DECK ones. Nine animated characters against the east
screen's six; 216 bytes a pass against 144.

The two composite sets are **pixel-identical**. They are the same flight over a
different background, and they differ only in colour -- and **they are never
wanted in the same screen third**: a roof crossing is screen row 5 and a shop
one is row 10 or 15. The TMS9918 colours each third from its own table, so one
character can be the deck up top and the floor bar lower down. `DEFINE COLOR`
paints them as the bar in all three thirds and `esc_deck_col` repaints third 0
as the deck, once, at setup. Six characters either side now, and the whole
store table lost six entries with them.

That invariant is the price of the trick, so `checkesc.py` gates it: it reads
the band rows and the escalator sides out of the source, works out which third
each crossing lands in, and fails if a roof one and a shop one ever share.

**MEASURED, and the headline is not the escalator.** A debug pass-counter on the
HUD says the loop runs at **24-26 passes a second everywhere**, dropping to
**20** on the west screen with two flights. So the game is at ~25 Hz, not 60,
and `fdv` is about 2.4 all the time; the escalator costs a further ~20% on top
of that. Everything paced by `fdv` -- movement, the timer, the animation and
footsteps since this section -- keeps correct wall-clock time regardless. What
does not is anything locked to the pass: the steps and the rider, which
therefore run at 25/60 of their intended speed. **That is the residual
sluggishness, and closing it means raising the loop rate itself**, which is a
profiling job on the whole main loop rather than anything escalator-specific.
`define_char` compounds it: in bitmap mode it calls LDIRVM3, the *triple* copy,
so nine characters is 216 bytes of VRAM per pass and not 72.

---

### 0c. Second video pass — the escalator, and why the roof hid the player

**The escalator was the worst-looking thing in the store, and the video says why.**
It was drawn as a *solid diagonal wedge* with a stippled body — a filled
triangle, which reads as a ramp or a wall. The reference draws an **open
flight**: a run of chunky **white step treads** descending between thin rails,
with a flat landing and a long **black horizontal rail** at the top end. It is
now four flight characters (a pair per row — the flight drops 8 px per 16 px
across, so each row is an upper-half and a lower-half character) plus one rail
character. The rails themselves are dropped: they are dark green in the
reference, and with two colours per scan line the row's second colour is better
spent on the treads, which are what make it read as an escalator at all.

**The ride went straight up, because only one axis was ever interpolated.**
Boarding snapped `klx` to the destination and then the ride interpolated `y`
alone, so Kelly teleported sideways and rose *vertically* — visibly beside the
staircase rather than on it. He now boards at the foot and stays there, and
`move_kelly` walks him along the flight: the flight's ends are 48 px apart and
the floors 40 px, over a 40-frame ride, so **y moves 1 px a frame for all 40 and
x moves 2 px a frame for the first 24** (= 48 px) and then holds. Those last 16
frames are the **flat landing** at the head, which the reference draws as a real
part of the escalator. Down is the same ride mirrored: board at the head, travel
to the foot.

**The flight is a black band with white treads.** Dark green on medium green was
tried first, to match the reference's dark outline, and the TMS9918's two greens
are close enough that the band was effectively invisible — the flight read as a
dotted white line floating on the floor. Black gives the ribbon the contrast the
reference gets from its outline, and it matches the landing rail, which is
already black.

**The band came back off again.** A dense frame burst (`fps=10` over the ride)
settles what a single frame could not: the flight's interior is **store green**
with white step wedges in it, inside a thin dark outline — it is an *open*
staircase, not a filled ribbon. The black band was heavier than anything
actually on screen. It is now two-pixel white treads and risers on green,
which reads as steps at 1× where the earlier 4×2 dashes read as a dotted line.
The same burst also shows the **steps do not scroll** — no step animation is
needed, which is worth knowing before building one.

**DARK GREEN IS NOT A COLOUR ON THIS MACHINE, NOT NEXT TO MEDIUM GREEN.**
TMS9918 colour 12 is (33,176,59) and colour 2 is (33,200,66). Twice now the
reference's "darker green than the store" was copied literally and twice the
thing simply vanished: first the escalator band, then the elevator shaft. Where
the reference uses dark green *against* medium green, use **black** — it keeps
the relationship (this is the dark thing in a green wall) with contrast the
hardware can deliver. The shaft is black, the car cyan, and the shaft now runs
the **full** band height as the reference draws it rather than starting a row
down.

**Moving the art moved the boarding zones.** The old filled triangle covered the
whole lower corner of the band, so the boarding zone was the whole corner. The
stepped flight occupies two characters per row, so the foot is now columns 7–8
(west) / 23–24 (east) and the zones are those columns. Leaving the zone where it
was would have put the player on a staircase that is not under them — silent,
and it would present as the floor teleporting you at a random spot.

**The roof was sky all the way down, and that made Kelly invisible.** The sky was
`DBLUE`, which is *exactly* `C_KELLY` — his tunic colour. On the roof, the one
place he is silhouetted against sky rather than against the green store, he was
drawn in the background colour. Two fixes, both needed: the sky is now **cyan**
(the reference's own), and the roof band is now layered the way the reference
layers it — **sky, then skyline, then a grey backdrop, then the deck** — so the
figure stands against grey at the height he actually occupies rather than
against open sky. Every roof screen carries a full row of skyline: a horizon is
not an ornament at one end.

**Where the sources disagree**

1. **Bonus multiplier bands.** The AtariAge manual gives Krooks **1–8 / 9–16 / 17+** for
   ×100 / ×200 / ×300. A secondary summary gives **1–9 / 10–15 / 16+**. → We take the
   manual: **1–8 / 9–16 / 17+**.
2. **Three floors or four.** Wikipedia says "four floors"; PixelatedArcade says "three floors
   and a rooftop" — the same building counted two ways. → **Three shopping floors and a
   roof.** Four bands on screen, but the roof is not a shopping floor: it has no aisles, no
   obstacles on the ground and no escalator onward. It is the escape.
3. **Biplane penalty.** One summary of the AtariAge manual attributes the 9-second penalty to
   biplanes as well. Three independent sources say a biplane **kills**. → Biplanes kill.
   This matters: it is the only thing in the store that does.
4. **Escalator direction.** No source states whether escalators run down as well as up. →
   **UP ONLY.** This was briefly built both ways and then taken out again at the
   reviewer's direction. Removing it also removed a re-boarding lock that existed solely
   because stepping off at the head left you standing in the zone that rode the same
   flight back down; with no down ride there is no such zone, because a floor's escalator
   is at the opposite end from the one below it. The elevator is the only way down.

**Deliberate deviation, at the reviewer's direction:** the arcade view *scrolls*
horizontally. Ours **flips** — the store is eight discrete screens and crossing an edge blits
the next one. §2a records what that costs and what it buys.

---

## 1. Performance budget (decided before line 1 — `CLAUDE.md` §5A)

| term | value |
|---|---|
| Loop | **Real-time, one `WAIT` per frame**, 60 Hz on both machines. No pacing constant. |
| Simultaneously moving actors | **10 max** — Kelly, Harry, and ≤2 obstacles on each of 4 bands. |
| Per-actor work | **O(1)**. Constant velocity plus one add. No search, no pathfinding. |
| Harry's AI | **Two comparisons.** He runs at this floor's up-point and climbs. He never reconsiders. |
| Per-frame VDP **reads** | **ZERO.** There is no tile map to consult — see below. |
| Per-frame VDP **writes** | Sprite attributes only. HUD digits when a digit changes; scanner dots when a dot moves. |
| The big blit | **4 × 160 chars, only on a screen crossing** — a discrete event, never per frame. |

**Why there are no per-frame VDP reads.** A platform game normally asks the screen "what is
under my feet". This one never needs to: an actor's floor is its `lv` (0–3) and the surface
height is `FLOORY(lv)`, a four-entry table. Obstacles are a RAM array compared arithmetically
against Kelly. The store's *appearance* lives in VRAM; the store's *physics* is four numbers.
That is the same trick that keeps Joust cheap, and it is why the Ms. Pac-Man trap (actors ×
per-actor search) is absent by construction rather than by tuning.

**Why the flip is cheap where RallyX's pan was not.** RallyX repaints 576 chars *every time
the camera moves one cell*, and had to have all its movement rewritten to advance to cell
boundaries to survive it. Here the repaint happens once per screen crossing — roughly once
every two seconds of running — so the per-frame budget never sees it at all. The cost of the
flip is paid entirely in fidelity (§2a), not in frame time.

---

## 2. The store

### Geometry

```
world = 8 screens × 256 px = 2048 px wide, 4 levels tall
```

Eight screens of exactly 32 columns is the load-bearing number. **A screen is 256 pixels, so
an actor's x within its screen is exactly one unsigned byte** — no 16-bit world coordinate, no
`#var` unsigned-compare split (`CLAUDE.md` §3A), no scaling anywhere. Position is
`(lv 0..3, scr 0..7, x 0..255)`. Crossing an edge is `x` wrapping and `scr` stepping.

Screens left to right, matching the reviewer's layout (given right-to-left) and
PixelatedArcade's "escalators at alternating ends, elevator in the centre":

```
 scr    0        1        2        3        4        5        6        7
     +--------+--------+--------+--------+--------+--------+--------+--------+
lv3  |  roof  :  roof  :  roof  :  roof  :  roof  :  roof  :  roof  |  ROOF  |  <- escape edge
lv2  |  ESC   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  esc   |  floor 3
lv1  |  esc   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  ESC   |  floor 2
lv0  |  ESC   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  esc   |  floor 1
     +--------+--------+--------+--------+--------+--------+--------+--------+
       west end                 elevator                            east end
                                                          Kelly starts here ^
```

**Three shopping floors and a roof.** Escalators stand at both ends, but **only the
capitalised one on each floor goes up**: floor 1 climbs at the **west** end (screen 0),
floor 2 at the **east** (screen 7), floor 3 at the **west** again.

**The store has ends, and they are walled.** The extreme column of screen 0 and of screen 7
carries a wall character on every floor. Without it the player runs into the edge of the
screen and the building appears simply to stop — which reads first as though they ought to be
able to keep going, and then as though the game has stuck them there. (It literally did: the
clamp used to park Kelly's 16 px sprite at x = 255, entirely off the right edge, where nothing
moved him back.)

Kelly starts at **screen 7, floor 1 — the east entrance**, which is the far end from floor 1's
escalator. So the climb from the street to the roof is **three full traverses of the store**,
one per floor, and the alternation is what makes each of them full-length:

```
floor 1   east entrance  ->  west escalator      traverse 1
floor 2   west landing   ->  east escalator      traverse 2
floor 3   east landing   ->  west escalator      traverse 3
roof      west landing   ->  east edge           Harry's escape, and the last chase
```

Getting the alternation backwards would land Kelly on floor 1's escalator at spawn and cost
only *two* traverses — the store would be a third shorter than it looks. **The roof's escape
edge is at the east**, opposite the escalator that lands on it, so the rhythm carries through
to the last run.

That is what "alternating ends" buys, and it is the entire reason the elevator is worth the
walk to the middle: **the elevator is the only way down, and the only shortcut** — one ride
from the centre replaces a traverse and a half.

Harry starts at **screen 3, floor 2, at the elevator door.**

### Rows

24 rows, and every one is spoken for:

```
row  0        HUD:  SCORE 001250            TIME 43        Kops as icons, right
rows 1– 5     lv3   ROOF          4 rows of air + 1 surface row
rows 6–10     lv2   FLOOR 3
rows 11–15    lv1   FLOOR 2
rows 16–20    lv0   FLOOR 1
rows 21–23    SCANNER   16 chars × 3 rows, centred
```

A band is **5 rows = 40 px**: four rows of air over one surface row. Standing Kelly is 16 px,
so he has **16 px of headroom** — enough for a 14 px hop and nothing more, which is exactly
the margin the `platformer-jump-headroom-ceiling` note says to design for rather than
discover. Two consequences follow from it, and the art must respect both:

- **Ground obstacles are 8 px tall**, drawn in the bottom half of their 16×16 sprite box.
  A 14 px jump clears a cart with room to spare.
- **Biplanes fly with their bottom edge 16 px above the surface** (hitbox 16..22). Standing
  Kelly (24 px) is struck; ducking Kelly (11 px) passes five pixels under. The duck is not a
  dodge, it is a height change. A biplane is **not** jumpable — the apex is 14, under the
  plane, so a jump puts Kelly's body straight through it. See §0k for why 16 is the ceiling.
- **Beach balls move through both windows**, which is what makes §5a the tightest arithmetic
  in the game: the jump arc and the duck gap have to meet without leaving a height at which
  the ball cannot be avoided at all, and the arc is capped below standing height so no ball is
  ever free.

### 2a. The flip, and what it costs

Crossing a screen edge sets `scr`, then blits. The reviewer's call, and it is defensible: the
per-frame budget never pays for the store at all. What it costs is that **Harry can be one
pixel off-screen and completely invisible**, where the arcade's scroll would have shown him
coming.

That is not a hole — it is why the **scanner exists**, and the manual already treats the
scanner as a first-class instrument rather than decoration. With a flip, the scanner is
promoted from "nice overview" to **the primary instrument for locating Harry**, and §6 sizes
it accordingly.

**Hysteresis is mandatory.** Crossing right at `x = 255` must set `x = 8` on the new screen,
not `x = 0` — otherwise a step back left re-crosses immediately and the store re-blits every
frame at the seam. Crossing left at `x = 0` sets `x = 247`. The 8 px dead band is four times
one frame of running (2 px), so a seam can never oscillate.

### 2b. How a screen is drawn — about 1 KB for the whole store

Storing 8 screens × 20 rows of literal char codes would be 5,120 bytes of the scarce budget.
Instead the store is **band templates**: one 5-row × 32-col strip = 160 bytes, plus a
**32-byte index** saying which template each `(scr, lv)` uses.

```
templates:  T_AISLE_A  T_AISLE_B  T_ESCALATOR  T_ELEVATOR
            T_ROOF  T_ROOF_ESC (west landing)  T_ROOF_EDGE (east escape)
            7 × 160 = 1,120 bytes  +  32-byte index  =  ~1.1 KB for the entire store
```

Drawing a screen is **four `SCREEN` blits** (one per band, template → its 5 rows), then a
handful of `VPOKE`s for what is per-screen rather than per-template: the collectible bags and
the elevator car's position in its shaft.

Two rules this must obey, both from `CLAUDE.md` §3A and both silent when broken:

- Every template block is **even-length by construction** (160 is even), so no word table
  after it lands on an odd address and reads back shifted by a byte for ever.
- A `VPOKE` target is a **raw VRAM address** — name table at **6144** — and 6144 is added as
  **its own statement**, never folded into a constant expression.

---

## 3. Kelly

**Kelly and Harry are 24 px — two sprites tall**, a 16 px top sprite with the top half of a
second one below it. At 16 px they read as tokens rather than as a policeman chasing a crook.

| state | height | how |
|---|---|---|
| Running | 24 px | stick left/right, **4 px/frame** (240 px/s) — see §4a |
| Standing | 24 px | no input |
| Jumping | 24 px | button; 14 px apex, 30 frames, **9 of them at the apex** |
| Running jump | 24 px | button + direction; same arc, keeps horizontal speed |
| Ducking | 8 px | stick back; cannot move horizontally |
| Riding | 24 px | on an escalator or in the elevator car — **input ignored, invincible** |

**The height was checked against the arithmetic before the art was drawn.** A band gives 32 px
of air over the floor line, *plus* the 7 px of the ceiling row that sits below that row's 1 px
slab line — 39 px of real headroom. A 24 px figure with a 14 px jump needs 38. It fits with one
pixel spare, and every window in §5a is unchanged: jumpable at a ball height ≤ 8, duckable at
≥ 6, three pixels of overlap, nothing free below 22.

**The apex could not be traded for the height.** Dropping the jump to 10 px to "make room"
opens a **dead band at 5**, where the ball is neither jumpable nor duckable. So 14 is
load-bearing, and the only reason that was caught before it shipped is that the numbers were
swept rather than eyeballed (`assets/checkball.py`).

**Two sprites do not double the scanline cost.** The halves never share a scanline with each
other, so a band still carries Kelly 1 + Harry 1 + two obstacles = four, the VDP's limit.
Kelly holds slots **0 and 1**, Harry 2 and 3, obstacles 4–11 — lowest slots to the things that
must never be dropped.

Vertical motion is **8.8 fixed point with velocity biased +32768** — the Joust convention, so
no comparison ever crosses zero and every `#var` compare stays safely unsigned
(`cvbasic-unsigned-16bit-compares`).

Landing is a single test against `FLOORY(lv)`. No ground query, no tile lookup.

**The arc is 30 frames with a nine-frame plateau at the apex.** The first version was 24
frames that touched 14 for only four of them, which made every jump a timing test rather than
a decision — leave the ground on the wrong frame and you clipped the thing you were jumping.
Widening the plateau rather than raising the apex keeps §5a's arithmetic intact (that depends
on the apex being exactly 14) while making the window forgiving: the player still has to
*choose* to jump, but no longer has to be frame-perfect about it.

**Kelly is sprite 0.** Flicker stays **off** — CVBasic's flicker is all-or-nothing and would
rotate Kelly along with everything else (`cvbasic-flicker-is-all-or-nothing`) — and the VDP
drops the highest-numbered sprites on an over-full scanline, so being sprite 0 means Kelly is
the one thing that can never disappear.

---

### 3b. Three sprites per actor, one colour per row

Kelly and Harry are each **three sprites**, one per colour band: hat+tunic,
face, trousers. A TMS9918 sprite carries exactly one colour, so that is the
only way to get three colours into a figure.

**The VDP counts sprite BOXES per scanline, not pixels.** A 16×16 sprite
occupies all sixteen of its scanlines whether or not those rows contain
anything, so "the overlaps are empty" buys back nothing. Three 16 px boxes
stacked inside a 24 px figure therefore overlap three deep somewhere, and Kelly
plus Harry would be **six boxes on the lines where they meet** — the endgame
chase — with two silently dropped.

**But a box only has to cover the rows its band uses, and the `y` is free.**
The first version parked every band at the figure's top, so all three boxes
spanned rows 0–15 whether they had anything there or not — three boxes per
actor, six for a meeting, and one band had to be sacrificed. Pushing a band's
pattern to one end of its box (`shift()` in `genart.py`) and drawing the sprite
at the matching offset makes the box cover only its own rows:

| actor | band | drawn at | box covers |
|---|---|---|---|
| Kelly | hat (black) | `y−13` | −13…2 |
| Kelly | face | `y−10` | −10…5 |
| Kelly | tunic (blue) | `y+6` | 6…21 |
| Kelly | trousers | `y+16` | 16…31 |
| Harry | cap + body (white) | `y` | 0…15 |
| Harry | stripes (black) | `y` | 0…15 |
| Harry | face | **`y+3`** | 3…18 |
| Harry | legs | `y+16` | 16…31 |

Worst line of a meeting: **four boxes**, the hardware limit exactly, nothing
dropped. That is also why obstacles are suppressed on Harry's floor (§5): it is
load-bearing, not a kindness.

**Kelly's hat had to leave the tunic's sprite so Harry could have a striped
cap.** Harry striped from cap to hem means *both* his stripe colours run the
whole upper half, so both boxes span rows 0–15 and neither can be tucked out of
the way. That is only affordable if Kelly contributes just one box over the cap
rows — which he does once the hat is its own sprite (box −13…2) and the tunic
starts at row 6. Harry's face is then pushed *down* (`y+3`) rather than up, so
it clears the cap rows where the four boxes already are.

**The consequence is where the seams fall.** The top box holds only two
colours, and the face sits between the hat and the torso — so **hat and torso
must share a colour**:

| | rows 0–2 | rows 3–5 | rows 6–15 | rows 16–23 |
|---|---|---|---|---|
| Kelly | **black** hat | skin | blue tunic | blue trousers |
| Harry | striped cap | skin | striped body | white legs |

**The black hat needed the elevator shaft fixed first.** The hat went blue for a
while because it shared a sprite with the tunic and the shaft was black, so the
Kop vanished in the one place the game most wants you to go. Both halves are
fixed now: the hat has its own sprite, and the shaft is **grey** — the
reference's dark green is indistinguishable from the store's medium green on
this VDP (§0c), so it needed replacing regardless.

`checkbands.py` fails the build if any band overlaps another on a pixel row, or
if two actors level with each other would ever exceed four boxes on a line.

**No eyes.** An eye drawn in black would put two colours on one row; an eye left
as a hole shows the green store through the face. The face is solid.

**`assets/checkbands.py` gates both builds.** It fails if any figure row carries
pixels from two of an actor's sprites, or if any scanline is covered by more
than two boxes — both of which are invisible in the source and present only as
"the sprite looks wrong".

---

## 4. Harry

Harry's whole brain is: **run for the roof, continuously.** Get to this floor's up-point, take
it, repeat; on the roof, run for the east edge. He is not patrolling — he is escaping, and
every frame he is not climbing is a frame he is losing.

**Exactly one thing changes his mind: Kelly arriving on his floor.** Then he stops heading for
the escalator and simply runs *away*. A thief who keeps walking calmly toward a fixed point
while a policeman closes on him is not a thief, he is a train.

Still two comparisons. The flee direction is "opposite whichever side Kelly is on", compared
screen-first then pixel-within-screen — there is no world coordinate to subtract (§2). Three
consequences fall out, none of them special-cased:

- Fleeing may carry him **toward** his escalator, in which case he climbs and clears the
  floor. Fine — he earned it.
- It may carry him **away** from it, into the end wall, where he is trapped. Also fine: that
  is the catch.
- He never stops trying, so it does not read as broken AI the way a fleeing *enemy* would
  (`difficulty-dial-must-not-invert-goal`). Running is what this character is **for** — the
  rule is about enemies that abandon their goal, and Harry's goal is to get away.

- He runs at a flat **1.75 px/frame** (105 px/s), at every Krook. Not 2, not a per-Krook
  ramp — §4a is the whole reason, and it is arithmetic rather than taste.
- He rides **escalators** exactly as Kelly does, standing on a step, 36 frames a flight
  less the animation phase (§0f). He does **not** use the elevator: the car is Kelly's
  shortcut and Kelly's alone, and it is the one asymmetry that pays for Kelly's much
  longer route (§4a).
- **He never goes down.** The chase is therefore a race up a zig-zag, and Kelly's only
  advantages are raw speed and the elevator.
- **He starts on the player's screen** (screen 7, floor 2), not at the elevator door the
  research names. The reason given here used to be that "the arcade shows you the crook the
  moment the round begins" — **and the video says it does not**: at a round start the 2600
  shows Kelly alone on the ground floor, with the crook nowhere on screen and findable only
  on the scanner. So the honest reason is the flipped view (§2a): screen 3 would put him
  four screens away and invisible for the opening seconds, and this port has no scroll to
  soften that. It is a deliberate divergence, not a reading of the original.
- When fleeing, the side comparison carries a **16 px dead band**. Comparing raw positions
  makes him flip direction every time Kelly crosses his centre by a pixel, which on screen is
  not fleeing, it is a vibration — and it reads as the crook being broken rather than cornered.
- Kelly catches him by touching him: `|dx| < 12` on the same `lv` and `scr`.
- Harry reaching the east edge of the roof is an **escape**, and costs a Kop.

Difficulty is the **obstacle tables**, never Harry's speed and never a change of goal — an
enemy that stops trying reads as broken AI (`difficulty-dial-must-not-invert-goal`). Harry
always runs for the roof at the same speed, and it is the store that gets harder around him.
That is also the only dial the manual names: *"as your levels increase, so does the speed of
the obstacles."*

---

## 4a. The chase arithmetic — why 4 against 1.75

**A chase resolves on `path ÷ speed`, not on speed.** This is the one number in the game that
neither constant shows you, and getting it wrong does not look like a tuning problem — it
looks like the crook cheating.

Kelly ran 3 px/frame against Harry's 2. A 1.5× advantage sounds comfortable. It was not:

```
Kelly   east entrance -> west esc -> east esc -> west esc -> roof edge
        1984 + 2008 + 1992 + 2008  =  7992 px  + 3 rides   =  46.4 s at 3 px/frame
Harry   spawn -> east esc -> west esc -> roof edge
         104 + 1992 + 2008          =  4104 px  + 2 rides   =  35.5 s at 2 px/frame
```

**Kelly lost the race to the roof by eleven seconds, every round, at every Krook.** Harry
spawns *beside* floor 2's escalator (§4, and it is the right call — you have to be able to see
what you are chasing), so he skips a traverse and runs 4,104 px where Kelly runs 7,992. The
route is **1.95× as long**, so a 1.5× speed advantage is not an advantage at all. Pursuit on
foot could never close, at any distance, given any amount of time. The elevator was not a
shortcut, it was the only way to win — and a player who mistimed the car had already lost the
round without being told.

The fix is Kelly at **4** and Harry at **1.75**:

| | route | rides | to the roof edge |
|---|---|---|---|
| Kelly, 4 px/frame, **by lift** | 1,121 + 863 + 2,008 px | 1 ride + a worst-case 12.8 s wait | **30.1 s** |
| Kelly, 4 px/frame, on foot | 7,992 px | 3 rides | 35.1 s |
| Harry, 1.75 px/frame | 4,104 px | 2 rides | **40.2 s** |

**10.1 seconds of slack.** One beach ball costs 9 s, so Kelly can absorb a mistake and still
make the catch. Harry escapes at 40.2 s against a 50-second clock, so *"escaped off the roof"*
stays the loss that actually happens and the timer stays the backstop behind it.

**THE LIFT IS PART OF THAT AND LEAVING IT OUT DISTORTED THE DESIGN.** This section, and the
check, used to charge Kelly the full on-foot route and nothing else. That is not a
conservative assumption — it is a route no player takes: the shaft is on screen 3, *on his
way* from his spawn to floor 1's escalator, and it carries him two floors for the price of a
wait. Modelling only the foot route made the chase look 5 s tighter than it is, and that
phantom tightness was then used, right here, to argue the crook's speed down to 1.5. A check
that errs in the safe direction still shapes the design; this one shaped it wrongly.

**Harry's speed is still not the difficulty dial.** 2.0 — the ratio measured off the original
(§0f) — leaves 5.2 s, less than a single obstacle hit. There is no room in this geometry for
a per-Krook ramp on the crook, and the ramp that used to be described here (`HSPD(krook)`,
"closing on Kelly as the Krooks go by") was never implemented — which is the only reason the
game was playable at all. Difficulty ramps on the obstacles (`obsp`, and the ball arcs
of §5a).

**`assets/checkchase.py` checks all of it mechanically** and is wired into both build scripts.
It reads `WALKSP`, `hsp4`, both spawns, `stor_esc`, `ESCRISE`, the lift's timings and `TIMEL`
out of the source, walks Kelly's two routes and Harry's one, and fails if Harry is not slower
than Kelly, if Kelly's margin drops below 8 s, or if Harry can no longer escape inside the
timer. It was run against the old constants
first and correctly reports them as `-10.9 s` — a check that passes on the defect it was
written for is worse than no check (`check-scope-narrower-than-bug`), so it was tested against
the known-bad input before being trusted on the good one.

> Both actors move a whole number of pixels per **loop pass**, not per frame delta, so a
> stalled frame costs them equally and the race is unaffected. Harry's 1.5 is a **quarter-pixel
> accumulator** (`hsp4`/`hacc` in `move_harry`) spending 1, 2, 1, 2 px — `hx` is one unsigned
> byte per screen (§2) and has nowhere to keep a fraction, and `/` compiles to a real TMS9900
> `DIV`, so the fraction is carried in a variable and spent with two `IF`s.

---

## 5. Obstacles and collectibles

Obstacles belong to a **screen band**, not to the world: each `(scr, lv)` carries up to three,
and they run only while their screen is shown. That falls straight out of the flip model, and
it is what keeps the moving-actor count at 14 instead of 96.

**THE CROOK'S OWN LEVEL IS ALWAYS CLEAR.** No obstacle is drawn on, or may collide on, the
band Harry is currently on. Once you reach his floor the round becomes a foot race you can
actually see, and a biplane arriving in the middle of it takes the Kop for reasons that have
nothing to do with the chase — the one moment where a hazard is pure noise rather than a
decision. It is enforced in **two** places, the draw loop and `coll_obst`, deliberately: a
hidden sprite that can still kill you is the worst possible version of this.

| thing | motion | avoid by | cost |
|---|---|---|---|
| Shopping cart | rolls, 1–3 px/frame, wraps at the screen edge | **jump** | −9 s |
| Beach ball | rolls and **bounces** 8 / 10 / 12 px by Krook | **jump it low, duck under it high** — see §5a | −9 s |
| Cathedral radio | **stationary** | **jump** | −9 s |
| Toy biplane | flies at head height, 2 px/pass and 3 from Krook 8; **not before Krook 4**, and never on the roof | **duck** | **a Kop** |
| *(the roof carries **carts**, not biplanes — see 0m)* | | | |
| Money bag | static, on a surface | walk into it | **+50** |
| Suitcase | static, on a surface | walk into it | **+50** |

**One kind per band.** A floor carrying a cart *and* a ball asks two different questions at
once — jump this, read that one's phase — and the answer to one is the wrong answer to the
other. Two of the same thing is a floor with a rule; one of each is a floor with a trick. The
kind rotates by screen and level, so the store still varies; it just never varies within a
single stretch of floor.

**Obstacles wrap; they do not bounce.** An obstacle that turns round at the wall is a
pendulum — it has a near end and a far end, and the player learns to stand at the far one and
wait. Wrapping makes each floor a *stream*, so standing still is never the answer.

**They enter from the far side.** Kelly walks into a screen from one edge, so its obstacles
start at the *other* edge and run toward him: crossing a seam always presents oncoming
traffic rather than a set of backs to catch up with, and the direction he is travelling is
always the direction the danger comes from. The three slots are staggered a screen-third
apart so they arrive in sequence instead of as one wall.

**No hazards at all on screens 0, 3 and 7** — the two ends and the elevator. Those are where
the player has to stop and do something precise (board a flight, wait for a car), and a
rolling cart there is not difficulty, it is a toll on a manoeuvre the game has already
committed them to.

A hit costs 9 seconds. **One hit per contact, with a refractory period** — and both halves of
that are needed:

1. **The latch.** The overlap test is true on every frame the player is touching something, so
   with no latch a single clumsy cart charges nine seconds several times over. What the player
   sees is the clock jumping by 27, and the only available conclusion is that the penalty is
   broken.
2. **The countdown.** A latch that clears on the first non-overlapping frame is *still* not
   enough, and the case that breaks it is the **bouncing ball**: it lifts off the player
   between bounces, which is a genuine loss of contact, so someone standing under one is taxed
   on every bounce while being given no opening to do anything about it. Technically two
   collisions; in play, one situation.

So each obstacle carries a countdown rather than a flag. A hit sets it to `HITREF` (45
frames); it ticks down **only while the player is clear**, so contact holds it up and parking
inside something never earns a second penalty either.

There is **no blanket invulnerability window** — the refractory period is per obstacle, so a
second, different hazard still hits. The only true immunity is inside the elevator, which is
the one place the manual grants one.

**Two sprite constraints the art is designed around, not patched for later:**

- **Sprite size and magnification are GLOBAL on the TMS9918.** Every sprite in the game is
  16×16. A cart is not an 8×8 sprite; it is a cart *drawn 16 wide and 8 tall inside a 16×16
  box*. There is no mixing sizes, at all, ever.
- **Four sprites per scanline, and the fifth VANISHES** — it does not flicker, it is simply
  not drawn. This sets the obstacle cap, and the cap is **two per band, not three**.

  Three was the original number and it was wrong: it was sized against Kelly alone (1 + 3 = 4)
  and forgot that **Harry can be standing on that band too**. When he is, the fifth sprite on
  his scanline is the highest-numbered obstacle — which disappears while remaining perfectly
  solid. An invisible thing that costs nine seconds is the worst failure this game can have,
  and it happens *only when the crook is beside you*, which is exactly when you are not looking
  at the floor. Kelly (slot 0) + Harry (slot 1) + two obstacles = four, which is provably safe
  on any band in any situation.

  **The general lesson: a sprite budget has to be counted against every actor that can occupy
  the row, not against the one you were thinking about when you wrote it.**

### 5a. The beach ball — the only obstacle with two right answers

Every other hazard has one response. The ball's **changes with its height, and the two do not
overlap**: a low ball must be jumped, and **a high ball cannot be jumped at all** — you have
to go under it. That is the mechanic, and it is what makes the ball the only obstacle the
player has to *read* rather than react to.

Writing `Bb` for the ball's bottom edge above the surface:

| `Bb` | what works | why |
|---|---|---|
| 0–7 | **Jump — only.** | Standing or ducking is a hit. |
| 8–10 | either | the seam, three pixels wide |
| 11–14 | **Duck — only.** | 14 px of apex cannot clear it; standing is a hit |

**The arc is capped at `Bb` = 14 — two pixels below Kelly's standing height — so there is no
such thing as a ball you can simply run under.** Every ball costs an action, always; a high
ball demands a *different* action, not no action. Letting the apex reach 16 would make the
highest-bouncing balls — the late-Krook ones, the ones that are supposed to be the hardest —
completely free, which is the difficulty ramp running backwards.

So a ball bouncing high is not a harder jump, it is **not a jump**. The player who keeps
hammering the button on later Krooks keeps taking 9-second hits, and the answer is to stop
jumping and start ducking — which is the read the mechanic is asking for.

The three-pixel seam at 8–10 exists for exactly one reason: **without it there is a height at
which the ball can be neither jumped nor ducked**, and an unavoidable hazard is not difficulty,
it is a bug that feels like bad luck. The arithmetic that creates the seam:

```
jumpable   while  Bb + ball_box <= apex          ->  Bb <= 14 - 4  = 10
duckable   while  Bb            >= duck_height   ->  Bb >=  8
                                                     seam = 8..10, three pixels
```

Which forces three numbers to be chosen together, not tuned independently:

- **Jump apex 14 px**, against 16 px of headroom — 2 px short of the band ceiling, because an
  arc that bonks is silently truncated (`platformer-jump-headroom-ceiling`).
- **Ducked height 8 px**, one char row.
- **The ball's collision box is 4 px tall inside an 8 px sprite** — inset 2 px top and bottom,
  in the player's favour. That inset is not cosmetic generosity: `apex - duck_height = 6`, so
  a box of 6 px or more collapses the seam to nothing and a box of 8 px opens a **dead band at
  `Bb` = 7** where neither answer works. The hitbox inset *is* the seam.

**Difficulty raises the apex, never the answer.** The three arcs are **9 / 10 / 12** px:
Krook 1–3 tops out at the very top of the jump band, 4–8 goes duck-only at the peak while
staying jumpable lower down, and 9+ sits at the cap. The ball never stops being avoidable and
never becomes free; it stops being avoidable the *same way*, which is a dial that raises what
the player must read rather than taking the answer away
(`difficulty-dial-must-not-invert-goal`).

**The low arc used to be 4 px, and that was a bug wearing a number's clothes.** A ball that
barely leaves the floor looks nothing like the original and gives the early game nothing to
read — but it was the only height the *old* jump could reliably clear, because that arc
touched its apex for four frames and anything taller demanded a frame-perfect take-off. The
ball height was never the problem; the jump was. Once the jump held 14 px for nine frames the
balls could go back to bouncing properly. **Worth noticing as a pattern: a value tuned down to
compensate for a defect elsewhere looks like a considered choice forever after, and nothing
points back at the real cause.**

**A high-bouncing ball still comes down.** Its arc touches the surface every period, so the
jump band is never gone — it is just brief, and it arrives on the ball's schedule instead of
the player's. That is the whole difficulty of a late-Krook ball: the answer is time-varying,
and running at one without reading its phase means arriving during whichever window you
weren't prepared for.

**The bounce has to be legible.** A ball whose phase cannot be read in the ~15 frames before
contact is a coin flip, so the arc is slow and tall rather than fast and shallow, and its
period is fixed per Krook rather than randomised.

---

### 5b. What actually animates, and what deliberately does not

A store where only the positions change reads as a diagram. Each of these is
cheap, and each one was added because its absence was visible:

| thing | frames | driven by |
|---|---|---|
| Kelly's legs | 2 | `kanim`, ticked only while he is *moving* — a figure whose legs pump while standing still is worse than one that never animates |
| Harry's legs | 2 | `hanim`, same rule |
| **Biplane propeller** | 2 | `fphs AND 4` — alternates a broken arc with a solid disc |
| **Kelly, while knocked about** | flash | `fphs AND 2` for the 20 frames of `knock` |
| **Elevator doors** | 3 | open → part-open → shut, redrawn only when the phase changes |
| **Escalator steps** | 4 | `esc_tick`, by rewriting four character *patterns* |
| Elevator car | position | its own travel |
| Scanner: Kelly's marker | *(none)* | he was a blinking character cell; both markers are sprites now and carry their own colour (§6a) |

**The propeller is the only moving part a toy plane has.** Drawn static it reads
as a decal painted on the nose; the alternation is what makes it a thing flying
at you. It costs one extra pattern pair per facing.

**The hit flash exists because nothing said you had been hit.** Hitting an
obstacle set a 20-frame `knock` and took *nine seconds* off the clock, and the
only evidence was the number changing — a punishment with no cause attached to
it, especially when the collision happened at the edge of attention. Flashing
the sprite is the arcade's own idiom and costs one variable.

**Escalator steps animate here, though the reference's do not.** A dense frame
burst of the original (§0c) shows its treads holding still while the rider moves
along them — but a moving staircase is what an escalator *is*, and at the
reviewer's direction ours run. It is nearly free: rewriting the step cells'
**patterns** moves every escalator on screen at once — no name-table traffic,
and the same cost whether one flight is visible or ten. The phases slide the
steps *along the slope*, so they travel up the flight rather than drifting
sideways, and a phase advances by exactly the 2 px across and 1 up that a rider
moves in a frame, which is what makes a rider stand on the stairs rather than
hover over them.

**WHICH cells are rewritten is measured, and getting it wrong is silent in both
directions.** `genart.py` compares each cell across the four phases and animates
exactly those that differ.

- Too many, and motionless cells are rewritten sixty times a second for
  nothing. The block used to be “everything except the head cap” — eighteen
  cells, of which **six** move. The balustrade, the frame and the foot were
  identical in all four phases, so three quarters of the phase tables said
  nothing, at 32 bytes a cell.
- Too few, and part of the staircase stands still. The row that crosses the
  floor above is drawn with the **composite** characters (§0d) — same pattern,
  floor colours — and those are separate character codes, so they were outside
  the block. The top steps of every flight were frozen while the rest climbed
  past them. Whether a cell moves is a property of its *pattern*, so a
  composite moves exactly when its plain twin does.

`assets/checkesc.py` gates both: every cell whose pattern changes must sit
inside the animated run, the run must be contiguous, and the `DEFINE CHAR`
base and count in `KEYSTONE.bas` must be exactly that run — a source constant
against generated data, which nothing else ties together.

---

## 6. The scanner

Rows 21–23, 16 chars wide, centred: a **48-char pattern-plotted canvas** in the RallyX radar
style. The chars are fixed in the name table and plotting is a `VPOKE` into the *pattern*
table, so a moving dot costs two writes and no name-table traffic at all.

```
16 chars × 8 px = 128 px wide   ->  8 screens × 16 px per screen
 3 rows  × 8 px =  24 px tall   ->  4 px of MARGIN, 4 levels × 4 px, 4 px of MARGIN
```

The canvas carries **furniture as well as dots**: a full-width line at each floor, a slash at
whichever end that floor's escalator is, and a bar for the elevator car. Without them the
scanner is two dots in a void — you can see *that* Harry is somewhere, but not what he is
near, which is the one thing you actually need when he is off-screen.

**It is coloured BY PIXEL ROW, and that is what lets it show four things at once.** The
canvas was white-on-black throughout, so the floor lines, the escalators, the elevator and
both actors were all the same white — the instrument you navigate by when Harry is off
screen, drawn in one colour, with the player indistinguishable from the furniture. The
colour mode here is per 8×1 scan line, and every pixel row of a band has a fixed job, so
each role gets its own colour at **no run-time cost**:

| band row | what lives there | colour |
|---|---|---|
| +0 | the escalator's **head**, and the elevator car | grey |
| +1 | **Kelly**, and the escalator's **foot** — which the manual draws black anyway, so the slash spans both rows | black |
| +2 | **Harry** | white |
| +3 | the floor line | yellow, matching the store's own floor bars |

**FOUR PIXELS A LEVEL, AND FOUR IS THE FLOOR.** It was six — two furniture rows, a row each
for the actors, a clear row and the floor line — and at six the instrument filled all 24 rows
of its canvas edge to edge, touching the shop floor above it and the bottom of the screen
below. Four levels of four rows is 16, which leaves **eight empty pixel rows, split four
above and four below**. Four separate colours cannot fit in fewer than four rows, so this is
as tight as it goes; the escalator gave up its second grey row and spans the grey and black
ones instead, and the elevator gave up its second row and took the width back instead.

**The margin is BLACK, and that is the point of it.** Inked the scanner's own dark green it
would be padding *inside* the box: the box would still run from the shop floor to the bottom
of the screen and still touch both. Worse, `DGREEN` is within a few counts of the store's
`MGREEN` on this palette, so the box would not read as a separate thing at all — it would
read as more store. Black margins put real space around the instrument, which is how the
original has it: a green scanner floating in the black strip under the store.

**The escalators lean the way they run.** The head goes on the upper row and the foot on the
lower, so a west escalator reads as climbing to the left and an east one to the right — which
is precisely what you need when deciding which way to run. That costs two pixel rows, which
is why the dots are one row and three pixels wide rather than two by two: the ink moved
sideways.

**The elevator marker TRACKS THE CAR.** It began as two black pixels on dark green — not
enough ink to find, so it read as absent — and then as a bar repeated on every floor the car
serves. That second version was still wrong: it says where the *shaft* is, which never
changes and which the player already knows, and says nothing about the one fact that matters,
which is whether the car is on your floor. It is now a **single five-pixel grey bar** erased
and redrawn at `elvl` each tick, exactly like an actor's dot. Five wide rather than three
because it lost its second row to the squeeze, and a fixed centre column plus the extra width
is what tells it from an actor at a glance.

**Furniture and dots share rows, so the furniture is redrawn every tick.** Dots are erased by
ANDing their bits out, so a dot standing over the escalator's foot takes a bite out of it.
Redrawing the escalators and the car each tick is far cheaper than tracking which pixels
belonged to whom.

**The strip either side of the scanner is black too.** The canvas is 16 chars
wide and centred, so eight columns at each end of rows 21–23 are not part of
it. They held the SPACE character, whose colour is black on **cyan** — right for
the HUD on row 0, wrong here, because it left the radar sitting in a cyan strip
with black margins that stopped at its own edges. That reads as a border drawn
round a panel, not as space around an instrument. The font's colour cannot be
changed for these rows alone: the title screen prints at rows 16, 19 and 21,
and blacking the bottom third of the font would take that text with it. One
blank black character (`SCANBK`) is cheaper and cannot affect anything else.

**`assets/checkscan.py` gates the whole layout**, and it has to, because the geometry and the
colours live in two files that never mention each other: `KEYSTONE.bas` computes the rows and
`genart.py` emits the colour of each one. Out of step, there is no error — there is a white
Kop, or an escalator drawn in floor-line yellow, or a dot plotted in a margin row where the
ink is the colour of the ground and the marker simply does not appear. The checker evaluates
the real arithmetic out of the source (`scan_base`, `scan_furn`, `scan_escs`, `scan_elev` and
`scan_tick`) and checks the row each thing lands on is coloured for the job it is doing.
`assets/preview.py` draws the radar from the same evaluator, so the previewer cannot show a
layout the source no longer has.

**The dot masks were mirrored, and that was invisible.** In a pattern byte `0x80` is the
*leftmost* pixel, so an x offset must be subtracted from 7 rather than used as the shift
directly. It was used directly, flipping every dot inside its own character — an error of up
to 7 px that reads as the radar being approximate rather than as being wrong, which is
precisely why nobody would ever chase it. Because of the flip (§2a) this is how you know where
Harry is at all, so it is built in Phase 6 and not left as polish.

---

## 7. Timer, scoring and Kops

- **50 seconds** per Krook, counted down **by frame delta** and never once per loop pass — a
  per-pass counter is not a clock (`CLAUDE.md` §3A), and a warning cue that drifts under load
  is least reliable exactly when the frame is busiest.
- **Flashes below 10 seconds.** The flash runs off its **own phase counter**, not the parity of
  a timer that decrements by a variable delta — an even delta freezes parity and the flash
  silently stops.
- Obstacle hit: **−9 s**. If that takes the timer to zero, the Kop is lost exactly as a
  time-out loses it.
- Capture bonus: `seconds_remaining × 100` (Krooks 1–8), `× 200` (9–16), `× 300` (17+).
- Money bag / suitcase: **50** each.
- **Bonus Kop every 10,000 points, three reserves maximum.**
- Score is a **BCD digit array** — the ×300 band puts a single capture bonus at up to 15,000,
  and a run past 65,535 well inside normal play.

**The Kop indicator shows RESERVES** — `CLAUDE.md` §7A, and here the manual agrees in its own
words ("three reserve Kops"): a fresh game shows **three** icons with a fourth Kop on the
beat, and the last Kop shows **none**. The decrement-then-redraw order means the draw routine
*is* called with `kops = 0`, so the spare count is guarded (`IF kops > 0 THEN spare = kops - 1`)
against the unsigned wrap to 255 that would light every icon exactly when the player has none.

---

## 8. Controls

| action | TI-99/4A | ColecoVision |
|---|---|---|
| Run left / right | joystick left/right | joystick left/right |
| Jump | fire | fire (L) |
| Running jump | fire + direction | fire + direction |
| Duck | joystick **down** | joystick **down** |
| Enter elevator | joystick **up** | joystick **up** |
| Leave elevator | joystick **down** | joystick **down** |
| Board escalator | walk into it | walk into it |

### 8a. ALPHA LOCK — a hazard specific to this game

On the TI, **ALPHA LOCK shares a line with the joystick's vertical axis**
(`ti99-alpha-lock-joystick-vertical`). Latched down, it reports a vertical direction that is
never released. Every other game in this repo dodges this by not reading up/down at all.
**This one cannot** — down is the duck, up is the elevator. With ALPHA LOCK latched, Kelly
ducks forever and biplanes become unavoidable, which reads as a broken game rather than as a
key in the wrong position.

So the title screen **calibrates the axis**: it samples up and down for 40 frames before any
input can reasonably have been given, and a direction held for essentially all of them is the
key rather than a player. It says so on screen and then **ignores that direction for the rest
of the game**, which makes ALPHA LOCK harmless instead of fatal.

**The first version refused to start until the axis cleared, and that was wrong.** Classic99
defaults to `invertcaps=1`, so the TI sees ALPHA LOCK *down* when the host's Caps Lock is *up*
— the normal state. The game then sat on its title screen forever waiting on a condition the
player had no reason to suspect, and it presented as *"the title comes up and it will not
start."* **A check that turns a survivable input quirk into a dead game is worse than no
check** — the same lesson as `check-scope-narrower-than-bug`, one level up: detecting a
condition correctly is not the same as responding to it usefully.

Starting also accepts **`1` as well as FIRE**. On the TI, joystick fire is TAB, which is
neither guessable nor forgiving — Windows treats a stray TAB as a focus change and moves the
window away. Accepting a digit costs one line and removes the only way to be stuck on the
title.

---

## 9. Sound

Every effect gets an **explicit note-off** and a per-channel decay counter, ticked after every
`WAIT` including inside animation loops — sticky audio is the CVBasic default failure.
`SOUND`'s second argument is a **10-bit divisor: smaller is higher, max 1023**, so a "rising"
sweep is written as a *decreasing* argument and anything over 1023 is silently masked to an
unrelated pitch.

| cue | shape |
|---|---|
| Footstep | short tick, alternating pitch, on the run animation phase |
| Jump | quick rising sweep (divisor falling) |
| Obstacle hit | low buzz, and the 9 seconds audibly ticking off |
| Timer warning | one beep per second below 10 s, off its own phase counter |
| Bag / suitcase | bright two-note blip — two notes need **two channels** |
| Capture | short fanfare, then the bonus counts down audibly into the score |
| Bonus Kop | rising chime |
| Harry escapes | descending slide |

---

## 10. Variables (RAM budget — ColecoVision has ~814 bytes total)

| name | meaning | width |
|---|---|---|
| `klv klsc klx kly` | Kelly's level, screen, x, y | 4 × 8 |
| `#klvy` | Kelly's fixed-point y velocity, +32768 biased | 16 |
| `klst` | state: run / jump / duck / ride | 8 |
| `hlv hsc hx` | Harry | 3 × 8 |
| `obx obk obv oby` | 12 obstacles × (x, kind, velocity, y) | 48 |
| `#tmr` | timer in frames (50 s = 3000) | 16 |
| `sc0..sc6` | score, BCD digits | 7 × 8 |
| `krk kops` | Krook number, Kops remaining | 2 × 8 |
| `elv elvy` | elevator car level and pixel y | 2 × 8 |
| `#lf #fd` | last frame, frame delta | 2 × 16 |

Roughly **100 bytes** of game state. The store's maps live in ROM and the scanner canvas lives
in VRAM, so neither touches the Coleco RAM budget — the same discipline that let RallyX fit a
32×56 maze into a machine with 1 KB.

---

## 11. Hazards this game walks into

Each of these has cost a session somewhere in this repo. They are listed here so this game
pays for them once, at design time.

1. **Sprite size/magnification is global** (§5) — 16×16 everything, small objects drawn small.
2. **Four sprites per scanline; the fifth vanishes** — hence ≤3 obstacles per band. Kelly is
   sprite 0, so he is never the one dropped.
3. **Seam oscillation at a screen edge** (§2a) — 8 px hysteresis.
4. **Screen offsets over 255.** `row*32+col` is fine through row 7 and silently truncates
   above it. Every offset is a bare literal or a `#var`; `tools/bigvar.py` and
   `tools/bigconst.py` gate the build. This game has a **20-row playfield and a row-21
   scanner**, so nearly every offset it computes is over 255 — it is maximally exposed.
5. **`PRINT AT` past column 31, and a HUD `VPOKE` landing inside another routine's label** —
   `assets/checklayout.py`, ported from UFO. Its scope must be declared **per screen**
   (title / setup / play), because UFO's first version compared only within a label and
   passed the very bug it existed to catch (`check-scope-narrower-than-bug`).
6. **A `GOSUB` left by `GOTO`.** `do_death`, `do_catch` and `do_escape` are all natural places
   for it and all reached several levels deep; it is invisible on the TI and fatal on Coleco.
   `tools/gosubtrace.py` gates the build.
7. **Reading a 16-bit var right after multiplying it** returns the product's high word — and
   the bonus calculation (`seconds × 100`) is exactly that shape. Compute it behind its own
   label so the compiler is forced to emit a real load.
8. **`%` compiles to a real DIV** — the scanner's screen→pixel mapping uses shifts, not modulo.
9. **Odd-length `DATA BYTE` blocks** misalign every word table after them (§2b).
10. **`VPOKE` operands must be precomputed** into plain vars, never expressions — ISR race.
11. **ALPHA LOCK** (§8a) — this is the first game here that reads the vertical axis in anger.
12. **The Kop indicator counts spares**, and the redraw is called at zero (§7).
13. **FOUR MENU ENTRIES FOR ONE CART, THREE OF THEM BROKEN.** `linkticart.py`
    writes the 80-byte cartridge header at the top of *every* 8 KB loader page and
    then pads the image to a power-of-two page count, so the console finds four
    headers and lists the program four times. Only page 0 is a real entry point:
    the others were copied wholesale and point into the middle of data, so
    selecting one runs from a bogus address. A banked build hides this (the
    console only ever sees bank 0 during its power-up scan), which is why it does
    not show up on every cart in the repo. `assets/onemenuentry.py` blanks the
    `>AA` magic on pages 1+ after linking, and the TI build script runs it.
14. **A one-pixel dead band in the beach ball's arc** (§5a). It is the only hazard whose
    correct response changes mid-flight, so it is the only one that can have a height where
    *no* response works — and that height would present as an occasional unfair hit, never as
    a reproducible bug. It is closed by three numbers chosen together (apex, ducked height,
    hitbox inset) and verified by a **sweep over every `Bb`**, not by playing.

---

## 12. Build

```
games/KeystoneKapers/
  DESIGN.md  README.md
  src/KEYSTONE.bas          one source, both targets
  assets/genart.py          char + sprite patterns
  assets/genstore.py        band templates -> store.bas
  assets/genfont.py         HUD font
  assets/checklayout.py     screen-layout gate, per-screen scope
  assets/checklayout_test.py  proves that gate FAILS on each defect it claims
  assets/onemenuentry.py    strips linkticart's decoy cart headers (see 11.13)
  assets/preview.py         renders a store screen from the SHIPPED bytes
  assets/checkball.py       sweeps every ball height for a dead band (build gate)
  assets/checkchase.py      walks both routes to the roof; fails if the chase
                            cannot be won on foot (build gate, see 4a)
  build-ti.sh               cvbasic --ti994a -> xas99 -> linkticart -> KEYSTONE_8.bin
  build-coleco.sh           cvbasic -> gasm80 -> keystone.rom
```

Both scripts run the same gates as UFO's — `bigvar.py`, `bigconst.py`, `gosubtrace.py`,
`checklayout.py`, `checkball.py`, `checkchase.py` — plus the fixed-area check against the **24,336-byte** cap. Expected to fit
a single bank: the store is ~1 KB of templates and there is no music engine.

---

## 13. Phase plan

Each phase builds on **both** targets before the next one starts.

| # | phase | done when |
|---|---|---|
| 1 | **Store & flip** — 8 screens, 4 bands, templates, `SCREEN` blits, Kelly running, seam hysteresis | You can run the length of the store and back; seams never flicker |
| 2 | **Jump & duck** — fixed-point vertical, apex, running jump, duck height, landing | Kelly hops 14 px and ducks to 8 px, on every floor |
| 3 | **Escalators & elevator** — alternating up-points, the car, ride states, invincibility | You can climb the zig-zag and ride down the middle |
| 4 | **Obstacles** — carts, balls, radios; the ball's jump/duck windows (§5a); the 9-second penalty; bags and suitcases | Hits cost 9 s; ≤3 per band; nothing vanishes on a scanline; the `Bb` sweep finds no dead band |
| 5 | **Harry** — flee AI, catch, roof escape | He can be caught, and he can get away |
| 6 | **Scanner** — the 48-char canvas, both dots and the furniture | You can find Harry without seeing him |
| 7 | **Timer, score, Kops** — countdown, flash, bonus bands, bags, bonus Kop, game over | A full Krook plays start to finish |
| 8 | **Biplanes, difficulty, title** — the ducking hazard, per-Krook ramp **including the ball apex**, title + `838` setup, ALPHA LOCK check, sound | Krooks 1→17+ ramp; late-Krook balls bounce out of the jump band; the title refuses to start with ALPHA LOCK down |

---

## 14. Acceptance criteria

- Runs at **60 Hz on both targets** with 14 actors moving, no frame misses.
- **Zero per-frame VDP reads**, verified by inspection of the main loop.
- A seam crossing repaints once and never oscillates.
- Kelly clears an 8 px obstacle at the top of his jump, and passes under a biplane ducked, on
  every one of the four bands.
- **Swept over every `Bb` from 0 to the 14 px cap, the beach ball is avoidable at every single
  height** — jump below 11, duck above 7. No dead band, verified by sweep and not by playing,
  because a one-pixel hole would present as an occasional unfair hit and never as a
  reproducible bug.
- A high-bouncing ball on a late Krook **cannot be jumped and cannot be run under standing**.
  It is duck-only, and no ball at any apex is ever free.
- The climb from the first-floor entrance to the roof on foot is **three full traverses** of
  the store, one per floor — never two. Getting the alternation backwards silently shortens
  the store by a third and is not visible in a screenshot.
- Harry is catchable at Krook 1 and escapes reliably if ignored.
- The scanner shows both dots at the correct screen and level at all times.
- Bonus bands, the 9-second penalty and the 10,000-point Kop all match §7.
- The Kop indicator shows **three** at the start of a fresh game and **none** on the last Kop.
- Fits the **24,336-byte** fixed area on TI; Coleco RAM stays under 814 bytes.
- With ALPHA LOCK latched, the title says so instead of starting a broken game.
