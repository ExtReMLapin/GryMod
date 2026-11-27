-- Tests of the fall damage and the suit's armor (sv_health.lua, sv_fall_damage.lua), GLuaTest format, server realm.
-- The engine's fall is one number: when a player lands faster than 526.5 units a second it asks `GM:GetFallDamage(ply, speed)` (the hooks of the addons first, then the
-- gamemode) and applies the answer as damage of the type DMG_FALL from the world, through EntityTakeDamage. The armor therefore sees the FINAL number of every
-- addon that answers GetFallDamage, whatever the order of those addons (the order problem of docs/compat.md only exists for addons that scale damage inside
-- EntityTakeDamage). The cases do what the engine does, on the real player: ask the hooks, then apply the answer. The hooks of the addons are stand-ins that answer what the code of
-- JMod, Beatrun, gwater2 and DrGBase answers (read from their public code, see docs/compat.md): none of those addons is needed to run this.
-- Each case names the production change whose absence makes it fail.

local function ply()
	return player.GetAll()[1]
end

-- What the engine does when a player lands: the answer of the hooks, then the damage. Returns the answer (nil: the engine does nothing).
local function land(p, speed)
	local amount = hook.Run("GetFallDamage", p, speed)

	if not isnumber(amount) or amount ~= amount or amount <= 0 then
		return amount
	end

	local d = DamageInfo()

	d:SetDamage(amount)
	d:SetDamageType(DMG_FALL)
	d:SetAttacker(game.GetWorld())
	d:SetInflictor(game.GetWorld())
	p:TakeDamageInfo(d)

	return amount
end

local function realistic(speed)
	return (speed - 526.5) * (100 / 396)
end

local savedConfig
local addedHooks = {}

local function addHook(name, id, fn)
	hook.Add(name, id, fn)
	addedHooks[#addedHooks + 1] = {name, id}
end

-- The gamemode's answer with the setting "realistic fall damage" (mp_falldamage 1: GM:GetFallDamage of the base gamemode). The engine's own convar cannot be set
-- from Lua in the same frame (a console command runs at the end of the frame), so the formula of the gamemode is the hook of the case; the real fall, with the real
-- setting, is the job tests/fall_damage_job.lua.
local function realisticOn()
	addHook("GetFallDamage", "test_realistic", function(_, speed)
		return realistic(speed)
	end)
end

-- the health is whole points: the engine rounds what it takes
local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.01)
end

local function reset()
	local p = ply()

	if not p:Alive() then
		p:Spawn()
	end

	p:GodDisable()
	p:SetHealth(p:GetMaxHealth())
	p:SetNW2Bool("GryDisabled", false)
	p:SetNW2Float("GryEnergy", 100)
	p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
	p.next_energy_regen = CurTime() + 1000 -- no recharge during a case: the bar shows what the armor paid
	GryMod.Config.InfiniteArmor = false
	GryMod.Config.Mechanics = "crysis"
end

return {
	groupName = "GryMod armor and fall damage (server)",
	beforeAll = function()
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function()
		GryMod.Config = table.Copy(savedConfig)
		reset()
	end,
	afterEach = function()
		for _, h in ipairs(addedHooks) do
			hook.Remove(h[1], h[2])
		end

		addedHooks = {}
		GryMod.Config = table.Copy(savedConfig)

		local p = ply()

		if IsValid(p) then
			pcall(p.GodDisable, p)

			if not p:Alive() then
				p:Spawn()
			end

			p:SetNW2Float("GryEnergy", 100)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetHealth(p:GetMaxHealth())
			p.next_energy_regen = CurTime()
		end
	end,
	cases = {
		{
			-- fails when the armor stops paying for DMG_FALL (a rule that lets falls through, an exception for the world as attacker): the bar would not move and the health would
			-- go down, the bug that the owner would see as "the armor does nothing when I fall"
			name = "the game's realistic fall damage (mp_falldamage 1): the armor pays the whole fall, the health is not touched",
			func = function()
				local p = ply()

				realisticOn()

				local amount = land(p, 800)

				expect(near(amount, realistic(800))).to.beTrue()
				expect(near(p:GetNW2Float("GryEnergy"), 100 - realistic(800))).to.beTrue()
				expect(p:Health()).to.equal(p:GetMaxHealth())
			end
		},
		{
			-- fails when the armor's remainder goes wrong for a fall that is more than the bar holds: the part of the fall that the bar cannot pay goes to the health, and at least
			-- 30 percent of it is taken by the armor (the rule of every other damage)
			name = "a fall bigger than the bar: the bar is empty, the health takes the rest, never more than 70 percent of the fall",
			func = function()
				local p = ply()

				realisticOn()
				p:SetNW2Float("GryEnergy", 30)

				local amount = land(p, 900)
				local rest = amount - 30

				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				expect(near(p:GetMaxHealth() - p:Health(), math.min(rest, amount * 0.7), 1)).to.beTrue()
			end
		},
		{
			-- fails when the armor pays for a fall in a mode that is not the armor: the speed, the strength and the camouflage have no armor, the health takes the fall
			name = "in the strength, speed and camouflage modes the fall goes to the health and the bar is not touched",
			func = function()
				local p = ply()

				realisticOn()

				for _, mode in ipairs({GryMod.Modes.STRENGTH, GryMod.Modes.SPEED, GryMod.Modes.CLOAK}) do
					p:SetHealth(p:GetMaxHealth())
					p:SetNanosuitMode(mode, false)
					p:SetNW2Float("GryEnergy", 100)

					land(p, 800)

					expect(p:GetNW2Float("GryEnergy") >= 99.9).to.beTrue()
					expect(near(p:GetMaxHealth() - p:Health(), realistic(800), 1)).to.beTrue()
				end
			end
		},
		{
			-- fails when a fall is paid in god mode: the bar would go down for damage that never comes
			name = "god mode: a hard fall costs nothing, the bar included",
			func = function()
				local p = ply()

				realisticOn()
				p:GodEnable()
				land(p, 1200)

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(p:Health()).to.equal(p:GetMaxHealth())
			end
		},
		{
			-- fails when the armor counts a fall twice (a second hook that also pays, a fall reported as two hits) or lets the number of an addon through unchanged. JMod's rule:
			-- speed squared over 8000
			name = "a fall damage addon that answers GetFallDamage (JMod: speed squared over 8000): the armor pays exactly its number",
			func = function()
				local p = ply()

				addHook("GetFallDamage", "test_jmod", function(_, speed)
					return speed ^ 2 / 8000
				end)

				local amount = land(p, 700)

				expect(near(amount, 61.25)).to.beTrue()
				expect(near(p:GetNW2Float("GryEnergy"), 100 - 61.25)).to.beTrue()
				expect(p:Health()).to.equal(p:GetMaxHealth())
			end
		},
		{
			-- fails when the armor takes a fall that an addon cancelled (Beatrun's landing mat and the rolls, gwater2's water, DrGBase's possession, a bunny hop addon: they answer 0)
			name = "an addon that answers 0 (a roll, water, a landing mat): the fall costs nothing, no energy, no health",
			func = function()
				local p = ply()

				addHook("GetFallDamage", "test_zero", function()
					return 0
				end)
				land(p, 1000)

				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
				expect(p:Health()).to.equal(p:GetMaxHealth())
			end
		},
		{
			-- fails when the armor stops a lethal fall (Prone Mod's multiplier is for a prone player only: Beatrun sends math.huge for a fall of 800 or more, and means it): the
			-- suit must not make a fall that an addon wants deadly harmless, and must not raise an error for a number that is not finite
			name = "an addon that answers math.huge (Beatrun at 800 and more): the player dies, the energy stays a number between 0 and 100, no error",
			func = function()
				local p = ply()

				addHook("GetFallDamage", "test_beatrun", function(_, speed)
					if speed >= 800 then
						return math.huge
					end

					return 0
				end)

				land(p, 600)
				expect(p:Alive()).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)

				local ok, err = pcall(land, p, 900)

				expect(ok).to.beTrue()
				expect(err).to.equal(math.huge)
				expect(p:Alive()).to.beFalse()

				local energy = p:GetNW2Float("GryEnergy")

				expect(energy >= 0 and energy <= 100).to.beTrue()
			end
		},
		{
			-- fails when two addons that answer GetFallDamage make the armor's payment depend on which one the engine asked first: the engine takes the first number that is not nil, so
			-- the armor only ever sees ONE number. The two cases below are the same hook table in two orders of declaration
			name = "two addons that answer GetFallDamage: the armor pays the number the engine used, not the sum",
			func = function()
				local p = ply()

				addHook("GetFallDamage", "test_a", function(_, speed)
					return 20
				end)
				addHook("GetFallDamage", "test_b", function(_, speed)
					return 20
				end)

				local amount = land(p, 800)

				expect(amount).to.equal(20)
				expect(near(p:GetNW2Float("GryEnergy"), 80)).to.beTrue()
			end
		},
		-- The setting gry_realistic_fall (sv_fall_damage.lua): it turns the game's own setting mp_falldamage on and keeps it on between two launches of the game (the game's setting
		-- is reset to 0 at every launch). The game's setting cannot be changed in the same frame, so the file's two functions that touch it are replaced by recorders.
		{
			-- fails when the setting does not exist, is not saved (the whole point: the game forgets its own), or is on by default (the default behaviour of the game must not change)
			name = "gry_realistic_fall exists: saved, replicated, off by default",
			func = function()
				local convar = GetConVar("gry_realistic_fall")

				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0")
				expect(convar:IsFlagSet(FCVAR_REPLICATED)).to.beTrue()
				-- the engine does not show the archive bit: the flags are those of the other saved, replicated, notified settings of the server
				expect(convar:GetFlags()).to.equal(GetConVar("gry_malfunction"):GetFlags())
			end
		},
		{
			-- fails when the setting does not turn the game's setting on, turns it on every time it is asked (a command at every sync), or does not take it back when it is turned off
			name = "gry_realistic_fall on turns the game's setting on once, off turns it back off",
			func = function()
				local FD = GryMod.FallDamage
				local engine, commands = false, {}
				local realOn, realSet = FD.EngineOn, FD.SetEngine

				FD.EngineOn = function() return engine end
				FD.SetEngine = function(on)
					engine = on
					commands[#commands + 1] = tostring(on)
				end
				FD.Owned = false

				local ok, err = pcall(function()
					FD.Sync(true)
					FD.Sync(true)
					expect(table.concat(commands, ",")).to.equal("true")
					FD.Sync(false)
					FD.Sync(false)
					expect(table.concat(commands, ",")).to.equal("true,false")
				end)

				FD.EngineOn, FD.SetEngine, FD.Owned = realOn, realSet, false
				assert(ok, err)
			end
		},
		{
			-- fails when the setting turns off a game's setting that somebody else turned on (the checkbox of the sandbox, a server's config, an admin): GryMod only takes back what it set itself
			name = "gry_realistic_fall off leaves the game's setting alone when it was already on before",
			func = function()
				local FD = GryMod.FallDamage
				local commands = {}
				local realOn, realSet = FD.EngineOn, FD.SetEngine

				FD.EngineOn = function() return true end
				FD.SetEngine = function(on) commands[#commands + 1] = on end
				FD.Owned = false

				local ok, err = pcall(function()
					FD.Sync(true)
					FD.Sync(false)
					expect(#commands).to.equal(0)
				end)

				FD.EngineOn, FD.SetEngine, FD.Owned = realOn, realSet, false
				assert(ok, err)
			end
		},
		{
			-- fails when changing the convar (the options panel, the console, a config file) does not reach Sync: the setting would only work at the next launch
			name = "changing gry_realistic_fall runs the sync at once",
			func = function()
				local FD = GryMod.FallDamage
				local convar = GetConVar("gry_realistic_fall")
				local before = convar:GetString()
				local seen = {}
				local realSync = FD.Sync

				FD.Sync = function(wanted) seen[#seen + 1] = tostring(wanted) end

				local ok, err = pcall(function()
					convar:SetString("1")
					convar:SetString("0")
					expect(table.concat(seen, ",")).to.equal("true,false")
				end)

				FD.Sync = realSync
				convar:SetString(before)
				assert(ok, err)
			end
		},
		{
			-- fails when the setting is not in the white list of the administrators' settings (the panel could not change it on a dedicated server)
			name = "gry_realistic_fall is a setting an administrator may change from the options panel",
			func = function()
				expect(GryMod.ServerSettings.Validate("gry_realistic_fall", "1")).to.equal("1")
				expect(GryMod.ServerSettings.Validate("gry_realistic_fall", "2")).to.beNil()
			end
		}
	}
}
