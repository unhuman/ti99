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
- **TWO THINGS THAT MUST MOVE TOGETHER MUST SHARE ONE CLOCK -- AND IF ONE OF THEM IS A
  CYCLIC ANIMATION, THAT CLOCK CANNOT BE THE FRAME DELTA.** Movement is normally paced by
  `fdv` and animation by the loop pass; while the loop keeps up those agree, so the pairing
  looks right in the source and on screen. Both failure modes are silent and both shipped:
  - **Paced apart, the actor drifts.** A rider on an escalator advanced `2*fdv` px along
    the steps while the steps advanced 2 per pass, so his feet started planted on a tread
    and ended floating several pixels above it. It *compounds*, so it does not read as a
    one-frame glitch. And the screens where the two must agree are usually the busiest
    (that animation rewrote 120 bytes of pattern table per pass), so the delta is largest
    exactly where the mismatch shows.
  - **Paced together by `fdv`, the animation ALIASES.** A 4-phase cycle over an 8 px period
    stepped by 2 flips between two positions half a period apart (direction unreadable);
    stepped by 3 it runs 0,3,2,1 -- the **wagon-wheel effect**, and the escalator visibly
    carried its steps *downward* while the rider went up. **A cyclic animation can only be
    stepped by one, whatever the frame rate.**
  So: make the animation the clock and pace the actor *from it* -- both by a fixed step per
  pass. The ride then takes N passes rather than N frames and slows when the loop does,
  which is the honest behaviour for a machine that is carrying you. **A checker for this
  must simulate `fdv > 1`** (the code is correct at 1, which is what a desk check and a fast
  emulator both exercise) **and must read both clocks out of the source and compare them** --
  `games/KeystoneKapers/assets/checkride.py` does, and names all three failures.
- **A MIRROR IS ONLY WORTH TWO DRAWINGS IF THE DRAWING IS ASYMMETRIC, AND AN
  "EVERY OTHER FRAME" ANIMATION CYCLE IS USUALLY TWO POSES.** Both halves cost a
  session in Keystone Kapers and both present identically -- as an actor whose
  legs go back and forth between two positions -- while every existing check
  passes, because the numbers are all consistent: the right patterns are loaded
  at the right addresses and drawn on the right beats. They are just the same
  picture twice.
  - **The mirror half.** "Four poses cost two drawings: left-foot-forward is the
    mirror of right-foot-forward" is sound, and Kelly's legs were drawn as two
    parallel vertical columns -- apart in one pose, together in the other. A pair
    of vertical legs mirrors to itself. His four beats differed by **4 px and
    8 px**, and 4 of those 4 were the hip row sliding two columns sideways
    because it had been given the tunic's hem shape, which is not its own mirror.
  - **The every-other-frame half.** In an 8-frame run cycle **frame n+4 is the
    same pose with the legs swapped**, and a side-view silhouette cannot tell
    those apart. So frames 1, 3, 5, 8 -- which alternate the leading leg
    correctly -- play as A, B, A, B. Order them so the unavoidable near-duplicates
    sit *opposite* each other in the cycle, not adjacent.
  - **RANK ON THE CLOSEST PAIR ANYWHERE IN THE CYCLE, NOT THE CONSECUTIVE STEP.**
    The consecutive step is the reassuring number and it is the wrong one: the
    bad set scored 49 px between adjacent beats and 7 px between beats 1 and 3.
  - **A striped actor is split across complementary sprites, so measure the whole
    figure.** Harry's white leg layer holds 10 px of 33; two of his four beats
    were **byte-identical** in it while the black stripes-and-shoes layer they are
    drawn with differed by 34. Measuring one half alone calls the same art a
    two-frame cycle or a four-frame one depending which half it is handed.
  - **`games/KeystoneKapers/assets/checkanim.py` gates it** -- it reads each
    band's beats out of the `.bas` itself (base assignment plus the following
    `IF <clock> AND <bit> THEN v = v + n` lines, never a table of its own),
    resolves them through the art generator's sprite table, adds the derived
    bands back in, and fails on any two beats within 10 px. It also fails when
    two bands of one figure run on different clock bits -- four leg poses against
    two torso poses is two clocks in one body, which reads as flapping. It was
    run against the defective art before being trusted, and failed on it.
  - **A MEASURED DEFECT THAT IS DELIBERATELY KEPT NEEDS A NAMED EXEMPTION, NOT A
    LOWERED THRESHOLD.** The Kop's two-frame cycle was redrawn twice and the
    redraw rejected both times -- the reviewer wanted yesterday's animation back.
    Relaxing MINDIFF until he passed would have blinded the check for every OTHER
    band at the same moment, which is how a gate quietly stops being one. The
    exemption lists the band by name with its reason, still MEASURES it, and
    still prints its 4 px on every build; only the failure is suppressed, so the
    number moves in plain sight if the art ever gets worse.
  - **AND THE FIX FOR A SYMMETRIC MIRROR EXPOSES THE MIRROR ITSELF.** Redrawing
    the Kop's two poses with real strides ended the repeated beats and
    immediately produced a new complaint -- *"sometimes the body is facing the
    wrong direction"*. A mirrored stride puts the OTHER foot forward on a body
    still facing the same way, which reads as the figure **turning round**; it
    was invisible only because the old legs were two near-vertical columns. So
    the mirror trick and the asymmetry requirement are in direct tension: a
    drawing asymmetric enough to be worth two beats is asymmetric enough that
    its mirror is a different ACTOR, not a different beat. Drop the mirrored
    beats and run the two drawings you have.
  - **A DUCK-OR-JUMP GAME PINS THE CROUCH HEIGHT TO THE PIXEL, AND "GIVE IT
    MORE HEADROOM" MAY HAVE NO ANSWER.** Duckable means the hazard clears the
    crouch; jumpable means it clears under the apex. Raising the crouch raises
    the duckable floor until it meets the apex coming down, and then a band of
    hazard heights is NEITHER. Keystone Kapers swept its crouch from 11 to 20
    and the dead band opened at **12** -- the very first pixel. So the answer to
    a request for a taller crouch is a measurement, not a redraw: the ceiling is
    usually much closer than the sprite box, which had five spare rows and was
    never the constraint. **Sweep it before drawing to it**, and if the pose
    needs the height, the hazard hitboxes or the arc move first.
  - **AND AN UPRIGHT HEAD IS THE EASIEST WAY TO DRAW A POSE THAT MIRRORS TO
    ITSELF.** A crouch with the head centred on a symmetric squat is its own
    mirror, so ducking reads as the figure being SQUASHED rather than as it
    dropping and still looking where it is going -- the same defect as the
    mirrored run beats, from a pose nobody would suspect. Push the brim
    forward, set the face forward under it, give the shoulders a lead over the
    trailing rump, and **measure the composite against its own mirror** rather
    than judging the layers separately. The layers tell you nothing about it.
  - **AND AN "EXTRA" POSE IS ONLY A POSE IF IT MEASURES DIFFERENT.** Kelly was
    given a standing drawing, because an animation counter that advances by
    DISTANCE freezes when the actor stops and leaves him holding whichever beat
    he halted on. The file came back **byte-identical to run frame 1** -- the
    same sixteen rows uploaded into a second slot. The fix is a one-line alias
    (`IF kmv = 0 THEN kb = P_KRUN1`), not a second sprite, and the way to find
    out is to `==` the assembled art rather than to read the two files. Keep
    the vacated slots as declared BLANKS so nothing renumbers, and say in the
    table that they are free.
  - **A LOOPING DETAIL DRAWN INTO A BAND IS ON SCREEN FOR THE WHOLE POSE.**
    Kelly's raised baton lives in his FACE sprite, and there is one face per
    pose -- so selecting it off the same bit as the body put it up **half the
    time**, which reads as waving rather than running. A detail that should
    punctuate the cycle needs its own, SLOWER bit (`AND 16` on top of the
    body's `AND 8`, so one beat in four) and an explicit override for any
    state where the counter does not advance: a standing jump holds no
    direction, so a distance counter is frozen and the bit is whatever it was
    at take-off. Without the override the detail appears on some jumps and not
    others, for a reason no player can see.
- **AN ART ROW THAT LOSES ONE CHARACTER IS SILENTLY DROPPED, AND EVERY ROW BELOW
  IT SHIFTS UP.** A hand-editable art file that picks out its rows by shape
  ("any line of exactly 16 of `.#-0`") so the file can carry its own header will
  QUIETLY SKIP a row that is 15 wide. Nothing fails: the file still has enough
  art rows, every band/colour check passes, and the generator, assembler and
  cart are all happy. `kelly-run2.txt` lost the trailing dot of two rows and it
  was reported as **two unrelated drawing bugs** -- *"the buttons on the shirt
  are all messed up"* and *"one of the arms sort of disappears"* -- with nothing
  anywhere naming a line, because a shifted block rebuilds the figure out of its
  neighbours' rows. **Make a near-miss a HARD ERROR**: any line made only of art
  characters must be exactly the width, or the build stops naming file, line and
  width. A line that is meant to be prose must start with the comment character.
- **A PARSER THAT SILENTLY MATCHES LESS IS A CHECK THAT REPORTS SUCCESS.**
  `checkanim.py` reads each animated band out of the `.bas` as a base assignment
  plus the `IF <clock> AND <bit> THEN v = v + n` lines after it. Rewriting a
  four-beat ladder as a two-beat ASSIGNMENT (`kb = P_KRUN2`) meant the band
  stopped being recognised, and the gate printed `animation OK -- 1 clocked
  bands` with the player's run entirely unmeasured. Teaching it the assignment
  form, and making its search window count **code** lines rather than source
  lines (a paragraph of comment had been pushing steps out of reach), turned up
  **two MORE bands that had never been measured** -- and one of them failed.
  - This is the mirror of "a check whose scope is narrower than the bug": the
    scope was right and the *extractor* narrowed under it. The count in the
    summary line is the only visible symptom, and nobody reads a passing line.
  - **Assert the subjects BY NAME in the self-test**, with the beat count each
    must have. A gate that says how many things it measured, but never what,
    cannot tell you it has gone blind.
- **A FRACTIONAL-SPEED ACCUMULATOR IS CAPPED BY ITS NUMBER OF DRAIN STEPS, AND
  THE CHECKER WILL NOT KNOW.** Keystone Kapers spends a quarter-pixel speed as
  whole pixels with `hacc = hacc + hsp4` then a run of
  `IF hacc > 3 THEN hspd = N : hacc = hacc - 4`. **Each step can spend one pixel,
  so N steps cap the speed at N px per pass no matter what the constant says.**
  With two steps and `hsp4 = 9` the crook ran at a flat 2.0 while every comment,
  the design table and `checkchase.py` all said 2.25; the surplus leaked into an
  8-bit accumulator that wrapped every 256 passes. Nothing failed -- he simply
  arrived two thirds of a screen short of his own escape.
  - The comment above it stated the invariant correctly (*"hacc is under 4 on
    entry and hsp4 is at most 8, so it can never need a third"*) and was **not
    re-read when the constant changed**. Write the invariant AND check it.
  - **The model must parse the accumulator, not the constant.** `checkchase.py`
    now counts the drain steps out of the source and fails on a speed they
    cannot deliver, instead of dividing and believing the answer.
- **THE LOOP RATE IS A DIFFICULTY DIAL, AND WHERE THE PLAYER STANDS TURNS IT.**
  Anything paced per loop PASS moves slower in real time on a busy screen, while
  anything paced by the frame DELTA -- a countdown clock, typically -- does not.
  In Keystone Kapers the crook is per-pass and the round timer is per-frame, so
  the same uninterrupted escape finished with **TIME 09 in hand from a light
  screen and TIME 00 from the lift screen**. Measured, not inferred: a pass
  counter gave 2,335 passes over ~98 s (23.8/s) against the model's assumed 25.
  Raising the quarry's speed papers over it. **The fix is to pace the actor off
  the same clock as the thing that judges it** -- in Keystone Kapers the crook now
  accumulates once per elapsed FRAME rather than once per pass, and the spread
  collapsed from 00-vs-09 timer units to 04-vs-04.
  - **A per-frame accumulator wants a FINER unit and FEWER drain steps.** His
    step drops under a pixel a frame, so two drains suffice where three were
    needed per pass -- and the finer unit is what makes the speed tunable: in
    sixteenths one notch was six seconds of his route, in sixty-fourths one and
    a half.
  - **CLAMP THE PER-PASS STEP, AND NOT TOO TIGHTLY.** Position tests sample once
    a pass and do not interpolate, so a big step can jump an arrival window or
    pass through a catch radius. But clamping at 3 frames re-created the original
    bug in miniature, because the slowest screen *is* 3 frames a pass: every
    hitch there lost a frame. Size the clamp off the narrowest window, not off
    the typical delta.
  - **WHEN A TIMING IS TUNED AGAINST A MODEL YOU DO NOT FULLY TRUST, ASK WHICH
    DIRECTION IS SURVIVABLE.** Keystone Kapers' checker reads seven seconds
    optimistic against measured play, and the crook was left arriving about eight
    seconds early rather than shaved to the buzzer. The errors are not symmetric:
    early costs a little tension, late means he **never escapes at all**, which
    deletes one of the two ways to lose a round -- silently, because the game
    still runs perfectly well without it. Spend the margin on the side where
    being wrong is cheap, and record it as a decision so it does not read as an
    unfinished tuning job.
  - **A rider on a cyclic animation stays on the animation's clock** -- it cannot
    move to the frame delta without drifting off or aliasing. Mixing the two
    within one actor is correct, and the model has to count them in their own
    units (adding passes to frames and dividing by one rate is a units error a
    ratio test cannot see).
- **A DEBUG READOUT THAT COSTS ANYTHING WILL MEASURE ITSELF.** Five digit-print
  calls per pass dropped the measured rate from 24 to 21 -- the instrument was
  three passes a second of the thing it was reporting. Print once a second, not
  once a pass. Two more traps in the same fifty lines: computing the answer on
  the machine (a route length in pixels) was **150 bytes over the cart cap** when
  reporting the raw position and doing the arithmetic offline was free; and
  holding `FRAME` in a plain variable wrapped at 256 and reported 1 pass a second
  (`bigvar.py` catches a literal over 255, not a variable handed one at runtime).
- **A PROPERTY OF A PAIR IS INVISIBLE TO EVERY CHECK WRITTEN ABOUT ONE OF THEM.**
  Keystone Kapers gates each hazard hard -- checkball.py sweeps a single ball
  against the jump and the crouch frame by frame, checklevels.py pins the round
  each hazard arrives on. Both were right, and from the round where a floor
  starts carrying TWO hazards the pair was unclearable on every screen: the gap
  was 46 px on one side of the lift and 70 on the other, against the 168 px of
  closing distance one jump consumes, so the player cleared the first and came
  down onto the second. Neither check could see it, because neither asks a
  question about two objects.
  - **The asymmetry is what gets REPORTED, and it is not the fault.** It
    surfaced as "on the left and right of the elevator they seem closer
    together" -- true, and a distraction: both sides were already below the
    floor. The difference was two placement bytes; the defect was that the
    spacing had never been derived from anything.
  - Derive the spacing from the mechanic that must fit through it (here the
    jump s airborne frames times the closing speed), name it, and check it.
    games/KeystoneKapers/assets/checkspace.py does, and REPORTS rather than
    fails on the one case the screen cannot satisfy -- a check that demands the
    impossible is a check somebody deletes.
- **ANCHOR A GENERATED-ART EDIT ON THE THING'S NAME, NEVER ON ITS COLOUR OR
  ITS BYTES.** Two edits meant for one character in Keystone Kapers' art table
  matched on `""", WHITE, GRAY),` instead, which four characters shared. Both
  hit the FIRST of them, so the lift shaft was recoloured twice and the intended
  character never changed at all. **Nothing failed**: both are real characters,
  both ended up with plausible colours, every generator and gate passed, and the
  only symptom was a white band across the roof bar where a pillar met it --
  reported as a drawing bug in the pillars, which is not where the edit went.
  Colour arguments, pattern rows and byte lists all repeat across an art table
  by design; the name is the only unique thing in the entry.
- **A LABEL CAN BE PRINTED FROM MORE THAN ONE PLACE, AND A LAYOUT CHECK CANNOT
  SEE THE ONE YOU MISSED.** Moving the HUD's `TIME` two columns right produced
  `TIMEME` on screen, because a flash routine blinks the same label when the
  clock runs low and carried its own copy of the column. A checker that tests
  each write for overflow and collision passes: two writes of the same string at
  different columns collide with nothing and overflow nothing. Grep for the
  literal, not for the routine that appears to own it.
 Anything timed — a beep interval, a countdown, a
  telegraph — must decrement by the frame delta, not once per loop pass, or it slows down exactly
  when the loop gets busy. That is the same root cause as movement slowing (§3A's FRAME-delta
  item), and it is worst for warning cues, which become least reliable precisely when the frame is
  most loaded. Corollary: once a timer decrements by a *variable* delta, any logic keyed on its
  **parity** (`t AND 1`) breaks — an even delta freezes the parity. Drive alternating states from
  their own phase counter.
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
- **A PROXY CONDITION THAT AGREES WITH THE REAL RULE IN THE COMMON CASE IS AN
  EDGE CASE WAITING.** Keystone Kapers boarded an escalator from a jump only if
  the arc was **descending**. That is true of every ordinary landing and it is
  not the rule: the rule is "he has arrived on the staircase from outside it".
  A flight is a diagonal and the jump's apex is 14 px, so an arc can clear the
  three treads it could land on and then meet the riser of the fourth, at 16 --
  which is above the apex. That collision happens while still **rising**, so the
  proxy rejected it and the player went through the staircase onto the floor
  underneath.
  - **Replace the proxy with the property.** "Has been above the surface during
    this jump" is one byte and covers both a tread hit on the way down and a
    riser hit on the way up -- and its complement is exactly the walkable floor
    beneath the flight, which must keep working.
  - **The bug's rarity is a fingerprint of a launch window, not of flaky input.**
    It needed a 40 px band of starting positions; the reporter said "this is
    rare", which is what a geometric edge case sounds like from play.
  - **A sweep is the only honest answer to "check all scenarios".**
    `assets/checkjump.py` runs 108,000 arcs -- every launch x, both flights,
    every animation phase, frame delta, jump direction and accumulator phase.
    Two construction rules made it trustworthy: the geometry is modelled in the
    checker (ground truth) while the **boarding rule is parsed out of the `.bas`
    and executed**, so it cannot drift from the game; and an unrecognised
    statement is a **hard error, not a skip** -- when the fix added a block `IF`
    the interpreter stopped rather than silently ignoring two lines, which would
    have left it passing everything. Its extractor then had that exact bug
    (stopping at the first `END IF`, which now closed the inner block), and only
    `checkjump_test.py` -- which types out the rule that shipped the fault and
    asserts the sweep rejects it -- proved the clean run meant anything.
- **A SCREEN THAT IS DRAWN AND NOT LISTENING IS NOT UP YET, AND EVERY SYMPTOM OF
  THE GAP LOOKS LIKE AN INPUT BUG.** Drawing a menu before the setup that follows
  it is an obvious win and measures like one -- Keystone Kapers' title went from
  4.03 s to 2.62 s. What it actually bought was a **finished, readable, deaf**
  screen: `setup_rest`, `init_tables` and a 40-frame calibration all ran after the
  draw and nothing polled input during them.
  - **It was reported three times over three sessions and misdiagnosed twice**, as
    `8-3-8` losing its first digit, then a start press that did not take, then
    *"FIRE TO START is delayed"*. The first diagnosis was keyboard noise and
    produced a three-frame stability filter that ate REAL presses; the second was
    that the prompt needed to be printed later so its arrival marked the moment.
    Neither is the fault. Both made it worse.
  - **The fix is to put the work back in front of the draw**, not to shrink it or
    to label it. The screen appears later and is live on the frame it appears; the
    extra time lands on a black screen where there is nothing to act on. Keeping
    the routines split still pays, because the re-entry label sits BELOW the setup
    and a second game redraws the title without rebuilding anything.
  - **The general rule: an optimisation that reorders work around a user-visible
    moment has to account for what the program can DO at that moment, not only
    what it shows.** Anything that puts a prompt on screen before the loop that
    reads it is this bug, and it will be reported as flaky input.
- **THE ALPHA LOCK / VERTICAL-AXIS GUARD WAS REMOVED, AND THE ENTRY BELOW WAS
  PARTLY WRONG.** It claimed "every other game in this repo dodges this by not
  reading up/down at all". **Eight of them read it** -- Adventire, Astiroids,
  HardHatMack, Ms. Pac-Man, RallyX, Structris, UFO, Bust-A-Bobble -- and none has
  a calibration or has ever shown the fault. Keystone Kapers was the only game
  that guarded against it and the only one with trouble.
  - **It never fired.** The notice it prints on detecting a stuck axis has never
    appeared on the machine this is developed on.
  - **The original evidence is suspect.** The symptom was "the title comes up and
    it will not start", and the first version of the guard BLOCKED until the axis
    cleared. That is indistinguishable from the several input bugs since found
    and fixed for real -- keys arriving at a screen not yet listening. The
    diagnosis was probably one of those.
  - **It cost two bugs of its own**: forty frames of a drawn but deaf title
    screen, which swallowed the first digit of `8-3-8` and could lose a button
    press; and a wrong theory about keyboard noise that led to a stability filter
    which ate real presses.
  - **Do not re-add a guard on this without reproducing the fault first.** If a
    stuck axis appears it is obvious -- the player ducks or rides the lift
    without asking. The removed code is in the history.
  - The mechanism below is still true as electronics, and `invertcaps` is still
    the Classic99 default. What is not established is that it causes a problem in
    practice.
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
- **SPRITE SLOTS ARE A SHARED NUMBER SPACE, AND "THE NEXT FREE ONE" USUALLY IS
  NOT.** Slot numbers are typically handed out in blocks -- player, enemy,
  hazards, HUD -- with the blocks only written down in a comment, so adding a
  sprite to an actor and taking the number right after its last one lands in
  the middle of somebody else's block. Both writers succeed; whichever runs
  later in the frame wins.
  - Keystone Kapers gave Harry a fourth sprite at slot 8. Slots 8-15 are the
    OBSTACLES, and the obstacle pass runs later in the same routine, so his new
    leg stripes were written and overwritten every frame. **Two symptoms,
    neither an error:** the stripes never appeared, and *a ball flickered
    somewhere it did not belong* -- obstacle 0 dragged to Harry's position and
    pattern for part of each frame and then put back. The second was reported
    as a flicker-control regression, which is what it looks like.
  - Grep for every `SPRITE <n>` **and** every computed slot (`SPRITE ds`,
    `ds = di + 8`) before picking a number, and put the block map in the source
    next to the allocation rather than in a design doc.
  - **A RANGE WRITTEN BY RAW VRAM ADDRESS IS OWNED BY NOBODY AS FAR AS ANY GATE CAN
    SEE.** Keystone Kapers' radar canvas is 48 CHARACTERS that `scan_wipe` rewrites as
    raw pattern memory every frame. No `DEFINE`, no upload, nothing in the source that
    looks like a claim -- so the pattern-ownership gate reported those codes as FREE and
    a second copy of the font was put there. It uploaded correctly and was scribbled
    over from its twelfth character on; the HUD came out as bands of unrelated art.
    **This was the same class of mistake the gate had just been written to catch, one
    day later**, which is the point: a gate that derives ownership from uploads is blind
    to everything drawn another way. Derive those ranges too (from the art generator's
    own constant, never a second copy of the number) and make the gate PRINT the free
    space so the next reader is told rather than guessing.
  - **AND THE SAME IS TRUE OF PATTERN CODES, WHERE "A FREE GAP" IS USUALLY SOMEBODY'S
    ART.** Keystone Kapers moved a sprite pose into "176..207, a 32-code gap nothing
    else uses" and it was the player-chased actor's own left-facing LEG bands. The
    upload succeeded, the art loaded at the address it was given, every gate passed,
    and the only symptom was **a detached block of the wrong art a dozen pixels below
    the actor, on alternate frames** -- reported as "a ball shaped thing drops below
    his feet". The real free space was twelve patterns against the sixteen needed.
    **Derive the free list from the art generator's table and print it; never assert a
    range is free.** `games/KeystoneKapers/assets/checkpat.py` resolves every upload
    (both the `nchr`/`ncnt`/`ntab` form and `DEFINE CHAR`/`DEFINE SPRITE`) to a range
    and a source and fails on any that lands in another table's codes, with the
    deliberate borrows declared by name.
  - **A ROUTINE HANDED ITS ADDRESS BY ITS CALLER BELONGS TO NO ONE SCREEN, AND A
    LAYOUT GATE HAS TO ATTRIBUTE THE WRITE TO THE ASSIGNMENT RATHER THAN TO THE
    POKE.** Keystone Kapers shared one digit printer between the in-game HUD and
    a new score line on the title card. `checklayout.py` refuses to pass a
    drawing routine it cannot map to a screen -- correctly -- and there was no
    honest answer: mapped to the game, the title's `HI` field collided with the
    game's TIME digits, and no nine-character field on row 0 avoids the game's
    TIME label, its digits and the lives icons at once. **The two screens want
    the same columns for different things, which is fine, because they never
    coexist.** The fix is that the checker records `(literal, assigning label)`
    and tests each write against the screen of the routine that SET the address.
    That is strictly more accurate, not looser: the shared printer's columns
    stop all landing on one screen and split across the two that own them.
  - **A CHECK ADDED ALONGSIDE THE CHANGE IT IS MEANT TO GUARD WILL AGREE WITH IT.**
    The same commit taught `checkchars.py` to verify the pose's `CONST` against the
    `nchr` of the upload that loaded it -- two halves of one mistake, both saying 176,
    so it passed. **A constant is only checked when it is compared against something
    INDEPENDENT of it.** Compare against the generator, never against the other end of
    the same edit.
  - **A TIGHT `VPOKE` LOOP IS A VBLANK OVERRUN WITH NO UPLOAD IN SIGHT.** The same
    game drew its message boxes with a `VPOKE` loop and no `WAIT`: ~43 cycles a cell
    and a hundred-odd cells, against ~1679 available, so the tail was discarded at the
    PPU and the box came out with characters missing -- intermittently, because the
    cut point moves. **Pace any unbounded write loop**, and prefer a bound that needs
    no counter (one `WAIT` per row) when RAM is tight.
  - **AND ONCE A BOX IS COLOURED BY THE ATTRIBUTE TABLE, ITS POSITION IS ON A
    FOUR-ROW GRID FOR EVER.** An attribute byte covers FOUR characters by four,
    so a message box sized and placed to cover whole bytes -- which is what
    stops colouring it repainting the scenery around it -- can only ever start
    on rows where `(row + picture offset) % 4 == 0`. Keystone Kapers was asked
    to move its boxes down TWO rows and could not: the legal rows are 1, 5, 9,
    13, 17, 21, so the nearest move downward is FOUR. Moving two would have
    straddled two byte rows, and colouring both repaints sixteen columns of
    eight rows -- two whole floors of shop -- in the box's colour. **Say this
    when it comes up rather than quietly shipping the two-row version on the
    TMS targets and a four-row one on NES**: a difference in kind between
    targets is what every gate that parses the source is built to assume away.
  - **A FOUR-ROW BOX CANNOT CENTRE A ONE-ROW MESSAGE, AND THE ONLY CHOICE IS
    WHICH SIDE GETS THE ODD ROW.** One above and two below, or two above and
    one below -- there is no third option while the box has to cover a whole
    attribute byte, and shrinking it to three rows leaves the fourth row of the
    COLOURED block showing scenery through it, which is worse than an uneven
    margin. Keystone Kapers shipped the first and it was reported as *"an extra
    row below the message"*. Put the odd row above: the eye reads a gap under
    text as unfinished and a gap over it as headroom.
  - **CENTRE TEXT FROM THE TEXT, NEVER BY TYPING THE PADDING.** Keystone Kapers'
    five message lines were padded by hand to a fixed box width and two of them
    -- `GOT HIM!` and `TIME UP!` -- sat one column left of centre with the
    surplus on the right. It is invisible in a source listing because every line
    is the right LENGTH, which is the only thing a width check can ask about,
    and on screen it reads as the BOX having a wider margin on one side. One
    helper that takes the words and returns the padded line cannot be typed
    wrong.
  - **TEXT HAS NO BACKGROUND UNLESS YOU GIVE IT ONE, AND INDEX 0 CANNOT BE IT.** A font
    uploaded with no colour table gets ink on index 0 -- the UNIVERSAL backdrop, one
    colour for the whole screen -- so every character sits in a box of it. To put a
    colour behind text, its PAPER has to move to another index, and paper is written
    into the second bitplane at upload time: it is a property of the character, not of
    where the character is drawn. A colour table of identical bytes is the cheap way
    (ROM is three budgets and this is not the scarce one); a second copy of the font is
    usually neither possible nor needed, because in game all the text wants the same
    treatment. Then remember that **a blank cell is ALL paper**, so every region that
    holds blanks needs its attribute byte pointed at a palette whose index 1 is right --
    Keystone Kapers got a green band above its score line from two rows nothing draws in.
  - **A COSMETIC RULE APPLIED BY HAND AT EACH SITE WILL MISS ONE, AND THE MISS IS
    INVISIBLE TO EVERY CHECK YOU HAVE.** Keystone Kapers colours each message box by
    pointing its attribute bytes at the HUD's palette, written out at each call site.
    One was missed and `GOT HIM!` kept the store's gold-on-green while every other box
    went white-on-blue. **Nothing failed** -- it is a readable message in the wrong
    palette, which no layout, overflow or collision check can speak to, and the author
    had no list to compare against because the list was "the places I edited". Make it
    a ROUTINE and derive the rule from the PRODUCER: `assets/checkmsg.py` requires
    every `msg_*` draw to be flushed before and coloured after, and is mutation-tested
    against the real miss. Same shape as `snd_off` going stale.
  - **GIVING TEXT A PAPER MAKES EVERY PRE-EXISTING `CLS` VISIBLE.** A cleared cell is
    all paper. While that paper was index 0 -- the backdrop -- a clear went black and
    read as part of whatever redraw followed it; once the paper is a real colour the
    same clear becomes a flat field of the region colours. Keystone Kapers had a
    redundant `CLS` before its full redraw for the whole life of the port and nobody
    saw it until the HUD got a background; it was then reported as full-screen flashes
    "at indeterminate intervals with nothing special going on" -- the interval being a
    round, which is not special to look at. **Audit every clear when you add a paper**,
    and delete the ones whose redraw covers the screen anyway.
  - **`CLS` CLEARS THE ATTRIBUTE TABLE, SO ANYTHING WRITTEN TO IT BEFOREHAND IS LOST.**
    Setting a screen's palettes and then clearing the screen loses the palettes, and the
    symptom is a screen whose text is on the wrong colour -- not a blank screen, which
    is what "the CLS wiped it" sounds like it would look like.
  - **AND WATCH FOR A CHARACTER SENT TWICE IN TWO DIFFERENT FORMS.** That game's
    marquee lamps were loaded once with the store's colour table (paper -> index 1)
    and re-sent at run time with `#ncol = 0` (paper -> index 0, the backdrop). Both
    were correct in their own context and the screen visibly changed colour a second
    after it appeared, one character at a time, as the second form caught up. **Send
    it at setup in the form the run-time path uses**, or the first frame of a screen
    is not the screen.
  - Check the hide/reset paths too: a `FOR i = 0 TO 23` that blanks sprites
    will not cover a slot outside its range, and widening it may blank a block
    it was deliberately skipping.
- **WHEN YOU CHANGE A UNIT, THE CHECKER THAT STILL PASSES IS THE SUSPICIOUS ONE.**
  Keystone Kapers moved its hazards from px-per-pass to 64ths-of-a-px-per-frame,
  which changed the constants from `2` to `51`. Every gate still passed.
  `checkspace.py` was cheerfully printing `closing 55 px/pass` -- Kelly's 4 plus
  the hazard's new 51 -- and passing *because* a nonsense closing speed makes
  "one jump clears both" trivially true. **A units change should break something;
  if nothing breaks, the checks are not reading the units.**
  - **The deeper error it exposed had been there for months.** The file multiplied
    the JUMP ARC's length by a PER-PASS speed, and the arc is indexed by a counter
    that advances by the frame delta -- so its entries are frames, and every
    closing distance came out ~2.4x too large. The hazard gap had been chosen
    against those inflated numbers and was in the "dangerous middle" the file
    exists to reject: too far apart to clear in one jump, too close to land
    between. It had been reported from play and not recognised.
  - **A checker's self-test that re-derives the model by hand will re-derive the
    bug.** `checkspace_test.py` computed the same window the same wrong way, so
    the two agreed perfectly. Re-deriving is still right -- importing the numbers
    would make the test vacuous -- but the test must be re-derived from the
    SOURCE's units, and every historical bad case kept as a case. The gap that
    shipped is now one of them.
  - **The tell that a unit is lying is a label.** `checkchase.py` printed
    `'Kelly %d px/frame'` for a constant that was px per PASS, and a `climb_by_lift`
    that summed frames and passes into one number. Both were correct when written
    and both silently stopped being so.
- **A KEYPRESS THAT DISMISSES ONE SCREEN MUST NOT ACT IN THE NEXT, AND THIS COSTS
  A FIX PER SCREEN.** The press is still down when the next screen starts reading,
  so it arrives there as input nobody gave. Keystone Kapers paid for this four
  separate times before anyone wrote it down:
  - the cheat code's final `8` was typed into the setup page's first field;
  - the sound bench played a variant on boot from the cart-select keypress;
  - the title screen's own `8-3-8` was broken by spurious reads between presses;
  - and FIRE on the title made the player JUMP on the first frame of the round.
  - **Wait for the RELEASE, not for a different value.** An edge-triggered read is
    not enough: the value has not changed yet, it is simply still there. The fix
    that works everywhere is to spin until the control reads idle before the new
    screen starts listening.
  - **But CAP THE WAIT.** A stuck or shorted line turns "wait for release" into a
    dead game, which is worse than the bug -- the same mistake as blocking on an
    ALPHA LOCK check that can never clear. Give up after a second and carry on.
  - **A latch reset in the new screen may not be enough.** Clearing the jump's
    release flag when the round starts is obviously correct and did not fix it in
    play; waiting for the button did. When two latches interact, stop reasoning
    about their order and wait for the physical thing.
- **HIDING A SPRITE *AFTER* DRAWING IT SHOWS IT, whenever the routine can span a
  vblank.** CVBasic's `SPRITE` writes a RAM mirror that the vblank ISR copies to
  VRAM, so a draw-then-hide in one pass is only invisible if no vblank falls
  between the two writes. A long draw routine on a busy screen spans two or three
  frames, so the intermediate state is latched constantly. In Keystone Kapers the
  player flickered at the floor he had just left while riding the lift, which
  reads as a drawing bug and is not one. **Decide visibility BEFORE drawing** --
  it costs one test and the mirror never holds a position to be caught with.
- **A STRICT INPUT RESET AND A NOISY KEY LINE DESTROY EACH OTHER.** On the TI,
  ALPHA LOCK shorts a keyboard line (and Classic99 defaults to `invertcaps`, so it
  reads DOWN with the host's Caps Lock UP), and `cont1.key` then returns values
  nobody pressed for a frame or two at a time. A cheat-code state machine whose
  reset is deliberately strict -- anything that is not the next digit clears it,
  so `8,5,3,8` cannot work -- is cleared by that noise too, so the code typed
  correctly does nothing.
  - **The symptom names the cause if you read it carefully**: "8-3-8 does nothing,
    then 3-8 works". The trailing 8 of the failed attempt was still standing as
    state, which only happens if the reset fired *between* the player's presses.
  - **Fix it with a stability filter, not by weakening the reset.** Require the
    key to hold for three frames (50 ms); a human press is several times that and
    the noise is one or two. Cap the counter AT the threshold and test for
    equality, so a held key is accepted once rather than every frame.
  - This is the same short behind two earlier Keystone bugs -- the setup page
    opening on its own, and the cheat code's final digit being typed into its
    first field. **Any new `cont1.key` reader on this machine inherits it.**
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
- **A REACHABILITY CHECK THAT MODELS ONLY EXPLICIT JUMPS WILL CALL LIVE CODE
  DEAD.** A dead-label sweep over Keystone Kapers reported `tick_flash` --
  the low-time warning -- as unreachable: nothing `GOSUB`s or `GOTO`s it, and
  `git log -S "GOSUB tick_flash"` found no commit that ever had. It runs fine.
  It is entered by **FALL-THROUGH** from the routine above it, which ends without
  a `RETURN` and drops into the next label, and which says so in a comment. In
  CVBasic that is ordinary control flow, not a trick.
  - **A false alarm during a delete-things pass is worse than a missed byte.**
    Deleting it would have removed a working feature and the ROM saving would
    have looked like a win. Any "unused" list must model fall-through -- a label
    is reachable if the statement before it can complete -- or be treated as
    suspects to confirm rather than a work list.
  - This is the mirror of the scope trap below (a check narrower than the bug
    reports success): a model narrower than the control flow reports a **failure
    that is not there**. Both cost the same trust.
  - The rest of the same sweep was sound: two assignments the compiler itself
    flagged as never read, and three CONSTs matched nowhere in the text.
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
  - **`define_color` ALWAYS does the triple copy** (`bl @LDIRVM3` in the generated
    assembly), so it cannot patch one screen third. A routine that colours a single
    third has to stay a `VPOKE` loop; check which you have before converting.
- **DRAW THE FIRST SCREEN AS SOON AS THE FONT EXISTS, NOT WHEN SETUP IS DONE.**
  Boot-time asset loading naturally gets written as one block with the title after
  it, and then every byte of it is time the player spends watching nothing. Almost
  none of it is needed to draw text. Splitting setup so the title is drawn after
  the font and before everything else does not reduce the work -- it moves the work
  behind something worth looking at, which is what the player actually experiences
  as speed. Keystone Kapers went from 4.03 s to 2.62 s with no work removed beyond
  the fill above.
  - **Check the re-entry path, not just first boot.** The title routine is usually
    also the game-over destination, so splitting it can leave the second visit
    drawing nothing or re-running boot-time work.
- **A ONCE-PER-POWER-ON HARDWARE PROBE INSIDE THE TITLE ROUTINE RUNS ONCE PER GAME,
  AND THE RE-RUNS ARE WRONG.** Keystone Kapers samples the joystick's vertical axis
  for 40 frames to detect a latched ALPHA LOCK (§3A above), then ignores that
  direction for the run. It lived inside the title routine, which `GOTO boot`
  re-enters after every game over. The probe's whole validity rests on being taken
  **before any input is plausible** -- on a return to the title that is false, so a
  player still holding a direction had it read as a stuck key and **disabled for the
  next game**. Hoist any calibration whose answer cannot change to the one-time boot
  path; redraw its notice per screen if the screen is cleared.
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
- **CLASSIC99 DEFAULTS TO `invertcaps=1`, so the TI sees ALPHA LOCK *DOWN* WHEN THE HOST'S
  CAPS LOCK IS *UP*** -- the normal state of a keyboard. Combined with the ALPHA LOCK / joystick
  vertical-axis short (`ti99-alpha-lock-joystick-vertical`), that means **`cont1.up` reads as
  permanently pressed on a default install**. Any game that reads the vertical axis is affected
  out of the box, not in some rare configuration.
  - **DETECTING IT IS NOT ENOUGH -- DO NOT BLOCK ON IT.** Keystone Kapers' first version printed
    `RELEASE ALPHA LOCK` and refused to start until the axis cleared, which on a default
    Classic99 is never: the game sat on its title screen forever and presented as *"the title
    comes up and it will not start."* **Calibrate instead**: sample up and down for ~40 frames
    before any input is plausible, treat a direction held for essentially all of them as the
    key rather than the player, say so on screen, and ignore that direction for the rest of the
    run. A check that turns a survivable input quirk into a dead game is worse than no check.
  - Corollary for any title screen: **do not make FIRE the only way to start.** On the TI fire
    is TAB, which Windows also treats as a focus change; accept a digit as well.
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
- **THE NES TARGET RUNS A TMS9918-SHAPED GAME, AND THE THING THAT SAID IT COULD NOT WAS A
  MISREADING OF THE CARTRIDGE HEADER.** This entry used to say the target was blocked. Keystone
  Kapers now boots, draws its store in colour and plays on `--nes`; what follows is what it took
  and what it cost, because every game here will hit the same seven things.
  - **`DEFINE` really is unimplemented** — not `DEFINE CHAR`, `DEFINE COLOR` or `DEFINE SPRITE`
    (`cvbasic.c`: `if (machine == NES) emit_error("DEFINE isn't implemented for NES")`), and `VDP`
    is refused too. A `--nes` compile of any game here ends in dozens of errors (Keystone Kapers 58,
    Bust-A-Bobble 59).
  - **BUT AN iNES HEADER WITH A CHR-BANK COUNT OF *ZERO* ASKS FOR 8 KB OF CHR-*RAM*, AND THAT IS
    THE HEADER CVBASIC ALREADY EMITS.** `NES_CHR_BANKS` is written from `chrrom_size`, which stays
    0 unless the program uses `BITMAP` or `CHRROM`. So the pattern table on an ordinary CVBasic NES
    build **is writable at run time**, through `PPUADDR`/`PPUDATA` like any other VRAM — which is
    all `DEFINE CHAR` ever did. The reasoning that blocked this for a session ("patterns live in
    CHR, CHR is cartridge ROM") is true of CHR-ROM and simply not true of the cart CVBasic builds.
    **Check the header bytes before believing an architecture claim**: `4E 45 53 1A 02 00 …` is
    PRG 2 banks, **CHR 0**.
  - **Reach it with the `ASM` statement.** CVBasic has one, variables are addressable as
    `cvb_NAME` (and `VARPTR label(0)` works on a `DATA BYTE` label), so a helper routine plus
    `#if NES` branches at every `DEFINE` site is the whole mechanism. No compiler patch.
    `games/KeystoneKapers/assets/nes_chr.asm` is the worked example.
  - **The two senses of "define" are still unrelated.** `#if NES` is a PREPROCESSOR constant and
    works perfectly (`--nes` auto-defines `NES`). `DEFINE` is a runtime upload. Confusing them
    wastes a session; so does concluding from `DEFINE`'s absence that no runtime upload exists.
  - **A 16x16 TMS sprite pattern needs NO repacking to become two NES sprites.** The four 8-byte
    tiles are ordered left-top, left-bottom, right-top, right-bottom, and an NES 8x16 sprite is a
    tile pair at an even index — so `(p, p+1)` is the left half and `(p+2, p+3)` the right. Mirror
    OAM slot *n* into *n+28* with the tile two on and x eight right, in ONE routine at the end of
    the draw, not as a second `SPRITE` statement beside each of the dozens.
  - **In 8x16 mode the sprite pattern table is bit 0 of the OAM tile byte**, and the PPUCTRL sprite
    bit is ignored. Pattern numbers that are multiples of four are all even, so the sprites are
    nailed to `$0000` — move the BACKGROUND to `$1000` instead (PPUCTRL bit 4). That also lands
    background patterns at address 4096, exactly where the TMS bitmap mode's third screen third had
    them, so a game that pokes pattern memory needs a stride change (8 → 16) and nothing else.
  - **THE NAME TABLE IS 32x30, NOT 32x24, AND ITS TOP EIGHT SCAN LINES ARE UNDER THE BEZEL.** A
    24-row picture written at row 0 loses its top row into overscan — which presents as *"the score
    and timer don't show up, but they flash when I hit something"*: the HUD is being written
    correctly and is simply not visible. Drop the picture three rows (+96 on every name-table
    address, +96 on every `PRINT AT`, +96 on the `SCREEN` destination).
  - **AND THEN EVERY SPRITE Y HAS TO FOLLOW IT DOWN, +24 PIXELS.** A sprite's y is a SCREEN
    coordinate and knows nothing about where the name table was written, so moving the background
    alone puts the whole cast three rows above the floor. It reads as *two* bugs — "the actors are
    a bit high" and "the radar dots are off the radar" — and it is one offset seen twice. **The
    radar is the measuring stick**: its canvas is characters and its dot is a sprite, so their
    disagreement measures the background-vs-sprite offset directly. Do it at the ONE table every y
    derives from (`flry` here), never at the call sites, and **never in the OAM mirror routine** —
    that applies itself in place to slots the game did not rewrite, so a y offset there would move
    every actor further every frame.
  - **`SPRHID` 209 IS A VISIBLE ROW ON THIS MACHINE.** There is no sprite-list terminator; y is just
    a row. Two dozen "hidden" sprites at 209 draw in a heap near the bottom of the screen with
    pattern 0 — whatever art that happens to be — and swamp the eight-per-scanline budget, taking
    the real actors down with them. It is reported as *flicker*. Hide at 240 (`$F0`), which is what
    the prologue's own `clear_sprites` uses.
  - **COLOUR DOES NOT MAP, AND THE ATTRIBUTE TABLE IS USUALLY THE WRONG TOOL.** A TMS cell carries
    ink and paper PER CHARACTER PER SCAN LINE; the NES picks one of four palettes per 16x16 BLOCK.
    In any tile-map game a wall, the pillar beside it and the bar above it share a block, so no
    per-block palette can separate them. **Use the second BITPLANE instead** — it is per character,
    which is the shape the `DEFINE COLOR` data already has. Read the game's own colour table, map
    each TMS colour to one of four palette indices, and write ink where the art has a bit and paper
    where it has not. That gives per-character two-colour cells out of one global palette, with no
    attribute-table work and no extra art. **Rebuild the two masks once per ROW, not once per
    character** — an NES tile is eight rows of two bits per pixel, so each row picks its own pair
    out of the four entries, which is the same shape as the TMS's eight colour bytes.
    **PER-SCAN-LINE COLOUR IS NOT LOST HERE; only per-scan-line colour beyond FOUR INDICES is.**
    Keystone Kapers collapsed the eight bytes into one and it cost a session: its floor bar sets
    **8 of a character's 64 pixels** — one row — because the bar's five yellow rows over three
    green ones live entirely in the colour table and not in the art. Flattened, the floor became a
    one-pixel line and the end walls stopped meeting the storey above, which was reported as *the
    building's support having a gap in it* — a colour bug wearing a structural costume. Any
    character whose shape lives in `DEFINE COLOR` rather than in `DEFINE CHAR` fails this way, and
    it does not look like a colour problem.
    **Sprites are fine**: colour is per sprite in the OAM byte, so a stack of single-colour sprites
    survives. Map the TMS colour there too — the NES reads only its low two bits, so `11` and `15`
    both land on palette 3 — and make the map **idempotent** if it is applied in place.
  - **ANYTHING PACED PER LOOP PASS RUNS AT A DIFFERENT SPEED HERE.** The 6502 build runs far more
    passes a second than the 9900 one, so a per-pass cyclic animation (and any rider locked to it —
    see the one-clock rule above) runs correspondingly fast. **Do not fix it by stepping the
    animation faster or slower**: a cyclic animation can only advance one phase per pass, and the
    rider must stay on the same clock. Put a **floor** on the loop rate instead — wait until as many
    frames have elapsed as a pass takes on the reference machine — which keeps every per-pass thing
    coupled and cannot speed anything up.
  - **`VPEEK` is unavailable, for a second and independent reason.** `WRTVRM` on NES does not touch
    the PPU — it queues into `PPUBUF` for the NMI to flush — so a read-back is both illegal during
    rendering and blind to everything still queued. Any read-modify-write on video memory needs its
    "read" to come from a RAM shadow or from the data the draw came from.
  - **A per-pass CHR-RAM write must be QUEUED, not written synchronously.** Turning rendering off
    and waiting for vblank costs a whole frame per call (the NMI never services the vblank you
    waited for, so the game's own `WAIT` then waits for the one after). For a contiguous run of
    characters, build the bytes into a RAM buffer and push ONE of the NMI queue's copy descriptors —
    five bytes in `PPUBUF`, no frame lost.
  - **THE NMI'S COPY LOOP DOES NOT STOP WHEN VBLANK ENDS, SO ~100 BYTES A FRAME IS THE REAL
    BUDGET — AND THE OVERFLOW IS DISCARDED BY THE HARDWARE, NOT QUEUED.** Both `WRTVRM` and
    `LDIRVM` end in `JMP wait` when `PPUBUF` fills, so it is natural to conclude that nothing
    can be lost. Nothing is lost *in the queue*; it is lost at the PPU. `nmi_handler`'s copy is
    a flat `LDA (ppu_source),Y / STA PPUDATA / INY / BNE`, which runs to the end of the
    descriptor whatever the raster is doing, and **a `PPUDATA` write outside vblank is dropped
    on the floor**. NTSC vblank is ~2273 CPU cycles, OAM DMA takes 513 of them, and the loop
    costs ~14 a byte: **about a hundred bytes get through per frame.**
    - Keystone Kapers blitted its store a band at a time, `SCREEN …,32,5,32` — **160 bytes**.
      Three rows arrived, the fourth stopped eight or nine cells in, and the floor bar and the
      air row above it were never drawn. On screen: `#########.......................`, on three
      bands out of four, with the fourth surviving only because its blit happened to start
      earlier in the frame. **38% of the picture was black.**
    - **It does not present as a timing bug, it presents as corrupt artwork or a bad blit**, and
      every check of the drawing code passes, because the drawing code is right. The tell is
      that the damage is always a *tail* — whole rows early in the burst, a partial row, then
      nothing — and that the cut column MOVES between runs.
    - **Split any burst over ~100 bytes across frames.** One 32-byte row per `WAIT` is the
      obvious unit for a name-table blit and costs four extra frames a band at round start.
      Do not reach for a bigger `PPUBUF`: the buffer was never the constraint.
    - **AND THE OVERRUN'S OTHER CONSEQUENCE IS THE WHOLE PICTURE JUMPING, WHICH IS FAR
      LOUDER THAN THE DROPPED BYTES.** `nmi_handler` does not end with the copy: it then
      writes `PPUADDR` twice and both `PPUSCROLL` bytes. Done mid-frame that **re-points the
      PPU's own render address**, so the rest of that frame is drawn from somewhere else.
      Keystone Kapers reported it for three sessions as *"the entire screen flashes when
      Harry gets on and off the escalator"* — which sounds like a sprite or pattern bug and
      is neither.
    - **`PPUBUF` ACCUMULATES FOR A WHOLE LOOP PASS, SO EVERY WRITE IN THE PASS SHARES ONE
      VBLANK.** Nothing is written when the program asks; the NMI empties the buffer in one
      go. A pattern upload therefore flushes together with every `VPOKE` the radar made and
      every HUD digit, however far apart they are in the source, and **only a `WAIT` divides
      them**. Two corollaries that cost real time here:
      - **Splitting a big upload in half fixes nothing** unless a `WAIT` goes between the
        halves — both descriptors still land in the same vblank and cost what one did.
      - **Reducing the FREQUENCY fixes nothing either.** The overrun is per FRAME, not per
        second, so a slower animation only makes the bad frames rarer.
      The fix is a `WAIT` immediately before the large upload, giving it a vblank of its
      own. In Keystone Kapers that is one frame a pass on the two escalator screens: 96
      bytes (six characters — **a tile is SIXTEEN bytes in two bitplanes, not eight**) is
      ~1394 cycles of the ~1679 left after OAM DMA, which leaves six `VPOKE`s for the rest
      of the pass. The radar beats that whenever a dot moves, which is exactly why it was
      intermittent.
    - **`games/KeystoneKapers/assets/checkvblank.py` gates it mechanically** — it walks the
      routines reachable from `main` (over `GOSUB`, `GOTO` **and fall-through**), costs each
      queued upload against a 2273-cycle vblank, and fails on a large one with no `WAIT` in
      front of it, or on a rendering-off `DEFINE`-equivalent reachable during play.
      `checkvblank_test.py` feeds it the two forms that actually shipped the fault and
      requires rejection. **Its first run failed on the TI's `SCREEN …,32,5,32`** — a model
      of one machine has to skip the other's `#if` branches, or it reports a defect that is
      not on the target it describes.
    - **EVERY EARLIER DIAGNOSIS WAS A REAL UPLOAD DOING A REAL THING.** Three separate
      per-pass uploads were found and removed, each an improvement, and the flash survived
      all three — because the cause is not *which* upload runs, it is that the pass's other
      writes share a vblank with it. **A per-object question cannot reach a property of the
      frame.**
  - **`SOUND` links against `sn76489_freq/_vol/_control`, which no NES prologue defines.** The 6502
    prologue does, for a 6502 machine with a real SN76489, so a shim can be written against that
    convention — and the pitch maths is near-exact, because the NES CPU is almost exactly half the
    SN76489's clock, making the APU timer `divisor - 1`.
    `games/KeystoneKapers/assets/nes_apu.asm` is that shim. **Enable `$4015` (and `$4017`) once at
    setup** rather than inside the volume write, or a channel given a pitch before a volume is
    written into a disabled channel.
  - **AN ARRAY CAN BE ALLOCATED PAST THE END OF NES RAM, AND CVBASIC WILL TELL YOU THERE IS ROOM
    LEFT.** The NES has 2 KB at `$0000-$07FF` and the address space **mirrors**: `$0800` is
    `$0000`, the zero page. So an array that overruns the top does not fault and does not land in
    unused memory — it overwrites the runtime's own pointers. Keystone Kapers added a 32-byte
    array and CVBasic reported *"1567 RAM bytes used of 1838 available"* while placing the tail of
    the NEXT array five bytes over the end.
    - **The only symptom is a BLACK SCREEN AT BOOT.** No compiler error, no assembler error, exit
      status 0, and a ROM of exactly the right size. Nothing anywhere names RAM.
    - **The array that breaks is not the one you added**, it is whichever the allocator happens to
      place last — so the failure does not point at the change that caused it.
    - **`games/KeystoneKapers/assets/checknesram.py` gates it** and is wired into `build-nes.sh`
      after the compile (it is the one check that cannot run before, because it needs the
      addresses the allocator chose). It reads `array_*: equ $xxxx` out of the generated assembly
      and the sizes out of the `DIM`s, and fails on any array whose last byte is above `$07FF`.
      Mutation-tested against the real defect, not just against a passing build.
    - **Do not "solve" it by staging in an array that already exists** without checking what reads
      that array and WHEN. Reusing the escalator's CHR buffer looked free and was not: `nes_chrq`
      hands the NMI a *pointer* into it and the copy happens at the next vblank, so overwriting it
      meanwhile copied the new bytes into the **pattern table** and destroyed the skyline. That is
      the same deferred-copy hazard as the marquee bug below, hit a second time in one session.
    - **THREE BYTES OF SCRATCH VARIABLES ARE ENOUGH TO DO IT, AND THE SECOND SHAPE OF THE
      FAILURE IS NOT A BLACK SCREEN.** Scalars are allocated below the arrays, so adding two
      temporaries to a routine pushes every array up. Keystone Kapers added `nso` and `#nso`
      (3 bytes) for one piece of setup arithmetic and pushed `#tsrc` -- the table of template
      source offsets its store blit reads -- **one byte** past the end. The game booted, played,
      and drew seven of its eight screens perfectly; on the eighth, two of the three bands
      blitted their NAME TABLE from the wrong address and came out as a field of unrelated
      characters.
      - **It was reported as "the NES display is all corrupted" and it looks like an art or a
        blit bug.** Nothing about one screen's bands being garbled suggests storage, so the
        search starts in the drawing code, which is correct.
      - **The tell is that it follows the SCREEN, not the play session.** It was there on the
        first frame of the round (`TIME 50`), it came back every time that screen was re-entered,
        and every other screen was clean. A bad *pointer table entry* is per-index; corruption
        that accumulates would not behave like that.
      - **Spend no new variable when a constant will do.** The arithmetic was
        `(CH_SKY2 - 96) * 8`, which is a fixed 456 -- it only became a runtime computation
        because a folded constant over 255 truncates (see the `CONST` item above), and the
        answer is to write the bare literal, not to build it in registers.
    - **AND THE GATE MISSED IT BECAUSE `\w` DOES NOT MATCH `#`.** `checknesram.py` read both the
      `DIM`s and the `array_*: equ` lines with `\w+`, so **every 16-bit array was invisible to
      it** -- they are all named `#something` -- and it printed OK having read none of them. Same
      slip as grepping the generated assembly for `NSRC` when the symbol is `cvb_#NSRC`. Two
      further rules came out of the fix, and both generalise to any checker over CVBasic:
      - **A 16-bit array is TWO BYTES AN ELEMENT.** `DIM #tsrc(15)` is 30 bytes, not 15.
      - **An array the assembly has and the source does not `DIM` must FAIL, not be noted and
        skipped.** An array the gate cannot measure is precisely the one that overruns.
  - **`gasm80` assembles 6502 despite the name**, so no separate assembler is needed — but **it
    exits 0 with errors on stdout and still emits a full-size ROM** with undefined labels resolved
    to zero. `gasm80 ... || die` therefore never fires and the build reports success on a dead
    cart. Grep its output for `^Error:` instead. CVBasic likewise prints "Compilation finished"
    AFTER errors; only its exit status is the truth.
  - **A CHECKER THAT MODELS THE TMS SCREEN MUST SKIP `#if NES` BRANCHES, and that is scoping rather
    than blinding — but only while the TI form stays byte-for-byte and the NES form is ADDITIVE
    beside it.** Keystone Kapers' `checkscan.py` read `sdy = sdy + 24` literally and failed on a
    screen it does not describe. Write every NES branch as `#if NES / <extra> / #else / <the
    original line, untouched> / #endif` so the gates that parse `DEFINE …`, `PRINT AT <n>` and the
    like keep seeing exactly what they saw, and so nothing a checker tests can migrate into a branch
    it cannot see.
  - See `games/KeystoneKapers/DESIGN.md` §12a for the full state, the colour table, and what is
    still not done (merged 2bpp sprite art for the eight-per-scanline limit; sound unverified).
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
- **A CHASE RESOLVES ON `path ÷ speed`, AND THE PATHS ARE ALMOST NEVER THE SAME LENGTH.** Two
  speed constants sitting next to each other invite the reading "the player is 1.5× faster, so
  the player wins", and that reading is wrong whenever the quarry's route is shorter. Keystone
  Kapers had Kelly at 3 px/frame against Harry's 2 — and Kelly lost the race to the roof by
  **eleven seconds every single round**, because Harry spawns beside his first escalator and
  runs 4,104 px where Kelly runs 7,992. A 1.95× route needs more than a 1.95× speed, so pursuit
  on foot could not close at any distance given any amount of time.
  - **It does not present as a tuning problem, it presents as the enemy cheating** — the player
    sees themselves visibly gaining and still never arriving. Nothing errors, and neither
    constant is wrong on its own; the defect lives only in the ratio of two quotients.
  - **The corollary is that the quarry's speed is then not a difficulty dial.** Once the margin
    is set, one notch on the quarry can consume all of it: at 1.75 px/frame the slack fell from
    11.6 s to 5.1 s, less than a single obstacle hit. Ramp the hazards instead — which is also
    what the original manuals actually say.
  - **Compute it, do not eyeball it.** `games/KeystoneKapers/assets/checkchase.py` walks both
    routes out of the real constants (speeds, spawns, escalator sides, ride length, round
    timer) and fails the build if the margin, the ordering, or the escape-inside-the-timer
    property breaks. Copy it for any game with a pursued actor.
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
- **`games/KeystoneKapers/assets/sfx/` — measuring sound effects off a reference
  recording, and tuning them.** Three stdlib-only scripts (no numpy) — `sfxscan`,
  `sfxpitch`, `sfxshape` — plus the process in `sfxprocess.md`, the reusable part:
  find the events, read the SN76489 divisors, classify by shape, build a bench
  cart, move a finding into the game. **The first decision is the one that
  matters: take the reference recording with YOUR CHIP in it.** The SN76489 is
  also in the ColecoVision, SG-1000, Master System and BBC Micro, and from any of
  those a frequency converts straight back to the register the game wrote
  (`divisor = 111860 / freq`). From an Atari 2600 recording nothing translates —
  the TIA is a different chip, so every number becomes a judgement. Keystone
  Kapers did the 2600 first and had to do it twice. Both reference sheets live
  here beside the scripts (`sfxref-coleco.md`, `sfxref-2600.md`), and the two
  bench carts that play the candidates sit under `sound/` in that same game --
  `colecosounds` for the ColecoVision pass, `testsounds` for the 2600 one.

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

- **TWO CLOCKS IN ONE LOOP IS A UNITS BUG A RATIO TEST CANNOT SEE.** If the actors are
  advanced once per **loop pass** (`x = x + SPEED` in the main loop) while a timer is
  advanced by the **frame delta**, the game has two different time bases and the loop rate
  silently becomes a difficulty dial. Keystone Kapers ran `WALKSP = 4` px per *pass* at ~25
  passes/s -- 100 px/s, which happened to match the reference exactly -- against a clock
  ticking in real seconds. Kelly needs **72 s** to reach the roof and Harry **96 s** to
  escape; the round was **50 s**, so it always ended on a timeout and one of the two loss
  conditions could never fire at all.
  - **`checkchase.py` passed on every run**, because it converted *both* routes with
    `FPS = 60`. Halving a number on both sides of a comparison leaves the comparison intact,
    so every relative assertion — "Harry is slower than Kelly", "Kelly arrives first" — stayed
    true. The error only appears when the actors are compared against something measured in
    **different** units. A ratio test cannot catch a units error; a checker needs at least one
    absolute anchor.
  - The tell is a constant whose name implies a unit it does not have. `WALKSP = 4 ' px per
    frame` was px per *pass*. **Before trusting any speed constant, find where it is spent**
    and confirm the loop's actual rate — do not read it off the comment.

- **A CENTRING OFFSET ADDED BEFORE A DISTANCE WILL WRAP THE BYTE, AND THE BUG LOOKS LIKE A
  GENEROUS HITBOX.** Keystone Kapers measured the catch as
  `kcx = klx + 8 : hcx = hx + 8 : |kcx - hcx|`. Harry walks to x 253 before crossing a screen
  seam, so `hx + 8` wrapped to 5 and a Kop at the far LEFT read as five pixels from a crook
  walking off the far RIGHT — arresting him across the whole store. Nothing warns: both are
  plain 8-bit variables and the wrap is silent.
  - **The offset cancels in a difference**, so the fix is to delete it, not to widen the type:
    `|(a+k) - (b+k)| == |a - b|`. Any per-actor offset applied to BOTH sides before subtracting
    is dead arithmetic that can only introduce overflow.
  - The tell is a hit that fires at *maximum* separation rather than minimum — the wrap makes
    the two extremes of the range adjacent.
- **AN OVERRIDE THAT IGNORES THE STATE IT OVERRIDES WILL CONTRADICT IT IN FULL VIEW.** A "run
  away for a while" mode bolted on top of an enemy's normal AI beat the *flee* as well as the
  goal-seeking, so the crook held one heading regardless of where the player was and ran
  straight into him. Written as a **default the other rules can outrank** — cleared the moment
  the player appears on his floor — the same code reads as deliberate.
  - Its sibling: **a mode ended by a timer changes direction with nothing on screen to explain
    it.** End it on a world event instead (reaching a wall, the player arriving) so every
    change of heading has a visible cause.
  - And check WHERE the override sits. Placed below the movement it only reached the animation
    counter: the actor faced the right way, played the run cycle, and travelled zero pixels.

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

- **A SENTINEL VALUE THAT IS ALSO A VALID VALUE WILL EAT THE VALID ONE, AND ONLY HALF THE TIME.**
  Keystone Kapers stored a table of support-beam COLUMNS with 0 meaning "no more entries" — and
  column 0 is where the west end wall stands. Every west wall was silently skipped while the east
  wall at column 31 worked perfectly, so it read as intermittent rather than systematic, and the
  half that worked kept "proving" the mechanism was fine. Store `value + 1` (or use a separate
  count) whenever 0 is in the domain.
  - The previewer had the identical bug, so every render agreed with the defect. **When a checker
    and the code are written from the same assumption, the checker cannot see the assumption.**
- **VERIFY GEOMETRY BY SAMPLING PIXELS, NOT BY LOOKING AT A SCALED SCREENSHOT.** Three separate
  "confirmations" in one session were wrong: a capture taken during a between-rounds message, a
  comparison of one floor's pillar columns against a bar carrying a *different* floor's beam tops,
  and a column index computed from an assumed 3× emulator scale when the window actually scales to
  fit and clips the right edge. A two-pixel detail does not survive eyeballing a 4× crop. Print the
  RGB at a computed coordinate, or simulate the draw from the data and print the resulting
  character codes.


### NES palette lesson: shared grey and separate HUD icons (2026-09-20)

The universal background colour need not be black. Keystone Kapers now shares
grey across its four background palettes, allowing blue counters beside grey
pillars and multiple skyline bands. Per-region palettes must preserve every
colour needed within their 16x16 attribute quadrants, including fixture outlines.
Audit HUD icons as well as text: reusing the HUD's black index for pink sky made
the reserve hats pink. They now use five otherwise unused OAM entries and the
black sprite palette, with explicit CHR ownership, title cleanup and count tests.
See the game's DESIGN section 15; older fixed-palette limitations are historical.


NES-specific pixel art can need a native 2bpp upload: the TMS ink/paper converter
can express only two colours on each 8-pixel row, while NES tiles can use all
four palette indices on that row. Keystone's generator now preconverts static
store art and uploads native tiles at setup; animated TMS-derived tiles keep
the old converter. This trades ROM for richer art without extra game RAM or
sprite usage. Keep the rendering-off native loader unreachable from gameplay.
