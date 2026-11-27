-- Tests of the registry of weapon menus (GryMod.API.AddWeaponMenuProvider / RemoveWeaponMenuProvider / GetWeaponMenu / OpenWeaponMenu, lua/grymod/client/cl_api.lua),
-- GLuaTest format, client realm. Some weapon bases have a menu of their own to inspect and change the weapon (the attachments, the ammunition): the weapon icon of the quick
-- menu opens it. GryMod knows none of them: a provider answers, for a weapon, with the function that opens the menu, or nothing when the weapon is not its own or has no menu
-- to open. The provider runs under SafeCall (five errors in a row switch it off), the opener too. Each case names the production change whose absence makes it fail.

local API = GryMod.API
local ids

local function provider(id, fn)
	ids[#ids + 1] = id

	return API.AddWeaponMenuProvider(id, fn)
end

-- a weapon stand-in: a table that answers IsValid
local function weapon(class)
	return {IsValid = function() return true end, class = class or "test"}
end

return {
	groupName = "GryMod extension API: weapon menus (client)",
	beforeEach = function()
		ids = {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemoveWeaponMenuProvider(id)
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad id or function is accepted
			name = "AddWeaponMenuProvider takes a text id and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("weaponmenu")).to.beTrue()
				expect(provider("test.a", function() end)).to.beTrue()
				expect(API.AddWeaponMenuProvider("", function() end)).to.beFalse()
				expect(API.AddWeaponMenuProvider(5, function() end)).to.beFalse()
				expect(API.AddWeaponMenuProvider("test.b", "no")).to.beFalse()
				expect(API.AddWeaponMenuProvider("test.b")).to.beFalse()
			end
		},
		{
			-- fails when the opener of the first provider that has one is not the answer, when a provider that answers nothing stops the search, or when the weapon is not given on
			name = "GetWeaponMenu: the opener of the first provider that has one; a provider that has none is passed; no provider, no opener",
			func = function()
				local w = weapon()
				local seen
				local function open() end

				expect(API.GetWeaponMenu(w)).to.beNil()

				provider("test.none", function() return nil end)
				provider("test.false", function() return false end)
				provider("test.mine", function(given) seen = given return open end)
				provider("test.late", function() return function() end end)

				expect(API.GetWeaponMenu(w)).to.equal(open)
				expect(seen).to.equal(w)
			end
		},
		{
			-- fails when a value that is not a function is taken for an opener (the quick menu would call it), or an invalid weapon is asked about
			name = "GetWeaponMenu: only a function is an opener; no weapon, an invalid one or a number give nothing and no error",
			func = function()
				local asked = 0

				provider("test.junk", function() asked = asked + 1 return "open" end)

				expect(API.GetWeaponMenu(weapon())).to.beNil()
				expect(asked).to.equal(1)

				for _, junk in ipairs({false, 5, "weapon", NULL}) do
					expect(API.GetWeaponMenu(junk)).to.beNil()
				end

				expect(API.GetWeaponMenu(nil)).to.beNil()
				expect(asked).to.equal(1)
			end
		},
		{
			-- fails when a provider that raises an error stops the others, is asked again after the fifth error, or cannot be re-armed by adding it again
			name = "a provider that raises an error is skipped and the next one still answers; five errors in a row switch it off; adding it again re-arms it",
			func = function()
				local calls = 0
				local function open() end

				provider("test.bad", function() calls = calls + 1 error("broken provider") end)
				provider("test.good", function() return open end)

				for _ = 1, 8 do
					expect(API.GetWeaponMenu(weapon())).to.equal(open)
				end

				expect(calls).to.equal(5)

				provider("test.bad", function() calls = calls + 1 end)
				API.GetWeaponMenu(weapon())
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when OpenWeaponMenu does not run the opener with the weapon, does not say whether there was a menu, or lets the opener's error out into the player's input
			name = "OpenWeaponMenu: runs the opener with the weapon and says true; false when there is no menu or the opener raises an error",
			func = function()
				local w = weapon()
				local given

				expect(API.OpenWeaponMenu(w)).to.beFalse()

				provider("test.opens", function() return function(weaponAsked) given = weaponAsked end end)
				expect(API.OpenWeaponMenu(w)).to.beTrue()
				expect(given).to.equal(w)

				API.RemoveWeaponMenuProvider("test.opens")
				provider("test.breaks", function() return function() error("opener broke") end end)
				expect(API.OpenWeaponMenu(w)).to.beFalse()
			end
		},
		{
			-- fails when adding a provider with the same id adds a second one, or Remove does not take it away
			name = "the same id replaces the provider, and RemoveWeaponMenuProvider takes it away",
			func = function()
				local first, second = function() end, function() end

				provider("test.same", function() return first end)
				provider("test.same", function() return second end)
				expect(API.GetWeaponMenu(weapon())).to.equal(second)
				expect(API.RemoveWeaponMenuProvider("test.same")).to.beTrue()
				expect(API.RemoveWeaponMenuProvider("test.same")).to.beFalse()
				expect(API.GetWeaponMenu(weapon())).to.beNil()
			end
		}
	}
}
