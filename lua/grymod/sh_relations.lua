-- What the client may ask the server about a few entities at once: "what are these to me, ally, neutral or hostile?" (the answer of GryMod.API.Relation,
-- which only exists on the server). The binoculars' hologram (cl_hud_binoculars_holo.lua) needs it for up to 16 NPCs; the crosshair's own question
-- (gry_friendly_ask, one NPC, a yes or no) is left as it is. Shared: the client writes the question and reads the answer, the server the other way.

GryMod = GryMod or {}

local R = GryMod.Relations or {}
GryMod.Relations = R

-- at most this many entities in one question (the server cuts the rest)
R.MAX = 16

R.CODES = {neutral = 0, ally = 1, hostile = 2}
R.NAMES = {[0] = "neutral", [1] = "ally", [2] = "hostile"}

-- The code (0 to 2) of a relation word: anything that is not one of the three is neutral.
function R.Code(relation)
	return R.CODES[relation] or 0
end

-- The word of a code: anything that is not a code is neutral.
function R.Name(code)
	return R.NAMES[code] or "neutral"
end

-- The question: the count (5 bits) and the entity indices (13 bits each), at most R.MAX of them.
function R.WriteQuery(indices)
	local count = math.min(#indices, R.MAX)

	net.WriteUInt(count, 5)

	for i = 1, count do
		net.WriteUInt(indices[i], 13)
	end
end

function R.ReadQuery()
	local count = math.min(net.ReadUInt(5), R.MAX)
	local indices = {}

	for i = 1, count do
		indices[i] = net.ReadUInt(13)
	end

	return indices
end

-- The answer: a list of {index, relation, level}, the count (5 bits), then each index (13 bits), its code (2 bits) and its alert level (2 bits: 0 idle, 1 alerted,
-- 2 in combat, the radar's own levels).
function R.WriteAnswer(list)
	local count = math.min(#list, R.MAX)

	net.WriteUInt(count, 5)

	for i = 1, count do
		net.WriteUInt(list[i].index, 13)
		net.WriteUInt(R.Code(list[i].relation), 2)
		net.WriteUInt(math.Clamp(list[i].level or 0, 0, 3), 2)
	end
end

function R.ReadAnswer()
	local count = math.min(net.ReadUInt(5), R.MAX)
	local list = {}

	for i = 1, count do
		local index = net.ReadUInt(13)

		local relation = R.Name(net.ReadUInt(2))

		list[i] = {index = index, relation = relation, level = net.ReadUInt(2)}
	end

	return list
end
