# tools

The release tools and the checks that need no game. They run on the developer's machine and in GitHub Actions (`.github/workflows/ci.yml`).

| File | What it does |
| --- | --- |
| `prepare_release.py` | Builds the folder that is released and refuses anything the Workshop would refuse: file names and types, development files, missing compiled shaders, the Workshop id against the one in the code, the size. Writes the version into `lua/autorun/grymod_shared.lua`, and with `--workshop` sets `GryMod.Workshop = true`. Never changes the working tree. |
| `check_lua_syntax.py` | Parses every Lua file of the addon and of the tests with LuaJIT (`pip install lupa`). |
| `test_prepare_release.py` | Tests of the release tool. |
| `test_loader_coverage.py` | The loader names every file, and every file it names exists and runs in the right realm. |
| `test_docs_coverage.py` | Every hook, networked variable, network message and API entry of the code has an entry in the reference documentation, and no entry names something that does not exist. |
| `test_shipped_resources.py`, `test_sound_files.py` | What the addon ships is used, what the Lua asks the clients to download exists, and the WAV files are ones the engine accepts. |
| `test_override_guard.py` | Every file that draws a model through a material override was checked against the engine's dynamic vertex buffer limit. |
| `test_flash_bar.py`, `test_flash_draw_alloc.py`, `test_flash_goto.py` | Tests of the pure parts of the Flash player, run in LuaJIT outside the game. |

Run any of them from the repository root, for instance `python -m unittest tools.test_docs_coverage`.
