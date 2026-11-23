-- Tests of the text lines drawn from the original Scaleform movie (GryMod.FlashMessages, lua/grymod/client/cl_hud_messages_flash.lua),
-- GLuaTest format, client realm. Needs the converted movie lua/grymod/flash/hud_messages.lua. The rule: ONE event, "message", shows the
-- text and plays its sound together, whoever asks (an addon through GryMod.API.ShowMessage, the suit's own lines); the lines of a lane
-- stack up and leave after their life; nothing runs (no paint hook) when no line is shown; the player's settings cut it.
-- Everything that touches the live game is replaced and put back in afterEach, inside a pcall, even when a case fails halfway: the HUD
-- state, the sound, the settings, the error printer, the listeners.

local Messages = GryMod.Messages
local Module = GryMod.FlashMessages
local API = GryMod.API

local saved = {}
local convarsSaved = {}
local listeners = {}
local played, reported, errors

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

	assert(convar, "no convar " .. name)

	if convarsSaved[name] == nil then
		convarsSaved[name] = convar:GetString()
	end

	convar:SetString(value)
end

local function restore()
	for i = #saved, 1, -1 do
		local entry = saved[i]
		entry[1][entry[2]] = entry[3]
	end

	saved = {}

	for name, value in pairs(convarsSaved) do
		GetConVar(name):SetString(value)
	end

	convarsSaved = {}

	for _, id in ipairs(listeners) do
		hook.Remove("GryMod_MessageShown", id)
	end

	listeners = {}
end

-- seconds of the movie, in steps of a frame (the paint hook is not involved: Step is what it runs)
local function run(seconds)
	for _ = 1, math.ceil(seconds * 30) do
		Module.Step(1 / 30)
	end
end

local function listen()
	local id = "gry_messages_test"

	hook.Add("GryMod_MessageShown", id, function(text, opts)
		reported[#reported + 1] = {text = text, opts = opts}
	end)

	listeners[#listeners + 1] = id
end

-- the middle of a line on the stage, from the placement of the movie: the clip, its Ani and the field
local function centreOf(slot)
	local ani = slot.text:Child("Ani")
	local field = ani:Field("Message" .. slot.n)
	local entry = ani:Child("Message" .. slot.n)

	return slot.text.entry.m[5] + ani.entry.m[5] + entry.m[5] + field.w / 2
end

return {
	groupName = "GryMod text lines (HUD_Messages)",
	beforeEach = function()
		Module.Reset()
		played, reported, errors = {}, {}, {}

		stub(GryMod, "PlaySound", function(path) played[#played + 1] = path return true end)
		stub(GryMod.FlashHUD, "Enabled", function() return true end)
		stub(_G, "ErrorNoHalt", function(text) errors[#errors + 1] = text end)
		setConVar("gry_hud_messages", "1")

		for _, line in pairs(Messages.Lines) do
			setConVar(line.convar, "1")
		end

		listen()
	end,
	afterEach = function()
		pcall(Module.Reset)
		pcall(restore)
	end,
	cases = {
		{
			-- fails without the event registration or without API.ShowMessage
			name = "the event exists and GryMod.API.ShowMessage runs it with checked data; a bad text or option never reaches it",
			func = function()
				expect(API.GetHUDEventInfo("message")).to.exist()
				expect(API.ShowMessage("HELLO")).to.beTrue()
				expect(Module.Texts("top")[1]).to.equal("HELLO")

				local before = #reported

				for _, args in ipairs({{""}, {nil}, {"x", {lane = "nowhere"}}, {string.rep("a", 200)}}) do
					local ok, reason = API.ShowMessage(args[1], args[2])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end

				expect(#reported).to.equal(before)
			end
		},
		{
			-- fails if the picture and the sound were two paths (the sound played by the caller), or without the report hook
			name = "ONE call shows the text on its lane AND plays its sound, and reports it with the hook GryMod_MessageShown",
			func = function()
				expect(API.ShowMessage("HELLO", {lane = "status", sound = "grymod/hud/hud_activate_01.wav", duration = 3})).to.beTrue()

				expect(Module.Texts("status")[1]).to.equal("HELLO")
				expect(#Module.Texts("top")).to.equal(0)
				expect(#played).to.equal(1)
				expect(played[1]).to.equal("grymod/hud/hud_activate_01.wav")
				expect(#reported).to.equal(1)
				expect(reported[1].text).to.equal("HELLO")
				expect(reported[1].opts.lane).to.equal("status")
				expect(reported[1].opts.sound).to.equal("grymod/hud/hud_activate_01.wav")
				expect(reported[1].opts.duration).to.equal(3)
			end
		},
		{
			-- fails if the sound played even when the picture is off
			name = "the text lines off (gry_hud_messages 0) or the HUD off: no text, no sound, no report; the event still ran",
			func = function()
				setConVar("gry_hud_messages", "0")
				expect(API.ShowMessage("HELLO", {sound = "a/b.wav"})).to.beTrue()
				expect(#Module.Texts("top")).to.equal(0)
				expect(#played).to.equal(0)
				expect(#reported).to.equal(0)
				expect(Module.Active()).to.beFalse()

				setConVar("gry_hud_messages", "1")
				GryMod.FlashHUD.Enabled = function() return false end
				API.ShowMessage("HELLO", {sound = "a/b.wav"})
				expect(#Module.Texts("top")).to.equal(0)
				expect(#played).to.equal(0)
				expect(#reported).to.equal(0)
			end
		},
		{
			-- fails without the paint hook that starts with the first line and ends with the last
			name = "no paint hook while nothing is shown: the first line adds it, the end of the last one removes it",
			func = function()
				expect(Module.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHMESSAGES"]).to.beNil()

				API.ShowMessage("HELLO")
				expect(Module.Active()).to.beTrue()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHMESSAGES"]).to.exist()

				-- the paint hook ends itself when its step says nothing is left
				run(5.5)
				expect(Module.Step(0)).to.beFalse()
				Module.Paint()
				expect(Module.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHMESSAGES"]).to.beNil()
			end
		},
		{
			-- fails without Shift: the lines would not stack
			name = "the lines of a lane stack up: the newest goes last, the seventh pushes the first one out",
			func = function()
				for i = 1, 3 do
					API.ShowMessage("line " .. i, {lane = "status"})
				end

				local texts = Module.Texts("status")
				expect(#texts).to.equal(3)
				expect(texts[1]).to.equal("line 1")
				expect(texts[3]).to.equal("line 3")

				for i = 4, 8 do
					API.ShowMessage("line " .. i, {lane = "status"})
				end

				texts = Module.Texts("status")
				expect(#texts).to.equal(7)
				expect(texts[1]).to.equal("line 2")
				expect(texts[7]).to.equal("line 8")

				-- a lane that shows one line at a time keeps the last one only
				API.ShowMessage("one", {lane = "middle"})
				API.ShowMessage("two", {lane = "middle"})
				expect(#Module.Texts("middle")).to.equal(1)
				expect(Module.Texts("middle")[1]).to.equal("two")
			end
		},
		{
			-- fails if a line keeps its text after its life, or its age is lost when it moves up
			name = "a line leaves after its 5 seconds, and an older line that moved up keeps its age (it leaves first)",
			func = function()
				API.ShowMessage("old", {lane = "status"})
				run(3)
				API.ShowMessage("new", {lane = "status"})
				expect(#Module.Texts("status")).to.equal(2)

				-- the old one has lived 3 s: 2.3 s later it is over, the new one has 2.7 s left
				run(2.3)
				local texts = Module.Texts("status")
				expect(#texts).to.equal(1)
				expect(texts[1]).to.equal("new")

				run(3)
				expect(#Module.Texts("status")).to.equal(0)
			end
		},
		{
			-- fails without the speed of a line with a duration
			name = "a duration changes how long a line stays: 1 second is over before 1.2 s, 10 seconds is still there at 9",
			func = function()
				API.ShowMessage("short", {lane = "top", duration = 1})
				API.ShowMessage("long", {lane = "middle", duration = 10})
				run(1.2)
				expect(#Module.Texts("top")).to.equal(0)
				expect(#Module.Texts("middle")).to.equal(1)
				run(7.8)
				expect(#Module.Texts("middle")).to.equal(1)
				run(1.5)
				expect(#Module.Texts("middle")).to.equal(0)
			end
		},
		{
			-- fails without the hold of the single line lanes: the movie stops their line at its second frame and never ends it by itself
			name = "a lane of one line holds its line, fades it out at the end of its life, and is empty at 5 seconds like the others",
			func = function()
				API.ShowMessage("held", {lane = "crosshair"})
				run(2.5)
				expect(Module.Texts("crosshair")[1]).to.equal("held")
				run(1.5) -- 4 s: the fade has begun, the line is still there
				expect(Module.Texts("crosshair")[1]).to.equal("held")
				run(1.5) -- 5.5 s
				expect(#Module.Texts("crosshair")).to.equal(0)
			end
		},
		{
			-- fails without the plate that follows the width of the text, or the centring of the text
			name = "the text stays centred on the same point whatever its width, and the plate behind it is 54 pixels wider than the text",
			func = function()
				API.ShowMessage("A", {lane = "status"})
				local slots = Module.Lane("status")
				local slot = slots[#slots]
				local shortCentre = centreOf(slot)
				local shortScale = slot.plate:Child("Ani"):Child("Middle").entry.m[1] * 100

				API.ShowMessage("A MUCH LONGER LINE OF TEXT FOR THE STACK", {lane = "status"})
				slots = Module.Lane("status")
				slot = slots[#slots]

				expect(math.abs(centreOf(slot) - shortCentre) < 1.5).to.beTrue()

				local longScale = slot.plate:Child("Ani"):Child("Middle").entry.m[1] * 100
				expect(longScale > shortScale).to.beTrue()

				local ani = slot.text:Child("Ani")
				local field = ani:Field("Message" .. slot.n)
				-- the width of the text is the field's minus its two margins; the plate is that plus 4 + 50, from a picture that is 2.8 wide
				expect(math.abs(longScale - Module.PlateScale(field.w - 4)) < 3).to.beTrue()
			end
		},
		{
			-- fails without the plates of the empty places hidden
			name = "the plate of an empty place is hidden, the one of a used place shows",
			func = function()
				API.ShowMessage("HELLO", {lane = "status"})

				local slots = Module.Lane("status")

				for index, slot in ipairs(slots) do
					local middle = slot.plate:Child("Ani"):Child("Middle")
					expect(middle.visible).to.equal(index == #slots)
				end
			end
		},
		{
			-- fails without the line's own setting
			name = "a suit line shows on its lane with its own text, unless its setting is off",
			func = function()
				API.HUDEvent("message", {line = "cloak_disabled"})
				expect(Module.Texts("status")[1]).to.equal("Temperature Camo: Disabled!")
				expect(reported[#reported].opts.line).to.equal("cloak_disabled")

				Module.Reset()
				setConVar("gry_msg_cloak_disabled", "0")
				API.HUDEvent("message", {line = "cloak_disabled"})
				expect(#Module.Texts("status")).to.equal(0)

				API.HUDEvent("message", {line = "killed_friend"})
				expect(Module.Texts("middle")[1]).to.equal("YOU KILLED A FRIENDLY!")
			end
		},
		{
			-- fails without the predicate or the hook on the mode change
			name = "the camouflage dropped to armor for lack of energy shows the line; a change the player asked for, or another cause, does not",
			func = function()
				local Modes, Reasons = GryMod.Modes, GryMod.ModeReasons

				expect(Module.CloakDropped(Modes.ARMOR, Modes.CLOAK, Reasons.ENERGY)).to.beTrue()
				expect(Module.CloakDropped(Modes.ARMOR, Modes.CLOAK, Reasons.PLAYER)).to.beFalse()
				expect(Module.CloakDropped(Modes.ARMOR, Modes.CLOAK, Reasons.MALFUNCTION)).to.beFalse()
				expect(Module.CloakDropped(Modes.SPEED, Modes.CLOAK, Reasons.ENERGY)).to.beFalse()
				expect(Module.CloakDropped(Modes.ARMOR, Modes.SPEED, Reasons.ENERGY)).to.beFalse()

				-- the hook itself, called directly: the other addons are not told of a fake change
				local listener = hook.GetTable()["GryMod_ModeChanged"]["GryMessagesCloak"]
				expect(listener).to.exist()

				listener(LocalPlayer(), Modes.ARMOR, Modes.CLOAK, Reasons.PLAYER)
				expect(#Module.Texts("status")).to.equal(0)

				listener(LocalPlayer(), Modes.ARMOR, Modes.CLOAK, Reasons.ENERGY)
				expect(Module.Texts("status")[1]).to.equal("Temperature Camo: Disabled!")
			end
		},
		{
			-- fails if a listener that errors could switch the event off
			name = "a listener of GryMod_MessageShown that fails does not stop the line, and its error is printed once",
			func = function()
				hook.Add("GryMod_MessageShown", "gry_messages_test_bad", function() error("boom") end)
				listeners[#listeners + 1] = "gry_messages_test_bad"

				for i = 1, 6 do
					expect(API.ShowMessage("line " .. i, {lane = "status"})).to.beTrue()
				end

				expect(#Module.Texts("status")).to.equal(6)
				expect(#errors).to.equal(6) -- one print per failure, and the event is still registered
				expect(API.ShowMessage("still works", {lane = "status"})).to.beTrue()
			end
		},
		{
			-- fails without Placement
			name = "the stage is as high as the screen and centred across its width",
			func = function()
				local x, y, scale = Module.Placement(1920, 1080)
				expect(math.abs(scale - 1080 / 768) < 1e-9).to.beTrue()
				expect(math.abs(x - (1920 - 1024 * 1080 / 768) / 2) < 1e-6).to.beTrue()
				expect(y).to.equal(0)

				x, _, scale = Module.Placement(1024, 768)
				expect(scale).to.equal(1)
				expect(x).to.equal(0)
			end
		}
	}
}
