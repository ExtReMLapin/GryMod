-- The alert hexagon of the radar. The original radar has, at the bottom left, an empty hexagonal frame; the movie HUD_SP_HexIcons (loaded in
-- single player) puts a warning sign in it that shows how much the VEHICLES and machines (cars, tanks, helicopters, boats) have noticed the player.
-- The danger bar beside the compass shows the same for the other observers, the soldiers and the aliens (the AI keeps two pairs of numbers: "puppet"
-- and "vehicle"; the bar takes the higher of the first pair, the hexagon the higher of the second). One call of the movie, setStealthExposure(0 to 100),
-- is all it takes: the number is a frame of a clip whose timeline sets the size and the colour (0 to 48 small and green, 49 to 54 amber, 55 to 79 grows
-- to 125 % and turns red, 80 to 94 red, 95 and up red and pulsing).
-- Where the numbers come from: docs/superpowers/plans/2026-11-22-radar-exposure-ai-research.md (the AI, CryAISystem.dll) and
-- 2026-11-22-radar-alert-hexagon-research.md (the movie and the HUD). Loaded after cl_hud_radar_units.lua.
--
-- What GryMod knows is less than the original AI: the radar's contacts say whether a hostile is alerted or fights the player, not how well it sees him.
-- So the target of the meter is the awareness the bar already uses (Radar.Awareness: alerted 0.5, fighting 1), and the AI's own smoothing and memory
-- turn it into the number of the movie. Assumptions, where the research could not say: one meter for all the vehicles together (the original keeps
-- the highest of all its observers), the same forget times for every vehicle (the original gives the tank twice as long), and the draw of the icon
-- at every frame, small and green when nothing is wrong (the original's movie starts with setStealthExposure(0)).

GryMod = GryMod or {}

local Radar = GryMod.FlashRadar
local S = GryMod.RadarShared
local Flash = GryMod.Flash

if not Radar then
	return
end

-- kept by a hot reload: the state of the meter and what the panels hold
local Hex = Radar.Hex or {}
Radar.Hex = Hex

-- The icon types of the radar's contacts (sh_radar.lua, the registry's `type`) that are vehicles and machines for the AI: 2 flying, 3 machines and
-- vehicles. 1 (ground units) and 4 (the Combine mine, a device) stay with the danger bar.
Hex.VEHICLE_TYPES = {[2] = true, [3] = true}

-- ai_SOMSpeedRelaxed and ai_SOMSpeedCombat (CryAISystem.dll): the seconds the meter takes to go up by the target (the code divides the step by them).
Hex.SOM_RELAXED = 1.5
Hex.SOM_COMBAT = 4.5
-- The rise is dt / ((1 - RISE_BIAS * target) * K): a high target is reached sooner.
Hex.RISE_BIAS = 0.5
-- forgetTimeTarget, forgetTimeSeek and forgetTimeMemory of a soldier or a vehicle (the scripts' defaults), in seconds: how long the AI keeps the top
-- level, the middle one and the lowest one of its threat after the meter went down.
Hex.FORGET_TARGET = 16
Hex.FORGET_SEEK = 20
Hex.FORGET_MEMORY = 20
-- The meter falls by a whole unit in FORGET_TARGET / 8 seconds (2), or / 4 (4) while the vehicle is alerted.
Hex.FALL_DIVISOR = 8
Hex.FALL_DIVISOR_ALERT = 4
-- The levels of the threat: the meter above these values holds level 1, 2, 3.
Hex.LEVEL_1, Hex.LEVEL_2, Hex.LEVEL_3 = 0.3, 0.6, 0.9
-- What an addon's call to Hex.Force (or the HUD event radar_exposure) gets without saying: the pulsing red for a few seconds.
Hex.FORCE_LEVEL = 100
Hex.FORCE_SECONDS = 3
Hex.FORCE_MAX_SECONDS = 60

-- The meter of the vehicles: {exposure 0 to 1, level 0 to 3 (the threat held), timeout (seconds left on that level), alert (seconds left of the alert)}.
function Hex.NewState()
	return {exposure = 0, level = 0, timeout = 0, alert = 0}
end

Hex.State = Hex.State or Hex.NewState()
-- What an addon forced: the level (0 to 1) and the seconds left.
Hex.Forced = Hex.Forced or 0
Hex.ForcedLeft = Hex.ForcedLeft or 0
-- The level (0 to 100) the hook was told last.
Hex.Last = Hex.Last or 0

-- Whether the hexagon is switched on (the player's gry_hud_radarhex).
function Hex.Enabled()
	local options = GryMod.HUDOptions

	return not options or options.Enabled("radarhex")
end

-- The two highest awarenesses of a list of contacts {type, sub, marker}: of the soldiers and the like (the danger bar), then of the vehicles and
-- machines (the hexagon). A friend never counts (Radar.Awareness), a crowd does not add up.
function Radar.SplitTargets(contacts)
	local bar, hex = 0, 0

	if not contacts then
		return bar, hex
	end

	local vehicles = Hex.VEHICLE_TYPES

	for i = 1, math.min(#contacts, S.MAX_CONTACTS) do
		local c = contacts[i]
		local awareness = Radar.Awareness(c)

		if vehicles[c.type] then
			if awareness > hex then
				hex = awareness
			end
		elseif awareness > bar then
			bar = awareness
		end
	end

	return bar, hex
end

-- The threat held (0 to 0.9) of a meter: a memory in three levels that empties in FORGET_* seconds each, so that after a fight the hexagon falls fast
-- (the exposure) and then slowly (this).
local function threat(state)
	local level, left = state.level, math.max(state.timeout, 0)

	if level == 1 then
		return left / Hex.FORGET_MEMORY * Hex.LEVEL_1
	elseif level == 2 then
		return (left / Hex.FORGET_SEEK + 1) * Hex.LEVEL_1
	elseif level == 3 then
		return left / Hex.FORGET_TARGET * Hex.LEVEL_1 + Hex.LEVEL_2
	end

	return 0
end

-- What the hexagon shows for a meter: the higher of the exposure and the threat held (0 to 1).
function Hex.Value(state)
	return math.max(state.exposure, threat(state))
end

-- The meter `dt` seconds later, going for `target` (0 to 1, the highest awareness of the vehicles), changed in place. Returns Hex.Value. This is the
-- AI's own rule (CPuppet::UpdatePuppetInternalState): the exposure goes up by dt / ((1 - target / 2) * K) with K 1.5 s, or 4.5 s while the vehicle is
-- in alert, and down by dt / (forget time / 8), or / 4 in alert; above 0.3, 0.6 and 0.9 it holds a threat of level 1, 2 and 3 for 20, 20 and 16 s,
-- each level falling to the one below when its time is out; the alert lasts 36 s after the top level.
function Hex.Step(state, target, dt)
	if dt == nil or dt ~= dt or dt <= 0 then
		return Hex.Value(state)
	end

	if type(target) ~= "number" or target ~= target then
		target = 0
	elseif target > 1 then
		target = 1
	end

	local exposure = state.exposure
	local alerted = state.alert > 0.01

	if target > exposure then
		exposure = math.min(exposure + dt / ((1 - Hex.RISE_BIAS * target) * (alerted and Hex.SOM_COMBAT or Hex.SOM_RELAXED)), target)
	elseif target < exposure then
		exposure = math.max(exposure - dt / (Hex.FORGET_TARGET / (alerted and Hex.FALL_DIVISOR_ALERT or Hex.FALL_DIVISOR)), target)
	end

	state.exposure = exposure

	local level, time = 0, 0

	if exposure > Hex.LEVEL_3 then
		level, time = 3, Hex.FORGET_TARGET
		state.alert = Hex.FORGET_TARGET + Hex.FORGET_MEMORY
	elseif exposure > Hex.LEVEL_2 then
		level, time = 2, Hex.FORGET_SEEK
	elseif exposure > Hex.LEVEL_1 then
		level, time = 1, Hex.FORGET_MEMORY
	end

	-- a level is never lowered while its time runs
	if level > 0 and state.level <= level then
		state.level, state.timeout = level, time
	end

	if state.level > 0 then
		state.timeout = state.timeout - dt

		if state.timeout < 0 then
			state.level = state.level - 1
			state.timeout = state.level == 2 and Hex.FORGET_SEEK or state.level == 1 and Hex.FORGET_MEMORY or 0
		end
	end

	if state.alert > 0 then
		state.alert = math.max(state.alert - dt, 0)
	end

	return Hex.Value(state)
end

-- The level the hook is told, and the movie's number: 0 to 100, cut (not rounded) the way Flash cuts a number given to gotoAndStop, so that 94.9 does
-- not pulse. A small allowance for the error of a product (0.95 * 100 must be 95).
function Hex.Quantise(value)
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return 0
	end

	if value >= 1 then
		return 100
	end

	return math.floor(value * 100 + 1e-6)
end

-- The frame of the clip StealthExposure for a value 0 to 1: the number itself, and frame 1 for 0 (gotoAndStop(0) goes to the first frame).
function Hex.Frame(value)
	return math.max(Hex.Quantise(value), 1)
end

-- Makes the hexagon show at least `level` (0 to 100, 100 without it) for `seconds` (3 without it, 0.1 to 60), whatever the vehicles do: for an addon
-- (a drone's radar, a story event) and for the debug window. Afterwards the hexagon goes back to what the vehicles say.
function Hex.Force(level, seconds)
	if type(level) ~= "number" or level ~= level then
		level = Hex.FORCE_LEVEL
	end

	if type(seconds) ~= "number" or seconds ~= seconds then
		seconds = Hex.FORCE_SECONDS
	end

	Hex.Forced = math.Clamp(level, 0, 100) / 100
	Hex.ForcedLeft = math.Clamp(seconds, 0.1, Hex.FORCE_MAX_SECONDS)
end

-- Forgets the meter of the vehicles (not what an addon forced): nobody feeds it any more, the radar's contacts are off.
function Hex.ForgetMeter()
	local state = Hex.State

	state.exposure, state.level, state.timeout, state.alert = 0, 0, 0, 0
end

-- Forgets the meter, what was forced and the last level told (the player's switch goes off, the tests).
function Hex.Reset()
	Hex.ForgetMeter()
	Hex.Forced, Hex.ForcedLeft, Hex.Last = 0, 0, 0
end

local hookError

-- The level 0 to 100 changed: tells the addons (GryMod_RadarExposure(level, previous)). A listener that fails is told once, it does not stop the HUD.
local function tell(level, previous)
	local ok, err = pcall(hook.Run, "GryMod_RadarExposure", level, previous)

	if not ok and err ~= hookError then
		hookError = err
		ErrorNoHalt("[GryMod] GryMod_RadarExposure listener: " .. tostring(err) .. "\n")
	end
end

-- Each frame the HUD draws (Radar.Feed): moves the meter towards `target` and shows it on the panel. With the switch off the meter is forgotten, the
-- icon is not drawn and rests.
function Hex.Feed(panel, target, dt)
	if not Hex.Enabled() then
		if Hex.Last ~= 0 or Hex.Forced ~= 0 or Hex.State.exposure ~= 0 or Hex.State.level ~= 0 then
			Hex.Reset()
		end

		panel.hexShown = false
		panel:SetExposure(0)

		return
	end

	local value = Hex.Step(Hex.State, target, dt)

	if Hex.ForcedLeft > 0 then
		Hex.ForcedLeft = Hex.ForcedLeft - (dt or 0)

		if Hex.ForcedLeft <= 0 then
			Hex.Forced, Hex.ForcedLeft = 0, 0
		elseif Hex.Forced > value then
			value = Hex.Forced
		end
	end

	panel.hexShown = true
	panel:SetExposure(value)

	local level = Hex.Quantise(value)

	if level ~= Hex.Last then
		local previous = Hex.Last

		Hex.Last = level
		tell(level, previous)
	end
end

-- The panel's side. The icon is the movie HUD_SP_HexIcons, drawn at the same place as the radar's (their Root clips are at the same point of the stage).
-- Radar.HEX_MOVIE = nil or a movie that is not there: no icon, the radar goes on without it.
Radar.HEX_MOVIE = Radar.HEX_MOVIE or "hud_sp_hexicons"

local Panel = Radar.Panel

-- destroy(status) of the movie: 0 normal (its Icons clip on the "stealth" frame, where the exposure clip is), 1 a malfunction (the movie's own bar),
-- 2 flickering. Called with the radar's own state.
function Panel:_hexState(status)
	local hex = self.hex

	if not hex then
		return
	end

	local main = hex.clip

	if status == 1 then
		main:GotoAndStop("malfunction")
	elseif status == 2 then
		main:GotoAndStop("flickering")
	else
		-- the movie's script of its second frame: Icons.gotoAndStop("stealth"); the first frame plays into it
		main:GotoAndStop(2)

		local icons = main:Child("Icons")

		if icons then
			icons:GotoAndStop("stealth")
		end
	end

	-- a new clip starts at its first frame: the level is said again
	self:SetExposure(self.exposure)
end

-- Makes the icon clip of the movie, in the radar's theme. Nothing (no error) when the movie is not there.
function Panel:_startHex()
	local movie = Flash.Load(Radar.HEX_MOVIE)

	if not movie then
		return
	end

	local root = Flash.NewRoot(movie, self.theme)
	local main = root:Child("Root")

	if not main then
		Flash.ReleaseClip(root)

		return
	end

	-- the three clips that only hold the theme's colours
	for _, name in ipairs({"Line", "Over", "Text"}) do
		local holder = root:Child(name)

		if holder then
			holder:SetVisible(false)
		end
	end

	self.hex = {root = root, clip = main}
	self:_hexState(self.status)
end

-- setStealthExposure of the movie: `level` 0 to 1 is the frame of the exposure clip (see Hex.Frame). Only touches the clip when the frame changes.
function Panel:SetExposure(level)
	if type(level) ~= "number" or level ~= level then
		level = 0
	end

	self.exposure = level

	local hex = self.hex
	local icons = hex and hex.clip:Child("Icons")
	local icon = icons and icons:Child("StealthExposure")

	if not icon then
		return
	end

	local frame = Hex.Frame(level)

	if icon:CurrentFrame() ~= frame then
		icon:GotoAndStop(frame)
	end
end
