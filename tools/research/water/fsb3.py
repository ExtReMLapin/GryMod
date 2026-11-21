import struct,sys,wave
def read_fsb(path):
    d=open(path,'rb').read()
    assert d[:4]==b'FSB3'
    n,shdr,dsz,ver,mode=struct.unpack('<5I',d[4:24])
    off=24; samples=[]; pos=24+shdr
    for i in range(n):
        sz=struct.unpack('<H',d[off:off+2])[0]
        name=d[off+2:off+32].split(b'\0')[0].decode('latin1')
        length,comp,ls,le,smode,freq=struct.unpack('<6I',d[off+32:off+56])
        defvol,defpan,defpri,ch=struct.unpack('<HhHH',d[off+56:off+64])
        samples.append(dict(i=i,name=name,len=length,bytes=comp,mode=smode,freq=freq,ch=ch,off=pos,vol=defvol))
        pos+=comp; off+=sz
    return d,samples
STEP=[7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767]
IDX=[-1,-1,-1,-1,2,4,6,8]
def dec_block(b, hdr_sample):
    pred=struct.unpack('<h',b[0:2])[0]; idx=min(88,b[2]); out=[pred] if hdr_sample else []
    for byte in b[4:]:
        for nib in (byte&15, byte>>4):
            st=STEP[idx]; diff=st>>3
            if nib&1: diff+=st>>2
            if nib&2: diff+=st>>1
            if nib&4: diff+=st
            if nib&8: diff=-diff
            pred=max(-32768,min(32767,pred+diff)); idx=max(0,min(88,idx+IDX[nib&7]))
            out.append(pred)
    return out
def decode(d,s,hdr_sample=True,inter=4):
    ch=s['ch']; data=d[s['off']:s['off']+s['bytes']]
    chans=[[] for _ in range(ch)]
    bs=36*ch
    for p in range(0,len(data)-bs+1,bs):
        blk=data[p:p+bs]
        if ch==1: parts=[blk]
        else:
            # per-channel header (4 bytes each) then interleaved groups of `inter` bytes
            parts=[]
            for c in range(ch):
                hdr=blk[c*4:c*4+4]
                body=b''.join(blk[ch*4+g*inter*ch+c*inter: ch*4+g*inter*ch+c*inter+inter] for g in range((32)//inter))
                parts.append(hdr+body)
        for c in range(ch): chans[c]+=dec_block(parts[c],hdr_sample)[:64]
    return chans
def write_wav(path,chans,freq):
    n=min(len(c) for c in chans)
    w=wave.open(path,'wb'); w.setnchannels(len(chans)); w.setsampwidth(2); w.setframerate(freq)
    fr=bytearray()
    for i in range(n):
        for c in chans: fr+=struct.pack('<h',c[i])
    w.writeframes(bytes(fr)); w.close()
if __name__=='__main__':
    d,ss=read_fsb(sys.argv[1])
    flt=sys.argv[2].lower() if len(sys.argv)>2 else ''
    for s in ss:
        if flt in s['name'].lower(): print(s['i'],s['name'],s['freq'],s['ch'],s['len'],hex(s['mode']),'%.2fs'%(s['len']/s['freq']))
