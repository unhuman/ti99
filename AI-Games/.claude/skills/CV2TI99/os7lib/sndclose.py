"""The vblank sound's closure must not use the alternate registers.

    sndclose.py [--mutate]

os7.a99's SNDRUN runs the sound engine (PLAY_SONGS, SOUND_MAN, $035F and
the song effects the cart supplies) at a vblank on the game's workspace,
and saves only R0-R8, R11, R12 and R15: it never touches R9 R10 R13 R14
(BC' DE' HL' A').  That is right only while nothing the engine can reach
executes EXX or EX AF,AF' -- the translator uses those registers for
nothing else.  This walks every path from the roots through the traced
listings (calls, jumps, ann.ICALL targets) and fails on an EXX / EX AF or
on a computed jump it cannot follow.  build.py runs it on every build.
--mutate adds a root that reaches the cart's EXX at $94AA: it must fail.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import ann

# PLAY_SONGS, SOUND_MAN, the note loader, SASSIGN, the song effects
ROOTS = (0x0300, 0x027F, 0x035F, 0x0295) + tuple(getattr(ann, 'JPTAB_EXTRA', ()))


def listing():
    ins = {}
    for f in ('bios.lst', 'cart.lst'):
        for ln in open(os.path.join(ROOT, 'disasm', f)):
            m = re.match(r'\s+([0-9A-F]{4})\s+([0-9a-f]+)\s+(\S.*)$', ln)
            if m and not m.group(3).startswith('db'):
                ins[int(m.group(1), 16)] = (len(m.group(2)) // 2, m.group(3).strip())
    return ins


def check(roots=ROOTS):
    """-> (instructions reached, [alternate-register uses], [unfollowed])"""
    ins = listing()
    seen, todo, bad, unk = set(), list(roots), [], []
    while todo:
        a = todo.pop()
        while a not in seen:
            if a not in ins:
                unk.append('%04X (not traced)' % a)
                break
            seen.add(a)
            n, t = ins[a]
            if t.startswith('exx') or t.startswith('ex af'):
                bad.append('%04X %s' % (a, t))
            if a in ann.ICALL:
                targets, nxt = ann.ICALL[a]
                todo += list(targets)
                if nxt is None:
                    break
                a = nxt
                continue
            op = t.split()[0]
            m = re.search(r'\$([0-9A-F]{4})', t)
            if op in ('call', 'jp', 'jr', 'djnz') and m:
                todo.append(int(m.group(1), 16))
                if op in ('jp', 'jr') and ',' not in t:
                    break
            if op == 'rst':
                todo.append(int(t.split()[1].lstrip('$'), 16))
            if t.startswith('jp ('):
                unk.append('%04X %s' % (a, t))
                break
            if t in ('ret', 'reti', 'retn'):
                break
            a += n
    return len(seen), bad, unk


def main():
    roots = ROOTS + ((0x94AA,) if '--mutate' in sys.argv else ())
    n, bad, unk = check(roots)
    print('sndclose: %d instructions reached from the sound roots' % n)
    for b in bad:
        print('  alternate registers: %s' % b)
    for u in unk:
        print('  not followed: %s' % u)
    sys.exit(1 if bad or unk else 0)


if __name__ == '__main__':
    main()
