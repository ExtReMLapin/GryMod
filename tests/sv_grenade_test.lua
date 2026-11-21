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
	end,
	cases = {
		{
			name = "the module, the switch and the classes exist",
			func = function(state)
				expect(G).toNot.beNil()
				expect(GetConVar("gry_grenade_armed_only")).toNot.beNil()
				expect(GetConVar("gry_grenade_armed_only"):GetInt()).to.equal(1)
				expect(GetConVar("gry_grenade_armed_only"):IsFlagSet(FCVAR_REPLICATED)).to.beTrue()

				for _, class in ipairs({"npc_grenade_frag", "grenade_ar2", "rpg_missile", "grenade_helicopter", "combine_mine", "prop_combine_ball"}) do
					expect(G.Classes[class]).toNot.beNil()
				end

				expect(G.Classes.prop_physics).to.beNil()
			end
		},
		{
			name = "a frag grenade is active from the moment its fuse runs (the time of the explosion is in the future), not before",
			func = function(state)
				expect(G.IsActive("npc_grenade_frag", {detonate = -47.2})).to.beFalse() -- never armed: minus the game time
				expect(G.IsActive("npc_grenade_frag", {detonate = 0})).to.beFalse()
				expect(G.IsActive("npc_grenade_frag", {detonate = 2.49})).to.beTrue()
				expect(G.IsActive("npc_grenade_frag", {})).to.beFalse()
			end
		},
		{
			name = "a rifle grenade and a missile are active while they fly (they have no state: they are fired already live)",
			func = function(state)
				expect(G.IsActive("grenade_ar2", {speed = 0})).to.beFalse() -- one made at rest (the spawn menu) stays harmless
				expect(G.IsActive("grenade_ar2", {speed = 900})).to.beTrue()
				expect(G.IsActive("rpg_missile", {speed = 0})).to.beFalse()
				expect(G.IsActive("rpg_missile", {speed = 1100})).to.beTrue()
			end
		},
		{
			name = "a helicopter bomb is active once it has fallen and ticks (activated), or while it falls fast",
			func = function(state)
				expect(G.IsActive("grenade_helicopter", {speed = 0, activated = false})).to.beFalse()
				expect(G.IsActive("grenade_helicopter", {speed = 450, activated = false})).to.beTrue() -- falling at you
				expect(G.IsActive("grenade_helicopter", {speed = 0, activated = true})).to.beTrue() -- the countdown runs
			end
		},
		{
			name = "a hopping mine is active in the air only: not asleep, not armed on the ground, not clicking before the jump",
			func = function(state)
				expect(G.IsActive("combine_mine", {mineState = 1, speed = 0})).to.beFalse() -- on the ground
				expect(G.IsActive("combine_mine", {mineState = 3, speed = 0})).to.beFalse() -- armed, waits for a foe
				expect(G.IsActive("combine_mine", {mineState = 4, speed = 0})).to.beFalse() -- triggered, clicking
				expect(G.IsActive("combine_mine", {mineState = 4, speed = 20})).to.beFalse() -- the little shuffle
				expect(G.IsActive("combine_mine", {mineState = 4, speed = 376})).to.beTrue() -- jumping
				expect(G.IsActive("combine_mine", {mineState = 1, speed = 376})).to.beFalse() -- a mine thrown by physics, not hopping
			end
		},
		{
			name = "an energy ball is active once launched and not held by the gravity gun",
			func = function(state)
				expect(G.IsActive("prop_combine_ball", {launched = false})).to.beFalse()
				expect(G.IsActive("prop_combine_ball", {launched = true, held = false})).to.beTrue()
				expect(G.IsActive("prop_combine_ball", {launched = true, held = true})).to.beFalse()
			end
		},
		{
			name = "an unknown class is never active",
			func = function(state)
				expect(G.IsActive("prop_physics", {speed = 999, detonate = 5, launched = true})).to.beFalse()
				expect(G.IsActive(nil, {})).to.beFalse()
			end
		},
		{
			name = "a frag grenade made at rest is not armed (GryArmed false), a running one is (GryArmed true)",
			func = function(state)
				local p = ply()
				local g = spawn("npc_grenade_frag", p:EyePos() + p:GetForward() * 120)
				G.Update(g)
				expect(g:GetNWBool("GryArmed")).to.beFalse()
				-- the fuse: picking the grenade up arms it (1.5 s) in the engine, then it is let go
				p:PickupObject(g)
				p:DropObject()
				expect(g:GetInternalVariable("m_flDetonateTime") > 0).to.beTrue()
				G.Update(g)
				expect(g:GetNWBool("GryArmed")).to.beTrue()
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
				expect(G.ReadState(g).held).to.beTrue()
				G.Update(g)
				expect(g:GetNWBool("GryArmed")).to.beFalse()
				p:DropObject()
				expect(g:IsPlayerHolding()).to.beFalse()
				G.Update(g)
				expect(g:GetNWBool("GryArmed")).to.beTrue()
			end
		},
		{
			name = "a held projectile is never active, whatever its class",
			func = function(state)
				expect(G.IsActive("npc_grenade_frag", {detonate = 1.5, held = true})).to.beFalse()
				expect(G.IsActive("npc_grenade_frag", {detonate = 1.5, held = false})).to.beTrue()
				expect(G.IsActive("grenade_helicopter", {activated = true, held = true})).to.beFalse()
				expect(G.IsActive("rpg_missile", {speed = 900, held = true})).to.beFalse()
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
				expect(mine:GetNWBool("GryArmed")).to.beFalse()
				expect(bomb:GetNWBool("GryArmed")).to.beFalse()
			end
		},
		{
			name = "the state is read from the entity: the time of the explosion, the mine state, the bomb's flag",
			func = function(state)
				local p = ply()
				local mine = spawn("combine_mine", p:EyePos() + p:GetForward() * 150)
				local read = G.ReadState(mine)
				expect(read.mineState).to.equal(mine:GetInternalVariable("m_iMineState"))
				expect(read.speed).to.equal(mine:GetVelocity():Length())
				local bomb = spawn("grenade_helicopter", p:EyePos() + p:GetForward() * 150 + Vector(0, 100, 0))
				expect(G.ReadState(bomb).activated).to.beFalse()
				local ball = spawn("prop_combine_ball", p:EyePos() + p:GetForward() * 150 + Vector(0, -100, 0))
				expect(G.ReadState(ball).launched).to.beFalse()
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
				g:SetNWBool("GryArmed", true) -- a stale mark: the tick corrects it
				G.Tick()
				expect(g:GetNWBool("GryArmed")).to.beFalse()
				-- one that is gone (an entity is valid until the end of the frame: a stand-in that can be made invalid at once)
				local alive = true
				local fake = {
					IsValid = function() return alive end,
					GetClass = function() return "combine_mine" end,
					GetVelocity = function() return Vector(0, 0, 0) end,
					GetInternalVariable = function() return 1 end,
					GetNWBool = function() return false end,
					SetNWBool = function() end
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
