# The fixed area is padded with zeros; find the last non-zero byte to see how
# much of the 24,336-byte cap is actually used.
d = open('RALLYX_b0.bin','rb').read()
last = len(d)
while last > 0 and d[last-1] == 0:
    last -= 1
print("b0 file %d bytes, last non-zero at %d" % (len(d), last))
for name in ('RALLYX_b3.bin','RALLYX_b4.bin'):
    b = open(name,'rb').read()
    l = len(b)
    while l > 0 and b[l-1] == 0:
        l -= 1
    print("%s: %d bytes, used %d" % (name, len(b), l))
