-- Tests of the effects test window (GryMod.DebugWindow, cl_debug_window.lua), GLuaTest format, client realm. ONE window (a DFrame popup, hidden when
-- closed, never two). Nothing in it names an effect or a command: the grid of the effects is a loop over GryMod.API.ListHUDEvents and
-- GetHUDEventInfo (one button per variant, or one for an event with none), and the real section is a loop over the list the server sent
-- (gry_debug_list), grey for a player who is not an admin. The cases use INVENTED events and commands. What is stubbed (the registry of the events,
-- HUDEvent, the way the window takes the mouse, the way a command or the list is asked for, the admin status) is put back after each case, in a
-- pcall, whatever happens: nothing here touches the real player, his net functions or his state (one real convar, gry_screenfx, is read and put
-- back inside a pcall).

local DW = function() return GryMod.DebugWindow end

local saved
local played, sent, asked
local realList

-- the invented registry: an event with three variants and a tooltip source, one with nothing
local ALPHA = {
	label = "Alpha effect",
	variants = {
		{label = "alpha one", data = {power = 1}},
		{label = "alpha two", data = {power = 2}},
		{label = "alpha three", data = {power = 3, tag = "x"}}
	},
	follows = {{"gry_screenfx", "the screen effects of the test"}}
}

local function infoOf(table_)
	return function(name) return table_[name] end
end

local function stubAll(events, infos)
	GryMod.API.ListHUDEvents = function() return events end
	GryMod.API.GetHUDEventInfo = infoOf(infos or {})
	GryMod.API.HUDEvent = function(name, data)
		played[#played + 1] = {name = name, data = data}

		return true
	end
	DW().MakePopup = function() end -- the window must not take the mouse of the player who is running the tests
	DW().SendCommand = function(id) sent[#sent + 1] = id end
	DW().RequestList = function() asked = asked + 1 end
end

local function asAdmin(isAdmin, fn)
	local meta = FindMetaTable("Player")
	local real = meta.IsAdmin
	meta.IsAdmin = function() return isAdmin end
	local ok, err = pcall(fn)
	meta.IsAdmin = real

	if not ok then
		error(err, 0)
	end
end

local function build(events, infos, isAdmin, commands)
	stubAll(events, infos)
	local frame

	asAdmin(isAdmin ~= false, function()
		DW().SetRealList(commands or {})
		DW().Open()
		frame = DW().Frame
	end)

	return frame
end

local function buttonsOf(layout)
	local list = {}

	for _, child in ipairs(layout:GetChildren()) do
		-- a panel that was removed leaves the list at the end of the frame, not at once
		if child.ClassName == "DButton" and not child:IsMarkedForDeletion() then
			list[#list + 1] = child
		end
	end

	return list
end

local function find(frame, label)
	for _, button in ipairs(frame.GryEventButtons or {}) do
		if button:GetText() == label then
			return button
		end
	end
end

local CMDS = {{id = "zz_one", label = "Do one"}, {id = "zz_two", label = "Do two"}}

return {
	groupName = "GryMod effects test window (client)",
	beforeAll = function()
		saved = {
			list = GryMod.API.ListHUDEvents,
			info = GryMod.API.GetHUDEventInfo,
			event = GryMod.API.HUDEvent,
			popup = GryMod.DebugWindow and GryMod.DebugWindow.MakePopup,
			send = GryMod.DebugWindow and GryMod.DebugWindow.SendCommand,
			request = GryMod.DebugWindow and GryMod.DebugWindow.RequestList
		}

		realList = GryMod.DebugWindow and GryMod.DebugWindow.RealList
	end,
	beforeEach = function()
		played, sent, asked = {}, {}, 0
	end,
	afterEach = function()
		if GryMod.DebugWindow and GryMod.DebugWindow.Destroy then
			pcall(GryMod.DebugWindow.Destroy)
		end

		GryMod.API.ListHUDEvents = saved.list
		GryMod.API.GetHUDEventInfo = saved.info
		GryMod.API.HUDEvent = saved.event

		if GryMod.DebugWindow then
			GryMod.DebugWindow.MakePopup = saved.popup
			GryMod.DebugWindow.SendCommand = saved.send
			GryMod.DebugWindow.RequestList = saved.request
			GryMod.DebugWindow.RealList = realList
		end
	end,
	cases = {
		{
			-- would fail if: the module did not exist (the button of the options panel would call nothing)
			name = "the module exists with Open, and the ways out are fields",
			func = function()
				expect(GryMod.DebugWindow).to.beA("table")
				expect(DW().Open).to.beA("function")
				expect(DW().SendCommand).to.beA("function")
				expect(DW().RequestList).to.beA("function")
				expect(DW().MakePopup).to.beA("function")
				expect(net.Receivers["gry_debug_list"]).to.beA("function")
			end
		},
		{
			-- would fail if: a name of an effect or a command came back in the file as a literal (a hard-coded list instead of a loop)
			name = "the file names no effect and no command: they are all read from the registries",
			func = function()
				local source = file.Read("grymod/client/cl_debug_window.lua", "LUA")
				expect(source).to.beA("string")

				for _, name in ipairs({"boot", "lost", "reboot", "malfunction", "jam", "armor_hit", "decloak", "low_health", "mode", "energy_critical",
					"regen_start", "regen_stop", "dive_in", "dive_out", "drown", "reset", "disabled", "enabled", "suit_off", "suit_on", "emp_self",
					"energy_empty", "energy_full", "mode_armor", "mode_speed", "mode_strength", "mode_cloak"}) do
					expect(string.find(source, '"' .. name .. '"', 1, true)).to.beNil()
				end
			end
		},
		{
			-- would fail if: Open built a new frame at each call (a window per click, panels that leak)
			name = "two Open make ONE window: the same panel, shown, a DFrame, one in the whole screen",
			func = function()
				local first = build({"zz_alpha"}, {zz_alpha = ALPHA})
				expect(IsValid(first)).to.beTrue()
				expect(first.ClassName).to.equal("DFrame")
				expect(first:IsVisible()).to.beTrue()

				DW().Open()
				expect(DW().Frame).to.equal(first)

				local count = 0

				for _, child in ipairs(vgui.GetWorldPanel():GetChildren()) do
					if child.GryDebugWindow then
						count = count + 1
					end
				end

				expect(count).to.equal(1)
			end
		},
		{
			-- would fail if: Open did not take the mouse (a popup), or took it through another way than the field
			name = "Open makes it a popup (the way is a field), draggable and resizable",
			func = function()
				stubAll({})
				local popups = 0
				DW().MakePopup = function() popups = popups + 1 end
				DW().Open()
				local frame = DW().Frame

				expect(popups >= 1).to.beTrue()
				expect(frame:GetDraggable()).to.beTrue()
				expect(frame:GetSizable()).to.beTrue()
			end
		},
		{
			-- would fail if: closing destroyed the panel and Open then showed a stale one, or closing left it visible
			name = "closing hides the window and the next Open shows it again, still a single one",
			func = function()
				local frame = build({})
				frame:Close()
				expect(IsValid(DW().Frame)).to.beTrue()
				expect(DW().Frame:IsVisible()).to.beFalse()

				DW().Open()
				expect(DW().Frame:IsVisible()).to.beTrue()
			end
		},
		{
			-- would fail if: a variant was dropped, an event with variants kept its own button, or one without variants got none
			name = "a registry of two invented events, one with 3 variants: exactly 1 + 3 buttons, with the labels of the registry",
			func = function()
				local frame = build({"zz_alpha", "zz_beta"}, {zz_alpha = ALPHA, zz_beta = {label = "Beta effect"}})

				expect(#frame.GryEventButtons).to.equal(4)
				expect(#buttonsOf(frame.GryEventGrid)).to.equal(4)

				local labels = {}

				for _, button in ipairs(frame.GryEventButtons) do
					labels[#labels + 1] = button:GetText()
				end

				expect(table.concat(labels, "|")).to.equal("alpha one|alpha two|alpha three|Beta effect")
			end
		},
		{
			-- would fail if: the window needed GetHUDEventInfo (the other agent's function) to open
			name = "without GetHUDEventInfo, or with no description for an event, the button is the name, alone, with no tooltip",
			func = function()
				local frame = build({"zz_alpha", "zz_gamma"}, {})
				GryMod.API.GetHUDEventInfo = nil
				DW().Open()
				frame = DW().Frame

				expect(#frame.GryEventButtons).to.equal(2)
				expect(frame.GryEventButtons[1]:GetText()).to.equal("zz_alpha")
				expect(frame.GryEventButtons[2]:GetText()).to.equal("zz_gamma")
				expect(frame.GryEventButtons[1]:GetTooltip()).to.beNil()
			end
		},
		{
			-- would fail if: Open did not read the registry again (an event registered after the first Open would never appear)
			name = "an event registered after the first Open appears at the next Open, and the old buttons are not kept twice",
			func = function()
				local frame = build({"zz_beta"}, {zz_beta = {label = "Beta effect"}})
				expect(#frame.GryEventButtons).to.equal(1)

				GryMod.API.ListHUDEvents = function() return {"zz_beta", "zz_late"} end
				DW().Open()
				expect(#DW().Frame.GryEventButtons).to.equal(2)
				expect(#buttonsOf(DW().Frame.GryEventGrid)).to.equal(2)
			end
		},
		{
			-- would fail if: the window raised an error when ListHUDEvents is not there yet
			name = "without ListHUDEvents (or an empty list) the window opens with an empty grid and raises nothing",
			func = function()
				stubAll({})
				GryMod.API.ListHUDEvents = nil
				DW().Open()
				expect(IsValid(DW().Frame)).to.beTrue()
				expect(#DW().Frame.GryEventButtons).to.equal(0)

				GryMod.API.ListHUDEvents = function() return nil end
				DW().Open()
				expect(#DW().Frame.GryEventButtons).to.equal(0)
			end
		},
		{
			-- would fail if: a button did not call the API, lost the seconds of the slider, or lost the data of its variant
			name = "a button plays its event through GryMod.API.HUDEvent with the seconds of the slider and the data of its variant, and only that",
			func = function()
				local frame = build({"zz_alpha"}, {zz_alpha = ALPHA})
				frame.GrySeconds:SetValue(7.5)
				find(frame, "alpha three"):DoClick()

				expect(#played).to.equal(1)
				expect(played[1].name).to.equal("zz_alpha")
				expect(played[1].data.seconds).to.equal(7.5)
				expect(played[1].data.power).to.equal(3)
				expect(played[1].data.tag).to.equal("x")

				-- the data of the registry is not changed by the click
				expect(ALPHA.variants[3].data.seconds).to.beNil()

				find(frame, "alpha one"):DoClick()
				expect(played[2].data.power).to.equal(1)
				expect(played[2].data.tag).to.beNil()
			end
		},
		{
			name = "the slider goes from 0.5 to 15 seconds",
			func = function()
				local frame = build({})
				expect(frame.GrySeconds:GetMin()).to.equal(0.5)
				expect(frame.GrySeconds:GetMax()).to.equal(15)
			end
		},
		{
			-- would fail if: the tooltip did not come from `follows`, or blocked the button, or stayed when the option is on
			name = "when an option of `follows` is off the tooltip of each button of the event says so, and the button still plays; with the option on there is none",
			func = function()
				local frame = build({"zz_alpha", "zz_beta"}, {zz_alpha = ALPHA, zz_beta = {label = "Beta effect"}})
				local convar = GetConVar("gry_screenfx")
				local before = convar:GetString()
				local ok, err = pcall(function()
					convar:SetString("0")
					DW().Open() -- the tooltips are made again

					local button = find(DW().Frame, "alpha two")
					local tip = button:GetTooltip() or ""
					expect(string.find(tip, "off by your option", 1, true) ~= nil).to.beTrue()
					expect(string.find(tip, "gry_screenfx", 1, true) ~= nil).to.beTrue()
					expect(string.find(tip, "the screen effects of the test", 1, true) ~= nil).to.beTrue()

					-- every variant of the event, not the first one only; an event without `follows` has none
					expect(find(DW().Frame, "alpha three"):GetTooltip()).to.equal(tip)
					expect(find(DW().Frame, "Beta effect"):GetTooltip()).to.beNil()

					button:DoClick()
					expect(#played).to.equal(1)
				end)

				convar:SetString(before)

				if not ok then
					error(err, 0)
				end

				DW().Open()
				expect(find(DW().Frame, "alpha two"):GetTooltip()).to.beNil()
			end
		},
		{
			-- would fail if: Open did not ask the server (the list would stay what it was at the first Open for ever)
			name = "each Open asks the server for the list of the real commands",
			func = function()
				build({})
				expect(asked).to.equal(1)
				DW().Open()
				DW().Open()
				expect(asked).to.equal(3)
			end
		},
		{
			-- would fail if: the real section was a fixed set of buttons
			name = "the real section is built from the list received: two invented commands, two buttons, in the order of the list, with its labels",
			func = function()
				local frame = build({}, nil, true, CMDS)

				expect(#frame.GryRealOrder).to.equal(2)
				expect(frame.GryRealOrder[1]).to.equal("zz_one")
				expect(frame.GryRealOrder[2]).to.equal("zz_two")
				expect(#buttonsOf(frame.GryRealGrid)).to.equal(2)
				expect(frame.GryRealButtons.zz_one:GetText()).to.equal("Do one")
				expect(frame.GryRealButtons.zz_two:GetText()).to.equal("Do two")

				-- an admin: active, and a click sends the id of its own entry, once
				for id, button in pairs(frame.GryRealButtons) do
					expect(button:IsEnabled()).to.beTrue()
					button:DoClick()
					expect(sent[#sent]).to.equal(id)
				end

				expect(#sent).to.equal(2)
			end
		},
		{
			-- would fail if: an answer that comes while the window is open did not show (a command registered later, a list that was empty)
			name = "a list that arrives while the window is open makes the buttons again: the old ones are gone, the new ones are there",
			func = function()
				local frame = build({}, nil, true, CMDS)
				asAdmin(true, function()
					DW().SetRealList({{id = "zz_three", label = "Do three"}})
				end)

				expect(#frame.GryRealOrder).to.equal(1)
				expect(frame.GryRealButtons.zz_one).to.beNil()
				expect(frame.GryRealButtons.zz_three:GetText()).to.equal("Do three")
				expect(#buttonsOf(frame.GryRealGrid)).to.equal(1)
			end
		},
		{
			-- would fail if: a malformed entry of a list became a button (a nil id could then be sent)
			name = "what is not an id and a label of text in the list is dropped",
			func = function()
				local frame = build({}, nil, true, {{id = "zz_ok", label = "Fine"}, {id = 5, label = "No"}, {label = "No id"}, {id = "zz_nolabel"}, "text"})
				expect(#frame.GryRealOrder).to.equal(1)
				expect(frame.GryRealOrder[1]).to.equal("zz_ok")
			end
		},
		{
			-- would fail if: the receiver did not read the message of the server as the server writes it (a count of 8 bits, then two strings each)
			name = "the receiver of gry_debug_list reads the message the server sends and makes the real buttons",
			func = function()
				local frame = build({}, nil, true, {})
				local receiver = net.Receivers["gry_debug_list"]
				local items = {2, "zz_x", "Label X", "zz_y", "Label Y"}
				local head = 0
				local function nextItem() head = head + 1 return items[head] end

				local realU, realS = net.ReadUInt, net.ReadString
				net.ReadUInt, net.ReadString = nextItem, nextItem
				local ok, err = pcall(function()
					asAdmin(true, function() receiver(0) end)
				end)
				net.ReadUInt, net.ReadString = realU, realS

				if not ok then
					error(err, 0)
				end

				expect(#frame.GryRealOrder).to.equal(2)
				expect(frame.GryRealButtons.zz_y:GetText()).to.equal("Label Y")
			end
		},
		{
			-- would fail if: a non-admin could click a real command (the server refuses anyway, but the button must say it is off)
			name = "the real section is grey and inactive for a player who is not an admin, with a tooltip that says why, and a click sends nothing",
			func = function()
				local frame = build({}, nil, false, CMDS)

				for id, button in pairs(frame.GryRealButtons) do
					expect(button:IsEnabled()).to.beFalse()
					expect(button:GetAlpha() < 255).to.beTrue()
					expect(string.find(button:GetTooltip() or "", "dministrator", 1, true) ~= nil).to.beTrue()

					button:DoClick() -- something that skips the mouse code
				end

				expect(#sent).to.equal(0)
			end
		},
		{
			-- would fail if: the visual buttons were greyed with the real ones (they are for everybody)
			name = "the effect buttons are not affected by the admin status",
			func = function()
				local frame = build({"zz_beta"}, {zz_beta = {label = "Beta effect"}}, false, CMDS)
				expect(find(frame, "Beta effect"):IsEnabled()).to.beTrue()
				find(frame, "Beta effect"):DoClick()
				expect(#played).to.equal(1)
			end
		},
		{
			-- would fail if: the window turned an admin who loses his rights into one who keeps the buttons
			name = "the status is looked at again while the window is open: a player who stops being an admin gets the buttons greyed",
			func = function()
				local frame = build({}, nil, true, CMDS)
				expect(frame.GryRealButtons.zz_one:IsEnabled()).to.beTrue()

				asAdmin(false, function()
					DW().Poll(frame, RealTime() + 5)
				end)

				expect(frame.GryRealButtons.zz_one:IsEnabled()).to.beFalse()
			end
		},
		{
			-- would fail if: Destroy left the panel, or the hot reload of the file left an old window behind
			name = "Destroy removes the window for good, and the next Open builds a new one",
			func = function()
				local frame = build({})
				DW().Destroy()
				expect(IsValid(frame)).to.beFalse()
				expect(DW().Frame).to.beNil()

				DW().Open()
				expect(IsValid(DW().Frame)).to.beTrue()
			end
		},
		{
			-- would fail if: the button of the options panel was not at the bottom, after the administrators' section
			name = "the options panel ends with the button that opens the window",
			func = function()
				stubAll({})
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					asAdmin(true, function()
						GryMod.GryOptionschute(panel)
					end)

					local found, lastButton

					local function walk(root)
						for _, child in ipairs(root:GetChildren()) do
							if child.ClassName == "DButton" or child.ClassName == "DCheckBoxLabel" or child.ClassName == "DComboBox" then
								lastButton = child
							end

							if child.ClassName == "DButton" and child.GetText and child:GetText() == "Open the effects test window" then
								found = child
							end

							walk(child)
						end
					end

					walk(panel)
					expect(found ~= nil).to.beTrue()
					expect(lastButton).to.equal(found)

					found:DoClick()
					expect(IsValid(DW().Frame)).to.beTrue()
				end)
				panel:Remove()

				if not ok then
					error(err, 0)
				end
			end
		}
	}
}
