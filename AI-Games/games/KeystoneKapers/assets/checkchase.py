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
spawns, the escalator sides, ESCRISE or TIMEL.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, '..', 'src')

MARGIN = 8.0    # seconds of slack Kelly must have on Harry's whole climb.
                # One beach ball costs 9 s, so anything under this means a
                # single mistake makes the round unwinnable.
# PASSES PER SECOND, NOT FRAMES -- for everything still paced that way.
#
# HARRY IS THE EXCEPTION NOW: he walks by the frame delta, so his stride is in
# real frames and does not depend on this figure at all. That is the whole point
# of the change -- the loop rate varies 20-26 by screen, and while he was paced
# per pass it silently decided whether he escaped (DESIGN.md 0f-ter). His
# escalator rides are still passes, and climb() keeps the two apart.
#
# Kelly is still per pass -- `klx = klx + WALKSP` -- and the loop does not
# run at 60 Hz. It was measured in play at 24-26 passes a second on ordinary
# screens and 20 on the west one (two escalator flights), so 25 is the honest
# figure and the west screen is the pessimistic one.
#
# THIS CONSTANT BEING 60 IS WHAT HID A BROKEN ROUND. With it the checker
# reported Kelly reaching the roof in 30 s against a 50 s timer -- comfortable.
# The real numbers are 2.4x that: 72 s of wall clock against a timer that,
# at 60 frames a unit, ran out at 50. The round could not be completed by the
# intended route and the checker said OK on every run. The timer is paced by
# the frame delta and therefore in real seconds; the actors are not; a checker
# that converts both with the same number cannot see the gap between them.
PASSES = 25.0
FPS    = PASSES

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

WALKSP = const(bas, 'WALKSP')           # px per PASS, the old unit -- kept
                                       # only because comments still quote it
KWALK64 = const(bas, 'KWALK64')        # sixty-fourths of a px per FRAME
# A RIDE IS ESCRISE FRAMES MINUS THE ANIMATION PHASE. The rider climbs 1 px
# a frame with the steps, from the floor to the one above, and the bottom step
# is 4 + escp px up when he gets on -- so a ride takes 36, 35, 34 or 33 frames
# depending on which of the four phases he boards in. The chase has to hold at
# the SLOWEST, so the pessimistic 36 is what is charged here (and 33 for the
# quarry, whose speed we are trying not to overstate).
#
# THESE ARE PASSES, NOT FRAMES, and the difference is deliberate. A rider is
# clocked by the step animation rather than by the frame delta (DESIGN.md 0f),
# so a ride takes 36 loop passes however long a pass is. Charging them as
# frames therefore UNDERSTATES both actors' ride time -- but Harry rides twice
# and Kelly (by lift) once, so it understates the quarry more, and the margin
# reported below stays on the safe side.
ESCRISE = const(bas, 'ESCRISE')
RIDE_SLOW = ESCRISE - 4                 # boarding on phase 0
RIDE_FAST = ESCRISE - 7                 # boarding on phase 3
TIMEL  = const(bas, 'TIMEL')
# A TIMER UNIT IS NOT A SECOND (DESIGN.md 0m). The round is TIMEL units of
# TICKFR frames, and the timer is the one thing here paced in real time.
TICKFR = const(bas, 'TICKFR')
ROUND  = TIMEL * TICKFR / 60.0

# THE ELEVATOR IS PART OF KELLY'S ROUTE AND LEAVING IT OUT DISTORTED THE GAME.
# This used to charge Kelly the full on-foot route -- four end-to-end traverses
# -- and nothing else. That is not a conservative assumption, it is a route no
# player takes: the shaft is on screen 3, which is ON THE WAY from his spawn to
# floor 1's escalator, and it carries him two floors for the price of a wait.
#
# Modelling only the foot route made the chase look 5 s tighter than it is, and
# that phantom tightness was being used to hold the quarry's speed down -- so
# the check was shaping the design, wrongly. Kelly is now charged the BETTER of
# the two routes, with the elevator's worst case: he arrives just as the car
# leaves and waits a full round trip.
ELWAIT = const(bas, 'ELWAIT')
ELMOVE = const(bas, 'ELMOVE')
ELSCR  = 3                              # draw_car / try_elev: `klsc <> 3`
ELX    = ELSCR * 256 + (const(bas, 'ELXL') + const(bas, 'ELXR')) // 2
# a full 0->2->0 round trip is the longest he can be made to wait, and the ride
# up stops at the middle floor on the way
EL_WAIT_WORST = 4 * ELMOVE + 4 * ELWAIT
EL_RIDE_UP    = 2 * ELMOVE + ELWAIT

# THE ACCUMULATOR'S CEILING, READ OUT OF THE SOURCE RATHER THAN ASSUMED.
#
# Harry's speed is a fraction spent as whole pixels: `hacc = hacc + hsp64`, then
# a run of `IF hacc > N THEN hspd = k : hacc = hacc - (N+1)` drain steps. EACH
# DRAIN CAN SPEND ONE WHOLE PIXEL, so the number of them is a hard cap on his
# speed no matter what the constant says.
#
# This file used to compute `hspd = sp4 / 4.0` and model whatever it was given.
# When the constant was set to 9 quarter-pixels against a two-drain accumulator,
# the runtime delivered a flat 2.0 px/pass and this check confidently reported
# 2.25 -- a bracket of three candidate speeds in which two rows were physically
# unreachable. The crook arrived two thirds of a screen short of his own escape
# and nothing in the build disagreed. A checker that can express a speed the
# machine cannot is worse than no checker, so the ceiling is parsed here.
#
# IT IS NOW ONE SHARED ROUTINE, `pace_step`, and every paced actor calls it --
# Harry, Kelly, each hazard kind and the bounce phase. So the ceiling read here
# is the ceiling for ALL of them, which is the point: one place to get wrong
# instead of four. The parse is anchored on the routine's label rather than on
# Harry's variable names, which is what it used to key off and what broke the
# moment the code moved.
mv = bas[bas.find('pace_step:'):]
if 'pace_step:' not in bas:
    sys.exit('checkchase: pace_step not found -- the shared accumulator has '
             'moved or been renamed, and its ceiling is now unmodelled')
DRAINS = len(re.findall(r"IF\s+pacc\s*>\s*\d+\s+THEN", mv[:600]))
um = re.search(r"IF\s+pacc\s*>\s*(\d+)\s+THEN", mv)
cm = re.search(r"IF\s+pfd\s*>\s*(\d+)\s+THEN", mv)
if not DRAINS or not um or not cm:
    sys.exit('checkchase: could not read the shared accumulator -- the source '
             'shape changed and the ceiling is now unmodelled')
UNIT = int(um.group(1)) + 1             # 4 for quarters, 64 for sixty-fourths
CLAMP = int(cm.group(1))                # frames of catch-up allowed in one pass

# Harry's per-Krook speed, in accumulator units: a base plus `IF krk > N` steps.
sk = bas[bas.find('start_krook:'):]
base = re.search(r"^\s*hsp64\s*=\s*(\d+)", sk, re.M)
if not base:
    sys.exit('checkchase: hsp64 base not found in start_krook')
bands = [(1, int(base.group(1)))]
for m in re.finditer(r"^\s*IF\s+krk\s*>\s*(\d+)\s+THEN\s+hsp64\s*=\s*(\d+)", sk, re.M):
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

def climb(lv, world_x, px_per_step, ride=None):
    """Reach the roof escape edge: running every leg end to end, riding each
    escalator.

    RETURNS WALKING AND RIDING SEPARATELY, BECAUSE THEY ARE NO LONGER IN THE
    SAME UNIT. Kelly is paced per loop PASS throughout, so both of his numbers
    are passes. Harry now walks by the frame DELTA -- one accumulate per elapsed
    frame -- so his walking is in FRAMES, while his escalator rides stay per
    pass, locked to the moving staircase (DESIGN.md 0f: a rider stepped by the
    delta drifts off the treads or makes the steps run backwards).

    Adding the two together and dividing by one rate, as this did, is exactly
    the units error CLAUDE.md warns about -- and it is invisible to a ratio
    test, because halving a number on both sides of a comparison leaves the
    comparison intact. The caller converts each in its own unit.
    """
    if ride is None:
        ride = RIDE_SLOW
    walk, rides, legs = 0.0, 0.0, []
    while lv < 3:
        side = esc[lv]
        if side > 1:
            sys.exit('checkchase: level %d has no working escalator' % lv)
        run = abs(BOARD[side] - world_x)
        walk += run / px_per_step
        rides += ride
        legs.append((lv, run))
        world_x = LAND[side]
        lv += 1
    run = abs(ROOF_ESCAPE - world_x)
    walk += run / px_per_step
    legs.append((3, run))
    return walk, rides, legs


def climb_by_lift(world_x, px_per_frame):
    """Kelly's other route: run to the shaft, ride floor 1 to floor 3, then
    take floor 3's escalator to the roof. The car does not serve the roof, so
    the last climb is on foot either way.

    
    RUNNING IN FRAMES, WAITING AND RIDING IN PASSES, returned separately.

    They used to be added together, which was correct while Kelly walked once
    per pass -- everything shared a unit. Now that he walks by elapsed frames
    they cannot be summed here, and summing them anyway is exactly the units
    error that made the original defect invisible: halving a number on both
    sides of a comparison leaves the comparison intact, so every relative
    assertion stays true and nothing fails.
    """
    walk = abs(ELX - world_x) / px_per_frame             # to the shaft
    rides = EL_WAIT_WORST + EL_RIDE_UP                   # wait, then ride
    x = ELX
    side = esc[2]                                        # floor 3's escalator
    if side > 1:
        return None, None, []
    legs = [(0, abs(ELX - world_x)), (2, abs(BOARD[side] - x))]
    walk += abs(BOARD[side] - x) / px_per_frame
    rides += RIDE_SLOW
    x = LAND[side]
    run = abs(ROOF_ESCAPE - x)
    walk += run / px_per_frame
    legs.append((3, run))
    return walk, rides, legs


# BOTH ACTORS ARE NOW THE SAME SHAPE: walking in real frames, riding in loop
# passes, each converted at its own rate. Kelly used to be per-pass end to end,
# so his two numbers could be added before converting; they cannot any more, and
# adding them would be a units error a ratio test cannot see -- the one that made
# the original defect invisible (see the header).
def kelly_time(walk, rides):
    """Walking in real frames, riding in loop passes, each in its own rate."""
    return walk / 60.0 + rides / FPS


def harry_time(walk, rides):
    """Walking in real frames, riding in loop passes, each in its own rate."""
    return walk / 60.0 + rides / FPS

kelly_lv = assign(sk, 'klv'); kelly_x = assign(sk, 'klsc') * 256 + assign(sk, 'klx')
harry_lv = assign(sk, 'hlv'); harry_x = assign(sk, 'hsc')  * 256 + assign(sk, 'hx')

KWALK = KWALK64 / 64.0                  # px per frame, as the machine spends it
kfwalk, kfride, kflegs = climb(kelly_lv, kelly_x, KWALK)
kfoot = kelly_time(kfwalk, kfride)
klwalk, klride, kllegs = climb_by_lift(kelly_x, KWALK)
print('Kelly  %.2f px/frame, spawns lv%d x%d' % (KWALK, kelly_lv, kelly_x))
print('       on foot   %s px  ->  %5.1f s'
      % ('+'.join(str(r) for _, r in kflegs), kfoot))
if klwalk is not None and kelly_lv == 0:
    klift = kelly_time(klwalk, klride)
    print('       by lift   %s px + a worst-case %.1f s wait  ->  %5.1f s'
          % ('+'.join(str(r) for _, r in kllegs),
             (EL_WAIT_WORST + EL_RIDE_UP) / FPS, klift))
    kt = min(kfoot, klift)
    which = 'the lift' if klift < kfoot else 'on foot'
else:
    kt, which = kfoot, 'on foot'
# ALREADY SECONDS. kelly_time converts, and this divided by FPS a second time --
# which reported the whole climb as 2.5 s and still said the chase resolved,
# because Kelly arriving impossibly early passes every test in this file.
print('       best %s: %5.1f s' % (which, kt))
print()

fail = []
for i, (first, sp16) in enumerate(bands):
    last  = bands[i + 1][0] - 1 if i + 1 < len(bands) else None
    label = 'Krooks %d-%d' % (first, last) if last else 'Krooks %d+' % first
    want  = sp16 / float(UNIT)
    hspd  = min(want, DRAINS)
    if want > DRAINS:
        fail.append('%s: the speed says %.4f px/pass but the accumulator has '
                    'only %d drain steps, so the crook can never exceed %d. '
                    'Add a drain or lower the constant -- as written he runs '
                    'at %d and every number below is fiction.'
                    % (label, want, DRAINS, DRAINS, DRAINS))
    # the quarry gets the FAST ride and Kelly the slow one, so the margin
    # reported is the worst case rather than the average
    hwalk, hride, hlegs = climb(harry_lv, harry_x, hspd, RIDE_FAST)
    ht = harry_time(hwalk, hride)
    margin = ht - kt
    print('%-14s Harry %.2f px/frame, route %s px' %
          (label, hspd, '+'.join(str(r) for _, r in hlegs)))
    print('%-14s escapes at %5.1f s (round %.0f s), Kelly is there %5.1f s earlier'
          % ('', ht, ROUND, margin))
    if hspd >= WALKSP:
        fail.append('%s: Harry %.2f px/frame is not slower than Kelly %d -- '
                    'he cannot be caught once he flees' % (label, hspd, WALKSP))
    if margin < MARGIN:
        fail.append('%s: Kelly beats Harry to the roof by only %.1f s '
                    '(need %.1f) -- one obstacle hit makes the round '
                    'unwinnable' % (label, margin, MARGIN))
    if ht >= ROUND:
        fail.append('%s: Harry needs %.1f s to escape but the round is %d s -- '
                    'he can never escape, so that loss condition is dead'
                    % (label, ht, ROUND))
    print()

if fail:
    for f in fail:
        print('FAIL  ' + f)
    sys.exit(1)
print('OK: the chase resolves at every Krook band.')
