# GryMod extension API

One table, `GryMod.API`, for the addons that plug into the nanosuit and the HUD. Everything below exists in version 1 of the
interface unless it says otherwise. Guides with examples: [entities.md](entities.md) (tracked entities, relation), [weapons.md](weapons.md)
(weapon registry); the index is [README.md](README.md).

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
  `"safecall"`, `"attackreport"`, `"weapons"`, `"weaponparts"` (client), `"weaponmenu"` (client), `"tracked"`, `"objectives"`, `"messages"`, `"campaign"`, `"usable"`, `"pickups"` (client), `"radarmarkers"` (client), `"weaponlist"` (client). New parts add a name here and never change the version number.
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
GryMod.API.ReportAttack(ply, true)   -- an attack that is not a bullet (a swing, a thrown grenade...): ends the camouflage, see below
```

An energy command counts as a use of the energy: the recharge starts again after its usual delay.

`SetMode` returns `false` and a reason when it does not change the mode: `"invalid mode"`, `"dead"`, `"malfunction"` (the suit is
down, so it stays in armor), `"disabled"` (the suit is off, see below) or `"vetoed"`.

### Attacks that end the camouflage

The camouflage ends when the player attacks. The server already sees every **bullet** (the hook `EntityFireBullets`): a weapon that fires bullets needs nothing, whatever
its rules. What it cannot see is an attack that is not a bullet: a knife's swing, a grenade thrown or launched, a beam. A weapon that knows it just made one tells GryMod:

```lua
-- server, in the weapon's attack code, or from a hook of its base
GryMod.API.ReportAttack(ply, true)    -- true: it came from the right click (the player may have turned that rule off: gry_cloak_altfire)
GryMod.API.ReportAttack(ply, false)   -- any other attack
```

It returns `true` when the player was camouflaged (his client ends the camouflage), or `false` and why (`"invalid player"`, `"not camouflaged"`); nothing is raised,
whatever you give it. `GryMod.API.Has("attackreport")` tells whether it exists. Weapons that are not yours: GryMod ships patches for some weapon bases (TFA, see
[compat.md](compat.md)).

### The suit on or off

```lua
GryMod.API.SetSuitEnabled(ply, false)   -- for a game where the suit is not on the player yet
GryMod.API.IsSuitEnabled(ply)
```

Off means: armor mode and no mode change, the armor takes no hit (the whole damage goes through), the energy neither drains nor
recharges, the suit cannot go down in a malfunction, and the HUD is hidden on that player's screen. It is a flag
(`GryDisabled`, a networked boolean), not a malfunction. It stays through death and respawn until you set `true`.

## Suit events (hooks)

| Hook | When |
| --- | --- |
| `GryMod_ModeChanged(ply, mode, oldMode, reason)` | the mode really changed (any path: the player's menu, the API, a malfunction), and at every respawn (even armor to armor). On the **server** and on the **client**, same name and same arguments (the client runs it only for the local player). `reason` is one of `GryMod.ModeReasons` (see below) |
| `GryMod_EnergyEmpty(ply)` | the bar reached 0 (once, not again until it has been above 0) |
| `GryMod_EnergyUsed(ply)` | energy was used (the new name of `GryUseEnergy`, which keeps firing too) |
| `GryMod_SuitEnabled(ply)`, `GryMod_SuitDisabled(ply)` | `SetSuitEnabled` changed the state |
| `GryMod_MalfunctionStart(ply, seconds, reason)`, `GryMod_MalfunctionEnd(ply)` | the suit went down, came back. The client has the same two hooks with only `(ply)`, for every player (see `docs/events.md`) |
| `GryMod_EMP(pos, radius, seconds)` | you can run this hook yourself to fire an EMP (same as `API.EMP`) |
| `GryMod_StrengthJump(ply)` | a strength jump was granted on the ground (once per key press). It is paid in energy, or free with the infinite armor. Not fired for the weak jump you get when the bar is too low |
| `GryMod_Zoom(ply, fov)` | the field of view the server zoom asks of the engine for the player, in degrees; `fov = 0` when the zoom is over |
| `GryMod_ArmorAbsorbed(ply, absorbed, passed)` | a hit was taken by the armor: `absorbed` points went to the armor, `passed` points went on to the health (`absorbed + passed` is the hit). Only when `absorbed > 0` |
| `GryMod_SprintStart(ply)`, `GryMod_SprintEnd(ply)` | the speed-mode sprint began, ended |
| `GryMod_SuitNoise(ply, pos, radius, kind)` | the suit made a noise that an AI could hear (see "Suit noises" below) |
| `GryMod_TargetSpotted(ply, ent, relation)` | the player's binoculars spotted `ent` (the scan ended on it and the radar shows it from now on). Once, the first time the entity is tagged for this player. `relation` is `"ally"`, `"neutral"` or `"hostile"` (the relation chain below) |

The other hooks of this table run on the server only. `GryMod_ModeChanged` also runs on the client, for the local player. The old hooks `GryNanosuitMode(ply, mode)` and `GryUseEnergy(ply)` still fire (on the server).

### Why the mode changed: `GryMod.ModeReasons`

The 4th argument of `GryMod_ModeChanged` is one of these plain strings, on the server and on the client:

| Constant | Value | Cause |
| --- | --- | --- |
| `GryMod.ModeReasons.SPAWN` | `"spawn"` | the player respawned: the suit always starts again in armor |
| `GryMod.ModeReasons.PLAYER` | `"player"` | the player asked for it (quick menu, key) |
| `GryMod.ModeReasons.API` | `"api"` | an addon called `GryMod.API.SetMode` |
| `GryMod.ModeReasons.ENERGY` | `"energy"` | the camouflage ran out of energy |
| `GryMod.ModeReasons.MALFUNCTION` | `"malfunction"` | the suit went down, or a mode was asked while it is down |
| `GryMod.ModeReasons.DISABLED` | `"disabled"` | the suit was switched off, or a mode was asked while it is off |
| `GryMod.ModeReasons.OTHER` | `"other"` | a caller of `Player:SetNanosuitMode` that gave no cause |
| `GryMod.ModeReasons.VETOED` | `"vetoed"` | the server refused a request (a veto, or something that is not a mode) and sends back the mode it really keeps |
| `GryMod.ModeReasons.SYNC` | `"sync"` | the server's answer when the client has finished loading: the client learns the real mode |

A respawn is always announced (`reason == SPAWN`), also from armor to armor (`mode == oldMode == GryMod.Modes.ARMOR`), also the first spawn of a new
player. When the mode was not armor, `oldMode` is the mode the player died in. For the other causes the hook runs only when the mode changes: the same
mode asked again, whoever asks, says nothing. At the respawn the energy is already back at 100 when the server's hook runs.

**Server and client.** The hook has the same name and the same arguments in both realms. The client runs it only for the local player (the only
one whose mode it knows), and it is told the cause by the server: on the network the cause is a small integer (`GryMod.ModeReasonIds`, the position in
`GryMod.ModeReasonList` minus 1, `GryMod.ModeReasonBits` = 4 bits), and it is a string again in the hook, so your handler reads the same value in both realms.
The mode the client sees is the new one when the hook runs. The "assumed" armor of a client that is still loading counts as the old mode.

When the **player** changes the mode himself (quick menu, key), the client applies it at once and the hook runs there with `PLAYER`; the server is only told
and runs its own hook with `PLAYER` too. If the server refuses (a veto, a malfunction, the suit switched off), it sends the real mode back and a **second**
hook runs on the client with `VETOED` (or `MALFUNCTION` / `DISABLED` when that is why), with `oldMode` the mode the client had set. Dropping the suit's
item is not a mode: no hook.

```lua
hook.Add("GryMod_ModeChanged", "my_addon", function(ply, mode, oldMode, reason)
	if reason == GryMod.ModeReasons.SPAWN then
		-- the suit was reset by the respawn: put my own look back
	end
end)
```

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

**The quick menu shows your veto.** To grey out a mode that is refused, the server tells each client which modes the veto refuses, and the quick
menu opens at once with the last answer (the client never asks). The server runs `GryMod_CanSetMode` once for each of the modes speed, cloak and
strength (never for the mode the suit is in, never for the armor, never while the suit is down or off) and sends the result when:

- the client is ready and at every spawn (always);
- the mode of the player changes, a malfunction starts or ends, or the suit is switched off or on (only if the answer changed);
- you call `GryMod.API.RefreshModeStates(ply)` (only if the answer changed): this is THE way to say "my condition changed", for example when the
  player walks into a zone. Call it once after you add your listener too, so that the check below starts;
- a timer says so. A veto is any function of any state, so GryMod cannot see it change by itself. While at least one listener of
  `GryMod_CanSetMode` exists and a player is alive, a timer (every 0.5 s) asks again for each living player and sends a message only to the
  players whose answer changed. With no listener, or nobody alive, the timer does not exist and nothing runs.

So your listener can be called more often than by real mode changes: it must only answer, with no side effect, and be cheap. The cost is 2 or 3
calls of the hook for each living player at each tick, so at most 6 calls a second for each living player, each running all the listeners.

```lua
GryMod.API.RefreshModeStates(ply) -- true, or false and "invalid player"; the open menu greys or restores its icons at once if the answer changed
```

A player can turn the display off with `gry_menu_show_refused 0` (the menu then only greys the weapon icon when the weapon in hand has no menu of its own, see the weapon menus below). On the client,
`GryMod.FlashMenu.IsRefused(mode)` says what the server last sent.

### Notes on the reporting hooks

All the hooks above only report: GryMod never reads what a handler returns, and a handler cannot change the result. (`GryMod_CanSetMode` is
the one veto.)

- `GryMod_Zoom` only covers the zoom that goes through `gry_zoom_fov`: the suit's own zoom and the binoculars. The zoom of a weapon (the
  crossbow, a scope) is not reported. The value is sent once per real change, never twice in a row; the final `0` also comes when the zoom
  stops by itself (the client went silent), when the player dies and when he leaves, but only if a zoom was held.
- `GryMod_ArmorAbsorbed` runs after the damage was changed: the `DamageInfo` already holds `passed`. A handler that calls `TakeDamage` from
  this hook starts a nested damage event (the handler of the armor runs again inside yours): guard against it.
- `GryMod_SprintStart` / `GryMod_SprintEnd` follow `GryMod.IsSpeedSprinting`: fast enough, on the ground or swimming, in speed mode. With the
  infinite armor there is no sprint and no event (switching the infinite armor on while a player sprints ends it). The events are told by
  the existing speed `Think`, so the end comes one tick after a change of mode or a death. A player who leaves while sprinting gets his
  `GryMod_SprintEnd` at once, so a start always has an end.
- `GryMod_StrengthJump` is fired right after the jump is granted and the energy is paid. With the infinite armor the jump is free but it is
  reported too.

## Cloak level (server and client)

`GryMod.API.Has("cloaklevel")` is true. The camouflage is a switch for the player, but an AI that watches him needs to know how far it has
faded: right after the switch the player is still half visible, and right after the end he is still half hidden.

```lua
local level = GryMod.API.CloakLevel(ply) -- 0 = not cloaked, 1 = fully cloaked
```

- The level moves toward 1 while the camouflage is on and toward 0 when it is off, at `1 / gry_cloak_fade_seconds` per second. The server
  setting `gry_cloak_fade_seconds` is 2 by default, from 0 (an instant switch) to 10.
- A camouflage switched on again during the fade-out goes on from the level it had.
- A dead player is 0, and a respawn starts at 0 at once.
- Nothing runs between two switches: the server writes two networked stamps on the player at each switch (`GryCloakLvl0`, the level at that
  moment, and `GryCloakT0`, the time), and the level is computed when you ask. So it costs nothing to ask it often, on the server or on the
  client.
- `GryMod.CloakLevelFrom(on, level0, t0, now, rate)` is the formula itself, and `GryMod.CloakFadeRate()` the rate of the server setting.

The camouflage still sets `FL_NOTARGET` for the Half-Life 2 NPCs, as before: the level is for AIs that make their own perception.

## Suit noises (server)

`GryMod.API.Has("suitnoise")` is true. The hook `GryMod_SuitNoise(ply, pos, radius, kind)` tells an AI's hearing about the noises only the
suit knows of. `pos` is where the player stands, `radius` is how far it carries in units, `kind` is one of:

| `kind` | When | Radius |
| --- | --- | --- |
| `cloak_fire` | the player fires while his cloak level is above 0 (at most once a quarter second) | 2000 |
| `strength_jump` | a strength jump (the same moment as `GryMod_StrengthJump`) | 1000 |
| `speed_sprint` | a speed sprint starts (the same moment as `GryMod_SprintStart`) | 800 |
| `cloak_on`, `cloak_off` | the camouflage switches on or off (not at a respawn) | 300 |

The radii are in `GryMod.SuitNoiseRadius`, which you may change. Footsteps, landings and the weapons' own sounds are not suit noises: hear them
yourself (`PlayerFootstep`, `OnPlayerHitGround`, `EntityFireBullets`). `GryMod.EmitSuitNoise(ply, kind)` fires the hook by hand.

## Relation: ally, neutral or hostile (server)

`GryMod.API.Relation(ply, ent)` returns `"ally"`, `"neutral"` or `"hostile"`. It is the only place that decides it for the radar and for
an NPC under the crosshair's friendly cross (`GryMod.Friendly.Relation` is the same function). Known gap: for another player the cross
applies the team rule on the client without asking the server, so a provider cannot change it for players. The order:

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

## Binoculars: spotting and the hologram

While the binoculars are up (the zoom key, or the own zoom of GryMod) the HUD follows the original game's rules. Every part has its own setting of the player
(the Binoculars category of the options, all saved client convars):

- **Pace and shot.** No sprint, and the slow walk instead of the jog (`gry_binoculars_walk`, 1); no shooting (`gry_binoculars_no_fire`, 1). Both work on the buttons of
  the player's move, only while the binoculars are up. Holding the right click steps the zoom ONCE, 0.25 s after the key went down (2x, 4x, 8x, then back to 2x; let go and hold again to step again) (`gry_binoculars_hold_zoom`, 1).
- **The hologram** (`gry_binoculars_hologram`, 1; needs `gry_binoculars_silhouette`). What the binoculars spot is drawn with a thin outline and its whole body
  filled with scan lines. A **hostile** NPC in view is lit from the start (`gry_binoculars_baseline`, 1; with 0 only what the scan reaches), in
  the colour of its alert level, as in the original: dark green when it is idle, amber when it is alerted (`NPC_STATE_ALERT`), dark red when it fights
  (`NPC_STATE_COMBAT`, or when it has the player as its enemy). The NPC the binoculars are scanning turns **white** for the last 0.3 s of its scan, then it is
  **spotted**: the server is told, the radar shows it, and it goes back to its colour. An **ally** (or a neutral NPC) is not drawn; when it is scanned it pulses
  once from white to blue and nothing stays (no label: the box with a name and a distance belongs to the objective markers). A **weapon lying on the ground**
  (nobody holds it) within 10 m is blue, and white while the player aims at it; a weapon in someone's hand is never lit on its own: it is part of the silhouette
  of its holder (a lit hostile) or nothing (an ally). At most 16 things are drawn, the nearest ones; the sides and the alert levels come from the relation chain
  (`GryMod.API.Relation`) and the radar's rule, asked in one batch of questions (three a second at most, each answer worth one second).
- **The hologram's style** (`gry_binoculars_holo_style`, `crysis` by default). `crysis` draws it the way the original does, with a pixel shader: the things are drawn
  flat, in their colour, into a buffer the size of the screen (only where they are not behind a wall); a full-screen pass finds the boundary of the shapes, fills
  every body with a share of its colour, brightens the boundary, puts a bright and a dim pixel row on all of it (the scan lines) and a vignette, and adds a blurred
  glow. `simple` is the older drawing (an additive scan-line material and the game's halo). The game falls back to `simple` by itself when it cannot run the shader.
  The levels are the fields of `GryMod.BinocularsHolo.Crysis` (`FILL`, `BOOST`, `STRENGTH`, `TAP_1080` for the width of the boundary, `GLOW_GAIN`, `SCAN_HI`,
  `SCAN_LO`, `VIGNETTE`), read at every frame: change them from the console to tune the look. With antialiasing on (`mat_antialias` above 1) the buffer cannot share the
  scene's depth, so a wall is looked for with a trace for each thing instead.
- **The radar.** A hostile is on the radar once the binoculars spotted it, or when it is alerted or fighting within 26 m. It is **yellow** while it is alerted
  (`NPC_STATE_ALERT`: it heard something, it is searching) and **red** when it is fighting (`NPC_STATE_COMBAT`). The hook `GryMod_TargetSpotted(ply, ent, relation)`
  (server, in the table of the hooks above) tells your addon when a target is spotted.
- **The objectives** (`gry_objectives_marker_mode`): `binoculars` (the default, as in the original) shows the objective markers on the screen only while the
  binoculars are up, `always` shows them all the time. The radar and the maps are not affected.
- **The use prompt** (`gry_usehint_delay`, 0.1 seconds by default as in the original, 0 for at once): the prompt shows after the crosshair stayed that long on the same usable thing,
  and goes `gry_usehint_hold` seconds after the crosshair left the thing (0.2 by default as in the original, 0 for at once);
  looking at another usable thing ends the hold at once, and looking back at the same thing keeps the prompt without a break. `GryMod_UsableChanged` (docs/events.md) is run when the prompt appears or goes.

## Night vision (client)

The suit has the night vision of the original game: a light amplifier with an energy of its own (30 units, 0.5 used a second, so 60 s of use; 2 recovered a
second while it is off, so 15 s to refill; it switches itself off when it is empty and cannot be switched on then). The key is **N** by default (only when nothing
else is bound on it; pick another one in Options > GryMod > Keys, or `bind <key> +gry_nightvision`). The sounds are the original's (switch on, a loop while it
lasts, switch off), the energy bar is the original's movie, and the screen effect is GryMod's own: a green amplifier with an automatic gain, a soft light
behind the player (with shadows), a long grey fog and a faint starlight floor. Nothing about the AI changes: the night vision does not make the player more or less
visible.

Everything is a setting of the player (client, saved) and each piece is optional:

| Setting | Default | What it does |
| --- | --- | --- |
| `gry_nightvision` | 1 | 0: the night vision cannot be switched on |
| `gry_nightvision_key` | 0 (N when free) | the key (a button code, 0 = the default) |
| `gry_nightvision_hold` | 0 | 1: the key is held (on while it is down); 0: press to switch on and again to switch off |
| `gry_nightvision_energy` | 1 | 0: no energy limit and no bar |
| `gry_nightvision_drain`, `gry_nightvision_recharge` | 0.5, 2 | energy used a second while on, recovered a second while off |
| `gry_nightvision_fx` | 1 | 0: no screen effect (the sounds and the bar stay) |
| `gry_nightvision_light` | 1 | the light behind the player |
| `gry_nightvision_star` | 1 | the starlight pass (a second, cheap render of the world) |
| `gry_nightvision_localgain` | 1 | each dark area of the screen is brightened on its own; 0: one gain for the screen |
| `gry_hud_nightvision` | 1 | the energy bar of the HUD |
| `gry_sv_nightvision` (server) | 1 | 0: nobody can use it (administrators' menu) |

`gry_sounds 0` mutes its sounds. The effect costs nothing while the night vision is off (its hooks exist only while it is on and for the quarter second of the fade).

```lua
-- run on the client, once at each change; the return is not read
hook.Add("GryMod_NightVision", "my_addon", function(on, reason)
	-- reason: "key" (the player), "energy" (empty), "death", "dead", "suit" or "malfunction" (the suit is down), "disabled" (the suit flag is off),
	-- "option" (the player turned the setting off), "server" (the server switch), "shutdown" / "init" (map change, silent), or the reason of the caller
end)

GryMod.NightVision.IsOn()            -- the wanted state
GryMod.NightVision.Energy()          -- 0 to 30
GryMod.NightVision.Bar()             -- 0 to 100, what the HUD bar shows
GryMod.NightVision.CanTurnOn()       -- false plus the reason when it would be refused
GryMod.NightVision.Set(true, "my_addon")   -- the same rules as the key; true, or false plus the reason ("same" when nothing changes)
GryMod.NightVision.Toggle("my_addon")
```

Switching it through `Set` (or the HUD event `night_vision`, see docs/events.md) plays the sounds and runs the hook; it never comes back by itself after it went off.
There is no veto hook (the return of `GryMod_NightVision` is not read): an addon that wants to take it away (an area without light amplification, say) switches it
off with `Set(false, "my_addon")` when its own condition holds, from that same hook for example. The energy bar is raised by the hook and goes by itself when the energy is full again.

## HUD events

A HUD event is a named effect the HUD plays, picture and sound together; GryMod's own triggers call the same events. The full list
(`boot`, `lost`, `reboot`, `malfunction`, `armor_hit`, `decloak`, `low_health`, `jam`, `mode`, `energy_critical`, `regen_start`,
`regen_stop`, `dive_in`, `dive_out`, `drown`, `reset`, `disabled`, `enabled`, `message`), their data, what each plays and the options they follow are
in [events.md](events.md), with examples and the effects test window.

From the server, to one player or a list of players:

```lua
GryMod.API.HUDEvent(ply, "malfunction", {seconds = 3})
GryMod.API.HUDEvent(player.GetAll(), "boot")
```

The data is `nil` or a small table: at most 8 fields, names of letters, digits and underscore (24 characters at most), values that
are finite numbers, strings (128 characters at most) or booleans. The event name has 32 characters at most. A call that breaks
these limits returns `false` and a reason, and sends nothing (`GryMod.API.HUDEventLimits` tells the limits).

On the client, to play one here or to declare your own (the optional third argument describes it for tools: `label`, `variants`,
`follows`, see events.md):

```lua
GryMod.API.RegisterHUDEvent("my_flash", function(data)
	-- data is a table (empty when there is no data)
end)

GryMod.API.HUDEvent("my_flash", {power = 3})     -- plays it on this client, returns true when the handler ran
GryMod.API.UnregisterHUDEvent("my_flash")
GryMod.API.ListHUDEvents()                       -- sorted names
GryMod.API.GetHUDEventInfo("my_flash")           -- a copy of {label, variants, follows}, or nil

hook.Add("GryMod_HUDEvent", "my_addon", function(name, data) end)   -- after a handler ran without error
```

## Text lines

`GryMod.API.Has("messages")` is true. A line of text on the HUD (the stack of lines of the original game) is the HUD event `message`:

```lua
GryMod.API.ShowMessage("OBJECTIVE ACTIVATED")                                -- client: on this screen, the top lane
GryMod.API.ShowMessage(ply, "Door unlocked", {lane = "status", duration = 3}) -- server: on the screen of ply (or a list of players)
hook.Add("GryMod_MessageShown", "my_addon", function(text, opts) end)         -- client: a line was shown
```

Options: `lane` (`"top"` by default, `"middle"`, `"status"`, `"crosshair"`, or 1 to 4), `sound` (a sound path, played with the line) and `duration`
(seconds, 0.5 to 60; 5 by default). The text is 128 characters at most. The lanes, the suit's own lines and the settings that turn them off are
in [events.md](events.md) ("Text lines"). The player can turn all lines off with `gry_hud_messages`.

## Usable things: the use prompt

`GryMod.API.Has("usable")` is true. When the player looks at something that needs the use key, the HUD shows an icon and a text under the crosshair
("ENTER VEHICLE", "CLIMB", "TALK", "USE"). Whether something can be used at all is the crosshair's own test, the one that opens its "usable" state; the
registry of usable entities says WHAT it is. An entity that no entry names has no prompt, and what the player takes by walking over it (a weapon on the
floor, a health kit, a battery, ammo) has none either: it needs no key. The player can turn the prompt off with `gry_hud_usehint`.

```lua
GryMod.API.RegisterUsable("my_addon_terminal", {
	class = "my_addon_terminal",        -- or base = "my_base", or match = function(ent) return ... end
	icon = "use",                       -- "use", "enter", "pickup", "grab" or "ladder" (the five of the movie)
	text = "HACK %1",                   -- %1 is the name; a function(ent, ply) -> string works too. The text is shown in capitals
	name = "terminal",                  -- optional: a string or function(ent) -> string; else the weapon's print name, else the class
	priority = 10,                      -- optional: the higher first (the stock entries are at -100)
	nonsolid = false,                   -- optional: true for a thing the player's aim passes through (a ladder); needs a class
	use = "repeat",                     -- optional: "repeat" (a door, a button: it can be done again) or "once" (the default: the use changes the state)
	cooldown = 2,                       -- optional, "repeat" only: seconds the prompt is dimmed after the key (0.5 when not given)
	ready = function(ent) return not ent:GetNWBool("hacking") end,        -- optional: false = dimmed, the key does nothing
	busy = function(ent, ply) return ent:GetNWEntity("user") == ply end,  -- optional: true = no prompt now (it is in use)
	group = "terminals",                -- optional: the player switches the group with the client convar gry_usehint_terminals when there is one
	spawnflags = {need = 256, forbid = 32768},  -- optional: the entry applies only if all the `need` bits are set and none of the `forbid` bits (or a function(flags, ent) -> bool)
	active = function() return true end,        -- optional: false = the entry does not apply now at all (a setting of the server, not of the entity)
	range = 80,                         -- optional: how far the key reaches for it, in units (80 by default, the engine's)
	hold = false,                       -- optional: true when the key must be kept down (a charger): one pulse at the press, not one per repeat
	nolimits = false,                   -- optional: true for a "grab" that has no size or mass limit
	netclass = "class C_BaseToggle",    -- optional, with nonsolid: the name the CLIENT gives these entities when the game has no client class of their name
	})

GryMod.API.UnregisterUsable("my_addon_terminal")
GryMod.API.GetUsable(ent)               -- the entry that matches the entity, or nil
GryMod.API.UsableText(ent, ply)         -- the text the prompt shows for it, or nil
GryMod.API.UsableFlagsAllow(entry, ent) -- whether the entity's spawnflags let the entry apply (true when it has no rule or the flags cannot be read)
GryMod.API.UsableRange(entry)           -- the key's reach for the entry in units (80, GryMod.API.USE_REACH, when it gives none)
GryMod.API.UsableMaxRange()             -- the greatest range of all the entries: how far the crosshair looks
```

The crosshair asks this registry what can be used: **registering an entity makes it usable** (the crosshair's "usable" state opens on it, and the
prompt shows), and an entity no entry names is not. Rules that apply on top: an entry with the `"grab"` icon only counts while the player can lift the
entity (the Source rule: at most 35 kg and 128 units on every side; the client reads the size and asks the server for the mass, because it has no physics
object for a prop of the server: while the answer is not there the prop is not offered, and it is asked again every 3 seconds while it stays aimed);
an entry with the `"enter"` icon does not count while the player sits in a vehicle; an entry whose `busy` says yes does not count; an entry with a `group`
does not count while the player switched that group off. An entry with `nonsolid = true` (it needs a `class`) is for things that are not solid, like the
ladder: the eye trace passes through them, so the crosshair also looks for the entities of those classes (and the `netclass` names) along the aim ray, up to the
entry's range and not behind a wall (`GryMod.API.UsableNonSolidClasses()` lists them). To react when the usable thing changes, listen to the client hook
`GryMod_UsableChanged(ent, mode, ply)` (see [events.md](events.md)).

**Spawnflags: what really answers the key.** Many things have a use capability in the engine and do nothing with it, or do not have it at all, depending on
their spawnflags, and the client can read them (`ent:GetSpawnFlags()`). An entry with `spawnflags` only matches an entity whose flags pass: the stock
rules are `prop_door_rotating`: not 32768 ("Ignore player +USE": 36 doors of the campaign), `func_door` and `func_door_rotating`: 256 ("Use opens": 367 of the
492 stock `func_door` have neither it nor 1024 "Touch opens", a button or a trigger opens them), `func_button`, `func_rot_button` and `momentary_rot_button`: 1024
("Use activates": touch and damage buttons get no prompt), the mounted guns `func_tank*`: 32 ("Controllable"), `prop_physics`: not 512 ("Prevent pickup"),
`func_physbox`: not 8192. A door or a button that "starts locked" (2048) still gets the prompt: the use plays the lock sound, and whether it is locked now cannot
be read on the client. An entity that cannot say its flags is not refused for them. The entities with no entry never get a prompt: that is the deny list
(`func_brush`, `cycler`, `func_pushable`, the Monk, Dr Mossman, G-Man and the metropolice, whose use does nothing or only annoys, and ragdolls, which the use
key does not lift).

**Class names on the client.** For a `func_button`, a `func_rot_button` and a `momentary_rot_button` the client's `ent:GetClass()` is the name of the network class
(`class C_BaseToggle`), not the class the map gave. The registry matches on `GryMod.API.UsableClassOf(ent)`, which asks the server (once per entity, answer kept
for 20 seconds, 10 questions a second at most per player) for a name like that, so an entry with `class = "func_button"` works on the client. The answer takes a
tenth of a second: until it is there the entity has no prompt.

**Reach.** The use key reaches 80 units from the eye (`GryMod.API.USE_REACH`); the prompt shows only inside that distance, or the entry's own `range` (the stock
ladder: 64). The ladder has a prompt (`CLIMB`) only while the server variable `sv_ladder_useonly` is 1: with the default 0 the player climbs a ladder by walking
into it, so no key is needed.

**What the key does to the prompt.** `use = "once"` (the default) is for a use that changes the state of the thing, like picking up a grenade, getting into
a vehicle or taking a mounted gun: the prompt goes away as soon as the key is pressed and stays away while the player keeps looking at that thing; it comes
back after he looked away or at something else. `use = "repeat"` is for a door, a button, a charger: the prompt stays, the HUD event `use_feedback` plays
(the icon pulses and a beep plays, see [events.md](events.md)), and the prompt is dimmed for the entry's `cooldown` (half a second when it gives none) or for as
long as its `ready(ent)` says no. With `hold = true` (the chargers and the wheels, whose text is `USE (HOLD)`) the key is kept down while they work: the event
comes once, at the press, however often the bind repeats, and there is no dimming. The client convar `gry_usehint_feedback` (1 by default) turns the pulse, the
beep and the dimming off.

**Groups.** The stock entries for the props, the physboxes and the floor turret you can lift (`PICK UP`) are in the group `"props"`, which the player switches
with the client convar `gry_usehint_props` (0, off, by default: "you can pick up almost anything"). The convar of a group is named `gry_usehint_<group>`; a
group that has no convar is always on. A developer can make one: `CreateClientConVar("gry_usehint_terminals", "1", true, false)`.

The stock entries are registered the same way, with a low priority: yours win. They cover what has a +use action in Half-Life 2 and Garry's Mod and
is not taken by touch: the ammo crate (`TAKE AMMO`), the wall chargers and the wheels (`USE (HOLD)`), vehicles (`ENTER VEHICLE`), ladders (`CLIMB`, only with
`sv_ladder_useonly 1`), doors and buttons (`USE`, by their spawnflags), the mounted guns (`USE`, the controllable ones), the thrown frag grenade (`PICK UP`), the
lifted props and physboxes and the floor turret (`PICK UP`, in the props group), the friendly NPCs that answer +use (`TALK`: citizen, Barney, Alyx, the
vortigaunt), `gmod_button`, `gmod_wheel` and `sent_ball`.

## Pickups

`GryMod.API.Has("pickups")` is true on the client. When the player takes ammo, a weapon or an item (the game's own hooks `HUDAmmoPickedUp`,
`HUDWeaponPickedUp`, `HUDItemPickedUp`), a small popup shows the count, an icon and the name, and the Half-Life 2 pickup list is hidden while
the popup is on. The same pickup taken again while the popup is still on adds the counts. The player can turn it off with `gry_hud_pickups`.
The icons of the movie are ammo icons; the registry says which one a pickup gets (a pickup that no entry names has no picture, only its count and
name):

```lua
-- client
GryMod.API.RegisterPickupIcon("ammo", "MyAmmo", "rocket")        -- kind: "ammo" (the ammo type), "weapon" (the class) or "item" (the class)
GryMod.API.RegisterPickupIcon("weapon", "my_addon_gun", "DSG1")
GryMod.API.GetPickupIcon("ammo", "MyAmmo")                       -- "rocket", or "New" (no picture)
GryMod.API.UnregisterPickupIcon("ammo", "MyAmmo")
```

The icons are `Riffle`, `socom`, `shootgun`, `missle`, `rocket`, `FY71`, `Hurricane`, `LAW`, `TACGun`, `GaussRifle`, `DSG1`, `MOAR`, `MOAC`,
`Flashbang`, `SmokeGrenade`, `Sleep` and `AVMine`.

## Weapons

`GryMod.API.Has("weapons")` is true. The HUD never knows a weapon by its class name: it asks the weapon registry what the weapon is.
The stock Half-Life 2 weapons are registered in the registry as data (`lua/grymod/compat/hl2/sh_weapons.lua`), with the same call your
addon uses: there is no private table and no special case for them.

### Describe a weapon

A weapon is described by a **definition**, a table of optional fields. A field you leave out is read from the weapon itself.

| Field | Values | Meaning |
| --- | --- | --- |
| `fire` | `"auto"`, `"semi"`, `"burst"`, `"none"`, or `function(wep)` returning one of them | the fire mode shown in the weapon slot (`"none"`: no gun icon, for a melee weapon) |
| `burst` | integer, 2 to 32 | the size of a burst, when `fire` is `"burst"` |
| `ammo` | ammo type name | the primary ammo (default: `Primary.Ammo`, then the engine's ammo of the weapon) |
| `counter` | `"clip"`, `"none"`, or `function(wep)` returning a text | what the counter shows (default `"clip"`; `"none"` when `CustomAmmoDisplay` says `Draw = false`) |
| `alt` | `"none"`, `"grenade"`, `"energy"`, `"zoom"`, `"doublebarrel"`, `"shoot"`, `"throwlow"`, `"melee"` | what the secondary fire (right click) is; `"zoom"` also makes the binoculars end the weapon's zoom when they open (client and server read the registry) |
| `altAmmo` | ammo type name | the ammo the secondary counts (`"SMG1_Grenade"` for a grenade launcher, `"AR2AltFire"` for the energy ball) |
| `altShoots` | boolean | true when the secondary fires a shot. The camouflage ends on a right click that shoots. Default: true for `grenade`, `energy`, `doublebarrel`, `shoot` and `throwlow` |
| `altLabel` | short text, 24 characters at most | the name of the secondary fire (`"40mm"`) |
| `altIcon` | an icon key (see below) | the icon the HUD shows for the secondary fire |
| `icon` | an icon key | the icon of the weapon slot (it wins over `fire`) |
| `slotIcon` | an icon key | the stock icon of the weapon slot, when `icon` is not given |
| `crosshair` | boolean, or a number 1 to 13 | `false`: the HUD draws no crosshair while the weapon is in hand (the stock fists and RPG). `true` or no field: the player's crosshair style. A number: the weapon shows that one of the 13 crosshairs of the HUD movie (11, 12 and 13 are the ones the original game forces by weapon), unless the player turned off `gry_hud_crosshair_weapon` |
| `zoomCrosshair` | boolean, or a number 1 to 13 | with `alt = "zoom"`, for a weapon that draws no scope aim of its own: `true` keeps the player's crosshair while the zoom is up; a number shows that one of the 13 crosshairs of the HUD movie in the zoom (the stock crossbow, a precision weapon, shows the thin cross, 7), unless the player turned off `gry_hud_crosshair_weapon`. Without the field, a zoomed weapon hides the crosshair, as a scope has its own |
| `heat` | `function(wep)` returning a number, 0 (cold) to 1 (overheated) | how hot the weapon is: the HUD shows the heat bar above the weapon icon, only for a weapon that declares this. Asked at each frame while the weapon is in hand, under `SafeCall`. The player can turn the bar off (`gry_hud_overheat`) |
| `listIcon` | a silhouette of the weapon list (`GryMod.API.WeaponListIcons`: `SOCOM`, `SMG`, `Shotgun`, `SCAR`, `FY71`, `Hurricane`, `LAW`, `TACGun`, `GaussRifle`, `DSG1`, `Grenade_Explosive`, `Grenade_Flashbang`, `Grenade_Smoke`, `C4`, `LockpickKit`, `RadarKit`, `RepairKit`, `AVMine`, `Claymore`, `MOARAttach`, `AlienMount`, `Grenade_EMP`, `NightVision`, `Binoculars`, `Fists`) | the picture of the weapon in the weapon list that shows when the player changes weapon. Without it the list uses the kind of the weapon's `grenade`, and else writes the weapon's name |
| `grenade` | `"explosivegrenade"`, `"flashbang"`, `"smokegrenade"`, `"empgrenade"` (`GryMod.API.GrenadeKinds`) | the kind of hand grenade the grenade slot shows while the weapon is in hand. A weapon that declares it counts **its own primary ammo** there (the player's hand grenades are the explosive ones). Default: `"explosivegrenade"` and the hand grenades' count |

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
| `fire` | client | the fire-mode icon of the weapon slot |
| `burst`, `ammo`, `counter` | resolved, not read yet | accepted and returned by `ResolveWeapon`; the HUD does not read them today (its counter is the engine's own ammo: `Clip1`, `GetMaxClip1`) |
| `alt`, `altAmmo`, `altIcon` | client | the grenade slot (which ammo it counts, its icon) |
| `altLabel` | sent, not drawn | the movie has no text field for it |
| `altShoots` | client | the camouflage: a right click that shoots ends it (the HUD tells the server) |
| `icon`, `slotIcon` | client | the icon of the weapon slot |
| `crosshair` | client | the HUD's crosshair is hidden while the weapon is in hand, or the weapon's own style is shown |
| `zoomCrosshair` | client | with `alt = "zoom"`: the HUD's crosshair stays while the zoom is up (`true`), or is the numbered one of the movie (the stock crossbow: the thin cross); without it a zoomed weapon hides the crosshair |
| `heat` | client | the heat bar above the weapon icon; also reported to the hook `GryMod_WeaponHeat(ply, wep, percent)` (client, each time the bar moves, 0 when it is hidden) |
| `grenade` | client | the icon of the grenade slot, and its blink when the kind changes (a weapon change from one kind to another) |
| `listIcon` | client | the silhouette of the weapon in the weapon list shown at each weapon change; reported to the hook `GryMod_WeaponListShown(ply, wep)` (client) |

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
weapons: later (the HUD already reads their fire mode, for the icon only, through its own resolvers, `GryMod.FlashHUD.AddFireModeResolver`,
which is not part of the versioned API). An adapter is asked for a weapon **entity** only: the camouflage rule `AltFireShoots`
asks by class name, so an adapter cannot answer `alt` or `altShoots`.

### Weapon parts: the models a weapon draws itself (client)

`GryMod.API.Has("weaponparts")` is true. A weapon can draw models of its own that are not its view model: the attachments of a weapon base (a sight, a silencer, a laser).
The engine does not know them, so the camouflage of the arms and the gun would leave them plain. A **provider** says which they are, for a weapon, at the moment it is asked:

```lua
-- client side
GryMod.API.AddWeaponPartsProvider("my_addon", function(weapon, out)
	if weapon:GetClass() ~= "my_weapon" then return end

	out[#out + 1] = weapon.SightModel       -- client side models the weapon draws, valid entities
	out[#out + 1] = weapon.LaserModel
end)

GryMod.API.RemoveWeaponPartsProvider("my_addon")
GryMod.API.GetWeaponParts(weapon, out)      -- fills your table (reused) and returns it with the count
```

The suit asks at every frame it draws the camouflaged gun in first person, and puts the same layers over each part as over the view model, so an attachment that the player changes
during the camouflage is the next frame's list: nothing to refresh. The layers leave alone what the player aims with, found by what the materials ARE and not by any name: an
unlit material (a reticle, a holographic sight), a translucent or additive one (the glass of a lens, with the dot of a red dot sight painted on it), and a material whose texture is
not a file (the picture a scope shows, a render target). The body of the weapon and of its attachments, opaque and lit, is camouflaged. A provider runs under `SafeCall` (five errors in a row switch it off), what it gives is checked (valid entities
only), at most `GryMod.API.MAX_WEAPON_PARTS` (16), and the same id replaces the provider. The patch for TFA is in `lua/grymod/compat/weapons/cl_tfa_parts.lua` ([compat.md](compat.md)).

### Weapon menus: the menu of a weapon base (client)

`GryMod.API.Has("weaponmenu")` is true. The weapon icon of the suit's quick menu opens the menu of the weapon in hand (for a TFA weapon: its attachments and ammunition menu), and it is
greyed for a weapon that has none. It used to drop the weapon: that is gone, and so is the old drop "mode". GryMod knows no weapon base: a **provider** answers, for a weapon, with the
function that opens its menu, or with nothing when the weapon is not its own or has no menu to open.

```lua
-- client side
GryMod.API.AddWeaponMenuProvider("my_addon", function(weapon)
	if weapon:GetClass() ~= "my_weapon" then return nil end

	return function(weapon) weapon:OpenMyMenu() end   -- what opens the menu
end)

GryMod.API.RemoveWeaponMenuProvider("my_addon")
GryMod.API.GetWeaponMenu(weapon)     -- the opener of the first provider that has one, or nil
GryMod.API.OpenWeaponMenu(weapon)    -- runs it, true when there was a menu to open
```

A provider must be cheap (the quick menu asks it while it is open), runs under `SafeCall` (five errors in a row switch it off) and the same id replaces it. An opener that raises an
error is caught. The patch for TFA is `lua/grymod/compat/weapons/cl_tfa_menu.lua` ([compat.md](compat.md)).

## Radar markers (client)

`GryMod.API.Has("radarmarkers")` is true. Anything can put icons on the radar of the HUD by giving it a **source**: a function that returns the markers of
the moment. The radar asks every source once per frame it draws, places each marker with the same range, zoom and frame as its own contacts, and draws it
with the icon of the original game. No `Think` is added: the sources are asked from the radar's own drawing code, and when there is no source nothing runs.

```lua
-- client side
local function myMarkers()
	return {
		{pos = Vector(0, 0, 64), type = 5, subtype = 0, id = "treasure"},    -- an objective: an arrow on the border when it is far
		{pos = LocalPlayer():GetPos() + Vector(300, 0, 0), type = 6, scale = 150, alpha = 0.5}, -- a ring
	}
end

GryMod.Radar.AddSource("my_addon", myMarkers)       -- returns true, or false and a reason
-- ... later:
GryMod.Radar.RemoveSource("my_addon")               -- returns whether there was a source
```

| Function | What it does |
| --- | --- |
| `GryMod.Radar.AddSource(key, fn)` | adds a source (a second call with the same key replaces it and keeps its place). `fn()` takes no argument and returns an array of markers, or nothing |
| `GryMod.Radar.RemoveSource(key)` | takes a source away |
| `GryMod.Radar.HasSource(key)` | whether the key is a source |
| `GryMod.Radar.Sources()` | the keys of the sources, in order |

A **marker** is a table. Only `pos` and `type` are required:

| Field | Meaning |
| --- | --- |
| `pos` | `Vector`, a point of the world |
| `type` | the icon: `1` to `4` the unit icons of the contacts, `5` an objective arrow, `6` an explosion ring, `7` a team mate |
| `subtype` | `0` to `4`, default `0`. For the units it is their state (`0` calm, `3` alerted, `4` fighting). For type 5 it is `0` primary (green) or `2` secondary (yellow); the radar picks the arrow itself when the marker is beyond the radar |
| `alpha` | `0` to `1`. Default: the original's (`0.85` units, `0.75` objective arrow, `1` ring and team mate) |
| `scale` | percent of the icon, `100` being the size of the movie's picture. Default: the original's (the units' by height, `75` objective arrow, `100` ring, a team mate `100` times the height factor) |
| `yaw` | degrees, optional: the way a unit icon (types 1 to 4) faces in the world. Without it the icon points up |
| `id` | anything, only given back to the radar's code |

**What the radar does with a marker beyond its reach** depends on the type, as in the original game:

- type `5` (objective arrow) **sticks to the border** of the radar, in the edge picture (an arrow pointing away from the player). Inside the
  radar it is a glow.
- type `7` (team mate) sticks to the **circle of the range**.
- every other type is not drawn when it leaves the radar's frame.

A marker more than 500 m above or below the player is not drawn, and a radar can show 64 markers at most. A marker that is not valid is skipped.
A source runs under `pcall`: when it throws, the others are not affected; after three errors in a row it is **removed** with one message in the console.
The radar zoom (`gry_radar_range`, and the automatic zoom) applies to the markers as to the contacts. The player's switch is `gry_hud_radarmarkers`
(Radar and map menu): off, no source is asked.

### Explosion rings: `GryMod.API.ReportRadarPing(pos, kind)` (server)

An explosion shows on the radar as a ring that opens and fades in two seconds (the original game's icon type 6). The server tells the players that are
within 250 m of it. Every `env_explosion` does it by itself, so the Half-Life 2 rockets, barrels, mines, helicopter bombs, tripmines, scanners and roller
mines ring the radar with no code from you, and so does an addon's own `env_explosion`. Some things explode with no `env_explosion` (the engine draws
their blast as an effect): the hand grenade, the SMG grenade, the satchel, the AR2 energy ball and a destroyed manhack. They ring the radar when they are
removed, from the table `GryMod.Radar.ExplosiveClasses` (server; `{radius = units}` or `{kind = "small"}`, `dead = true` for an entity that only counts when it is
destroyed): add the class of your own explosive there if it works the same way. For anything else (your own blast, a gunshot, an alarm), report it:

```lua
-- server side
GryMod.API.ReportRadarPing(ent:GetPos())             -- an ordinary explosion
GryMod.API.ReportRadarPing(ent:GetPos(), "big")      -- "small", "explosion" or "big"
GryMod.API.ReportRadarPing(ent:GetPos(), 6.5)        -- or the radius of the blast in metres (0.5 to 8)

hook.Add("GryMod_RadarPing", "my_addon", function(pos, size, automatic)
	-- a ping was accepted; `automatic` is true for the ones made from an env_explosion. The return value is not read.
end)
```

`ReportRadarPing` returns `true`, or `false` and why: the position is not a `Vector`, the kind is not one, or more than 20 pings were reported in the
same second. A ring of more than 4 m makes one echo, as the original does. The server's `gry_radar_pings` (Radar and map menu, administrators) turns the
automatic pings off; a report through the function always goes out. The player's `gry_hud_radarpings` hides the rings. The rings are drawn through the
marker sources above (key `gry_pings`).

### Team mates

In a team game (at least two teams with players: `Player:Team()` is neither the unassigned, the spectator nor the connecting team) the living players of
your team show on your radar with the team mate icon (type 7), anywhere on the map: far ones stick to the circle of the range. Sandbox, where everybody is
in one team, shows none. The server's `gry_radar_teammates` (1 by default; Radar and map menu, administrators) turns it off. They are radar contacts, so
the player's "Radar contacts" switch hides them.

### Danger bar and hexagon: seen or heard

The danger bar and the hexagon at the bottom left of the radar show how much the hostile NPCs have noticed the player: the bar for the soldiers, the
hexagon for the machines (flying units, vehicles, turrets). The radar's contacts feed them (an alerted or fighting hostile within 26 m). On top of that,
the server counts the hostile NPCs that are **not** contacts, wherever they are in the radar's search sphere (2.1 times the radar range): one that has
the player as enemy or sees him (`COND.SEE_PLAYER`) counts as fighting, one that hears him (`COND.HEAR_PLAYER`) or has lost him and looks for him counts as
alerted. A hostile that fights someone else does not count. The two highest numbers travel in a 4-bit message (`gry_radar_detect`), only when they change.
The server's `gry_radar_detect` (1 by default; Radar and map menu, administrators) turns it off and brings the old behaviour back. A friend never counts.
It costs two engine calls (`HasCondition`) per NPC in the sphere at each tick of the radar (5 a second), no new search and no new timer.

## Tracked entities

`GryMod.API.Has("tracked")` is true. The registry of tracked entities says what an entity is for the HUD. For an NPC or a nextbot: its
icon on the radar, when the radar lists it, what it is to the player (ally, neutral or hostile) and whether the binoculars may tag it.
For a projectile or a trap (a grenade, a mine, a missile): that it is a **danger** the player is warned about, what to call it and
how the server knows it is armed. An entity that is not registered behaves as it always did: the radar reads its class and its
attitude.

Everything the HUD knows about Half-Life 2 entities is registered here as plain data (`lua/grymod/compat/hl2/sh_tracked.lua`: the icon
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
| `shape` | `"unit"` (default), `"dot"`, `"rect"`, `"triangle"` | how it will be drawn on the radar. Accepted and stored, never an error, but nothing reads it yet: the radar draws the icon of `type` (a vehicle is already a rectangle through `type = "machine"`) |
| `danger` | a table (below) | the entity is a projectile or a trap the player must be warned about (the grenade warning) |
| `indicator` | `"warning"`, `"marker"`, `"none"` | how a danger shows on the screen. `"warning"` (the default for an entry with `danger`) is the grenade-detect warning: an icon with the label and the distance. `"marker"` and `"none"` are accepted and stored: the warning does not draw them, and no marker is drawn yet |
| `priority` | a number, -1000 to 1000, `0` by default | the entries with the higher priority are tried first (see below) |
| `heavy` | boolean | server: a hit by this entity (attacker or inflictor) that breaks the armor of a player in armor mode puts the suit down for 3 s (`gry_malfunction_impact`). Matched by class, base or `match` |
| `shock` | `"light"` or `"strong"` | server: a hit by this inflictor is a light shock (flicker, energy drain) or a strong one (suit down for 5 s), whatever the damage type (`gry_malfunction_shock`) |
| `cloakBlind` | boolean, needs a `class` | server: this NPC keeps a camouflaged player in mind for good, so the server makes it neutral to him and makes it forget him while he is camouflaged (`gry_cloak_ai`) |

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

`TrackedClasses(field)` lists the classes of the entries that have a field (the first entry that names a class decides): the list is kept, read it
and do not change it. The camouflage's AI rule uses it to know which NPCs to look for.

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
`relation`). Vehicles and devices (the Combine mine) are listed too, as contacts with a `radar` rule, see above; other entities are
accepted by the registry and ignored by the radar. The `label` does not travel to the client: the radar's message has no room for text and the movies have
no field for a name; it is there for a later part.

### Nextbots that report their awareness

`GryMod.API.Has("awareness")` is true. A nextbot that makes its own perception (it has no NPC state for the radar to read) can tell the radar
what it knows of each player with one method:

```lua
-- server side, on your entity
function ENT:GetGryAwareness(ply)
	return level, exposure, seen, heard
	-- level: 0 calm, 1 alerted (it heard something, it searches), 2 fighting
	-- exposure: 0 to 1, how aware it is of THIS player right now
	-- seen, heard: whether it sees or hears this player at this moment
end
```

- The radar asks it instead of reading an NPC state: the colour of the contact (calm, yellow, red), the binoculars' hologram and the danger
  bar follow your level.
- The **stealth bar** goes to the exact `exposure` (the highest of the hostiles that report one, contact or not), instead of the steps the radar
  gives other NPCs (alerted = half, fighting = full). It travels in steps of 1/63.
- The values are clamped (a level outside 0 to 2, an exposure outside 0 to 1). The method runs under `GryMod.API.SafeCall`: one that throws is
  ignored for that call, and five errors in a row disable it, with one console line.
- Your class must still be a radar contact: register it with `GryMod.API.RegisterTracked("my_addon_soldier", {class = "my_soldier", radar = "hostile"})`.
- Every other entity keeps exactly today's rule.

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
| `shape` | stored | stored | nothing reads it yet; the radar draws the icon of `type` |
| `priority` | yes | yes | the order of the entries |
| `heavy`, `shock`, `cloakBlind` | yes | stored | the suit's malfunction rules and the camouflage's AI rule (server only) |
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

## Objectives

Garry's Mod has no objectives, so GryMod brings a small system for addons and maps: a title, a description, a state, and a place in the
world. GryMod only keeps them and tells everyone who is interested: the server holds the truth, each client gets a mirror, and both realms
run the same three hooks. What the HUD does with them is in "What the HUD does with them", below.

An objective has:

| field | meaning |
|---|---|
| `id` | the text you choose (1 to 64 characters); it names the objective in every call. `"my_addon.find_key"` is a good shape |
| `title` | 1 to 128 characters (required) |
| `description` | up to 512 characters, `""` by default |
| `primary` | `true` (default): a primary objective; `false`: a secondary one |
| `state` | `"active"` (default), `"done"` or `"failed"` |
| `pos` **or** `ent` | where it is: a `Vector`, or an entity (or a function that returns one, asked now and again when the entity may have changed). Give one of them, not both |
| `onRemove` | what happens when the entity it follows is removed: `"remove"` (default: the objective goes away), `"complete"` (it stays at the last place of the entity, `"done"`) or `"fail"` (same, `"failed"`) |
| `via` | optional: an array of up to 16 `Vector`s, the places the player should pass on the way to the objective, in order (a straight line from the player crosses walls; the map's author knows the way). GryMod keeps them and sends them to the clients as `obj.via`; the displays point at the first waypoint the player has not passed yet (within 150 units counts as passed), then at the next one, then at the objective. Give few, certain places rather than many |
| `radar`, `marker` | `true` (default): the HUD may show it on the radar and the minimap (`radar`) and on the screen (`marker`). Turn one off for an objective that should stay in the list only |
| `filter` | `function(ply) return true end`: asked **on the server** for each player; only the players for whom it answers true receive the objective. An error in it, or no answer, hides the objective |

The main objective is a separate choice (`SetMainObjective`): at most one, the one the displays stress.

### Functions (server)

All of them check their input and never raise: they return `true`, or `false` and a short reason.

```lua
GryMod.API.RegisterObjective(id, def)    -- new, or an update of the same id (it keeps its place in the list)
GryMod.API.SetObjectiveState(id, state)  -- "active" | "done" | "failed"
GryMod.API.RemoveObjective(id)
GryMod.API.SetMainObjective(id)          -- nil: no main objective
GryMod.API.ClearObjectives()             -- returns how many were removed
GryMod.API.GetObjective(id)              -- a copy: {id, title, description, primary, main, state, pos, ent, radar, marker, onRemove, via}, or nil
GryMod.API.GetObjectives()               -- copies of all of them, in the order they were registered
GryMod.API.RefreshObjectives([ply])      -- asks the filters again and sends the list again (to one ready player, or to all)
```

`pos` in a copy is where the objective is now: the entity's position while it follows one. At most 256 objectives. A state that
the objective already has is not an error (nothing is told). Re-registering an id replaces its definition; the main objective stays main.

### Hooks (both realms)

```lua
hook.Add("GryMod_ObjectiveAdded",   "my_addon", function(id, obj) end)
hook.Add("GryMod_ObjectiveChanged", "my_addon", function(id, obj, oldState) end)
hook.Add("GryMod_ObjectiveRemoved", "my_addon", function(id, obj, reason) end)
```

They only report (nothing a handler returns is read) and they are run protected: a handler that throws is shown on the console, five times at most
per hook, and stops nothing. `obj` is a copy with the fields of `GetObjective`. `via` is an array of Vectors, or `nil` when the objective has none.

- `GryMod_ObjectiveAdded`: a new objective. On a client: it arrived (when the player joined, or when it was given).
- `GryMod_ObjectiveChanged`: the `state`, the `title`, the `description`, the `primary` flag or the main objective changed. `oldState` is the state
  before the change (the same as `obj.state` when the change is something else). A new position is not a change.
- `GryMod_ObjectiveRemoved`: it is gone, and `reason` says why:

| reason | meaning |
|---|---|
| `"removed"` | `RemoveObjective`; on a client, also: the player may not see it any more (filter) |
| `"cleared"` | `ClearObjectives`, or the administrators switched `gry_objectives` off |
| `"entity_removed"` | the entity it followed was removed and `onRemove` is `"remove"` |
| `"map_changed"` | the map was cleaned up (`game.CleanUpMap`, "Cleanup" in a sandbox game): every objective is gone |

On the server the hooks are not told while the switch `gry_objectives` is off (below).

### Read them on the client

```lua
local list = GryMod.Objectives.List()   -- in the order they were registered
for i = 1, #list do
	local o = list[i]                   -- {id, title, description, primary, main, state, pos, ent, radar, marker, via}
end
GryMod.Objectives.Get("my_addon.find_key")   -- one of them, or nil
GryMod.Objectives.Main()                     -- the main objective, or nil
```

The list can also hold the player's own points, put on the big map with a right click (`own = true`, ids `gry_user_N`): private to the client, never sent to or
known by the server, and left alone by the full list and the CLEAR of the server. Code that wants only the server's objectives skips the entries with `o.own`.

`GryMod.Objectives.Syncing()` is true while a full list is arriving (the list the player gets when he joins, or when `RefreshObjectives` sends it again): the
hooks run during it too, so a display that tells the player about "a new objective" can stay silent for these.

`pos` is resolved when you ask. When the client has the entity the objective follows (it is in view), `pos` is the entity's position
now and `ent` is the entity. Otherwise `pos` is the last position the server sent (it refreshes it twice a second while the entity
moves more than 32 units) and `ent` is `nil`. The tables are reused at every call, so asking every frame costs no garbage: read them, do not
keep or change them (the hooks give copies).

### Example

```lua
-- lua/autorun/server/my_addon_objectives.lua
hook.Add("InitPostEntity", "my_addon objectives", function()
	if not (GRYMOD_INSTALLED and GryMod.API.Has("objectives")) then return end

	-- 1. an objective at a place, the main one
	GryMod.API.RegisterObjective("my_addon.reach_roof", {
		title = "Reach the roof",
		description = "The helicopter leaves in two minutes.",
		pos = Vector(1200, -340, 512)
	})
	GryMod.API.SetMainObjective("my_addon.reach_roof")

	-- 2. an objective that follows an entity and is completed when the entity is removed (an NPC that dies is removed)
	local captain = ents.Create("npc_combine_s")
	captain:SetPos(Vector(900, 100, 0))
	captain:Spawn()

	GryMod.API.RegisterObjective("my_addon.kill_captain", {
		title = "Kill the captain",
		primary = false,
		ent = captain,
		onRemove = "complete"
	})
end)

-- 3. a listener, in a file both realms run (lua/autorun/my_addon_listener.lua)
hook.Add("GryMod_ObjectiveChanged", "my_addon listener", function(id, obj, oldState)
	if obj.state == "done" and oldState ~= "done" then
		print("Objective done: " .. obj.title)
	end
end)
```

### What the HUD does with them

The HUD shows the objectives with no code on your side, and each part has its own setting of the player:

- **On the screen** (`gry_hud_objectives`, in the HUD elements): a marker, the diamond of the original game's HUD, at the place of each **active**
  objective whose `marker` is on, with its distance in metres; it shrinks from 1.4 times its size at 10 metres to 0.7 at 500 metres. When the
  objective is off the screen or behind the player, an arrow of the original's eight sits on the border of the screen and points the way. The marker
  nearest to the middle of the screen opens a small box with the objective's title. A primary and a secondary objective look the same here, as in the
  original. A finished or failed objective has no marker. By default (`gry_objectives_marker_mode` `binoculars`, as in the original) the markers are only
  there while the player looks through the binoculars; `always` draws them all the time.
- **On the radar and the minimap** (`gry_hud_radarobjectives`, in the Radar and map menu): a green glow for a primary objective and a yellow one for a
  secondary one, for each active objective whose `radar` is on, and an arrow on the border of the radar when the objective is farther than its range.
  The minimap is the radar's own window, so it shows the same markers. This uses the marker sources of the radar (see "Radar markers (client)").
- **A line and a sound** (`gry_msg_objectives`): when an objective is added, finished or failed, the top line of the HUD says
  `NEW OBJECTIVE: <title>`, `OBJECTIVE COMPLETED: <title>` or `OBJECTIVE FAILED: <title>` with the sound of the original game. It is the HUD event
  `objective` (docs/events.md). The list the player gets when he joins is silent.

To see all of it without writing Lua, an administrator (or the host of a listen server) types `gry_objectives_demo` in the console, or presses
**Objectives demo (on / off)** in the effects test window: a primary objective 50 metres in front of him, a secondary one 200 metres in front of
him, and one that follows the nearest NPC and is finished when the NPC dies (`onRemove = "complete"`). The same command takes them away.

### A map entity: `gry_objective`

A mapmaker places the point entity `gry_objective` in Hammer and needs no Lua. It calls the same functions.

| keyvalue | meaning |
|---|---|
| `id` | the id of the objective; empty: the entity's name, else `gry_objective_` and its entity index |
| `title`, `description` | the texts (the title is the id when empty) |
| `primary`, `radar`, `marker` | `1` (default) or `0` |
| `startactive` | `1`: the objective exists, active, when the map starts. `0` (default): it waits for `Activate` |
| `follow` | the name of an entity to follow; empty (or not found): the objective sits where `gry_objective` is |
| `removeaction` | `remove` (default), `complete` or `fail`: the `onRemove` of the entity it follows |

Inputs: `Activate` (register it, active; also puts it back to active), `Complete`, `Fail` (register it first when it never was), `Remove`,
`SetMain`. Outputs: `OnActivated`, `OnCompleted`, `OnFailed`, `OnRemoved`, triggered by the inputs above.

### The switch and the rest of the rules

- `gry_objectives` (administrators, default `1`): `0` stops the objectives being sent and the three hooks being run on the server. The functions keep
  working and keep the objectives (so a switch turned off and on again loses nothing); clients drop their copy at once (reason `"cleared"`) and get
  the full list again when it is turned on.
- A client gets the full list when it says it is ready (when it joins), then each change as it happens. Nothing runs on a timer while no
  objective follows an entity.
- A map cleanup (`game.CleanUpMap`) is not the death of every entity: during it, `onRemove` does not run. After it every objective is gone
  (reason `"map_changed"`) and the `gry_objective` entities of the map register themselves again if they start active.
- `filter` is asked when something is sent, not all the time. If what a player may see changes, call `RefreshObjectives`.

## Campaign objectives

The maps of Half-Life 2 and of its two episodes give GryMod objectives by themselves: the way out of each map, the key weapons and vehicles, the steps of the
story that the game marks, and for some maps a hand-written chain of steps. No code is needed on your side. A third party can add objectives to any map, or
replace the ones GryMod ships. Everything goes through the objectives above, so the HUD, the radar, the map and the hooks (`GryMod_ObjectiveAdded`,
`GryMod_ObjectiveChanged`, `GryMod_ObjectiveRemoved`) work the same way.

### How it works

- The data of a map is a file, `lua/grymod/campaign/<game>/<map>.lua` (`hl2`, `ep1`, `ep2`). It is read **only for the map being played**, the first time
  it is needed. A map with no file does nothing.
- When the map starts, the first step of each chain, the independent steps and the way out are listed. Only the **current** step of a chain is listed: the
  next one appears when the previous one is done (`after`). A step that is done is shown as done for a few seconds, then it leaves the list.
- What finishes a step is listened for **only while a step of that kind waits**. The map's own scripts send inputs to named entities (a door `Open`, a
  relay `Trigger`...): GryMod watches `GM:AcceptInput`, looked up by input name first. The other kinds use `WeaponEquip`, `PlayerCanPickupItem`,
  `PlayerEnteredVehicle`, `PlayerUse`, `OnNPCKilled`, `EntityRemoved` and `ShutDown`. When nothing waits for a kind its hook is removed. Nothing runs on
  `Think`.
- The main objective (`SetMainObjective`) is the first primary step that is listed; the way out when nothing else is left. The objectives are the same for
  every player (the `filter` of the objectives API is still yours to use on a copy).
- The map's own "game over" messages (a dead ally, a lost vehicle) set the primary steps to `"failed"`. A failure is not saved: the game goes back to its
  last save.

### The settings

| setting | default | meaning |
|---|---|---|
| `gry_campaign_objectives` | `1` | Administrators. `0`: nothing runs and no data is read; the objectives of the campaign are taken away at once |
| `gry_campaign_secrets` | `0` | Administrators. `1`: the hidden items of a map (the game's own "lambda caches" and similar) are counted in ONE objective, `Secrets 3/7`, that is not shown on the radar or the screen. Never listed one by one |
| `gry_campaign_reset` | | Console command (administrators). Forgets what is saved for the running map, `gry_campaign_reset all` for every map |

### What is saved, and its limit

A quickload restarts the Lua of the map, so the steps that are done are saved on the server (its sql database, one row for each map) when they change. When
the map starts, GryMod reads them, asks the world what it already proves (a weapon a player has, a vehicle he is in; this only ever adds a step to the done
ones), and also counts as done every step before a done step.

The limit: the record belongs to the **map**, not to a save game. A quickload of an earlier moment of the same map leaves later steps marked done, and a new
game starts with what the last game did. Type `gry_campaign_reset` then.

### The data of a map

```lua
-- lua/grymod/campaign/hl2/my_map.lua (what GryMod ships has this shape)
return {
	objectives = {
		{
			id = "hl2c.my_map.door", title = "Get out of the back room", description = "Wait until the door opens.", primary = true,
			pos = Vector(-3497, -460, 22),
			via = {Vector(-3800, -470, 22)},
			after = "hl2c.my_map.checkpoint",
			complete = {kind = "input", entity = "barney_door_2", input = "Open"},
			fail = {kind = "input", entity = "alarm_message", input = "ShowMessage"},
			tr = {fr = {title = "Sortir de l'arriere-salle", description = "Attendez que la porte s'ouvre."}},
		},
	},
	fail_events = {{entity = "killed_critical_npc", input = "ShowMessage"}},
}
```

| field | meaning |
|---|---|
| `id`, `title`, `description`, `primary` | as for `RegisterObjective` (`primary` is `true` by default). The ids of the data GryMod ships start with `hl2c.<map>.` |
| `pos` **or** `place` | a `Vector`; or the name of a map entity whose position is used when the objective is listed (`pos` is the fallback) |
| `via` | optional waypoints, an array of up to 16 `Vector`s, as for `RegisterObjective` |
| `after` | the id of the step that must be done first, or an array of ids (all of them). The step is not listed, and not listened for, until then |
| `exit` | `true` for the way out of the map: it is listed from the start when it has no `after`, and waits for its `after` steps like any other step otherwise. A `changelevel` completion is an exit by default |
| `secret` | `true`: a hidden item. Counted in `Secrets n/m` (see the setting), never listed |
| `complete` | what finishes it (below) |
| `fail` | optional, what fails it: a completion of the kind `input`, `killed` or `removed` |
| `tr` | optional translations, `{fr = {title = "...", description = "..."}}`. The English texts are the default; the server's language (`gmod_language`) picks one, and an addon adds a language by giving `tr` |
| `fail_events` (of the map) | `{entity, input}` pairs: the map's own "game over" message; it fails every primary step that waits |

The kinds of completion:

| `kind` | finishes when | fields |
|---|---|---|
| `input` | a named map entity receives an input (a map script sends it) | `entity`, `input` |
| `pickup` | a player takes a weapon (`class = "weapon_..."`) or an item (`class = "item_..."`) | `class` (the class decides; `entity` and `mapid` only help to know where the item lies) |
| `enter_vehicle` | a player gets into a vehicle | `class` (decides) or `entity` |
| `use` | a player presses the use key on an entity | `entity`, or `mapid`, or `class` with `at` (a place; `radius` 8 units by default) |
| `changelevel` | the level ends and a living player stands in the exit trigger that leads to `target` | `target`, optional `entity` (the trigger's name) |
| `removed` | an entity goes (not during a map cleanup or the end of the level) | `entity`, `class` or `mapid` |
| `killed` | an NPC dies | `entity`, `class` or `mapid` |

Any completion can carry `also = {...}` (one alternative, same fields): either one finishes it. An entity made by a `point_template` is renamed by the
engine (`name&0003`); GryMod knows that form and matches it. Names of the map are not case sensitive. `mapid` is `Entity:MapCreationID()`.

### Add or replace objectives (server)

```lua
-- lua/autorun/server/my_addon_campaign.lua
hook.Add("Initialize", "my_addon campaign", function()
	if not (GRYMOD_INSTALLED and GryMod.API.Has("campaign")) then return end

	-- objectives for your own map: the list is yours (replace = true), nothing of GryMod's is read for it
	local ok, why = GryMod.API.RegisterCampaignMap("my_map", {
		{id = "my_addon.start", title = "Find the generator", pos = Vector(100, 0, 0), complete = {kind = "use", entity = "generator_button"}},
		{id = "my_addon.exit", title = "Leave", pos = Vector(900, 0, 0), after = "my_addon.start", complete = {kind = "changelevel", target = "my_next_map"}},
	}, {replace = true, fail_events = {{entity = "alarm_message", input = "ShowMessage"}}})

	-- change ONE objective of a map GryMod ships (the same id replaces it, a new id is added), or take one away with false
	GryMod.API.OverrideCampaignObjective("d1_trainstation_01", "hl2c.d1_trainstation_01.soda", false)
end)
```

- `GryMod.API.RegisterCampaignMap(map, list, opts)`: without `replace`, the list is added to what GryMod ships and an objective of the same id replaces the shipped
  one. Several calls pile up in the order they are made. Returns `true`, or `false` and why (the number and the id of the objective that is wrong); nothing is kept
  when anything is wrong.
- `GryMod.API.OverrideCampaignObjective(map, id, def | false)`: one objective by id. `false` takes it away, and the steps that came after it follow what it
  came after, so the chain goes on.
- `GryMod.API.ResetCampaignProgress([map])`: what `gry_campaign_reset` does.
- Call them before the map starts (an autorun file is fine). Called later for the running map, they start its objectives again.

### What ships

The data of the maps is generated from the entity lists of the game's own maps (names, positions and what a map script sends, which are facts about the
game) with texts written for GryMod. Every map has its way out, its key weapons and vehicles and the story steps the game marks itself; its hidden items are
counted. For the maps whose story is made of doors, scenes and relays, a hand-written chain exists (`d1_trainstation_01`, `d1_canals_01`, `d2_coast_03`,
`ep2_outland_01`); the others are the generated baseline, which finds about half of what a hand-written chain does and none of the steps that only the
player's own action tells apart. A hand-written file says in comments what map fact each step rests on.

The waypoints (`via`) of the way out are the places of the map that its own logic uses to move the story: a trigger that, directly or through a few relays,
starts a story step, and the key weapons. They are few on purpose. Their **order** is not read from the map: it is the shortest way (straight lines) from where the
player arrives through all of them to the exit, and it can be wrong.

The technique of listening to the map's inputs with `GM:AcceptInput` is the one the Lambda gamemode (MIT licence, copyright 2017 Zeh Matt) uses; no code was taken
from it.
