# Hard Hat Mack (ColecoVision and TI-99/4A, CVBasic)

An adaptation of Michael Abbot and Matthew Alexander's construction-site platformer.
Both targets build from `src/HARDHAT.bas` using the **unhuman/CVBasic** fork.

Three construction sites are implemented:

1. **Beams and Bolts:** carry four girder pieces to the holes, then catch the roaming
   jackhammer and rivet them. Filled but unriveted holes reopen after a death;
   their pieces return. Jump to ring the bell and summon the elevator.
2. **Lunch Break:** collect six lunch pails across the platforms and ground,
   avoiding the pincers, pounder, concrete, furnace and vat. The magnet stays parked until all six pails are collected. Jump from the upper
   conveyor into the armed magnet; it carries Mack back to the crane top.
3. **Rivet Works:** start on the upper-right platform and collect six steel boxes.
   Carry each to a lip of either lower-floor opening; the box drops into the
   processor. Four paddles circulate counterclockwise (left down, right up).
   The two springs bounce Mack across the site and onto the opposite lower tier.
   The processors, central toilet and conveyor machinery are dangerous.

Joystick 1: left/right walk, up/down climb, **Fire jumps** from a floor, chain,
crane beam, conveyor, or parked elevator. Direction at takeoff sets momentum.
A long Fire hold releases the jackhammer. The title defaults to site 1;
**up/down selects a starting site, Fire starts**. Three starting lives appear as
two reserve hats. One extra life is awarded at 7,000 points.
Classic99 uses arrows/Tab; CoolCV uses arrows/Space for controller 1.

## Reference-driven repair (2026-10-01)

The [all-level Apple II longplay](https://www.youtube.com/watch?v=zanShXo4btw)
supersedes assumptions made from the earlier level-1-only clip and still images.
This pass corrects item placement, the independent drill route, fixed rivet
thrower, bell, death recovery, active machinery, magnet finish, enemy climbing,
factory start, four-paddle circulation and box delivery. The conveyor box remains
stationary, as it does in the reference; the belt carries Mack toward the grinder.
Stage numbers continue increasing when the three sites repeat.

The factory conveyor escape chain remains climbable after a head-only grab,
including while carrying a box. Walking off a ledge, chain or parked elevator
now drops straight down, even if
the direction remains held. Deliberate jumps keep their takeoff direction. A low
ceiling limits jump height without cutting its horizontal clearance time short.
The first boarding starts the crane. Concrete drops from the spigot and travels
with the lower belt, leaving a clear half-cycle for entry. Parked elevator cabins
also use background characters; these erase as soon as the cabin moves.

The preceding repair supplies shared frame pacing, 32-pixel jumps,
white hat/purple clothing, elevator cage, and PSG sound envelopes with note-offs.
This remains a hardware adaptation: the existing jump timing and sound effects are
not a measured transcription of the Apple II original. Later-loop enemy escalation
and original music remain unfinished.

## Build and review

From the project root on Windows:

```powershell
& tools/hardhat-dev.ps1 BuildAll
& tools/hardhat-dev.ps1 LaunchTI
& tools/hardhat-dev.ps1 LaunchColeco
```

Or run `bash games/HardHatMack/build-ti.sh` followed by
`bash games/HardHatMack/build-coleco.sh` using Cygwin bash.
Outputs: `src/HARDHAT_8.bin` (Classic99/js99er) and `src/hardhat.rom` (ColecoVision).
Build sequentially. Both scripts run physics, truncation and return-stack checks;
the TI build also verifies the fixed-area size and exact packed data bank.

The physics checker executes actual BASIC routines and all three level parsers.
It checks objective handling, death rollback, timed hazard windows, magnet capture
and delivery, drill/enemy routes, twelve platform transfers, 448 lift/rider steps,
both spring transfers, jump clearance, walk-off versus jump falls and sound
note-offs. It also tests the live spawn-to-conveyor-to-crane route at eight hazard
phases and factory lift entries from all six side tiers at fourteen phases each.
Eighteen deliberately broken variants must fail. Controlled-position tests do not
prove uninterrupted whole-level clears or original-hardware performance.

See DESIGN.md section 16 for the reference evidence, budgets and verification limits.
