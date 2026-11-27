-- Tests of the weapon selector setting (GryMod.WeaponSelector, lua/grymod/client/cl_weapon_selector.lua), GLuaTest format, client realm.
-- The setting gry_weapon_selector has three positions: 0 the game's own selector (the default, nothing changes), 1 "wheel only" (a notch of the
-- wheel changes the weapon at once), 2 "wheel then click" (the wheel walks a list at the bottom right, the HUD's own weapon list, and the left click
-- confirms). Every position must go with the camouflage: a click that confirms is never a shot. Fake players and weapons, the clock and the
-- engine's weapon change are stubs, everything is put back in afterEach inside a pcall.

local saved = {}
local selected
local shown
local showResult
local clock
local sent
local savedMode
local savedGuard

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

local function setMode(value)
	GetConVar("gry_weapon_selector"):SetString(tostring(value))
end

-- the weapons of the player in the order the engine walks them: slot, then position in the slot
local function fakeWeapons(defs)
	local list = {}

	for _, def in ipairs(defs or {{"weapon_crowbar", 0, 0}, {"weapon_pistol", 1, 0}, {"weapon_smg1", 2, 0}, {"weapon_ar2", 2, 1}, {"weapon_shotgun", 3, 0}}) do
		local weapon = {class = def[1], slot = def[2], pos = def[3], ammo = def[4] ~= false}

		function weapon:IsValid() return true end
		function weapon:GetClass() return self.class end
		function weapon:GetSlot() return self.slot end
		function weapon:GetSlotPos() return self.pos end
		function weapon:HasAmmo() return self.ammo end
		function weapon:Clip1() return 30 end
		function weapon:GetPrimaryAmmoType() return 1 end
		function weapon:GetSecondaryAmmoType() return 2 end
		function weapon:GetNextPrimaryFire() return CurTime() - 1 end
		function weapon:GetNextSecondaryFire() return CurTime() - 1 end

		list[#list + 1] = weapon
	end

	return list
end

local function fakePlayer(mode, activeClass, defs)
	local ply = {NanosuitMode = mode, modeSet = {}, alive = true, inVehicle = false, attackHeld = false}
	ply.weapons = fakeWeapons(defs)

	for _, weapon in ipairs(ply.weapons) do
		if weapon.class == activeClass then
			ply.active = weapon
		end
	end

	function ply:IsValid() return true end
	function ply:Alive() return self.alive end
	function ply:InVehicle() return self.inVehicle end
	function ply:GetWeapons() return self.weapons end
	function ply:GetActiveWeapon() return self.active end
	function ply:KeyDown(key) return key == IN_ATTACK and self.attackHeld end
	function ply:GetAmmoCount() return 100 end
	function ply:SetNanosuitMode(newMode, networked)
		self.modeSet[#self.modeSet + 1] = {newMode, networked}
		self.NanosuitMode = newMode
	end

	GryMod.CloakSnapshot(ply)

	return ply
end

local function weaponNamed(ply, class)
	for _, weapon in ipairs(ply.weapons) do
		if weapon.class == class then
			return weapon
		end
	end
end

-- what the game does with a bind: the hooks of PlayerBindPress in turn, the first one that answers stops the others. The order of the hooks of an
-- addon cannot be chosen, so the two orders of the selector and of the camouflage guard are both tried.
local function press(ply, bind, pressed, selectorFirst)
	local code = bind == "+attack" and 107 or 113
	local first, second = GryMod.WeaponSelector.BindPress, GryMod.CloakSelectorBind

	if selectorFirst == false then
		first, second = second, first
	end

	local taken = first(ply, bind, pressed ~= false, code)

	if taken ~= nil then
		return taken
	end

	return second(ply, bind, pressed ~= false, code)
end

local function inWindow()
	local List = GryMod.FlashWeaponList

	return List.HOLD + List.FADE_FRAMES / 30 + 0.2
end

return {
	groupName = "GryMod weapon selector setting (wheel only, wheel then click)",
	beforeAll = function()
		local convar = GetConVar("gry_weapon_selector")

		savedMode = convar and convar:GetString()
		savedGuard = GetConVar("gry_cloak_selector_guard") and GetConVar("gry_cloak_selector_guard"):GetString()
	end,
	beforeEach = function()
		selected, shown, sent, clock, showResult = {}, {}, {}, 100, true

		local ok, err = pcall(function()
			stub(net, "Start", function(name) sent[#sent + 1] = name end)
			stub(net, "SendToServer", function() end)
			stub(timer, "Simple", function() end)
			stub(_G, "CurTime", function() return clock end)
			stub(input, "SelectWeapon", function(weapon) selected[#selected + 1] = weapon end)
			stub(GryMod.FlashWeaponList, "Show", function(ply, weapon)
				shown[#shown + 1] = weapon

				return showResult
			end)
			stub(GryMod.FlashWeaponList, "Clear", function() end)

			GryMod.SelectorState.Reset(GryMod.CloakSelectorState)
			GryMod.WeaponSelector.Reset()
			GetConVar("gry_cloak_selector_guard"):SetString("1")
			setMode(0)
		end)

		if not ok then
			restore()
			error(err, 0)
		end
	end,
	afterEach = function()
		pcall(restore)
		pcall(function() GryMod.SelectorState.Reset(GryMod.CloakSelectorState) end)
		pcall(function() GryMod.WeaponSelector.Reset() end)
		pcall(function()
			if savedMode then
				GetConVar("gry_weapon_selector"):SetString(savedMode)
			end
		end)
		pcall(function()
			if savedGuard then
				GetConVar("gry_cloak_selector_guard"):SetString(savedGuard)
			end
		end)
	end,
	cases = {
		{
			-- fails if: the setting does not exist, is not saved, or does not start at 0 (a player who never opens the menu must see no change)
			name = "the setting gry_weapon_selector exists, is saved with the player's settings, and is 0 by default",
			func = function()
				local convar = GetConVar("gry_weapon_selector")

				expect(convar).to.exist()
				expect(convar:GetDefault()).to.equal("0")
				-- (this game's flags of an archived client setting are not FCVAR_ARCHIVE alone: the reference is a setting that is saved, the guard's)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_cloak_selector_guard"):GetFlags())
			end
		},
		{
			-- fails if: the setting is read as a plain boolean, or a value outside 0..2 is not brought back to the range
			name = "the position is the setting's value, kept between 0 and 2",
			func = function()
				setMode(0)
				expect(GryMod.WeaponSelector.Mode()).to.equal(0)
				setMode(1)
				expect(GryMod.WeaponSelector.Mode()).to.equal(1)
				setMode(2)
				expect(GryMod.WeaponSelector.Mode()).to.equal(2)
				setMode(7)
				expect(GryMod.WeaponSelector.Mode()).to.equal(2)
				setMode(-3)
				expect(GryMod.WeaponSelector.Mode()).to.equal(0)
			end
		},
		{
			-- fails if: the selector takes a bind, selects, shows the list or hides the cloak guard's window with the setting at 0 (the default must change nothing)
			name = "position 0 changes nothing: no bind is taken, no weapon is selected, no list is shown, and the camouflage guard sees the notches as before",
			func = function()
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				for _, order in ipairs({true, false}) do
					GryMod.SelectorState.Reset(GryMod.CloakSelectorState)
					expect(press(ply, "invnext", true, order)).to.beNil()
					expect(press(ply, "invprev", true, order)).to.beNil()
					expect(GryMod.SelectorState.Phase(GryMod.CloakSelectorState, clock)).to.equal("open") -- the guard followed the notch
					expect(press(ply, "+attack", true, order)).to.beNil() -- the engine's own confirmation goes on
				end

				expect(#selected).to.equal(0)
				expect(#shown).to.equal(0)
				expect(#ply.modeSet).to.equal(0)
			end
		},
		{
			-- fails if: a notch does not change the weapon at once, or goes the wrong way (the wheel down, invnext, is the next weapon)
			name = "position 1: a notch down selects the next weapon at once and a notch up the previous one, and the notch is taken",
			func = function()
				setMode(1)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				expect(press(ply, "invnext", true)).to.beTrue()
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_ar2"))

				clock = clock + 1 -- the weapon in hand is the one that counts again
				expect(press(ply, "invprev", true)).to.beTrue()
				expect(selected[2]).to.equal(weaponNamed(ply, "weapon_pistol"))
				expect(#shown).to.equal(0) -- no selection list of ours: the HUD shows its own list when the weapon changes
			end
		},
		{
			-- fails if: the list does not wrap, or a weapon with no ammo is stopped on (as the game's selector does not)
			name = "position 1: the walk wraps round the ends and skips a weapon that cannot be selected",
			func = function()
				setMode(1)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_shotgun")
				press(ply, "invnext", true)
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_crowbar"))

				clock = clock + 1
				ply.active = weaponNamed(ply, "weapon_crowbar")
				weaponNamed(ply, "weapon_pistol").ammo = false
				press(ply, "invnext", true)
				expect(selected[2]).to.equal(weaponNamed(ply, "weapon_smg1"))

				clock = clock + 1
				ply.active = weaponNamed(ply, "weapon_crowbar")
				press(ply, "invprev", true)
				expect(selected[3]).to.equal(weaponNamed(ply, "weapon_shotgun"))
			end
		},
		{
			-- fails if: the next notch starts again from the weapon in hand (which has not changed yet: the change reaches the player a moment later)
			name = "position 1: notches that come faster than the weapon changes go on from the weapon asked for, not from the one still in hand",
			func = function()
				setMode(1)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_crowbar")
				press(ply, "invnext", true)
				clock = clock + 0.05
				press(ply, "invnext", true)
				clock = clock + 0.05
				press(ply, "invnext", true)

				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_pistol"))
				expect(selected[2]).to.equal(weaponNamed(ply, "weapon_smg1"))
				expect(selected[3]).to.equal(weaponNamed(ply, "weapon_ar2"))

				-- a long time after, the weapon in hand is the base again
				clock = clock + 5
				ply.active = weaponNamed(ply, "weapon_crowbar")
				press(ply, "invnext", true)
				expect(selected[4]).to.equal(weaponNamed(ply, "weapon_pistol"))
			end
		},
		{
			-- fails if: the notch feeds the camouflage guard (the engine's selector is not up in this position, the guard would take a real shot for a confirmation)
			name = "position 1 and the camouflage: a click after a notch is a shot (the engine's selector is not open), and it ends the camouflage",
			func = function()
				setMode(1)

				for _, order in ipairs({true, false}) do
					local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")
					GryMod.SelectorState.Reset(GryMod.CloakSelectorState)

					press(ply, "invnext", true, order)
					expect(GryMod.SelectorState.Phase(GryMod.CloakSelectorState, clock)).to.equal("none")
					clock = clock + 0.4
					expect(press(ply, "+attack", true, order)).to.beNil()
					GryMod.CloackAttack(ply, IN_ATTACK)
					expect(#ply.modeSet).to.equal(1)
					clock = clock + 5
				end
			end
		},
		{
			-- fails if: the wheel is taken from the physgun (it moves the held prop with the wheel while the attack key is down), from a driver, a dead player or one with no weapon
			name = "positions 1 and 2 leave the wheel to the game when the attack key is down (the physgun), in a vehicle, when dead, and with no weapon in hand",
			func = function()
				for _, position in ipairs({1, 2}) do
					setMode(position)

					local held = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
					held.attackHeld = true
					expect(press(held, "invnext", true)).to.beNil()

					local driver = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
					driver.inVehicle = true
					expect(press(driver, "invnext", true)).to.beNil()

					local dead = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
					dead.alive = false
					expect(press(dead, "invnext", true)).to.beNil()

					local bare = fakePlayer(GryMod.Modes.ARMOR, nil)
					expect(press(bare, "invnext", true)).to.beNil()
				end

				expect(#selected).to.equal(0)
				expect(#shown).to.equal(0)
			end
		},
		{
			-- fails if: the selector takes the wheel while the binoculars' or the suit's zoom use it for their stages
			name = "positions 1 and 2 leave the wheel to the zoom while it is up",
			func = function()
				stub(GryMod.SuitZoom, "IsActive", function() return true end)

				for _, position in ipairs({1, 2}) do
					setMode(position)

					local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
					expect(press(ply, "invnext", true)).to.beNil()
				end

				expect(#selected).to.equal(0)
				expect(#shown).to.equal(0)
			end
		},
		{
			-- fails if: the release of the wheel counts as a notch, or the selector takes other binds
			name = "a release, the right click and other binds are never taken, in either position",
			func = function()
				for _, position in ipairs({1, 2}) do
					setMode(position)

					local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
					expect(press(ply, "invnext", false)).to.beNil()
					expect(press(ply, "+attack2", true)).to.beNil()
					expect(press(ply, "+jump", true)).to.beNil()
					expect(press(ply, "-attack", false)).to.beNil()
				end

				expect(#selected).to.equal(0)
				expect(#shown).to.equal(0)
			end
		},
		{
			-- fails if: the wheel changes the weapon at once in position 2 (the click is the confirmation), or the list is not asked to show the weapon the wheel is on
			name = "position 2: a notch moves a selection on the HUD's weapon list and changes nothing yet; the notch is taken",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				expect(press(ply, "invnext", true)).to.beTrue()
				expect(shown[1]).to.equal(weaponNamed(ply, "weapon_ar2"))
				expect(#selected).to.equal(0)

				clock = clock + 0.3
				expect(press(ply, "invnext", true)).to.beTrue()
				expect(shown[2]).to.equal(weaponNamed(ply, "weapon_shotgun")) -- from the selection, the weapon in hand has not moved
				clock = clock + 0.3
				expect(press(ply, "invprev", true)).to.beTrue()
				expect(shown[3]).to.equal(weaponNamed(ply, "weapon_ar2"))
				expect(#selected).to.equal(0)
			end
		},
		{
			-- fails if: the click does not select what the list shows, or lets the weapon fire
			name = "position 2: the left click confirms the selection (that weapon is selected, the click is taken so the weapon in hand does not fire)",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				press(ply, "invnext", true)
				clock = clock + 0.3
				press(ply, "invnext", true)
				clock = clock + 2
				expect(press(ply, "+attack", true)).to.beTrue()
				expect(#selected).to.equal(1)
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_shotgun"))

				-- used up: the next click is an ordinary one
				expect(press(ply, "+attack", true)).to.beNil()
				expect(#selected).to.equal(1)
			end
		},
		{
			-- fails if: a click with no selection under way is taken (the weapon could never fire again)
			name = "position 2: a click with no selection is a plain click, and is not taken",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				expect(press(ply, "+attack", true)).to.beNil()
				expect(#selected).to.equal(0)
			end
		},
		{
			-- fails if: the selection stays valid after the list is gone (a click long after would be eaten without any list on the screen)
			name = "position 2: the selection lasts as long as the list is on the screen (3 s and its fade); after that a click is a plain click",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				press(ply, "invnext", true)
				clock = clock + inWindow() - 0.05
				expect(press(ply, "+attack", true)).to.beTrue() -- the list is still there

				press(ply, "invnext", true)
				clock = clock + inWindow() + 0.05
				expect(press(ply, "+attack", true)).to.beNil() -- gone
				expect(#selected).to.equal(1)

				-- a notch after the list went starts again from the weapon in hand
				press(ply, "invnext", true)
				expect(shown[#shown]).to.equal(weaponNamed(ply, "weapon_ar2"))
			end
		},
		{
			-- fails if: the selection survives a weapon key or the last weapon key (the engine's selector, opened by them, is the one that takes the click)
			name = "position 2: a weapon key or the last weapon key ends the selection (the click then goes to the game)",
			func = function()
				setMode(2)

				for _, key in ipairs({"slot2", "lastinv"}) do
					local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

					press(ply, "invnext", true)
					press(ply, key, true)
					clock = clock + 0.3
					expect(press(ply, "+attack", true)).to.beNil()
					clock = clock + 10
				end

				expect(#selected).to.equal(0)
			end
		},
		{
			-- fails if: the confirmation is lost when the selection came back to the weapon in hand (a full turn): the click must still be eaten, as the engine eats it
			name = "position 2: a click on the weapon already in hand is taken, selects nothing, and fires nothing",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				press(ply, "invnext", true)
				clock = clock + 0.2
				press(ply, "invprev", true)
				clock = clock + 0.2
				expect(press(ply, "+attack", true)).to.beTrue()
				expect(#selected).to.equal(0)
			end
		},
		{
			-- fails if: a weapon that was taken away during the selection is selected (the player lost it, or died: a new life has other weapons)
			name = "position 2: a weapon the player no longer has is not selected, and the click is not taken",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				press(ply, "invnext", true)
				table.RemoveByValue(ply.weapons, weaponNamed(ply, "weapon_ar2"))
				clock = clock + 0.3
				expect(press(ply, "+attack", true)).to.beNil()
				expect(#selected).to.equal(0)
			end
		},
		{
			-- fails if: with the HUD list off (the HUD is off, or the list is turned off, or its movie is missing) the wheel is taken and nothing shows: the player would scroll blind
			name = "position 2 with no list to show (the HUD's list is off or not available): the wheel changes the weapon at once, as in position 1",
			func = function()
				setMode(2)
				showResult = false

				local ply = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")

				expect(press(ply, "invnext", true)).to.beTrue()
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_ar2"))

				-- and no selection stays under way: the click is a plain click
				clock = clock + 0.3
				expect(press(ply, "+attack", true)).to.beNil()
			end
		},
		{
			-- fails if: the confirming click ends the camouflage, in either order of the two hooks, with the guard option on or off
			name = "position 2 and the camouflage: the confirming click does not end it, even if the press reaches KeyPress, and the confirmation is used up once",
			func = function()
				setMode(2)

				for _, guard in ipairs({"1", "0"}) do
					GetConVar("gry_cloak_selector_guard"):SetString(guard)

					for _, order in ipairs({true, false}) do
						local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")
						GryMod.SelectorState.Reset(GryMod.CloakSelectorState)
						sent = {}

						press(ply, "invnext", true, order)
						expect(GryMod.SelectorState.Phase(GryMod.CloakSelectorState, clock)).to.equal("none") -- the engine's selector is not the one that is up
						clock = clock + 0.5
						expect(press(ply, "+attack", true, order)).to.beTrue()
						GryMod.CloackAttack(ply, IN_ATTACK) -- the press may still come to KeyPress
						expect(#ply.modeSet).to.equal(0)
						expect(#sent).to.equal(0)

						clock = clock + 0.1
						GryMod.CloackAttack(ply, IN_ATTACK) -- the next one is a shot
						expect(#ply.modeSet).to.equal(1)
						clock = clock + 5
					end
				end
			end
		},
		{
			-- fails if: a plain click after the selection window is eaten or is not judged as a shot in the camouflage
			name = "position 2 and the camouflage: a click after the list is gone is a real shot and ends the camouflage",
			func = function()
				setMode(2)

				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				press(ply, "invnext", true)
				clock = clock + inWindow() + 0.5
				expect(press(ply, "+attack", true)).to.beNil()
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(1)
				expect(sent[#sent]).to.equal("gry_empty_energy")
			end
		},
		{
			-- fails if: the selector adds a hook that runs at every frame (the addon's rule: no permanent Think), or is not on the bind hook
			name = "the selector is a PlayerBindPress hook and adds no hook that runs at every frame",
			func = function()
				local tables = hook.GetTable()

				expect(tables.PlayerBindPress["GryWeaponSelector"]).to.exist()

				for _, event in ipairs({"Think", "Tick", "HUDPaint", "PostDrawHUD", "CreateMove", "StartCommand", "PreRender", "PostRender"}) do
					for id in pairs(tables[event] or {}) do
						expect(string.find(tostring(id), "GryWeaponSelector", 1, true)).to.beNil()
					end
				end
			end
		},
		{
			-- fails if: the setting has no line in the options menu, or a line that does not write the setting
			name = "the setting is in the options menu as a choice of three lines that write gry_weapon_selector",
			func = function()
				local combo
				local panel = vgui.Create("ControlPanel")
				local writes = {}
				local realRun = RunConsoleCommand
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DComboBox" and child.GryConVar == "gry_weapon_selector" then
								combo = child
							end

							walk(child)
						end
					end

					walk(panel)

					expect(combo).to.exist()
					expect(combo:GetOptionText(1)).to.exist()
					expect(combo:GetOptionText(3)).to.exist()
					expect(combo:GetOptionText(4)).to.beNil()

					RunConsoleCommand = function(name, value) writes[#writes + 1] = tostring(name) .. "=" .. tostring(value) end
					combo.OnSelect(combo, 2, combo:GetOptionText(2), combo:GetOptionData(2))
				end)

				RunConsoleCommand = realRun
				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(writes[1]).to.equal("gry_weapon_selector=1")
			end
		}
	}
}
