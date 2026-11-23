-- Tests of the explosion rings of the radar (type 6, cl_hud_radar_pings.lua), GLuaTest format, client realm. The numbers are the original's (the explosion
-- list of CHUDRadar::Update, read in CryGame.dll): a ring lives 2 s, its radius in radar pixels is (age + 1) * 4 * min(size, 4), it is drawn at 10 times
-- that in percent, fades linearly to nothing, goes away when it is wider than 43 pixels or its centre is past 62.9 pixels; a ring of more than 4 makes
-- one echo of half the size after about 0.05 s.

local U = 0.01905

local function metres(m)
	return m / U
end

local function P()
	return GryMod.FlashRadar.Pings
end

-- Runs fn with the clock, the player's place, the range and the dice of the pings under the test's control, and puts everything back.
local function withPings(fn)
	local pings = P()
	local real = {Time = pings.Time, Origin = pings.Origin, Range = pings.Range, Random = pings.Random}
	local convar = GetConVar("gry_hud_radarpings")
	local realValue = convar:GetString()
	local clock = {now = 100}
	pings.Time = function() return clock.now end
	pings.Origin = function() return Vector(0, 0, 0) end
	pings.Range = function() return 75 end
	pings.Random = function() return 0.5 end -- r = 0 in -1 to 1
	pings.Clear()
	convar:SetString("1")

	local ok, err = pcall(fn, clock)

	pings.Clear()
	pings.Time, pings.Origin, pings.Range, pings.Random = real.Time, real.Origin, real.Range, real.Random
	convar:SetString(realValue)

	if not ok then
		error(err, 0)
	end
end

local function ring(ahead, right)
	return Vector(metres(ahead or 0), -metres(right or 0), 0)
end

return {
	groupName = "GryMod radar explosion rings (client)",
	cases = {
		-- fails without Pings.Radius / Pings.Alpha
		{
			name = "the ring's radius is (age + 1) * 4 * min(size, 4) radar pixels; the alpha falls straight from 1 to 0 over the 2 seconds",
			func = function(state)
				expect(P().Radius(4, 0)).to.equal(16)
				expect(P().Radius(2, 0.5)).to.equal(12)
				expect(P().Radius(8, 0)).to.equal(16) -- the drawing holds the size to 4
				expect(P().Radius(4, 1)).to.equal(32)
				expect(P().Alpha(0)).to.equal(1)
				expect(P().Alpha(1)).to.aboutEqual(0.5, 0.0001)
				expect(P().Alpha(2)).to.equal(0)
				expect(P().Alpha(3)).to.equal(0)
			end
		},
		-- fails without Pings.Add and the source it registers
		{
			name = "a ping becomes a type 6 marker: its place, 10 times the radius in percent, the faded alpha; the source is added with the first ping and removed with the last",
			func = function(state)
				withPings(function(clock)
					expect(GryMod.Radar.HasSource("gry_pings")).to.beFalse()
					P().Add(ring(30, 0), 4)
					expect(GryMod.Radar.HasSource("gry_pings")).to.beTrue()
					local buffer = {}
					expect(GryMod.FlashRadar.CollectMarkers(buffer)).to.equal(1)
					local m = buffer[1]
					expect(m.type).to.equal(6)
					expect(m.subtype).to.equal(0)
					expect(m.scale).to.aboutEqual(160, 0.01)
					expect(m.alpha).to.aboutEqual(1, 0.0001)
					expect(m.pos.x).to.aboutEqual(metres(30), 0.01)

					clock.now = 100.5
					GryMod.FlashRadar.CollectMarkers(buffer)
					expect(buffer[1].scale).to.aboutEqual(240, 0.01) -- 1.5 * 16 pixels
					expect(buffer[1].alpha).to.aboutEqual(0.75, 0.0001)

					clock.now = 102.01 -- past the 2 seconds
					expect(GryMod.FlashRadar.CollectMarkers(buffer)).to.equal(0)
					expect(P().Count()).to.equal(0)
					expect(GryMod.Radar.HasSource("gry_pings")).to.beFalse()
				end)
			end
		},
		{
			name = "a ring wider than 43 radar pixels is not drawn (a size 4 ring at 1.75 s is 44 wide), and neither is one whose centre is past 62.9 radar pixels (109.7 m at 75 m)",
			func = function(state)
				withPings(function(clock)
					P().Add(ring(30, 0), 4)
					clock.now = 101.7 -- 43.2 pixels? (2.7 * 16 = 43.2): past the limit
					local buffer = {}
					expect(GryMod.FlashRadar.CollectMarkers(buffer)).to.equal(0)

					P().Clear()
					clock.now = 100
					P().Add(ring(109, 0), 1)
					P().Add(ring(111, 0), 1)
					expect(GryMod.FlashRadar.CollectMarkers(buffer)).to.equal(1)
					expect(buffer[1].pos.x).to.aboutEqual(metres(109), 0.01)
				end)
			end
		},
		{
			name = "the range of the radar scales the reach: with 40 m a ring 60 m away is already past the limit",
			func = function(state)
				withPings(function(clock)
					P().Range = function() return 40 end
					P().Add(ring(55, 0), 1) -- 59 pixels at 40 m: kept
					P().Add(ring(60, 0), 1) -- 64.5 pixels: dropped
					local buffer = {}
					expect(GryMod.FlashRadar.CollectMarkers(buffer)).to.equal(1)
				end)
			end
		},
		-- fails without the echo
		{
			name = "a ring of more than 4 makes ONE echo of half its size after about 0.05 s (with the dice at 0); a ring of 4 or less makes none",
			func = function(state)
				withPings(function(clock)
					local buffer = {}
					P().Add(ring(30, 0), 6)
					clock.now = 100.04
					GryMod.FlashRadar.CollectMarkers(buffer)
					expect(P().Count()).to.equal(1)
					clock.now = 100.06
					GryMod.FlashRadar.CollectMarkers(buffer)
					expect(P().Count()).to.equal(2)
					expect(P().Size(2)).to.aboutEqual(3, 0.0001)
					expect(P().Born(2)).to.aboutEqual(100.06, 0.0001) -- the echo starts when it is made
					clock.now = 100.1
					GryMod.FlashRadar.CollectMarkers(buffer)
					expect(P().Count()).to.equal(2) -- once

					P().Clear()
					clock.now = 200
					P().Add(ring(30, 0), 4)
					clock.now = 200.5
					GryMod.FlashRadar.CollectMarkers(buffer)
					expect(P().Count()).to.equal(1)
				end)
			end
		},
		{
			name = "at most 16 rings are kept (the oldest goes first); a size held to 8 and above 0.5 on the way in",
			func = function(state)
				withPings(function(clock)
					for i = 1, 20 do
						clock.now = 100 + i * 0.001
						P().Add(ring(10, 0), 1)
					end

					expect(P().Count()).to.equal(16)
					expect(P().Born(1)).to.aboutEqual(100.005, 0.0001)
					P().Clear()
					P().Add(ring(10, 0), 50)
					expect(P().Size(1)).to.equal(8)
				end)
			end
		},
		-- fails without the client switch
		{
			name = "with the player's switch off (gry_hud_radarpings 0) a ping is not kept; a bad position is refused",
			func = function(state)
				withPings(function(clock)
					GetConVar("gry_hud_radarpings"):SetString("0")
					expect(P().Add(ring(10, 0), 4)).to.beFalse()
					expect(P().Count()).to.equal(0)
					GetConVar("gry_hud_radarpings"):SetString("1")
					expect(P().Add(nil, 4)).to.beFalse()
					expect(P().Add(Vector(0 / 0, 0, 0), 4)).to.beFalse()
					expect(P().Add(ring(10, 0), 4)).to.beTrue()
				end)
			end
		},
		-- fails without ReadMessage
		{
			name = "the message of the server: a position and the size in half metres; it adds the ring",
			func = function(state)
				withPings(function(clock)
					local real = {ReadVector = net.ReadVector, ReadUInt = net.ReadUInt}
					net.ReadVector = function() return ring(20, 0) end
					net.ReadUInt = function(bits) return bits == 5 and 8 or 0 end
					local ok, err = pcall(P().ReadMessage)
					net.ReadVector, net.ReadUInt = real.ReadVector, real.ReadUInt
					assert(ok, err)
					expect(P().Count()).to.equal(1)
					expect(P().Size(1)).to.equal(4)
				end)
			end
		}
	}
}
