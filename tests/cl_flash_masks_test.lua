-- Tests of the data of the converted movies (lua/grymod/flash/*.lua), GLuaTest format, client realm.
--
-- A clip layer (a placement with a clip depth, "cd") hides what is drawn above it outside its own shape. The
-- drawing code (cl_flash_draw.lua) can only cut a picture along the outline of a mask, so a mask shape whose
-- converted data has no outline (no `p`, no `ps`) is dropped and what it should have hidden is drawn in full:
-- noise over the whole radar, the bars of the "lost" signal as a plain yellow line, and so on.

local FILMS = {
	"hud_ammohealthenergysuit", "hud_binoculars", "hud_crosshair", "hud_friendlycross", "hud_grenadedetect",
	"hud_initialize", "hud_lost", "hud_quickmenu", "hud_radarcompassstealth", "hud_reboot", "hud_sp_hexicons"
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

-- Whether a list of outlines ({{x1, y1, ...}, ...}) is usable: at least one, each a closed polygon of 3 points or more.
local function validOutlines(outlines)
	if not istable(outlines) or #outlines == 0 then
		return false
	end

	for _, outline in ipairs(outlines) do
		if #outline < 6 or #outline % 2 ~= 0 then
			return false
		end
	end

	return true
end

-- The outlines of a shape or a morph as a list: `ps`, or the single `p` (and the same for the end of a morph).
local function outlinesOf(definition, single, several)
	if definition[several] then
		return definition[several]
	end

	return definition[single] and {definition[single]} or nil
end

-- Whether the drawing code finds an outline for the mask `char`: a shape or a morph with its polygon `p` or its
-- polygons `ps` (a morph at both ends, the same number of outlines of the same sizes), or a clip whose first shape
-- with an outline counts, as in cl_flash_draw.lua.
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

	local starts = outlinesOf(definition, "p", "ps")

	if definition.k == "morph" then
		local ends = outlinesOf(definition, "pe", "pes")

		if not validOutlines(starts) or not validOutlines(ends) or #starts ~= #ends then
			return false
		end

		for i = 1, #starts do
			if #starts[i] ~= #ends[i] then
				return false
			end
		end

		return true
	end

	return validOutlines(starts)
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
				if not hasOutline(movie, mask.char) then
					missing[#missing + 1] = string.format("char %d (%s, sprite %s frame %d)", mask.char,
						movie.chars[mask.char] and movie.chars[mask.char].k or "?", mask.where, mask.frame)
				end
			end

			expect(table.concat(missing, "; ")).to.equal("")
		end
	}
end

cases[#cases + 1] = {
	name = "a mask outline is a closed polygon of at least 3 points, a morph's two ends have the same number of outlines and points",
	func = function(state)
		for _, name in ipairs(FILMS) do
			local movie = loadFresh(name)

			for id, definition in pairs(movie.chars) do
				-- a shape has one outline (p) or several (ps), never both
				expect(definition.p ~= nil and definition.ps ~= nil).to.beFalse()
				expect(definition.pe ~= nil and definition.pes ~= nil).to.beFalse()

				local starts = outlinesOf(definition, "p", "ps")

				if starts then
					expect(validOutlines(starts)).to.beTrue()
				end

				if definition.k == "morph" and starts then
					local ends = outlinesOf(definition, "pe", "pes")
					expect(ends).toNot.beNil()
					expect(#ends).to.equal(#starts)

					for i = 1, #starts do
						expect(#ends[i]).to.equal(#starts[i])
					end
				end
			end
		end
	end
}

cases[#cases + 1] = {
	name = "the clip layers that are made of several contours have them all: the bars of the lost signal, the grenade warning, the reboot",
	func = function(state)
		local lost = loadFresh("hud_lost")
		expect(#lost.chars[41].ps).to.equal(20) -- the 20 horizontal bars
		expect(lost.chars[40].k).to.equal("morph")
		expect(#lost.chars[40].ps).to.equal(20)
		expect(#lost.chars[40].pes).to.equal(20)
		expect(#loadFresh("hud_grenadedetect").chars[13].ps).to.equal(2)
		expect(#loadFresh("hud_reboot").chars[15].ps).to.equal(2)
	end
}

return {
	groupName = "GryMod Flash movies: clip layers (masks)",
	cases = cases
}
