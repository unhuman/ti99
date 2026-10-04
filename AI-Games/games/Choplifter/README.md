# Choplifter for the TI-99/4A

A playable CVBasic rescue game inspired by the original Choplifter: four prison camps, 64 people, a 16-seat helicopter, three lives, tanks, jets, and pursuing airborne mines. New game code and pixel art, with horizontal scrolling, animated rotors, sound effects, mission results, and a session best rescue count.

The primary cartridge is **[build/ti/CHOPLIFT_8.bin](build/ti/CHOPLIFT_8.bin)**. It is a 32 KB non-inverted banked TI cartridge and requires the **32 KB RAM expansion**. Load it in Classic99 or compatible TI cartridge hardware. A ColecoVision build is also available at `build/coleco/choplift.rom`.

## Play

| Control | Action |
|---|---|
| FIRE or `1` at the title | Start |
| Joystick 1 up/down | Climb/descend; holding DOWN builds descent speed |
| Release DOWN | Stop descending; use short presses for a soft landing |
| Joystick 1 left/right | Fly sideways; facing stays independent |
| Release left/right | Brake into a hover, keeping your aim |
| Tap FIRE in flight | Fire on release: sideways when facing left/right, bomb when facing front |
| Hold FIRE | Hold 0.5 seconds to turn; continue holding to turn every 0.3 seconds |
| Hold `P` on TI / `0` on Coleco | Pause after 0.2 seconds; same key or FIRE resumes |

The supplied Classic99 input profile uses **arrow keys and Tab for joystick 1**. On real TI hardware, release ALPHA LOCK if it interferes with the joystick's vertical axis.

You start at home on the right. Fly left and shoot open a barrack. Its roof burns while the sixteen people steadily escape and spread out on both sides, even while you are away or your cabin is full. People have three appearances, varied walking speeds, and individually phased walking and waving poses. Land beside a waiting group and stop to let them board. The cabin holds 16. Return to the right and land on the **H pad**: passengers step out individually and walk into the post office. Lift off with UP before trying to move sideways on the ground.

The helicopter starts facing left. Hold FIRE for half a second to face front for bombing; keep holding to face right. Shorter presses fire on release without turning. FIRE is sampled every video interrupt and taps are latched across slower game updates. Turning does not also fire. Bombs inherit your sideways speed at release and keep drifting that way if you stop or reverse; hovering drops fall straight down. It banks in the direction of travel, including backward flight, and sideways shots follow that pitch. Both the main and tail rotors animate; the tail alternates cross and diagonal blades in mirrored and banked side views. Off-screen shots expire so they cannot occupy the weapon slots indefinitely. The helicopter and its shots have priority under the TI's four-sprites-per-scanline limit.

Weapons are disabled on the ground. Holding DOWN accelerates descent; a fast touchdown crashes the helicopter and loses its passengers. Release DOWN to brake into a hover, then use short downward presses to land softly. Landing on a person plays a brief squish sound.

A destroyed helicopter catches fire and falls while keeping its sideways momentum. It hits the ground, burns for 1.5 seconds, then disappears into low embers before the next helicopter launches or the mission ends. Impact bursts and fire crackle accompany the animation. Flying, firing, and turning stay disabled during the crash.

Do not land on people or fire through them. A crash loses everyone aboard. Tanks threaten low flight. Jets unlock only after your first nonempty collection has left the cabin and every walker has entered the post office; each makes three passes with two broad banking turns and carries two missiles. After the second completed delivery, a pursuing drone can follow you home. A low, wide post office with a roof-mounted waving flag marks home. The **320-pixel demilitarized zone** separates it from enemy territory. Two boundary fences extend into the foreground; their posts and rails stay connected as perspective changes. Camp indicators change from a number to `o` when opened and `-` when emptied. The two helicopter icons are **spare lives**, excluding the helicopter being flown.

The mission ends when all 64 people are saved or lost, or the third helicopter is destroyed. A perfect rescue saves all 64. There is no fuel timer.

For practice, type **838** at the title, then choose **1–9 helicopters**; `0` cancels. The selected number includes the helicopter in play. Practice saved counts carry a small asterisk, including games started with three helicopters. The best rescue count keeps its own marker, and an unmarked run wins a tie. Normal starts still use three helicopters.

Tanks have a larger 32-pixel hull and left, right, and front views aimed toward your helicopter. Shots use swept bounds against tanks and aircraft, including bombs crossing the ground between updates. A shot stops at its first destroyed target.

Main and tail rotors now change pose every four video frames, twice the previous rate when the loop keeps up. Sound includes an idling engine, stronger airborne blade pulses, gunshot and falling-bomb sweeps, distinct boarding/unloading chirps, a completed-delivery chime, nearby jets and drones, tank cannon fire, missile launches, and fading explosions. Weapons take priority over aircraft sounds; pause and screen changes silence every channel.

The sparse star field scrolls in three depth bands: upper stars at one-eighth of terrain speed, middle stars at one-quarter, and lower stars at three-eighths. The ground extends to the bottom of the display, replacing the old instruction/status strip. Pause is indicated in the top HUD.

## Build

From `AI-Games/games/Choplifter/` on the configured Windows development machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 All
powershell -NoProfile -ExecutionPolicy Bypass -File launch-ti.ps1
```

`build.ps1 TI` and `build.ps1 Coleco` select a single target. Cygwin users may run `bash build-ti.sh` or `bash build-coleco.sh`. All builds are sequential.

Dependencies: the **unhuman/CVBasic** fork (including its preprocessor and TI runtime), Python 3.10+, xdt99's `xas99.py`, and `linkticart.py`. Coleco additionally uses `gasm80`. Paths default to the repository's installed tools; override `CVBASIC_DIR`, `XDT99_DIR`, or `GASM80` as needed. On Windows, run the shell scripts with Cygwin, not Git Bash.

The launcher copies the established Classic99 input profile into `build/review` and opens a separate review session. It preserves pre-existing emulator sessions. To reload the session it created, pass `-ReviewProcessId` with the ID recorded in `build/review/process-id.txt`. It logs the exact ROM path and SHA256. Generated output and review captures stay under ignored `build/`. To stop Classic99 audio logging, open the debugger (Ctrl+Home) and uncheck **Debug > Log Audio**; logging survives a reset.

## Implementation and validation

- `src/CHOPLIFT.bas`: game logic, input, rendering and sound.
- Escaping, waiting, and homeward-walking people use animated background characters, so a whole crowd remains visible without extra hardware sprites. Settled people use prebuilt poses; moving crowds use a double-buffered compositor. Scrolling leaves the visible crowd row intact until its replacement is ready. Off-screen camps are culled before drawing, and settled camps skip walking updates. Overlapping silhouettes are combined without erasing each other, and office scenery is preserved behind walkers. An eight-pixel character cell shares one palette. The person approaching the cabin uses a matching runner sprite. People remain individually tracked and vulnerable to shots and unsafe landings before rescue.
- `assets/generate.py`: editable art and world-map generator; `src/assets.bas` is regenerated output.
- `tools/check.py`: 60 tests execute BASIC routines for rescue accounting, crowd evacuation/compositing, individual pace, office entry, flight, single-button controls, pause debounce, projectile retirement, bomb momentum and sprite priority, jet unlocking/turns/missiles, perspective clipping, roof/flag attachment, HUD placement, asset/rotor geometry, sound envelopes/shutdown, 838 choices and marked-score ties, tank views, swept projectile bounds, grounded weapons, hard/soft landings, squish triggers, star parallax, the expanded ground, and burning crashes through ground impact and burnout. Known-bad accounting, HUD, pause, weapon cleanup, sprite priority, jet-gate, crowd, character-allocation, map-stride and crash-sequence mutations are detected.
- `tools/profile.py`: builds a separate TI scrolling benchmark (32 updates per scenario), leaving production sources untouched. Run with Cygwin Python and use a separate Classic99 instance; restore the normal cart after review.
- `tools/build.py`: generation, repository truncation/GOSUB gates, compilation, assembly, size checks, and byte-for-byte packed data-bank verification. It checks the generated TI multiply stores the low word and reloads across the movement routine boundary.

| Target | ROM | Fixed code | Game variables |
|---|---:|---:|---:|
| TI-99/4A | 32,768 B | 23,910 / 24,336 B | 838 / 7,854 B |
| ColecoVision | 24,576 B | Unbanked | 813 / 814 B |

Both builds pass all 60 tests and the repository checks. Classic99 review also verifies 838 entry, the nine-helicopter selection with eight spare icons, the saved-count asterisk, and the enlarged tank in all three views. Additional Classic99 captures verify star scrolling, the deeper ground and HUD pause label, a hard-landing life loss, and a helicopter-contact casualty. Crash captures in `build/review-crash/` verify the airborne fire, ground burn, embers, and last-life results screen; the production cartridge was restored immediately. A production hard-landing check also verifies the next helicopter respawning at home with one reserve remaining. Sound pitch/envelope and shutdown checks pass; final sound balance has not been auditioned.

TI data bank: 7,978 / 8,190 bytes including bank setup overhead and the results-screen code. This bank stays selected throughout play. The crash uses four hardware sprites and no additional RAM. The game uses no per-frame VDP reads. Camera changes first prepare the crowd row without moving the houses. After WAIT, three scenery rows and the crowd row are copied consecutively; ground, fence, flag and fire overlays follow. This keeps house roofs and their ground-level walls at the same camera position. A scrolling update can wait up to one video frame to synchronize; stationary crowd redraws do not add this wait.

Classic99 review captures show varied evacuees around a burning camp, passengers stepping out toward the office, and a complete 16-person delivery with no walkers remaining outside. The normal cartridge was restored immediately after each separate review-cart capture. Other captures verify the revised post office, roof-mounted flag, home boundary fence, title, turning/banking and P pause display. A complete uninterrupted 64-person mission, real-hardware speed, sound listening, and Coleco emulator play remain unverified. The source-level tests exercise all-64 completion and the crowd/combat/control behavior. The capture helper accepts `-ReleaseControls` and `-RefocusSteps` for controlled review sequences; it checks the explicitly selected window before each step.

## Design references

See [DESIGN.md](DESIGN.md) for performance decisions and deliberate adaptations. References include the [Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057), [Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121), [single-button version comparison](https://www.atariprotos.com/other/gamediff/choplifter/choplifter.htm), and the supplied [C64 longplay](https://www.youtube.com/watch?v=wCrKd0fM1CY), inspected as extracted frame sequences. The original game was created by Dan Gorlin and published by Brøderbund. This implementation uses CVBasic by Oscar Toledo G. and its TI support by Tursi.

## Performance pass (2026-10-03)

Classic99 at Normal CPU speed measured the same 32-update scrolling workload before and after this pass:

| Scene | Before (video frames) | After | Speedup |
|---|---:|---:|---:|
| No exposed people | 225 | 94 | 2.4× |
| 64 waiting people off-screen | 329 | 104 | 3.2× |
| Flying past waiting crowds | 728 | 177 | 4.1× |

These measure people, camera, crowd and sprite processing, not full-game FPS. Original hardware and Coleco gameplay timing remain unmeasured. The TI has small assembly kernels for copying, combining pixels and scanning waiting people; tests execute those instructions and compare the waiting renderer with the portable CVBasic path. Double-buffer and terrain-order mutations must fail. The render path no longer blanks the crowd row during scrolling, and FIRE timing no longer depends on the main-loop update rate.

Final TI review: `build/perf/verified-tap.png` captures a 90 ms tap producing a shot without turning. Desktop captures could show only repainted regions; `tools/capture.ps1` now invalidates the full client region and requests a complete image with PrintWindow (Classic99 DIB mode), with desktop capture as a fallback. The running review uses DIB mode. Audio logging was explicitly verified off.

## Scrolling and touchdown correction (2026-10-03)

House roofs and their ground-level walls now wait for crowd composition to finish, then update together after a video-frame boundary. The helicopter lands one pixel lower: its existing skid art ends directly above the ground, with no empty pixel between them. The helicopter artwork is unchanged. Both target builds pass 57 tests, including both scroll directions with empty, waiting, and moving crowds and skid geometry for all six landed poses.

The Windows sandbox created a separate desktop: a Classic99 process there could load the cartridge but was not the user's visible review window. Launching and capturing outside the sandbox reached the interactive desktop. The old isolated process was closed, the production game was verified running, and the user confirmed improved scrolling. Run the project launcher/capture tools on the interactive desktop for future reviews. Audio logging is explicitly checked off.

Landing-pad rendering also preserves the white markings and black apron as the nearby fence changes perspective. Empty fence tiles are transparent; the one post tile crossing the pad is precomposed with the underlying markings. A pixel-level regression sweeps both scrolling directions and rejects both the old opaque stamp and missing pad composition.
