# Choplifter for the TI-99/4A

A playable CVBasic rescue game inspired by the original Choplifter: four prison camps, 64 people, a 16-seat helicopter, three lives, tanks, jets, and pursuing airborne mines. New game code and pixel art, with horizontal scrolling, animated rotors, sound effects, mission results, and a session best rescue count.

The primary cartridge is **[build/ti/CHOPLIFT_8.bin](build/ti/CHOPLIFT_8.bin)**. It is a 32 KB non-inverted banked TI cartridge and requires the **32 KB RAM expansion**. Load it in Classic99 or compatible TI cartridge hardware. A ColecoVision build is also available at `build/coleco/choplift.rom`.

## Play

| Control | Action |
|---|---|
| FIRE or `1` at the title | Start |
| Joystick 1 up/down | Climb/descend |
| Joystick 1 left/right | Fly and aim sideways |
| Release left/right | Brake, hover, and face forward |
| FIRE while hovering | Shoot down at barracks or tanks |
| FIRE while steering | Shoot sideways |
| `0` | Pause; `0` or FIRE resumes |

The supplied Classic99 input profile uses **arrow keys and Tab for joystick 1**. On real TI hardware, release ALPHA LOCK if it interferes with the joystick's vertical axis.

You start at home on the right. Fly left, shoot open a barrack, then land beside it. Stop and let the yellow people walk aboard. The cabin holds 16. Return to the right and land on the **H pad** to unload. Lift off with UP before trying to move sideways on the ground.

Do not land on people or fire through them. A crash loses everyone aboard. Tanks threaten low flight; jets cross the sky; after 32 rescues a pursuing drone can follow you home. Camp indicators change from a number to `o` when opened and `-` when emptied. The two helicopter icons are **spare lives**, excluding the helicopter being flown.

The mission ends when all 64 people are saved or lost, or the third helicopter is destroyed. A perfect rescue saves all 64. There is no fuel timer.

## Build

From this directory on the configured Windows development machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 All
powershell -NoProfile -ExecutionPolicy Bypass -File launch-ti.ps1
```

`build.ps1 TI` and `build.ps1 Coleco` select a single target. Cygwin users may run `bash build-ti.sh` or `bash build-coleco.sh`. All builds are sequential.

Dependencies: the **unhuman/CVBasic** fork (including its preprocessor and TI runtime), Python 3.10+, xdt99's `xas99.py`, and `linkticart.py`. Coleco additionally uses `gasm80`. Paths default to the repository's installed tools; override `CVBASIC_DIR`, `XDT99_DIR`, or `GASM80` as needed. On Windows, run the shell scripts with Cygwin, not Git Bash.

The launcher copies the established Classic99 input profile into `build/review` and opens a separate review session. It preserves pre-existing emulator sessions. To reload the session it created, pass `-ReviewProcessId` with the ID recorded in `build/review/process-id.txt`. It logs the exact ROM path and SHA256. Generated output and review captures stay under ignored `build/`.

## Implementation and validation

- `src/CHOPLIFT.bas`: game logic, input, rendering and sound.
- `assets/generate.py`: editable art and world-map generator; `src/assets.bas` is regenerated output.
- `tools/check.py`: 14 tests, including direct execution of the BASIC rescue, flight, and weapon routines. Tests cover 64-person conservation, capacity, pad bounds, crashes, landing casualties, all-64 completion, frame-delta movement, world boundaries, barrack/tank hits, HUD placement, and asset geometry. Deliberately broken accounting and HUD writes are rejected.
- `tools/build.py`: generation, repository truncation/GOSUB gates, compilation, assembly, size checks, and byte-for-byte packed data-bank verification. It checks the generated TI multiply stores the low word and reloads across the movement routine boundary.

| Target | ROM | Fixed code | Game variables |
|---|---:|---:|---:|
| TI-99/4A | 32,768 B | 11,754 / 24,336 B | 156 / 7,854 B |
| ColecoVision | 16,384 B | Unbanked | 148 / 814 B |

TI data bank: 1,770 / 8,190 bytes including bank setup overhead. The game uses no per-frame VDP reads and redraws only five terrain rows on camera changes.

Classic99 review verified title/start, takeoff, horizontal flight and scrolling, opening camps, visible walking/boarding passengers, enemy encounters, helicopter loss, reserve indicators, and the corrected HUD/pause display. A return-trip capture shows **14 saved and an empty cabin after unloading at home** (`build/return-check.png`). A complete uninterrupted 64-person mission, real-hardware speed, sound listening, and Coleco emulator play remain unverified. The rescue-state tests also exercise successful unloading and all-64 completion directly from the BASIC source.

## Design references

See [DESIGN.md](DESIGN.md) for performance decisions and deliberate adaptations. Historical mechanics were checked against the [Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057) and [Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121). The original game was created by Dan Gorlin and published by Brøderbund. This implementation uses CVBasic by Oscar Toledo G. and its TI support by Tursi.
