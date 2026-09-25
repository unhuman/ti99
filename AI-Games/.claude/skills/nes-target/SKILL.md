---
name: nes-target
description: >-
  The NES porting contract for this repo's CVBasic games (cvbasic --nes): DEFINE is
  unimplemented but CHR-RAM is writable via the ASM statement, the 32x30 name table and
  the matching +24 px sprite offset, per-character colour through the second bitplane
  instead of the attribute table, SPRHID 240, the ~100-byte-per-frame PPUBUF vblank
  budget and the whole-screen jump it causes when overrun, the SOUND/APU shim, NES RAM
  mirroring and the array-overrun black screen, plus the palette and forced-blank
  lessons. Load this when building, debugging or extending an NES build
  (games/KeystoneKapers/build-nes.sh) or when touching any #if NES branch. It is NOT
  needed for the TI-99/4A or ColecoVision targets.
---

# NES target (CVBasic `--nes`)

Moved out of the always-loaded `CLAUDE.md` so it loads only for NES work. Everything here is a
hard-won failure contract: none of it is derivable from the code, and each item cost a session.
The TMS-target rules in `CLAUDE.md` §3A still apply -- this file is additive.

## The porting contract

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


### iNES audio setting mismatch (2026-09-20)

On this Windows iNES installation, saved `UseSound=0` can coexist with
`SndRate=22050`: the menu shows 22 kHz selected while synthesis is silent.
After launching, explicitly select No Sound then 22 kHz to initialize audio;
checking the menu selection or Windows mixer volume alone does not verify it.
`tools/keystone-dev.ps1 LaunchNES` does this and enables audio while inactive.
Use a positive-control sound when measuring output: silent diagnostic ROMs
alone do not establish an APU-code failure.
A nonzero meter establishes signal, not audible balance or successful playback
for the user. Do not report a listening complaint resolved solely from that test.

### NES forced-blank redraws (Keystone, 2026-09-21)

A full redraw may copy directly while rendering is disabled, but the NMI must
also leave PPUADDR/PPUDATA/scroll alone throughout the transaction. Keystone's
local nesfast.py runtime hooks reserve mode bit 7, preserving the existing
flicker bit, controller polling and FRAME updates. Outside that mode the normal
vblank queue and its budgets remain mandatory. The hooks fail on changed runtime
anchors; they do not modify the shared compiler. Park PPUADDR outside palette
space after direct writes: a palette address can colour the forced-blank screen.
Keep a blank backdrop until the completed screen is committed at vblank.
