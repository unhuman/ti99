# Apple II source assessment

## Establish the model and loaded program

Distinguish II/II+, IIe (including enhanced 65C02), and IIc requirements. Determine
whether auxiliary/language-card RAM, double-hi-res, or a sound card is required.
An Apple IIgs program is a different architecture and needs a separate scope;
do not treat all Apple-branded disk images as baseline 6502 games.

Identify disk/container format, boot code, DOS/ProDOS or custom loader use, and
the executable after loading/decompression. Preserve the original image and
record the provenance of extracted memory. A sector image's byte order is not
automatically an executable memory map; a boot snapshot may omit later levels.

## Questions that can change the verdict

- **Display:** identify text/lo-res/hi-res modes, page switching, mixed regions,
  and any auxiliary-memory modes. Decode the interleaved screen layout before
  measuring dirty areas or extracting art. Baseline hi-res is nominally 280x192;
  composite artifact colors depend on pixel arrangement. A monochrome bitmap or
  emulator RGB setting is not necessarily the intended color image. Compare
  against the game's intended display configuration. See Apple's
  [1978 Reference Manual](https://apple2history.org/dl/Apple_II_Redbook.pdf).
- **Software rendering:** inspect erase/redraw routines, saved backgrounds,
  collision tests against pixels, and pre-shifted shapes. Replacing the renderer
  with target sprites may save CPU while changing collision semantics. Count
  required colors/layers and per-line overlap before calling that a solution.
- **Sound and timing:** standard speaker output is toggled through $C030;
  software timing creates the waveform. Determine whether sound stalls gameplay,
  interleaves with rendering/input, or uses cycle-sensitive samples. Replacing
  a blocking sound loop can change game speed even if the new tone sounds right.
  See Apple's [II/II+ Service Manual, speaker section](https://www.digibarn.com/friends/curbow/Apple2Level2ServiceMan1981.pdf).
- **Machine dependencies:** inspect paddle timing, keyboard/strobe behavior,
  display-related timing tricks, bank-switch soft switches, and OS calls. Check
  whether disk loads, protection routines, or sound-card interrupts are required
  during play or only during boot. Keep unresolved loading separate from an
  actual gameplay hardware mismatch.

Model-specific graphics or cards require their own authoritative documentation;
do not generalize baseline speaker or memory behavior to every Apple II release.

## Focused evidence collection

[AppleWin](https://github.com/AppleWin/AppleWin) includes a symbolic debugger and
multiple machine/video configurations. Read the installed debugger help before
using commands; record the selected model, CPU, RAM/cards, video mode, and speed.
Do not rely on an emulator's fast-disk or accelerated CPU mode for timing claims.

Use code and access traces to identify changing state and important renderer,
speaker, and input routines. Capture an audio-heavy scene if sound pacing is a
decision risk. Compare color captures with the original display intent before
estimating target color compromises. Distinguish measured pixel changes from
the amount of target VRAM work needed to display them.

Fixed scenes and compact state can be favorable. Software graphics are not
automatically easier than hardware sprites: resolution, color rules, buffers,
and pixel-based game logic may dominate the conversion.
