"""Read entity lumps of Source .bsp files (offline). Keeps every key, including repeated output keys.
Entity = dict(kv: {key: value}, outs: [(output, target, input, param, delay, once)])."""
import struct, re, os, glob
# The game's own maps are read, never copied: the folder is the Half-Life 2 install (set GRYMOD_HL2_DIR for another place).
HL2_DIR = os.environ.get('GRYMOD_HL2_DIR', r'D:\SteamLibrary\steamapps\common\Half-Life 2')
ROOTS = {
 'hl2': os.path.join(HL2_DIR, 'hl2', 'maps'),
 'ep1': os.path.join(HL2_DIR, 'episodic', 'maps'),
 'ep2': os.path.join(HL2_DIR, 'ep2', 'maps'),
}
TOK = re.compile(r'"([^"]*)"|([{}])')
OUTKEYS_HINT = re.compile(r'^(On|Pressed|Out|Fire|Trigger|Position|Reload|Cycle)', re.I)

def read_ents(path):
    d = open(path, 'rb').read()
    ident, ver = struct.unpack_from('<4si', d, 0)
    if ident != b'VBSP': raise ValueError('not VBSP')
    ofs, ln, lv, fcc = struct.unpack_from('<iiii', d, 8)
    if fcc: raise ValueError('compressed lump')
    txt = d[ofs:ofs+ln].decode('latin1')
    out = []; cur = None; key = None
    for m in TOK.finditer(txt):
        s, b = m.groups()
        if b == '{': cur = {'kv': {}, 'outs': []}; key = None
        elif b == '}': out.append(cur); cur = None
        elif cur is not None:
            if key is None: key = s
            else:
                val = s
                parts = val.replace('\x1b', ',').split(',')
                if len(parts) == 5 or len(parts) == 6 and False:
                    pass
                # an output has 5 comma fields: target,input,param,delay,once
                if len(parts) == 5 and re.fullmatch(r'-?[\d.]+', parts[3] or 'x') and re.fullmatch(r'-?\d+', parts[4] or 'x') and key not in ('origin','angles','rendercolor'):
                    cur['outs'].append((key, parts[0], parts[1], parts[2], float(parts[3]), int(parts[4])))
                else:
                    cur['kv'].setdefault(key, val)
                key = None
    return out

def read_models(path):
    """brush model bounds: list of (mins, maxs) indexed by '*N' (lump 14, 48 bytes each)."""
    d = open(path, 'rb').read()
    ofs, ln = struct.unpack_from('<ii', d, 8 + 14 * 16)
    out = []
    for i in range(ln // 48):
        v = struct.unpack_from('<9f', d, ofs + i * 48)
        out.append((v[0:3], v[3:6]))
    return out

def all_maps():
    res = {}
    for ep, root in ROOTS.items():
        for p in sorted(glob.glob(os.path.join(root, '*.bsp'))):
            name = os.path.basename(p)[:-4]
            if os.path.getsize(p) == 0: continue
            try: res[(ep, name)] = read_ents(p)
            except Exception as e: print('ERR', p, e)
    return res
