#!/usr/bin/env bash
#
# Build Astiroids (CVBasic) for ColecoVision.
#
#   compile (CVBasic, default target = Coleco) -> assemble+pack (gasm80) -> .rom
#
# Output: src/astiroids.rom  -- load in CoolCV / blueMSX (ColecoVision).
#
# Same .bas source as the TI-99 build; only the toolchain differs (no --ti994a,
# and gasm80 instead of xas99+linkticart). Sprite magnification is set portably
# with VDP(1)=$E3 in the source, so nothing here is TI- vs Coleco-specific.
#
# -Dpacen=2 is REQUIRED (see ASTIROIDS.bas top-of-file comment): it's the
# measured native loop rate for this machine (2 VDP frames/tick = 30fps on
# ColecoVision, vs 3/20fps on the TI-99 -- build-ti.sh passes -Dpacen=3). The
# main loop and every frame-counted duration/velocity in the game derive from
# this constant, so Coleco runs its OWN native speed with equivalent
# real-world game pacing instead of being throttled down to the TI's rate.
# Omitting it fails LOUDLY at compile time, not silently at runtime.

CVBASIC_DIR="/cygdrive/c/Users/Howie/github.git/nanochess/CVBasic"
GASM80="/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe"

SRC="ASTIROIDS.bas"     # canonical source (shared with the TI build)
NAME="astiroids"        # output base name (dot-free, lowercase)
ASM="${NAME}_col.asm"
ROM="${NAME}.rom"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/2] CVBasic (Coleco)  $SRC -> $ASM   (-Dpacen=2, 30Hz Coleco native rate)"
rm -f "$ASM"
# No --ti994a: ColecoVision is CVBasic's default target. The trailing-slash 3rd
# path arg is the library dir (prologue/epilogue), same requirement as the TI build.
"$CVBASIC_DIR/cvbasic.exe" -Dpacen=2 "$SRC" "$ASM" "$CVBASIC_DIR/" \
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
