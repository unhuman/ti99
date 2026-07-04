# Adventire

An Atari-2600-*Adventure*-style quest (original code/art/room data) for **TI-99/4A** and
**ColecoVision**, written in CVBasic — one source, both machines.

**Four games** on the title screen (UP/DOWN + FIRE):

1. **INTRO KINGDOM** — our original 13-room map: a gentle introduction.
2. **SMALL KINGDOM** — compact kingdom: gold + black castles, blue maze, two dragons.
3. **FULL KINGDOM** — the big map: three castles, dark catacombs and black-castle maze
   (fog of war), red maze, magnet, bat, and a hidden secret room.
4. **RANDOM KINGDOM** — the full kingdom with object locations scrambled each game.

**Quest (all games):** find keys, open castles, get the sword past the dragons, and carry the
chalice home **inside the gold castle** — alive.

## Controls

- **Joystick** — move (8-way, walls slide)
- **Touch an object** — pick it up (you carry one; touching another swaps). It rides at the
  spot where you grabbed it.
- **FIRE** — drop what you're carrying
- Touch a gate while carrying its key to open it; walk up into the open archway to enter.
- The **sword** kills dragons on contact, carried or lying. The red dragon is faster.
- The **bridge**: grab by the rails, drop across a wall (snaps to the grid), walk the dark
  channel. The only way into sealed chambers.
- The **magnet** drags every loose object in the room toward it — through walls.
- The **bat** steals things — even from your hands. Chase it and snatch them back.
- **Dark rooms** (games 3/4) reveal walls only near you.
- Somewhere in the black castle's maze hides an **invisible dot**… the east end of the
  corridor row rewards the curious.
- Swallowed or victorious → back to the title. Every start is a fresh kingdom.

## Status

🎮 Playable — 4-game version (intro map + documented-structure kingdom with magnet, dot,
fog, bat). Compiles clean for both targets; needs an emulator gameplay pass.

## Build

```
bash games/Adventire/build-ti.sh        # -> src/adventire_8.bin  (Classic99 / js99er)
bash games/Adventire/build-coleco.sh    # -> src/adventire.rom    (CoolCV / blueMSX)
```

(Or the shared skill script: `bash .claude/skills/build-cvbasic-game/build.sh
games/Adventire/src/adventire.bas ADVENTIRE` — note cvbasic.exe needs `C:\cygwin64\bin`
reachable for `cygwin1.dll`; run the stages from PowerShell if Git Bash's PATH fights cygwin.)

See `DESIGN.md` for the world map, per-game object tables, and engine notes.
