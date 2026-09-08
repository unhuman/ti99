# What the Atari 2600's sound effects actually are

Measured, not guessed. Source: an Atari 2600 Keystone Kapers recording, at the
timestamps the reviewer named. The audio was pulled with `yt_dlp` (as a Python
module — the android client, format 18, because audio-only streams now want a PO
token), converted to mono 16 kHz with `ffmpeg`, and analysed in pure Python.
No numpy on this machine, so the analysis is an RMS envelope to find bursts and
Goertzel filters to measure them.

## The results

| effect | what it is |
|---|---|
| **running** | a 64 ms **noise** burst every **165 ms** — about 6 a second |
| **pickup** | **RISING** tones, 295 → 1028 → 2543 Hz, about 320 ms |
| **jump** | about **415 Hz warbling against 188 Hz**, about 280 ms |
| **hit** (ball or plane) | the same warble, tail **FALLING** to 235 Hz, about 660 ms |
| **time up** | a warble wandering **235–371 Hz**, about 430 ms |
| **tally** | ticks every **64 ms**, with a longer accent every few |

As SN76489 divisors (`f = 3579545 / (32 × divisor)`, so **smaller is higher**):

| Hz | divisor |
|---|---|
| 188 | 595 |
| 235 | 476 |
| 264 | 424 |
| 295 | 379 |
| 371 | 301 |
| 415 | 270 |
| 1028 | 109 |
| 2543 | 44 |

## Two things the first pass got wrong

**Autocorrelation called every effect noise, and it was measuring the wrong
thing.** The running sound plays *underneath* all of them, and its hiss drags the
confidence of a pitch estimate down below any sensible threshold — so a clean
tone with footsteps over it scores 0.4 and gets filed as noise. Only *running*
and the *tally* ticks are actually noise. A direct energy measurement at fixed
frequencies (Goertzel) does not have this problem: it says where the energy **is**,
and a sweep shows as the peak walking up the column. Use that to classify, and
autocorrelation only on a clip you already know is tonal.

**Which mattered, because it hid the most important distinction in the set.** The
pickup *rises* and the hit *falls*. That is the difference between a reward and a
penalty, and a player hears it long before they could name a pitch. Filed as
"both noise, both ~660 ms", they were the same sound.

## What does not transfer

The 2600's TIA is a different chip — a 5-bit divider and a 4-bit waveform
selector, with several voices being polynomial noise. The SN76489 in the TI and
the ColecoVision has three square channels and one noise channel. So the
**pitches and the timing transfer; the timbre does not.** Copying frequencies
alone would make ours worse, because our square-wave versions were chosen to
sound good as squares. The useful imports are the shapes: rising vs falling,
warble vs steady, and the durations above.

## The one number that contradicts the game

Keystone Kapers fires a footstep every 7 pixels of travel. At about 104 px/s
that is roughly **15 a second**, against the reference's **6**. Worth checking
against `testsounds` option 2, which plays the measured cadence.
