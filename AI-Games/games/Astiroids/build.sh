#!/usr/bin/env bash
#
# Build Astiroids (CVBasic) for the TI-99/4A.
#
#   compile (CVBasic) -> assemble (xas99) -> pack cartridge (linkticart)
#
# Output: src/astiroids_8.bin  -- load directly in Classic99 or js99er.
#
# Run from anywhere:   bash build.sh      (or ./build.sh after chmod +x)
#
# Everything runs with src/ as the working directory, so the intermediate
# .bin stays next to the tools that need it -- nothing has to be moved by hand.

CVBASIC_DIR="/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic"
XDT99_DIR="/cygdrive/c/Users/Howie/github.git/endlos99/xdt99"

NAME="astiroids"
CARTNAME="ASTIROIDS"          # shown on the TI cartridge menu (<=20 chars, uppercase)

# --- pick a Python 3 interpreter (xas99 + linkticart need it) ---
PY="python3"
command -v "$PY" >/dev/null 2>&1 || PY="python"

die() { echo "ERROR: $1" >&2; exit 1; }

# --- sanity: tools present ---
[ -f "$CVBASIC_DIR/cvbasic.exe"  ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$XDT99_DIR/xas99.py"       ] || die "xas99.py not found in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not found in $CVBASIC_DIR"

# --- work in the source directory ---
cd "$(dirname "$0")/src" || die "cannot find the src/ directory"
[ -f "$NAME.bas" ] || die "$NAME.bas not found in $(pwd)"

echo "[1/3] CVBasic compile   $NAME.bas -> $NAME.a99"
rm -f "$NAME.a99"
# The trailing-slash 4th arg is the library path where CVBasic reads
# cvbasic_9900_prologue.asm / _epilogue.asm. Without it, CVBasic looks in
# the current dir, fails to find them, and leaves a tiny broken stub.
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$NAME.bas" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

echo "[2/3] xas99 assemble    $NAME.a99 -> $NAME.bin"
rm -f "$NAME.bin"
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"
[ -s "$NAME.bin" ] || die "xas99 produced no/empty $NAME.bin"

echo "[3/3] linkticart pack   $NAME.bin -> ${NAME}_8.bin"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$NAME.bin" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

echo
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
