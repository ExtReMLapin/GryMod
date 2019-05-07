local health_regen_speed = 15; -- per sec
local health_regen_delay = 3;
local energy_regen_speed = 15
local energy_regen_delay = 3;

hook.Add("PlayerSpawn", "GryMod_ENER_HLT_VARS", function(ply)
	ply.next_health_regen = CurTime()
	ply.health_on_dmg = ply:Health()
	ply.next_energy_regen = CurTime()
	ply.energy_on_use = ply:GetNWInt("GryEnergy")
end)

-- need to be called AFTER the energy drain
hook.Add("GryUseEnergy", "grymod energy usage", function(ply)
	local amnt = ply:GetNWInt("GryEnergy")
	ply.next_energy_regen = CurTime() + energy_regen_delay
	ply.energy_on_use = amnt

	if ply:GetNWBool("Speed") == true and GryMod.Config.speedEnergyDrain * FrameTime() > amnt then
		ply:SetRunSpeed(400)
	end

end)





hook.Add("EntityTakeDamage", "Grymod damage handeling", function (ply,  dmginfo)
		if (not ply:IsPlayer()) then
			return
		end
		local amt = dmginfo:GetDamage()

		if ply:GetNWBool("Armor", true) then
			local energy =  ply:GetNWInt("GryEnergy")
			if (amt > energy) then
				ply:SetNWInt("GryEnergy", 0)
				local diff = amt - energy
				dmginfo:SetDamage(diff)
			else
				dmginfo:SetDamage(0)
				ply:SetNWInt("GryEnergy", ply:GetNWInt("GryEnergy") - amt)
			end
			hook.Run("GryUseEnergy", ply)
		end
		ply.next_health_regen = CurTime() + health_regen_delay
		ply.health_on_dmg = ply:Health() - amt

end)


hook.Add("Think", "GryMod health think", function()
	for k, ply in pairs(player.GetAll()) do
		if not ply:Alive() then continue end
		if ply.next_health_regen and (ply.next_health_regen < CurTime()) then
			if (ply:Health() >= ply:GetMaxHealth()) then
				ply.next_health_regen = 0
				
			else
				ply:SetHealth(math.min(ply:GetMaxHealth(), ply.health_on_dmg + (CurTime() - ply.next_health_regen) * health_regen_speed))
			end
		end

		local curenergy = ply:GetNWInt("GryEnergy")

		if (ply.next_energy_regen and ply.next_energy_regen < CurTime()) then
			if (curenergy >= 100) then
				ply.next_energy_regen = 0
				
			else
				ply:SetNWInt("GryEnergy", math.min(100, ply.energy_on_use + (CurTime() - ply.next_energy_regen) * energy_regen_speed))
				if ply:GetNWBool("Speed") == true then
					ply:SetRunSpeed(600)
				end
			end
		end
	end
end)