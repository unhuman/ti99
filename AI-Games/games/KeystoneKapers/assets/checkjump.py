#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""No jump may pass THROUGH an escalator flight.

THE FAULT THIS EXISTS FOR
-------------------------
Reported from play as *"I was able to jump through the escalator to the floor.
This is rare."* -- and rare is the tell, because it needs a particular launch
point rather than a particular input.

A flight is a diagonal. In `esw` (distance along the flight from its head) the
bottom tread is at height 4 and every 8 px further along the floor the surface
steps up another 4. The jump's apex is **14 px**, so an arc launched near the
foot and heading up-flight flies OVER the bottom three treads (4, 8, 12) and
then meets the fourth (16), which is above the apex -- it cannot clear it. It
passes from above the staircase to below it, which in a side view is straight
through the riser, and lands on the floor beneath the flight.

`try_esc` could not catch it because its jump branch only looked at `esw`
52..76 -- the three treads a 14 px apex can land ON -- and required the arc to
be DESCENDING. Both are true of the ordinary case and neither is true here: the
collision is with a riser the player is still rising towards.

WHAT THIS CHECKS
----------------
The staircase surface is modelled here from ESCRISE and the 8-px-per-4-px step
pitch -- that is the ground truth, and it is deliberately NOT read from
`try_esc`, because `try_esc` is the thing under test.

The boarding RULE, by contrast, is executed straight out of the source: the
jump branch's statements are parsed and interpreted, so this cannot drift away
from the game the way a re-typed copy of the rule would. Any statement shape the
interpreter does not recognise is a hard error rather than a skip -- a checker
that silently ignores a new line is a checker that passes anything.

The sweep runs every launch position on the screen carrying each flight, both
flights, all four animation phases, all five frame deltas the pacer can produce,
all three jump directions, and a spread of accumulator phases. It fails on any
arc that is strictly above the surface on one pass and strictly below it on the
next without `try_esc` having boarded.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, 'src', 'KEYSTONE.bas')
STORE = os.path.join(HERE, os.pardir, 'src', 'store.bas')


# ----------------------------------------------------------------- the source
def read(path):
    return io.open(path, encoding='utf-8').read()


def strip_comment(line):
    out, in_str = [], False
    for ch in line:
        if ch == '"':
            in_str = not in_str
        if ch == "'" and not in_str:
            break
        out.append(ch)
    return ''.join(out).rstrip()


def const(text, name):
    m = re.search(r'CONST\s+%s\s*=\s*(-?\d+)' % name, text)
    if not m:
        sys.exit('checkjump: no CONST %s' % name)
    return int(m.group(1))


def jump_arc(text):
    m = re.search(r'jarc_tbl:.*?\n((?:\s*DATA BYTE [^\n]*\n)+)', text)
    if not m:
        sys.exit('checkjump: no jarc_tbl')
    vals = []
    for line in m.group(1).strip().split('\n'):
        vals += [int(v) for v in
                 line.split('DATA BYTE', 1)[1].split(',')]
    return vals


def jump_branch(text):
    """try_esc's ELSE arm -- the rule for boarding while airborne."""
    lines = [strip_comment(l) for l in text.split('\n')]
    try:
        i = next(k for k, l in enumerate(lines) if l.strip() == 'try_esc:')
    except StopIteration:
        sys.exit('checkjump: no try_esc')
    # the LAST `IF klst = ST_RUN THEN` before the routine's `GOSUB esc_ride`
    end = next(k for k in range(i, len(lines))
               if lines[k].strip() == 'GOSUB esc_ride')
    starts = [k for k in range(i, end)
              if lines[k].strip() == 'IF klst = ST_RUN THEN']
    if not starts:
        sys.exit('checkjump: try_esc has no walking/jumping split')
    s = starts[-1]
    try:
        e = next(k for k in range(s, end) if lines[k].strip() == 'ELSE')
    except StopIteration:
        sys.exit('checkjump: the split has no ELSE arm')
    # NESTING-AWARE. The arm contains block IFs of its own, so the first
    # `END IF` after it is not necessarily the one that closes it -- taking it
    # as the end silently truncated the rule to its first two statements.
    body, depth = [], 0
    for k in range(e + 1, end):
        t = lines[k].strip()
        if not t:
            continue
        if t == 'END IF':
            if depth == 0:
                break
            depth -= 1
        body.append(t)
        if re.match(r'^IF\b.*\bTHEN$', t):
            depth += 1
    return body


# ------------------------------------------------------------ the interpreter
CMP = {'>': lambda a, b: a > b, '<': lambda a, b: a < b,
       '=': lambda a, b: a == b, '>=': lambda a, b: a >= b,
       '<=': lambda a, b: a <= b, '<>': lambda a, b: a != b}

ASSIGN = re.compile(r'^([a-z][a-z0-9]*)\s*=\s*(.+)$')
COND = re.compile(r'^IF\s+([a-z][a-z0-9]*)\s*(<>|>=|<=|[<>=])\s*'
                  r'([a-z0-9]+)\s+THEN\s+(.+)$')
BLOCK = re.compile(r'^IF\s+([a-z][a-z0-9]*)\s*(<>|>=|<=|[<>=])\s*'
                   r'([a-z0-9]+)\s+THEN$')


def build(body):
    """Fold multi-line IF/ELSE/END IF into nested nodes.

    A block IF is not a shape to be skipped past -- try_esc uses one to set a
    flag and return, which is precisely the rule under test.
    """
    out, i = [], 0
    while i < len(body):
        stmt = body[i]
        m = BLOCK.match(stmt)
        if not m:
            out.append(stmt)
            i += 1
            continue
        depth, j = 1, i + 1
        then, els, cur = [], [], None
        while j < len(body):
            t = body[j]
            if BLOCK.match(t):
                depth += 1
            elif t == 'END IF':
                depth -= 1
                if depth == 0:
                    break
            elif t == 'ELSE' and depth == 1:
                cur = els
                j += 1
                continue
            (els if cur is els else then).append(t)
            j += 1
        if j >= len(body):
            sys.exit('checkjump: unclosed IF in try_esc -- `%s`' % stmt)
        out.append((m.groups(), build(then), build(els)))
        i = j + 1
    return out


def value(tok, env):
    if re.match(r'^-?\d+$', tok):
        return int(tok)
    if tok in env:
        return env[tok]
    sys.exit('checkjump: unknown name `%s` in try_esc' % tok)


def expr(text, env):
    parts = [p.strip() for p in text.split('+')]
    return sum(value(p, env) for p in parts)


def run_rule(body, env):
    """Execute the parsed jump branch. True = boarded, False = returned."""
    for stmt in body:
        if isinstance(stmt, tuple):
            (lhs, op, rhs), then, els = stmt
            arm = then if CMP[op](value(lhs, env), value(rhs, env)) else els
            if not run_rule(arm, env):
                return False
            continue
        m = COND.match(stmt)
        if m:
            lhs, op, rhs, then = m.groups()
            if not CMP[op](value(lhs, env), value(rhs, env)):
                continue
            if then.strip() == 'RETURN':
                return False
            stmt = then.strip()
        m = ASSIGN.match(stmt)
        if m:
            env[m.group(1)] = expr(m.group(2), env)
            continue
        if stmt == 'RETURN':
            return False
        sys.exit('checkjump: try_esc statement not understood -- `%s`\n'
                 '  Teach the interpreter this shape rather than skipping it;\n'
                 '  a rule the model cannot read is a rule this cannot check.'
                 % stmt)
    return True


# ------------------------------------------------------------- the staircase
def surface(esw, escrise):
    """Height of the flight above the floor at `esw`, in pixels.

    Ground truth, derived from the geometry and NOT from try_esc: the bottom
    tread (height 4) owns esw 68..76 and every 8 px up-flight adds 4 px.
    """
    if esw > 67:
        return 4
    h, edge = 4, 67
    while esw <= edge and h < escrise:
        h += 4
        edge -= 8
    return min(h, escrise)


# -------------------------------------------------------------------- pacing
def pace(acc, sp64, fdv, drains):
    """The game's shared fractional pacer. `drains` caps the step per frame."""
    step = 0
    for _ in range(min(fdv, 5)):
        acc += sp64
        for _ in range(drains):
            if acc > 63:
                step += 1
                acc -= 64
    return step, acc


def main():
    src = read(SRC)
    store = read(STORE)

    escrise = const(src, 'ESCRISE')
    kwalk = const(src, 'KWALK64')
    xwalw = const(src, 'XWALW')
    xwall = const(src, 'XWALL')
    arc = jump_arc(store)
    body = build(jump_branch(src))

    drains = len(re.findall(r'IF pacc > 63 THEN', src))
    if drains < 1:
        sys.exit('checkjump: pace_step has no drain steps')

    print('checkjump: arc %d frames, apex %d; flight rises %d px'
          % (len(arc), max(arc), escrise))
    print('           boarding rule read from try_esc, %d statements'
          % len(body))
    print('           pacer %d/64 px per frame, %d drain step(s)'
          % (kwalk, drains))

    bad, checked = sweep(body, arc, kwalk, drains, escrise, xwalw, xwall)
    print('           %d arcs simulated' % checked)
    return report(bad, checked)


def sweep(body, arc, kwalk, drains, escrise, xwalw, xwall):
    """Every launch, both flights, every phase, delta and direction."""
    bad = []
    checked = 0

    for esd in (0, 1):
        for escp in range(4):
            for fdv in range(1, 6):
                for kjdx in (0, 1, 2):
                    for kacc0 in (0, 16, 32, 48):
                        for klx0 in range(xwalw, xwall + 1):
                            checked += 1
                            r = simulate(klx0, kjdx, fdv, kacc0, escp, esd,
                                         arc, kwalk, drains, body, escrise,
                                         xwalw, xwall)
                            if r:
                                bad.append(r)
    return bad, checked


def report(bad, checked):
    if bad:
        # report the widest launch band per flight, not every instance
        seen = {}
        for esd, klx0, kjdx, fdv, escp, a, b, ew in bad:
            key = (esd, kjdx)
            lo, hi, ex = seen.get(key, (klx0, klx0, (fdv, escp, a, b, ew)))
            seen[key] = (min(lo, klx0), max(hi, klx0), ex)
        print('')
        print('  FAIL  %d of %d arcs pass THROUGH a flight' %
              (len(bad), checked))
        for (esd, kjdx) in sorted(seen):
            lo, hi, (fdv, escp, a, b, ew) = seen[(esd, kjdx)]
            side = 'west' if esd == 0 else 'east'
            way = ('standing', 'running east', 'running west')[kjdx]
            print('        %s flight, %s: launch x %d..%d' %
                  (side, way, lo, hi))
            print('          e.g. fdv %d phase %d -- height went %d -> %d '
                  'while the surface at esw %d is above it' %
                  (fdv, escp, a, b, ew))
        print('')
        print('  A flight is solid. An arc that is above the treads on one')
        print('  pass and below them on the next has gone through a riser,')
        print('  and lands on the floor beneath the staircase.')
        return 1

    print('           OK -- every arc either clears a flight or lands on it')
    return 0


def simulate(klx0, kjdx, fdv, kacc0, escp, esd, arc, kwalk, drains, body,
             escrise, xwalw, xwall):
    """One jump. Returns a failure tuple, or None."""
    klx, kacc = klx0, kacc0
    kjf, kjh = 1, arc[1]
    above = None                     # was he over the staircase last pass?

    while True:
        kjp = kjh
        kjf += fdv
        if kjf > 29:
            return None              # landed without incident
        kjh = arc[kjf]

        step, kacc = pace(kacc, kwalk, fdv, drains)
        if kjdx == 1:
            if esd == 1:             # east flight lives on screen 7
                klx = min(klx + step, xwall)
            else:
                if 255 - klx < step:
                    return None      # crossed the seam, off this flight
                klx += step
        elif kjdx == 2:
            if esd == 0:             # west flight lives on screen 0
                klx = max(klx - step, xwalw)
            else:
                if klx < step:
                    return None
                klx -= step

        kcx = klx + 8
        if esd == 0:
            esw = kcx + 2 * escp - 27
        else:
            head = 228 + 2 * escp
            if kcx > head:
                above = None
                continue
            esw = head - kcx
        if esw < 0 or esw > 255:
            above = None
            continue

        surf = surface(esw, escrise)
        env = {'esw': esw, 'kjh': kjh, 'kjp': kjp, 'escp': escp,
               'esy0': 0, 'esyp': 0 if above is None else int(above)}
        if run_rule(body, env):
            return None              # boarded -- the flight caught him

        now_above = kjh > surf
        if above is True and not now_above and esw <= 76:
            return (esd, klx0, kjdx, fdv, escp, kjp, kjh, esw)
        above = now_above

    return None


if __name__ == '__main__':
    sys.exit(main())
