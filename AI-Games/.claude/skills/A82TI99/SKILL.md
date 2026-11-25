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
- **Colour a squeezed column only from the bytes that show in it**
  (2026-11-17). With 9 bytes squeezed into 8 TI columns as
  `(b[k] << 8 | b[k+1]) << (k + 1)`, column 8g + 7 is byte 9g + 8 with only byte 9g + 7's last pixel merged
  into its first, but the byte-to-column table still listed 9g + 7 there. A creature inked in
  that byte painted the wall beside it grey. Put the rule in the ONE routine
  that maps bytes to columns, because every colour writer must agree. A
  draw that skips a column its merged restore still assumes is covered
  leaves stale colour. So does a tint (the blast) that covers a column its
  restore skips. A mutant that restores the old rule can pass a run that has
  no figure in such a byte, and in these carts it also changes timing, so
  the game takes a different path. Force the case: Aztec's `colcheck
  --pilewall --room 01`, and catch an unexplained writer by hooking
  `vdp.write_data` for the bad cell and printing the PC's label.

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
  (both repeat every 15). One noise channel against four: **the youngest
  noise wins**, then the loudest. Loudest-first was wrong. Aztec's fuse is a
  sustained full-volume hiss that the game keeps rewriting on channel 4; it
  won every tie, so no footstep was heard while it ran. The user reported
  this as "walking sounds still cut out" and "high pitched noise". On the
  Atari the two mix. Count each channel's age in calls, and hold a new
  source for the same minimum time as a volume.
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
- **Hold a sound for the time the game meant, not for one interrupt.** The
  translated code holds `LIMI 0`, so TI interrupts come 10,000-95,000 cycles
  apart (a frame is 50,000). A one-frame footstep switched on late and off
  early sounded for milliseconds, and the user reported "intermittent"
  footsteps. Measure real time with the TMS9901 decrementer (CRU 0 = clock
  mode, load bits 1-14, read them back latched; 3 MHz / 64) and keep each
  volume on until 0.92 frame has passed since it started. Give each volume
  its own start time: with one shared time, a new tone kept a finished noise
  on. The emulator needs the timer modelled (`ti99emu_base.py clk_*`); the
  gate fails any sound under 0.85 of a frame, and its `nohold` mutant must fail.
  The 9901's clock register is 0 at power-on, so the timer stands still and
  every sound would be held for good. Start it on the mapper's first call
  (a flag the boot clears), not only on the title: the tools skip the title.
  Pick mutant seeds that actually cut a sound short (Aztec's colour seed 1
  never did).
- **A free-running timer's age wraps.** The 9901 turns every 0.35 s, so a
  longer sound read modulo a turn looks young about 4% of the time. Mark a
  sounding volume "past the hold" as soon as it is, and stage the wrap in
  the gate: end a long noise at the mapper's entry exactly where its age
  modulo a turn is small. Chance would hit it in a few runs at most.
- **The masking was invisible to random play.** Of 2,000 footstep frames
  across four seeds, one overlapped another noise. Stage the overlap (a
  footstep inside the hiss) and require it to be heard. Read every
  "sometimes" in a sound report as a sustained sound plus a short one.
- **"Inconsistent" sound can be inconsistent game speed.** Before changing
  the mapping, log when the game starts each effect against when the chip
  sounds, on both machines, from the same input. Aztec played every footstep
  it was asked for. The TI's creature pass took 12 frames against the
  Atari's 3, so the steps themselves were uneven: a speed problem.
- **Front-end animations with interrupts off** (Aztec's stairs walk) write
  the effect's chip bytes directly and call the mute/forget routine after,
  so the interrupt mapper does not trust a stale "last sent".
- **The game's interrupt handlers must get 8-bit A, X and Y (the runtime's
  `VBLH`, fixed 2026-11-15).** The Atari's VBI and DLI handlers see the
  interrupted A, X, Y, which are bytes. The glue passed the interrupted R1,
  R2 and R3 whole. Translated code keeps the other byte 0, but a native the
  interrupt lands in need not: Aztec's colour natives held R2 = `>1D00`.
  The driver's `LDA table,X` (`MOVB @tbl(R2),R1`) then read 7 KB off and
  played zero-page bytes as effect steps. Footsteps were silent while
  creatures were on screen, and stray rumbles and stuck slots followed.
  The user heard "lots of weird effects". `VBLH` now masks the handlers'
  copies (`ANDI R1,>FF00`, `ANDI R2,>00FF`, `ANDI R3,>00FF`); `RTI`
  restores the full words. A chip-against-POKEY gate cannot see this,
  because the broken driver wrote POKEY too. Check the invariant at the
  handler entries instead, with a mutant that removes the masks, and count
  the interrupts that land with dirty registers so the check cannot go blind.
  `pc_hooks` match any bank: limit them to the banks that carry the runtime.
  Lockstep never interrupts a native, so it passes this bug.

### 5D. The player as sprites, and speed in squeeze play (Aztec, 2026-11-16)

The user: "you should do the sprites for the player. Since he'd be the only
sprites, there will be no conflicts." `src/spr.a99` in Aztec is the example.
- **Leave the game's screen memory alone.** The game still draws the man
  into its bitmap (collision reads it). Only the TI side changes: his blit
  pair (Aztec `BL2` draw, `BL1` restore) skips the VRAM refresh and builds
  stacked 16x16 sprites from his mask. Lockstep stays exact for free.
- **Squeeze the sprites the way the bitmap is squeezed** (9 Atari pixels to
  8, per phase), or he slides against the walls he stands on. Every bitmap
  refresh must now exclude his pixels, so the picture under him is the room.
- **Double-buffer the patterns and send the attribute list in the
  interrupt** (Aztec: pattern sets `>1D00`/`>1E80`, `PSSAT` sent by the
  sound interrupt, `PSDIRT` while a move is unsent). Otherwise his new shape
  shows at the old place for a frame.
- **Checkers: compare the composed picture, bitmap AND sprites**, read from
  the SAT (`vexpect.sprite_ink`). The draw-to-interrupt gap and an in-flight
  refresh are legitimate differences: skip mid-draw frames and confirm a
  difference only when the next check repeats it. Every new excuse needs a
  mutant that must fail (`vidcheck --mutant nosat`, `vidhook merge|phase`).
- **A checker whose baseline resets on a mode change can hide the first
  bad write.** vidhook's mutants passed until that reset went. And print a
  difference AND exit non-zero: one gate printed it and exited 0.
- **The sprites removed whole colour paths**: blits no longer give way to the
  player's colour (`POV`, `CPINK`). Delete dead paths: they cost bank space
  (the colour bank overflowed by 116 bytes until they went) and time.

**Speed.** Measure with input keyed to the game's passes, never to frames
(`passbench.py`). A faster cart given frame-keyed random input walks into other
rooms, so its sums do not compare. Hash only screen memory at the end: equal
hashes prove the same game. The scratchpad holds frame counters, which differ
by design. Per-phase profiles (Aztec's `$AE`) then say which pass is slow.
Changes that paid in a squeeze cart (13% together, `FASTQ`, an
`AZTEC_SLOWQ=1` build keeps the old ones for A/B):
- blit loops with no VRAM test inside: the squeeze sends after the blit, so
  the per-byte "is this line visible" tests were dead weight;
- word reads in the squeeze where the shadow address is even;
- **hold a restore's rectangle** and send it as one union with the next draw
  that touches it (a creature moves as restore then draw over nearly the same
  cells). Flush it before any other refresh. What is sent is read from the
  shadow, so a late send cannot be wrong, only late; the video checker
  excuses held cells, with `lost` (never sent) and `union` (wrong edge) mutants.
`pc_hooks` match any bank: a profiler that labels by symbol alone puts
another bank's code under the runtime's names. Qualify by bank.

**Scripted states random play never reaches.** Aztec's dynamite needs a
crawl, a stop, and a fresh fire press (the instructions said so; six
single-input tries did not). Give one stick only: a second press lights
another stick and blows the first early, so the countdown is never seen.
`lockstep --fuse` scripts this. Stop short of game over, where a TI's own
title parts from the Atari's by design.

**A TI-only "fire continues" patch must want a NEW press.** Aztec's fire at
the end-of-game wait took a fire held as the man died, and the game-over
screen flashed by. Keep a TI RAM flag (`FIREUP`), cleared when the wait
starts and set once fire is seen up. In the check, hold fire into the wait
with the trigger shadow already showing held (`TRIGV`), not just the key
set. Otherwise the wait's first pass sees it up, then "pressed", and the
check passes the race on one cart and fails on the other.
Speeding a cart moved its game over onto a random fire, which is how the
gate found this.

**Second speed round (Aztec, 2026-11-16): per-pass waits, interrupt glue,
native scans.**
- **Find the game's frame waits and ask what each one is for.** A pass
  loop that waits for the next frame only to time a redraw against the
  Atari's beam idles on a TI whose passes already take longer than its cap.
  Aztec's `$440E` was 8-9% of play. Skip it (a TI-only `PATCH`), keep the
  cap wait (`$43DD`, the Atari's speed), and give lockstep the original
  back: patch the skip to a NOP in the harness (`tirun.exact_waits`), with
  a `--fastw` control that must diverge.
- **Pass-keyed input does not make two speeds play one game when the player
  acts per frame.** Aztec's `$448C` (stick, the man's action) runs from the
  VBI while `$AB` is 0. A faster cart gives him fewer actions per pass, and
  the screen hashes part, even though the random generator is per call. For
  a same-game A/B of other changes, put the skipped wait back
  (`passbench --exact`). Look for a per-frame player routine before blaming
  random numbers.
- **The interrupt glue is paid every frame.** Aztec's keyboard scan (17
  instructions a column) and two 16-word workspace copies were about 9% of
  play. A column with no key down now costs one `CB` (the column in
  `LDCR`'s high byte), and the copies move two words a turn. Prove such a
  rewrite exhaustively against a model of the old rules (`kscancheck.py`:
  every key, every pair, random sets; a mutant must fail).
- **Scan keys only where the game reads them (`ISRJOY`).** List every read
  of the OS key code (`$02FC`) first. Aztec reads it on the title (its own
  native scan), in the game-over wait, and at one play-time key, which saves
  to disk (a NOP on the TI). With `ISRJOY` defined, the runtime's interrupt
  skips `KSCAN`. The game reads the joystick column in its frame native
  through `KS6` (R2 = the column's rows, R3 = `KLAST`), which leaves `KLAST`
  and `CHV` alone. The waits that take any key call `KSCAN` themselves,
  interrupts off, once on entry so a held key is not new
  (`ann.py WKEY`, `firecheck --key`, mutant `nokey`). Fire is joystick
  column 6 of the same matrix, so it stays in the frame read.
- **Shift by b + 1 to merge.** In a 9-to-8 squeeze one `SLA` by b + 1
  leaves pixel b in C and pixel b + 1 on top: 8 instructions a byte, not 10,
  and no separate b = 0 loop.
- **Native slot scans with several exits.** A translated loop over object
  slots that calls a routine for a matching slot cannot be a one-exit
  `REGION`. `REGION` exits may be a tuple (`xlate65` labels them,
  `lockstep65` runs the 6502 to whichever comes first). The native tests
  the slots in the original's order, so A and X leave as the 6502 leaves
  them; set carry where it is live after the loop (`Translator.live`) and
  leave for the call through the original's own code, which returns into
  the translated INX/DEX and back to the head. **Do not put the native's
  loop label on the region head's own TI address.** Lockstep reads any pass
  through that address as the 6502 back at the head; start the patch with
  a NOP. Count the exits in lockstep and fail as blind without them; a
  mutant without the first test must diverge.
- **"Keep the sprites up between restore and draw" needs an end.** Aztec's
  blast death restores the man and never draws him, so his sprites stood
  through the death message and the game-over wait. Speeding the cart
  changed which games the random checks played and exposed it. Measure the
  normal restore-to-draw gap (0-6 frames) and take the sprites down past it
  (`PSRST`, counted in the frame interrupt), with a mutant that never does.
- Measure the "drawing is free" bound before restructuring a draw path:
  patch the send routines' first word to `RT` in every bank. Aztec's bound
  was 1.3x plain and 1.5x colour, and only 9% of squeezed bytes were sent
  twice a pass, so a once-a-pass dirty flush would not have paid.

### 5E. Byte-at-a-time screen loops, interrupt-shared state, pass timers (Aztec, 2026-11-16)

- **A game loop that stores a box byte by byte pays one refresh per byte.**
  Aztec's popups clear 18x24 bytes on opening and again on closing, and its
  fuse redraws an 8-line column every pass. Through the write-through, each
  byte was its own refresh (~8,000 cycles), so a popup cost about 3.5M
  cycles and the fuse made a pass 3.6 times longer. Find such loops with a
  probe on the write-through, keyed to the caller's 6502 PC. Replace each
  with a REGION native that writes the shadow itself and sends the rectangle
  once. Lockstep checks it (Aztec `--popup` fails blind if none ran).
  Batching the write-through with a deferred flush lost bytes; the region
  natives did not.
- **Anything a refresh started in the interrupt can overwrite, the
  foreground's refresh must get back.** The squeeze's working words
  (`SQL0`-`SQP0`) were shared, and the comment said the worst case was
  "which bytes are sent". For the status text's moved columns it was a
  different column's letters: garbage over the E of EMPTY. The runtime has a
  hook for this: define `ISRKN` and the game's `ISRKX`, which swaps those
  words at the interrupt's start and end. Put the hook in a natives bank if
  the shared segment is full; Aztec's costs about 5% of a busy pass.
- **Set CRU 21 high in the keyboard scan.** Low (the runtime never set it),
  a latched ALPHA LOCK pulls joystick UP's line down for good. A game that
  acts when UP is *released* (Aztec's weapon draw) then never acts. Classic99
  with Caps Lock on shows it; the headless checks never do.
- **A timer the game counts in passes runs long when the TI's passes are
  slow.** Aztec's fuse is 160 passes: 8 s on the Atari (3 frames a pass),
  18 s or more on the TI with the fuse drawn. Count it in frames, one step
  per Atari pass-length of frames, capped, remainder carried. Gate it with a
  JMP that `tirun.exact_waits` turns into a NOP, so lockstep runs the
  original decrement. Keep C as the original instruction leaves it (STST,
  then RTWP with the saved C) and set Z from the counter last.
- **Heredocs in a bash edit script turn `\\x10` into a real byte.** A patch
  written that way put a NUL in `tirun.py`, and every tool then failed on
  import. Write such a script with the Write tool, or use `bytes.fromhex`.

### 5F. DLIs that do frame work, colour-register effects, a fourth bank (Aztec, 2026-11-17)

- **A DLI that does the frame's work can be skipped when the game moves the
  DLI bit.** Aztec's flood moves a DLI up the display list; the flood DLI
  sets a colour register and returns, and the Atari's next DLI (the status
  line) reads the stick. The TI makes one DLI call a frame, so in a flood
  the stick was never read and the man could not turn. List every DLI's
  early return and what the later DLI was relied on for; patch the early
  return on to the frame work when the TI has one call.
- **A colour-register change below a moving line is a colour-table tint on
  the TI.** Tint only the lines that change, and gate the call inline:
  even a no-op far call (two bank switches) every frame cost 6% of play.
  An after-the-fact read-modify-write repair of every cell the colour
  natives wrote made the game crawl (~250-400 cycles a cell); tint inside
  the writers instead (they know their line), and undo the tint when the
  effect ends (the plain cart sets its colour table only at init).
- **A full natives bank: add another behind stubs.** Put one entry routine
  (`N4GO`: set `CURBNK`, select, `B *R0`) at the same address, first in
  both the calling bank and the new one, and give each moved entry a
  two-word stub in the caller's bank. Move self-contained modules (one
  entry) first; check the tools that patch code by bank (mutants).
- **A scripted input keyed to frames goes blind when a cart's passes slow
  down.** Aztec's dyncheck held FIRE 4 frames; a colour pass is ~5, so the
  press often fell between reads, and each failed try crawled the man away
  from the exit. Hold presses longer than the slowest pass, and re-establish
  the precondition (position) before each try, not once.
- **A native that writes a whole region's shadow and then sends it in
  pieces looks wrong to a per-refresh checker.** Label the loop's return
  and skip checks there (as the blit's two rectangles already were).
- **Profile the interrupt on its own** (hooks at `VBLH` and its final
  `B *R11`; swap `t.prof` between two dicts). Aztec's was 34% of all cycles.
  A routine moved to a newer bank behind stubs (`ISRKX`/`ISRKY`, twice a
  frame) now cost two far-call chains each time: 1,500 cycles a frame, 3%
  of the CPU, until the nine-word copy moved into the shared segment. Never
  put an every-frame interrupt call behind a stub chain; move a once-only
  routine (`GINIT`) out of the shared segment to make room instead.
- **Run the Atari's VBI/DLI as native code, and leave the stick to the game
  loop** (Aztec `src/isr.a99`, runtime `VBLH` `.IFDEF ISRNAT`, 2026-11-17).
  Most of the interrupt was glue: saving 16 registers and the refresh's
  words, far calls, copying back. Native handlers, run in `SAVWS` as their
  workspace, cut the interrupt from 34% to 16% of play. Keep a fast path for
  the common frame and fall back to the translated full path for everything
  else (display list or state change, flood, a loop that stops polling).
  Lockstep's exact mode must force the full path (a JMP the tool NOPs), so
  the oracle still runs the handlers at the Atari's points. A handler
  routine whose effect is only read once a pass (Aztec's stick decoder
  `$448C`) can be counted as owed (`MANOW`) and run from the pass's own
  wait, with a cap (`MANLIM`) that sends a non-polling loop back to the full
  path. Any native that read `@WS+n` as an absolute register byte breaks
  when the interrupt's workspace is not `WS` (`spr.a99 PSVBL` did).
- **A send deferred "until the next refresh" needs a guaranteed next
  refresh.** Aztec held each restore to merge it with the following draw.
  Once the player became sprites and his own send was skipped, a quiet room
  made no refresh, and a figure's last restore (the stars after a fall)
  stayed unsent for seconds: old pixels in VRAM, new colours over them.
  Flush deferred work at a point that runs every pass (his restore,
  `sq.a99 SQPLH`), and gate the age of a deferral, not only its contents:
  vidhook excused held cells, so it could never see this.
- **A sprite mask in a checker must end where the screen memory stops
  holding the player.** vidhook kept his sprite ink masked until the blit's
  end check, so a refresh inside his own restore failed on cells that were
  exactly right. Only a timing change (a shorter interrupt) exposed it.
  When a check reports equal bytes as different, suspect the checker's
  mask, not the native.
- **A free RAM word is not needed for a per-call constant.** Push it on the
  R10 stack and use `A *R10,Rn` (no extra instruction word); keep the VDP
  data port in a register (`MOVB Rn,*R5`).
- **Identify creatures by placing them, not by guessing from the survey.**
  Fill the room table (Aztec's `$1180` + room x 16 + slot) with one type
  before the man enters, then capture. Forcing a type into an animating
  slot drew garbage. Placement only covers what the main generator makes:
  **list every writer of the creature table** (absolute and indexed stores
  into it, then a runtime survey of live records for the indirect ones).
  Aztec's octopus is types 23-27, five pieces only the pool room's builder
  (`$7E37`) places; checking the generator alone, I wrongly told the user
  there was no octopus. There are no rats. The colour table the user gave
  (octopus keys 7-11 = 23-27 AND 15) had it right all along.
- **Decode the chip writes to judge a sound.** A table of AUDF/AUDC words
  does not show what the SN76489 plays. Rebuild the registers from the
  write log and print frequency and volume per frame. A "tinkle" needs pure
  tones of 3 kHz and up, struck loud and dying within ~3 frames; Aztec's
  first version (2-4 kHz, 2-frame notes, peak 13) was rejected as not clearly
  a tinkle. Check the property in the gate (atkcheck), not just the label.
- **Speed claims need the same workload.** Cycles a call or a frame show
  where time went; the claim "faster" needs `passbench --exact` on seeds
  whose screen hashes match, with the old cart rebuilt from saved sources in
  a copy of the tree (Aztec: 3.9% fewer frames on 3 matched seeds). Swapping
  a shared file (runtime65.a99) for the old build: copy and restore it with
  the same shell's `cp` (Cygwin's cannot see `/c/...` paths).
- **A colour pass over a block repaints figures inside it.** Aztec's blast
  end (`BOOM_OFF`, `CBLIT`) paints the block's background colour over a
  weapon-kind figure still in it (death crosses: magenta for ~8 frames).
  Restoring "what is behind" must not ignore figures that stay drawn.
- **A frame-count speed cap punishes alternating passes.** Aztec caps each
  pass at 3 frames since the last (`$43DD`), and its passes alternate:
  creature passes (odd `$AE`) ran 10+ frames in a crowd, the man's passes
  ~1.5 and then spun to 3, 9% of a crowded room. Carry the overrun into the
  next pass (at most the cap, `CAPCR`), so the average never beats the
  Atari's rate and a stall is not repaid in a sprint; give lockstep the
  original wait back (`tirun.exact_waits` NOPs `CAPX`). Profile the wait
  separately: it hides inside "translated" time.
- **A "fall back to the full path after N frames" guard must exceed the
  longest legitimate pass.** `MANLIM` 8 sent crowded creature passes (10-12
  frames, no poll) down the interrupt's full path, ~3,000 cycles a frame;
  24 still catches menus and room builds.
- **A/B one change by patching it in the emulator**, not across two builds:
  frame-keyed runs differ ~10% between builds by creature randomness alone.
  Aztec's scratch `pb.py` (passbench + an `exec` hook) flipped `MANLIM` in
  one cart and compared only seeds whose screen hashes matched. Git Bash
  rewrites a `/cygdrive/...` path in an environment variable too: set
  `MSYS2_ENV_CONV_EXCL` for it.
- **A PC hook on a switched natives bank must test the bank.** vidhook's
  held-restore check moved from `BL1` (always-visible code) to `SQPL` and
  `SQHLD` in the fourth natives bank. Unfiltered, translated code at the
  same addresses in game banks fired them, and the check failed a correct
  cart (frame 448). Filter with `t.bank == (NB4SEL - 0x6000) // 2`, and
  label the exact instruction you hook (`SQHLD`): a hook at `SQHF-2`
  pointed into the wrong place and never fired.
- **"Once a pass" is a claim to verify.** `BL1` can be entered twice in a
  frame without reaching its squeeze, so a check keyed on its entry failed
  falsely. Hook the point that does the work (`SQPL`, which flushes).
- **A speed-up changes the game the gates play.** After the cap credit and
  the MANLIM change, seeds that once ended a game or held a restore went
  blind, and blind "must fail" controls passed for the wrong reason. Pick
  seeds that work on both carts (firecheck 2, vidhook 3/7), and make a
  mutant force the path it tests (sndcheck `nomask` puts MANLIM 8 back,
  in the emulator only, so the interrupt's full path runs).
- **A rejected experiment: one held erase per creature (2026-11-17).** A
  creature pass erases all creatures, then draws them all, so the single
  held restore merges only the last pair. Holding up to eight (squeeze
  rectangles in OS page 3, $0310-$03D3, plus a colour list in the colour
  cart) made the colour cart SLOWER in a crowd (13.7 frames a pass
  against 7.2): every blit scanned all eight footprints, and that cost
  more than the duplicate VRAM writes it saved. The user saw it at once
  ("as soon as there are large creatures on screen, it's much worse")
  and hit a black-screen hang. Everything was reverted, the fifth bank
  too. Run the crowd profile BEFORE a cart reaches `build/` where the
  user can play it, and treat a per-blit list scan as a cost to measure,
  not a detail.
- **A second far-entry bank must copy the first's entry bytes EXACTLY.**
  The fifth bank's `N5GO` was reached through a copy in that bank that
  was meant to share its address. The copy padded 10 bytes for N4GO's 12,
  so it sat two bytes early. The interrupt's routine, next in line, still
  ran by luck; the first other routine there ran the interrupt instead.
  Put the real N4GO instructions in front, not a pad, and check both
  label addresses in the listings. build65.py's BANKED5 support remains
  for that use.
- **Colour that depends on neighbouring pixels: decide WHEN those pixels
  are final (Aztec walls win, 2026-11-18).** A pile's edge cell turns
  magenta when the byte beside it shows a wall. Four faults on the way,
  each silent:
  - The shadow is at 6502 address + `KS`. The native AND its checker both
    read the unshifted address. Seven rooms "passed" against the wrong RAM,
    because the checker shared the code's assumption. Derive the checker's
    address from `ann`, and make sure some case actually exercises the rule
    (`--walls` fails if no wall cell was checked).
  - The generator stamps fixtures before it draws walls, so a test at
    stamp time never sees a wall. A pass over every fixture was added.
    Run after REDRAW, that pass saw creatures already drawn into the shadow
    and painted them magenta. It runs at the room's first draw instead,
    before any figure's pixels. The man's and the creatures' pixels are in
    the shadow too. The checker counted them as walls twice: the man in
    room 01, then a creature beside an opened box (seed 15 room 07).
    Exclude every live figure's bytes, and accept either colour there.
  - A per-frame sample of a pass counter can catch a pass that ended after
    the event in the same frame. floodcheck read a 3-pass gap that was 4.
    Read the game's own counter (`FLDP`) instead.
  - Calling that pass from inside another blit's entry overwrote the blit's
    working words (`CBK`, `CBW`, ...), so the creature lost its colour. Save
    and restore the block around it (`CWSV`). And a `BL` inside a routine
    entered by `BL` loses R11: zero checks and a hung game.
  - New RAM in OS page 3 is not cleared at power-on. A stray "walls only"
    flag there stopped every fixture stamp. Clear such flags in the room
    fill.
- **A second figure as sprites (Aztec stars, 2026-11-18).** The stars over
  a fallen man (`BL4`/`BL3`) took a colour pass and clashed with walls.
  Making them sprites like the man (§5D) fixed that. What carried over:
  - **Name the blit by its shape, not its checker's label.** colcheck
    called `BL4` "his weapon". It was the stars. The drawn weapon was part
    of the man's own shape, already a sprite. Read the mask pointer and
    render the shape before promising a change to a figure.
  - **Shift to the first ink pixel.** A 4-byte figure squeezes to about 29
    pixels. Byte-aligned like the man's, that spans three 16-pixel sprites.
    Shifted left to its first pixel, it needs two. That keeps the stars plus
    the man at no more than 4 sprites a line, which was measured, not assumed.
  - **Give it fixed slots before the moving list.** Put two entries first
    and the man's list after them, sent in one write. Hide an entry with
    Y `>C0`; `>D0` ends the whole list.
  - **Copy the squeeze rules and break the copy in a test.** Run
    mutants on the stars' own table copies: they must fail. One of them
    (`stmerge`) only showed on the colour cart's star positions. Run each
    mutant where it is known to fail.
  - **Leave the figure out of the check while it may linger.** After a
    restore, its sprites stay up to 8 frames. Exclude them while the
    countdown runs, but only for -1..-8, so the "never hides" mutant still
    fails.
  - **Fall back to the bitmap for anything unusual**: clipped columns, off
    screen, or a different size. A rare edge case need not be a sprite.
  - **Bank room.** Moving a cold routine (the status ornaments) into a
    fresh bank paid for the hot code's growth in the full one.
- **Pair erases with redraws in the order the game actually uses (Aztec,
  2026-11-20).** A creature pass erased every creature and then drew them
  all, and only one erase was held for its redraw. The plan assumed both
  loops ran in the same order and built a queue. It gained 3%, not the
  estimated 6-10%. Logging each rectangle showed why: the erase loop runs
  the slots high to low and the draw loop low to high. A stack paired every
  creature: crowd 5.33 -> 4.83 frames a pass (plain), 7.28 -> 6.82 (colour),
  and its code was smaller than the queue's. Lessons:
  - **Log the actual rectangles before choosing the data structure.** An
    erase and a draw of the same creature overlap, but so do the erase of
    one creature and the draw of a neighbour. A pairing that tests only
    "touches" can still pick the wrong partner and look like it works.
  - **Exclude a figure's wrap send from "anything else flushes".** A figure
    past column 39 sends its wrapped columns after its own rectangle. That
    second send flushed every held erase before the draws came.
  - **Gate the pairing itself.** Correct pixels do not prove the speed-up.
    A mutant where no draw ever pairs passes every picture check. vidhook
    `--queue` fails unless some pass pairs two or more, which makes it fail.
- **One noise channel needs a priority, and a death needs its own silence
  (Aztec, 2026-11-20).** Every POKEY effect mapped to the SN76489's single
  noise channel, youngest first, so a big cat's roar was lost under a
  footstep. The user read that as "the cheetah makes no sound". The fix was
  a priority in the mixer, not a new sound. The blast plays alone. Otherwise
  an attack plays alone. Everything else is muted while it plays and resumes
  where it has got to. The fuse sizzle keyed on the game's fuse byte, which
  a death leaves set, so the sizzle kept playing after "you did not make
  it". Find the one place every death passes through (Aztec: `$4102`) and
  clear the TI-only sound state there. Lockstep cannot see this RAM. Gate it
  with a probe that keeps the effect running up to a real death, plus a
  mutant (`deathfz.py --mutant fresh`).
- **A full gate run on the final cart can find a fault that older carts
  hide (Aztec, 2026-11-20).** A stray unconditional store after a
  conditional widen (`MOV @SQL1,@PBL1` after `SQKPD`) shrank the box of
  sends to the last send's bottom. The player's restore then skipped a
  creature's send now and then. It sat unseen for three days, because no
  gate seed reached that layout until the new stack changed the
  trajectories. Each min/max widen needs its own mutant (vidhook `pbox`).
  When a seed goes blind after a speed change, move the seed. Never drop
  the gate. The same mutant was blind on the plain cart's seed 7 (it
  passed); a must-fail gate that passes is a blind gate, so run it per cart.
- **A routine moved to another bank from inside a BL'd routine must not
  BL there (Aztec kill sounds, 2026-11-20).** The sound bank was full, so
  the kill-sound player went to the fifth bank, called from `SNVIRT` with
  `BL @N5GO`. That overwrote `SNVIRT`'s own R11, its `RT` came back into
  the call site, and the interrupt looped: zero frames checked. Jump both
  ways instead. The caller does `B @N5GO`; the callee returns with
  `LI R0,<continuation> / LI R12,NB3SEL / B @N4GO+4`, re-entering the
  bank-entry stub after its `LI` (the same instructions sit at the same
  address in both banks), so the third bank pays no return stub. Rare game
  events (a kill needs a drawn weapon and a creature in reach; random play
  found none in 70,000 frames) are staged in the sound gate by writing the
  request word the PATCH writes, and checked word for word from the cart's
  own tables.
  - **And a sequence pointer in page 3 needs a boot clear (the same day).**
    The kill player's pointer `SNKL` held power-on garbage (`>FF02`), so the
    player stepped through RAM playing whatever words it found: the user
    heard "hissing sound effects in background when it shouldn't be". The
    chip-against-registers gate passed, because the chip faithfully played
    the garbage registers. Clear new state in the routine that runs before
    the first sound (`SNDOFF`), and gate the pointer's range, not only the
    output (sndcheck: `SNKL` in `KSHING`-`KLEND` or 0; mutant `kloff`).
- **A "he is gone" timeout must exceed the slowest pass, not the measured
  one (Aztec, 2026-11-20).** The man's sprites came down 8 frames after a
  restore with no draw (a death: the Atari shows nothing). That was 2x the
  0-6 frames measured in the first rooms, but beside the octopus the colour
  cart took 12-23 frames: his sprite list's first entry became `$D0`, the
  VDP stopped there, and the user saw him blink. Size such a timeout between
  the slowest legitimate gap (the most crowded room, the slowest cart) and
  the real event's (a death redraws 45-63 frames later): now 40.
- **A pinned PATCH should not copy a far call (the same day).** The thrust's
  `JSR $63B6` translates to `BL @FARC / DATA L63B6,>600C` in the plain cart
  and `>600E` in the colour one. Patch the instruction before it instead
  when every path passes it (`$4E62`'s `LDA #$01`).
- **A gameplay change the user asks for keeps the Atari's rule behind a
  lockstep switch.** The octopus's tentacles hit at their tip, up to 8
  columns out, while the machete only killed at the root (the Atari's rule;
  the pistol also passes over the short pieces). PATCH `$6401` widens the
  test for those types only, with a NOP (`OCTX`) that `tirun.exact_waits`
  turns into a jump back to the original test, as `DYNLOST` and `FUSET`
  do. Probe such questions with the hit taken out (a pc hook skipping
  `$6504` for the octopus's slots) so the man lives long enough to try
  every column; a scripted drop into the room left him stunned and dead
  before he could swing, which says nothing about the rule.
- **A picture checker must skip frames that end inside a blit.** vidcheck's
  "restore without a draw" mode starts at `BL1`'s entry, but the frame can
  end before the restore reaches screen memory. It then compared the bitmap
  alone with a screen still holding his figure (his sprites were still up):
  a false fault that moved with every route change. Skip while `inblit`.
- **A special region of the screen needs its rule on EVERY send path**
  (Aztec, 2026-11-23: a bottom-floor blast drawn shifted into the status
  band). The first fix taught the rectangle refresh to squeeze the band
  inside the blast, and the blast still landed wrong: it draws a byte at a
  time, and band bytes take the one-cell path (`sqf.a99 SQSF4` → `SQFS`),
  which sends them as text. List every path that can write the region
  (rectangle, one-cell, fast column, character) before fixing one.
  Two checker traps on the way: a pc hook on an address a `PATCH`
  replaces never fires (the in-blast check silently ran zero times while
  both mutants "passed"; count the checks and print the count), and a
  per-frame comparison sees the byte being drawn as the frame ends. Model
  that exactly (one cell, never the same cell two frames running), not
  with a percentage, so a stuck cell still fails.
- **A full shared segment: the size search can overshoot by a step**
  (Aztec, 2026-11-23, the victory screen). The shared segment is
  rounded to 32 bytes, and every natives bank pays each step. Its end
  depends on its own size (the payload table `PAYT` shrinks as the
  segment grows), so rounding up from one failed size landed a step
  too high (`>14E0`) and overfilled a natives bank, while `>14C0` fits.
  Aztec's `tools/build.py` now also tries one step below any size that
  fails. A blob whose copier reselects the natives bank per entry can
  keep its table there instead (`g.BLOB_BANKED`, build65). Also: when a
  second tune joins one player, route **every** idle path through its
  start check. `KLVIRT` had three branches to the march check, and only
  one went through the new tune's, so the song never started.
  Finally, the bank-blind `pc_hooks` trap (§5C) bit a hook on `TITLE`. The
  `--key none` control (nothing pressed, must fail) passed and exposed
  it. Give every "it returned to X" check a no-input control.
- **When a code fix makes a mutant stop failing, suspect the fix**
  (Aztec, 2026-11-23). A gate flagged one band cell during a blast. I
  blamed a byte sent the text way and rerouted it, and `boomcheck --mutant
  bsend` then passed: that byte's send was the very path `bsend` breaks,
  and it was already correct. The cart was right; the checker had compared
  an untouched cell (old text, from a byte the blast had since changed)
  with today's bytes. Before changing code for a checker failure, find the
  writes to that cell; and a must-fail gate going blind right after the
  edit is the cheapest sign the edit was wrong. Also: a probe reading 6502
  zero page must go through `ti_addr` **and** the scratchpad (`t.scratch`
  for `>8300`-`>83FF`, as vidcheck's `rd8`): `t.exp` there reads zeros, and
  an 838 probe "proved" a working cheat broken in both old and new builds.

## 6. Working practice

- Tools that import each other live in one folder: **never name a script
  after a standard module** (a `dis.py` there broke `import inspect`).
- Bash heredocs feeding `python -` hang or fail here; write a file and run it.
- A launcher that types `2` to pick the cart from the TI menu also answers a
  game menu that takes digits (Aztec started at difficulty 2). Check what the
  game does with the keys the launcher sends.
- Keep the game's `README.md` and `DESIGN.md` in step with every change, and
  leave the newest cart running in Classic99 (repo standing rules).
- **Track work in the port's `todo.md`** (`Decompiled/<Game>/todo.md`; the
  user, 2026-11-18). When a task to track comes up (a proposal the user
  wants, an open question, a speed idea, a bug), add it to the open list at
  the top straight away. Give each item a one-line title, what was measured
  or estimated, and what is still undecided. When one is done, move it to
  the **Completed** section at the bottom, with the date and outcome, and
  for a speed item the measured numbers. Rejected or reverted work goes
  there too, marked as such, so it is not tried again blind. Update the
  file in the same change as the work, like `DESIGN.md`.

## 7. Open work

In this order, for Aztec and so for the pipeline:

1. ~~Lockstep~~ done (`lockstep65.py`, `soak.py`).
2. ~~Sound~~ done (§5C, `sndcheck.py`).
3. ~~Gate runner~~ done: Aztec `tools/gates.py` (parallel, auto-sized,
   longest first, mutants must fail).
4. **Speed against the Atari**: `passbench.py` (pass-keyed A/B),
   `passrate.py` and `tblank.py`. The blitters, the character drawer and
   the generator's bit loop are native, and §5D's squeeze changes and
   second round are in (about 4.7 / 5.4 frames a pass plain / colour).
   Busy rooms still take far more than the Atari's 3. The profile is flat:
   blits 20%, squeeze 19%, interrupt 10%. Next: fuse the squeeze send into
   the blit's column loop, the colour fixture scan, the generator, `REDRAW`.
5. ~~Cart size~~ done: banks are repacked with the real branch sizes (Aztec 128 KB).
6. Front end: TI-style title, FCTN 8/9 back to the menu, save-game decision.
