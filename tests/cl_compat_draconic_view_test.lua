-- Tests of the Draconic Base view patch, client side (lua/grymod/compat/weapons/cl_draconic_view.lua), GLuaTest format, client realm. Draconic's hook CalcView "!DrcLerp" (the drag of the
-- camera with the weapon's animations) returns a view EVERY frame while a Draconic gun is in hand, and the first view that a CalcView hook returns ends the chain: the binoculars' own hook
-- (GRYBINOCULARSZOOM) never ran, the suit zoom saw "another addon took the view" and closed at once, so the zoom key did nothing. While the binoculars are on screen the hook of the base must
-- give no view. The hook table is stood in for (the real one is checked in the game). Each case names the change that makes it fail.

local saved = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

-- a stand-in of the hook table: what the patch reads (hook.GetTable) and what it writes (hook.Add)
local function hookTable(initial)
	local calc = {}

	for k, v in pairs(initial or {}) do
		calc[k] = v
	end

	local added = {}

	stub(hook, "GetTable", function() return {CalcView = calc} end)
	stub(hook, "Add", function(event, id, fn)
		added[#added + 1] = {event, id, fn}
		calc[id] = fn
	end)

	return calc, added
end

return {
	groupName = "GryMod compat: Draconic Base view (client)",
	afterEach = function()
		for i = #saved, 1, -1 do
			saved[i][1][saved[i][2]] = saved[i][3]
		end

		saved = {}
	end,
	cases = {
		{
			-- fails when the patch answers "the binoculars have the view" for neither the open zoom nor the picture on screen (opening, up, closing), or when it says yes while neither is there
			name = "the base yields while the suit zoom is open or the binoculars' picture is on screen, and only then",
			func = function()
				local V = GryMod.DraconicView
				local active, up = false, false

				stub(GryMod.SuitZoom, "IsActive", function() return active end)
				stub(GryMod.FlashBinoculars, "IsUp", function() return up end)

				expect(V.Yield()).to.beFalse()
				active = true
				expect(V.Yield()).to.beTrue()
				active, up = false, true
				expect(V.Yield()).to.beTrue()
			end
		},
		{
			-- fails when the hook of the base is not wrapped, when the wrapper answers a view while the binoculars are up (the chain would end before ours), or when it no longer gives the base's own
			-- view when they are not (the drag of the camera would be lost for everybody)
			name = "the wrapper gives no view while the binoculars are up, and the base's own view otherwise",
			func = function()
				local V = GryMod.DraconicView
				local yield, calls = false, 0
				local view = {origin = Vector(1, 2, 3)}
				local original = function(ply, origin, ang, fov) calls = calls + 1 return view end
				local calc, added = hookTable({["!DrcLerp"] = original})

				stub(V, "Yield", function() return yield end)
				stub(_G, "DRC", {})

				expect(V.Install()).to.beTrue()
				expect(#added).to.equal(1)
				expect(added[1][1]).to.equal("CalcView")
				expect(added[1][2]).to.equal("!DrcLerp")
				expect(calc["!DrcLerp"]).notTo.equal(original)

				expect(calc["!DrcLerp"]({}, Vector(), Angle(), 90, 1, 100)).to.equal(view)
				expect(calls).to.equal(1)

				yield = true
				expect(calc["!DrcLerp"]({}, Vector(), Angle(), 90, 1, 100)).to.beNil()
				expect(calls).to.equal(1)
			end
		},
		{
			-- fails when a second install wraps the wrapper (the base's function would be asked through two layers, and a reload of the file would add one more each time)
			name = "the install is made once",
			func = function()
				local V = GryMod.DraconicView
				local calc, added = hookTable({["!DrcLerp"] = function() end})

				stub(_G, "DRC", {})

				expect(V.Install()).to.beTrue()

				local wrapper = calc["!DrcLerp"]

				expect(V.Install()).to.beTrue()
				expect(calc["!DrcLerp"]).to.equal(wrapper)
				expect(#added).to.equal(1)
			end
		},
		{
			-- fails when the patch adds a hook although the base has none (an installed base that renamed its hook, or no base at all), or raises an error
			name = "nothing is wrapped when the base's hook is not there",
			func = function()
				local V = GryMod.DraconicView
				local _, added = hookTable({})

				stub(_G, "DRC", nil)
				expect(V.Install()).to.beFalse()

				stub(_G, "DRC", {})
				stub(GryMod.API, "WarnPatchMissing", function() end)
				expect(V.Install()).to.beFalse()
				expect(#added).to.equal(0)
			end
		},
		{
			-- fails when the owner is not told, once the game is up, that the base is there but its hook is not (the zoom key would do nothing and nobody would know why)
			name = "an installed base without its hook is reported once through WarnPatchMissing",
			func = function()
				local V = GryMod.DraconicView
				local told = {}

				hookTable({})
				stub(_G, "DRC", {})
				stub(GryMod.API, "WarnPatchMissing", function(addon, what) told[#told + 1] = {addon, what} end)

				V.Install()
				expect(#told).to.equal(1)
				expect(told[1][1]).to.equal("Draconic Base")
				expect(told[1][2]).to.contain("!DrcLerp")
			end
		}
	}
}
