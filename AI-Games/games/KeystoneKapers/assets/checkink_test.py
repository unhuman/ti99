#!/usr/bin/env python3
"""Proof that checkink.py rejects the ink maps that actually shipped faults.

A checker is worth nothing until it has been seen to FAIL, and both cases here
are maps that really existed in this tree.

WORTH KNOWING WHAT THIS CHECK DID *NOT* FIND. It was written to explain a white
block reported on the roof, on the theory that the partial buildings standing
against the sunset were collapsing to one index. They were not: the shipped ink
map leaves every store character with two colours, and running this against it
is what proved so. The white block has another cause and is still open.

What the check then caught was real, and was mine: the first attempt at
splitting the sky merged WHITE with the sunset colours AND merged CYAN with
LBLUE, which would have turned three characters -- including the counter top --
into solid blocks that nothing else in the build would have noticed.

Run:  python3 checkink_test.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import checkink

# (name, map, the characters it must name as unintended solid blocks)
CASES = [
    # CH_SHELFT (99) USED TO BE A THIRD WITNESS HERE AND NO LONGER IS. It is
    # now re-uploaded with `#ncol = 0` so the counters can have an ink of their
    # own, which takes it out of the colour table -- and out of every question
    # this file asks. The case is still REJECTED, by 152 and 153; what changed
    # is how many characters testify, not whether the defect gets through.
    # Narrowing the expectation is honest here and would not be if the case
    # stopped failing.
    ("the first attempt at splitting the sky (merged WHITE with the sunset)",
     [0, 0, 1, 1, 1, 1, 3, 1, 3, 3, 3, 3, 1, 3, 2, 3],
     {152, 153}),
    # Merging GRAY into WHITE was genuinely considered, to keep WHITE away from
    # the sunset colours. The check says it costs FIVE characters -- the grey
    # structure standing on white floor bars -- which is a good deal more than
    # the "floor bars lose a little contrast" it looked like on paper.
    ("merging GRAY into WHITE",
     [0, 0, 1, 1, 1, 1, 3, 2, 3, 3, 3, 3, 1, 3, 2, 2],
     {108, 109, 173, 174, 175}),
]

# The map that SHIPPED is clean by this measure -- see the note above. It is
# kept here so the fact stays checked rather than remembered.
SHIPPED = [0, 0, 1, 1, 2, 2, 2, 1, 2, 3, 2, 3, 1, 3, 2, 3]


def collapses(inkmap, chars):
    """The unexempt characters checkink would fail on, using its own rule.

    BOTH of checkink's escapes have to be honoured here, or the gate and the
    test that proves the gate works disagree -- and a gate whose own test calls
    it wrong is one somebody switches off. The second escape is the derived one:
    a character re-uploaded with `#ncol = 0` never consults the colour table, so
    whether its two table colours collapse is not a question about it.
    """
    solo = set(checkink.ink_only())
    out = set()
    for n, rows in enumerate(chars):
        code = checkink.STORE_FIRST + n
        if any(inkmap[b >> 4] != inkmap[b & 15] for b in rows):
            continue
        if code not in checkink.EXEMPT and code not in solo:
            out.add(code)
    return out


def main():
    chars = checkink.read_store_col()
    live = checkink.read_inkmap()

    rc = 0
    for name, inkmap, expect in CASES:
        got = collapses(inkmap, chars)
        if not expect <= got:
            print("SETUP ERROR: %s -- expected %s among the failures, got %s"
                  % (name, sorted(expect), sorted(got)))
            rc = 1
        elif not got:
            print("FAIL: %s produced no failures at all" % name)
            rc = 1
        else:
            print("ok: %-58s rejected (%s)" % (name, sorted(got)))

    got = collapses(SHIPPED, chars)
    if got:
        print("SETUP ERROR: the shipped map now collapses %s -- the note at the "
              "top of this file is out of date" % sorted(got))
        rc = 1
    else:
        print("ok: the shipped map is clean, so it is NOT the white block")

    # ...and the map in the tree must be clean, or the two halves disagree.
    got = collapses(live, chars)
    if got:
        print("FAIL: the live ink map collapses %s" % sorted(got))
        rc = 1
    else:
        print("ok: the live ink map leaves no unintended solid blocks")

    return rc


if __name__ == "__main__":
    sys.exit(main())
