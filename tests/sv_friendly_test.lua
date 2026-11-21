-- Tests of the answer to "is this entity an ally for me?" (GryMod.Friendly, sv_friendly.lua), GLuaTest format, server
-- realm. The friendly cross of the crosshair opens on this answer: an NPC is an ally when its REAL attitude towards
-- the player is like (D_LI), never because of its class (the "Enemy Rebel" of the NPC menu is an npc_citizen that
-- hates the player). Real NPCs are used: the attitude is what the engine says. No net.* function is replaced.

local function ply()
	return player.GetAll()[1]
end

local spawned = {}

local function spawnNPC(class, dx)
	local p = ply()
	local npc = ents.Create(class or "npc_citizen")
	npc:SetPos(p:GetPos() + Vector(dx or 600, 0, 20))
	npc:Spawn()
	npc:Activate()
	spawned[#spawned + 1] = npc

	return npc
end

-- a fake entity for the cases that do not need the engine
local function fake(fields)
	fields.IsValid = fields.IsValid or function() return true end

	return fields
end

return {
	groupName = "GryMod friendly cross (server)",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end
	end,
	afterEach = function()
		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
	end,
	cases = {
		{
			name = "the module and its two net messages exist",
			func = function()
				expect(GryMod.Friendly ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_friendly_ask") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_friendly") ~= 0).to.beTrue()
				expect(net.Receivers["gry_friendly_ask"] ~= nil).to.beTrue()
			end
		},
		{
			name = "an NPC is an ally when its attitude towards the player is like, and only then (like, hate, neutral, fear)",
			func = function()
				local F = GryMod.Friendly
				local npc = spawnNPC("npc_citizen")
				local p = ply()

				npc:AddEntityRelationship(p, D_LI, 99)
				expect(npc:Disposition(p)).to.equal(D_LI)
				expect(F.IsAlly(p, npc)).to.beTrue()

				npc:AddEntityRelationship(p, D_HT, 99)
				expect(F.IsAlly(p, npc)).to.beFalse()

				npc:AddEntityRelationship(p, D_NU, 99)
				expect(F.IsAlly(p, npc)).to.beFalse()

				npc:AddEntityRelationship(p, D_FR, 99)
				expect(F.IsAlly(p, npc)).to.beFalse()
			end
		},
		{
			name = "a rebel that is hostile to the player (the NPC menu's Enemy Rebel) is no ally, whatever its class; a plain rebel is one",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local friend = spawnNPC("npc_citizen", 500)
				local foe = spawnNPC("npc_citizen", 700)
				foe:AddEntityRelationship(p, D_HT, 99)

				expect(friend:GetClass()).to.equal(foe:GetClass())
				expect(F.IsAlly(p, friend)).to.beTrue()
				expect(F.IsAlly(p, foe)).to.beFalse()
			end
		},
		{
			name = "an NPC that turns hostile (or friendly) is answered with its new attitude at once",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local npc = spawnNPC("npc_citizen")
				expect(F.IsAlly(p, npc)).to.beTrue()
				npc:AddEntityRelationship(p, D_HT, 99)
				expect(F.IsAlly(p, npc)).to.beFalse()
				npc:AddEntityRelationship(p, D_LI, 99)
				expect(F.IsAlly(p, npc)).to.beTrue()
			end
		},
		{
			name = "a hostile-class NPC is no ally, and an NPC made friendly to the player is one (the class decides nothing)",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local zombie = spawnNPC("npc_zombie")
				expect(F.IsAlly(p, zombie)).to.beFalse()
				zombie:AddEntityRelationship(p, D_LI, 99)
				expect(F.IsAlly(p, zombie)).to.beTrue()
			end
		},
		{
			name = "Relation tells ally, hostile or neutral from the NPC's real attitude: like, hate, and neutral / fear / anything else",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local npc = spawnNPC("npc_citizen")

				expect(F.Relation).toNot.beNil()
				npc:AddEntityRelationship(p, D_LI, 99)
				expect(F.Relation(p, npc)).to.equal("ally")
				npc:AddEntityRelationship(p, D_HT, 99)
				expect(F.Relation(p, npc)).to.equal("hostile")
				npc:AddEntityRelationship(p, D_NU, 99)
				expect(F.Relation(p, npc)).to.equal("neutral")
				npc:AddEntityRelationship(p, D_FR, 99)
				expect(F.Relation(p, npc)).to.equal("neutral")
			end
		},
		{
			name = "Relation of a real seagull (an animal) and of a Combine soldier are neutral and hostile, a rebel with no order is an ally",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local gull = spawnNPC("npc_seagull")
				local soldier = spawnNPC("npc_combine_s", 800)
				local rebel = spawnNPC("npc_citizen", 400)
				gull:AddEntityRelationship(p, D_NU, 99)

				expect(F.Relation(p, gull)).to.equal("neutral")
				expect(F.Relation(p, soldier)).to.equal(soldier:Disposition(p) == D_HT and "hostile" or "neutral")
				expect(F.Relation(p, rebel)).to.equal("ally")
			end
		},
		{
			name = "Relation: a player of the same team is an ally, another team or no team is neutral, never the asker; invalid and non-NPC things are neutral",
			func = function()
				local F = GryMod.Friendly
				local me = fake({IsPlayer = function() return true end, Team = function() return 1 end})
				local function player_(team)
					return fake({IsPlayer = function() return true end, Team = function() return team end})
				end

				expect(F.Relation(me, player_(1))).to.equal("ally")
				expect(F.Relation(me, player_(2))).to.equal("neutral")
				expect(F.Relation(me, me)).to.equal("neutral")
				expect(F.Relation(player_(1001), player_(1001))).to.equal("neutral")
				expect(F.Relation(ply(), nil)).to.equal("neutral")
				expect(F.Relation(ply(), NULL)).to.equal("neutral")
				expect(F.Relation(nil, spawnNPC("npc_citizen"))).to.equal("neutral")
				expect(F.Relation(me, fake({IsPlayer = function() return false end, IsNPC = function() return false end}))).to.equal("neutral")
			end
		},
		{
			name = "IsAlly is the ally relation and nothing else, for every attitude",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local npc = spawnNPC("npc_citizen")

				for _, d in ipairs({D_LI, D_HT, D_NU, D_FR}) do
					npc:AddEntityRelationship(p, d, 99)
					expect(F.IsAlly(p, npc)).to.equal(F.Relation(p, npc) == "ally")
					expect(F.IsAlly(p, npc)).to.equal(d == D_LI)
				end
			end
		},
		{
			name = "a player is an ally when on the same team (when the game has teams), never the asker itself",
			func = function()
				local F = GryMod.Friendly
				local me = fake({IsPlayer = function() return true end, Team = function() return 1 end})
				local function player_(team)
					return fake({IsPlayer = function() return true end, Team = function() return team end})
				end

				expect(F.IsAlly(me, player_(1))).to.beTrue()
				expect(F.IsAlly(me, player_(2))).to.beFalse()
				expect(F.IsAlly(me, me)).to.beFalse()
				-- no teams (unassigned, spectators): nobody is an ally
				local noTeam = fake({IsPlayer = function() return true end, Team = function() return 1001 end})
				expect(F.IsAlly(noTeam, player_(1001))).to.beFalse()
				expect(F.IsAlly(fake({IsPlayer = function() return true end, Team = function() return 1002 end}), player_(1002))).to.beFalse()
			end
		},
		{
			name = "an invalid entity, nil, a non-NPC entity and an asker that is gone are never allies",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				expect(F.IsAlly(p, nil)).to.beFalse()
				expect(F.IsAlly(p, NULL)).to.beFalse()
				expect(F.IsAlly(p, fake({IsValid = function() return false end}))).to.beFalse()
				expect(F.IsAlly(p, fake({IsPlayer = function() return false end, IsNPC = function() return false end}))).to.beFalse()
				expect(F.IsAlly(nil, spawnNPC("npc_citizen"))).to.beFalse()
				-- a prop is no ally either
				local prop = ents.Create("prop_physics")
				prop:SetModel("models/props_c17/oildrum001.mdl")
				prop:Spawn()
				spawned[#spawned + 1] = prop
				expect(F.IsAlly(p, prop)).to.beFalse()
			end
		},
		{
			name = "the answer goes to the asker only: the entity index asked and whether it is an ally",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local friend = spawnNPC("npc_citizen", 500)
				local foe = spawnNPC("npc_citizen", 700)
				foe:AddEntityRelationship(p, D_HT, 99)
				local answers = {}
				local function reply(to, idx, ally) answers[#answers + 1] = {to = to, idx = idx, ally = ally} end

				F.Handle(p, friend:EntIndex(), 100, reply)
				F.Handle(p, foe:EntIndex(), 100.1, reply)
				F.Handle(p, 0, 100.2, reply) -- the world

				expect(#answers).to.equal(3)
				expect(answers[1].to).to.equal(p)
				expect(answers[1].idx).to.equal(friend:EntIndex())
				expect(answers[1].ally).to.beTrue()
				expect(answers[2].idx).to.equal(foe:EntIndex())
				expect(answers[2].ally).to.beFalse()
				expect(answers[3].ally).to.beFalse()
			end
		},
		{
			name = "the questions of a player are limited to 5 a second, and the limit lets go as the second passes",
			func = function()
				local F = GryMod.Friendly
				local p = ply()
				local npc = spawnNPC("npc_citizen")
				local n = 0
				local function reply() n = n + 1 end
				F.Forget(p)

				for i = 1, 20 do
					F.Handle(p, npc:EntIndex(), 200 + i * 0.01, reply)
				end

				expect(n).to.equal(5)
				-- a second after the window began, the next question is answered again
				F.Handle(p, npc:EntIndex(), 201.05, reply)
				expect(n).to.equal(6)
				F.Forget(p)
			end
		},
		{
			name = "one player's questions do not use another's allowance",
			func = function()
				local F = GryMod.Friendly
				local a = fake({IsPlayer = function() return true end, Team = function() return 1001 end})
				local b = fake({IsPlayer = function() return true end, Team = function() return 1001 end})
				local nA, nB = 0, 0

				for i = 1, 8 do
					if F.Allowed(a, 300) then nA = nA + 1 end
				end

				for i = 1, 3 do
					if F.Allowed(b, 300) then nB = nB + 1 end
				end

				expect(nA).to.equal(5)
				expect(nB).to.equal(3)
			end
		}
	}
}
