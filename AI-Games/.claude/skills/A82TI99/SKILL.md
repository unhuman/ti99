---
name: A82TI99
description: >-
  Port an Atari 400/800 (6502) game to the TI-99/4A by statically translating
  its 6502 code to TMS9900 assembly, built as a bank-switched cart. Covers
  getting the real program out of a disk image (boot loaders, crunchers,
  frozen snapshots), the headless Atari reference machine that needs no Atari
  OS ROM, the survey tools (coverage, CPU profile, pointer sites), the
  translator and its flag model, the TI memory map and runtime (real VDP
  interrupts, bitmap write-through, keyboard, text screens), the cart build,
  and the checks. Load before starting or changing any Atari-8-bit-to-TI port
  (Decompiled/Aztec is the worked example). Use assess-retro-port first when
  the question is whether a game is worth porting.
---

# A82TI99: Atari 400/800 → TI-99/4A

Sister of CV2TI99. The two machines share nothing but the era: different CPU,
video and sound. So this is a translation of the game's *logic* onto a native
TI runtime that stands in for ANTIC, GTIA, POKEY and the Atari OS. The tools
are in `tools/` of this skill and are generic; a game supplies `tools/ann.py`
(annotations) and `src/game.a99` (its TI natives).

**Status (2026-11-13): first port (Aztec) plays in Classic99, passes
lockstep, and runs at 75-80% of the Atari's game speed after native blits.** Done and checked: unpacking, reference machine, surveys,
translator (`insntest65.py`), runtime, 128 KB cart build, whole-game lockstep
(`lockstep65.py`: 6 runs x 2,500 frames, 0 differences), free-running soak
with real interrupt timing (8 x 12,000 frames, no crash). **Not built yet:**
sound, the one-command gate runner, speed against the Atari, native rewrites
beyond the screen clear. Until those exist a port made with this skill is an
intermediate build; say so when handing it over. The
[open work list](#7-open-work) is the order to do them in.

## 1. Inputs

| Input | What | Notes |
|---|---|---|
| Game image | `.atr` disk, `.xex` executable or cart dump, the user's own | Never download one |
| TI console ROM + GROM | `994arom.bin`, `994agrom.bin` in the game's `tools/roms/` | Copy from another port in `Decompiled/` |
| xdt99 | `xas99.py` (`XDT99_DIR`) | Same as CV2TI99 |
| Atari OS ROM | **not needed** | The reference machine does the OS services itself |
| Altirra | optional | Only for a second opinion on video or sound; it carries its own OS replacement, so no Atari ROM either |

Python: Cygwin `python3.9`, standard library only. Nothing to `pip install`.

## 2. Get the real program out

Disk images are rarely the game: expect a boot loader, a cruncher and maybe a
frozen memory snapshot. Run the image's own unpacking code in `m6502.CPU` until
it jumps to the game, then keep the memory image. Aztec had three layers
(`Decompiled/Aztec/assessment/tools/unpack.py`, `unpack2.py`). Things that
cost time there:

- An unpacker can depend on what an unused hardware register reads (`LSR
  $D017` decided a branch). GTIA's unused read registers return `$0F`.
- A snapshot's vectors hold XL OS addresses (`$C0E2`, `$C28A`); `a8emu.ALIAS`
  maps them to the published entries.
- **Model every step of a loader stub, or none.** Aztec's stub parks
  `$BC00-$BFFF` at `$0700` across an OS warm start and copies it back. Doing
  only the copy back destroyed 1 KB of packed data, and the last stage then
  produced 2,000 wrong bytes at the top of memory: garbage where the game's
  messages and status text should be. Everything still ran, and lockstep was
  clean, because **the reference machine ran the same damaged image**.
  Before trusting an extraction, read its text: dump the string tables and
  look at a reference picture for words (`STRENGTH`, `BULLETS`).
- Crackers add trainer menus. Find the game's own cold entry (Aztec: the menu
  sets DOSINI to `$40CE` and warm-starts) and start the port there.

## 3. Reference machine and surveys

`a8emu.Atari` is the oracle: exact documented-opcode 6502 with cycle counts,
ANTIC per scan line (display list, DMA cycle stealing, DLI, VBI, WSYNC,
VCOUNT), register files for GTIA/POKEY/PIA, and the OS services a game
reaches done in Python at trap addresses (SYSVBV, XITVBV, warm start, SIO).
An unknown ROM entry stops the run with its address: add the service.
`rng='soft'` replaces POKEY RANDOM with the generator the TI runtime uses, so
both machines can play the same game.

Run these before designing anything (Aztec's copies are in its `tools/`):

| Tool | Answers |
|---|---|
| `play.py` | Does it run; pictures; decoded text screens |
| `extent.py` | Which pixels of the 320 the game uses (TI has 256) |
| `cover.py` | Bytes executed, read, written: the RAM the port needs |
| `prof.py` | Where the Atari's CPU time goes. **Read this before worrying about speed** |
| `survey.py` | Self-modifying code, indirect jumps, hardware and OS references |
| `ptrsites.py` | Which region each computed address touches (per-site mapping) |

The TI executes roughly a quarter as many simple instructions a frame as the
Atari (about 1,500-1,850 against about 7,000 in a hi-res mode). A straight
translation is therefore only full speed when the game mostly waits. Aztec
spends 84% of its cycles in two frame-wait loops, which is why it works.
A game that is busy all frame needs the native-rewrite plan from the start.

## 4. Translator (`xlate65.py`)

Registers: A = R1 high byte (low byte 0), X = R2 and Y = R3 zero-extended, R4
computed address, R5/R6 byte temps (low bytes 0 and 1), R7 data stack, R9 =
`>0100`, R10 return stack, R13 = workspace, R14/R15 for status-preserving
sequences. The low byte of a register is addressable (`@XLB` = `>8305`), which
is what makes X and Y cheap.

- **Flags live in the TMS9900 status register**, only where a later
  instruction can read them (liveness across calls and returns). A sequence
  that would destroy a live flag is wrapped in `STST R15 ... LI R14,$+6 /
  RTWP`, which restores the whole status register. Far calls, far jumps and
  flag-returning RTS use the same trick.
- Carry after CLC/SEC is a known constant until something needs it.
- A compare read only by the branches right after it becomes `CB`/`CI` with
  `JL`/`JHE`; otherwise it is a real subtract so C is the 6502's.
- **R0 cannot index** on the TMS9900; computed addresses use R4.
- Self-modified operands become pointer cells read at run time. A
  self-modified JMP/JSR needs an annotation.
- `JMP (vec)` dispatches through a table of targets (static scan for
  `LDA #lo / STA vec / LDA #hi / STA vec+1`, plus what `ptrsites.py` saw).
- Not supported, and reported at translate time: decimal mode, PHP/PLP, TSX,
  the V flag, BIT that needs both N and Z, zero-page index wrap, `(zp,X)`.

`insntest65.py` checks random snippets (with a flag observer, inside and
outside subroutines) against the reference CPU. Run it after every translator
change; it exits nonzero on a mismatch.

## 5. TI side

**Memory.** The Atari's 48 KB does not fit linearly in the TI's 32 KB, so
addresses map by region, statically where the address is static: zero page to
scratchpad, the main data region with one offset K, the screen with another,
and "islands" (data runs inside the code area, self-modified operands) packed
into free RAM. Computed addresses are mapped per site from `ptrsites.py`
('S' screen, 'D' main, 'F' font, 'I:xxxx' one island, 'M' decided at run time
by `PTRMAP`). Hazards found:

- The console interrupt routine owns `>8379` and `>837B`. Zero page mapped
  across them is corrupted every frame; split the mapping around them.
- A game can read the OS character set at `$E000` to draw its own text. The
  runtime copies the console's font there instead (so the reference machine
  must be given the same font).

**Interrupts are real, not polled.** The game's VBI and DLI handlers run from
the console ISR's user hook (`>83C4`), with the translated code's workspace
saved and restored around them. Wait loops like `LDA $BD / CMP $BD / BEQ`
then work unchanged. The hook must read the VDP status itself or the
interrupt fires again immediately. The stock `tiemu.py` has no real
interrupts; `ti65.py` adds them.

**Screen.** A hi-res bitmap goes to the TMS9918 bitmap mode through a RAM
shadow (the game reads the screen back) plus a write-through to VRAM
(`SCRST`), clipped to a 32-byte-column window. Text display lists become
Graphics I screens drawn from a table built at build time. `src/game.a99`
watches the display-list shadow to switch between them.

**Build** (`build65.py`): shared segment (runtime, natives, tables) at the
start of every 8 KB bank, translated code in code banks with `FARC`/`FARJ`
across banks, RAM image copied out at power-up from the free tails of the code
banks first and then from payload banks (each `PAYT` entry has its own source
address). Growing the shared segment grows `PAYT`, so raise `shared=` with a
little slack. The build
checks every label address against the assembler's, so a wrong size model
fails instead of producing a broken cart.

## 5A. Faults the first port hit (check each in a new one)

- **A return address needs its bank.** A routine can continue in another bank
  through a far jump (the build splits long flows), so a near call that pushed
  only the address returned into the wrong bank and ran through empty ROM:
  wild writes, a long beep from the sound chip, a frozen picture. Every call
  frame is now (return, bank) and every RTS goes through `RETF`/`RETN`.
  **Lockstep did not catch it** in 15,000 frames; the soak did in 2,000.
- **Zero-page indexing wraps.** `DEX / BPL` leaves X = $FF and `STA $EB,X`
  then means $EA. A static `@base(R2)` walked off the scratchpad into the
  sound chip at >8400. `zp,X` and `zp,Y` now go through `ZPMAP`.
- **Lockstep and soak find different bugs; run both.** Lockstep delivers
  interrupts at instruction boundaries with scripted input; `soak.py` runs
  the cart free with the console's real interrupt and watches for a bad
  workspace pointer, execution outside the cart, sound-chip writes and a
  stalled frame counter. `crashtrace.py` replays a failing soak and prints
  the jumps before it.
- **Boot order.** Anything the runtime builds in RAM (the font copy) must
  come after the RAM image is copied, and every RAM area that holds islands
  must be in the payload list.
- **Handlers see the interrupted A, X, Y** on the Atari. The glue reloads
  them from the saved workspace and pushes them for the vertical-blank
  handler, which also lets lockstep compare registers inside handlers.
- **Display off means "don't draw yet".** Games turn ANTIC off to clear and
  redraw. Blank the VDP, keep writing the RAM shadow only, and send the
  finished picture once when the display returns (`SCROFF`, `REDRAW`).
  Without this the player watches thousands of slow single-byte updates.
- **Instructions that emit no code** (CLC, SEC, CLD, NOP) share a TI address
  with the next one; the lockstep keeps a list per address.
- CPU-bound phases run at about a sixth of the Atari's speed (Aztec's
  dungeon generator: 19 frames there, about 180 here). Profile with
  `tiprof.py` and replace the worst routine first.
- **"Frame-paced" is not "unaffected".** A game that needs N frames of work
  per step and gets it in N frames on the Atari runs slower on the TI as soon
  as a step overruns. Aztec's straight translation ran 9 game steps a second
  against 20. Players feel it as controls that misbehave: walking and running
  are told apart by how long the stick is held, counted in steps. Measure
  steps a second against the reference (`passrate.py`, the main loop's phase
  counter; Aztec's `tools/passrate.py`) in a quiet and in a busy room before calling a port playable.
- **An interrupt handler that runs past the next vertical blank runs twice in
  a row.** The VDP interrupt is pending when the handler returns, so it is
  taken before the game executes an instruction. A wait like `LDX $BD / INX /
  INX / CPX $BD / BNE` then sees the frame counter step over its value and
  waits for it to wrap: Aztec froze for up to four seconds after every room
  change (`REDRAW` plus the VBI's beam-timing delay loop ran in the handler).
  The glue now drops the interrupt that piled up (`VB3`), and the delay loop
  is native. **Lockstep cannot see this** (it delivers interrupts at
  instruction boundaries); look for long stays in a wait loop with
  `tiprof.py` or by sampling the program counter each frame.
- **The runtime's variable list must not grow into the interrupt glue's
  save area.** `VARS` sat below a fixed `SAVWS` at `+>40`; the blit's new
  variables overlapped it, so every interrupt overwrote them mid-blit and
  sprites were drawn to the wrong place in VRAM only. Lockstep was clean (its
  interrupts never land inside a native) and so was the soak; `vidhook.py`
  (VRAM against the shadow at every native's return) found it in one run.
  `build65.py` now fails when the list reaches `SAVWS` (`+>80`).
- **Natives must leave A's low byte zero** (R1 low byte), like CV2TI99's rule.
  A DIV into R1 in Aztec's character native left `>20` there; lockstep caught
  it at the first call (`registers: TI A 3C20`).
- **Replacing a loop:** `REGION = {start: (native, exit)}` in `ann.py` puts
  `BL @native / JMP exit` at the loop head, `DEAD` drops the body from the
  translation, the exit becomes a label, and the lockstep lets the 6502 run
  the region to its exit. The native must leave every register, flag the
  exit reads, and memory cell as the loop would. Order inside the native is
  free when each byte is independent: Aztec's blit draws full rows column by
  column so the VDP's address auto-increments down each character cell, and
  only the row that ends the blit goes byte by byte.
- **A Datamost-era game often has several versions.** Instructions found on
  the internet for Aztec describe the keyboard-driven Apple II game; the
  Atari version is joystick-only. Check the controls on the reference machine
  before mapping keys.
- **`MOVB` leaves the low byte; compare a loaded byte only after masking.**
  `TXTDRW`'s new "$FF = blank" test used `CI R4,>FF00` straight after
  `MOVB *R3+,R4`. The low byte still held the VDP address, so it never matched
  and the menu kept showing rows of `_`. Use `ANDI R4,>FF00` first, or `CB`.
- **Unwritten text memory shows up before the menu does.** The game clears its
  text screen to $FF and writes the menu frames later. A text refresh that
  runs in between draws junk. Draw $FF as a blank, and refresh often (Aztec:
  every 8 frames) so the text appears promptly.
- **Disk paths in a cracked image can crash the original.** Aztec's menu key L
  loads a saved game. With no drive, `JMP ($009D)` is still 0 and the 6502
  jumps to `$0000`. Random-key soaks find it as a TRAP from the indirect-jump
  table. Disable the key with a `PATCH` rather than modelling a disk. A
  `PATCH` can carry its own label as `('LABEL', name)`. A bare label string
  gets indented and is assembled as a mnemonic.
- **Front-end text belongs in the natives bank.** Aztec's ~2 KB of
  instruction pages in the shared segment cost a bank in every executable
  bank and pushed the cart to 32 banks. `BANKED` takes a list of `src` files,
  `g.banked_lines()` adds generated tables after them, and `g.NBRES` sizes
  the reserve. Size it to `NBEND`; the rest of that bank holds payload.
- **Animate front-end figures with the game's own shapes and pace.** Aztec's
  user rejected a sprite sliding diagonally down a picture's stairs. Find
  the shapes by hooking the reference machine's draw routine. Aztec's is at
  `$5458`, with the self-modified shape operand at `$5483`. Log the pointer,
  the screen address and the state each pass. Read the shapes from the game
  image and plan the path on surfaces measured from the converted picture.
  Use the commonest line under the feet, since stray dots mislead. Check
  every frame offline before building. A large path and pattern set can go
  in a data blob that the picture copier sends to VRAM that is free while the
  picture shows (Aztec: the text names). That keeps it out of the natives
  bank.
- **A picture can replace the game's menu by patching its key wait.** Aztec
  patches `LDA CH` at the menu's key loop with a native: it shows the title
  picture, runs `KSCAN` itself with interrupts off, applies the menu's own
  key test, and leaves the accepted code in CH for the original code. When
  the tools stub the native out, the patch still reads CH, so lockstep is
  unchanged. `KSCAN` leaves its column count in R1's low byte. Clear R1
  before `MOVB @CHV,R1`, or a word compare such as `CI R1,>0D00` never
  matches. Take a picture's own text out at conversion time
  (`apple2ti.ERASE`). For text over the art, grow the surrounding picture
  inward ring by ring: copying the lines above and below makes bars, and one
  colour makes a slab. Then draw clean text from the font in RAM into the
  bitmap.
- **Credits on a replaced screen (user's rule, Aztec 2026-11-14).** The port
  line reads **"<build year> PORT BY UNHUMAN"**, e.g. `2026 PORT BY UNHUMAN`,
  not the CVBasic games' "UNHUMAN AND AI C&C". A screen that replaces one of
  the original's must keep that screen's authorship. Aztec's text menu said
  `DESIGNED BY PAUL STEPHENSON` and `(C) 1982 DATAMOST, INC.`, and both lines
  now sit at the foot of the title picture that replaces it. Dump the
  original's text screens from the reference machine before hiding one.

### 5B. Colouring a one-colour Atari game (Aztec colour cart, 2026-11-14)

- **Colour through the blit natives.** Every figure already passes through
  the native blit engine, so hang a colour pass off it per blit kind (player,
  weapon, creature draw/restore, fixture). Add build variants with an `.IFDEF`
  and an environment flag (`AZTEC_COLOR=1`, `tools/build.py color`) rather than
  a run-time switch: the plain cart keeps its speed and its lockstep.
- **Find the creature type from the game's own slot table** (Aztec
  `$19CA,slot AND 15`) by surveying shape pointers on the reference machine;
  then a 32-byte ROM table gives the colour.
- **Fixtures are not blits.** Boxes and rubble come from their own drawers. A
  `PATCH` at the instruction after the drawer has its final row in hand
  (`$74E7` box, `$75A7` pile) calls the native with the rectangle. Keep them in
  a small per-room list so restores and creatures' blank cells give back the
  fixture's colour, and merge line ranges when the same spot is stamped twice.
  **Find every drawer from the screen, not from the routine you know.** Aztec
  has a third object drawer (`$7638`) that draws the same rubble art; its
  heaps stayed magenta, and the colour gate, which learns fixtures from the
  patch hooks, passed. Locate an object's writer by watching its shadow cells
  and naming the BANK-QUALIFIED label before the change (`labels.json` gives
  `[bank, address]`; a bare TI address names different code in every bank).
- **Squeezed pairs.** One TI column takes two shadow bytes. The ink test
  must OR both bytes' masks (or one at the edges); a one-byte test leaves
  half-coloured figures. Mutate it in the gate.
- **The order is the priority.** With no RAM for a per-cell owner, write
  the colour after the shadow/squeeze pass and skip the player's rectangle
  in every other pass. That leaves only small, declared stale cases.
- **Running from the cart bus costs 400-500 cycles a line** and the
  scratchpad is full: the first colour pass cost 24% of play. Gains came
  from skipping work: per TI column with VDP auto-increment; holding a
  restore and merging it with the matching draw (skip the lines it covers);
  skipping a player who did not move or change shape; flushing the held
  restore before anything else. Now ~19%.
- **Squeezed text loses a letter in nine.** A squeeze that is right for the
  picture merges text. Move text unsqueezed, but per character (Aztec's
  `SQCHR` marks a character refresh, column + 64, and `SQRB` places it at
  TI column - 3 without the squeezed pass); a static unsqueezed column range
  misaligns stairs that cross the band. Survey where every text, popup
  included, is drawn (hook the character drawer: line, column, code) before
  choosing the columns: Aztec's first range covered the counts but not the
  popups, and the user saw "abbreviated" messages.
- **`JL`/`JH`/`JLE`/`JHE` are UNSIGNED on the TMS9900; `JLT`/`JGT` are signed.**
  Aztec's band-text marker tested `CI R4,64 / JL`, and a blit starting left
  of the screen has a negative column (`>FFFE`), so it was taken for a
  marked character and the figure's left-edge part was lost. vidhook found
  it (seed 1, a creature at the left edge). Use `JLT`/`JGT` wherever a
  value can be negative.
- **When the natives banks are full, a native can be a `PATCH` body.** It is
  placed inline in the code bank that holds that 6502 address, which the
  packer sizes; labels go in as `('LABEL', name)` (`ann.asm_lines` parses
  column-0 labels). It must leave A, X, Y and the flags exactly as the
  replaced instruction does (end with that instruction's own load), and
  keep R14/R15.
- **Some effects are not blits.** Aztec's dynamite blast saves a block,
  animates in it and puts it back, all synchronously. Find such drawers by
  watching the screen shadow and naming the bank-qualified label, then
  colour the block before and restore "what is behind" after.
- **Size a per-room list from the game's tables, not from the rooms play
  reaches.** Aztec's fixture list held 10; the tables give up to 11, and an
  opened box restamps itself taller. The heap (stamped last) and the lid
  fell off, and restores painted them magenta, reported twice by the user
  while every gate passed: random play visits two rooms. Count per room
  from the tables, key restamps to one entry, check the list's count
  against the model, and force crowded rooms in the gate (`colcheck --room`).
- **The same picture can come from two code paths; patch both, and teach
  the checker from the game's routine, not from your patch.** Aztec's box
  lid is drawn by the box drawer at room build AND directly by the
  open-box code in play. Only the first was patched, and the checker
  learned fixtures from the patch, so it agreed. Hook the drawing
  routine's own entry (`$7512`) in the model. Also: a native that stores
  state in a shared variable, then calls a helper first (a pending
  restore), must not trust that variable afterwards. Aztec's `CFIX` kind
  in `BXC` was overwritten and opened boxes turned gray.
- **Build every room in a gate, not just the ones play reaches.** Poke the
  room coordinates at the room builder's entry from a snapshot taken just
  before it (Aztec `tools/roomscan.py`, `$6F90` / `$8B`,`$8C`), then compare
  the whole picture exactly. A checker allowance ("either form is fine in
  the popup columns") hid stairs broken in the status band after a popup
  fix; the exact compare after a full refresh has no allowance, and its
  mutant must fail on the rooms with the feature.
- **Squeezed text needs its cells free; find what the game prints there
  before squeezing ornaments around it.** Aztec prints the item names
  (PISTOL, MACHETE, THE IDOL) from Atari column 24 into a right-hand
  ornament; squeezing that region cut MACHETE to MACTE. The fix was
  mapping the whole text region unsqueezed and replacing the ornaments
  with the TI's own, smaller and symmetric (user's choice). A static TI
  overlay costs least as cells the squeeze never writes, drawn once at
  each screen clear (`TXC` 2, `ORNDRW`); rewriting it on every refresh
  overflowed both natives banks. Also colour band text through the
  same path as the fill: the band's fill once covered rows 0-20 only, and
  stairs crossing the band showed white.
- **Zero page is in the scratchpad (`>83xx`).** A checker that reads it from
  the expansion RAM array reads zeros. Hooks read `t.scratch`.
- **A second natives bank (`BANKED2`) can overrun silently into the next
  bank's code.** Grow `NB2RES` when its end label passes the bank end, and
  check that the runtime variables stop below the colour RAM (`RAMLO`,
  build65).
- **Natives called from translated code keep the translator's registers.**
  R5/R6 (R6 low byte = 1), R14/R15 and R11 must survive; push them on R10.
  The first colour cart "freaked out" because `CBOX` did not.
- **The gate (`colcheck.py`)** models the rules from hooks and compares the
  colour table after each blit. It must name what it saw (player, creature,
  room) and fail when blind, and one mutant per rule must fail: no restore,
  creatures ignoring the player, one byte per TI column. A mutant can pass a
  seed once timing changes (no overlap left in that run); pick a seed per
  mutant that exercises it.

### 5C. Sound: POKEY to the SN76489 (Aztec, 2026-11-15)

- **Start from the shadows.** The translator already keeps every POKEY
  register in RAM (the `$D200` block of hardware cells), so sound is one
  native run once a frame from the game's `FRAMEV` hook (in the interrupt),
  mapping them to the chip. No translated code changes, so lockstep is
  untouched. Read the game's driver first: Aztec's is a table of
  (frames, AUDF, AUDC) steps per effect, and it was all noise.
- **The mapping** (AUDCTL 0, 64 kHz): pure tone (AUDC distortion 5/7) ->
  a tone, divider 3.5 × (AUDF + 1); any poly -> the noise channel clocked
  by tone 3 (kept silent) at 1.75 × (AUDF + 1), because POKEY's noise is
  sampled at 64 kHz / (AUDF + 1) and the SN's noise shifts once per tone-3
  period (111,861 / N a second). The 4-bit poly (`$C0`) -> periodic noise
  (both repeat every 15). One noise channel against four: the loudest wins.
  Volume: linear to 2 dB steps, round(-20 log10(v / 15) / 2).
- **Write only what changed.** A noise-control write restarts the noise
  generator; rewriting it every frame changes the sound. Keep the last
  value sent per register, and return at once when every POKEY volume is 0
  and the chip is already quiet (Aztec: 2,300 -> ~270 cycles a frame).
- **Mute where the interrupt stops or never runs**: before a native that
  holds the interrupt for frames (`REDRAW`) and on front-end screens that
  poll with interrupts off. Otherwise the last noise hangs on.
- **"Unused" 6502 RAM is not free.** A comment said 6502 `$0400-$0AFF` is
  unused by the game; the runtime's stacks live there (`RSTK` `>2AF0`
  growing down). Sound state put at `$0AC0` overwrote the R10 stack and the
  cart crashed within 300 frames. Check `STACKS` and every `EQU` in the
  generated source before claiming RAM; Aztec's is at `>2160`, past the
  hardware cells, with a build assert.
- **When the shared segment and the natives banks are full**, build65 takes
  a third natives bank (`BANKED3`, `NB3RES`, `NB3SEL`). Aztec's `N3CALL` is
  `NBCALL`'s body with that bank's select: only callers with interrupts off
  (the interrupt itself, the title), since it leaves them off.
- **The gate (`sndcheck.py`)** rebuilds the chip from every byte written
  to `>8400` and compares it, at the next call (so the quiet fast path is
  checked too), with POKEY's registers worked out independently. Random
  play reached 3 of Aztec's 5 effects, so the gate starts each effect in
  the game's own driver slots, writes the other channel's tick and a pure
  tone, and fails if any was never heard. Mutants: every register every
  frame, the noise clock an octave off, the fast path taken while sounding.
  Its first unchanged-control test passed the always-write mutant: `b & 7
  == x` is `b & (7 == x)` in Python, and the only noise in random play
  lasted one frame. Run every mutant before trusting a pass.

## 6. Working practice

- Tools that import each other live in one folder: **never name a script
  after a standard module** (a `dis.py` there broke `import inspect`).
- Bash heredocs feeding `python -` hang or fail here; write a file and run it.
- A launcher that types `2` to pick the cart from the TI menu also answers a
  game menu that takes digits (Aztec started at difficulty 2). Check what the
  game does with the keys the launcher sends.
- Keep the game's `README.md` and `DESIGN.md` in step with every change, and
  leave the newest cart running in Classic99 (repo standing rules).

## 7. Open work

In this order, for Aztec and so for the pipeline:

1. ~~Lockstep~~ done (`lockstep65.py`, `soak.py`).
2. ~~Sound~~ done (§5C, `sndcheck.py`).
3. **Gate runner**: one parallel command, mutation self-tests (CV2TI99 §0).
4. **Speed against the Atari**: `passrate.py` (game steps a second) and
   `tblank.py` (blank spans) exist; Aztec's blitters, character drawer and
   generator bit loop are native. Next: interrupt glue and keyboard scan,
   the generator, `REDRAW`.
5. ~~Cart size~~ done: banks are repacked with the real branch sizes (Aztec 128 KB).
6. Front end: TI-style title, FCTN 8/9 back to the menu, save-game decision.
