# Hard Hat Mack (ColecoVision and TI-99/4A, CVBasic)

An adaptation of Michael Abbot and Matthew Alexander's construction-site platformer.
Both targets build from `src/HARDHAT.bas` using the **unhuman/CVBasic** fork.
The July note retiring TI support is superseded: TI is a required target again.

Three construction sites are implemented:

1. **Beams and Bolts:** carry four girder pieces to the holes, then collect the
   roaming jackhammer and rivet the filled gaps.
2. **Lunch Break:** collect six red lunch pails, then jump into the moving electromagnet.
3. **Rivet Works:** carry six steel boxes to the IN machines.

Joystick 1: left/right walk, up/down climb, **Fire jumps** from a floor, chain,
crane beam, conveyor, or parked elevator. Direction at takeoff sets momentum;
a jump with no direction stays in place. A long Fire hold releases the jackhammer.
The title defaults to level 1. **Up/down selects the starting level; Fire starts.**
This lets you review later levels directly. Fire after game over returns to the title.
Three plays per game, shown as two spare hard hats at the right of the HUD.

## Playability repair (2026-10-01)

- Normal jumps now travel 32 pixels at walking speed, retaining the 11-pixel
  ceiling clearance. The longer apex makes enemies possible to jump over.
  Spring launches retain their original arc. Horizontal momentum continues
  after the jump arc ends, rather than stopping abruptly in mid-air.
- Fire can release Mack from a chain or parked elevator into a jump.
- Player, enemies, bolts, platforms and bonus countdown share one simulation
  clock, including catch-up steps. Fatal landings stop movement immediately.
- New games restart at level 1. Screen changes hide old sprites and stop
  effects; steel boxes are restored as steel boxes after death. Bolt spawning
  no longer wraps to the left when Mack stands near the right edge.
- Level-3 boxes cannot be consumed by stale level-1 gaps; extra-life HUD
  updates preserve the pickup loop index.
- TI art and level data occupy one permanently selected cartridge bank,
  restoring a valid **32 KB TI cartridge** without deleting content.
- Level 2's conveyors follow the drawn 2:1 slope, including roller ends. The
  lower conveyor returns to its reference position. All six pickups are two-cell
  lunch pails. The crane and its rider render from the same simulation step.
- Level 3's substitute ladder and fixed stubs are replaced by two circulating
  lift paddles. Riders travel with them through the corners; Fire jumps off.
  The shaft is scenery. IN machines and the processor door have larger artwork.
- Mack has a white hard hat and purple clothing in all movement poses. The
  elevator has a cage; columns, girders and loose pieces have clearer artwork.
- Jump/spring sweeps, pickup tones, a descending death effect and a short clear
  phrase replace flat beeps. Effects, death pauses and the hammer hold use elapsed
  video frames. Every effect has a note-off. A long hold is 45 video frames.

The supplied [Apple II video](https://www.youtube.com/watch?v=HwHZ-18Zgvg)
shows level 1 only. Later levels also use the still references in `assets/`.
This is an adaptation, not pixel-exact graphics or audio reproduction.

## Build and review

From the project root, on Windows:

```powershell
& tools/hardhat-dev.ps1 BuildAll
& tools/hardhat-dev.ps1 LaunchTI
& tools/hardhat-dev.ps1 LaunchColeco
```

Or run `bash games/HardHatMack/build-ti.sh` and then
`bash games/HardHatMack/build-coleco.sh` using Cygwin bash on Windows.
Outputs: `src/HARDHAT_8.bin` (Classic99/js99er) and `src/hardhat.rom` (ColecoVision).
Build sequentially. Both scripts run physics, truncation and return-stack checks.
The TI script also checks fixed-area size and exact data-bank preservation.

The physics checker executes the BASIC movement routines with deterministic
geometry, checks enemy-clearance windows, gaps, chain/elevator jumps, fall
momentum and fatal landings. It also parses all three real maps, checks every
pickup/delivery, conveyor surfaces, 480 lift/rider steps, twelve platform transfers,
both spring entries and sound envelopes. Nine deliberately broken variants must
fail. It does not emulate CPU performance or prove complete play-throughs.

**Verification:** both target builds pass; all three screens and title selection
were checked in Classic99 and CoolCV. TI checks include conveyor traversal and a
spring launch to the lower-left level-3 platform. Complete uninterrupted clears
and listening comparisons remain outstanding. The level-3 conveyor box is still
stationary; original music and escalating loop difficulty remain unimplemented.
See DESIGN.md section 15 for budgets and test limits. Classic99 uses arrows/Tab;
CoolCV uses arrows/Space for controller 1.
