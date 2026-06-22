# <GAME TITLE> — Design

> Fill this in **before** writing code. Keep it honest and short. Anything you can't answer here
> is a decision you haven't made yet. See repo `CLAUDE.md` for platform rules (§1–§8).

## 1. Concept & objective
- One-sentence pitch:
- Win condition:
- Lose condition:

## 2. Controls
| Action | Key (`CALL KEY` ASCII) | Notes |
|--------|------------------------|-------|
| Up     | `E` = 69 | TI ESDX diamond |
| Left   | `S` = 83 | |
| Right  | `D` = 68 | |
| Down   | `X` = 88 | |
| Fire/etc | | |

(Or `CALL JOYST(1,X,Y)` — document axis values used.)

## 3. Screen
- Mode: **Screen2** (default) / Screen1 — why:
- Layout sketch (24 rows × 32 cols; mark walls/HUD/play area):

```
(ASCII sketch here)
```

## 4. Characters & sprites
| Purpose | Char code | `CHAR2` pattern (16 hex) | `COLOR2` set = INT((code-24)/8) | fg | bg |
|---------|-----------|--------------------------|---------------------------------|----|----|
|         |           |                          |                                 |    |    |

- Sprites (if any): `CALL SPRITE` patterns use **Screen1** `CALL CHAR` defs. List #, pattern, color, motion.

## 5. Sound
- Effects (`CALL SOUND(dur,freq,vol)`):
- Music / sound lists (`SLCOMPILER`/`PLAY`), if any:

## 6. Game-state variables
List every variable (short integer names — this doubles as a stack budget). Strings cost the most.

| Name | Meaning | Range |
|------|---------|-------|
|      |         |       |

## 7. Main-loop / GOSUB map
- Line-number bands (e.g. 100 init, 200 loop, 500 game-over, 900 subs):
- Loop steps: input → update → render → pace (`DELAY`/`SYNC`) → win/lose test.
- Subroutines (`GOSUB` target → purpose):

## 8. Memory & stack notes
- Big data kept in `DATA` + `READ` on demand? Y/N
- String variables reused / minimized? Y/N
- Estimated risk vs the ~8K stack / 24488-byte program budget:

## 9. Compiler-safety checklist (must all hold — see `CLAUDE.md` §6)
- [ ] Integer / fixed-point only; `INT()` around every `/` and `SQR`
- [ ] Randomness via `INT(RND*N)` or `CALL LINK("IRND",…)`
- [ ] Timing via `DELAY` / paired `CALL SOUND` / `SYNC` — never raw `FOR/NEXT`
- [ ] No trailing `::` on any line; no block `IF`/`END IF` (XB has neither)
- [ ] `SUB`/`CALL LINK` names unique in first 6 chars, not reserved; `LINK` name a string constant
- [ ] `RESTORE` targets a `DATA` line; no `GOTO` into `DATA`
- [ ] No `SIN/COS/TAN/ATN/LOG/EXP/DEF/IMAGE/DISPLAY USING`; `CALL CLEAR` (not `DISPLAY ERASE ALL`)
- [ ] `PRINT` ≤20 items; no `ON GOTO/GOSUB` inside `IF/THEN/ELSE`
- [ ] Disk program name UPPERCASE, ≤8 chars; default Screen2; output `-X`

## 10. Build & run
- Disk program name:
- Steps: standard lifecycle (`CLAUDE.md` §8).

## 11. Acceptance criteria / test plan
- [ ] Runs interpreted in XB256 with expected behavior
- [ ] (game-specific checks…)
- [ ] Compiles with no unsupported-statement errors
- [ ] `-X` build runs identically to interpreted
