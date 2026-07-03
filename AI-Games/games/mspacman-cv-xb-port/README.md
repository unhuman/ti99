# Ms. Pac-Man — CVBasic, faithful 1-shot port of the XB game

A direct CVBasic translation of `games/mspacman/src/MSPAC.ti99` (XB256), as opposed to the
ground-up `games/mspacman-cv` rewrite. The **maze layouts are reused verbatim** (the four `DATA`
strings), and the movement + ghost-AI logic is ported line-for-line.

**Dual target, one source.** The same `mspac.bas` builds for the TI-99/4A *and* the ColecoVision
(shared TMS9918A VDP + SN76489 sound); only the toolchain back end differs:

- **TI-99/4A** (→ `src/mspac_8.bin`, Classic99 / js99er):
  `bash games/mspacman-cv-xb-port/build-ti.sh`
  (`cvbasic --ti994a -Dhz=24` → `xas99` → `linkticart.py`).
- **ColecoVision** (→ `src/mspac.rom`, CoolCV / blueMSX):
  `bash games/mspacman-cv-xb-port/build-coleco.sh`
  (`cvbasic -Dhz=60` default target → `gasm80`). Fits Coleco's 1 KB RAM (**232 of 814 bytes**).

Both scripts pass a **required** `-Dhz=N` build-time constant (24 TI, 60 Coleco — each machine's
measured native main-loop rate); don't build `mspac.bas` with the generic shared
`.claude/skills/build-cvbasic-game/build.sh`, which doesn't pass it (compile fails loudly if `hz`
is missing, rather than risking a silent runtime divide-by-zero).

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

## Cross-platform timing — each machine runs its OWN native rate, rescaled to match
Earlier revisions capped ColecoVision's main loop down to match the TI-99's measured rate (a flat
frame-pace check). The current design instead lets **each machine tick at whatever its own hardware
naturally sustains** — TI-99 measured a stable **24fps** (its own per-frame cost, not a throttle);
ColecoVision (faster Z80) hits a full uncapped **60fps** — and **rescales every duration and
movement rate** so real-world game speed matches regardless. This gives Coleco genuine extra
smoothness instead of just idling at the TI's pace.

- **`hz`** is a **required** compile-time constant (`-Dhz=24` TI / `-Dhz=60` Coleco, passed by
  `build-ti.sh` / `build-coleco.sh`) — this machine's native ticks/sec. Never declared with `CONST`
  in the source (would collide with `-D` and fail to compile); a forgotten flag fails **loudly**
  at the first derived-constant line, not silently at runtime.
- **Plain durations** (ghost pen-release timers, fright duration, scatter/chase mode timer, eye-pew
  sweep, fruit despawn/roam-blip timers) use `cdN = (N*hz+12)/24` — exact identity at `hz=24` so the
  TI build is unaffected; more ticks needed to cover the same real time at a faster rate.
- **Pac-Man's movement** was previously "always run 2 fixed 1px sub-steps every tick" — fine at the
  TI's 24 ticks/sec (48 sub-steps/sec), but 2.5× too fast at Coleco's 60 ticks/sec if left alone. A
  phase accumulator (`pacacc`) spreads the *same* 48 sub-steps/sec across however many ticks/sec the
  machine has: exactly 2 sub-steps every tick at `hz=24` (identity), ~0.8 sub-steps/tick at `hz=60`
  — same average speed, but genuinely smoother 1px-at-a-time motion on Coleco instead of the TI's
  2px hops.
- **Ghost speed** was "skip 1 tick out of every `sp(gi)`" — a *discrete, nonlinear* throttle that
  does **not** scale by simply multiplying `sp(gi)` by the tick-rate ratio (verified by hand: for
  `sp=8`, naive scaling left Coleco ghosts at ~57 moves/sec against an intended ~21). Replaced with
  a per-ghost rate accumulator (`#spcd()`), `NUM=24*(sp(gi)-1)`, `DEN=hz*sp(gi)` — algebraically
  identical to the original ratio at `hz=24` (the 24 cancels), and correctly reproduces the same
  real-world moves/sec at any other `hz`. The old "`sp(gi)<40` skip the check, always move" bypass
  (a micro-optimization to dodge a division CVBasic no longer needs dodging, via the accumulator)
  was removed so max-speed Blinky is also correctly scaled on Coleco.
- **Tunnel ghosts were ~2.5× too slow on Coleco** (found after playtesting the above): the tunnel/
  fright half-speed throttle (`gtslow`) and the `sp(gi)` accumulator were sequential checks, the
  second only reached if the first didn't already jump away — so a tunnel ghost's `sp(gi)`
  accumulator only advanced on the ~half of ticks `gtslow` let through. Harmless at one fixed `hz`
  (both throttles ride the same clock, so whatever compounded rate results is self-consistent on
  that machine), but `gtslow`'s absolute fire rate is a hz-independent 12/sec by design, so gating
  the `sp(gi)` accumulator's *increment* behind it made that accumulator fill at 12/sec instead of
  the `hz/sec` its `NUM/DEN` math assumes — worked out by hand to a ~2.5× slowdown on Coleco.
  Fixed by evaluating both throttles independently every tick (`skip1`/`skip2` flags, no early
  jump) so each accumulator always advances at its own correct rate.
- **Ghosts almost never actually throttled in the real tunnel** (found while diagnosing the above
  with an on-screen moves/sec counter): `ty1`/`ty2` (the tunnel rows' Y-coordinates, computed once
  while parsing the maze) used the formula `(mr+1)*8-3`, but every other place in this file converts
  a Y position to its grid row via `(y+11)/8` — solving that backwards for which Y maps to row
  `mr+1` gives `(mr+1)*8-11`, not `-3`. Confirmed by computing `(oldTy1+11)/8 = mr+2`, one row past
  intended. So the tunnel-slow throttle's exact-equality check (`by=ty1`) matched ghosts one row
  *below* the true tunnel (usually not a walkable corridor there), while ghosts genuinely in the
  tunnel were never throttled at all — full speed through the real tunnel, every time, on **both**
  platforms (not a Coleco-specific bug, just more noticeable once the other rate issues were fixed).
  Also silently miscalculated the roaming fruit's tunnel-approach target row (`spawnfruit`'s
  `ftr=(tg+11)/8` uses the same `ty1`/`ty2`) — fixed as a side effect.
- **Ghost "eyes" (a caught ghost returning to the pen) returned way too fast on Coleco, with a
  broken-sounding 'pew'.** Eyes (`gsi=2`) matched neither `skip1`'s condition (`gsi=1`) nor
  `skip2`'s (`gsi=0`) — they moved **completely unthrottled**, every tick, on both the normal ghost
  pass and the separate "double speed" extra pass, i.e. 2 full moves/tick unconditionally = raw
  `hz`-dependent speed with zero scaling. 2.5× too fast on Coleco, and since the eye 'pew' sound
  fires on every direction change, 2.5× the movement rate also meant 2.5× the pew rate — explaining
  the "wrong sound" as a direct symptom, not a separate bug. Fixed with the same accumulator
  approach, targeting a flat 24 fires/sec (the TI's "always move" baseline) — exact identity at
  `hz=24` (fires every tick, matching the old unthrottled TI behavior), correctly rate-limited at
  any other `hz`. Separate accumulators for the normal pass and the double-speed pass so together
  they reproduce the original "moves twice per tick, every tick" baseline.
- **TI-99 speed was raised, not just capped.** CVBasic compiles every `%` (modulo) — even by a
  compile-time-constant power of 2 — to a genuine `DIV` instruction, one of the slowest ops on the
  TMS9900, with no compiler-side conversion to `AND`. Converted every power-of-2 `%` to `AND`
  throughout the hot path, deduplicated `#fc AND 7` (was recomputed via `DIV` up to 5×/tick for the
  identical value), and eliminated the ghost speed throttle's division-by-a-runtime-variable
  entirely (folded into the rate accumulator above). Measured effect (temporary on-screen counter):
  TI-99's native rate went from fluctuating 22–24fps to a solid, stable 24fps.

This is a bigger, less mechanically-obvious change than a simple pacing cap — it needs an emulator
playtest on both targets to confirm ghost speed and Pac-Man's movement feel right, not just that it
compiles.

## Status
One-shot port; compiles for **both** TI-99/4A (`mspac_8.bin`, 265 RAM bytes) and ColecoVision
(`mspac.rom`, 16 KB, 245 RAM bytes) from one source. TI runtime-tested by the user; the
ColecoVision build needs an emulator pass (keypad 8-3-8, joystick, sound, and Z80 speed with the
per-frame `VPEEK` maze probes). Fixed after first run: real sprite art,
animated title (Pac + ghosts), sprites hidden on title entry/exit (no more game-over pollution),
removed the colour-table poke that corrupted the screen, and corrected collision/AI distance math
(CVBasic 8-bit subtraction wraps — `ABS()` over it and squaring negative diffs were both wrong).
