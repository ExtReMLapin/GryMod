-- Tests of the JMod patch, the shared part (lua/grymod/compat/tools/sh_jmod.lua), GLuaTest format, runs in the server AND in the client realm. JMod was not installed when this was
-- written: the cases use stand-ins for its entities with the fields the patch reads, taken from its public code (github.com/Jackarunda/gmod, lua/entities/): the networked `State`
-- (NetworkVar Int), the constants of the grenades in autorun/jmod_init.lua (EZ_STATE_ARMED 4) and the LOCAL constants of the bombs (ARMED 1), the rockets (LAUNCHED 2) and the mines
-- (WARNING 3), `JMod.GetEZowner`. Each case names the change whose absence makes it fail.

local API
local realJMod

local function ent(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetSpawnFlags = function() return 0 end,
		GetVelocity = function() return Vector(0, 0, 0) end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

-- an entity of `class` built on `base`, in `state`
local function jmod(class, base, state, fields)
	local e = ent(class, fields)

	e.Base = base

	e.GetState = function() return state end

	return e
end

return {
	groupName = "GryMod compat: JMod (shared)",
	beforeEach = function()
		API = GryMod.API
		realJMod = JMod
		JMod = {EZ_STATE_ARMED = 4, GetEZowner = function(e) return e.EZowner end}
		include("grymod/compat/tools/sh_jmod.lua")
	end,
	afterEach = function()
		JMod = realJMod
	end,
	cases = {
		{
			-- fails when the grenades of JMod (the entities built on its grenade base) are not dangers, or when the fuse is not what arms them
			name = "a grenade of JMod warns when its fuse runs (state ARMED, 4), not in the hand with the pin out (PRIMED, 2) nor at rest",
			func = function()
				local armed = jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", 4)
				local entry = API.GetDanger(armed)

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed(armed)).to.beTrue()
				expect(entry.danger.armed(jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", 2))).to.beFalse()
				expect(entry.danger.armed(jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", 0))).to.beFalse()
			end
		},
		{
			-- fails when the grenade states are read with another table's constants (the bombs' ARMED is 1, the grenades' is 4)
			name = "a bomb warns while it falls armed (its own ARMED is 1) and not when it lies armed or is off",
			func = function()
				local falling = jmod("ent_jack_gmod_ezhebomb", "ent_jack_gmod_ezbomb", 1, {GetVelocity = function() return Vector(0, 0, -500) end})
				local lying = jmod("ent_jack_gmod_ezhebomb", "ent_jack_gmod_ezbomb", 1)
				local off = jmod("ent_jack_gmod_ezhebomb", "ent_jack_gmod_ezbomb", 0, {GetVelocity = function() return Vector(0, 0, -500) end})
				local entry = API.GetDanger(falling)

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed(falling)).to.beTrue()
				expect(entry.danger.armed(lying)).to.beFalse()
				expect(entry.danger.armed(off)).to.beFalse()
			end
		},
		{
			-- fails when a rocket that stands on its launcher warns, or one the player fires warns him
			name = "a rocket warns once launched (LAUNCHED, 2) and never warns the player who fired it",
			func = function()
				local flying = jmod("ent_jack_gmod_ezheatrocket", "ent_jack_gmod_ezherocket", 2)
				local entry = API.GetDanger(flying)

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed(flying)).to.beTrue()
				expect(entry.danger.armed(jmod("ent_jack_gmod_ezheatrocket", "ent_jack_gmod_ezherocket", 1))).to.beFalse()
				expect(entry.danger.ownMissile).to.beTrue()
			end
		},
		{
			-- fails when a mine that only waits for somebody warns (it would warn all the time), or when the one that was triggered does not
			name = "a mine warns when it has been triggered (WARNING, 3), not while it waits armed (2) or is off",
			func = function()
				local entry = API.GetDanger(ent("ent_jack_gmod_ezlandmine"))

				expect(entry ~= nil).to.beTrue()

				for _, class in ipairs({"ent_jack_gmod_ezlandmine", "ent_jack_gmod_ezatmine", "ent_jack_gmod_ezwarmine"}) do
					expect(API.GetDanger(ent(class)).danger.armed(jmod(class, nil, 3))).to.beTrue()
					expect(API.GetDanger(ent(class)).danger.armed(jmod(class, nil, 2))).to.beFalse()
					expect(API.GetDanger(ent(class)).danger.armed(jmod(class, nil, 0))).to.beFalse()
				end
			end
		},
		{
			-- fails when the owner is read from the engine's owner (JMod does not use it) and not from JMod's own, or when the world counts as a player
			name = "the owner of a JMod explosive is JMod.GetEZowner (a player), nothing for the world or when JMod has no such function",
			func = function()
				local ply = {IsValid = function() return true end, IsPlayer = function() return true end}
				local world = {IsValid = function() return true end, IsPlayer = function() return false end}
				local entry = API.GetDanger(ent("ent_jack_gmod_ezlandmine"))

				expect(entry.danger.ownerOf(ent("ent_jack_gmod_ezlandmine", {EZowner = ply}))).to.equal(ply)
				expect(entry.danger.ownerOf(ent("ent_jack_gmod_ezlandmine", {EZowner = world}))).to.beNil()

				JMod.GetEZowner = nil

				expect(entry.danger.ownerOf(ent("ent_jack_gmod_ezlandmine", {EZowner = ply}))).to.equal(ply)
				expect(entry.danger.ownerOf(ent("ent_jack_gmod_ezlandmine"))).to.beNil()
			end
		},
		{
			-- fails when the mines are not radar contacts once scanned, or when the ones the player laid are hostile to him
			name = "a mine is a radar contact once scanned, an ally when the player laid it and hostile otherwise",
			func = function()
				local ply = {IsValid = function() return true end, IsPlayer = function() return true end}
				local other = {IsValid = function() return true end, IsPlayer = function() return true end}
				local entry = API.GetTrackedByClass("ent_jack_gmod_ezlandmine")

				expect(entry ~= nil).to.beTrue()
				expect(entry.radar).to.equal("scan")
				expect(entry.relation(ply, ent("ent_jack_gmod_ezlandmine", {EZowner = ply}))).to.equal("ally")
				expect(entry.relation(ply, ent("ent_jack_gmod_ezlandmine", {EZowner = other}))).to.equal("hostile")
				expect(entry.relation(ply, ent("ent_jack_gmod_ezlandmine"))).to.equal("hostile")
			end
		},
		{
			-- fails when a grenade of JMod has no prompt, or one that cannot be taken (broken, state -1: Use returns at once) shows it
			name = "a grenade has the PICK UP prompt, with no size limit, and none once it is broken",
			func = function()
				local good = jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", 0)
				local entry = API.GetUsable(good)

				expect(entry ~= nil).to.beTrue()
				expect(entry.icon).to.equal("grab")
				expect(entry.nolimits).to.beTrue()
				expect(API.UsableBusy(good, nil, entry)).to.beFalse()
				expect(API.UsableBusy(jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", -1), nil, entry)).to.beTrue()
			end
		},
		{
			-- fails when the bomb's text does not follow its state (a double tap arms it, another disarms it)
			name = "a bomb's prompt says ARM when it is off and DISARM when it is armed",
			func = function()
				local off = jmod("ent_jack_gmod_ezhebomb", "ent_jack_gmod_ezbomb", 0)
				local on = jmod("ent_jack_gmod_ezhebomb", "ent_jack_gmod_ezbomb", 1)

				expect(API.UsableText(off, nil)).to.equal("ARM")
				expect(API.UsableText(on, nil)).to.equal("DISARM")
			end
		},
		{
			-- fails when the machines, the mines or the resource boxes are left without a prompt, or when the pieces of another addon get one
			name = "the machines, the mines and the resource boxes have a prompt, and what is not JMod's has none",
			func = function()
				expect(API.GetUsable(jmod("ent_jack_gmod_ezfabricator", "ent_jack_gmod_ezmachine_base", 0)) ~= nil).to.beTrue()
				expect(API.GetUsable(ent("ent_jack_gmod_ezlandmine")) ~= nil).to.beTrue()
				expect(API.GetUsable(jmod("ent_jack_gmod_ezsteel", "ent_jack_gmod_ezresource", 0)).icon).to.equal("grab")
				expect(API.GetUsable(ent("some_other_addon_entity"))).to.beNil()
				expect(API.GetDanger(ent("some_other_addon_entity"))).to.beNil()
			end
		},
		{
			-- fails when the entries use a match function (asked about every entity of a class no entry took) instead of bases and classes
			name = "no entry uses a match function",
			func = function()
				expect(API.GetUsable(ent("ent_jack_gmod_ezlandmine")).match).to.beNil()
				expect(API.GetDanger(ent("ent_jack_gmod_ezlandmine")).match).to.beNil()
				expect(API.GetDanger(jmod("ent_jack_gmod_ezfragnade", "ent_jack_gmod_ezgrenade", 4)).match).to.beNil()
			end
		},
		{
			-- fails when a reader raises an error for an entity that has no State (a version of JMod, a stand-in): five errors in a row switch a reader off
			name = "the readers answer false for an entity that has no state, and nothing is raised",
			func = function()
				local grenade = ent("ent_jack_gmod_ezfragnade", {Base = "ent_jack_gmod_ezgrenade"})
				local entry = API.GetDanger(grenade)

				expect(entry.danger.armed(grenade)).to.beFalse()
				expect(API.UsableBusy(grenade, nil, API.GetUsable(grenade))).to.beFalse()
			end
		}
	}
}
