-- Tests of the Wiremod patch (lua/grymod/compat/tools/sh_wire.lua), GLuaTest format, runs in the server AND in the client realm. Wiremod was not installed when this was written:
-- the cases use stand-ins for its entities, with exactly the fields the patch reads (read in the public code of wiremod/wire: gmod_wire_button.lua NetworkVar "On",
-- gmod_wire_lever.lua NWEntity "User", the screens' client side `IsInteractive`, gmod_wire_textentry.lua NetworkVar "DisableUse", gmod_wire_explosive.lua `exploding` and
-- `GetPlayer()`). Each case names the change whose absence makes it fail.

local API

-- a stand-in for a Wire entity of `class`
local function wire(class, fields)
	local e = {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetSpawnFlags = function() return 0 end
	}

	for key, value in pairs(fields or {}) do
		e[key] = value
	end

	return e
end

local function usable(class, fields)
	return API.GetUsable(wire(class, fields))
end

-- whether the prompt is hidden NOW for this entity and player (the registry's `busy`)
local function busy(class, fields, ply)
	local ent = wire(class, fields)
	local entry = API.GetUsable(ent)

	return entry ~= nil and API.UsableBusy(ent, ply, entry) == true
end

return {
	groupName = "GryMod compat: Wiremod (shared)",
	beforeEach = function()
		API = GryMod.API
		include("grymod/compat/tools/sh_wire.lua")
	end,
	cases = {
		{
			-- fails when the patch is not loaded, or when one of the entities whose Use does something is left without a prompt
			name = "the buttons, the lever, the wheel and the hologrid have a use prompt",
			func = function()
				for _, class in ipairs({"gmod_wire_button", "gmod_wire_dynamic_button", "gmod_wire_lever", "gmod_wire_wheel", "gmod_wire_hologrid"}) do
					local entry = usable(class)

					expect(entry ~= nil).to.beTrue()
					expect(entry.icon).to.equal("use")
				end
			end
		},
		{
			-- fails when an entity whose ENT:Use is empty or does nothing for the player (the keypad is used by aiming and typing, a gate has no use) gets a prompt
			name = "the keypad and the gates have none: they have no +use action",
			func = function()
				expect(usable("gmod_wire_keypad")).to.beNil()
				expect(usable("gmod_wire_gate")).to.beNil()
				expect(usable("gmod_wire_expression2")).to.beNil()
				expect(usable("gmod_wire_gpu")).to.beNil()
			end
		},
		{
			-- fails when the pod, the keyboard or the egp keep the prompt although the prompt would promise something else than what the key does
			name = "the keyboard has the prompt (its Use attaches the player); the pod has none (its use is a two seconds hold that gives a remote controller)",
			func = function()
				expect(usable("gmod_wire_keyboard").text).to.equal("USE")
				expect(usable("gmod_wire_pod")).to.beNil()
			end
		},
		{
			-- fails when a screen that is not interactive (its model has no widgets: the client's IsInteractive is false) shows a prompt, or one that is does not
			name = "an interactive screen has the prompt, a plain one has none (the client's IsInteractive)",
			func = function()
				for _, class in ipairs({"gmod_wire_digitalscreen", "gmod_wire_consolescreen", "gmod_wire_characterlcd", "gmod_wire_oscilloscope", "gmod_wire_interactiveprop"}) do
					expect(usable(class) ~= nil).to.beTrue()
					expect(busy(class, {IsInteractive = true})).to.beFalse()
					expect(busy(class, {IsInteractive = false})).to.beTrue()
					expect(busy(class, {})).to.beTrue() -- not known: no prompt rather than a wrong one
				end
			end
		},
		{
			-- fails when a text entry that the owner made "no use" (DisableUse) still shows the prompt
			name = "a text entry with its use disabled has no prompt",
			func = function()
				expect(busy("gmod_wire_textentry", {GetDisableUse = function() return false end})).to.beFalse()
				expect(busy("gmod_wire_textentry", {GetDisableUse = function() return true end})).to.beTrue()
				expect(busy("gmod_wire_textentry", {})).to.beFalse() -- cannot say: the prompt stays
			end
		},
		{
			-- fails when the lever keeps the prompt while somebody holds it (its User is set: Use returns at once), or hides it when nobody does
			name = "the lever has no prompt while a player is using it",
			func = function()
				local user = {IsValid = function() return true end}

				expect(busy("gmod_wire_lever", {GetNWEntity = function() return user end})).to.beTrue()
				expect(busy("gmod_wire_lever", {GetNWEntity = function() return NULL end})).to.beFalse()
				expect(busy("gmod_wire_lever", {})).to.beFalse()
			end
		},
		{
			-- fails when the explosives are not dangers, when an unarmed one warns, or when the countdown does not
			name = "the Wire explosive is a danger while its countdown runs (exploding) and not before",
			func = function()
				local entry = API.GetDanger(wire("gmod_wire_explosive"))

				expect(entry ~= nil).to.beTrue()
				expect(entry.danger.armed(wire("gmod_wire_explosive", {exploding = true}))).to.beTrue()
				expect(entry.danger.armed(wire("gmod_wire_explosive", {exploding = false}))).to.beFalse()
				expect(entry.danger.armed(wire("gmod_wire_explosive", {}))).to.beFalse()
			end
		},
		{
			-- fails when the player who built it is not its owner for the warning (Wire keeps him in GetPlayer, not in SetOwner)
			name = "the owner of a Wire explosive is its GetPlayer()",
			func = function()
				local ply = {IsValid = function() return true end}
				local entry = API.GetDanger(wire("gmod_wire_explosive"))

				expect(entry.danger.ownerOf(wire("gmod_wire_explosive", {GetPlayer = function() return ply end}))).to.equal(ply)
				expect(entry.danger.ownerOf(wire("gmod_wire_explosive", {}))).to.beNil()
			end
		},
		{
			-- fails when the patch uses a match function for Wire (a match is asked about every entity of a class no entry took: thousands with a duplicator)
			name = "no entry of the patch uses a match function (Wire has thousands of entities)",
			func = function()
				for _, class in ipairs({"gmod_wire_button", "gmod_wire_lever", "gmod_wire_keyboard", "gmod_wire_textentry", "gmod_wire_digitalscreen"}) do
					expect(usable(class).match).to.beNil()
				end

				expect(API.GetDanger(wire("gmod_wire_explosive")).match).to.beNil()
			end
		},
		{
			-- fails when a second load of the file stacks a second entry or breaks the first
			name = "loading the file again replaces its entries (a hot reload)",
			func = function()
				include("grymod/compat/tools/sh_wire.lua")
				include("grymod/compat/tools/sh_wire.lua")

				expect(usable("gmod_wire_button").icon).to.equal("use")
				expect(API.GetDanger(wire("gmod_wire_explosive")) ~= nil).to.beTrue()
			end
		}
	}
}
