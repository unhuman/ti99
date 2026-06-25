---
name: build-cvbasic-game
description: >-
  Build a CVBasic (nanochess) game for the TI-99/4A: compile a .bas source with
  cvbasic, assemble the .a99 with xas99, and pack a loadable cartridge .bin with
  linkticart. Use whenever asked to build/compile/assemble a CVBasic game, produce
  a cart ROM, or check that a .bas still compiles.
---

# Build a CVBasic game (TI-99/4A)

Turns a CVBasic `.bas` source into a cartridge ROM (`<name>_8.bin`) that loads in
Classic99 or js99er. Three stages: **cvbasic compile → xas99 assemble → linkticart pack**.

## Quick start

```bash
bash .claude/skills/build-cvbasic-game/build.sh <path/to/game.bas> ["CART NAME"]
```

Example:

```bash
bash .claude/skills/build-cvbasic-game/build.sh games/mspacman-cv-xb-port/src/mspac.bas "MS PACMAN"
```

The script derives the program name from the `.bas`, runs all three stages in the
source directory, checks each output is non-empty, and prints the final
`<name>_8.bin` path. `CART NAME` (the TI menu label, ≤20 chars, uppercase) defaults
to the uppercased program name.

## Toolchain (this machine)

The script uses these locations; override with env vars (`CVBASIC_DIR`, `XDT99_DIR`)
if they move:

- **CVBasic** (nanochess): `C:\Users\Howie\github.git\nanochess\CVBasic`
  — needs `cvbasic.exe` + `linkticart.py` + the `cvbasic_9900_prologue.asm` / `_epilogue.asm`.
- **xdt99** (xas99 assembler): `C:\Users\Howie\github.git\endlos99\xdt99`
- **Python 3** for `xas99.py` and `linkticart.py`.

The script runs under either cygwin (`/cygdrive/c/...`) or Git Bash (`/c/...`) — it
auto-falls-back to the `/c/` form if the cygwin path doesn't resolve.

If `cvbasic.exe` is missing, build it with cygwin gcc (`C:\cygwin64\bin`, not on the
Bash tool's PATH — prepend it or use PowerShell):

```bash
cd /cygdrive/c/Users/Howie/github.git/nanochess/CVBasic
gcc -O cvbasic.c node.c driver.c cpuz80.c cpu6502.c cpu9900.c -o cvbasic.exe
```

## The three stages (what the script runs)

1. `cvbasic.exe --ti994a game.bas game.a99 "<CVBASIC_DIR>/"` — the **trailing-slash
   library-path 4th arg is required**; without it CVBasic can't find the 9900
   prologue/epilogue and silently leaves a broken stub.
2. `python xas99.py -b -R game.a99 -L game.txt` — assembles to `game.bin`
   (assembly errors land in `game.txt`).
3. `python linkticart.py game.bin game_8.bin "CART NAME"` — wraps it as an 8K-banked
   TI cartridge ROM.

## Pitfalls

- **TI filenames have no dots.** A TI disk name uses `.` as the device separator, so
  keep program/output names dot-free and ≤8 chars (`mspac`, not `ms.pac`).
- **stderr banner ≠ failure.** CVBasic prints its banner to stderr, so PowerShell may
  show a `NativeCommandError` even on success — judge by the output file and the
  "Compilation finished" message, not the stderr text. (The Bash script checks exit
  codes + non-empty outputs instead.)
- **Compile-only here.** This builds and compile-checks; it does **not** runtime-test.
  Gameplay must be verified by loading `<name>_8.bin` in Classic99 / js99er.
- A from-scratch CVBasic project: start from `examples/viboritas.bas` in the CVBasic
  clone (a complete game); `manual.txt` and `README - TI99.md` are the references.

## Per-game `build.sh`

Some games keep a hardcoded `build.sh` in their folder (e.g.
`games/mspacman-cv-xb-port/build.sh`). The skill's script is the generalized form —
prefer it for new games, or to build any game by passing its `.bas` path.
