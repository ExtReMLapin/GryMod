-- Tests of the clean-up when a player dies (server realm, GLuaTest format).
-- `GM:PlayerDeath` is not called after `Player:KillSilent()`, `GM:PostPlayerDeath` is called after every death (wiki; measured
-- on a test client: Kill and TakeDamage run DoPlayerDeath, PlayerDeath, PostPlayerDeath; KillSilent only PostPlayerDeath).
-- The suit failure, the radar contacts, the drowning count and the health repair sound have to end with the life, whichever way
-- it ended. These tests use the real engine calls on the test client's player and bring it back with Spawn.

local function ply()
	return player.GetAll()[1]
end

local STUBBED = {"Start", "Send", "WriteUInt", "WriteInt", "WriteBool", "WriteFloat", "WriteEntity", "WriteString"}

-- run fn with the net library recording the messages it starts; the real functions are back whatever happens inside
local function recorded(fn)
	local sent, real = {}, {}

	for _, name in ipairs(STUBBED) do
		real[name] = net[name]
		net[name] = function() end
	end

	net.Start = function(name)
		sent[#sent + 1] = name

		return true
	end

	local ok, err = pcall(fn)

	for _, name in ipairs(STUBBED) do
		net[name] = real[name]
	end

	if not ok then
		error(err, 0)
	end

	return sent
end

local function count(sent, name)
	local n = 0

	for _, message in ipairs(sent) do
		if message == name then n = n + 1 end
	end

	return n
end

-- a life with every state the clean-up is about
local function dirty(p)
	p:SetHealth(p:GetMaxHealth())
	assert(GryMod.Malfunction.Start(p, 30, "emp"), "the suit did not go down")
	GryMod.Radar.State(p).sent = {{id = 1}, {id = 2}}
	p.gryDrown = GryMod.Drown.NewState()
	p:SetNWBool("GryDrowning", true)
	p.should_heath_regen = true
	p.next_health_regen = CurTime() + 5
	p.last_repair_sound = CurTime()
end

local function clean(p)
	expect(p:GetNWBool("GryMalfunction")).to.beFalse()
	expect(timer.Exists("GryMalfunction" .. p:EntIndex())).to.beFalse()
	expect(p.gryMalfunctionEnd).to.beNil()
	expect(GryMod.Radar.State(p).sent).to.beNil()
	expect(p.gryDrown).to.beNil()
	expect(p:GetNWBool("GryDrowning")).to.beFalse()
	expect(p.should_heath_regen).to.equal(false)
end

-- each way of dying, then a new life; the player is always brought back
local function die(how)
	local p = ply()
	p:Spawn()
	dirty(p)
	local sent, again

	local ok, err = pcall(function()
		sent = recorded(function()
			how(p)
		end)
		expect(p:Alive()).to.beFalse()
		clean(p)
		expect(p.next_health_regen).to.equal(0)

		-- the death hooks run a second time (an addon calling them again, or one more death hook): nothing is done twice
		again = recorded(function()
			hook.Run("PostPlayerDeath", p)
		end)
		clean(p)
	end)

	p:Spawn()
	GryMod.Malfunction.Clear(p)

	if not ok then
		error(err, 0)
	end

	return sent, again, p
end

return {
	groupName = "GryMod clean-up at death (server)",
	afterAll = function(state)
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end
	end,
	cases = {
		{
			name = "the clean-up is on the hook every death goes through, PostPlayerDeath (PlayerDeath is skipped by KillSilent)",
			func = function(state)
				local hooks = hook.GetTable()

				expect(hooks.PostPlayerDeath["grymod death stop healing sound"]).to.beA("function")
				expect(hooks.PostPlayerDeath["GryMod malfunction death"]).to.beA("function")
				expect(hooks.PostPlayerDeath["GryMod radar"]).to.beA("function")
				expect(hooks.PostPlayerDeath["GryDrownClear"]).to.beA("function")
				expect(hooks.PostPlayerDeath["GryCloakAI"]).to.beA("function")

				for _, name in ipairs({"grymod death stop healing sound", "GryMod malfunction death", "GryMod radar", "GryDrownClear"}) do
					expect((hooks.PlayerDeath or {})[name]).to.beNil()
				end
			end
		},
		{
			name = "a silent kill ends the suit failure, the radar contacts, the drowning and the repair sound, and tells the client once",
			func = function(state)
				local sent = die(function(p) p:KillSilent() end)

				expect(count(sent, "gry_stop_health_regen")).to.equal(1)
				expect(count(sent, "gry_radar")).to.equal(1)
			end
		},
		{
			name = "an ordinary death does the same",
			func = function(state)
				local sent = die(function(p) p:Kill() end)

				expect(count(sent, "gry_stop_health_regen")).to.equal(1)
				expect(count(sent, "gry_radar")).to.equal(1)
			end
		},
		{
			name = "a death by damage does the same",
			func = function(state)
				local sent = die(function(p) p:TakeDamage(10000) end)

				-- the hit itself already stops the repair sound once: the death may add its own stop
				expect(count(sent, "gry_stop_health_regen")).to.beGreaterThan(0)
				expect(count(sent, "gry_radar")).to.equal(1)
			end
		},
		{
			name = "running the death hooks again sends nothing more",
			func = function(state)
				local _, again = die(function(p) p:KillSilent() end)

				expect(#again).to.equal(0)
			end
		},
		{
			name = "after a silent kill the next life is clean and the suit can go down again",
			func = function(state)
				local _, _, p = die(function(p) p:KillSilent() end)

				expect(p:Alive()).to.beTrue()
				clean(p)
				expect(GryMod.Malfunction.Start(p, 5, "emp")).to.beTrue()
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				GryMod.Malfunction.Clear(p)
			end
		}
	}
}
