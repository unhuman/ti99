"""Build a TI-99/4A cartridge from a translated Atari 8-bit game (A82TI99).

  build(g, root)   g = the game's ann module, root = the game folder

Layout: non-inverted bank-switched cart, 8 KB banks (select = write to >6000+2n).
Every bank starts with the shared segment (runtime65.a99, src/game.a99, tables);
translated code fills the rest of the code banks; the RAM image (6502 data,
islands, zero page) sits in payload banks and is copied out at power-up.
Outputs: build/<NAME>_8.bin, and under artifacts/gen: the source, listing and
labels.json (TI address and bank of every 6502 label, cells, sizes).
"""
import os, sys, json, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import xlate65, asm65
from asm65 import item_size, item_text
from a8emu import KEY, MODE_LINES, MODE_BYTES
import ti99emu_base

BANK = 0x2000
VARS = ['CURBNK', 'SAVBNK', 'IRETV', 'SAVR11', 'INISR', 'KLAST', 'VMODE', 'WINX', 'RNDV', 'FRAMES', 'RDRET', 'TRAPV',
        'STICKV', 'TRIGV', 'CONSV', 'LASTDL', 'FVRET', 'GV1', 'GV2', 'GV3', 'SCROFF', 'GV4', 'GV5', 'GV6', 'GV7', 'GM', 'GS1', 'GREST', 'GROW', 'GNR', 'GSTOP', 'GSV1', 'GSV2', 'GCS', 'GCP', 'GCB', 'GLN',
        'SQL0', 'SQL1', 'SQLE', 'SQLS', 'SQC0', 'SQC1', 'SQJ', 'SQJE', 'SQP0', 'SQDEP', 'SQNEST']
VARBASE = 0x2000
NBRES = 0x0600                  # room for g.BANKED natives at the start of their bank
PAYORG = 0x6040                 # payload banks: header and START's bank-0 select below this


def sel(bank): return 0x6000 + 2 * bank


def layout(chunks, cap, first_bank):
    """Assign chunks to banks and choose branch forms.  First with worst-case sizes (always fits),
    then again with the sizes the relaxed branches really have, which needs far fewer banks.
    -> where, forms, label bank, label offset, bytes used per bank"""
    def worst(it):
        if isinstance(it, str) or it[0] in ('LABEL', 'RET'): return item_size(it, 1)
        return item_size(it, 2)

    def assign(sizes):
        where = []; bank = first_bank; used = 0
        for n in sizes:
            if n > cap: raise SystemExit('a chunk of %d bytes does not fit a bank (%d)' % (n, cap))
            if used + n > cap: bank += 1; used = 0
            where.append(bank); used += n
        return where

    def relax(where):
        lbank = {}
        for ci, (_, items) in enumerate(chunks):
            for it in items:
                if not isinstance(it, str) and it[0] == 'LABEL': lbank[it[1]] = where[ci]
        forms = {}
        for ci, (_, items) in enumerate(chunks):
            for ii, it in enumerate(items):
                if isinstance(it, str): continue
                if it[0] in ('BR', 'JMP'):
                    forms[ci, ii] = 1 if lbank[it[3] if it[0] == 'BR' else it[1]] == where[ci] else 2
                elif it[0] == 'CALL':
                    forms[ci, ii] = 1 if len(it) > 2 or lbank['L%04X' % it[1]] == where[ci] else 2
        while True:
            addr = {}; pos = {}; top = {}
            for ci, (_, items) in enumerate(chunks):
                a = top.get(where[ci], 0)
                for ii, it in enumerate(items):
                    if not isinstance(it, str) and it[0] == 'LABEL': addr[it[1]] = a
                    pos[ci, ii] = a
                    a += item_size(it, forms.get((ci, ii), 1))
                top[where[ci]] = a
            changed = False
            for (ci, ii), f in list(forms.items()):
                it = chunks[ci][1][ii]
                if f != 1 or it[0] not in ('BR', 'JMP'): continue
                tgt = it[3] if it[0] == 'BR' else it[1]
                n = len(it[1]) if it[0] == 'BR' else 1
                d = (addr[tgt] - (pos[ci, ii] + 2 * n)) // 2
                if -120 <= d <= 120: forms[ci, ii] = 0; changed = True
            if not changed: return forms, lbank, addr, top

    where = assign([sum(worst(it) for it in items) for _, items in chunks])
    forms, lbank, addr, top = relax(where)
    for margin in (1.03, 1.06, 1.10, 1.15):
        real = [sum(item_size(it, forms.get((ci, ii), 1)) for ii, it in enumerate(items)) for ci, (_, items) in enumerate(chunks)]
        w2 = assign([min(cap, int(n * margin) + 2) for n in real])
        if max(w2) >= max(where): break
        f2, lb2, ad2, top2 = relax(w2)
        if max(top2.values()) <= cap:
            where, forms, lbank, addr, top = w2, f2, lb2, ad2, top2; break
    return where, forms, lbank, addr, top


def ram_image(g):
    """The TI RAM the game starts with: (start, bytes) regions and the scratchpad cells."""
    ram = bytearray(65536); M = g.MEM
    for a in range(0x200, 0x2000): ram[a + g.K] = M[a]
    for a in range(0x8100, 0xC000): ram[(a + g.K) & 0xFFFF] = M[a]
    for lo, hi in g.POOLS: ram[lo:hi] = bytes(hi - lo)
    ram[VARBASE:VARBASE + 0x200] = bytes(0x200)
    ram[0x2900:0x2B00] = bytes(0x200)
    ram[g.FONT:g.FONT + 0x400] = bytes(0x400)
    for s, e, t in g.ISLANDS: ram[t:t + e - s] = M[s:e]
    for a in list(range(0x80, 0x100)) + list(g.ZPLOW): ram[g.ti_addr(a, 0)] = M[a]
    return ram


def text_table(g, dl):
    """DATA lines for TXTDRW from an ANTIC display list of text rows (modes 2 and 6)."""
    M = g.MEM; pc = dl; line = 0; mem = 0; out = []
    while True:
        op = M[pc]; pc += 1; mode = op & 15
        if mode == 0: line += ((op >> 4) & 7) + 1; continue
        if mode == 1: break
        if op & 0x40: mem = M[pc] | M[pc + 1] << 8; pc += 2
        row = (line - 24 + 4) // 8
        if 0 <= row < 24:
            if mode == 2: out.append('       DATA >%04X,%d,32,1' % (g.ti_addr(mem + 4, 0), row * 32))
            elif mode in (6, 7): out.append('       DATA >%04X,%d,16,2' % (g.ti_addr(mem + 2, 0), row * 32))
        line += MODE_LINES[mode]; mem += MODE_BYTES[mode]
    return out + ['       DATA 0']


def build(g, root, shared=0x0B00):
    x = xlate65.Translator(g)
    isl, free = g.plan_islands(x.t, x.smc)
    chunks = x.translate()
    codeorg = 0x6000 + shared; cap = BANK - shared
    where, forms, lbank, addr, top = layout(chunks, cap, 0)
    ncode = max(where) + 1
    banked = getattr(g, 'BANKED', None)      # natives in a bank of their own, after the code banks (src files)
    if isinstance(banked, str): banked = [banked]
    nbres = getattr(g, 'NBRES', NBRES)
    nbank = ncode if banked else None
    banked2 = getattr(g, 'BANKED2', None) or []  # a second natives bank (NB2SEL), after the first
    nb2 = ncode + (1 if banked else 0) if banked2 else None
    banked3 = getattr(g, 'BANKED3', None) or []  # a third (NB3SEL), after the second
    nb3 = ncode + (1 if banked else 0) + (1 if banked2 else 0) if banked3 else None
    nexec = ncode + (1 if banked else 0) + (1 if banked2 else 0) + (1 if banked3 else 0)        # banks that carry the shared segment
    ram = ram_image(g)
    # payload: the RAM regions (cleared at boot), less runs of 64+ zero bytes, cut into pieces.
    # Pieces fill the free tails of the code banks first, then payload banks, which carry only the
    # cart header and the start of START (to PAYORG); the boot copier runs from RAM.
    regions = [(0x2000, 0x2000), (0xA000, 0x4000), (0xFE00, 0x0200)]
    spans = []
    for dst, n in regions:
        i = dst
        while i < dst + n:
            if ram[i] == 0:
                j = i
                while j < dst + n and ram[j] == 0: j += 1
                if j - i < 64 and spans and spans[-1][1] == i: spans[-1][1] = j
                i = j; continue
            j = i
            while j < dst + n and ram[j] != 0: j += 1
            if spans and i - spans[-1][1] < 64: spans[-1][1] = j
            else: spans.append([i, j])
            i = j
    spans = [(a & ~1, ((b + 1) & ~1) - (a & ~1)) for a, b in spans]
    room = [[b, codeorg + ((top.get(b, 0) + 1) & ~1), 0x8000] for b in range(ncode)]      # bank, first free address, end
    if banked: room.append([nbank, codeorg + nbres, 0x8000])
    if banked2: room.append([nb2, codeorg + g.NB2RES, 0x8000])
    if banked3: room.append([nb3, codeorg + g.NB3RES, 0x8000])
    pay = []; pbank = nexec; pdata = []
    for dst, n in spans:
        o = 0
        while o < n:
            r = next((r for r in room if r[2] - r[1] >= 64 or r[2] - r[1] >= n - o > 0), None)
            if r is None: room.append([pbank, PAYORG, 0x8000]); pbank += 1; continue
            k = min(r[2] - r[1], n - o) & ~1
            pay.append((r[0], dst + o, k, r[1])); pdata.append((r[0], r[1] - 0x6000, bytes(ram[dst + o:dst + o + k])))
            r[1] += k; o += k
    # data blobs (g.data_blobs(): name -> bytes, e.g. pictures): pieces in the same free room.
    # Table NAME: DATA select,source,bytes ... 0, read by a copier running from RAM.
    blobt = []
    for name, data in (g.data_blobs() if hasattr(g, 'data_blobs') else []):
        ents = []; o = 0
        while o < len(data):
            r = next((r for r in room if r[2] - r[1] >= 64 or r[2] - r[1] >= len(data) - o > 0), None)
            if r is None: room.append([pbank, PAYORG, 0x8000]); pbank += 1; continue
            k = min(r[2] - r[1], len(data) - o) & ~1
            ents.append((r[0], r[1], k)); pdata.append((r[0], r[1] - 0x6000, bytes(data[o:o + k])))
            r[1] += k; o += k
        blobt.append((name, ents))
    spimg = bytes(ram[0x8320:0x83C0])               # scratchpad cells ride in the last payload bank's tail?  keep them shared
    nb = 1
    while nb < pbank: nb *= 2

    gen = os.path.join(root, 'artifacts', getattr(g, 'GEN', 'gen')); os.makedirs(gen, exist_ok=True)
    os.makedirs(os.path.join(root, 'build'), exist_ok=True)
    L = []
    for i, v in enumerate(VARS): L.append('%-6s EQU  >%04X' % (v, VARBASE + 2 * i))
    if 2 * len(VARS) > 0x80: raise SystemExit('runtime variables (%d) overrun SAVWS at >%04X' % (len(VARS), VARBASE + 0x80))
    ramlo = getattr(g, 'RAMLO', VARBASE + 0x80)          # a game's own cells below SAVWS start there
    if VARBASE + 2 * len(VARS) > ramlo: raise SystemExit('runtime variables (%d) overrun the game cells at >%04X' % (len(VARS), ramlo))
    L.append('SAVWS  EQU  >%04X' % (VARBASE + 0x80))         # the interrupt glue's saved workspace, 32 bytes: >2080-209F
    for name, v in g.STACKS.items(): L.append('%-6s EQU  >%04X' % (name, v))
    L += ['K      EQU  >%04X' % g.K, 'KS     EQU  >%04X' % g.KS, 'KF     EQU  >%04X' % g.KF, 'FONT   EQU  >%04X' % g.FONT,
          'SCRLO  EQU  >%04X' % g.SCREEN[0], 'SCRHI  EQU  >%04X' % g.SCREEN[1], 'CODEHI EQU  >%04X' % g.CODE[1],
          'SHADOW EQU  >%04X' % ((g.SCREEN[0] + g.KS) & 0xFFFF), 'RSEED  EQU  >%04X' % getattr(g, 'RSEED', 1),
          'TXTCOL EQU  >F400', 'TXTBAK EQU  4']
    L += ['%-6s EQU  >%04X' % (n, a) for n, a in sorted(g.cells().items())]
    if banked: L.append('NBSEL  EQU  >%04X' % sel(nbank))
    if banked2: L.append('NB2SEL EQU  >%04X' % sel(nb2))
    if banked3: L.append('NB3SEL EQU  >%04X' % sel(nb3))
    L += ['       BANK ALL,>6000', '       COPY "runtime65.a99"', '       COPY "game.a99"']
    L += ['ENTRYV BL   @FARJ', '       DATA L%04X,>%04X' % (g.ENTRY, sel(lbank['L%04X' % g.ENTRY])),
          'VBIENT BL   @FARJ', '       DATA L%04X,>%04X' % (g.VBI, sel(lbank['L%04X' % g.VBI])),
          'DLIENT BL   @FARJ', '       DATA L%04X,>%04X' % (g.DLI, sel(lbank['L%04X' % g.DLI]))]
    for vec, targets in x.ijmp_items():
        L += ['IJ%04X STST R15' % vec, '       MOVB @>%04X,R0' % g.ti_addr(vec + 1, 0), '       MOVB @>%04X,@WS+1' % g.ti_addr(vec, 0),
              '       LI   R4,IT%04X' % vec, 'IL%04X MOV  *R4+,R12' % vec, '       JEQ  IX%04X' % vec, '       C    R12,R0',
              '       JNE  IN%04X' % vec, '       B    @IJGO', 'IN%04X C    *R4+,*R4+' % vec, '       JMP  IL%04X' % vec,
              'IX%04X BL   @TRAP' % vec, 'IT%04X' % vec]
        L += ['       DATA >%04X,L%04X,>%04X' % (t, t, sel(lbank['L%04X' % t])) for t in targets] + ['       DATA 0']
    L.append('ZPMAP  ANDI R4,>00FF            zero-page address (wrapped) -> TI address')
    for i, (lo, off) in enumerate(g.ZPRANGES):
        L += ['       CI   R4,>%04X' % lo, '       JL   ZPM%d' % i, '       AI   R4,>%04X' % (off & 0xFFFF), '       RT', 'ZPM%d' % i]
    L.append('       BL   @TRAP')
    L.append('PAYT')
    L += ['       DATA >%04X,>%04X,>%04X,%d' % (sel(b), src, dst, (n + 1) // 2) for b, dst, n, src in pay]
    L += ['       DATA >6000,SPIMG,>8320,%d' % (len(spimg) // 2), '       DATA 0']
    for name, ents in blobt:
        L.append(name); L += ['       DATA >%04X,>%04X,%d' % (sel(b), src, k) for b, src, k in ents] + ['       DATA 0']
    L.append('SPIMG'); L +=['       BYTE ' + ','.join('>%02X' % v for v in spimg[i:i + 16]) for i in range(0, len(spimg), 16)]
    L.append('ISLT')
    L += ['       DATA >%04X,>%04X,>%04X' % (s, e, (t - s) & 0xFFFF) for s, e, t in g.ISLANDS] + ['       DATA 0,>FFFF,K']
    L.append('BTAB'); L += ['       BYTE ' + ','.join('>%02X' % v for v in range(i, i + 16)) for i in range(0, 256, 16)]
    keytab = [0xFF] * 48
    for name, (col, row) in ti99emu_base.KEYS.items():
        an = {' ': 'SPACE', 'ENTER': 'RETURN'}.get(name, name)
        if col < 6 and an in KEY: keytab[col * 8 + row] = KEY[an]
    L.append('KEYTAB'); L += ['       BYTE ' + ','.join('>%02X' % v for v in keytab[i:i + 8]) for i in range(0, 48, 8)]
    L += g.gen_lines(text_table)
    L += ['       EVEN', 'SHEND']
    for b in range(ncode):
        L += ['       BANK %d' % b, '       AORG >%04X' % codeorg]
        for ci, (_, items) in enumerate(chunks):
            if where[ci] != b: continue
            for ii, it in enumerate(items):
                f = forms.get((ci, ii), 1); s = None
                if f == 2:
                    tgt = it[3] if it[0] == 'BR' else it[1] if it[0] == 'JMP' else 'L%04X' % it[1]
                    s = sel(lbank[tgt])
                L += item_text(it, f, s)
    if banked:
        L += ['       BANK %d' % nbank, '       AORG >%04X' % codeorg] + ['       COPY "%s"' % f for f in banked]
        L += g.banked_lines() if hasattr(g, 'banked_lines') else []      # generated tables for them
        L += ['       EVEN', 'NBEND']
    if banked2:
        L += ['       BANK %d' % nb2, '       AORG >%04X' % codeorg] + ['       COPY "%s"' % f for f in banked2]
        L += ['       EVEN', 'NB2END']
    if banked3:
        L += ['       BANK %d' % nb3, '       AORG >%04X' % codeorg] + ['       COPY "%s"' % f for f in banked3]
        L += ['       EVEN', 'NB3END']
    L.append('       END')
    src = os.path.join(gen, 'gen.a99'); open(src, 'w').write('\n'.join(L) + '\n')
    shutil.copy(os.path.join(HERE, 'runtime65.a99'), gen)
    shutil.copy(os.path.join(root, 'src', 'game.a99'), gen)
    for f in list(banked or ()) + banked2 + banked3: shutil.copy(os.path.join(root, 'src', f), gen)
    open(os.path.join(gen, 'name.a99'), 'w').write("       BYTE %d\n       TEXT '%s'\n" % (len(g.NAME), g.NAME))
    mem, sym = asm65.assemble(src)
    if sym['SHEND'] > codeorg: raise SystemExit('shared segment ends at >%04X, past >%04X: raise shared=' % (sym['SHEND'], codeorg))
    bad = [n for n, a in addr.items() if sym.get(n.upper()) != a + codeorg]
    if bad: raise SystemExit('size model mismatch at %d labels, first %s: layout >%04X, xas99 >%04X' % (
        len(bad), bad[0], addr[bad[0]] + codeorg, sym.get(bad[0].upper(), 0)))
    banks = [bytearray(b'\xff' * BANK) for _ in range(nb)]
    if banked and sym['NBEND'] > codeorg + nbres: raise SystemExit('banked natives end at >%04X, past >%04X: raise NBRES' % (sym['NBEND'], codeorg + nbres))
    # NBRES is counted from codeorg, which moves up as the shared segment grows: the bank's end is a
    # separate limit (an AORG past >7FFF assembled without complaint and cut the title's code off).
    for n in ('NBEND', 'NB2END', 'NB3END'):
        if n in sym and sym[n] > 0x8000: raise SystemExit('%s at >%04X: the natives no longer fit their bank (shared ends >%04X)' % (n, sym[n], sym['SHEND']))
    if banked2 and sym['NB2END'] > codeorg + g.NB2RES: raise SystemExit('second natives bank ends at >%04X, past >%04X: raise NB2RES' % (sym['NB2END'], codeorg + g.NB2RES))
    if banked3 and sym['NB3END'] > codeorg + g.NB3RES: raise SystemExit('third natives bank ends at >%04X, past >%04X: raise NB3RES' % (sym['NB3END'], codeorg + g.NB3RES))
    if sym['BOOTE'] > PAYORG: raise SystemExit('START reaches >%04X before selecting bank 0; payload banks start at >%04X' % (sym['BOOTE'], PAYORG))
    for b in range(nb):
        for a, v in mem['ALL'].items():
            if b < nexec or b >= pbank or a < PAYORG: banks[b][a - 0x6000] = v
        for a, v in mem.get(b, {}).items(): banks[b][a - 0x6000] = v
    for b, off, d in pdata:
        if any(v != 0xFF for v in banks[b][off:off + len(d)]): raise SystemExit('payload overlaps code in bank %d at >%04X' % (b, 0x6000 + off))
        banks[b][off:off + len(d)] = d
    out = os.path.join(root, 'build', '%s_8.bin' % g.NAME)
    open(out, 'wb').write(b''.join(banks))
    labels = {n: [lbank[n], a + codeorg] for n, a in addr.items() if n[0] in 'LJ' and len(n) == 5}
    # where every 6502 instruction starts on the TI (lockstep65.py): the comment item in front of it
    pos = {}; tops = {}; insn = {}
    for ci, (_, items) in enumerate(chunks):
        a = tops.get(where[ci], 0)
        for ii, it in enumerate(items):
            if isinstance(it, str) and it.startswith('* '): insn[it[2:6]] = [where[ci], a + codeorg]
            a += item_size(it, forms.get((ci, ii), 1))
        tops[where[ci]] = a
    info = dict(labels=labels, sym={k: v for k, v in sym.items() if not (k[0] in 'LJT' and k[1:].isalnum() and len(k) <= 6 and k[1:2].isdigit())},
                banks=nb, code_banks=ncode, shared_end=sym['SHEND'], codeorg=codeorg,
                code_bytes=sum(top.values()), islands=g.ISLANDS, cells=g.cells(), insn=insn)
    json.dump(info, open(os.path.join(gen, 'labels.json'), 'w'))
    print('%s: %d banks (%d code, %d payload), code %d bytes, shared ends >%04X (limit >%04X), islands %d bytes' % (
        os.path.basename(out), nb, ncode, pbank - ncode, sum(top.values()), sym['SHEND'], codeorg, isl))
    return out
