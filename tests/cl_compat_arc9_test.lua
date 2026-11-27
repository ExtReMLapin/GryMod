-- Tests of the ARC9 patches of the weapon base (lua/grymod/compat/weapons/cl_arc9.lua, cl_arc9_parts.lua, cl_arc9_menu.lua), GLuaTest format, client realm. ARC9 draws the
-- attachments of a weapon itself, as client side models kept in the weapon's VModel (one for each installed attachment, and for each duplicate of it), and shows the weapon on a
-- screen of its own (the customization menu: CustomizeDelta goes from 0 to 1 while the gun is turned towards the player over a dark, blurred picture of the world). The cases use a
-- stand-in for the weapon with the fields the patches read and real client side models; the last cases run against a real ARC9 weapon when ARC9 is installed, in the game of the
-- test (the real weapon given to the player and read in the client). Each case names the change whose absence makes it fail.

local API = GryMod.API
local made
local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		saved[i][1][saved[i][2]] = saved[i][3]
	end

	saved = {}
end

local function model(fields)
	local ent = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OTHER)

	made[#made + 1] = ent
	ent:SetNoDraw(true)

	for k, v in pairs(fields or {}) do
		ent[k] = v
	end

	return ent
end

-- an ARC9 weapon stand-in
local function arc9(models, fields)
	local w = {ARC9 = true, VModel = models, CustomizeDelta = 0}

	function w:IsValid() return true end
	function w:GetCustomize() return self.customizing == true end

	for k, v in pairs(fields or {}) do
		w[k] = v
	end

	return w
end

local function parts(weapon)
	return API.GetWeaponParts(weapon, {})
end

return {
	groupName = "GryMod compat: ARC9 (client)",
	beforeEach = function()
		made = {}
	end,
	afterEach = function()
		restore()

		pcall(function()
			for _, ent in ipairs(made) do
				if IsValid(ent) then
					ent:Remove()
				end
			end
		end)
	end,
	cases = {
		{
			-- fails when the patch is not registered, or when the attachments in ARC9's VModel are not the weapon's parts, in its order
			name = "the models of the attachments in ARC9's VModel are the weapon's parts, in its order",
			func = function()
				local a, b = model(), model()
				local list, count = parts(arc9({a, b}))

				expect(count).to.equal(2)
				expect(list[1]).to.equal(a)
				expect(list[2]).to.equal(b)
			end
		},
		{
			-- fails when a model ARC9 does not draw is given to the camouflage (an animation proxy, one hidden by a bone, one switched off, the charm that hangs from a model), or when
			-- the charm model ARC9 draws for an attachment (charmmdl) is left plain
			name = "what ARC9 does not draw is not a part (animation proxy, hidden, no draw, charm child), and the charm of an attachment is one",
			func = function()
				local shown, charm = model(), model()
				shown.charmmdl = charm

				local list, count = parts(arc9({
					shown,
					model({IsAnimationProxy = true}),
					model({hidden = true}),
					model({NoDraw = true}),
					model({charmparent = true})
				}))

				expect(count).to.equal(2)
				expect(list[1]).to.equal(shown)
				expect(list[2]).to.equal(charm)
			end
		},
		{
			-- fails when the patch keeps a list: the attachment the player changes during the camouflage must be the next call's list (ARC9 builds a new VModel)
			name = "the parts are read at each call: an attachment put on or taken off is the next list",
			func = function()
				local first, second = model(), model()
				local w = arc9({first})

				expect(select(2, parts(w))).to.equal(1)

				w.VModel = {first, second}
				expect(select(2, parts(w))).to.equal(2)

				w.VModel = {second}

				local list, count = parts(w)

				expect(count).to.equal(1)
				expect(list[1]).to.equal(second)
			end
		},
		{
			-- fails when a weapon that is not ARC9's, or an ARC9 weapon that has no models yet, raises an error or gives parts
			name = "nothing for a weapon that is not ARC9's, nor for an ARC9 weapon that has no list yet; never an error",
			func = function()
				local ent = model()
				local other = {IsValid = function() return true end, VModel = {ent}}

				expect(select(2, parts(other))).to.equal(0)
				expect(select(2, parts(arc9(nil)))).to.equal(0)
				expect(select(2, parts(arc9({})))).to.equal(0)
				expect(select(2, parts(arc9({false, "x"})))).to.equal(0)
			end
		},
		{
			-- fails when the camouflage covers the gun in ARC9's customization menu (the picture it copies is not the one on the screen), when only the first frame of the menu counts, or
			-- when the menu being over is not seen at once
			name = "the customization menu has the view: a plain view from the first frame of the menu to the last of its fading, not before nor after",
			func = function()
				local w = arc9({})

				expect(API.IsPlainView(w)).to.beFalse()

				w.CustomizeDelta = 0.3 -- the menu is coming in
				expect(API.IsPlainView(w)).to.beTrue()

				w.CustomizeDelta = 0
				w.customizing = true -- asked, the delta has not moved yet
				expect(API.IsPlainView(w)).to.beTrue()

				w.customizing = false
				w.CustomizeDelta = 0.2 -- going out
				expect(API.IsPlainView(w)).to.beTrue()

				w.CustomizeDelta = 0
				expect(API.IsPlainView(w)).to.beFalse()
			end
		},
		{
			-- fails when a weapon that is not ARC9's is told to be in a menu, or when an ARC9 weapon without the function raises an error
			name = "no plain view for a weapon that is not ARC9's, nor for an ARC9 weapon that cannot say",
			func = function()
				local other = {IsValid = function() return true end, CustomizeDelta = 1, GetCustomize = function() return true end}

				expect(API.IsPlainView(other)).to.beFalse()
				expect(API.IsPlainView({IsValid = function() return true end, ARC9 = true})).to.beFalse()
			end
		},
		{
			-- fails when the option does not exist, is not saved, is off by default (the owner's HUD would still be crowded) or has no check box on the ARC9 tab of the Compatibility page
			name = "gry_arc9_hide_hud: a saved client setting, on by default, with a check box on the ARC9 tab of the Compatibility page",
			func = function()
				local cvar = GetConVar("gry_arc9_hide_hud")

				expect(cvar ~= nil).to.beTrue()
				expect(cvar:GetDefault()).to.equal("1")
				expect(cvar:GetFlags()).to.equal(GetConVar("gry_binoculars_no_fire"):GetFlags()) -- saved, like the other client settings

				local found = false
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.CompatOptionsPanel(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button and child.Button.m_strConVar == "gry_arc9_hide_hud" then
								found = true
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

				expect(found).to.beTrue()
			end
		},
		{
			-- fails when ARC9's HUD is still asked for with the option on and the HUD of GryMod up (the owner's report: it sits under the minimap), when it is hidden with the option off,
			-- with the HUD of GryMod off, or in ARC9's customization menu (its hints and its menu stay), or when ARC9's own answer is changed in any other case
			name = "ARC9's ShouldDrawHUD answers nothing (its hints stay, its HUD goes) with the option on and GryMod's HUD up, and ARC9's own answer in every other case",
			func = function()
				local weapon = {ARC9 = true, IsValid = function() return true end, customizing = false}

				function weapon:GetCustomize() return self.customizing end
				stub(_G, "ARC9", {ShouldDrawHUD = function() return true end})
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, GetActiveWeapon = function() return weapon end} end)

				local hudUp = true

				stub(GryMod.FlashHUD, "Enabled", function() return hudUp end)
				stub(GryMod.ARC9HUD, "original", GryMod.ARC9HUD.original) -- the real one comes back (the cases put a stand-in of ARC9's function there)
				expect(GryMod.ARC9HUD.Install()).to.beTrue()

				local cvar = GetConVar("gry_arc9_hide_hud")
				local saved = cvar:GetString()
				local ok, err = pcall(function()
					cvar:SetString("1")
					expect(ARC9.ShouldDrawHUD()).to.beNil()

					weapon.customizing = true
					expect(ARC9.ShouldDrawHUD()).to.equal(true)
					weapon.customizing = false

					hudUp = false
					expect(ARC9.ShouldDrawHUD()).to.equal(true)
					hudUp = true

					cvar:SetString("0")
					expect(ARC9.ShouldDrawHUD()).to.equal(true)
				end)

				cvar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when installing twice wraps the wrapper (a hot reload: ARC9's own function would be called twice, and its answer lost when the option is off)
			name = "installing again (a reload) wraps ARC9's own function once: it is asked once, and a file loaded again does not lose it",
			func = function()
				local asked = 0

				stub(_G, "ARC9", {ShouldDrawHUD = function() asked = asked + 1 return "own" end})
				stub(_G, "LocalPlayer", function() return {IsValid = function() return true end, GetActiveWeapon = function() return NULL end} end)
				stub(GryMod.FlashHUD, "Enabled", function() return true end)
				stub(GryMod.ARC9HUD, "original", GryMod.ARC9HUD.original)

				expect(GryMod.ARC9HUD.Install()).to.beTrue()
				expect(GryMod.ARC9HUD.Install()).to.beTrue()

				local cvar = GetConVar("gry_arc9_hide_hud")
				local saved = cvar:GetString()
				local ok, err = pcall(function()
					cvar:SetString("0")
					expect(ARC9.ShouldDrawHUD()).to.equal("own")
					expect(asked).to.equal(1)
				end)

				cvar:SetString(saved)

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails when the patch raises an error or invents ARC9 when it is not installed, or when a version of ARC9 without the function is patched
			name = "nothing to do without ARC9 (no table, or none that has ShouldDrawHUD): Install says false and raises no error",
			func = function()
				stub(_G, "ARC9", nil)
				expect(GryMod.ARC9HUD.Install()).to.beFalse()

				stub(_G, "ARC9", {})
				expect(GryMod.ARC9HUD.Install()).to.beFalse()
				expect(ARC9.ShouldDrawHUD).to.beNil()
			end
		},
		{
			-- fails when a weapon on safety shows the icon of its automatic or burst mode (it cannot fire: the file's own comment says it shows the single shot icon, the code did not do it),
			-- or when the launcher no longer comes first
			name = "fire mode icon: a weapon on safety shows the single shot icon whatever its mode; the launcher under the barrel still shows grenades, and a weapon off safety shows its mode",
			func = function()
				local function gun(mode, safe, launcher)
					return {ARC9 = true, IsValid = function() return true end, GetCurrentFiremode = function() return mode end, GetUBGL = function() return launcher end, GetSafe = function() return safe end}
				end

				local M = GryMod.FlashHUD

				expect(M.FireModeFor(gun(-1, true))).to.equal("Single")
				expect(M.FireModeFor(gun(3, true))).to.equal("Single")
				expect(M.FireModeFor(gun(-1, false))).to.equal("Auto")
				expect(M.FireModeFor(gun(3, false))).to.equal("Burst")
				expect(M.FireModeFor(gun(1, false))).to.equal("Single")
				expect(M.FireModeFor(gun(-1, true, true))).to.equal("Grenade")

				-- a version of ARC9 without GetSafe still reads its mode
				local old = gun(-1, false)

				old.GetSafe = nil
				expect(M.FireModeFor(old)).to.equal("Auto")
			end
		},
		{
			-- fails when a knife (ARC9's PrimaryBash: the weapon only bashes) shows the single shot icon of a gun: the stock crowbar shows NoGun, and the ammunition of a weapon with no
			-- magazine is the infinity icon alone (Clip1 is -1, no bullets, no counter)
			name = "fire mode icon: a weapon that only bashes (a knife) shows no gun, like the crowbar; the processed value is read first (an attachment can change it), then the plain field",
			func = function()
				local M = GryMod.FlashHUD
				local function knife(processed, plain)
					local w = {ARC9 = true, IsValid = function() return true end, PrimaryBash = plain, GetCurrentFiremode = function() return 1 end,
						GetUBGL = function() return false end, GetSafe = function() return false end}

					if processed ~= nil then
						w.GetProcessedValue = function(_, name) return name == "PrimaryBash" and processed or nil end
					end

					return w
				end

				expect(M.FireModeFor(knife(true, false))).to.equal("NoGun")
				expect(M.FireModeFor(knife(nil, true))).to.equal("NoGun")
				expect(M.FireModeFor(knife(false, true))).to.equal("Single") -- the processed value wins: an attachment turned the bash off
				expect(M.FireModeFor(knife(nil, false))).to.equal("Single")
			end
		},
		{
			-- fails when a throwable (ARC9's Throwable: a grenade, a flare, a claymore) shows the single shot icon of a gun: it has no fire mode, the grenade icon is what the movie has
			name = "fire mode icon: a throwable weapon shows the grenade icon, not a gun's single shot; a gun with Throwable false keeps its mode",
			func = function()
				local M = GryMod.FlashHUD
				local function nade(throwable)
					return {ARC9 = true, IsValid = function() return true end, Throwable = throwable, GetCurrentFiremode = function() return 1 end,
						GetUBGL = function() return false end, GetSafe = function() return false end}
				end

				expect(M.FireModeFor(nade(true))).to.equal("Grenade")
				expect(M.FireModeFor(nade(false))).to.equal("Single")
				expect(M.FireModeFor(nade(nil))).to.equal("Single")
			end
		},
		{
			-- fails when the patch does not work with the real ARC9 base (a name or a field that is not what the patch reads): the real weapon the test player holds is asked
			name = "a real ARC9 weapon (when ARC9 is installed and the test player holds one): its parts are read without an error and are the models of its VModel",
			func = function()
				if not weapons.GetStored("arc9_base") then
					return -- ARC9 is not installed here: nothing to check
				end

				local wep = LocalPlayer():GetActiveWeapon()

				if not IsValid(wep) or wep.ARC9 ~= true then
					return -- the player holds no ARC9 weapon: nothing to check
				end

				local ok, count = pcall(function()
					return select(2, parts(wep))
				end)

				expect(ok).to.beTrue()

				local drawn = 0

				for _, m in ipairs(wep.VModel or {}) do
					if IsValid(m) and not m.IsAnimationProxy and not m.hidden and not m.NoDraw and not m.charmparent then
						drawn = drawn + 1
					end
				end

				expect(count >= drawn).to.beTrue()
				expect(API.IsPlainView(wep)).to.beFalse()
			end
		}
	}
}
