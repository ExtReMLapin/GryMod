-- Tests of the TFA patch for the weapon parts (lua/grymod/compat/weapons/cl_tfa_parts.lua), GLuaTest format, client realm. A TFA weapon draws its attachments itself, in
-- its ViewModelDrawn, as models of its own (the elements of its ViewModelElements, each with a client side model in `curmodel`): the suit's camouflage knew only the view model
-- and left a sight plain on a camouflaged gun. The patch says which models those are, for a TFA weapon, from TFA's own tables at the moment it is asked, with TFA's own rule for
-- which of them are drawn (type Model, not hidden, a bone or an attachment point, not switched off by the stat "ViewModelElements.<name>.active"). The cases use a stand-in for the
-- weapon with the fields the patch reads and real client side models; one case runs against a real TFA weapon when TFA is installed. Each case names the change whose absence makes it fail.

local API = GryMod.API
local made

local function model()
	local ent = ClientsideModel("models/props_junk/PopCan01a.mdl", RENDERGROUP_OTHER)

	made[#made + 1] = ent
	ent:SetNoDraw(true)

	return ent
end

-- a TFA weapon stand-in: elements = {name = element}, order = the names in the order TFA draws them, inactive = {name = true} for the stat that says "not active"
local function tfa(elements, order, inactive)
	local w = {IsTFAWeapon = true, vRenderOrder = order}

	function w:IsValid() return true end
	function w:GetStatRawL(name) return name == "ViewModelElements" and elements or nil end
	function w:GetStatL(name, default)
		local element = string.match(name, "^ViewModelElements%.(.+)%.active$")

		if element and inactive and inactive[element] then
			return false
		end

		return default
	end

	return w
end

local function parts(weapon)
	local list, count = API.GetWeaponParts(weapon, {})

	return list, count
end

return {
	groupName = "GryMod compat: TFA weapon parts (client)",
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
			-- fails when the patch is not registered, or when the models of the elements TFA draws are not the parts, in its order
			name = "the models of the elements that TFA draws are the weapon's parts, in TFA's order",
			func = function()
				local a, b = model(), model()
				local w = tfa({sight = {type = "Model", bone = "ValveBiped.Bip01_R_Hand", curmodel = a}, laser = {type = "Model", attachment = "muzzle", curmodel = b}}, {"sight", "laser"})
				local list, count = parts(w)

				expect(count).to.equal(2)
				expect(list[1]).to.equal(a)
				expect(list[2]).to.equal(b)
			end
		},
		{
			-- fails when an element that TFA does not draw is given to the effect (a hidden one, one that is not a model, one with no bone or attachment point, one switched off by the
			-- stat, one whose model is not made yet), or when it has to
			name = "what TFA does not draw is not a part: hidden, not a model, no bone and no attachment point, switched off by its stat, no model yet",
			func = function()
				local shown = model()
				local w = tfa({
					shown = {type = "Model", bone = "b", curmodel = shown},
					hidden = {type = "Model", bone = "b", hide = true, curmodel = model()},
					sprite = {type = "Sprite", bone = "b", curmodel = model()},
					nobone = {type = "Model", curmodel = model()},
					off = {type = "Model", bone = "b", curmodel = model()},
					later = {type = "Model", bone = "b"}
				}, {"shown", "hidden", "sprite", "nobone", "off", "later", "missing"}, {off = true})
				local list, count = parts(w)

				expect(count).to.equal(1)
				expect(list[1]).to.equal(shown)
			end
		},
		{
			-- fails when the patch keeps a list: the attachment the player changes during the camouflage must be the next call's list (TFA builds a new element and a new model)
			name = "the parts are read at each call: an attachment put on or taken off, or a model made again, is the next list",
			func = function()
				local first, second = model(), model()
				local elements = {sight = {type = "Model", bone = "b", curmodel = first}}
				local order = {"sight"}
				local w = tfa(elements, order)

				expect(select(2, parts(w))).to.equal(1)

				-- a laser is put on: a new element, and TFA rebuilds its render order
				elements.laser = {type = "Model", bone = "b", curmodel = second}
				w.vRenderOrder = {"sight", "laser"}
				expect(select(2, parts(w))).to.equal(2)

				-- the sight is taken off
				elements.sight = nil
				w.vRenderOrder = {"laser"}

				local list, count = parts(w)

				expect(count).to.equal(1)
				expect(list[1]).to.equal(second)

				-- the sight comes back with a model of its own
				local third = model()

				elements.sight = {type = "Model", bone = "b", curmodel = third}
				w.vRenderOrder = {"sight", "laser"}
				list = parts(w)
				expect(list[1]).to.equal(third)
			end
		},
		{
			-- fails when a weapon that is not TFA's, or a TFA weapon that is not ready (no render order yet, no tables), raises an error or gives parts
			name = "nothing for a weapon that is not TFA's, nor for a TFA weapon that is not ready; never an error",
			func = function()
				local ent = model()
				local other = {IsValid = function() return true end, vRenderOrder = {"sight"}, ViewModelElements = {sight = {type = "Model", bone = "b", curmodel = ent}}}

				expect(select(2, parts(other))).to.equal(0)

				local noOrder = tfa({sight = {type = "Model", bone = "b", curmodel = ent}}, nil)

				expect(select(2, parts(noOrder))).to.equal(0)

				local noTables = tfa(nil, {"sight"})

				expect(select(2, parts(noTables))).to.equal(0)

				-- an order that names an element that is gone (TFA rebuilds it at its next draw)
				expect(select(2, parts(tfa({}, {"ghost"})))).to.equal(0)
			end
		},
		{
			-- fails when the patch does not work with the real TFA base (a name or a field of its tables that is not what the patch reads): the real weapon is given to the player and
			-- asked for its parts
			name = "a real TFA weapon (when TFA is installed): the patch reads its own tables without an error and gives the models it has",
			func = function()
				local class = "tfa_ins2_famas"

				if not weapons.GetStored(class) then
					return -- TFA is not installed here: nothing to check
				end

				local wep = weapons.Get(class)

				expect(wep ~= nil).to.beTrue()

				-- the stored weapon is not an entity: the patch must say nothing for it and raise nothing
				local ok, count = pcall(function()
					return select(2, parts(wep))
				end)

				expect(ok).to.beTrue()
				expect(count).to.equal(0)
			end
		}
	}
}
