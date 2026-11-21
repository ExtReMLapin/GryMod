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
	-- the run speed of the speed mode follows the energy in its own Think hook (sv_mechanics.lua)
end)


-- PostPlayerDeath, not PlayerDeath: it is the one hook that every death goes through, Player:KillSilent included. Running it
-- twice does nothing more: the sound is over for the player once it has been stopped.
hook.Add("PostPlayerDeath","grymod death stop healing sound", function (ply)
	if (ply.should_heath_regen or Mech.RepairSoundPlaying(ply, CurTime())) then
		ply.should_heath_regen = false
		ply.last_repair_sound = nil
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

	-- the armor below can take all of the hit and the hooks run in no fixed order: the damage arrows and the hit marker
	-- are told from here, with the amount the hit came with (sv_feedback.lua leaves the hits on players to this hook)
	if GryMod.Feedback then
		GryMod.Feedback.OnHit(ply, dmginfo:GetAttacker(), amt)
	end

	-- electric hits burn energy and heavy impacts can put the suit down (sv_malfunction.lua)
	if GryMod.Malfunction then
		GryMod.Malfunction.OnDamage(ply, dmginfo)
	end

	-- a suit that is off (GryMod.API.SetSuitEnabled) has no armor: the hit goes through and the bar is not touched
	local armorOn = ply.Nanosuit_mode == GryMod.Modes.ARMOR and not ply:GetNWBool("GryDisabled", false)

	if armorOn then
		local energy = ply:GetNWFloat("GryEnergy")
		-- what the bar holds once the hit is taken (the infinite armor takes nothing)
		local energyAfter = GryMod.Config.InfiniteArmor and energy or math.max(0, energy - amt)

		if Mech.ArmorHitSoundDue(ply.Nanosuit_mode, dmginfo:IsBulletDamage(), amt, ply:GetMaxHealth(), energy, energyAfter) then
			net.Start("gry_armor_hit_sound")
			net.Send(ply)
		end
	end

	if armorOn and GryMod.Config.InfiniteArmor then
		-- the armor never runs out
		dmginfo:SetDamage(0)

		return
	end

	if armorOn then
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

		-- a suit that is down does not recharge (sv_malfunction.lua), nor one that is off (GryMod.API.SetSuitEnabled)
		if (ply.next_energy_regen and ply.next_energy_regen < CurTime()) and not (GryMod.Malfunction and GryMod.Malfunction.IsActive(ply)) and not ply:GetNWBool("GryDisabled", false) then
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
			end
		end
	end
end)

-- ---------------------------------------------------------------------------------------------------------
-- The energy to the client. The networked float (SetNWFloat) is only flushed to the client about every 0.1 s
-- (measured: 9.4 distinct values a second, whatever the tick rate), so a sprint reached the bar in steps of 4 to
-- 5 points. The original game gives its HUD the energy at every frame. Here the value goes in a small unreliable
-- message (gry_energy) at every tick it changes, with the rate of change in units a second: the client
-- predicts between two ticks (cl_energy_smooth.lua). gry_energy_net 0 leaves the networked float alone.
-- ---------------------------------------------------------------------------------------------------------

util.AddNetworkString("gry_energy")

local energyNet = CreateConVar("gry_energy_net", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY), -- replicated: the options panel of an admin shows its real value
	"Send the suit energy to the player at every tick (smooth HUD bar) instead of only through the networked float")

-- Energy per second that the Think hooks give or take at this moment, as they will apply it (0 when the bar does not
-- move, or when the next tick may change the rule: the cloak or the speed sprint about to give out).
function GryMod.EnergyRate(ply)
	if not ply:Alive() or GryMod.Config.InfiniteArmor or ply:GetNWBool("GryDisabled", false) then
		return 0
	end

	local energy = ply:GetNWFloat("GryEnergy")
	local Mech = GryMod.Mech

	-- GryCloakThink (sv_system.lua)
	if ply.Nanosuit_mode == GryMod.Modes.CLOAK then
		local drain = Mech.CloakDrain(ply:GetVelocity():Length())

		if drain * FrameTime() > energy or Mech.CloakFailsAt(energy) then
			return 0
		end

		return -drain
	end

	-- GrySpeedThink (sv_system.lua)
	if GryMod.IsSpeedSprinting(ply) then
		local drain = Mech.SpeedDrain(energy)

		if energy > 0 and drain * FrameTime() <= energy then
			return -drain
		end
	end

	-- the recharge above
	if energy < 100 and ply.next_energy_regen and ply.next_energy_regen < CurTime() and not (GryMod.Malfunction and GryMod.Malfunction.IsActive(ply)) then
		return Mech.EnergyRechargeRate(ply.Nanosuit_mode, Mech.IsCrysis() and Mech.IsMoving(ply))
	end

	return 0
end

hook.Add("Think", "GryMod energy net", function()
	if not energyNet:GetBool() then
		return
	end

	for _, ply in ipairs(player.GetHumans()) do
		local energy = ply:GetNWFloat("GryEnergy")
		local rate = GryMod.EnergyRate(ply)
		local sent = ply.gryEnergySent

		if not sent or sent[1] ~= energy or sent[2] ~= rate then
			sent = sent or {}
			sent[1], sent[2] = energy, rate
			ply.gryEnergySent = sent
			net.Start("gry_energy", true)
			net.WriteFloat(energy)
			net.WriteFloat(rate)
			net.Send(ply)
		end
	end
end)
