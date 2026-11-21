-- The real commands of the effects test window (cl_debug_window.lua). The commands are a REGISTRY: GryMod.API.RegisterDebugCommand(id, {label, run})
-- and UnregisterDebugCommand(id). GryMod's own ten are entries made by a loop over the table of data below; another addon adds its own with the
-- same call. Two net messages, and the SERVER decides every time, in this order:
--   1. the sender: a valid player (the server console is no sender of a message) that GryMod.MayConfigure accepts, the same rule as the
--      administrators' settings (sv_server_options.lua): an admin, the host of a listen server and the single player;
--   2. the rate: one message of each kind per 0.2 s per player (a message that comes too early is refused and does not move the clock);
--   3. the id (gry_debug_cmd): it must be in the registry, nothing else can be reached.
-- gry_debug_cmd (client to server): a command id. It runs on the SENDER only (the client never chooses a target), through the public GryMod.API,
-- inside a SafeCall: the error of a command of another addon breaks nothing.
-- gry_debug_list (both ways): the client asks, when the window opens; the server answers with the ordered ids and labels, and an EMPTY list for a
-- player who is not an admin. A refusal for the rate is silent.
-- Cost: nothing runs by itself.

util.AddNetworkString("gry_debug_cmd")
util.AddNetworkString("gry_debug_list")

GryMod = GryMod or {}
GryMod.API = GryMod.API or {} -- sh_api.lua makes it first; this is only for a load order that would differ

local API = GryMod.API

local Cmd = GryMod.DebugCmd or {}
GryMod.DebugCmd = Cmd

local INTERVAL = 0.2 -- seconds between two messages of one kind from a player
local ID_MAX, LABEL_MAX = 32, 48
local LIST_MAX = 255 -- the count of the list travels in 8 bits

local commands = Cmd._commands or {} -- [id] = {label = text, run = function(ply)}
local order = Cmd._order or {} -- the ids, in the order of registration
Cmd._commands, Cmd._order = commands, order

local lastTime = {cmd = setmetatable({}, {__mode = "k"}), list = setmetatable({}, {__mode = "k"})} -- [kind][player] = time of the last accepted message

-- ---------------------------------------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------------------------------------

-- Adds (or replaces, with the same id, keeping its place) a command: id (letters, digits, underscore, at most 32), a table with `label` (a text of
-- 1 to 48 characters, shown on the button) and `run` (function(ply): ply is the player who asked, and nobody else). Returns true, or false and why.
function API.RegisterDebugCommand(id, def)
	if not isstring(id) or #id < 1 or #id > ID_MAX or string.find(id, "^[%w_]+$") == nil then
		return false, "invalid id"
	end

	if not istable(def) then
		return false, "invalid definition"
	end

	if not isstring(def.label) or #def.label < 1 or #def.label > LABEL_MAX then
		return false, "invalid label"
	end

	if not isfunction(def.run) then
		return false, "invalid function"
	end

	if not commands[id] then
		order[#order + 1] = id
	end

	API.SafeCallReset("debugcmd:" .. id)
	commands[id] = {label = def.label, run = def.run}

	return true
end

-- Removes a command; returns whether there was one.
function API.UnregisterDebugCommand(id)
	if not isstring(id) or not commands[id] then
		return false
	end

	commands[id] = nil
	table.RemoveByValue(order, id)

	return true
end

-- The registry in order: a new table of {id = , label = }.
function Cmd.List()
	local list = {}

	for _, id in ipairs(order) do
		list[#list + 1] = {id = id, label = commands[id].label}
	end

	return list
end

-- GryMod's own commands, as data: {id, label, run}, in the order of the window. Each goes through the public API.
local BUILTIN = {
	{"suit_off", "Suit off", function(ply) API.SetSuitEnabled(ply, false) end},
	{"suit_on", "Suit on", function(ply) API.SetSuitEnabled(ply, true) end},
	{"malfunction", "Malfunction (5 s)", function(ply) API.StartMalfunction(ply, 5, "debug window") end},
	{"emp_self", "EMP on me (200, 10 s)", function(ply) API.EMP(ply:GetPos(), 200, 10) end},
	{"energy_empty", "Energy to 0", function(ply) API.EmptyEnergy(ply) end},
	{"energy_full", "Energy full", function(ply) API.RefillEnergy(ply) end},
	{"mode_armor", "Mode: armor", function(ply) API.SetMode(ply, GryMod.Modes.ARMOR) end},
	{"mode_speed", "Mode: speed", function(ply) API.SetMode(ply, GryMod.Modes.SPEED) end},
	{"mode_strength", "Mode: strength", function(ply) API.SetMode(ply, GryMod.Modes.STRENGTH) end},
	{"mode_cloak", "Mode: cloak", function(ply) API.SetMode(ply, GryMod.Modes.CLOAK) end}
}

for _, entry in ipairs(BUILTIN) do
	API.RegisterDebugCommand(entry[1], {label = entry[2], run = entry[3]})
end

-- ---------------------------------------------------------------------------------------------------------
-- The messages
-- ---------------------------------------------------------------------------------------------------------

function Cmd.Forget(ply)
	lastTime.cmd[ply] = nil
	lastTime.list[ply] = nil
end

function Cmd.Tracked(ply)
	return lastTime.cmd[ply] ~= nil or lastTime.list[ply] ~= nil
end

-- Whether the sender may do something of this kind now (the clock moves only when it may).
local function allowed(kind, ply, now)
	local last = lastTime[kind][ply]

	if last and now - last < INTERVAL then
		return false
	end

	lastTime[kind][ply] = now

	return true
end

-- One command. The answer, for the tests and the logs: "ok", "denied" (sender), "rate", "unknown" (id), "error" (the command raised an error).
function Cmd.Handle(ply, id, now)
	if not IsValid(ply) or not GryMod.MayConfigure(ply) then
		return "denied"
	end

	local last = lastTime.cmd[ply]

	if last and now - last < INTERVAL then
		return "rate"
	end

	local command = isstring(id) and commands[id]

	if not command then
		return "unknown"
	end

	lastTime.cmd[ply] = now

	if not API.SafeCall("debugcmd:" .. id, command.run, ply) then
		return "error"
	end

	return "ok"
end

-- The real way to send the list to a player (a field, so that the tests can look at what is sent).
function Cmd.SendList(ply, list)
	local count = math.min(#list, LIST_MAX)

	net.Start("gry_debug_list")
	net.WriteUInt(count, 8)

	for i = 1, count do
		net.WriteString(list[i].id)
		net.WriteString(list[i].label)
	end

	net.Send(ply)
end

-- One request for the list. The answer: "ok", "denied" (the sender gets an empty list; the console and a missing player get nothing), "rate".
function Cmd.HandleList(ply, now)
	if not IsValid(ply) then
		return "denied"
	end

	if not allowed("list", ply, now) then
		return "rate"
	end

	if not GryMod.MayConfigure(ply) then
		Cmd.SendList(ply, {})

		return "denied"
	end

	Cmd.SendList(ply, Cmd.List())

	return "ok"
end

net.Receive("gry_debug_cmd", function(_, ply)
	Cmd.Handle(ply, net.ReadString(), RealTime())
end)

net.Receive("gry_debug_list", function(_, ply)
	Cmd.HandleList(ply, RealTime())
end)

hook.Add("PlayerDisconnected", "GryMod debug cmd", function(ply)
	Cmd.Forget(ply)
end)
