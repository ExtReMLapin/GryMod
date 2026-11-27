-- The player's own body in first person (client): two addons draw the local player's body or legs themselves, with client side models that the camouflage does not cover (they are not
-- the view model nor the player the engine draws): Gmod Legs 3 (1.3 million subscribers) and Enhanced Camera 2 (136 thousand). A camouflaged player would look down at plain legs.
-- While the camouflage is on (and while it fades out) this patch HIDES them, through what each addon offers; covering them like the arms is `GryMod.API.AddPlayerPartsProvider` and
-- is for a later decision. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): nothing happens, nothing is written, for an addon that is not installed.
--
-- What was READ in the addons' public source (none is installed here; the checks are made with stand-ins, tests/cl_compat_view_parts_test.lua):
--   Gmod Legs 3  its test of "draw the legs" includes `not LocalPlayer():GetTable().ShouldDisableLegs` (cl_gmod_legs.lua:24), a field that any gamemode may set. It is set to true while the
--                camouflage is on, and put back to nothing at the end ONLY if this patch set it (a flag that somebody else had set stays).
--   Enhanced Camera 2  its body is drawn when EnhancedCameraTwo:ShouldDraw() answers true (client.lua:162-175, asked by its Render at :503 and by its CreateMove). The addon also has
--                SetLimbHidden(limb, hidden) (:20-30, public) but that hides the four limbs only, not the torso and the head, so ShouldDraw is wrapped (once; the original is kept): false
--                while the camouflage is on, the addon's own answer otherwise. Its yaw lock in a vehicle follows the same answer, which is fine while the body is hidden.
--
-- When: the hook GryMod_CloakChanged(ply, on, level) (docs/api.md "What a player wears"), for the local player only. At the end of a camouflage the player is still half hidden while it
-- fades out (GryMod.API.CloakLevel), so the body comes back with ONE timer set for the end of the fade, and a camouflage switched on again before cancels it. No Think, no polling.

GryMod = GryMod or {}

local B = GryMod.CompatPlayerBody or {}
GryMod.CompatPlayerBody = B

B.TIMER = "GryMod compat body hide"

local hidden = false
local legsSet = false

function B.Hidden()
	return hidden
end

local function legsThere()
	return GetConVar("cl_legs") ~= nil
end

-- Hides or shows the body that the addons draw. Cheap, and safe when no addon is there.
function B.Apply(on)
	hidden = on == true

	if not legsThere() then
		return
	end

	local ply = LocalPlayer()

	if not IsValid(ply) then
		return
	end

	local fields = ply:GetTable()

	if hidden then
		if not fields.ShouldDisableLegs then
			fields.ShouldDisableLegs = true
			legsSet = true
		end
	elseif legsSet then
		fields.ShouldDisableLegs = nil
		legsSet = false
	end
end

-- Enhanced Camera 2: ShouldDraw asked through a wrapper (kept once, so a file loaded again does not wrap the wrapper).
B.wrappers = B.wrappers or setmetatable({}, {__mode = "k"})

local function wrapper(self, ...)
	if hidden then
		return false
	end

	return B.original(self, ...)
end

B.wrappers[wrapper] = true

-- Puts the wrapper on Enhanced Camera 2's function. True when it is there, false when the addon is not installed.
function B.Install()
	if not istable(EnhancedCameraTwo) or not isfunction(EnhancedCameraTwo.ShouldDraw) then
		return false
	end

	local current = EnhancedCameraTwo.ShouldDraw

	if current == wrapper then
		return true
	end

	if not B.wrappers[current] then
		B.original = current
	end

	EnhancedCameraTwo.ShouldDraw = wrapper

	return true
end

-- The camouflage of the local player starts or ends.
function B.OnCloakChanged(ply, on, level)
	if ply ~= LocalPlayer() then
		return
	end

	if on then
		timer.Remove(B.TIMER)
		B.Apply(true)

		return
	end

	-- the end: the body comes back when the fade-out is over (the level goes down at CloakFadeRate a second)
	local rate = GryMod.CloakFadeRate and GryMod.CloakFadeRate() or math.huge
	local remaining = (isnumber(level) and rate > 0 and rate ~= math.huge) and level / rate or 0

	if remaining <= 0 then
		timer.Remove(B.TIMER)
		B.Apply(false)

		return
	end

	timer.Create(B.TIMER, remaining, 1, function()
		-- (a camouflage that came back in the meantime keeps the body hidden)
		if GryMod.API.CloakLevel(LocalPlayer()) > 0 then
			return
		end

		B.Apply(false)
	end)
end

-- Everything back as it was (a file loaded again, the tests).
function B.Reset()
	timer.Remove(B.TIMER)

	if legsSet then
		local ply = LocalPlayer()

		if IsValid(ply) then
			ply:GetTable().ShouldDisableLegs = nil
		end
	end

	hidden, legsSet = false, false
end

hook.Add("GryMod_CloakChanged", "GryMod compat body hide", function(ply, on, level)
	B.OnCloakChanged(ply, on, level)
end)

-- the addons define their functions when their own files load, which may be after this one; a player already camouflaged when the game is up is hidden at once
hook.Add("InitPostEntity", "GryMod compat body hide", function()
	B.Install()

	local ply = LocalPlayer()

	if IsValid(ply) and GryMod.API.CloakLevel(ply) > 0 then
		B.Apply(true)
	end
end)

B.Install()
