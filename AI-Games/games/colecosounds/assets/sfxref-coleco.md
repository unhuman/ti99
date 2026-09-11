# Keystone Kapers sound effects, measured off the ColecoVision

The candidates in `src/COLSND.bas` come from a ColecoVision longplay:
`https://www.youtube.com/watch?v=TLXbhNgpxMU` — 734 s, *Keystone Kapers
[COLECOVISION] 20,450*.

## Why this recording and not the 2600 one

The sibling bench (`games/testsounds`) took its numbers from an **Atari 2600**
recording. The 2600's TIA is a different chip: a 5-bit divider with its own
waveform table and no relation to anything we can write. Every number taken off
it had to be *re-imagined* as an SN76489 setting.

The ColecoVision runs **the same chip as our TI-99/4A target** — a TI SN76489 at
3.579545 MHz — so the game's register writes are recoverable rather than merely
imitable:

```
freq = 3579545 / (32 * divisor)        divisor = 111860 / freq
```

## How the numbers were got

No numpy on this machine, so the analysis leans on the standard library:

* **`audioop.rms()`** over 10–20 ms blocks to find where something happens. C
  speed, so the whole 734 s is a few seconds' work.
* **A Goertzel filter per candidate divisor** to identify the pitch. This asks a
  better question than an FFT peak-pick or a zero-crossing count: not *"what
  frequency is this?"* but **"of the divisors the chip can actually play, which
  one is present?"** The answer is the register value directly.

### The limit, stated plainly

**The recovery is only exact where the pitch is high.** Adjacent divisors sit
about `freq / divisor` apart in hertz:

| divisor | frequency | neighbours | window needed |
|--------:|----------:|-----------:|--------------:|
| 40 | 2,797 Hz | ~70 Hz apart | 15 ms — easy |
| 108 | 1,035 Hz | ~10 Hz apart | 100 ms — usually fine |
| 212 | 527 Hz | ~2.5 Hz apart | 420 ms — longer than the effect |

So a 400 ms warble down at divisor 212 comes back as *"somewhere around 212"*,
with 211 and 210 scoring identically. Read a high-pitched result as the register
value and a low-pitched one as a neighbourhood. Still far better than the 2600
source, where nothing translates at all — but **not** the same as reading the ROM.

A second caveat: the recording carries music and several channels at once, so a
reading is the *loudest* thing in that window, not necessarily the effect.

## What was measured

### Footsteps — the one clear correction

Onsets over a twelve-second continuous run, from the RMS track:

```
gaps (s): 0.13 0.13 0.13 0.14 0.13 0.14 0.13 0.14 0.13 0.13 0.13 0.14 ...
median 0.130 s  =  7.7 steps a second  =  8 frames at 60 Hz
```

**The 2600-derived bench put this at six a second.** At 7.7 the crook's feet
match his speed; at 6 he skates. This is the measurement most worth acting on,
because it is a *rhythm* rather than a pitch and the analysis resolves rhythm
exactly.

The step itself reads at the bottom of the divisor range, which is what a
percussive noise burst looks like to a pitch detector — it is the noise channel,
not a tone.

### Jump — a warble that rises and returns

400 ms, the commonest effect in the recording after the footsteps, recurring
every few seconds of play:

```
divisor  212  192  176  192  212
freq     527  582  635  582  527 Hz
```

Up and back down, about 80 ms a step.

### A falling run — 240 ms

Recurring every fifteen to twenty seconds:

```
divisor  108  120  144  [72]  176  212
freq    1035  932  777 [1553] 635  527 Hz
```

Descending, with one bright accent partway through.

**Which game event this is cannot be heard.** A recording says what the chip did,
not why, and a falling run at that spacing fits either a hit or a prize being
taken. The bench therefore files it by **shape** (category 3, FALL) and offers
its exact mirror as category 4 (RISE) — the same notes and holds played
backwards. That pair is the comparison worth making, because a fall and a rise
are the difference between a penalty and a reward, and the recording cannot
settle which this game wanted.

### Round boundary — a held tone

Twice in the recording, ~46 s apart and so almost certainly the round boundary, a
tone **holds at divisor 108** (~1,035 Hz) for two full seconds, with brief blips
over it. A ~3 s warbling jingle precedes it.

### Ticks

Short 2-frame blips at divisor ~496 (~226 Hz) punctuate the quiet stretches.

## Tooling

The analysis scripts are not in the repo — they were written against a scratch
copy of the audio and are recorded here so the work can be repeated:

* `colscan.py` — RMS + zero-crossing sweep, finds events and rough pitch
* `colfreq.py` — the Goertzel divisor identifier, with the resolution note above
* `colevents.py` — walks each event and reports its pitch **shape** (rising,
  falling, warble, steady), which is what classifies an effect

Re-deriving them needs the audio, `ffmpeg -ac 1 -ar 44100` to a WAV, and nothing
else.
