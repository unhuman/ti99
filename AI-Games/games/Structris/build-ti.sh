#!/usr/bin/env bash
#
# Build Structris (CVBasic) for the TI-99/4A.
#
#   cvbasic compile -> xas99 assemble -> linkticart pack -> STRUCTRS_8.bin
#
# Output: src/STRUCTRS_8.bin -- load in Classic99 or js99er.
#
# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. No build-time constants needed (unlike Astiroids'
# -Dpacen): the main loop is a single WAIT per frame doing trivial work on
# both machines, so both run the same 60Hz NTSC tick rate natively --
# no cross-platform pacing tricks required.
#
# On this machine, cvbasic.exe/xas99.py/linkticart.py have been flaky when run
# from the Bash tool's cygwin shell (missing shared libs / mixed path forms).
# If this script fails under bash, fall back to running the three stages
# directly from PowerShell -- see .claude/skills/build-cvbasic-game/SKILL.md.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

NAME="STRUCTRS"
CARTNAME="STRUCTRIS"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$NAME.bas" ] || die "$NAME.bas not found in $(pwd)"

echo "[1/3] cvbasic    $NAME.bas -> $NAME.a99"
rm -f "$NAME.a99"
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$NAME.bas" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin"
rm -f "$NAME.bin"
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"
[ -s "$NAME.bin" ] || die "xas99 produced no/empty $NAME.bin"

echo "[3/3] linkticart $NAME.bin -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$NAME.bin" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

echo
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
