#!/usr/bin/env python3
"""Find CVBasic routines that are ENTERED with GOSUB and LEFT with GOTO.

WHY THIS IS WORTH A TOOL. A GOSUB pushes a return address and only RETURN (or a
PROCEDURE's END) pops it. A routine that is GOSUBed but exits by jumping somewhere
else abandons that address, and every pass through it grows the stack by the whole
call chain.

The failure is asymmetric, which is what makes it expensive. On the TI ~7 KB of RAM
absorbs the leak for hundreds of rounds and it never surfaces. On ColecoVision --
1 KB total, of which CVBasic's variables leave perhaps 150 bytes of headroom -- a
few dozen rounds is enough for the stack to walk down into the variables.
Bust-A-Bobble's symptoms were score digits printing as bubble characters, the pop
animation hanging, and corruption that survived into the title screen. None of that
looks like a stack, and it took a Coleco-only bug hunt to find. See CLAUDE.md 3A.

HOW IT DECIDES. Labels at column 0 are entry points. From every label some GOSUB
targets, walk the control flow -- fallthrough, GOTO, ON GOTO -- and check that a
return is reachable. GOSUB is a call that comes back, so it is not an edge. Both
routine forms are handled:

    name: PROCEDURE ... END          returns at END
    name: ... RETURN                 returns at RETURN

A GOTO that lands in ANOTHER GOSUBed routine which returns is a tail call: the
return address is reused correctly, so it is not reported. What is reported is a
path that reaches the end of the program, halts, or falls into the next PROCEDURE
without ever returning.

Run:  python3 tools/gosubtrace.py games/*/src/*.bas
"""
import re
import sys


def analyse(path):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")

    labels, isproc = {}, {}
    for i, ln in enumerate(lines):
        m = re.match(r"^([A-Za-z_]\w*)\s*:", ln)
        if m and ln[:1] not in (" ", "\t"):
            labels[m.group(1)] = i
            isproc[i] = bool(re.search(r"\bPROCEDURE\b", ln.split("'")[0], re.I))
    proc_lines = set(i for i, p in isproc.items() if p)

    gosubbed = set()
    for ln in lines:
        for m in re.finditer(r"\bGOSUB\s+([A-Za-z_]\w*)", ln.split("'")[0], re.I):
            gosubbed.add(m.group(1))

    def trace(entry):
        """(terminals, lines visited) for every path out of `entry`."""
        start = labels[entry]
        # Inside a PROCEDURE a bare END is the return; outside one it halts.
        proc = isproc[start]
        seen, stack, term = set(), [start], set()
        while stack:
            i = stack.pop()
            if i in seen or i >= len(lines):
                continue
            seen.add(i)
            code = lines[i].split("'")[0]
            up, stripped = code.upper(), code.strip()

            if re.search(r"\bRETURN\b", up):
                term.add(("RETURN", i))
                if re.match(r"^RETURN$", stripped, re.I):
                    continue
            if re.match(r"^END$", stripped, re.I):
                term.add(("END-of-PROCEDURE" if proc else "halt:END", i))
                continue

            targets = re.findall(
                r"\bGOTO\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)", code, re.I)
            for group in targets:
                for t in re.split(r"\s*,\s*", group):
                    if t in labels:
                        stack.append(labels[t])
                    else:
                        term.add(("unknown-label:" + t, i))
            uncond = (targets and re.match(r"^(GOTO|ON\s)", stripped, re.I)
                      and " THEN " not in up)
            if uncond:
                continue
            if i + 1 >= len(lines):
                term.add(("end-of-file", i))
            elif i + 1 in proc_lines:
                # Execution cannot fall into a PROCEDURE header.
                term.add(("falls-into-PROCEDURE", i))
            else:
                stack.append(i + 1)
        return term, seen

    bad = []
    for name in sorted(gosubbed):
        if name not in labels:
            continue
        term, seen = trace(name)
        good = set(("RETURN", "END-of-PROCEDURE"))
        if not any(k in good for k, _ in term):
            bad.append((name, sorted(term)[:4], len(seen)))
    return bad, len(gosubbed)


bad_total = 0
for path in sys.argv[1:]:
    bad, n = analyse(path)
    print("%s (%d GOSUB targets)" % (path, n))
    if not bad:
        print("    every GOSUB target reaches a return")
    for name, term, nseen in bad:
        print("    %-16s NO return reachable; %d lines traced; ends at %s"
              % (name + ":", nseen,
                 ", ".join("%s line %d" % (k, i + 1) for k, i in term)))
    bad_total += len(bad)
    print()
sys.exit(1 if bad_total else 0)
