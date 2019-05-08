util.AddNetworkString("gry_nanosuit_mode_change")
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")
util.AddNetworkString("gry_drop")
util.AddNetworkString("gry_empty_energy")

GryMod.Config = {
	ShouldRegen = true,
	InfiniteArmor = false,
	speedEnergyDrain = 15,
	cloakEnergyDrain = 3
}

--CreateConVar( "GryMod", 1, false, false )
hook.Add("PlayerSpawn", "GryModSpawn", function(ply)
	ply:SetNanosuitMode(GryMod.Modes.ARMOR, true)
	ply:SetNWFloat("GryEnergy", 100)
	net.Start("gry_spawn")
	net.Send(ply)
end)

local meta = FindMetaTable("Player")

net.Receive("gry_nanosuit_mode_change", function(len, ply)
	if not ply:Alive() then
		return
	end

	-- cheeeetaaa
	local mode = net.ReadUInt(3)
	ply:SetNanosuitMode(mode, false)
end)

function meta:SetNanosuitMode(mode, networked)
	if not self:Alive() then
		return
	end

	if mode == GryMod.Modes.SPEED then
		self:SetWalkSpeed(400)
		self:SetRunSpeed(600)
	else
		self:SetWalkSpeed(200)
		self:SetRunSpeed(400)
	end

	if (mode == GryMod.Modes.STRENGTH) then
		self:SetJumpPower(500)
	else
		self:SetJumpPower(200)
	end

	if (mode == GryMod.Modes.CLOAK) then
		self:SetMaterial("cloak/organic")
		self:GetHands():SetMaterial("cloak/organic")
		self:SetNoTarget(true)
		self:DrawWorldModel(false)
	else
		self:SetMaterial("")

		if (IsValid(self:GetHands())) then
			self:GetHands():SetMaterial("")
		end

		self:SetNoTarget(false)
		self:DrawWorldModel(true)
	end

	self.Nanosuit_mode = mode

	if not networked then
		return
	end

	net.Start("gry_nanosuit_mode_change")
	net.WriteUInt(mode, 3)
	net.Send(self)
end

net.Receive("gry_empty_energy", function(len, ply)
	ply:SetNWFloat("GryEnergy", 0)
end)

net.Receive("gry_drop", function(len, ply)
	if IsValid(ply) and IsValid(ply:GetActiveWeapon()) then
		ply:DropWeapon(ply:GetActiveWeapon()) --Drop active weapon
	end
end)

function GryMod.SuperJump(ply, key)
	if ply:Alive() and ply.Nanosuit_mode == GryMod.Modes.STRENGTH and ply:GetNWFloat("GryEnergy") >= 40 and ply:OnGround() and not GryMod.Config.InfiniteArmor and key == IN_JUMP then
		ply:SetJumpPower(500)
		ply:SetNWFloat("GryEnergy", ply:GetNWFloat("GryEnergy") - 40)
		hook.Run("GryUseEnergy", ply)
		ply.ps = true
		net.Start("gry_jump")
		net.Send(ply)
	end

	if ply:Alive() and ply.Nanosuit_mode == GryMod.Modes.STRENGTH and ply:GetNWFloat("GryEnergy") < 40 and ply.ps == false then
		ply:SetJumpPower(200)
		ply.ps = true
	end
end

-- Cost 40 enery point
hook.Add("KeyPress", "KeyPressedStrengthGry", GryMod.SuperJump)

function GryMod.RSuperJump(ply, key)
	if key == IN_JUMP then
		ply.ps = false
	end
end

hook.Add("KeyRelease", "keyreleasestrengthgry", GryMod.RSuperJump)

hook.Add("Think", "GrySpeedThink", function()
	for k, v in pairs(player.GetAll()) do
		local amnt_to_drain = GryMod.Config.speedEnergyDrain * FrameTime()
		local amnt = v:GetNWFloat("GryEnergy")

		if v:IsSprinting() == true and v:GetVelocity():LengthSqr() > 50  and (v:IsOnGround() or v:WaterLevel() > 1) and v.Nanosuit_mode == GryMod.Modes.SPEED and not GryMod.Config.InfiniteArmor then
			if amnt_to_drain > amnt then
				v:SetRunSpeed(400)
			else
				v:SetNWFloat("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

hook.Add("Think", "GryCloakThink", function()
	for k, v in pairs(player.GetAll()) do
		if v.Nanosuit_mode == GryMod.Modes.CLOAK and not GryMod.Config.InfiniteArmor then
			v:DrawWorldModel(false) -- Because the WeaponEquip/Switch is not working
			local amnt = v:GetNWFloat("GryEnergy")
			local amnt_to_drain = GryMod.Config.cloakEnergyDrain * FrameTime() * (v:GetVelocity():Length() / 100 + 0.6)

			if amnt_to_drain > amnt then
				v:SetNanosuitMode(GryMod.Modes.ARMOR, true)
			else
				v:SetNWFloat("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

concommand.Add("gry_Armor", function(ply)
	if ply:IsAdmin() then
		GryMod.Config.InfiniteArmor = not GryMod.Config.InfiniteArmor
	end
end)

concommand.Add("gry_Health", function(ply)
	if ply:IsAdmin() then
		GryMod.Config.ShouldRegen = not GryMod.Config.ShouldRegen
	end
end)