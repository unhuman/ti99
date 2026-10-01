---
name: checker-design
description: >-
  How to write build-time checkers and tests for this repo's games without them going blind:
  extractors that silently match less, properties of pairs, unit changes that should break a
  check, reachability with fall-through, labels printed from several places, proxy conditions
  and exhaustive sweeps (checkjump.py), sampling pixels instead of eyeballing screenshots, and
  keeping builds fast with parallel gates (5C). Load before writing or changing any check*.py,
  *_test.py, layout checker or build-script test step.
---

# checker-design

Moved verbatim from the root `CLAUDE.md` (§3A and its trailing sections) on 2026-09-28 so it
loads only when needed. Section references like "§3A" mean the root `CLAUDE.md`.

- **A PARSER THAT SILENTLY MATCHES LESS IS A CHECK THAT REPORTS SUCCESS.**
  `checkanim.py` reads each animated band out of the `.bas` as a base assignment
  plus the `IF <clock> AND <bit> THEN v = v + n` lines after it. Rewriting a
  four-beat ladder as a two-beat ASSIGNMENT (`kb = P_KRUN2`) meant the band
  stopped being recognised, and the gate printed `animation OK -- 1 clocked
  bands` with the player's run entirely unmeasured. Teaching it the assignment
  form, and making its search window count **code** lines rather than source
  lines (a paragraph of comment had been pushing steps out of reach), turned up
  **two MORE bands that had never been measured** -- and one of them failed.
  - This is the mirror of "a check whose scope is narrower than the bug": the
    scope was right and the *extractor* narrowed under it. The count in the
    summary line is the only visible symptom, and nobody reads a passing line.
  - **Assert the subjects BY NAME in the self-test**, with the beat count each
    must have. A gate that says how many things it measured, but never what,
    cannot tell you it has gone blind.

- **A PROPERTY OF A PAIR IS INVISIBLE TO EVERY CHECK WRITTEN ABOUT ONE OF THEM.**
  Keystone Kapers gates each hazard hard -- checkball.py sweeps a single ball
  against the jump and the crouch frame by frame, checklevels.py pins the round
  each hazard arrives on. Both were right, and from the round where a floor
  starts carrying TWO hazards the pair was unclearable on every screen: the gap
  was 46 px on one side of the lift and 70 on the other, against the 168 px of
  closing distance one jump consumes, so the player cleared the first and came
  down onto the second. Neither check could see it, because neither asks a
  question about two objects.
  - **The asymmetry is what gets REPORTED, and it is not the fault.** It
    surfaced as "on the left and right of the elevator they seem closer
    together" -- true, and a distraction: both sides were already below the
    floor. The difference was two placement bytes; the defect was that the
    spacing had never been derived from anything.
  - Derive the spacing from the mechanic that must fit through it (here the
    jump s airborne frames times the closing speed), name it, and check it.
    games/KeystoneKapers/assets/checkspace.py does, and REPORTS rather than
    fails on the one case the screen cannot satisfy -- a check that demands the
    impossible is a check somebody deletes.

- **A LABEL CAN BE PRINTED FROM MORE THAN ONE PLACE, AND A LAYOUT CHECK CANNOT
  SEE THE ONE YOU MISSED.** Moving the HUD's `TIME` two columns right produced
  `TIMEME` on screen, because a flash routine blinks the same label when the
  clock runs low and carried its own copy of the column. A checker that tests
  each write for overflow and collision passes: two writes of the same string at
  different columns collide with nothing and overflow nothing. Grep for the
  literal, not for the routine that appears to own it.

- **A PROXY CONDITION THAT AGREES WITH THE REAL RULE IN THE COMMON CASE IS AN
  EDGE CASE WAITING.** Keystone Kapers boarded an escalator from a jump only if
  the arc was **descending**. That is true of every ordinary landing and it is
  not the rule: the rule is "he has arrived on the staircase from outside it".
  A flight is a diagonal and the jump's apex is 14 px, so an arc can clear the
  three treads it could land on and then meet the riser of the fourth, at 16 --
  which is above the apex. That collision happens while still **rising**, so the
  proxy rejected it and the player went through the staircase onto the floor
  underneath.
  - **Replace the proxy with the property.** "Has been above the surface during
    this jump" is one byte and covers both a tread hit on the way down and a
    riser hit on the way up -- and its complement is exactly the walkable floor
    beneath the flight, which must keep working.
  - **The bug's rarity is a fingerprint of a launch window, not of flaky input.**
    It needed a 40 px band of starting positions; the reporter said "this is
    rare", which is what a geometric edge case sounds like from play.
  - **A sweep is the only honest answer to "check all scenarios".**
    `assets/checkjump.py` runs 108,000 arcs -- every launch x, both flights,
    every animation phase, frame delta, jump direction and accumulator phase.
    Two construction rules made it trustworthy: the geometry is modelled in the
    checker (ground truth) while the **boarding rule is parsed out of the `.bas`
    and executed**, so it cannot drift from the game; and an unrecognised
    statement is a **hard error, not a skip** -- when the fix added a block `IF`
    the interpreter stopped rather than silently ignoring two lines, which would
    have left it passing everything. Its extractor then had that exact bug
    (stopping at the first `END IF`, which now closed the inner block), and only
    `checkjump_test.py` -- which types out the rule that shipped the fault and
    asserts the sweep rejects it -- proved the clean run meant anything.

- **WHEN YOU CHANGE A UNIT, THE CHECKER THAT STILL PASSES IS THE SUSPICIOUS ONE.**
  Keystone Kapers moved its hazards from px-per-pass to 64ths-of-a-px-per-frame,
  which changed the constants from `2` to `51`. Every gate still passed.
  `checkspace.py` was cheerfully printing `closing 55 px/pass` -- Kelly's 4 plus
  the hazard's new 51 -- and passing *because* a nonsense closing speed makes
  "one jump clears both" trivially true. **A units change should break something;
  if nothing breaks, the checks are not reading the units.**
  - **The deeper error it exposed had been there for months.** The file multiplied
    the JUMP ARC's length by a PER-PASS speed, and the arc is indexed by a counter
    that advances by the frame delta -- so its entries are frames, and every
    closing distance came out ~2.4x too large. The hazard gap had been chosen
    against those inflated numbers and was in the "dangerous middle" the file
    exists to reject: too far apart to clear in one jump, too close to land
    between. It had been reported from play and not recognised.
  - **A checker's self-test that re-derives the model by hand will re-derive the
    bug.** `checkspace_test.py` computed the same window the same wrong way, so
    the two agreed perfectly. Re-deriving is still right -- importing the numbers
    would make the test vacuous -- but the test must be re-derived from the
    SOURCE's units, and every historical bad case kept as a case. The gap that
    shipped is now one of them.
  - **The tell that a unit is lying is a label.** `checkchase.py` printed
    `'Kelly %d px/frame'` for a constant that was px per PASS, and a `climb_by_lift`
    that summed frames and passes into one number. Both were correct when written
    and both silently stopped being so.

- **A REACHABILITY CHECK THAT MODELS ONLY EXPLICIT JUMPS WILL CALL LIVE CODE
  DEAD.** A dead-label sweep over Keystone Kapers reported `tick_flash` --
  the low-time warning -- as unreachable: nothing `GOSUB`s or `GOTO`s it, and
  `git log -S "GOSUB tick_flash"` found no commit that ever had. It runs fine.
  It is entered by **FALL-THROUGH** from the routine above it, which ends without
  a `RETURN` and drops into the next label, and which says so in a comment. In
  CVBasic that is ordinary control flow, not a trick.
  - **A false alarm during a delete-things pass is worse than a missed byte.**
    Deleting it would have removed a working feature and the ROM saving would
    have looked like a win. Any "unused" list must model fall-through -- a label
    is reachable if the statement before it can complete -- or be treated as
    suspects to confirm rather than a work list.
  - This is the mirror of the scope trap below (a check narrower than the bug
    reports success): a model narrower than the control flow reports a **failure
    that is not there**. Both cost the same trust.
  - The rest of the same sweep was sound: two assignments the compiler itself
    flagged as never read, and three CONSTs matched nowhere in the text.

## 5C. Build time from line 1

Keystone Kapers' builds grew to ~180 s each, ~9 minutes for all three targets,
because every new gate and test was appended to a serial list. Timed
(2026-09-26), compiling and assembling were seconds; four Python simulations were
~160 s of each build. Set new games up like this from the first gate.

* **Measure before cutting anything.** `PS4='+ $EPOCHREALTIME ' bash -x build.sh
  2> trace` timestamps every top-level command; the gap to the next line is its
  duration. The "NES is slower" impression turned out to be builds chained
  back-to-back in the background: measured, all three targets took the same
  ~180 s.
* **Run independent checks in parallel.** Gates and `*_test.py` that only READ
  the source and generated files can all start at once; the build then waits for
  the slowest instead of the sum. Keystone's `assets/runtests.sh`
  (`run_checks_parallel`) is the template: every job keeps its own failure
  message, every job is waited for, and every failure is listed with its output
  tail before the build stops. Set `PYTHONDONTWRITEBYTECODE=1`, so parallel
  imports cannot race on `__pycache__` (and the stale-`.pyc` hazard in 3A goes
  away too).
* **Run target-independent tests once per multi-target build.** A test of the
  shared BASIC logic proves nothing new on the second and third target. Keystone's
  `tools/keystone-dev.ps1 BuildAll` runs the suite with the first target and sets
  `KK_TESTS_DONE=1` for the rest. Gates that read a target's own output
  (assembly, RAM map, layout) still run on every target.
* **Keep every test.** Each guards a bug that shipped. Make them cheap to run, not
  optional.
* **A control-flow checker must model the preprocessor.** When a checker decides
  fall-through from a routine's last line, it must skip `#if`/`#else`/`#endif`
  and lines the target does not compile. Otherwise `#if A / GOTO x / #else /
  GOTO y / #endif` reads as falling through (Keystone's checkvblank did exactly
  this, DESIGN.md section 51). Test both directions: the false alarm, and a real
  fall-through that must still fail.

- **VERIFY GEOMETRY BY SAMPLING PIXELS, NOT BY LOOKING AT A SCALED SCREENSHOT.** Three separate
  "confirmations" in one session were wrong: a capture taken during a between-rounds message, a
  comparison of one floor's pillar columns against a bar carrying a *different* floor's beam tops,
  and a column index computed from an assumed 3× emulator scale when the window actually scales to
  fit and clips the right edge. A two-pixel detail does not survive eyeballing a 4× crop. Print the
  RGB at a computed coordinate, or simulate the draw from the data and print the resulting
  character codes.
