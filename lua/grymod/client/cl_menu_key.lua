-- The key of the quick menu. The engine does not let Lua run `bind`, so the key can be chosen two ways: the
-- usual `bind <key> +crysishud`, or the gry_menu_key setting, picked with a key picker (this file's prompt and the
-- options panel). While neither is set, a small prompt asks for a key every time the player spawns.
--
-- The chosen key is seen by the key factory (cl_key_binder.lua), which polls it: the hooks PlayerButtonDown / PlayerButtonUp are not called
-- in a single player game (cl_predict 0). A key bound with `bind <key> +crysishud` reaches the console command, which works everywhere.

GryMod = GryMod or {}

local Key

Key = GryMod.KeyBinder.New{
	convar = "gry_menu_key",
	description = "Key that opens the quick menu (a button code, 0 = none; `bind <key> +crysishud` works too)",
	command = "+crysishud",
	title = "GryMod quick menu",
	text = "It is where you change the mode of the suit (armor, speed, cloak, strength).\nPress the key you want to open it with, now. You can change it later in the GryMod options\n(or bind a key to +crysishud in the console).",
	heading = "Your suit's quick menu has no key yet",
	modal = true,
	-- the chosen key goes down or up: the menu opens or applies
	press = function(down)
		local chosen = Key.Chosen()

		Key.Track(chosen, down)
		Key.Handle(chosen, down)
	end,
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

-- The quick menu opened by a `bind <key> +crysishud` (the command, not the hooks: they are not called without prediction): the key that is
-- down and bound to the command is the one to poll for its release.
function Key.TrackBinding()
	for code = 1, BUTTON_CODE_LAST or 0 do
		if input.IsButtonDown(code) and input.LookupKeyBinding(code) == "+crysishud" then
			Key.pressed = code

			return code
		end
	end

	return nil
end

function Key.Pressed()
	return Key.pressed
end

function Key.Forget()
	Key.pressed = nil
end

-- The button that opens the menu is remembered while it is down (the hooks, when the engine calls them: a game with prediction; the chosen
-- key's press and a bind's command also do it, see above). The press itself is the factory's.
hook.Add("PlayerButtonDown", "GRYMENUKEY", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() or gui.IsGameUIVisible() or IsValid(vgui.GetKeyboardFocus()) then
		return
	end

	Key.Track(button, true)
end)

-- The release is passed on to the menu whenever the hook gets it. It does not get it when a panel (the chat, the Q or C
-- menu) has the keyboard: the menu then cancels itself (cl_hud_quickmenu_flash.lua) so it never stays open.
hook.Add("PlayerButtonUp", "GRYMENUKEY", function(ply, button)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	Key.Track(button, false)
end)
