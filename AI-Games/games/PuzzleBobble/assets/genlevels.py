#!/usr/bin/env python3
"""
PUZZLE BOBBLE - levels.txt -> src/levels.bas

Reads the human-authored level file and emits CVBasic DATA BYTE blocks:

    pb_lay   30 x 44 B   layout,   11 rows x 8 cells, one NIBBLE per cell
    pb_seq   30 x 16 B   sequence, 32 shots,          one NIBBLE per shot
    pb_meta  30 x  2 B   colours in play, droptime in QUARTER-SECONDS

Nibble packing is high-nibble-first: cell 0 is the high nibble of byte 0.
0 = empty, 1..8 = bubble colour.  Odd grid rows hold only cells 0..6; cell 7 is
forced empty (they are the 7-wide staggered rows -- DESIGN.md section 2).

Run:  python3 genlevels.py          (from anywhere; paths are resolved off this file)
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "levels.txt")
OUT = os.path.join(HERE, "..", "src", "levels.bas")

NLEVELS = 30       # the game ships 30 rounds
NROWS = 11         # grid rows stored per level
NCOLS = 8          # grid columns (odd rows use 0..6)
NSEQ = 32          # shot-sequence entries per level (index wraps with AND 31)


class LevelError(Exception):
    pass


def parse(path):
    """levels.txt -> list of dicts, ordered by the LEVEL number given."""
    levels = {}
    cur = None
    lineno = 0

    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            lineno += 1
            line = raw.rstrip("\n").rstrip()
            if not line.strip() or line.lstrip().startswith("#"):
                continue

            head = line.strip().split()
            kw = head[0].upper()

            if kw == "LEVEL":
                n = int(head[1])
                if n in levels:
                    raise LevelError("line %d: LEVEL %d defined twice" % (lineno, n))
                cur = {"n": n, "colours": None, "droptime": None, "seq": None, "rows": []}
                levels[n] = cur
                continue

            if cur is None:
                raise LevelError("line %d: data before the first LEVEL" % lineno)

            if kw == "COLOURS" or kw == "COLORS":
                cur["colours"] = int(head[1])
                continue
            if kw == "DROPTIME":
                cur["droptime"] = float(head[1])
                continue
            if kw == "SEQ":
                cur["seq"] = head[1]
                continue

            # otherwise: a grid row. Odd rows are written with ONE leading space so the
            # hex stagger is visible in the file; strip exactly that one space.
            r = len(cur["rows"])
            body = line[1:] if (r & 1) and line.startswith(" ") else line.strip()
            cur["rows"].append((r, body, lineno))

    return [levels[k] for k in sorted(levels)]


def validate(lv):
    n = lv["n"]

    def bad(msg):
        raise LevelError("LEVEL %d: %s" % (n, msg))

    if lv["colours"] is None:
        bad("no COLOURS line")
    if not 3 <= lv["colours"] <= 8:
        bad("COLOURS %d out of range 3..8" % lv["colours"])
    if lv["droptime"] is None:
        bad("no DROPTIME line")

    q = int(round(lv["droptime"] * 4))          # quarter-seconds
    if not 1 <= q <= 255:
        bad("DROPTIME %g s does not fit a byte as quarter-seconds" % lv["droptime"])
    lv["q"] = q

    if lv["seq"] is None:
        bad("no SEQ line")
    if len(lv["seq"]) != NSEQ:
        bad("SEQ has %d entries, need exactly %d" % (len(lv["seq"]), NSEQ))
    for ch in lv["seq"]:
        if not ch.isdigit() or not 1 <= int(ch) <= lv["colours"]:
            bad("SEQ contains '%s', not a colour 1..%d" % (ch, lv["colours"]))

    if len(lv["rows"]) > NROWS:
        bad("%d grid rows, max %d" % (len(lv["rows"]), NROWS))

    grid = [[0] * NCOLS for _ in range(NROWS)]
    used = set()
    for (r, body, lineno) in lv["rows"]:
        want = NCOLS - (r & 1)                  # even rows 8 wide, odd rows 7
        if len(body) != want:
            bad("row %d (line %d) is %d cells, need %d" % (r, lineno, len(body), want))
        for c, ch in enumerate(body):
            if ch == ".":
                continue
            if not ch.isdigit() or not 1 <= int(ch) <= lv["colours"]:
                bad("row %d has '%s'; expected '.' or 1..%d" % (r, ch, lv["colours"]))
            grid[r][c] = int(ch)
            used.add(int(ch))

    if not used:
        bad("no bubbles")

    # A colour in the shot sequence that is not on the field is legal (the substitution rule
    # handles it) but is almost always a typo, so say so.
    for ch in sorted(set(lv["seq"])):
        if int(ch) not in used:
            print("  ! LEVEL %d: SEQ uses colour %s, which is not on the field" % (n, ch))

    lv["grid"] = grid
    lv["count"] = sum(1 for r in range(NROWS) for c in range(NCOLS) if grid[r][c])
    lv["used"] = used
    return lv


def pack(vals):
    """nibbles -> bytes, high nibble first."""
    out = []
    for i in range(0, len(vals), 2):
        out.append((vals[i] << 4) | vals[i + 1])
    return out


def emit(fh, label, comment, blocks):
    fh.write("%s:\n" % label)
    fh.write("\t' %s\n" % comment)
    for n, rows in blocks:
        fh.write("\t' level %d\n" % n)
        for row in rows:
            fh.write("\tDATA BYTE %s\n" % ",".join("$%02X" % b for b in row))
    fh.write("\n")


def main():
    try:
        levels = [validate(lv) for lv in parse(SRC)]
    except LevelError as e:
        sys.stderr.write("error: %s\n" % e)
        return 1

    if not levels:
        sys.stderr.write("error: no levels defined in %s\n" % SRC)
        return 1

    defined = set(lv["n"] for lv in levels)
    for n in range(1, NLEVELS + 1):
        if n not in defined:
            break

    # Undefined levels are emitted as empty placeholders so the table is always 30 entries
    # and the game's indexing never depends on how many are authored yet.
    by_n = dict((lv["n"], lv) for lv in levels)
    lay_blocks, seq_blocks, meta = [], [], []

    for n in range(1, NLEVELS + 1):
        lv = by_n.get(n)
        if lv is None:
            lay_blocks.append((n, [pack([0] * NCOLS) for _ in range(NROWS)]))
            seq_blocks.append((n, [pack([1] * NSEQ)]))
            meta.append((n, 3, 80))
            continue
        lay_blocks.append((n, [pack(lv["grid"][r]) for r in range(NROWS)]))
        seq_blocks.append((n, [pack([int(c) for c in lv["seq"]])]))
        meta.append((n, lv["colours"], lv["q"]))

    outdir = os.path.dirname(os.path.abspath(OUT))
    if not os.path.isdir(outdir):
        os.makedirs(outdir)

    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\t' PUZZLE BOBBLE level data -- GENERATED by assets/genlevels.py\n")
        fh.write("\t' Do not edit. Edit assets/levels.txt and regenerate.\n")
        fh.write("\t' %d levels, %d rows x %d cells, one nibble per cell.\n\n"
                 % (NLEVELS, NROWS, NCOLS))
        emit(fh, "pb_lay", "%d B per level: %d rows x %d cells, nibble-packed"
             % (NROWS * NCOLS // 2, NROWS, NCOLS), lay_blocks)
        emit(fh, "pb_seq", "%d B per level: %d shots, nibble-packed, index wraps AND 31"
             % (NSEQ // 2, NSEQ), seq_blocks)
        fh.write("pb_meta:\n\t' 2 B per level: colours in play, droptime in QUARTER-seconds\n")
        for (n, col, q) in meta:
            fh.write("\tDATA BYTE $%02X,$%02X\t' level %d: %d colours, %g s\n"
                     % (col, q, n, col, q / 4.0))
        fh.write("\n")

    lay_b = NLEVELS * NROWS * NCOLS // 2
    seq_b = NLEVELS * NSEQ // 2
    meta_b = NLEVELS * 2
    print("wrote %s" % os.path.normpath(OUT))
    print("  layouts  %5d B   sequences %5d B   metadata %4d B   total %5d B"
          % (lay_b, seq_b, meta_b, lay_b + seq_b + meta_b))
    print("  %d of %d levels authored" % (len(levels), NLEVELS))
    for lv in levels:
        print("    level %-2d  %2d bubbles  colours %s  droptime %gs"
              % (lv["n"], lv["count"], "".join(str(c) for c in sorted(lv["used"])),
                 lv["q"] / 4.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
