# Choplifter — TI-99/4A / CVBasic

Current-state design. History is in git; sizes below are from the latest build
(2026-10-07); full-loop speeds were re-measured the same day, per-routine costs on 2026-10-06.

## Performance budget

- **Loop.** Real time, frame-delta pacing: `dt` is the number of video frames since the last
  update, clamped to 6. Updates run at most every 2 frames (30/s); an update that already
  took 2 or more frames starts the next one immediately (`main_loop`), so the only idle wait
  is the scroll synchronisation below. At 6 frames per update the game still runs at true
  speed, just in coarser steps; beyond that it slows down.
- **Measured rates** (Classic99 Normal speed, `tools/profile.py` full-loop cases, video
  frames per 32 updates → updates per second):

  | Situation | Original | Now |
  |---|---:|---:|
  | Cruising over open terrain | 160 (12/s) | 95 (**20/s**) |
  | Over a settled crowd with tank, jet, air mine and shots | 256 (7.5/s) | 154 (**12.5/s**) |
  | Two camps evacuating at once (32 walkers in view) | 380 (5/s) | 192 (**10/s**) |

- **Cost model.** One video frame buys only about 1,300–1,500 instructions of compiled
  CVBasic (code runs from the 8-bit 32K expansion). Per-call costs from
  `profile.py --micro`, in frames: stars 0.48, terrain rows and overlays near open camps
  0.66, settled crowd row 1.0, moving-crowd compositor with 32 walkers 3.25, walker logic
  for 32 walkers 1.56, sprites with every actor on 0.78 / all off 0.34, enemies and weapons
  0.53, sound + rotor + pause input + flight 0.34. A scrolling update costs whole frames:
  its synchronised WAIT rounds the work up.
- **Hardware sprites.** At most 17 world sprites, each in a fixed slot (*Sprites* below),
  with CVBasic's `SPRITE FLICKER ON`: on a scanline with more than four, every sprite takes
  its turn, the helicopter included. Tanks run on their own plane below the crowd row, so a
  landed helicopter never shares a scanline with them. An explosion is four or five sprites placed
  from ROM tables, with no per-particle RAM or arithmetic beyond an index.
- **VDP work per scrolling update.** One WAIT, then rows 17–20 (128 bytes, back to back),
  then the flag and the blown-out barracks' row-19 overlays, then rows 21–22 (64 bytes) and
  the fence stamps. Row 23 is
  static. Stars write 14–28 cells, and none while the camera is still. No VDP reads, no
  GCHAR, no COINC; collisions use world coordinates and boxes cut to the drawn shapes
  (*Enemies*). The VDP's sprite-coincidence flag is not used: it is one bit for every pair
  of sprites and is a frame behind the update.
- **TI native kernels** (each with a portable BASIC twin used by ColecoVision and tested
  against it): star field, crowd walking, moving-crowd compositor, crowd colour upload,
  settled-crowd scan and row copy. See *TI native kernels*.

## Size budget

| | Used | Limit | Notes |
|---|---:|---:|---|
| TI fixed area (after short branches) | 22,478 | 24,336 | 1,858 free |
| TI fixed area, unoptimised | 24,266 | 24,574 | xas99's first pass must stay below >FFFE |
| TI data bank (`BANK 1`) | 7,654 | 8,190 | play-time data and tables, menu font; crash, title, setup and results code |
| TI boot bank (`BANK 2`) | 4,842 | 8,190 | art uploaded only at power-on |
| TI RAM | 810 | 7,854 | |
| ColecoVision ROM | 28,379 | 32,768 | |
| ColecoVision RAM | 811 | 814 | nearly full; see `#vaddr` |

The TI cart is 64 KB: three loader pages and two banks. `assets/generate.py` writes two
files. `assets.bas` (crash flames, map, crowd glyphs and palettes, fire frames, arcs, the
explosion timelines, menu font) goes into the data bank, which start-up selects for good.
`assets_boot.bas` (all 64 sprites, the scenery characters and colours, waiting people,
stars) goes into the boot bank, which `boot:` selects only around those uploads. With the
boot-only art out of it, the data bank also holds the enemy and hit-box tables and the cold
code: the crash routines (`crash`, `crash_tick`, the burst triggers and `crash_draw`, which
run only after a crash or a hit), the title (and its helicopter), the 838 setup and the
results. The crash routines moved there when the explosions, difficulty levels and new
collision code pushed the unoptimised fixed image past >FFFE; code in the data bank runs
at the same speed, since bank 1 never leaves the window during play. ColecoVision builds
the same source unbanked.

`tools/build.py` runs Keystone Kapers' verified `shortbranches.py` (about 425 branches,
1.7 KB saved) and fails if the unoptimised image reaches >FFFE, because that pass cannot run
then; it also checks both bank images and their place in the cart. The menu font's colour
table (all white on black) is filled at run time from the idle crowd pixel buffer instead of
256 identical ROM bytes. ColecoVision RAM is the tightest budget: `#vaddr` is one shared
VPOKE address used by every routine that computes an address and writes it immediately,
never across a GOSUB. The tank's aim reuses `#distance`, the air mine's target `#ax`
(scratch results of `distance_x`), the pause its frame counters from the main loop, and
the jet, missile and shell moves share `#bullet_step`. An explosion's whole state is
`#blast_x`, `blast_y`, `blast_timer` and `blast_end` (its kind); `blast_draw` steps through
its debris rows with `di`, idle once `draw_actors`' shot loop is done, and a small burst
takes its position in the scratch `#ax`/`ay`. `hide_all` counts with `ini`; dropping the
camp indicators freed `hc`. The rotor's chop costs three: `chop_period`, `chop_frame` and
`sound_busy`. Three bytes are left.

## Research and adaptation

Based on Dan Gorlin's original rescue game, rather than Sega's later arcade campaign. The
[Atari 5200 manual](https://atariage.com/manual_html_page.php?SoftwareID=2057) specifies 64
hostages, 16 passengers, three helicopters, separate lost/aboard/saved tallies, vulnerable
people and landing-pad unloading. The
[Atari 7800 manual](https://atariage.com/manual_html_page.php?SoftwareID=2121) describes four
barracks and escalating tanks, jets and airborne mines. The
[Atari version comparison](https://www.atariprotos.com/other/gamediff/choplifter/choplifter.htm)
distinguishes Apple's two-button controls from Atari's hold-to-turn adaptation;
[gameplay notes](https://strategywiki.org/wiki/Choplifter!/Gameplay) describe tap fire, hold
rotate, jets after a delivery and later airborne mines. The user's
[C64 longplay](https://www.youtube.com/watch?v=wCrKd0fM1CY) was inspected as frame sheets in
the ignored `build/reference`: around 75–85 s the first group unloads beside the flag; around
87–98 s jets approach head-on and turn into side-on firing passes; the footage shows
front/side helicopter poses and pronounced pitch in travel. The same footage sets the scenery:
blue barracks with a white roof edge, a chimney, a dark doorway and a white porch, blown
open with a fire inside once shot; low blue mounds flecked with white between the camps
(drawn taller here, at the player's request); and at home a low brick building with white roof edge, window bands either
side of a dark door, the flag at its east end and a blue landing pad. There is no sign on the
building. Reference material is not a build dependency.

Tank fire: neither manual, [Wikipedia](https://en.wikipedia.org/wiki/Choplifter) nor the
[C64-Wiki](https://www.c64-wiki.com/wiki/Choplifter) gives a range or trajectory. They agree
that tanks shoot at a helicopter that is landed or near the ground, with turrets that track
it, and [StrategyWiki](https://www.strategywiki.org/wiki/Choplifter!/Gameplay) adds that
tanks cannot hit you if you remain airborne. A short shell that falls under gravity gives
exactly that: a finite, short range and a threat only on or just above the ground. Jets:
the same sources say they attack a helicopter in the air with air-to-air missiles and one on
the ground with bombs. The C64 footage shows jets diving in head-on and then flying side-on
passes; this game's jets fire only straight ahead along their flight. The 7800 manual's
airborne mines are small, slow, homing objects in the footage.

This is new code and new pixel art, not a conversion. TI adaptations: an eight-screen world,
eight-pixel scenery scrolling, character-composited crowds that also board as characters,
up to two tanks, one jet and one air mine, a single fire/turn button (with SPACE or keypad
`*` as a turn key), gravity instead of a fuel limit, bombs for tanks but strafing for
everything else, three difficulty levels, and particle explosions drawn with four sprites.
The jets' bounded three-pass route, the shells' arc and the missiles' dive are adaptations,
not claims of identical original AI.

## Play and accounting

The world is 2,048 pixels wide. Home is at the east end: a 40×13 brick building
(x=1976–2015, door at x=1992) with its flag on the roof at x=2008, and against its west wall
a landing pad 56 pixels wide (x=1920–1975). The helicopter spawns in the middle of the pad
(x=1932) and unloads only with all 32 of its pixels on it (1920 ≤ x ≤ 1944). Each passenger walks to the door, and
some stop on the way to wave at the helicopter (*Play and accounting*). A 320-pixel demilitarised zone (DMZ)
spans x=1568–1888 between two boundary fences. Four camps at x=128, 384, 640 and 896 hold 16
people each; each barrack is 32 pixels wide (x−16 to x+15), and the nearest one's outer wall
is 656 pixels from the enemy-side fence.

Strafing a barrack (a sideways shot whose 3×3 touches the drawn hut, x−16 to x+15, at or
below its roof line, y ≥ 151; bombs pass by) blows it open in a ground burst: its middle is
a ragged hole with a fire burning inside. It releases one person every 24 video
frames, whatever the helicopter is doing, including during a crash. People walk out in two
groups of eight to waiting spots 8 pixels apart, up to 88 pixels from the camp, farthest
spots first. The cabin holds 16.

**Boarding.** Landed with seats to spare, the nearest waiting person within 104 pixels of the
cabin door starts running for it, and one more joins on every update, so a whole group is
running within a second or two; each boards on reaching the door. Runners never outnumber the
free seats (`board_count`), so a nearly full cabin is never chased by people who cannot get
in. Runners are crowd characters (walking poses, no sprite) and as exposed as anyone outside.
If the helicopter ends up more than 180 pixels away they walk back to their places; while it
hovers nearby they wait. A group of 14 within reach boards in about four seconds (the
previous one-runner-at-a-time scheme took about 17 for a full cabin). Land on the pad at home
to unload people one at a time; each walks to the building's door and counts as saved on
leaving the cabin. One in four (ids divisible by 4), and always the last one out of the
cabin (`last_out`), stops at x=1964 on the black ground, its raised arm 4 px short of the
building (for contrast), and waves at the helicopter for 90 frames: standing poses, arm up
and down. One waves at a time (`wave_id`); the last
one out cuts short anyone else's wave. A waver steps past the spot afterwards, so nobody
waves twice, and the next delivery's jets wait until everyone is inside.

Saved + lost + aboard + everyone still at the camps always equals 64; a runner counts with
its camp until it boards or dies. A crash loses everyone aboard and one helicopter; the next
starts at home. The HUD, after the arcade's, is a magenta band (rows 0–2) holding four black
capsules with pointed ends, 10 pixels tall (y 7–16): left to right the dead (a red dot),
those on board (cyan) and the saved (bright green), each with two white digits, then the
spare helicopters (excluding the one flying), right-justified in the fourth capsule's four
cells, so at most four show. A practice game's star stands on the band after the saved
capsule. The band's 13 characters (`HUD_CHARS`: band, capsule edges and ends, three dots,
the star) are uploaded once to codes 1–13 of the top screen third only, where codes below 32
are otherwise unused; `game_screen` copies the template (`hud_rows`) and `hud` writes the
counts, icons and star. There are no camp indicators. The band ends at y 23 and the
helicopter climbs no higher than y 25, so it never flies into it. The mission ends when all 64 are saved or lost, or the last
helicopter is destroyed; the results screen lists the skill level played, then saved,
lost, stranded and the session's
best rescue. A perfect rescue is 64.

People persist across trips and crashes. Landing on an exposed person (escaping, waiting or
running) kills them; so do player shots and bombs, a tank shell's landing and a jet's bomb or
diving missile. Lost people never return or count twice.

## Controls and flight

Joystick 1 flies independently of facing; the helicopter starts facing left. Releasing
horizontal input brakes to a hover without changing aim. Horizontal acceleration and braking
step once per update (0–3 px/frame); cruising distance follows elapsed frames.

FIRE is sampled every video frame by an `ON FRAME` handler, so taps survive slow updates: a
press shorter than 18 frames (0.3 s) fires on release; holding turns after 18 frames and
then every 15 (0.25 s), cycling left → front → right → front (`turn_step`). Releasing after
a turn does not fire. SPACE (TI) or keypad `*` (ColecoVision), read by the same handler,
turns one step per press, edge-triggered (`turn_key`), and never fires. The helicopter
cannot turn on the ground: the hold timer stays at zero while it is landed, so lifting off
with FIRE held starts a fresh hold, and the turn key does nothing there.
Side views shoot in the facing direction and follow the nose pitch; the front view drops
bombs that keep the helicopter's sideways speed at release. Shots expire after 90 frames or
on leaving the view; old shots retire before a new tap is accepted. Weapons are disabled on
the ground, and so is sideways flight: lift off with UP first. Menus, pause and respawn gate
the sampler and discard stale presses.

Holding DOWN descends at 1 px/frame, speeding up every 24 held frames to 3 px/frame;
releasing DOWN brakes. **Gravity:** with the stick centred (no direction at all) the
helicopter sinks 1 px every 6 frames (10 px/s, `sink_clock`), slow enough to settle on the
ground safely; any direction holds it up. Touching down faster than 1 px/frame crashes, even during
spawn invulnerability; short taps land safely. While the descent is that fast the engine warns
with a higher, pulsing whine (higher still at full speed), which stops when DOWN is released. Holding P (TI) or keypad 0 (ColecoVision) for
12 frames pauses; the same key or FIRE resumes. Pause silences sound and resets the frame
clock. **BACK (FCTN-9) or REDO (FCTN-8)** abandons the mission for the title, from play or
from the pause; keypad # does it on ColecoVision. `back_key` reads the TI keyboard matrix
over the CRU, because the key scan stops at FCTN, and the main loop tests it at its top
level so `GOTO title` leaves no return address on the stack.

**Crashes.** A hit is drawn before it explodes: `hits_heli` only sets `crash_pending`, and
the main loop crashes at the top of the next update, so the frame between shows the threat
touching the helicopter. From the crash on, the helicopter itself is never drawn: it and
every other actor are hidden at once, a burst plays where it was hit (an air burst, or a
ground burst if it was landed), and only its burning wreck is drawn, flames in slots 0–1
whose two halves swap yellow and red every 8 frames, falling at 2 px/frame with its
sideways speed. On landing it bursts again (a ground burst) and burns for 90 frames,
burning down in four stages as `crash_tick` redefines sprites 13–14: full flames (15 rows,
142 pixels), then lower and narrower ones from 60 frames before the end (`crash_burn2`, 9
rows, 76) and from 40 (`crash_burn3`, 6 rows, 43), then embers from 24 (4 rows, 26), each
at least half the one before so the fire never drops from a blaze to a few pixels
(`burn_down` in the generator squashes and narrows the full flames); nothing at all for
the last 12, by which time the burst is over and erased too. Only then does the next
helicopter appear on the pad (`new_heli`, `game_screen`), drawn with its own patterns, or
the mission ends. Lives and passengers are charged once, at the crash. Meanwhile camps keep
releasing people and walkers keep walking; the wreck's impact counts as no landing on anyone
(`old_y` follows it).

## Enemies

All enemy activity and border checks use the DMZ fence, x=1568. Enemies never multiply (four
sprites per scanline); they push harder instead. The **difficulty** (easy, medium or hard,
picked on the title; medium at power-on) and the **level**, the number of completed
deliveries capped at 4, together give `threat = 5 × difficulty + level`, which indexes rows of
five in small ROM tables (`tank_reload`, `jet_missiles`, `#jet_delay`, `#drone_delay`): every
level strictly harder than the one before, and every difficulty harder than the one below
at the same level. The first completed delivery brings a second tank on every difficulty.

| Level | 0 | 1 | 2 | 3 | 4 |
|---|---:|---:|---:|---:|---:|
| Frames between tank shells: easy / medium / hard | 200 / 140 / 100 | 180 / 125 / 90 | 160 / 110 / 80 | 140 / 95 / 70 | 120 / 80 / 60 |
| Missiles per jet | 1 / 2 / 3 | 1 / 2 / 3 | 2 / 3 / 4 | 2 / 3 / 4 | 2 / 4 / 5 |
| Frames before the next jet | 480 / 360 / 270 | 440 / 320 / 240 | 400 / 280 / 210 | 360 / 240 / 180 | 320 / 200 / 150 |
| Frames before the next air mine | 360 / 240 / 180 | 320 / 210 / 160 | 280 / 180 / 140 | 240 / 150 / 120 | 200 / 120 / 100 |

The difficulty also sets how enemies fire and chase, from three-entry tables (easy / medium /
hard): a tank shell's top speed (`tank_speed`, 2.5 / 3 / 3.5 px per frame: a reach on the
ground of about 90 / 105 / 120 px), the frames between a jet's missiles (`jet_reload`, 90 /
60 / 40), how far out of line a jet still fires (`jet_aim`, 10 / 16 / 24 px), and the air
mine's drift (15 / 30 / 45 px/s).

**Hits** test boxes cut to what is drawn, never a radius. The helicopter (`hits_heli`, at
its visible x `#hv`, see *Scrolling*) is its cabin, nose and skids (rows 5–14) plus, in the
side views, its tail boom (rows 8–9); the columns of each depend on the facing
(`heli_box`): 11–28 and 2–12 facing right, 3–20 and 19–29 facing left, 9–24 in the front
view. The rotor blade, mast and tail rotor, and the sprite's empty corners, do not count.
Threats: the air mine's ball and spikes (x+3–11, y+3–11), the jet's fuselage (all 16
columns, rows 6–9) and its wings and tail fin (rows 3–12, columns 6–14 flying west, 1–9
flying east; `jet_body`, `jet_wings`), a missile 11×3 or a bomb 4×6 about its centre, a
shell 3×3. Player shots use the same jet boxes.

- **Tanks.** 32×16 pixels with left, right and front views; the side views raise the
  barrel about 25°. They drive on their own plane in the foreground (rows 22–23, tracks at
  y=189, sprite y=174), below the barracks and the crowd row, so only bombs reach them and a
  landed helicopter never shares their scanlines. One tank until the first completed
  delivery, then up to two (`tank_on(2)`, `#tank_x(2)`). They crawl toward the helicopter at
  15 px/s, never past x=1504, and one stops 40 px short of the other ahead of it. The limit
  is the fence as drawn: its perspective stamp leans its near end up to 32 px west when it
  stands at the west edge of the view, so on the tanks' rows its westernmost ink is x=1536,
  and a tank at 1504 ends (barrel tip, x+30) at 1534. At the old limit, 1536, a tank stood
  half over the fence. Jets turn at x ≤ 1528 (16 px wide) and the air mine stops at 1552.
  A single
  timer (`#tank_wait`, counting only while the helicopter is west of the fence) spaces
  arrivals and shells: when it runs out a missing tank arrives (160 px behind the
  helicopter, or 180 px ahead near the west end or when the other tank is already behind),
  or else the first tank on screen that can reach the helicopter fires. A tank off screen
  holds its fire.
- **Shells are short lobs under gravity** (`tank_aim`, `shell_tick`), one in the air at a
  time, from the barrel tip the turret faces (x+0, x+29, or x+15 when it shows its front).
  Research: tanks cannot hit a helicopter that stays airborne; they fire when it has landed
  or is near the ground. So a tank fires only at a helicopter at y ≥ 137 (within 16 px of
  landing). A shell leaves the muzzle at y=176, climbs 32 pixels in 20 frames, falls back
  and bursts on the crowd plane at y=164 on frame 36 (`shell_arc`, generated), killing
  whoever stands at the impact. The tank aims at the helicopter's centre: it finds the frame
  of the fall that reaches that height and the rounded horizontal speed, in 1/16 px per
  frame, that arrives with it, so a helicopter that stays put is hit and one that moves is
  missed. It fires one shell per reload (above), and only when the speed is within
  `tank_speed` (on medium 3 px/frame: a reach of about 105 pixels on the ground and 72 at
  y=137) and the helicopter is within 128 px. A new shell is drawn at the muzzle before it
  first moves and is harmless for its first 8 frames, so no shell strikes before it has
  been seen; a helicopter landed right over a tank is hit when the lob comes back down. A
  slow update never carries a shell past its burst frame, and no shell outlives its 36
  frames or crosses the fence. Its landing is a small ground burst.
- **Weapons.** Bombs (front view) destroy tanks (a ground burst) and nothing else in the
  sky; they fall past the crowd row (hurting anyone they cross) and, missing, burst on the
  ground below the tanks' tracks (y > 185). Sideways shots open barracks and down jets and
  air mines (air bursts), and stop at the ground. Whatever ends in a person or on the ground
  bursts there (`shot_burst`, `missile_burst`, `shell_tick`): a bomb, a jet's missile or
  bomb and a tank shell with a small burst, a sideways shot with a tiny puff. Hitting a
  person (`crowd_struck`) throws the burst's spray; bare ground with no target, or a missile
  ending at the fence or the world's edge (`shot_miss`, `missile_miss`), plays only its
  core, so a miss reads differently from a hit.
- **Jets.** Enabled after the first completed delivery (every walker has gone indoors at home).
  A launch countdown of 6 s, then three passes at 120 px/s joined by two 48-frame banking
  turns, all west of the fence. The first pass scouts; after that a jet on screen fires
  only straight ahead along its line of flight, one weapon at a time (research: air-to-air
  missiles at a helicopter in the air, bombs at one on the ground), at most one every
  `jet_reload` frames. A **missile** (a missile-shaped sprite, nose first) leaves the nose
  level and flies on at the jet's 2 px/frame plus 2 of its own for half a second
  (`missile_ttl`, 30 frames), then noses down 2 px/frame until it bursts on the ground (or
  in the crowd, at the fence or at the world's west edge: none just vanishes); the jet fires
  it only with the helicopter ahead and in line (centres within `jet_aim` px of height). A
  **bomb** keeps the jet's 2 px/frame and falls 2 px/frame, so it lands as far ahead as it
  falls; the jet releases it with a landed helicopter that far ahead, and it bursts on the
  ground, killing anyone it lands on. After
  its last pass a departing jet retires as soon as it is wholly off camera, so the gap before
  the next jet does not depend on how far west the world extends.
- **Air mine** (the `drone_*` variables). Enabled after the second completed delivery, while
  the helicopter is west of the fence. A small dark-red spiked ball, it appears out of view
  at mid height (y=88): 8 px beyond the east edge of the view, or 8 px beyond the west edge
  when the east edge is past the fence. It drifts toward the helicopter at 15, 30 or 45 px/s
  on both axes, in quarter pixels, stopping at the fence (x ≤ 1552). Touching it crashes the
  helicopter; one shot destroys it. It used to appear at y=32 and, near the fence, at x=1552
  even when that was on screen, which could put it on top of a helicopter flying high near
  the fence: a crash with nothing visibly coming.

## Display

256×192 TMS9918 screen. Rows 0–2 the HUD band, rows 3–16 sky (PAUSED, centred on row 4,
which no star uses, while paused), rows 17–21 scenery (row 20 is the crowd row), rows 22–23 ground. The ground is dark blue
(the mountains rise out of it in the same colour), the landing pad gray with a white rim,
and the fence stamps white on the ground's blue. Ground contact: helicopter
top y=153 (its lowest ink at y=167 touches ground row 21 at y=168); tanks on rows 22–23.

**Scrolling.** The camera moves in 8-pixel steps, following the helicopter at screen x 112.
The helicopter is drawn at its *visible* x, `#hv` (set by `move_heli`): while the camera
follows (112 < x < 1904) that is `#hx` rounded down to 8, so it stays at screen x 112 and
the scenery steps past it, instead of creeping 0–7 px ahead and jumping back 8 at every
camera step (a sawtooth the player saw as the helicopter jerking left and right); at either
end of the world, where the camera stops, it is `#hx`. Everything the player judges by eye
uses `#hv`: drawing, hits, the shots' muzzle, the cabin door for boarding and unloading,
landing on people, the pad, and the enemies' aim. The physics keeps `#hx`. A scroll update
composes the crowd row
first (without touching the visible one), then `crowd_commit` draws every sprite for the new
camera, the helicopter last, WAITs for vblank and copies rows 17–19 and the crowd row back to
back. The vblank that ends the WAIT copies the new sprite positions, so the sprites and the
scenery move on the same frame (when the sprites were drawn after the scenery copy, the
helicopter sat at its old screen place over scrolled scenery for a frame or two and
appeared to shake), and roofs and their footings always share a camera position. The flag and the blown-out barracks' holes (rows 17–19) are written immediately after, ahead
of the ground rows and fences, so they land before the beam reaches them; otherwise a
blown-out barrack shows its closed front for a frame after each scroll. Then rows 21–22
are copied and the fence stamps drawn. Row 23 is drawn once by `game_screen`.

**Stars.** A sparse sky of eight stars on uneven rows (three far, two middle, three near), in
three parallax bands: rows 3–6 move 1,
rows 7–11 2 and rows 12–16 3 pixels per 8-pixel camera step, wrapping at the screen edges.
Characters 240–255 hold eight sub-cell phases in two shapes. Each star is redrawn in one pass
and its old cell cleared only when it has left it; because each star owns its row (the
generator asserts it), that never erases another star. `star_row` ends with row 0, so the
list in `assets/generate.py` can change length freely.

**Scenery art.** `assets/generate.py` paints the barracks, mountains and home as letter-per-pixel
art (`HUT`, `HUT_OPEN`, `MOUND_TOP`, `MOUND_LOW`, `HOME`) and cuts it into characters with a
colour per pixel row; it rejects any 8×1 segment that would need a third colour (which is
why the barracks' sloping roof edges have no white outline). A barrack, after the arcade's,
is four characters wide on rows 19–20 (camp column −2 to +1): a blue hut with a white roof
line, a brick chimney at its west end (row 18), a dark doorway under the roof's crown, a
white porch below it with a ramp and rails, and a white footing. Shot open, it is blown
out: its two middle columns (west of the camp column, and the camp column) show a ragged
hole on row 19 (134, 136, written by `camp_fronts`) with a fire burning inside on the crowd
row (126, 127, written into the crowd row by `crowd_doors` unless someone stands there). The
fire's two frames swap every 8 frames. Mountains are rough blue ranges 4–6 columns wide
and up to 16 pixels tall: flanks and body on the crowd row (142, 133, 143), and on row 19
a small peak (148), the tall snow-capped summit (149), a middling peak (158) and another
small one (150), with valleys between and a few white rocks; any 4-, 5- or 6-wide
selection of tops joins up. The flanks rise only from 5 to 8 pixels, and one or two
foothill characters on each side carry the slope down to the ground (121, 122 west; 123,
124 east: bottom-third characters uploaded after the reserved cell 120 as `low_art`), so a
range climbs over 2–3 characters per side instead of jumping up (`MOUNDS` gives each
range's width and foothills). They sit in the gaps between the crowds (the generator
asserts no range or foothill reaches a waiting spot or the home fence). The home is five characters on rows 19–20 (columns 247–251) with the flag pole's stub
drawn into the last roof character (139), so the pole stands on the roof. The landing pad
(`PAD_ART`) is a gray slab seven characters wide on row 21 (columns 240–246, x 1920–1975)
right against the building's west wall: a white rim with yellow lights at both ends, a
white H in the middle (column 243) and a dark shadow under its front edge (codes 159, 137,
138, 141). Its plain rows carry white ink, so a fence stamp drawn over it would stay white.

**Fences, pad and flag.** Each fence is a clipped 5×2 perspective stamp from the
horizon (row 21) into the foreground (row 22) whose near end leans away from the screen
centre; empty stamp cells are transparent. The home fence's stamps end at column 238, so
none crosses the pad; character 120 stays reserved for a precomposed pad-and-fence cell
(the generator builds one if a stamp ever lands on the pad) and holds blanks. The flag
waves by redefining two characters every 16 frames.

**Crowds (characters, not sprites).** All 64 people are background characters in row 20, so
a whole crowd costs no sprite slots, runners included.
- *Appearance.* Three looks by `id % 3`; poses `(anim/8 + id) AND 3`, so neighbours are out of
  step; walking speeds of 60, 48 or 40 px/s from a stride of 4, 5 or 6 frames per 4-pixel
  step, with each person's step clock offset by its id (one shared clock, no per-person
  timers).
- *Settled crowds.* A camp with no walkers has everyone on world-aligned spots 8 pixels apart,
  so each person owns a cell: 24 prebuilt standing characters (3 looks × 4 poses × night or
  barrack-wall paper) are written straight into the name row.
- *Moving crowds.* Camps with walkers or runners, and homeward walkers near the home, go
  through the
  compositor. A person sits on a 4-pixel grid, so they fill one cell or straddle two. ROM
  holds pre-shifted copies of every pose (unshifted, and the two halves of a 4-pixel shift).
  A 256-byte RAM buffer holds the row's pixels; the first person in a cell copies in the
  scenery pattern beneath it, then every silhouette touching the cell is ORed in, so
  overlapping people merge. Each 8-pixel cell has one palette (a TMS9918 limit): the first
  person's look, except that a barrack wall (132), mountain body (133), home window (156) or
  doorway (157) keeps its scenery from `CROWD_BASES` with a per-row palette from
  `PERSON_COLORS`. Where a row would need a third colour it gives way: under a walker a
  window pane's brick edges and the doorway's frame turn dark. A test compares each of these
  with its scenery character. Someone in front of a burning barrack hides the fire in that
  cell. Patterns and
  colours upload to the hidden half of a double-buffered character set (codes 0–31 or 64–95
  in the bottom screen third), then one name-row copy switches over.
- Settled camps stay on the cheap path even while a neighbour evacuates: crowds of different
  camps are at least 64 pixels apart and never share a cell.

**Sprites.** Two 16×16 sprites make the 32×16 helicopter, in left, right and front views
with two rotor beats each and level or banked poses; side views alternate cross and diagonal
tail-rotor blades. Main and tail rotors share a four-frame beat that never skips both poses on
a slow update. There are 64 sprite patterns; 13–14 are the crash flames, 18–19 the
explosion's fireball and ring, 47–49 the missiles and bomb, 51–57 the explosion's sparks,
embers, dirt, flash and puff, and 58 an air burst's falling chunk; 50 is free.
Fixed slots:

| Slots | Owner |
|---|---|
| 0–1 | helicopter (after a crash, its burning wreck) |
| 2 | tank shell |
| 3 | jet missile or bomb (patterns 47/48, 49) |
| 4–5 | player shots |
| 6–7, 8–9 | tank 0 and tank 1 halves |
| 10 | jet |
| 11 | air mine |
| 12 | explosion core |
| 13–15 | explosion debris |
| 16 | an air burst's falling chunk |

The VDP draws four sprites per scanline. `SPRITE FLICKER ON` makes the TI's vblank copy start
one slot later each frame (all 32 slots in turn), so on an overloaded line every sprite,
the helicopter included, is drawn on most frames and none is left invisible (an invisible
mine or shell read as dying for no reason). Low slots show most often; lines with four or
fewer sprites never flicker. `#sprite_shown` has one bit per slot (0–15; slot 16 shares bit 0,
which is free because the helicopter's slots 0 and 1 are drawn with `SPRITE` directly and
never use the mask, and a test proves both halves), so an inactive
actor's slot is hidden once and then costs a bit test.

**Explosions** (`blast_draw`) are four sprites (five in the air): a core and three clusters of three to eight
separate pixels each, so they read as a spray of particles. Everything comes from ROM
tables written by `assets/generate.py` (`BLAST_ROWS`), one row per two frames, indexed by
`(blast_end − blast_timer) / 2`: the core's pattern, colour and rise, the debris' pattern
and colour, and each cluster's offset from the burst (stored +64). Six kinds:

| Kind | `blast_end` | Frames | Used for |
|---|---:|---:|---|
| Air burst | 36 | 36 | jets and air mines shot down, the helicopter hit in flight |
| Ground burst | 72 | 36 | tanks, barracks, the helicopter hit landed or its wreck landing |
| Small burst | 92 | 20 | bombs, jet missiles and bombs, and tank shells hitting a person |
| Small, core only | 112 | 20 | the same on bare ground, with no target |
| Tiny burst | 124 | 12 | the player's sideways shots hitting a person |
| Tiny, core only | 136 | 12 | the same on bare ground |

A big burst's core flashes white, turns yellow, opens into a ring that reddens to dark red and
fades out where it burst; nothing rises (a gray smoke puff rising 12 px once ended each
burst and read as a second, white explosion popping up at the end). Its debris (white, then yellow, orange, red embers) is thrown on
ballistic arcs up to 60 px out. An air burst also drops a burning chunk with a trail of
sparks straight down (slot 16, pattern 58), up to 120 px over its 36 frames
(`blast_fall`, `blast_fpat`, `blast_fcol`; hidden once below the screen), so it reads as a
burst in the sky rather than on the ground. In the air the debris falls on past the burst; on the ground
it comes down at the burst's level and lies there. A small burst is a white star flash, dirt
thrown up and falling back, the flash fading through yellow and red to dark red. A tiny
burst is a 5×5 puff that flashes white and fades through red to dark red, with three sparks hopping up to 6 px out. A core-only kind
has the same core rows with debris pattern 0, which `blast_draw` reads as "no spray" and
hides slots 13–15 (no debris art uses pattern 0; the generator asserts it). A burst places its
own sprites; a particle below the screen is hidden rather than given y=208 (which would end
the sprite list). It sits where the projectile ended, but no lower than the ground's surface
(burst top at y 176). One burst plays at a time, and a smaller one never cuts short a bigger
one still playing: a smaller `blast_end` is the bigger burst, so a big one replaces anything,
a hit's burst outranks the same size on bare ground, and a tiny core only replaces another.
`burst_play` takes the kind's `blast_end` in `blast_row`, idle outside `blast_draw`.

## Sound

Channel 0 carries the engine: a steady hum, quiet on the pad and higher under horizontal
load, and a louder pulsing whine while the descent is too fast to land on. **The rotor's chop**
is on channel 3: low white noise (type 6) restarted on each beat and dying away frame by frame
(`chop_air`, quieter `chop_ground` on the pad). The beat quickens with speed: every 12
frames idling on the pad (5 Hz), 9 hovering, then 8, 7 and 6 (10 Hz) as horizontal speed
builds (`chop_period`, set by `sound_tick`). The vblank handler (`fire_control`) times it,
so the beat stays steady whatever the update rate, and writes only single bytes (the noise
type, then volumes); `sound_tick` raises `sound_busy` while it writes, so the handler never
lands between the two bytes of a main-loop frequency write (`sn76489_freq` writes them with
interrupts on). `silence` clears `chop_period` before it quiets the chip. Channel 1 plays a short gun sweep or a longer falling
bomb whistle; when free it carries a nearby jet's distance-dependent tone or the air mine's
alternating warning. Channel 2 carries rising boarding and falling unloading chirps and a
three-note delivery chime. Channel 3's chop gives way to tank fire,
missile launches, explosions (which win over launches; a small burst is a shorter, quieter
crack and a tiny one a soft tick, neither cutting a louder one short) and an eight-frame squish when the helicopter
lands on a person. Effects expire on frame deltas; pause, new helicopters, the
title and the results silence all four channels and clear effect state. No music player.

## Title and practice setup

The title centres the name (row 4) and RESCUE OPERATIONS (row 6), with the helicopter
circling them clockwise at 2 px a frame on a 528-pixel loop (`title_heli`, x 8–247,
y 8–79, clear of all text): banked and facing its way along the top (east) and bottom
(west), in the front view down and up the sides, rotor turning. Below them FREE 64 PEOPLE.
FLY THEM HOME. (row 12), then the difficulty on row 15, `1 EASY  2 MEDIUM  3 HARD` with
the chosen one in brackets drawn light red (characters 91 and 93 recoloured with
`DEFINE COLOR` from `bracket_colors`; no other screen uses them, the crowd recolours its own
cells in play and `menu_restore` resets the bottom third), so the pick stands out from the
white text (`title_level`); there are no control instructions on the
title (the README has them). Keys 1–3 pick the difficulty, or LEFT/RIGHT step it;
`title_code` reads the stick as keys 20 and 21 so one edge test serves both, and a 3 that
continues an 8-3 sequence is not a choice. The pick lasts from game to game (medium at
power-on). The credit line, 2026 UNHUMAN AND AI C&C (the bottom third's font has no lower
case), is on row 21 and PRESS FIRE TO START on row 23: FIRE starts (no digit). The results
screen also continues with FIRE only. It lists SKILL LEVEL (EASY, MEDIUM or HARD) on row 7,
then PEOPLE SAVED, PEOPLE LOST and STRANDED on rows 9, 11 and 13, and BEST RESCUE on row
15; a practice (838) game puts the small star after the skill level and the saved count.

The hidden title sequence 838 shows one line, HELICOPTERS (1-9)?, and a digit 1–9 starts a
practice game at the difficulty last picked; there is no way back from it. Normal games use
three helicopters. Practice saved counts carry a small asterisk (character 60) and the best
rescue keeps its marker; an unmarked run wins a tie. At most four spare icons show.

## TI native kernels

Each kernel is inline `ASM` inside a BASIC routine, with the BASIC original kept as the
ColecoVision path:

| Routine | Work |
|---|---|
| `stars_draw` | the star field, one pass per star |
| `walk_camp` | one camp's escaping and homeward walkers (same stride DIVs as `person_stride`) |
| `compose_block` | one camp's people into the crowd pixel buffer (`crowd_plot`/`crowd_cell`) |
| `crowd_draw` | clearing the cell map and uploading cell palettes |
| `waiting_scan`, `waiting_draw` | settled people and the scenery row copy |

Rules they follow: registers r0–r9 only (r10 is CVBasic's stack; r11 is used only for a local
`bl`); the vblank handler has its own workspace, so registers survive interrupts; every VDP
address-and-data write is wrapped in `limi 0`/`limi 2`, as the runtime's `WRTVRM` does, so the
handler cannot move the address between the two halves; and a kernel ends in `RETURN` or is
followed by statements that reload what they use, because inline `ASM` does not invalidate
the compiler's register cache (checked in the generated assembly).

## Source, tools and validation

- `src/CHOPLIFT.bas` — the game. `assets/generate.py` owns art, the world map, the star
  table, the shell arc and the explosion timelines, and writes `src/assets.bas` (play-time
  data, including the menu font) and `src/assets_boot.bas` (power-on uploads).
- `tools/build.py` — generation, the 98 source-executing tests (once per `build.ps1 All`),
  the repository truncation and GOSUB gates, compilation, assembly, the short-branch pass with
  its verification, budget checks, an even-address check on every indexed word table (from
  xas99's symbol file: a label alone on its line before a padded `DATA` keeps an odd address
  that the listing hides), packing, and assembly assertions.
- `tools/check.py` — a strict interpreter that executes the game's BASIC routines and its TI
  kernels (registers, status flags, `DIV`, local `bl`, memory writes, the VDP ports, which
  must be written with interrupts off, and the keyboard matrix through the CRU). A routine
  falls through into the next label and follows `GOTO`, as compiled code does. Unknown
  statements and instructions are errors. A test that places the helicopter by setting
  `#hx` places it where it is seen (`#hv` follows); the game's own assignments bypass that,
  so `move_heli`'s rule is tested on its own. Hit boxes are checked against the sprite art
  pixel by pixel in every facing; the fence limit against the fence stamps' ink.
  Native kernels are compared with their portable twins over sweeps and randomised scenes,
  and known-bad mutations of every kernel must fail.
- `tools/profile.py` — benchmark carts: full-loop and component cases, `--micro` per-routine
  costs, `--stub ROUTINE` to attribute cost, and `--review` for a production-code cart that
  starts airborne over evacuating camps. Benchmarks call routines out of context and look
  scrambled on screen; use `--review` to judge rendering. The benchmark code itself goes in
  the data bank, in place of the title and results code it never reaches: the fixed area's
  unoptimised image has no room for it.
- `tools/run-bench.ps1` — runs a benchmark cart in its own Classic99, starts it (title key,
  then 2) and captures the finished screen. `tools/capture.ps1` screenshots and drives a
  specific Classic99 process. `launch-ti.ps1` opens a separate review session of the
  production cart.

Verified in Classic99: the production review cart scrolling over two evacuating camps with a
tank, shells and crashes (clean rendering, overlays in place); a soft landing beside a settled
crowd that boarded 16 in about two seconds of play; and every benchmark case. The redrawn
scenery was checked against an offline render and in Classic99: burning barracks with people
walking out in front of them, a mound, the home building, flag and pad, a lob arcing from a
tank and an air mine drifting in. After this round: the reference-style barracks with the
blown-out hole and the fire inside, the taller, peaked mountains, two tanks on the foreground plane with
raised barrels and their lobs, gravity bringing an idle helicopter down, a passenger waving
in front of the home, and the title helicopter circling the name. On 2026-10-07, frame
bursts captured from scenario carts built from the production source: a crash in flight
(the mine drawn touching the helicopter, then no helicopter at all while the air burst,
the falling flames, the ground burst on landing and the embers played out, an empty frame,
and the new helicopter on the new pad); the helicopter holding one screen column through
70 frames of scrolling while the scenery stepped past; bombs bursting on the ground; a jet
missile flying level, nosing down and bursting; and a tank stopping with its barrel short
of the fence. The ColecoVision build has been booted and flown briefly in CoolCV (before
this round). Not verified: original hardware, sound balance and a complete 64-person
mission played through.
