-- Tests of the PAC3 patch (lua/grymod/compat/tools/cl_pac3.lua), GLuaTest format, client realm. PAC3 draws the parts of an outfit as models of its own, in
-- PostDrawOpaqueRenderables / PostDrawTranslucentRenderables and, in first person, PostDrawViewModel / PostDrawPlayerHands (lua/pac3/core/client/part_pool.lua of
-- github.com/CapsAdmin/pac3), never through the player's own draw: when the camouflage hides the player (PrePlayerDraw) an outfit stays in plain view. PAC3's public
-- pac.TogglePartDrawing(ent, bool) (lua/pac3/core/client/util.lua) shows or hides every part of an entity. PAC3 was not installed when this was written: the cases use a stand-in
-- of that function and of pac.LocalViewModel / pac.LocalHands. Each case names the change whose absence makes it fail.

local realPac, calls
local ME = {IsValid = function() return true end, name = "me"}
local OTHER = {IsValid = function() return true end, name = "other"}

local function toggled(ent)
	local list = {}

	for _, call in ipairs(calls) do
		if call[1] == ent then
			list[#list + 1] = call[2]
		end
	end

	return list
end

return {
	groupName = "GryMod compat: PAC3 (client)",
	beforeEach = function()
		realPac = pac
		calls = {}
		pac = {TogglePartDrawing = function(ent, show) calls[#calls + 1] = {ent, show} end}
		LOCAL_PLAYER = ME
		include("grymod/compat/tools/cl_pac3.lua")
	end,
	afterEach = function()
		pac = realPac
		LOCAL_PLAYER = nil
		hook.Remove("GryMod_CloakChanged", "GryMod compat pac3")
	end,
	cases = {
		{
			-- fails when the outfit of a player who goes camouflaged stays visible, or when it does not come back
			name = "the parts of a player's outfit are hidden when he goes camouflaged and shown when he comes out",
			func = function()
				hook.Run("GryMod_CloakChanged", OTHER, true, 0)

				expect(toggled(OTHER)[1]).to.equal(false)

				hook.Run("GryMod_CloakChanged", OTHER, false, 0)

				expect(toggled(OTHER)[2]).to.equal(true)
			end
		},
		{
			-- fails when a player the patch did not hide is "shown" at each end of a camouflage: PAC has its own reasons to hide an outfit (an ignored player, a hidden outfit)
			name = "a player whose outfit the patch did not hide is not touched when his camouflage ends",
			func = function()
				hook.Run("GryMod_CloakChanged", OTHER, false, 0)

				expect(#toggled(OTHER)).to.equal(0)
			end
		},
		{
			-- fails when a second report of the same state toggles again
			name = "the same state told twice toggles once",
			func = function()
				hook.Run("GryMod_CloakChanged", OTHER, true, 0)
				hook.Run("GryMod_CloakChanged", OTHER, true, 0.5)

				expect(#toggled(OTHER)).to.equal(1)
			end
		},
		{
			-- fails when the local player's gloves and attachments on the view model and the hands (drawn in first person by PostDrawViewModel / PostDrawPlayerHands) stay visible
			name = "for the local player the parts on the view model and the hands are hidden and shown too",
			func = function()
				local vm = {IsValid = function() return true end}
				local hands = {IsValid = function() return true end}

				pac.LocalViewModel, pac.LocalHands = vm, hands
				hook.Run("GryMod_CloakChanged", ME, true, 0)

				expect(toggled(ME)[1]).to.equal(false)
				expect(toggled(vm)[1]).to.equal(false)
				expect(toggled(hands)[1]).to.equal(false)

				hook.Run("GryMod_CloakChanged", ME, false, 0)

				expect(toggled(ME)[2]).to.equal(true)
				expect(toggled(vm)[2]).to.equal(true)
				expect(toggled(hands)[2]).to.equal(true)
			end
		},
		{
			-- fails when another player's camouflage touches the view model's parts, or when a missing view model raises an error
			name = "another player's change leaves the view model alone; a missing view model or hands is no error",
			func = function()
				local vm = {IsValid = function() return true end}

				pac.LocalViewModel = vm
				hook.Run("GryMod_CloakChanged", OTHER, true, 0)

				expect(#toggled(vm)).to.equal(0)

				pac.LocalViewModel, pac.LocalHands = nil, nil
				hook.Run("GryMod_CloakChanged", ME, true, 0)

				expect(toggled(ME)[1]).to.equal(false)
			end
		},
		{
			-- fails when the patch raises an error without PAC3, with a PAC3 that has no such function, or with one that fails: the hook is GryMod's, it must never break the camouflage
			name = "without PAC3, with an odd PAC3 or one that fails, nothing is raised",
			func = function()
				pac = nil
				hook.Run("GryMod_CloakChanged", OTHER, true, 0)

				pac = {}
				hook.Run("GryMod_CloakChanged", OTHER, true, 0)

				pac = {TogglePartDrawing = function() error("boom") end}
				hook.Run("GryMod_CloakChanged", OTHER, false, 0)

				expect(#calls).to.equal(0)
			end
		},
		{
			-- fails when a player that PAC3 learned about after he was camouflaged is shown at the end of it although the patch could not hide him (PAC3 was not there when he went in)
			name = "a player the patch could not hide (no PAC3 then) is not shown later",
			func = function()
				local later = {IsValid = function() return true end}

				pac = nil
				hook.Run("GryMod_CloakChanged", later, true, 0)

				pac = {TogglePartDrawing = function(ent, show) calls[#calls + 1] = {ent, show} end}
				hook.Run("GryMod_CloakChanged", later, false, 0)

				expect(#calls).to.equal(0)
			end
		}
	}
}
