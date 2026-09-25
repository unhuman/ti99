# tunes

A **music** bench for Keystone Kapers, beside the two sound-effect benches
(`sound/testsounds`, `sound/colecosounds`). Press a digit to hear a candidate song.
Each candidate is a variation to judge before any music goes into the game.

## Controls

| key | does |
|---|---|
| **1**–**9**, **A**–**C** | play that slot on the current page (a `>` marks the playing tune) |
| **N** / **P**, or joystick **right** / **left** | next / previous page |
| **0** | stop |
| **FIRE** | play the next tune, across pages; the page turns to follow it |

Twelve tunes a page, three pages. The keys mean the same slot on every page.
On the ColecoVision (keypad 0–9 only), FIRE and the joystick reach every tune.

## The tunes

Page 1. Every tune on every page is an **original** composition; none copies a published song or arrangement.

| key | tune | style | what it is for |
|---|---|---|---|
| 1 | RITZ | walk + drums | a 1929 Broadway strut: minor key, bass walking down by half steps, 3+3+2 hook |
| 2 | CHASE | gallop + snare | the silent-film "hurry": running E-minor eighths over a pumping bass |
| 3 | VILLAIN | tremolo | the misterioso: a creeping line over a held bass and a shaking left hand, diminished sevenths, then a staccato tiptoe |
| 4 | WALTZ | waltz (3/4) | the love scene: a long F-major tune, bass on 1, chord on 2 and 3 |
| 5 | RAG | stride | the comedy: C-major ragtime oom-pah with a tied, off-beat right hand |
| 6 | SORROW | lament | the sad scene: slow A minor, held chords, sighing melody notes |
| 7 | MARCH | stride + snare | the Kops set off: B-flat major, bugle-call opening |
| 8 | TIPTOE | pizz | sneaking: C minor, every note short, two careful steps then a pause |
| 9 | AGITATO | tremolo, fast | panic: G-minor scale runs that turn back on themselves, then leaping arpeggios |
| A | TWOSTEP | stride + snare | a jaunty G-major dance for a happy moment |
| B | DIRGE | lament, **plays once** | a life lost: eight slow bars of C minor sinking to the tonic |
| C | FANFARE | held chords + roll, **plays once** | the crook is caught: bugle pickup, a climb through D major, held top note |

These are the stock moods a 1910s-20s cinema pianist switched between as the
picture changed. Scene cues loop. DIRGE and FANFARE are **event** cues
(`loop: False`, ending in `MUSIC STOP`), which is the shape a game needs for a
capture or a lost life. Solo piano unless marked with drums.

### Pages 2 and 3

| page | key | tune | style | what it is for |
|---|---|---|---|---|
| 2 | 1 | CAKEWALK | stride + snare | a strutting dance contest, F major |
| 2 | 2 | STORM | tremolo, fast | wind and rain: E-minor arpeggios |
| 2 | 3 | MIDNIGHT | lament | an empty house at night, slow B minor |
| 2 | 4 | SLAPSTICK | gallop + snare | a pie fight: fast comic galop in C |
| 2 | 5 | TANGO | tango | the vamp: D minor, habanera bass in 3+3+2 |
| 2 | 6 | HOEDOWN | gallop + snare | a barn dance: G-major fiddle figures |
| 2 | 7 | LULLABY | waltz | a cradle song, slow C major |
| 2 | 8 | SEASIDE | waltz | a rowboat: A-major barcarolle rocking in 6/8 |
| 2 | 9 | HEIST | pizz | safe-crackers at work, A minor |
| 2 | A | BIG TOP | stride + snare | a circus parade, E-flat major |
| 2 | B | RUNAWAY | gallop + snare | no brakes: relentless A minor |
| 2 | C | PARLOR | waltz | high society: a genteel G-major waltz |
| 3 | 1 | BLUES | walk + brushes | a twelve-bar blues in B-flat |
| 3 | 2 | SHADOWS | tremolo | something moves in the dark, F minor |
| 3 | 3 | VICTORY | stride + snare | the hero wins, broad C major |
| 3 | 4 | HEARTACHE | lament | bad news, E minor |
| 3 | 5 | STREET | walk + snare | rush hour: bustling F major |
| 3 | 6 | DAYBREAK | lament | a quiet morning, G major |
| 3 | 7 | EXTRA | **plays once** | bonus life: a quick C-major arpeggio |
| 3 | 8 | READY | **plays once** | round start: bugle pickup ending on the dominant |
| 3 | 9 | TIME UP | **plays once** | too late: a chromatic sag into C minor |

All 33 are original compositions. EXTRA, READY and TIME UP join DIRGE and FANFARE
as event cues sized for the game: 3 to 4 bars, 100 to 132 bytes each.


## Adding a tune

Songs are written in `assets/gentunes.py`, not in BASIC. Each bar is a chord and
one melody token per eighth note (8 a bar, or 6 with `meter: 6` for a waltz):

```python
('Gm', 'D5 S  S  Bb4 S  S  G4  S'),
```

* A token is a note (`D5`, `Bb4`, `F#5`), `S` to sustain, or `-` to rest. Flats
  are allowed and are converted to CVBasic's sharps.
* The generator writes the other voices from the chord symbol, in the tune's `style`:
  `walk`, `stride`, `gallop`, `tremolo`, `lament`, `pizz` or `waltz` (see `patterns()`). `walk`
  is a walking **bass**
  (root, third, fifth, then a half step into the next root), off-beat **comping**
  on the "and" of 1 and 3, and **drums** (strong on 1 and 3, tap on 2 and 4, a
  roll on the bars listed in `rolls`). Set `drums: False` for solo piano, and
  `loop: False` for a cue that plays once.
* Supported chord qualities: major, `m`, `7`, `m7`, `m7b5`, `dim`, `6`.
* `ticks` is the length of an eighth note in player ticks. RITZ uses 9, about 150 bpm.

To add one, add it to a list in `gentunes.py` with `tune(label, menu, ticks,
style, bars, ...)`. The `menu` text can be at most 21 characters. That is the only
edit. The generator also writes the tune count, the `PLAY` dispatch and the menu
pages into `songs.bas`, so the player picks up the new tune and its page without
changes. `PLAY` needs a constant label, which is why the dispatch is generated as
one line per tune rather than written by hand.

### Two hazards

* **Bass floor.** The `Z` bass instrument sounds two octaves below the written
  note, and the SN76489 cannot go below about 109 Hz (A2). The generator keeps
  bass roots in the written range A4 to G#5, and any lower note would be silent.
* **The file name is `songs.bas`, not `tunes.bas`.** Windows file names ignore
  case, so a generated `tunes.bas` is the same file as `TUNES.bas`. The first build
  overwrote the player with it.

## Build

```
./build-ti.sh        # -> src/TUNES_8.bin   (Classic99, js99er)
./build-coleco.sh    # -> src/tunes.rom     (CoolCV, blueMSX)
```

Run them with Cygwin's bash (`C:\cygwin64\bin\bash.exe`). Under Git Bash, the
Coleco script's truncation gates fail because of path rewriting, the same way
`colecosounds` does. TI: 23,705 of 24,336 bytes. ColecoVision: 24 KB.

## Room for more

**The fixed area is full**: 23,705 of 24,336 bytes, 631 free. 15,396 bytes of that
is music. A 16-bar tune is **516 bytes**, a waltz or twelve-bar blues 388, and an
event cue 100 to 260. Each tune also costs about 45 bytes of menu line and
dispatch code.

More tunes need a **data bank**. Put `BANK ROM 128` near the top, `BANK SELECT 1`
at startup, and `BANK 1` above `INCLUDE "songs.bas"`, following the pattern in
Keystone Kapers' `CLAUDE.md` notes. The generated code would then have to move
out of `songs.bas` into a separate include above the bank. Each 8 KB bank holds
about 15 more tunes. With one bank selected once at startup, the music player can
read it every frame safely.
