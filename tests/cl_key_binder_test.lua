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
	afterEach = function(state)
		if made then
			made.HidePrompt()
			made.convar:SetInt(0)
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
