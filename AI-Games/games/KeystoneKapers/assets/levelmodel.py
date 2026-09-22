"""Read the small, numeric per-Krook speed program from the actual BASIC."""
import re


def speeds(source, krook):
    block = source.split('start_krook:', 1)[1].split("' HARRY'S SPEED", 1)[0]
    values = {}
    for raw in block.splitlines():
        line = raw.split("'", 1)[0].strip()
        match = re.fullmatch(r'(?:IF krk > (\d+) THEN )?(obsp|ocsp|opsp) = (\d+)', line)
        if match:
            threshold, name, value = match.groups()
            if threshold is None or krook > int(threshold):
                values[name] = int(value)
    if set(values) != {'obsp', 'ocsp', 'opsp'}:
        raise ValueError('Cannot read all three hazard speeds from start_krook')
    update = source.split('upd_obst:', 1)[1].split('pace_step:', 1)[0]
    if not re.search(r'^\s*ospp = pspd \+ pspd\b', update, re.M):
        raise ValueError('Plane movement no longer uses two-pixel accumulator units')
    return {1: values['ocsp'], 2: values['obsp'], 3: 0, 4: values['opsp'] * 2}
