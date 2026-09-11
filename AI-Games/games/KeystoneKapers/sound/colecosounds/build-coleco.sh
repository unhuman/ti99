#!/usr/bin/env bash
#
# Build Keystone Kapers for ColecoVision.
#
#   cvbasic (default target)  ->  gasm80  ->  src/ufo.rom
#
# Same source as build-ti.sh; only the toolchain differs (no --ti994a, and
# gasm80 instead of xas99 + linkticart).

CVBASIC_DIR="${CVBASIC_DIR:-/cygdrive/c/Users/Howie/github.git/unhuman/CVBasic}"
GASM80="${GASM80:-/cygdrive/c/Users/Howie/github.git/nanochess/gasm80/gasm80.exe}"
[ -d "$CVBASIC_DIR" ] || CVBASIC_DIR="${CVBASIC_DIR/#\/cygdrive\/c\//\/c\/}"
[ -f "$GASM80" ]      || GASM80="${GASM80/#\/cygdrive\/c\//\/c\/}"

SRC="COLSND.bas"
NAME="colsnd"
ASM="${NAME}_col.asm"
ROM="${NAME}.rom"

die() { echo "ERROR: $1" >&2; exit 1; }

[ -f "$CVBASIC_DIR/cvbasic.exe" ] || die "cvbasic.exe not found in $CVBASIC_DIR"
[ -f "$GASM80" ]                 || die "gasm80.exe not found ($GASM80)"

# REPO ROOT, DERIVED RATHER THAN COUNTED. This bench sits at
# games/KeystoneKapers/sound/<name>/, so the shared tools are five levels up
# from src/ -- a depth that has already changed once, when the bench moved under
# the game whose sounds it measures. A wrong ../../.. count would make python
# fail to open the file and the die message would name the GATE rather than the
# path, so derive it from $0 and check it here, where the error can say so.
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)" || die "cannot locate the repo root"
[ -f "$REPO/tools/bigvar.py" ] || die "tools/ not found at $REPO -- has this bench moved?"

cd "$(dirname "$0")/src" || die "cannot find src/"
[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

# PYTHON. Prefer one on PATH; fall back to the Cygwin interpreter this machine
# actually has. Git Bash has NEITHER `python3` NOR `python`, and when the gates
# below ran with a missing interpreter they still failed the build -- reporting
# "8-bit truncation", the gate's own message, rather than "no python". A gate
# that cannot run must say so, not accuse the source.
find_py() {
    for pc in python3 python /c/cygwin64/bin/python3.9.exe \
              /cygdrive/c/cygwin64/bin/python3.9.exe; do
        if command -v "$pc" >/dev/null 2>&1; then echo "$pc"; return 0; fi
    done
    return 1
}
PY="$(find_py)" || die "no python interpreter found (tried python3, python, Cygwin 3.9)"
TRUNCPY="$PY"

# CVBASIC.EXE IS A CYGWIN BINARY AND GIT BASH SHADOWS ITS RUNTIME. Git Bash is
# MSYS2 and puts its own msys-2.0.dll first, so running cvbasic.exe from here
# died with
#
#   cvbasic.exe: error while loading shared libraries: ?: cannot open shared
#   object file: No such file or directory
#
# -- exit 127, no line number, nothing to do with the program being compiled.
# The same command from PowerShell worked, which made it read as general
# flakiness in the toolchain rather than as one directory in the wrong order.
for cyg in /c/cygwin64/bin /cygdrive/c/cygwin64/bin; do
    [ -d "$cyg" ] && PATH="$cyg:$PATH" && break
done
export PATH

# AND THE SECOND HALF OF THE SAME PROBLEM: Git Bash rewrites an absolute POSIX
# ARGUMENT into C:/... before handing it to a native program, and Cygwin's
# python does not read that as absolute -- it joins it onto the current
# directory and reports "can't open file <cwd>/C:/Users/...". Passing the
# /cygdrive form with MSYS2's rewriting switched off is the form both
# understand. Only the tool scripts outside this tree are affected; every
# other argument in this file is relative and needs none of it.
PYCYG=0
[ "$("$PY" -c 'import sys; print(sys.platform)' 2>/dev/null)" = "cygwin" ] && PYCYG=1
cygpy() {
    _s="$1"; shift
    if [ "$PYCYG" = 1 ]; then
        case "$_s" in /c/*) _s="/cygdrive$_s";; esac
        MSYS2_ARG_CONV_EXCL='*' "$PY" "$_s" "$@"
    else
        "$PY" "$_s" "$@"
    fi
}

# ---------------------------------------------------------------- TRUNCATION GATE
# See TRUNCATION.md. Both forms are silent and both produce a plausible wrong
# value rather than a failure, so they fail the build instead.
# NO GENERATE STAGE -- this program has no art to generate.

"$TRUNCPY" "$REPO"/tools/bigvar.py *.bas \
    || die "8-bit truncation -- see TRUNCATION.md 1a"
"$TRUNCPY" "$REPO"/tools/bigconst.py *.bas \
    || die "CONST over 255 -- see TRUNCATION.md 1b"

# THIS MATTERS MORE HERE THAN ON THE TI. A GOSUB left by GOTO never pops its
# return address; the TI has ~7 KB of stack to absorb it, ColecoVision has 1 KB
# total and the leak walks down into the variables.
"$TRUNCPY" "$REPO"/tools/gosubtrace.py "$SRC" | grep -q "every GOSUB target reaches a return" \
    || die "a GOSUB target cannot reach a RETURN -- see CLAUDE.md 3A"

# A PRINT AT that runs past column 31 wraps onto the next row, and a HUD VPOKE
# can land inside a label some other routine printed. Both are arithmetic on a
# bare offset, so neither is visible in the source -- UFO's 838 screen shipped its
# difficulty digit into the middle of the word DIFFICULTY. This game's checker
# also refuses to pass on a drawing routine missing from its screen map, and
# NO GATES -- they all check Keystone Kapers art and levels, which this
# program does not have. The truncation sweep above is kept: it is about
# CVBasic, not about that game.

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
