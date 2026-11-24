-- Tests of the corner marks drawn from the original Scaleform movies HUD_Corner_Left and HUD_Corner_Right (GryMod.FlashCorners), GLuaTest format,
-- client realm. The rules are from the movies' ActionScript (destroy(1) plays the red state, destroy(2) the flicker, destroy(0) the normal one) and
-- from the audit of the movies: the original loads both marks with the HUD and nothing hides them.

local Corners
local drawn
local realDraw
local saved = {}

local function savedConVar(name)
	saved[#saved + 1] = {name, GetConVar(name):GetString()}
end

local function run(instance, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		instance:Update(1 / 30)
	end
end

-- Flash.Draw is a recorder: the movies of the clips that were drawn, in order.
local function recordDraws()
	realDraw = GryMod.Flash.Draw
	GryMod.Flash.Draw = function(root, x, y, scale)
		drawn[#drawn + 1] = {movie = root.movie, x = x, y = y, scale = scale}
	end
end

local function namesOf(list)
	local out = {}

	for i, d in ipairs(list) do
		out[i] = d.movie == GryMod.Flash.Load("hud_corner_left") and "left" or d.movie == GryMod.Flash.Load("hud_corner_right") and "right" or "other"
	end

	table.sort(out)

	return out
end

-- The death of the player, without killing the real one (see cl_hud_boot_flash_test.lua): LocalPlayer answers a stand-in that is dead while
-- `life.dead` is true and the real player otherwise.
local function withDeath(body)
	local HUD = GryMod.FlashHUD
	local real = LocalPlayer()

	if not IsValid(real) or not real:Alive() then
		return
	end

	local life = {dead = false}
	local stand = setmetatable({
		IsValid = function() return true end,
		Alive = function() return not life.dead end
	}, {__index = function(_, key)
		local value = real[key]

		if isfunction(value) then
			return function(_, ...) return value(real, ...) end
		end

		return value
	end})

	local realLocalPlayer = LocalPlayer
	-- the stand-in is a table, not an entity: the real IsSuitEnabled says "no" to it, and the paint would drop the HUD instead of showing the death
	local realEnabled = GryMod.API.IsSuitEnabled
	local ok, err = pcall(function()
		LocalPlayer = function() return life.dead and stand or real end
		GryMod.API.IsSuitEnabled = function(ply) return ply == stand or realEnabled(ply) end
		HUD.Reset()
		body(life, HUD)
	end)

	LocalPlayer = realLocalPlayer
	GryMod.API.IsSuitEnabled = realEnabled
	pcall(HUD.Reset)

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod HUD corner marks (Flash)",
	beforeAll = function(state)
		Corners = GryMod.FlashCorners
	end,
	beforeEach = function(state)
		drawn = {}
		saved = {}
		savedConVar("gry_hud_corners")
		savedConVar("gry_hud")
		savedConVar("gry_hud_lost_on_death")
		GetConVar("gry_hud"):SetString("1")
		Corners.Reset()
		Corners.SetStatus(0)
	end,
	afterEach = function(state)
		if realDraw then
			GryMod.Flash.Draw = realDraw
			realDraw = nil
		end

		for i = #saved, 1, -1 do
			pcall(function() GetConVar(saved[i][1]):SetString(saved[i][2]) end)
		end

		pcall(Corners.Reset)
		pcall(Corners.SetStatus, 0)
	end,
	cases = {
		{
			-- needs: the two converted movies and Corners.New
			name = "the two movies load and make a mark each, a missing movie or an unknown side makes none",
			func = function(state)
				local Flash = GryMod.Flash
				expect(Corners.New("left", Flash.Load(Corners.MOVIES.left))).toNot.beNil()
				expect(Corners.New("right", Flash.Load(Corners.MOVIES.right))).toNot.beNil()
				expect(Corners.New("left", nil)).to.beNil()
				expect(Corners.New("middle", Flash.Load(Corners.MOVIES.left))).to.beNil()
			end
		},
		{
			-- needs: Instance:Destroy porting destroy(): 1 malfunction (red), 2 flickering (off), 0 normal
			name = "the mark shows after its first frame; destroy(1) turns it red, destroy(2) puts it off, destroy(0) brings it back as it was",
			func = function(state)
				local mark = Corners.New("left", GryMod.Flash.Load(Corners.MOVIES.left))
				run(mark, 0.2)
				expect(mark.clip:CurrentFrame()).to.equal(2)
				local entry = mark.clip:EntryAt(1)
				expect(entry).toNot.beNil()
				-- (the colour of the HUD is put on it by the movie's colour script)
				local normal = entry.cx and entry.cx[5] or 0

				mark:Destroy(1)
				run(mark, 0.2)
				expect(mark.clip:CurrentFrame()).to.equal(4) -- the frame after the label "malfunction" (3), where the red mark is and the clip stops
				entry = mark.clip:EntryAt(1)
				expect(entry).toNot.beNil()
				-- the colour is replaced by red: multiplier 0, red added
				expect(entry.cx[1]).to.equal(0)
				expect(entry.cx[5]).to.equal(255)
				expect(entry.cx[6]).to.equal(0)
				expect(entry.cx[7]).to.equal(0)

				mark:Destroy(2)
				run(mark, 0.2)
				expect(mark.clip:CurrentLabel()).to.equal("flickering")
				expect(mark.clip:EntryAt(1)).to.beNil()

				mark:Destroy(0)
				run(mark, 0.2)
				expect(mark.clip:CurrentFrame()).to.equal(2)
				expect(mark.clip:EntryAt(1)).toNot.beNil()
				local back = mark.clip:EntryAt(1).cx
				expect(back == nil or back[5] ~= 255 or normal == 255).to.beTrue()
			end
		},
		{
			-- needs: Corners.Placement
			name = "the left mark's movie is against the left edge of the screen and the right mark's against the right edge, the stage as high as the screen",
			func = function(state)
				for _, size in ipairs({{1920, 1080}, {1280, 720}, {1024, 768}, {2560, 1080}}) do
					local w, h = size[1], size[2]
					local lx, ly, lscale = Corners.Placement("left", w, h)
					local rx, ry, rscale = Corners.Placement("right", w, h)
					expect(lx).to.equal(0)
					expect(ly).to.equal(0)
					expect(ry).to.equal(0)
					expect(lscale).to.equal(h / 768)
					expect(rscale).to.equal(h / 768)
					expect(math.abs(rx - (w - 1024 * h / 768)) < 1e-6).to.beTrue()
				end
			end
		},
		{
			-- needs: the HUD element "corners" with the default "1" (the owner asked for them on by default on 2026-11-24)
			name = "the corner marks are a HUD element that is on by default (gry_hud_corners), with a check box in the options; the other elements stay on by default",
			func = function(state)
				local convar = GetConVar("gry_hud_corners")
				expect(convar).toNot.beNil()
				-- (the definition is what a new game builds the convar from; a convar made earlier in the same game keeps its old default until it restarts)
				expect(GryMod.HUDOptions.Find("corners")).to.exist()
				expect(GryMod.HUDOptions.Find("corners").default).to.beNil() -- no default said: on, like every element
				convar:SetString("0")
				expect(Corners.Wanted()).to.beFalse()
				convar:SetString("1")
				expect(Corners.Wanted()).to.beTrue()
				expect(GetConVar("gry_hud_status"):GetDefault()).to.equal("1")

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

				expect(found["gry_hud_corners"]).to.beTrue()
			end
		},
		{
			-- needs: Options.MigrateCorners and its saved marker: the marks were OFF by default before, so every player has a saved 0 that is only the old default
			name = "a saved 0 of the corner marks (the old default) is put to 1 once, then the player's own choice is kept",
			func = function(state)
				local Options = GryMod.HUDOptions
				local marker = GetConVar("gry_hud_corners_default_on")
				expect(marker).toNot.beNil()
				local savedMarker = marker:GetString()

				local ok, err = pcall(function()
					marker:SetString("0")
					GetConVar("gry_hud_corners"):SetString("0")
					Options.MigrateCorners()
					expect(GetConVar("gry_hud_corners"):GetString()).to.equal("1")
					expect(marker:GetString()).to.equal("1")

					-- the player turns them off himself: the migration does not run again
					GetConVar("gry_hud_corners"):SetString("0")
					Options.MigrateCorners()
					expect(GetConVar("gry_hud_corners"):GetString()).to.equal("0")
				end)

				marker:SetString(savedMarker)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- needs: Corners.Paint drawing one clip per side when the setting is on, nothing (and nothing made) when it is off
			name = "a paint draws the two marks when the setting is on and nothing at all when it is off (and nothing stays made)",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_corners"):SetString("0")
				Corners.Paint(1 / 60)
				expect(#drawn).to.equal(0)

				GetConVar("gry_hud_corners"):SetString("1")
				Corners.Paint(1 / 60)
				local names = namesOf(drawn)
				expect(#names).to.equal(2)
				expect(names[1]).to.equal("left")
				expect(names[2]).to.equal("right")
				expect(drawn[1].y).to.equal(0)

				-- turned off again: nothing is drawn and the marks are given back
				drawn = {}
				GetConVar("gry_hud_corners"):SetString("0")
				Corners.Paint(1 / 60)
				expect(#drawn).to.equal(0)
				expect(Corners.Count()).to.equal(0)
			end
		},
		{
			-- needs: the hook GryMod_HUDStatus listened to (no polling), the status applied to marks made later
			name = "the HUD's report of its state (GryMod_HUDStatus) turns the marks red or off and back, including marks made after the report",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_corners"):SetString("1")
				Corners.Paint(1 / 30)
				local report = hook.GetTable()["GryMod_HUDStatus"]["GRYCORNERS"]
				expect(report).toNot.beNil()

				report(1)
				expect(Corners.Status()).to.equal(1)
				expect(Corners.Mark("left").status).to.equal(1)
				expect(Corners.Mark("right").status).to.equal(1)

				-- marks made while the HUD is down start red
				Corners.Reset()
				expect(Corners.Count()).to.equal(0)
				Corners.Paint(1 / 30)
				expect(Corners.Mark("left").status).to.equal(1)

				report(2)
				expect(Corners.Mark("left").status).to.equal(2)
				report(0)
				expect(Corners.Mark("right").status).to.equal(0)
				expect(Corners.Status()).to.equal(0)
			end
		},
		{
			-- needs: the HUD paint calling Corners.Paint, and Module.Reset giving the marks back
			name = "the HUD's paint draws the marks, and resetting the HUD gives them back",
			func = function(state)
				local HUD = GryMod.FlashHUD
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				recordDraws()
				GetConVar("gry_hud_corners"):SetString("1")
				HUD.Reset()
				HUD.Paint()
				local names = {}

				for _, name in ipairs(namesOf(drawn)) do
					if name ~= "other" then
						names[#names + 1] = name
					end
				end

				expect(#names).to.equal(2)
				expect(Corners.Count()).to.equal(2)
				HUD.Reset()
				expect(Corners.Count()).to.equal(0)
			end
		},
		{
			-- needs: the death handled in the paint: the marks go red with the HUD, stay while the death is shown, and are fresh after the respawn
			name = "at a death the marks go red with the HUD and stay drawn until the respawn, which puts them back to normal; with the death setting off they go with the HUD",
			func = function(state)
				recordDraws()
				GetConVar("gry_hud_corners"):SetString("1")

				withDeath(function(life, HUD)
					GetConVar("gry_hud_lost_on_death"):SetString("1")
					HUD.Paint()
					expect(Corners.Status()).to.equal(0)
					life.dead = true
					drawn = {}
					HUD.Paint()
					expect(Corners.Status()).to.equal(1)
					local cornersDrawn = 0

					for _, name in ipairs(namesOf(drawn)) do
						if name ~= "other" then cornersDrawn = cornersDrawn + 1 end
					end

					expect(cornersDrawn).to.equal(2)

					life.dead = false
					HUD.Paint()
					expect(Corners.Status()).to.equal(0)

					-- with the death setting off the HUD goes at the death and the marks with it
					GetConVar("gry_hud_lost_on_death"):SetString("0")
					HUD.Paint()
					life.dead = true
					drawn = {}
					HUD.Paint()
					expect(Corners.Count()).to.equal(0)
					cornersDrawn = 0

					for _, name in ipairs(namesOf(drawn)) do
						if name ~= "other" then cornersDrawn = cornersDrawn + 1 end
					end

					expect(cornersDrawn).to.equal(0)
				end)
			end
		}
	}
}
