#!/usr/bin/env python3
"""Keystone Kapers -- THE CHASE ARITHMETIC CHECK.

A chase does not resolve on speed, it resolves on PATH LENGTH / SPEED, and the
two are easy to get wrong independently.  Kelly used to run 1.5x faster than
Harry and still never catch him, because Harry spawns beside floor 2's
escalator and so covers two thirds of Kelly's distance: both climbed to the
roof in ~35 s, so a pursuit on foot could not close no matter how long it ran.
Nothing about that is visible in either speed constant, and nothing in the
build reports it.

So this reads the real constants out of src/KEYSTONE.bas and src/store.bas,
walks both actors' routes to the roof, and checks three things per Krook band:

  1. Harry is strictly slower than Kelly            (else he cannot be caught
                                                     once he starts fleeing)
  2. Kelly's climb beats Harry's by >= MARGIN sec   (else pursuit on foot is
                                                     arithmetically hopeless)
  3. Harry's escape lands inside the round timer    (else "escaped off the
                                                     roof" is a dead loss
                                                     condition and only the
                                                     clock can end a round)

Exits non-zero on any failure.  Run it after touching WALKSP, hsp4, the
spawns, the escalator sides, ESCF or TIMEL.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, '..', 'src')

MARGIN = 8.0    # seconds of slack Kelly must have on Harry's whole climb.
                # One beach ball costs 9 s, so anything under this means a
                # single mistake makes the round unwinnable.
FPS    = 60.0

def read(name):
    with open(os.path.join(SRC, name), encoding='utf-8', errors='replace') as f:
        return f.read()

def const(src, name):
    m = re.search(r'^\s*CONST\s+%s\s*=\s*(\d+)' % name, src, re.M)
    if not m:
        sys.exit('checkchase: CONST %s not found' % name)
    return int(m.group(1))

def assign(src, var, after=None):
    """Value of the last plain `var = N` assignment (optionally after a label)."""
    body = src
    if after:
        i = body.find(after)
        if i < 0:
            sys.exit('checkchase: label %s not found' % after)
        body = body[i:]
    m = re.search(r'^\s*%s\s*=\s*(\d+)\s*(?:\'|$)' % var, body, re.M)
    if not m:
        sys.exit('checkchase: assignment %s not found' % var)
    return int(m.group(1))

bas   = read('KEYSTONE.bas')
store = read('store.bas')

WALKSP = const(bas, 'WALKSP')
ESCF   = const(bas, 'ESCF')
TIMEL  = const(bas, 'TIMEL')

# Harry's per-Krook speed, in quarter pixels: a base plus `IF krk > N THEN` steps.
sk = bas[bas.find('start_krook:'):]
base = re.search(r"^\s*hsp4\s*=\s*(\d+)", sk, re.M)
if not base:
    sys.exit('checkchase: hsp4 base not found in start_krook')
bands = [(1, int(base.group(1)))]
for m in re.finditer(r"^\s*IF\s+krk\s*>\s*(\d+)\s+THEN\s+hsp4\s*=\s*(\d+)", sk, re.M):
    bands.append((int(m.group(1)) + 1, int(m.group(2))))

# Escalator side per level: 0 = climbs west, 1 = east, 255 = none.
m = re.search(r'stor_esc:.*?\n\s*DATA BYTE\s+([0-9,\s]+)', store, re.S)
if not m:
    sys.exit('checkchase: stor_esc table not found')
esc = [int(v) for v in m.group(1).split(',')][:4]

# The point an actor runs to in order to board, and where the ride lands him.
# Both come straight from move_harry / try_esc: west is x=32 on screen 0
# landing at x=8, east is x=224 on screen 7 landing at x=232.
BOARD = {0: 0 * 256 + 32, 1: 7 * 256 + 224}
LAND  = {0: 0 * 256 + 8,  1: 7 * 256 + 232}
ROOF_ESCAPE = 7 * 256 + 224     # move_harry: hlv=3 -> htsc 7, htx 224

def climb(lv, world_x, px_per_frame):
    """Frames for an actor starting on level `lv` at `world_x` to reach the roof
    escape edge, running every leg end to end and riding each escalator."""
    frames, legs = 0.0, []
    while lv < 3:
        side = esc[lv]
        if side > 1:
            sys.exit('checkchase: level %d has no working escalator' % lv)
        run = abs(BOARD[side] - world_x)
        frames += run / px_per_frame + ESCF
        legs.append((lv, run))
        world_x = LAND[side]
        lv += 1
    run = abs(ROOF_ESCAPE - world_x)
    frames += run / px_per_frame
    legs.append((3, run))
    return frames, legs

kelly_lv = assign(sk, 'klv'); kelly_x = assign(sk, 'klsc') * 256 + assign(sk, 'klx')
harry_lv = assign(sk, 'hlv'); harry_x = assign(sk, 'hsc')  * 256 + assign(sk, 'hx')

kf, klegs = climb(kelly_lv, kelly_x, float(WALKSP))
kt = kf / FPS
print('Kelly  %d px/frame, spawns lv%d x%d' % (WALKSP, kelly_lv, kelly_x))
print('       route %s px  ->  climbs in %5.1f s' %
      ('+'.join(str(r) for _, r in klegs), kt))
print()

fail = []
for i, (first, sp4) in enumerate(bands):
    last  = bands[i + 1][0] - 1 if i + 1 < len(bands) else None
    label = 'Krooks %d-%d' % (first, last) if last else 'Krooks %d+' % first
    hspd  = sp4 / 4.0
    hf, hlegs = climb(harry_lv, harry_x, hspd)
    ht = hf / FPS
    margin = ht - kt
    print('%-14s Harry %.2f px/frame, route %s px' %
          (label, hspd, '+'.join(str(r) for _, r in hlegs)))
    print('%-14s escapes at %5.1f s (timer %d s), Kelly is there %5.1f s earlier'
          % ('', ht, TIMEL, margin))
    if hspd >= WALKSP:
        fail.append('%s: Harry %.2f px/frame is not slower than Kelly %d -- '
                    'he cannot be caught once he flees' % (label, hspd, WALKSP))
    if margin < MARGIN:
        fail.append('%s: Kelly beats Harry to the roof by only %.1f s '
                    '(need %.1f) -- one obstacle hit makes the round '
                    'unwinnable on foot' % (label, margin, MARGIN))
    if ht >= TIMEL:
        fail.append('%s: Harry needs %.1f s to escape but the round is %d s -- '
                    'he can never escape, so that loss condition is dead'
                    % (label, ht, TIMEL))
    print()

if fail:
    for f in fail:
        print('FAIL  ' + f)
    sys.exit(1)
print('OK: the chase resolves at every Krook band.')
