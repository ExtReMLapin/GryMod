local health_regen_speed = 17 -- per sec
local health_regen_delay = 3
local energy_regen_speed = 7
local energy_regen_delay = 5

util.AddNetworkString("gry_start_health_regen")
util.AddNetworkString("gry_stop_health_regen")

hook.Add("PlayerSpawn", "GryMod_ENER_HLT_VARS", function(ply)
	ply.next_health_regen = CurTime()
	ply.health_on_dmg = ply:Health()
	ply.should_heath_regen = false

	ply.next_energy_regen = CurTime()
	ply.energy_on_use = ply:GetNWFloat("GryEnergy")
end)

-- need to be called AFTER the energy drain
hook.Add("GryUseEnergy", "grymod energy usage", function(ply)
	local amnt = ply:GetNWFloat("GryEnergy")
	ply.next_energy_regen = CurTime() + energy_regen_delay
	ply.energy_on_use = amnt

	if ply.Nanosuit_mode == GryMod.Modes.SPEED == true and GryMod.Config.speedEnergyDrain * FrameTime() > amnt then
		ply:SetRunSpeed(400)
	end
end)


hook.Add("PlayerDeath","grymod death stop healing sound", function (ply)
	if (ply.should_heath_regen) then
		ply.should_heath_regen = false
		net.Start("gry_stop_health_regen")
		net.Send(ply)
	end
	ply.next_health_regen = 0
end)


hook.Add("EntityTakeDamage", "Grymod damage handeling", function(ply, dmginfo)
	if (not ply:IsPlayer()) then
		return
	end

	local amt = dmginfo:GetDamage()

	if ply.Nanosuit_mode == GryMod.Modes.ARMOR then
		local energy = ply:GetNWFloat("GryEnergy")

		if (energy > 0 and dmginfo:IsBulletDamage()) then
			net.Start("gry_armor_hit_sound")
			net.Send(ply)



		end


		if (amt > energy) then
			ply:SetNWFloat("GryEnergy", 0)
			local diff = amt - energy
			dmginfo:SetDamage(diff)
		else
			dmginfo:SetDamage(0)
			ply:SetNWFloat("GryEnergy", ply:GetNWFloat("GryEnergy") - amt)
			hook.Run("GryUseEnergy", ply)
			return
		end

		hook.Run("GryUseEnergy", ply)
	end


	ply.next_health_regen = CurTime() + health_regen_delay
	
	if (ply.should_heath_regen == true) then
		ply.should_heath_regen = false
		net.Start("gry_stop_health_regen")
		net.Send(ply)
	end
	ply.health_on_dmg = ply:Health() - dmginfo:GetDamage()
end)

hook.Add("Think", "GryMod health think", function()
	for k, ply in pairs(player.GetAll()) do
		if not ply:Alive() then continue end

		if ply.next_health_regen and (ply.next_health_regen < CurTime()) then


			if (ply:Health() >= ply:GetMaxHealth()) then
				if (ply.should_heath_regen) then
					ply.should_heath_regen = false
					net.Start("gry_stop_health_regen")
					net.Send(ply)
				end
				ply.next_health_regen = 0
			else
				if not ply.should_heath_regen then
					net.Start("gry_start_health_regen")
					net.Send(ply)
					ply.should_heath_regen = true
				end
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply.health_on_dmg + (CurTime() - ply.next_health_regen) * health_regen_speed))
			end
		end

		local curenergy = ply:GetNWFloat("GryEnergy")

		if (ply.next_energy_regen and ply.next_energy_regen < CurTime()) then
			if (curenergy >= 100) then
				ply.next_energy_regen = 0
			else
				ply:SetNWFloat("GryEnergy", math.min(100, ply.energy_on_use + (CurTime() - ply.next_energy_regen) * energy_regen_speed))

				if ply.Nanosuit_mode == GryMod.Modes.SPEED then
					ply:SetRunSpeed(600)
				end
			end
		end
	end
end)