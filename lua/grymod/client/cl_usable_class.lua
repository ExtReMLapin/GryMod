-- The class of an entity as the use prompt must see it (sh_api_usable.lua matches the registry on it). On the client ent:GetClass() gives the name of the
-- NETWORK class for the entities the game has no client class of that name for: "class C_BaseToggle" for a func_button, a momentary_rot_button (the wheels)
-- and a func_rot_button (read in game on d1_eli_01), "class C_BaseEntity" for others. The registry could never find a button with that. This file installs
-- the resolver the registry calls for such a name: it asks the server (sv_usable_class.lua) which class the map gave the entity.
--
-- Cost: nothing runs by itself, no timer. The question goes out when the crosshair's scan (ten times a second) aims at such an entity within the reach of
-- the key; the answer is kept for 20 seconds (an entity index can be reused) and the old answer counts while a new one is on its way. While there is no
-- answer yet the class stays generic: no prompt, for the tenth of a second the answer takes.

GryMod = GryMod or {}

local UC = GryMod.UsableClass or {}
GryMod.UsableClass = UC

UC.TRUST_FOR = 20 -- seconds an answer is used before it is asked again
UC.RETRY_AFTER = 1 -- seconds before a question that got no answer is asked again
UC.ASK_GAP = 0.2 -- two questions are at least this far apart (the server answers 10 a second to a player)

local answers = {} -- [entity index] = {class = name or nil, answered = time, asked = time}
local lastAsk = -math.huge

-- Asks the server for the class of the entity of this index (replaceable by the tests).
function UC.Ask(index)
	net.Start("gry_class_ask")
	net.WriteUInt(index, 13)
	net.SendToServer()
end

-- The server's answer.
function UC.OnAnswer(index, class, now)
	local entry = answers[index] or {asked = now}

	entry.class, entry.answered = class, now
	answers[index] = entry
end

function UC.Forget()
	answers = {}
	lastAsk = -math.huge
end

-- The real class of the entity, or nil while it is not known. `class` is what the entity says (the network name).
function UC.Resolve(ent, class, now)
	if not ent or not isfunction(ent.EntIndex) then
		return nil
	end

	now = now or RealTime()

	local index = ent:EntIndex()
	local entry = answers[index]
	local stale

	if not entry then
		stale = true
	elseif entry.answered then
		stale = now - entry.answered >= UC.TRUST_FOR and now - entry.asked >= UC.RETRY_AFTER
	else
		stale = now - entry.asked >= UC.RETRY_AFTER
	end

	if stale and now - lastAsk >= UC.ASK_GAP then
		lastAsk = now
		entry = entry or {}
		entry.asked = now
		answers[index] = entry
		UC.Ask(index)
	end

	return entry and entry.class or nil
end

net.Receive("gry_class", function()
	local index = net.ReadUInt(13)

	UC.OnAnswer(index, net.ReadString(), RealTime())
end)

if GryMod.API then
	GryMod.API.UsableClassResolver = UC.Resolve
end
