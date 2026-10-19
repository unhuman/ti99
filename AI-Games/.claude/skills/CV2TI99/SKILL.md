---
name: CV2TI99
description: >-
  Port a ColecoVision game to the TI-99/4A by statically translating its Z80
  code (and the parts of the ColecoVision BIOS it uses) to TMS9900 assembly,
  built as a 128 KB bank-switched cart. Covers the inputs you must get first
  (the game ROM and the ColecoVision BIOS), the trace/annotate/translate/build/
  lockstep pipeline, the TI front end (TI994AVISION title rebrand, circled-X
  copyright, skippable title, entering the game from the option screen,
  keyboard mapping), game-over and black-screen handling, and the TMS9900
  speed techniques that actually paid off. Load before starting or changing
  any ColecoVision-to-TI port (Decompiled/CVZaxxon is the worked example).
---

# CV2TI99: ColecoVision → TI-99/4A

The two machines share the TMS9918A video chip and the SN76489 sound chip, so a
ColecoVision game can be translated instruction by instruction and keep its
graphics, sound and behaviour exactly. The CPU is the hard part: the TMS9900
runs about 1,850 instructions a frame from the TI's 8-bit memory against the
Z80's ~6,400, so a straight translation runs at roughly half speed and the work
after the first playable build is removing work, not re-encoding it
(`optimization.md`).

**Worked example: `Decompiled/CVZaxxon`** (local; `Decompiled/` is gitignored, so it
is not in git history). Copy its `tools/` and `src/` as the starting point; the
generic parts are `xlate.py`, `build.py`, `layout.py`, `lockstep.py`, `z80emu.py`,
`tiemu.py`/`ti99emu_base.py`/`vdp.py`, `insntest.py`, the speed tools and
`src/runtime.a99`/`src/sound.a99`. Game-specific: `tools/ann.py` (annotations),
`tools/screens.py` (title/option screen patches), `src/render.a99` and the `src/r*.a99`
regions. Read its `README.md` first.
**Newer, cleaner template: `Decompiled/RiverRaid`** (a $55AA game that calls the
BIOS): Joust's region map and far jumps plus Zaxxon's BIOS natives, the
vblank-deferred VDP queue, and the measurement and porting tools
(`ipass.py`, `zincl.py`, `xlatcost.py`, `routest.py`, `vtime.py`, `vregs.py`,
`pdist.py`, `gotest.py`). Start a new port from it.

## 1. Inputs: get them before anything else

Stop and ask the user if any is missing. Never download ROMs; use the user's dumps.

| Input | What | Where it goes |
|---|---|---|
| Game ROM | the cartridge dump, `.col`/`.rom`, 8-32 KB, mapped at `$8000` (header `$AA55`/`$55AA` at `$8000`) | `roms/<game>.col` |
| ColecoVision BIOS | `coleco.rom`, 8 KB at `$0000-$1FFF`. The game calls it through the jump table at `$1F61-$1FFF`, and the BIOS draws the title screen and the option ("GAME_OPT") screen | `roms/coleco.rom` |
| TI toolchain | xdt99 (`xas99.py`), Python 3, Classic99 (the `Downloads` QI399.087 build) | see `CVZaxxon/README.md` |

Also ask for (or find) a reference video/description of the original if the user
wants extras (the Zaxxon explosion was specified from the arcade).

## 2. Pipeline

1. **Trace** (`tools/trace.py` → `disasm/cart.lst`, `disasm/bios.lst`): recursive
   disassembly from the reset vector, the NMI vector (`$8021` in the cart header
   → the game's NMI handler) and every BIOS entry the cart calls.
2. **Annotate** (`tools/ann.py`) what the tracer cannot see: computed jumps
   (`JP (HL)` tables, `JP_TARGET`), inline parameters after calls, data regions,
   `ICALL` (sound-effect routine pointers), BIOS routines to replace natively
   (`NATIVE`, `NATIVE_FLAGS` when the native returns flags), literal TMS9900
   patches (`PATCH`, keyed by Z80 address), hand-written regions (`ASM_REGIONS`).
3. **Translate** (`tools/xlate.py`): one Z80 instruction → a few TMS9900 ones.
   Register map: A = R1 high byte (low byte 0), BC/DE/HL/IX/IY = R2-R6, R7 = Z80
   SP + K (a real pointer into the stack), R8 = flags (canonical bits Z >2000,
   C >1000, S >8000, P >0400; flags stay in the TMS9900 status when the next use
   allows), BC'/DE'/HL' = R9/R10/R13, A' = R14, R11 = link, R12 = 0 (CRU base),
   R0/R15 scratch (the NMI path clobbers them). Memory: Z80 `$7000-$CFFF` →
   TI `>A000-FFFF` (K = >3000; RAM `$7000-$73FF` at `>A000`); BIOS `$0000-$1FFF`
   → `>2000-3FFF` (KB = >2000).
4. **Interrupt**: the TI has no NMI. The VDP interrupt is polled at loop heads
   (`TB 2 / JEQ $+6 / BLWP @NMIV`); the glue runs the game's NMI handler. Honour
   the game's own critical sections (Zaxxon: `RST 8` sets `$719E` bit 0 and the
   handler only marks the NMI pending).
5. **Build** (`tools/build.py`, `layout.py`, `screens.py`): 128 KB non-inverted
   bank-switched cart (`_8`, 16 banks of 8 KB, select by writing `>6000+2n`). The
   runtime is a shared segment (`BANK ALL`, repeated in every bank); hot code
   goes to RAM (holes in the BIOS image and the cart image, copied from payload
   banks at boot) and the shared segment; cold code to banks via `FARCALL`. Hot vs
   cold comes from a profile of the Z80 reference (`build/prof_z80.json`).
6. **Verify** (§6) and play-test in Classic99 (§7).

## 3. TI front end (do all of these in every port)

**Title screen (BIOS).** The BIOS boot screen says COLECOVISION and shows a
(c) line. Rebrand it to **TI994AVISION** in the same blocky multicolour font:
the BIOS builds the logo from 8x8 "pieces" (8 bytes each at `$14C3 + 8*i`), a
table at `$18A3` maps pieces onto patterns `$60-$8F`, and two name-table rows
(`$144D`, `$1463`) place them; letter colour comes from the pattern's colour
group. New glyphs (T, 9, 4, A) are drawn on the originals' grid and stored in
BIOS bytes nobody reads as data. The logo is one column narrower, so move the
TM (an `ann.PATCH` on the `LD DE` that positions it). **Replace the © glyph
(character `$1D`, BIOS font at `$158B`) with a circled X**:
`7E 81 A5 99 99 A5 81 7E`. All of this is `screens.bios_patches()`; every
patched range must be in `reserved_bios()` so the RAM image keeps it.

**Title hold.** The BIOS sits on the title for ~11 s (`$1968`, a 39 M T-state
busy loop). Replace it natively (`N_TITLEW`): 657 frames, **cut short by any key
or joystick input**, then wait (at most a second) for the release so the press
does not reach the option screen.

**Option screen (BIOS GAME_OPT).** Change "PRESS BUTTON ON KEYPAD." to
**"PRESS BUTTON ON KEYBOARD."**, centred, with "TO SELECT GAME OPTION," starting
in the same column (Zaxxon moved both strings into the BIOS's unused "TURN GAME
OFF" message at `$1479` and patched the pointers). Keys 1-8 pick the option
directly.

**Keyboard and joysticks** (`KSCAN` in `runtime.a99`, read through the
controller port emulation and the native POLLER):

| Coleco | TI |
|---|---|
| joystick 1 / 2 | TI joystick 1 / 2, or E S D X; controller 2 also follows joystick 1 |
| left fire | joystick fire, SPACE or Q |
| right fire (arm) | ENTER |
| keypad 0-9 | 0-9 |
| `*` | SHIFT 8, FCTN 8 (REDO) — check what the game uses it for |
| `#` | SHIFT 3, FCTN 9 (BACK) |

The keypad port reads active-low codes that the BIOS decodes through a table at
`$10F5` (index = complemented nibble; `*` reads 9 → `$0A`, `#` reads 6 → `$0B`).
**Put the whole decode table in `reserved_bios()`**: the profile only sees the
keys pressed while profiling, so the RAM copy otherwise holds zeros for the
others, and `*`/`#` silently stop working (that was the Zaxxon game-over bug).

**Entering the game.** Boot → title (skippable) → option screen → a digit
starts the game. Wait for the key's release between screens (§ti-input-screens
skill: a press that dismisses one screen must not act in the next).

## 4. Game over and black screens (TI players read a black screen as a crash)

ColecoVision games blank the display after an idle timeout (a screen saver).
On the TI this looks like a hang. In every port:

- **Game over must never go blank.** When the game-over timeout expires, go to
  the option (difficulty) screen instead of turning the display off.
- On the game-over screen, **FCTN 9 (BACK), FCTN 8 (REDO) and the fire button
  return to the option screen**; keep `*` (SHIFT 8) as "play again" if the
  original had it. Require a fresh press (the fire button is usually still held
  from play: clear the field / wait for a release first).
- **Option screen idle blanking**: find the BIOS/cart timeout that writes VDP
  register 1 with the display bit clear (Zaxxon `$C1C3`: `$82` into register 1,
  black into register 7) and remove it.
- **Slow full-screen clears** done byte by byte through the VRAM-write helper
  look like black/frozen screens on the TI (Zaxxon's clear took 31 frames vs 15
  on the Coleco). Make the fill native (one address set, then data writes,
  polling the frame every 32 bytes). Return exactly the registers and flags the
  original leaves (`NATIVE_FLAGS`).
- Implement these as `ann.PATCH` entries on the Z80 instructions (literal
  TMS9900) plus small natives, and say in the README that they differ from the
  original. They are TI-only behaviour: the lockstep must be able to switch them
  off (§6).
- One-player games: hide the second player's score if the original draws it
  (Zaxxon draws both rows).

## 5. Speed

Read `native-porting.md` (the measured budget, the porting process, the
tools and the rules) and `optimization.md` before optimizing. Summary of what paid off in Zaxxon,
largest first: native BIOS sound/poller/VRAM routines and the game's NMI glue;
a native playfield renderer with precomputed (planar) character tables and a
table-driven fast row path; compare-on-change caches (sprite-table dirty flags,
PLAY_SONGS per-channel inputs, controller debounce settle, keyboard decode);
TI-only renderer pacing (`RMINN`) so the picture never starves; reading the
controllers every other frame; native fills. Re-encoding translated code by hand
gave ~0: only removing work helps. Measure with `tools/speed.py ... --pass`
(input keyed to logic passes so both machines play the same game; frame-keyed
random input makes the machines play different games and gives misleading
ratios) and profile with `tools/tiprof6.py` (listing-based attribution).
The translation runs about one TMS9900 instruction per Z80 instruction at
2.6x the time each, so it tops out near half speed; past that only removing
work helps (`native-porting.md` section 0).

## 6. Verification (non-negotiable)

- `tools/lockstep.py` runs the TI build and the Z80 reference (`z80emu.py`) in
  lockstep from power-on: time is counted in poll-site visits ("ticks"), the
  interrupt is taken at the same poll site on both, and RAM (minus the stack),
  VRAM, VDP registers and the sound chip's registers are compared. 0 diffs is
  the bar for every change. `--keys 1@6000,#@150000,2@165000,*@250000` scripts the
  keypad through a game, game over, both exits and a second game; also run it
  with random joystick + fire input (both Coleco controllers mirrored, since the
  TI's controller 2 follows joystick 1), which reaches later parts of the game
  that no-input runs never see.
- **Every TI-only behaviour must be switchable** so lockstep stays exact: renderer
  pacing (`RMINN` = 0 via a hook at `RMINOK`), keyboard sampling (force a full
  scan on every read), extras like the explosion, HUD changes, game-over exits.
  The Z80 reference must run the same patched program if you patch the ROM.
- `tools/sprcheck.py`: the VRAM sprite table equals RAM after every copy (catches
  a store that changed the table without marking it dirty).
- `tools/insntest.py`: single translated instructions vs the Z80 with random inputs.
- `tools/routest.py ADDR` (RiverRaid): one routine from real captured states,
  the TI build's version (translated, native or region) against the Z80;
  the check for every native port (`native-porting.md` section 5).
- Test scripts that hook TI addresses must be **bank-aware**: a banked routine's
  address is reused by code in other banks (a hook on `$80B5` in bank 5 fired on
  other banks' code and made a working exit look broken).

## 7. Working practice

- Build both the cart and its docs together; keep `README.md` (controls, what
  differs from the original, measured speed) in sync with every change.
- Put every candidate cart in `build/` and tell the user the path. Do not
  relaunch, kill or key-drive a Classic99 the user is playing without asking.
- Another agent (Codex) may be working on the same folder: check file times and
  running processes before editing; never edit files another agent is changing.
- Pitfalls that cost real time are listed in `optimization.md` § Pitfalls.
