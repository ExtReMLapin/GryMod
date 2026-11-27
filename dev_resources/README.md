# dev_resources

What makes the data of the addon. Nothing here is loaded by the game, and the folder is left out of the Workshop package and of the release zip (`addon.json`). The files it produces are committed, so the game and the release never need these tools or the original files.

| Folder | What it makes |
| --- | --- |
| [`flash2lua/`](flash2lua/README.md) | The Flash to Lua converter: the movies become `lua/grymod/flash/*.lua` and the texture atlases in `materials/grymod/flash/`. Needs FFDec and the Crysis SP demo's files, which are not in this repository. |
| [`shaders/`](shaders/README.md) | The HLSL sources of the camouflage and night vision shaders and the build that compiles them to `shaders/fxc/*.vcs`. |
| `campaign/` | `build_campaign.py` builds `lua/grymod/campaign/` from the entity lump of the Half-Life 2 maps; its tests check the rules. |
| `cloak/` | Scripts that extract the camouflage textures and make the normal map and the sparks texture. |
| `sounds/` | `extract_sounds.py`: extracts the suit, HUD, quick menu, binoculars, night vision and underwater sounds from the Crysis SP demo. |
| `flash_audit/` | Audits a converted movie against the original's scripts, and lists the elements of the converted movies that the port never reaches. |
| `research/` | Small scripts used while reading the original's files and measuring behaviour. Code only; see its README. |
| `*.py` at this level | One-off analyses of map node graphs and floors (`scan_map_graphs.py`, `level_survey_analysis.py`, `level_rule_experiment.py`, `save_stairs.py`). |

The Python tests of these folders run in GitHub Actions when the needed files are there (`python -m unittest discover -s dev_resources/<folder>`).
