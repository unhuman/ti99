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

* **A band is not a floor.** The view scrolls vertically and *wraps*, so the same
  band holds the roof at one moment and floor 2 four seconds later. Counting
  "hazards on floor 2" by fixing a y range gives nonsense; counts here are per
  band-instant.
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

## What this does not settle

* **Speeds.** The guide's "carts get faster at 7, planes at 8" was not measured;
  tracking a hazard's velocity across frames is a different job from counting.
* **Tall balls.** The guide puts them at level 5. Bounce height was not measured.
* **Which floors carry hazards.** Occupied bands averaged 2.8-3.4 of 4 from level
  3 onward and 0.5-0.8 on levels 1-2, which is consistent with the ramp in
  occupancy the port already has, but the vertical wrap makes per-storey
  attribution unreliable and it was not pursued.
