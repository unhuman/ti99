# Sourced by build-ti.sh, build-coleco.sh and build-nes.sh (cwd = src/, with
# $TRUNCPY and die() already defined).
#
# THE SLOW PART OF EVERY BUILD WAS FOUR PYTHON SIMULATIONS, RUN ONE AFTER
# ANOTHER. Timed with `PS4='+ $EPOCHREALTIME' bash -x` (2026-09-26), each build
# took ~180 s, the same on all three targets: the 22 *_test.py took ~130 s and the
# check*.py gates ~45 s. Four of them were ~160 s of it -- checkjump_test.py ~58,
# checkjump.py ~43, levelplay_test.py ~41, randomlevels_test.py ~20. Compiling
# and assembling were seconds. They are independent processes that only READ the
# source and the generated files, so they run here all at once; the build waits
# for the slowest (checkjump_test, ~60 s) instead of the sum.
#
# NOTHING IS SKIPPED, AND EVERY FAILURE IS NAMED. Each job keeps its own die
# message; all of them are waited for, every failure is listed with the tail of
# its output, and only then does the build stop -- a parallel run must be at
# least as readable as the serial one it replaces.
#
# KK_TESTS_DONE=1 skips the *_test.py suite, and only that: tools/keystone-dev.ps1
# BuildAll sets it after the first target's build, because the suite tests the
# game's shared BASIC logic and generators, not one target's output -- three
# builds running it three times was ~260 s of repeat work. Every gate, including
# checkjump.py, still runs on every target.
#
# PYTHONDONTWRITEBYTECODE=1: parallel imports must not race writing the same
# __pycache__ files -- and a stale .pyc is its own CLAUDE.md 3A hazard anyway.

run_checks_parallel() {
    local dir rc name failed=""
    dir=$(mktemp -d) || die "cannot make a temp directory for the parallel checks"
    local -a names=() msgs=() pids=()
    local t
    # the gate that is as slow as a test
    names+=("checkjump.py")
    msgs+=("a jump can pass through an escalator -- run assets/checkjump.py")
    if [ "${KK_TESTS_DONE:-0}" != 1 ]; then
        for t in ../assets/*_test.py; do
            names+=("$(basename "$t")")
            msgs+=("$(basename "$t") fails -- its checker no longer rejects a defect
       that was actually played, or its mutation no longer applies. Run it.")
        done
    else
        echo "      (KK_TESTS_DONE=1: the *_test.py suite already passed in this BuildAll)"
    fi
    local i
    for i in "${!names[@]}"; do
        PYTHONDONTWRITEBYTECODE=1 "$TRUNCPY" "../assets/${names[$i]}" \
            > "$dir/$i.log" 2>&1 &
        pids+=($!)
    done
    for i in "${!names[@]}"; do
        wait "${pids[$i]}"
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "---- ${names[$i]} failed (exit $rc); last lines:" >&2
            tail -n 15 "$dir/$i.log" >&2
            failed="$failed
  ${msgs[$i]}"
        fi
    done
    rm -rf "$dir"
    [ -z "$failed" ] || die "parallel checks failed:$failed"
    echo "      ${#names[@]} checks/tests passed in parallel"
}
