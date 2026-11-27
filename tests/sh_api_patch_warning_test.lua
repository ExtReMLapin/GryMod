-- Tests of GryMod.API.WarnPatchMissing (lua/grymod/sh_api.lua), GLuaTest format, run in the server and in the client realm. A compatibility patch that replaces a function of another
-- addon looks for it first: when the addon is there but the function is not (the addon changed), the patch is off and the owner is told, in the console and in the chat: "GryMod tried to
-- replace X of Y, but it does not exist (any more)". Once for a thing, whatever the number of tries. The stand-ins (the console, the chat, the players, the timers) are put back after
-- each case. Each case names the change whose absence makes it fail.

local API
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

return {
	groupName = "GryMod extension API: a patch that cannot replace a function says so",
	beforeEach = function()
		API = GryMod.API
		saved = {}
		API.ForgetPatchWarnings()

		-- nothing of the cases reaches the real chat
		if SERVER then
			stub(player, "GetAll", function() return {} end)
		else
			stub(chat, "AddText", function() end)
		end
	end,
	afterEach = function()
		for i = #saved, 1, -1 do
			pcall(function() saved[i][1][saved[i][2]] = saved[i][3] end)
		end

		saved = {}
		pcall(API.ForgetPatchWarnings)
	end,
	cases = {
		{
			-- fails when the function does not exist, when nothing is written to the console, when the text does not name the addon and the function, or when it does not ask how to go on
			name = "WarnPatchMissing writes to the console what could not be replaced, in which addon, and asks how to go on",
			func = function()
				expect(isfunction(API.WarnPatchMissing)).to.beTrue()

				local lines = {}

				stub(_G, "MsgC", function(...) for _, part in ipairs({...}) do if isstring(part) then lines[#lines + 1] = part end end end)
				stub(_G, "timer", setmetatable({Simple = function(_, fn) fn() end}, {__index = timer}))

				expect(API.WarnPatchMissing("T_Addon", "T_Addon.Function")).to.beTrue()

				local text = table.concat(lines, "")

				expect(string.find(text, "T_Addon", 1, true) ~= nil).to.beTrue()
				expect(string.find(text, "T_Addon.Function", 1, true) ~= nil).to.beTrue()
				expect(string.find(text, "does not exist", 1, true) ~= nil).to.beTrue()
				expect(string.find(text, "How should it be handled", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			-- fails when the same thing is told every time the patch tries again (the console and the chat would fill up), or when another thing is taken for the same
			name = "WarnPatchMissing tells a thing once, and another thing separately",
			func = function()
				local count = 0

				stub(_G, "MsgC", function() count = count + 1 end)
				stub(_G, "timer", setmetatable({Simple = function(_, fn) fn() end}, {__index = timer}))

				expect(API.WarnPatchMissing("T_Addon", "T_Addon.A")).to.beTrue()
				expect(API.WarnPatchMissing("T_Addon", "T_Addon.A")).to.beFalse()
				expect(count).to.equal(1)

				expect(API.WarnPatchMissing("T_Addon", "T_Addon.B")).to.beTrue()
				expect(count).to.equal(2)
			end
		},
		{
			-- fails when the chat is not told (server: the administrators; client: the player), or when everybody is told instead of the administrators
			name = "WarnPatchMissing tells the chat: the administrators on the server, the player on the client",
			func = function()
				local chats = {}

				stub(_G, "MsgC", function() end)
				stub(_G, "timer", setmetatable({Simple = function(_, fn) fn() end}, {__index = timer}))

				if SERVER then
					local admin = {IsValid = function() return true end, IsAdmin = function() return true end, ChatPrint = function(_, text) chats[#chats + 1] = text end}
					local user = {IsValid = function() return true end, IsAdmin = function() return false end, ChatPrint = function(_, text) chats[#chats + 1] = "USER " .. text end}

					stub(player, "GetAll", function() return {admin, user} end)
				else
					stub(chat, "AddText", function(...) for _, part in ipairs({...}) do if isstring(part) then chats[#chats + 1] = part end end end)
				end

				API.WarnPatchMissing("T_Addon", "T_Addon.Chat")

				expect(#chats).to.equal(1)
				expect(string.find(chats[1], "T_Addon.Chat", 1, true) ~= nil).to.beTrue()
				expect(string.find(chats[1], "USER", 1, true) == nil).to.beTrue()
			end
		},
		{
			-- fails when a check that says the thing is there after all (the addon defined it late) still warns, or when one that says it is still missing does not
			name = "WarnPatchMissing with a check: nothing when the thing is there by then, the warning when it is still missing",
			func = function()
				local count = 0
				local queue = {}

				stub(_G, "MsgC", function() count = count + 1 end)
				stub(_G, "timer", setmetatable({Simple = function(_, fn) queue[#queue + 1] = fn end}, {__index = timer}))

				API.WarnPatchMissing("T_Addon", "T_Addon.Late", function() return false end) -- there by the time of the check
				API.WarnPatchMissing("T_Addon", "T_Addon.Gone", function() return true end) -- still missing

				expect(count).to.equal(0) -- nothing is said before the check

				for _, fn in ipairs(queue) do fn() end

				expect(count).to.equal(1)
			end
		}
	}
}
