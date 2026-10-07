# Choplifter for the TI-99/4A

A CVBasic rescue game inspired by the original Choplifter: four prison camps, 64 people, a
16-seat helicopter, three helicopters, tanks, jets and pursuing airborne mines. New game code
and pixel art, with eight screens of horizontal scrolling, parallax stars, animated rotors,
sound effects, mission results and a session best rescue count.

The cartridge is **[build/ti/CHOPLIFT_8.bin](build/ti/CHOPLIFT_8.bin)**: a 64 KB banked TI
cartridge that needs the **32 KB RAM expansion**. Load it in Classic99 or on cartridge
hardware. A ColecoVision build is produced at `build/coleco/choplift.rom`.

## Play

| Control | Action |
|---|---|
| `1` `2` `3` or LEFT/RIGHT at the title | Pick easy, medium or hard (shown in brackets; kept between games) |
| FIRE at the title | Start |
| Joystick up/down | Climb/descend; holding DOWN builds descent speed |
| Release DOWN | Stop descending; use short presses for a soft landing |
| Stick centred | Gravity: the helicopter sinks slowly and settles safely |
| Joystick left/right | Fly sideways; facing stays independent |
| Release left/right | Brake into a hover, keeping your aim |
| Tap FIRE in flight | Fire on release: sideways when facing left/right, a bomb when facing front |
| Hold FIRE | Turn after 0.3 s, then every 0.25 s (left, front, right, front) |
| SPACE (TI) / keypad `*` (ColecoVision) | Turn one step per press, in the air |
| Hold `P` (TI) / `0` (ColecoVision) | Pause; the same key or FIRE resumes |
| BACK (`FCTN-9`) or REDO (`FCTN-8`) / keypad `#` | Abandon the mission and return to the title |

The supplied Classic99 profile uses **arrow keys and Tab for joystick 1**. On real hardware,
release ALPHA LOCK if it interferes with the joystick's vertical axis.

You start at home on the right, on the landing pad beside the brick headquarters with the
flag on its roof. Fly
west across the demilitarised zone, drop low and **strafe** one of the blue barracks (fire
sideways; bombs pass by): it is blown open, a fire burns inside, and sixteen people pour out
in two groups, even while you are away or your cabin is full. Land beside a group and stop:
everyone within reach runs for the cabin at once, as many as there are free seats, and
climbs aboard on arrival. Fly home and land on the gray **H pad** against the building:
passengers only step out with the whole helicopter on the pad. They walk in through the
door, and some stop on the dark ground beside it to wave at you first. The last one out
always does. Lift off with UP before moving sideways on the ground. Weapons and turning do
not work on the ground.

Holding DOWN speeds up the descent, and touching down fast crashes; the engine warns with a
high, pulsing whine while you are coming down too fast. Anything that hits you is drawn
touching you first, and only what is drawn counts: the cabin, nose, skids and tail boom,
not the rotor or the empty air around them. A crash is a burst of fire and sparks where you
were hit; the burning wreck falls, bursts again on the ground and burns out, and only then,
with the screen clear, does the next helicopter appear on the pad. A crash loses everyone
aboard, but the camps keep emptying while the wreck burns. Do not land on people or shoot
through them.
**Tanks** roll along the foreground below the camps, so only **bombs** (face front and tap
FIRE) destroy them. They **lob short shells** from raised barrels that rise and fall under
gravity, aimed at where you are when they fire, and only while they are on screen and you
are landed or within a few pixels of the ground: a shell bursts within 0.6 s and reaches
about 105 pixels (90 on easy, 120 on hard), and the burst kills anyone it lands on. Keep
moving and they miss; stay airborne and they hold fire. Tanks stop short of the DMZ fence.
After your first completed delivery a second tank joins in, and jets arrive and make three
passes. A jet on screen fires only straight ahead: **missiles** (missile-shaped) that fly
level along its line of flight for half a second, so it needs you ahead and at its height,
then dive into the ground, or **bombs** that fall onto you if you are landed. After the
second delivery an **air mine** (a small red spiked ball) drifts in at mid height from
beyond the edge of the screen, never from the top and never on top of you, and follows
you, slowly, but never past the DMZ fence. Jets and air mines fall to sideways shots only.
Every completed delivery (up to four) makes them press harder: tanks reload faster, jets
carry more missiles, and the next jet and air mine come sooner.

**Difficulty** sets how hard they push from the start: on easy tanks reload more slowly
and reach less far, jets carry fewer missiles, fire less often and only when you are nearly
level with them, and air mines come later and drift at half speed; hard is the reverse.
Medium is the game as it was before the levels existed.

Everything that blows up bursts into sparks and smoke: tanks, barracks, jets, air mines and
your helicopter. Every bomb, missile and shell bursts where it lands, and your shots leave a
tiny puff where they hit. When one hits a person the burst throws a spray of sparks and
dirt; on bare ground with no target you see only its flash and smoke, so you can tell a
miss from a hit. The top line shows SAVED, ABOARD and LOST, and on the right your **spare**
helicopters (not counting the one you are flying). The mission ends when all 64 people are
saved or lost, or the last helicopter is destroyed. There is no fuel.

When more than four sprites share a scanline they flicker in turn (sprite flicker is on), so
nothing that can hit you is ever invisible for long; a tank shell is always drawn before it
can strike. The helicopter holds its place on screen while the scenery scrolls past it in
8-pixel steps, and sprites move on the same frame as the scenery, so it does not shake or
jitter. The ground is dark blue and the landing pad gray with a white rim and an H.

For practice, type **838** at the title and answer **1–9** for the number of helicopters.
Practice saved counts carry a small asterisk, and the best rescue keeps its marker. Up to
five spare icons show.

## Build

From `AI-Games/games/Choplifter/` on the configured Windows machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 All
powershell -NoProfile -ExecutionPolicy Bypass -File launch-ti.ps1
```

`build.ps1 TI` or `build.ps1 Coleco` builds one target; `build.ps1 All` runs the tests once
and builds both (about three and a half minutes). Cygwin users may run `bash build-ti.sh` or
`bash build-coleco.sh`; do not use Git Bash. Dependencies: the **unhuman/CVBasic** fork,
Python 3.10+, xdt99's `xas99.py`, `linkticart.py`, Keystone Kapers' `shortbranches.py` (in
this repository) and, for ColecoVision, `gasm80`. Override `CVBASIC_DIR`, `XDT99_DIR` or
`GASM80` as needed. `TI_SHORT_BRANCHES=0` skips the branch-shortening pass for comparison.

`launch-ti.ps1` opens a separate Classic99 review session (the Downloads build) with the
project's input profile and loads the production cartridge; it leaves other emulator
sessions alone. Pass `-ReviewProcessId` with the ID in `build/review/process-id.txt` to
reload that session.

| Target | Code | RAM |
|---|---:|---:|
| TI-99/4A | 22,198 / 24,336 B fixed (+ 7,140 and 4,634 / 8,190 B banks) | 806 / 7,854 B |
| ColecoVision | 27,542 / 32,768 B ROM | 808 / 814 B |

## Speed

Measured in Classic99 at normal speed with `tools/profile.py`, full game loop:

| Situation | Updates per second |
|---|---:|
| Cruising | 20 (was 12) |
| Combat over a crowd: tank, jet, air mine, shots | 12.5 (was 7.5) |
| Two camps evacuating at once | 10 (was 5) |

The TI build uses small assembly kernels for the star field, crowd walking and crowd
drawing; the ColecoVision build runs the equivalent BASIC. See [DESIGN.md](DESIGN.md) for the
performance and size budgets, the scrolling pipeline, the crowd renderer and the sprite plan.

## Implementation and validation

- `src/CHOPLIFT.bas`: game logic, input, rendering and sound.
- `assets/generate.py`: pixel art (scenery painted letter by letter and checked against the
  two-colours-per-row limit), world map, star table and shell arc; writes `src/assets.bas`
  (play-time data) and `src/assets_boot.bas` (art uploaded once at power-on, in its own TI
  bank).
- `tools/check.py`: 94 tests that execute the BASIC routines and the TI assembly kernels in a
  strict interpreter, compare each kernel with its BASIC twin, and reject known-bad
  mutations. They cover rescue accounting, crowds, controls, gravity, pause, BACK/REDO,
  weapons, enemies, sprite flicker, scrolling order, scenery, stars, sound envelopes,
  boarding, waving, the threat ramp and difficulty, the title, crashes, explosions, hit
  boxes checked against the sprite art, the steady helicopter while scrolling, the landing
  pad, the fence limit and air-mine arrivals.
- `tools/build.py`: generation, tests and gates, compilation, assembly, branch shortening,
  budget and word-alignment checks, and cartridge packing.
- `tools/profile.py` and `tools/run-bench.ps1`: speed benchmarks (whole-loop, per-routine and
  stubbed variants) and a production-code review cart (`--review`, with `--calm` for no
  enemies). Benchmark carts look
  scrambled on screen by design.

Verified in Classic99 with the production code: scrolling over evacuating camps, tanks,
shells, crashes, a whole group boarding together, the redrawn barracks (and blown open with
the fire inside), the snow-capped mountain ranges with their foothills, the home base, two tanks lobbing from the foreground,
an air mine, gravity, a passenger waving, and the title helicopter; then the crash sequence,
explosions, ground bursts from bombs and a diving missile, the steady helicopter while
scrolling, the landing pad and a tank stopping at the fence. Not yet verified: original
hardware, sound balance and a full 64-person playthrough.

## Design references

See [DESIGN.md](DESIGN.md). References include the
[Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057),
[Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121),
[Wikipedia](https://en.wikipedia.org/wiki/Choplifter),
[C64-Wiki](https://www.c64-wiki.com/wiki/Choplifter),
[single-button version comparison](https://www.atariprotos.com/other/gamediff/choplifter/choplifter.htm)
and the [C64 longplay](https://www.youtube.com/watch?v=wCrKd0fM1CY). The original game was
created by Dan Gorlin and published by Brøderbund. This implementation uses CVBasic by Oscar
Toledo G. and its TI support by Tursi.
