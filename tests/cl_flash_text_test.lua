-- Tests of the text fields of the Flash player (GryMod.Flash), GLuaTest format, client realm.

local function movie()
	return {
		w = 1024, h = 768, fps = 30, atlases = {"grymod/flash/none.png"},
		fonts = {
			[9] = {a = 1, em = 100, asc = 90, desc = 20, g = {
				[48] = {x = 0, y = 0, w = 40, h = 70, ox = 2, oy = -70, adv = 50},
				[49] = {x = 0, y = 0, w = 20, h = 70, ox = 2, oy = -70, adv = 30},
				[32] = {x = 0, y = 0, w = 0, h = 0, ox = 0, oy = 0, adv = 25}
			}}
		},
		chars = {
			-- a 100 x 30 pixel field, 20 px high text, centred
			[1] = {k = "text", ox = 0, oy = 0, w = 100, h = 30, fh = 20, t = "0", col = {255, 255, 255, 255}, al = 2, f = 9},
			[2] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Digit"}, {d = 2, c = 3, n = "Inner"}}}},
			[3] = {k = "sprite", n = 1, labels = {}, frames = {{{d = 1, c = 1, n = "Deep"}}}}
		},
		root = {{{d = 1, c = 2, n = "Box"}}}
	}
end

return {
	groupName = "GryMod Flash text",
	cases = {
		{
			name = "a replaced colour (multiplier 0) is drawn from the white twin of the atlas, the others from the atlas",
			func = function(state)
				local F = GryMod.Flash
				local movie = {atlases = {"grymod/flash/a_1.png", "grymod/flash/a_font.png"}, white = {[1] = true}}
				expect(F.AtlasPathFor(movie, 1, 0, 0, 0)).to.equal("grymod/flash/a_1_w.png")
				expect(F.AtlasPathFor(movie, 1, 1, 1, 1)).to.equal("grymod/flash/a_1.png")
				expect(F.AtlasPathFor(movie, 1, 0.5, 0, 0)).to.equal("grymod/flash/a_1.png")
				expect(F.AtlasPathFor(movie, 2, 0, 0, 0)).to.equal("grymod/flash/a_font.png") -- glyphs are white already
				expect(F.AtlasPathFor({atlases = {"x.png"}}, 1, 0, 0, 0)).to.equal("x.png") -- a movie without twins
			end
		},
		{
			name = "the atlases are textures without extension (VTF + VMT): the white twin is the same name plus _w",
			func = function(state)
				local F = GryMod.Flash
				local movie = {atlases = {"grymod/flash/a_1", "grymod/flash/hud_font"}, white = {[1] = true}}
				expect(F.AtlasPathFor(movie, 1, 0, 0, 0)).to.equal("grymod/flash/a_1_w")
				expect(F.AtlasPathFor(movie, 1, 1, 1, 1)).to.equal("grymod/flash/a_1")
				expect(F.AtlasPathFor(movie, 2, 0, 0, 0)).to.equal("grymod/flash/hud_font")
			end
		},
		{
			name = "the localisation keys of the movies (@ui_...) are English words, in every converted movie, never a raw key",
			func = function(state)
				local F = GryMod.Flash
				expect(F.Localise("@ui_MALFUNCTION")).to.equal("MALFUNCTION")
				expect(F.Localise("@ui_ZOOM")).to.equal("ZOOM")
				expect(F.Localise("@ui_NW")).to.equal("NW")
				expect(F.Localise("@ui_init_text01")).to.equal("Loading Control Unit ")
				expect(F.Localise("plain")).to.equal("plain")
				expect(F.Localise(nil)).to.equal(nil)
				-- a key nobody wrote the text of: readable, without the @ and the prefix
				expect(F.Localise("@ui_SOME_NEW_KEY")).to.equal("SOME NEW KEY")

				local movies = {"hud_ammohealthenergysuit", "hud_binoculars", "hud_radarcompassstealth", "hud_quickmenu",
					"hud_grenadedetect", "hud_crosshair", "hud_initialize", "hud_reboot", "hud_lost"}
				local bad = {}

				for _, name in ipairs(movies) do
					local movie = F.Load(name)
					expect(movie).to.exist()

					for id, definition in pairs(movie.chars) do
						if definition.k == "text" and isstring(definition.t) and string.find(F.Localise(definition.t), "@", 1, true) then
							bad[#bad + 1] = name .. "/" .. id .. " " .. definition.t
						end
					end
				end

				expect(table.concat(bad, ", ")).to.equal("")
			end
		},
		{
			name = "a text field made from a key starts with the English text, and SetText keeps what it is given",
			func = function(state)
				local m = movie()
				m.chars[1].t = "@ui_MALFUNCTION"
				local box = GryMod.Flash.NewRoot(m):Child("Box")
				expect(box:Child("Digit").text).to.equal("MALFUNCTION")
				box:SetText("Digit", "@raw")
				expect(box:Child("Digit").text).to.equal("@raw")
			end
		},
		{
			name = "a text field starts with its initial text",
			func = function(state)
				local root = GryMod.Flash.NewRoot(movie())
				expect(root:Child("Box"):Child("Digit").text).to.equal("0")
			end
		},
		{
			name = "SetText changes a named field and says whether it found it",
			func = function(state)
				local box = GryMod.Flash.NewRoot(movie()):Child("Box")
				expect(box:SetText("Digit", "1")).to.beTrue()
				expect(box:Child("Digit").text).to.equal("1")
				expect(box:SetText("Nothing", "1")).to.beFalse()
				expect(box:SetText("Inner", "1")).to.beFalse() -- a clip, not a field
			end
		},
		{
			name = "SetText accepts numbers and nil",
			func = function(state)
				local box = GryMod.Flash.NewRoot(movie()):Child("Box")
				box:SetText("Digit", 42)
				expect(box:Child("Digit").text).to.equal("42")
				box:SetText("Digit", nil)
				expect(box:Child("Digit").text).to.equal("")
			end
		},
		{
			name = "Find follows a dotted path of instance names",
			func = function(state)
				local root = GryMod.Flash.NewRoot(movie())
				expect(root:Find("Box.Inner.Deep")).to.exist()
				expect(root:Find("Box.Inner.Nothing")).to.beNil()
				expect(root:Find("Nothing.Inner")).to.beNil()
			end
		},
		{
			name = "text layout: centred, left and right alignment inside the 2 px margin",
			func = function(state)
				local m = movie()
				local font, field = m.fonts[9], m.chars[1]
				-- "00" = 2 * 50 / 100 * 20 = 20 px wide
				local x, baseline, width = GryMod.Flash.LayoutText(font, field, "00")
				expect(width).to.equal(20)
				expect(x).to.equal(40) -- (100 - 20) / 2
				expect(baseline).to.equal(2 + 90 * 20 / 100)
				field.al = 0
				expect(GryMod.Flash.LayoutText(font, field, "00")).to.equal(2)
				field.al = 1
				expect(GryMod.Flash.LayoutText(font, field, "00")).to.equal(100 - 2 - 20)
			end
		},
		{
			name = "text layout: unknown characters and the empty string do not break it",
			func = function(state)
				local m = movie()
				local x, baseline, width = GryMod.Flash.LayoutText(m.fonts[9], m.chars[1], "")
				expect(width).to.equal(0)
				local _, _, w2 = GryMod.Flash.LayoutText(m.fonts[9], m.chars[1], "0\xE9\n1")
				expect(w2).to.equal((50 + 30) * 20 / 100) -- unknown characters count for nothing
			end
		}
	}
}
