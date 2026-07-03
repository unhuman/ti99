# Ms. Pac-Man — CVBasic, faithful 1-shot port of the XB game

A direct CVBasic translation of `games/mspacman/src/MSPAC.ti99` (XB256), as opposed to the
ground-up `games/mspacman-cv` rewrite. The **maze layouts are reused verbatim** (the four `DATA`
strings), and the movement + ghost-AI logic is ported line-for-line.

**Dual target, one source.** The same `mspac.bas` builds for the TI-99/4A *and* the ColecoVision
(shared TMS9918A VDP + SN76489 sound); only the toolchain back end differs:

- **TI-99/4A** (→ `src/mspac_8.bin`, Classic99 / js99er):
  `bash games/mspacman-cv-xb-port/build-ti.sh`
  (`cvbasic --ti994a` → `xas99` → `linkticart.py`).
- **ColecoVision** (→ `src/mspac.rom`, CoolCV / blueMSX):
  `bash games/mspacman-cv-xb-port/build-coleco.sh`
  (`cvbasic` default target → `gasm80`). Fits Coleco's 1 KB RAM (**220 of 814 bytes**).

Both build scripts pass a `-Dhz=N` flag left over from an earlier, reverted experiment (see
"Cross-platform timing, reverted" below) — this source doesn't reference `hz` at all, so the flag
is silently unused; harmless, but safe to remove from the scripts if it's ever confusing.

## Translation map (XB → CVBasic)
- `M$()` wall cache → the maze is read **straight from VRAM** (`VPEEK` of `scr(r,c)`, `scr` =
  `DEF FN`, VRAM `$1800`); dots are eaten with `VPOKE`. Wall/dot probes call `VPEEK` on demand —
  **no RAM mirror.** (An earlier revision cached the maze in an `mc(768)` RAM array to save VPEEKs;
  that was 768 bytes and, with the `om(768)` openness cache, blew past ColecoVision's 1 KB RAM by
  ~930 bytes. In *compiled* CVBasic a `VPEEK` is a few inline instructions — not the slow
  *interpreted* GCHAR the XB perf doctrine warns about — and the maze is probed only ~10–15×/frame,
  so dropping the mirrors costs almost nothing and lets one source fit both machines.)
- `P$()`/`H$()` openness cache → `om(768)` is gone too; the per-cell openness mask (1=up 2=down
  4=left 8=right passable) is computed **on demand** by `openmask`, which `VPEEK`s the four
  neighbours using the same wall rule the old mask-build loop used (walls 128–143, plus the pen
  exceptions at rows 11–13). The ghost and roaming-fruit direction loops `GOSUB openmask` once per
  decision and bit-test `mk`. Pac-Man stays on `wallchk` (it carries an extra row-13 pen rule the
  ghost mask doesn't).
- `CALL LOCATE/SPRITE` → `SPRITE n, sy-2, sx-1, frame, colour`; TI colour N → CVBasic N-1.
- `::` → `:`; XB block `IF` clauses → CVBasic `IF…THEN`/`END IF`.
- Ghost target distance: XB's `SG*dist` signed-compare → a `flee` flag (max vs min distance);
  squared differences forced to 16-bit so negative diffs don't wrap before squaring.
- Sprite art is the **actual TI art**, converted from the XB `CALL CHAR` quadrant hex
  (TL,BL,TR,BR interleaved to 16×16 rows).

## Known simplifications (not yet faithful)
- **Sound** uses an SFX-duration timer (CVBasic `SOUND` plays until silenced): dot waka, frighten
  warble, descending ghost-eat sweep, fruit chime + roam blip, an eye "pew" on turns, and a 3-voice
  original start jingle (12 chords, melody + harmony + bass) played once when a game begins.
- **Scoring** (HUD appends a `0`, so score = `#pt`×10): dot 10, power pellet 50, ghosts
  200/400/800/1600, fruit 100/200/500/700/1000/2000/5000, extra life at 10000 (three-bell sound).
- **Presentation:** data-driven start tune (`jingle_data`), 1-second "get ready" hold (`ready`)
  after a respawn and after the tune, blinking energizers (char 152 toggled), and a 2-frame ghost
  walk animation (sprite defs 5 and 10, alternated by `#fc`). Game over clears all sprites.
- Sprite draw offset (`sy-2, sx-1`) may need a ±1 tweak after eyeballing on hardware.

## Implemented since the first port
- Per-level **fruit shapes** (cherry…banana) via runtime `DEFINE SPRITE`; **level-clear flash**
  (sprites + sound cleared first); **death spin** animation; **8-3-8** title cheat (LEVEL/LIVES select).
- **Per-maze wall colour** (`setwc` + four `DEFINE COLOR` tables, walls 128–143 and the `+` cross):
  maze 1 magenta, 2 light blue, 3 light red, 4 dark blue — the XB `WC` palette (TI 14/6/10/5 →
  CV 13/5/9/4). Applied in `drawmaze` and restored during the level-clear flash.
- Ghosts: **reverse-on-energizer** (except already-scared), no reverse while scared, no reverse
  while exiting the pen (`gx<>121 AND gy<>77`).
- Ghost speed: distinct **Blinky > Pinky > Inky > Clyde** ranking via per-ghost caps `spc()`
  (Blinky 40≈100%, Pinky 16≈94%, Inky 12≈92%, Clyde 10≈90%); base `sp()` rises +4/level to each cap.
  **Cruise Elroy**: Blinky takes extra move-steps as the maze empties (`dt<30` every other frame,
  `dt<10` every frame), becoming the closer. A level-wide overdrive still boosts all chasers at `le>9`.
- **Timer audit:** every value that exceeds 255 is 16-bit (`#fc #ft #fb #mt #fw`). CVBasic 8-bit
  vars wrap at 256, which silently broke the scatter/chase (`mt=800→32`), fright (`fb=300→44`), and
  fruit-timeout (`fw>400`, never true) timers when ported from XB.

## Cross-platform timing
The main loop is **frame-locked to ~24Hz** (`#pacef`/`pcyc`), measured with a temporary on-screen
loop counter, not guessed. Since 60fps doesn't divide evenly into 24, the loop alternates waiting 2
and 3 VDP frames per step (`pcyc` toggles 0/1, wait threshold `2 + pcyc`) for an average of 2.5
frames/step = 24Hz.

**TI-99 speed was raised, not just capped.** CVBasic compiles every `%` (modulo) — even by a
compile-time-constant power of 2 — to a genuine `DIV` instruction, one of the slowest ops on the
TMS9900; there's no compiler-side conversion to a bitwise AND. The hot path (Pac-Man movement, all
4 ghosts, every tick) did several of these unconditionally, including `#fc % sp(gi)` — a division
by a *runtime variable* (impossible to convert to AND), running up to 3×/tick for the whole game
(the ghost speed throttle). Fixed by: converting every power-of-2 `%` to `AND` (`% 8`→`AND 7`,
`% 16`→`AND 15`, `% 2`→`AND 1`); computing `#fc AND 7`/`#fc AND 1` **once** per tick and reusing
them (was recomputed via `DIV` up to 5×/tick for the identical value — Pac's chomp frame, plus once
per ghost's walk-cycle check); and replacing the variable-divisor ghost speed throttle with a
per-ghost countdown counter (`spcd()`) that reproduces the exact same skip-1-tick-in-`sp(gi)` rate
using only a decrement + compare, no division at all.

Measured effect: the TI-99's native loop rate went from **fluctuating 22–24fps to a solid, stable
24fps** — the same optimization also benefits ColecoVision, which now hits a full uncapped 60fps
(previously not re-measured after this pass). 24Hz remains the shared target since it's the TI's
now-stable ceiling; capping both machines to it keeps the tuned TI feel, sounds included.

**Follow-up cleanup pass (deliberately conservative, no timing/behavior changes):**
- Removed `wallchk2` — provably dead code (confirmed via search: never called anywhere), left over
  from before `openmask` replaced its 4-calls-per-decision usage. Zero behavior risk; it never ran.
- `ghost:` was evaluating the exact same "is this ghost in the tunnel" condition twice, back to
  back (once for the overdrive exclusion, once for the speed throttle) — computed once into `intun`
  and reused. Pure common-subexpression elimination: the condition itself is byte-for-byte
  unchanged, this only removes a redundant re-evaluation a few lines later.
- `dr % 4` (in the death-spin animation) → `dr AND 3` — same DIV-avoidance as the rest of the file;
  cold path (only runs during Pac-Man's death sequence), so negligible speed impact, but free and
  consistent with the rest of the pass.
- `#fc % 3` (roaming-fruit trigger) and `#fw % 6` (fruit roam-blip cadence) — the two remaining
  16-bit `DIV`s (~92–124 TMS9900 cycles each) — converted to countdowns (`frcd`, `frbcd`) using the
  same proven pattern as the ghost speed throttle's `spcd()`: `frcd` decrements every tick
  unconditionally (preserving the original "fires on a fixed 3-tick global cadence" — only the
  *phase* within that cadence changes, which doesn't affect gameplay, same reasoning already
  validated elsewhere in this file); `frbcd` decrements once per `movefruit` call (the same rate
  `#fw` itself already advances at) and is reset to 6 at spawn. Estimated savings: each conversion
  trades a ~92–124 cycle `DIV` for a ~35–50 cycle decrement+compare, but both only ever run while
  `fa=1` (fruit actively roaming, a minority of play) — a real but proportionally small win compared
  to the ghost-speed throttle fix above, which ran far more often across the whole game.

**Reverted experiment (2026-07):** a later pass tried letting ColecoVision run at its own native
60fps instead of being capped to match the TI, rescaling every duration/movement rate from a
`-Dhz=N` build constant so real-world game speed would still match. It repeatedly introduced new,
hard-to-pin-down bugs in ghost tunnel behaviour and ghost-eyes speed across several rounds of
fixes that each seemed to work in isolation but didn't hold up in play. Rather than keep
iterating, that whole approach was reverted back to this simpler "throttle Coleco down to the
TI's rate" design, which is the version actually confirmed working. If native-Coleco-speed is
revisited later, budget for a much more careful, incremental verification pass — ideally with
real emulator/hardware access during development, not indirect user-relayed testing across many
back-and-forth rounds.

## Status
One-shot port; compiles for **both** TI-99/4A (`mspac_8.bin`, 239 RAM bytes) and ColecoVision
(`mspac.rom`, 16 KB, 220 RAM bytes) from one source. TI runtime-tested by the user; the
ColecoVision build needs an emulator pass (keypad 8-3-8, joystick, sound, and Z80 speed with the
per-frame `VPEEK` maze probes). Fixed after first run: real sprite art,
animated title (Pac + ghosts), sprites hidden on title entry/exit (no more game-over pollution),
removed the colour-table poke that corrupted the screen, and corrected collision/AI distance math
(CVBasic 8-bit subtraction wraps — `ABS()` over it and squaring negative diffs were both wrong).
