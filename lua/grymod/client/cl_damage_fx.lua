-- What the original Crysis does when the player is hurt (research: docs/superpowers/plans/2026-11-21-damage-feedback-notes.md):
--
-- * armor mode, a hit that costs a fifth of the energy bar or more: the HUD jumps (the "HUD interference" effect: random
--   offsets of up to half 20 pixels, falling away at 4 a second), the screen flashes dark and red for 0.2 s, glitches for
--   0.4 s and shakes for 0.5 s;
-- * the health falling through 25 % and then 20 %: a red tint over 4 s and a radial blur over 6 s (and a shake of 0.4 s at 20 %).
--
-- The HUD jump is the switch gry_hud_damagefx (one of the HUD elements, see cl_hud_options.lua); the screen effects are
-- the switch gry_screenfx. Nothing runs when nothing is happening: the screen hook only exists while an effect plays.

GryMod = GryMod or {}

local FX = {}
GryMod.DamageFx = FX

local screenConVar = CreateClientConVar("gry_screenfx", "1", true, false, "Screen effects of damage: the flash and shake of a heavy armor hit, the red tint and blur at low health")

-- The energy an armor hit must cost: the game's 40 of 200, a fifth of the bar.
FX.ARMOR_COST = 20
FX.ARMOR_SECONDS = 0.5
-- The health zones, as part of the maximum (the game's 40 and 50 of 200).
FX.LOW_CRITICAL = 0.20
FX.LOW_BAND = 0.25
-- The HUD interference: the game's distortion (pixels of the 1024 x 768 stage), its decay a second and its floor.
FX.INTERFERENCE_DISTORTION = 20
FX.INTERFERENCE_DECAY = 4
FX.INTERFERENCE_FLOOR = 0.5

local function number(value)
	if type(value) ~= "number" or value ~= value then
		return nil
	end

	return value
end

-- Seconds of shake an armor hit of this cost gives (0 for none).
function FX.ArmorShake(cost)
	cost = number(cost)

	if cost and cost >= FX.ARMOR_COST then
		return FX.ARMOR_SECONDS
	end

	return 0
end

-- The effect a fall of the health from previous to health starts: 2 when it goes through 20 % or lower from above, 1 when it
-- lands in the 20-25 % band from above 25 %, 0 otherwise (the game starts nothing when the health rises or stays in a zone).
function FX.LowHealthLevel(health, max, previous)
	health, max, previous = number(health), number(max), number(previous)

	if not health or not max or not previous or max <= 0 or health >= previous then
		return 0
	end

	local critical, band = max * FX.LOW_CRITICAL, max * FX.LOW_BAND

	if health <= critical then
		return previous > critical and 2 or 0
	end

	if health < band then
		return previous >= band and 1 or 0
	end

	return 0
end

-- One frame of the interference: it loses decay * dt of itself and is gone under the floor.
function FX.InterferenceStep(strength, dt)
	strength = strength - strength * FX.INTERFERENCE_DECAY * dt

	if strength < FX.INTERFERENCE_FLOOR then
		return 0
	end

	return strength
end

-- The jump of the HUD for a strength and two random numbers of 0 to 1: plus and minus half the strength.
function FX.InterferenceOffsets(strength, rx, ry)
	if strength <= 0 then
		return 0, 0
	end

	return (rx - 0.5) * strength, (ry - 0.5) * strength
end

local function ramp(t, seconds)
	return math.Clamp(1 - t / seconds, 0, 1)
end

-- The screen after an armor hit, t seconds later (nil when over): brightness 0.3 back to 1 and the red tint 0.5 back to 0
-- in 0.2 s, the glitch 1 back to 0 in 0.4 s.
function FX.ArmorFlash(t)
	if t < 0 or t >= FX.ARMOR_SECONDS then
		return nil
	end

	local dark = ramp(t, 0.2)

	return {brightness = 1 - 0.7 * dark, tint = 0.5 * dark, glitch = ramp(t, 0.4)}
end

-- The screen t seconds after the health went low (nil when over): the radial blur 1 back to 0 in 6 s, the red tint 0.5
-- back to 0 in 4 s.
function FX.LowHealthFx(level, t)
	if level ~= 1 and level ~= 2 or t < 0 or t >= 6 then
		return nil
	end

	return {blur = ramp(t, 6), tint = 0.5 * ramp(t, 4)}
end

-- The shake of the camera: a replaceable function (the tests record it). The amplitude and frequency are GryMod's own
-- scale for util.ScreenShake; the original's data are a shift of 0.07, 0.4 to 0.5 s, frequency 20 (armor) and 40 (health).
function FX.Shake(amplitude, frequency, seconds)
	local ply = LocalPlayer()

	if IsValid(ply) then
		util.ScreenShake(ply:GetPos(), amplitude, frequency, seconds, 64)
	end
end

function FX.NewState()
	return {jolt = 0}
end

function FX.Reset(state)
	state.jolt = 0
	state.armorAt, state.lowAt, state.lowLevel = nil, nil, nil
	state.health, state.energy = nil, nil
	FX.Sync(state, 0)
end

-- Looks at the player once a frame: sample = {health, max, energy (0-100), armor (the suit is in armor mode)}, now in
-- seconds, options = {hud, screen} (which effects are switched on). The first sample only sets the reference.
function FX.Observe(state, sample, now, options)
	local health, energy = sample.health, sample.energy
	local lastHealth, lastEnergy = state.health, state.energy
	state.health, state.energy = health, energy

	if lastHealth == nil then
		return
	end

	local started = false

	if sample.armor and lastEnergy and energy < lastEnergy and FX.ArmorShake(lastEnergy - energy) > 0 then
		if options.hud then
			state.jolt = FX.INTERFERENCE_DISTORTION
		end

		if options.screen then
			state.armorAt = now
			started = true
			FX.Shake(1.5, 20, FX.ARMOR_SECONDS)
		end
	end

	if options.screen then
		local level = FX.LowHealthLevel(health, sample.max, lastHealth)

		if level > 0 then
			state.lowAt, state.lowLevel = now, level
			started = true

			if level == 2 then
				FX.Shake(1, 40, 0.4)
			end
		end
	end

	if started then
		FX.Sync(state, now)
	end
end

-- The jump of the HUD this frame (stage pixels), and the decay of its strength. The two random numbers are for the tests.
function FX.HudOffset(state, dt, rx, ry)
	if state.jolt <= 0 then
		return 0, 0
	end

	local x, y = FX.InterferenceOffsets(state.jolt, rx or math.random(), ry or math.random())
	state.jolt = FX.InterferenceStep(state.jolt, dt)

	return x, y
end

-- What the screen shows at this time, or nil when no effect is running: the armor flash and the low health tint add up.
function FX.ScreenParams(state, now)
	local flash = state.armorAt and FX.ArmorFlash(now - state.armorAt)
	local low = state.lowAt and FX.LowHealthFx(state.lowLevel, now - state.lowAt)

	if not flash and not low then
		return nil
	end

	return {
		brightness = flash and flash.brightness or 1,
		tint = math.max(flash and flash.tint or 0, low and low.tint or 0),
		glitch = flash and flash.glitch or 0,
		blur = low and low.blur or 0
	}
end

local HOOK = "GryDamageFx"
local frame = CLIENT and CreateMaterial("gry_damagefx_frame", "UnlitGeneric", {
	["$basetexture"] = "_rt_FullFrameFB",
	["$translucent"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
	["$ignorez"] = 1
})

local colour = {
	["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
	["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1,
	["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0
}

local current

-- The post effect: the red tint and the dark flash by colour modify, the radial blur as two enlarged copies of the
-- picture over it, the glitch as a few strips of the picture pushed sideways.
local function paint()
	local params = current and FX.ScreenParams(current, RealTime())

	if not params then
		FX.Sync(current or FX.NewState(), RealTime())

		return
	end

	if params.tint > 0 or params.brightness < 1 then
		colour["$pp_colour_addr"] = params.tint * 0.3
		colour["$pp_colour_colour"] = 1 - params.tint * 0.6
		colour["$pp_colour_brightness"] = (params.brightness - 1) * 0.5
		DrawColorModify(colour)
	end

	local w, h = ScrW(), ScrH()

	if params.blur > 0 then
		render.UpdateScreenEffectTexture()
		surface.SetMaterial(frame)

		for i = 1, 2 do
			local grow = (0.03 * i) * params.blur * 1.5
			surface.SetDrawColor(255, 255, 255, (i == 1 and 110 or 70) * params.blur)
			surface.DrawTexturedRect(-w * grow, -h * grow, w * (1 + 2 * grow), h * (1 + 2 * grow))
		end
	end

	if params.glitch > 0 then
		render.UpdateScreenEffectTexture()
		local texture = render.GetScreenEffectTexture()

		for _ = 1, 3 do
			local y = math.random(0, h - 1)
			local band = math.random(math.max(2, math.floor(h / 40)), math.max(3, math.floor(h / 12)))
			render.SetScissorRect(0, y, w, math.min(h, y + band), true)
			render.DrawTextureToScreenRect(texture, (math.random() - 0.5) * w * 0.12 * params.glitch, 0, w, h)
			render.SetScissorRect(0, 0, 0, 0, false)
		end
	end
end

-- Adds the post effect while something plays and takes it away when it is over.
function FX.Sync(state, now)
	local running = FX.ScreenParams(state, now) ~= nil
	local hooked = hook.GetTable().RenderScreenspaceEffects and hook.GetTable().RenderScreenspaceEffects[HOOK] ~= nil

	if running then
		current = state

		if not hooked then
			hook.Add("RenderScreenspaceEffects", HOOK, paint)
		end
	elseif hooked then
		hook.Remove("RenderScreenspaceEffects", HOOK)
	end
end

-- The state of the local player, and the two switches (the HUD jump is one of the HUD elements).
FX.State = FX.NewState()

-- One table, filled in again at each call: this is read every frame and must not make garbage.
local switches = {hud = true, screen = true}

function FX.Options()
	local options = GryMod.HUDOptions

	switches.hud = not options or options.Enabled("damagefx")
	switches.screen = screenConVar:GetBool()

	return switches
end
