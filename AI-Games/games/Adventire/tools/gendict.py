#!/usr/bin/env python3
"""Row-dictionary compressor for Adventire room bitmaps.

The shipped src/adventire.bas stores rooms as 24 one-byte indices into a
71-row dictionary (rowdd). This is NOT hand-editable. To change a room:

  1. Get the RAW room DATA (24 rows x `DATA BYTE $hh,$hh,$hh,$hh`) - the last
     commit before the row-dictionary reclaim has it, or keep a raw copy.
  2. Edit the raw rooms.
  3. Run this on the raw file: `python gendict.py raw_rooms.bas`
     It prints stats, round-trip-verifies, and writes newdata.txt (the rowdd
     dictionary + per-room index blocks) to paste back into adventire.bas.

Parses every `rdN:` block (24 `DATA BYTE a,b,c,d` rows each).
"""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else 'adventire.bas'
src = open(path, 'r', encoding='latin1').read().splitlines()
labelre = re.compile(r'^rd(\d+):(.*)$')
byterow = re.compile(r'DATA BYTE\s+(.*)')
rooms, comments, order = {}, {}, []
cur, rows = None, []


def flush():
    global cur, rows
    if cur is not None:
        rooms[cur] = rows[:]
    rows = []


for ln in src:
    m = labelre.match(ln)
    if m:
        flush()
        cur = int(m.group(1)); order.append(cur)
        comments[cur] = m.group(2).rstrip(); rows = []; continue
    if re.match(r'^[a-zA-Z_]\w*:', ln) and cur is not None and not byterow.search(ln):
        flush(); cur = None
    if cur is not None:
        bm = byterow.search(ln.split("'")[0])
        if bm:
            vals = [int(v.strip().replace('$', '0x'), 16)
                    for v in bm.group(1).split(',') if v.strip()]
            if vals:
                assert len(vals) == 4, (cur, vals)
                rows.append(tuple(vals))
flush()

for n in order:
    assert len(rooms[n]) == 24, (n, len(rooms[n]))
print("rooms:", len(order), order)

dic, idx = [], {}
for n in order:
    for row in rooms[n]:
        if row not in idx:
            idx[row] = len(dic); dic.append(row)
print("distinct rows:", len(dic))
assert len(dic) <= 255, "too many rows for a 1-byte index"

for n in order:
    assert [dic[idx[r]] for r in rooms[n]] == rooms[n]
print("round-trip OK")

hx = lambda b: "$%02X" % b
out = ["\t' ------------------------------------------------------------",
       "\t' room bitmaps, row-dictionary compressed: %d distinct 4-byte" % len(dic),
       "\t' rows live once in rowdd (loaded into rowd() at startup); each",
       "\t' room below is just 24 indices into it. rbl expands them.",
       "\t' ------------------------------------------------------------",
       "rowdd:"]
for i, row in enumerate(dic):
    out.append("\tDATA BYTE %s\t' %d" % (", ".join(hx(b) for b in row), i))
out.append("")
for n in order:
    ix = [idx[row] for row in rooms[n]]
    out.append("rd%d:%s" % (n, comments[n]))
    out.append("\tDATA BYTE %s" % ", ".join(str(v) for v in ix[:12]))
    out.append("\tDATA BYTE %s" % ", ".join(str(v) for v in ix[12:]))
open('newdata.txt', 'w', encoding='latin1').write("\n".join(out) + "\n")
print("dict %dB + indices %dB = %dB vs raw %dB -> saved %dB"
      % (len(dic) * 4, len(order) * 24, len(dic) * 4 + len(order) * 24,
         len(order) * 96, len(order) * 96 - (len(dic) * 4 + len(order) * 24)))
print("wrote newdata.txt")
