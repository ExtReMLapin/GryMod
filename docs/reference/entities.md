# Entities: relations, classes, tracked entities, dangers and vehicles

This page lists the functions of `GryMod.API` that tell GryMod what an entity is: ally, neutral or hostile to a player, which class it really has, whether it is a living creature, what the radar and the binoculars do with it, whether it is a danger to warn about, and which vehicle a player sits in. The guide [entities.md](../entities.md) has the recipes and the limits that exist today; this page is the reference of each call.

Every callback described here runs under `GryMod.API.SafeCall` (see [Safe calls](../api.md#safe-calls)): an error is caught and counts as "no answer", and the fifth error in a row switches that callback off with one line in the console. Registering the same key again re-arms it. The failure counts are kept separately in each realm.

## Relation

The relation of an entity to a player is one of three words: `"ally"`, `"neutral"` or `"hostile"`. It is decided on the server in this order: the relation providers, then the `relation` field of the tracked entry that matches, then the built-in rule (see [The relation](../entities.md#the-relation) in the guide). The client reads the answer with `ClientRelation`.

### GryMod.API.AddRelationProvider(id, fn, priority)

Server. Adds a function that answers what an entity is to a player, ahead of the tracked registry and the built-in rule. `GryMod.API.Has("relation")` is true in both realms, but the functions of this section that start with `Add`, `Remove` and `Relation` exist on the server only.

| Parameter | Type | Meaning | Default |
| --- | --- | --- | --- |
| `id` | string | Name of the provider. Not empty. Adding an id that exists replaces that provider. | required |
| `fn` | function | `fn(ply, ent)`. Returns `"ally"`, `"neutral"` or `"hostile"`, or nothing for no opinion. | required |
| `priority` | number | The higher is asked first. Providers of equal priority are asked in the order they were added. Any number is accepted except NaN, negative and fractional ones included. | `0` |

Returns `true`, or `false` and a reason: `"invalid id"`, `"invalid function"` or `"invalid priority"`.

The provider is asked for every entity the radar lists (five times a second for each) and for the entity under the crosshair, so it has to be cheap. Any answer other than the three words is ignored and the next provider is asked. Replacing a provider puts it at the end of its priority group, because the order of registration is counted again. Adding an id again re-arms a provider that was switched off.

```lua
GryMod.API.AddRelationProvider("my_addon_factions", function(ply, ent)
	local theirs = ent:GetNW2String("MyAddonFaction")

	if theirs == "" then
		return nil
	end

	return theirs == ply:GetNW2String("MyAddonFaction") and "ally" or "hostile"
end, 50)
```

### GryMod.API.RemoveRelationProvider(id)

Server. Removes the provider `id`.

Returns `true` when there was one, `false` otherwise (including an `id` that is not a string). The entity goes back to the other steps of the chain at once. The failure count of the provider is not cleared by the removal; adding the id again clears it.

### GryMod.API.Relation(ply, ent)

Server. Says what the entity is to the player. The radar's colour, the crosshair's friendly cross and the binoculars all ask this function, and `GryMod.Friendly.Relation` calls it.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | The player the relation is seen from. A table with an `IsValid` method is accepted. |
| `ent` | Entity | The entity to judge. Same rule. |

Returns `"ally"`, `"neutral"` or `"hostile"`. An invalid player, an invalid entity or a value that is neither an entity nor a table gives `"neutral"`, and no provider is asked.

The chain stops at the first answer. The providers come first, from the highest priority. The second step is the `relation` field of the entry that `GetTracked(ent)` returns: nothing is taken from it when the entry says `"auto"`, when no entry matches, or when its function does not answer one of the three words. The last step is the built-in rule: a player of the same team is an ally (never the player himself, and not for the unassigned team 1001 or the spectator team 1002), an NPC whose disposition towards the player is like is an ally, one that hates him is hostile, and everything else is neutral, including an NPC without a `Disposition` method.

### GryMod.API.ClientRelation(ent)

Client. Gives what the entity is to the local player, as the server's chain answers it. Announced by `GryMod.API.Has("clientrelation")`.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity to ask about. |

Returns `"ally"`, `"neutral"` or `"hostile"`, or `nil`. It returns `nil` when `ent` is not a valid entity, when the crosshair module is not loaded, and for an entity whose answer has not come from the server yet or is more than 2 seconds old.

The function works from a cache. The first call for an entity sends a question to the server and returns `nil`; a later call finds the answer. The same entity is asked again when its last question is 1 second old and it is still being asked about. Two questions leave at least 0.2 second apart, whoever asks (the crosshair or this function), and the server answers a player 5 times a second at most and ignores the rest. Ask for the entity the player aims at or for a few at a time, not for a whole map in one frame.

Two cases are answered without the server. A player is answered at once from the teams: `"ally"` for a player of the same team (the same exclusions as the built-in rule), `"neutral"` otherwise, so a provider added on the server does not change the answer for a player. An entity whose index is 0 or less, or above 8191 (a client-side entity), is `"neutral"`. A server that only sends the older message answers `"ally"` or `"neutral"`.

```lua
local relation = GryMod.API.ClientRelation(ent)

if relation == "hostile" then
	-- nil means "not known yet": draw nothing and ask again next frame
end
```

## Class and creature providers

Two shared questions that other addons answer in their own way. `ClassOf` is asked by every per-class lookup of GryMod: the tracked registry, the radar's icon, the `heavy` and `shock` rules and the use prompt. `IsCreature` replaces the tests of `IsNPC()` in the radar's contacts, the crosshair's living target and the NPC that hurt the player. Providers of one kind are asked in the order they were added.

### GryMod.API.AddClassProvider(key, fn)

Shared. Adds a function that knows the real class of an entity whose `GetClass` was replaced by another addon (ZBase makes its NPCs answer the class of their base).

| Parameter | Type | Meaning |
| --- | --- | --- |
| `key` | string | Name of the provider. Not empty. The same key replaces the provider and keeps its place in the order. |
| `fn` | function | `fn(ent)`. Returns a class name, or nothing for no opinion. |

Returns `true`, or `false` and `"invalid key"` or `"invalid function"`. Adding a key again re-arms a provider that was switched off.

An answer counts only when it is a string that is not empty. Anything else, and an error, is no answer and the next provider is asked.

### GryMod.API.RemoveClassProvider(key)

Shared. Removes the class provider `key`.

Returns `true` when there was one, `false` otherwise.

### GryMod.API.ClassOf(ent)

Shared. Gives the class that GryMod works with for the entity.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. A table with an `IsValid` method and a `GetClass` method is accepted. |

Returns a string: the answer of the first provider that gives a non-empty string, else `ent:GetClass()`. Returns `nil` for a value that is not an entity or a table, for an invalid entity, and for a table without a `GetClass` method.

With no provider registered the call is `ent:GetClass()` and nothing more, because it is asked for many entities at every tick.

### GryMod.API.AddCreatureProvider(key, fn)

Shared. Adds a function that says an entity is a living creature although the engine does not call it an NPC. A DrGBase nextbot is one.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `key` | string | Name of the provider. Not empty. The same key replaces the provider and keeps its place. |
| `fn` | function | `fn(ent)`. Returns `true` when the entity is a creature. |

Returns `true`, or `false` and `"invalid key"` or `"invalid function"`.

Only the exact value `true` counts. `false`, `nil`, any other value and an error leave the question to the next provider. A provider cannot say "not a creature" about an entity that `IsNPC()` accepts.

### GryMod.API.RemoveCreatureProvider(key)

Shared. Removes the creature provider `key`.

Returns `true` when there was one, `false` otherwise.

### GryMod.API.IsCreature(ent)

Shared. Says whether GryMod treats the entity as a living creature.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. A table with an `IsValid` method is accepted. |

Returns `true` when `ent:IsNPC()` is true, or when a creature provider answers `true`. Returns `false` for an invalid entity and for a value that is neither an entity nor a table. The providers are not asked about an NPC.

## The tracked registry

An entry of the registry says what an entity is for the radar, the binoculars, the suit's malfunction rules and the grenade warning. The same file of declarations should run in both realms: the server decides and the client draws, and a field that one realm does not use is stored and ignored there. The guide has a table of [which side reads which field](../entities.md#which-side-reads-which-field). The stock Half-Life 2 entries are registered through the same call with a priority of -100.

### GryMod.API.RegisterTracked(key, def)

Shared. Adds the entry `key`, or replaces it. `GryMod.API.Has("tracked")` is true when the registry is there.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `key` | string | Name of the entry. Not empty. An existing key is replaced. |
| `def` | table | The definition, fields below. Fields that are not in the table are ignored. |

Returns `true`, or `false` and a reason. The reasons are `"invalid key"`, `"the definition must be a table"`, `"invalid <field>: <value>"`, `"nothing to match on: give a class, a base or a match function"` and `"a cloakBlind needs a class (the cloak looks for these NPCs by class)"`. For a wrong value in `danger` the field name is the sub-field (`danger.range`) and the value printed is the whole `danger` table. A refused definition changes nothing and the previous entry stays.

At least one of `class`, `base` and `match` is required. The entity matches when any of the ones given matches. They are tried in the order class, base, function, and the function is not called when the class or the base matched.

Replacing an entry with the same priority keeps its place in the order. Replacing it with another priority moves it to the end of its new priority group. Every registration empties the caches of the registry. It also re-arms the functions of the entry that were switched off, except `heavy`, whose count is not cleared.

The entries are tried by `priority`, the higher first, and in the order of registration among equal priorities. The first entry that matches an entity decides every field for it: an entry of yours for `npc_strider` that does not set `heavy` takes it away from the stock strider.

**Matching and listing**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `class` | string, or list of strings | Class names to match. Each is 1 to 64 characters; a list cannot be empty. Compared with `GryMod.API.ClassOf(ent)`. | none |
| `base` | string, or list of strings | Matches an entity whose class equals the name, whose `Base` field equals it, or that `scripted_ents.IsBasedOn` says is built on it. Same limits as `class`. | none |
| `match` | function | `match(ent)`. Matches when it returns `true`. It is asked about an entity only when no class or base of this entry matched it, and its answer is not cached. | none |
| `priority` | number, -1000 to 1000 | Order of the entries. Fractions are accepted. | `0` |

**What the radar and the binoculars do (server and client)**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `scan` | boolean | `false`: the binoculars play no lock sound and draw no outline for it, and the server refuses the tag. | `true` |
| `radar` | `"always"`, `"hostile"`, `"scan"` or `"never"` | When the radar lists the contact; see [`radar`](../entities.md#radar-when-the-contact-is-listed) in the guide. An entity that is neither an NPC nor a nextbot is a contact, and scannable by the binoculars, only when the entry has a `radar` other than `"never"`. A nextbot is a contact only when some entry matches it. `"danger"` is refused. | none: the usual rules |
| `relation` | `"auto"`, `"ally"`, `"neutral"`, `"hostile"` or a function | Step 2 of the relation chain. A function is called as `fn(ply, ent)` on the server and answers one of the three words; any other answer gives no opinion and the built-in rule decides. `"auto"` gives no opinion. | `"auto"` |
| `type` | `"human"`, `"flying"`, `"machine"`, `"device"`, or the integer 1 to 4 | The radar's icon: 1 ground unit, 2 flying, 3 machine or vehicle, 4 device (a rectangle with a disc). A name is stored as its number. `GetVehicleKind` takes 2 as `"air"`. | none: the class decides, and an unknown class is 1 |
| `size` | `"normal"` or `"big"` | `"big"` draws the icon at twice the size. | none: the class decides |
| `dead` | function | `dead(ent)`, server. Returns `true` when the entity is destroyed. A destroyed entity is not listed, its tag and marker are forgotten, the binoculars cannot tag it, and it does not count for the danger bar. Only the exact value `true` counts. | none |
| `awareness` | function | `awareness(ent, ply)`, server. Returns `level, exposure, seen, heard`, as `ENT:GetGryAwareness` does: level 0 calm, 1 alerted, 2 fighting (the value is rounded down and kept between 0 and 2); exposure 0 to 1; two booleans. The method of the entity wins when it has both. A call that errors leaves the radar's own rule. | none |
| `crew` | function | `crew(ent)`, server. Returns a list of players and NPCs. Used only when the relation of the entity came out `"neutral"`: the relation becomes `"hostile"` if one occupant is hostile to the player, else `"ally"` if one is an ally, else `"neutral"`. The player himself is not counted. A value that is not a table gives `"neutral"`. Without `crew` such a vehicle takes the relation of its driver (`GetVehicleDriver`). | none |
| `facing` | function | `facing(ent)`, server. Returns a world forward `Vector`; the radar's heading is its yaw. A value that is not a vector, a null one in x and y, or an error gives the usual rule (the entity's yaw, plus 90 degrees for an engine vehicle). The client redraws a contact whose entity it has with its own yaw and does not read this field. | none |

**Dangers (server and client)**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `danger` | table | Makes the entity a projectile or a trap the player is warned about. Sub-fields below. | none |
| `indicator` | `"warning"`, `"marker"` or `"none"` | Only `"warning"` draws anything: the grenade-detect icon with a label and a distance. The other two are stored. | `"warning"` when `danger` is set, else none |
| `label` | string, or function | A string of at least one character is the label of the warning when `danger.label` is missing. A function is accepted and stored, and nothing calls it. No other part of the HUD shows the label. | none |

The `danger` table accepts these sub-fields. Others are ignored.

| Sub-field | Type | What it does | Default |
| --- | --- | --- | --- |
| `label` | string, 1 to 32 characters | Text of the warning. | the entry's `label` when it is a string, else `"DANGER"` |
| `type` | string, 1 to 24 characters | Kind of icon. Stored; the warning has one icon. | none |
| `armed` | function | `armed(ent)`, server. `true` while the projectile is dangerous. The server follows the entity from its creation, asks five times a second and sends the answer in the networked bool `GryArmed`. A projectile held by a player or by the gravity gun is never armed. An error or any other answer is "not armed". Without it, the entity is dangerous as soon as it exists. | none |
| `range` | number, above 0 and at most 200 | Metres. The warning starts at this distance. It can only shorten the player's own range (`gry_grenade_range`). | none |
| `ownerOf` | function | `ownerOf(ent)`, server. Returns the player who threw or fired it. The server also reads the engine's owner and thrower. | none |
| `ownMissile` | boolean | `true`: the player fires it, and it never warns its own shooter. `false`: it warns the thrower within 15 m while the player's `gry_grenade_own_warn` is on. | `false` |
| `warnFor` | function | `warnFor(ent, ply)`, client. Returns `false` to say this projectile does not warn this player. Nothing, `true` or an error warns. | none |

**Rules of the suit (server)**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `heavy` | boolean, or function | `true`: a hit that breaks the armor of a player in armor mode, with this entity as attacker or inflictor, puts the suit down for 3 seconds (needs `gry_malfunction_impact`). A function is `heavy(ent)` and answers `true` for the entities that are. When the question is asked about a class name instead of an entity, a function gives `false`. | none |
| `shock` | `"light"` or `"strong"` | A hit with this inflictor is a light shock (the HUD flickers, the energy bar loses 1.5 per point of damage, from 5 to 30) or a strong one (suit down for 5 seconds), whatever the damage type. | none |
| `cloakBlind` | boolean | `true`: while a player is camouflaged, the server makes this NPC neutral to him and makes it forget him, and gives the attitude back when the cloak ends. Needs a `class`, because the server searches these classes only (through `TrackedClasses("cloakBlind")`). Needs `gry_cloak_ai`. | none |

```lua
GryMod.API.RegisterTracked("my_addon_buggy", {
	class = "prop_vehicle_my_addon_buggy",
	type = "machine",
	radar = "scan",
	crew = function(ent)
		return {ent:GetDriver()}
	end,
})
```

### GryMod.API.UnregisterTracked(key)

Shared. Removes the entry `key`.

Returns `true` when an entry was removed, `false` when there was none or `key` is not a string. The caches are emptied, so the entities go back to the usual rules at once.

### GryMod.API.GetTracked(ent)

Shared. Gives the first entry that matches the entity.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. A table with `IsValid` and `GetClass` methods is accepted. |

Returns the stored entry table, or `nil`. The table is the registry's own: read it and do not change it. It holds `key` and `priority`, the fields given at registration after normalisation (`class` and `base` as lists, `type` as a number), the defaults `scan`, `shape` and `relation`, and internal names for the callbacks. Returns `nil` when the registry is empty, when the value is not a valid entity, and when no entry matches.

The class is read with `ClassOf`. The answer for each class is cached until the next registration or removal, so the call allocates nothing and is cheap enough for the radar to ask for every NPC at every tick. A `match` function is not cached and runs on each call for entities of a class that no earlier entry took.

### GryMod.API.GetTrackedByClass(class)

Shared. Gives the first entry that names a class.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `class` | string | A class name. |

Returns the stored entry, or `nil`. Only the `class` lists are searched. An entry that matches by `base` or by `match` needs an entity and is not found here. Read the table and do not change it. The radar uses it for the icon of a class, and the suit's malfunction rules use it when they are given a class name.

### GryMod.API.TrackedClasses(field)

Shared. Lists the classes whose entry has a field set.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `field` | string | A field name of a definition, such as `"cloakBlind"`. |

Returns a list of class names. A class is in the list when the first entry that names it has the field set to a value that is not `false`; an entry above it that names the same class without the field takes it away. The order is the order of the entries. The list is empty for a name that is not a field, for a value that is not a string, and for an empty registry. The list is kept until the next change of the registry: read it and do not change it. Only the `class` lists count.

## Dangers

The three functions below read the entries that have a `danger` table. They are asked in both realms for every projectile: the server to follow and mark it, the client to know what to warn about. See [A dangerous projectile or trap](../entities.md#a-dangerous-projectile-or-trap) for the recipe.

### GryMod.API.GetDanger(classOrEntity)

Shared. Gives the first entry that has a `danger`.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `classOrEntity` | string or Entity | A class name, or an entity. |

Returns the stored entry, or `nil`. Read the table and do not change it.

With a class name, only the entries that name that class in `class` are searched. With an entity, the entries with a danger are tried in the order of the registry and the first that matches by class, base or `match` function is returned. This can differ from `GetTracked(ent)`: an entry with a higher priority and no `danger` matches the entity there and is skipped here.

For an entity, an entry that was found is kept until the registry changes, so a `match` function runs once for it. An entity for which nothing was found is asked again at each call, because a function can answer later, once the entity has its fields. Returns `nil` for an invalid entity, for a value that is neither a string nor an entity, and for an empty registry.

### GryMod.API.DangerNeedsEntity()

Shared. Says whether a class name is enough to find the dangers.

Returns `true` when at least one entry with a `danger` names its entities by `base` or by `match`. Then `GetDanger(class)` cannot place such an entity and only `GetDanger(entity)` can. The client uses it to judge an entity again one frame after its creation, once its fields are there. Returns `false` otherwise, including with an empty registry.

### GryMod.API.DangerClasses()

Shared. Lists the classes that have a danger entry.

Returns a list of class names, in the order of the entries. A class appears once, for the first entry with a danger that names it. The list is kept until the next change of the registry: read it and do not change it. The server uses it, when its file loads, to find the projectiles that already exist; the ones made before an entry is registered are not looked for again. Entries that match by `base` or `match` add nothing to the list.

## Vehicles

A vehicle of another addon is often not one engine entity with a seat: a simfphys car is a scripted entity with a separate seat for the player, and an LVS or Glide vehicle has its own seats. `Player:GetVehicle` then answers the seat, or nothing. A vehicle provider tells GryMod once how to find the vehicle of a player, who drives it, and what kind it is. The radar does not list the vehicle the player sits in, it colours a vehicle by its driver, and the binoculars do not scan what the player sits in. The provider table has this form:

| Field | Type | Meaning |
| --- | --- | --- |
| `ofPlayer` | function | Required. `ofPlayer(ply)` returns the vehicle entity or nothing. |
| `driver` | function | Optional. `driver(vehicle)` returns the player or NPC at the wheel, `false` for nobody, or nothing for no answer. |
| `kind` | string or function | Optional. `"ground"`, `"air"` or `"water"`, or `kind(vehicle)` returning one of them. |

### GryMod.API.AddVehicleProvider(key, spec)

Shared. Adds a vehicle provider, or replaces the one with the same key and keeps its place. `GryMod.API.Has("vehicles")` is true when it exists.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `key` | string | Name of the provider. Not empty. |
| `spec` | table | The provider, fields above. |

Returns `true`, or `false` and a reason: `"invalid key"`, `"the spec must be a table"`, `"ofPlayer must be a function"`, `"driver must be a function"` or `"kind must be \"ground\", \"air\" or \"water\""`. Providers are asked in the order they were added. Adding a key again re-arms its functions if they were switched off.

```lua
GryMod.API.AddVehicleProvider("my_addon", {
	ofPlayer = function(ply) return ply:GetNW2Entity("MyAddonCar") end,
	driver = function(car) return car:GetNW2Entity("MyAddonDriver") end,
	kind = "air",
})
```

### GryMod.API.RemoveVehicleProvider(key)

Shared. Removes the vehicle provider `key`.

Returns `true` when there was one, `false` otherwise, including for a `key` that is not a string. A vehicle that this provider already claimed keeps the claim in the table `GetVehicleKind` reads, so that call can still answer with the kind of a provider that was removed.

### GryMod.API.GetVehicleOf(ply)

Shared. Gives the vehicle the player is in.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ply` | Player | The player. A table with an `IsValid` method is accepted. |

Returns an entity, or `nil`. The first provider whose `ofPlayer` answers a valid entity wins, and the vehicle is remembered as claimed by it. When none answers, the result is `ply:GetVehicle()` if that is valid, which covers the Half-Life 2 vehicles. Returns `nil` for an invalid player.

### GryMod.API.GetVehicleDriver(vehicle)

Shared. Gives who is at the wheel.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `vehicle` | Entity | The vehicle. |

Returns the player or NPC, or `nil`. The providers that have a `driver` are asked in order. The first valid entity wins. An answer of `false` means nobody drives it: the result is `nil` and the entity's own `GetDriver` is not asked, which is the case of a car commanded from outside by a remote driver. Any other answer passes to the next provider. When no provider decides, the result is `vehicle:GetDriver()` if that is a valid entity (called under `pcall`), else `nil`.

### GryMod.API.GetVehicleKind(vehicle)

Shared. Says whether a vehicle is a ground, air or water vehicle.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `vehicle` | Entity | The vehicle. |

Returns `"ground"`, `"air"` or `"water"`. The kind is the one of the provider that claimed the vehicle through `GetVehicleOf` or `GetVehicleDriver`. A `kind` function is asked about the vehicle at each call. A vehicle no provider has claimed yet is claimed by the first provider that has both `driver` and `kind` and whose `driver` answers a valid entity for it. When there is no provider kind, or the function errors or answers something else, the result is `"air"` for a vehicle whose tracked entry has `type = "flying"` and `"ground"` for everything else. An invalid vehicle gives `"ground"`.
