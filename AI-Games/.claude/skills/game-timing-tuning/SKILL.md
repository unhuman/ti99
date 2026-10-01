---
name: game-timing-tuning
description: >-
  Lessons on pacing, speed and difficulty in this repo's CVBasic games: one clock for things
  that move together, frame-delta vs per-pass pacing, fractional accumulators capped by drain
  steps, loop rate as a hidden difficulty dial, chase margins (path / speed, checkchase.py),
  #fd clamps, WAIT quantisation, timers on the frame delta, AI override pitfalls and grid-cell
  occupancy. Load before changing any speed, timer, pacing constant, chase/escape tuning or
  difficulty ramp.
---

# game-timing-tuning

Moved verbatim from the root `CLAUDE.md` (§3A and its trailing sections) on 2026-09-28 so it
loads only when needed. Section references like "§3A" mean the root `CLAUDE.md`.

- **TWO THINGS THAT MUST MOVE TOGETHER MUST SHARE ONE CLOCK -- AND IF ONE OF THEM IS A
  CYCLIC ANIMATION, THAT CLOCK CANNOT BE THE FRAME DELTA.** Movement is normally paced by
  `fdv` and animation by the loop pass; while the loop keeps up those agree, so the pairing
  looks right in the source and on screen. Both failure modes are silent and both shipped:
  - **Paced apart, the actor drifts.** A rider on an escalator advanced `2*fdv` px along
    the steps while the steps advanced 2 per pass, so his feet started planted on a tread
    and ended floating several pixels above it. It *compounds*, so it does not read as a
    one-frame glitch. And the screens where the two must agree are usually the busiest
    (that animation rewrote 120 bytes of pattern table per pass), so the delta is largest
    exactly where the mismatch shows.
  - **Paced together by `fdv`, the animation ALIASES.** A 4-phase cycle over an 8 px period
    stepped by 2 flips between two positions half a period apart (direction unreadable);
    stepped by 3 it runs 0,3,2,1 -- the **wagon-wheel effect**, and the escalator visibly
    carried its steps *downward* while the rider went up. **A cyclic animation can only be
    stepped by one, whatever the frame rate.**
  So: make the animation the clock and pace the actor *from it* -- both by a fixed step per
  pass. The ride then takes N passes rather than N frames and slows when the loop does,
  which is the honest behaviour for a machine that is carrying you. **A checker for this
  must simulate `fdv > 1`** (the code is correct at 1, which is what a desk check and a fast
  emulator both exercise) **and must read both clocks out of the source and compare them** --
  `games/KeystoneKapers/assets/checkride.py` does, and names all three failures.

- **A FRACTIONAL-SPEED ACCUMULATOR IS CAPPED BY ITS NUMBER OF DRAIN STEPS, AND
  THE CHECKER WILL NOT KNOW.** Keystone Kapers spends a quarter-pixel speed as
  whole pixels with `hacc = hacc + hsp4` then a run of
  `IF hacc > 3 THEN hspd = N : hacc = hacc - 4`. **Each step can spend one pixel,
  so N steps cap the speed at N px per pass no matter what the constant says.**
  With two steps and `hsp4 = 9` the crook ran at a flat 2.0 while every comment,
  the design table and `checkchase.py` all said 2.25; the surplus leaked into an
  8-bit accumulator that wrapped every 256 passes. Nothing failed -- he simply
  arrived two thirds of a screen short of his own escape.
  - The comment above it stated the invariant correctly (*"hacc is under 4 on
    entry and hsp4 is at most 8, so it can never need a third"*) and was **not
    re-read when the constant changed**. Write the invariant AND check it.
  - **The model must parse the accumulator, not the constant.** `checkchase.py`
    now counts the drain steps out of the source and fails on a speed they
    cannot deliver, instead of dividing and believing the answer.

- **THE LOOP RATE IS A DIFFICULTY DIAL, AND WHERE THE PLAYER STANDS TURNS IT.**
  Anything paced per loop PASS moves slower in real time on a busy screen, while
  anything paced by the frame DELTA -- a countdown clock, typically -- does not.
  In Keystone Kapers the crook is per-pass and the round timer is per-frame, so
  the same uninterrupted escape finished with **TIME 09 in hand from a light
  screen and TIME 00 from the lift screen**. Measured, not inferred: a pass
  counter gave 2,335 passes over ~98 s (23.8/s) against the model's assumed 25.
  Raising the quarry's speed papers over it. **The fix is to pace the actor off
  the same clock as the thing that judges it** -- in Keystone Kapers the crook now
  accumulates once per elapsed FRAME rather than once per pass, and the spread
  collapsed from 00-vs-09 timer units to 04-vs-04.
  - **A per-frame accumulator wants a FINER unit and FEWER drain steps.** His
    step drops under a pixel a frame, so two drains suffice where three were
    needed per pass -- and the finer unit is what makes the speed tunable: in
    sixteenths one notch was six seconds of his route, in sixty-fourths one and
    a half.
  - **CLAMP THE PER-PASS STEP, AND NOT TOO TIGHTLY.** Position tests sample once
    a pass and do not interpolate, so a big step can jump an arrival window or
    pass through a catch radius. But clamping at 3 frames re-created the original
    bug in miniature, because the slowest screen *is* 3 frames a pass: every
    hitch there lost a frame. Size the clamp off the narrowest window, not off
    the typical delta.
  - **WHEN A TIMING IS TUNED AGAINST A MODEL YOU DO NOT FULLY TRUST, ASK WHICH
    DIRECTION IS SURVIVABLE.** Keystone Kapers' checker reads seven seconds
    optimistic against measured play, and the crook was left arriving about eight
    seconds early rather than shaved to the buzzer. The errors are not symmetric:
    early costs a little tension, late means he **never escapes at all**, which
    deletes one of the two ways to lose a round -- silently, because the game
    still runs perfectly well without it. Spend the margin on the side where
    being wrong is cheap, and record it as a decision so it does not read as an
    unfinished tuning job.
  - **A rider on a cyclic animation stays on the animation's clock** -- it cannot
    move to the frame delta without drifting off or aliasing. Mixing the two
    within one actor is correct, and the model has to count them in their own
    units (adding passes to frames and dividing by one rate is a units error a
    ratio test cannot see).

- **A DEBUG READOUT THAT COSTS ANYTHING WILL MEASURE ITSELF.** Five digit-print
  calls per pass dropped the measured rate from 24 to 21 -- the instrument was
  three passes a second of the thing it was reporting. Print once a second, not
  once a pass. Two more traps in the same fifty lines: computing the answer on
  the machine (a route length in pixels) was **150 bytes over the cart cap** when
  reporting the raw position and doing the arithmetic offline was free; and
  holding `FRAME` in a plain variable wrapped at 256 and reported 1 pass a second
  (`bigvar.py` catches a literal over 255, not a variable handed one at runtime).

 Anything timed — a beep interval, a countdown, a
  telegraph — must decrement by the frame delta, not once per loop pass, or it slows down exactly
  when the loop gets busy. That is the same root cause as movement slowing (§3A's FRAME-delta
  item), and it is worst for warning cues, which become least reliable precisely when the frame is
  most loaded. Corollary: once a timer decrements by a *variable* delta, any logic keyed on its
  **parity** (`t AND 1`) breaks — an even delta freezes the parity. Drive alternating states from
  their own phase counter.

- **A grid-cell occupancy check does NOT prove sprites do not overlap.** A 16-px actor on a 16-px
  grid straddles two cells for its entire traverse, so "no two actors share a cell" can read a
  clean 0 while they are visibly stacked. Worse, a cell cache derived from raw pixels every frame
  is **asymmetric**: moving up or left, `pixel / 16` flips to the next cell after ONE pixel, so
  the actor releases the cell its body still fills. Hold the cached cell as an **anchor** updated
  only on arrival (both low nibbles zero) and let the actor reserve origin + destination while in
  transit. Assert on the thing you can see — `|dx| < size AND |dy| < size` — not on the index you
  happen to store. RallyX chased this through several "verified fixed" rounds because the probe
  measured cells.

- **A difficulty dial must never invert the goal.** Weakening an enemy by making it flee reads as
  broken AI, not as an easier game. Degrade the *quality* of the pursuit instead (chase on the
  worse axis, react later, move slower); the actor should always be visibly trying.

- **A CHASE RESOLVES ON `path ÷ speed`, AND THE PATHS ARE ALMOST NEVER THE SAME LENGTH.** Two
  speed constants sitting next to each other invite the reading "the player is 1.5× faster, so
  the player wins", and that reading is wrong whenever the quarry's route is shorter. Keystone
  Kapers had Kelly at 3 px/frame against Harry's 2 — and Kelly lost the race to the roof by
  **eleven seconds every single round**, because Harry spawns beside his first escalator and
  runs 4,104 px where Kelly runs 7,992. A 1.95× route needs more than a 1.95× speed, so pursuit
  on foot could not close at any distance given any amount of time.
  - **It does not present as a tuning problem, it presents as the enemy cheating** — the player
    sees themselves visibly gaining and still never arriving. Nothing errors, and neither
    constant is wrong on its own; the defect lives only in the ratio of two quotients.
  - **The corollary is that the quarry's speed is then not a difficulty dial.** Once the margin
    is set, one notch on the quarry can consume all of it: at 1.75 px/frame the slack fell from
    11.6 s to 5.1 s, less than a single obstacle hit. Ramp the hazards instead — which is also
    what the original manuals actually say.
  - **Compute it, do not eyeball it.** `games/KeystoneKapers/assets/checkchase.py` walks both
    routes out of the real constants (speeds, spawns, escalator sides, ride length, round
    timer) and fails the build if the margin, the ordering, or the escape-inside-the-timer
    property breaks. Copy it for any game with a pursued actor.

- **FRAME-delta pacing is a positive feedback loop — keep per-pass work O(events), not
  O(`#fd`).** With `#fd = FRAME - #lf`, any "repeat the step `#fd` times" loop (per-pixel
  movement, per-pixel AI polling) makes a slow pass slower still: cost rises with `#fd`, which
  raises `#fd` again. RallyX sat pinned at its `#fd` clamp of 4 and ran at **8 loop passes/sec**
  until everything that moves was rewritten to advance to the next *cell boundary* in one step
  (→ **60/s, one pass per vblank**). Symptom is "sluggish sometimes" with `FRAME` still ticking a
  clean 60 Hz — i.e. no vblanks lost, the loop is just too fat. **Profile before optimising:** the
  obvious suspect there (the 576-byte `SCREEN` pan blit) was never called during the slow runs,
  and the enemy AI ran 0.56×/pass. Measure loop passes/sec against a host clock —
  see `games/RallyX/DESIGN.md` §1a.

- **The `#fd` clamp DISCARDS real time — game speed then depends on frame rate.** Clamping the
  delta bounds catch-up work, but the world advances only `clamp` frames per pass while real time
  advances more, so everything runs slow *exactly when the loop is busy* and full speed when it
  is idle. In RallyX this read as "the enemy cars move faster when the screen isn't scrolling."
  Once movement is O(cells crossed) a big delta is cheap **and** safe (each step still tests walls
  at every boundary, so nothing tunnels), so set the clamp far above normal play. Same trap for
  any timer counted in *passes* rather than frames — scale every countdown by `#fd`.

- **`WAIT` quantises the loop to whole frames**: achievable rates are 60, 30, 20 … A body that
  overruns one frame by a hair costs a whole extra frame, so the last millisecond is worth more
  than it looks — and an average like "2.2 frames per pass" means visible jitter between 2 and 3.

---

- **TWO CLOCKS IN ONE LOOP IS A UNITS BUG A RATIO TEST CANNOT SEE.** If the actors are
  advanced once per **loop pass** (`x = x + SPEED` in the main loop) while a timer is
  advanced by the **frame delta**, the game has two different time bases and the loop rate
  silently becomes a difficulty dial. Keystone Kapers ran `WALKSP = 4` px per *pass* at ~25
  passes/s -- 100 px/s, which happened to match the reference exactly -- against a clock
  ticking in real seconds. Kelly needs **72 s** to reach the roof and Harry **96 s** to
  escape; the round was **50 s**, so it always ended on a timeout and one of the two loss
  conditions could never fire at all.
  - **`checkchase.py` passed on every run**, because it converted *both* routes with
    `FPS = 60`. Halving a number on both sides of a comparison leaves the comparison intact,
    so every relative assertion — "Harry is slower than Kelly", "Kelly arrives first" — stayed
    true. The error only appears when the actors are compared against something measured in
    **different** units. A ratio test cannot catch a units error; a checker needs at least one
    absolute anchor.
  - The tell is a constant whose name implies a unit it does not have. `WALKSP = 4 ' px per
    frame` was px per *pass*. **Before trusting any speed constant, find where it is spent**
    and confirm the loop's actual rate — do not read it off the comment.

- **A CENTRING OFFSET ADDED BEFORE A DISTANCE WILL WRAP THE BYTE, AND THE BUG LOOKS LIKE A
  GENEROUS HITBOX.** Keystone Kapers measured the catch as
  `kcx = klx + 8 : hcx = hx + 8 : |kcx - hcx|`. Harry walks to x 253 before crossing a screen
  seam, so `hx + 8` wrapped to 5 and a Kop at the far LEFT read as five pixels from a crook
  walking off the far RIGHT — arresting him across the whole store. Nothing warns: both are
  plain 8-bit variables and the wrap is silent.
  - **The offset cancels in a difference**, so the fix is to delete it, not to widen the type:
    `|(a+k) - (b+k)| == |a - b|`. Any per-actor offset applied to BOTH sides before subtracting
    is dead arithmetic that can only introduce overflow.
  - The tell is a hit that fires at *maximum* separation rather than minimum — the wrap makes
    the two extremes of the range adjacent.

- **AN OVERRIDE THAT IGNORES THE STATE IT OVERRIDES WILL CONTRADICT IT IN FULL VIEW.** A "run
  away for a while" mode bolted on top of an enemy's normal AI beat the *flee* as well as the
  goal-seeking, so the crook held one heading regardless of where the player was and ran
  straight into him. Written as a **default the other rules can outrank** — cleared the moment
  the player appears on his floor — the same code reads as deliberate.
  - Its sibling: **a mode ended by a timer changes direction with nothing on screen to explain
    it.** End it on a world event instead (reaching a wall, the player arriving) so every
    change of heading has a visible cause.
  - And check WHERE the override sits. Placed below the movement it only reached the animation
    counter: the actor faced the right way, played the run cycle, and travelled zero pixels.
