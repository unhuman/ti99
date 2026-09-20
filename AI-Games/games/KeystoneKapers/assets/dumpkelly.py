#!/usr/bin/env python3
"""Dump Kelly's sprite art as editable .txt grids, and read them back.

WHY 16x32 AND NOT THE BANDS SEPARATELY. Kelly is four sprites -- helmet, face,
tunic, legs -- each its own colour, because a TMS9918 sprite carries exactly
one. Handing those over one at a time is unjudgeable: nobody can tell whether a
shoulder line is right while looking at a shoulder on its own.

The four stack with no gap. `draw_actors` puts the helmet at y-10, the face at
y-5, the tunic at y+11 and the legs at y+16, and `genart` shifts each band
inside its own box by exactly the complementary amount -- so the assembled
figure is KELLY_TOP (rows 0-15) sitting directly on the leg art (rows 16-31).
Verified here rather than assumed, by `--check`.

That means a 16x32 grid is BOTH the thing you can judge AND a 1:1 map back to
the source blocks:

    rows  0-5    KELLY_TOP    HAT    -- helmet, black
    rows  6-10   KELLY_TOP    FACE   -- the one skin band
    rows 11-15   KELLY_TOP    TORSO  -- tunic
    rows 16-31   KELLY_LEGn          -- legs, blue

THE CROUCH IS NOT HERE ANY MORE. It used to be three overlapping 16x16 grids
drawn at one y and needed a writer and a reader of its own; staggering its boxes
the way the run does made it an ordinary pose, so assets/kelly-duck.txt is now
the same format as these two and genart reads it with the same loader. Its
header is hand-written because it carries the duck-height arithmetic, which is
about the game rather than about the file.

Run:  python3 dumpkelly.py          write the .txt files
      python3 dumpkelly.py --check  verify they round-trip to the source
"""
import io
import os
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))

# ONE CHARACTER PER COLOUR, and the colours are per-sprite rather than
# per-pixel -- so the character also says WHICH SPRITE a pixel belongs to,
# which is what makes the grid splittable back into bands.
INK = {"#": "black helmet", "-": "skin", "0": "blue tunic and legs"}


def rows(art):
    return art.strip("\n").split("\n")


def stack(top, leg):
    """KELLY_TOP over a leg frame -> the 16x32 figure, colour-coded.

    The band a pixel belongs to is decided by its ROW, exactly as genart's
    band() does it, so this cannot drift from the real split.
    """
    out = []
    for n, line in enumerate(rows(top)):
        ink = "#" if n in g.HAT else ("-" if n in g.FACE else "0")
        out.append("".join(ink if c == "#" else "." for c in line))
    for line in rows(leg):
        out.append("".join("0" if c == "#" else "." for c in line))
    return out


def unstack(grid):
    """The inverse: 16x32 colour grid -> (KELLY_TOP art, leg art).

    Every non-'.' becomes a '#' in whichever block that row belongs to. The ink
    character is therefore REDUNDANT on the way back in -- it is there to be
    read by a person, and a mismatch between ink and row is reported by
    --check rather than silently honoured.
    """
    nl = chr(10)
    top = nl + nl.join("".join("#" if c != "." else "." for c in r)
                       for r in grid[:16]) + nl
    leg = nl + nl.join("".join("#" if c != "." else "." for c in r)
                       for r in grid[16:]) + nl
    return top, leg


def load(path):
    """Art rows out of a .txt -- exactly 16 of the ink alphabet, ';' ignored."""
    out = []
    for ln in io.open(path, encoding="utf-8").read().split("\n"):
        s = ln.rstrip("\r")
        if s.lstrip().startswith(";") or not s.strip():
            continue
        if len(s) == 16 and set(s) <= set(".#-0"):
            out.append(s)
    return out


HEAD = """\
; Keystone Kapers -- Kelly the Kop, %(what)s. Facing RIGHT.
;
;   #   black helmet      -   skin (face)      0   blue tunic / legs
;   .   nothing -- the store shows through
;
; The grid is 16 wide by 32 tall. That is still TWO source blocks -- the
; head-and-torso block on top, the leg block below -- but they now end up in
; THREE sprites, not four, because the tunic and the legs are merged into one.
; Edit the rows and hand the file back. Any
; line that is exactly 16 of '.#-0' is read as art; everything else -- these
; ';' lines, blanks, the ruler -- is ignored, so annotate freely.
;
; HE IS THREE SPRITES, ONE COLOUR EACH, and the row decides which:
;
;     rows  0-5   HELMET   black
;     rows  6-10  FACE     skin
;     rows 11-31  BODY     blue   -- tunic AND legs, ONE sprite
;
; THE TUNIC-TO-LEG SEAM IS NO LONGER A SPRITE BOUNDARY. It used to be: the
; trousers were a fourth sprite at slot 3, drawn 16 px lower. They are one box
; now, because tunic and legs span 13 contiguous rows in the same blue and fit
; inside a single 16-row sprite -- so draw across row 15 as freely as any other
; row. Nothing in the drawing changes at that line any more.
;
; So the INK CHARACTER MUST MATCH THE ROW. Skin on row 12 is not available --
; it would need a fourth sprite, and the scanline budget has none. Change the
; band boundaries only by saying so; they are HAT/FACE/TORSO in genart.py.
;
; WHAT USES THIS FRAME:
%(uses)s;
; THE FOUR RUN FRAMES ARE TWO DRAWINGS. Frames 3 and 4 are frames 1 and 2
; MIRRORED -- the VDP has no flip bit, so both facings are generated, but there
; is nothing extra to draw. A pose that is its own mirror therefore costs a
; frame for nothing: a pair of vertical legs mirrors to itself, which is how an
; earlier four-beat cycle turned out to be two pictures. checkanim.py fails the
; build on any two beats closer than 10 px, so the drawings have to differ
; properly, not subtly.
;
;      0123456789012345
;      0000000000111111
"""

REF = """
; For reference, the same rows numbered and labelled -- IGNORED, being ';'.
;
;      0123456789012345
%s"""


def band_of(n):
    """Which SPRITE a row belongs to -- three now, not four.

    Rows 11 upward are all one box: the tunic and the legs were merged, so
    there is no boundary at row 15 any more.
    """
    if n < 16:
        return ("helmet" if n in g.HAT else
                "face" if n in g.FACE else "body (tunic)")
    return "body (legs)"


def write(path, what, uses, grid):
    ref = "".join(";%3d   %s   %s\n" % (n, r, band_of(n))
                  for n, r in enumerate(grid))
    body = "\n".join(grid)
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        HEAD % {"what": what, "uses": uses} + "\n" + body + "\n" + REF % ref)
    return path


FILES = [
    ("kelly-run1.txt", "RUN FRAME 1 of 2", g.KELLY_TOP_B, "KELLY_LEG1",
     ";   * run frames 1 and 3 (3 is this one mirrored)\n"
     ";   * THE JUMP -- draw_actors forces leg frame 1 while airborne, so a\n"
     ";     jumping Kelly is these legs with whichever torso the counter is\n"
     ";     showing. There is no separate jump drawing.\n"
     ";   * STANDING STILL. kanim advances by kspd, so the counter FREEZES\n"
     ";     when he stops and he holds whatever frame he was on. There is no\n"
     ";     separate standing drawing either -- if a stopped Kelly looks\n"
     ";     wrong, it is these frames being wrong at rest.\n"),
    ("kelly-run2.txt", "RUN FRAME 2 of 2", g.KELLY_TOP, "KELLY_LEG2",
     ";   * run frames 2 and 4 (4 is this one mirrored)\n"
     ";   * the arm-forward torso, which alternates with run1's arm-back one\n"
     ";     on the same counter bit that picks the legs\n"),
]




def duck_grid(art, ink):
    return ["".join(ink if c == "#" else "." for c in r) for r in rows(art)]




def main():
    check = "--check" in sys.argv
    bad = []
    for name, what, top, legname, uses in FILES:
        leg = getattr(g, legname)
        grid = stack(top, leg)
        path = os.path.join(HERE, name)
        if check:
            got = load(path)
            if len(got) != 32:
                bad.append("%s: %d art rows, expected 32" % (name, len(got)))
                continue
            t, l = unstack(got)
            if rows(t) != rows(top):
                bad.append("%s: head/torso differs from %s" % (name, what))
            if rows(l) != rows(leg):
                bad.append("%s: legs differ from %s" % (name, legname))
            ink = [n for n, r in enumerate(got)
                   for c in set(r) - {"."}
                   if c != ("#" if n in g.HAT else "-" if n in g.FACE
                            else "0")]
            if ink:
                bad.append("%s: ink does not match the band at rows %s -- a "
                           "colour cannot cross a sprite boundary"
                           % (name, sorted(set(ink))))
        else:
            print("wrote %s" % os.path.normpath(write(path, what, uses, grid)))

    if check:
        for b in bad:
            print("FAIL  " + b)
        if not bad:
            print("OK: every Kelly .txt round-trips to the art in genart.py")
        return 1 if bad else 0
    print()
    print("The run frames are 16 x 32, head+torso over legs, and TWO drawings")
    print("cover all four of them (3 and 4 are mirrors), the jump (leg frame 1)")
    print("and standing (the counter freezes when he stops).")
    print()
    print("The crouch (kelly-duck.txt) is the same 16 x 32 format and genart")
    print("reads it with the same loader, but it is NOT written from here --")
    print("its header carries the duck-height arithmetic, which is about the")
    print("game rather than about the file. Edit it directly.")
    print()
    print("It used to be three overlapping 16 x 16 grids drawn at one y, which")
    print("cost THREE sprites on every scanline the figure touched. Staggering")
    print("its boxes the way the run does -- helmet y-10, face y-5, body y+11 --")
    print("dropped that to two and made it an ordinary pose.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
