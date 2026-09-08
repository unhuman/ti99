# testsounds

A sound bench for Keystone Kapers. Press a digit, hear a candidate effect.

Not a game — a tool. It exists because tuning a sound effect by editing the game,
rebuilding it, and playing to the screen where that effect fires is hopeless, and
because the effects it is tuning against were hand-picked numbers that had never
been compared with anything.

## Controls

Digits **1–9**. Each plays one candidate and returns to the menu.

| key | effect |
|---|---|
| 1 | run, a single step |
| 2 | run, the cadence — 6 a second |
| 3 | jump — 415 Hz warbling against 188 |
| 4 | time up — a warble wandering 235–371 Hz |
| 5 | pickup — **rising**, 295 → 1028 → 2543 Hz |
| 6 | hit — the jump's warble with a tail **falling** to 235 Hz |
| 7 | tally — ticks every 64 ms |
| 8 | pickup as a smooth rise, more notes over the same span |
| 9 | hit as a smooth fall, the mirror of 8 |

5 against 6, and 8 against 9, are the comparisons worth making: one rises and one
falls, which is the difference between a reward and a penalty.

## Where the numbers come from

`assets/sfxref.md` — measured off an Atari 2600 recording rather than guessed,
with the analysis method and the two mistakes the first pass made.

## Adding a candidate

Effects live in one `DATA` block at the bottom of `src/TESTSND.bas`, eight steps
of four bytes each: **frames, channel, value, volume**.

* channel `0`–`2` is a tone, and the value is the **divisor over four** — a
  divisor runs to 1023 and a `DATA BYTE` stops at 255. Pitch is
  `3579545 / (32 × divisor)`, so a **smaller divisor is a higher note** and
  sweeps read backwards from how they are written.
* channel `3` is noise, and the value is the register `0`–`7`: `0`–`3` periodic
  (buzzy, nearly pitched), `4`–`7` white, rate falling as the number rises.
  `3` and `7` clock the noise from tone channel 2, making it tunable.
* channel `255` is silence, for the gaps in a cadence.
* a step of **0 frames** ends the effect early.

**Eight steps of four bytes per effect, always.** The player skips to an effect
by multiplying, so a short one must be *padded* with zero-frame steps rather than
just ending. Get the count wrong and every effect after it plays somebody else's
data — silently, because the bytes are all valid.

## Build

```
./build-ti.sh        # -> src/TESTSND_8.bin   (Classic99, js99er)
./build-coleco.sh    # -> src/testsnd.rom     (CoolCV, blueMSX)
```

Both derive from Keystone Kapers' scripts with the art generation and the thirteen
game-specific gates removed. What is kept is the part about the **toolchain**
rather than about that game — the `PATH` order that stops MSYS2 shadowing
Cygwin's runtime, the `cygpy` argument handling, and the 8-bit truncation sweep —
because those bite any CVBasic build on this machine.

TI: 4,000 of 24,336 bytes. ColecoVision: 8 KB.
