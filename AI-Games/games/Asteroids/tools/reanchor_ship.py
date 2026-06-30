#!/usr/bin/env python3
# Uniformly shift all 16 ship rotation frames in ship_sprites by (DR,DC) cells,
# preserving each frame's per-frame rotation orbit (the frames are NOT centered
# individually -- that would break the rotation of a front-heavy ship). Used to
# move the rotation pivot from cell (7.5,7.5) to (5.5,5.5) so the live ship can
# render at offset 11 and reach the screen edges (see DESIGN.md "Ship velocity &
# wrap"). Max safe shift is bounded by the frame nearest each edge.
#
#   python reanchor_ship.py ../assets/sprites.bas [write]
import sys, re

PATH = sys.argv[1]
DR, DC = -2, -2   # uniform cell shift (up-left)

with open(PATH, 'r', newline='') as f:
    lines = f.readlines()

start = None
for i, ln in enumerate(lines):
    if ln.strip() == 'ship_sprites:':
        start = i + 1
        break
if start is None:
    sys.exit('ship_sprites: not found')

bm = []  # (line index, 16-char string, indent)
i = start
while len(bm) < 256:
    m = re.match(r'^(\s*)BITMAP\s+"([.X]{16})"\s*$', lines[i])
    if not m:
        sys.exit(f'unexpected line {i+1}: {lines[i]!r}')
    bm.append((i, m.group(2), m.group(1)))
    i += 1

def shift_frame(rows, dr, dc):
    grid = [['.'] * 16 for _ in range(16)]
    for r in range(16):
        for c in range(16):
            if rows[r][c] == 'X':
                grid[r+dr][c+dc] = 'X'
    return [''.join(g) for g in grid]

# Safety: confirm no frame clips with this uniform shift.
for fi in range(16):
    frame = [bm[fi*16 + k][1] for k in range(16)]
    rs = [r for r in range(16) for c in range(16) if frame[r][c] == 'X']
    cs = [c for r in range(16) for c in range(16) if frame[r][c] == 'X']
    if min(rs)+DR < 0 or max(rs)+DR > 15 or min(cs)+DC < 0 or max(cs)+DC > 15:
        sys.exit(f'frame {fi} would clip with shift ({DR},{DC})')

for fi in range(16):
    frame = [bm[fi*16 + k][1] for k in range(16)]
    new = shift_frame(frame, DR, DC)
    print(f'frame {fi:2d}: shift ({DR:+d},{DC:+d})')
    for k in range(16):
        idx, _, indent = bm[fi*16 + k]
        lines[idx] = f'{indent}BITMAP "{new[k]}"\n'

if len(sys.argv) > 2 and sys.argv[2] == 'write':
    with open(PATH, 'w', newline='') as f:
        f.writelines(lines)
    print('WROTE file')
else:
    print('(dry run -- pass "write" to apply)')
