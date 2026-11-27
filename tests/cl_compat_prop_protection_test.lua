-- Tests of the prop protection patch (lua/grymod/compat/tools/cl_prop_protection.lua), GLuaTest format, client realm. A prop protection refuses the +use key on what another
-- player owns, on the server; the client already knows the answer: Falco's Prop Protection keeps it in FPP.canTouchEnt(ent, "PlayerUse") (lua/fpp/client/ownability.lua, bit 8 of
-- the touchability the server sends), valid only when its setting FPP_PLAYERUSE1.toggle is on (it is off by default: lua/fpp/sh_settings.lua); NADMOD PP has
-- NADMOD.PlayerCanTouch(ply, ent) (lua/autorun/client/cl_nadmodpp.lua), valid when NADMOD.PPConfig.use is on, and a prop it has no owner for (the world's) is no refusal (its server
-- hook answers nothing for the world's props). Neither was installed when this was written: the cases use stand-ins. Each case names the change whose absence makes it fail.

local realAdd, realRemove, filters
local realFPP, realNADMOD

local ME = {IsValid = function() return true end}

local function ent(index)
	return {IsValid = function() return true end, EntIndex = function() return index or 1 end}
end

local function refuses(e)
	return filters.prop_protection(e, ME) == false
end

return {
	groupName = "GryMod compat: prop protection (client)",
	beforeEach = function()
		local API = GryMod.API

		filters = {}
		realAdd, realRemove = API.AddUsableFilter, API.RemoveUsableFilter
		realFPP, realNADMOD = FPP, NADMOD
		FPP, NADMOD = nil, nil
		API.AddUsableFilter = function(id, fn) filters[id] = fn return true end
		API.RemoveUsableFilter = function() return true end
		include("grymod/compat/tools/cl_prop_protection.lua")
	end,
	afterEach = function()
		local API = GryMod.API

		API.AddUsableFilter, API.RemoveUsableFilter = realAdd, realRemove
		FPP, NADMOD = realFPP, realNADMOD
	end,
	cases = {
		{
			-- fails when the patch registers no filter, or has an opinion with no prop protection installed
			name = "with no prop protection the filter has no opinion",
			func = function()
				expect(filters.prop_protection ~= nil).to.beTrue()
				expect(filters.prop_protection(ent(), ME)).to.beNil()
			end
		},
		{
			-- fails when FPP's answer for the use key is not read, or read for another kind of touch
			name = "FPP: what FPP says the player may not use has no prompt, what he may use has",
			func = function()
				local asked

				FPP = {
					Settings = {FPP_PLAYERUSE1 = {toggle = 1}},
					canTouchEnt = function(e, kind) asked = kind return e.denied ~= true end
				}

				local denied = ent(5)

				denied.denied = true

				expect(refuses(denied)).to.beTrue()
				expect(asked).to.equal("PlayerUse")
				expect(refuses(ent(6))).to.beFalse()
			end
		},
		{
			-- fails when the prompt is taken away while the server's use protection is off (FPP's default): the key works then
			name = "FPP: with its use protection off (its default) nothing is refused",
			func = function()
				FPP = {
					Settings = {FPP_PLAYERUSE1 = {toggle = 0}},
					canTouchEnt = function() return false end
				}

				expect(refuses(ent())).to.beFalse()

				FPP.Settings = nil

				expect(refuses(ent())).to.beFalse()
			end
		},
		{
			-- fails when an entity whose touchability FPP has not sent yet (canTouchEnt answers nil) loses its prompt
			name = "FPP: an entity it knows nothing about yet is not refused",
			func = function()
				FPP = {Settings = {FPP_PLAYERUSE1 = {toggle = 1}}, canTouchEnt = function() return nil end}

				expect(refuses(ent())).to.beFalse()
			end
		},
		{
			-- fails when NADMOD's answer is not read, or read with its use protection off
			name = "NADMOD: a prop another player owns, with its use protection on, has no prompt; with it off, or a prop of yours, it has",
			func = function()
				NADMOD = {PPConfig = {use = true}, PropOwners = {[7] = "STEAM_0:1:2"}, PropNames = {[7] = "Other"}, PlayerCanTouch = function(_, e) return e.mine == true end}

				expect(refuses(ent(7))).to.beTrue()

				local mine = ent(7)

				mine.mine = true

				expect(refuses(mine)).to.beFalse()

				NADMOD.PPConfig.use = false

				expect(refuses(ent(7))).to.beFalse()
			end
		},
		{
			-- fails when a prop of the world (no owner on the client: PlayerCanTouch says no for it) or one NADMOD has not told about yet loses its prompt: a map door must keep it
			name = "NADMOD: the world's props and the ones with no known owner are not refused",
			func = function()
				NADMOD = {PPConfig = {use = true}, PropOwners = {}, PropNames = {[8] = "World"}, PlayerCanTouch = function() return false end}

				expect(refuses(ent(8))).to.beFalse()
				expect(refuses(ent(9))).to.beFalse()
			end
		},
		{
			-- fails when a prop protection that errors, or that answers with odd values, raises an error into the crosshair's scan
			name = "a failing prop protection raises nothing and refuses nothing",
			func = function()
				FPP = {Settings = {FPP_PLAYERUSE1 = {toggle = 1}}, canTouchEnt = function() error("boom") end}
				NADMOD = {PPConfig = {use = true}, PropOwners = {[1] = "x"}, PlayerCanTouch = function() error("boom") end}

				expect(refuses(ent(1))).to.beFalse()
			end
		}
	}
}
