#!/usr/bin/env python3
"""Generate baked directional-openness DATA for MSPAC.ti99.

Replicates the runtime wall checks GOSUB 700 (Pac) / 760 (ghost) over each maze,
in SCREEN coords (the same coords the runtime build used), and emits one mask
char per cell (offset +65 => 'A'..'P' for mask 0..15), 32 chars per row, 24 rows
per maze. bit0=up(1) bit1=down(2) bit2=left(4) bit3=right(8); 1 = neighbour open.
"""
import re, sys

SRC = r"C:\Users\Howie\github.git\unhuman\ti99\AI-Games\games\mspacman\src\MSPAC.ti99"

# maze -> first DATA line number (22 contiguous rows each)
MAZES = {1: 9001, 2: 9101, 3: 9201, 4: 9301}

def decode(ch):
    if 'a' <= ch <= 'p':
        return 128 + (ord(ch) - ord('a'))   # wall tiles 128-143
    return {'.':144, 'O':152, 'D':160, '+':168, ' ':32}[ch]

def load_lines():
    text = open(SRC, encoding='latin-1').read().splitlines()
    by_num = {}
    for ln in text:
        m = re.match(r'\s*(\d+)\s+DATA\s+"(.*)"\s*$', ln)
        if m:
            by_num[int(m.group(1))] = m.group(2)
    return by_num

def build_grid(by_num, first):
    # 1-based screen grid [1..24][1..32], default space(32)
    grid = [[32]*33 for _ in range(25)]
    for mr in range(1, 23):                 # DATA rows 1..22
        s = by_num[first + mr - 1]
        sr = mr + 2                         # screen row
        for i in range(1, 29):              # DATA cols 1..28
            ch = s[i-1] if i-1 < len(s) else ' '
            grid[sr][i+2] = decode(ch)      # screen col = i+2
    return grid

def wall(grid, TR, TC, pac):
    if TC < 1 or TC > 32 or TR < 1 or TR > 24:
        return True
    g = grid[TR][TC]
    if 128 <= g <= 143:
        return True
    if TR == 12 and 15 < TC < 18:           # door (cols 16,17)
        return True
    if pac and TR == 13 and 13 < TC < 20:   # pen interior (cols 14-19) - Pac only
        return True
    return False

def mask(grid, R, C, pac):
    m = 0
    if not wall(grid, R-1, C, pac): m += 1   # up
    if not wall(grid, R+1, C, pac): m += 2   # down
    if not wall(grid, R, C-1, pac): m += 4   # left
    if not wall(grid, R, C+1, pac): m += 8   # right
    return m

def main():
    by_num = load_lines()
    diffs_total = 0
    out = {}
    for mz, first in MAZES.items():
        grid = build_grid(by_num, first)
        rows = []
        ph_diff = []
        for R in range(1, 25):
            line = []
            for C in range(1, 33):
                h = mask(grid, R, C, pac=False)
                p = mask(grid, R, C, pac=True)
                if p != h:
                    ph_diff.append((R, C, p, h, grid[R][C]))
                line.append(chr(65 + h))     # bake the H mask
            rows.append("".join(line))
        out[mz] = rows
        diffs_total += len(ph_diff)
        print(f"-- maze {mz}: P vs H differ at {len(ph_diff)} cells")
        for (R, C, p, h, g) in ph_diff:
            occ = "WALL" if 128 <= g <= 143 else ("DOOR" if g==160 else f"open(code {g})")
            print(f"     screen ({R},{C}) cell={occ}  P={p} H={h}")
    print(f"== total P!=H cells across all mazes: {diffs_total}")
    print()
    # emit DATA blocks (line numbers chosen contiguous, after the maze data)
    starts = {1: 9401, 2: 9425, 3: 9449, 4: 9473}
    for mz in (1, 2, 3, 4):
        ln = starts[mz]
        print(f"; ---- maze {mz} openness ({ln}-{ln+23}) ----")
        for r in range(24):
            print(f'{ln+r} DATA "{out[mz][r]}"')
        print()

if __name__ == "__main__":
    main()
