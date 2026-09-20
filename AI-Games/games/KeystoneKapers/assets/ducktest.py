#!/usr/bin/env python3
"""Prove genart's pose reader rejects the ways a Kelly art file can go wrong.

A reader that has only ever been handed a good file is not known to be a gate,
and this one guards the quietest failure in the set: a row that loses ONE
character stops being art and is SKIPPED, so every row below it shifts up and
the figure is rebuilt out of its neighbours. It shipped once, and it was
reported as two unrelated drawing bugs -- "the buttons on the shirt are all
messed up" and "one of the arms sort of disappears" -- with nothing anywhere
naming a line.

THE CROUCH IS AN ORDINARY POSE FILE NOW. It used to be three overlapping 16x16
grids drawn at one y, which needed a reader of its own and a rule about the
helmet winning shared pixels; staggering its sprite boxes the way the run does
made the three bands sit in separate ROWS of one figure, so it reads with the
same loader as kelly-run1.txt. The mutations moved with it: what used to be
"two inks in one row" and "the helmet covering the face" are now the band rule,
which says a colour may not cross a sprite boundary.

Run:  python3 ducktest.py
"""
import io
import os
import shutil
import subprocess
import sys

ASSETS = os.path.dirname(os.path.abspath(__file__))
TMP = os.environ.get("TMPDIR", "/tmp")
ALPHA = set(".#-0")

# Every file the pose reader parses. Mutating each of them is the point: they
# share one loader, so a hole in it is a hole under all three.
POSES = ["kelly-duck.txt", "kelly-run1.txt", "kelly-run2.txt"]


def art_rows(lines):
    return [n for n, r in enumerate(lines)
            if len(r) == 16 and set(r) <= ALPHA]


def run(sandbox, name, lines, label, expect_reject):
    """Import genart in a COPY of assets/ with one file made defective.

    IT USED TO MUTATE THE REAL FILES and put them back afterwards, which is a
    trap with two ways to spring. A build running at the same time reads
    whichever half-second it lands in -- that happened, and genart refused
    `kelly-run2.txt` for skin ink on a helmet row while the file on disk was
    perfectly fine. And a run killed between the write and the restore leaves
    the artwork corrupted with no sign of why.

    The sandbox costs one directory copy and removes both. Nothing this test
    does can touch the art any more.
    """
    path = os.path.join(sandbox, name)
    io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    subprocess.call(["rm", "-rf", os.path.join(sandbox, "__pycache__")])
    p = subprocess.Popen(
        [sys.executable, "-c",
         "import sys; sys.path.insert(0, %r); import genart" % sandbox],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.communicate()[0].decode("utf-8", "replace")
    shutil.copy(os.path.join(ASSETS, name), path)      # put the sandbox back

    rejected = p.returncode != 0
    ok = rejected == expect_reject
    print("  %-38s %s" % (label,
                          "REJECTED  ok" if rejected and expect_reject else
                          "accepted  ok" if ok else
                          ("ACCEPTED -- THE GATE IS BLIND" if expect_reject
                           else "REJECTED -- good art refused")))
    if rejected and expect_reject:
        said = [l for l in out.split("\n") if l.strip()]
        print("      %s" % (said[-1][:92] if said else "(no message)"))
    return ok


def main():
    print("genart pose reader -- mutation test")
    good = True

    sandbox = os.path.join(TMP, "ducktest-assets")
    if os.path.isdir(sandbox):
        shutil.rmtree(sandbox)
    shutil.copytree(ASSETS, sandbox,
                    ignore=shutil.ignore_patterns("__pycache__", "*.png",
                                                  "ref2600", "sfx", "sound"))

    for name in POSES:
        path = os.path.join(ASSETS, name)
        lines = io.open(path, encoding="utf-8").read().split("\n")
        rows = art_rows(lines)
        if len(rows) < 17:
            print("  %s has %d art rows -- cannot mutate" % (name, len(rows)))
            return 1
        print("\n%s" % name)

        good &= run(sandbox, name, lines, "the file as shipped", False)

        # ONE CHARACTER SHORT. The row stops being art and is skipped, so the
        # figure below it shifts up a row. This is the one that shipped.
        m = list(lines)
        m[rows[0]] = m[rows[0]][:-1]
        good &= run(sandbox, name, m, "a 15-character art row", True)

        # INK THAT CROSSES A SPRITE BOUNDARY. A band IS a sprite and a TMS9918
        # sprite carries one colour, so skin on a helmet row cannot be drawn --
        # and drawn anyway it would come out black without a word.
        m = list(lines)
        m[rows[0]] = "-" + m[rows[0]][1:]
        good &= run(sandbox, name, m, "skin ink on a HELMET row", True)

        # And the same rule from the other side: helmet ink down in the body.
        m = list(lines)
        m[rows[12]] = "#" + m[rows[12]][1:]
        good &= run(sandbox, name, m, "helmet ink on a BODY row", True)

        # TOO FEW ROWS. A file cut short is padded, but one cut below the
        # minimum is a file that lost its legs rather than one drawn empty.
        m = [l for n, l in enumerate(lines) if n not in rows[3:]]
        good &= run(sandbox, name, m, "all but three art rows deleted", True)

    # THE CROUCH'S HEAD IS THE STANDING HEAD, AND THAT IS A CLAIM WITH NO
    # MECHANISM BEHIND IT.
    #
    # Rows 0..10 of kelly-duck.txt were GENERATED by copying kelly-run1.txt, so
    # they matched on the day. Nothing keeps them matching: the two files are
    # edited independently, and a tweak to the standing head leaves the crouch
    # wearing the old one -- two hats that are nearly the same, which is
    # precisely the kind of difference nobody sees and everybody feels.
    #
    # "Full size" is only checkable if it is checked.
    print("\nthe crouch wears the STANDING head")
    head = {}
    for name in ("kelly-run1.txt", "kelly-duck.txt"):
        lines = io.open(os.path.join(ASSETS, name),
                        encoding="utf-8").read().split("\n")
        head[name] = [lines[n] for n in art_rows(lines)[:11]]
    same = head["kelly-run1.txt"] == head["kelly-duck.txt"]
    print("  %-38s %s" % ("rows 0-10 match kelly-run1.txt",
                          "ok" if same else
                          "WRONG -- the crouch has drifted from the run"))
    if not same:
        for n, (a, b) in enumerate(zip(head["kelly-run1.txt"],
                                       head["kelly-duck.txt"])):
            if a != b:
                print("      row %-2d  run1 %s   duck %s" % (n, a, b))
    good &= same

    print()
    print("ducktest OK" if good else
          "ducktest FAILED -- the reader is not a gate")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
