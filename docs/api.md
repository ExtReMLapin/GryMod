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
  `"safecall"`, `"weapons"`. New parts add a name here and never change the version number.
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

## Weapons

`GryMod.API.Has("weapons")` is true. The HUD never knows a weapon by its class name: it asks the weapon registry what the weapon is.
The stock Half-Life 2 weapons are registered in the registry as data (`lua/grymod/sh_api_weapons_hl2.lua`), with the same call your
addon uses: there is no private table and no special case for them.

### Describe a weapon

A weapon is described by a **definition**, a table of optional fields. A field you leave out is read from the weapon itself.

| Field | Values | Meaning |
| --- | --- | --- |
| `fire` | `"auto"`, `"semi"`, `"burst"`, `"none"`, or `function(wep)` returning one of them | the fire mode shown in the weapon slot (`"none"`: no gun icon, for a melee weapon) |
| `burst` | integer, 2 to 32 | the size of a burst, when `fire` is `"burst"` |
| `ammo` | ammo type name | the primary ammo (default: `Primary.Ammo`, then the engine's ammo of the weapon) |
| `counter` | `"clip"`, `"none"`, or `function(wep)` returning a text | what the counter shows (default `"clip"`; `"none"` when `CustomAmmoDisplay` says `Draw = false`) |
| `alt` | `"none"`, `"grenade"`, `"energy"`, `"zoom"`, `"doublebarrel"`, `"shoot"`, `"throwlow"`, `"melee"` | what the secondary fire (right click) is |
| `altAmmo` | ammo type name | the ammo the secondary counts (`"SMG1_Grenade"` for a grenade launcher, `"AR2AltFire"` for the energy ball) |
| `altShoots` | boolean | true when the secondary fires a shot. The camouflage ends on a right click that shoots. Default: true for `grenade`, `energy`, `doublebarrel`, `shoot` and `throwlow` |
| `altLabel` | short text, 24 characters at most | the name of the secondary fire (`"40mm"`) |
| `altIcon` | an icon key (see below) | the icon the HUD shows for the secondary fire |
| `icon` | an icon key | the icon of the weapon slot (it wins over `fire`) |
| `slotIcon` | an icon key | the stock icon of the weapon slot, when `icon` is not given |

The icon keys are the ones of the HUD movie: `Single`, `Burst`, `Auto`, `Grenade`, `Shotgun`, `Mine`, `Repairkit`, `Missle`, `NoGun`,
`HandGrenade` and the ones that no stock weapon uses, which are yours to choose: `Incendiary`, `Tranquilizer`, `infinity`, `Narrow`,
`Moac`, `Moar`, `TACCannon`, `C4`, `Gauss`, `Gunner`, `Mounted`, `Claymore` (`GryMod.API.WeaponIcons` lists them all).

What the HUD does with the secondary fire: with `alt = "grenade"` or `"energy"` the grenade slot (where the hand grenades are) counts
`altAmmo` and shows `altIcon` (the 40 mm grenade icon when you give none) instead of the hand grenades. The SMG does this with its
grenade, the AR2 with its energy ball. The other kinds show nothing there: the shotgun's double barrel uses the primary ammo, the
crossbow's zoom has no counter. `altLabel` reaches the HUD (`GryMod.FlashHUD.LauncherLookFor(wep)`, and `hud:GetLauncherLabel()`), but
the movie has no text field for it yet: it is not drawn.

### Declare it from the weapon (no call to GryMod needed)

```lua
SWEP.GryHUD = {
	fire = "burst", burst = 3,
	ammo = "Gauss",
	alt = "energy", altAmmo = "Gauss", altLabel = "PLASMA", altIcon = "Gauss",
	icon = "Gauss",
}
```

A weapon written like this works whether or not GryMod is installed.

### Register it

```lua
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	local ok, reason = GryMod.API.RegisterWeapon("weapon_my_rifle", {
		fire = "auto",
		ammo = "SMG1",
		alt = "grenade", altAmmo = "SMG1_Grenade", altLabel = "40mm",
	})

	if not ok then print("GryMod refused my weapon: " .. reason) end
end
```

- `RegisterWeapon(class, def)` returns `true`, or `false` and a reason. Fields it does not know are ignored; an invalid value (a `fire`
  that is not in the list, an unknown icon key...) refuses the whole definition and keeps the previous one. Registering a class again
  replaces its definition. A base class counts for the classes built on it (`SWEP.Base`).
- `UnregisterWeapon(class)` removes the entry, `GetWeapon(class)` gives back a copy of it (no base class, no default).
- `ResolveWeapon(wep)` is what the HUD uses: the final description of a weapon entity (or of a class name, then without the things only
  an entity can tell), `nil` for an invalid weapon. `ResolveWeapon(wep, true)` gives only what is declared, with no default.
  `WeaponValue(wep, field)` gives one field without building a table.
- A function you give for `fire` or `counter` runs under `SafeCall` (see above): a broken one never breaks the HUD.

### Where a field comes from

For each field, the first of these that says something wins:

1. the registry entry of the weapon's class, or of the nearest base class that has one;
2. the `SWEP.GryHUD` table of the weapon;
3. the weapon adapters (below);
4. the defaults read from the weapon: `Primary.Automatic` (auto or semi), `Primary.Ammo` and `Secondary.Ammo` (or the engine's ammo of
   the weapon), a secondary ammo that is a grenade type but not the hand grenade's (a launcher), and `CustomAmmoDisplay` (the table
   the HUD addon holohud2 reads: `Draw`, `PrimaryClip`, `PrimaryAmmo`, `SecondaryAmmo`, `SecondaryClip`; its numbers are in the
   `display` field of the resolved description).

### Adapters for the weapon bases

`GryMod.API.AddWeaponAdapter(id, fn)` adds a function `fn(wep)` that returns a partial definition (or nothing), asked through `SafeCall`
in the order the adapters were added; `RemoveWeaponAdapter(id)` removes it. There is none today. Adapters for ArcCW, TFA, M9K and CW2
weapons: later (the HUD already reads their fire mode through its own resolvers).

## Tracked entities

Not there yet: a registry of scannable entities shared by the binoculars and the radar. `GryMod.API.Has("tracked")` will tell when it
exists.
