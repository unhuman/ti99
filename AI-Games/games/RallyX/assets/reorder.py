import io
p = 'genrocks.py'
s = io.open(p, encoding='utf-8').read()

def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)

sub("""        if must_reach <= reachable(road, trial, start):
            chosen.append(best)
        if not cand:
            break
    return chosen""",
"""        if must_reach <= reachable(road, trial, start):
            chosen.append(best)
        if not cand:
            break
    # ORDER BY DISTANCE FROM THE START, nearest first. Farthest-point
    # sampling picks good POSITIONS but a terrible ORDER: after the centre
    # seed it jumps straight to the maze corners, so rounds 2-5 -- one to
    # four rocks -- put them where nobody drives.
    #
    # Reordering is free because reachability is MONOTONE: removing a rock
    # can only open paths, so if the full set leaves every flag reachable
    # then so does every subset, whatever order they appear in. The
    # incremental check above is what guarantees the full set; the prefixes
    # come along for nothing.
    chosen.sort(key=lambda rc: abs(rc[0] - start[0]) + abs(rc[1] - start[1]))
    return chosen""")

sub("""    # paranoia: re-verify every prefix independently of the build loop
    for k in range(len(rocks) + 1):
        assert set(flags) <= reachable(road, set(rocks[:k]), start), \
            "maze %d prefix %d strands a flag" % (lvl, k)""",
"""    # Paranoia: re-verify every prefix independently, AFTER the reorder.
    # Monotonicity says checking the full set is enough, but this is cheap
    # and it is the property the game actually depends on.
    for k in range(len(rocks) + 1):
        assert set(flags) <= reachable(road, set(rocks[:k]), start), \
            "maze %d prefix %d strands a flag" % (lvl, k)""")
io.open(p, 'w', encoding='utf-8').write(s)
print("ordering fixed")
