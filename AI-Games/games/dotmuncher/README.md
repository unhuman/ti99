# Dot Muncher (`MUNCH`)

A one-screen maze game: move the muncher with **E/S/D/X** (up/left/right/down) and eat every
dot to win. No enemy yet — this game's real job is to **validate the whole XB256 → compile →
`-X` toolchain** end to end. See `DESIGN.md` for the spec.

- **Source:** `src/MUNCH.ti99` (paste-ready XB256 listing)
- **Status:** awaiting first interpreted run + first compile (in Classic99)
- **Platform rules:** repo `CLAUDE.md`

## Build & run (Classic99, with `JUWEL7` mounted as DSK1)

1. Boot **Classic99** → Cartridge → Apps → **Extended BASIC** → choose **XB256** from the menu.
2. Type `NEW`, then paste the contents of `src/MUNCH.ti99` (Classic99: Edit → Paste XB), or key it in.
3. `RUN` — verify interpreted: maze draws, HUD shows the dot count, holding a direction moves the
   muncher continuously, walls block, dots score with a blip, last dot triggers the win jingle.
4. `SAVE DSK2.MUNCH` then `SAVE DSK2.MUNCH-M,MERGE` (use whatever working disk you set up).
5. Quit to the menu → **COMPILER** → set the prompts: `MUNCH-M` in, **`MUNCH-S` out** (dot-free —
   **not** `MUNCH.TXT`; a `.` in a TI filename gives `I/O ERROR`), runtime on DSK1, runtime
   **not** in low memory → **Proceed**.
6. **ASSEMBLER** (TI assembler) → object out **`MUNCH-O`** (dot-free) → assemble → 0000 ERRORS.
   (Only if you use **Asm994a** instead are the `.TXT`/`.OBJ` extensions valid.)
7. **LOADER** → save **`MUNCH-X`** (XB loader) → `RUN`.
8. Confirm `MUNCH-X` behaves identically to the interpreted run, just far faster. ✅ toolchain validated.

> If the compiler stops on a line (`L###`), that line has an unsupported statement — check it
> against `CLAUDE.md` §6.
