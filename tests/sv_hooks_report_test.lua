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

-- the damage handler of the armor, called the way the engine calls it; returns the DamageInfo after the handler changed it
local function takeDamage(p, amount, damageType)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(damageType or DMG_BULLET)
	hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, dmg)

	return dmg
end

-- the least part of a hit the armor takes is a rule of the mechanics: the tests choose it (0 = classic, 0.3 = the original game)
local realMinimum

local function setMinimumAbsorption(value)
	realMinimum = realMinimum or GryMod.Mech.ArmorMinimumAbsorption
	GryMod.Mech.ArmorMinimumAbsorption = function() return value end
end

-- the sprint test of the Think hook, told by the test (the real one needs a moving player): only the test player sprints, when `state.on`
local realSprinting
local state = {on = false}

local function stubSprint(p)
	realSprinting = realSprinting or GryMod.IsSpeedSprinting
	state.on = false
	GryMod.IsSpeedSprinting = function(who) return who == p and state.on end
end

local function think()
	hook.GetTable().Think["GrySpeedThink"]()
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

		if realSprinting then
			GryMod.IsSpeedSprinting = realSprinting
			realSprinting = nil
		end

		if IsValid(p) then
			p.gryApiSprint = nil
		end

		if realMinimum then
			GryMod.Mech.ArmorMinimumAbsorption = realMinimum
			realMinimum = nil
		end

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
		},
		-- GryMod_ArmorAbsorbed(ply, absorbed, passed)
		{
			-- fails without: the hook.Run in the "the armor takes all of the hit" branch of the damage handler (sv_health.lua)
			name = "GryMod_ArmorAbsorbed, whole hit: the bar pays all of it: absorbed = the hit, passed = 0, once, after the damage was changed; a returned value changes nothing",
			func = function()
				local p = ply()
				local seenDamage, seenEnergy
				local calls = {}
				local dmg

				p:SetNW2Float("GryEnergy", 100)

				listen("GryMod_ArmorAbsorbed", function(who, absorbed, passed)
					calls[#calls + 1] = {who, absorbed, passed}
					seenDamage = dmg and dmg:GetDamage()
					seenEnergy = who:GetNW2Float("GryEnergy")

					return true -- a report: this must not change the hit
				end)

				-- (the handler reads `dmg` when the hook runs, inside takeDamage: keep the object in reach)
				local info = DamageInfo()
				info:SetDamage(30)
				info:SetDamageType(DMG_BULLET)
				dmg = info
				hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, info)

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(p)
				expect(calls[1][2]).to.equal(30)
				expect(calls[1][3]).to.equal(0)
				expect(seenDamage).to.equal(0) -- already the damage that goes on to the health
				expect(seenEnergy).to.equal(70) -- already paid
				expect(info:GetDamage()).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(70)
			end
		},
		{
			-- fails without: the hook.Run after the partial branch of the damage handler (the bar was not enough)
			name = "GryMod_ArmorAbsorbed, partial: the bar was not enough: absorbed = the energy + the least part the armor takes, passed = what is left, they add up to the hit",
			func = function()
				local p = ply()
				local calls = record("GryMod_ArmorAbsorbed")

				setMinimumAbsorption(0.3)
				p:SetNW2Float("GryEnergy", 20)

				local dmg = takeDamage(p, 50, DMG_BULLET)

				-- the bar (20) leaves 30 to pass, the armor keeps at least 30 percent of the hit (15): 30 passes
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(p)
				expect(calls[1][3]).to.equal(dmg:GetDamage())
				expect(calls[1][2] + calls[1][3]).to.equal(50)
				expect(calls[1][2]).to.equal(20)
				expect(calls[1][3]).to.equal(30)
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
			end
		},
		{
			-- fails without: the least absorption counts as absorbed too (the minimum branch of the same code)
			name = "GryMod_ArmorAbsorbed, partial with an empty bar: the least part the armor takes (30 percent) is reported; with a rule of 0 there is nothing to report",
			func = function()
				local p = ply()
				local calls = record("GryMod_ArmorAbsorbed")

				setMinimumAbsorption(0.3)
				p:SetNW2Float("GryEnergy", 0)
				local dmg = takeDamage(p, 100, DMG_BULLET)

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(30)
				expect(calls[1][3]).to.equal(70)
				expect(dmg:GetDamage()).to.equal(70)

				-- the rule of the classic mechanics: an empty bar takes nothing, so nothing is absorbed
				setMinimumAbsorption(0)
				p:SetNW2Float("GryEnergy", 0)
				takeDamage(p, 100, DMG_BULLET)

				expect(#calls).to.equal(1)
			end
		},
		{
			-- fails without: the hook.Run in the infinite armor branch, before its `return` (sv_health.lua)
			name = "GryMod_ArmorAbsorbed, infinite armor: all of the hit is absorbed, passed = 0, the bar is not touched",
			func = function()
				local p = ply()
				local calls = record("GryMod_ArmorAbsorbed")

				GryMod.Config.InfiniteArmor = true
				p:SetNW2Float("GryEnergy", 55)

				local dmg = takeDamage(p, 40, DMG_BULLET)

				expect(#calls).to.equal(1)
				expect(calls[1][2]).to.equal(40)
				expect(calls[1][3]).to.equal(0)
				expect(dmg:GetDamage()).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(55)
			end
		},
		{
			-- fails without: the `absorbed > 0` test (a hit of 0 goes through the whole-hit branch and the infinite branch)
			name = "GryMod_ArmorAbsorbed: not fired when the armor took nothing (a hit of 0, in either branch that has the bar), nor when the suit is not an armor",
			func = function()
				local p = ply()
				local calls = record("GryMod_ArmorAbsorbed")

				takeDamage(p, 0, DMG_BULLET)
				GryMod.Config.InfiniteArmor = true
				takeDamage(p, 0, DMG_BULLET)
				GryMod.Config.InfiniteArmor = false
				expect(#calls).to.equal(0)

				-- another mode: the armor is not there
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				takeDamage(p, 10, DMG_BULLET)
				expect(#calls).to.equal(0)

				-- the suit is off
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				p:SetNW2Bool("GryDisabled", true)
				takeDamage(p, 10, DMG_BULLET)
				expect(#calls).to.equal(0)
			end
		},
		-- GryMod_SprintStart(ply), GryMod_SprintEnd(ply)
		{
			-- fails without: the flag compared with GryMod.IsSpeedSprinting and the two hook.Run in the Think hook GrySpeedThink (sv_system.lua)
			name = "GryMod_SprintStart / GryMod_SprintEnd: one Start when the speed sprint begins, one End when it stops, nothing on the ticks in between; a returned value changes nothing",
			func = function()
				local p = ply()
				local starts, ends = {}, {}

				stubSprint(p)
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				p:SetNW2Float("GryEnergy", 100)

				listen("GryMod_SprintStart", function(who) starts[#starts + 1] = who return false end)
				listen("GryMod_SprintEnd", function(who) ends[#ends + 1] = who return false end)

				think()
				expect(#starts).to.equal(0)
				expect(#ends).to.equal(0)

				state.on = true
				think()
				expect(#starts).to.equal(1)
				expect(starts[1]).to.equal(p)
				expect(#ends).to.equal(0)

				think()
				think()
				expect(#starts).to.equal(1)
				-- (the drain still works: the reports are not the drain's business)
				expect(p:GetNW2Float("GryEnergy") < 100).to.beTrue()

				state.on = false
				think()
				expect(#ends).to.equal(1)
				expect(ends[1]).to.equal(p)
				expect(#starts).to.equal(1)

				think()
				expect(#ends).to.equal(1)

				-- a second sprint is a second pair
				state.on = true
				think()
				state.on = false
				think()
				expect(#starts).to.equal(2)
				expect(#ends).to.equal(2)
			end
		},
		{
			-- fails without: the check of Alive() in the flag (a dead player is not sprinting: End fires, no Start for him)
			name = "GryMod_SprintEnd: a death ends the sprint on the next tick; a dead player does not start one",
			func = function()
				local p = ply()
				local starts, ends = record("GryMod_SprintStart"), record("GryMod_SprintEnd")

				stubSprint(p)
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				state.on = true
				think()
				expect(#starts).to.equal(1)

				override(p, "Alive", function() return false end)
				think()
				expect(#ends).to.equal(1)

				think()
				expect(#starts).to.equal(1)
				expect(#ends).to.equal(1)
			end
		},
		{
			-- fails without: the same flag compares IsSpeedSprinting, which says false in another mode: End one tick after the change
			name = "GryMod_SprintEnd: leaving the speed mode while sprinting ends it on the next tick",
			func = function()
				local p = ply()
				local starts, ends = record("GryMod_SprintStart"), record("GryMod_SprintEnd")

				-- the real rule this time: a sprinting player in speed mode is what IsSpeedSprinting says; here the stub follows the mode
				stubSprint(p)
				GryMod.IsSpeedSprinting = function(who) return who == p and who.Nanosuit_mode == GryMod.Modes.SPEED end

				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				think()
				expect(#starts).to.equal(1)

				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(#ends).to.equal(0) -- not at once: the Think reports
				think()
				expect(#ends).to.equal(1)
			end
		},
		{
			-- fails without: the PlayerDisconnected handler "GryMod sprint report" that ends a sprint the Think will never see again
			name = "GryMod_SprintEnd: a player who leaves while sprinting gets his End at once (no Start without an End), and only when he was sprinting",
			func = function()
				local p = ply()
				local starts, ends = record("GryMod_SprintStart"), record("GryMod_SprintEnd")
				local onLeave = hook.GetTable().PlayerDisconnected["GryMod sprint report"]

				expect(isfunction(onLeave)).to.beTrue()

				stubSprint(p)
				onLeave(p)
				expect(#ends).to.equal(0)

				state.on = true
				think()
				expect(#starts).to.equal(1)

				onLeave(p)
				expect(#ends).to.equal(1)
				expect(ends[1][1]).to.equal(p)

				onLeave(p)
				expect(#ends).to.equal(1)
			end
		},
		{
			-- fails without: the flag uses GryMod.IsSpeedSprinting (the real rule, the infinite armor included), not a rule of its own
			name = "GryMod_SprintStart / GryMod_SprintEnd follow the real rule of the speed sprint: a fast sprinting player on the ground in speed mode starts one; the infinite armor gives none, and ends it",
			func = function()
				local p = ply()
				local starts, ends = record("GryMod_SprintStart"), record("GryMod_SprintEnd")

				-- the engine's facts only, the rule is GryMod's
				override(p, "IsSprinting", function() return true end)
				override(p, "GetVelocity", function() return Vector(1000, 0, 0) end)
				override(p, "IsOnGround", function() return true end)
				override(p, "WaterLevel", function() return 0 end)

				-- the infinite armor from the start: no sprint, so no Start
				GryMod.Config.InfiniteArmor = true
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				think()
				expect(GryMod.IsSpeedSprinting(p)).to.beFalse()
				expect(#starts).to.equal(0)

				-- the real thing
				GryMod.Config.InfiniteArmor = false
				think()
				expect(GryMod.IsSpeedSprinting(p)).to.beTrue()
				expect(#starts).to.equal(1)

				-- the infinite armor is switched on while he sprints: the sprint is over for the rule
				GryMod.Config.InfiniteArmor = true
				think()
				expect(#ends).to.equal(1)
			end
		}
	}
}
