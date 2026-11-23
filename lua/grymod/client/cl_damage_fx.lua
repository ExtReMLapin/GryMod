-- What the original Crysis does when the player is hurt (research: docs/superpowers/plans/2026-11-21-damage-feedback-notes.md):
--
-- * armor mode, a hit that costs a fifth of the energy bar or more: the HUD jumps (the "HUD interference" effect: random
--   offsets of up to half 20 pixels, falling away at 4 a second), the screen flashes dark and red for 0.2 s, glitches for
--   0.4 s and shakes for 0.5 s;
-- * the health falling through 25 % and then 20 %: a red tint over 4 s and a radial blur over 6 s (and a shake of 0.4 s at 20 %);
-- * any lighter hit the armor takes: a small shake of 0.35 s (the original's cl_hitShake, played on every hit of the player; the Half-Life 2
--   punch that stands in for it on the health does not come when the armor takes the whole hit).
--
-- The HUD jump is the switch gry_hud_damagefx (one of the HUD elements, see cl_hud_options.lua); the screen effects are
-- the switch gry_screenfx. Nothing runs when nothing is happening: the screen hook only exists while an effect plays.
--
-- These effects are HUD events of the extension API (cl_api_hud_events.lua: armor_hit, decloak, low_health, jam). The functions
-- here are what an event runs (FX.Events); the game's own triggers (the observer below, the shot out of the camouflage) call the
-- event through FX.Emit, so that a picture and its sound have ONE path (the armor hit's sound is played by the same event).

GryMod = GryMod or {}

local FX = {}
GryMod.DamageFx = FX

local screenConVar = CreateClientConVar("gry_screenfx", "1", true, false, "Screen effects of damage: the flash and shake of a heavy armor hit, the red tint and blur at low health")
local hitShakeConVar = CreateClientConVar("gry_hit_shake", "1", true, false, "A hit the armor takes that is lighter than a heavy one (under a fifth of the bar) gives a small shake of the screen, as every hit does in the original game (needs the screen effects)")
local decloakConVar = CreateClientConVar("gry_decloak_glitch", "1", true, false, "Firing out of the camouflage plays the armor hit effect (flash, HUD jump, shake) at any energy; 0: nothing plays")

-- The energy an armor hit must cost: the game's 40 of 200, a fifth of the bar.
FX.ARMOR_COST = 20
FX.ARMOR_SECONDS = 0.5
-- The small shake of a lighter hit: the original's cl_hitShake lasts 0.35 s. A drop of the bar under SMALL_HIT_MIN (of 100) is noise, not a hit
-- (in armor mode nothing else takes energy).
FX.SMALL_SECONDS = 0.35
FX.SMALL_HIT_MIN = 1
-- After a deliberate emptying of the bar (firing out of the camouflage) the drop is expected within this many seconds: it is
-- not an armor hit.
FX.EMPTIED_SECONDS = 1
FX.EMPTIED_BELOW = 1 -- the energy (0-100) the emptied bar falls under
-- The health zones, as part of the maximum (the game's 40 and 50 of 200).
FX.LOW_CRITICAL = 0.20
FX.LOW_BAND = 0.25
-- The HUD interference: the game's distortion (pixels of the 1024 x 768 stage), its decay a second and its floor.
FX.INTERFERENCE_DISTORTION = 20
FX.INTERFERENCE_DECAY = 4
FX.INTERFERENCE_FLOOR = 0.5
-- The jam event (the HUD interference kept going): how long it lasts by default and at most (seconds), and how hard the HUD shakes
-- (stage pixels, the unit of the interference's distortion).
FX.JAM_SECONDS = 2
FX.JAM_MAX_SECONDS = 60
FX.JAM_STRENGTH = 12

-- The clock of the effects: replaceable, the tests freeze it.
function FX.Now()
	return RealTime()
end

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

-- Seconds of the small shake a hit that costs this much gives: for a hit the armor takes that is not a heavy one (0 for none).
function FX.SmallHitShake(cost)
	cost = number(cost)

	if cost and cost >= FX.SMALL_HIT_MIN and cost < FX.ARMOR_COST then
		return FX.SMALL_SECONDS
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
	state.jamLeft = nil
	state.armorAt, state.lowAt, state.lowLevel, state.emptiedUntil = nil, nil, nil, nil
	state.health, state.energy = nil, nil
	FX.Sync(state, 0)
end

-- The armor hit effect: the HUD jumps (options.hud), the screen flashes and shakes (options.screen). Returns whether the
-- screen effect started (the caller then calls FX.Sync).
function FX.ArmorImpact(state, now, options)
	if options.hud then
		state.jolt = FX.INTERFERENCE_DISTORTION
	end

	if options.screen then
		state.armorAt = now
		FX.Shake(1.5, 20, FX.ARMOR_SECONDS)

		return true
	end

	return false
end

-- The player fires out of the camouflage (GryMod.CloackAttack): the suit goes back to armor mode and the bar is emptied.
-- That is not a hit, so the drop of the bar is marked here and Observe does not read it as one; the effect of a hit plays
-- by choice (gry_decloak_glitch, the original's glitch), at any energy: before, it only played when the energy lost was
-- 20 or more, which is the energy the player had.
function FX.Decloak(state, now, options)
	state.emptiedUntil = now + FX.EMPTIED_SECONDS

	if decloakConVar:GetBool() and FX.ArmorImpact(state, now, options or FX.Options()) then
		FX.Sync(state, now)
	end
end

-- Looks at the player once a frame: sample = {health, max, energy (0-100), armor (the suit is in armor mode), malfunction
-- (the suit is down: its start empties the bar)}, now in seconds, options = {hud, screen} (which effects are switched on).
-- The first sample only sets the reference. Only an energy drop that costs something is an armor hit: not the bar emptied by
-- a decloak (FX.Decloak) nor by the start of a malfunction.
function FX.Observe(state, sample, now, options)
	local health, energy = sample.health, sample.energy
	local lastHealth, lastEnergy = state.health, state.energy
	state.health, state.energy = health, energy

	if lastHealth == nil then
		return
	end

	local dropped = lastEnergy and energy < lastEnergy
	local emptied = false

	if state.emptiedUntil then
		-- the drop to nothing is the emptied bar (the slow drain of the camouflage before it is not), and it is only expected once
		emptied = dropped and energy < FX.EMPTIED_BELOW

		if emptied or now >= state.emptiedUntil then
			state.emptiedUntil = nil
		end
	end

	if sample.armor and dropped and not emptied and not sample.malfunction then
		if FX.ArmorShake(lastEnergy - energy) > 0 then
			-- the picture only: the sound of an armor hit is the server's decision (sv_health.lua, Mech.ArmorHitSoundDue), it comes with
			-- the same event (cl_sounds.lua) and has its own rule: the two rules of the original game are not the same
			FX.Emit("armor_hit", {sound = false}, state, now, options)
		elseif options.hit == true and FX.SmallHitShake(lastEnergy - energy) > 0 then
			-- a lighter hit: the same event, with its small look (nothing but the shake)
			FX.Emit("armor_hit", {sound = false, small = true}, state, now, options)
		end
	end

	local level = FX.LowHealthLevel(health, sample.max, lastHealth)

	if level > 0 then
		FX.Emit("low_health", {level = level}, state, now, options)
	end
end

-- Says that a HUD event is due: the game's own triggers call the extension API like any addon does (cl_api_hud_events.lua plays
-- the event with the state of the local player). The state, the time and the options come along for the tests, which put another
-- Emit here to run the event on a state of their own.
function FX.Emit(name, data)
	local API = GryMod.API

	if API and API.HUDEvent then
		return API.HUDEvent(name, data)
	end

	return false
end

-- The low health effect, level 1 (the 20-25 % band) or 2 (under 20 %: the shake as well): the red tint and the blur. The screen
-- switch only. Returns whether it started.
function FX.LowHealth(state, level, now, options)
	if (level ~= 1 and level ~= 2) or not options.screen then
		return false
	end

	state.lowAt, state.lowLevel = now, level

	if level == 2 then
		FX.Shake(1, 40, 0.4)
	end

	FX.Sync(state, now)

	return true
end

-- The jam: the HUD trembles for this many seconds (the interference kept up at JAM_STRENGTH, then it falls away). The HUD jump
-- switch only. Returns whether it started.
function FX.Jam(state, seconds, options)
	if not options.hud then
		return false
	end

	state.jamLeft = math.Clamp(tonumber(seconds) or FX.JAM_SECONDS, 0.1, FX.JAM_MAX_SECONDS)

	return true
end

-- What each HUD event runs, on a state: function(state, now, data, options). The extension API's handlers are in
-- cl_api_hud_events.lua and call these with the state of the local player.
FX.Events = {}

-- data.visual = false: no picture (the sound alone), data.sound = false: no sound (the picture alone)
function FX.Events.armor_hit(state, now, data, options)
	if data.small == true then
		-- the small look of a light hit: the shake alone (the screen switch and the hit shake switch), no flash and no jump of the HUD
		if data.visual ~= false and options.screen and options.hit ~= false then
			FX.Shake(0.8, 25, FX.SMALL_SECONDS)
		end
	elseif data.visual ~= false and FX.ArmorImpact(state, now, options) then
		FX.Sync(state, now)
	end

	if data.sound ~= false and GryMod.PlayArmorHitSound then
		GryMod.PlayArmorHitSound()
	end
end

function FX.Events.decloak(state, now, data, options)
	FX.Decloak(state, now, options)
end

function FX.Events.low_health(state, now, data, options)
	FX.LowHealth(state, data.level, now, options)
end

function FX.Events.jam(state, now, data, options)
	FX.Jam(state, data.seconds, options)
end

-- The jump of the HUD this frame (stage pixels), and the decay of its strength. The two random numbers are for the tests.
function FX.HudOffset(state, dt, rx, ry)
	-- a jam keeps the interference at its strength while it lasts
	local jam = state.jamLeft

	if jam and jam > 0 then
		state.jolt = math.max(state.jolt, FX.JAM_STRENGTH)
		state.jamLeft = jam - dt
	end

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
	if GryMod.Minimap and GryMod.Minimap.Capture and GryMod.Minimap.Capture.IsCapturing() then return end

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
local switches = {hud = true, screen = true, hit = true}

function FX.Options()
	local options = GryMod.HUDOptions

	switches.hud = not options or options.Enabled("damagefx")
	switches.screen = screenConVar:GetBool()
	switches.hit = hitShakeConVar:GetBool()

	return switches
end

-- The suit goes down (the HUD status 1) or the HUD is destroyed: the arcs of the damage direction around the crosshair are a sibling of its
-- clip, so a crosshair hidden by the shutdown would still let them play. They are cleared once, from the report of the HUD status (cl_hud_flash.lua
-- runs it at each change): no frame watcher.
hook.Add("GryMod_HUDStatus", "GRYDAMAGEFXCLEAR", function(status)
	if status ~= 1 then
		return
	end

	local Cross = GryMod.FlashCrosshair
	local instance = Cross and Cross.Current and Cross.Current()

	if instance and instance.ClearDamageDirection then
		instance:ClearDamageDirection()
	end
end)
