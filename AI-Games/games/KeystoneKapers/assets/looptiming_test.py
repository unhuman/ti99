"""Platform guards must pace Coleco/NES without changing the TI reference."""
from pathlib import Path
import re
import unittest

SOURCE = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()


def platform_source(source, platform):
    active, stack, lines = True, [], []
    for raw in source.splitlines():
        line = raw.split("'", 1)[0].strip()
        if line.startswith('#if '):
            condition = line[4:] == platform
            stack.append((active, condition))
            active = active and condition
        elif line == '#else':
            parent, condition = stack[-1]
            active = parent and not condition
        elif line == '#endif':
            active = stack.pop()[0]
        elif active:
            lines.append(line)
    return '\n'.join(lines)


def pacing(source, platform):
    code = platform_source(source, platform)
    main = code.split('main:', 1)[1].split('fphs =', 1)[0]
    paced = 'nes_pace:' in main
    if not paced:
        return [1] * 40
    initial = int(re.search(r'^nespw = (\d+)$', code, re.M)[1])
    total = int(re.search(r'^nespw = (\d+) - nespw$', main, re.M)[1])
    assert 'IF #fd < nespw THEN\nWAIT\nGOTO nes_pace' in main
    result = []
    for _ in range(40):
        result.append(initial)
        initial = total - initial
    return result


class LoopTimingTest(unittest.TestCase):
    def test_fast_targets_take_100_frames_for_40_steps(self):
        for platform in ('NES', 'COLECO'):
            self.assertEqual(pacing(SOURCE, platform), [2, 3] * 20)

    def test_ti_retains_its_existing_loop(self):
        self.assertNotIn('nes_pace:', platform_source(SOURCE, 'TI994A'))

    def test_rejects_original_coleco_omission(self):
        old = SOURCE.replace('main:\n\tWAIT\n\t#if TI994A\n\t#else',
                             'main:\n\tWAIT\n\t#if NES', 1)
        self.assertNotEqual(sum(pacing(old, 'COLECO')), 100)


if __name__ == '__main__':
    unittest.main()
