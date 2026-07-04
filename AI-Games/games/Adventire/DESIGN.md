# Adventire — Design

An original action-adventure in the style of Atari 2600 *Adventure* (1979). **CVBasic**, one
source, dual target: TI-99/4A cartridge and ColecoVision ROM. All code, pixel art, and room
data are original — a mechanics homage whose kingdom layout and connections are our own
adaptation of the game structure documented in published maps and guides (the AtariAge map,
Wikipedia, walkthroughs). Nothing is copied from the Atari game.

## The four games (title-screen select, UP/DOWN + FIRE)

| Game | Name | World |
|------|------|-------|
| 1 | INTRO KINGDOM | Our original 13-room map (rooms 0–12): 3 castles, 3 dragons, bat, bridge + sealed chamber. A gentle introduction. |
| 2 | SMALL KINGDOM | Compact kingdom in the spirit of the cartridge's first game: gold + black castles, corridor row, blue maze, two dragons. No bat, no dark rooms, no white castle. |
| 3 | FULL KINGDOM | The big map (rooms 13–38): 3 castles, corridor row, blue maze, **dark** catacombs and black-castle maze (fog of war), red maze, magnet, bat, and the hidden-dot **secret room**. |
| 4 | RANDOM KINGDOM | Game 3 with the objects scattered anew each game (`RANDOM`, white key barred from the red maze so it can't seal itself away). |

Swallowed or victorious → back to the title (game select, same game highlighted). Every start
is a full world reset.

## Performance Budget

- **Moving sprites:** typically 3–4 per frame (player, ≤1 live dragon per room, bat, carried
  object). 14 sprite slots (player, 3 dragons, 8 objects, bat, bridge-fill); off-room actors
  parked at Y=$d1. The bat simulates globally every tick (one actor, no wall tests).
- **Sprite magnification:** `VDP(1)=$E3` — 16×16 art renders 32×32 (4×4 characters).
  **Dragons are TWO stacked sprites (32×64 shown)**: def 1 head/neck over def 2 body/legs
  (slots 1–6, two per dragon); slain dragons collapse to the single belly-up def 3 at ground
  level. Bridge and bat use full single patterns; the player square stays 4×4 art (8×8 on
  screen) to thread 16px corridors. Dragon wall box is the central 8×16 (y+24..39); bite/sword
  centers are at (x+16, y+32).
- **Loop pacing:** fixed 30 Hz (two `WAIT`s per tick) on both machines; no `pacen` constant.
- **Zero per-frame VRAM reads**; collision is a RAM bit test on the 24-byte room bitmap.
- **Per-frame VRAM writes:** sprite attributes, plus (only when active) the 8-cell secret-wall
  flicker, one 8-byte glyph recolor in the secret room, and the fog window redraw on block
  crossings (≤ ~200 VPOKEs, well inside a 30 Hz tick).
- **ROM-resident tables:** room bitmaps (39 × 24 bytes), per-game link tables, and color
  triplets are read on demand with RESTORE + skip-loops — no RAM arrays for them (RAM use
  went *down* vs. the single-map version: 182 bytes TI / 171 Coleco).

## World structure (rooms 13–38, games 2–4)

```
                          [24 BLACK castle]--gate--[25 hall]--[26..28 DARK black maze,
                                |                              sealed DOT chamber in 28]
                          [19..23 BLUE maze (hyperspace links)]
                                |
[13 GOLD castle]--gate--[14 hall = WIN]
      |
[15 corridor W]--[16 corridor mid]--[17 corridor E]--(secret wall)--[18 SECRET room]
                                          |
                          [29..31 DARK catacombs (fog)]
                                |                 \
[32 WHITE castle]--gate--[33 hall]--[34..35 RED maze]   [36..38 side rooms]
```

- Game 2 uses the same screens with its own link table (catacombs/white castle/secret sealed
  off; room 17 is a dead end).
- Maze links include hyperspace-style inconsistent pairs (e.g. blue maze 20's E **and** W both
  lead to 21; leaving 22 north lands in 23 but 23's south goes to 20) — in the spirit of the
  original's letter-coded map connections.
- Castle halls have no inbound edge links (gate warps only), so the bat can never carry loot
  into a locked castle.

**Colors:** ALL lit rooms — including Game 1's — are colored walls on a **gray background**
(per-room `(wall,bg,dark)` triplets; BORDER + char-32 + wall-char colors set on entry), so
the **black castles are actually black** and the **black bat reads everywhere**. Dark rooms
invert: gray walls on black. **Castle doors (portcullis char) are always black.** The player
square wears the **current room's wall color**, exactly like the original avatar (walls
always contrast with the background, so it stays visible); the invisible dot is drawn in the
wall color too, like the original's wall-gray speck.

**Room format ("quarter characters"):** rooms are 32×24 grids of **8px cells** (one character
per cell), 4 bytes per row × 24 rows = 96 bytes. Custom rooms 0–12 are the old block layouts
mechanically bit-doubled (game 1 is pixel-identical); kingdom rooms 13–38 are fine-grid
originals. Thin 8px walls with 16px paths give the kingdom mazes the winding, multi-route
look of the cartridge: serpentine wall bands with staggered 2-cell doorways, vertical spur
posts, all mirrored left/right. Every wall band always has ≥1 doorway; E/W exits open at cell
rows 10–13 (y80–111), N/S gaps at cols 14–17 (x112–143) — the same pixel zones as before, so
links/warps/gates are unchanged.

**Doorway sealing:** on room entry, any doorway whose exit link is 255 *in the selected game*
is sealed in the RAM bitmap before drawing, so collision and visuals always agree (game 2
shares screens with the full kingdom but links fewer of them — its corridor-east room used to
show a south door that led nowhere and trapped the player).

## Objects (8) and creatures

| # | Object | Game 2 | Games 3/4 (game 4 scrambles 0–6) |
|---|--------|--------|-----------------------------------|
| 0 | Gold key | corridor W (15) | catacombs (30) |
| 1 | Black key | blue maze (21) | red maze end (35) |
| 2 | White key | — | blue maze (21) |
| 3 | Sword | gold hall (14) | corridor mid (16) |
| 4 | Bridge | — | catacombs (31) |
| 5 | Chalice | black hall (25) | black maze end (28) |
| 6 | Magnet | black hall (25) | black maze (27) |
| 7 | Dot | — | sealed chamber in 28 (invisible) |

- Carry one; touch = pick up/swap; FIRE = drop; carried objects keep their grab offset.
- **Magnet:** when lying in your room, every loose object there creeps 1px/tick toward it —
  straight line, through walls — until it rests beside it. The classic recovery tool (pulls
  the dot out of the sealed chamber).
- **Bridge:** rails-only grab, grid-snapped drop, dark channel-fill sprite; only way *into*
  sealed chambers.
- **Dot + secret room (games 3/4):** the dot is drawn in the room's **wall color** (near-
  invisible, like the original's wall-gray speck; silent pickup). Bring it to corridor E (17)
  with **2+ other objects** present and the east wall flickers (chars toggle each tick) and
  becomes passable → the SECRET room (18): "ADVENTIRE" / "2026 UNHUMAN AND CLAUDE" with
  rippling glyph colors (one glyph's color table row rewritten per tick; the title screen
  restores them).
- **Dragons:** yellow (corridor E / blue maze top), green (catacombs / black grounds), red =
  fast (blue maze, games 3/4 only). **They ignore walls entirely** (greedy longer-axis chase
  straight at you — the maze never protects you, only the sword does) and **pursue between
  rooms**: a live dragon in a room you leave bursts into your new room ~1.3s later (`fdl()`
  timers scheduled by `dchase` in `enterroom`), arriving at room center with a roar — both
  matching the cartridge's relentless dragons. Sword/swallow rules unchanged; swallowed →
  title.
- **Bat (games 1, 3, 4):** black, 32×32, flies through walls, roams via the link tables,
  steals objects (even carried ones; snatch them back). Softlock guards: never enters the
  secret room, never takes the bridge out of a chamber room (6/28), never swap-drops inside a
  sealed chamber.

## Dark rooms (fog of war)

Rooms flagged dark (black maze 26–28, catacombs 29–31): the room draws **nothing**; wall
cells within a 4-cell (32px) Chebyshev window of the player are drawn, and the window is
wiped and redrawn whenever the player crosses an 8px cell boundary (`fogenter`/`fogupd`/
`fogwipe`/`fogdraw`). Sprites (dragons, bat, objects) remain visible, like the original's
sprite layer.

## Engine notes (CVBasic specifics)

- **CVBasic pitfall:** 16-wide `BITMAP` lines are emitted in VDP **sprite column order**
  (every 16 lines: all left-half bytes, then all right-half bytes) — fine for `DEFINE
  SPRITE`, garbage for sequential `READ`. Room rows are therefore `DATA BYTE` with the
  32-cell art kept as a trailing comment (generated by `scratchpad/fixbitmap.py`-style
  conversion; hand-edit the hex + comment together).
- Room bitmaps (dispatched by a 39-label `ON rn GOTO` ladder to per-room `RESTORE`s), links,
  and colors are ROM `DATA`; player links cached per room (`pn/pe/ps/pw`), bat looks links up on
  demand.
- E/W arrivals snap to the rows-5/6 doorway if the landing spot is inside a wall, then pull
  one block inward if still stuck (`ewsnap`). Every E-link must target a room whose **west**
  edge opens at rows 5–6 (and W-links an open **east** edge) — blue maze 23's east link goes
  to 20, not 22, because 22's west edge is walled (that mismatch could strand the player
  inside a wall).
- No modulo (only `AND` masks); unsigned-safe compares via `adiff`; soft tick counter `tk`
  (FRAME parity never changes at 30 Hz); all `GOSUB` targets are `PROCEDURE`s and no `GOTO`
  escapes one (swallow restart is flagged out to main level).
- Gate rooms: 0/8/11 (game 1) and 13/24/32 (games 2–4) map to keys 0–2; warp targets and the
  hall→grounds return are room-pair special cases in `gwarp`/`gosouth`.
- Sound: SN76489 channel 0 blips/sweeps (pickup, drop, gate, roar, bat squeak), channel 3
  noise for a slain dragon; swallow wail and win fanfare inline.

## Acceptance criteria

1. Title: UP/DOWN selects GAME 1–4, FIRE starts; death/win return here with a full reset.
2. Game 1 plays exactly as before (same map, colors, rules).
3. Game 2: two castles, two dragons, no bat/dark rooms; completable (gold key → sword →
   black key → chalice home).
4. Games 3/4: black castle renders black-on-gray; bat is black; catacombs and black maze are
   dark with the reveal window following the player; magnet drags objects (including the dot
   out of the chamber); dot + 2 objects in room 17 opens the flickering east wall to the
   secret room with rippling credit text; game 4 scrambles object rooms but stays completable.
5. Both targets build clean and behave identically (`adventire_8.bin`, `adventire.rom`).
