util.AddNetworkString("gry_nanosuit_mode_change")
util.AddNetworkString("gry_spawn")
util.AddNetworkString("gry_jump")
util.AddNetworkString("gry_empty_energy")
util.AddNetworkString("gry_cloak_shot")
util.AddNetworkString("gry_armor_hit_sound")
util.AddNetworkString("gry_client_ready")

GryMod.Config = {
	ShouldRegen = true,
	InfiniteArmor = false,
	speedEnergyDrain = 15,
	cloakEnergyDrain = 3
}

-- The two toggles of the administrators are real settings: replicated convars that the options panel shows as check boxes and changes through
-- the white list (sh_server_options.lua, sv_server_options.lua). ARCHIVED, like every other setting of the server panel: the choice of the
-- administrator is kept from one map and one session to the next (a server convar that is not archived is created again with its default at every
-- map load, so the check box seemed to forget its value). GryMod.Config stays what the rest of the code reads: it follows the convars (read here at
-- load, and a change callback on each), and the other code, the tests and the extension keep writing it.
local toggleFlags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

local healthRegen = CreateConVar("gry_health_regen", "1", toggleFlags,
	"1: the suit repairs the health over time; 0: no regeneration (the console command gry_Health flips it)", 0, 1)
local infiniteArmor = CreateConVar("gry_infinite_armor", "0", toggleFlags,
	"1: the suit never loses energy and no malfunction happens; 0: the normal rules (the console command gry_Armor flips it)", 0, 1)

-- Reads both convars into GryMod.Config (the table of the moment: a test or an addon may have replaced it).
function GryMod.SyncToggles()
	GryMod.Config.ShouldRegen = healthRegen:GetBool()
	GryMod.Config.InfiniteArmor = infiniteArmor:GetBool()
end

GryMod.SyncToggles()

-- the text of a convar as the engine reads a switch: 0 is off, any other number is on
local function isOn(text)
	return (tonumber(text) or 0) ~= 0
end

cvars.AddChangeCallback("gry_health_regen", function(_, _, new)
	GryMod.Config.ShouldRegen = isOn(new)
end, "GryMod_ToggleHealthRegen")

cvars.AddChangeCallback("gry_infinite_armor", function(_, _, new)
	GryMod.Config.InfiniteArmor = isOn(new)
end, "GryMod_ToggleInfiniteArmor")

-- The only modes a client is allowed to ask for (any other number is refused)
local selectableModes = {
	[GryMod.Modes.ARMOR] = true,
	[GryMod.Modes.SPEED] = true,
	[GryMod.Modes.CLOAK] = true,
	[GryMod.Modes.STRENGTH] = true
}

-- Does an addon that brought the player back with Player:Spawn (a ragdoll that gets up, a respawn in place) want the suit to keep its state? The hook
-- GryMod_CanResetOnSpawn(ply) is the veto: a handler that answers false keeps the energy, the mode and the camouflage (put on again in silence, see below),
-- the radar's tags, a malfunction in progress and the delays of the regeneration. Every PlayerSpawn hook of GryMod that resets something asks here (they run in
-- no fixed order), and the handlers are asked ONCE for a spawn: the answer is kept for the tick. A player who has no mode yet (his first spawn) has nothing to keep.
-- A handler that raises an error is not a veto and does not break the spawn.
GryMod.SpawnRestore = GryMod.SpawnRestore or {}

function GryMod.SpawnRestore.Reset(ply)
	if IsValid(ply) then
		ply.gryKeepSpawn = nil
	end
end

function GryMod.KeepStateOnSpawn(ply)
	if not IsValid(ply) or ply.Nanosuit_mode == nil then
		return false
	end

	local asked = ply.gryKeepSpawn
	local tick, now = engine.TickCount(), CurTime()

	if asked and asked.tick == tick and asked.time == now then
		return asked.keep
	end

	local ok, answer = pcall(hook.Run, "GryMod_CanResetOnSpawn", ply)

	if not ok then
		ErrorNoHalt("[GryMod] A handler of GryMod_CanResetOnSpawn failed: " .. tostring(answer) .. "\n")
		answer = nil
	end

	local keep = answer == false

	ply.gryKeepSpawn = {tick = tick, time = now, keep = keep}

	return keep
end

--CreateConVar( "GryMod", 1, false, false )
hook.Add("PlayerSpawn", "GryModSpawn", function(ply)
	if GryMod.KeepStateOnSpawn(ply) then
		-- the engine's Spawn erased the notarget flag, the material and the run speed: the mode that the player had is put on again, with no start-up of the HUD, no
		-- message (the client's mode did not change) and no announcement (it is the same mode)
		ply:SetNanosuitMode(ply.Nanosuit_mode, false, GryMod.ModeReasons.RESTORE)

		return
	end

	-- the energy first: a handler of GryMod_ModeChanged (cause SPAWN) runs inside SetNanosuitMode and must see the full bar of the new life
	ply:SetNW2Float("GryEnergy", 100)
	ply:SetNanosuitMode(GryMod.Modes.ARMOR, true, GryMod.ModeReasons.SPAWN)
	net.Start("gry_spawn")
	net.Send(ply)
end)

local meta = FindMetaTable("Player")

-- Tells the client the mode the server really keeps (a refused request leaves both sides in step), and why: `reason` is one of GryMod.ModeReasons; it
-- crosses the network as its id (GryMod.ModeReasonIds, ModeReasonBits wide) and the client makes the string of it again for the hook
-- GryMod_ModeChanged (cl_hud.lua). A missing or unknown cause goes as OTHER.
local function tellMode(ply, mode, reason)
	net.Start("gry_nanosuit_mode_change")
	net.WriteUInt(mode, 3)
	net.WriteUInt(GryMod.ModeReasonIds[reason] or GryMod.ModeReasonIds[GryMod.ModeReasons.OTHER], GryMod.ModeReasonBits)
	net.Send(ply)
end

-- Applies a mode asked by a client, and tells the client the real mode when the request is refused,
-- so both sides never stay out of sync.
function GryMod.SetModeFromClient(ply, mode)
	if not IsValid(ply) or not ply:Alive() then
		return
	end

	if not selectableModes[mode] then
		-- a refused request: the client undoes what it did at once (its change was optimistic)
		tellMode(ply, ply.Nanosuit_mode or GryMod.Modes.ARMOR, GryMod.ModeReasons.VETOED)

		return
	end

	ply:SetNanosuitMode(mode, false, GryMod.ModeReasons.PLAYER)
end

net.Receive("gry_nanosuit_mode_change", function(len, ply)
	GryMod.SetModeFromClient(ply, net.ReadUInt(3)) -- cheeeetaaa: that is why the mode is checked
end)

-- A client that has finished loading says so (cl_hud.lua, at InitPostEntity, and when its files are loaded again in a running game) and is told the
-- mode the server really keeps. The message of the spawn (above) is sent while the client may still be loading, and the engine does not deliver net
-- messages reliably before the client's InitPostEntity: the new player's suit would have no mode. The energy needs no message: it is a networked
-- float, which a client that joins gets in its first full update, and the message of the energy follows every change (sv_health.lua).
-- One answer per player and per second: a client cannot make the server send without end.
GryMod.ReadyInterval = 1

function GryMod.AnswerReady(ply)
	if not IsValid(ply) then
		return false
	end

	local now = CurTime()

	if ply.gryReadyAnswered and now - ply.gryReadyAnswered < GryMod.ReadyInterval then
		return false
	end

	ply.gryReadyAnswered = now
	tellMode(ply, ply.Nanosuit_mode or GryMod.Modes.ARMOR, GryMod.ModeReasons.SYNC)

	-- the modes a veto refuses (sv_mode_states.lua): the client is ready and knows nothing yet, so it is always told
	if GryMod.ModeStates and GryMod.ModeStates.Push then
		GryMod.ModeStates.Push(ply)
		GryMod.ModeStates.Sync()
	end

	return true
end

net.Receive("gry_client_ready", function(len, ply)
	GryMod.AnswerReady(ply)
end)

-- Puts the suit in a mode. Every path that changes the mode goes through here: the client's request, the cloak running
-- out, a malfunction, the extension API (GryMod.API.SetMode). Returns true, or false and why the suit stayed as it was or
-- went to armor instead: "dead", "malfunction", "disabled" (the suit is off: GryMod.API.SetSuitEnabled), "vetoed".
-- The armor is the suit's safe state: it is never vetoed (a malfunction, an empty bar or a respawn must always reach it).
-- `reason` (one of GryMod.ModeReasons, OTHER when left out) is the 4th argument of GryMod_ModeChanged, which runs when the mode changes and at EVERY
-- respawn (cause SPAWN, even armor to armor); with `networked` it is also sent to the client, which runs the same hook for its own player (cl_hud.lua). When the suit cannot take the mode asked (down or
-- off) it goes to armor and the reason is the real one (malfunction, disabled), not the asker's.
function meta:SetNanosuitMode(mode, networked, reason)
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
			reason = GryMod.ModeReasons[string.upper(refused)]
		elseif mode ~= (self.Nanosuit_mode or GryMod.Modes.ARMOR) and hook.Run("GryMod_CanSetMode", self, mode) == false then
			-- another addon refuses this mode (veto): nothing changes, and the client is told, as for any refused request
			tellMode(self, self.Nanosuit_mode or GryMod.Modes.ARMOR, GryMod.ModeReasons.VETOED)

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
		--
		-- The time of the activation goes BEFORE the switch (both reach a client in the same update): a client that first sees this player already
		-- camouflaged (it joins, or the player comes back into view) tells a change that is going on from one that was done long ago (cl_cloak_fx.lua,
		-- F.StartAmount). It is kept while the switch stays on: a second request for the camouflage is not a new activation.
		if not self:GetNW2Bool("GryCloak", false) then
			self:SetNW2Float("GryCloakSince", CurTime())
			-- the stamps of the cloak level (sh_cloak_level.lua), written before the switch: the level of this moment and the time
			self:SetNW2Float("GryCloakLvl0", GryMod.API.CloakLevel(self))
			self:SetNW2Float("GryCloakT0", CurTime())
		end

		self:SetNW2Bool("GryCloak", true)
		self:SetNoTarget(true)
		self:DrawWorldModel(false)
	else
		if reason == GryMod.ModeReasons.SPAWN then
			-- a respawn: the new life starts uncloaked at once, also when the old one died during a fade-out (the switch already off)
			self:SetNW2Float("GryCloakLvl0", 0)
			self:SetNW2Float("GryCloakT0", CurTime())
		elseif self:GetNW2Bool("GryCloak", false) then
			-- leaving the cloak: the level fades out from where it is
			self:SetNW2Float("GryCloakLvl0", GryMod.API.CloakLevel(self))
			self:SetNW2Float("GryCloakT0", CurTime())
		end

		self:SetNW2Bool("GryCloak", false)
		self:SetMaterial("")

		if IsValid(hands) then
			hands:SetMaterial("")
		end

		self:SetNoTarget(false)
		self:DrawWorldModel(true)
	end

	self.Nanosuit_mode = mode
	self:SetNW2Int("GryMode", mode) -- both sides know the mode (sh_suit_weapons.lua: the weapons' adapters)
	hook.Run("GryNanosuitMode", self, mode) -- sv_cloak_ai.lua: the NPCs forget a camouflaged player

	reason = reason or GryMod.ModeReasons.OTHER

	-- a change is announced; so is a respawn, always, even from armor to armor (a respawn is a new life of the suit, not a "same mode again")
	if mode ~= oldMode or reason == GryMod.ModeReasons.SPAWN then
		hook.Run("GryMod_ModeChanged", self, mode, oldMode, reason)
	end

	if networked then
		tellMode(self, mode, reason)
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
		-- a report for the addons: the jump is granted (and paid, unless the armor is infinite). Not for the weak jump below.
		hook.Run("GryMod_StrengthJump", ply)
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
	return ply:IsSprinting() == true and ply:GetVelocity():LengthSqr() > GryMod.Movement.SprintSpeedSqr() and (ply:IsOnGround() or ply:WaterLevel() > 1) and ply.Nanosuit_mode == GryMod.Modes.SPEED and not GryMod.Config.InfiniteArmor
end

hook.Add("Think", "GrySpeedThink", function()
	for _, v in ipairs(GryMod.Players.All()) do
		local amnt = v:GetNW2Float("GryEnergy")
		local amnt_to_drain = GryMod.Mech.SpeedDrain(amnt) * FrameTime()
		local sprinting = GryMod.IsSpeedSprinting(v)

		-- Reports for the addons (nothing is read from them), told here and not in a Think of their own: the start and the end of the
		-- speed sprint, once each. A change of mode, a death or the infinite armor ends the sprint for the rule above, so the end comes
		-- on the next tick. A dead player is not sprinting.
		local reported = sprinting and v:Alive()

		if reported and not v.gryApiSprint then
			v.gryApiSprint = true
			hook.Run("GryMod_SprintStart", v)
		elseif not reported and v.gryApiSprint then
			v.gryApiSprint = nil
			hook.Run("GryMod_SprintEnd", v)
		end

		if sprinting then
			-- an empty bar or a drain that cannot be paid: nothing is taken (the run speed follows the energy, sv_mechanics.lua)
			if amnt_to_drain <= amnt and amnt > 0 then
				v:SetNW2Float("GryEnergy", amnt - amnt_to_drain)
				hook.Run("GryUseEnergy", v)
			end
		end
	end
end)

-- A player who leaves while sprinting never comes back in the loop above: his End is told here, so a Start always gets its End.
hook.Add("PlayerDisconnected", "GryMod sprint report", function(ply)
	if ply.gryApiSprint then
		ply.gryApiSprint = nil
		hook.Run("GryMod_SprintEnd", ply)
	end
end)

hook.Add("Think", "GryCloakThink", function()
	for _, v in ipairs(GryMod.Players.All()) do
		-- a dead player keeps his mode until he respawns (sv_cloak_ai.lua) but pays nothing for it, and the camouflage does not "run out" on a body:
		-- the cause ENERGY is the one the HUD answers with "Temperature Camo: Disabled!", it is only asked for a player who is alive
		if v.Nanosuit_mode == GryMod.Modes.CLOAK and not GryMod.Config.InfiniteArmor and v:Alive() then
			v:DrawWorldModel(false) -- Because the WeaponEquip/Switch is not working
			local amnt = v:GetNW2Float("GryEnergy")
			local amnt_to_drain = GryMod.Mech.CloakDrain(v:GetVelocity():Length()) * FrameTime()

			if amnt_to_drain > amnt or GryMod.Mech.CloakFailsAt(amnt) then
				v:SetNanosuitMode(GryMod.Modes.ARMOR, true, GryMod.ModeReasons.ENERGY)
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

	-- the field is what the rules read, the convar is what the check box of the panel shows: both go to the same value (when the two had drifted apart
	-- the convar may already hold it, and then it fires no callback)
	local new = not GryMod.Config.InfiniteArmor

	infiniteArmor:SetBool(new)
	GryMod.Config.InfiniteArmor = new
	tell(ply, "Infinite armor: " .. onOff(new))

	return true
end

function GryMod.ToggleHealthRegen(ply)
	if not mayConfigure(ply) then
		return false
	end

	local new = not GryMod.Config.ShouldRegen

	healthRegen:SetBool(new)
	GryMod.Config.ShouldRegen = new
	tell(ply, "Health regeneration: " .. onOff(new))

	return true
end

concommand.Add("gry_Armor", function(ply)
	GryMod.ToggleInfiniteArmor(ply)
end)

concommand.Add("gry_Health", function(ply)
	GryMod.ToggleHealthRegen(ply)
end)
