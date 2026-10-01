---
name: ti-input-screens
description: >-
  TI-99/4A input and screen-sequencing lessons: the ALPHA LOCK / joystick vertical-axis short
  and Classic99 invertcaps (and why the Keystone guard was removed), keypresses leaking into
  the next screen, drawn-but-deaf screens, noisy cont1.key lines, one-time boot probes and
  drawing the first screen early. Load before touching title/menu/setup screens, cont1.*
  input, cheat codes, key-release waits or boot ordering.
---

# ti-input-screens

Moved verbatim from the root `CLAUDE.md` (§3A and its trailing sections) on 2026-09-28 so it
loads only when needed. Section references like "§3A" mean the root `CLAUDE.md`.

> **Read first:** the entry "THE ALPHA LOCK / VERTICAL-AXIS GUARD WAS REMOVED" is the
> latest word. The invertcaps entry's "calibrate instead", the ONCE-PER-POWER-ON probe and
> the STRICT INPUT RESET stability filter describe mechanisms that were later removed or
> found to eat real presses; they are kept as history.

- **A SCREEN THAT IS DRAWN AND NOT LISTENING IS NOT UP YET, AND EVERY SYMPTOM OF
  THE GAP LOOKS LIKE AN INPUT BUG.** Drawing a menu before the setup that follows
  it is an obvious win and measures like one -- Keystone Kapers' title went from
  4.03 s to 2.62 s. What it actually bought was a **finished, readable, deaf**
  screen: `setup_rest`, `init_tables` and a 40-frame calibration all ran after the
  draw and nothing polled input during them.
  - **It was reported three times over three sessions and misdiagnosed twice**, as
    `8-3-8` losing its first digit, then a start press that did not take, then
    *"FIRE TO START is delayed"*. The first diagnosis was keyboard noise and
    produced a three-frame stability filter that ate REAL presses; the second was
    that the prompt needed to be printed later so its arrival marked the moment.
    Neither is the fault. Both made it worse.
  - **The fix is to put the work back in front of the draw**, not to shrink it or
    to label it. The screen appears later and is live on the frame it appears; the
    extra time lands on a black screen where there is nothing to act on. Keeping
    the routines split still pays, because the re-entry label sits BELOW the setup
    and a second game redraws the title without rebuilding anything.
  - **The general rule: an optimisation that reorders work around a user-visible
    moment has to account for what the program can DO at that moment, not only
    what it shows.** Anything that puts a prompt on screen before the loop that
    reads it is this bug, and it will be reported as flaky input.

- **THE ALPHA LOCK / VERTICAL-AXIS GUARD WAS REMOVED, AND THE ENTRY BELOW WAS
  PARTLY WRONG.** It claimed "every other game in this repo dodges this by not
  reading up/down at all". **Eight of them read it** -- Adventire, Astiroids,
  HardHatMack, Ms. Pac-Man, RallyX, Structris, UFO, Bust-A-Bobble -- and none has
  a calibration or has ever shown the fault. Keystone Kapers was the only game
  that guarded against it and the only one with trouble.
  - **It never fired.** The notice it prints on detecting a stuck axis has never
    appeared on the machine this is developed on.
  - **The original evidence is suspect.** The symptom was "the title comes up and
    it will not start", and the first version of the guard BLOCKED until the axis
    cleared. That is indistinguishable from the several input bugs since found
    and fixed for real -- keys arriving at a screen not yet listening. The
    diagnosis was probably one of those.
  - **It cost two bugs of its own**: forty frames of a drawn but deaf title
    screen, which swallowed the first digit of `8-3-8` and could lose a button
    press; and a wrong theory about keyboard noise that led to a stability filter
    which ate real presses.
  - **Do not re-add a guard on this without reproducing the fault first.** If a
    stuck axis appears it is obvious -- the player ducks or rides the lift
    without asking. The removed code is in the history.
  - The mechanism below is still true as electronics, and `invertcaps` is still
    the Classic99 default. What is not established is that it causes a problem in
    practice.

- **THE TI's ALPHA LOCK KEY SHARES A LINE WITH THE JOYSTICK'S VERTICAL AXIS.** With it
  latched down the console reports an up/down direction that is **never released**, so
  any menu built on `cont1.up`/`cont1.down` boots pinned to one entry and cannot be
  moved off it -- a per-pass `IF cont1.down THEN k = 2` is recomputed every pass, so the
  stuck axis wins every pass and no other key can ever get an edge in. No error, and it
  looks like a broken menu rather than an input problem. `cont1.left`/`cont1.right` are
  unaffected and are what every game here already uses for aiming/steering, which is why
  this stays hidden until something reads the vertical axis for the first time.
  **For a menu, prefer `cont1.key` (0-9 on both targets, 15 for nothing) and PRINT the
  key beside each entry** -- it dodges the hazard, states its own controls, and costs
  less code than a cursor (in Bust-A-Bobble it freed 248 bytes). Swapping a vertical
  menu to left/right instead is a trap of its own: it works, and players still press up
  and down.

- **A KEYPRESS THAT DISMISSES ONE SCREEN MUST NOT ACT IN THE NEXT, AND THIS COSTS
  A FIX PER SCREEN.** The press is still down when the next screen starts reading,
  so it arrives there as input nobody gave. Keystone Kapers paid for this four
  separate times before anyone wrote it down:
  - the cheat code's final `8` was typed into the setup page's first field;
  - the sound bench played a variant on boot from the cart-select keypress;
  - the title screen's own `8-3-8` was broken by spurious reads between presses;
  - and FIRE on the title made the player JUMP on the first frame of the round.
  - **Wait for the RELEASE, not for a different value.** An edge-triggered read is
    not enough: the value has not changed yet, it is simply still there. The fix
    that works everywhere is to spin until the control reads idle before the new
    screen starts listening.
  - **But CAP THE WAIT.** A stuck or shorted line turns "wait for release" into a
    dead game, which is worse than the bug -- the same mistake as blocking on an
    ALPHA LOCK check that can never clear. Give up after a second and carry on.
  - **A latch reset in the new screen may not be enough.** Clearing the jump's
    release flag when the round starts is obviously correct and did not fix it in
    play; waiting for the button did. When two latches interact, stop reasoning
    about their order and wait for the physical thing.

- **A STRICT INPUT RESET AND A NOISY KEY LINE DESTROY EACH OTHER.** On the TI,
  ALPHA LOCK shorts a keyboard line (and Classic99 defaults to `invertcaps`, so it
  reads DOWN with the host's Caps Lock UP), and `cont1.key` then returns values
  nobody pressed for a frame or two at a time. A cheat-code state machine whose
  reset is deliberately strict -- anything that is not the next digit clears it,
  so `8,5,3,8` cannot work -- is cleared by that noise too, so the code typed
  correctly does nothing.
  - **The symptom names the cause if you read it carefully**: "8-3-8 does nothing,
    then 3-8 works". The trailing 8 of the failed attempt was still standing as
    state, which only happens if the reset fired *between* the player's presses.
  - **Fix it with a stability filter, not by weakening the reset.** Require the
    key to hold for three frames (50 ms); a human press is several times that and
    the noise is one or two. Cap the counter AT the threshold and test for
    equality, so a held key is accepted once rather than every frame.
  - This is the same short behind two earlier Keystone bugs -- the setup page
    opening on its own, and the cheat code's final digit being typed into its
    first field. **Any new `cont1.key` reader on this machine inherits it.**

- **DRAW THE FIRST SCREEN AS SOON AS THE FONT EXISTS, NOT WHEN SETUP IS DONE.**
  Boot-time asset loading naturally gets written as one block with the title after
  it, and then every byte of it is time the player spends watching nothing. Almost
  none of it is needed to draw text. Splitting setup so the title is drawn after
  the font and before everything else does not reduce the work -- it moves the work
  behind something worth looking at, which is what the player actually experiences
  as speed. Keystone Kapers went from 4.03 s to 2.62 s with no work removed beyond
  the fill above.
  - **Check the re-entry path, not just first boot.** The title routine is usually
    also the game-over destination, so splitting it can leave the second visit
    drawing nothing or re-running boot-time work.

- **A ONCE-PER-POWER-ON HARDWARE PROBE INSIDE THE TITLE ROUTINE RUNS ONCE PER GAME,
  AND THE RE-RUNS ARE WRONG.** Keystone Kapers samples the joystick's vertical axis
  for 40 frames to detect a latched ALPHA LOCK (§3A above), then ignores that
  direction for the run. It lived inside the title routine, which `GOTO boot`
  re-enters after every game over. The probe's whole validity rests on being taken
  **before any input is plausible** -- on a return to the title that is false, so a
  player still holding a direction had it read as a stuck key and **disabled for the
  next game**. Hoist any calibration whose answer cannot change to the one-time boot
  path; redraw its notice per screen if the screen is cleared.

- **CLASSIC99 DEFAULTS TO `invertcaps=1`, so the TI sees ALPHA LOCK *DOWN* WHEN THE HOST'S
  CAPS LOCK IS *UP*** -- the normal state of a keyboard. Combined with the ALPHA LOCK / joystick
  vertical-axis short (`ti99-alpha-lock-joystick-vertical`), that means **`cont1.up` reads as
  permanently pressed on a default install**. Any game that reads the vertical axis is affected
  out of the box, not in some rare configuration.
  - **DETECTING IT IS NOT ENOUGH -- DO NOT BLOCK ON IT.** Keystone Kapers' first version printed
    `RELEASE ALPHA LOCK` and refused to start until the axis cleared, which on a default
    Classic99 is never: the game sat on its title screen forever and presented as *"the title
    comes up and it will not start."* **Calibrate instead**: sample up and down for ~40 frames
    before any input is plausible, treat a direction held for essentially all of them as the
    key rather than the player, say so on screen, and ignore that direction for the rest of the
    run. A check that turns a survivable input quirk into a dead game is worse than no check.
  - Corollary for any title screen: **do not make FIRE the only way to start.** On the TI fire
    is TAB, which Windows also treats as a focus change; accept a digit as well.
