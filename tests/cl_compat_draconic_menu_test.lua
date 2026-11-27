-- Tests of the Draconic Base weapon menu, client side (lua/grymod/compat/weapons/cl_draconic_menu.lua), GLuaTest format, client realm. The weapon icon of the quick menu must open
-- Draconic's customization menu (its attachments, its camouflages) for the weapon in hand. Draconic opens it from the SERVER (DRC:ForceAttachmentMenu puts the weapon in inspection mode
-- and tells the client), so the opener only sends the request "gry_draconic_customize"; the server side is tested in sv_compat_draconic_test.lua. Draconic's weapons are stood in for (the
-- real ones are tried in the game). Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a Draconic weapon stand-in; the fields that matter are the marker, CanCustomize (shared: false for a weapon with nothing to choose or when the server forbids it) and Customizing
local function weapon(fields)
	local w = {Draconic = true, Customizing = false}

	function w:IsValid() return true end
	function w:GetClass() return "test_draconic_gun" end
	function w:CanCustomize(bypass) return bypass == true end

	for k, v in pairs(fields or {}) do
		w[k] = v
	end

	return w
end

return {
	groupName = "GryMod compat: Draconic Base weapon menu (client)",
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the provider is not added, answers for a weapon that is not Draconic's (the TFA and ARC9 icons would be taken over), or opens for a weapon with nothing to customize
			name = "the weapon icon opens Draconic's menu only for a Draconic weapon that can be customized",
			func = function()
				local API = GryMod.API

				stub(_G, "DRC", {SV = {drc_inspections = 1}})

				expect(API.GetWeaponMenu(weapon())).to.beA("function")
				expect(API.GetWeaponMenu(weapon({Draconic = false}))).to.beNil()
				expect(API.GetWeaponMenu({IsValid = function() return true end})).to.beNil()
				expect(API.GetWeaponMenu(weapon({CanCustomize = function() return false end}))).to.beNil()
				expect(API.GetWeaponMenu(weapon({CanCustomize = false}))).to.beNil()
			end
		},
		{
			-- fails when the question to CanCustomize is the one that needs the inspection mode already on (the weapon is not inspecting when the quick menu opens it: the answer would always be no)
			name = "the question is asked with the inspection bypass: the weapon is not inspecting yet",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 1}})

				local asked

				expect(GryMod.API.GetWeaponMenu(weapon({CanCustomize = function(_, bypass) asked = bypass return true end}))).to.beA("function")
				expect(asked).to.equal(true)
			end
		},
		{
			-- fails when the fists get an empty menu: the base answers "yes" to CanCustomize for any melee weapon, whatever it has to choose (no attachment slot), so a melee weapon needs a camouflage
			-- list (WeaponSkinDefaultMat) to be offered
			name = "a melee weapon is offered the menu only when it has camouflages to choose",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 1}})

				expect(GryMod.API.GetWeaponMenu(weapon({IsMelee = true}))).to.beNil()
				expect(GryMod.API.GetWeaponMenu(weapon({IsMelee = true, WeaponSkinDefaultMat = "models/x"}))).to.beA("function")
				expect(GryMod.API.GetWeaponMenu(weapon({IsMelee = false}))).to.beA("function")
			end
		},
		{
			-- fails when the menu is offered while the server has switched the inspection off (sv_drc_inspections 0: the server refuses it, the icon would do nothing)
			name = "no menu while the server forbids the inspection",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 0}})

				expect(GryMod.API.GetWeaponMenu(weapon())).to.beNil()
			end
		},
		{
			-- fails when the provider raises an error for a weapon whose CanCustomize raises one (a pack with a broken weapon), or when it answers anything but nil
			name = "a weapon whose CanCustomize fails has no menu and raises nothing",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 1}})

				local ok, menu = pcall(GryMod.API.GetWeaponMenu, weapon({CanCustomize = function() error("broken pack") end}))

				expect(ok).to.beTrue()
				expect(menu).to.beNil()
			end
		},
		{
			-- fails when Draconic is not installed and the provider still answers
			name = "nothing without the Draconic library",
			func = function()
				stub(_G, "DRC", nil)

				expect(GryMod.API.GetWeaponMenu(weapon())).to.beNil()
			end
		},
		{
			-- fails when the opener does not send the request, sends another message, or sends it more than once
			name = "the opener sends the request to the server, once",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 1}})

				local started, sent = {}, 0

				stub(net, "Start", function(name) started[#started + 1] = name end)
				stub(net, "SendToServer", function() sent = sent + 1 end)

				local w = weapon()

				expect(GryMod.API.OpenWeaponMenu(w)).to.beTrue()
				expect(#started).to.equal(1)
				expect(started[1]).to.equal("gry_draconic_customize")
				expect(sent).to.equal(1)
			end
		},
		{
			-- fails when the camouflage stays on the gun while Draconic's menu is up (the player would pick parts on a gun that is not there), or when it goes plain without the menu
			name = "the gun is plain while Draconic's customization menu is up",
			func = function()
				local plain = GryMod.API.IsPlainView

				expect(plain).to.beA("function")
				expect(plain(weapon({Customizing = true}))).to.beTrue()
				expect(plain(weapon({Customizing = false}))).to.beFalse()
				expect(plain(weapon({Draconic = false, Customizing = true}))).to.beFalse()
			end
		},
		{
			-- fails when the opener does not follow up: Draconic's own message reaches the client before its inspection screen is ready, and the panel then refuses to open (while the weapon is
			-- already marked as customizing, so the gun would be plain and no menu there): a short wait must exist after the request
			name = "the opener starts a short wait that opens the panel when the base is ready, and stops after two seconds",
			func = function()
				stub(_G, "DRC", {SV = {drc_inspections = 1}})
				stub(net, "Start", function() end)
				stub(net, "SendToServer", function() end)

				local created

				stub(timer, "Create", function(name, delay, reps, fn) created = {name = name, delay = delay, reps = reps, fn = fn} end)

				GryMod.API.OpenWeaponMenu(weapon())
				expect(created).to.exist()
				expect(created.reps).to.beGreaterThan(5)
				expect(created.reps * created.delay).to.beBetween(1.5, 3)
			end
		},
		{
			-- fails when the panel is asked for before the weapon is inspecting and the base has drawn its screen once (the base refuses and the wait would be over), when it is asked for twice, or when
			-- a panel that the base made by itself is opened over
			name = "the wait opens the panel once the weapon is inspecting and the base is ready, and only then",
			func = function()
				local M = GryMod.DraconicMenu
				local calls = {}
				local panel = {IsValid = function() return false end}
				local drc = {SV = {}, AttachMenu = {mpanel = panel}, Inspection = {}}

				function drc:ToggleAttachmentMenu(w, b) calls[#calls + 1] = {w, b} end

				local ready = weapon({GetNW2Bool = function(_, key) return key == "Inspecting" end})
				local notYet = weapon({GetNW2Bool = function() return false end})
				local inHand = notYet

				stub(_G, "DRC", drc)
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, GetActiveWeapon = function() return inHand end} end)

				-- the weapon is not inspecting yet: wait
				expect(M.Step(notYet)).to.beFalse()
				inHand = ready
				-- inspecting, but the base has not drawn its screen (no colours): wait
				expect(M.Step(ready)).to.beFalse()
				expect(#calls).to.equal(0)

				drc.Inspection.ThemeColours_Attachments = {}
				expect(M.Step(ready)).to.beTrue()
				expect(#calls).to.equal(1)
				expect(calls[1][1]).to.equal(ready)
				expect(calls[1][2]).to.equal(true)

				-- the panel is up (the base's own message won the race): nothing to do
				panel.IsValid = function() return true end
				expect(M.Step(ready)).to.beTrue()
				expect(#calls).to.equal(1)
			end
		},
		{
			-- fails when the weapon is put away during the wait and the panel is still opened (for another weapon), or when an error of the base reaches the timer
			name = "the wait stops when the weapon is no longer in hand, and an error of the base is caught",
			func = function()
				local M = GryMod.DraconicMenu
				local drc = {SV = {}, AttachMenu = {}, Inspection = {ThemeColours_Attachments = {}}}
				local gone = weapon({GetNW2Bool = function() return true end})
				local other = weapon()

				stub(_G, "DRC", drc)
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, GetActiveWeapon = function() return other end} end)

				local calls = 0

				function drc:ToggleAttachmentMenu() calls = calls + 1 end

				expect(M.Step(gone)).to.beTrue()
				expect(calls).to.equal(0)

				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, GetActiveWeapon = function() return gone end} end)
				function drc:ToggleAttachmentMenu() error("broken base") end

				local ok, done = pcall(M.Step, gone)

				expect(ok).to.beTrue()
				expect(done).to.beTrue()
			end
		},
		{
			-- fails when the weapon stays marked as customizing after the wait gave up (the gun would stay plain, with no menu)
			name = "when the wait gives up without a panel the weapon is no longer marked as customizing",
			func = function()
				local M = GryMod.DraconicMenu
				local w = weapon({Customizing = true})

				stub(_G, "DRC", {SV = {}, AttachMenu = {}, Inspection = {}})
				M.GiveUp(w)
				expect(w.Customizing).to.beFalse()
			end
		}
	}
}
