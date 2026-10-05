"""Editable conveyor art; regenerate with --write, verify during both builds."""
import argparse
from pathlib import Path
import re

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'


def rows(pixels):
    return [sum(128 >> x for x in range(8) if pixels(x, y)) for y in range(8)]


def diagonal(phase, offset=0):
    # Four-pixel band; stationary rails connect across the 2:1 tile seams.
    def pixel(x, y):
        depth = y - offset - (4 - x // 2)
        return depth in (0, 3) or (depth in (1, 2) and (x-phase) % 8 < 2)
    return rows(pixel)


def roller(phase):
    rim = [0x3c, 0x66, 0xc3, 0x81, 0x81, 0xc3, 0x66, 0x3c]
    # An off-centre spoke makes all eight rotational phases distinguishable.
    spokes = [(4,1),(5,2),(6,4),(5,5),(3,6),(2,5),(1,3),(2,2)]
    x,y = spokes[phase]
    rim[y] |= 128 >> x
    rim[3] |= 0x18
    rim[4] |= 0x18
    return rim


def flat(phase):
    return rows(lambda x,y: y in (2,6) or (3 <= y <= 5 and (x-phase) % 8 < 2))


def tables():
    post = [0x18]*7+[0x7e]
    result = {'convh_pat':flat(0), 'convh_col':[0x11,0x11,0xf1,0x31,0x31,0x31,0xf1,0x11],
              'conv_col':[0xf1]*32+[0xe1]*8}
    # Four blue/white cap tiles feed a tapered end tile. Its six-pixel red
    # mouth spans the whole first visible blob; the old two-pixel stem was
    # narrower than the goop it supposedly contained.
    # These are characters 225-226: 232 is the Level-1 thrower, not a valve.
    result['spigot_pat'] = ([0xff]*4+[0]*4+
                            [0xff,0xff,0xfe,0x7e,0x7e,0x7e,0x7e,0x7e])
    result['spigot_col'] = ([0x51,0xf1,0x51,0x51]+[0x11]*4+
                            [0x51,0xf1,0x51,0x51,0x91,0x91,0x91,0x91])
    for phase in range(8):
        result['belt_anim%d'%phase] = (diagonal(phase)+diagonal(phase,4)+
            diagonal(phase,-4)+roller(phase)+post+flat(phase))
    result['conv_pat'] = result['belt_anim0'][:40]
    # Five tiles: 32 clear pixels open, tips meet at x=19/20 when closed.
    result['claw_pat'] = []
    for phase in range(17):
        pixels = set()
        base = phase
        for y in range(2,8):
            # Continuous inner face: the lower jaw must close too, not just
            # three white pixels above a permanent gap between the heels.
            xs = range(base+2,base+4) if y<5 else range(base,base+4)
            for x in xs:
                pixels.add((x,y)); pixels.add((39-x,y))
        for tile in range(5):
            result['claw_pat'] += rows(lambda x,y: (x+tile*8,y) in pixels)
    result['claw_col'] = [0x11,0x11,0xf1,0xf1,0xf1,0x31,0x31,0xf1]*5
    # Pre-shift the centered rivets WITH the crane bar at every pixel offset.
    beam = [0xff,0xff,0xff,0xe7,0xe7,0xff,0xff,0xff]
    result['beamshift_pat'] = []
    for lower in (False,True):
        for offset in range(8):
            shifted = [0]*offset + beam + [0]*(8-offset)
            result['beamshift_pat'] += shifted[8:16] if lower else shifted[:8]
    # A visible parked head, supported by a lengthening piston. Colors follow
    # the four head rows across tile boundaries, rather than coloring a tile.
    head_colors = [0xf1,0xf1,0xe1,0xf1,0xf1]
    result['press_pat'] = []
    result['press_col'] = []
    for phase in range(32):
        head = phase - 9
        for row in range(3):
            for tile in range(2):
                def pixel(x,y):
                    x += tile*8; y += row*8
                    bracket = y<2 and 4<=x<=11
                    stem = 7<=x<=8 and y<head
                    face = head<=y<head+5 and 1<=x<=14
                    if y==head+2 and x in (3,12):face=False
                    return bracket or stem or face
                result['press_pat'] += rows(pixel)
                result['press_col'] += [head_colors[row*8+y-head] if head<=row*8+y<head+5 else 0xe1 for y in range(8)]
    # Factory head extends into the two empty rows ABOVE the belt's top rail.
    # Keep all eight belt phases beneath it; never erase or stop the conveyor.
    result['pressfoot_pat'] = []
    for depth in range(3):
        for phase in range(8):
            for tile in range(2):
                foot = flat(phase)
                for y in range(depth):
                    foot[y] = sum(128>>x for x in range(8) if 1<=x+tile*8<=14)
                result['pressfoot_pat'] += foot
    result['pressfoot_col'] = []
    for depth in range(3):
        col = [0x11,0x11,0xf1,0x31,0x31,0x31,0xf1,0x11]
        col[:depth] = head_colors[5-depth:] if depth else []
        result['pressfoot_col'] += col*2
    # One 16-pixel springboard, five heights. Its base stays planted while
    # the white/magenta cap descends to it and the exposed coil gets shorter.
    result['tramp_pat'] = []
    result['tramp_col'] = []
    for depth in range(5):
        for tile in range(2):
            def pixel(x,y):
                x += tile*8
                if y in (depth,depth+1):return 1<=x<=14
                if y in (6,7):return 3<=x<=12
                return depth+1<y<6 and x in ((5,10) if y&1 else (6,9))
            result['tramp_pat'] += rows(pixel)
            result['tramp_col'] += [0xf1 if y==depth else 0xd1 if y==depth+1
                                    else 0x31 if y>=6 else 0xd1 if y&1 else 0x31
                                    for y in range(8)]
    # Both factory springs reuse the exact two-character level-one artwork.
    result['pad_pat'] = result['tramp_pat'][:16]*2
    result['pad_col'] = result['tramp_col'][:16]*2
    # Reference furnace: twin green caps, white sight glass, magenta housing,
    # white panel bars, and a left-facing outlet level with the lower window.
    result['furnace_pat'] = [0x1c,0x1c,0x7f,0x40,0x5f,0x50,0xdf,0xc0,
                             0x38,0x38,0xfe,0x02,0xfa,0x0a,0xfa,0x02,
                             0x40,0x5f,0x40,0x5c,0x5c,0x40,0x7f,0x00,
                             0x02,0xfa,0x02,0x3a,0x3a,0x02,0xfe,0x00]
    result['furnace_col'] = ([0x31,0x31,0xd1,0xfd,0xfd,0xf1,0xfd,0xfd]*2
                            +[0xfd,0xfd,0xfd,0xfd,0xfd,0xfd,0xd1,0x41]*2)
    # A single wall emitter across two cells, with three outward trajectories.
    # White hot center, yellow/orange scatter; no round bomb/flame silhouettes.
    result['spark_pat'] = []
    for phase in range(8):
        pixels={(0,y) for y in range(8)} | {(1,y) for y in (0,1,6,7)}
        pixels |= {(x,y) for x in (1,2,3) for y in (3,4)}
        for offset,branch in ((0,-1),(5,0),(10,1)):
            x=3+(phase*2+offset)%16
            y=3+branch*(x//5)
            pixels.add((x,y))
            if x>3:pixels.add((x-1,y))
        for tile in range(2):
            result['spark_pat'] += rows(lambda x,y:(x+tile*8,y) in pixels)
    result['spark_col'] = [0xe1,0x91,0xb1,0xf1,0xf1,0xb1,0x91,0xe1]*2
    # Low two-cell crate on level 2's mid-left tier. Six visible pixels tall
    # so a normal jump clears it; the character codes remain in the lethal
    # hazard band so walking into the crate is unsafe.
    half = [0,0xff,0x81,0xbd,0xbd,0x81,0xff,0]
    result['crate_pat'] = half*2
    result['crate_col'] = [0xf1,0xf1,0x71,0x71,0x71,0x71,0xf1,0xf1]*2
    result['fire_pat'] = []
    for depth in range(17):
        def flame(x,y):
            if x < 16-depth: return False
            # A broad turbulent plume leaves the nozzle at (15,14), swells,
            # then tapers to a ragged up-curled tip at the left edge.
            reach = 15-x
            center = 14-(reach*7//15)
            if reach < 2: width=1
            elif reach < 8: width=1+reach//2
            elif reach < 11: width=3
            else: width=max(0,3-(reach-10)//2)
            # Changing tongues break the outline into animated licks.
            flicker = (x+depth)&3
            if flicker == 0: width += 1
            if flicker == 2: center -= 1
            if flicker == 3: center += 1
            return abs(y-center)<=width
        for row in range(2):
            for col in range(2):
                result['fire_pat'] += rows(lambda x,y: flame(col*8+x,row*8+y))
    # Four palettes cycle from red-orange edges through yellow to white-hot
    # cores. The furnace's two character rows each have independent gradients.
    palettes = (
        ([7,7,9,9,10,12,10,9], [7,9,9,10,12,15,10,9]),
        ([7,9,9,10,11,12,10,9], [9,9,10,11,12,15,11,10]),
        ([7,9,10,11,12,10,9,7], [9,10,11,12,15,12,10,9]),
        ([7,7,9,10,12,15,10,9], [7,9,10,12,15,12,10,9]),
    )
    assert all(sum(color in (7,9,10) for color in row) >= 4
               for palette in palettes for row in palette), 'fire palette needs more reds'
    result['fire_col'] = []
    for left,right in palettes:
        result['fire_col'] += [((color<<4)|1) for color in left]
        result['fire_col'] += [((color<<4)|1) for color in right]
        result['fire_col'] += [((color<<4)|1) for color in left]
        result['fire_col'] += [((color<<4)|1) for color in right]
    assert len(result['fire_col']) == 128
    return result


def rewrite(source):
    generated=tables()
    for label,data in generated.items():
        body = label+":\n\t' Generated by assets/genconveyors.py; edit the generator.\n"
        body += ''.join('\tDATA BYTE '+','.join('$%02X'%v for v in data[i:i+8])+'\n'
                        for i in range(0,len(data),8))
        source,n = re.subn(r'^'+label+r':\n.*?(?=^\w+:)',lambda m:body,source,
                           flags=re.M|re.S)
        assert n==1, 'missing/duplicate art label '+label
    for kind in ('pat','col'):
        idle=generated['tramp_'+kind][:16]
        body="\t' 137/138 springboard idle halves; generated by assets/genconveyors.py.\n"
        body+=''.join('\tDATA BYTE '+','.join('$%02X'%v for v in idle[i:i+8])+'\n'
                      for i in (0,8))
        label='tile_'+kind
        section=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S)
        updated,n=re.subn(r"\t' 137(?:/138)? springboard.*",lambda m:body,section[0],flags=re.S)
        assert n==1, 'missing springboard idle art '+label
        source=source[:section.start()]+updated+source[section.end():]
    return source


def check(source):
    assert rewrite(source)==source, 'conveyor art stale; run genconveyors.py --write'
    t=tables()
    # The shifted upper/lower cells must reconstruct the SAME centered rivets,
    # including offsets where those marks straddle the character boundary.
    for offset in range(8):
        pair=t['beamshift_pat'][offset*8:offset*8+8]+t['beamshift_pat'][64+offset*8:72+offset*8]
        assert pair[:offset]==[0]*offset and pair[offset+8:]==[0]*(8-offset)
        assert pair[offset:offset+8]==[255,255,255,231,231,255,255,255], 'crane rivets not centered'
    tile=re.search(r'^tile_pat:\n.*?(?=^\w+:)',source,re.M|re.S).group()
    tile='\n'.join(line.split("'")[0] for line in tile.splitlines())
    data=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',tile)]
    assert data[8:16]==[255]*8, 'plain level-2 beam contains rivets'
    dots=re.search(r'^girder_dot_pat:\n.*?(?=^\w+:)',source,re.M|re.S).group()
    dotted=[int(n[1:],16) for n in re.findall(r'\$[0-9A-F]{2}',dots)]
    assert dotted[8:16]==[255,255,255,231,231,255,255,255], 'level-2 rivets not centered'
    assert data[72:88]==t['tramp_pat'][:16], 'springboard starts in a different pose'
    spring=t['tramp_pat']
    assert len({tuple(spring[n:n+16]) for n in range(0,80,16)})==5
    for depth in range(5):
        frame=spring[depth*16:depth*16+16]
        pixels={(tile*8+x,y) for tile in range(2) for y in range(8)
                for x in range(8) if frame[tile*8+y] & (128>>x)}
        assert min(y for x,y in pixels)==depth, 'springboard cap does not compress'
        assert {(x,y) for x,y in pixels if y>=6}=={(x,y) for x in range(3,13) for y in (6,7)}, 'springboard base moves'
        assert {(x,depth) for x in range(1,15)}<=pixels, 'springboard cap breaks apart'
    assert t['pad_pat']==t['tramp_pat'][:16]*2 and t['pad_col']==t['tramp_col'][:16]*2
    assert t['spigot_pat'][8:12] == [0xff,0xff,0xfe,0x7e]
    assert t['spigot_pat'][12:16] == [0x7e]*4, 'slag valve mouth is narrower than the blob'
    assert t['spigot_col'][12:16] == [0x91]*4, 'slag valve outlet is not red'
    slag=re.search(r'^slag_bitmap:\n.*?(?=^\w+:)',source,re.M|re.S).group()
    first_frame=re.findall(r'BITMAP "([.X]{16})"',slag)[:16]
    blob_x={44+x for row in first_frame for x,pixel in enumerate(row) if pixel=='X'}
    mouth_x={48+x for x in range(8) if t['spigot_pat'][15] & (128>>x)}
    assert blob_x <= mouth_x, 'first goop ball extends outside the emitting mouth'
    assert len({tuple(t['belt_anim%d'%i]) for i in range(8)})==8
    sparks=t['spark_pat']
    assert len(sparks)==128 and len({tuple(sparks[i:i+16]) for i in range(0,128,16)})==8
    for frame in range(8):
        pixels={(tile*8+x,y) for tile in range(2) for y in range(8) for x in range(8)
                if sparks[frame*16+tile*8+y] & (128>>x)}
        assert {(0,y) for y in range(8)}<=pixels, 'spark wall detaches'
        assert any(x>=11 for x,y in pixels), 'spark stream disappears at belt end'
    crate=t['crate_pat']
    assert len(crate)==16 and all(crate[y]==crate[8+y] for y in range(8))
    assert crate[0]==crate[7]==crate[8]==crate[15]==0 and all(crate[y] for y in range(1,7)) and all(crate[y] for y in range(9,15)), 'crate is not a low jumpable obstacle'
    for name,fn in [('inclined',diagonal),('flat',flat)]:
        assert len({tuple(fn(i)) for i in range(8)})==8, name+' phases repeat'
    # Independent continuity property: both rails survive every phase.
    for phase in range(8):
        full=diagonal(phase)
        for x in range(8):
            assert full[4-x//2] & (128>>x)
            assert full[7-x//2] & (128>>x)
        assert flat(phase)[2]==flat(phase)[6]==255
    # Reject corruption, rather than merely checking the generator itself.
    broken=source.replace('belt_anim3:\n','belt_anim3:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken
    broken=source.replace('beamshift_pat:\n','beamshift_pat:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken
    broken=source.replace('tramp_pat:\n','tramp_pat:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken
    broken=source.replace('spark_pat:\n','spark_pat:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--write',action='store_true')
    args=p.parse_args()
    source=SOURCE.read_text(encoding='utf-8')
    if args.write:
        source=rewrite(source)
        with SOURCE.open('w',encoding='utf-8',newline='\n') as out:out.write(source)
    check(source)
    print('Conveyors: generated art matches; eight distinct phases, continuous rails, bad data rejected')
