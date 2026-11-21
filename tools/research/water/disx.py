import struct,sys,capstone
p=r"C:\Program Files (x86)\Electronic Arts\Crytek\Crysis SP Demo\Bin32\CryGame.dll"
d=open(p,'rb').read()
pe=struct.unpack('<I',d[0x3c:0x40])[0]
nsec=struct.unpack('<H',d[pe+6:pe+8])[0]; osz=struct.unpack('<H',d[pe+20:pe+22])[0]
base=struct.unpack('<I',d[pe+24+28:pe+24+32])[0]
secs=[]
o=pe+24+osz
for i in range(nsec):
    nm=d[o:o+8].strip(b'\0');vs,va,rs,ro=struct.unpack('<4I',d[o+8:o+24]);secs.append((nm,va,vs,ro,rs));o+=40
def off(a):
    r=a-base
    for nm,va,vs,ro,rs in secs:
        if va<=r<va+max(vs,rs): return ro+r-va
def rd(a,n): 
    o=off(a); return d[o:o+n]
def dis(a,n):
    md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_32)
    for i in md.disasm(rd(a,n),a): yield i
if __name__=='__main__':
    print(hex(base),[(s[0],hex(s[1])) for s in secs][:4])
    a=int(sys.argv[1],16); n=int(sys.argv[2],16)
    for i in dis(a,n): print('%x: %s %s'%(i.address,i.mnemonic,i.op_str))
