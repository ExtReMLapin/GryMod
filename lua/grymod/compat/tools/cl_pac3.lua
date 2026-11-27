-- PAC3: the outfit of a camouflaged player. Part of the compatibility patches (lua/grymod/compat/, docs/compat.md): it uses GryMod's public hook GryMod_CloakChanged and PAC3's
-- public pac.TogglePartDrawing(ent, show), and does nothing when PAC3 is not installed. Read in the public code of PAC3 (github.com/CapsAdmin/pac3, lua/pac3/core/client/), NOT
-- tried in a game (not installed when this was written): check it with a real outfit, a camouflaged player seen in third person, in a mirror, and the local player's gloves.
--
-- What PAC3 does: the parts of an outfit are drawn for each entity of pac.drawn_entities in PostDrawOpaqueRenderables and PostDrawTranslucentRenderables (part_pool.lua), and the
-- parts that sit on the view model or the hands in PostDrawViewModel and PostDrawPlayerHands: never through the player's own draw. The camouflage hides the player there
-- (PrePlayerDraw), so the outfit stayed in plain view around nobody. pac.TogglePartDrawing(ent, false) hides every part of an entity (and keeps them hidden: PAC3's own update
-- does not show them again), (ent, true) gives them back. It is what PAC3 itself exposes to the server for the same purpose (editor/server/init.lua).
--
-- GryMod tells every client at each change of a player's camouflage (GryMod_CloakChanged(ply, on, level), docs/api.md): the outfit goes with the beginning of the camouflage and
-- comes back with its end, as the body does (it does not fade, PAC3's parts have no opacity of GryMod's). Only what this patch hid is shown again: PAC3 has reasons of its own to
-- hide an outfit (an ignored player, a hidden outfit) and they are not ours to undo. For the local player the parts on the view model and on the hands go too.

local HOOK = "GryMod compat pac3"

local hidden = setmetatable({}, {__mode = "k"}) -- [entity] = true: the entities whose parts this patch hid

local function toggle(ent, show)
	if ent ~= nil and IsValid(ent) then
		pac.TogglePartDrawing(ent, show)
	end
end

local function hide(ply)
	if hidden[ply] then
		return
	end

	hidden[ply] = true
	toggle(ply, false)

	if ply == LocalPlayer() then
		toggle(pac.LocalViewModel, false)
		toggle(pac.LocalHands, false)
	end
end

local function show(ply)
	if not hidden[ply] then
		return
	end

	hidden[ply] = nil
	toggle(ply, true)

	if ply == LocalPlayer() then
		toggle(pac.LocalViewModel, true)
		toggle(pac.LocalHands, true)
	end
end

hook.Add("GryMod_CloakChanged", HOOK, function(ply, on)
	if not istable(pac) or not isfunction(pac.TogglePartDrawing) then
		return
	end

	pcall(function()
		if on then
			hide(ply)
		else
			show(ply)
		end
	end)
end)
