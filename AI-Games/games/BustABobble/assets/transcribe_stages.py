#!/usr/bin/env python3
"""
BUST-A-BOBBLE -- arcade-stages.txt  ->  levels.txt

Turns the transcribed arcade SHAPES into playable levels by assigning a concrete
colour to every cell, then emits the authoring file genlevels.py consumes.

WHY COLOURS HAVE TO BE ASSIGNED. The source diagrams mark a colour only where it
matters strategically (a-d); every other bubble is 'O' = "ball of any colour".
The shapes and the per-round colour counts are authentic; the specific colour of
each O is not recoverable from that source, so it is generated here.

ASSIGNMENT RULES
  * a,b,c,d keep their identity: each maps to its own colour, and two cells that
    share a letter always share a colour. This preserves the puzzle structure the
    FAQ actually cared about.
  * O and X take colour ((c >> 1) + r) mod N + 1 -- horizontal PAIRS of the same
    colour, shifting one step per row. Pairs matter: a lone bubble needs two more
    of its colour to pop, so a field of noise plays badly, while banded pairs mean
    most shots have a target. X is treated as O (the legend makes it a hint, not a
    distinct colour).
  * Every round therefore uses its full stated palette.

The shot sequence is deterministic per round (a level is a puzzle, not a slot
machine) and drawn from that round's palette.

Run:  python3 transcribe_stages.py      then genlevels.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "arcade-stages.txt")
OUT = os.path.join(HERE, "levels.txt")

NSEQ = 32
LETTERS = "abcdefgh"


def parse(path):
    stages, cur = [], None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        head = line.split()
        if head[0].upper() == "STAGE":
            cur = {"n": int(head[1]), "ncol": int(head[2]), "rows": []}
            stages.append(cur)
            continue
        r = len(cur["rows"])
        body = line[1:] if (r & 1) and line.startswith(" ") else line
        cur["rows"].append(body)
    return stages


def assign(st):
    """symbols -> colours 1..N"""
    n = st["ncol"]
    out = []
    for r, body in enumerate(st["rows"]):
        want = 8 - (r & 1)
        if len(body) != want:
            raise SystemExit("stage %d row %d is %d cells, need %d: %r"
                             % (st["n"], r, len(body), want, body))
        line = []
        for c, ch in enumerate(body):
            if ch == ".":
                line.append(".")
            elif ch in "OX":
                line.append(str(((c >> 1) + r) % n + 1))
            elif ch in LETTERS:
                k = LETTERS.index(ch)
                if k >= n:
                    raise SystemExit("stage %d uses '%s' but only %d colours"
                                     % (st["n"], ch, n))
                line.append(str(k + 1))
            else:
                raise SystemExit("stage %d: unknown symbol %r" % (st["n"], ch))
        out.append("".join(line))
    return out


def sequence(st, grid):
    """32 shots, deterministic, WEIGHTED by what is actually on the field.

    Only colours actually placed can appear: a sparse layout does not always
    receive every colour its round declares, and a shot of a colour that is not on
    the board is a wasted turn. The draw is weighted by each colour's share of the
    field, so a mostly-red board mostly hands you red.

    NOTE the generator is a real LCG, not a cheap polynomial. `(i*i + i*5 + k) % n`
    was used here first and was badly broken: i*i + i*5 factors to i*(i+5), so one
    term is always even and the whole expression has fixed parity -- with 4 colours
    only residues 1 and 3 ever came out, so half of every palette was unreachable
    and round 1 dealt nothing but greens and yellows. Modular structure in a
    "random enough" formula is exactly the kind of thing that looks fine in the
    source and is only visible in play.
    """
    counts = {}
    for row in grid:
        for ch in row:
            if ch != ".":
                counts[ch] = counts.get(ch, 0) + 1
    pool = []
    for c in sorted(counts):
        pool.extend([c] * counts[c])

    s = [(st["n"] * 2654435761 + 12345) & 0x7FFFFFFF]

    def rnd(n):
        s[0] = (s[0] * 1103515245 + 12345) & 0x7FFFFFFF
        return (s[0] >> 16) % n

    # One of EVERY colour on the field first, so none can be missed, then fill
    # the rest by weight. A round like stage 2 has nine bubbles across six
    # colours -- some appear once, and a purely weighted draw of 32 will happily
    # skip them, leaving a colour on the board that the launcher never offers.
    out = sorted(counts)
    while len(out) < NSEQ:
        out.append(pool[rnd(len(pool))])
    for i in range(len(out) - 1, 0, -1):        # deterministic shuffle
        j = rnd(i + 1)
        out[i], out[j] = out[j], out[i]
    return "".join(out)


def droptime(n):
    """20 s at round 1 easing to 12 s by round 30, in quarter-second steps."""
    secs = 20.0 - (n - 1) * 8.0 / 29.0
    return round(secs * 4) / 4.0


def main():
    stages = parse(SRC)
    if len(stages) != 30:
        sys.stderr.write("error: found %d stages, expected 30\n" % len(stages))
        return 1

    body, fail = [], []
    for st in stages:
        grid = assign(st)
        used = sorted(set(ch for row in grid for ch in row if ch != "."))
        body.append("LEVEL %d" % st["n"])
        # COLOURS is the highest colour index PLACED, which is what genlevels.py
        # validates the sequence against. The round's authentic declared count
        # lives in arcade-stages.txt; a sparse layout may not receive all of them.
        body.append("COLOURS %d" % max(int(c) for c in used))
        body.append("DROPTIME %g" % droptime(st["n"]))
        seq = sequence(st, grid)
        # GUARD: a sequence must reach every colour on the field. The first
        # generator here silently reached only half of each palette, which is
        # invisible in the data and obvious the moment you play it.
        missing = sorted(set(used) - set(seq))
        if missing:
            fail.append("stage %d: sequence never offers colour(s) %s"
                        % (st["n"], ",".join(missing)))
        body.append("SEQ %s" % seq)
        for r, row in enumerate(grid):
            body.append((" " if (r & 1) else "") + row)
        body.append("")

    head = [
        "# BUST-A-BOBBLE -- level data.  GENERATED by assets/transcribe_stages.py",
        "# from assets/arcade-stages.txt. Do not hand-edit: regenerate instead.",
        "#",
        "# Shapes are the 30 arcade layouts, transcribed cell-for-cell. COLOURS ARE",
        "# ASSIGNED, not authentic -- the source marks a colour only where it matters",
        "# strategically and leaves every other bubble as 'any colour'. See the header",
        "# of arcade-stages.txt for exactly what is and is not from the source.",
        "#",
        "# '.' = empty, '1'..'8' = colour. Even rows 8 cells, odd rows 7 and indented.",
        # Names must match genart.py's BUBBLE table, which is what the ROM draws.
        # This line used to read '7 white 8 orange'; there is no orange bubble --
        # 7 is GREY (heavy dither, reads darkest) and 8 is WHITE (light dither,
        # reads brightest). Getting it wrong sends a reader looking for a ball
        # that does not exist.
        "# 1 red  2 green  3 blue  4 yellow  5 cyan  6 magenta  7 grey  8 white",
        "",
    ]
    if fail:
        for f in fail:
            sys.stderr.write("error: %s\n" % f)
        return 1

    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(head + body) + "\n")

    tot = sum(sum(1 for row in assign(st) for ch in row if ch != ".") for st in stages)
    print("wrote %s" % os.path.normpath(OUT))
    print("  30 stages, %d bubbles total" % tot)
    for st in stages:
        g = assign(st)
        cnt = sum(1 for row in g for ch in row if ch != ".")
        print("    stage %-2d  %2d rows  %3d bubbles  %d colours  droptime %gs"
              % (st["n"], len(g), cnt, st["ncol"], droptime(st["n"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
