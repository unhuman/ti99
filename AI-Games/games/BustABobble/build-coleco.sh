#!/usr/bin/env bash
#
# Build Puzzle Bobble (CVBasic) for ColecoVision.
#
#   cvbasic (default target = Coleco) -> gasm80 -> bustabob.rom
#
# Output: src/bustabob.rom -- load in CoolCV / blueMSX (ColecoVision).
#
# Same .bas source as the TI-99 build (build-ti.sh); only the toolchain
# differs (no --ti994a, and gasm80 instead of xas99+linkticart). No
# build-time constants needed: the main loop is a single WAIT per frame
# doing trivial work on both machines, so both run the same 60Hz NTSC tick
# rate natively -- unlike Astiroids, there's no per-frame arcade-physics load
# that would make one machine's loop spill past a single vblank.

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
GASM80="${GASM80:-/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -f "$GASM80" ]      || GASM80="${GASM80/#\/cygdrive\/c\//\/c\/}"

# Two carts from one source, exactly as build-ti.sh does it:
#   ./build-coleco.sh            -> bustabob.rom, the 30 arcade rounds
#   ./build-coleco.sh --expert   -> bustab2.rom,  the 50 generated ones
SRC="BUSTABOB.bas"      # canonical source (shared with the TI build)
NAME="bustabob"          # output base name (dot-free, lowercase)
DEFS=""
EXPERT=0
if [ "$1" = "--expert" ]; then
    NAME="bustab2"
    DEFS="-DEXPERT=1"
    EXPERT=1
elif [ "$1" = "--both" ]; then
    NAME="bustab12"
    DEFS="-DBOTH=1"
elif [ -n "$1" ]; then
    echo "ERROR: unknown option '$1' (--expert or --both)" >&2; exit 1
fi
ASM="${NAME}_col.asm"
ROM="${NAME}.rom"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/2] CVBasic (Coleco)  $SRC -> $ASM"
rm -f "$ASM"
# No --ti994a: ColecoVision is CVBasic's default target. The trailing-slash 3rd
# path arg is the library dir (prologue/epilogue), same requirement as the TI build.
"$CVBASIC_DIR/cvbasic.exe" $DEFS "$SRC" "$ASM" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$ASM" ] || die "CVBasic produced no/empty $ASM"

echo "[2/2] gasm80 assemble   $ASM -> $ROM"
rm -f "$ROM"
"$GASM80" "$ASM" -o "$ROM" \
    || die "gasm80 failed"
[ -s "$ROM" ] || die "gasm80 produced no/empty $ROM"

echo
echo "Build OK ->  $(pwd)/$ROM"
echo "Load it in CoolCV or blueMSX (ColecoVision)."
