"""Files a staircase recorded by tests/minimap/stairs_record_job.lua (REC.run in the game) into the repository.

Usage:  python dev_resources/save_stairs.py <name> [--no-commit]

Reads garrysmod/data/grymod_tmp/stairs_<name>.txt (written by the game), then:
  * appends the samples to tests/minimap/fixtures/<map>_stairs.lua under the key <name> (the file is created when the map has none; a key already there is replaced);
  * appends the position, the view and what the game saw to docs/superpowers/plans/2026-11-22-stairs-test-positions.md (private, git-ignored);
  * commits the fixture (not the notes), unless --no-commit;
  * deletes the file in the game's data folder.
"""
import os
import re
import subprocess
import sys

GAME_DATA = r"D:\SteamLibrary\steamapps\common\GarrysMod\garrysmod\data\grymod_tmp"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NOTES = os.path.join(REPO, "docs", "superpowers", "plans", "2026-11-22-stairs-test-positions.md")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit(__doc__)
    name = args[0]
    src = os.path.join(GAME_DATA, "stairs_%s.txt" % name)
    text = open(src, encoding="utf-8").read()
    head, _, body = text.partition("\n---\n")
    meta = dict(line.split("=", 1) for line in head.splitlines() if "=" in line)
    samples = [l.rstrip(",").strip() for l in body.strip().splitlines() if l.strip()]
    map_name = meta["map"]
    fixture = os.path.join(REPO, "tests", "minimap", "fixtures", "%s_stairs.lua" % map_name)

    block = "\t-- %s (recorded %s at the owner's request): pos %s, angles (pitch, yaw, roll) %s, the level of the rule here: %s, ceiling %s units over the feet.\n" % (
        name, "2026-11-22", meta["pos"], meta["angles"], meta["level"], meta.get("ceilingAbove") or meta["ceiling"])
    block += "\t-- The ground followed straight ahead every 12 units with down rays: %s samples, %s units, z %s to %s, stopped by: %s. Format: {x, y, feet z, highest ceiling that is not the sky\n" % (
        meta["samples"], meta["length"], meta["zStart"], meta["zEnd"], meta["stop"])
    block += "\t-- (-99999: none), 1 when the centre ray saw the sky or nothing, height of the sky or 0}.\n"
    block += "\t%s = {\n%s\n\t},\n" % (name, "\n".join("\t\t%s," % s for s in samples))

    if os.path.exists(fixture):
        lua = open(fixture, encoding="utf-8").read()
        # a key already there is replaced
        pattern = re.compile(r"(\t--[^\n]*\n)*\t%s = \{.*?\n\t\},\n" % re.escape(name), re.S)
        lua = pattern.sub("", lua)
        lua = lua.rstrip()
        assert lua.endswith("}"), "the fixture does not end with a closing brace"
        lua = lua[:-1].rstrip() + "\n" + block + "}\n"
    else:
        lua = ("-- Real samples of %s recorded for the tests of the floors rule (stairs and ramps the owner shows), by tests/minimap/stairs_record_job.lua and dev_resources/save_stairs.py.\n"
               "return {\n%s}\n") % (map_name, block)
    open(fixture, "w", encoding="utf-8").write(lua)

    note = "\n## %s (%s, %s)\n\n" % (name, map_name, "2026-11-22")
    note += "- Position des pieds : (%s), vue (pitch, yaw, roll) : (%s). Au sol : voir le relevé.\n" % (meta["pos"].replace(",", ", "), meta["angles"].replace(",", ", "))
    note += "- Le sol devant (distance:hauteur) : %s\n" % meta["ahead"]
    note += "- Plafond : %s (%s au-dessus des pieds). Niveau de la règle actuelle : `%s`.\n" % (meta["ceiling"], meta.get("ceilingAbove") or "?", meta["level"])
    note += "- Trajet : le sol suivi tout droit, %s positions sur %s unités, de z %s à %s, arrêt : %s. Fixture : `tests/minimap/fixtures/%s_stairs.lua`, clé `%s`.\n" % (
        meta["samples"], meta["length"], meta["zStart"], meta["zEnd"], meta["stop"], map_name, name)
    open(NOTES, "a", encoding="utf-8").write(note)

    os.remove(src)
    try:
        os.rmdir(GAME_DATA)
    except OSError:
        pass

    if "--no-commit" not in sys.argv:
        rel = os.path.relpath(fixture, REPO)
        subprocess.check_call(["git", "add", rel], cwd=REPO)
        subprocess.check_call(["git", "commit", "-q", "-m",
                               "Tests: a staircase recorded on %s (%s: %s samples, z %s to %s)" % (map_name, name, meta["samples"], meta["zStart"], meta["zEnd"]), "--", rel], cwd=REPO)
        print(subprocess.check_output(["git", "log", "--oneline", "-1"], cwd=REPO, text=True).strip())
    print("saved %s: %s samples, z %s to %s" % (name, meta["samples"], meta["zStart"], meta["zEnd"]))


if __name__ == "__main__":
    main()
