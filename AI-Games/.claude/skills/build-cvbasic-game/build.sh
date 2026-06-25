#!/usr/bin/env bash
#
# Build a CVBasic game for the TI-99/4A:
#   cvbasic compile  ->  xas99 assemble  ->  linkticart pack  ->  <name>_8.bin
#
# Usage:
#   bash build.sh <path/to/game.bas> ["CART NAME"]
#
# Example:
#   bash build.sh games/mspacman-cv-xb-port/src/mspac.bas "MS PACMAN"
#
# Output: <name>_8.bin next to the source -- load directly in Classic99 or js99er.
#
# Toolchain locations on this machine (override via env vars if they move):
CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
# Work under cygwin (/cygdrive/c/...) or Git Bash (/c/...): fall back to the
# /c/ form if the cygwin form doesn't resolve.
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

die() { echo "ERROR: $1" >&2; exit 1; }

SRC="$1"
[ -n "$SRC" ] || die "usage: build.sh <path/to/game.bas> [\"CART NAME\"]"
[ -f "$SRC" ] || die "source not found: $SRC"

# Derive program NAME (no dots -- a TI filename cannot contain '.') and work dir.
DIR="$(cd "$(dirname "$SRC")" && pwd)" || die "cannot resolve source directory"
BAS="$(basename "$SRC")"
NAME="${BAS%.*}"
# Cart label shown on the TI menu: <=20 chars, uppercase. Defaults to NAME.
CARTNAME="${2:-$(printf '%s' "$NAME" | tr '[:lower:]' '[:upper:]')}"

# xas99 + linkticart need Python 3.
PY="python3"; command -v "$PY" >/dev/null 2>&1 || PY="python"

# Sanity: tools present.
[ -f "$CVBASIC_DIR/cvbasic.exe"   ] || die "cvbasic.exe not in $CVBASIC_DIR (build it: see SKILL.md)"
[ -f "$XDT99_DIR/xas99.py"        ] || die "xas99.py not in $XDT99_DIR"
[ -f "$CVBASIC_DIR/linkticart.py" ] || die "linkticart.py not in $CVBASIC_DIR"

cd "$DIR" || die "cannot cd to $DIR"

echo "[1/3] cvbasic    $BAS -> $NAME.a99"
rm -f "$NAME.a99"
# The trailing-slash 4th arg is the CVBasic library path: it is where CVBasic
# reads cvbasic_9900_prologue.asm / _epilogue.asm. Omit it and CVBasic looks in
# the current dir, fails to find them, and leaves a tiny broken stub.
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$BAS" "$NAME.a99" "$CVBASIC_DIR/" \
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
echo "Build OK ->  $DIR/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
