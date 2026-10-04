# Hard Hat Mack (ColecoVision and TI-99/4A, CVBasic)

An adaptation of Michael Abbot and Matthew Alexander's construction-site platformer.
Both targets build from `src/HARDHAT.bas` using the **unhuman/CVBasic** fork.

Three construction sites are implemented:

1. **Beams and Bolts:** carry four girder pieces to the holes, then catch the roaming
   jackhammer and rivet them. Filled but unriveted holes reopen after a death;
   their pieces return. Pieces are red with a white outline, both loose and
   placed; riveting makes them match the surrounding girder. All girders have
   centered rivet pairs separated by plain beam sections. Repaired gaps continue
   that spacing. Jump to ring the bell and summon the elevator. Landing anywhere
   supported by an armed elevator centers Mack and starts the ride. At either end of an occupied
   ride, Mack does two quick crouch-and-rise motions with a two-tone sound
   (about half a second); a horizontal nudge summons the next trip, while Jump
   lets him leave the cabin. A fixed launcher at the upper-right end of the
   top beam fires leftward rivets. The right-hand trampoline
   compresses under Mack, then rebounds and launches him; its base stays planted
   and his feet follow the moving cap. Mack starts one character to the right
   of the middle pedestal. The spray-can bonus is two characters to the right
   of that pedestal, clear of Mack's starting position.
   The bottom pedestals have a single bearing plate, continuous narrow stem
   and broad white footing, rather than repeated flared tiles.
2. **Lunch Break:** collect six lunch pails across the platforms and ground,
   avoiding the pincers, pounder, concrete, furnace and vat. The magnet stays parked until all six pails are collected. Jump from the upper
   conveyor into the armed magnet; it carries Mack back to the crane top. The upper
   conveyor is one character farther right; walking or riding past its right end
   is fatal, so jump before the last roller. Fixed and moving girders are bright
   green with blue edges and rivets. Lunch pails are twelve pixels tall; either
   side can be collected. Their rounded white lids, small handles and divided
   red panels resemble lunch pails. Concrete leaving the lower conveyor arcs
   into the single open-mouthed receiver; the extra machine beside the crane
   is removed. The bottom-right chain hangs from the platform's far
   right edge, with a clear floor approach to its left. Pincers complete
   a smooth cycle in 90 world steps (previously 96), preserving the two-jump route.
3. **Rivet Works:** start on the upper-right platform and collect six steel boxes.
   The conveyor box sits one character left of the smasher.
   Carry each to a lip of either lower-floor opening; the box drops into the
   processor. After a short processing beat, a rivet emerges from its dark,
   white-rimmed side outlet, travels clear of the casing, then drops into the
   nearby two-character-wide bucket; the final delivery finishes before the level ends.
   Flashing IN labels and downward arrows sit above white feed caps. The
   processors follow the supplied Apple II screenshot: low white outlines,
   dark blue fronts with red side panels, and angled oval shoulder outlets.
   The central cabinet has a white border, blue body, gridded window and red door.
   Four paddles circulate counterclockwise around rounded upper and lower axles
   (left down, right up). Moving chain links and rotating wheel spokes follow
   the same platform drive, so the whole mechanism works together.
   The upper-left conveyor carries Mack left at his walking speed: holding
   right keeps him in place, releasing the stick carries him left, and walking
   left doubles his travel. Its tread animation matches that speed.
   At its left end, a single wall emitter throws animated white, yellow and
   orange spark trails across two characters; grab the escape chain before it.
   The two springs bounce Mack across the site and onto the opposite lower tier.
   Both are two characters wide, one row above the ground, and use level one's
   artwork, compression, rebound and launch sound. Only the pad
   under Mack compresses, with his feet following it before each launch.
   The processors, central cabinet and conveyor machinery are dangerous.

The smashers on levels 2 and 3 share a five-pixel-tall, predominantly white head,
with gray detailing. They remain visible at the top and reach their girder or belt.
Their downstrokes are slightly quicker again: level 2 descends in eight world
steps and level 3 in eighteen. The impact beats, bottom dwell and upward return
are unchanged. They wait visibly at the top before dropping.
The upper-right furnace's two-character support girder has centered blue rivets
in its bright green body. The furnace has a magenta-and-white cabinet with green
caps; fire shoots from its left outlet, curls upward, and retracts before repeating.
The plume broadens into a ragged flame with a bright core and cycling reds,
orange and yellow; red occupies at least half of each palette band. Its shape
flickers as it extends. In 838 mode, the selected starting level remains
visible briefly before gameplay clears the setup screen.

Mack's running cycle combines a passing step, extended stride and bent-knee
recovery with arm swing. A projecting hat brim, face and rear hair make his
direction clear; both layers of the jumping pose mirror when he faces left.
It follows distance walked, returns to a neutral pose
when stopped, and keeps his original height, movement speed and collision bounds.

Joystick 1: left/right walk, up/down climb, **Fire jumps** from a floor, chain,
crane beam, conveyor, or parked elevator. Direction at takeoff sets momentum.
**Hold Fire for 0.75 seconds to release the jackhammer** (Tab in Classic99,
Space in CoolCV). It returns to its starting position and cannot be re-caught until it and Mack
separate. Mack can carry only one block or jackhammer. A loose jackhammer passing
behind Mack while he holds a block is hidden until clear, so the two cannot
appear to be held together; its route continues normally. A new pickup resets
the hold timer, even if Fire was already held. Fire starts a normal game at site 1 with three lives.
Type **838** on the title, then a digit **1-9 for total lives**, then **1-6 for
the starting stage**. Stages 4-6 repeat screens 1-3 with the harder second-tour
enemy setup; stage 4 starts level 1 with two roaming enemies. The chosen number
appears beside the prompt before play begins. Release each key between digits.
These choices apply to one game only. Reserve hats exclude the current
life and are right-justified below the score line. One extra life is awarded at 7,000 points.
Classic99 uses arrows/Tab; CoolCV uses arrows/Space for controller 1. On TI-99,
F8 (REDO) or F9 (BACK) returns to the title during play.
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
Fire/Tab to return to the title. With no fresh press, the title returns
automatically after 10 seconds, even if Fire remains held. The message has a
one-character blank border. Completing a level visibly counts the remaining
bonus down in 100-point steps, adding it to the score with a short tick per step,
before playing that level's fanfare. Each tick is a quiet, short noise pulse
with a silent gap, rather than a sustained pitched beep.

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
ring. Placing a block adds a clunk; moving lifts add quiet ratchets; concrete
entering its receiver gets a plop; processing a box adds a crunch, followed by
a higher bucket ping when its rivet lands. Reward chimes have their own channel so they cannot erase a jump sweep.
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
& tools/hardhat-dev.ps1 BuildTI
& tools/hardhat-dev.ps1 LaunchTI
```

Or run `bash games/HardHatMack/build-ti.sh` followed by
`bash games/HardHatMack/build-coleco.sh` using Cygwin bash.
Outputs: `src/HARDHAT_8.bin` (Classic99/js99er) and `src/hardhat.rom` (ColecoVision).
Build sequentially. Both scripts run generated-art, physics, truncation and return-stack checks;
the TI source/art checks run concurrently, and physics rejection tests use up to four workers;
the TI build also verifies the fixed-area size and all four packed banks. Its 64 KB
cartridge contains the loader, setup/assets bank and separate banks for
actors/audio, the title/setup screen plus extra scenery, and motion/animated machinery; their wrappers restore
the setup/assets bank before returning. Coleco remains
an unbanked cartridge within 32 KB. The TI build uses
the repository's checked short-branch optimizer and verifies the resulting opcodes
and destinations after reassembly. `TI_SHORT_BRANCHES=0` retains the comparison
path with the same size gate. Starting play restores the gameplay characters
after the title artwork uses that character range.

Editable title lettering and scenery live in `assets/gentitle.py`; `--write`
regenerates the title patterns, colors and screen map. Builds reject stale art.
Editable conveyor, pincer, smasher, furnace and trampoline art lives in
`assets/genconveyors.py`. Mack's running poses, blocks, girders, pickups and factory scenery live in
`assets/genfixtures.py`; it enforces the TMS9918's two inks per character row.
`assets/genmotion.py` owns the exact factory paddle-position tables.
Run the changed generator with `--write`, then build; builds reject stale art.

Current development focus (2026-10-03): build and review TI-99 only, per the
user's request. Coleco validation will resume after the TI gameplay work.
See DESIGN.md sections 19-25 for TI validation, budgets and verification limits.

The physics checker executes actual BASIC routines and all three level parsers.
It checks objective handling, death rollback, timed hazard windows, magnet capture
and delivery, drill/enemy routes, twelve platform transfers, 448 lift/rider steps,
both spring transfers, jump clearance, walk-off versus jump falls and sound
note-offs. It also tests the live spawn-to-conveyor-to-crane route at eight hazard
phases and factory lift entries from all six side tiers at fourteen phases each.
164 deliberately broken variants must fail. New checks cover directional airborne
art, conveyor walking balance, quicker downstrokes, curved furnace flames,
cross-level spark restoration, bonus counting,
game-over timeout/release, full-width elevator boarding, spaced rivets,
synchronized factory chains/wheels, distance-driven running poses and material sound priority,
concrete entering the receiver, exclusive item
pickups in both orders, carried-sprite cleanup, loose-hammer overlap, fixture bank
ownership, complete pickup removal, processor output, title font restoration, moving
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

TI performance refinements reduce dynamic graphics transfers, skip absent
machinery and avoid an extra frame wait after a busy update. Factory paddles
use exact ROM lookups while collision checks still run at every pixel. See
DESIGN.md section 39 for timing evidence and validation limits. Controlled
Classic99 idle samples improved from about 23/12/9 to 49/16/14 updates per
second on the three sites. The upper-right level-two furnace rests on a full-width
riveted girder and repeatedly extends and retracts its left-facing flame; its
danger area follows the visible upward curl.
