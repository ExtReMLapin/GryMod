# lua/grymod/server

The server decides; the clients draw. These files hold the rules and send the clients what they cannot work out themselves.

| Files | What they do |
| --- | --- |
| `sv_system.lua`, `sv_mechanics.lua`, `sv_health.lua` | The suit: mode changes, the energy loop, the numbers of Crysis (`gry_mechanics crysis`) or of the earlier GryMod (`classic`), health regeneration. `sv_mechanics.lua` is where every number lives. |
| `sv_malfunction.lua` | The suit going down (EMP, strong electric shocks) and coming back. |
| `sv_movement.lua`, `sv_fall_damage.lua`, `sv_underwater.lua` | Base speeds of the modes (off by default), fall damage, the drowning rule. |
| `sv_cloak_ai.lua`, `sv_suit_noise.lua`, `sv_friendly.lua`, `sv_relations.lua` | What NPCs do about a cloaked player, the noises the suit makes for other addons' AI, who counts as an ally. |
| `sv_radar.lua`, `sv_radar_pings.lua`, `sv_grenade.lua`, `sv_feedback.lua` | The radar's contacts, explosion rings, the dangerous projectiles of the grenade warning, hit direction and hit confirmation for the crosshair. |
| `sv_usable_class.lua`, `sv_usable_mass.lua` | Facts the client cannot read about entities, for the use prompt. |
| `sv_zonemap.lua` | The in/out map: computed once per map from the node graph, saved in `data/grymod/zonemap/`, sent to the players. |
| `sv_objectives.lua`, `sv_campaign.lua`, `sv_campaign_core.lua`, `sv_objectives_demo.lua` | The objectives registry and the Half-Life 2 campaign data that feeds it. |
| `sv_server_options.lua`, `sv_nightvision.lua`, `sv_weapon_zoom.lua`, `sv_zoom_fov.lua` | The administrators' settings (one net message, white-listed) and the server side of client features. |
| `sv_api.lua`, `sv_messages.lua`, `sv_mode_states.lua`, `sv_debug_cmd.lua`, `sv_players.lua` | The server half of the extension API and its helpers. |

The reference for what other addons may call or listen to is in [`docs/`](../../../docs/README.md): [`docs/reference/`](../../../docs/reference/), [`docs/hooks.md`](../../../docs/hooks.md), [`docs/networking.md`](../../../docs/networking.md).
