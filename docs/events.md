# HUD events

A **HUD event** is a named effect of the interface: an animation, a sound, or both, played together by one call. GryMod runs on its own
events: when the armor takes a hit, when the suit changes mode, when the water closes over the player's head, GryMod itself calls
`GryMod.API.HUDEvent(name, data)`. There is no second code path that plays the picture here and the sound there. So whatever you can see
or hear from the suit, you can play from your addon with the same call, and the debug window lists the same events.

Everything here is **client side** (the HUD is drawn on the client). From the server you ask a client to play one (see below).

## The events

The "Options" column lists the settings of the player that cut the effect. An event follows them like the game does; a call made while an
option is off plays nothing for that half.

| Event | Data | What it plays (picture + sound) | GryMod plays it when | Options |
| --- | --- | --- | --- | --- |
| `boot` | | the start-up log of the HUD + the reboot sound | the player spawns (once, see `gry_boot_every_spawn`) | `gry_hud_boot`, `gry_sounds` |
| `lost` | | the emergency shutdown animation + the failure sound, until a `reboot` (the sound repeats while the suit is down) | the suit goes down (HUD status 1) | `gry_hud_boot`, `gry_sounds`, `gry_sound_malfunction_loop` |
| `reboot` | | the reboot sequence (silent, as in the original) | the suit comes back | `gry_hud_boot` |
| `malfunction` | `seconds` (5; 0.1 to 60) | shutdown, then reboot after `seconds`, with the failure sound (repeated until the reboot) | never by itself: API and debug window | `gry_hud_boot`, `gry_sounds`, `gry_sound_malfunction_loop` |
| `armor_hit` | `visual` (false: sound only), `sound` (false: picture only), `small` (true: the small look of a light hit) | the flash, the shake and the jump of the HUD + one file of the impact sound (shuffled, rate limited); with `small`, only a short shake (0.35 s) | the server says a bullet hit the armor (sound), and the bar loses 20 energy or more (picture), or from 1 to under 20 (the small shake) | `gry_screenfx`, `gry_hud_damagefx`, `gry_hit_shake`, `gry_sounds` |
| `decloak` | | the glitch of leaving the camouflage (and the emptied bar is not read as a hit) | the player fires out of the camouflage | `gry_decloak_glitch`, `gry_screenfx`, `gry_hud_damagefx` |
| `low_health` | `level` (1: under 25 %, 2: under 20 %) | the red tint and the blur, a shake at level 2 | the health falls through a low zone | `gry_screenfx` |
| `jam` | `seconds` (2; 0.1 to 60) | the interface trembles (12 px), then settles | never by itself | `gry_hud_damagefx` |
| `radar_exposure` | `level` (100; 0 to 100), `seconds` (3; 0.1 to 60) | the hexagon of the radar shows at least `level` for `seconds` (no sound: the original has none), then goes back to what the vehicles say | never by itself: the radar's contacts drive the hexagon (see below), this is for addons and the debug window | `gry_hud_radarhex`, `gry_hud_radar` |
| `mode` | `mode` (`"armor"`, `"speed"`, `"strength"`, `"cloak"` or the number), `tint` (false), `sound` (false) | the colour tint of the mode (none for the camouflage) + its activation sound + its voice half a second later | the suit changes mode (the camouflage also plays its own loop while it lasts, `gry_sound_cloak_loop`, and lowers your own footsteps and the suit's own sounds to 70 % over one second, `gry_cloak_foley_quiet`; other players' steps and the world's ambience are not changed) | `gry_screenfx`, `gry_sounds`, `gry_cloak_foley_quiet` |
| `energy_critical` | | the "energy critical" voice | the energy falls under 25 % (at most every 30 s) | `gry_sounds` |
| `regen_start`, `regen_stop` | | the repair sound from its start / its fade out (1 s) | the server starts / stops the health regeneration | `gry_sound_regen`, `gry_sounds` |
| `dive_in` | `fall` (the fall speed, 0) | the splash, slow or fast | the head goes under water | `gry_underwater_fx`, `gry_sounds` |
| `dive_out` | | the sound of coming out | the head comes out | `gry_underwater_fx`, `gry_sounds` |
| `drown` | | a gasp | the server's drowning tick | `gry_underwater_fx`, `gry_sounds` |
| `reset` | | the interface starts again from its start state (rebuilt, the energy bar on the real value, the damage effects forgotten, a hidden HUD brought back) | never by itself | |
| `disabled` | | the HUD plays the shutdown (2.5 s) with its sound, then stays hidden | the suit flag of the server changes to off (`GryMod.API.SetSuitEnabled(ply, false)`) | `gry_hud`, `gry_hud_boot`, `gry_sounds` |
| `enabled` | | the HUD comes back with the reboot sequence | the suit flag changes to on | `gry_hud`, `gry_hud_boot` |
| `objective` | `kind` (`"added"`, `"completed"` or `"failed"`), `title` (the objective's title) | the top line `NEW OBJECTIVE: <title>` (or `OBJECTIVE COMPLETED:` / `OBJECTIVE FAILED:`) and its sound, together: `pda_update` for added and failed, `objective_completed` for completed | an objective is added, finished or failed (the list sent when the player joins is silent; see "Objective banner") | `gry_msg_objectives`, `gry_hud_messages`, `gry_hud`, `gry_sounds` |
| `message` | `text` (128 characters at most), `lane` (`"top"`, `"middle"`, `"status"`, `"crosshair"` or 1 to 4; `"top"`), `sound` (a sound path), `duration` (seconds, 0.5 to 60; 5), or `line` (a key of the suit's own lines, see "Text lines") | a line of text on the HUD, in the movie's own stack, and its sound together | the suit's own lines (see "Text lines"); never by itself otherwise | `gry_hud_messages`, `gry_hud`, `gry_sounds` |
| `use_feedback` | | the use prompt's icon pulses for a quarter of a second and a beep plays (the quick menu's navigation beep) | the use key pressed on a prompt of a repeatable use (a door, a button, a charger: `use = "repeat"` in the registry of usable entities); once per press for a `hold` use (charger, wheel), not at each repeat of the bind | `gry_usehint_feedback`, `gry_hud_usehint`, `gry_sounds` |
| `night_vision` | `on` (true or false), `reason` (optional, see `GryMod_NightVision` in docs/api.md) | the sounds of the night vision (switch on, then its loop; the loop stops and the switch-off sound plays) and the hook `GryMod_NightVision`; the energy bar of the HUD and the screen effect follow the same state. Played from outside (an addon, the server, the debug window) it asks for the same switch under the same rules and plays nothing when the switch is refused | the player's key (N by default), the energy running out, the suit going down or off, death | `gry_nightvision`, `gry_sounds` |
| `map_open`, `map_close` | | the big map opens (its window, the first picture and the opening sound) / closes (the closing sound) | the player's key (M by default) or `GryMod.Map.Open()` / `Close()` | `gry_map_enable`, `gry_sounds` |

Not events, because they run on every frame: the sprint sounds and the binoculars loop. The binoculars cues and the quick menu sounds are
not events yet.

## The radar's hexagon

At the bottom left of the radar there is a hexagon with a warning sign in it, as in the original game. It follows the **vehicles and machines** (the radar's
contacts of icon type 2, flying, and 3, machines: cars, helicopters, gunships, striders, turrets...) that have noticed the player, while the danger bar beside
the compass follows the soldiers only (types 1 and 4). The sign is small and green at rest, turns amber (about half), grows and turns red, then pulses red
when a vehicle fights you. It rises quickly and falls in two steps, as the original's AI does: fast at first, then a slow memory (the longest is a minute).
`gry_hud_radarhex 0` turns it off, and the danger bar then follows every hostile as before.

Listen to its level (0 to 100, the number of the picture) with a hook; it fires when the number changes, not at every frame:

```lua
hook.Add("GryMod_RadarExposure", "my_addon", function(level, previous)
	if level >= 95 and previous < 95 then -- the pulsing red begins
	end
end)
```

Force it from your addon, for a drone's radar or a scripted alarm. The hexagon shows at least `level` for `seconds`, whatever the vehicles do:

```lua
GryMod.API.HUDEvent("radar_exposure", {level = 70, seconds = 5}) -- grown and red for 5 s
```

## Hooks of the client

Besides `GryMod_HUDEvent` (above) and `GryMod_RadarExposure`, the client runs these hooks. They only say that something happened: nothing
reads what a listener returns. The malfunction, `GryMod_InOutMapReady` and `GryMod_InOutMapState` hooks are run inside a `pcall`: a listener
that fails is shown once in the console and stops nothing. `GryMod_HUDStatus`, `GryMod_BinocularsToggled` and `GryMod_SuitZoom` are run with a
plain `hook.Run`: an error in your listener there reaches GryMod's own code, so keep those listeners safe.

### `GryMod_HUDStatus(status, why)`

The state of the HUD changed. `why` is a text, and only given for the changes that do not come from the suit itself: `"death"` (the player died, `status` 1:
the red HUD of the death), `"respawn"` (the life is back, `status` 0) and `"gone"` (`status` 0: the HUD is dropped and will not be shown, because the suit is
off, the HUD is switched off, or the player died with no red HUD; what was told as down is over, so a listener never keeps a malfunction look for good). `"gone"`
is not a reboot: GryMod plays no reboot sequence for it. `status` is a number: `0` the suit works, `1` malfunction (the server says the suit is down; with
`gry_malfunction_empty 1` an empty energy bar counts too), `2` flicker (a light shock). It is run once at each change of that number, from the
frame code of the HUD, so only while the HUD is drawn (see "What depends on the drawn HUD"). GryMod's own `lost` and `reboot` events, and the
close of the binoculars' zoom, are driven by it. A HUD that is built again (a respawn, a new theme) starts at `0` and does not report it: a
suit that is down at that moment gives `1` at once, and the end of a malfunction that came while no HUD was drawn gives nothing. It has no
"previous" argument; keep the last value yourself. For the state of the suit itself, use `GryMod_MalfunctionStart` and `GryMod_MalfunctionEnd`.

### `GryMod_MapOpened()`, `GryMod_MapClosed()`, `GryMod_MapZoomed(zoom)`

The big map (see `docs/minimap.md`) opened, closed, or changed its zoom (`zoom`, from 1 up to the closest zoom of the map, 8 at least, after a wheel notch or a middle-button drag; not at opening). Run inside a
`pcall`: a listener that fails is shown once in the console and stops nothing.

```lua
hook.Add("GryMod_MapOpened", "my_addon", function() print("the big map is open") end)
hook.Add("GryMod_MapZoomed", "my_addon", function(zoom) print(("zoom x%.1f"):format(zoom)) end)
```

### `GryMod_MalfunctionStart(ply)`, `GryMod_MalfunctionEnd(ply)`

The suit of a player went down, or came back. They have the names of the server hooks (`docs/api.md`), but the client only sees the networked
flag change, so it gives the player and nothing else: no duration, no cause. They are run for **every player** the client knows, not only the
local one, and they do not need the HUD. A report is made when the flag really changes from false to true (start) or from true to false (end).
Not reported: what the client learns when a player comes into view, or when you join (a suit that is already down gives no start), and a
suit that stays down longer. The end is also reported when the server clears the flag at a death, a respawn or a disconnect, where the server
hook `GryMod_MalfunctionEnd` is not run. A listener that fails is shown once in the console and does not stop the game's other hooks.

### `GryMod_MessageShown(text, opts)`

A text line was put on the HUD (the event `message`, below). `text` is the cleaned text; `opts` is a new table `{lane, sound, duration, line}`
(`lane` is always a name, the others are `nil` when not given; `line` is the key of the suit's own line, if it was one). It is run once for
each line that is really shown, after it is on the HUD and its sound has started: a line that is not shown, because the player turned the text
lines off (`gry_hud_messages`), the HUD is off or the movie is missing, is not reported and plays no sound. A listener that fails is shown in the
console and does not break GryMod (the listeners after it are not run).

### `GryMod_UsableChanged(ent, mode, ply)`

What the player aims at and can use or take changed. It is the test that opens the crosshair's "usable" state, looked at ten times a second,
and the hook is run once at each change, not at each look. The use prompt (and so this hook) only comes after the crosshair stayed `gry_usehint_delay` seconds (0.1 by default, 0 for at once) on the same thing, and goes `gry_usehint_hold` seconds (0.2 by default, 0 for at once) after the crosshair leaves it, or at once when another usable thing is aimed; the crosshair's own usable state is not delayed. `ent` is the entity (`nil` when there is none), `mode` is `1` (it can be used or
taken) or `0` (nothing; `2`, "it can not", is not used any more: what is taken by walking over it is no usable thing). It is run while the crosshair is drawn, so not when the crosshair is off
or the player is dead. The use prompt hangs on it. A listener that fails is shown in the console and does not break GryMod (the listeners after it are not run).

### `GryMod_BinocularsToggled(wanted)`

The player puts the binoculars up (`wanted` is `true`) or down (`false`). "Wanted" is: the player is alive and either holds the game's zoom
key (`IN_ZOOM`) or has GryMod's own zoom open (`GryMod_SuitZoom` below). It is run once at each change of that answer, and only looked at
when one of those two says something (the own zoom's hook, the key press or release of `IN_ZOOM`), not at every frame. It says what the
player asks for, not what is on the screen: it does not look at `gry_hud` or `gry_hud_binoculars`, so a player who holds the game's zoom key
with the HUD off still gives it. A player who dies while holding the game's zoom key and lets go of it while dead leaves the last answer stale
until the next key event or own zoom event. Nothing is reported when the file loads.

### `GryMod_SuitZoom(active, reason)`

The **own zoom** of the binoculars (option `gry_zoom_own`, its own key) opened or closed. It is not the game's zoom key: that one never
runs this hook (use `GryMod_BinocularsToggled` for both). On open: `GryMod_SuitZoom(true)`, no second argument, only when a zoom really
opens (nothing in the world prevents it). On close: `GryMod_SuitZoom(false, reason)`, once, only when a zoom was open. `reason` is one of:

- soft, the binoculars close as usual in 0.2 s: `"release"` (the key let go), `"toggle"` (a second press), `"weapon"` (the weapon changed),
  `"weaponkey"` (a weapon key was pressed), `"water"`;
- hard, the binoculars are put away at once: `"init"`, `"death"`, `"disabled"` (the option `gry_zoom_own`, the HUD, the binoculars or the suit is off), `"quickmenu"`,
  `"pause"`, `"console"`, `"ui"` (a cursor or a panel has the focus), `"chat"`, `"focus"` (the game lost the focus), `"malfunction"`,
  `"vehicle"`, `"thirdperson"`, `"viewentity"`, `"observer"`, `"frozen"`, `"viewtaken"` (another addon took the view), `"shutdown"`,
  `"spawnmenu"`, `"contextmenu"`.

A reset of the module (a reload of the file) is silent: no hook.

### `GryMod_InOutMapReady(boxCount)`

The client received a complete file of the in/out map of the level, decoded it and indexed it without error. `boxCount` is the number of
boxes of the map (a number). It is run each time a file is accepted, so it can come more than once for a level (the server sends the file again
when the map is made again, and when a client asks). It is also run for a map flagged incomplete (state 5 below). Not run when the file is
refused. It does not say that a map went away: for that, watch `GryMod_InOutMapState`. A listener that fails is shown once in the console and
does not stop the receiver.

### `GryMod_InOutMapState(state, done, total)`

The server told the client the state of its work on the in/out map. `state` is a whole number: `0` off, `1` no graph, `2` waiting, `3`
computing, `4` ready, `5` incomplete (made, but not from every point), `6` failed (the reason is in the server log). `done` and `total` count
the points the server has sampled and the points there are (while computing; at `4` and `5` they are equal). It is run for every valid message, so also for a repeat of the same state (the server repeats it when a client asks; while computing
it sends at most four a second). With a state under `4`, or `6`, the map the client held is dropped before the hook is run. At `4` and `5`
the message comes first and the file after it: `GryMod_InOutMapReady` follows. A message with a state outside 0 to 6 is ignored, no hook.
A listener that fails is shown once in the console and does not stop the receiver.

### `GryMod_ObjectiveAdded(id, obj)`, `GryMod_ObjectiveChanged(id, obj, oldState)`, `GryMod_ObjectiveRemoved(id, obj, reason)`

An objective (docs/api.md, "Objectives") arrived on this client, changed, or went away. The server runs the same three hooks with the same
arguments, so one listener file serves both realms. On a client they follow the messages of the server, for the objectives this player may
see: `Added` when it arrives (also for each objective when the player joins), `Changed` when its state, title, description, primary flag or main
objective status changed (`oldState` is the state before; a new position is not a change), `Removed` with a `reason` (`"removed"`, `"cleared"`,
`"entity_removed"`, `"map_changed"`). `obj` is a copy: `{id, title, description, primary, main, state, pos, ent, radar, marker}`. They are run inside
a `pcall`: a listener that fails is shown on the console (five times at most per hook) and stops nothing. Nothing reads what a listener returns.

### `GryMod_WeaponHeat(ply, wep, percent)`

Client. Runs each time the weapon heat bar moves: `percent` is 0 to 100, and 0 when the bar is hidden (a weapon that declares no `heat`
in the weapon registry, another weapon in hand, or the player turned the bar off). Run inside a `pcall`.

### `GryMod_WeaponListShown(ply, wep)`

Client. Runs each time the weapon list is shown: the player changed the weapon in hand (`wep`) and the list of the player's weapons (at the
bottom right, up to five rows, the weapon in hand on a plate) appears for three seconds. It is not run when the list is off (`gry_hud_weaponlist`,
the HUD, the suit) or when the HUD was just made (nothing changed). Run inside a `pcall`; the return value is ignored.

## What depends on the drawn HUD

GryMod's HUD is drawn by one `HUDPaint` hook (`Module.Paint` of `cl_hud_flash.lua`). `Module.Apply` removes it when `gry_hud` is 0 or when
the HUD movie is missing; while it is there, `Module.Paint` stops at the start (and forgets the HUD) when the player is dead or when the suit
is off (the suit flag of the server, or an event `disabled` that has not been followed by `enabled`). Several reports are made from the frame
code that this hook runs, so in those cases they are not made:

- `GryMod_HUDStatus`, and so the events `lost` and `reboot` that GryMod plays from it;
- the event `low_health`, and the picture half of `armor_hit` (the sound half comes from a message of the server and does not need the HUD);
- `GryMod_RadarExposure` (the meter of the hexagon is fed by the radar's frame code, `Radar.Feed`).
- the event `message` and `GryMod_MessageShown`: a line is shown only while the HUD is on (and the suit with it); the event still runs, it shows nothing and plays no sound.
- `GryMod_WeaponListShown` (the list is drawn by the HUD's own frame code).

These do **not** depend on the HUD being drawn: the events `mode`, `decloak`, `energy_critical`, `regen_start`, `regen_stop`, `dive_in`,
`dive_out`, `drown`, `enabled` and `disabled`, the sound half of `armor_hit`, the hooks `GryMod_MalfunctionStart` and `GryMod_MalfunctionEnd`, and
`GryMod_BinocularsToggled`. (`GryMod_SuitZoom` is another case: the own zoom only opens while the HUD and the binoculars are on, and closes with the reason `"disabled"` if they go off.) If your addon needs to know
that the suit is down whatever the HUD does, use the malfunction hooks, not `GryMod_HUDStatus`.

## Play an event

On the client:

```lua
GryMod.API.HUDEvent("jam", {seconds = 3})          -- true when the handler ran, false and a reason otherwise
GryMod.API.HUDEvent("mode", {mode = "speed"})
GryMod.API.HUDEvent("armor_hit", {sound = false})  -- the picture without the sound
```

From the server, to one player or a list of players:

```lua
GryMod.API.HUDEvent(ply, "malfunction", {seconds = 3})
GryMod.API.HUDEvent(player.GetAll(), "reset")
```

The data is `nil` or a small table: at most 8 fields, names of letters, digits and underscore (24 characters at most), values that are
finite numbers, strings (128 characters at most) or booleans. The event name has 32 characters at most. A call that breaks these limits
returns `false` and a reason, and sends nothing.

Listen to what plays (the hook fires after a handler ran without error):

```lua
hook.Add("GryMod_HUDEvent", "my_addon", function(name, data)
	if name == "armor_hit" then -- e.g. flash my own lamp
	end
end)
```

## Text lines

The event `message` writes a line of text on the HUD, in the stack of lines of the original game: a new line enters at the bottom and pushes the
older ones along, seven at most in a lane, each stays five seconds and fades out. It is one event: the text and its sound come together, and
the players' settings cut both.

On the client:

```lua
GryMod.API.ShowMessage("OBJECTIVE ACTIVATED")                                  -- the top lane
GryMod.API.ShowMessage("Door unlocked", {lane = "status", duration = 3, sound = "buttons/button17.wav"})
```

From the server, to one player or a list of players (the same call with the players in front; it returns what `GryMod.API.HUDEvent` returns):

```lua
GryMod.API.ShowMessage(ply, "Reinforcements are coming", {lane = "middle"})
GryMod.API.ShowMessage(player.GetAll(), "Round over")
```

The options are `lane`, `sound` (a sound path, played with the line through GryMod's mix) and `duration` (the whole life of the line, in
seconds). The lanes are the four of the movie, with the number the original gives each: `"top"` (1, the banner of the objectives), `"middle"`
(2, the upper middle), `"status"` (3, just under the centre, where the suit's own lines go) and `"crosshair"` (4, above the crosshair). The top
lane and the status lane stack up to seven lines; the other two show one line at a time. The text is 128 characters at most (a longer one is
refused, not cut), one line, no control characters. A call that breaks these limits returns `false` and a reason and shows nothing.

The suit's own lines are shown by the same event, `{line = key}`, each with a setting of the player that turns it off:

| `line` | Text | Shown when | Setting |
| --- | --- | --- | --- |
| `cloak_disabled` | `Temperature Camo: Disabled!` | the camouflage ran out of energy and the suit went back to armor | `gry_msg_cloak_disabled` |
| `cloak_health` | `Temperature Camo: Health too low!` | the camouflage was refused because the health is too low: the server setting `gry_cloak_min_health` (the original game's rule uses 24; it is `0`, no rule, by default) | `gry_msg_cloak_health` |
| `killed_friend` | `YOU KILLED A FRIENDLY!` | the player killed an ally (`GryMod.API.Relation` says so: a player of his team, an NPC that likes him). Nothing is punished | `gry_msg_killed_friend` |

Listen to what is shown with `GryMod_MessageShown(text, opts)` (above). `GryMod.API.Has("messages")` is true when this exists.

## Objective banner

The event `objective` is how the HUD tells the player that an objective (docs/api.md, "Objectives") arrived, was finished or failed. GryMod plays it
by itself from `GryMod_ObjectiveAdded` and `GryMod_ObjectiveChanged`, once for each real change of the state (a new title, the main flag or a new
position say nothing), and never for the list the player gets when he joins (`GryMod.Objectives.Syncing()` is true then). It builds the line
`<NEW OBJECTIVE | OBJECTIVE COMPLETED | OBJECTIVE FAILED>: <title>` (a long title is cut with `...` so that the line stays at 128 characters), shows it
on the top lane of the text lines above, and plays its sound with it. The player's setting `gry_msg_objectives` cuts both. You can play it yourself:

```lua
GryMod.API.HUDEvent("objective", {kind = "completed", title = "Find the key"})
```

## Add your own event

Register a handler on the client. The third argument describes the event for tools such as the debug window; it is optional.

```lua
GryMod.API.RegisterHUDEvent("my_flash", function(data)
	-- play the picture AND the sound here, in one place
	GryMod.PlaySound("buttons/button17.wav")          -- through GryMod's mix (its level, its limits, gry_sounds)
	util.ScreenShake(LocalPlayer():GetPos(), 2, 20, 0.4, 64)
end, {
	label = "My flash",                               -- the text of the button (default: the name)
	variants = {                                      -- several buttons for one event
		{label = "My flash, weak", data = {power = 1}},
		{label = "My flash, strong", data = {power = 3}}
	},
	follows = {                                       -- the options of the player that cut it: {convar, what it cuts}
		{"gry_sounds", "the suit sounds"},
		{"gry_screenfx", "the screen effects"}
	}
})

GryMod.API.UnregisterHUDEvent("my_flash")
GryMod.API.ListHUDEvents()                            -- sorted names
GryMod.API.GetHUDEventInfo("my_flash")                -- a copy of {label, variants, follows}, or nil
```

Rules for a handler: it receives `data` as a table (empty when there is none), it plays everything the event is (picture and sound), and
it respects the player's options. An error in a handler never reaches the caller; five errors in a row switch the handler off until it is
registered again. A malformed `info` is ignored piece by piece, never an error.

If an event of GryMod should play when something happens in your game, call it; do not play its sound yourself.

## The debug window

At the bottom of the GryMod configuration panel, **Open the effects test window** opens a popup, apart from the panel. It has no list of
its own:

- **Effects on this screen**: one button per event of `ListHUDEvents()` (one per variant when it has some), played on this client only, with
  the slider's seconds as `data.seconds`. An event you register appears at the next opening. The tooltip says which option of the player
  is off and would cut the effect; the button still plays.
- **Real, on me (administrators only)**: the commands the server registered. The window asks the server for the list every time it opens;
  a player who is not an admin gets an empty list. A command applies to the player who clicks, never to another one.

Add a command to that section (server side):

```lua
GryMod.API.RegisterDebugCommand("my_addon_shield", {
	label = "My addon: shield on me",     -- 48 characters at most
	run = function(ply) ply:SetArmor(100) end
})

GryMod.API.UnregisterDebugCommand("my_addon_shield")
```

The id is letters, digits and underscore (32 at most). The server decides again at every click: the sender must be an admin, one command per
0.2 s per player, and the id must be in the registry. A command that raises an error is caught; five errors in a row switch it off until it
is registered again.

## Test an event

Call it from the console of the game with a Lua command, or write a test in the format of `tests/` (see `tests/cl_api_hud_events_test.lua`):
replace the functions your handler calls (the sound, the shake) by recorders inside a `pcall`, put them back afterwards, and check that
one `GryMod.API.HUDEvent` call reaches both the picture and the sound.
