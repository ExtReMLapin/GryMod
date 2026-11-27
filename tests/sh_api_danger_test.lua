-- Tests of the danger entries of the tracked registry that name their entities by a base or a match function, and of the danger's `warnFor` field
-- (GryMod.API.RegisterTracked with `danger`, GryMod.API.GetDanger, lua/grymod/sh_api_tracked.lua), GLuaTest format, runs in the server AND in the client realm
-- (SHARED-DANGER-1). Before, a danger needed a class: a projectile of a vehicle weapon base (LVS, Glide, a VJ Base grenade) is made of many classes, and is found by the
-- base they share or by a function that knows them. Each case names the production change whose absence makes it fail.

local API
local KEYS = {"t_dng_a", "t_dng_b", "t_dng_c"}
local realIsBasedOn

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

return {
	groupName = "GryMod extension API: danger by base or match (shared)",
	beforeEach = function()
		API = GryMod.API
		realIsBasedOn = scripted_ents.IsBasedOn
	end,
	afterEach = function()
		scripted_ents.IsBasedOn = realIsBasedOn

		for _, key in ipairs(KEYS) do
			API.UnregisterTracked(key)
			API.SafeCallReset("tracked:" .. key .. "/match")
			API.SafeCallReset("tracked:" .. key .. "/warnfor")
		end
	end,
	cases = {
		{
			-- fails when a danger with a base only is refused, or when GetDanger(entity) only knows classes
			name = "a danger with a base: GetDanger(entity) finds an entity of that base (its Base field, or a class built on it), and not an entity of another; a class name finds nothing",
			func = function()
				scripted_ents.IsBasedOn = function(class, base) return class == "t_dng_child" and base == "t_dng_base" end

				expect(API.RegisterTracked("t_dng_a", {base = "t_dng_base", danger = {label = "MISSILE"}})).to.beTrue()

				expect(API.GetDanger(ent("t_dng_child")).key).to.equal("t_dng_a")
				expect(API.GetDanger(ent("t_dng_other", {Base = "t_dng_base"})).key).to.equal("t_dng_a")
				expect(API.GetDanger(ent("t_dng_other"))).to.beNil()
				expect(API.GetDanger("t_dng_child")).to.beNil()
			end
		},
		{
			-- fails when a match function is not asked for the entity of GetDanger, or its answer is not read as true only
			name = "a danger with a match function: GetDanger(entity) finds the entities it says true for, once an entity is found it is kept (the function is not asked again)",
			func = function()
				local asked = 0
				local mine, other = ent("t_dng_x", {mark = true}), ent("t_dng_y")

				expect(API.RegisterTracked("t_dng_a", {match = function(e) asked = asked + 1 return e.mark == true end, danger = {label = "FUNCTION"}})).to.beTrue()

				expect(API.GetDanger(other)).to.beNil()
				expect(API.GetDanger(mine).key).to.equal("t_dng_a")
				expect(API.GetDanger(mine).key).to.equal("t_dng_a")
				expect(API.GetDanger(mine).key).to.equal("t_dng_a")
				expect(asked).to.equal(2) -- the other once, mine once

				-- a change of the registry drops what was kept
				API.RegisterTracked("t_dng_a", {match = function() return false end, danger = {label = "FUNCTION"}})
				expect(API.GetDanger(mine)).to.beNil()
			end
		},
		{
			-- fails when the match function of a danger runs outside SafeCall (an error would reach the game's hook) or is never switched off
			name = "a match function that raises an error is no danger, and is switched off after five errors in a row",
			func = function()
				local calls = 0

				expect(API.RegisterTracked("t_dng_a", {match = function() calls = calls + 1 error("broken match") end, danger = {}})).to.beTrue()

				for _ = 1, 8 do
					expect(API.GetDanger(ent("t_dng_x"))).to.beNil()
				end

				expect(calls).to.equal(5)
			end
		},
		{
			-- fails when the entries are not read in the order of the registry (priority, then registration) whatever they match on
			name = "the first entry that matches wins, in the order of the registry: a higher priority match function beats a class entry; a class entry without danger is skipped",
			func = function()
				API.RegisterTracked("t_dng_a", {class = "t_dng_c1", radar = "always"}) -- names the class but is no danger
				API.RegisterTracked("t_dng_b", {class = "t_dng_c1", danger = {label = "CLASS"}})
				API.RegisterTracked("t_dng_c", {match = function() return true end, priority = 5, danger = {label = "FUNCTION"}})

				expect(API.GetDanger(ent("t_dng_c1")).key).to.equal("t_dng_c")
				API.UnregisterTracked("t_dng_c")
				expect(API.GetDanger(ent("t_dng_c1")).key).to.equal("t_dng_b")
				expect(API.GetDanger("t_dng_c1").key).to.equal("t_dng_b") -- the class form is as before
			end
		},
		{
			-- fails when a caller cannot tell whether a danger needs the entity (the client then judges an entity that has no answer yet again one frame later)
			name = "DangerNeedsEntity: false with class dangers only, true while an entry with a base or a match function has a danger",
			func = function()
				-- the adapters of the game (LVS, Glide, GB5...) may already have entries by base or by function: the case compares with what was there before
				local before = API.DangerNeedsEntity()

				API.RegisterTracked("t_dng_a", {class = "t_dng_c1", danger = {}})
				expect(API.DangerNeedsEntity()).to.equal(before) -- a class danger changes nothing

				API.RegisterTracked("t_dng_b", {base = "t_dng_base", danger = {}})
				expect(API.DangerNeedsEntity()).to.beTrue()

				API.UnregisterTracked("t_dng_b")
				expect(API.DangerNeedsEntity()).to.equal(before)
			end
		},
		{
			-- fails when a warnFor that is not a function is accepted (the warning would call it), or when a function is refused
			name = "danger.warnFor must be a function (invalid danger.warnFor otherwise) and is kept in the entry",
			func = function()
				local fn = function() return true end
				local ok, reason = API.RegisterTracked("t_dng_a", {class = "t_dng_c1", danger = {warnFor = "yes"}})

				expect(ok).to.beFalse()
				expect(string.find(reason, "danger.warnFor", 1, true) ~= nil).to.beTrue()

				expect(API.RegisterTracked("t_dng_a", {class = "t_dng_c1", danger = {warnFor = fn}})).to.beTrue()
				expect(API.GetDanger("t_dng_c1").danger.warnFor).to.equal(fn)
				expect(API.GetDanger("t_dng_c1").warnId).to.equal("tracked:t_dng_a/warnfor")
			end
		}
	}
}
