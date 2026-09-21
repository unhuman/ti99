# Keystone Kapers

Garry Kitchen's **Keystone Kapers** (Activision, Atari 2600, 1983), for the **TI-99/4A** and
**ColecoVision** from one CVBasic source.

Officer Keystone Kelly has fifty seconds to run Harry Hooligan down inside Southwick's
Emporium — a department store **eight screens wide and four levels tall** — before Harry
reaches the roof and disappears. Shopping carts, beach balls and cathedral radios cost nine
seconds each; toy biplanes cost a Kop. A plane hit plays the jump's warble pitched down and held -- `TESTSOUNDS 5H` with its trailing beep cut, since the round ends on the spot and there is nothing for a tail to decay over. The roof carries **carts but no biplanes** -- the last
few strides can cost you time, never a Kop.

**Watch the beach balls.** They bounce, and their apex grows with the Krook — a low one has to
be jumped, and **a high one cannot be jumped at all: you have to duck under it.** No ball ever
bounces high enough to run under standing up, so every one of them costs you an action. It is
the only obstacle whose answer changes while it is in the air.

## Controls

| action | input |
|---|---|
| Run left / right | joystick left / right |
| Jump | fire |
| Long running jump | fire **+** a direction |
| Duck (under biplanes) | joystick **down** |
| Enter / leave the elevator | joystick **up** / **down** |
| Ride an escalator (**up only**) | walk into its foot, or land a jump on a step |

**TI-99/4A: ALPHA LOCK.** It shares a line with the joystick's vertical axis, so latched down it
can report a direction that never releases — which matters here, where down is the duck and up
is the lift. There **used to be a 40-frame calibration** that sampled the axis at boot and
ignored whichever direction looked stuck. It has been removed: it never once fired, eight other
games in this repo read the vertical axis with no such guard and have never shown the fault, and
it caused two input bugs of its own. If a stuck axis ever does turn up it is unmistakable — Kelly
ducks or rides the lift without being asked. (`DESIGN.md` §0e-sexies.)

`838` on the title opens a setup screen: **three typed digits** -- one for the number of Kops, two for the starting level -- and the last one starts the game. Out-of-range levels are clamped to 1-20 rather than refused, so there is nothing to get stuck in. It is deliberately **unadvertised** -- a hidden code in the Activision idiom, not a menu entry -- so nothing on the title screen mentions it (`DESIGN.md` §0d-octies).

## The store

**Three shopping floors and a roof.** Escalators stand at both ends but only **one per floor
connects upward**, and it alternates: floor 1 climbs at the **west** end, floor 2 at the
**east**, floor 3 at the **west**. Kelly starts at the east entrance, so reaching the roof on
foot is **three full traverses of the store** — one per floor. Escalators run **up only**:
walk into a flight's foot and you step up onto the bottom tread; jump at it and the arc
finishes, landing you on whichever of the bottom three steps it comes down over. Either way
your feet are **on a step**, and it carries you at its own speed. The
**elevator in the centre** is the only way down — fast, and it serves all three shopping
floors but not the roof.

**The clock is not seconds.** It counts **50 units** down to 0 and a unit is **two seconds**,
measured off the reference video (DESIGN.md 0m) -- so a round is about **100 seconds**. It used
to be one second a unit, which made the round unfinishable: Kelly needs ~72 s to reach the roof
and Harry ~96 s to escape, so at 50 s the clock beat both of them every time and Harry could
never get away at all.

**Under ten units the TIME field blinks** -- the word and the digits together, and there is no beep: the last ten seconds are the busiest part of a round, and a repeating tone arrives exactly when the player most needs to hear the hazards. The two halves are one field with one flag owning whether it is up, so they cannot get out of step (`DESIGN.md` 0e-quinquies).

**Each floor has its own hazard** -- beach balls at the bottom, radios above them, biplanes
above those, shopping carts on the roof -- and it does not change as you walk. **Corner the
crook and he rides an escalator back DOWN**, which you cannot: they only go up.

**The hazards arrive one per round.** Krook 1 is short beach balls and nothing else; radios
join at 2, shopping carts at 3, **biplanes at 4**, the balls go tall at 5, a second radio per
floor at 6, and carts and planes speed up at 7 and 8. Then the doubling continues: a THIRD radio
at 8, a second ball at 9 and a second cart at 11, after which the levels stop changing. **Biplanes never
double** -- they are the one hazard you must duck rather than jump.

That progression is the original's, and the doubling half of it is **measured** rather than
taken from a guide: `assets/ref2600/hazards.md` counts hazards frame by frame through a full
2600 playthrough. The published guide stops at level 8 saying the game stops changing there;
it does not. `assets/checklevels.py` fails the build if any of it drifts.

The lift has a **step**: a two-pixel lip in the floor bar's own colours along the bottom of the doorway, with the doors opening above it, so boarding reads as stepping up into the car.

**Catch Harry and the clock is counted into your score**, a unit at a time with a tick under
each step -- 100 points a unit on Krooks 1-9, 200 on 10-15, 300 from 16.

**Money bags and suitcases are worth 50 each**, and a radio or a prize takes whatever fixture it stands in with it -- a pillar, a beam top or a whole counter -- rather than punching a hole through it. The building itself is the exception: the outside wall and the skyline are structure, not fixtures, and a radio standing beside one leaves it alone.

**A city stands behind the roof**, so the shopping carts up there can actually be seen --
a grey cart on a grey backdrop could not.

**An escalator is solid all the way up.** The jump's apex is 14 px and a flight rises 4 px every 8 px along the floor, so an arc can clear the three treads it could land on and then meet the riser of the fourth -- which it cannot clear. It used to pass through and land on the floor beneath the staircase. Landing is now "at or below the flight, having been above it", which catches a riser hit on the way up as well as a tread hit on the way down, while leaving the walkable floor underneath alone. `assets/checkjump.py` sweeps 108,000 arcs and gates the build (`DESIGN.md` §0e-nonies).

**The elevator keeps its place between rounds.** It is part of the building, so it no longer snaps back to floor 1 whenever a round ends -- which also stopped its cycle being learnable from a fixed start (`DESIGN.md` §0e-octies).

**Harry stands still on an escalator** instead of running on the spot. The sprite pattern table was full -- 63 of its 64 slots -- so the standing pose has no slot of its own: it is copied over four he is not using while he rides, and the running art is put back when he steps off (`DESIGN.md` 0e-decies).

**The title screen is a marquee that chases.** A ring of lamps round the dark
blue field, three lit and one dark all the way round, and the dark one travels
while the screen waits for you. It costs no name-table writes at all: every cell
of the frame is one of four bulb characters by its position, and the chase
redefines which pattern is blank -- two `DEFINE CHAR`s per step instead of
ninety-two pokes. The name above it is drawn as whole KERNED words, three cells
tall, sliced on the character grid so a cell can hold parts of two letters
(`DESIGN.md` 0e-quaterdecies).

**Row 0 of the title card carries `SCORE:` and `HI:`** -- the last game and the best
so far, justified to the marquee: `SCORE:` starts at the frame's left column and the
HI digits end at its right one, so the line has the same edges as the card under it.
The whole card sits two rows lower than it used to (the marquee is rows 3-23)
to free that row; the ring is still 92 lamps, so the chase period still divides it. The
high score is settled by **one comparison at GAME OVER** and nowhere else: the score
only goes up, so the largest value it reaches is its value when the last Kop is gone,
and a test beside every award would run thousands of times to learn the same thing in
the budget that has no room for it. It lasts until the console is switched off -- neither
cartridge has storage to keep it longer.

The whole card -- frame, name and text -- is bank data drawn by one walker, so it
costs the code budget almost nothing. `assets/prevtitle.py` renders it offline
from the shipped bytes, because the emulator clips the right-hand columns at
every window size and a full-width frame is exactly what a screenshot cannot
check.

**The title screen and the message boxes are data, not code.** They live in a
ROM bank as display lists and are drawn by one shared routine, so changing what
the title says -- or adding to it -- costs bank bytes, of which there are
thousands, instead of code bytes, of which there were thirty. Edit
`assets/gentitle.py` and rebuild. That change plus the second bank took the
fixed area from **30 free bytes to 682** (`DESIGN.md` 0e-duodecies).

**The TI build is a 64 KB cartridge with two data banks.** Bank 1 holds
everything read while the game runs -- art, store templates, lookup tables --
and is selected once before the first frame and never switched, which is what
makes banking safe here. Bank 2 holds only the font, which two `DEFINE`s copy
into VRAM at setup and nothing reads again; it is selected for those two
statements and left. Get that wrong and the title comes up in garbage, which is
a deliberately loud failure. A bigger cart does **not** buy code space -- the
24,336-byte cap is the 32K expansion's RAM window, not cart ROM -- it buys room
to move data out of code (`DESIGN.md` 0e-undecies).

**Support beams run floor to floor.** They are part of the building, not scenery on top of
it -- see DESIGN.md 0k2 for why they have to be stamped in after the bands are drawn.

The **scanner** along the bottom shows all four levels at once, and it is colour-coded by
what a thing *is*: yellow floor lines, grey-and-black escalator slashes, a grey bar at the
elevator **car** (not its shaft), **Kelly black and Harry white**. Four pixel rows per level,
one colour each, inset in a grey band the width of the screen -- as the 2600 has it.

**The end of a round is one dark blue box** in the middle of the store: the reason you lost the Kop, with `GAME OVER` stacked above it when that was the last one. It no longer clears the screen, which used to make the end of the game look like the end of the program (`DESIGN.md` §0d-septies).

The boxes sit on rows 13-15, with `GAME OVER` above on 9-11. Their 16-column
width aligns with NES palette quadrants. Text is centred horizontally by
the generator, including `GOT HIM!` and `TIME'S UP!`.

Vertically the box is **three** rows, with equal blank margins. NES uses P1
for the top two rows and a navy tile in P3 for the bottom margin; it leaves
the fourth row's scenery intact instead of adding an extra blue row.

**A catch needs you level with him, not just on his floor.** A crook riding an
escalator keeps the floor he left until he arrives at the next one, so running
over the head of a flight used to arrest him through the floor while he was most
of a storey below (`DESIGN.md` 0e-quindecies).

**Harry walks by real time**, not once per loop pass -- so a busy screen cannot starve him of steps and his escape lands in the same place wherever the player happens to be standing. It used to range from failing outright on the lift screen to escaping with eighteen seconds in hand on a light one (`DESIGN.md` §0f-ter).

**Harry starts at the lift** and runs at 2.25 px a pass -- the only quarter-pixel speed that lets him reach the roof inside the round (93.7 s of 100) while still losing the race to Kelly by 9.4 s. One notch slower and he can never escape; one faster and a single obstacle hit makes the round unwinnable (`DESIGN.md` §0f-bis).

**The run and the jump are measured, not invented** -- taken off an Atari 2600 recording via `sound/testsounds`, the sound bench built for the purpose. The footstep is a burst of white noise six times a second (it was two alternating tones, fifteen times a second); the jump is a 415/188 Hz warble (it was a rising sweep). `DESIGN.md` §0e-ter.

**The bonus tally counts rather than ratchets** -- a 1,036 Hz blip per timer unit, two frames on and two off, and nothing after the last one. The measured 2600 tally is noise, and ten noise bursts in a row sound like a mechanism being wound; the pitch is also what keeps the count from sitting in the same register as the clock it is emptying. Two closing accents were tried and both rejected, an octave apart, which is what proved the objection was to the extra note rather than to its pitch (`DESIGN.md` §0e-ter).

**Getting hit stops the store** for exactly as long as the hit sounds -- Kelly, the hazards, the lift and the radios all hold still, which is how the nine-second penalty reads as an event rather than as a number quietly changing. **Harry and the clock keep going**, so the freeze is a cost and not a rest. `DESIGN.md` §0e-septies.

**Then that floor's hazards clear** until you re-enter the screen -- nine seconds is penalty enough without having to walk back out through them. The clear happens when the freeze ends, not when the hit lands, so the thing that hit you is still there while you are being told about it. Radios go too: they are characters on the shelf rather than sprites, so they are erased from the name table rather than just switched off.

**Level 1 is deliberately sparse -- a median of ZERO hazards on screen**, and four of its eight screens are completely bare on every floor. That is measured off the original, not chosen; the port used to show two at all times because a hazard that had not arrived yet was turned into a BEACH BALL rather than removed. Which screens carry what, on every round, is a generated data table now rather than a ladder of gates -- see DESIGN.md 0p-octies, and run assets/genstore.py --levels to read the whole ramp as a grid. Krook 5 is where the balls bounce higher -- the apex goes 9 px -> 16 px, and 20 px from Krook 10 -- and a TALL ball is seeded to meet you at the top of its bounce rather than the bottom, so it has to be ducked rather than jumped, and Krook 6 the first round with two hazards on a floor — spaced `HAZGAP` = 104 px, which is inside the window where you can **land between them** and take each with its own jump. 104 is measured off the original, whose moving hazards are never closer than 108 px in our scale (`DESIGN.md` §0p, §0p-bis, §0p-quater).

The score line sits two columns in from the edge on **dark blue**, with the reserve-Kop hats one column in (five of them — six would wrap off the row) and **right-justified**, so the last one always sits in the last column and the row grows leftward. The lift takes **two seconds** between floors.

The roof is **grey buildings against a sunset** -- light blue at the top, then magenta, red, light red and yellow down to the skyline, with a black deck line and black beneath it. A vertical gradient is free on this VDP (it colours one 8x1 scan line at a time), but it costs **row variants**: a character cannot know which row it was placed in, so the sky and the partial buildings come in one per roof row (`DESIGN.md` §0d-quater).

On NES, the artwork uses navy shelf frames, gold trim,
coloured book spines and drawer handles, distinct from grey pillars. Edit the
8x16 shelf module in `assets/nes-shelf.txt`. The skyline blends blue into pink
and orange into gold with ordered dithering; buildings stay grey with gold
windows. Reserve hats remain black using the sprite palette, right-aligned with a
two-character margin at the screen edge. Gameplay clears
the title's SCORE/HI row and keeps the live score on the top HUD line.
NES suitcases have brown sprite outlines over their existing black-filled
background tiles, matching the TI colour scheme without recolouring fixtures.
NES sound uses pulse 1 for jumping and pulse 2 for prizes and the bonus tally,
with triangle extra-life notes and noise footsteps. NES bonus ticks use a
lower 415 Hz pitch with the original two-frame on/off rhythm. Hits take priority over
prizes on pulse 2; jumping and prizes can play together.
Footsteps now trigger the noise length counter correctly and stop before screen
redraws, avoiding a sustained hiss while sound updates are paused. Jump audio
is muted during the redraw and resumes its remaining warble afterward. Triangle
note-off preserves its reload control; countdown, pickup and extra-life notes
set volume before pitch. No extra RAM is required.
In iNES, enable
Audio > Play Sound When Inactive if you want sound while another window has focus.
Crowded NES scanlines can drop the brown overlay; the background case remains
visible underneath. Money bags retain their gold background artwork.
The elevator has shaded door panels, a centre seam, gold jamb highlights,
a threshold and a rear cabin rail; edit `assets/nes-elevator.txt`.
The strip above the radar is navy, with black sections beneath fixtures and
escalators to preserve their black details. TI and Coleco artwork is unchanged.
See `DESIGN.md` sections 15-20 for the palette allocation and NES artwork.


The lift's door jambs sit in the **wall column either side** of the doorway, four pixels wide, so all four doorway characters are car and the opening is the full **32 px** rather than 24. They used to sit inside the doorway's own end columns, which spent a quarter of the opening framing it and needed six characters to do it (a header twin and a sill twin for each side); a jamb in the wall is one picture on every row in every door state, so it needs two. It is also **static** now — the old frame only existed while the doors were open, so it appeared as they parted (`DESIGN.md` §0d-ter).

The shop floor is TMS9918 **dark green (12)**, not medium green — the only darker green the hardware has. It lives in `genart.py` as one name, `STORE_BG`, because **56 of the 87 store characters carry it as their background** and a colour spelled out 56 times is a colour somebody will miss a cell of; the previewers and checkers derive their RGB from it rather than repeating the literal (`DESIGN.md` §0d-bis).

Both figures are **transcribed off the reference video onto the 2600's own pixel grid**
rather than drawn from impression (`DESIGN.md` §0h): Kelly's head is 42% of his height with a
flat black brim right across him, Harry's face is a third of his. `assets/cmpref.py` squashes
ours back down to theirs to compare, and `assets/previewrun.py` renders every frame, facing
and pose from the shipped bytes.

Harry runs in **side profile** -- legs scissored with the trailing foot kicked up behind, and **striped from his hat to his shoes** (a brimless three-row box cap, black-white-black; black shoes), with the arms drawn as those same bands extended sideways (which is how the arcade does it, and what makes them read as arms). Symmetric legs are a front view, and they were why he read as facing the player however his head was drawn.

His cycle is **four drawn poses, torso and legs together**, taken from an eight-frame run-cycle sheet (`assets/ref2600/runcycle-sheet.png`) by `assets/sheet2harry.py`, which writes `harryrun1..4.txt` with our own head over rows 0-8. Every band steps on the same two bits of `hanim`; the torso used to have only two poses on a clock of its own, which is what made him flap rather than run. Both facings are drawn out, **legs included** -- at this stride an unmirrored left run leads with the back foot. That is **63 of the VDP's 64 sprites**, so anything Harry gains from here has to displace something.

**Which four frames of the eight is measured, not assumed.** Every other frame (1, 3, 5, 8) looks right and plays as two poses, because frame n+4 of a run cycle is the same pose with the legs swapped and a silhouette cannot tell them apart; the order is `1 -> 4 -> 5 -> 3`, which alternates the leading leg and keeps the two near-duplicates opposite each other. `assets/checkanim.py` reads the beats out of the source, resolves them through genart's table and fails the build if any two are within 10 px. See `DESIGN.md` §0j2 and §0j3.

**The Kop runs two drawn frames, and stands on frame 1.** He used to run four -- A, B, and the two of them with the legs *mirrored* -- which was two pictures each shown twice while his legs were near-symmetric, and became something worse once `assets/kelly-run{1,2}.txt` were redrawn with real strides: a mirrored stride reads as the figure **turning round**. The mirrored beats are gone. A separate standing pose was drawn and came back byte-identical to run frame 1, so the source names `P_KRUN1` for standing rather than loading the same sixteen rows twice; their slots stay in the table as blanks, which keeps `P_KFACING` at 36 and leaves **patterns 16-23 and 52-59 free**. He stands when no direction is held and while riding an escalator or the lift (both need their own test -- they `RETURN` out of `move_kelly` before `kmv` is cleared). Measured: 77 px between his two beats. `DESIGN.md` §0j4.

**All of Kelly's art is editable text.** `assets/kelly-run1.txt`, `kelly-run2.txt` and `kelly-duck.txt` are the drawings -- `genart.py` reads them, so editing one and rebuilding is the whole workflow. Run `python3 assets/dumpkelly.py` to regenerate them from the art (it also refreshes the per-row reference comments), and `--check` to verify the round trip. The crouch needs **three** grids rather than one because its three sprites sit at the same `y` and overlap: 14 body pixels live underneath the helmet and face, and a flat composite would discard them. `assets/ducktest.py` runs on every build and injects four defects the reader must refuse -- a row one character short (which steals a row from the next grid), a row mixing two inks, a missing grid, and the helmet drawn over the face.

**The baton comes up on one beat in four.** It lives in the FACE band of `kelly-run2.txt`, and riding it on the run-2 body put it up half the time -- a man waving rather than a man running with a stick. The body still alternates on `kanim AND 8`; the raised head needs `AND 16` as well, so the arm has three beats to come back down. The jump gets it unconditionally, because a standing jump holds no direction and so never advances `kanim`. Both tests are on the **pose**, not on the counter a second time: `kanim` freezes when he stops, which is what used to leave him standing still with the baton in the air.

**Two silent traps that change how the art is edited.** An art row that loses one character is no longer 16 wide, so the reader skipped it and every row below shifted up -- reported as *"the buttons on the shirt are all messed up"* and *"one of the arms sort of disappears"*, with nothing naming a line; `genart.py` now refuses any line of `.#-0` that is not exactly 16 wide. And `checkanim.py` had silently stopped measuring Kelly when his ladder became an assignment -- teaching it that form, and making its window count code rather than source lines, turned up **two more bands it had never seen** (Harry's legs and the biplane). It measures four where it measured two, and `checkanim_test.py` asserts them by name.

**Kelly runs 4 px/frame, Harry 1.75** -- a ratio of 2.29 against the 2.07 measured off the
reference video (`DESIGN.md` §0f); 2.0 exactly would leave the chase 5.2 s of slack, less than
one obstacle hit. That is not the comfortable margin it looks like: Harry
spawns beside floor 2's escalator and runs 4,104 px to the roof edge where Kelly runs 7,992
on foot, so Kelly needs to be more than *twice* Harry's speed just to be ahead. Taking the
lift — which is on his way — he arrives 10.1 seconds before Harry does, enough to absorb one
nine-second obstacle and still make the catch. `DESIGN.md` §4a has the arithmetic;
`assets/checkchase.py` enforces it at build time.

## Status

**Builds pass on TI-99/4A, ColecoVision and NES (2026-09-20).** TI fixed code
uses **21,888 / 24,336 bytes (2,448 free)**, with 620 bytes of RAM and a 64 KB
cartridge. Runtime data bank 1 has 506 bytes free; setup bank 2 has 5,764 free.
ColecoVision uses a 24 KB ROM and 595 / 814 RAM; NES uses a 32 KB PRG image
plus its 16-byte header and reports 1,506 RAM bytes. See `DESIGN.md` section 14
for measurements, validation and the remaining runtime checks.

Kelly and Harry are **colour-banded sprites** — Kelly three, Harry four — with one colour per
pixel row, and each band drawn at its own `y` so its sprite box covers only the rows it uses.
`DESIGN.md` §3b has the arithmetic; the short version is that the VDP counts sprite *boxes*
per scanline rather than pixels, so where a band's box *starts* matters as much as what is in
it. Getting that right is what lets both figures stay whole when they meet. All the build gates pass, including the new
`checkchase.py`. `DESIGN.md` §0 carries the
sourced research and §13 the phase plan.

## Build

```sh
./build-ti.sh        # cvbasic --ti994a -> xas99 -> linkticart -> src/KEYSTONE_8.bin
./build-coleco.sh    # cvbasic          -> gasm80            -> src/keystone.rom
./build-nes.sh       # cvbasic --nes    -> gasm80            -> src/keystone.nes
```

The TI build **banks the art**: `art.bas` and `store.bas` assemble into ROM bank 1, which
frees 4.5 KB of the 24,336-byte fixed area. `assets/banksize.py` measures what is left (a
banked image is padded, so `wc -c` reads a phantom overflow).

`build-ti.sh` also shortens eligible TMS9900 conditional branches after the first
assembly. A second assembly verifies every rewritten opcode and destination before
linking. Use `TI_SHORT_BRANCHES=0 ./build-ti.sh` for an unoptimized comparison;
this leaves 660 fixed-area bytes free. The default is enabled. Ignored
`src/KEYSTONE.unopt.a99`, `.unopt.txt` and `.branches.json` retain the originals
and rewrite manifest. `assets/romprofile.py` reports measured routine sizes,
including the final routine, excluding bank padding and switched-bank data.

All three scripts regenerate art, store and title assets (including the setup-bank
`src/scancol.bas` and NES-only `src/nescolor.bas`) first, then run the repo's
truncation, `GOSUB`/`RETURN` and screen-layout gates, plus `checkball.py` (no beach ball is
unavoidable), `checkchase.py` (the chase can be won on foot), `checkbands.py` (no actor's
colour bands overflow the 4-sprites-per-line limit), `checkesc.py` (every escalator phase
reassembles, and the animated character range matches the cells that move) and
`checkscan.py` (every radar row is coloured for what is drawn on it), `checkchars.py` (every
hand-written character number still points at the character it names) and `checkride.py`
(a rider's feet are on a drawn step every frame of every ride). The TI script also checks the
24,336-byte fixed-area cap; the NES script adds `checknesram.py` (no array runs off the end of
the 2 KB and into zero page), `checknesstart.py` (production starting conditions) and `checkvblank.py` (no vblank is asked to copy more than it can
finish before the scroll restore, which is what made the escalator screens flash).

> `cvbasic.exe` is a **Cygwin** binary and Git Bash's own MSYS2 runtime shadows it, so it
> used to die with `cannot open shared object file` — exit 127, no other clue — while the
> same command worked from PowerShell. Both build scripts now put `C:\cygwin64\bin` at the
> front of `PATH` and pass tool paths in the `/cygdrive` form with MSYS2's argument rewriting
> off, so bash works. No PowerShell fallback needed.

## Design notes worth knowing

- **The view flips, it does not scroll.** Eight discrete screens, one blit per crossing, so
  the per-frame budget never pays for the store. The trade is that Harry can be a pixel
  off-screen and invisible — which is why the scanner is a Phase 6 requirement and not polish.
- **A screen is exactly 256 pixels**, so an actor's x within its screen is one unsigned byte.
  No 16-bit world coordinates anywhere.
- **Zero per-frame VDP reads.** An actor's floor is an index into a four-entry height table,
  not a question asked of the screen.
- **The look is measured from gameplay video, not from screenshots.** `assets/grabref.ps1`
  pulls reference frames; `DESIGN.md` §0b records what they showed. Stills had got three
  things wrong, including the floors — they are thick olive bars, not the hairlines an
  earlier note built its whole look rule on.
