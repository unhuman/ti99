# The Truncation Issue

**A value too large for the thing holding it does not error on this toolchain. It
loses its high bits and carries on, and what remains is usually a plausible wrong
number rather than an obvious zero.** That is why this class of bug survives review,
survives testing, and ships: nothing anywhere reports it, and the symptom is almost
never "it crashed" — it is a sprite drawn in the wrong place, a prize worth the wrong
amount, a difficulty curve that runs backwards.

This file is the single place that describes every form of it, how each one has
actually bitten in this repo, and what is now in place to stop it happening again.

---

## 1. The four forms

### 1a. A plain CVBasic variable is EIGHT BITS

`v = 463` silently becomes `207`. Any screen offset past row 7 (`row*32+col > 255`),
any VRAM address, any pixel count over 255, any frame count over 255 must go in a
`#var`.

**The whole expression evaluates in 8 bits**, so the truncation happens *before* the
rest of the arithmetic — `scti = 300 - rnd * 30` truncates 300 to 44 first, then
subtracts.

| where | written | became | symptom |
|---|---|---|---|
| Bust-A-Bobble 838 menu | `rdp = 463` | 207 | typed digits drew at row 6, not row 14 — read as an odd layout choice for weeks |
| Bust-A-Bobble playfield | `sdc = 713` | 201 | a black 2×2 hole punched through row 6 on every redraw |
| RALLY-X head start | `scti = 300 - rnd*30` | 44 → clamped to 120 | **the difficulty curve inverted**: round 1 got the *shortest* head start, round 3 the longest |
| Ms. Pac-Man fruit | `ffp = 500` | 244 | the banana scored **2440** instead of 5000. Every smaller prize in the same ladder was correct, so the table looked right |
| Structris countdown | `cdf = 400/500/640` | 144/244/128 | countdown beeps at the wrong pitches, and "1" higher than "3". *Released; accepted, not fixed* |

> The `sdc = 713` case happened **hours after the rule was written into `CLAUDE.md`**.
> Writing a rule down does not prevent it. That is why this is now tooling.

### 1b. `CONST` above 255 truncates — bare literals do not

The sharpest edge, because it is invisible at the point of use. `CONST FXMIN = 4096`
compiled to `ci r0,0`; `CONST RNDPOS = 311` compiled to `li r0,55`.

- **It truncates, it does not zero.** 311 → 55 is a perfectly plausible name-table
  offset, so the write landed *somewhere real* — row 1 columns 23-24, on top of the
  score, instead of row 9. A wrong-but-plausible address is far harder to spot than
  an obvious zero.
- **A `CONST` can be safe for months and then break without being edited.** That 311
  was 247 while `ROUND` sat on row 7. Moving the label down two rows pushed the
  *derived* constant over 255 — so the change that broke it was a layout tweak, and
  the value it broke was one nobody was looking at. **Any `row*32+col` constant is one
  row-move away from this.**
- The distinction is **`CONST` vs literal, not magnitude**: `IF #bx < 4096` and
  `#bx = 20480` written inline are both fine.

### 1c. An 8-bit variable times a constant over 255 compiles to `CLR`

`mhi * 256` emitted a bare `clr`, which silently reduced every music note to its low
byte. The threshold is **256, not 2048** — `* 34`, `* 68`, `* 136` are all fine. A
folded dotted constant (`$1800 + 728.`) truncates the addend the same way.

### 1d. A word table on an ODD address reads shifted one byte

Not a value truncation but the same family: **silent, and plausible.** The TMS9900
ignores the low bit of a word address, so `mov *r0` from an odd address reads the word
*below* it without faulting. CVBasic emits `even` after its own string literals but
**not** after a hand-written `DATA BYTE` run, so an odd-length byte block leaves the
location counter odd and every `DATA` (word) table after it in that segment reads back
shifted for ever.

A 33-byte marquee table put Bust-A-Bobble's `#aimdx` on `>68FB`, so `#aimdx(0)`
returned **3840 instead of 0**: the aim guide dots scattered across the HUD 60px
apart, and a shot aimed straight up left at a severe angle at the wrong speed.

**It presented as "only vertical is broken".** A shifted table reads
`(low byte of entry i-1) << 8 | (high byte of entry i)` — entry 0 picks up a
neighbour's byte and goes huge, while entry 1 reads `>0000` and is *still* 0. One
nudge off vertical looked correct and hid the corruption.

---

## 2. What is in place to stop it

Three checks, all of which **fail the build**. None of them is advice.

| check | catches | how |
|---|---|---|
| `tools/bigvar.py` | 1a | Every `name = …` where `name` is plain (no `#`) and the expression holds a literal over 255. Divisors are exempt (`bpx = #bx / 256` is the normal way to bring a fixed-point value into a byte); **multiplication is not**. |
| `tools/bigconst.py` | 1b | Every `CONST` over 255, repo-wide. |
| `assets/romcheck.py` (per game) | 1d | Every `ai r0,<label>` + `mov *r0` pair — how the compiler indexes a word table — resolved to its real address in the `xas99` listing, and failed if odd. No heuristics: even is correct by construction. |

Form **1c** has no mechanical check yet; it needs reading the generated `.a99` for a
bare `clr` where a multiply was expected. **Check the generated assembly whenever a
multiply matters.**

### Running them

```
python3 tools/bigvar.py        # all games, or pass paths
python3 tools/bigconst.py
```

Both are wired into every game's `build-ti.sh` and `build-coleco.sh`, so a truncation
fails the build rather than shipping.

### Accepting one deliberately

Put `TRUNCATION-OK` in the offending line's own comment, with the reason:

```basic
cdf = 400        ' TRUNCATION-OK -- released, audible only; see above
```

The reason travels with the code instead of rotting in a list elsewhere. **A gate that
fires on findings everyone has agreed to live with is a gate everyone learns to
ignore**, which is worse than no gate at all.

---

## 3. The rule behind all of it

> **Every one of these is silent, and every one produces a plausible wrong value
> rather than an obvious failure.** So the defence cannot be care, and it cannot be a
> note in a file — `sdc = 713` was written hours after the rule was. It has to be a
> check that runs without being remembered.

Two corollaries earned the hard way:

- **Verify a guard against the real defect, not against a passing build.** The
  alignment check was first written as a heuristic over odd-length byte runs; it cried
  wolf four times on a build already known good. It was replaced and then re-run
  against the actual bug (`mq_row` back at 33 bytes) to watch it fail.
- **A comment claiming something is finished stops the next person checking.** A note
  reading "nothing data-shaped is left above the BANK directive" sat one screen below
  136 bytes of data that were above it, and was false for months. If a claim cannot be
  verified mechanically, write down *what to check* instead.
