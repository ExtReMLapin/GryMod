# lua/grymod/flash

The converted Crysis interface movies, one Lua file for each. **Generated; do not edit by hand.** A change made here is lost the next time the converter runs.

Each file is the data of one Flash movie: its symbols, their timelines (frames, transforms, colour transforms, masks, labels, frame actions) and the position of each shape in the texture atlases in `materials/grymod/flash/`. `lua/grymod/client/cl_flash.lua` loads them by name (`GryMod.Flash.Load("hud_quickmenu")`) and plays them; `cl_flash_draw.lua` draws them.

| File | Movie |
| --- | --- |
| `hud_ammohealthenergysuit.lua` | Health, energy, ammunition and the suit icon. |
| `hud_radarcompassstealth.lua` | The compass, the radar and the stealth bar. |
| `hud_quickmenu.lua` | The quick menu. |
| `hud_binoculars.lua` | The binoculars. |
| `hud_grenadedetect.lua` | The grenade warning. |
| `hud_crosshair.lua`, `hud_friendlycross.lua` | The crosshair and the cross on allies. |
| `hud_initialize.lua`, `hud_lost.lua`, `hud_reboot.lua`, `hud_boot_strings.lua` | The start-up log, the shutdown and the reboot sequences, and their texts. |
| `hud_weaponselection.lua`, `hud_interactiveicons.lua`, `hud_ammopickup.lua`, `hud_messages.lua` | The weapon list, the use prompts, the pickup popup, the text lines. |
| `hud_missionobjective_icon.lua`, `hud_pda_map.lua`, `hud_nightvision.lua` | The objective markers, the frame of the big map, the night vision bar. |
| `hud_corner_left.lua`, `hud_corner_right.lua` | The corner marks of the HUD. |
| `hud_sp_hexicons.lua` | The alert hexagon of the radar. |

To regenerate, see [`dev_resources/flash2lua/README.md`](../../../dev_resources/flash2lua/README.md). The ActionScript of the movies is not converted: what it did is ported by hand into the `cl_hud_*_flash.lua` files of [`client/`](../client/README.md).
