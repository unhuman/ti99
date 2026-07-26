s=open("HARDHAT.bas","rb").read().decode("utf-8")
i=s.find("my = my - 1")
while i!=-1:
    print(repr(s[i-20:i+30])); i=s.find("my = my - 1",i+1)
