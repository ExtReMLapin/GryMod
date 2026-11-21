-- the numbers of the rules are in sv_mechanics.lua (gry_mechanics: crysis or classic)
local health_regen_speed = 17 -- per sec, the classic continuous regeneration

util.AddNetworkString("gry_start_health_regen")
util.AddNetworkString("gry_stop_health_regen")

local Mech = GryMod.Mech

-- The armor hit sound, from the original game (BasicActor.lua Client:OnHit, and the armor read by CPlayer): only the
-- player hit hears it, for bullet damage over 10 (of the game's 200 health, so 5 percent of the maximum health),
-- in armor mode, with the armor still over 10 after the hit (a tenth of the bar: the game's 20 of 200 energy).
-- gry_mechanics classic keeps the earlier rule: any bullet while the bar is not empty.
function Mech.ArmorHitSoundDue(mode, isBullet, damage, maxHealth, energyBefore, energyAfter)
	if mode ~= GryMod.Modes.ARMOR or not isBullet then
		return false
	end

	if not Mech.IsCrysis() then
		return energyBefore > 0
	end

	return damage > 10 * maxHealth / 200 and energyAfter > 10
end

-- The repair sound (suit_medical_use_new) lasts 5.95 seconds and nothing in the game's code stops it before the end.
Mech.RepairSoundSeconds = 5.95

function Mech.RepairSoundPlaying(ply, now)
	return Mech.IsCrysis() and ply.last_repair_sound ~= nil and now - ply.last_repair_sound < Mech.RepairSoundSeconds
end

hook.Add("PlayerSpawn", "GryMod_ENER_HLT_VARS", function(ply)
	ply.last_repair_sound = nil
	ply.next_health_regen = CurTime()
	ply.health_on_dmg = ply:Health()
	ply.should_heath_regen = false

	ply.next_energy_regen = CurTime()
	ply.energy_on_use = ply:GetNWFloat("GryEnergy")
end)

-- need to be called AFTER the energy drain
hook.Add("GryUseEnergy", "grymod energy usage", function(ply)
	local amnt = ply:GetNWFloat("GryEnergy")
	ply.next_energy_regen = CurTime() + GryMod.Mech.EnergyRechargeDelay()
	ply.energy_on_use = amnt

	if ply.Nanosuit_mode == GryMod.Modes.SPEED and (amnt <= 0 or GryMod.Mech.SpeedDrain(amnt) * FrameTime() > amnt) then
		ply:SetRunSpeed(400)
	end
end)


hook.Add("PlayerDeath","grymod death stop healing sound", function (ply)
	if (ply.should_heath_regen or Mech.RepairSoundPlaying(ply, CurTime())) then
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

	-- electric hits burn energy and heavy impacts can put the suit down (sv_malfunction.lua)
	if GryMod.Malfunction then
		GryMod.Malfunction.OnDamage(ply, dmginfo)
	end

	if ply.Nanosuit_mode == GryMod.Modes.ARMOR then
		local energy = ply:GetNWFloat("GryEnergy")
		-- what the bar holds once the hit is taken (the infinite armor takes nothing)
		local energyAfter = GryMod.Config.InfiniteArmor and energy or math.max(0, energy - amt)

		if Mech.ArmorHitSoundDue(ply.Nanosuit_mode, dmginfo:IsBulletDamage(), amt, ply:GetMaxHealth(), energy, energyAfter) then
			net.Start("gry_armor_hit_sound")
			net.Send(ply)
		end
	end

	if ply.Nanosuit_mode == GryMod.Modes.ARMOR and GryMod.Config.InfiniteArmor then
		-- the armor never runs out
		dmginfo:SetDamage(0)

		return
	end

	if ply.Nanosuit_mode == GryMod.Modes.ARMOR then
		local energy = ply:GetNWFloat("GryEnergy")


		if (amt > energy) then
			ply:SetNWFloat("GryEnergy", 0)
			local diff = amt - energy
			-- the armor takes at least a part of the hit even with an empty bar (the original game: 30 percent)
			dmginfo:SetDamage(math.min(diff, amt * (1 - GryMod.Mech.ArmorMinimumAbsorption())))
		else
			dmginfo:SetDamage(0)
			ply:SetNWFloat("GryEnergy", ply:GetNWFloat("GryEnergy") - amt)
			hook.Run("GryUseEnergy", ply)
			return
		end

		hook.Run("GryUseEnergy", ply)
	end


	ply.next_health_regen = CurTime() + GryMod.Mech.HealthDelay()
	ply.next_health_tick = nil
	
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

		-- The repair sound is not tied to the regeneration or to its steps (the game checks it every frame, with no
		-- delay after a hit): armor mode, under 90 percent of the health, 30 seconds apart, played to its end.
		if GryMod.Config.ShouldRegen and Mech.RepairSoundDue(ply:Health(), ply:GetMaxHealth(), ply.Nanosuit_mode, CurTime(), ply.last_repair_sound) then
			ply.last_repair_sound = CurTime()
			net.Start("gry_start_health_regen")
			net.Send(ply)
		end

		if not GryMod.Config.ShouldRegen then
			-- regeneration switched off (gry_Health): stop the healing sound if it was playing
			if ply.should_heath_regen then
				ply.should_heath_regen = false
				net.Start("gry_stop_health_regen")
				net.Send(ply)
			end
		elseif ply.next_health_regen and (ply.next_health_regen < CurTime()) then
			local Mech = GryMod.Mech

			if (ply:Health() >= ply:GetMaxHealth()) then
				if (ply.should_heath_regen) then
					ply.should_heath_regen = false
					net.Start("gry_stop_health_regen")
					net.Send(ply)
				end
				ply.next_health_regen = 0
				ply.next_health_tick = nil
			elseif Mech.IsCrysis() then
				local now = CurTime()

				-- health comes back in whole steps once a second (the fraction is carried to the next step)
				if not ply.next_health_tick or now >= ply.next_health_tick then
					ply.next_health_tick = now + Mech.HealthStepSeconds()
					local gain = ply:GetMaxHealth() / Mech.HealthRegenSeconds(ply.Nanosuit_mode, Mech.IsMoving(ply)) + (ply.health_remainder or 0)
					local whole = math.floor(gain)
					ply.health_remainder = gain - whole
					ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + whole))
				end
			else
				if not ply.should_heath_regen then
					net.Start("gry_start_health_regen")
					net.Send(ply)
					ply.should_heath_regen = true
				end
				-- never lower the health: a medkit used during the delay must not be lost
				local target = math.min(ply:GetMaxHealth(), ply.health_on_dmg + (CurTime() - ply.next_health_regen) * health_regen_speed)

				if target > ply:Health() then
					ply:SetHealth(target)
				end
			end
		end

		if GryMod.Config.InfiniteArmor then
			ply:SetNWFloat("GryEnergy", 100)
		end

		local curenergy = ply:GetNWFloat("GryEnergy")

		-- a suit that is down does not recharge (sv_malfunction.lua)
		if (ply.next_energy_regen and ply.next_energy_regen < CurTime()) and not (GryMod.Malfunction and GryMod.Malfunction.IsActive(ply)) then
			if (curenergy >= 100) then
				ply.next_energy_regen = 0
			else
				if GryMod.Mech.IsCrysis() then
					-- the rate depends on the mode and on moving: given back a frame at a time
					local rate = GryMod.Mech.EnergyRechargeRate(ply.Nanosuit_mode, GryMod.Mech.IsMoving(ply))
					ply:SetNWFloat("GryEnergy", math.min(100, curenergy + rate * FrameTime()))
				else
					ply:SetNWFloat("GryEnergy", math.min(100, ply.energy_on_use + (CurTime() - ply.next_energy_regen) * GryMod.Mech.EnergyRechargeRate(ply.Nanosuit_mode, false)))
				end

				if ply.Nanosuit_mode == GryMod.Modes.SPEED then
					ply:SetRunSpeed(600)
				end
			end
		end
	end
end)