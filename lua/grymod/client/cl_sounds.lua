
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

-- the game plays at most 8 armor hits at a time (maxpb 8), and the mix leaves 60 ms between two: a shotgun's pellets or a
-- burst would stack into one loud noise (see GryMod.SoundMix.MayPlay). A hit that is refused uses up no file of the shuffle.
net.Receive("gry_armor_hit_sound",function()
	local ok, count = GryMod.SoundMix.MayPlay("armor_hit", GryMod.SoundMix.Now())

	if not ok then return end

	-- the hits that stack are quieter (GryMod.SoundMix.Limits.armor_hit.stack): they would clip together
	GryMod.PlaySound(Sound(GryMod.NextArmorHitSound()), GryMod.SoundMix.StackScale("armor_hit", count))
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

net.Receive("gry_stop_health_regen",function ()
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



end)

net.Receive("gry_start_health_regen",function ()
	if not IsValid(healingSound) or not GryMod.SoundsEnabled() or not RegenEnabled:GetBool() then return end
	-- a fade-out still running would pause the sound again a moment after it starts
	hook.Remove("Think", "GryModSoundhealthregenfadeaway")
	healingSound:SetVolume(GryMod.SoundMix.Volume(REGEN_PATH))
	-- a sound that played to its end is still at its end: play it from the beginning every time
	healingSound:SetTime(0)
	healingSound:Play()
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

-- forget the last play (the tests start from a voice that was never played)
function GryMod.ResetEnergyCritical()
	lastCriticalAt = nil
end

hook.Add("Think", "GryModSounds", function()
	local ply = LocalPlayer()

	if not IsValid(ply) then return end

	local energy = ply:GetNWFloat("GryEnergy")
	local now = GryMod.SoundMix.Now()

	-- the voice: nothing before the first energy value (the sprint sound below runs whatever the energy)
	if lastenergy == nil and energy ~= 0 then
		lastenergy = energy
	end

	if lastenergy ~= nil then
		if GryMod.EnergyCriticalDue(lastenergy, energy, lastCriticalAt, now) then
			lastCriticalAt = now
			GryMod.PlaySound(Sound("grymod/suit/suit_energy_critical.wav"))
		end

		lastenergy = energy
	end

	-- the servo of the speed sprint
	local frame = GryMod.SprintSound.Sample(ply, energy, sprintWasOnGround)
	sprintWasOnGround = frame.onGround
	local dt = sprintLastThink and math.Clamp(now - sprintLastThink, 0, 0.25) or 0
	sprintLastThink = now
	local actions
	sprintState, actions = GryMod.SprintSound.Step(sprintState, frame, dt)
	sprintLoops.ground = speedLoopGround
	sprintLoops.underwater = speedLoopUnderwater
	GryMod.SprintSound.Apply(actions, sprintLoops)
end)
