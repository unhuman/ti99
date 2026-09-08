#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""checkjump must REJECT the rule that shipped the bug, and accept the fix.

A sweep that passes proves nothing on its own -- it might be passing because it
cannot see the fault. This feeds `checkjump.sweep` the two rules by hand:

  * the HISTORICAL one, which looked only at the three treads a 14 px apex can
    land on and required the arc to be descending. It is the rule that was in
    the game when a player reported jumping through a flight, so the sweep must
    fail on it.
  * the CURRENT one, taken live out of KEYSTONE.bas, which must pass.

The rules are typed out here rather than imported from the source, because a
test that reads its input from the thing under test is a test that agrees with
whatever that thing does.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import checkjump as C                                       # noqa: E402


BROKEN = [
    'IF esw > 76 THEN RETURN',
    'IF esw < 52 THEN RETURN',
    'esy0 = 12',
    'IF esw > 59 THEN esy0 = 8',
    'IF esw > 67 THEN esy0 = 4',
    'esy0 = esy0 + escp',
    'IF kjh > kjp THEN RETURN',
    'IF kjh > esy0 THEN RETURN',
]


def main():
    src = C.read(C.SRC)
    store = C.read(C.STORE)
    arc = C.jump_arc(store)
    escrise = C.const(src, 'ESCRISE')
    kwalk = C.const(src, 'KWALK64')
    xwalw = C.const(src, 'XWALW')
    xwall = C.const(src, 'XWALL')
    import re
    drains = len(re.findall(r'IF pacc > 63 THEN', src))

    args = (arc, kwalk, drains, escrise, xwalw, xwall)
    fails = 0

    bad, checked = C.sweep(C.build(BROKEN), *args)
    if bad:
        print('  ok    the shipped rule is rejected (%d of %d arcs go '
              'through a flight)' % (len(bad), checked))
    else:
        print('  FAIL  the sweep PASSES the rule that shipped the bug --')
        print('        it cannot see the fault it exists to catch')
        fails += 1

    bad, checked = C.sweep(C.build(C.jump_branch(src)), *args)
    if not bad:
        print('  ok    the rule now in KEYSTONE.bas is accepted (%d arcs)'
              % checked)
    else:
        print('  FAIL  the current rule lets %d of %d arcs through'
              % (len(bad), checked))
        fails += 1

    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
