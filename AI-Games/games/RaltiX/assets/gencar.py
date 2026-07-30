#!/usr/bin/env python3
"""Generate RaltiX's 16x16 top-down F1 car sprite, 4 rotations.

Prints an ASCII preview of each frame plus the CVBasic DATA BYTE lines to
paste into `car_bitmaps:` in src/RALTIX.bas. Emitted in TMS9918 16x16 sprite
order: left half rows 0-15, then right half rows 0-15 (do NOT reorder -- see
the sprite-order note in DESIGN.md section 5).

The 'up' design is deliberately LEFT-RIGHT SYMMETRIC so its 90-degree
rotations stay readable: an earlier asymmetric attempt (rear wing spanning
the full width) rotated into a ragged single-pixel edge column and read as
a blob. Wheels come out 2 wide x 4 tall travelling vertically and 4 x 2
horizontally, which is what a car actually looks like from above.

Run from assets/: C:\\cygwin64\\bin\\python3.9.exe gencar.py
"""

up = [
    ".......##.......",
    "......####......",
    ".##...####...##.",
    ".##...####...##.",
    ".##..######..##.",
    ".##..######..##.",
    ".....######.....",
    "....########....",
    "....########....",
    ".....######.....",
    ".##..######..##.",
    ".##..######..##.",
    ".##...####...##.",
    ".##...####...##.",
    "..############..",
    "................",
]

def rot90(g):
    """Rotate a 16x16 ASCII grid 90 degrees clockwise."""
    return ["".join(g[15 - c][r] for c in range(16)) for r in range(16)]

frames = {"up": up}
frames["right"] = rot90(up)
frames["down"] = rot90(frames["right"])
frames["left"] = rot90(frames["down"])
order = ("up", "right", "down", "left")

for n in order:
    print(n)
    for row in frames[n]:
        print("  " + row)
    print()

print("--- paste into car_bitmaps: ---")
for n in order:
    left, right = [], []
    for row in frames[n]:
        bits = int("".join("1" if ch == "#" else "0" for ch in row), 2)
        left.append(bits >> 8)
        right.append(bits & 0xFF)
    print("\t' %s" % n)
    for half in (left, right):
        print("\tDATA BYTE " + ",".join("$%02X" % b for b in half))
