"""Convert Crysis HUD movies from the demo's GameData.pak into GryMod Lua data and atlases.

    python -m tools.flash2lua.convert --pak <GameData.pak> --ffdec <ffdec-cli.exe> HUD_AmmoHealthEnergySuit ...

Writes lua/grymod/flash/<movie>.lua and materials/grymod/flash/<movie>_<n>.png (lower case names).
"""
import argparse
import os
import tempfile
import zipfile

from tools.flash2lua import emit_lua, glyphs, rasterize, swfmodel

MATERIAL_DIR = "grymod/flash"


def _extract_swf(pak_path, movie_name, dest_dir):
    wanted = f"libs/ui/{movie_name}.swf".lower()
    with zipfile.ZipFile(pak_path) as pak:
        for entry in pak.namelist():
            if entry.lower() == wanted:
                path = os.path.join(dest_dir, movie_name + ".swf")
                with open(path, "wb") as out:
                    out.write(pak.read(entry))
                return path
    raise KeyError(f"{movie_name}.swf is not in {pak_path}")


def _localized_pak(pak_path):
    """Localized/english.pak sits next to GameData.pak in the game folder."""
    return os.path.join(os.path.dirname(os.path.abspath(pak_path)), "Localized", "english.pak")


def convert_movie(pak_path, movie_name, ffdec, lua_dir, materials_dir, localized_pak=None):
    name = movie_name.lower()
    os.makedirs(lua_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        swf = _extract_swf(pak_path, movie_name, tmp)
        xml = os.path.join(tmp, name + ".xml")
        swfmodel.swf_to_xml(ffdec, swf, xml)
        movie = swfmodel.parse_swf_xml(xml)
        rects = rasterize.rasterize_movie(movie, swf, materials_dir, ffdec, prefix=name)
        fonts = {}
        used = {c.font_id for c in movie.characters.values() if c.kind == "text" and c.font_id}
        for char_id, (url, _) in sorted(movie.imports.items()):
            if char_id in used and url and url.lower().endswith(".swf"):
                fonts[char_id] = glyphs.build_font_atlas(localized_pak or _localized_pak(pak_path), url, ffdec,
                                                         materials_dir, name + "_font")
    text = emit_lua.emit_lua(movie, rects, MATERIAL_DIR, fonts)
    with open(os.path.join(lua_dir, name + ".lua"), "w", encoding="utf8", newline="\n") as out:
        out.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", required=True)
    parser.add_argument("--ffdec", required=True)
    parser.add_argument("--lua-dir", default="lua/grymod/flash")
    parser.add_argument("--materials-dir", default="materials/grymod/flash")
    parser.add_argument("movies", nargs="+")
    args = parser.parse_args()
    for movie in args.movies:
        convert_movie(args.pak, movie, args.ffdec, args.lua_dir, args.materials_dir)
        print("converted", movie)


if __name__ == "__main__":
    main()
