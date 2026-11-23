-- Tests of the HUD boot sequences drawn from the original Scaleform movies (GryMod.FlashBoot), GLuaTest format,
-- client realm: HUD_Initialize (the log at the start), HUD_Reboot (after a malfunction) and HUD_Lost (during one).
-- The rules are from the game's code (research notes: research-ui2/crosshair-reboot.md): the start plays the
-- reboot sound, and the activate sound when the log ends; a malfunction plays its sound and the Lost animation,
-- the end of it plays the Reboot movie with its sounds.

local Boot

local played
local realPlay, realOption
local savedEverySpawn

local function run(seconds)
	for _ = 1, math.ceil(seconds * 30) do
		Boot.Step(1 / 30)
	end
end

local function lastSound()
	return played[#played]
end

-- The death of the player, without killing the real one: LocalPlayer answers a stand-in that is dead while `state.dead` is true (every other
-- question goes to the real player), and the real one while it is not. `body(state)` runs with the stubs, the HUD and the sequences built from
-- nothing; everything is put back after it, whatever it does (an error is raised again once the state is clean).
local function withDeath(options, body)
	local HUD = GryMod.FlashHUD
	local real = LocalPlayer()

	if not IsValid(real) or not real:Alive() then
		return
	end

	local state = {dead = false}
	local stand = setmetatable({
		IsValid = function() return true end,
		Alive = function() return not state.dead end
	}, {__index = function(_, key)
		local value = real[key]

		if isfunction(value) then
			return function(_, ...) return value(real, ...) end
		end

		return value
	end})

	local realLocalPlayer, realDraw = LocalPlayer, GryMod.Flash.Draw
	-- the stand-in is a table, not an entity: the real IsSuitEnabled says "no" to it, and the paint would drop the HUD instead of showing the death
	local realEnabled = GryMod.API.IsSuitEnabled
	local saved = {}

	for name, value in pairs(options) do
		saved[name] = GetConVar(name):GetString()
	end

	local ok, err = pcall(function()
		for name, value in pairs(options) do
			GetConVar(name):SetString(value)
		end

		LocalPlayer = function() return state.dead and stand or real end
		GryMod.Flash.Draw = function() end
		GryMod.API.IsSuitEnabled = function(ply) return ply == stand or realEnabled(ply) end
		HUD.Reset()
		Boot.Reset()
		body(state, HUD)
	end)

	LocalPlayer = realLocalPlayer
	GryMod.Flash.Draw = realDraw
	GryMod.API.IsSuitEnabled = realEnabled

	for name, value in pairs(saved) do
		pcall(function() GetConVar(name):SetString(value) end)
	end

	pcall(HUD.Reset)
	pcall(Boot.Reset)

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod HUD boot sequences (Flash)",
	beforeAll = function(state)
		Boot = GryMod.FlashBoot
		savedEverySpawn = GetConVar("gry_boot_every_spawn"):GetString()
	end,
	beforeEach = function(state)
		played = {}
		realPlay = GryMod.PlaySound
		GryMod.PlaySound = function(path)
			played[#played + 1] = path

			return true
		end

		GetConVar("gry_hud_boot"):SetString("1")
		GetConVar("gry_boot_every_spawn"):SetString("0")
		Boot.Reset()
		Boot.ResetSpawn()
	end,
	afterEach = function(state)
		GryMod.PlaySound = realPlay
		GetConVar("gry_boot_every_spawn"):SetString(savedEverySpawn)
		Boot.Reset()
		Boot.ResetSpawn()
	end,
	cases = {
		{
			name = "the three movies load and make sequences, a missing movie makes none",
			func = function(state)
				for _, kind in ipairs({"initialize", "reboot", "lost"}) do
					expect(Boot.New(kind, GryMod.Flash.Load(Boot.MOVIES[kind]))).to.exist()
				end

				expect(Boot.New("initialize", nil)).to.beNil()
				expect(Boot.New("nothing", GryMod.Flash.Load("hud_initialize"))).to.beNil()
			end
		},
		{
			name = "the start log runs 89 frames: still going after 2 seconds, done after 3",
			func = function(state)
				local seq = Boot.New("initialize", GryMod.Flash.Load(Boot.MOVIES.initialize))
				seq:Start()
				seq:Update(2)
				expect(seq:IsDone()).to.beFalse()
				seq:Update(1.1)
				expect(seq:IsDone()).to.beTrue()
			end
		},
		{
			name = "the reboot movie lasts under 5 seconds, the Lost animation never ends by itself",
			func = function(state)
				local reboot = Boot.New("reboot", GryMod.Flash.Load(Boot.MOVIES.reboot))
				reboot:Start()
				reboot:Update(4)
				expect(reboot:IsDone()).to.beFalse()
				reboot:Update(1)
				expect(reboot:IsDone()).to.beTrue()

				local lost = Boot.New("lost", GryMod.Flash.Load(Boot.MOVIES.lost))
				lost:Start()
				lost:Update(30)
				expect(lost:IsDone()).to.beFalse()
			end
		},
		{
			name = "the reboot movie opens its six clips as showProgressBar(true) does, and closes them after 3.97 seconds",
			func = function(state)
				local seq = Boot.New("reboot", GryMod.Flash.Load(Boot.MOVIES.reboot))
				local holder = seq.root:Child("Root")
				local paths = {"Alpha", "Logo.Colorset", "Texts", "LoadBars", "Outlines.Colorset", "Alpha2"}
				seq:Start()

				for _, path in ipairs(paths) do
					expect(holder:Find(path):CurrentLabel()).to.equal("open")
				end

				-- the opening ends on its own, the clips wait on their last frame of it
				seq:Update(3.9)
				expect(holder:Find("Alpha"):CurrentFrame()).to.equal(24)
				-- then the game closes them: they are in their closing animation
				seq:Update(0.2)

				for _, path in ipairs(paths) do
					local frame = holder:Find(path):CurrentFrame()
					expect(frame > 17 and frame < 44).to.beTrue()
				end
			end
		},
		{
			name = "spawning plays the start log with the reboot sound, and the activate sound when it ends",
			func = function(state)
				Boot.Spawned()
				expect(Boot.Current()).to.equal("initialize")
				expect(#played).to.equal(1)
				expect(lastSound()).to.equal(Sound("grymod/hud/hud_reboot.wav"))
				run(2)
				expect(Boot.Current()).to.equal("initialize")
				run(1.2)
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(2)
				expect(lastSound()).to.equal(Sound("grymod/hud/hud_activate_01.wav"))
			end
		},
		{
			name = "a malfunction plays its sound once and shows the Lost animation, a second report does not play it again",
			func = function(state)
				Boot.OnStatus(1)
				expect(Boot.Current()).to.equal("lost")
				expect(Boot.IsLost()).to.beTrue()
				expect(#played).to.equal(1)
				expect(lastSound()).to.equal(Sound("grymod/hud/hud_malfunction_hit.wav"))
				Boot.OnStatus(1)
				expect(#played).to.equal(1)
				run(10)
				expect(Boot.Current()).to.equal("lost")
			end
		},
		{
			name = "the end of a malfunction plays the Reboot movie and no sound at all (the original plays none), whatever the spawn switch says",
			func = function(state)
				for _, every in ipairs({"0", "1"}) do
					GetConVar("gry_boot_every_spawn"):SetString(every)
					Boot.Reset()
					Boot.OnStatus(1)
					played = {}
					Boot.OnStatus(0)
					expect(Boot.IsLost()).to.beFalse()
					expect(Boot.Current()).to.equal("reboot")
					expect(#played).to.equal(0)
					run(5.2)
					expect(Boot.Current()).to.beNil()
					expect(#played).to.equal(0)
				end
			end
		},
		{
			name = "only the first spawn plays the start log: the next ones play nothing and show nothing",
			func = function(state)
				Boot.Spawned()
				run(3.2)
				expect(Boot.Current()).to.beNil()
				played = {}
				Boot.Spawned()
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(0)
				Boot.Spawned()
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(0)
			end
		},
		{
			name = "a respawn that comes while the first log still runs does not play it again or cut it",
			func = function(state)
				Boot.Spawned()
				run(1)
				played = {}
				Boot.Spawned()
				expect(Boot.Current()).to.equal("initialize")
				expect(#played).to.equal(0)
			end
		},
		{
			name = "gry_boot_every_spawn 1 brings back the log and its two sounds at every spawn",
			func = function(state)
				local convar = GetConVar("gry_boot_every_spawn")
				expect(convar:GetDefault()).to.equal("0")
				convar:SetString("1")

				for _ = 1, 3 do
					played = {}
					Boot.Spawned()
					expect(Boot.Current()).to.equal("initialize")
					expect(lastSound()).to.equal(Sound("grymod/hud/hud_reboot.wav"))
					run(3.2)
					expect(Boot.Current()).to.beNil()
					expect(#played).to.equal(2)
					expect(lastSound()).to.equal(Sound("grymod/hud/hud_activate_01.wav"))
				end
			end
		},
		{
			name = "a spawn after a death is clean: no log, no sound, and the malfunction of the last life is forgotten",
			func = function(state)
				Boot.Spawned()
				run(3.2)
				Boot.OnStatus(1)
				-- death: what the paint hook does when the player is no longer alive
				Boot.Died()
				expect(Boot.Current()).to.beNil()
				expect(Boot.IsLost()).to.beFalse()
				played = {}
				Boot.Spawned()
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(0)
				-- the suit is up again: a new malfunction starts from nothing
				Boot.OnStatus(1)
				expect(Boot.Current()).to.equal("lost")
			end
		},
		{
			name = "gry_boot_every_spawn has a check box in the options",
			func = function(state)
				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_boot_every_spawn"]).to.beTrue()
			end
		},
		{
			name = "a status 0 without a malfunction before does nothing",
			func = function(state)
				Boot.OnStatus(0)
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(0)
			end
		},
		{
			name = "with the boot switch off there is no sequence and no sound",
			func = function(state)
				GetConVar("gry_hud_boot"):SetString("0")
				Boot.Spawned()
				Boot.OnStatus(1)
				Boot.OnStatus(0)
				expect(Boot.Current()).to.beNil()
				expect(Boot.IsLost()).to.beFalse()
				expect(#played).to.equal(0)
			end
		},
		{
			name = "the texts of the movies are English words, not the @ui_ keys, in every frame of every sequence",
			func = function(state)
				expect(Boot.Localise("@ui_init_text01")).to.equal("Loading Control Unit ")
				expect(Boot.Localise("@UI_SYSTEM_OVERRUN")).to.equal("SYSTEM OVERRUN")
				expect(Boot.Localise("plain")).to.equal("plain")
				expect(Boot.Localise("@ui_nothing_like_this")).to.equal("nothing like this")
				expect(Boot.Localise(nil)).to.equal(nil)

				for _, kind in ipairs({"initialize", "reboot", "lost"}) do
					local seq = Boot.New(kind, GryMod.Flash.Load(Boot.MOVIES[kind]))
					seq:Start()
					local keys = {}

					for _ = 1, math.ceil(Boot.DURATION[kind] or 4) * 30 do
						seq:Update(1 / 30)
						seq.root:MapText(function(text)
							if isstring(text) and string.sub(text, 1, 4) == "@ui_" then
								keys[text] = true
							end

							return text
						end)
					end

					expect(table.Count(keys)).to.equal(0)
				end
			end
		},
		{
			name = "a spawn during a malfunction keeps the Lost animation, whatever order the HUD and the sequences are painted in",
			func = function(state)
				Boot.OnStatus(1)
				played = {}
				Boot.Spawned()
				expect(Boot.Current()).to.equal("lost")
				expect(#played).to.equal(0)
				Boot.OnStatus(1)
				expect(#played).to.equal(0)
				Boot.OnStatus(0)
				expect(Boot.Current()).to.equal("reboot")
			end
		},
		{
			name = "turning the HUD off drops a sequence that was on, so that nothing stays stuck when it comes back",
			func = function(state)
				local hud = GetConVar("gry_hud"):GetString()
				Boot.OnStatus(1)
				GetConVar("gry_hud"):SetString("0")
				hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
				GetConVar("gry_hud"):SetString(hud)
				expect(Boot.Current()).to.beNil()
				expect(Boot.IsLost()).to.beFalse()
			end
		},
		{
			name = "rebuilding the pictures (a new colour) keeps the sequence that is on, without playing its sound again",
			func = function(state)
				Boot.OnStatus(1)
				played = {}
				Boot.Rebuild()
				expect(Boot.Current()).to.equal("lost")
				Boot.OnStatus(1) -- the rebuilt HUD says its state again
				expect(#played).to.equal(0)
				Boot.OnStatus(0)
				expect(Boot.Current()).to.equal("reboot")

				GryMod.FlashHUD.ResetAll()
				expect(Boot.Current()).to.equal("reboot")
			end
		},
		{
			name = "the HUD reports its malfunction to the sequences when its status changes (the empty-bar rule on, gry_malfunction_empty 1)",
			func = function(state)
				local HUD = GryMod.FlashHUD
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local convar = GetConVar("gry_malfunction_empty")
				local savedValue = convar:GetString()
				convar:SetString("1")
				local real, realDraw = HUD.MalfunctionFor, GryMod.Flash.Draw
				GryMod.Flash.Draw = function() end
				HUD.Reset()
				HUD.MalfunctionFor = function() return 1 end
				HUD.Paint()
				local lost = Boot.IsLost()
				HUD.MalfunctionFor = function() return 0 end
				HUD.Paint()
				local after = Boot.Current()
				HUD.MalfunctionFor = real
				GryMod.Flash.Draw = realDraw
				convar:SetString(savedValue)
				HUD.Reset()

				expect(lost).to.beTrue()
				expect(after).to.equal("reboot")
			end
		},
		{
			name = "with the default setting an empty bar alone puts nothing on: no Lost sequence, the HUD is not told of a malfunction",
			func = function(state)
				local HUD = GryMod.FlashHUD
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

				local convar = GetConVar("gry_malfunction_empty")
				local savedValue = convar:GetString()
				convar:SetString("0")
				local real, realDraw = HUD.MalfunctionFor, GryMod.Flash.Draw
				GryMod.Flash.Draw = function() end
				HUD.Reset()
				HUD.MalfunctionFor = function() return 1 end
				HUD.Paint()
				local lost = Boot.IsLost()
				HUD.MalfunctionFor = real
				GryMod.Flash.Draw = realDraw
				convar:SetString(savedValue)
				HUD.Reset()

				expect(lost).to.beFalse()
			end
		}		,
		-- the Lost screen at the death (gry_hud_lost_on_death): the original's death handler puts the HUD down
		{
			-- needs: Module.DeathPhase (cl_hud_flash.lua)
			name = "what the HUD paint does about a death: start when it dies with the HUD up and the setting on, keep while dead, respawn when alive again, drop otherwise",
			func = function(state)
				local P = GryMod.FlashHUD.DeathPhase
				-- alive: nothing, unless a death was shown (the respawn)
				expect(P(true, true, false, true, true)).to.beNil()
				expect(P(true, false, false, false, true)).to.beNil()
				expect(P(true, false, true, true, true)).to.equal("respawn")
				-- dead: the first paint after the life is the start, with a HUD built and the setting on
				expect(P(false, true, false, true, true)).to.equal("start")
				expect(P(false, true, false, true, false)).to.equal("drop") -- setting off
				expect(P(false, true, false, false, true)).to.equal("drop") -- no HUD to turn red
				expect(P(false, false, false, true, true)).to.equal("drop") -- was already dead (arrived dead): nothing to start
				expect(P(false, false, true, true, true)).to.equal("keep")
				expect(P(false, true, true, false, false)).to.equal("keep") -- the setting turned off while the death is shown does not cut it
			end
		},
		{
			-- needs: HUD.GoDown (the paint's start phase), Boot.HoldDeath / EndDeath, the Boot paint hook keeping the Lost screen while the death is held
			name = "dying with the HUD up: the HUD turns red, the Lost screen and its sound start once, they stay while the player is dead, and the respawn ends them",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "1", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					-- the life has begun: the spawn is behind (no start-up log in the way of what is checked here)
					Boot.NoteSpawn()
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					Boot.Reset()
					expect(HUD.Status()).to.equal(0)
					expect(Boot.IsLost()).to.beFalse()
					played = {}

					life.dead = true
					HUD.Paint()
					expect(HUD.Status()).to.equal(1)
					expect(HUD.DeathShown()).to.beTrue()
					expect(Boot.IsLost()).to.beTrue()
					expect(#played).to.equal(1)
					expect(lastSound()).to.equal(Sound("grymod/hud/hud_malfunction_hit.wav"))

					-- the paint of the sequences does not end the Lost screen of a life that is over, and nothing plays twice
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(Boot.IsLost()).to.beTrue()
					expect(HUD.Status()).to.equal(1)
					expect(#played).to.equal(1)

					-- the respawn: the HUD is a new one (working), the Lost screen is over, with no sound
					life.dead = false
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					HUD.Paint()
					expect(HUD.DeathShown()).to.beFalse()
					expect(HUD.Status()).to.equal(0)
					expect(Boot.IsLost()).to.beFalse()
					expect(Boot.Current()).to.beNil()
					expect(#played).to.equal(1)
				end)
			end
		},
		{
			-- needs: Boot.Step holding the Lost movie at Boot.LOST_HOLD_FRAME while the death is held (the movie itself ends on an empty stage at frame 137,
			-- 4.6 s after it starts: the panel vanished while the player was still dead)
			name = "the Lost screen of a death is still on the stage long after the movie's own end, and the respawn lets it go",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "1", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					Boot.NoteSpawn()
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					life.dead = true
					HUD.Paint()
					expect(Boot.IsLost()).to.beTrue()

					-- the clip of the movie's stage, found through the sequences table the step works on
					local sequences
					local i = 1

					while true do
						local name, value = debug.getupvalue(Boot.Step, i)

						if not name then break end

						if name == "sequences" then sequences = value end

						i = i + 1
					end

					expect(sequences ~= nil and sequences.lost ~= nil).to.beTrue()

					local clip = sequences.lost.root:Child("Root")

					run(8) -- the movie alone would be over after 4.6 s
					expect(Boot.IsLost()).to.beTrue()
					expect(clip.frame < 137).to.beTrue()
					expect(clip.frame >= 11).to.beTrue() -- past the start, on a frame that has the panel

					-- the respawn: nothing stays
					life.dead = false
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					HUD.Paint()
					expect(Boot.Current()).to.beNil()
				end)
			end
		},
		{
			-- needs: the respawn handled by the HUD paint alone too (the sequences' paint not run first), through Boot.EndDeath
			name = "the Lost screen of a death ends at the respawn whichever of the two paints runs first, and the HUD's own paint ends it too",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "1", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					Boot.NoteSpawn()
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					life.dead = true
					HUD.Paint()
					expect(Boot.IsLost()).to.beTrue()
					life.dead = false
					HUD.Paint() -- the HUD first: it ends the Lost screen itself
					expect(Boot.IsLost()).to.beFalse()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(Boot.IsLost()).to.beFalse()
					expect(HUD.Status()).to.equal(0)

					-- the sequences' paint first
					HUD.Reset()
					Boot.Reset()
					Boot.NoteSpawn()
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					life.dead = true
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(Boot.IsLost()).to.beTrue()
					life.dead = false
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(Boot.IsLost()).to.beFalse()
					HUD.Paint()
					expect(Boot.IsLost()).to.beFalse()
					expect(HUD.Status()).to.equal(0)
				end)
			end
		},
		{
			-- needs: the setting read by the paint; off gives the old behaviour (the HUD is dropped at the death)
			name = "with gry_hud_lost_on_death 0 the HUD just goes at the death, as it did: no red HUD, no Lost screen, no sound",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "0", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					HUD.Paint()
					played = {}
					life.dead = true
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(HUD.Status()).to.beNil()
					expect(HUD.DeathShown()).to.beFalse()
					expect(Boot.IsLost()).to.beFalse()
					expect(#played).to.equal(0)
				end)
			end
		},
		{
			-- needs: the start phase only for a HUD that was up (built and alive at the last paint)
			name = "a player who is dead when the HUD first paints gets no Lost screen (there was no life to end)",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "1", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					life.dead = true
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(HUD.Status()).to.beNil()
					expect(Boot.IsLost()).to.beFalse()
					expect(#played).to.equal(0)
				end)
			end
		},
		{
			-- needs: an already down suit (status 1) kept as it is at the death: one Lost screen and one sound, not two
			name = "dying while the suit is already down keeps the one Lost screen it had: no second sound, and it ends at the respawn",
			func = function(state)
				withDeath({gry_hud_lost_on_death = "1", gry_hud = "1", gry_hud_boot = "1"}, function(life, HUD)
					HUD.Paint()
					Boot.OnStatus(1)
					HUD.GoDown()
					expect(#played).to.equal(1)
					life.dead = true
					HUD.Paint()
					hook.GetTable().HUDPaint["GRYFLASHBOOT"]()
					expect(#played).to.equal(1)
					expect(Boot.IsLost()).to.beTrue()
					life.dead = false
					HUD.Paint()
					expect(Boot.IsLost()).to.beFalse()
				end)
			end
		},
		{
			-- needs: the setting and its check box
			name = "gry_hud_lost_on_death exists (1 by default) and has a check box in the options",
			func = function(state)
				local convar = GetConVar("gry_hud_lost_on_death")
				expect(convar).toNot.beNil()
				expect(convar:GetDefault()).to.equal("1")
				local found = {}
				local panel = vgui.Create("ControlPanel")
				local ok, err = pcall(function()
					GryMod.GryOptionschute(panel)

					local function walk(p)
						for _, child in ipairs(p:GetChildren()) do
							if child.ClassName == "DCheckBoxLabel" and child.Button then
								found[child.Button.m_strConVar or "?"] = true
							end

							walk(child)
						end
					end

					walk(panel)
				end)

				panel:Remove()

				if not ok then
					error(err, 0)
				end

				expect(found["gry_hud_lost_on_death"]).to.beTrue()
			end
		}
	}
}
