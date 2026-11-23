-- The class of an entity, for the use prompt (cl_usable_class.lua). The client cannot name many of the brush entities of the game: for a func_button, a
-- momentary_rot_button or a func_rot_button its ent:GetClass() is the name of the network class ("class C_BaseToggle"), so the registry of usable things
-- (sh_api_usable.lua) could never match a button or a wheel. The client asks, only for an entity like that which it aims at, and the server answers with
-- the class name the map gave it.
--
-- Cost: nothing runs by itself. The client asks (gry_class_ask: an entity index, 13 bits) once for such an entity and again every few seconds while it
-- stays aimed; the server answers the asker only (gry_class: the index and the name). A player may ask 10 times a second at most.

util.AddNetworkString("gry_class_ask")
util.AddNetworkString("gry_class")

GryMod = GryMod or {}

local UsableClass = GryMod.UsableClass or {}
GryMod.UsableClass = UsableClass

local LIMIT = 10 -- questions per player per window
local WINDOW = 1 -- seconds

local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}

-- The class of an entity, or nil when it is not a valid entity.
function UsableClass.Of(ent)
	if not ent or not isfunction(ent.IsValid) or not ent:IsValid() or not isfunction(ent.GetClass) then
		return nil
	end

	return ent:GetClass()
end

-- Whether the player may ask now (10 a second).
function UsableClass.Allowed(ply, now)
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

function UsableClass.Forget(ply)
	windows[ply] = nil
end

-- The answer to one message: `reply(player, index, class)` is called unless the player asked too much or the entity is gone.
function UsableClass.Handle(ply, index, now, reply)
	if not IsValid(ply) or not UsableClass.Allowed(ply, now) then
		return
	end

	local class = UsableClass.Of(Entity(index))

	if class then
		reply(ply, index, class)
	end
end

local function send(ply, index, class)
	net.Start("gry_class")
	net.WriteUInt(index, 13)
	net.WriteString(class)
	net.Send(ply)
end

net.Receive("gry_class_ask", function(_, ply)
	UsableClass.Handle(ply, net.ReadUInt(13), RealTime(), send)
end)

hook.Add("PlayerDisconnected", "GryMod usable class", function(ply)
	windows[ply] = nil
end)
