# Output layout for future ports

User-requested convention, 2026-10-27. Applies to **new ports** using CV2TI99 or
TI992CV, including new projects copied from an older port's tooling. Read this
before setting up their build scripts and checkers.

**Existing projects keep their current paths.** This convention does not
authorize moving, deleting, renaming or cleaning existing outputs, or changing
existing build/test/emulator scripts. Ordinary maintenance of an existing port
does not trigger migration. Migrate one only when the user explicitly requests
it. Historical `build/` paths in these skills remain accurate for their named
examples; they are not the layout to reproduce in a new project.

## Two output roots

`build/` contains only the current loadable binary deliverables. All generated
supporting material belongs in the sibling `artifacts/` tree. Keep the existing
source/input organization (`src/`, `tools/`, editable assets, `roms/`, tests and
project documentation) appropriate to the port.

| Location | Contents |
|---|---|
| `build/` | Current cartridge binaries and required loadable variants, such as `game_8.bin`, `game.rom`, `game_dev.rom`, `game_ls.rom`, or the target's loadable cartridge package |
| `artifacts/intermediate/<target>/<variant>/` | Generated assembly/includes, object files, unpacked banks, generated asset payloads, listings, symbol/map files, translation mappings and pickles |
| `artifacts/reports/<run-id>/` | Verification results, ROM hashes/manifests, budget and timing reports, profiler results and trace data |
| `artifacts/logs/<run-id>/` | Compiler, assembler, build, emulator and test logs |
| `artifacts/captures/<run-id>/` | Screenshots, audio, video and emulator states |
| `artifacts/optimization/` | Experiment/process ledger and its supporting results |
| `artifacts/snapshots/<id>/` | Frozen baseline/candidate bundles, including their binaries, matching symbols/mappings and manifests |
| `artifacts/tmp/` | Disposable staging files and temporary test/mutation outputs |

Create only the subdirectories the port uses. Choose identifiable run/snapshot
IDs so simultaneous tests and later builds do not overwrite one another's
evidence. A binary extension does not make an intermediate asset or historical
ROM a current deliverable: those remain under `artifacts/`. Development and
lockstep ROMs are legitimate current binaries when the port requires them.

Keep `build/` flat and limited to its explicitly named deliverables: no logs,
JSON, hash text files, README, generated source, symbols, screenshots, caches,
archive subdirectories, or old candidate versions. The top-level README lists
the playable filename and links to evidence under `artifacts/`.

## Wire the layout into the new toolchain

1. Define the two roots in the port's shared path configuration, resolved from
   the project location rather than the caller's working directory. Adapt copied
   template paths before the new port's first build. Do not copy its old output
   directory or retain its hard-coded report destinations.
2. Make generators and assemblers write supporting outputs directly beneath
   `artifacts/`. If a tool insists on writing beside its output file, assemble
   in an intermediate/staging directory and publish only the named binaries to
   `build/` after the required generation, assembly and build gates succeed.
   A failed build must not replace the previous successful binary with a partial
   output. Do not rely on sweeping unwanted files out of `build/` afterward.
3. Update producers **and readers** together in the new project. Checkers,
   profilers and emulator helpers must locate matching symbols, maps, pickles,
   fixtures and reports through shared configuration or explicit arguments.
   Do not infer that they live beside a ROM just because an older template did.
   Preserve all existing correctness, timing, budget and mutation checks.
4. Freeze a complete binary-plus-metadata bundle under `artifacts/snapshots/`
   for long suites. Pin readers to that bundle; rebuilding current outputs must
   not change a running test's inputs. Write test results outside the frozen
   input bundle and bind them to the tested ROM hash. Put mutated ROMs and
   temporary scenarios outside the current deliverable set.
5. Document the layout and configure ignore rules for generated outputs in the
   new project. Keep deliberate regression fixtures in their established test
   location; classify them explicitly rather than discarding useful evidence
   as clutter. A routine cleanup must not erase retained baselines or evidence.

## Verify the directory contract

For a new port, have its normal build/full-verification entry points check the
contents of `build/` against the configured current binary filenames. Check
again after tests and captures, since those tools can introduce sidecars even
when assembly is clean. Reject unexpected files or directories with a useful
message; do not silently delete them or accept everything with a `.bin` suffix.
Prove the check rejects a stray log and a supporting metadata file using an
isolated directory fixture, without touching a user's existing build folder.

Exercise a fresh build and an incremental build. Confirm launchers select the
intended current binary, tests still find its matching metadata, reports carry
the correct hash, and the build directory remains limited to deliverables.
These checks supplement the port's normal gates; changing output locations
does not weaken them. Documentation-only adoption of this convention requires
no rebuild or filesystem reorganization of existing games.
