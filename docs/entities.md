# Tracked entities and relations

This guide is for the addons that add NPCs, nextbots, vehicles, mines or projectiles and want GryMod's HUD to treat them properly.
It builds on [api.md](api.md) (the reference, with the table of fields); here you find what each field changes on the screen,
complete examples, and the limits that exist today.

What you can do with one registry entry:

- **Binoculars**: say whether the entity can be scanned (the lock sound, the pale outline, the tag), and add vehicles and devices
  to what they can scan.
- **Radar**: say when the entity is listed, with which icon, and in which colour (through its relation).
- **Relation**: say that the entity is an ally, neutral or hostile to the player. The radar's colour and the crosshair's friendly
  cross both follow it.
- **Danger warning**: say that a projectile or a trap is something the player must be warned about (the grenade-detect icon).

Everything below is checked by running it, on the server and on the client, in a game with GryMod loaded.

## Before you register

Two things to know.

**GryMod must be there, and it must be loaded already.** The autorun files of all addons run in alphabetical order, so a file
whose name sorts before `grymod_shared.lua` runs when `GRYMOD_INSTALLED` is still `nil`. Register from the `Initialize` hook,
which runs after every autorun file:

```lua
-- shared: lua/autorun/my_addon_gryhud.lua
hook.Add("Initialize", "my_addon_gryhud", function()
	if not (GRYMOD_INSTALLED and GryMod.API and GryMod.API.Has("tracked")) then
		return -- GryMod is not installed: nothing to do, and nothing breaks
	end

	local ok, reason = GryMod.API.RegisterTracked("my_addon_guard", {
		class = "npc_my_addon_guard",
		relation = "ally",
		radar = "always",
	})

	if not ok then
		print("GryMod refused my guard: " .. reason)
	end
end)
```

**Both realms run the same declarations.** Put the registration in a file that runs on the server and on the client (a plain
`lua/autorun/*.lua` file does). The server decides what the radar lists, what the entity is to the player and which projectile is
armed; the client draws the binoculars and the warning. A field one side does not use is stored and ignored there. The table
"[Which side reads which field](#which-side-reads-which-field)" below has the details.

In the examples that follow, the guard (`if GRYMOD_INSTALLED and ...`) stands for "inside that `Initialize` function".

## Recipes

### An NPC of yours that is an ally

The radar lists an ally at once, in blue, without waiting for the player to notice it (while the player's switch
`gry_radar_allies_always` is on). With `radar = "always"` it is listed even if that switch is off.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_citizen", {
		class = {"npc_my_addon_citizen", "npc_my_addon_medic"},
		relation = "ally",
		radar = "always",
		type = "human",
	})
end
```

`relation = "ally"` is fixed. If the attitude of your NPCs changes in play, give a function (see "The relation" below) or
leave `relation` out: by default (`"auto"`) the NPC's real attitude towards the player decides (it likes him: ally; it hates him:
hostile; otherwise neutral).

### A hostile machine the binoculars cannot tag

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_drone", {
		class = "npc_my_addon_drone",
		relation = "hostile",
		radar = "hostile",
		scan = false,
		type = "flying",
	})
end
```

`radar = "hostile"` lists it by the rules of the enemies: when it is alerted or fighting the player within 26 m, or scanned.
`scan = false` makes the binoculars skip it (no lock sound, no outline) and the server refuses the tag.
`type = "flying"` gives it the helicopter icon; `"machine"` gives the rectangle with a square, `"human"` the soldier, `"device"`
the rectangle with a disc. Add `size = "big"` for an icon twice as large.

### A vehicle

A vehicle is not an NPC: the radar does not look at it unless an entry gives it a `radar` rule. With `radar = "scan"` it is listed
once the player scanned it with the binoculars. It is drawn with the machine icon (a rectangle that points where it drives) in the
colour of its **driver**: grey for nobody or a neutral, blue for a friend, red for a hostile. An entry that gives the vehicle a
`relation` of `"ally"` or `"hostile"` overrides that (`"neutral"` still takes the driver's colour).

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_buggy", {
		class = "prop_vehicle_my_addon_buggy",
		type = "machine",
		radar = "scan",
	})
end
```

The vehicle the player sits in is never listed. The administrators' switch `gry_radar_objects` turns all vehicles and mines off.

### A nextbot, matched by its base

A nextbot has no attitude in the engine, so give it a `relation`, and `radar = "always"` if the radar should list it without a
scan (a nextbot is not on the radar at all unless an entry matches it). `base` matches every entity built on that base class.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_bots", {
		base = "my_addon_nextbot",
		type = "human",
		radar = "always",
		relation = function(ply, ent)
			if ent:GetNW2Bool("MyAddonHostile") then
				return "hostile"
			end

			return "ally"
		end,
	})
end
```

### Many classes with one rule: `match`

`match` is a function that gets the entity and returns `true` for the ones this entry is about. It is only asked for the
entities that no earlier entry took by class or base, so keep it short.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_family", {
		match = function(ent)
			return string.StartWith(ent:GetClass(), "npc_my_addon_")
		end,
		relation = "ally",
	})
end
```

### A dangerous projectile or trap

The warning is the grenade-detect icon with a label and a distance, drawn while the projectile is coming. `armed` runs on the
**server** (the client cannot read the engine's internal fields) and says when the projectile is a danger now; the server sends
the answer to the clients. An entry with a `danger` needs a `class`.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	GryMod.API.RegisterTracked("my_addon_rocket", {
		class = "my_addon_rocket",
		danger = {
			label = "ROCKET",
			type = "missile",
			range = 60,
			ownMissile = true,
			armed = function(ent)
				return ent:GetVelocity():Length() > 100
			end,
			ownerOf = function(ent)
				return ent:GetOwner()
			end,
		},
	})
end
```

What each `danger` field does:

| Field | Effect |
| --- | --- |
| `label` | the text of the warning, 32 characters at most. Without it: the entry's `label` if it is a text, then `"DANGER"` |
| `armed(ent)` | server. `true` while the projectile is dangerous (a fuse that runs, a rocket in flight). Without it, the entity is dangerous from its creation. An error counts as "not armed" |
| `range` | metres, 200 at most. The warning starts at that distance. It can only shorten the range the player chose (`gry_grenade_range`) |
| `ownerOf(ent)` | server. The player who threw or fired it, when the engine does not say. The server also reads the engine's owner and thrower |
| `ownMissile` | `true`: something the player fires, it never warns its own shooter. `false` (default): it warns the thrower within 15 m if the player's switch `gry_grenade_own_warn` is on |
| `type` | the kind of icon, a short word. Stored: the warning has one icon whatever you say |

A projectile held in the hands or by the gravity gun is never armed, whatever `armed` returns. The warning ignores what is off the
screen or closer than 1 m from the eye. The player's settings (range, line of sight, armed only) apply to your entry too.

The server follows an entity from its creation. If the entry is registered after an entity of that class was made, the server does
not look for it again: register at load time (`Initialize`), not later.

### A machine that breaks the suit, an electric weapon, an NPC that ignores the cloak

Three server rules of the suit are fields of the entry too. GryMod's own Half-Life 2 data (the strider, the energy ball...) is
registered the same way, so what you write here works exactly like theirs.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	-- a boss: a hit of it that breaks the armor puts the suit down (the malfunction "impact"), and it keeps a
	-- camouflaged player in mind unless the cloak makes it forget him
	GryMod.API.RegisterTracked("my_addon_titan", {
		class = "npc_my_addon_titan",
		type = "machine",
		size = "big",
		heavy = true,
		cloakBlind = true,
	})

	-- a projectile that shocks the suit, whatever its damage type
	GryMod.API.RegisterTracked("my_addon_arc", {
		class = "my_addon_arc_bolt",
		shock = "strong",
	})
end
```

| Field | Effect (server) |
| --- | --- |
| `heavy` | `true`: when this entity is the attacker or the inflictor of a hit that breaks the armor of a player in armor mode (the damage is 25 or more and at least the energy the suit has left), the suit goes down for 3 seconds. Needs the player's switch `gry_malfunction_impact`. Matched by class, base or `match` like any field |
| `shock` | `"strong"`: a hit by this inflictor puts the suit down for 5 seconds (unless it just restarted). `"light"`: the HUD flickers and the energy bar loses 1.5 per point of damage (5 to 30). The damage type does not matter. Without the field, the usual rule applies: shock, energy beam and plasma damage is light under 25 points and strong from 25. Needs `gry_malfunction_shock` |
| `cloakBlind` | `true`: this NPC keeps a camouflaged player as its enemy for good (the engine's NPCs of this kind ignore the cloak badly), so while a player is camouflaged the server makes it neutral to him and makes it forget him, and gives its attitude back when the cloak ends. Only a hostile NPC is touched. Needs a `class` (the server searches these classes only, every half second, and only while somebody is camouflaged) and the administrators' switch `gry_cloak_ai` |

The first entry that matches the entity decides, as for every field: an entry of yours for `npc_strider` that does not say
`heavy` or `cloakBlind` takes them away from the stock strider. For `cloakBlind`, which is looked up by class, the first entry that
names the class decides.

### Remove what you added

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("tracked") then
	print(GryMod.API.UnregisterTracked("my_addon_guard"))   -- true when there was an entry
end
```

`UnregisterTracked(key)` returns whether it removed something. The entity goes back to the radar's usual rules at once: the
caches are emptied by every registration and every removal. Providers are removed with
`GryMod.API.RemoveRelationProvider(id)`, weapons with `UnregisterWeapon(class)`.

### Look at what GryMod knows about an entity

```lua
-- shared
local function describe(ent)
	local entry = GryMod.API.GetTracked(ent)

	if not entry then
		return "not registered"
	end

	return string.format("entry '%s', priority %d, radar %s, scan %s", entry.key, entry.priority, tostring(entry.radar), tostring(entry.scan))
end

print(describe(Entity(0)))
```

`GetTracked(ent)` returns the stored entry (read it, do not change it) or `nil`. `GetTrackedByClass(class)` asks the same about a
class name; it only sees entries that list the class in `class` (an entry with a `base` or a `match` needs an entity).
`GetDanger(classOrEntity)` is the same question for the entries with a `danger`. `TrackedClasses(field)` lists the classes whose
entry has a field set (for example `TrackedClasses("cloakBlind")`); the list is kept, read it, do not change it.

## The fields, and what each one changes

| Field | Binoculars | Radar | Relation | Warning |
| --- | --- | --- | --- | --- |
| `class`, `base`, `match` | find the entry | find the entry | find the entry | `class` only |
| `scan` | `false`: no lock, no outline, no tag | `false`: cannot be tagged by a scan | | |
| `radar` | a vehicle or device is scannable only with a rule other than `"never"` | when the contact is listed | | |
| `relation` | | the colour | the answer of step 2 | |
| `type`, `size` | | the icon, the size | | |
| `label` | | | | fallback text of a danger. Nothing else shows it |
| `shape` | | | | not read by anything |
| `danger` | | | | the whole warning |
| `indicator` | | | | `"warning"` draws it; `"marker"`, `"none"` draw nothing |
| `heavy`, `shock`, `cloakBlind` | | | | server rules of the suit, see above (nothing is drawn) |
| `priority` | which entry wins | which entry wins | which entry wins | which entry wins |

`priority` (-1000 to 1000, 0 by default) orders the entries: the higher first, and among equals the one registered first. The first
entry that matches an entity wins and the others are not looked at. The stock Half-Life 2 entries are at -100, so one of yours
for `npc_strider`, say, beats them whatever the order the addons load in.

An entry is matched by its class, then by its base, then by its `match` function. When you give several, any of them matches.

### `radar`: when the contact is listed

The radar's contacts are worked out on the server, five times a second, for the players who have the radar on, among the
entities within the radar's range (the player's setting, 20 to 100 m; the search goes a third beyond). It lists NPCs, the nextbots
that an entry matches, and the vehicles and devices whose entry has a `radar` rule other than `"never"`. Players are not listed.

| `radar` | The contact is listed |
| --- | --- |
| nothing | by the usual rules: an ally at once (the player's switch), a hostile when it is alerted or fighting within 26 m, a neutral only when scanned or when it hurt the player. A vehicle or a device with no rule is not listed |
| `"always"` | at once, calm, even if never scanned. Blue for an ally, the colour of its state for a hostile |
| `"hostile"` | by the rules of the enemies whatever its relation: alerted or fighting within 26 m, or scanned. An ally here keeps its blue |
| `"scan"` | only once the binoculars scanned it. Its alert, a marker and the allies' switch do not list it |
| `"never"` | never: not scanned, not as a marker, not at once |

A contact that was tagged (noticed, or scanned) stays on the radar, in the colour of its present state, until it dies or the
player does. An NPC that hurt the player is marked for 10 s, on the border of the radar if it is out of it. A hit by a vehicle or
a nextbot does not mark.

Colours by allegiance: blue for an ally, the icons of the radar's movie for the others (calm, alerted, fighting).

### The relation

What an entity is to a player ("ally", "neutral", "hostile") is decided in one place, on the server, in this order:

1. the providers added with `GryMod.API.AddRelationProvider`, the higher priority first;
2. the `relation` field of the entry that matches the entity (a word or a function), unless it is `"auto"`;
3. the built-in rule: an NPC that likes the player is an ally, one that hates him is hostile, a player of the same team is an
   ally, everything else is neutral.

A function that returns nothing (or any other value) has no opinion and the next step decides. Every function runs under
`SafeCall`: an error is caught, and after 5 in a row it is disabled with one line in the console; registering it again re-arms it.

A provider is for a rule that crosses entries: a faction, a team, a game mode.

```lua
-- server
GryMod.API.AddRelationProvider("my_addon_factions", function(ply, ent)
	local mine, theirs = ply:GetNW2String("MyAddonFaction"), ent:GetNW2String("MyAddonFaction")

	if theirs == "" then
		return nil -- not one of mine: no opinion
	end

	return mine == theirs and "ally" or "hostile"
end, 50)
```

The functions are asked for every entity the radar lists (five times a second for each) and for the one under the crosshair, so
do not search the world in them.

`GryMod.API.Relation(ply, ent)` is the question itself. It exists on the server only; on the client the crosshair asks the server.
It answers `"neutral"` for an invalid player or entity.

Two limits of the crosshair's friendly cross ("do not shoot"): it only opens on players of the same team and on **NPCs** (the
engine class `NPC`), so a nextbot or a vehicle that you made an ally shows blue on the radar but never opens the cross.

## Which side reads which field

| Field | Server | Client |
| --- | :---: | :---: |
| `class`, `base`, `match` | the radar, the relation, the tag, the projectiles it follows | the binoculars, the projectiles it warns about (`class`) |
| `scan` | refuses the tag | skips the lock sound and the outline |
| `radar`, `type`, `size` | decides and sends the contacts | draws what it receives |
| `relation` | answers the chain | asks the server (the crosshair) |
| `danger.armed`, `danger.ownerOf` | read here, sent in `GryArmed` and `GryThrower` | |
| `danger.label`, `danger.range`, `danger.ownMissile`, `indicator` | | the warning |
| `priority` | the order of the entries | the order of the entries |
| `heavy`, `shock`, `cloakBlind` | the suit's malfunctions and the camouflage's effect on the NPCs | stored |
| `label`, `shape`, `danger.type` | stored | stored |

So a declaration file that runs in both realms is right for every field. If you only registered on the server, the client would
not know that your mine is a danger, and the binoculars would not lock on your vehicle.

## Known limits

All of these are true today.

- **48 contacts per list.** The radar sends the nearest 48 (markers first). A crowd of allies can push a distant hostile out of the
  list.
- **`label` is not transmitted.** The radar's message carries no text and the movies have no field for a name. The `label` of an
  entry is stored, and is the fallback text of a `danger`. Nothing else shows it.
- **`radar = "danger"` does not exist.** It is refused (`invalid radar: danger`). A danger is shown by the warning only, never on
  the radar.
- **`shape` is not read.** The values `"unit"`, `"dot"`, `"rect"` and `"triangle"` are accepted and stored (never an error), but no
  part of the HUD reads them: the radar draws the icon chosen by `type`. A vehicle is the `"machine"` rectangle.
- **`indicator`:** `"marker"` and `"none"` are accepted and stored; only `"warning"` draws.
- **`danger.type` is stored.** The warning has one icon.
- **Players are not on the radar.**
- **The crosshair's friendly cross is for NPCs and players** (see above).
- **Dangers are followed from their creation** (see above).
- **The weight is not measured with many players:** the radar does one sphere search per player and `match` functions are not cached.
- **The seats of the spawn menu** (`prop_vehicle_prisoner_pod`) are not registered: a vehicle that matters is yours to register.
- A registration that is refused (an invalid value) keeps the previous entry and returns `false` and a reason.
