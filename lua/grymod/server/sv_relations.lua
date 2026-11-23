-- The answer to the client's question "what are these entities to me?" (see sh_relations.lua): one message with up to 16 indices, one message back with
-- the relation of each, asked of the relation chain of the extension API (GryMod.API.Relation: the providers of the addons, the registry, the
-- built-in rule). The binoculars' hologram asks it about the NPCs in view, a few times a second at most; a player who asks more often is not
-- answered (3 questions a second), so a modified client cannot make the server walk the entities for nothing.

util.AddNetworkString("gry_relations_ask")
util.AddNetworkString("gry_relations")

GryMod = GryMod or {}

local Rel = GryMod.RelationsServer or {}
GryMod.RelationsServer = Rel

local weak = {__mode = "k"}
local last = setmetatable({}, weak) -- [player] = the time of the last question answered

-- Two questions of a player are at least this many seconds apart.
Rel.GAP = 0.3

-- Whether the player may ask now.
function Rel.Allowed(ply, now)
	local before = last[ply]

	-- (a stamp after `now` is from a clock that went back: it must not lock the player out until the clock catches up)
	if before and now >= before and now - before < Rel.GAP then
		return false
	end

	last[ply] = now

	return true
end

-- What the entities of these indices are to the player: a list of {index, relation, level} (level: how alerted it is, 0 to 2), the ones that do not exist left out.
function Rel.Answer(ply, indices)
	local list = {}

	for i = 1, math.min(#indices, GryMod.Relations.MAX) do
		local ent = Entity(indices[i])

		if IsValid(ent) then
			list[#list + 1] = {index = indices[i], relation = GryMod.Friendly.Relation(ply, ent), level = GryMod.Radar.AlertLevelOf(ent, ply)}
		end
	end

	return list
end

-- One question: reply(ply, list) is called with the answer, unless the player asks too often.
function Rel.Handle(ply, indices, now, reply)
	if not IsValid(ply) or not Rel.Allowed(ply, now) then
		return false
	end

	reply(ply, Rel.Answer(ply, indices))

	return true
end

local function send(ply, list)
	net.Start("gry_relations")
	GryMod.Relations.WriteAnswer(list)
	net.Send(ply)
end

net.Receive("gry_relations_ask", function(_, ply)
	Rel.Handle(ply, GryMod.Relations.ReadQuery(), RealTime(), send)
end)

hook.Add("PlayerDisconnected", "GryMod relations", function(ply)
	last[ply] = nil
end)
