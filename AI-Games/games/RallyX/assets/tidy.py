import io
p = 'genmusic.py'
s = io.open(p, encoding='utf-8').read()

def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)

sub('STEP_TICKS = div // STEPS_PER_BEAT          # ticks per eighth',
    'STEP_TICKS = div // STEPS_PER_BEAT          # ticks per step (a sixteenth)')
sub('    """Quantise to the eighth grid. A slot holds a pitch where a note',
    '    """Quantise to the sixteenth grid. A slot holds a pitch where a note')
sub('''         "\t' New Rally-X BGM, 151 BPM, STRAIGHT EIGHTHS -- one step is one",
         "\t' eighth = 12 frames (MUSTICK). %d steps = %d bars." % (STEPS, STEPS // 16),''',
    '''         "\t' New Rally-X BGM, 151 BPM. One step is a SIXTEENTH = 6 frames",
         "\t' (MUSTICK): the bass is eighths but the melody has sixteenth runs,",
         "\t' and an eighth grid swallowed the second note of every pair.",
         "\t' %d steps = %d bars. Position must be 16-bit -- this is past 255." % (STEPS, STEPS // 16),''')
sub('        lines.append("\t\' bar %d" % (i // 8 + 1))',
    '        lines.append("\t\' bar %d" % (i // 16 + 1))')
io.open(p, 'w', encoding='utf-8').write(s)
print("comments and bar numbering corrected")
