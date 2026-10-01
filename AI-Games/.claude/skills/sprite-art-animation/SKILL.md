---
name: sprite-art-animation
description: >-
  Hard-won lessons for sprite and character ART in this repo's CVBasic games: mirrored poses
  that are their own mirror, run cycles whose non-adjacent beats repeat (checkanim.py),
  crouch-height limits, art-row width errors in hand-edited art files, anchoring generated-art
  edits on names, sprite-slot and pattern-code ownership (checkpat.py), message boxes on the
  attribute grid, text paper colours and CLS side effects. Load before editing
  sprite/character art, animation beats, text boxes, sprite slot numbers or pattern-code
  ranges.
---

# sprite-art-animation

Moved verbatim from the root `CLAUDE.md` (§3A and its trailing sections) on 2026-09-28 so it
loads only when needed. Section references like "§3A" mean the root `CLAUDE.md`.

- **A MIRROR IS ONLY WORTH TWO DRAWINGS IF THE DRAWING IS ASYMMETRIC, AND AN
  "EVERY OTHER FRAME" ANIMATION CYCLE IS USUALLY TWO POSES.** Both halves cost a
  session in Keystone Kapers and both present identically -- as an actor whose
  legs go back and forth between two positions -- while every existing check
  passes, because the numbers are all consistent: the right patterns are loaded
  at the right addresses and drawn on the right beats. They are just the same
  picture twice.
  - **The mirror half.** "Four poses cost two drawings: left-foot-forward is the
    mirror of right-foot-forward" is sound, and Kelly's legs were drawn as two
    parallel vertical columns -- apart in one pose, together in the other. A pair
    of vertical legs mirrors to itself. His four beats differed by **4 px and
    8 px**, and 4 of those 4 were the hip row sliding two columns sideways
    because it had been given the tunic's hem shape, which is not its own mirror.
  - **The every-other-frame half.** In an 8-frame run cycle **frame n+4 is the
    same pose with the legs swapped**, and a side-view silhouette cannot tell
    those apart. So frames 1, 3, 5, 8 -- which alternate the leading leg
    correctly -- play as A, B, A, B. Order them so the unavoidable near-duplicates
    sit *opposite* each other in the cycle, not adjacent.
  - **RANK ON THE CLOSEST PAIR ANYWHERE IN THE CYCLE, NOT THE CONSECUTIVE STEP.**
    The consecutive step is the reassuring number and it is the wrong one: the
    bad set scored 49 px between adjacent beats and 7 px between beats 1 and 3.
  - **A striped actor is split across complementary sprites, so measure the whole
    figure.** Harry's white leg layer holds 10 px of 33; two of his four beats
    were **byte-identical** in it while the black stripes-and-shoes layer they are
    drawn with differed by 34. Measuring one half alone calls the same art a
    two-frame cycle or a four-frame one depending which half it is handed.
  - **`games/KeystoneKapers/assets/checkanim.py` gates it** -- it reads each
    band's beats out of the `.bas` itself (base assignment plus the following
    `IF <clock> AND <bit> THEN v = v + n` lines, never a table of its own),
    resolves them through the art generator's sprite table, adds the derived
    bands back in, and fails on any two beats within 10 px. It also fails when
    two bands of one figure run on different clock bits -- four leg poses against
    two torso poses is two clocks in one body, which reads as flapping. It was
    run against the defective art before being trusted, and failed on it.
  - **A MEASURED DEFECT THAT IS DELIBERATELY KEPT NEEDS A NAMED EXEMPTION, NOT A
    LOWERED THRESHOLD.** The Kop's two-frame cycle was redrawn twice and the
    redraw rejected both times -- the reviewer wanted yesterday's animation back.
    Relaxing MINDIFF until he passed would have blinded the check for every OTHER
    band at the same moment, which is how a gate quietly stops being one. The
    exemption lists the band by name with its reason, still MEASURES it, and
    still prints its 4 px on every build; only the failure is suppressed, so the
    number moves in plain sight if the art ever gets worse.
  - **AND THE FIX FOR A SYMMETRIC MIRROR EXPOSES THE MIRROR ITSELF.** Redrawing
    the Kop's two poses with real strides ended the repeated beats and
    immediately produced a new complaint -- *"sometimes the body is facing the
    wrong direction"*. A mirrored stride puts the OTHER foot forward on a body
    still facing the same way, which reads as the figure **turning round**; it
    was invisible only because the old legs were two near-vertical columns. So
    the mirror trick and the asymmetry requirement are in direct tension: a
    drawing asymmetric enough to be worth two beats is asymmetric enough that
    its mirror is a different ACTOR, not a different beat. Drop the mirrored
    beats and run the two drawings you have.
  - **A DUCK-OR-JUMP GAME PINS THE CROUCH HEIGHT TO THE PIXEL, AND "GIVE IT
    MORE HEADROOM" MAY HAVE NO ANSWER.** Duckable means the hazard clears the
    crouch; jumpable means it clears under the apex. Raising the crouch raises
    the duckable floor until it meets the apex coming down, and then a band of
    hazard heights is NEITHER. Keystone Kapers swept its crouch from 11 to 20
    and the dead band opened at **12** -- the very first pixel. So the answer to
    a request for a taller crouch is a measurement, not a redraw: the ceiling is
    usually much closer than the sprite box, which had five spare rows and was
    never the constraint. **Sweep it before drawing to it**, and if the pose
    needs the height, the hazard hitboxes or the arc move first.
  - **AND AN UPRIGHT HEAD IS THE EASIEST WAY TO DRAW A POSE THAT MIRRORS TO
    ITSELF.** A crouch with the head centred on a symmetric squat is its own
    mirror, so ducking reads as the figure being SQUASHED rather than as it
    dropping and still looking where it is going -- the same defect as the
    mirrored run beats, from a pose nobody would suspect. Push the brim
    forward, set the face forward under it, give the shoulders a lead over the
    trailing rump, and **measure the composite against its own mirror** rather
    than judging the layers separately. The layers tell you nothing about it.
  - **AND AN "EXTRA" POSE IS ONLY A POSE IF IT MEASURES DIFFERENT.** Kelly was
    given a standing drawing, because an animation counter that advances by
    DISTANCE freezes when the actor stops and leaves him holding whichever beat
    he halted on. The file came back **byte-identical to run frame 1** -- the
    same sixteen rows uploaded into a second slot. The fix is a one-line alias
    (`IF kmv = 0 THEN kb = P_KRUN1`), not a second sprite, and the way to find
    out is to `==` the assembled art rather than to read the two files. Keep
    the vacated slots as declared BLANKS so nothing renumbers, and say in the
    table that they are free.
  - **A LOOPING DETAIL DRAWN INTO A BAND IS ON SCREEN FOR THE WHOLE POSE.**
    Kelly's raised baton lives in his FACE sprite, and there is one face per
    pose -- so selecting it off the same bit as the body put it up **half the
    time**, which reads as waving rather than running. A detail that should
    punctuate the cycle needs its own, SLOWER bit (`AND 16` on top of the
    body's `AND 8`, so one beat in four) and an explicit override for any
    state where the counter does not advance: a standing jump holds no
    direction, so a distance counter is frozen and the bit is whatever it was
    at take-off. Without the override the detail appears on some jumps and not
    others, for a reason no player can see.

- **AN ART ROW THAT LOSES ONE CHARACTER IS SILENTLY DROPPED, AND EVERY ROW BELOW
  IT SHIFTS UP.** A hand-editable art file that picks out its rows by shape
  ("any line of exactly 16 of `.#-0`") so the file can carry its own header will
  QUIETLY SKIP a row that is 15 wide. Nothing fails: the file still has enough
  art rows, every band/colour check passes, and the generator, assembler and
  cart are all happy. `kelly-run2.txt` lost the trailing dot of two rows and it
  was reported as **two unrelated drawing bugs** -- *"the buttons on the shirt
  are all messed up"* and *"one of the arms sort of disappears"* -- with nothing
  anywhere naming a line, because a shifted block rebuilds the figure out of its
  neighbours' rows. **Make a near-miss a HARD ERROR**: any line made only of art
  characters must be exactly the width, or the build stops naming file, line and
  width. A line that is meant to be prose must start with the comment character.

- **ANCHOR A GENERATED-ART EDIT ON THE THING'S NAME, NEVER ON ITS COLOUR OR
  ITS BYTES.** Two edits meant for one character in Keystone Kapers' art table
  matched on `""", WHITE, GRAY),` instead, which four characters shared. Both
  hit the FIRST of them, so the lift shaft was recoloured twice and the intended
  character never changed at all. **Nothing failed**: both are real characters,
  both ended up with plausible colours, every generator and gate passed, and the
  only symptom was a white band across the roof bar where a pillar met it --
  reported as a drawing bug in the pillars, which is not where the edit went.
  Colour arguments, pattern rows and byte lists all repeat across an art table
  by design; the name is the only unique thing in the entry.

- **SPRITE SLOTS ARE A SHARED NUMBER SPACE, AND "THE NEXT FREE ONE" USUALLY IS
  NOT.** Slot numbers are typically handed out in blocks -- player, enemy,
  hazards, HUD -- with the blocks only written down in a comment, so adding a
  sprite to an actor and taking the number right after its last one lands in
  the middle of somebody else's block. Both writers succeed; whichever runs
  later in the frame wins.
  - Keystone Kapers gave Harry a fourth sprite at slot 8. Slots 8-15 are the
    OBSTACLES, and the obstacle pass runs later in the same routine, so his new
    leg stripes were written and overwritten every frame. **Two symptoms,
    neither an error:** the stripes never appeared, and *a ball flickered
    somewhere it did not belong* -- obstacle 0 dragged to Harry's position and
    pattern for part of each frame and then put back. The second was reported
    as a flicker-control regression, which is what it looks like.
  - Grep for every `SPRITE <n>` **and** every computed slot (`SPRITE ds`,
    `ds = di + 8`) before picking a number, and put the block map in the source
    next to the allocation rather than in a design doc.
  - **A RANGE WRITTEN BY RAW VRAM ADDRESS IS OWNED BY NOBODY AS FAR AS ANY GATE CAN
    SEE.** Keystone Kapers' radar canvas is 48 CHARACTERS that `scan_wipe` rewrites as
    raw pattern memory every frame. No `DEFINE`, no upload, nothing in the source that
    looks like a claim -- so the pattern-ownership gate reported those codes as FREE and
    a second copy of the font was put there. It uploaded correctly and was scribbled
    over from its twelfth character on; the HUD came out as bands of unrelated art.
    **This was the same class of mistake the gate had just been written to catch, one
    day later**, which is the point: a gate that derives ownership from uploads is blind
    to everything drawn another way. Derive those ranges too (from the art generator's
    own constant, never a second copy of the number) and make the gate PRINT the free
    space so the next reader is told rather than guessing.
  - **AND THE SAME IS TRUE OF PATTERN CODES, WHERE "A FREE GAP" IS USUALLY SOMEBODY'S
    ART.** Keystone Kapers moved a sprite pose into "176..207, a 32-code gap nothing
    else uses" and it was the player-chased actor's own left-facing LEG bands. The
    upload succeeded, the art loaded at the address it was given, every gate passed,
    and the only symptom was **a detached block of the wrong art a dozen pixels below
    the actor, on alternate frames** -- reported as "a ball shaped thing drops below
    his feet". The real free space was twelve patterns against the sixteen needed.
    **Derive the free list from the art generator's table and print it; never assert a
    range is free.** `games/KeystoneKapers/assets/checkpat.py` resolves every upload
    (both the `nchr`/`ncnt`/`ntab` form and `DEFINE CHAR`/`DEFINE SPRITE`) to a range
    and a source and fails on any that lands in another table's codes, with the
    deliberate borrows declared by name.
  - **A ROUTINE HANDED ITS ADDRESS BY ITS CALLER BELONGS TO NO ONE SCREEN, AND A
    LAYOUT GATE HAS TO ATTRIBUTE THE WRITE TO THE ASSIGNMENT RATHER THAN TO THE
    POKE.** Keystone Kapers shared one digit printer between the in-game HUD and
    a new score line on the title card. `checklayout.py` refuses to pass a
    drawing routine it cannot map to a screen -- correctly -- and there was no
    honest answer: mapped to the game, the title's `HI` field collided with the
    game's TIME digits, and no nine-character field on row 0 avoids the game's
    TIME label, its digits and the lives icons at once. **The two screens want
    the same columns for different things, which is fine, because they never
    coexist.** The fix is that the checker records `(literal, assigning label)`
    and tests each write against the screen of the routine that SET the address.
    That is strictly more accurate, not looser: the shared printer's columns
    stop all landing on one screen and split across the two that own them.
  - **A CHECK ADDED ALONGSIDE THE CHANGE IT IS MEANT TO GUARD WILL AGREE WITH IT.**
    The same commit taught `checkchars.py` to verify the pose's `CONST` against the
    `nchr` of the upload that loaded it -- two halves of one mistake, both saying 176,
    so it passed. **A constant is only checked when it is compared against something
    INDEPENDENT of it.** Compare against the generator, never against the other end of
    the same edit.
  - **A TIGHT `VPOKE` LOOP IS A VBLANK OVERRUN WITH NO UPLOAD IN SIGHT.** The same
    game drew its message boxes with a `VPOKE` loop and no `WAIT`: ~43 cycles a cell
    and a hundred-odd cells, against ~1679 available, so the tail was discarded at the
    PPU and the box came out with characters missing -- intermittently, because the
    cut point moves. **Pace any unbounded write loop**, and prefer a bound that needs
    no counter (one `WAIT` per row) when RAM is tight.
  - **AND ONCE A BOX IS COLOURED BY THE ATTRIBUTE TABLE, ITS POSITION IS ON A
    FOUR-ROW GRID FOR EVER.** An attribute byte covers FOUR characters by four,
    so a message box sized and placed to cover whole bytes -- which is what
    stops colouring it repainting the scenery around it -- can only ever start
    on rows where `(row + picture offset) % 4 == 0`. Keystone Kapers was asked
    to move its boxes down TWO rows and could not: the legal rows are 1, 5, 9,
    13, 17, 21, so the nearest move downward is FOUR. Moving two would have
    straddled two byte rows, and colouring both repaints sixteen columns of
    eight rows -- two whole floors of shop -- in the box's colour. **Say this
    when it comes up rather than quietly shipping the two-row version on the
    TMS targets and a four-row one on NES**: a difference in kind between
    targets is what every gate that parses the source is built to assume away.
  - **A FOUR-ROW BOX CANNOT CENTRE A ONE-ROW MESSAGE, AND THE ONLY CHOICE IS
    WHICH SIDE GETS THE ODD ROW.** One above and two below, or two above and
    one below -- there is no third option while the box has to cover a whole
    attribute byte, and shrinking it to three rows leaves the fourth row of the
    COLOURED block showing scenery through it, which is worse than an uneven
    margin. Keystone Kapers shipped the first and it was reported as *"an extra
    row below the message"*. Put the odd row above: the eye reads a gap under
    text as unfinished and a gap over it as headroom.
  - **CENTRE TEXT FROM THE TEXT, NEVER BY TYPING THE PADDING.** Keystone Kapers'
    five message lines were padded by hand to a fixed box width and two of them
    -- `GOT HIM!` and `TIME UP!` -- sat one column left of centre with the
    surplus on the right. It is invisible in a source listing because every line
    is the right LENGTH, which is the only thing a width check can ask about,
    and on screen it reads as the BOX having a wider margin on one side. One
    helper that takes the words and returns the padded line cannot be typed
    wrong.
  - **TEXT HAS NO BACKGROUND UNLESS YOU GIVE IT ONE, AND INDEX 0 CANNOT BE IT.** A font
    uploaded with no colour table gets ink on index 0 -- the UNIVERSAL backdrop, one
    colour for the whole screen -- so every character sits in a box of it. To put a
    colour behind text, its PAPER has to move to another index, and paper is written
    into the second bitplane at upload time: it is a property of the character, not of
    where the character is drawn. A colour table of identical bytes is the cheap way
    (ROM is three budgets and this is not the scarce one); a second copy of the font is
    usually neither possible nor needed, because in game all the text wants the same
    treatment. Then remember that **a blank cell is ALL paper**, so every region that
    holds blanks needs its attribute byte pointed at a palette whose index 1 is right --
    Keystone Kapers got a green band above its score line from two rows nothing draws in.
  - **A COSMETIC RULE APPLIED BY HAND AT EACH SITE WILL MISS ONE, AND THE MISS IS
    INVISIBLE TO EVERY CHECK YOU HAVE.** Keystone Kapers colours each message box by
    pointing its attribute bytes at the HUD's palette, written out at each call site.
    One was missed and `GOT HIM!` kept the store's gold-on-green while every other box
    went white-on-blue. **Nothing failed** -- it is a readable message in the wrong
    palette, which no layout, overflow or collision check can speak to, and the author
    had no list to compare against because the list was "the places I edited". Make it
    a ROUTINE and derive the rule from the PRODUCER: `assets/checkmsg.py` requires
    every `msg_*` draw to be flushed before and coloured after, and is mutation-tested
    against the real miss. Same shape as `snd_off` going stale.
  - **GIVING TEXT A PAPER MAKES EVERY PRE-EXISTING `CLS` VISIBLE.** A cleared cell is
    all paper. While that paper was index 0 -- the backdrop -- a clear went black and
    read as part of whatever redraw followed it; once the paper is a real colour the
    same clear becomes a flat field of the region colours. Keystone Kapers had a
    redundant `CLS` before its full redraw for the whole life of the port and nobody
    saw it until the HUD got a background; it was then reported as full-screen flashes
    "at indeterminate intervals with nothing special going on" -- the interval being a
    round, which is not special to look at. **Audit every clear when you add a paper**,
    and delete the ones whose redraw covers the screen anyway.
  - **`CLS` CLEARS THE ATTRIBUTE TABLE, SO ANYTHING WRITTEN TO IT BEFOREHAND IS LOST.**
    Setting a screen's palettes and then clearing the screen loses the palettes, and the
    symptom is a screen whose text is on the wrong colour -- not a blank screen, which
    is what "the CLS wiped it" sounds like it would look like.
  - **AND WATCH FOR A CHARACTER SENT TWICE IN TWO DIFFERENT FORMS.** That game's
    marquee lamps were loaded once with the store's colour table (paper -> index 1)
    and re-sent at run time with `#ncol = 0` (paper -> index 0, the backdrop). Both
    were correct in their own context and the screen visibly changed colour a second
    after it appeared, one character at a time, as the second form caught up. **Send
    it at setup in the form the run-time path uses**, or the first frame of a screen
    is not the screen.
  - Check the hide/reset paths too: a `FOR i = 0 TO 23` that blanks sprites
    will not cover a slot outside its range, and widening it may blank a block
    it was deliberately skipping.
