"""Checks that the compiled shaders shipped in shaders/fxc/ are the ones of the HLSL sources next to this file.

    python dev_resources/shaders/check_compiled.py            check (exit 1 and the reasons when something is wrong): the CI runs this
    python dev_resources/shaders/check_compiled.py --update   after a recompilation (build_shaders.py), write the manifest again

The CI does not compile (ShaderCompile is a Windows program that is not in this repository, nor are the SDK headers it needs): the .vcs are committed.
What the CI can do, and does, is to refuse a source that was changed without a recompilation: compiled.sha256 holds, for each shader, the hash of its
source and the hash of its compiled file as they were when the developer compiled. A source edited and not rebuilt, a compiled file replaced by
another, a new shader never added to the manifest all fail the check. The source is hashed with its line ends normalised (a Windows checkout and a
Linux one give the same hash); the compiled file as it is.
"""
import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
HEADER = "# sha256 of each shader's source (line ends as \\n) and of its compiled file, written by check_compiled.py --update after a recompilation"


class ManifestError(Exception):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_hash(path):
    with open(path, "rb") as f:
        return digest(f.read().replace(b"\r\n", b"\n"))


def file_hash(path):
    with open(path, "rb") as f:
        return digest(f.read())


def current(src_dir, out_dir):
    """{base: (source hash, compiled hash or None)} for every .hlsl of src_dir."""
    found = {}

    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".hlsl"):
            continue

        base = name[: -len(".hlsl")]
        compiled = os.path.join(out_dir, base + ".vcs")
        found[base] = (source_hash(os.path.join(src_dir, name)), file_hash(compiled) if os.path.isfile(compiled) else None)

    return found


def read_manifest(path):
    entries = {}

    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()

            if not line or line.startswith("#"):
                continue

            parts = line.split()

            if len(parts) != 3:
                raise ManifestError(f"{path}: a line is not `source-hash compiled-hash name`: {line!r}")

            entries[parts[2]] = (parts[0], parts[1])

    return entries


def check(src_dir, out_dir, manifest_path):
    """The list of what is wrong (empty when everything is in order)."""
    if not os.path.isfile(manifest_path):
        return [f"no manifest ({manifest_path}): run check_compiled.py --update after compiling"]

    try:
        known = read_manifest(manifest_path)
    except ManifestError as err:
        return [str(err)]

    now = current(src_dir, out_dir)
    problems = []

    for base, (src, compiled) in now.items():
        if compiled is None:
            problems.append(f"{base}: shaders/fxc/{base}.vcs is missing")
        elif base not in known:
            problems.append(f"{base}: not in the manifest: compile it and run check_compiled.py --update")
        elif known[base][0] != src:
            problems.append(f"{base}: the source changed since it was compiled: recompile (build_shaders.py), then run check_compiled.py --update")
        elif known[base][1] != compiled:
            problems.append(f"{base}: shaders/fxc/{base}.vcs is not the file that was compiled from this source (the manifest says another one)")

    for base in known:
        if base not in now:
            problems.append(f"{base}: in the manifest, no longer in the sources: run check_compiled.py --update")

    return problems


def update(src_dir, out_dir, manifest_path):
    now = current(src_dir, out_dir)

    for base, (_, compiled) in now.items():
        if compiled is None:
            raise ManifestError(f"{base}: shaders/fxc/{base}.vcs is missing: compile first")

        if os.path.getsize(os.path.join(out_dir, base + ".vcs")) == 0:
            raise ManifestError(f"{base}: the compiled file is empty")

    lines = sorted(f"{src}  {compiled}  {base}" for base, (src, compiled) in now.items())

    with open(manifest_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HEADER + "\n" + "\n".join(lines) + "\n")

    return len(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--src", default=HERE)
    parser.add_argument("--out", default=os.path.join(ROOT, "shaders", "fxc"))
    parser.add_argument("--manifest", default=os.path.join(HERE, "compiled.sha256"))
    args = parser.parse_args(argv)

    try:
        if args.update:
            print(f"manifest written: {update(args.src, args.out, args.manifest)} shaders")

            return 0

        problems = check(args.src, args.out, args.manifest)
    except ManifestError as err:
        problems = [str(err)]

    for problem in problems:
        print(f"::error::{problem}", file=sys.stderr)

    if not problems:
        print("shaders: the compiled files match their sources")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
