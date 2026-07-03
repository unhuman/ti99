# Games

Index of games in this repo. Each lives in `games/<name>/` and follows the structure and
lifecycle in `CLAUDE.md` §8. New games start from `templates/`.

| Game | Folder | Disk name | Status | Concept |
|------|--------|-----------|--------|---------|
| Dot Muncher | `games/dotmuncher/` | `MUNCH` | ✅ Toolchain validated (compiles + `-X` runs) | One-screen maze; eat every dot to win. Char-cell movement, no enemy. Proved the full XB256→compile→`-X` pipeline. |
| Ms. Pac-Man | `games/mspacman/` | `MSPAC` | 🔨 In development — **Step 3a** of 7 (see `games/mspacman/DESIGN.md` §12) | Full Ms. Pac-Man with sprites (MAGNIFY 3, LOCATE movement), 1-char walls, flicker rotation. Built incrementally. Replaces broken `mspacman-old/`. |

| Astiroids | `games/Astiroids/` | `ASTIROIDS` | 🎮 Playable — first version | Classic Asteroids. CVBasic, **dual-target**: TI-99/4A cartridge (`--ti994a` → `_8.bin`) **and** ColecoVision (`build-coleco.sh` → `.rom`, fits the 1KB RAM). 2× sprite magnification, 32-slot sprite pool (24 asteroid slots), 16-step ship rotation, inertial thrust + inertia-carrying bullets, UFO (large/small) with aiming, explosions, and a stall watchdog that brings saucers out faster, waves with free-flight gap, heartbeat sound, silent title with an `8 3 8` setup screen (pick ships + starting level), persistent session high score. |

### Planned / candidates
- **Text Adventure** — port of `Adventure-Java/` (string/stack-heavy; no sprites).
