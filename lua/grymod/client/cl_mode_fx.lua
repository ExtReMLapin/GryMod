-- The screen effect of a suit mode change (client side). The original game plays the effect graph of the mode that is entered
-- (research: docs/superpowers/plans/2026-11-21-suit-mode-fx.md): a short colour grade that rises and falls, with one tint
-- per mode:
--
--   * armor:    blue   +0.15 at 0.1 s, gone at 0.5 s
--   * speed:    bright +0.2 (all three channels) at 0.15 s, gone at 0.5 s
--   * strength: red    +0.2 at 0.2 s, gone at 0.6 s
--
-- The camouflage has its own effect (cl_cloak_fx.lua, the graph "suit_cloakmode", 1.7 s) and is not repeated here. The
-- graphs also hold a white and a dark red fade-in, but nothing starts it in the demo's data: it is not drawn.
--
-- How it works: the tint is part of the HUD event "mode" (cl_api_hud_events.lua), which plays it together with the mode's
-- activation sound. Player:SetNanosuitMode (cl_hud.lua) calls the event at every change of mode, and asks for the tint (data.tint)
-- only when TintDue says so: not the first time the mode is known, not while the player is dead, in the first second after a
-- respawn (the server puts the suit back in armor then), nor while the suit is down (sv_malfunction.lua forces armor mode). The
-- bookkeeping those rules need rides on events, nothing runs at every frame: the respawn message of the server (net "gry_spawn",
-- cl_hud.lua calls FX.Spawned), the arrival in game (InitPostEntity) and the networked flag "GryMalfunction" turning on
-- (EntityNetworkedVarChanged). The post effect hook exists only while an effect runs and takes itself away at the end. Switch:
-- gry_screenfx, the same as the damage effects of cl_damage_fx.lua.

GryMod = GryMod or {}

local FX = GryMod.ModeFX or {}
GryMod.ModeFX = FX

local Modes = GryMod.Modes

-- Seconds after a respawn in which a change of mode is the server's own (the suit goes back to armor), not a choice.
FX.SPAWN_GRACE = 1

-- Seconds after a change in which a suit that turns out to be down (the flag "GryMalfunction" turns on), or a player who turns out to
-- have just respawned (the message "gry_spawn"), takes the effect back: the server sets the flag just before it forces armor mode, and
-- puts the suit back in armor just before it sends the respawn message, but the messages reach the client in the order they like
-- (seen in a test: the mode first, the flag a frame later at 20 fps).
FX.WITHDRAW = 0.3

-- Per mode, the flow graph's numbers: seconds up to the peak, seconds in all, and the colour offsets added to the picture at
-- the peak (0 to 1). The graph moves one of the grade's cyan, yellow or black values from 0 to -0.15 or -0.2 and back; the
-- engine's colour matrix turns a negative cyan into red, a negative yellow into blue and a negative black into all three.
FX.PROFILES = {
	[Modes.ARMOR] = {rise = 0.1, total = 0.5, r = 0, g = 0, b = 0.15},
	[Modes.SPEED] = {rise = 0.15, total = 0.5, r = 0.2, g = 0.2, b = 0.2},
	[Modes.STRENGTH] = {rise = 0.2, total = 0.6, r = 0.2, g = 0, b = 0}
}

local PROFILES = FX.PROFILES

-- the order in which a state's running effects are summed (no pairs() in the frame loop)
local ORDER = {Modes.ARMOR, Modes.SPEED, Modes.STRENGTH}

local function level(profile, t)
	if t <= 0 or t >= profile.total then
		return 0
	end

	if t < profile.rise then
		return t / profile.rise
	end

	return (profile.total - t) / (profile.total - profile.rise)
end

-- Seconds an effect lasts (0 for a mode that has none).
function FX.Duration(mode)
	local profile = PROFILES[mode]

	return profile and profile.total or 0
end

-- The colour offsets (red, green, blue, 0 to 1) of a mode's effect t seconds after the change.
function FX.Offsets(mode, t)
	local profile = PROFILES[mode]

	if not profile then
		return 0, 0, 0
	end

	local k = level(profile, t)

	return profile.r * k, profile.g * k, profile.b * k
end

--------------------------------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------------------------------

-- starts: mode -> the time its effect began; spawnAt: when the respawn message (or the arrival in game) was last seen, nil when none
-- was (the player has been there for a while); startedMode, startedAt: the last effect Play started (Withdraw may take it back).
function FX.NewState()
	return {starts = {}, spawnAt = nil}
end

-- The clock of the effects: replaceable, the tests freeze it.
function FX.Now()
	return RealTime()
end

-- The sum of the running effects at this time: red, green, blue offsets, or nil when nothing runs (the finished ones are
-- forgotten here).
function FX.Params(state, now)
	local r, g, b, running = 0, 0, 0, false
	local starts = state.starts

	for i = 1, #ORDER do
		local mode = ORDER[i]
		local start = starts[mode]

		if start then
			local profile = PROFILES[mode]
			local t = now - start

			if t >= profile.total then
				starts[mode] = nil
			else
				local k = level(profile, t)
				r, g, b, running = r + profile.r * k, g + profile.g * k, b + profile.b * k, true
			end
		end
	end

	if not running then
		return nil
	end

	return math.min(r, 1), math.min(g, 1), math.min(b, 1)
end

--------------------------------------------------------------------------------------------------------------------
-- The post effect
--------------------------------------------------------------------------------------------------------------------

local HOOK = "GryModeFx"

local colour = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
}

local current

local function hooked()
	local hooks = hook.GetTable().RenderScreenspaceEffects

	return hooks ~= nil and hooks[HOOK] ~= nil
end

local function paint()
	if GryMod.Minimap and GryMod.Minimap.Capture and GryMod.Minimap.Capture.IsCapturing() then return end

	local r, g, b = FX.Params(current or FX.State, FX.Now())

	if not r then
		hook.Remove("RenderScreenspaceEffects", HOOK)

		return
	end

	if r > 0 or g > 0 or b > 0 then
		colour["$pp_colour_addr"], colour["$pp_colour_addg"], colour["$pp_colour_addb"] = r, g, b
		DrawColorModify(colour)
	end
end

-- Starts the effect of a mode at this time (again from zero when it already runs) and puts the post hook on.
function FX.Start(state, mode, now)
	if not PROFILES[mode] then
		return
	end

	state.starts[mode] = now
	current = state

	if not hooked() then
		hook.Add("RenderScreenspaceEffects", HOOK, paint)
	end
end

--------------------------------------------------------------------------------------------------------------------
-- The HUD event "mode" (cl_api_hud_events.lua): the tint of the mode entered and the mode's activation sound, played together.
-- Player:SetNanosuitMode (cl_hud.lua) is the trigger and asks for the tint only when the change is a real one (TintDue).
--------------------------------------------------------------------------------------------------------------------

-- The modes the event knows, by the name data.mode uses.
FX.NAMES = {armor = Modes.ARMOR, speed = Modes.SPEED, strength = Modes.STRENGTH, cloak = Modes.CLOAK}

-- The mode a data.mode value means: its name ("armor", "speed", "strength", "cloak") or its number (GryMod.Modes); nil for
-- anything else (the drop is no mode).
function FX.ModeFromData(value)
	if isstring(value) then
		return FX.NAMES[value]
	end

	for _, mode in pairs(FX.NAMES) do
		if value == mode then
			return mode
		end
	end

	return nil
end

-- The name data.mode carries for a mode number, or nil for what is no mode.
function FX.NameOf(mode)
	for name, value in pairs(FX.NAMES) do
		if value == mode then
			return name
		end
	end

	return nil
end

-- Whether a change of the suit from `previous` to `mode` gets the tint (the sound plays in any case). sample = {alive, malfunction}.
-- Not for a mode without a tint, the same mode again, or the first mode known (nothing before it); not while dead, nor in the
-- first second after a respawn (the server's own change back to armor), nor while the suit is down (sv_malfunction.lua forces armor
-- mode).
function FX.TintDue(state, previous, mode, sample, now)
	if not PROFILES[mode] or previous == nil or previous == mode then
		return false
	end

	if not sample.alive or sample.malfunction then
		return false
	end

	return state.spawnAt == nil or now - state.spawnAt >= FX.SPAWN_GRACE
end

-- Takes back the tint Play started less than FX.WITHDRAW seconds ago: the change that started it turns out to be the server's own
-- (a suit that went down, a player who respawned), not a choice. Nothing to take back: nothing happens.
function FX.Withdraw(state, now)
	if state.startedMode and now - state.startedAt < FX.WITHDRAW then
		state.starts[state.startedMode] = nil
		state.startedMode = nil
	end
end

-- The player respawned at this time (the server's message "gry_spawn", or the arrival in game): the first second holds the tint back
-- (TintDue), and the mode change that came just before the message is the respawn's own (Withdraw).
function FX.Spawn(state, now)
	state.spawnAt = now
	FX.Withdraw(state, now)
end

-- Starts the tint of a mode on a state and remembers it (Withdraw may take it back). Returns whether the mode has a tint.
function FX.Play(state, mode, now)
	if not PROFILES[mode] then
		return false
	end

	FX.Start(state, mode, now)
	state.startedMode, state.startedAt = mode, now

	return true
end

local switch = GetConVar("gry_screenfx") or CreateClientConVar("gry_screenfx", "1", true, false,
	"Screen effects of damage and of a suit mode change: the flash and shake of a heavy armor hit, the red tint and blur at low health, the colour tint of the new mode")

function FX.Enabled()
	return switch:GetBool()
end

FX.State = FX.State or FX.NewState()

-- one table, filled in again at each mode change: no garbage
local sample = {alive = false, malfunction = false}

-- Whether the local player's change of mode from `previous` to `mode` gets the tint, from what the player is now.
function FX.TintNow(previous, mode)
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return false
	end

	sample.alive = ply:Alive()
	sample.malfunction = ply:GetNW2Bool("GryMalfunction", false)

	return FX.TintDue(FX.State, previous, mode, sample, FX.Now())
end

-- The respawn message of the server arrived (cl_hud.lua, net "gry_spawn").
function FX.Spawned()
	FX.Spawn(FX.State, FX.Now())
end

-- The suit goes down: the game calls EntityNetworkedVarChanged when a NW2 variable changes (nothing is polled), with the NEW value as
-- the fourth argument. Only the flag of the local player turning on matters.
hook.Add("EntityNetworkedVarChanged", HOOK, function(ent, name, _, down)
	if name == "GryMalfunction" and down == true and ent == LocalPlayer() then
		FX.Withdraw(FX.State, FX.Now())
	end
end)

-- Reports for other addons: GryMod_MalfunctionStart(ply) and GryMod_MalfunctionEnd(ply), the client twins of the server hooks of the same
-- names. This side only sees the networked flag change, so it knows the player and nothing else (no seconds, no reason). It is told for every
-- player the client knows, not only the local one. The same game hook as above, so nothing new runs at every frame. A change is a flag that
-- really goes from false to true or back: an old value of nil is the full update that tells the client what a player already is (when he comes
-- into view, or when we join), it is not an event. A listener that fails is told once on screen and does not stop the game's other change
-- hooks (the mode tint above, the cloak, the suit flag), which a plain hook.Run inside this one would do.
local reportedError

hook.Add("EntityNetworkedVarChanged", "GryMalfunctionReport", function(ent, name, old, down)
	if name ~= "GryMalfunction" or old == down or (down ~= true and down ~= false) or (old ~= true and old ~= false) then
		return
	end

	local ok, err = pcall(hook.Run, down and "GryMod_MalfunctionStart" or "GryMod_MalfunctionEnd", ent)

	if not ok and err ~= reportedError then
		reportedError = err
		ErrorNoHalt("[GryMod] GryMod_Malfunction" .. (down and "Start" or "End") .. " listener: " .. tostring(err) .. "\n")
	end
end)

-- The arrival in game counts as a respawn: the server's answer with the mode (sv_system.lua) must not tint.
hook.Add("InitPostEntity", HOOK, function()
	FX.Spawn(FX.State, FX.Now())
end)

-- The first version looked at the player at every frame: a copy of it left by an older load of the file goes.
hook.Remove("Think", HOOK)
