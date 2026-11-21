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
			name = "a missing movie gives no binoculars instead of an error",
			func = function(state)
				expect(GryMod.FlashBinoculars.New(nil)).to.equal(nil)
			end
		}
	}
}
