#!/usr/bin/env python3
"""Repeated statement sequences in the CVBasic source -- duplication, measured.

Every byte of the fixed area is scarce (CLAUDE.md 3A), and the three times this
game has been rescued from the cap it was by finding two pieces of code doing the
same job -- the prize erase and the radio erase turning into one `wipe_2x2`, the
838 page's two draw routines, the font colour fill that a table already held.
Each was found by reading, which does not scale to 4,200 lines.

This finds them mechanically: strip comments and blank lines, normalise each
statement, and report every run of >= MIN statements that occurs more than once,
ranked by the bytes it could plausibly return (extra copies x length).

WHAT IT CANNOT TELL YOU is whether a clone is worth folding. A run of N
statements factored into a GOSUB costs the call, the return, and any parameter
staging -- so short clones with many distinct variables are usually a loss.
Ranked output is a reading list, not a work list.

Usage:
    python3 romclones.py [-m 4] [-n 25] [source.bas]
"""

import os
import re
import sys

# A rough per-statement cost, from romprofile.py's totals: 20,580 bytes of game
# code over roughly a thousand statements. Only used for ranking.
BYTES_PER_STMT = 20


def statements(path):
    """[(line_no, normalised_text)] -- code only, comments and blanks dropped."""
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for n, raw in enumerate(fh, 1):
            s = raw.strip()
            if not s or s.startswith("'"):
                continue
            # a trailing comment on a real statement
            if "'" in s:
                q = 0
                for i, c in enumerate(s):
                    if c == '"':
                        q ^= 1
                    elif c == "'" and not q:
                        s = s[:i].strip()
                        break
            if not s:
                continue
            out.append((n, re.sub(r"\s+", " ", s)))
    return out


# ---------------------------------------------------------------------------
# ALPHA-NORMALISATION -- seeing "the same algorithm over different variables"
# ---------------------------------------------------------------------------
#
# Text matching cannot find the duplication that actually matters here. The
# three copies of the escalator ride were invisible to this tool for months:
#
#     IF esy < eson THEN esy = esy + 1        IF hsy < hson THEN hsy = hsy + 1
#     esy = esy + 1                           hsy = hsy + 1
#     IF esxr = 1 THEN klx = klx + 2 ...      IF hesd = 0 THEN hx = hx - 2 ...
#
# -- identical shape, different names, zero matching characters. CLAUDE.md says
# the big routines' duplication is structural and a text matcher cannot see it.
# This is that blind spot, closed.
#
# WHAT IS RENAMED: lowercase identifiers, with or without a leading `#` (the
# 16-bit sigil). Variables in this codebase are lowercase; CONSTs and keywords
# are UPPERCASE, so leaving case alone separates them for free.
#
# WHAT IS NOT: the target of a GOSUB or GOTO. Renaming those would make every
# call match every other call, which manufactures clones out of unrelated code
# -- and a detector that reports noise is one people stop reading. String
# literals are protected for the same reason: renaming inside them is simply
# wrong.
#
# The mapping is reported with each hit, because it IS the cost estimate. A run
# with two distinct variables folds into a GOSUB cheaply; one with seven needs
# seven values staged at every call site and will usually LOSE (CLAUDE.md).

CALLTGT = re.compile(r"\b(?:GOSUB|GOTO)\s+[A-Za-z_]\w*")
QUOTED = re.compile(r'"[^"]*"')
VARNAME = re.compile(r"#?\b[a-z][a-z0-9_]*")


def alpha(seq):
    """(shape tuple, {original: placeholder}) for a run of statements."""
    mapping = {}
    shaped = []
    for stmt in seq:
        held = []

        def hide(mo):
            held.append(mo.group(0))
            return "\x01%d\x01" % (len(held) - 1)

        masked = QUOTED.sub(hide, stmt)
        masked = CALLTGT.sub(hide, masked)

        def rename(mo):
            word = mo.group(0)
            if word not in mapping:
                mapping[word] = "v%d" % (len(mapping) + 1)
            return mapping[word]

        masked = VARNAME.sub(rename, masked)
        for i, original in enumerate(held):
            masked = masked.replace("\x01%d\x01" % i, original)
        shaped.append(masked)
    return tuple(shaped), mapping


def main():
    args = list(sys.argv[1:])
    alpha_mode = "-a" in args
    if alpha_mode:
        args.remove("-a")
    minlen, top = 4, 25
    for flag, setter in (("-m", "minlen"), ("-n", "top")):
        if flag in args:
            i = args.index(flag)
            if setter == "minlen":
                minlen = int(args[i + 1])
            else:
                top = int(args[i + 1])
            del args[i:i + 2]
    here = os.path.dirname(os.path.abspath(__file__))
    path = args[0] if args else os.path.join(here, "..", "src", "KEYSTONE.bas")

    stmts = statements(path)
    text = [t for _, t in stmts]
    lines = [n for n, _ in stmts]

    def runkey(i, n):
        """What makes two runs 'the same' -- literal text, or shape."""
        if not alpha_mode:
            return tuple(text[i:i + n])
        return alpha(text[i:i + n])[0]

    # Longest repeated runs, greedily: index every window of MIN statements,
    # then extend each duplicated window as far as it stays duplicated.
    seen = {}
    for i in range(len(text) - minlen + 1):
        seen.setdefault(runkey(i, minlen), []).append(i)

    found = []
    covered = set()
    for key, idxs in seen.items():
        if len(idxs) < 2:
            continue
        if any(i in covered for i in idxs):
            continue
        # extend while every occurrence still matches. Under -a the SHAPE of
        # the longer window has to be recomputed each time rather than
        # comparing one more statement: a placeholder's meaning depends on
        # where its variable first appeared in the run, so `v1` in a 5-window
        # need not be `v1` in the 6-window.
        n = minlen
        while True:
            if idxs[-1] + n >= len(text):
                break
            if alpha_mode:
                want = runkey(idxs[0], n + 1)
                if all(runkey(j, n + 1) == want for j in idxs[1:]):
                    n += 1
                else:
                    break
            else:
                nxt = text[idxs[0] + n]
                if all(text[j + n] == nxt for j in idxs[1:]):
                    n += 1
                else:
                    break
        # non-overlapping occurrences only
        keep, last = [], -10 ** 9
        for j in idxs:
            if j >= last + n:
                keep.append(j)
                last = j
        if len(keep) < 2:
            continue
        # A RUN THAT CONTAINS A LABEL IS NOT FOLDABLE, and under -a these turn
        # up constantly: `END IF / END IF / NEXT x / RETURN / some_label:` has
        # the same shape wherever one routine ends and the next begins, so the
        # tool was ranking the seams between routines as its top find. Nothing
        # can be factored out of a run that another routine jumps into the
        # middle of.
        if any(t.endswith(":") for t in text[keep[0]:keep[0] + n]):
            continue
        for j in keep:
            covered.update(range(j, j + n))
        found.append((n, keep))

    found.sort(key=lambda f: -(f[0] * (len(f[1]) - 1)))

    print("%d statements of code in %s" % (len(text), os.path.basename(path)))
    print("Repeated runs of >= %d statements, ranked by removable bytes\n" % minlen)
    shown = 0
    for n, idxs in found:
        if shown >= top:
            break
        shown += 1
        gain = n * (len(idxs) - 1) * BYTES_PER_STMT
        print("%2d statements x %d copies  ~%4d B   lines %s"
              % (n, len(idxs), gain,
                 ", ".join(str(lines[j]) for j in idxs)))
        for t in text[idxs[0]:idxs[0] + min(n, 6)]:
            print("      %s" % t)
        if n > 6:
            print("      ... (%d more)" % (n - 6))
        if alpha_mode:
            # WHETHER THIS IS WORTH FOLDING IS A QUESTION ABOUT THE VARIABLES,
            # not about the byte count above, and under -a the byte count is
            # actively misleading: "five distinct variables set to zero" has
            # the same SHAPE everywhere it occurs, so a reset block in one
            # routine matches an unrelated one in another. Folding those would
            # be wrong -- they are different variables that happen to rhyme.
            #
            # So print the actual names per copy. Identical lists mean a
            # parameterless GOSUB and a real saving. Different lists mean every
            # name has to be staged at every call site, and past about two the
            # fold LOSES (CLAUDE.md: a short clone costs the call, the return
            # and the staging).
            names = [list(alpha(text[j:j + n])[1].keys()) for j in idxs]
            if all(x == names[0] for x in names[1:]):
                print("      vars: %s -- SAME in every copy, folds with no "
                      "staging" % ", ".join(names[0]))
            else:
                print("      vars differ per copy -- %d to stage:"
                      % len(names[0]))
                for j, nm in zip(idxs, names):
                    print("        line %-5d %s" % (lines[j], ", ".join(nm)))
        print()


if __name__ == "__main__":
    main()
