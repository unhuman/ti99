# Adventire — Design

An original action-adventure in the style of Atari 2600 *Adventure* (1979): a one-square hero
roams a kingdom of connected single-screen rooms, juggling one object at a time to open castles,
slay dragons, and carry the enchanted chalice home. **CVBasic**, one source, dual target:
TI-99/4A cartridge and ColecoVision ROM. All code, pixel art, and room maps are original —
this is a mechanics homage, nothing is copied from the Atari game.

## Performance Budget

- **Moving sprites:** typically 3–4 per frame (player, at most 1 live dragon per room, the bat,
  carried object). 11 sprite slots (player, 3 dragons, 6 objects, bat); off-room actors are
  parked at Y=$d1. The bat is simulated globally every tick (trivial cost: one actor, no wall
  tests — it flies through walls).
- **Sprite magnification:** `VDP(1)=$E3` (16×16 patterns + MAG, like Astiroids) — sprites render
  **32×32 (4×4 characters)**. Dragons and the bridge use the full pattern; the player square
  stays 4×4 art (8×8 on screen) so it can thread the 16px maze corridors.
- **Loop pacing:** real-time, fixed **30 Hz** on both machines (two `WAIT`s per tick). Per-tick
  work is small, so TI-99 and ColecoVision run identically from one source — no `pacen` constant.
- **Zero per-frame VRAM reads.** Wall collision is a RAM bit test against the current room's
  24-byte bitmap (`rm()`), loaded once on room entry. No VPEEK/GCHAR-style calls in the loop.
- **Per-frame VRAM writes:** sprite attribute updates only (11 `SPRITE` calls). Background is
  redrawn only on room entry (~768 VPOKEs, an event, not a frame cost).
- **AI:** one greedy (non-search) chase for at most one on-screen dragon, plus the bat's
  linear drift. Dragons in other rooms do nothing.

## World

13 rooms, each a 16×12 grid of 16×16-pixel blocks (2×2 characters). One `DATA BYTE` pair per
row, 24 bytes per room. Walls are char 128 (solid), tinted per room by rewriting the color
table rows for char 128 in all three screen thirds ($2400/$2C00/$3400).

```
[12 White Hall: BRIDGE]      [2 Gold Hall*]            [9 Black Hall]--[10 Dungeon: CHALICE]
    | gate                       | gate                    | gate
[11 White Castle]------------[0 Gold Castle]           [8 Black Castle, YELLOW dragon]
                                 |                         |
                             [1 N Meadow]--[3 Corridor: SWORD]--[5 Maze N]
                                 |                                  |
             [4 S Meadow: GOLD KEY]--[6 Cave: sealed chamber = BLACK KEY, GREEN dragon]--[7 Maze S: WHITE KEY, RED dragon]
```
(Exact exits in `lnkdat`; R11–R1 connect E/W, R5–R7 N/S, R7–R8 E/W. `*` = win room. The halls
(2, 9, 12) and dungeon (10) have **no inbound edge links** — they are entered only via gate
warps, which the bat never uses.)

**Intended progression:** gold key (R4, free) → sword (R3) → white key (R7, red dragon) →
white castle → **bridge** (R12) → bridge into the sealed cave chamber (R6, green dragon) →
black key → black castle (yellow dragon) → chalice (R10) → home to the gold hall.

Room colors (`coldat`, VDP 0–15): gold 11/10, meadow greens, red corridor, maze blues, purple
cave, gray black castle, dark-red dungeon, white castle 15.

## Objects & rules

| # | Object | Starts in | Color |
|---|--------|-----------|-------|
| 0 | Gold key | R4 south meadow | 11 |
| 1 | Black key | R6 **sealed chamber** (bridge required) | 14 |
| 2 | White key | R7 maze south (red dragon) | 15 |
| 3 | Sword | R3 corridor | 7 |
| 4 | Bridge | R12 white castle hall | 13 |
| 5 | Chalice | R10 dungeon | shimmers (FRAME-cycled 8–15); the largest object icon — a full cup+stem+base filling most of its 16×16 art |

- **Carry one object.** Touch picks up (swapping drops the old one on the spot, 10-tick
  cooldown); **FIRE drops** (edge-triggered).
- **A carried object keeps the offset where you grabbed it** (`#crx`/`#cry`, biased +64 to stay
  unsigned, clamped at screen edges). Grab the sword on your left and it fights on your left.
- **Gates (3):** touch a closed gate carrying the matching key → opens permanently. The touch
  window is px 100–148, py ≤ 70 — deliberately generous, because 3px movement steps can leave
  the player resting at py=66–70 against the gate (a py≤65 window made keys "sometimes not
  work"). Walking deep into an open archway (py≤34, px 106–138) warps inside; the hall's south
  doorway returns you just below the gate.
- **Bridge:** 32×32, two rails around a channel, drawn with **two sprites** — the purple rails
  plus a black channel-fill sprite (slot 11, def 9) so the passage reads as a dark opening in
  the wall it spans. While it lies in the room (not carried, and not in a castle-grounds room —
  no bridging gates), the player's wall collision is skipped whenever the target box sits
  inside the channel (with a 2px margin off the rails): drop it across a wall and walk through.
  **It is grabbed by its rails only** — walking the channel, or standing where you just dropped
  it, never re-picks it up (an earlier center-touch pickup made the bridge grab itself back
  instantly, which is why it "couldn't be crossed"). On drop its Y **snaps to the 16px block
  grid**, so the channel always covers whole wall rows and a crossing never dead-ends inside a
  partially covered wall. You cannot pick it up while standing inside a wall (that would seal
  you in). It is the only way into the R6 chamber.
- **Win:** the chalice's room becomes 2 (carried in or dropped) → color-cycling flash +
  fanfare → play again (full reset).

## Dragons (3)

| # | Color | Home | Speed |
|---|-------|------|-------|
| 0 | Yellow (11) | R8 black castle grounds | 2–3 px/tick alternating (~75 px/s) |
| 1 | Green (2) | R6 cave, outside the chamber | same |
| 2 | Red (8) | R7 maze, over the white key | **3 px/tick (fast)** |

- Chase only while you're in their room; greedy longer-axis-first movement. Wall box is the
  central 8×16 of the 32×32 body (the visual overhang brushes walls, as on the 2600).
- **Sword (object 3) kills on contact, carried or lying** — the kill zone is wherever the
  sword sits, so carry it on the side facing the dragon.
- Bitten without the sword: swallowed — falling wail, player shown in the belly, then FIRE
  starts a **fresh game** (full reset: objects, dragons, gates, bat).
- On room entry a live dragon within 40px of your arrival point is pushed to room center
  (108,72); entering a live dragon's room plays a roar.

## The Bat

Simulated every tick wherever it is (starts in R5). Flies **through walls** at 2px/tick
horizontally with a 1px vertical wobble (direction flips on a timer + `RANDOM`), and drifts
between rooms through the normal exit links — which by construction never lead into a hall or
the dungeon, so it cannot lock a key inside a castle. On touching an object (150-tick cooldown
after each grab) it takes it — swapping means its old loot drops on the spot — **including the
object in your hands** (you can chase it and snatch the item back, which resets its cooldown).
Anti-softlock guards: it never swap-drops inside the R6 sealed chamber and never grabs the
bridge while in R6.

## Engine notes (CVBasic specifics)

- Collision: `chkpt` computes block row/col by `/16` and bit-tests `rm()` with a mask table —
  no modulo (only `AND 7`), per the TMS9900 DIV lesson from Ms. Pac-Man.
- All comparisons unsigned-safe (deltas via the `adiff` max−min helper in 16-bit vars).
- Dragon/bat step alternation uses a soft tick counter `tk`, not `FRAME` (FRAME advances +2
  per 30 Hz tick, so its parity never changes).
- `GOSUB` targets are all `PROCEDURE`s; no `GOTO` escapes a procedure (CVBasic requirement).
  The swallow sequence is flagged (`eflag`) out of the dragon loop; the restart `GOTO newgame`
  happens at main-loop level.
- Sound: SN76489 channel 0 for blips/sweeps (pickup, drop, gate sweep, roar, bat squeak),
  channel 3 noise for a dragon slain; swallow wail and win fanfare play inline.
- RAM: 214 bytes (TI), 199 (Coleco) — far inside the ColecoVision's 1 KB.

## Acceptance criteria

1. Title → FIRE starts in R0 with all three gates closed; joystick moves, walls block, exits
   lead to the mapped rooms with matching entry positions.
2. Each key opens only its own castle; opening works when pressed anywhere against the gate
   (including resting at py=66–70); archway warp works in and out of all three castles.
3. A picked-up object rides at the offset where it was touched (left grab = left carry).
4. The bridge lets the player (only) cross walls its channel covers; the sealed chamber is
   reachable with it and unreachable without it; the bridge can't be grabbed mid-wall.
5. Sword slays any dragon on contact on any side; the red dragon is visibly faster.
6. The bat roams rooms, steals objects (including carried ones), and can be robbed back;
   it never marooning-drops in the sealed chamber and never enters a castle hall.
7. Swallowed → FIRE fully resets the game; win → play-again also fully resets.
8. Dragons and bridge render 32×32 (4×4 characters); chunky 2× pixels throughout.
9. Chalice into the gold hall = flash + fanfare + play-again.
10. Identical behavior on TI-99/4A (`adventire_8.bin`) and ColecoVision (`adventire.rom`).
