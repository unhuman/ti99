"""Editable TMS9918 scenery and Mack art; character rows use at most two inks."""
from pathlib import Path
import re
import argparse

SOURCE = Path(__file__).resolve().parent.parent / 'src/HARDHAT.bas'


def canvas(w, h, color=1):
    return [[color]*w for _ in range(h)]


def rect(im, x0, y0, x1, y1, color):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1): im[y][x] = color


def encode(im):
    pat, col = [], []
    for ty in range(0, len(im), 8):
        for tx in range(0, len(im[0]), 8):
            for y in range(ty, ty+8):
                row = im[y][tx:tx+8]
                inks = sorted(set(row))
                assert len(inks)<=2, ('three inks in character row',tx,y,row)
                bg, fg = (inks[0], inks[-1]) if len(inks)==2 else (1,inks[0])
                pat.append(sum(128>>x for x,c in enumerate(row) if c==fg))
                col.append(fg*16+bg)
    return pat,col


def mack_poses():
    # Composite art: W = hat/skin/shoes, P = purple work clothes. Each pose
    # has the same forward-facing head and 12-pixel, bottom-anchored envelope.
    head=['................']*4+[
        '......WWWW......','.....WWWWWWW....',
        '.....PPWW.WW....','......PWWW......']
    return [head+body for body in (
        ['......PPPP......','.....PPPPPP.....','.....WPPPPPW....',
         '......PPPP......','......PPPP......','......PP.PP.....',
         '......PP.PP.....','.....WWW.WWW....'],
        ['......PPPP......','.....PPPPPPWW...','....WPPPPP......',
         '.....PPPPP......','.....PP.PPP.....','....PP...PP.....',
         '...PP.....PP....','..WWW.....WWW...'],
        ['......PPPP......','...WWPPPPPP.....','.....PPPPP.W....',
         '......PPPP......','....PPP.PP......','...PP...PP......',
         '..WW....PP......','........WWW.....'])]


def mack_layers():
    poses=mack_poses()
    assert all(len(row)==16 and set(row)<=set('.WP') for p in poses for row in p)
    def layer(p,ink):return [''.join('X' if c==ink else '.' for c in row) for row in p]
    right=[(layer(p,'W'),layer(p,'P')) for p in poses]
    left=[([r[::-1] for r in w],[r[::-1] for r in p]) for w,p in right]
    jump=poses[0][:7]+['.W....PWWW..W...']+[
        '.PP.PPPPPP.PP...','..PPPPPPPPPP....','.....PPPPPP.....',
        '....PPPPPPPP....','...PPP....PPP...','..PPP......PPP..',
        '..WW........WW..','................']
    jumpwhite,jumppurple=layer(jump,'W'),layer(jump,'P')
    return dict(mack_bitmap=right[0][0],mackw_bitmap=right[1][0],
                mackl_bitmap=left[0][0],mackl2_bitmap=left[1][0],
                mackj_bitmap=jumpwhite,
                mack_jump_left=[r[::-1] for r in jumpwhite]+[r[::-1] for r in jumppurple],
                mack_colour=right[0][1]+right[1][1]+left[0][1]+left[1][1]+jumppurple,
                mack_run_extra=right[2][0]+right[2][1]+left[2][0]+left[2][1])


def tables():
    out=mack_layers()
    # Fixed upper-right rivet launcher. The white feed cap, magenta housing,
    # and green inspection window match the small in-game reference; the
    # 16x16 image is split into four TMS9918 characters for two-ink rows.
    launcher=canvas(16,16)
    rect(launcher,7,0,8,1,15);rect(launcher,6,2,9,2,15)
    rect(launcher,5,3,10,3,15)
    rect(launcher,2,4,13,4,15)
    rect(launcher,1,5,14,12,15)
    rect(launcher,2,5,13,12,13)
    rect(launcher,0,5,0,12,15);rect(launcher,15,5,15,6,15)
    rect(launcher,15,12,15,12,15)
    rect(launcher,14,7,15,11,13)
    rect(launcher,0,7,3,9,15)
    rect(launcher,1,7,3,8,13)
    # Inspection window is set into the right half, replacing its magenta
    # face locally so every scanline keeps the VDP's two-ink limit.
    rect(launcher,10,7,13,11,10)
    rect(launcher,9,6,14,6,15);rect(launcher,9,12,14,12,15)
    rect(launcher,2,13,13,13,15)
    out['thrower_pat'],out['thrower_col']=encode(launcher)
    # One continuous pedestal: bearing plate, narrow stem, broad footing.
    # The former repeated eight-pixel foot produced two stacked cones.
    support=canvas(8,16)
    rect(support,1,0,6,1,15)
    rect(support,2,2,5,2,15)
    rect(support,3,3,4,10,15)
    rect(support,3,3,4,3,13);rect(support,3,10,4,10,13)
    rect(support,2,11,5,12,15);rect(support,1,13,6,13,15)
    rect(support,0,14,7,15,15)
    out['support_pat'],out['support_col']=encode(support)
    # Apple II reference: paired fasteners separated by plain lengths of beam.
    # Masks are screen-column anchored, so gaps never restart the decoration.
    out['girder_marks']=[]
    for columns in ((4,5,11,12,17,18,24,25),
                    (3,4,8,9,12,13,15,16,19,20,24,25),
                    (3,4,8,9,13,14,18,19,23,24,27,28)):
        out['girder_marks'] += [int(c in columns) for c in range(32)]
    out['girder_dot_pat']=([255,255,255,231,231,255,255,0]+
                          [255,255,255,231,231,255,255,255]*2)
    out['girder_dot_col']=([0x61,0x41,0x41,0x41,0x41,0x41,0x61,0x11]+
                          [0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41]+
                          [0xa1,0xa1,0x51,0x51,0x51,0x51,0xa1,0xa1])
    out['beamplain_pat']=[]
    for lower in (False,True):
        for offset in range(8):
            shifted=[0]*offset+[255]*8+[0]*(8-offset)
            out['beamplain_pat'] += shifted[8:] if lower else shifted[:8]
    # Site-two ground hazard: a red dynamite stick under a flickering fuse.
    # Keep the original site-three grinder in character 164; character 165
    # starts the fuse cycle, 166 is the stick, and 169-171 are fuse variants.
    sparks=(((4,0),(3,1),(4,1),(5,1),(2,2),(4,2),(6,2)),
            ((5,0),(4,1),(5,1),(6,1),(5,2),(6,2)),
            ((3,1),(2,2),(3,2),(4,2),(3,0)),
            ((4,0),(4,1),(3,2),(4,2),(5,2)))
    fuse_frames=[]
    for phase,points in enumerate(sparks):
        fuse=canvas(8,8)
        for y in range(3,8):fuse[y][4]=15
        for x,y in points:fuse[y][x]=(15,11,9,11)[phase]
        fuse_frames.append(encode(fuse))
    stick=canvas(8,8)
    rect(stick,2,0,5,0,15)
    rect(stick,1,1,6,3,9)
    rect(stick,1,4,6,4,15)
    rect(stick,1,5,6,6,9)
    rect(stick,2,7,5,7,15)
    stick_pat,stick_col=encode(stick)
    out['haz_pat']=[0x99,0x5A,0x3C,0xFF,0xFF,0x3C,0x5A,0x99]+fuse_frames[0][0]+stick_pat
    out['haz_col']=[0x91,0x91,0xE1,0xE1,0xE1,0xE1,0x91,0x91]+fuse_frames[0][1]+stick_col
    out['fuse_pat']=sum((frame[0] for frame in fuse_frames[1:]),[])
    out['fuse_col']=sum((frame[1] for frame in fuse_frames[1:]),[])
    # Site-two receiver: open black mouth, white rounded body/side outlet,
    # magenta mounting collar and green foot, as in the Apple II longplay.
    receiver=canvas(16,16)
    rect(receiver,3,0,10,0,15)
    rect(receiver,2,1,11,1,15);rect(receiver,1,2,12,9,15)
    rect(receiver,2,10,11,11,15);rect(receiver,3,1,10,5,1)
    rect(receiver,2,6,2,9,1)
    rect(receiver,12,7,15,7,15);rect(receiver,14,8,15,9,15)
    rect(receiver,11,10,14,10,15)
    rect(receiver,3,12,10,12,13);rect(receiver,4,13,9,13,13)
    rect(receiver,1,14,12,15,3)
    out['mixer_pat'],out['mixer_col']=encode(receiver[:8])
    out['mixb_pat'],out['mixb_col']=encode(receiver[8:])
    # Blue cabinet, white perimeter, a gridded window and framed red door.
    cabinet=canvas(32,32,4)
    rect(cabinet,0,0,31,0,15);rect(cabinet,0,31,31,31,15)
    rect(cabinet,0,0,0,31,15);rect(cabinet,31,0,31,31,15)
    rect(cabinet,8,3,23,10,15);rect(cabinet,9,4,22,9,4)
    for x in (12,16,20):rect(cabinet,x,4,x,9,15)
    rect(cabinet,9,7,22,7,15)
    rect(cabinet,8,13,23,29,15);rect(cabinet,9,14,22,28,6)
    rect(cabinet,20,20,21,21,15)
    bucket=canvas(16,8)
    # Single broad bucket: white rim, magenta walls, open dark interior.
    rect(bucket,1,0,14,0,15);rect(bucket,0,1,0,5,15);rect(bucket,15,1,15,5,15)
    rect(bucket,1,2,1,5,15);rect(bucket,14,2,14,5,15)
    rect(bucket,2,2,13,5,13);rect(bucket,1,6,14,6,15);rect(bucket,2,7,13,7,13)
    # Keep the outside portions black; edge scanlines have white/black only.
    for y in range(2,6):
        bucket[y]=[15,15]+[13]*12+[15,15]
    # Counterclockwise spokes follow the left-down/right-up chain travel.
    wheels=[]
    for dx,dy in ((0,-5),(-4,-4),(-5,0),(-4,4),(0,5),(4,4),(5,0),(4,-4)):
        axle=canvas(16,16)
        for y in range(16):
            for x in range(16):
                radius=(2*x-15)**2+(2*y-15)**2
                if 121<=radius<=196:axle[y][x]=13 if y in (1,14) else 15
        rect(axle,7,7,8,8,15)
        for step in range(1,6):
            x=round(7.5+dx*step/5);y=round(7.5+dy*step/5)
            axle[y][x]=15
        wheels.append(axle)
    axle=wheels[0]
    assert all(encode(im)[1]==encode(axle)[1] for im in wheels), 'wheel animation changes its fixed palette'
    out['wheel_anim_pat']=sum((encode(im)[0] for im in wheels),[])
    out['drivechain_pat']=[];out['drivechain_col']=[]
    link=[0x30,0x78,0x48,0x48,0x48,0x78,0x30,0x30]
    for phase in range(8):
        for direction in (1,-1):
            for y in range(8):
                row=(y-direction*phase)%8
                out['drivechain_pat'].append(link[row] if direction==1 else link[row]>>2)
                out['drivechain_col'].append(0xf1 if row==1 else 0x31)
    out['pn_pat']=out['drivechain_pat'][:16]
    out['pn_col']=out['drivechain_col'][:16]
    # Twelve-pixel lunch pail, occupying two character rows. Bottom remains
    # at the original floor so its enlargement cannot eat the supporting beam.
    pail=canvas(16,16)
    rect(pail,6,4,9,4,15);rect(pail,6,5,6,6,15);rect(pail,9,5,9,6,15)
    # Domed shoulders and white lid over two red panels, divided by a white
    # fastening strap. This is a lunch pail rather than a plain suitcase.
    rect(pail,4,7,11,7,15);rect(pail,2,8,13,8,15);rect(pail,0,9,15,15,15)
    rect(pail,7,9,8,10,6)
    rect(pail,2,11,5,14,6);rect(pail,8,11,13,14,6)
    rect(pail,10,11,11,11,15)
    rect(pail,0,15,15,15,15)
    label=canvas(16,16)
    letters=('111001001','010001101','010001011','010001001','111001001')
    for y,row in enumerate(letters):
        for x,c in enumerate(row,7):
            if c=='1':label[y][x]=15
    # Label cells start eight pixels after each 40-pixel processor's left
    # edge. Center the arrow at local x=11.5, over the feed at x=19.5.
    rect(label,11,7,12,10,15)
    for y,lo,hi in ((10,8,15),(11,9,14),(12,10,13),(13,11,12)):rect(label,lo,y,hi,y,15)
    # 96-111 cabinet, 112-113 bucket, 114-117 axle, 118-119 pail top,
    # 120-123 reserved for site-specific art, 124-127 IN and down-arrow.
    parts=[cabinet,bucket,axle,pail[:8],canvas(16,16),label]
    out['fixture_pat']=[];out['fixture_col']=[]
    for im in parts:
        p,c=encode(im);out['fixture_pat']+=p;out['fixture_col']+=c
    out['pail_pat'],out['pail_col']=encode(pail[8:])
    out['inflash_pat']=encode(label)[0]+[0]*32
    # Restore the title credit's three lowercase glyphs after scenery used
    # their codes. These are the compiler font's original a/d/n patterns.
    out['credit_pat']=[0,0,0x68,0x98,0x88,0x98,0x68,0,
                      8,8,0x68,0x98,0x88,0x98,0x68,0,
                      0,0,0xb0,0xc8,0x88,0x88,0x88,0]
    out['credit_col']=[0xf1]*8
    # User's Apple II screenshot: low outlined housing, dark blue centre,
    # red side panels, white feed cap and angled oval shoulder outlets.
    nozzle_rows=(
        '........','........','..WW....','..WWW...',
        '.W...W..','.W....W.','W......W','W.....W.',
        '.W...W..','..WWW...','..WW....','...WW...',
        '....WW..','.....WW.','......WW','WWWWWWWW')
    nozzle=[[15 if c=='W' else 1 for c in row] for row in nozzle_rows]
    machine=canvas(40,16)
    rect(machine,12,0,27,0,15);rect(machine,16,1,23,1,15)
    rect(machine,17,2,22,2,15);rect(machine,18,3,21,3,15)
    rect(machine,16,4,23,4,4)
    rect(machine,12,5,27,5,15);rect(machine,8,6,31,6,15)
    # Fine dark shading approximates the reference's subdued interior;
    # each character row still contains only its panel ink and black.
    for y in range(7,15):
        for x in range(8,32):
            machine[y][x]=(4 if 16<=x<24 else 6) if (x+y)%2 else 1
    rect(machine,0,15,39,15,15)
    for y in range(16):
        machine[y][:8]=nozzle[y][::-1]
        machine[y][32:]=nozzle[y]
    out['machine_art'],out['machine_col']=encode(machine)
    # The active inward corners retain their site-specific upper characters;
    # their lower halves are now integrated into the common housing artwork.
    outlets=[row+row[::-1] for row in nozzle[:8]]
    out['eject_pat'],out['eject_col']=encode(outlets)
    # Block fill/outline layers share the exact eight-by-eight silhouette.
    for name,outline in (('brick_bitmap',False),('brick_edge',True)):
        out[name]=[''.join('X' if (4<=x<12 and 4<=y<12 and
                     ((x in (4,11) or y in (4,11))==outline)) else '.'
                     for x in range(16)) for y in range(16)]
    return out


def rewrite(source):
    for label,data in tables().items():
        if isinstance(data[0],str):
            body=''.join('\tBITMAP "'+r+'"\n' for r in data)
        else:
            body=''.join('\tDATA BYTE '+','.join('$%02X'%v for v in data[i:i+8])+'\n'
                         for i in range(0,len(data),8))
        body=label+":\n\t' Generated by assets/genfixtures.py; edit the generator.\n"+body
        source,n=re.subn(r'^'+label+r':\n.*?(?=^\w+:)',lambda m:body,source,flags=re.M|re.S)
        assert n==1, 'missing/duplicate '+label
    # Shared block and riveted/ordinary girder appearances, from one definition.
    for label in ('tile_pat','tile_col','item_pat','item_col','beamshift_col'):
        m=re.search(r'^'+label+r':\n.*?(?=^\w+:)',source,re.M|re.S)
        lines=[line.split("'")[0] for line in m[0].splitlines()]
        data=[int(v[1:],16) for v in re.findall(r'\$[0-9A-F]{2}','\n'.join(lines))]
        if label=='tile_pat':
            data[:40]=([255]*7+[0]+[255]*16+
                       [255,129,129,129,129,129,129,255]+[255]*7+[0])
        elif label=='tile_col':
            data[8:16]=[0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41]
            data[24:32]=[0xf1]+[0xf6]*6+[0xf1]
            data[32:40]=data[:8]
        elif label=='item_pat':data[:8]=[255,129,129,129,129,129,129,255]
        elif label=='item_col':data[:8]=[0xf1]+[0xf6]*6+[0xf1]
        else:
            beam=[0x41,0x31,0x31,0x34,0x34,0x31,0x31,0x41];data=[]
            for lower in (False,True):
                for offset in range(8):
                    shifted=[0x11]*offset+beam+[0x11]*(8-offset)
                    data+=shifted[8:] if lower else shifted[:8]
        body=label+":\n\t' Generated by assets/genfixtures.py (spring halves also genconveyors.py).\n"
        for i in range(0,len(data),8):
            if label in ('tile_pat','tile_col') and i==72:
                body+="\t' 137/138 springboard idle halves; generated by assets/genconveyors.py.\n"
            body+='\tDATA BYTE '+','.join('$%02X'%v for v in data[i:i+8])+'\n'
        source=source[:m.start()]+body+source[m.end():]
    return source


def check(source):
    assert rewrite(source)==source,'fixture art stale; run genfixtures.py --write'
    assert len(tables()['fixture_pat'])==32*8
    tp,tc=tables()['thrower_pat'],tables()['thrower_col']
    assert len(tp)==len(tc)==32 and 0xFD in tc and 0xDA in tc and 0xF1 in tc
    # Validate the three materials remain visible in their intended regions.
    def thrower_ink(x,y):
        i=((y//8)*2+x//8)*8+y%8
        return tc[i]//16 if tp[i] & (128>>(x%8)) else tc[i]%16
    assert thrower_ink(7,0)==15 and thrower_ink(3,6)==13 and thrower_ink(11,8)==10
    broken=source.replace('machine_art:\n','machine_art:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken,'corrupt fixture table accepted'
    poses=mack_poses()
    for p in poses:
        assert all(row=='.'*16 for row in p[:4]), 'Mack exceeds his 12-pixel height'
        assert 'W' in p[15], 'Mack loses floor contact'
        assert p[4:8]==poses[0][4:8], 'run pose changes facing/head position'
    # Three distinct drawings; the four-beat cycle deliberately reuses the
    # neutral/passing pose between opposite strides, not mirrored body poses.
    for i in range(3):
        for j in range(i):
            diff=sum(a!=b for ra,rb in zip(poses[i],poses[j]) for a,b in zip(ra,rb))
            assert diff>=20, ('Mack run poses too similar',i,j,diff)
    broken=source.replace('mack_run_extra:\n','mack_run_extra:\n\tBITMAP "XXXXXXXXXXXXXXXX"\n',1)
    assert rewrite(broken)!=broken, 'corrupt Mack animation accepted'
    p,c=tables()['pail_pat'],tables()['pail_col']
    def ink(x,y):
        index=(x//8)*8+y
        return c[index]//16 if p[index] & (128>>(x%8)) else c[index]%16
    assert all(ink(x,y)==15 for x in (6,7) for y in range(3,7)), 'pail loses white center strap'
    assert all(ink(x,5)==6 for x in (2,3,4,5,8,9,10,11,12,13)), 'pail loses its two red panels'
    broken=source.replace('pail_pat:\n','pail_pat:\n\tDATA BYTE 0\n',1)
    assert rewrite(broken)!=broken,'corrupt pail table accepted'
    data=tables()
    def white_pixels(pattern,colors,width,y):
        found=[]
        for x in range(width):
            i=((y//8)*(width//8)+x//8)*8+y%8
            ink=colors[i]//16 if pattern[i] & (128>>(x%8)) else colors[i]%16
            if ink==15:found.append(x)
        return found
    # Compare the drawn arrow/lettering to the actual feed cap, including
    # their different map origins. A centered glyph in its own tile is wrong.
    cap=white_pixels(data['machine_art'],data['machine_col'],40,0)
    center=(min(cap)+max(cap))/2
    labelp=data['inflash_pat'][:32];labelc=data['fixture_col'][28*8:32*8]
    for y in (7,10,11,12,13):
        arrow=white_pixels(labelp,labelc,16,y)
        assert 8+(min(arrow)+max(arrow))/2==center, 'IN arrow misses processor center'
    letters=sum((white_pixels(labelp,labelc,16,y) for y in range(5)),[])
    assert abs(8+(min(letters)+max(letters))/2-center)<=0.5, 'IN lettering is off center'


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--write',action='store_true')
    args=parser.parse_args();source=SOURCE.read_text(encoding='utf-8')
    if args.write:
        source=rewrite(source);SOURCE.write_bytes(source.encode('utf-8'))
    check(source)
    print('Fixtures: two-ink rows, shared blocks/girders and generated data verified')
