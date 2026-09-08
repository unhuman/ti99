# Keystone Kapers

Garry Kitchen's **Keystone Kapers** (Activision, Atari 2600, 1983), for the **TI-99/4A** and
**ColecoVision** from one CVBasic source.

Officer Keystone Kelly has fifty seconds to run Harry Hooligan down inside Southwick's
Emporium — a department store **eight screens wide and four levels tall** — before Harry
reaches the roof and disappears. Shopping carts, beach balls and cathedral radios cost nine
seconds each; toy biplanes cost a Kop. The roof carries **carts but no biplanes** -- the last
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

**TI-99/4A: ALPHA LOCK.** It shares a line with the joystick's vertical axis, so latched down
it reports a direction that never releases. The title screen **measures the axis for 40 frames
at boot and ignores whichever direction is stuck**, so the game stays playable either way — it
just says `ALPHA LOCK DOWN - IGNORED` and carries on. (Classic99 defaults to `invertcaps=1`,
which means the TI sees ALPHA LOCK *down* when your Caps Lock is *up*.)

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

**Each floor has its own hazard** -- beach balls at the bottom, radios above them, biplanes
above those, shopping carts on the roof -- and it does not change as you walk. **Corner the
crook and he rides an escalator back DOWN**, which you cannot: they only go up.

**The hazards arrive one per round.** Krook 1 is short beach balls and nothing else; radios
join at 2, shopping carts at 3, **biplanes at 4**, the balls go tall at 5, a second hazard per
floor at 6, and carts and planes speed up at 7 and 8. That is the original's progression, and
`assets/checklevels.py` fails the build if any of it drifts.

The lift has a **step**: a two-pixel lip in the floor bar's own colours along the bottom of the doorway, with the doors opening above it, so boarding reads as stepping up into the car.

**Catch Harry and the clock is counted into your score**, a unit at a time with a tick under
each step -- 100 points a unit on Krooks 1-9, 200 on 10-15, 300 from 16.

**Money bags and suitcases are worth 50 each**, and a radio or a prize takes whatever fixture it stands in with it -- a pillar, a beam top or a whole counter -- rather than punching a hole through it. The building itself is the exception: the outside wall and the skyline are structure, not fixtures, and a radio standing beside one leaves it alone.

**A city stands behind the roof**, so the shopping carts up there can actually be seen --
a grey cart on a grey backdrop could not.

**Support beams run floor to floor.** They are part of the building, not scenery on top of
it -- see DESIGN.md 0k2 for why they have to be stamped in after the bands are drawn.

The **scanner** along the bottom shows all four levels at once, and it is colour-coded by
what a thing *is*: yellow floor lines, grey-and-black escalator slashes, a grey bar at the
elevator **car** (not its shaft), **Kelly black and Harry white**. Four pixel rows per level,
one colour each, inset in a grey band the width of the screen -- as the 2600 has it.

**The end of a round is one dark blue box** in the middle of the store: the reason you lost the Kop, with `GAME OVER` stacked above it when that was the last one. It no longer clears the screen, which used to make the end of the game look like the end of the program (`DESIGN.md` §0d-septies).

**Harry walks by real time**, not once per loop pass -- so a busy screen cannot starve him of steps and his escape lands in the same place wherever the player happens to be standing. It used to range from failing outright on the lift screen to escaping with eighteen seconds in hand on a light one (`DESIGN.md` §0f-ter).

**Harry starts at the lift** and runs at 2.25 px a pass -- the only quarter-pixel speed that lets him reach the roof inside the round (93.7 s of 100) while still losing the race to Kelly by 9.4 s. One notch slower and he can never escape; one faster and a single obstacle hit makes the round unwinnable (`DESIGN.md` §0f-bis).

**The run and the jump are measured, not invented** -- taken off an Atari 2600 recording via `games/testsounds`, the sound bench built for the purpose. The footstep is a burst of white noise six times a second (it was two alternating tones, fifteen times a second); the jump is a 415/188 Hz warble (it was a rising sweep). `DESIGN.md` §0e-ter.

**Getting hit clears that floor's hazards** until you re-enter the screen -- nine seconds is penalty enough without having to walk back out through them. Radios go too: they are characters on the shelf rather than sprites, so they are erased from the name table rather than just switched off.

**Level 1 is deliberately sparse**: two of the four floors carry a hazard, three from Krook 2, all four from Krook 3. Krook 5 is where the balls bounce higher and more of each bounce has to be ducked, and Krook 6 the first round with two hazards on a floor — spaced `HAZGAP` = 48 px, which is inside the window where **one jump clears both** (`DESIGN.md` §0p, §0p-bis).

The score line sits two columns in from the edge on **dark blue**, with the reserve-Kop hats one column in (five of them — six would wrap off the row). The lift takes **two seconds** between floors.

The roof is **grey buildings against a sunset** -- light blue at the top, then magenta, red, light red and yellow down to the skyline, with a black deck line and black beneath it. A vertical gradient is free on this VDP (it colours one 8x1 scan line at a time), but it costs **row variants**: a character cannot know which row it was placed in, so the sky and the partial buildings come in one per roof row (`DESIGN.md` §0d-quater).

The lift's door jambs sit in the **wall column either side** of the doorway, four pixels wide, so all four doorway characters are car and the opening is the full **32 px** rather than 24. They used to sit inside the doorway's own end columns, which spent a quarter of the opening framing it and needed six characters to do it (a header twin and a sill twin for each side); a jamb in the wall is one picture on every row in every door state, so it needs two. It is also **static** now — the old frame only existed while the doors were open, so it appeared as they parted (`DESIGN.md` §0d-ter).

The shop floor is TMS9918 **dark green (12)**, not medium green — the only darker green the hardware has. It lives in `genart.py` as one name, `STORE_BG`, because **56 of the 87 store characters carry it as their background** and a colour spelled out 56 times is a colour somebody will miss a cell of; the previewers and checkers derive their RGB from it rather than repeating the literal (`DESIGN.md` §0d-bis).

Both figures are **transcribed off the reference video onto the 2600's own pixel grid**
rather than drawn from impression (`DESIGN.md` §0h): Kelly's head is 42% of his height with a
flat black brim right across him, Harry's face is a third of his. `assets/cmpref.py` squashes
ours back down to theirs to compare, and `assets/previewrun.py` renders every frame, facing
and pose from the shipped bytes.

Harry runs in **side profile** -- legs scissored with the trailing foot kicked up behind, and **striped from his hat to his shoes** (a brimless three-row box cap, black-white-black; black shoes), with the arms drawn as those same bands extended sideways (which is how the arcade does it, and what makes them read as arms). Symmetric legs are a front view, and they were why he read as facing the player however his head was drawn.

His cycle is **four drawn poses, torso and legs together**, taken from an eight-frame run-cycle sheet (`assets/ref2600/runcycle-sheet.png`) by `assets/sheet2harry.py`, which writes `harryrun1..4.txt` with our own head over rows 0-8. Every band steps on the same two bits of `hanim`; the torso used to have only two poses on a clock of its own, which is what made him flap rather than run. Both facings are drawn out, **legs included** -- at this stride an unmirrored left run leads with the back foot. That is **63 of the VDP's 64 sprites**, so anything Harry gains from here has to displace something.

**Which four frames of the eight is measured, not assumed.** Every other frame (1, 3, 5, 8) looks right and plays as two poses, because frame n+4 of a run cycle is the same pose with the legs swapped and a silhouette cannot tell them apart; the order is `1 -> 4 -> 5 -> 3`, which alternates the leading leg and keeps the two near-duplicates opposite each other. The Kop has the same defect from the other direction -- his four beats come from two symmetric drawings and differ by 4 and 8 px, so he runs two frames -- and that one is **kept on purpose**: a redraw was rejected and yesterday's art restored, so Harry is the figure under improvement. `assets/checkanim.py` reads the beats out of the source, resolves them through genart's table and fails the build if any two are within 10 px, with the Kop carried as a **named exemption** whose 4 px is still printed every build rather than by lowering the threshold for everybody. See `DESIGN.md` §0j2 and §0j3.

**Kelly runs 4 px/frame, Harry 1.75** -- a ratio of 2.29 against the 2.07 measured off the
reference video (`DESIGN.md` §0f); 2.0 exactly would leave the chase 5.2 s of slack, less than
one obstacle hit. That is not the comfortable margin it looks like: Harry
spawns beside floor 2's escalator and runs 4,104 px to the roof edge where Kelly runs 7,992
on foot, so Kelly needs to be more than *twice* Harry's speed just to be ahead. Taking the
lift — which is on his way — he arrives 10.1 seconds before Harry does, enough to absorb one
nine-second obstacle and still make the catch. `DESIGN.md` §4a has the arithmetic;
`assets/checkchase.py` enforces it at build time.

## Status

🛠 **Builds on both targets; needs a runtime pass.** TI 23,706 / 24,336 bytes (**630 free**), 420 RAM;
ColecoVision 16 KB ROM, 420 / 814 RAM. The fixed area is now the binding
constraint — see `DESIGN.md` §12 before adding anything sizeable.

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
```

The TI build **banks the art**: `art.bas` and `store.bas` assemble into ROM bank 1, which
frees 4.5 KB of the 24,336-byte fixed area. `assets/banksize.py` measures what is left (a
banked image is padded, so `wc -c` reads a phantom overflow).

Both scripts regenerate `src/art.bas` and `src/store.bas` first, then run the repo's
truncation, `GOSUB`/`RETURN` and screen-layout gates, plus `checkball.py` (no beach ball is
unavoidable), `checkchase.py` (the chase can be won on foot), `checkbands.py` (no actor's
colour bands overflow the 4-sprites-per-line limit), `checkesc.py` (every escalator phase
reassembles, and the animated character range matches the cells that move) and
`checkscan.py` (every radar row is coloured for what is drawn on it), `checkchars.py` (every
hand-written character number still points at the character it names) and `checkride.py`
(a rider's feet are on a drawn step every frame of every ride). The TI script also checks the
24,336-byte fixed-area cap.

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
