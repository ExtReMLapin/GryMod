-- Tests of the answer to the client's question about the relation of a few entities (lua/grymod/server/sv_relations.lua, lua/grymod/sh_relations.lua),
-- GLuaTest format, server realm. The binoculars' hologram colours an NPC by what it is to the player, and only the server knows (GryMod.API.Relation).

local realRelation
local spawned = {}

return {
	groupName = "GryMod relations asked in a batch (server)",
	beforeEach = function()
		realRelation = GryMod.Friendly.Relation
	end,
	afterEach = function()
		pcall(function() GryMod.Friendly.Relation = realRelation end)

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			-- fails without sh_relations.lua: no codes
			name = "the codes: neutral 0, ally 1, hostile 2, and a word that is none of them is neutral; the question holds at most 16",
			func = function()
				local R = GryMod.Relations

				expect(R.Code("neutral")).to.equal(0)
				expect(R.Code("ally")).to.equal(1)
				expect(R.Code("hostile")).to.equal(2)
				expect(R.Code("friend")).to.equal(0)
				expect(R.Code(nil)).to.equal(0)
				expect(R.Name(2)).to.equal("hostile")
				expect(R.Name(3)).to.equal("neutral")
				expect(R.MAX).to.equal(16)
			end
		},
		{
			-- fails without Rel.Allowed: a player could make the server walk entities as often as he likes
			name = "a player is answered at most three times a second, and a gap of 0.3 s lets him ask again",
			func = function()
				local Rel = GryMod.RelationsServer
				local p = player.GetAll()[1]

				expect(Rel.Allowed(p, 100)).to.beTrue()
				expect(Rel.Allowed(p, 100.1)).to.beFalse()
				expect(Rel.Allowed(p, 100.29)).to.beFalse()
				expect(Rel.Allowed(p, 100.31)).to.beTrue()
			end
		},
		{
			-- fails without Rel.Answer / Rel.Handle: nothing would be answered, or the relation chain would not be asked
			name = "the answer asks the relation chain for each index that exists, leaves out the ones that do not, and a question too soon is not answered",
			func = function()
				local Rel = GryMod.RelationsServer
				local p = player.GetAll()[1]
				local npc = ents.Create("npc_citizen")
				npc:Spawn()
				spawned[#spawned + 1] = npc

				GryMod.Friendly.Relation = function(ply, ent)
					return ent == npc and "ally" or "hostile"
				end

				local list = Rel.Answer(p, {npc:EntIndex(), 8000})
				expect(#list).to.equal(1)
				expect(list[1].index).to.equal(npc:EntIndex())
				expect(list[1].relation).to.equal("ally")

				local got
				local reply = function(ply, answer) got = answer end

				expect(Rel.Handle(p, {npc:EntIndex()}, 500, reply)).to.beTrue()
				expect(got[1].relation).to.equal("ally")

				got = nil
				expect(Rel.Handle(p, {npc:EntIndex()}, 500.1, reply)).to.beFalse()
				expect(got).to.beNil()
			end
		},
		{
			-- fails without the "before is in the future" rule in Rel.Allowed: a stamp left by a test (or a clock that went back) refused every question until the clock caught up
			name = "a question stamped after now (a clock that went back) does not lock the player out: he is answered",
			func = function()
				local Rel = GryMod.RelationsServer
				local p = player.GetAll()[1]

				expect(Rel.Allowed(p, 900)).to.beTrue()
				expect(Rel.Allowed(p, 10)).to.beTrue()
				expect(Rel.Allowed(p, 10.1)).to.beFalse()
				expect(Rel.Allowed(p, 10.4)).to.beTrue()
			end
		}
	}
}
