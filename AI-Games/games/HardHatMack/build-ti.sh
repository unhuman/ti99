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
# Fixed RAM-resident program is capped at 24,336 bytes; art/levels live in
# four 8 KB banks: setup/assets, actors/audio, title/scenery and motion/art. Check all
# BEFORE accepting the cart. The final cartridge is padded to 64 KB by linkticart.
#
# Run with Cygwin bash on Windows (the compiler is a Cygwin binary).

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
[ -f "$NAME.bas" ] || die "$NAME.bas not found in $(pwd)"

echo "[1/3] cvbasic    $NAME.bas -> $NAME.a99"
rm -f "$NAME.a99"
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$NAME.bas" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

echo "[2/3] xas99      $NAME.a99 -> $NAME.bin"
rm -f "$NAME.bin" "${NAME}"_b*.bin
"$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
    || die "xas99 failed (see $NAME.txt for assembly errors)"
[ -s "${NAME}_b0.bin" ] || die "xas99 produced no fixed image"

# Verify every shortened branch after reassembly; shared checked optimizer.
case "${TI_SHORT_BRANCHES:-1}" in
    0) echo "TI short branches disabled" ;;
    1)
        cp "$NAME.a99" "$NAME.unopt.a99" || die "cannot save original assembly"
        cp "$NAME.txt" "$NAME.unopt.txt" || die "cannot save original listing"
        "$TRUNCPY" ../../KeystoneKapers/assets/shortbranches.py rewrite "$NAME.unopt.a99" "$NAME.unopt.txt" \
            "$NAME.a99" "$NAME.txt" "$NAME.branches.json" || die "branch rewrite failed"
        "$PY" "$XDT99_DIR/xas99.py" -b -R "$NAME.a99" -L "$NAME.txt" \
            || die "short-branch assembly failed"
        "$TRUNCPY" ../../KeystoneKapers/assets/shortbranches.py verify "$NAME.unopt.a99" "$NAME.unopt.txt" \
            "$NAME.a99" "$NAME.txt" "$NAME.branches.json" || die "branch verification failed"
        ;;
    *) die "TI_SHORT_BRANCHES must be 0 or 1" ;;
esac

# Banked fixed image is padded; check actual content before packing.
FIRST="${NAME}_b0.bin"
[ -s "$FIRST" ] || die "missing banked fixed image"
"$PY" ../../KeystoneKapers/assets/banksize.py "$FIRST" "$CAP" || die "fixed area overflow"
echo "[3/3] linkticart $FIRST -> ${NAME}_8.bin"
"$PY" "$CVBASIC_DIR/linkticart.py" "$FIRST" "${NAME}_8.bin" "$CARTNAME" || die "linkticart failed"
"$PY" ../assets/checkbank.py || die "data bank validation failed"
echo "Build OK -> $(pwd)/${NAME}_8.bin"

# Build and package before the long source/art regressions. This leaves a usable
# cartridge on disk promptly so it can be tried in Classic99 while checks run.
# A failing gate still makes this build command fail; the earlier cart remains
# available for debugging and must not be treated as a validated release.
TRUNCPY="python3"; command -v "$TRUNCPY" >/dev/null 2>&1 || TRUNCPY="python"
TRUNCPY="$TRUNCPY" bash ../assets/runtests.sh || die "source/art regression gate"
