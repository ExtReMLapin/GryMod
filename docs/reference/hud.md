# HUD reference

This page lists the functions of `GryMod.API` that act on the HUD: the HUD events and the data they carry over the network, the text lines, the pickup icons, the marker sources of the radar and the commands of the effects test window. The list of the events GryMod plays itself, with their data and the player options that cut them, is in [events.md](../events.md#the-events). The guides that explain how the parts fit together are [events.md](../events.md) and [api.md](../api.md).

Each entry names its realm. A function is defined only in the realm it names. `HUDEvent` and `ShowMessage` are defined in both, with different arguments, and the entries say what each realm does.

## HUD events

A HUD event is a name that the client maps to one handler. The handler plays the picture and the sound of the effect together. The registry lives on the client. The server only asks a client to play an event, by name.

### GryMod.API.RegisterHUDEvent(name, fn [, info])

Client. Declares the HUD event `name` and the function that plays it.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `name` | string | Letters, digits and underscore, 1 to 32 characters. | no |
| `fn` | function | `fn(data)`, called each time the event plays. `data` is a table, empty when the caller gave none. The return value is not read. | no |
| `info` | table | Describes the event for tools. Only the effects test window reads it. | yes |

Returns `true`, or `false` and a reason: `"invalid event name"`, `"invalid function"`.

The fields of `info` that the code reads are these. Anything else in the table is ignored.

| Field | Type | What it changes | Default |
| --- | --- | --- | --- |
| `label` | string, 1 to 64 characters | The text of the event's button in the effects test window. | the name of the event |
| `variants` | array of tables | One button each. A variant is `{label = string (1 to 64 characters), data = table}`; `data` is optional and is copied when the event is registered. The button plays the event with that data. | none: one button for the event |
| `follows` | array of `{convar, text}` | The options of the player that cut the effect. Both values are strings and `convar` is not empty. The window shows them in the tooltip of the button. | none |

A piece of `info` that is malformed is left out and the rest is kept. An `info` that is not a table gives the default label and nothing else.

Registering a name that exists replaces its handler and its `info`, and arms the handler again if it had been switched off. No name is reserved: the events that GryMod registers itself are replaced like any other. Each call of the handler goes through `GryMod.API.SafeCall` under the id `hudevent:<name>`. The fifth error in a row switches the handler off, with one line in the console, until the name is registered again.

```lua
GryMod.API.RegisterHUDEvent("my_flash", function(data)
	GryMod.PlaySound("buttons/button17.wav")
end, {label = "My flash", follows = {{"gry_sounds", "the sound"}}})
```

### GryMod.API.UnregisterHUDEvent(name)

Client. Removes the HUD event `name`, its handler and its `info`.

Returns `true` when there was such an event, `false` otherwise.

### GryMod.API.ListHUDEvents()

Client. Lists the names of the registered HUD events.

Returns a new array of strings, sorted. The effects test window builds its buttons from this list.

### GryMod.API.GetHUDEventInfo(name)

Client. Returns what an event says of itself.

Returns a copy of `{label, variants, follows}`, or `nil` when no event has this name. `label` is always there (the name when the event gave none). `variants` and `follows` are there only when the event gave at least one valid entry.

### GryMod.API.HUDEvent([players,] name [, data])

Client and server. Plays a HUD event. The two realms take different arguments.

**On the client**, `GryMod.API.HUDEvent(name, data)` plays the event on this client.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `name` | string | The event to play. | no |
| `data` | table | Passed to the handler. | yes, `{}` |

Returns `true` when the handler ran without error. Returns `false` and a reason otherwise: `"unknown event"`, `"disabled"` (five errors in a row, see `RegisterHUDEvent`), or the error message of the handler. The call is immediate. The client does not check `data` against `GryMod.API.HUDEventLimits`: the limits apply to what goes over the network. When the handler succeeded, the hook `GryMod_HUDEvent(name, data)` runs, with the same `data` table that the handler received. The hook is called with a plain `hook.Run`, outside the protection of the handler.

**On the server**, `GryMod.API.HUDEvent(players, name, data)` asks the clients of `players` to play the event.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `players` | Player or array of Players | The recipients. Entries that are not valid players are left out. | no |
| `name` | string | The event to play. | no |
| `data` | table | At most 8 fields of finite numbers, strings or booleans, see `HUDEventLimits`. | yes |

Returns `true` and the number of recipients, or `false` and a reason. The reasons are the ones of `CheckHUDEvent`, or `"no valid recipient"`. The count is the number of clients the message was sent to, not a confirmation that an event of that name exists there: a client that has no such event drops the message without a word. The message is `gry_api_hud`, sent with `net.Send`.

```lua
GryMod.API.HUDEvent(ply, "malfunction", {seconds = 3})  -- server: one player
GryMod.API.HUDEvent("jam", {seconds = 3})               -- client: this screen
```

### GryMod.API.ReceiveHUDEvent()

Client. The receiver of the network message `gry_api_hud`. It reads the message with `ReadHUDEvent` and plays the event with `HUDEvent(name, data)`. A message that breaks the bounds is dropped, and so is a message that names an event the client does not have. Nothing is printed.

GryMod registers it with `net.Receive` when the file loads. It takes no argument and reads the current net message.

## The data of an event and the network message

The server and the client share five entries for the payload of `gry_api_hud`: the limits, a name test, a check, a writer and a reader. They are defined in both realms.

### GryMod.API.HUDEventLimits

Shared. A table with the bounds of a HUD event. Its exact contents:

```lua
{name = 32, fields = 8, key = 24, string = 128}
```

| Key | Meaning |
| --- | --- |
| `name` | Longest event name, in characters. |
| `fields` | Most fields in the data table. |
| `key` | Longest field name, in characters. |
| `string` | Longest string value, in characters. |

The checks read this table every time they run. Treat it as read-only.

### GryMod.API.IsValidHUDEventName(name)

Shared. Tells whether `name` can name a HUD event.

Returns `true` when `name` is a string of 1 to `HUDEventLimits.name` characters, all letters, digits or underscore. Returns `false` for anything else, including a value that is not a string.

### GryMod.API.CheckHUDEvent(name, data)

Shared. Tells whether an event name and its data can be sent.

Returns `true`, or `false` and a reason. `data` may be `nil`. The reasons, in the order they are tested:

| Reason | Cause |
| --- | --- |
| `invalid event name` | `name` fails `IsValidHUDEventName`. |
| `the data must be a table` | `data` is neither `nil` nor a table. |
| `too many fields (8 at most)` | More than `HUDEventLimits.fields` fields. |
| `invalid field name` | A key is not a string of 1 to 24 letters, digits or underscore. A numeric key fails here. |
| `string too long in field '<key>'` | A string value is longer than 128 characters. |
| `field '<key>' must be a finite number, a string or a boolean` | A table, a function, `nan` or an infinity as a value. |

The server calls it in `HUDEvent`. An addon can call it before it builds an expensive payload.

### GryMod.API.WriteHUDEvent(name, data)

Shared. Writes the event into the net message that the caller has started. It starts nothing and sends nothing, and it does not check its arguments: call `CheckHUDEvent` first.

The layout is: the name (string), the field count (4 bits), then for each field its key (string), a type tag of 2 bits (`0` number, `1` string, `2` boolean) and the value (a double, a string, a boolean). The order of the fields is the order of `pairs`. Returns nothing.

### GryMod.API.ReadHUDEvent()

Shared. Reads an event written by `WriteHUDEvent` from the current net message.

Returns the name and a new data table, or `nil` when the message breaks a bound: an invalid name, more than 8 fields, an invalid field name, a string over 128 characters, a number that is not finite, or an unknown type tag. A caller must drop the message when it gets `nil`, and does not get a partial table.

## Text lines

### GryMod.API.ShowMessage([players,] text [, opts])

Client and server. Shows a line of text on the HUD, with its sound. It builds the data of the event `message` and plays it with `HUDEvent`. `GryMod.API.Has("messages")` is true when it exists. The lanes and the suit's own lines are described in [events.md](../events.md#text-lines).

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `players` | Player or array of Players | Server only. The recipients. | no on the server |
| `text` | string | The line. Runs of spaces, tabs and line breaks become one space and the ends are trimmed. At most 128 characters after that. | no |
| `opts` | table | `lane`, `sound`, `duration`, below. | yes |

| Field of `opts` | Type | Meaning | Default |
| --- | --- | --- | --- |
| `lane` | string or whole number | `"top"` (1), `"middle"` (2), `"status"` (3) or `"crosshair"` (4). | `"top"` |
| `sound` | string | A sound path, 1 to 128 characters, played with the line through GryMod's mix. | none |
| `duration` | number | The whole life of the line in seconds. A value outside 0.5 to 60 is moved to the nearest bound, not refused. | 5 |

Returns what `HUDEvent` returns in the same realm. On the client that is `true` when the event ran, and the value stays `true` when the player turned the text lines off or the HUD is hidden: the event ran and drew nothing. On the server it is `true` and the number of recipients. When the arguments are wrong nothing is shown and the call returns `false` and one of these reasons: `no text` (not a string, or empty after cleaning), `text too long (128 characters at most)`, `the options must be a table`, `invalid lane`, `invalid sound`, `invalid duration`. A text that is too long is refused and not cut.

On the client the hook `GryMod_MessageShown(text, opts)` runs for each line that is really shown.

```lua
GryMod.API.ShowMessage(ply, "Door unlocked", {lane = "status", duration = 3}) -- server
```

## Pickup icons

The popup that shows when the player takes ammo, a weapon or an item has an icon, which is a frame of the movie `HUD_AmmoPickup`. The registry says which frame a pickup gets. Stock Half-Life 2 entries are registered when the file loads, with these same calls: ammo `Pistol`, `SMG1`, `AR2`, `357`, `Buckshot`, `XBowBolt`, `RPG_Round`, `SMG1_Grenade`, `Grenade` and `AR2AltFire`, and the weapons `weapon_pistol`, `weapon_smg1`, `weapon_ar2`, `weapon_357`, `weapon_shotgun`, `weapon_crossbow`, `weapon_rpg`, `weapon_frag` and `weapon_slam`. The behaviour of the popup is in [api.md](../api.md#pickups). `GryMod.API.Has("pickups")` is true on the client.

### GryMod.API.RegisterPickupIcon(kind, name, icon)

Client. Gives a pickup its icon.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `kind` | string | `"ammo"` (the ammo type), `"weapon"` (the class of the weapon) or `"item"` (the class of the item). | no |
| `name` | string | The ammo type or the class, 1 to 64 characters. The comparison ignores case. | no |
| `icon` | string | A frame of the movie, case sensitive: `Riffle`, `socom`, `shootgun`, `missle`, `rocket`, `FY71`, `Hurricane`, `LAW`, `TACGun`, `GaussRifle`, `DSG1`, `MOAR`, `MOAC`, `Flashbang`, `SmokeGrenade`, `Sleep`, `AVMine` or `New`. | no |

Returns `true`, or `false` and a reason: `"invalid kind"`, `"invalid name"`, `"invalid icon"`. Registering the same kind and name again replaces the icon. `New` is accepted and is the frame that has no picture, so the popup shows the count and the name only.

### GryMod.API.UnregisterPickupIcon(kind, name)

Client. Removes the icon of a pickup.

Returns `true` when an entry was removed. Returns `false` for an invalid kind, a name that is not a string, or an entry that does not exist.

### GryMod.API.GetPickupIcon(kind, name)

Client. Returns the icon a pickup gets.

Returns the frame name as a string. It never returns `nil`: an unknown kind, a name that is not a string or a name with no entry gives `"New"`. The popup calls it with the ammo type name, the class of the weapon or the class of the item.

## Radar marker sources

A marker source is a function that the radar asks for markers once per frame it draws. The four functions below are stored in the table `GryMod.Radar` and are called as `GryMod.Radar.AddSource`, `GryMod.Radar.RemoveSource`, `GryMod.Radar.HasSource` and `GryMod.Radar.Sources`. `GryMod.API` has no function of these names; the headings carry the `GryMod.API` prefix so that they follow the naming of the rest of this reference. On the server `GryMod.Radar` is another table (the radar's rules), so call them on the client only. `GryMod.API.Has("radarmarkers")` is true on the client when they exist. The guide with the full marker table is [api.md](../api.md#radar-markers-client), and the same markers can go on the big map through `GryMod.Map.AddMarkerSource` ([minimap.md](../minimap.md)).

The player's setting `gry_hud_radarmarkers` (default 1) switches the markers off. While it is 0, or while no source exists, no source is asked. GryMod uses the keys `objectives` and `gry_pings` for its own sources.

A source returns an array of markers, or nothing. A marker is a table:

| Field | Type | Meaning | Default |
| --- | --- | --- | --- |
| `pos` | Vector | A point of the world. Required. | none |
| `type` | whole number, 1 to 7 | `1` to `4` the unit icons, `5` the objective arrow, `6` the explosion ring, `7` the team mate. Required. | none |
| `subtype` | number | The variant of the icon. The frame is `type * 5 + subtype`. For type 5 the values 0 and 1 are the primary arrow (green) and 2 and 3 the secondary one (yellow); the radar picks the border form itself. | 0 |
| `alpha` | number | 0 to 1, moved to the nearest bound outside. | 0.75 for type 5, 1 for types 6 and 7, 0.85 for the others |
| `scale` | number above 0 | Size in percent of the picture of the movie. | 75 for type 5, 100 for type 6, a team mate 4 times the size a unit icon would get; for the others a size that depends on the height difference with the player |
| `id` | any | Given back to the radar's own code. | the position of the marker in the list of all the markers collected in that frame |
| `yaw` | number | Degrees. The icon turns with it. Read for every type except 5. | none |

A marker with no valid `pos`, a `type` that is not a whole number from 1 to 7, or more than 500 m above or below the player is skipped. The radar draws 64 markers at most across all the sources, in the order of the sources. A type 5 marker beyond the range sticks to the border of the radar, a type 7 marker sticks to the circle of the range, and a marker of another type is not drawn once it leaves the radar's frame.

### GryMod.Radar.AddSource(key, fn)

Client. Adds a marker source, or replaces the one with the same key.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `key` | any value except `nil` and `nan` | The name of the source. A string is the usual choice. | no |
| `fn` | function | `fn()` takes no argument and returns an array of markers. | no |

Returns `true`, or `false` and a reason: `"invalid key"`, `"the source must be a function"`. Call it as `GryMod.Radar.AddSource(key, fn)`. A second call with the same key replaces the function, keeps the place of the source in the order and clears its error count.

The radar runs each source under `pcall`. A source that raises is skipped for that frame. After 3 errors in a row (`Radar.SOURCE_MAX_ERRORS`) the radar removes it and prints one line in the console. An answer without an error starts the count again. A source may add or remove sources, itself included, while it runs.

```lua
GryMod.Radar.AddSource("my_addon", function()
	return {{pos = Vector(0, 0, 64), type = 5, subtype = 0, id = "treasure"}}
end)
```

### GryMod.Radar.RemoveSource(key)

Client. Removes a marker source. Called as `GryMod.Radar.RemoveSource(key)`.

Returns `true` when the key was a source, `false` otherwise.

### GryMod.Radar.HasSource(key)

Client. Tells whether a key is a marker source. Called as `GryMod.Radar.HasSource(key)`.

Returns `true` or `false`.

### GryMod.Radar.Sources()

Client. Lists the keys of the marker sources, in the order their markers are collected. Called as `GryMod.Radar.Sources()`.

Returns a new array. A change to it does not change the registry.

## Debug commands

The effects test window has a section "Real, on me (administrators only)". Each button of that section is an entry of the registry below. GryMod registers its own entries when the file loads: `suit_off`, `suit_on`, `malfunction`, `emp_self`, `energy_empty`, `energy_full`, `mode_armor`, `mode_speed`, `mode_strength` and `mode_cloak`, and `objectives_demo`. The window is described in [events.md](../events.md#the-debug-window).

Two network messages carry the traffic: `gry_debug_list` (the window asks for the list when it opens, the server answers with the ids and the labels) and `gry_debug_cmd` (the client sends the id of the entry that was clicked). The server decides each time. The sender must be a valid player for whom `GryMod.MayConfigure` is true, which means an administrator (`Player:IsAdmin`). Any other sender gets an empty list, and no command runs for it. A sender may send one message of each kind every 0.2 s. A message that comes too early is dropped and does not restart the clock. The id must be in the registry. The command runs on the sender only, never on another player. The list sent holds 255 entries at most.

### GryMod.API.RegisterDebugCommand(id, def)

Server. Adds a button to the administrators' section of the effects test window.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | Letters, digits and underscore, 1 to 32 characters. | no |
| `def` | table | `label` and `run`, below. Other fields are ignored. | no |

| Field of `def` | Type | Meaning |
| --- | --- | --- |
| `label` | string, 1 to 48 characters | The text of the button. |
| `run` | function | `run(ply)`, where `ply` is the player who clicked. |

Returns `true`, or `false` and a reason: `"invalid id"`, `"invalid definition"`, `"invalid label"`, `"invalid function"`. Registering an id that exists replaces the entry, keeps its place in the list and arms it again if it was switched off. The window asks the server for the list each time it opens, so a new entry appears the next time the window is opened.

`run` is called under `GryMod.API.SafeCall` with the id `debugcmd:<id>`. An error is caught. The fifth error in a row switches the command off until it is registered again.

```lua
GryMod.API.RegisterDebugCommand("my_addon_shield", {
	label = "My addon: shield on me",
	run = function(ply) ply:SetArmor(100) end
})
```

### GryMod.API.UnregisterDebugCommand(id)

Server. Removes a command from the registry.

Returns `true` when the entry existed, `false` when it did not or when `id` is not a string. The entries GryMod registered itself can be removed too.
