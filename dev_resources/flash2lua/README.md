# flash2lua

Offline converter that turns the Crysis HUD Scaleform/Flash files into Lua data and texture
atlases for GryMod. It is only needed to regenerate the data, never at runtime.

Needs: Python 3.12 with Pillow and numpy, FFDec (https://github.com/jindrapetrik/jpexs-decompiler) and the
Crysis SP demo (`Game\GameData.pak` for the movies, `Game\Localized\english.pak` for the HUD font). The raw
demo files are not part of this repository.

Run the tests (from the repository root; they are skipped when FFDec or the demo is missing):

    set FFDEC=path\to\ffdec-cli.exe
    set SWF_DIR=path\to\extracted\Libs\UI
    set CRYSIS_GAMEDATA_PAK=path\to\GameData.pak
    set CRYSIS_LOCALIZED_PAK=path\to\Localized\english.pak
    python -m unittest discover -s dev_resources/flash2lua -t . -p "test_*.py"

Regenerate the data (from the repository root; `lua/grymod/flash/` and `materials/grymod/flash/` are overwritten):

    python -m dev_resources.flash2lua.convert --pak "<...>\Crysis SP Demo\Game\GameData.pak" --ffdec <ffdec-cli.exe> ^
        HUD_AmmoHealthEnergySuit HUD_RadarCompassStealth

Compare a render of the game with FFDec's render of the same movie (pixel by pixel):

    python -m dev_resources.flash2lua.compare_pixels reference.png game.png --bg 51,51,51 --tolerance 48

`lupa` (pip) is optional: with it the tests also load the generated Lua in a real LuaJIT.

What the atlases contain: the shapes of the movie rasterised at 4x its stage size, with their colours
sRGB-encoded (the engine decodes the colour textures it samples as sRGB, Flash blends the plain 0-255
values), and the glyphs of the HUD font (Agency FB) for the text fields.

What the game loads: VTF textures (`materials/grymod/flash/<movie>_<n>.vtf` with a `.vmt`, and `<movie>_<n>_w.vtf`, the
all-white twin of the shapes whose colour a colour-set clip replaces). `convert` rasterises into PNG atlases in a
temporary folder and `repack` (also usable alone, on PNG atlases already made) turns them into them: it cuts every
shape out, shrinks the flat or smooth ones (they do not need four texels per stage pixel), packs them in the smallest
power-of-two sheets (`pack.py`), and writes DXT5 with the mip levels in the file (`vtf.py`: the engine loads it in
milliseconds and keeps one byte per pixel, where a PNG is decoded when the material is made and kept as RGBA8).
The glyph atlas is the same picture in every movie: one shared uncompressed `hud_font.vtf`.
`tests/flash_atlas_job.lua` and `tests/flash_scenes_job.lua` draw every shape and the movies in game, to compare two
states of the atlases pixel by pixel (`compare_pixels.py`, or a few lines of numpy).
