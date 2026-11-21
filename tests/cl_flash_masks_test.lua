-- Tests of the data of the converted movies (lua/grymod/flash/*.lua), GLuaTest format, client realm.
--
-- A clip layer (a placement with a clip depth, "cd") hides what is drawn above it outside its own shape. The
-- drawing code (cl_flash_draw.lua) can only cut a picture along the outline of a mask, so a mask shape whose
-- converted data has no outline (no `p`, no `ps`) is dropped and what it should have hidden is drawn in full:
-- noise over the whole radar, the bars of the "lost" signal as a plain yellow line, and so on.

-- Mask shapes made of SEVERAL contours (separate bars or rectangles): one outline cannot describe them, the
-- drawing code takes a single polygon per mask, so these are still drawn without their mask. Taking them off this
-- list is the job of whoever gives the drawing code several outlines per mask (a `ps` list in the converter).
local PENDING = {
	hud_grenadedetect = {[13] = true},
	hud_lost = {[40] = true, [41] = true},
	hud_reboot = {[15] = true}
}

local FILMS = {
	"hud_ammohealthenergysuit", "hud_binoculars", "hud_crosshair", "hud_friendlycross", "hud_grenadedetect",
	"hud_initialize", "hud_lost", "hud_quickmenu", "hud_radarcompassstealth", "hud_reboot"
}

-- The movie as its file holds it (GryMod.Flash.Load keeps the first copy it read, and the drawing code adds working data to it).
local function loadFresh(name)
	local ok, movie = pcall(include, "grymod/flash/" .. name .. ".lua")

	return ok and istable(movie) and movie or nil
end

-- Every placement that is a clip layer in the movie: {where = "root" or sprite id, frame, char}.
local function maskPlacements(movie)
	local found = {}

	local function scan(frames, where)
		for number, frame in ipairs(frames) do
			for _, op in ipairs(frame) do
				if op.cd and op.c then
					found[#found + 1] = {where = where, frame = number, char = op.c}
				end
			end
		end
	end

	scan(movie.root, "root")

	for id, definition in pairs(movie.chars) do
		if definition.k == "sprite" then
			scan(definition.frames, tostring(id))
		end
	end

	return found
end

-- Whether the drawing code finds an outline for the mask `char`: a shape or a morph with its polygon `p` (a morph at
-- both ends), or a clip whose first shape with an outline counts, as in cl_flash_draw.lua.
local function hasOutline(movie, char, depth)
	local definition = movie.chars[char]

	if not definition or (depth or 0) > 8 then
		return false
	end

	if definition.k == "sprite" then
		for _, frame in ipairs(definition.frames) do
			for _, op in ipairs(frame) do
				if op.c and not op.cd and hasOutline(movie, op.c, (depth or 0) + 1) then
					return true
				end
			end
		end

		return false
	end

	if definition.k == "morph" then
		return definition.p ~= nil and definition.pe ~= nil and #definition.p == #definition.pe
	end

	return definition.p ~= nil
end

local cases = {}

for _, name in ipairs(FILMS) do
	cases[#cases + 1] = {
		name = "every clip layer of " .. name .. " has an outline to cut along",
		func = function(state)
			local movie = loadFresh(name)
			expect(movie).toNot.beNil()
			local missing = {}

			for _, mask in ipairs(maskPlacements(movie)) do
				local pending = PENDING[name] and PENDING[name][mask.char]

				if pending then
					expect(hasOutline(movie, mask.char)).to.beFalse() -- it has one now: take it off PENDING
				elseif not hasOutline(movie, mask.char) then
					missing[#missing + 1] = string.format("char %d (%s, sprite %s frame %d)", mask.char,
						movie.chars[mask.char] and movie.chars[mask.char].k or "?", mask.where, mask.frame)
				end
			end

			expect(table.concat(missing, "; ")).to.equal("")
		end
	}
end

cases[#cases + 1] = {
	name = "a mask outline is a closed polygon of at least 3 points, a morph's two ends have the same number of points",
	func = function(state)
		for _, name in ipairs(FILMS) do
			local movie = loadFresh(name)

			for id, definition in pairs(movie.chars) do
				if definition.p then
					expect(#definition.p >= 6 and #definition.p % 2 == 0).to.beTrue()
				end

				if definition.k == "morph" and definition.p then
					expect(definition.pe).toNot.beNil()
					expect(#definition.pe).to.equal(#definition.p)
				end
			end
		end
	end
}

return {
	groupName = "GryMod Flash movies: clip layers (masks)",
	cases = cases
}
