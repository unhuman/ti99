# AI-Games: Codex project instructions

## Read first

- Read [CLAUDE.md](CLAUDE.md) before changing game code. It is the shared repository
  specification and accumulated toolchain knowledge for both Claude and Codex.
  Keep it as the canonical reference; do not copy its entire contents here.
- The current project is **Keystone Kapers**, in `games/KeystoneKapers/`, unless
  the user names another game. Read its [AGENTS.md](games/KeystoneKapers/AGENTS.md),
  `README.md`, and relevant `DESIGN.md` sections before editing it, including when
  the session starts at this directory rather than inside the game.
- Check existing changes before editing. This directory sits inside the parent
  `ti99` Git repository; scope Git operations to the intended project files.
- Consult [GAMES.md](GAMES.md) for other games and their platforms.

## Interpret the shared notes in context

`CLAUDE.md` starts with the older XB256 mandate, but section 3A explicitly describes
the current CVBasic games. Preserve each game's existing language and targets.
Keystone Kapers is CVBasic, with TI-99/4A, ColecoVision, and NES build scripts.
Do not convert it to numbered Extended BASIC or apply XB memory limits to it.

The notes include historical diagnoses, measurements, and explicit corrections.
Read the correction and inspect the current implementation before acting on an old
entry. Do not treat an old phase plan as a list of features still missing.

Existing workflow references remain available at their original paths:

- CVBasic: [.claude/skills/build-cvbasic-game/SKILL.md](.claude/skills/build-cvbasic-game/SKILL.md).
  Read when building CVBasic; use the game's own build scripts where present,
  since they include its generators, regression gates, banking, and target fixes.
- XB256: [.claude/skills/xb256-reference/SKILL.md](.claude/skills/xb256-reference/SKILL.md).
  Read when working on an XB256 game.

These files can be read directly even if they are not registered as Codex skills.
The generic CVBasic skill's older nanochess compiler path does not supersede a
game's use of the **unhuman/CVBasic** fork, which supplies its preprocessor.

## Working agreements

- Preserve original-hardware performance and memory budgets. Check generated
  assembly when compiler behavior matters; successful compilation alone is not
  proof of correct behavior.
- Keep a changed game's `DESIGN.md` and `README.md` synchronized with behavior,
  layout, controls, and asset/build changes. Record new general toolchain hazards
  in `CLAUDE.md`, so both assistants inherit them.
- Edit asset generators and editable art, then regenerate their outputs together.
  Do not fix generated files in isolation.
- Run the game's build scripts and their existing checks for code/asset changes.
  Build both TI and ColecoVision for shared CVBasic changes; preserve and validate
  any additional targets the game supports. Run builds sequentially when they
  share generated files or tests that temporarily mutate the source.
- Preserve `.gitattributes`: shell scripts and CVBasic sources need LF endings.
  Read documentation as UTF-8. On Windows, distinguish native paths from Cygwin
  `/cygdrive/c/...` paths; the game scripts handle the runtime/path conversions.
- A regression gate must test the actual property and reject known bad cases.
  Do not weaken a threshold just to make a build pass; retain documented, named
  exceptions and the existing checker self-tests.
- Lives icons mean reserves excluding the current life, right-justified and
  guarded against unsigned underflow (`CLAUDE.md` section 7A).
- For gameplay/build handoffs, follow `CLAUDE.md`'s emulator rule: leave the newest
  TI cart running in one Classic99 window for review and verify what is loaded.
  Keep normal starting conditions in source; use a separate review cart for a
  later level. Report any runtime verification that could not be performed.

## CVBasic reminders

The full failure contracts are in `CLAUDE.md` section 3A and `TRUNCATION.md`.
In particular: variables are global; plain variables are 8-bit and `#` variables
are unsigned 16-bit; constants above 255 truncate; compound comparisons on the
TI backend are unsafe; multiplication can leave stale register state; `DIM a(N)`
has indices 0 through N-1; and a `GOSUB` must unwind through a return. Keep byte
tables even-sized before word tables. Use the repository's checkers rather than
relying only on these reminders.
