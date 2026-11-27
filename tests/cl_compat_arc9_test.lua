-- Tests of the ARC9 patches of the weapon base (lua/grymod/compat/weapons/cl_arc9.lua, cl_arc9_parts.lua, cl_arc9_menu.lua), GLuaTest format, client realm. ARC9 draws the
-- attachments of a weapon itself, as client side models kept in the weapon's VModel (one for each installed attachment, and for each duplicate of it), and shows the weapon on a
-- screen of its own (the customization menu: CustomizeDelta goes from 0 to 1 while the gun is turned towards the player over a dark, blurred picture of the world). The cases use a
-- stand-in for the weapon with the fields the patches read and real client side models; the last cases run against a real ARC9 weapon when ARC9 is installed, in the game of the
-- test (the real weapon given to the player and read in the client). Each case names the change whose absence makes it fail.

local API = GryMod.API
local made

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
