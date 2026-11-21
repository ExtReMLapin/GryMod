-- Tests of the three server fields of the registry of tracked entities that replaced private tables of the code (GryMod.API.RegisterTracked,
-- docs/entities.md): `heavy` (a machine whose hit breaks the suit down: Mech.IsHeavyMachine, Malfunction.OnDamage), `shock` (an electric
-- inflictor: Mech.ShockClass) and `cloakBlind` (an NPC that keeps a camouflaged player: CloakAI). GLuaTest format, server realm.
-- Nothing here touches the real player or spawns an entity: the entities, the players and the NPCs are tables that answer like
-- the real ones, and every function that is replaced is put back inside a pcall.

local API

local KEYS = {"doc_test_heavy", "doc_test_shock", "doc_test_blind", "doc_test_bad", "doc_test_other"}

-- an entity of the tests: a table that answers like one
local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

-- Runs fn with the given replacements of fields of a table ({{tbl, "name", value}, ...}), puts every original back, then rethrows.
local function with(replacements, fn)
	local originals = {}

	for i, r in ipairs(replacements) do
		originals[i] = r[1][r[2]]
	end

	local ok, err = pcall(function()
		for _, r in ipairs(replacements) do
			r[1][r[2]] = r[3]
		end

		fn()
	end)

	for i, r in ipairs(replacements) do
		r[1][r[2]] = originals[i]
	end

	if not ok then
		error(err, 0)
	end
end

-- A player of the tests (armor mode, energy as given) and a damage that answers like a DamageInfo.
local function fakePlayer(energy)
	local p = {Nanosuit_mode = GryMod.Modes.ARMOR}
	local nw = {GryEnergy = energy, GryDisabled = false}

	p.IsValid = function() return true end
	p.Alive = function() return true end
	p.GetNW2Bool = function(_, key, default) if nw[key] ~= nil then return nw[key] end return default end
	p.GetNW2Float = function(_, key) return nw[key] or 0 end
	p.SetNW2Float = function(_, key, value) nw[key] = value end

	return p
end

local function fakeDamage(amount, damageType, attacker, inflictor)
	return {
		GetDamage = function() return amount end,
		GetDamageType = function() return damageType end,
		GetAttacker = function() return attacker end,
		GetInflictor = function() return inflictor end
	}
end

-- OnDamage with the switches on and no timer: what the hit asked for (`gryMalfunctionPending`), or nil.
local function asked(p, dmg)
	local Malfunction = GryMod.Malfunction
	local config = GryMod.Config

	with({
		{Malfunction, "Enabled", function() return true end},
		{timer, "Simple", function() end},
		{config, "InfiniteArmor", false}
	}, function()
		Malfunction.OnDamage(p, dmg)
	end)

	return p.gryMalfunctionPending
end

return {
	groupName = "GryMod tracked registry: the heavy, shock and cloakBlind fields (server)",
	beforeEach = function()
		API = GryMod.API
	end,
	afterEach = function()
		for _, key in ipairs(KEYS) do
			API.UnregisterTracked(key)
		end
	end,
	cases = {
		-- the validation
		{
			name = "heavy and cloakBlind are booleans, shock is \"light\" or \"strong\": anything else is refused with the name of the field, never an error",
			func = function()
				for _, field in ipairs({"heavy", "cloakBlind"}) do
					for _, bad in ipairs({"yes", 1, {}, 0}) do
						local ok, reason = API.RegisterTracked("doc_test_bad", {class = "doc_test_npc", [field] = bad})
						expect(ok).to.beFalse()
						expect(string.find(reason, "invalid " .. field, 1, true) ~= nil).to.beTrue()
					end
				end

				for _, bad in ipairs({"medium", "", true, 5, {}}) do
					local ok, reason = API.RegisterTracked("doc_test_bad", {class = "doc_test_npc", shock = bad})
					expect(ok).to.beFalse()
					expect(string.find(reason, "invalid shock", 1, true) ~= nil).to.beTrue()
				end

				expect(API.GetTracked(ent("doc_test_npc"))).to.beNil() -- a refused entry is not stored

				expect(API.RegisterTracked("doc_test_heavy", {class = "doc_test_npc", heavy = true, cloakBlind = false, shock = "light"})).to.beTrue()

				local entry = API.GetTracked(ent("doc_test_npc"))
				expect(entry.heavy).to.beTrue()
				expect(entry.cloakBlind).to.beFalse()
				expect(entry.shock).to.equal("light")
			end
		},
		{
			name = "a field that is not given stays nil, and a cloakBlind needs a class (the cloak looks for these NPCs by class)",
			func = function()
				expect(API.RegisterTracked("doc_test_heavy", {class = "doc_test_npc", radar = "always"})).to.beTrue()

				local entry = API.GetTracked(ent("doc_test_npc"))
				expect(entry.heavy).to.beNil()
				expect(entry.shock).to.beNil()
				expect(entry.cloakBlind).to.beNil()

				local ok, reason = API.RegisterTracked("doc_test_bad", {base = "doc_test_base", cloakBlind = true})
				expect(ok).to.beFalse()
				expect(string.find(reason, "class", 1, true) ~= nil).to.beTrue()

				ok, reason = API.RegisterTracked("doc_test_bad", {match = function() return true end, cloakBlind = true})
				expect(ok).to.beFalse()

				expect(API.RegisterTracked("doc_test_bad", {base = "doc_test_base", heavy = true, shock = "strong"})).to.beTrue()
			end
		},

		-- the stock entries
		{
			name = "the stock entries carry the old private tables: heavy for the hunter, strider, gunship and helicopter; shock strong for the energy ball; cloakBlind for the strider, hunter and manhack",
			func = function()
				for _, class in ipairs({"npc_hunter", "npc_strider", "npc_combinegunship", "npc_helicopter"}) do
					expect(API.GetTracked(ent(class)).heavy).to.beTrue()
				end

				for _, class in ipairs({"npc_manhack", "npc_cscanner", "npc_clawscanner", "npc_combinedropship", "npc_turret_floor", "npc_antlionguard"}) do
					expect(API.GetTracked(ent(class)).heavy).toNot.beTrue()
				end

				expect(API.GetTracked(ent("prop_combine_ball")).shock).to.equal("strong")
				expect(API.GetTracked(ent("npc_strider")).shock).to.beNil()

				for _, class in ipairs({"npc_strider", "npc_hunter", "npc_manhack"}) do
					expect(API.GetTracked(ent(class)).cloakBlind).to.beTrue()
				end

				for _, class in ipairs({"npc_combinegunship", "npc_helicopter", "npc_cscanner", "npc_rollermine"}) do
					expect(API.GetTracked(ent(class)).cloakBlind).toNot.beTrue()
				end
			end
		},
		{
			name = "the stock entries keep what they were for the radar: the gunship and the helicopter flying, the manhack flying, the strider and hunter big machines",
			func = function()
				for _, class in ipairs({"npc_combinegunship", "npc_helicopter", "npc_manhack"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.type).to.equal(2)
					expect(entry.size).to.beNil()
					expect(entry.scan).to.beTrue()
					expect(entry.radar).to.beNil()
				end

				for _, class in ipairs({"npc_strider", "npc_hunter"}) do
					local entry = API.GetTracked(ent(class))
					expect(entry.type).to.equal(3)
					expect(entry.size).to.equal("big")
				end
			end
		},

		-- heavy
		{
			name = "heavy: an entity another addon registers as heavy is one, by class name, by entity and by base; one that is not registered, or not heavy, is not",
			func = function()
				local Mech = GryMod.Mech

				expect(Mech.IsHeavyMachine("doc_test_tank")).to.beFalse()
				expect(Mech.IsHeavyMachine(ent("doc_test_tank"))).to.beFalse()

				expect(API.RegisterTracked("doc_test_heavy", {class = "doc_test_tank", heavy = true})).to.beTrue()
				expect(API.RegisterTracked("doc_test_other", {class = "doc_test_scout", radar = "always"})).to.beTrue()

				expect(Mech.IsHeavyMachine("doc_test_tank")).to.beTrue()
				expect(Mech.IsHeavyMachine(ent("doc_test_tank"))).to.beTrue()
				expect(Mech.IsHeavyMachine("doc_test_scout")).to.beFalse()
				expect(Mech.IsHeavyMachine(ent("doc_test_scout"))).to.beFalse()

				expect(API.RegisterTracked("doc_test_blind", {base = "doc_test_base", heavy = true})).to.beTrue() -- heavy needs no class
				expect(Mech.IsHeavyMachine(ent("doc_test_child", {Base = "doc_test_base"}))).to.beTrue()

				expect(Mech.IsHeavyMachine(nil)).to.beFalse()
				expect(Mech.IsHeavyMachine(NULL)).to.beFalse()
				expect(Mech.IsHeavyMachine(42)).to.beFalse()
				expect(Mech.IsHeavyMachine({})).to.beFalse()

				API.UnregisterTracked("doc_test_heavy")
				expect(Mech.IsHeavyMachine("doc_test_tank")).to.beFalse()
			end
		},
		{
			name = "heavy end to end: a hit from a registered heavy machine that breaks the armor puts the suit down (attacker or inflictor); a hit from one that is not heavy does not",
			func = function()
				expect(API.RegisterTracked("doc_test_heavy", {class = "doc_test_tank", heavy = true})).to.beTrue()
				expect(API.RegisterTracked("doc_test_other", {class = "doc_test_scout"})).to.beTrue()

				local tank, scout = ent("doc_test_tank"), ent("doc_test_scout")
				local impact = GryMod.Mech.HeavyImpactDamage()

				expect(asked(fakePlayer(10), fakeDamage(impact, DMG_CLUB, tank, tank))).to.equal("impact")
				expect(asked(fakePlayer(10), fakeDamage(impact, DMG_CLUB, tank, nil))).to.equal("impact")
				expect(asked(fakePlayer(10), fakeDamage(impact, DMG_CLUB, nil, tank))).to.equal("impact")

				expect(asked(fakePlayer(10), fakeDamage(impact, DMG_CLUB, scout, scout))).to.beNil()
				expect(asked(fakePlayer(10), fakeDamage(impact, DMG_CLUB, nil, nil))).to.beNil()
				-- the armor holds: more energy than the damage
				expect(asked(fakePlayer(100), fakeDamage(impact, DMG_CLUB, tank, tank))).to.beNil()
			end
		},

		-- shock
		{
			name = "shock: an inflictor registered with shock \"strong\" or \"light\" gives that class whatever the damage type, by class name and by entity; the electric damage types still work without it",
			func = function()
				local Mech = GryMod.Mech

				expect(Mech.ShockClass(DMG_BULLET, 1, "doc_test_zap")).to.beNil()

				expect(API.RegisterTracked("doc_test_shock", {class = "doc_test_zap", shock = "strong"})).to.beTrue()
				expect(API.RegisterTracked("doc_test_other", {class = "doc_test_spark", shock = "light"})).to.beTrue()

				expect(Mech.ShockClass(DMG_BULLET, 1, "doc_test_zap")).to.equal("strong")
				expect(Mech.ShockClass(DMG_DISSOLVE, 1, ent("doc_test_zap"))).to.equal("strong")
				expect(Mech.ShockClass(DMG_BULLET, 500, "doc_test_spark")).to.equal("light")
				expect(Mech.ShockClass(DMG_BULLET, 500, ent("doc_test_spark"))).to.equal("light")

				expect(Mech.ShockClass(DMG_BULLET, 500, "doc_test_plain")).to.beNil()
				expect(Mech.ShockClass(DMG_BULLET, 500, ent("doc_test_plain"))).to.beNil()
				expect(Mech.ShockClass(DMG_BULLET, 500, nil)).to.beNil()
				expect(Mech.ShockClass(DMG_BULLET, 500, NULL)).to.beNil()
				expect(Mech.ShockClass(DMG_SHOCK, 30, ent("doc_test_plain"))).to.equal("strong")
				expect(Mech.ShockClass(DMG_SHOCK, 10, nil)).to.equal("light")

				-- the stock ball, by name and by entity, as before
				expect(Mech.ShockClass(DMG_DISSOLVE, 1, "prop_combine_ball")).to.equal("strong")
				expect(Mech.ShockClass(DMG_DISSOLVE, 1, ent("prop_combine_ball"))).to.equal("strong")
				expect(Mech.ShockClass(DMG_DISSOLVE, 5, "npc_hunter")).to.beNil()

				API.UnregisterTracked("doc_test_shock")
				expect(Mech.ShockClass(DMG_BULLET, 1, "doc_test_zap")).to.beNil()
			end
		},
		{
			name = "shock end to end: a strong inflictor puts the suit down at once, a light one drains the energy; an unregistered inflictor does neither",
			func = function()
				expect(API.RegisterTracked("doc_test_shock", {class = "doc_test_zap", shock = "strong"})).to.beTrue()
				expect(API.RegisterTracked("doc_test_other", {class = "doc_test_spark", shock = "light"})).to.beTrue()

				local zap, spark, plain = ent("doc_test_zap"), ent("doc_test_spark"), ent("doc_test_plain")

				expect(asked(fakePlayer(100), fakeDamage(5, DMG_BULLET, zap, zap))).to.equal("shock")

				local p = fakePlayer(100)
				expect(asked(p, fakeDamage(10, DMG_BULLET, spark, spark))).to.beNil()
				expect(p:GetNW2Float("GryEnergy")).to.equal(100 - GryMod.Mech.ShockEnergyDrain(10))

				p = fakePlayer(100)
				expect(asked(p, fakeDamage(10, DMG_BULLET, plain, plain))).to.beNil()
				expect(p:GetNW2Float("GryEnergy")).to.equal(100)
			end
		},

		-- cloakBlind
		{
			name = "cloakBlind: the NPCs of the classes the registry names are hidden from a camouflaged player (the three stock ones, and a class another addon registers), the other classes are not searched, and never every entity",
			func = function()
				local CloakAI = GryMod.CloakAI

				local cloaked = {
					IsValid = function() return true end,
					Alive = function() return true end,
					Nanosuit_mode = GryMod.Modes.CLOAK
				}

				local function npc()
					local n = {disposition = D_HT, relations = 0}
					n.Disposition = function() return n.disposition end
					n.AddEntityRelationship = function(_, _, disposition) n.disposition = disposition n.relations = n.relations + 1 end
					n.GetEnemy = function() return NULL end
					n.IsValid = function() return true end

					return n
				end

				local blind, plain = npc(), npc()
				local searched, all = {}, 0
				local convar = GetConVar("gry_cloak_ai")
				local saved = convar:GetString()

				expect(API.RegisterTracked("doc_test_blind", {class = "doc_test_blinder", cloakBlind = true})).to.beTrue()
				expect(API.RegisterTracked("doc_test_other", {class = "doc_test_seer", radar = "always"})).to.beTrue()

				local ok, err = pcall(function()
					convar:SetString("1")

					with({
						{player, "GetAll", function() return {cloaked} end},
						{ents, "GetAll", function() all = all + 1 return {} end},
						{ents, "FindByClass", function(class)
							searched[#searched + 1] = class

							if class == "doc_test_blinder" then return {blind} end
							if class == "doc_test_seer" then return {plain} end

							return {}
						end},
						{timer, "Create", function() end},
						{timer, "Remove", function() end}
					}, function()
						CloakAI.Tick()
					end)
				end)

				convar:SetString(saved)
				if not ok then error(err, 0) end

				expect(all).to.equal(0)
				expect(blind.disposition).to.equal(D_NU)
				expect(plain.disposition).to.equal(D_HT)
				expect(plain.relations).to.equal(0)

				for _, class in ipairs({"npc_strider", "npc_hunter", "npc_manhack", "doc_test_blinder"}) do
					expect(table.HasValue(searched, class)).to.beTrue()
				end

				expect(table.HasValue(searched, "doc_test_seer")).to.beFalse()
				expect(table.HasValue(searched, "npc_zombie")).to.beFalse()

				local seen = {}

				for _, class in ipairs(searched) do
					expect(seen[class]).to.beNil() -- a class is searched once
					seen[class] = true
				end
			end
		},
		{
			name = "cloakBlind: removing the entry stops the search at once; an entry registered later for the same class without it (higher priority) takes the class off the list; CloakAI.Classes still adds classes",
			func = function()
				local CloakAI = GryMod.CloakAI
				local convar = GetConVar("gry_cloak_ai")
				local saved = convar:GetString()
				local cloaked = {
					IsValid = function() return true end,
					Alive = function() return true end,
					Nanosuit_mode = GryMod.Modes.CLOAK
				}

				local function searchedClasses()
					local searched = {}

					with({
						{player, "GetAll", function() return {cloaked} end},
						{ents, "FindByClass", function(class) searched[#searched + 1] = class return {} end},
						{timer, "Create", function() end},
						{timer, "Remove", function() end}
					}, function()
						CloakAI.Tick()
					end)

					return searched
				end

				local extra = CloakAI.Classes
				local ok, err = pcall(function()
					convar:SetString("1")

					expect(API.RegisterTracked("doc_test_blind", {class = "doc_test_blinder", cloakBlind = true})).to.beTrue()
					expect(table.HasValue(searchedClasses(), "doc_test_blinder")).to.beTrue()

					API.UnregisterTracked("doc_test_blind")
					expect(table.HasValue(searchedClasses(), "doc_test_blinder")).to.beFalse()

					-- an addon that registers the strider again, above the stock entry and without cloakBlind, turns it off for that class
					expect(API.RegisterTracked("doc_test_other", {class = "npc_strider", priority = 50})).to.beTrue()
					expect(table.HasValue(searchedClasses(), "npc_strider")).to.beFalse()
					expect(table.HasValue(searchedClasses(), "npc_hunter")).to.beTrue()
					API.UnregisterTracked("doc_test_other")
					expect(table.HasValue(searchedClasses(), "npc_strider")).to.beTrue()

					-- the public list of the older code still works
					CloakAI.Classes = {"doc_test_legacy"}
					expect(table.HasValue(searchedClasses(), "doc_test_legacy")).to.beTrue()
				end)

				CloakAI.Classes = extra
				convar:SetString(saved)
				if not ok then error(err, 0) end
			end
		},
		{
			name = "TrackedClasses lists the classes of the entries with a field: the first entry that names the class decides, a list that is kept, nothing for an unknown field",
			func = function()
				expect(isfunction(API.TrackedClasses)).to.beTrue()
				expect(API.RegisterTracked("doc_test_blind", {class = {"doc_test_blinder", "doc_test_blinder2"}, cloakBlind = true})).to.beTrue()

				local list = API.TrackedClasses("cloakBlind")
				expect(table.HasValue(list, "doc_test_blinder")).to.beTrue()
				expect(table.HasValue(list, "doc_test_blinder2")).to.beTrue()
				expect(table.HasValue(list, "npc_strider")).to.beTrue()
				expect(API.TrackedClasses("heavy")).toNot.equal(list)
				expect(table.HasValue(API.TrackedClasses("heavy"), "npc_helicopter")).to.beTrue()
				expect(table.HasValue(API.TrackedClasses("heavy"), "doc_test_blinder")).to.beFalse()
				expect(#API.TrackedClasses("doc_test_nothing")).to.equal(0)
				expect(#API.TrackedClasses(nil)).to.equal(0)
			end
		}
	}
}
