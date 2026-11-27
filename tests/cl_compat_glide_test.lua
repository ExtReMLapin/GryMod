-- Tests of the Glide adapter, the client part (compat/vehicles/cl_glide.lua): the camera owner (Glide has its own camera), the name of a camouflaged player that Glide writes
-- over what he is aiming at, the dashboard of Glide that the player may hide, and the night vision key that Glide uses too. GLuaTest format, client realm.
--
-- Glide is NOT installed in the test game: the players are STAND-INS that answer the way lua/glide/sh_player.lua does (ply:GlideGetVehicle), and the table `Glide` that the key
-- test reads (Glide.Config.binds, lua/glide/client/config.lua and events.lua) is made for the case and taken away after it. Each case names the production change whose absence
-- makes it fail.

local API
local saved = {}

-- what GetNW2Entity answers for an entity that was never set (the engine's NULL): a stand-in that is not valid
local NULL_ENTITY = {IsValid = function() return false end}
local realGlide, hadGlide

local function player(name, vehicleOf, cloak)
	local p = {
		IsValid = function() return true end,
		GetClass = function() return "player" end,
		IsPlayer = function() return true end,
		name = name,
		cloak = cloak or 0
	}

	if vehicleOf ~= nil then
		function p:GlideGetVehicle() return vehicleOf or nil end
	end

	return p
end

local function car()
	return {IsValid = function() return true end, GetClass = function() return "t_glide_car" end, IsGlideVehicle = true}
end

local function setConVar(name, value)
	local cv = GetConVar(name)

	assert(cv, "the convar " .. name .. " does not exist")

	if saved[name] == nil then
		saved[name] = cv:GetString()
	end

	cv:SetString(value)
end

return {
	groupName = "GryMod Glide adapter: the camera, the name tag, the dashboard and the key (client)",
	beforeEach = function()
		API = GryMod.API
		saved = {}
		saved.CloakLevel = API.CloakLevel
		API.CloakLevel = function(ply) return ply.cloak or 0 end
		hadGlide, realGlide = Glide ~= nil, Glide
	end,
	afterEach = function()
		API.CloakLevel = saved.CloakLevel
		Glide = hadGlide and realGlide or nil

		if GryMod.GlideCompat then
			GryMod.GlideCompat.LocalVehicle, GryMod.GlideCompat.NightVisionKey = saved.LocalVehicle, saved.NightVisionKey
		end

		for name, value in pairs(saved) do
			if name ~= "CloakLevel" and name ~= "LocalVehicle" and name ~= "NightVisionKey" and GetConVar(name) then
				GetConVar(name):SetString(value)
			end
		end
	end,
	cases = {
		{
			-- fails when the adapter adds no camera owner, or answers true for a player who is not in a Glide vehicle (GryMod would never zoom again for him)
			name = "a player in a Glide vehicle has another camera on him: Glide's; a walking player has not",
			func = function()
				expect(API.IsCameraOwned(player("rider", car()), true)).to.beTrue()
				expect(API.IsCameraOwned(player("walker", false), true)).to.beFalse()
				expect(API.IsCameraOwned(player("no glide function"), true)).to.beFalse()
			end
		},
		{
			-- fails when Glide writes the name of a camouflaged player: the hook of the tag must answer a colour and another name
			name = "Glide_PlayerTagColor hides the name of a camouflaged player (from half of the camouflage on)",
			func = function()
				local color, name = hook.Run("Glide_PlayerTagColor", player("secret", nil, 1), "secret", 1)

				expect(color).to.exist()
				expect(name).to.equal("???")

				expect(select(2, hook.Run("Glide_PlayerTagColor", player("fading", nil, 0.6), "fading", 1))).to.equal("???")
				expect(hook.Run("Glide_PlayerTagColor", player("half", nil, 0.4), "half", 1)).to.beNil()
				expect(hook.Run("Glide_PlayerTagColor", player("plain", nil, 0), "plain", 1)).to.beNil()
			end
		},
		{
			-- fails when the setting does not exist (default on), or does not give the name back when it is off
			name = "gry_glide_tag_cloak 0 lets Glide write the name",
			func = function()
				expect(GetConVar("gry_glide_tag_cloak")).to.exist()
				expect(GetConVar("gry_glide_tag_cloak"):GetDefault()).to.equal("1")

				setConVar("gry_glide_tag_cloak", "0")
				expect(hook.Run("Glide_PlayerTagColor", player("secret", nil, 1), "secret", 1)).to.beNil()
			end
		},
		{
			-- fails when the dashboard of Glide is hidden by default (nothing changes until the player asks), or the setting does not hide it
			name = "Glide's dashboard is shown by default, and hidden when the player asks (Glide_CanDrawHUD)",
			func = function()
				expect(GetConVar("gry_glide_hide_hud")).to.exist()
				expect(GetConVar("gry_glide_hide_hud"):GetDefault()).to.equal("0")
				expect(hook.Run("Glide_CanDrawHUD", car())).to.beNil()

				setConVar("gry_glide_hide_hud", "1")
				expect(hook.Run("Glide_CanDrawHUD", car())).to.equal(false)
			end
		},
		{
			-- fails when the night vision key of the game still toggles the night vision in a Glide vehicle while Glide uses the same key (N is Glide's neutral gear)
			name = "the night vision is refused by its key in a Glide vehicle when Glide has that key, and only then",
			func = function()
				expect(GryMod.GlideCompat).to.exist()

				saved.LocalVehicle, saved.NightVisionKey = GryMod.GlideCompat.LocalVehicle, GryMod.GlideCompat.NightVisionKey

				Glide = {Config = {binds = {general_controls = {headlights = KEY_H or 1}, land_controls = {shift_neutral = KEY_N}}}}

				GryMod.GlideCompat.NightVisionKey = function() return KEY_N end
				GryMod.GlideCompat.LocalVehicle = function() return car() end
				expect(hook.Run("GryMod_CanUseView", "nightvision", "key")).to.equal(false)

				-- on foot
				GryMod.GlideCompat.LocalVehicle = function() return nil end
				expect(hook.Run("GryMod_CanUseView", "nightvision", "key")).to.beNil()

				-- in the vehicle, with a key Glide does not use
				GryMod.GlideCompat.LocalVehicle = function() return car() end
				GryMod.GlideCompat.NightVisionKey = function() return 9999 end
				expect(hook.Run("GryMod_CanUseView", "nightvision", "key")).to.beNil()

				-- the zoom is another question, and a bind (+gry_nightvision) is blocked by Glide itself
				GryMod.GlideCompat.NightVisionKey = function() return KEY_N end
				expect(hook.Run("GryMod_CanUseView", "zoom", "key")).to.beNil()
				expect(hook.Run("GryMod_CanUseView", "nightvision", "bind")).to.beNil()
			end
		},
		{
			-- fails when the setting does not exist, or when switching it off does not give the key back
			name = "gry_glide_nv_key 0 gives the key back to the night vision",
			func = function()
				expect(GetConVar("gry_glide_nv_key")).to.exist()
				expect(GetConVar("gry_glide_nv_key"):GetDefault()).to.equal("1")

				saved.LocalVehicle, saved.NightVisionKey = GryMod.GlideCompat.LocalVehicle, GryMod.GlideCompat.NightVisionKey
				Glide = {Config = {binds = {land_controls = {shift_neutral = KEY_N}}}}
				GryMod.GlideCompat.NightVisionKey = function() return KEY_N end
				GryMod.GlideCompat.LocalVehicle = function() return car() end

				setConVar("gry_glide_nv_key", "0")
				expect(hook.Run("GryMod_CanUseView", "nightvision", "key")).to.beNil()
			end
		},
		{
			-- fails when a file that is run without Glide in the game raises an error at the hook (Glide's table is not there)
			name = "without Glide nothing raises: the key test answers nothing when there is no Glide table",
			func = function()
				Glide = nil
				saved.LocalVehicle, saved.NightVisionKey = GryMod.GlideCompat.LocalVehicle, GryMod.GlideCompat.NightVisionKey
				GryMod.GlideCompat.NightVisionKey = function() return KEY_N end
				GryMod.GlideCompat.LocalVehicle = function() return car() end

				expect(hook.Run("GryMod_CanUseView", "nightvision", "key")).to.beNil()
			end
		},
		{
			-- fails when a missile that follows somebody else's vehicle warns this player, or when the one that follows his own vehicle (or himself, or his seat) does not: the warning is for
			-- the target (SHARED-DANGER-1, danger.warnFor)
			name = "the warning of a Glide missile is for the player it follows: himself, his vehicle or his seat; not for another target",
			func = function()
				local entry = API.GetTracked({IsValid = function() return true end, GetClass = function() return "glide_missile" end})
				local mine, other = car(), car()
				local seat = {IsValid = function() return true end}
				local me = player("me", mine)

				function me:GetVehicle() return seat end

				local function missile(target, hasTarget)
					return {
						GetNW2Entity = function() return target or NULL_ENTITY end,
						GetHasTarget = function() return hasTarget == true end
					}
				end

				expect(entry.danger.warnFor(missile(mine, true), me)).to.beTrue()
				expect(entry.danger.warnFor(missile(me, true), me)).to.beTrue()
				expect(entry.danger.warnFor(missile(seat, true), me)).to.beTrue()
				expect(entry.danger.warnFor(missile(other, true), me)).to.beFalse()
			end
		},
		{
			-- fails when a rocket that follows nothing (an unguided one) stops warning, or when a guided one whose target the client does not know warns everybody
			name = "an unguided Glide missile warns whoever is near; a guided one whose target is out of sight does not",
			func = function()
				local entry = API.GetTracked({IsValid = function() return true end, GetClass = function() return "glide_missile" end})
				local me = player("me", false)

				local function missile(hasTarget)
					return {GetNW2Entity = function() return NULL_ENTITY end, GetHasTarget = function() return hasTarget end}
				end

				expect(entry.danger.warnFor(missile(false), me)).to.beTrue()
				expect(entry.danger.warnFor(missile(true), me)).to.beFalse()
			end
		},
		{
			-- fails when the tab is not on the Compatibility page (the settings above would have no place in the menu)
			name = "the Compatibility page has a Glide tab",
			func = function()
				if not GryMod.OptionTabList then
					return
				end

				local found = false

				for _, tab in ipairs(GryMod.OptionTabList("compat")) do
					found = found or tab.name == "Glide"
				end

				expect(found).to.beTrue()
			end
		}
	}
}
