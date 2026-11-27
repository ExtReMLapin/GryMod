-- Wiremod: the entities whose +use key does something, for the use prompt, and the explosives, for the grenade warning. Part of the compatibility patches
-- (lua/grymod/compat/, docs/compat.md): data and small readers through the public API (GryMod.API.RegisterUsable, RegisterTracked), nothing when Wiremod is not there (an
-- entry for a class that does not exist matches nothing).
--
-- Every class below was read in the public code of Wiremod (github.com/wiremod/wire, lua/entities/): the file and what its ENT:Use does are in each comment. Wiremod was not
-- installed when this was written, so none of it was tried in a game: the tests use stand-ins with the fields read here.
--
-- NO `match` function anywhere: a match is asked about every entity of a class no earlier entry took, and a duplicator pastes thousands of Wire entities. Classes only.
-- The priority is above the stock entries (-100) and below the default (0): an entry of another addon for the same class wins.

GryMod = GryMod or {}

local API = GryMod.API

if not API or not API.RegisterUsable or not API.RegisterTracked then
	return -- sh_api.lua, sh_api_tracked.lua and sh_api_usable.lua are included first (grymod_shared.lua)
end

local PRIORITY = -50

local function usable(key, def)
	def.priority = PRIORITY

	local ok, reason = API.RegisterUsable(key, def)

	if not ok then
		MsgN("GryMod: the Wiremod entry '" .. key .. "' of the usable registry was refused: " .. tostring(reason))
	end
end

local function tracked(key, def)
	def.priority = PRIORITY

	local ok, reason = API.RegisterTracked(key, def)

	if not ok then
		MsgN("GryMod: the Wiremod entry '" .. key .. "' of the tracked registry was refused: " .. tostring(reason))
	end
end

-- The value of a method of the entity, or `default` when it has none (a stand-in, an entity of another version): a matcher that raises five errors in a row is switched off.
local function ask(ent, method, default)
	local fn = ent[method]

	if isfunction(fn) then
		return fn(ent)
	end

	return default
end

-- The buttons: gmod_wire_button.lua:83 and gmod_wire_dynamic_button.lua:60 (SIMPLE_USE: a press; a button that is not a toggle stays on while the key is held), the wheel
-- (gmod_wire_wheel.lua:151, reverses its motor) and the hologrid (gmod_wire_hologrid.lua:48, switches its coordinates). They can be used again at once.
usable("wire_buttons", {
	class = {"gmod_wire_button", "gmod_wire_dynamic_button", "gmod_wire_wheel", "gmod_wire_hologrid"}, icon = "use", text = "USE", use = "repeat", cooldown = 0.5
})

-- The lever (gmod_wire_lever.lua:114): Use returns at once while another player holds it (its `User`, the networked entity "User"), so the prompt is hidden then.
usable("wire_lever", {
	class = "gmod_wire_lever", icon = "use", text = "USE", use = "repeat", cooldown = 0.5,
	busy = function(ent)
		local user = ent.GetNWEntity and ent:GetNWEntity("User")

		return user ~= nil and IsValid(user)
	end
})

-- The keyboard (gmod_wire_keyboard/init.lua:229): ONOFF_USE, the player is attached to it on the release of the key (his keys are then captured by the keyboard).
usable("wire_keyboard", {class = "gmod_wire_keyboard", icon = "use", text = "USE", use = "once"})

-- The screens that open an interface on the player (their ENT:Use calls Prompt: characterlcd/init.lua:253, consolescreen/init.lua:69, digitalscreen/init.lua:67, oscilloscope
-- :214, interactiveprop :493). Prompt does nothing unless the screen is interactive, which the client reads from the model (cl_init.lua: `IsInteractive`). A screen that does not
-- say is NOT offered: a missing prompt is better than one that promises what the key does not do.
usable("wire_screens", {
	class = {"gmod_wire_digitalscreen", "gmod_wire_consolescreen", "gmod_wire_characterlcd", "gmod_wire_oscilloscope", "gmod_wire_interactiveprop"},
	icon = "use", text = "USE", use = "repeat", cooldown = 0.5,
	busy = function(ent)
		return ent.IsInteractive ~= true
	end
})

-- The text entry (gmod_wire_textentry.lua:278): the same Prompt, unless its owner disabled the use (the networked `DisableUse`).
usable("wire_text_entry", {
	class = "gmod_wire_textentry", icon = "use", text = "USE", use = "repeat", cooldown = 0.5,
	busy = function(ent)
		return ask(ent, "GetDisableUse", false) == true
	end
})

-- NOT HERE: gmod_wire_pod (:704, a hold of two seconds that gives a remote controller, and only to its owner), gmod_wire_las_receiver (the same), gmod_wire_egp and
-- gmod_wire_egp_hud (a wire output / a HUD link, nothing the player sees), gmod_wire_gpu (an empty Use), gmod_wire_keypad (used by aiming and typing the numbers, not by +use).

-- The explosives. gmod_wire_explosive.lua: a trigger starts a countdown (`exploding`, true until it blows), then util.BlastDamage + the explosion effect (line 232), and the
-- entity is rebuilt or removed. The player who built it is `GetPlayer()` (Wire's own accessor), not the engine's owner. gmod_wire_simple_explosive has no countdown: a trigger
-- blows it at once, so there is nothing to warn about. The blast of both rings the radar through the core's wrap of util.BlastDamage (docs/api.md): nothing to do for it here.
tracked("wire_explosive", {
	class = "gmod_wire_explosive",
	danger = {
		label = "EXPLOSIVE", type = "bomb",
		armed = function(ent)
			return ent.exploding == true
		end,
		ownerOf = function(ent)
			local ply = ask(ent, "GetPlayer", nil)

			if ply ~= nil and IsValid(ply) then
				return ply
			end

			return nil
		end
	}
})
