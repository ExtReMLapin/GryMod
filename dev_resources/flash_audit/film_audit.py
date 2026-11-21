"""Audit of a converted Scaleform film (lua/grymod/flash/hud_*.lua) against the original's scripts.

Two checks that the conversion and the hand ports of the HUD did not make, and that would have found the binoculars' vignette:

1. FULL-SCREEN ELEMENTS. Every shape that covers a large part of the stage (a vignette, a tint, a fade) with the chain of named
   clips that holds it, so that each one is looked at on purpose: when does it appear, when does it go, who animates it.
2. SCRIPT STATEMENTS THE FILM CANNOT CARRY. The converted film keeps `stop`, `play`, `gotoAndPlay/Stop` of the clip itself or of a
   direct child, and the colour setters. A statement that reaches another clip (`_root.Root.Alpha.gotoAndPlay("close")`), calls the
   game (`fscommand`) or copies text is dropped: each must be ported by hand, or written down as not needed.

Usage:
  python dev_resources/flash_audit/film_audit.py --scripts D:/dev/crysis-hud-research/research-ui/scripts/HUD_Binoculars/scripts \
      --film lua/grymod/flash/hud_binoculars.lua [--stage 1366 768] [--min-share 0.35]

`--scripts` is the folder FFDec writes with `-export script` (DefineSprite_N/frame_K/DoAction.as, frame_K/DoAction.as for the root).
No game code is copied: the output is a list of what to look at.
"""

import argparse
import json
import os
import re
import sys

SHAPE = re.compile(r'^\t\[(\d+)\]=\{k="shape".*?dw=([0-9.]+),dh=([0-9.]+)')
SPRITE = re.compile(r'^\t\[(\d+)\]=\{k="sprite",n=(\d+),labels=\{(.*?)\},frames=\{')
PLACE = re.compile(r'\{d=(\d+),c=(\d+)(?:,n="([^"]*)")?')


def parse_film(text):
    """{'shapes': {id: (dw, dh)}, 'sprites': {id: {'n': int, 'places': [(child id, name)]}}, 'root': [(child id, name)]}"""
    shapes, sprites, root = {}, {}, []
    current = None
    in_root = False

    for line in text.split("\n"):
        match = SHAPE.match(line)

        if match:
            shapes[int(match.group(1))] = (float(match.group(2)), float(match.group(3)))
            current = None
            continue

        match = SPRITE.match(line)

        if match:
            current = {"n": int(match.group(2)), "places": [], "labels": match.group(3)}
            sprites[int(match.group(1))] = current
            continue

        if line.startswith("\troot="):
            in_root = True
            current = None
            continue

        target = root if in_root else (current["places"] if current is not None else None)

        if target is not None:
            for place in PLACE.finditer(line):
                target.append((int(place.group(2)), place.group(3)))

    return {"shapes": shapes, "sprites": sprites, "root": root}


def fullscreen_chains(film, stage, min_share):
    """For every shape covering at least min_share of the stage: the chains of clips from the root down to it, as lists of
    'id' / 'id:name' strings."""
    area = stage[0] * stage[1]
    big = [s for s, (w, h) in film["shapes"].items() if w * h >= min_share * area]
    parents = {}

    for sprite_id, sprite in film["sprites"].items():
        for child, name in sprite["places"]:
            parents.setdefault(child, set()).add((sprite_id, name))

    for child, name in film["root"]:
        parents.setdefault(child, set()).add((0, name))

    chains = []

    def climb(node, chain, seen):
        for parent, name in sorted(parents.get(node, []), key=lambda x: (x[0], x[1] or "")):
            label = "%d:%s" % (node, name) if name else str(node)

            if parent == 0:
                chains.append([label] + chain)
            elif parent not in seen:
                climb(parent, [label] + chain, seen | {parent})

    for shape_id in big:
        before = len(chains)
        climb(shape_id, [], {shape_id})

        if len(chains) == before:
            chains.append([str(shape_id), "(not placed)"])

    return big, chains


CONVERTIBLE = [
    re.compile(r"^(stop|play)\(\);?$"),
    re.compile(r"^gotoAnd(Stop|Play)\([^)]*\);?$"),
    re.compile(r"^(this\.)?[A-Za-z_][A-Za-z_0-9]*\.gotoAnd(Stop|Play)\([^)]*\);?$"),
    re.compile(r"^var \w+ = new Color\(.*\);?$"),
    re.compile(r"^color2\.setRGB\(color1\.getRGB\(\)\);?$"),
]


def unconvertible(statement):
    statement = statement.strip()

    if not statement or statement in ("{", "}") or statement.startswith(("if(", "if (", "else")):
        return False

    return not any(pattern.match(statement) for pattern in CONVERTIBLE)


CROSS = re.compile(r"_root\.|_parent\.|fscommand|\.\w+\.gotoAnd|_level|getURL")


def reaches_outside(statement):
    """A statement that touches another clip or the game (what a clip-local conversion cannot carry), as opposed to the
    body of a function the movie defines for the game's code."""
    return bool(CROSS.search(statement))


def script_gaps(scripts_dir):
    """[(where, statement)] for every sprite frame script statement the film cannot carry (the root's script, the movie's own API,
    is ported by hand and is not listed)."""
    gaps = []

    for entry in sorted(os.listdir(scripts_dir)):
        if not entry.startswith("DefineSprite_"):
            continue

        for frame in sorted(os.listdir(os.path.join(scripts_dir, entry))):
            folder = os.path.join(scripts_dir, entry, frame)

            if not os.path.isdir(folder):
                continue

            # a frame can hold several DoAction tags: FFDec writes DoAction.as, DoAction_2.as, DoAction_3.as...
            for name in sorted(os.listdir(folder)):
                if not (name.startswith("DoAction") and name.endswith(".as")):
                    continue

                with open(os.path.join(folder, name), encoding="utf8", errors="replace") as handle:
                    for statement in handle.read().split("\n"):
                        if unconvertible(statement):
                            gaps.append(("%s/%s" % (entry, frame), statement.strip()))

    return gaps


def gaps_as_records(gaps):
    """[(where, statement)] as [{sprite, frame, statement}], where `where` is 'DefineSprite_N/frame_K'."""
    records = []

    for where, statement in gaps:
        sprite, frame = where.split("/", 1)
        records.append({"sprite": sprite, "frame": frame, "statement": statement})

    return records


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scripts", required=True)
    parser.add_argument("--film", required=True)
    parser.add_argument("--stage", nargs=2, type=float, default=[1366, 768])
    parser.add_argument("--min-share", type=float, default=0.35)
    parser.add_argument("--cross-only", action="store_true", help="only the statements that reach another clip or the game")
    parser.add_argument("--json", action="store_true", help="the gaps as a JSON list of {sprite, frame, statement} (to sort them elsewhere)")
    args = parser.parse_args(argv)

    with open(args.film, encoding="utf8") as handle:
        film = parse_film(handle.read())

    gaps = script_gaps(args.scripts)

    if args.cross_only:
        gaps = [gap for gap in gaps if reaches_outside(gap[1])]

    if args.json:
        print(json.dumps(gaps_as_records(gaps), indent=1))

        return 0

    big, chains = fullscreen_chains(film, args.stage, args.min_share)
    print("Full-screen shapes (>= %d%% of the stage): %s" % (args.min_share * 100, ", ".join(map(str, sorted(big))) or "none"))

    for chain in chains:
        print("  root > " + " > ".join(chain))

    print("Script statements the film cannot carry: %d" % len(gaps))

    for where, statement in gaps:
        print("  %-28s %s" % (where, statement))

    return 0


if __name__ == "__main__":
    sys.exit(main())
