-- Tests of the binoculars drawn from the original Scaleform movie (GryMod.FlashBinoculars), GLuaTest format,
-- client realm. Needs the converted movie lua/grymod/flash/hud_binoculars.lua.

local function newBinoculars()
	return GryMod.FlashBinoculars.New(GryMod.Flash.Load("hud_binoculars"))
end

local function run(b, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		b:Update(1 / 30)
	end
end

-- the strength (0 to 1) of the vignette, the full-screen black gradient of the film: the colour transform of the picture
-- held by the clip called Alpha (its alpha is a multiplier of 1 when it has none)
local function vignetteAlpha(b)
	local entry = b.root:Find("Root.Alpha"):EntryAt(1)

	return entry.cx and entry.cx[4] or 1
end

-- the text of the field called `name` held directly by `clip`
local function field(clip, name)
	local entry = clip.names[name]

	return entry and entry.text
end

return {
	groupName = "GryMod binoculars (Flash)",
	cases = {
		{
			name = "the binoculars are hidden until shown, and the colour holders never show",
			func = function(state)
				local b = newBinoculars()
				expect(b:IsShown()).to.beFalse()
				b:Show()
				expect(b:IsShown()).to.beTrue()

				for _, name in ipairs({"Line", "Over", "Text"}) do
					expect(b.root:Child(name).visible).to.beFalse()
				end
			end
		},
		{
			name = "the target lock icons (brackets drawn at the corner of the stage when nothing is locked) stay hidden, during the intro and after",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				local seen = 0

				for _, seconds in ipairs({0, 0.1, 1.5}) do
					run(b, seconds)

					for _, entry in ipairs(b.bino:Entries()) do
						if entry.clip and ((entry.name and string.find(entry.name, "^TargetIcon")) or entry.id == 51) then
							seen = seen + 1
							expect(entry.clip.visible).to.beFalse()
						end
					end
				end

				expect(seen > 0).to.beTrue()
			end
		},
		{
			name = "showing plays the intro to its resting frame",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				expect(b.bino:CurrentFrame()).to.equal(25)
				expect(b.bino.playing).to.beFalse()
			end
		},
		{
			name = "the zoom reads X0 and twice the mode",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetZoomMode(2)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X04")
				b:SetZoomMode(0)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X00")
			end
		},
		{
			name = "the position strings are written in the two degree fields",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetPosition("045° 12.34 N", "010° 05.00 W")
				expect(field(b.bino:Find("DegreeN.Colorset"), "DegreeN")).to.equal("045° 12.34 N")
				expect(field(b.bino:Find("DegreeW.Colorset"), "DegreeW")).to.equal("010° 05.00 W")
			end
		},
		{
			name = "the distance shows its digits, the dim zeros for the missing hundreds, the dot and the M",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetDistance(34, 56)
				local d = b.bino:Find("TargetDistance.Colorset")
				-- 034: the hundreds are a dim zero (frame 2), the others are plain digits (frame 1)
				expect(d:Child("ObjNumber0"):CurrentFrame()).to.equal(2)
				expect(field(d:Child("ObjNumber0"):Child("Low"), "ObjNumber0")).to.equal("0")
				expect(d:Child("ObjNumber1"):CurrentFrame()).to.equal(1)
				expect(field(d:Child("ObjNumber1"), "ObjNumber1")).to.equal("3")
				expect(field(d:Child("ObjNumber2"), "ObjNumber2")).to.equal("4")
				expect(field(d, "ObjNumber4")).to.equal("5")
				expect(field(d, "ObjNumber5")).to.equal("6")
				expect(field(d, "Dot")).to.equal(".")
				expect(field(d, "MTEXT")).to.equal("M")
				expect(d:Child("Icon").visible).to.beFalse()
			end
		},
		{
			name = "no distance (nothing aimed at) blanks the digits and shows the icon",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:SetDistance(34, 56)
				b:SetDistance(0, 0)
				local d = b.bino:Find("TargetDistance.Colorset")
				expect(field(d, "ObjNumber4")).to.equal("")
				expect(field(d, "ObjNumber5")).to.equal("")
				expect(field(d, "Dot")).to.equal("")
				expect(field(d, "MTEXT")).to.equal("")
				expect(d:Child("Icon").visible).to.beTrue()
			end
		},
		{
			name = "the values stay while the intro still rebuilds the clips",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				b:SetZoomMode(3)
				b:SetPosition("001° 00.00 N", "002° 00.00 W")
				run(b, 1.5)
				expect(field(b.bino:Find("Zoom.Colorset"), "Zoom")).to.equal("X06")
				expect(field(b.bino:Find("DegreeN.Colorset"), "DegreeN")).to.equal("001° 00.00 N")
			end
		},
		{
			name = "closing plays the original close animation and hides the binoculars at its end",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				run(b, 1.5)
				b:Close()
				expect(b.bino:CurrentLabel()).to.equal("close")
				run(b, 2)
				expect(b:IsShown()).to.beFalse()
				b:Show()
				expect(b:IsShown()).to.beTrue()
			end
		},
		{
			name = "the zoom factor of a field of view gives the mode: 1 under 4x, 2 under 6x, 3 under 8x, 4 above",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.ZoomModeFor(90, 90)).to.equal(1)
				expect(M.ZoomModeFor(90, 45)).to.equal(1) -- about 2.4x
				expect(M.ZoomModeFor(90, 22)).to.equal(2) -- about 5x
				expect(M.ZoomModeFor(90, 16)).to.equal(3) -- about 7x
				expect(M.ZoomModeFor(90, 14)).to.equal(4) -- about 8x
				expect(M.ZoomModeFor(90, 5)).to.equal(4)
				expect(M.ZoomModeFor(nil, 20)).to.equal(1)
				expect(M.ZoomModeFor(90, 0 / 0)).to.equal(1)
			end
		},
		{
			name = "a distance in world units gives the metres and hundredths the movie wants, and nothing when nothing is hit",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local int, frac = M.MetresFrom(52.49 * 34.56)
				expect(int).to.equal(34)
				expect(frac).to.equal(56)
				int, frac = M.MetresFrom(0)
				expect(int).to.equal(0)
				expect(frac).to.equal(0)
				int, frac = M.MetresFrom(nil)
				expect(int).to.equal(0)
				expect(frac).to.equal(0)
				int, frac = M.MetresFrom(52.49 * 5000) -- past the three digits of the display
				expect(int).to.equal(999)
				expect(frac).to.equal(99)
			end
		},
		{
			name = "the position strings are the original's: a number that grows by ten per metre, printed as DD\"MM'SS.hh, N from x and W from y",
			func = function(state)
				local M = GryMod.FlashBinoculars
				-- at the origin: 50155927 and 10647257 (digit groups, not base 60: the seconds can pass 59)
				local n, w = M.PositionStrings(Vector(0, 0, 0))
				expect(n).to.equal("50\"15'59.27 N")
				expect(w).to.equal("10\"64'72.57 W")
				-- 12.34 m along x: +123 (the metres times ten, cut toward zero) = 50156050
				n, w = M.PositionStrings(Vector(52.49 * 12.34, 52.49 * 5, 0))
				expect(n).to.equal("50\"15'60.50 N")
				expect(w).to.equal("10\"64'73.07 W")
				-- behind the origin: -100 m is -1000, cut toward zero
				n, w = M.PositionStrings(Vector(-52.49 * 100, -52.49 * 0.55, 0))
				expect(n).to.equal("50\"15'49.27 N")
				-- -0.55 m is -5.5, cut to -5
				expect(w).to.equal("10\"64'72.52 W")
			end
		},
		{
			name = "the horizon ladder sits at forward.z * 360 + 336 (the movie's own units), whatever the input",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.HorizonY(0)).to.equal(336)
				expect(M.HorizonY(1)).to.equal(696)
				expect(M.HorizonY(-1)).to.equal(-24)
				expect(math.abs(M.HorizonY(0.5) - 516) < 1e-9).to.beTrue()
				-- a forward vector is never out of [-1, 1]; a rounding error or a missing value does not break the ladder
				expect(M.HorizonY(1.5)).to.equal(696)
				expect(M.HorizonY(nil)).to.equal(336)
				expect(M.HorizonY(0 / 0)).to.equal(336)
			end
		},
		{
			name = "the horizon is placed on the Attitude clip, and stays there while the intro rebuilds the clips",
			func = function(state)
				local b = newBinoculars()
				b:Show()
				b:SetHorizon(450)
				local attitude = b.bino:Child("Attitude")
				expect(attitude).toNot.beNil()
				expect(attitude.entry.m[6]).to.equal(450)
				run(b, 1.5)
				expect(attitude.entry.m[6]).to.equal(450)
				b:SetHorizon(500)
				expect(attitude.entry.m[6]).to.equal(500)
			end
		},
		{
			name = "the scan rays start at the corners of a square, in the original's order, then at the eye itself (the last one), and run along the view",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local o = M.RayOrigins(Vector(100, 0, 0), Vector(0, -1, 0), Vector(0, 0, 1), 10)
				expect(#o).to.equal(5)
				-- right and up, right and down, left and down, left and up
				expect(o[1]).to.equal(Vector(100, -10, 10))
				expect(o[2]).to.equal(Vector(100, -10, -10))
				expect(o[3]).to.equal(Vector(100, 10, -10))
				expect(o[4]).to.equal(Vector(100, 10, 10))
				-- the original's characters are caught by all four corners; a narrower hitbox in the middle would not be: the centre ray last
				expect(o[5]).to.equal(Vector(100, 0, 0))
				-- 0.3 m each way, 300 m long, in world units
				expect(math.abs(M.RAY_OFFSET - 0.3 * M.UNITS_PER_METRE) < 1e-9).to.beTrue()
				expect(math.abs(M.RANGE - 300 * M.UNITS_PER_METRE) < 1e-9).to.beTrue()
			end
		},
		{
			name = "the aimed distance: the first ray that finds an entity gives the distance to that entity, else the last ray's hit",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local e1, e2 = {name = "e1"}, {name = "e2"}
				local centre = function(e) return e == e1 and 1000 or 2000 end
				local function ray(hit, distance, entity) return {hit = hit, distance = distance, entity = entity} end

				-- an entity on the second ray: its own distance, not the ray's, and the first ray (a wall) does not count
				local d, e = M.AimedDistance({ray(true, 500), ray(true, 900, e1), ray(true, 900, e2), ray(true, 300)}, centre)
				expect(d).to.equal(1000)
				expect(e).to.equal(e1)

				-- no entity anywhere: the hit of the last ray only
				d, e = M.AimedDistance({ray(true, 500), ray(true, 600), ray(true, 700), ray(true, 800)}, centre)
				expect(d).to.equal(800)
				expect(e).to.beNil()

				-- the last ray found nothing (sky, or out of range): no distance, even if the others hit
				d, e = M.AimedDistance({ray(true, 500), ray(true, 600), ray(true, 700), ray(false, 0)}, centre)
				expect(d).to.beNil()
				expect(e).to.beNil()

				-- a ray that missed does not carry an entity
				d, e = M.AimedDistance({ray(false, 0, e1), ray(false, 0), ray(false, 0), ray(false, 0)}, centre)
				expect(d).to.beNil()
				expect(M.AimedDistance({}, centre)).to.beNil()
			end
		},
		{
			name = "the original's aim rules are a choice: with them off the distance is the eye's to the single ray's hit, up to 1000 m; with them on five rays of 300 m",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local rules = M.AimRules
				local ok, err = pcall(function()
					M.AimRules = function() return false end
					expect(M.TraceCount()).to.equal(1)
					expect(M.TraceLength()).to.equal(1000 * M.UNITS_PER_METRE)
					M.AimRules = function() return true end
					expect(M.TraceCount()).to.equal(5)
					expect(M.TraceLength()).to.equal(M.RANGE)
				end)

				M.AimRules = rules

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the Half-Life 2 zoom overlay (CHudZoom) is hidden while our binoculars are wanted, and only then",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local enabled, wanted = M.Enabled, M.Wanted

				local ok, err = pcall(function()
					M.Enabled = function() return true end
					M.Wanted = function() return true end
					expect(hook.Run("HUDShouldDraw", "CHudZoom") == false).to.beTrue()
					-- the other elements are not ours to hide
					expect(hook.Run("HUDShouldDraw", "CHudCloseCaption") == false).to.beFalse()

					M.Wanted = function() return false end
					expect(hook.Run("HUDShouldDraw", "CHudZoom") == false).to.beFalse()

					M.Wanted = function() return true end
					M.Enabled = function() return false end
					expect(hook.Run("HUDShouldDraw", "CHudZoom") == false).to.beFalse()
				end)

				M.Enabled, M.Wanted = enabled, wanted

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the sound cues: opening plays the select sound and starts the loop, closing plays the deselect sound and stops it, nothing otherwise",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local function cues(wasWanted, wanted)
					return table.concat(M.SoundCues(wasWanted, wanted), ",")
				end

				expect(cues(false, true)).to.equal("select,loop_start")
				expect(cues(true, false)).to.equal("deselect,loop_stop")
				expect(cues(true, true)).to.equal("")
				expect(cues(false, false)).to.equal("")
			end
		},
		{
			name = "the files of the cues are binocular sounds that exist, each with a level in the mix's table, and the lock keeps its pitch",
			func = function(state)
				local M = GryMod.FlashBinoculars
				for _, name in ipairs({"select", "deselect", "loop", "locked"}) do
					local path = M.Sounds[name]
					expect(isstring(path)).to.beTrue()
					expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
					expect(GryMod.SoundMix.Original[GryMod.SoundMix.Normalize(path)] ~= nil).to.beTrue()
				end

				expect(GryMod.SoundMix.Pitch(M.Sounds.locked)).to.equal(143)
			end
		},
		{
			name = "the audio plays the cues through GryMod.PlaySound only, and nothing when the binoculars' sounds are off",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local playSound, startLoop, stopLoop, enabled = GryMod.PlaySound, M.StartLoop, M.StopLoop, M.SoundsEnabled
				local played, loops = {}, {}

				local ok, err = pcall(function()
					GryMod.PlaySound = function(path) played[#played + 1] = path return true end
					M.StartLoop = function() loops[#loops + 1] = "start" end
					M.StopLoop = function() loops[#loops + 1] = "stop" end
					M.SoundsEnabled = function() return true end
					M.AudioReset()

					M.AudioStep(false)
					expect(#played).to.equal(0)
					M.AudioStep(true)
					expect(played[1]).to.equal(M.Sounds.select)
					expect(loops[1]).to.equal("start")
					M.AudioStep(true)
					expect(#played).to.equal(1)
					M.AudioStep(false)
					expect(played[2]).to.equal(M.Sounds.deselect)
					expect(loops[2]).to.equal("stop")

					-- switched off: no sound, no loop
					M.SoundsEnabled = function() return false end
					played, loops = {}, {}
					M.AudioStep(true)
					M.AudioStep(false)
					expect(#played).to.equal(0)
					expect(#loops).to.equal(0)

					-- the lock sound
					M.PlayLocked()
					expect(#played).to.equal(0)
					M.SoundsEnabled = function() return true end
					M.PlayLocked()
					expect(played[1]).to.equal(M.Sounds.locked)
				end)

				GryMod.PlaySound, M.StartLoop, M.StopLoop, M.SoundsEnabled = playSound, startLoop, stopLoop, enabled
				M.AudioReset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the sounds switched off while the binoculars are up stop the loop, and switching them on again plays no select sound",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local playSound, startLoop, stopLoop, enabled = GryMod.PlaySound, M.StartLoop, M.StopLoop, M.SoundsEnabled
				local loops, played = {}, {}

				local ok, err = pcall(function()
					GryMod.PlaySound = function(path) played[#played + 1] = path return true end
					M.StartLoop = function() loops[#loops + 1] = "start" end
					M.StopLoop = function() loops[#loops + 1] = "stop" end
					M.SoundsEnabled = function() return true end
					M.AudioReset()
					M.AudioStep(true)
					M.SoundsEnabled = function() return false end
					M.AudioStep(true)
					expect(loops[#loops]).to.equal("stop")
					M.SoundsEnabled = function() return true end
					M.AudioStep(true)
					expect(#played).to.equal(1)
				end)

				GryMod.PlaySound, M.StartLoop, M.StopLoop, M.SoundsEnabled = playSound, startLoop, stopLoop, enabled
				M.AudioReset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the loop's volume is the mix's level for its file, brought up over the first hundredths of a second",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local full = GryMod.SoundMix.Volume(M.Sounds.loop)
				expect(M.LoopVolume(0)).to.equal(0)
				expect(M.LoopVolume(10)).to.equal(full)
				expect(M.LoopVolume(GryMod.SoundMix.FadeInSeconds / 2) < full).to.beTrue()
			end
		},
		{
			name = "the scan: an entity aimed at for 0.05 s joins the queue, and 0.55 s later it is scanned (once)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local st = M.NewScan()
				local e = {}
				local always = function() return true end
				local scanned

				-- the frame the entity comes into view starts the debounce (it is counted down on the frames after): nothing is queued yet
				expect(M.ScanStep(st, e, 0.02, always)).to.beNil()
				expect(st.current).to.beNil()
				expect(M.ScanStep(st, e, 0.02, always)).to.beNil()
				expect(M.ScanStep(st, e, 0.02, always)).to.beNil()
				-- 0.04 s are gone: not yet; the fourth step takes it under zero, the scan starts at once (the queue was empty)
				expect(st.current).to.beNil()
				expect(M.ScanStep(st, e, 0.02, always)).to.beNil()
				expect(st.current).to.equal(e)
				expect(math.abs(st.timer - M.SCAN_SECONDS) < 1e-9).to.beTrue()

				-- the countdown runs 0.55 s; the entity is given back once, when it ends
				for _ = 1, 10 do
					scanned = M.ScanStep(st, e, 0.05, always) or scanned
				end

				expect(scanned).to.beNil()
				scanned = M.ScanStep(st, e, 0.05, always)
				expect(scanned).to.equal(e)
				-- and it is not scanned again while it is aimed at (the caller says it is tagged)
				local again = false
				local tagged = function(x) return x ~= e end

				for _ = 1, 40 do
					again = again or M.ScanStep(st, e, 0.05, tagged) ~= nil
				end

				expect(again).to.beFalse()
			end
		},
		{
			name = "the scan: a glance of less than 0.05 s queues nothing, a target change starts the debounce again, no target changes nothing",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local st = M.NewScan()
				local a, b = {}, {}
				local always = function() return true end

				M.ScanStep(st, a, 0.03, always)
				M.ScanStep(st, nil, 0.03, always)
				expect(st.current).to.beNil()
				-- back on `a` after looking at nothing: the debounce goes on from where it was (the target was cleared, so it starts again)
				M.ScanStep(st, a, 0.03, always)
				expect(st.current).to.beNil()
				M.ScanStep(st, b, 0.04, always)
				M.ScanStep(st, b, 0.04, always)
				expect(st.current).to.beNil()
				M.ScanStep(st, b, 0.04, always)
				expect(st.current).to.equal(b)
			end
		},
		{
			name = "the scan goes on after the aim leaves the entity, and the next entity waits in the queue for the end of the scan",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local st = M.NewScan()
				local a, b = {}, {}
				local always = function() return true end
				local order = {}

				local function run(target, seconds)
					for _ = 1, math.floor(seconds / 0.05 + 0.5) do
						local done = M.ScanStep(st, target, 0.05, always)

						if done then
							order[#order + 1] = done
						end
					end
				end

				run(a, 0.15)
				expect(st.current).to.equal(a)
				-- the aim moves to b while a is being scanned: b is queued, a still ends
				run(b, 0.2)
				expect(#st.queue).to.equal(1)
				expect(st.queue[1]).to.equal(b)
				run(nil, 0.5)
				expect(order[1]).to.equal(a)
				-- b starts when a ends, and ends 0.55 s later
				expect(st.current).to.equal(b)
				run(nil, 0.6)
				expect(order[2]).to.equal(b)
				expect(st.current).to.beNil()
			end
		},
		{
			name = "the scan refuses what the caller refuses (not an NPC, already tagged), and forgets what it queued when it is reset",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local st = M.NewScan()
				local e = {}

				for _ = 1, 4 do
					M.ScanStep(st, e, 0.05, function() return false end)
				end

				expect(st.current).to.beNil()
				expect(#st.queue).to.equal(0)

				-- a target refused when its debounce ends is not asked again until the aim leaves it and comes back
				M.ScanStep(st, nil, 0.05, function() return true end)

				for _ = 1, 4 do
					M.ScanStep(st, e, 0.05, function() return true end)
				end

				expect(st.current).to.equal(e)
				M.ScanReset(st)
				expect(st.current).to.beNil()
				expect(st.timer).to.equal(0)
				expect(#st.queue).to.equal(0)
			end
		},
		{
			name = "a finished scan is not given back for an entity the caller no longer accepts (it died while it was scanned)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local st = M.NewScan()
				local e = {}
				local alive = true
				local accepts = function() return alive end

				for _ = 1, 4 do
					M.ScanStep(st, e, 0.05, accepts)
				end

				expect(st.current).to.equal(e)
				alive = false
				local done

				for _ = 1, 14 do
					done = M.ScanStep(st, nil, 0.05, accepts) or done
				end

				expect(done).to.beNil()
				expect(st.current).to.beNil()
			end
		},
		{
			name = "each addition to the binoculars has its own switch (a client convar), on by default",
			func = function(state)
				local M = GryMod.FlashBinoculars
				for _, name in ipairs({"gry_binoculars_sounds", "gry_binoculars_aim", "gry_binoculars_horizon", "gry_binoculars_tag", "gry_binoculars_vignette"}) do
					local convar = GetConVar(name)
					expect(convar).toNot.beNil()
					expect(convar:GetDefault()).to.equal("1")
				end

				expect(isfunction(M.SoundsEnabled)).to.beTrue()
				expect(isfunction(M.AimRules)).to.beTrue()
				expect(isfunction(M.HorizonEnabled)).to.beTrue()
				expect(isfunction(M.TagEnabled)).to.beTrue()
			end
		},
		{
			name = "the options panel has a check box for each of the binoculars' switches, and opening it writes nothing",
			func = function(state)
				local writes = {}
				local realRun = RunConsoleCommand
				RunConsoleCommand = function(name, value) writes[#writes + 1] = tostring(name) end
				local found = {}

				local ok, err = pcall(function()
					local panel = vgui.Create("ControlPanel")
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
					panel:Remove()
				end)

				RunConsoleCommand = realRun
				expect(ok).to.beTrue()
				for _, name in ipairs({"gry_binoculars_sounds", "gry_binoculars_aim", "gry_binoculars_horizon", "gry_binoculars_tag", "gry_binoculars_vignette"}) do
					expect(found[name]).to.beTrue()
				end

				expect(#writes).to.equal(0)
			end
		},
		{
			name = "the vignette (the film's full-screen black gradient, the clip called Alpha) is there from the first frame of the intro, at full strength, as in the film",
			func = function(state)
				local b = newBinoculars()
				local alpha = b.root:Find("Root.Alpha")
				expect(alpha).toNot.beNil()
				b:Show()
				expect(vignetteAlpha(b)).to.equal(1)
				run(b, 0.2)
				expect(vignetteAlpha(b)).to.equal(1)
				run(b, 1.5)
				expect(vignetteAlpha(b)).to.equal(1)
			end
		},
		{
			name = "closing fades the vignette out frame by frame as the film's script does (Binoculars frame 26 plays Alpha's close): 14 frames of the film, 0.93 down to 0, while the rest of the close animation goes on",
			func = function(state)
				local b = newBinoculars()
				local fade = GryMod.FlashBinoculars.VignetteFade
				local ok, err = pcall(function()
					GryMod.FlashBinoculars.VignetteFade = function() return true end
					b:Show()
					run(b, 1.5)
					b:Close()
					-- the values of the film's frames 2 to 15 of the clip (0.929688 ... 0), one per 1/30 s, the first at once
					local expected = {0.929688, 0.855469, 0.785156, 0.714844, 0.644531, 0.570312, 0.5, 0.429688, 0.355469, 0.285156, 0.214844, 0.144531, 0.0703125, 0}
					for i, value in ipairs(expected) do
						expect(math.abs(vignetteAlpha(b) - value) < 1e-6).to.beTrue()
						b:Update(1 / 30)
					end

					-- gone, while the binoculars are still closing (the close animation is longer)
					expect(vignetteAlpha(b)).to.equal(0)
					expect(b:IsShown()).to.beTrue()
					run(b, 2)
					expect(b:IsShown()).to.beFalse()
				end)

				GryMod.FlashBinoculars.VignetteFade = fade

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "with the fade off the vignette stays at full strength until the binoculars are gone, as before",
			func = function(state)
				local b = newBinoculars()
				local fade = GryMod.FlashBinoculars.VignetteFade
				local ok, err = pcall(function()
					GryMod.FlashBinoculars.VignetteFade = function() return false end
					b:Show()
					run(b, 1.5)
					b:Close()
					run(b, 0.5)
					expect(vignetteAlpha(b)).to.equal(1)
				end)

				GryMod.FlashBinoculars.VignetteFade = fade

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "opening again after a close starts the vignette over at full strength (the film is not left at its faded frame)",
			func = function(state)
				local b = newBinoculars()
				local fade = GryMod.FlashBinoculars.VignetteFade
				local ok, err = pcall(function()
					GryMod.FlashBinoculars.VignetteFade = function() return true end
					b:Show()
					run(b, 1.5)
					b:Close()
					run(b, 3)
					expect(b:IsShown()).to.beFalse()
					b:Show()
					expect(vignetteAlpha(b)).to.equal(1)
					run(b, 1.5)
					expect(vignetteAlpha(b)).to.equal(1)

					-- and one that comes while the close is under way
					b:Close()
					run(b, 0.2)
					expect(vignetteAlpha(b) < 1).to.beTrue()
					b:Show()
					expect(vignetteAlpha(b)).to.equal(1)
				end)

				GryMod.FlashBinoculars.VignetteFade = fade

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the vignette's fade has its own switch, on by default, with a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_binoculars_vignette")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				expect(isfunction(GryMod.FlashBinoculars.VignetteFade)).to.beTrue()
			end
		},
		{
			name = "the cryvision sound mood follows the binoculars: on while they are up and the switch is on, off when they go or the switch goes, and Reset puts it out",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local Mix = GryMod.SoundMix
				local moodSet, enabled = Mix.MoodSet, M.MoodEnabled
				local calls = {}

				local ok, err = pcall(function()
					Mix.MoodSet = function(name, on) calls[#calls + 1] = name .. (on and ":on" or ":off") return true end
					M.MoodEnabled = function() return true end
					M.MoodStep(true)
					M.MoodStep(false)
					expect(calls[1]).to.equal("cryvision:on")
					expect(calls[2]).to.equal("cryvision:off")

					-- the switch off while the binoculars are up
					M.MoodEnabled = function() return false end
					M.MoodStep(true)
					expect(calls[3]).to.equal("cryvision:off")

					-- Reset: the mood goes out whatever else
					M.MoodEnabled = function() return true end
					calls = {}
					M.Reset()
					expect(calls[#calls]).to.equal("cryvision:off")
				end)

				Mix.MoodSet, M.MoodEnabled = moodSet, enabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the mood is a real fade through the mix: on, half a second later the physics sounds are at half volume; the binoculars closing brings them back in half a second",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local Mix = GryMod.SoundMix
				local now = 0
				local clock, enabled = Mix.Now, M.MoodEnabled

				local ok, err = pcall(function()
					Mix.Now = function() return now end
					M.MoodEnabled = function() return true end
					Mix.MoodReset()
					M.MoodStep(true)
					now = 0.5
					expect(Mix.MoodGain("collision")).to.aboutEqual(0.5, 1e-6)
					M.MoodStep(false)
					now = 1
					expect(Mix.MoodGain("collision")).to.equal(1)
				end)

				Mix.Now, M.MoodEnabled = clock, enabled
				Mix.MoodReset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the mood has its own switch (gry_binoculars_mood, saved, on by default) with a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_binoculars_mood")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				expect(isfunction(GryMod.FlashBinoculars.MoodEnabled)).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_binoculars_mood"]).to.beTrue()
			end
		},
		{
			name = "the silhouette's target: the entity being scanned, only in the last 0.3 s of the countdown, and only while the caller finds it valid",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.SILHOUETTE_SECONDS).to.equal(0.3)
				local e = {}
				local always = function() return true end

				-- no scan, no entity: none
				expect(M.SilhouetteTarget(M.NewScan(), always)).to.beNil()

				local function target(timer, valid)
					return M.SilhouetteTarget({current = e, timer = timer}, valid or always)
				end

				expect(target(0.55)).to.beNil()
				expect(target(0.31)).to.beNil()
				expect(target(0.3)).to.equal(e)
				expect(target(0.15)).to.equal(e)
				expect(target(0.001)).to.equal(e)
				-- a finished scan has no timer left
				expect(target(0)).to.beNil()
				expect(target(0.2, function() return false end)).to.beNil()
				expect(M.SilhouetteTarget({current = nil, timer = 0.2}, always)).to.beNil()
			end
		},
		{
			name = "an NPC that is alive is a valid silhouette target; a dead one, one that is not an NPC and an invalid one are not",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local function npc(valid, isNpc, health)
					return {IsValid = function() return valid end, IsNPC = function() return isNpc end, Health = function() return health end}
				end

				expect(M.SilhouetteValid(npc(true, true, 40))).to.beTrue()
				expect(M.SilhouetteValid(npc(true, true, 0))).to.beFalse()
				expect(M.SilhouetteValid(npc(true, false, 40))).to.beFalse()
				expect(M.SilhouetteValid(npc(false, true, 40))).to.beFalse()
				expect(M.SilhouetteValid(nil)).to.beFalse()
			end
		},
		{
			name = "the silhouette is a halo on the scanned NPC in the last 0.3 s: nothing before, nothing after, nothing for a dead NPC, nothing with the switch off or the binoculars down",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local add, enabled, wanted, hudEnabled = halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled
				local calls = {}
				local alive = true
				local npc = {IsValid = function() return true end, IsNPC = function() return true end, Health = function() return alive and 40 or 0 end}
				local st = M.ScanState

				local ok, err = pcall(function()
					halo.Add = function(entities, color, blurx, blury, passes, additive, ignorez)
						calls[#calls + 1] = {entities = entities, color = color, blurx = blurx, blury = blury, passes = passes, additive = additive, ignorez = ignorez}
					end

					M.SilhouetteEnabled = function() return true end
					M.Wanted = function() return true end
					M.Enabled = function() return true end
					M.ScanReset(st)

					-- no scan: nothing
					M.DrawSilhouette()
					expect(#calls).to.equal(0)

					-- scanning, 0.5 s left: nothing
					st.current, st.timer = npc, 0.5
					M.DrawSilhouette()
					expect(#calls).to.equal(0)

					-- 0.2 s left: one halo, on the NPC
					st.timer = 0.2
					M.DrawSilhouette()
					expect(#calls).to.equal(1)
					expect(#calls[1].entities).to.equal(1)
					expect(calls[1].entities[1]).to.equal(npc)
					expect(calls[1].color.r > 0 and calls[1].color.a > 0).to.beTrue()
					expect(calls[1].passes >= 1).to.beTrue()
					-- through walls: no (what is aimed at is seen)
					expect(calls[1].ignorez).to.beFalse()

					-- dead: nothing
					alive = false
					M.DrawSilhouette()
					expect(#calls).to.equal(1)
					alive = true

					-- the switch off, the binoculars down, the HUD off: nothing
					M.SilhouetteEnabled = function() return false end
					M.DrawSilhouette()
					M.SilhouetteEnabled = function() return true end
					M.Wanted = function() return false end
					M.DrawSilhouette()
					M.Wanted = function() return true end
					M.Enabled = function() return false end
					M.DrawSilhouette()
					expect(#calls).to.equal(1)
				end)

				M.ScanReset(st)
				halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled = add, enabled, wanted, hudEnabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the silhouette is the original's pale blue-white (204, 204, 255), not the radar's red",
			func = function(state)
				local c = GryMod.FlashBinoculars.SilhouetteColor
				expect(c.r).to.equal(204)
				expect(c.g).to.equal(204)
				expect(c.b).to.equal(255)
				expect(c.a).to.equal(255)
			end
		},
		{
			name = "the set of outlined entities: no duplicates, at most SILHOUETTE_MAX (8) with the oldest dropped first, invalid or dead ones pruned, and it can be cleared",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.SILHOUETTE_MAX).to.equal(8)
				local set = {}
				local list = {}
				for i = 1, 10 do list[i] = {id = i} end
				local always = function() return true end

				M.SilhouetteAdd(set, list[1])
				M.SilhouetteAdd(set, list[1])
				expect(#set).to.equal(1)

				for i = 2, 10 do M.SilhouetteAdd(set, list[i]) end
				expect(#set).to.equal(8)
				-- the oldest two (1 and 2) are gone, the newest is last
				expect(set[1]).to.equal(list[3])
				expect(set[8]).to.equal(list[10])

				-- pruning keeps the order and the same table
				local kept = M.SilhouetteLive(set, function(e) return e.id % 2 == 0 end)
				expect(kept).to.equal(set)
				expect(#set).to.equal(4)
				expect(set[1]).to.equal(list[4])
				expect(set[4]).to.equal(list[10])
				expect(#M.SilhouetteLive(set, always)).to.equal(4)

				-- nil is not added
				M.SilhouetteAdd(set, nil)
				expect(#set).to.equal(4)

				M.SilhouetteClear(set)
				expect(#set).to.equal(0)
			end
		},
		{
			name = "durations: the outline starts in the last 0.3 s of the 0.55 s scan and then stays, frame after frame, for as long as the binoculars are up; it goes when they are let go or the NPC dies, and does not come back",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local add, enabled, wanted, hudEnabled = halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled
				local st = M.ScanState
				local alive, up = true, true
				local haloed = {}
				local npc = {IsValid = function() return true end, IsNPC = function() return true end, Health = function() return alive and 40 or 0 end}
				local dt = 1 / 30

				local ok, err = pcall(function()
					halo.Add = function(entities) haloed[#haloed + 1] = entities[1] end
					M.SilhouetteEnabled = function() return true end
					M.Wanted = function() return up end
					M.Enabled = function() return true end
					M.ScanReset(st)
					M.SilhouetteClear(M.Silhouettes)

					local first, last
					local accepts = function() return true end

					-- 12 s of frames aimed at the NPC
					for frame = 1, 360 do
						local time = frame * dt
						M.ScanStep(st, npc, dt, accepts)
						local before = #haloed
						M.DrawSilhouette()

						if #haloed > before then
							first = first or time
							last = time
						end
					end

					-- the aim is seen on frame 1, the debounce (0.05 s) and the scan (0.55 s) follow: the outline starts about 0.3 s before the
					-- end of the scan, around 0.35 s to 0.45 s here, and is still there on the last frame
					expect(first).toNot.beNil()
					expect(first > 0.3 and first < 0.5).to.beTrue()
					expect(last).to.aboutEqual(12, 1e-6)
					-- one halo per frame from the first frame to the last, no gap
					expect(#haloed).to.equal(math.floor((12 - first) / dt + 0.5) + 1)

					-- let go: gone, and not back when the binoculars come up again
					local count = #haloed
					up = false
					M.DrawSilhouette()
					up = true
					M.DrawSilhouette()
					expect(#haloed).to.equal(count)

					-- a scanned NPC that is then killed: its outline goes with it, for good
					M.ScanReset(st)
					st.current, st.timer = npc, 0.2
					M.DrawSilhouette()
					expect(#haloed).to.equal(count + 1)
					st.current, st.timer = nil, 0
					M.DrawSilhouette()
					expect(#haloed).to.equal(count + 2)
					alive = false
					M.DrawSilhouette()
					expect(#haloed).to.equal(count + 2)
					alive = true
					M.DrawSilhouette()
					expect(#haloed).to.equal(count + 2)
				end)

				M.ScanReset(st)
				M.SilhouetteClear(M.Silhouettes)
				halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled = add, enabled, wanted, hudEnabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "a reset takes every outline away, and the entities scanned are outlined together (one halo call with all of them)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local add, enabled, wanted, hudEnabled = halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled
				local st = M.ScanState
				local calls = {}
				local function npc() return {IsValid = function() return true end, IsNPC = function() return true end, Health = function() return 40 end} end
				local a, b = npc(), npc()

				local ok, err = pcall(function()
					halo.Add = function(entities) calls[#calls + 1] = #entities end
					M.SilhouetteEnabled = function() return true end
					M.Wanted = function() return true end
					M.Enabled = function() return true end
					M.ScanReset(st)
					M.SilhouetteClear(M.Silhouettes)

					st.current, st.timer = a, 0.2
					M.DrawSilhouette()
					st.current, st.timer = b, 0.2
					M.DrawSilhouette()
					st.current, st.timer = nil, 0
					M.DrawSilhouette()
					expect(calls[#calls]).to.equal(2)

					local count = #calls
					M.Reset()
					expect(st.current).to.beNil()
					M.DrawSilhouette()
					expect(#calls).to.equal(count)
				end)

				M.ScanReset(st)
				M.SilhouetteClear(M.Silhouettes)
				halo.Add, M.SilhouetteEnabled, M.Wanted, M.Enabled = add, enabled, wanted, hudEnabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the silhouette is drawn from the game's PreDrawHalos, under one name, and has its own switch (gry_binoculars_silhouette, saved, on by default) with a check box",
			func = function(state)
				local hooks = hook.GetTable().PreDrawHalos
				expect(hooks and hooks["GRYBINOCULARSSILHOUETTE"]).toNot.beNil()

				local convar = GetConVar("gry_binoculars_silhouette")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				expect(isfunction(GryMod.FlashBinoculars.SilhouetteEnabled)).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_binoculars_silhouette"]).to.beTrue()
			end
		},
		{
			name = "the zoom stages are the original's 2x, 4x, 8x, 0.2 s to open and to close and 0.055 s from one stage to the next; a stage's field of view is the base field of view divided by its magnification (the ratio of the tangents of the half fields)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(#M.ZOOM_STAGES).to.equal(3)
				expect(M.ZOOM_STAGES[1]).to.equal(2)
				expect(M.ZOOM_STAGES[2]).to.equal(4)
				expect(M.ZOOM_STAGES[3]).to.equal(8)
				expect(M.ZOOM_IN_TIME).to.equal(0.2)
				expect(M.ZOOM_OUT_TIME).to.equal(0.2)
				expect(M.ZOOM_STEP_TIME).to.equal(0.055)

				for _, base in ipairs({75, 90, 100, 110}) do
					expect(M.StageFov(base, 1)).to.aboutEqual(base, 1e-9)
					local previous = base

					for _, factor in ipairs(M.ZOOM_STAGES) do
						local fov = M.StageFov(base, factor)
						expect(fov < previous).to.beTrue()
						previous = fov
						expect(math.tan(math.rad(base) / 2) / math.tan(math.rad(fov) / 2)).to.aboutEqual(factor, 1e-6)
					end
				end

				-- one number to hold on to: 100 degrees at 2x
				expect(M.StageFov(100, 2)).to.aboutEqual(61.58, 0.01)
			end
		},
		{
			name = "the label of a stage follows the film's mode (1, 2, 3 read X02, X04, X06: the original's 8x reads X06), decided from the field of view in force, so it changes in the middle of a transition",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local base = 100

				expect(M.StageModeFor(base, M.StageFov(base, 2))).to.equal(1)
				expect(M.StageModeFor(base, M.StageFov(base, 4))).to.equal(2)
				expect(M.StageModeFor(base, M.StageFov(base, 8))).to.equal(3)
				-- not zoomed yet: the first label, not X00
				expect(M.StageModeFor(base, base)).to.equal(1)
				-- between 2x and 4x it is still the first stage's, and past 8x it stays at the last
				expect(M.StageModeFor(base, M.StageFov(base, 3))).to.equal(1)
				expect(M.StageModeFor(base, M.StageFov(base, 6))).to.equal(2)
				expect(M.StageModeFor(base, M.StageFov(base, 20))).to.equal(3)
				-- nonsense gives the first
				expect(M.StageModeFor(base, nil)).to.equal(1)
				expect(M.StageModeFor(base, 0 / 0)).to.equal(1)
			end
		},
		{
			name = "opening: the field of view goes from the base to 2x in a straight line over 0.2 s, then stays",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				local base = 100
				local stage1 = M.StageFov(base, 2)

				expect(M.ZoomStep(z, 10, false, base, base)).to.beNil()
				expect(z.active).to.beFalse()

				expect(M.ZoomStep(z, 10, true, base, base)).to.aboutEqual(base, 1e-9)
				expect(z.stage).to.equal(1)
				expect(M.ZoomStep(z, 10.05, true, base, 80)).to.aboutEqual(base + (stage1 - base) * 0.25, 1e-6)
				expect(M.ZoomStep(z, 10.1, true, base, 60)).to.aboutEqual((base + stage1) / 2, 1e-6)
				expect(M.ZoomStep(z, 10.2, true, base, 30)).to.aboutEqual(stage1, 1e-6)
				expect(M.ZoomStep(z, 15, true, base, 25)).to.aboutEqual(stage1, 1e-6)
			end
		},
		{
			name = "the wheel steps through the stages: in goes to the next (sound zoom_in), out to the previous (sound zoom_out), a straight 0.2 s from where the field of view is; at an end it does nothing (no sound) but the wheel is still taken",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				local base = 100
				local f1, f2, f3 = M.StageFov(base, 2), M.StageFov(base, 4), M.StageFov(base, 8)

				M.ZoomStep(z, 0, true, base, base)
				M.ZoomStep(z, 1, true, base, f1)

				local handled, cue = M.ZoomWheel(z, "invprev")
				expect(handled).to.beTrue()
				expect(cue).to.equal("zoom_in")
				expect(z.stage).to.equal(2)
				expect(M.ZoomStep(z, 1, true, base, f1)).to.aboutEqual(f1, 1e-6)
				-- a step between two stages takes 0.055 s (the zoom class's default stage time, DEDUCED), not the 0.2 s of the opening
				expect(M.ZoomStep(z, 1.0275, true, base, f1)).to.aboutEqual((f1 + f2) / 2, 1e-6)
				expect(M.ZoomStep(z, 1.055, true, base, f1)).to.aboutEqual(f2, 1e-6)
				expect(M.ZoomStep(z, 1.2, true, base, f1)).to.aboutEqual(f2, 1e-6)

				-- a second step in the middle of the first goes on from where the field of view is
				handled, cue = M.ZoomWheel(z, "invprev")
				expect(cue).to.equal("zoom_in")
				expect(z.stage).to.equal(3)
				M.ZoomStep(z, 5, true, base, f1)
				expect(M.ZoomStep(z, 5.0275, true, base, f1)).to.aboutEqual((f2 + f3) / 2, 1e-6)
				expect(M.ZoomStep(z, 5.055, true, base, f1)).to.aboutEqual(f3, 1e-6)
				M.ZoomStep(z, 5.2, true, base, f1)

				-- at the last stage: taken, nothing happens
				handled, cue = M.ZoomWheel(z, "invprev")
				expect(handled).to.beTrue()
				expect(cue).to.beNil()
				expect(z.stage).to.equal(3)

				-- out, twice, then the end at the first
				handled, cue = M.ZoomWheel(z, "invnext")
				expect(cue).to.equal("zoom_out")
				expect(z.stage).to.equal(2)
				handled, cue = M.ZoomWheel(z, "invnext")
				expect(cue).to.equal("zoom_out")
				expect(z.stage).to.equal(1)
				handled, cue = M.ZoomWheel(z, "invnext")
				expect(handled).to.beTrue()
				expect(cue).to.beNil()
				expect(z.stage).to.equal(1)

				-- other keys are not the wheel's; and with no zoom up the wheel is not ours
				expect(M.ZoomWheel(z, "+attack")).to.beFalse()
				expect(M.ZoomWheel(z, "slot1")).to.beFalse()
				expect(M.ZoomWheel(M.NewZoom(), "invprev")).to.beFalse()
			end
		},
		{
			name = "a wheel step in the middle of the opening goes on from the field of view in force over 0.055 s; the opening itself stays at 0.2 s",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				local base = 100
				local f1, f2 = M.StageFov(base, 2), M.StageFov(base, 4)

				M.ZoomStep(z, 0, true, base, base)
				local middle = M.ZoomStep(z, 0.1, true, base, base)
				expect(middle).to.aboutEqual((base + f1) / 2, 1e-6)
				M.ZoomWheel(z, "invprev")
				expect(M.ZoomStep(z, 0.1, true, base, base)).to.aboutEqual(middle, 1e-6)
				expect(M.ZoomStep(z, 0.1275, true, base, base)).to.aboutEqual((middle + f2) / 2, 1e-6)
				expect(M.ZoomStep(z, 0.155, true, base, base)).to.aboutEqual(f2, 1e-6)
			end
		},
		{
			name = "closing: the field of view goes back to the base in a straight 0.2 s; then the override ends only once the engine's own return is over (or after 0.6 s), and a new opening in the middle goes on from where it is",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local base = 100
				local f3 = M.StageFov(base, 8)

				local function zoomed(z, now)
					M.ZoomStep(z, now, true, base, base)
					M.ZoomWheel(z, "invprev")
					M.ZoomWheel(z, "invprev")
					M.ZoomStep(z, now + 1, true, base, base)
					expect(M.ZoomStep(z, now + 2, true, base, base)).to.aboutEqual(f3, 1e-6)
				end

				-- the engine is back at the base at once (the engine's field of view is the base): the override ends when ours does
				local z = M.NewZoom()
				zoomed(z, 0)
				expect(M.ZoomStep(z, 10, false, base, base)).to.aboutEqual(f3, 1e-6)
				expect(M.ZoomStep(z, 10.1, false, base, base)).to.aboutEqual((f3 + base) / 2, 1e-6)
				expect(M.ZoomStep(z, 10.2, false, base, base)).to.beNil()
				expect(z.active).to.beFalse()
				expect(z.stage).to.equal(0)
				expect(M.ZoomStep(z, 11, false, base, base)).to.beNil()

				-- the engine is still coming back (25 up to 100): ours holds the base until it is there
				z = M.NewZoom()
				zoomed(z, 0)
				M.ZoomStep(z, 10, false, base, 25)
				expect(M.ZoomStep(z, 10.2, false, base, 40)).to.aboutEqual(base, 1e-6)
				expect(M.ZoomStep(z, 10.3, false, base, 70)).to.aboutEqual(base, 1e-6)
				expect(M.ZoomStep(z, 10.4, false, base, 99.8)).to.beNil()
				expect(z.active).to.beFalse()

				-- an engine that never gets back (another addon's field of view): ours lets go after 0.6 s from the release
				z = M.NewZoom()
				zoomed(z, 0)
				M.ZoomStep(z, 10, false, base, 25)
				expect(M.ZoomStep(z, 10.5, false, base, 25)).to.aboutEqual(base, 1e-6)
				expect(M.ZoomStep(z, 10.7, false, base, 25)).to.beNil()
				expect(z.active).to.beFalse()

				-- the key pressed again half way through the closing: the first stage, from the field of view in force
				z = M.NewZoom()
				zoomed(z, 0)
				M.ZoomStep(z, 10, false, base, 25)
				local middle = M.ZoomStep(z, 10.1, false, base, 25)
				local f1 = M.StageFov(base, 2)
				expect(M.ZoomStep(z, 10.1, true, base, 25)).to.aboutEqual(middle, 1e-6)
				expect(z.stage).to.equal(1)
				expect(M.ZoomStep(z, 10.2, true, base, 25)).to.aboutEqual((middle + f1) / 2, 1e-6)
				expect(M.ZoomStep(z, 10.3, true, base, 25)).to.aboutEqual(f1, 1e-6)
			end
		},
		{
			name = "a new base field of view (the player changes fov_desired while zoomed) moves the target of the stage",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				M.ZoomStep(z, 0, true, 90, 90)
				expect(M.ZoomStep(z, 1, true, 90, 90)).to.aboutEqual(M.StageFov(90, 2), 1e-6)
				M.ZoomStep(z, 2, true, 110, 90)
				expect(M.ZoomStep(z, 3, true, 110, 90)).to.aboutEqual(M.StageFov(110, 2), 1e-6)
			end
		},
		{
			name = "the mouse is slowed as the field of view narrows: the fraction of the normal sensitivity is fov / base times the engine's zoom ratio, and nothing is said while no stage is up",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				local base = 100
				expect(M.SensitivityScale(z, base, 1)).to.beNil()
				M.ZoomStep(z, 0, true, base, base)
				M.ZoomStep(z, 5, true, base, 25)
				expect(M.SensitivityScale(z, base, 1)).to.aboutEqual(M.StageFov(base, 2) / base, 1e-6)
				expect(M.SensitivityScale(z, base, 0.5)).to.aboutEqual(M.StageFov(base, 2) / base * 0.5, 1e-6)
				M.ZoomWheel(z, "invprev")
				M.ZoomWheel(z, "invprev")
				M.ZoomStep(z, 6, true, base, 25)
				M.ZoomStep(z, 7, true, base, 25)
				expect(M.SensitivityScale(z, base, 1)).to.aboutEqual(M.StageFov(base, 8) / base, 1e-6)
				M.ZoomReset(z)
				expect(M.SensitivityScale(z, base, 1)).to.beNil()
			end
		},
		{
			name = "the label comes from the zoom in force: the stage's mode while the stages are up, the old rule (the engine's field of view) otherwise",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.NewZoom()
				-- no stages up: the engine's 25 degrees at a base of 100 is X04 as before
				expect(M.ZoomLabelMode(z, 100, 25)).to.equal(M.ZoomModeFor(100, 25))
				M.ZoomStep(z, 0, true, 100, 100)
				M.ZoomWheel(z, "invprev")
				M.ZoomWheel(z, "invprev")
				M.ZoomStep(z, 5, true, 100, 25)
				M.ZoomStep(z, 6, true, 100, 25)
				-- 8x is the third mode (X06), whatever the engine says
				expect(M.ZoomLabelMode(z, 100, 25)).to.equal(3)
				expect(M.ZoomLabelMode(z, 100, 100)).to.equal(3)
			end
		},
		{
			name = "CalcView: with the stages on and the binoculars wanted it gives the view the stage's field of view and leaves the rest of the view as it was; in every other case it returns nothing (the other addons' CalcView hooks are not touched)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local now, wanted, enabled, stages, clock = 0, M.Wanted, M.Enabled, M.StagesEnabled, M.Now
				local ply = {GetInfoNum = function(self, name, default) return name == "fov_desired" and 100 or default end}
				local origin, angles = Vector(1, 2, 3), Angle(4, 5, 6)
				local want, hud, on = true, true, true

				local ok, err = pcall(function()
					M.Now = function() return now end
					M.Wanted = function() return want end
					M.Enabled = function() return hud end
					M.StagesEnabled = function() return on end
					M.ZoomReset(M.ZoomState)

					-- on and wanted
					local view = M.CalcView(ply, origin, angles, 100, 3, 8000)
					expect(view).toNot.beNil()
					expect(view.fov).to.aboutEqual(100, 1e-6)
					expect(view.origin).to.equal(origin)
					expect(view.angles).to.equal(angles)
					expect(view.znear).to.equal(3)
					expect(view.zfar).to.equal(8000)
					now = 0.2
					expect(M.CalcView(ply, origin, angles, 40, 3, 8000).fov).to.aboutEqual(M.StageFov(100, 2), 1e-6)

					-- the switch off while it is up: the state goes and nothing is returned
					on = false
					expect(M.CalcView(ply, origin, angles, 40, 3, 8000)).to.beNil()
					expect(M.ZoomState.active).to.beFalse()
					on = true

					-- the HUD (or the binoculars element) off: nothing, and the state goes
					now = 1
					expect(M.CalcView(ply, origin, angles, 40, 3, 8000)).toNot.beNil()
					hud = false
					expect(M.CalcView(ply, origin, angles, 40, 3, 8000)).to.beNil()
					expect(M.ZoomState.active).to.beFalse()
					hud = true

					-- not wanted and nothing up: nothing
					want = false
					M.ZoomReset(M.ZoomState)
					expect(M.CalcView(ply, origin, angles, 100, 3, 8000)).to.beNil()
				end)

				M.Now, M.Wanted, M.Enabled, M.StagesEnabled = clock, wanted, enabled, stages
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the mouse hook: the sensitivity of the zoom in force while the stages are up, nothing (the engine's own) otherwise",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local wanted, enabled, stages, clock, ratio = M.Wanted, M.Enabled, M.StagesEnabled, M.Now, M.ZoomRatio
				local ply = {GetInfoNum = function(self, name, default) return name == "fov_desired" and 100 or default end}
				local now = 0

				local ok, err = pcall(function()
					M.Now = function() return now end
					M.Wanted = function() return true end
					M.Enabled = function() return true end
					M.StagesEnabled = function() return true end
					M.ZoomRatio = function() return 1 end
					M.ZoomReset(M.ZoomState)

					expect(M.AdjustSensitivity(ply)).to.beNil()
					M.CalcView(ply, Vector(), Angle(), 100, 1, 1)
					now = 5
					M.CalcView(ply, Vector(), Angle(), 25, 1, 1)
					expect(M.AdjustSensitivity(ply)).to.aboutEqual(M.StageFov(100, 2) / 100, 1e-6)

					M.StagesEnabled = function() return false end
					expect(M.AdjustSensitivity(ply)).to.beNil()
				end)

				M.Wanted, M.Enabled, M.StagesEnabled, M.Now, M.ZoomRatio = wanted, enabled, stages, clock, ratio
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the wheel key: with the stages on and the binoculars up the wheel steps the stage, plays the zoom sound through GryMod.PlaySound (nothing with the sounds off) and is swallowed; otherwise the key goes on to the game",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local wanted, enabled, stages, clock, sounds, playSound = M.Wanted, M.Enabled, M.StagesEnabled, M.Now, M.SoundsEnabled, GryMod.PlaySound
				local ply = {GetInfoNum = function(self, name, default) return name == "fov_desired" and 100 or default end}
				local played = {}
				local want, on, sound = true, true, true

				local ok, err = pcall(function()
					M.Now = function() return 0 end
					M.Wanted = function() return want end
					M.Enabled = function() return true end
					M.StagesEnabled = function() return on end
					M.SoundsEnabled = function() return sound end
					GryMod.PlaySound = function(path) played[#played + 1] = path return true end
					M.ZoomReset(M.ZoomState)
					M.CalcView(ply, Vector(), Angle(), 100, 1, 1)

					expect(M.BindPress(ply, "invprev", true)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)
					expect(played[1]).to.equal(M.Sounds.zoom_in)
					expect(M.BindPress(ply, "invnext", true)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(1)
					expect(played[2]).to.equal(M.Sounds.zoom_out)

					-- the release of the wheel key does not step again, but is swallowed with its press
					expect(M.BindPress(ply, "invprev", false)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(1)
					expect(#played).to.equal(2)

					-- at an end: swallowed, no sound
					expect(M.BindPress(ply, "invnext", true)).to.beTrue()
					expect(#played).to.equal(2)

					-- sounds off: it steps in silence
					sound = false
					expect(M.BindPress(ply, "invprev", true)).to.beTrue()
					expect(M.ZoomState.stage).to.equal(2)
					expect(#played).to.equal(2)
					sound = true

					-- other keys are not ours
					expect(M.BindPress(ply, "+attack", true)).to.beNil()
					-- stages off or binoculars down: the wheel goes to the game
					on = false
					expect(M.BindPress(ply, "invprev", true)).to.beNil()
					on = true
					want = false
					expect(M.BindPress(ply, "invprev", true)).to.beNil()
				end)

				M.Wanted, M.Enabled, M.StagesEnabled, M.Now, M.SoundsEnabled, GryMod.PlaySound = wanted, enabled, stages, clock, sounds, playSound
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "Reset puts the zoom stages away with everything else, and the zoom sounds are files that exist with a level in the mix",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local z = M.ZoomState
				z.stage, z.active, z.fov = 2, true, 40
				M.Reset()
				expect(z.stage).to.equal(0)
				expect(z.active).to.beFalse()

				for _, key in ipairs({"zoom_in", "zoom_out"}) do
					local path = M.Sounds[key]
					expect(isstring(path)).to.beTrue()
					expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
					expect(GryMod.SoundMix.Original[path]).toNot.beNil()
				end
			end
		},
		{
			name = "the stages are on three hooks of the game under one name each (CalcView, PlayerBindPress, AdjustMouseSensitivity) and have their own switch (gry_binoculars_stages, saved, OFF by default: it changes the feel of the mouse) with a check box",
			func = function(state)
				local hooks = hook.GetTable()
				expect(hooks.CalcView and hooks.CalcView["GRYBINOCULARSZOOM"]).toNot.beNil()
				expect(hooks.PlayerBindPress and hooks.PlayerBindPress["GRYBINOCULARSZOOM"]).toNot.beNil()
				expect(hooks.AdjustMouseSensitivity and hooks.AdjustMouseSensitivity["GRYBINOCULARSZOOM"]).toNot.beNil()

				local convar = GetConVar("gry_binoculars_stages")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0")
				expect(isfunction(GryMod.FlashBinoculars.StagesEnabled)).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_binoculars_stages"]).to.beTrue()
			end
		},
		{
			name = "sway (F13, recipe 8.6): a figure of eight from the time since the zoom started, in radians: pitch 0.012 * k * sin(4 pi p), yaw 0.015 * k * -cos(2 pi p), p = 0.3 t, k = max(0.2, 1 - t / 1.125)",
			func = function(state)
				local M = GryMod.FlashBinoculars

				-- t = 0: no pitch, the yaw at its full -0.015 at once
				local pitch, yaw = M.SwayOffset(0, false, false, false)
				expect(pitch).to.aboutEqual(0, 1e-9)
				expect(yaw).to.aboutEqual(-0.015, 1e-9)

				-- t = 0.3 s: k = 0.7333, p = 0.09
				pitch, yaw = M.SwayOffset(0.3, false, false, false)
				expect(pitch).to.aboutEqual(0.007962478, 1e-8)
				expect(yaw).to.aboutEqual(-0.009287607, 1e-8)

				-- t = 1.125 s: k is at its floor 0.2, p = 0.3375
				pitch, yaw = M.SwayOffset(1.125, false, false, false)
				expect(pitch).to.aboutEqual(-0.002138416, 1e-8)
				expect(yaw).to.aboutEqual(0.001567496, 1e-8)

				-- t = 5 s: k = 0.2, p = 0.5 (the phase wraps at 1): no pitch, the yaw at +0.003
				pitch, yaw = M.SwayOffset(5, false, false, false)
				expect(pitch).to.aboutEqual(0, 1e-9)
				expect(yaw).to.aboutEqual(0.003, 1e-9)

				-- absolute, never accumulated: the same time gives the same answer, and a time 10 s on (p back to the same
				-- place, k at its floor) never grows past the floor
				local a1, a2 = M.SwayOffset(0.3, false, false, false)
				local b1, b2 = M.SwayOffset(0.3, false, false, false)
				expect(a1).to.equal(b1)
				expect(a2).to.equal(b2)

				for t = 1, 200 do
					local p, y = M.SwayOffset(t * 0.37, false, false, false)
					expect(math.abs(p) <= 0.012 * 0.2 + 1e-12 or t * 0.37 < 0.9).to.beTrue()
					expect(math.abs(y) <= 0.015 * 0.2 + 1e-12 or t * 0.37 < 0.9).to.beTrue()
				end
			end
		},
		{
			name = "sway: crouching scales it by 0.75, lying down by 0.5, the strength mode by 0.75 (they multiply), and nonsense in gives no sway",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local p0, y0 = M.SwayOffset(0.3, false, false, false)

				local p, y = M.SwayOffset(0.3, true, false, false)
				expect(p).to.aboutEqual(p0 * 0.75, 1e-12)
				expect(y).to.aboutEqual(y0 * 0.75, 1e-12)
				expect(p).to.aboutEqual(0.005971859, 1e-8)

				p, y = M.SwayOffset(0.3, false, true, false)
				expect(p).to.aboutEqual(p0 * 0.5, 1e-12)
				expect(y).to.aboutEqual(-0.004643803, 1e-8)

				p, y = M.SwayOffset(0.3, false, false, true)
				expect(p).to.aboutEqual(p0 * 0.75, 1e-12)
				expect(y).to.aboutEqual(y0 * 0.75, 1e-12)

				p, y = M.SwayOffset(0.3, true, false, true)
				expect(p).to.aboutEqual(p0 * 0.5625, 1e-12)
				expect(y).to.aboutEqual(-0.005224279, 1e-8)

				-- lying down wins over crouching (one stance at a time)
				p = M.SwayOffset(0.3, true, true, false)
				expect(p).to.aboutEqual(p0 * 0.5, 1e-12)

				-- a time that is not a number: none
				p, y = M.SwayOffset(nil, false, false, false)
				expect(p).to.equal(0)
				expect(y).to.equal(0)
				p, y = M.SwayOffset(0 / 0, false, false, false)
				expect(p).to.equal(0)
				expect(y).to.equal(0)
			end
		},
		{
			name = "sway state: it starts again from zero each time the binoculars are raised, follows the clock while they are up (a long frame is cut at 0.1 s), and gives nothing (and forgets) while they are down",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local s = M.NewSway()

				expect(M.SwayStep(s, false, 0)).to.beNil()

				-- first frame: t = 0
				local pitch, yaw = M.SwayStep(s, true, 10)
				expect(pitch).to.aboutEqual(0, 1e-9)
				expect(yaw).to.aboutEqual(-0.015, 1e-9)

				-- 0.3 s later
				pitch, yaw = M.SwayStep(s, true, 10.1)
				pitch, yaw = M.SwayStep(s, true, 10.2)
				pitch, yaw = M.SwayStep(s, true, 10.3)
				expect(pitch).to.aboutEqual(0.007962478, 1e-8)
				expect(yaw).to.aboutEqual(-0.009287607, 1e-8)

				-- the same frame again changes nothing
				local again1, again2 = M.SwayStep(s, true, 10.3)
				expect(again1).to.aboutEqual(pitch, 1e-12)
				expect(again2).to.aboutEqual(yaw, 1e-12)

				-- a stall of 5 s counts 0.1 s only
				pitch, yaw = M.SwayStep(s, true, 15.3)
				local p2, y2 = M.SwayOffset(0.4, false, false, false)
				expect(pitch).to.aboutEqual(p2, 1e-9)
				expect(yaw).to.aboutEqual(y2, 1e-9)

				-- let go: nothing, and the state is back at the start
				expect(M.SwayStep(s, false, 16)).to.beNil()
				expect(s.t).to.equal(0)
				expect(s.last).to.beNil()

				-- raised again: from zero, whatever the clock says
				pitch, yaw = M.SwayStep(s, true, 100)
				expect(yaw).to.aboutEqual(-0.015, 1e-9)

				-- the stance and the strength mode are read each frame
				pitch, yaw = M.SwayStep(s, true, 100.1, true, false, false)
				local q1, q2 = M.SwayOffset(0.1, true, false, false)
				expect(pitch).to.aboutEqual(q1, 1e-9)
				expect(yaw).to.aboutEqual(q2, 1e-9)

				M.SwayReset(s)
				expect(s.t).to.equal(0)
			end
		},
		{
			name = "sway stance: crouching from Crouching(), lying down from IsProne() when an addon has it, the strength mode from the suit's mode",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local ply = {Crouching = function() return true end, NanosuitMode = GryMod.Modes.STRENGTH}
				local crouch, prone, strength = M.SwayStance(ply)
				expect(crouch).to.beTrue()
				expect(prone).to.beFalse()
				expect(strength).to.beTrue()

				ply = {Crouching = function() return false end, IsProne = function() return true end, NanosuitMode = GryMod.Modes.SPEED}
				crouch, prone, strength = M.SwayStance(ply)
				expect(crouch).to.beFalse()
				expect(prone).to.beTrue()
				expect(strength).to.beFalse()

				crouch, prone, strength = M.SwayStance({Crouching = function() return false end})
				expect(crouch).to.beFalse()
				expect(prone).to.beFalse()
				expect(strength).to.beFalse()
			end
		},
		{
			name = "sway in CalcView: with the option on and the binoculars up it adds the offsets (in degrees) to the view's pitch and yaw and leaves the rest (the field of view too); nothing at all otherwise, and what was added is gone when they are let go",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local now, wanted, enabled, stages, sway, clock = 0, M.Wanted, M.Enabled, M.StagesEnabled, M.SwayEnabled, M.Now
				local ply = {GetInfoNum = function(self, name, default) return name == "fov_desired" and 100 or default end, Crouching = function() return false end}
				local origin, angles = Vector(1, 2, 3), Angle(4, 5, 6)
				local want, on = true, true

				local ok, err = pcall(function()
					M.Now = function() return now end
					M.Wanted = function() return want end
					M.Enabled = function() return true end
					M.StagesEnabled = function() return false end
					M.SwayEnabled = function() return on end
					M.SwayReset(M.SwayState)

					-- first frame: t = 0, yaw -0.015 rad
					local view = M.CalcView(ply, origin, angles, 90, 3, 8000)
					expect(view).toNot.beNil()
					expect(view.fov).to.equal(90)
					expect(view.origin).to.equal(origin)
					expect(view.znear).to.equal(3)
					expect(view.zfar).to.equal(8000)
					expect(view.angles.p).to.aboutEqual(4, 1e-4)
					expect(view.angles.y).to.aboutEqual(5 + math.deg(-0.015), 1e-4)
					expect(view.angles.r).to.aboutEqual(6, 1e-4)
					-- the caller's angles are not touched
					expect(angles.y).to.aboutEqual(5, 1e-9)

					-- 0.3 s on (frames of 0.1 s)
					for i = 1, 3 do
						now = i * 0.1
						view = M.CalcView(ply, origin, angles, 90, 3, 8000)
					end

					expect(view.angles.p).to.aboutEqual(4 + math.deg(0.007962478), 1e-4)
					expect(view.angles.y).to.aboutEqual(5 + math.deg(-0.009287607), 1e-4)

					-- the same frame again: the same view (recalculated, not accumulated)
					local again = M.CalcView(ply, origin, angles, 90, 3, 8000)
					expect(again.angles.p).to.aboutEqual(view.angles.p, 1e-9)
					expect(again.angles.y).to.aboutEqual(view.angles.y, 1e-9)

					-- let go: nothing, state gone
					want = false
					now = 1
					expect(M.CalcView(ply, origin, angles, 90, 3, 8000)).to.beNil()
					expect(M.SwayState.t).to.equal(0)
					expect(M.SwayState.last).to.beNil()

					-- the option off while up: nothing
					want = true
					on = false
					expect(M.CalcView(ply, origin, angles, 90, 3, 8000)).to.beNil()
					expect(M.SwayState.last).to.beNil()
				end)

				M.Now, M.Wanted, M.Enabled, M.StagesEnabled, M.SwayEnabled = clock, wanted, enabled, stages, sway
				M.SwayReset(M.SwayState)
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "sway with the stages: one view with the stage's field of view and the swayed angles; Reset puts the sway away; it has its own switch (gry_binoculars_sway, saved, OFF by default) with a check box",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local now, wanted, enabled, stages, sway, clock = 0, M.Wanted, M.Enabled, M.StagesEnabled, M.SwayEnabled, M.Now
				local ply = {GetInfoNum = function(self, name, default) return name == "fov_desired" and 100 or default end, Crouching = function() return false end}

				local ok, err = pcall(function()
					M.Now = function() return now end
					M.Wanted = function() return true end
					M.Enabled = function() return true end
					M.StagesEnabled = function() return true end
					M.SwayEnabled = function() return true end
					M.SwayReset(M.SwayState)
					M.ZoomReset(M.ZoomState)

					M.CalcView(ply, Vector(), Angle(), 100, 1, 1)
					-- (a frame counts 0.1 s at most: two frames to reach 0.2 s)
					now = 0.1
					M.CalcView(ply, Vector(), Angle(), 40, 1, 1)
					now = 0.2
					local view = M.CalcView(ply, Vector(), Angle(), 40, 1, 1)
					expect(view.fov).to.aboutEqual(M.StageFov(100, 2), 1e-6)
					local p, y = M.SwayOffset(0.2, false, false, false)
					expect(view.angles.p).to.aboutEqual(math.deg(p), 1e-4)
					expect(view.angles.y).to.aboutEqual(math.deg(y), 1e-4)

					M.Reset()
					expect(M.SwayState.t).to.equal(0)
					expect(M.SwayState.last).to.beNil()
				end)

				M.Now, M.Wanted, M.Enabled, M.StagesEnabled, M.SwayEnabled = clock, wanted, enabled, stages, sway
				M.SwayReset(M.SwayState)
				M.ZoomReset(M.ZoomState)

				if not ok then
					error(err, 0)
				end

				local convar = GetConVar("gry_binoculars_sway")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0")
				expect(isfunction(M.SwayEnabled)).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok2, err2 = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok2 then
					error(err2, 0)
				end

				expect(found["gry_binoculars_sway"]).to.beTrue()
			end
		},
		{
			name = "vision (recipe 8.1): the interlacing is a triangle wave of the pixel row, period 4, times 1.5: rows 0 and 3 of each group at 1.3125, rows 1 and 2 at 0.9375",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local expected = {1.3125, 0.9375, 0.9375, 1.3125}

				for row = 0, 11 do
					expect(M.InterlaceGain(row)).to.aboutEqual(expected[row % 4 + 1], 1e-9)
				end

				-- the tint (0.7, 0.8, 1.0) times it, per row of the pattern
				local r, g, b = M.VisionRowGains(0)
				expect(r).to.aboutEqual(0.91875, 1e-9)
				expect(g).to.aboutEqual(1.05, 1e-9)
				expect(b).to.aboutEqual(1.3125, 1e-9)
				r, g, b = M.VisionRowGains(1)
				expect(r).to.aboutEqual(0.65625, 1e-9)
				expect(g).to.aboutEqual(0.75, 1e-9)
				expect(b).to.aboutEqual(0.9375, 1e-9)
				-- a row is its place in the group of four
				r, g, b = M.VisionRowGains(7)
				expect(r).to.aboutEqual(0.91875, 1e-9)

				-- the mean of the four rows is 1.125 (two bright, two dim)
				local sum = 0
				for row = 0, 3 do sum = sum + M.InterlaceGain(row) end
				expect(sum / 4).to.aboutEqual(1.125, 1e-9)
			end
		},
		{
			name = "vision: the tint texel holds half the gain of the bright rows in gamma mode ((117, 134, 167)) and, in linear mode (the framebuffer blends in linear light and a 2D draw is attenuated, measured), the level worked back through the sRGB curves and the attenuation ((184, 209, 255): the blue falls 2 % short, 255 is the limit); the dim rows' grey texel holds the ratio of the two gains (0.714: 91 in gamma mode, 145 in linear mode)",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local r, g, b = M.VisionTintTexel("gamma")
				expect(r).to.equal(117)
				expect(g).to.equal(134)
				expect(b).to.equal(167)
				r, g, b = M.VisionTintTexel("linear")
				expect(r).to.equal(184)
				expect(g).to.equal(209)
				expect(b).to.equal(255)

				expect(M.VisionDimRatio()).to.aboutEqual(0.9375 / 1.3125, 1e-9)
				expect(M.VisionDimTexel("gamma")).to.equal(91)
				expect(M.VisionDimTexel("linear")).to.equal(145)

				-- in gamma space every gain of the shader is reachable
				expect(M.VisionLevel(1.3125, "gamma") <= 1).to.beTrue()
				-- in linear light the largest (1.3125) is just out of reach and the byte stops at 255
				expect(M.VisionLevel(1.3125, "linear") > 1).to.beTrue()

				-- the dim rows are rows 1 and 2 of each four
				for row = 0, 11 do
					expect(M.VisionIsDim(row)).to.equal(row % 4 == 1 or row % 4 == 2)
				end
			end
		},
		{
			name = "vision: the sRGB curves are each other's inverse, and the blend's space is told from one measured ratio: a pixel at the middle times the tint texel gives the green gain in linear light (about 1.05) and twice the texel in gamma space",
			func = function(state)
				local M = GryMod.FlashBinoculars

				for _, v in ipairs({0, 0.001, 0.02, 0.1, 0.3, 0.5, 0.8, 1}) do
					expect(M.SrgbEncode(M.SrgbDecode(v))).to.aboutEqual(v, 1e-9)
				end

				expect(M.SrgbDecode(0.5)).to.aboutEqual(0.21404, 1e-4)

				-- the texel built for linear light, drawn over pixels from 0.3 to 0.7: the ratio is the green gain 1.05, give or take a percent
				local _, texel = M.VisionTintTexel("linear")
				for _, dest in ipairs({0.3, 0.5, 0.7}) do
					local ratio = M.VisionPredict(texel / 255, dest, "linear")
					expect(ratio).to.aboutEqual(1.05, 0.05)
					expect(M.VisionClassify(ratio, texel / 255, dest)).to.equal("linear")
					-- a gamma-space framebuffer would have doubled the texel
					expect(M.VisionClassify(2 * texel / 255, texel / 255, dest)).to.equal("gamma")
				end

				-- the texel built for gamma space, measured in either
				_, texel = M.VisionTintTexel("gamma")
				expect(M.VisionPredict(texel / 255, 0.5, "gamma")).to.aboutEqual(1.05, 0.01)
				expect(M.VisionClassify(M.VisionPredict(texel / 255, 0.5, "gamma"), texel / 255, 0.5)).to.equal("gamma")
				expect(M.VisionClassify(M.VisionPredict(texel / 255, 0.5, "linear"), texel / 255, 0.5)).to.equal("linear")
			end
		},
		{
			name = "vision: the blend's space is measured on the first channel of a probe pixel that has a value from 60 to 150 (a dark or a bright channel is no use), none when there is none",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.VisionProbeChannel(100, 100, 100)).to.equal(1)
				expect(M.VisionProbeChannel(10, 100, 200)).to.equal(2)
				expect(M.VisionProbeChannel(10, 200, 150)).to.equal(3)
				expect(M.VisionProbeChannel(60, 200, 200)).to.equal(1)
				expect(M.VisionProbeChannel(59, 151, 255)).to.beNil()
				expect(M.VisionProbeChannel(0, 0, 0)).to.beNil()
				expect(M.VisionProbeChannel(255, 255, 255)).to.beNil()
			end
		},
		{
			name = "vision: the vignette is saturate(1 - 0.6 * distance from the centre in texture units): 1 at the centre, 0.70 at the middle of any edge, 0.576 in the corners, an ellipse on a wide screen, and its texel in 8 bits follows the blend's space",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.VignetteGain(0.5, 0.5)).to.aboutEqual(1, 1e-9)
				expect(M.VignetteGain(0, 0.5)).to.aboutEqual(0.7, 1e-9)
				expect(M.VignetteGain(1, 0.5)).to.aboutEqual(0.7, 1e-9)
				expect(M.VignetteGain(0.5, 0)).to.aboutEqual(0.7, 1e-9)
				expect(M.VignetteGain(0.5, 1)).to.aboutEqual(0.7, 1e-9)
				expect(M.VignetteGain(0, 0)).to.aboutEqual(0.5757359, 1e-6)
				expect(M.VignetteGain(1, 1)).to.aboutEqual(0.5757359, 1e-6)
				-- beyond the screen it stays between 0 and 1
				expect(M.VignetteGain(10, 10) >= 0).to.beTrue()
				expect(M.VignetteGain(0.5, 0.5) <= 1).to.beTrue()
				-- the grey of the texture: half the gain in gamma mode, worked back through the sRGB curves and the attenuation in linear mode
				expect(M.VignetteTexel(0.5, 0.5, "gamma")).to.equal(128)
				expect(M.VignetteTexel(0, 0.5, "gamma")).to.equal(89)
				expect(M.VignetteTexel(0, 0, "gamma")).to.equal(73)
				expect(M.VignetteTexel(0.5, 0.5, "linear")).to.equal(200)
				expect(M.VignetteTexel(0, 0.5, "linear")).to.equal(142)
				expect(M.VignetteTexel(0, 0, "linear")).to.equal(118)
			end
		},
		{
			name = "vision hook: it is on RenderScreenspaceEffects only while the binoculars are up and the option and the HUD element are on; down (or off) there is no hook at all",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local vision, enabled = M.VisionEnabled, M.Enabled
				local on, hud = true, true

				local function hooked()
					local list = hook.GetTable().RenderScreenspaceEffects
					return list ~= nil and list["GRYBINOCULARSVISION"] ~= nil
				end

				local ok, err = pcall(function()
					M.VisionEnabled = function() return on end
					M.Enabled = function() return hud end

					M.VisionStep(false)
					expect(hooked()).to.beFalse()
					M.VisionStep(true)
					expect(hooked()).to.beTrue()
					-- asked again every frame: still one hook
					M.VisionStep(true)
					expect(hooked()).to.beTrue()
					M.VisionStep(false)
					expect(hooked()).to.beFalse()

					on = false
					M.VisionStep(true)
					expect(hooked()).to.beFalse()
					on = true
					M.VisionStep(true)
					expect(hooked()).to.beTrue()
					-- the option switched off while up
					on = false
					M.VisionStep(true)
					expect(hooked()).to.beFalse()
					on = true

					-- the HUD element off
					M.VisionStep(true)
					hud = false
					M.VisionStep(true)
					expect(hooked()).to.beFalse()
					hud = true

					-- Reset takes it away
					M.VisionStep(true)
					expect(hooked()).to.beTrue()
					M.Reset()
					expect(hooked()).to.beFalse()
				end)

				M.VisionStep(false)
				M.VisionEnabled, M.Enabled = vision, enabled

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "vision, drawing: three passes in 2D, all with the doubling blend (the tint over the whole screen, the dim rows as strips of two rows from row 1 every four, the vignette), the blend put back and the 2D ended even if a draw fails; nothing at all when the binoculars are down, in third person or the option is off",
			func = function(state)
				local M = GryMod.FlashBinoculars
				local saved = {M.VisionEnabled, M.Enabled, M.Wanted, M.VisionBuild, render.OverrideBlend, cam.Start2D, cam.End2D, surface.SetMaterial,
					surface.SetDrawColor, surface.DrawTexturedRect, LocalPlayer}
				local state2 = M.VisionState
				local savedMaterials = {state2.tint, state2.dim, state2.vignette, state2.mode}
				local log = {}
				local want, thirdPerson, failing = true, false, false
				local builds = 0

				local ok, err = pcall(function()
					M.VisionEnabled = function() return true end
					M.Enabled = function() return true end
					M.Wanted = function() return want end
					M.VisionBuild = function() builds = builds + 1 return true end
					state2.tint, state2.dim, state2.vignette, state2.mode = "tint", "dim", "vignette", "linear"
					render.OverrideBlend = function(enable, src, dst, func) log[#log + 1] = {"blend", enable, src, dst, func} end
					cam.Start2D = function() log[#log + 1] = {"start2d"} end
					cam.End2D = function() log[#log + 1] = {"end2d"} end
					surface.SetMaterial = function(m) log[#log + 1] = {"material", m} end
					surface.SetDrawColor = function() end
					surface.DrawTexturedRect = function(x, y, w, h)
						if failing then error("draw failed") end
						log[#log + 1] = {"rect", x, y, w, h}
					end
					LocalPlayer = function() return {ShouldDrawLocalPlayer = function() return thirdPerson end} end

					M.DrawVision()

					local height, width = ScrH(), ScrW()
					local strips = math.ceil((height - 1) / 4)
					local names = {}
					for i, entry in ipairs(log) do names[i] = entry[1] end
					local expectedNames = {"start2d", "blend", "material", "rect", "material"}
					for _ = 1, strips do expectedNames[#expectedNames + 1] = "rect" end
					expectedNames[#expectedNames + 1] = "material"
					expectedNames[#expectedNames + 1] = "rect"
					expectedNames[#expectedNames + 1] = "blend"
					expectedNames[#expectedNames + 1] = "end2d"
					expect(table.concat(names, ",")).to.equal(table.concat(expectedNames, ","))

					-- the tint: 2 * source * destination, the whole screen
					expect(log[2][2]).to.beTrue()
					expect(log[2][3]).to.equal(BLEND_DST_COLOR)
					expect(log[2][4]).to.equal(BLEND_SRC_COLOR)
					expect(log[3][2]).to.equal("tint")
					expect(log[4][2]).to.equal(0)
					expect(log[4][3]).to.equal(0)
					expect(log[4][4]).to.equal(width)
					expect(log[4][5]).to.equal(height)

					-- the dim rows: the same blend, a strip of two rows at rows 1, 5, 9, ... and each as wide as the screen
					expect(log[5][2]).to.equal("dim")

					for k = 1, strips do
						local rect = log[5 + k]
						expect(rect[3]).to.equal(1 + (k - 1) * 4)
						expect(rect[4]).to.equal(width)
						expect(rect[5]).to.equal(math.min(2, height - rect[3]))
						-- every pixel row of a strip is a dim row, and no dim row is left out
						for row = rect[3], rect[3] + rect[5] - 1 do expect(M.VisionIsDim(row)).to.beTrue() end
					end

					local covered = 0
					for k = 1, strips do covered = covered + log[5 + k][5] end
					local dimRows = 0
					for row = 0, height - 1 do if M.VisionIsDim(row) then dimRows = dimRows + 1 end end
					expect(covered).to.equal(dimRows)

					-- the vignette: the same blend, the whole screen, last
					expect(log[6 + strips][2]).to.equal("vignette")
					expect(log[7 + strips][4]).to.equal(width)
					expect(log[7 + strips][5]).to.equal(height)
					expect(log[#log - 1][2]).to.beFalse()

					-- a draw that fails: the blend is back to normal and the 2D is ended
					log = {}
					failing = true
					M.DrawVision()
					failing = false
					expect(log[#log][1]).to.equal("end2d")
					expect(log[#log - 1][1]).to.equal("blend")
					expect(log[#log - 1][2]).to.beFalse()

					-- nothing drawn: binoculars down, third person, option off, HUD element off
					local function silent()
						log = {}
						M.DrawVision()
						expect(#log).to.equal(0)
					end

					want = false
					silent()
					want = true
					thirdPerson = true
					silent()
					thirdPerson = false
					M.VisionEnabled = function() return false end
					silent()
					M.VisionEnabled = function() return true end
					M.Enabled = function() return false end
					silent()

					-- the materials are asked for once the drawing is certain
					expect(builds).to.equal(2)
				end)

				M.VisionEnabled, M.Enabled, M.Wanted, M.VisionBuild, render.OverrideBlend, cam.Start2D, cam.End2D, surface.SetMaterial,
					surface.SetDrawColor, surface.DrawTexturedRect, LocalPlayer = unpack(saved, 1, 11)
				state2.tint, state2.dim, state2.vignette, state2.mode = savedMaterials[1], savedMaterials[2], savedMaterials[3], savedMaterials[4]

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "vision: the textures and materials are built once (two 'build' calls give the same materials), and the vision has its own switch (gry_binoculars_vision, saved, OFF by default) with an honest check box",
			func = function(state)
				local M = GryMod.FlashBinoculars
				expect(M.VisionBuild()).to.beTrue()
				local tint, dim, vignette, builds = M.VisionState.tint, M.VisionState.dim, M.VisionState.vignette, M.VisionState.builds
				expect(tint).toNot.beNil()
				expect(dim).toNot.beNil()
				expect(vignette).toNot.beNil()
				expect(M.VisionBuild()).to.beTrue()
				expect(M.VisionState.tint).to.equal(tint)
				expect(M.VisionState.dim).to.equal(dim)
				expect(M.VisionState.vignette).to.equal(vignette)
				expect(M.VisionState.builds).to.equal(builds)

				local convar = GetConVar("gry_binoculars_vision")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("0")
				expect(isfunction(M.VisionEnabled)).to.beTrue()

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = child:GetText()
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				local text = found["gry_binoculars_vision"]
				expect(text).toNot.beNil()
				-- honest: the original has it on High quality only, and it doubles the film's vignette
				expect(string.find(text, "High", 1, true)).toNot.beNil()
				expect(string.find(text, "vignette", 1, true)).toNot.beNil()
			end
		},
		{
			name = "a missing movie gives no binoculars instead of an error",
			func = function(state)
				expect(GryMod.FlashBinoculars.New(nil)).to.equal(nil)
			end
		}
	}
}
