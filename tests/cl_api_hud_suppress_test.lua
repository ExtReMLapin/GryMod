-- Tests of the HUD suppressors (GryMod.API.AddHudSuppressor / RemoveHudSuppressor / IsHudSuppressed, lua/grymod/client/cl_api.lua, read by GryMod.HUDOptions.Enabled),
-- GLuaTest format, client realm (SHARED-HUD-1). An addon that draws a HUD of its own (a vehicle's dashboard, a drone's screen) can hide one element of GryMod while its HUD
-- is up, without touching the player's settings: the element is simply not drawn. Each case names the production change whose absence makes it fail.

local API = GryMod.API
local ids

local function suppressor(id, fn)
	ids[#ids + 1] = id

	return API.AddHudSuppressor(id, fn)
end

return {
	groupName = "GryMod extension API: HUD suppressors (client)",
	beforeEach = function()
		ids = {}
	end,
	afterEach = function()
		pcall(function()
			for _, id in ipairs(ids) do
				API.RemoveHudSuppressor(id)
			end
		end)
	end,
	cases = {
		{
			-- fails without the functions, or when a bad key or function is accepted, or the feature is not announced
			name = "AddHudSuppressor takes a text key and a function, and answers false for anything else; the feature is announced",
			func = function()
				expect(API.Has("hudsuppress")).to.beTrue()
				expect(suppressor("test.a", function() return false end)).to.beTrue()
				expect(API.AddHudSuppressor("", function() end)).to.beFalse()
				expect(API.AddHudSuppressor(5, function() end)).to.beFalse()
				expect(API.AddHudSuppressor("test.b", "no")).to.beFalse()
				expect(API.AddHudSuppressor("test.b")).to.beFalse()
			end
		},
		{
			-- fails when the suppressor is not asked with the element's name and the player, when Enabled does not read it, or when the answer of another element is taken
			name = "HUDOptions.Enabled: an element a suppressor hides is not enabled, the others are; the suppressor is asked (element, player); Remove brings it back",
			func = function()
				local Options = GryMod.HUDOptions
				local seenElement, seenPly

				expect(Options.Enabled("radar")).to.beTrue()

				suppressor("test.radar", function(element, ply)
					seenElement, seenPly = element, ply

					return element == "radar"
				end)

				expect(Options.Enabled("radar")).to.beFalse()
				expect(seenElement).to.equal("radar")
				expect(seenPly).to.equal(LocalPlayer())
				expect(Options.Enabled("crosshair")).to.beTrue()
				expect(API.IsHudSuppressed("radar")).to.beTrue()
				expect(API.IsHudSuppressed("crosshair")).to.beFalse()

				expect(API.RemoveHudSuppressor("test.radar")).to.beTrue()
				expect(API.RemoveHudSuppressor("test.radar")).to.beFalse()
				expect(Options.Enabled("radar")).to.beTrue()
			end
		},
		{
			-- fails when hiding an element writes the player's setting (it would stay off after the addon's HUD is gone), or when a suppressor can turn on what the player switched off
			name = "a suppressor never changes the player's switch (gry_hud_radar stays as it is), and cannot show an element the player switched off",
			func = function()
				local Options = GryMod.HUDOptions
				local convar = GetConVar("gry_hud_radar")
				local saved = convar:GetString()

				local ok, err = pcall(function()
					convar:SetString("1")
					suppressor("test.all", function() return true end)
					expect(Options.Enabled("radar")).to.beFalse()
					expect(convar:GetString()).to.equal("1")

					convar:SetString("0")
					API.AddHudSuppressor("test.all", function() return false end)
					expect(Options.Enabled("radar")).to.beFalse()
				end)

				convar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when only the answer true hides (a number or a text would hide an element by mistake), or when an error stops the others
			name = "only the answer true hides; a suppressor that raises an error is skipped and the next one still answers; five errors in a row switch it off (one frame each)",
			func = function()
				local calls = 0

				suppressor("test.junk", function() return 1 end)
				expect(API.IsHudSuppressed("radar", true)).to.beFalse()

				suppressor("test.bad", function() calls = calls + 1 error("broken suppressor") end)
				suppressor("test.good", function(element) return element == "radar" end)

				for _ = 1, 8 do
					expect(API.IsHudSuppressed("radar", true)).to.beTrue()
				end

				expect(calls).to.equal(5)

				suppressor("test.bad", function() calls = calls + 1 return false end)
				API.IsHudSuppressed("radar", true)
				expect(calls).to.equal(6)
			end
		},
		{
			-- fails when the suppressors are asked at every call: the HUD asks many times a frame, the addon's code would run at each of them
			name = "the suppressors are asked once per frame and element (the answer is kept for the frame); a new one or a removed one is asked at once",
			func = function()
				local calls, answer = 0, false

				suppressor("test.count", function() calls = calls + 1 return answer end)

				for _ = 1, 5 do
					API.IsHudSuppressed("radar")
				end

				expect(calls).to.equal(1)
				API.IsHudSuppressed("crosshair")
				expect(calls).to.equal(2)

				answer = true
				suppressor("test.count", function() calls = calls + 1 return answer end)
				expect(API.IsHudSuppressed("radar")).to.beTrue()

				API.RemoveHudSuppressor("test.count")
				expect(API.IsHudSuppressed("radar")).to.beFalse()
			end
		}
	}
}
