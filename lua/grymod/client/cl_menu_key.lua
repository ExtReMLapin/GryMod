-- The key of the quick menu. The engine does not let Lua run `bind`, so the key can be chosen two ways: the
-- usual `bind <key> +crysishud`, or the gry_menu_key setting, picked with a key picker (this file's prompt and the
-- options panel). While neither is set, a small prompt asks for a key every time the player spawns.

GryMod = GryMod or {}

local Key = {}
GryMod.MenuKey = Key

local keyConVar = CreateClientConVar("gry_menu_key", "0", true, false, "Key that opens the quick menu (a button code, 0 = none; `bind <key> +crysishud` works too)")

-- Whether the player has a way to open the menu.
function Key.IsBound()
	return input.LookupBinding("+crysishud") ~= nil or keyConVar:GetInt() > 0
end

function Key.KeyName(code)
	if not code or code <= 0 then
		return "none"
	end

	return string.upper(input.GetKeyName(code) or "?")
end

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

-- Saves the key; Escape and "no key" are refused. Closes the prompt.
function Key.SetKey(code)
	if not code or code <= 0 or code == KEY_ESCAPE then
		return false
	end

	keyConVar:SetInt(code)
	Key.HidePrompt()

	return true
end

function Key.HidePrompt()
	if IsValid(Key.panel) then
		Key.panel:Remove()
	end

	Key.panel = nil
end

-- The prompt: a small frame with a key picker, until a key is chosen or the player closes it.
function Key.ShowPrompt()
	if IsValid(Key.panel) then
		return
	end

	local frame = vgui.Create("DFrame")
	frame:SetTitle("GryMod quick menu")
	frame:SetSize(340, 130)
	frame:SetPos(ScrW() - 360, 40)
	frame:SetDeleteOnClose(true)
	frame:SetKeyboardInputEnabled(true)

	local label = vgui.Create("DLabel", frame)
	label:SetText("No key opens the quick menu yet.\nClick the box and press the key you want\n(or bind one to +crysishud in the console).")
	label:SetWrap(true)
	label:SetSize(320, 50)
	label:SetPos(10, 28)

	local binder = vgui.Create("DBinder", frame)
	binder:SetSize(220, 28)
	binder:SetPos(10, 88)
	binder.OnChange = function(_, code)
		Key.SetKey(code)
	end

	local later = vgui.Create("DButton", frame)
	later:SetText("Later")
	later:SetSize(90, 28)
	later:SetPos(240, 88)
	later.DoClick = function()
		Key.HidePrompt()
	end

	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false) -- the binder takes the keyboard when it is clicked
	Key.panel = frame
end

-- Asks for a key when there is none.
function Key.MaybePrompt()
	if not Key.IsBound() then
		Key.ShowPrompt()
	end
end
