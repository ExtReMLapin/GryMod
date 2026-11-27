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
--     refuse      = function(code), true for a key that must not be taken (optional: the other key's, for example),
--     default     = function, the button used while the player has chosen none (a button code, or nil for no default: optional). It is
--                   computed by the owner and never saved in the player's setting: Chosen() stays 0, Effective() gives the button in use,
--     press       = function(down), what the key does: called with true when the key is pressed and false when it is let go
-- }
--
-- HOW A KEY IS SEEN. The hooks PlayerButtonDown / PlayerButtonUp are "predicted" ones: a single player game runs with cl_predict 0
-- (the engine sets it at every map load, measured), and then the client never calls them (measured: input.IsButtonDown(KEY_H) true, the
-- hooks silent; with cl_predict 1, or a game of 2 players, they come). So the key is POLLED: once per frame (Think) the chosen button is read
-- with input.IsButtonDown and its edges are the presses and the releases. The hooks stay as a second source, and one press seen by both
-- counts once. A press is only taken when nothing else has the keyboard or the mouse (the chat, a panel, the console, a menu, a window
-- without the focus): a H typed in the chat does not zoom. A key that was down when such a thing closed does not press: it must be let go
-- and pressed again. A release is always taken (a lost one is found by the poll).

GryMod = GryMod or {}

local Binder = {}
GryMod.KeyBinder = Binder

-- The keys made here, by the name of their setting (a file run again replaces its key).
Binder.Keys = Binder.Keys or {}

-- What a button that changed does. Pure. known: whether we knew the button as down, isDown: what the input says, allowed: whether a press
-- may be taken now, taken: whether a press was taken and not let go yet. Gives "press" (a press to take), "release" (a release to take),
-- "skip" (a change that is not ours to act on: a press refused, a release of a press never taken) or nil (nothing changed).
function Binder.Decide(known, isDown, allowed, taken)
	if isDown == known then
		return nil
	end

	if isDown then
		return allowed and "press" or "skip"
	end

	return taken and "release" or "skip"
end

-- The command the game already has on a button (a `bind` of the player or of the game's own defaults), or nil: a free key, a key bound
-- to the command we are going to put on it (`command`), an empty bind and no key give nothing. Another addon that reads the key with a hook
-- cannot be seen (its hook is an anonymous function): that conflict is not detected.
function Binder.Conflict(code, command)
	if not code or code <= 0 then
		return nil
	end

	local bound = input.LookupKeyBinding(code)

	if bound == nil or bound == "" or bound == command then
		return nil
	end

	return bound
end

-- The warning for a key picked in the options, or nil.
function Binder.ConflictText(code, command)
	local bound = Binder.Conflict(code, command)

	if bound then
		return "This key is already bound to " .. bound .. " in the game (it will do that as well)."
	end

	return nil
end

-- The first reason a press must be refused, from the facts of the situation (pause, console, cursor, focusPanel, typing, focus), or nil.
-- Pure. The binoculars refuse in these cases too (SuitZoom.Reason), the quick menu cancels in them.
function Binder.Blocked(sit)
	if sit.pause then return "pause" end
	if sit.console then return "console" end
	if sit.cursor then return "cursor" end
	if sit.focusPanel then return "panel" end
	if sit.typing then return "chat" end
	if not sit.focus then return "focus" end

	return nil
end

-- Reads the world into a situation (a table that is filled again each time).
function Binder.Read(sit)
	local ply = LocalPlayer()

	sit.pause = gui.IsGameUIVisible()
	sit.console = gui.IsConsoleVisible()
	sit.cursor = vgui.CursorVisible()
	sit.focusPanel = IsValid(vgui.GetKeyboardFocus())
	sit.typing = IsValid(ply) and ply:IsTyping() or false
	sit.focus = system.HasFocus()

	return sit
end

local situation = {}

function Binder.New(options)
	local Key = {}
	local convar = CreateClientConVar(options.convar, "0", true, false, options.description)

	Key.convar = convar

	-- the key as we know it: the button that is polled, whether it is down, whether a press of it was taken and not let go yet
	local button, known, taken = 0, false, false

	-- The key chosen (a button code, 0 = none).
	function Key.Chosen()
		return convar:GetInt()
	end

	-- The button in use: the key chosen, else the default of the owner (if it has one and gives one), else 0. This is the one polled.
	function Key.Effective()
		local chosen = convar:GetInt()

		if chosen > 0 then
			return chosen
		end

		if options.default then
			return options.default() or 0
		end

		return 0
	end

	-- Whether the player has a way to use the key.
	function Key.IsBound()
		return input.LookupBinding(options.command) ~= nil or convar:GetInt() > 0
	end

	-- Forgets the key (a test, a map change that must not press again).
	function Key.Reset()
		button, known, taken = 0, false, false
	end

	local function release()
		if taken then
			taken = false

			if options.press then
				options.press(false)
			end
		end
	end

	-- The key goes down (true) or up (false), as the poll or the hook of the engine says: acts on a change only (the other source may have
	-- said it already). The situation is only read for a press. Returns what was decided.
	function Key.Feed(down)
		local action = Binder.Decide(known, down, down and Binder.Blocked(Binder.Read(situation)) == nil, taken)

		known = down

		if action == "press" then
			taken = true

			if options.press then
				options.press(true)
			end
		elseif action == "release" then
			release()
		end

		return action
	end

	-- Once per frame: the button in use (chosen, else the default) is read, and its edges are fed. Does nothing (and reads nothing) while there
	-- is none.
	function Key.Poll()
		local chosen = Key.Effective()

		if chosen ~= button then
			-- (another key chosen, or none: the old one is let go, and the new one is only known: held while chosen, it presses nothing)
			release()
			button, taken = chosen, false
			known = chosen > 0 and input.IsButtonDown(chosen) or false

			return
		end

		if chosen > 0 then
			Key.Feed(input.IsButtonDown(chosen))
		end
	end

	-- The engine's hooks PlayerButtonDown / PlayerButtonUp (when they come): the button in use only.
	function Key.Hook(code, down)
		local chosen = Key.Effective()

		if chosen > 0 and code == chosen then
			if chosen ~= button then
				-- (a key just chosen, not polled yet: this event is its first sight, a press is a new press)
				release()
				button, taken, known = chosen, false, not down
			end

			Key.Feed(down)
		end
	end

	-- Whether the player has a way to use the key, for the questions asked at every frame: the same answer as IsBound, but the lookup of the
	-- bind (an engine call that walks every key) is made once in half a second, and never while a key is chosen.
	local bound, boundUntil = false, 0

	function Key.IsBoundCached()
		if convar:GetInt() > 0 then
			return true
		end

		local now = RealTime()

		if now >= boundUntil then
			bound, boundUntil = input.LookupBinding(options.command) ~= nil, now + 0.5
		end

		return bound
	end

	-- (a bind just made: the next question looks again)
	function Key.ForgetBinding()
		boundUntil = 0
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

	-- The modal prompt (options.modal: the quick menu, which a new player must find): a big frame in the middle of the screen with a heading, the text, a key picker that ALREADY waits
	-- for the key (the player presses the key he wants, no click needed) and a Later button (asked again at the next spawn).
	local function showModalPrompt()
		local w, h = math.min(560, ScrW() - 40), 250
		local frame = vgui.Create("DFrame")

		frame:SetTitle(options.title)
		frame:SetSize(w, h)
		frame:Center()
		frame:SetDeleteOnClose(true)
		frame:SetDraggable(true)
		frame:ShowCloseButton(false)

		local heading = vgui.Create("DLabel", frame)

		heading:SetFont("DermaLarge")
		heading:SetText(options.heading or options.title)
		heading:SetWrap(true)
		heading:SetAutoStretchVertical(true)
		heading:SetWide(w - 40)
		heading:SetPos(20, 36)

		local label = vgui.Create("DLabel", frame)

		label:SetText(options.text)
		label:SetWrap(true)
		label:SetAutoStretchVertical(true)
		label:SetWide(w - 40)
		label:SetPos(20, 96)

		local binder = vgui.Create("DBinder", frame)

		binder:SetSize(w - 160, 36)
		binder:SetPos(20, h - 60)
		binder.OnChange = function(_, code)
			Key.SetKey(code)
		end

		local later = vgui.Create("DButton", frame)

		later:SetText("Later")
		later:SetSize(110, 36)
		later:SetPos(w - 130, h - 60)
		later.DoClick = function()
			Key.HidePrompt()
		end

		frame:MakePopup()
		binder:DoClick() -- the key picker waits for the key at once
		Key.panel = frame
	end

	-- The prompt: a small frame with a key picker, until a key is chosen or the player closes it (a big one in the middle for a key that must be found: options.modal).
	function Key.ShowPrompt()
		if IsValid(Key.panel) then
			return
		end

		if options.modal then
			showModalPrompt()

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

	Binder.Keys[options.convar] = Key

	return Key
end

-- Every key, once per frame.
function Binder.PollAll()
	for _, key in pairs(Binder.Keys) do
		key.Poll()
	end
end

hook.Add("Think", "GRYKEYPOLL", Binder.PollAll)

-- (the hooks of the engine are a second source: first prediction only, the player itself)
hook.Add("PlayerButtonDown", "GRYKEYBINDER", function(ply, code)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	for _, key in pairs(Binder.Keys) do
		key.Hook(code, true)
	end
end)

hook.Add("PlayerButtonUp", "GRYKEYBINDER", function(ply, code)
	if not IsFirstTimePredicted() or ply ~= LocalPlayer() then
		return
	end

	for _, key in pairs(Binder.Keys) do
		key.Hook(code, false)
	end
end)
