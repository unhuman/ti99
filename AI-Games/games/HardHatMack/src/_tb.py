p="HARDHAT.bas"
raw=open(p,"rb").read().decode("utf-8"); crlf="\r\n" in raw
s=raw.replace("\r\n","\n")
def rep(old,new,tag):
    global s
    n=s.count(old); assert n==1,"%s: %d"%(tag,n)
    s=s.replace(old,new); print("ok:",tag)
rep("\tDEFINE CHAR T_LBOXL,1,pail_pat\n\tDEFINE COLOR T_LBOXL,1,pail_col",
    "\tDEFINE CHAR T_LBOXL,2,pail_pat\t' 183 lunch pail, 184 toolbox\n\tDEFINE COLOR T_LBOXL,2,pail_col","define pail x2")
rep("pail_col:\n","\t' 184 toolbox: carry handle over a squat chest (2nd L2 prize)\n\tDATA BYTE $18,$3C,$00,$7E,$FF,$FF,$FF,$7E\npail_col:\n","toolbox pattern")
rep("\t' white dome+lid, gray latch band, red body, red base\n\tDATA BYTE $F1,$F1,$F1,$F1,$E1,$61,$61,$61",
    "\t' white dome+lid, gray latch band, red body, red base\n\tDATA BYTE $F1,$F1,$F1,$F1,$E1,$61,$61,$61\n\t' toolbox: gray handle, dark-yellow chest\n\tDATA BYTE $E1,$E1,$11,$A1,$A1,$A1,$A1,$A1","toolbox colour")
if crlf: s=s.replace("\n","\r\n")
open(p,"wb").write(s.encode("utf-8")); print("DONE")
