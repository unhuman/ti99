p="HARDHAT.bas"
raw=open(p,"rb").read().decode("utf-8"); crlf="\r\n" in raw
s=raw.replace("\r\n","\n")
def rep(old,new,tag):
    global s
    n=s.count(old); assert n==1,"%s: %d"%(tag,n)
    s=s.replace(old,new); print("ok:",tag)

# 1) full-height crane cable down col 14 (reference shows it running the whole shaft)
rep("\tDATA BYTE 7, 14,3,2\t\t' cable stub col 14, rows 3-4 (holds the magnet)",
    "\tDATA BYTE 7, 14,3,17\t\t' crane cable col 14, rows 3-19: in the reference it\n\t\t\t\t\t' runs the WHOLE shaft, the beam rides it",
    "cable full height")

# 2) beam_draw must RESTORE the cable it passes over, not blank it (cols 11-16, cable at 14)
old_blank = ("\t\t#va = VADDR(bprow,11)\n\t\tFOR i = 1 TO 6\n\t\t\tVPOKE #va,32\n\t\t\t#va = #va + 1\n\t\tNEXT i\n"
             "\t\tbpr2 = bprow + 1\n\t\t#va = VADDR(bpr2,11)\n\t\tFOR i = 1 TO 6\n\t\t\tVPOKE #va,32\n\t\t\t#va = #va + 1\n\t\tNEXT i")
new_blank = ("\t\t' Vacated cells go back to EMPTY -- except col 14, which carries the\n"
             "\t\t' crane cable the beam rides on; blanking it chewed a moving hole in\n"
             "\t\t' the cable.\n"
             "\t\t#va = VADDR(bprow,11)\n\t\tFOR i = 1 TO 6\n\t\t\tbc9 = 32\n\t\t\tIF i = 4 THEN bc9 = T_CABLE\n\t\t\tVPOKE #va,bc9\n\t\t\t#va = #va + 1\n\t\tNEXT i\n"
             "\t\tbpr2 = bprow + 1\n\t\t#va = VADDR(bpr2,11)\n\t\tFOR i = 1 TO 6\n\t\t\tbc9 = 32\n\t\t\tIF i = 4 THEN bc9 = T_CABLE\n\t\t\tVPOKE #va,bc9\n\t\t\t#va = #va + 1\n\t\tNEXT i")
rep(old_blank,new_blank,"beam restores cable")

if crlf: s=s.replace("\n","\r\n")
open(p,"wb").write(s.encode("utf-8")); print("DONE")
