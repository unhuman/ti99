# Games

Index of games in this repo. Each lives in `games/<name>/` and follows the structure and
lifecycle in `CLAUDE.md` §8. New games start from `templates/`.

| Game | Folder | Disk name | Status | Concept |
|------|--------|-----------|--------|---------|
| Dot Muncher | `games/dotmuncher/` | `MUNCH` | ✅ Toolchain validated (compiles + `-X` runs) | One-screen maze; eat every dot to win. Char-cell movement, no enemy. Proved the full XB256→compile→`-X` pipeline. |
| Ms. Pac-Man | `games/mspacman/` | `MSPAC` | 🔨 In development — **Step 3a** of 7 (see `games/mspacman/DESIGN.md` §12) | Full Ms. Pac-Man with sprites (MAGNIFY 3, LOCATE movement), 1-char walls, flicker rotation. Built incrementally. Replaces broken `mspacman-old/`. |
| Ms. Pac-Man (CVBasic) | `games/mspacman-cv-xb-port/` | `MSPAC` | 🎮 **Dual-target** (TI runtime-tested; Coleco needs emulator pass) | CVBasic 1-shot port of the XB256 game. One source builds for TI-99/4A (`--ti994a` → `_8.bin`) **and** ColecoVision (`build-coleco.sh` → `mspac.rom`, fits the 1 KB RAM by reading the maze from VRAM with `VPEEK` — no RAM mirror). Full mazes, ghost AI, fruit, per-maze colours, 8-3-8 cheat. |

| Adventire | `games/Adventire/` | `ADVENTIRE` | 🎮 Playable — first version (compiles for both targets; needs emulator gameplay pass) | Atari-2600-*Adventure*-style quest (original code/art/maps). CVBasic, **dual-target**: TI-99/4A cartridge (`build-ti.sh` → `adventire_8.bin`) **and** ColecoVision (`build-coleco.sh` → `adventire.rom`). **Four games** (title select): the original 13-room intro map, plus a 26-room kingdom adapted from the documented 2600 structure — small kingdom (2 castles/2 dragons), full kingdom (3 castles, dark fog-of-war mazes, magnet, bat, invisible-dot **secret room**), and a randomized variant. Key-locked castles, fast red dragon, thieving bat, walk-through-walls bridge, grab-offset carrying, black castle on gray, swallow/win → title with full reset. 2× sprite magnification (32×32 dragons/bridge), 30 Hz loop, RAM-bitmap collision + ROM-resident room/link tables. |
| Astiroids | `games/Astiroids/` | `ASTIROIDS` | 🎮 Playable — first version | Classic Asteroids. CVBasic, **dual-target**: TI-99/4A cartridge (`--ti994a` → `_8.bin`) **and** ColecoVision (`build-coleco.sh` → `.rom`, fits the 1KB RAM). 2× sprite magnification, 32-slot sprite pool (24 asteroid slots), 16-step ship rotation, inertial thrust + inertia-carrying bullets, UFO (large/small) with aiming, explosions, and a stall watchdog that brings saucers out faster, waves with free-flight gap, heartbeat sound, silent title with an `8 3 8` setup screen (pick ships + starting level), persistent session high score. |

### Planned / candidates
- **Text Adventure** — port of `Adventure-Java/` (string/stack-heavy; no sprites).
