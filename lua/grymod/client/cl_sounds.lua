
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

net.Receive("gry_armor_hit_sound",function()
	GryMod.PlaySound(Sound(GryMod.NextArmorHitSound()))
end)






-- The repair sound (suit_medical_use_new, 5.95 s). The server starts it (sv_health.lua); gry_sound_regen switches it off.
local RegenEnabled = CreateClientConVar("gry_sound_regen", "1", true, false, "Play the suit repair sound when the health comes back")
local healingSound

-- hackysound system
sound.PlayFile("sound/suit/suit_medical_use_new.mp3", "noblock noplay", function(soundchannel, error, str ) healingSound = soundchannel end)

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
		healingSound:SetVolume(1 - (CurTime() - overtime) - 1) -- it fades away
		if CurTime() > overtime then
			healingSound:Pause()
			healingSound:SetTime(0)
			healingSound:SetVolume(1)
			hook.Remove("Think", "GryModSoundhealthregenfadeaway")
		end

	end)



end)

net.Receive("gry_start_health_regen",function ()
	if not IsValid(healingSound) or not GryMod.SoundsEnabled() or not RegenEnabled:GetBool() then return end
	-- a fade-out still running would pause the sound again a moment after it starts
	hook.Remove("Think", "GryModSoundhealthregenfadeaway")
	healingSound:SetVolume(1)
	-- a sound that played to its end is still at its end: play it from the beginning every time
	healingSound:SetTime(0)
	healingSound:Play()
end)




local speedLoopGround;
local speedLoopUnderwater;

sound.PlayFile("sound/suit/servo_speed_loop_01c.mp3", "noblock noplay",
	function(soundchannel, error, str )
		speedLoopGround = soundchannel
		soundchannel:EnableLooping(true)
		soundchannel:SetVolume(0.5)

	end)

sound.PlayFile("sound/suit/servo_speed_loop_01_underwater.mp3", "noblock noplay",
	function(soundchannel, error, str )
	speedLoopUnderwater = soundchannel
	soundchannel:EnableLooping(true)
	soundchannel:SetVolume(0.5)
end)




hook.Add("GryModStartSprinting", "sound", function()
	if not GryMod.SoundsEnabled() then return end

	-- the channels are created asynchronously: they may not exist yet
	local channel = LocalPlayer():WaterLevel() < 3 and speedLoopGround or speedLoopUnderwater

	if IsValid(channel) then
		channel:Play()
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



local wasSprinting = false
local wasUnderwater = false
hook.Add("Think", "GryModSounds", function()

	if not IsValid(LocalPlayer()) then return end
	local energy = LocalPlayer():GetNWFloat("GryEnergy")
	if (lastenergy == nil) then
		if energy == 0 then return end
		lastenergy = energy
	end
	if (lastenergy >= 20 and energy < 20) then
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
	if wasSprinting and IsValid(speedLoopGround) then
		local tr = util.TraceLine( {
		start = LocalPlayer():GetPos(),
		endpos = LocalPlayer():EyePos() + Vector(0,0,-50000000),
	} )
		local distanceFromGround = LocalPlayer():GetPos():Distance(tr.HitPos)
		local volume = math.Max(math.Remap(distanceFromGround, 0, 300, 1, 0),0)
		speedLoopGround:SetVolume(volume)
	end

	-- if we get from water to air or to air from water, swap the two sounds
	local bothLoops = IsValid(speedLoopGround) and IsValid(speedLoopUnderwater)

	if (wasUnderwater and LocalPlayer():WaterLevel() < 3) then
		wasUnderwater = false
		if (wasSprinting and bothLoops) then
			speedLoopGround:SetTime(speedLoopUnderwater:GetTime())
			speedLoopGround:Play()
			speedLoopUnderwater:Pause()
			speedLoopUnderwater:SetTime(0)
		end
	elseif (not wasUnderwater and LocalPlayer():WaterLevel() == 3) then
		wasUnderwater = true
		if (wasSprinting and bothLoops) then
			speedLoopUnderwater:SetTime(speedLoopGround:GetTime())
			speedLoopUnderwater:Play()
			speedLoopGround:Pause()
			speedLoopGround:SetTime(0)
		end

	end


end)