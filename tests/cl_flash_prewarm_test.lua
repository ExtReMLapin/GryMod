-- Tests of the preloading of the interface (GryMod.FlashPrewarm, cl_flash_prewarm.lua), GLuaTest format, client realm.
--
-- The first time a part of the interface is used it loads its movie (a big Lua table) and its atlas pictures
-- (Material() decodes the PNG and builds its mip levels: about 0.6 s for each 2048 x 4096 atlas, 1.2 s for the
-- quick menu's 4096 x 4096 ones), all in one frame: a freeze. The preloading does that work at the loading
-- screen (or, as an option, spread over the first seconds of play) and only for what is switched on.

local SWITCHES = {"status", "radar", "crosshair", "binoculars", "grenade", "quickmenu", "boot"}

local saved = {}
local pieces

local function filmNames()
	local names = {}

	for _, step in ipairs(GryMod.FlashPrewarm.Plan()) do
		if step.film then
			names[step.film] = true
		end
	end

	return names
end

local function busy(ms)
	local stop = SysTime() + ms / 1000

	while SysTime() < stop do
	end
end

-- Puts the movies and their pictures back in the state of a game that has not used them yet (only theirs: the other
-- parts of the interface keep what they loaded).
local function forget(...)
	for _, name in ipairs({...}) do
		local movie = GryMod.Flash.Load(name)

		for index, path in ipairs(movie and movie.atlases or {}) do
			GryMod.Flash.ForgetAtlas(path)
			GryMod.Flash.ForgetAtlas(GryMod.Flash.AtlasPathFor(movie, index, 0, 0, 0))
		end

		GryMod.Flash.Unload(name)
	end
end

local function everyAtlasLoaded(name)
	local movie = GryMod.Flash.Load(name)

	for index, path in ipairs(movie.atlases) do
		if not GryMod.Flash.AtlasLoaded(path) then
			return false
		end

		-- the white twin of an atlas draws the shapes a colour-set clip repaints
		local twin = GryMod.Flash.AtlasPathFor(movie, index, 0, 0, 0)

		if twin ~= path and not GryMod.Flash.AtlasLoaded(twin) then
			return false
		end
	end

	return true
end

return {
	groupName = "GryMod interface preloading",
	beforeAll = function(state)
		for _, name in ipairs(SWITCHES) do
			saved["gry_hud_" .. name] = GetConVar("gry_hud_" .. name):GetString()
		end

		saved.gry_hud = GetConVar("gry_hud"):GetString()
		saved.gry_hud_prewarm = GetConVar("gry_hud_prewarm"):GetString()
		pieces = GryMod.FlashPrewarm.Pieces
	end,
	afterEach = function(state)
		-- a failed test must not leave its settings, or its fake catalogue, to the next ones
		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end

		GryMod.FlashPrewarm.Pieces = pieces
		GryMod.FlashPrewarm.Clear()
	end,
	afterAll = function(state)
		for name, value in pairs(saved) do
			GetConVar(name):SetString(value)
		end

		GryMod.FlashPrewarm.Pieces = pieces
		GryMod.FlashPrewarm.Clear()
	end,
	cases = {
		{
			name = "the setting exists and is on by default",
			func = function(state)
				local convar = GetConVar("gry_hud_prewarm")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
			end
		},
		{
			name = "everything that is switched on is planned, the panels of the spawn first",
			func = function(state)
				for _, name in ipairs(SWITCHES) do
					GetConVar("gry_hud_" .. name):SetString("1")
				end

				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_prewarm"):SetString("1")

				local plan = GryMod.FlashPrewarm.Plan()
				local names = filmNames()

				for _, name in ipairs({"hud_ammohealthenergysuit", "hud_radarcompassstealth", "hud_crosshair", "hud_friendlycross",
					"hud_initialize", "hud_quickmenu", "hud_binoculars", "hud_grenadedetect", "hud_lost", "hud_reboot", "hud_sp_hexicons"}) do
					expect(names[name]).to.beTrue()
				end

				-- the spawn needs the status panel first; nothing of the other tier comes before a spawn piece
				expect(plan[1].film).to.equal("hud_ammohealthenergysuit")

				local seenLater = false

				for _, step in ipairs(plan) do
					if step.tier == 2 then
						seenLater = true
					else
						expect(seenLater).to.beFalse()
					end
				end
			end
		},
		{
			name = "an element that is switched off is not preloaded",
			func = function(state)
				GetConVar("gry_hud_prewarm"):SetString("1")

				for _, case in ipairs({
					{"status", "hud_ammohealthenergysuit"}, {"radar", "hud_radarcompassstealth"}, {"crosshair", "hud_crosshair"},
					{"crosshair", "hud_friendlycross"}, {"binoculars", "hud_binoculars"}, {"grenade", "hud_grenadedetect"},
					{"quickmenu", "hud_quickmenu"}, {"boot", "hud_initialize"}, {"boot", "hud_lost"}, {"boot", "hud_reboot"}
				}) do
					for _, name in ipairs(SWITCHES) do
						GetConVar("gry_hud_" .. name):SetString("1")
					end

					GetConVar("gry_hud_" .. case[1]):SetString("0")
					expect(filmNames()[case[2]]).to.beNil()
				end
			end
		},
		{
			name = "with the HUD off only the quick menu is preloaded (it works without the HUD)",
			func = function(state)
				for _, name in ipairs(SWITCHES) do
					GetConVar("gry_hud_" .. name):SetString("1")
				end

				GetConVar("gry_hud_prewarm"):SetString("1")
				GetConVar("gry_hud"):SetString("0")

				local names = filmNames()
				expect(names.hud_quickmenu).to.beTrue()
				expect(names.hud_ammohealthenergysuit).to.beNil()
				expect(names.hud_binoculars).to.beNil()
				expect(names.hud_initialize).to.beNil()
			end
		},
		{
			name = "with the setting off nothing is planned",
			func = function(state)
				GetConVar("gry_hud_prewarm"):SetString("0")
				expect(#GryMod.FlashPrewarm.Plan()).to.equal(0)
			end
		},
		{
			name = "a time budget stops the work after the step that used it up, and always lets one step run",
			func = function(state)
				local ran = 0
				local steps = {}

				for i = 1, 5 do
					steps[i] = {label = "fake " .. i, run = function() busy(3) ran = ran + 1 end}
				end

				local done = GryMod.FlashPrewarm.RunSteps(steps, 4)
				expect(done).to.equal(2) -- 3 ms < 4 ms: a second step starts, then 6 ms > 4 ms stops
				expect(ran).to.equal(2)
				expect(#steps).to.equal(3) -- the steps that ran are taken off the list

				expect(GryMod.FlashPrewarm.RunSteps(steps, 0)).to.equal(1) -- no budget: still one step, so the work goes on
				expect(GryMod.FlashPrewarm.RunSteps(steps, math.huge)).to.equal(2)
				expect(#steps).to.equal(0)
			end
		},
		{
			name = "a step that fails does not stop the others",
			func = function(state)
				local ran = 0
				local steps = {
					{label = "boom", run = function() error("on purpose") end},
					{label = "fine", run = function() ran = ran + 1 end}
				}

				expect(GryMod.FlashPrewarm.RunSteps(steps, math.huge)).to.equal(2)
				expect(ran).to.equal(1)
			end
		},
		{
			name = "preloading a film loads its movie and every atlas picture it can draw, white twins included",
			func = function(state)
				local P = GryMod.FlashPrewarm
				P.Pieces = {{name = "friendly", tier = 1, option = "crosshair", hud = true, films = function() return {"hud_friendlycross"} end}}
				GetConVar("gry_hud_prewarm"):SetString("1")
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_crosshair"):SetString("1")

				forget("hud_friendlycross")
				expect(GryMod.Flash.Loaded("hud_friendlycross")).to.beFalse()

				P.Fill()
				expect(P.Pending() > 0).to.beTrue()
				P.Run(math.huge)

				expect(P.Pending()).to.equal(0)
				expect(GryMod.Flash.Loaded("hud_friendlycross")).to.beTrue()
				expect(everyAtlasLoaded("hud_friendlycross")).to.beTrue()
				P.Fill()
				expect(P.Pending()).to.equal(0) -- nothing left to do
			end
		},
		{
			name = "after the preloading the first use of the grenade warning builds from what is loaded and costs about as much as the next one",
			func = function(state)
				local P = GryMod.FlashPrewarm
				local Grenade = GryMod.FlashGrenade
				P.Pieces = {{name = "grenade", tier = 2, option = "grenade", hud = true, films = function() return {"hud_grenadedetect"} end}}
				GetConVar("gry_hud_prewarm"):SetString("1")
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_grenade"):SetString("1")

				forget("hud_grenadedetect")
				P.Fill()
				P.Run(math.huge)

				local movie = GryMod.Flash.Load("hud_grenadedetect")
				expect(everyAtlasLoaded("hud_grenadedetect")).to.beTrue()
				expect(GryMod.Flash.Load("hud_grenadedetect")).to.equal(movie) -- the same table: not read again

				local function use()
					local t = SysTime()
					local warning = Grenade.New(GryMod.Flash.Load("hud_grenadedetect"))
					warning:Show()
					warning:Update(1 / 30)
					local ms = (SysTime() - t) * 1000
					GryMod.Flash.ReleaseClip(warning.root)

					return ms
				end

				local first = use()
				local second = use()
				-- generous bounds: the point is the difference with the 100 ms and more it took to load the pictures
				expect(first < 25).to.beTrue()
				expect(first < second * 10 + 5).to.beTrue()
			end
		},
		{
			name = "at the loading screen the whole plan runs in the mode 1, and only the spawn pieces in the mode 2",
			func = function(state)
				local P = GryMod.FlashPrewarm
				local ran = {}

				local function fake(name, tier)
					return {name = name, tier = tier, hud = false, films = function() return {} end,
						extra = function() return {{label = name, tier = tier, run = function() ran[#ran + 1] = name end}} end}
				end

				P.Pieces = {fake("a", 1), fake("b", 2)}

				GetConVar("gry_hud_prewarm"):SetString("1")
				P.Fill()
				P.OnLoad()
				expect(table.concat(ran, ",")).to.equal("a,b")
				expect(P.Pending()).to.equal(0)

				ran = {}
				GetConVar("gry_hud_prewarm"):SetString("2")
				P.Fill()
				P.OnLoad()
				expect(table.concat(ran, ",")).to.equal("a")
				expect(P.Pending()).to.equal(1)

				-- spread over the next frames: one step per call under the budget
				P.Think(RealTime() + 100, 3)
				expect(table.concat(ran, ",")).to.equal("a,b")
				expect(P.Pending()).to.equal(0)
			end
		},
		{
			name = "the spreading waits between expensive steps so that two freezes do not follow each other",
			func = function(state)
				local P = GryMod.FlashPrewarm
				local ran = 0

				P.Pieces = {{name = "slow", tier = 2, hud = false, films = function() return {} end,
					extra = function()
						local steps = {}

						for i = 1, 3 do
							steps[i] = {label = "slow " .. i, tier = 2, run = function() busy(8) ran = ran + 1 end}
						end

						return steps
					end}}

				GetConVar("gry_hud_prewarm"):SetString("2")
				P.Fill()
				local now = RealTime() + 100
				P.Think(now, 3)
				expect(ran).to.equal(1) -- one step used more than the budget
				P.Think(now + 0.01, 3)
				expect(ran).to.equal(1) -- too soon after it: nothing
				P.Think(now + 10, 3)
				expect(ran).to.equal(2)
			end
		},
		{
			name = "a switch turned on later gets its pictures preloaded too",
			func = function(state)
				local P = GryMod.FlashPrewarm
				GetConVar("gry_hud_prewarm"):SetString("1")
				GetConVar("gry_hud"):SetString("1")
				GetConVar("gry_hud_quickmenu"):SetString("0")
				P.Pieces = {{name = "quickmenu", tier = 2, option = "quickmenu", hud = false, films = function() return {"hud_friendlycross"} end}}
				forget("hud_friendlycross")
				P.Fill()
				expect(P.Pending()).to.equal(0)

				GetConVar("gry_hud_quickmenu"):SetString("1")
				P.Fill()
				expect(P.Pending() > 0).to.beTrue()
			end
		}
	}
}
