# Assessment report format and decisions

Lead with the recommendation, not a diary of the investigation. Keep a short
screen brief; expand tables and evidence only when the findings justify it.
Use the same profiles and fidelity requirements when comparing candidates.

## Decision vocabulary

| Verdict | Meaning |
|---|---|
| Good candidate | Evidence supports a plausible implementation within the stated profile and fidelity goal; no unresolved critical blocker. Target performance is still an estimate until implementation. |
| Conditional candidate | A plausible route depends on an explicit, unaccepted compromise, hardware alternative, or bounded technical condition. Identify the condition and whether it is verified. |
| Poor fit | A demonstrated mismatch defeats the requested baseline/fidelity, or addressing it requires disproportionate replacement of essential behavior. Explain the constraint; do not equate this with universally impossible. |
| Insufficient evidence | A critical unknown prevents a defensible recommendation. State the missing evidence and the smallest next probe. |

Use conditional for a concrete route, not a vague promise that optimization will
fix things. A known baseline failure can coexist with a conditional expanded
alternative; retain both verdicts. Missing evidence must not be scored as a pass
or automatically as a hardware failure.

Confidence describes the verdict's evidence, not the likelihood of finishing a
port: **high** when decisive findings are directly established and relevant
coverage is adequate, **medium** with bounded assumptions, **low** when mostly
documentation/indirect evidence. A definitive resource conflict can justify high
confidence in a poor-fit verdict without tracing the whole game. Missing a key
game image can justify high confidence that evidence is insufficient, while
technical feasibility itself remains unknown. Explain this distinction.

## Suggested report

### Recommendation

| Target/profile | Verdict | Confidence and basis | Main reason / condition |
|---|---|---|---|
| Stock ColecoVision, ROM banking allowed | ... | ... | ... |
| TI-99/4A + 32 KB, standard graphics/sound | ... | ... | ... |

State the requested fidelity goal and source/target regions. If not specified,
aim to preserve rules, timing, controls, and randomness, and expose visual/audio
differences rather than assuming approval. Use NTSC targets provisionally.

### Source and evidence

- Game/version/model, media, paths, SHA-256 hashes, and provenance of extracts.
- Source/disassembly correspondence; tools, versions, machine configuration.
- Scenes, inputs/seeds, durations, and code paths reached; significant gaps.
- Each decisive finding cites an address plus bank/context, source symbol,
  artifact/trace location, or authoritative document section as appropriate.
- Mark findings **measured**, **code-derived**, **documented**, **estimated**, or
  **unknown**. Avoid invented precision, observed-coverage percentages without a
  defensible denominator, and claims of whole-game behavior from one scene.

### Constraints and proposed route

| Area | Source evidence | Coleco impact | TI impact | Remaining uncertainty |
|---|---|---|---|---|
| Changing state, buffers, runtime/stack | ... | ... | ... | ... |
| Graphics, overlap and scrolling | ... | ... | ... | ... |
| Simulation and frame workload | ... | ... | ... | ... |
| Audio and timing interaction | ... | ... | ... | ... |
| Controls, loaders and storage | ... | ... | ... | ... |

Explain what could be translated, what needs native replacement, and whether
the result preserves original logic or amounts to a substantial reimplementation.
Give budget assumptions and relative effort drivers. Distinguish audio rhythm
from timbre, and visual adaptation from changes to collision or reaction time.
List expansion alternatives separately with the exact problem each resolves.

### Decision boundary and next step

List the remaining critical unknowns, what would change the verdict, and the
smallest useful follow-up experiment. State why investigation stopped. Do not
present future conversion work as already performed or launch it from the report.
For a shortlist, include evidence maturity per game so an unexamined title does
not outrank a well-investigated one merely because its risks are still hidden.
