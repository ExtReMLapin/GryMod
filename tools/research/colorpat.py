import re, os, collections
pat = collections.Counter()
where = collections.defaultdict(list)
for root, dirs, files in os.walk('.'):
    for f in files:
        if not f.endswith('.as'):
            continue
        t = open(os.path.join(root, f), encoding='utf8').read()
        if 'new Color' not in t:
            continue
        norm = re.sub(r'\s+', ' ', t).strip()
        pat[norm] += 1
        where[norm].append(root.replace(chr(92), '/'))
for k, n in pat.most_common(14):
    print(n, k[:430])
    print('   e.g.', where[k][:3])
    print()
print('distinct', len(pat))
