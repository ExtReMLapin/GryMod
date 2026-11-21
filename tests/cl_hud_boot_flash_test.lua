-- Tests of the HUD boot sequences drawn from the original Scaleform movies (GryMod.FlashBoot), GLuaTest format,
-- client realm: HUD_Initialize (the log at the start), HUD_Reboot (after a malfunction) and HUD_Lost (during one).
-- The rules are from the game's code (research notes: research-ui2/crosshair-reboot.md): the start plays the
-- reboot sound, and the activate sound when the log ends; a malfunction plays its sound and the Lost animation,
-- the end of it plays the Reboot movie with its sounds.

local Boot

local played
local realPlay, realOption

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
	end,
	beforeEach = function(state)
		played = {}
		realPlay = GryMod.PlaySound
		GryMod.PlaySound = function(path)
			played[#played + 1] = path

			return true
		end

		GetConVar("gry_hud_boot"):SetString("1")
		Boot.Reset()
	end,
	afterEach = function(state)
		GryMod.PlaySound = realPlay
		Boot.Reset()
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
				expect(lastSound()).to.equal(Sound("cry_hud_reboot.wav"))
				run(2)
				expect(Boot.Current()).to.equal("initialize")
				run(1.2)
				expect(Boot.Current()).to.beNil()
				expect(#played).to.equal(2)
				expect(lastSound()).to.equal(Sound("cry_hud_activate.wav"))
			end
		},
		{
			name = "a malfunction plays its sound once and shows the Lost animation, a second report does not play it again",
			func = function(state)
				Boot.OnStatus(1)
				expect(Boot.Current()).to.equal("lost")
				expect(Boot.IsLost()).to.beTrue()
				expect(#played).to.equal(1)
				expect(lastSound()).to.equal(Sound("cry_hud_malfunction.wav"))
				Boot.OnStatus(1)
				expect(#played).to.equal(1)
				run(10)
				expect(Boot.Current()).to.equal("lost")
			end
		},
		{
			name = "the end of a malfunction plays the Reboot movie with the reboot sound, then the activate sound",
			func = function(state)
				Boot.OnStatus(1)
				played = {}
				Boot.OnStatus(0)
				expect(Boot.IsLost()).to.beFalse()
				expect(Boot.Current()).to.equal("reboot")
				expect(lastSound()).to.equal(Sound("cry_hud_reboot.wav"))
				run(5.2)
				expect(Boot.Current()).to.beNil()
				expect(lastSound()).to.equal(Sound("cry_hud_activate.wav"))
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
				expect(Boot.Localise("@ui_nothing_like_this")).to.equal("@ui_nothing_like_this")
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
			name = "the HUD reports its malfunction to the sequences when its status changes",
			func = function(state)
				local HUD = GryMod.FlashHUD
				local ply = LocalPlayer()

				if not IsValid(ply) or not ply:Alive() then
					return
				end

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
				HUD.Reset()

				expect(lost).to.beTrue()
				expect(after).to.equal("reboot")
			end
		}
	}
}
