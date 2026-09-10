"""Prove checklayout.py fails on the defects it exists to catch.

A checker that has never been shown a known-bad input is an untested claim.
This repo has already shipped one that passed the very bug it was written for.
"""
import io, os, re, shutil, subprocess, sys

BASE = r'C:\Users\Howie\github.git\unhuman\ti99\AI-Games\games\KeystoneKapers'
SRC = os.path.join(BASE, 'src', 'KEYSTONE.bas')
CHK = os.path.join(BASE, 'assets', 'checklayout.py')
PY = sys.executable

orig = io.open(SRC, encoding='utf-8').read()
chk_orig = io.open(CHK, encoding='utf-8').read()


def run():
    r = subprocess.run([PY, 'checklayout.py'], cwd=os.path.join(BASE, 'assets'),
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


cases = []

# 1. a PRINT AT that runs past column 31
#
# THE ANCHOR IS DERIVED, NOT TYPED -- the same rot that case 2 below already
# suffered, and this case then caught it in turn. It was the literal
# `PRINT AT 614,"FIRE TO START"`; the title screen moved down a row, 614 became
# 617, and the mutation silently applied to nothing. The suite still printed its
# four lines and three of them still passed.
#
# So: take whatever the FIRST `PRINT AT n,"text"` in the source is, and lengthen
# its string until it runs off the right-hand edge from wherever it starts. That
# holds however the screens are laid out.
_pa = re.search(r'PRINT AT (\d+),"([^"]*)"', orig)
if not _pa:
    raise SystemExit("checklayout_test: no `PRINT AT n,\"...\"` in the source "
                     "at all -- this case can no longer be built and the "
                     "overflow check is untested")
_col = int(_pa.group(1)) % 32
_over = "X" * (32 - _col + 4)
cases.append(("PRINT AT overflow", SRC, orig,
              orig.replace(_pa.group(0),
                           'PRINT AT %s,"%s"' % (_pa.group(1), _over), 1),
              "runs"))

# 2. a HUD VPOKE landing inside a printed label
#
# THE ANCHOR IS DERIVED, NOT TYPED. It used to be the literal `#psa = 6150`,
# and 6150 stopped existing when the score field moved -- so the mutation
# silently applied to nothing, the run came back CLEAN, and the case reported
# SETUP ERROR instead of testing anything. A self-test that rots into a no-op
# is worse than none, because the suite still prints four lines and three of
# them pass.
#
# 6146 is row 0 column 2, which is inside the word SCORE that hud_all prints
# there. Whatever address hud_score currently uses, moving it to 6146 is the
# defect this case is about.
_psa = re.search(r'#psa = (\d+)', orig)
if not _psa:
    raise SystemExit("checklayout_test: no `#psa = N` in the source at all -- "
                     "the HUD digit routine was renamed or restructured")
cases.append(("VPOKE inside a label", SRC, orig,
              orig.replace(_psa.group(0), '#psa = 6146', 1),
              "INSIDE the string"))

# 3. a drawing routine missing from the SCREEN map
cases.append(("unmapped routine", CHK, chk_orig,
              chk_orig.replace('"hud_kops": "GAME", ', ''),
              "not in the SCREEN map"))

# 4. two HUD fields declared on top of each other
cases.append(("HUD fields overlap", CHK, chk_orig,
              chk_orig.replace('("time digits",  0, 19, 2),',
                               '("time digits",  0, 16, 2),'),
              "OVERLAP"))

fails = 0
for name, path, good, broken, expect in cases:
    if broken == good:
        print("SETUP ERROR: %s -- the mutation changed nothing" % name)
        fails += 1
        continue
    io.open(path, 'w', encoding='utf-8', newline='').write(broken)
    try:
        rc, out = run()
    finally:
        io.open(path, 'w', encoding='utf-8', newline='').write(good)
    ok = rc != 0 and expect in out
    print("%-24s %s" % (name, "caught" if ok else "*** NOT CAUGHT ***"))
    if not ok:
        fails += 1
        print(out[-600:])

rc, out = run()
print("%-24s %s" % ("clean source", "passes" if rc == 0 else "*** FAILS ***"))
if rc != 0:
    fails += 1
    print(out[-600:])

sys.exit(1 if fails else 0)
