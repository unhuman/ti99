# Choplifter for the TI-99/4A

A CVBasic rescue game inspired by the original Choplifter: four prison camps, 64 people, a
16-seat helicopter, three helicopters, tanks, jets and pursuing airborne mines. New game code
and pixel art, with eight screens of horizontal scrolling, parallax stars, animated rotors,
sound effects, mission results and a session best rescue count.

The cartridge is **[build/ti/CHOPLIFT_8.bin](build/ti/CHOPLIFT_8.bin)**: a 32 KB banked TI
cartridge that needs the **32 KB RAM expansion**. Load it in Classic99 or on cartridge
hardware. A ColecoVision build is produced at `build/coleco/choplift.rom`.

## Play

| Control | Action |
|---|---|
| FIRE or `1` at the title | Start |
| Joystick up/down | Climb/descend; holding DOWN builds descent speed |
| Release DOWN | Stop descending; use short presses for a soft landing |
| Joystick left/right | Fly sideways; facing stays independent |
| Release left/right | Brake into a hover, keeping your aim |
| Tap FIRE in flight | Fire on release: sideways when facing left/right, a bomb when facing front |
| Hold FIRE | Turn after half a second, then every 0.3 s (left, front, right, front) |
| Hold `P` (TI) / `0` (ColecoVision) | Pause; the same key or FIRE resumes |

The supplied Classic99 profile uses **arrow keys and Tab for joystick 1**. On real hardware,
release ALPHA LOCK if it interferes with the joystick's vertical axis.

You start at home on the right. Fly west across the demilitarised zone, turn to face front
and bomb a barrack: its roof burns and sixteen people pour out in two groups, even while you
are away or your cabin is full. Land beside a group and stop: everyone within reach runs for
the cabin at once, as many as there are free seats, and climbs aboard on arrival.
Fly home and land on the **H pad**; passengers step out and walk into the post office. Lift
off with UP before moving sideways on the ground. Weapons do not work on the ground.

Holding DOWN speeds up the descent, and touching down fast crashes; the engine warns with a
high, pulsing whine while you are coming down too fast. A crash loses everyone aboard, but the
camps keep emptying while the wreck burns. Do not land on people or shoot through them. Tanks shell you whenever you come
within range, and **straight up when you hover over them**. Jets arrive after your first
completed delivery and make three passes firing missiles; after the second delivery a drone
hunts you, even across the DMZ. Every completed delivery (up to four) makes them press harder:
tanks reload faster, jets carry more missiles, and the next jet and drone come sooner. Camp indicators change from a number to `o` when opened
and `-` when emptied; the helicopter icons are your **spare** helicopters. The mission ends
when all 64 people are saved or lost, or the last helicopter is destroyed. There is no fuel.

Shells and missiles are always drawn, even on a crowded scanline. When too many sprites share
a line (a tank firing beside your landed helicopter), the tank halves flicker in turn rather
than one disappearing.

For practice, type **838** at the title and choose **1–9 helicopters** (`0` cancels).
Practice saved counts carry a small asterisk, and the best rescue keeps its marker.

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
| TI-99/4A | 21,834 / 24,336 B fixed (+ 8,032 / 8,190 B bank) | 806 / 7,854 B |
| ColecoVision | 24,576 B ROM | 809 / 814 B |

## Speed

Measured in Classic99 at normal speed with `tools/profile.py`, full game loop:

| Situation | Updates per second |
|---|---:|
| Cruising | 20 (was 12) |
| Combat over a crowd: tank, jet, drone, shots | 12.6 (was 7.5) |
| Two camps evacuating at once | 10 (was 5) |

The TI build uses small assembly kernels for the star field, crowd walking and crowd
drawing; the ColecoVision build runs the equivalent BASIC. See [DESIGN.md](DESIGN.md) for the
performance and size budgets, the scrolling pipeline, the crowd renderer and the sprite plan.

## Implementation and validation

- `src/CHOPLIFT.bas`: game logic, input, rendering and sound.
- `assets/generate.py`: art, world map and star table; writes `src/assets.bas`.
- `tools/check.py`: 73 tests that execute the BASIC routines and the TI assembly kernels in a
  strict interpreter, compare each kernel with its BASIC twin, and reject known-bad
  mutations. They cover rescue accounting, crowds, controls, pause, weapons, enemies, sprite
  priority, scrolling order, scenery, stars, sound envelopes, boarding, the threat ramp and
  crashes.
- `tools/build.py`: generation, tests and gates, compilation, assembly, branch shortening,
  budget and word-alignment checks, and cartridge packing.
- `tools/profile.py` and `tools/run-bench.ps1`: speed benchmarks (whole-loop, per-routine and
  stubbed variants) and a production-code review cart (`--review`, with `--calm` for no
  enemies). Benchmark carts look
  scrambled on screen by design.

Verified in Classic99 with the production code: scrolling over evacuating camps, tanks,
shells, crashes, and a whole group boarding together. Not yet verified: original hardware,
sound balance and a full 64-person playthrough.

## Design references

See [DESIGN.md](DESIGN.md). References include the
[Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057),
[Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121),
[single-button version comparison](https://www.atariprotos.com/other/gamediff/choplifter/choplifter.htm)
and the [C64 longplay](https://www.youtube.com/watch?v=wCrKd0fM1CY). The original game was
created by Dan Gorlin and published by Brøderbund. This implementation uses CVBasic by Oscar
Toledo G. and its TI support by Tursi.
