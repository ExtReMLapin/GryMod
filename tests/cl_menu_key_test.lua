-- Tests of the quick menu key (GryMod.MenuKey), GLuaTest format, client realm.
-- The engine blocks `bind` from Lua, so the addon has its own key setting (gry_menu_key) next to the usual
-- `bind <key> +crysishud`, and a prompt that asks for a key while neither is set.

local function reset()
	GryMod.MenuKey.HidePrompt()
end

return {
	groupName = "GryMod quick menu key",
	cases = {
		{
			name = "the key setting is created to be saved between sessions and starts unset",
			func = function(state)
				local created = {}
				local realCreate = CreateClientConVar
				CreateClientConVar = function(name, default, shouldsave, ...)
					created[name] = {default = default, save = shouldsave}

					return realCreate(name, default, shouldsave, ...)
				end

				include("grymod/client/cl_menu_key.lua")
				CreateClientConVar = realCreate

				expect(created.gry_menu_key.save).to.beTrue()
				expect(created.gry_menu_key.default).to.equal("0")
			end
		},
		{
			name = "the menu counts as bound with a +crysishud bind or with the setting, and as unbound with neither",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local lookup, key = input.LookupBinding, convar:GetInt()

				input.LookupBinding = function() return nil end
				convar:SetInt(0)
				expect(K.IsBound()).to.beFalse()
				input.LookupBinding = function() return "MOUSE3" end
				expect(K.IsBound()).to.beTrue()
				input.LookupBinding = function() return nil end
				convar:SetInt(KEY_F7)
				expect(K.IsBound()).to.beTrue()

				input.LookupBinding = lookup
				convar:SetInt(key)
			end
		},
		{
			name = "the chosen key opens the menu on press and applies it on release; other keys and an unset key do nothing",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local key, openClose = convar:GetInt(), GryMod.CryOpenClose
				local calls = {}
				GryMod.CryOpenClose = function(_, command) calls[#calls + 1] = command end

				convar:SetInt(KEY_F7)
				expect(K.Handle(KEY_F7, true)).to.beTrue()
				expect(K.Handle(KEY_F7, false)).to.beTrue()
				expect(K.Handle(KEY_F8, true)).to.beFalse()
				expect(calls[1]).to.equal("+crysishud")
				expect(calls[2]).to.equal("-crysishud")
				expect(#calls).to.equal(2)

				convar:SetInt(0)
				expect(K.Handle(0, true)).to.beFalse()
				expect(K.Handle(BUTTON_CODE_NONE or 0, true)).to.beFalse()
				expect(#calls).to.equal(2)

				GryMod.CryOpenClose = openClose
				convar:SetInt(key)
			end
		},
		{
			name = "the button that opened the menu is remembered until it is released: the chosen key, or the key bound to +crysishud",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local key, lookup, pressed = convar:GetInt(), input.LookupKeyBinding, K.pressed
				input.LookupKeyBinding = function(button) return button == KEY_F9 and "+crysishud" or nil end

				local ok, err = pcall(function()
					convar:SetInt(KEY_F7)
					K.pressed = nil
					expect(K.Pressed()).to.beNil()

					K.Track(KEY_F8, true) -- not the menu's key
					expect(K.Pressed()).to.beNil()
					K.Track(KEY_F7, true)
					expect(K.Pressed()).to.equal(KEY_F7)
					K.Track(KEY_F8, false) -- another key going up changes nothing
					expect(K.Pressed()).to.equal(KEY_F7)
					K.Track(KEY_F7, false)
					expect(K.Pressed()).to.beNil()

					K.Track(KEY_F9, true) -- bind F9 +crysishud
					expect(K.Pressed()).to.equal(KEY_F9)
					K.Forget()
					expect(K.Pressed()).to.beNil()
				end)

				input.LookupKeyBinding = lookup
				convar:SetInt(key)
				K.pressed = pressed

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the key hooks only act on the first prediction of a press, so a press is not handled several times",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local key, openClose, first, pressed = convar:GetInt(), GryMod.CryOpenClose, IsFirstTimePredicted, K.pressed
				local calls = {}
				GryMod.CryOpenClose = function(_, command) calls[#calls + 1] = command end
				convar:SetInt(KEY_F7)

				local ok, err = pcall(function()
					local down = hook.GetTable().PlayerButtonDown["GRYMENUKEY"]
					local up = hook.GetTable().PlayerButtonUp["GRYMENUKEY"]

					IsFirstTimePredicted = function() return false end
					down(LocalPlayer(), KEY_F7)
					up(LocalPlayer(), KEY_F7)
					expect(#calls).to.equal(0)

					IsFirstTimePredicted = function() return true end
					down(LocalPlayer(), KEY_F7)
					expect(calls[1]).to.equal("+crysishud")
					expect(K.Pressed()).to.equal(KEY_F7)
					up(LocalPlayer(), KEY_F7)
					expect(calls[2]).to.equal("-crysishud")
					expect(K.Pressed()).to.beNil()
				end)

				IsFirstTimePredicted = first
				GryMod.CryOpenClose = openClose
				convar:SetInt(key)
				K.pressed = pressed

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "choosing a key saves it and closes the prompt; Escape and nothing are refused",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local key = convar:GetInt()
				K.ShowPrompt()
				expect(IsValid(K.panel)).to.beTrue()

				expect(K.SetKey(KEY_ESCAPE)).to.beFalse()
				expect(K.SetKey(0)).to.beFalse()
				expect(IsValid(K.panel)).to.beTrue()

				expect(K.SetKey(KEY_F7)).to.beTrue()
				expect(convar:GetInt()).to.equal(KEY_F7)
				expect(IsValid(K.panel)).to.beFalse()

				convar:SetInt(key)
				reset()
			end
		},
		{
			name = "the prompt shows once, only while no key is set, and goes away on request",
			func = function(state)
				local K = GryMod.MenuKey
				local convar = GetConVar("gry_menu_key")
				local lookup, key = input.LookupBinding, convar:GetInt()
				input.LookupBinding = function() return nil end
				convar:SetInt(0)
				reset()

				K.MaybePrompt()
				local first = K.panel
				expect(IsValid(first)).to.beTrue()
				K.MaybePrompt()
				expect(K.panel).to.equal(first) -- no second panel
				K.HidePrompt()
				expect(IsValid(first)).to.beFalse()

				-- bound: nothing to ask
				input.LookupBinding = function() return "MOUSE3" end
				K.MaybePrompt()
				expect(IsValid(K.panel)).to.beFalse()

				input.LookupBinding = lookup
				convar:SetInt(key)
				reset()
			end
		},
		{
			name = "the key name is readable, and says so when none is set",
			func = function(state)
				local K = GryMod.MenuKey
				expect(K.KeyName(KEY_F7)).to.equal("F7")
				expect(K.KeyName(0)).to.equal("none")
			end
		}
	}
}
