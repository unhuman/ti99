#!/usr/bin/env python3
"""Every beat of a run cycle must be a DIFFERENT PICTURE.

WHY THIS EXISTS. Kelly's legs were built on a scheme that is correct and was
documented at length: four poses cost two drawings, because "left foot forward"
is the mirror of "right foot forward" and the facing lives in the hat and the
tunic. The scheme is fine. The DRAWINGS were two pairs of parallel vertical
legs -- apart in one pose, together in the other -- and mirroring a pair of
vertical legs gives back nearly the same picture. Measured on the shipped
bytes, the four beats he actually played differed by

    beat1 -> beat3   4 px        beat2 -> beat4   8 px

and 4 of those 4 pixels were the hip row sliding two columns sideways. He ran a
TWO-frame cycle with each frame shown twice, for months, and it was reported
from play as "that is only 2 frames of animation" -- which is exactly what it
was. Nothing in the build had an opinion, because every check we had asked
whether the numbers were consistent, and they were: the right patterns were
loaded at the right addresses and drawn on the right beats. The patterns were
just the same picture twice.

So this asks the one question none of the others do: **given the beats the
SOURCE actually plays, are they different pictures?**

HOW IT READS THE BEATS. Not from a table here -- from `KEYSTONE.bas`. It finds
each band's base assignment and the `IF <clock> AND <bit> THEN <var> = <var> +
<n>` lines that follow it, enumerates every combination of those bits, and
resolves the resulting pattern numbers through genart's own sprite table. A
checker that hard-coded "Kelly plays KLEG1..4" would agree with the source
right up until somebody changed the source, which is the moment it matters.

IT ALSO CHECKS THE OTHER HALF OF THE SAME BUG: that every band of one figure
runs on the SAME clock bits. Four leg poses against two torso poses is two
clocks in one body -- the arms complete a swing in half the time the legs
complete a stride -- and that is what made Harry look like he was flapping
before he was redrawn from the run-cycle sheet. Bands that are DERIVED from
another band (`hs = hp - P_HBODY : hs = hs + P_HSTRIPE`) are the correct way to
avoid it and are recognised as such.

And it checks that a facing offset lands on real patterns, since `P_HFACING`
has to grow every time a figure gains a frame and nothing else would notice if
it did not.

Run:  python3 checkanim.py
"""

import io
import os
import re
import sys

import genart as g

HERE = os.path.dirname(os.path.abspath(__file__))
BAS = os.path.join(HERE, "..", "src", "KEYSTONE.bas")

# Pixels that must differ between any two beats of one band. Harry's four beats
# measure 25 px apart at the torso and 28 at the legs; the defect this exists
# for measured 4 and 8. Set below the real figures and well above the defect,
# so it fails on a pose that is its own mirror without dictating how anybody
# draws.
MINDIFF = 10

# Bands allowed to repeat a beat, each with the reason. AN EXEMPTION IS A
# DECISION, NOT A SILENCER: the check still measures the band and still prints
# what it found, so an exempted cycle cannot quietly get worse -- it just does
# not fail the build. Lowering MINDIFF instead would have blinded the check for
# every OTHER band at the same time, which is how a gate stops being one.
EXEMPT = {
    "kq": "The Kop's leg poses are the reviewer's explicit choice, restored "
          "from e9564ee after a redraw was rejected on sight. They are two "
          "near-symmetric drawings mirrored, so beats 1/3 measure 4 px and "
          "2/4 measure 8 -- he really does run a two-frame cycle, and that "
          "is the animation that was asked for. Harry is the figure being "
          "worked on; do not 'fix' this one to make the number go up.",
}


def bitmaps():
    """pattern number -> its 16x16 art, straight out of genart's sprite list."""
    out = {}
    for _label, arts, _c in g.SPRITES:
        for name, art in arts:
            out[g.SPR[name]] = art
    return out


def diff(a, b):
    nl = chr(10)
    A = a.strip(nl).split(nl)
    B = b.strip(nl).split(nl)
    n = 0
    for y in range(min(len(A), len(B))):
        for x in range(min(len(A[y]), len(B[y]))):
            if A[y][x] != B[y][x]:
                n += 1
    return n


def parse(src):
    """Find every animated band: base constant, clock, and the (bit, add) steps.

    Returns {var: {"base": name, "clock": var, "steps": [(bit, add)],
                   "line": n, "derived": from-var or None}}.
    """
    consts = dict((m.group(1), int(m.group(2)))
                  for m in re.finditer(r"CONST (P_\w+) = (\d+)", src))
    lines = src.split(chr(10))
    bands = {}

    base_re = re.compile(r"^\s*(\w+) = (P_\w+)\s*(?:'.*)?$")
    step_re = re.compile(r"^\s*IF (\w+) AND (\d+) THEN (\w+) = \3 \+ (\d+)"
                         r"\s*(?:'.*)?$")
    der_re = re.compile(r"^\s*(\w+) = (\w+) - (P_\w+)\s*(?:'.*)?$")

    for i, ln in enumerate(lines):
        m = der_re.match(ln)
        if m and m.group(2) in bands:
            bands[m.group(1)] = {"derived": m.group(2), "line": i + 1,
                                 "base": None, "clock": None, "steps": []}
            continue
        m = base_re.match(ln)
        if not m:
            continue
        var, base = m.group(1), m.group(2)
        if base not in consts:
            continue
        steps, clock = [], None
        for ln2 in lines[i + 1:i + 6]:
            s = step_re.match(ln2)
            if not s:
                if ln2.strip().startswith("'") or ln2.strip() == "":
                    continue
                break
            if s.group(3) != var:
                break
            clock = s.group(1)
            steps.append((int(s.group(2)), int(s.group(4))))
        if steps:
            bands[var] = {"base": base, "basen": consts[base], "clock": clock,
                          "steps": steps, "line": i + 1, "derived": None}
    return bands, consts


def facings(src, consts):
    """{var: offset} for every `<var> = <var> + P_*FACING` line."""
    out = {}
    for m in re.finditer(r"^\s*(\w+) = \1 \+ (P_\w+FACING)\s*(?:'.*)?$",
                         src, re.M):
        if m.group(2) in consts:
            out[m.group(1)] = consts[m.group(2)]
    return out


def main():
    src = io.open(BAS, encoding="utf-8").read()
    bands, consts = parse(src)
    if not bands:
        sys.exit("checkanim: found no animated bands in KEYSTONE.bas -- the "
                 "source shape changed and this check is now blind")
    art = bitmaps()
    face = facings(src, consts)
    bad, notes = [], []

    direct = dict((v, b) for v, b in bands.items() if not b["derived"])

    # A derived band names the base it is offset FROM (hs = hp - P_HBODY, then
    # hs = hs + P_HSTRIPE). Recover that second constant so its beats can be
    # lined up with the band it follows.
    derived_base = {}
    for m in re.finditer(r"^\s*(\w+) = \1 \+ (P_\w+)\s*(?:'.*)?$", src, re.M):
        if m.group(1) in bands and bands[m.group(1)]["derived"]:
            derived_base[m.group(1)] = consts[m.group(2)]
            bands[m.group(1)]["basen"] = consts[m.group(2)]

    for var in sorted(direct):
        b = direct[var]
        beats = [b["basen"]]
        for bit, add in b["steps"]:
            beats = beats + [n + add for n in beats]
        beats = sorted(set(beats))
        names = []
        for n in beats:
            if n not in art:
                bad.append("%s (line %d): beat pattern %d is not a sprite in "
                           "genart's table" % (var, b["line"], n))
                names.append("?")
            else:
                names.append(n)
        if "?" in names:
            continue

        # COMPARE THE WHOLE FIGURE, NOT THE ONE SPRITE. A striped actor is split
        # across two patterns -- Harry white legs plus black stripes-and-shoes --
        # and the two halves are complementary, so most of the ink can sit in
        # the half this band does not name. His white leg layer holds 10 px of
        # 33 and two of his four beats were IDENTICAL in it while the black
        # layer they are drawn with differed by 34. Measuring one half alone
        # would have called that a two-frame cycle and a four-frame one on the
        # same art, depending which half it happened to be handed. Add the
        # derived bands back in and compare what is actually on screen.
        partners = [b2 for v2, b2 in bands.items()
                    if b2["derived"] == var and v2 in derived_base]
        worst = None
        for i in range(len(beats)):
            for j in range(i + 1, len(beats)):
                d = diff(art[beats[i]], art[beats[j]])
                for pb in partners:
                    oi = beats[i] - b["basen"] + pb["basen"]
                    oj = beats[j] - b["basen"] + pb["basen"]
                    if oi in art and oj in art:
                        d += diff(art[oi], art[oj])
                if worst is None or d < worst[0]:
                    worst = (d, beats[i], beats[j])
        if worst is None:
            continue
        notes.append("  %-4s %s  %d beats, closest pair %d px apart%s"
                     % (var, b["base"], len(beats), worst[0],
                        "   [EXEMPT]" if var in EXEMPT else ""))
        if var in EXEMPT:
            notes.append("       %s" % EXEMPT[var])
        if worst[0] < MINDIFF and var not in EXEMPT:
            bad.append("%s (line %d): beats %d and %d differ by only %d px -- "
                       "they are the same picture, so this cycle has fewer "
                       "frames than it looks like. A mirrored pose is only "
                       "worth two drawings if the drawing is ASYMMETRIC."
                       % (var, b["line"], worst[1], worst[2], worst[0]))

        # the facing offset, if this band takes one, must land on real patterns
        if var in face:
            for n in beats:
                if n + face[var] not in art:
                    bad.append("%s (line %d): facing offset %d puts beat %d at "
                               "%d, which is not a sprite -- the left-hand set "
                               "does not start where the offset says"
                               % (var, b["line"], face[var], n,
                                  n + face[var]))

    # ONE CLOCK PER FIGURE. Bands sharing a clock variable must share its bits.
    byclock = {}
    for var, b in direct.items():
        byclock.setdefault(b["clock"], []).append((var, b))
    for clock in sorted(x for x in byclock if x):
        seen = {}
        for var, b in byclock[clock]:
            seen[tuple(sorted(bit for bit, _a in b["steps"]))] = var
        if len(seen) > 1:
            bad.append("clock %s drives bands on DIFFERENT bits (%s) -- that "
                       "is two clocks in one figure, and the band on the "
                       "faster one completes its cycle while the other is "
                       "half way through. Derive it from the slower band "
                       "instead." % (clock, ", ".join(
                           "%s uses %s" % (v, list(k)) for k, v in
                           sorted(seen.items(), key=lambda kv: kv[1]))))

    for var in sorted(v for v in bands if bands[v]["derived"]):
        notes.append("  %-4s derived from %s -- no clock of its own"
                     % (var, bands[var]["derived"]))

    if bad:
        print("checkanim FAILED")
        for b in bad:
            print("  " + b)
        print()
        for n in notes:
            print(n)
        return 1
    print("animation OK -- %d clocked bands, every beat at least %d px from "
          "every other, one clock per figure" % (len(direct), MINDIFF))
    for n in notes:
        print(n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
