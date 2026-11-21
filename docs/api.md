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
  `"safecall"`, `"weapons"`, `"tracked"`. New parts add a name here and never change the version number.
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
2. the `relation` field of the entry of the registry of tracked entities that matches the entity (see below), when it is not `"auto"`;
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

### Which side uses which field

Your registration file is shared: the same declarations run on the server and on the client (put them in a file that both
realms include, see the full example at the end of this document). A field that one side does not use is stored there and ignored,
without an error. The weapon registry is read by the HUD, so it is the client that uses every field today; the server keeps the
entry (it answers `GetWeapon` and `ResolveWeapon` too) and does nothing with it.

| Field | Used by | What for |
| --- | --- | --- |
| `fire`, `burst` | client | the fire-mode icon of the weapon slot |
| `ammo`, `counter` | client | the ammo counter |
| `alt`, `altAmmo`, `altLabel`, `altIcon` | client | the grenade slot (which ammo it counts, its icon) |
| `altShoots` | client | the camouflage: a right click that shoots ends it (the HUD tells the server) |
| `icon`, `slotIcon` | client | the icon of the weapon slot |

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

`GryMod.API.Has("tracked")` is true. The registry of tracked entities says what an entity is for the HUD. For an NPC or a nextbot: its
icon on the radar, when the radar lists it, what it is to the player (ally, neutral or hostile) and whether the binoculars may tag it.
For a projectile or a trap (a grenade, a mine, a missile): that it is a **danger** the player is warned about, what to call it and
how the server knows it is armed. An entity that is not registered behaves as it always did: the radar reads its class and its
attitude.

Everything the HUD knows about Half-Life 2 entities is registered here as plain data (`lua/grymod/sh_api_tracked_hl2.lua`: the icon
classes of the radar and the six dangerous projectiles), with the same call your addon uses. There is no private table and no special
case: the radar and the grenade warning only read the registry.

### Register a class

```lua
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	-- the guards of my addon: allies, always on the radar, even when the player did not meet them yet
	GryMod.API.RegisterTracked("my_addon_guard", {
		class = "npc_my_guard",
		relation = "ally",
		radar = "always",
	})

	-- my turret: a hostile machine the binoculars cannot tag, listed like any enemy (alerted or fighting within 26 m)
	GryMod.API.RegisterTracked("my_addon_turret", {
		class = {"npc_my_turret", "npc_my_turret_big"},
		relation = "hostile",
		radar = "hostile",
		scan = false,
		type = "machine",
		size = "big",
	})
end
```

`RegisterTracked(key, def)` returns `true`, or `false` and a reason. The key is yours (a unique name: registering it again replaces
the entry and keeps its place in the order). An invalid value refuses the whole definition and keeps the previous one; fields it does
not know are ignored. `UnregisterTracked(key)` removes it (returns whether there was one). `GetTracked(ent)` gives the first entry
that matches the entity, or `nil`: it is the stored table, read it and do not change it.

### The fields

| Field | Values | Meaning |
| --- | --- | --- |
| `class` | a class name, or a list of them | matches the entities of these classes |
| `base` | a class name, or a list of them | matches the entities built on that base class (`ENT.Base`, `scripted_ents.IsBasedOn`) and the base itself |
| `match` | `function(ent)` returning `true` | matches what the function says, asked through `SafeCall` |
| `scan` | boolean, `true` by default | the binoculars may tag it; `false`: they cannot (the lock sound does not play, the server refuses the tag) |
| `radar` | `"always"`, `"hostile"`, `"scan"`, `"never"` | when the radar lists it (below); nothing: the radar's usual rules |
| `relation` | `"auto"` (default), `"ally"`, `"neutral"`, `"hostile"`, or `function(ply, ent)` | what it is to the player; `"auto"`: the NPC's real attitude |
| `type` | `"human"`, `"flying"`, `"machine"`, `"device"` or 1, 2, 3, 4 | the icon of the radar: a soldier, a flying unit, a machine or a vehicle (a rectangle with a square), a device (a rectangle with a disc: GryMod's Combine mine); nothing: the class decides (unknown classes are `"human"`) |
| `size` | `"normal"`, `"big"` | `"big"` draws the icon twice the size (the Strider's); nothing: the class decides |
| `label` | text, or `function(ent)` | a name for the entity. Stored; no part of the HUD shows it yet |
| `shape` | `"unit"` (default), `"dot"`, `"rect"`, `"triangle"` | how it is drawn on the radar. Only `"unit"` (the radar's soldier, machine and flying icons) is drawn today; the other shapes are accepted and stored, never an error (`"rect"` is for vehicles, `"triangle"` for dangers) |
| `danger` | a table (below) | the entity is a projectile or a trap the player must be warned about (the grenade warning) |
| `indicator` | `"warning"`, `"marker"`, `"none"` | how a danger shows on the screen. `"warning"` (the default for an entry with `danger`) is the grenade-detect warning: an icon with the label and the distance. `"marker"` and `"none"` are accepted and stored: the warning does not draw them, and no marker is drawn yet |
| `priority` | a number, -1000 to 1000, `0` by default | the entries with the higher priority are tried first (see below) |

A vehicle or a device (an entity that is neither an NPC nor a nextbot) is a radar contact when its entry gives it a `radar` rule (the stock entries
for the Buggy and the Jalopy, `prop_vehicle_jeep`, the airboat, the Combine APC and crane, and for the Combine mine use `"scan"`: on the radar once
the binoculars scanned it), unless the player sits in it or the administrators' switch `gry_radar_objects` is off. A vehicle takes the colour of its
DRIVER (nobody or a neutral: grey, a friend: blue, a hostile: red) unless its entry has a `relation` of its own; the mine is hostile until the player has
put it down with the gravity gun (`m_bPlacedByPlayer`). The seats of the spawn menu (`prop_vehicle_prisoner_pod`) are not registered: another
addon registers its own vehicles through this function.

At least one of `class`, `base` and `match` is needed. The entity matches when ANY of the ones you give matches, tried in this order
of cost: the class, then the base, then the function (which is not called when the class or the base matched). Entries are tried by
priority (the higher first), and in the order they were registered among the same priority: the first that matches wins. The stock
Half-Life 2 entries have a priority of -100, so an entry of your addon for one of their classes (say `npc_strider`, to make it an
ally) beats them whatever the order the addons load in. The class and base answers are kept in a cache by class (emptied by
every `RegisterTracked` and `UnregisterTracked`), so `GetTracked` is cheap enough for the radar to ask it for every NPC at every tick.
A `match` function is asked about every entity of a class that no earlier entry took: keep it short.

`GetTrackedByClass(class)` is the same question for a class name instead of an entity: the first entry that names the class in its
`class` list (a `base` or a `match` needs an entity to be asked). The radar uses it for the icon of a class.

### `radar`: when the contact is listed

| Value | The radar lists it |
| --- | --- |
| `"always"` | at once, calm and never scanned, within the radar's range, in the colour of its relation (blue for an ally; for a hostile the colour of its state), whatever the player's "allies always on the radar" switch says |
| `"hostile"` | by the rules of the enemies, whatever its relation: alerted or fighting the player within 26 m, or scanned. It has the colours of an enemy, an ally with this setting keeps its blue |
| `"scan"` | only once the binoculars scanned it (its alert, a marker when it hurt the player and the allies switch do not list it) |
| `"never"` | never: not scanned, not as a marker, not at once |

Without `radar` the usual rules apply: an ally is listed at once (the player's switch), a hostile by its alert, a neutral only
scanned or when it hurt the player.

### `relation`

`relation` is step 2 of the relation chain above: your providers come first, then the entry, then the NPC's real attitude. A function
is asked with `(ply, ent)` through `SafeCall` and answers `"ally"`, `"neutral"` or `"hostile"`; `nil` (or any other value) is no opinion
and the built-in rule answers. The crosshair's friendly cross follows it too.

### What the radar looks at

The registry is read for **NPCs and nextbots**. A nextbot is not on the radar unless an entry matches it (the radar then describes it with
no NPC state and no enemy: it is calm, and `radar = "always"` or a scan lists it; the engine gives it no attitude, so give it a
`relation`). Other entities, vehicles included, are accepted by the registry but ignored by the radar: their drawing comes with their own
part (`shape = "rect"`). The `label` does not travel to the client either: the radar's message has no room for text and the movies have
no field for a name; it is there for a later part.

### Dangers: the grenade warning

An entry with a `danger` table makes the entity a danger: the HUD warns the player about it with the grenade-detect icon (its label,
its distance, shrinking as it goes away) while it is coming. The stock warning covers the frag grenade, the rifle grenade, the
missile, the helicopter bomb, the Combine mine and the energy ball; yours goes through the same code.

```lua
danger = {
	label = "MINE",              -- the text of the warning, 32 characters at most (default: the entry's label, then "DANGER")
	type = "mine",               -- the kind of icon (any short word: "grenade", "missile", "mine", "bomb", "energy"). Stored: the warning has one icon
	armed = function(ent) ... end,   -- SERVER: is it dangerous now? Without it, the entity is dangerous as soon as it exists
	range = 25,                  -- metres, 200 at most: warn within this distance (it can only shorten the player's own range)
	ownerOf = function(ent) ... end, -- SERVER: the player who threw or fired it, when the engine does not say
	ownMissile = true,           -- a projectile the player FIRES: it never warns its shooter (default false)
}
```

- A **danger needs a `class`** (a name or a list): the client looks for these entities by class. A `base` or a `match` alone is
  refused with a reason.
- `armed(ent)` runs on the **server only**: the client cannot read the engine's internal variables (`m_flDetonateTime`,
  `m_iMineState`...). The server follows every entity that has a danger entry from its creation (`OnEntityCreated`; the ones that
  stand before the entry is registered are not looked for again), asks `armed` five times a second and sends the answer to the
  clients in the networked boolean `GryArmed`. A projectile a player holds in the hands (or with the gravity gun) is never armed,
  whatever `armed` says. `armed` runs under `SafeCall`: an error means "not armed", and 5 errors in a row disable it with one console
  line. Return `true` only for a danger that is coming (a grenade whose fuse runs, a mine in the air), not for one that lies around.
- `ownerOf(ent)` helps for a projectile that keeps its owner in a field of its own; the server also reads the engine's owner and
  thrower. The thrower is networked in `GryThrower`.
- The player's settings apply to every entry with a danger, yours included: the range (`gry_grenade_range`, the entry's `range` can only
  make it shorter), the rule for the player's own grenades (`gry_grenade_own_warn`: what the player threw never warns, and with the
  setting on a thrown one warns within 15 m, but a `ownMissile` one never), the line of sight (`gry_grenade_los`) and
  `gry_grenade_armed_only` (off: every projectile of the list warns, armed or not).
- Nothing is warned about within 1 m of the eye or off the screen.

### Which side uses which field

The same declarations run on both realms (put them in a shared file, see the example below). A field that a side does not use is
stored and ignored there, with no error. The server decides what the radar lists, what an entity is to the player, which projectile
is armed and what the binoculars may tag; the client draws.

| Field | Server | Client | Used for |
| --- | :---: | :---: | --- |
| `class`, `base`, `match` | yes | yes | matching: the server for the radar, the relation, the scan and the danger it follows; the client for the binoculars and the warning's scan (by `class`) |
| `scan` | yes | yes | the server refuses the tag of the binoculars; the client skips the lock sound |
| `radar` | yes | | the radar's contact rules (the client draws the list the server sends) |
| `relation` | yes | | the relation chain (the client asks the server: the crosshair's friendly cross) |
| `type`, `size` | yes | | the icon of the radar contact in the message |
| `label` | stored | stored | the entry's name; it is also the fallback label of a danger. No part of the HUD shows it |
| `shape` | stored | stored | only `"unit"` is drawn, by the radar; the other shapes are for later |
| `priority` | yes | yes | the order of the entries |
| `danger.armed` | yes | | the server reads the state and networks it (`GryArmed`) |
| `danger.ownerOf` | yes | | who threw it (`GryThrower`) |
| `danger.label` | | yes | the text of the warning |
| `danger.type` | stored | stored | the kind of icon: stored, the warning has one icon |
| `danger.range` | | yes | the warning's range |
| `danger.ownMissile` | | yes | a projectile the player fires never warns them |
| `danger` (the table itself) | yes | yes | the server follows and marks these entities, the client looks for them by class |
| `indicator` | | yes | `"warning"` draws the warning; `"marker"` and `"none"` draw nothing yet |

### Full example: an addon registers its mine

One file, included by both realms (`lua/autorun/my_addon_shared.lua`, which runs on the server and on the client), registers the
entity as a danger for the warning (the server reads its state, the client draws the warning). Its entity (`ENT.Type = "anim"`, class `my_addon_mine`) keeps who
planted it in `ENT.Planter` and a state in `ENT.Armed`.

```lua
-- lua/autorun/my_addon_shared.lua (shared)
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	local ok, reason = GryMod.API.RegisterTracked("my_addon_mine", {
		class = "my_addon_mine",
		danger = {
			label = "PROXIMITY MINE",
			type = "mine",
			range = 20,                                   -- client: not warned about from farther than 20 m
			armed = function(ent) return ent.Armed == true end,   -- server: the state the client cannot read
			ownerOf = function(ent) return ent.Planter end,       -- server: the player who planted it never gets the warning
		},
		-- the same entry says the rest of what the HUD needs to know about it:
		scan = false,        -- the binoculars do not tag it
		shape = "dot",       -- stored: the radar draws units only for now
	})

	if not ok then print("GryMod refused my mine: " .. reason) end
end
```

On the server the entity is followed from its creation and `GryArmed` follows `ent.Armed`; on the client the warning shows `PROXIMITY MINE`
and its distance while it is armed, within the player's range and 20 m. Nothing else to write: no hook, no net message.
