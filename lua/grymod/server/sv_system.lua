local util = util
local net = net
local hook = hook
local timer = timer
local concommand = concommand
-- fak u i comnt in frech 
util.AddNetworkString("cloak_start") -- Les util du cloak sont utilisés pour signaler le changement du material de Viewmodel
util.AddNetworkString("armor_start")
util.AddNetworkString("speed_start")
util.AddNetworkString("strenght_start")
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")

GryMod.Config = {
	ShouldRegen = true,
	InfiniteArmor = false,
	speedEnergyDrain = 25
}

--CreateConVar( "GryMod", 1, false, false )
hook.Add("PlayerSpawn", "GryModSpawn", function(ply)
	GryMod.Armor(ply)
	ply:SetNWInt("GryEnergy", 100)
	
	net.Start("gry_spawn")
	net.Send(ply)
end)

function GryMod.Strenght(ply)
	if ply:Alive() then
		ply:SetWalkSpeed(200)
		ply:SetRunSpeed(400)
		ply:SetJumpPower(500)
		ply:SetMaterial("")
		--ply:EmitSound("suit/strength.mp3", 100, 100)
		ply:SetNoTarget(false)
		ply:SetNWBool("Strenght", true)
		ply:SetNWBool("Armor", false)
		ply:SetNWBool("Speed", false)
		ply:SetNWBool("Cloak", false)
		ply:DrawWorldModel(true)

		net.Start("strenght_start")
		net.Send(ply)
	end
end

concommand.Add("Strength", GryMod.Strenght)

function GryMod.Speed(ply)
	if ply:Alive() then
		ply:SetNWBool("Strenght", false)
		ply:SetNWBool("Armor", false)
		ply:SetNWBool("Speed", true)
		ply:SetNWBool("Cloak", false)
		ply:DrawWorldModel(true)
		ply:SetWalkSpeed(400)
		ply:SetRunSpeed(600)
		ply:SetJumpPower(200)
		--ply:EmitSound("suit/speed.mp3", 100, 100)
		ply:SetMaterial("")
		ply:SetNoTarget(false)

		net.Start("speed_start")
		net.Send(ply)
	end
end

concommand.Add("Speed", GryMod.Speed)

function GryMod.Cloak(ply)
	if ply:Alive() then
		ply:SetMaterial("cloak/organic")
		ply:GetHands():SetMaterial("cloak/organic")
		ply:SetWalkSpeed(200)
		ply:SetRunSpeed(400)
		--ply:EmitSound("suit/cloak.mp3", 100, 100)
		ply:SetNoTarget(true)
		ply:SetJumpPower(200)
		ply:SetNWBool("Strenght", false)
		ply:SetNWBool("Armor", false)
		ply:SetNWBool("Speed", false)
		ply:SetNWBool("Cloak", true)
		ply:DrawWorldModel(false)
		net.Start("cloak_start")
		net.Send(ply)
	end
end

concommand.Add("Cloak", GryMod.Cloak)

function GryMod.Armor(ply)
	if ply:Alive() then
		ply:SetWalkSpeed(200)
		ply:SetRunSpeed(400)
		ply:SetJumpPower(200)
		--ply:EmitSound("suit/armor.mp3", 100, 100)
		ply:SetMaterial("")
		ply:SetNoTarget(false)
		ply:SetNWBool("Strenght", false)
		ply:SetNWBool("Armor", true)
		ply:SetNWBool("Speed", false)
		ply:SetNWBool("Cloak", false)
		ply:DrawWorldModel(true)
		net.Start("armor_start")
		net.Send(ply)
	end
end

concommand.Add("Armor", GryMod.Armor)

function GryMod.ArmorFUUUUU(ply)
	ply:SetNWInt("GryEnergy", 0)
end

concommand.Add("ArmorFUUUUU", GryMod.ArmorFUUUUU)

function GryMod.Drop(ply)
	if IsValid(ply:GetActiveWeapon()) then
		ply:DropWeapon(ply:GetActiveWeapon()) --Drop active weapon
	end
end

concommand.Add("Drop", GryMod.Drop)


function GryMod.SuperJump(ply, key)
	if ply:Alive() and ply:GetNWBool("Strenght", true) and ply:GetNWInt("GryEnergy") >= 40 and ply:OnGround() and not GryMod.Config.InfiniteArmor and key == IN_JUMP then
		ply:SetJumpPower(500)
		ply:SetNWInt("GryEnergy", ply:GetNWInt("GryEnergy") - 40)
		hook.Run("GryUseEnergy", ply)
		ply.ps = true
		net.Start("gry_jump")
		net.Send(ply)
	end

	if ply:Alive() and ply:GetNWBool("Strenght", true) and ply:GetNWInt("GryEnergy") < 40 and ply.ps == false then
		ply:SetJumpPower(200)
		ply.ps = true
	end
end

-- Cost 40 enery point
hook.Add("KeyPress", "KeyPressedStrenghtGry", GryMod.SuperJump)

function GryMod.RSuperJump(ply, key)
	if key == IN_JUMP then
		ply.ps = false
	end
end

hook.Add("KeyRelease", "keyreleasestrenghtgry", GryMod.RSuperJump)

function GryMod.Speedsystem()
	for k, v in pairs(player.GetAll()) do
		local amnt_to_drain = GryMod.Config.speedEnergyDrain * FrameTime()
		local amnt = v:GetNWInt("GryEnergy")
		if v:IsSprinting() == true and v:GetNWBool("Speed", true) and not GryMod.Config.InfiniteArmor then
			if amnt_to_drain > amnt then
				ply:SetRunSpeed(400)
			else
				v:SetNWInt("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end

	timer.Simple(0.1, GryMod.Speedsystem)
end

GryMod.Speedsystem()

function GryMod.Cloaksystem()
	for k, v in pairs(player.GetAll()) do
		if v:GetNWBool("Cloak", true) and not GryMod.Config.InfiniteArmor then
			v:DrawWorldModel(false) -- Because the WeaponEquip/Switch is not working
			v:SetNWInt("GryEnergy", (v:GetNWInt("GryEnergy") - (0.092 + (0.001 * v:GetVelocity():Length()))))
			hook.Run("GryUseEnergy", v)
		end
	end

	timer.Simple(0.1, GryMod.Cloaksystem)
end

GryMod.Cloaksystem()

/*function GryMod.FixEnergySuitMod(ply)
	if ply:GetNWInt("GryEnergy") <= 0 then
		GryMod.Armor(ply)
		ply:SetNWInt("GryEnergy", 0)
	end
end

hook.Add("GryUseEnergy", "SuitMod Auto", GryMod.FixEnergySuitMod)*/

concommand.Add("gry_Armor", function(ply)
	if ply:IsAdmin() then
		GryMod.Config.InfiniteArmor = not GryMod.Config.InfiniteArmor
	end
end)

-- wew sush cedng skilz
concommand.Add("gry_Health", function(ply)
	if ply:IsAdmin() then
		GryMod.Config.ShouldRegen = not GryMod.Config.ShouldRegen
	end
end)