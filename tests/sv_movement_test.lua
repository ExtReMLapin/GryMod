-- Tests of the base speeds option (GryMod.Movement, sv_movement.lua), GLuaTest format, server realm. The option is OFF by default: the walk
-- and run speeds are GryMod's own (200 / 400, and 400 / 600 in the speed mode). Turned on, the four speeds are the original game's, read
-- from its code (research-mech/SPEEDS.md, 1 metre = 52.49 units): walk 177 and sprint 266 in every mode, the speed mode's walk stays 177
-- (its multiplier only works with the sprint key) and its sprint is the top 757 (x2.85 of 266); the speed mode's sprint under a fifth
-- of the bar and empty follow the same multipliers (x1.4, x1.3 of the plain sprint). It is only the speeds: the energy is not touched.

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
		p:SetNWFloat("GryEnergy", 100)

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

				local defaults = {gry_movement = "0", gry_move_walk = "177", gry_move_run = "266", gry_move_speed_walk = "177", gry_move_speed_run = "757"}

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
			name = "on: walk 177 and sprint 266 in the armor, strength and cloak modes; in the speed mode the walk stays 177 and the sprint is 757",
			func = function()
				local M = GryMod.Movement
				GetConVar("gry_movement"):SetString("1")

				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.STRENGTH, GryMod.Modes.CLOAK}) do
					local walk, run = M.Speeds(mode)
					expect(walk).to.equal(177)
					expect(run).to.equal(266)
				end

				local walk, run = M.Speeds(GryMod.Modes.SPEED)
				expect(walk).to.equal(177)
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
				expect(p:GetWalkSpeed()).to.equal(177)
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

				p:SetNWFloat("GryEnergy", 10)
				hook.GetTable().Think["GryMod run speed"]()
				expect(near(p:GetRunSpeed(), low)).to.beTrue()

				p:SetNWFloat("GryEnergy", 90)
				hook.GetTable().Think["GryMod run speed"]()
				expect(p:GetRunSpeed()).to.equal(757)
			end
		},
		{
			name = "the option can be changed by an administrator from the options panel: gry_movement is in the white list, as a switch",
			func = function()
				local S = GryMod.ServerSettings
				local setting = S.Find("gry_movement")

				expect(setting ~= nil).to.beTrue()
				expect(setting.kind).to.equal("bool")
				expect(S.Validate("gry_movement", "1")).to.equal("1")
				expect(S.Validate("gry_movement", "2")).to.beNil()
			end
		}
	}
}
