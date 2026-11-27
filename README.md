# GryMod Remastered

**Playing? Get it on the Steam Workshop: [GryMod Remastered - Crysis Nanosuit & HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3846743387).**
Everything a player needs (what it does, the keys, the settings) is on that page and in the options menu of the game. This repository is the developer's page.

GryMod Remastered is the nanosuit of Crysis 1 for Garry's Mod: its four modes (Armor, Strength, Speed, Cloak), its energy rules, its HUD, its binoculars, its night
vision and its maps. Fan-made, not affiliated with Crytek or EA.

## What changed since the first GryMod: the interface is a port

The first GryMod drew a look-alike of the Crysis HUD with Garry's Mod's own drawing functions. Remastered is a **port**: the interface is the Crysis one, ported from
its Flash (Scaleform) files, so the animations are the original's animations and not an imitation of them.

How the port works:

1. **Convert, once, offline** (`dev_resources/flash2lua/`). The Flash movies are read with [FFDec](https://github.com/jindrapetrik/jpexs-decompiler). Every shape is rasterised
   into a texture atlas (VTF files in `materials/grymod/flash/`), and every timeline (the frames, the transforms, the colour changes, the masks, the labels) becomes plain
   Lua data (`lua/grymod/flash/*.lua`). The generated files are committed: the game needs neither the converter nor the original files.
2. **Play the timelines in the game** (`lua/grymod/client/cl_flash.lua` and `cl_flash_draw.lua`). A small Flash player written in Lua runs the timelines at the movie's
   30 images per second whatever the frame rate of the game, with `gotoAndPlay`, masks, colour transforms and text fields.
3. **Port the ActionScript by hand.** What the movies do when the game sends them a value (the digits, the bars, the quick menu's selection, the crosshair's states, the
   malfunction and the shutdown and reboot sequences...) was read in the original scripts and rewritten in Lua: the `cl_hud_*_flash.lua` files are that link, one for each movie.
4. **Same for the rules.** The energy, the armor, the health regeneration, the camouflage and the speeds follow the numbers of Crysis (`lua/grymod/server/sv_mechanics.lua`;
   a server setting gives the earlier GryMod numbers back). The camouflage's electric sparks are a port of the original pixel shader (`dev_resources/shaders/`).

That is why the animations match: nothing is redrawn by eye. The converter needs the Crysis SP demo's files; they are not in this repository (see
[`dev_resources/flash2lua/README.md`](dev_resources/flash2lua/README.md)).

## Where things are

| Folder | What is in it |
| --- | --- |
| [`lua/autorun/grymod_shared.lua`](lua/autorun/grymod_shared.lua) | The loader: it includes every file of `lua/grymod/` (a test checks that none is forgotten) and holds the addon's version and Workshop id. |
| [`lua/grymod/`](lua/grymod/README.md) | The addon: `sh_` shared, `sv_` server and `cl_` client files. |
| [`lua/grymod/client/`](lua/grymod/client/README.md) | The HUD, the Flash player, the quick menu, the radar, the camouflage rendering, the options, the keys. |
| [`lua/grymod/client/minimap/`](lua/grymod/client/minimap/README.md) | The minimap and the big map: the map rendered from above, kept on disk, with levels. |
| [`lua/grymod/server/`](lua/grymod/server/README.md) | The suit's rules, the radar's contacts, the damage, the objectives, the in/out map. |
| [`lua/grymod/compat/`](lua/grymod/compat/README.md) | The patches for other addons: weapon bases, NPC bases, vehicles, tools, third person cameras. |
| [`lua/grymod/flash/`](lua/grymod/flash/README.md) | The converted movies. Generated, not written by hand. |
| [`lua/grymod/campaign/`](lua/grymod/campaign/README.md) | The objectives of the Half-Life 2 campaign maps, generated from the maps. |
| [`docs/`](docs/README.md) | The documentation for the addons that plug into GryMod. |
| [`tests/`](tests/README.md) | The tests, run in a real game. |
| [`tools/`](tools/README.md) | The release tools and the checks that need no game. |
| [`dev_resources/`](dev_resources/README.md) | What makes the data: the Flash converter, the shaders, the campaign builder. Left out of the Workshop package. |

## For addon developers

GryMod has a public API, so that your weapons, NPCs, vehicles and effects show properly on the HUD, the radar and the binoculars without patching GryMod. Start with
[`docs/README.md`](docs/README.md):

| Guide | What it covers |
| --- | --- |
| [`docs/api.md`](docs/api.md) | The extension API: is GryMod there and which version, safe calls, the suit's commands and events, the relation chain. |
| [`docs/entities.md`](docs/entities.md) | Tracked entities: make your NPCs, vehicles, mines and projectiles show on the radar, the binoculars and the grenade warning. |
| [`docs/weapons.md`](docs/weapons.md) | The weapon registry: fire modes, ammunition, melee, the weapon list. |
| [`docs/events.md`](docs/events.md) | The HUD events: every effect of the interface (animation and sound together), how to play or add one. |
| [`docs/minimap.md`](docs/minimap.md) | The minimap and the big map: how they are made, cached and set. |
| [`docs/compat.md`](docs/compat.md) | The compatibility patches, the rules they follow, and the checklist for supporting a new weapon base. |

The one thing to know first: test for GryMod from the `Initialize` hook, with `GRYMOD_INSTALLED` and `GryMod.API.Version` (see
[`docs/README.md`](docs/README.md)). The interface version goes up only when something breaks.

## Compatibility

**TFA and ARC9 are the only addons with real, tested support.** Their weapons work with the suit (melee and recoil effects, the camouflage with the attachments, fire mode
and ammo on the HUD, the weapon menu).

Everything else in `lua/grymod/compat/` (ArcCW, CW 2.0, FA:S 2, M9K, VJ Base, DrGBase, ZBase, Draconic Base, LVS, Glide, simfphys, JMod, Wiremod, PAC3...) is the bare
minimum, written without much testing. It uses the public API only, it may be incomplete, and it may break. What was tried in a game and what was only read in the
source is written in [`docs/compat.md`](docs/compat.md), which also holds the rules a patch follows.

## Settings

Everything is optional and saved: Options > GryMod in the spawn menu, or the console. Server rules (`gry_mechanics`, the cloak's rules, the minimap's in/out map...) are in the
administrators' page of the options. A few to know: `gry_hud 0` hides the HUD, `gry_hud_theme` picks the colours, `gry_minimap 0` turns the minimap off, `gry_mechanics classic`
gives the earlier numbers back. The quick menu key is asked at the first spawn (or `bind mouse3 +crysishud`).

## Tests and checks

The tests (`tests/`) are in the GLuaTest format and run in a real game with [gmod-mcp](https://github.com/ExtReMLapin/gmod-mcp): load a map, then `tests_run` with the
realm of the file (`sv_` server, `cl_` client). The checks that need no game (Lua syntax, the loader, the shaders, the release package) run in GitHub Actions on every
push; see [`tools/README.md`](tools/README.md).

## Releases

A GitHub release (a tag such as `5.0`) builds the zip and the Workshop package from the same commit with `tools/prepare_release.py`, which refuses anything that the Workshop
would refuse, then uploads it (`.github/workflows/release.yml`). The Workshop item of GryMod Remastered is a new item, separate from the first GryMod's.

## License

You are not allowed to re-upload it or to make money with it. Credits for the ideas and the data that come from others are in the source files that use them.
