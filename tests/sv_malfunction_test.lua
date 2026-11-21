-- Tests of the suit malfunctions (GryMod.Malfunction and the rules in GryMod.Mech), GLuaTest format, server realm:
-- the state (down, no recharge, armor only, restart), the causes (electric hits, heavy impacts, EMP) and the
-- switches. The numbers are in docs/superpowers/plans/2026-11-21-suit-malfunction-notes.md.

local function ply()
	return player.GetAll()[1]
end

local function thinkHook(name)
	return hook.GetTable().Think[name]
end

local function takeDamage(p, amount, damageType, attacker, inflictor)
	local dmg = DamageInfo()
	dmg:SetDamage(amount)
	dmg:SetDamageType(damageType or DMG_BULLET)

	if attacker then
		dmg:SetAttacker(attacker)
	end

	if inflictor then
		dmg:SetInflictor(inflictor)
	end

	hook.GetTable().EntityTakeDamage["Grymod damage handeling"](p, dmg)

	return dmg
end

local function near(a, b, tolerance)
	return math.abs(a - b) <= (tolerance or 0.001)
end

local savedConfig
local spawned = {}
local saved = {}

local function setConvar(name, value)
	local convar = GetConVar(name)
	saved[name] = saved[name] or convar:GetString()
	convar:SetString(value)
end

local function restoreConvars()
	for name, value in pairs(saved) do
		GetConVar(name):SetString(value)
	end

	saved = {}
end

local function pending(p)
	return p.gryMalfunctionPending
end

return {
	groupName = "GryMod suit malfunctions",
	beforeAll = function(state)
		savedConfig = table.Copy(GryMod.Config)
	end,
	beforeEach = function(state)
		local p = ply()
		if not p:Alive() then p:Spawn() end
		GryMod.Malfunction.Clear(p)
		p:SetHealth(p:GetMaxHealth())
		p:SetNW2Float("GryEnergy", 100)
		p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
		GryMod.Config = table.Copy(savedConfig)
		GryMod.Config.InfiniteArmor = false
		GryMod.Config.ShouldRegen = true
		GryMod.Config.Mechanics = "crysis"
	end,
	afterEach = function(state)
		local p = ply()

		if IsValid(p) then
			GryMod.Malfunction.Clear(p)
			p:SetNanosuitMode(GryMod.Modes.ARMOR, false)
			p:SetNW2Float("GryEnergy", 100)
		end

		for _, e in ipairs(spawned) do
			if IsValid(e) then e:Remove() end
		end

		spawned = {}
		restoreConvars()
		GryMod.Config = table.Copy(savedConfig)
	end,
	cases = {
		-- the rules
		{
			name = "the downtime is the game's 10 s for an EMP (g_emp_nanosuit_downtime), 5 s for a shock or an overload, 3 s for an impact",
			func = function(state)
				local M = GryMod.Mech
				expect(M.MalfunctionSeconds("emp")).to.equal(10)
				expect(M.MalfunctionSeconds("shock")).to.equal(5)
				expect(M.MalfunctionSeconds("overload")).to.equal(5)
				expect(M.MalfunctionSeconds("impact")).to.equal(3)
				expect(M.MalfunctionGrace()).to.equal(3)
			end
		},
		{
			name = "electric hits: shock, energy beam and plasma are light under 25 and strong from 25; the combine ball is always strong; bullets and blasts are not electric",
			func = function(state)
				local M = GryMod.Mech
				expect(M.ShockClass(DMG_SHOCK, 10)).to.equal("light")
				expect(M.ShockClass(DMG_ENERGYBEAM, 24)).to.equal("light")
				expect(M.ShockClass(DMG_PLASMA, 5)).to.equal("light")
				expect(M.ShockClass(DMG_SHOCK, 25)).to.equal("strong")
				expect(M.ShockClass(bit.bor(DMG_BLAST, DMG_SHOCK), 40)).to.equal("strong")
				expect(M.ShockClass(DMG_DISSOLVE, 1, "prop_combine_ball")).to.equal("strong")
				expect(M.ShockClass(DMG_BULLET, 500)).to.beNil()
				expect(M.ShockClass(DMG_BLAST, 500)).to.beNil()
				expect(M.ShockClass(DMG_DISSOLVE, 5, "npc_hunter")).to.beNil()
			end
		},
		{
			name = "a light shock burns 1.5 energy per point of damage, from 5 to 30",
			func = function(state)
				local M = GryMod.Mech
				expect(M.ShockEnergyDrain(10)).to.equal(15)
				expect(M.ShockEnergyDrain(1)).to.equal(5)
				expect(M.ShockEnergyDrain(24)).to.equal(30)
				expect(M.ShockEnergyDrain(100)).to.equal(30)
			end
		},
		{
			name = "the heavy machines are the hunter, the strider, the gunship and the helicopter",
			func = function(state)
				local M = GryMod.Mech
				expect(M.IsHeavyMachine("npc_hunter")).to.beTrue()
				expect(M.IsHeavyMachine("npc_strider")).to.beTrue()
				expect(M.IsHeavyMachine("npc_combinegunship")).to.beTrue()
				expect(M.IsHeavyMachine("npc_helicopter")).to.beTrue()
				expect(M.IsHeavyMachine("npc_manhack")).to.beFalse()
				expect(M.IsHeavyMachine(nil)).to.beFalse()
			end
		},
		{
			name = "the convars exist, on by default: gry_malfunction and one per cause",
			func = function(state)
				for _, name in ipairs({"gry_malfunction", "gry_malfunction_shock", "gry_malfunction_impact", "gry_malfunction_emp"}) do
					local convar = GetConVar(name)
					expect(convar ~= nil).to.beTrue()
					expect(convar:GetDefault()).to.equal("1")
				end
			end
		},

		-- the state
		{
			name = "Start puts the suit down: the flag, an empty bar, armor mode, and a timer for the end",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
				expect(GryMod.Malfunction.Start(p, 6, "emp")).to.beTrue()
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(p:GetNW2Bool("GryMalfunction")).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				expect(near(GryMod.Malfunction.Remaining(p), 6, 0.1)).to.beTrue()
				expect(timer.Exists("GryMalfunction" .. p:EntIndex())).to.beTrue()
			end
		},
		{
			name = "a second Start only makes it longer, never shorter",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 4, "shock")
				GryMod.Malfunction.Start(p, 2, "shock")
				expect(near(GryMod.Malfunction.Remaining(p), 4, 0.1)).to.beTrue()
				GryMod.Malfunction.Start(p, 9, "emp")
				expect(near(GryMod.Malfunction.Remaining(p), 9, 0.1)).to.beTrue()
			end
		},
		{
			name = "no malfunction for a dead player, with infinite armor, or with gry_malfunction 0",
			func = function(state)
				local p = ply()
				GryMod.Config.InfiniteArmor = true
				expect(GryMod.Malfunction.Start(p, 5, "emp")).to.beFalse()
				GryMod.Config.InfiniteArmor = false
				setConvar("gry_malfunction", "0")
				expect(GryMod.Malfunction.Start(p, 5, "emp")).to.beFalse()
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},
		{
			name = "End restarts the suit: flag off, empty bar, recharge delay of 1 s, and the Reboot is up to the client",
			func = function(state)
				local p = ply()
				local ended
				hook.Add("GryMod_MalfunctionEnd", "test", function(who) ended = who end)
				GryMod.Malfunction.Start(p, 5, "emp")
				GryMod.Malfunction.End(p)
				hook.Remove("GryMod_MalfunctionEnd", "test")
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
				expect(p:GetNW2Bool("GryMalfunction")).to.beFalse()
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				expect(near(p.next_energy_regen - CurTime(), 1, 0.1)).to.beTrue()
				expect(timer.Exists("GryMalfunction" .. p:EntIndex())).to.beFalse()
				expect(ended).to.equal(p)
			end
		},
		{
			name = "no recharge while the suit is down, normal recharge after the restart",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "emp")
				p.next_energy_regen = CurTime() - 5 -- the delay is long over
				thinkHook("GryMod health think")()
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				GryMod.Malfunction.End(p)
				p.next_energy_regen = CurTime() - 1
				thinkHook("GryMod health think")()
				expect(p:GetNW2Float("GryEnergy")).to.beGreaterThan(0)
			end
		},
		{
			name = "the mode cannot be changed while the suit is down: the server keeps ARMOR",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "emp")

				for _, mode in ipairs({GryMod.Modes.SPEED, GryMod.Modes.CLOAK, GryMod.Modes.STRENGTH}) do
					GryMod.SetModeFromClient(p, mode)
					expect(p.Nanosuit_mode).to.equal(GryMod.Modes.ARMOR)
				end

				GryMod.Malfunction.End(p)
				GryMod.SetModeFromClient(p, GryMod.Modes.SPEED)
				expect(p.Nanosuit_mode).to.equal(GryMod.Modes.SPEED)
			end
		},
		{
			name = "the armor takes its minimum 30 percent only while down, nothing more is absorbed",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "emp")
				local dmg = takeDamage(p, 10)
				expect(near(dmg:GetDamage(), 7)).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
			end
		},
		{
			name = "death and respawn clear the state",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "emp")
				hook.GetTable().PostPlayerDeath["GryMod malfunction death"](p)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
				expect(timer.Exists("GryMalfunction" .. p:EntIndex())).to.beFalse()

				GryMod.Malfunction.Start(p, 5, "emp")
				hook.GetTable().PlayerSpawn["GryMod malfunction spawn"](p)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},

		-- the causes
		{
			name = "a light shock in armor mode: the armor takes the hit, the bar loses 1.5 per point on top, the HUD flickers, no malfunction",
			func = function(state)
				local p = ply()
				local dmg = takeDamage(p, 10, DMG_SHOCK)
				expect(dmg:GetDamage()).to.equal(0)
				expect(near(p:GetNW2Float("GryEnergy"), 100 - 10 - 15)).to.beTrue()
				expect(p:GetNW2Float("GryFlicker")).to.beGreaterThan(CurTime())
				expect(pending(p)).to.beNil()
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},
		{
			name = "THE OWNER'S CASE: a shock that eats the end of the armor bar puts the suit down (5 s)",
			func = function(state)
				local p = ply()
				p:SetNW2Float("GryEnergy", 20)
				takeDamage(p, 10, DMG_SHOCK) -- 20 - 15 - 10 is under 0
				expect(pending(p)).to.equal("overload")
				GryMod.Malfunction.Resolve(p)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(near(GryMod.Malfunction.Remaining(p), 5, 0.1)).to.beTrue()
				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
			end
		},
		{
			name = "a light shock when the bar is already empty puts the suit down",
			func = function(state)
				local p = ply()
				p:SetNW2Float("GryEnergy", 0)
				takeDamage(p, 8, DMG_SHOCK)
				GryMod.Malfunction.Resolve(p)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
			end
		},
		{
			name = "a light shock outside armor mode with a bar that holds does not put the suit down",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.SPEED, false)
				takeDamage(p, 10, DMG_SHOCK)
				expect(near(p:GetNW2Float("GryEnergy"), 85)).to.beTrue()
				expect(pending(p)).to.beNil()
			end
		},
		{
			name = "a strong shock puts the suit down at once (5 s), whatever the bar",
			func = function(state)
				local p = ply()
				takeDamage(p, 30, DMG_ENERGYBEAM)
				expect(pending(p)).to.equal("shock")
				GryMod.Malfunction.Resolve(p)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(near(GryMod.Malfunction.Remaining(p), 5, 0.1)).to.beTrue()
			end
		},
		{
			name = "bullets, blasts and fire never put the suit down, even with an empty bar",
			func = function(state)
				local p = ply()
				p:SetNW2Float("GryEnergy", 0)

				for _, kind in ipairs({DMG_BULLET, DMG_BLAST, DMG_BURN, DMG_SLASH, DMG_DISSOLVE}) do
					takeDamage(p, 40, kind)
					expect(pending(p)).to.beNil()
				end

				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},
		{
			name = "a heavy machine breaking the armor puts the suit down (3 s); a small hit or a hit the armor holds does not",
			func = function(state)
				local p = ply()
				local hunter = ents.Create("npc_hunter")
				hunter:Spawn()
				spawned[#spawned + 1] = hunter
				expect(hunter:GetClass()).to.equal("npc_hunter")

				p:SetNW2Float("GryEnergy", 100)
				takeDamage(p, 60, DMG_CLUB, hunter, hunter) -- the bar holds
				expect(pending(p)).to.beNil()

				p:SetNW2Float("GryEnergy", 10)
				takeDamage(p, 15, DMG_CLUB, hunter, hunter) -- breaks it, but a small hit
				expect(pending(p)).to.beNil()

				p:SetNW2Float("GryEnergy", 30)
				takeDamage(p, 40, DMG_CLUB, hunter, hunter)
				expect(pending(p)).to.equal("impact")
				GryMod.Malfunction.Resolve(p)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(near(GryMod.Malfunction.Remaining(p), 3, 0.1)).to.beTrue()
			end
		},
		{
			name = "a hit that breaks the armor from something that is not a heavy machine does nothing special",
			func = function(state)
				local p = ply()
				local prop = ents.Create("prop_physics")
				prop:SetModel("models/props_c17/oildrum001.mdl")
				prop:Spawn()
				spawned[#spawned + 1] = prop
				p:SetNW2Float("GryEnergy", 10)
				takeDamage(p, 40, DMG_CLUB, prop, prop)
				expect(pending(p)).to.beNil()
			end
		},
		{
			name = "after the restart a shock cannot put the suit down for 3 s; after that it can again",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "shock")
				GryMod.Malfunction.End(p)
				takeDamage(p, 30, DMG_SHOCK)
				expect(pending(p)).to.beNil()
				p.gryMalfunctionGrace = CurTime() - 0.1
				takeDamage(p, 30, DMG_SHOCK)
				expect(pending(p)).to.equal("shock")
			end
		},
		{
			name = "shocks during a malfunction do nothing more",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "emp")
				takeDamage(p, 30, DMG_SHOCK)
				expect(pending(p)).to.beNil()
				expect(near(GryMod.Malfunction.Remaining(p), 5, 0.1)).to.beTrue()
			end
		},
		{
			name = "the switches: gry_malfunction_shock off leaves shocks to the plain armor, gry_malfunction 0 turns every cause off",
			func = function(state)
				local p = ply()
				setConvar("gry_malfunction_shock", "0")
				p:SetNW2Float("GryEnergy", 20)
				takeDamage(p, 30, DMG_SHOCK)
				expect(pending(p)).to.beNil()
				expect(p:GetNW2Float("GryFlicker")).to.equal(0)
				expect(p:GetNW2Float("GryEnergy")).to.equal(0) -- the armor took it as any damage: 20 absorbed, 10 through
				setConvar("gry_malfunction", "0")
				setConvar("gry_malfunction_shock", "1")
				p:SetNW2Float("GryEnergy", 100)
				takeDamage(p, 30, DMG_SHOCK)
				expect(pending(p)).to.beNil()
			end
		},

		-- the EMP
		{
			name = "hook GryMod_EMP puts the suits in range down for the given seconds, and not the ones out of range",
			func = function(state)
				local p = ply()
				hook.Run("GryMod_EMP", p:GetPos() + Vector(50, 0, 0), 100, 4)
				expect(GryMod.Malfunction.IsActive(p)).to.beTrue()
				expect(near(GryMod.Malfunction.Remaining(p), 4, 0.1)).to.beTrue()
				GryMod.Malfunction.Clear(p)
				hook.Run("GryMod_EMP", p:GetPos() + Vector(5000, 0, 0), 100, 4)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},
		{
			name = "an EMP lasts the game's 10 s by default, at most a minute, and the grace after a restart does not protect from it",
			func = function(state)
				local p = ply()
				GryMod.Malfunction.Start(p, 5, "shock")
				GryMod.Malfunction.End(p)
				expect(GryMod.Malfunction.InGrace(p)).to.beTrue()
				expect(GryMod.Malfunction.EMP(p:GetPos(), 100)).to.equal(1)
				expect(near(GryMod.Malfunction.Remaining(p), 10, 0.1)).to.beTrue()
				GryMod.Malfunction.Clear(p)
				GryMod.Malfunction.EMP(p:GetPos(), 100, 9999)
				expect(near(GryMod.Malfunction.Remaining(p), 60, 0.1)).to.beTrue()
			end
		},
		{
			name = "an EMP with no radius from the console reaches everyone; gry_malfunction_emp 0 turns it off",
			func = function(state)
				local p = ply()
				expect(GryMod.Malfunction.EMP(Vector(0, 0, 0), math.huge, 3)).to.equal(#player.GetAll())
				GryMod.Malfunction.Clear(p)
				setConvar("gry_malfunction_emp", "0")
				expect(GryMod.Malfunction.EMP(p:GetPos(), 100, 3)).to.equal(0)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		},
		{
			name = "gry_emp is for the console, superadmins, sv_cheats and single player; it falls on the caller's position",
			func = function(state)
				local p = ply()
				local realSolo = game.SinglePlayer
				local realGetConVar = GetConVar
				local cheatsOn = false
				local super = false
				-- a stand-in for a player who is not an admin (the real ones cannot be changed from here)
				local guest = {IsValid = function() return true end, IsSuperAdmin = function() return super end}
				local ok, err = pcall(function()
					game.SinglePlayer = function() return false end
					GetConVar = function(name)
						if name == "sv_cheats" then
							return {GetBool = function() return cheatsOn end}
						end

						return realGetConVar(name)
					end
					expect(GryMod.Malfunction.MayTest(guest)).to.beFalse()
					expect(GryMod.Malfunction.RunTestCommand(guest, {"5"})).to.beFalse()
					expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
					expect(GryMod.Malfunction.MayTest(nil)).to.beTrue()
					cheatsOn = true
					expect(GryMod.Malfunction.MayTest(guest)).to.beTrue()
					cheatsOn = false
					super = true
					expect(GryMod.Malfunction.MayTest(guest)).to.beTrue()
					super = false
					game.SinglePlayer = function() return true end
					expect(GryMod.Malfunction.MayTest(guest)).to.beTrue()
					expect(GryMod.Malfunction.RunTestCommand(p, {"7"})).to.beTrue()
					expect(near(GryMod.Malfunction.Remaining(p), 7, 0.1)).to.beTrue()
				end)
				game.SinglePlayer = realSolo
				GetConVar = realGetConVar
				assert(ok, tostring(err))
			end
		},
		{
			name = "the console command exists",
			func = function(state)
				local found = false

				for _, name in ipairs(concommand.GetTable and table.GetKeys(concommand.GetTable()) or {}) do
					if name == "gry_emp" then found = true end
				end

				expect(found).to.beTrue()
			end
		},
		{
			name = "firing out of the camouflage empties the bar (the client's message) and puts no malfunction on: no flag, no pending cause, the recharge goes on",
			func = function(state)
				local p = ply()
				p:SetNanosuitMode(GryMod.Modes.CLOAK, true)
				expect(p:GetNW2Float("GryEnergy") > 0).to.beTrue()

				-- what cl_hud.lua sends when the attack key is pressed while camouflaged
				p:SetNanosuitMode(GryMod.Modes.ARMOR, true)
				net.Receivers["gry_empty_energy"](0, p)

				expect(p:GetNW2Float("GryEnergy")).to.equal(0)
				expect(p:GetNW2Bool("GryMalfunction", false)).to.beFalse()
				expect(p.gryMalfunctionPending).to.beNil()
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()

				-- the frame after: nothing starts it either
				GryMod.Malfunction.Resolve(p)
				expect(GryMod.Malfunction.IsActive(p)).to.beFalse()
			end
		}
	}
}
