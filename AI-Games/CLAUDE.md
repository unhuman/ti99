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

## 1. Toolchain & Target

- **Hardware model:** TI-99/4A console + **32K Memory Expansion (required)** + disk system.
  Extended BASIC cartridge. Use **XB 2.9 G.E.M.** *only* when making cartridges or when using
  `CALL PEEKV/POKEV/MOVE/STCR/LDCR`; otherwise plain TI Extended BASIC.
- **Dev environment:** **Classic99**, with the `JUWEL7` folder mounted as **DSK1**
  (Options → enable "Write DV80 as Windows Text"; leave "Write DF80…" off). Use **CPU overdrive**
  while compiling/assembling.
- **Default distribution target:** **XB loader (`-X`)** — the compiled program embedded in an XB
  loader, runnable/chainable from an XB menu. (Alternatives: `-E` EA5 for a standalone program;
  `.BIN` cartridge via `MAKECART8`/`MAKECARTG`, which needs XB 2.9 G.E.M. + Classic99
  QI399.055+.)
- **TI filename rule (important):** a TI disk filename **cannot contain a period** — `.` is the
  device separator (`DSK2.NAME`). So name compiler/assembler outputs with **hyphen suffixes, no
  dots** (`NAME-S`, `NAME-O`). A dotted name like `DSK2.MUNCH.TXT` is illegal and fails the OPEN
  with `I/O ERROR` (code 130, type 7). The `.TXT`/`.OBJ` forms shown in some Wilhelm docs are
  **only** valid on the Asm994a (Windows-text) path; on the bundled **TI assembler** path use
  dot-free names.
- **The 6-file pipeline** (mostly "press Enter"):

  | File | Meaning |
  |------|---------|
  | `NAME`     | XB/XB256 source program |
  | `NAME-M`   | same program saved in **MERGE** format (compiler input) |
  | `NAME-S`   | assembly **source** produced by the compiler (`-TXT` also fine; never `.TXT`) |
  | `NAME-O`   | assembled **object** code (`.OBJ` only on the Asm994a path) |
  | `NAME-E`   | compiled program, **EA5** format |
  | **`NAME-X`** | compiled program in an **XB loader** ← our default output |

  Flow: develop & test in XB256 → `SAVE` → `SAVE …-M,MERGE` → **Compiler** (output `NAME-S`) →
  **Assembler** (TI assembler → `NAME-O`, or Asm994a) → **Loader** (save `-X` / `-E`, or `RUN`).

---

## 2. Hard Compiler Constraints (integer-only) — drive all game math

- **Integers only, −32768…32767.** Overflow wraps: `200*200 = -25536`, `32767+1 = -32768`.
  Use **fixed-point** (e.g. store position×256, shift when reading) where you need fractions.
- **Division truncates.** Wrap **`INT()`** around any `/` or `SQR` in the XB source so the
  interpreted and compiled results match (e.g. `INT(5/2)` = 2 in both).
- **`RND` compiles to 0.** Always `INT(RND*N)` for a 0…N-1 result. Prefer
  `CALL LINK("IRND",limit,var)` (XB256) — same result *and* much faster. `RANDOMIZE` is a
  no-op (auto-seeded); for a repeatable sequence `CALL LOAD(-31808,n1,n2)`.
- **Delay loops do NOT translate** (`FOR I=1 TO 500::NEXT` ≈ seconds in XB, a blink compiled):
  - Timed delay: `CALL SOUND(ms,110,30)::CALL SOUND(1,110,30)` (the 2nd call blocks until the
    1st finishes), **or** `CALL LINK("DELAY",ms)` (1–30000 ms; sprites/sound keep running).
  - Fixed-period loop: `CALL LOAD(-1,N)` once, then `CALL LINK("SYNC")` just before the loop's
    `NEXT`/`GOTO` → each pass takes exactly N/60 s.
- **Not supported (will break / be dropped):** `SIN COS TAN ATN LOG EXP`, `DEF`, `IMAGE` &
  `DISPLAY USING`, `CALL ERR`. Trig workaround = precomputed **SINE255** string + `SEG$`/`ASC`
  (see `JUWEL7/SINE255` and XB Compiler.pdf p.7); `COS(a)=SIN(90-a)`.
- **Syntax landmines:**
  - **Never a trailing `::`** at the end of a line — it crashes the compiler.
  - User `SUB` names are truncated to the **first 6 letters** and must stay unique
    (`UPDATEWHITE`/`UPDATEBLACK` collide; `UPDATWHITE`/`UPDATBLACK` are fine).
  - **`RESTORE` must point to a `DATA` line, never a `REM`/`!`**. You cannot `GOTO` a `DATA` line.
  - `CALL LINK` name must be a **string constant** — `CALL LINK(A$,…)` will not compile right.
  - Keep `PRINT` lists to **≤20 items**. No `ON GOTO`/`ON GOSUB` **inside** an `IF/THEN/ELSE`.
  - `DISPLAY ERASE ALL` (with no print list) crashes the compiler — use `CALL CLEAR`.
  - **`SEG$` needs all *three* args** `SEG$(s,start,len)`. A 2-arg `SEG$(s,start)` ("to end") is
    invalid XB — interpreted it errors, but the **compiler silently miscompiles it to garbage**
    (corrupt string write → freeze/crash, a stray inverse char on screen), with no error at compile
    or run time. For "rest of string," pass an explicit length (e.g. `SEG$(s,start,LEN(s)-start+1)`
    or a constant ≥ the max remaining). Confirmed in `games/mspacman` cache update (line 753).
  - **Jump-codegen corruption near program end** (confirmed by decoding the generated assembly):
    close to the label-table limit, the compiler can *silently* mistranslate conditional jumps in
    the **last** code region. Two confirmed modes: (1) a **bare single small-constant comparison**
    jumping to a line — `IF K<1 THEN 1234`, `IF K>0 THEN 1231` — came out comparing the *wrong
    variable* / a garbage target; the **compound `OR`** form right beside it compiled fine
    (`IF K<48 OR K>57 THEN …`), so prefer compound conditions. (2) a **short backward `GOTO`/`ELSE`
    to a line that immediately follows *another* jump target** resolved to a garbage label
    (→ `undefined symbol`, or a silent jump into unrelated code). Fixes: no standalone short backward
    `GOTO` (fold the loop-back into an `ELSE`); **put a buffer line so a loop-back target never sits
    right after a jump target**; and shed labels by merging contiguous plain `::` lines (each source
    line ≈ one label) to pull back from the table limit.
- **Reserved names:** the compiler reserves ~1000 internal labels — `NC/NV/NA/SC/SV/SA…`,
  `L`+digit, and the full table on **XB Compiler.pdf p.12**. Game `SUB`/`CALL LINK` names must
  avoid these (and their 6-char truncations).
- **Supported and behaving like XB:** full `IF/THEN/ELSE` (incl. statement clauses),
  `FOR/NEXT/STEP`, `GOSUB/RETURN`, `ON GOTO/GOSUB`, arrays incl. **nested** `A(B(i))`,
  multi-assignment (`A,B,C=3`), string ops (`SEG$ POS LEN VAL STR$ CHR$ ASC RPT$ &`, 255-byte
  cap), `ACCEPT`/`DISPLAY AT`/`PRINT`, and the graphics/sound CALLs in §4. Up to three
  `DISPLAY,VARIABLE` files (`#1 #2 #3`) — `LINPUT`/`INPUT` for read, `ON ERROR line#` supported.

---

## 3. XB256 / TI Extended BASIC reference → **skill `xb256-reference`**

The TI Extended BASIC language rules (`::` separators, `IF/THEN/ELSE` semantics, subprogram
argument passing) and the full **XB256 `CALL LINK` capability map** (Screen2 vs sprite pattern
tables, the TMS9918A two-colours-per-cell model, `MAGNIFY` sizes, 1-based coordinates,
scrolling, sound) now live in `.claude/skills/xb256-reference/SKILL.md`.

**Invoke that skill when working on an XB256 game** (`games/dotmuncher`, `games/mspacman`).
It is deliberately *not* always-loaded: most games here are CVBasic (§3A), so keeping ~1.6k
tokens of XB256 API reference resident in every session was dead weight. Everything binding —
the mandates, the compiler landmines (§2), the performance budget (§5A), the checklist (§6)
and the per-game lifecycle (§8) — stayed in this file.

---

## 3A. CVBasic hazards (the current platform — always loaded)

Most active games (`Structris`, `HardHatMack`, `RallyX`, `Astiroids`, `Adventire`,
`mspacman-cv-xb-port`) are **CVBasic**, dual-target TI-99/4A + ColecoVision, *not* XB256.
These are hard-won failure contracts — none of them is derivable from the code, and each one
cost a debugging session:

- **Never `MODE 2`.** It compiles clean and renders broken on both targets. Use the default
  startup mode with `DEFINE CHAR`/`DEFINE COLOR`.
- **Never `<cmp> AND <cmp>` / `<cmp> OR <cmp>` on TI** — the 0.9.2 TMS9900 backend ANDs against
  a stale register. Nest single-comparison `IF`s.
- **CVBasic has NO local variables.** Every variable is global, so a scratch temp that reuses a
  state variable's name silently corrupts it — a camera temp named `#hi` clobbered the HIGH
  SCORE every frame. Prefix temps per routine and grep the name before adding one.
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
- **A per-pass counter is not a clock.** Anything timed — a beep interval, a countdown, a
  telegraph — must decrement by the frame delta, not once per loop pass, or it slows down exactly
  when the loop gets busy. That is the same root cause as movement slowing (§3A's FRAME-delta
  item), and it is worst for warning cues, which become least reliable precisely when the frame is
  most loaded. Corollary: once a timer decrements by a *variable* delta, any logic keyed on its
  **parity** (`t AND 1`) breaks — an even delta freezes the parity. Drive alternating states from
  their own phase counter.
- **THE TI's ALPHA LOCK KEY SHARES A LINE WITH THE JOYSTICK'S VERTICAL AXIS.** With it
  latched down the console reports an up/down direction that is **never released**, so
  any menu built on `cont1.up`/`cont1.down` boots pinned to one entry and cannot be
  moved off it -- a per-pass `IF cont1.down THEN k = 2` is recomputed every pass, so the
  stuck axis wins every pass and no other key can ever get an edge in. No error, and it
  looks like a broken menu rather than an input problem. `cont1.left`/`cont1.right` are
  unaffected and are what every game here already uses for aiming/steering, which is why
  this stays hidden until something reads the vertical axis for the first time.
  **For a menu, prefer `cont1.key` (0-9 on both targets, 15 for nothing) and PRINT the
  key beside each entry** -- it dodges the hazard, states its own controls, and costs
  less code than a cursor (in Bust-A-Bobble it freed 248 bytes). Swapping a vertical
  menu to left/right instead is a trap of its own: it works, and players still press up
  and down.
- **`#var` comparisons are unsigned** — signed logic (`< 0`, wraps) needs a split at 32768.
- **`%` compiles to a real DIV**, even by a power of two — hand-convert (`% 8` → `AND 7`).
- **`DIM a(N)` is 0..N-1.** A one-past-end write is silent on TI and black-screens ColecoVision.
- **VDP writes are buffered per frame**; bursts beyond a few dozen are silently dropped. Pace
  with `WAIT`. `VPOKE` operands must be precomputed into plain vars (ISR race), and TI
  `DEFINE CHAR`/`COLOR` are synchronous (safe in bulk).
- **Sprite y = 208 terminates the sprite list** — hide sprites at 209, and watch for `y-1`.
- Misc: 8-bit `FOR` to 255 loops forever; `ON GOTO` is 0-based; `DEF FN` args substitute
  textually (parenthesize every use); a computed `FOR 1 TO 0` still runs the body once.
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
- **TI cart limit: 24,336 bytes** in the fixed area — `linkticart` silently truncates past it.
  Beyond that use `BANK ROM`/`BANK SELECT` (data in banks, `BANK SELECT` only from bank 0).
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
- **Build BOTH targets every time**, not just TI. `#if TI994A` needs the **unhuman/CVBasic**
  fork (stock nanochess has no preprocessor).
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
- **A grid-cell occupancy check does NOT prove sprites do not overlap.** A 16-px actor on a 16-px
  grid straddles two cells for its entire traverse, so "no two actors share a cell" can read a
  clean 0 while they are visibly stacked. Worse, a cell cache derived from raw pixels every frame
  is **asymmetric**: moving up or left, `pixel / 16` flips to the next cell after ONE pixel, so
  the actor releases the cell its body still fills. Hold the cached cell as an **anchor** updated
  only on arrival (both low nibbles zero) and let the actor reserve origin + destination while in
  transit. Assert on the thing you can see — `|dx| < size AND |dy| < size` — not on the index you
  happen to store. RallyX chased this through several "verified fixed" rounds because the probe
  measured cells.
- **A difficulty dial must never invert the goal.** Weakening an enemy by making it flee reads as
  broken AI, not as an easier game. Degrade the *quality* of the pursuit instead (chase on the
  worse axis, react later, move slower); the actor should always be visibly trying.
- **FRAME-delta pacing is a positive feedback loop — keep per-pass work O(events), not
  O(`#fd`).** With `#fd = FRAME - #lf`, any "repeat the step `#fd` times" loop (per-pixel
  movement, per-pixel AI polling) makes a slow pass slower still: cost rises with `#fd`, which
  raises `#fd` again. RallyX sat pinned at its `#fd` clamp of 4 and ran at **8 loop passes/sec**
  until everything that moves was rewritten to advance to the next *cell boundary* in one step
  (→ **60/s, one pass per vblank**). Symptom is "sluggish sometimes" with `FRAME` still ticking a
  clean 60 Hz — i.e. no vblanks lost, the loop is just too fat. **Profile before optimising:** the
  obvious suspect there (the 576-byte `SCREEN` pan blit) was never called during the slow runs,
  and the enemy AI ran 0.56×/pass. Measure loop passes/sec against a host clock —
  see `games/RallyX/DESIGN.md` §1a.
- **The `#fd` clamp DISCARDS real time — game speed then depends on frame rate.** Clamping the
  delta bounds catch-up work, but the world advances only `clamp` frames per pass while real time
  advances more, so everything runs slow *exactly when the loop is busy* and full speed when it
  is idle. In RallyX this read as "the enemy cars move faster when the screen isn't scrolling."
  Once movement is O(cells crossed) a big delta is cheap **and** safe (each step still tests walls
  at every boundary, so nothing tunnels), so set the clamp far above normal play. Same trap for
  any timer counted in *passes* rather than frames — scale every countdown by `#fd`.
- **`WAIT` quantises the loop to whole frames**: achievable rates are 60, 30, 20 … A body that
  overruns one frame by a hair costs a whole extra frame, so the last millisecond is worth more
  than it looks — and an average like "2.2 frames per pass" means visible jitter between 2 and 3.

---

## 5. Memory Budget

- **Program space:** **24488 bytes** (drops to **17558** if XB256 is *packaged/merged* into the
  XB program rather than autoloaded).
- **Stack (VDP), reduced by XB256:** ≈ **9092** bytes at `CALL FILES(1)`, **8574** at `(2)`,
  **8056** at `(3)` — and less if you reserve a sound buffer with `CALL LINK("XB256",n)`.
- **Stack-saving conventions (adopt by default):**
  - Prefer **string constants** over string variables (`DISPLAY AT(1,1):"TEXT"` beats `A$="TEXT"`).
  - **Reuse one `A$`** when building/loading many strings; keep numeric var names short.
  - Keep bulk data in `DATA` and `READ` on demand instead of into string arrays.
  - Minimize **named subprograms** in hot paths; convert to `GOSUB`/`ON GOSUB` where possible.
- VDP memory map (for `VREAD/VWRITE/CWRITE`): screen image 0–767; sprite attr 768–879; sound
  buffer 2432–3071; Screen2 patterns 4096–6143; value stack 6176+. (Full map in XB256.pdf p.11.)

---

## 5A. Runtime Performance Budget — design for speed from line 1

The compiler makes the program *correct*, not *fast*. On **original hardware** an XB256 design that
ignores per-frame cost can be **unplayably slow even compiled** (lesson learned the hard way:
`games/mspacman` is correct and compiler-safe but crawls on a real TI-99). Speed is an architecture
decision made in `DESIGN.md`, not something to optimize later. **Mental cost model:**

> per-frame cost ≈ (moving actors) × (per-actor work) + (per-frame VDP round-trips)

`games/mspacman` maxes out every term — and is the cautionary reference for what *not* to do:
it repositions all 5 actors by CPU every frame (`CALL LOCATE`), runs a 4-direction pathfind for
**each** of 4 ghosts **every frame**, and does many per-frame `CALL GCHAR` wall reads.

**Levers, fastest first:**
- **Turn-based / input-paced loops are essentially free** — the CPU mostly waits on `CALL KEY`.
  Puzzle/board games (Tetris, Snake, Minesweeper, 2048, Reversi) have effectively unlimited speed.
- **Prefer hardware `CALL MOTION` over per-frame `CALL LOCATE`.** A sprite given a constant velocity
  is moved (and **edge-wrapped**) by the VDP for *free*; you only re-issue `MOTION` on a discrete
  event (thrust, bounce, fire). `LOCATE`-every-frame is pure CPU and is the #1 thing that made
  Ms. Pac-Man slow. (Ms. Pac-Man needed deterministic grid movement, so it couldn't — but most
  games *can*.)
- **Minimize per-frame VDP round-trips.** `CALL GCHAR`/`COINC`/`POSITION` each cost a VDP access;
  doing them per-actor per-frame is brutal. Cache, check every other frame, or design them out.
  **Concrete win (applied in `games/mspacman`):** mirror a static/slow-changing screen in a
  **string array, one char per cell, indexed so char position = screen column** (`M$(R)`), then
  replace `CALL GCHAR(R,C,G)` with `G=ASC(SEG$(M$(R),C,1))` — a CPU/value-space read, no VDP
  access. Build it while rendering; patch the one cell you change (e.g. an eaten dot) in the same
  line. Costs ~1 byte/cell (a numeric array costs 8×), so a full 24×32 field is ~800 bytes vs ~6600.
- **Avoid per-actor per-frame AI search for many actors.** N pursuers each pathfinding every frame
  is the Ms. Pac-Man trap. Prefer scripted/constant-velocity motion or reactive (non-search) AI.
- **Cap simultaneously-moving sprites** and redraw **only cells that changed** (don't repaint the
  field). `FLICK` handles >4 on a scanline but doesn't make the per-frame work cheaper.

**Mandate:** every `DESIGN.md` opens with a **Performance Budget** block stating: max
simultaneously-moving sprites; `MOTION`-vs-`LOCATE` choice per entity type; a ceiling on per-frame
`GCHAR`/`COINC` calls; and whether the loop is real-time or input-paced. Decide these *before* line 1.
If a concept implies "many actors each thinking every frame," expect Ms. Pac-Man-class slowness and
redesign or pick a different game.

---

## 6. Compiler-Safe Coding Checklist

Every game's XB source must satisfy all of these so XB and compiled behavior match:

- [ ] Integer / fixed-point math only; explicit `INT()` on every `/` and `SQR`.
- [ ] Randomness via `INT(RND*N)` or `CALL LINK("IRND",…)`.
- [ ] Timing via `CALL LINK("DELAY",ms)` / paired `CALL SOUND` / `SYNC` — never raw `FOR/NEXT`.
- [ ] No trailing `::` on any line.
- [ ] `SUB`/`CALL LINK` names: unique in first 6 chars, not in the reserved list, `LINK` name a
      string constant.
- [ ] `RESTORE` targets a `DATA` line; no `GOTO` into `DATA`.
- [ ] No `SIN/COS/TAN/ATN/LOG/EXP/DEF/IMAGE/DISPLAY USING`; `CALL CLEAR` (not `DISPLAY ERASE ALL`).
- [ ] `PRINT` ≤20 items; no `ON GOTO/GOSUB` inside `IF/THEN/ELSE`.
- [ ] Default Screen2; output as `-X`.
- [ ] **Performance budget honored (§5A):** `DESIGN.md` has a Performance Budget block; constant-velocity
      actors use `CALL MOTION` (not per-frame `LOCATE`); per-frame `GCHAR`/`COINC` minimized; no
      many-actor per-frame AI search.
- [ ] **Tested on / reasoned about original-hardware speed**, not just emulator default speed.
- [ ] Fully debugged in interpreted XB256 **before** compiling.

---

## 7. Reference Assets (in repo)

- `JUWEL7/` demos to mine for patterns: `256DEMO`, `256DEMO2`, `APERTURE` (Adamantyr,
  compiler-compatible), `8QUEENS`, `HELLO`.
- `JUWEL7/SINE255` — trig workaround string. `JUWEL7/SOUNDLIB.txt`,
  `JUWEL7/TMLSOUNDPLAYER/`. `JUWEL7/FLICKERROUTINE/` — handles >4 sprites on one scan line
  (`CALL LINK("FLICK"/"FLICKX")`).
- `JUWEL7/DOCS/` — authoritative PDFs (XB256, XB Compiler, Using XBGDP, TI XB manual).
- Existing project material: `mspacman-old/`, `Adventure-Java/` (candidate first games).

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
  - A setup/options screen that asks for "number of cars" still means TOTAL cars (3 cars = 3
    plays). Only the in-game HUD counts reserves.

## 8. Per-Game Structure & Lifecycle

Every game is built the same way — that consistency is the point.

**Folder layout** (`games/<name>/`):

```
games/<name>/
  DESIGN.md          # the spec — write BEFORE code (from templates/GAME-DESIGN-template.md)
  README.md          # one screen: concept, controls, status, build line
  src/<NAME>.ti99    # canonical paste-ready XB256 source (numbered listing)
  assets/            # COMPRESS DATA strings, char defs, sound lists (as created)
  build/             # -M .TXT .OBJ -E -X artifacts (git-ignored)
```

**Naming:** on-disk program name UPPERCASE and **≤8 chars** (TI filenames max 10; leaves room
for the `-M`/`-X` suffixes); folder name lowercase. Index every game in `GAMES.md`.

**Lifecycle — do these in order:**
1. Fill `DESIGN.md` from `templates/GAME-DESIGN-template.md`.
2. Author `src/<NAME>.ti99`, compiler-safe from line 1 (§6). Start from `templates/skeleton.ti99`.
3. Run **interpreted** in XB256 (Classic99, `JUWEL7` = DSK1); debug fully.
4. `SAVE DSKn.<NAME>` then `SAVE DSKn.<NAME>-M,MERGE`.
5. Compiler → Assembler → Loader; save **`<NAME>-X`**.
6. Run `<NAME>-X`; confirm it matches the interpreted behavior + the DESIGN acceptance criteria.
7. Commit `DESIGN.md`, `README.md`, and `src/`.

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
