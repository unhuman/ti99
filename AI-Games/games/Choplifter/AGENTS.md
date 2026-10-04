# Choplifter

This folder is the Choplifter CVBasic game. Read `../../CLAUDE.md`, `README.md` and
`DESIGN.md` before changes. Keep work scoped here; other games live in the parent
repository. Edit `assets/generate.py` before regenerating `src/assets.bas`.

Run `build.ps1 All` through PowerShell or the two Cygwin shell scripts sequentially.
`tools/check.py` executes selected BASIC routines; an unsupported statement must
fail instead of being ignored. Keep the known-bad mutation tests.

Use `launch-ti.ps1` for a separate Classic99 review session. Do not stop an existing
user emulator session without approval. `tools/capture.ps1` requires an explicit
process ID; never send test input to whichever emulator happens to be first.
