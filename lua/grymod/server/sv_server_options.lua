-- The administrators' settings: ONE net message, gry_set_server_option (the name of the setting, its value, two strings). A client cannot change a
-- server convar by itself (on a dedicated server a replicated convar refuses the console of a client, and a convar that is not replicated does
-- not exist for it), so the options panel asks and the SERVER decides, in this order:
--   1. the rate: 5 messages a second per player at most (as sv_friendly.lua), every message counts, an admin's too;
--   2. the sender: a valid player that GryMod.MayConfigure accepts (an admin; the host of a listen server and the single player are admins);
--      the server console is no sender of a message;
--   3. the name: it must be in the white list of sh_server_options.lua, nothing else can be reached;
--   4. the value: valid for that setting (0 or 1, crysis or classic).
-- Then it sets the convar. A refusal is silent: no error, nothing sent back (the panel shows the value the server really has).
-- Cost: nothing runs by itself.

util.AddNetworkString("gry_set_server_option")

GryMod = GryMod or {}

local Options = GryMod.ServerOptions or {}
GryMod.ServerOptions = Options

local LIMIT = 5 -- messages per player per window
local WINDOW = 1 -- seconds

local windows = setmetatable({}, {__mode = "k"}) -- [player] = {start = time, count = n}

-- Whether the player may send now (5 a second).
local function allowed(ply, now)
	local w = windows[ply]

	if not w or now - w.start >= WINDOW then
		windows[ply] = {start = now, count = 1}

		return true
	end

	if w.count >= LIMIT then
		return false
	end

	w.count = w.count + 1

	return true
end

function Options.Forget(ply)
	windows[ply] = nil
end

function Options.Tracked(ply)
	return windows[ply] ~= nil
end

-- One message. The answer, for the tests and the logs: "ok", "rate", "denied", "unknown" (name), "invalid" (value).
function Options.Handle(ply, name, value, now)
	if not IsValid(ply) then
		return "denied"
	end

	if not allowed(ply, now) then
		return "rate"
	end

	if not GryMod.MayConfigure(ply) then
		return "denied"
	end

	if not GryMod.ServerSettings.Find(name) then
		return "unknown"
	end

	local text = GryMod.ServerSettings.Validate(name, value)

	if not text then
		return "invalid"
	end

	GetConVar(name):SetString(text)

	return "ok"
end

net.Receive("gry_set_server_option", function(_, ply)
	Options.Handle(ply, net.ReadString(), net.ReadString(), RealTime())
end)

hook.Add("PlayerDisconnected", "GryMod server options", function(ply)
	Options.Forget(ply)
end)
