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
		}
	}
}
