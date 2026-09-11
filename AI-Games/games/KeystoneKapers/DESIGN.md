# Keystone Kapers — Design

A CVBasic port of **Garry Kitchen's *Keystone Kapers*** (Activision, Atari 2600, 1983;
AX-025), dual-target **TI-99/4A + ColecoVision** from one source.

Officer Keystone Kelly has Harry Hooligan cornered in Southwick's Emporium — a department
store **eight screens wide and four levels tall** — and fifty seconds to run him down before
he reaches the roof and vanishes. Kelly is fast. The store is long. Everything in it is in
the way.

**Single player.** One active Kop and three in reserve, faithful to the cartridge; `838` on
the title opens a setup screen for Kops and starting Krook.

---

## 0. Research base

The manual scan on archive.org is image-only (JPX streams, not OCR'd — confirmed by fetching
it), so the text below comes from the **AtariAge HTML manual**, the **Atari 5200 manual** at
atarihq, Wikipedia, PixelatedArcade and the activisionpatches strategy page. Where they
disagree the conflict is recorded rather than smoothed over — that is the rule that saved
Joust from shipping without a pterodactyl.

| fact | source |
|---|---|
| Garry Kitchen, Activision 1983; the store is **Southwick's Emporium** | Wikipedia |
| The store is **eight times wider** than the visible display; the view scrolls at the edges | PixelatedArcade |
| Escalators are at **alternating ends** of the map; the **elevator is in the centre** | PixelatedArcade |
| Kelly starts at the **first-floor entrance, lower right**; Harry at the **second-floor elevator door** | PixelatedArcade; activisionpatches ("centre of the second floor") |
| Kelly runs left/right on the stick; **jumps on the button**; button + direction = **long running jump** | AtariAge manual |
| Kelly **ducks when you pull the stick back** | AtariAge manual |
| **Push forward to step into an open elevator, pull back to step out** | AtariAge manual |
| Kelly **boards an escalator by touching it** | AtariAge manual |
| **Jump over** shopping carts, beach balls and cathedral radios | AtariAge manual; activisionpatches |
| **Duck under** toy biplanes | AtariAge manual; activisionpatches |
| A cart / ball / radio costs **9 seconds** | AtariAge manual; activisionpatches; atarihq |
| A **biplane costs a Kop** | activisionpatches; Wikipedia; atarihq |
| **50 seconds** per Krook | activisionpatches; Wikipedia |
| The timer **flashes when 9 seconds remain** | atarihq manual |
| Money bags and suitcases are **50 points each** | AtariAge manual; activisionpatches |
| Capture bonus = seconds remaining × **100 / 200 / 300** | AtariAge manual |
| **Three reserve Kops**; a bonus Kop **every 10,000 points**, three reserves maximum | AtariAge manual; atarihq |
| A Kop is lost to **time out, biplane, or Harry escaping off the roof** | atarihq manual |
| The scanner shows **all floors and the roof**: Kelly a **black dot**, the crook a **white dot**, the elevator a **grey square**, escalators **black slashes** | atarihq manual |
| **You are invincible inside the elevator, until you step out** | activisionpatches |
| Rising levels increase **obstacle speed** | activisionpatches |
| The store interior is flat **green**, floors are **thin light lines**, storefronts are plain blocks, the sky is **navy** with an orange skyline, the roof deck **grey**, Kelly **blue** | Atari 2600 screenshots, pixelatedarcade |

### 0a. The look is the ATARI 2600's, and it is measured

**The reference is the 2600 version** — the one this is a port of. Two earlier
attempts got it wrong in two different ways, and neither read as a colour bug;
both read as *a different game*:

1. **Dark blue store, from memory.** The store is green.
2. **The ColecoVision palette.** Tempting, because that machine has the same VDP
   and therefore literally the same sixteen colours, so it is the easiest thing
   to match. But it is a different-looking port: chunky floor treads, detailed
   shelving, a black sky with magenta buildings.

What the 2600 actually looks like, and what we now draw:

| element | 2600 | here |
|---|---|---|
| Store interior | flat medium green, wall to wall | `STORE_BG` = `DGREEN` — see §0d-bis |
| Floors | thick **olive bars** with a light top edge | ← *corrected, see 0b* |
| Storefronts | blue counters on the floor + narrow white pillars | ← *corrected, see 0b* |
| Sky strip | blue-violet; orange skyline above the roof deck | *superseded — see §0d-quater* | **`CYAN`** + `MRED` — see 0c |
| Roof deck | grey | `GRAY`, and it now backs the whole roof band |
| Score | **white**; timer and Kop hats **black** | ← *corrected, see 0b* |

**Quiet blocks are still the thing.** Bright storefronts on a green field are
harsh and busy; the 2600's charm is that it is mostly flat green with a few calm
rectangles in it — *simple, and still pretty* — so detail works against it as
much as the wrong hue would. `assets/preview.py` renders a screen from the
shipped bytes so this can be checked in a second instead of through an emulator.

### 0b. Measured from gameplay VIDEO, which overturned part of 0a

Everything in 0a above was read off **static screenshots**, and three of its
rows were wrong. `assets/grabref.ps1` pulls frames from a gameplay recording
(and documents the three separate reasons the obvious command line fails on this
machine). Motion also settles things a screenshot cannot: which objects move,
how the scanner is furnished, and what the HUD does as the clock runs out.

**What the video corrected:**

- **The floors are not hairlines.** They are **thick olive/dark-yellow bars,
  about 5 px, with one lighter yellow row along the top edge** — substantial,
  and the strongest horizontal line in the picture. 0a asserted the opposite
  ("thin light lines… thick treads alone make the store read as the
  ColecoVision port") and built a rule on it. The rule was sound — the CV port
  *does* have chunkier treads — but the premise was not: the 2600's own floors
  are bars, not lines. **This is the one correction that changes how the store
  reads at a glance, so it is the reviewer's call, not an automatic edit.**
- **The score is white, not yellow**, and the **timer and the Kop hats are
  black**, all three sitting in the blue-violet sky strip. The hats are bowler
  silhouettes at the left, the timer immediately to their right.
- **The storefronts are two different shapes, not two blocks.** Wide **blue
  counters** stand *on* the floor bar (bottom-aligned, roughly a third of a
  screen wide, half a band tall), and separate **narrow white pillars** span a
  band's full height. 0a had them as two same-shaped rectangles.

**What the video confirmed or newly pinned down:**

| element | what it looks like |
|---|---|
| Elevator | a **dark-green shaft column** through all three shopping floors — not the roof — with a **pale cyan car** riding in it |
| Escalator | a dark-green outlined parallelogram with **white step dashes**, plus a horizontal landing rail at the top |
| Shopping cart | a **white wire basket** — a mesh of uprights between two rails — on a solid black wheeled base |
| Beach ball | a **solid red disc**, not a ring |
| Cathedral radio | **yellow**, an arched case widest at the foot with two small prongs on top |
| Toy biplane | **dark green** body with a **light-green** propeller — two sprites; drawn from above so it reads as an aircraft (0n) |
| Money bag / case | **yellow box with a black handle** (ours: a tied sack stamped `$`, and a case) |
| Scanner | green field, **yellow horizontal lines per floor**, **black diagonal slashes** for escalators, a **pale block** for the elevator, and a white dot per actor — exactly the furniture §6 draws |
| Low time | the HUD digits and the Kop hats **change colour** as the clock runs down |

The frames are not checked in — they are someone else's recording. `grabref.ps1`
regenerates them into a scratch directory on demand; the observations live here.

### 0d. Two colours per SCAN LINE, not per character

A character that must show both a floor bar and the escalator crossing it looked
impossible — four colours in one cell — so the flight was shortened to stay clear
of the bar, which dragged the handrail up away from the steps. That was wrong,
and the reviewer caught it: colour here is per **scan line**, and any one line of
that character needs only **two** — whatever the floor shows on that line, and
black for the flight.

So the cells that cross a floor get **composite** copies: the same pattern,
coloured line for line as the floor is. Black on yellow where they cross the
bar, black on green above and below it. The floor runs across underneath the
staircase instead of being punched through by it.

**The roof needs its own set.** It is not coloured like a shopping floor — its air
is grey and its "floor" is the white-topped deck — so the flight up from floor 3
has a second pair of composites. Only the west flight climbs to the roof, so only
it needs them.

**This pushed the store past the scanner's characters.** The canvas used to start
at 144 and the store table grew to 155. `genart.py` now *checks* that overlap and
fails with the list of bases to move, rather than letting two tables quietly
overwrite each other's patterns.

---

### 0d-bis. The store's ground is a ROLE, not a colour

The shop floor moved from medium green (2) to **dark green (12)** on request —
the only darker green the TMS9918 has, so this dial has exactly two positions.
Measured off the emulator at fixed coordinates rather than judged by eye:
Classic99 paints the shop floor `(34,204,51)` before and `(34,187,34)` after,
over 84,000 identical pixels of the same region.

**The interesting part is not the colour, it is that fifty-six of the eighty-
seven store characters carry it.** On this VDP a character's "background" *is*
what an unlit pixel shows, so the ground is spelled out once per character:
every blank cell, every escalator tread, both end walls, the display cases, the
bags, the radio, the roof deck's lower rows. Spelling a colour out fifty-six
times means the next person to darken the shop has to find all fifty-six, and
the ones they miss are single cells in the middle of a wall — which read as
dirt, not as a bug.

So it is now one name, `STORE_BG`, in `genart.py`. **The substitution was only
safe because medium green was never a FOREGROUND**, and that was checked over
the built `CHARS` table rather than assumed: 0 characters ink with it, 56 sit on
it. If that ever stops being true this cannot stay a rename.

`previewrun.py`, `checkbands.py` and `checkesc.py` now **derive** the RGB from
`genart.STORE_BG` instead of carrying `(33, 200, 66)` as a literal. That is not
tidiness: `previewrun.py` has drifted out of step with the game three times
already, and a preview that lags the thing it previews does not merely fail to
help, it accuses the wrong file. `checkesc.py` needed exactly one colour and had
no palette table at all, so the canonical one now lives in
`genart.PALETTE_RGB` rather than becoming a fourth copy.

**The scanner was already dark green**, so its canvas and the store are now the
identical byte. It still reads as a separate object because its margin is
**grey** — which was the whole reason for the grey, and is more true now than
when it was written.

### 0d-ter. The lift's jambs move out of the doorway, and the opening gains a third

The doorway is four characters, 32 px. Its end columns each carried **four
pixels of jamb beside four of door**, so the opening the player was actually
aiming at was **24 px** — a quarter of the lift spent framing itself.

The jambs had been there for a reason. They began as whole columns of their
own, which put eight pixels of post around thirty-two of opening: a heavier
frame than the thing it framed. Moving them inboard fixed the proportion and
paid for it out of the opening, which is the number that matters — the lift is
what the player is trying to get into.

**They are outboard again, at four pixels instead of eight.** The column either
side of the doorway is ordinary wall (`t_elev` said so in as many words), so
its inner half can carry the post while its outer half stays shop floor: two
colours in one character, which is all this VDP allows and exactly enough. The
box is 40 px again and the opening is the **full 32**, a third wider.

| | box | opening | characters |
|---|---|---|---|
| outboard posts, 8 px | 48 px | 32 px | 2 columns of wall spent |
| inboard, 4 px | 32 px | **24 px** | 6 |
| outboard, 4 px | 40 px | **32 px** | **2** |

**It costs two characters where the inboard version cost six.** A jamb that
lives in the wall is the same picture on every row and in every door state, so
it needs no header twin, no sill twin, and no left/right pair per state —
`ECARL`, `ECARR`, `ECARLT`, `ECARRT`, `ECARLS` and `ECARRS` are all gone, with
their six `CONST CH_*` and both of `car_cell`'s column special-cases. The
character table went 87 → 83 and the fixed area gained 126 bytes.

**And the frame is static now.** Being part of the wall rather than part of the
car, it is drawn once by the template and never touched at run time. The old
jambs only existed in the OPEN state — shut and half-open, those columns were
plain grey door — so the frame literally appeared as the doors parted. A door
frame should not do that.

The threshold still spans the **opening only**. It is the plate between the
jambs, and the jambs stand on the floor beside it, which is where a door post
goes.

### 0d-quater. A sunset behind a grey city, and a per-scan-line gradient

The roof band was cyan sky over a red-brick skyline with lit windows, a white
line along the top of the deck and green under it. It is now **grey buildings
against a sunset**:

| roof band scan lines | |
|---|---|
| 8–11 | light blue — the sky above every building |
| 12–19 | magenta |
| 20–23 | red |
| 24–27 | light red |
| 28–31 | yellow |
| 32–39 | the solid wall of grey buildings that closes the band |
| 40–41 | **black** deck line (was white) |
| 42–44 | grey deck |
| 45–47 | **black** under the deck (was the shop's green) |

**A VERTICAL GRADIENT IS FREE ON THIS HARDWARE, AND THAT IS NOT A COINCIDENCE.**
The TMS9918 colours an 8×1 scan line at a time — the constraint that costs us a
colour everywhere else (§0d) is exactly the shape of a gradient. `SKYGRAD` in
`genart.py` is one entry per scan line and the whole sunset is a table.

**What it costs is ROW VARIANTS, because a character does not know where it is
placed.** A gradient that changes down the screen cannot be a single shared
cell, so the sky and the two partial-building cells come in one variant per
roof row: `SKY0/1/2` and `BLDGM0/1`. `BLDGL` and `BLDGH` are row 2 only and
`BLDGW` is solid building, so those need no twin — five characters became
eight, and the table went 80 → 85.

**The windows stay lit yellow.** Grey buildings with dark windows read as a
wall rather than as a city, and the yellow is the only thing left saying these
are buildings at all once the red went.

`ROOFAIR_BG`, the backdrop the escalator composites use where the flight
crosses the skyline's solid row, follows `BLDG_BODY` rather than carrying its
own copy of the colour — it existed so the flight would not cut a hole in the
city, and it has to keep meaning that after a repaint.

---

### 0d-quinquies. The door animation, not just the door

Widening the opening (§0d-ter) fixed the wrong number. The **fully open** state
is what that changed, and the part the player actually watches is the frame
**between** shut and open -- which was still a pair of four-pixel slits drawn as
their own cells (`EDHALF` and its header and sill twins). Eight pixels of car
out of a thirty-two pixel opening: the doors barely appeared to move.

Part-open is now simply **the car seen through the middle two columns**, which
is only expressible because the jambs left the doorway and freed all four:

```
shut  ....########################################....   car =  0 px
part  ....############CCCCCCCCCCCCCCCC############....   car = 16 px
open  ....####CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC####....   car = 32 px
```

Double what it was, symmetric, and it **reuses the car own cells** rather than
needing three of its own -- `EDHALF`, `EDHALFT` and `EDHALFS` are gone with
their constants, so the character table went 83 -> 80 before the roof work put
five back.

The lesson is one this file keeps relearning from a different direction:
*"make the opening wider"* and *"make the opening ANIMATION wider"* are
different requests, and the first was the one that got implemented. The
measurement that would have caught it is the same one that fixed it -- print
every state of the animation side by side, not just the extreme.

---

### 0d-sexies. The score line, the gradient, and a lift that takes its time

**The HUD moved two columns in from the left** — it ran hard against the screen
edge, which a real set's overscan eats. `SCORE` to column 2, its digits to 8,
`TIME` to 16, its digits to 21.

**The reserve-Kop hats moved ONE column, not two, and lost a slot.** The row
ends at column 31: six hats from column 27 would wrap onto row 1, which is
precisely the failure `checklayout.py` exists to catch. Five is what fits, so a
game set to more than six Kops shows five hats and the rest are implied.

**AND THE HATS WERE ON THE WRONG GROUND.** `KOPIC` was `BLACK` on `CYAN`, left
from when the whole font was, so once the score line went dark blue each hat
carried a cyan box around it. It is `HUD_BG` now — a *named* colour, because the
HUD's ground is a role shared by the font colour table and by anything else
drawn up there, and the two must not drift apart.

**The gradient is six even bands of four scan lines.** Dark blue reaches half a
character below the score line so the HUD does not stop at a hard edge, and
light blue drops into the top half of what magenta had:

```
DBLUE 4   LBLUE 4   MAGENTA 4   MRED 4   LRED 4   DYELL 4
```

It was `LBLUE 4, MAGENTA 8, MRED 4, LRED 4, DYELL 4` — one band twice the height
of its neighbours, which is what made it read as a stripe rather than as a fade.

**ONLY THE TOP OF THE SKYLINE GOES UP, AND THAT IS A CONSTRAINT RATHER THAN A
PREFERENCE.** The gradient's bottom band -- the yellow -- lives on band lines
20-23, and roof row 3 is solid building from line 24 down, so a column shows
yellow only if its building is SHORTER than twelve pixels. Raising every step by
four (`8 11 14 20 24 28` -> `12 14 20 24 28 32`) put every column at twelve or
more and **the yellow disappeared from the sky entirely** -- reported from play
as exactly that, one build after it was added.

So the two tallest steps gain four pixels each and the three short ones are
untouched: `8 11 14 20 24 28` -> `8 11 14 20 28 32`. The tallest now fills the
whole band and meets the score line's blue; the low blocks still cut down far
enough to let the yellow through. No new characters -- the taller steps just
take a cell higher up.

**AND THE TALLEST BUILDINGS STOP A QUARTER OF A CHARACTER SHORT.** Filling the
band outright ran them into the score line, so the sky above the city was a hard
edge rather than the top of a fade and the gradient had nowhere to begin. Two
pixels of the HUD own blue on the row-0 cell (`BLDGW0`) is the whole change:
every column now shows some sky under the score line, and those two lines are
there to carry a cornice later if one is wanted.

**The window lights stayed light yellow.** Dark yellow was tried on the
reasoning that against grey buildings the light yellow is the brightest thing on
the screen; on the machine it was simply hard to see. Reverted.

**THE VICTROLA BROADCASTS: THREE WHITE MARKS, THEN FOUR.** Its sound marks were
one per top cell -- two in each phase -- and inked BLACK like the horn below
them, so a radio that is meant to be blaring looked like a radio with two
smudges over it. They are WHITE now and the phases count 3 and 4, which is what
reads as broadcasting rather than as flickering.

It cost no redraw of the horn and no extra character, and that is the
per-scan-line colour model paying off rather than luck: the marks live on rows
0-2 and the horn starts at row 3, so `[WHITE] * 3 + [BLACK] * 5` inks each half
of the cell without the two ever sharing a line. They were put on their own rows
when the victrola was first drawn, for the pulse; that is what made this a
colour change.

**THE CAR HAS A WHITE TOP EDGE, AND IT MEASURES THE OPENING.** `ECART` is the
doorway header row -- four scan lines of grey lintel, then the car below it --
so its first car line is the roof of the cage. White there separates the car
from the lintel it slides under, and because part-open uses the same cell for
the middle two columns, the highlight is exactly as wide as the part that has
opened: 16 px part-open, 32 px open. One colour byte, no new character.

**8-3-8 now starts the game rather than returning to the title.** Anyone who has
typed the code and set the number of Kops has already decided to play; bouncing
them back to press FIRE again is a second decision nobody asked for. The branch
`RETURN`s from `title_screen` the same way FIRE does, so the caller runs
`new_game` next either way.

**The lift takes two seconds between floors**, up from 0.75. `elt` counts down
by `fdv`, the FRAME delta, so `ELMOVE = 120` is real frames on both 60 Hz
targets and stays two seconds when the loop gets busy — unlike anything counted
in loop passes (§0f-bis). At 45 frames the doors barely had time to read as
opening.

**A HUD LABEL CAN BE PRINTED FROM MORE THAN ONE PLACE.** Moving `TIME` two
columns produced `TIMEME` on screen: `tick_flash` blinks the same label when the
clock runs low and had its own copy of the column. Nothing in the build could
see it — `checklayout.py` checks each write for overflow and collision, and two
writes of the same string at different columns collide with *nothing*. Grep for
the literal, not just for the routine that owns it.

### 0d-septies. One box for the end of a round, and GAME OVER stacks on top of it

Losing a Kop and losing the *last* Kop used to be two unrelated presentations: a
single line of text on the playfield for the reason, then -- if that was the last
one -- a `CLS` and two words on an empty field. Clearing the screen made the end
of the game look like the end of the *program*, and the two messages never
appeared together, so the player who ran out of time on their last life was told
only one of the two things that had just happened.

Both are now one box, drawn in the middle of the store:

```
row  8   [                ]      <- only when it is the last Kop
row  9   [   GAME OVER    ]      <- only when it is the last Kop
row 10   [                ]
row 11   [  HE GOT AWAY   ]      <- the reason, always this row
row 12   [                ]
```

**THE BOX IS THE FONT'S OWN BACKGROUND.** Every font character is black on
`HUD_BG` (dark blue, §0d-sexies), so a row of *spaces* is already a solid dark
blue bar. The frame costs two strings and no new characters, and it separates
cleanly from the playfield because nothing else down there is that colour.

**Thirteen wide, which is the longest message plus one space either side.**
`HE GOT AWAY` and `THE BIPLANE` are both eleven. Every string is padded to
exactly thirteen so the edges are straight, and printing at column 10 spans
columns 10-22 -- centre 16, which is the screen's. (The old single line started
at column 11 and sat visibly right of centre.)

**The reason is always on the same row, and that is what lets one layout serve
both cases.** Losing a Kop draws the three rows around it; losing the last one
draws two *more on top*, so `GAME OVER` appears above the reason rather than
replacing it. Putting the reason on a different row per case would need
`PRINT AT` with a variable, and every other `PRINT` in the program uses a
constant.

**The reason became a CODE (`rsn`) set at the point of death and drawn later.**
It has to be *decided* in `do_death`, before `dead`/`tout` are cleared -- reading
those flags after clearing them made the biplane test dead code and every biplane
death say `TIME UP` -- but it has to be *drawn* after `GAME OVER` has had its
chance to claim the rows above. Deciding and drawing are no longer the same step.

**Order matters more than it looks:** the box is drawn, *then* the pause runs,
*then* the Kop is taken off the HUD. The pause is what makes the message
readable; drawing after it would flash the box for one frame before the screen
was rebuilt for the next round.

### 0d-decies. Duplication, found by measuring rather than by reading

Three times this game has been rescued from the 24,336-byte cap by finding two
pieces of code doing the same job -- the prize erase and the radio erase becoming
one `wipe_2x2`, the 838 page's two draw routines, the font colour fill a table
already held. Every one was found by reading, which does not scale to 4,200 lines.
So a sweep, with two new tools.

**`assets/romprofile.py`** attributes the fixed area to routines, from the xas99
listing's real addresses rather than from source lines (which would weight
comments equally with code). Each CVBasic label becomes a `cvb_NAME` in the
assembly; a routine's cost is the distance to the next one. The catch that makes
or breaks it: **a label line in the listing has no address column of its own**, so
the label has to be bound to the first emitted address that follows it, and
CVBasic's own internal labels have to be ignored or every routine is credited only
the bytes up to its first `IF`.

**`assets/romclones.py`** finds repeated statement runs -- strip comments,
normalise, index every window, extend while every occurrence still matches. It
ranks by removable bytes, and that ranking is a **reading list, not a work list**:
a short clone factored into a `GOSUB` costs the call, the return and any parameter
staging, so folding one can easily lose.

#### WHAT THE SWEEP FOUND

| | bytes |
|---|---|
| `scan_furn` drew the escalator diagonals that `scan_escs` draws a moment later | **192** |
| `floor0_colour`'s two identical eleven-statement blocks -> `f0_rows` | 96 |
| the two radar dots, thirteen statements of identical arithmetic -> `scan_dot` | 64 |
| `sold`, assigned twice and read never; three CONSTs read nowhere | 12 |

**364 bytes, and the largest was invisible.** `scan_furn` computed the escalator
diagonals and `scan_escs`, called from its last line, computed the same three rows
for the same three floors -- `scan_base`, the side lookup, the masks and
`scan_pat` are all pure functions of `fl`, and `scan_or1` is an OR, so doing it
twice cannot differ from doing it once. It is the shape a routine takes when a
feature is split out and the original is left behind: `scan_escs` is that block
plus the colour write added later, and it had inherited a copy of the explanatory
comment as well as the code.

**A screenshot could not have settled it.** The radar is three pixel rows tall and
Classic99 crops the bottom of the screen at every window size. It was proved by
replaying both versions against a model of the pattern table for all eight
escalator-side combinations -- the same discipline as §0m's "verify geometry by
sampling pixels, not by looking at a scaled screenshot".

#### WHAT THE SWEEP DID NOT TOUCH

`draw_actors` (2,012 B), `move_harry` (1,720) and `move_kelly` (1,098) are the
three largest routines and between them a fifth of the game, but the clone
detector finds almost nothing in them: their duplication is **structural, not
textual**. `move_harry` and `move_kelly` are the same algorithm over different
variables, and folding them means one routine with a subject parameter, touching
both actors' movement at once -- a change with real behavioural risk, and one that
would collide head-on with the outstanding work to pace Kelly by real time. It is
a deliberate decision to leave, not an omission.

#### AND ONE FALSE ALARM WORTH KEEPING

The sweep also reported **`tick_flash` as unreachable** -- nothing `GOSUB`s or
`GOTO`s it, and `git log -S "GOSUB tick_flash"` finds no commit that ever did. It
looked like the low-time warning had never worked.

**It works.** `tick_flash` is entered by **fall-through** from `tick_timer`, which
runs off the end of its own body into the label below it -- and says so in a
comment two lines up: *"falls through to the flash -- no GOTO, so the whole
routine stays on one traceable path."* A reachability check that models only
explicit jumps cannot see that, and reported a live feature as dead.

Deleting it would have removed a working warning and the bytes would have looked
like a win. This is the mirror of §13's "a check whose scope is narrower than the
bug reports success": here the model was narrower than the control flow, so it
reported a **failure that was not there**. Both directions cost the same amount of
trust, and a false alarm is the more dangerous one during a delete-things pass.

### 0d-nonies. The title is drawn as soon as it can be, not when everything is ready

The title took **3-4 seconds** to appear after the cart was selected, and it filled
in visibly rather than arriving. Neither cause was the drawing: `CLS` compiles to a
single hardware `FILVRM` of 768 bytes with interrupts off, and `DEFINE CHAR` /
`DEFINE COLOR` are synchronous triple copies. It was our own boot.

**Cause one: one constant, written 1,416 times.** `font_colour` filled the font's
colour table a byte at a time -- 59 characters x 8 scan lines x 3 screen thirds --
paced by 24 `WAIT`s, because a VDP burst past a few dozen writes in one frame is
silently dropped. It is now a single `DEFINE COLOR 32,59,font_col` against a table
of 472 identical bytes.

That table looks like waste and is not. **The scarce budget is the fixed area, not
the bank**: the bytes go in the data bank, which had 860 spare, and deleting the
routine *returned* 80 bytes of fixed area. `define_color` always takes the LDIRVM3
triple-copy path (verified in the generated assembly, `bl @LDIRVM3`), which is also
why `esc_deck_col` and `floor0_colour` cannot use it -- they patch a single screen
third each.

**Cause two was the boot order, and the fix for it was later REVERTED -- see
below.** Cause one stands on its own and is where the real time went.

The reverted change interleaved the title with the setup: `setup` split into
`setup_font` and `setup_rest`, the title routine into `title_draw` and
`title_input`, and the title was drawn between them. Only the font is needed to put
text on a screen, and the store characters, colours, escalator deck, radar canvas
and sprite sets are not read until `new_game`, so nothing was out of order. It
measured **4.03 s to a settled title, now 2.62 s**, with three intermediate frames
instead of six.

**It was reverted because those 1.4 seconds were bought with a dead screen.** The
title was drawn, complete and readable, while `setup_rest` and `init_tables` ran --
and nothing was reading the keyboard during them. Section 0e-sexies has the rest.
The split routines were kept; only the order changed back:

```basic
GOSUB setup_font        ' BANK SELECT, font chars, DEFINE COLOR font
GOSUB setup_rest        ' store, deck, radar, sprites
GOSUB init_tables
boot:
GOSUB title_draw        ' <-- READABLE AND LIVE HERE
GOSUB title_input
```

**Keeping the split still pays**, because `boot` re-enters below the setup: a
second game reaches its title in one redraw instead of rebuilding a store that is
already defined.

#### AND THE ALPHA LOCK CALIBRATION WAS 40 MORE FRAMES OF IT

The 40-frame sample sat inside the title routine, and `GOTO boot` re-enters that
after every game over, so it re-ran per game. Moving it to first boot removed a
failure mode as well: the sample cannot tell a latched key from a held stick, so on
a *return* to the title a player still holding a direction had it read as a stuck
line and **disabled for the whole next game**.

**The whole routine is gone now** -- section 0e-sexies -- so this is history. It
matters only as the other two thirds of the dead-title window.

**Not changed:** `scan_colour`'s 9 waits (0.15 s, on the black screen before the
title -- collapsing it would need its 24-byte table expanded to 384 in the bank). And the custom font stays: CVBasic's runtime already loads its own
ASCII face before our code runs, so ours is not functionally required, but it is a
deliberate arcade face (`genfont.py`) and `DEFINE CHAR` is one synchronous call, so dropping
it would buy 472 bank bytes and no time at all.

### 0d-octies. The 838 page types its numbers instead of cycling to them

The setup page reached by `838` used to CYCLE each field -- `1` stepped the Kop
count, `2` stepped the start level, both wrapping at the top. Reaching level 20
took nineteen presses, and overshooting meant going round again: **the setting
that most wants reaching was the most expensive one**, which is backwards for a
page whose entire purpose is skipping ahead. Worst case was about 28 presses.

It now asks for **three digits** and is done. Kops is one digit, the level is
two, and the result is **clamped** to 1-20 rather than refused -- which is what
lets a two-digit field cover a twenty-round range with no rejection path to get
stuck in. This is Bust-A-Bobble's `setup838` (`BUSTABOB.bas:3602`), which reaches
any round in two presses; RallyX's single-digit prompt is cheaper still but caps
at 10, so it cannot express this range at all.

**One prompt at a time, and no number on screen the player did not type.**
`KOPS 1-9` appears alone; answering it brings up `LEVEL 01-20`. There is no
heading and no instructions, because a page showing exactly one question does not
need to explain that one digit answers it.

Pre-displaying the *current* values was the obvious first version and it cost far
more than it gave: two draw routines, a "fire keeps what is shown" escape to make
the display mean anything, and the defaults had to be applied on the page as well
as in `new_game` so there was something to show. Removing all of it is why the
typed page ended up **cheaper than the cycling one it replaced** -- the fixed area
went from 134 bytes free to **270**, having passed through 26 with the version
that still showed the current settings.

**Typing the last digit starts the game.** No confirm step and no way back out:
someone who has typed a Kop count and a level has already decided to play, and it
means the page is left with KEYS ALONE. Fire on the TI is TAB, which Windows may
treat as a focus change, so "do not make FIRE the only way out" applies here as
much as on the title. The clamp is what makes that safe -- no typed pair can be
refused, so there is no state to be stuck in.

#### AND `1` NO LONGER STARTS THE GAME

The title accepted `1` as well as FIRE, because TI fire is TAB and CLAUDE.md §3A
says not to make FIRE the only way out of a title screen. That is now a **named
exception**, taken on purpose.

What it buys is the cheat code. Every digit on the title now means exactly one
thing: a step of `8-3-8`, or a reset of it. While `1` also meant START, mistyping
one digit did not merely reset the sequence -- **it began a game**, which is a far
worse outcome than having to type the code again. The two hazards are not
symmetric: a stray TAB that moves the window leaves the title on screen and the
player clicks back, while a game started by accident cannot be undone at all.

The prompt says `FIRE TO START`.

#### THE CHEAT CODE WAS TYPING ITSELF INTO THE FIRST FIELD

`cont1.key` still reports the sequence's final `8` on the first pass inside
`setup838`, so the Kops field read it as the answer: **typing `8-3-8` set the Kop
count to 8** as a side effect of the cheat code, before the player had touched
anything. Waiting for the key to be RELEASED (`su_rel`) is the whole fix, and the
same wait sits before every later digit so one held key cannot answer two
questions.

#### AND THE SEQUENCE ITSELF IS NOW EDGE-TRIGGERED

`title_wait` used to read `cont1.key` raw every pass and test only for the digit
it wanted next. That worked -- but only because `8-3-8` **alternates**, so holding
`8` cannot advance past the first step. It is an accident of the sequence rather
than a design, and it had two costs: `8,5,3,9,8` opened the page as readily as
`8,3,8`, and a key that *reads* as held for many frames got a free walk through
the state machine.

That second one is not hypothetical on this machine. ALPHA LOCK shorts a keyboard
line -- and Classic99 defaults to `invertcaps`, so it reads DOWN with the host's
Caps Lock UP -- and **a cold boot with no keys pressed at all landed on the setup
page with an 8 already in the field**, reproducibly. A hidden code that opens
itself is not hidden.

The reset is the DEFAULT rather than a test for a particular wrong digit:

```basic
IF tk <> tkl THEN
    tkl = tk
    IF tk < 10 THEN            ' 15 means nothing pressed, and the edge
        tnx = 0                ' fires on RELEASE as well as on press
        IF tk = 8 THEN tnx = 1
        IF t838 = 1 THEN IF tk = 3 THEN tnx = 2
        IF t838 = 2 THEN IF tk = 8 THEN tnx = 3
        t838 = tnx
    END IF
END IF
```

Computing the next state from this state and this key is what lets the reset be
the default rather than a case. Bust-A-Bobble resets only on a stray `3` and still
lets `8,5,3,8` through; RallyX's bare `tseq = 0` before the re-arm is the strictest
of the three, and this is that.

**The `tk < 10` guard is load-bearing.** `cont1.key` returns 15 for nothing
pressed and the edge fires on release, so without it every key let go of would
reset the sequence it had just advanced.

### 0f-bis. Harry starts at the lift, and that set his speed

He used to spawn at the west edge of screen 7, chosen because it was as far
towards the lift as he could get **without taking the escape away**. He starts
at the lift itself now, and the arithmetic that made screen 7 the limit is what
decided his new speed.

His route zigzags -- east along floor 2 to its escalator, west along floor 3 to
that one, east again along the roof to the door -- so moving him west lengthens
it three times over. From screen 3 it is **5,120 px** against the 4,208 he
walked from screen 7. At his old 1.75 px a pass that is 105 s of a 100 s round:
**he could never escape at all**, and one of the two loss conditions would
quietly have stopped existing.

**2.25 px a pass is the only quarter-pixel value that works**, and the bracket
either side of it is one notch wide:

| `hsp4` | px/pass | Harry escapes at | |
|---|---|---|---|
| 8 | 2.00 | 105.0 s | never escapes |
| **9** | **2.25** | **93.7 s** | Kelly is there 9.4 s earlier |
| 10 | 2.50 | 84.6 s | Kelly 0.3 s earlier -- one hit and it is unwinnable |

At 10 the round is decided by whether Kelly is ever touched; at 8 there is no
chase. This is CLAUDE.md's warning about a quarry's speed not being a difficulty
dial, in three lines of arithmetic -- and 93.7 s of a 100 s round is as close to
"escapes as the timer expires" as quarter-pixel speeds reach.

The margin that remains is the **round's**, not the chase's: Kelly still has to
get there first, and does, by 9.4 s -- a little over one obstacle hit.
`assets/checkchase.py` walks both routes out of these constants and fails the
build on either side of the bracket.

### 0f-ter. The crook walks by real time, so the player's screen stops mattering

**The symptom.** Identical uninterrupted rounds finished differently depending on
where the player was standing:

| where the player stood | before | after |
|---|---|---|
| the lift screen | **TIME 00** -- ran out of clock | **TIME 04** |
| an escalator screen | TIME 01 | **TIME 04** |
| a light screen | TIME 09 | TIME 04 |

**The cause.** Everything that MOVES was paced per loop PASS while the CLOCK is
paced by the frame delta, in real time. A busy screen slows the loop, so the
crook covered less ground per real second and the clock did not slow with him.
Instrumented, a whole round came to **2,335 passes over ~98 s = 23.8 passes a
second** against the 25 the model assumed, and the lift and escalator screens are
slower again (20 with two flights).

**The change.** His walk accumulates once per ELAPSED FRAME rather than once per
pass, so he covers the same ground per real second wherever anybody stands. Three
details carry the whole risk:

* **The unit went to SIXTY-FOURTHS with two drains.** Per-frame accumulation puts
  his step under a pixel, so two drains are ample where the per-pass version
  needed three -- and the finer unit is what makes the speed tunable at all. In
  sixteenths one notch was about **six seconds** of his route; in sixty-fourths it
  is about one and a half.
* **The step is clamped to five frames' worth.** Two tests sample his position
  once a pass and neither interpolates: arrival is an eleven-pixel window
  (`hdx < 6`) and the catch is a 23-wide band (`hdd < CATCHR`). Five frames is
  10 px, and skipping the window needs 12. **Three was too few** -- the lift
  screen runs at almost exactly 20 passes a second, which *is* `fdv = 3`, so
  every hitch there pushed past the clamp and he lost that frame. That produced
  the intermediate reading of TIME 02 against TIME 04, which is the same bug in
  miniature.
* **The escalator ride is deliberately untouched.** It returns before the walk
  code, still one step per pass, locked to the moving staircase -- a rider
  advanced by the delta either drifts off the treads or makes the steps run
  backwards (§0f, CLAUDE.md S3A). It is ~3% of his journey.

`hanim` needed nothing: it is an odometer, advancing by pixels travelled rather
than by time, so the run cycle stays locked to the ground at any rate.

**Kelly was deliberately left per-pass**, on the reviewer's call, so on a busy
screen he is still slightly slower than the crook. Verified as acceptable by a
full chase run: the crook was caught at the top-floor escalator with 23 timer
units still on the clock.

#### EARLY IS THE SAFE SIDE TO BE WRONG ON, AND THAT SETTLES THE LAST FEW SECONDS

`checkchase.py` says he escapes at **98.5 s**; measured play says about **91**
(TIME 04 of a 50-unit, ~2 s-per-unit clock). It is consistent across runs and
across screens, so something in the model is wrong -- most likely what it charges
for the two escalator rides, or the exact point the escape triggers.

**The speed was NOT shaved to close it, and that is a decision rather than a
loose end.** THE TWO ERRORS ARE NOT SYMMETRIC. A crook who arrives a few seconds
early costs a little tension. A crook who arrives a few seconds late **never
escapes at all**, which deletes one of the two ways to lose a round and does it
silently -- the game still works, it just quietly stops being able to end that
way. Trimming six seconds to reach the buzzer, using a model that disagrees with
the machine by more than six, is a bet with that on the downside.

So TIME 04 stands: he escapes with about eight seconds in hand, from every
screen. The seven-second gap between the model and the machine is still worth
finding -- most likely what the model charges for the two escalator rides, or the
exact point the escape triggers -- but it is an accuracy problem in the checker,
not a fault in the game.

### 0p-ter. A hit clears the floor -- ALL of it -- until you re-enter the screen

Nine seconds is a heavy penalty on a fifty-unit clock, and taking it while still
standing among the things that charged it is how one mistake becomes three --
especially with a second hazard 104 px behind the first. So a hit **zeroes both of
that band's hazard slots**, whatever is in them, and they stay gone until the
screen is re-entered.

**It costs no state and no timer.** `load_band` repopulates a band from the
template, and it runs only on a seam crossing or a round start, so "until the
screen is re-entered" is already the natural lifetime of the thing being cleared.
Leave, come back, and the hazards are simply placed again.

**Radios used to be exempt, and that was the wrong conclusion from a real
problem.** They are CHARACTERS stamped into the name table rather than sprites,
so zeroing the kind stops them colliding while leaving them plainly visible on
the shelf -- and a fixture that is still there has to still be there. But that is
a reason to **undraw** them, not a reason to keep them: it left the one hazard
that *cannot leave on its own* as the only one the mercy did not cover. A cart or
a ball is already travelling and wraps away; a radio just sits there, so walking
clear of it means walking its whole width, at a walking pace, with `obht()`
expiring the moment you touch it again.

**So `haz_off` takes the characters with it.** Zeroing the kind is the whole job
for a sprite hazard, because the draw pass reads the kind and stops putting it
anywhere. For a radio, `CH_WALL` goes back over its four cells as well -- exactly
what a collected prize does, and since the counter or pillar it stood in front of
was already cleared to make room for it (`radio_band`), there is nothing
underneath to restore.

Prize and radio share one `wipe_2x2`, and that sharing is what paid for the
change: the fixed area had 174 bytes free and the first version was 50 over.

This is separate from `obht()`, which stays. That is a per-OBSTACLE refractory
that stops one object charging twice without an intervening clear frame -- it is
what makes a bouncing ball you are standing under cost nine seconds once rather
than once per bounce. The floor clear is a per-FLOOR mercy after the penalty has
already been paid; the two solve different problems and neither replaces the
other.

### 0e-quindecies. A catch through the floor

Reported from play: *"when harry is going down an escalator and I run over top
of him, even though we do not touch, it counted as catching him".*

`coll_harry` tested the same FLOOR and the horizontal distance. But `hlv` does
not change until a ride ENDS -- a crook stepping onto a flight keeps the floor he
left until he arrives at the next one -- so while he was most of a storey up or
down the stairs he still counted as standing where he started, and a Kop running
over the head of the flight arrested him through the floor.

**It is the same shape as the catch that fired at MAXIMUM separation** (0e-bis,
the `+8` that wrapped the byte): a test that is right about one axis and silent
about the other, where the silent one happens to be true nearly all the time. A
floor is a whole storey, so "same floor" reads as "same place" until something
is halfway between two of them.

The test now also requires them to be at the same HEIGHT, within a character row.

**THE ARITHMETIC IS UNSIGNED-SAFE, AND THAT IS THE ONLY SUBTLE PART.** Riding up
is above the shared floor and riding down is below it -- a signed quantity, and
CVBasic's variables are not signed. So both are collected as POSITIVE heights on
opposite sides: Kelly's climb plus Harry's descent on one side, Harry's climb on
the other, and the difference is taken between two numbers that cannot go
negative. Two riders passing on the same flight then measure the SUM of their
heights, which is exactly the distance between them.

Checked against the true signed separation over every combination of ride state
and height -- **zero mismatches** -- and the reported case stops catching once
Harry is eight pixels down the flight.

### 0e-quaterdecies. The title card: kerned words, a marquee ring, and a chase

The first marquee was three passes from right, and every wrong turn was a
different lesson.

#### THE NAME IS DRAWN AS WORDS, NOT LETTERS

Giving every letter its own 2x2 block of characters puts every letter on an
8-pixel boundary. That is a grid, not typesetting: the spacing cannot vary,
nothing can tuck under anything, and it reads as separate stamps. The reference
is KERNED -- fitted together and drawn as one image.

So `titleword.py` composites the letters into a WORD bitmap at a 12-pixel
advance and only then slices it on the character grid. A cell may hold parts of
two letters; that is the point.

**THE BUDGET CHOSE THE WIDTH, not taste.** The character table has 63 codes
free (font 32..90, store art 96..184, radar canvas 208..255). Three cells tall
is what the name needs to look like a sign, and at a 13-pixel advance the two
words want 69 cells -- it does not fit at any price short of moving the store
art to another bank. At 12 it is 63 exactly, and deduping brings it to **44
distinct cells**: blank cells use the space character and eleven cells repeat
between the two words. Condensed is not a compromise; the reference's own face
is tall and narrow.

**ONE CAP HEIGHT, ASSERTED.** The first face ran from eleven rows to thirteen
with tops and bottoms on different lines, which reads as letters sitting at
different depths -- obvious on screen, invisible in the source.
`check_heights()` requires every letter to occupy rows 2..21, and it caught `O`
and `S` short on BOTH passes of the redraw. The round letters are the ones that
drift: a flat-topped letter's extent is obvious from its first row, a bowl's
depends on how many rows the curve takes.

#### THE MARQUEE IS ONE CONTINUOUS RING

Laying out four sides independently is the wrong shape of solution. It gives a
four-lamp run at one corner and a double gap at another, and no amount of
adjusting the ends fixes both. Walking the PERIMETER and lighting `i mod 4 < 3`
makes the corners fall out of the rhythm the way a real marquee's do.

**That constrains the frame's size.** A perimeter that is not a multiple of four
has a seam where the pattern restarts. Rows 1..21 by columns 2..28 gives **92 --
23 clusters exactly** -- and still keeps two columns clear on the left, three on
the right and two rows at the bottom, so nothing is lost to a real set's
overscan. `frame_runs` refuses a frame that does not close and says which way to
change it.

Three earlier attempts at the rhythm, each wrong in its own way and worth
keeping because none is obviously wrong on paper:

* **Repeating `###.`** leaves whatever the width gives at the right-hand end --
  a two-bulb stub.
* **Mirroring a repeated half** fixes the ends and butts two clusters together
  at the seam: a seven-bulb run through the middle of the top row. Symmetric,
  and plainly wrong.
* **Spreading a fixed number of clusters and pushing the remainder into the
  gaps** gives gaps of two and three -- even, symmetric, and not a marquee.

#### THE CHASE COSTS NO NAME-TABLE WRITES

Every cell of the frame is a bulb CHARACTER, including the dark ones. A space
would be cheaper in the table and would make the animation impossible: a cell
that is a space can never light up.

Each cell carries its phase 0..3 by position round the ring, and each phase has
its own character code. The chase then works by **redefining which of the four
patterns is blank** -- the dark cell travels all the way round the sign without
a single byte of the name table changing. At any moment exactly one lamp is
blank, so a step lights the one that was and blanks the next: **two
`DEFINE CHAR`s per step**, against ninety-two pokes. Six frames a step, about
ten a second.

**AND THE CHARACTER NUMBER IS ARITHMETIC, NOT A BRANCH.** The first version
dispatched on the phase -- four `IF`s, eight `DEFINE CHAR`s -- and cost about
**three hundred bytes** for that picture. `DEFINE CHAR` takes an EXPRESSION for
the character number, so `CH_BULB0 + bphs` collapses the whole thing to two
calls and no ladder: 478 bytes free where there had been 266. A four-way branch
over consecutive things is nearly always arithmetic wearing a disguise.

**TWO CALLS, NOT FIVE.** Lighting all four and then darkening one is the same
result and reads more simply, but two separate `DEFINE`s can have a vblank
between them -- the sign would show every lamp lit for one frame per step, a
flash rather than a chase. Changing only the two lamps that actually change
cannot do that, and the capture confirms it: the lit count holds at 47-48 across
frames instead of spiking.

**ONE INITIALISATION HAS TO AGREE WITH THE ART.** genart ships BULB0..2 lit and
BULB3 blank, so `bphs` starts at 3. Left at 0 the first step would light a lamp
that is already lit and darken a second, and the sign would lose a lamp on every
pass round. Nothing else needs resetting: every rotation is a valid
three-and-one, so a title reached after a game over carries on from wherever the
last chase stopped.

**IT NEARLY DIED IN THE ART GENERATOR.** `genart` merges characters with
identical patterns to save codes, which is right almost always -- and it
collapsed `BULB0`, `BULB1` and `BULB2` into one code, because all three ship
with the same lit picture and differ only once the chase starts rotating them.
Three quarters of the sign would have blinked together and the chase would have
been a flash. There was already an exemption for animated escalator cells for
exactly this reason ("two flight cells can look identical while the steps are at
rest"); the bulbs joined it.

**THE ANIMATION SITS BELOW THE INPUT READS**, deliberately. This loop's history
is input bugs -- a screen drawn but not listening, a keypress eaten by a
stability filter -- so nothing decorative goes in front of the polling. A
dropped frame of animation is invisible; a dropped keypress took three sessions
to find.

#### AND A COLLISION THE PREVIEWER COULD NOT SEE

The name's characters were first loaded as one 40-character block at 182, which
ran into the radar canvas at 208: `S` and `T` came out as the scanner's green
diagonals, on a screen with no radar on it, because the clash is in the PATTERN
table and has nothing to do with what is displayed.

`assets/prevtitle.py` **agreed with the bug** -- it painted from the generated
blocks and had the face exactly where the generator said, so it showed a perfect
title. Only the emulator disagreed. The previewer is still worth having, because
Classic99 clips the right-hand columns at every window size and a full-width
frame is precisely what a screenshot cannot verify; but it complements the
hardware rather than replacing it.

`free_codes()` now derives the free ranges from `genart` instead of a literal,
so a future character cannot quietly land on the title -- which it promptly had
to, when the four bulbs pushed the store art from 181 to 184.

### 0e-terdecies. The title gets a marquee, and it costs no code at all

After the Activision title card: a ring of lamps round the screen. The reference
is a white panel in a black surround; ours keeps the dark blue field it already
had, so the bulbs sit straight on it and the screen still has exactly one
background colour -- nothing to clash with under the TMS9918's one-pair-per-row
rule.

**It needed no new mechanism, which is the point of having done 0e-duodecies
first.** A bulb is one character and the frame is runs of characters at fixed
positions -- which is exactly what the display list already was. The whole
marquee is bank data drawn by the same `run_list` walker as the text, so the
fixed area is **unchanged at 682 free**. Bank 1 paid the 130 bytes.

That is what "the title is data" was for: this would previously have been a
negotiation with a 30-byte budget.

#### THE CLUSTERS ARE PLACED, NOT REPEATED

Three lamps, a gap, three lamps. Every-other-cell was tried first and reads as a
dotted rule rather than a marquee -- it is the grouping that says *sign*.

Getting the grouping symmetric took three attempts, and the failures are the
interesting part:

* **Repeating `###.` across the width** leaves whatever the width happens to
  give at the right-hand end -- a two-bulb stub, which reads as a mistake
  because it is asymmetric.
* **Mirroring a repeated half** fixes the ends and puts two clusters back to
  back at the seam: a **seven-bulb run through the middle of the top row**.
  Symmetric, and plainly wrong.
* **Handing the leftover cells out one gap at a time**, nearest the centre
  first, is not the same as handing them out in symmetric PAIRS. It produced
  gaps of `[2,3,3,2,2]` -- a sign that leans right.

So a fixed number of clusters is spread across the width and the remainder goes
into the gaps in symmetric pairs from the middle outwards. `bulb_row` asserts
the result is a palindrome rather than drawing a lopsided sign, and refuses a
width that cannot hold the clusters at all. Six clusters, not seven: seven in
thirty cells cannot be symmetric -- the middle one would have to start at 13.5.

**Dense top and bottom, sparse down the sides**, as the reference has it. That
is also much cheaper: a horizontal run is one entry of 30 bytes, where a
vertical one costs a three-byte entry per bulb.

#### AND A PREVIEWER, BECAUSE THE EMULATOR CANNOT SHOW THIS

Classic99 scales its window to fit and **clips the right-hand columns at every
size tried**, so the one thing a full-width frame needs checking -- that it
closes on the right, and that the pattern is symmetric -- is precisely what a
screenshot cannot show. `assets/prevtitle.py` walks `title.bas` exactly as
`run_list` does and paints it from the shipped `font.bas` and `art.bas` bytes,
so the layout can be checked at any zoom in a second.

The text moved to centre inside the frame, and `DUCK PLANES AND HIGH ONES` had
to move two columns left: at its old column its last character landed in the
frame's right-hand column. **The generator's own double-write check caught
that**, which is why the text moved rather than the frame. `checklayout.py`
imports `frame_runs()` as well as `TITLE`, so the frame is compared against the
text and against the `FIRE TO START` prompt that `title_input` still prints.

### 0e-duodecies. The screen text is data, and the code got 652 bytes back

With a second bank open (0e-undecies), the data-shaped things still living in
code could leave. The fixed area went from **30 free bytes to 682**.

**The title screen and the message boxes are display lists now.** Twelve
`PRINT AT n,"..."` in `title_draw` and seven more across `do_catch` and
`lose_kop` -- 281 characters -- became tables in a ROM bank, walked by one
routine, `run_list`. A caller sets `#tta` to a table's address and calls; nothing
in the walker knows which screen it is drawing.

The format is `row, col, length, bytes...` with 255 to end. **Row and column
rather than a 16-bit screen offset**, because reassembling one from two bytes
needs a multiply, and on the TMS9900 `MPY` clobbers r0 -- the next line that
reads the product returns the HIGH word. Five doublings have no such hazard and
are smaller.

**The real gain is not the bytes, it is what the NEXT change costs.** A better
title screen used to mean finding room in the scarcest budget in the program.
Now it is an edit to `assets/gentitle.py` and a rebuild, paid for in bank bytes.

**Each message box is a whole SCENE** -- blank bar, text, blank bar -- so a call
site is one address and one `GOSUB` instead of three `PRINT AT`s. The blank rows
repeat in every scene, which is deliberate: they cost bank bytes to save
fixed-area bytes, which is the trade the right way round.

#### THE GATE HAD TO COME WITH IT

`checklayout.py`'s entire method is parsing `PRINT AT n,"literal"` to catch a
string running past column 31 or a write landing inside another label. Moving
the text into a table would have made the title and both message boxes
**invisible** to it -- trading a build gate for bytes, which is a worse deal than
trading a diagnostic for bytes.

So it imports `gentitle.TITLE` and `gentitle.MESSAGES` instead, folds them in as
writes by `title_draw`, `do_catch` and `lose_kop`, and checks them exactly as
before. Coverage went UP: 25 strings to 32, and the title's runs are now
compared against the `FIRE TO START` prompt that `title_input` still prints on
the same screen -- two routines writing one screen, which is the case section 13
exists for. `gentitle.py` also refuses to generate a run that overflows a row,
writes a cell twice, or uses a character outside the loaded font.

**And a rotted self-test was found doing it.** `checklayout_test.py` mutates
`#psa = 6150` to prove the VPOKE-inside-a-label case fails. That address stopped
existing when the score field moved, so the mutation applied to nothing, the run
came back clean, and the case reported SETUP ERROR while the other three passed.
A self-test that rots into a no-op is worse than none. The anchor is derived from
the source now.

#### THE ROWS WERE CHECKED, NOT ASSUMED

The message boxes are at rows 10-12 and `GAME OVER` two rows above at 8-9 --
read back out of the original `PRINT AT` offsets (330, 362, 394; 266, 298) and
verified by printing the reconstructed offsets before building. The first draft
had them a row low and two rows apart, and nothing in the build would have said
so: a message box in the wrong place is not an error, it is a layout choice.

#### HARRY'S TWO RIDES WERE THE SAME CODE TWICE

Riding up and riding down were identical statements over identical variables,
differing only in the sign of the horizontal step and the direction of the level
change -- which is what "the same staircase from the other end" means
arithmetically. One negation is now the whole difference. **62 bytes**, and
`checkride.py` and `checkchase.py` still pass.

Kelly's third copy is deliberately NOT folded in. It uses a different variable
set, so a three-way fold needs seven values staged at three call sites, which is
the case where folding LOSES.

#### AND THE DETECTOR THAT COULD NOT SEE ANY OF IT

`romclones.py` compared text, so the three escalator rides -- same shape, zero
matching characters -- were invisible to it for months. `-a` alpha-normalises:
lowercase identifiers (variables here; CONSTs and keywords are uppercase, so
case separates them for free) become positional placeholders. `GOSUB`/`GOTO`
targets and string literals are left alone, or every call would match every
other call and the tool would manufacture clones out of unrelated code.

Two things make its output usable rather than merely bigger:

* **Runs containing a label are dropped.** `END IF / END IF / NEXT x / RETURN /
  some_label:` has the same shape wherever one routine ends and the next
  begins, so the tool's top find was the seams between routines. Nothing can be
  factored out of a run that another routine jumps into the middle of.
* **The variable mapping is printed per copy, because the byte ranking is
  actively misleading under `-a`.** "Five distinct variables set to zero" has
  one shape, so a reset block in one routine matches an unrelated one in
  another: the tool ranked `tout/dead/caught/escapd/knock`,
  `inl/inr/inu/ind/inb`, `sot/sht/spt/swt/spz` and `swf/sfj/sfh/sfp/sfe`
  together as a 300-byte find. They are four different jobs that happen to
  rhyme. Identical name lists mean a parameterless `GOSUB` and a real saving;
  differing lists mean staging, and past about two the fold loses.

### 0e-undecies. Two data banks, and a 64 KB cart

The fixed area reached **30 free bytes of 24,336** and bank 1 reached **six of
8,192**. Both doors shut at once, which is worse than it sounds, because the two
budgets are connected: the way you make room for code is to move data-shaped
things OUT of code, and that needs somewhere to put them.

**A BIGGER CART DOES NOT ADD CODE SPACE, and it is worth knowing exactly why.**
`linkticart.py` writes precisely three loader pages of 8,112 bytes and then
`# any excess is discarded`; bank files are appended AFTER them. Those three
pages are not really cart ROM -- the startup code copies them into the 32K
expansion's RAM at `>A000-­>FFFF` and jumps there. The 24,336-byte cap is the
size of that RAM window, and a 64 KB or 512 KB cart leaves it exactly where it
is. What a bigger cart adds is BANK pages, which hold data.

So the cart went to **64 KB** (five pages round up to eight) for a second data
bank -- not to hold code, but to reopen the route by which code gets smaller.

**THE FONT IS THE TENANT, AND ITS SIZE IS NOT THE REASON.** The rule that makes
banking safe here is that there is exactly ONE bank, selected once before the
first frame and never switched: a missed `BANK SELECT` returns bytes from the
wrong page with no error at build or run time, so the safest number of switches
during play is none. Two banks threaten that rule -- unless the second one holds
something read ONCE.

The font is exactly that. Two `DEFINE`s copy it into VRAM at setup and nothing
reads `font_bits` or `font_col` again, so it can live on a page that is mapped
for the length of two statements. `setup_font` selects bank 2, loads it, and
selects bank 1 before returning; nothing switches again for the life of the
program, and every existing `VARPTR`/`PEEK` read still sees a permanently
mapped page.

It also gets back a diagnostic that was given up earlier. The font used to be
kept OUT of the banks so a bank mistake would show as *text survives, art does
not* rather than a blank screen. Now the polarity is reversed and just as loud:
select the wrong bank at setup and the title comes up in garbage, immediately.

**Result:** bank 1 has **948 bytes** free again (the font s), bank 2 has **7,204**, and the fixed area is unchanged at 26 -- the extra `BANK SELECT`
costs four bytes.

#### AND THE BANKS FINALLY HAVE A GUARD

`build-ti.sh` checked the fixed area and nothing else, so the banks -- where an
overflow is **completely silent** -- had no check at all. Nothing in
`cvbasic` -> `xas99` -> `linkticart` says a word; the excess is dropped, and
what goes missing is whatever sits nearest the end of the bank, normally a
`DATA` block. Bank 1 got to six spare bytes and had lost nothing only by luck.

`assets/bankfill.py` extracts the **last DATA block of the last INCLUDE** in
each bank -- the block an overflow eats first -- and searches for it, byte for
byte, in that bank's packed image. It also prints free space, which is the early
warning. The bank-to-file mapping is derived from the source's own
`BANK`/`INCLUDE` order rather than hardcoded, so adding a third bank cannot
leave it silently unchecked.

**`assets/bankfill_test.py` proves it rejects a truncated bank**, because a
guard that has only ever passed is not a guard. It is a fixture test rather than
an end-to-end one for a reason worth recording: the obvious test -- append a
block big enough to overflow a real bank, then build -- **does not work here**,
because `build-ti.sh`'s first step REGENERATES `art.bas`, `store.bas` and
`font.bas`. The fixture is erased by the build before the assembler sees it.
Tried; the build came back byte-identical with the probe silently gone.

### 0e-decies. Harry stands on the escalator, in a slot he gives back

He rode flights running on the spot. None of his four drawings can stand in --
all four are mid-stride and there is no passing pose with the feet together --
so standing needed its own art.

**And there was nowhere to put it.** The sprite pattern table holds SIXTY-FOUR
16x16 sprites and the game uses sixty-three. A standing Harry facing both ways
is EIGHT patterns: he is striped, so he is split across complementary sprites,
and each of body, stripe layer, leg and leg stripe needs a mirror. Eight into
one does not go, and there was no slack to find -- the only exact duplicate in
the whole table is `KLHAT`, which equals `KHAT` because a hat is symmetric, and
the next-closest mirrored pair differs by twelve pixels.

**So he borrows.** `esc_stand` copies the standing art over four slots when he
steps onto a flight and `esc_run` puts the running art back when he steps off.
A ride is rare and long -- a few seconds, a handful of times a round -- so two
block copies are free, where four permanent slots do not exist at any price.

Two things make it fit:

* **Only one facing is live at a time.** He is riding in one direction, so only
  that mirror needs to be resident. The target is the same four slots whichever
  way he rides; the borrowed slot carries whichever mirror the ride needs, and
  `draw_harry` points at it AFTER the facing has been applied, because the art
  already carries it.
* **The borrowed slots are ADJACENT**, so a swap is one `DEFINE SPRITE` and not
  four. The loan is his own four right-facing running bodies, sprites 18-21 --
  the one run of the table guaranteed idle exactly when it is needed, since
  while he stands none of his running bodies is drawn and nothing else in the
  game touches them. A sprite can be pointed at any pattern, so the borrowed
  slots need not hold the kind of thing they normally hold: standing body,
  stripes, leg and leg stripe go into 18, 19, 20, 21 in that order.

  **This is not a tidiness point, it is the whole feasibility.** Borrowing the
  four slots that normally hold those four kinds meant twelve DEFINE SPRITEs
  across the three call sites, which came to **132 bytes MORE than the fixed
  area had**. The adjacent version fits with 30 bytes to spare.

**The run art has to be put back from somewhere**, and it cannot be read out of
the middle of `spr_harry` -- `DEFINE SPRITE` takes a label, not an offset into
one. So the four running bodies appear a second time under their own label, in
the DATA BANK, which is the budget with room in it.

`esc_run` is also called from `start_krook`, because a round can end while he
is still on a flight and a borrowed slot nobody gave back would put a standing
Harry into the middle of the next round s run cycle. Same shape as `snd_off`:
the routine that undoes a thing has to run on every path out, not just the tidy
one.

**`checkchars.py` verifies the loan** rather than being told to ignore it. The
`P_HST*` constants are aliases for another sprite s pattern number, so the gate
checks each against the sprite it borrows -- which is exactly the number a
renumber would move out from under `esc_stand`, and the symptom would be a
standing pose appearing in the middle of the run cycle rather than any error.

### 0e-nonies. A jump could go through an escalator

Reported from play as *"I was able to jump through the escalator to the floor.
This is rare."* Rare was the tell: it needs a particular launch point, not a
particular input.

**A flight is a diagonal and the apex is 14 px.** In `esw` -- distance along the
flight from its head -- the bottom tread sits at height 4, and every 8 px
further along the floor the surface steps up another 4. So an arc launched near
the foot and heading up-flight clears treads 4, 8 and 12, and then meets the
riser of the fourth at **16, which is above the apex and cannot be cleared**. It
went from above the staircase to below it, which in a side view is straight
through, and landed on the floor underneath.

`try_esc` could not catch it for two reasons that are each correct about the
ordinary case:

* its jump branch only looked at `esw` 52..76 -- the three treads a 14 px apex
  can land ON. Nothing was watching further up the flight, because nothing could
  land there.
* it required the arc to be **descending**. A riser is hit while still *rising*.

**The fix is a surface and a latch.** The ladder now runs the whole flight, and
the descending test is replaced by `esyp` -- "has he been above the staircase
during this jump". Landing is then *at or below the surface, having been above
it*, which covers both falling onto a tread and running into a riser. Its
complement is the floor **underneath** the flight, which is walkable and always
was: a jump taken under the stairs never gets above the surface, so `esyp` stays
0 and it is left alone.

**Descent was never the point** -- having been outside the staircase was. The old
test was a proxy that happened to agree with the right rule everywhere except
here.

#### THE SWEEP, AND WHY IT EXECUTES THE RULE RATHER THAN COPYING IT

`assets/checkjump.py` simulates **108,000 arcs**: every launch x on the screen
carrying each flight, both flights, all four animation phases, all five frame
deltas the pacer can produce, three jump directions and four accumulator
phases. It fails on any arc that is strictly above the surface on one pass and
strictly below it on the next without boarding.

Two things about its construction are the transferable part:

* **The staircase is modelled here; the boarding rule is executed from the
  source.** The surface comes from `ESCRISE` and the step pitch -- ground truth,
  and deliberately not read from `try_esc`, because `try_esc` is what is on
  trial. The rule itself is parsed out of the `.bas` and interpreted, so it
  cannot drift away from the game the way a re-typed copy would.
* **An unrecognised statement is a hard error, not a skip.** When the fix
  introduced a block `IF`, the interpreter stopped and said so rather than
  quietly ignoring two lines -- which would have left it passing everything.
  That is the same failure the extractor then had: it stopped at the first
  `END IF`, which now belonged to the inner block, and silently truncated the
  rule to its first two statements.

`assets/checkjump_test.py` types out the rule that shipped the bug and asserts
the sweep rejects it (2,352 of 108,000 arcs), then asserts the current rule
passes. Without it the sweep's clean run would only prove it cannot see.

### 0e-octies. The lift keeps its place between rounds

`elvl`, `elst`, `elt` and `eldn` were set in `start_krook`, which runs at the top
of every round **and** every life -- so the car snapped back to floor 1 with its
doors just opening whenever anything ended. A fixture of the store teleporting
because a Krook got away.

It also made the cycle predictable in a way it is not meant to be: the player
learned one arrival time and it was right at the start of every round. The lift
now initialises once in `new_game` and runs across round boundaries -- wherever
it was when the Krook was caught is where it is when the next one starts.

### 0e-septies. A hit stops the store, and nothing else

Nine seconds is the heaviest thing that happens in this game and it used to
happen in motion: the number changed, Kelly flashed, and everything carried on.
The penalty read as bookkeeping rather than as an event, and the flash had to do
all the work of saying so.

**The store now holds still for exactly as long as the hit sounds.** `do_hit`
sets `hfz`, and while it is non-zero the main loop skips `read_input`,
`radio_tick`, `move_kelly`, `upd_elev`, `upd_obst`, `coll_obst` and
`coll_prize`. The obstacle that hit him stays on screen, stopped, next to a
flashing Kop.

**What keeps running is the point of it.**

| runs during the freeze | why |
|---|---|
| `move_harry` | he is still escaping -- the freeze is a cost, not a rest |
| `tick_timer` | the clock is the real enemy; stopping it would refund the penalty |
| `scan_tick` | the radar tracks Harry, so it tracks what is still moving |
| `esc_tick` | Harry rides the escalator on the animation's clock |
| `coll_harry` | a Harry who runs into a stunned Kop is still caught |
| `draw_actors`, `sfx_tick` | the freeze has to be visible and audible |

`esc_tick` is the one that could look misplaced. It is scenery, but it is also
Harry's clock: CLAUDE.md's rule is that a rider and its cyclic animation share
one clock or the rider drifts off it, so freezing the steps under a moving Harry
would slide him up a stationary staircase. Nothing that IS frozen has a rider --
Kelly cannot be hit on an escalator or in the lift, because obstacles live on
floor bands.

**The freeze length is the sound length, by name.** `CONST HITSND = 20` passes
sets both `sht` and (plus one) `hfz`. The extra pass is because `sfh` is a latch
`sfx_tick` consumes on the *following* pass, so the note runs passes 2..21 of a
21-pass freeze and the two end together. Two counters that must agree should not
be two literals.

**And the floor clear moved to the END of the freeze.** `haz_gone` used to run
inside `do_hit`, which wiped the hazards out from under a player who was still
being told they had been hit -- the thing that hit them vanished before the sound
for it finished. It now fires on the pass `hfz` reaches zero, so the freeze shows
the collision standing still and the mercy arrives *with* the resumption instead
of in place of it.

### 0e-sexies. A title that is drawn and not listening is not up yet

The screen appeared, complete and readable, about a second before it would answer
a key. Reported three ways over as many sessions -- `8-3-8` losing its first digit,
a start press that did not take, and finally *"FIRE TO START is delayed"* -- and
diagnosed wrongly twice, first as ALPHA LOCK noise (which produced a stability
filter that ate real presses) and then as a labelling problem.

**It was the boot order**, section 0d-nonies: the title was deliberately drawn
early and `setup_rest`, `init_tables` and a 40-frame ALPHA LOCK sample all ran
after it. Nothing polled input during them.

**Both halves of the window are gone.**

*The setup moved back in front of the draw.* The title now appears later and is
live on the frame it appears. That trade is not close: a menu the player cannot act
on is not up, whatever is painted on it, and the extra second lands on a black
screen at power-on where there is nothing to act on anyway. It is also paid once --
`boot` re-enters below the setup, so a game over returns to the title in one
redraw.

*And the ALPHA LOCK guard was removed outright:*

* `CLAUDE.md` claimed every other game here avoided the problem by not reading
  up/down. **Eight of them read it** and none has a calibration or has ever shown
  the fault.
* It never fired here: the notice it prints on detecting a stuck axis has never
  appeared.
* Its original evidence -- "the title comes up and it will not start" -- is
  indistinguishable from the input bugs since found and fixed for real, and the
  first version of the guard *blocked* until the axis cleared.

It also caused two bugs: two thirds of the deaf window above, and the wrong theory
about keyboard noise that led to the stability filter. A guard that has never
caught anything, and has twice been the thing that broke, is not carrying its
weight.

**The prompt stays in `title_input`** rather than moving back into `title_draw`.
There is no gap between them to mark any more, but printing it from the routine
that does the reading keeps the two together: if anything ever slides between the
draw and the poll again, the prompt slides with it and says so.

**The general shape, worth keeping:** an optimisation that reorders work around a
user-visible moment has to account for what the program can DO at that moment, not
only what it shows. "Draw it as early as possible" measured beautifully and was
wrong, and every symptom it produced looked like an input bug rather than like the
scheduling change that caused it.

### 0e-quinquies. The HUD, the catch box, and a keypress that leaked into play

**The score drops its leading zeros.** `000050` reads as a six-digit number that
happens to be small; `50` reads as a score. All five digits may be blanked rather
than four, because `hud_score` always prints a fixed trailing zero -- so a score
of nothing still shows one `0` and the field is never empty. The clock stays
padded: a countdown is a fixed-width field you glance at, and `05` holds its
column where `5` would jump one.

The suppression is a flag on `prt_digits` so the two callers choose independently,
and it walks to "past the leading zeros" at the first significant digit -- a zero
*inside* the number still prints.

**Yes, the score is stored in tens.** `#score` counts tens and `hud_score` appends
the fixed `0`, so five stored digits display six. Worth knowing that the ceiling is
the STORAGE, not the field: `#score` is 16-bit, so it caps at 65,535 tens =
655,350 points, where the six-character field would show 999,990.

**`GOT HIM!` gets the same box as the losses.** It was one line, 12 characters, at
row 10 column 11 -- a different width in a different place from `HE GOT AWAY` and
`TIME UP!`, so the good outcome and the bad ones did not read as the same kind of
announcement, and the odd one out was the one the player earns.

#### THE FIRE THAT STARTED THE ROUND WAS ALSO A JUMP

`jrel` is the jump's release latch -- the button must come up between jumps -- and
it was never reset when play began, so it carried its value in from whatever
happened last. Press FIRE on the title with `jrel` left at 1 and Kelly jumps on
the first frame, told to do so by the keypress that only meant "start".

**It hid on the first game of a session.** CVBasic zeroes its variables and
`jrel = 0` already means "wait for a release", so it appeared only from the second
round onward -- which reads as intermittent rather than as a rule.

Clearing it in `start_krook` (the one place `new_game`, losing a life and advancing
a Krook all pass through) was the obvious fix and **was not sufficient in play**,
twice. Rather than keep reasoning about the ordering of two latches, the boot now
waits for the button itself to be released before `new_game` -- the key that said
"start" is not down when the loop begins.

**Capped at one second**, and that cap is the point. A stuck or shorted fire line
would otherwise hang the game on a black screen for ever, which is exactly the
mistake the ALPHA LOCK check made in its first version: refusing to start until a
condition cleared that never would.

### 0e-quater. Four things found by playing it

**Kelly starts mid-screen.** He was at x 224 against the east wall at 232, so a
quarter of the screen behind him was wall he could never use and the round opened
with him pinned rather than placed. 120 is the middle of the walkable range
(`XWALW` 8 to `XWALL` 232). It shortens his first traverse by ~100 px and the
chase margin went 17.3 s -> 18.3 s.

**The low-time warning is silent, and the number flashes with the label.** There
was a beep a second under ten, and the last ten seconds are the busiest part of a
round -- a repeating tone arrives exactly when the player most needs to hear the
hazards, and it was competing with the prize arpeggio for channel 2. Blinking the
word alone left the digits steady, so the thing actually running out was the one
part of the HUD not asking to be looked at.

Two writes rather than one blank spanning both, because the label is columns
16-19 and the number 21-22 and a single string across them overlaps what
`hud_time` writes. `checklayout.py` caught that and was right to; the collision is
the mechanism here, so it now carries a **named exemption** that still reports the
pair on every build. Relaxing the rule instead would have blinded it to every
other overlap at the same moment.

**AND THE TWO HALVES GOT OUT OF STEP.** Reported as the game ending on `00` with
no `TIME` beside it. `tick_timer` calls `hud_time` on **every** tick, and a tick
can land in a blank phase -- so the digits were repainted on their own while the
word stayed blank. The round then ended and froze the field half-drawn.

`tflon` was already the answer and was being read as the wrong question. It is not
"is the flash on", it is **"is the TIME field currently drawn"** -- so `hud_time`
now honours it and returns without writing while the field is blanked. Nothing is
lost: the next on-phase calls `time_show`, which comes straight back to
`hud_time` and draws whatever the value is by then.

`time_show` is the one routine that puts the field back up, word and digits
together, and the restore that used to be inlined in `tick_flash` is now a call to
it. `bonus_count` and `lose_kop` call it too: a round can end on any phase of the
flash, and a tally counting into a blanked field would draw nothing at all.

**The general shape: two things drawn as one field need one flag that owns
whether the field is up.** Every caller of `hud_time` wants the current value and
none of them knows about the flash; asking each of them to check would be the
same hand-kept enumeration that made `snd_off` go stale.

**The first step off the mark is always heard.** `sfw` is a distance -- a step
every fifteen pixels -- so a short tap moved Kelly a few pixels and made no sound
at all. That does not read as a short step, it reads as the controls being
ignored, and it is worst where a player taps rather than holds: lining up a jump,
edging round a hazard. Priming the accumulator to the threshold on the
standing-to-moving transition fires the next pass. It does not cheat the rate,
because the trigger subtracts the threshold rather than zeroing and the pixels
actually travelled still carry.

#### THE LIFT FLICKER WAS AN ISR RACE, NOT A DRAWING BUG

Riding with the doors shut, Kelly flickered at the floor he had just left. He was
being drawn at his old position and hidden a few lines later, both in the same
pass -- and that is not free. `SPRITE` writes a RAM mirror which the vblank ISR
copies to VRAM, so **a vblank landing between the draw and the hide latches the
visible state for a frame**. `draw_actors` is long (Kelly, Harry, eight
obstacles) and a pass on the lift screen spans two or three frames, so it happened
constantly.

Deciding *before* drawing costs one test and cannot race the ISR at all: the
mirror never holds a position to be caught with. **Hide-after-draw is a bug
whenever the routine can span a vblank**, which on this machine is most of them.

### 0e-ter. The run and the jump, measured instead of invented

Both effects were hand-picked divisors that had never been compared with
anything. They are now `testsounds` variant A -- measured off an Atari 2600
recording (`games/testsounds/assets/sfxref.md` has the method and the workings).

**The footstep is NOISE, on the noise channel.** It was two alternating tones on
channel 0. The recording says a footstep is a short burst of white noise, and
channel 3 was sitting unused while the footsteps and the jump sweep shared
channel 0 and had to take turns. Register 4 (white, fastest rate) at volume 12 --
against the old 7, because noise reads quieter than a tone at the same level.

**Six a second, not fifteen.** `sfw` counts pixels travelled and fired a step
every 7 px. At 104 px/s that is about **fifteen a second**, which is a machine gun
rather than a run. The 2600 plays one every **165 ms**, so at our speed that is
every 17 px -- `sfw > 16`.

**The jump is a warble, not a sweep.** It was a rising sweep, divisor 500 down to
120 in steps of 40. Invented rather than measured, and the wrong *shape*: a sweep
reads as something departing, which is a reasonable idea and not what the original
does. The recording shows about **415 Hz alternating with 188** for roughly 280 ms
-- eight ticks alternating between divisors 270 and 595, which is four cycles.

**It cost nothing and freed a channel.** The fixed area went from 588 bytes free
to 628: the toggle and the sweep arithmetic that came out were larger than what
replaced them. Channel 0 now carries only the jump, and the noise channel is in
use for the first time.

#### snd_off WAS A HAND-WRITTEN LIST, AND IT WENT STALE TWICE

Two sounds outlived their round, both reported from play in one sitting:

* **White noise that would not stop.** A footstep still ringing when Harry was
  caught hissed through the whole bonus tally and beyond. `snd_off` silenced
  channels 0, 1 and 2 -- it was written when the footstep was a pair of tones on
  channel 0, and never learned that the footstep had moved to the **noise**
  channel. Zeroing `sot` does not help: a decay counter emits its note-off on the
  pass it reaches zero, so assigning zero by hand skips the very write that would
  have stopped the sound.
* **A ding over a freshly drawn level.** The prize arpeggio's counter `spz` was
  added after the list and never joined it, so a prize collected late in a round
  played its remaining notes on the first pass of the next one.

Both are the same defect: a routine whose correctness depends on a hand-kept
enumeration of everything another routine can start. Nothing in `snd_off` says
what the complete set is, so it looks finished in every state.

**`assets/checksound.py` derives the set from `sfx_tick` instead.** Every channel
`sfx_tick` writes must appear in `snd_off` as an explicit `SOUND n,0,0`, and
every variable `sfx_tick` tests in an `IF` -- the latches and the decay counters,
exactly the state that can make a sound on a later pass -- must be zeroed there.
Keeping a second list inside the checker would have gone stale the same way. Run
against the defective source first, it named both faults and a third (`swf`, the
warble's phase) before either had been fixed by hand.

#### THE BONUS TALLY IS A BLIP THAT COUNTS, NOT A BUZZ THAT RATCHETS

`testsounds` **TALLY B**, chosen off the bench against the measured 2600 tick (A)
and an accelerating variant (C). The measurement says the original's tally is
*noise* -- and noise is what it stayed until ten of them were played in a row,
which is the only way a tally can be judged. A run of noise bursts ratchets; it
sounds like a mechanism being wound rather than like something being counted.

**One blip per timer unit, 1,036 Hz, two frames on and two off.** It was 373 Hz
for three frames on and two off. Two things changed and both matter over a run:

* **The pitch separates it from the clock.** 373 Hz sits in the same register as
  the timer's own low tick, so the count read as more of the thing that had just
  run out. A fourth above it reads as arithmetic.
* **The shorter gap makes ten of them a phrase.** At five frames a unit a
  fifty-unit capture is four seconds of evenly spaced beeps, which is a queue.
  Four frames is quick enough that the run has a shape.

**AND IT ENDS ON ITS LAST BLIP** -- the bench carries this as **TALLY H**, which
is B with the final step deleted and nothing put in its place. There is no closing
accent, and getting to
that took two rejected attempts and one wrong diagnosis.

The reasoning for an accent is sound on paper: ten identical blips that simply
stop leave the player waiting for an eleventh, so the count should resolve. The
bench's own ending for B rose a fourth, to 2,542 Hz, and was rejected as a shriek
-- the same fault the pickup was rewritten for. **The diagnosis was the pitch**,
so it was moved an OCTAVE BELOW the ticks, to 518 Hz.

**That was rejected in exactly the same words**, and it cannot be too high by any
measure: 518 Hz is the lowest note anywhere in the effect. The report that settled
it was *"if it plays over and over it's fine, but as it finishes there's that
sound"* -- the objection was never to a frequency, it was to **there being an
extra note at all**.

A tally is arithmetic, and arithmetic finishes when the last term is added. A
flourish after it is a second event the player has to interpret, arriving exactly
when there is nothing left to say -- and the HUD has already shown the clock
empty. The count stops when the counting stops.

**The transferable part is the diagnosis, not the note.** A complaint that names a
property ("it's high pitched") is a description of the symptom, and the obvious
reading -- change that property -- was tried and failed. Moving the note to the
opposite extreme and getting the identical complaint is what proved the property
was not the subject. If a fix that inverts the named cause changes nothing, the
named cause was not the cause.

**Channel 2 stays**, though the bench plays B on channel 0. The effect table uses
channel 2 for the upper voice of a two-note effect, so a tick here cannot cancel a
sustained tone on channel 1 (CLAUDE.md §3A: two `SOUND`s on one channel back to
back just cancel the first). The bench has nothing else running and can use
whatever channel it likes -- **a variant's channel is a property of the bench, not
of the sound**, and porting one across means keeping the game's own allocation.

**The bench's divisor byte is multiplied by four** before it reaches `SOUND`
(`play_fx` doubles it twice, because a plain CVBasic variable is 8-bit and a real
divisor does not fit). So B's `27` is divisor **108** and its accent's `11` is
**44**. Reading the table as literal divisors would have transposed the whole
effect four octaves up.

#### THE ANALYSIS GOT ITS OWN FIRST PASS WRONG, WHICH IS THE TRANSFERABLE PART

Autocorrelation reported **every** effect as noise. The running sound plays
underneath all of them, and its hiss drags the confidence of a pitch estimate
below any sensible threshold -- so a clean tone with footsteps over it scores 0.4
and gets filed as noise. Only the running and the tally ticks actually are.

That hid the most important distinction in the set: **the pickup rises and the hit
falls**. Filed as "both noise, both about 660 ms" they were the same sound, when
they are the difference between a reward and a penalty. Measuring energy at fixed
frequencies (Goertzel) rather than periodicity does not have this problem -- it
says where the energy *is*, so a sweep shows as the peak walking up the column.

**Classify with a spectrogram; only measure pitch on something already known to be
tonal.** And what transfers from a different sound chip is the *shape* -- rising
against falling, warble against steady, and the durations -- not the timbre.

### 0e-bis. The radio, redrawn as openwork

The radio's body was three **wide** green slots under a solid arch, which at
sixteen pixels reads as a doorway or a bookcase rather than the front of a
wireless. It is now openwork throughout: a latticed arch over a cabinet with a
centre channel and two wide feet.

**Three of my drafts were rejected before the reviewer drew it, and the failures
are the useful part:**

* **An even lattice of 2×2 holes** fixed the texture and lost the object. An even
  field of holes is a *pattern*, and the cabinet vanished into it — reported as
  *"basically just checkmarks"*.
* **The same lattice broken by a cross-bar** did not help, because **a hole two
  pixels tall has no direction**. Still a checkerboard, just a stripier one.
* **One-pixel slats, five tall**, did read as a grille — direction is what says
  "slats in a cabinet" rather than "tiling" — but the verdict was that it had
  gone too far the other way. The answer was not a finer grille; it was to open
  up the arch as well, so the whole object is one idea instead of a solid top on
  a perforated bottom.

The shipped drawing is the reviewer's, kept in `assets/radio4.txt` alongside the
three drafts it replaced (`radio1-3.txt`) in an editable 16×16 form.

#### ROW 7 BELONGS TO FOUR CHARACTERS, NOT TWO

The broadcast marks animate between two poses, `RADTL0`/`RADTR0` and
`RADTL1`/`RADTR1`, and **only rows 0–2 may differ between them**. Everything below
is the same cabinet drawn twice. Opening the crown's base (row 7) meant changing
it in all four, and getting that wrong does not look like a drawing mistake — the
whole shoulder pulses in time with the dots, which reads as the radio strobing
rather than transmitting.

The same is true of rows 4–6, which the openwork arch also changed. Any edit below
row 2 has to be made twice; the check is to render both frames and compare.

**Only black and the floor.** Two colours per scan line is the entire budget, so
`#` is the cabinet and `.` is the shop floor seen through it — the holes are not a
colour of their own, they are the room behind. A lighter green for the holes was
tried and rejected: the radio is a black object, and lighting them makes it a
different one.

### 0f-quater. Everything that moves now moves by elapsed frames

Harry went to real-time pacing first (§0f-ter) and Kelly and the hazards were
left per-pass, deliberately. Reading them to finish the job turned up **two live
mismatches**, so this was a correctness fix rather than a tidy-up:

* **Kelly's legs already ran on the frame delta while his body did not.**
  `kanim = kanim + fdv` against `klx ± WALKSP` once per pass, so his stride
  slipped against the ground whenever the loop was busy. The first fix had moved
  `kanim` from passes to the frame delta, which traded one mismatch for another.
  It is an **odometer** now -- `kanim = kanim + kspd`, pixels travelled, exactly
  like Harry's `hanim`.
* **The jump was frame-paced and the ball's bounce was pass-paced.**
  `kjf = kjf + fdv` against `obp + 1` per pass. So whether a jump cleared a ball
  depended on how busy the screen was, and the frame-by-frame property
  `checkball.py` proves was exact only at `fdv = 1`.

**One shared `pace_step`** now serves Harry, Kelly, each hazard kind and the
bounce phase: `pacc` in and out, `psp64` in (sixty-fourths of a pixel per frame),
`pspd` out. Harry had the only copy; folding his into it returned about 180 bytes
and is most of what the rest cost.

**Constants, all in sixty-fourths per frame:** Kelly `KWALK64 = 111`, hazards 51
and 76 (were 2 and 3 px/pass), bounce `BOUNCE64 = 25`.

#### CONVERTING A PER-PASS SPEED, USE THE BEST CASE AND NOT THE AVERAGE

`KWALK64` was 102 first, which is 4 px/pass at the measured average of 23.8
passes/s = 95.6 px/s. The average is the wrong statistic. What Kelly actually did
depended on the screen:

| screen | passes/s | old speed | now |
|---|---|---|---|
| light | 26 | **104 px/s** | 104 |
| lift / escalator | 20 | 80 px/s | 104 |

**A chase spends most of its time on light screens**, so matching the average cost
him 8% exactly where it is decided -- and the crook was already per-frame, so he
did not change and the ratio quietly dropped. Played, it read as only just
catching him on the last screen, where the chase used to end around TIME 23.

111/64 is 104.1 px/s: his best case, made constant. He is now **at least as fast
as he ever was on any screen** rather than faster on some and slower on others,
and the modelled margin goes 10.6 s -> 17.3 s (the old, pre-conversion model
claimed 14.2). The corollary is general: converting a per-pass speed to real time
is not a neutral re-expression unless the loop rate is constant, and it never is.

Raising it further is available and was not taken -- 115 gives 20.0 s and 120 gives
23.1 s, both faster than the player has ever moved, which changes the feel of
running rather than restoring it. It also shortens hazard warning time: closing
speed sets `checkspace`'s reaction budget, and at 111 the nearer hazard still
gives 62 frames.

**The bounce keeps its period.** Stepping the phase by `fdv` would have fixed the
clock and wrecked the game -- a 32-phase arc dropping from ~1.35 s to ~0.55 s,
balls 2.4× faster everywhere. 25/64 of a phase per frame is 23.4 phases a second
against the 23.8 it ran at.

**Accumulate per KIND, not per slot.** Three calls a pass serve all eight
obstacles. Per-slot would have been up to eight calls of O(`fdv`) work every pass
-- the positive feedback loop CLAUDE.md §3A warns about, in the routine whose whole
job is to take the loop rate out of the game's behaviour. `obs()` went with it:
it only ever held a copy of the kind's speed.

**The escalator rides stay per-pass**, both actors', for the reason they always
have: a rider is locked to the step animation and that clock cannot be the frame
delta.

#### AND THE GAP BETWEEN TWO HAZARDS WAS NEVER CLEARABLE

`checkspace.py` multiplied the jump arc's length by a **per-pass** speed. The arc
is indexed by `kjf`, which advances by the frame delta, so **its entries are frames
and always were** -- every closing distance it printed was about 2.4× too large:

| | old model | corrected |
|---|---|---|
| one jump clears both at | ≤ 54 px | **≤ 22 px** |
| landing between needs | ≥ 168 px | **≥ 82 px** |

`HAZGAP` was 48, chosen because 48 ≤ 54. Against the real numbers 48 is **the
dangerous middle**: too far apart to clear together, too close to land between.
That is precisely what was reported from play -- *"they seem closer together,
making them harder to jump over"* -- the player clears the first and comes down
onto the second.

**This is not a regression from the re-pacing.** The real closing distance was
~70 px before and ~67 px after; only the model was wrong. The gap has been
unclearable since it was set.

**A SECOND UNIT ERROR HID INSIDE THE FIX.** The corrected file still computed
*both* bounds from the **slowest** hazard. The two have opposite worst cases:
clearing a pair together is hardest against the slowest (less ground drifts
under the apex), but landing between them is hardest against the **fastest**,
because the whole airborne stretch is spent closing. Landing between needs
**82 px**, not the 67 that one speed for both reported. It never showed, because
the shipped gap sat in the other window entirely.

**And that 67 was the number which "proved" the land-between option impossible.**
The reasoning ran: `WARNPX = 120` of reaction distance caps the gap at 57, 57 is
under 67, so there is no room -- therefore `HAZGAP = 20`, a pair taken as one
wide obstacle. Every step follows; the premise was a units bug. A wrong unit did
not merely misplace a threshold, it argued a whole design option out of
existence, and the game shipped the wrong pairing for it. **See §0p-bis for what
the option actually costs, which is slot 0's jitter and not the gap.**

`checkspace_test.py` now rejects 70, 176, 48 **and 71** -- the last being a gap
that only the fastest hazard can see through, and the case that fails the moment
anyone puts the bound back on a single speed.

### 0p-bis. Two hazards on a floor: there are two safe gaps, and the game had picked the wrong one

From Krook 6 a floor can carry two hazards -- which kinds, and from which Krook,
is §0p-ter. Kelly closes on an oncoming hazard at `(KWALK64 + its speed)/64` px a
**frame** -- 2.53 at the slow speed, 2.92 at the fast one -- and the jump arc
**holds its 14 px apex for 9 frames** and is **airborne for 28**. So exactly two
gaps are survivable:

```
gap <=  22 px    ONE JUMP CLEARS BOTH        (9 apex frames, slowest hazard)
gap >=  82 px    HE CAN LAND BETWEEN THEM    (28 airborne frames, FASTEST)
```

Anything between is **the dangerous middle** — too far apart to take together,
too close to land between.

**What shipped was a difference of two placement bytes.** The second hazard sat
at `(lx AND 63) + 64`, giving 46 px on screens 1 and 2 and 70 px on 4, 5 and 6.
Screens 2 and 4 flank the lift, which is how it surfaced: *"on the left and
right of the elevator they seem closer together"*. 46 px is inside the one-jump
window and fine; **70 px is squarely in the dangerous middle**. The asymmetry
was the symptom; the fault was that the gap had never been derived from
anything.

**THE SECOND WINDOW *IS* AVAILABLE, AND THIS DOCUMENT SAID OTHERWISE.** The
first fix sized the gap at 176 px so a jump would fit between the pair, and that
made it worse: `stag` is distance from the **far** edge, so widening the gap
moves the second hazard *toward* the player, and at 176 px it starts about 64 px
from the wall he walks in through. Reported immediately — *"the 2nd ball seems to
be placed where the player is entering, and immediately the player cannot
dodge"*. The conclusion drawn was that the window did not fit at all, and the gap
went to 20 px — a pair taken as **one** obstacle.

That conclusion rested on a land-between threshold of 168 px, then 67 px, both
wrong (§0p). It is **82 px**, and 82 + the 120 px reaction budget fits inside the
240 px of placeable floor with room to spare.

**`HAZGAP` is 104 px, and it is MEASURED rather than chosen.** A frame-by-frame
census of a full 2600 playthrough — `assets/ref2600/hazards.md` — finds that two
**moving** hazards on one floor are never closer than **108 px** in our scale,
not once across 21 levels, and that its static radios come as close as **54**.
Our own arc independently puts the thresholds at 82 px moving and 49 static, so
the original sits just above both, from evidence that knows nothing about this
jump. That is the *run / jump / run / jump* the reviewer asked for.

**The price is slot 0's jitter, and it is arithmetic rather than a judgement.**
The pair spans `HAZGAP`, and the nearer of the two still owes the player his
reaction distance at the entry wall: 120 + 104 = 224 of the 240 px available, so
the pair can only slide **16 px**. Hence `HAZMASK = 15`, applied from Krook 6 —
before that nothing is paired and slot 0 keeps its full 64 px of range, which
covers most of the early game. This is not less faithful than what it replaces:
the original places its radios on exactly **three fixed positions** per floor and
has no jitter at all.

**NO EXISTING CHECK COULD SEE ANY OF IT.** `checkball.py` sweeps a *single* ball
against the jump and the crouch and is right about every frame; `checklevels.py`
pins *when* the second hazard arrives and is right about that. Neither asks
whether two hazards that are each individually fair are fair **together** — a
property of a pair is invisible to every check written about one of them.

`assets/checkspace.py` asks both halves: the gap must land in one of the two
windows, **and** the nearer hazard must not start in the doorway — because the
first fix satisfied the first half and failed the second.
`checkspace_test.py` holds it to both known-bad inputs, 70 px and 176 px, which
fail for opposite reasons.

### 0p-quater. Which hazards come in twos, measured rather than assumed

The doubling was **one gate at Krook 6 for every kind**, on the strength of a
published guide's line about "double radios". The guide's table stops at level 8
and says the levels stay the same after it. The reviewer remembered otherwise,
and remembered radios in twos and threes.

Rather than pick a side, the original was counted: one frame per second of a full
2600 playthrough, hazards classified by colour and shape, rounds attributed to
levels through the HUD. Method, pitfalls and the full table are in
**`assets/ref2600/hazards.md`**; the result:

| what | from |
|---|---|
| shopping carts appear | level 3 |
| biplanes appear | level 4 |
| **a second radio** | level 6 |
| a third radio | level 8 |
| **a second ball** | level 9 |
| **a second cart** | level 11 |
| **a second biplane** | never, in 21 levels |

So the ramp **does not stop at 8** — balls double at 9 and carts at 11, and from
11 the layout is stable through 21. The guide is not wrong so much as
incomplete: its author reached level 8. The reviewer's recollection was right.

Two consequences for the port, both of which the single Krook 6 gate got wrong:

* **Two balls turned up five rounds early**, at 6 instead of 9.
* **Biplanes came in pairs, and the original never pairs them.** It is the one
  hazard that must be **ducked** rather than jumped, so a pair of them is a
  different question from a pair of anything else — and the answer is no. The
  rule is expressed as an absence (the default `ldbl` is simply never lowered for
  `OB_PLANE`), and an absence is exactly what a later edit restores without
  noticing, so `checklevels.py` checks for it rather than trusting it.

### 0p-quinquies. Three radios, and why "two slots" was never about radios

The port shipped with a **third radio out of scope**, on the reasoning that only
two obstacle slots per band are live and a third "would cost a slot in the table
and the sprite budget". The first half is true and the second half is wrong.

**The two-slot cap is a limit on SPRITES, and a radio is not one.** The VDP shows
four sprites per scanline and *drops* the fifth by slot order rather than
flickering it, so a band affords Kelly (2 boxes) + Harry (2 boxes), or Kelly +
two obstacles — four either way. That argument is airtight for balls, carts and
biplanes. A radio is **four characters stamped into the name table** by
`draw_radios`; `draw_obst` explicitly skips it. It costs no sprite, and the
scanline limit does not reach it.

So there are now **twelve slots in two groups**:

| slots | per band | kinds | sprites |
|---|---|---|---|
| 0–7 | two, at `band*2 + slot` | any | 8–15, propellers 16–23 |
| 8–11 | one, at `8 + band` | **radio or empty** | none |

Keeping the new slots in their own block rather than making the stride three is
what leaves `draw_obst`'s `FOR di = 0 TO 7` and its `ds = di + 8` untouched. A
stride of three would have scattered the sprite-bearing slots to 0,1,3,4,6,7,9,10
and every sprite number in the game would have had to be recomputed — to place a
thing that does not use one.

The third slot's kind does **not** come from the table. It is synthesised from
the band's own slot 0: a third radio appears only where that band already has
radios, from **Krook 8** (measured — §0p-quater). Reading a kind out of the table
would have let a third *ball* through, and a third ball is the fifth sprite the
cap exists to prevent.

**The placement is arithmetic, not cases.** The three positions are columns 7, 15
and 23 — eight apart — and the pixel x is simply the column times eight: 56, 120,
184, midpoint 128, dead centre. A lone radio takes the middle, a pair takes the
ends, three fill the rack. This was three literal x values selected by a nest of
`IF`s and then a **runtime divide by repeated subtraction** (`rad_col`, up to
fifteen laps) to recover the column from the pixel — two spellings of one fact,
since the pixels were only ever multiples of eight because they were columns.
`rad_col` existed solely for that call and is gone with it; the rewrite paid for
most of the feature.

### 0p-septies. The roof has no east wall, and removing art saved nothing

The crook's escape point was `htx = 224` on screen 7, with a comment explaining
that 224 is *inside* `XWALL` (232) because "a target he cannot reach is a crook
who can never escape". Correct, and it stopped him two characters short of the
edge — because the **exit door was drawn there**, six cells of `EXITC` at
columns 28-30.

Both moved together, and they had to: the arrival test is *within 6 px of
`htx`*, so a target past the limit his own movement clamps him to deletes the
escape loss condition silently. `XROOF = 252` is now the target **and** the
clamp, so the place he stops and the place he escapes from cannot drift apart.
Floors 1-3 keep `XWALL`, because they *do* end in an `ENDWALL` character; the
roof does not.

**And the art removal cost nothing and saved nothing — measured, both.**

| build | fixed area | bank 1 |
|---|---|---|
| before | 24,306 | 7,898 |
| door art removed only | **24,306** | **7,898** |
| + escape moved east | 24,308 | 7,898 |

Removing six cells from a band template does not shrink anything: a template is
a fixed **5 × 32 = 160-byte** block, so blanking a cell changes *which* byte is
stored, never *how many*. And the character's own 8 bytes of pattern plus 8 of
colour live in a **bank**, which is the budget with thousands free — deleting
`EXITC` outright would have renumbered every code above 156 (`checkchars.py`
named 21 stale constants when it was tried) to reclaim 16 bytes of the budget
that is not scarce. It stays defined and simply unplaced.

**And how far east he goes is limited by an 8-bit wrap, not by the screen.** His
sprite is 16 px wide, so at 240 he stands flush against the edge *fully visible*
and then stops existing — `do_escape` runs `hide_all` on the same pass, which
reads as being deleted rather than leaving. At **252** twelve of those sixteen
pixels are already clipped off screen when he goes.

Getting there meant keeping the **measure-the-room-then-step** clamp rather than
the cheaper `hx = hx + hspd : IF hx > hlim THEN hx = hlim`. That form silently
caps XROOF at 245: `pace_step` can emit two pixels a frame over five frames, so
`hspd` reaches 10, and 252 + 10 is 6 in eight bits — `IF 6 > 252` is false and
the crook would **teleport to the west wall** on his last stride, at a speed
nobody has set yet. Measuring first never adds past the limit and is exact at
any limit up to 255. The `IF hx < hlim` guard it used to carry is dropped:
`hx <= hlim` is invariant, so the subtraction cannot underflow.

`checkchase.py` reads `XROOF` out of the source now. It had `7 * 256 + 224`
typed in with a comment saying where it came from, **and it still passed** after
the edge moved: 16 px is a tenth of a second on a 4,104 px route, so it shifted
no assertion. A stale constant that only lies by a little is the kind a green
build protects.

### 0p-octies. The level design moved out of code and into data

Reported from play, and recurring: *"The obstacle density, especially on the early
levels is wrong. There are some purely empty screens, especially on level 1, and you
put balls on every screen on the 1st and 3rd floors."* Both halves were true and both
were the same fault.

**The layout was data; the ramp was code — and the ramp decides what appears.** Every
per-Krook decision was a ladder of `IF krk < n` gates inside `load_band`, and a gate
can only say things about *(Krook, floor, kind)*. Two things the original does were
therefore not expressible at all:

* **"this screen is empty."** The arrival gate **downgraded an unarrived kind to a
  beach ball** rather than removing it, and floors 0 and 2 had no occupancy gate, so
  both carried a ball on every populated screen from Krook 1 forever. A populated
  screen could *never* be empty, on any Krook — provable from the gates.
* **"this floor has a cart here and a plane there."** `stor_ob`'s kind byte was
  constant per floor: floor 1 all balls, floor 2 all radios, for the whole game.

Measured against the original (`assets/ref2600/hazards.md`, re-derived from the
frames already on disk): **level 1 shows a median of ZERO hazards on screen** where
the port showed two, and **every floor carries two to four kinds** from level 3 on.

Two earlier claims in that document were wrong and had to go first. It said the view
scrolls vertically so "a band is not a floor" — band 0 is grey in all 1,425 frames,
nothing scrolls, and band index *is* the floor. And this document's author claimed the
original's floor is one screen against our eight; **the reviewer corrected it** — the
original flips 2 escalator, 1 elevator and 5 hazard screens, exactly as we do. What
looked like vertical scrolling was the screen flipping.

**The table.** `stor_lvl`, generated by `genstore.levels()`: 11 Krook rows × 32 bands
× 1 byte, kind in bits 0-2 and "a second one here" in bit 3. Krook 12+ reuse row 11,
where the measurement shows the original stops changing. `stor_ob`'s 192 bytes are
gone; the stagger it carried is derived from the band index instead, because
unpacking a stored nibble costs a **divide** and the fixed area had nothing to spare.

**It paid for itself in the budget that binds:**

| | fixed area | bank 1 |
|---|---|---|
| before | 24,320 (16 free) | 7,898 |
| after | **24,070 (266 free)** | 8,058 (134 free) |

**250 bytes returned** — the gates cost more than the table read. The extra 160 bytes
land in a bank, which is the budget with room.

Screens 0, 3 and 7 stop being excluded *as a block*, because the table can now say
"empty" per band and the measurement shows the original's elevator screen carries
hazards. **Two rules override the measurement, both on the reviewer's word:**

*Never a hazard on an escalator screen*, of any kind, on any Krook. That is where the
player has to stop and board, and anything there is a toll on a manoeuvre the game has
already committed them to.

**A SCREEN IS THE WHOLE VERTICAL SLICE — all four floors — and that is the unit the
rule is about.** Two narrower readings were written first and both were reported back:

1. *the band whose template is a flight.* A flight is drawn in the band you are
   **leaving**, so this catches the foot and misses the head: a cart stood at the top
   of floor 3's escalator, on the roof.
2. *the foot and the head.* Better, and still wrong — floor 1's screen 7 kept a ball
   while floor 2's escalator stood on that same screen, one band above it. All four
   bands are on screen together, so the player sees a hazard and an escalator in the
   same picture, which is the thing the rule exists to prevent.

So `esc_screens()` derives the screen **indices** that carry an escalator on any floor
— 0 and 7 — and every band on them is unplaceable. Eight of the 32; `fill_order()`
omits them, so the budget cannot spend one by accident. Derived rather than a literal
`(0, 7)`, which would go stale the day a floor changed sides.

The **elevator** screen is deliberately not covered: waiting for a car is not the same
as stepping onto a moving stair, and the reviewer wants hazards there.

**And the density metric had to change with it.** It averaged over all eight screens on
both sides, which is not like for like once two of ours are structurally empty: a
whole-store average is a quarter lower by construction, and no table could reach a
figure measured on a game that does put hazards on its end screens. It made Krook 7
look 0.52 short of a target it could not have hit. `density()` now averages over the
**placeable** screens and is checked against the original's **aisle** column.

### 0p-nonies. Matching the average is not matching the distribution

With the density curve on target the table still played wrong, reported as *"sometimes
the distribution feels heavy on certain screens"* and *"there are no hazards on the
first band on the way to the elevator"* — which are the same observation from both
ends. **A mean says nothing about spread**, and two faults were hiding under a correct
average.

**The screens filled in lockstep.** Every screen got its first hazard before any got a
second, so at Krook 4 two thirds of screens carried exactly three and the rest exactly
four: no relief anywhere and no variety. The original's spread is wide at every level —
12-19% of its screens are empty even at levels 4 to 8, with a tail carrying five, six
and seven. `SPREAD` is now a screen *stride*: at 1 the screens fill in lockstep, at 4
strictly one at a time, and 3 sits where the last screen in the order can fall far
enough behind to stay bare. Which screen runs ahead rotates with the Krook, so no
stretch of shop is permanently the quiet one.

**And the doubling piled onto whichever screens came first.** Spent in fill order, it
gave Krook 9 loads of `[4, 3, 1, 7, 6, 10]` — one screen carrying **ten** against a
maximum of **seven** ever observed in the original, with another holding one. That is
the "heavy" report, and it came from the doubling rather than from which bands are
occupied. Doubles are now dealt **round-robin across screens**, and a per-screen cap
binds outright, because round-robin alone does not: once the other screens run out of
bands whose *kind* may pair, the loop keeps returning to the one that has them.

**AND THE CAP HAS TO BE PER LEVEL, APPLIED WHEN BANDS ARE PLACED.** It was a single 7 --
the most seen anywhere in the playthrough -- which is no constraint at all on the early
rounds, and it was only consulted while doubling. Krook 1 places five hazards and put
three of them on ONE screen, a wall of balls across three bands with the rest of the
store empty, while a game-wide cap of seven sat there being satisfied. Reported as *"a
very heavy weight on the first screen I came to ... a really heavy skew and many empty
other pages"*. The original never shows more than **two** at once on level 1, in 57
sampled frames. `MAXLOAD` is now the measured per-level maximum and steers the
placement rather than trimming it afterwards.

Both are checked. The load cap is held as a literal in `checklevels.py` rather than
imported from the generator — the first version read `genstore.MAXLOAD` for its
expectation, so raising the generator's cap raised the threshold with it and a table
piling ten onto one screen reported success. That is the second time this file has made
exactly that mistake; the mutation test is what caught it both times.

*Never a radio on the roof.* A hardware limit rather than a taste: a radio is drawn as
**characters**, so it shares its cells' two colours with whatever it stands on — flat
green on a shop floor, the parallax skyline on the roof. Reported from play as *"the
colors get messed up"*. The 2600 does put radios up there; we cannot. The roof
therefore carries **carts and nothing else** — no biplane either, per above.

A radio is also kept off any screen whose boarding zone a rack position would sit on:
it is the only hazard that does not move, so the only one that can *park* on one, and
its rack is chosen at run time where the generator cannot steer it. That is what
finally makes `_clear_x` live code — it had never once fired.

**And the checker had to move with it.** `checklevels.py` parsed the gates out of the
source; there are no gates. It now asserts against the generated table — arrivals,
doubling, the roof's no-biplane rule, boarding zones, **the density curve**, and that
level 1 really has a bare screen. The density curve is the one that was never pinned
anywhere, and it is exactly what was reported.

Its first version took its expectations *from `genstore` itself*, which makes the
assertion vacuous — mutating `DOUBLE[BALL]` from 9 to 6 moved the table and the
expectation together and the check reported success. The measured numbers are written
in the checker now, independently of the generator. Four mutations were run against it
before it was trusted.

### 0p-sexies. The time bonus was paying ten times over

`#score` is counted in **units of ten** — the prize is `#addv = 5` for fifty
points, and the bonus-Kop threshold is `#nextk = 1000` for ten thousand. The time
bonus was written as `#bval = 100 / 200 / 300`, in *points*, and therefore paid
**1,000 per time unit** where the original pays 100.

Nothing failed. The digits lined up, the tally counted out at the right speed,
and the only symptom was a score that ran away — reported from play as *"it seems
like you awarded 1000 per time unit left"*, which is exactly what it did.

The tell is a constant written in a **different unit from the routine it is
passed to**, the same class of fault as the px-per-pass speeds in CLAUDE.md §3A.
`checklevels.py` now checks the bands in **points** (band × 10) rather than in
the source's own unit — a check written in the source's unit would have agreed
with the bug.

### 0e. A character number written by hand is a bug waiting for a rename

The character table is **generated and automatically de-duplicated**, so a code
is not a fact about the source — it is a *result*. Adding one character, or
merging two that happen to be identical, renumbers everything after it, and any
number written down by hand then points somewhere else with no error anywhere:

- `CONST CH_CASE = 113` shipped once. A renumbering had made 113 `EXITC`, so the
  second collectible drew an **exit door** in the aisle — a plausible-looking
  box, and nothing connecting it to a change made in another file.
- `CH_ECAR` and `CH_EDOOR` were **both one too high**, because `SHELFB` merged
  into `SHELFT` and `EDOOR` merged into `SHAFT`. The elevator shaft drew the
  *car* pattern on every floor and the open car drew an *escalator step*. That
  one sat in the shipped cart until a checker was written for it.
- The same class bites the `DEFINE CHAR 96,N,store_pat` count: a table that
  outgrows its load is simply not loaded, and the extra characters draw as
  whatever happened to be in VRAM.

**`assets/checkchars.py` checks every `CONST CH_<NAME>` against `CODES["<NAME>"]`
and both load counts against the table's real length**, and fails if it finds no
constants at all — a check that quietly stops applying is worse than one that
fails.

---

### 0f. The ride, the jump onto it, and the crook's speed -- all measured

**The rider was never on a step.** He moved at the staircase's slope, 2 px
along for 1 up, and the steps moved at the same rate -- and he still floated,
because the two were never put *in register*. The bottom tread sits 4 px above
the floor, and the whole staircase slides another 1 px up per animation phase,
so a rider boarding without that `+ escp` term starts up to 3 px out and stays
out for the entire ride. Nothing about that is visible in either file: the
rates match, the constants look right, and the rider simply travels beside the
steps.

The fix is to derive everything from **which step he is on**. The staircase is
a straight line, so a step 4 px higher is 8 px further along it, and one number
-- the step's height above the floor being left -- fixes the rider's x, his y,
and the rest of the ride:

```
west  klx = 99 - 2*height        east  klx = 140 + 2*height
```

Walking on, that step is the bottom one (`4 + escp` px up) and the feet have to
climb onto it: he rises 2 px a frame while the tread rises 1, so the gap closes
in `4 + escp` frames and he is riding it after that. `assets/checkride.py`
simulates every ride -- 3 floors x 2 directions x 4 phases x 4 ways on -- and
checks the pixel under his feet is the top of a tread in the bitmap that will
be on screen that frame.

**And matching the rates was still not enough, because they were two different
clocks.** The rider advanced by the frame delta -- `fdv` -- like everything
else in the loop, while `esc_tick` advanced the staircase by one phase per loop
*pass*. Those agree only while the loop keeps up. The moment a pass costs two
frames the rider travels 4 px along and 2 up while the staircase travels 2 and
1, and he climbs off the step he is standing on. It compounds across the ride:
his feet start planted on a tread and end floating several pixels above it.

**The obvious repair makes it worse, and that is the interesting part.**
Pacing the animation by `fdv` too locks the pair together and *aliases*: there
are four phases covering an 8 px period, so stepping by 2 flips the pattern
between two positions half a period apart -- direction unreadable -- and
stepping by 3 runs the sequence 0,3,2,1, which is the **wagon-wheel effect**.
The staircase visibly carries its steps *downward* while the rider goes up. A
4-phase cycle can only be stepped by one, whatever the frame rate.

So the animation is the clock, and **the rider is paced from it**: both advance
by a fixed 2-across-and-1-up per pass. That is the only arrangement in which
they cannot drift, and it is what "the player moves at the rate the steps carry
him" actually means. The price is that a ride takes 36 *passes* rather than 36
frames, so it slows when the loop does -- honest behaviour for a machine that
is carrying you, and the two screens with a staircase are the busiest in the
game (`esc_tick` alone rewrites 120 bytes of pattern table per pass).

`checkride.py` reads both clocks out of the source and fails if they differ, if
the phase is stepped by more than one, or if a foot leaves a tread at any of
frame deltas 1, 2 or 3. All three of those shipped at least once.

**And then it let him jump clean THROUGH the staircase.** Boarding required
his height to *cross* a step's exact height in one frame, which is too strict:
he covers 4 px a frame, so a given step is under him for about two frames of
the descent, and if his arc did not happen to pass through that step's own
height in those two he sailed over the whole flight and landed on the floor
beyond it. The rule is now the one a floor uses -- coming down, and at or below
the step. It cannot over-reach because only the bottom three steps are in
range at all.

**A jump at the staircase used to be cut short.** Boarding fired the moment he
entered the foot's 24 px zone, which zeroed his height in mid-air and dropped
him at the bottom of the flight -- so aiming a jump at the steps was strictly
worse than walking. Now the arc finishes and the staircase is simply what he
lands on: the step under him follows from his x, and he boards when his feet
*cross* its height coming down. Only the bottom three steps are within a 14 px
apex at 4 px a step, so it is a ladder rather than a divide.

**The crook was too slow, and by a measurable amount.** Tracked off the
reference video frame by frame, the 2600's Kelly covers **0.40 screen widths a
second** and its Harry **0.193** -- a ratio of **2.07**. Ours was 2.67. (The
absolute speeds cannot be copied: ours are ~2.3x the original's, because our
Kelly is charged three full traverses where the original's player picks a much
shorter path.) Harry is now 1.75 px/frame, a ratio of 2.29.

2.0 would match the original exactly and cannot be used. **Our** routes are not
the original's -- Kelly's is 1.95x Harry's -- so a speed ratio of 2.0 leaves him
5.2 s ahead at the escape edge, less than one beach ball. 1.75 leaves 10.1 s.

**That margin only became visible once the check stopped ignoring the lift.**
`checkchase.py` charged Kelly the full on-foot route and nothing else, which is
not a conservative assumption but a route no player takes: the shaft is on
screen 3, *on his way* from his spawn to floor 1's escalator, and it carries him
two floors. Modelling only the foot route made the chase look 5 s tighter than
it is -- and that phantom tightness was being used to argue the crook's speed
down. A check that is wrong in the safe direction still shapes the design, and
here it was shaping it wrongly.

**The scanner's surround is GREY, not black.** Also measured: the 2600 insets
its scanner in a grey band the width of the screen. It was briefly black, which
reads fine and is not the original.

---

### 0g. The run cycle, and what a symmetric leg costs

Measured off the reference video frame by frame: the original runs a **four-pose
cycle with a forward lean**, and the arms swing with it — a skin-coloured hand
appears beside the face on half the frames.

Ours was **two poses, and both were symmetric about the centre line**. A
symmetric leg says nothing about which way the figure is going, and mirroring
it for the other facing produces the identical pattern — so half the sprite
table was paying for nothing and the run read as a shuffle.

**Four poses cost two drawings.** In a side view, "left foot forward" is the
horizontal mirror of "right foot forward"; the facing lives in the hat, the
face and the tunic, not in the legs. So the cycle is

```
A, B, mirror(A), mirror(B)
```

and **the same four patterns serve both facings**, entered at a different point
— invisible, because the phase runs continuously anyway.

**The arms swing inside the tunic's own sprite.** A skin hand would be a fourth
box on those rows, and four is the entire per-line budget once Harry is on
screen (§5). Moving the *arms* into the blue tunic pattern costs one extra
pattern per facing and no boxes at all: the leading arm lifts on the two
full-stride frames and hangs on the passing frames.

**The cycle rate is matched to the speed, per character.** A pose has to cover
about a stride's worth of ground or the figure skates. Kelly runs 4 px/frame and
uses bits 2-3 of his counter (four frames a pose, 16 px); Harry runs 1.75 and
uses bits 3-4 (eight frames, 14 px).

**Halving Harry's cadence was tried and is worse.** `hanim` advances by pixels
moved, so a pose is a distance: bits 4-5 put one pose on 16 px and the cycle on
64, which is nearer a real stride for a figure 24 px tall and was rejected on
sight. Reverted to 8 px a pose. The arithmetic argument from his height is
seductive and wrong at this size -- do not re-derive it. Bit tests only halve or
double in any case (a divide is out: `/` compiles to a real TMS9900 DIV in
per-frame code), so if the cadence ever needs work it is the POSES that have to
change, not the rate.

**The crouch has a front now.** It was a symmetric blob, so mirroring it
produced a nearly identical shape and ducking read as being squashed rather
than as dropping into a crouch and still looking where you are going. The brim
is the tell: it reaches further forward than back, the head tucks behind it,
the back hunches over the leading knee and the feet trail.

**`assets/previewrun.py` renders the whole thing from the shipped bytes** —
every frame, both facings, both characters, plus the crouch — because a walk
cycle cannot be judged from a table of hex. And `assets/checkchars.py` now
covers the sprite numbers as well as the character ones: adding the four run
frames renumbered everything after them and pushed the obstacles up by two
sprites, so `DEFINE SPRITE 24,1,spr_cart` would have loaded the shopping cart
straight over Harry's third leg frame. Nothing in the build would have said a
word.

**AND HARRY'S OWN LEGS WERE STILL SYMMETRIC LONG AFTER THIS WAS WRITTEN.**
§0g fixed Kelly. Harry kept a pair of mirror-symmetric leg frames -- both legs
splayed equally either side of the hips -- which is a FRONT view, and no amount
of work on his head could stop him reading as facing the player. Two rounds of
redrawing the cap, the nose and the torso changed nothing, because the legs are
where a running figure states its direction.

A side-view runner **scissors**: one leg leads and one trails, and the trailing
foot sits *higher* than the leading one because the knee is folded up behind.
That height difference is most of the cue at this size. His two frames are now

* **stride** -- trailing leg swept back with the foot two rows off the ground,
  leading leg reaching forward with its foot planted;
* **passing** -- the planted leg in almost exactly the same place, and the
  other swinging through with its **knee out to column 12 and its foot tucked
  one row off the floor**.

**BOTH FEET ARE ON THE GROUND IN EVERY FRAME, and that is measured, not a
simplification.** In each reference frame the two leg blobs sit on the *same*
scanline, always: the 2600 sprite never lifts a foot. What changes between
poses is only how far apart they are -- about 1.5 clocks closed, nearly 4 at
the widest stride.

That is *nearly* the whole difference between a run and a wobble, and getting
it exactly right took overshooting in both directions. One version lifted the
trailing foot two rows and folded the knee high in the other pose: both frames
were different SHAPES, and alternating between two shapes is a dance. The
correction planted both feet in both poses, which is smooth and completely
stiff -- no knee ever bends.

**The variable is not the lift, it is HOW MUCH OF THE FIGURE MOVES WITH IT.**
The planted leg is in almost the same place in both poses, so the silhouette
barely changes; only the swinging leg travels, and it is free to bend its knee
right out and lift its foot clear of the floor. A bent knee reads from the
**kink in the leg**, not from the height of the hips.

The general form: at four frames a pose, anything that moves the whole figure
between adjacent frames -- a dropped hip, both legs relocating, a change of
stance width *and* height at once -- reads as bobbing, however careful the
individual drawings are. Moving one limb never does.

**His arms were detached blobs.** Two pixels of arm with a one-pixel gap
between them and the torso reads as a lump beside the body, not a limb, and
both frames put them at the same height so they swapped sides without ever
looking like they were swinging. They connect at the shoulder now, and the
**forward arm is high** while the **back arm is low** -- opposition, which is
the other half of the cue. Each arm is **two rows thick along its whole
length** and tilts as it goes: a one-row spike reads as a stick.

**AND THE ARMS ARE THE STRIPES.** Going back to the video settles what the
arms should be made of. Harry is a stack of alternating light and dark bands
from shoulder to hem, and **the arms are those same bands extended sideways**
-- which is what makes them read as arms rather than as things stuck on the
side of him. So an arm's upper row lands on a band and its lower row between
two, and it is striped exactly like the torso it grows out of.

That means the bands run every other row -- `HSTRIPE = {0, 2, 10, 12, 14}`,
leaving white between them. It was `{3, 13, 15}`: two bands down near the waist
with nothing above them, which reads as a belt rather than as a shirt.

**AND THEY RUN THE WHOLE FIGURE, HAT TO SHOES.**

* **The hat is three rows, black-white-black, and has no brim.** It was a wide
  flat brim before -- which is *Kelly's* silhouette, and at this size it made
  the two of them read as the same character in two colours. Harry's is a soft
  box cap sitting on the head and no wider than it. Losing the brim row moves
  his face band up to rows 3-8, so the face sprite is drawn at `hy+3` rather
  than `hy+4`; it still clears the hat rows, which is the only reason that box
  is offset at all.
* **The legs are striped too, at the shirt's own pitch, and the same sprite
  paints the SHOES.** The bands sit on body rows 10, 12 and 14 and carry on
  down leg rows 0, 2 and 4. Banding them two rows at a time was tried, on the
  reading that the trousers run coarser than the shirt on the 2600 grid and
  that a single striped column is what "his torso is too long" describes --
  and it looked considerably worse in motion. Reverted. The measurement may
  well be right about the reference; it is not right about this figure at this
  size.
* **A shoe cannot be a band.** It is the lowest row of each leg, and the two
  legs do not end on the same row -- that is what a stride *is* -- so it is
  written out per pose beside the stripe.

That costs a **fourth sprite box**, and it is affordable because of where it
sits: down on the leg rows Harry has only these two boxes, the other three
being sixteen rows up, so meeting Kelly is two against two -- exactly the
per-line limit of §5. It is also the **highest-numbered** of his four, so if
anything ever does overflow the VDP keeps the four lowest and he loses his
shoes rather than his legs.

**AND A BLACK SPRITE BEHIND A SOLID WHITE ONE IS INVISIBLE.** The two halves
of a striped figure must be **complementary** -- the stripe shows through
*holes* in the body, it is never painted over it -- because the lower-numbered
sprite wins every shared pixel and the legs are slot 7 against the stripe's 27.
The first version drew a full white leg with the stripe underneath, so his
trousers stayed white with nothing wrong anywhere. `split_stripes` and `cut` in
genart.py now guarantee the two never share a pixel, for the torso and the legs
alike.

**AN ARM READS AS AN ARM WHEN THERE IS BACKGROUND BETWEEN IT AND THE BODY.**
This is the one that took four attempts. Every earlier version drew the arm
FLUSH against the torso on the same row -- so it was not a limb at all, it was
that row of the shirt being wider, and the only part that stuck out far enough
to be seen separately was two pixels of hand. That is what "stumpy" meant, both
times it was said.

Each arm is a **three-pixel diagonal over two rows**: it touches the torso at
the shoulder and then steps away, so from its second row on there is a clear
gap of green between the arm and the body. It reaches column 14 in front and
column 0 behind -- five and four pixels clear of a torso only six wide -- and
because it crosses a band row and a white row it is striped like the sleeve it
is. Frame A carries the forward arm high and the back arm low; frame B swaps
them, which is what arms do when the legs swap.

The corollary is worth stating plainly, because it invalidates the two rules
below it as *sufficient* conditions: **length alone does not make an arm, and
neither does contrast with the row above.** Separation does. A three-pixel arm
with green under it reads; a ten-pixel one welded to the torso does not.

**WHAT MAKES AN ARM READ IS THE ROW BESIDE IT, NOT THE ARM.** Measured off the
2600 sprite: one row of the swing runs from **-1.8 to +4.1 clocks** against a
3-clock torso -- a single bar right across him -- the next is torso width with a
**detached hand at about +4.5**, and the next is a shorter bar out to -1.0. So
the rows ALTERNATE, long then short, and an arm row is roughly twice the width
of a torso row. A version with four long
rows in a row does not read as arms at all, it reads as wider stripes, which is
exactly what it looked like.

The reference also carries **detached hand blobs**, one beside the face and one
out past the body with a clear gap between. They are what stop an arm ending in
a blunt edge, and they cost two pixels. So each arm here is a long band row, the
torso-width row beside it, and a two-pixel hand one row further down and
further out.

The arms are kept **disjoint from the torso**, which means no cell is both and
`split_stripes` finds no crossing -- every band simply takes its row's colour.
The crossing machinery stays because it is the general case: were an arm ever
drawn *over* the body, its cells would take the **opposite** colour to their row
(a black sleeve on a white row, a white sleeve on a black band) so the limb
stays visible instead of vanishing into the torso. That is why the split is done
cell by cell rather than by whole rows, and why `checkbands.py`'s row rule had
to become a pixel rule -- see the note there.

**AND HIS STRIPES VANISHED WHENEVER KELLY DREW LEVEL.** Reported from play,
and it was the box count. The VDP counts sprite BOXES per scanline, not pixels,
so where a box *reaches* is what costs. Harry's face box was drawn at `hy+3`,
which means it spans figure rows **3 to 18** -- the whole torso and the top of
the legs -- so every torso row carried three Harry boxes. With Kelly's two that
is five on a line, one over the limit, and the VDP drops the highest-numbered:
his stripes.

The fix costs nothing. The face occupies figure rows 3-8 either way; what
changes is where the *box* reaches. Pushing the pattern to the **bottom** of its
16-row box and drawing the box at `hy-7` spans rows -7..8 instead, so the torso
rows carry body and stripe only. Harry costs two there, a meeting is four, and
nothing drops at all. `checkbands.py` now reports no overflow anywhere.

**AND IT GOES IN SLOT 27, NOT SLOT 8.** The sprite slots are allocated in
blocks -- 0-3 Kelly, 4-7 Harry, **8-15 the obstacles**, 16-23 their
propellers, 24-26 the radar -- so the "next free" slot after Harry's four is
the FIRST OBSTACLE, and the obstacle pass runs later in the same routine. The
first version wrote his leg stripes there and had them overwritten every
frame. Two symptoms, neither of them an error: his trousers stayed white, and
a **ball flickered somewhere it did not belong** -- obstacle 0 being dragged to
Harry's position and pattern for part of every frame and then put back. That
second one reads as a flicker-control problem, which is what it was reported
as; `SPRITE FLICKER OFF` had not moved. `hide_play` gets an explicit
`SPRITE 27` too: its loop stops at 23 and cannot simply be widened, because
24-26 are the radar and it must leave those alone.

**`HARRY_STRIPE` is no longer one drawing shared by both frames.** It could not
be: the arms move on the band rows, so a shared drawing would have left a black
bar hanging in mid-air on the frame without the arm -- which is why the stripes
used to be pushed down to rows the arms never touched. A second drawing costs
**one more sprite pattern and no extra sprite box** (the stripe already has a
box of its own), so §5's per-line budget is untouched; it is 32 bytes of
pattern table. `P_HFACING` goes 16 -> 20 with it, since the left-hand set
starts after everything in the right-hand one. (It is **36** now -- see §0j2,
where the two torso frames became four drawn ones.)

The hem came in from twelve cells to eight to match the body -- at twelve it
read as a skirt.

---

**AND THE CROUCH KEEPS ITS MASS.** Kelly's ducked body narrowed to five pixels
through the middle, so ducking did not read as a man bending -- it read as the
figure shrinking to a smudge and popping back. **A crouch does not lose volume,
it redistributes it:** the back rounds up and the haunches thicken as the height
comes down. The widest rows of the ducked body are now wider than his standing
torso, and nothing tapers below the shoulders except the legs. It is safe to
widen because the ducked body is the whole silhouette with the hat and face
drawn *over* it from lower slots, so extra width can only add bulk at the edges
and can never disturb the brim, which is the one feature that says Kelly at this
size.

---

### 0h. The figures, transcribed onto the 2600's own pixel grid

§0g redrew the run cycle and it still did not look like the game. The reason is
that everything up to then had been drawn from an *impression* of the reference
rather than from a measurement of it, and the proportions were wrong in a way
that reads as a different character.

**Recovering the grid.** The only format the video offers is 480x360 for a
160x192 display, so neither pitch is an integer and — 2600 pixels being
famously non-square — the two are not the same. Both had to be measured:

- **Vertical** from the store: floor bars 51 video px apart, a band being 32
  scanlines, gives **1.594 px per scanline**.
- **Horizontal** from the sprite: a TIA player is exactly 8 clocks and his
  widest row is 20 px, so **2.5 px per clock**.

Sampling each native cell by vote (the encode is soft) then gives the real
bitmap. `assets/cmpref.py` keeps the transcription and squashes our 16x24
figure back down to their 8x19 to compare, because "does it look like the
video" is a question about the silhouette, not about our extra resolution.

**What the measurement said.** Kelly is 8 clocks by about 19 scanlines:

```
 0 ..KKKK..   crown, 4 of 8            9 .....BB.   a shoulder stub
 3 KKKKKKKK   brim, the FULL 8        10 .BBBBBB.   body, 6-7 of 8
 5 ..SSS...   face, 3 of 8            18 ...KKKKK   dark feet
```

**His head is 42% of his height** and the brim is a flat line right across him.
Ours was a small head on a long thin body with wire arms and separated legs — a
different character entirely. Harry measures the same way at about 17 scanlines
with the **face a third of him**, a flat white cap with one black band, a
striped body and legs that split wide.

Carrying those proportions onto our 24 px figures takes **15 of Kelly's 19 rows
to an exact match**; the four that differ are the bottom, where the reference
narrows to dark feet and we keep articulated legs — deliberate, because we have
twice the horizontal resolution and a four-frame cycle to animate.

**The crouch got a third sprite out of it.** It was two bands, hat and body
together in blue, which threw away the one feature that says Kelly at this
size. Three bands is three boxes on those eight rows; it is affordable because
obstacles are suppressed on Harry's floor, so no biplane ever appears there and
he need never duck level with the crook. **And in the air he now holds one
stride** — cycling the legs through a jump reads as running on nothing.

**Kelly's wider brim costs Harry two scanlines of stripe.** With the hat band
reaching y+5, the line where Kelly's brim is level with Harry's cap carries five
boxes. The VDP drops the highest-numbered, which is Harry's stripe sprite — the
degradation this layout was designed around from the start. `checkbands.py`
declares exactly that one droppable and fails on anything else, and it now
reads the pattern numbers by NAME from genart and the draw offsets out of
`KEYSTONE.bas`, because it had gone stale in both at once: reporting overlaps
that were not there while no longer checking the layout that was.

---

### 0j. The animation ran backwards, and one frame is not a facing

The figures were transcribed (§0h) and the run still looked wrong: he faced the
way he had come. The transcription was right; the *frame it came from* was not.

A single frame does not establish a facing. The one used was from a moment
where Kelly was **turning** -- his x wandered 240, 234, 234, 236, 234 -- and its
body leaned the other way from a real run. Building the base art on it meant
`kldir = 1` (right) selected a left-facing figure and the entire animation,
both directions, came out inverted.

The fix is a rule rather than a redraw: **take the frame from the middle of the
longest monotone run.** `dirs.py` searches for exactly that, and it finds a
127-frame rightward stretch. Transcribed from inside it, the right-facing
figure has the shoulder stub on the LEFT and the body inset a clock either
side. Laid out row-for-row against that, `cmpref.py` now reports **18 of 19
rows identical** -- the one that differs is the reference's dark feet, which a
single-colour legs sprite cannot do.

### 0j2. Four DRAWN torsos, from a run-cycle sheet -- and the legs finally get a facing

Harry's run kept reading as a shuffle through every fix in 0g-0j, and the last
reason was arithmetic rather than draughtsmanship: **his legs stepped through
four poses while his torso alternated between two.** `hanim` bits 3 and 4 chose
the leg, bit 4 alone chose the body. Two clocks in one figure -- so the arms
completed a swing in half the time the legs completed a stride, and on two of
the four beats the arm was in a position no runner's arm reaches with that leg
forward. Whatever bit the body was keyed to, it flapped.

The fix is more drawings, not more code. A supplied **eight-frame run-cycle
sheet** (`assets/ref2600/runcycle-sheet.png`) provides the poses, and
`assets/sheet2harry.py` writes four of them out as `harryrun1..4.txt`, 16x24
each, with **our own head already grafted over rows 0-8**. genart reads the
text files, so the build depends on no imaging library and the frames stay
hand-editable.

**WHICH four is measured, and the obvious answer is wrong.** Taking every other
frame -- 1, 3, 5, 8 -- alternates the leading leg correctly and its
*consecutive* steps are a healthy 49 px, which is the number that looks
reassuring. It still plays as two poses. In an eight-frame run cycle
**frame n+4 is the same pose with the legs swapped**, and a side-view
silhouette of a symmetric figure cannot tell those two apart, so every-other-
frame gives you A, B, A, B. Measured on this sheet:

| | | | |
|---|---|---|---|
| 1 vs 5 | 16 px | 3 vs 8 | **7 px** |
| 1 vs 2 | 11 px | 3 vs 4 | 18 px |

The trailing leg sweeps down-LEFT in frames 1, 2 and 5 and down-RIGHT in 3, 4,
6, 7 and 8; within each group they are near-duplicates. It was reported from
play as *"the legs just seem to be going back and forth"*, which is exactly
what a cycle of A, B, A, B is.

**The right metric is the closest pair ANYWHERE in the cycle, not the
consecutive step.** `1 -> 4 -> 5 -> 3` still alternates left, right, left,
right, and puts the two unavoidable near-duplicates *opposite* each other
rather than adjacent: closest pair 16 px, smallest consecutive step 50. 16 is
the best any alternating set can do here, because the sheet offers only three
left-sweep frames and all three are within 16 px of one another.

Every band now steps on the **same two bits**:

```
hq = P_HLEG1  : IF hanim AND 8 THEN hq = hq + 4 : IF hanim AND 16 THEN hq = hq + 8
hp = P_HBODY  : IF hanim AND 8 THEN hp = hp + 4 : IF hanim AND 16 THEN hp = hp + 8
hs = hp - P_HBODY : hs = hs + P_HSTRIPE
```

**The stripes are DERIVED from the body, never recomputed.** The stripe layer
*is* the body layer in the other colour, so a second copy of the beat
arithmetic would be a second clock -- and the day one of them changed, his
stripes would swing half a stride behind his shirt. Same reason `hqs` comes
from `hq`.

Three things followed from grafting a real body onto our head, and all three
cost a version:

* **The neck is a LOCAL MINIMUM, not the narrowest row.** The narrowest row in
  the upper third of a running silhouette is the top of the *scalp* -- two
  pixels of head -- so cutting there grafts the sheet's whole head on under
  ours. Walk down from the head's widest row to the first dip instead.
* **Scale isotropically, anchored on the neck.** Fitting each body's own ink
  bounding box to the sprite stretches it by a different amount in every frame
  (an outstretched arm widens the box) and centres the *box* rather than the
  *body*, so the torso slides out from under the head. One scale for both axes,
  taken from the height, with the neck's centre pinned to column 7.
* **A silhouette flatters.** Judge it striped, the way the game draws it: the
  bands chop the figure up and thin limbs lose whole rows to the black half.

**AND THE LEGS NOW TAKE A FACING.** They used not to, on the stated grounds
that a running leg looks the same either way. That was true of the old poses,
which barely left the body's own width -- and false the moment the sheet's
stride reached the full sixteen columns with one leg forward and one trailing.
Unmirrored, left-running Harry had his **back foot leading and his front foot
dragging behind him**: not a subtle wrongness, and it only appeared because the
art got better. `P_HLEGFACING = 32` (four white poses plus four black ones) is
added to `hq` and `hqs` inside the same `IF hdir = 0` that turns the torso
round, so a facing can never be half-applied.

Costs, measured:

| | before | after |
|---|---|---|
| Harry's sprite patterns | 18 | 34 |
| sprites defined, of 64 | 55 | **63** |
| `P_HFACING` | 20 | **36** |
| fixed area free | 814 B | 770 B |
| `art.bas` (banked) | 3,614 B | 3,870 B |

The pattern table is the binding one: **63 of 64 sprites**, one spare. Anything
else Harry gains from here has to displace something.

`assets/previewrun.py` drifted out of date for the third time doing this and
was corrected twice in one sitting -- once for the two-torso `HFRAMES` table,
once for the leg mirroring. It is the file that shows whether the change
worked, so **it is the file most likely to be describing the previous version**;
check it against `draw_actors` before believing what it draws.

---

### 0j3. The Kop runs two frames, and that is now a decision rather than an accident

Chasing Harry's cycle turned up the same arithmetic in the player, older and
worse. §0g's scheme for Kelly is sound -- four poses cost two drawings, because
"left foot forward" is the mirror of "right foot forward" and the facing lives
in the hat and the tunic. **The drawings underneath it are two pairs of
parallel vertical legs**, apart in one pose and together in the other, and
mirroring a pair of vertical legs gives back very nearly the same picture.
Measured on the shipped bytes:

```
beat1 -> beat3   4 px        beat2 -> beat4   8 px
```

and 4 of those 4 pixels are the hip row sliding two columns sideways, because
it was given the tunic's hem shape (columns 4-13) which is not its own mirror.
So the Kop genuinely runs a **two-frame cycle with each frame shown twice**.

**It was redrawn to scissor and the redraw was rejected on sight.** Two
different attempts, in fact -- one from this line of work and one from another
session running in parallel, which also split `KLEG3`/`KLEG4` out into separate
drawings on the (correct) observation that the mirror was saving drawing effort
rather than ROM. Both were reverted to `e9564ee` at the reviewer's request:
*"the animation from yesterday for the kop was better, so restore that."*
**Harry is the figure under improvement; the Kop is finished.**

That leaves a measured defect that is deliberately being kept, which is exactly
the situation an automated check handles badly. The wrong response is to drop
the threshold until he passes -- that blinds the check for every *other* band
at the same time, which is how a gate stops being one. `assets/checkanim.py`
therefore carries a **named exemption with its reason**: `kq` is still
measured, its 4 px is still printed on every build, and only the failure is
suppressed. If the Kop's art ever gets worse, the number moves in plain sight.

**`assets/checkanim.py` asks the one question none of the other checks did.**
Every existing check asks whether the numbers are consistent -- and they were:
the right patterns were loaded at the right addresses and drawn on the right
beats. They were just the same picture twice. So this one reads the beats out
of `KEYSTONE.bas` itself (base assignment plus the following `IF <clock> AND
<bit>` lines, never a table of its own), resolves them through genart's sprite
table, and fails if any two beats of one cycle are within 10 px.

Two things it has to do that were learned the hard way:

* **Compare the whole figure, not the one sprite it names.** A striped actor is
  split across complementary patterns, so most of the ink can sit in the half
  the band does not name -- Harry's white leg layer holds 10 px of 33, and two
  of his four beats were *byte-identical* in it while the black layer they are
  drawn with differed by 34. Measuring one half alone would call the same art a
  two-frame cycle or a four-frame one depending which half it was handed. It
  adds the derived bands (`hqs`, `hs`) back in. `checkanim_test.py` made the
  same mistake in the opposite direction on its first run -- comparing Harry's
  white torso alone gave 9 px and 6 px and failed art that is correct.
* **Check that every band of one figure runs on the same clock bits.** Four leg
  poses against two torso poses is two clocks in one body, which is §0j2's
  flapping. A band derived from another (`hs = hp - P_HBODY`) is the correct
  way to avoid it and is recognised as such.

It was run against the defective art before being trusted, and failed on it:
`hq` closest pair 0 px, `hp` 5 px, `kq` 4 px. Harry is now at 28 and 25; the
Kop stays at 4, on purpose.

### 0k. The crouch bends over, and 11 px is the ceiling

The crouch was 8 px, which is not a crouch: there is no room at that height to
draw a figure bending in a *direction*, so it read as a squash however it was
mirrored. It is 11 px now -- rump high and behind, back sloping down and
forward, the black brim thrust out ahead, the face tucked under it.

**11 is a limit, not a preference,** and the reasoning generalises to any
duck-or-jump obstacle. Duckable means the obstacle's hitbox clears the crouch;
jumpable means it clears under the 14 px apex. Raising the crouch raises the
duckable floor, so past some height a band of beach-ball heights is *neither* --
an obstacle that cannot be avoided at all. A sweep of every crouch height
against every ball hitbox puts the break at 12, and shrinking the ball does not
move it: **the apex is what binds**, and the apex cannot rise because a 24 px
Kelly plus a 14 px jump already sits 2 px under the band ceiling.

The biplane is raised to match, which was the reviewer's suggestion and is what
buys the extra pixels: an 11 px crouch clears it, a 24 px standing Kop does not,
and a jump still cannot -- so it stays the one obstacle that must be ducked.
`assets/checkball.py` fails the build on any dead band, and it caught this at
16 px before it could ship.

It now flies at **16..22**, not 12..18. At 12 the crouch passed under it by a
single pixel, so a duck that plainly worked still looked like a squeak and a
duck one frame late was a hit -- the *window* was correct and the *reading* was
not. 16 is as high as it can go and still catch a 24 px standing Kop, and the
14 px apex is under it, so raising it costs nothing and buys five pixels of
visible daylight.

**The pose is a bend at the waist, and where the HEAD goes is the whole read.**
A squat keeps the head up and compresses the body under it; a bend puts the head
forward and down with the back gone horizontal above it and the legs still under
the hips, behind. The first eleven-pixel crouch had the head buried under a flat
slab of back with the legs splayed underneath, and it read as a dive -- which is
why "it is still a squish" survived the change from eight pixels to eleven. The
back is now a wedge high and to the **rear**, the hat is clear of it with a
crown and a brim projecting **forward** over the face, and the legs stay under
the hips. So the silhouette has a front and a back and points the way he faces.

**The reference could not settle this one.** About 2,700 sampled frames of the
longplay were searched for a ducking Kelly -- by figure height, by moving-blob
height, and by requiring the hat/face/tunic stack -- and the player never ducks
in any of them; the height sits at a flat 29 video px throughout. (The two
shortest hits were the Activision logo.) So unlike the run cycle (§0h) this pose
is reasoned from the mechanic, not transcribed, and it is recorded here so the
search is not run a third time.

### 0p. How the levels actually advance

Researched, not invented: two independent readings of the published level guides
agree on the arrivals and the speed dials, the **doublings are measured from the
original frame by frame** (§0p-quater and `assets/ref2600/hazards.md`), and
`assets/checklevels.py` fails the build if one moves.

**Arrivals, doubling and occupancy are DATA now** — a per-Krook table, §0p-octies —
so what follows describes what the table contains, not a ladder of gates. Only the
speed dials and the ball apex are still code. **And the table says more than this
list can**: which screens are empty, and which kind sits on which floor *of which
screen*, neither of which the gates could express.

| Krook | what changes |
|---|---|
| **1** | short beach balls, **and nothing else** -- and a median of ZERO on screen |
| **2** | + cathedral radios |
| **3** | + shopping carts (slow) |
| **4** | + biplanes (slow) |
| **5** | the balls go **tall** -- they stop being jumpable and must be ducked |
| **6** | a **second radio** per floor ("double radios") |
| **7** | carts get faster |
| **8** | biplanes get faster |
| **9** | a **second ball** per floor |
| **11+** | a **second cart** per floor; after this the levels stop changing |

**Biplanes never double**, on any Krook. See §0p-quater: the measurement finds
one per floor in all 21 levels reached, and it is the only hazard that must be
ducked rather than jumped.

The published guide's table ends at 8 with "from here on out the levels stay the
same". That is where its author stopped playing, not where the game stops
ramping — the measured original keeps going to 11.

**There are no biplanes on Krook 1**, which is the point of the whole ramp: the
one hazard that costs a *life* rather than nine seconds is the fourth thing the
player meets, not the first. Our previous model had the hazard *kind* fixed per
floor by a static table and only the *speed* ramping, so a new player met a
biplane on the first screen of the first round.

The static placement table stays -- it still decides *where* on each floor a
hazard sits. What is new is a gate on the way in: a hazard that has not arrived
yet becomes a **beach ball** rather than nothing, so a floor is never empty and
Krook 1 is exactly the "short balls" screen the guides describe.

#### AND THAT SUBSTITUTION IS WHY KROOK 1 WAS TOO BUSY

"A floor is never empty" plus "every floor owns a hazard" means **all four
floors carried a ball from Krook 1** -- and all four bands are on screen at
once, so four identical balls were in view at all times. The guides say the
first round "starts out with **merely a few** beach balls". Four at once, on
every populated screen, is not a few.

The per-band *count* was never the problem: only one slot is live until Krook 6,
and then only for radios (§0p-quater). What had no ramp was the number of
**occupied floors**, and it now has one:

| Krook | floors carrying a hazard |
|---|---|
| **1** | 2 of 4 -- floors 0 and 2 |
| **2** | 3 of 4 -- floor 1 joins |
| **3+** | all four -- the roof joins last |

**Alternating rather than clearing the top or bottom half**, so the empty floors
do not stack into a visibly dead region that reads as a bug rather than as a
gentle opening. The **roof is last** because that is where the round is decided.
`checklevels.py` pins both thresholds like every other Krook number.

#### Enemy speeds, per kind, from the video

One global `obsp` could not express this, because the original ramps carts and
biplanes on *different* rounds. Each kind now carries its own speed:

| kind | px per pass | why |
|---|---|---|
| beach ball | 2 | measured at 0.82 px/frame = 49 px/s |
| shopping cart | 2, then **3** from Krook 7 | measured at 0.80 (48 px/s) **and** 1.21 (73 px/s) |
| biplane | 2, then **3** from Krook 8 | same two speeds |
| cathedral radio | 0 | stationary |

The base of 2 is not a guess. Carts were tracked in the reference at 0.80 and
1.21 px/frame, and at this loop's ~25 passes a second those are **exactly 2 and
3 px per pass** -- so the two speeds the original puts on screen are the two
speeds here. The old ramp started at 1 (25 px/s), which was half the slowest
cart the reference ever showed.

#### Scoring

* time remaining x **100** on Krooks 1-9, x **200** on 10-15, x **300** from 16;
* money bags and suitcases **50** each;
* a spare Kop every **10,000** points.

The x100/x200/x300 bands now have two independent sources. The manual's own
wording suggests 1-8 / 9-16 / 17+ instead, and that disagreement is recorded in
section 0 -- the published guides win here because two of them agree.

#### The bonus is counted out, not awarded

Dropping the whole sum into the score in one frame tells the player a number.
Ticking the clock down a unit at a time -- score climbing, a beat under each
step -- tells them what the number was *for*, and it is the pay-off for every
second they saved. `bonus_count` does it in about a tenth of a second per unit.

It also **removed** code rather than adding it. The old `calc_bonus` summed the
bonus by repeated addition to dodge two hazards at once: `tsec * bmul` is an
8-bit product (a 50-unit capture in the x300 band pays 15,000, six times past a
byte), and multiplying properly lands on the MPY/r0 hazard where a 16-bit
variable read straight after being multiplied returns the product's high word.
Counting it out a unit at a time makes the loop the player watches *be* the
arithmetic, so there is no multiply to work around. It fixes the last-tick case
for free as well: `bn_loop` tests `tsec = 0` on entry, where the old
`FOR bi = 1 TO tsec` would have run its body once and paid a full multiplier for
no time at all.

#### The aeroplane is yellow, over black

Two sprites, and the trick is **priority**: a lower sprite number wins on the
TMS9918, and the body sits in slots 8-15 with the detail in 16-23. So the black
layer can only show through where the yellow has *nothing* -- which means the
cockpit is a **hole** in the body, filled from beneath, while the propeller
needs no hole because it hangs off the nose where the body has no pixels. The
detail being the low-priority half is deliberate: when Kelly, a plane and a high
ball share a scan line the VDP drops the highest-numbered sprite, so what
disappears is decoration and never the plane the player has to duck.

### 6a. The scanner: characters underneath, sprites on top

The instrument is split by what MOVES, and that turned out to be the whole
design.

| | drawn as | why |
|---|---|---|
| floor lines, flights, lift shaft | **characters** | fixed relative to the canvas; cost nothing to keep |
| the lift car | **characters**, redrawn on move | moves rarely, and only vertically |
| Kelly and Harry | **sprites** (24, 25) | move constantly, and need to be over everything |

Four rows a level, 4 px of grey margin top and bottom. Rows 0-2 are that
floor's **air** and row 3 is its **yellow line**, which nothing else touches.
The flights are a three-step diagonal down the air, leaning the way they climb;
the car is three pixels tall; and both actors are three-pixel sprites over the
top.

**Why sprites for the actors and nothing else.** A colour byte covers one 8x1
scan line of one CHARACTER, so a whole pixel row of this canvas can only be one
colour. As characters the Kop and the crook could therefore have a row each and
stood a single pixel high, and the two attempts to make them taller both cost
something else: five rows a level put the floor line on the escalator's grey
row and made the lift car -- also grey, also there -- vanish into it completely;
six rows took the margin and read as too big. Per-character colouring did work,
and it is what a sprite gives away for free.

As sprites they need no colour table, no erase and no priority arithmetic: they
draw over the furniture because sprites always do, and nothing shifts to make
room. **The blink went with it.** Kelly flashed only because two markers inside
one character merged into one colour; two sprites are two colours wherever they
stand. And the furniture is drawn ONCE rather than every tick, because there is
no longer a marker erase ANDing bits out of whatever it stood on.

It also removed code: `scan_mark`, `scan_wipe1`, `scan_set`, `scan_clr` and
`scan_addr` all existed to paint, erase or recolour a marker made of character
pixels. **790 bytes came back.**

One thing to watch, and it is the same class as the vanished lift car: the
Kop's marker is black and the flights are black, so where he stands on one --
the extreme end of a floor that has an escalator -- he is briefly invisible.
`checkscan.py` checks that the two SPRITE colours differ from each other; it
cannot check this one, because a sprite over a character is not something the
colour table knows about.

### 6b. What the crook does when he is cornered

He rides the flight that comes UP to his floor back DOWN, which Kelly cannot do
-- an escalator only goes up. Without it the chase always ended in the same
corner, and a crook with nowhere to go is not a chase.

Three things went wrong on the way, and all three have the same shape: **an
override that ignores the state it overrides will eventually contradict it in
full view.**

1. **He rode straight back up.** A flight's foot IS its boarding point, so
   landing there put him on the step he had just come down. He now runs for the
   far end and boards nothing while he does.
2. **He stood still instead of running.** The run override sat BELOW the two
   `IF hmv` movement blocks, where the only thing it could still reach was the
   animation counter: he faced the right way, played the run cycle and
   travelled zero pixels.
3. **He ran into the Kop without noticing, and turned round for no reason.**
   The override beat the flee as well as the climb, so he held one heading
   whatever Kelly did; and it was a count of passes, which expired mid-floor.
   It is a flag now, cleared by exactly two things the player can see: **the Kop
   arriving on his floor** (the flee outranks it) and **reaching the end wall**.

### 6c. Two arithmetic faults worth remembering

**The catch wrapped around the screen.** `coll_harry` centred both actors
before measuring:

```
kcx = klx + 8
hcx = hx + 8          ' hx reaches 253 -> 261 -> wraps to 5
```

Harry walks to x 253 before crossing a seam, so a Kop at the far LEFT measured
five pixels to a crook walking off the far RIGHT and arrested him across the
whole store. The `+ 8` cancels in a difference, so removing it fixes the wrap
and is less work. The obstacle test has the same shape but cannot reach it:
`obx` tops out at 240 and `klx` at `XWALL`.

**A ball at the top of its arc could be jumped.** The hitbox is the middle four
pixels of the eight-pixel art, so an apex of 8 put it at 10..14 against a jump
apex of exactly 14 -- and `kfh < oht` is false at 14 < 14. He cleared it by one
pixel of arithmetic, on the one arc a new player meets first. Nine makes it
11..15. `checkball.py` now reports the split cleanly: 25 of 32 frames jumpable
and 7 duckable on the low arc, which partition exactly, so the top of every arc
is a duck and no frame is free.

### 6d. Hazards stay on their own floor

The placement table used to pick a floor's hazard as `palette[lv][(scr+lv) % 3]`
-- it rotated by SCREEN, for variety across the store. All four bands are
visible at once here, so crossing a seam swapped the kinds in full view: the
balls being tracked on one floor became carts, and balls appeared a storey up.
It reads as objects teleporting between levels.

Each floor now owns one hazard for the whole store -- **balls on 1, radios on 2,
biplanes on 3, carts on the roof** -- and the variety comes from the Krook ramp
(0p), which brings them in one per round. Fixing this also uncovered a leftover
rule, `if lv == 3 and k not in (PLANE, NONE): k = NONE`, which had been silently
deleting every roof obstacle: the roof carts restored two revisions earlier had
never actually appeared.

### 6e. Fixtures give way to what stands in front of them

A radio or a prize is 2x2 and sits in band rows 2-3. Whatever the template put
there has to go, and "whatever" turned out to be three separate things, each
found only once the last was fixed:

1. **The pillar's top half.** A pillar fills all four air rows and the object
   covers the lower two, so it left a grey stub hanging with nothing under it.
2. **The beam top above that.** `beam_tops` stamps the floor bar with the
   support carried up through it into the slab row above every pillar, and it
   runs BEFORE the objects are placed -- so clearing the pillar left three grey
   pixels dangling out of the ceiling. `beam_clear` puts it back, and it
   **tests** the cell rather than assuming: the row above the top shopping
   floor is the roof deck, and writing a floor bar over it would punch a hole
   in the roof.
3. **The rest of the counter.** A shelf run is five cells and the object covers
   two, so it punched a hole through the middle and left the ends either side.
   A counter reads as one object, so the whole unit goes: `wipe_shelf` walks
   outward along row 2 while the cell is still a shelf top, clearing top and
   bottom halves together, bounded at eight steps.

**The prizes are 2x2 as well.** One character is eight pixels square, which is
not enough to say "money bag" rather than "yellow blob" when everything it
sits among is sixteen. That needed character space: the store ran to 158 with
the scanner starting at 160, so the scanner moved to **208** -- it wants 48
contiguous codes and 208..255 is 48 exactly -- and the store now has 96..207.
Collecting one erases all four cells; it used to erase one and leave three
quarters of a bag that no longer scored.

**THE BAG READS AS A BAG BECAUSE OF ITS NECK, NOT ITS BODY.** Sixteen pixels
bought the space but not the shape: the first version was a rounded diamond,
which at any size is a yellow blob. It now goes, top to bottom, **fanned ends ->
neck -> black tie -> body**, and the tie is what makes the cloth above it read as
*gathered* rather than as a lid. The ends turn up one row above the bar, which is
the whole difference between a bow and a bowl -- two rows of that flare and it
reads as a cup.

**The dollar sign costs the bag its shading, and that is the trade.** Two colours
per scan line is the entire budget (§0d): on a row carrying the `$` they are
spent on ink and bag, leaving none for the store floor behind. So **every row the
`$` touches is full-width bag** -- rows 8-14, where there is no green left to run
out of. The rows that *are* silhouetted against the store (the flare, the neck,
the tie, the base chamfer) carry no `$`.

Which means **`#` flips meaning part-way down the figure**. On rows 0-7 and on row
15, `#` is the bag and `.` is the store; on rows 8-14 it is the other way round,
`#` the black `$` and `.` the bag. Both are said in the per-row colour lists
rather than in the patterns, which is why the bottom half looks inside-out read
as art -- worth knowing before editing it. The glyph is six columns wide at
columns 5-10, whose centre is 7.5: the figure's own centre, so it is centred
exactly rather than nearly.

### 6f. The roof owes the floor below its air -- but not to the beams

Every shop floor's slab is five pixels of bar over **three of green**, and those
three are the air at the top of the storey underneath. The roof surface was two
white rows over six of GREY, so the top shopping floor got grey where it should
have had air, and the lift shaft -- which runs to the top of its band --
appeared to carry straight on into the roof. It read as the housing being
taller on that floor than on the others.

Giving `ROOFS` its three green rows fixed the shaft and broke the **beams**,
which is the opposite requirement: a beam HOLDS THE ROOF UP and has to reach
it, while the shaft merely stops beneath it. So the roof has its own version of
the stamp, `ROOFSP` -- grey all the way down, `SLABP`'s opposite number -- and
`beam_tops` now covers all three shopping floors instead of stopping at two.
It stopped at two because band 2's ceiling already ran into grey, which was
true only while the roof had no air under it.

### 6g. Three timing faults, one shape

All three are the same mistake: **work that outlives the loop that was supposed
to finish it.**

**The radar's lift car flickered.** `scan_elev` erased its three cells and put
them back every tick, whether or not the car had moved, so several times a
second there was a window with the pixels off. It is a sprite now (slot 26,
below the two markers, so they pass over it for free) and there is no erase at
all. `scan_elev` and `scan_clr1` went with it.

**A long beep opened the next round.** Not a sounding tone -- a PENDING one. A
set `sf*` flag is an effect waiting for the next pass of the main loop, and
between a capture and the next Krook the main loop does not run, so anything
latched during the round (a hit as Harry was caught, the bonus Kop the tally
just awarded) survived the silence and fired on the new round's first pass with
a fresh decay counter. Silencing the channels cannot help; `snd_off` drops the
flags too.

**The old screen's sprites stood on the new one.** `draw_screen` WAITs between
bands -- one band a frame, because a burst of VDP writes past a few dozen is
silently dropped -- so painting a screen takes several frames, and for all of
them the previous screen's actors and obstacles were still on top of it. They
are hidden BEFORE the blit now and put back by the normal draw on the same
pass, so a crossing reads as a cut. `hide_play` covers 0-23 only: the radar's
three sprites belong to the instrument rather than to the screen, and blinking
them out every crossing would be a new fault in place of the old one.

### 6g-bis. The lift has a step, and Kelly stands on it

The car's floor does not sit level with the shop floor. There is a **two-pixel
lip** along the bottom of the doorway, in the floor bar's own two colours --
`LYELL` over `DYELL`, exactly how `SLAB` lights its own top edge -- so it reads
as the same material as the floor it stands on rather than as a stripe painted
on the wall. The doors then open **above** the lip instead of through it, and a
rider is drawn higher, so boarding is visibly stepping UP into the car.

* **Two pixels is the whole budget.** Three eats into a doorway that is only
  four rows tall; one is invisible beside a five-pixel floor bar.
* **Every door state needs its own stepped twin** -- shut, part-open and open.
  Sharing one stepped character across the states would blink the lip out for
  the two frames the doors are moving, which reads as the step falling off.
  Hence `EDOORS`, `ECARS` and `EDHALFS`: identical to their originals above row
  6, and identical to each other below it.
* **THE SILL IS PART OF THE BUILDING, NOT PART OF THE CAR**, so it is drawn on
  every floor whether the car is there or not. It was originally left off the
  shut state, on the reasoning that "a sill under a shut door would be a ledge
  with nothing behind it" -- which sounds right and is wrong. A real lift
  threshold is a plate set into the *landing* floor in front of the doors; it
  belongs to the storey, not to the car, and you see it whether the car has
  arrived or not. Without it the doorway sat flush with the wall on the three
  floors the car was not on, and the lift read as a painted rectangle rather
  than something you could walk into. `car_cell` therefore sets the sill
  **before** the door-state branches, which also covers the two jamb columns of
  a part-open door that the part-open branch never touches.
* **THE DRAWN STEP AND THE RIDER'S LIFT ARE DIFFERENT NUMBERS**, and the design
  originally made them one constant on the grounds that sharing it meant "the
  drawing and the standing height can only ever agree". Agreeing is precisely
  what they must not do.

  `ELSTEP` (2) is a fact about the **art**: the lip is two character-graphics
  pixels proud of the shop floor, exact and unambiguous. `ELRIDE` (3) is where
  the **sprite** must sit to look like it is standing on that lip -- and a
  sprite is not placed the way a character is, because **the VDP puts a
  sprite's top line at y + 1** (`tms9918-sprite-y-208-terminates`' sibling
  hazard). A rider lifted by exactly the drawn step height renders one pixel
  *into* it rather than on it.

  Holding them in one constant made the correct answer inexpressible, and the
  comment claiming the shared value was a safety property is what kept the
  off-by-one looking like a rounding opinion rather than a bug.

### 6h. The city behind the roof

The roof band was a flat grey panel, chosen so Kelly (dark blue) would not
vanish against the sky. It worked for him and hid the roof's own hazard: a
shopping cart is grey, and it disappeared completely. **One neutral cannot
serve a dark actor and a light hazard at once.**

A skyline solves both precisely because it is not one colour. Dark brick with
lit windows cut against cyan sky means anything crossing it is against brick
for part of its width and sky for the rest. The windows are the character's
FOREGROUND and the wall its background, which is how one cell carries both, and
the per-row background is what lets a single cell be sky-above-wall for a
roofline.

Three details that each took a pass to see:

* **Row 1 used to be the parapet** -- a crenellated band of medium red across
  the whole screen. As a horizon above flat grey it read fine; above a lit
  skyline it reads as a **row of flames**. Removed, and the tallest buildings
  take that row instead.
* **They take ALL of it, and the tallest reach into row 0.** The skyline uses
  every row of the band above the deck: row 3 is always solid wall, rows 2 and
  1 may be a full storey, and the tallest carry a 4 px `BLDGM` into row 0. The
  six steps are **8, 11, 14, 20, 24 and 28 px** -- the top of the city is three
  and a half characters, with 4 px of sky still above it, which is enough to
  keep it reading as a horizon rather than a wall. `BLDGM`'s courses and
  windows line up with `BLDGW` cell to cell.
* **The building tops were exposed windows.** Both top characters put their
  windows in the first brick row, so every block was cut off through a row of
  lit windows and read as sliced rather than finished. One solid row at the top
  of each. **`BLDGM` brought the fault back** when it was added: a straight
  4 px slice off the bottom of `BLDGW` is window, window, blank, blank, so the
  new half-height roofline spilled yellow over its own top edge while the
  full-height tops beside it looked finished. Its windows moved down a row --
  solid, window, window, blank. Any future partial top needs the same cover.
* **The flight that crosses into the roof** kept a grey backdrop in its
  composites -- right when the band was a grey panel, and a grey rectangle cut
  out of the city afterwards.

### 6i. Walls, and a terminator that ate a real column

The building's outside wall gets the same treatment as a pillar: it fills all
four air rows, so `_beam_cols` counts it and `beam_tops` carries it up through
the floor above. Two faults were in the way, and the first is the more
interesting.

**COLUMN 0 WAS THE TABLE'S TERMINATOR.** `stor_pil` stored raw column numbers
with 0 meaning "no more entries" -- and column 0 is a real place: it is where
the WEST end wall stands. Every west wall on every floor was silently skipped,
while the east wall at column 31 worked perfectly, so it presented as an
intermittent problem rather than a systematic one. Columns are stored as
**column + 1** now. `preview.py` had the identical bug *and* stopped at band 1
where the game does three, which is why every render agreed with it.

**AND THE WALL'S CAP IS BRICK, NOT A GREY BLOCK.** `SLABP` carries a solid
support up through the bar, which is right for a pillar and wrong for bonded
brickwork; `SLABE` and `ROOFSE` cut the pattern in. The first version took its
three rows straight off the end of the wall's own cycle -- rows 5, 6, 7 -- and
row 5 is a MORTAR course, so a green line ran between the bar and the top of
the wall. Beside the pillars' solid grey it read as the wall not quite
reaching. Two courses of brick then the mortar keeps the wall's 2-and-1 rhythm
and puts something solid against the bar.

**The pillars are deliberately NOT aligned between floors.** Making them line
up was tried and reverted: it is a different building, and it was not what the
edge problem was about.

**AND THEN A FIXTURE ERASED THE CAP AGAIN -- ONLY ON THE ESCALATOR SCREENS.**
`beam_clear` exists to pull a beam top down when a radio or a prize stands
where one would hang (6f, point 2), and it cleared **all four** cap characters.
Two of those are not caps at all: `SLABE` and `ROOFSE` are written by
`beam_tops` at column 0 and column 31 and nowhere else -- read the two edge
tests -- and there they are the **building's outside wall**. Clearing them
replaced the brickwork with a plain bar and the storey above stood on nothing
at the extreme edge of the screen.

It could only ever appear on an **escalator screen**, which is exactly how it
was reported -- one side, then mirrored on the other. The flight fills the
middle of an escalator band, so that screen's radio or prize is pushed right
out against the end wall; on every other screen no fixture sits close enough
for the two-cell clear at `#bca` and `#bca+1` to reach column 0 or 31. That is
also why four rounds of reading the tables found nothing: **the templates, the
beam-column table and the draw order were all correct**, and the damage was
done afterwards by a routine whose whole purpose is to remove structure.

`beam_clear` now handles `SLABP` and `ROOFSP` only. The distinction is
provable rather than positional: a pillar cap is something a fixture may stand
in front of, an end-wall cap is permanent structure, and the character code
already says which is which.

**AND THE SAME FAULT SAT ONE ROW LOWER.** Clearing the *cap* was only half of
it: a radio or a prize also blanks the two cells directly above itself, to take
down the upper half of the pillar it covers, and that was an unconditional
green `VPOKE`. Correct for a pillar; at column 0 or 31 it painted over the
outside wall, and on the roof it would have punched green through the skyline.
`wall_clear` replaces it and tests for the thing it is allowed to remove --
`COUNTR`, a pillar or a counter -- rather than trusting the position.

**AND THE ONE THAT WAS ACTUALLY BEING REPORTED WAS NEITHER.** The ground
floor's outside wall stayed missing after both of the fixes above, on screens 0
and 7 only, mirrored side to side. Probing the name table said it was there --
four separate times, at draw and every frame, cap and body. It was: the cell
held `ENDWALL` throughout. **The GLYPH was empty, and only in one screen
third.**

`scan_wipe` blanks the radar canvas by writing zeros into the pattern table's
bottom third, whose base is `4096 + SCAN_FIRST*8`. That was hand-computed as
`4096 + 160*8` when `SCAN_FIRST` was 160; art added later moved it to 208 and
nothing moved this with it. So the wipe zeroed the 48 characters *below* the
canvas and never touched the canvas at all -- and two of those are structure:
`ENDWALL` (the outside wall) and `SLABP` (a pillar's cap). It also took the
bottom halves of a suitcase prize.

Rows 16-23 are the bottom third, so a character blanked there draws perfectly
in bands 1, 2 and the roof and falls back to its own background colour on the
**ground floor**. `ENDWALL` appears on screens 0 and 7 and nowhere else, which
is precisely why it presented as "only the escalator screens". The ground
floor's pillars had been losing their brick cap the same way, on every screen,
for as long.

Three lessons, all of them expensive:

* **A probe that copies a character somewhere else to look at it cannot see
  this.** The HUD is the top third, so the copy rendered from a different
  pattern and looked perfect while the original was blank.
* **A raw VRAM address is a character code in disguise.** `renumber.py`
  rewrites every `CONST CH_*` from genart's tables, which is exactly why this
  one -- an address, not a constant -- went stale silently. It now maintains
  the `scan_wipe` base too, and `checkstruct.py` fails the build if the two
  disagree.
* **"The name table is correct" is not "the screen is correct."** Four rounds
  of reading templates, tables and draw order all came back clean because the
  drawing was clean.

**AND ONE OF THEM WAS VISIBLE AS A FLICKER, NOT AS A HOLE.** `draw_screen` blits a band and
then corrects it in the same pass, and the raster does not stop in between. The
`WAIT` sat at the *end* of the loop body, so a band's burst began wherever the
CPU happened to be in the frame; if the beam passed those rows between the blit
and the correction, the uncorrected band was shown for a frame. After `CLS` at
round start that reads as a support beam appearing and being rubbed out. The
`WAIT` is now at the **top** of the body, so every band's burst starts at
vblank with a clear run at its own rows -- and each band still gets its own
frame, which is what keeps a VDP write burst from being silently dropped.

### 6j. Hazards: one decision, made when the screen is drawn

No sprite hazard stands on the floor the crook is standing on. Radios are
exempt -- they are characters, they do not move, and a fixture he runs past is
not what the rule is about.

**THE DECISION IS MADE IN `load_band` AND NEVER REVISITED.** It began as a test
in the draw loop and another in the collision test, both re-evaluated every
frame, so the hazards came and went as Harry walked on and off the screen: run
him to the edge and a floor's worth of balls appeared out of nothing behind
him. A rule about what a screen CONTAINS cannot be a per-frame question,
because the answer changes while the player is looking at it.

Zeroing the kind at load also made both tests unnecessary -- an obstacle that
was never loaded cannot be drawn and cannot hit anybody -- and the version with
one decision is thirty bytes SMALLER than the version with two guards.

### 0m. What the video actually measures

Everything below is measured off the longplay, not inferred. The calibration
first, because every number depends on it:

* the playfield is **456 video px** wide and that is our **256 px**;
* a band is **51 video px** tall and that is our **40**;
* the capture is **30 fps** against a 60 Hz console, so **one video frame is two
  console frames**.

#### The timer is not seconds -- it is a unit of about two seconds

It counts **50 down to 0**, and a unit lasts **59.75 video frames = 1.99 s**.
Measured twice, independently:

1. **Directly.** 50 at frame 360, 49 at 420, 48 at 480, 47 at 540, 46 at 599 --
   239 frames for four ticks.
2. **End to end.** Finding every frame whose timer reads 50 gives five round
   starts in the sample; the gaps are 83.8, 52.8, **98.5**, 65.8 and 82.7 s.
   A full 50-unit round at 1.99 s is **99.5 s**, and the longest observed round
   is 98.5 -- a round that nearly timed out. The short ones are Harry caught
   early.

So the manual's "50 seconds" is 50 *timer units*, and a round is about **100
seconds** of play. The digits are a count, not a clock.

#### The speeds already match -- because they are paced per PASS, not per frame

The reference Kelly covers **102 px/s**. Ours covers **~100 px/s**, and the
arithmetic that gets there is the thing to understand, because reading the
constant alone gives the wrong answer twice over:

> `WALKSP = 4` is **4 px per LOOP PASS**, and the loop runs at about **25
> passes a second**, not 60. So Kelly's real speed is 4 x 25 = 100 px/s.

An earlier draft of this section read `WALKSP = 4` as px per *frame*, concluded
we ran 2.35x too fast, and recommended no change on the grounds that a 2x-fast
clock cancelled it. **Both halves of that were wrong.** The speeds were never
fast; the clock alone was.

| object | reference px/frame | as a fraction of reference Kelly | ours, as a fraction of our Kelly |
|---|---|---|---|
| shopping cart, roof | 0.80 | 0.47 | 0.25 - 0.75 |
| shopping cart, floor 1 | 1.21 | 0.71 | (same range) |
| beach ball, horizontal | 0.82 | 0.48 | (same range) |

A cart runs at roughly half the player's speed in both games, so **the object
speeds need no change**. The **clock did**, and it was not cosmetic.

#### The clock was the one thing out of step, and it made the round unfinishable

Everything that moves is advanced once per loop pass. The timer is the one
thing paced by the frame **delta** -- i.e. in real seconds. At 60 frames a unit
a round was 50 real seconds, and Kelly's route to the roof takes **72**. The
clock ran out before either man could get near the roof, so every round ended
on a timeout and Harry's escape -- one of the game's two loss conditions --
could never happen at all.

`checkchase.py` reported this as healthy on every run, because it converted
both routes with `FPS = 60`. Halving a number on both sides of a comparison
leaves the comparison intact, which is exactly why the bug was invisible: the
margin between Kelly and Harry was right, and only their relationship to the
*clock* was wrong. It now models **25 passes/s** and reads `TICKFR` for the
real round length:

| | before (FPS=60) | now (25 passes/s, 120-frame unit) |
|---|---|---|
| Kelly to the roof | 30.1 s | **72.2 s** |
| Harry escapes at | 40.2 s | **96.4 s** |
| round length | 50 s | **100 s** |

And that is the reference: five measured rounds ran 83.8 / 52.8 / **98.5** /
65.8 / 82.7 s against a 100 s cap, with the longest one nearly timing out --
which is precisely a Harry who escapes at 96.4 s.

**The lesson for any future checker here:** a ratio test cannot catch a units
error. Both actors were converted with the same wrong constant, so every
*relative* assertion still passed; it took comparing them against something
measured in different units -- the clock -- for the mistake to show.

#### The advancement arithmetic, in the units that matter

At 102 px/s a reference screen takes 2.51 s, so a floor of eight screens is
about 20 s and a 100 s round buys **five floor-traverses**. Ours, at ~100 px/s
and a 100 s round: 2.56 s a screen, 20.5 s a floor -- **4.9 traverses**. The
same game. That is the number to hold constant if the speeds are ever retuned:
not px/frame, and not seconds, but *floor-traverses per round*.

Note what this makes fragile. Movement is per pass and the clock is per second,
so **the loop rate is a difficulty dial nobody declared**: at 20 passes/s (the
west screen) Kelly covers 80 px/s and the same round buys 3.9 traverses. Frame-
pacing the actors would remove that, at the cost of re-tuning every speed to
px/frame and re-deriving the chase; it is not done here, and this is where to
start if it ever is.

#### Objects on the roof

A shopping cart was tracked crossing the **roof** band at 0.80 px/frame, so the
roof is not a clear run -- it carries obstacles like any other floor, and 0k2's
first version (which emptied it) was wrong. Restored as **carts only**: a cart
costs time, and the roof is where the round is decided, so the one hazard that
costs a whole Kop stays off it.

#### What this pass did NOT establish

No ducking frame exists in the sample (0k), and the reference's own biplane is
a blob rather than an aeroplane (0n). Screens-per-floor and escalator placement
were not re-measured here; those remain as recorded in section 4.

### 0n. The aeroplane, and the policeman's helmet

**The plane is drawn from above.** Zoomed off the video the original is a small
dark-green body with a light-green dashed arc over it -- at 2600 resolution
that is all there was room for, and copied literally it reads as a bug. Three
attempts at a side-on biplane failed for a reason worth recording: a side view
needs two wings, two struts, a fuselage and a fin, and at sixteen pixels those
collapse into **three parallel bars that read as a grid**. From above an
aeroplane is one shape -- a long fuselage with swept wings and a nose that runs
out ahead of them -- and nothing else on screen resembles it.

**And it is two colours after all.** A TMS9918 sprite has one colour, so a
dark-green body with a light-green propeller takes two sprites, and all sixteen
slots were spoken for (0-3 Kelly, 4-7 Harry, 8-15 obstacles). The way through
is **priority**: the VDP drops the *highest-numbered* sprites on an overfull
scan line, so the propellers live in slots **16-23**. When Kelly, a plane and a
high beach ball share a line -- the only case that exceeds four -- what
disappears is a propeller, which is decoration, and never the plane the player
has to duck. The body no longer carries the prop, so it is one pattern per
facing instead of two, and the two prop phases cost only two patterns net.

**The Kop wears a custodian helmet.** The reference is inconsistent with
itself: the figure on the playfield wears a flat-brimmed bowler, while the HUD's
spare-Kop icons are unmistakable **bobby helmets** -- a tall dome with a boss on
the crown and a modest brim. Both now follow the HUD, because that is the one a
player reads as a policeman. The old HUD icon was a whole little figure and at
eight pixels it read as an animal; a silhouette that small has room for exactly
one idea, and the helmet is the one that says Kop.

### 0k2. Roof obstacles, and beams that reach the floor above

Two things the reviewer caught in the same pass, both of which are about what
the screen *says* rather than about what it computes.

**Carts on the roof, but not biplanes.** The roof band used to draw from a
palette of two biplanes, and emptying it entirely was an over-correction -- a
cart was later tracked crossing the roof in the reference (0m). It is still the
band where the chase is decided rather than survived, so the palette is carts
only: a cart costs nine seconds, a biplane costs a Kop, and a kill arriving in
that window turns the finish into a coin toss the player cannot see coming.

**Support beams have to reach the floor they hold up, and that floor is not in
their own band.** A beam fills its band's four air rows, so its top pixel sits
directly under the *slab row of the band above*; a slab row is five pixels of
bar over three of green (see `SLAB`), so every beam stopped three pixels short
of the bar. It did not read as a rounding error, it read as a beam that misses
the floor.

It cannot be drawn into either template. The beam belongs to the band below and
the row belongs to the band above, and the two templates are chosen
independently per screen, so **no template knows both**. So the band blits go
down first and `beam_tops` stamps the tops afterwards from a per-template column
table (`stor_pil`) -- the same shape as the escalator's head cap, and for the
same reason. The stamped character is `SLABP`: the floor bar with those three
green rows in the beam's grey instead.

Bands 0 and 1 only. Band 2's top row is the roof deck, which is grey over grey
with no green to bridge, and the roof has no band above it at all -- which is
exactly the two floors the reviewer named.

`assets/preview.py` models the stamp. A previewer that painted straight out of
the templates would still show the gap, which is the §0i lesson again: a check
narrower than the thing it checks reports success.

### 0l. The jump is ballistic

The stick used to steer him in mid-air, because the running block ran during
`ST_JUMP` like any other state. That is not a jump, it is flight -- and it also
let him flip which way he was *facing* halfway through an arc. The horizontal
direction is now latched at take-off (`kjdx`) and the stick ignored until he
lands.

---

### 0i. Why the escalator screens ran slow

Reported from play: on the two screens with a staircase the running looked
slower and the footsteps dragged, with the timer possibly unaffected.

All three parts of that are explained by one line. `esc_tick` is **the only
per-pass work unique to screens 0 and 7**, and it was rewriting all fifteen
animated cells — 120 bytes of pattern table — every pass. That pushes a pass
past one frame, so `fdv` rises above 1 there and nowhere else.

- The **timer is not slower**: `tick_timer` counts down by `fdv`.
- **Movement is not slower** either, for the same reason.
- But `kanim`, `sfw` (the footstep period), `hanim` and `sct` all counted
  **passes**, so the legs, the footsteps, Harry's legs and the radar all
  stretched out exactly where the loop was heaviest. They count `fdv` now.

And the cause itself is halved: only one flight direction is ever on screen —
screen 0 carries a west one, screen 7 an east one — so genart groups the moving
cells **west then east** and `esc_tick` writes only this screen's half. 72 bytes
on the west screen, 48 on the east, down from 120.

`escp` itself stays per-pass and must: a four-phase cycle stepped by more than
one aliases, and the rider is locked to it (§0f).

**AND THE WEST SCREEN COST HALF AS MUCH AGAIN, because it carries TWO
flights.** Not because two staircases are twice the work -- they share their
patterns -- but because the two cross *different surfaces*: floor 1's flight
crosses into a shop floor and floor 3's into the roof, so it needed both the
BAR composites and the DECK ones. Nine animated characters against the east
screen's six; 216 bytes a pass against 144.

The two composite sets are **pixel-identical**. They are the same flight over a
different background, and they differ only in colour -- and **they are never
wanted in the same screen third**: a roof crossing is screen row 5 and a shop
one is row 10 or 15. The TMS9918 colours each third from its own table, so one
character can be the deck up top and the floor bar lower down. `DEFINE COLOR`
paints them as the bar in all three thirds and `esc_deck_col` repaints third 0
as the deck, once, at setup. Six characters either side now, and the whole
store table lost six entries with them.

That invariant is the price of the trick, so `checkesc.py` gates it: it reads
the band rows and the escalator sides out of the source, works out which third
each crossing lands in, and fails if a roof one and a shop one ever share.

**MEASURED, and the headline is not the escalator.** A debug pass-counter on the
HUD says the loop runs at **24-26 passes a second everywhere**, dropping to
**20** on the west screen with two flights. So the game is at ~25 Hz, not 60,
and `fdv` is about 2.4 all the time; the escalator costs a further ~20% on top
of that. Everything paced by `fdv` -- movement, the timer, the animation and
footsteps since this section -- keeps correct wall-clock time regardless. What
does not is anything locked to the pass: the steps and the rider, which
therefore run at 25/60 of their intended speed. **That is the residual
sluggishness, and closing it means raising the loop rate itself**, which is a
profiling job on the whole main loop rather than anything escalator-specific.
`define_char` compounds it: in bitmap mode it calls LDIRVM3, the *triple* copy,
so nine characters is 216 bytes of VRAM per pass and not 72.

---

### 0c. Second video pass — the escalator, and why the roof hid the player

**The escalator was the worst-looking thing in the store, and the video says why.**
It was drawn as a *solid diagonal wedge* with a stippled body — a filled
triangle, which reads as a ramp or a wall. The reference draws an **open
flight**: a run of chunky **white step treads** descending between thin rails,
with a flat landing and a long **black horizontal rail** at the top end. It is
now four flight characters (a pair per row — the flight drops 8 px per 16 px
across, so each row is an upper-half and a lower-half character) plus one rail
character. The rails themselves are dropped: they are dark green in the
reference, and with two colours per scan line the row's second colour is better
spent on the treads, which are what make it read as an escalator at all.

**The ride went straight up, because only one axis was ever interpolated.**
Boarding snapped `klx` to the destination and then the ride interpolated `y`
alone, so Kelly teleported sideways and rose *vertically* — visibly beside the
staircase rather than on it. He now boards at the foot and stays there, and
`move_kelly` walks him along the flight: the flight's ends are 48 px apart and
the floors 40 px, over a 40-frame ride, so **y moves 1 px a frame for all 40 and
x moves 2 px a frame for the first 24** (= 48 px) and then holds. Those last 16
frames are the **flat landing** at the head, which the reference draws as a real
part of the escalator. Down is the same ride mirrored: board at the head, travel
to the foot.

**The flight is a black band with white treads.** Dark green on medium green was
tried first, to match the reference's dark outline, and the TMS9918's two greens
are close enough that the band was effectively invisible — the flight read as a
dotted white line floating on the floor. Black gives the ribbon the contrast the
reference gets from its outline, and it matches the landing rail, which is
already black.

**The band came back off again.** A dense frame burst (`fps=10` over the ride)
settles what a single frame could not: the flight's interior is **store green**
with white step wedges in it, inside a thin dark outline — it is an *open*
staircase, not a filled ribbon. The black band was heavier than anything
actually on screen. It is now two-pixel white treads and risers on green,
which reads as steps at 1× where the earlier 4×2 dashes read as a dotted line.
The same burst also shows the **steps do not scroll** — no step animation is
needed, which is worth knowing before building one.

**DARK GREEN IS NOT A COLOUR ON THIS MACHINE, NOT NEXT TO MEDIUM GREEN.**
TMS9918 colour 12 is (33,176,59) and colour 2 is (33,200,66) — 12% down in the
green channel, identical in red and blue. Twice now the reference's "darker
green than the store" was copied literally and twice the thing simply vanished:
first the escalator band, then the elevator shaft. Where the reference uses dark
green *against* medium green, use **black** — it keeps the relationship (this is
the dark thing in a green wall) with contrast the hardware can deliver.

That the two greens do not read as two colours is exactly why the store's own
ground could be moved from 2 to 12 (§0d-bis) without redrawing anything: it is a
change of *shade*, not of colour. The pair is unusable as a contrast and
perfectly good as a single darker ground. Both statements are the same fact. The shaft is black, the car cyan, and the shaft now runs
the **full** band height as the reference draws it rather than starting a row
down.

**Moving the art moved the boarding zones.** The old filled triangle covered the
whole lower corner of the band, so the boarding zone was the whole corner. The
stepped flight occupies two characters per row, so the foot is now columns 7–8
(west) / 23–24 (east) and the zones are those columns. Leaving the zone where it
was would have put the player on a staircase that is not under them — silent,
and it would present as the floor teleporting you at a random spot.

**The roof was sky all the way down, and that made Kelly invisible.** The sky was
`DBLUE`, which is *exactly* `C_KELLY` — his tunic colour. On the roof, the one
place he is silhouetted against sky rather than against the green store, he was
drawn in the background colour. Two fixes, both needed: the sky is now **cyan**
(the reference's own), and the roof band is now layered the way the reference
layers it — **sky, then skyline, then a grey backdrop, then the deck** — so the
figure stands against grey at the height he actually occupies rather than
against open sky. Every roof screen carries a full row of skyline: a horizon is
not an ornament at one end.

**Where the sources disagree**

1. **Bonus multiplier bands.** The AtariAge manual gives Krooks **1–8 / 9–16 / 17+** for
   ×100 / ×200 / ×300. A secondary summary gives **1–9 / 10–15 / 16+**. → We take the
   manual: **1–8 / 9–16 / 17+**.
2. **Three floors or four.** Wikipedia says "four floors"; PixelatedArcade says "three floors
   and a rooftop" — the same building counted two ways. → **Three shopping floors and a
   roof.** Four bands on screen, but the roof is not a shopping floor: it has no aisles, no
   obstacles on the ground and no escalator onward. It is the escape.
3. **Biplane penalty.** One summary of the AtariAge manual attributes the 9-second penalty to
   biplanes as well. Three independent sources say a biplane **kills**. → Biplanes kill.
   This matters: it is the only thing in the store that does.
4. **Escalator direction.** No source states whether escalators run down as well as up. →
   **UP ONLY.** This was briefly built both ways and then taken out again at the
   reviewer's direction. Removing it also removed a re-boarding lock that existed solely
   because stepping off at the head left you standing in the zone that rode the same
   flight back down; with no down ride there is no such zone, because a floor's escalator
   is at the opposite end from the one below it. The elevator is the only way down.

**Deliberate deviation, at the reviewer's direction:** the arcade view *scrolls*
horizontally. Ours **flips** — the store is eight discrete screens and crossing an edge blits
the next one. §2a records what that costs and what it buys.

---

## 1. Performance budget (decided before line 1 — `CLAUDE.md` §5A)

| term | value |
|---|---|
| Loop | **Real-time, one `WAIT` per frame**, 60 Hz on both machines. No pacing constant. |
| Simultaneously moving actors | **10 max** — Kelly, Harry, and ≤2 obstacles on each of 4 bands. |
| Per-actor work | **O(1)**. Constant velocity plus one add. No search, no pathfinding. |
| Harry's AI | **Two comparisons.** He runs at this floor's up-point and climbs. He never reconsiders. |
| Per-frame VDP **reads** | **ZERO.** There is no tile map to consult — see below. |
| Per-frame VDP **writes** | Sprite attributes only. HUD digits when a digit changes; scanner dots when a dot moves. |
| The big blit | **4 × 160 chars, only on a screen crossing** — a discrete event, never per frame. |

**Why there are no per-frame VDP reads.** A platform game normally asks the screen "what is
under my feet". This one never needs to: an actor's floor is its `lv` (0–3) and the surface
height is `FLOORY(lv)`, a four-entry table. Obstacles are a RAM array compared arithmetically
against Kelly. The store's *appearance* lives in VRAM; the store's *physics* is four numbers.
That is the same trick that keeps Joust cheap, and it is why the Ms. Pac-Man trap (actors ×
per-actor search) is absent by construction rather than by tuning.

**Why the flip is cheap where RallyX's pan was not.** RallyX repaints 576 chars *every time
the camera moves one cell*, and had to have all its movement rewritten to advance to cell
boundaries to survive it. Here the repaint happens once per screen crossing — roughly once
every two seconds of running — so the per-frame budget never sees it at all. The cost of the
flip is paid entirely in fidelity (§2a), not in frame time.

---

## 2. The store

### Geometry

```
world = 8 screens × 256 px = 2048 px wide, 4 levels tall
```

Eight screens of exactly 32 columns is the load-bearing number. **A screen is 256 pixels, so
an actor's x within its screen is exactly one unsigned byte** — no 16-bit world coordinate, no
`#var` unsigned-compare split (`CLAUDE.md` §3A), no scaling anywhere. Position is
`(lv 0..3, scr 0..7, x 0..255)`. Crossing an edge is `x` wrapping and `scr` stepping.

Screens left to right, matching the reviewer's layout (given right-to-left) and
PixelatedArcade's "escalators at alternating ends, elevator in the centre":

```
 scr    0        1        2        3        4        5        6        7
     +--------+--------+--------+--------+--------+--------+--------+--------+
lv3  |  roof  :  roof  :  roof  :  roof  :  roof  :  roof  :  roof  |  ROOF  |  <- escape edge
lv2  |  ESC   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  esc   |  floor 3
lv1  |  esc   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  ESC   |  floor 2
lv0  |  ESC   :  aisle :  aisle :  ELEV  :  aisle :  aisle :  aisle |  esc   |  floor 1
     +--------+--------+--------+--------+--------+--------+--------+--------+
       west end                 elevator                            east end
                                                          Kelly starts here ^
```

**Three shopping floors and a roof.** Escalators stand at both ends, but **only the
capitalised one on each floor goes up**: floor 1 climbs at the **west** end (screen 0),
floor 2 at the **east** (screen 7), floor 3 at the **west** again.

**The store has ends, and they are walled.** The extreme column of screen 0 and of screen 7
carries a wall character on every floor. Without it the player runs into the edge of the
screen and the building appears simply to stop — which reads first as though they ought to be
able to keep going, and then as though the game has stuck them there. (It literally did: the
clamp used to park Kelly's 16 px sprite at x = 255, entirely off the right edge, where nothing
moved him back.)

Kelly starts at **screen 7, floor 1 — the east entrance**, which is the far end from floor 1's
escalator. So the climb from the street to the roof is **three full traverses of the store**,
one per floor, and the alternation is what makes each of them full-length:

```
floor 1   east entrance  ->  west escalator      traverse 1
floor 2   west landing   ->  east escalator      traverse 2
floor 3   east landing   ->  west escalator      traverse 3
roof      west landing   ->  east edge           Harry's escape, and the last chase
```

Getting the alternation backwards would land Kelly on floor 1's escalator at spawn and cost
only *two* traverses — the store would be a third shorter than it looks. **The roof's escape
edge is at the east**, opposite the escalator that lands on it, so the rhythm carries through
to the last run.

That is what "alternating ends" buys, and it is the entire reason the elevator is worth the
walk to the middle: **the elevator is the only way down, and the only shortcut** — one ride
from the centre replaces a traverse and a half.

Harry starts at **screen 3, floor 2, at the elevator door.**

### Rows

24 rows, and every one is spoken for:

```
row  0        HUD:  SCORE 001250            TIME 43        Kops as icons, right
rows 1– 5     lv3   ROOF          4 rows of air + 1 surface row
rows 6–10     lv2   FLOOR 3
rows 11–15    lv1   FLOOR 2
rows 16–20    lv0   FLOOR 1
rows 21–23    SCANNER   16 chars × 3 rows, centred
```

A band is **5 rows = 40 px**: four rows of air over one surface row. Standing Kelly is 16 px,
so he has **16 px of headroom** — enough for a 14 px hop and nothing more, which is exactly
the margin the `platformer-jump-headroom-ceiling` note says to design for rather than
discover. Two consequences follow from it, and the art must respect both:

- **Ground obstacles are 8 px tall**, drawn in the bottom half of their 16×16 sprite box.
  A 14 px jump clears a cart with room to spare.
- **Biplanes fly with their bottom edge 16 px above the surface** (hitbox 16..22). Standing
  Kelly (24 px) is struck; ducking Kelly (11 px) passes five pixels under. The duck is not a
  dodge, it is a height change. A biplane is **not** jumpable — the apex is 14, under the
  plane, so a jump puts Kelly's body straight through it. See §0k for why 16 is the ceiling.
- **Beach balls move through both windows**, which is what makes §5a the tightest arithmetic
  in the game: the jump arc and the duck gap have to meet without leaving a height at which
  the ball cannot be avoided at all, and the arc is capped below standing height so no ball is
  ever free.

### 2a. The flip, and what it costs

Crossing a screen edge sets `scr`, then blits. The reviewer's call, and it is defensible: the
per-frame budget never pays for the store at all. What it costs is that **Harry can be one
pixel off-screen and completely invisible**, where the arcade's scroll would have shown him
coming.

That is not a hole — it is why the **scanner exists**, and the manual already treats the
scanner as a first-class instrument rather than decoration. With a flip, the scanner is
promoted from "nice overview" to **the primary instrument for locating Harry**, and §6 sizes
it accordingly.

**Hysteresis is mandatory.** Crossing right at `x = 255` must set `x = 8` on the new screen,
not `x = 0` — otherwise a step back left re-crosses immediately and the store re-blits every
frame at the seam. Crossing left at `x = 0` sets `x = 247`. The 8 px dead band is four times
one frame of running (2 px), so a seam can never oscillate.

### 2b. How a screen is drawn — about 1 KB for the whole store

Storing 8 screens × 20 rows of literal char codes would be 5,120 bytes of the scarce budget.
Instead the store is **band templates**: one 5-row × 32-col strip = 160 bytes, plus a
**32-byte index** saying which template each `(scr, lv)` uses.

```
templates:  T_AISLE_A  T_AISLE_B  T_ESCALATOR  T_ELEVATOR
            T_ROOF  T_ROOF_ESC (west landing)  T_ROOF_EDGE (east escape)
            7 × 160 = 1,120 bytes  +  32-byte index  =  ~1.1 KB for the entire store
```

Drawing a screen is **four `SCREEN` blits** (one per band, template → its 5 rows), then a
handful of `VPOKE`s for what is per-screen rather than per-template: the collectible bags and
the elevator car's position in its shaft.

Two rules this must obey, both from `CLAUDE.md` §3A and both silent when broken:

- Every template block is **even-length by construction** (160 is even), so no word table
  after it lands on an odd address and reads back shifted by a byte for ever.
- A `VPOKE` target is a **raw VRAM address** — name table at **6144** — and 6144 is added as
  **its own statement**, never folded into a constant expression.

---

## 3. Kelly

**Kelly and Harry are 24 px — two sprites tall**, a 16 px top sprite with the top half of a
second one below it. At 16 px they read as tokens rather than as a policeman chasing a crook.

| state | height | how |
|---|---|---|
| Running | 24 px | stick left/right, **4 px/frame** (240 px/s) — see §4a |
| Standing | 24 px | no input |
| Jumping | 24 px | button; 14 px apex, 30 frames, **9 of them at the apex** |
| Running jump | 24 px | button + direction; same arc, keeps horizontal speed |
| Ducking | 8 px | stick back; cannot move horizontally |
| Riding | 24 px | on an escalator or in the elevator car — **input ignored, invincible** |

**The height was checked against the arithmetic before the art was drawn.** A band gives 32 px
of air over the floor line, *plus* the 7 px of the ceiling row that sits below that row's 1 px
slab line — 39 px of real headroom. A 24 px figure with a 14 px jump needs 38. It fits with one
pixel spare, and every window in §5a is unchanged: jumpable at a ball height ≤ 8, duckable at
≥ 6, three pixels of overlap, nothing free below 22.

**The apex could not be traded for the height.** Dropping the jump to 10 px to "make room"
opens a **dead band at 5**, where the ball is neither jumpable nor duckable. So 14 is
load-bearing, and the only reason that was caught before it shipped is that the numbers were
swept rather than eyeballed (`assets/checkball.py`).

**Two sprites do not double the scanline cost.** The halves never share a scanline with each
other, so a band still carries Kelly 1 + Harry 1 + two obstacles = four, the VDP's limit.
Kelly holds slots **0 and 1**, Harry 2 and 3, obstacles 4–11 — lowest slots to the things that
must never be dropped.

Vertical motion is **8.8 fixed point with velocity biased +32768** — the Joust convention, so
no comparison ever crosses zero and every `#var` compare stays safely unsigned
(`cvbasic-unsigned-16bit-compares`).

Landing is a single test against `FLOORY(lv)`. No ground query, no tile lookup.

**The arc is 30 frames with a nine-frame plateau at the apex.** The first version was 24
frames that touched 14 for only four of them, which made every jump a timing test rather than
a decision — leave the ground on the wrong frame and you clipped the thing you were jumping.
Widening the plateau rather than raising the apex keeps §5a's arithmetic intact (that depends
on the apex being exactly 14) while making the window forgiving: the player still has to
*choose* to jump, but no longer has to be frame-perfect about it.

**Kelly is sprite 0.** Flicker stays **off** — CVBasic's flicker is all-or-nothing and would
rotate Kelly along with everything else (`cvbasic-flicker-is-all-or-nothing`) — and the VDP
drops the highest-numbered sprites on an over-full scanline, so being sprite 0 means Kelly is
the one thing that can never disappear.

---

### 3b. Three sprites per actor, one colour per row

Kelly and Harry are each **three sprites**, one per colour band: hat+tunic,
face, trousers. A TMS9918 sprite carries exactly one colour, so that is the
only way to get three colours into a figure.

**The VDP counts sprite BOXES per scanline, not pixels.** A 16×16 sprite
occupies all sixteen of its scanlines whether or not those rows contain
anything, so "the overlaps are empty" buys back nothing. Three 16 px boxes
stacked inside a 24 px figure therefore overlap three deep somewhere, and Kelly
plus Harry would be **six boxes on the lines where they meet** — the endgame
chase — with two silently dropped.

**But a box only has to cover the rows its band uses, and the `y` is free.**
The first version parked every band at the figure's top, so all three boxes
spanned rows 0–15 whether they had anything there or not — three boxes per
actor, six for a meeting, and one band had to be sacrificed. Pushing a band's
pattern to one end of its box (`shift()` in `genart.py`) and drawing the sprite
at the matching offset makes the box cover only its own rows:

| actor | band | drawn at | box covers |
|---|---|---|---|
| Kelly | hat (black) | `y−13` | −13…2 |
| Kelly | face | `y−10` | −10…5 |
| Kelly | tunic (blue) | `y+6` | 6…21 |
| Kelly | trousers | `y+16` | 16…31 |
| Harry | cap + body (white) | `y` | 0…15 |
| Harry | stripes (black) | `y` | 0…15 |
| Harry | face | **`y+3`** | 3…18 |
| Harry | legs | `y+16` | 16…31 |

Worst line of a meeting: **four boxes**, the hardware limit exactly, nothing
dropped. That is also why obstacles are suppressed on Harry's floor (§5): it is
load-bearing, not a kindness.

**Kelly's hat had to leave the tunic's sprite so Harry could have a striped
cap.** Harry striped from cap to hem means *both* his stripe colours run the
whole upper half, so both boxes span rows 0–15 and neither can be tucked out of
the way. That is only affordable if Kelly contributes just one box over the cap
rows — which he does once the hat is its own sprite (box −13…2) and the tunic
starts at row 6. Harry's face is then pushed *down* (`y+3`) rather than up, so
it clears the cap rows where the four boxes already are.

**The consequence is where the seams fall.** The top box holds only two
colours, and the face sits between the hat and the torso — so **hat and torso
must share a colour**:

| | rows 0–2 | rows 3–5 | rows 6–15 | rows 16–23 |
|---|---|---|---|---|
| Kelly | **black** hat | skin | blue tunic | blue trousers |
| Harry | striped cap | skin | striped body | white legs |

**The black hat needed the elevator shaft fixed first.** The hat went blue for a
while because it shared a sprite with the tunic and the shaft was black, so the
Kop vanished in the one place the game most wants you to go. Both halves are
fixed now: the hat has its own sprite, and the shaft is **grey** — the
reference's dark green is indistinguishable from the store's medium green on
this VDP (§0c), so it needed replacing regardless.

`checkbands.py` fails the build if any band overlaps another on a pixel row, or
if two actors level with each other would ever exceed four boxes on a line.

**No eyes.** An eye drawn in black would put two colours on one row; an eye left
as a hole shows the green store through the face. The face is solid.

**`assets/checkbands.py` gates both builds.** It fails if any figure row carries
pixels from two of an actor's sprites, or if any scanline is covered by more
than two boxes — both of which are invisible in the source and present only as
"the sprite looks wrong".

---

## 4. Harry

Harry's whole brain is: **run for the roof, continuously.** Get to this floor's up-point, take
it, repeat; on the roof, run for the east edge. He is not patrolling — he is escaping, and
every frame he is not climbing is a frame he is losing.

**Exactly one thing changes his mind: Kelly arriving on his floor.** Then he stops heading for
the escalator and simply runs *away*. A thief who keeps walking calmly toward a fixed point
while a policeman closes on him is not a thief, he is a train.

Still two comparisons. The flee direction is "opposite whichever side Kelly is on", compared
screen-first then pixel-within-screen — there is no world coordinate to subtract (§2). Three
consequences fall out, none of them special-cased:

- Fleeing may carry him **toward** his escalator, in which case he climbs and clears the
  floor. Fine — he earned it.
- It may carry him **away** from it, into the end wall, where he is trapped. Also fine: that
  is the catch.
- He never stops trying, so it does not read as broken AI the way a fleeing *enemy* would
  (`difficulty-dial-must-not-invert-goal`). Running is what this character is **for** — the
  rule is about enemies that abandon their goal, and Harry's goal is to get away.

- He runs at a flat **1.75 px/frame** (105 px/s), at every Krook. Not 2, not a per-Krook
  ramp — §4a is the whole reason, and it is arithmetic rather than taste.
- He rides **escalators** exactly as Kelly does, standing on a step, 36 frames a flight
  less the animation phase (§0f). He does **not** use the elevator: the car is Kelly's
  shortcut and Kelly's alone, and it is the one asymmetry that pays for Kelly's much
  longer route (§4a).
- **He never goes down.** The chase is therefore a race up a zig-zag, and Kelly's only
  advantages are raw speed and the elevator.
- **He starts on the player's screen** (screen 7, floor 2), not at the elevator door the
  research names. The reason given here used to be that "the arcade shows you the crook the
  moment the round begins" — **and the video says it does not**: at a round start the 2600
  shows Kelly alone on the ground floor, with the crook nowhere on screen and findable only
  on the scanner. So the honest reason is the flipped view (§2a): screen 3 would put him
  four screens away and invisible for the opening seconds, and this port has no scroll to
  soften that. It is a deliberate divergence, not a reading of the original.
- When fleeing, the side comparison carries a **16 px dead band**. Comparing raw positions
  makes him flip direction every time Kelly crosses his centre by a pixel, which on screen is
  not fleeing, it is a vibration — and it reads as the crook being broken rather than cornered.
- Kelly catches him by touching him: `|dx| < 12` on the same `lv` and `scr`.
- Harry reaching the east edge of the roof is an **escape**, and costs a Kop.

Difficulty is the **obstacle tables**, never Harry's speed and never a change of goal — an
enemy that stops trying reads as broken AI (`difficulty-dial-must-not-invert-goal`). Harry
always runs for the roof at the same speed, and it is the store that gets harder around him.
That is also the only dial the manual names: *"as your levels increase, so does the speed of
the obstacles."*

---

## 4a. The chase arithmetic — why 4 against 1.75

**A chase resolves on `path ÷ speed`, not on speed.** This is the one number in the game that
neither constant shows you, and getting it wrong does not look like a tuning problem — it
looks like the crook cheating.

Kelly ran 3 px/frame against Harry's 2. A 1.5× advantage sounds comfortable. It was not:

```
Kelly   east entrance -> west esc -> east esc -> west esc -> roof edge
        1984 + 2008 + 1992 + 2008  =  7992 px  + 3 rides   =  46.4 s at 3 px/frame
Harry   spawn -> east esc -> west esc -> roof edge
         104 + 1992 + 2008          =  4104 px  + 2 rides   =  35.5 s at 2 px/frame
```

**Kelly lost the race to the roof by eleven seconds, every round, at every Krook.** Harry
spawns *beside* floor 2's escalator (§4, and it is the right call — you have to be able to see
what you are chasing), so he skips a traverse and runs 4,104 px where Kelly runs 7,992. The
route is **1.95× as long**, so a 1.5× speed advantage is not an advantage at all. Pursuit on
foot could never close, at any distance, given any amount of time. The elevator was not a
shortcut, it was the only way to win — and a player who mistimed the car had already lost the
round without being told.

The fix is Kelly at **4** and Harry at **1.75**:

| | route | rides | to the roof edge |
|---|---|---|---|
| Kelly, 4 px/frame, **by lift** | 1,121 + 863 + 2,008 px | 1 ride + a worst-case 12.8 s wait | **30.1 s** |
| Kelly, 4 px/frame, on foot | 7,992 px | 3 rides | 35.1 s |
| Harry, 1.75 px/frame | 4,104 px | 2 rides | **40.2 s** |

**10.1 seconds of slack.** One beach ball costs 9 s, so Kelly can absorb a mistake and still
make the catch. Harry escapes at 40.2 s against a 50-second clock, so *"escaped off the roof"*
stays the loss that actually happens and the timer stays the backstop behind it.

**THE LIFT IS PART OF THAT AND LEAVING IT OUT DISTORTED THE DESIGN.** This section, and the
check, used to charge Kelly the full on-foot route and nothing else. That is not a
conservative assumption — it is a route no player takes: the shaft is on screen 3, *on his
way* from his spawn to floor 1's escalator, and it carries him two floors for the price of a
wait. Modelling only the foot route made the chase look 5 s tighter than it is, and that
phantom tightness was then used, right here, to argue the crook's speed down to 1.5. A check
that errs in the safe direction still shapes the design; this one shaped it wrongly.

**Harry's speed is still not the difficulty dial.** 2.0 — the ratio measured off the original
(§0f) — leaves 5.2 s, less than a single obstacle hit. There is no room in this geometry for
a per-Krook ramp on the crook, and the ramp that used to be described here (`HSPD(krook)`,
"closing on Kelly as the Krooks go by") was never implemented — which is the only reason the
game was playable at all. Difficulty ramps on the obstacles (`obsp`, and the ball arcs
of §5a).

**`assets/checkchase.py` checks all of it mechanically** and is wired into both build scripts.
It reads `WALKSP`, `hsp4`, both spawns, `stor_esc`, `ESCRISE`, the lift's timings and `TIMEL`
out of the source, walks Kelly's two routes and Harry's one, and fails if Harry is not slower
than Kelly, if Kelly's margin drops below 8 s, or if Harry can no longer escape inside the
timer. It was run against the old constants
first and correctly reports them as `-10.9 s` — a check that passes on the defect it was
written for is worse than no check (`check-scope-narrower-than-bug`), so it was tested against
the known-bad input before being trusted on the good one.

> Both actors move a whole number of pixels per **loop pass**, not per frame delta, so a
> stalled frame costs them equally and the race is unaffected. Harry's 1.5 is a **quarter-pixel
> accumulator** (`hsp4`/`hacc` in `move_harry`) spending 1, 2, 1, 2 px — `hx` is one unsigned
> byte per screen (§2) and has nowhere to keep a fraction, and `/` compiles to a real TMS9900
> `DIV`, so the fraction is carried in a variable and spent with two `IF`s.

---

## 5. Obstacles and collectibles

Obstacles belong to a **screen band**, not to the world: each `(scr, lv)` carries up to three,
and they run only while their screen is shown. That falls straight out of the flip model, and
it is what keeps the moving-actor count at 14 instead of 96.

**THE CROOK'S OWN LEVEL IS ALWAYS CLEAR.** No obstacle is drawn on, or may collide on, the
band Harry is currently on. Once you reach his floor the round becomes a foot race you can
actually see, and a biplane arriving in the middle of it takes the Kop for reasons that have
nothing to do with the chase — the one moment where a hazard is pure noise rather than a
decision. It is enforced in **two** places, the draw loop and `coll_obst`, deliberately: a
hidden sprite that can still kill you is the worst possible version of this.

| thing | motion | avoid by | cost |
|---|---|---|---|
| Shopping cart | rolls, 1–3 px/frame, wraps at the screen edge | **jump** | −9 s |
| Beach ball | rolls and **bounces** 8 / 10 / 12 px by Krook | **jump it low, duck under it high** — see §5a | −9 s |
| Cathedral radio | **stationary** | **jump** | −9 s |
| Toy biplane | flies at head height, 2 px/pass and 3 from Krook 8; **not before Krook 4**, and never on the roof | **duck** | **a Kop** |
| *(the roof carries **carts**, not biplanes — see 0m)* | | | |
| Money bag | static, on a surface | walk into it | **+50** |
| Suitcase | static, on a surface | walk into it | **+50** |

**One kind per band.** A floor carrying a cart *and* a ball asks two different questions at
once — jump this, read that one's phase — and the answer to one is the wrong answer to the
other. Two of the same thing is a floor with a rule; one of each is a floor with a trick. The
kind rotates by screen and level, so the store still varies; it just never varies within a
single stretch of floor.

**Obstacles wrap; they do not bounce.** An obstacle that turns round at the wall is a
pendulum — it has a near end and a far end, and the player learns to stand at the far one and
wait. Wrapping makes each floor a *stream*, so standing still is never the answer.

**They enter from the far side.** Kelly walks into a screen from one edge, so its obstacles
start at the *other* edge and run toward him: crossing a seam always presents oncoming
traffic rather than a set of backs to catch up with, and the direction he is travelling is
always the direction the danger comes from. The three slots are staggered a screen-third
apart so they arrive in sequence instead of as one wall.

**No hazards at all on screens 0, 3 and 7** — the two ends and the elevator. Those are where
the player has to stop and do something precise (board a flight, wait for a car), and a
rolling cart there is not difficulty, it is a toll on a manoeuvre the game has already
committed them to.

A hit costs 9 seconds. **One hit per contact, with a refractory period** — and both halves of
that are needed:

1. **The latch.** The overlap test is true on every frame the player is touching something, so
   with no latch a single clumsy cart charges nine seconds several times over. What the player
   sees is the clock jumping by 27, and the only available conclusion is that the penalty is
   broken.
2. **The countdown.** A latch that clears on the first non-overlapping frame is *still* not
   enough, and the case that breaks it is the **bouncing ball**: it lifts off the player
   between bounces, which is a genuine loss of contact, so someone standing under one is taxed
   on every bounce while being given no opening to do anything about it. Technically two
   collisions; in play, one situation.

So each obstacle carries a countdown rather than a flag. A hit sets it to `HITREF` (45
frames); it ticks down **only while the player is clear**, so contact holds it up and parking
inside something never earns a second penalty either.

There is **no blanket invulnerability window** — the refractory period is per obstacle, so a
second, different hazard still hits. The only true immunity is inside the elevator, which is
the one place the manual grants one.

**Two sprite constraints the art is designed around, not patched for later:**

- **Sprite size and magnification are GLOBAL on the TMS9918.** Every sprite in the game is
  16×16. A cart is not an 8×8 sprite; it is a cart *drawn 16 wide and 8 tall inside a 16×16
  box*. There is no mixing sizes, at all, ever.
- **Four sprites per scanline, and the fifth VANISHES** — it does not flicker, it is simply
  not drawn. This sets the obstacle cap, and the cap is **two per band, not three**.

  Three was the original number and it was wrong: it was sized against Kelly alone (1 + 3 = 4)
  and forgot that **Harry can be standing on that band too**. When he is, the fifth sprite on
  his scanline is the highest-numbered obstacle — which disappears while remaining perfectly
  solid. An invisible thing that costs nine seconds is the worst failure this game can have,
  and it happens *only when the crook is beside you*, which is exactly when you are not looking
  at the floor. Kelly (slot 0) + Harry (slot 1) + two obstacles = four, which is provably safe
  on any band in any situation.

  **The general lesson: a sprite budget has to be counted against every actor that can occupy
  the row, not against the one you were thinking about when you wrote it.**

### 5a. The beach ball — the only obstacle with two right answers

Every other hazard has one response. The ball's **changes with its height, and the two do not
overlap**: a low ball must be jumped, and **a high ball cannot be jumped at all** — you have
to go under it. That is the mechanic, and it is what makes the ball the only obstacle the
player has to *read* rather than react to.

Writing `Bb` for the ball's bottom edge above the surface:

| `Bb` | what works | why |
|---|---|---|
| 0–7 | **Jump — only.** | Standing or ducking is a hit. |
| 8–10 | either | the seam, three pixels wide |
| 11–14 | **Duck — only.** | 14 px of apex cannot clear it; standing is a hit |

**The arc is capped at `Bb` = 14 — two pixels below Kelly's standing height — so there is no
such thing as a ball you can simply run under.** Every ball costs an action, always; a high
ball demands a *different* action, not no action. Letting the apex reach 16 would make the
highest-bouncing balls — the late-Krook ones, the ones that are supposed to be the hardest —
completely free, which is the difficulty ramp running backwards.

So a ball bouncing high is not a harder jump, it is **not a jump**. The player who keeps
hammering the button on later Krooks keeps taking 9-second hits, and the answer is to stop
jumping and start ducking — which is the read the mechanic is asking for.

The three-pixel seam at 8–10 exists for exactly one reason: **without it there is a height at
which the ball can be neither jumped nor ducked**, and an unavoidable hazard is not difficulty,
it is a bug that feels like bad luck. The arithmetic that creates the seam:

```
jumpable   while  Bb + ball_box <= apex          ->  Bb <= 14 - 4  = 10
duckable   while  Bb            >= duck_height   ->  Bb >=  8
                                                     seam = 8..10, three pixels
```

Which forces three numbers to be chosen together, not tuned independently:

- **Jump apex 14 px**, against 16 px of headroom — 2 px short of the band ceiling, because an
  arc that bonks is silently truncated (`platformer-jump-headroom-ceiling`).
- **Ducked height 11 px.** (This block's arithmetic above still shows the 8 px crouch it
  was written against, and the seam it computes from it. The crouch became 11 px when it
  was redrawn to bend over rather than squash — see §0k — and at the shipped numbers there
  is **no seam at all**: jumpable while `Bb <= 8`, duckable while `Bb >= 9`, an exact partition.
  §6c has the current account, and `checkball.py` reads the real constants rather than any of
  this prose.)
- **The ball's collision box is 4 px tall inside an 8 px sprite** — inset 2 px top and bottom,
  in the player's favour. That inset is not cosmetic generosity: `apex - duck_height = 6`, so
  a box of 6 px or more collapses the seam to nothing and a box of 8 px opens a **dead band at
  `Bb` = 7** where neither answer works. The hitbox inset *is* the seam.

**Difficulty raises the apex, never the answer.** The three arcs are **9 / 16 / 20** px, and
which of them is in play is the whole of the ball's difficulty:

| Krook | apex | jumpable | duckable | met at |
|---|---|---|---|---|
| 1–4 | 9 px | 25 of 32 frames | 7 | the GROUND |
| 5–9 | 16 px | 11 | 21 | the APEX |
| 10+ | 20 px | 7 | 25 | the APEX |

The top of every arc is a duck, including the first, and **the taller the ball bounces the more
of its cycle that is**. Ducking is in the vocabulary from the opening screen; what the later
rounds add is how much of the bounce demands it.

**AND THEY WERE 9 / 10 / 12, WHICH IS THREE PIXELS ACROSS THE WHOLE GAME.** The apexes had been
chosen entirely by the frame split in that table — a real thing to tune, and the wrong thing to
tune alone, because what a player reads is **height**. Kelly is 24 px tall; the "tall" ball of
Krook 5 was **one pixel** taller than the short ball of Krook 1. Reported from play as *"I do not
see balls bouncing higher"* on Krook 8, and the report was exactly right.

`checkball.py` passed throughout, and could not have done otherwise: its question is whether every
frame of an arc is jumpable or duckable and none is free — **a question about one arc at a time**.
Whether the three are tellable apart is a property of the *set*, invisible to every check written
about a member of it. That is `checkanim.py`'s lesson in another subsystem: **rank on the closest
pair, not on each item alone.** `checkball.py` now measures the apex spread and fails under 4 px;
run against 9 / 10 / 12 it names the defect.

Arc 0 stays at 9 — it is pinned by the "a duck is in the vocabulary from the first ball" call,
reverted twice at the reviewer's word. The ceiling is `Bb ≥ 22`, where a ball becomes *free*
(clearable by a standing Kelly); 20 keeps two pixels off it.

**AND THE APEX WAS ONLY HALF OF IT — THE OTHER HALF WAS THE PHASE SEEDING.** Raising the arcs
did not stop *"it's easy to just keep running and jump over it"*, because the height was never
what made the tall ball jumpable. `ball_phase` seeds each ball's bounce so that it is at **phase
0 — on the ground** — exactly when Kelly reaches it. For a short ball that is the whole point:
it is the frame a jump clears, and it makes the encounter deterministic instead of the coin toss
it used to be. Applied unchanged to the tall arcs, it hands out a **free jump every single
time**, however high the ball bounces.

Half a cycle later is the apex, so the tall arcs now seed to **phase 16** instead. The property
that mattered is kept — the encounter is still deterministic and still readable on the approach —
and only the answer is inverted: *tall ball, duck*. A taller arc with the old seeding would have
changed nothing a player could feel.

**A FULLY JUMPABLE LOW ARC WAS TRIED AND REJECTED.** At apex 8 the band is 10..14, and the hit
test `kfh < oht` makes 14 < 14 false, so the jump clears it and the low arc becomes jumpable on
all 32 frames. The published guides do read that way — level 5 is where "the balls start to
bounce higher", and the advice there is "don't jump over the beach balls when they bounce high
up". The call here went the other way, twice, and it is the reviewer's: **the duck belongs in the
vocabulary from the first ball**, and later rounds should add more of it rather than the first
sight of it. Recorded so it is not re-derived from the guides a third time.

The ball never stops being avoidable and never becomes free; it stops being avoidable the *same
way*, which is a dial that raises what the player must read rather than taking the answer away
(`difficulty-dial-must-not-invert-goal`).

**The low arc used to be 4 px, and that was a bug wearing a number's clothes.** A ball that
barely leaves the floor looks nothing like the original and gives the early game nothing to
read — but it was the only height the *old* jump could reliably clear, because that arc
touched its apex for four frames and anything taller demanded a frame-perfect take-off. The
ball height was never the problem; the jump was. Once the jump held 14 px for nine frames the
balls could go back to bouncing properly. **Worth noticing as a pattern: a value tuned down to
compensate for a defect elsewhere looks like a considered choice forever after, and nothing
points back at the real cause.**

**A high-bouncing ball still comes down.** Its arc touches the surface every period, so the
jump band is never gone — it is just brief, and it arrives on the ball's schedule instead of
the player's. That is the whole difficulty of a late-Krook ball: the answer is time-varying,
and running at one without reading its phase means arriving during whichever window you
weren't prepared for.

**The bounce has to be legible.** A ball whose phase cannot be read in the ~15 frames before
contact is a coin flip, so the arc is slow and tall rather than fast and shallow, and its
period is fixed per Krook rather than randomised.

---

### 5b. What actually animates, and what deliberately does not

A store where only the positions change reads as a diagram. Each of these is
cheap, and each one was added because its absence was visible:

| thing | frames | driven by |
|---|---|---|
| Kelly's legs | 2 | `kanim`, ticked only while he is *moving* — a figure whose legs pump while standing still is worse than one that never animates |
| Harry's legs | 2 | `hanim`, same rule |
| **Biplane propeller** | 2 | `fphs AND 4` — alternates a broken arc with a solid disc |
| **Kelly, while knocked about** | flash | `fphs AND 2` for the 20 frames of `knock` |
| **Elevator doors** | 3 | open → part-open → shut, redrawn only when the phase changes |
| **Escalator steps** | 4 | `esc_tick`, by rewriting four character *patterns* |
| Elevator car | position | its own travel |
| Scanner: Kelly's marker | *(none)* | he was a blinking character cell; both markers are sprites now and carry their own colour (§6a) |

**The propeller is the only moving part a toy plane has.** Drawn static it reads
as a decal painted on the nose; the alternation is what makes it a thing flying
at you. It costs one extra pattern pair per facing.

**The hit flash exists because nothing said you had been hit.** Hitting an
obstacle set a 20-frame `knock` and took *nine seconds* off the clock, and the
only evidence was the number changing — a punishment with no cause attached to
it, especially when the collision happened at the edge of attention. Flashing
the sprite is the arcade's own idiom and costs one variable.

**Escalator steps animate here, though the reference's do not.** A dense frame
burst of the original (§0c) shows its treads holding still while the rider moves
along them — but a moving staircase is what an escalator *is*, and at the
reviewer's direction ours run. It is nearly free: rewriting the step cells'
**patterns** moves every escalator on screen at once — no name-table traffic,
and the same cost whether one flight is visible or ten. The phases slide the
steps *along the slope*, so they travel up the flight rather than drifting
sideways, and a phase advances by exactly the 2 px across and 1 up that a rider
moves in a frame, which is what makes a rider stand on the stairs rather than
hover over them.

**WHICH cells are rewritten is measured, and getting it wrong is silent in both
directions.** `genart.py` compares each cell across the four phases and animates
exactly those that differ.

- Too many, and motionless cells are rewritten sixty times a second for
  nothing. The block used to be “everything except the head cap” — eighteen
  cells, of which **six** move. The balustrade, the frame and the foot were
  identical in all four phases, so three quarters of the phase tables said
  nothing, at 32 bytes a cell.
- Too few, and part of the staircase stands still. The row that crosses the
  floor above is drawn with the **composite** characters (§0d) — same pattern,
  floor colours — and those are separate character codes, so they were outside
  the block. The top steps of every flight were frozen while the rest climbed
  past them. Whether a cell moves is a property of its *pattern*, so a
  composite moves exactly when its plain twin does.

`assets/checkesc.py` gates both: every cell whose pattern changes must sit
inside the animated run, the run must be contiguous, and the `DEFINE CHAR`
base and count in `KEYSTONE.bas` must be exactly that run — a source constant
against generated data, which nothing else ties together.

---

## 6. The scanner

Rows 21–23, 16 chars wide, centred: a **48-char pattern-plotted canvas** in the RallyX radar
style. The chars are fixed in the name table and plotting is a `VPOKE` into the *pattern*
table, so a moving dot costs two writes and no name-table traffic at all.

```
16 chars × 8 px = 128 px wide   ->  8 screens × 16 px per screen
 3 rows  × 8 px =  24 px tall   ->  4 px of MARGIN, 4 levels × 4 px, 4 px of MARGIN
```

The canvas carries **furniture as well as dots**: a full-width line at each floor, a slash at
whichever end that floor's escalator is, and a bar for the elevator car. Without them the
scanner is two dots in a void — you can see *that* Harry is somewhere, but not what he is
near, which is the one thing you actually need when he is off-screen.

**It is coloured BY PIXEL ROW, and that is what lets it show four things at once.** The
canvas was white-on-black throughout, so the floor lines, the escalators, the elevator and
both actors were all the same white — the instrument you navigate by when Harry is off
screen, drawn in one colour, with the player indistinguishable from the furniture. The
colour mode here is per 8×1 scan line, and every pixel row of a band has a fixed job, so
each role gets its own colour at **no run-time cost**:

| band row | what lives there | colour |
|---|---|---|
| +0 | the escalator's **head**, and the elevator car | grey |
| +1 | **Kelly**, and the escalator's **foot** — which the manual draws black anyway, so the slash spans both rows | black |
| +2 | **Harry** | white |
| +3 | the floor line | yellow, matching the store's own floor bars |

**FOUR PIXELS A LEVEL, AND FOUR IS THE FLOOR.** It was six — two furniture rows, a row each
for the actors, a clear row and the floor line — and at six the instrument filled all 24 rows
of its canvas edge to edge, touching the shop floor above it and the bottom of the screen
below. Four levels of four rows is 16, which leaves **eight empty pixel rows, split four
above and four below**. Four separate colours cannot fit in fewer than four rows, so this is
as tight as it goes; the escalator gave up its second grey row and spans the grey and black
ones instead, and the elevator gave up its second row and took the width back instead.

**The margin is BLACK, and that is the point of it.** Inked the scanner's own dark green it
would be padding *inside* the box: the box would still run from the shop floor to the bottom
of the screen and still touch both. Worse, `DGREEN` is within a few counts of the store's
`MGREEN` on this palette, so the box would not read as a separate thing at all — it would
read as more store. Black margins put real space around the instrument, which is how the
original has it: a green scanner floating in the black strip under the store.

**The escalators lean the way they run.** The head goes on the upper row and the foot on the
lower, so a west escalator reads as climbing to the left and an east one to the right — which
is precisely what you need when deciding which way to run. That costs two pixel rows, which
is why the dots are one row and three pixels wide rather than two by two: the ink moved
sideways.

**The elevator marker TRACKS THE CAR.** It began as two black pixels on dark green — not
enough ink to find, so it read as absent — and then as a bar repeated on every floor the car
serves. That second version was still wrong: it says where the *shaft* is, which never
changes and which the player already knows, and says nothing about the one fact that matters,
which is whether the car is on your floor. It is now a **single five-pixel grey bar** erased
and redrawn at `elvl` each tick, exactly like an actor's dot. Five wide rather than three
because it lost its second row to the squeeze, and a fixed centre column plus the extra width
is what tells it from an actor at a glance.

**Furniture and dots share rows, so the furniture is redrawn every tick.** Dots are erased by
ANDing their bits out, so a dot standing over the escalator's foot takes a bite out of it.
Redrawing the escalators and the car each tick is far cheaper than tracking which pixels
belonged to whom.

**The strip either side of the scanner is black too.** The canvas is 16 chars
wide and centred, so eight columns at each end of rows 21–23 are not part of
it. They held the SPACE character, whose colour is black on **cyan** — right for
the HUD on row 0, wrong here, because it left the radar sitting in a cyan strip
with black margins that stopped at its own edges. That reads as a border drawn
round a panel, not as space around an instrument. The font's colour cannot be
changed for these rows alone: the title screen prints at rows 16, 19 and 21,
and blacking the bottom third of the font would take that text with it. One
blank black character (`SCANBK`) is cheaper and cannot affect anything else.

**`assets/checkscan.py` gates the whole layout**, and it has to, because the geometry and the
colours live in two files that never mention each other: `KEYSTONE.bas` computes the rows and
`genart.py` emits the colour of each one. Out of step, there is no error — there is a white
Kop, or an escalator drawn in floor-line yellow, or a dot plotted in a margin row where the
ink is the colour of the ground and the marker simply does not appear. The checker evaluates
the real arithmetic out of the source (`scan_base`, `scan_furn`, `scan_escs`, `scan_elev` and
`scan_tick`) and checks the row each thing lands on is coloured for the job it is doing.
`assets/preview.py` draws the radar from the same evaluator, so the previewer cannot show a
layout the source no longer has.

**The dot masks were mirrored, and that was invisible.** In a pattern byte `0x80` is the
*leftmost* pixel, so an x offset must be subtracted from 7 rather than used as the shift
directly. It was used directly, flipping every dot inside its own character — an error of up
to 7 px that reads as the radar being approximate rather than as being wrong, which is
precisely why nobody would ever chase it. Because of the flip (§2a) this is how you know where
Harry is at all, so it is built in Phase 6 and not left as polish.

---

## 7. Timer, scoring and Kops

- **50 seconds** per Krook, counted down **by frame delta** and never once per loop pass — a
  per-pass counter is not a clock (`CLAUDE.md` §3A), and a warning cue that drifts under load
  is least reliable exactly when the frame is busiest.
- **Flashes below 10 seconds.** The flash runs off its **own phase counter**, not the parity of
  a timer that decrements by a variable delta — an even delta freezes parity and the flash
  silently stops.
- Obstacle hit: **−9 s**. If that takes the timer to zero, the Kop is lost exactly as a
  time-out loses it.
- Capture bonus: `seconds_remaining × 100` (Krooks 1–8), `× 200` (9–16), `× 300` (17+).
- Money bag / suitcase: **50** each.
- **Bonus Kop every 10,000 points, three reserves maximum.**
- Score is a **BCD digit array** — the ×300 band puts a single capture bonus at up to 15,000,
  and a run past 65,535 well inside normal play.

**The Kop indicator shows RESERVES** — `CLAUDE.md` §7A, and here the manual agrees in its own
words ("three reserve Kops"): a fresh game shows **three** icons with a fourth Kop on the
beat, and the last Kop shows **none**. The decrement-then-redraw order means the draw routine
*is* called with `kops = 0`, so the spare count is guarded (`IF kops > 0 THEN spare = kops - 1`)
against the unsigned wrap to 255 that would light every icon exactly when the player has none.

---

## 8. Controls

| action | TI-99/4A | ColecoVision |
|---|---|---|
| Run left / right | joystick left/right | joystick left/right |
| Jump | fire | fire (L) |
| Running jump | fire + direction | fire + direction |
| Duck | joystick **down** | joystick **down** |
| Enter elevator | joystick **up** | joystick **up** |
| Leave elevator | joystick **down** | joystick **down** |
| Board escalator | walk into it | walk into it |

### 8a. ALPHA LOCK — a hazard specific to this game

On the TI, **ALPHA LOCK shares a line with the joystick's vertical axis**
(`ti99-alpha-lock-joystick-vertical`). Latched down, it reports a vertical direction that is
never released. Every other game in this repo dodges this by not reading up/down at all.
**This one cannot** — down is the duck, up is the elevator. With ALPHA LOCK latched, Kelly
ducks forever and biplanes become unavoidable, which reads as a broken game rather than as a
key in the wrong position.

So the title screen **calibrates the axis**: it samples up and down for 40 frames before any
input can reasonably have been given, and a direction held for essentially all of them is the
key rather than a player. It says so on screen and then **ignores that direction for the rest
of the game**, which makes ALPHA LOCK harmless instead of fatal.

**The first version refused to start until the axis cleared, and that was wrong.** Classic99
defaults to `invertcaps=1`, so the TI sees ALPHA LOCK *down* when the host's Caps Lock is *up*
— the normal state. The game then sat on its title screen forever waiting on a condition the
player had no reason to suspect, and it presented as *"the title comes up and it will not
start."* **A check that turns a survivable input quirk into a dead game is worse than no
check** — the same lesson as `check-scope-narrower-than-bug`, one level up: detecting a
condition correctly is not the same as responding to it usefully.

Starting also accepts **`1` as well as FIRE**. On the TI, joystick fire is TAB, which is
neither guessable nor forgiving — Windows treats a stray TAB as a focus change and moves the
window away. Accepting a digit costs one line and removes the only way to be stuck on the
title.

---

## 9. Sound

Every effect gets an **explicit note-off** and a per-channel decay counter, ticked after every
`WAIT` including inside animation loops — sticky audio is the CVBasic default failure.
`SOUND`'s second argument is a **10-bit divisor: smaller is higher, max 1023**, so a "rising"
sweep is written as a *decreasing* argument and anything over 1023 is silently masked to an
unrelated pitch.

| cue | shape |
|---|---|
| Footstep | short tick, alternating pitch, on the run animation phase |
| Jump | quick rising sweep (divisor falling) |
| Obstacle hit | low buzz, and the 9 seconds audibly ticking off |
| Timer warning | one beep per second below 10 s, off its own phase counter |
| Bag / suitcase | bright two-note blip — two notes need **two channels** |
| Capture | short fanfare, then the bonus counts down audibly into the score |
| Bonus Kop | rising chime |
| Harry escapes | descending slide |

---

## 10. Variables (RAM budget — ColecoVision has ~814 bytes total)

| name | meaning | width |
|---|---|---|
| `klv klsc klx kly` | Kelly's level, screen, x, y | 4 × 8 |
| `#klvy` | Kelly's fixed-point y velocity, +32768 biased | 16 |
| `klst` | state: run / jump / duck / ride | 8 |
| `hlv hsc hx` | Harry | 3 × 8 |
| `obx obk obv oby` | 12 obstacles × (x, kind, velocity, y) | 48 |
| `#tmr` | timer in frames (50 s = 3000) | 16 |
| `sc0..sc6` | score, BCD digits | 7 × 8 |
| `krk kops` | Krook number, Kops remaining | 2 × 8 |
| `elv elvy` | elevator car level and pixel y | 2 × 8 |
| `#lf #fd` | last frame, frame delta | 2 × 16 |

Roughly **100 bytes** of game state. The store's maps live in ROM and the scanner canvas lives
in VRAM, so neither touches the Coleco RAM budget — the same discipline that let RallyX fit a
32×56 maze into a machine with 1 KB.

---

## 11. Hazards this game walks into

Each of these has cost a session somewhere in this repo. They are listed here so this game
pays for them once, at design time.

1. **Sprite size/magnification is global** (§5) — 16×16 everything, small objects drawn small.
2. **Four sprites per scanline; the fifth vanishes** — hence ≤3 obstacles per band. Kelly is
   sprite 0, so he is never the one dropped.
3. **Seam oscillation at a screen edge** (§2a) — 8 px hysteresis.
4. **Screen offsets over 255.** `row*32+col` is fine through row 7 and silently truncates
   above it. Every offset is a bare literal or a `#var`; `tools/bigvar.py` and
   `tools/bigconst.py` gate the build. This game has a **20-row playfield and a row-21
   scanner**, so nearly every offset it computes is over 255 — it is maximally exposed.
5. **`PRINT AT` past column 31, and a HUD `VPOKE` landing inside another routine's label** —
   `assets/checklayout.py`, ported from UFO. Its scope must be declared **per screen**
   (title / setup / play), because UFO's first version compared only within a label and
   passed the very bug it existed to catch (`check-scope-narrower-than-bug`).
6. **A `GOSUB` left by `GOTO`.** `do_death`, `do_catch` and `do_escape` are all natural places
   for it and all reached several levels deep; it is invisible on the TI and fatal on Coleco.
   `tools/gosubtrace.py` gates the build.
7. **Reading a 16-bit var right after multiplying it** returns the product's high word — and
   the bonus calculation (`seconds × 100`) is exactly that shape. Compute it behind its own
   label so the compiler is forced to emit a real load.
8. **`%` compiles to a real DIV** — the scanner's screen→pixel mapping uses shifts, not modulo.
9. **Odd-length `DATA BYTE` blocks** misalign every word table after them (§2b).
10. **`VPOKE` operands must be precomputed** into plain vars, never expressions — ISR race.
11. **ALPHA LOCK** (§8a) — this is the first game here that reads the vertical axis in anger.
12. **The Kop indicator counts spares**, and the redraw is called at zero (§7).
13. **FOUR MENU ENTRIES FOR ONE CART, THREE OF THEM BROKEN.** `linkticart.py`
    writes the 80-byte cartridge header at the top of *every* 8 KB loader page and
    then pads the image to a power-of-two page count, so the console finds four
    headers and lists the program four times. Only page 0 is a real entry point:
    the others were copied wholesale and point into the middle of data, so
    selecting one runs from a bogus address. A banked build hides this (the
    console only ever sees bank 0 during its power-up scan), which is why it does
    not show up on every cart in the repo. `assets/onemenuentry.py` blanks the
    `>AA` magic on pages 1+ after linking, and the TI build script runs it.
14. **A one-pixel dead band in the beach ball's arc** (§5a). It is the only hazard whose
    correct response changes mid-flight, so it is the only one that can have a height where
    *no* response works — and that height would present as an occasional unfair hit, never as
    a reproducible bug. It is closed by three numbers chosen together (apex, ducked height,
    hitbox inset) and verified by a **sweep over every `Bb`**, not by playing.

---

## 12. Build

```
games/KeystoneKapers/
  DESIGN.md  README.md
  src/KEYSTONE.bas          one source, both targets
  assets/genart.py          char + sprite patterns
  assets/genstore.py        band templates -> store.bas
  assets/genfont.py         HUD font
  assets/checklayout.py     screen-layout gate, per-screen scope
  assets/checklayout_test.py  proves that gate FAILS on each defect it claims
  assets/onemenuentry.py    strips linkticart's decoy cart headers (see 11.13)
  assets/preview.py         renders a store screen from the SHIPPED bytes
  assets/checkball.py       sweeps every ball height for a dead band (build gate)
  assets/checkchase.py      walks both routes to the roof; fails if the chase
                            cannot be won on foot (build gate, see 4a)
  build-ti.sh               cvbasic --ti994a -> xas99 -> linkticart -> KEYSTONE_8.bin
  build-coleco.sh           cvbasic -> gasm80 -> keystone.rom
```

Both scripts run the same gates as UFO's — `bigvar.py`, `bigconst.py`, `gosubtrace.py`,
`checklayout.py`, `checkball.py`, `checkchase.py` — plus the fixed-area check against the **24,336-byte** cap. Expected to fit
a single bank: the store is ~1 KB of templates and there is no music engine.

---

## 13. Phase plan

Each phase builds on **both** targets before the next one starts.

| # | phase | done when |
|---|---|---|
| 1 | **Store & flip** — 8 screens, 4 bands, templates, `SCREEN` blits, Kelly running, seam hysteresis | You can run the length of the store and back; seams never flicker |
| 2 | **Jump & duck** — fixed-point vertical, apex, running jump, duck height, landing | Kelly hops 14 px and ducks to 8 px, on every floor |
| 3 | **Escalators & elevator** — alternating up-points, the car, ride states, invincibility | You can climb the zig-zag and ride down the middle |
| 4 | **Obstacles** — carts, balls, radios; the ball's jump/duck windows (§5a); the 9-second penalty; bags and suitcases | Hits cost 9 s; ≤3 per band; nothing vanishes on a scanline; the `Bb` sweep finds no dead band |
| 5 | **Harry** — flee AI, catch, roof escape | He can be caught, and he can get away |
| 6 | **Scanner** — the 48-char canvas, both dots and the furniture | You can find Harry without seeing him |
| 7 | **Timer, score, Kops** — countdown, flash, bonus bands, bags, bonus Kop, game over | A full Krook plays start to finish |
| 8 | **Biplanes, difficulty, title** — the ducking hazard, per-Krook ramp **including the ball apex**, title + `838` setup, ALPHA LOCK check, sound | Krooks 1→17+ ramp; late-Krook balls bounce out of the jump band; the title refuses to start with ALPHA LOCK down |

---

## 13a. Parallax the roof skyline

**DONE.** The costing below was written before the work and is left as written;
what shipped matched it to the byte -- 40 bytes of fixed area (638 free -> 598)
and 800 in the bank, no new code. Kept in full because the costing was wrong the
FIRST time and the reason it was wrong is the reusable part.

The city behind the roof is identical on every screen, so crossing a seam up
there gives no sense of travel: the foreground jumps a whole screen and the
horizon does not move at all. The buildings read as wallpaper rather than as
distance.

**The change.** Shift the skyline **1 character per screen**, opposite to the
player — exit LEFT and the buildings shift RIGHT, exit RIGHT and they shift
LEFT. That is a 1/32 **parallax rate** against the foreground.

**It was two characters first, and two was too fast to follow.** The rate has to
be slow enough that the eye reads the far city as the *same* city seen from
further along; at two columns a crossing changed enough of the silhouette that
the continuity broke, and it read as a *different* skyline rather than a moved
one. Distance is sold by moving very little, not by moving visibly.

### What it costs

| | cost | headroom after |
|---|---|---|
| ROM bank | **+800 B** — 5 extra roof templates × 160 (3 roof templates become 8) | 1,483 of 8,192 free |
| Fixed area | **~40 B** — five more `#tsrc(n) = m` lines | 814 free |
| RAM | **10 B** — `DIM #tsrc(15)` instead of `(10)` | — |
| New code | **none** | — |

### Why it needs no code

`stor_ix[lv*8 + scr]` already selects a template per (level, screen). Eight
roof templates with the skyline pre-shifted drop straight into that index, and
the roof band stays an ordinary `SCREEN` blit like every other band — so
`checkbands.py` and `checkstruct.py` need no teaching either.

### The implementation, as built

1. `t_roof()` in `assets/genstore.py` takes the screen it is for and samples
   `SKYLINE[(c + scr) & 31]`; `TEMPLATES` names eight roof entries,
   `T_ROOF0`..`T_ROOF7`. Screen 0 keeps its head-house on top of its own
   offset. **Screen 7 no longer carries exit furniture**: six cells of `EXITC`
   stood at columns 28-30, rows 2-3, and read on screen as purple dots on white.
   The roof's east end is the edge of the *building* and the crook goes over it
   — a doorway there says he leaves through something, which is the wrong
   statement about how a round ends, and it was also standing exactly where he
   used to stop (see §0p-septies).
2. `KEYSTONE.bas`: `DIM #tsrc(15)` and five more `#tsrc(n)` lines; `INDEX`s
   roof row became `[R0 R1 R2 R3 R4 R5 R6 R7]`.

**Verified on the generated templates, not by eye** -- parallax sense is
invisible in a still. Screen s+1 column c equals screen s column c+2 for rows
0-2 across all six plain screens, and rows 3 and 4 are byte-identical on every
screen, so the wall at actor height and the deck underfoot do not slide.

**Direction check**, because parallax sense is easy to invert and impossible to
spot in a still: `skyline[s][c] = SKYLINE[(c + 2s) & 31]` means screen `s+1`'s
column `c` shows what screen `s` had at column `c+2` — the buildings move LEFT
as the player moves east. That is correct.

### THE COSTING WAS WRONG THE FIRST TIME, AND THE REASON GENERALISES

The first analysis said eight roof templates "does not fit" — 8 × 160 = 1,280
bytes against a fixed area with 372 free — and recommended stamping the
skyline in at run time instead.

That is backwards. **`store.bas` is INCLUDEd after the `BANK 1` directive, so
template data lands in ROM bank space**, which is two-thirds empty. The option
dismissed as too expensive is the cheap one; the run-time stamp recommended in
its place is the expensive one, because it needs new **code**, and code is the
budget that is actually scarce.

**The general lesson: "does it fit" is meaningless without asking WHICH budget
it lands in.** This game has three that behave nothing like each other — the
24,336-byte fixed area (scarce, holds all code), the 8 KB data bank (roomy),
and Coleco's 814 bytes of RAM. `CLAUDE.md` §3A already says moving data out of
a bank into code "makes things worse"; this was the same error in the other
direction, costing bank-resident data against the fixed area and concluding the
cheap thing was unaffordable.

### Watch for

- The skyline spans rows 0–2 with different characters per building height
  (`ROW0`/`ROW1`/`ROW2` in `t_roof`); all three rows shift together.
- Rows 3 and 4 — the solid brick wall and the deck — must **not** shift.
- The shift wraps every 16 screens, so over 8 screens you see half a cycle and
  nothing repeats across the store.
- It spends about a quarter of the remaining bank, and bank space is what art
  expansion will want next. Not pressing at 1,483 free, but worth knowing
  before something larger needs it.

---

## 14. Acceptance criteria

- Runs at **60 Hz on both targets** with 14 actors moving, no frame misses.
- **Zero per-frame VDP reads**, verified by inspection of the main loop.
- A seam crossing repaints once and never oscillates.
- Kelly clears an 8 px obstacle at the top of his jump, and passes under a biplane ducked, on
  every one of the four bands.
- **Swept over every `Bb` from 0 to the 14 px cap, the beach ball is avoidable at every single
  height** — jump at `Bb <= 8`, duck at `Bb >= 9`. No dead band, verified by sweep and not by playing,
  because a one-pixel hole would present as an occasional unfair hit and never as a
  reproducible bug.
- A high-bouncing ball on a late Krook **cannot be jumped and cannot be run under standing**.
  It is duck-only, and no ball at any apex is ever free.
- The climb from the first-floor entrance to the roof on foot is **three full traverses** of
  the store, one per floor — never two. Getting the alternation backwards silently shortens
  the store by a third and is not visible in a screenshot.
- Harry is catchable at Krook 1 and escapes reliably if ignored.
- The scanner shows both dots at the correct screen and level at all times.
- Bonus bands, the 9-second penalty and the 10,000-point Kop all match §7.
- The Kop indicator shows **three** at the start of a fresh game and **none** on the last Kop.
- Fits the **24,336-byte** fixed area on TI; Coleco RAM stays under 814 bytes.
- With ALPHA LOCK latched, the title says so instead of starting a broken game.
