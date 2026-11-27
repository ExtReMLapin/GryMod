# Usable things: the use prompt

This page lists the functions of `GryMod.API` behind the use prompt, the icon and the text under the crosshair when the player looks at something he can use or take ("ENTER VEHICLE", "CLIMB", "USE"). The registry of usable entities says what each thing is, a filter takes the prompt away for an entity the player may not use, and a few functions answer the questions the crosshair asks. The long description of the stock entries, the spawnflags that decide what answers the key, and the groups is in [Usable things: the use prompt](../api.md#usable-things-the-use-prompt) of the API guide.

The registry exists in both realms, and the only reader in GryMod is the client: the crosshair's test of what can be used and the prompt under it. `GryMod.API.Has("usable")` is true when the registry is there. The player turns the prompt off with `gry_hud_usehint`. The client hook `GryMod_UsableChanged(ent, mode, ply)` tells an addon when the aimed thing changes (see [events.md](../events.md#grymod_usablechanged-ent-mode-ply)).

Callbacks run under `GryMod.API.SafeCall` (see [Safe calls](../api.md#safe-calls)): an error counts as "no answer", the fifth in a row switches that callback off, and registering the entry again re-arms it.

## The registry

An entry is matched on a class, on a base class or by a function. The entries are tried by `priority`, the higher first, and in the order of registration among equal priorities. The first entry that matches and applies decides what the entity shows. An entity that no entry names has no prompt, and what the player takes by walking over it (a weapon, an item) needs no entry. The stock Half-Life 2 and Garry's Mod entries are registered through the same call with a priority of -100.

### GryMod.API.RegisterUsable(key, def)

Shared. Adds the entry `key`, or replaces it. Registering an entity makes it usable: the crosshair's "usable" state opens on it and the prompt shows.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `key` | string | Name of the entry. Not empty. An existing key is replaced. |
| `def` | table | The definition, fields below. Fields that are not listed are ignored. |

Returns `true`, or `false` and a reason: `"invalid key"`, `"the definition must be a table"`, `"invalid <field>: <value>"`, `"nothing to match on: give a class, a base or a match function"`, or `"nonsolid needs a class: the crosshair looks for the entities of those classes"`. A refused definition changes nothing and the previous entry stays. Replacing an entry with the same priority keeps its place in the order; with another priority it goes to the end of its new priority group. Every registration empties the caches of the registry.

At least one of `class`, `base` and `match` is required.

**What matches**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `class` | string, or list of strings | Class names to match. Each is 1 to 64 characters; a list cannot be empty. The class is read with `GryMod.API.UsableClassOf(ent)`. | none |
| `base` | string, or list of strings | Matches an entity whose class equals the name, whose `Base` field equals it, or that `scripted_ents.IsBasedOn` says is built on it. Same limits as `class`. | none |
| `match` | function | `match(ent)`. Matches when it returns `true`. It runs on each `GetUsable` call for an entity of a class that no class or base of an earlier entry took, and its answer is not cached. | none |
| `priority` | number, -1000 to 1000 | Order of the entries. | `0` |
| `spawnflags` | table, or function | The entry applies only when the flags of the entity pass the rule. A table is `{need = bits, forbid = bits}`: all the `need` bits must be set and none of the `forbid` bits. Both are integers from 0 to 2147483647 and at least one key is required. A function is `fn(flags, ent)` and lets the entity through by returning `true`. See `UsableFlagsAllow`. | none |
| `active` | function | `active()`, called with no argument. Returns `false` or nothing when the entry does not apply at all now, for a reason that is a setting and not a property of the entity. An error counts as "applies". | none |

**What the prompt shows**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `icon` | `"use"`, `"enter"`, `"pickup"`, `"grab"` or `"ladder"` | The icon of the movie. `"grab"` counts only while the player can lift the entity: at most 35 kg and 128 units on every side (the client reads the size and asks the server for the mass, and until the answer is there the prop is not offered). `"enter"` does not count while the player sits in a vehicle. | `"use"` |
| `text` | string, or function | The text of the prompt, shown in capitals. A string is 1 to 64 characters and may contain `%1`, replaced by the name. A function is `text(ent, ply)` and returns the string. A result that is not a string, is empty, or an error gives `"USE"`. The text is worked out when the aimed entity or the usable state changes, not at every frame. | `"USE"` |
| `name` | string, or function | What `%1` stands for. A string is 1 to 64 characters; a function is `name(ent)` and returns a string. See `UsableName` for the fallback. | none |
| `group` | string | A kind of prompt the player can switch off with the client convar `gry_usehint_<group>`. 1 to 24 characters among `a-z`, `0-9` and `_`. A group with no convar is always on. The convar is looked up once per group, and a missing one is remembered, so create it before the prompt is first asked for that group. | none |

**What the key does**

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `use` | `"once"` or `"repeat"` | `"once"`: the use changes the state of the thing (a grenade taken, a vehicle entered). The prompt goes away at the key press and stays away while the player keeps aiming at the same thing; it comes back after he looks elsewhere. `"repeat"`: the use can be done again (a door, a button). The prompt stays, the HUD event `use_feedback` plays (the icon pulses and a sound plays), and the prompt is dimmed for `cooldown` seconds. | `"once"` |
| `cooldown` | number, 0 to 60 | Seconds a `"repeat"` prompt is dimmed after the key. | 0.5 |
| `hold` | boolean | `true`: the key is kept down while the thing works (a charger, a wheel). The feedback comes once, at the press, however often the bind repeats, and the key press does not start the cooldown. The test for `hold` comes before the one for `use`. | `false` |
| `ready` | function | `ready(ent)`. `false` dims the prompt, and the key does nothing yet. Any other answer, and an error, count as ready. | none |
| `busy` | function | `busy(ent, ply)`. `true` takes the prompt away because the thing is in use. Any other answer, and an error, count as not busy. | none |
| `range` | number, 1 to 1000 | How far the key reaches for this entry, in units. | `GryMod.API.USE_REACH` (80) |
| `nolimits` | boolean | `true` for a `"grab"` whose engine use has no size or mass limit (the floor turret). | `false` |
| `nonsolid` | boolean | `true` for a thing the eye trace passes through (a ladder). The crosshair looks for the entities of the entry's classes along the aim ray. Needs a `class`. | none |
| `netclass` | string, or list of strings | The name the client gives these entities when the game has no client class of their name (`"class C_BaseToggle"`). Read only for an entry with `nonsolid`; it adds names to `UsableNonSolidClasses`. Same limits as `class`. | none |

The feedback, the cooldown and the pulse follow the client convar `gry_usehint_feedback` (1 by default).

```lua
GryMod.API.RegisterUsable("my_addon_terminal", {
	class = "my_addon_terminal",
	icon = "use",
	text = "HACK %1",
	name = "terminal",
	use = "repeat",
	cooldown = 2,
	busy = function(ent, ply)
		return ent:GetNWEntity("user") == ply
	end,
})
```

### GryMod.API.UnregisterUsable(key)

Shared. Removes the entry `key`.

Returns `true` when an entry was removed, `false` when there was none or `key` is not a string. The caches are emptied.

### GryMod.API.GetUsable(ent)

Shared. Gives the entry that says what the entity is for the use prompt.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. A table with `IsValid` and `GetClass` methods is accepted. |

Returns the stored entry table, or `nil`. The table is the registry's own: read it and do not change it. It holds `key`, the fields given at registration (`class` and `base` as lists), and the defaults `icon`, `text`, `priority` and `use`. Returns `nil` for an empty registry, for an invalid entity and when no entry applies.

The first entry in the order that matches and applies is returned. An entry whose `active` says no, or whose `spawnflags` rule refuses the entity, is skipped and the next one is tried. The match by class and base is cached for each class until the next registration or removal. The `match` functions, the `active` functions and the spawnflags rules are run again at each call.

### GryMod.API.UsableClassOf(ent)

Shared. Gives the class the registry matches an entity on.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | A valid entity. |

Returns a string. It is `GryMod.API.ClassOf(ent)`, except for a name that starts with `class C_`. On the client, `GetClass` answers the name of the network class for entities the game has no client class of that name for: `class C_BaseToggle` for a `func_button`, a `func_rot_button` and a `momentary_rot_button`. For such a name the function calls `GryMod.API.UsableClassResolver`, which the client installs, and returns its answer when it is a string that is not empty. The resolver asks the server, keeps each answer for 20 seconds, sends at most one question every 0.2 second, and the server answers a player 10 times a second at most. While no answer is there, or when the resolver fails (it runs under `pcall`), the generic name is returned and it matches no entry, so the entity has no prompt for the tenth of a second the answer takes.

### GryMod.API.UsableFlagsAllow(entry, ent)

Shared. Says whether the spawnflags of the entity let the entry apply.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `entry` | table | An entry, as `GetUsable` returns it. |
| `ent` | Entity | The entity whose `GetSpawnFlags` is read. |

Returns a boolean. It is `true` when the entry has no `spawnflags` rule, when `entry` or `ent` is missing, when the entity has no `GetSpawnFlags` method, and when the flags are not a number: only a flag that clearly says no refuses. With a table rule it is `false` when a `need` bit is missing or a `forbid` bit is set. With a function rule it is `true` only when the function returns `true`, and also when the function errors.

### GryMod.API.UsableNonSolidClasses()

Shared. Lists the classes of the entries marked `nonsolid`.

Returns a list of class names, in the order of the entries, without repeats. The `netclass` names of those entries follow their classes. The crosshair looks for the entities of these classes along the aim ray, since the eye trace passes through them. An entry whose `active` says no is left out. The list is kept until the next registration or removal, except while an entry with `nonsolid` has an `active` function: then the list is built again at each call. Read the list and do not change it.

## Reach

The use key reaches 80 units from the eye. The crosshair shows a prompt only inside the reach of the entry. When the eye trace hits something farther away than that, the prompt does not show.

### GryMod.API.USE_REACH

Constant, a number: `80`. It is the reach of the use key in units, the `PLAYER_USE_RADIUS` of the Source SDK, measured from the eye to the point hit. It is the reach of an entry that gives no `range`.

### GryMod.API.UsableRange(entry)

Shared. Gives how far the key reaches for an entry.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `entry` | table or nil | An entry, as `GetUsable` returns it. |

Returns the `range` of the entry in units, or `GryMod.API.USE_REACH` when the entry has none or `entry` is `nil`.

### GryMod.API.UsableMaxRange()

Shared. Gives the greatest reach of all the entries.

Returns a number in units: `GryMod.API.USE_REACH`, or the largest `range` among the entries when one is greater. It is 80 with the stock entries. The crosshair casts its trace this far to see anything usable. The value is kept until the next registration or removal.

## What the prompt does now

### GryMod.API.UsableReady(ent, entry)

Shared. Says whether the thing can be used now.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. |
| `entry` | table | The entry that matches it. |

Returns `false` only when the entry has a `ready` function and it returns `false`. Returns `true` when `entry` is missing, when it has no `ready`, when the function returns anything other than `false`, and when it errors, so that a broken function does not dim the prompt for ever. The prompt is dimmed while this is `false`.

### GryMod.API.UsableBusy(ent, ply, entry)

Shared. Says whether the thing is in use and shows no prompt.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. |
| `ply` | Player | The player who looks at it. |
| `entry` | table | The entry that matches it. |

Returns `true` only when the entry has a `busy` function and it returns `true`. Returns `false` when `entry` is missing, when it has no `busy`, and when the function errors or answers anything else.

## Text and icons

### GryMod.API.UsableName(ent, entry)

Shared. Gives what the entity is called in the prompt, the value of `%1`.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity. |
| `entry` | table or nil | The entry that matches it. |

Returns a string that is never empty. The name of the entry is used first: a string as it is, or the result of the `name` function when it is a string that is not empty. Next comes the `GetPrintName` of the entity, with a leading `#` translated through `language.GetPhrase`. The last fallback is the class with `weapon_` or `item_` removed from its start and the underscores replaced by spaces.

### GryMod.API.UsableText(ent, ply, entry)

Shared. Gives the text of the prompt for an entity and a player.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ent` | Entity | The entity. | no |
| `ply` | Player | The player, passed to a `text` function. | no |
| `entry` | table | The entry to use. | yes, `GetUsable(ent)` when missing |

Returns the text in capitals, or `nil` when no entry names the entity (the caller then shows the plain `"USE"`). A `text` function that errors or returns something that is not a string, or an empty one, gives `"USE"`. `%1` is replaced by `UsableName(ent, entry)` before the text is put in capitals.

### GryMod.API.UsableIcons

Constant, a table. The five icon names of the prompt's movie as keys with the value `true`: `use`, `enter`, `pickup`, `grab` and `ladder`. They are the values the `icon` field accepts. The table is the one the registry validates against.

## Filters

The registry says what the use key does for a thing and not who may use it. A filter takes the prompt away for an entity that this player may not use: a prop protection, a locked vehicle, a door that only its owner opens. A filter never adds a prompt, and an entity that the registry does not call usable stays not usable. Filters exist on the client only. `GryMod.API.Has("usablefilter")` is true when they are there.

### GryMod.API.AddUsableFilter(id, fn)

Client. Adds a filter, or replaces the one with the same id.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `id` | string | Name of the filter. Not empty. |
| `fn` | function | `fn(ent, ply)`. Returns `false` to refuse the prompt. Any other answer, nothing included, is no opinion. |

Returns `true`, or `false` with no reason when `id` is not a non-empty string or `fn` is not a function. Adding an id again replaces the function, keeps its place in the order, and re-arms a filter that was switched off.

The crosshair asks the filters after the entry has matched, the group is on, and before the reach is tested, for the one entity the player aims at, at most ten times a second. The filter has to be cheap.

```lua
GryMod.API.AddUsableFilter("my_addon", function(ent, ply)
	if MyAddon.IsLockedAgainst(ent, ply) then
		return false
	end
end)
```

### GryMod.API.RemoveUsableFilter(id)

Client. Removes the filter `id`.

Returns `true` when there was one, `false` otherwise. The failure count of the filter is cleared.

### GryMod.API.UsableFiltered(ent, ply)

Client. Says whether a filter refuses the prompt for the entity.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `ent` | Entity | The entity the player aims at. |
| `ply` | Player | The local player. |

Returns `true` when at least one filter returns exactly `false`, and `false` otherwise. The filters are asked in the order they were added and the loop stops at the first refusal. A filter that errors gives no opinion. This is the call the crosshair makes; an addon rarely needs it.
