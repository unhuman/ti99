#!/usr/bin/env bash
#
# Build Ms. Pac-Man (CVBasic) for ColecoVision.
#
#   compile (CVBasic, default target = Coleco) -> assemble+pack (gasm80) -> .rom
#
# Output: src/mspac.rom  -- load in CoolCV / blueMSX (ColecoVision).
#
# Same mspac.bas source as the TI-99 build. The maze is read straight from VRAM
# (VPEEK) with no RAM mirror, so the variables fit ColecoVision's 1KB RAM
# (~209 bytes). Nothing here is TI- vs Coleco-specific; only the back end differs
# (no --ti994a, and gasm80 instead of xas99+linkticart).

CVBASIC_DIR="/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic"
GASM80="/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe"

SRC="mspac.bas"     # canonical source (shared with the TI build)
NAME="mspac"        # output base name (dot-free, lowercase)
ASM="${NAME}_col.asm"
ROM="${NAME}.rom"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/2] CVBasic (Coleco)  $SRC -> $ASM"
rm -f "$ASM"
"$CVBASIC_DIR/cvbasic.exe" "$SRC" "$ASM" "$CVBASIC_DIR/" \
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
