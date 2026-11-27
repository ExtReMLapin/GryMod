# Hooks

This page lists the hooks that GryMod fires for other addons to listen to. A listener is added with `hook.Add("<HookName>", "my_addon", function(...) end)`.
The terms (suit, mode, energy, malfunction, HUD event) are the ones of [api.md](api.md) and [events.md](events.md); the index is [README.md](README.md).

## Conventions

- A hook named `GryMod_<Event>` reports that something happened. GryMod does not read what a listener returns and a listener cannot change the result.
- A hook named `GryMod_Can<Action>` is a veto. A listener that returns `false` refuses the action. Any other return value, including `nil` and `true`, allows it.
- `GryMod_EMP` is the one hook that asks GryMod to do something: GryMod listens to it itself.
- The engine's `hook.Run` stops at the first listener that returns a value other than `nil` and gives that value back. For a veto this means that the first listener that answers decides. A listener that returns `true` hides the listeners after it, so a listener that has no objection returns nothing.
- A hook that an entry says is run under `pcall` (or `ProtectedCall`) cannot break GryMod: an error in your listener is printed and the code goes on. Every other hook is run with a plain `hook.Run`, and an error in your listener reaches GryMod's own code. Keep listeners short and guard them.
- A hook that is fired on the server is fired for every player, bots included, unless the entry says otherwise. A hook that is fired on the client concerns the local player, unless the entry says otherwise.

| Hook | Realm | For |
| --- | --- | --- |
| `GryMod_ModeChanged` | Server and client | every player (server), the local player (client) |
| `GryMod_CanSetMode` | Server | every player |
| `GryMod_EnergyUsed` | Server | every player |
| `GryMod_EnergyEmpty` | Server | every player |
| `GryMod_ArmorAbsorbed` | Server | every player |
| `GryMod_StrengthJump` | Server | every player |
| `GryMod_SprintStart`, `GryMod_SprintEnd` | Server | every player |
| `GryMod_MalfunctionStart`, `GryMod_MalfunctionEnd` | Server and client, different arguments | every player |
| `GryMod_EMP` | Server | every living player in range |
| `GryMod_Zoom` | Server | every player |
| `GryMod_RadarPing` | Server | none (a position) |
| `GryMod_HUDStatus` | Client | the local player |
| `GryMod_HUDEvent` | Client | the local player |
| `GryMod_BinocularsToggled` | Client | the local player |
| `GryMod_SuitZoom` | Client | the local player |
| `GryMod_CanUseView` | Client | the local player |
| `GryMod_CloakChanged` | Client | every player the client follows |
| `GryMod_SuitEnabled`, `GryMod_SuitDisabled` | Server | the player whose suit flag changed |
| `GryMod_CanResetOnSpawn` | Server | every player who respawns |
| `GryMod_SuitNoise` | Server | the player who made the noise |
| `GryMod_Explosion` | Server | none (a position) |
| `GryMod_TargetSpotted` | Server | the player whose binoculars scanned |
| `GryMod_UsableChanged` | Client | the local player |
| `GryMod_MessageShown` | Client | the local player |
| `GryMod_WeaponHeat` | Client | the local player |
| `GryMod_WeaponListShown` | Client | the local player |
| `GryMod_RadarExposure` | Client | the local player |
| `GryMod_NightVision` | Client | the local player |
| `GryMod_InOutMapReady`, `GryMod_InOutMapState` | Client | the local player |
| `GryMod_MinimapProgress`, `GryMod_MinimapReady` | Client | the local player |
| `GryUseEnergy` | Server | every player |
| `GryNanosuitMode` | Server | every player |

## Suit hooks (server and client)

### GryMod_ModeChanged(ply, mode, oldMode, reason)

Realm: server and client. Same name and same arguments in both.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit changed mode |
| `mode` | number | the new mode: `GryMod.Modes.ARMOR` 0, `SPEED` 1, `CLOAK` 2, `STRENGTH` 3 |
| `oldMode` | number | the mode before |
| `reason` | string | one of `GryMod.ModeReasons`: `"spawn"`, `"player"`, `"api"`, `"energy"`, `"malfunction"`, `"disabled"`, `"other"`, `"vetoed"`, `"sync"`, `"restore"` |

Return value: not read.

For every player on the server. On the client only for the local player, which is the only one whose mode the client knows.

When it fires, on the server (`Player:SetNanosuitMode` in `lua/grymod/server/sv_system.lua`): when `mode` differs from `oldMode`, and at every respawn (`reason == "spawn"`), including armor to armor. A mode request that the suit refuses (veto, malfunction, suit off) does not fire it for the mode asked: a suit that is down or off goes to armor and the hook reports that change with `"malfunction"` or `"disabled"`. A respawn in place that an addon kept with `GryMod_CanResetOnSpawn` does not fire it (`reason` `"restore"`, same mode). The hook runs after `GryNanosuitMode` and before the client is told. At a respawn the energy is already 100.

When it fires, on the client (`announceMode` in `lua/grymod/client/cl_hud.lua`): under the same rule, after the client's `NanosuitMode` field holds the new mode. When the player changes the mode himself, the client runs it at once with `"player"`. If the server then refuses, it sends the real mode back and a second run follows on the client with `"vetoed"`, `"malfunction"` or `"disabled"`. The mode of a client that is still loading counts as armor and as the old mode.

The meaning of each `reason` is in [api.md](api.md#why-the-mode-changed-grymodmodereasons).

```lua
hook.Add("GryMod_ModeChanged", "my_addon", function(ply, mode, oldMode, reason)
	if reason == GryMod.ModeReasons.SPAWN then
		-- the suit was reset by the respawn: put my own look back
	end
end)
```

### GryMod_CanSetMode(ply, mode)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit would change mode |
| `mode` | number | the mode asked: `GryMod.Modes.SPEED` 1, `CLOAK` 2 or `STRENGTH` 3 |

Return value: `false` refuses the mode. `nil`, `true` or any other value allows it. The first listener that returns a value other than `nil` ends the call, so a listener that returns `true` hides a later one that would return `false`.

When it fires: in `Player:SetNanosuitMode` (`lua/grymod/server/sv_system.lua`), for every path that changes the mode (the player's request, `GryMod.API.SetMode`, any caller). It is not asked for armor, for the mode the suit is already in, or while the suit is down or off. A refusal leaves the suit as it was, tells the client the real mode with the cause `"vetoed"` and makes `SetNanosuitMode` return `false, "vetoed"`.

The hook is also asked without any mode change, in `lua/grymod/server/sv_mode_states.lua`: once for each of the modes speed, cloak and strength that is not the current one, for each living player, to tell the quick menu which modes to grey out. It runs under `pcall` there, and an error in a listener counts as no refusal. This happens when the client is ready, at each spawn, when the mode, a malfunction or the suit flag changes, when an addon calls `GryMod.API.RefreshModeStates(ply)`, and every 0.5 s while a listener exists and a player is alive. A listener must answer without side effects and must be cheap.

GryMod has one listener of its own, `GryMessagesCloakHealth` (`lua/grymod/server/sv_messages.lua`). It returns `false` for `GryMod.Modes.CLOAK` when the setting `gry_cloak_min_health` is above 0 and the player's health is at or under it. The setting is 0 by default.

```lua
hook.Add("GryMod_CanSetMode", "my_addon", function(ply, mode)
	if mode == GryMod.Modes.CLOAK and ply:GetNWBool("MyAddon_NoCloak") then
		return false
	end
end)
```

See [api.md](api.md#veto-grymod_cansetmodeply-mode) for the quick menu and `RefreshModeStates`.

## Energy and damage hooks (server)

### GryMod_EnergyUsed(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose energy was used |

Return value: not read.

When it fires: each time `GryUseEnergy` is run (`lua/grymod/server/sv_api.lua`, the listener `GryMod API energy`). `GryUseEnergy` is run, after the new value of `GryEnergy` is set, by:

- `GryMod.API.SetEnergy` and the functions built on it (`lua/grymod/server/sv_api.lua`);
- a hit taken by the armor (`lua/grymod/server/sv_health.lua`);
- the start of a malfunction and a light shock (`lua/grymod/server/sv_malfunction.lua`);
- the speed sprint drain, the camouflage drain, the cost of a jump in speed or strength mode, and the message `gry_empty_energy` (`lua/grymod/server/sv_system.lua`).

It is not fired when the bar recharges, when the player drains it underwater (`lua/grymod/server/sv_underwater.lua`), at a respawn, or when a malfunction ends. During a sprint or a camouflage it fires on every server tick. Listeners run often, so keep them cheap.

An addon that runs `hook.Run("GryUseEnergy", ply)` itself also triggers this hook.

### GryMod_EnergyEmpty(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose bar reached 0 |

Return value: not read.

When it fires: at a run of `GryUseEnergy` (see `GryMod_EnergyUsed`, same listener in `lua/grymod/server/sv_api.lua`) when `GryEnergy` is 0 or less, and only once. The hook is armed again when a run of `GryUseEnergy` finds the bar above 0, and at every respawn (not at a respawn that an addon kept with `GryMod_CanResetOnSpawn`). `GryMod_EnergyUsed` is fired before it. A bar that reaches 0 without a run of `GryUseEnergy` (the underwater drain) does not fire it. The start of a malfunction empties the bar and runs `GryUseEnergy`, so it fires this hook when the bar was not already reported empty.

### GryMod_ArmorAbsorbed(ply, absorbed, passed)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player who was hit |
| `absorbed` | number | the points of the hit that the armor took, above 0 |
| `passed` | number | the points that went on to the health |

`absorbed + passed` is the damage of the hit as it came.

Return value: not read.

When it fires: in the `EntityTakeDamage` listener `Grymod damage handeling` (`lua/grymod/server/sv_health.lua`), after the damage of the hit was changed. It fires when the player is in armor mode, the suit is on, and the armor took part of the hit. It fires in three cases:

- with the infinite armor: `passed` is 0;
- when the bar held enough energy for the whole hit: `passed` is 0;
- when the bar was not enough: `passed` is what remains of the damage after the armor's share. The armor takes at least a part of the hit even with an empty bar.

It does not fire when `absorbed` would be 0, for a player in god mode, for a hit that a hit filter (`GryMod.API.AddHitFilter`) answered with `"ignore"` or `"bypass"`, or outside armor mode. The `DamageInfo` already holds `passed` when the hook runs. A listener that calls `TakeDamage` starts a nested damage event and runs the armor's handler again, so it needs a guard.

### GryMod_StrengthJump(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player who jumped |

Return value: not read.

When it fires: in `GryMod.SuperJump` (`lua/grymod/server/sv_system.lua`, the `KeyPress` listener `KeyPressedStrengthGry`), once per press of the jump key, right after the jump power is raised to 500, the energy is paid and the message `gry_jump` is sent. The conditions are: the player is alive, not in a vehicle, in strength mode, on the ground, and has the energy for the jump or the infinite armor is on. With the infinite armor the jump is free and the hook fires. The weaker jump that a player gets when the bar is too low does not fire it.

### GryMod_SprintStart(ply), GryMod_SprintEnd(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the sprinting player |

Return value: not read.

When they fire: the `Think` listener `GrySpeedThink` (`lua/grymod/server/sv_system.lua`) follows `GryMod.IsSpeedSprinting(ply)` for each player. The start fires once when the player is alive and the answer turns true: not in a vehicle, sprinting, faster than the sprint speed, on the ground or swimming, in speed mode, and the infinite armor is off. The end fires once when the answer turns false or the player dies. A change of mode or a death ends a sprint, and the end is reported on the next tick. A player who disconnects while sprinting gets his end at once (`PlayerDisconnected`), so a start always has an end.

## Malfunction hooks

### GryMod_MalfunctionStart(ply, seconds, reason)

Realm: server. The client fires the same name with a different list, see below.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit went down |
| `seconds` | number | the length of the malfunction, held between 0.1 and 60 |
| `reason` | string | `"emp"`, `"shock"`, `"overload"`, `"impact"`, or the text given to `GryMod.API.StartMalfunction` (`"api"` when none) |

Return value: not read.

When it fires (server, `Malfunction.Start` in `lua/grymod/server/sv_malfunction.lua`): when a suit that was working goes down. By then the mode is forced to armor (with `GryMod_ModeChanged` and the cause `"malfunction"` when it was not armor), `GryEnergy` is set to 0 and `GryUseEnergy` has run. A call that only makes a running malfunction longer does not fire it. A call that does not start one (the player is dead, malfunctions are off, the infinite armor is on, the suit is off) fires nothing.

Realm: client, `GryMod_MalfunctionStart(ply)`.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit went down |

When it fires (client, `lua/grymod/client/cl_mode_fx.lua`): when the networked variable `GryMalfunction` of any player the client knows changes from `false` to `true`. The client has no duration and no cause. The first values that the client learns when it joins or when a player comes into view are not reported. It is run under `pcall`.

### GryMod_MalfunctionEnd(ply)

Realm: server and client, both with the same arguments.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit came back |

Return value: not read.

When it fires on the server (`Malfunction.End` in `lua/grymod/server/sv_malfunction.lua`): when the malfunction's timer ends and the suit restarts. It fires after `GryMalfunction` is set to `false`, the energy is 0 and the grace period of 3 seconds starts. It does not fire when the malfunction is cleared by a death, a respawn or a disconnect.

When it fires on the client (`lua/grymod/client/cl_mode_fx.lua`): when `GryMalfunction` of any player the client knows changes from `true` to `false`, including when the server clears it at a death, a respawn or a disconnect. It is run under `pcall`.

### GryMod_EMP(pos, radius, seconds)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `pos` | Vector | the centre of the pulse |
| `radius` | number | the radius in Source units; `math.huge` reaches every living player |
| `seconds` | number or nil | the length of the malfunction; `nil` is 10 seconds |

Return value: not read.

GryMod listens to this hook (`lua/grymod/server/sv_malfunction.lua`, the listener `GryMod malfunction`). Running it puts the suit of every living player whose `WorldSpaceCenter` is within `radius` of `pos` down, with the reason `"emp"`. It does nothing when `gry_malfunction` or `gry_malfunction_emp` is off. The grace period that follows a restart does not protect from it.

GryMod runs the hook itself for the console command `gry_emp [seconds] [radius]`: at the position of the player who typed it with a radius of 400, or, from the server console, with `vector_origin` and `math.huge`. `GryMod.API.EMP` does the same work without running the hook.

```lua
hook.Run("GryMod_EMP", ply:GetPos(), 600, 8)
```

## Zoom and radar hooks (server)

### GryMod_Zoom(ply, fov)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the zooming player |
| `fov` | number | the field of view in degrees that the server asks of the engine for the player; 0 when the zoom is over |

Return value: not read.

When it fires: in `lua/grymod/server/sv_zoom_fov.lua`, when the value really changes, never twice in a row with the same value. It follows the message `gry_zoom_fov`, which the client sends while the own zoom of the binoculars is up. It covers that zoom and the binoculars, not the zoom of a weapon such as the crossbow. A value below 5 is held at 5. The end (`fov` 0) is also reported when the client stops asking for 3 seconds, when the player dies and when he leaves, but only if a zoom was held.

### GryMod_RadarPing(pos, size, automatic)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `pos` | Vector | where the ring appears |
| `size` | number | the size in metres, from 0.5 to 8 |
| `automatic` | boolean | `true` for a ping that GryMod made from an explosion, `false` for one that came from `GryMod.API.ReportRadarPing` |

Return value: not read.

When it fires: in `send` (`lua/grymod/server/sv_radar_pings.lua`), each time a ping is accepted. A ping is refused, and the hook does not fire, for an invalid position or kind and when 20 pings were already made in the same second. The hook fires also when no player is within the reach of 250 m, in which case no message is sent.

## Client hooks

### GryMod_HUDStatus(status, why)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `status` | number | 0 the suit works, 1 malfunction, 2 flicker |
| `why` | string or nil | `"death"`, `"respawn"` or `"gone"`; `nil` for a change that comes from the suit |

Return value: not read.

When it fires: in `lua/grymod/client/cl_hud_flash.lua`, once at each change of the HUD's status, from the HUD's frame code, so only while the HUD is drawn. `status` 1 is a malfunction that the server reports through `GryMalfunction` (and, with `gry_malfunction_empty 1`, an empty bar). `status` 2 is the light shock flicker. `why` is `"death"` with `status` 1 when the player dies with the red HUD, `"respawn"` with `status` 0 when the life is back, and `"gone"` with `status` 0 when the HUD is dropped and will not be shown (the suit is off, the HUD is switched off, or a death with no red HUD). `"gone"` is only reported when the last reported status was not 0.

A HUD that is built again starts at 0 and does not report it. The hook has no previous value: keep it yourself. For the state of the suit itself use `GryMod_MalfunctionStart` and `GryMod_MalfunctionEnd`. See [events.md](events.md#grymod_hudstatusstatus-why) for the sequences it drives.

### GryMod_HUDEvent(name, data)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `name` | string | the name of the HUD event |
| `data` | table | the data the event was played with; an empty table when none was given |

Return value: not read.

When it fires: in `GryMod.API.HUDEvent` (`lua/grymod/client/cl_api.lua`), after the handler of the event ran without error. It fires for every HUD event played on this client: the events that GryMod plays for itself, the ones another addon registers, and the ones the server asks for with the message `gry_api_hud`. An event that is unknown or whose handler raised an error does not fire it. The list of events is in [events.md](events.md#the-events).

### GryMod_BinocularsToggled(wanted)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `wanted` | boolean | `true` when the player puts the binoculars up, `false` when he puts them down |

Return value: not read.

When it fires: in `Bino.CheckToggled` (`lua/grymod/client/cl_hud_binoculars_flash.lua`), once at each change of the answer "the binoculars are wanted". It is wanted when the player is alive and either holds the game's zoom key (`IN_ZOOM`) or has the own zoom open (`GryMod_SuitZoom`). The answer is read when one of those two reports something, not at every frame. It says what the player asks for, not what the screen shows: it does not look at `gry_hud` or `gry_hud_binoculars`. A player who dies while holding the zoom key and lets go of it while dead leaves the answer stale until the next key event or zoom event. Nothing is reported when the file loads.

### GryMod_SuitZoom(active, reason)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `active` | boolean | `true` when the own zoom opened, `false` when it closed |
| `reason` | string or nil | why it closed; `nil` when `active` is `true` |

Return value: not read.

When it fires (`lua/grymod/client/cl_suit_zoom.lua`): `GryMod_SuitZoom(true)` when the own zoom of the binoculars (`gry_zoom_own`, its own key) opens, which happens only when nothing in the world prevents it and no `GryMod_CanUseView` listener refuses. `GryMod_SuitZoom(false, reason)` once when an open zoom closes. The game's zoom key does not fire it; use `GryMod_BinocularsToggled` for both. A reset of the module (a reload of the file) is silent.

The values of `reason`:

| Kind | Values |
| --- | --- |
| Soft: the binoculars close in 0.2 s | `"release"`, `"toggle"`, `"weapon"`, `"weaponkey"`, `"water"` |
| Hard: the binoculars are put away at once | `"init"`, `"death"`, `"disabled"`, `"quickmenu"`, `"pause"`, `"console"`, `"ui"`, `"chat"`, `"focus"`, `"malfunction"`, `"vehicle"`, `"thirdperson"`, `"viewentity"`, `"viewtaken"`, `"cameraowner"`, `"observer"`, `"frozen"`, `"shutdown"`, `"spawnmenu"`, `"contextmenu"` |

### GryMod_CanUseView(kind, reason)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `kind` | string | `"nightvision"` or `"zoom"` |
| `reason` | string | what asks: `"key"`, `"bind"`, `"toggle"`, `"api"`, `"event"` or `"query"` |

Return value: `false` refuses. `nil`, `true` or any other value allows. The first listener that returns a value other than `nil` ends the call.

When it fires: when the night vision (`NV.Refusal` in `lua/grymod/client/cl_nightvision.lua`) or the suit's own zoom (`vetoed` in `lua/grymod/client/cl_suit_zoom.lua`) is about to switch on or open, and only after every other condition allowed it. `reason` is `"query"` when the question changes nothing (`NightVision.CanTurnOn`, `SuitZoom.CanEnter`), so a listener must not have side effects. For the zoom `reason` is `"key"` or `"bind"` when the player opens it. A night vision or a zoom that is already on is not switched off by this hook; use a camera owner for that (see [api.md](api.md#the-view-cameras-the-hud-the-relation-and-the-players-parts-client)).

```lua
hook.Add("GryMod_CanUseView", "my_addon", function(kind, reason)
	if MyAddon.CameraIsUp then return false end
end)
```

### GryMod_CloakChanged(ply, cloaked, level)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose camouflage changed |
| `cloaked` | boolean | the new state: the player's `GryCloak` flag is set and he is alive |
| `level` | number | `GryMod.API.CloakLevel(ply)` at that moment, from 0 to 1 |

Return value: not read.

For every player the client follows, not only the local one. A player is followed from the moment the client sees him camouflaged, so the first report for a player is `cloaked = true`. A player who is camouflaged when he comes into view is reported as `true`.

When it fires: in `F.Update` (`lua/grymod/client/cl_cloak_fx.lua`), from the `Think` listener `GryCloakFX`, once at each change of `cloaked`. A camouflaged player who dies is reported as `false`, because `cloaked` also needs him alive. The level follows the fade described in [api.md](api.md#cloak-level-server-and-client).

## Suit state hooks (server)

### GryMod_SuitEnabled(ply), GryMod_SuitDisabled(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit was switched on or off |

Return value: not read.

When they fire: in `GryMod.API.SetSuitEnabled` (`lua/grymod/server/sv_api.lua`), when the state really changes. `GryMod_SuitDisabled` follows a call with `false`, `GryMod_SuitEnabled` a call with `true`. A call that repeats the current state fires nothing. `GryDisabled` is already set when the hook runs, and a suit that was not in armor mode has already been put in armor with `GryMod_ModeChanged` and the cause `"disabled"`.

### GryMod_CanResetOnSpawn(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player who is respawning |

Return value: `false` keeps the suit's state at this spawn. Any other value, including `nil`, lets the spawn reset it. The first listener that returns a value other than `nil` ends the call.

When it fires: in `GryMod.KeepStateOnSpawn` (`lua/grymod/server/sv_system.lua`), called by every `PlayerSpawn` listener of GryMod that resets something. The answer is kept for the tick, so the listeners are asked once per spawn. The hook is not asked for a player who has no mode yet, which is the case at his first spawn. It runs under `pcall`, and an error in a listener counts as no veto.

A listener that returns `false` keeps the energy, the radar's tags and markers, a malfunction in progress and the recharge delays. The mode and the camouflage the player had are put on again with the cause `"restore"`, and `GryMod_ModeChanged` is not fired. See [api.md](api.md#keep-the-suit-at-a-respawn-in-place-grymod_canresetonspawnply).

```lua
hook.Add("GryMod_CanResetOnSpawn", "my_addon", function(ply)
	if ply.MyAddonGettingUp then
		return false
	end
end)
```

### GryMod_SuitNoise(ply, pos, radius, kind)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player who made the noise |
| `pos` | Vector | the position of the player |
| `radius` | number | how far the noise carries, in Source units, read from `GryMod.SuitNoiseRadius[kind]` |
| `kind` | string | `"cloak_fire"`, `"strength_jump"`, `"speed_sprint"`, `"cloak_on"` or `"cloak_off"` |

Return value: not read.

When it fires: in `GryMod.EmitSuitNoise` (`lua/grymod/server/sv_suit_noise.lua`), under `ProtectedCall`. The default radii are 2000 for `cloak_fire`, 1000 for `strength_jump`, 800 for `speed_sprint` and 300 for `cloak_on` and `cloak_off`. The kinds are emitted:

- `strength_jump`: with `GryMod_StrengthJump`;
- `speed_sprint`: with `GryMod_SprintStart`;
- `cloak_on` and `cloak_off`: with `GryMod_ModeChanged` when the mode becomes or stops being the camouflage, except for the causes `"spawn"` and `"sync"`;
- `cloak_fire`: when a bullet or a shot reported with `GryMod.API.ReportShot` leaves a player whose cloak level is above 0, at most once every 0.25 s for each player.

A call with a kind that has no radius, or with something that is not a player, fires nothing. `GryMod.EmitSuitNoise(ply, kind)` fires the hook by hand. See [api.md](api.md#suit-noises-server).

### GryMod_Explosion(pos, radius, inflictor, attacker)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `pos` | Vector | where the blast is |
| `radius` | number | the radius given to the blast, in Source units |
| `inflictor` | Entity | the entity that blew up, as given to `util.BlastDamage` |
| `attacker` | Entity | the attacker, as given to `util.BlastDamage` |

Return value: not read.

When it fires: GryMod wraps `util.BlastDamage` and `util.BlastDamageInfo` once (`Radar.InstallBlast` and `Radar.InstallBlastInfo` in `lua/grymod/server/sv_radar_pings.lua`). After the original function ran, `Radar.OnBlast` runs the hook under `pcall`, for every blast whose position is a vector and whose radius is a number. The radius, the settings `gry_radar_pings` and `gry_radar_blast_rings`, and whether a ring was made do not matter. A nested call of the wrapped function fires it once. The hook is not fired for an `env_explosion`.

### GryMod_TargetSpotted(ply, ent, relation)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose binoculars spotted the entity |
| `ent` | Entity | the entity that the scan ended on |
| `relation` | string | `"ally"`, `"neutral"` or `"hostile"`, from the relation chain |

Return value: not read.

When it fires: in `Radar.Scan` (`lua/grymod/server/sv_radar.lua`), when the server accepts the message `gry_radar_scan` for an entity that was not yet tagged for this player. A tagged entity that is scanned again fires nothing. The tags are forgotten when the player dies or respawns, so the hook can fire again for the same entity after that. It runs under `pcall`. The entity must be a living creature, a registered nextbot or a tracked object, and within 330 m (300 m of ray and a tenth more).

## HUD and feedback hooks (client)

### GryMod_UsableChanged(ent, mode, ply)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity or nil | the thing the player aims at that can be used or taken; `nil` when there is none |
| `mode` | number | 1 when it can be used or taken, 0 when there is nothing |
| `ply` | Player | the local player |

Return value: not read.

When it fires: in `Cross.ReportUsable` (`lua/grymod/client/cl_hud_crosshair_flash.lua`), under `pcall`, once at each change of the thing that is shown or of its mode. The crosshair looks ten times a second. A thing is reported after the crosshair stayed on it for `gry_usehint_delay` seconds (0.1 by default, 0 for at once). When the aim leaves it the report `nil, 0` follows after `gry_usehint_hold` seconds (0.2 by default, 0 for at once), or at once when another usable thing is aimed. The crosshair's own usable state is not delayed. The hook is only run while the crosshair is drawn, so not when the crosshair, the HUD or the suit is off or the player is dead. The test for "can be used" is the registry of usable things (`GryMod.API.RegisterUsable`) with the reach of the key (80 units unless an entry says otherwise), the filters added with `GryMod.API.AddUsableFilter`, and the player's group settings. The use prompt (`lua/grymod/client/cl_hud_use_flash.lua`) listens to this hook.

### GryMod_MessageShown(text, opts)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `text` | string | the cleaned text of the line |
| `opts` | table | a new table `{lane, sound, duration, line}` |

The fields of `opts`: `lane` is a string and is always set (the top lane by default), `sound` is a sound path or `nil`, `duration` is a number of seconds or `nil`, `line` is the key of one of the suit's own lines or `nil`.

Return value: not read.

When it fires: in `Module.Handle` (`lua/grymod/client/cl_hud_messages_flash.lua`), under `pcall`, once for each line that is really shown, after the line is on the HUD and its sound has started. A line that is not shown (the player turned the text lines off with `gry_hud_messages`, the HUD is off, the movie is missing, or the suit's own line is switched off) is not reported.

### GryMod_WeaponHeat(ply, wep, percent)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the local player |
| `wep` | Weapon | the weapon in hand |
| `percent` | number | 0 to 100, as a whole number; 0 when the bar is hidden |

Return value: not read.

When it fires: in the HUD's feed (`lua/grymod/client/cl_hud_flash.lua`), under `pcall`, each time the value of the heat bar changes. The value comes from the `heat` function of the weapon's registry entry, and is 0 for a weapon that declares none, for another weapon in hand, or when the player turned the bar off (`gry_hud_overheat`). A heat above 0 is held between 1 and 100. The hook is only run while the HUD is drawn.

### GryMod_WeaponListShown(ply, wep)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the local player |
| `wep` | Weapon | the weapon in hand, or the weapon the wheel is on |

Return value: not read.

When it fires: in `List.Show` (`lua/grymod/client/cl_hud_weaponlist_flash.lua`), under `pcall`, each time the weapon list is shown. The list is shown when the weapon in hand changes, and, with `gry_weapon_selector` at 2, at each notch of the wheel; `wep` is then the weapon the wheel is on. It is not fired when the list is off or has no weapon to show, or when the HUD was just made. See [weapons.md](weapons.md).

### GryMod_RadarExposure(level, previous)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `level` | number | the level of the radar's hexagon now, a whole number from 0 to 100 |
| `previous` | number | the level that was last reported |

Return value: not read.

When it fires: in `lua/grymod/client/cl_hud_radar_exposure.lua`, under `pcall`, each time the whole number changes, from the HUD's frame code. It follows the vehicles and machines that have noticed the player, or the value forced with the HUD event `radar_exposure`. The picture is small and green up to 48, amber from 49, grows and turns red from 55, and pulses from 95. Nothing is reported while `gry_hud_radarhex` is 0. See [events.md](events.md#the-radars-hexagon).

```lua
hook.Add("GryMod_RadarExposure", "my_addon", function(level, previous)
	if level >= 95 and previous < 95 then
		-- the pulsing red begins
	end
end)
```

### GryMod_NightVision(on, reason)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `on` | boolean | `true` when the night vision switched on, `false` when it switched off |
| `reason` | string | what caused the switch |

Return value: not read.

When it fires: in `NV.Play` (`lua/grymod/client/cl_nightvision.lua`), under `pcall`, at each real switch, as the sound half of the HUD event `night_vision`. A switch to the state it is already in fires nothing. The values of `reason`:

| Kind | Values |
| --- | --- |
| Asked | `"key"`, `"toggle"`, `"api"`, `"event"` |
| It went off by itself | `"energy"`, `"dead"`, `"invalid"`, `"suit"`, `"malfunction"`, `"death"`, `"disabled"`, `"option"`, `"server"`, `"shutdown"`, `"init"` |

`"shutdown"` and `"init"` play no sound. To refuse the switch on, use `GryMod_CanUseView`.

## In/out map and minimap hooks (client)

All four hooks of this section run under `pcall`. A listener that fails is shown in the console and stops nothing.

### GryMod_InOutMapReady(boxCount)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `boxCount` | number | the number of boxes of the in/out map |

Return value: not read.

When it fires: in `lua/grymod/client/cl_zonemap.lua`, each time the client accepts a complete file of the map that it decoded and indexed without error (the file comes in the message `gry_zonemap_data`). It can fire more than once for a level: the server sends the file again when the map is made again or when a client asks. It also fires for a map flagged incomplete (state 5). It is not fired when the file is refused, and it does not say that a map went away: watch `GryMod_InOutMapState` for that.

### GryMod_InOutMapState(state, done, total)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `state` | number | 0 off, 1 no graph, 2 waiting, 3 computing, 4 ready, 5 incomplete, 6 failed |
| `done` | number | the points the server has sampled |
| `total` | number | the points there are |

Return value: not read.

When it fires: in `Z.OnState` (`lua/grymod/client/cl_zonemap.lua`), for every valid message `gry_zonemap_state`, repeats of the same state included. A state outside 0 to 6 is ignored. With a state under 4, or 6, the map the client held is dropped before the hook runs. At states 4 and 5 the message comes first and the file after it, so `GryMod_InOutMapReady` follows. While the server computes it sends at most four messages a second.

### GryMod_MinimapProgress(done, total)

Realm: client.

| Argument | Type | Meaning |
| --- | --- | --- |
| `done` | number | the tiles of the main level that exist |
| `total` | number | the tiles of the main level that are wanted |

Return value: not read.

When it fires: in `fireProgress` (`lua/grymod/client/minimap/gen.lua`), each time one of the two numbers changes. It describes the main level only. See [minimap.md](minimap.md#events).

### GryMod_MinimapReady()

Realm: client. No arguments.

Return value: not read.

When it fires: in `fireReady` (`lua/grymod/client/minimap/gen.lua`), once for each request, when every wanted tile of the main level exists. The same function fires `GryMod_MinimapBelowReady` and `GryMod_MinimapOutsideReady`, see the last section of this page. See [minimap.md](minimap.md#events).

## Older names

Two hooks of the first versions of the addon still exist under their old names. GryMod still fires both, on the server, and it listens to both itself. Each has a `GryMod_` hook that replaces it.

### GryUseEnergy(ply)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose energy was used |

Return value: not read.

It is run after the code changes `GryEnergy` for a use of the energy: the sites are listed in `GryMod_EnergyUsed`. GryMod's own listeners restart the recharge delay and remember the energy at the moment of use (`lua/grymod/server/sv_health.lua`), and fire `GryMod_EnergyUsed` and `GryMod_EnergyEmpty` (`lua/grymod/server/sv_api.lua`). Replaced by `GryMod_EnergyUsed(ply)`. Use `GryMod_EnergyEmpty(ply)` to be told that the bar reached 0.

### GryNanosuitMode(ply, mode)

Realm: server.

| Argument | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | the player whose suit was put in a mode |
| `mode` | number | the mode the suit is in now (`GryMod.Modes`) |

Return value: not read.

It is run at the end of `Player:SetNanosuitMode` (`lua/grymod/server/sv_system.lua`), after `GryMode` is set and before `GryMod_ModeChanged`. Unlike that hook it is run for every request that reaches that point, including the same mode again and a respawn in place with the cause `"restore"`. It has no old mode and no cause. GryMod's own listener makes the NPCs forget a camouflaged player (`lua/grymod/server/sv_cloak_ai.lua`). Replaced by `GryMod_ModeChanged(ply, mode, oldMode, reason)`.

## Hooks fired with a name held in a variable

These hooks are run by a helper that receives the hook name as a variable, so a search for the literal name finds only the helper. They are real hooks of the same kind as the ones above. None of them has a return value that GryMod reads, and all run under `pcall`.

| Hook | Realm | Arguments | When it fires | Source |
| --- | --- | --- | --- | --- |
| `GryMod_MapOpened` | client | none | the big map opened | `lua/grymod/client/map/panel.lua` |
| `GryMod_MapClosed` | client | none | the big map closed | `lua/grymod/client/map/panel.lua` |
| `GryMod_MapZoomed` | client | `zoom` (number) | the zoom of the big map changed, by a wheel notch or a middle-button drag, not at opening | `lua/grymod/client/map/panel.lua` |
| `GryMod_MinimapBelowReady` | client | none | once for each request, after `GryMod_MinimapReady`, when the floor below was asked for and all its tiles exist | `lua/grymod/client/minimap/gen.lua` |
| `GryMod_MinimapOutsideReady` | client | none | the same for the outside, after the one above | `lua/grymod/client/minimap/gen.lua` |
| `GryMod_ObjectiveAdded` | server and client | `id` (string), `obj` (table) | an objective was added; on a client, it arrived | `lua/grymod/server/sv_objectives.lua`, `lua/grymod/client/cl_objectives.lua` |
| `GryMod_ObjectiveChanged` | server and client | `id` (string), `obj` (table), `oldState` (string) | the state, the title, the description, the primary flag or the main objective changed | same |
| `GryMod_ObjectiveRemoved` | server and client | `id` (string), `obj` (table), `reason` (string) | an objective is gone; `reason` is `"removed"`, `"cleared"`, `"entity_removed"` or `"map_changed"` | same |

The big map hooks and the minimap hooks are described in [minimap.md](minimap.md). The objective hooks are described in [api.md](api.md#hooks-both-realms). The server does not fire the objective hooks while `gry_objectives` is 0. The helper `Obj.Fire` (`lua/grymod/sh_objectives.lua`) prints the first 5 errors of a listener for each hook.
