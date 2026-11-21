-- Tests of the relation chain of the extension API (GryMod.API.Relation, lua/grymod/server/sv_api.lua), GLuaTest format,
-- server realm: THE decision point of ally / neutral / hostile (crosshair, radar, binoculars...). Order: the providers of
-- other addons (higher priority first), then the registry entry of the entity (wave B: an empty hook point today), then the
-- built-in rule (the NPC's real attitude, which GryMod.Friendly.Relation used to be). GryMod.Friendly.Relation stays the
-- public name and calls the chain. Third-party providers are called through SafeCall.
-- Fake entities (a table with IsValid) are enough for the rules; two cases use a real NPC.

local function ply()
	return player.GetAll()[1]
end

local function fakeNPC(disposition)
	return {
		IsValid = function() return true end,
		IsPlayer = function() return false end,
		IsNPC = function() return true end,
		Disposition = function() return disposition end
	}
end

local ids = {}
local spawned = {}
local realMsgN, lines
local realTracked

local function provide(id, fn, priority)
	ids[#ids + 1] = id

	return GryMod.API.AddRelationProvider(id, fn, priority)
end

return {
	groupName = "GryMod extension API: relation chain (server)",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		lines = {}
		realMsgN = MsgN
		MsgN = function(...) lines[#lines + 1] = table.concat({...}, "") end
		realTracked = GryMod.API._TrackedRelation
	end,
	afterEach = function()
		MsgN = realMsgN
		GryMod.API._TrackedRelation = realTracked

		for _, id in ipairs(ids) do
			GryMod.API.RemoveRelationProvider(id)
			GryMod.API.SafeCallReset("provider:" .. id)
		end

		ids = {}

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			name = "the functions exist, and the registry hook point (_TrackedRelation) answers nil while there is no registry",
			func = function()
				local API = GryMod.API

				expect(isfunction(API.Relation)).to.beTrue()
				expect(isfunction(API.AddRelationProvider)).to.beTrue()
				expect(isfunction(API.RemoveRelationProvider)).to.beTrue()
				expect(API._TrackedRelation(ply(), fakeNPC(D_LI))).to.beNil()
			end
		},
		{
			name = "with no provider the built-in rule decides: like is ally, hate is hostile, everything else (neutral, fear, VJ's 100) is neutral",
			func = function()
				local API, p = GryMod.API, ply()

				expect(API.Relation(p, fakeNPC(D_LI))).to.equal("ally")
				expect(API.Relation(p, fakeNPC(D_HT))).to.equal("hostile")
				expect(API.Relation(p, fakeNPC(D_NU))).to.equal("neutral")
				expect(API.Relation(p, fakeNPC(D_FR))).to.equal("neutral")
				expect(API.Relation(p, fakeNPC(100))).to.equal("neutral")
				expect(API.Relation(p, NULL)).to.equal("neutral")
				expect(API.Relation(p, nil)).to.equal("neutral")
				expect(API.Relation(NULL, fakeNPC(D_LI))).to.equal("neutral")
				expect(API.Relation(p, p)).to.equal("neutral") -- never the asker itself
			end
		},
		{
			name = "no provider: the chain does not even call SafeCall (the relation is asked often: radar and crosshair)",
			func = function()
				local API = GryMod.API
				local realSafeCall = API.SafeCall
				local calls = 0

				API.SafeCall = function(...)
					calls = calls + 1

					return realSafeCall(...)
				end

				local ok, err = pcall(function()
					for _ = 1, 20 do API.Relation(ply(), fakeNPC(D_LI)) end
				end)

				API.SafeCall = realSafeCall
				expect(ok).to.beTrue()
				expect(calls).to.equal(0)
			end
		},
		{
			name = "GryMod.Friendly.Relation is the chain (a provider changes what it says, IsAlly follows); the built-in rule keeps a name of its own",
			func = function()
				local F, p = GryMod.Friendly, ply()
				local npc = fakeNPC(D_LI)

				expect(F.Relation(p, npc)).to.equal("ally")
				expect(F.IsAlly(p, npc)).to.beTrue()

				expect(provide("t_hostile", function() return "hostile" end)).to.beTrue()

				expect(F.Relation(p, npc)).to.equal("hostile")
				expect(F.IsAlly(p, npc)).to.beFalse()
				expect(F.BuiltinRelation(p, npc)).to.equal("ally")
			end
		},
		{
			name = "a provider decides before the built-in rule; nil is no opinion (the rule answers); anything that is not one of the three words is ignored",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_HT)
				local answer

				provide("t_answer", function() return answer end)

				answer = "ally"
				expect(API.Relation(p, npc)).to.equal("ally")
				answer = "neutral"
				expect(API.Relation(p, npc)).to.equal("neutral")
				answer = "hostile"
				expect(API.Relation(p, fakeNPC(D_LI))).to.equal("hostile")

				for _, junk in ipairs({"enemy", "ALLY", 5, true, {}}) do
					answer = junk
					expect(API.Relation(p, npc)).to.equal("hostile") -- the rule: D_HT
				end

				answer = nil
				expect(API.Relation(p, npc)).to.equal("hostile")
				expect(API.Relation(p, fakeNPC(D_LI))).to.equal("ally")
			end
		},
		{
			name = "a provider gets (player, entity) and is never asked about an invalid entity or player",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_LI)
				local got = {}

				provide("t_args", function(a, b) got[#got + 1] = {a, b} end)

				API.Relation(p, npc)
				API.Relation(p, NULL)
				API.Relation(NULL, npc)
				API.Relation(p, nil)

				expect(#got).to.equal(1)
				expect(got[1][1]).to.equal(p)
				expect(got[1][2]).to.equal(npc)
			end
		},
		{
			name = "the higher priority is asked first; the same priority goes in the order of registration; a provider with no opinion lets the next one decide",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_NU)
				local order = {}

				provide("t_low", function() order[#order + 1] = "low"; return "hostile" end, -5)
				provide("t_mid_a", function() order[#order + 1] = "mid_a" end, 0)
				provide("t_mid_b", function() order[#order + 1] = "mid_b"; return "ally" end, 0)
				provide("t_high", function() order[#order + 1] = "high" end, 10)
				provide("t_default", function() order[#order + 1] = "default" end) -- priority 0

				expect(API.Relation(p, npc)).to.equal("ally")
				expect(table.concat(order, ",")).to.equal("high,mid_a,mid_b")

				API.RemoveRelationProvider("t_mid_b")
				order = {}
				expect(API.Relation(p, npc)).to.equal("hostile")
				expect(table.concat(order, ",")).to.equal("high,mid_a,default,low")
			end
		},
		{
			name = "registering an id again replaces its provider (no duplicate); RemoveRelationProvider removes it and says whether there was one",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_NU)
				local first, second = 0, 0

				provide("t_same", function() first = first + 1; return "ally" end)
				provide("t_same", function() second = second + 1; return "hostile" end)

				expect(API.Relation(p, npc)).to.equal("hostile")
				expect(first).to.equal(0)
				expect(second).to.equal(1)

				expect(API.RemoveRelationProvider("t_same")).to.beTrue()
				expect(API.RemoveRelationProvider("t_same")).to.beFalse()
				expect(API.RemoveRelationProvider("never_there")).to.beFalse()
				expect(API.Relation(p, npc)).to.equal("neutral")
			end
		},
		{
			name = "a bad registration (no id, no function, a priority that is not a number) is refused with a reason and registers nothing",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_NU)

				for _, args in ipairs({{nil, function() return "ally" end}, {"", function() return "ally" end}, {42, function() return "ally" end}, {"t_nofn", nil}, {"t_nofn", "ally"}, {"t_prio", function() return "ally" end, "high"}}) do
					local ok, reason = API.AddRelationProvider(args[1], args[2], args[3])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(API.Relation(p, npc)).to.equal("neutral")
			end
		},
		{
			name = "a provider that raises an error is skipped (the next one, then the rule, answer) and never reaches the caller; 5 errors in a row disable it with one console line",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_LI)
				local runs = 0

				provide("t_broken", function() runs = runs + 1; error("broken provider") end, 5)

				for _ = 1, 8 do
					expect(API.Relation(p, npc)).to.equal("ally")
				end

				expect(runs).to.equal(5)
				expect(API.SafeCallDisabled("provider:t_broken")).to.beTrue()
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "provider 't_broken' disabled after 5 errors", 1, true) ~= nil).to.beTrue()

				-- registered again (fixed): it works
				provide("t_broken", function() return "hostile" end, 5)
				expect(API.Relation(p, npc)).to.equal("hostile")
			end
		},
		{
			name = "the registry's place in the chain: after the providers, before the built-in rule",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC(D_LI)
				local tracked

				API._TrackedRelation = function() return tracked end

				tracked = "hostile"
				expect(API.Relation(p, npc)).to.equal("hostile") -- before the rule (ally)

				provide("t_wins", function() return "neutral" end)
				expect(API.Relation(p, npc)).to.equal("neutral") -- a provider wins over the registry

				API.RemoveRelationProvider("t_wins")
				tracked = nil
				expect(API.Relation(p, npc)).to.equal("ally") -- no opinion: the rule
			end
		},
		{
			name = "real NPC: a rebel is an ally by its attitude, a provider makes it hostile for the radar's and the crosshair's question (GryMod.Friendly.Relation), removing it gives the rule back",
			func = function()
				local p = ply()
				local npc = ents.Create("npc_citizen")
				npc:SetPos(p:GetPos() + Vector(600, 0, 20))
				npc:Spawn()
				npc:Activate()
				spawned[#spawned + 1] = npc

				npc:AddEntityRelationship(p, D_LI, 99)
				expect(GryMod.Friendly.Relation(p, npc)).to.equal("ally")

				provide("t_real", function(_, ent) if ent:GetClass() == "npc_citizen" then return "hostile" end end)
				expect(GryMod.Friendly.Relation(p, npc)).to.equal("hostile")
				expect(GryMod.API.Relation(p, npc)).to.equal("hostile")

				GryMod.API.RemoveRelationProvider("t_real")
				expect(GryMod.Friendly.Relation(p, npc)).to.equal("ally")
			end
		}
	}
}
