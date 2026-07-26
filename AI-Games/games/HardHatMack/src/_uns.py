p="HARDHAT.bas"
raw=open(p,"rb").read().decode("utf-8"); crlf="\r\n" in raw
s=raw.replace("\r\n","\n")
def rep(old,new,tag):
    global s
    n=s.count(old); assert n==1,"%s: %d"%(tag,n)
    s=s.replace(old,new); print("ok:",tag)

rep("\tded = 0\n\tfd2 = my - fcy\n\tIF fd2 > FATALFALL THEN\n\t\tGOSUB mack_die\n\t\tded = 1\n\tEND IF\n\tRETURN",
    "\tded = 0\n\t' UNSIGNED GUARD (CVBasic has no negative math): landing HIGHER than\n\t' the apex -- jumping UP onto a conveyor/beam from beside or below --\n\t' makes my < fcy, and my - fcy wraps to a huge value that sails past\n\t' FATALFALL. That killed every upward landing on the belt.\n\tIF my > fcy THEN\n\t\tfd2 = my - fcy\n\t\tIF fd2 > FATALFALL THEN\n\t\t\tGOSUB mack_die\n\t\t\tded = 1\n\t\tEND IF\n\tEND IF\n\tRETURN",
    "land_chk unsigned guard")

rep("fall_land:\n\tfd2 = my - fcy\n\tIF fd2 > FATALFALL THEN",
    "fall_land:\n\t' Same unsigned guard as land_chk: a catch that snaps Mack UPWARD\n\t' (elevator rising into him) would otherwise wrap the subtraction.\n\tfd2 = 0\n\tIF my > fcy THEN fd2 = my - fcy\n\tIF fd2 > FATALFALL THEN",
    "fall_land unsigned guard")

# the jump solid-landing check (added earlier inline) needs the same guard
rep("\t\t\t\t\tfd2 = my - fcy\n\t\t\t\t\tIF fd2 > FATALFALL THEN",
    "\t\t\t\t\tfd2 = 0\n\t\t\t\t\tIF my > fcy THEN fd2 = my - fcy\n\t\t\t\t\tIF fd2 > FATALFALL THEN",
    "jump solid-landing guard")

if crlf: s=s.replace("\n","\r\n")
open(p,"wb").write(s.encode("utf-8")); print("DONE")
