#!/usr/bin/env bash
#
# Build Keystone Kapers for the NES / Famicom.
#
#   cvbasic --nes  ->  gasm80 (6502 mode)  ->  src/keystone.nes
#
# Same source as build-ti.sh and build-coleco.sh; only the toolchain differs.
#
# GASM80 IS NOT MISNAMED HERE. Despite the name it assembles 6502 as well as
# Z80 -- it prints "Expanding jumps as needed for 6502" on this input -- and
# CVBasic's --nes target emits `CPU 6502`. No separate 6502 assembler is
# needed, and reaching for one is a wrong turn.
#
# AND IT EXITS 0 WITH ERRORS ON STDOUT. `gasm80 ... || die` therefore never
# fires: a run with forty undefined labels "succeeded", left a 16-byte file,
# passed the `[ -s "$ROM" ]` test and printed Build OK. That is the worst
# possible state -- a broken cart reported as a good one -- so the error
# output is grepped and the ROM size is sanity-checked instead.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
GASM80="${GASM80:-/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -f "$GASM80" ]      || GASM80="${GASM80/#\/cygdrive\/c\//\/c\/}"

SRC="KEYSTONE.bas"
NAME="keystone"
ASM="${NAME}_nes.asm"
ROM="${NAME}.nes"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

# PYTHON. Prefer one on PATH; fall back to the Cygwin interpreter this machine
# actually has. Git Bash has NEITHER `python3` NOR `python`, and when the gates
# below ran with a missing interpreter they still failed the build -- reporting
# "8-bit truncation", the gate's own message, rather than "no python". A gate
# that cannot run must say so, not accuse the source.
find_py() {
    for pc in python3 python /c/cygwin64/bin/python3.9.exe \
              /cygdrive/c/cygwin64/bin/python3.9.exe; do
        if command -v "$pc" >/dev/null 2>&1; then echo "$pc"; return 0; fi
    done
    return 1
}
PY="$(find_py)" || die "no python interpreter found (tried python3, python, Cygwin 3.9)"
TRUNCPY="$PY"

# CVBASIC.EXE IS A CYGWIN BINARY AND GIT BASH SHADOWS ITS RUNTIME. Git Bash is
# MSYS2 and puts its own msys-2.0.dll first, so running cvbasic.exe from here
# died with
#
#   cvbasic.exe: error while loading shared libraries: ?: cannot open shared
#   object file: No such file or directory
#
# -- exit 127, no line number, nothing to do with the program being compiled.
# The same command from PowerShell worked, which made it read as general
# flakiness in the toolchain rather than as one directory in the wrong order.
for cyg in /c/cygwin64/bin /cygdrive/c/cygwin64/bin; do
    [ -d "$cyg" ] && PATH="$cyg:$PATH" && break
done
export PATH

# AND THE SECOND HALF OF THE SAME PROBLEM: Git Bash rewrites an absolute POSIX
# ARGUMENT into C:/... before handing it to a native program, and Cygwin's
# python does not read that as absolute -- it joins it onto the current
# directory and reports "can't open file <cwd>/C:/Users/...". Passing the
# /cygdrive form with MSYS2's rewriting switched off is the form both
# understand. Only the tool scripts outside this tree are affected; every
# other argument in this file is relative and needs none of it.
PYCYG=0
[ "$("$PY" -c 'import sys; print(sys.platform)' 2>/dev/null)" = "cygwin" ] && PYCYG=1
cygpy() {
    _s="$1"; shift
    if [ "$PYCYG" = 1 ]; then
        case "$_s" in /c/*) _s="/cygdrive$_s";; esac
        MSYS2_ARG_CONV_EXCL='*' "$PY" "$_s" "$@"
    else
        "$PY" "$_s" "$@"
    fi
}

# ---------------------------------------------------------------- TRUNCATION GATE
# See TRUNCATION.md. Both forms are silent and both produce a plausible wrong
# value rather than a failure, so they fail the build instead.
# REGENERATE THE ART FIRST, ALWAYS. art.bas and store.bas are generated, and
# store.bas places characters by code out of genart.py's table -- so running
# one generator without the other leaves the templates pointing at cell
# numbers that have moved. That does not fail the build: it draws the wrong
# characters, which looks like broken artwork and sends you hunting in the
# wrong file. Cheap to make impossible.
#
# And CLEAR THE BYTECODE CACHE first. genstore.py and the checkers import
# genart.py, and Python decides a cached .pyc is current by comparing whole
# SECONDS -- so an edit and a run inside the same second reuse the stale
# module and every downstream file is generated from the OLD art. Observed:
# a checker kept reporting a value that had just been changed.
echo "[0/3] generate   art.bas + store.bas"
rm -rf ../assets/__pycache__
"$TRUNCPY" ../assets/genart.py > /dev/null   || die "genart.py failed"
"$TRUNCPY" ../assets/genstore.py > /dev/null || die "genstore.py failed"
"$TRUNCPY" ../assets/gentitle.py > /dev/null || die "gentitle.py failed"

"$TRUNCPY" ../../../tools/bigvar.py *.bas \
    || die "8-bit truncation -- see TRUNCATION.md 1a"
"$TRUNCPY" ../../../tools/bigconst.py *.bas \
    || die "CONST over 255 -- see TRUNCATION.md 1b"

# A raw name-table address that nobody gated points INSIDE THE PATTERN TABLE on
# this machine, so it corrupts artwork rather than drawing in the wrong place.
# The HUD's score and timer shipped exactly that way.
"$TRUNCPY" ../assets/checknes.py \
    || die "an ungated raw name-table address -- run assets/checknes.py"

# THIS MATTERS MORE HERE THAN ON THE TI. A GOSUB left by GOTO never pops its
# return address; the TI has ~7 KB of stack to absorb it, ColecoVision has 1 KB
# total and the leak walks down into the variables.
"$TRUNCPY" ../../../tools/gosubtrace.py "$SRC" | grep -q "every GOSUB target reaches a return" \
    || die "a GOSUB target cannot reach a RETURN -- see CLAUDE.md 3A"

# A PRINT AT that runs past column 31 wraps onto the next row, and a HUD VPOKE
# can land inside a label some other routine printed. Both are arithmetic on a
# bare offset, so neither is visible in the source -- UFO's 838 screen shipped its
# difficulty digit into the middle of the word DIFFICULTY. This game's checker
# also refuses to pass on a drawing routine missing from its screen map, and
# assets/checklayout_test.py proves it fails on all four defects it claims.
"$TRUNCPY" ../assets/checklayout.py > /dev/null     || die "screen layout: run assets/checklayout.py to see it"

# The beach ball's avoidability is the product of FOUR numbers chosen together
# -- jump apex, ducked height, hitbox inset, arc apexes -- and any one of them
# can be edited alone by someone who does not know about the other three. A
# one-pixel hole does not crash and does not show in a screenshot; it presents
# as an occasional unfair hit, which is indistinguishable from bad luck.
"$TRUNCPY" ../assets/checkball.py > /dev/null \
    || die "a beach-ball height is unavoidable -- run assets/checkball.py"

# A chase resolves on PATH / SPEED, not on speed. Kelly used to be 1.5x faster
# than Harry and STILL lose the race to the roof by 11 seconds, because Harry's
# route is barely half as long -- and neither speed constant shows that. This
# walks both routes out of the real constants and fails if the chase cannot be
# won on foot, if Harry is not slower than Kelly, or if he can no longer escape
# inside the round timer.
"$TRUNCPY" ../assets/checkchase.py > /dev/null \
    || die "the chase does not resolve -- run assets/checkchase.py"
"$TRUNCPY" ../assets/checklevels.py > /dev/null     || die "the Krook progression has drifted -- run assets/checklevels.py"
# TWO HAZARDS ON ONE FLOOR MUST BE FAR ENOUGH APART TO LAND BETWEEN.
# Every other check here asks about ONE hazard: checkball sweeps a single
# ball against the jump and the crouch, checklevels pins when the second
# one arrives. Neither can see whether a PAIR is takeable. The gap shipped
# at 46 px west of the lift and 70 px east of it, against the 168 a jump
# eats -- so from Krook 6 there was no screen where the two could both be
# jumped. checkspace_test.py proves this rejects all five of those.
"$TRUNCPY" ../assets/checkspace.py > /dev/null \
    || die "two hazards on a floor are too close -- run assets/checkspace.py"
"$TRUNCPY" ../assets/checkstruct.py > /dev/null \
    || die "an erase routine clears the outside wall's cap -- run assets/checkstruct.py"
# A TMS cell has an ink and a paper; the NES shim maps BOTH through nes_inkmap
# onto one of four palette indices, and when both land on the same index the
# cell is a solid block with the artwork gone. Moving any colour in that table
# is a two-sided edit -- it separates one pair and can merge another -- and
# nothing else in this build would notice the second half. checkink_test.py
# proves this rejects two maps that were really written here.
"$TRUNCPY" ../assets/checkink.py > /dev/null     || die "a character collapses to one colour on NES -- run assets/checkink.py"

"$TRUNCPY" ../assets/checkbands.py > /dev/null \
    || die "an actor colour band overlaps -- run assets/checkbands.py"
# A run cycle whose beats are the SAME PICTURE has fewer frames than it
# looks like, and every other check here passes on it: the right patterns
# are loaded at the right addresses and drawn on the right beats. Kelly
# shipped a four-beat cycle whose beats 1 and 3 differed by 4 px, and
# Harry's legs a set of four in which two were byte-identical.
"$TRUNCPY" ../assets/checkanim.py > /dev/null \
    || die "a run cycle has repeated beats -- run assets/checkanim.py"
"$TRUNCPY" ../assets/checkesc.py > /dev/null \
    || die "an escalator animation phase is torn -- run assets/checkesc.py"
"$TRUNCPY" ../assets/checkscan.py > /dev/null \
    || die "a radar row is the wrong colour -- run assets/checkscan.py"
"$TRUNCPY" ../assets/checkchars.py > /dev/null \
    || die "a hand-written character number is stale -- run assets/checkchars.py"

# NO UPLOAD MAY LAND IN CODES ANOTHER TABLE OWNS. Harry's standing pose was
# briefly made resident at "176..207, a 32-code gap nothing else uses" -- a gap
# that does not exist: it is HLLEG1..4 and HLLEGS1..4, his own left-facing legs.
# The art loaded correctly, at the address it was given, and running LEFT drew
# standing art in the leg slots as a detached striped block below his feet.
# Nothing failed, and checkchars PASSED because the check added with it compared
# the constant against the very upload that carried the mistake. checkpat.py
# compares both against genart instead, covers DEFINE CHAR/SPRITE as well as the
# NES uploads, and lists the deliberate borrows by name; checkpat_test.py proves
# it rejects the overwrite that shipped plus three near misses.
"$TRUNCPY" ../assets/checkpat.py > /dev/null \
    || die "an upload overwrites another table's art -- run assets/checkpat.py"

# A MESSAGE BOX THAT IS NOT COLOURED IS A READABLE MESSAGE IN THE WRONG
# PALETTE, which no layout, overflow or collision check can see. The
# colouring was written out by hand at each site and GOT HIM! was missed, so
# it kept the store's gold on green while every other box went white on blue.
# checkmsg.py checks the rule against the PRODUCER instead -- anything that
# draws a msg_* list must flush before it and call nes_boxatt after it -- and
# is mutation-tested against that exact miss plus two neighbours.
"$TRUNCPY" ../assets/checkmsg.py > /dev/null \
    || die "a message box is drawn without its colours -- run assets/checkmsg.py"
"$TRUNCPY" ../assets/checkride.py > /dev/null \
    || die "a rider's feet leave the escalator steps -- run assets/checkride.py"

# THE NMI COPIES UNTIL THE DESCRIPTOR ENDS, NOT UNTIL VBLANK DOES, and the
# PPUADDR/PPUSCROLL restore that follows it re-points the PPU mid-frame if it
# runs late -- the whole picture jumps for that frame. PPUBUF also accumulates
# for a WHOLE loop pass, so the escalator's 96-byte upload flushes together
# with every radar poke the pass made unless a WAIT divides them. That was the
# escalator flash, reported over several sessions and misread as a sprite bug
# each time. checkvblank.py costs the descriptors against a 2273-cycle vblank
# and fails on any that cannot fit; checkvblank_test.py proves it rejects both
# forms that shipped the fault.
"$TRUNCPY" ../assets/checkvblank.py > /dev/null \
    || die "an NES vblank is overcommitted -- run assets/checkvblank.py"

# snd_off is a HAND-WRITTEN list of channels and counters, and it went stale
# twice without a word: the footstep moved to the noise channel and snd_off
# still named only 0-2, so a step ringing at a capture hissed through the whole
# bonus tally; and the prize arpeggio's counter was added later than the list,
# so a prize taken late in a round dinged over the start of the next one. Both
# were reported from play. This derives the required set from sfx_tick itself
# rather than keeping a second list that could go stale the same way, and it was
# run against the defective source first -- it failed on both.
"$TRUNCPY" ../assets/checksound.py > /dev/null \
    || die "a sound can outlive its round -- run assets/checksound.py"

# A flight is a diagonal and the jump's apex is 14 px, so an arc can fly OVER
# the three treads it could land on and then meet the riser of the fourth,
# which is above the apex -- passing from above the staircase to below it and
# landing on the floor underneath. Reported from play, and rare because it
# needs a launch inside a 40 px band. This sweeps every launch position on both
# flights, every animation phase, frame delta and jump direction; it EXECUTES
# the boarding rule parsed out of try_esc rather than a copy of it, and
# assets/checkjump_test.py proves it still rejects the rule that shipped the bug.
"$TRUNCPY" ../assets/checkjump.py > /dev/null \
    || die "a jump can pass through an escalator -- run assets/checkjump.py"

# AND NOW THE CHECKS ON THE CHECKS -- see the same block in build-ti.sh. These
# were named in comments and run by nothing, and two of checklayout_test.py's
# cases rotted into no-ops that way, each reporting SETUP ERROR to nobody.
for t in ../assets/*_test.py; do
    "$TRUNCPY" "$t" > /dev/null \
        || die "$(basename "$t") fails -- its checker no longer rejects a defect
       that was actually played, or its mutation no longer applies. Run it."
done

echo "[1/2] cvbasic (NES)  $SRC -> $ASM"
rm -f "$ASM"
_cvlog="$(mktemp)"
"$CVBASIC_DIR/cvbasic.exe" --nes "$SRC" "$ASM" "$CVBASIC_DIR/" 2>&1 | tee "$_cvlog"
_cvrc=${PIPESTATUS[0]}
# CVBasic PRINTS "Compilation finished for NES/Famicom" EVEN AFTER ERRORS, so
# that line means nothing on its own -- reading it as success is how this was
# first misdiagnosed as a link problem. The exit status is the truth, and the
# errors are worth counting because there is only ever one cause.
_ndef=$(grep -c "DEFINE isn't implemented for NES" "$_cvlog")
if [ "$_ndef" -gt 0 ]; then
    rm -f "$_cvlog"
    die "CVBasic's NES target does not implement DEFINE, and a DEFINE has reached
       the compiler $_ndef time(s) -- i.e. one is no longer behind its #if NES
       guard. Every DEFINE in this source has an #if NES branch that uploads the
       same art into CHR-RAM instead (see assets/nes_chr.asm); a new one needs
       the same treatment.

       The old note here said this target could not work at all. It can:
       $_ndef times -- DEFINE CHAR, DEFINE COLOR and DEFINE SPRITE, for the
       font, the store tiles, the title font, every sprite, and the escalator
       animation that rewrites patterns as it runs.

       THIS IS NOT A BUILD-SCRIPT PROBLEM AND NOT A LINK PROBLEM. On the NES
       character patterns live in CHR supplied with the cartridge, not uploaded
       at run time, so there is nothing for DEFINE to compile to. Getting this
       target working needs the art moved into CHR (and CHR-RAM for the parts
       that animate), not another flag here."
fi
rm -f "$_cvlog"
[ "$_cvrc" = 0 ] || die "CVBasic compile failed (see messages above)"
[ -s "$ASM" ] || die "CVBasic produced no/empty $ASM"

# AND NOW THAT THERE IS AN ASSEMBLY, CHECK THE ARRAYS FIT IN RAM. This is the
# one gate that cannot run before the compiler, because it needs the addresses
# the ALLOCATOR chose. CVBasic counts RAM against a notional total and will
# happily place an array past $07FF; the NES mirrors $0800 onto $0000, so the
# overrun lands in the zero page and the machine dies before it draws anything.
# Black screen, no error, correct-size ROM. See assets/checknesram.py.
"$TRUNCPY" ../assets/checknesram.py > /dev/null \
    || die "an array runs past the end of NES RAM -- run assets/checknesram.py"

# THE APU SHIM. CVBasic's 6502 codegen calls sn76489_freq/_vol/_control for
# every SOUND statement and the NES prologue defines none of them -- the NES
# has a 2A03 APU, not an SN76489. assets/nes_apu.asm supplies them.
#
# IT IS INSERTED BEFORE `rom_end:`, NOT APPENDED. The generated file ends with
# `times $fffa-$ db $ff`, the three 6502 vectors and the CHR data, so the
# address space is already full at the bottom; anything appended lands after
# the vectors and is never assembled into the cart.
[ -f ../assets/nes_apu.asm ] || die "assets/nes_apu.asm is missing"
[ -f ../assets/nes_chr.asm ] || die "assets/nes_chr.asm is missing"
grep -q "^rom_end:" "$ASM" || die "no rom_end: label in $ASM -- CVBasic's output
       layout has changed and the APU shim has nowhere safe to go"
# MSYS2_ARG_CONV_EXCL IS NOT OPTIONAL HERE. Git Bash rewrites an argument that
# looks like an absolute POSIX path before handing it to a native program, and
# an awk PATTERN starts with a slash -- so /^rom_end:/ was handed to gawk as
# C:\Program Files\Git\^rom_end;\ and died with a syntax error. The same
# rewriting turns `sed '/pattern/d'` into "unknown command: 'C'".
MSYS2_ARG_CONV_EXCL='*' awk -v apu=../assets/nes_apu.asm -v chr=../assets/nes_chr.asm '
    /^rom_end:/ && !done {
        while ((getline l < apu) > 0) print l; close(apu)
        while ((getline l < chr) > 0) print l; close(chr)
        done = 1
    }
    { print }' "$ASM" > "$ASM.tmp" && mv "$ASM.tmp" "$ASM"
grep -q "^sn76489_freq:" "$ASM" || die "the APU shim did not make it into $ASM"
grep -q "^nes_chrup:" "$ASM" || die "the CHR-RAM uploader did not make it into $ASM"

echo "[2/2] gasm80 assemble   $ASM -> $ROM"
rm -f "$ROM"
_asmlog="$(mktemp)"
"$GASM80" "$ASM" -o "$ROM" 2>&1 | tee "$_asmlog"
# THE EXIT STATUS IS USELESS -- see the note at the top. Read the output.
if grep -q "^Error:" "$_asmlog"; then
    _n=$(grep -c "^Error:" "$_asmlog")
    echo
    echo "  distinct undefined labels:"
    grep -o "undefined label '[A-Za-z0-9_]*'" "$_asmlog" | sort | uniq -c | sort -rn \
        | sed 's/^/    /'
    rm -f "$_asmlog"
    die "gasm80 reported $_n error(s) -- the ROM is NOT usable"
fi
rm -f "$_asmlog"
[ -s "$ROM" ] || die "gasm80 produced no/empty $ROM"
# An iNES image is a 16-byte header plus at least one 16 KB PRG bank. Anything
# smaller is the header alone, which is what a failed assemble leaves behind.
_sz=$(wc -c < "$ROM")
[ "$_sz" -gt 16400 ] || die "$ROM is only $_sz bytes -- that is the iNES header
       with little or nothing behind it, i.e. the assemble did not really run"

echo
echo "ROM: $_sz bytes"
echo "Build OK ->  $(pwd)/$ROM"
echo "Load it in Mesen, FCEUX or Nestopia (NES/Famicom)."
