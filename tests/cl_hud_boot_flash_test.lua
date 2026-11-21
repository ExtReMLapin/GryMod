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
		}
	}
}
