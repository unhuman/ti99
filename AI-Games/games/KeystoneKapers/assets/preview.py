#!/usr/bin/env python3
"""Render a store screen offline, from the SHIPPED data, as a PNG.

Judging pixel art from emulator screenshots is unreliable here -- the window
scales, the capture is a lottery on a busy desktop, and driving the TI menu to
reach the right screen costs minutes per look. This paints the real thing from
`src/art.bas` and `src/store.bas` (the same bytes the cartridge carries) so a
palette change can be checked in one second.

It renders what the NAME TABLE would hold: the four band templates for one
screen, in their real characters and their real per-scanline colours. Sprites
are not drawn -- this is for the store, not the actors.

Run:  python3 preview.py [screen 0-7] [out.png]
"""

import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")

# TMS9918 palette, approximate sRGB
PAL = [
    (0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120),
    (84, 85, 237), (125, 118, 252), (212, 82, 77), (66, 235, 245),
    (252, 85, 84), (255, 121, 120), (212, 193, 84), (230, 206, 128),
    (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255),
]


def read_bytes(path, label):
    """Pull one DATA BYTE block out of a .bas file by label."""
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"^%s:.*?$" % re.escape(label), txt, re.M)
    if not m:
        raise SystemExit("label %s not found in %s" % (label, path))
    out = []
    for line in txt[m.end():].split("\n"):
        s = line.strip()
        if not s or s.startswith("'"):
            continue
        if not s.startswith("DATA BYTE"):
            break
        for tok in s[9:].split(","):
            tok = tok.strip()
            out.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    return out


def draw_scanner(px, art, store):
    """Paint the radar into rows 21-23, the way the game paints it.

    THE ROWS COME OUT OF THE SOURCE, not out of a copy of the layout kept
    here: checkscan.py already evaluates scan_base and friends, so this
    imports that rather than writing the band arithmetic down a third time.
    A previewer with its own idea of the layout would keep showing the old
    one after a change, which is the failure it exists to prevent.
    """
    import checkscan as cs
    import genart as g

    rt = cs.routines()
    scol = read_bytes(art, "scan_col3")
    esc = read_bytes(store, "stor_esc")        # 0 = west end, 1 = east
    X0, Y0 = 8 * 8, 21 * 8                     # cols 8-23, rows 21-23

    def put(x, y, w, fg):
        cb = scol[y]
        for i in range(w):
            if 0 <= x + i < 128:
                px[Y0 + y][X0 + x + i] = PAL[cb >> 4] if fg else PAL[cb & 15]

    for y in range(24):                        # the dark-green ground
        put(0, y, 128, False)

    for lv in range(4):
        fbase = cs.run(rt, "scan_base", {"fl": lv})["fbase"]

        row = floor = None
        for ln in rt["scan_furn"]:
            ln = cs.COMMENT.sub("", ln.rstrip())
            m = re.match(r"^	+say = fbase(?: \+ (\d+))?$", ln)
            if m:
                row = fbase + int(m.group(1) or 0)
            elif "VPOKE #sda,255" in ln:
                floor = row
        put(0, floor, 128, True)

        if lv < 3:                             # that floor's up escalator
            # Three steps down the band's air, leaning the way it climbs, and
            # BLACK -- scan_escc colours the flight's own character, so taking
            # the colour from the table here would show it grey and hide the
            # very thing that separates it from the lift car.
            for k, x in enumerate((0, 2, 4) if esc[lv] == 0 else (126, 124, 122)):
                for i in range(2):
                    if 0 <= x + i < 128:
                        px[Y0 + fbase + k][X0 + x + i] = PAL[g.BLACK]

    # THE CAR AND THE TWO ACTORS ALL FILL THE AIR -- three rows each, none of
    # them touching the floor line on row 3.
    #
    # The actors are painted in their OWN colours rather than the table's,
    # because that is what the game does: the band is grey in scan_col3 and
    # scan_mark recolours the character an actor is standing in. A previewer
    # that took the colour from the table alone would show two grey markers
    # and hide exactly the thing that makes them readable.
    KOP, CROOK = PAL[g.BLACK], PAL[g.WHITE]

    def block(x, y0, w, col):
        for k in range(3):
            for i in range(w):
                if 0 <= x + i < 128:
                    px[Y0 + y0 + k][X0 + x + i] = col

    for k in range(3):
        put(56, cs.run(rt, "scan_base", {"fl": 1})["fbase"] + k, 5, True)
    block(40, cs.run(rt, "scan_base", {"fl": 0})["fbase"], 3, KOP)
    block(88, cs.run(rt, "scan_base", {"fl": 2})["fbase"], 3, CROOK)


def main():
    scr = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "preview.png")

    art = os.path.join(SRC, "art.bas")
    store = os.path.join(SRC, "store.bas")
    pat = read_bytes(art, "store_pat")
    col = read_bytes(art, "store_col")
    tpl = read_bytes(store, "stor_tpl")
    idx = read_bytes(store, "stor_ix")

    W, H = 32 * 8, 24 * 8
    px = [[(0, 0, 0)] * W for _ in range(H)]

    # HOW MANY STORE CHARS THERE ARE COMES FROM THE DATA, never a literal. This
    # was hardcoded as "96..115" and silently went stale the moment the char
    # table grew: the extra codes were skipped and painted BLACK, which looked
    # like a bug in the new artwork rather than in the previewer.
    last = 96 + len(pat) // 8 - 1

    # esc_deck: (char, 8 colour bytes) x N -- third 0's override
    dk = read_bytes(art, "esc_deck")
    deck = {}
    for k in range(0, len(dk), 9):
        deck[dk[k]] = dk[k + 1:k + 9]

    # THE NAME TABLE IS BUILT FIRST AND PAINTED SECOND, because not every cell
    # comes from a template. `beam_tops` in the source stamps a support beam's
    # top into the slab row of the band ABOVE it after the bands are blitted --
    # a row no template owns -- so a previewer that paints straight out of the
    # templates shows the three-pixel gap the stamp exists to close.
    name = [[0] * 32 for _ in range(24)]
    for lv in range(4):
        top = 1 + (3 - lv) * 5            # band's top screen row
        base = idx[lv * 8 + scr] * 160
        for r in range(5):
            for c in range(32):
                name[top + r][c] = tpl[base + r * 32 + c]

    pil = read_bytes(store, "stor_pil")
    for lv in range(2):                   # bands 0 and 1 only, as the game does
        top = 1 + (3 - lv) * 5
        base = idx[lv * 8 + scr] * 4
        for k in range(4):
            c = pil[base + k]
            if c:
                name[top - 1][c] = g.CODES["SLABP"]

    for row in range(24):
        for c in range(32):
                code = name[row][c]
                top, r = row, 0
                if code < 96 or code > last:
                    continue
                o = (code - 96) * 8
                for line in range(8):
                    bits = pat[o + line]
                    cb = col[o + line]
                    # THE COLOUR TABLE IS PER SCREEN THIRD, and one character
                    # relies on it: a flight crossing the roof shows the deck
                    # behind it and one crossing a shop floor shows the bar,
                    # from the SAME pixels (genart's ESC_DECK). Third 0 is
                    # repainted at setup, so model that here or this previewer
                    # quietly shows the wrong surface on the roof.
                    if (top + r) < 8 and code in deck:
                        cb = deck[code][line]
                    fg, bg = PAL[cb >> 4], PAL[cb & 15]
                    y = (top + r) * 8 + line
                    for b in range(8):
                        px[y][c * 8 + b] = fg if (bits << b) & 0x80 else bg

    draw_scanner(px, art, store)

    try:
        from PIL import Image
        im = Image.new("RGB", (W, H))
        im.putdata([p for row in px for p in row])
        im = im.resize((W * 2, H * 2), Image.NEAREST)
        im.save(out)
    except ImportError:
        # no PIL: write a minimal uncompressed BMP instead
        import struct
        out = os.path.splitext(out)[0] + ".bmp"
        rowb = (W * 3 + 3) & ~3
        data = b""
        for y in range(H - 1, -1, -1):
            line = b"".join(bytes((p[2], p[1], p[0])) for p in px[y])
            data += line + b"\x00" * (rowb - W * 3)
        hdr = struct.pack("<2sIHHI", b"BM", 54 + len(data), 0, 0, 54)
        hdr += struct.pack("<IiiHHIIiiII", 40, W, H, 1, 24, 0, len(data),
                           2835, 2835, 0, 0)
        open(out, "wb").write(hdr + data)
    print("wrote %s  (screen %d)" % (os.path.normpath(out), scr))


if __name__ == "__main__":
    main()
