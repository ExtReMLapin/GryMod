-- Tests of the usable filters (GryMod.API.AddUsableFilter / RemoveUsableFilter / UsableFiltered, lua/grymod/client/cl_api.lua, read by GryMod.FlashCrosshair.UsableFor, which
-- opens the crosshair's "usable" state and the use prompt), GLuaTest format, client realm (SHARED-USABLE-FILTER-1). The registry of usable entities says what the use key does;
-- it does not know who may use it (a prop protection, a locked vehicle). A filter answers false for an entity this player may not use: no prompt. Any other answer is no opinion.
-- Each case names the production change whose absence makes it fail.

local API = GryMod.API
local ids

local function filter(id, fn)
	ids[#ids + 1] = id

	return API.AddUsableFilter(id, fn)
end

-- an entity of the tests: a button, which the registry says is usable
local function button()
	return {IsValid = function() return true end, GetClass = function() return "func_button" end, IsWeapon = function() return false end}
end

local player = {HasWeapon = function() return false end}

return {
	groupName = "GryMod extension API: usable filters (client)",
	beforeEach = function()
		ids = {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemoveUsableFilter(id)
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad id or function is accepted, or the feature is not announced
			name = "AddUsableFilter takes a text id and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("usablefilter")).to.beTrue()
				expect(filter("test.a", function() end)).to.beTrue()
				expect(API.AddUsableFilter("", function() end)).to.beFalse()
				expect(API.AddUsableFilter(5, function() end)).to.beFalse()
				expect(API.AddUsableFilter("test.b", "no")).to.beFalse()
				expect(API.AddUsableFilter("test.b")).to.beFalse()
			end
		},
		{
			-- fails when the prompt still shows for an entity a filter refuses, when the filter is not asked (ent, ply), or when Remove does not bring the prompt back
			name = "UsableFor: a filter that answers false takes the prompt away (it is asked with the entity and the player); nil, true or anything else is no opinion; Remove brings it back",
			func = function()
				local C = GryMod.FlashCrosshair
				local ent = button()
				local seenEnt, seenPly

				expect(C.UsableFor(ent, player)).to.equal(1)

				filter("test.veto", function(e, p) seenEnt, seenPly = e, p return false end)
				expect(C.UsableFor(ent, player)).to.equal(0)
				expect(seenEnt).to.equal(ent)
				expect(seenPly).to.equal(player)

				for _, answer in ipairs({"nil", true, 0, "no"}) do
					filter("test.veto", function() if answer ~= "nil" then return answer end end)
					expect(C.UsableFor(ent, player)).to.equal(1)
				end

				filter("test.veto", function() return false end)
				expect(C.UsableFor(ent, player)).to.equal(0)
				expect(API.RemoveUsableFilter("test.veto")).to.beTrue()
				expect(API.RemoveUsableFilter("test.veto")).to.beFalse()
				expect(C.UsableFor(ent, player)).to.equal(1)
			end
		},
		{
			-- fails when a filter that is asked about something the registry does not call usable changes anything, or is asked at all (it would run for every entity aimed at)
			name = "a filter is asked only for what the registry calls usable: nothing aimed at that is not usable runs it",
			func = function()
				local C = GryMod.FlashCrosshair
				local asked = 0
				local wall = {IsValid = function() return true end, GetClass = function() return "func_brush" end, IsWeapon = function() return false end}

				filter("test.count", function() asked = asked + 1 return false end)

				expect(C.UsableFor(wall, player)).to.equal(0)
				expect(asked).to.equal(0)
				expect(C.UsableFor(button(), player)).to.equal(0)
				expect(asked).to.equal(1)
			end
		},
		{
			-- fails when a filter that raises an error stops the others or lets the prompt go away (a broken filter must not take a prompt), is asked again after the fifth error, or cannot be re-armed
			name = "a filter that raises an error gives no opinion and the next one still answers; five errors in a row switch it off; adding it again re-arms it",
			func = function()
				local C = GryMod.FlashCrosshair
				local calls = 0

				filter("test.bad", function() calls = calls + 1 error("broken filter") end)
				expect(C.UsableFor(button(), player)).to.equal(1)

				filter("test.good", function() return false end)

				for _ = 1, 7 do
					expect(C.UsableFor(button(), player)).to.equal(0)
				end

				expect(calls).to.equal(5)

				filter("test.bad", function() calls = calls + 1 end)
				C.UsableFor(button(), player)
				expect(calls).to.equal(6)
			end
		}
	}
}
