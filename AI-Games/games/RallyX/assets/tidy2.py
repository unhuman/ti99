import io
p = 'genmusic.py'
s = io.open(p, encoding='utf-8').read()
for old, new in (
    ('STEP_TICKS = div // STEPS_PER_BEAT          # ticks per eighth',
     'STEP_TICKS = div // STEPS_PER_BEAT          # ticks per step (a sixteenth)'),
    ('    """Quantise to the eighth grid. A slot holds a pitch where a note',
     '    """Quantise to the sixteenth grid. A slot holds a pitch where a note'),
    ("        lines.append(\"\t' bar %d\" % (i // 8 + 1))",
     "        lines.append(\"\t' bar %d\" % (i // 16 + 1))"),
):
    assert s.count(old) == 1, old[:50]
    s = s.replace(old, new)
io.open(p, 'w', encoding='utf-8').write(s)
print("tidied")
