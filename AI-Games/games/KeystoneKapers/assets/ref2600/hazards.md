# Hazard layout of the Atari 2600 original, measured

Two written sources disagreed about how Keystone Kapers ramps its hazards, so
this measures the game instead. The published GameFAQs guide gives a per-level
table and then says *"from here on out the levels stay the same"* after level 8;
the reviewer recalled the ramp running further, and recalled radios appearing in
twos and threes. **The measurement settles both: the ramp continues to level 11,
and radios do reach three.**

## Source

World of Longplays' full playthrough, `https://www.youtube.com/watch?v=7YxKf8D7w8U`
— 1,426 s, 570x360. Verified to start at the beginning: frame 1 shows score 0,
timer 50 and three spare Kellys. The run reaches **level 21**.

Tooling lived in the job scratch directory, not the repo: one frame per second
extracted with `ffmpeg -vf fps=1`, then a colour/shape classifier per frame, the
timer read by template-matched OCR, and rounds attributed to levels.

## How a frame was read, and what nearly went wrong

Five things are not visible in a single still and each one produced a wrong
answer before it was caught. They are recorded because any future measurement
off this video inherits all five.

* ~~**A band is not a floor.** The view scrolls vertically and *wraps*.~~
  **THIS WAS WRONG AND IT COST THE WHOLE PER-FLOOR ANALYSIS.** Band 0 is grey
  (the roof) in all 1,425 frames and bands 1-3 are green in all of them; nothing
  scrolls vertically. **Band index IS the floor** — 0 roof, 1 floor 3, 2 floor 2,
  3 floor 1 — and per-floor attribution is exact.

  What produced the illusion was the store **flipping screens horizontally**, as
  the port does: a hazard on the roof at one moment and on floor 2 four seconds
  later is two different screens, not one screen scrolled. The first pass read
  that as vertical motion, declared per-storey attribution unreliable, and left
  the most useful question in the file unanswered.
* **A round is not a level.** There is no level number on screen, and the store
  stays drawn during the bonus tally, so nothing in the HUD or the playfield
  marks a boundary. Rounds were cut at the timer's reset to 50 — but *a death
  also resets the timer*. The spare-Kelly count separates them: 25 rounds, 21
  levels, four deaths. Reading the time bonus instead called all 25 rounds wins.
* **The radio is not always green.** The 2600 recolours it per level, and its
  yellow is the biplane's yellow — same hue, same brightness. What separates them
  is that a radio SITS ON THE FLOOR and a biplane FLIES. Before that test, the
  centre radio was counted as a biplane 245 times, a fifth of every plane
  sighting in the video.
* **The floor line is the biplane's colour too**, at (189,178,35) against the
  wing's (229,221,63). A tolerance box wide enough to survive the video's
  re-encode swallows the line, and then every column of every floor contains a
  plane. Only brightness separates them: the wing goes above 205, nothing else
  does.
* **A maximum believes its noisiest frame.** Counting the most ever seen at once
  reported *four* radios on six levels. There are exactly three radio positions;
  every one of those sightings was those three plus a one-frame stray elsewhere —
  7 frames out of 1,425. A count is only believed here if it held for 3 frames.

## What the levels do

Counts are the most of that kind on one floor at one instant. They are **lower
bounds**: the player does not visit every floor every round, so a level may allow
more than was seen. Read the first level a count appears at, not its absence
afterwards.

| level | radios | carts | balls | biplanes |
|------:|-------:|------:|------:|---------:|
| 1     | 1      | –     | 1     | –        |
| 2     | 1      | –     | 1     | –        |
| 3     | 1      | 1     | 1     | –        |
| 4     | 1      | 1     | 1     | 1        |
| 5     | 1      | 1     | 1     | 1        |
| 6     | **2**  | 1     | 1     | 1        |
| 7     | 2      | 1     | 1     | 1        |
| 8     | **3**  | 1     | 1     | 1        |
| 9     | 2      | 1     | **2** | 1        |
| 10    | 3      | 1     | –     | 1        |
| 11    | 3      | **2** | 2     | 1        |
| 12-21 | 3      | 2     | 2     | 1        |

So the arrivals are **carts at 3, biplanes at 4**, and the doublings are
**radios at 6, a third radio at 8, balls at 9, carts at 11**. From level 11 the
layout does not change again through level 21.

Two findings worth stating plainly:

* **The ramp does not stop at 8.** The guide's table ends there and says the
  levels stay the same; balls double at 9 and carts at 11. The reviewer's
  recollection was right and the guide is simply incomplete — its author
  reached level 8.
* **Biplanes never double.** One, in every one of the 21 levels, across 800+
  frame-sightings. Every other hazard doubles; this one does not. It is also the
  hazard that must be ducked rather than jumped.

Radios are present from level 1, which the guide's "level 1 is merely a few beach
balls" does not mention. 18 frames of level 1 show one.

## Where hazards are placed — the part that matters most

**Radios are static and sit on three fixed positions**, at x 149, 269 and 389 in
capture pixels. 99.7% of 2,381 radio sightings are at exactly those three. The
level decides how many of the three are filled. Balls and carts, by contrast,
are spread uniformly across every x — they move.

The gap between two hazards of one kind on one floor, over the whole video:

| kind  | gap (capture px)                | in our pixels |
|-------|---------------------------------|---------------|
| ball  | **240** (164), 360 (31)         | **108**, 162  |
| cart  | **240** (205), 360 (89)         | **108**, 162  |
| radio | **120** (1007), 240 (170)       | **54**, 108   |

**A moving pair is never closer than 240 capture pixels — 108 of ours.** Not
once in 21 levels. The 360s are the same grid two steps wider. Radios, being
static, go down to one grid step apart.

The scale is `256 / 570 = 0.449`: the store fills the capture's full width, and
our port places hazards across a 256 px screen.

### This independently confirms the jump model

`assets/checkspace.py` derives, from the shipped jump arc and speeds, that a
player can land between two hazards when the gap is at least **82 px** for a
moving pair, and about **49 px** for a static one (a static hazard closes only at
walking pace).

The original's tightest spacings are **108 px** for a moving pair and **54 px**
for a static one. Both sit just above the thresholds our own arc predicts, from
completely independent evidence. That is a strong check on the model — and it
says the shipped `HAZGAP` of 20 px, which puts a pair inside one jump, is a
window the original never uses for moving hazards.

## Density, and which floor carries what

Once band index is understood to be the floor, both questions the first pass gave
up on fall straight out of the same census. **These two tables are the design
target for `stor_lvl`, and `assets/checklevels.py` asserts against them** — they
are the point of this document, not background.

### How much is on screen at once

The original flips screens exactly as the port does — **2 escalator, 1 elevator,
5 hazard screens** — so this compares like with like. Screen type is inferred
from the static furniture (aisle pillars and counters), which makes the split a
good proxy rather than an exact one; the totals are exact.

| level | hazard screens (mean / median) | escalator + elevator | the port, before this work |
|------:|-------------------------------:|---------------------:|---------------------------:|
| 1     | **0.71 / 0**                   | 0.33 / 0             | **2.00**                   |
| 2     | 1.50 / 2                       | 0.25 / 0             | ~3                         |
| 3     | 2.47 / 3                       | 1.67 / 2             | 4                          |
| 4     | 3.28 / 4                       | 2.93 / 3             | 4                          |
| 5     | 3.17 / 4                       | 2.54 / 3             | 4                          |
| 6     | 3.97 / 4                       | 3.03 / 4             | 4                          |
| 7     | 4.04 / 4                       | 3.68 / 4             | 4                          |
| 8     | 4.50 / 5                       | 3.09 / 4             | 4                          |
| 9     | 4.97 / 5                       | 3.09 / 4             | 4                          |
| 10    | 3.59 / 4                       | 3.78 / 4             | 4                          |
| 11    | 5.15 / 5                       | 4.14 / 4             | 4                          |
| 12    | 6.09 / 7                       | 4.74 / 4             | 4                          |

Two things follow, and the second was a genuine surprise:

* **Level 1 is nearly empty — a median of ZERO hazards on screen**, and level 2
  barely more. From level 4 the port's density is about right; the fault is
  entirely in levels 1-3.
* **The escalator and elevator screens are not empty.** From level 3 they carry
  almost as much as the aisle screens. The port excluded screens 0, 3 and 7
  outright.

### Which kind on which floor

Percentage of a level's frames in which that kind was visible on that floor. A
column showing several kinds means that floor carries **a mix**, not one hazard
type.

| level | roof | floor 3 | floor 2 | floor 1 |
|------:|------|---------|---------|---------|
| 1  | radio 7%             | ball 10%, radio 3%                | radio 19%                       | ball 7%, radio 1%                        |
| 2  | radio 31%            | ball 8%, radio 4%, cart 2%        | radio 16%                       | ball 12%, cart 2%                        |
| 3  | radio 45%, cart 35%  | radio 22%, ball 16%, cart 16%     | cart 19%, radio 12%             | cart 25%, ball 19%, radio 3%             |
| 4  | cart 48%, radio 34%  | cart 32%, radio 24%, ball/plane 6% | plane 43%, cart 17%, radio 15% | cart 51%, ball 18%, plane 6%, radio 3%   |
| 7  | radio 57%, cart 57%  | cart 49%, radio 26%, plane 11%    | plane 53%, cart 17%, radio 15%  | cart 65%, ball 14%, radio 4%, plane 4%   |
| 11 | radio 88%, cart 46%  | radio 71%, plane 22%, cart 21%    | radio 47%, plane 45%, cart 21%  | cart 47%, ball 33%, plane 11%, radio 4%  |

**Every floor carries two to four kinds from level 3 onward.** The port assigned
one kind per floor for the whole game (floor 1 all balls, floor 2 all radios, and
so on), which is the other half of what was reported from play.

## What this does not settle

* **Speeds.** The guide's "carts get faster at 7, planes at 8" was not measured;
  tracking a hazard's velocity across frames is a different job from counting.
* **Tall balls.** The guide puts them at level 5. Bounce height was not measured.
* **Which SCREEN of a floor a hazard sits on.** The census records the screen the
  player was standing on, not its index in the floor, so the per-screen pattern
  within a level is not recoverable from this data. The port's table is free to
  choose, subject to the density above.
