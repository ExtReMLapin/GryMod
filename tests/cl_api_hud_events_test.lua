-- Tests of the HUD events GryMod plays on its own interface (lua/grymod/client/cl_api_hud_events.lua), GLuaTest format, client realm.
-- The rule: an event plays its animation AND its sound together, by the same path, and GryMod's own triggers (damage, mode change,
-- regeneration, energy, water, malfunction...) call GryMod.API.HUDEvent themselves. Everything that touches the live game is stubbed
-- and put back in afterEach: the sounds (GryMod.PlaySound), the states of the effects, the net functions, the player.

local API = GryMod.API
local DamageFx = GryMod.DamageFx
local ModeFX = GryMod.ModeFX
local Modes = GryMod.Modes

local saved = {}
local played
local spy
local listeners = {}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}
end

local savedConVars = {}

local function setConVar(name, value)
	local convar = GetConVar(name)

	if not convar then return end

	if savedConVars[name] == nil then
		savedConVars[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function listen()
	spy = {}
	local id = "gry_api_hud_events_test"
	hook.Add("GryMod_HUDEvent", id, function(name, data) spy[#spy + 1] = {name = name, data = data} end)
	listeners[#listeners + 1] = id
end

local function seen(name)
	for _, event in ipairs(spy or {}) do
		if event.name == name then return event end
	end
end

local function receive(name)
	local receiver = net.Receivers[name]
	assert(receiver, "no receiver for " .. name)
	receiver()
end

local function fakeChannel()
	local channel = {calls = {}}

	for _, name in ipairs({"Play", "Pause", "SetTime", "SetVolume"}) do
		channel[name] = function(self, value)
			self.calls[#self.calls + 1] = name .. (value ~= nil and ("=" .. tostring(value)) or "")
		end
	end

	channel.IsValid = function() return true end

	return channel
end

local function isArmorHitFile(path)
	for _, file in ipairs(GryMod.ArmorHitSounds) do
		if Sound(file) == path then return true end
	end

	return false
end

local ON = {hud = true, screen = true}

return {
	groupName = "GryMod HUD events: animation and sound together (client)",
	beforeEach = function()
		played = {}
		spy = nil
		stub(GryMod, "PlaySound", function(path, scale) played[#played + 1] = {path = path, scale = scale} return true end)
		stub(DamageFx, "State", DamageFx.NewState())
		stub(DamageFx, "Shake", function() end)
		stub(DamageFx, "Options", function() return ON end)
		stub(ModeFX, "State", ModeFX.NewState())
		stub(ModeFX, "Enabled", function() return true end)
		setConVar("gry_sounds", "1")
		GryMod.SoundMix.ResetLimits()
		GryMod.ResetArmorHitSounds()
	end,
	afterEach = function()
		restore()
		hook.Remove("RenderScreenspaceEffects", "GryDamageFx")
		hook.Remove("RenderScreenspaceEffects", "GryModeFx")
		hook.Remove("Think", "GryModSoundhealthregenfadeaway")
		timer.Remove("GryModModeVoice")
		timer.Remove("GryApiDisabled")

		for _, id in ipairs(listeners) do hook.Remove("GryMod_HUDEvent", id) end

		for _, name in ipairs(API.ListHUDEvents and API.ListHUDEvents() or {}) do
			if name:sub(1, 3) == "zz_" then API.UnregisterHUDEvent(name) end
		end

		listeners = {}

		for name, value in pairs(savedConVars) do
			local convar = GetConVar(name)

			if convar then convar:SetString(value) end
		end

		savedConVars = {}
		GryMod.SoundMix.ResetLimits()

		if GryMod.FlashHUD and GryMod.FlashHUD.SetLocalOff then GryMod.FlashHUD.SetLocalOff(false) end

		if GryMod.FlashBoot then GryMod.FlashBoot.Reset() end
	end,
	cases = {
		{
			name = "ListHUDEvents gives the sorted names of every event the HUD plays: the four boot ones and all the effects",
			func = function()
				expect(isfunction(API.ListHUDEvents)).to.beTrue()
				local names = API.ListHUDEvents()
				local expected = {"armor_hit", "boot", "decloak", "disabled", "dive_in", "dive_out", "drown", "enabled", "energy_critical", "jam", "lost", "low_health",
					"malfunction", "mode", "reboot", "regen_start", "regen_stop", "reset"}
				local have = {}

				for _, name in ipairs(names) do have[name] = true end

				for _, name in ipairs(expected) do
					expect(have[name]).to.beTrue()
				end

				local sorted = table.Copy(names)
				table.sort(sorted)

				for i, name in ipairs(names) do expect(sorted[i]).to.equal(name) end
			end
		},
		{
			name = "the info of an event: label, variants and follows are stored from the third argument of RegisterHUDEvent and given back as a COPY",
			func = function()
				expect(isfunction(API.GetHUDEventInfo)).to.beTrue()
				local info = {
					label = "My flash",
					variants = {{label = "Soft", data = {power = 1}}, {label = "Hard", data = {power = 9}}, {label = "Plain"}},
					follows = {{"gry_screenfx", "the flash"}, {"gry_sounds", "the sound"}}
				}

				expect(API.RegisterHUDEvent("zz_info", function() end, info)).to.beTrue()
				local got = API.GetHUDEventInfo("zz_info")

				-- what was stored is not the caller's table: changing it afterwards changes nothing
				info.label = "Changed"
				info.variants[1].data.power = 99
				info.follows[1][1] = "other"
				local again = API.GetHUDEventInfo("zz_info")
				API.UnregisterHUDEvent("zz_info")

				expect(got.label).to.equal("My flash")
				expect(#got.variants).to.equal(3)
				expect(got.variants[1].label).to.equal("Soft")
				expect(got.variants[1].data.power).to.equal(1)
				expect(got.variants[2].data.power).to.equal(9)
				expect(got.variants[3].data).to.beNil()
				expect(#got.follows).to.equal(2)
				expect(got.follows[1][1]).to.equal("gry_screenfx")
				expect(got.follows[1][2]).to.equal("the flash")
				expect(again.label).to.equal("My flash")
				expect(again.variants[1].data.power).to.equal(1)
				expect(again.follows[1][1]).to.equal("gry_screenfx")
			end
		},
		{
			name = "the info that is given back is a copy: a tool that changes it changes nothing for the next one",
			func = function()
				API.RegisterHUDEvent("zz_info", function() end, {label = "A", variants = {{label = "V", data = {n = 1}}}, follows = {{"gry_sounds", "x"}}})
				local one = API.GetHUDEventInfo("zz_info")
				one.label = "Z"
				one.variants[1].data.n = 5
				one.follows[1][2] = "changed"
				local two = API.GetHUDEventInfo("zz_info")
				API.UnregisterHUDEvent("zz_info")
				expect(two.label).to.equal("A")
				expect(two.variants[1].data.n).to.equal(1)
				expect(two.follows[1][2]).to.equal("x")
			end
		},
		{
			name = "an event with no info: the label is its name, no variants, no follows; an unknown event has no info",
			func = function()
				API.RegisterHUDEvent("zz_plain", function() end)
				local info = API.GetHUDEventInfo("zz_plain")
				API.UnregisterHUDEvent("zz_plain")
				expect(info.label).to.equal("zz_plain")
				expect(info.variants).to.beNil()
				expect(info.follows).to.beNil()
				expect(API.GetHUDEventInfo("zz_missing")).to.beNil()
				expect(API.GetHUDEventInfo(nil)).to.beNil()
			end
		},
		{
			name = "a badly formed info is ignored piece by piece, never an error: the event is registered all the same",
			func = function()
				expect(API.RegisterHUDEvent("zz_bad", function() end, "not a table")).to.beTrue()
				expect(API.GetHUDEventInfo("zz_bad").label).to.equal("zz_bad")

				expect(API.RegisterHUDEvent("zz_bad", function() end, {
					label = 5,
					variants = {5, {label = 1}, {label = "no data table", data = 7}, {label = ""}, "x"},
					follows = {{1, 2}, "x", {"gry_sounds"}, {"", "empty"}}
				})).to.beTrue()
				local info = API.GetHUDEventInfo("zz_bad")
				expect(info.label).to.equal("zz_bad")
				expect(info.variants).to.beNil()
				expect(info.follows).to.beNil()

				-- the good pieces of a half bad info stay
				API.RegisterHUDEvent("zz_bad", function() end, {label = {}, variants = {{label = "ok", data = {a = 1}}, 3}, follows = "no"})
				info = API.GetHUDEventInfo("zz_bad")
				API.UnregisterHUDEvent("zz_bad")
				expect(info.label).to.equal("zz_bad")
				expect(#info.variants).to.equal(1)
				expect(info.variants[1].data.a).to.equal(1)
				expect(info.follows).to.beNil()
			end
		},
		{
			name = "registering again replaces the info, and removing the event removes it",
			func = function()
				API.RegisterHUDEvent("zz_swap", function() end, {label = "One"})
				expect(API.GetHUDEventInfo("zz_swap").label).to.equal("One")
				API.RegisterHUDEvent("zz_swap", function() end)
				expect(API.GetHUDEventInfo("zz_swap").label).to.equal("zz_swap")
				API.UnregisterHUDEvent("zz_swap")
				expect(API.GetHUDEventInfo("zz_swap")).to.beNil()
			end
		},
		{
			name = "every event of GryMod has its info: a label, the four modes and the two health levels as variants, and follows that name real options",
			func = function()
				local names = {"armor_hit", "boot", "decloak", "disabled", "dive_in", "dive_out", "drown", "enabled", "energy_critical", "jam", "lost", "low_health",
					"malfunction", "mode", "reboot", "regen_start", "regen_stop", "reset"}

				for _, name in ipairs(names) do
					local info = API.GetHUDEventInfo(name)
					expect(info ~= nil).to.beTrue()
					expect(isstring(info.label) and info.label ~= name and info.label ~= "").to.beTrue()

					for _, option in ipairs(info.follows or {}) do
						-- the option exists: it is a convar of the player (an event that names an option that is not there would lie in a tooltip)
						expect(GetConVar(option[1]) ~= nil).to.beTrue()
						expect(isstring(option[2]) and option[2] ~= "").to.beTrue()
					end
				end

				local modes = API.GetHUDEventInfo("mode").variants
				expect(#modes).to.equal(4)

				for i, mode in ipairs({"armor", "speed", "strength", "cloak"}) do
					expect(modes[i].data.mode).to.equal(mode)
				end

				local health = API.GetHUDEventInfo("low_health").variants
				expect(#health).to.equal(2)
				expect(health[1].data.level).to.equal(1)
				expect(health[2].data.level).to.equal(2)

				-- every variant plays: the event takes its data
				for _, name in ipairs({"mode", "low_health"}) do
					for _, variant in ipairs(API.GetHUDEventInfo(name).variants) do
						expect(API.HUDEvent(name, variant.data)).to.beTrue()
					end
				end

				timer.Remove("GryModModeVoice")

				-- the options that really cut the effect are named
				local function follows(name, convar)
					for _, option in ipairs(API.GetHUDEventInfo(name).follows or {}) do
						if option[1] == convar then return true end
					end

					return false
				end

				expect(follows("boot", "gry_hud_boot")).to.beTrue()
				expect(follows("armor_hit", "gry_screenfx")).to.beTrue()
				expect(follows("armor_hit", "gry_hud_damagefx")).to.beTrue()
				expect(follows("armor_hit", "gry_sounds")).to.beTrue()
				expect(follows("decloak", "gry_decloak_glitch")).to.beTrue()
				expect(follows("regen_start", "gry_sound_regen")).to.beTrue()
				expect(follows("dive_in", "gry_underwater_fx")).to.beTrue()
				expect(follows("mode", "gry_screenfx")).to.beTrue()
				expect(follows("jam", "gry_hud_damagefx")).to.beTrue()
			end
		},
		{
			name = "ListHUDEvents follows the registry: a third-party event shows, and goes when it is removed",
			func = function()
				expect(API.RegisterHUDEvent("zz_listed", function() end)).to.beTrue()
				local found = false

				for _, name in ipairs(API.ListHUDEvents()) do
					if name == "zz_listed" then found = true end
				end

				API.UnregisterHUDEvent("zz_listed")
				expect(found).to.beTrue()

				for _, name in ipairs(API.ListHUDEvents()) do
					expect(name ~= "zz_listed").to.beTrue()
				end
			end
		},
		{
			name = "armor_hit plays the flash, the HUD jump, the shake AND one file of the impact shuffle, in one call",
			func = function()
				local shakes = 0
				DamageFx.Shake = function() shakes = shakes + 1 end

				expect(API.HUDEvent("armor_hit")).to.beTrue()
				expect(DamageFx.State.armorAt ~= nil).to.beTrue()
				expect(DamageFx.State.jolt).to.equal(DamageFx.INTERFERENCE_DISTORTION)
				expect(shakes).to.equal(1)
				expect(#played).to.equal(1)
				expect(isArmorHitFile(played[1].path)).to.beTrue()
			end
		},
		{
			name = "armor_hit: data.sound = false plays the picture only, data.visual = false the sound only",
			func = function()
				API.HUDEvent("armor_hit", {sound = false})
				expect(DamageFx.State.armorAt ~= nil).to.beTrue()
				expect(#played).to.equal(0)

				DamageFx.State = DamageFx.NewState()
				API.HUDEvent("armor_hit", {visual = false})
				expect(DamageFx.State.armorAt).to.beNil()
				expect(DamageFx.State.jolt).to.equal(0)
				expect(#played).to.equal(1)
			end
		},
		{
			name = "armor_hit follows the options: the screen switch and the HUD jump switch each keep their own half, gry_sounds 0 silences the sound",
			func = function()
				DamageFx.Options = function() return {hud = true, screen = false} end
				API.HUDEvent("armor_hit")
				expect(DamageFx.State.jolt).to.equal(DamageFx.INTERFERENCE_DISTORTION)
				expect(DamageFx.State.armorAt).to.beNil()

				DamageFx.State = DamageFx.NewState()
				GryMod.SoundMix.ResetLimits() -- the second hit is not within 60 ms of the first
				DamageFx.Options = function() return {hud = false, screen = true} end
				API.HUDEvent("armor_hit")
				expect(DamageFx.State.jolt).to.equal(0)
				expect(DamageFx.State.armorAt ~= nil).to.beTrue()

				-- GryMod.PlaySound is the one that checks gry_sounds: the event still goes through it
				expect(#played).to.equal(2)
			end
		},
		{
			name = "armor_hit: the mix's limit holds back a second sound within 60 ms and a refused hit uses up no file of the shuffle; the picture still plays",
			func = function()
				local asked = 0
				local realNext = GryMod.NextArmorHitSound
				stub(GryMod, "NextArmorHitSound", function() asked = asked + 1 return realNext() end)

				API.HUDEvent("armor_hit")
				DamageFx.State = DamageFx.NewState()
				API.HUDEvent("armor_hit")
				expect(DamageFx.State.armorAt ~= nil).to.beTrue() -- the flash is not limited
				expect(#played).to.equal(1)
				expect(asked).to.equal(1)
			end
		},
		{
			name = "the server's gry_armor_hit_sound message goes through the armor_hit event (sound only: the picture has its own rule, the energy it costs)",
			func = function()
				listen()
				receive("gry_armor_hit_sound")
				local event = seen("armor_hit")
				expect(event ~= nil).to.beTrue()
				expect(event.data.visual).to.equal(false)
				expect(#played).to.equal(1)
				expect(isArmorHitFile(played[1].path)).to.beTrue()
				expect(DamageFx.State.armorAt).to.beNil()
			end
		},
		{
			name = "a heavy energy drop seen by the observer goes through the armor_hit event (picture only: the sound is the server's decision)",
			func = function()
				listen()
				local state = DamageFx.NewState()
				-- the state the HUD's observer keeps is the live one; Observe says what it saw through DamageFx.Emit, here the real API
				DamageFx.State = state
				DamageFx.Observe(state, {health = 100, max = 100, energy = 80, armor = true}, 0, ON)
				DamageFx.Observe(state, {health = 100, max = 100, energy = 50, armor = true}, 1, ON)
				local event = seen("armor_hit")
				expect(event ~= nil).to.beTrue()
				expect(event.data.sound).to.equal(false)
				expect(state.armorAt ~= nil).to.beTrue()
				expect(#played).to.equal(0)
			end
		},
		{
			name = "decloak plays the glitch, marks the emptied bar, and follows gry_decloak_glitch (the mark stays either way)",
			func = function()
				setConVar("gry_decloak_glitch", "1")
				expect(API.HUDEvent("decloak")).to.beTrue()
				expect(DamageFx.State.armorAt ~= nil).to.beTrue()
				expect(DamageFx.State.emptiedUntil ~= nil).to.beTrue()

				DamageFx.State = DamageFx.NewState()
				setConVar("gry_decloak_glitch", "0")
				API.HUDEvent("decloak")
				expect(DamageFx.State.armorAt).to.beNil()
				expect(DamageFx.State.emptiedUntil ~= nil).to.beTrue()
			end
		},
		{
			name = "firing out of the camouflage (GryMod.CloakShot) plays the decloak event, not the glitch directly",
			func = function()
				listen()
				local realStart, realWrite, realSend = net.Start, net.WriteUInt, net.SendToServer
				local fake = {NanosuitMode = Modes.CLOAK}
				fake.SetNanosuitMode = function() end
				local ok, err = pcall(function()
					net.Start, net.SendToServer = function() end, function() end
					GryMod.CloakShot(fake, false)
				end)
				net.Start, net.WriteUInt, net.SendToServer = realStart, realWrite, realSend
				if not ok then error(err, 0) end
				expect(debug.getinfo(net.Start, "S").what).to.equal("C")
				expect(seen("decloak") ~= nil).to.beTrue()
			end
		},
		{
			name = "low_health: level 1 starts the tint and blur, level 2 adds the shake; another level, or the screen switch off, plays nothing",
			func = function()
				local shakes = {}
				DamageFx.Shake = function(a, f, s) shakes[#shakes + 1] = {a, f, s} end

				expect(API.HUDEvent("low_health", {level = 1})).to.beTrue()
				expect(DamageFx.State.lowLevel).to.equal(1)
				expect(DamageFx.State.lowAt ~= nil).to.beTrue()
				expect(#shakes).to.equal(0)
				expect(hook.GetTable().RenderScreenspaceEffects.GryDamageFx ~= nil).to.beTrue()

				DamageFx.State = DamageFx.NewState()
				API.HUDEvent("low_health", {level = 2})
				expect(DamageFx.State.lowLevel).to.equal(2)
				expect(#shakes).to.equal(1)
				expect(shakes[1][3]).to.equal(0.4)

				DamageFx.State = DamageFx.NewState()
				API.HUDEvent("low_health", {level = 7})
				API.HUDEvent("low_health")
				expect(DamageFx.State.lowAt).to.beNil()

				DamageFx.Options = function() return {hud = true, screen = false} end
				API.HUDEvent("low_health", {level = 2})
				expect(DamageFx.State.lowAt).to.beNil()
			end
		},
		{
			name = "the health falling through a low zone goes through the low_health event (the observer's trigger)",
			func = function()
				listen()
				local state = DamageFx.NewState()
				DamageFx.State = state
				DamageFx.Observe(state, {health = 80, max = 100, energy = 100, armor = false}, 0, ON)
				DamageFx.Observe(state, {health = 18, max = 100, energy = 100, armor = false}, 1, ON)
				local event = seen("low_health")
				expect(event ~= nil).to.beTrue()
				expect(event.data.level).to.equal(2)
				expect(state.lowLevel).to.equal(2)
			end
		},
		{
			name = "jam: the HUD trembles for data.seconds (2 by default) and falls away after; it follows the HUD jump switch",
			func = function()
				local state = DamageFx.State
				expect(API.HUDEvent("jam")).to.beTrue()
				expect(state.jamLeft).to.equal(DamageFx.JAM_SECONDS)
				expect(DamageFx.JAM_SECONDS).to.equal(2)

				-- during the jam every frame moves the HUD, however long it lasts
				local moved = 0

				for _ = 1, 100 do
					local x, y = DamageFx.HudOffset(state, 0.016, 1, 1)
					if x ~= 0 or y ~= 0 then moved = moved + 1 end
				end

				expect(moved).to.equal(100) -- 1.6 s of the 2
				for _ = 1, 40 do DamageFx.HudOffset(state, 0.016, 1, 1) end -- past the 2 s
				expect(state.jamLeft <= 0).to.beTrue()

				for _ = 1, 100 do DamageFx.HudOffset(state, 0.016, 1, 1) end -- it fell away on its own
				expect(state.jolt).to.equal(0)

				DamageFx.State = DamageFx.NewState()
				API.HUDEvent("jam", {seconds = 5})
				expect(DamageFx.State.jamLeft).to.equal(5)
				API.HUDEvent("jam", {seconds = 9999})
				expect(DamageFx.State.jamLeft <= 60).to.beTrue()

				DamageFx.State = DamageFx.NewState()
				DamageFx.Options = function() return {hud = false, screen = true} end
				API.HUDEvent("jam")
				expect((DamageFx.State.jamLeft or 0) <= 0).to.beTrue()
			end
		},
		{
			name = "mode: the tint of the mode AND its activation sound AND (half a second later) its voice, in one call",
			func = function()
				local cases = {
					{"armor", Modes.ARMOR, "suit_armor_108", "suit_maximum_armor"},
					{"speed", Modes.SPEED, "suit_speed_activate_07_good", "suit_maximum_speed"},
					{"strength", Modes.STRENGTH, "suit_strength_101_r", "suit_maximum_strength"}
				}

				for _, case in ipairs(cases) do
					played = {}
					ModeFX.State = ModeFX.NewState()
					expect(API.HUDEvent("mode", {mode = case[1]})).to.beTrue()
					expect(ModeFX.State.starts[case[2]] ~= nil).to.beTrue()
					expect(#played).to.equal(1)
					expect(played[1].path).to.equal(Sound("grymod/suit/" .. case[3] .. ".wav"))
					expect(timer.Exists("GryModModeVoice")).to.beTrue()
					timer.Remove("GryModModeVoice")
				end
			end
		},
		{
			name = "mode: the camouflage has no tint here (cl_cloak_fx.lua owns its picture) but plays its sound; data.mode may also be the mode's number",
			func = function()
				API.HUDEvent("mode", {mode = "cloak"})
				expect(next(ModeFX.State.starts)).to.beNil()
				expect(#played).to.equal(1)
				expect(played[1].path).to.equal(Sound("grymod/suit/suit_cloak_chameleon_101_r.wav"))
				timer.Remove("GryModModeVoice")

				played = {}
				API.HUDEvent("mode", {mode = Modes.SPEED})
				expect(ModeFX.State.starts[Modes.SPEED] ~= nil).to.beTrue()
				expect(#played).to.equal(1)
				timer.Remove("GryModModeVoice")
			end
		},
		{
			name = "mode: data.tint = false and data.sound = false each keep their half out; an unknown mode, or the screen switch off, plays nothing wrong",
			func = function()
				API.HUDEvent("mode", {mode = "speed", tint = false})
				expect(next(ModeFX.State.starts)).to.beNil()
				expect(#played).to.equal(1)
				timer.Remove("GryModModeVoice")

				played = {}
				API.HUDEvent("mode", {mode = "speed", sound = false})
				expect(ModeFX.State.starts[Modes.SPEED] ~= nil).to.beTrue()
				expect(#played).to.equal(0)
				expect(timer.Exists("GryModModeVoice")).to.beFalse()

				ModeFX.State = ModeFX.NewState()
				expect(API.HUDEvent("mode", {mode = "nonsense"})).to.beTrue()
				API.HUDEvent("mode")
				expect(next(ModeFX.State.starts)).to.beNil()
				expect(#played).to.equal(0)

				ModeFX.Enabled = function() return false end
				API.HUDEvent("mode", {mode = "strength"})
				expect(next(ModeFX.State.starts)).to.beNil()
				expect(#played).to.equal(1) -- the sound has its own switch (gry_sounds)
				timer.Remove("GryModModeVoice")
			end
		},
		{
			name = "a mode change (Player:SetNanosuitMode) goes through the mode event, with the tint when the change is a real one",
			func = function()
				listen()
				local now = 1000
				local me = {NanosuitMode = Modes.ARMOR}
				function me:IsValid() return true end
				function me:Alive() return true end
				function me:GetNW2Bool() return false end
				function me:GetViewModel() return NULL end
				stub(_G, "LocalPlayer", function() return me end)
				stub(ModeFX, "Now", function() return now end)
				ModeFX.State.aliveAt = 0

				FindMetaTable("Player").SetNanosuitMode(me, Modes.SPEED, false)
				local event = seen("mode")
				expect(event ~= nil).to.beTrue()
				expect(event.data.mode).to.equal("speed")
				expect(event.data.tint).to.equal(true)
				expect(me.NanosuitMode).to.equal(Modes.SPEED)
				expect(ModeFX.State.starts[Modes.SPEED] ~= nil).to.beTrue()
				expect(#played).to.equal(1)
				timer.Remove("GryModModeVoice")
			end
		},
		{
			name = "a mode change right after a respawn, while the suit is down, or the first one seen, plays its sound but no tint (the old observer's rules)",
			func = function()
				listen()
				local now = 1000
				local me = {NanosuitMode = Modes.ARMOR, down = false}
				function me:IsValid() return true end
				function me:Alive() return true end
				function me:GetNW2Bool(name) return name == "GryMalfunction" and self.down end
				function me:GetViewModel() return NULL end
				stub(_G, "LocalPlayer", function() return me end)
				stub(ModeFX, "Now", function() return now end)
				local set = FindMetaTable("Player").SetNanosuitMode

				-- 0.2 s after the respawn
				ModeFX.State.aliveAt = now - 0.2
				set(me, Modes.SPEED, false)
				expect(seen("mode").data.tint).to.equal(false)
				timer.Remove("GryModModeVoice")

				-- the suit is down
				spy = {}
				ModeFX.State.aliveAt = 0
				me.down = true
				set(me, Modes.STRENGTH, false)
				expect(seen("mode").data.tint).to.equal(false)
				timer.Remove("GryModModeVoice")
				expect(#played).to.equal(2)
				expect(next(ModeFX.State.starts)).to.beNil()
			end
		},
		{
			name = "energy_critical plays the warning voice through the mix",
			func = function()
				expect(API.HUDEvent("energy_critical")).to.beTrue()
				expect(#played).to.equal(1)
				expect(played[1].path).to.equal(Sound("grymod/suit/suit_energy_critical.wav"))
			end
		},
		{
			name = "the Think hook of the sounds plays the energy-critical voice through the energy_critical event",
			func = function()
				listen()
				local realDue = GryMod.EnergyCriticalDue
				stub(GryMod, "EnergyCriticalDue", function() return true end)
				local hookFunc = hook.GetTable().Think["GryModSounds"]
				local ok, err = pcall(function()
					-- a real value must have been seen once for the voice to be due
					local ply = LocalPlayer()
					expect(IsValid(ply)).to.beTrue()
					hookFunc()
					hookFunc()
				end)
				GryMod.EnergyCriticalDue = realDue
				GryMod.ResetEnergyCritical()
				if not ok then error(err, 0) end
				expect(seen("energy_critical") ~= nil).to.beTrue()
			end
		},
		{
			name = "regen_start starts the repair sound from the beginning, regen_stop fades it out; the nets of the server go through these events",
			func = function()
				listen()
				local channel = fakeChannel()
				local realChannel = GryMod.RegenSound.GetChannel()
				GryMod.RegenSound.SetChannel(channel)
				setConVar("gry_sound_regen", "1")
				local ok, err = pcall(function()
					expect(API.HUDEvent("regen_start")).to.beTrue()
					expect(channel.calls[#channel.calls]).to.equal("Play")
					expect(table.HasValue(channel.calls, "SetTime=0")).to.beTrue()

					expect(API.HUDEvent("regen_stop")).to.beTrue()
					expect(hook.GetTable().Think["GryModSoundhealthregenfadeaway"] ~= nil).to.beTrue()

					spy = {}
					receive("gry_start_health_regen")
					expect(seen("regen_start") ~= nil).to.beTrue()
					receive("gry_stop_health_regen")
					expect(seen("regen_stop") ~= nil).to.beTrue()
				end)
				GryMod.RegenSound.SetChannel(realChannel)
				if not ok then error(err, 0) end
			end
		},
		{
			name = "regen_start follows gry_sound_regen and gry_sounds",
			func = function()
				local channel = fakeChannel()
				local realChannel = GryMod.RegenSound.GetChannel()
				GryMod.RegenSound.SetChannel(channel)
				local ok, err = pcall(function()
					setConVar("gry_sound_regen", "0")
					API.HUDEvent("regen_start")
					expect(#channel.calls).to.equal(0)
					setConVar("gry_sound_regen", "1")
					setConVar("gry_sounds", "0")
					API.HUDEvent("regen_start")
					expect(#channel.calls).to.equal(0)
				end)
				GryMod.RegenSound.SetChannel(realChannel)
				if not ok then error(err, 0) end
			end
		},
		{
			name = "dive_in plays the slow splash for a gentle entry and a fast one for a hard fall; dive_out the way out; drown a gasp",
			func = function()
				local U = GryMod.Underwater
				setConVar("gry_underwater_fx", "1")

				API.HUDEvent("dive_in", {fall = 0})
				expect(played[1].path).to.equal(Sound(U.Files.diveSlow))

				played = {}
				API.HUDEvent("dive_in", {fall = 900})
				local fast = false

				for _, path in ipairs(U.Files.diveFast) do
					if Sound(path) == played[1].path then fast = true end
				end

				expect(fast).to.beTrue()

				played = {}
				API.HUDEvent("dive_in")
				expect(#played).to.equal(1)

				played = {}
				API.HUDEvent("dive_out")
				expect(played[1].path).to.equal(Sound(U.Files.diveOut))

				played = {}
				API.HUDEvent("drown")
				local gasp = false

				for _, path in ipairs(U.Files.drown) do
					if Sound(path) == played[1].path then gasp = true end
				end

				expect(gasp).to.beTrue()
			end
		},
		{
			name = "the water events follow gry_underwater_fx",
			func = function()
				setConVar("gry_underwater_fx", "0")
				API.HUDEvent("dive_in", {fall = 900})
				API.HUDEvent("dive_out")
				API.HUDEvent("drown")
				expect(#played).to.equal(0)
			end
		},
		{
			name = "the head going under, coming out, and the server's drowning tick go through the dive_in, dive_out and drown events",
			func = function()
				listen()
				local U = GryMod.Underwater
				setConVar("gry_underwater_fx", "1")
				local me = {level = 0}
				function me:IsValid() return true end
				function me:WaterLevel() return self.level end
				function me:Alive() return true end
				function me:GetVelocity() return Vector(0, 0, -700) end
				function me:GetNW2Bool() return false end
				stub(_G, "LocalPlayer", function() return me end)
				U.Reset()
				local ok, err = pcall(function()
					U.Poll() -- the first look: nothing
					expect(seen("dive_in")).to.beNil()
					me.level = 3
					U.Poll()
					local diveIn = seen("dive_in")
					expect(diveIn ~= nil).to.beTrue()
					expect(diveIn.data.fall).to.equal(700)

					me.level = 0
					U.Poll()
					expect(seen("dive_out") ~= nil).to.beTrue()

					receive("gry_drown_tick")
					expect(seen("drown") ~= nil).to.beTrue()
				end)
				U.Reset()
				if not ok then error(err, 0) end
			end
		},
		{
			name = "reset sends the interface back to its start: the HUD is rebuilt (ResetAll), the energy bar starts on the real value, the damage effects are forgotten",
			func = function()
				local calls = {}
				stub(GryMod.FlashHUD, "ResetAll", function() calls[#calls + 1] = "ResetAll" end)
				stub(GryMod.EnergySmooth, "Reset", function() calls[#calls + 1] = "EnergySmooth" end)
				DamageFx.State.jolt = 15
				DamageFx.State.armorAt = 1

				expect(API.HUDEvent("reset")).to.beTrue()
				expect(table.HasValue(calls, "ResetAll")).to.beTrue()
				expect(table.HasValue(calls, "EnergySmooth")).to.beTrue()
				expect(DamageFx.State.jolt).to.equal(0)
				expect(DamageFx.State.armorAt).to.beNil()
			end
		},
		{
			name = "reset also brings back a HUD that a disabled event hid",
			func = function()
				stub(GryMod.FlashHUD, "ResetAll", function() end)
				stub(GryMod.EnergySmooth, "Reset", function() end)
				API.HUDEvent("disabled")
				expect(GryMod.FlashHUD.IsLocalOff()).to.beTrue()
				API.HUDEvent("reset")
				expect(GryMod.FlashHUD.IsLocalOff()).to.beFalse()
			end
		},
		{
			name = "disabled: the shutdown animation (with its sound) plays, and the HUD stays hidden until enabled, which plays the reboot",
			func = function()
				setConVar("gry_hud_boot", "1")
				local Boot = GryMod.FlashBoot
				Boot.Reset()

				expect(API.HUDEvent("disabled")).to.beTrue()
				expect(GryMod.FlashHUD.IsLocalOff()).to.beTrue()
				expect(GryMod.FlashHUD.Enabled()).to.beFalse()
				expect(Boot.Current()).to.equal("lost")
				expect(#played).to.equal(1) -- the malfunction sound, as the real shutdown has it
				expect(timer.Exists("GryApiDisabled")).to.beTrue()

				played = {}
				expect(API.HUDEvent("enabled")).to.beTrue()
				expect(GryMod.FlashHUD.IsLocalOff()).to.beFalse()
				expect(Boot.Current()).to.equal("reboot")
				expect(#played).to.equal(0) -- the reboot of the original has no sound
				expect(timer.Exists("GryApiDisabled")).to.beFalse()
			end
		},
		{
			name = "disabled: the shutdown animation ends by itself and the HUD stays hidden",
			func = function()
				setConVar("gry_hud_boot", "1")
				local Boot = GryMod.FlashBoot
				Boot.Reset()
				API.HUDEvent("disabled")
				expect(Boot.Current()).to.equal("lost")
				-- the timer's function, run now
				local data = timer.Exists("GryApiDisabled")
				expect(data).to.beTrue()
				GryMod.APIEvents.EndShutdown()
				expect(Boot.Current()).to.beNil()
				expect(GryMod.FlashHUD.IsLocalOff()).to.beTrue()
			end
		},
		{
			name = "the HUD stays hidden while the event holds it: the suit counts as off for the paint hook",
			func = function()
				expect(GryMod.FlashHUD.SuitOn(LocalPlayer())).to.beTrue()
				API.HUDEvent("disabled")
				expect(GryMod.FlashHUD.SuitOn(LocalPlayer())).to.beFalse()
				API.HUDEvent("enabled")
				expect(GryMod.FlashHUD.SuitOn(LocalPlayer())).to.beTrue()
			end
		},
		{
			name = "the server's suit flag (GryMod.API.SetSuitEnabled) plays disabled and enabled when it changes: nothing at the first look, nothing when it does not change",
			func = function()
				local step = GryMod.APIEvents.SuitFlagStep
				expect(step(nil, true)).to.beNil()
				expect(step(nil, false)).to.beNil()
				expect(step(true, true)).to.beNil()
				expect(step(false, false)).to.beNil()
				expect(step(true, false)).to.equal("disabled")
				expect(step(false, true)).to.equal("enabled")
			end
		},
		{
			name = "boot, lost and reboot: the spawn and the HUD's own status changes call the events themselves",
			func = function()
				listen()
				setConVar("gry_hud_boot", "1")
				local Boot = GryMod.FlashBoot
				Boot.Reset()
				Boot.ResetSpawn()

				Boot.Spawned()
				expect(seen("boot") ~= nil).to.beTrue()
				expect(Boot.Current()).to.equal("initialize")

				spy = {}
				hook.Run("GryMod_HUDStatus", 1)
				expect(seen("lost") ~= nil).to.beTrue()
				expect(Boot.Current()).to.equal("lost")

				spy = {}
				hook.Run("GryMod_HUDStatus", 2) -- a flicker: nothing
				expect(#spy).to.equal(0)

				hook.Run("GryMod_HUDStatus", 0)
				expect(seen("reboot") ~= nil).to.beTrue()
				expect(Boot.Current()).to.equal("reboot")

				-- back to normal while nothing is wrong: no reboot sequence
				Boot.Reset()
				spy = {}
				hook.Run("GryMod_HUDStatus", 0)
				expect(seen("reboot")).to.beNil()
				expect(Boot.Current()).to.beNil()
			end
		}
	}
}
