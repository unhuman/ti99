#!/usr/bin/env bash
#
# Build RALLY-X (CVBasic) for the TI-99/4A.
#
#   cvbasic compile -> xas99 assemble -> linkticart pack -> RALLYX_8.bin
#
# Output: src/RALLYX_8.bin -- load in Classic99 or js99er.
#
# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. If this script fails under bash, run the three stages
# from PowerShell -- see .claude/skills/build-cvbasic-game/SKILL.md.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
XDT99_DIR="${XDT99_DIR:-/cygdrive/c/Users/Howie/github.git/endlos99/xdt99}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -d "$XDT99_DIR" ]   || XDT99_DIR="${XDT99_DIR/#\/cygdrive\/c\//\/c\/}"

NAME="RALLYX"
CARTNAME="RALLY-X"

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

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin / ${NAME}_b*.bin"
rm -f "$NAME.bin" "${NAME}"_b*.bin
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"

# BANK-using programs emit ${NAME}_b0.bin.. (fixed area b0-b2, banks b3+);
# non-banked programs emit a single $NAME.bin. linkticart wants the _b0 form
# to pick up the extra banks. The fixed area caps at 24,336 bytes either way.
if [ -s "${NAME}_b0.bin" ]; then
    FIRST="${NAME}_b0.bin"
else
    FIRST="$NAME.bin"
    [ -s "$FIRST" ] || die "xas99 produced no/empty $NAME.bin"
    SZ=$(stat -c%s "$FIRST" 2>/dev/null || wc -c < "$FIRST")
    [ "$SZ" -le 24336 ] || die "$FIRST is $SZ bytes > 24336 -- linkticart would silently truncate; move data/code into BANKs"
fi

echo "[3/3] linkticart $FIRST -> ${NAME}_8.bin   ('$CARTNAME')"
rm -f "${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$FIRST" "${NAME}_8.bin" "$CARTNAME" \
    || die "linkticart failed"
[ -s "${NAME}_8.bin" ] || die "linkticart produced no/empty ${NAME}_8.bin"

# AUDIT THE PACKED CART. The guard above only covers the NON-banked path; a
# BANKED build had no check at all, and that is exactly how 229 bytes were
# cut off the end of the music with every tool in the chain reporting
# success. romcheck.py re-derives the fixed-area usage from the binary and
# proves the at-risk data blocks survived into the cart.
echo
"$PY" "../assets/romcheck.py" || die "romcheck FAILED -- the cart is truncated (see above)"

echo
echo "Build OK ->  $(pwd)/${NAME}_8.bin"
echo "Load it in Classic99 or js99er."
