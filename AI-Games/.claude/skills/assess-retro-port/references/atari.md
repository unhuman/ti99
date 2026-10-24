# Atari 400/800 source assessment

## Establish the actual machine

Record cartridge/executable/disk format, mapper, required RAM, OS revision,
CTIA versus GTIA, and PAL/NTSC. Check whether the supplied release really runs
on a 400/800 or requires XL/XE memory or other later features. Do not silently
use an expanded emulator configuration to make the source run.

Distinguish direct hardware access from OS shadow registers and vertical-blank
services. Inspect initialization and interrupt vectors alongside gameplay;
an OS call may conceal display, input, timer, or audio work. Identify later
loads and code overlays before treating the initial executable as complete.

## Questions that can change the verdict

- **ANTIC display:** follow the active display list, screen addresses, modes,
  fine scrolling, and display-list interrupts. Convert the actual mixed display
  into target regions; a single advertised resolution misses line-by-line use.
- **Moving objects:** inspect player/missile data, sizes, priorities, collision
  reads, and reuse during the frame. Derive target sprite pieces and scanline
  overlap from the composed scene. Source object counts alone are insufficient.
- **Scheduling:** determine whether VBI, DLI, POKEY timers, scanline waits, or
  polling drive each subsystem. Account for ANTIC DMA when interpreting source
  CPU traces; hardware-assisted scrolling can become significant target work.
- **POKEY:** separate music/effect events from channel configuration, joined
  frequency channels, distortion, and filters. Inspect RANDOM reads and their
  timing dependencies. A hardware random source cannot be replaced with one
  observed sequence; decide what original behavior/distribution must be retained
  and what remains uncertain.

These hardware facilities are documented in Atari's [De Re Atari](https://www.musanim.com/mam/DeReAtari.pdf),
especially chapters 2, 4-7 and 8. Consult the actual chapter for register-level
details instead of inferring them from a screenshot.

Also inspect console keys, paddles, multi-controller requirements, disk/SIO
services, and persistent storage. A two-player scheme may be straightforward;
four-player or analog controls require an explicit target mapping. Treat code
using undocumented CPU behavior or self-modifying routines as translation work
to investigate, not an automatic rejection.

## Focused evidence collection

[Altirra's developer documentation and releases](https://www.virtualdub.org/altirra.html)
provide the starting point for debugger/history facilities. Consult the locally
installed help before choosing commands or export formats; do not assume a
particular automation API. Record the machine configuration with each capture.

Start with a display-list/interrupt overview, then investigate the densest scene
or scroll transition relevant to the decision. Distinguish CPU writes to display
memory from ANTIC's reads. If only a short initial wave is reachable, label
later-level complexity unknown. An original timing or random algorithm needs
code evidence, even when sampled paths look convincing.

Report whether replacing ANTIC/GTIA work remains within the target's proposed
frame and memory budgets, and separately whether changed colors, raster effects,
or POKEY timbre are acceptable under the requested fidelity goal.
