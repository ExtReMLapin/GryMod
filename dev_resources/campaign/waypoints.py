"""Waypoints for the baseline: the places on the way to a map's exit that the map's OWN logic makes certain, in the order of the shortest way through them.

A straight line from the player to the exit crosses walls. The route is better described by the places the game itself uses to move the story along:
  * a trigger (trigger_once, trigger_multiple, func_button) whose outputs, directly or through up to three named relays and scenes, reach a story step: an
    "achievement" event of the map's list, or the named input that changes the level;
  * a key weapon lying in the world (or handed over at a trigger): the objectives of the baseline that are weapons.
Each waypoint has a PROOF (the entity, its class, its place and the output that was followed) that is checked against the map; the generated data carries it as a
comment. It is deliberately short: a few certain places, not many guessed ones. Waypoints within 150 units of the start or of the exit are left out (the player
passes them at once), as are too big triggers (the centre of a trigger the size of the level is nowhere) and places within 150 units of an earlier one.

The ORDER is not read from the map: it is the shortest way (straight lines) from the place where the player arrives, through all the waypoints, to the exit. It is a
guess, said so in the docs; the display points at the first waypoint not passed, so a wrong order costs a detour, not a dead end. The place where the player arrives
is the landmark of the way back (the player enters through it), else info_player_start; with neither, the way is free at its start.
"""
import math
import itertools

import baseline

BRUSH_CLASSES = ('trigger_once', 'trigger_multiple', 'func_button')
MAX_EXTENT = 1024        # units: a trigger larger than this on x or y has no useful centre
PASSED = 150             # units: the distance at which the displays count a waypoint as passed
MAX_DEPTH = 3            # relays and scenes between the trigger and the story step
MAX_PER_SINK = 3         # gates kept for one story step
MAX_GATES = 12           # the shortest-way search is exact up to this many


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def _extent(models, kv):
    m = kv.get('model', '')
    if m.startswith('*') and int(m[1:]) < len(models):
        mn, mx = models[int(m[1:])]
        return max(mx[0] - mn[0], mx[1] - mn[1])
    return 0


def _places(ents, models):
    """Entities that can be waypoints: {index: (x, y, z)} for the brush classes, with a usable size."""
    out = {}
    for i, e in enumerate(ents):
        kv = e['kv']
        if kv.get('classname') in BRUSH_CLASSES and _extent(models, kv) <= MAX_EXTENT:
            p = baseline.centre(models, kv)
            if p is not None:
                out[i] = tuple(round(float(a), 2) for a in p)
    return out


def find_gates(ents, models, sinks):
    """The brush triggers that lead to a sink. sinks: names of entities that are story steps (achievement events, a level change input).
    Returns [{'index', 'class', 'pos', 'out': [output, target, input], 'sink', 'depth'}] in the order found (nearest to the step first)."""
    places = _places(ents, models)
    by_target = {}
    for i, e in enumerate(ents):
        for o in e['outs']:
            by_target.setdefault(o[1], []).append((i, o))
    gates, seen = [], set()
    for sink in sinks:
        found = []
        frontier, visited = [(sink, 0)], {sink}
        while frontier:
            name, depth = frontier.pop(0)
            for i, o in by_target.get(name, []):
                if i in places:
                    if i not in seen and len(found) < MAX_PER_SINK:
                        found.append({'index': i, 'class': ents[i]['kv']['classname'], 'pos': places[i], 'out': [o[0], o[1], o[2]], 'sink': sink, 'depth': depth})
                        seen.add(i)
                elif depth < MAX_DEPTH:
                    nm = ents[i]['kv'].get('targetname', '')
                    if nm and nm not in visited:
                        visited.add(nm)
                        frontier.append((nm, depth + 1))
        gates.extend(found)
    return gates


def arrival(ents, models, name):
    """Where the player arrives: the landmark of the way back (a trigger_changelevel that leads to another map and is not the way on is not known here, so any
    landmark named by a changelevel trigger of this map is tried), else info_player_start. None when the map says neither."""
    landmarks = {}
    for e in ents:
        if e['kv'].get('classname') == 'info_landmark' and e['kv'].get('targetname'):
            p = baseline.centre(models, e['kv'])
            if p is not None:
                landmarks[e['kv']['targetname']] = tuple(round(float(a), 2) for a in p)
    return landmarks, [tuple(round(float(a), 2) for a in baseline.centre(models, e['kv'])) for e in ents
                       if e['kv'].get('classname') == 'info_player_start' and baseline.centre(models, e['kv']) is not None]


def start_place(ents, models, name, forward_maps):
    """The arrival point. A landmark that belongs to a trigger_changelevel to a map that is NOT a forward exit is the way back: the player comes in there."""
    landmarks, starts = arrival(ents, models, name)
    for e in ents:
        kv = e['kv']
        if kv.get('classname') == 'trigger_changelevel' and kv.get('map') and kv['map'] != name and kv['map'] not in forward_maps:
            lm = landmarks.get(kv.get('landmark', ''))
            if lm is not None:
                return lm
    return starts[0] if starts else None


def shortest_way(points, start, goal):
    """The order of `points` that makes the shortest way start -> all points -> goal (straight lines). Exact (Held-Karp) up to MAX_GATES points.
    start None: the way may start anywhere. Returns the indices."""
    n = len(points)
    if n <= 1:
        return list(range(n))
    INF = float('inf')
    cost = {}
    parent = {}
    for j in range(n):
        cost[(1 << j, j)] = dist(start, points[j]) if start is not None else 0.0
    for size in range(2, n + 1):
        for combo in itertools.combinations(range(n), size):
            mask = sum(1 << j for j in combo)
            for j in combo:
                prev_mask = mask ^ (1 << j)
                best, arg = INF, None
                for k in combo:
                    if k != j:
                        c = cost[(prev_mask, k)] + dist(points[k], points[j])
                        if c < best - 1e-9:
                            best, arg = c, k
                cost[(mask, j)] = best
                parent[(mask, j)] = arg
    full = (1 << n) - 1
    j = min(range(n), key=lambda j: cost[(full, j)] + dist(points[j], goal))
    order, mask = [], full
    while j is not None:
        order.append(j)
        prev = parent.get((mask, j))
        mask ^= (1 << j)
        j = prev
    return order[::-1]


def waypoints_for_exit(game, name, ents, models, objs, exit_obj, forward_maps, extras=()):
    """The ordered waypoints for one exit objective of the baseline: [{'pos', 'proof', 'note'}] (possibly empty).
    objs: the baseline objectives of the map. extras: proofs (dicts of proofs.py) of own-data waypoints added by hand, checked like the others."""
    goal = tuple(exit_obj['pos'])
    sinks = [o['complete']['entity'] for o in objs if o['rule'] == 'R4_milestone' and o['complete'].get('entity')]
    sinks += [o['complete']['entity'] for o in objs if o['rule'] == 'R1_exit' and o['complete']['kind'] == 'input']
    cands = []
    for g in find_gates(ents, models, sinks):
        cands.append({'pos': g['pos'], 'proof': {'class': g['class'], 'pos': g['pos'], 'out': g['out']},
                      'note': '%s at %s fires %s %s (%d relays away)' % (g['class'], g['pos'], g['out'][1], g['out'][2], g['depth'])})
    for o in objs:
        if o['rule'] in ('R2_weapon', 'R2b_give') and o.get('pos') is not None:
            p = tuple(round(float(a), 2) for a in o['pos'])
            cl = o['complete']['class']
            pr = {'class': cl, 'pos': p} if o['rule'] == 'R2_weapon' else {'class': 'trigger_once', 'pos': p}
            cands.append({'pos': p, 'proof': pr, 'note': 'key weapon %s at %s' % (cl, p)})
    for pr in extras:
        # an own-data waypoint chosen by hand: the proof carries its class and place
        cands.append({'pos': tuple(pr['pos']), 'proof': pr, 'note': 'trigger %s at %s that sets other things going' % (pr.get('class'), tuple(pr['pos']))})
    start = start_place(ents, models, name, forward_maps)
    kept = []
    for c in cands:
        if dist(c['pos'], goal) <= PASSED or (start is not None and dist(c['pos'], start) <= PASSED):
            continue
        if any(dist(c['pos'], k['pos']) <= PASSED for k in kept):
            continue
        kept.append(c)
    if len(kept) > MAX_GATES:
        # keep the ones that are far from each other
        chosen = [kept[0]]
        while len(chosen) < MAX_GATES:
            nxt = max((k for k in kept if k not in chosen), key=lambda k: min(dist(k['pos'], c['pos']) for c in chosen))
            chosen.append(nxt)
        kept = chosen
    order = shortest_way([k['pos'] for k in kept], start, goal)
    return [kept[i] for i in order]
