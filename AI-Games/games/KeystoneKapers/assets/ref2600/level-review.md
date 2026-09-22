# Level and movement review — 2026-09-21

Reference: [World of Longplays, Atari 2600 Longplay 003](https://www.youtube.com/watch?v=7YxKf8D7w8U),
1,426 seconds, downloaded at 570×360 / 30 fps. This review supplements
[hazards.md](hazards.md); its old speed assumptions were incomplete.

## Findings that changed the game

1. **Prizes were exhausted for the whole game.** `takn(0..3)` was cleared only
   in `new_game`. Catching Harry increased `krk` without clearing those bits.
   A player who collected the five prizes across the first few levels could
   therefore find no prizes thereafter. Each successful capture now replenishes
   them. Screen crossings and losing a life retain collection state for that
   Krook, so revisiting or deliberately dying cannot farm the same prize.
2. **The speed curves were wrong.** Balls, early carts and early planes all used
   51/64 px/frame. The video has carts/planes moving twice as fast as balls,
   fast single carts from level 7, slower paired carts from level 11, and four
   plane tiers. The last two plane tiers were absent altogether.
3. **Fill-order rank accidentally selected the hazard kind.** A modulo-four
   selection combined with four floors settled into balls below planes below
   radios. The generator now chooses from explicit aisle cycles, independently
   of occupancy rank. From level 4 each shopping floor has at least three kinds
   across its occupied screens. The roof remains carts only.
4. **The loader did not implement the table's radio counts.** From level 8 a
   supposedly single radio spawned a second one in the third slot. From level 6
   it also stood at the left rack position instead of the centre. The pair bit
   now controls both decisions. A pair upgrades to three from level 8; a single
   stays centred and single. The generator also reserves both extra places when
   turning one radio into three, so a screen cannot exceed its load cap by one.

## Movement measured from the supplied video

These are horizontal speeds in **capture pixels per second**, not Atari pixels,
port pixels, pixels per game pass, or sprite animation rates.

| Kind | Levels | Measured speed | Useful witnesses |
|---|---|---:|---|
| Ball | 1–21 | about 112.5 | 00:28, 01:04, 06:57, 12:36, 18:14 |
| Cart | 3–6 | about 225 | 01:55, 02:25, 03:26, 04:30 |
| Cart | 7–10 | about 450 | 05:34, 06:57, 08:00, 09:09 |
| Cart | 11–21 | about 225 | 10:15, 11:25, then each later-level witness |
| Plane | 4–7 | about 225 | 02:25, 03:26, 04:30, 05:34 |
| Plane | 8–11 | about 450 | 06:57, 08:00, 09:09, 10:15 |
| Plane | 12–15 | about 675 | 11:25, 12:36, 13:32, 14:30 |
| Plane | 16–21 | about 900 | 15:12, 16:45, 18:14, 20:31, 22:01 |

[motion.csv](motion.csv) retains individual accepted tracks and fit errors.
The velocities are estimates: sprite animation and video compression shift a
detected bounding box by a pixel or two. Several short plane tracks at level 12
run slightly above 675; the longer traces and subsequent levels distinguish the
675 tier clearly from both 450 and 900. A missing kind in a witness means it was
not visible there, not that the entire level omits it.

The 240-capture-pixel spacing of a pair and the 600-capture-pixel wrap period
were checked separately; **570 is the visible image width, not the wrap period**.
Mapping that period to the port's 240-pixel hazard loop gives a factor of 0.4.
The resulting port speeds at 60 Hz are:

| Levels | Balls | Carts | Planes |
|---|---:|---:|---:|
| 1–2 | 45 px/s | absent | absent |
| 3 | 45 | 90 | absent |
| 4–6 | 45 | 90 | 90 |
| 7 | 45 | 180 | 90 |
| 8–10 | 45 | 180 | 180 |
| 11 | 45 | 90, including pairs | 180 |
| 12–15 | 45 | 90, including pairs | 270 |
| 16+ | 45 | 90, including pairs | 360 |

The ball changes slightly from the former 47.8 px/s. Kelly, Harry, escalators,
elevator timing, bounce periods, jump shape and the round timer are unchanged.
The velocity program remains frame based on all three platforms.

### Attribution to levels

Timer resets were checked against score and spare hats. Starts, in seconds:

```
level  1       2      3      4      5      6      7      8      9     10
time   0    57.5  104.5  135.5  193.5  250.5  321.5  390.5  460.5  534.0

level 11      12     13     14     15     16     17     18      19      20      21
time 602.0 672.5  743.5  799.0  857.0  899.0  992.0 1081.0 1165.5  1218.0  1308.5
```

The reset at 1179.5 is a death/retry on level 19. Resets at 1366, 1388.5 and
1396.5 are deaths/retries on level 21. Thus the 25 rounds represent 21 levels,
not 25. In particular, the plane increases occur on levels 12 and 16, not on
round numbers shifted by those deaths.

### Reproducing the measurements

Install Pillow; obtain the linked video at the documented resolution. From Bash:

```sh
python3 assets/ref2600/measure_motion.py /path/to/reference.mp4 /path/to/scratch \
  --ffmpeg /path/to/ffmpeg --csv /path/to/motion.csv
```

The script takes 20 samples at 10 fps from each two-second witness, finds bright
cart baskets, red balls and airborne yellow planes, and fits constant-velocity
tracks. It rejects tracks shorter than four samples, fits with more than three
pixels of error, and stationary fragments. Floor-height and shape checks exclude
pillars, floor lines and most flashing actors. Plane propeller fragments are
joined before tracking. Screen flips/wraps break tracks rather than becoming
huge apparent velocities. The original video and extracted images stay outside
the repository. The initial survey also examined 2,852 frames at 2 fps to locate
round transitions and sustained motion; 2 fps is too sparse for reliable tracking
of the fastest planes, which is why the velocity measurements use 10 fps.

## Layout adaptation and limits

The port preserves its established empty escalator screens (0 and 7), keeps
radios off the elevator boarding rack, and keeps the roof free of radios because
of TI/Coleco skyline colour sharing. These are deliberate differences from the
2600. Counts and encounter progression are matched; this is **not a recovered
screen-for-screen map** of the Atari ROM. The longplay does not visit every band,
and visual transitions alone do not establish all absolute screen indices.

Radios now appear in sparse level 1, consistent with both this video and the
existing census. Carts arrive at 3 and planes at 4. Radios pair at 6 and can form
triples at 8; balls pair at 9 and carts at 11. Planes stay single. Level 11 uses
nine paired bands rather than seven, distributing more cart pairs while reaching
5.17 hazards per eligible screen against the measured 5.15. Counts remain within
the existing per-level caps; later levels reuse that layout while planes keep
accelerating.

## Fast-movement safeguards

The shared byte accumulator now has three drains and accepts at most 192 units:
its remainder is at most 63, so addition cannot exceed 255. Planes count
two-pixel units and double only the resulting displacement, allowing the last
tier without new RAM. Both wrap directions subtract the distance to the edge
before adding/subtracting; a 30-pixel catch-up step must not overflow a byte.

Collision checks include the travelled centre segment for carts and planes.
Otherwise a fast plane could cross a standing Kelly between passes without
being detected. Ducking still clears planes; no vertical hitbox was enlarged.

Moving-pair spacing is checked at the speeds those pairs actually use. The
104-pixel gap exceeds the 91-pixel landing requirement for the new cart pairs,
and preserves 121 pixels of entry clearance. Fast planes never pair. Keeping
the single-cart speed after level 10 is a tested failure: it would make the
existing pair gap unsafe.

`levelplay_test.py` executes the actual BASIC loader for all screens and levels
1–20 under each platform's preprocessor branch, checks prize replenishment,
executes every accumulator remainder at the supported speeds, exercises both
wrap directions, and checks fast collisions while standing and ducking. Full
build and emulator results are recorded in DESIGN.md section 30.
