-- Tests of the registry of plain views (GryMod.API.AddPlainViewProvider / RemovePlainViewProvider / IsPlainView, lua/grymod/client/cl_api.lua), GLuaTest format, client
-- realm. Some weapon bases show the weapon on a screen of their own (ARC9's customization menu: the gun is turned towards the player over a dark, blurred picture of the
-- world). The camouflage of the first person view cannot show the picture behind the gun there (the picture it copies is not the one the player sees), and the player
-- needs to see the parts he picks: a provider says, for a weapon, that its view is such a screen and the effects draw the weapon plain. The provider runs under SafeCall (five
-- errors in a row switch it off). Each case names the production change whose absence makes it fail.

local API = GryMod.API
local ids

local function provider(id, fn)
	ids[#ids + 1] = id

	return API.AddPlainViewProvider(id, fn)
end

-- a weapon stand-in: a table that answers IsValid
local function weapon()
	return {IsValid = function() return true end}
end

return {
	groupName = "GryMod extension API: plain views (client)",
	beforeEach = function()
		ids = {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemovePlainViewProvider(id)
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad id or function is accepted
			name = "AddPlainViewProvider takes a text id and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("plainview")).to.beTrue()
				expect(provider("test.a", function() end)).to.beTrue()
				expect(API.AddPlainViewProvider("", function() end)).to.beFalse()
				expect(API.AddPlainViewProvider(5, function() end)).to.beFalse()
				expect(API.AddPlainViewProvider("test.b", "no")).to.beFalse()
				expect(API.AddPlainViewProvider("test.b")).to.beFalse()
			end
		},
		{
			-- fails when nothing registered still says "plain", when the first true is not the answer, or when the weapon is not given to the provider
			name = "IsPlainView: false with no provider, true as soon as one says true (a provider that says nothing or false is passed), and the provider is given the weapon",
			func = function()
				local w = weapon()
				local seen

				expect(API.IsPlainView(w)).to.beFalse()

				provider("test.none", function() return nil end)
				provider("test.false", function() return false end)

				expect(API.IsPlainView(w)).to.beFalse()

				provider("test.mine", function(given) seen = given return true end)

				expect(API.IsPlainView(w)).to.beTrue()
				expect(seen).to.equal(w)
			end
		},
		{
			-- fails when only the value true counts (a truthy text is not a yes), or when no weapon, an invalid one or a number gives an error or a yes
			name = "IsPlainView: only true is a yes; no weapon, an invalid one or a number give false and no error",
			func = function()
				provider("test.junk", function() return "yes" end)

				expect(API.IsPlainView(weapon())).to.beFalse()

				provider("test.always", function() return true end)

				expect(API.IsPlainView(nil)).to.beFalse()
				expect(API.IsPlainView(5)).to.beFalse()
				expect(API.IsPlainView({IsValid = function() return false end})).to.beFalse()
			end
		},
		{
			-- fails when a provider that raises an error breaks the call, or is never switched off (the call would go on at every frame of the game)
			name = "a provider that raises an error is passed (no error out), and is switched off after five errors in a row; adding it again re-arms it",
			func = function()
				local calls = 0
				local w = weapon()

				provider("test.bad", function() calls = calls + 1 error("boom") end)
				provider("test.good", function() return true end)

				for _ = 1, 8 do
					expect(API.IsPlainView(w)).to.beTrue()
				end

				expect(calls).to.equal(5)

				provider("test.bad", function() calls = calls + 1 error("boom") end)
				API.IsPlainView(w)
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when the same id adds a second provider (a file loaded again would then answer twice) or when removing does not take the provider away
			name = "the same id replaces the provider; RemovePlainViewProvider takes it away and says whether it was there",
			func = function()
				local w = weapon()

				provider("test.same", function() return true end)
				provider("test.same", function() return false end)

				expect(API.IsPlainView(w)).to.beFalse()

				provider("test.other", function() return true end)

				expect(API.IsPlainView(w)).to.beTrue()
				expect(API.RemovePlainViewProvider("test.other")).to.beTrue()
				expect(API.RemovePlainViewProvider("test.other")).to.beFalse()
				expect(API.IsPlainView(w)).to.beFalse()
			end
		}
	}
}
