-- Tests of the hook GryMod_TargetSpotted(ply, ent, relation) (GryMod.Radar.Scan, lua/grymod/server/sv_radar.lua), GLuaTest format, server realm: it is run once
-- when the binoculars' scan tags an entity for the first time, with what the entity is to the player; a listener that fails does not stop the tag.

local spawned = {}
local realErrorNoHalt

return {
	groupName = "GryMod radar: target spotted hook (server)",
	beforeEach = function()
		realErrorNoHalt = ErrorNoHalt
		GryMod.Radar.Reset(player.GetAll()[1])
	end,
	afterEach = function()
		pcall(function() ErrorNoHalt = realErrorNoHalt end)
		hook.Remove("GryMod_TargetSpotted", "GryTestSpotted")

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
		pcall(function() GryMod.Radar.Reset(player.GetAll()[1]) end)
	end,
	cases = {
		{
			-- fails without Radar.ReportSpotted called from Radar.Scan
			name = "a first scan of an NPC runs GryMod_TargetSpotted once with the player, the NPC and its relation; a second scan of the same NPC runs nothing",
			func = function()
				local p = player.GetAll()[1]
				local npc = ents.Create("npc_citizen")
				npc:SetPos(p:GetPos() + Vector(300, 0, 10))
				npc:Spawn()
				spawned[#spawned + 1] = npc

				local calls = {}
				hook.Add("GryMod_TargetSpotted", "GryTestSpotted", function(ply, ent, relation)
					calls[#calls + 1] = {ply, ent, relation}
				end)

				expect(GryMod.Radar.Scan(p, npc)).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(p)
				expect(calls[1][2]).to.equal(npc)
				expect(calls[1][3]).to.equal(GryMod.Friendly.Relation(p, npc))

				expect(GryMod.Radar.Scan(p, npc)).to.beTrue()
				expect(#calls).to.equal(1)
			end
		},
		{
			-- fails without the pcall in Radar.ReportSpotted: the error of a listener would reach the scan
			name = "a listener that fails is shown in the console and does not stop the tag",
			func = function()
				local p = player.GetAll()[1]
				local npc = ents.Create("npc_citizen")
				npc:SetPos(p:GetPos() + Vector(300, 50, 10))
				npc:Spawn()
				spawned[#spawned + 1] = npc

				local shown
				ErrorNoHalt = function(text) shown = text end
				hook.Add("GryMod_TargetSpotted", "GryTestSpotted", function() error("boom") end)

				expect(GryMod.Radar.Scan(p, npc)).to.beTrue()
				expect(GryMod.Radar.State(p).tagged[npc]).to.beTrue()
				expect(shown).toNot.beNil()
				expect(string.find(shown, "GryMod_TargetSpotted", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			-- fails without the entity out of range being refused before the report
			name = "an entity the scan refuses (too far) is not reported",
			func = function()
				local p = player.GetAll()[1]
				local npc = ents.Create("npc_citizen")
				npc:SetPos(p:GetPos() + Vector(30000, 0, 10))
				npc:Spawn()
				spawned[#spawned + 1] = npc

				local called = false
				hook.Add("GryMod_TargetSpotted", "GryTestSpotted", function() called = true end)

				expect(GryMod.Radar.Scan(p, npc)).to.beFalse()
				expect(called).to.beFalse()
			end
		}
	}
}
