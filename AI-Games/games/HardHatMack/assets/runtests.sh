#!/usr/bin/env bash
# Run Hard Hat Mack's target-independent source/art regression checks in parallel.
# Caller sets TRUNCPY and runs from src/ after any requested asset regeneration.

set -u
TRUNCPY="${TRUNCPY:-python3}"
dir=$(mktemp -d) || { echo "ERROR: cannot create gate log directory" >&2; exit 1; }
trap 'rm -rf "$dir"' EXIT

names=(bigvar bigconst genfixtures genconveyors genmotion gentitle checkphysics gosubtrace)
run_gate() {
    case "$1" in
        0) "$TRUNCPY" ../../../tools/bigvar.py *.bas ;;
        1) "$TRUNCPY" ../../../tools/bigconst.py *.bas ;;
        2) "$TRUNCPY" ../assets/genfixtures.py ;;
        3) "$TRUNCPY" ../assets/genconveyors.py ;;
        4) "$TRUNCPY" ../assets/genmotion.py ;;
        5) "$TRUNCPY" ../assets/gentitle.py ;;
        6) "$TRUNCPY" ../assets/checkphysics.py ;;
        7) "$TRUNCPY" ../../../tools/gosubtrace.py HARDHAT.bas ;;
    esac
}

export PYTHONDONTWRITEBYTECODE=1
pids=()
for i in "${!names[@]}"; do
    run_gate "$i" >"$dir/$i.log" 2>&1 &
    pids[$i]=$!
done

failed=()
for i in "${!names[@]}"; do
    if wait "${pids[$i]}"; then
        :
    else
        rc=$?
        echo "---- ${names[$i]} failed (exit $rc); last lines:" >&2
        tail -n 15 "$dir/$i.log" >&2
        failed+=("${names[$i]}")
    fi
done

if ((${#failed[@]})); then
    echo "ERROR: regression gate failure(s): ${failed[*]}" >&2
    exit 1
fi
echo "All ${#names[@]} source/art regression gates passed in parallel"
