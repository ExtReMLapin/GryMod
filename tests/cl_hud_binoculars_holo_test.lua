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
			-- fails without Holo.ItemStyle
			name = "a weapon's colour: white while aimed, blue when an ally holds it, nothing otherwise (a weapon on the ground is only drawn aimed)",
			func = function()
				local S = H().ItemStyle

				expect(S(nil, true)).to.equal("white")
				expect(S("ally", true)).to.equal("white")
				expect(S("ally", false)).to.equal("blue")
				expect(S("hostile", false)).to.beNil()
				expect(S("neutral", false)).to.beNil()
				expect(S(nil, false)).to.beNil()
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

				expect(kept[16].dist).to.equal(16)
			end
		},
		{
			-- fails without Holo.Pending
			name = "the questions to the server: what is unknown, what is older than 5 s, an unanswered one after a second; each index once, at most 16",
			func = function()
				local Holo = H()
				local cache = {
					[1] = {relation = "ally", answered = 100, asked = 99},
					[2] = {relation = "hostile", answered = 90, asked = 89},
					[3] = {asked = 99.5},
					[4] = {asked = 98}
				}

				local out = Holo.Pending({1, 2, 3, 4, 5, 5, 1}, cache, 100.2, 16)
				expect(out[1]).to.equal(2)
				expect(out[2]).to.equal(4)
				expect(out[3]).to.equal(5)
				expect(#out).to.equal(3)

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

				Holo.OnAnswer({{index = 11, relation = "ally"}, {index = 12, relation = "hostile"}}, 10.3)
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
			-- fails without Holo.ConeCos / Holo.BoxOf / Holo.DistanceText
			name = "the helpers: the cone is wider than the field of view, a box holds its points, a distance reads whole metres and an M",
			func = function()
				local Holo = H()

				expect(Holo.ConeCos(40) > Holo.ConeCos(80)).to.beTrue()
				expect(Holo.ConeCos(nil)).to.equal(Holo.ConeCos(75))
				expect(Holo.ConeCos(0 / 0)).to.equal(Holo.ConeCos(75))
				expect(Holo.ConeCos(170) > 0).to.beTrue()

				local l, t, r, b = Holo.BoxOf({10, 50, 30}, {5, 20, 90}, 3)
				expect(l).to.equal(10)
				expect(t).to.equal(5)
				expect(r).to.equal(50)
				expect(b).to.equal(90)

				expect(Holo.DistanceText(B().UNITS_PER_METRE * 118)).to.equal("118M")
				expect(Holo.DistanceText(B().UNITS_PER_METRE * 7.4)).to.equal("7M")
			end
		},
		{
			-- fails without Holo.Sync and the listener of GryMod_BinocularsToggled: the three hooks would be there all the time, or never
			name = "the hooks (fill, outline, marker) exist only while the binoculars are up with the hologram on; a toggle report adds and removes them",
			func = function()
				local Holo = H()
				local up = false

				B().Wanted = function() return up end
				B().Enabled = function() return true end

				local function hooked()
					local t = hook.GetTable()

					return t.PostDrawTranslucentRenderables and t.PostDrawTranslucentRenderables["GRYBINOCULARSHOLO"] ~= nil,
						t.PreDrawHalos and t.PreDrawHalos["GRYBINOCULARSHOLO"] ~= nil,
						t.HUDPaint and t.HUDPaint["GRYBINOCULARSHOLO"] ~= nil
				end

				withConVar("gry_binoculars_hologram", "1", function()
					withConVar("gry_binoculars_silhouette", "1", function()
						local listener = hook.GetTable().GryMod_BinocularsToggled["GRYBINOCULARSHOLO"]
						expect(listener).to.beA("function")

						Holo.Sync()
						local a, b, c = hooked()
						expect(a or b or c).to.beFalse()

						up = true
						listener(true)
						a, b, c = hooked()
						expect(a and b and c).to.beTrue()

						up = false
						listener(false)
						a, b, c = hooked()
						expect(a or b or c).to.beFalse()
					end)

					-- the hologram off: nothing is added even with the binoculars up
					withConVar("gry_binoculars_hologram", "0", function()
						up = true
						Holo.Sync()
						local a, b, c = hooked()
						expect(a or b or c).to.beFalse()
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
		}
	}
}
