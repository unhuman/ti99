#!/usr/bin/env python3
"""Generate the baked openness DATA BYTE blocks (open1-open4) for mspac.bas.

Reads the four `mazeN:` blocks of DATA BYTE strings from ../src/mspac.bas, replicates
the ghost wall rule (= CV `wallchk2`: walls 128-143, door at row 12 cols 16-17) over the
24x32 screen grid, and emits, per maze, 22 rows x 28 cols of mask chars 'A'..'P'
(mask 0..15 + 65). bit0=up(1) bit1=down(2) bit2=left(4) bit3=right(8); 1 = neighbour open.

Output rows/cols match the drawmaze READ order, so the loader fills
om((mr+1)*32 + (i+1)) for mr=1..22, i=1..28. Repaste the output over the open1-open4
DATA BYTE blocks in src/mspac.bas whenever a maze's walls change.

Run (PowerShell, cygwin python):
    python gen_open_cv.py
"""
import re
import os

SRC = os.path.join(os.path.dirname(__file__), "..", "src", "mspac.bas")

def decode(ch):
    if 'a' <= ch <= 'p':
        return 128 + (ord(ch) - ord('a'))
    return {'.':144, 'O':152, 'D':160, '+':168, ' ':32}[ch]

def load_mazes():
    lines = open(SRC, encoding='latin-1').read().splitlines()
    mazes = {}
    cur = None
    for ln in lines:
        mlabel = re.match(r'\s*maze(\d):', ln)
        if mlabel:
            cur = int(mlabel.group(1)); mazes[cur] = []; continue
        md = re.match(r'\s*DATA BYTE\s+"(.*)"\s*$', ln)
        if cur is not None and md and len(mazes[cur]) < 22:
            mazes[cur].append(md.group(1))
        elif cur is not None and not md:
            cur = None
    return mazes

def build_grid(rows):
    grid = [[32]*33 for _ in range(25)]   # 1-based [1..24][1..32]
    for mr in range(1, 23):
        s = rows[mr-1]
        sr = mr + 2
        for i in range(1, 29):
            ch = s[i-1] if i-1 < len(s) else ' '
            grid[sr][i+2] = decode(ch)
    return grid

def wall(grid, TR, TC):
    if TC < 1 or TC > 32 or TR < 1 or TR > 24:
        return True
    g = grid[TR][TC]
    if 128 <= g <= 143:
        return True
    if TR == 12 and 15 < TC < 18:
        return True
    return False

def mask(grid, R, C):
    m = 0
    if not wall(grid, R-1, C): m += 1
    if not wall(grid, R+1, C): m += 2
    if not wall(grid, R, C-1): m += 4
    if not wall(grid, R, C+1): m += 8
    return m

def main():
    mazes = load_mazes()
    for mz in (1, 2, 3, 4):
        rows = mazes[mz]
        assert len(rows) == 22, f"maze {mz}: {len(rows)} rows"
        for r in rows:
            assert len(r) == 28, f"maze {mz}: row len {len(r)}"
        grid = build_grid(rows)
        print(f"open{mz}:")
        for mr in range(1, 23):
            sr = mr + 2
            line = "".join(chr(65 + mask(grid, sr, i+2)) for i in range(1, 29))
            print(f'\tDATA BYTE "{line}"')
        print()

if __name__ == "__main__":
    main()
