# TI-99/4A Game Core Definition (XB256 + XB Compiler)

This repository builds games for the **TI-99/4A** in **TI Extended BASIC**, targeting Harry
Wilhelm's **XB Game Developer's Package** (the `JUWEL7/` folder): the **XB256** graphics/sound
extensions plus the **XB compiler** for arcade-class speed.

This file is the binding spec for **every** game in this repo. The toolchain is nuanced — the
compiler is integer-only and silently changes or drops many XB behaviors, and code must behave
**identically when interpreted in XB256 and after compilation**. Write to these limits from the
start; do not "write it twice."

> **Mandate (non-negotiable): every game targets XB256 *and* the XB compiler.**
> All code must run under **XB256** (load/test with XB256 active) and must be **compiler-safe**
> (§6). That means: use the XB256 `CALL LINK(...)` routines for what they cover (§4), stay on
> **Screen2** by default, and never use a construct the compiler rejects (§2) or a plain-XB idiom
> that only works interpreted. If a feature exists in both plain XB and XB256, prefer the XB256
> form. **One exception that is itself an XB256 rule:** *sprite patterns are defined with
> `CALL CHAR`, not `CHAR2`* — sprites read the Screen1 pattern table (see §4).

> **Golden rule:** Perfect the program in interpreted XB256 first, then compile. The compiler
> does almost no error checking and reports no line numbers at runtime — an undebugged program
> just "quits."

All facts here were taken from `JUWEL7/DOCS/` (`XB256.pdf`, `XB Compiler.pdf`, `Using XBGDP.pdf`)
and the TI Extended BASIC manual.

---

## 1-3, 6. XB256 toolchain, compiler, language & checklist -> **skill `xb256-reference`**

The XB256/XB-compiler toolchain (Classic99 with `JUWEL7` as DSK1, the 6-file
`NAME`/`-M`/`-S`/`-O`/`-E`/`-X` pipeline), memory budget, reference assets, the integer-only
compiler landmines, the TI Extended BASIC language rules, the XB256 `CALL LINK` map, the
performance levers, the XB256 folder layout/lifecycle and the compiler-safe checklist all live in
`.claude/skills/xb256-reference/SKILL.md`. XB256 is not the recommended path for new games;
**invoke that skill before editing `games/dotmuncher` or `games/mspacman`.** Most games here are
CVBasic (§3A). Still binding here: §5A, §7A and §8's standing rules.

---

## 3A. CVBasic hazards (the current platform — always loaded)

**Lesson skills.** The long-form failure contracts below this list were moved into skills
(verbatim) so they load only when the task needs them. **Load the matching skill before:**
- editing sprite/character art, animation beats, text boxes or pattern/sprite-slot numbers
  -> `sprite-art-animation`
- changing any speed, timer, frame-delta pacing, chase/escape tuning or difficulty ->
  `game-timing-tuning`
- adding code or data when ROM/bank/PRG space is tight, banking, music budgets, or
  running romprofile/romclones -> `rom-budget`
- writing or changing any `check*.py` gate, `*_test.py`, layout checker or build-time
  step -> `checker-design`
- touching title/menu/setup screens, `cont1.*` input, ALPHA LOCK, key-release handling
  or boot ordering -> `ti-input-screens`

- **Never `MODE 2`.** It compiles clean and renders broken on both targets. Use the default
  startup mode with `DEFINE CHAR`/`DEFINE COLOR`.
- **Never `<cmp> AND <cmp>` / `<cmp> OR <cmp>` on TI** — the 0.9.2 TMS9900 backend ANDs against
  a stale register. Nest single-comparison `IF`s.
- **A bare `IF #word AND 1 THEN` can test the HIGH byte on TI.** Hard Hat Mack's
  five-point score formatter compiled that expression as `movb @cvb__SCVALUE,r0`,
  so a stored score of 1000 displayed as 5005 instead of 5000. Preserve the word
  width explicitly: `#scodd = #scvalue AND 1`, then `IF #scodd THEN ...`.
  Verify `mov @cvb__SCVALUE,r0 / andi r0,1` in the generated assembly. Its TI
  `assets/checkbank.py` checks both score formatters and rejects byte-read mutations;
  source-level arithmetic tests alone cannot detect this backend error.
- **CVBasic has NO local variables.** Every variable is global, so a scratch temp that reuses a
  state variable's name silently corrupts it — a camera temp named `#hi` clobbered the HIGH
  SCORE every frame. Prefix temps per routine and grep the name before adding one.
- The TI short-branch pass may pull a source-line suffix into the fixed address window when
  earlier long branches shrink. Its planner accepts up to one page of pre-relaxation overflow
  (including five-digit listing addresses); the verifier still requires every final instruction
  inside the fixed window and checks retained addresses and each rewritten branch.
  **That tolerance is luck, not headroom:** xas99's unoptimized first pass rejects any short
  jump that straddles `>FFFF` ("Out of range ... -0x7ffe"), so code past the wrap breaks the
  build the moment a growth shifts a jump across it. Hard Hat Mack was already 154 bytes over
  when a ~300-byte change made three jumps straddle. Keep the unoptimized pass under `>FFFE` by
  banking pure routines (skill `rom-budget`), and measure it by assembling a scratch copy
  with `aorg >9000`.
- **Constants > 255 truncate to 8 bits** in three shapes: `CONST X = 768` used in a 16-bit
  assignment compiles to `CLR`; a folded dotted constant (`$1800 + 728.`) truncates the addend;
  and **an 8-bit var times a constant > 255** compiles to `CLR`. The threshold is **256, not
  2048** — `mhi * 256.` emitted a bare `clr`, which silently reduced every music note to its low
  byte. (`* 34.`, `* 68.`, `* 136.` are all fine.) Use bare 16-bit literals, precomputed values,
  an IF-ladder, or repeated doubling (`#x = #x + #x` eight times == `* 256`).
  **Check the generated `.a99`** when a multiply matters: this failure is completely silent.
- **READING A 16-BIT VAR RIGHT AFTER MULTIPLYING IT RETURNS THE PRODUCT'S HIGH WORD (usually 0).**
  On the TMS9900 `MPY` writes a **32-bit** product into a register *pair*: the low word (the
  answer) lands in `r1` and **`r0` is overwritten with the high word**. CVBasic stores `r1`
  correctly and then keeps believing `r0` still holds the multiplied variable, so the very next
  statement that reads it compiles to a register move of the *high* word — zero for any product
  under 65536:
  ```
  #droprl = #droprl * 15      li r1,15
                              mpy r1,r0            ; r0 = HIGH word, r1 = low word
                              mov r1,@cvb__DROPRL  ; correct
  #bstep  = #droprl           mov r0,@cvb__BSTEP   ; WRONG -- stores 0
  ```
  No compile or run-time error; in Bust-A-Bobble the only symptom was a drop-timer gauge that
  sat full and never drained. **Fix: put the dependent computation behind its own label**
  (`GOSUB calc_x`) — a branch target forces the compiler to emit a real load — or otherwise break
  the register-tracking before re-reading. Applies to *any* read of a just-multiplied 16-bit
  variable, so it is much easier to hit than the `CLR` truncation above. Verify in the `.a99`:
  the good form is `mov @cvb__SRC,@cvb__DST`, the bug is a bare `mov r0,@cvb__DST`.
- **`VPOKE` takes a RAW VRAM address; the name table is at `$1800` (6144). `SCREEN`'s target
  offset is name-table-RELATIVE (0–767).** Mixing them up writes your name-table data into the
  **pattern table**, i.e. it corrupts the character set: the symptom is a field of junk tiling the
  whole screen, missing walls/borders, and garbled text — not a crash, and not obviously an
  addressing bug. Add 6144 as **its own step** (`#a = row*32+col : #a = #a + 6144`), never folded
  into a constant expression (folded constants truncate, per the item below). Cost a Puzzle Bobble
  session; `RALLYX.bas:1434` carries the same warning.
- **`DEFINE COLOR n,total,label` needs EIGHT bytes per character** (one per scan line, this is the
  per-8×1-line colour mode), not one. `DEFINE COLOR 32,16,tbl` reads **128** bytes. Supply fewer
  and it silently reads whatever follows in ROM as colour data — text and tiles come out in random
  colours with no error. `DEFINE CHAR` is 8 bytes/char and replicates across all three screen
  thirds automatically.
- **A PLAIN VARIABLE IS 8-BIT, so `v = 463` silently becomes 207.** Same family as the `CONST`
  item below but it bites in ordinary code: any screen offset past row 7 (`row*32+col > 255`), any
  VRAM address, any pixel count over 255 must go in a `#var`. Nothing warns at build or run time —
  in Bust-A-Bobble the 838 menu's `rdp = 463` put the typed digits at row 6 instead of row 14, which
  read as a deliberate (if odd) layout choice rather than a bug for weeks. **It then happened AGAIN
  the same day, hours after being written down here**: `sdc = 713` (row 22, col 9) truncated to 201
  and punched a black 2×2 hole through row 6 of the playfield on every redraw. Recording the rule is
  not enough — **grep any new routine for bare assignments over 255 before building.** The symptom is
  never an error; it is drawing or writing at a plausible-looking wrong place, 256 or 512 cells off.
- **`CONST` > 255 is silently TRUNCATED TO 8 BITS — bare literals are fine.** This is the sharpest
  edge of the truncation item above and deserves its own line: `CONST FXMIN = 4096` compiled to
  `ci r0,0` and `#bx = FXLX` (20480) compiled to a bare `clr`. A ball launched from 0,0 and no wall
  ever bounced. The same values written inline (`IF #bx < 4096`, `#bx = 20480`) compile correctly,
  as does `SOUND 0,300` → `li r0,300`. **The distinction is CONST vs literal, not the magnitude.**
  Never put a value above 255 in a `CONST`.
  - **It truncates, it does not zero** — `clr` is only the case where the low byte happens to be 0.
    `CONST RNDPOS = 311` compiled to `li r0,55`, and 55 is a perfectly plausible name-table offset,
    so the write landed *somewhere real*: row 1 columns 23-24, on top of the score, instead of row 9
    under its label. A wrong-but-plausible address is far harder to spot than an obvious zero.
  - **A CONST can be safe for months and then break without being edited.** That 311 was `247` for
    as long as `ROUND` sat on row 7 of the HUD. Moving the label down two rows pushed the *derived*
    offset over 255 — so the change that broke it was a layout tweak, and the value it broke was one
    nobody was looking at. **Any `row*32+col` constant is one row-move away from this.** Screen
    offsets belong in bare literals from the start.
  - **`tools/bigconst.py` sweeps every game for it** and exits non-zero if it finds one. Run it after
    any layout change.
- **Every sound effect needs an explicit note-off.** `SOUND ch,f,v` latches; with no `SOUND ch,f,0`
  the last tone sustains forever ("sticky" audio). Two `SOUND` calls on the *same* channel back to
  back just cancel the first — a two-note effect needs two channels. Keep a per-channel decay
  counter and tick it after **every** `WAIT`, including inside animation loops that don't run the
  main loop.
- **`SOUND`'s second argument is a 10-bit DIVISOR, not a frequency — smaller is HIGHER**
  (`RALLYX.bas:1118`: "a smaller divider is a higher note"). Two traps, both silent:
  (1) the field is **10 bits, max 1023** — anything larger is masked, so `SOUND 0,2400,10` plays
  some unrelated pitch rather than a high one; (2) rising/falling sweeps read backwards, so a
  "descending" tone written as a decreasing argument actually rises. Pitch ≈ 3579545/(32·n):
  n=100 → ~1100 Hz, n=250 → ~450 Hz, n=900 → ~124 Hz. In Puzzle Bobble this had a *high ping*
  standing in for the ceiling's low clunk and four effects silently masked, none of which
  produced any error.
- **AN ODD-LENGTH `DATA BYTE` BLOCK SILENTLY MISALIGNS EVERY WORD TABLE AFTER IT.**
  The TMS9900 **ignores the low bit of a word address**: `mov *r0,@dst` from an odd
  address reads the word *below* it and does not fault. CVBasic emits `even` after its
  own string literals but **not** after a hand-written `DATA BYTE` run, so a block with
  an odd byte count leaves the location counter odd and every `DATA` (word) table
  defined later in that segment lands on an odd address — and reads back **shifted one
  byte, for ever**. In Bust-A-Bobble a 33-byte marquee table put `#aimdx` on `>68FB`, so
  `#aimdx(0)` returned **3840 instead of 0**: the aim guide dots landed 60 px apart
  across the HUD, and a shot the player aimed straight up left at a severe angle and the
  wrong speed. Nothing in `cvbasic` → `xas99` → `linkticart` said a word, and it hit all
  three carts at once because the table sat outside every `#if`.
  - The tell is **one value wrong at one index while neighbours look fine** — a shifted
    table reads `(low byte of entry i-1) << 8 | (high byte of entry i)`, which is
    plausible garbage for some entries and near-zero for others, so it presents as "only
    this one case is broken" rather than as corruption.
  - **Keep every byte block even.** Pad with an unused byte and say why in a comment.
  - **`romcheck.py` now checks it mechanically** and fails the build: it finds every
    `ai r0,<label>` + `mov *r0` pair (how the compiler indexes a word table), reads the
    label's resolved address out of the `xas99` listing, and reports any that is odd.
    Verified against the real defect, not just against a passing build.
  - **Read the label's VALUE, never the next listing row.** xas99 pads a `DATA` (word)
    block to an even address, but a label alone on the line above it keeps the odd
    location counter: Choplifter's `#sprite_bit` label was `>FEAF` while the listing showed
    its data at `>FEB0`, so a check that binds a label to the next emitted address passes
    the bug. `romcheck.py` reads the `ai r0,<label>` operand; Choplifter's `tools/build.py`
    reads xas99's `-E` symbol file. Proven against a deliberately odd block.
- **A "STOP EVERYTHING" ROUTINE THAT ENUMERATES STATE BY HAND GOES STALE, AND
  NOTHING TELLS YOU.** Keystone Kapers' `snd_off` silences the chip and clears
  the effect latches between rounds. It named channels 0, 1 and 2 and four decay
  counters, and it was correct when written. Then the footstep moved to the
  **noise** channel and the prize arpeggio gained a counter, and neither joined
  the list. Two sounds outlived their round: a footstep ringing when the crook
  was caught hissed through the entire bonus tally, and a prize taken late in a
  round dinged over the start of the next one.
  - **The routine looks finished in every state**, because nothing in it says
    what the complete set is. Reading it will not find the bug; only comparing
    it against the producer will.
  - **Zeroing a decay counter does not silence anything.** These counters emit
    their note-off on the pass they reach zero, so assigning zero by hand skips
    the very write that would have stopped the sound. The channel needs its own
    explicit off.
  - Fix it by **deriving the set from the producer**: `assets/checksound.py`
    reads every channel `sfx_tick` writes and every variable it tests in an
    `IF` -- exactly the state that can make a sound on a later pass -- and fails
    if `snd_off` misses one. A second hand-kept list inside the checker would
    have gone stale identically. Run against the defective source it named both
    faults and a third nobody had noticed.
- **A `PRINT AT` PAST COLUMN 31 WRAPS ONTO THE NEXT ROW, and a HUD `VPOKE` can land INSIDE a
  label another routine printed.** Both are arithmetic on a bare offset, so neither is visible
  in the source and neither produces an error: the first overwrites a line you were not editing,
  and the second reads as a *typo in the label* rather than as a misplaced value. Bust-A-Bobble
  and Joust both position text this way; UFO!'s `838` screen shipped its difficulty digit into
  the middle of the word `DIFFICULTY`.
  - **`games/UFO/assets/checklayout.py` checks it mechanically** and is wired into both build
    scripts — it parses every `PRINT AT` and every statically resolvable `#addr = <literal>` +
    `VPOKE #addr` pair and fails on an overflow or a collision.
  - **Its first version passed the very bug it was written for**, and the reason generalises to
    any checker in this repo: it compared writes only against strings under the **same label**,
    but the setup screen prints its text in `setup838` and writes its digits in `su_draw`. A row
    only means the same thing within one **screen**, and screen boundaries are *not derivable
    from the source* — they have to be declared. **A check whose scope is narrower than the bug
    is worse than no check, because it reports success.**

- **A ROUTINE THAT ERASES SCENERY WILL ERASE STRUCTURE TOO, AND THE SYMPTOM IS
  A BUILDING THAT STANDS ON NOTHING.** Anything drawn on top of a tile map needs
  a matching "take the fixture with it" pass -- pull down the pillar top, wipe
  the rest of the counter -- and that pass matches on the CHARACTER CODE. If one
  code is used for both a removable fixture and a permanent part of the world,
  the erase hits both. Keystone Kapers' `beam_clear` cleared all four floor-bar
  cap characters, two of which (`SLABE`, `ROOFSE`) are written only at column 0
  and column 31 and are the **building's outside wall**: a radio placed beside
  the wall silently deleted the second floor's support.
  - **It presented as a bug in the DRAWING code, and it is not.** The report was
    "only the escalator screens, and mirrored on the other side" -- a clean,
    specific, structural-sounding clue. Four passes over the templates, the
    beam-column table, the blit order and the head-cap columns all came back
    correct, because they were: the damage was done *afterwards*, by a routine
    whose entire job is removing things. **When every input to a drawing looks
    right, stop re-reading the drawing code and enumerate what writes to those
    cells LATER.**
  - The screen-type correlation was real but indirect: the escalator flight
    fills the middle of its band, so those screens are the only ones where a
    fixture lands close enough for a two-cell clear to reach the edge column.
    **A "this only happens on screens of type X" clue can point at where the
    ACTORS end up, not at how type X is built.**
  - Fix by making the distinction provable from the data: give permanent
    structure its own character codes and never match them in an erase. Do not
    guard on the coordinate -- the coordinate is a fact about this layout, the
    code is a fact about what the cell means.
- **A PATTERN BLANKED IN ONE SCREEN THIRD IS INVISIBLE FROM EVERY OTHER THIRD,
  SO PROBING THE NAME TABLE PROVES NOTHING.** In bitmap mode the pattern and
  colour tables are three independent copies, one per eight rows. Write zeros
  over character N in the bottom third and it still draws correctly in the top
  two: on screen it becomes a cell of its own background colour, in the bottom
  eight rows only. The name table still says N, the templates still say N, and
  every check built on either agrees that nothing is wrong.
  - Keystone Kapers' `scan_wipe` cleared its radar canvas with a hand-computed
    `4096 + SCAN_FIRST*8`. `SCAN_FIRST` later moved from 160 to 208 and the
    address did not, so it blanked the 48 characters *below* the canvas --
    including the building's outside wall and a pillar cap. The ground floor's
    wall vanished while the identical wall one storey up was perfect, for
    months, and only on the two screens that carry an end wall.
  - **A raw VRAM address is a character code in disguise.** A renumbering tool
    that rewrites `CONST CH_*` from the art tables will not touch it, which is
    exactly why it goes stale in silence. Derive it or gate it.
  - **A probe that copies the character somewhere else to look at it cannot see
    this** -- the copy renders from the third it was copied into. To test a
    suspected glyph problem, read the pattern bytes, or put the probe in the
    same third as the fault.
- **HIDING A SPRITE *AFTER* DRAWING IT SHOWS IT, whenever the routine can span a
  vblank.** CVBasic's `SPRITE` writes a RAM mirror that the vblank ISR copies to
  VRAM, so a draw-then-hide in one pass is only invisible if no vblank falls
  between the two writes. A long draw routine on a busy screen spans two or three
  frames, so the intermediate state is latched constantly. In Keystone Kapers the
  player flickered at the floor he had just left while riding the lift, which
  reads as a drawing bug and is not one. **Decide visibility BEFORE drawing** --
  it costs one test and the mirror never holds a position to be caught with.
- **`#var` comparisons are unsigned** — signed logic (`< 0`, wraps) needs a split at 32768.
- **`%` compiles to a real DIV**, even by a power of two — hand-convert (`% 8` → `AND 7`).
- **`DIM a(N)` is 0..N-1.** A one-past-end write is silent on TI and black-screens ColecoVision.
- **VDP writes are buffered per frame**; bursts beyond a few dozen are silently dropped. Pace
  with `WAIT`. `VPOKE` operands must be precomputed into plain vars (ISR race), and TI
  `DEFINE CHAR`/`COLOR` are synchronous (safe in bulk).
- **Sprite y = 208 terminates the sprite list** — hide sprites at 209, and watch for `y-1`.
- Misc: 8-bit `FOR` to 255 loops forever; `ON GOTO` is 0-based; `DEF FN` args substitute
  textually (parenthesize every use); a computed `FOR 1 TO 0` still runs the body once.
- **`DEFINE CHAR/COLOR/SPRITE` CANNOT TAKE A RAM ARRAY, AND IT DOES NOT SAY SO.**
  `DEFINE CHAR 65,1,buf` with `DIM buf(64)` compiles cleanly to `li r0,cvb_BUF`, but
  the array lives at `array_BUF` (TI), so the upload reads from a label that is
  either undefined or, worse, some other variable. `DEFINE`'s source must be a
  `DATA` label. To upload RAM, write the VDP yourself (or through a routine that
  takes an address). `VARPTR buf(0)` *does* give the array's real address. Found
  while planning Keystone's TI compression (its DESIGN.md section 53).
- **A `GOSUB` THAT LEAVES BY `GOTO` LEAKS THE STACK — and only ColecoVision dies of it.**
  A routine entered with `GOSUB` and exited with `GOTO` never pops its return address, so every
  pass through it grows the stack by the whole call chain. Bust-A-Bobble's `do_clear` and `do_dead`
  did this on every completed round and every death, from four levels deep. On the **TI** the leak
  has ~7 KB of RAM to chew through and never surfaced in months of play; on **ColecoVision**, with
  1 KB total and ~150 bytes of headroom above the variables, about twenty rounds walked the stack
  down into them. The symptoms look like anything but a stack: score digits printing as unrelated
  characters (a corrupted BCD array read through `48 + digit`), an animation hanging, and
  corruption that survives into the title screen because nothing reinitialises those variables
  without a reboot. **Set a state variable, RETURN, and dispatch from the main loop.** The tell is
  the combination — *gets worse over time*, *one target only*, *ends in a hang* — and the
  asymmetry is just the RAM budgets. **`tools/gosubtrace.py` checks this mechanically**: it walks
  the control flow out of every `GOSUB` target — both `label: PROCEDURE … END` and
  `label: … RETURN` — and reports any that cannot reach a return. A `GOTO` into *another* routine
  that returns is a tail call and is correctly not flagged. Run it over `games/*/src/*.bas` after
  any change to a game's control flow; it swept the whole repo and found one more instance
  (Astiroids' `game_over`, since fixed).
- **THE BUILD CHAIN IS CYGWIN AND GIT BASH SHADOWS IT — BOTH HALVES ARE SILENT.**
  `cvbasic.exe` (and `gasm80.exe`) are **Cygwin** binaries. Git Bash is MSYS2 and puts its own
  `msys-2.0.dll` first, so running one from a bash build script dies with
  `cvbasic.exe: error while loading shared libraries: ?: cannot open shared object file`
  — exit 127, no line number, nothing about the program being compiled. The same command from
  PowerShell works, so it reads as *the toolchain is flaky under bash* rather than as one
  directory in the wrong order, and Keystone Kapers' build script carried a "run it from
  PowerShell instead" note for months because of it. **Put `C:\cygwin64\bin` at the FRONT of
  `PATH`.**
  - **And the second half: Git Bash rewrites an absolute POSIX ARGUMENT into `C:/...` before
    handing it to a native program, which Cygwin's python does not read as absolute** — it
    joins it onto the cwd and reports `can't open file '<cwd>/C:/Users/...'`. Relative
    arguments are untouched, so only paths to tools *outside* the tree are affected
    (`xas99.py`, `linkticart.py`). Pass those in the `/cygdrive/c/...` form with
    `MSYS2_ARG_CONV_EXCL='*'` set for that one call. `games/KeystoneKapers/build-ti.sh`'s
    `cygpy` helper does both, and detects a Cygwin interpreter with
    `sys.platform == "cygwin"` rather than assuming one.
- **PYTHON'S BYTECODE CACHE IS STALE FOR A WHOLE SECOND, which is long enough to matter when a
  generator and its consumers run back to back.** `.pyc` freshness compares **whole seconds**
  of mtime, so editing `genart.py` and re-running a script that imports it inside the same
  second silently reuses the OLD module — the generated art, the templates and every checker
  all come from code that no longer exists on disk. Observed as a checker insisting on a value
  that had just been changed. `rm -rf __pycache__` as the first step of any generate stage;
  both Keystone Kapers build scripts do.
- **Build BOTH targets every time**, not just TI. `#if TI994A` needs the **unhuman/CVBasic**
  fork (stock nanochess has no preprocessor).
  - **TI inline `ASM` does not invalidate the compiler's register cache.** After
    a BASIC assignment and raw assembly, an `IF` on that same variable can
    compile to a conditional jump with no reload/test. Explicitly restore the
    cached value and condition flags before returning to BASIC (for a byte in
    R0, `ASM MOVB @cvb_NAME,R0`). Check the generated assembly. Keystone's
    cancel-key scanner needs this to avoid silencing effects on ordinary frames.
  - **Inline `ASM` that writes the VDP ports must hold interrupts off across each
    address-and-data sequence** (`LIMI 0` … `LIMI 2`, exactly as the runtime's `WRTVRM`
    does): the vblank handler sets its own VDP address, and landing between your two
    address bytes sends the data elsewhere. The handler runs in its own workspace
    (`>8320`), so main registers R0-R9 survive it; R10 is CVBasic's stack. Choplifter's
    `tools/check.py` interpreter rejects a port write made with interrupts enabled.
  - **A word `DATA` table is read through a `#` label** (`#tbl:` / `#tbl(i)`). Written
    as `tbl(i)` it compiles to a BYTE read at an un-doubled index, with no warning; a test
    model that holds the table as a list of words will agree with the bug, so make it
    refuse word values read through a byte name.
  - **An UNDEFINED name in `#if` is silently FALSE** — no error, no warning. So a mistyped
    `-DEXPRT=1` compiles the *other* branch and every tool in the chain reports success. When a `-D`
    selects which content a cart carries, that is a wrong cart with a right-looking name. **Make the
    source announce which branch it took** with `#info` and have the build script grep the compiler
    transcript, rather than trusting the flag it just passed.
  - **`#info` prints only its FIRST TOKEN.** `#info BUILDING THE EXPERT SET` emits
    `INFO: BUILDING` — which matches both branches and makes the guard useless. Use one underscored
    word (`#info BUILDING_EXPERT_SET_50_GENERATED_LEVELS`).
  - `#if` **cannot nest** ("Nested #IF not supported"), but each INCLUDEd file gets a fresh
    conditional state, so a file boundary buys one more effective level. An `INCLUDE` inside a false
    `#if` is never opened, which is how one source can select between two data files.
- **NES target (CVBasic `--nes`) -> skill `nes-target`.** The full NES porting contract -- CHR-RAM
  uploads through `ASM`, the 32x30 name table and its +24 px sprite offset, per-character colour
  through the second bitplane, `SPRHID` 240, the ~100-byte-per-frame `PPUBUF` vblank budget and its
  whole-screen-jump symptom, the APU shim, the NES RAM mirroring trap, and the palette and
  forced-blank lessons -- now lives in `.claude/skills/nes-target/SKILL.md`. **Invoke that skill
  whenever building or debugging an NES build** (`games/KeystoneKapers/build-nes.sh`, any `#if NES`
  branch). It is not always-loaded because one game currently has an NES target; everything binding
  for the TMS targets stayed here.
## 5A. Runtime Performance Budget — design for speed from line 1

The compiler makes the program *correct*, not *fast*. On **original hardware** an XB256 design that
ignores per-frame cost can be **unplayably slow even compiled** (lesson learned the hard way:
`games/mspacman` is correct and compiler-safe but crawls on a real TI-99). Speed is an architecture
decision made in `DESIGN.md`, not something to optimize later. **Mental cost model:**

> per-frame cost ≈ (moving actors) × (per-actor work) + (per-frame VDP round-trips)

`games/mspacman` maxes out every term — and is the cautionary reference for what *not* to do:
it repositions all 5 actors by CPU every frame (`CALL LOCATE`), runs a 4-direction pathfind for
**each** of 4 ghosts **every frame**, and does many per-frame `CALL GCHAR` wall reads.

XB256-specific levers (`CALL MOTION` vs `LOCATE`, `GCHAR` mirrors, actor caps)
are in skill `xb256-reference`. For CVBasic, see §3A and skill `game-timing-tuning`.

**Mandate:** every `DESIGN.md` opens with a **Performance Budget** block stating: max
simultaneously-moving sprites; `MOTION`-vs-`LOCATE` choice per entity type; a ceiling on per-frame
`GCHAR`/`COINC` calls; and whether the loop is real-time or input-paced. Decide these *before* line 1.
If a concept implies "many actors each thinking every frame," expect Ms. Pac-Man-class slowness and
redesign or pick a different game.

---

## 7A. Arcade Conventions (binding for EVERY game in this repo)

Player-facing conventions that arcade players read without thinking. Getting one wrong does not
look like a bug, it looks like the game is broken — so these are rules, not preferences.

- **The lives/ships/cars indicator shows SPARES — the reserves, EXCLUDING the life being played.**
  A fresh 3-life game shows **two** icons; the last life shows **none**; game over is the crash
  that happens with zero showing. Never draw one icon per total life. Drawing the current life as
  well is an anti-convention: the icon disappears the moment play starts, which reads as having
  already lost one, and the player can never tell whether the last icon means "one more chance"
  or "this is it". This has been got wrong repeatedly in this repo — check it in every game.
  - Watch the underflow: the decrement-then-redraw-then-test-for-game-over order means the draw
    routine IS called with `lives = 0`, and these are unsigned 8-bit vars, so a bare `lives - 1`
    wraps to 255 and lights every icon exactly when the player has none. Guard it
    (`IF lives > 0 THEN spare = lives - 1`).
  - **RIGHT-JUSTIFY THE ROW so the last icon sits in the last column.** Filling from the left
    means the row empties from the RIGHT, and the final life ends up alone several blanks from
    the screen edge — a position that says nothing about why it stopped there. Growing leftward
    from a fixed right edge keeps one end anchored, so the count is read off the row's left-hand
    end and the icons always finish in the same place.
  - **And write the justification test WITHOUT the subtraction.** `IF slot + spare > last` is
    the same rule as `IF slot >= width - spare` and only the first is safe: `spare` is unsigned
    8-bit, so `width - spare` wraps to ~250 the moment a cheat or a setup screen grants more
    lives than the row can hold — lighting every cell at exactly the point the indicator should
    be saturating. Same underflow as the `lives - 1` above, at the other end of the same routine.
  - A setup/options screen that asks for "number of cars" still means TOTAL cars (3 cars = 3
    plays). Only the in-game HUD counts reserves.

## 8. Per-Game Structure & Lifecycle

Every game is built the same way — that consistency is the point.

> **Standing rule — keep the docs in sync with the code (non-negotiable).** Any change to a game's
> behavior, layout, colors, controls, line numbers, or asset/build details **must** update that
> game's `DESIGN.md` *and* `README.md` in the **same change**, so the docs never describe stale
> behavior. Treat the source, `DESIGN.md`, and `README.md` as one unit: don't consider an edit done
> until the docs that describe it match (and the cross-referenced line numbers/labels still point at
> the right lines). When a change exposes a new toolchain hazard or rule, also record it in the
> relevant section of this `CLAUDE.md` (e.g. the §2 compiler land-mines) so future games inherit it.

> **Standing rule — leave the emulator running when you hand work back (continuous development).**
> Finish every work session by launching the **newest** build in Classic99 (kill any older instance
> first, so exactly one window is up, running the cart you just built) and **leave that window open**
> for review. Intermediate probes — screenshot captures, A/B comparisons — may open and close freely;
> the rule governs the final hand-back state. If the change is in a later level, build a separate
> level-start cart (e.g. `NAME_L2_8.bin`) so the reviewer doesn't have to replay earlier levels, and
> keep the committed source at its normal starting level. **Verify the open window is running the new
> cart** — an emulator left open from an earlier build shows stale behavior and reads as "your fix
> didn't work."

- **SDL emulator input needs scan codes.** Windows `keybd_event(vk, 0, ...)`
  reached Classic99 but delivered no input to CoolCV, despite valid foreground
  focus and screenshots. Supply the scan code from `MapVirtualKey(vk, 0)`;
  arrows also need `KEYEVENTF_EXTENDEDKEY` on both press and release. Verify an
  actual menu selection or movement before diagnosing the ROM's input code.

- **`core.autocrlf=true` MAKES EVERY SHELL SCRIPT UNRUNNABLE AFTER A CHECKOUT.** Git stores LF
  and hands the working tree CRLF, and bash does not fail on the carriage returns themselves —
  it reports `syntax error near unexpected token $'{\r'`, which reads as a broken script rather
  than as a line-ending problem. It appears after a *checkout* rather than after an edit, so
  nothing in the session points at the cause. Pin it in `.gitattributes` (`*.sh text eol=lf`,
  and the same for any source a Cygwin tool reads) rather than converting the files by hand,
  which only lasts until the next checkout.
- **THE VDP PUTS A SPRITE'S TOP LINE AT y + 1.** Replacing a character-drawn marker with a
  sprite carries the old y across and everything lands one pixel low — which matters when the
  thing is three pixels tall in a three-pixel band, because its last row then sits on whatever
  it was meant not to touch. Bias the y by −1 and put the bias in the CHECKER too, or the check
  agrees with the bug.

- **A LATCHED EFFECT FLAG IS A SOUND THAT HAS NOT HAPPENED YET, AND SILENCING THE CHANNELS DOES
  NOT CANCEL IT.** Keystone Kapers sets `sf*` flags that the main loop's sound routine consumes
  on its next pass. Between a capture and the next round the main loop does not run — so a hit
  latched as the round ended, or a bonus life the tally just awarded, survived a full
  `SOUND ch,0,0` on every channel and then fired on the FIRST pass of the new round, with a
  fresh decay counter. It presents as "a long beep at the start of a level that earned nothing".
  - Generalises to any deferred event consumed by a loop that stops: a "silence everything"
    routine must clear the **pending** queue as well as the current state, or the pause simply
    postpones the noise into a context where it makes no sense.
- **A MULTI-FRAME BLIT LEAVES THE PREVIOUS STATE'S SPRITES STANDING ON TOP OF IT.** A screen
  redraw that `WAIT`s between bands (necessary — a burst past a few dozen VDP writes in one
  frame is silently dropped) takes several frames, and sprites are not part of the name table,
  so they keep drawing throughout. Following an actor through a screen seam showed him and every
  obstacle from the floor he had just left, standing on a shop assembling itself underneath.
  **Hide the sprites before the blit, not after** — the normal draw puts them back on the same
  pass. Hide only the ones that belong to the screen: a HUD or radar sprite blinking out on
  every crossing is a new fault in place of the old one.

- **AN OVERLAY POKED AFTER A VBLANK-SYNCHRONISED COPY RACES THE BEAM.** Choplifter copies its
  scenery rows straight after a `WAIT`, then pokes the burning roofs and open doors back over
  them. Queued behind two more row copies, the fence stamps and the flag, those pokes finished
  after the beam had passed rows 17-19 whenever two camps were in view, so for one frame per
  scroll an evacuating camp showed its closed roof and door. It reads as video corruption, and a
  screenshot only catches it sometimes. **After a synchronised copy, restore the overlays on the
  rows just copied first, top of the screen first**, then do everything lower down.
- **ON A CROWDED SCANLINE, GIVE WHATEVER CAN KILL THE PLAYER THE SLOTS RIGHT AFTER THE
  PLAYER.** The VDP draws four sprites per line, lowest slot first. Choplifter's tank shell sat
  in slot 8, behind the tank's two halves, so with the helicopter landed beside a tank the shell
  was the fifth sprite on its lines exactly when it was about to hit: deaths "for no reason".
  Pin the player, put enemy projectiles next, and rotate the rest each update (from a ROM table,
  reversing the order on alternate updates so any two neighbours take turns), so overload becomes
  flicker instead of an invisible bullet. CVBasic's `SPRITE FLICKER` would rotate the player too.

- **A SENTINEL VALUE THAT IS ALSO A VALID VALUE WILL EAT THE VALID ONE, AND ONLY HALF THE TIME.**
  Keystone Kapers stored a table of support-beam COLUMNS with 0 meaning "no more entries" — and
  column 0 is where the west end wall stands. Every west wall was silently skipped while the east
  wall at column 31 worked perfectly, so it read as intermittent rather than systematic, and the
  half that worked kept "proving" the mechanism was fine. Store `value + 1` (or use a separate
  count) whenever 0 is in the domain.
  - The previewer had the identical bug, so every render agreed with the defect. **When a checker
    and the code are written from the same assumption, the checker cannot see the assumption.**
### Classic99 launch directory selects the input profile (2026-09-21)

Classic99 reads `classic99.ini` relative to its launch working directory on this
installation. Keystone's stable launcher initially used the executable folder,
which selected a different joystick profile from the project's established one.
Both old and new ROMs ignored Tab there, while the current ROM started and moved
normally when launched from the project root. Preserve that working directory
in `tools/keystone-dev.ps1 LaunchTI`; report the ROM and configuration folder.
Do not work around a launch regression by broadening game controller semantics
before comparing old and new builds under identical conditions.




### SCREEN SOURCE STRIDE IS A BYTE ON THE TMS TARGETS (2026-10-04)

CVBasic reduces SCREEN width, height and optional source stride to eight bits on
TI and Coleco. A 256-column map therefore cannot use a single multirow SCREEN
with stride 256: it becomes zero and repeats the same source row. Choplifter's
eight-screen world uses consecutive one-row SCREEN calls, advancing a word
source offset by the bare literal 256 between them, all after the same WAIT.
Its source-executing checker models byte-sized SCREEN arguments and rejects a
mutation restoring the zero-stride multirow copy. Inspect generated assembly;
plain successful compilation does not validate a map stride.

### BANKED CVBasic CALLERS AND TI FCTN INPUT (2026-10-05)

On TI, keep cartridge-bank switches around `GOSUB` in fixed ROM. A routine
executing from bank 2 that selects bank 3 immediately before `GOSUB` leaves
the call's inline target word in bank 2, so the runtime can read an unrelated
word from bank 3. Hard Hat Mack's level-start HUD lost its score and reserve
lives this way. Return to fixed ROM before selecting another page, and verify
the generated assembly and opening screen rather than treating compilation as
proof of a safe bank transition.

The fork's TI keyboard scanner can report bare FCTN as key code 254 while
`cont2.button2` is set. That combination also occurs with ordinary Classic99
direction controls, so it must not be accepted as a generic REDO/BACK command.
Read the FCTN modifier and physical 8/9 matrix positions instead; Keystone
Kapers' `ti_cancel_key` shows the CRU sequence. Test directional movement and
shortcut keys in the running emulator together.
