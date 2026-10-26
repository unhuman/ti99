# os7lib: the native ColecoVision OS7 BIOS for CV2TI99 ports

Reusable, register-exact TMS9900 replacements for the OS7 services that
BIOS-calling ($AA55) Coleco games spend their time in, plus a TI-only
vblank sound player that keeps music at tempo when a game tick takes
longer than a frame. Built and measured in `Decompiled/Carnival`
(October 2026), which is the integration reference. This folder retains the
generic object drawer and timer-base check. Carnival's newer `os7obj.a99`
also calls its generated OGL entry and emits rectangle queue records; its
`os7.a99` uses a faster timer path whose table-base ownership must be proven.
Do not copy those files alone into another port. For all accepted changes,
read the [resolved-work index](../optimization.md#carnival-resolved-work-index)
and integrate the matching runtime, queue reader/writer, placement and checks
together. Keep Carnival-specific generated gallery and expanded asset loaders
in Carnival; they are not generic BIOS replacements. Shared sound sources
remain synchronized with the accepted port.

**Use it in every BIOS port.** Translated OS7 code runs at about 3 TI
cycles per Z80 T-state. These natives run at 1.4-1.6 (TIME_MGR 1.37,
SOUND_MAN 1.52). On Carnival they took the game from 63.5% to 79.6% of
Coleco speed with lockstep still at 0 diffs.

## Files

| File | Where it is assembled | What |
|---|---|---|
| `os7.a99` | RAM: `runtime.a99` copies it in at `AORG >A460`, before `sound.a99` | `N_027F` SOUND_MAN (fused: $02D6/$012F/$00FC/$0190/$01A6/$01E9 inline), the vblank sound (`SNDVBL`/`SNDRUN`/`SNDFR`/`SNDEND`), `N_0F37` TIME_MGR, `N_10CB` TEST_SIGNAL (with the table-end shortcut) |
| `os7obj.a99` | shared segment (`COPY` before `RSEGE`): RAM was full | `N_0679` WRITER and its object drawer `OBJ` ($06E3): type 0 semi-mobile without a background save, types 2/3 sprites (with off-screen handling), type 4 complex. `PVSPR` (PUT_VRAM 0, the `$73C7` RAM-buffer mode too) and `QW` (TI-only fast paths) |
| `sound.a99` | RAM, after `os7.a99` | `N_PLAYSNG` PLAY_SONGS (`PSREAL`, compare-on-change per channel), `N_SNDOFF` |
| `fastpath.py` | `tools/` | the TI-only fast paths (QW, QW1, PVF) against N_WRVRAM |
| `sndclose.py` | `tools/`, run by `build.py` | the vblank sound's closure has no EXX / EX AF (SNDRUN's register subset depends on it) |
| `sndruncheck.py` | `tools/` | a vblank sound run preserves all 16 game registers, caller workspace, ROM bank and far-call stack |
| `sndtempo.py` | `tools/` | the sound engine runs once per owed vblank (SNDDUE), whoever runs it |
| `sndpollcheck.py` | `tools/`, needs the port's `routest.py` | a pending sound poll preserves an active GLUE return context while ordinary calls service the frame |
| `snddebtcheck.py` | `tools/`, needs `routest.py` | owed updates survive long sound/PLAY_IT runs; the discarded-debt mutation is rejected |
| `sndpaircheck.py` | `tools/`, needs `routest.py` | a pending frame with zero debt must enable both foreground sound halves together |
| `sndbankcheck.py` | `tools/`, needs the port's `routest.py` | both sound caller workspaces restore every hardware/software ROM bank; the missing-restoration mutation is rejected |
| `qcheck.py` | `tools/` | every QFLUSH and SATCK against a reference model of the queue entries |

Every mutation self-test must reject its deliberately broken case. These
tools report successful detection with exit code 0; a surviving mutant fails
the gate.

The port also needs these from Carnival's `runtime.a99`: `N_WRVRAM` /
`N_RDVRAM` (the deferred queue and sprite shadow), `N_0295` (SASSIGN),
`N_POLLER`, `WENDV`, `JPLOOK`, `C035F` (translated), the byte constants
`BCxx` (build.py generates every one a source file names), and `K`.
Take the queue code from Carnival's current `runtime.a99`, not an older
port's. It has:
- the head pointer `QHEAD` (>A450). A partial flush moves the head up and
  moves the leftover down only past QBUF+256.
- QFLUSH's inline path for entries under 8 bytes.
- SATCK's word copy.
- SATFULL saves the pending sprite count, destination and caller status across
  QFLUSH. The callee overwrites R2/R3/R15; losing a zeroed count makes the
  subsequent decrement underflow into a runaway copy. Keep the assembled
  `queuefullcheck.py` regression and its mutation from Carnival.
- WEND commits the completed batch for frame service; never flush using the
  stale tick-entry ONTIME flag. This is the user-confirmed flashing repair.
- TICKD also only commits. POLLN cannot prove the beam is still in blanking.
- Service pending frames at safe native boundaries: WRL, the type-0 object
  entry, READ_VRAM/WRITE_VRAM before their transactions, TIME_MGR before its walk, and
  N_PLAYSNG before deciding whether sound is due. The generic object file
  has the first two; Carnival's generated gallery calls its predecoded OB0P
  entry directly. Keep R0/R15 scratch and service outside queue cursor use.
  Carnival's later write-entry boundary is in its runtime, not these library
  files. Keep algorithm comparisons after that poll on both clones; test the
  actual scheduling boundary and production beam timing separately.
- Never add a poll between PLAY_SONGS and SOUND_MAN. A zero-debt skip by
  the first followed by a poll and a real second half loses song updates.
  SNDRUN calls PSREAL directly, bypassing the foreground poll. Retain the
  existing background-workspace guard at the original note-end poll.
- the single QFLUSH exit `QFX` that `qcheck.py` hooks.
- **reference entries** (`>2000|count`, VRAM address, TI pointer): QW1 and
  N_WRVRAM queue a row whose bytes are in the cartridge ROM ($8000-$BEFF:
  never written, so they can be read when sent) as a pointer instead of a
  copy. QFLUSH (`QF13`) and QOVLB (`QO8`) read them; test the fill bit
  (>4000) first, since a fill count can have >2000 set. 98% of Carnival's
  name rows come from ROM; this removed the byte copy (2.2k cycles a heavy
  tick).
- `QWR1`/`QWR11` (>A45C/>A45E): QWN keeps R1 across N_WRVRAM, for OB0's
  fast row loop.

## Integration checklist (Carnival is the worked example)

1. **runtime.a99**
   - `QEND EQU >AF80`. Formerly free >A452 is now SNDWP; >A45C/E are QWR1/QWR11. The os7 scratch is `>AF80-AF9F` (WRITER, TIME_MGR/TEST_SIGNAL, QWT at >AF9E: all used), the sound `>AFA0-AFFF` (SNDSAV 24 bytes, SNDDUE/SNDR11/SNDIYR at >AFF4-AFF9).
   - Clear SNDWP at boot. SNDRUN records its caller workspace there, chooses
     a fixed GLUEWS/SNDEWS return instruction, then clears it. There is no
     runtime instruction patch. Do not add another caller without extending
     and testing that fixed return dispatch.
   - Reserve SNDBNK at >F042, above the downward bank stack and below >F060.
     >AFFA is already SNDDE. SNDRUN must restore both the hardware bank and
     CURBNK after translated sound fragments: a tail jump can leave a cold
     bank selected even though all game registers have been restored. The
     interrupted PC may be in a different bank. Check BSP as well.
   - The boot clears `OBRET .. FSA1+2` (`LI R0,OBRET / CLR *R0+ / CI R0,FSA1+2`). `O4BSY` and `TSLAST` must start at 0.
   - `GLUE3` begins with `BL @SNDVBL`.
   - `COPY "os7obj.a99"` before `RSEGE`, then `AORG >A460 / COPY "os7.a99" / COPY "sound.a99" / RRAMEN`.
2. **ann.py**
   - `NATIVE`: 0x027F N_027F, 0x0300 N_PLAYSNG, 0x0295 N_0295, 0x0F37 N_0F37, 0x10CB N_10CB, 0x0679 N_0679, 0x11C1 N_POLLER, plus WRITE/READ_VRAM, FILL, WRITE_REGISTER and RAND.
   - `NATIVE_EXACT`: ALLREGS for SOUND_MAN, SASSIGN, TIME_MGR, TEST_SIGNAL. POLLER is ALLREGS - {a}. PLAY_SONGS is ALTS | {yh, yl}. **WRITER is ALTS**: it mirrors the BIOS's BC' DE' HL' scratch use in R9/R10/R13.
   - `NATIVE_USE`: none of them read registers, except TEST_SIGNAL (a), SASSIGN (IX), WRITE/READ_VRAM (BC DE HL), FILL (A DE HL) and WRITE_REGISTER (BC).
   - `NATIVE_DEF`: TIME_MGR {h l}. TEST_SIGNAL {a b c d e h l}. SOUND_MAN {a b c d e h l xh xl}. **POLLER {xh xl yh yl}**: without this, IY counts as live after the WRITER at the frame tick, and the WRITER native cannot be used there.
   - `NATIVE_FLAGS`: SOUND_MAN, SASSIGN and TEST_SIGNAL 'ZCSP'; TIME_MGR 'ZC'.
   - `PATCH`: PLAY_IT's busy count (0x025E `INC @SNDBSY`; 0x0269 and 0x027E return through `BLWP @SNDENV`); 0x06C0 `BLWP @WENDV`; **0x0FAA INIT_TIMER also does `CLR @TSLAST`**.
   - `HOT_ROUTINES = {0x06E3}` and `RUNTIME_CALLS = ('C035F', 'C06E3')`: the WRITER hands the object kinds it does not draw to the translated BIOS.
   - `NATIVE_COVERS`: the BIOS ranges the natives run themselves (Carnival's list); see the placement step below.
   - Retain the original 02EE sound poll via `NATIVE_POLLS = {'SNDPOL': 0x02EE}`
     and teach the deterministic harness that mapping, as in Carnival.
     FSEND skips it while SNDWP marks a background caller. Otherwise a BLWP
     into GLUE overwrites an already active return context before SNDIN can
     stop the sound recursion. Keep `sndpollcheck.py` and its mutation.
3. **Tools** (all already in Carnival's `tools/`):
   - Per-site native fallback: `xlate.native_at(site, t)` and `ann.NATIVE_SKIP`. `build.check_natives` sends only the call sites that can read a register the native does not leave to the translated original; the native stays everywhere else. Before this, one cold call site with a live register (Carnival's WRITER in the NMI handler and at the round start) removed the native from the hot frame tick too.
   - `build.runtime_size` fails if the RAM library passes `>AC00`. An overflow assembled cleanly into the sprite shadow and the queue.
   - `zplay.py profile` also writes `build/prof_z80_native.json`: each pc's share of its heat that falls inside native calls. `build.classify` scales that share out for the pcs in `ann.NATIVE_COVERS`, so translated BIOS code a native replaced stops taking hot room. Regenerating the main profile can change the whole layout: keep the old `prof_z80.json`/`coverage.json` and take only the fraction file from a new run (Carnival did).
   - `routest.py` compares A' BC' DE' HL' too.
   - `cspeed.py --profile` resets attribution at every AORG and names the os7 routines (`OS7_NAMES`). Before this, the sound frame and the WRITER were billed to the labels before them.
4. **Exactness rules the library follows** (keep them when extending it):
   - Never push native temporaries on the Z80 stack (R7). Lockstep excludes only the stack depth the game used, and Carnival keeps live data just below it. Use the os7 scratch words.
   - Leave R12 = 0 and R14 (A') alone. R0 cannot be an index register.
   - The fallback for an object kind not drawn natively is a **tail jump** to `C06E3` with IX/B as the BIOS had them, before anything is changed. Nested complex objects take it too, since the native keeps its state in fixed words.
   - TI-only work is gated on `PACE` (and `DEFER`); lockstep runs with them off.

## The vblank sound: who plays a frame's sound (SNDDUE)

The game calls PLAY_SONGS and SOUND_MAN once a tick, so a tick longer
than a frame slows the music. Under PACE the engine runs exactly once
per vblank. `SNDDUE` counts the vblanks not yet played:
- each vblank adds one, including while playback is blocked;
- the game's own call plays it for real when one is due. That is the
  usual on-time tick: there is no register save, and the registers are
  exactly the BIOS's;
- the vblank plays it itself (`SNDRUN`) only when two are due, i.e. a long
  tick ran past a vblank;
- a game call with none due returns the registers the last run left.

Carnival: +1.4 points over running every frame from the vblank.
`sndtempo.py` must show drift <= 2. Retain every SNDDUE update while
SNDIN or SNDBSY prevents re-entry; clamping debt to two loses music updates.
`snddebtcheck.py` tests six blocked frames and rejects the old clamp.

`SNDRUN` switches to the game's workspace with LWPI and saves only
R0-R8, R11, R12 and R15. A BLWP into the game's workspace would overwrite
R13-R15 (HL', A'). That subset is valid only while `sndclose.py` passes,
and `build.py` runs it.

## Measuring a change (Carnival's lessons)

- **Ticks per frame swing about 1.5% per seed in either direction**
  between two builds of the same code. Each build plays a different game:
  the game's randomness follows timing. Compare on 6-12 seeds run in
  parallel (Carnival `scratchpad/pspeed.sh`, Coleco counts cached in
  `build/zspeed.json`), or by the routine's cycles per call
  (`routest.py`) with the hot set unchanged (compare `labels.json`).
  A 3-seed run once showed a real gain as a 0.5-point loss.
- **Ticks are bimodal.** Most finish in under half a frame and wait, as
  on the Coleco. The loss is the heavy ticks (Carnival: about 30%, 1.5-2
  frames each). Profile the heavy ticks alone (`tools/heavyprof.py`, in os7lib),
  and leave out set-up ticks over 3 frames; they skew the averages.
- **Simulate a scheduling idea before building it.** Running the WRITER
  early, in the previous tick's idle time, looked like a large gain. A
  replay of the measured per-tick busy times (`scratchpad/earlysim.py`)
  showed +3 ticks in 1,244, so it was dropped.

## Validation (run all of it after any change here)

- `routest.py 0679 --ignore BC,DE,IX,IY` (with the alternate registers), then `routest.py 0F37`, `10CB` and `027F`, on two seeds and game modes. Carnival: WRITER 400 samples, TIME_MGR 200, TEST_SIGNAL 300, all 0 differ.
- `lockstep.py` 0 diffs: 200k ticks one player, and 150k ticks `--seed 2 --game 5`. Run it from a frozen copy of the tree.
- With PACE on, which lockstep never reaches: `fastpath.py`, `qcheck.py`, `sndruncheck.py` and `sndtempo.py` must each pass, and each one's `--mutate` must fail.
- Speed on 6+ seeds against the baseline. Carnival's speed per change:

  | Change | % of Coleco |
  |---|---|
  | baseline | 63.5 |
  | timers, RAM library | 64.1 |
  | native WRITER | 71.7 |
  | TEST_SIGNAL shortcut | 74.0 |
  | fast paths | 76.4 |
  | sound scan in a register, SNDRUN subset, TIME_MGR registers, QW threshold, QHEAD | 77.4 |
  | TIME_MGR CZC loop, QFLUSH inline, SATCK words | 78.3 |
  | SNDDUE | 79.6 |
  | small LDIR inline (translator), reference queue entries | 80.7 (5 seeds) |
  | OB0 fast row loop (ODF), bear hit confirmation | 80.5 (5 seeds: noise; the 2+ frame ticks went 94 -> 90) |

## Known costs left (Carnival, per tick, 79.6%)

| Cost | Cycles a tick |
|---|---|
| SOUND_MAN area scan (13 areas, 12 free at ~100 cycles each) | 2.9k |
| TIME_MGR (8.5 entries, 6 of them done one-shots that still count down) | 2.2k |
| WRITER: OB0, OB4, OBS, PVSPR, SATCK, OBJ, N_0679 | ~8k |
| QFLUSH | 1.9k |
| KSCAN + POLLER | 2.9k |
| TEST_SIGNAL (~555 cycles a call) | 1.4k |

**Find the ticks that lose a whole vblank.** Carnival's busy times per
tick (`scratchpad/earlysim.py`) had a separate mode at 2.0-2.5 frames:
~100 ticks in 1,500 frames, each one costing a full vblank. They are the
gallery rows redrawn as complex objects: ~13 components and ~24 name rows
each, 50k cycles of WRITER work. Profile that band alone with
`heavyprof.py SEED 1.95 ROWS 2.9` (the fourth argument is the upper bound).
Getting those ticks under 2 frames is worth more than any uniform saving.

OB0's rows (October 2026): an object wholly on the screen (row >= 0,
row + height <= 24) takes `ODF`. It has no per-row screen test, and DE'
holds the name table's address while it runs (subtracted after, since DE'
must end as the BIOS leaves it). The width stays in R1, and `($73FE)` is
stored once. That halves the ~600 cycles a row.

Tried and dropped, with numbers:
- a name-table compare-on-change: 14% of rows repeat;
- a sprite-entry compare-on-change: 25% repeat;
- running the WRITER early: +0.2% simulated.
