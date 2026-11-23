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
| `lost` | | the emergency shutdown animation + the failure sound, until a `reboot` | the suit goes down (HUD status 1) | `gry_hud_boot`, `gry_sounds` |
| `reboot` | | the reboot sequence (silent, as in the original) | the suit comes back | `gry_hud_boot` |
| `malfunction` | `seconds` (5; 0.1 to 60) | shutdown, then reboot after `seconds`, with the failure sound | never by itself: API and debug window | `gry_hud_boot`, `gry_sounds` |
| `armor_hit` | `visual` (false: sound only), `sound` (false: picture only) | the flash, the shake and the jump of the HUD + one file of the impact sound (shuffled, rate limited) | the server says a bullet hit the armor (sound), and the bar loses 20 energy or more (picture) | `gry_screenfx`, `gry_hud_damagefx`, `gry_sounds` |
| `decloak` | | the glitch of leaving the camouflage (and the emptied bar is not read as a hit) | the player fires out of the camouflage | `gry_decloak_glitch`, `gry_screenfx`, `gry_hud_damagefx` |
| `low_health` | `level` (1: under 25 %, 2: under 20 %) | the red tint and the blur, a shake at level 2 | the health falls through a low zone | `gry_screenfx` |
| `jam` | `seconds` (2; 0.1 to 60) | the interface trembles (12 px), then settles | never by itself | `gry_hud_damagefx` |
| `radar_exposure` | `level` (100; 0 to 100), `seconds` (3; 0.1 to 60) | the hexagon of the radar shows at least `level` for `seconds` (no sound: the original has none), then goes back to what the vehicles say | never by itself: the radar's contacts drive the hexagon (see below), this is for addons and the debug window | `gry_hud_radarhex`, `gry_hud_radar` |
| `mode` | `mode` (`"armor"`, `"speed"`, `"strength"`, `"cloak"` or the number), `tint` (false), `sound` (false) | the colour tint of the mode (none for the camouflage) + its activation sound + its voice half a second later | the suit changes mode | `gry_screenfx`, `gry_sounds` |
| `energy_critical` | | the "energy critical" voice | the energy falls under 25 % (at most every 30 s) | `gry_sounds` |
| `regen_start`, `regen_stop` | | the repair sound from its start / its fade out (1 s) | the server starts / stops the health regeneration | `gry_sound_regen`, `gry_sounds` |
| `dive_in` | `fall` (the fall speed, 0) | the splash, slow or fast | the head goes under water | `gry_underwater_fx`, `gry_sounds` |
| `dive_out` | | the sound of coming out | the head comes out | `gry_underwater_fx`, `gry_sounds` |
| `drown` | | a gasp | the server's drowning tick | `gry_underwater_fx`, `gry_sounds` |
| `reset` | | the interface starts again from its start state (rebuilt, the energy bar on the real value, the damage effects forgotten, a hidden HUD brought back) | never by itself | |
| `disabled` | | the HUD plays the shutdown (2.5 s) with its sound, then stays hidden | the suit flag of the server changes to off (`GryMod.API.SetSuitEnabled(ply, false)`) | `gry_hud`, `gry_hud_boot`, `gry_sounds` |
| `enabled` | | the HUD comes back with the reboot sequence | the suit flag changes to on | `gry_hud`, `gry_hud_boot` |

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

### `GryMod_HUDStatus(status)`

The state of the HUD changed. `status` is a number: `0` the suit works, `1` malfunction (the server says the suit is down; with
`gry_malfunction_empty 1` an empty energy bar counts too), `2` flicker (a light shock). It is run once at each change of that number, from the
frame code of the HUD, so only while the HUD is drawn (see "What depends on the drawn HUD"). GryMod's own `lost` and `reboot` events, and the
close of the binoculars' zoom, are driven by it. A HUD that is built again (a respawn, a new theme) starts at `0` and does not report it: a
suit that is down at that moment gives `1` at once, and the end of a malfunction that came while no HUD was drawn gives nothing. It has no
"previous" argument; keep the last value yourself. For the state of the suit itself, use `GryMod_MalfunctionStart` and `GryMod_MalfunctionEnd`.

### `GryMod_MalfunctionStart(ply)`, `GryMod_MalfunctionEnd(ply)`

The suit of a player went down, or came back. They have the names of the server hooks (`docs/api.md`), but the client only sees the networked
flag change, so it gives the player and nothing else: no duration, no cause. They are run for **every player** the client knows, not only the
local one, and they do not need the HUD. A report is made when the flag really changes from false to true (start) or from true to false (end).
Not reported: what the client learns when a player comes into view, or when you join (a suit that is already down gives no start), and a
suit that stays down longer. The end is also reported when the server clears the flag at a death, a respawn or a disconnect, where the server
hook `GryMod_MalfunctionEnd` is not run. A listener that fails is shown once in the console and does not stop the game's other hooks.

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

## What depends on the drawn HUD

GryMod's HUD is drawn by one `HUDPaint` hook (`Module.Paint` of `cl_hud_flash.lua`). `Module.Apply` removes it when `gry_hud` is 0 or when
the HUD movie is missing; while it is there, `Module.Paint` stops at the start (and forgets the HUD) when the player is dead or when the suit
is off (the suit flag of the server, or an event `disabled` that has not been followed by `enabled`). Several reports are made from the frame
code that this hook runs, so in those cases they are not made:

- `GryMod_HUDStatus`, and so the events `lost` and `reboot` that GryMod plays from it;
- the event `low_health`, and the picture half of `armor_hit` (the sound half comes from a message of the server and does not need the HUD);
- `GryMod_RadarExposure` (the meter of the hexagon is fed by the radar's frame code, `Radar.Feed`).

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
