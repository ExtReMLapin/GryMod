"""Offline analysis of the level rules of the minimap on SURVEYS of whole maps (2026-11-22), not only on straight stairs.

A survey (tests/minimap/levels_survey_job.lua, server realm) is every point of a 32-unit grid around the ground nodes of a map's node graph: the feet, the highest ceiling of
the five up rays of Floors.CurrentAt, whether the centre ray sees the sky, the height the centre ray hit, and whether the +x / +y neighbour is reachable (no wall at 36 over the
feet). Two points are NEIGHBOURS when they are 32 apart on the grid, nothing blocks between them and their feet differ by at most 24 (a step).

For each rule (a function of the place only, except "game", the faithful port of the game's rule with its memory, run on random walks), per map:
  levels    distinct levels over the closed points (ceiling within 512, centre not on the sky; the others are the open level for every rule);
  border%   neighbour pairs (both closed) whose levels differ, in % of the closed pairs: what the player crosses as a change of level;
  flat%     the same among the pairs with the same floor (feet within 1): changes of level on a flat floor, caused by the ceiling alone;
  split     flat-floor regions (points linked by neighbours with feet within 2) that get more than one level, weighted by points, in %;
  walk      changes of level per 1000 units of random walk over the neighbours (the game's port has memory: only this column means something for it);
  feet/head/cut   points where the feet are under the slab + 8, the head (feet + 72) over its top, the top over the ceiling the CENTRE ray hit (the spot under the player hidden by it).
Run:  python dev_resources/level_survey_analysis.py <folder of the <map>.txt surveys>
"""
import collections
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import level_rule_experiment as X  # noqa: E402  (the port of the game's rule)


def load(path):
    pts = []
    for line in open(path):
        v = line.split()
        if len(v) < 8:
            continue
        x, y = int(v[0]), int(v[1])
        f, c, op, ch, ox, oy = float(v[2]), float(v[3]), int(v[4]), float(v[5]), int(v[6]), int(v[7])
        pts.append((x, y, f, c, op, ch, ox, oy))
    return pts


def closed(p):
    x, y, f, c, op, ch, ox, oy = p
    return c > -90000 and c - f <= 512 and not op


# ---------------------------------------------------------------------------------------------------------------------------------------
# rules: (f, c) -> (id, zlo, zhi); only asked for closed points

def r_fresh(f, c):
    a = math.floor(f / 16 + 0.5) * 16
    k = X.class_for(a, c)
    return ("f%dc%d" % (a, k), a - 56, a + k)


def make_ceiling(grids, classes, fine=8, head=72, gap=8):
    """top = (ceiling - gap) floored to the first grid of `grids` that keeps the head (feet + head) under it, else to `fine`; thickness = the smallest of `classes` that holds the
    feet (8 over the bottom), else the biggest."""
    def rule(f, c):
        top = None
        for g in grids:
            t = math.floor((c - gap) / g) * g
            if t >= f + head:
                top = t
                break
        if top is None:
            top = math.floor((c - gap) / fine) * fine
        need = top - (f - 8)
        t = next((k for k in classes if k >= need), classes[-1])
        return ("c%dt%d" % (top, t), top - t, top)
    return rule


def make_dyadic(classes, head=72, gap=8):
    """top = the 'roundest' height in [feet + head, ceiling - gap] (the multiple of the biggest power of two in it); empty interval: ceiling - gap floored to 8."""
    def rule(f, c):
        lo, hi = f + head, c - gap
        top = None
        if hi >= lo:
            g = 1024
            while g >= 8:
                t = math.floor(hi / g) * g
                if t >= lo:
                    top = t
                    break
                g //= 2
        if top is None:
            top = math.floor(hi / 8) * 8
        need = top - (f - 8)
        t = next((k for k in classes if k >= need), classes[-1])
        return ("c%dt%d" % (top, t), top - t, top)
    return rule


RULES = [
    ("fresh(now)", r_fresh),
    ("cand64", make_ceiling([64], [320, 576])),
    ("cand96", make_ceiling([96], [320, 576])),
    ("g64/32", make_ceiling([64, 32], [320, 576])),
    ("g64/32/16", make_ceiling([64, 32, 16], [320, 576])),
    ("g128/64/32", make_ceiling([128, 64, 32], [320, 576])),
    ("g64/32 t576", make_ceiling([64, 32], [576])),
    ("dyadic", make_dyadic([320, 576])),
]


def neighbours(pts):
    """index pairs (i, j) of neighbours, and the length of each link (32)."""
    by = collections.defaultdict(list)
    for i, p in enumerate(pts):
        by[(p[0], p[1])].append(i)
    pairs = []
    for i, p in enumerate(pts):
        x, y, f = p[0], p[1], p[2]
        for dx, dy, ok in ((32, 0, p[6]), (0, 32, p[7])):
            if not ok:
                continue
            for j in by.get((x + dx, y + dy), ()):
                if abs(pts[j][2] - f) <= 24:
                    pairs.append((i, j))
    return pairs


def components(n, pairs):
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for i, j in pairs:
        a, b = find(i), find(j)
        if a != b:
            parent[a] = b
    return [find(i) for i in range(n)]


def walks(pts, adj, levels_of, count=200, length=400, seed=7):
    """random walks over the neighbours of closed points; levels_of(path) -> list of level ids; changes per 1000 units."""
    rnd = random.Random(seed)
    starts = [i for i in range(len(pts)) if adj[i]]
    if not starts:
        return 0.0
    changes, dist = 0, 0
    for _ in range(count):
        i = rnd.choice(starts)
        path, prev = [i], None
        for _ in range(length):
            nxt = [j for j in adj[i] if j != prev] or adj[i]
            prev, i = i, rnd.choice(nxt)
            path.append(i)
        ids = levels_of(path)
        changes += sum(1 for a, b in zip(ids, ids[1:]) if a is not None and b is not None and a != b)
        dist += 32 * (len(path) - 1)
    return 1000.0 * changes / dist


BLOCK = 256


def display_hold(pts, lv):
    """The DISPLAY keeps the level it shows while that level is still right for the place (feet 8 over its bottom, head under its top unless the place's own level cuts it too,
    top under the highest ceiling - 8) and its tiles can be there (proxy: the level is the place's own level of a point within one block of 256 units, i.e. the preload made it);
    else it shows the place's own level. Only the places' own levels are ever made."""
    built = collections.defaultdict(set)
    for k, p in enumerate(pts):
        if lv[k]:
            bx, by = p[0] // BLOCK, p[1] // BLOCK
            for ix in (-1, 0, 1):
                for iy in (-1, 0, 1):
                    built[(bx + ix, by + iy)].add(lv[k][0])

    def run(path):
        out, shown = [], None
        for i in path:
            p, own = pts[i], lv[i]
            if own is None:
                shown = None
                out.append(None)
                continue
            f, c = p[2], p[3]
            if shown is not None:
                _, zlo, zhi = shown
                ok = zlo <= f - 8 and (zhi >= f + 72 or own[2] < f + 72) and zhi <= c - 8 and shown[0] in built[(p[0] // BLOCK, p[1] // BLOCK)]
                if not ok:
                    shown = None
            if shown is None:
                shown = own
            out.append(shown[0])
        return out
    return run


def game_walk_levels(pts):
    def run(path):
        g = X.Game()
        now = 1000.0
        out = []
        for i in path:
            x, y, f, c, op, ch, ox, oy = pts[i]
            now += 32 / 190.0  # walking speed of a player, 190 units/s
            if not closed(pts[i]):
                g.last = None if g.last is None else g.last
            lv = g.at(x, y, f, None if c < -90000 else c, bool(op), now)
            out.append(lv["id"])
        return out
    return run


def analyse(path):
    pts = load(path)
    name = os.path.basename(path)[:-4]
    cl = [closed(p) for p in pts]
    pairs = [(i, j) for i, j in neighbours(pts)]
    cpairs = [(i, j) for i, j in pairs if cl[i] and cl[j]]
    flatpairs = [(i, j) for i, j in cpairs if abs(pts[i][2] - pts[j][2]) <= 1]
    regpairs = [(i, j) for i, j in cpairs if abs(pts[i][2] - pts[j][2]) <= 2]
    region = components(len(pts), regpairs)
    adj = [[] for _ in pts]
    for i, j in cpairs:
        adj[i].append(j)
        adj[j].append(i)
    print("\n%s: %d points, %d closed, %d closed neighbour pairs (%d on a flat floor)" % (name, len(pts), sum(cl), len(cpairs), len(flatpairs)))
    print("  %-12s %6s %8s %7s %7s %7s %7s %6s %6s %6s" % ("rule", "levels", "border%", "flat%", "split%", "walk", "hold", "feet", "head", "cut"))
    gw = walks(pts, adj, game_walk_levels(pts))
    print("  %-12s %6s %8s %7s %7s %7.2f %7s %6s %6s %6s" % ("game(memory)", "-", "-", "-", "-", gw, "-", "-", "-", "-"))
    out = {}
    for rname, rule in RULES:
        lv = [rule(p[2], p[3]) if cl[k] else None for k, p in enumerate(pts)]
        ids = set(l[0] for l in lv if l)
        border = sum(1 for i, j in cpairs if lv[i][0] != lv[j][0])
        flat = sum(1 for i, j in flatpairs if lv[i][0] != lv[j][0])
        reg = collections.defaultdict(set)
        regn = collections.Counter()
        for k in range(len(pts)):
            if lv[k]:
                reg[region[k]].add(lv[k][0])
                regn[region[k]] += 1
        split = sum(regn[r] for r in reg if len(reg[r]) > 1)
        feet = head = cut = 0
        for k, p in enumerate(pts):
            if not lv[k]:
                continue
            _, zlo, zhi = lv[k]
            f, ch = p[2], p[5]
            if zlo > f - 8:
                feet += 1
            if zhi < f + 72:
                head += 1
            if ch > -90000 and zhi > ch - 1:
                cut += 1
        w = walks(pts, adj, lambda path: [lv[i][0] if lv[i] else None for i in path])
        wh = walks(pts, adj, display_hold(pts, lv))
        nclosed = max(1, sum(regn.values()))
        print("  %-12s %6d %8.2f %7.2f %7.1f %7.2f %7.2f %6d %6d %6d" % (rname, len(ids), 100.0 * border / max(1, len(cpairs)), 100.0 * flat / max(1, len(flatpairs)),
                                                                 100.0 * split / nclosed, w, wh, feet, head, cut))
        out[rname] = (len(ids), border, len(cpairs), flat, len(flatpairs), w, wh)
    return out


def main():
    folder = sys.argv[1]
    total = collections.defaultdict(lambda: [0, 0, 0, 0, 0, 0.0, 0.0])
    for fn in sorted(os.listdir(folder)):
        if fn.endswith(".txt") and os.path.getsize(os.path.join(folder, fn)) > 0:
            for k, v in analyse(os.path.join(folder, fn)).items():
                t = total[k]
                for a in range(5):
                    t[a] += v[a]
                t[5] += v[5]
                t[6] += v[6]
    print("\nALL MAPS: rule, levels (summed), border %, flat %, walk, hold (sums of the maps' changes per 1000 units; hold = with the display hold)")
    for k, t in total.items():
        print("  %-12s %6d %8.2f %7.2f %7.2f %7.2f" % (k, t[0], 100.0 * t[1] / max(1, t[2]), 100.0 * t[3] / max(1, t[4]), t[5], t[6]))


if __name__ == "__main__":
    main()
