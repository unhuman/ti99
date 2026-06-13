# Dot Muncher — Design

> Purpose: **prove the toolchain end-to-end** (write → run in XB256 → compile → `-X` → run) and
> exercise the per-game framework, while seeding the later Ms. Pac-Man. Deliberately minimal.

## 1. Concept & objective
- Pitch: Move a muncher around a small walled maze and eat every dot.
- Win condition: dots remaining (`DT`) reaches 0.
- Lose condition: none in v1 (no enemy yet — that's the next iteration).

## 2. Controls
| Action | Key (`CALL KEY` ASCII) | Notes |
|--------|------------------------|-------|
| Up     | `E` = 69 | TI ESDX diamond (fixes the mismapped old Pac-Man) |
| Left   | `S` = 83 | |
| Right  | `D` = 68 | |
| Down   | `X` = 88 | |

Movement is continuous while a key is held: `CALL KEY` returns `S=-1` for a held key, so we
move whenever `S<>0` and pace the loop with `DELAY`.

## 3. Screen
- Mode: **Screen2** — validates the XB256 path (`SCRN2`/`CHAR2`/`COLOR2`).
- Background black (`CALL SCREEN(2)`); HUD on row 1; maze is a box, rows 3–12, cols 10–23.

```
Row1:  SCORE 0  DOTS 87
Row3:  ##############        (cols 10..23)
Row4:  #C...........#        C = muncher start (4,11)
 ...   #............#
Row8:  #..########..#        interior divider (row 8, cols 13..20)
 ...   #............#
Row12: ##############
```

## 4. Characters & sprites
| Purpose | Char code | `CHAR2` pattern (16 hex) | `COLOR2` set = INT((code-24)/8) | fg | bg |
|---------|-----------|--------------------------|---------------------------------|----|----|
| Wall    | 96  | `FFFFFFFFFFFFFFFF` | 9  | 6 (lt blue) | 1 (transp) |
| Dot     | 42  | `0000001818000000` | 2  | 16 (white)  | 1 |
| Muncher | 128 | `3C7EFCF8F8FC7E3C` | 13 | 12 (lt yellow) | 1 |

Codes chosen to avoid clobbering letters/digits used by `DISPLAY AT` text: 96 = `` ` ``,
42 = `*`, 128 = beyond ASCII — none appear in "SCORE/DOTS/YOU WIN/PRESS ANY KEY". (The old
Pac-Man's player char 80 = `P` would have corrupted the word "PRESS".) No sprites in v1.

## 5. Sound
- Eat blip: `CALL SOUND(20,880,2)`.
- Win jingle: `CALL SOUND` C5–E5–G5 (523, 659, 784).

## 6. Game-state variables
| Name | Meaning | Range |
|------|---------|-------|
| SC | score | 0…~870 |
| DT | dots remaining | 0…~87 |
| PR,PC | player row, col | 4..11 / 11..22 |
| NR,NC | candidate target cell | same |
| K,S | `CALL KEY` key / status | — |
| G | `GCHAR` result at a cell | 32/42/96/128 |
| R,C | init dot-fill loop counters | — |

No strings stored in variables (HUD uses string constants) — stack-friendly.

## 7. Main-loop / GOSUB map
- Bands: 100 init, 200 var/maze, 300 dot-fill, 400 HUD, 500 main loop, 700 win.
- Loop: read key → if `S=0` skip → compute `NR,NC` → `GCHAR` target → if wall, skip move →
  else erase old cell, move, if dot eat (+score, −dot, blip, HUD) → draw player → win test → `DELAY`.
- No `GOSUB` needed (small enough to be linear).

## 8. Memory & stack notes
- Tiny. No `DATA`, no string variables, ~87 dots. Well within budget.

## 9. Compiler-safety checklist (all hold)
- [x] Integer only; no `/` or `SQR` used
- [x] No `RND`
- [x] Timing via `CALL LINK("DELAY",40)` — no bare `FOR/NEXT` delay
- [x] No trailing `::`; no block `IF`/`END IF` — all single-line `IF`
- [x] Only `CALL LINK` with string-constant names (`SCRN2`/`CHAR2`/`COLOR2`/`DELAY`)
- [x] No `RESTORE`/`DATA`
- [x] No unsupported functions; `CALL CLEAR` used
- [x] `DISPLAY AT` lists ≤20 items, no SIZE; HUD padded with trailing spaces to clear stale digits
- [x] Disk name `MUNCH` (5 chars); Screen2; output `-X`

## 10. Build & run
- Disk program name: **`MUNCH`**.
- Steps: standard lifecycle (`CLAUDE.md` §8). See `README.md` for the exact Classic99 key sequence.

## 11. Acceptance criteria / test plan
- [ ] Runs interpreted in XB256: maze draws, HUD shows correct initial `DOTS` count
- [ ] Held direction key moves continuously; walls block; eating a dot increments score and
      decrements dots with a blip
- [ ] Eating the last dot plays the win jingle and shows "YOU WIN!"
- [ ] Compiles with no unsupported-statement errors (compiler shows `L100…` then returns clean)
- [ ] `MUNCH-X` runs identically (just much faster) — **this is the toolchain-validation signal**
