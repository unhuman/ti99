"""Profile of the ticks that take longer than a frame (busy > LIM frames),
with set-up ticks over 3 frames left out; per-pc cycles go to
build/heavy_pcs.json and build/light_pcs.json.  Run from the port root.
    heavyprof.py [seed] [lim] [rows] [hi]"""
import os, sys, json, re, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tiemu, cspeed

seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
LIM = float(sys.argv[2]) if len(sys.argv) > 2 else 0.9
ROWS = int(sys.argv[3]) if len(sys.argv) > 3 else 40
HI = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0     # ticks over HI frames left out
lab = json.load(open('build/labels.json'))['zaddr']
t = tiemu.load('build/CARNIVAL_8.bin')
tiemu.start_game(t, '1')
drv = cspeed.Driver(seed)
FR = 50000.0 * 1.0            # placeholder; measured below
st = {'end': None, 'start': None, 'snap': None}
heavy = collections.Counter()
light = collections.Counter()
nh = [0, 0]
wb, wa = lab['831D']
tb, ta = lab['8331']
t.prof = {}
c0 = t.cycles
f0 = [0]


def w(m):
    if st['start'] is None and st['end'] is not None:
        st['start'] = m.cycles


def tick(m):
    drv.tick()
    d, f = drv.state()
    for k in ('J1LEFT', 'J1RIGHT', 'J1FIRE'):
        m.pressed.discard(k)
    if d == 'left':
        m.pressed.add('J1LEFT')
    if d == 'right':
        m.pressed.add('J1RIGHT')
    if f:
        m.pressed.add('J1FIRE')
    now = m.cycles
    if st['end'] is not None and st['start'] is not None and st['snap'] is not None:
        busy = st['start'] - st['end']
        snap = st['snap']
        if busy > HI * FRC:
            tgt = collections.Counter()
        else:
            tgt = heavy if busy > LIM * FRC else light
        if tgt is heavy or tgt is light:
            nh[0 if tgt is heavy else 1] += 1
        for k, v in m.prof.items():
            dv = v - snap.get(k, 0)
            if dv:
                tgt[k] += dv
    st['end'] = now
    st['start'] = None
    st['snap'] = dict(m.prof)


# cycles a frame, measured
cA = t.cycles
t.run_frames(10)
FRC = (t.cycles - cA) / 10.0
print('cycles a frame %.0f' % FRC)
t.pc_hooks[wa] = w
t.pc_hooks[ta] = tick
t.run_frames(1500)

lst = 'build/cv_gen.lst'
labs = {}
bank = 'ALL'
labn = None
for line in open(lst, encoding='latin-1'):
    b = re.match(r'^\d+\s+BANK\s+(\S+)', line)
    if b:
        bank = b.group(1).split(',')[0]
        continue
    if re.match(r'^\d+\s+AORG ', line):
        labn = None
        continue
    m = re.match(r'^\d+\s+(?:[0-9A-F]{4} [0-9A-F]{4}\s+\d+\s+)?([A-Z_][A-Z0-9_]*)(\s|$)', line)
    if m and line.split()[0].isdigit():
        name = m.group(1)
        if re.match(r'^C[0-9A-F]{4}$', name) or name.startswith('N_') or name in cspeed.RT_NAMES:
            labn = name
        elif labn is None and re.match(r'^Z[0-9A-F]{4}$', name):
            labn = name
    m = re.match(r'^\d+ ([0-9A-F]{4}) ', line)
    if m:
        labs.setdefault((bank, int(m.group(1), 16)), labn)


def agg(c):
    a = collections.Counter()
    for (b, pc), cyc in c.items():
        if 0x6000 <= pc < 0x8000:
            l = labs.get((str(b), pc)) or labs.get(('ALL', pc))
        else:
            l = labs.get(('ALL', pc))
        a[l] += cyc
    return a


H, L = agg(heavy), agg(light)
th, tl = sum(H.values()), sum(L.values())
print('heavy ticks %d: %.0f cycles each (%.2f frames); light %d: %.0f each' %
      (nh[0], th / max(1, nh[0]), th / max(1, nh[0]) / FRC, nh[1], tl / max(1, nh[1])))
print('%-10s %9s %9s' % ('routine', 'heavy/tk', 'light/tk'))
for l, cyc in H.most_common(ROWS):
    print('%-10s %9.0f %9.0f' % (l, cyc / nh[0], L[l] / max(1, nh[1])))
json.dump({'n': nh[0], 'pcs': [[str(b), pc, c] for (b, pc), c in heavy.items()]}, open('build/heavy_pcs.json', 'w'))
json.dump({'n': nh[1], 'pcs': [[str(b), pc, c] for (b, pc), c in light.items()]}, open('build/light_pcs.json', 'w'))
