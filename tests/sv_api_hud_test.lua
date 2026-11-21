-- Tests of the HUD events the server sends (GryMod.API.HUDEvent(players, name, data), lua/grymod/server/sv_api.lua),
-- GLuaTest format, server realm: one net message (gry_api_hud) to the players asked for, nothing for a recipient that is
-- not a valid player, nothing for a payload that breaks the bounds. The net functions are replaced by recorders, so
-- nothing goes to the real client; the wire format itself is tested in sh_api_hud_test.lua.

local function ply()
	return player.GetAll()[1]
end

local real = {}
local sent, started, writes

local function spy()
	for _, n in ipairs({"Start", "Send", "WriteString", "WriteUInt", "WriteBool", "WriteDouble"}) do
		real[n] = net[n]
	end

	sent, started, writes = {}, {}, {}

	net.Start = function(name) started[#started + 1] = name end
	net.Send = function(recipients) sent[#sent + 1] = recipients end
	net.WriteString = function(v) writes[#writes + 1] = v end
	net.WriteUInt = function(v) writes[#writes + 1] = v end
	net.WriteBool = function(v) writes[#writes + 1] = v end
	net.WriteDouble = function(v) writes[#writes + 1] = v end
end

local function unspy()
	for n, f in pairs(real) do net[n] = f end

	real = {}
end

return {
	groupName = "GryMod extension API: HUD events, server side",
	beforeEach = function()
		local p = ply()
		if not p:Alive() then p:Spawn() end

		spy()
	end,
	afterEach = function()
		unspy()
	end,
	cases = {
		{
			name = "the net message exists, and the part is advertised",
			func = function()
				unspy()
				expect(util.NetworkStringToID("gry_api_hud") ~= 0).to.beTrue()
				expect(isfunction(GryMod.API.HUDEvent)).to.beTrue()
				expect(GryMod.API.Has("hudevents")).to.beTrue()
			end
		},
		{
			name = "an event for one player: one message gry_api_hud with the name and the data, sent to that player only",
			func = function()
				local p = ply()
				local ok = GryMod.API.HUDEvent(p, "malfunction", {seconds = 3})

				expect(ok).to.beTrue()
				expect(#started).to.equal(1)
				expect(started[1]).to.equal("gry_api_hud")
				expect(#sent).to.equal(1)
				expect(#sent[1]).to.equal(1)
				expect(sent[1][1]).to.equal(p)
				expect(writes[1]).to.equal("malfunction")
				expect(writes[2]).to.equal(1) -- one field
				expect(writes[3]).to.equal("seconds")
			end
		},
		{
			name = "an event with no data is just the name",
			func = function()
				expect(GryMod.API.HUDEvent(ply(), "boot")).to.beTrue()
				expect(writes[1]).to.equal("boot")
				expect(writes[2]).to.equal(0)
				expect(#writes).to.equal(2)
			end
		},
		{
			name = "an event for a list of players: the ones that are not valid players (NULL, text, numbers, the world) are left out",
			func = function()
				local p = ply()
				local ok = GryMod.API.HUDEvent({p, NULL, "everyone", 5, game.GetWorld()}, "reboot")

				expect(ok).to.beTrue()
				expect(#sent).to.equal(1)
				expect(#sent[1]).to.equal(1)
				expect(sent[1][1]).to.equal(p)
			end
		},
		{
			name = "no valid recipient (nil, NULL, a table of junk, text, a number, an empty list): refused with a reason, nothing sent",
			func = function()
				for _, target in ipairs({NULL, "all", 42, true, {}, {NULL, "x"}, {game.GetWorld()}}) do
					local ok, reason = GryMod.API.HUDEvent(target, "boot")
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				local ok = GryMod.API.HUDEvent(nil, "boot")
				expect(ok).to.beFalse()
				expect(#started).to.equal(0)
				expect(#sent).to.equal(0)
			end
		},
		{
			name = "a payload that breaks the bounds is refused with the reason and nothing is sent (name, fields, value types, sizes)",
			func = function()
				local p = ply()
				local many = {}
				for i = 1, 9 do many["k" .. i] = i end

				for _, args in ipairs({
					{"bad name", nil},
					{"", nil},
					{string.rep("n", 33), nil},
					{"e", "text"},
					{"e", many},
					{"e", {f = function() end}},
					{"e", {n = 0 / 0}},
					{"e", {s = string.rep("x", 200)}}
				}) do
					local ok, reason = GryMod.API.HUDEvent(p, args[1], args[2])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(#started).to.equal(0)
				expect(#sent).to.equal(0)
			end
		}
	}
}
