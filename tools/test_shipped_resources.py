"""Checks that what the addon ships (maps/, models/, materials/) is still used, and that what the Lua asks the clients to download exists:

    python tools/test_shipped_resources.py

A file counts as used when the Lua code (outside the resource.AddFile lines, which only send it) names it, or when a used .vmt
names it ($basetexture, $bumpmap, ...), and so on down the chain. materials/grymod/flash is left out: the pictures of the HUD
are produced and checked by tools/flash2lua and tools/flash_audit. Exit code 1 and one line per problem on failure.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FLASH = "materials/grymod/flash/"
ADDFILE = re.compile(r"resource\.AddFile\(\s*\"([^\"]+)\"\s*\)", re.I)


def lua_files():
    for folder, _, names in os.walk(os.path.join(ROOT, "lua")):
        for name in names:
            if name.endswith(".lua"):
                yield os.path.join(folder, name)


def shipped_files():
    for top in ("maps", "models", "materials"):
        for folder, _, names in os.walk(os.path.join(ROOT, top)):
            for name in names:
                path = os.path.relpath(os.path.join(folder, name), ROOT).replace("\\", "/")

                if not path.lower().startswith(FLASH):
                    yield path


def sent_paths():
    found = []

    for path in lua_files():
        found += ADDFILE.findall(open(path, encoding="utf8", errors="ignore").read())

    return found


def code_text():
    text = []

    for path in lua_files():
        for line in open(path, encoding="utf8", errors="ignore"):
            if "resource.addfile" not in line.lower():
                text.append(line.lower())

    return "".join(text)


def key(path):
    """How the code and the .vmt files name a file: materials/a/b.vtf is a/b, anything else keeps its folder and extension."""
    lower = path.lower()

    if lower.startswith("materials/"):
        return os.path.splitext(lower[len("materials/"):])[0]

    return lower


def names(text, path):
    """True when the text names the file as a whole word of its own (cloak/cloak is not cloak/cloak_refract)."""
    return re.search(r"(?<![\w/.])" + re.escape(key(path)) + r"(?![\w/])", text) is not None


def used_files():
    files = sorted(shipped_files())
    code = code_text()
    used, queue = set(), [p for p in files if names(code, p)]

    while queue:
        path = queue.pop()

        if path in used:
            continue

        used.add(path)

        if path.lower().endswith(".vmt"):
            text = open(os.path.join(ROOT, path), encoding="utf8", errors="ignore").read().lower()
            queue += [p for p in files if p not in used and p.lower().endswith(".vtf") and names(text, p)]

    return used


def problems():
    found = []

    for path in sent_paths():
        if not os.path.exists(os.path.join(ROOT, path)):
            found.append("sent to the clients but not in the addon: " + path)

    used = used_files()

    for path in shipped_files():
        if path not in used:
            found.append("shipped but nothing uses it: " + path)

    return found


if __name__ == "__main__":
    errors = problems()

    for line in errors:
        print(line)

    print("%d problem(s)" % len(errors))
    sys.exit(1 if errors else 0)
