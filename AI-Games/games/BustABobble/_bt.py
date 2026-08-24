P = "build-ti.sh"
s = open(P, encoding="utf-8").read()

old = """# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. No build-time constants needed (unlike Astiroids'
# -Dpacen): the main loop is a single WAIT per frame doing trivial work on
# both machines, so both run the same 60Hz NTSC tick rate natively --
# no cross-platform pacing tricks required.
#"""
new = """# Same .bas source as the ColecoVision build (build-coleco.sh); only the
# toolchain differs. No pacing constant is needed (unlike Astiroids' -Dpacen):
# the main loop is a single WAIT per frame doing trivial work on both machines,
# so both run the same 60Hz NTSC tick rate natively.
#
#   ./build-ti.sh            -> BUSTABOB_8.bin, the 30 arcade rounds
#   ./build-ti.sh --expert   -> BUSTAB2_8.bin,  the 50 generated ones
#
# ONE ENGINE, TWO CARTS. --expert passes -DEXPERT=1; the source uses it to pick
# levels2.bas over levels.bas and to swap the timer ceiling-drop for the arcade's
# shot-count rule. Both carts are built from the same BUSTABOB.bas, so an engine
# fix reaches both without being applied twice.
#
# The disk name is BUSTAB2, not BUSTABOB2: the repo caps program names at 8
# characters (CLAUDE.md 8).
#"""
assert old in s
s = s.replace(old, new, 1)

old = """NAME="BUSTABOB"
CARTNAME="BUST-A-BOBBLE"
"""
new = """SRC="BUSTABOB.bas"          # one source; --expert only changes what it compiles
NAME="BUSTABOB"
CARTNAME="BUST-A-BOBBLE"
DEFS=""
EXPERT=0
if [ "$1" = "--expert" ]; then
    NAME="BUSTAB2"
    CARTNAME="BUST-A-BOBBLE 2"
    DEFS="-DEXPERT=1"
    EXPERT=1
elif [ -n "$1" ]; then
    echo "ERROR: unknown option '$1' (only --expert)" >&2; exit 1
fi
"""
assert old in s
s = s.replace(old, new, 1)

old = """[ -f "$NAME.bas" ] || die "$NAME.bas not found in $(pwd)"

echo "[1/3] cvbasic    $NAME.bas -> $NAME.a99\""""
new = """[ -f "$SRC" ] || die "$SRC not found in $(pwd)"

echo "[1/3] cvbasic    $SRC -> $NAME.a99   ${DEFS:-(arcade set)}\""""
assert old in s
s = s.replace(old, new, 1)

old = """# The forked cvbasic (unhuman/CVBasic) auto-defines a constant named after the
# machine, so --ti994a makes TI994A=1. The source's `#if TI994A` uses that to
# compile OUT the level-up flush on TI (it overflowed the 24,336-byte cart and
# is redundant with the walls-collapse there); ColecoVision leaves TI994A
# undefined, so its `#else` keeps the full flush. No explicit -DTI994A is passed
# -- it would just "constant redefined" over the auto-define.
"$CVBASIC_DIR/cvbasic.exe" --ti994a "$NAME.bas" "$NAME.a99" "$CVBASIC_DIR/" \
    || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99\""""
new = """# The forked cvbasic (unhuman/CVBasic) auto-defines a constant named after the
# machine, so --ti994a makes TI994A=1. This source's `#if TI994A` blocks are the
# BANK directives: the level data lives in ROM bank 1 on TI, while ColecoVision
# leaves TI994A undefined and keeps everything flat. No explicit -DTI994A is
# passed -- it would just "constant redefined" over the auto-define.
"$CVBASIC_DIR/cvbasic.exe" --ti994a $DEFS "$SRC" "$NAME.a99" "$CVBASIC_DIR/" \
    2>&1 | tee "$NAME.log" || die "CVBasic compile failed (see messages above)"
[ -s "$NAME.a99" ] || die "CVBasic produced no/empty $NAME.a99"

# PROVE THE FLAG ARRIVED, rather than trusting that we passed it. An undefined
# name in `#if` is silently FALSE in this compiler -- no error, no warning -- so a
# mistyped -DEXPRT=1 would pack the ARCADE levels into a cart called BUSTAB2 and
# nothing in the chain would say a word. Both branches of the source announce
# themselves with #info, so the compiler itself tells us which one it took.
if [ "$EXPERT" = 1 ]; then
    grep -q "BUILDING THE EXPERT SET" "$NAME.log" \
        || die "-DEXPERT=1 did not reach the source: the compiler reported the ARCADE branch"
else
    grep -q "BUILDING THE ARCADE SET" "$NAME.log" \
        || die "expected the ARCADE branch; the compiler reported something else"
fi"""
assert old in s
s = s.replace(old, new, 1)

# The winnability gate must audit the level file this cart actually carries.
old = """"$PY" ../assets/solvelevels.py --anchors || die "level data has unanchored bubbles -- see above\""""
new = """if [ "$EXPERT" = 1 ]; then
    echo "      *** EXPERT SET NOT YET WINNABILITY-CHECKED -- see the plan, phase 4 ***"
else
    "$PY" ../assets/solvelevels.py --anchors || die "level data has unanchored bubbles -- see above"
fi"""
assert old in s
s = s.replace(old, new, 1)

old = """"$PY" ../assets/romcheck.py || die "romcheck FAILED -- the cart is truncated (see above)\""""
new = """"$PY" ../assets/romcheck.py "$NAME" || die "romcheck FAILED -- the cart is truncated (see above)\""""
assert old in s
s = s.replace(old, new, 1)
open(P, "w", encoding="utf-8", newline="\n").write(s)
print("build-ti.sh: --expert flag, compile-branch proof, per-cart romcheck")
