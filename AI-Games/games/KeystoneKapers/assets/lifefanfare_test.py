"""Execute the award and fanfare BASIC routines, including NES/non-NES branches."""
from collections import defaultdict
from pathlib import Path
import re
import unittest
from checksound import routine, strip_comment, with_calls

SOURCE = Path(__file__).parents[1].joinpath('src/KEYSTONE.bas').read_text()

class Basic:
    def __init__(self, nes):
        self.nes = nes
        self.state = defaultdict(int)
        self.voices = defaultdict(lambda: [0, 0])
        self.writes = []

    def value(self, expression):
        expression = re.sub(r'#[a-z]+|[a-z]+', lambda m: str(self.state[m[0]]), expression)
        expression = re.sub(r'(?<![<>!])=(?!=)', '==', expression)
        assert re.fullmatch(r'[0-9 +<>=-]+', expression), expression
        return eval(expression, {'__builtins__': {}})

    def run(self, name):
        active, conditional = True, []
        lines = []
        for raw in routine(SOURCE.splitlines(), name):
            line = strip_comment(raw).strip()
            if line == '#if NES':
                conditional.append(active)
                active = active and self.nes
            elif line == '#else':
                active = conditional[-1] and not self.nes
            elif line == '#endif':
                active = conditional.pop()
            elif active and line:
                lines.append(line)
        blocks = [True]
        for line in lines:
            if line == 'END IF':
                blocks.pop()
                continue
            if line.startswith('IF ') and line.endswith(' THEN'):
                blocks.append(blocks[-1] and bool(self.value(line[3:-5])))
                continue
            if not blocks[-1]:
                continue
            if line.startswith('IF '):
                condition, line = line[3:].split(' THEN ', 1)
                if not self.value(condition):
                    continue
            if line == 'RETURN':
                return
            if line.startswith('GOSUB hud_'):
                continue
            if line.startswith('SOUND '):
                args = line[6:].split(',')
                channel = int(args[0])
                for index, arg in enumerate(args[1:]):
                    if arg:
                        self.voices[channel][index] = self.value(arg)
                self.writes.append((channel, tuple(self.voices[channel])))
            else:
                name, expression = line.split(' = ', 1)
                self.state[name] = self.value(expression)

class LifeTest(unittest.TestCase):
    def test_award_only_when_life_is_added_and_repeats(self):
        for nes in (False, True):
            vm = Basic(nes)
            vm.state.update({'#score': 990, '#nextk': 1000, '#addv': 10, 'kops': 3})
            vm.run('add_score')
            self.assertEqual((vm.state['kops'], vm.state['sfk'], vm.state['#nextk']), (4, 1, 2000))
            for lives in range(5, 10):
                vm.state.update({'sfk': 0, '#addv': 1000})
                vm.run('add_score')
                self.assertEqual((vm.state['kops'], vm.state['sfk']), (lives, 1))
            vm.state.update({'sfk': 0, '#addv': 1000})
            vm.run('add_score')
            self.assertEqual((vm.state['kops'], vm.state['sfk'], vm.state['#nextk']), (9, 0, 8000))
            vm.state['kops'] = 2
            vm.run('add_score')
            self.assertEqual((vm.state['kops'], vm.state['sfk']), (3, 1))

    def test_phrase_timing_and_final_note_off_on_each_platform(self):
        expected = [571]*2 + [428]*2 + [340]*2 + [286]*4 + [340]*2 + [428]*2 + [286]*6
        for nes in (False, True):
            vm = Basic(nes)
            vm.state['sfk'] = 1
            pitches = []
            channel = 0 if nes else 2
            for _ in expected:
                vm.run('life_tick')
                pitch, volume = vm.voices[channel]
                self.assertEqual(volume, 13)
                pitches.append(pitch)
            self.assertEqual(pitches, expected)
            vm.run('life_tick')
            self.assertEqual(vm.voices[channel][1], 0)
            self.assertEqual((vm.state['spt'], vm.state['sfk']), (0, 0))
            count = len(vm.writes)
            vm.run('life_tick')
            self.assertEqual(len(vm.writes), count)

    def test_bonus_and_capture_keep_award_sound_alive(self):
        bonus = SOURCE.split('bonus_count:', 1)[1].split('do_escape:', 1)[0]
        self.assertRegex(bonus, r'GOSUB add_score\s+GOSUB life_tick')
        self.assertRegex(bonus, r'IF spt = 0 THEN\s+SOUND 1,,12\s+SOUND 1,270\s+END IF')
        self.assertIn('IF spt = 0 THEN SOUND 2,108,12', bonus)
        self.assertIn('IF spt = 0 THEN SOUND 2,0,0', bonus)
        capture = SOURCE.split('do_catch:', 1)[1].split('bonus_count:', 1)[0]
        code = '\n'.join(strip_comment(line) for line in capture.splitlines())
        self.assertRegex(code, r'GOSUB life_finish\s+GOSUB snd_off')
        self.assertRegex(code, r'FOR bwi = 1 TO 21\s+WAIT\s+WAIT\s+WAIT\s+GOSUB life_tick')
        self.assertIn('IF spt = 0 THEN SOUND 0,#swp,12', SOURCE)

    def test_shutdown_gate_follows_sound_helpers(self):
        mutated = SOURCE.replace('life_tick:', 'life_tick:\n\tSOUND 4,100,15', 1)
        body = '\n'.join(with_calls(mutated.splitlines(), 'sfx_tick'))
        self.assertIn('SOUND 4,100,15', body)
        self.assertIn('spt = 21', body)

if __name__ == '__main__':
    unittest.main()
