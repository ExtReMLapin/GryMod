# GryMod extension API

One table, `GryMod.API`, for the addons that plug into the nanosuit and the HUD. Everything below exists in version 1 of the
interface unless it says otherwise. Design notes: `docs/superpowers/specs/2026-11-21-extension-api-design.md`.

Conventions:

- A **function** means "do this". It validates its arguments and returns `true`, or `false` and a short reason (a getter returns the
  value, or `nil` for a player that is not valid).
- A **hook** named `GryMod_<Event>` means "this happened" (fired with `hook.Run`, it never changes anything).
- A hook named `GryMod_Can<Action>` is a **veto**: a handler that returns `false` refuses the action.
- The server decides everything that changes the game. The client functions only drive the local HUD.

## Is GryMod there, and which version?

```lua
if GRYMOD_INSTALLED and GryMod.API and GryMod.API.Version >= 1 then
	-- safe to use version 1 of the interface
end
```

- `GryMod.API.Version` is the interface version (an integer, 1 today). It goes up only when something breaks.
- `GryMod.GetInterfaceVersion()` gives the same number.
- `GryMod.API.Has("hudevents")` tells whether an optional part exists. Today: `"suit"`, `"relation"`, `"hudevents"`,
  `"safecall"`. New parts add a name here and never change the version number.
- `GryMod.Version` is the addon version as text (`"dev"` in a checkout). Use it for display only.

## Safe calls

Every callback of yours that GryMod calls (relation providers, HUD event handlers) runs under `GryMod.API.SafeCall(id, fn, ...)`.
An error is caught and never reaches the HUD. After 5 errors in a row the callback is disabled and one line says which one:

```
GryMod API: provider 'my_addon' disabled after 5 errors: lua/my_addon.lua:12: attempt to ...
```

Registering the same id again re-arms it. You can use `SafeCall` yourself: it returns what `pcall` returns.

## Suit commands (server)

```lua
GryMod.API.SetEnergy(ply, 50)        -- 0 to 100, clamped
GryMod.API.AddEnergy(ply, -20)       -- a negative amount takes energy
GryMod.API.RefillEnergy(ply)
GryMod.API.EmptyEnergy(ply)
GryMod.API.GetEnergy(ply)            -- number, or nil
GryMod.API.SetMode(ply, GryMod.Modes.SPEED)   -- ARMOR, SPEED, CLOAK or STRENGTH
GryMod.API.GetMode(ply)
GryMod.API.StartMalfunction(ply, 5, "my reason")   -- the suit goes down for 5 seconds
GryMod.API.EMP(pos, 400, 10)         -- every suit within 400 units goes down for 10 s, returns how many
```

An energy command counts as a use of the energy: the recharge starts again after its usual delay.

`SetMode` returns `false` and a reason when it does not change the mode: `"invalid mode"`, `"dead"`, `"malfunction"` (the suit is
down, so it stays in armor), `"disabled"` (the suit is off, see below) or `"vetoed"`.

### The suit on or off

```lua
GryMod.API.SetSuitEnabled(ply, false)   -- for a game where the suit is not on the player yet
GryMod.API.IsSuitEnabled(ply)
```

Off means: armor mode and no mode change, the armor takes no hit (the whole damage goes through), the energy neither drains nor
recharges, the suit cannot go down in a malfunction, and the HUD is hidden on that player's screen. It is a flag
(`GryDisabled`, a networked boolean), not a malfunction. It stays through death and respawn until you set `true`.

## Suit events (server hooks)

| Hook | When |
| --- | --- |
| `GryMod_ModeChanged(ply, mode, oldMode)` | the mode really changed (any path: the player's menu, the API, a malfunction) |
| `GryMod_EnergyEmpty(ply)` | the bar reached 0 (once, not again until it has been above 0) |
| `GryMod_EnergyUsed(ply)` | energy was used (the new name of `GryUseEnergy`, which keeps firing too) |
| `GryMod_SuitEnabled(ply)`, `GryMod_SuitDisabled(ply)` | `SetSuitEnabled` changed the state |
| `GryMod_MalfunctionStart(ply, seconds, reason)`, `GryMod_MalfunctionEnd(ply)` | the suit went down, came back |
| `GryMod_EMP(pos, radius, seconds)` | you can run this hook yourself to fire an EMP (same as `API.EMP`) |

The old hooks `GryNanosuitMode(ply, mode)` and `GryUseEnergy(ply)` still fire.

### Veto: `GryMod_CanSetMode(ply, mode)`

```lua
hook.Add("GryMod_CanSetMode", "my_addon", function(ply, mode)
	if mode == GryMod.Modes.CLOAK and ply:GetNWBool("MyAddon_NoCloak") then
		return false -- refused: the player's client is told the mode that stays
	end
end)
```

It applies to every path that changes the mode, the player's own request included. It never applies to the armor mode: the armor is
the suit's safe state (a malfunction, an empty bar and a respawn must always reach it).

## Relation: ally, neutral or hostile (server)

`GryMod.API.Relation(ply, ent)` returns `"ally"`, `"neutral"` or `"hostile"`. It is the only place that decides it: the crosshair's
friendly cross and the radar both ask it (`GryMod.Friendly.Relation` is the same function). The order:

1. the providers you add, the higher priority first;
2. the registry of tracked entities (not there yet, see below);
3. the built-in rule: an NPC that likes the player is an ally, one that hates him is hostile, everything else is neutral; a player of
   the same team is an ally.

```lua
GryMod.API.AddRelationProvider("my_addon", function(ply, ent)
	if ent:GetClass() == "npc_my_guard" then return "ally" end
	-- return nothing: no opinion, the next provider decides
end, 10)                               -- priority, 0 by default

GryMod.API.RemoveRelationProvider("my_addon")
```

A provider returns one of the three words, or `nil` for no opinion; any other value is ignored. Adding an id again replaces its
provider. A provider is never asked about an invalid player or entity.

## HUD events

A HUD event is a named effect the HUD plays. Built in: `"boot"` (the start-up log), `"lost"` (the emergency shutdown animation, until a
`"reboot"`), `"reboot"` (the reboot sequence), `"malfunction"` (`data.seconds`, 5 by default: shutdown, then reboot). They follow the
player's own choice: with the HUD boot sequences option off they play nothing.

From the server, to one player or a list of players:

```lua
GryMod.API.HUDEvent(ply, "malfunction", {seconds = 3})
GryMod.API.HUDEvent(player.GetAll(), "boot")
```

The data is `nil` or a small table: at most 8 fields, names of letters, digits and underscore (24 characters at most), values that
are finite numbers, strings (128 characters at most) or booleans. The event name has 32 characters at most. A call that breaks
these limits returns `false` and a reason, and sends nothing (`GryMod.API.HUDEventLimits` tells the limits).

On the client, to play one here or to declare your own:

```lua
GryMod.API.RegisterHUDEvent("my_flash", function(data)
	-- data is a table (empty when there is no data)
end)

GryMod.API.HUDEvent("my_flash", {power = 3})     -- plays it on this client, returns true when the handler ran
GryMod.API.UnregisterHUDEvent("my_flash")

hook.Add("GryMod_HUDEvent", "my_addon", function(name, data) end)   -- after a handler ran without error
```

## Weapons and tracked entities

Wave B, not there yet: a weapon registry (fire mode, ammo, counters, icons) and a registry of scannable entities shared by the
binoculars and the radar. `GryMod.API.Has("weapons")` and `GryMod.API.Has("tracked")` will tell when they exist.
