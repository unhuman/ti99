#!/usr/bin/env python3
"""checkpat.py, run against the overwrite that actually shipped.

A gate that has only ever passed is not known to be a gate -- and this one
replaces a check that PASSED on the very defect it was extended for. So the four
shapes below are applied to the real source and the run is believed only if each
one is rejected.

  1. the resident standing art at 176 -- exactly what shipped, over Harry's own
     left-facing legs;
  2. a borrow written outside its declared range;
  3. the chunked uploader handed a table that is not a declared borrow;
  4. a font load moved on top of the store.

Run:  python3 checkpat_test.py
"""

import os
import sys
import tempfile

import checkpat as cp

BAS = cp.BAS


def run(mutate):
    src = open(BAS, encoding="utf-8").read()
    out = mutate(src)
    assert out != src, "the mutation matched nothing -- the test is vacuous"
    fd, path = tempfile.mkstemp(suffix=".bas", text=True)
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(out)
        return cp.main(path, quiet=True)
    finally:
        os.unlink(path)


def resident_at_176(s):
    """What shipped: the standing pose loaded over HLLEG1..4 / HLLEGS1..4."""
    a = "\t#nsrc = VARPTR spr_raddot(0)\n"
    return s.replace(a, "\t#nsrc = VARPTR spr_hstand(0)\n"
                        "\tnchr = 176\n\tncnt = 16\n\tntab = 0\n"
                        "\t#ncol = 0\n\tnink = 1\n\tGOSUB nes_def\n" + a, 1)


def borrow_off_range(s):
    """The escalator's west phase written one character late."""
    return s.replace("\tnchr = 110\n", "\tnchr = 111\n", 1)


def swapper_wrong_source(s):
    """The chunked uploader pointed at art that is not a declared borrow."""
    return s.replace("\t#nsrc = VARPTR spr_hbod4(0)\n",
                     "\t#nsrc = VARPTR spr_cart(0)\n", 1)


def font_over_store(s):
    """A font load moved on top of the store's characters."""
    return s.replace("\tnchr = 32\n", "\tnchr = 100\n", 1)


CASES = [
    ("the resident standing art at 176 (what shipped)", resident_at_176),
    ("a borrow one character outside its range", borrow_off_range),
    ("the chunked uploader handed a non-borrow", swapper_wrong_source),
    ("a font load moved on top of the store", font_over_store),
]


def main():
    ok = True
    if cp.main(quiet=True) != 0:
        print("FAIL: the current source does not pass checkpat")
        ok = False
    else:
        print("ok  : the current source passes")
    for label, fn in CASES:
        got = run(fn)
        mark = "ok  " if got == 1 else "FAIL"
        if got != 1:
            ok = False
        print("%s: %-48s  rejected=%s" % (mark, label, got == 1))
    if not ok:
        print("checkpat did not reject a real overwrite -- do not trust a pass")
        return 1
    print("checkpat rejects every shape of overwrite tried, including the one "
          "that shipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
