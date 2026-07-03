#!/usr/bin/env python3
# Compute the per-frame bullet-spawn (nose) offset table (#ndx_t/#ndy_t in
# ASTIROIDS.bas) from the ship art. For each of the 16 rotation frames it
# finds the nose tip (farthest pixel along the +nose axis from the pivot at
# cell 5.5,5.5 -- the same pivot the render offset-11 uses), takes its
# centroid, steps a small GAP further forward to clear the hull, and emits
# the (dx,dy) in screen px from the ship center (spx,spy). This replaces the
# old "9*sin/9*cos" formula, which assumed the nose sits exactly 9px along
# the facing axis from center -- true for the original symmetric art, but
# NOT after the top-left reanchor shifted the art (and moved the pivot to a
# deliberately off-center 5.5,5.5 point) to let the nose reach the screen
# edge. Mirrors tools/flame_offsets.py (same pivot, same projection method,
# opposite direction). Re-run if ship_sprites art changes, then paste the
# "--- paste ---" block over the #ndx_t/#ndy_t init in ASTIROIDS.bas.
#
#   python nose_offsets.py ../assets/sprites.bas [GAP_cells]
import sys, re

PATH = sys.argv[1]
GAP = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5   # cells beyond nose-tip center

sin_t = [0,25,45,57,64,57,45,25,0,-25,-45,-57,-64,-57,-45,-25]
cos_t = [64,57,45,25,0,-25,-45,-57,-64,-57,-45,-25,0,25,45,57]
PR = PC = 5.5  # pivot cell (same as render offset 11 => 11/2)

with open(PATH) as f:
    lines = f.readlines()
start = next(i for i,l in enumerate(lines) if l.strip()=='ship_sprites:') + 1
rows_all = []
i = start
while len(rows_all) < 256:
    m = re.match(r'^\s*BITMAP\s+"([.X]{16})"', lines[i])
    if m: rows_all.append(m.group(1))
    i += 1

dxs, dys = [], []
for fi in range(16):
    frame = rows_all[fi*16:(fi+1)*16]
    pix = [(r,c) for r in range(16) for c in range(16) if frame[r][c]=='X']
    su, cu = sin_t[fi]/64.0, cos_t[fi]/64.0   # nose dir (col,row)=(su,-cu)
    nx, ny = su, -cu                          # +nose unit (col,row)
    proj = [ (c-PC)*nx + (r-PR)*ny for (r,c) in pix ]
    R = max(proj)
    tip = [pix[k] for k in range(len(pix)) if proj[k] >= R-0.6]
    bc = sum(c for r,c in tip)/len(tip)
    br = sum(r for r,c in tip)/len(tip)
    fc = bc + GAP*nx                          # spawn point = tip centroid + GAP along +nose
    fr = br + GAP*ny
    dx = round(2*(fc-PC))                      # screen px from pivot (2x magnification)
    dy = round(2*(fr-PR))
    dxs.append(dx); dys.append(dy)
    print(f'frame {fi:2d}: R={R:.2f} tipC=({br:.1f},{bc:.1f}) -> dx={dx:+d} dy={dy:+d}')

def emit(name, vals):
    out = []
    for k in range(0,16,4):
        out.append(' : '.join(f'{name}({k+j})={vals[k+j]}' for j in range(4)))
    return out

print('\n--- paste ---')
for l in emit('#ndx_t', dxs): print('\t'+l)
for l in emit('#ndy_t', dys): print('\t'+l)
