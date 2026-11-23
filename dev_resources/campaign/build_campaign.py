"""Builds the campaign data files of GryMod: lua/grymod/campaign/<game>/<map>.lua, one for each map of Half-Life 2, Episode One and Episode Two that has
something to say.

    python dev_resources/campaign/build_campaign.py            writes the files
    python dev_resources/campaign/build_campaign.py --check    writes nothing; exit 1 when a file on disk is not what the maps give (and for a false proof)

Where the data comes from:
  * the BASELINE: rules (baseline.py) applied to the entity lump of each map, read from the game's own .bsp files (HL2_DIR, see bsp_ents.py). The maps
    are only read; they are never copied or shipped, and the generated Lua holds facts (names, positions, outputs) and texts of our own.
  * the CURATED maps (curated.py): written by hand, each with PROOFS (proofs.py) that this script checks against the map. A false proof stops the build.
    A curated map replaces the baseline of the same map completely. Every proof is written above its objective in the data file.
The baseline finds every way out of a map, the weapons, the vehicles and the story steps that the game itself marks (its "achievement" events). It
does not find the story steps made of doors, scenes and relays: that is what the curated maps are for (about half of the hand-made objectives
are found by the baseline, the exits first).
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import baseline  # noqa: E402
import bsp_ents as B  # noqa: E402
import curated  # noqa: E402
import emit_lua  # noqa: E402
import proofs  # noqa: E402
import waypoints  # noqa: E402
from extra_waypoints import EXTRA  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
OUT_DEFAULT = os.path.join(REPO, 'lua', 'grymod', 'campaign')


def read_maps(roots=None):
    """{(game, map): (entities, models)} for the campaign maps that can be read."""
    roots = roots or B.ROOTS
    maps = {}
    for game, root in roots.items():
        for p in sorted(os.listdir(root)):
            if not p.endswith('.bsp'):
                continue
            name = p[:-4]
            path = os.path.join(root, p)
            if baseline.SKIP.search(name) or os.path.getsize(path) == 0:
                continue
            maps[(game, name)] = (B.read_ents(path), B.read_models(path))
    return maps


def _clean(d):
    """A dict without the keys whose value is None or empty."""
    return {k: v for k, v in d.items() if v not in (None, '')}


def baseline_complete(c):
    """The completion of a baseline objective in the shape of the data files."""
    out = {'kind': c['kind']}
    for k in ('class', 'entity', 'target', 'input'):
        if c.get(k):
            out[k] = c[k]
    if c['kind'] in ('pickup', 'enter_vehicle', 'use') and c.get('mapid') is not None:
        out['mapid'] = c['mapid']
    via = c.get('via_input')
    if via and via.get('entity'):
        # a weapon handed over by a map command: the command reaching its entity is another way to finish
        out['also'] = {'kind': 'input', 'entity': via['entity'], 'input': via['input']}
    return out


def vec(p):
    return tuple(round(float(a), 3) for a in p)


def baseline_objective(o, wps=()):
    fields = {
        'id': o['id'], 'title': o['title'], 'description': o['description'], 'primary': o['primary'],
        'exit': True if (o['rule'] == 'R1_exit' and o['complete']['kind'] == 'input') else None,
        'pos': vec(o['pos']), 'complete': baseline_complete(o['complete']),
    }
    if wps:
        fields['via'] = [vec(w['pos']) for w in wps]
    notes = [e.strip() for e in o.get('evidence', [])[:3]]
    for i, w in enumerate(wps, 1):
        notes.append('waypoint %d: %s' % (i, w['note']))
    return {'fields': fields, 'notes': notes}


def secret_objective(s):
    fields = {
        'id': s['id'], 'title': s['title'], 'description': '', 'primary': False, 'secret': True,
        'pos': vec(s['pos']), 'complete': {'kind': 'input', 'entity': s['complete']['entity'], 'input': s['complete']['input']},
    }
    return {'fields': fields, 'notes': [e.strip() for e in s.get('evidence', [])[:2]]}


def curated_complete(c):
    out = {}
    for k, v in c.items():
        if k == 'at':
            v = vec(v)
        elif k == 'also':
            v = curated_complete(v)
        out[k] = v
    return out


def curated_objective(o, results):
    fields = {
        'id': o['id'], 'title': o['title'], 'description': o['description'], 'primary': o['primary'],
        'pos': vec(o['pos']), 'after': o.get('after'),
        'complete': curated_complete(o['complete']),
    }
    if o.get('via'):
        fields['via'] = [vec(p) for p in o['via']]
    if o.get('fail'):
        fields['fail'] = {k: v for k, v in o['fail'].items() if k != 'why'}
    notes = []
    for oid, pr, ok in results:
        if oid == o['id']:
            notes.append('proof %s: %s' % ('true' if ok else 'FALSE', pr))
    if o.get('fail') and o['fail'].get('why'):
        notes.append('fails when: ' + o['fail']['why'])
    return {'fields': fields, 'notes': notes}




def build(maps, derived=None, curated_maps=None):
    """Returns ({(game, map): file text}, report dict). `maps` as read_maps gives it."""
    derived = derived if derived is not None else baseline.derive_all(maps)
    curated_maps = curated_maps if curated_maps is not None else curated.MAPS
    texts, report = {}, {'false_proofs': [], 'objectives': 0, 'secrets': 0, 'fails': 0, 'curated': 0, 'maps': 0, 'unnamed_fail_events': 0, 'waypoints': 0}

    for (game, name), (objs, secrets, fails) in sorted(derived.items()):
        if (game, name) in curated_maps:
            continue
        ents, models = maps[(game, name)]
        entries = []
        for o in objs:
            wps = []
            if o['rule'] == 'R1_exit':
                wps = waypoints.waypoints_for_exit(game, name, ents, models, objs, o, baseline.successors(game, name), EXTRA.get(name, ()))
                for w in wps:
                    if not proofs.check(w['proof'], ents, models):
                        report['false_proofs'].append((name, o['id'], w['proof']))
                report['waypoints'] += len(wps)
            entries.append(baseline_objective(o, wps))
        entries += [secret_objective(s) for s in secrets]
        fail_events = []
        for f in fails:
            if not f['entity']:
                report['unnamed_fail_events'] += 1   # an env_message with no name cannot be listened to
                continue
            fail_events.append({'fields': {'entity': f['entity'], 'input': 'ShowMessage'}, 'note': f['message']})
        if not entries and not fail_events:
            continue
        header = ['%s (%s). Generated by dev_resources/campaign/build_campaign.py from the map: do not edit by hand.' % (name, game),
                  'Texts are ours; names, positions and outputs are facts read from the map. The comments above each objective are what the map says.']
        texts[(game, name)] = emit_lua.emit_map(header, entries, fail_events)
        report['objectives'] += len(objs)
        report['secrets'] += len(secrets)
        report['fails'] += len(fail_events)
        report['maps'] += 1

    for (game, name), d in sorted(curated_maps.items()):
        ents, models = maps[(game, name)]
        results = proofs.check_all(d['objectives'], ents, models)
        for oid, pr, ok in results:
            if not ok:
                report['false_proofs'].append((name, oid, pr))
        entries = [curated_objective(o, results) for o in d['objectives']]
        # the secrets of a curated map are still the baseline's: they are not part of the story
        base = derived[(game, name)]
        entries += [secret_objective(s) for s in base[1]]
        fail_events = [{'fields': {'entity': f['entity'], 'input': f['input']}, 'note': f.get('why')} for f in d['fail_events']]
        header = ['%s (%s). Written by hand (dev_resources/campaign/curated.py). Every proof line below was checked against the map when this file was made.' % (name, game),
                  d['note'], 'Texts are ours; the meaning of each step is deduced from the names and outputs and has to be walked once in the game.']
        texts[(game, name)] = emit_lua.emit_map(header, entries, fail_events)
        report['objectives'] += len(d['objectives'])
        report['secrets'] += len(base[1])
        report['fails'] += len(fail_events)
        report['curated'] += 1
        report['maps'] += 1

    return texts, report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--out', default=OUT_DEFAULT)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args(argv)

    maps = read_maps()
    texts, report = build(maps)
    bad = len(report['false_proofs'])
    for name, oid, pr in report['false_proofs']:
        print('PROOF FAILS', name, oid, pr)

    stale = []
    for (game, name), text in texts.items():
        path = os.path.join(args.out, game, name + '.lua')
        if args.check:
            have = open(path, encoding='utf-8', newline='').read() if os.path.exists(path) else None
            if have != text:
                stale.append(path)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8', newline='\n') as f:
                f.write(text)

    print('%d maps (%d curated), %d objectives, %d secrets, %d fail events; %s' % (
        report['maps'], report['curated'], report['objectives'], report['secrets'], report['fails'],
        'ALL PROOFS TRUE' if not bad else '%d PROOFS FALSE' % bad))
    for p in stale:
        print('differs from the maps:', p)
    return 1 if bad or stale else 0


if __name__ == '__main__':
    sys.exit(main())
