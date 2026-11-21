-- Tests of the registry's place in the relation chain (GryMod.API._TrackedRelation and GryMod.API.Relation, lua/grymod/sh_api_tracked.lua
-- and server/sv_api.lua), GLuaTest format, server realm: the `relation` field of a matching entry is step 2 of the chain, after the
-- providers and before the built-in rule (the NPC's real attitude). "auto" is no opinion; a function runs under SafeCall.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, parts 3 and 5.

local function ply()
	return player.GetAll()[1]
end

local function fakeNPC(class, disposition)
	return {
		IsValid = function() return true end,
		IsPlayer = function() return false end,
		IsNPC = function() return true end,
		GetClass = function() return class end,
		Disposition = function() return disposition end
	}
end

local KEYS = {"t_rel_a", "t_rel_b"}
local ids = {}
local spawned = {}
local realMsgN, lines

return {
	groupName = "GryMod extension API: tracked entities in the relation chain (server)",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		lines = {}
		realMsgN = MsgN
		MsgN = function(...) lines[#lines + 1] = table.concat({...}, "") end
	end,
	afterEach = function()
		MsgN = realMsgN

		for _, key in ipairs(KEYS) do
			GryMod.API.UnregisterTracked(key)
			GryMod.API.SafeCallReset("tracked:" .. key .. "/relation")
		end

		for _, id in ipairs(ids) do
			GryMod.API.RemoveRelationProvider(id)
		end

		ids = {}

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			name = "_TrackedRelation says nothing for an entity that is not registered, for an invalid one, and for an entry whose relation is auto",
			func = function()
				local API, p = GryMod.API, ply()

				expect(API._TrackedRelation(p, fakeNPC("t_rel_class", D_LI))).to.beNil()

				API.RegisterTracked("t_rel_a", {class = "t_rel_class"})
				expect(API._TrackedRelation(p, fakeNPC("t_rel_class", D_LI))).to.beNil() -- relation "auto" (the default)

				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = "auto"})
				expect(API._TrackedRelation(p, fakeNPC("t_rel_class", D_LI))).to.beNil()

				expect(API._TrackedRelation(p, NULL)).to.beNil()
				expect(API._TrackedRelation(p, nil)).to.beNil()
				expect(API._TrackedRelation(p, 5)).to.beNil()
			end
		},
		{
			name = "a fixed relation of the entry decides: ally, neutral, hostile, whatever the NPC's attitude is",
			func = function()
				local API, p = GryMod.API, ply()

				for _, relation in ipairs({"ally", "neutral", "hostile"}) do
					API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = relation})

					for _, disposition in ipairs({D_LI, D_HT, D_NU}) do
						expect(API._TrackedRelation(p, fakeNPC("t_rel_class", disposition))).to.equal(relation)
						expect(API.Relation(p, fakeNPC("t_rel_class", disposition))).to.equal(relation)
					end
				end
			end
		},
		{
			name = "the chain: a provider wins over the entry, the entry wins over the built-in rule, an entry that is auto lets the rule decide",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC("t_rel_class", D_LI)

				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = "hostile"})
				expect(API.Relation(p, npc)).to.equal("hostile") -- before the rule (ally)

				ids[#ids + 1] = "t_rel_provider"
				API.AddRelationProvider("t_rel_provider", function() return "neutral" end)
				expect(API.Relation(p, npc)).to.equal("neutral") -- a provider wins

				API.RemoveRelationProvider("t_rel_provider")
				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = "auto"})
				expect(API.Relation(p, npc)).to.equal("ally") -- the rule
			end
		},
		{
			name = "an entity that is not registered gets the built-in rule exactly as before",
			func = function()
				local API, p = GryMod.API, ply()

				API.RegisterTracked("t_rel_a", {class = "t_rel_other", relation = "hostile"})

				expect(API.Relation(p, fakeNPC("t_rel_class", D_LI))).to.equal("ally")
				expect(API.Relation(p, fakeNPC("t_rel_class", D_HT))).to.equal("hostile")
				expect(API.Relation(p, fakeNPC("t_rel_class", D_NU))).to.equal("neutral")
				expect(API.Relation(p, {IsValid = function() return true end, IsPlayer = function() return false end, IsNPC = function() return true end, Disposition = function() return D_LI end})).to.equal("ally") -- no GetClass at all
			end
		},
		{
			name = "a function relation is asked with (player, entity) and its answer decides; nil and anything that is not one of the three words is no opinion (the rule answers)",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC("t_rel_class", D_HT)
				local answer, got

				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = function(a, b)
					got = {a, b}

					return answer
				end})

				answer = "ally"
				expect(API.Relation(p, npc)).to.equal("ally")
				expect(got[1]).to.equal(p)
				expect(got[2]).to.equal(npc)

				for _, junk in ipairs({"enemy", "ALLY", 5, true, {}}) do
					answer = junk
					expect(API.Relation(p, npc)).to.equal("hostile") -- the rule: D_HT
				end

				answer = nil
				expect(API.Relation(p, npc)).to.equal("hostile")
			end
		},
		{
			name = "a function relation that raises an error is skipped (the rule answers) and never reaches the caller; 5 errors in a row disable it with one console line",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = fakeNPC("t_rel_class", D_LI)
				local runs = 0

				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = function() runs = runs + 1 error("broken relation") end})

				for _ = 1, 8 do
					expect(API.Relation(p, npc)).to.equal("ally")
				end

				expect(runs).to.equal(5)
				expect(API.SafeCallDisabled("tracked:t_rel_a/relation")).to.beTrue()
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "tracked 't_rel_a/relation' disabled after 5 errors", 1, true) ~= nil).to.beTrue()

				-- registered again (fixed): it works
				API.RegisterTracked("t_rel_a", {class = "t_rel_class", relation = function() return "hostile" end})
				expect(API.Relation(p, npc)).to.equal("hostile")
			end
		},
		{
			name = "real NPC: a zombie registered as an ally is an ally for the crosshair's and the radar's question, and is its own self again once the entry goes",
			func = function()
				local API, p = GryMod.API, ply()
				local npc = ents.Create("npc_zombie")

				npc:SetPos(p:GetPos() + Vector(600, 0, 20))
				npc:Spawn()
				spawned[#spawned + 1] = npc
				npc:AddEntityRelationship(p, D_HT, 99)

				expect(GryMod.Friendly.Relation(p, npc)).to.equal("hostile")

				API.RegisterTracked("t_rel_a", {class = "npc_zombie", relation = "ally"})
				expect(GryMod.Friendly.Relation(p, npc)).to.equal("ally")
				expect(GryMod.Friendly.IsAlly(p, npc)).to.beTrue()
				expect(GryMod.Friendly.BuiltinRelation(p, npc)).to.equal("hostile") -- the rule keeps its name and its answer

				API.UnregisterTracked("t_rel_a")
				expect(GryMod.Friendly.Relation(p, npc)).to.equal("hostile")
			end
		}
	}
}
