-- Tests of what the server and the client agree on for the radar contacts (GryMod.RadarShared), GLuaTest format, run in
-- either realm: the constants of the original radar and the compact message of a contact list.

local function R()
	return GryMod.RadarShared
end

-- Runs fn with the net library's integer readers and writers replaced by a queue; the queue is returned. The functions
-- are put back whatever happens.
local function withBuffer(fn)
	local queue, head, bits = {}, 0, 0
	local real = {
		WriteUInt = net.WriteUInt, WriteInt = net.WriteInt, WriteBool = net.WriteBool,
		ReadUInt = net.ReadUInt, ReadInt = net.ReadInt, ReadBool = net.ReadBool
	}

	net.WriteUInt = function(v, n) queue[#queue + 1] = v bits = bits + n end
	net.WriteInt = function(v, n) queue[#queue + 1] = v bits = bits + n end
	net.WriteBool = function(v) queue[#queue + 1] = v and 1 or 0 bits = bits + 1 end
	net.ReadUInt = function(n) head = head + 1 return queue[head] end
	net.ReadInt = function(n) head = head + 1 return queue[head] end
	net.ReadBool = function() head = head + 1 return queue[head] == 1 end

	local ok, err = pcall(fn, function() return bits end)

	for name, f in pairs(real) do
		net[name] = f
	end

	assert(ok, err)
end

return {
	groupName = "GryMod radar wire format",
	cases = {
		{
			name = "the rules of the original radar are in one place",
			func = function(state)
				expect(R()).toNot.beNil()
				expect(R().RANGE).to.equal(75) -- metres, CHUDRadar::Update
				expect(R().PIXELS).to.equal(43) -- stage pixels for the range
				expect(R().GATE_PIXELS).to.equal(15) -- an alerted hostile is first noticed within 15 pixels
				expect(R().MARKER_SECONDS).to.equal(10)
				expect(R().METRES_PER_UNIT).to.aboutEqual(0.01905, 0.00001)
				-- 15 pixels of 43 for 75 m is 26.2 m
				expect(R().GateMetres()).to.aboutEqual(15 * 75 / 43, 0.001)
				expect(R().GateUnits()).to.aboutEqual(15 * 75 / 43 / 0.01905, 0.5)
				-- the entities are looked for as far as the radar window reaches (no pop-in at the edge): its farthest corner is 90 pixels of 43 away, so at least
				-- 2.09 radiuses (tests/minimap/radar_frame_test.lua checks it against GryMod.FlashRadar.FRAME)
				expect(R().SCAN_FACTOR >= 90 / 43).to.beTrue()
				expect(R().ScanUnits()).to.aboutEqual(75 * R().SCAN_FACTOR / 0.01905, 0.5)
			end
		},
		{
			name = "the radius may go down to 5 metres: ClampRange keeps 5 (not the old 20), and the gate and the search radius follow it without a floor of their own",
			func = function(state)
				expect(R().MIN_RANGE).to.equal(5)
				expect(R().MAX_RANGE).to.equal(100)
				expect(R().ClampRange(5)).to.equal(5)
				expect(R().ClampRange(4.6)).to.equal(5)
				expect(R().ClampRange(1)).to.equal(5)
				expect(R().ClampRange(10)).to.equal(10)
				expect(R().ClampRange(0)).to.equal(75) -- no usable number is still the original's
				-- at 5 m: 15 pixels of 43 are 1.74 m, the search radius is 2.1 radiuses (10.5 m): both finite and above zero
				expect(R().GateMetres(5)).to.aboutEqual(15 * 5 / 43, 0.001)
				expect(R().GateUnits(5)).to.aboutEqual(15 * 5 / 43 / 0.01905, 0.01)
				expect(R().ScanUnits(5)).to.aboutEqual(5 * R().SCAN_FACTOR / 0.01905, 0.01)
				-- the search still reaches the farthest corner of the glass (90 pixels of 43 for 5 m is 10.47 m)
				expect(R().ScanUnits(5) * 0.01905 >= 90 / 43 * 5).to.beTrue()
			end
		},
		{
			name = "a contact list goes through the message and comes back, quantised",
			func = function(state)
				local contacts = {
					{id = 5, x = 1000, y = -2000, z = 30, yaw = 90, type = 1, sub = 4, marker = false, big = false},
					{id = 300, x = -16000, y = 16000, z = -500, yaw = 359, type = 3, sub = 2, marker = true, big = true}
				}
				local back

				withBuffer(function(bits)
					R().Write(contacts)
					back = R().Read()
				end)

				expect(#back).to.equal(2)
				expect(back[1].id).to.equal(5)
				expect(back[1].type).to.equal(1)
				expect(back[1].sub).to.equal(4)
				expect(back[1].marker).to.beFalse()
				expect(back[1].big).to.beFalse()
				expect(math.abs(back[1].x - 1000) <= 4).to.beTrue()
				expect(math.abs(back[1].y + 2000) <= 4).to.beTrue()
				expect(math.abs(back[1].z - 30) <= 4).to.beTrue()
				expect(math.abs(back[1].yaw - 90) <= 0.71).to.beTrue()
				expect(back[2].id).to.equal(300)
				expect(back[2].type).to.equal(3)
				expect(back[2].sub).to.equal(2)
				expect(back[2].marker).to.beTrue()
				expect(back[2].big).to.beTrue()
				expect(math.abs(back[2].x + 16000) <= 4).to.beTrue()
				expect(math.abs(back[2].y - 16000) <= 4).to.beTrue()
				expect(math.abs(back[2].yaw - 359) <= 0.71).to.beTrue()
			end
		},
		{
			name = "the ally colour is a subtype of its own that fits the three bits of the message and goes through it",
			func = function(state)
				expect(R().SUB_ALLY).to.equal(5) -- the movie's subtypes are 0 to 4
				expect(R().SUB_ALLY < 8).to.beTrue() -- 3 bits
				local back

				withBuffer(function(bits)
					R().Write({{id = 9, x = 80, y = 16, z = 0, yaw = 0, type = 2, sub = R().SUB_ALLY, marker = false, big = false}})
					back = R().Read()
				end)

				expect(back[1].sub).to.equal(R().SUB_ALLY)
				expect(back[1].type).to.equal(2)
				-- an ally is not the same message as the neutral at the same place: a change of relation is sent
				local ally = {{id = 5, x = 0, y = 0, z = 0, yaw = 0, type = 1, sub = R().SUB_ALLY, marker = false, big = false}}
				local neutral = {{id = 5, x = 0, y = 0, z = 0, yaw = 0, type = 1, sub = 0, marker = false, big = false}}
				expect(R().Same(ally, neutral)).to.beFalse()
				expect(R().Same(ally, ally)).to.beTrue()
			end
		},
		{
			name = "a contact costs about nine bytes and an empty list one",
			func = function(state)
				local one = {{id = 5, x = 1, y = 2, z = 3, yaw = 4, type = 1, sub = 1, marker = false, big = false}}
				local used

				withBuffer(function(bits)
					R().Write(one)
					used = bits()
				end)

				expect(used <= 8 + 72).to.beTrue()
				expect(used >= 8 + 60).to.beTrue()

				withBuffer(function(bits)
					R().Write({})
					used = bits()
				end)

				expect(used <= 8).to.beTrue()
			end
		},
		{
			name = "a list is cut at the limit and a position past the map is clamped, not wrapped",
			func = function(state)
				local many = {}

				for i = 1, R().MAX_CONTACTS + 10 do
					many[i] = {id = i, x = 40000, y = -40000, z = 0, yaw = 0, type = 1, sub = 0, marker = false, big = false}
				end

				local back

				withBuffer(function()
					R().Write(many)
					back = R().Read()
				end)

				expect(#back).to.equal(R().MAX_CONTACTS)
				expect(back[1].x > 30000).to.beTrue()
				expect(back[1].y < -30000).to.beTrue()
			end
		},
		{
			name = "yaws below 0 and above 360 land on the circle",
			func = function(state)
				local back

				withBuffer(function()
					R().Write({
						{id = 1, x = 0, y = 0, z = 0, yaw = -90, type = 1, sub = 0, marker = false, big = false},
						{id = 2, x = 0, y = 0, z = 0, yaw = 450, type = 1, sub = 0, marker = false, big = false}
					})
					back = R().Read()
				end)

				expect(math.abs(back[1].yaw - 270) <= 0.71).to.beTrue()
				expect(math.abs(back[2].yaw - 90) <= 0.71).to.beTrue()
			end
		},
		{
			name = "two lists are the same when every quantised value is the same",
			func = function(state)
				local a = {{id = 5, x = 1000, y = -2000, z = 30, yaw = 90, type = 1, sub = 4, marker = false, big = false}}
				local b = {{id = 5, x = 1001, y = -1999, z = 31, yaw = 90.1, type = 1, sub = 4, marker = false, big = false}}
				local c = {{id = 5, x = 1100, y = -2000, z = 30, yaw = 90, type = 1, sub = 4, marker = false, big = false}}
				local d = {{id = 5, x = 1000, y = -2000, z = 30, yaw = 90, type = 1, sub = 3, marker = false, big = false}}
				expect(R().Same(a, b)).to.beTrue()
				expect(R().Same(a, c)).to.beFalse()
				expect(R().Same(a, d)).to.beFalse()
				expect(R().Same({}, {})).to.beTrue()
				expect(R().Same(a, {})).to.beFalse()
			end
		}
	}
}
