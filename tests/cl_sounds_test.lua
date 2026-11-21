-- Tests of the decisions of the suit sounds on the client (cl_sounds.lua), GLuaTest format, client realm: which
-- file the armor hit plays, and when the repair sound starts and stops. Nothing is listened to: GryMod.PlaySound is
-- replaced and the repair channel is a table that records its calls.

local savedPlay
local savedConVars = {}

local function setConVar(name, value)
	local convar = GetConVar(name)

	if savedConVars[name] == nil then
		savedConVars[name] = convar:GetString()
	end

	convar:SetString(value)
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

local function receive(name)
	local receiver = net.Receivers[name]
	assert(receiver, "no receiver for " .. name)
	receiver()
end

return {
	groupName = "GryMod sounds (client)",
	beforeEach = function(state)
		savedPlay = GryMod.PlaySound
		GryMod.SoundMix.ResetLimits()
		state.channel = GryMod.RegenSound.GetChannel()
		setConVar("gry_sounds", "1")
		setConVar("gry_sound_regen", "1")
	end,
	afterEach = function(state)
		GryMod.PlaySound = savedPlay
		GryMod.RegenSound.SetChannel(state.channel)
		hook.Remove("Think", "GryModSoundhealthregenfadeaway")

		for name, value in pairs(savedConVars) do
			GetConVar(name):SetString(value)
		end

		savedConVars = {}
	end,
	cases = {
		{
			name = "the armor hit uses the 13 suit_bullet_impact_fp files of the game (mat_armor_fp), all of them, each one shipped",
			func = function(state)
				local list = GryMod.ArmorHitSounds
				expect(#list).to.equal(13)
				local seen = {}

				for _, path in ipairs(list) do
					expect(seen[path]).to.beNil()
					seen[path] = true
					expect(file.Exists("sound/" .. path, "GAME")).to.beTrue()
					expect(path:find("^grymod/suit/suit_bullet_impact_fp_%d%d%.wav$") ~= nil).to.beTrue()
				end

				-- every suit_bullet_impact file that is shipped is in the list (none is left unused)
				for _, name in ipairs(file.Find("sound/grymod/suit/suit_bullet_impact_*", "GAME")) do
					expect(seen["grymod/suit/" .. name]).to.beTrue()
				end
			end
		},
		{
			name = "the armor hit shuffles like the game: every file once before any plays again, never the same twice in a row",
			func = function(state)
				local previous
				GryMod.ResetArmorHitSounds()

				for round = 1, 4 do
					local seen, count = {}, 0

					for i = 1, #GryMod.ArmorHitSounds do
						local path = GryMod.NextArmorHitSound()
						expect(seen[path]).to.beNil()
						expect(path ~= previous).to.beTrue()
						seen[path] = true
						previous = path
						count = count + 1
					end

					expect(count).to.equal(13)
				end
			end
		},
		{
			name = "the armor hit message plays one file of the list, in or out of the water",
			func = function(state)
				local played = {}
				GryMod.PlaySound = function(path) played[#played + 1] = path end
				receive("gry_armor_hit_sound")
				expect(#played).to.equal(1)
				local found = false

				for _, path in ipairs(GryMod.ArmorHitSounds) do
					if Sound(path) == played[1] then found = true end
				end

				expect(found).to.beTrue()
			end
		},
		{
			name = "the energy-critical voice is due when the energy crosses 25 (50 of the game's 200) downwards, 30 s after the last one",
			func = function(state)
				local due = GryMod.EnergyCriticalDue
				expect(due).toNot.beNil()
				expect(GryMod.ENERGY_CRITICAL_LEVEL).to.equal(25)
				expect(GryMod.ENERGY_CRITICAL_PAUSE).to.equal(30)
				-- the crossing: above the level before, at or under it now
				expect(due(26, 25, nil, 100)).to.beTrue()
				expect(due(80, 10, nil, 100)).to.beTrue()
				expect(due(30, 24.9, nil, 100)).to.beTrue()
				-- no crossing: still above, already under, rising through it, or exactly on the level before
				expect(due(80, 30, nil, 100)).to.beFalse()
				expect(due(24, 10, nil, 100)).to.beFalse()
				expect(due(10, 50, nil, 100)).to.beFalse()
				expect(due(25, 20, nil, 100)).to.beFalse()
				-- the old rule (a fifth of the bar) is gone: 21 to 19 is not a crossing of 25
				expect(due(21, 19, nil, 100)).to.beFalse()
				-- the pause: silent for 30 s after the last time, then allowed again
				expect(due(26, 20, 100, 110)).to.beFalse()
				expect(due(26, 20, 100, 129.9)).to.beFalse()
				expect(due(26, 20, 100, 130)).to.beTrue()
				expect(due(26, 20, 100, 131)).to.beTrue()
				-- no value yet
				expect(due(nil, 10, nil, 100)).to.beFalse()
				expect(due(80, nil, nil, 100)).to.beFalse()
			end
		},
		{
			name = "the Think hook plays the energy-critical voice through the mix once, then waits the 30 s",
			func = function(state)
				local hookFunc = hook.GetTable().Think["GryModSounds"]
				expect(hookFunc).toNot.beNil()
				local realDue, realNow = GryMod.EnergyCriticalDue, GryMod.SoundMix.Now
				local calls, plays, now = {}, {}, 1000
				local surfaced = 0
				local realSurface = surface.PlaySound
				local ok, err = pcall(function()
					GryMod.PlaySound = function(path) plays[#plays + 1] = path end
					GryMod.SoundMix.Now = function() return now end
					surface.PlaySound = function() surfaced = surfaced + 1 end
					GryMod.EnergyCriticalDue = function(prev, cur, lastAt, t)
						calls[#calls + 1] = {prev, cur, lastAt, t}

						return #calls == 1 or realDue(prev, cur, lastAt, t)
					end
					hookFunc()
					expect(#plays).to.equal(1)
					expect(plays[1]).to.equal(Sound("grymod/suit/suit_energy_critical.wav"))
					expect(calls[1][4]).to.equal(1000)
					now = 1010
					hookFunc()
					-- the Think passes the time of the last play, so the real rule can hold it back
					expect(calls[2][3]).to.equal(1000)
					expect(calls[2][4]).to.equal(1010)
					expect(surfaced).to.equal(0)
				end)
				GryMod.EnergyCriticalDue, GryMod.SoundMix.Now, surface.PlaySound = realDue, realNow, realSurface
				GryMod.ResetEnergyCritical()
				assert(ok, err)
			end
		},
		{
			name = "gry_sound_regen exists, is on by default and saved",
			func = function(state)
				local convar = GetConVar("gry_sound_regen")
				expect(convar ~= nil).to.beTrue()
				expect(convar:GetDefault()).to.equal("1")
				-- saved like the other settings (CreateClientConVar with shouldsave: the same flags as gry_sounds)
				expect(convar:GetFlags()).to.equal(GetConVar("gry_sounds"):GetFlags())
			end
		},
		{
			name = "the repair sound starts from the beginning each time, not from where the last play ended",
			func = function(state)
				local channel = fakeChannel()
				GryMod.RegenSound.SetChannel(channel)
				receive("gry_start_health_regen")
				expect(channel.calls[#channel.calls]).to.equal("Play")
				expect(table.HasValue(channel.calls, "SetTime=0")).to.beTrue()

				local setTime, play

				for i, call in ipairs(channel.calls) do
					if call == "SetTime=0" then setTime = setTime or i end
					if call == "Play" then play = play or i end
				end

				expect(setTime < play).to.beTrue()
			end
		},
		{
			name = "the repair sound does not start with gry_sound_regen 0 or gry_sounds 0",
			func = function(state)
				local channel = fakeChannel()
				GryMod.RegenSound.SetChannel(channel)
				setConVar("gry_sound_regen", "0")
				receive("gry_start_health_regen")
				expect(#channel.calls).to.equal(0)
				setConVar("gry_sound_regen", "1")
				setConVar("gry_sounds", "0")
				receive("gry_start_health_regen")
				expect(#channel.calls).to.equal(0)
			end
		},
		{
			name = "the stop message fades the repair sound out, and a start during the fade cancels it",
			func = function(state)
				local channel = fakeChannel()
				GryMod.RegenSound.SetChannel(channel)
				receive("gry_stop_health_regen")
				expect(hook.GetTable().Think["GryModSoundhealthregenfadeaway"] ~= nil).to.beTrue()
				receive("gry_start_health_regen")
				expect(hook.GetTable().Think["GryModSoundhealthregenfadeaway"]).to.beNil()
			end
		},
		{
			name = "the options panel has a check box for the repair sound, wired to gry_sound_regen",
			func = function(state)
				local panel = vgui.Create("ControlPanel")
				GryMod.GryOptionschute(panel)
				local found = false

				local function walk(p)
					for _, child in ipairs(p:GetChildren()) do
						if child.ClassName == "DCheckBoxLabel" and child.Button and child.Button.m_strConVar == "gry_sound_regen" then
							found = true
						end

						walk(child)
					end
				end

				walk(panel)
				panel:Remove()
				expect(found).to.beTrue()
			end
		}
	}
}
