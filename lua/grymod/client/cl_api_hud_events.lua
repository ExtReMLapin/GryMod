-- The extension API, client side (GryMod.API, see cl_api.lua and docs/api.md): the HUD events of GryMod's own interface. Every effect
-- the interface plays is a HUD event, and an event plays its animation AND its sound together, by one path: the game's own triggers
-- (damage, mode change, regeneration, energy, water, malfunction...) call GryMod.API.HUDEvent themselves, as an addon does, so that
-- the API is what GryMod runs on and nothing plays a picture on one side and its sound on another. The sounds go through
-- GryMod.PlaySound (the mix: shuffles, limits, gry_sounds) and the events follow the player's options, like "boot".
--
-- boot, lost, reboot and malfunction are registered by the module that draws them (cl_hud_boot_flash.lua). The others are here; each
-- handler only calls what its module offers (cl_damage_fx.lua, cl_mode_fx.lua, cl_sounds.lua, cl_underwater.lua, cl_hud.lua...).
-- The third argument of RegisterHUDEvent tells a tool (the debug window) the label, the variants and the options that cut the effect.

GryMod = GryMod or {}

local API = GryMod.API

if not API then
	return -- sh_api.lua is included first (grymod_shared.lua)
end

local Events = {}
GryMod.APIEvents = Events

-- How long the shutdown animation of "disabled" plays before the HUD stays hidden (the original's lost movie loops: this is its
-- first run).
Events.SHUTDOWN_SECONDS = 2.5

local SHUTDOWN_TIMER = "GryApiDisabled"

local BOOT_OPTION = {"gry_hud_boot", "the start-up and reboot sequences"}
local SOUNDS_OPTION = {"gry_sounds", "the sound"}

-- The shutdown animation of "disabled" is over: the HUD stays hidden until "enabled".
function Events.EndShutdown()
	timer.Remove(SHUTDOWN_TIMER)

	if GryMod.FlashBoot then
		GryMod.FlashBoot.Stop()
	end
end

-- What the server's flag of the suit (GryMod.API.SetSuitEnabled) did between two looks: "disabled", "enabled" or nil. The first look
-- (nothing before it) and a flag that does not change play nothing.
function Events.SuitFlagStep(previous, now)
	if previous == nil or now == nil or previous == now then
		return nil
	end

	return now and "enabled" or "disabled"
end

-- An effect of cl_damage_fx.lua, played on the local player's state with its options.
local function damage(name)
	return function(data)
		local FX = GryMod.DamageFx

		if FX then
			FX.Events[name](FX.State, FX.Now(), data, FX.Options())
		end
	end
end

function Events.Register()
	local register = API.RegisterHUDEvent

	-- the armor takes a hit: the flash, the shake and the jump of the HUD with the impact sound. Triggers: the energy drop the HUD
	-- sees (the picture, data.sound = false) and the server's message of a heard hit (the sound, data.visual = false): the game's two
	-- rules for them are not the same. data.visual = false: no picture, data.sound = false: no sound.
	register("armor_hit", damage("armor_hit"), {
		label = "Armor hit",
		follows = {{"gry_screenfx", "the flash and the shake"}, {"gry_hud_damagefx", "the jump of the HUD"}, {"gry_sounds", "the impact sound"}}
	})

	-- firing out of the camouflage: the glitch of the armor hit, at any energy (no sound of its own)
	register("decloak", damage("decloak"), {
		label = "Camouflage glitch",
		follows = {{"gry_decloak_glitch", "the glitch"}, {"gry_screenfx", "the flash and the shake"}, {"gry_hud_damagefx", "the jump of the HUD"}}
	})

	-- the health falls through 25 % (level 1) or 20 % (level 2): the red tint, the blur, and a shake at level 2
	register("low_health", damage("low_health"), {
		label = "Low health",
		variants = {{label = "Low health (25 %)", data = {level = 1}}, {label = "Critical health (20 %)", data = {level = 2}}},
		follows = {{"gry_screenfx", "the tint, the blur and the shake"}}
	})

	-- the HUD trembles for data.seconds (2 by default)
	register("jam", damage("jam"), {
		label = "HUD jam",
		follows = {{"gry_hud_damagefx", "the jump of the HUD"}}
	})

	-- the suit changes mode (data.mode: "armor", "speed", "strength" or "cloak"): the tint of the mode and its activation sound with
	-- the voice half a second later. data.tint = false: no tint, data.sound = false: no sound. The camouflage has no tint here.
	register("mode", function(data)
		local FX = GryMod.ModeFX
		local mode = FX and FX.ModeFromData(data.mode)

		if not mode then
			return
		end

		if data.tint ~= false and FX.Enabled() then
			FX.Play(FX.State, mode, FX.Now())
		end

		if data.sound ~= false and GryMod.PlayModeSound then
			GryMod.PlayModeSound(mode)
		end
	end, {
		label = "Mode change",
		variants = {
			{label = "Armor", data = {mode = "armor"}},
			{label = "Speed", data = {mode = "speed"}},
			{label = "Strength", data = {mode = "strength"}},
			{label = "Cloak", data = {mode = "cloak"}}
		},
		follows = {{"gry_screenfx", "the tint"}, SOUNDS_OPTION}
	})

	-- the energy falls to a quarter of the bar: the warning voice (the pause between two is the trigger's)
	register("energy_critical", function()
		if GryMod.PlayEnergyCritical then
			GryMod.PlayEnergyCritical()
		end
	end, {
		label = "Energy critical",
		follows = {{"gry_sounds", "the voice"}}
	})

	-- the repair sound starts (from the beginning) and fades out
	register("regen_start", function()
		if GryMod.StartRegenSound then
			GryMod.StartRegenSound()
		end
	end, {
		label = "Repair sound start",
		follows = {{"gry_sound_regen", "the repair sound"}, SOUNDS_OPTION}
	})

	register("regen_stop", function()
		if GryMod.StopRegenSound then
			GryMod.StopRegenSound()
		end
	end, {
		label = "Repair sound stop",
		follows = {{"gry_sound_regen", "the repair sound"}, SOUNDS_OPTION}
	})

	-- the water: the splash of the head going under (data.fall, the downward speed: a hard fall plays a fast one), the one of coming
	-- out, and a gasp of a drowning player. The loop and the breathing under water are a state, not an event.
	register("dive_in", function(data)
		if GryMod.Underwater then
			GryMod.Underwater.PlayDiveIn(data.fall)
		end
	end, {
		label = "Dive in",
		follows = {{"gry_underwater_fx", "the underwater sounds"}, SOUNDS_OPTION}
	})

	register("dive_out", function()
		if GryMod.Underwater then
			GryMod.Underwater.PlayDiveOut()
		end
	end, {
		label = "Dive out",
		follows = {{"gry_underwater_fx", "the underwater sounds"}, SOUNDS_OPTION}
	})

	register("drown", function()
		if GryMod.Underwater then
			GryMod.Underwater.PlayDrown()
		end
	end, {
		label = "Drowning gasp",
		follows = {{"gry_underwater_fx", "the underwater sounds"}, SOUNDS_OPTION}
	})

	-- the interface goes back to its start state: the HUD is rebuilt, the energy bar starts on the real value, the damage effects, the
	-- sequences and a hidden HUD ("disabled") are forgotten
	register("reset", function()
		local Hud = GryMod.FlashHUD

		timer.Remove(SHUTDOWN_TIMER)

		if Hud and Hud.SetLocalOff then
			Hud.SetLocalOff(false)
		end

		if GryMod.FlashBoot then
			GryMod.FlashBoot.Stop()
		end

		if Hud and Hud.ResetAll then
			Hud.ResetAll()
		end

		if GryMod.EnergySmooth then
			GryMod.EnergySmooth.Reset()
		end

		local FX = GryMod.DamageFx

		if FX then
			FX.Reset(FX.State)
		end
	end, {
		label = "Reset the HUD"
	})

	-- the suit goes off, on this screen only: the shutdown animation (with the malfunction sound), then the HUD stays hidden until
	-- "enabled" (or "reset"). The server's flag (GryMod.API.SetSuitEnabled) calls these two when it changes (see the EntityNetworkedVarChanged hook below).
	register("disabled", function()
		if GryMod.FlashHUD and GryMod.FlashHUD.SetLocalOff then
			GryMod.FlashHUD.SetLocalOff(true)
		end

		if GryMod.FlashBoot then
			GryMod.FlashBoot.Shutdown()
		end

		timer.Create(SHUTDOWN_TIMER, Events.SHUTDOWN_SECONDS, 1, Events.EndShutdown)
	end, {
		label = "Suit off",
		follows = {{"gry_hud", "the HUD"}, BOOT_OPTION, {"gry_sounds", "the malfunction sound"}}
	})

	-- the suit comes back: the HUD is shown again and plays its reboot sequence (silent, as in the original game)
	register("enabled", function()
		timer.Remove(SHUTDOWN_TIMER)

		if GryMod.FlashHUD and GryMod.FlashHUD.SetLocalOff then
			GryMod.FlashHUD.SetLocalOff(false)
		end

		if GryMod.FlashBoot then
			GryMod.FlashBoot.Restart()
		end
	end, {
		label = "Suit on",
		follows = {{"gry_hud", "the HUD"}, BOOT_OPTION}
	})
end

Events.Register()

-- The built-in events of the boot module (boot, lost, reboot, malfunction): in case this file runs after a reload of cl_api.lua.
if GryMod.FlashBoot and GryMod.FlashBoot.RegisterEvents then
	GryMod.FlashBoot.RegisterEvents()
end

-- The server's flag of the suit (the NW2 bool "GryDisabled", GryMod.API.SetSuitEnabled): when it changes, the HUD plays its shutdown or its
-- reboot. Nothing is polled: the game calls EntityNetworkedVarChanged when a NW2 variable changes, and for every variable of every entity at a
-- full update (the arrival in game: the old value is nil then, as it is for the first set of a variable). The hook gets the NEW value as its
-- fourth argument (the entity still holds the old one, so it is not read from there). What was seen last is kept, so that a full update that
-- repeats the flag, and the arrival itself, play nothing: only a real change does.
local lastFlag -- the state of the suit as last seen (true = on), nil before the first look

-- The state the flag was last seen in: on = true / false, nil to forget it (the next value is a first look and plays nothing).
function Events.SuitFlagSync(on)
	lastFlag = on
end

local function syncSuitFlag()
	local ply = LocalPlayer()

	if IsValid(ply) and API.IsSuitEnabled then
		Events.SuitFlagSync(API.IsSuitEnabled(ply))
	end
end

hook.Add("EntityNetworkedVarChanged", "GryApiSuitFlag", function(ent, name, _, disabled)
	if name ~= "GryDisabled" or ent ~= LocalPlayer() or not IsValid(ent) then
		return
	end

	local on = not disabled
	local event = Events.SuitFlagStep(lastFlag, on)
	lastFlag = on

	if event then
		API.HUDEvent(event)
	end
end)

-- The first look: the flag as it is when the player arrives in game (the full update may have come before this) and when this file is loaded
-- again in a running game. Once, not a loop.
hook.Add("InitPostEntity", "GryApiSuitFlag", syncSuitFlag)
syncSuitFlag()

-- The first version of this watched the flag at every frame: a copy of it left by an older load of the file goes.
hook.Remove("Think", "GryApiSuitFlag")
