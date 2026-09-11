#!/usr/bin/env bash
#
# Build Keystone Kapers for the TI-99/4A.
#
#   cvbasic --ti994a  ->  xas99  ->  linkticart  ->  src/KEYSTONE_8.bin
#
# Same source as build-coleco.sh; only the toolchain differs. No pacing constant
# is needed: the loop is one WAIT per frame doing O(1) work per actor on both
# machines, so both run the same 60 Hz NTSC tick natively.
#
# This used to say the toolchain was "flaky under the cygwin shell" and to fall
# back to PowerShell. It was not flaky; see the PATH and cygpy notes below for
# what was actually wrong and what fixes it.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

SRC="KEYSTONE.bas"
NAME="KEYSTONE"
CARTNAME="KEYSTONE KAPERS"   # the TI menu entry; not a filename, so it
                            # is not bound by the 10-char disk limit
CAP=24336                   # 3 loader pages x 8112 bytes

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

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

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

# ---------------------------------------------------------------- TRUNCATION GATE
# A plain CVBasic variable is 8-BIT and a CONST over 255 truncates -- both silently,
# and both produce a PLAUSIBLE WRONG VALUE rather than a failure, which is why this
# class ships. See TRUNCATION.md. Deliberate exceptions are recorded in
# tools/truncation-accepted.txt, so a gate nobody can silence never becomes a gate
# everybody ignores.
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

# A GOSUB left by GOTO never pops its return address. Invisible on the TI's 7 KB
# of stack; on ColecoVision's 1 KB it walks down into the variables.
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

# AND THE CART'S ART, HITBOX AND THE JUMP ARC ARE THREE NUMBERS IN THREE FILES.
# checkball.py is about BALLS -- a ball's hitbox comes from its bounce arc, not
# from its sprite -- so nothing was watching the obstacles whose height is a
# constant. Raising the cart from 8 px to 12 is exactly the edit this guards.
"$TRUNCPY" ../assets/checkcart.py > /dev/null \
    || die "the cart's art, hitbox and jump arc disagree -- run assets/checkcart.py"

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
"$TRUNCPY" ../assets/checkride.py > /dev/null \
    || die "a rider's feet leave the escalator steps -- run assets/checkride.py"

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

# AND NOW THE CHECKS ON THE CHECKS. Every *_test.py above types out a defect
# that was really played, mutates the source to reintroduce it, and asserts its
# checker still says no.
#
# They were named in the comments above and RUN BY NOTHING, which is how a
# self-test rots: checklayout_test.py's HUD case died when the score field
# moved, was repaired, and then its PRINT AT case died the same way when the
# title screen moved down a row -- both times reporting SETUP ERROR into a
# terminal nobody was watching, while the suite still printed its other lines
# and passed them. A gate that guards a gate has to be on the same trigger as
# the thing it guards.
for t in ../assets/*_test.py; do
    "$TRUNCPY" "$t" > /dev/null \
        || die "$(basename "$t") fails -- its checker no longer rejects a defect
       that was actually played, or its mutation no longer applies. Run it."
done

echo "[1/3] cvbasic    $SRC -> $NAME.a99"
rm -f "$NAME.a99"
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$SRC" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin"
rm -f "$NAME.bin" "${NAME}"_b*.bin
cygpy "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"

FIRST="$NAME.bin"
[ -s "${NAME}_b0.bin" ] && FIRST="${NAME}_b0.bin"
[ -s "$FIRST" ] || die "xas99 produced no/empty $FIRST"

echo "[3/3] linkticart $FIRST -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
cygpy "$CVBASIC_DIR/linkticart.py" "$FIRST" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

# ONE MENU ENTRY. linkticart writes the cartridge header at the top of EVERY
# 8 KB loader page and then pads to a power of two, so the console lists this
# program four times -- and only the first is a real entry point, because the
# other three headers were copied wholesale and point into the middle of data.
# Selecting one of those runs from a bogus address. See assets/onemenuentry.py.
"$TRUNCPY" ../assets/onemenuentry.py "${NAME}_8.bin" \
    || die "could not reduce the cart to one menu entry"

# SIZE. linkticart SILENTLY DISCARDS anything past the cap; the symptom is
# missing data at the top of the image, not a build error. Measuring it is not
# a `wc -c` because a BANKED image is padded to fill the whole >A000 window --
# see assets/banksize.py, which handles both shapes.
echo
"$TRUNCPY" ../assets/banksize.py "$FIRST" "$CAP"     || die "the fixed area overflowed -- see the line above"

# AND THE DATA BANKS, WHICH HAD NO GUARD AT ALL. banksize.py above covers the
# FIXED area only. A bank overflow is completely silent -- xas99 and linkticart
# say nothing, the excess is dropped, and what goes missing is whatever sits
# nearest the end of the bank, normally a DATA block rather than code. Bank 1
# reached SIX spare bytes of 8,192 before anyone noticed, and nothing had been
# lost only by luck. This checks that each bank's LAST block -- the one an
# overflow eats first -- is really in the packed image, and reports free space
# as an early warning. assets/bankfill_test.py proves it rejects a truncated
# bank rather than only describing a healthy one.
"$TRUNCPY" ../assets/bankfill.py \
    || die "a data bank overflowed and lost its last block -- run assets/bankfill.py"
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."