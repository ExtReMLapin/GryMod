-- Preloading of the interface.
--
-- A part of the interface that is used for the first time loads its movie (a Lua table of 50 to 200 KB, 3 to 5 ms) and
-- turns the atlas pictures it draws into materials: Material() decodes the PNG and builds its mip levels, about 0.6 s
-- for each 2048 x 4096 picture and 1.2 s for the quick menu's 4096 x 4096 ones, and it cannot be cut in pieces. Done
-- on demand that is a freeze of a second or two when the quick menu or the binoculars come up for the first time (and
-- of three seconds at the first spawn).
--
-- This file does the same work ahead of time, one piece at a time, for what is switched on:
--   gry_hud_prewarm 1: all of it at the loading screen (InitPostEntity runs while it is still up: nobody sees the
--                      freeze, the map just takes longer to open);
--   gry_hud_prewarm 2: the pieces drawn at the spawn at the loading screen, the others one step at a time over the
--                      first seconds of play (each step is a short freeze, kept apart from the next one);
--   gry_hud_prewarm 0: nothing, every part loads when it is first used.
-- The work is a list of steps ("load this movie", "make this picture's material"); a movie's step adds the steps of its
-- pictures when it runs, because the movie says which pictures it uses.

GryMod = GryMod or {}

local Flash = GryMod.Flash

local Prewarm = GryMod.FlashPrewarm or {}
GryMod.FlashPrewarm = Prewarm

local MODE = CreateClientConVar("gry_hud_prewarm", "1", true, false,
	"Preload the interface (0: off, 1: at the loading screen, 2: spread over the first seconds of play)", 0, 2)

local SPREAD_BUDGET = 3 -- ms of work per frame while spreading (a step that does not fit still runs, alone)
local SPREAD_GAP = 0.5 -- seconds left after a step that used more than the budget (a freeze) before the next one
local SPREAD_DELAY = 1.5 -- seconds after the spawn before the spreading starts

local queue = {}
local startAt, nextAt = 0, 0

Prewarm.Log = {} -- {label, ms} of the last steps run, to see what the loading cost

local function note(label, ms)
	local log = Prewarm.Log

	if #log >= 64 then
		table.remove(log, 1)
	end

	log[#log + 1] = {label, ms}
end

local function movieNames(...)
	local names = {}

	for index = 1, select("#", ...) do
		local name = select(index, ...)

		if name then
			names[#names + 1] = name
		end
	end

	return names
end

local function movieOf(module, field)
	return GryMod[module] and GryMod[module][field] or nil
end

-- What the interface is made of, in the order it is needed: tier 1 is drawn right at the spawn, tier 2 later (a key
-- pressed, a grenade, a malfunction). option = the HUD setting that turns the piece off, hud = the piece needs gry_hud
-- (the quick menu works without the HUD). films = the names of its movies (a function: the modules are loaded after
-- this file's data, and a movie may be missing).
Prewarm.Pieces = {
	{name = "status", tier = 1, hud = true, option = "status", films = function()
		return movieNames(movieOf("FlashHUD", "MOVIE"))
	end},
	{name = "radar", tier = 1, hud = true, option = "radar", films = function()
		return movieNames(movieOf("FlashRadar", "MOVIE"))
	end},
	{name = "crosshair", tier = 1, hud = true, option = "crosshair", films = function()
		return movieNames(movieOf("FlashCrosshair", "MOVIE"), movieOf("FlashCrosshair", "FRIENDLY_MOVIE"))
	end},
	{name = "initialize", tier = 1, hud = true, option = "boot", films = function()
		local movies = movieOf("FlashBoot", "MOVIES")

		return movieNames(movies and movies.initialize)
	end},
	{name = "quickmenu", tier = 2, hud = false, option = "quickmenu", films = function()
		return movieNames(movieOf("FlashMenu", "MOVIE"))
	end},
	{name = "binoculars", tier = 2, hud = true, option = "binoculars", films = function()
		return movieNames(movieOf("FlashBinoculars", "MOVIE"))
	end},
	{name = "grenade", tier = 2, hud = true, option = "grenade", films = function()
		return movieNames(movieOf("FlashGrenade", "MOVIE"))
	end},
	{name = "malfunction", tier = 2, hud = true, option = "boot", films = function()
		local movies = movieOf("FlashBoot", "MOVIES")

		return movieNames(movies and movies.lost, movies and movies.reboot)
	end}
}

local function hudOn()
	local convar = GetConVar("gry_hud")

	return not convar or convar:GetBool()
end

local function wanted(piece)
	if MODE:GetInt() == 0 then
		return false
	end

	if piece.hud and not hudOn() then
		return false
	end

	return not piece.option or not GryMod.HUDOptions or GryMod.HUDOptions.Enabled(piece.option)
end

-- The pictures a movie draws: each atlas, and the white twin of the ones that have one (the shapes a colour-set clip
-- repaints come from it).
local function atlasPaths(movie)
	local paths = {}

	for index, path in ipairs(movie.atlases or {}) do
		paths[#paths + 1] = path

		local twin = Flash.AtlasPathFor(movie, index, 0, 0, 0)

		if twin ~= path then
			paths[#paths + 1] = twin
		end
	end

	return paths
end

-- Whether a movie and all its pictures are in memory (nothing left to do for it).
local function complete(name)
	if not Flash.Loaded(name) then
		return false
	end

	for _, path in ipairs(atlasPaths(Flash.Load(name))) do
		if not Flash.AtlasLoaded(path) then
			return false
		end
	end

	return true
end

-- The step of a movie: load it, then add the steps of its pictures (right after itself, with its tier).
local function filmStep(name, tier)
	return {
		film = name,
		tier = tier,
		label = "film " .. name,
		run = function(steps)
			local movie = Flash.Load(name)

			if not movie then
				return
			end

			local position = 1

			for _, path in ipairs(atlasPaths(movie)) do
				if not Flash.AtlasLoaded(path) then
					table.insert(steps, position, {
						tier = tier,
						label = "atlas " .. path,
						run = function()
							Flash.AtlasMaterial(path)
						end
					})

					position = position + 1
				end
			end
		end
	}
end

-- Everything that is switched on, as steps (whether it is loaded already or not).
function Prewarm.Plan()
	local plan = {}

	for _, piece in ipairs(Prewarm.Pieces) do
		if wanted(piece) then
			for _, name in ipairs(piece.films and piece.films() or {}) do
				plan[#plan + 1] = filmStep(name, piece.tier)
			end

			for _, step in ipairs(piece.extra and piece.extra() or {}) do
				plan[#plan + 1] = step
			end
		end
	end

	return plan
end

-- Runs steps from the front of the list while the time budget (ms) lasts: the step that uses it up is the last, and
-- at least one runs. Returns how many ran. A step that fails is reported and left behind.
function Prewarm.RunSteps(steps, budget)
	local start = SysTime()
	local done = 0

	while steps[1] do
		local step = table.remove(steps, 1)
		local began = SysTime()
		local ok, err = pcall(step.run, steps)
		local ms = (SysTime() - began) * 1000

		note(step.label or "step", ms)

		if not ok then
			MsgN("[GryMod] Preloading failed at ", step.label or "a step", ": ", tostring(err))
		end

		done = done + 1

		if (SysTime() - start) * 1000 >= budget then
			break
		end
	end

	return done
end

-- The work still to do: what is switched on and not loaded yet (replaces the list that was waiting).
function Prewarm.Fill()
	queue = {}

	for _, step in ipairs(Prewarm.Plan()) do
		if not step.film or not complete(step.film) then
			queue[#queue + 1] = step
		end
	end

	return #queue
end

function Prewarm.Pending()
	return #queue
end

-- Forgets the work waiting and the spreading's clock (tests).
function Prewarm.Clear()
	queue = {}
	startAt, nextAt = 0, 0
	Prewarm.Log = {}
end

-- Runs the waiting steps for as long as the budget (ms) lasts, only those of a tier up to `maxTier` when given.
function Prewarm.Run(budget, maxTier)
	local start = SysTime()
	local done = 0

	while queue[1] and (not maxTier or (queue[1].tier or 2) <= maxTier) do
		done = done + Prewarm.RunSteps(queue, 0)

		if (SysTime() - start) * 1000 >= budget then
			break
		end
	end

	return done
end

-- The level is loaded and the player is in it: InitPostEntity runs while the loading screen is still up.
function Prewarm.OnLoad()
	local mode = MODE:GetInt()

	Prewarm.Fill()
	startAt = RealTime() + SPREAD_DELAY
	nextAt = 0

	if mode == 1 then
		Prewarm.Run(math.huge)
	elseif mode == 2 then
		Prewarm.Run(math.huge, 1)
	end
end

-- One frame of the spreading: a step or two within the budget (ms), then a pause when a step was a freeze. `hidden`:
-- the game's menu is up, nobody sees a freeze, so no pause.
function Prewarm.Think(now, budget, hidden)
	if not queue[1] or MODE:GetInt() == 0 or now < startAt or (not hidden and now < nextAt) then
		return
	end

	local began = SysTime()
	Prewarm.RunSteps(queue, budget)

	nextAt = now + ((SysTime() - began) * 1000 > budget and SPREAD_GAP or 0)
end

hook.Add("InitPostEntity", "GRYPREWARM", Prewarm.OnLoad)

hook.Add("Think", "GRYPREWARM", function()
	if queue[1] then
		Prewarm.Think(RealTime(), SPREAD_BUDGET, gui.IsGameUIVisible())
	end
end)

-- A setting changes in the game: what became wanted is preloaded, spread over the next seconds.
local function refill()
	if not IsValid(LocalPlayer()) then
		return
	end

	Prewarm.Fill()
	startAt = RealTime() + 0.5
end

cvars.AddChangeCallback("gry_hud_prewarm", refill, "GryModPrewarm")
cvars.AddChangeCallback("gry_hud", refill, "GryModPrewarm")

for _, option in ipairs(GryMod.HUDOptions and GryMod.HUDOptions.List or {}) do
	cvars.AddChangeCallback("gry_hud_" .. option.name, refill, "GryModPrewarm")
end

-- this file loaded again in the middle of a game (no InitPostEntity coming): catch up, spread
refill()
