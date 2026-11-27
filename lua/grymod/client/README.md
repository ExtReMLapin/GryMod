# lua/grymod/client

Everything the player sees and presses. The files are grouped by prefix.

| Files | What they do |
| --- | --- |
| `cl_flash.lua`, `cl_flash_draw.lua`, `cl_flash_prewarm.lua` | The Flash player: plays the converted timelines at 30 images per second, draws them with meshes, and loads the big pictures at the loading screen (`gry_hud_prewarm`). |
| `cl_hud.lua`, `cl_hud_flash.lua` | The HUD as a whole: the health, energy and ammo panel, the vanilla HUD elements that are hidden, the HUD switch. |
| `cl_hud_*_flash.lua` | One file for each interface movie: `quickmenu`, `radar`, `crosshair`, `binoculars`, `grenade`, `boot` (start-up, shutdown and reboot), `weaponlist`, `use` (use prompts), `messages`, `pickup`, `nightvision`, `objectives`, `corners`. They hold the rules that the original movies' ActionScript held, ported to Lua. |
| `cl_hud_radar_*.lua` | The radar around the movie: contacts (`units`), the sources other addons add, the alert hexagon (`exposure`), explosion rings (`pings`), the automatic range (`zoom`). |
| `cl_cloak_*.lua` | The camouflage's rendering: the layers drawn over the player and the weapon, the refraction, the scan lines, the pixel shader. The shader sources are in `dev_resources/shaders/`. |
| `cl_nightvision*.lua` | The night vision: the state and energy, the screen effect and the light. |
| `cl_options*.lua`, `cl_admin_option.lua`, `cl_key_binder.lua`, `cl_menu_key.lua` | The options menu (Options > GryMod), the pages and tabs, the administrators' settings, and the key picker (the engine does not let Lua run `bind`, so the keys are read by polling). |
| `cl_objectives*.lua` | The objective markers, the banner and the radar icons. |
| `cl_sounds.lua`, `cl_sound_mix.lua`, `cl_sprint_sound.lua`, `cl_underwater.lua` | The suit sounds and their mix. |
| `cl_api.lua`, `cl_api_hud_events.lua` | The client half of the extension API and the HUD events ([`docs/reference/`](../../../docs/reference/)). |
| `cl_zonemap.lua` | Receives the in/out map made by the server. |

[`minimap/`](minimap/README.md) holds the minimap and `map/` the big map (the PDA).
