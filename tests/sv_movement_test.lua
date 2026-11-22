-- Tests of the base speeds option (GryMod.Movement, sh_movement.lua and sv_movement.lua), GLuaTest format, server realm. gry_movement has three
-- positions. 0 (default): the walk and run speeds are GryMod's own (200 / 400, and 400 / 600 in the speed mode). 1, "Crysis vanilla speed": the
-- original game's speeds, read from its code (research-mech/SPEEDS.md, 1 metre = 52.49 units): walk 177 and sprint 266 in every mode, the speed
-- mode's walk 221.25 (177 x 1.25: the owner's choice, the demo's code gives 177) and its sprint a ramp from x1.3 to
-- the top 757 (x2.85 of 266) in one second, x1.4 under a fifth of the bar and x1.3 empty. 2, "Crysis ratios": GMod's own walk and sprint (200 / 400)
-- with the same ratios (the speed mode's walk x1.25, its sprint x1.3 to x2.85 of 400). In 1 and 2 the energy rules are the original's too.

local NAMES = {"gry_movement", "gry_move_walk", "gry_move_run", "gry_move_speed_walk", "gry_move_speed_run"}

local function ply()
	return player.GetAll()[1]
end

local function near(a, b)
	return math.abs(a - b) < 0.01
end

local saved = {}

return {
	groupName = "GryMod base speeds option (server)",
	beforeAll = function()
		for _, name in ipairs(NAMES) do
			local c = GetConVar(name)
			saved[name] = c and c:GetString()
		end
	end,
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end
		p:SetNW2Float("GryEnergy", 100)

		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end

		GetConVar("gry_movement"):SetString("0")
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
	end,
	afterEach = function()
		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end

		local p = ply()
		if IsValid(p) then
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		end
	end,
	cases = {
		{
			name = "the option is off by default, with the original game's four speeds as the values, replicated",
			func = function()
				local M = GryMod.Movement
				expect(M).to.exist()

				local defaults = {gry_movement = "0", gry_move_walk = "177", gry_move_run = "266", gry_move_speed_walk = "221.25", gry_move_speed_run = "757"}

				for name, value in pairs(defaults) do
					local c = GetConVar(name)
					expect(c ~= nil).to.beTrue()
					expect(c:GetDefault()).to.equal(value)
					-- (FCVAR_ARCHIVE is not reported by the server's convars in single player, the other options of the server are the same)
					expect(c:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				end

				expect(M.Enabled()).to.beFalse()
			end
		},
		{
			name = "off: the speeds are GryMod's own, 200 / 400 and 400 / 600 in the speed mode, whatever the four values say",
			func = function()
				local M = GryMod.Movement
				GetConVar("gry_move_walk"):SetString("50")
				GetConVar("gry_move_run"):SetString("60")

				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.STRENGTH, GryMod.Modes.CLOAK}) do
					local walk, run = M.Speeds(mode)
					expect(walk).to.equal(200)
					expect(run).to.equal(400)
				end

				local walk, run = M.Speeds(GryMod.Modes.SPEED)
				expect(walk).to.equal(400)
				expect(run).to.equal(600)
			end
		},
		{
			name = "mode 1: walk 177 and sprint 266 in the armor, strength and cloak modes; in the speed mode the walk is 177 x 1.25 (the owner's choice) and the sprint is 757",
			func = function()
				local M = GryMod.Movement
				GetConVar("gry_movement"):SetString("1")

				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.STRENGTH, GryMod.Modes.CLOAK}) do
					local walk, run = M.Speeds(mode)
					expect(walk).to.equal(177)
					expect(run).to.equal(266)
				end

				local walk, run = M.Speeds(GryMod.Modes.SPEED)
				expect(walk).to.equal(221.25)
				expect(run).to.equal(757)
			end
		},
		{
			name = "on: the four values are the ones the convars hold, and a value that is not a sane speed is cut to the engine's range",
			func = function()
				local M = GryMod.Movement
				GetConVar("gry_movement"):SetString("1")
				GetConVar("gry_move_walk"):SetString("150")
				GetConVar("gry_move_run"):SetString("300")
				GetConVar("gry_move_speed_walk"):SetString("250")
				GetConVar("gry_move_speed_run"):SetString("900")

				local walk, run = M.Speeds(GryMod.Modes.ARMOR)
				expect(walk).to.equal(150)
				expect(run).to.equal(300)

				walk, run = M.Speeds(GryMod.Modes.SPEED)
				expect(walk).to.equal(250)
				expect(run).to.equal(900)

				-- nonsense: not under 50, not above 2000 (a player at 5000 u/s leaves the map)
				GetConVar("gry_move_walk"):SetString("-10")
				GetConVar("gry_move_run"):SetString("99999")
				walk, run = M.Speeds(GryMod.Modes.ARMOR)
				expect(walk).to.equal(M.MIN_SPEED)
				expect(run).to.equal(M.MAX_SPEED)
			end
		},
		{
			name = "the mode change gives the player the speeds of the mode, option off or on",
			func = function()
				local p = ply()

				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(p:GetWalkSpeed()).to.equal(400)
				expect(p:GetRunSpeed()).to.equal(600)

				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(p:GetWalkSpeed()).to.equal(200)
				expect(p:GetRunSpeed()).to.equal(400)

				GetConVar("gry_movement"):SetString("1")
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(p:GetWalkSpeed()).to.equal(177)
				expect(p:GetRunSpeed()).to.equal(266)

				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(p:GetWalkSpeed()).to.equal(221.25)
				expect(p:GetRunSpeed()).to.equal(757)
			end
		},
		{
			name = "turning the option on or off, or changing a value, reaches the players at once, in the mode they are in",
			func = function()
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
				expect(p:GetRunSpeed()).to.equal(400)

				GetConVar("gry_movement"):SetString("1")
				expect(p:GetWalkSpeed()).to.equal(177)
				expect(p:GetRunSpeed()).to.equal(266)

				GetConVar("gry_move_run"):SetString("300")
				expect(p:GetRunSpeed()).to.equal(300)

				GetConVar("gry_movement"):SetString("0")
				expect(p:GetWalkSpeed()).to.equal(200)
				expect(p:GetRunSpeed()).to.equal(400)
			end
		},
		{
			name = "the speed mode's sprint follows the energy on the option's speeds too: 757 above a fifth of the bar, x1.4 of 266 under it, x1.3 empty",
			func = function()
				local p = ply()
				local M = GryMod.Mech
				GetConVar("gry_movement"):SetString("1")
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)

				-- the multipliers are put on the line 266 -> 757 (x1 -> x2.85): about 266 x 1.4 and 266 x 1.3
				local low = 266 + (1.4 - 1) / (2.85 - 1) * (757 - 266)
				local empty = 266 + (1.3 - 1) / (2.85 - 1) * (757 - 266)

				expect(M.SpeedRunSpeed(80)).to.equal(757)
				expect(near(M.SpeedRunSpeed(10), low)).to.beTrue()
				expect(near(M.SpeedRunSpeed(0), empty)).to.beTrue()
				expect(math.abs(low - 266 * 1.4) < 2).to.beTrue()

				-- the sprint key is held, and has been for two seconds (the climb of the first second is over): the top, or the multiplier of the bar
				local realHeld = M.SprintHeld
				M.SprintHeld = function() return true end
				p.gry_sprint_since = CurTime() - 2

				local ok, err = pcall(function()
					p:SetNW2Float("GryEnergy", 10)
					hook.GetTable().Think["GryMod run speed"]()
					expect(near(p:GetRunSpeed(), low)).to.beTrue()

					p:SetNW2Float("GryEnergy", 90)
					hook.GetTable().Think["GryMod run speed"]()
					expect(near(p:GetRunSpeed(), 757)).to.beTrue()
				end)

				M.SprintHeld = realHeld
				p.gry_sprint_since = nil

				if not ok then error(err, 0) end
			end
		},
		{
			name = "mode 2, Crysis ratios: GMod's own 200 / 400 in the armor, strength and cloak modes; the speed mode's walk is 200 x 1.25 and its sprint 400 x (757 / 266)",
			func = function()
				local M = GryMod.Movement
				GetConVar("gry_movement"):SetString("2")
				expect(M.Mode()).to.equal(2)
				expect(M.Enabled()).to.beTrue()

				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.STRENGTH, GryMod.Modes.CLOAK}) do
					local walk, run = M.Speeds(mode)
					expect(walk).to.equal(200)
					expect(run).to.equal(400)
				end

				local walk, run = M.Speeds(GryMod.Modes.SPEED)
				expect(near(walk, 250)).to.beTrue()
				expect(near(run, 400 * 757 / 266)).to.beTrue()
			end
		},
		{
			name = "the setting holds 0, 1 or 2 and nothing else (the engine cuts it), and Mode reads it as a whole number",
			func = function()
				local M = GryMod.Movement
				local c = GetConVar("gry_movement")
				c:SetString("5")
				expect(M.Mode()).to.equal(2)
				c:SetString("-3")
				expect(M.Mode()).to.equal(0)
				c:SetString("1")
				expect(M.Mode()).to.equal(1)
			end
		},
		{
			-- the code of the original: 1 + max(0.3, 1.85 x min(1, seconds of sprint)): x1.3 for the first 0.16 s, then up to x2.85 at one second
			name = "the speed sprint's multiplier is x1.3 at the start, x2.85 after one second, straight in between",
			func = function()
				local M = GryMod.Movement
				expect(near(M.SprintMultiplier(0), 1.3)).to.beTrue()
				expect(near(M.SprintMultiplier(0.15), 1.3)).to.beTrue()
				expect(near(M.SprintMultiplier(0.5), 1 + 1.85 * 0.5)).to.beTrue()
				expect(near(M.SprintMultiplier(1), 2.85)).to.beTrue()
				expect(near(M.SprintMultiplier(7), 2.85)).to.beTrue()
				expect(near(M.SprintMultiplier(-1), 1.3)).to.beTrue()
			end
		},
		{
			name = "mode 1: the speed mode's sprint climbs from x1.3 to the top in a second on the line 266 -> 757; under a fifth of the bar and empty it does not climb",
			func = function()
				local M = GryMod.Mech
				GetConVar("gry_movement"):SetString("1")
				local function line(mult) return 266 + (mult - 1) / (2.85 - 1) * (757 - 266) end

				expect(near(M.SpeedRunSpeed(80, 0), line(1.3))).to.beTrue()
				expect(near(M.SpeedRunSpeed(80, 0.5), line(1 + 1.85 * 0.5))).to.beTrue()
				expect(near(M.SpeedRunSpeed(80, 1), 757)).to.beTrue()
				expect(near(M.SpeedRunSpeed(80, 4), 757)).to.beTrue()
				expect(near(M.SpeedRunSpeed(10, 0), line(1.4))).to.beTrue()
				expect(near(M.SpeedRunSpeed(10, 5), line(1.4))).to.beTrue()
				expect(near(M.SpeedRunSpeed(0, 5), line(1.3))).to.beTrue()
			end
		},
		{
			name = "mode 2: the same climb on the line 400 -> 400 x 757 / 266",
			func = function()
				local M = GryMod.Mech
				GetConVar("gry_movement"):SetString("2")
				local top = 400 * 757 / 266
				local function line(mult) return 400 + (mult - 1) / (2.85 - 1) * (top - 400) end

				expect(near(M.SpeedRunSpeed(80, 0), line(1.3))).to.beTrue()
				expect(near(M.SpeedRunSpeed(80, 1), top)).to.beTrue()
				expect(near(M.SpeedRunSpeed(10, 0), line(1.4))).to.beTrue()
			end
		},
		{
			name = "the option off keeps the old behaviour: the speed mode's sprint is the top as soon as there is energy, however short the sprint",
			func = function()
				local M = GryMod.Mech
				expect(M.SpeedRunSpeed(80, 0)).to.equal(600)
				expect(M.SpeedRunSpeed(80, 0.3)).to.equal(600)
			end
		},
		{
			-- the Think hook of the run speed counts how long the sprint key has been held (Mech.SprintHeld, a field so that a test can say it is)
			name = "in the speed mode the run speed follows the seconds of sprint: a sprint begun now is x1.3, one begun a second ago the top, a sprint let go starts again",
			func = function()
				local p = ply()
				local M = GryMod.Mech
				local held = true
				local realHeld = M.SprintHeld
				M.SprintHeld = function() return held end

				local ok, err = pcall(function()
					GetConVar("gry_movement"):SetString("1")
					p:SetNanosuitMode(GryMod.Modes.SPEED, false)
					p:SetNW2Float("GryEnergy", 90)
					p.gry_sprint_since = nil

					local think = hook.GetTable().Think["GryMod run speed"]
					think()
					expect(near(p:GetRunSpeed(), 266 + 0.3 / 1.85 * (757 - 266))).to.beTrue()

					p.gry_sprint_since = CurTime() - 1.2
					think()
					expect(near(p:GetRunSpeed(), 757)).to.beTrue()

					held = false
					think()
					expect(p.gry_sprint_since).to.beNil()
					held = true
					think()
					expect(near(p:GetRunSpeed(), 266 + 0.3 / 1.85 * (757 - 266))).to.beTrue()
				end)

				M.SprintHeld = realHeld

				if not ok then error(err, 0) end
			end
		},
		{
			-- the fixed 412 units a second of the old rule is above the speed mode's first sprint (345): the drain and the servo sound would start late
			name = "the speed under which a sprint is not counted follows the mode: 412 off, a little over the speed mode's walk on 1 and 2",
			func = function()
				local M = GryMod.Movement
				expect(near(M.SprintSpeedSqr(), 170000)).to.beTrue()

				GetConVar("gry_movement"):SetString("1")
				expect(near(M.SprintSpeedSqr(), (221.25 * 1.15) ^ 2)).to.beTrue()

				GetConVar("gry_movement"):SetString("2")
				expect(near(M.SprintSpeedSqr(), (250 * 1.15) ^ 2)).to.beTrue()
			end
		},
		{
			name = "on 1 and 2 the energy rules are the original's whatever gry_mechanics says: the speed sprint takes 42.5 a second above a fifth of the bar, 1.5 under it, nothing empty",
			func = function()
				local M = GryMod.Mech
				local mechanics = GetConVar("gry_mechanics")
				local before = mechanics:GetString()
				mechanics:SetString("classic")

				local ok, err = pcall(function()
					GetConVar("gry_movement"):SetString("0")
					expect(M.IsCrysis()).to.beFalse()

					for _, setting in ipairs({"1", "2"}) do
						GetConVar("gry_movement"):SetString(setting)
						expect(M.IsCrysis()).to.beTrue()
						expect(M.SpeedDrain(80)).to.equal(42.5)
						expect(M.SpeedDrain(10)).to.equal(1.5)
						expect(M.SpeedDrain(0)).to.equal(0)
					end
				end)

				mechanics:SetString(before)

				if not ok then error(err, 0) end
			end
		},
		{
			name = "the option can be changed by an administrator from the options panel: gry_movement is in the white list, as a choice of three",
			func = function()
				local S = GryMod.ServerSettings
				local setting = S.Find("gry_movement")

				expect(setting ~= nil).to.beTrue()
				expect(setting.kind).to.equal("choice")
				expect(S.Validate("gry_movement", "1")).to.equal("1")
				expect(S.Validate("gry_movement", "2")).to.equal("2")
				expect(S.Validate("gry_movement", "3")).to.beNil()
			end
		}
	}
}
