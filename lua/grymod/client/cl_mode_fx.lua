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
-- How it works: a Think hook reads the mode of the local player (the field NanosuitMode that cl_hud.lua keeps, so nothing
-- depends on a network message) and starts the effect of the mode when it changes. Not played the first time the mode is
-- seen, while the player is dead, in the first second after a respawn (the server puts the suit back in armor then),
-- nor while the suit is down (sv_malfunction.lua forces armor mode). The post effect hook exists only while an effect
-- runs and takes itself away at the end. Switch: gry_screenfx, the same as the damage effects of cl_damage_fx.lua.

GryMod = GryMod or {}

local FX = GryMod.ModeFX or {}
GryMod.ModeFX = FX

local Modes = GryMod.Modes

-- Seconds after a respawn in which a change of mode is the server's own (the suit goes back to armor), not a choice.
FX.SPAWN_GRACE = 1

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

-- starts: mode -> the time its effect began; mode: the last mode seen; aliveAt: when the player was last seen coming alive.
function FX.NewState()
	return {starts = {}, mode = nil, aliveAt = nil}
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
-- Watching the player
--------------------------------------------------------------------------------------------------------------------

-- Looks at the player once a frame: sample = {mode, alive, malfunction}, now in seconds, enabled = the switch. Returns the mode
-- whose effect it started, if any. The first mode seen is only the reference, and a mode followed while dead or with the
-- switch off is not played later.
function FX.Observe(state, sample, now, enabled)
	local mode = sample.mode

	if not sample.alive then
		state.aliveAt = nil

		if mode ~= nil then
			state.mode = mode
		end

		return nil
	end

	if not state.aliveAt then
		state.aliveAt = now
	end

	if mode == nil then
		return nil
	end

	local previous = state.mode
	state.mode = mode

	if previous == nil or previous == mode or not enabled or sample.malfunction then
		return nil
	end

	if now - state.aliveAt < FX.SPAWN_GRACE or not PROFILES[mode] then
		return nil
	end

	FX.Start(state, mode, now)

	return mode
end

local switch = GetConVar("gry_screenfx") or CreateClientConVar("gry_screenfx", "1", true, false,
	"Screen effects of damage and of a suit mode change: the flash and shake of a heavy armor hit, the red tint and blur at low health, the colour tint of the new mode")

function FX.Enabled()
	return switch:GetBool()
end

FX.State = FX.State or FX.NewState()

-- one table, filled in again each frame: no garbage
local sample = {mode = nil, alive = false, malfunction = false}

hook.Add("Think", HOOK, function()
	local ply = LocalPlayer()

	if not IsValid(ply) then
		return
	end

	sample.mode = ply.NanosuitMode
	sample.alive = ply:Alive()
	sample.malfunction = ply:GetNWBool("GryMalfunction", false)

	FX.Observe(FX.State, sample, FX.Now(), FX.Enabled())
end)
