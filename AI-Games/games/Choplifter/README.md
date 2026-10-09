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
| `1` `2` `3` or LEFT/RIGHT at the title | Pick easy, medium or hard (shown in cyan brackets; kept between games) |
| FIRE at the title | Start |
| Joystick up/down | Climb/descend; holding DOWN builds descent speed |
| Release DOWN | Stop descending; use short presses for a soft landing |
| No UP or DOWN | Gravity: the helicopter sinks slowly, even while flying sideways; tap UP to hold altitude |
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
west across the demilitarised zone. The hostages behave as in the Apple II original. The
nearest barrack is already burning when you start, with six of its people spread across
their wandering ground. For the
others, drop low and **strafe** one of the blue barracks (fire sideways; bombs pass by): it
is blown open, a fire burns inside, and its sixteen people come out a few at a time, even
while you are away or your cabin is full. Only about six are ever outside; more come out
as others are picked up. Outside they run about on their own, dash, stop, look around and
dash again, and they stop and wave as you fly over. Come down low over them and up to six
run underneath you: land right on them and you crush them, so set down beside them. Landed,
those within reach run for the cabin, as many as there are free seats, and climb aboard.
Lift off and land again further on and the runners follow, as far as you lead them (never
past the DMZ fence); but if someone nearer is waiting, or you leave them far behind, they
give up and run all the way back to their own barrack, ignoring you unless you land right
beside them. With the cabin full they wave you off and wait for you to come back. Fly home and land on the red pad's **yellow octagon** beside the building:
passengers only step out with the whole helicopter on the pad. They walk in through the
door, and some stop on the dark ground beside it to wave at you first. The last one out
always does. Lift off with UP before moving sideways on the ground. Weapons and turning do
not work on the ground.

The rotor chops quicker the faster you fly, slower when hovering and slowest idling on the
pad. Holding DOWN speeds up the descent, and touching down fast crashes; the engine warns with
a high, pulsing whine while you are coming down too fast. Anything that hits you is drawn
touching you first, and only what is drawn counts: the cabin, nose, skids and tail boom,
not the rotor or the empty air around them. A crash is a burst of fire and sparks where you
were hit; the burning wreck falls, flickering yellow and red, bursts again on the ground and
burns down gradually to embers, and only then,
with the screen clear, does the next helicopter appear on the pad. A crash loses everyone
aboard, but the camps keep emptying while the wreck burns. Do not land on people or shoot
through them; your bombs fall in front of the crowd and pass people by.
The home scene shows FIRST, SECOND or THIRD SORTIE between two solid bars when a new
helicopter arrives. Its rotor turns while the message is up. Press UP to lift off and clear
any sortie message immediately; FIRST SORTIE waits for that move, while later messages
also clear after a brief pause. The hidden practice mode numbers sorties four through nine.
The two boundary fences enclose a 320-pixel demilitarized zone west of the landing pad.

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
your helicopter; a burst in the sky also drops a burning chunk that falls away below it.
Every bomb, missile and shell bursts where it lands, and your shots leave a
tiny puff where they hit. When one hits a person the burst throws a spray of sparks and
dirt; on bare ground with no target you see only its flash and smoke, so you can tell a
miss from a hit. The magenta band at the top counts, left to right, the people lost (red
dot), on board (cyan) and saved (green), and the last box holds your **spare** helicopters
(not counting the one you are flying). The mission ends when all 64 people are
saved or lost, or the last helicopter is destroyed. There is no fuel. Rescue all 64 and a
fireworks display lights up the sky over the home before the summary: rockets whistling up
from behind the building at fanning angles, trailing sparks, and bursting into spheres,
willows and rings in six colours. Ten go up one at a time, then the finale: a quickening
salvo of five, a triple and a pair, another triple and pair, and a crescendo of five at
once, about ten and a half seconds in all.

When more than four sprites share a scanline they flicker in turn (sprite flicker is on), so
nothing that can hit you is ever invisible for long; a tank shell is always drawn before it
can strike. The helicopter holds its place on screen while the scenery scrolls past it in
8-pixel steps, and sprites move on the same frame as the scenery, so it does not shake or
jitter. A low blue horizon runs behind the people, buildings and landed helicopter. The
landing apron is dark red, with a gray sidewalk by the building and a yellow landing marker.

The mission summary centres its heading at the top and the FIRE prompt at the bottom. It
names the skill level you played, with your saved, lost and stranded counts and the
session's best rescue.

For practice, type **838** at the title and answer **1–9** for the number of helicopters.
The summary marks a practice game with a small asterisk after its skill level and saved
count, and the best rescue keeps its marker. Up to
four spare icons show. Typing **HOWIE** at the title (**4-6-9-4-3** on the ColecoVision
keypad) plays the fireworks without winning a game.

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
| TI-99/4A | 22,750 / 24,336 B fixed (+ 8,188 and 8,186 / 8,190 B banks) | 812 / 7,854 B |
| ColecoVision | 32,100 / 32,768 B ROM | 812 / 814 B |

## Speed

Measured in Classic99 at normal speed with `tools/profile.py`, full game loop:

| Situation | Updates per second |
|---|---:|
| Cruising | 20 (was 12) |
| Combat over a crowd: tank, jet, air mine, shots | 12.5 (was 7.5) |
| Two camps evacuating at once | 10 (was 5) |

(The crowd figures predate the hostages running about, with at most six out per camp; they
are due to be measured again.)

The TI build uses small assembly kernels for the star field, crowd walking and crowd
drawing; the ColecoVision build runs the equivalent BASIC. See [DESIGN.md](DESIGN.md) for the
performance and size budgets, the scrolling pipeline, the crowd renderer and the sprite plan.

## Implementation and validation

- `src/CHOPLIFT.bas`: game logic, input, rendering and sound.
- `assets/generate.py`: pixel art (scenery painted letter by letter and checked against the
  two-colours-per-row limit), world map, star table and shell arc; writes `src/assets.bas`
  (play-time data) and `src/assets_boot.bas` (art uploaded once at power-on, in its own TI
  bank).
- `tools/check.py`: 111 tests that execute the BASIC routines and the TI assembly kernels in a
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
