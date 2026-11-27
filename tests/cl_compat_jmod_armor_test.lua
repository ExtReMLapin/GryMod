-- Tests of the JMod armor patch (lua/grymod/compat/tools/cl_jmod.lua), GLuaTest format, client realm. JMod's armor is a list of client side models in `ply.EZarmorModels`
-- (lua/jmod/cl_armor.lua of github.com/Jackarunda/gmod): the ones that are bone merged to the player are drawn by the engine as separate entities, which stay in plain view when the
-- camouflage hides the player (the engine skips the player's draw: PrePlayerDraw); the others have no draw of the engine (NoDraw) and JMod draws them by hand in PostPlayerDraw,
-- which GryMod's own draw of the camouflaged player runs again. JMod was not installed when this was written: the cases use stand-ins. Each case names the change whose absence
-- makes it fail.

-- the patch's own function of an event (hook.Run would also run every other addon's hooks with these stand-ins)
local function fire(event, ...)
	local fn = hook.GetTable()[event] and hook.GetTable()[event]["GryMod compat jmod"]

	if fn then
		return fn(...)
	end

	return nil
end

local API
local realAdd, realRemove, providers

local function model(merged, noDraw)
	local m = {nodraw = noDraw or false, SetNoDraw = function(self, b) self.nodraw = b end, GetNoDraw = function(self) return self.nodraw end}

	m.IsValid = function() return not m.removed end
	m.IsEffectActive = function(_, effect) return merged and effect == EF_BONEMERGE end

	return m
end

local function wearer(models)
	return {IsValid = function() return true end, EZarmorModels = models}
end

local function provide(ply)
	local out = {}

	providers.jmod_armor(ply, out)

	return out
end

return {
	groupName = "GryMod compat: JMod armor (client)",
	beforeEach = function()
		API = GryMod.API
		providers = {}
		realAdd, realRemove = API.AddPlayerPartsProvider, API.RemovePlayerPartsProvider
		API.AddPlayerPartsProvider = function(id, fn) providers[id] = fn return true end
		API.RemovePlayerPartsProvider = function() return true end
		JMod = {}
		include("grymod/compat/tools/cl_jmod.lua")
	end,
	afterEach = function()
		API.AddPlayerPartsProvider, API.RemovePlayerPartsProvider = realAdd, realRemove
		JMod = nil
	end,
	cases = {
		{
			-- fails when the patch gives no provider, or gives models that the engine draws as part of the player's own draw (the ones JMod draws by hand are inside GryMod's draw already)
			name = "the provider gives the bone merged armor models, and not the ones JMod draws by hand",
			func = function()
				local a, b, byHand = model(true), model(true), model(false, true)
				local out = provide(wearer({x = a, y = byHand, z = b}))

				expect(#out).to.equal(2)
				expect(out[1] == a or out[2] == a).to.beTrue()
				expect(out[1] == b or out[2] == b).to.beTrue()
			end
		},
		{
			-- fails when the engine keeps drawing a merged model plain next to the camouflage's layers
			name = "a model given to the camouflage is taken out of the engine's draw, once",
			func = function()
				local a = model(true)

				provide(wearer({a}))

				expect(a.nodraw).to.beTrue()
			end
		},
		{
			-- fails when the armor stays out of sight after the camouflage ended
			name = "when the player's camouflage ends, the models the patch hid are drawn by the engine again, and only those",
			func = function()
				local ours, theirs = model(true), model(true, true)
				local ply = wearer({ours, theirs})

				expect(#provide(ply)).to.equal(1) -- a model JMod put away itself is not given to the camouflage either
				fire("GryMod_CloakChanged", ply, false, 0)

				expect(ours.nodraw).to.beFalse()
				expect(theirs.nodraw).to.beTrue() -- JMod's own NoDraw (a weapon armor put away): the patch did not set it, so it does not take it off
			end
		},
		{
			-- fails when the start of a camouflage gives the models back, or when another player's change touches this one's models
			name = "the start of the camouflage, and the change of another player, leave the models as they are",
			func = function()
				local a = model(true)
				local ply = wearer({a})

				provide(ply)
				fire("GryMod_CloakChanged", ply, true, 0.1)
				fire("GryMod_CloakChanged", wearer({}), false, 0)

				expect(a.nodraw).to.beTrue()
			end
		},
		{
			-- fails when a player with no armor, a model that was removed, or no JMod at all raises an error into the camouflage's draw
			name = "no armor, a removed model, or no JMod: nothing is given and nothing is raised",
			func = function()
				local gone = model(true)

				gone.removed = true

				expect(#provide(wearer(nil))).to.equal(0)
				expect(#provide(wearer({gone}))).to.equal(0)

				JMod = nil

				expect(#provide(wearer({model(true)}))).to.equal(0)
			end
		}
	}
}
