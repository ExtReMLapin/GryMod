# Objectives reference

This page lists the functions of `GryMod.API` that manage objectives and the campaign data of a map. The objectives are a registry on the server. Each client receives a mirror of the objectives its player may see. The guide that explains what the HUD does with them, the three hooks and the map entity `gry_objective` is [api.md](../api.md#objectives), and the guide to the campaign objectives is [api.md](../api.md#campaign-objectives).

Every function here runs on the server. `GryMod.API.Has("objectives")` and `GryMod.API.Has("campaign")` tell whether they exist. The client side is `GryMod.Objectives.List()` and its companions, described in [api.md](../api.md#read-them-on-the-client).

## What the server does with an objective

Most of the entries below share the same rules, which are listed once here.

- **Memory.** The registry is in the memory of the server. Nothing in it is saved between sessions. A map cleanup (`game.CleanUpMap`) removes every objective, with the reason `"map_changed"`.
- **Network.** The server sends the changes in one message, `gry_objectives`. A client gets the full list of what it may see when it says it is ready, then each change as it happens. A client that is not ready yet is sent nothing. `filter(ply)` is asked when something is sent, so a player only receives the objectives his filter lets through.
- **The switch `gry_objectives`.** It is an administrator setting, 1 by default. At 0 nothing is sent and the three hooks `GryMod_ObjectiveAdded`, `GryMod_ObjectiveChanged` and `GryMod_ObjectiveRemoved` are not run on the server. The functions keep working and the registry keeps its objectives.
- **Hooks.** The hooks are reports. A listener's return value is not read, and a listener that raises is shown in the console, five times at most for each hook. The hooks receive `(id, obj, ...)`, where `obj` is a copy with the fields listed under `GetObjective`.
- **No error is raised.** Every function checks its input and returns `false` and a reason instead.

### GryMod.API.RegisterObjective(id, def)

Server. Adds an objective, or replaces the objective that has the same `id`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | 1 to 64 characters. It names the objective in every other call. | no |
| `def` | table | The definition, below. | no |

The fields of `def` that the code reads:

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `title` | string, 1 to 128 characters | The title that the displays and the banner show. | required |
| `description` | string, at most 512 characters | A longer text. | `""` |
| `primary` | boolean | `true` is a primary objective, `false` a secondary one. | `true` |
| `state` | `"active"`, `"done"` or `"failed"` | The state it starts in. | `"active"` |
| `pos` | Vector with finite components | Where the objective is. A copy is kept. | none |
| `ent` | Entity, or a function that returns one | An entity the objective follows. A function is called when the objective is registered, then every 0.5 s while the objective follows an entity and the switch is on. When it returns another entity, the objective follows that one. | none |
| `onRemove` | `"remove"`, `"complete"` or `"fail"` | What happens when the followed entity is removed. `"remove"` removes the objective (reason `"entity_removed"`). The two others keep it at the last position of the entity, stop following, and set the state to `"done"` or `"failed"`. It has no effect on an objective with `pos`. | `"remove"` |
| `radar` | boolean | Whether the radar and the minimap may show it. | `true` |
| `marker` | boolean | Whether the screen may show its marker. | `true` |
| `via` | array of Vectors, at most 16 | Waypoints, in order, on the way to the objective. They are sent to the clients as `obj.via`. An empty array is the same as none. | none |
| `filter` | function | `filter(ply)` is asked on the server for each player. Only the players for whom it returns a true value receive the objective. An error, or no answer, hides it from that player. The filter runs under `SafeCall` with the id `objective:<id>/filter`: five errors in a row switch it off and the objective is then hidden from everyone until it is registered again. | none: everyone sees it |

Give exactly one of `pos` and `ent`. A field that is not in this table is ignored. A `main` field is not read: the main objective is chosen with `SetMainObjective`.

Returns `true`, or `false` and a reason that names the field, for example `"invalid title: a text of 1 to 128 characters"`. The other reasons are `"invalid id: ..."`, `"invalid definition: it must be a table"`, `"invalid description: ..."`, `"invalid primary: true or false"`, `"invalid state: active, done or failed"`, `"invalid onRemove: remove, complete or fail"`, `"invalid radar: true or false"`, `"invalid marker: true or false"`, `"invalid filter: ..."`, `"give a pos or an ent, not both"`, `"invalid pos: ..."`, `"invalid ent: ..."`, `"give a pos (a Vector) or an ent (an entity, or a function that returns one)"`, `"invalid via: ..."`, `"too many objectives (256 at most)"` and, for an `ent` function, `"invalid ent: the function failed: ..."` or `"invalid ent: the function did not return a valid entity"`.

Behaviour to rely on:

- The limit of 256 objectives applies to new ids. Replacing an existing id never fails on the count.
- Replacing an id swaps the whole definition. A field that is left out takes its default again, `state` included. The objective keeps its place in the list and, if it was the main objective, it stays the main one.
- The effect is immediate. The players who may see it are sent the record, and the players who saw it and may not any more are told it is gone.
- A new id runs `GryMod_ObjectiveAdded(id, obj)`. An existing id runs `GryMod_ObjectiveChanged(id, obj, oldState)` only when the title, the description, the state or the `primary` flag differ from the old definition. A change of position, `radar`, `marker`, `via`, `filter` or `ent` is sent to the clients and reported by no hook.
- While at least one objective follows an entity, the server keeps a hook on `EntityRemoved`. While the switch `gry_objectives` is also on, a timer runs every 0.5 s and sends the new position only when the entity moved more than 32 units. With no such objective neither exists.

```lua
GryMod.API.RegisterObjective("my_addon.kill_captain", {
	title = "Kill the captain", primary = false, ent = captain, onRemove = "complete"
})
```

### GryMod.API.SetObjectiveState(id, state)

Server. Changes the state of an objective.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The objective. | no |
| `state` | string | `"active"`, `"done"` or `"failed"`. | no |

Returns `true`, or `false` and a reason: `"unknown objective"`, `"invalid state: active, done or failed"`. Setting the state the objective already has returns `true` and tells nobody. Otherwise the clients that may see it get the new record at once and `GryMod_ObjectiveChanged(id, obj, oldState)` runs. The HUD plays the banner `objective` from that hook, see [events.md](../events.md#objective-banner).

### GryMod.API.RemoveObjective(id)

Server. Removes an objective.

Returns `true`, or `false` and `"unknown objective"`. If it was the main objective, there is no main objective afterwards. The clients that had it are sent a removal and `GryMod_ObjectiveRemoved(id, obj, "removed")` runs, with `obj` the copy as it was.

### GryMod.API.SetMainObjective(id)

Server. Chooses the main objective, the one the displays stress. There is at most one.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string, `nil` or `false` | The objective. `nil` or `false` takes the main flag away. | no |

Returns `true`, or `false` and `"unknown objective"` for a string that is not an objective and for any other type. Asking for the objective that is already main returns `true` and does nothing. Otherwise each ready player is told the id, or an empty id when he may not see that objective. `GryMod_ObjectiveChanged` runs for the old main objective and for the new one, each with its current state as `oldState`.

### GryMod.API.GetObjective(id)

Server. Returns a copy of one objective, or `nil` when there is none (also when `id` is not a string).

The copy has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `id`, `title`, `description` | string | As registered. |
| `primary` | boolean | |
| `main` | boolean | Whether it is the main objective now. |
| `state` | string | `"active"`, `"done"` or `"failed"`. |
| `pos` | Vector | Where the objective is now. It is the position of the entity while the objective follows a valid one. |
| `ent` | Entity or `nil` | The followed entity, when there is one and it is valid. |
| `radar`, `marker` | boolean | |
| `onRemove` | string | `"remove"`, `"complete"` or `"fail"`. |
| `via` | array of Vectors or `nil` | A copy of the waypoints. |

Nothing in the copy belongs to the registry, so a caller may change it. A change has no effect.

### GryMod.API.GetObjectives()

Server. Returns an array of copies, as `GetObjective` gives them, in the order the ids were registered. The array is empty when there are no objectives.

### GryMod.API.ClearObjectives()

Server. Removes every objective.

Returns the number of objectives that were removed. The main objective is cleared too. When the switch `gry_objectives` is on and at least one objective existed, the ready clients get one clear message with the reason `"cleared"`, then `GryMod_ObjectiveRemoved(id, obj, "cleared")` runs for each objective that was removed. When the switch is off, the registry is emptied and nothing is sent or reported.

### GryMod.API.RefreshObjectives([ply])

Server. Sends the objectives again and asks the filters again. Use it when the rule of who sees what has changed.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player to refresh. | yes: every ready player |

Returns `true`, or `false` and `"the client of this player is not ready"` when `ply` is not a valid player whose client has said it is ready. Without an argument the call returns `true` even when nobody is ready. Each refreshed player gets the full list: a begin marker, one record for each objective he may see, an end marker. The message is sent even when the list is empty, so the client drops what it still had. On the client the hooks run during this list, and `GryMod.Objectives.Syncing()` is true while it arrives. While the switch `gry_objectives` is 0 nothing is sent and the call still returns `true`.

## Campaign data

The campaign system lists the objectives of a map from a file of data, `lua/grymod/campaign/<game>/<map>.lua` with `<game>` one of `hl2`, `ep1`, `ep2`. It registers each step through `RegisterObjective`, so every rule above applies to them. These three functions let an addon give a map its own list, change one objective of the shipped list, or forget what was done. The behaviour of the system, its settings (`gry_campaign_objectives`, `gry_campaign_secrets`) and the shipped data are described in [api.md](../api.md#campaign-objectives).

What a call gives is kept in the memory of the server, for the map it names, and is lost when the server stops. Make the calls at every load, from an autorun file. When a call concerns the map that is running, the campaign system has started and `gry_campaign_objectives` is 1, that map's objectives are listed again at once: the objectives the campaign had registered are removed, then the ones the new list asks for are registered. What was done before comes back from the saved progress. A chain that cannot start is not reported by these functions. An objective whose `after` names a step that is not in the list, or whose `after` chain loops, is dropped when the list is used, with a line in the server console.

### GryMod.API.RegisterCampaignMap(map, list, opts)

Server. Gives a map a list of campaign objectives.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `map` | string | The name of the map: 1 to 64 letters, digits, `_` or `-`. | no |
| `list` | array of tables | The objectives, below. At most 200. | no |
| `opts` | table | `replace` and `fail_events`, below. | yes |

| Field of `opts` | Type | Meaning | Default |
| --- | --- | --- | --- |
| `replace` | boolean | `true` drops what GryMod ships for the map and what earlier calls gave, and uses this list. Anything other than `true` adds the list to what exists: an objective with an id that is already there replaces it where it stood, a new id goes at the end. | `false` |
| `fail_events` | array of `{entity = string, input = string}` | The map's own "game over" messages. When the named entity (1 to 64 characters) receives the named input, every primary step that is waiting fails. | none |

Returns `true`, or `false` and a reason. The reasons are `"invalid map: ..."`, `"invalid opts: ..."`, `"invalid list: an array of objectives"`, `"too many objectives (200 at most)"`, `"objective #<n> (\"<id>\"): <why>"`, `"objective #<n> (\"<id>\"): the id is given twice"` and `"fail_events #<n>: <why>"`. Nothing is kept when anything is wrong. An empty list is valid. With `replace = true` it leaves the map with no campaign objectives. Several calls for the same map pile up and are applied in the order they were made.

The fields of one objective in `list`. A field that is not here is ignored.

| Field | Type | What it does | Default |
| --- | --- | --- | --- |
| `id` | string, 1 to 64 characters | The objective's id, unique in the list. It is the id given to `RegisterObjective`. | required |
| `title` | string, 1 to 128 characters | As for `RegisterObjective`. | required |
| `description` | string, at most 512 characters | As for `RegisterObjective`. | `""` |
| `primary` | boolean | As for `RegisterObjective`. A secondary step is never the main objective. | `true` |
| `secret` | boolean | A hidden item. It is counted in the one objective `Secrets n/m` while `gry_campaign_secrets` is on, and never listed by itself. | `false` |
| `exit` | boolean | The way out of the map. It is listed from the start when it has no `after`. A primary exit is the main objective when no other primary step is listed. | `true` when `complete` has the kind `changelevel`, else `false` |
| `pos` | Vector | Where the step is. | none |
| `place` | string, 1 to 64 characters | The name of a map entity. Its position is used when the step is listed, and `pos` is the fallback. | none |
| `via` | array of Vectors, at most 16 | Waypoints, as for `RegisterObjective`. | none |
| `after` | string, or array of at most 8 ids | The steps that must be done first. The step is not listed, and not waited for, until they are. | none |
| `complete` | completion | What finishes the step. | required |
| `fail` | completion | What fails the step. Its kind is `input`, `removed` or `killed`. | none |
| `tr` | table | Texts in other languages: `{fr = {title = "...", description = "..."}}`. A language name is 1 to 8 characters. The language of the server (`gmod_language`) picks the entry, and a missing or empty text falls back to the English one. | none |

Give at least one of `pos` and `place`. A step is registered with `RegisterObjective` using only `title`, `description`, `primary`, a position and `via`. The state of a step that is done comes from `SetObjectiveState`. A step that is done stays in the list for 8 seconds and is then removed.

A completion is a table with a `kind` and the fields that kind needs. `also` may hold one alternative completion of the same shape, which cannot have an `also` of its own. Either one finishes the step.

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | string | Required. One of `input`, `pickup`, `enter_vehicle`, `use`, `changelevel`, `removed`, `killed`. |
| `entity` | string, 1 to 64 characters | The name of a map entity. Names are not case sensitive. The form the engine gives to an entity made by a `point_template`, `name&0003`, matches `name`. |
| `class` | string, 1 to 64 characters | A classname. |
| `input` | string, 1 to 64 characters | The name of an input. |
| `target` | string, 1 to 64 characters | The name of the next map. |
| `mapid` | whole number, 0 or more | The `Entity:MapCreationID()` of the entity. |
| `at` | Vector | A place the entity must be near. |
| `radius` | number above 0 | How near `at` must be, in units. Default 8. |
| `also` | completion | The alternative. |

The fields each kind needs, and when it finishes:

| `kind` | Needs | Finishes when |
| --- | --- | --- |
| `input` | `entity` and `input` | the named map entity receives the input |
| `pickup` | `class` | a player takes the weapon (`weapon_*`) or the item (`item_*`) |
| `enter_vehicle` | `class` or `entity` | a player gets into the vehicle |
| `use` | `entity`, or `mapid`, or `class` with `at` | a player presses the use key on the entity |
| `changelevel` | `target` | the level ends while a living player stands within 72 units of the box of a `trigger_changelevel` that leads to `target` (when no trigger can be matched to `target`, any `trigger_changelevel` counts); `entity` limits it to the trigger of that name |
| `removed` | `entity`, `class` or `mapid` | the entity is removed, outside a map cleanup and the end of the level |
| `killed` | `entity`, `class` or `mapid` | an NPC that matches dies |

The fields that are given must all hold for an entity to match. For `pickup` and `enter_vehicle`, a `class` alone decides and the other fields are not compared.

```lua
GryMod.API.RegisterCampaignMap("my_map", {
	{id = "my_addon.start", title = "Find the generator", pos = Vector(100, 0, 0), complete = {kind = "use", entity = "generator_button"}},
	{id = "my_addon.exit", title = "Leave", pos = Vector(900, 0, 0), after = "my_addon.start", complete = {kind = "changelevel", target = "my_next_map"}}
}, {replace = true})
```

### GryMod.API.OverrideCampaignObjective(map, id, def)

Server. Replaces one objective of a map by its id, adds it when the id is new, or removes it.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `map` | string | The map, as for `RegisterCampaignMap`. | no |
| `id` | string | The id of the objective, 1 to 64 characters. | no |
| `def` | table or `false` | The objective, with the fields of `RegisterCampaignMap`. `false` removes the objective. | no |

Returns `true`, or `false` and a reason: `"invalid map: ..."`, `"invalid id: ..."`, `"invalid definition: an objective (a table), or false to remove it"`, or the reason of the field that is wrong. The `id` argument wins over a `def.id`. Removing an objective that does not exist is accepted and changes nothing. When an objective is removed, the steps that came after it come after what it came after, so the chain goes on. The call joins the same list of operations as `RegisterCampaignMap`, in order, so a later call can add the id again.

### GryMod.API.ResetCampaignProgress([map])

Server. Forgets what the campaign has saved: the steps that are done and the secrets that are found.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `map` | string | The map to forget. | yes: every map |

Always returns `true`. The progress is saved in the `gry_campaign` table of the server's database (`sv.db`), one row for each map, and it survives between sessions. This call deletes the row of `map`, or every row when `map` is `nil`. It does not check the name. When the campaign system has started, the running map is then started again from its list, whichever map was reset, and while `gry_campaign_objectives` is 0 that start lists nothing. The console command `gry_campaign_reset` (administrators) calls it for the running map, and `gry_campaign_reset all` for every map.
