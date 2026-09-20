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
each band's base assignment and the `IF <clock> AND <bit> THEN <var> = ...`
lines that follow it -- either `<var> + <n>` or an outright `P_*` assignment --
enumerates every combination of those bits, and resolves the resulting pattern
numbers through genart's own sprite table. A checker that hard-coded "Kelly
plays KLEG1..4" would agree with the source right up until somebody changed the
source, which is the moment it matters.

READING THE SOURCE IS NOT ENOUGH ON ITS OWN, though, and that is worth stating
because it went wrong here. When Kelly's four-beat ladder became a two-beat
assignment, the extractor stopped recognising it, his band vanished, and this
file printed "animation OK" -- correctly, about everything it could still see.
Two more bands turned out to have been invisible for the same reason: the
window that looks for steps counted COMMENT lines against its budget. A parser
that silently matches less is the same failure as a check that is scoped too
narrowly, so `checkanim_test.py` now asserts the bands by name.

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
# THE KOP'S EXEMPTION HAS BEEN RETIRED, because the defect it named is gone.
#
# It used to read: "The Kop's leg poses are the reviewer's explicit choice...
# They are two near-symmetric drawings mirrored, so beats 1/3 measure 4 px and
# 2/4 measure 8 -- he really does run a two-frame cycle, and that is the
# animation that was asked for."
#
# That was true and is not any more. Both poses were redrawn in
# assets/kelly-run{1,2}.txt with asymmetric strides, and the same measurement
# now reads 18 px between beats 1 and 3 and 22 between 2 and 4 -- four distinct
# beats where there were two pictures. The reviewer changed the art rather than
# the threshold, which is the outcome this file was arguing for.
#
# AN EXEMPTION OUTLIVING ITS DEFECT IS WORSE THAN NO GATE: it would sit here
# accepting a silent return to a two-frame cycle on the one band that is not
# allowed to fail. So it is removed rather than left "harmless".
EXEMPT = {
    # THE BIPLANE IS MEANT TO BE THE SAME PICTURE TWICE. Its two phases are one
    # aeroplane with two PROPELLERS -- a near-solid disc and broken blades --
    # and the airframe is identical by construction, because an aircraft that
    # changed shape between frames would not read as an aircraft. The 4 px is
    # the whole propeller, which is the only part that is supposed to move.
    #
    # It is listed by name and still MEASURED, so if the two phases ever
    # collapse into one the number printed here moves in plain sight.
    #
    # This band was invisible to the check until the parser learned the
    # assignment form and stopped counting comment lines against its window --
    # so were Harry's legs (hq, 39 px) and their stripe layer. Three bands went
    # unmeasured while the file printed OK.
    "dp": "the propeller is the animation; the airframe is one drawing on "
          "purpose (P_PLANE / P_PLANEB)",
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
    # A BEAT IS PICKED EITHER BY ADDING OR BY ASSIGNING, and this has to read
    # both. It read only the adding form, and when Kelly's four-beat ladder
    # (`kb = kb + 4` / `+ 8`) became a two-beat one written as an assignment
    # (`kb = P_KRUN2`) his band simply STOPPED BEING FOUND -- the run went
    # unmeasured and the file still printed "animation OK", one band lighter.
    # Nothing said a word, which is the same shape as the bug this whole check
    # exists for. A checker that quietly narrows is worse than one that fails.
    step_re = re.compile(r"^\s*IF (\w+) AND (\d+) THEN (\w+) = "
                         r"(?:\3 \+ (\d+)|(P_\w+))\s*(?:'.*)?$")
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
        # Comments between the base and its steps are skipped rather than
        # counted, so the window is a bound on CODE lines, not on source lines
        # -- it used to be five source lines and a paragraph of comment pushed
        # the step out of reach, which loses the band silently.
        for ln2 in lines[i + 1:i + 60]:
            t = ln2.strip()
            if t.startswith("'") or t == "":
                continue
            s = step_re.match(ln2)
            if not s or s.group(3) != var:
                break
            clock = s.group(1)
            if s.group(4) is not None:
                steps.append(("add", int(s.group(2)), int(s.group(4))))
            else:
                if s.group(5) not in consts:
                    break
                steps.append(("set", int(s.group(2)), consts[s.group(5)]))
        if steps:
            bands[var] = {"base": base, "basen": consts[base], "clock": clock,
                          "steps": steps, "line": i + 1, "derived": None}
    return bands, consts


def beats_of(b):
    """The pattern numbers one band plays, over every combination of its bits.

    An "add" step accumulates and a "set" step overwrites, which is what lets
    the two-beat assignment form and the four-beat ladder share one model.
    """
    found = set()
    for mask in range(1 << len(b["steps"])):
        n = b["basen"]
        for k, (kind, _bit, val) in enumerate(b["steps"]):
            if mask & (1 << k):
                n = n + val if kind == "add" else val
        found.add(n)
    return sorted(found)


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
        beats = beats_of(b)
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
            seen[tuple(sorted(bit for _k, bit, _a in b["steps"]))] = var
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
