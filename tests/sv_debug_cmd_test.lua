-- Tests of the real commands of the effects test window (GryMod.DebugCmd, sv_debug_cmd.lua), GLuaTest format, server realm. The commands are a
-- REGISTRY (GryMod.API.RegisterDebugCommand / UnregisterDebugCommand): GryMod's own ten are entries made by a loop over a table of data, and
-- another addon adds its own the same way. Two net messages, both decided by the SERVER: gry_debug_cmd (a command id, a string) and gry_debug_list
-- (the client asks for the list; the server answers with the ordered ids and labels, an empty list for a player who is not an admin). The sender is
-- a valid player that GryMod.MayConfigure accepts (an admin), the id must be in the registry, one message of each kind per 0.2 s per player; the
-- command is applied to the SENDER only, through the public GryMod.API, inside a SafeCall. Fake players and a recorder in place of the API are
-- used: the real player (the owner's) is never touched. What is stubbed lives only while the function under test runs (`with`): the real functions
-- are back whatever happens inside. The commands the cases register are removed after each case.

local DEFAULTS = {
	"suit_off", "suit_on", "malfunction", "emp_self", "energy_empty", "energy_full", "mode_armor", "mode_speed", "mode_strength", "mode_cloak"
}

local registered = {}

-- the real functions are put back right after fn, in any case
local function with(stubs, fn)
	local saved = {}

	for _, entry in ipairs(stubs) do
		saved[#saved + 1] = {entry[1], entry[2], entry[1][entry[2]]}
		entry[1][entry[2]] = entry[3]
	end

	local ok, err = pcall(fn)

	for i = #saved, 1, -1 do
		saved[i][1][saved[i][2]] = saved[i][3]
	end

	if not ok then
		error(err, 0)
	end
end

local function fakePlayer(admin, pos)
	return {
		IsValid = function() return true end,
		IsAdmin = function() return admin end,
		GetPos = function() return pos or Vector(1, 2, 3) end
	}
end

-- registers a command of the case; it is removed in afterEach
local function register(id, label, run)
	registered[#registered + 1] = id

	return GryMod.API.RegisterDebugCommand(id, {label = label, run = run})
end

local function ids()
	local list = {}

	for _, entry in ipairs(GryMod.DebugCmd.List()) do
		list[#list + 1] = entry.id
	end

	return list
end

-- runs fn with every API function the built-in commands may call replaced by a recorder; `calls` gets {name, args...}
local function recorded(fn)
	local calls = {}
	local stubs = {}

	for _, name in ipairs({"SetSuitEnabled", "StartMalfunction", "EMP", "EmptyEnergy", "RefillEnergy", "SetMode"}) do
		stubs[#stubs + 1] = {GryMod.API, name, function(...)
			calls[#calls + 1] = {name, ...}

			return true
		end}
	end

	with(stubs, function() fn(calls) end)

	return calls
end

-- the lists the server would send: {player, list}
local function listsSent(fn)
	local sent = {}

	with({{GryMod.DebugCmd, "SendList", function(ply, list) sent[#sent + 1] = {ply = ply, list = list} end}}, function() fn(sent) end)

	return sent
end

return {
	groupName = "GryMod effects test window: real commands (server)",
	afterEach = function()
		for _, id in ipairs(registered) do
			GryMod.API.UnregisterDebugCommand(id)
		end

		registered = {}
	end,
	cases = {
		{
			name = "the module, its two net messages, their receivers and the registry functions exist",
			func = function()
				expect(GryMod.DebugCmd ~= nil).to.beTrue()
				expect(util.NetworkStringToID("gry_debug_cmd") ~= 0).to.beTrue()
				expect(util.NetworkStringToID("gry_debug_list") ~= 0).to.beTrue()
				expect(net.Receivers["gry_debug_cmd"] ~= nil).to.beTrue()
				expect(net.Receivers["gry_debug_list"] ~= nil).to.beTrue()
				expect(GryMod.API.RegisterDebugCommand).to.beA("function")
				expect(GryMod.API.UnregisterDebugCommand).to.beA("function")
			end
		},
		{
			-- would fail if: the ten commands were not entries of the registry (a table of code instead of a loop over data), or lost their order or label
			name = "GryMod's own ten commands are registered entries, in order, each with a label of 48 characters at most",
			func = function()
				local list = GryMod.DebugCmd.List()

				for i, id in ipairs(DEFAULTS) do
					expect(list[i].id).to.equal(id)
					expect(list[i].label).to.beA("string")
					expect(#list[i].label >= 1 and #list[i].label <= 48).to.beTrue()
				end
			end
		},
		{
			name = "a command another addon registers is in the list after the others, runs for an admin, and is gone once unregistered",
			func = function()
				local ran = {}
				expect(register("zz_dbg_a", "Mine A", function(ply) ran[#ran + 1] = ply end)).to.beTrue()

				local list = GryMod.DebugCmd.List()
				expect(list[#list].id).to.equal("zz_dbg_a")
				expect(list[#list].label).to.equal("Mine A")

				local admin = fakePlayer(true)
				expect(GryMod.DebugCmd.Handle(admin, "zz_dbg_a", 1)).to.equal("ok")
				expect(#ran).to.equal(1)
				expect(ran[1]).to.equal(admin)

				expect(GryMod.API.UnregisterDebugCommand("zz_dbg_a")).to.beTrue()
				expect(GryMod.DebugCmd.Handle(admin, "zz_dbg_a", 2)).to.equal("unknown")
				expect(#ran).to.equal(1)

				-- nothing to remove the second time
				expect(GryMod.API.UnregisterDebugCommand("zz_dbg_a")).to.beFalse()
			end
		},
		{
			-- would fail if: an id or a label that breaks the limits got in (it goes in a net message, and a console-like id must never be accepted)
			name = "an invalid id, label or function is refused with a reason, and the list does not change",
			func = function()
				local before = table.concat(ids(), ",")
				local ok = function() end

				local bad = {
					{"", "label", ok}, {"a b", "label", ok}, {string.rep("a", 33), "label", ok}, {nil, "label", ok}, {5, "label", ok},
					{"x;quit", "label", ok}, {"é", "label", ok}, {"zz_dbg_b", "", ok}, {"zz_dbg_b", string.rep("l", 49), ok},
					{"zz_dbg_b", 5, ok}, {"zz_dbg_b", nil, ok}, {"zz_dbg_b", "label", nil}, {"zz_dbg_b", "label", "print"}
				}

				for _, case in ipairs(bad) do
					local done, why = GryMod.API.RegisterDebugCommand(case[1], {label = case[2], run = case[3]})
					expect(done).to.beFalse()
					expect(why).to.beA("string")
				end

				-- a definition that is not a table
				expect((GryMod.API.RegisterDebugCommand("zz_dbg_b", nil))).to.beFalse()
				expect((GryMod.API.RegisterDebugCommand("zz_dbg_b", "x"))).to.beFalse()

				-- the limits themselves are valid
				expect(register(string.rep("a", 32), string.rep("l", 48), ok)).to.beTrue()
				GryMod.API.UnregisterDebugCommand(string.rep("a", 32))

				expect(table.concat(ids(), ",")).to.equal(before)
			end
		},
		{
			name = "registering an id again replaces the command and keeps its place in the list",
			func = function()
				local first, second = 0, 0
				register("zz_dbg_c", "One", function() first = first + 1 end)
				register("zz_dbg_d", "Two", function() end)
				register("zz_dbg_c", "One again", function() second = second + 1 end)

				local list = GryMod.DebugCmd.List()
				expect(list[#list - 1].id).to.equal("zz_dbg_c")
				expect(list[#list - 1].label).to.equal("One again")
				expect(list[#list].id).to.equal("zz_dbg_d")

				GryMod.DebugCmd.Handle(fakePlayer(true), "zz_dbg_c", 1)
				expect(first).to.equal(0)
				expect(second).to.equal(1)
			end
		},
		{
			name = "a player who is not an admin is refused: nothing is called, whatever the command",
			func = function()
				local calls = recorded(function()
					for i, id in ipairs(DEFAULTS) do
						expect(GryMod.DebugCmd.Handle(fakePlayer(false), id, i)).to.equal("denied")
					end
				end)

				expect(#calls).to.equal(0)
			end
		},
		{
			name = "the server console and a missing player are no sender",
			func = function()
				local calls = recorded(function()
					expect(GryMod.DebugCmd.Handle(NULL, "suit_off", 1)).to.equal("denied")
					expect(GryMod.DebugCmd.Handle(nil, "suit_off", 2)).to.equal("denied")
				end)

				expect(#calls).to.equal(0)
			end
		},
		{
			-- would fail if: an id that is not in the registry (a name near the list, another type, a console line, a command that was removed) ran anything
			name = "an id that is not in the registry is refused for an admin: nothing is called",
			func = function()
				register("zz_dbg_e", "Gone soon", function() end)
				GryMod.API.UnregisterDebugCommand("zz_dbg_e")

				local calls = recorded(function()
					local admin = fakePlayer(true)

					for i, id in ipairs({"", "SUIT_OFF", "suit_off ", "mode_drop", "kill", "gry_hud 0", "quit", "suit_off;quit", "zz_dbg_e"}) do
						expect(GryMod.DebugCmd.Handle(admin, id, i)).to.equal("unknown")
					end

					expect(GryMod.DebugCmd.Handle(admin, nil, 20)).to.equal("unknown")
					expect(GryMod.DebugCmd.Handle(admin, 5, 22)).to.equal("unknown")
					expect(GryMod.DebugCmd.Handle(admin, {}, 24)).to.equal("unknown")
				end)

				expect(#calls).to.equal(0)
			end
		},
		{
			name = "a burst is limited to one command per 0.2 s per player; another player has his own clock",
			func = function()
				local calls = recorded(function()
					local a, b = fakePlayer(true), fakePlayer(true)

					expect(GryMod.DebugCmd.Handle(a, "energy_full", 100)).to.equal("ok")
					expect(GryMod.DebugCmd.Handle(a, "energy_full", 100.05)).to.equal("rate")
					expect(GryMod.DebugCmd.Handle(a, "energy_full", 100.19)).to.equal("rate")
					expect(GryMod.DebugCmd.Handle(b, "energy_full", 100.1)).to.equal("ok")
					expect(GryMod.DebugCmd.Handle(a, "energy_full", 100.2)).to.equal("ok")
				end)

				expect(#calls).to.equal(3)
			end
		},
		{
			name = "every built-in command calls the right API function, with the sender and nothing else (never another target)",
			func = function()
				local expected = {
					suit_off = {"SetSuitEnabled", false},
					suit_on = {"SetSuitEnabled", true},
					malfunction = {"StartMalfunction", 5},
					energy_empty = {"EmptyEnergy"},
					energy_full = {"RefillEnergy"},
					mode_armor = {"SetMode", GryMod.Modes.ARMOR},
					mode_speed = {"SetMode", GryMod.Modes.SPEED},
					mode_strength = {"SetMode", GryMod.Modes.STRENGTH},
					mode_cloak = {"SetMode", GryMod.Modes.CLOAK}
				}

				local now = 0

				for id, want in pairs(expected) do
					now = now + 1

					local admin, other = fakePlayer(true), fakePlayer(true)

					local calls = recorded(function()
						expect(GryMod.DebugCmd.Handle(admin, id, now)).to.equal("ok")
					end)

					expect(#calls).to.equal(1)
					expect(calls[1][1]).to.equal(want[1])
					expect(calls[1][2]).to.equal(admin) -- the sender
					expect(calls[1][2] ~= other).to.beTrue()
					expect(calls[1][3]).to.equal(want[2])
				end
			end
		},
		{
			name = "the EMP is on the sender's own position: radius 200, 10 s",
			func = function()
				local pos = Vector(10, 20, 30)

				local calls = recorded(function()
					expect(GryMod.DebugCmd.Handle(fakePlayer(true, pos), "emp_self", 1)).to.equal("ok")
				end)

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal("EMP")
				expect(calls[1][2]).to.equal(pos)
				expect(calls[1][3]).to.equal(200)
				expect(calls[1][4]).to.equal(10)
			end
		},
		{
			-- would fail if: the error of a command of another addon reached the receiver (it would break the net message and every next command)
			name = "a command that raises an error is swallowed: the answer says so and the other commands still run",
			func = function()
				register("zz_dbg_f", "Breaks", function() error("boom") end)
				local admin = fakePlayer(true)

				local answer
				expect(pcall(function() answer = GryMod.DebugCmd.Handle(admin, "zz_dbg_f", 1) end)).to.beTrue()
				expect(answer).to.equal("error")

				local calls = recorded(function()
					expect(GryMod.DebugCmd.Handle(admin, "energy_full", 2)).to.equal("ok")
				end)

				expect(#calls).to.equal(1)
			end
		},
		{
			name = "the list is the registry in order, as ids and labels, for an admin who asks",
			func = function()
				register("zz_dbg_g", "Last one", function() end)
				local admin = fakePlayer(true)

				local sent = listsSent(function()
					expect(GryMod.DebugCmd.HandleList(admin, 1)).to.equal("ok")
				end)

				expect(#sent).to.equal(1)
				expect(sent[1].ply).to.equal(admin)

				local list = sent[1].list

				for i, id in ipairs(DEFAULTS) do
					expect(list[i].id).to.equal(id)
				end

				expect(list[#list].id).to.equal("zz_dbg_g")
				expect(list[#list].label).to.equal("Last one")
				expect(#list).to.equal(#GryMod.DebugCmd.List())
			end
		},
		{
			-- would fail if: a player who is not an admin got the names of the commands (or got no answer and the window waited for ever)
			name = "a player who is not an admin gets an EMPTY list, not the registry",
			func = function()
				local other = fakePlayer(false)

				local sent = listsSent(function()
					expect(GryMod.DebugCmd.HandleList(other, 1)).to.equal("denied")
				end)

				expect(#sent).to.equal(1)
				expect(sent[1].ply).to.equal(other)
				expect(#sent[1].list).to.equal(0)
			end
		},
		{
			name = "no answer to the console or to a missing player; the list request is limited too: one per 0.2 s per player",
			func = function()
				local sent = listsSent(function()
					expect(GryMod.DebugCmd.HandleList(NULL, 1)).to.equal("denied")
					expect(GryMod.DebugCmd.HandleList(nil, 2)).to.equal("denied")
				end)

				expect(#sent).to.equal(0)

				local admin = fakePlayer(true)

				sent = listsSent(function()
					expect(GryMod.DebugCmd.HandleList(admin, 50)).to.equal("ok")
					expect(GryMod.DebugCmd.HandleList(admin, 50.1)).to.equal("rate")
					expect(GryMod.DebugCmd.HandleList(admin, 50.2)).to.equal("ok")
				end)

				expect(#sent).to.equal(2)
			end
		},
		{
			name = "a command registered later is in the next list, one that was removed is not",
			func = function()
				local admin = fakePlayer(true)
				local before = #GryMod.DebugCmd.List()

				register("zz_dbg_h", "Later", function() end)

				local sent = listsSent(function() GryMod.DebugCmd.HandleList(admin, 1) end)
				expect(#sent[1].list).to.equal(before + 1)

				GryMod.API.UnregisterDebugCommand("zz_dbg_h")
				sent = listsSent(function() GryMod.DebugCmd.HandleList(admin, 2) end)
				expect(#sent[1].list).to.equal(before)
			end
		},
		{
			name = "the receivers read what the client sent and decide on the sender they are given",
			func = function()
				local command, list = net.Receivers["gry_debug_cmd"], net.Receivers["gry_debug_list"]
				expect(command).to.beA("function")
				expect(list).to.beA("function")

				-- a non-admin: no command runs, and the list that comes back is empty
				local other = fakePlayer(false)

				local calls = recorded(function()
					with({{net, "ReadString", function() return "energy_full" end}}, function()
						command(0, other)
					end)
				end)

				expect(#calls).to.equal(0)

				local sent = listsSent(function() list(0, other) end)
				expect(#sent).to.equal(1)
				expect(#sent[1].list).to.equal(0)

				-- an admin: the command that was read runs on that sender, and the list is the registry
				local admin = fakePlayer(true)

				calls = recorded(function()
					with({{net, "ReadString", function() return "energy_full" end}}, function()
						command(0, admin)
					end)
				end)

				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal("RefillEnergy")
				expect(calls[1][2]).to.equal(admin)

				sent = listsSent(function() list(0, admin) end)
				expect(#sent).to.equal(1)
				expect(#sent[1].list >= #DEFAULTS).to.beTrue()
			end
		},
		{
			name = "the clocks of a player are forgotten when he leaves",
			func = function()
				local ply = fakePlayer(true)

				recorded(function()
					GryMod.DebugCmd.Handle(ply, "energy_full", 1)
				end)

				listsSent(function()
					GryMod.DebugCmd.HandleList(ply, 1)
				end)

				expect(GryMod.DebugCmd.Tracked(ply)).to.beTrue()
				GryMod.DebugCmd.Forget(ply)
				expect(GryMod.DebugCmd.Tracked(ply)).to.beFalse()
			end
		}
	}
}
