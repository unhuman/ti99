#!/usr/bin/env bash
#
# Build Hard Hat Mack (CVBasic) for the TI-99/4A.
#
#   cvbasic compile -> xas99 assemble -> linkticart pack -> HARDHAT_8.bin
#
# Output: src/HARDHAT_8.bin -- load in Classic99 or js99er.
#
# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. Uses the forked cvbasic (unhuman/CVBasic), which
# auto-defines TI994A=1 under --ti994a for any `#if TI994A` splits.
#
# SIZE GUARD: a single-bank TI cart hard-caps at 24,336 bytes of program
# (linkticart pads to 32K and silently TRUNCATES anything past the cap,
# which shows up as impossible-looking runtime corruption, not an error).
# This script measures HARDHAT.bin and fails loudly if it exceeds the cap,
# and reports free bytes on every successful build.
#
# On this machine, cvbasic.exe/xas99.py/linkticart.py have been flaky when run
# from the Bash tool's cygwin shell (missing shared libs / mixed path forms).
# If this script fails under bash, fall back to running the three stages
# directly from PowerShell -- see .claude/skills/build-cvbasic-game/SKILL.md.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

NAME="HARDHAT"
CARTNAME="HARD HAT MACK"
CAP=24336

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

# The raw .bin carries a fixed 16,384-byte base offset (cart layout);
# the PROGRAM is what counts against the 24,336-byte cap (3 banks of
# 8,112 payload bytes each -- linkticart puts an 80-byte header at the
# start of every 8K bank).
RAW=$(wc -c < "$NAME.bin")
SIZE=$((RAW - 16384))
FREE=$((CAP - SIZE))
BANKS=$(( (SIZE + 8111) / 8112 ))
if [ "$BANKS" -ge 3 ]; then
    echo "NOTE: program uses bank 3 (> 16,224 B). Classic99 QI399.087's"
    echo "      '-rom' command line mis-loads 3-bank carts (black screen)"
    echo "      even though the cart image is correct -- load it via the"
    echo "      Cartridge menu (or js99er) to runtime-test."
fi
if [ "$SIZE" -gt "$CAP" ]; then
    die "SIZE OVERFLOW: $NAME.bin is $SIZE bytes, cap is $CAP ($((SIZE - CAP)) over). linkticart would silently truncate -- shrink the program (see DESIGN.md cut list)."
fi

echo "[3/3] linkticart $NAME.bin -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$NAME.bin" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

echo
echo "Build OK ->  $(pwd)/${NAME}_8.bin   (program $SIZE bytes, $FREE free of $CAP)"
echo "Load it in Classic99 or js99er."
