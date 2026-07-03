#!/usr/bin/env bash
#
# Build Ms. Pac-Man (CVBasic) for the TI-99/4A.
#
#   cvbasic compile  ->  xas99 assemble  ->  linkticart pack  ->  mspac_8.bin
#
# This mirrors .claude/skills/build-cvbasic-game/build.sh but adds -Dhz=24,
# a REQUIRED build-time constant (see mspac.bas top-of-file comment): the
# main loop and every frame-counted duration/movement rate in the game are
# scaled from hz, the TI-99's measured native main-loop rate (24 ticks/sec).
# ColecoVision uses -Dhz=60 (build-coleco.sh). Omitting -Dhz fails LOUDLY at
# compile time ("not a constant expression in CONST"), not silently at
# runtime -- so don't build mspac.bas with the generic shared skill script,
# which doesn't pass this flag.
#
# Output: src/mspac_8.bin -- load in Classic99 or js99er.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

SRC="mspac.bas"
NAME="mspac"
CARTNAME="MS PACMAN"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/3] cvbasic    $SRC -> $NAME.a99   (-Dhz=24, TI-99 native rate)"
rm -f "$NAME.a99"
"$CVBASIC_DIR/cvbasic.exe" --ti994a -Dhz=24 "$SRC" "$NAME.a99" "$CVBASIC_DIR/" \
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
