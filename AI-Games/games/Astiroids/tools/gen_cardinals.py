#!/usr/bin/env python3
# (Re)generate the 4 cardinal ship frames (0=up, 4=east, 8=down, 12=west) in
# ship_sprites as a 9-cell-long ship. EAST/DOWN/WEST are exact 90/180/270
# rotations of UP about the pivot (5.5,5.5), so the nose shape and rotation stay
# consistent; the diagonal frames are left untouched. Edit UP below and re-run
# with "write" to reshape all four cardinals at once, then re-run
# tools/flame_offsets.py to refresh the flame table.
#
#   python gen_cardinals.py ../assets/sprites.bas [write]
import sys, re

PATH = sys.argv[1]

# UP: 2-tall nose at col 6, even taper to a 7-wide base, 9 cells long (rows 0-8).
UP = [
    "......X.........",
    "......X.........",
    ".....X.X........",
    ".....X.X........",
    "....X...X.......",
    "....X...X.......",
    "...X.....X......",
    "...X.....X......",
    "...XXXXXXX......",
] + ["................"]*7

def pts(rows):
    return [(r,c) for r in range(16) for c in range(16) if rows[r][c]=='X']

def build(points):
    g = [['.']*16 for _ in range(16)]
    for r,c in points:
        g[r][c]='X'
    return [''.join(x) for x in g]

P = pts(UP)
east = build([(c, 11-r) for r,c in P])    # 90 CW about (5.5,5.5)
down = build([(11-r, 11-c) for r,c in P])  # 180
west = build([(11-c, r) for r,c in P])     # 90 CCW
frames = {0: UP, 4: east, 8: down, 12: west}

with open(PATH, 'r', newline='') as f:
    lines = f.readlines()
start = next(i for i,l in enumerate(lines) if l.strip()=='ship_sprites:') + 1
bm_idx = []
i = start
while len(bm_idx) < 256:
    if re.match(r'^\s*BITMAP\s+"[.X]{16}"', lines[i]):
        bm_idx.append(i)
    i += 1

for fi, art in frames.items():
    for r,c in pts(art):
        assert 0 <= r < 16 and 0 <= c < 16, fi   # no clip
    for k in range(16):
        idx = bm_idx[fi*16+k]
        indent = re.match(r'^(\s*)', lines[idx]).group(1)
        lines[idx] = f'{indent}BITMAP "{art[k]}"\n'

if len(sys.argv) > 2 and sys.argv[2] == 'write':
    with open(PATH, 'w', newline='') as f:
        f.writelines(lines)
    print('WROTE 4 cardinal frames (0,4,8,12)')
else:
    for fi, art in frames.items():
        print(f'-- frame {fi} --')
        for row in art[:10]: print('  '+row)
    print('(dry run -- pass "write" to apply)')
