# Astiroids — Design

> CVBasic (`--ti994a`) game — native TMS9900 **bank-switched cartridge ROM**, *not* an
> XB256/XB-compiler game. The repo `CLAUDE.md` is the XB256 platform spec; the CVBasic notes
> here supersede it for this game. Sibling CVBasic project: `games/mspacman-cv-xb-port`.

This document describes the game **as built**. Source of truth is `src/ASTIROIDS.bas`
(+ `assets/sprites.bas`); keep this file in sync with any behavior change.

---

## 1. Concept & Objective

- **Pitch:** Classic vector-style Asteroids for the TI-99/4A. Rotate, thrust through inertial
  space, shoot rocks, dodge the flying saucer, survive.
- **Win a wave:** destroy every asteroid. The next wave starts with one more large rock (cap 6).
- **Lose a life:** the ship touches an asteroid, is hit by a UFO bullet, or **crashes into the
  saucer itself** (which destroys the saucer too). Start with 3 lives; game over at zero. Extra
  life every 10,000 points (no cap).

---

## 2. Controls (joystick 1)

| Action | Input | Behavior |
|---|---|---|
| Rotate left / right | `cont1.left` / `cont1.right` | `sangle` ±1 mod 16. Step cooldown alternates 2/3 frames (avg 2.5). |
| Thrust | `cont1.up` | Adds the facing vector to velocity **every other frame** (gentle ramp). Pure inertia, no friction. Top speed ±294 (≈4.6 px/frame). |
| Fire | `cont1.button` | Up to 4 bullets; `fire_cd=12` between shots. Bullet velocity = facing·8 **plus the ship's current velocity** (inertia). Lifetime 25 frames. |
| Hyperspace | `cont1.down` | Teleport to a random spot. **No invincibility** — you reappear live and vulnerable. Debounced (`hyp_cd=45`) so a held DOWN can't spam-jump. |

In-game play is joystick-only. The **keyboard** is read (via `CONT1.KEY`) only on the title screen,
for the `8 3 8` setup code and the number-key field entry (see §11).

---

## 3. Screen & HUD

- **Mode:** CVBasic TI-99 bitmap mode (TMS9918A, 256×192, 32×24 character grid). Black background (`BORDER 1`).
- **VDP 2× sprite magnification** is enabled at startup via a single inline-ASM write to VDP
  register 1 (`>E3`: 16×16 sprites, MAG on). Every 16×16 sprite renders **32×32** on screen; a
  cell-centered art uses a **16 px** sprite-box offset. The **ship** instead anchors its art toward
  the cell's top-left (see §5) and renders at offset **11**, so its hardware coordinate stays
  non-negative at the top/left edges.
- **`SPRITE FLICKER ON`** — when >4 sprites share a scanline (late waves), CVBasic rotates priority
  so they flicker instead of vanishing.

**HUD (top row, drawn by `hud_draw` / `lives_draw`):**

```
[score]  [ship icons = lives-1]                 [HI: hiscore]
```

- **Score** at top-left, no label, stored ÷10 with a trailing `0` appended on display.
- **Reserve ships** as little white ship icons (char 128) right after the score — shows
  `lives` while no ship is on screen, `lives-1` once the ship is live (the one in play isn't counted).
- **`HI:` high score** at top-right; persists across games for the session.
- The **title screen** reuses `hud_draw`, so score/high-score sit in the same corners there.

---

## 4. Sprites

### Hardware slot assignment (32 slots, all used)

| Slot(s) | Entity |
|---|---|
| 0 | Ship (also plays the ship-explosion frames on death) |
| 1 | Thrust flame |
| 2–5 | Player bullets (max 4) |
| 6 | UFO (large/small; plays explosion in-place when shot) |
| 7 | UFO bullet (1 at a time) |
| 8–31 | Asteroid pool (24 slots: active / exploding / hidden) |

### Pattern table (def → `SPRITE name = def*4`)

| Def(s) | Name(s) | Contents |
|---|---|---|
| 0–15 | 0–60 | Ship: 16 rotation frames, 22.5° each, nose-up at def 0. Cardinals (0/4/8/12) are a symmetric flaring triangle to a 1-px point (≈7×8 art); diagonals hand-drawn. All 16 frames shifted **−2,−2** in-cell (top-left anchored) for the offset-11 render (see §5). |
| 16–17 | 64–68 | Thrust flame, 2 frames |
| 18 | 72 | Bullet — single art pixel (→ 2×2 magnified) |
| 19–21 | 76/80/84 | Asteroid large, 3 tumble frames (recentered in cell) |
| 22–23 | 88/92 | Asteroid medium, 2 tumble frames |
| 24 | 96 | Asteroid small, 1 frame |
| 25 | 100 | UFO large (skirt 10px wide — trimmed 1 art-col/side) |
| 26 | 104 | UFO small |
| 27–30 | 108–120 | Explosion, 4 frames (shared by ship / asteroids / UFO, played in place) |
| 31 | 124 | (spare; HUD ship icon is char 128, not a sprite) |

> Art is in `assets/sprites.bas`. The 4 **cardinal** ship frames are generated as exact 90°
> rotations of one hand-authored symmetric triangle (so N/S/E/W stay mirror-symmetric); the
> asteroid bitmaps are **recentered** in their 16×16 cells so the collision box lines up with
> what's drawn.

### Explosion reuse

A dying entity keeps its slot and cycles explosion frames 27→30 in place, then hides (Y=`$D1`).
While exploding it is **not** collidable. Asteroid splits: the parent slot explodes; up to 2
children spawn into free pool slots at the parent's position.

### Colors

Ship 15 (white) · thrust 11 (lt yellow) · bullet 15 · large asteroid 6 (cyan) · medium 11 ·
small 15 · UFO large 9 (red) · UFO small 13 (magenta) · explosions 15. HUD ship icon (char 128)
is white — **bitmap mode needs 8 color bytes per char** (one per row), not 1.

---

## 5. Physics

### Fixed-point ×64

All positions are 16-bit (`#`) variables scaled ×64: pixel = value/64. Screen 256×192 → ranges
0..16383 / 0..12287.

### Ship velocity & wrap

- `#svx, #svy` accumulate thrust; capped at ±294. Applied to position every frame.
- **The ship pops fully across edges (no straddle/slide-in).** The center is wrapped within
  **X 11..245** (`#spx` 704..15680, band 14976) and **Y 11..181** (`#spy` 704..11584, band 10880).
  Reaching one limit jumps it to the opposite limit, fully visible.
- **Top-left art anchoring kills most of the "pop."** The ship art is shifted **−2,−2** within its
  cell (`assets/sprites.bas`, applied uniformly to all 16 frames so the rotation orbit is preserved)
  so the rotation pivot sits at cell (5.5, 5.5) = box **11**, and the live ship renders at
  **offset 11** instead of 16 (`SPRITE 0,spy-11,spx-11`; the thrust flame and in-place explosion
  stay at 16 because their art is cell-centered and their visual center is still `(spx,spy)`). With
  the empty magnification margin pushed off the **bottom-right** (clipped harmlessly), the hardware
  coordinate `center-11` stays ≥0 at the top/left edges — no negative coord, no VDP dead zone — so
  the nose now grazes **y=0** at the top, **y=192** at the bottom, and the ship reaches the side
  edges with only its inherent (narrow-orientation) margin instead of the old ~6–10 px box inset.
  Collision (`chk_coll`), UFO aiming, and child-asteroid spawn are unchanged: stored position is
  still the visual center, so they keep working center-to-center.

### Rotation

16 steps. Sin/cos tables (×64, signed) in `#sin_t`/`#cos_t`; ship frame = `sangle*4`.

### Thrust flame (slot 1)

Anchored just behind each frame's **actual rear edge** (the engine), on the ship axis, via a
**per-frame pixel-offset table** `#fdx_t`/`#fdy_t` (16 entries each): `fpx=spx+#fdx_t(sangle)`,
`fpy=spy+#fdy_t(sangle)`. The flame art centers on cell (row 8, col 7), so it renders at
`SPRITE 1,fpy-16,fpx-14`. A single fixed distance can't work — the rotation pivot (cell 5.5,5.5)
sits ~3 px from the tail on cardinals but ~7 px on the (larger) diagonal frames, so a constant
offset floats on cardinals and embeds on diagonals. The table is precomputed from the real art by
`tools/flame_offsets.py` (rear-edge centroid + a small gap along the −nose axis); re-run it if the
ship art changes. It is **addition-only** (no per-frame divide), sidestepping the unsigned-divide
trap entirely.

### Asteroids

`#avx/#avy` velocities; **wrap the full screen** (0..16384 / 0..12288) with a signed-safe
two-branch wrap. **Render guard** keeps rocks drawn right out to the left/right edges and only
hides them in a 4-px top/bottom dead band (`apy>=4 AND apy<=188`) — symmetric top↔bottom, no early
left/right pop-out. (Top=4 lets a rock graze the very top rows as it wraps; deliberate, so objects
display fully rather than blinking out early.)

### Bullets

4 slots. Velocity inherits ship inertia. Lifetime 25 frames (~200 px). A bullet that hits
something **stops scanning that frame** (one bullet = one hit; it can't also catch the fragments
it just spawned). Same render-guard rule as asteroids: shown to the L/R edges, hidden only in the
4-px top/bottom band.

---

## 6. Ship lifecycle (`ship_st`)

| `ship_st` | Meaning |
|---|---|
| 0 | Alive, vulnerable (collisions checked) |
| 1 | Spawn invincibility — blinks, not collidable, `ship_tmr=90` (1.5 s) |
| 2 | Exploding (plays explosion frames) |
| 3 | Respawn delay |

A life is consumed in `ship_die` (so the HUD reserve is correct through the explosion);
game-over is decided when the explosion ends. Respawn re-centers the ship.

**Game over** silences sound and prints `GAME OVER` over the **frozen final frame** — it does *not*
wipe the sprites, so the last asteroid field stays on screen behind the text. The sprites are
cleared (and a fresh title field rebuilt) only when control returns to the `title` routine.

---

## 7. Waves

- Starting large asteroids = `wave + 2`, capped at 6. Rocks spawn at the screen edges.
- **Clearing a wave does NOT reset play.** A ~2.5 s **free-flight gap** (`wave_gap=150`) follows:
  the ship keeps its position and momentum so the player can fly toward the middle before the
  next wave's rocks appear. The *first* wave of a new game still centers the ship with `GET READY`.
- **Starting wave** is normally 1, but the 838 setup screen (§11) can start the game at level 1–9
  (`start_wave`, clamped). Higher start = more/faster rocks immediately and small saucers from the
  off (wave ≥ 4).

---

## 8. UFO system

- **Spawn:** `#utimer` counts down — 450 frames (~7.5 s) to the first UFO, then 900 (wave<4) /
  600 recurring. Wave <4 spawns large only; wave ≥4 is 40% small / 60% large.
- **Stall watchdog:** two per-frame clocks pull the next saucer in sooner when the player is
  coasting. `#nokill` (frames since any rock was destroyed, reset in `ast_hit`) > 420 (~7 s), or
  `#wage` (frames since the wave started, reset in `spawn_wave`) > 1800 (~30 s), makes `#utimer`
  drain **4× faster** — so saucers keep coming if you stop shooting or can't clear the wave. Both
  clocks are capped < 30000 to stay inside the unsigned-compare-safe range.
- **Movement:** enters from a random edge and **despawns when it reaches the far edge**
  (direction-aware test — `ux` is 8-bit, so the old `<0`/`>255` tests were dead code and the UFO
  never left). **Small saucers are faster and jumpier:** ±3 px/frame (large ±2), and they re-pick
  a vertical step of −2..+2 every 12 frames vs the large UFO's occasional ±1 every 20.
- **Fire (rapid, no waiting):** the saucer fires a steady stream as it crosses — large every 16
  frames, small every 12 (first shot 14 frames after it appears). Each shot either **aims at the
  ship** (closest of 16 headings via `ufo_aim`) or
  goes in a random direction: **large aims 20% of shots, small aims 40%.** One UFO bullet at a
  time; it's cleared when the UFO leaves or dies (no stranded dot). The UFO bullet also **shatters
  asteroids** it strikes (no points to the player). It **wraps around the screen** (X via the 8-bit
  256-px width, Y folded into 0..191) for its whole `ublife=80`, rather than dying at an edge.
- **Aiming (`ufo_aim`):** the target vector is reduced to magnitude ≤63 by **sign-safe halving**
  (not unsigned divide), then the best of 16 headings is chosen by an argmax of `dx·sin − dy·cos`
  **offset by +16384** so the comparison stays in the unsigned-safe positive range. UFO-bullet
  velocity comes from a precomputed signed `#bv_t` table (= sin/16), never `sin*4/64` at runtime
  (that unsigned divide turned negative components into huge values — a prior latent bug).
- **Collisions:** the saucer is destroyed (no player points) if it **crashes into an asteroid**
  (the rock breaks up too) or **into the ship** (which also kills the ship). When shot by the
  player it scores once.
- **Death:** the UFO plays the shared explosion in place (`uexp`) and can't be re-hit while
  exploding.
- **Sound:** channel 2 plays a two-tone engine warble while a UFO is active (pitched by size); each
  shot briefly overrides it with a descending "pew" — higher-pitched for the small saucer.

---

## 9. Scoring

Score stored ÷10 (`#score`); display appends `0`.

| Target | Stored | Shown |
|---|---|---|
| Large asteroid | 2 | 20 |
| Medium asteroid | 5 | 50 |
| Small asteroid | 10 | 100 |
| Large UFO | 20 | 200 |
| Small UFO | 100 | 1,000 |

Extra life each time `#score/1000` crosses a new integer (every 10,000 points), tracked by
`last_extra`, no cap. `#hiscore` holds the session high; **not** reset by `game_init`.

---

## 10. Sound (SN76489)

Channels 0–2 are tone, channel 3 is noise. The mixer lives in `sfx_t` (run every frame):

- **Tone channels (0/1/2) are envelope/sweep-driven.** Each holds a current frequency `#fN`, a
  per-frame step `#dN` (0 = steady tone), a volume `vN`, and a frame countdown `sfxN`. A trigger
  just sets those four; `sfx_t` advances the sweep and re-issues `SOUND` until the timer hits 0.
  Sweep clamp respects the unsigned-compare trap: an underflow past 0 wraps to ~65000, so the
  `>=32768` floor check runs **first**, then the 90 Hz / 8000 Hz range pins.
- **Channel 3 (noise) is owned by explosions, lent to thrust.** Explosions set a noise type +
  start volume + duration and **fade the volume each frame** (the envelope that makes them read as
  a "boom" rather than a flat blip), louder/longer for bigger rocks and the ship. When no explosion
  is active, holding thrust hisses a low rocket rumble on the same channel; it silences on release.
- **Heartbeat** (ch 0) alternates two low tones, tempo `hbeat_rate = 120 - ast_count*4` (min 30) so
  it quickens as the field thins; it goes silent during the ship-death explosion so the two don't
  fight.
- **Player fire** = a fast descending "pew" on ch 1. **UFO** = a two-tone engine warble on ch 2
  with a descending shot "pew" over it (higher pitch for the small saucer). **Ship death** = a long
  descending tone (ch 0) over a big noise rumble. **Extra life** = a short rising chime (ch 0).
- **Sounds are cut at the right boundaries.** A shared `snd_off` silences all four channels and
  zeroes the mixer state. It runs when the **ship-death explosion finishes** (so nothing carries
  into the respawn/reset), and the saucer's ch-2 hum is cut the moment its explosion ends. The
  **title screen is fully silent** — it doesn't tick the heartbeat or the mixer at all.

---

## 11. Title screen & 838 setup

Centered: `* * * ASTIROIDS * * *`, `TI-99/4A CVBASIC`, the control list (labels padded to 6 chars
so the colons align), `2026 UNHUMAN`, and `PRESS FIRE TO BEGIN` on the bottom row. Score +
high-score show at the top via `hud_draw`. Six asteroids drift/tumble behind the text (reusing
`upd_ast` + `render`). The screen is **silent** — no heartbeat or mixer tick. FIRE starts a normal
game (3 ships, level 1).

### 838 setup mode

Typing **`8 3 8`** on the keyboard at the title (read via `CONT1.KEY`: a digit key returns its
value, 15 = nothing pressed; a small `code_st` state machine, debounced on key-down with `lastk`,
watches for the sequence) opens a **silent** setup screen (`setup838`):

- **`SHIPS:`** and **`LEVEL:`** fields with a `>` cursor on the active one. The **first** number key
  `1–9` sets ships (cursor moves to LEVEL); the next sets the starting level. **FIRE** begins
  (debounced so a held button can't auto-start).
- The chosen values flow through `start_lives` / `start_wave` into `game_init`
  (`lives = start_lives`, `wave = start_wave`, both clamped 1–9). A plain FIRE-to-start leaves the
  defaults (3 / 1). Reserve-ship HUD icons still cap at 6, but `lives` itself is honored.

---

## 12. CVBasic gotchas honored (see also the repo memory)

CVBasic (`--ti994a`) compiles 16-bit (`#`) **comparisons and division as unsigned**, which silently
breaks signed logic. These bit this game repeatedly and the fixes are load-bearing:

- **Unsigned compare** → speed caps, split-velocity caps, and all screen wraps split at 32768
  (`IF #v>=32768` detects "negative") instead of testing `<0`.
- **Unsigned divide** → never `#signed/2`; thrust is halved by applying it every other frame, not
  by dividing the sin/cos table. The thrust-flame offset hit this first as `#cos_t*8/64` (flame flew
  to garbage where cos<0); if you must divide, fold the signed term into an always-positive sum
  first, `(#spy+8*#cos_t(sangle))/64` (parens required, or `/` binds first). The flame ultimately
  went **table-driven** (`#fdx_t`/`#fdy_t`, addition-only) — the most reliable escape from the trap.
- **`ABS(a-b)` on 8-bit vars is wrong** (the byte subtract underflows and `abs` can't recover the
  sign) → collision deltas are computed in 16-bit (`#cdx = #bx/64 - #ax/64`) so `ABS` is signed.
- **Sprite edges:** the VDP gives no clean per-pixel horizontal wrap and a vertical dead zone, so
  the ship is kept fully on-screen and *popped* across edges rather than relying on hardware wrap.
- **Bitmap mode char color = 8 bytes/char** (one per row), or unset rows render garbage colors.

---

## 13. Build & run

```
bash .claude/skills/build-cvbasic-game/build.sh games/Asteroids/src/ASTIROIDS.bas "ASTIROIDS"
```

(Equivalent: `cvbasic --ti994a … ASTIROIDS.a99 "<CVBASIC_DIR>/"` → `xas99 -b -R` → `linkticart.py …
ASTIROIDS_8.bin "ASTIROIDS"`.) The skill builds and compile-checks only; load `ASTIROIDS_8.bin`
in **Classic99** / **js99er** as a cartridge to play. Generated artifacts (`.a99/.bin/.txt/_8.bin`)
are git-ignored.

---

## 14. Acceptance criteria

- [x] 16-step rotation; inertial thrust that tracks the aimed direction; ±294 top speed
- [x] ≤4 bullets, inherit ship inertia, expire ~200 px; one bullet hits one thing
- [x] Large→2 medium→2 small→gone; explosion plays in place; 24-slot pool never leaks
- [x] Collisions register from any direction (16-bit ABS); ship dies on rock / UFO-bullet / UFO-body contact
- [x] UFO appears (~7.5 s), moves, despawns at the far edge, fires continuously, explodes when shot
- [x] Small UFO is faster/jumpier; large aims 20% of shots, small 40%; UFO bullets and the UFO body shatter asteroids
- [x] Saucers come more often, and the stall watchdog (no kill ~7 s / wave uncleared ~30 s) brings them out ~4× faster
- [x] Distinct, enveloped sounds: fire "pew", higher-pitched small-UFO shot, decaying-noise explosions, thrust rumble
- [x] Title **and** 838 setup are silent; all sound is cut when the ship-death explosion ends and when the saucer leaves
- [x] Heartbeat tempo rises as the field thins
- [x] Score shows ×10 with trailing 0; extra life every 10,000; high score persists in session
- [x] Hyperspace teleports with no protection, debounced
- [x] Ship nose reaches all four screen edges (top-left art anchoring, render offset 11); pops across edges; rotation doesn't wobble; N/S/E/W frames symmetric with a crisp 1-px point
- [x] UFO bullets wrap around the screen (don't die at an edge)
- [x] Asteroids/bullets show to the L/R edges, hide only in the symmetric 4-px top/bottom band
- [x] `8 3 8` opens setup; number keys set ships (1–9) and starting level (1–9); FIRE starts with them; plain FIRE = 3 ships / level 1
- [x] Wave clear gives a free-flight gap (no re-center) before the next wave
- [x] Cartridge ROM matches interpreted behavior
