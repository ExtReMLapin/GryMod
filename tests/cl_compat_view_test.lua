-- Tests of the compatibility patches for the addons that take the view of the player or draw the player's own parts (lua/grymod/compat/view/: cl_thirdperson.lua, cl_legs_ec2.lua,
-- cl_vmanip.lua, cl_nvg_others.lua), GLuaTest format, client realm. None of these addons is installed in the game of the test: every case runs against a STAND-IN of what was read in
-- the addon's public source (the file and line are in the patch), put in place of the game's own functions for the length of the case (GetConVar, hook.GetTable, the addons' global
-- tables) and put back afterwards, whatever happens. A real addon is not touched and no convar of anybody is written. Each case names the change whose absence makes it fail.

local API = GryMod.API
local saved = {}
local fakeConvars, fakeHooks
local ownerKeys

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

-- a convar stand-in: GetBool, GetInt, GetFloat
local function convar(value)
	return {
		GetBool = function() return value == true or (isnumber(value) and value ~= 0) end,
		GetInt = function() return isnumber(value) and value or (value == true and 1 or 0) end,
		GetFloat = function() return isnumber(value) and value or (value == true and 1 or 0) end
	}
end

-- the world the patches look at: the convars by name, the hooks by event and id (never the game's own tables)
local function world()
	fakeConvars, fakeHooks = {}, {}

	local getConvar, getTable = GetConVar, hook.GetTable

	stub(_G, "GetConVar", function(name)
		if fakeConvars[name] ~= nil then
			return fakeConvars[name]
		end

		return getConvar(name)
	end)

	stub(hook, "GetTable", function()
		local merged = {}

		for event, entries in pairs(getTable()) do
			merged[event] = entries
		end

		for event, entries in pairs(fakeHooks) do
			local copy = {}

			for id, fn in pairs(merged[event] or {}) do
				copy[id] = fn
			end

			for id, fn in pairs(entries) do
				copy[id] = fn
			end

			merged[event] = copy
		end

		return merged
	end)
end

local function setConvar(name, value)
	fakeConvars[name] = convar(value)
end

local function setHook(event, id, fn)
	fakeHooks[event] = fakeHooks[event] or {}
	fakeHooks[event][id] = fn or function() end
end

-- the local player as the patches ask about him
local function player(facts)
	facts = facts or {}

	local ply = {
		IsValid = function() return true end,
		Alive = function() return facts.dead ~= true end,
		InVehicle = function() return facts.vehicle == true end,
		ShouldDrawLocalPlayer = function() return facts.thirdperson == true end,
		GetActiveWeapon = function() return facts.weapon or NULL end,
		GetViewEntity = function(self) return self end
	}

	return ply
end

local function owned(ply)
	return API.IsCameraOwned(ply, true)
end

local function install()
	GryMod.CompatThirdPerson.Install()
end

-- the keys of the owners that the patch put (they all begin with "compat.")
local function compatOwners()
	local found = {}

	for _, owner in ipairs(API._cameraOwners or {}) do
		if string.sub(owner.key, 1, 7) == "compat." then
			found[#found + 1] = owner.key
		end
	end

	return found
end

local function dropOwners()
	for _, key in ipairs(compatOwners()) do
		API.RemoveCameraOwner(key)
	end
end

local function clear(names)
	for _, name in ipairs(names) do
		stub(_G, name, nil)
	end
end

return {
	groupName = "GryMod compat: addons that take the view (client)",
	beforeEach = function()
		world()
		dropOwners()
	end,
	afterEach = function()
		pcall(dropOwners)
		pcall(function()
			if GryMod.CompatPlayerBody then
				GryMod.CompatPlayerBody.Reset()
			end
		end)
		restore()
	end,
	cases = {
		{
			-- fails when the patch is not loaded, or puts an owner for an addon that is not there (each owner is asked at every frame)
			name = "third person: with none of the addons there, the patch puts no camera owner and answers nothing",
			func = function()
				expect(GryMod.CompatThirdPerson).to.exist()
				clear({"ctp", "pac", "pace", "ARC9"})
				install()

				expect(#compatOwners()).to.equal(0)
				expect(owned(player())).to.beFalse()
			end
		},
		{
			-- fails when Simple ThirdPerson's switch (simple_thirdperson_enabled, thirdperson.lua:897) is not read, or read without its CalcView hook (SimpleTP.Camera.View, :945)
			name = "Simple ThirdPerson: its camera owns the view while simple_thirdperson_enabled is on, not when it is off, not without its hook",
			func = function()
				local ply = player()

				setConvar("simple_thirdperson_enabled", false)
				install()
				expect(owned(ply)).to.beFalse() -- the convar alone, no hook: not this addon

				setHook("CalcView", "SimpleTP.Camera.View")
				install()
				expect(owned(ply)).to.beFalse()

				setConvar("simple_thirdperson_enabled", true)
				expect(owned(ply)).to.beTrue()
			end
		},
		{
			-- fails when Enhanced ThirdPerson's own conditions are not kept (thirdperson.lua:98-127: thirdperson_etp on, not in a vehicle, alive)
			name = "Enhanced ThirdPerson: thirdperson_etp on owns the view, but not in a vehicle and not dead (its CalcView returns nothing there)",
			func = function()
				setConvar("thirdperson_etp", true)
				setHook("CalcView", "ThirdpersonEnhanced_CalcView")
				install()

				expect(owned(player())).to.beTrue()
				expect(owned(player({vehicle = true}))).to.beFalse()
				expect(owned(player({dead = true}))).to.beFalse()

				setConvar("thirdperson_etp", false)
				expect(owned(player())).to.beFalse()
			end
		},
		{
			-- fails when the switch is read without checking the addon (a convar named third_person could be anybody's), or its vehicle rule is lost (cl_thirdperson.lua:13)
			name = "DarkFated's third person: third_person on with its CalcView hook owns the view, not in a vehicle, not without the hook",
			func = function()
				setConvar("third_person", true)
				install()
				expect(owned(player())).to.beFalse()

				setHook("CalcView", "DarkFated.ThirdPerson")
				install()
				expect(owned(player())).to.beTrue()
				expect(owned(player({vehicle = true}))).to.beFalse()
			end
		},
		{
			-- fails when tpcgm's conditions are not kept (sh_fortnite.lua:176-181: tpc_enabled, no vehicle, dead only with tpc_deathcam, its own disable hook)
			name = "tpcgm (draws the player with drawviewer only): tpc_enabled owns the view; not in a vehicle; dead only with its death camera; its disable hook gives the view back",
			func = function()
				setConvar("tpc_enabled", true)
				setConvar("tpc_deathcam", false)
				setHook("CalcView", "fortnite-camera")
				install()

				expect(owned(player())).to.beTrue()
				expect(owned(player({vehicle = true}))).to.beFalse()
				expect(owned(player({dead = true}))).to.beFalse()

				setConvar("tpc_deathcam", true)
				expect(owned(player({dead = true}))).to.beTrue()

				-- tpcgm asks hook.Run("fortnite-camera-disable") and leaves the view when it answers true
				local run = hook.Run
				stub(hook, "Run", function(name, ...)
					if name == "fortnite-camera-disable" then
						return true
					end

					return run(name, ...)
				end)
				expect(owned(player())).to.beFalse()
			end
		},
		{
			-- fails when Customisable Thirdperson's state (ctp:IsEnabled(), ctp.lua:460) is not read, or any other value than true counts
			name = "Customisable Thirdperson: ctp:IsEnabled() true owns the view (it also took our CalcView away), false or nil does not",
			func = function()
				local enabled

				stub(_G, "ctp", {IsEnabled = function() return enabled end})
				install()

				expect(owned(player())).to.beFalse()
				enabled = true
				expect(owned(player())).to.beTrue()
				enabled = false
				expect(owned(player())).to.beFalse()
			end
		},
		{
			-- fails when ARC9's own third person is not read (ARC9.ShouldThirdPerson, cl_thirdperson.lua:258), or the sights that force the first person (:35) are ignored
			name = "ARC9 third person: ARC9.ShouldThirdPerson() owns the view, not while the sights force the first person (IronSights.ForceFP)",
			func = function()
				local should, sighted = false, false
				local weapon = {
					IsValid = function() return true end,
					ARC9 = true,
					IronSights = {ForceFP = true},
					GetInSights = function() return sighted end
				}

				stub(_G, "ARC9", {ShouldThirdPerson = function() return should end})
				install()

				local ply = player({weapon = weapon})

				expect(owned(ply)).to.beFalse()
				should = true
				expect(owned(ply)).to.beTrue()
				sighted = true
				expect(owned(ply)).to.beFalse()
				weapon.IronSights = {}
				expect(owned(ply)).to.beTrue()
			end
		},
		{
			-- fails when the camera part is read from anything but the active camera (camera.lua:304-345), or a hidden or inactive part counts
			name = "PAC camera part: an active, shown camera part owns the view; a hidden or inactive one does not",
			func = function()
				local part = {IsValid = function() return true end, IsHidden = function() return false end, inactive = false}

				stub(_G, "pac", {active_camera = part})
				install()

				expect(owned(player())).to.beTrue()
				part.IsHidden = function() return true end
				expect(owned(player())).to.beFalse()
				part.IsHidden = function() return false end
				part.inactive = true
				expect(owned(player())).to.beFalse()
				stub(_G, "pac", {})
				expect(owned(player())).to.beFalse()
			end
		},
		{
			-- fails when the editor's camera (view.lua:512-513: pace.IsActive and the hook pac_editor) is not read
			name = "PAC editor: the editor's camera (pace.IsActive() with its CalcView hook pac_editor) owns the view",
			func = function()
				local active = false

				stub(_G, "pac", {})
				stub(_G, "pace", {IsActive = function() return active end})
				setHook("CalcView", "pac_editor")
				install()

				expect(owned(player())).to.beFalse()
				active = true
				expect(owned(player())).to.beTrue()
			end
		},
		{
			-- fails when a camera imposed by a server (net_combat.lua:2867-2880: LocalPlayer().has_calcview and its hook, for half a second) is not read
			name = "PAC lock part: the camera a server imposes owns the view while its hook is there and it was renewed in the last half second",
			func = function()
				local ply = player()
				local now = CurTime()

				ply.has_calcview, ply.last_calcview = true, now
				stub(_G, "pac", {})
				stub(_G, "LocalPlayer", function() return ply end)
				setHook("CalcView", "PAC_lockpart_calcview")
				install()

				expect(owned(ply)).to.beTrue()
				ply.last_calcview = now - 2
				expect(owned(ply)).to.beFalse()
				ply.last_calcview, ply.has_calcview = now, false
				expect(owned(ply)).to.beFalse()
			end
		},
		{
			-- fails when the patch only answers true or false by luck: whatever the addon's switch gives, the owner must give exactly true or false (a number or a text is not a yes)
			name = "an addon whose switch is a number or a text is still answered with true or false",
			func = function()
				setConvar("simple_thirdperson_enabled", 3)
				setHook("CalcView", "SimpleTP.Camera.View")
				install()

				expect(owned(player())).to.beTrue()

				for _, owner in ipairs(API._cameraOwners) do
					if string.sub(owner.key, 1, 7) == "compat." then
						expect(owner.fn(player())).to.beTrue()
					end
				end
			end
		},
		{
			-- fails when a file loaded again, or Install called twice, puts the owner twice
			name = "Install twice leaves one owner for an addon",
			func = function()
				setConvar("simple_thirdperson_enabled", true)
				setHook("CalcView", "SimpleTP.Camera.View")
				install()
				install()

				expect(#compatOwners()).to.equal(1)
			end
		},
		{
			-- fails when the addon is taken away and its owner stays (a stale owner would block the binoculars for good)
			name = "Install again after an addon went away takes its owner away",
			func = function()
				setConvar("simple_thirdperson_enabled", true)
				setHook("CalcView", "SimpleTP.Camera.View")
				install()
				expect(#compatOwners()).to.equal(1)

				fakeHooks.CalcView = nil
				fakeConvars.simple_thirdperson_enabled = nil
				install()

				expect(#compatOwners()).to.equal(0)
			end
		},
		{
			-- H3 of the study: Enhanced ThirdPerson answers true for CHudCrosshair when its third person or its crosshair is off (thirdperson.lua:368-380); a hook that answers true
			-- before ours leaves the game's crosshair next to GryMod's. Fails without the wrapper that gives no answer when our own hook says to hide it.
			name = "Enhanced ThirdPerson's HUDShouldDraw no longer brings the game's crosshair back while GryMod's crosshair is up (first person)",
			func = function()
				local theirs = function(name)
					if name == "CHudCrosshair" then
						return true
					end
				end
				local ours = function(name)
					if name == "CHudCrosshair" then
						return false
					end
				end
				local table_ = {HUDShouldDraw = {ThirdpersonEnhanced_HUDShouldDraw = theirs, GRYCROSSHAIRHIDE = ours}}
				local hooks = {}

				stub(hook, "GetTable", function() return table_ end)
				stub(hook, "Add", function(event, id, fn) table_[event][id] = fn hooks[#hooks + 1] = id end)
				stub(_G, "LocalPlayer", function() return player() end)

				expect(table_.HUDShouldDraw.ThirdpersonEnhanced_HUDShouldDraw("CHudCrosshair")).to.beTrue() -- the problem, as read

				GryMod.CompatThirdPerson.FixEnhancedCrosshair()

				local wrapped = table_.HUDShouldDraw.ThirdpersonEnhanced_HUDShouldDraw

				expect(wrapped("CHudCrosshair")).to.beNil()
				expect(wrapped("CHudHealth")).to.beNil()

				-- in third person GryMod's crosshair is not drawn: the addon keeps its answer
				stub(_G, "LocalPlayer", function() return player({thirdperson = true}) end)
				expect(wrapped("CHudCrosshair")).to.beTrue()

				-- called again: the wrapper is not wrapped
				GryMod.CompatThirdPerson.FixEnhancedCrosshair()
				expect(table_.HUDShouldDraw.ThirdpersonEnhanced_HUDShouldDraw).to.equal(wrapped)

				-- and when GryMod's crosshair is off (no hide from our hook) the addon's answer stays
				table_.HUDShouldDraw.GRYCROSSHAIRHIDE = function() end
				stub(_G, "LocalPlayer", function() return player() end)
				expect(wrapped("CHudCrosshair")).to.beTrue()
			end
		},
		{
			-- fails when the patch is not registered in the loader, or runs without the addon
			name = "H3 wrapper: nothing happens when Enhanced ThirdPerson is not installed",
			func = function()
				local table_ = {HUDShouldDraw = {}}

				stub(hook, "GetTable", function() return table_ end)
				GryMod.CompatThirdPerson.FixEnhancedCrosshair()

				expect(next(table_.HUDShouldDraw)).to.beNil()
			end
		}
	}
}
