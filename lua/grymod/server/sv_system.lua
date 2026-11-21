util.AddNetworkString("gry_nanosuit_mode_change")
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")
util.AddNetworkString("gry_drop")
util.AddNetworkString("gry_empty_energy")
util.AddNetworkString("gry_cloak_shot")
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
	ply:SetNW2Float("GryEnergy", 100)
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

-- Tells the client the mode the server really keeps (a refused request leaves both sides in step).
local function tellMode(ply, mode)
	net.Start("gry_nanosuit_mode_change")
	net.WriteUInt(mode, 3)
	net.Send(ply)
end

-- Puts the suit in a mode. Every path that changes the mode goes through here: the client's request, the cloak running
-- out, a malfunction, the extension API (GryMod.API.SetMode). Returns true, or false and why the suit stayed as it was or
-- went to armor instead: "dead", "malfunction", "disabled" (the suit is off: GryMod.API.SetSuitEnabled), "vetoed".
-- The armor is the suit's safe state: it is never vetoed (a malfunction, an empty bar or a respawn must always reach it).
function meta:SetNanosuitMode(mode, networked)
	if not self:Alive() then
		return false, "dead"
	end

	local refused

	-- a suit that is down or off stays in armor mode (sv_malfunction.lua, sv_api.lua); the client is told the real mode
	if mode ~= GryMod.Modes.ARMOR then
		if GryMod.Malfunction and GryMod.Malfunction.IsActive(self) then
			refused = "malfunction"
		elseif self:GetNW2Bool("GryDisabled", false) then
			refused = "disabled"
		end

		if refused then
			mode = GryMod.Modes.ARMOR
			networked = true
		elseif mode ~= (self.Nanosuit_mode or GryMod.Modes.ARMOR) and hook.Run("GryMod_CanSetMode", self, mode) == false then
			-- another addon refuses this mode (veto): nothing changes, and the client is told, as for any refused request
			tellMode(self, self.Nanosuit_mode or GryMod.Modes.ARMOR)

			return false, "vetoed"
		end
	end

	local oldMode = self.Nanosuit_mode or GryMod.Modes.ARMOR

	-- the speeds of the mode: GryMod's own or, with gry_movement, the original game's (sv_movement.lua)
	GryMod.Movement.Apply(self, mode)

	if (mode == GryMod.Modes.STRENGTH) then
		self:SetJumpPower(500)
	else
		self:SetJumpPower(200)
	end

	local hands = self:GetHands()

	if (mode == GryMod.Modes.CLOAK) then
		-- the look is made on each client from this switch (cl_cloak_fx.lua): the picture behind the player is bent,
		-- and it fades in and out. A client that turned it off (gry_cloak_fx 0) puts the old material on itself.
		self:SetNW2Bool("GryCloak", true)
		self:SetNoTarget(true)
		self:DrawWorldModel(false)
	else
		self:SetNW2Bool("GryCloak", false)
		self:SetMaterial("")

		if IsValid(hands) then
			hands:SetMaterial("")
		end

		self:SetNoTarget(false)
		self:DrawWorldModel(true)
	end

	self.Nanosuit_mode = mode
	hook.Run("GryNanosuitMode", self, mode) -- sv_cloak_ai.lua: the NPCs forget a camouflaged player

	if mode ~= oldMode then
		hook.Run("GryMod_ModeChanged", self, mode, oldMode)
	end

	if networked then
		tellMode(self, mode)
	end

	return refused == nil, refused
end

-- The camouflage ends when the player shoots. The client judges the press of the key by the numbers of the weapon (cl_hud.lua), which is a
-- guess; bullets leaving the weapon are the shot itself, and the engine tells every addon through EntityFireBullets (the engine's weapons,
-- the scripted ones, whatever their rules). Only bullets: a grenade, an energy ball, a lob, a swing leave through the client's rules.
-- The server sees it (in single player the client's weapon code does not run), so it is told to the player, who ends the camouflage (he
-- may have turned the right click off: gry_cloak_altfire is his).
--
-- Whose shot is this: the player's, or a scripted weapon's whose owner is a player; and only in the camouflage. Returns the player and whether it is an
-- alt fire (the right click alone is down), or nothing.
function GryMod.CloakShooter(ent)
	if not IsValid(ent) then return nil end

	local ply = ent

	if ent:IsWeapon() then
		ply = ent:GetOwner()
	end

	if not IsValid(ply) or not ply:IsPlayer() or ply.Nanosuit_mode ~= GryMod.Modes.CLOAK then
		return nil
	end

	return ply, ply:KeyDown(IN_ATTACK2) and not ply:KeyDown(IN_ATTACK)
end

-- Every bullet of the server goes through here: the check is cheap and nothing is returned (the bullets are left as they are).
hook.Add("EntityFireBullets", "GryCloakShot", function(ent, data)
	local ply, alt = GryMod.CloakShooter(ent)

	if not ply then return end

	net.Start("gry_cloak_shot")
	net.WriteBool(alt)
	net.Send(ply)
end)

net.Receive("gry_empty_energy", function(len, ply)
	ply:SetNW2Float("GryEnergy", 0)
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
		local available = ply:GetNW2Float("GryEnergy")

		if speedCost > 0 and available >= speedCost then
			ply:SetNW2Float("GryEnergy", available - speedCost)
			hook.Run("GryUseEnergy", ply)
		end

		return
	end

	if key ~= IN_JUMP or not ply:Alive() or ply.Nanosuit_mode ~= GryMod.Modes.STRENGTH then
		return
	end

	local energy = ply:GetNW2Float("GryEnergy")
	local infinite = GryMod.Config.InfiniteArmor

	local cost = GryMod.Mech.JumpCost(GryMod.Modes.STRENGTH)

	if (infinite or energy >= cost) and ply:OnGround() then
		ply:SetJumpPower(500)

		if not infinite then
			ply:SetNW2Float("GryEnergy", energy - cost)
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

-- Is the player really using the Speed mode (sprinting fast enough, on the ground or swimming)? The one test of the
-- sprint drain below and of the rate told to the client (GryMod.EnergyRate in sv_health.lua).
function GryMod.IsSpeedSprinting(ply)
	return ply:IsSprinting() == true and ply:GetVelocity():LengthSqr() > 170000 and (ply:IsOnGround() or ply:WaterLevel() > 1) and ply.Nanosuit_mode == GryMod.Modes.SPEED and not GryMod.Config.InfiniteArmor
end

hook.Add("Think", "GrySpeedThink", function()
	for k, v in pairs(player.GetAll()) do
		local amnt = v:GetNW2Float("GryEnergy")
		local amnt_to_drain = GryMod.Mech.SpeedDrain(amnt) * FrameTime()

		if GryMod.IsSpeedSprinting(v) then
			-- an empty bar or a drain that cannot be paid: nothing is taken (the run speed follows the energy, sv_mechanics.lua)
			if amnt_to_drain <= amnt and amnt > 0 then
				v:SetNW2Float("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

hook.Add("Think", "GryCloakThink", function()
	for k, v in pairs(player.GetAll()) do
		if v.Nanosuit_mode == GryMod.Modes.CLOAK and not GryMod.Config.InfiniteArmor then
			v:DrawWorldModel(false) -- Because the WeaponEquip/Switch is not working
			local amnt = v:GetNW2Float("GryEnergy")
			local amnt_to_drain = GryMod.Mech.CloakDrain(v:GetVelocity():Length()) * FrameTime()

			if amnt_to_drain > amnt or GryMod.Mech.CloakFailsAt(amnt) then
				v:SetNanosuitMode(GryMod.Modes.ARMOR, true)
			else
				v:SetNW2Float("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

-- The server console has no player: it is allowed, like any admin
local function mayConfigure(ply)
	return not IsValid(ply) or ply:IsAdmin()
end

-- also the rule of the administrators' settings of the options panel (sv_server_options.lua)
GryMod.MayConfigure = mayConfigure

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
