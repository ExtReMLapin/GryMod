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

-- What an entity is to a player, in one place (the friendly cross and the radar both ask): "ally" for a player of the same team
-- (when the game has teams, i.e. not unassigned 1001 nor spectator 1002, and never the player itself) and for an NPC whose
-- attitude towards the player is like (D_LI); "hostile" for an NPC that hates him (D_HT); "neutral" for everything else (an NPC
-- that is neutral or afraid, an animal, a player of another team, a prop, an invalid entity). The attitude of an NPC the engine
-- cannot tell (no Disposition) is neutral.
-- This is the built-in rule, the last step of the relation chain of the extension API (GryMod.API.Relation, sv_api.lua: the
-- providers of other addons come first); Friendly.Relation below is the public name and asks the chain.
function Friendly.BuiltinRelation(ply, ent)
	if not ply or not IsValid(ply) or not ent or not IsValid(ent) then
		return "neutral"
	end

	if ent:IsPlayer() then
		local team = ent:Team()

		if ent ~= ply and team == ply:Team() and team ~= 1001 and team ~= 1002 then
			return "ally"
		end

		return "neutral"
	end

	if not ent:IsNPC() or not ent.Disposition then
		return "neutral"
	end

	local disposition = ent:Disposition(ply)

	if disposition == D_LI then
		return "ally"
	end

	if disposition == D_HT then
		return "hostile"
	end

	return "neutral"
end

-- What an entity is to a player: "ally", "neutral" or "hostile". The one question the crosshair and the radar ask; the answer
-- comes from the relation chain of the extension API when it is loaded, and from the built-in rule alone otherwise.
function Friendly.Relation(ply, ent)
	local API = GryMod.API

	if API and API.Relation then
		return API.Relation(ply, ent)
	end

	return Friendly.BuiltinRelation(ply, ent)
end

-- Whether the entity is an ally for the player (the friendly cross opens on it).
function Friendly.IsAlly(ply, ent)
	return Friendly.Relation(ply, ent) == "ally"
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
