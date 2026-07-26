p="HARDHAT.bas"
raw=open(p,"rb").read().decode("utf-8")
crlf="\r\n" in raw
s=raw.replace("\r\n","\n")
def rep(old,new,tag):
    global s
    n=s.count(old); assert n==1, "%s: found %d"%(tag,n)
    s=s.replace(old,new); print("ok:",tag)

rep("\t\t\tmy = my - 1\n\t\tNEXT t8",
    "\t\t\tmy = my - 1\n\t\t\tfcy = my\t' rising: hold the fall origin at the apex\n\t\tNEXT t8","apex")
rep("\t\t' Arc exhausted without landing: free fall, measured from here.\n\t\tst = S_FALL\n\t\tfcy = my\n\t\tfct = 0",
    "\t\t' Arc exhausted without landing: keep falling. fcy still holds the\n\t\t' arc's APEX, so the drop is measured from the true high point.\n\t\tst = S_FALL\n\t\tfct = 0","jump_adv apex")
rep("\nfoot_probe:\n",
    "\nland_chk:\n\t' ONE landing rule for EVERY surface. A landing reached from a jump or a\n\t' fall is fatal when the drop from the apex (fcy) exceeds FATALFALL --\n\t' solid girder, crane beam, conveyor, elevator alike. Only plain solid\n\t' ground used to be checked, so a long fall onto the moving girder or a\n\t' belt was a free save from ANY height.\n\tded = 0\n\tfd2 = my - fcy\n\tIF fd2 > FATALFALL THEN\n\t\tGOSUB mack_die\n\t\tded = 1\n\tEND IF\n\tRETURN\n\nfoot_probe:\n","land_chk")
rep("\t\t\tGOSUB elev_sup\n\t\t\tIF esup = 1 THEN\n\t\t\t\tst = S_RIDE\n\t\t\t\tRETURN\n\t\t\tEND IF",
    "\t\t\tGOSUB elev_sup\n\t\t\tIF esup = 1 THEN\n\t\t\t\tGOSUB land_chk\n\t\t\t\tIF ded = 0 THEN st = S_RIDE\n\t\t\t\tRETURN\n\t\t\tEND IF","jump->elev")
rep("\t\t\tGOSUB beam_sup\n\t\t\tIF bsup = 1 THEN\n\t\t\t\tst = S_WALK\n\t\t\t\tbonbeam = 1\n\t\t\t\tmy = bmy - 16\n\t\t\t\tRETURN\n\t\t\tEND IF",
    "\t\t\tGOSUB beam_sup\n\t\t\tIF bsup = 1 THEN\n\t\t\t\tmy = bmy - 16\n\t\t\t\tGOSUB land_chk\n\t\t\t\tIF ded = 0 THEN\n\t\t\t\t\tst = S_WALK\n\t\t\t\t\tbonbeam = 1\n\t\t\t\tEND IF\n\t\t\t\tRETURN\n\t\t\tEND IF","jump->beam")
rep("\t\t\tGOSUB conv_sup\n\t\t\tIF csup = 1 THEN\n\t\t\t\tst = S_WALK\n\t\t\t\tRETURN\n\t\t\tEND IF",
    "\t\t\tGOSUB conv_sup\n\t\t\tIF csup = 1 THEN\n\t\t\t\tGOSUB land_chk\n\t\t\t\tIF ded = 0 THEN st = S_WALK\n\t\t\t\tRETURN\n\t\t\tEND IF","jump->conv")
rep("\t\tGOSUB beam_sup\n\t\tIF bsup = 1 THEN\n\t\t\tmy = bmy - 16\n\t\t\tbonbeam = 1\n\t\t\tst = S_WALK\n\t\t\tRETURN\n\t\tEND IF",
    "\t\tGOSUB beam_sup\n\t\tIF bsup = 1 THEN\n\t\t\tmy = bmy - 16\n\t\t\tGOSUB land_chk\n\t\t\tIF ded = 0 THEN\n\t\t\t\tbonbeam = 1\n\t\t\t\tst = S_WALK\n\t\t\tEND IF\n\t\t\tRETURN\n\t\tEND IF","fall->beam")
rep("\t\tGOSUB conv_sup\n\t\tIF csup = 1 THEN\n\t\t\tst = S_WALK\n\t\t\tRETURN\n\t\tEND IF",
    "\t\tGOSUB conv_sup\n\t\tIF csup = 1 THEN\n\t\t\tGOSUB land_chk\n\t\t\tIF ded = 0 THEN st = S_WALK\n\t\t\tRETURN\n\t\tEND IF","fall->conv")
if crlf: s=s.replace("\n","\r\n")
open(p,"wb").write(s.encode("utf-8")); print("ALL APPLIED (crlf=%s)"%crlf)
