-- Tests of what the server tells a player who joins a game in progress (sv_system.lua), GLuaTest format, server realm.
--
-- Two things used to be missing:
--   * the camouflage switch ("GryCloak") says WHO is camouflaged but not SINCE WHEN, so a client that joins while somebody is camouflaged saw
--     him as if the activation had just begun (the fade and the sparks of the change, for 0.8 s). The server now writes the time of the
--     activation ("GryCloakSince", a NW2 float) BEFORE the switch, so that the client reads both at once;
--   * the mode of a suit was told to its owner only once, by a net message at the spawn, which a client that is still loading loses
--     (the engine does not deliver net messages reliably before the client's InitPostEntity). The client now says it is ready
--     ("gry_client_ready") and gets the real mode back, at most once a second.
--
-- Nobody else is in the game (single player, maxplayers 1): the cases use FAKE players and recorders in place of the network, and the real
-- player is never touched (his mode, his camouflage and his energy are his own). The recorders live only while the function under test runs
-- (`with`): the real net functions are back whatever happens inside, even when a case fails.

local meta = FindMetaTable("Player")

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

-- a player the suit code can run on; every call it makes on the player that matters here goes in `log` (the order counts)
local function fakePlayer(log, mode)
	local ply = {Nanosuit_mode = mode, nw2 = {}, log = log}

	function ply:IsValid() return true end
	function ply:IsPlayer() return true end
	function ply:Alive() return true end
	function ply:GetNW2Bool(name, default)
		if self.nw2[name] == nil then return default end

		return self.nw2[name]
	end
	function ply:SetNW2Bool(name, value)
		self.nw2[name] = value
		self.log[#self.log + 1] = {"bool", name, value}
	end
	function ply:SetNW2Float(name, value)
		self.nw2[name] = value
		self.log[#self.log + 1] = {"float", name, value}
	end
	function ply:GetNW2Float(name, default)
		if self.nw2[name] == nil then return default or 0 end

		return self.nw2[name]
	end
	function ply:GetHands() return NULL end
	function ply:SetWalkSpeed() end
	function ply:SetRunSpeed() end
	function ply:SetJumpPower() end
	function ply:SetNoTarget() end
	function ply:InVehicle() return false end
	function ply:IsFlagSet() return false end
	function ply:DrawWorldModel() end
	function ply:SetMaterial() end

	return ply
end

-- puts the fake player's suit in a mode with the clock at `now`; the other addons' hooks (a veto, the mode change) are not called: they would get a fake
local function setMode(ply, mode, now)
	with({
		{_G, "CurTime", function() return now end},
		{hook, "Run", function() return nil end}
	}, function()
		meta.SetNanosuitMode(ply, mode, false)
	end)
end

local function find(log, kind, name)
	for i, entry in ipairs(log) do
		if entry[1] == kind and entry[2] == name then
			return i, entry
		end
	end
end

-- the net messages the server starts, as a list: {name, mode (the first UInt), reason (the second UInt: the id of the cause), target}
local function recorded(fn, now)
	local sent = {}

	with({
		{net, "Start", function(name) sent[#sent + 1] = {name = name, writes = 0} return true end},
		{net, "WriteUInt", function(value)
			local message = sent[#sent]
			message.writes = message.writes + 1

			if message.writes == 1 then
				message.mode = value
			elseif message.writes == 2 then
				message.reason = value
			end
		end},
		{net, "Send", function(target) sent[#sent].target = target end},
		{_G, "CurTime", function() return now end}
	}, fn)

	return sent
end

local function ready(ply, now)
	local receiver = net.Receivers["gry_client_ready"]
	expect(receiver).to.beA("function")

	local all = recorded(function()
		receiver(0, ply)
	end, now)

	-- (the answer also carries the modes a veto refuses, gry_modes_refused, sv_mode_states.lua, and the objectives that exist, gry_objectives,
	-- sv_objectives.lua: their own test files look at those messages)
	local sent = {}

	for _, message in ipairs(all) do
		if message.name ~= "gry_modes_refused" and message.name ~= "gry_objectives" then
			sent[#sent + 1] = message
		end
	end

	return sent
end

return {
	groupName = "GryMod a player who joins a game in progress (server)",
	cases = {
		{
			-- would fail if: SetNanosuitMode stopped writing "GryCloakSince", or wrote it after the switch (the client's Think reads both in one frame)
			name = "the activation time is written with the camouflage switch, and BEFORE it, so the client never reads a switch without its time",
			func = function()
				local log = {}
				local ply = fakePlayer(log, GryMod.Modes.ARMOR)

				setMode(ply, GryMod.Modes.CLOAK, 1234.5)

				local iSince, since = find(log, "float", "GryCloakSince")
				local iSwitch, switch = find(log, "bool", "GryCloak")

				expect(iSince).to.exist()
				expect(iSwitch).to.exist()
				expect(since[3]).to.equal(1234.5)
				expect(switch[3]).to.beTrue()
				expect(iSince < iSwitch).to.beTrue()
			end
		},
		{
			-- would fail if: the time was written at every call, whatever the switch was (a second request for the camouflage would restart the clock)
			name = "asking for the camouflage again while it is on keeps the time of the first activation (the client would take it for a new one)",
			func = function()
				local log = {}
				local ply = fakePlayer(log, GryMod.Modes.ARMOR)

				setMode(ply, GryMod.Modes.CLOAK, 100)
				setMode(ply, GryMod.Modes.CLOAK, 250)

				expect(ply.nw2.GryCloakSince).to.equal(100)
			end
		},
		{
			-- would fail if: the time was only written once, at the first activation ever
			name = "a new activation after the camouflage went off writes a new time",
			func = function()
				local log = {}
				local ply = fakePlayer(log, GryMod.Modes.ARMOR)

				setMode(ply, GryMod.Modes.CLOAK, 100)
				setMode(ply, GryMod.Modes.ARMOR, 150)
				expect(ply.nw2.GryCloak).to.beFalse()
				setMode(ply, GryMod.Modes.CLOAK, 300)

				expect(ply.nw2.GryCloakSince).to.equal(300)
				expect(ply.nw2.GryCloak).to.beTrue()
			end
		},
		{
			-- would fail if: the time was written for the other modes too (a time with the switch off means nothing)
			name = "no time is written for the other modes",
			func = function()
				for _, mode in ipairs({GryMod.Modes.ARMOR, GryMod.Modes.SPEED, GryMod.Modes.STRENGTH}) do
					local log = {}
					local ply = fakePlayer(log, GryMod.Modes.ARMOR)

					setMode(ply, mode, 77)
					expect(find(log, "float", "GryCloakSince")).to.beNil()
				end
			end
		},
		{
			-- would fail if: util.AddNetworkString("gry_client_ready") was missing from sv_system.lua
			name = "the message the client sends when it is ready is registered (without it the client's net.Start fails)",
			func = function()
				expect(util.NetworkStringToID("gry_client_ready") ~= 0).to.beTrue()
			end
		},
		{
			-- would fail if: the receiver was missing, or answered with another message, or with a fixed mode
			name = "a client that says it is ready is told the mode the server really keeps: armor for a new one, the real mode for one that has changed",
			func = function()
				for _, mode in ipairs({GryMod.Modes.SPEED, GryMod.Modes.CLOAK, GryMod.Modes.STRENGTH}) do
					local ply = fakePlayer({}, mode)
					local sent = ready(ply, 10)

					expect(#sent).to.equal(1)
					expect(sent[1].name).to.equal("gry_nanosuit_mode_change")
					expect(sent[1].mode).to.equal(mode)
					expect(sent[1].target).to.equal(ply)
					-- would fail if: the answer had no cause, or the cause of another path: the client reads this one as "I just arrived, this is the real mode"
					expect(sent[1].reason).to.equal(GryMod.ModeReasonIds[GryMod.ModeReasons.SYNC])
				end

				local sent = ready(fakePlayer({}, nil), 10) -- a suit that never had a mode is in armor
				expect(#sent).to.equal(1)
				expect(sent[1].mode).to.equal(GryMod.Modes.ARMOR)
			end
		},
		{
			-- would fail if: the limit of one answer a second was missing (a client could make the server send without end) or was shared by all the players
			name = "one answer per player and per second: a client that asks again at once gets nothing, a second later it is answered, another player is not held back",
			func = function()
				local a, b = fakePlayer({}, GryMod.Modes.SPEED), fakePlayer({}, GryMod.Modes.CLOAK)

				expect(#ready(a, 50)).to.equal(1)
				expect(#ready(a, 50)).to.equal(0)
				expect(#ready(a, 50.9)).to.equal(0)
				expect(#ready(b, 50.5)).to.equal(1) -- somebody else, in the same second
				expect(#ready(a, 51.1)).to.equal(1)
				expect(#ready(a, 51.2)).to.equal(0)
			end
		},
		{
			-- would fail if: the receiver did not check the player (the engine can call it for a client that has just gone)
			name = "a player who is gone gets no answer and no error",
			func = function()
				local gone = fakePlayer({}, GryMod.Modes.SPEED)
				function gone:IsValid() return false end

				local sent
				expect(function() sent = ready(gone, 10) end).to.succeed()
				expect(#sent).to.equal(0)
			end
		}
	}
}
