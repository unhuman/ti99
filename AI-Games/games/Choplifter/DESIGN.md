# Choplifter — TI-99/4A / CVBasic

Current-state design. History is in git; numbers below are from the latest build and
benchmark run (2026-10-06).

## Performance budget

- **Loop.** Real time, frame-delta pacing: `dt` is the number of video frames since the last
  update, clamped to 6. Updates run at most every 2 frames (30/s); an update that already
  took 2 or more frames starts the next one immediately (`main_loop`), so the only idle wait
  is the scroll synchronisation below. At 6 frames per update the game still runs at true
  speed, just in coarser steps; beyond that it slows down.
- **Measured rates** (Classic99 Normal speed, `tools/profile.py` full-loop cases, video
  frames per 32 updates → updates per second):

  | Situation | Original | Now |
  |---|---:|---:|
  | Cruising over open terrain | 160 (12/s) | 96 (**20/s**) |
  | Over a settled crowd with tank, jet, drone and shots | 256 (7.5/s) | 152 (**12.6/s**) |
  | Two camps evacuating at once (32 walkers in view) | 380 (5/s) | 191 (**10/s**) |

- **Cost model.** One video frame buys only about 1,300–1,500 instructions of compiled
  CVBasic (code runs from the 8-bit 32K expansion). Per-call costs from
  `profile.py --micro`, in frames: stars 0.48, terrain rows and overlays near open camps
  0.66, settled crowd row 1.0, moving-crowd compositor with 32 walkers 3.25, walker logic
  for 32 walkers 1.56, sprites with every actor on 0.78 / all off 0.34, enemies and weapons
  0.53, sound + rotor + pause input + flight 0.34. A scrolling update costs whole frames:
  its synchronised WAIT rounds the work up.
- **Hardware sprites.** At most 12 world sprites; slot map in *Sprites* below. No automatic
  flicker: the helicopter is pinned to slots 0–1, anything that can destroy it comes next,
  and the remaining ground and air actors rotate (software flicker).
- **VDP work per scrolling update.** One WAIT, then rows 17–20 (128 bytes, back to back),
  then flag/fire/door overlays, then rows 21–22 (64 bytes) and the fence stamps. Row 23 is
  static. Stars write 14–28 cells, and none while the camera is still. No VDP reads, no
  GCHAR, no COINC; collisions use world coordinates.
- **TI native kernels** (each with a portable BASIC twin used by ColecoVision and tested
  against it): star field, crowd walking, moving-crowd compositor, crowd colour upload,
  settled-crowd scan and row copy. See *TI native kernels*.

## Size budget

| | Used | Limit | Notes |
|---|---:|---:|---|
| TI fixed area (after short branches) | 21,852 | 24,336 | 2,484 free |
| TI fixed area, unoptimised | 23,492 | 24,574 | xas99's first pass must stay below >FFFE |
| TI data bank | 8,044 | 8,190 | assets, menu font, results screen |
| TI RAM | 810 | 7,854 | |
| ColecoVision RAM | 809 | 814 | nearly full; see `#vaddr` |

`tools/build.py` runs Keystone Kapers' verified `shortbranches.py` (about 410 branches,
1.6 KB saved) and fails if the unoptimised image reaches >FFFE, because that pass cannot run
then. Grow the unoptimised figure carefully; bank cold code (title, setup) if it gets tight.
The menu font lives in the data bank; its colour table (all white on black) is filled at run
time from the idle crowd pixel buffer instead of 256 identical ROM bytes. ColecoVision RAM
is the tightest budget: `#vaddr` is one shared VPOKE address used by every routine that
computes an address and writes it immediately, never across a GOSUB.

## Research and adaptation

Based on Dan Gorlin's original rescue game, rather than Sega's later arcade campaign. The
[Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057) specifies 64
hostages, 16 passengers, three helicopters, separate lost/aboard/saved tallies, vulnerable
people and landing-pad unloading. The
[Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121) describes four
barracks and escalating tanks, jets and airborne mines. The
[Atari version comparison](https://www.atariprotos.com/other/gamediff/choplifter/choplifter.htm)
distinguishes Apple's two-button controls from Atari's hold-to-turn adaptation;
[gameplay notes](https://strategywiki.org/wiki/Choplifter!/Gameplay) describe tap fire, hold
rotate, jets after a delivery and later airborne mines. The user's
[C64 longplay](https://www.youtube.com/watch?v=wCrKd0fM1CY) was inspected as frame sheets in
the ignored `build/reference`: around 75–85 s the first group unloads beside the flag; around
87–98 s jets approach head-on and turn into side-on firing passes; the footage shows
front/side helicopter poses and pronounced pitch in travel. Reference material is not a
build dependency.

This is new code and new pixel art, not a conversion. TI adaptations: an eight-screen world,
eight-pixel scenery scrolling, character-composited crowds with one boarding-runner sprite,
one tank, jet and drone at a time, a single fire/turn button and no fuel limit. The jets'
bounded three-pass route is an adaptation, not a claim of identical original AI.

## Play and accounting

The world is 2,048 pixels wide. Home is at the east end: the helicopter spawns at x=1920,
lands on the pad at 1896 < x < 1953, and unloads beside an 80×16 post office (x=1960–2039)
with a roof-mounted flag at x=2016. A 320-pixel demilitarised zone (DMZ) spans x=1568–1888
between two boundary fences. Four camps at x=128, 384, 640 and 896 hold 16 people each; the
nearest camp's outer wall is 648 pixels from the enemy-side fence.

Bombing a barrack opens it and sets its roof burning. It releases one person every 24 video
frames, whatever the helicopter is doing. People walk out in two groups of eight to waiting
spots 8 pixels apart, up to 88 pixels from the camp, farthest spots first. Land beside a
group and stop: the nearest waiting person approaches as the runner sprite. The cabin holds
16. Land on the pad at home to unload people one at a time; each walks to the office door
and counts as saved on leaving the cabin.

Saved + lost + aboard + everyone still at the camps always equals 64; the runner counts with
its camp until it boards or dies. A crash loses everyone aboard and one helicopter; the next
starts at home. The HUD shows spare helicopters (excluding the one flying), right-justified;
camp indicators change from a number to `o` when opened and `-` when emptied. The mission
ends when all 64 are saved or lost, or the last helicopter is destroyed; the results screen
lists saved, lost, stranded and the session's best rescue. A perfect rescue is 64.

People persist across trips and crashes. Landing on a runner or an exposed person kills them;
so do player shots, tank shells and jet missiles. Lost people never return or count twice.

## Controls and flight

Joystick 1 flies independently of facing; the helicopter starts facing left. Releasing
horizontal input brakes to a hover without changing aim. Horizontal acceleration and braking
step once per update (0–3 px/frame); cruising distance follows elapsed frames.

FIRE is sampled every video frame by an `ON FRAME` handler, so taps survive slow updates: a
press shorter than 30 frames (0.5 s) fires on release; holding turns after 30 frames and
then every 18, cycling left → front → right → front. Releasing after a turn does not fire.
Side views shoot in the facing direction and follow the nose pitch; the front view drops
bombs that keep the helicopter's sideways speed at release. Shots expire after 90 frames or
on leaving the view; old shots retire before a new tap is accepted. Weapons are disabled on
the ground, and so is sideways flight: lift off with UP first. Menus, pause and respawn gate
the sampler and discard stale presses.

Holding DOWN descends at 1 px/frame, speeding up every 24 held frames to 3 px/frame;
releasing DOWN brakes to a hover. Touching down faster than 1 px/frame crashes, even during
spawn invulnerability; short taps land safely. Holding P (TI) or keypad 0 (ColecoVision) for
12 frames pauses; the same key or FIRE resumes. Pause silences sound and resets the frame
clock.

A destroyed helicopter catches fire and falls at 2 px/frame, keeping its sideways speed. It
burns for 90 frames on the ground (the last 24 as low embers), then the next helicopter
launches or the mission ends. Lives and passengers are charged once, at the hit. The crash
uses sprite slots 0–3 only (flames ahead of the grey hull) with every other sprite hidden.

## Enemies

All enemy activity and border checks use the DMZ fence, x=1568.

- **Tank.** One at a time, 32×16 pixels with left, right and front views; it appears 2.5 s
  after the helicopter crosses west of the fence and crawls toward it at 15 px/s, never
  past the fence. It fires one shell every 140 frames (100 once 16 people are saved) when the
  helicopter is within 220 pixels. Shells fly 2 px/frame sideways and rise 1 px/frame, or fly
  flat when the helicopter is low (y > 130). **When the helicopter is overhead the turret
  shows its front view and the shell goes straight up from its centre at 2 px/frame**, so
  hovering above a tank is not safe. Contact with the hull crashes the helicopter.
- **Jets.** Enabled after the first completed delivery (every walker has entered the office).
  A launch countdown of 6 s, then three passes at 120 px/s joined by two 48-frame banking
  turns, all west of the fence. The first pass scouts; then it can fire two aimed missiles,
  one at a time (3 px/frame, retiring after 90 frames or at the sky, ground or fence). After
  its last pass a departing jet retires as soon as it is wholly off camera, so the gap before
  the next jet does not depend on how far west the world extends.
- **Drone.** Enabled after the second completed delivery. It enters at the fence, chases the
  helicopter (60 px/s sideways, 30 px/s vertically) and may cross the DMZ to home.

## Display

256×192 TMS9918 screen. Rows 0–1 HUD (PAUSED replaces SPARES while paused), rows 2–16 sky,
rows 17–21 scenery (row 20 is the crowd row), rows 22–23 ground. Ground contact: helicopter
top y=153 (its lowest ink at y=167 touches ground row 21 at y=168), runner y=160, tank 156.

**Scrolling.** The camera moves in 8-pixel steps. A scroll update composes the crowd row
first (without touching the visible one), then `crowd_commit` WAITs for vblank and copies
rows 17–19 and the crowd row back to back, so roofs and their footings always share a camera
position. The flag, camp fires and open doors (rows 17–19) are written immediately after, ahead
of the ground rows and fences, so they land before the beam reaches them; otherwise a
burning camp shows its closed roof and door for a frame after each scroll. Then rows 21–22
are copied and the fence stamps drawn. Row 23 is drawn once by `game_screen`.

**Stars.** Fourteen stars, one per sky row 3–16, in three parallax bands: rows 3–6 move 1,
rows 7–11 2 and rows 12–16 3 pixels per 8-pixel camera step, wrapping at the screen edges.
Characters 240–255 hold eight sub-cell phases in two shapes. Each star is redrawn in one pass
and its old cell cleared only when it has left it; because each star owns its row, that
never erases another star. `star_row` ends with row 0, so the star list can change length.

**Fences, pad, office and flag.** Each fence is a clipped 5×2 perspective stamp from the
horizon (row 21) into the foreground (row 22) whose near end leans away from the screen
centre; empty stamp cells are transparent, and the one cell crossing the landing pad is
precomposed with the pad marking (character 120). The flag waves by redefining two
characters every 16 frames.

**Crowds (characters, not sprites).** All 64 people are background characters in row 20, so
a whole crowd costs no sprite slots; only the runner is a sprite.
- *Appearance.* Three looks by `id % 3`; poses `(anim/8 + id) AND 3`, so neighbours are out of
  step; walking speeds of 60, 48 or 40 px/s from a stride of 4, 5 or 6 frames per 4-pixel
  step, with each person's step clock offset by its id (one shared clock, no per-person
  timers).
- *Settled crowds.* A camp with no walkers has everyone on world-aligned spots 8 pixels apart,
  so each person owns a cell: 24 prebuilt standing characters (3 looks × 4 poses × black or
  blue paper) are written straight into the name row.
- *Moving crowds.* Camps with walkers, and homeward walkers near the office, go through the
  compositor. A person sits on a 4-pixel grid, so they fill one cell or straddle two. ROM
  holds pre-shifted copies of every pose (unshifted, and the two halves of a 4-pixel shift).
  A 256-byte RAM buffer holds the row's pixels; the first person in a cell copies in the
  scenery pattern beneath it, then every silhouette touching the cell is ORed in, so
  overlapping people merge. Each 8-pixel cell has one palette (a TMS9918 limit): the first
  person's look, except that office wall, window and door cells keep their own. Patterns and
  colours upload to the hidden half of a double-buffered character set (codes 0–31 or 64–95
  in the bottom screen third), then one name-row copy switches over.
- Settled camps stay on the cheap path even while a neighbour evacuates: crowds of different
  camps are at least 64 pixels apart and never share a cell.

**Sprites.** Two 16×16 sprites make the 32×16 helicopter, in left, right and front views
with two rotor beats each and level or banked poses; side views alternate cross and diagonal
tail-rotor blades. Main and tail rotors share a four-frame beat that never skips both poses on
a slow update. There are 64 sprite patterns; 13–14 are the crash flames. Slots (the VDP draws
4 per scanline, lowest first):

| Slots | Owner |
|---|---|
| 0–1 | helicopter (pinned) |
| 2 | tank shell |
| 3 | jet missile |
| 4–5 | player shots |
| 6–11 | tank left/right, runner, jet, drone, explosion — rotating |

On the ground beside a tank there are six sprites for four places. Keeping the shell and
missile right after the helicopter means a projectile that can destroy it is never the one
dropped (it used to be: the shell was invisible exactly when it was about to hit). The
rotating block takes its order from `rot_map`, which changes every update and reverses on
alternate updates, so on a crowded line the tank halves and runner take turns (flicker)
instead of one vanishing; lines with four or fewer sprites never flicker. `#sprite_shown`
has one bit per slot so an inactive actor's slot is hidden once and then costs a bit test.

## Sound

Channel 0 carries the engine: quiet idle on the pad, stronger alternating airborne pulses and
a higher pitch under horizontal load. Channel 1 plays a short gun sweep or a longer falling
bomb whistle; when free it carries a nearby jet's distance-dependent tone or the drone's
alternating warning. Channel 2 carries rising boarding and falling unloading chirps and a
three-note delivery chime. Channel 3 carries periodic rotor noise, overridden by tank fire,
missile launches, explosions (which win over launches) and an eight-frame squish when the
helicopter lands on a person. Effects expire on frame deltas; pause, new helicopters, the
title and the results silence all four channels and clear effect state. No music player.

## Practice setup

The hidden title sequence 838 opens a 1–9 helicopter prompt (0 cancels); normal games use
three. Practice saved counts carry a small asterisk (character 60) and the best rescue keeps
its marker; an unmarked run wins a tie. Up to eight spare icons fit beside SPARES.

## TI native kernels

Each kernel is inline `ASM` inside a BASIC routine, with the BASIC original kept as the
ColecoVision path:

| Routine | Work |
|---|---|
| `stars_draw` | the star field, one pass per star |
| `walk_camp` | one camp's escaping and homeward walkers (same stride DIVs as `person_stride`) |
| `compose_block` | one camp's people into the crowd pixel buffer (`crowd_plot`/`crowd_cell`) |
| `crowd_draw` | clearing the cell map and uploading cell palettes |
| `waiting_scan`, `waiting_draw` | settled people and the scenery row copy |

Rules they follow: registers r0–r9 only (r10 is CVBasic's stack; r11 is used only for a local
`bl`); the vblank handler has its own workspace, so registers survive interrupts; every VDP
address-and-data write is wrapped in `limi 0`/`limi 2`, as the runtime's `WRTVRM` does, so the
handler cannot move the address between the two halves; and a kernel ends in `RETURN` or is
followed by statements that reload what they use, because inline `ASM` does not invalidate
the compiler's register cache (checked in the generated assembly).

## Source, tools and validation

- `src/CHOPLIFT.bas` — the game. `assets/generate.py` owns art, the world map and the star
  table and writes `src/assets.bas` (all banked data, including the menu font).
- `tools/build.py` — generation, the 69 source-executing tests (once per `build.ps1 All`),
  the repository truncation and GOSUB gates, compilation, assembly, the short-branch pass with
  its verification, budget checks, an even-address check on every indexed word table (from
  xas99's symbol file: a label alone on its line before a padded `DATA` keeps an odd address
  that the listing hides), packing, and assembly assertions.
- `tools/check.py` — a strict interpreter that executes the game's BASIC routines and its TI
  kernels (registers, status flags, `DIV`, local `bl`, memory writes and the VDP ports, which
  must be written with interrupts off). Unknown statements and instructions are errors.
  Native kernels are compared with their portable twins over sweeps and randomised scenes,
  and known-bad mutations of every kernel must fail.
- `tools/profile.py` — benchmark carts: full-loop and component cases, `--micro` per-routine
  costs, `--stub ROUTINE` to attribute cost, and `--review` for a production-code cart that
  starts airborne over evacuating camps. Benchmarks call routines out of context and look
  scrambled on screen; use `--review` to judge rendering.
- `tools/run-bench.ps1` — runs a benchmark cart in its own Classic99, starts it (title key,
  then 2) and captures the finished screen. `tools/capture.ps1` screenshots and drives a
  specific Classic99 process. `launch-ti.ps1` opens a separate review session of the
  production cart.

Verified in Classic99: the production review cart scrolling over two evacuating camps with a
tank, shells and crashes (clean rendering, overlays in place), and every benchmark case. The
ColecoVision build has been booted and flown briefly in CoolCV. Not verified: original
hardware, sound balance and a complete 64-person mission played through.
