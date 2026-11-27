-- Tests of the key factory (GryMod.KeyBinder), GLuaTest format, client realm. The quick menu key and the suit zoom key are two
-- objects of it: the setting, the "is a key bound" question, the refusals, the prompt with its key picker.

local made

local function make(options)
	options = options or {}
	options.convar = "gry_test_binder_key"
	options.description = "test"
	options.command = "+gry_test_binder"
	options.title = options.title or "Test keys"
	options.text = options.text or "No key yet."

	made = GryMod.KeyBinder.New(options)

	return made
end

return {
	groupName = "GryMod key factory",
	beforeEach = function(state)
		-- a world of the test's own: the situation read by the factory, and the key the input system reports. Everything put back.
		state.down = false
		state.withWorld = function(fn)
			local world = {pause = false, console = false, cursor = false, focusPanel = false, typing = false, focus = true}
			local realRead, realDown = GryMod.KeyBinder.Read, input.IsButtonDown

			GryMod.KeyBinder.Read = function(sit)
				for k, v in pairs(world) do
					sit[k] = v
				end

				return sit
			end
			input.IsButtonDown = function() return state.down end

			local ok, err = pcall(fn, world)
			GryMod.KeyBinder.Read, input.IsButtonDown = realRead, realDown

			if not ok then
				error(err, 0)
			end
		end
	end,
	afterEach = function(state)
		if made then
			made.HidePrompt()
			made.convar:SetInt(0)

			if made.Reset then
				made.Reset()
			end
		end
	end,
	cases = {
		{
			name = "a key made by the factory has a saved setting that starts at 0 (none), and counts as bound with a bind of its command or with a key set",
			func = function(state)
				local created = {}
				local realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, ...)
					created[name] = {default = default, save = shouldsave}

					return realCreate(name, default, shouldsave, ...)
				end

				local ok, err = pcall(make)
				CreateClientConVar = realCreate

				if not ok then
					error(err, 0)
				end

				expect(created.gry_test_binder_key.save).to.beTrue()
				expect(created.gry_test_binder_key.default).to.equal("0")

				local lookup = input.LookupBinding
				local asked

				ok, err = pcall(function()
					input.LookupBinding = function(command) asked = command return nil end
					expect(made.IsBound()).to.beFalse()
					expect(asked).to.equal("+gry_test_binder")
					input.LookupBinding = function() return "MOUSE3" end
					expect(made.IsBound()).to.beTrue()
					input.LookupBinding = function() return nil end
					made.convar:SetInt(KEY_F7)
					expect(made.IsBound()).to.beTrue()
					expect(made.Chosen()).to.equal(KEY_F7)
				end)

				input.LookupBinding = lookup

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "SetKey saves a key and closes the prompt; 0, nothing, Escape and what the refuse function says are refused",
			func = function(state)
				make({refuse = function(code) return code == KEY_F9 end})
				made.ShowPrompt()
				expect(IsValid(made.panel)).to.beTrue()

				expect(made.SetKey(0)).to.beFalse()
				expect(made.SetKey(nil)).to.beFalse()
				expect(made.SetKey(KEY_ESCAPE)).to.beFalse()
				expect(made.SetKey(KEY_F9)).to.beFalse()
				expect(made.Chosen()).to.equal(0)
				expect(IsValid(made.panel)).to.beTrue()

				expect(made.SetKey(KEY_F7)).to.beTrue()
				expect(made.Chosen()).to.equal(KEY_F7)
				expect(IsValid(made.panel)).to.beFalse()
			end
		},
		{
			-- fails when a prompt that is asked to be a modal one (the quick menu: a player who does not know where the menu is must see it) stays a small frame in a corner, or does not wait
			-- for the key at once (the player had to click the box first), or has no way to say "later"
			name = "a modal prompt is big and in the middle of the screen, already waits for the key, and still has a Later button",
			func = function(state)
				make({modal = true, title = "Quick menu", text = "Press the key that opens the quick menu.", heading = "Your suit's quick menu has no key"})
				made.ShowPrompt()

				local frame = made.panel

				expect(IsValid(frame)).to.beTrue()

				local w, h = frame:GetSize()
				local x, y = frame:GetPos()

				expect(w >= 480 and h >= 220).to.beTrue()
				expect(math.abs(x - (ScrW() - w) / 2) <= 2).to.beTrue()
				expect(math.abs(y - (ScrH() - h) / 2) <= 2).to.beTrue()

				local binder, later

				for _, child in ipairs(frame:GetChildren()) do
					if child.ClassName == "DBinder" then
						binder = child
					elseif child.ClassName == "DButton" and child:GetText() == "Later" then
						later = child
					end
				end

				expect(binder ~= nil).to.beTrue()
				expect(binder.Trapping == true).to.beTrue()
				expect(later ~= nil and later:GetText() == "Later").to.beTrue()

				made.HidePrompt()

				-- a plain prompt stays the small one it was
				make({title = "Zoom keys", text = "Pick the zoom key."})
				made.ShowPrompt()
				expect(made.panel:GetWide() < 400).to.beTrue()
				made.HidePrompt()
			end
		},
		{
			-- fails when the modal prompt has no way for a player to say "stop asking" (the owner: "even if I did not bind, go away": it is saved), when that choice does not silence
			-- the prompt at the next spawn, or when an optional second key (the binoculars' zoom) is not offered in the same prompt
			name = "a modal prompt can offer a second, optional key and a \"do not ask again\" box: ticking it is saved and the prompt stays away",
			func = function(state)
				local second = GryMod.KeyBinder.New{convar = "gry_test_binder_key2", description = "test", command = "+gry_test_binder2", title = "Second", text = "second"}
				local silence = "gry_test_binder_silence"
				local lookup = input.LookupBinding

				make({modal = true, silence = silence, extra = function() return second end, extraLabel = "Binoculars zoom key (optional)", extraRefuse = function(code) return code == KEY_F7 end, extraRefuseText = "No"})

				local ok, err = pcall(function()
					input.LookupBinding = function() return nil end
					expect(GetConVar(silence):GetBool()).to.beFalse()
					made.MaybePrompt()
					expect(IsValid(made.panel)).to.beTrue()

					local binders, box = {}

					local function walk(panel)
						for _, child in ipairs(panel:GetChildren()) do
							if child.ClassName == "DBinder" then
								binders[#binders + 1] = child
							elseif child.ClassName == "DCheckBoxLabel" then
								box = child
							end

							walk(child)
						end
					end

					walk(made.panel)
					expect(#binders).to.equal(2) -- the key of the menu and the optional second one
					expect(box ~= nil).to.beTrue()

					-- the second picker sets the second key; Escape and 0 are refused as for any key
					binders[2]:OnChange(KEY_F8)
					expect(second.Chosen()).to.equal(KEY_F8)

					-- a key that the second one must not be (the game's own zoom key) is not taken
					binders[2]:OnChange(KEY_F7)
					expect(second.Chosen()).to.equal(KEY_F8)

					-- ticking the box is saved at once, and the prompt does not come back
					box:SetChecked(true)
					box:OnChange(true)
					expect(GetConVar(silence):GetBool()).to.beTrue()
					made.HidePrompt()
					made.MaybePrompt()
					expect(IsValid(made.panel)).to.beFalse()

					-- and it can be changed back (the options panel's box): the prompt asks again
					RunConsoleCommand(silence, "0")
				end)

				input.LookupBinding = lookup
				RunConsoleCommand(silence, "0")
				RunConsoleCommand("gry_test_binder_key2", "0")
				made.HidePrompt()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the prompt has its own title, text and place, shows once, is only asked for while no key is set and the active function says so, and goes away on request",
			func = function(state)
				local active = true
				make({title = "Zoom keys", text = "Pick the zoom key.", y = 200, active = function() return active end})
				local lookup = input.LookupBinding

				local ok, err = pcall(function()
					input.LookupBinding = function() return nil end

					made.MaybePrompt()
					local first = made.panel
					expect(IsValid(first)).to.beTrue()
					expect(first:GetTitle()).to.equal("Zoom keys")
					expect(select(2, first:GetPos())).to.equal(200)
					made.MaybePrompt()
					expect(made.panel).to.equal(first)
					made.HidePrompt()
					expect(IsValid(first)).to.beFalse()

					-- not asked while the owner says no, nor with a key set
					active = false
					made.MaybePrompt()
					expect(IsValid(made.panel)).to.beFalse()
					active = true
					made.convar:SetInt(KEY_F7)
					made.MaybePrompt()
					expect(IsValid(made.panel)).to.beFalse()
				end)

				input.LookupBinding = lookup

				if not ok then
					error(err, 0)
				end
			end
		},
		-- ------------------------------------------------------------------------------------------------------------------
		-- Polling: the hooks PlayerButtonDown / PlayerButtonUp are "predicted": a single player game with cl_predict 0 (the engine
		-- sets it in a single player game: measured) never calls them on the client, while input.IsButtonDown reads the key all the same.
		-- ------------------------------------------------------------------------------------------------------------------
		{
			name = "Decide (pure): a key that goes down gives a press when a press is allowed; one that goes down while it is not allowed gives nothing (and is still known as down); a key that goes up gives a release only when its press was taken; no change gives nothing",
			func = function(state)
				local D = GryMod.KeyBinder.Decide
				-- (known, isDown, allowed, taken)
				expect(D(false, true, true, false)).to.equal("press")
				expect(D(false, true, false, false)).to.equal("skip")
				expect(D(true, false, true, true)).to.equal("release")
				expect(D(true, false, false, true)).to.equal("release")
				expect(D(true, false, true, false)).to.equal("skip")
				expect(D(true, true, true, true)).to.beNil()
				expect(D(false, false, true, false)).to.beNil()
				expect(D(true, true, false, false)).to.beNil()
			end
		},
		{
			name = "Blocked (pure): the game menu, the console, a visible cursor, a panel with the keyboard, the chat and a window without the focus each refuse a press, with their reason; a calm world refuses nothing",
			func = function(state)
				local B = GryMod.KeyBinder.Blocked
				local calm = {pause = false, console = false, cursor = false, focusPanel = false, typing = false, focus = true}
				expect(B(calm)).to.beNil()

				for _, case in ipairs({{"pause", true, "pause"}, {"console", true, "console"}, {"cursor", true, "cursor"}, {"focusPanel", true, "panel"},
					{"typing", true, "chat"}, {"focus", false, "focus"}}) do
					local sit = {pause = false, console = false, cursor = false, focusPanel = false, typing = false, focus = true}
					sit[case[1]] = case[2]
					expect(B(sit)).to.equal(case[3])
				end
			end
		},
		{
			name = "Read fills the situation from the world the engine gives (one table, filled again each time)",
			func = function(state)
				local sit = {}
				expect(GryMod.KeyBinder.Read(sit)).to.equal(sit)
				for _, field in ipairs({"pause", "console", "cursor", "focusPanel", "typing", "focus"}) do
					expect(type(sit[field])).to.equal("boolean")
				end
			end
		},
		{
			name = "polling: the key chosen is read with input.IsButtonDown once per call, a press calls the owner's function with true and a release with false (a mouse button included), each once however many frames the key stays down",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				state.withWorld(function(world)
					for _, button in ipairs({KEY_F7, MOUSE_MIDDLE}) do
						calls = {}
						made.convar:SetInt(button)
						local read = {}
						input.IsButtonDown = function(b) read[#read + 1] = b return state.down end

						state.down = false
						made.Poll()
						expect(#calls).to.equal(0)
						state.down = true
						made.Poll()
						made.Poll()
						made.Poll()
						expect(#calls).to.equal(1)
						expect(calls[1]).to.beTrue()
						state.down = false
						made.Poll()
						made.Poll()
						expect(#calls).to.equal(2)
						expect(calls[2]).to.beFalse()

						for _, b in ipairs(read) do
							expect(b).to.equal(button)
						end
					end
				end)
			end
		},
		{
			name = "a press seen by the hook and by the poll is one press, and so is a release (whichever comes first)",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				made.convar:SetInt(KEY_F7)
				state.withWorld(function(world)
					-- the hook first, then the poll that finds the key down
					state.down = false
					made.Poll()
					made.Hook(KEY_F7, true)
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)
					-- the poll first (the hook never comes): then the hook of the same press, in the same frame
					made.Hook(KEY_F7, false)
					expect(#calls).to.equal(2)
					state.down = false
					made.Poll()
					expect(#calls).to.equal(2)

					state.down = true
					made.Poll()
					made.Hook(KEY_F7, true)
					expect(#calls).to.equal(3)
					state.down = false
					made.Poll()
					made.Hook(KEY_F7, false)
					expect(#calls).to.equal(4)
					expect(calls[3]).to.beTrue()
					expect(calls[4]).to.beFalse()
				end)
			end
		},
		{
			name = "a key with a default (options.default, a function giving a button or nil): while no key is chosen the poll reads the default and its edges are the presses; a key chosen replaces it; Chosen stays 0, so the saved setting is never written for the player; with no default and no key nothing is read",
			func = function(state)
				local calls = {}
				local defaultKey = KEY_H
				make({press = function(down) calls[#calls + 1] = down end, default = function() return defaultKey end})
				state.withWorld(function(world)
					local read = {}
					input.IsButtonDown = function(b) read[#read + 1] = b return state.down end

					made.convar:SetInt(0)
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					made.Poll()
					state.down = false
					made.Poll()
					expect(#calls).to.equal(2)
					expect(calls[1]).to.beTrue()
					expect(calls[2]).to.beFalse()
					expect(made.Chosen()).to.equal(0)
					expect(made.convar:GetInt()).to.equal(0)
					expect(made.Effective()).to.equal(KEY_H)

					for _, b in ipairs(read) do
						expect(b).to.equal(KEY_H)
					end

					-- a key chosen replaces the default: the default button is not read any more
					calls, read = {}, {}
					made.convar:SetInt(KEY_F7)
					expect(made.Effective()).to.equal(KEY_F7)
					state.down = false
					made.Poll()
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)

					for _, b in ipairs(read) do
						expect(b).to.equal(KEY_F7)
					end

					-- no key, and the default says nothing: nothing is read
					made.Reset()
					made.convar:SetInt(0)
					defaultKey = nil
					calls, read = {}, {}
					expect(made.Effective()).to.equal(0)
					made.Poll()
					made.Poll()
					expect(#read).to.equal(0)
					expect(#calls).to.equal(0)
				end)
			end
		},
		{
			name = "a default that changes while it is held (the player binds the key to something else) is let go, the new default is only known, and a press that was down when it appeared presses nothing; the hook of the engine takes the default too",
			func = function(state)
				local calls = {}
				local defaultKey = KEY_H
				make({press = function(down) calls[#calls + 1] = down end, default = function() return defaultKey end})
				state.withWorld(function(world)
					input.IsButtonDown = function() return state.down end
					made.convar:SetInt(0)

					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)

					defaultKey = KEY_J
					made.Poll()
					expect(#calls).to.equal(2)
					expect(calls[2]).to.beFalse()
					-- (still down: the new key presses nothing until it is let go and pressed again)
					made.Poll()
					expect(#calls).to.equal(2)
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(3)

					-- the hook
					made.Reset()
					calls = {}
					defaultKey = KEY_H
					state.down = false
					made.Poll()
					made.Hook(KEY_H, true)
					expect(#calls).to.equal(1)
					made.Hook(KEY_J, true)
					expect(#calls).to.equal(1)
					made.Hook(KEY_H, false)
					expect(#calls).to.equal(2)
				end)
			end
		},
		{
			name = "Conflict (pure, from the engine's binds): a key that has a bind of the game gives it, a free key, the key of our own command, an empty bind and no key give nothing; ConflictText says what the key already does",
			func = function(state)
				local B = GryMod.KeyBinder
				local lookup = input.LookupKeyBinding
				local binds = {[KEY_B] = "+zoom", [KEY_F7] = "+gry_zoom", [KEY_F8] = "", [KEY_F9] = "+crysishud"}

				input.LookupKeyBinding = function(code) return binds[code] end

				local ok, err = pcall(function()
					expect(B.Conflict(KEY_B, "+gry_zoom")).to.equal("+zoom")
					expect(B.Conflict(KEY_F9, "+gry_zoom")).to.equal("+crysishud")
					expect(B.Conflict(KEY_F7, "+gry_zoom")).to.beNil()
					expect(B.Conflict(KEY_F8, "+gry_zoom")).to.beNil()
					expect(B.Conflict(KEY_H, "+gry_zoom")).to.beNil()
					expect(B.Conflict(0, "+gry_zoom")).to.beNil()
					expect(B.Conflict(nil, "+gry_zoom")).to.beNil()

					local text = B.ConflictText(KEY_B, "+gry_zoom")
					expect(string.find(text, "already bound to +zoom", 1, true)).toNot.beNil()
					expect(string.find(text, "as well", 1, true)).toNot.beNil()
					expect(B.ConflictText(KEY_H, "+gry_zoom")).to.beNil()
				end)

				input.LookupKeyBinding = lookup

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the hook only takes the chosen key, and nothing while no key is chosen",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				state.withWorld(function(world)
					made.convar:SetInt(KEY_F7)
					made.Hook(KEY_F8, true)
					expect(#calls).to.equal(0)
					made.convar:SetInt(0)
					made.Hook(KEY_F7, true)
					made.Hook(0, true)
					expect(#calls).to.equal(0)
				end)
			end
		},
		{
			name = "a key pressed while the chat, a panel with the keyboard, a visible cursor, a menu, the console or another window is up is ignored, and its release is not a release",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				made.convar:SetInt(KEY_F7)
				state.withWorld(function(world)
					for _, field in ipairs({{"typing", true}, {"focusPanel", true}, {"cursor", true}, {"pause", true}, {"console", true}, {"focus", false}}) do
						world.typing, world.focusPanel, world.cursor, world.pause, world.console, world.focus = false, false, false, false, false, true
						world[field[1]] = field[2]
						calls = {}
						state.down = false
						made.Poll()
						state.down = true
						made.Poll()
						expect(#calls).to.equal(0)
						state.down = false
						made.Poll()
						expect(#calls).to.equal(0)
					end
				end)
			end
		},
		{
			name = "a key that is still down when the panel that took it is closed does not press: it must be let go and pressed again",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				made.convar:SetInt(KEY_F7)
				state.withWorld(function(world)
					world.typing = true
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					world.typing = false
					made.Poll()
					made.Poll()
					expect(#calls).to.equal(0)
					-- a hook of that press reaching us late does not press either
					made.Hook(KEY_F7, true)
					expect(#calls).to.equal(0)

					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)
					expect(calls[1]).to.beTrue()
				end)
			end
		},
		{
			name = "a release the engine never sent (a panel took the keyboard after the press) is found by the poll, whatever is on screen",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				made.convar:SetInt(KEY_F7)
				state.withWorld(function(world)
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)
					world.typing, world.cursor = true, true
					state.down = false
					made.Poll()
					expect(#calls).to.equal(2)
					expect(calls[2]).to.beFalse()
				end)
			end
		},
		{
			name = "a key chosen while it is down does not press; a key changed or cleared while the old one is down releases it",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				state.withWorld(function(world)
					state.down = true
					made.convar:SetInt(KEY_F7)
					made.Poll()
					expect(#calls).to.equal(0)
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(1)
					-- another key is chosen while this one is down: released
					made.convar:SetInt(KEY_F8)
					made.Poll()
					expect(#calls).to.equal(2)
					expect(calls[2]).to.beFalse()
					-- and the same when it is cleared
					made.convar:SetInt(KEY_F7)
					state.down = false
					made.Poll()
					state.down = true
					made.Poll()
					expect(#calls).to.equal(3)
					made.convar:SetInt(0)
					made.Poll()
					expect(#calls).to.equal(4)
					expect(calls[4]).to.beFalse()
				end)
			end
		},
		{
			name = "with no key chosen the poll reads nothing (no input call, no situation read), and PollAll polls every key made by the factory",
			func = function(state)
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				state.withWorld(function(world)
					local reads, situations = 0, 0
					input.IsButtonDown = function() reads = reads + 1 return false end
					local realRead = GryMod.KeyBinder.Read
					GryMod.KeyBinder.Read = function(sit) situations = situations + 1 return realRead(sit) end
					-- (the other keys of the addon are the player's: they may be chosen)
					local keys = GryMod.KeyBinder.Keys
					GryMod.KeyBinder.Keys = {test = made}

					local ok, err = pcall(function()
						made.convar:SetInt(0)
						made.Poll()
						GryMod.KeyBinder.PollAll()
						expect(reads).to.equal(0)
						expect(situations).to.equal(0)

						made.convar:SetInt(KEY_F7)
						GryMod.KeyBinder.PollAll()
						expect(reads).to.equal(1)
					end)

					GryMod.KeyBinder.Read = realRead
					GryMod.KeyBinder.Keys = keys

					if not ok then
						error(err, 0)
					end
				end)
			end
		},
		{
			name = "the Think hook that polls the keys exists, and the hooks of the engine are only a second source (first prediction only, the player itself)",
			func = function(state)
				expect(hook.GetTable().Think["GRYKEYPOLL"]).toNot.beNil()
				local calls = {}
				make({press = function(down) calls[#calls + 1] = down end})
				made.convar:SetInt(KEY_F7)
				state.withWorld(function(world)
					local hooks = hook.GetTable()
					local down, up = hooks.PlayerButtonDown["GRYKEYBINDER"], hooks.PlayerButtonUp["GRYKEYBINDER"]
					expect(down).toNot.beNil()
					expect(up).toNot.beNil()

					local first = IsFirstTimePredicted
					local ok, err = pcall(function()
						IsFirstTimePredicted = function() return false end
						down(LocalPlayer(), KEY_F7)
						expect(#calls).to.equal(0)
						IsFirstTimePredicted = function() return true end
						down(Entity(0), KEY_F7)
						expect(#calls).to.equal(0)
						down(LocalPlayer(), KEY_F7)
						expect(#calls).to.equal(1)
						IsFirstTimePredicted = function() return false end
						up(LocalPlayer(), KEY_F7)
						expect(#calls).to.equal(1)
						IsFirstTimePredicted = function() return true end
						up(LocalPlayer(), KEY_F7)
						expect(#calls).to.equal(2)
					end)

					IsFirstTimePredicted = first

					if not ok then
						error(err, 0)
					end
				end)
			end
		},
		{
			name = "the key name is readable, and says so when none is set",
			func = function(state)
				make()
				expect(made.KeyName(KEY_F7)).to.equal("F7")
				expect(made.KeyName(0)).to.equal("none")
			end
		}
	}
}
