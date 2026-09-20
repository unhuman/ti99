#!/usr/bin/env python3
"""The crouch as the VDP assembles it, and how asymmetric it is.

THE THREE BOXES ARE STAGGERED, like the run's: the helmet is drawn at y-10, the
face at y-5 and the body at y+11, and genart shifts each band inside its own
box by exactly the complementary amount. Composing them here with those offsets
is the only way to see the figure -- the three grids read separately say nothing
about how they stack, which is how a head ends up sunk into a body.

IT ALSO SHOWS WHY THE STAGGER IS WORTH IT. The VDP counts sprite BOXES per
scanline, not the ink in them, so three boxes at one y cost three on every line
the figure touches. Spread out, the face's box and the body's never share a
line and nothing carries more than two -- which leaves room for two obstacles
inside the limit of four.

THE LAST NUMBER IS THE ONE TO WATCH. A crouch that is its own mirror reads as
the figure being SQUASHED rather than as him dropping and still looking where he
is going; an earlier crouch was rejected for exactly that, and an upright head
makes it easy to reintroduce, because a head centred on a symmetric squat
mirrors to itself.

Run:  python3 showduck.py
"""
import os
import sys

ASSETS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ASSETS)
import genart as g                                         # noqa: E402

# (art, the y offset draw_actors uses, the letter to print it as)
BANDS = [("KELLY_DBODY", 11, "B"), ("KELLY_DFACE", -5, "F"),
         ("KELLY_DHAT", -10, "H")]
PAD = 12                    # room above the figure top for the hat's box


def rows(block):
    return [r for r in block.split("\n") if len(r) == 16]


def mirror(block):
    return "\n" + "\n".join(r[::-1] for r in rows(block)) + "\n"


def compose(flip):
    fig = [["."] * 16 for _ in range(40)]
    for name, off, ink in BANDS:
        art = getattr(g, name)
        for y, r in enumerate(rows(mirror(art) if flip else art)):
            for x, c in enumerate(r):
                if c != ".":
                    fig[y + off + PAD][x] = ink
    return fig


def main():
    right, left = compose(False), compose(True)
    ink = [y for y in range(40) if set("".join(right[y])) != {"."}]

    print("H = black helmet   F = skin   B = blue body")
    print()
    print("      facing RIGHT        facing LEFT (mirrored)")
    for y in ink:
        print("  %2d  %s     %s"
              % (y - PAD, "".join(right[y]), "".join(left[y])))

    # boxes, not ink: what the per-scanline limit actually counts
    spans = [(off, off + 15) for _n, off, _i in BANDS]
    worst = max(sum(1 for lo, hi in spans if lo <= y <= hi)
                for y in range(-PAD, 30))
    diff = sum(1 for y in range(40)
               for a, b in zip(right[y], left[y]) if a != b)

    print()
    print("  height     %d px, rows %d..%d" % (len(ink), ink[0] - PAD,
                                               ink[-1] - PAD))
    print("  scanlines  %d sprites at worst (3 when the boxes shared a y)"
          % worst)
    print("  mirror     %d px differ -- near zero would read as squashed"
          % diff)
    return 0


if __name__ == "__main__":
    sys.exit(main())
