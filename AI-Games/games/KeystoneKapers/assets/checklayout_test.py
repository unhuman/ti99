"""Prove checklayout.py fails on the defects it exists to catch.

A checker that has never been shown a known-bad input is an untested claim.
This repo has already shipped one that passed the very bug it was written for.
"""
import io, os, shutil, subprocess, sys

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
cases.append(("PRINT AT overflow", SRC, orig,
              orig.replace('PRINT AT 614,"FIRE TO START"',
                           'PRINT AT 630,"FIRE TO START AND KEEP GOING"'),
              "runs"))

# 2. a HUD VPOKE landing inside a printed label
cases.append(("VPOKE inside a label", SRC, orig,
              orig.replace('#psa = 6150', '#psa = 6146'),
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
