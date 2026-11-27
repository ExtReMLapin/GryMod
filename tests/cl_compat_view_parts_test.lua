-- Tests of the compatibility patches for the addons that draw the player's own body or his view model, and for the other night visions (lua/grymod/compat/view/cl_legs_ec2.lua,
-- cl_vmanip.lua, cl_nvg_others.lua), GLuaTest format, client realm. None of these addons is installed in the game of the test: each case runs against a STAND-IN of what was read in
-- the addon's public source (the file and line are in the patch), put in place of the game's own functions for the length of the case and put back afterwards. A real addon is not
-- touched, no convar of anybody is written. Each case names the change whose absence makes it fail.

-- the game's own function, taken when the file is loaded (the cases put a stand-in in its place)
local realLocalPlayer = LocalPlayer

local saved = {}
local fakeHooks
local ply

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

local function player()
	local p = {fields = {}}

	p.IsValid = function() return true end
	p.GetTable = function(self) return self.fields end

	return p
end

local function setHook(event, id)
	fakeHooks[event] = fakeHooks[event] or {}
	fakeHooks[event][id] = function() end
end

return {
	groupName = "GryMod compat: the player's body, VManip and other night visions (client)",
	beforeEach = function()
		fakeHooks = {}
		ply = player()

		local getTable = hook.GetTable

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
		stub(_G, "LocalPlayer", function() return ply end)
	end,
	afterEach = function()
		pcall(function()
			if GryMod.CompatPlayerBody then
				GryMod.CompatPlayerBody.Reset()
			end
		end)
		pcall(function()
			if GryMod.CompatVManip then
				GryMod.CompatVManip.Reset()
			end
		end)
		restore()
	end,
	cases = {
		{
			-- fails when the patch is not loaded, or when the legs' flag is not set while the camouflage is on (cl_gmod_legs.lua:24 reads LocalPlayer():GetTable().ShouldDisableLegs)
			name = "Gmod Legs: the legs are switched off (ShouldDisableLegs) while the camouflage is on, and on again when it ends",
			func = function()
				local B = GryMod.CompatPlayerBody

				expect(B).to.exist()
				stub(_G, "GetConVar", function(name) if name == "cl_legs" then return {GetBool = function() return true end} end end)

				B.Apply(true)
				expect(ply:GetTable().ShouldDisableLegs).to.beTrue()
				B.Apply(false)
				expect(ply:GetTable().ShouldDisableLegs).to.beNil()
			end
		},
		{
			-- fails when the patch takes away a flag that somebody else set (a server's gamemode switches the legs off for its own reason): only what we set is ours
			name = "Gmod Legs: a ShouldDisableLegs that somebody else had set is left as it was",
			func = function()
				local B = GryMod.CompatPlayerBody

				stub(_G, "GetConVar", function(name) if name == "cl_legs" then return {GetBool = function() return true end} end end)
				ply:GetTable().ShouldDisableLegs = true

				B.Apply(true)
				B.Apply(false)

				expect(ply:GetTable().ShouldDisableLegs).to.beTrue()
			end
		},
		{
			-- fails when the patch writes a field on a player when Gmod Legs is not installed (no cl_legs convar)
			name = "Gmod Legs not installed: nothing is written on the player",
			func = function()
				local B = GryMod.CompatPlayerBody

				stub(_G, "GetConVar", function() return nil end)
				B.Apply(true)

				expect(ply:GetTable().ShouldDisableLegs).to.beNil()
			end
		},
		{
			-- fails when Enhanced Camera 2's ShouldDraw (client.lua:162, called by its Render at :503 and its CreateMove) is not wrapped, or the original answer is lost when the body is shown
			name = "Enhanced Camera 2: ShouldDraw answers false while the camouflage is on, and the addon's own answer otherwise",
			func = function()
				local B = GryMod.CompatPlayerBody
				local answer = true
				local ec2 = {ShouldDraw = function(self) return answer end}

				stub(_G, "EnhancedCameraTwo", ec2)
				B.Install()

				expect(ec2:ShouldDraw()).to.beTrue()
				B.Apply(true)
				expect(ec2:ShouldDraw()).to.beFalse()
				B.Apply(false)
				expect(ec2:ShouldDraw()).to.beTrue()
				answer = false
				expect(ec2:ShouldDraw()).to.beFalse()
			end
		},
		{
			-- fails when Install wraps its own wrapper (a file loaded again would then keep hiding a body that must show), or does not keep the original
			name = "Enhanced Camera 2: Install twice wraps once, and the original is kept",
			func = function()
				local B = GryMod.CompatPlayerBody
				local ec2 = {ShouldDraw = function(self) return true end}
				local original = ec2.ShouldDraw

				stub(_G, "EnhancedCameraTwo", ec2)
				B.Install()

				local wrapper = ec2.ShouldDraw

				B.Install()

				expect(ec2.ShouldDraw).to.equal(wrapper)
				expect(wrapper).toNot.equal(original)
				B.Apply(true)
				B.Apply(false)
				expect(ec2:ShouldDraw()).to.beTrue()
			end
		},
		{
			-- fails when the hook GryMod_CloakChanged (docs/api.md, SHARED-PLAYER-PARTS-1) is not listened to, or another player's change hides the local body
			name = "GryMod_CloakChanged: the local player's camouflage hides the body, another player's does not",
			func = function()
				local B = GryMod.CompatPlayerBody
				local other = player()

				stub(_G, "GetConVar", function(name) if name == "cl_legs" then return {GetBool = function() return true end} end end)

				B.OnCloakChanged(other, true, 1)
				expect(B.Hidden()).to.beFalse()

				B.OnCloakChanged(ply, true, 1)
				expect(B.Hidden()).to.beTrue()
				expect(ply:GetTable().ShouldDisableLegs).to.beTrue()
			end
		},
		{
			-- fails when the body comes back at once at the end of the camouflage (the player is half hidden while it fades out), or never comes back
			name = "the body comes back when the fade-out is over, not before",
			func = function()
				local B = GryMod.CompatPlayerBody
				local level = 1
				local timers = {}

				stub(_G, "GetConVar", function(name) if name == "cl_legs" then return {GetBool = function() return true end} end end)
				stub(GryMod.API, "CloakLevel", function() return level end)
				stub(GryMod, "CloakFadeRate", function() return 0.5 end) -- 2 seconds for a whole level
				stub(timer, "Create", function(name, delay, reps, fn) timers[name] = {delay = delay, fn = fn} end)
				stub(timer, "Remove", function(name) timers[name] = nil end)

				B.OnCloakChanged(ply, true, 1)
				level = 0.5
				B.OnCloakChanged(ply, false, 0.5)

				-- still hidden: half a level to go at half a level a second is one second
				expect(B.Hidden()).to.beTrue()
				expect(timers[B.TIMER]).to.exist()
				expect(timers[B.TIMER].delay).to.equal(1)

				level = 0
				timers[B.TIMER].fn()
				expect(B.Hidden()).to.beFalse()
				expect(ply:GetTable().ShouldDisableLegs).to.beNil()
			end
		},
		{
			-- fails when a new camouflage during the fade-out does not cancel the coming back
			name = "a camouflage switched on again during the fade-out cancels the coming back",
			func = function()
				local B = GryMod.CompatPlayerBody
				local timers = {}

				stub(_G, "GetConVar", function(name) if name == "cl_legs" then return {GetBool = function() return true end} end end)
				stub(GryMod.API, "CloakLevel", function() return 0.5 end)
				stub(GryMod, "CloakFadeRate", function() return 0.5 end)
				stub(timer, "Create", function(name, delay, reps, fn) timers[name] = {delay = delay, fn = fn} end)
				stub(timer, "Remove", function(name) timers[name] = nil end)

				B.OnCloakChanged(ply, true, 1)
				B.OnCloakChanged(ply, false, 0.5)
				B.OnCloakChanged(ply, true, 0.5)

				expect(timers[B.TIMER]).to.beNil()
				expect(B.Hidden()).to.beTrue()
			end
		},
		{
			-- fails when VManip's hook VManipPrePlayAnim (cl_vmanip.lua:263, false cancels the animation) is not answered while the binoculars are up: the hands of the animation
			-- are not drawn there (PreDrawViewModel returns true, so VManip's PostDrawViewModel does not come) and its animation would freeze
			name = "VManip: no animation starts while the binoculars are up",
			func = function()
				local V = GryMod.CompatVManip

				expect(V).to.exist()
				expect(V.PrePlay("flashlight")).to.beNil()

				V.OnBinoculars(true)
				expect(V.PrePlay("flashlight")).to.beFalse()

				V.OnBinoculars(false)
				expect(V.PrePlay("flashlight")).to.beNil()
			end
		},
		{
			-- fails when an animation that is playing when the binoculars go up is left to freeze (its camera stays on a frame of the animation)
			name = "VManip: an animation that plays when the binoculars go up is ended",
			func = function()
				local V = GryMod.CompatVManip
				local removed = 0
				local vmanip = {IsActive = function() return true end, Remove = function() removed = removed + 1 end}

				stub(_G, "VManip", vmanip)
				V.OnBinoculars(true)

				expect(removed).to.equal(1)

				-- and nothing is called when there is none
				vmanip.IsActive = function() return false end
				V.OnBinoculars(true)
				expect(removed).to.equal(1)
			end
		},
		{
			-- fails when VManip is touched without being there
			name = "VManip not installed: the patch does nothing and raises nothing",
			func = function()
				local V = GryMod.CompatVManip

				stub(_G, "VManip", nil)
				V.OnBinoculars(true)
				expect(V.PrePlay("x")).to.beFalse() -- the binoculars are up: the answer is still ours, VManip would only ask if it were there
				V.OnBinoculars(false)
			end
		},
		{
			-- fails when NVScript's switch (hook NV_FX on RenderScreenspaceEffects or HUDPaintBackground: SandEv-Legacy cl_nightvision.lua:11, HaloArmory cl_night_vision.lua:182) is not read
			name = "NVScript: its NV_FX hook (either event) means another night vision is on",
			func = function()
				local N = GryMod.CompatOtherNV

				expect(N).to.exist()
				expect(N.Active(ply)).to.beNil()

				setHook("RenderScreenspaceEffects", "NV_FX")
				expect(N.Active(ply)).to.equal("nvscript")

				fakeHooks = {}
				setHook("HUDPaintBackground", "NV_FX")
				expect(N.Active(ply)).to.equal("nvscript")
			end
		},
		{
			-- fails when JMod's armor effect (ply.EZarmor.effects.nightVision / nightVisionWP, cl_hud.lua:285-292; a dead device blackvision, :283) is not read
			name = "JMod night vision goggles: nightVision or nightVisionWP in the armor's effects, not when the device is dead",
			func = function()
				local N = GryMod.CompatOtherNV

				ply.EZarmor = {effects = {}}
				expect(N.Active(ply)).to.beNil()

				ply.EZarmor.effects.nightVision = true
				expect(N.Active(ply)).to.equal("jmod")

				ply.EZarmor.effects = {nightVisionWP = true}
				expect(N.Active(ply)).to.equal("jmod")

				ply.EZarmor.blackvision = true
				expect(N.Active(ply)).to.beNil()
			end
		},
		{
			-- fails when the veto is not given for the night vision, or is given for the zoom or for another kind (a camera of another addon is not the night vision's business)
			name = "GryMod_CanUseView: false for the night vision while another one is on, nothing for the zoom or when none is",
			func = function()
				local N = GryMod.CompatOtherNV

				expect(N.Veto("nightvision", "key")).to.beNil()

				setHook("RenderScreenspaceEffects", "NV_FX")

				expect(N.Veto("nightvision", "key")).to.beFalse()
				expect(N.Veto("nightvision", "query")).to.beFalse()
				expect(N.Veto("zoom", "key")).to.beNil()
				expect(N.Veto("something", "key")).to.beNil()
			end
		},
		{
			-- fails when the hook is not registered under GryMod's real veto (the game's own question: NightVision.CanTurnOn asks hook.Run("GryMod_CanUseView", "nightvision", ...))
			name = "the veto reaches GryMod's night vision: CanTurnOn is refused while another night vision is on",
			func = function()
				local NV = GryMod.NightVision

				setHook("RenderScreenspaceEffects", "NV_FX")

				-- GryMod's night vision reads the real player (alive, health, suit): not the stand-in of the other cases (put back with the others by restore)
				stub(_G, "LocalPlayer", realLocalPlayer)

				-- hook.Run is the game's: our handler must be in the game's own table to be reached
				local before = hook.Run("GryMod_CanUseView", "nightvision", "query")

				expect(before).to.beFalse()

				if NV and NV.CanTurnOn then
					local can = NV.CanTurnOn()

					expect(can).to.beFalse()
				end
			end
		}
	}
}
