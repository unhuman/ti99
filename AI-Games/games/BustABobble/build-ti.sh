#!/usr/bin/env bash
#
# Build Puzzle Bobble (CVBasic) for the TI-99/4A.
#
#   cvbasic compile -> xas99 assemble -> linkticart pack -> BUSTABOB_8.bin
#
# Output: src/BUSTABOB_8.bin -- load in Classic99 or js99er.
#
# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. No pacing constant is needed (unlike Astiroids' -Dpacen):
# the main loop is a single WAIT per frame doing trivial work on both machines,
# so both run the same 60Hz NTSC tick rate natively.
#
#   ./build-ti.sh            -> BUSTABOB_8.bin,  the 30 arcade rounds
#   ./build-ti.sh --expert   -> BUSTAB2_8.bin,   the 50 generated ones
#   ./build-ti.sh --both     -> BUSTAB12_8.bin,  both, chosen on a select screen
#
# ONE ENGINE, THREE CARTS, each buildable on its own. The flag picks which level
# table is INCLUDEd -- levels.bas, levels2.bas, or the combined levels12.bas of 80
# -- so an engine fix reaches all three without being applied three times.
#
# The combined cart is still 32 KB and still ONE bank: 80 levels at 54 B is 4,320,
# and with the art and music tables that is 7,574 of 8,192.
#
# Disk names are capped at 8 characters by repo rule (CLAUDE.md 8), hence BUSTAB2
# and BUSTAB12 rather than BUSTABOBBLE2.
#
# On this machine, cvbasic.exe/xas99.py/linkticart.py have been flaky when run
# from the Bash tool's cygwin shell (missing shared libs / mixed path forms).
# If this script fails under bash, fall back to running the three stages
# directly from PowerShell -- see .claude/skills/build-cvbasic-game/SKILL.md.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

SRC="BUSTABOB.bas"          # one source; --expert only changes what it compiles
NAME="BUSTABOB"
CARTNAME="BUST-A-BOBBLE"
DEFS=""
EXPERT=0
BOTH=0
if [ "$1" = "--expert" ]; then
    NAME="BUSTAB2"
    CARTNAME="BUST-A-BOBBLE 2"
    DEFS="-DEXPERT=1"
    EXPERT=1
elif [ "$1" = "--both" ]; then
    NAME="BUSTAB12"
    CARTNAME="BUST-A-BOBBLE 1+2"
    DEFS="-DBOTH=1"
    BOTH=1
elif [ -n "$1" ]; then
    echo "ERROR: unknown option '$1' (--expert or --both)" >&2; exit 1
fi

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"

cd "$(dirname "$0")/src" || die "cannot find src/"

# ---------------------------------------------------------------- TRUNCATION GATE
# A plain CVBasic variable is 8-BIT and a CONST over 255 truncates -- both silently,
# and both produce a PLAUSIBLE WRONG VALUE rather than a failure, which is why this
# class ships. See TRUNCATION.md for every form and what each one has cost.
#
# These fail the build. Deliberate exceptions are marked TRUNCATION-OK in the
# offending line's own comment, so a gate nobody can silence never becomes a gate
# everybody ignores.
TRUNCPY="python3"; command -v "$TRUNCPY" >/dev/null 2>&1 || TRUNCPY="python"
"$TRUNCPY" ../../../tools/bigvar.py *.bas \
    || { echo "ERROR: 8-bit truncation -- see TRUNCATION.md 1a" >&2; exit 1; }
"$TRUNCPY" ../../../tools/bigconst.py *.bas \
    || { echo "ERROR: CONST over 255 -- see TRUNCATION.md 1b" >&2; exit 1; }
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/3] cvbasic    $SRC -> $NAME.a99   ${DEFS:-(arcade set)}"
rm -f "$NAME.a99"
# The forked cvbasic (unhuman/CVBasic) auto-defines a constant named after the
# machine, so --ti994a makes TI994A=1. This source's `#if TI994A` blocks are the
# BANK directives: the level data lives in ROM bank 1 on TI, while ColecoVision
# leaves TI994A undefined and keeps everything flat. No explicit -DTI994A is
# passed -- it would just "constant redefined" over the auto-define.
# The output is teed so the #info line below can be checked. `tee` would otherwise
# swallow the compiler's exit status, so read it back out of PIPESTATUS -- a failed
# compile that still left a partial .a99 would sail past the -s test alone.
"$CVBASIC_DIR/cvbasic.exe" --ti994a $DEFS "$SRC" "$NAME.a99" "$CVBASIC_DIR/" \
    2>&1 | tee "$NAME.log"
[ "${PIPESTATUS[0]}" = 0 ] || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

# PROVE THE FLAG ARRIVED, rather than trusting that we passed it. An undefined
# name in `#if` is silently FALSE in this compiler -- no error, no warning -- so a
# mistyped -DEXPRT=1 would pack the ARCADE levels into a cart called BUSTAB2 and
# nothing in the chain would say a word. Both branches of the source announce
# themselves with #info, so the compiler itself reports which one it took.
# (The message is one underscored token because #info prints only its first word.)
if [ "$BOTH" = 1 ]; then
    grep -q "BUILDING_BOTH_SETS" "$NAME.log" \
        || die "-DBOTH=1 never reached the source: the compiler took another branch"
elif [ "$EXPERT" = 1 ]; then
    grep -q "BUILDING_EXPERT_SET" "$NAME.log" \
        || die "-DEXPERT=1 never reached the source: the compiler took the ARCADE branch"
else
    grep -q "BUILDING_ARCADE_SET" "$NAME.log" \
        || die "expected the ARCADE branch; the compiler reported otherwise"
fi

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin / ${NAME}_b*.bin"
# DELETE THE OLD BANK FILES FIRST. linkticart appends every ${NAME}_b*.bin it
# finds, so one left over from a previous build is silently packed into the cart
# and inflates the page count (CLAUDE.md 3A).
rm -f "$NAME.bin" "${NAME}"_b*.bin
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"

# A program using BANK assembles to ${NAME}_b0.bin (the >6000..>FFFF image) plus
# one file per bank from b3 up; a flat one leaves a single ${NAME}.bin.
# linkticart wants the _b0 form so it picks the extra banks up.
if [ -s "${NAME}_b0.bin" ]; then
    FIRST="${NAME}_b0.bin"
else
    FIRST="$NAME.bin"
    [ -s "$FIRST" ] || die "xas99 produced no/empty $NAME.bin"
fi

# AUDIT THE LEVEL DATA BEFORE PACKING. A layout with bubbles that hang from
# nothing is not a build error and not a crash -- it surfaces sessions later as
# three different apparent bugs in the drop logic, and one round that cannot be
# won at all (DESIGN.md 16a). It costs a second to check, so it is checked every
# build. (we are inside src/ at this point, hence the relative path)
# The combined cart carries BOTH sets, so both get audited.
if [ "$BOTH" = 1 ]; then
    "$PY" ../assets/solvelevels.py --anchors \
        || die "arcade level data has unanchored bubbles -- see above"
    "$PY" ../assets/solvelevels.py --set expert --anchors \
        || die "expert level data has unanchored bubbles -- see above"
elif [ "$EXPERT" = 1 ]; then
    "$PY" ../assets/solvelevels.py --set expert --anchors \
        || die "expert level data has unanchored bubbles -- see above"
else
    "$PY" ../assets/solvelevels.py --anchors || die "level data has unanchored bubbles -- see above"
fi

echo "[3/3] linkticart $FIRST -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$FIRST" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

# AUDIT THE PACKED CART. linkticart silently discards anything past 24,336 bytes
# of the >A000 program image; the symptom is missing DATA, not a build error, and
# the raw image starts at >6000 so its total size is NOT the number to compare.
# This runs AFTER packing because it also proves the banked blocks round-trip
# into the cart -- in RALLY-X the banked path had no check at all, and that is how
# 229 bytes were cut off the end of the music with every tool reporting success.
echo
RCFLAG=""; [ "$EXPERT" = 1 ] && RCFLAG="--expert"; [ "$BOTH" = 1 ] && RCFLAG="--both"
"$PY" ../assets/romcheck.py "$NAME" $RCFLAG || die "romcheck FAILED -- the cart is truncated (see above)"

echo
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
