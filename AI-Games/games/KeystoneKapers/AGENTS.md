# Keystone Kapers: continuation guide

Read `../../AGENTS.md` and `../../CLAUDE.md` along with this file. Paths below are
relative to this game directory. This guide was established on 2026-09-20 from
the existing source and notes; it is not a claim of a fresh runtime test.

## Source map

- `src/KEYSTONE.bas`: shared gameplay source, with `#if TI994A` / `#if NES`
  branches. TI-99/4A and ColecoVision are the original targets; NES is implemented.
- `assets/genart.py`: character/sprite data and pattern ownership. Kelly's editable
  drawings are `kelly-run1.txt`, `kelly-run2.txt`, and `kelly-duck.txt`; Harry's
  run drawings are `harryrun1.txt` through `harryrun4.txt` in the same directory.
- `assets/genstore.py`: store templates, roof skyline, and level hazard tables.
- `assets/gentitle.py`: title and message display lists.
- `src/art.bas`, `src/store.bas`, `src/title.bas`: generated outputs. All three
  generators run in the game build scripts; use that workflow.
- `assets/nes_chr.asm` / `assets/nes_apu.asm`: NES graphics and sound shims.
- `assets/gennescolor.py` / `assets/nes-shelf.txt`: NES-native store tiles,
  editable shelf artwork and per-screen palettes; emits `src/nescolor.bas`.
  Native static tiles and converted animated tiles must agree on shared colours.
- `assets/check*.py` and `assets/*_test.py`: regression gates and their self-tests.
- `assets/prevtitle.py`, `previewrun.py`, and `cmpref.py`: offline visual checks.
- `assets/sfx/sfxprocess.md` and reference sheets: measured sound workflow.
  `sound/colecosounds/` and `sound/testsounds/` hold the sound bench projects.

## Build and validate

From this directory in Bash, run sequentially:

```sh
bash build-ti.sh
bash build-coleco.sh
bash build-nes.sh
```

From PowerShell at the AI-Games root, the equivalent explicit Cygwin invocation is:

```powershell
& 'C:\cygwin64\bin\bash.exe' games/KeystoneKapers/build-ti.sh
& 'C:\cygwin64\bin\bash.exe' games/KeystoneKapers/build-coleco.sh
& 'C:\cygwin64\bin\bash.exe' games/KeystoneKapers/build-nes.sh
```

Check each exit status before continuing. The scripts use `unhuman/CVBasic`,
`endlos99/xdt99`, and `nanochess/gasm80`; `CVBASIC_DIR`, `XDT99_DIR`, and `GASM80`
can override their paths. They handle the Cygwin runtime, Python selection, and
MSYS2 path rewriting. The generic Claude build helper is not a replacement for
these game-specific scripts.

Outputs are `src/KEYSTONE_8.bin`, `src/keystone.rom`, and `src/keystone.nes`.
The scripts regenerate assets and run the shared truncation/control-flow gates,
game-specific gates, and every `assets/*_test.py`. Preserve these checks. The TI
build also verifies the fixed area and packed data banks; NES checks allocated
RAM after compilation and checks vblank budgets. `gasm80` can exit zero after
errors, so retain the scripts' output/error checks.

Building is not playtesting. For a game change, review title/start input, `838`
setup, screen seams, jumping/ducking, escalators/lift, catching/escape, hazards,
sound shutdown, score/lives, and game-over re-entry as relevant to the change.
Use `../../tools/shoot99.ps1` for Classic99 captures/input; it finds the visible
window because `MainWindowHandle` can refer to a hidden one. Follow the shared
newest-cart emulator handoff rule.

## Constraints to preserve

- Eight discrete 256-pixel screens, three shopping floors plus the roof, and
  zero per-frame VDP reads. The view flips at a seam rather than scrolling.
- Movement uses elapsed-frame accumulators. `WALKSP` is a historical per-pass
  constant; inspect `KWALK64` and the actual consumers before changing pacing.
  Escalator animation and its riders deliberately share a fixed per-pass clock
  to avoid drift and cyclic aliasing. Keep the distinction in the checkers too.
- TI code has a **24,336-byte fixed-area cap**, independent of cartridge size.
  There are two data banks: bank 2 supplies the setup font, and bank 1 holds
  runtime data. Inspect current bank selection and INCLUDE placement before
  moving anything. Measure fresh headroom with `banksize.py` / `bankfill.py`;
  old free-byte figures in the notes are not a current budget.
- Pattern codes, sprite slots, and raw VRAM ranges all have owners. Consult
  `genart.py`, `checkpat.py`, and the source's slot allocation before adding art.
  NES RAM is also tight: even a new scratch variable can move an array out of RAM.
- Keep sound note-offs, pending effect latches, and decay counters synchronized
  with `snd_off`; `checksound.py` derives the required state from its producer.
- Title input must be live when its prompts appear. The ALPHA LOCK calibration
  and speculative key stability filter were removed. Do not restore them from
  older notes without reproducing an actual fault (`DESIGN.md` section 0e-sexies).
- The `838` setup code is intentionally unadvertised. Release-gate controls
  between screens so a start press does not become an in-game jump.

## Where work stood

This is an existing playable implementation, not a phase-1 skeleton. Read the
relevant research/change sections of `DESIGN.md` before changing a mechanic;
section 12a covers the NES port and section 13a records completed roof parallax.
The old phase table and some README/source comments still describe superseded
timing, banking, and input behavior. Check executable source and explicit later
corrections before interpreting them as current requirements.

Known follow-up items to assess when the user selects the next change:

- `KEYSTONE.bas` currently separates `DUCKH = 11` (collision) from
  `DUCKDRAW = 17` (drawing). Its comment acknowledges the mismatch: closing it
  requires considering jump geometry and ball avoidability together, not merely
  raising the hitbox or redrawing the crouch. Use `checkball.py` and art checks.
- `DESIGN.md` section 12a, "What is not done", records NES counter/pillar colour
  ambiguity (resolved by section 15), unverified NES sound, and sprite scanline pressure that may need
  merged 2bpp actor art. Treat these as recorded limitations to reproduce, not
  as newly verified findings.
- That section also records that NES pacing was based on the TI's measured loop
  rate rather than a fresh NES measurement. Measure actual behavior before tuning.

No particular gameplay fix was selected during the Codex handoff. Continue from
the user's next concrete request, retaining these constraints and shared notes.
