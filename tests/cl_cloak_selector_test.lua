-- Tests of the weapon selector guard of the camouflage (GryMod.SelectorState, GryMod.CloakSelectorBind, cl_hud.lua), GLuaTest
-- format, client realm. Measured with real wheel and click events on a test client: the Half-Life 2 selector eats the click that
-- confirms a selection (no KeyPress, the weapon changes), but it closes by itself 1.2 s after the last notch; a click after that
-- is no confirmation any more, it fires the weapon in hand (magazine down, next fire time moved) and ended the camouflage. Fake
-- players and weapons, the network is a recorder, the clock is stubbed.

local saved = {}

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

local sent
local selected
local clock
local savedConVar

-- the weapons of the player, in the order the engine's selector walks them: slot, then position in the slot
local function fakeWeapons(ply)
	local list = {}

	for _, def in ipairs({{"weapon_crowbar", 0, 0}, {"weapon_pistol", 1, 0}, {"weapon_smg1", 2, 0}, {"weapon_ar2", 2, 1}, {"weapon_shotgun", 3, 0}}) do
		local weapon = {class = def[1], slot = def[2], pos = def[3], ammo = true}

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

local function fakePlayer(mode, activeClass)
	local ply = {NanosuitMode = mode, modeSet = {}}
	ply.weapons = fakeWeapons(ply)

	for _, weapon in ipairs(ply.weapons) do
		if weapon.class == activeClass then
			ply.active = weapon
		end
	end

	function ply:GetWeapons() return self.weapons end
	function ply:GetActiveWeapon() return self.active end
	function ply:KeyDown() return false end
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

local function entries(list)
	local out = {}

	for _, def in ipairs(list) do
		out[#out + 1] = {id = def[1], slot = def[2], pos = def[3], selectable = def[4] ~= false}
	end

	return out
end

return {
	groupName = "GryMod camouflage and the weapon selector",
	beforeAll = function(state)
		savedConVar = GetConVar("gry_cloak_selector_guard") and GetConVar("gry_cloak_selector_guard"):GetString()
	end,
	beforeEach = function(state)
		sent = {}
		selected = {}
		clock = 100

		local ok, err = pcall(function()
			stub(net, "Start", function(name) sent[#sent + 1] = name end)
			stub(net, "SendToServer", function() end)
			stub(timer, "Simple", function() end)
			stub(_G, "CurTime", function() return clock end)
			stub(input, "SelectWeapon", function(weapon) selected[#selected + 1] = weapon end)

			GryMod.SelectorState.Reset(GryMod.CloakSelectorState)

			local convar = GetConVar("gry_cloak_selector_guard")

			if convar then
				convar:SetString("1")
			end
		end)

		if not ok then
			restore()
			error(err, 0)
		end
	end,
	afterEach = function(state)
		pcall(restore)
		pcall(function() GryMod.SelectorState.Reset(GryMod.CloakSelectorState) end)
		pcall(function()
			if savedConVar then
				GetConVar("gry_cloak_selector_guard"):SetString(savedConVar)
			end
		end)
	end,
	cases = {
		{
			name = "a notch opens a window of 1.2 s (the engine's own timeout, measured), then a grace window of half a second, then nothing",
			func = function(state)
				local Sel = GryMod.SelectorState
				local s = Sel.New()
				expect(Sel.Phase(s, 10)).to.equal("none")

				Sel.Notch(s, 10, "next")
				expect(Sel.Phase(s, 10)).to.equal("open")
				expect(Sel.Phase(s, 11.19)).to.equal("open")
				expect(Sel.Phase(s, 11.21)).to.equal("late")
				expect(Sel.Phase(s, 11.69)).to.equal("late")
				expect(Sel.Phase(s, 11.71)).to.equal("none")
				expect(Sel.Phase(s, 9)).to.equal("none") -- the clock went back (a map change)
			end
		},
		{
			name = "every notch restarts the window from its own time",
			func = function(state)
				local Sel = GryMod.SelectorState
				local s = Sel.New()
				Sel.Notch(s, 10, "next")
				Sel.Notch(s, 11, "next")
				expect(Sel.Phase(s, 12.1)).to.equal("open")
				expect(Sel.Phase(s, 12.3)).to.equal("late")
			end
		},
		{
			name = "an attack press: confirmation in the window, late click in the grace window, a plain shot otherwise; each closes the selector",
			func = function(state)
				local Sel = GryMod.SelectorState
				local s = Sel.New()

				Sel.Notch(s, 10, "next")
				expect((Sel.Attack(s, 10.5))).to.equal("confirm")
				expect((Sel.Attack(s, 10.6))).to.equal("shot")

				Sel.Notch(s, 20, "next")
				local verdict, steps = Sel.Attack(s, 21.5)
				expect(verdict).to.equal("late")
				expect(steps).to.equal(1)
				expect((Sel.Attack(s, 21.6))).to.equal("shot")

				Sel.Notch(s, 30, "prev")
				expect((Sel.Attack(s, 32))).to.equal("shot")
			end
		},
		{
			name = "the notches count the steps of the selection (next adds, prev subtracts); a notch after the window starts a new selection",
			func = function(state)
				local Sel = GryMod.SelectorState
				local s = Sel.New()
				Sel.Notch(s, 10, "next")
				Sel.Notch(s, 10.2, "next")
				Sel.Notch(s, 10.4, "prev")
				Sel.Notch(s, 10.6, "next")
				local _, steps = Sel.Attack(s, 11)
				expect(steps).to.equal(2)

				Sel.Notch(s, 20, "next")
				Sel.Notch(s, 22, "next") -- the window of the first one is over: a new selection
				local _, steps2 = Sel.Attack(s, 23.5)
				expect(steps2).to.equal(1)
			end
		},
		{
			name = "a weapon key opens the window but its target is unknown (the steps are nil); the last weapon key closes it",
			func = function(state)
				local Sel = GryMod.SelectorState
				local s = Sel.New()
				Sel.Notch(s, 10, "slot")
				local verdict, steps = Sel.Attack(s, 11.5)
				expect(verdict).to.equal("late")
				expect(steps).to.beNil()

				Sel.Notch(s, 20, "next")
				Sel.Reset(s)
				expect((Sel.Attack(s, 21.5))).to.equal("shot")
			end
		},
		{
			name = "the bind kinds: the wheel, the weapon keys, the last weapon, the attack",
			func = function(state)
				local kind = GryMod.SelectorState.BindKind
				expect(kind("invnext")).to.equal("next")
				expect(kind("invprev")).to.equal("prev")
				expect(kind("slot1")).to.equal("slot")
				expect(kind("slot6")).to.equal("slot")
				expect(kind("lastinv")).to.equal("close")
				expect(kind("+attack")).to.equal("attack")
				expect(kind("+attack2")).to.beNil()
				expect(kind("-attack")).to.beNil()
				expect(kind("+jump")).to.beNil()
				expect(kind(nil)).to.beNil()
			end
		},
		{
			name = "the target of the selection: the weapons by slot then position, wrapping round, the ones without ammo skipped",
			func = function(state)
				local target = GryMod.SelectorState.Target
				local list = entries({{"crowbar", 0, 0}, {"pistol", 1, 0}, {"smg", 2, 0}, {"ar2", 2, 1}, {"shotgun", 3, 0}})

				expect(target(list, "smg", 1)).to.equal("ar2")
				expect(target(list, "smg", 2)).to.equal("shotgun")
				expect(target(list, "shotgun", 1)).to.equal("crowbar") -- the engine wraps (measured: frag -> crowbar)
				expect(target(list, "crowbar", -1)).to.equal("shotgun")
				expect(target(list, "pistol", 5)).to.equal("pistol")
				expect(target(list, "smg", 0)).to.equal("smg")
				expect(target(list, "smg", nil)).to.beNil()
				expect(target(list, "unknown", 1)).to.beNil()

				-- no ammo, not selectable (the weapon in hand always counts)
				local dry = entries({{"crowbar", 0, 0}, {"pistol", 1, 0, false}, {"smg", 2, 0}})
				expect(target(dry, "crowbar", 1)).to.equal("smg")
				local dryHand = entries({{"crowbar", 0, 0}, {"pistol", 1, 0, false}, {"smg", 2, 0}})
				expect(target(dryHand, "pistol", 1)).to.equal("smg")
			end
		},
		{
			name = "the measured sequence: a notch, then a click 1.4 s later (the selector closed) does not end the camouflage, and the selected weapon comes",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				expect(GryMod.CloakSelectorBind(ply, "invnext", true, 113)).to.beNil()
				clock = clock + 1.4
				local taken = GryMod.CloakSelectorBind(ply, "+attack", true, 107)

				expect(taken).to.beTrue() -- the click is taken: the weapon does not fire
				expect(#ply.modeSet).to.equal(0)
				expect(#sent).to.equal(0)
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_ar2"))
			end
		},
		{
			name = "three notches then a late click select the weapon three steps on",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_pistol")

				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 0.2
				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 0.2
				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beTrue()
				expect(selected[1]).to.equal(weaponNamed(ply, "weapon_shotgun"))
			end
		},
		{
			name = "a late click after a weapon key is taken too, with no weapon to select (its target is unknown)",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				GryMod.CloakSelectorBind(ply, "slot3", true, 4)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beTrue()
				expect(#selected).to.equal(0)
				expect(#ply.modeSet).to.equal(0)
			end
		},
		{
			name = "a click inside the window is the engine's confirmation: it goes on, and nothing is selected by us",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 0.5
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beNil()
				expect(#selected).to.equal(0)
				expect(#ply.modeSet).to.equal(0)
			end
		},
		{
			name = "a click long after the selector (past the grace window), or with no notch at all, is a real shot: not taken, and it ends the camouflage",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 2
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beNil()
				GryMod.CloackAttack(ply, IN_ATTACK)
				expect(#ply.modeSet).to.equal(1)
				expect(ply.modeSet[1][1]).to.equal(GryMod.Modes.ARMOR)

				local ply2 = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")
				expect(GryMod.CloakSelectorBind(ply2, "+attack", true, 107)).to.beNil()
				GryMod.CloackAttack(ply2, IN_ATTACK)
				expect(#ply2.modeSet).to.equal(1)
				expect(sent[#sent]).to.equal("gry_empty_energy")
			end
		},
		{
			name = "the late click is only taken in the camouflage, and only with the option on",
			func = function(state)
				local armor = fakePlayer(GryMod.Modes.ARMOR, "weapon_smg1")
				GryMod.CloakSelectorBind(armor, "invnext", true, 113)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(armor, "+attack", true, 107)).to.beNil()
				expect(#selected).to.equal(0)

				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")
				GetConVar("gry_cloak_selector_guard"):SetString("0")
				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beNil()
				expect(#selected).to.equal(0)
			end
		},
		{
			name = "the release of the attack key, the right click and other binds are never taken",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")
				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(ply, "-attack", false, 107)).to.beNil()
				expect(GryMod.CloakSelectorBind(ply, "+attack2", true, 108)).to.beNil()
				expect(GryMod.CloakSelectorBind(ply, "+jump", true, 65)).to.beNil()
				expect(GryMod.CloakSelectorBind(ply, "invnext", false, 113)).to.beNil() -- a release is no notch
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beTrue() -- the late click is still there
			end
		},
		{
			name = "a notch the zoom took (the wheel is the zoom's while it is up) opens no window",
			func = function(state)
				local ply = fakePlayer(GryMod.Modes.CLOAK, "weapon_smg1")

				stub(GryMod.SuitZoom, "IsActive", function() return true end)
				GryMod.CloakSelectorBind(ply, "invnext", true, 113)
				clock = clock + 1.4
				expect(GryMod.CloakSelectorBind(ply, "+attack", true, 107)).to.beNil()
				expect(#selected).to.equal(0)
			end
		},
		{
			name = "the option is in the options panel",
			func = function(state)
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

				expect(found["gry_cloak_selector_guard"]).to.beTrue()
			end
		}
	}
}
