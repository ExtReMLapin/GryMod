# flash2lua

Offline converter that turns the Crysis HUD Scaleform/Flash files into Lua data and texture
atlases for GryMod. It is only needed to regenerate the data, never at runtime.

Needs: Python 3.12 + Pillow, FFDec (https://github.com/jindrapetrik/jpexs-decompiler) and the
`GameData.pak` of the Crysis SP demo. The raw demo files are not part of this repository.

Run the tests (from the repository root):

    set FFDEC=path\to\ffdec-cli.exe
    set SWF_DIR=path\to\extracted\Libs\UI
    python -m unittest discover -s tools/flash2lua -t . -p "test_*.py"

Regenerate the data (from the repository root; `lua/grymod/flash/` and `materials/grymod/flash/` are overwritten):

    python -m tools.flash2lua.convert --pak "<...>\Crysis SP Demo\Game\GameData.pak" --ffdec <ffdec-cli.exe> HUD_AmmoHealthEnergySuit

`lupa` (pip) is optional: with it the tests also load the generated Lua in a real LuaJIT.
