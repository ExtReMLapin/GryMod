-- Tests of the REPORTING hooks of the server (GLuaTest format, server realm): GryMod only says "this just happened", no return value is
-- ever read from them. GryMod_StrengthJump, GryMod_Zoom, GryMod_ArmorAbsorbed, GryMod_SprintStart, GryMod_SprintEnd.
-- Each case names the production change whose absence makes it fail. Nothing here runs a real game loop: the code paths are called
-- directly (GryMod.SuperJump, GryMod.ZoomFov.Handle, the damage handler, the Think hook GrySpeedThink) the way the engine does.

local function ply()
	return player.GetAll()[1]
end

local savedConfig
local added = {}

-- a hook of the test, removed in afterEach
local function listen(event, fn)
	local id = "gry_hooks_report_test_" .. event .. "_" .. #added
	hook.Add(event, id, fn)
	added[#added + 1] = {event, id}
end

-- the calls an event got: {{arg1, arg2, ...}, ...}; the handler returns `returned` to prove that a returned value changes nothing
local function record(event, returned)
	local calls = {}

	listen(event, function(...)
		calls[#calls + 1] = {...}

		return returned
	end)

	return calls
end

-- the fields a test puts on the real player, put back in afterEach
local touched = {}

local function override(p, key, value)
	if touched[key] == nil then
		touched[key] = {had = rawget(p:GetTable(), key)}
	end

	p[key] = value
end

local function restoreFields(p)
	if IsValid(p) then
		for key, saved in pairs(touched) do
			p[key] = saved.had
		end
	end

	touched = {}
end

local savedJumpPower

-- a player as far as GryMod.ZoomFov looks (the same fake as tests/sv_zoom_fov_test.lua): alive, the normal field of view, no zoom owner
local function fakeZoomPlayer()
	local p = {fovCalls = {}}

	p.IsValid = function() return true end
	p.Alive = function() return true end
	p.GetInfoNum = function(_, name, fallback) return name == "fov_desired" and 100 or fallback end
	p.GetInternalVariable = function() return nil end
	p.SetFOV = function(_, fov, time) p.fovCalls[#p.fovCalls + 1] = {fov, time} end

	return p
end

-- the values a GryMod_Zoom hook got, in order (the player is checked apart)
local function fovs(calls)
	local out = {}

	for i, c in ipairs(calls) do
		out[i] = c[2]
	end

	return out
end

return {
	groupName = "GryMod reporting hooks (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		savedJumpPower = p:GetJumpPower()
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "classic"
		GryMod.Malfunction.Clear(p)
		p:SetNW2Bool("GryDisabled", false)
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		p.ps = false
		GryMod.ZoomFov.Reset()
	end,
	afterEach = function()
		for _, h in ipairs(added) do
			hook.Remove(h[1], h[2])
		end

		added = {}

		local p = ply()
		restoreFields(p)

		if IsValid(p) then
			p:SetJumpPower(savedJumpPower or 200)
			p.ps = false
			GryMod.Malfunction.Clear(p)
			p:SetNW2Bool("GryDisabled", false)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNW2Float("GryEnergy", 100)
			p:SetHealth(p:GetMaxHealth())
		end

		GryMod.ZoomFov.Reset()
		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		-- GryMod_StrengthJump(ply)
		{
			-- fails without: the hook.Run("GryMod_StrengthJump", ply) in the paid branch of GryMod.SuperJump (sv_system.lua)
			name = "GryMod_StrengthJump: a strength jump paid in energy on the ground fires once, after the energy is taken; a returned value changes nothing",
			func = function()
				local p = ply()
				local cost = GryMod.Mech.JumpCost(GryMod.Modes.STRENGTH)
				local energyAtCall
				local calls = {}

				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetNW2Float("GryEnergy", 100)
				override(p, "OnGround", function() return true end)

				listen("GryMod_StrengthJump", function(who)
					calls[#calls + 1] = who
					energyAtCall = who:GetNW2Float("GryEnergy")

					return false -- a report: this must not cancel anything
				end)

				GryMod.SuperJump(p, IN_JUMP)

				expect(#calls).to.equal(1)
				expect(calls[1]).to.equal(p)
				expect(energyAtCall).to.equal(100 - cost)
				expect(p:GetNW2Float("GryEnergy")).to.equal(100 - cost)
				expect(p:GetJumpPower()).to.equal(500)
				expect(p.ps).to.beTrue()
			end
		},
		{
			-- fails without: the hook.Run is in the paid branch only, not in the "energy < cost" branch (the weak jump)
			name = "GryMod_StrengthJump: not fired when the energy is not enough (the weak jump), nor in the air, nor in another mode, nor on another key",
			func = function()
				local p = ply()
				local cost = GryMod.Mech.JumpCost(GryMod.Modes.STRENGTH)
				local calls = record("GryMod_StrengthJump")

				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				override(p, "OnGround", function() return true end)

				-- not enough energy: the weak jump
				p:SetNW2Float("GryEnergy", cost - 1)
				GryMod.SuperJump(p, IN_JUMP)
				expect(#calls).to.equal(0)
				expect(p:GetJumpPower() ~= 500).to.beTrue()
				p.ps = false

				-- in the air
				p:SetNW2Float("GryEnergy", 100)
				override(p, "OnGround", function() return false end)
				GryMod.SuperJump(p, IN_JUMP)
				expect(#calls).to.equal(0)

				-- another key
				override(p, "OnGround", function() return true end)
				GryMod.SuperJump(p, IN_ATTACK)
				expect(#calls).to.equal(0)

				-- another mode
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				GryMod.SuperJump(p, IN_JUMP)
				expect(#calls).to.equal(0)
			end
		},
		{
			-- fails without: the hook.Run is reached with the infinite armor too (the jump is granted, only its price is zero)
			name = "GryMod_StrengthJump: with the infinite armor the jump is granted for nothing and is reported",
			func = function()
				local p = ply()
				local calls = record("GryMod_StrengthJump")

				GryMod.Config.InfiniteArmor = true
				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				p:SetNW2Float("GryEnergy", 12)
				override(p, "OnGround", function() return true end)

				GryMod.SuperJump(p, IN_JUMP)

				expect(#calls).to.equal(1)
				expect(p:GetNW2Float("GryEnergy")).to.equal(12)
			end
		},
		{
			-- fails without: one hook.Run per press, not one per tick or per call of a helper
			name = "GryMod_StrengthJump: one call per press (a second press fires a second time)",
			func = function()
				local p = ply()
				local calls = record("GryMod_StrengthJump")

				p:SetNanosuitMode(GryMod.Modes.STRENGTH, false)
				override(p, "OnGround", function() return true end)

				p:SetNW2Float("GryEnergy", 100)
				GryMod.SuperJump(p, IN_JUMP)
				GryMod.RSuperJump(p, IN_JUMP)
				GryMod.SuperJump(p, IN_JUMP)

				expect(#calls).to.equal(2)
			end
		},
		-- GryMod_Zoom(ply, fov)
		{
			-- fails without: the hook.Run("GryMod_Zoom", ply, fov) after the SetFOV in ZoomFov.Handle (sv_zoom_fov.lua)
			name = "GryMod_Zoom: a new field of view is reported with its value, after the engine got it; the heartbeat (same value) is not; a returned value changes nothing",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakeZoomPlayer()
				local calls = {}
				local engineCallsAtReport

				listen("GryMod_Zoom", function(who, fov)
					calls[#calls + 1] = {who, fov}
					engineCallsAtReport = #p.fovCalls

					return 0 -- a report: this must not change the value
				end)

				expect(Z.Handle(p, 40, 100)).to.equal("set")
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(p)
				expect(calls[1][2]).to.equal(40)
				expect(engineCallsAtReport).to.equal(1)
				expect(Z.Held(p)).to.equal(40)

				expect(Z.Handle(p, 40, 100.5)).to.equal("held")
				expect(#calls).to.equal(1)

				expect(Z.Handle(p, 20, 101)).to.equal("set")
				expect(fovs(calls)[2]).to.equal(20)
				expect(#calls).to.equal(2)
			end
		},
		{
			-- fails without: the value is the one the engine got (raised to MIN_FOV), not the raw request
			name = "GryMod_Zoom: the value is the one the engine got (a request under the minimum is raised to it)",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakeZoomPlayer()
				local calls = record("GryMod_Zoom")

				Z.Handle(p, 1, 100)

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(Z.MIN_FOV)
			end
		},
		{
			-- fails without: the hook.Run(..., 0) in ZoomFov.Release (called by Handle and by Expire)
			name = "GryMod_Zoom: 0 when the zoom ends (a request of 0, or a field of view not below the normal one), once; never when nothing was held",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakeZoomPlayer()
				local calls = record("GryMod_Zoom")

				expect(Z.Handle(p, 0, 100)).to.beFalse()
				expect(#calls).to.equal(0)

				Z.Handle(p, 40, 101)
				expect(Z.Handle(p, 0, 102)).to.equal("release")
				expect(Z.Handle(p, 0, 103)).to.beFalse()
				expect(fovs(calls)[1]).to.equal(40)
				expect(fovs(calls)[2]).to.equal(0)
				expect(#calls).to.equal(2)

				Z.Handle(p, 40, 104)
				expect(Z.Handle(p, 100, 105)).to.equal("release")
				expect(#calls).to.equal(4)
				expect(fovs(calls)[4]).to.equal(0)
			end
		},
		{
			-- fails without: no two equal values in a row (a start, a heartbeat, an end, a second end) gives exactly 40 then 0
			name = "GryMod_Zoom: never the same value twice in a row (start, heartbeats, end, end again: 40 then 0)",
			func = function()
				local Z = GryMod.ZoomFov
				local p = fakeZoomPlayer()
				local calls = record("GryMod_Zoom")

				Z.Handle(p, 40, 100)
				Z.Handle(p, 40, 100.1)
				Z.Handle(p, 40, 100.2)
				Z.Handle(p, 0, 100.3)
				Z.Handle(p, 0, 100.4)
				Z.Release(p)

				expect(fovs(calls)[1]).to.equal(40)
				expect(fovs(calls)[2]).to.equal(0)
				expect(#calls).to.equal(2)
			end
		},
		{
			-- fails without: the report is also in the Release that Expire calls
			name = "GryMod_Zoom: 0 when a request is not renewed and Expire ends it; the one kept alive is not reported",
			func = function()
				local Z = GryMod.ZoomFov
				local stale = fakeZoomPlayer()
				local fresh = fakeZoomPlayer()

				Z.Handle(stale, 40, 100)
				Z.Handle(fresh, 40, 100)
				Z.Handle(fresh, 40, 102.5)

				local calls = record("GryMod_Zoom")

				expect(Z.Expire(103.2)).to.equal(1)
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(stale)
				expect(calls[1][2]).to.equal(0)
			end
		},
		{
			-- fails without: the report in ZoomFov.Forget (what the disconnection hook calls) and in the PostPlayerDeath handler
			name = "GryMod_Zoom: 0 on a disconnection or a death only when a zoom was held, without calling the engine, and not a second time",
			func = function()
				local Z = GryMod.ZoomFov
				local calls = record("GryMod_Zoom")
				local onDeath = hook.GetTable().PostPlayerDeath["GryMod zoom fov"]

				expect(isfunction(onDeath)).to.beTrue()

				-- nothing held: nothing to say
				local idle = fakeZoomPlayer()
				Z.Forget(idle)
				onDeath(idle)
				expect(#calls).to.equal(0)

				-- disconnection
				local leaver = fakeZoomPlayer()
				Z.Handle(leaver, 40, 100)
				Z.Forget(leaver)
				expect(#calls).to.equal(2)
				expect(calls[2][1]).to.equal(leaver)
				expect(calls[2][2]).to.equal(0)
				expect(#leaver.fovCalls).to.equal(1)

				-- death
				local dead = fakeZoomPlayer()
				Z.Handle(dead, 40, 101)
				onDeath(dead)
				expect(#calls).to.equal(4)
				expect(calls[4][1]).to.equal(dead)
				expect(calls[4][2]).to.equal(0)
				expect(#dead.fovCalls).to.equal(1)

				-- both again: still nothing held
				onDeath(dead)
				Z.Forget(dead)
				expect(#calls).to.equal(4)
			end
		}
	}
}
