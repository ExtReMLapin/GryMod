-- Tests of the HUD event message of the extension API (GryMod.API.CheckHUDEvent, WriteHUDEvent, ReadHUDEvent in
-- lua/grymod/sh_api.lua), GLuaTest format, runs in either realm: the payload is a name and a small table of numbers,
-- strings and booleans, bounded in size, and it goes through the message and comes back. The server only sends what
-- passes CheckHUDEvent, and the client reads with the same bounds.

local function API()
	return GryMod.API
end

-- Runs fn with the net library's readers and writers replaced by a queue (the real ones are put back whatever happens).
local function withBuffer(fn)
	local queue, head = {}, 0
	local names = {"WriteString", "WriteUInt", "WriteBool", "WriteDouble", "ReadString", "ReadUInt", "ReadBool", "ReadDouble"}
	local real = {}

	for _, n in ipairs(names) do real[n] = net[n] end

	net.WriteString = function(v) queue[#queue + 1] = v end
	net.WriteUInt = function(v) queue[#queue + 1] = v end
	net.WriteBool = function(v) queue[#queue + 1] = v end
	net.WriteDouble = function(v) queue[#queue + 1] = v end
	net.ReadString = function() head = head + 1 return queue[head] end
	net.ReadUInt = function() head = head + 1 return queue[head] end
	net.ReadBool = function() head = head + 1 return queue[head] end
	net.ReadDouble = function() head = head + 1 return queue[head] end

	local ok, err = pcall(fn, queue)

	for n, f in pairs(real) do net[n] = f end

	assert(ok, err)
end

local function rejects(name, data)
	local ok, reason = API().CheckHUDEvent(name, data)
	expect(ok).to.beFalse()
	expect(isstring(reason)).to.beTrue()
end

return {
	groupName = "GryMod extension API: HUD event message (shared)",
	cases = {
		{
			name = "the limits are told (name, fields, key and string sizes) so an addon can read them",
			func = function()
				local L = API().HUDEventLimits

				expect(L.name).to.equal(32)
				expect(L.fields).to.equal(8)
				expect(L.key).to.equal(24)
				expect(L.string).to.equal(128)
			end
		},
		{
			name = "CheckHUDEvent accepts a name alone, an empty table and numbers, strings and booleans",
			func = function()
				local A = API()

				expect(A.CheckHUDEvent("boot")).to.beTrue()
				expect(A.CheckHUDEvent("boot", nil)).to.beTrue()
				expect(A.CheckHUDEvent("my_event2", {})).to.beTrue()
				expect(A.CheckHUDEvent("malfunction", {seconds = 5.5, reason = "emp", loud = false, negative = -3})).to.beTrue()
			end
		},
		{
			name = "CheckHUDEvent refuses a name that is missing, not a string, too long, or has anything but letters, digits and underscore",
			func = function()
				rejects(nil)
				rejects("")
				rejects(42)
				rejects({})
				rejects("a b")
				rejects("a.b")
				rejects("it's")
				rejects(string.rep("n", 33))
				expect(API().CheckHUDEvent(string.rep("n", 32))).to.beTrue()
			end
		},
		{
			name = "CheckHUDEvent refuses a payload that is not a table, has too many fields, a bad key, or a value that is not a number (finite), string or boolean",
			func = function()
				rejects("e", "text")
				rejects("e", 5)
				rejects("e", {[1] = "array"})
				rejects("e", {[true] = 1})
				rejects("e", {[string.rep("k", 25)] = 1})
				rejects("e", {["bad key"] = 1})
				rejects("e", {f = function() end})
				rejects("e", {t = {}})
				rejects("e", {n = 0 / 0})
				rejects("e", {n = math.huge})
				rejects("e", {s = string.rep("x", 129)})

				local many = {}
				for i = 1, 9 do many["k" .. i] = i end
				rejects("e", many)

				many.k9 = nil
				expect(API().CheckHUDEvent("e", many)).to.beTrue()
				expect(API().CheckHUDEvent("e", {s = string.rep("x", 128), k = string.rep("k", 24)})).to.beTrue()
			end
		},
		{
			name = "a payload goes through the message and comes back with the same name and the same values (numbers exact)",
			func = function()
				local sent = {seconds = 4.123456789, reason = "emp burst", loud = true, quiet = false, zero = 0, neg = -17.5}
				local gotName, gotData

				withBuffer(function()
					API().WriteHUDEvent("malfunction", sent)
					gotName, gotData = API().ReadHUDEvent()
				end)

				expect(gotName).to.equal("malfunction")

				for k, v in pairs(sent) do
					expect(gotData[k]).to.equal(v)
				end

				local count = 0
				for _ in pairs(gotData) do count = count + 1 end
				expect(count).to.equal(6)
			end
		},
		{
			name = "a name alone comes back with an empty table",
			func = function()
				local gotName, gotData

				withBuffer(function()
					API().WriteHUDEvent("reboot")
					gotName, gotData = API().ReadHUDEvent()
				end)

				expect(gotName).to.equal("reboot")
				expect(istable(gotData)).to.beTrue()
				expect(next(gotData)).to.beNil()
			end
		},
		{
			name = "the reader drops a message that breaks the bounds (too many fields, a bad name, an unknown value type, an oversized string) instead of trusting it",
			func = function()
				local A = API()

				-- name, field count, then fields: key, type (0 number, 1 string, 2 boolean), value
				local function read(...)
					local items, name, data = {...}, nil, nil

					withBuffer(function(queue)
						for _, v in ipairs(items) do queue[#queue + 1] = v end
						name, data = A.ReadHUDEvent()
					end)

					return name, data
				end

				expect(read("ok", 0)).to.equal("ok")
				expect(read("bad name", 0)).to.beNil()
				expect(read("", 0)).to.beNil()
				expect(read("ok", 9)).to.beNil()
				expect(read("ok", 1, "k", 3, 1)).to.beNil() -- a type that does not exist
				expect(read("ok", 1, "bad key", 0, 1)).to.beNil()
				expect(read("ok", 1, "k", 1, string.rep("x", 129))).to.beNil()
				expect(read("ok", 1, "k", 0, 0 / 0)).to.beNil()

				local name, data = read("ok", 2, "a", 0, 7, "b", 2, true)
				expect(name).to.equal("ok")
				expect(data.a).to.equal(7)
				expect(data.b).to.equal(true)
			end
		}
	}
}
