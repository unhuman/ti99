#!/usr/bin/env python3
"""Offline simulation of RALLY-X player movement, asserted against the map.

Ports `drive_step` / `at_center` / `start_rot` / `start_turn` / `sweep_step`
from src/RALLYX.bas and drives the car through the REAL char map with random
stick input, checking three invariants on every movement chunk:

  1. the car's cell is always ROAD -- never a wall or a tree
  2. the CROSS axis stays 16-aligned: driving vertically, px is a multiple of
     16; driving horizontally, py is. The car may never leave the lane grid.
  3. the heading only changes at a cell centre (a reverse excepted -- it flips
     along the same axis, so it cannot break the grid)

INVARIANT 2 IS THE ONE THAT BROKE, and it is why this exists. A 90-degree
turn begun at a cell centre used to let the frame's REMAINING pixel steps run
in the old direction, finishing the turn 1-3 px off-grid. After that the
cross-axis coordinate was never a multiple of 16 again, `at_center` never
fired, `blocked` stayed 0 -- and the car drove through every wall. That is
minutes of play to stumble into and one assertion to catch.

This reads the SAME data the game reads: the per-maze char map (map2_1.bas)
sampled at each cell's top-left quadrant, exactly as `probe` does. It
deliberately does NOT use map0.bas -- genmap.py still writes that logical map
but nothing in the cart includes it, so testing against it would be testing
something that does not ship.

Run from assets/:  C:\\cygwin64\\bin\\python3.9.exe simdrive.py [runs]
Exit code is non-zero on any violation, so a build script can gate on it.
"""
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

# --- constants, mirrored from src/RALLYX.bas ------------------------------
ROADCH = 113            # codes >= this are drivable
PSPD = 24               # player speed, 1/16 px per frame (1.5 px/f)
ROTRT = 5               # cosmetic sweep rate (90-degree turn, and enemies)
TURNRT = 3              # blocking sweep rate (180-degree reverse)
STRIDE = 68             # char map row stride
CELLS_W, CELLS_H = 34, 58


def data_block(path, label):
    t = open(os.path.join(SRC, path)).read()
    m = re.search(r"^%s:\s*$" % label, t, re.M)
    if not m:
        raise KeyError(label)
    vals = []
    for line in t[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.upper().startswith("DATA BYTE"):
            break
        for v in s[len("DATA BYTE"):].split("'")[0].split(","):
            v = v.strip()
            if v:
                vals.append(int(v[1:], 16) if v.startswith("$") else int(v))
    return vals


CHARMAP = data_block("map2_1.bas", "map2_1")
assert len(CHARMAP) == STRIDE * 116, "map2_1 is %d bytes" % len(CHARMAP)
START_R, START_C = data_block("items.bas", "start_data_1")[:2]


class Violation(Exception):
    pass


class Car(object):
    """One pass of the main loop is `pass_once`. Names match the source."""

    def __init__(self):
        self.px = START_C * 16
        self.py = START_R * 16
        self.dir = self.qdir = 0        # 0 N, 1 E, 2 S, 3 W -- restart: dir 0
        self.ang = 0                    # visual heading, 0-7
        self.turning = self.rotv = self.blocked = 0
        self.tang = self.rstep = self.trot = 0
        self.acc = 0
        self.pqd = 255                  # force the first at_center to probe
        self.pdr = 255
        self.lcr, self.lcc = START_R, START_C

    # --- probe: cell TYPE from the char map's top-left quadrant -----------
    def probe(self, cr, cc, d):
        tr, tc = cr, cc
        if d == 0:
            tr -= 1
        elif d == 1:
            tc += 1
        elif d == 2:
            tr += 1
        elif d == 3:
            tc -= 1
        assert 0 <= tr < CELLS_H and 0 <= tc < CELLS_W, \
            "probe left the map at (%d,%d) -- the border ring should have stopped it" % (tr, tc)
        return CHARMAP[tr * STRIDE * 2 + tc * 2]

    # --- rotation ---------------------------------------------------------
    def set_sweep(self):
        self.tang = self.qdir * 2
        self.rstep = 7 if ((self.tang - self.ang) & 7) > 4 else 1
        self.trot = 0

    def start_turn(self):               # 180: rotates IN PLACE, costs time
        self.set_sweep()
        if self.tang == self.ang:
            return
        self.turning = 1
        self.rotv = 0

    def start_rot(self):                # 90: heading commits, sweep is cosmetic
        # INVARIANT 3, checked where it actually matters. A 90-degree turn
        # commits the heading immediately, so it MUST happen on a cell centre
        # -- turning between centres is exactly what threw the car off the
        # lane grid before. (Checking this once per pass instead would be
        # wrong: the car can reach a centre mid-pass and turn there legally.)
        if (self.px & 15) or (self.py & 15):
            raise Violation("90-degree turn away from a cell centre: px=%d py=%d"
                            % (self.px, self.py))
        self.set_sweep()
        self.dir = self.qdir
        if self.tang == self.ang:
            return
        self.rotv = 1

    def sweep_step(self, srt, fd):
        self.trot += fd
        if self.trot < srt:
            return
        self.trot = 0
        self.ang = (self.ang + self.rstep) & 7

    def rot_step(self, fd):
        self.sweep_step(ROTRT, fd)
        if self.ang == self.tang:
            self.rotv = 0

    def turn_step(self, fd):
        self.sweep_step(TURNRT, fd)
        if self.ang != self.tang:
            return
        self.turning = 0
        self.dir = self.tang // 2
        self.blocked = 0
        self.pqd = 255          # invalidate at_center's cache -- see below

    # --- per-cell decisions ----------------------------------------------
    def at_center(self):
        cr, cc = self.py // 16, self.px // 16
        smkf = 1 if (self.lcr != cr or self.lcc != cc) else 0
        if smkf:
            self.lcr, self.lcc = cr, cc
        # the (cell, dir, qdir) cache: nothing has changed, nothing to decide
        if smkf == 0 and self.qdir == self.pqd and self.dir == self.pdr:
            return
        self.pqd, self.pdr = self.qdir, self.dir
        if self.qdir != self.dir:
            if self.probe(cr, cc, self.qdir) >= ROADCH:
                self.start_rot()
        if self.turning == 1:
            self.blocked = 1
            return
        self.blocked = 1 if self.probe(cr, cc, self.dir) < ROADCH else 0

    # --- movement: boundary to boundary, never per pixel ------------------
    def drive_step(self, fd, check):
        self.acc += PSPD * fd
        steps = self.acc // 16
        self.acc &= 15
        while steps:
            if (self.px & 15) == 0 and (self.py & 15) == 0:
                self.at_center()
            if self.blocked:
                return
            if self.dir == 0:
                pmk = self.py & 15
            elif self.dir == 1:
                pmk = 16 - (self.px & 15)
            elif self.dir == 2:
                pmk = 16 - (self.py & 15)
            else:
                pmk = self.px & 15
            if pmk == 0:
                pmk = 16
            if pmk > steps:
                pmk = steps
            if self.dir == 0:
                self.py -= pmk
            elif self.dir == 1:
                self.px += pmk
            elif self.dir == 2:
                self.py += pmk
            else:
                self.px -= pmk
            check(self)
            steps -= pmk

    def pass_once(self, fd, stick, check):
        # the stick is a HELD request: centring it cancels a pending turn
        self.qdir = self.dir if stick is None else stick
        if self.turning == 0 and self.qdir == ((self.dir + 2) & 3):
            self.start_turn()
        if self.turning == 1:
            self.turn_step(fd)
        else:
            self.drive_step(fd, check)
        if self.rotv:
            self.rot_step(fd)


def run(seed, passes=20000):
    random.seed(seed)
    car = Car()
    state = {}

    def check(c):
        cr, cc = c.py // 16, c.px // 16
        cell = CHARMAP[cr * STRIDE * 2 + cc * 2]
        if cell < ROADCH:
            raise Violation("car on NON-ROAD cell (%d,%d) code %d" % (cr, cc, cell))
        cross = c.px if c.dir in (0, 2) else c.py
        if cross & 15:
            raise Violation("car OFF-GRID: dir %d, px=%d py=%d (cross axis %d not 16-aligned)"
                            % (c.dir, c.px, c.py, cross))

    for p in range(passes):
        # a human holds a direction for a while, then lets go
        stick = state.get("stick")
        if random.random() < 0.12:
            stick = random.choice([None, 0, 1, 2, 3])
            state["stick"] = stick
        fd = random.choice([2, 2, 2, 2, 3, 4, 6])   # 30 Hz lock, with catch-up
        try:
            car.pass_once(fd, stick, check)
        except Violation as e:
            return "seed %d pass %d: %s" % (seed, p, e)
    return None


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    print("start cell (%d,%d), map %d x %d cells" % (START_R, START_C, CELLS_W, CELLS_H))
    bad = 0
    for s in range(n):
        err = run(s)
        if err:
            print("FAIL", err)
            bad += 1
    if bad:
        print("%d/%d runs FAILED" % (bad, n))
        sys.exit(1)
    print("OK: %d runs x 20000 passes -- car never left the roads or the lane grid" % n)
