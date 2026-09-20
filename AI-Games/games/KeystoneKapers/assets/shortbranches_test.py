import unittest
from shortbranches import INVERSE, OPCODE, relax, verify


def fixture(op='jeq', delta=10):
    # Backward targets precede the candidate; forward targets follow its skip.
    target = 0xB002 + delta * 2
    head = ['cvb_BOOT', 'cv1', '\tclr r0'] if delta < 0 else ['cvb_BOOT']
    n = len(head) + 1
    lines = head + ['\t%s cv2' % op, '\tb @cv1', 'cv2', '\tclr r0']
    rows = [(n, 0xB000, OPCODE.get(op, 0x1100) | 2),
            (n+1, 0xB002, 0x0460), (n+3, 0xB006, 0x04C0)]
    if delta < 0:
        rows.insert(0, (3, target, 0x04C0))
    else:
        lines += ['cv1', '\tclr r0']
        rows.append((len(lines), target, 0x04C0))
    lines += ['BANK_0_FREE: EQU >fffe-$', '\tbank 4']
    listing = ''.join('%5d %04X %04X     instruction\n' % row for row in rows)
    return '\n'.join(lines) + '\n', listing, rows


class BranchTest(unittest.TestCase):
    def test_conditions_and_encoding(self):
        for op in INVERSE:
            for delta in (-128, -127, -4, 3, 126, 127):
                with self.subTest(op=op, delta=delta):
                    source, listing, rows = fixture(op, delta)
                    optimized, changes = relax(source, listing)
                    self.assertEqual(len(changes), 1)
                    c = changes[0]
                    out = []
                    for n, addr, word in rows:
                        if n == c['removed']:
                            continue
                        if n > c['removed']:
                            addr -= 4
                        if n == c['line']:
                            word = OPCODE[INVERSE[op]] | ((delta - (2 if delta >= 0 else 0)) & 255)
                        out.append('%5d %04X %04X     instruction\n' % (n, addr, word))
                    verify(source, listing, optimized, ''.join(out), changes)
                    corrupt = list(out)
                    index = next(i for i, row in enumerate(corrupt) if int(row.split()[0]) == c['line'])
                    fields = corrupt[index].split()
                    fields[2] = '%04X' % (int(fields[2], 16) ^ 1)
                    corrupt[index] = ' '.join(fields) + '\n'
                    with self.assertRaises(ValueError):
                        verify(source, listing, optimized, ''.join(corrupt), changes)
                    with self.assertRaises(ValueError):
                        verify(source, listing, optimized, ''.join(out), [])
        # For every EQ/LGT flag combination, the old taken-skip path falls
        # through the replacement, and the old absolute branch is now taken.
        for eq in (False, True):
            for lgt in (False, True):
                flags = {'jeq': eq, 'jne': not eq, 'jhe': lgt or eq, 'jl': not (lgt or eq)}
                for op, inverse in INVERSE.items():
                    self.assertEqual(not flags[op], flags[inverse])

    def test_boundaries_and_unsupported(self):
        for delta in (-129, 128):
            source, listing, _ = fixture(delta=delta)
            self.assertEqual(relax(source, listing), (source, []))
        source, listing, _ = fixture(op='jlt')
        self.assertEqual(relax(source, listing), (source, []))

    def test_labels_segments_and_bad_listing(self):
        source, listing, _ = fixture()
        # An intervening label can be an entry point: never remove its B.
        labelled = source.replace('\tb @cv1', 'cv3\n\tb @cv1')
        self.assertEqual(relax(labelled, listing), (labelled, []))
        for bad in (source.replace('cvb_BOOT', 'other'),
                    source.replace('\tclr r0', '\taorg >B008\n\tclr r0'),
                    source.replace('cv2\n', 'cv2\n\tbank 4\n')):
            with self.assertRaises(ValueError):
                relax(bad, listing)
        with self.assertRaises(ValueError):
            relax(source, listing.replace('1302', '1303'))
        with self.assertRaises(ValueError):
            relax(source, '')


if __name__ == '__main__':
    unittest.main()
