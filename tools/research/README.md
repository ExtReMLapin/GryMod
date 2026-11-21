Research scripts
================

Small throw-away scripts used to read the files extracted from the Crysis demo while the HUD and the sounds of GryMod were made.
They are code only. The original resources they read (the extracted movies and their ActionScript, the game's own Lua, the FMOD
banks, the XML dumps, FFDec) stay in `D:\dev\crysis-hud-research` on the developer's machine and are never put in this repository.

| Script | What it does |
| --- | --- |
| `colorpat.py` | Counts the `new Color` patterns of a folder of dumped `.as` files (run it from the dump's folder). |
| `qm/dump.py` | Prints the display list of the quick menu movie from an FFDec XML export (`qm.xml` in the current folder). |
| `water/fsb3.py` | Reader of FMOD FSB3 sound banks (lists the samples, writes WAV files). |
| `water/parse_fdp.py` | Reads events and sound definitions out of an FMOD designer `.fdp` file. |
| `water/disx.py` | Disassembles a function of `CryGame.dll` (needs `capstone`; the path of the DLL is written in the script). |

The converters that make the addon's files (`../flash2lua`, `../flash_audit`, `../extract_sounds.py`) are in the folder above.
This whole `tools/` folder is left out of the Workshop package (`addon.json`) and of the release zip (`.gitattributes`).
