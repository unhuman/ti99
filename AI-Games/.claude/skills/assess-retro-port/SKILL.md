---
name: assess-retro-port
description: >-
  Assess whether a Commodore 64, Atari 400/800, or Apple II game is a good
  conversion candidate for ColecoVision and TI-99/4A. Use for feasibility
  reviews, candidate shortlists, hardware requirements, and fidelity or
  effort comparisons before porting. Inspect supplied binaries and relevant
  original code, then use focused runtime evidence where useful. Produces
  separate target verdicts; does not start a conversion.
---

# Assess a retro game for conversion

Give the user a defensible decision about whether a particular game is worth
porting, what would have to change, and what remains unknown. Preserve the
original gameplay algorithms and variability as the intended fidelity goal;
do not judge feasibility solely by recreating the appearance of one playthrough.

## Load only the relevant references

- Always read [target budgets](references/targets.md) and the
  [report format](references/report-format.md).
- For the source being assessed, read [Commodore 64](references/c64.md),
  [Atari 400/800](references/atari.md), or [Apple II](references/apple-ii.md).
  A comparison across versions may need more than one guide.

Default targets are **stock ColecoVision with ROM banking allowed**, and
**TI-99/4A with 32 KB RAM expansion and standard video/sound**. State these
profiles in each report. Other expansions are separate alternatives, never
silently included in the default verdict. Honor explicit user requirements
for hardware, region, fidelity, assessment depth, or selected targets.

## Staged investigation

### 1. Identify the game and available evidence

Search the project and supplied files before asking for missing inputs.
Record image paths, sizes, SHA-256 hashes, release/revision, media format,
source machine/CPU, RAM requirements, and PAL/NTSC configuration. Distinguish
verified facts from labels inferred from filenames or catalogs. Keep original
images unchanged; associate extracted/decompressed evidence with its source.

Locate existing source, disassemblies, documented ports, emulator/debugger
tools, and prior measurements. Source code from a different release is a lead,
not proof about the supplied binary. Do not fetch replacement game/firmware
images without a user request. If images are absent, offer a clearly preliminary
document-based screen and identify exactly what evidence is missing.

### 2. Screen the likely constraints

Inspect entry points, loaders, bank switching, code/data boundaries, interrupt
handlers, OS calls, and important hardware accesses. Identify interpreted code,
including BASIC, before assuming that a 6502 disassembly represents the game.
Use recursive/control-flow and runtime evidence; a linear sweep through data is
not a reliable disassembly. Record unresolved indirect calls and loaded overlays.

Estimate the target cost of changing state, rendering, audio, input, and disk
services. Fixed assets and code can often move to ROM; writable state cannot.
Avoid rejecting a game from its source RAM configuration or image size alone.
Conversely, banked ROM does not solve a demonstrated working-RAM shortage.

Identify the few uncertainties that could change either target's verdict.
If an unavoidable mismatch already decides the result, explain it and stop;
do not fully decompile an unsuitable game just to fill out the report.

### 3. Resolve decisive uncertainties with focused evidence

Use available, documented emulator/debugger capabilities. Check the installed
version and help before prescribing commands. Prefer headless or isolated runs
when supported; respect existing desktop/emulator permissions and user activity.
Do not change global emulator settings or the user's active game for a probe.

Capture only what answers the identified questions: selected code paths,
bank-aware reads/writes/execution, display registers, sprite density, sound
events, loader activity, or phase timing. Record tool/version/configuration,
input sequence, duration, and reached scenes. Include demanding scenes,
death/restart, transitions, later content, or different seeds when relevant and
accessible. Save-state or debugger-injected scenarios must be labeled; distinguish
them from naturally reached gameplay and account for changed timing/RNG state.

For memory, distinguish one-time loading, read-only-after-init data, persistent
state, scratch buffers, video data, and writes to subsequently executed code.
An observed write-set is neither a proven peak-live footprint nor proof that
unvisited code never writes elsewhere. When liveness is unknown, give bounds
and say what is unmeasured. Do not assume all buffers can share storage.

For behavior, inspect how movement, collision, timers, difficulty, and randomness
are computed. Include hardware-derived collision/random values and asynchronous
updates when used. A sampled path is not an enemy algorithm or an RNG model.

For performance, separate source frame cadence, simulation updates, and visible
rendering. Estimate target CPU work, bank-switch/runtime costs, VDP transfers,
audio service, and interrupt overhead in the demanding phase. State assumptions
and headroom. Source cycles or CPU MHz ratios alone do not prove target speed;
full original-speed parity remains unverified without a working implementation.

### 4. Decide and stop

Use the verdicts and confidence rules in the report reference. Keep hard
constraints visible; do not average a RAM failure into a favorable overall score.
Separate technical feasibility, expected fidelity, and conversion effort.
Give relative effort with concrete drivers, not an unsupported completion date.

Finish once the evidence supports the decision, or when unavailable inputs,
missing instrumentation, inaccessible scenes, or substantial new tooling prevent
a stronger conclusion. Report the unknown and the smallest useful next probe.
Do not repeatedly expand traces without a decision-changing question. An
incomplete probe is a coverage limitation, not a discovered game defect.

## Scope and handoff

Produce an assessment using the report format. Save it in a task-local assessment
directory if a project destination is available; otherwise return it in the
conversation. Put captures and extracts beside the assessment, not in production
game outputs. For multiple games, add a comparison table using the same profiles
and fidelity requirements, with evidence maturity visible for every row.

This workflow authorizes investigation, not a port. Do not modify game code,
build a translated ROM, implement a new emulator/translator, or start an
optimization campaign. List those as follow-up work when necessary. Do not load
the TI992CV/CV2TI99 conversion loops just because those skills are nearby. A
separate conversion request can consume this report and its evidence.
