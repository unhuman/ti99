# Keystone Kapers

Garry Kitchen's **Keystone Kapers** (Activision, Atari 2600, 1983), for the **TI-99/4A** and
**ColecoVision** from one CVBasic source.

Officer Keystone Kelly has fifty seconds to run Harry Hooligan down inside Southwick's
Emporium — a department store **eight screens wide and four levels tall** — before Harry
reaches the roof and disappears. Shopping carts, beach balls and cathedral radios cost nine
seconds each; toy biplanes cost a Kop.

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
| Ride an escalator (**up only**) | walk into its foot, or jump onto it |

**TI-99/4A: ALPHA LOCK.** It shares a line with the joystick's vertical axis, so latched down
it reports a direction that never releases. The title screen **measures the axis for 40 frames
at boot and ignores whichever direction is stuck**, so the game stays playable either way — it
just says `ALPHA LOCK DOWN - IGNORED` and carries on. (Classic99 defaults to `invertcaps=1`,
which means the TI sees ALPHA LOCK *down* when your Caps Lock is *up*.)

`838` on the title opens a setup screen for the number of Kops and the starting Krook.

## The store

**Three shopping floors and a roof.** Escalators stand at both ends but only **one per floor
connects upward**, and it alternates: floor 1 climbs at the **west** end, floor 2 at the
**east**, floor 3 at the **west**. Kelly starts at the east entrance, so reaching the roof on
foot is **three full traverses of the store** — one per floor. Escalators run **up only**:
walk into a flight's foot, or jump onto it, and the steps carry you at their own speed. The
**elevator in the centre** is the only way down — fast, and it serves all three shopping
floors but not the roof.

The **scanner** along the bottom shows all four levels at once, and it is colour-coded by
what a thing *is*: yellow floor lines, grey-and-black escalator slashes, a grey bar at the
elevator **car** (not its shaft), **Kelly black and Harry white**. Four pixel rows per level,
one colour each, floating in a black strip under the store.

**Kelly runs 4 px/frame, Harry 1.5.** That is not the comfortable margin it looks like: Harry
spawns beside floor 2's escalator and runs 4,104 px to the roof edge where Kelly runs 7,992,
so Kelly needs to be more than *twice* Harry's speed just to be ahead. He arrives 11.6 seconds
before Harry does — enough to absorb one nine-second obstacle and still make the catch on
foot, and no more. `DESIGN.md` §4a has the arithmetic; `assets/checkchase.py` enforces it at
build time.

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

Both scripts regenerate `src/art.bas` and `src/store.bas` first, then run the repo's
truncation, `GOSUB`/`RETURN` and screen-layout gates, plus `checkball.py` (no beach ball is
unavoidable), `checkchase.py` (the chase can be won on foot), `checkbands.py` (no actor's
colour bands overflow the 4-sprites-per-line limit), `checkesc.py` (every escalator phase
reassembles, and the animated character range matches the cells that move) and
`checkscan.py` (every radar row is coloured for what is drawn on it) and `checkchars.py`
(every hand-written character number still points at the character it names). The TI script
also checks the 24,336-byte fixed-area cap.

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
