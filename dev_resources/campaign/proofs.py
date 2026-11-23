"""The proof checker: a curated objective says things about a map (an entity of this class and name stands there, it sends this output to that target...).
Each one is a `proof` dict, checked against the entities read from the map. A proof that no entity satisfies is FALSE and the build stops.

proof keys (all optional, all must hold for one entity):
  class  the classname
  name   the targetname
  pos    (x, y, z): the origin, or the centre of the brush model, within 1.5 units
  kv     {key: value}: key values that must be exactly these
  out    [output, target, input]: the entity has this output
"""


def where(models, kv):
    """The place of an entity: its origin, or the centre of its brush model; None when it has neither."""
    if 'origin' in kv:
        return [float(v) for v in kv['origin'].split()]
    m = kv.get('model', '')
    if m.startswith('*') and int(m[1:]) < len(models):
        mn, mx = models[int(m[1:])]
        return [(a + c) / 2 for a, c in zip(mn, mx)]
    return None


def check(proof, ents, models):
    """The entities that satisfy the proof (an empty list: the proof is false)."""
    found = []
    for x in ents:
        kv = x['kv']
        if 'class' in proof and kv.get('classname') != proof['class']:
            continue
        if 'name' in proof and kv.get('targetname') != proof['name']:
            continue
        if 'kv' in proof and any(kv.get(k) != v for k, v in proof['kv'].items()):
            continue
        if 'pos' in proof:
            p = where(models, kv)
            if p is None or any(abs(a - b) > 1.5 for a, b in zip(p, proof['pos'])):
                continue
        if 'out' in proof and not any(o[0] == proof['out'][0] and o[1] == proof['out'][1] and o[2] == proof['out'][2] for o in x['outs']):
            continue
        found.append(x)
    return found


def check_all(objectives, ents, models):
    """[(objective id, proof, True or False)] for every proof of every objective."""
    results = []
    for o in objectives:
        for pr in o.get('proof', []):
            results.append((o['id'], pr, len(check(pr, ents, models)) >= 1))
    return results
