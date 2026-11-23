-- Tests of the binoculars' hologram (lua/grymod/client/cl_hud_binoculars_holo.lua), GLuaTest format, client realm: the colours of what the binoculars spot
-- (green hostile, white while scanned, blue ally, the pulse), the white phase of the scan, the batch of questions to the server, and the hooks that exist only
-- while the binoculars are up. What is drawn (the material, the halo) needs the game's renderer and is looked at by hand.

local function H()
	return GryMod.BinocularsHolo
end

local function B()
	return GryMod.FlashBinoculars
end

local function withConVar(name, value, fn)
	local cvar = GetConVar(name)
	local saved = cvar:GetString()
	cvar:SetString(value)

	local ok, err = pcall(fn)
	cvar:SetString(saved)

	if not ok then
		error(err, 0)
	end
end

local realWanted, realEnabled, realSend

return {
	groupName = "GryMod binoculars hologram",
	beforeEach = function()
		realWanted, realEnabled, realSend = B().Wanted, B().Enabled, H().Send
	end,
	afterEach = function()
		pcall(function()
			B().Wanted, B().Enabled, H().Send = realWanted, realEnabled, realSend
			H().Detach()
			H().ForgetRelations()
		end)
	end,
	cases = {
		{
			-- fails without Holo.NpcStyle
			name = "an NPC's colour: a hostile is green (with the baseline, or once spotted), white while scanned; an ally or a neutral is only drawn by the pulse while scanned; an unknown side is white while scanned",
			func = function()
				local S = H().NpcStyle

				expect(S("hostile", "none", true)).to.equal("green")
				expect(S("hostile", "none", false)).to.beNil()
				expect(S("hostile", "white", false)).to.equal("white")
				expect(S("hostile", "white", true)).to.equal("white")
				expect(S("hostile", "spotted", false)).to.equal("green")

				-- the alert level of the hostile (the Remaster's own): 0 idle green, 1 alerted amber, 2 in combat dark red; the white scan wins over it
				expect(S("hostile", "none", true, 0)).to.equal("green")
				expect(S("hostile", "none", true, 1)).to.equal("amber")
				expect(S("hostile", "none", true, 2)).to.equal("red")
				expect(S("hostile", "spotted", false, 2)).to.equal("red")
				expect(S("hostile", "none", true, nil)).to.equal("green")
				expect(S("hostile", "none", true, 7)).to.equal("red")
				expect(S("hostile", "white", true, 2)).to.equal("white")
				expect(S("hostile", "none", false, 2)).to.beNil()
				expect(S("ally", "white", true, 2)).to.equal("pulse")

				for _, side in ipairs({"ally", "neutral"}) do
					expect(S(side, "none", true)).to.beNil()
					expect(S(side, "white", true)).to.equal("pulse")
					expect(S(side, "spotted", true)).to.beNil()
				end

				expect(S(nil, "white", true)).to.equal("white")
				expect(S(nil, "none", true)).to.beNil()
				expect(S(nil, "spotted", true)).to.beNil()
			end
		},
		{
			-- fails without the new Holo.ItemStyle(aimed, baseline): the blue weapons of the captures are weapons lying on the ground (owner's correction), white when aimed
			name = "a weapon on the ground is blue at baseline, white while aimed (aimed wins), nothing when the baseline is off and it is not aimed",
			func = function()
				local S = H().ItemStyle

				expect(S(false, true)).to.equal("blue")
				expect(S(true, true)).to.equal("white")
				expect(S(true, false)).to.equal("white")
				expect(S(false, false)).to.beNil()
			end
		},
		{
			-- fails without Holo.IsGroundItem: a weapon in a hand (an NPC's, a player's) was highlighted on its own (the owner saw an ally's weapon lit while he was not)
			name = "only an unowned weapon, not attached to a character, is an item: a carried weapon follows its holder",
			func = function()
				local G = H().IsGroundItem

				expect(G(false, false)).to.beTrue()
				expect(G(true, false)).to.beFalse()
				expect(G(false, true)).to.beFalse()
				expect(G(true, true)).to.beFalse()
			end
		},
		{
			-- fails without Holo.CarriedWeapon: the weapon of a highlighted hostile would not be part of its silhouette
			name = "the weapon a highlighted NPC holds is drawn with it (its silhouette), only while it exists and is a weapon",
			func = function()
				local W = H().CarriedWeapon
				local wep = {IsValid = function() return true end}
				local npc = {GetActiveWeapon = function() return wep end}

				expect(W(npc)).to.equal(wep)
				expect(W({GetActiveWeapon = function() return nil end})).to.beNil()
				expect(W({GetActiveWeapon = function() return {IsValid = function() return false end} end})).to.beNil()
				expect(W({})).to.beNil()
				expect(W(nil)).to.beNil()
			end
		},
		{
			-- fails without Holo.PhaseOf
			name = "the phase: white for the entity being scanned, spotted for one the binoculars found, none for the others",
			func = function()
				local a, b = {}, {}

				expect(H().PhaseOf(a, a, false)).to.equal("white")
				expect(H().PhaseOf(a, a, true)).to.equal("white")
				expect(H().PhaseOf(a, b, true)).to.equal("spotted")
				expect(H().PhaseOf(a, b, false)).to.equal("none")
				expect(H().PhaseOf(a, nil, false)).to.equal("none")
			end
		},
		{
			-- fails without Holo.WHITE_SECONDS taken from the scan's silhouette time, or if the phase were outside what the owner saw (0.2 to 0.5 s)
			name = "the white phase lasts 0.3 s, between the 0.2 and 0.5 s of the original, and is the end of the scan: not before, ends in the spotted state",
			func = function()
				local Bino, Holo = B(), H()

				expect(Holo.WHITE_SECONDS).to.equal(Bino.SILHOUETTE_SECONDS)
				expect(Holo.WHITE_SECONDS >= 0.2 and Holo.WHITE_SECONDS <= 0.5).to.beTrue()

				local st = Bino.NewScan()
				local target = {}
				local tagged = false
				local phases = {}
				local whiteTime, firstWhite, lastWhite = 0, nil, nil
				local clock = 0

				for _ = 1, 40 do
					local done = Bino.ScanStep(st, target, 0.05, function() return true end)

					if done then
						tagged = true
					end

					clock = clock + 0.05

					local white = Bino.SilhouetteTarget(st, function() return true end)
					local phase = Holo.PhaseOf(target, white, tagged)

					phases[#phases + 1] = phase

					if phase == "white" then
						whiteTime = whiteTime + 0.05
						firstWhite = firstWhite or clock
						lastWhite = clock
					end
				end

				expect(phases[1]).to.equal("none")
				expect(phases[#phases]).to.equal("spotted")
				-- never spotted before the white phase is over, never white after being spotted
				local seenSpotted = false

				for _, phase in ipairs(phases) do
					if phase == "spotted" then
						seenSpotted = true
					end

					expect(seenSpotted and phase == "white").to.beFalse()
				end

				expect(whiteTime).to.aboutEqual(0.3, 0.06)
			end
		},
		{
			-- fails without Holo.PulseProgress and Holo.Rgb
			name = "the pulse goes from white to blue over the white phase, and the colours are the green, white and blue of the hologram",
			func = function()
				local Holo = H()

				expect(Holo.PulseProgress(Holo.WHITE_SECONDS)).to.equal(0)
				expect(Holo.PulseProgress(Holo.WHITE_SECONDS / 2)).to.aboutEqual(0.5, 1e-6)
				expect(Holo.PulseProgress(0)).to.equal(1)
				expect(Holo.PulseProgress(5)).to.equal(0)
				expect(Holo.PulseProgress(-1)).to.equal(1)

				local r0, g0, b0 = Holo.Rgb("pulse", 0)
				local r1, g1, b1 = Holo.Rgb("pulse", 1)
				local w, bl = Holo.Colours.white, Holo.Colours.blue
				expect(r0).to.equal(w[1])
				expect(g0).to.equal(w[2])
				expect(b0).to.equal(w[3])
				expect(r1).to.equal(bl[1])
				expect(g1).to.equal(bl[2])
				expect(b1).to.equal(bl[3])

				local rg, gg, bg = Holo.Rgb("green")
				expect(gg > rg and gg > bg).to.beTrue()

				-- the Remaster's colours of a hostile by alert level (read in its program): #44633E, (220,178,121), (127,49,45)
				local function same(name, r, g, b)
					local rr, gg2, bb = Holo.Rgb(name)

					expect(rr).to.equal(r)
					expect(gg2).to.equal(g)
					expect(bb).to.equal(b)
				end

				same("green", 68, 99, 62)
				same("amber", 220, 178, 121)
				same("red", 127, 49, 45)
				local rb, gb, bb = Holo.Rgb("blue")
				expect(bb > rb and bb > gb).to.beTrue()
			end
		},
		{
			-- fails without Holo.Nearest: more than 16 would be drawn, and not the nearest
			name = "at most 16 entities are kept, the nearest ones, in order",
			func = function()
				local list = {}

				for i = 1, 30 do
					list[i] = {dist = (i * 7) % 31 + 1, n = i}
				end

				local kept = H().Nearest(list, H().MAX)
				expect(H().MAX).to.equal(16)
				expect(#kept).to.equal(16)

				for i = 2, #kept do
					expect(kept[i - 1].dist <= kept[i].dist).to.beTrue()
				end

				-- (the list holds 2 to 31, each once: the 16th is 17)
				expect(kept[16].dist).to.equal(17)
			end
		},
		{
			-- fails without Holo.Pending
			name = "the questions to the server: what is unknown, what is older than 1 s (the alert level changes fast), an unanswered one after a second; each index once, at most 16",
			func = function()
				local Holo = H()
				local cache = {
					[1] = {relation = "ally", answered = 100, asked = 99},
					[2] = {relation = "hostile", answered = 90, asked = 89},
					[3] = {asked = 99.5},
					[4] = {asked = 98},
					[6] = {relation = "hostile", answered = 98.5, asked = 98}
				}

				local out = Holo.Pending({1, 2, 3, 4, 5, 5, 1, 6}, cache, 100.2, 16)
				expect(out[1]).to.equal(2)
				expect(out[2]).to.equal(4)
				expect(out[3]).to.equal(5)
				expect(out[4]).to.equal(6)
				expect(#out).to.equal(4)

				local many = {}

				for i = 1, 40 do
					many[i] = i + 100
				end

				expect(#Holo.Pending(many, {}, 0, 16)).to.equal(16)
			end
		},
		{
			-- fails without Holo.Ask / Holo.OnAnswer: the server would be asked at every look, or its answer never kept
			name = "asking: the missing sides go in one question, a second question waits 0.4 s, an answer is kept and read by index and by entity",
			func = function()
				local Holo = H()
				local sent = {}
				Holo.Send = function(indices) sent[#sent + 1] = indices end
				Holo.ForgetRelations()

				expect(Holo.Ask({11, 12}, 10)).to.beTrue()
				expect(#sent).to.equal(1)
				expect(#sent[1]).to.equal(2)
				expect(Holo.Ask({13}, 10.2)).to.beFalse()
				expect(#sent).to.equal(1)

				Holo.OnAnswer({{index = 11, relation = "ally", level = 0}, {index = 12, relation = "hostile", level = 2}}, 10.3)
				expect(Holo.LevelOfIndex(12)).to.equal(2)
				expect(Holo.LevelOfIndex(11)).to.equal(0)
				expect(Holo.LevelOfIndex(13)).to.equal(0)
				expect(Holo.RelationOfIndex(11)).to.equal("ally")
				expect(Holo.RelationOfIndex(12)).to.equal("hostile")
				expect(Holo.RelationOfIndex(13)).to.beNil()

				-- what is answered is not asked again at once
				expect(Holo.Ask({11, 12}, 11)).to.beFalse()
				expect(Holo.Ask({11, 13}, 11)).to.beTrue()
				expect(sent[2][1]).to.equal(13)
				expect(#sent[2]).to.equal(1)
			end
		},
		{
			-- fails without Holo.ConeCos
			name = "the helpers: the cone is wider than the field of view",
			func = function()
				local Holo = H()

				expect(Holo.ConeCos(40) > Holo.ConeCos(80)).to.beTrue()
				expect(Holo.ConeCos(nil)).to.equal(Holo.ConeCos(75))
				expect(Holo.ConeCos(0 / 0)).to.equal(Holo.ConeCos(75))
				expect(Holo.ConeCos(170) > 0).to.beTrue()
			end
		},
		{
			-- fails while the yellow name + distance marker of an aimed ally is still there (owner's correction: the capture's "Jester 118M" box is the OBJECTIVE marker's own
			-- description box, not an ally label; an aimed ally gets only the one white-to-blue pulse and nothing stays)
			name = "no label marker for an aimed ally: the bracket / name / distance helpers and the colour are gone",
			func = function()
				local Holo = H()

				for _, name in ipairs({"ScreenBox", "NameOf", "DistanceText", "BoxOf", "PaintMarker", "MARK_COLOUR"}) do
					expect(Holo[name]).to.beNil()
				end

				-- the HUD hook that builds the materials stays
				expect(isfunction(Holo.PrepareHud)).to.beTrue()
			end
		},
		{
			-- fails without Holo.Sync and the listener of GryMod_BinocularsToggled: the three hooks would be there all the time, or never
			-- (the fourth hook, RenderScreenspaceEffects, is the compose of the Crysis style: it fails without it)
			name = "the hooks (fill, outline, marker, compose) exist only while the binoculars are up with the hologram on; a toggle report adds and removes them",
			func = function()
				local Holo = H()
				local up = false

				B().Wanted = function() return up end
				B().Enabled = function() return true end

				local function hooked()
					local t = hook.GetTable()

					return t.PostDrawTranslucentRenderables and t.PostDrawTranslucentRenderables["GRYBINOCULARSHOLO"] ~= nil,
						t.PreDrawHalos and t.PreDrawHalos["GRYBINOCULARSHOLO"] ~= nil,
						t.HUDPaint and t.HUDPaint["GRYBINOCULARSHOLO"] ~= nil,
						t.RenderScreenspaceEffects and t.RenderScreenspaceEffects["GRYBINOCULARSHOLO"] ~= nil
				end

				withConVar("gry_binoculars_hologram", "1", function()
					withConVar("gry_binoculars_silhouette", "1", function()
						local listener = hook.GetTable().GryMod_BinocularsToggled["GRYBINOCULARSHOLO"]
						expect(listener).to.beA("function")

						Holo.Sync()
						local a, b, c, d = hooked()
						expect(a or b or c or d).to.beFalse()

						up = true
						listener(true)
						a, b, c, d = hooked()
						expect(a and b and c and d).to.beTrue()

						up = false
						listener(false)
						a, b, c, d = hooked()
						expect(a or b or c or d).to.beFalse()
					end)

					-- the hologram off: nothing is added even with the binoculars up
					withConVar("gry_binoculars_hologram", "0", function()
						up = true
						Holo.Sync()
						local a, b, c, d = hooked()
						expect(a or b or c or d).to.beFalse()
					end)
				end)

				Holo.Detach()
			end
		},
		{
			name = "the two switches are saved, on by default, and have a check box each in the Binoculars options; the old halo stays quiet while the hologram is on",
			func = function()
				local expected = {gry_binoculars_hologram = "1", gry_binoculars_baseline = "1"}

				for name, default in pairs(expected) do
					local cvar = GetConVar(name)
					expect(cvar ~= nil).to.beTrue()
					expect(cvar:GetDefault()).to.equal(default)
					expect(cvar:GetFlags()).to.equal(GetConVar("gry_binoculars_sway"):GetFlags())
				end

				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.BinocularsOptions(panel)

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

				for name in pairs(expected) do
					expect(found[name]).to.beTrue()
				end

				-- the halo hook of the earlier version gives way to the hologram
				local Bino = B()
				local adds = 0
				local realAdd, realDraw = halo.Add, Bino.DrawSilhouette
				Bino.DrawSilhouette = function() adds = adds + 1 end

				local run = hook.GetTable().PreDrawHalos["GRYBINOCULARSSILHOUETTE"]
				local ok2, err2 = pcall(function()
					withConVar("gry_binoculars_hologram", "1", function()
						withConVar("gry_binoculars_silhouette", "1", function() run() end)
					end)

					expect(adds).to.equal(0)

					withConVar("gry_binoculars_hologram", "0", function() run() end)
					expect(adds).to.equal(1)
				end)

				halo.Add, Bino.DrawSilhouette = realAdd, realDraw

				if not ok2 then
					error(err2, 0)
				end
			end
		},
		{
			-- fails without Bino.IsTagged and Bino.IsItem
			name = "the binoculars tell the hologram what they spotted and what is a weapon on the ground",
			func = function()
				local Bino = B()

				expect(Bino.IsTagged(nil)).to.beFalse()
				expect(Bino.IsTagged({})).to.beFalse()
				expect(Bino.IsItem(nil)).to.beFalse()
			end
		},
		{
			-- fails without Holo.StyleName and Holo.ModeFor
			name = "the style: crysis unless the player wrote simple; crysis needs the shader (pending until the probe ran, simple when the game cannot run it)",
			func = function()
				local Holo = H()

				expect(Holo.StyleName("simple")).to.equal("simple")
				expect(Holo.StyleName(" Simple ")).to.equal("simple")
				expect(Holo.StyleName("crysis")).to.equal("crysis")
				expect(Holo.StyleName("CRYSIS")).to.equal("crysis")
				expect(Holo.StyleName("nonsense")).to.equal("crysis")
				expect(Holo.StyleName("")).to.equal("crysis")
				expect(Holo.StyleName(nil)).to.equal("crysis")

				expect(Holo.ModeFor("crysis", true)).to.equal("crysis")
				expect(Holo.ModeFor("crysis", false)).to.equal("simple")
				expect(Holo.ModeFor("crysis", nil)).to.equal("pending")
				expect(Holo.ModeFor("simple", true)).to.equal("simple")
				expect(Holo.ModeFor("simple", nil)).to.equal("simple")
				expect(Holo.ModeFor("simple", false)).to.equal("simple")
			end
		},
		{
			-- fails without the gry_binoculars_holo_style convar
			name = "the style switch is a saved client convar, crysis by default, with a choice in the Binoculars options",
			func = function()
				local cvar = GetConVar("gry_binoculars_holo_style")

				expect(cvar ~= nil).to.beTrue()
				expect(cvar:GetDefault()).to.equal("crysis")
				expect(cvar:GetFlags()).to.equal(GetConVar("gry_binoculars_sway"):GetFlags())
			end
		},
		{
			-- fails without Holo.DrawScene: the hook would always draw one style
			name = "the scene hook draws the style that is chosen: the older fill for simple, the vision buffer for crysis, nothing while the probe is pending",
			func = function()
				local Holo, V = H(), H().Crysis
				local realFill, realVision, realWorks = Holo.DrawFill, V.DrawVision, V.works
				local called = {}

				Holo.DrawFill = function() called[#called + 1] = "fill" end
				V.DrawVision = function() called[#called + 1] = "vision" end

				local ok, err = pcall(function()
					withConVar("gry_binoculars_holo_style", "simple", function()
						V.works = true
						Holo.DrawScene(false, false)
					end)

					withConVar("gry_binoculars_holo_style", "crysis", function()
						V.works = true
						Holo.DrawScene(false, false)
						V.works = false
						Holo.DrawScene(false, false)
						V.works = nil
						Holo.DrawScene(false, false)
					end)
				end)

				Holo.DrawFill, V.DrawVision, V.works = realFill, realVision, realWorks

				if not ok then
					error(err, 0)
				end

				expect(table.concat(called, ",")).to.equal("fill,vision,fill")
			end
		},
		{
			-- fails without V.Registers and V.TapPixels: the shader would get wrong numbers
			name = "the shader's registers: the strength, boost, fill and tap distance, one pixel, the mode, the glow gain, the screen height and the scan lines",
			func = function()
				local V = H().Crysis
				local r = V.Registers(1, 1920, 1080)

				expect(r[1][1]).to.equal(V.STRENGTH)
				expect(r[1][2]).to.equal(V.BOOST)
				expect(r[1][3]).to.equal(V.FILL)
				expect(r[1][4]).to.equal(V.TapPixels(1080))
				expect(math.abs(r[2][1] - 1 / 1920) < 1e-9).to.beTrue()
				expect(math.abs(r[2][2] - 1 / 1080) < 1e-9).to.beTrue()
				expect(r[2][3]).to.equal(1)
				expect(r[2][4]).to.equal(V.GLOW_GAIN)
				expect(r[3][1]).to.equal(1080)
				expect(r[3][2]).to.equal(V.SCAN_PERIOD)
				expect(r[3][3]).to.equal(V.SCAN_HI)
				expect(r[3][4]).to.equal(V.SCAN_LO)
				expect(r[4][1]).to.equal(V.VIGNETTE)

				-- the glow's own draw (mode 0): same numbers, only the mode differs; the table given is filled again, not replaced
				local again = V.Registers(0, 1920, 1080, r)
				expect(again == r).to.beTrue()
				expect(r[2][3]).to.equal(0)

				-- the original's scan lines: one bright row and one dim row, 1.2 and 0.8, counted in screen pixels
				expect(V.SCAN_PERIOD).to.equal(2)
				expect(V.SCAN_HI).to.equal(1.2)
				expect(V.SCAN_LO).to.equal(0.8)
			end
		},
		{
			-- fails without V.TapPixels / V.GlowSize
			name = "the outline's width follows the screen's height (never under one pixel), and the glow buffer is a fraction of the screen",
			func = function()
				local V = H().Crysis

				expect(V.TapPixels(1080)).to.equal(V.TAP_1080)
				expect(V.TapPixels(2160)).to.equal(V.TAP_1080 * 2)
				expect(V.TapPixels(100)).to.equal(1)
				expect(V.TapPixels(0)).to.equal(1)
				expect(V.TapPixels(nil)).to.equal(1)

				local w, h = V.GlowSize(1920, 1080)
				expect(w).to.equal(math.floor(1920 / V.GLOW_DIV))
				expect(h).to.equal(math.floor(1080 / V.GLOW_DIV))

				w, h = V.GlowSize(2, 2)
				expect(w >= 1 and h >= 1).to.beTrue()
			end
		},
		{
			-- fails without V.NeedsTraceOcclusion: with antialiasing the vision buffer has no scene depth, a soldier behind a wall would be drawn
			name = "with antialiasing the render target has no scene depth, so a wall is looked for by a trace instead",
			func = function()
				local V = H().Crysis

				expect(V.NeedsTraceOcclusion(0)).to.beFalse()
				expect(V.NeedsTraceOcclusion(1)).to.beFalse()
				expect(V.NeedsTraceOcclusion(2)).to.beTrue()
				expect(V.NeedsTraceOcclusion(8)).to.beTrue()
				expect(V.NeedsTraceOcclusion(nil)).to.beFalse()
			end
		},
		{
			-- fails without the Push / Pop round render.BlurRenderTarget in the glow pass: the engine leaves the blurred target as the current one, so the final quad (and
			-- every draw after it) went into the glow's buffer and nothing showed on the screen (seen in the game: the same quad drew when no blur had run before it)
			name = "the glow's blur is wrapped in a Push / Pop of the render target (also when it fails), and the final quad is drawn on the screen's target",
			func = function()
				local V = H().Crysis
				local names = {"PushRenderTarget", "PopRenderTarget", "Clear", "SetMaterial", "DrawScreenQuad", "BlurRenderTarget"}
				local saved = {}
				local savedFields = {glow = V.glow, rawMaterial = V.rawMaterial, finalMaterial = V.finalMaterial, rawRegisters = V.rawRegisters, finalRegisters = V.finalRegisters}
				local savedFrame = V.visionFrame
				local realErrorNoHalt = ErrorNoHalt

				for _, name in ipairs(names) do
					saved[name] = render[name]
				end

				local ok, err = pcall(function()
					local material = {SetFloat = function() end}
					local depth, quads, blurDepth, finalDepth = 0, 0, nil, nil
					local failBlur = false

					V.glow, V.rawMaterial, V.finalMaterial = {}, material, material
					V.rawRegisters, V.finalRegisters = V.Registers(0, 100, 100), V.Registers(1, 100, 100)

					render.PushRenderTarget = function() depth = depth + 1 end
					render.PopRenderTarget = function() depth = depth - 1 end
					render.Clear = function() end
					render.SetMaterial = function() end

					render.DrawScreenQuad = function()
						quads = quads + 1

						if quads == 2 then
							finalDepth = depth
						end
					end

					render.BlurRenderTarget = function()
						blurDepth = depth

						if failBlur then
							error("blur failed", 0)
						end
					end

					local function run()
						depth, quads, blurDepth, finalDepth = 0, 0, nil, nil
						V.visionFrame = FrameNumber()
						V.Compose()
					end

					run()
					expect(blurDepth ~= nil and blurDepth >= 1).to.beTrue()
					expect(finalDepth).to.equal(0)
					expect(depth).to.equal(0)

					-- a failing blur: the target is still given back (nothing is drawn, the error is reported)
					failBlur = true
					ErrorNoHalt = function() end
					run()
					expect(depth).to.equal(0)
				end)

				ErrorNoHalt = realErrorNoHalt

				for _, name in ipairs(names) do
					render[name] = saved[name]
				end

				V.glow, V.rawMaterial, V.finalMaterial = savedFields.glow, savedFields.rawMaterial, savedFields.finalMaterial
				V.rawRegisters, V.finalRegisters = savedFields.rawRegisters, savedFields.finalRegisters
				V.visionFrame = savedFrame

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails without V.Fit: a bright colour (amber, white, blue) times the boundary's boost passes 255 and every hue turns white (seen in the game: the alerted hostile came out white)
			name = "a colour is scaled down so that its boundary at the brightest scan row stays under FIT_PEAK (the hue is kept), and a dark one is left as it is",
			func = function()
				local V = H().Crysis
				local Holo = H()
				local peak = (V.FILL + V.BOOST) * V.SCAN_HI * V.STRENGTH

				expect(V.Fit(68, 99, 62)).to.equal(1)
				expect(V.Fit(127, 49, 45)).to.equal(1)
				expect(V.Fit(0, 0, 0)).to.equal(1)

				for _, name in ipairs({"amber", "white", "blue"}) do
					local r, g, b = Holo.Rgb(name)
					local k = V.Fit(r, g, b)

					expect(k < 1 and k > 0).to.beTrue()
					expect(math.max(r, g, b) * k * peak).to.aboutEqual(V.FIT_PEAK, 0.01)
				end
			end
		}
	}
}
