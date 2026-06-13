# Games

Index of games in this repo. Each lives in `games/<name>/` and follows the structure and
lifecycle in `CLAUDE.md` §8. New games start from `templates/`.

| Game | Folder | Disk name | Status | Concept |
|------|--------|-----------|--------|---------|
| Dot Muncher | `games/dotmuncher/` | `MUNCH` | ✅ Toolchain validated (compiles + `-X` runs) | One-screen maze; eat every dot to win. Char-cell movement, no enemy. Proved the full XB256→compile→`-X` pipeline. |
| Ms. Pac-Man | `games/mspacman/` | `MSPAC` | 🔨 In development — **Step 2** of 7 (see `games/mspacman/DESIGN.md` §12) | Full Ms. Pac-Man with sprites (MAGNIFY 3, LOCATE movement), 1-char walls, flicker rotation. Built incrementally. Replaces broken `mspacman-old/`. |

### Planned / candidates
- **Text Adventure** — port of `Adventure-Java/` (string/stack-heavy; no sprites).
