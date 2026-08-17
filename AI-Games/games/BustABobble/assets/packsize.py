#!/usr/bin/env python3
"""Measure how much smaller BUST-A-BOBBLE's level data could be.

Reads the SHIPPED bytes out of src/levels.bas (the same nibble-packed blocks the
cartridge carries) and prices several encodings against them. Data size only --
decoder code is priced separately, by hand, because that is what decides whether
a scheme is a net win in the fixed area.

WHY THIS IS HERE AND NOT USED. Compression was measured, then passed over: the
level data went into a ROM bank instead (DESIGN.md 13), which freed 1,844 bytes of
the fixed area against the ~450-510 the best scheme here nets after its decoder,
and did it without changing a single byte of levels.bas -- so solvelevels.py, which
parses those bytes, needed no edit. This stays because the numbers are the argument:
if the fixed area ever gets tight again, re-run it rather than re-deriving it.

The one result worth remembering: the layouts are ALREADY nibble-packed at 4 bits a
cell, so the win is not in the value range (a per-level palette saves 9%, because the
mean level uses 6 colours) -- it is in the emptiness. 68% of cells are empty and every
empty row is trailing, which is why a one-byte height beats a row bitmap.

Run:  python3 packsize.py
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "src")


def read_labelled(path):
    out, cur = {}, None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        if not line[0].isspace() and line.strip().endswith(":"):
            cur = line.strip()[:-1]
            out[cur] = []
            continue
        s = line.strip()
        if s.startswith("'"):
            continue
        if cur is not None and s.upper().startswith("DATA"):
            body = s.split(None, 1)[1]
            if body.upper().startswith("BYTE"):
                body = body[4:]
            out[cur].append(body.split("'")[0])
    return out


def values(lines):
    v = []
    for body in lines:
        for tok in body.split(","):
            tok = tok.strip()
            if tok:
                v.append(int(tok[1:], 16) if tok.startswith("$") else int(tok))
    return v


lv = read_labelled(os.path.join(SRC, "levels.bas"))
lay = values(lv["pb_lay"])
seq = values(lv["pb_seq"])
meta = values(lv["pb_meta"])
assert len(lay) == 30 * 44 and len(seq) == 30 * 16

# levels[i] = 11 rows x 8 cells of colour 0..15
levels = []
for i in range(30):
    rows = []
    for r in range(11):
        base = i * 44 + r * 4
        cells = []
        for b in range(4):
            v = lay[base + b]
            cells.append(v >> 4)
            cells.append(v & 15)
        rows.append(cells)
    levels.append(rows)

print("CURRENT  pb_lay %d B + pb_seq %d B + pb_meta %d B = %d B"
      % (len(lay), len(seq), len(meta), len(lay) + len(seq) + len(meta)))
print()

# --- what the data actually looks like ---------------------------------------
tot_rows = 30 * 11
empty_rows = sum(1 for L in levels for r in L if not any(r))
pal = [sorted(set(c for r in L for c in r if c)) for L in levels]
print("shape of the data")
print("  empty rows: %d of %d (%.0f%%)" % (empty_rows, tot_rows,
                                           100.0 * empty_rows / tot_rows))
print("  distinct colours per level: min %d, max %d, mean %.1f"
      % (min(len(p) for p in pal), max(len(p) for p in pal),
         sum(len(p) for p in pal) / 30.0))
hist = Counter(len(p) for p in pal)
print("  levels by palette size: " +
      ", ".join("%d colours: %d levels" % (k, hist[k]) for k in sorted(hist)))
occupied = sum(1 for L in levels for r in L for c in r if c)
print("  occupied cells: %d of %d (%.0f%% empty)"
      % (occupied, 30 * 88, 100.0 - 100.0 * occupied / (30 * 88)))
print()

# --- candidate encodings ------------------------------------------------------
res = []

# A. row bitmap: 2-byte mask of non-empty rows, then 4 B per non-empty row.
n = 0
for L in levels:
    n += 2 + 4 * sum(1 for r in L if any(r))
res.append(("row bitmap + nibble rows", n))

# B. palette: 2 bits/cell needs <= 3 colours + empty; 3 bits/cell <= 7.
n = 0
for i, L in enumerate(levels):
    p = pal[i]
    bits = 4
    if len(p) <= 3:
        bits = 2
    elif len(p) <= 7:
        bits = 3
    n += 1 + len(p) + (88 * bits + 7) // 8      # count byte + palette + cells
res.append(("per-level palette, packed bits", n))

# C. palette + row bitmap
n = 0
for i, L in enumerate(levels):
    p = pal[i]
    bits = 2 if len(p) <= 3 else (3 if len(p) <= 7 else 4)
    live = [r for r in L if any(r)]
    n += 1 + len(p) + 2 + (len(live) * 8 * bits + 7) // 8
res.append(("palette + row bitmap", n))

# D. RLE over the whole field as nibbles: token = colour<<4 | (run-1), run 1..16
def rle_len(cells):
    out, i = 0, 0
    while i < len(cells):
        j = i
        while j < len(cells) and cells[j] == cells[i] and j - i < 16:
            j += 1
        out += 1
        i = j
    return out

n = 0
for L in levels:
    flat = [c for r in L for c in r]
    n += 1 + rle_len(flat)          # length byte + tokens
res.append(("RLE, colour+run in one byte", n))

# E. global row dictionary: unique 8-cell rows shared across all 30 levels,
#    each level stores 11 one-byte indices.
uniq = {}
for L in levels:
    for r in L:
        uniq.setdefault(tuple(r), len(uniq))
n = len(uniq) * 4 + 30 * 11
res.append(("global row dictionary (%d unique rows)" % len(uniq), n))

# F. row dictionary + the all-empty row costing nothing (bitmap picks it out)
uniq2 = {}
for L in levels:
    for r in L:
        if any(r):
            uniq2.setdefault(tuple(r), len(uniq2))
n = len(uniq2) * 4
for L in levels:
    n += 2 + sum(1 for r in L if any(r))
res.append(("row dictionary + row bitmap (%d rows)" % len(uniq2), n))

# G. dictionary of unique rows, RLE'd
n = len(uniq2) * 4
for L in levels:
    n += 2 + sum(1 for r in L if any(r))
res.append(("(same, for reference)", n))

cur = len(lay)
print("LAYOUTS -- data bytes only (current %d B)" % cur)
for name, n in res:
    print("  %-46s %5d B   saves %4d B  (%.0f%%)"
          % (name, n, cur - n, 100.0 * (cur - n) / cur))
print()

# --- shot sequences ----------------------------------------------------------
vals = []
for i in range(30):
    e = []
    for b in range(16):
        v = seq[i * 16 + b]
        e.append(v >> 4)
        e.append(v & 15)
    vals.append(e)
mx = max(max(e) for e in vals)
zeros = sum(1 for e in vals for x in e if x == 0)
print("SEQUENCES -- current %d B (32 entries x 4 bits per level)" % len(seq))
print("  max colour used %d, zero entries %d" % (mx, zeros))
print("  3 bits/entry:            %4d B   saves %3d B"
      % (30 * 12, len(seq) - 30 * 12))
uq = {}
for e in vals:
    uq.setdefault(tuple(e), 0)
print("  distinct sequences: %d of 30" % len(uq))
per = [len(set(e)) for e in vals]
print("  distinct colours per sequence: min %d max %d" % (min(per), max(per)))

print()
print("REFINEMENTS")
# Are the empty rows all TRAILING? If so a 1-byte row count beats a bitmap.
interior = 0
for L in levels:
    live = [i for i, r in enumerate(L) if any(r)]
    if live:
        interior += sum(1 for i in range(live[0], live[-1] + 1) if not any(L[i]))
print("  empty rows that sit BETWEEN occupied rows: %d" % interior)
n = 0
for L in levels:
    live = [i for i, r in enumerate(L) if any(r)]
    h = (live[-1] + 1) if live else 0
    n += 1 + 4 * h
print("  height byte + nibble rows                      %5d B   saves %4d B"
      % (n, cur - n))

# Column mask per live row: 1 mask byte + one nibble per OCCUPIED cell.
n = 0
for L in levels:
    live = [i for i, r in enumerate(L) if any(r)]
    h = (live[-1] + 1) if live else 0
    n += 1
    for r in L[:h]:
        occ = sum(1 for c in r if c)
        n += 1 + (occ + 1) // 2
print("  height + per-row column mask + nibbles         %5d B   saves %4d B"
      % (n, cur - n))

# Same, but the mask row is skipped entirely when empty (bitmap of live rows).
n = 0
for L in levels:
    n += 2
    for r in L:
        if any(r):
            occ = sum(1 for c in r if c)
            n += 1 + (occ + 1) // 2
print("  row bitmap + column mask + nibbles             %5d B   saves %4d B"
      % (n, cur - n))
