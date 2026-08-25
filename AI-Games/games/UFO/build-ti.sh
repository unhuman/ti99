#!/usr/bin/env bash
#
# Build UFO! for the TI-99/4A.
#
#   cvbasic --ti994a  ->  xas99  ->  linkticart  ->  src/UFO_8.bin
#
# Same source as build-coleco.sh; only the toolchain differs. No pacing constant
# is needed: the loop is one WAIT per frame doing O(1) work per actor on both
# machines, so both run the same 60 Hz NTSC tick natively.
#
# On this machine cvbasic.exe/xas99.py have been flaky under the cygwin shell
# (missing shared libs / mixed path forms). If this fails under bash, run the
# three stages from PowerShell -- see .claude/skills/build-cvbasic-game/SKILL.md.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

SRC="UFO.bas"
NAME="UFO"
CARTNAME="UFO"
CAP=24336                   # 3 loader pages x 8112 bytes

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

# ---------------------------------------------------------------- TRUNCATION GATE
# A plain CVBasic variable is 8-BIT and a CONST over 255 truncates -- both silently,
# and both produce a PLAUSIBLE WRONG VALUE rather than a failure, which is why this
# class ships. See TRUNCATION.md. Deliberate exceptions are recorded in
# tools/truncation-accepted.txt, so a gate nobody can silence never becomes a gate
# everybody ignores.
TRUNCPY="python3"; command -v "$TRUNCPY" >/dev/null 2>&1 || TRUNCPY="python"
"$TRUNCPY" ../../../tools/bigvar.py *.bas \
    || die "8-bit truncation -- see TRUNCATION.md 1a"
"$TRUNCPY" ../../../tools/bigconst.py *.bas \
    || die "CONST over 255 -- see TRUNCATION.md 1b"

# A GOSUB left by GOTO never pops its return address. Invisible on the TI's 7 KB
# of stack; on ColecoVision's 1 KB it walks down into the variables.
"$TRUNCPY" ../../../tools/gosubtrace.py "$SRC" | grep -q "every GOSUB target reaches a return" \
    || die "a GOSUB target cannot reach a RETURN -- see CLAUDE.md 3A"

echo "[1/3] cvbasic    $SRC -> $NAME.a99"
rm -f "$NAME.a99"
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$SRC" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin"
rm -f "$NAME.bin" "${NAME}"_b*.bin
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"

FIRST="$NAME.bin"
[ -s "${NAME}_b0.bin" ] && FIRST="${NAME}_b0.bin"
[ -s "$FIRST" ] || die "xas99 produced no/empty $FIRST"

echo "[3/3] linkticart $FIRST -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$FIRST" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

# SIZE. linkticart SILENTLY DISCARDS anything past the cap; the symptom is
# missing data at the top of the image, not a build error. The raw -b image
# starts at >6000 and the program at >A000, so subtract 16384 before comparing --
# getting that wrong reads as a 6 KB overflow on a build with 10 KB free.
RAW=$(wc -c < "$FIRST")
USED=$((RAW - 16384))
echo
if [ "$USED" -gt "$CAP" ]; then
    die "program image is $USED bytes, $((USED - CAP)) OVER the ${CAP}-byte cap --
     linkticart has silently discarded the top of it"
fi
echo "Fixed area:  $USED / $CAP bytes   ($((CAP - USED)) free)"
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
