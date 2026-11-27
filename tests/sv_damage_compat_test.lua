-- Tests of how the suit's armor (sv_health.lua, the EntityTakeDamage hook "Grymod damage handeling") lives with the other addons that change the damage,
-- GLuaTest format, server realm. The hooks of an event run in the order of `pairs` over a table (hook.lua of this version of the game: no priority argument in
-- hook.Add), so the order of two addons' hooks cannot be chosen: the armor can run before or after a mod that scales the damage. The cases call the armor's own function
-- and a stand-in for the other mod in both orders. What must hold WHATEVER the order: the armor never raises an error, never stops the other hooks (it returns
-- nothing), keeps its energy between 0 and its maximum, passes on a damage that is a number that is not negative, and charges nothing for a hit that costs nothing
-- (god mode, a hit of 0). What does depend on the order is stated by one case, so that nobody is surprised by it: the armor pays for the damage it SEES.
-- Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

local function ours()
	return hook.GetTable().EntityTakeDamage["Grymod damage handeling"]
end

local function damage(amount, kind)
	local d = DamageInfo()

	d:SetDamage(amount)
	d:SetDamageType(kind or DMG_BULLET)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())

	return d
end

-- another addon's hook: it scales the damage
local function scaler(factor)
	return function(_, d)
		d:ScaleDamage(factor)
	end
end

-- Runs the armor's function with the network and the reporting hook recorded, whatever happens inside. Returns what it returned, the messages sent and the reports of
-- GryMod_ArmorAbsorbed.
local function run(fn)
	local sent, reports = {}, 0
	local realStart, realSend, realRun = net.Start, net.Send, hook.Run

	net.Start = function(name)
		sent[#sent + 1] = name

		return true
	end
	net.Send = function() end
	hook.Run = function(name, ...)
		if name == "GryMod_ArmorAbsorbed" then
			reports = reports + 1
		end

		return realRun(name, ...)
	end

	local ok, a, b = pcall(fn)

	net.Start, net.Send, hook.Run = realStart, realSend, realRun
	assert(ok, a)

	return a, sent, reports, b
end

local savedConfig

return {
	groupName = "GryMod armor with other addons that change the damage (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		local p = ply()

		if not p:Alive() then
			p:Spawn()
		end

		p:GodDisable()
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Bool("GryDisabled", false)
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.Mechanics = "crysis"
	end,
	afterEach = function()
		local p = ply()

		if IsValid(p) then
			pcall(p.GodDisable, p)
			p:SetNW2Float("GryEnergy", 100)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetHealth(p:GetMaxHealth())
		end

		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		{
			-- fails when the armor drains for a player in god mode (an admin mod's "god", the engine's flag): the bar went down for hits that cost nothing, and the arrows and the
			-- hit sound were told for damage that never came
			name = "a player in god mode: the armor takes no energy, leaves the damage as it is, reports nothing and plays no sound",
			func = function()
				local p = ply()
				local d = damage(30)

				p:GodEnable()

				local _, sent, reports = run(function()
					return ours()(p, d)
				end)

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(d:GetDamage()).to.equal(30)
				expect(reports).to.equal(0)
				expect(#sent).to.equal(0)

				-- and when god mode is off again, the same hit is paid for
				p:GodDisable()
				run(function()
					return ours()(p, damage(30))
				end)
				expect(p:GetNW2Float("GryEnergy")).to.equal(70)
			end
		},
		{
			-- fails when the armor returns a value (the other hooks of the event stop running, and the gamemode's own function is not called: it WILL break other addons, says
			-- the wiki)
			name = "the armor's hook returns nothing, in every state of the suit, so the hooks after it and the gamemode still run",
			func = function()
				local p = ply()

				for _, case in ipairs({
					{GryMod.Modes.ARMOR, 100, false},
					{GryMod.Modes.ARMOR, 0, false},
					{GryMod.Modes.ARMOR, 100, true},
					{GryMod.Modes.SPEED, 100, false},
					{GryMod.Modes.CLOAK, 100, false}
				}) do
					p:SetNanosuitMode(case[1], false)
					p:SetNW2Float("GryEnergy", case[2])
					GryMod.Config.InfiniteArmor = case[3]

					for _, amount in ipairs({0, 1, 30, 150, 5000}) do
						local result = run(function()
							return ours()(p, damage(amount))
						end)

						expect(result).to.beNil()
					end
				end
			end
		},
		{
			-- fails when a mod that scales the damage before or after the armor makes the energy leave 0 to 100, or the damage that goes on negative or not a number
			name = "with a mod that scales the damage, before or after the armor, by 0, a half, 2 or 1000: the energy stays between 0 and 100 and the damage that goes on is a number that is not negative",
			func = function()
				local p = ply()

				for _, factor in ipairs({0, 0.5, 2, 1000}) do
					for _, amount in ipairs({1, 30, 100, 400}) do
						for _, order in ipairs({"before", "after"}) do
							p:SetNW2Float("GryEnergy", 100)

							local d = damage(amount)

							run(function()
								if order == "before" then
									scaler(factor)(p, d)
								end

								ours()(p, d)

								if order == "after" then
									scaler(factor)(p, d)
								end
							end)

							local energy, passed = p:GetNW2Float("GryEnergy"), d:GetDamage()

							expect(energy >= 0 and energy <= 100).to.beTrue()
							expect(passed == passed and passed >= 0).to.beTrue()
						end
					end
				end
			end
		},
		{
			-- fails when the armor no longer pays for what it sees: the day somebody changes the rule (a different order of work), this case says so. It is the order of the
			-- other addon's hook that decides, and nobody can choose it
			name = "the armor pays for the damage it SEES: a mod that doubles the damage and runs before it costs the suit twice as much as one that runs after it",
			func = function()
				local p = ply()

				-- after the armor: it saw 30, paid 30, the mod doubled what was left (nothing)
				local d = damage(30)

				run(function()
					ours()(p, d)
					scaler(2)(p, d)
				end)
				expect(p:GetNW2Float("GryEnergy")).to.equal(70)
				expect(d:GetDamage()).to.equal(0)

				-- before the armor: it saw 60 and paid 60
				p:SetNW2Float("GryEnergy", 100)
				d = damage(30)
				run(function()
					scaler(2)(p, d)
					ours()(p, d)
				end)
				expect(p:GetNW2Float("GryEnergy")).to.equal(40)
				expect(d:GetDamage()).to.equal(0)
			end
		},
		{
			-- fails when a hit of 0 (a mod that cancels the damage first, a blocked hit that the engine still reports) takes energy or reports an absorbed hit
			name = "a hit that already costs nothing (0 damage) takes no energy and reports nothing",
			func = function()
				local p = ply()
				local _, sent, reports = run(function()
					return ours()(p, damage(0))
				end)

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(reports).to.equal(0)
				expect(#sent).to.equal(0)
			end
		}
	}
}
