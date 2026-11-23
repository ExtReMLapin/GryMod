-- The mass of a prop, for the use prompt ("PICK UP", cl_hud_crosshair_flash.lua). The game lets +use lift a prop only up to 35 kg
-- (CBasePlayer::CanPickupObject), and the client cannot read that mass: it has no physics object for a prop of the server (GetPhysicsObject is
-- invalid there). So the client asks, only for a liftable-looking prop it aims at, and the server answers with the mass the game itself uses.
--
-- Cost: nothing runs by itself, no timer, no networked variable on the props. The client asks (gry_mass_ask: an entity index, 13 bits) once for a
-- prop it aims at and again every few seconds while it stays aimed; the server answers the asker only (gry_mass: the index and the mass, a float).
-- A player may ask 10 times a second at most; the questions beyond are ignored.

util.AddNetworkString("gry_mass_ask")
util.AddNetworkString("gry_mass")

GryMod = GryMod or {}

local UsableMass = GryMod.UsableMass or {}
GryMod.UsableMass = UsableMass

local LIMIT = 10 -- questions per player per window
local WINDOW = 1 -- seconds

local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}

-- The mass of an entity in kg, all its physics objects added up (the game's own sum for a ragdoll), or nil when it has no physics.
function UsableMass.Of(ent)
	if not ent or not isfunction(ent.IsValid) or not ent:IsValid() then
		return nil
	end

	local total, found = 0, false

	if isfunction(ent.GetPhysicsObjectCount) and isfunction(ent.GetPhysicsObjectNum) then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local obj = ent:GetPhysicsObjectNum(i)

			if obj and isfunction(obj.IsValid) and obj:IsValid() then
				total = total + obj:GetMass()
				found = true
			end
		end
	elseif isfunction(ent.GetPhysicsObject) then
		local obj = ent:GetPhysicsObject()

		if obj and isfunction(obj.IsValid) and obj:IsValid() then
			total, found = obj:GetMass(), true
		end
	end

	return found and total or nil
end

-- Whether the player may ask now (10 a second).
function UsableMass.Allowed(ply, now)
	local w = windows[ply]

	if not w or now - w.start >= WINDOW then
		windows[ply] = {start = now, count = 1}

		return true
	end

	if w.count >= LIMIT then
		return false
	end

	w.count = w.count + 1

	return true
end

function UsableMass.Forget(ply)
	windows[ply] = nil
end

-- The answer to one message: `reply(player, index, mass)` is called unless the player asked too much or the entity has no physics.
function UsableMass.Handle(ply, index, now, reply)
	if not IsValid(ply) or not UsableMass.Allowed(ply, now) then
		return
	end

	local mass = UsableMass.Of(Entity(index))

	if mass then
		reply(ply, index, mass)
	end
end

local function send(ply, index, mass)
	net.Start("gry_mass")
	net.WriteUInt(index, 13)
	net.WriteFloat(mass)
	net.Send(ply)
end

net.Receive("gry_mass_ask", function(_, ply)
	UsableMass.Handle(ply, net.ReadUInt(13), RealTime(), send)
end)

hook.Add("PlayerDisconnected", "GryMod usable mass", function(ply)
	windows[ply] = nil
end)
