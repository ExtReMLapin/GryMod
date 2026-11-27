# Suit: energy, mode, malfunction, hits and reports

This page holds the functions of `GryMod.API` that read or drive the nanosuit of a player: the energy bar, the mode, the suit being on or off, malfunctions and EMPs, the reports that an attack or an explosion happened, the cloak level and the hit filters. Unless an entry says otherwise, a function runs on the server and the server decides; the client only draws. The guide with the reasoning is [api.md](../api.md#suit-commands-server). The hooks that these calls fire are listed in [api.md](../api.md#suit-events-hooks).

The functions that act on a player take a `Player` entity. A value that is not a valid player is refused: the commands return `false, "invalid player"` and the getters return `nil` (`GetEnergy`, `GetMode`) or `false` (`IsSuitEnabled`).

## Energy

The bar goes from 0 to 100 and is held in the networked float `GryEnergy` of the player (`GetNW2Float`). The commands below set it at once on the server. Each of them counts as a use of the energy, like a drain: the recharge waits again for its usual delay (1 second with the original game's mechanics, 5 seconds with the classic ones) counted from the new value.

All of the writing commands run the hook `GryUseEnergy(ply)`, and from it `GryMod_EnergyUsed(ply)`. `GryMod_EnergyEmpty(ply)` runs once when the bar is at 0 after a command, and does not run again until a later use finds the bar above 0 (a respawn arms it again). The commands work on a dead player and on a suit that is down or off; they do not look at `GryMod.API.IsSuitEnabled`.

Two rules of the server can undo a value. With `gry_infinite_armor` at 1, the bar is put back to 100 at the next `Think`. A camouflaged player whose bar is set under what the camouflage needs (below 10 with the original game's mechanics) leaves the camouflage at the next `Think`, with the cause `GryMod.ModeReasons.ENERGY`.

### GryMod.API.GetEnergy(ply)

Server. Returns the energy of the suit, a number from 0 to 100.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |

Returns the value of `GryEnergy`, or `nil` for a player that is not valid. A player that has no value yet (before his first spawn) gives 0. On the client there is no `GetEnergy`; the client reads the same networked float.

### GryMod.API.SetEnergy(ply, amount)

Server. Sets the energy.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |
| `amount` | number | The new value. It is clamped to 0 to 100. | No |

Returns `true`, or `false` and a reason: `"invalid player"`, or `"invalid amount"` for a value that is not a number or is `NaN`. An infinite value is a number and is clamped.

The call runs `GryUseEnergy` even when the value does not change, so it restarts the recharge delay.

### GryMod.API.AddEnergy(ply, amount)

Server. Adds `amount` to the energy, then clamps the sum to 0 to 100. A negative amount takes energy.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |
| `amount` | number | What to add. Negative to take. | No |

Returns what `SetEnergy` returns: `true`, or `false` and `"invalid player"` or `"invalid amount"`. An amount of 0 changes nothing but still counts as a use.

```lua
-- an ability that costs 20 points
GryMod.API.AddEnergy(ply, -20)
```

The call does not check that the bar holds the amount: asked for more than there is, the bar goes to 0. Test `GetEnergy` first when the action must be refused for lack of energy.

### GryMod.API.RefillEnergy(ply)

Server. Sets the energy to 100. Same as `SetEnergy(ply, 100)`, with the same returns.

### GryMod.API.EmptyEnergy(ply)

Server. Sets the energy to 0. Same as `SetEnergy(ply, 0)`, with the same returns. It fires `GryMod_EnergyEmpty` if that event was not already told for this empty bar.

## Mode

The mode is one of `GryMod.Modes.ARMOR` (0), `SPEED` (1), `CLOAK` (2) and `STRENGTH` (3).

### GryMod.API.GetMode(ply)

Server. Returns the mode of the suit.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |

Returns a number from `GryMod.Modes`, or `nil` for a player that is not valid. A player with no mode yet gives `GryMod.Modes.ARMOR`. A dead player keeps the mode he died in until he respawns, where the suit starts again in armor. The mode is also in the networked integer `GryMode`, readable in both realms.

### GryMod.API.SetMode(ply, mode)

Server. Puts the suit in a mode and tells the client of that player. The change is made before the call returns.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |
| `mode` | number | One of `GryMod.Modes.ARMOR`, `SPEED`, `CLOAK`, `STRENGTH`. | No |

Returns `true`, or `false` and a reason:

| Reason | Cause |
| --- | --- |
| `"invalid player"` | `ply` is not a valid player. |
| `"invalid mode"` | `mode` is not a number, or is not one of the four modes. |
| `"dead"` | The player is not alive. |
| `"malfunction"` | The suit is down. It stays in armor. |
| `"disabled"` | The suit is off (`SetSuitEnabled`). It stays in armor. |
| `"vetoed"` | A listener of `GryMod_CanSetMode(ply, mode)` returned `false`. The mode does not change. |

The rules are those of `Player:SetNanosuitMode`, which every path that changes the mode goes through, the player's own request included. Behaviour to rely on:

- `GryMod_ModeChanged(ply, mode, oldMode, reason)` runs when the mode really changes, with `reason` equal to `GryMod.ModeReasons.API` (`"api"`). Asking for the mode the suit is already in changes nothing, runs no hook and asks no veto, and returns `true`. The client is still told the mode.
- Armor is never vetoed. `SetMode(ply, GryMod.Modes.ARMOR)` succeeds on a suit that is down or off.
- For a suit that is down or off, asking for another mode than armor returns `false` with the reason `"malfunction"` or `"disabled"`, and the client is told the real mode with that cause.
- A veto refusal sends the real mode to the client with the cause `GryMod.ModeReasons.VETOED`.
- An attack that should end the camouflage goes through `ReportAttack`, below.

```lua
local ok, why = GryMod.API.SetMode(ply, GryMod.Modes.CLOAK)

if not ok then
	print("cloak refused: " .. why)
end
```

See [api.md](../api.md#why-the-mode-changed-grymodmodereasons) for the causes and [api.md](../api.md#veto-grymod_cansetmodeply-mode) for the veto.

### GryMod.API.RefreshModeStates(ply)

Server. Tells the quick menu of a player which modes a veto refuses right now. The owner of a `GryMod_CanSetMode` listener calls it when the answer of the listener changed (the player walked into a zone, a rule was switched), and once after adding the listener.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player whose menu is concerned. | No |

Returns `true`, or `false` and `"invalid player"`.

The server asks the veto once for each of the modes speed, cloak and strength, except the mode the suit is in, and packs the answers in a mask of 3 bits (`gry_modes_refused`). Nothing is asked for a player who is dead, whose suit is down or whose suit is off: the mask is 0 then. The message is sent at once and only when the mask differs from the one the client was last told. The call also starts the half-second timer that follows the vetoes, if a listener exists and a player is alive.

The client never asks. GryMod also sends the mask by itself when the client is ready, at every spawn, and when the mode, a malfunction or the on/off state changes. Without a call from you, a change of your own condition is seen at the next tick of the timer, at most half a second later, while at least one listener of `GryMod_CanSetMode` exists and a player is alive.

Your listener is asked more often than real mode changes. It must answer without side effects and cost little: each tick asks it 2 or 3 times for each living player, at most 6 times a second for each living player.

## The suit on or off

A suit that is off is the state of a player whose suit is not on his body yet. It is kept as a flag of its own and has nothing to do with a malfunction.

### GryMod.API.IsSuitEnabled(ply)

Server and client. Tells whether the suit of `ply` is on. The answer is the opposite of the networked boolean `GryDisabled`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |

Returns `true` when the suit is on, `false` when it is off. Both realms return `false` for a value that is not a valid entity, and `true` for a suit that was never switched off.

- On the server the argument must be a valid player. The value is the one `SetSuitEnabled` wrote.
- On the client the argument must be a valid entity; the function does not check that it is a player. The value is the last one the server networked, so it follows `SetSuitEnabled` after the next network update and not in the same frame. The HUD, the quick menu and the night vision read it to hide or grey themselves.

### GryMod.API.SetSuitEnabled(ply, enabled)

Server. Switches the suit of a player off (`false`) or on (`true`).

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |
| `enabled` | boolean | `false` to switch off, `true` to switch on. | No |

Returns `true`, or `false` and a reason: `"invalid player"`, or `"invalid value"` when `enabled` is not a boolean (`nil` and `0` are refused).

While the suit is off:

- the mode is armor and cannot change (`SetMode` returns `false, "disabled"`);
- the armor takes no hit and the whole damage goes to the health;
- the energy neither drains nor recharges;
- the suit cannot go down in a malfunction (`StartMalfunction` is refused);
- the HUD is hidden on the player's screen.

The flag stays through death and respawn until it is set to `true`.

Calling it with the state the suit already has returns `true` and does nothing else. A real change:

1. sets `GryDisabled`;
2. when switching off a suit that is not in armor, puts it in armor with the cause `GryMod.ModeReasons.DISABLED`, so `GryMod_ModeChanged` runs. The result of that step is not checked: on a dead player the mode is left as it is;
3. runs `GryMod_SuitDisabled(ply)` or `GryMod_SuitEnabled(ply)`.

The local HUD of the player plays its shutdown animation (HUD event `"disabled"`) or its reboot (`"enabled"`) when it sees the flag change; the first value it sees on arrival plays nothing. The energy is not touched by either change, and a malfunction in progress is not ended. See [api.md](../api.md#the-suit-on-or-off).

## Malfunctions

A suit that is down is in armor mode, has an empty bar that does not recharge, and cannot change mode. At the end it restarts with an empty bar that recharges after the usual delay, and shocks cannot put it down again for 3 seconds (an EMP can). A suit that is down shows its state in the networked boolean `GryMalfunction`.

Both functions refuse when malfunctions are off (`gry_malfunction` at 0), when `gry_infinite_armor` is at 1, and for a suit that is off.

### GryMod.API.StartMalfunction(ply, seconds, reason)

Server. Puts the suit of a player down for a number of seconds.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |
| `seconds` | number | How long the suit stays down. Clamped to 0.1 to 60. | Yes. Default 10. |
| `reason` | string | A short text, given to `GryMod_MalfunctionStart`. | Yes. Default `"api"`. |

A `seconds` that `tonumber` cannot convert gives the default of 10. The built-in causes use the reasons `"emp"`, `"shock"`, `"overload"` and `"impact"`. A `reason` that is not a string is replaced by `"api"`.

Returns `true`, or `false` and a reason: `"invalid player"`, or `"refused"` when the player is not alive or one of the rules above applies.

- When the suit goes down: the mode goes to armor (cause `GryMod.ModeReasons.MALFUNCTION`), the energy goes to 0, and `GryMod_MalfunctionStart(ply, seconds, reason)` runs.
- A suit that is already down is not put down again, and no new hook runs. If the new end is later than the current one, the end moves to the new time. A shorter call leaves the current end as it is. Both return `true`.
- At the end `GryMod_MalfunctionEnd(ply)` runs. A death, a respawn and a disconnect end the state without running that hook.
- The HUD of the player plays its malfunction and reboot sequences.

### GryMod.API.EMP(pos, radius, seconds)

Server. Puts down every living suit within `radius` units of `pos`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `pos` | Vector | The centre of the EMP. | No |
| `radius` | number | The reach in Source units. `math.huge` reaches every living player. | Yes. Default 400. |
| `seconds` | number | How long each suit stays down. | Yes. Default 10. |

Returns the number of suits that went down. For a `pos` that is not a vector it returns `0` and `"invalid position"`. It returns `0` when `gry_malfunction_emp` or `gry_malfunction` is 0.

The distance is measured from the player's `WorldSpaceCenter()`. Each player in range is put down as `StartMalfunction` does, with the reason `"emp"`, and counts when that call returned `true`: a suit that was already down counts too. The 3 seconds of grace after a restart do not protect from an EMP. `seconds` is clamped to 0.1 to 60 for each suit.

`EMP` does not run the hook `GryMod_EMP(pos, radius, seconds)`. Running that hook does the same as this function, and is the call to use when other listeners of the hook should hear about it.

```lua
-- every living suit within 400 units goes down for 10 seconds
local count = GryMod.API.EMP(ent:GetPos(), 400, 10)
```

## Reports of attacks and explosions

The server sees every bullet through `EntityFireBullets`. These calls tell GryMod about what that hook cannot see.

### GryMod.API.ReportAttack(ply, rightClick)

Server. Tells that the player just made an attack that is not a bullet (a knife swing, a grenade thrown or launched, a beam), so that his camouflage ends.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The attacker. | No |
| `rightClick` | boolean | `true` when the attack came from the secondary fire. Only `true` counts; anything else is read as `false`. | Yes. Default `false`. |

Returns `true` when the player was camouflaged, or `false` and a reason: `"invalid player"`, or `"not camouflaged"` when his mode is not `GryMod.Modes.CLOAK`. Nothing is raised, whatever is given.

The call does not change the mode on the server. It sends the message `gry_cloak_shot` to that player's client, which ends the camouflage (the mode goes to armor with the cause `GryMod.ModeReasons.PLAYER`) and empties the bar. The effect therefore comes after one network trip, and `GryMod_ModeChanged` runs for that change then. The player may have turned the right-click rule off in his own options (`gry_cloak_altfire`); in that case the client ignores a report with `rightClick` set to `true`, and the call still returns `true`. `GryMod.API.Has("attackreport")` tells whether the function exists.

### GryMod.API.ReportShot(ply, rightClick)

Server. Does what `ReportAttack` does, and also makes the noise of a shot for the AI that listens. Use it for a shot that leaves no bullet for `EntityFireBullets`, such as the gun of a vehicle that does not call `FireBullets`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The shooter. | No |
| `rightClick` | boolean | As for `ReportAttack`. | Yes. Default `false`. |

Returns what `ReportAttack` returns: `true`, or `false` and the reason.

The noise is told with `hook.Run("GryMod_SuitNoise", ply, pos, radius, "cloak_fire")`, with `pos` the position of the player and `radius` 2000 units unless `GryMod.SuitNoiseRadius.cloak_fire` was changed. It is made only when the report succeeded and the player's cloak level is above 0, and at most once every 0.25 seconds for a player (a bullet and a report share the same limit). A listener that raises an error does not stop the call. `GryMod.API.Has("shotreport")` tells whether the function exists. The noises are described in [api.md](../api.md#suit-noises-server).

### GryMod.API.ReportRadarPing(pos, kind)

Server. Makes an explosion ring appear on the radars of the players near `pos`: a ring that opens and fades in 2 seconds. Use it for an explosion, a gunshot or an alarm that does not go through an `env_explosion` or `util.BlastDamage`, which ring the radar by themselves.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `pos` | Vector | Where the ring appears. | No |
| `kind` | string or number | A size name, or a radius in metres. `"small"` is 2 m, `"explosion"` is 4 m, `"big"` is 8 m. A number is held between 0.5 and 8. | Yes. Default: the size of `"explosion"`. |

Returns `true`, or `false` and a reason:

| Reason | Cause |
| --- | --- |
| `"invalid position"` | `pos` is not a vector, or one of its coordinates is `NaN`. |
| `"invalid kind"` | `kind` is a string that is not a name above, or is neither nil, a string nor a number (a table, a boolean, `NaN`). |
| `"too many pings this second"` | 20 pings were already accepted in the current second, from all callers together. A refused ping runs no hook. |

The recipients are the living players whose position is within 250 m of `pos` (`GryMod.RadarShared.PING_RANGE`, with 0.01905 m for each Source unit). A ping with no one in reach sends nothing, still returns `true`, and still runs the hook. The size travels in steps of half a metre, so 6.4 reaches the client as 6.5. The hook `GryMod_RadarPing(pos, size, automatic)` runs for each accepted ping, with the size before rounding and `automatic` set to `false` for this call.

The server setting `gry_radar_pings` turns the automatic rings off and does not affect this function. The player's `gry_hud_radarpings` hides the rings on his screen. The automatic pings, the classes that ring on removal and the rings of blasts are described in [api.md](../api.md#explosion-rings-grymodapireportradarpingpos-kind-server) and [api.md](../api.md#blasts-of-utilblastdamage).

```lua
GryMod.API.ReportRadarPing(ent:GetPos(), 6.5)
```

## Cloak level

### GryMod.API.CloakLevel(ply)

Shared. Tells how far the camouflage of a player has faded in, for the AI that watches him.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | No |

Returns a number from 0 (not camouflaged) to 1 (fully camouflaged). It returns 0 for a value that is not a valid player and for a dead player.

The camouflage is a switch (`GryCloak`). At each real change of the switch, the server writes two networked stamps on the player: `GryCloakLvl0`, the level at that moment, and `GryCloakT0`, the time. The level then moves in a straight line from `GryCloakLvl0` toward 1 while the camouflage is on, and toward 0 while it is off, at `1 / gry_cloak_fade_seconds` per second. The value is computed when the function is called, from the stamps and `CurTime()`. Nothing runs between two switches, so asking often costs little, in either realm.

- `gry_cloak_fade_seconds` is a replicated server setting: 2 by default, from 0 to 10. At 0 the level is the switch itself, 0 or 1 at once.
- A camouflage switched on again during the fade-out goes on from the level it had.
- A respawn starts the new life at level 0 at once.
- `GryMod.CloakLevelFrom(on, level0, t0, now, rate)` is the formula and `GryMod.CloakFadeRate()` the rate. `GryMod.API.Has("cloaklevel")` tells whether the function exists.

The camouflage still sets `FL_NOTARGET` for the Half-Life 2 NPCs. The level is for an AI that makes its own perception. See [api.md](../api.md#cloak-level-server-and-client).

## Hit filters

A filter tells the suit what to do with one hit on a player. The armor handler of the suit and the radar's marker of attackers both ask the filters, through `HitVerdict`. A filter has the form `fn(ply, dmginfo)` and answers `nil`, `"ignore"` or `"bypass"`. `GryMod.API.Has("hitfilter")` tells whether the functions exist. The guide, with examples, is [api.md](../api.md#hit-filters-what-the-suit-does-with-one-hit); the compatibility patches that use filters are described in [compat.md](../compat.md#damage-living-with-the-addons-that-change-it).

| Answer | What the suit does with the hit |
| --- | --- |
| `"ignore"` | Nothing. No energy is taken, no damage arrows, no hit marker, no malfunction, no armor sound, no `GryMod_ArmorAbsorbed`, no restart of the health regeneration delay, and the radar does not mark the attacker. The damage is left as it came. |
| `"bypass"` | The damage goes to the health as it is, in every mode and with the infinite armor too. The bar is not touched and no malfunction starts. The arrows and the hit marker still tell the hit. |
| anything else | The suit does what it always does. |

### GryMod.API.AddHitFilter(id, fn, priority)

Server. Registers a hit filter, or replaces the filter that has the same `id`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the filter. It cannot be empty. | No |
| `fn` | function | `fn(ply, dmginfo)`, called with the victim and the `CTakeDamageInfo`. It returns `"ignore"`, `"bypass"` or nothing. | No |
| `priority` | number | The filters with the higher priority are asked first. | Yes. Default 0. |

Returns `true`, or `false` and a reason: `"invalid id"`, `"invalid function"`, `"invalid priority"` (a value that is not a number, or `NaN`).

The filters are asked in order of priority, highest first, and in order of registration for equal priorities. The first filter that answers `"ignore"` or `"bypass"` decides, and the others are not asked. Registering an id again removes the old filter, puts the new one at the end of its priority class, and arms it again (`SafeCallReset("hitfilter:" .. id)`).

A filter runs under `SafeCall` with the call id `"hitfilter:" .. id`. An error skips the filter for that hit, and the fifth error in a row disables it, with one console line. The filters of GryMod's own compatibility patches use ids such as `"glide"`, `"lvs"` and `"GryMod compat zbase"`; pick an id that carries the name of your addon.

```lua
GryMod.API.AddHitFilter("my_addon", function(ply, dmginfo)
	if dmginfo:IsDamageType(DMG_VEHICLE) and MyAddon.OwnsCrash(dmginfo) then
		return "ignore"
	end
end, 10)
```

### GryMod.API.RemoveHitFilter(id)

Server. Removes the filter that has this id.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The id given to `AddHitFilter`. | No |

Returns `true` when a filter was removed, `false` when there was none. It returns nothing else and raises no error for any argument.

### GryMod.API.HitVerdict(ply, dmginfo)

Server. Returns what the filters say about one hit. The suit calls it from its damage handlers; an addon rarely needs to.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The victim. | No |
| `dmginfo` | CTakeDamageInfo | The hit. | No |

Returns `"ignore"`, `"bypass"`, or `nil` when no filter has an opinion.

- With no filter registered it returns `nil` at once and calls nothing.
- It keeps the answer of the last hit it was asked about, identified by the same `dmginfo` object, the same victim and the same `CurTime()`. The armor handler and the radar handler both ask for one hit, and the filters run once for it. The next hit, or the same hit in a later tick, asks the filters again.
- A filter that fails or answers anything else is skipped and the next one is asked.
- The armor handler (`EntityTakeDamage`) does not ask for a player in god mode. The radar handler asks for every player that is hit, so a filter can be called for a player in god mode.
