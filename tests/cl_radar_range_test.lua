-- Tests of the radar's range option on the client (gry_radar_range in cl_hud_radar_units.lua), GLuaTest format, client realm. The original's radar
-- has a radius of 75 m (a constant, or the level's mapRadius: the demo's levels give none) and no zoom; GryMod lets the player choose 5 to 100
-- metres, 75 by default, because at 75 m a vehicle's icon stands for about 14 m of ground. The radius changes where the icons are (the
-- pixels of the radar are the same, the metres they stand for change) and what the server looks for (the range goes with the request).

local OPTION = "gry_radar_range"

local function option()
	return GetConVar(OPTION)
end

local function contactAt(metres)
	return {id = 1, x = metres / GryMod.RadarShared.METRES_PER_UNIT, y = 0, z = 0, yaw = 0, type = 1, sub = 4, marker = false, big = false}
end

local real = {}

local function restoreNet()
	if real.Start then
		net.Start, net.WriteBool, net.WriteUInt, net.SendToServer = real.Start, real.WriteBool, real.WriteUInt, real.SendToServer
		real.Start = nil
	end
end

return {
	groupName = "GryMod radar range (client)",
	beforeEach = function(state)
		state.value = option() and option():GetString()

		-- the range tests are about the manual range: the automatic zoom (a setting of the player, archived) would take the slider's place
		local auto = GetConVar("gry_radar_autozoom")

		state.auto = auto and auto:GetString()

		if auto then
			auto:SetString("0")
		end
	end,
	afterEach = function(state)
		pcall(restoreNet)

		if state.auto and GetConVar("gry_radar_autozoom") then
			GetConVar("gry_radar_autozoom"):SetString(state.auto)
		end

		if state.value and option() then
			option():SetString(state.value)
		end

		local R = GryMod.FlashRadar

		if R and R.ResetWant then
			R.ResetWant()
		end
	end,
	cases = {
		{
			name = "the option exists: saved, 75 metres by default (the original's), from 5 to 100",
			func = function()
				local c = option()

				expect(c ~= nil).to.beTrue()
				expect(c:GetDefault()).to.equal("75")
				expect(c:GetMin()).to.equal(5)
				expect(c:GetMax()).to.equal(100)
			end
		},
		{
			name = "Range reads the option as whole metres between 5 and 100, whatever the text",
			func = function()
				local R = GryMod.FlashRadar

				option():SetString("40")
				expect(R.Range()).to.equal(40)
				option():SetString("40.6")
				expect(R.Range()).to.equal(41)
				option():SetString("5")
				expect(R.Range()).to.equal(5)
				option():SetString("5.4")
				expect(R.Range()).to.equal(5)
				option():SetString("20")
				expect(R.Range()).to.equal(20)
				-- under the minimum the engine's own clamping of the convar and ClampRange both hold at 5, never at the old 20
				option():SetString("2")
				expect(R.Range()).to.equal(5)
				option():SetString("900")
				expect(R.Range()).to.equal(100)
				-- text that is no number: the engine's own clamping of the convar (0 becomes its minimum), a usable value whatever it is
				option():SetString("abc")
				expect(R.Range() >= 5 and R.Range() <= 100).to.beTrue()
			end
		},
		{
			name = "Contacts: with a range the same distance is more or fewer pixels (20 m is 21.5 pixels of 43 at 40 m, 11.5 at 75 m), no range is the original's 75",
			func = function()
				local R = GryMod.FlashRadar
				local PX = 110 / 94
				local at75 = R.Contacts(Vector(0, 0, 0), 0, {contactAt(20)}, 0)[1]
				local at40 = R.Contacts(Vector(0, 0, 0), 0, {contactAt(20)}, 0, 40)[1]
				local atNil = R.Contacts(Vector(0, 0, 0), 0, {contactAt(20)}, 0, nil)[1]

				expect(math.abs((R.UNITS_CENTRE_Y - at75.y) - 20 / 75 * 43 * PX) < 0.01).to.beTrue()
				expect(math.abs((R.UNITS_CENTRE_Y - at40.y) - 20 / 40 * 43 * PX) < 0.01).to.beTrue()
				expect(math.abs(atNil.y - at75.y) < 0.0001).to.beTrue()
			end
		},
		{
			name = "a unit just outside the radar at the chosen range is dropped, and comes back with a bigger one",
			func = function()
				local R = GryMod.FlashRadar

				expect(R.Contacts(Vector(0, 0, 0), 0, {contactAt(60)}, 0, 40)[1]).to.beNil()
				expect(R.Contacts(Vector(0, 0, 0), 0, {contactAt(60)}, 0, 100)[1] ~= nil).to.beTrue()
			end
		},
		{
			name = "the request to the server carries the range (8 bits, metres) and is sent again when the range changes, not otherwise",
			func = function()
				local R = GryMod.FlashRadar
				expect(R.TellServer ~= nil and R.ResetWant ~= nil).to.beTrue()

				local sent = {}
				real.Start, real.WriteBool, real.WriteUInt, real.SendToServer = net.Start, net.WriteBool, net.WriteUInt, net.SendToServer

				local ok, err = pcall(function()
					net.Start = function(name) sent[#sent + 1] = {name = name} return true end
					net.WriteBool = function(v) sent[#sent].want = v end
					net.WriteUInt = function(v, bits) sent[#sent].range, sent[#sent].bits = v, bits end
					net.SendToServer = function() end

					R.ResetWant()
					option():SetString("40")
					R.TellServer(true)
					R.TellServer(true)
					option():SetString("60")
					R.TellServer(true)
					R.TellServer(false)
					R.TellServer(false)
				end)

				pcall(restoreNet)

				if not ok then error(err, 0) end

				expect(#sent).to.equal(3)
				expect(sent[1].name).to.equal("gry_radar_want")
				expect(sent[1].want).to.beTrue()
				expect(sent[1].range).to.equal(40)
				expect(sent[1].bits).to.equal(8)
				expect(sent[2].range).to.equal(60)
				expect(sent[3].want).to.beFalse()
			end
		},
		{
			name = "at 5 metres the contacts scale to the pixels (4 m ahead is 34.4 pixels, inside the glass) and the glass edge stays the limit: 6 m ahead (51.6 pixels, past the 46 ahead of the frame) is dropped",
			func = function()
				local R = GryMod.FlashRadar
				local PX = 110 / 94
				local near = R.Contacts(Vector(0, 0, 0), 0, {contactAt(4)}, 0, 5)[1]
				local far = R.Contacts(Vector(0, 0, 0), 0, {contactAt(6)}, 0, 5)[1]

				expect(near ~= nil).to.beTrue()
				expect(math.abs((R.UNITS_CENTRE_Y - near.y) - 4 / 5 * 43 * PX) < 0.01).to.beTrue()
				expect(near.x == near.x and near.y == near.y and near.scale == near.scale).to.beTrue()
				expect(far).to.beNil()
			end
		},
		{
			name = "the range told to the server is 5 metres when the option is at its minimum (not the old 20)",
			func = function()
				local R = GryMod.FlashRadar
				local sent = {}
				real.Start, real.WriteBool, real.WriteUInt, real.SendToServer = net.Start, net.WriteBool, net.WriteUInt, net.SendToServer

				local ok, err = pcall(function()
					net.Start = function(name) sent[#sent + 1] = {name = name} return true end
					net.WriteBool = function(v) sent[#sent].want = v end
					net.WriteUInt = function(v, bits) sent[#sent].range = v end
					net.SendToServer = function() end

					R.ResetWant()
					option():SetString("5")
					R.TellServer(true)
				end)

				pcall(restoreNet)

				if not ok then error(err, 0) end

				expect(#sent).to.equal(1)
				expect(sent[1].range).to.equal(5)
			end
		},
		{
			-- the slider lives in the Radar and map menu (next to the automatic definition, which follows it); the Config menu has none and only says where the radar options went
			name = "the Radar and map menu has ONE slider for the range, in the Minimap tab, with the recommended values in its label; the Config menu has none and points to the menu",
			func = function()
				local found, sliderMin, sliderMax, advice
				local count, position, minimapAt, sliderAt = 0, 0, nil, nil
				local panel = vgui.Create("ControlPanel")
				local config = vgui.Create("ControlPanel")
				local configSliders, configLine = 0, false
				local ok, err = pcall(function()
					GryMod.RadarOptionsPanel(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							position = position + 1

							if child.ClassName == "DNumSlider" and child.Scratch and child.Scratch.m_strConVar == OPTION then
								found = child:GetText()
								sliderMin, sliderMax = child:GetMin(), child:GetMax()
								count = count + 1
								sliderAt = position
							elseif child.ClassName == "ControlPanel" and child.GryTabRoot and child:GetParent().GetItems then
								-- the section is a tab of the page (cl_options_tabs.lua): its name is the tab's
								for _, item in ipairs(child:GetParent():GetItems()) do
									if item.Panel == child and item.Tab.GryName == "Minimap" then
										minimapAt = position
									end
								end
							elseif child.ClassName == "DLabel" and string.find(child:GetText(), "down to 5", 1, true) then
								-- the recommended values are the text under the slider (its label is short: a panel cuts a long one)
								advice = child:GetText()
							end

							walk(child)
						end
					end

					walk(panel)

					GryMod.GryOptionschute(config)

					local function walkConfig(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DNumSlider" and child.Scratch and child.Scratch.m_strConVar == OPTION then
								configSliders = configSliders + 1
							elseif child.ClassName == "DLabel" and child:GetText() == "Radar, compass and map options are in the Radar and map menu." then
								configLine = true
							end

							walkConfig(child)
						end
					end

					walkConfig(config)
				end)

				panel:Remove()
				config:Remove()

				if not ok then error(err, 0) end

				expect(count).to.equal(1)
				expect(minimapAt ~= nil and sliderAt ~= nil and sliderAt > minimapAt).to.beTrue()
				expect(configSliders).to.equal(0)
				expect(configLine).to.beTrue()
				expect(found ~= nil).to.beTrue()
				expect(string.find(found, "Radar range", 1, true)).to.equal(1)
				expect(advice ~= nil).to.beTrue()
				expect(string.find(advice, "40", 1, true) ~= nil).to.beTrue()
				expect(string.find(advice, "75", 1, true) ~= nil).to.beTrue()
				expect(sliderMin).to.equal(5)
				expect(sliderMax).to.equal(100)
			end
		}
	}
}
