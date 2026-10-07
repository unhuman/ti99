---
name: rom-budget
description: >-
  ROM and size budgeting for this repo's CVBasic carts (TI fixed area 24,336 B, banks,
  linkticart, NES PRG): banking data from the start, the three ROM budgets, silent truncation,
  banksize/bankfill/romcheck, romprofile/romclones duplication sweeps, short-branch
  optimisation, colour tables vs VPOKE loops, music player cost, pointing DATA labels into
  RAM, the one-menu-entry fix and per-target data gating (DESIGN.md 5B). Load before adding
  code or data when space is tight, touching BANK directives, music, or build size checks.
---

# rom-budget

Moved verbatim from the root `CLAUDE.md` (§3A and its trailing sections) on 2026-09-28 so it
loads only when needed. Section references like "§3A" mean the root `CLAUDE.md`.

- **A BOOT-ONLY BANK FREES THE DATA BANK FOR COLD CODE.** Choplifter's unoptimised fixed image
  went 232 bytes past `>FFFE` with its single data bank 122 bytes from full. Art uploaded only
  at power-on (all sprites, scenery characters and colours, ~4.5 KB) moved to a second bank,
  `assets_boot.bas` after `BANK 2`, which `boot:` selects around the `DEFINE`s and then
  restores to the permanent data bank. That left room in the data bank for the title, setup
  and results code, which the fixed area then lost. Keep any table that is redefined later (a
  crash's flame sprites) in the play-time bank as its own copy. The cart doubles to 64 KB.
  **Measure the overflow first** by assembling a scratch copy with `aorg >9000`: `BANK_0_FREE`
  then reads how far past the limit the unoptimised image is.
- **Measure the final routine before bank padding.** An xas99 profiler that
  sizes routines only between named labels loses the last routine; stopping at
  the next bank's first label can also include padding. Keystone's profiler now
  uses the final emitted word before `BANK_0_FREE`, including continuation words.
  Its local `assets/shortbranches.py` saves fixed code by replacing proven
  in-range conditional/absolute branch pairs, then reassembles and verifies
  addresses and opcodes. Keep that verification and the `TI_SHORT_BRANCHES=0`
  comparison switch; the shared compiler is unchanged. Faster code can affect
  per-pass animation even when frame-based movement remains unchanged.

Most active games (`Structris`, `HardHatMack`, `RallyX`, `Astiroids`, `Adventire`,
`mspacman-cv-xb-port`) are **CVBasic**, dual-target TI-99/4A + ColecoVision, *not* XB256.
These are hard-won failure contracts — none of them is derivable from the code, and each one
cost a debugging session:

- **DUPLICATION IS FOUND BY MEASURING, NOT BY READING -- AND THE BIGGEST CLONE IS
  USUALLY INVISIBLE.** Keystone Kapers has been rescued from the ROM cap three
  times by spotting two pieces of code doing one job, every time by reading, which
  does not scale past a few thousand lines. Two tools now do it mechanically and
  are worth copying to any game here:
  - **`romprofile.py`** attributes the fixed area to routines from the **xas99
    listing's addresses** (`build-ti.sh` already emits one with `-L`), not from
    source lines. Two traps, both silent: a label line in the listing has **no
    address column of its own**, so a label must be bound to the first emitted
    address after it; and CVBasic emits its **own internal labels** between the
    named ones, so binding every label credits each routine only the bytes up to
    its first `IF`. Get either wrong and everything is attributed to the runtime.
  - **`romclones.py`** finds repeated statement runs and ranks them by removable
    bytes. **That ranking is a reading list, not a work list** -- a short clone
    folded into a `GOSUB` costs the call, the return and the parameter staging, so
    folding one can lose.
  - **TI short-branch optimization needs a successful unoptimized assembly.**
    If fixed code starting at `>A000` grows past `>FFFF`, xas99 can reject even
    adjacent conditional branches with apparent displacements near `-0x8000`.
    The optimized fixed-area budget may still have room, but that first pass
    cannot reach the optimizer. Move suitable initialization-only routines and
    their data into a cartridge bank, or reduce the unoptimized code first.
    A fixed-area caller must select that bank before calling and restore the
    runtime data bank after returning. Keystone's random-level generator uses
    bank 2 this way; its per-screen RAM map reader stays fixed.
  - **The largest clone the sweep found was one nothing on screen could show**: a
    routine computed the radar's escalator diagonals and then called the routine
    that computes the same rows again. Both were pure functions of the same loop
    variable and the write was an OR, so the duplicate was a provable no-op --
    192 bytes that no screenshot could have found, because the affected art is
    three pixel rows tall and the emulator crops the bottom of the screen. Prove
    that class of thing by **replaying both versions against a model of the
    target memory**, over every input combination.
  - **The big routines are usually NOT where the clones are.** The three largest
    here are a fifth of the game and the detector finds almost nothing in them:
    their duplication is structural -- the same algorithm over different
    variables -- which a text matcher cannot see and a `GOSUB` cannot cheaply
    fold.

- **A CONSTANT COLOUR FILL BELONGS IN A TABLE, NOT IN A `VPOKE` LOOP -- AND THE
  TABLE OF IDENTICAL BYTES IS THE CHEAP OPTION.** Filling a font's colour table by
  hand costs 8 bytes per character per screen third (59 chars = 1,416 writes) and
  has to be paced with `WAIT`s, because a VDP burst past a few dozen writes in one
  frame is silently dropped. `DEFINE COLOR n,count,table` does the same job in one
  synchronous call with interrupts off. In Keystone Kapers that loop was 24 of the
  33 paced frames in the whole boot, and it is what made the title screen fill in
  visibly instead of appearing.
  - **The table is not the expensive part.** 472 identical bytes reads as waste,
    but ROM is three budgets (see above) and it goes in the abundant one; deleting
    the routine *returned* 80 bytes of the scarce one. Reaching for the loop to
    "save space" spends the budget that matters to save the one that does not --
    the same inversion as moving banked data into code.
  - **EXCEPT ON AN UNBANKED NES, where PRG *is* the scarce budget.** Keystone
    Kapers carried a 472-byte `nes_fcol` of one repeated value on that
    reasoning, with 37 bytes of PRG free. Its uploader now takes a small
    `#ncol` (1..255, never a real VARPTR there) as the colour byte itself. That
    and dropping TMS-only tables the NES never read freed 2,192 bytes
    (Keystone DESIGN.md section 49). **Sweep a target's assembly for
    unreferenced and mostly-unread tables before deciding it is full.**
  - **`define_color` ALWAYS does the triple copy** (`bl @LDIRVM3` in the generated
    assembly), so it cannot patch one screen third. A routine that colours a single
    third has to stay a `VPOKE` loop; check which you have before converting.

- **THE TI MUSIC PLAYER CAN READ A BANK THE PROGRAM SWITCHES AWAY FROM, AND
  `PLAY OFF` DOES NOT HAND THE CHIP BACK.** Two facts from
  `cvbasic_9900_prologue.asm`, both used by Keystone Kapers' title music
  (DESIGN.md section 46):
  - `PLAY` records the page mapped at the time (`>7FFE`). Every interrupt saves
    the current page, maps the music's page to read a row, and restores the
    saved page. So song data may live in a bank the main loop leaves, provided
    **`PLAY` runs while that bank is selected**. It does not break the "never
    switch under the ISR" rule, because the ISR does its own switching.
  - While any play MODE is set, the ISR rewrites the sound chip every frame,
    even after `PLAY OFF`, which stomps every `SOUND` effect. **`PLAY NONE`**
    clears the mode. Stop music with `PLAY OFF` then `PLAY NONE`.
  - The player is **~1,170 bytes of fixed-area runtime**. On a nearly full cart
    that overflows the *unoptimised* first xas99 pass before any branch
    shortening. Budget it against `BANK_0_FREE` in `NAME.unopt.txt`, not
    against the final free figure.

- **POINTING A `DATA` LABEL INTO RAM TAKES THREE TI ASSEMBLER RULES AT ONCE.** An
  `EQU` for the label's symbol (`cvb_NAME: EQU array_BUF+offset`) makes every
  `SCREEN`, `DEFINE`, `VARPTR` and indexed read of that label follow it into RAM,
  with no call site changed. Keystone's TI moves its play tables out of ROM this
  way (DESIGN.md section 54). Each of these rules cost a rebuild:
  1. **CVBasic writes an `ASM` line at column 1 only if its FIRST WORD ends in
     `:`**; every other line is indented, and xas99 reads an indented `cvb_X EQU`
     as the mnemonic `CVB_X`. Write `ASM cvb_X: EQU ...`.
  2. **xas99 cannot resolve an `EQU` that refers forward**, and CVBasic emits its
     RAM declarations (`array_...`) at the END of the file. Move the EQUs after
     them in the build.
  3. **But not after `ram_end:`**: a label alone on its line attaches to the NEXT
     statement, and xas99 rejects another label there ("Invalid continuation
     for label"). Insert them just before it; an EQU reserves nothing.

- **`linkticart` PUTS THE CART HEADER ON EVERY 8 KB PAGE, so one program lists FOUR TIMES in
  the TI menu -- and three of those entries are broken.** It writes the 80-byte header before
  each loader page (`hdr`, `ram[0:8112]`, `hdr`, `ram[8112:16224]`, `hdr`, `ram[16224:24336]`)
  and then pads to a power-of-two page count, which copies it again. The console scans each
  page, finds four headers, and lists the program once per page. **Only page 0 is a real entry
  point**: the other three headers were copied wholesale and point into the middle of data, so
  selecting one runs from a bogus address -- a menu line that does nothing, or hangs.
  - **A BANKED build hides it entirely** (the console only ever sees bank 0 during its
    power-up scan), which is why this does not show up on every cart here and why it can look
    like a bug in the new game rather than in the shared packer.
  - Fix: after linking, blank the `>AA` magic at the top of pages 1+. The scan requires `>AA`
    and skips a page without it; the loader walks the later pages as data at a fixed 80-byte
    offset and never looks for a signature. `games/KeystoneKapers/assets/onemenuentry.py` does
    this and is wired into that game's `build-ti.sh`.

- **BANK THE DATA FROM THE START — it is the default for TI builds in this repo, not a
  rescue.** The fixed area is **24,336 bytes** (three 8,112-byte loader pages) and
  `linkticart` silently truncates past it: no warning, and what goes missing is whatever sits
  nearest the end, usually a `DATA` block rather than code. Keystone Kapers reached 24,304 of
  24,336 and could not afford three hundred bytes of new sprite art; banking `art.bas` and
  `store.bas` gave back **4,574 bytes in one change**. Retrofitting is cheap when the INCLUDEs
  are already at the end of the file and expensive when they are not, so put the data INCLUDEs
  last and the `BANK` directive above them from the first commit.
  - The shape: `BANK ROM 128` (gated `#if TI994A`) near the top, `BANK SELECT 1` at setup
    **before anything reads from the bank**, and `BANK 1` immediately above the data INCLUDEs
    — everything after that directive assembles into the bank, so nothing but data may follow.
  - **`BANK 1` in CVBasic is PHYSICAL bank 3 on the TI.** Banks 0-2 are the RAM-resident
    program: the startup code copies them to `>A000` and jumps there. Do not try to reason
    about the physical numbers; use `BANK 1` and read the emitted `bank 3` in the `.a99` if you
    need to confirm it took.
  - **One data bank, selected once, is the safe configuration** — with nothing to switch there
    is no switch to miss, and data in a permanently-mapped bank can be read inside a frame.
    CLAUDE.md's "never read during a frame" rule is about *switching*, not about banking.
  - **Keep one readable thing OUT of the bank** (the font). A bank-selection mistake then
    shows as "text survives, art does not" rather than a uniformly blank screen.
  - **`wc -c` DOES NOT MEASURE A BANKED IMAGE.** The `>A000..>FFFF` window is padded to 24,576
    bytes with `>FF` plus a two-byte trailer at `>FFFE`, so length-minus-16384 reads 24,576 for
    every banked build whatever it contains — a phantom 240-byte overflow on a build with four
    kilobytes free. `games/KeystoneKapers/assets/banksize.py` handles both shapes; copy it.
  - **A BANK CAN OVERFLOW BY GROWING, NOT ONLY BY TRUNCATING.** A bank assembled 76 bytes
    past 8,192 came out of xas99 as a **73,728-byte** `_b3.bin`, and linkticart packed it as
    nine pages into a 96 KB cart, with everything past `>7FFF` outside the bank window. A
    "last block is present" check passes that. Fail on the bank image's SIZE as well
    (`games/KeystoneKapers/assets/bankfill.py` does both).
  - **LZSS INTO RAM HALVES A CART.** Tables compressed at build time and unpacked into one
    RAM buffer at power-on took Keystone Kapers from two banks (64 KB) to one (32 KB). Point
    each table's symbol into the buffer with `ASM cvb_X: EQU array_BUF+off`, so no reader
    changes. Keystone Kapers DESIGN.md sections 53-57 have the format, the decoder and the
    assembler traps.
  - **`BANK ROM` accepts only 128, 256, 512 or 1024.** `BANK ROM 32` is rejected outright
    ("BANK ROM not 128, 256, 512 or 1024"), and a `BANK` statement without it fails with
    "Using BANK without BANK ROM" pointing at the `BANK`, not at the missing declaration. The number
    sizes **ColecoVision's Megacart mapper** and is *not* the TI cart size — that comes from how many
    bank files the assembler emits, so `BANK ROM 128` with one bank still packs a 32 KB TI cart.
  - **Bank only what is never read during a frame, and gate it per target.** A `#if TI994A` around
    `BANK ROM` / `BANK n` / `BANK SELECT n` keeps a dual-target game unbanked on Coleco (whose Z80
    build is typically half the size of the same source on the 9900, so it rarely needs banking and
    would only become a Megacart image). **Everything after a `BANK n` directive is assembled into
    that bank**, so the INCLUDE order is load-bearing: putting the bank directive before the music
    tables would sweep them into a bank the vblank ISR cannot safely read.
  - **Selecting the bank once at startup beats switching per read** when only one bank exists. A
    missed `BANK SELECT` returns bytes from the wrong page with no error at build or run time.

- **WHEN THE FIXED AREA IS FULL, LOOK AT THE CODE YOU WROTE LAST WEEK -- IT IS
  WHERE THE SLACK IS.** Keystone Kapers went from **6 bytes free to 122** with
  two changes, both to code written in the same session that had filled it.
  New code has not been squeezed yet; the routines that have survived three
  budget crises already have not got anything left in them.
  - **A LADDER OF COMPARISONS IS USUALLY BIGGER THAN THE ARITHMETIC IT AVOIDS,
    AND THE `/`-IS-SLOW RULE DOES NOT APPLY OUTSIDE PER-FRAME CODE.** Stepping
    a digit printer's divisor down a decimal place was four
    `IF #psd = 10000 THEN #psd = 1000 : GOTO ...` lines -- four compares, four
    assignments and four jumps -- where `#psd = #psd / 10` is one instruction
    and **84 bytes smaller**. §3A's "hand-convert every `/` and `%`" is about
    SPEED in the main loop; a routine that runs when the score changes and once
    a second for the clock is the other side of that trade. **Say so in the
    source**, or the next reader dutifully converts it back.
  - **AN ODD ONE OUT IN A TABLE COSTS A BRANCH AT EVERY SITE THAT USES THE
    TABLE.** A sprite parked at the end of the pattern table "so nothing
    renumbers" had a facing offset of `+4` where every other sprite of that
    actor used `+36`, which meant the one place that applies a facing carried
    `IF kf = P_ODD THEN kf = kf + 4 ELSE kf = kf + P_FACING`. Moving it into a
    hole INSIDE the actor's own block -- exactly the facing offset apart --
    deleted the branch, a whole `DEFINE SPRITE` and its upload, and renumbered
    nothing, because a hole is not an insertion. **When a block frees slots,
    check whether an exception can move home.**

- **ROM IS THREE SEPARATE BUDGETS, and "shrink the ROM" usually optimises the wrong one.**
  (1) The **fixed area** — all code plus any data read during a frame — is the 24,336-byte cap
  above, and it is the only scarce one. (2) **Banks** are 8 KB each and typically half empty.
  (3) **Cart size** = 3 loader pages + one page per bank, *rounded up to a power of two*.
  Consequences, all three measured in RallyX (`games/RallyX/assets/romcheck.py`, run it on any
  banked game):
  - Moving repeated data out of a bank and into code **makes things worse** — it spends the
    scarce budget to save the abundant one. Doing exactly that (3.6 KB of repeated colour bytes
    → ~400 B of fill loops) overflowed the fixed area by 229 B and **silently cut the last seven
    bars off the music**: total ROM went *down* while the build broke.
  - **The overflow is invisible.** Nothing in `cvbasic` → `xas99` → `linkticart` warns; the
    excess is dropped and the symptom is missing *data* (whatever sits nearest `>FFFF`, usually
    the last `DATA` block), not a build error. A banked build skipped `build-ti.sh`'s size guard
    entirely. Audit the packed cart and verify at-risk blocks round-trip byte-for-byte.
  - **A thinly-used bank can double the cart.** A 1.1 KB title logo alone in bank 6 made 9 pages
    → 128 KB; folding it into a bank with room gave 8 pages → **64 KB, content unchanged**.
  - **Delete `NAME_b*.bin` before assembling** — linkticart appends every bank file it finds, so
    a stale one from a previous build is packed into the cart and inflates the page count.

- **A scrolling playfield's char map cannot be compressed** on this hardware. The TMS9918 has no
  scroll register, so a 1-char pan rewrites the whole 24×24 name table; only CVBasic's built-in
  `SCREEN` blit is fast enough, and it copies **literal char codes from CPU memory**. Any packed
  or per-cell encoding must be expanded 576 chars at a time in CVBasic (orders of magnitude
  slower), and decompressing a maze at round start needs contiguous RAM neither target has
  (TI ~7.2 KB free, Coleco ~230 B). Budget for it up front: it is the price of scrolling.

## 5B. Size budget from line 1 (CVBasic, every target)

Keystone Kapers got music on all three machines only by clawing bytes back
afterwards (its DESIGN.md sections 46-51). Each of those savings would have been
free if the game had been written this way from the start. **Plan the budget
first**, like the performance budget in §5A.

**Budget music up front.** CVBasic's music player costs about **1.2 KB of
fixed-area code on the TI** and **about 1 KB of PRG on the NES**, plus its RAM
(about 33 bytes on the NES and ColecoVision). A tune is **4 bytes per row**
(1 tick byte + 4/row + 1): a 16-bar tune at eight rows a bar is about 518 B. If a
game might ever have music, reserve that space in DESIGN.md before the fixed area
fills, not after.

**Per-target data is easy to leave in the wrong build.** A table only one target
reads still costs every target its bytes unless the INCLUDE or the emitter is
gated. Keystone's NES carried 1.4 KB of TMS store art, a 384-byte TMS radar colour
table and unreferenced tables while its PRG had 37 bytes free. From the first
commit:
* Gate each generated table by the target that reads it (`#if NES` / `#else` in
  the generator's output, or around the INCLUDE).
* When a target reads a few entries of a big shared table, emit a slice for it
  (sliced from the generator's constants, never typed offsets).
* **Sweep a target's assembly for unreferenced labels and partly-read tables**
  before calling it full. Match `#label` too: 6502 immediate operands prefix it.

**A table of one repeated value is the cheap option only where ROM is
plentiful.** On an unbanked NES it is 8 bytes per character for nothing: pass
the constant through the uploader instead (Keystone's `nes_chrinkrow` treats a
`#ncol` of 1..255 as the colour byte itself).

**6502 (NES) code is verbose, so write the small forms.**
* `IF x > 0 THEN GOTO lbl` is about 12 bytes (load, compare, long branch, jump).
  A run of them testing "is any of these non-zero" is **one `IF a OR b OR c ...
  THEN`** over unsigned bytes: a bitwise OR of values, about 3 bytes per term.
  This is not the TI's `<cmp> AND <cmp>` hazard: it ORs values, not comparisons.
* When two routines end with the same statements on a target, the second can
  `GOTO` the first's tail. Gate it if the other targets differ.
* Keep a clone sweep handy: repeated instruction runs, with compiler labels
  normalised, ranked by removable bytes. Most large clones are the compiler's
  array-index code, which only a source change can fold.

**NES RAM: scalars land in front of the arrays.** CVBasic allocates new scalar
variables just before the array block, so *three bytes of new scalars* can push
the last array past `$07FF` into the mirrored zero page. Run
`checknesram.py`-style checks before adding a variable. Prefer:
* reusing a documented, provably idle scratch byte,
* folding flags into one state byte (Keystone's NES music state is `nai`: 0
  playing, 1 ducked, 2 not started),
* branching instead of holding a flag,
* sizing arrays to the largest index actually read.

**When PRG is the limit, a small routine is cheaper in hand-written 6502.**
Keystone's `box_hide` compiled to ~226 bytes on the NES; the same rule written
by hand (`nes_boxhide`) is under half that. Keep the BASIC version for the TMS
targets and test the asm's constants against the same geometry (its DESIGN.md
section 58).

**Before saving state at run time to restore it later, check whether the
generator makes it constant.** Keystone's NES kept a 4-byte array of attribute
halves to restore around `GAME OVER`. Every one of those halves was P0 on every
screen, so a constant replaced the array, its fill loop and its RAM, and a test
now pins that they stay P0 (section 59).

**Keep a per-target byte budget table in DESIGN.md** (fixed/PRG free, RAM
free) and update it with every feature, the way §5A's performance budget is kept.
