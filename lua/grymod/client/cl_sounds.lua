
local armorHitSoundsGROUND = {"suit/suit_bullet_impact_01.mp3",
"suit/suit_bullet_impact_02.mp3",
"suit/suit_bullet_impact_03.mp3",
"suit/suit_bullet_impact_15.mp3",
"suit/suit_bullet_impact_16.mp3"}


local armorHitSoundsUNDERWATER = {"suit/suit_bullet_impact_05.mp3",
"suit/suit_bullet_impact_06.mp3",
"suit/suit_bullet_impact_07.mp3",
"suit/suit_bullet_impact_09.mp3",
"suit/suit_bullet_impact_10.mp3",
"suit/suit_bullet_impact_11.mp3",
"suit/suit_bullet_impact_13.mp3",
"suit/suit_bullet_impact_14.mp3",}

net.Receive("gry_armor_hit_sound",function()
	if (LocalPlayer():WaterLevel() < 3) then
		surface.PlaySound(Sound(table.Random(armorHitSoundsGROUND)))
	else
		surface.PlaySound(Sound(table.Random(armorHitSoundsUNDERWATER)))
	end
end)






local healingSound

-- hackysound system
sound.PlayFile("sound/suit/suit_medical_use_new.mp3", "noblock noplay", function(soundchannel, error, str ) healingSound = soundchannel end)
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
	if not IsValid(healingSound) then return end
	healingSound:Play()
end)




local speedLoopGround;
local speedLoopUnderwater;

sound.PlayFile("sound/suit/servo_speed_loop_01c.mp3", "noblock noplay",
	function(soundchannel, error, str )
		speedLoopGround = soundchannel
		soundchannel:EnableLooping()
		soundchannel:SetVolume(0.5)

	end)

sound.PlayFile("sound/suit/servo_speed_loop_01_underwater.mp3", "noblock noplay",
	function(soundchannel, error, str )
	speedLoopUnderwater = soundchannel
	soundchannel:EnableLooping()
	soundchannel:SetVolume(0.5)
end)




hook.Add("GryModStartSprinting", "sound", function()
			if LocalPlayer():WaterLevel() < 3 then
				speedLoopGround:Play()
			else
				speedLoopUnderwater:Play()
			end
end)

local speedStopLastPlay = 0

hook.Add("GryModEndSprinting", "sound", function()
	if LocalPlayer():WaterLevel() < 3  then
		if (CurTime() - speedStopLastPlay > 0.7 ) then
			speedStopLastPlay = CurTime()
			surface.PlaySound(Sound("suit/servo_speed_stop_fp_2.mp3"))
		end
		speedLoopGround:Pause()
		speedLoopGround:SetTime(0)
	else
		if (CurTime() - speedStopLastPlay > 0.7 ) then
			speedStopLastPlay = CurTime()
			surface.PlaySound(Sound("suit/servo_speed_stop_01_underwater.mp3"))
		end
		speedLoopUnderwater:Pause()
		speedLoopUnderwater:SetTime(0)
	end
end)

local lastenergy



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
		LocalPlayer():ChatPrint("nigger")
		surface.PlaySound(Sound("suit/suit_energy_critical.mp3"))
	end
	lastenergy = energy
	if LocalPlayer():IsSprinting() and LocalPlayer():GetVelocity():LengthSqr() > 170000 and LocalPlayer().NanosuitMode == GryMod.Modes.SPEED and energy > 1 then
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

	-- if we get from water to air or to air from water, swap the two sounds

	if (wasUnderwater and LocalPlayer():WaterLevel() < 3) then
		wasUnderwater = false
		if (wasSprinting) then
			speedLoopGround:SetTime(speedLoopUnderwater:GetTime())
			speedLoopGround:Play()
			speedLoopUnderwater:Pause()
			speedLoopUnderwater:SetTime(0)
		end
	elseif (not wasUnderwater and LocalPlayer():WaterLevel() == 3) then
		wasUnderwater = true
		if (wasSprinting) then
			speedLoopUnderwater:SetTime(speedLoopGround:GetTime())
			speedLoopUnderwater:Play()
			speedLoopGround:Pause()
			speedLoopGround:SetTime(0)
		end

	end


end)