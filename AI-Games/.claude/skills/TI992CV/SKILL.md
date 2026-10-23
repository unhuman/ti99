---
name: TI992CV
description: >-
  Port a TI-99/4A game to the ColecoVision by statically translating its
  TMS9900 code (and the parts of the TI console ROM/GROM it uses) to Z80
  assembly, built as a 32 KB cart or a MegaCart. The inverse of CV2TI99.
  Covers the inputs you must get first (the game's ROM banks, the TI console
  ROM and GROM), feasibility checks (GPL/GROM games, 32K-RAM games, speech),
  the trace/annotate/translate/build/lockstep pipeline, the big-endian
  workspace-in-RAM register model, lazy TMS9900 status flags, the console
  ISR replaced natively (sound lists, sprite motion, VDP timer), the TI
  keyboard rebuilt from the Coleco controllers, the Coleco cart header and
  front end, and the Coleco-only hazards (NMI, VDP write speed, 1 KB RAM).
  Load before starting or changing any TI-to-ColecoVision port.
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

**Status of this skill (2026-10-21): the first port (Parsec,
`Decompiled/CV_Target/Parsec`) is at the feasibility stage; §10 has what it
has found so far.** It is the
CV2TI99 method inverted plus what is known about both machines. Treat every
hardware fact here as something to confirm against the existing emulators
(`Decompiled/CVZaxxon/tools/z80emu.py`, `ti99emu_base.py`, `vdp.py`) before
relying on it. Rewrite the parts that turn out wrong, and add the lessons
(with dates) as the first port finds them, the way CV2TI99 grew.

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
3. **Speech** (`>9000`/`>9400`, the speech synthesizer): the Coleco has none.
   Ask whether to drop it or substitute a sound effect.
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

**Memory stays byte-identical and big-endian.** TI scratchpad `>8300-83FF` →
Coleco `$7000-$70FF` (one constant offset); expansion-RAM bytes the game uses
go into the rest of the 1 KB (or SGM RAM) through a table the translator
applies to every absolute address; cart data stays at a known offset in ROM.
Keeping TI byte order means:
- lockstep compares raw RAM bytes directly;
- pure word copies need no swap (`ld hl,(src) / ld (dst),hl` moves the two
  bytes unchanged);
- **arithmetic, compares and address use of a word need a byte swap** (load
  the high byte into H and the low into L, or compute bytewise). Forgetting
  the swap is silent: values are plausible and wrong. `insntest.py` must
  cover every arithmetic form with random operands.

**Registers live in RAM at WP + 2n, as on the TI.** TMS9900 code can and does
read its registers as memory (`MOV @>8302,R0` is R1 when WP = `>8300`), and
`BLWP`/`RTWP` switch workspaces, so registers stay in RAM. Resolve WP
statically per routine (from `LWPI`, `BLWP` vectors and the ISR's GPLWS
`>83E0`) and make the translator **fail** where it cannot. Start with every
register access going to memory (correct first); then cache registers in
HL/DE/BC within basic blocks, writing back at block exits, calls and any
instruction that can address that register as memory.

**Byte operations work on the register's HIGH byte**: the first byte in memory
(`WP+2n`). `MOVB R1,@X` stores the byte at `WP+2`; `SWPB` swaps the two bytes
in place.

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

**The console ISR becomes a native routine**, run at poll sites (loop heads and
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

**Console routines called by the game** (KSCAN, GPLLNK/XMLLNK) are natives:
KSCAN reads the virtual keyboard (§5) and fills `>8375` (key), `>8376`/`>8377`
(joystick Y/X) and `>837C` (status, new-key bit) exactly as the reference
does for each keyboard mode in `>8374`. GPLLNK font loads copy the bytes from
the console GROM into ROM at build time and write them to VRAM natively.
Games that read GROM directly through `>9800`/`>9802`/`>9C02` get a GROM
address/data emulation over an embedded copy of **only the ranges read**
(measured with the reference). Sprite and VDP behaviour needs nothing: same chip.

## 5. Controls: a virtual TI keyboard

Rebuild the TI's 8x8 keyboard matrix (and the two joystick columns) from the
Coleco controllers once per frame. All of the game's own CRU keyboard code and
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

**Each keypad key has one meaning across the whole game** (ti-input-screens
skill: a key that dismisses one screen must not act on the next). Reading the
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
  Coleco build's prologue) and check it in `z80emu.py`. Use `$AA55` with the
  game's own name, publisher and year, the inverse of CV2TI99's TI994AVISION
  rebrand (ask the user what the title line should say).
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

Unlike CV2TI99, speed is not expected to be the main problem. The Z80 executes
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
  launch**. If approved, ColEm needs `-ntsc -sync 60` (CLAUDE.md: its default is
  unsynchronised) and CoolCV needs scan-coded synthetic keys. Until then, rely
  on `z80emu.py` screenshots plus lockstep.
- Put every candidate cart in `build/` and tell the user the path.
- Keep `README.md` (controls mapping, what differs from the original,
  measured speed, RAM map) in sync with every change.
- Check for another agent (Codex) working in the same folder before editing.
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
then compare matching phases with real frame timing. The current opening
is 132 Coleco frames versus 133 TI frames; the previous release took 236.
See the game's README for all measured phases and tolerances.

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
