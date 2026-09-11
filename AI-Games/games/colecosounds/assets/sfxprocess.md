# Making and tuning sound effects from a reference recording

A repeatable way to go from *"the original sounded like this"* to numbers in a
`DATA` table, and then to a sound in the game you can defend. Written after doing
it twice for Keystone Kapers — once badly, from an Atari 2600 recording, and once
well, from a ColecoVision one.

Three scripts and a bench cart. None of it needs numpy.

It lives in `games/colecosounds/assets/`, beside the measurements it produced
and the cart that plays them. **Starting a new game's sound pass? Copy the three
`sfx*.py` scripts and this file into that game's `assets/`** -- the process is the
part worth reusing; the numbers here belong to Keystone Kapers.

---

## 0. Pick the recording — this decides everything after it

**Take the reference with YOUR sound chip in it.** The TI-99/4A's SN76489 is also
in the ColecoVision, the SG-1000, the Master System and the BBC Micro. If the
game you are porting appeared on any of those, that recording lets you *recover*
register values:

```
freq = 3579545 / (32 * divisor)        divisor = 111860 / freq
```

The Atari 2600's TIA is a 5-bit divider with its own waveform table and no useful
relation to an SN76489, so numbers taken off it must be **re-imagined**, not
translated — every one becomes a judgement, and judgements are what this whole
exercise is trying to replace.

Keystone Kapers' first sound pass used a 2600 longplay because that is the
famous version. The ColecoVision port existed the whole time.

## 1. Get the audio

`yt-dlp` under the Cygwin python, with the android player client (the default web
client wants a PO token for audio-only formats):

```python
opts = {"format": "bestaudio[ext=m4a]/bestaudio/18",
        "outtmpl": OUT, "quiet": True,
        "extractor_args": {"youtube": {"player_client": ["android"]}}}
```

Then to mono WAV, which is what all three scripts want:

```
ffmpeg -i in.m4a -ac 1 -ar 44100 out.wav
```

Download whole, then cut locally — Krita's bundled ffmpeg has no HTTPS.

## 2. Find the events — `sfxscan.py`

```
python3 sfxscan.py game.wav
```

`audioop.rms` over 10 ms blocks, at C speed, so sweeping twelve minutes costs
seconds. Prints every loud stretch with a duration and a rough pitch from zero
crossings. The gate is derived from the recording's own 55th percentile rather
than typed, because recordings differ by twenty decibels.

In a running game the footsteps outnumber the real effects about twenty to one.
Raise the gate, or filter by duration, to see past them.

## 3. Identify the notes — `sfxpitch.py`

```
python3 sfxpitch.py game.wav 8.15 0.04 0.04 10
```

Walks ten 40 ms windows from t=8.15 and prints the divisor of each, which is how
a sweep or a warble gets read off.

It runs **one Goertzel filter per candidate divisor**. That asks a better
question than an FFT peak-pick: not *"what frequency is this?"* — which you then
round and hope — but ***"of the divisors the chip can actually play, which one is
present?"*** The answer is the register value.

### The limit, which must travel with every number you take

Adjacent divisors sit about `freq / divisor` apart:

| divisor | freq | neighbours | window needed |
|--------:|-----:|-----------:|--------------:|
| 40 | 2,797 Hz | ~70 Hz | 15 ms — easy |
| 108 | 1,035 Hz | ~10 Hz | 100 ms — usually fine |
| 212 | 527 Hz | ~2.5 Hz | 420 ms — longer than most effects |

**A high note gives you a register value. A low note gives you a
neighbourhood.** The relative scores printed beside each result say which you
have: runners-up at 1.00 mean the window cannot separate them.

Two more honest caveats: a recording carries music and several channels at once,
so a reading is the *loudest* thing in its window rather than necessarily the
effect; and a percussive step reads as a garbage low divisor because it is noise,
not a tone.

## 4. Classify by shape — `sfxshape.py`

```
python3 sfxshape.py game.wav 2500 120
```

Reports each event as **rising, falling, warble, steady** or a blip.

**The shape is the design; the pitch is the detail.** A reward rises and a
penalty falls, and a player reads that before any particular note.

Mind the direction: **a smaller divisor is a higher note**, so a falling divisor
is a *rising* pitch. This repo has been caught by that more than once.

### What a recording cannot tell you

It says what the chip did, never *why*. A falling run recurring every fifteen
seconds fits a hit or a prize equally well, and no amount of analysis will
separate them.

So don't guess. **File the effect by its shape, build both it and its mirror as
candidates, and let someone decide by ear.** `games/colecosounds` does exactly
that with categories 3 (FALL) and 4 (RISE) — same notes, same holds, played
backwards.

## 5. Build a bench cart, not a patch to the game

Copy `games/colecosounds` (or `games/testsounds`). Tuning an effect by editing
the game, rebuilding, and playing to the screen where it fires is hopeless; on a
bench it is a keypress.

The pattern that works:

* **a digit picks a category, a letter plays a variant.** Picking what to listen
  to and listening to it are separate acts — merging them costs you a sound you
  did not ask for on every category change.
* **variant A is always the measured one**, so the reference is one key away and
  the comparison is never against memory.
* **cycling is the wrong control.** What you actually do is A/B a *pair* over and
  over; cycling makes you walk past everything in between and lose the
  comparison on the way. Keep FIRE as a cycle for ColecoVision, which has no
  keyboard.
* **effects are runs of four-byte steps** — frames, channel, value, volume — with
  a 0 frame count ending an effect. Scan the table at boot to find where each
  effect starts; a fixed-size slot means padding every short effect, and getting
  the count wrong makes every later effect play someone else's bytes, silently,
  because all the bytes are valid.
* store tone values as **divisor / 4**: a divisor runs to 1023 and a `DATA BYTE`
  stops at 255.

Two benches side by side, one per reference source, beats one bench with twice
the options — the comparison is then between *sources*, and the provenance of
each number survives.

## 6. Move a finding into the game

Expect the game and the bench to differ, and know why before you reconcile them:

* **A bench keeps a cadence; a game usually keeps a distance.** Keystone Kapers'
  footstep fires every N pixels travelled, so the feet keep time with the legs
  when the player is slowed. Matching "7.4 a second" means matching it *at
  walking speed* — and assumes the reference machine's character walks at yours,
  which the recording cannot confirm.
* **A per-pass timer cannot hit a per-frame length.** The game's shortest tick is
  one loop pass, about 42 ms, against a bench frame of 17.
* **Volume is a mix decision, not part of the measurement.** Footsteps run for a
  whole round and must sit under one-shot effects that carry information.

### Take the rhythms first

Rhythm is the one thing this method resolves **exactly**: it comes off the RMS
track by counting onsets, with no spectral estimate anywhere. Pitch, at the
bottom of the range, is a neighbourhood.

The footstep cadence is the case in point — 0.130 s between onsets across a
twelve-second run, 7.7 a second, against the 6 that the 2600 pass had guessed.

## Worked example

`games/colecosounds` is a complete one: `assets/sfxref-coleco.md` records the
recording, the method, every measurement and the limits; `src/COLSND.bas` turns
them into six categories of four candidates; and the footstep finding is now in
`games/KeystoneKapers/src/KEYSTONE.bas`, where the comment cites the measurement
rather than an opinion.
