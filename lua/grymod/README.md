# lua/grymod

The addon's code. `lua/autorun/grymod_shared.lua` is the loader: it names every file of this folder, sends the client files to the players (`AddCSLuaFile`) and includes each file in the realm that runs it. A file that is not named there is not loaded and the game does not say so; `tools/test_loader_coverage.py` fails when that happens.

## Naming

| Prefix or folder | Runs on | Holds |
| --- | --- | --- |
| `sh_*.lua` | server and client | Rules and data both sides need: the API registries (`sh_api*.lua`), the suit weapon rules, the radar wire format, the objectives data. |
| `server/sv_*.lua` | server | The rules of the suit, the radar contacts, damage, objectives, administrators' settings. |
| `client/cl_*.lua` | client | The HUD, the rendering, the options, the keys. |
| `client/minimap/`, `client/map/` | client | The minimap and the big map. |
| `flash/` | client | The converted Flash movies. Generated. |
| `compat/` | both | Patches for other addons, written against the public API only. |
| `campaign/` | server | Objectives of the Half-Life 2 campaign maps. Generated. |

The `GryMod` table is global. `GryMod.API` is the interface for other addons ([`docs/`](../../docs/README.md)); the other fields of `GryMod` (`GryMod.Mech`, `GryMod.CloakFX`, `GryMod.FlashHUD`...) are the addon's own modules and can change without notice.

## Where to start reading

- The suit's rules: `server/sv_mechanics.lua` (the numbers), `server/sv_system.lua` (mode changes, energy loop), `server/sv_malfunction.lua`.
- How a Crysis interface movie becomes a panel: `client/cl_flash.lua`, `client/cl_flash_draw.lua`, then one `client/cl_hud_*_flash.lua`, for instance `cl_hud_quickmenu_flash.lua`.
- How another addon plugs in: `sh_api.lua` and the `sh_api_*.lua` files, then [`compat/`](compat/README.md) for working examples.
