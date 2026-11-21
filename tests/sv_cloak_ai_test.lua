-- Tests of what the NPCs do about a camouflaged player (GryMod.CloakAI), GLuaTest format, server realm.
-- FL_NOTARGET (set by the cloak) keeps most NPCs from picking the player as an enemy, but one that already had him
-- (strider, hunter, manhack: measured in game) keeps him for good and keeps shooting. So while a player is
-- camouflaged those three are made neutral to him and forget him, and they get their old attitude back at the end.

local function ply()
	return player.GetAll()[1]
end

-- RunConsoleCommand only applies on the next frame: the convar is set directly
local function setAI(value)
	local c = GetConVar("gry_cloak_ai")

	if c then
		c:SetString(value)
	end
end

local spawned = {}
local savedAI

local function spawnNPC(class, dx)
	local p = ply()
	local npc = ents.Create(class)
	npc:SetPos(p:GetPos() + Vector(dx or 600, 0, 20))
	npc:Spawn()
	npc:Activate()
	spawned[#spawned + 1] = npc

	return npc
end

-- hostile to the player and engaged with him, like a strider in the middle of a fight
local function engage(npc)
	npc:AddEntityRelationship(ply(), D_HT, 99)
	npc:SetEnemy(ply())
end

return {
	groupName = "GryMod camouflage and the NPCs",
	beforeAll = function(state)
		savedAI = GetConVar("gry_cloak_ai") and GetConVar("gry_cloak_ai"):GetString()
	end,
	beforeEach = function(state)
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p:SetNW2Float("GryEnergy", 100)
		setAI("1")
	end,
	afterEach = function(state)
		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
		local p = ply()

		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end

		setAI(savedAI or "1")
	end,
	cases = {
		{
			name = "the settings exist, replicated, on by default",
			func = function(state)
				local c = GetConVar("gry_cloak_ai")
				expect(c).to.exist()
				expect(c:GetDefault()).to.equal("1")
				expect(bit.band(c:GetFlags(), FCVAR_REPLICATED)).to.equal(FCVAR_REPLICATED)
				expect(GryMod.CloakAI).to.beA("table")
			end
		},
		{
			name = "a strider that fought the player is neutral to him and forgets him when he cloaks",
			func = function(state)
				local npc = spawnNPC("npc_strider")
				engage(npc)
				expect(npc:Disposition(ply())).to.equal(D_HT)
				expect(npc:GetEnemy()).to.equal(ply())

				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)

				expect(npc:Disposition(ply())).to.equal(D_NU)
				expect(npc:GetEnemy()).notTo.equal(ply())
			end
		},
		{
			name = "the strider gets its hostility back when the cloak ends",
			func = function(state)
				local npc = spawnNPC("npc_strider")
				engage(npc)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				ply():SetNanosuitMode(GryMod.Modes.ARMOR, false)

				expect(npc:Disposition(ply())).to.equal(D_HT)
			end
		},
		{
			name = "the other armour modes do not touch the NPCs",
			func = function(state)
				local npc = spawnNPC("npc_manhack")
				engage(npc)
				ply():SetNanosuitMode(GryMod.Modes.SPEED, false)

				expect(npc:Disposition(ply())).to.equal(D_HT)
				expect(npc:GetEnemy()).to.equal(ply())
			end
		},
		{
			name = "an NPC that was not hostile is left alone, and stays as it was (another addon's relation)",
			func = function(state)
				local npc = spawnNPC("npc_manhack")
				npc:AddEntityRelationship(ply(), D_LI, 99)

				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(npc:Disposition(ply())).to.equal(D_LI)

				ply():SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(npc:Disposition(ply())).to.equal(D_LI)
			end
		},
		{
			name = "an NPC that was already neutral stays neutral after the cloak",
			func = function(state)
				local npc = spawnNPC("npc_manhack")
				npc:AddEntityRelationship(ply(), D_NU, 99)

				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				ply():SetNanosuitMode(GryMod.Modes.ARMOR, false)

				expect(npc:Disposition(ply())).to.equal(D_NU)
			end
		},
		{
			name = "classes that already respect the cloak are not touched",
			func = function(state)
				local npc = spawnNPC("npc_zombie")
				npc:AddEntityRelationship(ply(), D_HT, 99)

				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(npc:Disposition(ply())).to.equal(D_HT)
			end
		},
		{
			name = "an NPC that appears while the player is camouflaged is handled by the next tick",
			func = function(state)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				local npc = spawnNPC("npc_manhack")
				engage(npc)

				if GryMod.CloakAI then
					GryMod.CloakAI.Tick()
				end

				expect(npc:Disposition(ply())).to.equal(D_NU)
				expect(npc:GetEnemy()).notTo.equal(ply())
			end
		},
		{
			name = "a dead player is no longer hidden: the NPCs get their attitude back",
			func = function(state)
				local npc = spawnNPC("npc_manhack")
				engage(npc)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(npc:Disposition(ply())).to.equal(D_NU)

				local death = hook.GetTable().PostPlayerDeath and hook.GetTable().PostPlayerDeath["GryCloakAI"]
				expect(death).to.beA("function")
				death(ply())

				expect(npc:Disposition(ply())).to.equal(D_HT)
			end
		},
		{
			name = "a player who leaves is forgotten and the NPCs keep their attitude (no error)",
			func = function(state)
				local npc = spawnNPC("npc_manhack")
				engage(npc)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)

				local leave = hook.GetTable().PlayerDisconnected and hook.GetTable().PlayerDisconnected["GryCloakAI"]
				expect(leave).to.beA("function")
				leave(ply())

				expect(npc:Disposition(ply())).to.equal(D_HT)
			end
		},
		{
			name = "gry_cloak_ai 0 turns it off: the NPCs are not touched",
			func = function(state)
				setAI("0")
				local npc = spawnNPC("npc_manhack")
				engage(npc)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)

				expect(npc:Disposition(ply())).to.equal(D_HT)
				expect(npc:GetEnemy()).to.equal(ply())
			end
		},
		{
			name = "nobody camouflaged: no timer, no search (zero cost); a camouflaged player: the timer runs",
			func = function(state)
				expect(timer.Exists("GryCloakAI")).to.beFalse()

				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)
				expect(timer.Exists("GryCloakAI")).to.beTrue()

				ply():SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(timer.Exists("GryCloakAI")).to.beFalse()
			end
		},
		{
			name = "the tick searches the listed classes only, never every entity",
			func = function(state)
				ply():SetNanosuitMode(GryMod.Modes.CLOAK, false)

				local realFind, realAll = ents.FindByClass, ents.GetAll
				local classes, all = {}, 0
				ents.FindByClass = function(c)
					classes[#classes + 1] = c

					return realFind(c)
				end
				ents.GetAll = function()
					all = all + 1

					return realAll()
				end

				local ok, err = pcall(GryMod.CloakAI.Tick)
				ents.FindByClass, ents.GetAll = realFind, realAll
				assert(ok, err)

				expect(all).to.equal(0)
				expect(#classes).to.equal(#GryMod.CloakAI.Classes)
				expect(table.HasValue(classes, "npc_strider")).to.beTrue()
				expect(table.HasValue(classes, "npc_zombie")).to.beFalse()
			end
		},
	}
}
