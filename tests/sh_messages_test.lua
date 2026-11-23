-- Tests of the shared data of the HUD text lines (lua/grymod/sh_messages.lua), GLuaTest format, runs in either realm: the lanes, the
-- cleaning of a text, the data of the event "message" and what a received event is read as, the speed of a line with a duration, and the
-- move of the lines of a lane when a new one comes in. Pure: nothing is drawn, nothing is sent.

local M = GryMod.Messages

return {
	groupName = "GryMod text lines: shared data",
	cases = {
		{
			-- fails without Messages.LaneName
			name = "a lane is a name of the list or the number 1 to 4 of the original; nothing is the top lane; the rest is not a lane",
			func = function()
				expect(M.LaneName(nil)).to.equal("top")
				expect(M.LaneName("status")).to.equal("status")
				expect(M.LaneName(1)).to.equal("top")
				expect(M.LaneName(2)).to.equal("middle")
				expect(M.LaneName(3)).to.equal("status")
				expect(M.LaneName(4)).to.equal("crosshair")
				expect(M.LaneName(5)).to.beNil()
				expect(M.LaneName(0)).to.beNil()
				expect(M.LaneName(1.5)).to.beNil()
				expect(M.LaneName("bottom")).to.beNil()
				expect(M.LaneName(true)).to.beNil()
				expect(M.LaneName({})).to.beNil()
			end
		},
		{
			-- fails without Messages.Clean
			name = "a text is one line without control characters or spaces at the ends; an empty one is nothing",
			func = function()
				expect(M.Clean("  hello \n world\t")).to.equal("hello world")
				expect(M.Clean("a\r\nb")).to.equal("a b")
				expect(M.Clean("")).to.beNil()
				expect(M.Clean("   \n ")).to.beNil()
				expect(M.Clean(nil)).to.beNil()
				expect(M.Clean(12)).to.beNil()
				expect(M.Clean({})).to.beNil()
			end
		},
		{
			-- fails without Messages.Build
			name = "Build makes the data of the event: the text, and only the options that are valid; a bad one is refused with a reason",
			func = function()
				local data = M.Build("HELLO", {lane = "status", sound = "grymod/hud/hud_activate_01.wav", duration = 3})

				expect(data.text).to.equal("HELLO")
				expect(data.lane).to.equal("status")
				expect(data.sound).to.equal("grymod/hud/hud_activate_01.wav")
				expect(data.duration).to.equal(3)

				local plain = M.Build("HELLO")
				expect(plain.text).to.equal("HELLO")
				expect(plain.lane).to.beNil() -- the HUD puts it on the top lane itself
				expect(plain.sound).to.beNil()

				expect(M.Build("x", {lane = 3}).lane).to.equal("status")
				expect(M.Build("x", {duration = 0.01}).duration).to.equal(M.MIN_DURATION)
				expect(M.Build("x", {duration = 1000}).duration).to.equal(M.MAX_DURATION)

				for _, case in ipairs({
					{"", nil}, {nil, nil}, {12, nil},
					{string.rep("a", M.MAX_TEXT + 1), nil},
					{"x", 5}, {"x", {lane = "nowhere"}}, {"x", {lane = 9}}, {"x", {sound = 5}}, {"x", {sound = ""}},
					{"x", {sound = string.rep("s", M.MAX_TEXT + 1)}}, {"x", {duration = "long"}}, {"x", {duration = 0 / 0}}, {"x", {duration = math.huge}}
				}) do
					local ok, reason = M.Build(case[1], case[2])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(#M.Build(string.rep("a", M.MAX_TEXT)).text).to.equal(M.MAX_TEXT)
			end
		},
		{
			-- fails without the line table of the suit's own lines
			name = "the suit's own lines have their text, their lane and a setting each, and every convar name is its own",
			func = function()
				local seen = {}

				for _, key in ipairs(M.LineKeys()) do
					local line = M.Lines[key]

					expect(#line.text > 0 and #line.text <= M.MAX_TEXT).to.beTrue()
					expect(M.LaneName(line.lane)).to.equal(line.lane)
					expect(#line.label > 0 and #line.label <= 40).to.beTrue() -- a short label: the menu cuts a long one
					expect(string.sub(line.convar, 1, 8)).to.equal("gry_msg_")
					expect(seen[line.convar]).to.beNil()
					seen[line.convar] = true
				end

				-- the texts of the original game
				expect(M.Lines.cloak_disabled.text).to.equal("Temperature Camo: Disabled!")
				expect(M.Lines.cloak_health.text).to.equal("Temperature Camo: Health too low!")
				expect(M.Lines.killed_friend.text).to.equal("YOU KILLED A FRIENDLY!")
				expect(#M.LineKeys()).to.equal(3)
			end
		},
		{
			-- fails without Messages.Resolve; the second check fails with the first version of it, where a line without a lane in the data
			-- lost its own lane to the default one (LaneName(nil) is "top")
			name = "Resolve reads a text, or a suit line by its key: the line keeps its own lane unless the data names another",
			func = function()
				local info = M.Resolve({text = " hi ", lane = "crosshair", duration = 2, sound = "a/b.wav"})
				expect(info.text).to.equal("hi")
				expect(info.lane).to.equal("crosshair")
				expect(info.duration).to.equal(2)
				expect(info.sound).to.equal("a/b.wav")
				expect(info.line).to.beNil()

				expect(M.Resolve({text = "hi"}).lane).to.equal("top")

				local line = M.Resolve({line = "cloak_disabled"})
				expect(line.text).to.equal("Temperature Camo: Disabled!")
				expect(line.lane).to.equal("status")
				expect(line.line).to.equal("cloak_disabled")
				expect(M.Resolve({line = "cloak_disabled", lane = "top"}).lane).to.equal("top")
				expect(M.Resolve({line = "killed_friend"}).lane).to.equal("middle")
			end
		},
		{
			-- fails without the lineOn test of Resolve
			name = "Resolve gives nothing for a line the player turned off, an unknown line, a missing text, or something that is not data",
			func = function()
				local off = function(key) return key ~= "cloak_health" end

				expect(M.Resolve({line = "cloak_health"}, off)).to.beNil()
				expect(M.Resolve({line = "cloak_disabled"}, off)).to.exist()
				expect(M.Resolve({line = "nothing"})).to.beNil()
				expect(M.Resolve({line = 5})).to.beNil()
				expect(M.Resolve({})).to.beNil()
				expect(M.Resolve({text = "  "})).to.beNil()
				expect(M.Resolve(nil)).to.beNil()
				expect(M.Resolve("text")).to.beNil()
			end
		},
		{
			-- fails if Resolve trusted what it receives
			name = "Resolve never trusts the data: a long text is cut, a bad lane or sound or duration is dropped, not an error",
			func = function()
				local info = M.Resolve({text = string.rep("b", 500), lane = "nowhere", sound = 7, duration = "soon"})

				expect(#info.text).to.equal(M.MAX_TEXT)
				expect(info.lane).to.equal("top")
				expect(info.sound).to.beNil()
				expect(info.duration).to.beNil()
				expect(M.Resolve({text = "x", duration = 99999}).duration).to.equal(M.MAX_DURATION)
				expect(M.Resolve({text = "x", duration = 0 / 0}).duration).to.beNil()
			end
		},
		{
			-- fails without Messages.SpeedFor
			name = "a line with a duration plays the movie faster or slower so that its life lasts that long; the movie's own life is 5 seconds",
			func = function()
				expect(M.SpeedFor(nil)).to.equal(1)
				expect(M.SpeedFor(5)).to.equal(1)
				expect(M.SpeedFor(10)).to.equal(0.5)
				expect(M.SpeedFor(2.5)).to.equal(2)
				expect(M.SpeedFor(0)).to.equal(1)
				expect(M.SpeedFor(-3)).to.equal(1)
				expect(M.SpeedFor("a")).to.equal(1)
				expect(M.SpeedFor(0.001)).to.equal(10) -- held at the shortest life, 0.5 s
			end
		},
		{
			-- fails without Messages.Shift
			name = "a new line takes the last place and every line moves one place up; the oldest one leaves; the list keeps its length",
			func = function()
				local a, b, c, d = {text = "a"}, {text = "b"}, {text = "c"}, {text = "d"}
				local empty = {frame = 1, speed = 1}
				local items = {empty, a, b}
				local shifted = M.Shift(items, c)

				expect(#shifted).to.equal(3)
				expect(shifted[1]).to.equal(a)
				expect(shifted[2]).to.equal(b)
				expect(shifted[3]).to.equal(c)
				-- the list it was given is not changed
				expect(items[1]).to.equal(empty)
				expect(items[3]).to.equal(b)

				local again = M.Shift(shifted, d)
				expect(again[1]).to.equal(b)
				expect(again[3]).to.equal(d)

				-- a lane of one line: the new line replaces it
				expect(M.Shift({a}, b)[1]).to.equal(b)
				expect(#M.Shift({a}, b)).to.equal(1)
			end
		}
	}
}
