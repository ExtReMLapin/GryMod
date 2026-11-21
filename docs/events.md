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
