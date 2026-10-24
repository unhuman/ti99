# Target profiles and budget reasoning

Use these profiles unless the user specifies otherwise. Record region explicitly;
use NTSC as the provisional target when none is given, while retaining the source
game's real-time speed and identifying any PAL-to-NTSC adaptation needed.

## Default machines

| Resource | ColecoVision | TI-99/4A + 32 KB |
|---|---|---|
| CPU | Z80 | TMS9900 |
| CPU RAM | 1,024 physical bytes; mirrored addresses are not extra RAM | 256-byte scratchpad plus 32,768-byte expansion |
| Video RAM | Separate 16,384 bytes, accessed through VDP ports | Separate 16,384 bytes, accessed through VDP ports |
| Cartridge | 32 KB direct window; identify mapper for larger banked ROM | 8 KB CPU cartridge window; identify mapper/banking for larger ROM |
| Extra hardware excluded | SGM, cartridge RAM, enhanced graphics/audio | SAMS, cartridge RAM, F18A, speech synthesizer, enhanced audio |
| Inputs to assess | Joystick, two fire buttons, keypad; special controllers separately | Keyboard and joystick; paddle/mouse adaptations separately |

Coleco mapping and memory sizes are documented in the manufacturer's
[Technical Manual, section III](https://www.colecovisionzone.com/downloads/cv_Technical_Manual.pdf).
The TI expansion occupies >2000-3FFF and >A000-FFFF; cartridge ROM and expansion
RAM are different resources. See TI's
[Console and Peripheral Expansion System Technical Data, memory map](https://ftp.whtech.com/datasheets%20and%20manuals/Hardware/Texas%20Instruments/TI-994A%20Console%20and%20Perhipheral%20Expansion%20System%20Technical%20Data%201049717-2%20%281983%29.pdf).

### Graphics and sound limits shared by the baseline targets

The TMS9918-family graphics modes provide a 256x192 active area, 32 sprite
entries and a four-sprite-per-scanline limit. Each sprite has one visible color;
layered colors consume more entries and line capacity. Graphics II bitmap
colors are constrained to two colors per eight-pixel horizontal group. There
is no general hardware pixel-scroll register. See the TI
[VDP Data Manual](https://computers.baffa.tec.br/pages/datasheet/TMS9918A_TMS9928A_TMS9929A_Video_Display_Processors_Data_Manual_Nov82.pdf).

Both baseline sound systems provide three tone channels and noise, rather than
SID/POKEY-compatible register behavior. Budget any software envelopes, channel
sharing, samples, or speech alongside gameplay. Check noise/tone coupling and
the actual PSG variant before claiming exact effects. Neither baseline includes
the TI speech synthesizer. The PSG architecture is described by TI's
[SN76489AN data sheet](https://map.grauw.nl/resources/sound/texas_instruments_sn76489an.pdf).

## Turn constraints into a proposed implementation budget

- Account separately for game state, runtime/workspaces, stack and interrupts,
  input/audio state, decode/scroll buffers, and code that must execute from RAM.
  Do not allocate the entire nominal RAM capacity to source game variables.
- Account for all VDP tables and buffers before proposing spare VRAM as storage.
  It is not CPU-addressable RAM: accesses cost time and must preserve VDP address
  transaction ordering. Code cannot simply execute from it.
- For ROM, allow translated code expansion, assets, optional precomputed frames,
  fixed-bank helpers and mapper overhead. Do not import Parsec's expansion ratio
  or free-bank counts as measurements for a new CPU/game.
- Map actual busy scenes to target sprites/backgrounds. Count overlapping pieces
  per scanline, not only objects or total sprites. Quantify cropping/scaling and
  its effect on visibility, collision geometry, and reaction time.
- Propose scroll strategies such as changed tiles, pre-shifted patterns, or
  partial bitmap updates only with an estimated VRAM layout and transfer cost.
  Flicker, slower scrolling, or reduced object counts are compromises to expose.
- Model target work using documented instruction costs and memory wait states
  where applicable. On TI, scratchpad and external-memory execution differ.
  Reserve time for input, audio, interrupts, and worst-case rendering.

Report each budget as measured, estimated, or unknown; include the assumptions
behind any lower/upper bounds. A source footprint is evidence for a design,
not automatically the target footprint after a native rewrite.

## Alternatives

Keep baseline verdicts even if an expansion would help. Name the exact hardware,
usable memory/map, compatibility effect, and the bottleneck it resolves. Verify
specifications before assigning capacities; more RAM does not repair an
unsupported graphics mode or reproduce a SID filter. Do not silently substitute
an XL/XE, Apple IIgs, enhanced VDP, or emulator-only feature for a named machine.

A ROM-only cartridge with a documented mapper is allowed by the default; onboard
RAM or a coprocessor is additional hardware and must be labeled as such. Save
games and persistent scores require an explicit storage design; source disk
writes cannot be assumed to work on a ROM cartridge.
