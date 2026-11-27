-- Tests of the dangerous projectiles the server marks for the grenade warning (GryMod.Grenade, sv_grenade.lua), GLuaTest
-- format, server realm. The warning is only for a projectile that is ACTIVE (an armed grenade, a launched mine, a bomb that
-- fell...) and not held in the player's hands: the server tells it with the networked bool GryArmed. The values the rules
-- read (m_flDetonateTime, m_iMineState...) were measured on live entities, see docs/superpowers/plans/2026-11-21-grenade-entities.md.

local function ply()
	return player.GetAll()[1]
end

local G -- GryMod.Grenade, set in beforeAll

local spawned = {}

local function spawn(class, pos)
	local e = ents.Create(class)
	e:SetPos(pos)
	e:Spawn()
	spawned[#spawned + 1] = e

	return e
end

-- An entity stand-in for the rules (the `armed` readers of the registry's entries ask the entity itself): its class, its speed, the
-- internal variables they read and whether a player holds it.
local function stand(class, fields)
	fields = fields or {}

	return {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetVelocity = function() return Vector(fields.speed or 0, 0, 0) end,
		GetInternalVariable = function(_, name) return (fields.vars or {})[name] end,
		IsPlayerHolding = function() return fields.held == true end
	}
end

local function active(class, fields)
	return GryMod.Grenade.IsActive(stand(class, fields))
end

return {
	groupName = "GryMod grenade marks (server)",
	beforeAll = function(state)
		G = GryMod.Grenade
	end,
	afterEach = function(state)
		local p = ply()

		if IsValid(p) then
			p:DropObject()
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then
				e:SetPos(Vector(0, 0, -30000))
				e:Remove()
			end
		end

		spawned = {}

		if GryMod.API.UnregisterTracked then
			GryMod.API.UnregisterTracked("t_third_mine")
			GryMod.API.SafeCallReset("tracked:t_third_mine/armed")
			GryMod.API.SafeCallReset("tracked:t_third_mine/owner")
		end
	end,
	cases = {
		{
			name = "the module, the switch and the classes exist",
			func = function(state)
				expect(G).toNot.beNil()
				expect(GetConVar("gry_grenade_armed_only")).toNot.beNil()
				expect(GetConVar("gry_grenade_armed_only"):GetInt()).to.equal(1)
				expect(GetConVar("gry_grenade_armed_only"):IsFlagSet(FCVAR_REPLICATED)).to.beTrue()

				-- the classes are the registry's: stock entries with danger (compat/hl2/sh_tracked.lua), no table of the grenade module
				for _, class in ipairs({"npc_grenade_frag", "grenade_ar2", "rpg_missile", "grenade_helicopter", "combine_mine", "prop_combine_ball"}) do
					expect(GryMod.API.GetDanger(class)).toNot.beNil()
				end

				expect(GryMod.API.GetDanger("prop_physics")).to.beNil()
				expect(G.Classes).to.beNil()
			end
		},
		{
			name = "a frag grenade is active from the moment its fuse runs (the time of the explosion is in the future), not before",
			func = function(state)
				expect(active("npc_grenade_frag", {vars = {m_flDetonateTime = -47.2}})).to.beFalse() -- never armed: minus the game time
				expect(active("npc_grenade_frag", {vars = {m_flDetonateTime = 0}})).to.beFalse()
				expect(active("npc_grenade_frag", {vars = {m_flDetonateTime = 2.49}})).to.beTrue()
				expect(active("npc_grenade_frag", {})).to.beFalse()
			end
		},
		{
			name = "a rifle grenade and a missile are active while they fly (they have no state: they are fired already live)",
			func = function(state)
				expect(active("grenade_ar2", {speed = 0})).to.beFalse() -- one made at rest (the spawn menu) stays harmless
				expect(active("grenade_ar2", {speed = 900})).to.beTrue()
				expect(active("rpg_missile", {speed = 0})).to.beFalse()
				expect(active("rpg_missile", {speed = 1100})).to.beTrue()
			end
		},
		{
			name = "a helicopter bomb is active once it has fallen and ticks (activated), or while it falls fast",
			func = function(state)
				expect(active("grenade_helicopter", {speed = 0, vars = {m_bActivated = false}})).to.beFalse()
				expect(active("grenade_helicopter", {speed = 450, vars = {m_bActivated = false}})).to.beTrue() -- falling at you
				expect(active("grenade_helicopter", {speed = 0, vars = {m_bActivated = true}})).to.beTrue() -- the countdown runs
			end
		},
		{
			name = "a hopping mine is active in the air only: not asleep, not armed on the ground, not clicking before the jump",
			func = function(state)
				expect(active("combine_mine", {vars = {m_iMineState = 1}, speed = 0})).to.beFalse() -- on the ground
				expect(active("combine_mine", {vars = {m_iMineState = 3}, speed = 0})).to.beFalse() -- armed, waits for a foe
				expect(active("combine_mine", {vars = {m_iMineState = 4}, speed = 0})).to.beFalse() -- triggered, clicking
				expect(active("combine_mine", {vars = {m_iMineState = 4}, speed = 20})).to.beFalse() -- the little shuffle
				expect(active("combine_mine", {vars = {m_iMineState = 4}, speed = 376})).to.beTrue() -- jumping
				expect(active("combine_mine", {vars = {m_iMineState = 1}, speed = 376})).to.beFalse() -- a mine thrown by physics, not hopping
			end
		},
		{
			name = "an energy ball is active once launched and not held by the gravity gun",
			func = function(state)
				expect(active("prop_combine_ball", {vars = {m_bLaunched = false}})).to.beFalse()
				expect(active("prop_combine_ball", {vars = {m_bLaunched = true, m_bHeld = false}})).to.beTrue()
				expect(active("prop_combine_ball", {vars = {m_bLaunched = true, m_bHeld = true}})).to.beFalse()
			end
		},
		{
			name = "the thrower of a projectile is the first player among its owner, its thrower and its owner entity (a missile, a rifle grenade and a thrown frag all have the player as owner: measured)",
			func = function(state)
				local p = ply()
				local npc = {IsValid = function() return true end, IsPlayer = function() return false end}
				expect(G.PlayerOf(p)).to.equal(p)
				expect(G.PlayerOf(NULL, nil, p)).to.equal(p)
				expect(G.PlayerOf(npc, p)).to.equal(p) -- an owner that is not a player is skipped
				expect(G.PlayerOf(NULL, npc)).to.equal(nil)
				expect(G.PlayerOf()).to.equal(nil)
				expect(G.PlayerOf(nil, nil)).to.equal(nil)
			end
		},
		{
			name = "a projectile is marked with its thrower (GryThrower) when a player owns it, and with nobody when none does",
			func = function(state)
				local p = ply()
				local mine = spawn("rpg_missile", p:EyePos() + p:GetForward() * 200)
				mine:SetOwner(p)
				G.Update(mine)
				expect(mine:GetNW2Entity("GryThrower")).to.equal(p)
				local foe = spawn("rpg_missile", p:EyePos() + p:GetForward() * 200 + Vector(0, 100, 0))
				G.Update(foe)
				expect(IsValid(foe:GetNW2Entity("GryThrower"))).to.beFalse()
				-- the owner is lost later (the engine clears it): the mark follows
				mine:SetOwner(NULL)
				G.Update(mine)
				expect(IsValid(mine:GetNW2Entity("GryThrower"))).to.beFalse()
			end
		},
		{
			name = "a grenade the player picked up and let go is the player's (GryThrower), held or free: the client never warns about it (measured live)",
			func = function(state)
				local p = ply()
				-- made by nobody, like a Combine soldier's: no thrower before the player touches it
				local g = spawn("npc_grenade_frag", p:EyePos() + p:GetForward() * 60)
				G.Update(g)
				expect(IsValid(g:GetNW2Entity("GryThrower"))).to.beFalse()

				p:PickupObject(g)
				G.Update(g)
				expect(g:GetNW2Entity("GryThrower")).to.equal(p)
				expect(g:GetNW2Bool("GryArmed")).to.beFalse()

				p:DropObject()
				G.Update(g)
				expect(g:GetNW2Entity("GryThrower")).to.equal(p)
				expect(g:GetNW2Bool("GryArmed")).to.beTrue()
			end
		},
		{
			name = "an unknown class is never active",
			func = function(state)
				expect(active("prop_physics", {speed = 999, vars = {m_flDetonateTime = 5, m_bLaunched = true}})).to.beFalse()
				expect(G.IsActive(nil)).to.beFalse()
				expect(G.IsActive(NULL)).to.beFalse()
			end
		},
		{
			name = "a frag grenade made at rest is not armed (GryArmed false), a running one is (GryArmed true)",
			func = function(state)
				local p = ply()
				local g = spawn("npc_grenade_frag", p:EyePos() + p:GetForward() * 120)
				G.Update(g)
				expect(g:GetNW2Bool("GryArmed")).to.beFalse()
				-- the fuse: picking the grenade up arms it (1.5 s) in the engine, then it is let go
				p:PickupObject(g)
				p:DropObject()
				expect(g:GetInternalVariable("m_flDetonateTime") > 0).to.beTrue()
				G.Update(g)
				expect(g:GetNW2Bool("GryArmed")).to.beTrue()
			end
		},
		{
			name = "a grenade held in the player's hands is not armed, and is again once it is let go",
			func = function(state)
				local p = ply()
				local g = spawn("npc_grenade_frag", p:EyePos() + p:GetForward() * 60)
				p:PickupObject(g) -- the engine arms it (1.5 s) and the player holds it
				expect(g:IsPlayerHolding()).to.beTrue()
				expect(g:GetInternalVariable("m_flDetonateTime") > 0).to.beTrue()
				expect(G.IsActive(g)).to.beFalse() -- the fuse runs, but the player has it
				G.Update(g)
				expect(g:GetNW2Bool("GryArmed")).to.beFalse()
				p:DropObject()
				expect(g:IsPlayerHolding()).to.beFalse()
				G.Update(g)
				expect(g:GetNW2Bool("GryArmed")).to.beTrue()
			end
		},
		{
			name = "a held projectile is never active, whatever its class",
			func = function(state)
				expect(active("npc_grenade_frag", {vars = {m_flDetonateTime = 1.5}, held = true})).to.beFalse()
				expect(active("npc_grenade_frag", {vars = {m_flDetonateTime = 1.5}, held = false})).to.beTrue()
				expect(active("grenade_helicopter", {vars = {m_bActivated = true}, held = true})).to.beFalse()
				expect(active("rpg_missile", {speed = 900, held = true})).to.beFalse()
			end
		},
		{
			name = "the pick-up and the throw (the engine's hooks) mark the grenade at once, without waiting for the tick",
			func = function(state)
				local hooks = hook.GetTable()
				expect(hooks.OnPlayerPhysicsPickup and hooks.OnPlayerPhysicsPickup.GRYGRENADEHELD ~= nil).to.beTrue()
				expect(hooks.OnPlayerPhysicsDrop and hooks.OnPlayerPhysicsDrop.GRYGRENADEHELD ~= nil).to.beTrue()
			end
		},
		{
			name = "a mine on the ground and a bomb at rest are not armed",
			func = function(state)
				local p = ply()
				local mine = spawn("combine_mine", p:EyePos() + p:GetForward() * 150)
				local bomb = spawn("grenade_helicopter", p:EyePos() + p:GetForward() * 150 + Vector(0, 100, 0))
				G.Update(mine)
				G.Update(bomb)
				expect(mine:GetNW2Bool("GryArmed")).to.beFalse()
				expect(bomb:GetNW2Bool("GryArmed")).to.beFalse()
			end
		},
		{
			name = "the state is read from the real entity by the registry's readers: a mine, a bomb and a ball made at rest are not active",
			func = function(state)
				local p = ply()
				local mine = spawn("combine_mine", p:EyePos() + p:GetForward() * 150)
				expect(mine:GetInternalVariable("m_iMineState")).toNot.beNil()
				expect(G.IsActive(mine)).to.beFalse()
				local bomb = spawn("grenade_helicopter", p:EyePos() + p:GetForward() * 150 + Vector(0, 100, 0))
				expect(bomb:GetInternalVariable("m_bActivated")).to.beFalse()
				expect(G.IsActive(bomb)).to.beFalse()
				local ball = spawn("prop_combine_ball", p:EyePos() + p:GetForward() * 150 + Vector(0, -100, 0))
				expect(ball:GetInternalVariable("m_bLaunched")).to.beFalse()
				expect(G.IsActive(ball)).to.beFalse()
			end
		},
		{
			name = "a new grenade is followed, the tick marks it, and with none around the tick has nothing to do",
			func = function(state)
				local p = ply()
				G.Tick() -- clears the dead ones
				local before = G.TrackedCount()
				local g = spawn("npc_grenade_frag", p:EyePos() + p:GetForward() * 120)
				G.Track(g)
				expect(G.TrackedCount()).to.equal(before + 1)
				g:SetNW2Bool("GryArmed", true) -- a stale mark: the tick corrects it
				G.Tick()
				expect(g:GetNW2Bool("GryArmed")).to.beFalse()
				-- one that is gone (an entity is valid until the end of the frame: a stand-in that can be made invalid at once)
				local alive = true
				local fake = {
					IsValid = function() return alive end,
					GetClass = function() return "combine_mine" end,
					GetVelocity = function() return Vector(0, 0, 0) end,
					GetInternalVariable = function() return 1 end,
					GetNW2Bool = function() return false end,
					SetNW2Bool = function() end,
					GetOwner = function() return NULL end,
					GetNW2Entity = function() return NULL end,
					SetNW2Entity = function() end
				}
				G.Track(fake)
				expect(G.TrackedCount()).to.equal(before + 2)
				alive = false
				G.Tick()
				expect(G.TrackedCount()).to.equal(before + 1)
				g:Remove()
			end
		},
		{
			name = "a third-party mine registered with RegisterTracked (an invented class, its own armed reader) is followed from its creation and marked by the same path as combine_mine",
			func = function(state)
				local p = ply()
				scripted_ents.Register({Type = "anim", Base = "base_anim"}, "t_third_mine")
				expect(GryMod.API.RegisterTracked("t_third_mine", {
					class = "t_third_mine",
					danger = {label = "TRAP", type = "mine", armed = function(ent) return ent.TestArmed == true end}
				})).to.beTrue()

				G.Tick() -- forgets the dead ones
				local before = G.TrackedCount()
				local mine = spawn("t_third_mine", p:EyePos() + p:GetForward() * 150)
				expect(G.TrackedCount()).to.equal(before + 1) -- OnEntityCreated followed it, as for a combine_mine

				G.Tick()
				expect(mine:GetNW2Bool("GryArmed")).to.beFalse() -- its own reader says no
				mine.TestArmed = true
				G.Tick()
				expect(mine:GetNW2Bool("GryArmed")).to.beTrue() -- the five-times-a-second tick marks it: the client warns
				expect(G.IsActive(mine)).to.beTrue()

				mine.TestArmed = false
				G.Tick()
				expect(mine:GetNW2Bool("GryArmed")).to.beFalse()

				-- a registered class is the same everywhere: removing the entry stops the marks
				GryMod.API.UnregisterTracked("t_third_mine")
				mine.TestArmed = true
				expect(G.IsActive(mine)).to.beFalse()
			end
		},
		{
			name = "a danger with no armed reader is dangerous as soon as it exists, but not while a player holds it; a reader that raises an error is no danger and never reaches the tick",
			func = function(state)
				local p = ply()
				scripted_ents.Register({Type = "anim", Base = "base_anim"}, "t_third_mine")
				GryMod.API.RegisterTracked("t_third_mine", {class = "t_third_mine", danger = {label = "TRAP"}})
				local mine = spawn("t_third_mine", p:EyePos() + p:GetForward() * 150)
				G.Update(mine)
				expect(mine:GetNW2Bool("GryArmed")).to.beTrue()

				local held = true
				local stand = {IsValid = function() return true end, GetClass = function() return "t_third_mine" end, IsPlayerHolding = function() return held end}
				expect(G.IsActive(stand)).to.beFalse()
				held = false
				expect(G.IsActive(stand)).to.beTrue()

				local realMsgN = MsgN
				MsgN = function() end
				GryMod.API.RegisterTracked("t_third_mine", {class = "t_third_mine", danger = {armed = function() error("broken reader") end}})
				local ok, active = pcall(G.IsActive, mine)
				MsgN = realMsgN
				expect(ok).to.beTrue()
				expect(active).to.beFalse()
			end
		},
		{
			name = "ownerOf says whose a third-party projectile is: that player is the thrower (GryThrower), so the client never warns them about it",
			func = function(state)
				local p = ply()
				scripted_ents.Register({Type = "anim", Base = "base_anim"}, "t_third_mine")
				GryMod.API.RegisterTracked("t_third_mine", {class = "t_third_mine", danger = {ownerOf = function(ent) return ent.Planter end}})
				local mine = spawn("t_third_mine", p:EyePos() + p:GetForward() * 150)
				G.Update(mine)
				expect(IsValid(mine:GetNW2Entity("GryThrower"))).to.beFalse()
				mine.Planter = p
				G.Update(mine)
				expect(mine:GetNW2Entity("GryThrower")).to.equal(p)
			end
		},
		{
			name = "the tick does not look for entities when none is followed",
			func = function(state)
				local real = {ents.FindByClass, ents.GetAll, ents.FindInSphere}
				local calls = 0
				ents.FindByClass = function(...) calls = calls + 1 return real[1](...) end
				ents.GetAll = function(...) calls = calls + 1 return real[2](...) end
				ents.FindInSphere = function(...) calls = calls + 1 return real[3](...) end
				local ok, err = pcall(function()
					G.Clear()
					G.Tick()
				end)
				ents.FindByClass, ents.GetAll, ents.FindInSphere = real[1], real[2], real[3]
				expect(ok).to.beTrue()
				expect(calls).to.equal(0)
			end
		}
	}
}
