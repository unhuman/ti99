# Adventire

An Atari-2600-*Adventure*-style quest (original code/art/maps) for **TI-99/4A** and
**ColecoVision**, written in CVBasic — one source, both machines.

**Quest:** open the gold castle, take the sword, win the white key from the red dragon's maze,
fetch the **bridge** from the white castle, bridge into the sealed cave chamber for the black
key, brave the black castle, and carry the chalice back **inside the gold castle** — alive.
Three castles, three dragons, a thieving bat.

## Controls

- **Joystick** — move (8-way, walls slide)
- **Touch an object** — pick it up (you carry one; touching another swaps). It rides at the
  spot where you grabbed it — grab the sword on your left to fight dragons on your left.
- **FIRE** — drop what you're carrying
- Touch a gate while carrying its key to open it; walk up into the open archway to enter.
- The sword kills dragons on contact, carried or lying — keep it between you and the dragon.
- The **bridge**: drop it across a wall and walk through its dark channel (it snaps to the
  wall grid when dropped). Grab it by the **rails** — the channel is for walking, so crossing
  never picks it back up. Only way into the sealed cave chamber. You can't pick it up while
  standing inside a wall.
- The **bat** steals things — even out of your hands. Chase it and snatch them back.
- Swallowed? Press FIRE for a fresh game (full reset, like the console switch).

## Status

🎮 Playable — three castles / three dragons / bat / bridge version. Compiles clean for both
targets; needs an emulator gameplay pass.

## Build

```
bash games/Adventire/build-ti.sh        # -> src/adventire_8.bin  (Classic99 / js99er)
bash games/Adventire/build-coleco.sh    # -> src/adventire.rom    (CoolCV / blueMSX)
```

(Or the shared skill script: `bash .claude/skills/build-cvbasic-game/build.sh
games/Adventire/src/adventire.bas ADVENTIRE` — note cvbasic.exe needs `C:\cygwin64\bin`
reachable for `cygwin1.dll`; run the stages from PowerShell if Git Bash's PATH fights cygwin.)

See `DESIGN.md` for the map, rules, and engine notes.
