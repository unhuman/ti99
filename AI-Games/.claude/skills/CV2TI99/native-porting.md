# CV2TI99: porting hot code to native TMS9900 (the process)

Developed on River Raid (`Decompiled/RiverRaid`, whose `tools/` hold every
tool named here), on top of what Zaxxon taught (`optimization.md`). Read
this before writing any native routine or translator change.

## 0. The budget: why translation alone stops at about half speed

Measure it for every port with `tools/ipass.py` (instructions and cycles
per logic pass on both machines). River Raid:

| | instructions a pass | cost an instruction | per frame |
|---|---|---|---|
| ColecoVision Z80 (3.58 MHz) | 3,317 | 9.5 T-states | ~6,300 fit |
| TI translation (3 MHz, 8-bit bus) | 3,383 | 25 cycles | ~2,000 fit |

The translator is already **one TMS9900 instruction per Z80 instruction**,
but every TI instruction pays 4 wait states per 8-bit-bus access (its
fetch words, memory operands, the VDP): about 2.6x the Z80's time.
Consequences:

- **Re-encoding a routine by hand gains about nothing.** A native that
  does the same steps executes the same number of instructions. River
  Raid's sprite builder rewritten with everything in registers measured
  2.36 TI cycles a T-state against 2.33 for the plain port.
- Full speed needs each pass done in **fewer instructions than the Z80
  uses** (River Raid: ~2,000 instead of 3,300), or in cheaper ones.
  Only three things do that: **do less work** (caches, compare-on-change,
  skipping what did not change, tables instead of arithmetic), **cheaper
  instructions** (register-to-register work, auto-increment instead of
  indexed operands, code in the 16-bit scratchpad >8300-83FF with no fetch
  wait states), and **bulk transfers through scratchpad loops** (the VDP).
- A routine's **TI cycles per Z80 T-state** (from `tools/routest.py`)
  ranks it: about 3 for translated logic, 1.6 for code bound by VDP
  transfers, and below 1 needed for a pass to fit in a frame.

## 1. Measure (before choosing anything)

| Tool | Answers |
|---|---|
| `speed.py ti\|z80 1500 SEED` | logic passes per 100 frames (run 3 seeds: one seed's game drifts with timing) |
| `ipass.py` | instructions and cycles a pass on both machines (the budget above) |
| `zincl.py` | Z80 inclusive T-states a frame per called routine: what the original spends where |
| `tiprof.py` | TI cycles by label over play |
| `xlatcost.py` | TI cycles by Z80 instruction pattern, executions, cycles an execution: translator weak spots (a pattern costing far more than ~30 cycles a run hides a poll, a run-time mapping or a bank switch) |
| `routest.py ADDR --profile N [--byfunc]` | one routine: Z80 T vs TI cycles a call, and where its TI cycles go (by label, or by called routine) |
| `tifunc.py` | the whole pass on the TI by routine (translated code and regions charged to their Z80 routine) |
| `vtime.py`, `vregs.py` | where VRAM and VDP register writes land relative to the beam (tearing) |
| `pdist.py` | how many frames each pass takes (uneven passes read as jerking) |

Then rank targets by **TI cycles a pass**: routest's cycles a call times
calls a pass. Look inside each with `--profile` before deciding:

- **Mostly scratchpad / VDP labels**: the routine is bound by VDP
  bandwidth (River Raid's scroll copy: 55% in the transfer loops). Porting
  the logic around it gains little. A RAM shadow of VRAM was tried and was
  **slower** (2x): a RAM-to-RAM byte loop in 8-bit RAM costs more than the
  scratchpad VDP loop it replaced. Reduce the bytes moved instead, or leave it.
- **Hand-written code already**: check its ratio; if it is ~2.3+, the code
  does the Z80's steps one for one: find work to remove, not a re-encoding.
- **Translated code with a high ratio**: native candidate, but write down
  first what work the native will *not* do.

## 2. Write the contract

Read the Z80 routine and its callers (`tools/show.py ADDR`). Write a
header comment: inputs (registers, memory), every output (each register
and flag it leaves, every byte it writes, including scratch variables the
game later reads), what a caller may rely on, and the poll sites. Find the
callers' needs: flags live after the call (`NATIVE_FLAGS`), registers they
read before reloading.

## 3. Choose the mechanism

- **`ann.NATIVE[addr] = 'LABEL'`**: the whole routine (every call and jump
  to it goes to the native). Natives run on the game's workspace with
  `BL`: A = R1 high byte (low byte 0), BC/DE/HL = R2-R4, IX/IY = R5/R6, R7
  = SP + K (TI words, big-endian, on the Z80 stack), R8 = flags (canonical
  bits Z >2000, C >1000, S >8000, P >0400), BC'/DE'/HL'/A' = R9/R10/R13/R14,
  R11 = return, **R0 and R15 scratch, R12 = 0**. Return flags the callers
  need in R8 and list them in `NATIVE_FLAGS` (the translator then knows).
- **`ann.ASM_REGIONS[start] = (end, entries, polls, 'file.a99')`**: a span
  of Z80 code replaced by a hand-written file spliced into the translation.
  The file supplies the labels the rest of the code uses: `Cxxxx` (call
  entry, with the `DECT R7 / MOV R11,*R7` prologue if the routine is not a
  leaf), `Zxxxx` for every jump target into the span, and leaves by
  `B @Zend` or a return. Keep regions and the routines they `BL` hot
  (`ann.HOT_ROUTINES`): a raw `B @` / `BL @` cannot cross banks.
- **`ann.PATCH[addr] = [lines]`**: one instruction replaced by literal
  TMS9900. The translator keeps its flag model as if the instruction had
  not changed flags, so patch only instructions that do not set flags,
  and do not rely on status bits across it.
- **Useful byte addresses** in the main workspace (>8300): R0 low >8301,
  C >8305, E >8307, L >8309, IXl >830B, IYl >830D, R13 low >831B. `@T(R0)`
  is absolute (R0 cannot index); use R4/R5/R6/R15 as index registers.

## 4. Rules that keep it exact (each one cost a debugging session)

- **Keep the interrupt polls where the translation had them** (loop heads),
  with the `Zxxxx` label on the `TB 2`, and list them in the region's polls
  tuple: the lockstep counts time in poll-site visits on both machines, and
  the frame handler (which may now send queued VDP writes) only runs at
  polls. Removing the polls from River Raid's object loops left the frame
  handler up to 200 scan lines late and half the deferred sprite writes
  landed mid-frame. You may move a poll to another Z80 address (once a
  list instead of once an object), as long as the Z80 address in the tuple
  is where the label is.
- **A poll runs the NMI glue on the main workspace**: R0 and R15 are
  clobbered there; never keep a value in them across a poll or a `BL` into
  translated code.
- Registers a native "borrows" (the alternate set) must be saved and
  restored; push them on the Z80 stack (excluded from the comparisons).
- Native code that touches the VDP must not have a poll inside an address
  set + data sequence. Make every BIOS VDP routine native (FILL_VRAM,
  WRITE_REGISTER, WRITE_VRAM, READ_VRAM) so no translated code does.
- A native that reads the keyboard directly (POLLER) bypasses hooks put
  in the port routine (`CTRL`): River Raid's game-over "fire = #" pulse
  had to be added to the native POLLER too (caught by `gotest.py`).
- Byte/word addressing: a word access ignores bit 0; a buffer copied as
  words must start even (River Raid's sprite list at $7194 is; an odd
  count copies one byte more, which must stay inside the destination).

## 5. Verify, every change

1. `tools/routest.py ADDR --samples 150` (several `--seed` / `--game`): the
   routine from real captured states, against the Z80, 0 differences.
   It sets RAM, VRAM, VDP registers and the CPU registers on both machines,
   runs to the return, compares everything (stack area excepted). TI-only
   state the routine depends on (caches, shadows) must be set up by the
   test too, or it reports false differences.
2. `tools/lockstep.py` (4 seeds x 300,000 ticks) on the final build.
3. `tools/insntest.py` after any translator change.
4. `speed.py` on 3 seeds; keep the change only if it is faster.
5. Front-end tests (`gotest.py`) when input or screens are involved.

## 6. Translator improvements

Find them with `xlatcost.py` (pattern cost a run). Done so far:

- Canonical flags (`Emit.canon_lines`): all live flags constant -> one `LI`
  (`CLR` for 0); one flag in the status and the rest 0 -> `CLR R8` (CLR keeps
  the status) + a jump + `ORI` (3 instructions instead of 6+).
- A conditional return's own condition is a constant on its way out
  (`RET C` returns with C = 1): no test of it in the return path.
- Measured: River Raid +0.5 passes per 100 frames (the patterns were
  already near one instruction each).

- A run of `SRL r` on one register (up to 7, no branch target inside, not
  a 16-bit pair shift) is one `SRL R0,8+n` (`Body.same_op_chain`; insntest
  runs the whole run: `rot_runs`; insntest had assumed 1-byte rotates).
- `CP 0` sets C to the constant 0 (it never borrows): a later canonical save
  of Z and C is then one `LI` instead of 9 instructions.  After these flag
  changes no generic multi-flag save (`STST R0` ...) is left in River Raid.
- What remains in translated code is mostly call/return (about 160 TI
  cycles a call pair against 27 T: `BL`, the stack prologue, `MOV *R7+,R0 /
  B *R0`); only inlining small routines or another calling convention would
  cut it.

Candidates not done yet: the same for `SLA r` / `SRA r`; `push rr / pop rr'`
pairs as register moves where the stack slot is dead; leaf calls without
the stack prologue.

## 7. What removed work (River Raid, passes per 100 frames, ColecoVision 96)

| Change | Passes |
|---|---|
| straight translation | 26 |
| native WRITE_VRAM / READ_VRAM (their OUTI/INI loops ran through MAPV) | 43 |
| native OS7 sound engine (Zaxxon's) | 48 |
| object loop and sprite builder as regions | 54 |
| native POLLER, $1F00 bit reversal by table | 59 |
| VDP writes deferred to vblank (display fix; queueing costs) | 54 |
| faster object loop (poll a list, auto-increment), scroll row copy region, flags | 57 |
| the pass's 15 object lists as one generated region (table of flag-byte addresses, a poll a list) | 58 |
| the lists unrolled (per object: absolute load, mask, branch; registers as constants in a stub) | 62 |
| sprite builder: no poll a part, y/x in scratch registers, *R3+ stores, flag test once an object | 63 |
| scratchpad VDP loops unrolled to 8 bytes; READ_VRAM one-byte fast path; SRL runs | 64 |
| handlers called directly per list (the type record is a list constant; guard + fallback) | 65 |
| sound trims (word stores, PLAY_IT's exit without the stack), INIT_TABLE shift in one `SRL`, scroll pointers in registers, queue copy in scratchpad, `CP 0` | 66 |
| the game's NMI handler done in the glue (it only sets the frame flag); $BFCC / $BFB1 VRAM wrappers native | 67 |

### Where the ceiling is (River Raid at 67)

After these, a pass is 72,300 TI cycles (2,900 instructions); full speed
is 50,000.  What is left, and why each is hard to cut:

| share | what | why |
|---|---|---|
| 15% | scratchpad VDP loops | bytes the game moves (sprite table, scroll rows read and written, terrain rows); already ~24 cycles a byte |
| ~33% | translated code | already one instruction a Z80 instruction; about 7% of the pass is call/return (160 TI cycles a pair) |
| ~12% | sprite builder region | per part ~20 instructions, per object setup ~25; every register in use |
| ~8% | sound engine | per data area per frame, already compare-on-change for the chip |
| ~5% | idle in the game's own wait loops (respawn, game over), vblank syncs | correct waiting |

Tried and dropped at this stage: catch-up pacing (start a pass at once
when frames are owed: no gain, the idle is in the game's own waiting
loops, not in play); queueing more VDP writes (section above).  A further
big step would need a different calling convention or inlining in the
translator, or rewriting whole subsystems around different data layouts.

Instructions a pass (`ipass.py`) went from 3,383 to 2,918 (the Z80 runs
3,317); full speed needs about 2,000.

### What worked and what did not (River Raid)

- **Worked: removing work the data makes unnecessary.**  ROM tables are
  constants: unroll the walk over them at build time (generator), turn
  their entries into immediates and absolute addresses, call a handler
  directly instead of through its computed-jump chain when the record is
  fixed (keep a guard that falls back to the general path).
- **Worked: fast paths for the common small case** (READ_VRAM of one byte:
  700 -> 150 cycles; the terrain tests read single bytes).
- **Worked: polls that cost per element** (one per sprite part) moved to
  one per list, on both machines.
- **Did not work: re-encoding a compare-and-branch routine** (the collision
  tests $B355/$B38E/$B3C7 by hand were slightly slower than the
  translation; kept in `src/tried/` for reference) and the register-heavy
  sprite builder v2.  Translated straight-line logic is already ~1 TI
  instruction a Z80 instruction.
- **Did not work: a RAM copy of VRAM** to avoid VDP reads (2x slower).
- **Did not work: queueing more VDP writes to avoid vblank waits.**  The
  writes that waited (the terrain's new rows while a name-table switch is
  queued) are read back at once by the terrain test, so the read waits
  instead, and the overlap checks cost more than they saved.  Measure the
  waits (who calls `VSYNC`, tools/vsywait.py) before widening the queue.
- **Checker for the deferred writes**: `tools/defercheck.py` plays with
  TI-only behaviour on and fails on any VDP read or direct write that
  touches a queued range (deferral never changes RAM, so the lockstep is
  blind to it); `--selftest` plants a queued entry and must find 2 faults.
- **`MOVB` into a register keeps its low byte.**  Clear the register before
  using it as a word (shift, add, index): the INIT_TABLE region read IY one
  too high until it did (routest found it).
- **Watch the hot RAM.**  Generated and unrolled code is hot and large:
  5.6 KB of per-list specialised sprite builders did not fit and pushed
  other hot code into banks; measure the whole pass (`speed.py`) after a
  change, not only the routine.
- **A native's registers**: `routest.py` compares registers; a native that
  leaves different registers than the original (River Raid's native
  PLAY_IT, from Zaxxon) is acceptable only after checking the callers do
  not read them (here they pop or reload); write that down in the
  native's comment.

Tried and dropped: a RAM copy of the name tables (scroll 2x slower, see
section 1); the sprite builder with everything in registers (no change:
same instruction count).  Generated regions: when the code walks ROM
tables, a build-time generator (`tools/gen_rafea.py`) can turn them into
TI-ready tables (TI addresses, big-endian words) and unroll the call
sites, keeping one poll per original call so the lockstep ticks match.
