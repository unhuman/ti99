# Choplifter — TI-99/4A / CVBasic

## Performance budget

- Real-time, frame-delta movement; one bounded update per actor per pass. No pathfinding, no VDP reads, no GCHAR/COINC. Target 30–60 updates/sec on the original 3 MHz TI.
- At most ten moving hardware sprites: two helicopter halves, one tank, one walking hostage, one jet, one drone, two player shots, one enemy shell, one explosion. CVBasic SPRITE replaces XB MOTION/LOCATE. The helicopter owns slots 0–1 and never participates in automatic flicker.
- Terrain scrolls in eight-pixel steps. Only the five scenery rows are copied from a literal ROM map (160 bytes per camera change). Sky, HUD and ground remain stationary. Collisions use world coordinates.
- One permanently selected TI data bank, less than 8 KB; code budget 24,336 bytes; reserve 1.2 KB for possible future music. No music player in this release. Coleco builds from the same source, with an 814-byte variable budget.

## Research and adaptation

Based on Dan Gorlin's original rescue game, rather than Sega's later arcade campaign. The [Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057) specifies 64 hostages, 16 passengers, three helicopters, separate lost/aboard/saved tallies, vulnerable people, and landing-pad unloading. The [Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121) describes four barracks and escalating tanks, jets and airborne mines.

This is new code and new pixel art, not a conversion of an original ROM. TI adaptations: a five-screen-wide world, eight-pixel scenery scrolling, automatic facing, one visible runner at a time, one tank/jet/drone at a time, and one-button directional fire. No fuel restriction. A perfect rescue is 64 saved; the mission ends when all people are accounted for or the third helicopter is lost.

## Play and accounting

Home is at the east (right) end. Four camps at world x=128,384,640,896 contain 16 people apiece. Shoot a barrack to open it. Land beside it and stop; people emerge individually and walk to the cabin. Capacity is 16. Fly home and land on the marked H pad to unload individually. People persist at their camps across trips and helicopter losses.

Saved + lost + aboard + all camp populations always equals 64. An active runner is included in its camp population until it boards or dies. Crashing loses everyone aboard, consumes one helicopter, and returns the next helicopter to home. The HUD shows reserves excluding the current helicopter, right justified. With no lives left, the unresolved people are shown as stranded on the result screen.

Joystick 1 controls flight. Releasing horizontal input brakes into a hover and turns the helicopter toward the player; FIRE then drops a shot downward. While steering left/right, FIRE shoots horizontally. Horizontal movement on the ground is disabled. Descending onto an exposed runner kills that person. Shots and enemy shells can kill the exposed runner. Tanks threaten low flight, jets threaten higher flight, and a pursuing drone enters after 32 rescues. Tanks and jets stay west of the border; drones may cross it. Home replenishes no lives.

The `0` key pauses play; `0` or FIRE resumes. Pause stops sounds and resets the elapsed-frame clock on resume. Tank travel is 15 pixels/second and drone vertical travel is 30 pixels/second at 60 Hz, using fractional accumulators so a slower loop does not freeze them. Horizontal helicopter acceleration/braking is per update, with cruising movement driven by elapsed frames.

## Display and sound

256×192 TMS9918 display. Rows 0–1 are HUD, rows 2–16 sky, rows 17–21 scrollable scenery, row 22 ground and row 23 instructions/status. Ground contact is helicopter top y=152, runner y=160, tank y=156. Two 16×16 white sprites form a 32×16 helicopter with two rotor beats in left/right/front views. Other actors have one 16×16 sprite each; the runner has an 8×8 silhouette within it. The helicopter remains visible when the hardware's four-sprites-per-line limit is reached; lower-priority effects can disappear on congested lines.

Sound uses a quiet rotor pulse, gunfire, boarding/unloading chirps and explosions. Every effect has a frame-based timeout and every screen transition explicitly silences all four channels. No latched background music.

## Source and validation

`src/CHOPLIFT.bas` owns the game. `assets/generate.py` owns art and scenery and emits `src/assets.bas`. Build scripts regenerate before compiling, run the repository truncation and GOSUB gates, check source contracts and asset geometry, assemble, check fixed/bank sizes, and verify the packed data bank. The TI uses the unhuman/CVBasic fork, xdt99 and linkticart. All builds are sequential.

Runtime review verified a rescue-and-return trip with 14 saved and an empty cabin, plus camp opening, boarding, flight, enemy encounters, death/reserves, and pause. Fourteen regression tests pass. Fixed TI code is 11,754 / 24,336 bytes; the data bank uses 1,770 / 8,190 bytes. Game variables occupy 156 TI bytes and 148 Coleco bytes. Remaining verification limits are recorded in README.md.
