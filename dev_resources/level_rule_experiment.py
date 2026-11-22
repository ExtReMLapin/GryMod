"""Offline experiment on the level rule of the minimap floors (2026-11-22), on the recorded stairs (tests/minimap/fixtures/*_stairs.lua), with no game.

Question: can the level of a place be a function of the feet and the ceiling ONLY (no memory of the path, so that the tile preload can predict it) with far fewer levels than
"feet rounded to 16 + class of the ceiling"? Rule tried, "ceiling anchored": the slab ends under the ceiling (top = highest ceiling - 8, rounded down to a step of 16 or 32) and its
thickness is the smallest class that holds the feet (thickness >= top - feet + 8). Counted per recorded stretch and over all of them; the head is checked (top >= feet + 72).
Run:  python dev_resources/level_rule_experiment.py
"""
import glob
import os
import re, math, collections
R = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tests", "minimap", "fixtures")
def load(path):
    txt = open(path, encoding="utf-8").read()
    out = {}
    for m in re.finditer(r"\n\t(\w+) = \{\n(.*?)\n\t\},", txt, re.S):
        out[m.group(1)] = [[float(v) for v in g] for g in (re.findall(r"-?\d+\.?\d*", s) for s in re.findall(r"\{([^{}]*)\}", m.group(2)))]
    return out
fx = {}
for path in sorted(glob.glob(os.path.join(R, "*_stairs.lua"))):
    fx.update(load(path))
print({k: len(v) for k, v in fx.items()})

def ceilings_ok(rows): return [(r[2], r[3]) for r in rows if r[3] > -90000 and r[3] - r[2] <= 512 and not r[4]]

def rule_c(f, c, qtop, classes):
    top = math.floor((c - 8) / qtop) * qtop
    need = top - (f - 8)
    T = next((k for k in classes if k >= need), None)
    return top, T

def evaluate(qtop, classes, label):
    print("== %s (top rounded down to %d, thickness classes %s)" % (label, qtop, classes))
    tot = set()
    for k, rows in fx.items():
        pts = ceilings_ok(rows)
        lv = set(); viol = collections.Counter()
        for f, c in pts:
            if c - f < 80:  # a duct: no room for a head, left to the old rule
                viol["duct (old rule)"] += 1; continue
            top, T = rule_c(f, c, qtop, classes)
            if T is None: viol["thicker than the biggest class"] += 1; continue
            lv.add((top, T))
            if top < f + 72: viol["head over the slab"] += 1
        tot |= lv
        print("  %-24s closed %3d  levels %2d  %s" % (k, len(pts), len(lv), dict(viol) or ""))
    print("  all together:", len(tot), "levels")
evaluate(16, [128, 192, 256, 320, 384, 448, 512, 576], "A")
evaluate(32, [128, 192, 256, 320, 384, 448, 512, 576], "B")
evaluate(16, [160, 256, 384, 576], "C coarse thickness")
evaluate(32, [160, 256, 384, 576], "D coarse thickness and top")

print("\n== the current rule without any memory (A = feet rounded to 16, class by the ceiling), the same samples: the number of distinct levels")
CL = [448, 320, 224, 160, 120, 88, 56]
tot = set()
for k, rows in fx.items():
    lv = set()
    for f, c in ceilings_ok(rows):
        A = math.floor(f / 16 + 0.5) * 16
        room = c - A - 8
        C = next((x for x in CL if x <= room), 56)
        lv.add((A, C))
    tot |= lv
    print("  %-24s levels %2d" % (k, len(lv)))
print("  all together:", len(tot), "levels")
