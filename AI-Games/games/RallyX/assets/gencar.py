#!/usr/bin/env python3
"""Generate RALLY-X's 16x16 top-down F1 car in EIGHT headings (45 deg apart).

One shape definition is drawn at each heading, so every frame is the same
car -- rotating pixel art by 45 degrees turns to mush at this size, and
hand-drawing the diagonals separately makes them look like a different
vehicle.

The car is drawn ~12x12 inside the 16x16 sprite box on purpose: a 12-long,
9-wide car spans (12+9)/sqrt(2) ~= 14.8 px on the diagonal, so the 45-degree
frames fit without clipping their wheels. (At the old 16-px size the
diagonals clipped, which is what made them unreadable.)

Shape is defined in CAR SPACE: u = along the axis, + toward the nose;
v = perpendicular. Wheels are drawn as axis-aligned 3x3 blocks placed at
the rotated wheel positions -- rotated wheel boxes turn to mush, square
blocks read as wheels at every angle.

Frame order matches the code's `ang` variable: 0=N, 1=NE, 2=E, 3=SE,
4=S, 5=SW, 6=W, 7=NW. Emitted in TMS9918 16x16 sprite order (left half
rows 0-15, then right half rows 0-15) -- do NOT reorder.

Run from assets/: C:\\cygwin64\\bin\\python3.9.exe gencar.py
"""
import math

NAMES = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# car-space geometry (see module docstring)
BODY_BACK, BODY_NOSE = -5.0, 5.6
BODY_HALF, NOSE_HALF, NOSE_FROM = 2.4, 1.4, 2.6
WING_BACK, WING_FRONT, WING_HALF = -5.6, -4.4, 3.6
# wheels sit far enough outboard to leave a 1-px gap either side of the
# body; without it they merge into it and the car reads as a solid bar
WHEEL_U, WHEEL_V = 3.2, 4.4


def frame(theta_deg):
    th = math.radians(theta_deg)
    # heading vector: theta 0 = up (screen -y), rotating clockwise
    hx, hy = math.sin(th), -math.cos(th)
    g = [["."] * 16 for _ in range(16)]

    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            u = dx * hx + dy * hy          # along the car's axis
            v = -dx * hy + dy * hx         # perpendicular
            if BODY_BACK <= u <= BODY_NOSE:
                half = BODY_HALF if u < NOSE_FROM else NOSE_HALF
                if abs(v) <= half:
                    g[y][x] = "#"
            if WING_BACK <= u <= WING_FRONT and abs(v) <= WING_HALF:
                g[y][x] = "#"

    for wu in (WHEEL_U, -WHEEL_U):
        for wv in (WHEEL_V, -WHEEL_V):
            cx = 7.5 + wu * hx - wv * hy
            cy = 7.5 + wu * hy + wv * hx
            ix, iy = int(round(cx)), int(round(cy))
            for yy in range(iy - 1, iy + 2):
                for xx in range(ix - 1, ix + 2):
                    if 0 <= xx < 16 and 0 <= yy < 16:
                        g[yy][xx] = "#"

    return ["".join(r) for r in g]


frames = [frame(i * 45) for i in range(8)]

for n, f in zip(NAMES, frames):
    print(n)
    for row in f:
        print("  " + row)
    print()

print("--- paste into car_bitmaps: ---")
for n, f in zip(NAMES, frames):
    left, right = [], []
    for row in f:
        bits = int("".join("1" if ch == "#" else "0" for ch in row), 2)
        left.append(bits >> 8)
        right.append(bits & 0xFF)
    print("\t' %s" % n)
    for half in (left, right):
        print("\tDATA BYTE " + ",".join("$%02X" % b for b in half))
