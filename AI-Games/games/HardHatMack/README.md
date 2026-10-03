# Hard Hat Mack (ColecoVision and TI-99/4A, CVBasic)

An adaptation of Michael Abbot and Matthew Alexander's construction-site platformer.
Both targets build from `src/HARDHAT.bas` using the **unhuman/CVBasic** fork.

Three construction sites are implemented:

1. **Beams and Bolts:** carry four girder pieces to the holes, then catch the roaming
   jackhammer and rivet them. Filled but unriveted holes reopen after a death;
   their pieces return. Jump to ring the bell and summon the elevator. At either end of an occupied
   ride, Mack does two quick crouch-and-rise motions with a two-tone sound
   (about half a second), then you can walk or jump off. The right-hand trampoline
   compresses under Mack, then rebounds and launches him; its base stays planted
   and his feet follow the moving cap. Mack starts one character to the right
   of the vertical support so his hat and torso remain clear against black.
2. **Lunch Break:** collect six lunch pails across the platforms and ground,
   avoiding the pincers, pounder, concrete, furnace and vat. The magnet stays parked until all six pails are collected. Jump from the upper
   conveyor into the armed magnet; it carries Mack back to the crane top. The upper
   conveyor is one character farther right; walking or riding past its right end
   is fatal, so jump before the last roller.
3. **Rivet Works:** start on the upper-right platform and collect six steel boxes.
   Carry each to a lip of either lower-floor opening; the box drops into the
   processor. Four paddles circulate counterclockwise (left down, right up).
   The two springs bounce Mack across the site and onto the opposite lower tier.
   Both are two characters wide, one row above the ground, and use level one's
   artwork, compression, rebound and launch sound. Only the pad
   under Mack compresses, with his feet following it before each launch.
   The processors, central toilet and conveyor machinery are dangerous.

Joystick 1: left/right walk, up/down climb, **Fire jumps** from a floor, chain,
crane beam, conveyor, or parked elevator. Direction at takeoff sets momentum.
**Hold Fire for 0.75 seconds to release the jackhammer** (Tab in Classic99,
Space in CoolCV). It returns to its starting position and cannot be re-caught until it and Mack
separate. A new pickup resets the hold timer, even if Fire was already held. Fire starts a normal game at site 1 with three lives.
Type **838** on the title, then a digit **1-9 for total lives**, then **1-3 for
the starting level**; the last digit starts the game. Release each key between
digits. These choices apply to one game only. Reserve hats exclude the current
life and are right-justified below the score line. One extra life is awarded at 7,000 points.
Classic99 uses arrows/Tab; CoolCV uses arrows/Space for controller 1.
The construction-themed title shows **LAST SCORE** and **HIGH SCORE** at the top,
with matching full-height dithered white-to-yellow lettering (MACK restored to
its original 115-pixel width), Mack on a riveted girder, and the credit
**2026 UNHUMAN and C&C AI** above the controls, with **PRESS FIRE TO START**
at the bottom. LAST SCORE starts directly under its label without space padding;
its 838 asterisk follows the last digit. High score remains right-aligned. Scores persist between games until reset. An asterisk beside a
score identifies an 838 game; the high-score marker stays with the game that
set that record. Normal play clears the current-game marker, and a higher
normal score replaces an 838 record without an asterisk. Equal scores retain
the existing record and its marker. The gameplay HUD shows the current score flush left without a prefix (with
its 838 marker), **BONUS** and the timer centered, and **LEVEL** plus the stage
number right-aligned. Two- and three-digit levels expand leftward. High score
appears only on the title. Scores omit leading zeroes and
reach 327,675 points using five-point storage units; further awards saturate
at that maximum. All point awards and the 7,000-point extra life are unchanged.
It replaces the old title/instruction screen; Fire starts play directly.
After GAME OVER, wait 1.25 seconds (75 frames at 60 Hz), then release and press
Fire/Tab to return to the title. The message has a one-character blank border.

## Reference-driven repair (2026-10-01)

The [all-level Apple II longplay](https://www.youtube.com/watch?v=zanShXo4btw)
supersedes assumptions made from the earlier level-1-only clip and still images.
This pass corrects item placement, the independent drill route, fixed rivet
thrower, bell, death recovery, active machinery, magnet finish, enemy climbing,
factory start, four-paddle circulation and box delivery. The conveyor box remains
stationary, as it does in the reference; the belt carries Mack toward the grinder.
Stage numbers continue increasing when the three sites repeat.

The factory conveyor escape chain remains climbable after a head-only grab,
including while carrying a box. The added right-end shortcut chain is removed: jump
from the rotating lift onto the belt, collect the box, and escape up the original
left chain before reaching the grinder. Walking off a ledge, chain or parked elevator
now drops straight down, even if
the direction remains held. Deliberate jumps keep their takeoff direction. A low
ceiling limits jump height without cutting its horizontal clearance time short.
The first boarding starts the crane. Concrete drops from the spigot and travels
with the lower belt and arcs from its last roller into the vat. It now stays above
the belt. Releases are 317 world steps apart (about 4.7 seconds), leaving a
longer quiet interval and shifting their timing relative to the crane. Paired
pincers meet when closed and leave a 32-pixel opening when fully apart. Their
continuous one-pixel motion reverses immediately at each end, with a complete
cycle of about 1.42 seconds (96 world steps). Their full faces touch when closed. A 16-pixel clear
patch to their right lets Mack wait safely after leaving the crane, then jump
when the jaws touch, into the opening middle, and jump again for the pail.
Both directions allow a brief release/repress between the two jumps. A rising crane catches Mack during
the apex of a jump as well as during descent. The smashers on levels
2 and 3 use animated characters: each has a 14-pixel-wide head across two character
columns, a piston attached to the upper beam, and collision limited to its exposed
moving head. White, magenta and red bands follow each head through character
boundaries. Both wait visibly at the top; each reaches its supporting surface
and retracts smoothly;
level 2 moves at one pixel per world step, level 3 at one pixel per two steps.
Both inclined conveyors and the factory belt have continuous rails,
rotating rollers and treads that follow the transport direction and clock.
Level 2 girders have centered rivets, including all pixel positions of the crane.
The ground flame is left of the chain, leaving its base clear. Hold Up and release
Fire to catch a chain during a jump or fall. The magenta spray can beside the
right-hand ground machine is a 200-point bonus, clear of its support.

Loose blocks have a broad brick face and bright top edge. Walking, the held
jackhammer, bouncing rivets, closing pincers and pounder strikes now have short
sound cues alongside jump, pickup, scoring and death effects. Alternating boot
taps and chain clinks accompany movement; machinery has a metallic impact and
ring. Reward chimes have their own channel so they cannot erase a jump sweep.
Death takes priority. Each level has its own related C-major fanfare (about
2.0-2.3 seconds), with harmony, bass and percussion; all channels explicitly stop afterward. Parked
elevator cabins **and floors** use background characters that erase when movement
starts; game over preserves the entire elevator, including a moving cabin frozen
between stops. Rivet and pounder hitboxes align with their visible heads. Rivets
bounce at the visible floor, and delivered factory boxes descend visibly for about
0.6 seconds.

The preceding repair supplies shared frame pacing, 32-pixel jumps,
white hat/purple clothing, elevator cage, and PSG sound envelopes with note-offs.
This remains a hardware adaptation: the existing jump timing and sound effects are
not a measured transcription of the Apple II original. From stage 4 onward, every site has two independently chosen enemies
(vandal or OSHA inspector, including matching pairs). Both roam and climb, and
their selection persists through deaths. Ordinary jumps cannot clear their
12-pixel bodies; use the platforms and ladders to avoid them. The completion
music is newly composed for this port; original-music matching remains open.

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
Build sequentially. Both scripts run generated-art, physics, truncation and return-stack checks;
the TI build also verifies the fixed-area size and all three packed banks. Its 64 KB
cartridge contains the loader, setup/assets bank and separate banks for
machinery/animation/audio and the title/setup screen; their wrappers restore
the setup/assets bank before returning. Coleco remains
an unbanked cartridge within 32 KB. The TI build uses
the repository's checked short-branch optimizer and verifies the resulting opcodes
and destinations after reassembly. `TI_SHORT_BRANCHES=0` retains the comparison
path with the same size gate. Starting play restores the gameplay characters
after the title artwork uses that character range.

Editable title lettering and scenery live in `assets/gentitle.py`; `--write`
regenerates the title patterns, colors and screen map. Builds reject stale art.
Editable conveyor, pincer, smasher, moving-girder and trampoline art lives in `assets/genconveyors.py`. Run it with
`--write` after editing, then build both targets; builds reject stale art.

Current development focus (2026-10-02): build and review TI-99 only, per the
user's request. Coleco validation will resume after the TI gameplay work.
See DESIGN.md sections 19-25 for TI validation, budgets and verification limits.

The physics checker executes actual BASIC routines and all three level parsers.
It checks objective handling, death rollback, timed hazard windows, magnet capture
and delivery, drill/enemy routes, twelve platform transfers, 448 lift/rider steps,
both spring transfers, jump clearance, walk-off versus jump falls and sound
note-offs. It also tests the live spawn-to-conveyor-to-crane route at eight hazard
phases and factory lift entries from all six side tiers at fourteen phases each.
101 deliberately broken variants must fail. New checks cover moving
pincers, visible hazard bounds, belt/slag alignment, speed clocks, elevator boarding
with background tiles, both parked and moving elevators at game over, two-jump
pincer crossings launched at closure in both directions, the factory box route
without its shortcut, enemy jump prevention, and overlapping sounds with explicit note-offs. Controlled-position tests do not
prove uninterrupted whole-level clears or original-hardware performance.

The [C64 longplay](https://www.youtube.com/watch?v=WSbEDNtmQWY) is an additional
reference, including its loose girders and machinery. Its pacing differs from the
Apple II recording; these are documented adaptation choices, not a claim of exact
original collision-box dimensions. See DESIGN.md sections 16-17 for evidence,
speed measurements, budgets and verification limits.
