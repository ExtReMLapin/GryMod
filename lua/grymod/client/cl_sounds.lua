
-- The armor hit: in the single-player game Client:OnHit plays the physics event mat_armor_fp, whose sound definition
-- suit_bullet_impact_fp shuffles these 13 files (every one once before any plays again), whatever the water. (The
-- interface bank's suit_armor_use, with its own 13 files, is only reached by the network code; the earlier GryMod split
-- its list in two for the water, which no game event does.) The server decides when (sv_health.lua,
-- Mech.ArmorHitSoundDue).
GryMod.ArmorHitSounds = {
	"grymod/suit/suit_bullet_impact_fp_02.wav",
	"grymod/suit/suit_bullet_impact_fp_03.wav",
	"grymod/suit/suit_bullet_impact_fp_04.wav",
	"grymod/suit/suit_bullet_impact_fp_05.wav",
	"grymod/suit/suit_bullet_impact_fp_06.wav",
	"grymod/suit/suit_bullet_impact_fp_07.wav",
	"grymod/suit/suit_bullet_impact_fp_09.wav",
	"grymod/suit/suit_bullet_impact_fp_10.wav",
	"grymod/suit/suit_bullet_impact_fp_11.wav",
	"grymod/suit/suit_bullet_impact_fp_13.wav",
	"grymod/suit/suit_bullet_impact_fp_14.wav",
	"grymod/suit/suit_bullet_impact_fp_15.wav",
	"grymod/suit/suit_bullet_impact_fp_16.wav"
}

local armorHitBag = {}
local armorHitLast

-- the next file of the shuffle: a new random order once the 13 have played, never starting with the last one played
function GryMod.NextArmorHitSound()
	if #armorHitBag == 0 then
		for i, path in ipairs(GryMod.ArmorHitSounds) do
			armorHitBag[i] = path
		end

		for i = #armorHitBag, 2, -1 do
			local j = math.random(i)
			armorHitBag[i], armorHitBag[j] = armorHitBag[j], armorHitBag[i]
		end

		if armorHitBag[#armorHitBag] == armorHitLast then
			local j = math.random(#armorHitBag - 1)
			armorHitBag[#armorHitBag], armorHitBag[j] = armorHitBag[j], armorHitBag[#armorHitBag]
		end
	end

	armorHitLast = table.remove(armorHitBag)

	return armorHitLast
end

-- forget the shuffle (the tests start from a full new one)
function GryMod.ResetArmorHitSounds()
	armorHitBag = {}
	armorHitLast = nil
end

-- Every sound of this file belongs to a HUD event of the extension API (cl_api_hud_events.lua): the triggers below call the event,
-- and the event plays the picture and the sound together. The functions Play... and Start... are what the events run.
local function hudEvent(name, data)
	local API = GryMod.API

	if API and API.HUDEvent then
		return API.HUDEvent(name, data)
	end

	return false
end

-- The sound of the armor hit event. The game plays at most 8 armor hits at a time (maxpb 8), and the mix leaves 60 ms between two:
-- a shotgun's pellets or a burst would stack into one loud noise (see GryMod.SoundMix.MayPlay). A hit that is refused uses up no file
-- of the shuffle.
function GryMod.PlayArmorHitSound()
	local ok, count = GryMod.SoundMix.MayPlay("armor_hit", GryMod.SoundMix.Now())

	if not ok then return end

	-- the hits that stack are quieter (GryMod.SoundMix.Limits.armor_hit.stack): they would clip together
	GryMod.PlaySound(Sound(GryMod.NextArmorHitSound()), GryMod.SoundMix.StackScale("armor_hit", count))
end

-- The server says a hit was heard: the sound alone (the picture of an armor hit follows the energy it costs, see
-- cl_damage_fx.lua: the game's two rules are not the same, so the two triggers each ask for their half of the event).
net.Receive("gry_armor_hit_sound",function()
	hudEvent("armor_hit", {visual = false})
end)






-- The repair sound (suit_medical_use_new, 5.95 s). The server starts it (sv_health.lua); gry_sound_regen switches it off.
local RegenEnabled = CreateClientConVar("gry_sound_regen", "1", true, false, "Play the suit repair sound when the health comes back")
local REGEN_PATH = "grymod/suit/suit_medical_use_new.wav"
local healingSound

-- hackysound system
sound.PlayFile("sound/" .. REGEN_PATH, "noblock noplay", function(soundchannel, error, str )
	healingSound = soundchannel
	soundchannel:SetVolume(GryMod.SoundMix.Volume(REGEN_PATH))
end)

-- for the tests: the channel can be replaced by a recording one
GryMod.RegenSound = {
	GetChannel = function() return healingSound end,
	SetChannel = function(channel) healingSound = channel end
}

-- The regen_stop event: the repair sound fades out over a second.
function GryMod.StopRegenSound()
	if not IsValid(healingSound) then return end
	local overtime = CurTime() + 1
	hook.Add("Think", "GryModSoundhealthregenfadeaway", function()
		if not IsValid(healingSound) then
			hook.Remove("Think", "GryModSoundhealthregenfadeaway")
			return
		end
		healingSound:SetVolume(math.max(overtime - CurTime(), 0) * GryMod.SoundMix.Volume(REGEN_PATH)) -- it fades away
		if CurTime() > overtime then
			healingSound:Pause()
			healingSound:SetTime(0)
			healingSound:SetVolume(GryMod.SoundMix.Volume(REGEN_PATH))
			hook.Remove("Think", "GryModSoundhealthregenfadeaway")
		end

	end)
end

-- The regen_start event: the repair sound plays from the beginning.
function GryMod.StartRegenSound()
	if not IsValid(healingSound) or not GryMod.SoundsEnabled() or not RegenEnabled:GetBool() then return end
	-- a fade-out still running would pause the sound again a moment after it starts
	hook.Remove("Think", "GryModSoundhealthregenfadeaway")
	healingSound:SetVolume(GryMod.SoundMix.Volume(REGEN_PATH))
	-- a sound that played to its end is still at its end: play it from the beginning every time
	healingSound:SetTime(0)
	healingSound:Play()
end

-- the server starts and stops the repair sound (sv_health.lua)
net.Receive("gry_stop_health_regen",function ()
	hudEvent("regen_stop")
end)

net.Receive("gry_start_health_regen",function ()
	hudEvent("regen_start")
end)




-- The speed servo (cl_sprint_sound.lua decides, this file owns the two BASS channels): the machine is fed once a frame by
-- the Think hook below and its actions are applied to the channels (SprintSound.Apply).
local speedLoopGround
local speedLoopUnderwater

local GROUND_LOOP = GryMod.SprintSound.Files.loop.ground
local UNDERWATER_LOOP = GryMod.SprintSound.Files.loop.underwater

-- for the tests: the channels can be replaced by recording ones
GryMod.SpeedLoops = {
	Get = function() return speedLoopGround, speedLoopUnderwater end,
	Set = function(ground, underwater)
		speedLoopGround = ground
		speedLoopUnderwater = underwater
	end
}

sound.PlayFile("sound/" .. GROUND_LOOP, "noblock noplay",
	function(soundchannel, error, str )
		speedLoopGround = soundchannel
		soundchannel:EnableLooping(true)
		soundchannel:SetVolume(0)
	end)

sound.PlayFile("sound/" .. UNDERWATER_LOOP, "noblock noplay",
	function(soundchannel, error, str )
		speedLoopUnderwater = soundchannel
		soundchannel:EnableLooping(true)
		soundchannel:SetVolume(0)
	end)

local sprintState = GryMod.SprintSound.New()
local sprintWasOnGround = true
local sprintLastThink
local sprintLoops = {}
local sprintFrame = {}
local sprintReuse = {actions = {}}

local lastenergy

-- The servo loop of the speed sprint cuts out at a fifth of the bar under the original game's rules (the sprint
-- itself goes on), at nothing under the classic ones.
function GryMod.SprintLoopMinimum()
	local mechanics = GetConVar("gry_mechanics")

	return (mechanics and mechanics:GetString() ~= "classic") and 20 or 1
end



-- The energy-critical voice (suit_energy_critical). The original plays it when the energy goes from above 50 to 50
-- or less of its 200 (a quarter of the bar, 25 of GryMod's 100), and not again for 30 s after the last time.
GryMod.ENERGY_CRITICAL_LEVEL = 25
GryMod.ENERGY_CRITICAL_PAUSE = 30

-- Whether the voice is due: the energy (previous, now) crosses the level downwards, and the pause since the last
-- play (lastAt, in the same seconds as t; nil = never) is over.
function GryMod.EnergyCriticalDue(previous, energy, lastAt, t)
	if previous == nil or energy == nil or t == nil then
		return false
	end

	if not (previous > GryMod.ENERGY_CRITICAL_LEVEL and energy <= GryMod.ENERGY_CRITICAL_LEVEL) then
		return false
	end

	return lastAt == nil or t - lastAt >= GryMod.ENERGY_CRITICAL_PAUSE
end

local lastCriticalAt

-- The sound of the energy_critical event (the Think hook below says when).
function GryMod.PlayEnergyCritical()
	GryMod.PlaySound(Sound("grymod/suit/suit_energy_critical.wav"))
end

-- forget the last play (the tests start from a voice that was never played)
function GryMod.ResetEnergyCritical()
	lastCriticalAt = nil
end

hook.Add("Think", "GryModSounds", function()
	local ply = LocalPlayer()

	if not IsValid(ply) then return end

	local energy = ply:GetNW2Float("GryEnergy")
	local now = GryMod.SoundMix.Now()

	-- the voice: nothing before the first energy value (the sprint sound below runs whatever the energy)
	if lastenergy == nil and energy ~= 0 then
		lastenergy = energy
	end

	if lastenergy ~= nil then
		if GryMod.EnergyCriticalDue(lastenergy, energy, lastCriticalAt, now) then
			lastCriticalAt = now
			hudEvent("energy_critical")
		end

		lastenergy = energy
	end

	-- the servo of the speed sprint (the frame, the state and the list of actions are kept from a frame to the next: nothing is made each time)
	local frame = GryMod.SprintSound.Sample(ply, energy, sprintWasOnGround, sprintFrame)
	sprintWasOnGround = frame.onGround
	local dt = sprintLastThink and math.Clamp(now - sprintLastThink, 0, 0.25) or 0
	sprintLastThink = now
	local actions
	sprintState, actions = GryMod.SprintSound.Step(sprintState, frame, dt, sprintReuse)
	sprintLoops.ground = speedLoopGround
	sprintLoops.underwater = speedLoopUnderwater
	GryMod.SprintSound.Apply(actions, sprintLoops)
end)

-- ---------------------------------------------------------------------------------------------------------
-- The loops that go with a state of the suit: the malfunction (the failure sound goes on while the suit is down) and the camouflage (the
-- original's hud/cloak_feedback, 8.73 s, plays over and over while cloaked). Each starts at an event the game already reports and ends when the
-- state ends; while it plays, and only then, a Think hook watches the state (it also catches a death, a disconnect and the HUD going off, which
-- end the state without any report of their own). With nothing playing, no hook exists.
-- ---------------------------------------------------------------------------------------------------------
local Loops = GryMod.SuitLoops or {}
GryMod.SuitLoops = Loops

local MalfunctionLoopConVar = CreateClientConVar("gry_sound_malfunction_loop", "1", true, false, "The failure sound repeats while the suit is down (the original); 0: it plays once")
local CloakLoopConVar = CreateClientConVar("gry_sound_cloak_loop", "1", true, false, "A loop plays while the suit is cloaked (the original's hud cloak feedback)")

Loops.Files = {
	malfunction = "grymod/hud/hud_malfunction_hit.wav",
	cloak = "grymod/hud/hud_cloak_feedback.wav"
}

-- The failure sound of the lost sequence (cl_hud_boot_flash.lua) plays once, from the start of the malfunction: the loop takes over when that
-- sample (1.97 s) is over, so the two never play together.
Loops.DELAY = {malfunction = 1.97, cloak = 0}

local function newLoop(name)
	return {name = name, path = Loops.Files[name], wanted = false, started = false, startAt = 0, since = 0, channel = nil, loading = false}
end

Loops.State = {malfunction = newLoop("malfunction"), cloak = newLoop("cloak")}

-- What a loop does on a frame: "idle" (nothing wanted), "stop" (it was wanted and its state is over: `keepOn` false), "run" (playing),
-- "start" (its time has come and its channel is ready) or "wait". A pure rule.
function Loops.Phase(loop, now, keepOn, ready)
	if not loop.wanted then
		return "idle"
	end

	if not keepOn then
		return "stop"
	end

	if loop.started then
		return "run"
	end

	if ready and now >= loop.startAt then
		return "start"
	end

	return "wait"
end

local function hookName(loop)
	return "GrySuitLoop_" .. loop.name
end

-- The state that keeps a loop going: sounds on, its own switch, the player alive and the state itself (the HUD's malfunction, the camouflage).
-- The state the player is in is read from the client's own copies, so nothing is asked of the server.
function Loops.KeepOn(name)
	local ply = LocalPlayer()

	if not IsValid(ply) or not ply:Alive() or not GryMod.SoundsEnabled() then
		return false
	end

	if name == "malfunction" then
		local Boot = GryMod.FlashBoot

		return MalfunctionLoopConVar:GetBool() and Boot ~= nil and Boot.Malfunctioning()
	end

	return CloakLoopConVar:GetBool() and ply.NanosuitMode == GryMod.Modes.CLOAK
end

function Loops.End(loop)
	loop.wanted, loop.started = false, false
	hook.Remove("Think", hookName(loop))

	if IsValid(loop.channel) then
		loop.channel:SetVolume(0)
		loop.channel:Pause()
	end
end

-- One frame of a loop: its phase, and what the phase asks of the channel.
function Loops.Step(loop, now, keepOn)
	local phase = Loops.Phase(loop, now, keepOn, IsValid(loop.channel))

	if phase == "stop" then
		Loops.End(loop)
	elseif phase == "start" then
		loop.started, loop.since = true, now
		loop.channel:SetTime(0)
		loop.channel:SetVolume(0)
		loop.channel:Play()
	elseif phase == "run" then
		-- brought up over the first hundredths of a second, as the binoculars' loop is (a loop that starts at its level clicks)
		loop.channel:SetVolume(GryMod.SoundMix.Volume(loop.path) * GryMod.SoundMix.FadeIn(now - loop.since))
	end

	return phase
end

-- The loop is wanted from now: its channel is made once (the loading is asynchronous), and the Think hook that follows its state exists until
-- the state ends. A loop that is already wanted is left as it is.
function Loops.Begin(loop)
	if loop.wanted then
		return false
	end

	loop.wanted, loop.started = true, false
	loop.startAt = GryMod.SoundMix.Now() + Loops.DELAY[loop.name]

	if not IsValid(loop.channel) and not loop.loading then
		loop.loading = true

		sound.PlayFile("sound/" .. loop.path, "noblock noplay", function(created)
			loop.loading = false

			if IsValid(created) then
				loop.channel = created
				created:EnableLooping(true)
			end
		end)
	end

	hook.Add("Think", hookName(loop), function()
		Loops.Step(loop, GryMod.SoundMix.Now(), Loops.KeepOn(loop.name))
	end)

	return true
end

-- the suit goes down: the lost sequence (cl_hud_boot_flash.lua) says "lost" or "malfunction" through its event, and has set its own state first
hook.Add("GryMod_HUDEvent", "GRYSUITLOOPS", function(name)
	if (name == "lost" or name == "malfunction") and Loops.KeepOn("malfunction") then
		Loops.Begin(Loops.State.malfunction)
	end
end)

-- the suit goes to the camouflage (the local player's mode, told by the server or chosen here)
hook.Add("GryMod_ModeChanged", "GRYSUITLOOPS", function(ply, mode)
	if mode == GryMod.Modes.CLOAK and ply == LocalPlayer() and Loops.KeepOn("cloak") then
		Loops.Begin(Loops.State.cloak)
	end
end)

-- the game closes: nothing keeps playing
hook.Add("ShutDown", "GRYSUITLOOPS", function()
	for _, loop in pairs(Loops.State) do
		Loops.End(loop)
	end
end)
