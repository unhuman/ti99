#!/usr/bin/env python3
"""Print the generated flight as ASCII, in the reference's own orientation.

The point is to lay it beside the ColecoVision dump and read the difference,
rather than deciding by eye that it "looks like" a staircase. _flight_bitmap
mirrors its result so our west flight has its head on the left; this undoes
that, so what is printed is directly comparable to the screenshot.
"""
import genart as g

px = [list(reversed(r)) for r in g._flight_bitmap(0)]   # back to head-right

print("generated flight, %d x %d" % (g.FLIGHT_W, g.FLIGHT_H))
print("    " + "".join(str(i // 10 % 10) for i in range(g.FLIGHT_W)))
print("    " + "".join(str(i % 10) for i in range(g.FLIGHT_W)))
for y, row in enumerate(px):
    print("%3d %s" % (y, "".join("#" if v else "." for v in row)))
