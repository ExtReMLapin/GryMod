-- Tests of the numbers the server and the client share for the radar's explosion pings (GryMod.RadarShared, sh_radar.lua), GLuaTest format, run in either
-- realm. The numbers come from the original radar (the explosion list of CHUDRadar::Update): a ping lives 2 s, its size is held to 8, rings above 4 echo.

local function S()
	return GryMod.RadarShared
end

return {
	groupName = "GryMod radar pings (shared numbers)",
	cases = {
		-- fails without the PING_* constants in sh_radar.lua
		{
			name = "the numbers of the original: life 2 s, size held to 8, the reach of the explosion event 250 m, a ring above 4 echoes",
			func = function(state)
				expect(S().PING_LIFETIME).to.equal(2)
				expect(S().PING_MAX_SIZE).to.equal(8)
				expect(S().PING_RANGE).to.equal(250)
				expect(S().PING_ECHO_ABOVE).to.equal(4)
				expect(S().PING_DRAW_MAX_SIZE).to.equal(4)
			end
		},
		-- fails without S.PingSize
		{
			name = "PingSize turns a kind into a size: a name, a number (held between 0.5 and 8), nothing is the explosion; anything else is not a kind",
			func = function(state)
				expect(S().PingSize(nil)).to.equal(4)
				expect(S().PingSize("explosion")).to.equal(4)
				expect(S().PingSize("small")).to.equal(2)
				expect(S().PingSize("big")).to.equal(8)
				expect(S().PingSize(3)).to.equal(3)
				expect(S().PingSize(100)).to.equal(8)
				expect(S().PingSize(0.1)).to.equal(0.5)
				expect(S().PingSize("huge")).to.beNil()
				expect(S().PingSize(true)).to.beNil()
				expect(S().PingSize({})).to.beNil()
				expect(S().PingSize(0 / 0)).to.beNil()
			end
		},
		-- fails without S.PingSizeOfRadius
		{
			name = "the size of an env_explosion: its radius in units turned to metres and held; the default magnitude 100 (radius 250 units, 4.76 m) is a ring that echoes",
			func = function(state)
				expect(S().PingSizeOfRadius(250)).to.aboutEqual(250 * 0.01905, 0.001)
				expect(S().PingSizeOfRadius(250) > S().PING_ECHO_ABOVE).to.beTrue()
				expect(S().PingSizeOfRadius(5)).to.equal(0.5) -- a firecracker is held to the smallest
				expect(S().PingSizeOfRadius(100000)).to.equal(8)
				expect(S().PingSizeOfRadius(nil)).to.beNil()
				expect(S().PingSizeOfRadius(0 / 0)).to.beNil()
			end
		},
		-- fails without S.PingToWire / PingFromWire
		{
			name = "the size travels in 5 bits (half metres): written and read back it is the same to half a metre, and never 0",
			func = function(state)
				expect(S().PingToWire(0.5)).to.equal(1)
				expect(S().PingToWire(4)).to.equal(8)
				expect(S().PingToWire(8)).to.equal(16)
				expect(S().PingToWire(0.01)).to.equal(1)
				expect(S().PingToWire(50)).to.equal(16)
				expect(S().PingFromWire(8)).to.equal(4)
				expect(S().PingFromWire(0)).to.equal(0.5)
				expect(S().PingFromWire(31)).to.equal(8)
			end
		}
	}
}
