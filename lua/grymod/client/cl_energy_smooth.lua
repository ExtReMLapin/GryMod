-- The energy the HUD shows, at every frame.
--
-- In the original game the suit gives its HUD the energy at every frame, as a float (setEnergy), and the movie
-- turns it into a bar frame: 1 % of the bar a step. GryMod's energy is a networked float of the server; measured, the
-- client only gets a new value of it about every 0.1 s (9.4 distinct values a second, whatever the tick rate), which
-- drew a sprint in steps of 4 to 5 points. The server now also sends the energy and its rate of change (units a
-- second) in a small unreliable message at every tick (gry_energy, sv_health.lua), and this file does the rest, a
-- little like a game predicts a moving player:
--
--  * prediction: between two updates the value goes on along the rate the server told, so that the bar moves at
--    every frame (144 or 166 a second) and not at every tick (66 a second at best);
--  * reconciliation: a new value or a new rate is a new starting point. The bar joins the prediction in a few
--    frames; a gap of more than a point (a hit, a medkit, a rule that changed) is not smoothed, the bar goes to the
--    value at once, so that a hit is seen when it lands;
--  * safeguards: the prediction is not trusted for more than a quarter of a second without news, there is no
--    prediction while the suit is down or without a rate, nothing goes outside 0 to 100, and a respawn puts the bar on
--    the real value.
--
-- gry_hud_energy_smooth 0 gives the raw value back (the one the server told, with no prediction).

local Smooth = CreateClientConVar("gry_hud_energy_smooth", "1", true, false, "Predict the HUD energy between two server updates (a bar that moves at every frame)")

local MIN, MAX = 0, 100
local TRUST = 0.25 -- seconds a rate is trusted without news
local FOLLOW = 0.05 -- seconds: time constant with which the bar joins the prediction
local SNAP_DOWN = 1 -- points: a bar this far above the prediction goes down at once (a hit)
local SNAP_UP = 2 -- points: a bar this far under the prediction goes up at once
local MAX_DT = 0.1 -- seconds: the longest frame the bar moves by
local STALE = 0.5 -- seconds: a gry_energy value older than this is not used any more (the networked float is)

local ES = GryMod.EnergySmooth or {}
GryMod.EnergySmooth = ES

local Bar = {}
Bar.__index = Bar

function GryMod.NewEnergySmooth()
	return setmetatable({}, Bar)
end

-- The next frame starts on the real value, whatever the bar showed (respawn)
function Bar:Reset()
	self.shown, self.lastTime = nil, nil
	self.value, self.rate, self.anchorTime = nil, nil, nil
end

local function number(x, default)
	if type(x) ~= "number" or x ~= x then
		return default
	end

	return x
end

-- value, rate: what the server last told (rate in units a second); now: the time of the frame; predict: false while
-- the prediction must not be used (the suit is down). Returns the value to draw.
function Bar:Update(value, rate, now, predict)
	value = math.Clamp(number(value, MAX), MIN, MAX)
	rate = predict and number(rate, 0) or 0
	now = number(now, 0)

	-- a clock that went back (new map): start again
	if self.lastTime and now < self.lastTime then
		self:Reset()
	end

	-- a new value, or a new rate, is where the prediction starts from
	if value ~= self.value or rate ~= self.rate or not self.anchorTime then
		self.value, self.rate, self.anchorTime = value, rate, now
	end

	local elapsed = now - self.anchorTime
	local moving = rate ~= 0 and elapsed < TRUST
	local target = value + rate * math.min(elapsed, TRUST)

	if target >= MAX or target <= MIN then
		target, moving = math.Clamp(target, MIN, MAX), false
	end

	local before = self.shown

	if before == nil then
		self.shown, self.lastTime = target, now

		return target
	end

	local dt = math.Clamp(now - self.lastTime, 0, MAX_DT)
	local long = now - self.lastTime > MAX_DT
	self.lastTime = now

	-- a gap that is more than a few frames of smoothing (a hit, a medkit, a long frame): the value, at once
	if long or target < before - SNAP_DOWN or target > before + SNAP_UP then
		self.shown = target

		return target
	end

	-- it goes with the rate while the prediction goes, then joins the prediction by what is left
	local shown = before + (moving and rate * dt or 0)
	shown = shown + (target - shown) * (1 - math.exp(-dt / FOLLOW))

	-- a late update, or a prediction a little too far, must not make the bar go back against its own movement: it
	-- slows down (to a quarter of its speed at least, so that it is never still while it is supposed to move)
	if moving then
		local slowest = before + rate * dt * 0.25

		if rate > 0 then
			shown = math.max(shown, slowest)
		else
			shown = math.min(shown, slowest)
		end
	end

	if rate == 0 and math.abs(target - shown) < 0.005 then
		shown = target
	end

	shown = math.Clamp(shown, MIN, MAX)
	self.shown = shown

	return shown
end

-- ---------------------------------------------------------------------------------------------------------
-- What the HUD asks.
-- ---------------------------------------------------------------------------------------------------------

ES.view = ES.view or GryMod.NewEnergySmooth()
ES.net = ES.net or {}

-- gry_energy: the value, its rate, and when it came
function ES.Receive(value, rate, now)
	local n = ES.net
	n.value, n.rate, n.time = value, rate, now
end

net.Receive("gry_energy", function()
	ES.Receive(net.ReadFloat(), net.ReadFloat(), CurTime())
end)

-- What the server told: the value of the last gry_energy message and its rate, or the networked float (no rate) when
-- there is none, or an old one (the server sends nothing while the bar does not move, and gry_energy_net 0 sends
-- nothing at all).
function ES.Raw(ply, now)
	local n = ES.net
	local age = n.time and now - n.time

	if age and age >= 0 and age < STALE then
		return n.value, n.rate
	end

	return ply:GetNWFloat("GryEnergy"), 0
end

-- The energy to give the HUD's setEnergy.
function ES.Shown(ply, now)
	local value, rate = ES.Raw(ply, now)

	-- a dead player, or the prediction switched off: the value as the server told it
	if not Smooth:GetBool() or ply:Health() <= 0 then
		ES.view:Reset()

		return value
	end

	return ES.view:Update(value, rate, now, not ply:GetNWBool("GryMalfunction", false))
end

function ES.Reset()
	ES.view:Reset()
	ES.net.value, ES.net.rate, ES.net.time = nil, nil, nil
end
