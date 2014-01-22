
-- fak u i comnt in frech 
util.AddNetworkString( "cloak_stop" ) // Optimisation coté client + Anti bug
util.AddNetworkString( "cloak_start" ) // Les util du cloak sont utilisés pour signaler le changement du material de Viewmodel
util.AddNetworkString( "armor_start" )
util.AddNetworkString( "speed_start" )
util.AddNetworkString( "strenght_start" )
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")
local meta = FindMetaTable("Player")


--CreateConVar( "GryMod", 1, false, false )
  
 

 function Init_Suitmode(ply)
ply:SetNWBool("Strenght",false)
ply:SetNWBool("Armor",true)
ply:SetNWBool("Speed",false)
ply:SetNWBool("Cloak",false); ply:DrawWorldModel(true)
ply:SetMaterial("");
ply:SetNWInt("GryEnergy", 0)
ply.SP = false
net.Start("gry_spawn")
net.Send(ply)
 end
hook.Add( "PlayerSpawn", "problemson", Init_Suitmode )

function strenght(ply)
	if ply:Alive() then
		ply:SetWalkSpeed(150)
		ply:SetRunSpeed(300)
		ply:SetJumpPower(500)
		ply:SetMaterial("")
		ply:EmitSound("suit/strength.mp3", 100, 100)
		ply:SetNoTarget(false)
		ply:SetNWBool("Strenght",true)
		ply:SetNWBool("Armor",false)
		ply:SetNWBool("Speed",false)
		ply:SetNWBool("Cloak",false); ply:DrawWorldModel(true)
			net.Start("cloak_stop")
			net.Send(ply)

			net.Start("strenght_start")
			net.Send(ply)	
	end
end

concommand.Add("Strenght", strenght)




function speed(ply)
	if ply:Alive() then
		ply:SetNWBool("Strenght",false)
		ply:SetNWBool("Armor",false)
		ply:SetNWBool("Speed",true)
		ply:SetNWBool("Cloak",false); ply:DrawWorldModel(true)
		ply:SetWalkSpeed(300)
		ply:SetRunSpeed(600)
		ply:SetJumpPower(200)
		ply:EmitSound("suit/speed.mp3", 100, 100)
		ply:SetMaterial("")
		ply:SetNoTarget(false)
		
			net.Start("cloak_stop")
			net.Send(ply)	
			
			net.Start("speed_start")
			net.Send(ply)	
			
	end
end
concommand.Add("Speed", speed)

function cloak(ply)
if ply:Alive() then
	ply:SetMaterial("cloak/organic")
	ply:SetWalkSpeed(150)
	ply:SetRunSpeed(300)
	ply:EmitSound("suit/cloak.mp3", 100, 100)
	ply:SetNoTarget(true)
	ply:SetJumpPower(200)
	ply:SetNWBool("Strenght",false)
	ply:SetNWBool("Armor",false)
	ply:SetNWBool("Speed",false)
	ply:SetNWBool("Cloak",true); ply:DrawWorldModel(false);

			net.Start("cloak_start")
			net.Send(ply)	
end
end
concommand.Add("Cloak", cloak)
 

 
 
function armor(ply)
	if ply:Alive() then
	

ply:SetWalkSpeed(150)
ply:SetRunSpeed(300)
ply:SetJumpPower(200)
ply:EmitSound("suit/armor.mp3", 100, 100)
ply:SetMaterial("")
ply:SetNoTarget(false)
ply:SetNWBool("Strenght",false)
ply:SetNWBool("Armor",true)
ply:SetNWBool("Speed",false)
ply:SetNWBool("Cloak",false); ply:DrawWorldModel(true)
			net.Start("cloak_stop")
			net.Send(ply)	
			net.Start("armor_start")
			net.Send(ply)	
end
end
concommand.Add("Armor", armor)
 local function Drop(ply)
 if IsValid(ply:GetActiveWeapon()) then
		ply:DropWeapon(ply:GetActiveWeapon()) --Drop active weapon
		end
		
end
concommand.Add("Drop", Drop)

-- Starting energy system.
function IsMovingSpeed(ply, key)
	if ply:Alive()  then
		if key == IN_SPEED then 
		ply.SP = true
		end
	end
end
hook.Add( "KeyPress", "KeyPressedSpeedGry", IsMovingSpeed )

function RIsMovingSpeed(ply, key)
	if ply:Alive()   then
		if key == IN_SPEED then 
		--hook.Call("GryUseEnergyStop", ply, ply)
		ply.SP = false
		end
	end
end
hook.Add( "KeyRelease", "RKeyPressedSpeedGry", RIsMovingSpeed )

function SuperJump(ply, key) -- Cost 40 enery point
	if ply:Alive() and ply:GetNWBool("Strenght", true) and ply:GetNWInt("GryEnergy") >= 40 and ply:OnGround() then
		if key == IN_JUMP  then 
			ply:SetJumpPower(500)
			hook.Call("GryUseEnergy", ply, ply)
			ply:SetNWInt("GryEnergy", (ply:GetNWInt("GryEnergy") - 40))
			ply.ps = true
			net.Start("gry_jump")
			net.Send(ply)
		end
	end
	if ply:Alive() and ply:GetNWBool("Strenght", true) and ply:GetNWInt("GryEnergy") < 40 and ply.ps == false then
		ply:SetJumpPower(200)
		ply.ps = true	
	end
end
hook.Add( "KeyPress", "KeyPressedStrenghtGry", SuperJump )
function RSuperJump(ply, key)
	if key == IN_JUMP then 
ply.ps = false
	end
end
hook.Add("KeyRelease", "keyreleasestrenghtgry", RSuperJump)


function Speedsystem()
	for k, v in pairs(player.GetAll()) do
		if (v.SP == true) and v:GetNWBool("Speed", true) then 
		v:SetNWInt("GryEnergy", (v:GetNWInt("GryEnergy") - 1))
		hook.Call("GryUseEnergy", v, v, v)
		end
	 end
 timer.Simple(0.1,Speedsystem)
 end
Speedsystem()


function Cloaksystem()
	for k, v in pairs(player.GetAll()) do
		if v:GetNWBool("Cloak", true) then 
		v:DrawWorldModel(false) // Because the WeaponEquip/Switch is not working
		v:SetNWInt("GryEnergy", (v:GetNWInt("GryEnergy") - (0.092 + (0.001*v:GetVelocity():Length()))))
		hook.Call("GryUseEnergy", v, v, v)
		end
	 end
 timer.Simple(0.1,Cloaksystem)
 end
Cloaksystem()


function RealArmorGry(ply, dmginfo)
local infl = dmginfo:GetInflictor()
local att = dmginfo:GetAttacker()
local amount = dmginfo:GetDamage()
	if ply:IsPlayer() and ply:GetNWBool("Armor", true) then
		if amount < ply:GetNWInt("GryEnergy") then
			ply:SetNWInt("GryEnergy", ply:GetNWInt("GryEnergy") - amount)
			dmginfo:ScaleDamage(0.0001)
		end
		// Wow such maths
		if amount > ply:GetNWInt("GryEnergy") then
			local lam = (amount - ply:GetNWInt("GryEnergy"))
			ply:SetHealth(ply:Health() - lam)
			dmginfo:ScaleDamage(0)
		end
		
		hook.Call("GryUseEnergy", ply, ply)
	end


end
hook.Add("EntityTakeDamage", "ArmorGryTake", RealArmorGry)




function FixEnergySuitMod(ply)
if ply:GetNWInt("GryEnergy") < 0 then
armor(ply)
ply:SetNWInt("GryEnergy", 0)
end end
hook.Add("GryUseEnergy", "SuitMod Auto" , FixEnergySuitMod)