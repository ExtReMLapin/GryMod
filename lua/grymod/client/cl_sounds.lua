
-- The armor hit: the game's suit_armor_use event plays these 13 files as a shuffle (every one once before any plays
-- again), whatever the water. (The earlier GryMod split them in two lists, one for the water; the game's event has no
-- such split.) The server decides when (sv_health.lua, Mech.ArmorHitSoundDue).
GryMod.ArmorHitSounds = {
	"suit/suit_bullet_impact_01.mp3",
	"suit/suit_bullet_impact_02.mp3",
	"suit/suit_bullet_impact_03.mp3",
	"suit/suit_bullet_impact_05.mp3",
	"suit/suit_bullet_impact_06.mp3",
	"suit/suit_bullet_impact_07.mp3",
	"suit/suit_bullet_impact_09.mp3",
	"suit/suit_bullet_impact_10.mp3",
	"suit/suit_bullet_impact_11.mp3",
	"suit/suit_bullet_impact_13.mp3",
	"suit/suit_bullet_impact_14.mp3",
	"suit/suit_bullet_impact_15.mp3",
	"suit/suit_bullet_impact_16.mp3"
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

-- the game plays at most 2 armor hits at a time (maxpb 2), and the mix leaves 60 ms between two: a shotgun's pellets or a
-- burst would stack into one loud noise (see GryMod.SoundMix.MayPlay). A hit that is refused uses up no file of the shuffle.
net.Receive("gry_armor_hit_sound",function()
	if not GryMod.SoundMix.MayPlay("armor_hit", GryMod.SoundMix.Now()) then return end

	GryMod.PlaySound(Sound(GryMod.NextArmorHitSound()))
end)






-- The repair sound (suit_medical_use_new, 5.95 s). The server starts it (sv_health.lua); gry_sound_regen switches it off.
local RegenEnabled = CreateClientConVar("gry_sound_regen", "1", true, false, "Play the suit repair sound when the health comes back")
local REGEN_PATH = "suit/suit_medical_use_new.mp3"
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




local speedLoopGround;
local speedLoopUnderwater;

local GROUND_LOOP = "suit/servo_speed_loop_01c.mp3"
local UNDERWATER_LOOP = "suit/servo_speed_loop_01_underwater.mp3"

-- when the loop that plays now started (it fades in, see GryMod.SoundMix.FadeIn)
local loopStart = 0

-- The volume of the ground loop: the mix's volume (the original game's -27 dB plus the gain), lower as the player leaves
-- the ground (nothing at 300 units), and fading in over the first hundredths of a second after the start (sinceStart,
-- seconds). The earlier code set it to 1.0 on the ground at every frame, over the volume the loop was given.
function GryMod.GroundLoopVolume(distanceFromGround, sinceStart)
	local height = math.max(math.Remap(distanceFromGround, 0, 300, 1, 0), 0)

	return GryMod.SoundMix.Volume(GROUND_LOOP) * height * GryMod.SoundMix.FadeIn(sinceStart or math.huge)
end

function GryMod.UnderwaterLoopVolume(sinceStart)
	return GryMod.SoundMix.Volume(UNDERWATER_LOOP) * GryMod.SoundMix.FadeIn(sinceStart or math.huge)
end

-- for the tests: the channels can be replaced by recording ones
GryMod.SpeedLoops = {
	Get = function() return speedLoopGround, speedLoopUnderwater end,
	Set = function(ground, underwater)
		speedLoopGround = ground
		speedLoopUnderwater = underwater
	end
}

-- Sets the volume of both loops (the one that is not playing is paused, its volume does not matter): once per frame of a
-- sprint, with the height above the ground.
function GryMod.UpdateSpeedLoops(now, distanceFromGround)
	local sinceStart = now - loopStart

	if IsValid(speedLoopGround) then
		speedLoopGround:SetVolume(GryMod.GroundLoopVolume(distanceFromGround, sinceStart))
	end

	if IsValid(speedLoopUnderwater) then
		speedLoopUnderwater:SetVolume(GryMod.UnderwaterLoopVolume(sinceStart))
	end
end

-- starts a loop from silence: the frame brings it up (a loop that starts at once at its level clicks)
local function startLoop(channel)
	loopStart = GryMod.SoundMix.Now()
	channel:SetVolume(0)
	channel:Play()
end

sound.PlayFile("sound/" .. GROUND_LOOP, "noblock noplay",
	function(soundchannel, error, str )
		speedLoopGround = soundchannel
		soundchannel:EnableLooping(true)
		soundchannel:SetVolume(GryMod.SoundMix.Volume(GROUND_LOOP))

	end)

sound.PlayFile("sound/" .. UNDERWATER_LOOP, "noblock noplay",
	function(soundchannel, error, str )
	speedLoopUnderwater = soundchannel
	soundchannel:EnableLooping(true)
	soundchannel:SetVolume(GryMod.SoundMix.Volume(UNDERWATER_LOOP))
end)




hook.Add("GryModStartSprinting", "sound", function()
	if not GryMod.SoundsEnabled() then return end

	-- the channels are created asynchronously: they may not exist yet
	local channel = LocalPlayer():WaterLevel() < 3 and speedLoopGround or speedLoopUnderwater

	if IsValid(channel) then
		startLoop(channel)
	end
end)

local speedStopLastPlay = 0

hook.Add("GryModEndSprinting", "sound", function()
	if LocalPlayer():WaterLevel() < 3  then
		if (CurTime() - speedStopLastPlay > 0.7 ) then
			speedStopLastPlay = CurTime()
			GryMod.PlaySound(Sound("suit/servo_speed_stop_fp_2.mp3"))
		end
		if IsValid(speedLoopGround) then
			speedLoopGround:Pause()
			speedLoopGround:SetTime(0)
		end
	else
		if (CurTime() - speedStopLastPlay > 0.7 ) then
			speedStopLastPlay = CurTime()
			GryMod.PlaySound(Sound("suit/servo_speed_stop_01_underwater.mp3"))
		end
		if IsValid(speedLoopUnderwater) then
			speedLoopUnderwater:Pause()
			speedLoopUnderwater:SetTime(0)
		end
	end
end)

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

local wasSprinting = false
local wasUnderwater = false
hook.Add("Think", "GryModSounds", function()

	if not IsValid(LocalPlayer()) then return end
	local energy = LocalPlayer():GetNWFloat("GryEnergy")
	if (lastenergy == nil) then
		if energy == 0 then return end
		lastenergy = energy
	end
	local now = GryMod.SoundMix.Now()

	if GryMod.EnergyCriticalDue(lastenergy, energy, lastCriticalAt, now) then
		lastCriticalAt = now
		GryMod.PlaySound(Sound("suit/suit_energy_critical.mp3"))
	end
	lastenergy = energy
	if LocalPlayer():IsSprinting() and LocalPlayer():GetVelocity():LengthSqr() > 170000 and LocalPlayer().NanosuitMode == GryMod.Modes.SPEED and energy > GryMod.SprintLoopMinimum() then
		if wasSprinting == false then
			hook.Run("GryModStartSprinting")
			wasSprinting = true
		end
	else
		if wasSprinting == true then
			hook.Run("GryModEndSprinting")
			wasSprinting = false
		end
	end

	-- the ground loop fades out when the player leaves the ground: only needed (and only worth a long
	-- trace every frame) while the loop is playing
	if wasSprinting then
		local distanceFromGround = 0

		if IsValid(speedLoopGround) then
			local tr = util.TraceLine( {
			start = LocalPlayer():GetPos(),
			endpos = LocalPlayer():EyePos() + Vector(0,0,-50000000),
		} )
			distanceFromGround = LocalPlayer():GetPos():Distance(tr.HitPos)
		end

		GryMod.UpdateSpeedLoops(GryMod.SoundMix.Now(), distanceFromGround)
	end

	-- if we get from water to air or to air from water, swap the two sounds
	local bothLoops = IsValid(speedLoopGround) and IsValid(speedLoopUnderwater)

	if (wasUnderwater and LocalPlayer():WaterLevel() < 3) then
		wasUnderwater = false
		if (wasSprinting and bothLoops) then
			speedLoopGround:SetTime(speedLoopUnderwater:GetTime())
			startLoop(speedLoopGround)
			speedLoopUnderwater:Pause()
			speedLoopUnderwater:SetTime(0)
		end
	elseif (not wasUnderwater and LocalPlayer():WaterLevel() == 3) then
		wasUnderwater = true
		if (wasSprinting and bothLoops) then
			speedLoopUnderwater:SetTime(speedLoopGround:GetTime())
			startLoop(speedLoopUnderwater)
			speedLoopGround:Pause()
			speedLoopGround:SetTime(0)
		end

	end


end)