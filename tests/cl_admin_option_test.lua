-- Tests of the administrators' settings in the options panel (GryMod.AdminOption and GryMod.AdminUI, cl_admin_option.lua), GLuaTest format,
-- client realm. The settings that belong to the SERVER (the white list in sh_server_options.lua) are in a section of their own, greyed and disabled
-- (grey, a tooltip that says why) when the player is not an admin; they never write the convar from the client (on a dedicated server a client cannot
-- change a server convar): they ask the server with ONE net message, and the box shows the value the server really has. No global is replaced here:
-- the transport and the command runner are fields of GryMod.AdminUI (put back after each case), and the admin status is swapped on the Player
-- metatable inside a pcall that always puts it back.

local UI = function() return GryMod.AdminUI end

local realTransport, realRunner, realSendMessage

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

local function newPanel()
	return vgui.Create("ControlPanel")
end

-- every panel under (and including) `root`
local function walk(root, visit, flag)
	for _, child in ipairs(root:GetChildren()) do
		visit(child, flag or child.GryAdminItem)
		walk(child, visit, flag or child.GryAdminItem)
	end
end

local function indexOf(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
end

local INTERACTIVE = {DCheckBoxLabel = true, DButton = true, DComboBox = true, DNumSlider = true, DBinder = true, DColorMixer = true}

-- the server settings that are on the Compatibility page (cl_options_compat.lua, the Suit effects tab): the others are on the Server page (cl_options.lua, cl_options_radar.lua)
local COMPAT_MENU = {gry_suit_handling = true, gry_suit_reload_rate = true, gry_suit_shot_cost = true, gry_suit_shot_cost_by_ammo = true, gry_suit_melee_cost = true, gry_suit_strength_melee = true, gry_suit_strength_recoil = true}

-- the settings of the white list that the Server page holds (the radar ones included): one control for each, and the reset action
local function serverPageSettings()
	local list = {}

	for _, setting in ipairs(GryMod.ServerSettings.List) do
		if not COMPAT_MENU[setting.name] then
			list[#list + 1] = setting.name
		end
	end

	return list
end

local function serverPage(isAdmin)
	local panel = newPanel()

	asAdmin(isAdmin, function()
		GryMod.ServerOptionsPanel(panel)
	end)

	return panel
end

return {
	groupName = "GryMod administrators' settings (options panel)",
	beforeEach = function()
		realTransport, realRunner, realSendMessage = UI().Transport, UI().RunCommand, UI().SendMessage
	end,
	afterEach = function()
		UI().Transport, UI().RunCommand, UI().SendMessage = realTransport, realRunner, realSendMessage
	end,
	cases = {
		{
			name = "the decision is a pure function: an admin has the option on and no tooltip, anybody else has it off with the tooltip that says why",
			func = function()
				local on, tip = UI().Decide(true)
				expect(on).to.beTrue()
				expect(tip).to.beNil()

				local off, why = UI().Decide(false)
				expect(off).to.beFalse()
				expect(why).to.equal("Server setting: administrators only")

				-- what is not known to be an admin is not one
				expect((UI().Decide(nil))).to.beFalse()
				expect((UI().Decide("yes"))).to.beFalse()
			end
		},
		{
			name = "the line above the section follows the status: what an admin can do, what the others cannot",
			func = function()
				local admin, other = UI().StatusText(true), UI().StatusText(false)
				expect(admin ~= other).to.beTrue()
				expect(string.find(admin, "administrator", 1, true) ~= nil).to.beTrue()
				expect(string.find(other, "not", 1, true) ~= nil).to.beTrue()
			end
		},
		{
			name = "IsAdmin is the local player's status as the engine knows it, and a missing player is no admin",
			func = function()
				expect(UI().IsAdmin()).to.equal(LocalPlayer():IsAdmin())
				asAdmin(false, function() expect(UI().IsAdmin()).to.beFalse() end)
				asAdmin(true, function() expect(UI().IsAdmin()).to.beTrue() end)
				expect(LocalPlayer():IsAdmin()).to.equal(UI().IsAdmin()) -- put back
			end
		},
		{
			name = "a yes / no option is a check box that shows the value the server has and is not tied to a client convar",
			func = function()
				local panel = newPanel()
				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box.ClassName).to.equal("DCheckBoxLabel")
						expect(box:GetChecked()).to.equal(GetConVar("gry_malfunction"):GetBool())
						expect(box.Button.m_strConVar).to.beNil()
						expect(box:GetText()).to.equal("label")
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "an admin who ticks a box sends the name and the value through the transport, once, and the convar is not written from the client",
			func = function()
				local panel = newPanel()
				local sent = {}
				UI().Transport = function(name, value) sent[#sent + 1] = name .. "=" .. value end
				local before = GetConVar("gry_malfunction"):GetString()

				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box:IsEnabled()).to.beTrue()
						box:SetValue(not box:GetChecked())
						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal("gry_malfunction=" .. (before == "1" and "0" or "1"))
						expect(GetConVar("gry_malfunction"):GetString()).to.equal(before)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for a player who is not an admin the box is disabled, dimmed, has the tooltip, and a click that gets through anyway sends nothing and changes nothing shown",
			func = function()
				local panel = newPanel()
				local sent = 0
				UI().Transport = function() sent = sent + 1 end

				local ok, err = pcall(function()
					asAdmin(false, function()
						local box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						local shown = box:GetChecked()
						expect(box:IsEnabled()).to.beFalse()
						expect(box.Button:IsEnabled()).to.beFalse()
						expect(box:GetAlpha() < 255).to.beTrue() -- attenuated
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")
						expect(box.Button:IsMouseInputEnabled()).to.beFalse()

						box.Button:DoClick() -- something that skips the mouse code
						expect(sent).to.equal(0)
						expect(box:GetChecked()).to.equal(shown)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "a choice option is a selector that shows the server's value and asks for the other one through the transport",
			func = function()
				local panel = newPanel()
				local sent = {}
				UI().Transport = function(name, value) sent[#sent + 1] = name .. "=" .. value end

				local ok, err = pcall(function()
					asAdmin(true, function()
						local combo = GryMod.AdminOption(panel, "Suit rules", "gry_mechanics", "choice", {
							choices = {{"Crysis numbers", "crysis"}, {"Classic", "classic"}}
						})
						expect(combo.ClassName).to.equal("DComboBox")

						local value = GetConVar("gry_mechanics"):GetString()
						expect(combo:GetValue()).to.equal(value == "crysis" and "Crysis numbers" or "Classic")

						combo:ChooseOptionID(value == "crysis" and 2 or 1)
						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal("gry_mechanics=" .. (value == "crysis" and "classic" or "crysis"))
						expect(GetConVar("gry_mechanics"):GetString()).to.equal(value)
					end)

					asAdmin(false, function()
						sent = {}
						local combo = GryMod.AdminOption(panel, "Suit rules", "gry_mechanics", "choice", {
							choices = {{"Crysis numbers", "crysis"}, {"Classic", "classic"}}
						})
						expect(combo:IsEnabled()).to.beFalse()
						combo:ChooseOptionID(2)
						expect(#sent).to.equal(0)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "a button option runs its console command for an admin only (the server checks again)",
			func = function()
				local panel = newPanel()
				local ran = {}
				UI().RunCommand = function(command) ran[#ran + 1] = command end

				local ok, err = pcall(function()
					asAdmin(true, function()
						local button = GryMod.AdminOption(panel, "Toggle", nil, "button", {command = "gry_Health"})
						expect(button.ClassName).to.equal("DButton")
						expect(button:IsEnabled()).to.beTrue()
						button:DoClick()
						expect(#ran).to.equal(1)
						expect(ran[1]).to.equal("gry_Health")
					end)

					asAdmin(false, function()
						ran = {}
						local button = GryMod.AdminOption(panel, "Toggle", nil, "button", {command = "gry_Health"})
						expect(button:IsEnabled()).to.beFalse()
						button:DoClick()
						expect(#ran).to.equal(0)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the state follows the player live: the poll (once a second, from the panel's Think) greys the options when the player stops being an admin and turns them on again when he becomes one",
			func = function()
				local panel = newPanel()

				local ok, err = pcall(function()
					local box, status
					asAdmin(true, function()
						box = GryMod.AdminOption(panel, "label", "gry_malfunction", "bool")
						expect(box:IsEnabled()).to.beTrue()
					end)

					asAdmin(false, function()
						-- less than a second after the last poll: nothing is looked at
						UI().Poll(panel, panel.GryAdminPolled + 0.5)
						expect(box:IsEnabled()).to.beTrue()

						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:IsEnabled()).to.beFalse()
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")
					end)

					asAdmin(true, function()
						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:IsEnabled()).to.beTrue()
						expect(box:GetParent():GetTooltip()).to.beNil()
					end)

					-- and the panel's own Think makes the poll (with the real time)
					asAdmin(false, function()
						panel.GryAdminPolled = -10
						panel:Think()
						expect(box:IsEnabled()).to.beFalse()
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the box follows the value the server really has, and goes back to it when the server did not take a request",
			func = function()
				local panel = newPanel()
				local fake = CreateClientConVar("gry_test_admin_option", "1", false, false)

				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "label", "gry_test_admin_option", "bool")
						expect(box:GetChecked()).to.beTrue()

						fake:SetInt(0) -- a client convar here: a replicated one is changed by the server only
						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:GetChecked()).to.beFalse()

						-- the player ticks it: the request goes, the server does not change the convar (a refusal, the rate limit...): the box comes back to the real value
						local sent = 0
						UI().Transport = function() sent = sent + 1 end
						box:SetValue(true)
						expect(sent).to.equal(1)
						expect(box:GetChecked()).to.beTrue()
						UI().Poll(panel, panel.GryAdminPolled + 3)
						expect(box:GetChecked()).to.beFalse()
						expect(sent).to.equal(1) -- the poll only shows, it never asks
					end)
				end)

				fake:SetInt(1)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the Server page holds the settings of the white list that are not the suit's weapon effects (the two toggles included, as check boxes), and only those, and no control of the player",
			func = function()
				local panel = serverPage(true)
				local ok, err = pcall(function()
					local seen = {}
					for name in pairs(panel.GryAdminControls or {}) do
						if string.sub(name, 1, 7) ~= "action:" then
							seen[#seen + 1] = name
						end
					end

					local expected = serverPageSettings()

					table.sort(seen)
					table.sort(expected)
					expect(table.concat(seen, ",")).to.equal(table.concat(expected, ","))

					-- the kind of each control is the kind of the list
					for _, setting in ipairs(GryMod.ServerSettings.List) do
						local control = panel.GryAdminControls[setting.name]
						if COMPAT_MENU[setting.name] then
							expect(control).to.beNil()
						else
							expect(control.ClassName).to.equal(setting.kind == "choice" and "DComboBox" or "DCheckBoxLabel")
						end
					end

					-- every control of the page is an administrators' one: nothing of the player's is mixed in
					walk(panel, function(child, admin)
						if INTERACTIVE[child.ClassName] and not admin then
							expect(child.ClassName).to.equal("DButton") -- the arrows of the tab strip, when the tabs do not fit
							expect(child:GetText()).to.equal("")
						end
					end)

					-- none of the server settings is a box tied to a client convar any more
					for _, setting in ipairs(GryMod.ServerSettings.List) do
						walk(panel, function(child)
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								expect(child.Button.m_strConVar ~= setting.name).to.beTrue()
							end
						end)
					end
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: a toggle is left as a button (or made as another control), is bound to another name, or moves away from its neighbour
			name = "the two toggles (health regeneration, infinite armor) are check boxes of the section, bound to the names of the white list, with their labels, where the two buttons were, and no button option is left",
			func = function()
				local panel = serverPage(true)
				local ok, err = pcall(function()
					local regen = panel.GryAdminControls["gry_health_regen"]
					local armor = panel.GryAdminControls["gry_infinite_armor"]

					for _, control in ipairs({regen, armor}) do
						expect(control ~= nil).to.beTrue()
						expect(control.ClassName).to.equal("DCheckBoxLabel")
						expect(control.Button.m_strConVar).to.beNil() -- never a client convar: the server decides
					end

					expect(regen:GetText()).to.equal("Health regeneration")
					expect(armor:GetText()).to.equal("Infinite armor")

					-- they show what the server has
					expect(regen:GetChecked()).to.equal(GetConVar("gry_health_regen"):GetBool())
					expect(armor:GetChecked()).to.equal(GetConVar("gry_infinite_armor"):GetBool())

					-- no entry is named after a command (the only button of the page is the action, named after its message)
					for name in pairs(panel.GryAdminControls) do
						expect(string.sub(name, 1, 7) ~= "button:").to.beTrue()
					end

					-- the two are neighbours, in this order, in the Suit rules tab
					local names = {}

					for _, entry in ipairs(panel.GryAdminEntries) do
						names[#names + 1] = tostring(entry.name)
					end

					expect(string.find(table.concat(names, ","), "gry_health_regen,gry_infinite_armor", 1, true) ~= nil).to.beTrue()
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the front prediction is missing from the toggles, or a click does not send the request
			name = "the two toggles ask the server like the other check boxes: an admin's click sends the name and the value through the transport (no convar written, no console command), a player who is not an admin has them disabled with the tooltip and sends nothing",
			func = function()
				local sent, ran = {}, 0
				UI().Transport = function(name, value) sent[#sent + 1] = name .. "=" .. value end
				UI().RunCommand = function() ran = ran + 1 end

				local admin, other = serverPage(true), serverPage(false)
				local ok, err = pcall(function()
					for _, name in ipairs({"gry_health_regen", "gry_infinite_armor"}) do
						local box = admin.GryAdminControls[name]
						local before = GetConVar(name):GetString()

						expect(box:IsEnabled()).to.beTrue()

						sent = {}
						asAdmin(true, function()
							box:SetValue(not box:GetChecked())
						end)

						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal(name .. "=" .. (before == "1" and "0" or "1"))
						expect(GetConVar(name):GetString()).to.equal(before)

						local off = other.GryAdminControls[name]

						sent = {}
						expect(off:IsEnabled()).to.beFalse()
						expect(off:GetParent():GetTooltip()).to.equal("Server setting: administrators only")

						asAdmin(false, function()
							off:SetValue(not off:GetChecked()) -- a change that got through the mouse
						end)

						expect(#sent).to.equal(0)
					end

					expect(ran).to.equal(0)
				end)
				admin:Remove()
				other:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for a player who is not an admin every control of the Server page is disabled (the arrows of the tab strip are not its controls)",
			func = function()
				local panel = serverPage(false)
				local ok, err = pcall(function()
					asAdmin(false, function()
						local admins = 0
						walk(panel, function(child, admin)
							if INTERACTIVE[child.ClassName] and admin then
								admins = admins + 1
								expect(child:IsEnabled()).to.beFalse()
							end
						end)

						expect(admins).to.equal(#serverPageSettings() + 1) -- one control for each setting and the reset action: the toggles are check boxes
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "for an admin every control of the Server page is enabled",
			func = function()
				local panel = serverPage(true)
				local ok, err = pcall(function()
					asAdmin(true, function()
						local admins = 0
						walk(panel, function(child, admin)
							if admin and INTERACTIVE[child.ClassName] then
								admins = admins + 1
								expect(child:IsEnabled()).to.beTrue()
							end
						end)

						expect(admins).to.equal(#serverPageSettings() + 1)
					end)
				end)
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: a setting of the white list is on neither page, or on both
			name = "the Server and the Compatibility pages together hold every setting of the white list exactly once, the Compatibility page the suit's weapon ones, the Server page the others and the reset action",
			func = function()
				local server, compat = newPanel(), newPanel()
				local ok, err = pcall(function()
					asAdmin(true, function()
						GryMod.ServerOptionsPanel(server)
						GryMod.CompatOptionsPanel(compat)
					end)

					for _, setting in ipairs(GryMod.ServerSettings.List) do
						local inServer = server.GryAdminControls[setting.name] ~= nil
						local inCompat = compat.GryAdminControls[setting.name] ~= nil

						expect((inServer and 1 or 0) + (inCompat and 1 or 0)).to.equal(1)
						expect(inCompat).to.equal(COMPAT_MENU[setting.name] == true)
					end

					local names = {}

					for name in pairs(compat.GryAdminControls) do
						names[#names + 1] = name
					end

					table.sort(names)
					expect(table.concat(names, ",")).to.equal("gry_suit_handling,gry_suit_melee_cost,gry_suit_reload_rate,gry_suit_shot_cost,gry_suit_shot_cost_by_ammo,gry_suit_strength_melee,gry_suit_strength_recoil")

					-- the radar tab of the Server page has the radar ones and the reset action
					for _, name in ipairs({"gry_radar_allies_always", "gry_radar_detect", "gry_radar_objects", "gry_radar_pings", "gry_radar_teammates", "gry_zonemap", "gry_zonemap_navmesh", "action:gry_zonemap_reset"}) do
						expect(server.GryAdminControls[name] ~= nil).to.beTrue()
					end
				end)
				server:Remove()
				compat:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the action button sends without asking, ignores the answer, or is made as a check box
			name = "an action option is a button tied to no setting: a click asks first, on yes it sends its message (no payload), on no it sends nothing",
			func = function()
				local panel = newPanel()
				local sent, asked = {}, {}
				local realSend, realConfirm = UI().SendMessage, GryMod.Confirm
				UI().SendMessage = function(name) sent[#sent + 1] = name end

				local answer = true
				GryMod.Confirm = function(text, onYes)
					asked[#asked + 1] = text

					if answer then
						onYes()
					end
				end

				local ok, err = pcall(function()
					asAdmin(true, function()
						local box = GryMod.AdminOption(panel, "Do it", nil, "action", {message = "gry_test_message", confirm = "Really do it?"})
						expect(box.ClassName).to.equal("DButton")
						expect(box:GetText()).to.equal("Do it")
						expect(box:IsEnabled()).to.beTrue()
						expect(#asked).to.equal(0) -- building it asks nothing

						answer = false
						box:DoClick()
						expect(#asked).to.equal(1)
						expect(asked[1]).to.equal("Really do it?")
						expect(#sent).to.equal(0)

						answer = true
						box:DoClick()
						expect(#asked).to.equal(2)
						expect(#sent).to.equal(1)
						expect(sent[1]).to.equal("gry_test_message")

						-- the poll leaves it alone (no value to show) and nothing is asked again
						UI().Poll(panel, panel.GryAdminPolled + 3)
						expect(#sent).to.equal(1)
					end)
				end)

				UI().SendMessage, GryMod.Confirm = realSend, realConfirm
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			-- breaks if: the front prediction is missing from the action kind
			name = "an action option for a player who is not an admin is disabled with the tooltip, and a click that gets through asks nothing and sends nothing; the poll enables it when he becomes an admin",
			func = function()
				local panel = newPanel()
				local sent, asked, ran = 0, 0, 0
				local realSend, realConfirm = UI().SendMessage, GryMod.Confirm
				UI().SendMessage = function() sent = sent + 1 end
				GryMod.Confirm = function(_, onYes) asked = asked + 1 onYes() end

				local ok, err = pcall(function()
					local box
					asAdmin(false, function()
						box = GryMod.AdminOption(panel, "Do it", nil, "action", {onTick = function() ran = ran + 1 end, confirm = "Sure?"})
						expect(box.ClassName).to.equal("DButton")
						expect(box:IsEnabled()).to.beFalse()
						expect(box:GetParent():GetTooltip()).to.equal("Server setting: administrators only")

						box:DoClick()
						expect(asked).to.equal(0)
						expect(sent).to.equal(0)
						expect(ran).to.equal(0)
					end)

					asAdmin(true, function()
						UI().Poll(panel, panel.GryAdminPolled + 1.01)
						expect(box:IsEnabled()).to.beTrue()
						expect(box:GetParent():GetTooltip()).to.beNil()

						-- opts.onTick runs instead of a message
						box:DoClick()
						expect(asked).to.equal(1)
						expect(ran).to.equal(1)
						expect(sent).to.equal(0)
					end)
				end)

				UI().SendMessage, GryMod.Confirm = realSend, realConfirm
				panel:Remove()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "the real SendMessage is the net message with no payload",
			func = function()
				local realStart, realSend = net.Start, net.SendToServer
				local log = {}
				local ok, err = pcall(function()
					net.Start = function(name) log[#log + 1] = "start:" .. name end
					net.SendToServer = function() log[#log + 1] = "send" end
					realSendMessage("gry_zonemap_reset")
				end)

				net.Start, net.SendToServer = realStart, realSend
				if not ok then error(err, 0) end

				expect(table.concat(log, "|")).to.equal("start:gry_zonemap_reset|send")
			end
		},
		{
			name = "the real transport is the net message gry_set_server_option with the name and the value as two strings",
			func = function()
				expect(util.NetworkStringToID("gry_set_server_option") ~= 0).to.beTrue()

				local realStart, realWrite, realSend = net.Start, net.WriteString, net.SendToServer
				local log = {}
				local ok, err = pcall(function()
					net.Start = function(name) log[#log + 1] = "start:" .. name end
					net.WriteString = function(text) log[#log + 1] = "string:" .. text end
					net.SendToServer = function() log[#log + 1] = "send" end
					realTransport("gry_malfunction", "0")
				end)

				net.Start, net.WriteString, net.SendToServer = realStart, realWrite, realSend
				if not ok then error(err, 0) end

				expect(table.concat(log, "|")).to.equal("start:gry_set_server_option|string:gry_malfunction|string:0|send")
				expect(net.Start).to.equal(realStart)
			end
		},
	}
}
