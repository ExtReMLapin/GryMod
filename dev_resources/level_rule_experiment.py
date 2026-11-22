"""Offline experiment on the level rule of the minimap floors (2026-11-22), on every recorded stairs or ramp (tests/minimap/fixtures/*_stairs.lua), with no game.

Question: can the level of a place be a function of the feet and the ceiling ONLY (no memory of the path, so that the tile preload can predict it) with far fewer levels than the rule
of the game, and is it still correct for the player?

Rules compared, on every recorded stretch (the positions every 12 units, the feet on the ground, the highest ceiling the five up rays hit):
  * "game": a faithful port of Floors.CurrentAt (anchors f<A>c<C>, the registry of known anchors, the window of the feet 36 under / class - 72 over, the class held for one second before it goes
    up, a shot every 48 units or every second). It has MEMORY: its answer depends on the path.
  * "fresh": the same ids with no memory at all (A = feet rounded to 16, the class that fits under the ceiling): the upper bound of what a rule without memory gives.
  * "ceiling": a slab that ends under the ceiling (top = highest ceiling - 8, rounded down to a step) whose thickness is the smallest class that holds the feet. No memory.
For each: the distinct levels, the changes of level along the path, and the positions where the player would not be inside the slab (feet less than 8 over the bottom, head less than 72 under
the top). The positions with the open sky or a ceiling over 512 are the open level for every rule and are left out of the counts.
Run:  python dev_resources/level_rule_experiment.py
"""
import collections
import glob
import math
import os
import random
import re

R = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests", "minimap", "fixtures")
CLASSES = [448, 320, 224, 160, 120, 88, 56]


def load(path):
    txt = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\n\t(\w+) = \{\n(.*?)\n\t\},", txt, re.S):
        out[m.group(1)] = [[float(v) for v in g] for g in (re.findall(r"-?\d+\.?\d*", s) for s in re.findall(r"\{([^{}]*)\}", m.group(2)))]
    return out


def is_closed(r):
    x, y, f, c, centre_open, sky = r
    return c > -90000 and c - f <= 512 and not centre_open


# ---------------------------------------------------------------------------------------------------------------------------------
# the game's rule (port of floors.lua: usable, classFor, chooseAnchor, CurrentAt)
def class_for(a, c):
    room = c - a - 8
    return next((k for k in CLASSES if k <= room), 56)


def usable(level, f, c):
    a, k = level["fz"], level["cls"]
    above = 40
    if k != 56 and k - 72 > above:
        above = k - 72
    if a - 36 > f or f > a + above:
        return False
    return k == 56 or (a + k >= f + 72 and k <= c - a - 8)


class Game:
    def __init__(self):
        self.anchors = []
        self.last = None  # {x, y, z, t, level, since}

    def add(self, a, k):
        for l in self.anchors:
            if l["fz"] == a and l["cls"] == k:
                return l
        l = {"fz": a, "cls": k, "id": "f%dc%d" % (a, k)}
        self.anchors.append(l)
        return l

    def choose(self, f, c, now):
        last = self.last
        cur = last["level"] if last else None
        if cur is not None and cur.get("fz") is not None and usable(cur, f, c):
            better = class_for(cur["fz"], c)
            if better <= cur["cls"]:
                return cur, None
            since = last["since"] if last["since"] is not None else now
            if now - since >= 1:
                return self.add(cur["fz"], better), None
            return cur, since
        best = None
        for l in self.anchors:
            if usable(l, f, c):
                if best is None or l["cls"] > best["cls"] or (l["cls"] == best["cls"] and abs(l["fz"] - f) < abs(best["fz"] - f)):
                    best = l
        if best:
            return best, None
        a = math.floor(f / 16 + 0.5) * 16
        return self.add(a, class_for(a, c)), None

    def at(self, x, y, f, c, centre_open, now):
        last = self.last
        if last and now - last["t"] < 1:
            if (x - last["x"]) ** 2 + (y - last["y"]) ** 2 + (f - last["z"]) ** 2 <= 48 * 48:
                return last["level"]
        if centre_open or c is None or c - f > 512:
            level, since = {"id": "open", "fz": None}, None
        else:
            level, since = self.choose(f, c, now)
        self.last = {"x": x, "y": y, "z": f, "t": now, "level": level, "since": since}
        return level


def game_rule(rows, seed=1):
    g = Game()
    rnd = random.Random(seed)
    now = 1000.0
    out = []
    for x, y, f, c, centre_open, sky in rows:
        now += 0.1 + rnd.uniform(-0.002, 0.002)  # 12 units per 0.1 s = 120 units/s, never exactly 0.1 s (the threshold of one second)
        cc = None if c < -90000 else c
        level = g.at(x, y, f, cc, bool(centre_open), now)
        if level["id"] == "open":
            out.append(None)
        else:
            out.append((level["id"], level["fz"] - 56, level["fz"] + level["cls"]))
    return out


def fresh_rule(rows):
    out = []
    for x, y, f, c, centre_open, sky in rows:
        if centre_open or c < -90000 or c - f > 512:
            out.append(None)
            continue
        a = math.floor(f / 16 + 0.5) * 16
        k = class_for(a, c)
        out.append(("f%dc%d" % (a, k), a - 56, a + k))
    return out


def ceiling_rule(rows, step, classes):
    out = []
    for x, y, f, c, centre_open, sky in rows:
        if centre_open or c < -90000 or c - f > 512:
            out.append(None)
            continue
        top = math.floor((c - 8) / step) * step
        need = top - (f - 8)
        t = next((k for k in classes if k >= need), None)
        if t is None:
            out.append(("too thick", f - 8, c - 8))
            continue
        out.append(("c%dt%d" % (top, t), top - t, top))
    return out


def ceiling_rule_fine(rows, step, classes, off=0, fine=8):
    """The ceiling rule with a coarse grid for the top of the slab (step 64 or 96) and a finer top (8) only where the coarse one would put the head over the slab."""
    out = []
    for x, y, f, c, centre_open, sky in rows:
        if centre_open or c < -90000 or c - f > 512:
            out.append(None)
            continue
        top = math.floor((c - 8 - off) / step) * step + off
        if top < f + 72:
            top = math.floor((c - 8) / fine) * fine
        need = top - (f - 8)
        t = next((k for k in classes if k >= need), classes[-1])
        out.append(("c%dt%d" % (top, t), top - t, top))
    return out


def measure(rows, levels):
    ids, changes, viol = set(), 0, collections.Counter()
    prev = None
    for (x, y, f, c, centre_open, sky), lv in zip(rows, levels):
        if lv is None:
            prev = None
            continue
        lid, zlo, ztop = lv
        ids.add(lid)
        if prev is not None and prev != lid:
            changes += 1
        prev = lid
        if zlo > f - 8:
            viol["feet"] += 1
        if ztop < f + 72 and not (ztop - zlo <= 56 + 8):
            viol["head"] += 1
    return len(ids), changes, viol


def main():
    fx = {}
    for path in sorted(glob.glob(os.path.join(R, "*_stairs.lua"))):
        fx.update(load(path))
    variants = [
        ("ceil 16/8cl", lambda rows: ceiling_rule(rows, 16, [128, 192, 256, 320, 384, 448, 512, 576])),
        ("ceil 16/4cl", lambda rows: ceiling_rule(rows, 16, [160, 256, 384, 576])),
        ("ceil 32/4cl", lambda rows: ceiling_rule(rows, 32, [160, 256, 384, 576])),
        ("ceil 96/320,576", lambda rows: ceiling_rule_fine(rows, 96, [320, 576])),
        ("ceil 64/320,576", lambda rows: ceiling_rule_fine(rows, 64, [320, 576])),
    ]
    names = ["game(memory)", "fresh"] + [v[0] for v in variants]
    totals = {n: [set(), 0, collections.Counter()] for n in names}
    print("%-24s %4s %4s | %s" % ("stretch (levels / changes)", "all", "clsd", " | ".join("%-15s" % n for n in names)))
    for key, rows in fx.items():
        closed = sum(1 for r in rows if is_closed(r))
        cells = []
        results = [game_rule(rows), fresh_rule(rows)] + [v[1](rows) for v in variants]
        for n, lv in zip(names, results):
            nl, ch, viol = measure(rows, lv)
            cells.append("%3d /%4d%s" % (nl, ch, "!" if viol else " "))
            for l in lv:
                if l is not None:
                    totals[n][0].add((key, l[0]))
            totals[n][1] += ch
            totals[n][2].update(viol)
        print("%-24s %4d %4d | %s" % (key, len(rows), closed, " | ".join("%-15s" % c for c in cells)))
    print("\nTOTAL over all stretches (distinct levels per stretch summed, changes of level along the paths, positions outside the slab; ! = a position outside the slab):")
    for n in names:
        ids, ch, viol = totals[n]
        print("  %-14s %4d levels  %5d changes  violations %s" % (n, len(ids), ch, dict(viol) or "none"))


if __name__ == "__main__":
    main()
