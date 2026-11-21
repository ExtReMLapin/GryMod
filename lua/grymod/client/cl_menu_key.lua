-- The key of the quick menu. The engine does not let Lua run `bind`, so the key can be chosen two ways: the
-- usual `bind <key> +crysishud`, or the gry_menu_key setting, picked with a key picker (this file's prompt and the
-- options panel). While neither is set, a small prompt asks for a key every time the player spawns.

GryMod = GryMod or {}

local Key = GryMod.KeyBinder.New{
	convar = "gry_menu_key",
	description = "Key that opens the quick menu (a button code, 0 = none; `bind <key> +crysishud` works too)",
	command = "+crysishud",
	title = "GryMod quick menu",
	text = "No key opens the quick menu yet.\nClick the box and press the key you want\n(or bind one to +crysishud in the console).",
	-- the suit zoom key is another key (when both are chosen they must differ)
	refuse = function(code)
		return GryMod.SuitZoom ~= nil and GryMod.SuitZoom.Key.Chosen() == code
	end
}

GryMod.MenuKey = Key

local keyConVar = Key.convar

-- A button went down or up: opens or applies the menu when it is the chosen key. Returns whether it was.
function Key.Handle(button, down)
	local chosen = keyConVar:GetInt()

	if chosen <= 0 or button ~= chosen then
		return false
	end

	GryMod.CryOpenClose(LocalPlayer(), down and "+crysishud" or "-crysishud")

	return true
end

-- The button that opened the menu, kept until it goes up: the chosen key, or the key bound to +crysishud. The menu polls it
-- (Key.Pressed) because the release is not passed on when the chat or a panel took the keyboard meanwhile.
function Key.Track(button, down)
	if down then
		if button == keyConVar:GetInt() or input.LookupKeyBinding(button) == "+crysishud" then
			Key.pressed = button
		end
	elseif button == Key.pressed then
		Key.pressed = nil
	end
end

function Key.Pressed()
	return Key.pressed
end

function Key.Forget()
	Key.pressed = nil
end

-- (a press can be run again while the engine predicts the same command: only the first time counts)
hook.Add("PlayerButtonDown", "GRYMENUKEY", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then
		return
	end

	Key.Track(button, true)
	Key.Handle(button, true)
end)

-- The release is passed on to the menu whenever the hook gets it. It does not get it when a panel (the chat, the Q or C
-- menu) has the keyboard: the menu then cancels itself (cl_hud_quickmenu_flash.lua) so it never stays open.
hook.Add("PlayerButtonUp", "GRYMENUKEY", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	Key.Track(button, false)
	Key.Handle(button, false)
end)
