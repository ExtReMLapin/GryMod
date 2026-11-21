-- Tests of the foundation of the extension API (lua/grymod/sh_api.lua), GLuaTest format, runs in the server AND in the
-- client realm: presence and version for third-party addons, the feature list, and GryMod.API.SafeCall (a broken callback
-- of a third party never breaks the HUD: after 5 errors in a row it is disabled with one console line, and registering
-- it again re-arms it). Design: docs/superpowers/specs/2026-11-21-extension-api-design.md.

local realMsgN
local lines

local function failing()
	error("boom")
end

return {
	groupName = "GryMod extension API: presence, version, safe calls (shared)",
	beforeEach = function()
		lines = {}
		realMsgN = MsgN
		MsgN = function(...)
			lines[#lines + 1] = table.concat({...}, "")
		end
	end,
	afterEach = function()
		MsgN = realMsgN

		if GryMod.API and GryMod.API.SafeCallReset then
			for _, id in ipairs({"t:one", "t:two", "t:three", "t:four", "provider:x"}) do
				GryMod.API.SafeCallReset(id)
			end
		end
	end,
	cases = {
		{
			name = "the presence test of the doc works: GRYMOD_INSTALLED, GryMod.API.Version and GetInterfaceVersion agree",
			func = function()
				expect(GRYMOD_INSTALLED).to.equal(true)
				expect(istable(GryMod.API)).to.beTrue()
				expect(GryMod.API.Version).to.equal(1)
				expect(GryMod.GetInterfaceVersion()).to.equal(1)
				expect(GryMod and GryMod.API and GryMod.API.Version >= 1).to.beTrue()
			end
		},
		{
			name = "GryMod.Version is a human string (the addon version, or dev when the repository has none)",
			func = function()
				expect(isstring(GryMod.Version)).to.beTrue()
				expect(#GryMod.Version > 0).to.beTrue()
			end
		},
		{
			name = "Has tells which parts exist: the wave A parts, the weapon registry and the tracked entity registry yes, junk no",
			func = function()
				local API = GryMod.API

				expect(API.Has("suit")).to.beTrue()
				expect(API.Has("relation")).to.beTrue()
				expect(API.Has("hudevents")).to.beTrue()
				expect(API.Has("safecall")).to.beTrue()
				expect(API.Has("weapons")).to.beTrue()
				expect(API.Has("tracked")).to.beTrue()
				expect(API.Has("nothing at all")).to.beFalse()
				expect(API.Has(nil)).to.beFalse()
				expect(API.Has(42)).to.beFalse()
			end
		},
		{
			name = "SafeCall returns ok and the results of a good callback, with its arguments",
			func = function()
				local ok, a, b = GryMod.API.SafeCall("t:one", function(x, y) return x + y, "second" end, 1, 2)

				expect(ok).to.beTrue()
				expect(a).to.equal(3)
				expect(b).to.equal("second")
			end
		},
		{
			name = "SafeCall catches an error, returns false and the message, and says nothing yet (one error is not a disaster)",
			func = function()
				local ok, err = GryMod.API.SafeCall("t:one", failing)

				expect(ok).to.beFalse()
				expect(string.find(err, "boom", 1, true) ~= nil).to.beTrue()
				expect(#lines).to.equal(0)
				expect(GryMod.API.SafeCallDisabled("t:one")).to.beFalse()
			end
		},
		{
			name = "5 errors in a row disable the callback with ONE clear console line (kind, id, count and the reason); later calls do not run it",
			func = function()
				local API = GryMod.API
				local runs = 0

				local function bad()
					runs = runs + 1
					error("boom")
				end

				for _ = 1, 5 do
					API.SafeCall("provider:x", bad)
				end

				expect(runs).to.equal(5)
				expect(API.SafeCallDisabled("provider:x")).to.beTrue()
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "GryMod API: provider 'x' disabled after 5 errors", 1, true) ~= nil).to.beTrue()
				expect(string.find(lines[1], "boom", 1, true) ~= nil).to.beTrue()

				local ok = API.SafeCall("provider:x", bad)

				expect(ok).to.beFalse()
				expect(runs).to.equal(5)
				expect(#lines).to.equal(1)
			end
		},
		{
			name = "a success resets the count: 4 errors, a success, 4 errors do not disable",
			func = function()
				local API = GryMod.API

				for _ = 1, 4 do API.SafeCall("t:two", failing) end
				expect(API.SafeCall("t:two", function() return 1 end)).to.beTrue()
				for _ = 1, 4 do API.SafeCall("t:two", failing) end

				expect(API.SafeCallDisabled("t:two")).to.beFalse()
				expect(#lines).to.equal(0)
			end
		},
		{
			name = "the count is per id: another id keeps working while one is disabled",
			func = function()
				local API = GryMod.API

				for _ = 1, 5 do API.SafeCall("t:three", failing) end

				expect(API.SafeCallDisabled("t:three")).to.beTrue()
				expect(API.SafeCall("t:four", function() return "fine" end)).to.beTrue()
				expect(API.SafeCallDisabled("t:four")).to.beFalse()
			end
		},
		{
			name = "SafeCallReset (what registering the id again does) re-arms a disabled callback, with a fresh count",
			func = function()
				local API = GryMod.API

				for _ = 1, 5 do API.SafeCall("t:one", failing) end
				expect(API.SafeCallDisabled("t:one")).to.beTrue()

				API.SafeCallReset("t:one")

				expect(API.SafeCallDisabled("t:one")).to.beFalse()
				expect(API.SafeCall("t:one", function() return "back" end)).to.beTrue()

				for _ = 1, 4 do API.SafeCall("t:one", failing) end
				expect(API.SafeCallDisabled("t:one")).to.beFalse()
			end
		},
		{
			name = "an id with no kind prefix is still told clearly, and a non-function callback is an error, not a crash",
			func = function()
				local API = GryMod.API

				for _ = 1, 5 do API.SafeCall("plain", failing) end

				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "'plain' disabled after 5 errors", 1, true) ~= nil).to.beTrue()
				API.SafeCallReset("plain")

				local ok = API.SafeCall("t:one", nil)

				expect(ok).to.beFalse()
			end
		}
	}
}
