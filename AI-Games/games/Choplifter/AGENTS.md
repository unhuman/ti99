# Choplifter

This folder is the Choplifter CVBasic game. Read `../../CLAUDE.md`, `README.md` and
`DESIGN.md` before changes. Keep work scoped here; other games live in the parent
repository. Edit `assets/generate.py` before regenerating `src/assets.bas`.

Run `build.ps1 All` through PowerShell or the two Cygwin shell scripts sequentially.
`tools/check.py` executes selected BASIC routines; an unsupported statement must
fail instead of being ignored. Keep the known-bad mutation tests.

Use `launch-ti.ps1` for a separate, visible Classic99 review session. It moves the
launcher to `WinSta0\Default`; a direct `Start-Process` from Codex's private desktop
produces audio without a user-visible window. Run it after each new TI ROM build.
Do not stop an existing user emulator session without approval. `tools/capture.ps1` requires an explicit
process ID; never send test input to whichever emulator happens to be first.
Use `launch-coleco.ps1` for ColecoVision reviews. ColEm is the default emulator;
pass `-CoolCV` only when the user asks for CoolCV. It also launches on
`WinSta0\Default` and leaves existing emulator sessions alone. Keep its
`-ntsc -sync 60` arguments: ColEm otherwise defaults to an unsynchronized
frame clock, making gameplay speed comparisons unreliable.
