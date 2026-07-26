p="HARDHAT.bas"
raw=open(p,"rb").read().decode("utf-8"); crlf="\r\n" in raw
s=raw.replace("\r\n","\n")
def rep(old,new,tag):
    global s
    n=s.count(old); assert n==1,"%s: %d"%(tag,n)
    s=s.replace(old,new); print("ok:",tag)

# --- rivet dashes back on the L2 girder (reference has them; "holes" meant fall-through gaps) ---
rep("\t' 129 girder variant (level 2): SOLID full-height bar (reference is a solid\n\t' red/blue/red girder, no dash-holes, fills the whole cell)\n\tDATA BYTE $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF",
    "\t' 129 girder (level 2): full-height red/blue/red bar with RIVET DASHES in\n\t' the blue band, as the reference draws it. (These dashes are texture, not\n\t' gaps -- nothing falls through a girder.)\n\tDATA BYTE $FF,$FF,$DB,$FF,$DB,$FF,$FF,$FF","rivet dashes")

# --- layout transcribed from the reference cell grid ---
# top platform is SPLIT either side of the cable (cols 11-13 and 15-17)
rep("\tDATA BYTE 1, 5,11,7,1\t\t' top crane platform (cols 11-17)",
    "\tDATA BYTE 1, 5,11,3,1\t\t' top crane platform, LEFT half (cols 11-13)\n\tDATA BYTE 1, 5,15,3,1\t\t' top crane platform, RIGHT half (cols 15-17)\n\t\t\t\t\t' -- the reference splits it around the cable","top split")
# side tiers run cols 2-10 and 18-26 (were 2-9 / 18-25)
for r in (9,13,17):
    rep("\tDATA BYTE 1, %d,2,8,1"%r,  "\tDATA BYTE 1, %d,2,9,1"%r,  "tier %d left"%r)
    rep("\tDATA BYTE 1, %d,18,8,1"%r, "\tDATA BYTE 1, %d,18,9,1"%r, "tier %d right"%r)
# lower-left ledge the reference has at row 18, cols 2-5
rep("\tDATA BYTE 1, 23,2,28,2\t\t' ground (cols 2-29, type 2)",
    "\tDATA BYTE 1, 18,2,4,1\t\t' lower-left ledge (cols 2-5), per the reference\n\tDATA BYTE 1, 23,2,28,2\t\t' ground (cols 2-29, type 2)","row18 ledge")

if crlf: s=s.replace("\n","\r\n")
open(p,"wb").write(s.encode("utf-8")); print("DONE")
