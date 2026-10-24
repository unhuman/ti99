---
name: TI992CV
description: >-
  Port a TI-99/4A game to the ColecoVision by statically translating its
  TMS9900 code (and the parts of the TI console ROM/GROM it uses) to Z80
  assembly, built as a 32 KB cart or a MegaCart. The inverse of CV2TI99.
  Covers the inputs you must get first (the game's ROM banks, the TI console
  ROM and GROM), feasibility checks (GPL/GROM games, 32K-RAM games, speech),
  the trace/annotate/translate/build/lockstep pipeline, the little-endian
  workspace-in-RAM register model, lazy TMS9900 status flags, the console
  ISR replaced natively (sound lists, sprite motion, VDP timer), the TI
  keyboard rebuilt from the Coleco controllers, the Coleco cart header and
  front end, and the Coleco-only hazards (NMI, VDP write speed, 1 KB RAM).
  Every task under it runs the automatic validate-then-optimize loop (§0):
  scripted gates on each build, per-phase speed measured against the TI, and
  profile-driven optimization rounds until the target or a stop condition,
  without being asked. Load before starting or changing any TI-to-ColecoVision port.
---

# TI992CV: TI-99/4A → ColecoVision

The inverse of `CV2TI99` (read that skill too; most of its method carries over
with the roles of the two machines swapped). Both machines have the TMS9918A
video chip and the SN76489 sound chip, so a TI game translated instruction by
instruction keeps its graphics, sound and behaviour exactly. The hard parts
are the parts that differ:

| | TI-99/4A (source) | ColecoVision (target) |
|---|---|---|
| CPU | TMS9900, 16-bit, **big-endian**, registers in RAM (workspace) | Z80, 8-bit, **little-endian**, registers on chip |
| RAM | 256 B scratchpad `>8300` (+ 32 KB expansion if the game uses it) | **1 KB** at `$7000-$73FF` (mirrored `$6000-$7FFF`) |
| ROM | cart `>6000-7FFF`, 8 KB banks (write `>6000+2n`); console ROM + GROM | `$8000-$FFFF` 32 KB; MegaCart for more |
| VDP | `>8800` read data, `>8802` status, `>8C00` write data, `>8C02` address | port `$BE` data, `$BF` control/status |
| Sound | `>8400` | port `$FF` (same byte protocol) |
| Frame interrupt | maskable (`LIMI 2`), runs the console ISR | **NMI** (cannot be masked except via VDP R1 IE bit) |
| Input | 8x8 keyboard matrix over CRU, two joysticks on columns 6/7 | two controllers: joystick + 2 fires + 12-key keypad |

**Status (2026-10-22): Parsec is a working 128 KiB MegaCart port.**
Its release has native performance paths, all-family original-code enemy
checks, optional PSG speech, and a Coleco front end. Timed parity is measured,
not assumed; speech remains less clear than the original TI synthesizer.
Use `Decompiled/CV_Target/Parsec/tools` as the current reverse-port template.
Earlier forward-port tools remain useful references. See §10–12 for the
corrections learned from the complete port.

**Reusable tools (copy from `Decompiled/CVZaxxon/tools` / `Decompiled/RiverRaid/tools`):**
the roles flip. `ti99emu_base.py`/`tiemu.py` (cycle-counting TMS9900 + GROM +
9901 keyboard + bank switching) become the **reference**; `z80emu.py` (Coleco
Z80 + VDP + SN76489 capture) runs the **translated cart**; `vdp.py` is shared,
so status, collisions and screenshots come out identically on both. `z80.py`
(decoder) and `tms.py` (TMS9900 sizes/status bits) are the instruction facts;
`lockstep.py`, `insntest.py`, `routest.py`, `sprcheck.py` and the profilers
need their direction reversed. **Likely first candidates:** the TI ROM-only
carts already disassembled in `Decompiled/` (`MsPacFst`, `DonkeyKong`,
`galaxian`: Atarisoft, 8 KB banks, no GPL). Use their unpatched originals,
not the sped-up builds, unless the user asks otherwise.

## 0. Default loop: validate, then optimize, without being asked

Validation and optimization are **part of every task under this skill**, not
follow-ups to offer (the same contract as `CV2TI99` §0). The user has spent
many sessions manually prompting each verify/measure/optimize round. Do not
hand back a cart until this loop has run, and do not stop to ask whether to
run it.

1. **Baseline first.** Before changing anything, record the current ROMs'
   SHA-256 (`game.rom`, `game_dev.rom`, `game_ls.rom`), gate results and
   per-phase speed (`speed.py`, `scrollrate.py`, `scenes.py` phases from §11:
   title entry, first enemy, active movement, explosions, respawn, next wave,
   crash, speech under load). A new port copies Parsec's `tools/` first; the
   scripted gates are a deliverable of the port, like the cart.
2. **Validate every build automatically** with one command that exits
   nonzero on any failure (Parsec's `verify.py`, or the port's equivalent;
   create one if missing): exact lockstep on `game_ls.rom` (scripted keys
   **and** random input), `insntest`/`routest` for every touched translation
   or native, sprite/VDP-transaction/video tests, RAM and stack budget,
   front-end/input release tests, and the source-ROM algorithm checks. Each
   new gate gets a mutation self-test that rejects a real bad ROM. Run long
   suites against a frozen copy of `build/`.
3. **Compare against the target automatically.** The target is the TI's
   measured rate in every phase within the established per-phase tolerance
   (never relaxed to accept a candidate), capped at the TI's rate (§7), with
   no new flicker, sound or speech-cadence regression. If any phase is below
   target or slower than the baseline, **go straight into the optimization
   loop**:
   - profile the whole frame per phase (`cvprof.py`, `profile.py`,
     `costcmp.py`) and rank costs;
   - pick the largest *removable* work, using §11 and
     `CV2TI99/native-porting.md` / `optimization.md` as the menu of what
     paid. Keep a ledger (`build/optimization/process-ledger.json`, as in
     RiverRaid.3) and do not retry a rejected idea unless what it depended
     on changed;
   - implement it with any Coleco-only behaviour switchable for lockstep;
   - re-run step 2, then measure on the fixed phases plus held-out seeds:
     accept only if the total rises and no phase falls outside tolerance;
     record accept/reject with numbers; revert rejects;
   - repeat.
4. **Stop** when every phase meets the target, or two consecutive accepted
   rounds each gain under 1%, or ROM/RAM budget is exhausted, or the next
   step needs a user decision (a deliberate release difference, a MegaCart
   size change, the Super Game Module, speech trade-offs). Ask only then.
5. **Hand back** with final-ROM evidence: hashes, gate summary, per-phase
   speed vs the TI and vs the baseline, what was tried and rejected.
   Emulator play-tests follow §9 (ask before the first Coleco emulator
   launch; ColEm `-ntsc -sync 60`, Draw All Frames). Until approved,
   `z80emu.py` screenshots plus the gates are the evidence; say so.

A correctness fix still runs steps 2-3: a fix that costs speed is measured,
and if it drops a phase below target the loop runs.

## 1. Inputs and feasibility: settle these before anything else

Stop and ask the user if any input is missing. Never download ROMs; use the user's dumps.

| Input | What | Where it goes |
|---|---|---|
| Game | cart ROM banks (`NAMEC.bin`/`NAMED.bin`, or one `_8.bin`), optional `NAMEG.bin` GROM; or E/A5 program files | `roms/` |
| TI console ROM | `994aROM.bin`, 8 KB at `>0000` (KSCAN, the ISR, XMLLNK/GPLLNK entry points) | `roms/` |
| TI console GROM | `994aGROM.bin`, 24 KB (the character sets games load through GPLLNK, and anything read through `>9800`) | `roms/` |
| ColecoVision BIOS | `coleco.rom`, needed by the reference emulator and for the BIOS title screen | `roms/` |
| Z80 assembler | gasm80 (or the assembler a CVBasic Coleco build uses) | see `cvbasic-ti99-vs-coleco-dual-target` memory |

**Feasibility gates. Report each one to the user before translating:**

1. **GPL / GROM games.** Many TI cartridges (most TI-made ones) are GPL bytecode
   in GROM interpreted by the console. Translating those needs a GPL
   interpreter or a GPL-to-Z80 translator, which is a different project. Check
   the cart header (`>6000` ROM header vs a GROM `>AA` header at `>6000` in
   GROM space) and say so. ROM-only assembly carts are the target.
2. **RAM footprint.** Run the reference for a full game (title, several levels,
   death, game over) and record every **written** address outside VRAM. The
   scratchpad (256 B) fits easily. Expansion-RAM use (`>2000-3FFF`,
   `>A000-FFFF`, typical of E/A5 disk games) must fit in what is left of the
   1 KB (about 700 B after the scratchpad image and the stack), or the port
   needs the Super Game Module (24 KB extra RAM). That is a hardware add-on, so **ask the user
   before choosing it**. Data the game only reads, even if copied to RAM at
   boot, can stay in ROM.
3. **Speech** (`>9000`/`>9400`): the Coleco has no LPC synthesizer, but speech
   can be rendered through its existing PSG. Parsec decodes the original LPC
   offline and resynthesizes it as bounded tone/noise frames (§11). Preserve an
   existing user choice; otherwise establish whether speech is required.
   Do not promise TI-quality speech or choose CPU-blocking PCM without measuring
   its effect on input, sprite motion and the full game loop.
4. **Code run from RAM.** TI games copy hot loops into the 16-bit scratchpad
   for speed. If the copy is never modified afterwards, translate the ROM
   original and drop the copy. Self-modifying code (writes to an address that
   is later executed) must be found with the reference emulator (watch writes
   to every executed address) and annotated by hand.

## 2. Pipeline

1. **Trace** (TMS9900 tracing disassembler → `disasm/cart.lst`, plus
   `disasm/rom.lst` for the console-ROM routines the cart calls): recursive
   descent from the cart header's program-list entry point, every `BLWP`
   vector, the ISR hook the game installs (`>83C4`), and dynamic coverage from
   the reference emulator for what static tracing misses.
2. **Annotate** (`tools/ann.py`) what the tracer cannot see: computed
   branches (`B *R1`, `B @TBL(R2)`, `BL *R5`), `X` (execute) targets,
   inline parameters after `BL`/`BLWP` (`DATA` words read through R11/R14),
   data regions, self-modifying sites, console-ROM routines to replace
   natively (`NATIVE`), literal Z80 patches keyed by TI address (`PATCH`),
   hand-written regions.
3. **Translate** (`tools/xlate.py`) one TMS9900 instruction to Z80 code,
   using the model in §3.
4. **Console replacements** (natively written Z80, §4): the ISR, KSCAN, the
   GROM font loads, any XMLLNK/GPLLNK the game uses.
5. **Build**: a 32 KB cart if the translation fits, else a MegaCart (16 KB
   banks, `$8000-$BFFF` fixed, `$C000-$FFFF` switched; check CVBasic's
   `BANK ROM 128` Coleco output for the exact bank-select convention rather
   than trusting memory). Expect the Z80 code to be about **2-3x** the
   TMS9900 code's size (measure it). Map each TI bank's code by profile: hot in the fixed
   half, cold in switched banks behind far calls. The CVBasic lesson in
   CLAUDE.md §3A applies here too: a ROM that boots can still have
   unreachable later code if it outgrew the window.
6. **Verify** (§7) in lockstep against the TI reference, then play-test (§8).

## 3. Translation model

**Use little-endian TI words in the Z80 runtime (Parsec's tested model).**
TI scratchpad `>8300–83FF` maps to Coleco `$7000–70FF`; each TI byte maps to
the opposite byte of its relocated word (`offset ^ 1`). Word loads/stores can
then use `LD HL,(nn)` directly. Apply this consistently to mapped immutable
data, hot-page copies, mutable workspaces and patched inline parameters.
VDP streams and GROM byte streams retain their original external byte order.
Lockstep converts the runtime representation back to TI order before comparing.
The former big-endian proposal cost swaps on every hot word operation; do not
mix the two models. Check odd-address bytes, scratchpad mirroring, page wrap,
register aliasing and both words of MPY results against the original core.

**Registers live in RAM at WP + 2n, as on the TI.** TMS9900 code can and does
read its registers as memory (`MOV @>8302,R0` is R1 when WP = `>8300`), and
`BLWP`/`RTWP` switch workspaces, so registers stay in RAM. Resolve WP
statically per routine (from `LWPI`, `BLWP` vectors and the ISR's GPLWS
`>83E0`) and make the translator **fail** where it cannot. Start with every
register access going to memory (correct first); then cache registers in
HL/DE/BC within basic blocks, writing back at block exits, calls and any
instruction that can address that register as memory.

**Byte operations work on the register's HIGH byte**: logical TI address
`WP+2n`, mapped to the odd physical byte of the relocated little-endian word.
`MOVB R1,@X` reads that high byte; `SWPB` swaps the word's two bytes in place.

**Status flags are lazy.** Almost every TMS9900 instruction sets L>, A>, EQ
(compare against zero for `MOV`/`MOVB`/`A`/...), and `C`, `OV`, `OP`
(parity, byte ops only) by form. Z80 `LD` sets nothing. Compute only the bits
a later reader uses (jumps, `STST`, `RTWP`'s saved ST, `BLWP` callee reading
R15) by liveness over the basic-block graph; materialise them at block exits
the analysis cannot see past. Map the jumps: JEQ/JNE ↔ Z, JH/JL/JHE/JLE ↔
unsigned (C and Z after a swapped compare), JGT/JLT ↔ signed (S xor V),
JOC/JNC/JNO/JOP from the saved bits. **Take every flag rule from
`ti99emu_base.py`, never from memory.** The carry convention after a subtract
is inverted between the CPUs: the TMS9900 sets C on *no* borrow, the Z80 on a
borrow. DEC/DECT and the shifts also set C. `insntest.py` checks each form
against the reference core.

**Instruction notes:**
- Shift count 0 takes the count from R0's low 4 bits; if those are 0 too, the
  count is 16.
- `MPY` (16x16→32 into a register pair) and `DIV` (overflow sets OV and
  leaves the operands unchanged) become Z80 helper routines; replace
  multiplies by constants with shifts and adds or tables where they are hot.
- `X` executes the instruction in a register: annotate the possible values
  and translate each.
- `BL`/`B *R11` return through a register in RAM, not a stack. Translate
  `BL` as a Z80 `CALL` only when the callee provably returns with `B *R11`
  and R11 is never read or modified in between; otherwise store the return
  address in R11 and translate `B *R11` as a jump through it.
- **CRU** (`TB`, `SBO`, `SBZ`, `LDCR`, `STCR` relative to R12): keyboard
  column select (`>0024`) and row read (`>0006`) go to the virtual keyboard
  (§5); `TB 2` with R12 = 0 (VDP interrupt pending) reads the frame latch (§4);
  cassette and other bits become no-ops. Make the translator list every CRU
  address it meets and fail on unknown ones.
- `LIMI 0`/`LIMI 2` set a software ISR-enable flag (§4).
- Cart bank-switch writes (`>6000+2n`) become MegaCart bank selects or no-ops
  when everything is flat. Data read **indirectly** from a banked window has
  the same hazard CLAUDE.md records for CVZaxxon in the other direction:
  every indirect pointer must land inside the mapped window, and a
  successful build proves nothing about it. Add a debug-build bounds check.

## 4. Interrupts and the console ISR

**NMI.** TI games almost always set the VDP R1 interrupt-enable bit
(`>E2`-style values), often from a register table in a loop. On the Coleco
that bit drives the NMI, which cannot be masked. Do not try to strip the bit
from every R1 write. Install an NMI handler that only sets a RAM frame latch
and returns (`push af / ld a,1 / ld (nmiflag),a / pop af / retn`):
- it never touches the VDP, so an NMI between the two address bytes of a VDP
  write is harmless (reading `$BF` in the handler would reset the address latch
  and corrupt that write);
- it catches every frame even when the game reads the status register itself
  (TI games read `>8802` for the collision and fifth-sprite bits, which clears
  the frame flag);
- the NMI is edge-triggered and the INT line stays low until the status is
  read, so it costs one short handler per frame.
**Set SP first thing** (top of RAM), before anything can enable the
interrupt, and point the header's NMI vector at the handler.

**Translate the console ISR, replacing measured hot regions with checked natives**, run at poll sites (loop heads and
`LIMI 2` sites while the software enable flag is set and the frame latch is
set), mirroring how CV2TI99 polls for the TI's interrupt. It must reproduce
what the game depends on, chosen from the ISR's control flags at `>83C2` and
what the game reads:
- read the VDP status into `>837B` and clear the frame latch;
- the **VDP interrupt timer** `>8379` (games pace on it);
- the **sound-list player** (`>83CC` pointer, `>83CE` count, CPU or VDP list
  per `>83FD`): byte count, data bytes to the sound chip, duration;
- **sprite auto-motion** from the motion table in VRAM (`>0780`) for the
  number of sprites in `>837A`;
- the user hook at `>83C4` (call the translated routine);
- the **screen-blanking timeout**: the TI ISR blanks the screen after a few
  minutes with no key press. Keep it for lockstep exactness, behind a switch.
  It is the inverse of CV2TI99 §4's Coleco blanking problem, so ask the user
  whether the release build should keep it. Drop the QUIT-key check.
Translate the reference emulator's ISR (from `disasm/rom.lst`) and check it
with `routest.py`; do not write it from documentation.

**Console routines called by the game** (KSCAN, GPLLNK/XMLLNK) may stay
translated or use contract-tested native replacements:
KSCAN reads the virtual keyboard (§5) and fills `>8375` (key), `>8376`/`>8377`
(joystick Y/X) and `>837C` (status, new-key bit) exactly as the reference
does for each keyboard mode in `>8374`. GPLLNK font loads copy the bytes from
the console GROM into ROM at build time and write them to VRAM natively.
Games that read GROM directly through `>9800`/`>9802`/`>9C02` get a GROM
address/data emulation over an embedded copy of **only the ranges read**
(measured with the reference). The shared VDP permits asset reuse, but interrupt ordering and Z80 port
spacing still require the checks below.

## 5. Controls: a virtual TI keyboard

Rebuild the TI's 8x8 keyboard matrix (and the two joystick columns) from the
Coleco controllers at each original physical input scan. A once-per-frame cache
can be stale by the time gameplay calls KSCAN; refresh there as well. All of the game's own CRU keyboard code and
KSCAN then work unchanged. First list **every key the game tests** (CRU column
reads and KSCAN key comparisons, from the trace) and assign each one a Coleco
control. The default mapping, inverse of CV2TI99's:

| TI | Coleco |
|---|---|
| joystick 1 / 2 (and E S D X) | controller 1 / 2 joystick |
| joystick fire (and SPACE / Q) | left fire |
| ENTER | right fire |
| 0-9 | keypad 0-9 |
| REDO (FCTN 8) | `*` |
| BACK (FCTN 9) | `#` |
| letters the game needs (Y/N, P for pause, ...) | spare keypad keys; list them in the README and on any screen that names the TI key |
| QUIT (FCTN =) | not mapped |

**Controls belong to a screen/state, with explicit release gates between actions.**
A key may toggle speech on a title, pause in flight, and restart at game over,
provided the prompts make those roles clear. A held key must never dismiss one
screen and also act on the next. See `ti-input-screens` and §12. Reading the
controllers: `OUT ($80)` selects keypad mode, `OUT ($C0)` joystick mode,
then read `$FC` (controller 1) or `$FF` (controller 2), active low. The
keypad nibble decodes through the table CV2TI99 §3 describes at BIOS
`$10F5`. Confirm port behaviour and settle time against `z80emu.py`. **Rewrite
any on-screen text that names a TI key** ("PRESS ENTER", "FCTN 9") for the
Coleco control. That is a data patch (`PATCH`) and is listed as a difference
in the README.

## 6. Coleco front end and Coleco-only hazards

- **Cart header** at `$8000`: `$AA55` (the BIOS shows the COLECOVISION title
  with the game's name line, about 11 s) or `$55AA` (skip straight to the
  game). The start address at `$800A`, the NMI vector at `$8021`, the title
  string at `$8024`. Copy the layout from a working Coleco ROM (a CVBasic
  Coleco build's prologue) and check it in `z80emu.py`. Use the BIOS title header only when a BIOS splash is wanted.
  For the requested TI-style startup convention in section 12, use the skip-BIOS
  header and draw that native startup instead.
- **Power-on**: silence all four sound channels (`$9F $BF $DF $FF` to port
  `$FF`) and set every VDP register yourself; never rely on the BIOS's state.
- **The Z80 can outrun the VDP.** During active display the TMS9918A needs
  roughly 8 µs (about 29 Z80 T-states) between VRAM accesses. The TMS9900 was
  never fast enough to violate this, so TI code never had to care, but a
  translated or native Z80 loop (and `OTIR`, ~21 T-states a byte) can
  silently drop bytes. Only burst outside active display (vblank or display
  off). Pad native fills otherwise. Add the timing check to `vdp.py` so the
  lockstep catches it, then confirm the number against the TMS9918A data
  manual.
- **Game over / idle must never go blank**, and every screen must accept the
  mapped keys (CLAUDE.md §7A conventions still apply; the TI game's own
  difficulty screen stays as the original drew it).
- RAM is 1 KB, so the stack shares it with the game's state. Measure the
  deepest stack in the reference run plus the NMI frame, and fail the build if
  the RAM map leaves less than that.

## 7. Speed

§0's optimization loop runs this on its own; this section and §11 are its menu.
Translation overhead and ISR cost can be the main performance problem. The Z80 executes
far more instructions per frame (CV2TI99 measured ~6,400 Z80 vs ~1,850
TMS9900), but one TMS9900 instruction (16-bit, memory-to-memory) becomes
several Z80 instructions plus byte swaps and flag work, so **expect roughly
parity and measure it** (`speed.py --pass`, logic passes per second, both
machines given the same input). The two timing hazards:
- **Busy-wait delay loops** calibrated to the TMS9900 (`DEC R1 / JNE $-2`)
  run at a different real speed. Find them in the profile and pace them on the
  frame latch, or scale the count, as TI-only/Coleco-only switches.
- **Running faster than the original** in a game paced by its CPU rather
  than by `>8379`/the frame latch. Cap it to the TI's measured rate; the user's
  preference is the TI's speed unless they ask otherwise.
If it is slow, the CV2TI99 lessons hold: remove work (register caching,
dead-flag elimination, native replacements of hot routines), do not hand-tune
translated code (`CV2TI99/native-porting.md`).

## 8. Verification (non-negotiable)

- **Lockstep** (`lockstep.py`, reversed): the TI reference and the
  translated cart from power-on, time counted in poll-site visits, the frame
  interrupt taken at the same poll site on both; compare the mapped RAM
  (scratchpad image and every relocated expansion byte, minus the stack),
  VRAM, VDP registers and the sound chip's registers. 0 diffs is the bar for
  every change. Script the keys through title, play, death, game over and a
  second game, and also run random joystick + fire input, which reaches
  parts of the game no-input runs never see.
- **Every Coleco-only behaviour is switchable** so lockstep stays exact:
  rewritten key prompts, the blanking timeout, delay-loop pacing, the speed
  cap.
- `insntest.py` (reversed): every translated TMS9900 instruction form
  against the reference core with random registers, memory and flags,
  checking every flag the translation claims live afterwards.
- `routest.py`: every native (ISR, KSCAN, sound list, sprite motion, fills)
  against the console code it replaces, from captured real states.
- `sprcheck.py` and the VDP timing check from §6.
- Hooks in test scripts must be **bank-aware** once the cart is a MegaCart (CV2TI99 §6).

## 9. Working practice

- **Play-testing:** the user's standing preference (memory
  `no-coleco-emulator-runs`) is not to launch Coleco emulators. For this skill
  the Coleco cart *is* the product, so **ask before the first play-test
  launch** unless the existing session already authorizes it. Authorization
  persists; do not ask again for ordinary reloads within that scope. If approved, ColEm needs `-ntsc -sync 60` (CLAUDE.md: its default is
  unsynchronised) and CoolCV needs scan-coded synthetic keys. Until then, rely
  on `z80emu.py` screenshots plus lockstep.
- Put every candidate cart in `build/` and tell the user the path. The playable
  release is `game.rom`; development is `game_dev.rom`; exact diagnostic
  lockstep is `game_ls.rom`. Update scripts, defaults and docs together. Retained
  immutable historical fixtures may keep their old names. Do not leave a stale
  `game_rel.rom` beside the new playable file.
- Keep `README.md` (controls mapping, what differs from the original,
  measured speed, RAM map) in sync with every change.
- Check existing changes and whether another assistant is actively editing the
  same files. A stale process alone is not evidence of concurrent edits; honor
  the user's explanation of who is working.
- When a fact in this skill turns out wrong, fix the skill in the same change.

## 10. Lessons from the ports (dated)

**Copied `tiemu.py` never runs the console ISR (Parsec, 2026-10-21).**
`ti99emu_base.TI99.step` tests `self.vstatus`/`self.vreg[1]` for the
interrupt, but `tiemu.TI` routes the VDP through the shared `vdp.VDP` model, so
those fields never change and the ISR never fires. Zaxxon's TI build had its
own ISR and never noticed. The symptom in a console-ISR game is a title screen
that ignores every key (the timer at `>8379` and the timeout at `>83D6` never
advance). Sync both fields from `self.vdp` at the top of `step` (Parsec's
`tools/tiemu.py` does).

**`start_cart()` skips state the console ISR needs.** Jumping straight to the
cart's entry leaves the 9901 VDP-interrupt mask (CRU bit 2) clear and the GPL
workspace registers unset; enabling only the mask made the ISR loop forever.
Power the console on and choose the cart from the menu (Parsec's
`tiemu.load()`: space at the master title, then `2`). The reference must run
the same boot the real console does, or lockstep compares against a TI that
never existed.

**A "ROM-only" cart can be a loader for a 32K-RAM program.** Parsec's
`PARSEC8.BIN` copies 27 KB into expansion RAM and runs from `>A000`. Measuring
"RAM written" naively says 27 KB, which fails the 1 KB gate. Classify each
write by time: take the frame at which code first executes from expansion RAM
as the end of the copy, and count only bytes written after it. Parsec drops to
71 bytes (a 32-byte workspace plus 39 bytes of inline `BL` parameters the game
rewrites, e.g. `MOV R8,@>A1E4` patching the `DATA` word after
`BL @>A9BA`). Those patched parameter words are self-modifying **data inside
code**: the translator must turn each one into a RAM variable read by the
translated call, and confirm the list statically (every store whose address
falls inside the code image), not only from a play sample.

**Random joystick + fire play covers the whole cycle cheaply.** 12,000 frames
of random input (`play.py`) reached title, play, deaths, game over, a second
game and the screen-blank timeout in ~5 minutes of Cygwin Python.

**Lockstep that copies the reference's start state hides what the cart lacks
(Parsec, 2026-10-22).** The harness copied the TI's VRAM into the cart at the
game's entry, so the release cart ran from different VRAM than anything
lockstep had verified. Rebuild the reference's entry VRAM in the cart (Parsec:
760 bytes of RLE) and run lockstep with the cart's own start state
(`--no-vram-copy`).

**Lockstep proves states, not time: a translated ISR can starve the game.**
Parsec moves every moving sprite in its ISR hook. Translated, a screen of
explosion fragments filled the whole Coleco frame; the game logic barely ran,
the explosion never ended and collisions and fire lagged, with lockstep still
exact. Benchmark the heaviest scenes (crashes, explosions), not just steady
play, and give the ISR path a native (Parsec `spr_motion`, tested against the
reference on random states by `sprtest.py`).

**Optimizations that reduced translation overhead:** constants for reads of
the read-only image; fixed-bank copies of hot data pages and a bitmap for pages
with RAM overrides; flag fusion (producer + following jumps test Z80 registers);
liveness that treats `BLWP` as restoring the status at its return point; operand
profiles (record each register-indirect operand's pages) for inline guarded
accesses; return prediction (Z80 CALL + DW of the expected TI return, checked,
sentinel frame at the base); native loops for block-transfer idioms with exact
final registers (lockstep builds poll and write back each iteration); one
translation per (address, workspace) pair, which removed IX-relative registers
(the tracer's multi-WP sets were nearly all merge artifacts: 12 duplicates in
2,751 instructions).

**Release-only switches must survive the optimizer.** A `JNE` turned into an
unconditional jump in release builds was fused into its producer's test and
the switch silently did nothing (Parsec's blanking timeout and speech
switches). Keep switched instructions out of fusion and check the generated
code for each switch.

**Correction to Parsec's old speed figures (2026-10-22).** The earlier
112% flight / 95% crash claims are withdrawn. A fixed short FIRE tap did
not reliably start the Coleco game, and aggregate loop rates mixed flight
with different death/respawn proportions. Verify actual gameplay entry,
then compare matching phases with real frame timing. The early corrected
opening was 132 Coleco frames versus 133 TI frames; the broken release took 236.
Those are historical measurements. Use the current hash-bound game reports for
current timings and tolerances; a later optimization can change them again.

**Complete static enemy tables, not just profiled targets.** Parsec's
second-wave >BEE4 initializer was missing and hit dispatch trap 1 in ColEm.
Enumerate the complete original tables (here >AD36 and >AD46), propagate
indirect-call return points, and avoid predicted returns where an indirect
call did not push a prediction frame. The saved ColEm freeze now drives
original-ROM tests for every initializer and first enemy-logic update.
Deleting >BEE4 from dispatch reproduces and rejects the original trap.

**Visible ColEm frame settings affect review.** With NTSC and wave audio
already selected, choosing Video -> Draw All Frames resolved the user's
jerky movement and sound complaint without changing the ROM. Verify the
loaded cartridge and all-frame setting before tuning gameplay timing.


## 11. Reusable performance and correctness lessons (Parsec, 2026-10-22)

**Start from the working reverse-port harness.** Preserve a baseline ROM,
symbols, mapping pickle and SHA-256 before changing the translator. Source
addresses are diagnostics, not assumptions about generated Z80 addresses.
Build development, lockstep and release sequentially. Retain required tracing,
assembly, bank-selector, RAM/stack and asset gates. Checks must execute the
assembled production ROM, and negative controls must reject an actual bad
opcode, bank, guard or previously failing ROM.

**Profile the whole frame and matching gameplay phases.** Capture original
power-on/title/game entry first. Short fixed FIRE taps can compare active TI
play with an idle Coleco screen. Observe the original game-start event and
release the button when the release build waits for release; do not inject
the start flag. Measure first enemy, active movement, explosions, respawn,
next wave, ground crash and speech under load separately. Keep the established
per-phase tolerance; never relax it merely to accept a candidate. Exact
lockstep validates semantics but cannot establish real-time parity.

**Make native contracts exact before making them common.** Useful patterns:
- Resolve one translation per `(TI PC, WP)` instead of merging unrelated
  workspaces. Propagate every indirect callee's return destinations.
- Fold immutable data reads; copy genuinely hot pages into fixed ROM. Reserve
  an explicit map/bitmap for mutable words inside otherwise immutable pages.
- Fuse flag producers and consumers, but respect BLWP/RTWP's restored flags and
  prevent fusion from swallowing release-only branches. Check emitted assembly.
- Predict returns only where the caller pushed a compatible prediction frame;
  retain the safe indirect dispatch fallback and bounded sentinel stack.
- Specialize bounded copy/fill/rotate loops with exact pointer, counter and
  final-register results. Guard both below-workspace and above-workspace buffers,
  page wrap, register aliases, even/odd byte lanes and all supported workspaces.
- For TMS shifts, count zero means sixteen. Preserve the full word after a
  byte-output rotate; matching only emitted pixels can hide bad live registers.
- Both members of an alternating index table must reach the fast path. Parsec's
  terrain table selected FFC4 **and FFC5**; accelerating only one left half the
  terrain work slow and delayed enemy turns.
- Use lookup tables for immutable coordinate transforms and a bounded native
  star/sprite loop. Preserve the final iteration's live workspace outputs.
- Inline tiny, frequent VDP helpers when justified by profiles; keep their
  interrupt ordering and port-spacing contracts.
- Common collision probes can use byte arithmetic when coordinates and indices
  are proven byte-sized/aligned. Keep signed/general fallbacks, inactive-sprite
  rules, exact inclusive hit boundaries, the last distance result and poll site.
  Test both sides of each boundary and rejected guard cases against TI code.

**VDP transactions must be atomic with respect to cooperative interrupts.**
An original helper that yields *after* setting the VDP address can become
unsafe when the translated ISR reads a VRAM sound list. The read changes the
address; the pending sprite upload then overwrites sound data. Symptoms include
stray high tones, huge sound-packet counts, slowdown, overshoot and apparent
freezes after repeated deaths. Yield **before** installing the transfer address,
then keep address and data together. Apply the fix to inlined call sites too.
Inject the actual ISR address-changing side effect at the assembled poll; check
ordered reads/writes, final VRAM/latch/buffer, and repeated natural deaths. The
original bad ordering must fail. NMI must never touch the VDP latch or mapper.

**Enemy parity is an algorithm audit, including variability.** Enumerate all
initializer, logic, path and velocity tables from the original ROM. Establish
which choices are random, which depend on reserves/level/difficulty, and which
track the player. Preserve unequal selector probabilities; do not flatten them
into equally likely choices or hard-code a recorded path. Exhaust a small RNG's
state space (Parsec: all 65,536 states), test all flight tables and legal branch
boundaries, then advance the original frame timer between motion steps. A
trajectory harness with a frozen timer misses acceleration and stream exhaustion.
Derive sentinel constants from the original image, not guessed hexadecimal
values. Combine state/ordered-VDP tests with clocked runs of every family and
occasional firing. Slower logic allows ISR velocity to move farther before a
turn; optimize that cause before changing the original velocity/path constants.

**Protect genuinely late player boundary checks at the motion point.** Establish
the original clamp/stop threshold and legal movement first. A release guard may
enforce it for the live player's upward motion when cooperative work delays the
main-loop check. Scope it by sprite identity and live state; clear it before
death. Test delayed checks, wrapping, maximum lift, and nonplayer motion. Record
this as a deliberate release difference, not an exact-native substitution.

**PSG speech is possible but is not LPC-equivalent.** Decode the user's original
speech data offline with the appropriate TMS5200/5220 model, preserving phrase
IDs and timing. Parsec analyzes 8 kHz PCM and emits 60 Hz frames for three tone
oscillators plus noise. Weighted amplitude spectra, 2 dB quantization, original
pitch/voicing guidance, stable oscillator assignment and noise-mode changes only
when needed improved the measured result. User listening still preferred TI.
WAV bitrate or normalization cannot restore detail lost in PSG resynthesis.

Use a bounded producer at a safe service point and a two-frame RAM queue.
The fixed-ROM NMI may emit one already-queued PSG frame; it must preserve
registers/flags, never bank-switch, and never read VDP status. Keep clips inside
banks, verify every frame of every clip, and measure worst-case service cycles,
queue cadence and PSG spacing. Shadow the game's complete PSG register/latch
state while speech owns the chip; restore tones, volumes, noise mode and latch,
including continuation-byte behavior. Bound mixer headroom and render through
the real target emulator's PSG model to check clipping. Compare separate,
clearly labeled original/old/new audio with the user. Objective spectra are
supporting evidence, not proof of intelligibility. Preserve user feedback that
speech remains less clear.

## 12. Coleco front end convention (user-requested, 2026-10-22)

Use a **one-time TI-style startup screen**, shown only on cold cartridge start,
before the game's own title. Construct it from native VDP character cells and
the user's console font/logo assets; never scale a screenshot into a bitmap.
Parsec's template is `tools/ui_assets.py` plus `tools/ui_runtime.asm`:
- Cyan background, native TI logo, sixteen equal two-character color segments
  across the full 32-column width, three rows tall at rows 1–3 and 18–20.
- Top `UNHUMAN INSTRUMENTS` at row 9, column 7 (user-reviewed alignment),
  `HOME COMPUTER`, and `READY-PRESS ANY KEY TO BEGIN` in the original native font.
- Footer uses a circled **x**, `2026  UNHUMAN INSTRUMENTS`; the game's own title
  also uses the circled x, while its original game year/credit remain intact.
- Play the original TI **quick** beep on display and again on a keypad key or
  either fire button. Both use the same short duration (about 11 NTSC frames).
  Derive the PSG command bytes from the original console sound log. The original
  long cold-boot tone is intentionally shortened to the key-feedback duration.
- Scan input while the startup beep runs. After the advance action, finish the
  quick beep and consume release before entering the game's title. A held input
  must not start gameplay or activate a title option. This startup does not
  reappear after game-over BACK or REDO.

Keep input meaning explicit by state. Parsec's title has `* SPEECH ON` /
`* SPEECH OFF`; `*` toggles voice and other keypad keys or either fire start.
Speech defaults ON at cold reset and persists across games and title visits.
OFF suppresses requests and clears the original busy flag while leaving effects
enabled. Store that setting outside any RAM the original game initializes.
Do not put a gameplay pause-help line on the game title (user found it confusing).

During active play any keypad key pauses, and a **new** keypad press/resume
requires release again. Freeze logic, sprite auto-motion, gameplay timers and
speech queue consumption together; mute output while paused and restore effects
or resume queued speech afterward. Save/restore the message row if displaying
PAUSED. Merely waiting in the main loop while the ISR moves sprites is wrong.
Do not make fire pause the game. This mapping supersedes numeric gameplay keys
where all keypad keys are assigned to pause; document any displaced controls.

At game over show `PRESS * REDO OR # BACK`, centered from its actual encoded
length. REDO starts another ordinary game; BACK returns to a visible, reusable
game title. Require release at **every** discrete startup/title/toggle/pause/
resume/replay transition. A timer-based repeat delay is not a release gate.
Gameplay directions and firing remain continuous controls. Test all twelve
keypad keys and both fire buttons, long holds, release/new press, natural game
over, persistence, and a mutation removing the actual assembled release gate.

Keep new UI code in a measured free switched-bank region when fixed ROM is
tight. Use a fixed-bank trampoline preserving the caller's mapping and registers.
Budget UI data, speech, selector addresses, queue RAM, saved rows and stack
together. Restore the original entry VRAM after the startup screen so the game
starts from the same machine state. UI and decorative terrain patches belong
in editable assets/generators; regenerate source-derived output together.
Retain source-ROM algorithm checks in dev/lockstep and separately test intended
release differences. The normal `game.rom` must remain the review handoff.
