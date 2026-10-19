# CV2TI99: TMS9900 speed techniques and pitfalls

Measured on Zaxxon (Decompiled/CVZaxxon). Busy play went from ~45% to ~93% of
the ColecoVision's logic rate (95% of its scroll rate); straight flight reached
full speed. Numbers are per frame of 50,050 TI cycles unless noted.

## The cost model

- Every memory access outside the 256-byte scratchpad (`>8300-83FF`) and the
  console ROM costs 4 wait states: cartridge ROM, 32K RAM, VDP and sound ports
  alike. Code in ROM and code in 32K RAM run at the same speed; only scratchpad
  code is faster (no fetch waits), and it is tiny.
- The translation is already about one TMS9900 instruction per Z80 instruction.
  **Hand re-encoding a translated routine gains ~0** (tried on the collision
  probe). What pays is **removing work**: work the original repeats that does
  not change anything, and work whose result is already on the chip.
- Find it with `tools/tiprof6.py` (where a frame in flight goes, by source file
  and label, from the listing) and `tools/heavy3.py` / step-pass profiles (the
  passes that took two frames). Older profilers charged code that follows a
  file in memory to that file's last label: check attributions that look odd.
- Measure speed with `tools/speed.py ti|z80 3000 <seed> - --pass` on both
  machines (logic passes and scroll steps per 100 frames in flight). Use input
  keyed to logic passes; frame-keyed random input lets the slower machine play a
  different game.

## What paid off (largest first)

1. **Native BIOS services**: the sound engine (SOUND_MAN, PLAY_SONGS, PLAY_IT,
   SOUND_INIT, TURN_OFF_SOUND), the controller POLLER and decoder, the VRAM
   read/write/fill helpers, the game's NMI glue, the VDP-address helpers.
   Keep the BIOS's data layout in Z80 RAM (the game reads it) and match every
   register and flag the original returns (`NATIVE_FLAGS`).
2. **A native renderer for the game's character-mapped playfield**, drawing a
   whole row between interrupt polls, with the row's constants computed once per
   segment (`RSETUP`).
3. **Precomputed character tables** for the renderer's per-character math
   ((pattern byte mod L) + H), built by `build.py` from the ROM and loaded into
   RAM. Lay them out **planar** (column c of tile t at `base + 256c + t`, base on
   a 256 boundary): moving a map byte into the pointer register's low byte
   (`MOVB *R15,@>8309`) selects the tile with no shifts or adds, and a tile row is
   four indexed `MOVB @n(R4),*R11`.
4. **Table-driven row geometry**: one table indexed by the row's remaining length
   gives the middle tile-row count, the last tile row's length, the last tile
   row's map offset and the row's share, so the common row has no per-tile end
   checks; enter unrolled 4-instruction sequences at a computed offset for the
   partial first/last tile rows. Fall back to the general path for the rare rows
   (map end, wrapping positions, short rows). Route resumed rows (after a yield)
   through the same fast path (+1%).
5. **TI-only renderer pacing** (`RMINN`): a coroutine renderer that yields at
   every frame end starves on the slower CPU (the playfield never appears).
   Owe each slice a share of the scroll step before it may yield; 0 restores the
   original yields and is what the lockstep uses.
6. **Compare-on-change caches** (each exact, each cheap to check):
   - sprite attribute table: copy to VRAM only after a store that changed it
     (translated stores to the table compare first and set a dirty flag; a
     partial copy when only the player's fields changed);
   - PLAY_SONGS: per channel, remember the data-area pointer, status and the
     frequency/volume bytes last sent; skip the channel when unchanged (+0.6%);
   - POLLER: once two polls have seen the same raw inputs and enable flags,
     every debounce has settled and further polls are no-ops (detect a BIOS
     controller-init by its zeroed raw bytes);
   - keyboard scan: skip the decode when no column changed;
   - a subsystem's inputs shadow (Zaxxon `$D3DC`: skip when x, y, z unchanged).
7. **Read the controllers every other frame** when the logic runs at about that
   rate; rescan the keyboard every few port reads.
8. **Native fills/copies** for loops that call a 1-byte VRAM write per element
   (Zaxxon's screen clear: 31 frames → 3-4).
9. Translation-level wins: `RST 8` (call with NMI held off) as a plain call
   where the handler would only defer; leaf-routine relaxation; constant
   propagation of `OUT (C)` ports; peepholes (ANDI/ORI constants, INC/DEC via AI);
   VDP copy loops in scratchpad (4 bytes per iteration).

## Build-space rules

- Every cold bank repeats the shared segment, so the largest cold routine (a
  connected control-flow cluster, Zaxxon 1.9 KB) must fit in one bank beside it.
  Growth of the shared segment breaks placement silently-looking ("cold cluster
  larger than a bank"): `build.py` retries with a larger hot margin.
- Emit only the byte constants (`BCxx`) that something references.
- Free RAM for new variables by moving the start of a RAM code area (Zaxxon
  `>AC00-AC3F`), never by squeezing scratchpad (it is full of workspaces).

## Pitfalls (each cost real time)

- **A value kept in a register across a deferral must survive every path.**
  The fast path stored the row's start offset in R1 to write `$71A9` at the end
  of the row; the strip-change code that runs at some row starts reloads R1, so
  a row that also yielded resumed at a garbage VRAM address and drew map rows
  over the score, the altimeter and the playfield. No-input lockstep runs never
  hit it; a lockstep with random joystick input found it at once.
- **Lockstep with input**: the no-input game crashes early in level 1. Also run
  random joystick + fire input (mirror it onto both Coleco controllers when the
  TI's controller 2 follows joystick 1), for millions of ticks.
- TMS9900: R0 cannot be an index register (`@T(R0)` means absolute `@T`); word
  operations ignore address bit 0 (odd addresses read the word below); `LI`, `MOV`
  and most instructions set the status bits, so nothing may sit between a test and
  its jump; `C`/`CB` compare unsigned with `JH/JL/JHE/JLE`, signed with `JGT/JLT`.
- xas99: a comment needs **two or more spaces** after the operand, or it is read
  as part of it.
- VDP: the address is low byte then high byte (`| >40` for writes); after the
  first control byte the low byte is already live, so a data write between the
  two lands at old-high/new-low. Reading the status register resets the
  control-byte latch: never take the interrupt between the two address bytes.
- Keypad decode table (`$10F5`) must be fully copied into RAM (`reserved_bios`);
  partially-profiled BIOS data silently becomes zeros.
- Test hooks on banked addresses must check the bank.
- Bash heredocs eat backslashes in Python patch scripts (`\\b` became a literal
  backspace in a regex); edit Python with the Write/Edit tools.
- The lockstep's TI side must reproduce the original's timing model: interrupts
  only at poll sites, `$C5E5`-style delays one vblank per visit, the title hold
  skipped on both sides, and every TI-only feature switched off.

## Pitfalls found porting Joust (Decompiled/joust)

- **A game that never calls the BIOS needs none of it.** A `$55AA` header
  skips the BIOS title; Joust's NMI is `$0066 -> $8021`.  Trace from the
  start vector and `$8021` only, and use the freed >2000-3FFF.
- **More code than RAM + one bank: place cold code by chunk, not cluster.**
  Joust's 24 KB of logic is one cluster of tail jumps.  A jump into another
  cold chunk is a far jump; every call from banked code restores its bank
  (CALLSV / FARCALL); `LD SP` resets the bank stack.
- **A far jump must keep R11 and the status.** `BL @FARJMP` broke leaf
  routines (return address in R11) and flags carried in the status: the
  game froze entering level 1.  Use `BLWP` and set the caller's R14.
- **Conditional returns are flow `cret`.**  xlate's return analysis only
  counted `ret`, so `RET NZ` handed its caller stale flags (Joust went to a
  hidden options screen).  Fixed in joust/tools/xlate.py.
- **ADC HL,rr with a carry-in: add the carry after.**  `INC HL` then
  `A HL,HL` gave 2HL+2 for ADC HL,HL (Joust's random seed).  Insntest skips
  carry-in cases it cannot set up; the lockstep found it.
- **TB 2 is active low**: EQ means no interrupt pending (a HALT loop must
  spin on JEQ).
- **Lockstep: stop both machines at the same point of a poll site.**  The
  Z80 side must not execute the poll site's instruction after the target
  tick; the TI has run only its TB 2.  Otherwise a store there reads as a
  divergence.
- **Two simultaneous players: controller 2 must not follow joystick 1.**
- **A frame wait that always waits for a fresh vblank** halves the speed
  once a pass overruns: start the next pass if a vblank already came, and
  catch the per-pass sound driver up per missed frame (Joust N_PACE).

## Pitfalls found porting River Raid (Decompiled/RiverRaid)

- **A `$55AA` game can still use the BIOS.**  River Raid skips the BIOS
  title but calls the sound engine, POLLER and VRAM routines.  Start from
  the Joust tools (region map, MAPV, far jumps) and add the BIOS back:
  `is_rom` covers $0000-$1FFF, `ann.BIOS_USED` entries, a KB region, and
  Zaxxon's natives (same offsets if RAM and cart share K = >3000).
- **Initialise KPAD to $0F.**  KSCAN only decodes on a change, so a
  never-touched keyboard left KPAD = 0, which the port reports as keypad
  key 0: River Raid's pause.  The first lockstep compare caught it
  (POLLER's raw bytes $73F0/1 = $8F instead of $80).
- **MIRROR the BIOS idle-channel byte for the native sound engine.**  It
  reads channel data as `@K(R5)`, and an idle channel points at BIOS
  $024C, so $024C + K must hold that byte; with BIOS data at KB the TI byte
  there is something else, and every idle channel played junk at full
  volume.  Reserve it so no code lands on it.
- **Computed jumps through data tables.**  Record targets with a hook run
  (`tools/ijumps.py`), then read the tables themselves for the ones play
  never reached (River Raid's object type records give three handler
  words each).  A per-site compare chain (`CI R0,>t / JEQ Zt`) beats the
  global JPLOOK search.
- **INC A / SUB n before DAA** are BCD adds/subtracts too (`BCDSV`).
- **A conditional return may write R8 on its way out**: the "flag saved
  in R8 but R8 is overwritten" check must ignore `cret`, whose
  canonicalising lines are skipped on the fall-through path.
- **The OUTI/INI loops of WRITE_VRAM/READ_VRAM ran through MAPV** (their
  pointer can be ROM or RAM): 28% of the TI's time before the natives.
- **A slower pass moves the game's vblank work into the picture.**  A
  game that waits for the frame and then uploads sprites / switches VDP
  registers does that in vblank on the Coleco; on the TI the wait often
  returns late and the same writes tear the screen (River Raid's scroll
  switches the pattern table every step).  Measure with a beam-position
  log of VRAM/register writes on both machines (RiverRaid `tools/vtime.py`,
  `tools/vregs.py`), then queue those writes when the wait was late and
  send them from the frame handler at the next vblank (`DEFON`/`GLUE`).
  Only accesses that could observe the queue wait for it; make every BIOS
  VDP routine native first so no poll falls inside a VDP sequence, and keep
  polls in hand-written loops or the handler arrives too late.
- **Uneven pass lengths read as jerking.**  At 1-2 frames a pass the
  scroll speed alternates; holding every pass to two frames is smooth but
  slower (River Raid `build.py --even`).  Offer both.
