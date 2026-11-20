util.AddNetworkString("gry_nanosuit_mode_change")
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")
util.AddNetworkString("gry_drop")
util.AddNetworkString("gry_empty_energy")
util.AddNetworkString("gry_armor_hit_sound")

GryMod.Config = {
	ShouldRegen = true,
	InfiniteArmor = false,
	speedEnergyDrain = 15,
	cloakEnergyDrain = 3
}

-- The only modes a client is allowed to ask for (DROP is not a real mode, it only drops the weapon)
local selectableModes = {
	[GryMod.Modes.ARMOR] = true,
	[GryMod.Modes.SPEED] = true,
	[GryMod.Modes.CLOAK] = true,
	[GryMod.Modes.STRENGTH] = true
}

--CreateConVar( "GryMod", 1, false, false )
hook.Add("PlayerSpawn", "GryModSpawn", function(ply)
	ply:SetNanosuitMode(GryMod.Modes.ARMOR, true)
	ply:SetNWFloat("GryEnergy", 100)
	net.Start("gry_spawn")
	net.Send(ply)
end)

local meta = FindMetaTable("Player")

-- Applies a mode asked by a client, and tells the client the real mode when the request is refused,
-- so both sides never stay out of sync.
function GryMod.SetModeFromClient(ply, mode)
	if not IsValid(ply) or not ply:Alive() then
		return
	end

	if not selectableModes[mode] then
		net.Start("gry_nanosuit_mode_change")
		net.WriteUInt(ply.Nanosuit_mode or GryMod.Modes.ARMOR, 3)
		net.Send(ply)

		return
	end

	ply:SetNanosuitMode(mode, false)
end

net.Receive("gry_nanosuit_mode_change", function(len, ply)
	GryMod.SetModeFromClient(ply, net.ReadUInt(3)) -- cheeeetaaa: that is why the mode is checked
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

	local hands = self:GetHands()

	if (mode == GryMod.Modes.CLOAK) then
		self:SetMaterial("cloak/organic")

		-- some gamemodes do not give c_arms hands
		if IsValid(hands) then
			hands:SetMaterial("cloak/organic")
		end

		self:SetNoTarget(true)
		self:DrawWorldModel(false)
	else
		self:SetMaterial("")

		if IsValid(hands) then
			hands:SetMaterial("")
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
	-- count it as a use: otherwise the regeneration starts again from the energy of the last drain tick
	hook.Run("GryUseEnergy", ply)
end)

net.Receive("gry_drop", function(len, ply)
	if IsValid(ply) and IsValid(ply:GetActiveWeapon()) then
		ply:DropWeapon(ply:GetActiveWeapon()) --Drop active weapon
	end
end)

function GryMod.SuperJump(ply, key)
	if key == IN_JUMP and ply:Alive() and ply.Nanosuit_mode == GryMod.Modes.SPEED and ply:OnGround() and not GryMod.Config.InfiniteArmor then
		-- a jump in speed mode costs a little energy in the original game
		local speedCost = GryMod.Mech.JumpCost(GryMod.Modes.SPEED)
		local available = ply:GetNWFloat("GryEnergy")

		if speedCost > 0 and available >= speedCost then
			ply:SetNWFloat("GryEnergy", available - speedCost)
			hook.Run("GryUseEnergy", ply)
		end

		return
	end

	if key ~= IN_JUMP or not ply:Alive() or ply.Nanosuit_mode ~= GryMod.Modes.STRENGTH then
		return
	end

	local energy = ply:GetNWFloat("GryEnergy")
	local infinite = GryMod.Config.InfiniteArmor

	local cost = GryMod.Mech.JumpCost(GryMod.Modes.STRENGTH)

	if (infinite or energy >= cost) and ply:OnGround() then
		ply:SetJumpPower(500)

		if not infinite then
			ply:SetNWFloat("GryEnergy", energy - cost)
			hook.Run("GryUseEnergy", ply)
		end

		ply.ps = true
		net.Start("gry_jump")
		net.Send(ply)
	elseif energy < cost and not ply.ps then
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
		local amnt = v:GetNWFloat("GryEnergy")
		local amnt_to_drain = GryMod.Mech.SpeedDrain(amnt) * FrameTime()

		if v:IsSprinting() == true and v:GetVelocity():LengthSqr() > 170000  and (v:IsOnGround() or v:WaterLevel() > 1) and v.Nanosuit_mode == GryMod.Modes.SPEED and not GryMod.Config.InfiniteArmor then
			if amnt_to_drain > amnt or amnt <= 0 then
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
			local amnt_to_drain = GryMod.Mech.CloakDrain(v:GetVelocity():Length()) * FrameTime()

			if amnt_to_drain > amnt or GryMod.Mech.CloakFailsAt(amnt) then
				v:SetNanosuitMode(GryMod.Modes.ARMOR, true)
			else
				v:SetNWFloat("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

-- The server console has no player: it is allowed, like any admin
local function mayConfigure(ply)
	return not IsValid(ply) or ply:IsAdmin()
end

local function tell(ply, text)
	print("[GryMod] " .. text)

	if IsValid(ply) then
		ply:ChatPrint("[GryMod] " .. text)
	end
end

local function onOff(b)
	return b and "on" or "off"
end

function GryMod.ToggleInfiniteArmor(ply)
	if not mayConfigure(ply) then
		return false
	end

	GryMod.Config.InfiniteArmor = not GryMod.Config.InfiniteArmor
	tell(ply, "Infinite armor: " .. onOff(GryMod.Config.InfiniteArmor))

	return true
end

function GryMod.ToggleHealthRegen(ply)
	if not mayConfigure(ply) then
		return false
	end

	GryMod.Config.ShouldRegen = not GryMod.Config.ShouldRegen
	tell(ply, "Health regeneration: " .. onOff(GryMod.Config.ShouldRegen))

	return true
end

concommand.Add("gry_Armor", function(ply)
	GryMod.ToggleInfiniteArmor(ply)
end)

concommand.Add("gry_Health", function(ply)
	GryMod.ToggleHealthRegen(ply)
end)
