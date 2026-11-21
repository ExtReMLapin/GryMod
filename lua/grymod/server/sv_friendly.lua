-- Who is an ally for a player, for the friendly cross of the crosshair ("do not shoot", cl_hud_crosshair_flash.lua).
-- An NPC is an ally when its REAL attitude towards the player is like (D_LI): its class says nothing (the "Enemy Rebel" of
-- the NPC menu is an npc_citizen that hates the player). NPC:Disposition only exists on the server, so the client asks.
--
-- Cost: nothing runs by itself, no timer, no networked variable on the NPCs, no scan of the entities. The client asks
-- (gry_friendly_ask: an entity index, 13 bits) only while its crosshair is on an NPC, at most once a second for that NPC
-- and five times a second in all, and the server answers with one message (gry_friendly: the index and a bool) to the
-- asker only. A player may ask 5 times a second at most; the questions beyond are ignored (the client keeps the cross
-- closed without an answer). The relation can change at any time: the client asks again every second.

util.AddNetworkString("gry_friendly_ask")
util.AddNetworkString("gry_friendly")

GryMod = GryMod or {}

local Friendly = GryMod.Friendly or {}
GryMod.Friendly = Friendly

local LIMIT = 5 -- questions per player per window
local WINDOW = 1 -- seconds

local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}

-- Whether the entity is an ally for the player: a player of the same team (when the game has teams, i.e. not unassigned
-- 1001 nor spectator 1002), an NPC that likes the player. The attitude of an NPC the engine cannot tell (not an NPC, no
-- Disposition) is no ally.
function Friendly.IsAlly(ply, ent)
	if not ply or not IsValid(ply) or not ent or not IsValid(ent) then
		return false
	end

	if ent:IsPlayer() then
		local team = ent:Team()

		return ent ~= ply and team == ply:Team() and team ~= 1001 and team ~= 1002
	end

	if not ent:IsNPC() or not ent.Disposition then
		return false
	end

	return ent:Disposition(ply) == D_LI
end

-- Whether the player may ask now (5 a second).
function Friendly.Allowed(ply, now)
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

function Friendly.Forget(ply)
	windows[ply] = nil
end

-- The answer to one message: `reply(player, index, isAlly)` is called unless the player asked too much.
function Friendly.Handle(ply, index, now, reply)
	if not IsValid(ply) or not Friendly.Allowed(ply, now) then
		return
	end

	reply(ply, index, Friendly.IsAlly(ply, Entity(index)))
end

local function send(ply, index, ally)
	net.Start("gry_friendly")
	net.WriteUInt(index, 13)
	net.WriteBool(ally)
	net.Send(ply)
end

net.Receive("gry_friendly_ask", function(_, ply)
	Friendly.Handle(ply, net.ReadUInt(13), RealTime(), send)
end)

hook.Add("PlayerDisconnected", "GryMod friendly", function(ply)
	windows[ply] = nil
end)
