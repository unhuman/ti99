import io
p = 'genrocks.py'
s = io.open(p, encoding='utf-8').read()

def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:60])
    s = s.replace(old, new)

sub("""    cand = sorted(road - banned)
    chosen = []
    must_reach = set(flags)""",
    """    cand = sorted(road - banned)
    chosen = []
    # ENEMY SPAWNS ARE IN THE PROOF TOO, not just the flags. The cars treat
    # rocks as walls, so a rock that seals a spawn into a pocket would leave
    # that car driving in circles in a closet for the whole round. Flags
    # being reachable does not imply the spawns are.
    must_reach = set(flags) | set(spawns)""")

sub("""    # Paranoia: re-verify every prefix independently, AFTER the reorder.
    # Monotonicity says checking the full set is enough, but this is cheap
    # and it is the property the game actually depends on.
    for k in range(len(rocks) + 1):
        assert set(flags) <= reachable(road, set(rocks[:k]), start), \
            "maze %d prefix %d strands a flag" % (lvl, k)""",
    """    # Paranoia: re-verify every prefix independently, AFTER the reorder.
    # Monotonicity says checking the full set is enough, but this is cheap
    # and it is the property the game actually depends on.
    need = set(flags) | set(spawns)
    for k in range(len(rocks) + 1):
        assert need <= reachable(road, set(rocks[:k]), start), \
            "maze %d prefix %d strands a flag or a spawn" % (lvl, k)""")
io.open(p, 'w', encoding='utf-8').write(s)
print("spawns added to the reachability proof")
