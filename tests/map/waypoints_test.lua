-- Tests of the player's own objective points (GryMod.Map.Waypoints, lua/grymod/client/map/waypoints.lua), GLuaTest format, client realm. A right click on the big
-- map puts a point with a title; the point is an "own" objective of the client's mirror (cl_objectives.lua), so the big map, the minimap, the compass radar and
-- the markers of the binoculars show it with no code of their own. This file checks the rules of that module: the title, the file (a text, one point a line,
-- written and read back with a bad line in it), the ground under a click, the list and its limit, the mirror, the pick under the mouse and the switch. The disk
-- is replaced by a recorder (W.IO) and every convar and stand-in is put back in afterEach inside a pcall. Each case names the change whose absence makes it fail.

local W, Obj, Frame

local saved

local function setIO(files)
	W.IO = {
		Read = function(path) return files[path] end,
		Write = function(path, text) files[path] = text end,
		CreateDir = function() end
	}
end

local function view()
	local v = Frame.New({x = 100, y = 50, w = 800, h = 600}, {x0 = -4000, x1 = 4000, y0 = -4000, y1 = 4000})

	Frame.SetZoom(v, 2)
	Frame.CentreOn(v, 0, 0)

	return v
end

return {
	groupName = "GryMod big map: the player's own objective points",
	beforeEach = function(state)
		W, Obj, Frame = GryMod.Map.Waypoints, GryMod.Objectives, GryMod.Map.Frame
		expect(W ~= nil).to.beTrue()

		saved = {io = W.IO, switch = GetConVar("gry_map_waypoints"):GetString(), banner = GetConVar("gry_msg_objectives")}
		saved.bannerValue = saved.banner and saved.banner:GetString()

		-- the objective banner listens to the same hooks: no line and no sound for the test points
		if saved.banner then
			saved.banner:SetString("0")
		end

		GetConVar("gry_map_waypoints"):SetString("1")
		Obj.Reset()
		W.Reset()
		state.files = {}
		setIO(state.files)
	end,
	afterEach = function()
		pcall(function()
			W.Reset()
			Obj.Reset()
			W.IO = saved.io
			GetConVar("gry_map_waypoints"):SetString(saved.switch)

			if saved.banner and saved.bannerValue then
				saved.banner:SetString(saved.bannerValue)
			end
		end)
	end,
	cases = {
		{
			-- fails when the title is not trimmed, keeps a line break or a tab (they would break the file), is not cut at 128 bytes on a whole character, or an empty one is kept
			name = "CleanTitle: trimmed, line breaks and tabs become spaces, cut at 128 bytes on a whole character, nothing for an empty text or a value that is not a text",
			func = function()
				expect(W.CleanTitle("  Camp  ")).to.equal("Camp")
				expect(W.CleanTitle("a\tb\nc\r\nd")).to.equal("a b c d")
				expect(W.CleanTitle("")).to.beNil()
				expect(W.CleanTitle("   \t ")).to.beNil()
				expect(W.CleanTitle(nil)).to.beNil()
				expect(W.CleanTitle(12)).to.beNil()
				expect(#W.CleanTitle(string.rep("x", 300))).to.equal(128)

				-- 127 bytes then a two-byte letter: the cut at 128 would split it
				local cut = W.CleanTitle(string.rep("x", 127) .. "é")

				expect(#cut).to.equal(127)
				expect(utf8.len(cut) ~= nil).to.beTrue()
			end
		},
		{
			-- fails when the default title does not name the grid cell
			name = "DefaultTitle: 'Point C4' for a cell, 'Point' for none",
			func = function()
				expect(W.DefaultTitle("C4")).to.equal("Point C4")
				expect(W.DefaultTitle(nil)).to.equal("Point")
			end
		},
		{
			-- fails when a point does not come back as it went in, a title with odd characters is changed, a damaged line breaks the others, a file with another header
			-- is read, or more than MAX points are taken
			name = "Encode and Decode: the points come back as written, a bad line is dropped and the rest is kept, a file with no header or another version gives nothing, MAX points at most",
			func = function()
				local items = {
					{x = 100.5, y = -2000, z = 64, title = "Camp"},
					{x = -3.25, y = 4, z = -10.5, title = "Où \"ça\" ? [é] \\ ok"}
				}
				local back = W.Decode(W.Encode(items))

				expect(#back).to.equal(2)
				expect(back[1].x).to.aboutEqual(100.5, 0.06)
				expect(back[1].y).to.aboutEqual(-2000, 0.06)
				expect(back[1].z).to.aboutEqual(64, 0.06)
				expect(back[1].title).to.equal("Camp")
				expect(back[2].title).to.equal("Où \"ça\" ? [é] \\ ok")

				-- a damaged line (not a number, a missing field, a NaN, an empty title) is dropped, the others stay
				local text = "GRYWP 1\n1\t2\t3\tgood\nx\t2\t3\tnot a number\n1\t2\n1\t2\t3\t\nnan\t2\t3\tnan\n4\t5\t6\talso good\n"

				back = W.Decode(text)
				expect(#back).to.equal(2)
				expect(back[1].title).to.equal("good")
				expect(back[2].title).to.equal("also good")

				expect(#W.Decode("")).to.equal(0)
				expect(#W.Decode(nil)).to.equal(0)
				expect(#W.Decode("1\t2\t3\tno header\n")).to.equal(0)
				expect(#W.Decode("GRYWP 2\n1\t2\t3\tfuture\n")).to.equal(0)

				local many = {"GRYWP 1"}

				for i = 1, W.MAX + 10 do
					many[#many + 1] = i .. "\t0\t0\tp" .. i
				end

				expect(#W.Decode(table.concat(many, "\n"))).to.equal(W.MAX)
			end
		},
		{
			-- fails when a ground under a click is not found by going down from the top of the level, a sky brush stops the search, or an empty trace gives a number
			name = "GroundAt: the first solid surface under the top of the level, a sky brush is passed, nothing below gives nil",
			func = function()
				local calls = {}
				local function trace(x, y, from, to)
					calls[#calls + 1] = {x = x, y = y, from = from, to = to}

					return {Hit = true, HitSky = false, HitPos = {z = 40}}
				end

				expect(W.GroundAt(10, 20, 300, -100, trace)).to.equal(40)
				expect(calls[1].x).to.equal(10)
				expect(calls[1].y).to.equal(20)
				expect(calls[1].from).to.equal(300)
				expect(calls[1].to).to.equal(-100)

				-- the first surface is the sky: the search goes on under it
				local n = 0
				local function sky(x, y, from, to)
					n = n + 1

					if n == 1 then
						return {Hit = true, HitSky = true, HitPos = {z = 250}}
					end

					-- it goes on from just under the sky brush
					expect(from < 250).to.beTrue()

					return {Hit = true, HitSky = false, HitPos = {z = 12}}
				end

				expect(W.GroundAt(0, 0, 300, -100, sky)).to.equal(12)

				-- nothing hit: no ground
				expect(W.GroundAt(0, 0, 300, -100, function() return {Hit = false} end)).to.beNil()

				-- a sky that never ends does not loop for ever
				local m = 0

				expect(W.GroundAt(0, 0, 300, -100, function() m = m + 1 return {Hit = true, HitSky = true, HitPos = {z = 300 - m}} end)).to.beNil()
				expect(m <= 8).to.beTrue()
			end
		},
		{
			-- fails when Add does not make an own objective of the mirror with the title and the position, gives the same id twice, or does not save
			name = "Add: an own objective in the mirror (secondary, on the radar and with a marker, the title and the place), a new id each time, the file written",
			func = function(state)
				local id = W.Add(100, -200, 30, "Camp")

				expect(id).to.equal("gry_user_1")

				local o = Obj.Get(id)

				expect(o ~= nil).to.beTrue()
				expect(o.own).to.beTrue()
				expect(o.title).to.equal("Camp")
				expect(o.primary).to.beFalse()
				expect(o.radar).to.beTrue()
				expect(o.marker).to.beTrue()
				expect(o.state).to.equal("active")
				expect(o.pos.x).to.equal(100)
				expect(o.pos.y).to.equal(-200)
				expect(o.pos.z).to.equal(30)

				expect(W.Add(1, 2, 3, "Second")).to.equal("gry_user_2")
				expect(#W.List()).to.equal(2)

				-- the file holds both
				local path = W.Path()

				expect(state.files[path] ~= nil).to.beTrue()
				expect(#W.Decode(state.files[path])).to.equal(2)

				-- an empty title is not accepted by Add (the panel gives the default one)
				local bad, why = W.Add(1, 2, 3, "   ")

				expect(bad).to.beFalse()
				expect(type(why)).to.equal("string")
				expect(#W.List()).to.equal(2)

				-- a position that is not a number is refused
				expect((W.Add(0 / 0, 2, 3, "x"))).to.beFalse()
				expect((W.Add("1", 2, 3, "x"))).to.beFalse()
			end
		},
		{
			-- fails when the limit is not kept (the radar and the map walk the list at every frame)
			name = "Add: at most MAX points, the next one is refused with a reason and nothing changes",
			func = function()
				for i = 1, W.MAX do
					expect(W.Add(i, 0, 0, "p" .. i) ~= false).to.beTrue()
				end

				local id, why = W.Add(1, 1, 1, "one too many")

				expect(id).to.beFalse()
				expect(type(why)).to.equal("string")
				expect(#W.List()).to.equal(W.MAX)

				-- a removed point frees a place
				expect(W.Remove("gry_user_1")).to.beTrue()
				expect(W.Add(1, 1, 1, "now it fits") ~= false).to.beTrue()
			end
		},
		{
			-- fails when Remove leaves the objective in the mirror (the radar would go on showing it), does not save, or removes something that is not one of the player's points
			name = "Remove: gone from the mirror and the file; an unknown id and an objective of the server are left alone",
			func = function(state)
				local id = W.Add(0, 0, 0, "Camp")

				Obj.ApplySet({id = "mission", title = "Mission", description = "", primary = true, state = "active", main = false, radar = true, marker = true, pos = Vector(9, 9, 9), entIndex = 0})

				expect(W.Remove("mission")).to.beFalse()
				expect(Obj.Get("mission") ~= nil).to.beTrue()
				expect(W.Remove("nope")).to.beFalse()
				expect(W.Remove(id)).to.beTrue()
				expect(Obj.Get(id)).to.beNil()
				expect(#W.List()).to.equal(0)
				expect(#W.Decode(state.files[W.Path()])).to.equal(0)
				expect(W.Remove(id)).to.beFalse()
			end
		},
		{
			-- fails when Clear leaves a point, or touches the mission objectives
			name = "Clear: every point of the player is gone from the mirror and the file, the objectives of the server stay",
			func = function(state)
				W.Add(0, 0, 0, "a")
				W.Add(1, 1, 1, "b")
				Obj.ApplySet({id = "mission", title = "Mission", description = "", primary = true, state = "active", main = false, radar = true, marker = true, pos = Vector(9, 9, 9), entIndex = 0})

				expect(W.Clear()).to.equal(2)
				expect(#W.List()).to.equal(0)
				expect(#Obj.List()).to.equal(1)
				expect(Obj.List()[1].id).to.equal("mission")
				expect(#W.Decode(state.files[W.Path()])).to.equal(0)
			end
		},
		{
			-- fails when the points of the map are not read back (the whole point of keeping them), the ids go wrong after a load, or a file of another map is read
			name = "Load: the points of the file of this map come back into the mirror, with fresh ids; a missing or a damaged file gives none; Add goes on after them",
			func = function(state)
				state.files[W.Path()] = "GRYWP 1\n10\t20\t30\tFirst\n40\t50\t60\tSecond\n"
				state.files[W.PathFor("other_map")] = "GRYWP 1\n1\t1\t1\tElsewhere\n"

				expect(W.Load()).to.equal(2)
				expect(#W.List()).to.equal(2)
				expect(Obj.Get("gry_user_1").title).to.equal("First")
				expect(Obj.Get("gry_user_2").pos.y).to.equal(50)
				expect(W.Add(1, 2, 3, "Third")).to.equal("gry_user_3")

				-- loading again does not double them (the file holds the third one now: Add saved it)
				expect(W.Load()).to.equal(3)
				expect(#Obj.List()).to.equal(3)

				state.files[W.Path()] = nil
				expect(W.Load()).to.equal(0)
				expect(#Obj.List()).to.equal(0)

				state.files[W.Path()] = "garbage\0\1\2"
				expect(W.Load()).to.equal(0)
			end
		},
		{
			-- fails when the file name takes anything of the map name that is not a safe character (a path outside data/grymod/waypoints)
			name = "Path: one text file a map in data/grymod/waypoints, whatever characters the map name has",
			func = function()
				expect(W.PathFor("gm_construct")).to.equal("grymod/waypoints/gm_construct.txt")
				expect(W.PathFor("../../x/y z")).to.equal("grymod/waypoints/______x_y_z.txt")
				expect(W.PathFor("")).to.equal("grymod/waypoints/map.txt")
				expect(W.PathFor(nil)).to.equal("grymod/waypoints/map.txt")
			end
		},
		{
			-- fails when the switch does not take the points out of the mirror (and from the radar and the map with it), or loses them on the way (they are kept for when it is on again)
			name = "the switch gry_map_waypoints: off, the points leave the mirror but stay in the list and the file, Add is refused; on again, they come back",
			func = function(state)
				W.Add(0, 0, 0, "Camp")
				GetConVar("gry_map_waypoints"):SetString("0")
				W.Apply()

				expect(W.Enabled()).to.beFalse()
				expect(#Obj.List()).to.equal(0)
				expect(#W.List()).to.equal(1)
				expect(#W.Decode(state.files[W.Path()])).to.equal(1)

				local id, why = W.Add(1, 1, 1, "refused")

				expect(id).to.beFalse()
				expect(type(why)).to.equal("string")

				GetConVar("gry_map_waypoints"):SetString("1")
				W.Apply()
				expect(#Obj.List()).to.equal(1)
				expect(Obj.List()[1].title).to.equal("Camp")
				expect(Obj.List()[1].own).to.beTrue()
			end
		},
		{
			-- fails when the pick takes a point farther than the radius, takes the farther of two, or sees an objective of the server
			name = "Pick: the nearest point of the player within the radius of the mouse, nil beyond it, the server's objectives are never picked",
			func = function()
				local v = view()
				local a = W.Add(0, 0, 0, "centre")
				local b = W.Add(400, 0, 0, "right of it")
				local ax, ay = Frame.ToScreen(v, 0, 0)
				local bx, by = Frame.ToScreen(v, 400, 0)

				Obj.ApplySet({id = "mission", title = "Mission", description = "", primary = true, state = "active", main = false, radar = true, marker = true, pos = Vector(0, 0, 0), entIndex = 0})

				expect(W.Pick(v, ax, ay, 8)).to.equal(a)
				expect(W.Pick(v, ax + 5, ay + 5, 8)).to.equal(a)
				expect(W.Pick(v, ax + 7, ay + 7, 8)).to.beNil() -- 9.9 pixels away
				expect(W.Pick(v, bx, by, 8)).to.equal(b)
				expect(W.Pick(v, ax, ay + 300, 8)).to.beNil()

				-- two points under the mouse: the nearer one
				local c = W.Add(1, 0, 0, "next to centre")
				local cx, cy = Frame.ToScreen(v, 1, 0)

				expect(cx ~= ax or cy ~= ay).to.beTrue()
				expect(W.Pick(v, cx, cy, 20)).to.equal(c)

				-- off: nothing to pick
				GetConVar("gry_map_waypoints"):SetString("0")
				W.Apply()
				expect(W.Pick(v, ax, ay, 8)).to.beNil()
			end
		}
	}
}
