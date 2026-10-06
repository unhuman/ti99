"""Structural gates plus executable rescue-state regression tests.

The small interpreter executes selected routines directly from the game source.
Unknown statements fail, so tests cannot silently turn into a separate model.
"""
from pathlib import Path
import re
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'assets'))
SOURCE=(ROOT/'src/CHOPLIFT.bas').read_text(encoding='utf-8')

def structure(source):
    for line in source.splitlines():
        code=line.split("'")[0]
        for m in re.finditer(r'PRINT AT (\d+),"([^"]*)"',code):
            offset=int(m[1])
            if offset//32 >= 24 or offset%32+len(m[2]) > 32:
                raise ValueError('Text crosses screen edge: '+line)
        if re.search(r'\bIF\b.*[<>=].*\b(?:AND|OR)\b.*[<>=]',code,re.I):
            raise ValueError('Unsafe compound comparison: '+line)
    if 'DIM camp_left(4)' not in source: raise ValueError('Missing four-camp array')
    if 'DIM #shot_x(2)' not in source: raise ValueError('Missing two-shot pool')
    hud=source.split('\nhud:\n',1)[1].split('\ndigits:\n',1)[0]
    template=re.search(r'PRINT AT 0,"([^"]+)"',source)[1]
    fields=[int(x)-6144 for x in re.findall(r'#digit_pos=(\d+)',hud)]
    if fields != [m.start() for m in re.finditer('00',template)]:
        raise ValueError('HUD digits must replace the three 00 placeholders')

class Basic:
    """Strict subset used by accounting routines; CVBasic byte/word wrapping."""
    def __init__(self, source=SOURCE, target='TI994A'):
        self.v={}; self.a={}; self.r={}; self.vram={}; self.sprites={};self.patterns={};self.sprite_patterns={}
        self.sounds={};self.sound_writes=[]
        self.calls={};self.transfers=[];self.events=[]
        self.v.update({name.lower():int(value) for name,value in
                       re.findall(r'^CONST (\w+) = (\d+)$',source,re.M)})
        lines=source.splitlines()
        name=None
        enabled=True
        for line in lines:
            if line.startswith('#if '): enabled=line[4:]==target;continue
            if line=='#else':enabled=not enabled;continue
            if line=='#endif':enabled=True;continue
            if not enabled:continue
            m=re.match(r'^(\w+):\s*$',line)
            if m: name=m[1]; self.r[name]=[]
            elif name:
                code=line.split("'")[0].strip()
                if code:self.r[name].append(code)
    def expr(self,s):
        s=s.strip()
        s=re.sub(r'\bAND\b','&',s,flags=re.I)
        s=re.sub(r'\bXOR\b','^',s,flags=re.I)
        s=re.sub(r'\bOR\b','|',s,flags=re.I)
        s=re.sub(r'(#?[a-z_]\w*)\(([^()]+)\)',lambda m:str(self.element(m[1],self.expr(m[2]))),s,flags=re.I)
        s=re.sub(r'#?[a-z_]\w*(?:\.\w+)?',lambda m:str(self.v.get(m[0].lower(),0)),s,flags=re.I)
        s=s.replace('<>','!=')
        s=s.replace('/','//')
        s=re.sub(r'(?<![<>=!])=(?!=)','==',s)
        if not re.fullmatch(r'[\d\s+*/%<>=!()&|^\-]+',s):raise ValueError('Expression '+s)
        return int(eval(s,{'__builtins__':{}},{}))
    def element(self,name,index):
        # CVBasic reads a plain name(i) as BYTES; only #name(i) reads words.
        # A word table reached without '#' compiles to a byte read of the
        # wrong address, so the model must refuse it rather than hand back
        # the Python list's word.
        value=self.a[name][index]
        if not name.startswith('#') and not 0<=value<=255:
            raise ValueError(f'byte read {name}({index}) of word value {value}')
        return value
    def call(self,name):
        self.events.append(('call',name))
        self.calls[name]=self.calls.get(name,0)+1
        self.execute(self.r[name])
    def execute(self,lines):
        pc=0
        while pc<len(lines):
            line=lines[pc];pc+=1
            if line.startswith('ASM '):
                block=[line[4:]]
                while pc<len(lines) and lines[pc].startswith('ASM '):
                    block.append(lines[pc][4:]);pc+=1
                self.native(block)
            elif line.startswith('IF '):
                cond,tail=line[3:].split(' THEN',1)
                if tail.strip():
                    halves=tail.strip().split(' ELSE ',1)
                    chosen=halves[0] if self.expr(cond) else (halves[1] if len(halves)>1 else '')
                    if chosen:
                        flow=self.statements(chosen)
                        if flow:return flow
                else:
                    depth=1; start=pc; mid=None
                    while pc<len(lines):
                        if re.match(r'IF .* THEN$',lines[pc]):depth+=1
                        if lines[pc]=='END IF':depth-=1
                        if lines[pc]=='ELSE' and depth==1:mid=pc
                        if depth==0:break
                        pc+=1
                    if depth:raise ValueError('Unterminated IF')
                    yes=lines[start:mid if mid is not None else pc]
                    no=lines[mid+1:pc] if mid is not None else []
                    flow=self.execute(yes if self.expr(cond) else no)
                    if flow:return flow
                    pc+=1
            elif line.startswith('FOR '):
                m=re.fullmatch(r'FOR (\w+)=(.+) TO (.+)',line)
                if not m:raise ValueError(line)
                start=pc;depth=1
                while pc<len(lines):
                    if lines[pc].startswith('FOR '):depth+=1
                    if lines[pc].startswith('NEXT '):depth-=1
                    if depth==0:break
                    pc+=1
                if pc==len(lines):raise ValueError('Missing NEXT')
                for n in range(self.expr(m[2]),self.expr(m[3])+1):
                    self.v[m[1]]=n
                    result=self.execute(lines[start:pc])
                    if result=='exit':break
                    if result:return result
                pc+=1
            else:
                flow=self.statements(line)
                if flow:return flow
        return False
    def native(self,lines):
        """Execute the actual TI kernels, rejecting unknown opcodes. DIM arrays
        are array_NAME and DATA tables cvb_NAME, as in the generated assembly;
        a word table is #NAME -> _NAME. Writes outside every array are errors."""
        regs=[0]*16;memory={};bases={};ptr=0x4000;layout=[]
        dims=set(re.findall(r'^DIM (#?\w+)\(',SOURCE,re.M))
        for name,data in self.a.items():
            bases[('array_' if name in dims else 'cvb_')+name.replace('#','_')]=ptr
            layout.append((name,ptr))
            if name.startswith('#'):data=[v for word in data for v in (word>>8,word&255)]
            for i,v in enumerate(data):memory[ptr+i]=v
            ptr=(ptr+len(data)+3)&~1
        def store(addr,value,byte):
            for a,v in ((addr,value),) if byte else ((addr,value>>8),(addr+1,value&255)):
                if a not in memory:raise ValueError(f'native write outside arrays at {a:#x}')
                memory[a]=v
        def variable(dest,value):
            name=dest[5:];name='#'+name[1:] if name.startswith('_') else name
            self.v[name]=value
        labels={s[:-1].lower():i for i,s in enumerate(lines) if s.endswith(':')}
        # VDP ports: two address bytes (low, then high with >40 for writing),
        # then auto-incrementing data. Port writes need interrupts held off,
        # or the vblank handler can move the address between the two halves.
        vdp={'latch':[],'addr':None,'ints':True}
        def port(dest,value):
            if vdp['ints']:raise ValueError('VDP port written with interrupts enabled')
            if dest=='@vdpwadr':
                vdp['latch'].append(value)
                if len(vdp['latch'])==2:
                    low,high=vdp['latch'];vdp['latch']=[]
                    if not high&0x40:raise ValueError('VDP address set for reading')
                    vdp['addr']=((high&0x3f)<<8)|low
            elif dest=='@vdpwdata':
                if vdp['latch'] or vdp['addr'] is None:raise ValueError('VDP data before a full address')
                self.transfers.append((vdp['addr'],1));self.vram[vdp['addr']]=value
                vdp['addr']+=1
            else:raise ValueError('Unsupported native destination: '+dest)
        def operand(s,byte=False):
            if s.startswith('@cvb_'):
                name=s[5:];name='#'+name[1:] if name.startswith('_') else name
                return self.v.get(name,0)  # CVBasic variables start at zero
            if s.startswith('*r'):
                reg=int(s[2:].rstrip('+'));addr=regs[reg]
                if s.endswith('+'):regs[reg]+=1 if byte else 2
                return memory[addr] if byte else memory[addr]*256+memory[addr+1]
            if re.fullmatch('r[0-9]+',s):return regs[int(s[1:])] >> (8 if byte else 0)
            return bases[s] if s in bases else int(s)
        pc=0;zero=False;steps=0;compare=0
        while pc<len(lines):
            steps+=1
            if steps>40000:raise ValueError('Native loop runaway')
            line=lines[pc].lower();pc+=1
            if line.endswith(':'):continue
            op,args=line.split(None,1);parts=args.split(',')
            if op=='mov' and not re.fullmatch('r[0-9]+',parts[1]):
                value=operand(parts[0]);dest=parts[1]
                if dest.startswith('@cvb_'):variable(dest,value)
                elif dest.startswith('*r'):
                    reg=int(dest[2:].rstrip('+'));store(regs[reg],value,False)
                    if dest.endswith('+'):regs[reg]+=2
                else:raise ValueError('Unsupported native destination: '+dest)
                compare=value;zero=value==0
            elif op=='div':
                src=operand(parts[0]);reg=int(parts[1][1:])
                if src>regs[reg]:  # otherwise the TMS9900 sets overflow and leaves both
                    dividend=(regs[reg]<<16)|regs[reg+1]
                    regs[reg],regs[reg+1]=dividend//src,dividend%src
            elif op in ('mov','li','ai','a','s','srl','sla','andi','ori'):
                reg=int(parts[1][1:]) if op=='mov' else int(parts[0][1:])
                if op=='ai':regs[reg]+=operand(parts[1])
                elif op=='li':regs[reg]=operand(parts[1])
                elif op in ('a','s'):
                    reg=int(parts[1][1:]);regs[reg]+=operand(parts[0])*(1 if op=='a' else -1)
                elif op=='srl':regs[reg]>>=operand(parts[1])
                elif op=='sla':regs[reg]<<=operand(parts[1])
                elif op=='andi':regs[reg]&=operand(parts[1])
                elif op=='ori':regs[reg]|=operand(parts[1])
                else:regs[reg]=operand(parts[0])
                regs[reg]&=65535
                # Like the TMS9900, these compare their result with zero.
                compare=regs[reg];zero=compare==0
            elif op in ('neg','swpb'):
                reg=int(args[1:]);value=regs[reg]
                regs[reg]=(-value)&65535 if op=='neg' else ((value&255)<<8)|(value>>8)
                if op=='neg':compare=regs[reg];zero=compare==0
            elif op=='limi':vdp['ints']=operand(args)!=0
            elif op=='c':
                compare=operand(parts[0])-operand(parts[1]);zero=compare==0
            elif op=='jeq':
                if zero:pc=labels[args]
            elif op=='jmp':pc=labels[args]
            elif op=='bl':
                # Local subroutine: the TMS9900 keeps the return address in R11.
                if not args.startswith('@'):raise ValueError('Unsupported bl: '+line)
                regs[11]=pc;pc=labels[args[1:]]
            elif op=='b':
                if args!='*r11':raise ValueError('Unsupported branch: '+line)
                pc=regs[11]
            elif op=='movb' and parts[1].startswith('@cvb_'):
                value=operand(parts[0],True);variable(parts[1],value);compare=value;zero=value==0
            elif op=='movb' and parts[1].startswith('@'):port(parts[1],operand(parts[0],True))
            elif op in ('movb','socb'):
                value=operand(parts[0],True);dest=parts[1]
                if dest.startswith('*r'):
                    reg=int(dest[2:].rstrip('+'));addr=regs[reg]
                    if addr not in memory:raise ValueError(f'native write outside arrays at {addr:#x}')
                    memory[addr]=(memory[addr]|value) if op=='socb' else value
                    if dest.endswith('+'):regs[reg]+=1
                    value=memory[addr]
                else:
                    # A byte move replaces only the register's high byte.
                    reg=int(dest[1:]);regs[reg]=(value<<8)|(regs[reg]&255)
                compare=value;zero=value==0
            elif op in ('dec','inc','clr'):
                reg=int(args[1:]);regs[reg]=(0 if op=='clr' else regs[reg]+(-1 if op=='dec' else 1))&65535
                zero=regs[reg]==0
            elif op in ('ci','cb'):
                compare=operand(parts[0],op=='cb')-operand(parts[1],op=='cb')
                zero=compare==0
            elif op in ('jne','jhe','jl','jle','jh'):
                taken={'jne':not zero,'jhe':compare>=0,'jl':compare<0,'jle':compare<=0,'jh':compare>0}[op]
                if taken:pc=labels[args]
            else:raise ValueError('Unsupported native instruction: '+line)
        for name,base in layout:
            if name.startswith('#'):
                self.a[name]=[memory[base+2*i]*256+memory[base+2*i+1] for i in range(len(self.a[name]))]
            else:
                self.a[name]=[memory[base+i] for i in range(len(self.a[name]))]
    def statements(self,line):
        for part in line.split(':'):
            part=part.strip()
            if not part:continue
            if part=='WAIT':self.events.append(('wait',));continue
            if part=='CLS':
                self.transfers.append((6144,768))
                for a in range(6144,6912):self.vram[a]=32
                continue
            if part.startswith('PRINT AT '):
                m=re.fullmatch(r'PRINT AT ([^,]+),"([^"]*)"',part)
                if not m:raise ValueError('Unsupported PRINT: '+part)
                pos=6144+self.expr(m[1]);self.transfers.append((pos,len(m[2])))
                for i,ch in enumerate(m[2]):self.vram[pos+i]=ord(ch)
                continue
            if part=='RETURN':return 'return'
            if part=='EXIT FOR':return 'exit'
            if part.startswith('GOSUB '):self.call(part[6:]);continue
            if part.startswith('SOUND '):
                ch,pitch,volume=[self.expr(x) for x in part[6:].split(',')]
                if not 0<=ch<=3 or not 0<=volume<=15:raise ValueError('Invalid SOUND '+part)
                if not 0<=pitch<=(7 if ch==3 else 1023):raise ValueError('Invalid divisor '+part)
                self.sounds[ch]=(pitch,volume);self.sound_writes.append((ch,pitch,volume))
                continue
            if part.startswith('DEFINE VRAM '):
                addr,count,origin=part[12:].split(',',2)
                addr,count=self.expr(addr),self.expr(count)
                m=re.fullmatch(r'VARPTR (\w+)\((.*)\)',origin)
                if m:
                    offset=self.expr(m[2]);data=self.a[m[1]][offset:offset+count]
                else:data=self.a[origin][:count]
                if len(data)!=count:raise ValueError('Short VRAM source')
                self.transfers.append((addr,count))
                for i,value in enumerate(data):
                    self.vram[addr+i]=value
                    if 4096<=addr+i<6144:
                        tile=(addr+i-4096)//8
                        self.patterns.setdefault(tile,[0]*8)[(addr+i)%8]=value
                continue
            if part.startswith('DEFINE CHAR '):
                start,count,label=part[12:].split(',')
                start,count=self.expr(start),self.expr(count)
                data=self.a[label]
                for i in range(count):self.patterns[start+i]=data[i*8:i*8+8]
                continue
            if part.startswith('DEFINE SPRITE '):
                start,count,label=part[14:].split(',')
                start,count=self.expr(start),self.expr(count)
                data=self.a[label]
                if len(data)!=count*32:raise ValueError('Invalid sprite-pattern upload')
                for i in range(count):self.sprite_patterns[start+i]=data[i*32:i*32+32]
                continue
            if part.startswith('SCREEN '):
                label,*args=part[7:].split(',')
                values=[self.expr(x) for x in args]
                offset,dest,width,height=values[:4]
                # TMS backends reduce SCREEN width, height and source stride to bytes.
                width,height=width&255,height&255
                stride=(values[4]&255) if len(values)==5 else width
                self.events.append(('screen',label,offset,dest,width,height,stride))
                for row in range(height):
                    self.transfers.append((6144+dest+row*32,width))
                    for col in range(width):
                        self.vram[6144+dest+row*32+col]=self.a[label][offset+row*stride+col]
                continue
            if part.startswith('SPRITE '):
                slot,*data=[self.expr(x) for x in part[7:].split(',')]
                self.sprites[slot]=data
                continue
            if part.startswith('VPOKE '):
                addr,value=part[6:].split(',')
                self.transfers.append((self.expr(addr),1))
                self.vram[self.expr(addr)]=self.expr(value)
                continue
            if part.startswith('IF '):
                flow=self.execute([part])
                if flow:return flow
                continue
            m=re.fullmatch(r'(#?\w+)(?:\((.+)\))?=(.+)',part)
            if not m:raise ValueError('Unsupported statement: '+part)
            value=self.expr(m[3]) & (65535 if m[1].startswith('#') else 255)
            if m[2] is not None:self.a[m[1]][self.expr(m[2])]=value
            else:self.v[m[1].lower()]=value
        return False

class Tests(unittest.TestCase):
    def state(self):
        b=Basic();b.v.update(saved=0,lost=0,aboard=0,lives=3,dt=2,hy=b.v['landed'],old_y=b.v['landed'])
        b.a['camp_left']=[16]*4;b.a['camp_open']=[1]*4;b.a['#camp_x']=[128,384,640,896]
        b.a['camp_released']=[16]*4;b.a['camp_escape']=[0]*4;b.a['camp_active']=[0]*4
        b.a['person_state']=[0]*64;b.a['#person_x']=[0]*64;b.a['crowd_cells']=[0]*32
        b.a['person_state'][0]=3
        b.a['crowd_pixels']=[0]*256
        for name in ('#shot_x','shot_y','shot_dir','shot_on','shot_ttl','shot_slope','shot_speed','shot_drift'):b.a[name]=[0,0]
        sys.path.insert(0,str(ROOT/'assets'))
        import generate
        b.a['jet_arc']=generate.JET_ARC
        b.a['crash_flames']=[v for a in generate.SPRITES[13:15] for v in generate.sprite_bytes(a)]
        b.a['crash_embers']=[v for rows in generate.CRASH_EMBERS for v in generate.sprite_bytes(generate.fire_sprite(rows))]
        b.a['world_map']=[c for row in generate.MAP for c in row]
        b.a['fire_frame0']=generate.FIRE0;b.a['fire_frame1']=generate.FIRE1
        rows=generate.PERSON_ROWS
        b.a['person_rows']=rows+[v>>4 for v in rows]+[(v<<4)&255 for v in rows]
        b.a['person_colors']=generate.PERSON_COLORS
        b.a['crowd_bases']=[0]*8+[255-v for v in generate.TILES[5][0]]+generate.TILES[28][0]+generate.TILES[29][0]
        standing=[v for k in range(3) for v in generate.PERSON_ROWS[k*64:k*64+32]]*2
        for ch in range(24):b.patterns[ch+96]=standing[ch*8:ch*8+8]
        b.a['menu_font']=generate.MENU_FONT;b.a['camp_bits']=[1,2,4,8]
        b.a['person_kind']=[i%3 for i in range(64)];b.a['waiting_kind']=[96+(i%3)*4 for i in range(64)]
        b.a['tile_art']=[v for bits,_ in generate.TILES for v in bits]
        b.a['star_x']=generate.STAR_X;b.a['star_row']=generate.STAR_ROW+[0,0]
        # Every DATA table written in the game source itself (not assets.bas).
        for label,body in re.findall(r'^(#?\w+):\n((?:DATA(?: BYTE)? [\d,]+\n)+)',SOURCE,re.M):
            b.a[label]=[int(v) for line in body.splitlines() for v in line.split(' ',2)[-1].split(',')]
        b.a['ground_row']=[129]*32
        b.a['fence_codes']=generate.FENCE_CODES
        b.a['home_fence_codes']=generate.HOME_FENCE_CODES
        b.v.update({'#hx':160,'board_count':1})
        b.a['#person_x'][0]=172;b.a['camp_active'][0]=1
        return b
    def total(self,b):
        return sum(b.a['camp_left'])+sum(b.v[x] for x in ('saved','lost','aboard'))
    def test_structure(self):structure(SOURCE)
    def test_reject_bad_cases(self):
        for bad in ('PRINT AT 31,"XX"','IF a = 1 AND b = 2 THEN a=0'):
            with self.assertRaises(ValueError):structure(SOURCE+'\n'+bad)
        with self.assertRaises(ValueError):Basic().execute(['MYSTERY 1'])
        with self.assertRaises(ValueError):structure(SOURCE.replace('#digit_pos=6161','#digit_pos=6160'))
    def test_board_and_capacity(self):
        b=self.state();b.call('people_tick')
        self.assertEqual((b.v['aboard'],b.a['camp_left'][0],b.v['board_count']),(1,15,0))
        self.assertEqual((b.a['person_state'][0],b.a['camp_active'][0]),(5,0))
        self.assertEqual(self.total(b),64)
        b=self.state();b.v['aboard']=16;b.a['camp_left'][1]=0
        b.call('people_tick');self.assertEqual(b.v['aboard'],16);self.assertEqual(self.total(b),64)
    def test_unload_only_at_pad(self):
        for x,want in ((1896,0),(1920,1),(1953,0)):
            b=self.state();b.v.update({'#hx':x,'aboard':16,'runner_on':0,'transfer_timer':0})
            b.a['camp_left']=[0,16,16,16]
            b.a['person_state'][:16]=[5]*16
            b.call('people_tick');self.assertEqual(b.v['saved'],want);self.assertEqual(self.total(b),64)
    def test_crash_and_repeated_collision(self):
        b=self.state();b.v.update(aboard=9,invuln=0,crash_timer=0);b.a['camp_left'][0]=7
        b.call('crash');b.call('crash')
        self.assertEqual((b.v['lost'],b.v['aboard'],b.v['lives']),(9,0,2))
        self.assertEqual(self.total(b),64)

    def test_crash_falls_before_ground_burn_and_counts_once(self):
        def verify(source):
            for dt in (1,2,3,4,6):
                for altitude in (25,80,152,153):
                    for lives in (1,3):
                        b=self.state();b.r=Basic(source).r
                        b.v.update({'hy':altitude,'dt':dt,'lives':lives,'aboard':2,'invuln':0,
                                    'hspeed':3,'hdir':1,'#hx':20,'runner_on':0})
                        b.a['camp_left'][0]=14;b.a['person_state'][:2]=[5,5]
                        b.call('crash');b.call('crash')
                        self.assertEqual((b.v['lives'],b.v['lost'],b.v['aboard']),(lives-1,2,0))
                        self.assertEqual(b.a['person_state'][:2],[4,4]);self.assertEqual(self.total(b),64)
                        self.assertEqual(b.v['fire_gate'],2)
                        self.assertEqual(b.sprite_patterns[13]+b.sprite_patterns[14],b.a['crash_flames'])
                        fall_frames=0
                        while b.v['hy']<b.v['landed']:
                            old_y=b.v['hy'];b.call('sound_tick');b.call('crash_tick');fall_frames+=dt
                            self.assertGreater(b.v['hy'],old_y)
                            self.assertLessEqual(b.v['hy'],b.v['landed'])
                            self.assertEqual(b.v['crash_timer'],90)
                            self.assertGreaterEqual(b.v['#hx'],16)
                            self.assertLess(fall_frames,80)
                        self.assertLessEqual(abs(fall_frames-(153-altitude)/2),dt)
                        burn_frames=0
                        while b.v['crash_timer']:
                            b.call('sound_tick');b.call('crash_tick');burn_frames+=dt
                            self.assertEqual(b.v['hy'],153)
                            self.assertLessEqual(burn_frames,96)
                            if b.v['crash_timer']<=24:
                                self.assertEqual(b.sprite_patterns[13]+b.sprite_patterns[14],b.a['crash_embers'])
                        self.assertGreaterEqual(burn_frames,90)
                        self.assertLess(burn_frames,90+dt)
                        self.assertEqual((b.v['lives'],b.v['lost']),(lives-1,2))
                        b.call('new_heli');self.assertEqual(b.v['hy'],153)
                        b.v['invuln']=0;b.call('crash')
                        self.assertEqual(b.sprite_patterns[13]+b.sprite_patterns[14],b.a['crash_flames'])
        verify(SOURCE)
        for before,after in (
                ('hy=hy+dt+dt','hy=hy+dt+dt\n    crash_timer=crash_timer-dt'),
                ('IF hy >= LANDED THEN\n        hy=LANDED','IF hy > 250 THEN\n        hy=LANDED'),
                ('DEFINE SPRITE 13,2,crash_flames','DEFINE SPRITE 13,2,crash_embers')):
            self.assertIn(before,SOURCE)
            with self.assertRaises(AssertionError):verify(SOURCE.replace(before,after))

    def test_crash_flames_cover_hull_with_only_four_sprites(self):
        def verify(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'hy':80,'#hx':480,'#camera':368,'invuln':0})
            b.sprites={i:[159,i*4,68,11] for i in range(32)}
            b.call('crash')
            for hy,timer in ((80,90),(153,90),(153,24),(153,6)):
                b.v.update(hy=hy,crash_timer=timer)
                for beat in (0,1):
                    b.v['rotor_phase']=beat;b.call('draw_actors')
                    live={i:s for i,s in b.sprites.items() if s[0]<191 and s[3]&15}
                    self.assertEqual(set(live),set(range(4)) if timer>24 else {0,1})
                    self.assertEqual({live[i][2] for i in (0,1)},{52,56})
                    self.assertEqual([live[i][3] for i in (0,1)],[10,8])
                    if timer>24:self.assertEqual([live[i][3] for i in (2,3)],[14,14])
                    self.assertEqual(b.calls.get('world_sprite',0),0)
            b.call('clock_reset');self.assertEqual(b.v['fire_gate'],2)
            face=b.v.get('face',0);b.v['cont1.button']=1
            for _ in range(60):b.call('fire_control')
            self.assertEqual(b.v.get('face',0),face)
        verify(SOURCE)
        with self.assertRaises(AssertionError):
            verify(SOURCE.replace('GOSUB hide_all\nDEFINE SPRITE 13','DEFINE SPRITE 13'))

    def test_crash_fire_art_becomes_small_grounded_embers(self):
        import generate as art
        flame=[art.sprite_bytes(art.fire_sprite(rows)) for rows in art.CRASH_FLAMES]
        embers=[art.sprite_bytes(art.fire_sprite(rows)) for rows in art.CRASH_EMBERS]
        self.assertNotEqual(*flame);self.assertNotEqual(*embers)
        for f,e in zip(art.CRASH_FLAMES,art.CRASH_EMBERS):
            self.assertLess(sum(v.bit_count() for v in e),sum(v.bit_count() for v in f)//3)
            self.assertEqual(max(y for y,v in enumerate(e) if v),14)
        generated=(ROOT/'src/assets.bas').read_text(encoding='utf-8')
        sprite_block=generated.split('sprite_art:\n')[1].split('crash_embers:\n')[0]
        data=[int(v) for line in sprite_block.splitlines() if 'DATA BYTE' in line
              for v in line.split('DATA BYTE')[1].split(',')]
        self.assertEqual(data,[v for a in art.SPRITES for v in art.sprite_bytes(a)])
        self.assertEqual(data[13*32:15*32],sum(flame,[]))
    def test_landing_casualty(self):
        b=self.state();b.v['old_y']=150;b.call('people_tick')
        self.assertEqual((b.v['lost'],b.v['aboard']),(1,0));self.assertEqual(self.total(b),64)
    def test_all_64_can_be_saved(self):
        b=self.state()
        for camp in range(4):
            for person in range(16):
                who=camp*16+person
                b.a['person_state'][who]=3;b.a['#person_x'][who]=172;b.a['camp_active'][camp]+=1
                b.v.update({'#hx':160,'board_count':1,'transfer_timer':0})
                b.call('people_tick');self.assertEqual(self.total(b),64)
            self.assertEqual(b.v['aboard'],16)
            b.v.update({'#hx':1920,'board_count':0})
            for person in range(16):
                b.v['transfer_timer']=0;b.call('people_tick');self.assertEqual(self.total(b),64)
        self.assertEqual((b.v['saved'],b.v['lost'],b.v['aboard']),(64,0,0))
    def test_accounting_mutation_fails(self):
        bad=SOURCE.replace('aboard=aboard+1','aboard=aboard+2')
        b=self.state();b.r=Basic(bad).r;b.call('people_tick')
        self.assertNotEqual(self.total(b),64)
    def test_camp_lookup_and_spawn(self):
        b=self.state();self.assertEqual(b.expr('#camp_x(1)'),384)
        b.a['person_state'][0]=2;b.v['board_count']=0;b.a['camp_active'][0]=0
        b.v.update({'#hx':400,'transfer_timer':0})
        b.a['person_state'][16]=2;b.a['#person_x'][16]=432   # 20 px from the door
        b.call('people_tick')
        self.assertEqual((b.v['board_count'],b.a['camp_active'][1]),(1,1))
        self.assertEqual((b.a['person_state'][16],b.a['#person_x'][16]),(3,430))
    def test_tank_rate_across_frame_deltas(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update({'#hx':500,'#tank_x':100,'#tank_wait':60000,'#elapsed':dt,'dt':dt})
            for _ in range(60//dt):b.call('tank_tick')
            self.assertEqual(b.v['#tank_x'],115)
    def test_flight_rate_and_braking(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update({'#hx':500,'hy':100,'dt':dt,'hspeed':3,'hdir':0,'face':1,'cont1.right':1})
            for _ in range(60//dt):b.call('fly')
            self.assertEqual(b.v['#hx'],680)
            b.v['cont1.right']=0
            for _ in range(4):b.call('fly')
            self.assertEqual((b.v['hspeed'],b.v['face']),(0,1))
    def test_open_barrack_and_destroy_tank(self):
        b=self.state();b.a.update({'#shot_x':[128,0],'shot_y':[144,0],'shot_dir':[2,0],'shot_on':[1,0]})
        b.a['camp_open']=[0]*4
        b.call('move_shot')
        self.assertEqual((b.a['camp_open'][0],b.a['shot_on'][0]),(1,0))
        b.v.update({'tank_on':1,'#tank_x':128,'runner_on':0})
        b.a['#shot_x'][0]=140
        b.a['shot_on'][0]=1;b.a['shot_y'][0]=152
        b.call('move_shot')
        self.assertEqual((b.v['tank_on'],b.a['shot_on'][0]),(0,0))
    def test_ground_and_world_limits(self):
        for x,control,expected in ((17,'cont1.left',16),(2007,'cont1.right',2008)):
            b=self.state();b.v.update({'#hx':x,'hy':100,'dt':6,'hspeed':3,'hdir':int('left' in control),control:1})
            b.call('fly');self.assertEqual(b.v['#hx'],expected)
        b=self.state();b.v.update({'hy':152,'cont1.down':1,'cont1.right':1,'hspeed':3})
        b.call('fly');self.assertEqual((b.v['hy'],b.v['hspeed'],b.v['#hx']),(153,0,160))
    def test_assets(self):
        sys.path.insert(0,str(ROOT/'assets'))
        import generate as art
        self.assertEqual(len(art.SPRITES),64)
        self.assertEqual([len(art.sprite_bytes(a)) for a in art.SPRITES],[32]*64)
        self.assertEqual(len(art.TILES),112)
        self.assertTrue(all(len(bits)==8 for bits,_ in art.TILES))
        self.assertEqual([len(row) for row in art.MAP],[256]*5)
        for col in (16,48,80,112):self.assertEqual(art.MAP[3][col],135)
        self.assertEqual(art.MAP[4][242],138)
        self.assertNotEqual(art.SPRITES[0],art.SPRITES[2])
        self.assertNotEqual(art.SPRITES[0],art.SPRITES[20])
        self.assertNotEqual(art.SPRITES[20],art.SPRITES[32])
        self.assertEqual(len(art.FLAG_COLORS),16)
        self.assertNotEqual(art.FLAG0,art.FLAG1)

    def test_two_screen_camp_setback_and_full_width_map(self):
        import generate as art
        def verify(source):
            terrain=source.split('\nterrain:\n')[1].split('\ncamp_fronts:\n')[0]
            fences=[int(n) for n in re.findall(r'#fence_world=(\d+)',terrain)]
            self.assertEqual(fences,[1568,1888])
            camps=[int(n) for n in re.findall(r'#camp_x\(\d\)=(\d+)',source)]
            self.assertEqual(camps,[128,384,640,896])
            # Old nearest wall ended at 920, 136 pixels short of the fence.
            # Add exactly two 256-pixel screens without shifting camp spacing.
            east_wall=(max(i for i,ch in enumerate(art.MAP[2]) if ch==133)+1)*8
            self.assertEqual(fences[0]-east_wall,136+2*256)
            self.assertFalse(any(ch in (133,134,135) for row in art.MAP
                                 for ch in row[east_wall//8:fences[0]//8]))
            for target in ('TI994A','COLECO'):
                b=self.state();b.r=Basic(source,target=target).r
                b.a['camp_open']=[0]*4;b.a['person_state']=[0]*64
                b.v.update(anim=0,home_walking=0,crowd_pose=255);b.v['#camera']=65535
                for camera in list(range(0,1793,8))+list(range(1792,-1,-8)):
                    b.v['#hx']=camera+112;b.v['terrain_dirty']=1
                    b.call('camera_tick');self.assertEqual(b.v['#camera'],camera)
                    b.call('crowd_draw')
                    for row in (2,3):
                        actual=[b.vram[6144+(17+row)*32+c] for c in range(32)]
                        self.assertEqual(actual,art.MAP[row][camera//8:camera//8+32])
        verify(SOURCE)
        for before,after in (
                ('#fence_world=1568','#fence_world=1056'),
                ('IF #newcam > 1792 THEN #newcam=1792','IF #newcam > 1280 THEN #newcam=1280'),
                ('SCREEN world_map,#mapoff,544,32,1\n    #mapoff=#mapoff+256\n    SCREEN world_map,#mapoff,576,32,1\n    #mapoff=#mapoff+256\n    SCREEN world_map,#mapoff,608,32,1','SCREEN world_map,#mapoff,544,32,3,256'),
                ('#crowd_map=#crowd_map+768','#crowd_map=#crowd_map+576')):
            self.assertIn(before,SOURCE)
            with self.assertRaises(AssertionError):verify(SOURCE.replace(before,after))

    def test_jet_unlock_requires_finished_delivery(self):
        b=self.state();b.v.update({'#hx':500,'aboard':2,'runner_on':0,'#jet_wait':0,'#elapsed':2})
        b.a['person_state'][:2]=[5,5]
        b.call('jet_spawn');self.assertEqual(b.v.get('jet_on',0),0)
        b.v['#hx']=1920;b.call('people_tick');b.v['#hx']=500;b.call('jet_spawn')
        self.assertEqual(b.v.get('jet_on',0),0)
        b.v['transfer_timer']=0;b.v['#hx']=1920;b.call('people_tick');b.v['#hx']=500;b.call('jet_spawn')
        self.assertEqual(b.v.get('sorties',0),0) # the last passenger is still walking to the door
        for _ in range(50):b.call('people_tick')
        b.call('jet_spawn')
        self.assertEqual((b.v['sorties'],b.v['jet_on']),(1,1))
        b.call('new_heli');self.assertEqual(b.v['sorties'],1)
        bad=SOURCE.replace('IF sorties = 0 THEN RETURN','')
        b=self.state();b.r=Basic(bad).r;b.call('jet_spawn')
        self.assertEqual(b.v['jet_on'],1) # This mutation violates the first-trip contract.

    def test_pause_debounce_and_numeric_input(self):
        for key in (0,1,15):
            b=self.state();b.v['cont1.key']=key
            for _ in range(30):
                b.call('pause_input');self.assertEqual(b.v['pause_trigger'],0)
        for target,key in (('TI994A',80),('COLECOVISION',0)):
            b=Basic(target=target);b.v.update({'dt':2,'cont1.key':key})
            for _ in range(5):b.call('pause_input');self.assertEqual(b.v['pause_trigger'],0)
            b.call('pause_input');self.assertEqual(b.v['pause_trigger'],1)
            b.call('pause_input');self.assertEqual(b.v['pause_trigger'],0)
            b.v['cont1.key']=15;b.call('pause_input')
            b.v['cont1.key']=key
            for _ in range(6):b.call('pause_input')
            self.assertEqual(b.v['pause_trigger'],1)
        b=Basic(SOURCE.replace('pause_hold >= 12','pause_hold >= 0'))
        b.v.update({'dt':2,'cont1.key':80});b.call('pause_input')
        self.assertEqual(b.v['pause_trigger'],1) # Reject a single-sample pause.

    def test_tap_fire_hold_turn_and_release_gate(self):
        b=self.state();b.call('new_heli');b.v['cont1.button']=1
        for _ in range(60):b.call('fire_control')
        self.assertEqual(b.v.get('fire_events',0),0)
        b.call('clock_reset');b.call('fire_control')
        self.assertEqual(b.v['fire_gate'],1)
        b.v['cont1.button']=0;b.call('fire_control')
        b.v['cont1.button']=1;b.call('fire_control')
        b.v['cont1.button']=0;b.call('fire_control')
        self.assertEqual((b.v['face'],b.v['fire_events']),(1,1))
        b.v['hy']=80;b.call('weapon_tick')
        self.assertEqual(b.a['shot_on'],[1,0])
        b.v['cont1.button']=1;b.call('fire_control')
        for expected,frames in ((2,30),(0,18),(2,18),(1,18)):
            for _ in range(frames):b.call('fire_control')
            self.assertEqual((b.v['face'],b.v['fire_events']),(expected,1))
        b.v['cont1.button']=0;b.call('fire_control')
        self.assertEqual(b.v['fire_events'],1)

    def test_taps_never_inherit_prepress_time_or_turn(self):
        def tap(source,duration,step):
            b=self.state();b.r=Basic(source).r
            b.v.update({'face':1,'turn_phase':2,'hy':80,'dt':step,'cont1.button':1})
            b.call('fire_control')
            for _ in range(duration):b.call('fire_control')
            b.v['cont1.button']=0;b.call('fire_control')
            b.call('weapon_tick');return b
        for duration in (0,6,12,18,24,29):
            for step in range(1,7):
                b=tap(SOURCE,duration,step)
                self.assertEqual((b.v['face'],b.v['fire_request']),(1,1))
                self.assertEqual(b.a['shot_on'],[1,0])
                b.call('weapon_tick');self.assertEqual(b.v['fire_request'],0)
        for step in range(1,7):
            b=tap(SOURCE,30,step)
            self.assertEqual((b.v['face'],b.v['fire_request']),(2,0))
        for before,after in (('IF fire_hold >= 30 THEN','IF fire_hold >= 18 THEN'),
                             ('fire_hold=fire_hold+1','fire_hold=fire_hold+dt')):
            self.assertIn(before,SOURCE)
            self.assertNotEqual(tap(SOURCE.replace(before,after),24,6).v['face'],1)

    def test_short_tap_survives_between_game_updates(self):
        self.assertIn('ON FRAME GOSUB fire_control',SOURCE)
        for gap in (2,6,12,30):
            b=self.state();b.v.update({'hy':80,'face':1,'turn_phase':2})
            for frame in range(gap):
                b.v['cont1.button']=int(frame==0);b.call('fire_control')
            self.assertEqual(b.a['shot_on'],[0,0])
            b.call('weapon_tick');self.assertEqual(b.a['shot_on'],[1,0])
            b.call('weapon_tick');self.assertEqual(b.a['shot_on'],[1,0])
        b.call('silence');b.v['cont1.button']=1
        for _ in range(40):b.call('fire_control')
        b.v['cont1.button']=0;b.call('fire_control');b.call('clock_reset')
        b.call('weapon_tick');self.assertEqual(b.v['fire_request'],0)

    def test_waiting_fast_path_matches_portable_renderer(self):
        self.waiting_paths_agree(SOURCE)
        # The native scan covers one camp per call: stopping short of 16 people
        # or scanning from the wrong camp must be caught.
        for good,bad in (('ASM andi r6,15\nASM jne waiting_scan_loop','ASM andi r6,7\nASM jne waiting_scan_loop'),
                         ('        cp=tc*16\n','        cp=tc*8\n')):
            self.assertIn(good,SOURCE)
            with self.assertRaises((AssertionError,KeyError,ValueError)):
                self.waiting_paths_agree(SOURCE.replace(good,bad))
    def waiting_paths_agree(self,source):
        import generate as art
        for camera in range(0,1793,64):
            for anim in (0,8,16,24):
                results=[]
                for target in ('TI994A','COLECO'):
                    b=self.state();b.r=Basic(source,target=target).r
                    b.a['person_state']=[2 if i%5 else 4 for i in range(64)]
                    b.a['camp_active']=[0]*4;b.v['board_count']=0
                    for i in range(64):
                        offset=88-(i%16//2)*8
                        b.a['#person_x'][i]=b.a['#camp_x'][i//16]+(offset if i&1 else -offset)
                    b.v.update({'#camera':camera,'anim':anim,'crowd_pose':255,'crowd_dirty':1})
                    b.call('crowd_draw')
                    results.append([b.vram[6784+c] for c in range(32)])
                    self.assertEqual(b.calls.get('crowd_cell',0),0)
                    for i,state in enumerate(b.a['person_state']):
                        x=b.a['#person_x'][i]-camera
                        if state==2 and 0<=x<256:
                            expected=96+(i%3)*4+((anim//8+i)&3)
                            if art.MAP[3][(x+camera)//8]==132:expected+=12
                            self.assertEqual(results[-1][x//8],expected)
                self.assertEqual(*results)

    def test_crowd_commit_keeps_front_patterns_and_row_intact(self):
        def verify(source):
            b=self.state();b.r=Basic(source).r
            b.a['person_state']=[0]*64;b.a['person_state'][:2]=[1,2]
            b.a['#person_x'][:2]=[128,136];b.a['camp_active'][0]=1
            b.v.update({'#camera':0,'anim':0,'crowd_dirty':1,'crowd_pose':255})
            b.call('crowd_draw')
            for camera in (8,16,8,0):
                front={b.vram[6784+c] for c in range(32)}
                front={c for c in front if c<32 or 64<=c<96}
                b.transfers=[];b.v.update({'#hx':camera+112,'terrain_dirty':0});b.call('camera_tick')
                self.assertFalse(any(a<6816 and a+n>6784 for a,n in b.transfers))
                b.transfers=[];b.call('crowd_draw')
                for ch in front:
                    for addr in (4096+ch*8,12288+ch*8):
                        self.assertFalse(any(a<addr+8 and a+n>addr for a,n in b.transfers))
                self.assertEqual(sum(a==6784 for a,n in b.transfers),1)
        verify(SOURCE)
        for before,after in (('crowd_bank=64-crowd_bank','crowd_bank=crowd_bank'),
                             ('GOSUB stars_draw\nRETURN','SCREEN world_map,0,640,32,1\nGOSUB stars_draw\nRETURN')):
            self.assertIn(before,SOURCE)
            with self.assertRaises(AssertionError):verify(SOURCE.replace(before,after))

    def test_scrolling_house_rows_commit_together(self):
        def verify(source,target):
            for population in ('closed','waiting','moving'):
                b=self.state();b.r=Basic(source,target=target).r
                b.a['camp_open']=[int(population!='closed')]*4
                b.a['person_state']=[0]*64
                if population!='closed':
                    b.a['person_state'][:2]=[1 if population=='moving' else 2]*2
                    b.a['#person_x'][:2]=[104,152]
                    b.a['camp_active'][0]=int(population=='moving')
                b.v.update({'#camera':0,'anim':0,'crowd_pose':255,'crowd_dirty':1,'terrain_dirty':1})
                b.call('crowd_draw')
                for camera in (8,16,8,0):
                    old={a:b.vram.get(a,32) for a in range(6688,6816)}
                    b.events=[];b.v['#hx']=camera+112;b.call('camera_tick')
                    self.assertEqual({a:b.vram.get(a,32) for a in old},old)
                    call=b.call
                    def inspect(label):
                        if label in ('crowd_plot','compose_block','waiting_draw'):
                            self.assertEqual({a:b.vram.get(a,32) for a in old},old)
                        call(label)
                    b.call=inspect;b.call('crowd_draw');b.call=call
                    screens=[i for i,event in enumerate(b.events)
                             if event[0]=='screen' and event[3]==544]
                    self.assertEqual(len(screens),1)
                    i=screens[0]
                    self.assertEqual(b.events[i-1],('wait',))
                    for row in range(3):
                        self.assertEqual(b.events[i+row],('screen','world_map',camera//8+row*256,544+row*32,32,1,32))
                    # No person simulation, composition, terrain overlays, or wait
                    # can split the top three rows from the ground-level row.
                    self.assertEqual(b.events[i+3][0],'screen')
                    self.assertEqual(b.events[i+3][3:6],(640,32,1))
        for target in ('TI994A','COLECO'):
            verify(SOURCE,target)
            for before,after in (
                    ('    WAIT\n    SCREEN world_map,#mapoff,544','    SCREEN world_map,#mapoff,544'),
                    ('GOSUB stars_draw\nRETURN','GOSUB crowd_commit\nGOSUB stars_draw\nRETURN'),
                    ('IF crowd_mask THEN\n    SCREEN crowd_cells','IF crowd_mask THEN\n    WAIT\n    SCREEN crowd_cells')):
                self.assertIn(before,SOURCE)
                with self.assertRaises(AssertionError):verify(SOURCE.replace(before,after),target)

    def test_helicopter_skids_touch_ground_in_every_landed_pose(self):
        import generate as art
        def verify(source):
            for face in range(3):
                for beat in range(2):
                    b=self.state();b.r=Basic(source).r
                    b.v['landed']=Basic(source).v['landed']
                    b.call('new_heli')
                    b.v.update({'#camera':1792,'face':face,'rotor_phase':beat})
                    b.call('draw_actors')
                    bottoms=[]
                    for slot in (0,1):
                        sy,sx,pattern,color=b.sprites[slot]
                        pixels=art.SPRITES[pattern//4]
                        bottoms.append(sy+1+max(y for y,row in enumerate(pixels) if any(row)))
                    self.assertEqual(max(bottoms)+1,21*8)
                    self.assertEqual(b.v['hy'],b.v['landed'])
        verify(SOURCE)
        with self.assertRaises(AssertionError):verify(SOURCE.replace('CONST LANDED = 153','CONST LANDED = 152'))

    def test_idle_and_offscreen_crowds_skip_expensive_work(self):
        b=self.escaped_crowd();b.v.update({'#camera':1792,'hy':80,'old_y':80,'crowd_dirty':1,'anim':0})
        self.assertEqual(b.a['camp_active'],[0]*4)
        b.calls={};b.call('escape_tick');b.call('crowd_draw')
        for routine in ('person_stride','walk_camp','crowd_landing','crowd_plot','crowd_cell','waiting_draw'):
            self.assertEqual(b.calls.get(routine,0),0,routine)
        self.assertEqual(b.v.get('crowd_mask',0),0)
        b.v.update({'#camera':0,'crowd_dirty':1});b.call('crowd_draw')
        self.assertEqual(b.calls.get('crowd_cell',0),0)
        b.a['person_state'][0]=1;b.a['camp_active'][0]=1
        b.v.update(ep=0);b.call('lose_person')
        self.assertEqual(b.a['camp_active'],[0]*4)

    def test_banking_pose_and_shot_angles(self):
        for face in range(3):
            for direction,offset in ((0,80),(1,128)):
                b=self.state();b.v.update(face=face,hdir=direction,hspeed=3,hy=80)
                b.call('heli_pose');self.assertEqual(b.v['draw_pat'],offset+face*16)
                b.call('fire_shot');self.assertEqual(b.a['shot_dir'][0],face)
                self.assertEqual(b.a['shot_slope'][0],0 if face==2 else (2 if face==direction else 1))
                b.v['hspeed']=0;b.call('heli_pose');self.assertEqual(b.v['draw_pat'],face*16)

    def test_bombs_keep_release_momentum(self):
        def drop(source,speed,direction,dt):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#hx':500,'hy':60,'face':2,'hspeed':speed,'hdir':direction,'dt':dt})
            b.call('fire_shot')
            b.v.update(hspeed=3-speed,hdir=1-direction,wi=0)
            for _ in range(3):b.call('move_shot')
            return b
        for speed in range(4):
            for direction in range(2):
                for dt in range(1,7):
                    b=drop(SOURCE,speed,direction,dt)
                    self.assertEqual(b.a['#shot_x'][0],516+speed*dt*3*(1 if direction==0 else -1))
                    self.assertEqual(b.a['shot_y'][0],69+dt*6)
        for bad in (SOURCE.replace('shot_speed(wi)=hspeed','shot_speed(wi)=0'),
                    SOURCE.replace('IF shot_drift(wi) THEN','IF hdir THEN')):
            self.assertNotEqual(drop(bad,3,1,6).a['#shot_x'][0],462)
        b=drop(SOURCE,3,1,1)
        b.a['shot_on'][0]=0;b.v.update(fire_timer=0,hspeed=0)
        b.call('fire_shot');b.v['wi']=0;b.call('move_shot')
        self.assertEqual(b.a['#shot_x'][0],516) # Reused slot forgets previous momentum.

    def test_drifting_bomb_bounds_and_swept_hit(self):
        # Shooting throughout the expanded home-side region must still work.
        for face in (0,1,2):
            b=self.state();b.v.update({'#hx':1920,'hy':80,'face':face,'hspeed':3,'hdir':0})
            b.call('fire_shot');b.v['wi']=0;b.call('move_shot')
            self.assertEqual(b.a['shot_on'][0],1)
            self.assertGreater(b.a['#shot_x'][0],1792)
        for direction,x in ((1,2),(0,2042)):
            b=self.state();b.v.update(wi=0,dt=6)
            b.a['#shot_x'][0]=x;b.a['shot_y'][0]=100;b.a['shot_dir'][0]=2
            b.a['shot_on'][0]=1;b.a['shot_speed'][0]=3;b.a['shot_drift'][0]=direction
            b.call('move_shot');self.assertEqual(b.a['shot_on'][0],0)
            self.assertLess(b.a['#shot_x'][0],2112)
        for direction,x in ((0,490),(1,544)):
            b=self.state();b.v.update({'wi':0,'dt':6,'tank_on':1,'#tank_x':500})
            b.a['#shot_x'][0]=x;b.a['shot_y'][0]=155;b.a['shot_dir'][0]=2
            b.a['shot_on'][0]=1;b.a['shot_speed'][0]=3;b.a['shot_drift'][0]=direction
            b.call('move_shot')
            self.assertEqual((b.v['tank_on'],b.a['shot_on'][0]),(0,0))

    def test_offscreen_shots_release_pool_before_fire(self):
        def check(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#hx':500,'#camera':384,'hy':80,'face':0,'fire_events':1})
            b.a['#shot_x']=[100,900];b.a['shot_y']=[80,80]
            b.a['shot_ttl']=[90,90];b.a['shot_on']=[1,1]
            b.call('weapon_tick');return b
        b=check(SOURCE)
        self.assertEqual(b.a['#shot_x'][0],528)
        self.assertEqual(b.a['shot_on'],[1,0])
        bad=check(SOURCE.replace('GOSUB cull_shot',''))
        self.assertNotEqual(bad.a['#shot_x'][0],528)
        b.v['fire_held']=0;b.a['shot_ttl'][0]=1;b.call('weapon_tick')
        self.assertEqual(b.a['shot_on'],[0,0])

    TANK_L=(48,240,248);TANK_R=(236,244,252)
    def scanline(self,b,line):
        """Sprites the VDP shows on a scanline: the first four by slot."""
        return [data for _,data in sorted(b.sprites.items()) if data[0]<line<=data[0]+16][:4]
    def test_shots_survive_four_sprite_scanline_limit(self):
        def visible(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#camera':0,'#hx':120,'hy':153,'tank_on':1,'#tank_x':140})
            b.a['shot_on']=[1,1];b.a['shot_y']=[160,160];b.a['#shot_x']=[80,200]
            b.call('draw_actors')
            return sum(data[2]==68 for data in self.scanline(b,160))
        self.assertEqual(visible(SOURCE),2)
        bad=SOURCE.replace('    draw_slot=di+4\n','    draw_slot=di+10\n')
        self.assertNotEqual(bad,SOURCE)
        self.assertLess(visible(bad),2)

    def test_deadly_projectiles_never_drop_and_ground_actors_take_turns(self):
        # Landed beside a firing tank: helicopter, tank halves and shell all
        # cross scanline 165 -- five sprites for four places (runners are crowd
        # characters now). The shell must show on every update; the tank halves
        # must each show on some of them (flicker).
        def watch(source,passes=12):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#camera':0,'#hx':120,'hy':153,'tank_on':1,'#tank_x':152,
                        'shell_on':1,'#shell_x':140,'shell_y':156})
            b.a['shot_on']=[0,0];b.call('hide_all')
            seen=[]
            for _ in range(passes):
                b.call('draw_actors')
                seen.append([data[2] for data in self.scanline(b,165)])
            return seen
        seen=watch(SOURCE)
        self.assertTrue(all(68 in row for row in seen),seen)
        for group in (self.TANK_L,self.TANK_R):
            self.assertTrue(any(set(row)&set(group) for row in seen),(group,seen))
        # The original bug: the shell queued behind the tank is never drawn.
        late=watch(SOURCE.replace('draw_slot=2\nIF shell_on THEN','draw_slot=11\nIF shell_on THEN'))
        self.assertFalse(all(68 in row for row in late))
        # Without rotation one ground actor never gets a place.
        still=watch(SOURCE.replace('sprite_rot=sprite_rot+1\n','sprite_rot=0\n'))
        self.assertFalse(all(any(set(row)&set(g) for row in still) for g in (self.TANK_L,self.TANK_R)))
        # rot_map: each phase is one-to-one onto slots 6-11, and any two
        # rotating actors each lead the other in at least a third of phases.
        table=self.state().a['rot_map']
        self.assertEqual(len(table),72)
        rows=[table[r*6:r*6+6] for r in range(12)]
        for rot,row in enumerate(rows):self.assertEqual(sorted(row),list(range(6,12)),rot)
        for a in range(6):
            for c in range(6):
                if a!=c:self.assertGreaterEqual(sum(row[a]<row[c] for row in rows),4,(a,c))

    def test_unsafe_descent_strains_the_engine(self):
        def engine(fall,anim):
            b=self.state();b.v.update({'hy':100,'hspeed':0,'crash_timer':0,'rotor_phase':0,'dt':2,
                                      'fall_speed':fall,'anim':anim})
            b.call('sound_tick');return b.sounds[0]
        safe=engine(1,0)
        self.assertEqual(engine(0,0),safe)
        for fall in (2,3):
            quiet,loud=engine(fall,0),engine(fall,4)
            self.assertLess(quiet[0],safe[0])          # a smaller divisor is a higher note
            self.assertEqual(quiet[0],loud[0])
            self.assertNotEqual(quiet[1],loud[1])      # it pulses
            self.assertGreater(min(quiet[1],loud[1]),safe[1])
        self.assertLess(engine(3,0)[0],engine(2,0)[0])  # faster is higher still
        # Releasing DOWN brakes the descent, and the cue stops with it.
        b=self.state();b.v.update({'hy':100,'fall_speed':3,'dt':2,'crash_timer':0,'hspeed':0,'rotor_phase':0})
        b.call('fly');b.call('sound_tick');self.assertEqual(b.sounds[0],safe)
    def test_crowds_keep_moving_during_a_crash(self):
        def crash_run(source):
            b=self.state();b.r=Basic(source).r
            body=b.r['crash_frame'];self.assertEqual(body[-1],'GOTO draw_frame')
            b.a['person_state']=[0]*64;b.a['camp_released']=[12,16,16,16];b.a['camp_escape']=[0]*4
            for i in range(10):b.a['person_state'][i]=1;b.a['#person_x'][i]=128
            b.a['person_state'][10:12]=[2,2];b.a['#person_x'][10:12]=[172,48]  # 10 stands where the wreck lands
            b.a['person_state'][63]=6;b.a['#person_x'][63]=1960
            b.a['camp_active']=[10,0,0,0]
            b.v.update({'#hx':160,'hy':100,'old_y':100,'dt':2,'invuln':0,'lives':3,'home_walking':1,
                        'crash_timer':0,'anim':0,'#crowd_clock':0,'runner_on':0})
            b.call('crash')
            for _ in range(200):
                if not b.v['crash_timer']:break
                b.execute(body[:-1])
            return b
        b=crash_run(SOURCE)
        self.assertEqual(b.a['camp_released'][0],16)               # releases continued
        self.assertTrue(all(s in (1,2) for s in b.a['person_state'][:16]))
        self.assertNotEqual(b.a['#person_x'][:10],[128]*10)        # walkers walked
        self.assertEqual((b.a['person_state'][63],b.v['home_walking']),(7,0))
        self.assertEqual((b.v['lost'],b.a['person_state'][10]),(0,2))  # the wreck lands on no one
        bad=crash_run(SOURCE.replace('old_y=hy\nGOSUB escape_tick\nGOSUB crash_tick','GOSUB escape_tick\nGOSUB crash_tick'))
        self.assertGreater(bad.v['lost'],0)
        frozen=crash_run(SOURCE.replace('old_y=hy\nGOSUB escape_tick\nGOSUB crash_tick','old_y=hy\nGOSUB crash_tick'))
        self.assertEqual(frozen.a['camp_released'][0],12)
    def test_deliveries_raise_the_threat(self):
        b=self.state()
        tables={k:b.a[k] for k in ('tank_reload','jet_missiles','#jet_delay','#drone_delay')}
        for name,table in tables.items():self.assertGreaterEqual(len(table),5,name)
        for i in range(4):  # every level strictly harder, never easier
            for name in ('tank_reload','#jet_delay','#drone_delay'):
                self.assertGreater(tables[name][i],tables[name][i+1],name)
            self.assertLessEqual(tables['jet_missiles'][i],tables['jet_missiles'][i+1])
        self.assertGreater(tables['jet_missiles'][4],tables['jet_missiles'][0])
        # The level follows completed deliveries (people_tick) and stops at 4.
        for done in range(7):
            b=self.state();b.v.update({'sorties':done,'threat':min(done,4),'delivery_pending':1,
                                      'home_walking':0,'runner_on':0,'hy':80,'old_y':80})
            b.call('people_tick')
            self.assertEqual((b.v['sorties'],b.v['threat']),(done+1,min(done+1,4)))
        # Enemies read their level: a jet's missiles and a tank's reload.
        for level in range(5):
            b=self.state();b.v.update({'threat':level,'sorties':1,'#hx':1000,'#jet_wait':0,'#elapsed':2,'jet_on':0})
            b.call('jet_spawn');self.assertEqual(b.v['jet_ammo'],tables['jet_missiles'][level])
            self.assertEqual(b.v['#jet_wait'],tables['#jet_delay'][level])
            b=self.state();b.v.update({'threat':level,'tank_on':1,'#tank_x':400,'#hx':300,'hy':80,
                                      '#tank_wait':0,'shell_on':0,'dt':2,'#elapsed':2,'invuln':255})
            b.call('tank_tick');self.assertEqual(b.v['#tank_wait'],tables['tank_reload'][level])
    def test_tank_fires_straight_up_when_overhead(self):
        def fire(source,hx):
            b=self.state();b.r=Basic(source).r
            b.v.update({'tank_on':1,'#tank_x':400,'#hx':hx,'hy':80,'old_y':80,'#tank_wait':0,
                        'shell_on':0,'dt':2,'#elapsed':2,'invuln':0,'crash_timer':0,'lives':3,'runner_on':0})
            b.call('tank_tick')
            path=[]
            while b.v['shell_on'] and len(path)<80:
                path.append((b.v['#shell_x'],b.v['shell_y']))
                b.call('shell_tick')
            return b,path
        b,path=fire(SOURCE,388)  # helicopter body spans the turret: front view
        self.assertEqual(b.v['tank_face'],2)
        self.assertEqual({x for x,_ in path},{415})
        self.assertEqual([y for _,y in path[:3]],[150,146,142])
        self.assertTrue(b.v['crash_timer'],'a hovering helicopter above the turret is hit')
        b,path=fire(SOURCE,200)  # off to the side: the familiar diagonal
        self.assertEqual(b.v['shell_dir'],1)
        self.assertGreater(path[0][0]-path[-1][0],0)
        bad,path=fire(SOURCE.replace('IF tank_face = 2 THEN #shell_x=#tank_x+15:shell_y=150:shell_dir=2',''),388)
        self.assertFalse(bad.v['crash_timer'],'without the rule the shell flies away under it')
    def test_inactive_sprites_hide_once_and_reappear(self):
        b=self.state();b.v.update({'#camera':0,'#hx':120,'hy':80,'tank_on':1,'#tank_x':140,'runner_on':0})
        b.a['shot_on']=[1,0];b.a['shot_y']=[90,0];b.a['#shot_x']=[60,0]
        b.call('hide_all');b.call('draw_actors')
        shows=lambda pats:any(d[0]!=209 and d[2] in pats for d in b.sprites.values())
        self.assertTrue(shows((68,)) and shows(self.TANK_L) and shows(self.TANK_R))
        # Deactivated actors are hidden on the next pass ...
        b.v['tank_on']=0;b.a['shot_on']=[0,0];b.call('draw_actors')
        self.assertFalse(shows((68,)) or shows(self.TANK_L) or shows(self.TANK_R))
        # ... and only once: a further idle pass writes no sprite at all
        # beyond the helicopter's own two slots, whatever the rotation phase.
        for _ in range(12):
            b.sprites={};b.call('draw_actors')
            self.assertEqual(sorted(b.sprites),[0,1])
        # Off-camera actors are hidden too, and come back when in view.
        b.call('hide_all');b.v.update({'tank_on':1,'#tank_x':140});b.call('draw_actors')
        b.v['#tank_x']=900;b.call('draw_actors')
        self.assertFalse(shows(self.TANK_L) or shows(self.TANK_R))
        b.v['#tank_x']=140;b.call('draw_actors')
        self.assertTrue(shows(self.TANK_L) and shows(self.TANK_R))
        # A mask that is never cleared would leave a stale bit after hide_all.
        b.call('hide_all');self.assertEqual(b.v['#sprite_shown'],0)
        bad=self.state();bad.r=Basic(SOURCE.replace('#sprite_shown=#sprite_shown XOR #slot_bit','#slot_bit=0')).r
        bad.v.update({'#camera':0,'#hx':120,'hy':80,'tank_on':1,'#tank_x':140})
        bad.call('draw_actors');bad.v['tank_on']=0;bad.call('draw_actors')
        bad.sprites={};bad.call('draw_actors')
        self.assertTrue(set(bad.sprites)-{0,1})  # the broken mask keeps rewriting hidden slots
    def test_jet_turns_passes_and_departure(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update({'#hx':1500,'hy':140,'sorties':1,'#elapsed':dt,'dt':dt,'invuln':255})
            b.call('jet_spawn');directions=set();heights=set();turns=0
            for _ in range(2400//dt):
                if not b.v['jet_on']:break
                b.call('jet_tick');directions.add(b.v['jet_dir']);heights.add(b.v['jet_y'])
                turns+=bool(b.v['jet_turn'])
                self.assertLessEqual(b.v['#jet_x']+16,1568)
            self.assertEqual(directions,{0,1});self.assertGreater(len(heights),8)
            self.assertGreater(turns,0);self.assertEqual(b.v['jet_passes'],2)
            self.assertEqual(b.v['jet_on'],0)
        # After its last pass a departing jet retires on its first step wholly
        # off camera, not after flying on to the world's west edge.
        def depart(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#hx':1500,'#camera':1388,'hy':140,'sorties':1,'#elapsed':2,'dt':2,'invuln':255})
            b.call('jet_spawn')
            for _ in range(3000):
                if not b.v['jet_on']:break
                b.call('jet_tick')
            self.assertEqual((b.v['jet_on'],b.v['jet_passes']),(0,2))
            return b.v['#jet_x']
        x=depart(SOURCE)
        self.assertLess(x+16,1388);self.assertGreaterEqual(x+16+4,1388)
        self.assertLess(depart(SOURCE.replace('IF #jet_x+16 < #camera THEN jet_on=0:RETURN','')),8)

    def test_jet_missile_ammo_and_border(self):
        b=self.state();b.v.update({'#hx':600,'#jet_x':500,'jet_ammo':2,'jet_passes':0,'jet_y':58})
        b.call('jet_attack');self.assertEqual(b.v.get('missile_on',0),0)
        b.v['jet_passes']=1;b.call('jet_attack')
        self.assertEqual((b.v['missile_on'],b.v['jet_ammo']),(1,1))
        b.v.update({'#missile_x':1566,'missile_dir':0});b.call('missile_tick')
        self.assertEqual(b.v['missile_on'],0)
        b.v['jet_fire']=0;b.call('jet_attack');self.assertEqual(b.v['jet_ammo'],0)
        b.v.update(missile_on=0,jet_fire=0);b.call('jet_attack');self.assertEqual(b.v['missile_on'],0)

    def escaped_crowd(self, source=SOURCE):
        b=self.state();b.r=Basic(source).r
        b.v.update({'#hx':1912,'hy':80,'old_y':80,'board_count':0})
        b.a['person_state']=[0]*64;b.a['camp_released']=[0]*4;b.a['camp_active']=[0]*4
        for _ in range(240):b.call('escape_tick')
        return b

    def test_all_people_escape_without_helicopter(self):
        b=self.escaped_crowd()
        self.assertEqual(b.a['camp_released'],[16]*4)
        self.assertEqual(b.a['person_state'],[2]*64)
        self.assertEqual(self.total(b),64)
        for camp in range(4):
            positions=sorted(b.a['#person_x'][camp*16:camp*16+16])
            self.assertTrue(all(y-x>=8 for x,y in zip(positions,positions[1:])))
        b.v.update(aboard=16);b.a['camp_left'][3]=0
        for _ in range(100):b.call('people_tick')
        self.assertEqual(b.a['person_state'],[2]*64) # no disappearing offscreen queue
        self.assertEqual(self.total(b),64)

    def test_escape_clock_and_closed_house(self):
        for dt in (1,2,3,4,6):
            b=self.state();b.a['person_state']=[0]*64;b.a['camp_released']=[0]*4
            b.a['camp_open']=[1,0,0,0]
            b.v.update({'dt':dt,'hy':80,'runner_on':0,'aboard':16,'#hx':1912})
            for _ in range(60//dt):b.call('escape_tick')
            self.assertEqual(b.a['camp_released'],[3,0,0,0])
            self.assertEqual(b.a['#person_x'][0],68)
            self.assertEqual(b.a['person_state'][16:],[0]*48)

    def test_crowd_can_board_all_64(self):
        b=self.escaped_crowd();b.v.update(hy=153,old_y=153)
        for camp,origin in enumerate(b.a['#camp_x']):
            for x,want in ((origin-96,8),(origin+64,16)):
                b.v['#hx']=x
                for _ in range(900):
                    b.call('people_tick')
                    self.assertEqual(self.total(b),64)
                    if b.v['aboard']==want:break
                self.assertEqual(b.v['aboard'],want)
            self.assertEqual(b.a['person_state'][camp*16:camp*16+16],[5]*16)
            b.v['#hx']=1928
            for _ in range(100):b.call('people_tick')
            self.assertEqual((b.v['aboard'],b.v['saved']),(0,(camp+1)*16))
        self.assertEqual(self.total(b),64)

    def test_streamed_boarding(self):
        # Landed between camp 1's groups: 14 people are within reach.
        def land(aboard):
            b=self.escaped_crowd();b.v.update({'#hx':344,'hy':153,'old_y':153,'dt':2,'aboard':aboard})
            b.a['camp_left'][1]=16
            return b
        b=land(0);order=[];most=0;spots=list(b.a['#person_x'])
        for frame in range(0,600,2):
            before=list(b.a['person_state'])
            b.call('people_tick');self.assertEqual(self.total(b),64)
            order+=[i for i,(s,t) in enumerate(zip(before,b.a['person_state'])) if s==2 and t in (3,5)]
            running=[i for i,s in enumerate(b.a['person_state']) if s==3]
            most=max(most,len(running))
            self.assertEqual(b.v['board_count'],len(running))
            self.assertEqual(b.a['camp_active'][1],len(running))
            if b.v['aboard']==14 and not running:break
        self.assertEqual(b.v['aboard'],14)
        self.assertLess(frame,240)                       # about 4 s, not ~17 s one at a time
        self.assertGreaterEqual(most,5)                  # several run at once
        self.assertEqual(spots[order[0]],352)            # nearest first
        # Four free seats: exactly four run and board, the rest keep waiting.
        b=land(12)
        for _ in range(300):
            b.call('people_tick')
            self.assertLessEqual(b.v['board_count']+b.v['aboard'],16)
        self.assertEqual((b.v['aboard'],b.v['board_count']),(16,0))
        self.assertEqual(b.a['person_state'][16:32].count(2),12)
        # A runner is as exposed as anyone outside.
        b=land(0)
        for _ in range(3):b.call('people_tick')
        who=b.a['person_state'].index(3);count=b.v['board_count']
        b.v.update({'#crowd_shot_x':b.a['#person_x'][who]+4,'crowd_radius':3});b.call('crowd_hit')
        self.assertEqual((b.a['person_state'][who],b.v['board_count'],b.v['lost']),(4,count-1,1))
        self.assertEqual(self.total(b),64)
    def test_runner_returns_to_crowd_when_left_behind(self):
        b=self.escaped_crowd();b.v.update({'#hx':220,'hy':153,'old_y':153})   # door 16 px past the group
        b.call('board_tick');who=b.a['person_state'].index(3)
        self.assertEqual(b.v['board_count'],1)
        b.v['#hx']=1912;b.call('people_tick')
        self.assertEqual((b.v['board_count'],b.a['person_state'][who]),(0,1))
        b.call('new_heli')
        for _ in range(50):b.call('escape_tick')
        self.assertEqual(b.a['person_state'][who],2)
        self.assertEqual(self.total(b),64)

    def test_crowd_casualties_are_individual_and_permanent(self):
        b=self.escaped_crowd()
        for who in (0,1,2):
            b.v.update({'#crowd_shot_x':b.a['#person_x'][who]+4,'crowd_radius':3})
            b.call('crowd_hit')
            self.assertEqual(b.a['person_state'][who],4)
        self.assertEqual((b.v['lost'],b.a['camp_left'][0]),(3,13))
        b.call('crowd_hit');self.assertEqual(b.v['lost'],3)
        b.v.update({'#hx':b.a['#person_x'][3]-12,'hy':153,'old_y':150,'ep':3})
        b.call('crowd_landing');self.assertEqual(b.a['person_state'][3],4)
        self.assertEqual(self.total(b),64)

    def test_crowd_composites_and_screen_edge_clipping(self):
        import generate as art
        for camera in (0,8,80,1792):
            for phase in (0,4):
                b=self.state();b.a['person_state']=[0]*64
                b.a['world_map']=[32]*1280;b.a['camp_open']=[1]*4;b.a['#camp_x']=[camera+128]*4;b.a['camp_active']=[1]*4
                positions=[camera-4]+[camera+phase+x for x in range(0,260,8)]
                positions=[x for x in positions if x>=0]
                for i,x in enumerate(positions):
                    b.a['person_state'][i]=2;b.a['#person_x'][i]=x
                b.v.update({'#camera':camera,'crowd_pose':255,'crowd_dirty':1,'anim':0})
                b.call('crowd_draw')
                actual=set()
                for col in range(32):
                    code=b.vram[6784+col]
                    if code<32 or 64<=code<96:
                        for y,bits in enumerate(b.patterns[code]):
                            actual.update((col*8+x,y) for x in range(8) if bits&(128>>x))
                expected={(world-camera+x,y) for i,world in enumerate(positions)
                          for y,row in enumerate(art.person(i%3,False,i%4))
                          for x,ink in enumerate(row[:8]) if ink and 0<=world-camera+x<256}
                self.assertEqual(actual,expected)
                self.assertFalse(b.sprites) # the crowd consumes no hardware slots
                b.a['person_state']=[4]*64;b.v['crowd_dirty']=1;b.call('crowd_draw')
                self.assertTrue(all(not (b.vram[6784+c]<32 or 64<=b.vram[6784+c]<96) for c in range(32)))

    def test_crowd_mutations_are_rejected(self):
        for before,after in (('camp_released(ec)+1','camp_released(ec)+2'),
                             ('IF camp_open(ec) THEN','IF camp_open(ec) = 0 THEN')):
            self.assertIn(before,SOURCE)
            b=self.escaped_crowd(SOURCE.replace(before,after))
            self.assertNotEqual(b.a['person_state'],[2]*64)
        b=self.state();b.r=Basic(SOURCE.replace('lost=lost+1','lost=lost+2')).r
        b.a['person_state'][0]=2;b.a['#person_x'][0]=0;b.v.update({'#crowd_shot_x':4,'crowd_radius':3})
        b.call('crowd_hit');self.assertNotEqual(self.total(b),64)

    def test_crowd_row_is_not_cleared_while_composing(self):
        def verify(source):
            b=self.state();b.r=Basic(source).r
            b.a['person_state']=[0]*64;b.a['person_state'][0]=2
            b.a['#person_x'][0]=40;b.a['camp_active'][0]=1
            b.v.update({'#camera':0,'crowd_pose':0,'crowd_dirty':1})
            b.vram={6784+i:200+i for i in range(32)}
            visible=dict(b.vram);call=b.call
            def inspect(label):
                if label in ('crowd_plot','compose_block'):self.assertEqual(b.vram,visible)
                call(label)
            b.call=inspect;b.call('crowd_draw')
            self.assertNotEqual(b.vram,visible)
        verify(SOURCE)
        bad=SOURCE.replace('FOR tc=0 TO 3\n    IF crowd_mask', 'SCREEN world_map,#crowd_map,640,32,1,256\nFOR tc=0 TO 3\n    IF crowd_mask')
        with self.assertRaises(AssertionError):verify(bad)

    def test_parallax_and_flag_clipping(self):
        import generate as art
        b=self.state();near=[]
        for camera in (1472,1504):
            b.v.update({'#camera':camera,'#fence_world':1568});b.call('fence_boundary')
            near.append(b.v['#fence_screen']+(b.v['fence_shape']-4)*8)
        self.assertEqual(near[0]-near[1],40) # horizon moves 32, foreground 40
        b.vram={}
        for camera in range(1792,-1,-8):
            b.v['#camera']=camera;b.call('flag_position')
            for world in (1568,1888):
                flag=dict(b.vram);b.vram={}
                b.v['#fence_world']=world;b.call('fence_boundary')
                self.assertTrue(all(6816<=a<6880 for a in b.vram))
                x=world-camera
                if 0<=x<256:
                    tile=b.vram[6816+x//8]
                    self.assertTrue(art.TILES[tile-128][0][0] & (128>>(x%8)))
                b.vram=flag
        self.assertTrue(all(v==32 for v in b.vram.values())) # flag leaves no trail

    def test_office_flag_is_on_roof_and_zone_is_wide(self):
        import generate as art
        b=self.state();b.v['#camera']=1792;b.call('flag_position')
        col=b.v['flag_col']
        self.assertEqual(b.vram[6144+18*32+col],146)
        self.assertEqual(b.vram[6144+17*32+col],144)
        roof=art.MAP[2][224+col]
        self.assertIn(roof,range(151,156))
        self.assertEqual(sum(c in range(151,156) for c in art.MAP[2]),10)
        # Read fence placements from production source, not a second layout model.
        terrain=SOURCE.split('\nterrain:\n')[1].split('\nfence_boundary:\n')[0]
        boundaries=[int(n) for n in re.findall(r'#fence_world=(\d+)',terrain)]
        self.assertGreaterEqual(boundaries[1]-boundaries[0],320)

    def test_fence_preserves_landing_pad_while_scrolling(self):
        import generate as art
        def verify(source):
            b=self.state();b.r=Basic(source).r
            for camera in list(range(1656,1793,8))+list(range(1792,1655,-8)):
                b.v['#camera']=camera;b.call('terrain')
                for col,under in enumerate(art.MAP[4]):
                    if under not in (137,138):continue
                    x=col*8-camera
                    if not 0<=x<256:continue
                    ch=b.vram[6816+x//8]
                    if 120<=ch<126:
                        bits=art.PAD_FENCE_ART[(ch-120)*8:(ch-119)*8]
                        colors=art.PAD_FENCE_COLORS[(ch-120)*8:(ch-119)*8]
                    else:
                        bits,color=art.TILES[ch-128];colors=[color]*8
                    base,palette=art.TILES[under-128]
                    for y in range(8):
                        for px in range(8):
                            actual=(colors[y]>>4) if bits[y] & (128>>px) else (colors[y]&15)
                            # All pad markings must survive; its black apron
                            # may gain white fence pixels, never gray holes.
                            if base[y] & (128>>px):self.assertEqual(actual,palette>>4)
                            else:self.assertIn(actual,(palette>>4,palette&15))
        verify(SOURCE)

        for before,after in (
                ('IF fire_char THEN VPOKE #vaddr,fire_char','VPOKE #vaddr,fence_char'),
                ('fire_char=home_fence_codes(fence_char-160)','fire_char=fence_codes(fence_char-160)')):
            self.assertIn(before,SOURCE)
            with self.assertRaises(AssertionError):verify(SOURCE.replace(before,after))

    def test_crowd_redraw_preserves_new_office_and_patterns(self):
        import generate as art
        def draw(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#camera':1792,'crowd_dirty':1,'crowd_pose':255})
            b.a['camp_open']=[0]*4;b.a['person_state']=[0]*64
            b.call('crowd_draw');return b
        b=draw(SOURCE)
        self.assertEqual([b.vram[6784+x] for x in range(32)],art.MAP[3][224:256])
        self.assertFalse(set(b.patterns)&set(range(128,240)))
        # Empty scenery must avoid all dynamic pattern uploads.
        self.assertFalse(set(b.patterns)-set(range(96,120))-{126,127})
        bad=draw(SOURCE.replace('#crowd_map=#crowd_map+768','#crowd_map=#crowd_map+576'))
        self.assertNotEqual([bad.vram[6784+x] for x in range(32)],art.MAP[3][224:256])

    def test_camp_evacuates_offscreen_with_full_cabin(self):
        b=self.state();b.a['camp_open']=[1,0,0,0];b.a['camp_released']=[0]*4
        b.a['person_state']=[0]*64;b.a['camp_left'][3]=0
        b.v.update({'#hx':1920,'aboard':16,'runner_on':0,'hy':100,'dt':6})
        for _ in range(80):b.call('escape_tick')
        self.assertEqual(b.a['camp_released'],[16,0,0,0])
        self.assertEqual(b.a['person_state'][:16],[2]*16)
        self.assertLess(min(b.a['#person_x'][:16]),128)
        self.assertGreater(max(b.a['#person_x'][:16]),128)
        self.assertEqual(self.total(b),64)

    def test_crowd_casualty_counted_once(self):
        b=self.state();b.a['person_state'][1]=2;b.a['#person_x'][1]=128
        b.v.update({'#crowd_shot_x':132,'crowd_radius':9})
        b.call('crowd_hit');b.call('crowd_hit')
        self.assertEqual((b.v['lost'],b.a['camp_left'][0],b.a['person_state'][1]),(1,15,4))
        self.assertEqual(self.total(b),64)

    def test_tail_rotor_changes_without_facing_change(self):
        import generate as art
        a=art.heli(False,0);b=art.heli(False,1)
        self.assertNotEqual([r[:7] for r in a[3:10]],[r[:7] for r in b[3:10]])
        for base in (0,4,20,24,32,36):
            self.assertNotEqual(art.SPRITES[base],art.SPRITES[base+2])

    def test_squish_only_for_helicopter_casualties(self):
        b=self.state();b.v['old_y']=150;b.call('people_tick')
        self.assertEqual((b.v['lost'],b.v['noise_kind'],b.v['noise_timer']),(1,4,8))
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update(dt=dt,old_y=150,ep=1)
            b.a['person_state'][1]=2;b.a['#person_x'][1]=172
            b.call('crowd_landing');self.assertEqual(b.v['noise_kind'],4)
            for _ in range(9//dt+1):b.call('sound_tick')
            self.assertEqual((b.v['noise_timer'],b.sounds[3][1]),(0,0))
        b=self.state();b.v['ep']=1;b.call('lose_person');self.assertEqual(b.v.get('noise_kind',0),0)
        b=self.state();b.v.update(noise_kind=3,noise_timer=20);b.call('squish_sound')
        self.assertEqual((b.v['noise_kind'],b.v['noise_timer']),(3,20))

    def test_grounded_weapons_and_hard_landings(self):
        for face in range(3):
            b=self.state();b.v.update(face=face,hy=153);b.call('fire_shot')
            self.assertEqual(b.a['shot_on'],[0,0]);self.assertFalse(b.sound_writes)
            b.v['hy']=152;b.call('fire_shot');self.assertEqual(b.a['shot_on'],[1,0])
        for dt in (1,2,3,4,6):
            b=self.state();b.v.update(hy=152,dt=dt,**{'cont1.down':1})
            b.call('fly');self.assertEqual((b.v['hy'],b.v['lives']),(153,3))
            b=self.state();b.v.update(hy=80,dt=dt,aboard=2,invuln=120,**{'cont1.down':1})
            for _ in range(90//dt):
                b.call('fly')
                if b.v.get('crash_timer',0):break
            self.assertEqual((b.v['lives'],b.v['aboard'],b.v['lost']),(2,0,2))
            b=self.state();b.v.update(hy=130,dt=dt,fall_speed=3,fall_hold=20)
            b.call('fly');self.assertEqual((b.v['hy'],b.v['fall_speed']),(130,0))
            b.v.update(hy=152,**{'cont1.down':1});b.call('fly');self.assertEqual(b.v['lives'],3)
        bad=SOURCE.replace('IF hy = LANDED THEN RETURN\nIF fire_timer','IF fire_timer')
        b=self.state();b.r=Basic(bad).r;b.call('fire_shot');self.assertNotEqual(b.a['shot_on'],[0,0])

    def star_sweep(self,source=SOURCE,target='TI994A',cameras=None):
        """Scroll the star field and return the first frame whose pixels differ
        from the parallax model, or None. Every camera step and both directions,
        including jumps of several steps per update (slow updates)."""
        import generate as art
        b=self.state();b.r=Basic(source,target=target).r
        if cameras is None:
            cameras=list(range(0,1793,8))+list(range(1792,-1,-8))+list(range(0,1793,24))+list(range(1792,-1,-40))
        for camera in cameras:
            b.v['#camera']=camera;b.call('stars_draw')
            if not all(6144+96<=a<6144+544 for a in b.vram):return (camera,'write outside sky rows 3-16')
            cells={a:c for a,c in b.vram.items() if c!=32}
            if len(cells)!=len(art.STAR_X):return (camera,f'{len(cells)} star cells')
            actual=set()
            for a,c in cells.items():
                if not 240<=c<=255:return (camera,f'character {c}')
                row,col=divmod(a-6144,32)
                for y,bits in enumerate(art.STAR_BITS[(c-240)*8:(c-239)*8]):
                    actual.update((col*8+x,row*8+y) for x in range(8) if bits&(128>>x))
            expected={((x-camera//8*(1+(row>=7)+(row>=12)))%256,row*8+(2 if i%2 else 5))
                      for i,(x,row) in enumerate(zip(art.STAR_X,art.STAR_ROW))}
            if actual!=expected:return (camera,'pixels differ from the parallax model')
        return b
    def test_star_parallax_wrap_and_sky_ownership(self):
        import generate as art
        for target in ('TI994A','COLECO'):
            b=self.star_sweep(target=target)
            self.assertIsInstance(b,Basic,(target,b))
            # A stationary camera writes nothing.
            b.vram={};b.transfers=[];b.call('stars_draw');self.assertFalse(b.transfers)
            # One scroll step only rewrites stars, clearing a cell only when a star leaves it.
            b.transfers=[];b.v['#camera']=b.v['#camera']+8;b.call('stars_draw')
            self.assertLessEqual(len(b.transfers),2*len(art.STAR_X))
            self.assertGreaterEqual(len(b.transfers),len(art.STAR_X))
        # The native and portable renderers write the same cells for every view.
        native=self.star_sweep(target='TI994A',cameras=list(range(0,1793,8)))
        portable=self.star_sweep(target='COLECO',cameras=list(range(0,1793,8)))
        self.assertEqual(native.vram,portable.vram)
        # Collapsed layers, a wrong erase offset, a missing erase and a broken
        # row-0 terminator must all be caught on the path they break.
        mutations=(
            ('TI994A','ASM ci r8,12\nASM jl stars_layer\nASM a r4,r6','ASM ci r8,12\nASM jl stars_layer\nASM a r5,r6'),
            ('TI994A','ASM s r0,r7\nASM neg r7','ASM s r0,r7\nASM neg r7\nASM mov r6,r7'),
            ('TI994A','ASM jeq stars_kept\nASM a r8,r7','ASM jmp stars_kept\nASM a r8,r7'),
            ('TI994A','ASM ci r8,0\nASM jeq stars_done','ASM ci r8,99\nASM jeq stars_done'),
            ('COLECO','IF star_row(star_i) >= 12 THEN star_pos=star_pos+star_scroll','IF star_row(star_i) >= 12 THEN star_pos=star_pos+star_old'),
            ('COLECO','star_cell=star_x(star_i)-star_cell','star_cell=star_x(star_i)-star_pos'),
            ('COLECO','        VPOKE #vaddr,32\n','        star_char=32\n'),
        )
        for target,good,bad in mutations:
            self.assertIn(good,SOURCE)
            with self.assertRaises((AssertionError,ValueError,KeyError,IndexError),msg=bad):
                result=self.star_sweep(SOURCE.replace(good,bad),target=target)
                self.assertIsInstance(result,Basic)
        # Port writes with interrupts enabled are rejected by the interpreter.
        with self.assertRaises(ValueError):
            self.star_sweep(SOURCE.replace('ASM limi 0\nASM swpb r0','ASM swpb r0'),cameras=[0,8])

    def test_camp_fire_reject_matches_full_scan(self):
        # The off-screen reject is an optimisation only: every camera position
        # must draw exactly what testing every fire tile would.
        reject=('        #relative=#camp_x(tc)+16\n        IF #relative >= #camera THEN\n'
                '            #relative=#relative-#camera\n            IF #relative < 296 THEN GOSUB camp_fire\n        END IF\n')
        self.assertIn(reject,SOURCE)
        full=SOURCE.replace(reject,'        GOSUB camp_fire\n')
        # Reference camp_fire: the original per-tile clip, no alignment assumed.
        start=full.index('\ncamp_fire:\n');end=full.index('\nRETURN\n',start)
        full=full[:start]+('\ncamp_fire:\n#fire_world=#camp_x(tc)-24\nFOR fire_tile=0 TO 5\n'
            '    IF #fire_world >= #camera THEN\n        #fire_screen=#fire_world-#camera\n'
            '        IF #fire_screen < 256 THEN\n            #vaddr=#fire_screen/8\n'
            '            #vaddr=#vaddr+6720\n            fire_char=126+(fire_tile AND 1)\n'
            '            VPOKE #vaddr,fire_char\n        END IF\n    END IF\n'
            '    #fire_world=#fire_world+8\nNEXT fire_tile')+full[end:]
        self.assertNotEqual(full.count('IF #vaddr >= 6752 THEN EXIT FOR'),SOURCE.count('IF #vaddr >= 6752 THEN EXIT FOR'))
        for camera in range(0,1793,8):
            writes=[]
            for source in (SOURCE,full):
                b=self.state();b.r=Basic(source).r;b.v['#camera']=camera
                b.call('camp_fronts');writes.append(b.vram)
            self.assertEqual(writes[0],writes[1],camera)
        # Too tight a reject drops the edge tiles and must be caught.
        tight=SOURCE.replace('IF #relative < 296 THEN','IF #relative < 280 THEN')
        b=self.state();b.r=Basic(tight).r;b.v['#camera']=640+16-288;b.call('camp_fronts')
        c=self.state();c.v['#camera']=640+16-288;c.call('camp_fronts')
        self.assertNotEqual(b.vram,c.vram)
    def test_house_overlays_follow_the_synchronised_copy(self):
        # A scroll commit waits for vblank and copies rows 17-20; camp fires,
        # doors and the flag (rows 17-19) must be the very next writes, ahead
        # of the ground rows and fences, so the beam never shows a burning
        # camp with its closed roof for a frame.
        def order(source):
            b=self.state();b.r=Basic(source).r
            b.v.update({'#camera':256,'terrain_dirty':1,'crowd_mask':0,'#crowd_map':800,'flag_visible':0})
            b.events=[];b.transfers=[]
            b.call('crowd_commit')
            rows=[(a-6144)//32 for a,_ in b.transfers]
            return rows
        rows=order(SOURCE)
        self.assertEqual(rows[:4],[17,18,19,20])
        overlay=[i for i,r in enumerate(rows) if r in (17,18,19) and i>=4]
        ground=[i for i,r in enumerate(rows) if r in (21,22)]
        self.assertTrue(overlay and ground and max(overlay)<min(ground),rows)
        late=SOURCE.replace('GOSUB flag_position\nGOSUB camp_fronts\n#mapoff=#camera/8','#mapoff=#camera/8')
        late=late.replace('GOSUB fence_boundary\nterrain_dirty=0','GOSUB fence_boundary\nGOSUB flag_position\nGOSUB camp_fronts\nterrain_dirty=0')
        self.assertNotEqual(late,SOURCE)
        rows=order(late)
        overlay=[i for i,r in enumerate(rows) if r in (17,18,19) and i>=4]
        self.assertGreater(max(overlay),min(i for i,r in enumerate(rows) if r in (21,22)))
    def test_ground_replaces_status_row(self):
        b=self.state();b.v['#camera']=1792;b.call('terrain')
        self.assertEqual([b.vram[6848+x] for x in range(32) if x>16],[129]*15)
        # Row 23 is game_screen's alone: scrolling never rewrites it, and no
        # routine reachable during play writes there.
        self.assertFalse([a for a,_ in b.transfers if a>=6880])
        b=self.state();b.v.update(anim=0,crowd_pose=255);b.call('game_screen')
        self.assertEqual([b.vram[6880+x] for x in range(32)],[129]*32)
        b.transfers=[]
        for camera in list(range(0,1793,8))+list(range(1792,-1,-8)):
            b.v['#camera']=camera;b.call('terrain');b.call('stars_draw')
        b.call('hud')
        self.assertFalse([a for a,n in b.transfers if a+n>6880])
        for routine in ('hud','game_screen','pause_game','pause_end'):
            for line in b.r[routine]:
                m=re.search(r'PRINT AT (\d+)',line)
                if m:self.assertLess(int(m[1]),736)

    def test_faster_rotors_do_not_freeze_at_slow_deltas(self):
        for dt in (1,2,3,4,5,6):
            b=self.state();b.v['dt']=dt;poses=[]
            for _ in range(48//dt):
                b.call('rotor_tick');b.call('heli_pose');poses.append(b.v['draw_pat'])
            self.assertEqual(len(set(poses)),2)
            if dt in (1,2,4):
                self.assertEqual(sum(a!=c for a,c in zip(poses,poses[1:])),12-int(dt==4))
        old=SOURCE.replace('IF rotor_clock >= 4 THEN','IF rotor_clock >= 8 THEN',1)
        b=Basic(old);b.v['dt']=4;b.call('rotor_tick')
        self.assertEqual(b.v.get('rotor_phase',0),0)
        b=Basic();b.v['dt']=4;b.call('rotor_tick');self.assertEqual(b.v['rotor_phase'],1)

    def test_sound_envelopes_and_all_channels_off(self):
        for dt in (1,2,3,4,6):
            for gun in (1,2):
                for chime in (1,2,3):
                    b=self.state();b.v.update(dt=dt,crash_timer=90,gun_kind=gun,
                        gun_timer=24 if gun==2 else 10,chime_kind=chime,chime_timer=36 if chime==3 else 10,
                        noise_timer=24,noise_kind=3)
                    b.call('weapon_sound')
                    for _ in range(42//dt):b.call('sound_tick')
                    self.assertTrue(all(v==0 for _,v in b.sounds.values()))
                    self.assertGreater(len({p for c,p,v in b.sound_writes if c==1 and v}),1)
                    b.v.update(gun_timer=10,chime_timer=10,noise_timer=10)
                    b.call('silence')
                    self.assertTrue(all(v==0 for _,v in b.sounds.values()))
                    self.assertTrue(all(b.v[t]==0 for t in ('gun_timer','chime_timer','noise_timer')))
        b=self.state();b.v.update(hy=80,jet_on=1,**{'#jet_x':180});b.call('sound_tick')
        self.assertGreater(b.sounds[1][1],0)
        b.v['#jet_x']=900;b.call('sound_tick');self.assertEqual(b.sounds[1][1],0)
        bad=SOURCE.replace('SOUND 3,0,0\ngun_timer=0','gun_timer=0')
        b=Basic(bad);b.sounds[3]=(6,12);b.call('silence');self.assertNotEqual(b.sounds[3][1],0)

    def test_838_edges_choices_and_marked_best(self):
        for target in ('TI994A','COLECO'):
            b=Basic(target=target);b.v['title_key']=15
            for key in (8,8,15,3,3,15,8):
                b.v['cont1.key']=key;b.call('title_code')
            self.assertEqual(b.v['title_seq'],3)
            for lives in range(1,10):
                b.v.update(menu_key=lives,practice=0);b.call('setup_choice')
                self.assertEqual((b.v['start_lives'],b.v['practice']),(lives,1))
            for key in (0,10,15,80):
                b.v.update(menu_key=key,practice=0);b.call('setup_choice');self.assertEqual(b.v['practice'],0)
        for saved,best,practice,marked,want in ((20,16,1,0,1),(16,16,0,1,0),(16,16,1,0,0),(15,16,0,1,1)):
            b=Basic();b.v.update(saved=saved,best=best,practice=practice,best_practice=marked)
            b.call('best_update');self.assertEqual((b.v['best'],b.v['best_practice']),(max(saved,best),want))
        hud=SOURCE.split('\nhud:\n')[1].split('IF aboard = CAPACITY')[0]
        for lives in range(10):
            b=self.state();b.r['reserves']=hud.split('spares=0')[1].split('hudchar=32\nIF practice')[0]
            b.r['reserves']=['spares=0']+b.r['reserves'].strip().splitlines()
            b.v['lives']=lives;b.call('reserves')
            self.assertEqual([b.vram[6200+i] for i in range(8)],[32]*(8-max(0,lives-1))+[140]*max(0,lives-1))

    def test_tank_views_and_projectile_sweeps(self):
        import generate as art
        self.assertEqual(art.TANKS[1],[r[::-1] for r in art.TANKS[0]])
        self.assertNotEqual(art.TANKS[2],art.TANKS[0])
        for x,face in ((100,1),(200,2),(260,0)):
            b=self.state();b.v.update({'#hx':x,'#tank_x':200});b.call('tank_pose')
            self.assertEqual(b.v['tank_face'],face)
        for old,new,y,want in ((170,194,160,0),(175,199,160,0),(180,204,160,1),
                               (232,256,160,0),(240,216,160,1),(180,204,154,0)):
            b=self.state();b.v.update({'#sweep_x':old,'sweep_y':y,'#hit_x':203,
                'hit_width':26,'hit_top':158,'hit_bottom':170})
            b.a['#shot_x'][0]=new;b.a['shot_y'][0]=y;b.call('shot_hits_box')
            self.assertEqual(b.v['hit_found'],want)
        b=self.state();b.v.update({'dt':6,'tank_on':1,'#tank_x':200,'runner_on':0})
        b.a['#shot_x'][0]=215;b.a['shot_y'][0]=160;b.a['shot_dir'][0]=2;b.a['shot_on'][0]=1
        b.call('move_shot');self.assertEqual((b.v['tank_on'],b.a['shot_on'][0]),(0,0))

    def test_individual_paces_and_overlapping_poses(self):
        import generate as art
        # Three appearances walk at 60, 48 and 40 px/s: one second of 2-frame
        # updates through the real escape_tick, on both renderers' paths.
        for target in ('TI994A','COLECO'):
            b=self.state();b.r=Basic(target=target).r
            b.v.update({'dt':2,'#crowd_clock':0,'home_walking':0})
            b.a['person_state']=[0]*64;b.a['person_state'][:3]=[1,1,1]
            b.a['#person_x'][:3]=[128,128,128];b.a['camp_active']=[3,0,0,0]
            for _ in range(30):b.call('escape_tick')
            self.assertEqual([abs(x-128) for x in b.a['#person_x'][:3]],[60,48,40],target)
        def draw(source):
            b=self.state();b.r=Basic(source).r
            b.a['world_map']=[32]*1280;b.a['camp_open']=[1]*4;b.a['person_state']=[0]*64;b.a['camp_active'][0]=1
            for who,x in enumerate((40,44,48)):
                b.a['person_state'][who]=2;b.a['#person_x'][who]=x
            b.v.update({'#camera':0,'crowd_pose':255,'crowd_dirty':1})
            b.call('crowd_draw')
            return {(col*8+x,y) for col in range(32) if b.vram[6784+col]<32
                    for y,bits in enumerate(b.patterns[b.vram[6784+col]])
                    for x in range(8) if bits&(128>>x)}
        expected={(world+x,y) for who,world in enumerate((40,44,48))
                  for y,row in enumerate(art.person(who,False,who)) for x,ink in enumerate(row) if ink}
        self.assertEqual(draw(SOURCE),expected)
        self.assertEqual(SOURCE.count('ASM socb *r1+,*r0+'),8)
        bad=SOURCE.replace('ASM socb *r1+,*r0+','ASM movb *r1+,*r0+')
        self.assertNotEqual(draw(bad),expected)

    def walker_runs(self,source,trials=120):
        """Random crowds stepped through escape_tick on the native and portable
        paths; returns the first differing observation, or None."""
        import random
        rng=random.Random(1983)
        for trial in range(trials):
            states=[rng.choice((0,1,1,1,2,4,5,6,6,7)) for _ in range(64)]
            xs=[]
            for i,s in enumerate(states):
                camp=(128,384,640,896)[i//16]
                if s==1:xs.append(camp+4*rng.randint(-24,24))
                elif s==6:xs.append(1896+4*rng.randint(0,26))
                else:xs.append(4*rng.randint(0,511))
            dt=rng.randint(1,6);clock=rng.choice((0,59994,59999,rng.randint(0,59999)))
            released=[rng.choice((14,15,16,16)) for _ in range(4)]
            escape=[rng.randint(0,30) for _ in range(4)]
            runs=[]
            for target in ('TI994A','COLECO'):
                b=self.state();b.r=Basic(source,target=target).r
                b.a['person_state']=list(states);b.a['#person_x']=list(xs)
                b.a['camp_active']=[sum(s==1 for s in states[c*16:c*16+16]) for c in range(4)]
                b.a['camp_released']=list(released);b.a['camp_escape']=list(escape)
                b.v.update({'dt':dt,'#crowd_clock':clock,'home_walking':states.count(6),'crowd_dirty':0})
                seen=[]
                for step in range(6):
                    b.call('escape_tick')
                    seen.append((list(b.a['person_state']),list(b.a['#person_x']),list(b.a['camp_active']),
                                 b.v['home_walking'],b.v['crowd_dirty'],b.v['#crowd_clock']))
                    b.v['crowd_dirty']=0
                runs.append(seen)
            if runs[0]!=runs[1]:return trial
        return None
    def crowd_row_ink(self,source,target,walking,camera,anim):
        """Ink pixels of the crowd row with camp `walking` mid-evacuation and
        every other camp settled at its waiting spots."""
        b=self.state();b.r=Basic(source,target=target).r
        b.a['person_state']=[2]*64;b.a['camp_active']=[0]*4
        for i in range(64):
            offset=88-(i%16//2)*8
            b.a['#person_x'][i]=b.a['#camp_x'][i//16]+(offset if i&1 else -offset)
        for i in range(walking*16,walking*16+16,2):
            b.a['person_state'][i]=1;b.a['#person_x'][i]-=12 if i&1 else -12
        b.a['camp_active'][walking]=8
        b.v.update({'#camera':camera,'anim':anim,'crowd_pose':255,'crowd_dirty':1,'home_walking':0})
        b.call('crowd_draw')
        return {(col*8+x,y) for col in range(32) for code in [b.vram[6784+col]] if code in b.patterns
                for y,bits in enumerate(b.patterns[code]) for x in range(8) if bits&(128>>x)}
    def test_settled_camps_skip_the_compositor(self):
        # Composite every visible camp (the previous renderer) for reference.
        old=SOURCE.replace('        IF camp_active(tc) THEN\n#if TI994A\n            cp=tc*16:crowd_mode=0',
                           '        IF 1 THEN\n#if TI994A\n            cp=tc*16:crowd_mode=0')
        old=old.replace('#endif\nGOSUB crowd_settled\nGOSUB crowd_doors\nGOSUB crowd_commit\ncrowd_bank=64-crowd_bank',
                        '#endif\nGOSUB crowd_doors\nGOSUB crowd_commit\ncrowd_bank=64-crowd_bank')
        self.assertNotEqual(old,SOURCE)
        self.assertEqual(old.count('GOSUB crowd_settled'),1)  # only waiting_draw keeps it
        for target in ('TI994A','COLECO'):
            for walking in (0,1):
                for camera in range(0,641,32):
                    want=self.crowd_row_ink(old,target,walking,camera,8)
                    self.assertEqual(self.crowd_row_ink(SOURCE,target,walking,camera,8),want,(target,walking,camera))
        # Dropping the settled pass loses the neighbouring crowd.
        bad=SOURCE.replace('#endif\nGOSUB crowd_settled\nGOSUB crowd_doors','#endif\nGOSUB crowd_doors')
        self.assertNotEqual(self.crowd_row_ink(bad,'TI994A',0,192,8),self.crowd_row_ink(SOURCE,'TI994A',0,192,8))
    def compositor_runs(self,source,trials=60):
        """Random moving-crowd scenes drawn by the native and portable paths;
        returns the first trial whose name row, pixels or VRAM differ."""
        import random
        rng=random.Random(4096)
        for trial in range(trials):
            camera=8*rng.randint(0,224)
            if trial%5==0:camera=8*rng.randint(204,224)   # home: office tiles, walkers
            states=[0]*64;xs=[0]*64;active=[0]*4
            for c in range(4):
                walking=rng.random()<0.6
                for i in range(c*16,c*16+16):
                    camp=(128,384,640,896)[c]
                    s=rng.choice((1,1,2,2,2,3,4,5)) if walking else rng.choice((2,2,2,4))
                    states[i]=s;xs[i]=camp+4*rng.randint(-24,24)
                    if s==1:active[c]+=1
            for i in rng.sample(range(64),rng.randint(0,10)):
                states[i]=6;xs[i]=1896+4*rng.randint(0,26)
                active[i//16]-=0
            # Exact edge cases: half a person at the left edge, a straddle at cell 31.
            states[0]=1;xs[0]=camera-4 if camera>=4 else 4;states[1]=1;xs[1]=camera+252
            active=[sum(s in (1,3) for s in states[c*16:c*16+16]) for c in range(4)]
            anim=rng.randint(0,255);bank=rng.choice((0,64))
            rows=[]
            for target in ('TI994A','COLECO'):
                b=self.state();b.r=Basic(source,target=target).r
                b.a['person_state']=list(states);b.a['#person_x']=list(xs);b.a['camp_active']=list(active)
                b.a['crowd_pixels']=[0]*256
                b.v.update({'#camera':camera,'anim':anim,'crowd_pose':255,'crowd_dirty':1,'terrain_dirty':0,
                            'home_walking':states.count(6),'crowd_bank':bank})
                b.call('crowd_draw')
                rows.append((list(b.a['crowd_cells']),list(b.a['crowd_pixels']),dict(b.vram)))
            if rows[0]!=rows[1]:return trial
        return None
    def test_native_compositor_matches_portable(self):
        self.assertIsNone(self.compositor_runs(SOURCE))
        mutations=(('ASM ci r1,4\nASM jne compose_next','ASM ci r1,8\nASM jne compose_next'),
                   ('ASM ci r7,31\nASM jeq compose_next','ASM ci r7,32\nASM jeq compose_next'),
                   ('ASM ai r1,32\nASM jmp compose_palette','ASM ai r1,16\nASM jmp compose_palette'),
                   ('ASM ai r9,4\nASM compose_still:','ASM ai r9,0\nASM compose_still:'),
                   ('ASM li r8,192\nASM bl @compose_cell','ASM li r8,384\nASM bl @compose_cell'),
                   ('ASM ci r1,157\nASM jeq compose_door','ASM ci r1,158\nASM jeq compose_door'),
                   ('ASM ci r1,3\nASM jh compose_next','ASM ci r1,2\nASM jh compose_next'))
        for good,bad in mutations:
            self.assertIn(good,SOURCE)
            caught=None
            try:caught=self.compositor_runs(SOURCE.replace(good,bad),trials=40)
            except (ValueError,KeyError,IndexError):caught='error'
            self.assertIsNotNone(caught,bad)
    def test_native_walkers_match_portable(self):
        self.assertIsNone(self.walker_runs(SOURCE))
        # Each of these breaks one rule of the native walk and must be caught.
        mutations=(('ASM jle walk_store\nASM mov r0,r8','ASM jle walk_store\nASM mov r8,r8'),
                   ('ASM andi r1,1\nASM jne walk_east','ASM andi r1,1\nASM jeq walk_east'),
                   ('ASM movb *r9,r1\nASM ai r1,-256','ASM movb *r9,r1\nASM ai r1,0'),
                   ('ASM s r4,r1\nASM clr r0','ASM clr r0'),
                   ('ASM ci r8,1992\nASM jhe walk_inside','ASM ci r8,1984\nASM jhe walk_inside'),
                   ('ASM li r0,256\nASM movb r0,@cvb_CROWD_DIRTY','ASM li r0,0\nASM movb r0,@cvb_CROWD_DIRTY'))
        for good,bad in mutations:
            self.assertIn(good,SOURCE)
            caught=None
            try:caught=self.walker_runs(SOURCE.replace(good,bad),trials=40)
            except (ValueError,KeyError,IndexError):caught='error'
            self.assertIsNotNone(caught,bad)

    def test_unload_walks_to_office_before_unlocking_jets(self):
        b=self.state();b.a['person_state']=[0]*64;b.a['person_state'][:2]=[5,5]
        b.a['camp_left'][0]=14
        b.v.update({'#hx':1920,'aboard':2,'runner_on':0})
        b.call('people_tick')
        self.assertEqual((b.v['aboard'],b.v['saved'],b.a['person_state'][0]),(1,1,6))
        self.assertEqual(b.a['#person_x'][0],1932)
        self.assertEqual(b.v.get('sorties',0),0)
        for _ in range(60):
            b.call('people_tick');self.assertEqual(self.total(b),64)
        self.assertEqual(b.a['person_state'][:2],[7,7])
        self.assertTrue(all(x>=1992 for x in b.a['#person_x'][:2]))
        self.assertEqual((b.v['aboard'],b.v['saved'],b.v['sorties']),(0,2,1))

    def test_walkers_preserve_office_background(self):
        import generate as art
        b=self.state();b.a['person_state']=[0]*64;b.a['person_state'][0]=6
        b.a['#person_x'][0]=1976;b.a['camp_open']=[0]*4
        b.v.update({'#camera':1792,'crowd_pose':255,'crowd_dirty':1,'home_walking':1})
        b.call('crowd_draw');col=(1976-1792)//8
        silhouette=[sum(ink<<(7-x) for x,ink in enumerate(row)) for row in art.person(0,True,0)]
        self.assertEqual(b.patterns[col],[a|p for a,p in zip(art.TILES[156-128][0],silhouette)])
        self.assertEqual([b.vram[12288+col*8+y] for y in range(8)],[0x6F]*8)
        b.a['person_state'][0]=7;b.v['crowd_dirty']=1;b.call('crowd_draw')
        self.assertEqual(b.vram[6784+col],156)

if __name__=='__main__':unittest.main()
