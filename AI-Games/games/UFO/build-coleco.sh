#!/usr/bin/env bash
#
# Build UFO! for ColecoVision.
#
#   cvbasic (default target)  ->  gasm80  ->  src/ufo.rom
#
# Same source as build-ti.sh; only the toolchain differs (no --ti994a, and
# gasm80 instead of xas99 + linkticart).

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
GASM80="${GASM80:-/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -f "$GASM80" ]      || GASM80="${GASM80/#\/cygdrive\/c\//\/c\/}"

SRC="UFO.bas"
NAME="ufo"
ASM="${NAME}_col.asm"
ROM="${NAME}.rom"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

# ---------------------------------------------------------------- TRUNCATION GATE
# See TRUNCATION.md. Both forms are silent and both produce a plausible wrong
# value rather than a failure, so they fail the build instead.
TRUNCPY="python3"; command -v "$TRUNCPY" >/dev/null 2>&1 || TRUNCPY="python"
"$TRUNCPY" ../../../tools/bigvar.py *.bas \
    || die "8-bit truncation -- see TRUNCATION.md 1a"
"$TRUNCPY" ../../../tools/bigconst.py *.bas \
    || die "CONST over 255 -- see TRUNCATION.md 1b"

# THIS MATTERS MORE HERE THAN ON THE TI. A GOSUB left by GOTO never pops its
# return address; the TI has ~7 KB of stack to absorb it, ColecoVision has 1 KB
# total and the leak walks down into the variables.
"$TRUNCPY" ../../../tools/gosubtrace.py "$SRC" | grep -q "every GOSUB target reaches a return" \
    || die "a GOSUB target cannot reach a RETURN -- see CLAUDE.md 3A"

# A PRINT AT that runs past column 31 wraps onto the next row, and a HUD VPOKE
# can land inside a label some other routine printed. Both are arithmetic on a
# bare offset, so neither is visible in the source -- the 838 screen shipped the
# difficulty digit into the middle of the word DIFFICULTY.
"$TRUNCPY" ../assets/checklayout.py > /dev/null     || die "screen layout: run assets/checklayout.py to see it"

echo "[1/2] cvbasic (Coleco)  $SRC -> $ASM"
rm -f "$ASM"
"$CVBASIC_DIR/cvbasic.exe" "$SRC" "$ASM" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$ASM" ] || die "CVBasic produced no/empty $ASM"

echo "[2/2] gasm80 assemble   $ASM -> $ROM"
rm -f "$ROM"
"$GASM80" "$ASM" -o "$ROM" || die "gasm80 failed"
[ -s "$ROM" ] || die "gasm80 produced no/empty $ROM"

echo
echo "ROM: $(wc -c < "$ROM") bytes"
echo "Build OK ->  $(pwd)/$ROM"
echo "Load it in CoolCV or blueMSX (ColecoVision)."
