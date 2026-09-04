#!/usr/bin/env python3
"""Rebuild each escalator animation phase FROM THE CHARACTERS, and check it.

The first animation shipped corrupt because it rotated every 8x8 cell inside
its own box. That is valid only when a cell is a whole repeating tile; here the
band is a diagonal sliced across cell boundaries, so wrapping pixels within a
cell tears it away from its neighbours. Nothing caught it because nothing ever
reassembled the flight the way the VDP does.

So this does exactly that: it takes the phase patterns that will be written to
the pattern table, lays them out through the placement grid, and checks the
result is still a coherent flight -- every rail pixel continuous, and the step
count unchanged. It also writes a strip of all four phases to look at.

Run:  python3 checkesc.py [out.png]      exits non-zero if a phase is broken
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")


def check_define():
    """The DEFINE CHAR range must be exactly the run genart animated.

    Two ways this goes wrong, neither of which shows up as an error:
    a range too SHORT freezes the cells past its end -- which is what left
    the composite top steps standing still while the rest of the flight
    climbed -- and a range too LONG overwrites whatever follows the block
    with step patterns. The base and the count live in the source and the
    block is generated, so nothing but this ties the two together.
    """
    src = open(BAS, encoding="utf-8").read()
    found = re.findall(r"DEFINE CHAR (\d+),(\d+),esc_ph([we])(\d)", src)
    bad = []
    # one per phase per direction: the flight is written a half at a time
    want = {"w": (g.ESC_FIRST, g.ESC_ANIM_W),
            "e": (g.ESC_FIRST + g.ESC_ANIM_W, g.ESC_ANIM_E)}
    if len(found) != 2 * g.PHASES:
        bad.append("expected %d `DEFINE CHAR ...,esc_ph{w,e}N` statements "
                   "(one per phase per direction), found %d"
                   % (2 * g.PHASES, len(found)))
    for base, count, side, phase in found:
        wb, wn = want[side]
        if int(base) != wb or int(count) != wn:
            bad.append("KEYSTONE.bas has `DEFINE CHAR %s,%s,esc_ph%s%s` but "
                       "genart.py puts that half at chars %d-%d, so it should "
                       "be `DEFINE CHAR %d,%d,esc_ph%s%s`"
                       % (base, count, side, phase, wb, wb + wn - 1,
                          wb, wn, side, phase))
    return bad


def assemble(grid, cells):
    """Lay the characters out through the grid, as the name table will."""
    W, H = g.FLIGHT_COLS * 8, g.FLIGHT_ROWS * 8
    px = [[0] * W for _ in range(H)]
    for r in range(g.FLIGHT_ROWS):
        for c in range(g.FLIGHT_COLS):
            i = grid[r][c]
            if i is None:
                continue
            for y in range(8):
                bits = cells[i][y]
                for x in range(8):
                    if bits & (0x80 >> x):
                        px[r * 8 + y][c * 8 + x] = 1
    return px


def check_thirds():
    """The roof and shop-floor crossings must never want the same screen third.

    They share their characters -- same pixels, different surface behind them --
    and are told apart ONLY by the per-third colour table, which is what lets
    the west screen animate six characters a pass instead of nine. If a layout
    change ever put a roof crossing and a shop-floor crossing in the same third
    the two would have to be one colour, and one of them would be painted onto
    the wrong surface. Nothing else in the build would notice: it is a colour,
    not an error.

    A flight's cap lands on the FLOOR ROW of the band above it, which is that
    band's top row plus 4. Bands are read out of the source so this follows a
    layout change rather than assuming one.
    """
    src = open(BAS, encoding="utf-8").read()
    rows = []
    for m in re.finditer(r"#bdst\((\d)\) = (\d+)", src):
        rows.append((int(m.group(1)), int(m.group(2)) // 32))
    rows = dict(rows)
    if len(rows) != 4:
        return ["could not read #bdst() -- the band rows are unknown, so the "
                "per-third colour assumption is unchecked"]
    m = re.search(r"stor_esc:.*?\n\s*DATA BYTE\s+([0-9,\s]+)",
                  open(os.path.join(HERE, "..", "src", "store.bas"),
                       encoding="utf-8").read(), re.S)
    if not m:
        return ["stor_esc not found"]
    side = [int(v) for v in m.group(1).split(",")][:4]

    deck, bar = set(), set()
    for lv in range(3):
        if side[lv] > 1:
            continue
        cap_row = rows[lv + 1] + 4          # the floor row of the band above
        third = cap_row // 8
        (deck if lv + 1 == 3 else bar).add((third, cap_row, lv))
    clash = {t for t, _r, _l in deck} & {t for t, _r, _l in bar}
    if clash:
        return ["a roof crossing and a shop-floor crossing both land in screen "
                "third %s, so they cannot share characters: %s"
                % (sorted(clash), sorted(deck | bar))]
    return []


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "esc.png")
    bad = check_define() + check_thirds()
    frames = []

    for name, grid, phases, mirrored in (
            ("west", g.ESC_W_GRID, g.ESC_W_PHASES, False),
            ("east", g.ESC_E_GRID, g.ESC_E_PHASES, True)):
        for p in range(g.PHASES):
            cells = phases[p]
            px = assemble(grid, cells)
            frames.append(px)

            # THE REAL INVARIANT: laying the characters out through the grid
            # must reproduce the source bitmap EXACTLY. Anything that tears a
            # cell away from its neighbours shows up here as a pixel mismatch,
            # which an ink count or a rail probe can both miss.
            want = g._flight_bitmap(2 * p)
            if mirrored:
                want = g._mirror_bitmap(want)
            for y in range(g.FLIGHT_H):
                for x in range(g.FLIGHT_W):
                    if px[y][x] != want[y][x]:
                        bad.append("%s phase %d: round-trip differs at (%d,%d)"
                                   % (name, p, x, y))
                        break
                else:
                    continue
                break

    try:
        from PIL import Image
        W, H = g.FLIGHT_W, g.FLIGHT_H
        im = Image.new("RGB", (W, H * len(frames) + 2 * (len(frames) - 1)),
                       (33, 200, 66))
        for i, px in enumerate(frames):
            for y in range(H):
                for x in range(W):
                    if px[y][x]:
                        im.putpixel((x, i * (H + 2) + y), (255, 255, 255))
        im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(out)
        print("wrote %s  (west 0-3 then east 0-3)" % os.path.normpath(out))
    except ImportError:
        pass

    if bad:
        for b in bad:
            print("FAIL " + b)
        return 1
    print("OK  all %d phases reassemble into a continuous flight; the roof "
          "and shop-floor crossings are in different screen thirds so they "
          "share characters; the west half is DEFINE CHAR %d,%d and the east "
          "%d,%d, together the %d cells that move"
          % (g.PHASES, g.ESC_FIRST, g.ESC_ANIM_W,
             g.ESC_FIRST + g.ESC_ANIM_W, g.ESC_ANIM_E, g.ESC_ANIM_N))
    return 0


if __name__ == "__main__":
    sys.exit(main())
