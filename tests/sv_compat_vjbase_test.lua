-- Tests of the VJ Base adapter, server side (lua/grymod/compat/npc/sv_vjbase.lua), GLuaTest format, server realm. The pure rules are tried on stand-ins (tables
-- with the fields VJ Base writes on its NPCs); the cases marked `when = VJ ~= nil` use the real VJ Base NPCs and are skipped where VJ Base is not installed.
-- What VJ Base does (read in its code, VJ-Base/lua/vj_base/ai/core.lua): an NPC that dislikes the player but has not seen him has the disposition 100
-- (D_VJ_INTEREST) or none, a camouflaged player (FL_NOTARGET) is D_NU to everybody, friends too, and a follower that is not D_LI any more stops following.

local function ply()
	return player.GetAll()[1]
end

local spawned = {}

local function spawn(class, dx)
	local p = ply()
	local npc = ents.Create(class)
	npc:SetPos(p:GetPos() + p:GetForward() * (dx or 600) + Vector(0, 0, 20))
	npc:Spawn()
	npc:Activate()
	spawned[#spawned + 1] = npc

	return npc
end

-- a stand-in for a VJ Base NPC: the fields the adapter reads, and a Disposition that says `live`
local function fakeNPC(fields)
	local npc = {
		IsVJBaseSNPC = true,
		VJ_NPC_Class = {"CLASS_ZOMBIE"},
		Behavior = 1,
		CanAlly = true,
		RelationshipMemory = {},
		live = D_NU,
		calls = 0
	}

	function npc:Disposition()
		self.calls = self.calls + 1

		return self.live
	end

	for k, v in pairs(fields or {}) do
		npc[k] = v
	end

	return npc
end

local function fakePlayer()
	return {VJ_NPC_Class = {"CLASS_PLAYER_ALLY"}}
end

return {
	groupName = "GryMod VJ Base adapter (server)",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end
	end,
	afterEach = function()
		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:Remove()
			end
		end

		spawned = {}

		local p = ply()
		p.VJ_SpeedModified = nil
		p.VJ_SlowDownPlayerWalkSpeed = nil
		p.VJ_SlowDownPlayerRunSpeed = nil
		p:SetNanosuitMode(GryMod.Modes.ARMOR)
	end,
	cases = {
		{
			name = "the adapter exists, and the relation provider is in the chain",
			func = function()
				expect(GryMod.VJBase ~= nil).to.beTrue()
				expect(isfunction(GryMod.VJBase.Relation)).to.beTrue()
				expect(isfunction(GryMod.VJBase.CachedRelation)).to.beTrue()
			end
		},
		{
			name = "REAL VJ: the provider is in the chain once VJ Base is there (and only then), and it can be taken out and put back",
			when = VJ ~= nil,
			func = function()
				local V = GryMod.VJBase

				expect(V.ProviderAdded).to.beTrue()
				V.TeardownServer()
				expect(V.ProviderAdded).to.beFalse()
				V.SetupServer()
				expect(V.ProviderAdded).to.beTrue()
			end
		},
		{
			name = "an entity that is not a VJ Base NPC has no opinion (nil: the next provider decides)",
			func = function()
				local V = GryMod.VJBase

				expect(V.Relation(fakePlayer(), fakeNPC({IsVJBaseSNPC = false}))).to.beNil()
				expect(V.Relation(fakePlayer(), {})).to.beNil()
			end
		},
		{
			name = "what the engine says now wins when it is clear: D_HT is hostile (VJ saw the player), D_LI is an ally",
			func = function()
				local V = GryMod.VJBase

				expect(V.Relation(fakePlayer(), fakeNPC({live = D_HT}))).to.equal("hostile")
				expect(V.Relation(fakePlayer(), fakeNPC({live = D_LI, VJ_NPC_Class = {"CLASS_ZOMBIE"}}))).to.equal("ally")
			end
		},
		{
			name = "a hostile that has not seen the player yet (D_VJ_INTEREST, or D_NU) is hostile, not neutral",
			func = function()
				local V = GryMod.VJBase

				expect(V.Relation(fakePlayer(), fakeNPC({live = 100}))).to.equal("hostile")
				expect(V.Relation(fakePlayer(), fakeNPC({live = D_NU}))).to.equal("hostile")
			end
		},
		{
			name = "a friend (a class shared with the player) stays an ally while the player is camouflaged and VJ made him D_NU",
			func = function()
				local V = GryMod.VJBase
				local friend = fakeNPC({live = D_NU, VJ_NPC_Class = {"CLASS_UNITED_STATES_FRIENDLY", "CLASS_PLAYER_ALLY"}})

				expect(V.Relation(fakePlayer(), friend)).to.equal("ally")
				friend.CanAlly = false -- vj_npc_allies 0
				expect(V.Relation(fakePlayer(), friend)).to.equal("hostile")
			end
		},
		{
			name = "the memory of VJ (VJ.MEM_OVERRIDE_DISPOSITION: the properties menu, a betrayal) wins over the class",
			func = function()
				local V = GryMod.VJBase
				local p = fakePlayer()
				local zombie = fakeNPC({live = D_NU})
				local key = VJ and VJ.MEM_OVERRIDE_DISPOSITION or "override_disposition"

				zombie.RelationshipMemory[p] = {[key] = D_LI}
				expect(V.Relation(p, zombie)).to.equal("ally")
				zombie.RelationshipMemory[p] = {[key] = D_NU}
				expect(V.Relation(p, zombie)).to.equal("neutral")

				local friend = fakeNPC({live = D_NU, VJ_NPC_Class = {"CLASS_PLAYER_ALLY"}})
				friend.RelationshipMemory[p] = {[key] = D_HT}
				expect(V.Relation(p, friend)).to.equal("hostile")
			end
		},
		{
			name = "a neutral, passive or nature NPC that is not an ally is neutral (it does not attack), an ally of that kind is still an ally",
			func = function()
				local V = GryMod.VJBase

				for _, behavior in ipairs({2, 3, 4}) do
					expect(V.Relation(fakePlayer(), fakeNPC({Behavior = behavior}))).to.equal("neutral")
				end

				expect(V.Relation(fakePlayer(), fakeNPC({Behavior = 3, VJ_NPC_Class = {"CLASS_PLAYER_ALLY"}}))).to.equal("ally")
			end
		},
		{
			name = "while the game ignores players (ai_ignoreplayers: VJ_CVAR_IGNOREPLAYERS) the adapter has no opinion",
			func = function()
				local V = GryMod.VJBase
				local before = VJ_CVAR_IGNOREPLAYERS

				VJ_CVAR_IGNOREPLAYERS = true
				local ok, answer = pcall(V.Relation, fakePlayer(), fakeNPC({live = 100}))
				VJ_CVAR_IGNOREPLAYERS = before

				expect(ok).to.beTrue()
				expect(answer).to.beNil()
			end
		},
		{
			name = "the cached answer is kept for a fifth of a second: the engine is asked once for the same player and NPC",
			func = function()
				local V = GryMod.VJBase
				local p, npc = fakePlayer(), fakeNPC({live = 100})

				V.ForgetRelations()
				expect(V.CachedRelation(p, npc)).to.equal("hostile")
				expect(V.CachedRelation(p, npc)).to.equal("hostile")
				expect(npc.calls).to.equal(1)
				npc.live = D_LI
				V.ForgetRelations()
				expect(V.CachedRelation(p, npc)).to.equal("ally")
				expect(npc.calls).to.equal(2)
			end
		},
		{
			name = "no VJ Base, no error: an adapter that is asked about a plain table answers nothing",
			func = function()
				local ok, answer = pcall(GryMod.VJBase.CachedRelation, fakePlayer(), {})
				expect(ok).to.beTrue()
				expect(answer).to.beNil()
			end
		},
		{
			name = "REAL VJ: a zombie that has not seen the player is hostile in the relation chain of the radar (the engine said neutral)",
			when = VJ ~= nil,
			func = function()
				local p = ply()
				local zombie = spawn("npc_vj_zss_slow", 900)

				zombie:SetMaxLookDistance(100)
				zombie:AddEntityRelationship(p, D_NU, 0)
				GryMod.VJBase.ForgetRelations()

				expect(zombie:Disposition(p)).to.equal(D_NU)
				expect(GryMod.API.Relation(p, zombie)).to.equal("hostile")
			end
		},
		{
			name = "REAL VJ: a friendly soldier is an ally for the radar and the cross while the player is camouflaged (VJ made him D_NU)",
			when = VJ ~= nil,
			func = function()
				local p = ply()
				local ranger = spawn("npc_vj_milifri_ranger", 400)

				ranger:AddEntityRelationship(p, D_NU, 0)
				GryMod.VJBase.ForgetRelations()

				expect(GryMod.API.Relation(p, ranger)).to.equal("ally")
			end
		},
		{
			name = "REAL VJ: the follower keeps following a player who goes camouflaged, and is given back D_LI when the camouflage ends",
			when = VJ ~= nil,
			func = function()
				local p = ply()
				local ranger = spawn("npc_vj_milifri_ranger", 300)

				ranger:AddEntityRelationship(p, D_LI, 0)
				expect(ranger:Follow(p, true)).to.beTrue()

				p:SetNanosuitMode(GryMod.Modes.CLOAK)
				-- what VJ does at its next pass for a player with FL_NOTARGET
				ranger:AddEntityRelationship(p, D_NU, 0)

				expect(ranger:Disposition(p)).to.equal(D_LI) -- the Think of the follower asks this
				expect(GryMod.VJBase.IsHeld(ranger)).to.beTrue()

				p:SetNanosuitMode(GryMod.Modes.ARMOR)
				expect(GryMod.VJBase.IsHeld(ranger)).to.beFalse() -- the shim is gone
				expect(ranger:Disposition(p)).to.equal(D_LI)
			end
		},
		{
			name = "REAL VJ: a hostile soldier is not helped by the adapter: he still sees nothing of a camouflaged player",
			when = VJ ~= nil,
			func = function()
				local p = ply()
				local zombie = spawn("npc_vj_zss_slow", 700)

				p:SetNanosuitMode(GryMod.Modes.CLOAK)
				zombie:AddEntityRelationship(p, D_NU, 0)
				expect(GryMod.VJBase.IsHeld(zombie)).to.beFalse()
				expect(zombie:Disposition(p)).to.equal(D_NU)
			end
		},
		{
			name = "the shim only answers D_LI for the player it was made for, while he is camouflaged, and never for what is already something else than D_NU",
			func = function()
				local V = GryMod.VJBase
				local p = ply()
				local other = fakePlayer()
				local answers = {}

				expect(isfunction(V.CompanionDisposition)).to.beTrue()
				-- (npc real disposition, asked about, is camouflaged) -> answer
				answers[1] = V.CompanionDisposition(D_NU, p, p, true)
				answers[2] = V.CompanionDisposition(D_NU, other, p, true)
				answers[3] = V.CompanionDisposition(D_NU, p, p, false)
				answers[4] = V.CompanionDisposition(D_HT, p, p, true)
				answers[5] = V.CompanionDisposition(D_LI, p, p, true)

				expect(answers[1]).to.equal(D_LI)
				expect(answers[2]).to.equal(D_NU)
				expect(answers[3]).to.equal(D_NU)
				expect(answers[4]).to.equal(D_HT)
				expect(answers[5]).to.equal(D_LI)
			end
		},
		{
			name = "the melee slow of VJ keeps the speeds of the NEW mode to give back (the stored ones were the old mode's)",
			func = function()
				local p = ply()

				p.VJ_SpeedModified = true
				p.VJ_SlowDownPlayerWalkSpeed = 1
				p.VJ_SlowDownPlayerRunSpeed = 2
				p:SetNanosuitMode(GryMod.Modes.SPEED)

				expect(p.VJ_SlowDownPlayerWalkSpeed).to.equal(p:GetWalkSpeed())
				expect(p.VJ_SlowDownPlayerRunSpeed).to.equal(p:GetRunSpeed())
			end
		},
		{
			name = "a player who is not slowed by VJ gets nothing written on him",
			func = function()
				local p = ply()

				p.VJ_SpeedModified = nil
				p.VJ_SlowDownPlayerWalkSpeed = nil
				p:SetNanosuitMode(GryMod.Modes.SPEED)
				expect(p.VJ_SlowDownPlayerWalkSpeed).to.beNil()
			end
		},
		{
			name = "a VJ melee weapon in the hands ends the camouflage with ReportAttack (it fires no bullet), a bullet weapon is left to the bullets",
			func = function()
				local V = GryMod.VJBase
				local p = ply()
				local reported = {}
				local original = GryMod.API.ReportAttack

				GryMod.API.ReportAttack = function(who, alt)
					reported[#reported + 1] = {who = who, alt = alt}

					return true
				end

				local ok, err = pcall(function()
					local nextFire = 0
					local knife = {
						IsVJBaseWeapon = true, IsMeleeWeapon = true, Primary = {},
						GetOwner = function() return p end,
						Clip1 = function() return -1 end,
						GetNextPrimaryFire = function() return nextFire end
					}
					knife.PrimaryAttack = function() nextFire = CurTime() + 0.5 end

					local rifle = {
						IsVJBaseWeapon = true, IsMeleeWeapon = false, Primary = {},
						GetOwner = function() return p end, clip = 30,
						Clip1 = function(self) return self.clip end,
						GetNextPrimaryFire = function() return 0 end
					}
					rifle.PrimaryAttack = function(self) self.clip = self.clip - 1 end

					local launcher = {
						IsVJBaseWeapon = true, IsMeleeWeapon = false, Primary = {DisableBulletCode = true},
						GetOwner = function() return p end, clip = 1,
						Clip1 = function(self) return self.clip end,
						GetNextPrimaryFire = function() return 0 end
					}
					launcher.PrimaryAttack = function(self) if self.clip > 0 then self.clip = self.clip - 1 end end

					V.WrapWeapon(knife)
					V.WrapWeapon(rifle)
					V.WrapWeapon(launcher)
					V.WrapWeapon(launcher) -- twice: still one report per shot

					knife:PrimaryAttack()
					expect(#reported).to.equal(1)
					expect(reported[1].who).to.equal(p)
					expect(reported[1].alt).to.beFalse()
					rifle:PrimaryAttack()
					expect(#reported).to.equal(1)
					launcher:PrimaryAttack()
					expect(#reported).to.equal(2)
					launcher:PrimaryAttack() -- empty: no shot, no report
					expect(#reported).to.equal(2)
				end)

				GryMod.API.ReportAttack = original

				if not ok then error(err, 0) end
			end
		},
		{
			name = "a weapon that raises an error in its own attack code is not hidden by the wrapper, and a failing report never reaches VJ",
			func = function()
				local V = GryMod.VJBase
				local p = ply()
				local original = GryMod.API.ReportAttack
				GryMod.API.ReportAttack = function() error("boom") end

				local ok, err = pcall(function()
					local knife = {
						IsVJBaseWeapon = true, IsMeleeWeapon = true, Primary = {},
						GetOwner = function() return p end, Clip1 = function() return -1 end,
						GetNextPrimaryFire = function() return 0 end
					}
					knife.PrimaryAttack = function() return "fired" end
					V.WrapWeapon(knife)
					expect(knife:PrimaryAttack()).to.equal("fired")
				end)

				GryMod.API.ReportAttack = original
				if not ok then error(err, 0) end
			end
		},
		{
			name = "REAL VJ: a projectile that explodes with a blast and no env_explosion rings the radar (its class gets an entry in Radar.ExplosiveClasses)",
			when = VJ ~= nil,
			func = function()
				GryMod.Radar.ExplosiveClasses.obj_vj_grenade = nil

				local grenade = spawn("obj_vj_grenade", 300)
				local def = GryMod.Radar.ExplosiveClasses.obj_vj_grenade

				expect(def ~= nil).to.beTrue()
				expect(def.radius).to.equal(grenade.RadiusDamageRadius)
				expect(grenade.RadiusDamageRadius > 0).to.beTrue()
			end
		},
		{
			name = "REAL VJ: a follower is marked for the client prompt (GryVJFollow), a tank that does not follow is not",
			when = VJ ~= nil,
			func = function()
				local V = GryMod.VJBase
				local ranger = spawn("npc_vj_milifri_ranger", 300)
				local tank = spawn("npc_vj_milifri_m1a1abrams", 900)

				V.MarkFollower(ranger)
				V.MarkFollower(tank)

				expect(ranger:GetNW2Bool("GryVJFollow", false)).to.beTrue()
				expect(tank:GetNW2Bool("GryVJFollow", true)).to.beFalse()
			end
		},
		{
			name = "no error without VJ Base: Setup does nothing when the VJ table does not exist",
			func = function()
				local saved = VJ
				local ok, err = pcall(function()
					VJ = nil
					GryMod.VJBase.Setup()
				end)
				VJ = saved -- never leave the table of VJ Base removed, red or green

				if not ok then error(err, 0) end
			end
		}
	}
}
