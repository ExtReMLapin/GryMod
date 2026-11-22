"""Builds the folder that is released and refuses to go on when something is wrong.

    python tools/prepare_release.py --version 4.3 --out dist/zip                       the plain package (the release zip)
    python tools/prepare_release.py --version 4.3 --out dist/workshop --workshop --expect-wsid 153963150

What it does, in this order, and stops at the first thing that is wrong (exit 1, the reason on the standard error):
  * reads addon.json (title, type and tags are what the Workshop accepts) and takes the files git tracks, minus the "ignore" patterns of addon.json
    (the same rule as the Workshop's: a pattern matches the whole path or the file name, `*` goes over folders);
  * checks every one of them: lower case names with characters the Workshop takes, only file types the Workshop's white list takes, nothing of the
    development (tools, tests, sources) left in, every shader source (dev_resources/shaders/*.hlsl) has its compiled shaders/fxc/*.vcs and it is not empty;
  * copies them to --out, then in lua/autorun/grymod_shared.lua writes the version (`GryMod.Version = "x.y"`, a leading v of the tag goes) and, with
    --workshop, turns `GryMod.Workshop = false` into true (the Workshop package asks the clients to subscribe instead of sending every file);
  * checks that the Workshop id written in the code (GryMod.WSID) is the one given with --expect-wsid (the id of the repository's secret): a release of
    the wrong item is the mistake that cannot be taken back;
  * checks the size (--max-mb, 140 by default: what the Workshop took so far).
The tree it reads is never changed. Nothing here talks to the network or to Steam.
"""
import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# what gmad's white list takes among the types this addon uses (and the usual ones it could use later); addon.json is the one json file
ALLOWED_EXTENSIONS = {".lua", ".vmt", ".vtf", ".vcs", ".wav", ".mp3", ".ogg", ".png", ".jpg", ".ttf"}
ADDON_TYPES = {"gamemode", "map", "weapon", "vehicle", "npc", "tool", "effects", "model", "servercontent"}
ADDON_TAGS = {"fun", "roleplay", "scenic", "movie", "realism", "cartoon", "water", "comic", "build"}
SHARED = "lua/autorun/grymod_shared.lua"
VERSION = re.compile(r"^v?(\d+(?:\.\d+){1,2}(?:-[0-9A-Za-z.]+)?)$")
PATH_CHARACTERS = re.compile(r"^[a-z0-9_./-]+$")


class ReleaseError(Exception):
    pass


def is_ignored(path, patterns):
    """The Workshop's rule for the "ignore" list of addon.json: a pattern is tried on the whole path and on the file name."""
    name = path.rsplit("/", 1)[-1]

    return any(fnmatch.fnmatchcase(path, p) or fnmatch.fnmatchcase(name, p) for p in patterns)


def git_tracked(root):
    out = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, check=True).stdout.decode("utf-8")

    return [p for p in out.split("\0") if p]


def read_addon_json(root):
    path = os.path.join(root, "addon.json")

    try:
        with open(path, encoding="utf-8") as f:
            addon = json.load(f)
    except (OSError, ValueError) as err:
        raise ReleaseError(f"addon.json cannot be read: {err}")

    title = addon.get("title")

    if not isinstance(title, str) or not title.strip():
        raise ReleaseError("addon.json has no title")

    if addon.get("type") not in ADDON_TYPES:
        raise ReleaseError(f"addon.json type {addon.get('type')!r} is not one the Workshop knows: {sorted(ADDON_TYPES)}")

    tags = addon.get("tags")

    if not isinstance(tags, list) or len(tags) > 2 or any(t not in ADDON_TAGS for t in tags):
        raise ReleaseError(f"addon.json tags {tags!r}: the Workshop takes at most two tags among {sorted(ADDON_TAGS)}")

    if not isinstance(addon.get("ignore", []), list):
        raise ReleaseError("addon.json: ignore must be a list")

    return addon


def check_files(files):
    for path in files:
        if not path.islower() and path != path.lower():
            raise ReleaseError(f"{path}: the Workshop wants lower case names")

        if not PATH_CHARACTERS.match(path):
            raise ReleaseError(f"{path}: characters the Workshop refuses (lower case letters, digits, _ . / - only)")

        extension = os.path.splitext(path)[1]

        if path != "addon.json" and extension not in ALLOWED_EXTENSIONS:
            raise ReleaseError(f"{path}: a file type the Workshop would refuse ({extension or 'no extension'}); is it a development file the ignore list of addon.json forgot?")


def check_shaders(tracked, files, sizes):
    """A shader source without its compiled file is a shader that was never built (or whose file was left out)."""
    present = set(files)

    for path in tracked:
        match = re.match(r"^dev_resources/shaders/(.+)\.hlsl$", path)

        if not match:
            continue

        compiled = f"shaders/fxc/{match.group(1)}.vcs"

        if compiled not in present:
            raise ReleaseError(f"{match.group(1)}: the shader source {path} has no {compiled} in the package: compile it (dev_resources/shaders/README.md)")

        if sizes[compiled] == 0:
            raise ReleaseError(f"{compiled} is empty")


def parse_version(version):
    match = VERSION.match(version or "")

    if not match:
        raise ReleaseError(f"{version!r} is not a version (4.2, v4.3, 4.3.1, 5.0-rc1)")

    return match.group(1)


def parse_wsid(expect):
    if expect is None:
        return None

    text = str(expect).strip()

    if not text.isdigit():
        raise ReleaseError(f"the workshop id given ({expect!r}) must be a number: is the WORKSHOP_ID secret set?")

    return int(text)


def stamp_shared(text, version, workshop):
    """The shared file with the version written and, for the Workshop, the flag on. Line endings are kept."""
    flags = list(re.finditer(r"^GryMod\.Workshop = false[ \t]*(\r?\n|\Z)", text, re.M))

    if len(flags) != 1:
        raise ReleaseError(f"{SHARED} must hold exactly one line `GryMod.Workshop = false` (the repository ships the plain package); found {len(flags)}")

    if re.search(r"^\s*GryMod\.Version\s*=", text, re.M):
        raise ReleaseError(f"{SHARED} already sets GryMod.Version: the release writes it")

    match = flags[0]
    newline = match.group(1) or "\n"
    line = ("GryMod.Workshop = true" if workshop else "GryMod.Workshop = false") + newline + f'GryMod.Version = "{version}"' + newline

    return text[: match.start()] + line + text[match.end():]


def prepare(root, out, version, workshop=False, tracked=None, max_mb=140, expect_wsid=None):
    """Builds `out` from `root`. Returns {"files", "bytes", "wsid", "version", "workshop"}; raises ReleaseError."""
    version = parse_version(version)
    wanted_wsid = parse_wsid(expect_wsid)
    addon = read_addon_json(root)
    tracked = git_tracked(root) if tracked is None else list(tracked)
    patterns = addon.get("ignore", [])
    files = sorted(p for p in tracked if not is_ignored(p, patterns) and os.path.isfile(os.path.join(root, p)))
    sizes = {p: os.path.getsize(os.path.join(root, p)) for p in files}

    if SHARED not in files:
        raise ReleaseError(f"{SHARED} is not in the package")

    check_files(files)
    check_shaders(tracked, files, sizes)

    with open(os.path.join(root, SHARED), "rb") as f:
        shared = stamp_shared(f.read().decode("utf-8"), version, workshop)

    found = re.search(r"^GryMod\.WSID\s*=\s*(\d+)\s*$", shared, re.M)

    if not found:
        raise ReleaseError(f"{SHARED} has no `GryMod.WSID = <number>` line")

    wsid = int(found.group(1))

    if wanted_wsid is not None and wanted_wsid != wsid:
        raise ReleaseError(f"the code says the Workshop item is {wsid} (GryMod.WSID) and the id given is {wanted_wsid}: one of them is wrong, nothing was built")

    total = sum(sizes.values()) - sizes[SHARED] + len(shared.encode("utf-8"))

    if total > max_mb * 1_000_000:
        raise ReleaseError(f"the package is {total / 1e6:.1f} MB, over the limit of {max_mb} MB")

    if os.path.isdir(out) and os.listdir(out):
        raise ReleaseError(f"{out} is not empty: give a new folder")

    for path in files:
        target = os.path.join(out, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)

        with open(os.path.join(root, path), "rb") as src, open(target, "wb") as dst:
            dst.write(src.read())

    with open(os.path.join(out, SHARED), "wb") as f:
        f.write(shared.encode("utf-8"))

    return {"files": files, "bytes": total, "wsid": wsid, "version": version, "workshop": bool(workshop)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--version", required=True, help="the release tag: 4.3 or v4.3")
    parser.add_argument("--out", required=True, help="a new folder")
    parser.add_argument("--workshop", action="store_true", help="the Workshop flavour (GryMod.Workshop = true)")
    parser.add_argument("--max-mb", type=float, default=140)
    parser.add_argument("--expect-wsid", default=None, help="the Workshop id of the repository's secret; refused when it is not the code's GryMod.WSID")
    parser.add_argument("--root", default=ROOT)
    args = parser.parse_args(argv)

    try:
        report = prepare(args.root, args.out, args.version, args.workshop, max_mb=args.max_mb, expect_wsid=args.expect_wsid)
    except ReleaseError as err:
        print(f"::error::{err}", file=sys.stderr)

        return 1

    print(json.dumps({k: v for k, v in report.items() if k != "files"} | {"file_count": len(report["files"])}))

    return 0


if __name__ == "__main__":
    sys.exit(main())
