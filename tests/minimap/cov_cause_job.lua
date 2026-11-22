-- Causes of the veils left after the preload (lua_job, CLIENT realm; load preload_coverage_job.lua first with lua_exec_file). The same walk as COV.eval (the centres of the
-- navigation mesh in data/grymod_tmp/centres.txt when args.points == "nav", else the graph's ground nodes), done FORWARD and BACKWARD on the cache the preload made.
-- For every tile under the player that is missing the first time it is needed (a veil), the level SHOWN (CurrentAt, with the display hold) is compared with the
-- level OF THE PLACE (PeekAt: no memory):
--   a_never_prepared  shown == the place's level, and its tile was not made by the preload (coverage);
--   b_path            shown ~= the place's level (what the hold or any memory shows depends on the way the player came);
-- plus, at every step, whether shown ~= place's level (the hold is active), and whether the level shown at a place differs between the two directions.
-- Also the same walks with the hold off (TileReady always false): the veils of a display with no memory at all.
local M = GryMod.Minimap
local Z = GryMod.ZoneMapClient

job:wait(function() return Z and Z.Boxes and type(Z.Boxes()) == "table" end, 120)

local pts = (job.args and job.args.points == "nav") and COV.readCentres("grymod_tmp/" .. (job.args.name or ("cov_centres_" .. game.GetMap())) .. ".txt") or nil
local begun = COV.begin({points = pts})
local G = M.Gen

job:sleep(2)
job:wait(function()
	local p = G.PreloadProgress()

	return p and p.total and p.total > 0 and G.Pending() == 0 and (p.done or 0) + (p.failed or 0) >= p.total
end, 1500)

local F, C, S = M.Floors, M.Cache, M.Settings
local k = S.ScreenConstant()
local res = S.TileRes()
local foot = GetConVar("gry_radar_zoom_foot"):GetFloat()
local indoor = GetConVar("gry_radar_zoom_indoor"):GetFloat()

local function walk(route, noHold)
	local seen, shownAt = {}, {}
	local out = {veil = 0, a_never_prepared = 0, a_open = 0, b_path = 0, held_steps = 0, steps = 0}
	local def = S.Definition()
	local clock = 1000
	local realRT, realReady = RealTime, F.TileReady

	F.Reset()
	RealTime = function() return clock end

	if noHold then
		F.TileReady = function() return false end
	end

	local ok, err = pcall(function()
		for i = 1, #route do
			local p = route[i]

			clock = clock + 0.3
			out.steps = out.steps + 1

			local pos = Vector(p.x, p.y, p.z)
			local inside = Z.Indoor(pos) == true

			def = S.AutoDefinitionFor(k / (inside and indoor or foot), def)

			local level = F.CurrentAt(pos)
			local own = F.PeekAt(p.x, p.y, p.z)

			shownAt[i] = level.id

			if own and own.id ~= level.id then
				out.held_steps = out.held_steps + 1
			end

			local ux, uy = C.TileOf(p.x, p.y, res, def)
			local key = level.id .. "|" .. ux .. "," .. uy .. "," .. def

			if not seen[key] then
				seen[key] = true

				if not C.Has({level = level.id, tx = ux, ty = uy, res = res, ppm = def}) then
					out.veil = out.veil + 1

					if own and own.id ~= level.id then
						out.b_path = out.b_path + 1
					elseif level.open then
						out.a_open = out.a_open + 1
					else
						out.a_never_prepared = out.a_never_prepared + 1
					end
				end
			end

			if i % 200 == 0 then
				job:yield()
			end
		end
	end)

	RealTime = realRT
	F.TileReady = realReady
	F.Reset()

	if not ok then
		error(err)
	end

	return out, shownAt
end

local route = COV.nav
local back = {}

for i = #route, 1, -1 do
	back[#back + 1] = route[i]
end

local fwd, shownF = walk(route, false)
local bwd, shownB = walk(back, false)
local fwdNo = walk(route, true)
local bwdNo = walk(back, true)
local differ = 0

for i = 1, #route do
	if shownF[i] ~= shownB[#route + 1 - i] then
		differ = differ + 1
	end
end

COV.finish()

return {begun = begun, forward = fwd, backward = bwd, forwardNoHold = fwdNo, backwardNoHold = bwdNo, stepsShownDifferentByDirection = differ, steps = #route}
