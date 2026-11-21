-- A key chosen in the options: a saved setting (a button code, 0 = none), the question "does the player have a way to use
-- it" (a `bind <key> <command>` in the console counts too: the engine does not let Lua run `bind`), the refusals, and a small
-- prompt with a key picker. The quick menu key (cl_menu_key.lua) and the suit zoom key (cl_suit_zoom.lua) are two objects
-- made here.
--
-- GryMod.KeyBinder.New{
--     convar      = name of the saved setting,
--     description = its help text,
--     command     = the console command whose bind also counts (e.g. "+crysishud"),
--     title, text = the prompt's title and text,
--     y           = the top of the prompt (optional: two prompts must not sit on each other),
--     active      = function, whether the prompt is wanted at all (optional, default yes),
--     refuse      = function(code), true for a key that must not be taken (optional: the other key's, for example)
-- }

GryMod = GryMod or {}

local Binder = {}
GryMod.KeyBinder = Binder

function Binder.New(options)
	local Key = {}
	local convar = CreateClientConVar(options.convar, "0", true, false, options.description)

	Key.convar = convar

	-- The key chosen (a button code, 0 = none).
	function Key.Chosen()
		return convar:GetInt()
	end

	-- Whether the player has a way to use the key.
	function Key.IsBound()
		return input.LookupBinding(options.command) ~= nil or convar:GetInt() > 0
	end

	function Key.KeyName(code)
		if not code or code <= 0 then
			return "none"
		end

		return string.upper(input.GetKeyName(code) or "?")
	end

	-- Saves the key; Escape, "no key" and the keys the owner refuses are not taken. Closes the prompt.
	function Key.SetKey(code)
		if not code or code <= 0 or code == KEY_ESCAPE or (options.refuse and options.refuse(code)) then
			return false
		end

		convar:SetInt(code)
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
		frame:SetTitle(options.title)
		frame:SetSize(340, 130)
		frame:SetPos(ScrW() - 360, options.y or 40)
		frame:SetDeleteOnClose(true)
		frame:SetKeyboardInputEnabled(true)

		local label = vgui.Create("DLabel", frame)
		label:SetText(options.text)
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

	-- Asks for a key when there is none (and the owner wants it asked).
	function Key.MaybePrompt()
		if (options.active == nil or options.active()) and not Key.IsBound() then
			Key.ShowPrompt()
		end
	end

	return Key
end
