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
    python -m unittest discover -s tools/flash2lua -t . -p "test_*.py"

Regenerate the data (from the repository root; `lua/grymod/flash/` and `materials/grymod/flash/` are overwritten):

    python -m tools.flash2lua.convert --pak "<...>\Crysis SP Demo\Game\GameData.pak" --ffdec <ffdec-cli.exe> ^
        HUD_AmmoHealthEnergySuit HUD_RadarCompassStealth

Compare a render of the game with FFDec's render of the same movie (pixel by pixel):

    python -m tools.flash2lua.compare_pixels reference.png game.png --bg 51,51,51 --tolerance 48

`lupa` (pip) is optional: with it the tests also load the generated Lua in a real LuaJIT.

What the atlases contain: the shapes of the movie rasterised at 4x its stage size, with their colours
sRGB-encoded (the engine decodes PNG textures as sRGB when it samples them, Flash blends the plain 0-255
values), and the glyphs of the HUD font (Agency FB) for the text fields.
