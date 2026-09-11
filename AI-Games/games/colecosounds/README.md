# colecosounds

A **second** sound bench for Keystone Kapers. Press a digit, press a letter, hear
a candidate.

It is a separate app from `games/testsounds` on purpose, so the two can be run
against each other. That one's candidates were measured off an **Atari 2600**
recording; these are measured off a **ColecoVision** one.

## Why a second bench rather than more options in the first

The ColecoVision runs **the same sound chip as this target** — a TI SN76489 at
3.579545 MHz — so a frequency read off the recording converts straight back to
the register the game wrote:

```
divisor = 111860 / freq
```

The 2600's TIA is a different chip entirely, so every number taken from it had to
be re-imagined as an SN76489 setting rather than translated. Keeping the two sets
in separate carts means a comparison is between two *sources*, not between
entries in one list where the provenance has been lost.

## Controls

| key | does |
|---|---|
| **1**–**6** | pick a category |
| **A**–**D** | play that variant of it |
| **FIRE** | step through the held category's variants (ColecoVision has no keyboard) |

**A is always the measured one.** The others are deliberate departures, so that
what is being compared is a decision rather than a guess.

| key | category | what was measured |
|---|---|---|
| 1 | RUN | footfalls every **8 frames** — 7.7 a second |
| 2 | JUMP | a 400 ms warble, divisor 212 → 176 → 212 |
| 3 | FALL | a 240 ms run down, 108 → 212, with a bright accent |
| 4 | RISE | category 3 played backwards — see below |
| 5 | TALLY | 2-frame blips at divisor ~496 |
| 6 | ROUND | a tone held at divisor 108 for two seconds |

### The comparison worth making

**3 against 4.** The recording contains a falling run that recurs every fifteen
to twenty seconds, and *a recording cannot say which game event it belongs to* —
a fall at that spacing fits a hit or a prize equally well. So it is filed by
shape, and category 4 is its exact mirror: same notes, same holds, played
backwards. A fall and a rise are the difference between a penalty and a reward,
and this is the pair that decides which way round the game should have them.

### The one clear correction

**1A against 1C.** The measured cadence is 7.7 footfalls a second; the shipping
game runs 6, from the 2600 pass. 1C is the current one. At 6 the crook skates; at
7.7 his feet match his speed. Rhythm is the thing this analysis resolves exactly,
so this is the finding to act on first.

## Where the numbers come from

`assets/sfxref-coleco.md` — the recording, the method, what was measured, and
**the limit**: pitch recovery is exact only where the note is high. At divisor
212 the neighbours are 2.5 Hz away and a 400 ms effect cannot resolve them, so a
low reading is a neighbourhood rather than a register value.

The scripts are in **`assets/`** beside the measurements, and the process is
written up in `assets/sfxprocess.md` — how to choose a reference recording, pull
the audio, find the events, read the divisors, and move a finding into a game.
This cart is its worked example.

## Adding a candidate

Effects live in one `DATA` block at the bottom of `src/COLSND.bas` as runs of
four-byte steps — **frames, channel, value, volume** — with a `0` frame count
ending an effect and `255` ending the table. The player scans the table at boot
to find where each effect starts, so effects may be any length; add one and bump
its category's count in the `catfst`/`catnum` map near the top.

* channel `0`–`2` is a tone, and the value is the **divisor over four** (a
  divisor runs to 1023 and a `DATA BYTE` stops at 255). **A smaller divisor is a
  higher note**, so sweeps read backwards from how they sound.
* channel `3` is noise: `0`–`3` periodic (nearly pitched), `4`–`7` white.
* channel `255` is silence, for the gaps in a cadence.
* a frame count of `254` sets the step and carries on without waiting, which is
  how a held bed gets ticks played over it.

## Build

```
./build-ti.sh        # -> src/COLSND_8.bin   (Classic99, js99er)
./build-coleco.sh    # -> src/colsnd.rom     (CoolCV, blueMSX)
```

TI: 5,468 of 24,336 bytes. ColecoVision: 8 KB.
