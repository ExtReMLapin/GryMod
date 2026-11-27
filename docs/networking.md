# Networking

This page lists the networked variables that GryMod sets and the network messages it declares. The hooks are in [hooks.md](hooks.md), the functions in [api.md](api.md); the index is [README.md](README.md).

## Read this first

The network messages are the internal protocol of the addon. They are listed here so that a maintainer can follow the traffic, not so that another addon can use them. An addon uses `GryMod.API` and the hooks. The layout of a message can change in any release, and the interface version (`GryMod.API.Version`) does not go up when it does.

The networked variables are different in one way: they are read-only for an addon. They are the reliable way to know the state of a player's suit from either realm. An addon reads them with the getters below and changes the suit with `GryMod.API` (for example `GryMod.API.SetMode`, `GryMod.API.SetEnergy`, `GryMod.API.SetSuitEnabled`). An addon that writes one of these variables itself puts the suit and the HUD out of step.

## Networked variables

GryMod uses the `NW2` functions (`SetNW2Bool`, `SetNW2Int`, `SetNW2Float`, `SetNW2Entity`). Only the server writes them. Both realms read them with the getter of the same type.

| Variable | Type | Set on | Written by | Read by |
| --- | --- | --- | --- | --- |
| `GryMode` | Int | a player | the server, `Player:SetNanosuitMode` (`lua/grymod/server/sv_system.lua`) | the weapon adapters (`lua/grymod/sh_suit_weapons.lua`), both realms |
| `GryEnergy` | Float | a player | the server (`sv_system.lua`, `sv_health.lua`, `sv_malfunction.lua`, `sv_underwater.lua`, `sv_api.lua`) | the HUD, the sounds and the weapon adapters, both realms |
| `GryCloak` | Bool | a player | the server, `Player:SetNanosuitMode` | `lua/grymod/client/cl_cloak_fx.lua`, `lua/grymod/sh_cloak_level.lua` |
| `GryCloakSince` | Float | a player | the server, `Player:SetNanosuitMode` | `lua/grymod/client/cl_cloak_fx.lua` |
| `GryCloakLvl0` | Float | a player | the server, `Player:SetNanosuitMode` | `lua/grymod/sh_cloak_level.lua` |
| `GryCloakT0` | Float | a player | the server, `Player:SetNanosuitMode` | `lua/grymod/sh_cloak_level.lua` |
| `GryDisabled` | Bool | a player | the server, `GryMod.API.SetSuitEnabled` (`lua/grymod/server/sv_api.lua`) | the server's suit code, the HUD, the quick menu |
| `GryMalfunction` | Bool | a player | the server (`lua/grymod/server/sv_malfunction.lua`) | the server's suit code, the HUD, the sounds, the zoom |
| `GryFlicker` | Float | a player | the server (`sv_malfunction.lua`) | the HUD (`lua/grymod/client/cl_hud_flash.lua`) |
| `GryDrowning` | Bool | a player | the server (`lua/grymod/server/sv_underwater.lua`) | `lua/grymod/client/cl_underwater.lua` |
| `GryArmed` | Bool | a projectile | the server (`lua/grymod/server/sv_grenade.lua`) | the grenade warning (`lua/grymod/client/cl_hud_grenade_flash.lua`), the GB5 patch |
| `GryThrower` | Entity | a projectile | the server (`sv_grenade.lua`) | the grenade warning |
| `GryGlideTarget` | Entity | a Glide missile | the server, through the missile's `armed` reader (`lua/grymod/compat/vehicles/sh_glide.lua`) | the same file, on the client |
| `GryVJFollow` | Bool | a VJ Base NPC | the server (`lua/grymod/compat/npc/sv_vjbase.lua`) | `lua/grymod/compat/npc/sh_vjbase.lua` |

### Variables of the player's suit

`GryMode` is an integer, 0 to 3, with the values of `GryMod.Modes`:

| Value | Constant | Mode |
| --- | --- | --- |
| 0 | `GryMod.Modes.ARMOR` | armor |
| 1 | `GryMod.Modes.SPEED` | speed |
| 2 | `GryMod.Modes.CLOAK` | camouflage |
| 3 | `GryMod.Modes.STRENGTH` | strength |

It is set at every call of `Player:SetNanosuitMode` that reaches the end of the function, so it is 0 after a respawn. Read it with `ply:GetNW2Int("GryMode", GryMod.Modes.ARMOR)`. `GryMod.API.GetMode(ply)` gives the same value on the server.

`GryEnergy` is the suit's energy, a float from 0 to 100. Read it with `ply:GetNW2Float("GryEnergy")`. `GryMod.API.GetEnergy(ply)` does the same on the server. A comment in `lua/grymod/server/sv_health.lua` records that the networked float reached the client about every 0.1 s (measured with the older `SetNWFloat`), so the HUD gets a finer value from the message `gry_energy` and predicts between two messages. An addon that needs the value of the bar reads the variable.

`GryCloak` is `true` while the player is in camouflage mode. The three floats that follow it describe the fade. When the camouflage starts, the server writes `GryCloakSince` (the `CurTime()` of the start, kept while the switch stays on), `GryCloakLvl0` (the cloak level at that moment) and `GryCloakT0` (the `CurTime()` of the change), and then sets `GryCloak`. When the camouflage ends the server writes `GryCloakLvl0` and `GryCloakT0` again; at a respawn `GryCloakLvl0` is 0. The client reads `GryCloakSince` with the default -1 to tell a change that is going on from one that was made long ago. Do not read the three floats for the level. `GryMod.API.CloakLevel(ply)` computes it in both realms and returns 0 to 1 (0 for a dead player). See [api.md](api.md#cloak-level-server-and-client).

`GryDisabled` is `true` while the suit is switched off with `GryMod.API.SetSuitEnabled(ply, false)`. It stays through death and respawn. Read it through `GryMod.API.IsSuitEnabled(ply)`, which gives the opposite value and works in both realms.

`GryMalfunction` is `true` while the suit is down. The server sets it when a malfunction starts and clears it when the malfunction ends, and also at a death, a respawn and a disconnect. The client fires `GryMod_MalfunctionStart` and `GryMod_MalfunctionEnd` from its changes, see [hooks.md](hooks.md).

`GryFlicker` is a time, not a flag. The server sets it to `CurTime() + 0.8` at a light shock and to 0 when a malfunction is cleared. The HUD flickers while `GryFlicker > CurTime()`.

`GryDrowning` is `true` while the player is under water with an empty suit and the drowning damage ticks run. The server clears it when the head is out of the water.

### Variables of other entities

`GryArmed` and `GryThrower` are set on every projectile that has a `danger` entry in the tracked registry (the Half-Life 2 grenades, rockets and mines, and the entries that other addons register with `GryMod.API.RegisterTracked`). A server timer refreshes them every 0.2 s, and at once when a player picks the projectile up or drops it. A value is only written when it changes. `GryArmed` is `true` while the projectile is a danger that is coming, for example a grenade whose fuse runs, and `false` for one that lies inert or is held in a player's hands. `GryThrower` is the player who threw or fired it, or `NULL` when none is known; the server writes it first, so a client that sees `GryArmed` already knows whose projectile it is. The reader is `ent:GetNW2Bool("GryArmed")` and `ent:GetNW2Entity("GryThrower")`.

`GryGlideTarget` is the entity that a Glide missile follows. The `armed` reader of the missile's registry entry writes it when the missile has a valid `target`, and it is never cleared. The client compares it with the local player and his vehicle to decide whether the missile warns him. It is only set on a missile that follows a target.

`GryVJFollow` is `true` on a VJ Base NPC whose class follows the player when he presses the use key (`ENT.FollowPlayer`). The server writes it once, 0.1 s after the NPC is made, because VJ Base keeps that field on the server only. The client uses it to offer the follow prompt for an ally.

## Network messages

All 38 messages are declared with `util.AddNetworkString`. The direction column says who sends: server to the client, client to the server, or both. "One player" means `net.Send` to a single player. A payload is written in the order of the `net.Write` calls, with the bit width after the type. A message with no payload has an empty cell.

Every message that a client sends to the server is checked by the server. Several have a rate limit, given in the tables. A message sent too often is dropped without an answer.

### Suit messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_nanosuit_mode_change` | both | Server to one player: `tellMode` in `lua/grymod/server/sv_system.lua`, when the player's client must learn the mode (a spawn, a refusal, the answer to `gry_client_ready`, a request with `networked` set). Client to server: `Player:SetNanosuitMode` in `lua/grymod/client/cl_hud.lua` when the player picks a mode | Client to server: `UInt(3)` mode. Server to client: `UInt(3)` mode, `UInt(4)` cause (`GryMod.ModeReasonIds`, the position in `GryMod.ModeReasonList` minus 1) | The server accepts a mode of 0 to 3, applies it with the cause `"player"` and answers a mode that is not valid with the real mode and the cause `"vetoed"`. The client applies the mode, and an unknown cause becomes `"other"` |
| `gry_client_ready` | client to server | `GryMod.SendReady` (`lua/grymod/client/cl_hud.lua`) at `InitPostEntity` and when the file is loaded again in a running game | | The server answers with `gry_nanosuit_mode_change` (cause `"sync"`), pushes `gry_modes_refused` and sends the objectives. One answer per player per second (`GryMod.ReadyInterval`) |
| `gry_spawn` | server to one player | `PlayerSpawn` listener in `lua/grymod/server/sv_system.lua`, not for a respawn in place that an addon kept | | The client marks the spawn so that the first second has no mode tint, and 2 s and 2.5 s later may ask for the quick menu key and the zoom key (`lua/grymod/client/cl_hud.lua`) |
| `gry_modes_refused` | server to one player | `GryMod.ModeStates.Push` (`lua/grymod/server/sv_mode_states.lua`): at `gry_client_ready`, at each spawn, and when the answer of the `GryMod_CanSetMode` listeners changed | `UInt(3)` mask: bit 0 speed, bit 1 camouflage, bit 2 strength; a set bit is a refused mode | The quick menu (`lua/grymod/client/cl_hud_quickmenu_flash.lua`) greys the refused modes |
| `gry_jump` | server to one player | a strength jump is granted (`GryMod.SuperJump` in `sv_system.lua`) | | The client plays the jump sound |
| `gry_cloak_shot` | server to one player | a shot by a camouflaged player: the `EntityFireBullets` listener in `sv_system.lua`, or `GryMod.API.ReportAttack` in `lua/grymod/server/sv_api.lua` | `Bool` the shot came from the right click alone | `GryMod.CloakShot` (`cl_hud.lua`) ends the camouflage when the local mode is camouflage and, for a right click, `gry_cloak_altfire` is on. It sends `gry_empty_energy` and plays the HUD event `decloak` |
| `gry_empty_energy` | client to server | the client ends the camouflage by an act of the player (`endCloak` in `cl_hud.lua`) | | The server sets `GryEnergy` to 0 and runs `GryUseEnergy`. The server does not check who asks |
| `gry_armor_hit_sound` | server to one player | a bullet hit in armor mode that the sound rule accepts (`Mech.ArmorHitSoundDue` in `lua/grymod/server/sv_health.lua`) | | The client plays the HUD event `armor_hit` without the picture |

### Energy, health and water messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_energy` | server to one player, unreliable | the `Think` listener `GryMod energy net` (`sv_health.lua`) sends it to each human player whenever `GryEnergy` or its rate of change differs from the last message. Off with `gry_energy_net 0` | `Float` energy, `Float` rate in energy points per second | `lua/grymod/client/cl_energy_smooth.lua` keeps both and predicts the bar between two messages. An old value is replaced by the networked float |
| `gry_start_health_regen` | server to one player | the repair sound is due, or the classic regeneration starts (`sv_health.lua`) | | The client plays the HUD event `regen_start` (the repair sound, unless `gry_sound_regen` is 0) |
| `gry_stop_health_regen` | server to one player | the player is hit, the health is full, the regeneration is switched off or the player dies (`sv_health.lua`) | | The client plays the HUD event `regen_stop` (the repair sound fades out) |
| `gry_drown_tick` | server to one player | a drowning tick that does damage (`Drown.Notify` in `lua/grymod/server/sv_underwater.lua`) | | The client plays the HUD event `drown` (a gasp) |

### Crosshair feedback messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_damage_dir` | server to one player | a player is hurt by an attacker (`GryMod.Feedback.OnHit` in `lua/grymod/server/sv_feedback.lua`), at most 10 times a second for each victim | `Normal` the unit vector from the victim to the attacker | The crosshair draws the damage arcs (`lua/grymod/client/cl_hud_crosshair_flash.lua`) |
| `gry_hit` | server to one player | a player hurts a living target: a creature, a player or a nextbot (`sv_feedback.lua`) | | The crosshair blinks |

### Questions that a client asks the server

The client cannot read some facts, so it asks and the server answers one player. The questions share a pattern: an entity index in 13 bits.

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_friendly_ask` | client to server | the crosshair is on an NPC, at most once a second for it (`lua/grymod/client/cl_hud_crosshair_flash.lua`) | `UInt(13)` entity index | The server answers with `gry_friendly`. A player may ask 5 times a second; the rest is ignored (`lua/grymod/server/sv_friendly.lua`) |
| `gry_friendly` | server to one player | the answer to `gry_friendly_ask` | `UInt(13)` entity index, `Bool` is an ally, `UInt(2)` relation code (0 neutral, 1 ally, 2 hostile) | The client keeps the answer for 2 s and draws the friendly cross for an ally. It reads the relation code only when the message has bits left |
| `gry_relations_ask` | client to server | the binoculars' hologram asks about the NPCs in view (`lua/grymod/client/cl_hud_binoculars_holo.lua`) | `UInt(5)` count (16 at most), then `UInt(13)` entity index for each | The server answers with `gry_relations`. Two questions of a player must be at least 0.3 s apart (`lua/grymod/server/sv_relations.lua`) |
| `gry_relations` | server to one player | the answer to `gry_relations_ask` | `UInt(5)` count, then for each entity `UInt(13)` index, `UInt(2)` relation code (0 neutral, 1 ally, 2 hostile), `UInt(2)` alert level (0 idle, 1 alerted, 2 in combat) | The hologram keeps the relation and the level. An index that is not an entity is left out of the list |
| `gry_mass_ask` | client to server | the crosshair is on a prop that looks liftable (`cl_hud_crosshair_flash.lua`), again every 3 s while it stays aimed | `UInt(13)` entity index | The server answers with `gry_mass`. 10 questions a second at most (`lua/grymod/server/sv_usable_mass.lua`) |
| `gry_mass` | server to one player | the answer to `gry_mass_ask`, only for an entity that has a physics object | `UInt(13)` entity index, `Float` mass in kilograms (all the physics objects added) | The use prompt offers "pick up" for a prop of 35 kg or less |
| `gry_class_ask` | client to server | the crosshair is on an entity whose client class name is generic, such as a `func_button` (`lua/grymod/client/cl_usable_class.lua`) | `UInt(13)` entity index | The server answers with `gry_class`. 10 questions a second at most (`lua/grymod/server/sv_usable_class.lua`) |
| `gry_class` | server to one player | the answer to `gry_class_ask` | `UInt(13)` entity index, `String` the class name the map gave the entity | The client keeps it for 20 s and the registry of usable things matches on it |

### Zoom messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_zoom_fov` | client to server | while the own zoom of the binoculars is up: at each change of more than 0.05 degrees and once a second while it holds; 0 once when it ends (`lua/grymod/client/cl_zoom_fov.lua`) | `Float` field of view in degrees; 0 is back to normal | The server sets the player's field of view and fires `GryMod_Zoom` (`lua/grymod/server/sv_zoom_fov.lua`). A request that does not come again within 3 s is ended. 10 requests a second at most |
| `gry_cancel_weapon_zoom` | client to server | the binoculars go up while the weapon in hand holds a zoom (`lua/grymod/client/cl_weapon_zoom.lua`) | | The server ends the weapon's zoom, only for a weapon whose registry entry says `alt = "zoom"` and that owns the zoom (`lua/grymod/server/sv_weapon_zoom.lua`). 5 requests a second at most |

### Radar messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_radar_want` | client to server | the HUD starts or stops wanting the radar's contacts, and when the radius changes (`Radar.TellServer` in `lua/grymod/client/cl_hud_radar_units.lua`) | `Bool` wanted, `UInt(8)` radius in metres | The server keeps both for the player (`lua/grymod/server/sv_radar.lua`). The radius is held between 5 and 100, and 0 or nothing is 75 |
| `gry_radar` | server to one player | the 0.2 s radar timer, when the list of contacts changed; an empty list once when the contacts end (`sv_radar.lua`) | `UInt(7)` count (48 at most), then for each contact: `UInt(13)` entity index, `UInt(3)` icon type, `UInt(3)` subtype, `Bool` marker, `Bool` big, `Int(13)` x, `Int(13)` y, `Int(13)` z (positions in steps of 8 units), `UInt(9)` yaw in 512 steps of the circle | The client keeps the list and draws the radar (`lua/grymod/client/cl_hud_radar_units.lua`). The layout is in `GryMod.RadarShared.Write` and `Read` (`lua/grymod/sh_radar.lua`) |
| `gry_radar_detect` | server to one player | what the hostiles that are not contacts know of the player changed (`Radar.SendDetect` in `sv_radar.lua`) | `UInt(2)` highest level over the soldiers, `UInt(2)` highest level over the machines (0 nothing, 1 hears, 2 sees), `UInt(6)` the highest exposure in steps of 1/63 | The danger bar and the hexagon take the values as a minimum (`Radar.ReadDetect`) |
| `gry_radar_ping` | server to the players in reach | a ping is accepted (`send` in `lua/grymod/server/sv_radar_pings.lua`). The recipients are the living players within 250 m of the position | `Vector` position, `UInt(5)` size in half metres, from 1 to 16 | The client adds a ring at the position that lives 2 s (`lua/grymod/client/cl_hud_radar_pings.lua`) |
| `gry_radar_scan` | client to server | the binoculars' scan ended on an entity (`locked` in `lua/grymod/client/cl_hud_binoculars_flash.lua`) | `UInt(13)` entity index | `Radar.Scan` tags the entity for the player if it is valid, scannable and within 330 m, and may fire `GryMod_TargetSpotted` |

### HUD event message

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_api_hud` | server to the players given | `GryMod.API.HUDEvent(players, name, data)` (`lua/grymod/server/sv_api.lua`) after `API.CheckHUDEvent` accepted the arguments | `String` event name; `UInt(4)` number of fields (8 at most); for each field `String` key, `UInt(2)` type (0 number, 1 string, 2 boolean), then `Double`, `String` or `Bool` | The client reads it with `API.ReadHUDEvent`, which drops a message that breaks the limits (a name of 32 characters, a key of 24, a string of 128), and plays the event with `GryMod.API.HUDEvent` (`lua/grymod/client/cl_api.lua`). The layout is in `lua/grymod/sh_api.lua`. See [events.md](events.md) |

### Objectives message

`gry_objectives` carries every change of the objectives from the server to the clients. It is one message name with several operations. The server sends each one to the ready players that may see the objective (`lua/grymod/server/sv_objectives.lua`), and nothing is sent while `gry_objectives` is 0. The client reads it in `Obj.Receive` (`lua/grymod/client/cl_objectives.lua`).

Every message starts with `UInt(3)` operation. The operations are in `GryMod.Objectives.Ops` (`lua/grymod/sh_objectives.lua`):

| Value | Operation | Rest of the payload | Sent when |
| --- | --- | --- | --- |
| 0 | `SET` | a record, see below | an objective is added, or the values of one the client has changed |
| 1 | `REMOVE` | `String` id, `UInt(2)` cause | an objective is gone for this player. The cause is the position in `GryMod.Objectives.ReasonList` minus 1: 0 `"removed"`, 1 `"cleared"`, 2 `"entity_removed"`, 3 `"map_changed"` |
| 2 | `CLEAR` | `UInt(2)` cause | all objectives are gone |
| 3 | `MAIN` | `String` id, empty for none | the main objective changed; each player gets the id only if he may see it |
| 4 | `POS` | `UInt(9)` count, then `String` id and `Vector` position for each | objectives that follow an entity moved more than 32 units, checked twice a second |
| 5 | `BEGIN` | | a full list follows; what the list does not mention is gone when `END` comes |
| 6 | `END` | | the end of the full list |

The full list is sent to a player when he says he is ready (`gry_client_ready`): `BEGIN`, a `SET` for each objective he may see, `END`.

The record of a `SET` is written by `GryMod.Objectives.WriteRecord` in this order:

| Field | Type |
| --- | --- |
| id | `String` |
| title | `String` |
| description | `String` |
| primary | `Bool` |
| state | `UInt(2)`, 0 `"active"`, 1 `"done"`, 2 `"failed"` |
| main | `Bool` |
| radar | `Bool` |
| marker | `Bool` |
| position | `Vector` |
| entity index | `UInt(14)`, 0 for none |
| number of waypoints | `UInt(5)`, 16 at most |
| each waypoint | `Vector` |

The client drops a record that breaks the limits of `GryMod.Objectives.Limits` (an id of 64 characters, a title of 128, a description of 512).

### In/out map messages

The in/out map is made by the server and sent to the clients (`lua/grymod/server/sv_zonemap.lua`, `lua/grymod/client/cl_zonemap.lua`).

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_zonemap_want` | client to server | when the client's file loads, repeated every 3 s up to 10 times until the server answers, when the setting `gry_zonemap` goes on, and again after a file that did not arrive whole (`Z.Want` in `cl_zonemap.lua`) | | The server answers the asker with `gry_zonemap_state` and, when the map is ready or incomplete, with the file. 2 requests a second at most |
| `gry_zonemap_state` | server to everyone, or one player | at each change of state, while computing at most four times a second; to one player when he asks (`ZS.SendState`) | `UInt(3)` state, `UInt(24)` points done, `UInt(24)` points in all | `Z.OnState` keeps the state and fires `GryMod_InOutMapState`. The states are 0 off, 1 no graph, 2 waiting, 3 computing, 4 ready, 5 incomplete, 6 failed |
| `gry_zonemap_data` | server to everyone, or one player | when the map becomes ready or incomplete, and to one player when he asks and a map exists (`ZS.SendData`). The file goes in chunks of at most 30000 bytes, one message each | `UInt(16)` index of the chunk, from 0, `UInt(16)` number of chunks, `UInt(16)` length of this chunk, `Data` the bytes | `Z.OnData` joins the chunks, decodes the file and fires `GryMod_InOutMapReady`. A chunk out of order drops the set and the client asks again, at most once every 5 s |
| `gry_zonemap_reset` | client to server | the administrator confirms "Delete and remake the in/out map" in the options (`lua/grymod/client/cl_options_radar.lua`) | | The server deletes the file and the map of the current source and makes it again, if `GryMod.MayConfigure` accepts the sender. 1 request a second at most. A refusal is silent |

### Options and debug messages

| Message | Direction | Sent when | Payload | What the receiver does |
| --- | --- | --- | --- | --- |
| `gry_set_server_option` | client to server | an administrator changes a server setting in the options panel (`UI.Transport` in `lua/grymod/client/cl_admin_option.lua`) | `String` name of the setting, `String` value | The server checks, in this order: the rate (5 messages a second), the sender (`GryMod.MayConfigure`), the name against the white list of `lua/grymod/sh_server_options.lua`, and the value. Then it sets the convar. A refusal is silent (`lua/grymod/server/sv_server_options.lua`) |
| `gry_debug_cmd` | client to server | the effects test window runs a real command (`DW.SendCommand` in `lua/grymod/client/cl_debug_window.lua`) | `String` command id | The server runs the command registered with `GryMod.API.RegisterDebugCommand` on the sender, under `SafeCall`, if `GryMod.MayConfigure` accepts him. One message every 0.2 s per player (`lua/grymod/server/sv_debug_cmd.lua`) |
| `gry_debug_list` | both | Client to server: the window opens. Server to the player: the answer | Client to server: none. Server to client: `UInt(8)` count (255 at most), then `String` id and `String` label for each command | The server sends the list of the registered commands to an administrator and an empty list to another player. The window shows the list |

The action options of the panel (`opts.message` in `lua/grymod/client/cl_admin_option.lua`) send a message with no payload by its name. The only one in the panel today is `gry_zonemap_reset`.
