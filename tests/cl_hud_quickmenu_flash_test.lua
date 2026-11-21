-- Tests of the quick menu driven by the original Flash movie (GryMod.FlashMenu), GLuaTest format, client realm.
-- Needs the converted movie lua/grymod/flash/hud_quickmenu.lua. The rules come from the movie's ActionScript and
-- from the game's code (research notes: D:\dev\crysis-hud-research\research-qm\NOTES.md).

local ALL = {Speed = true, Strength = true, Cloak = true, Armor = true, Weapon = true}

local function newMenu(active, defect)
	local menu = GryMod.FlashMenu.New(GryMod.Flash.Load("hud_quickmenu"))
	menu:SetStates(active or ALL, defect or {})

	return menu
end

local function run(menu, seconds)
	for _ = 1, math.ceil(seconds * 30) do
		menu:Update(1 / 30)
	end
end

local function openMenu(active, defect)
	local menu = newMenu(active, defect)
	menu:Open()
	run(menu, 0.4)

	return menu
end

local function modeClip(menu, name)
	return menu.qm:Child(name)
end

local function near(a, b)
	return math.abs(a - b) < 0.01
end

return {
	groupName = "GryMod quick menu (Flash)",
	-- opening and closing the menu play its sounds: nothing is played by the tests (the mix's single exit is replaced)
	beforeEach = function(state)
		state.realEmit = GryMod.SoundMix.Emit
		GryMod.SoundMix.Emit = function() end
		state.savedKeep = GetConVar("gry_menu_keep_highlight"):GetString()
		GetConVar("gry_menu_keep_highlight"):SetString("1")
	end,
	afterEach = function(state)
		GryMod.SoundMix.Emit = state.realEmit
		GetConVar("gry_menu_keep_highlight"):SetString(state.savedKeep)
	end,
	cases = {
		{
			name = "the angle of a pointer vector: 0 right, 90 up, 180 left, 270 down, anticlockwise",
			func = function(state)
				local M = GryMod.FlashMenu
				expect(near(M.ThetaFor(0, -25), 90)).to.beTrue()
				expect(near(M.ThetaFor(25, 0), 0)).to.beTrue()
				expect(near(M.ThetaFor(-25, 0), 180)).to.beTrue()
				expect(near(M.ThetaFor(0, 25), 270)).to.beTrue()
				expect(near(M.ThetaFor(20, 30), 303.69)).to.beTrue()
			end
		},
		{
			name = "the sectors are the game's: Speed 52-128, Armor 128-205, Weapon 205-260, Cloak 260-342, Strength the rest",
			func = function(state)
				local M = GryMod.FlashMenu
				expect(M.SectorFor(90)).to.equal("Speed")
				expect(M.SectorFor(52)).to.equal("Speed")
				expect(M.SectorFor(127.9)).to.equal("Speed")
				expect(M.SectorFor(128)).to.equal("Defense")
				expect(M.SectorFor(180)).to.equal("Defense")
				expect(M.SectorFor(205)).to.equal("Weapon")
				expect(M.SectorFor(259.9)).to.equal("Weapon")
				expect(M.SectorFor(260)).to.equal("Cloak")
				expect(M.SectorFor(341.9)).to.equal("Cloak")
				expect(M.SectorFor(342)).to.equal("Strength")
				expect(M.SectorFor(0)).to.equal("Strength")
				expect(M.SectorFor(51.9)).to.equal("Strength")
			end
		},
		{
			name = "the pointer: a flick past 25 selects and clamps, coming back under 12.5 returns to the centre, in between nothing changes",
			func = function(state)
				local M = GryMod.FlashMenu
				local pointer = M.NewPointer()
				expect(pointer:Selection()).to.equal("Center")
				pointer:Move(5, 0)
				expect(pointer:Selection()).to.equal("Center") -- too small to select
				pointer:Move(40, 0)
				expect(pointer:Selection()).to.equal("Strength")
				expect(near(math.sqrt(pointer.x * pointer.x + pointer.y * pointer.y), 25)).to.beTrue() -- clamped
				pointer:Move(-10, 0) -- 15 left of the clamp: between the two thresholds, nothing changes
				expect(pointer:Selection()).to.equal("Strength")
				pointer:Move(-5, 0) -- 10: under 12.5, back to the centre with the accumulator reset
				expect(pointer:Selection()).to.equal("Center")
				expect(pointer.x).to.equal(0)
				expect(pointer.y).to.equal(0)
			end
		},
		{
			name = "the pointer starts on the current mode, as the game places its cursor",
			func = function(state)
				local M = GryMod.FlashMenu
				expect(M.NewPointer("Speed"):Selection()).to.equal("Speed")
				expect(M.NewPointer("Strength"):Selection()).to.equal("Strength")
				expect(M.NewPointer("Cloak"):Selection()).to.equal("Cloak")
				expect(M.NewPointer("Armor"):Selection()).to.equal("Defense")
				expect(M.NewPointer("Nothing"):Selection()).to.equal("Center")
			end
		},
		{
			name = "the menu is hidden until opened, and the legacy critical area and colour holders never show",
			func = function(state)
				local menu = newMenu()
				expect(menu:IsShown()).to.beFalse()
				menu:Open()
				expect(menu:IsShown()).to.beTrue()
				expect(menu.root:Child("Line").visible).to.beFalse()
				expect(menu.root:Child("Over").visible).to.beFalse()
				expect(menu.root:Child("Text").visible).to.beFalse()
				expect(menu.root:Child("Back").visible).to.beFalse()
				expect(menu.root:Find("Root.CriticalArea").visible).to.beFalse()
			end
		},
		{
			name = "opening plays the original animation to its resting frame, the five hexagons and the ring are there",
			func = function(state)
				local menu = openMenu()
				expect(menu.qm:CurrentFrame()).to.equal(8)
				expect(menu.qm.playing).to.beFalse()

				for _, name in ipairs({"Cloak", "Weapon", "Armor", "Strength", "Speed", "Circle"}) do
					expect(menu.qm:Child(name) ~= nil).to.beTrue()
				end
			end
		},
		{
			name = "an active mode is on its first frame, an inactive one on the grey frame, a defective one on the red frame",
			func = function(state)
				local menu = openMenu({Speed = true, Strength = true, Cloak = true}, {Armor = true})
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(1)
				expect(modeClip(menu, "Weapon"):CurrentFrame()).to.equal(3) -- not active
				expect(modeClip(menu, "Armor"):CurrentFrame()).to.equal(4) -- defective wins
			end
		},
		{
			name = "pointing at a mode puts it on the hover frame and the others back; the ring follows",
			func = function(state)
				local menu = openMenu()
				menu:Select("Speed")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(1)
				local circle = menu.qm:Child("Circle")
				expect(circle:Child("Indicator").visible).to.beTrue()
				expect(circle:Child("Circle_green").visible).to.beTrue()
				expect(circle:Child("Circle_orange").visible).to.beFalse()
				menu:Select("Cloak")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(1)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(2)
				-- the centre: no indicator, the orange ring
				menu:Select("Center")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(1)
				expect(circle:Child("Indicator").visible).to.beFalse()
				expect(circle:Child("Circle_orange").visible).to.beTrue()
				expect(circle:Child("Circle_green").visible).to.beFalse()
			end
		},
		{
			name = "an inactive or defective mode cannot be pointed at: no hover, no indicator, and it is not a selection",
			func = function(state)
				local menu = openMenu({Speed = true, Strength = true, Cloak = true, Armor = true}, {Cloak = true})
				menu:Select("Weapon")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Weapon"):CurrentFrame()).to.equal(3)
				expect(menu.qm:Child("Circle"):Child("Indicator").visible).to.beFalse()
				expect(menu:Choice()).to.equal(nil)
				menu:Select("Cloak")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(4)
				expect(menu:Choice()).to.equal(nil)
				menu:Select("Speed")
				expect(menu:Choice()).to.equal("Speed")
			end
		},
		{
			name = "the indicator turns with the pointer: its rotation is 90 minus the angle",
			func = function(state)
				local menu = openMenu()
				menu:Select("Speed")
				menu:SetAngle(90)
				menu:Update(1 / 30)
				local m = menu.qm:Child("Circle"):Child("Indicator").entry.m
				expect(near(m[1], 1)).to.beTrue() -- no rotation: straight up
				menu:SetAngle(0)
				m = menu.qm:Child("Circle"):Child("Indicator").entry.m
				expect(near(m[1], 0)).to.beTrue() -- 90 degrees clockwise: pointing right
				expect(near(m[2], 1)).to.beTrue()
			end
		},
		{
			name = "a hover sent before the opening animation is done is shown as soon as the movie can (its functions exist from frame 8)",
			func = function(state)
				local menu = newMenu()
				menu:Open()
				menu:Select("Speed")
				run(menu, 2 / 30) -- frame 4: the modes are not placed yet
				expect(menu.qm:CurrentFrame() < 8).to.beTrue()
				run(menu, 0.4)
				menu:Update(1 / 30)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2) -- applied as soon as the movie can
			end
		},
		{
			name = "the chosen icon stays lit while the menu fades out (the original goes back to the plain icon only when the pointer moves)",
			func = function(state)
				local menu = openMenu()
				menu:Select("Speed")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2)
				menu:Close()
				expect(menu.closing).to.beTrue()
				menu:Update(0.1)
				expect(menu.qm:CurrentFrame() > 8).to.beTrue() -- in the fade, not at its end
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(1)
				-- one frame later, still in the fade (the film itself drops the icons from its frame 14)
				menu:Update(1 / 30)
				expect(menu:IsShown()).to.beTrue()
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2)
				run(menu, 0.5)
				expect(menu:IsShown()).to.beFalse()
			end
		},
		{
			name = "with gry_menu_keep_highlight 0 the icons go back to plain at the release, as before; the switch is saved, on by default, with a check box",
			func = function(state)
				local convar = GetConVar("gry_menu_keep_highlight")
				expect(convar:GetDefault()).to.equal("1")
				convar:SetString("0")
				local menu = openMenu()
				menu:Select("Speed")
				menu:Update(1 / 30)
				menu:Close()
				menu:Update(0.1)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(1)

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

				expect(found["gry_menu_keep_highlight"]).to.beTrue()
			end
		},
		{
			name = "closing plays the original fade, hides the menu at its end and it can open again",
			func = function(state)
				local menu = openMenu()
				menu:Close()
				expect(menu.qm:CurrentLabel()).to.equal("close")
				run(menu, 0.5)
				expect(menu:IsShown()).to.beFalse()
				menu:Open()
				expect(menu:IsShown()).to.beTrue()
				run(menu, 0.4)
				expect(menu.qm:CurrentFrame()).to.equal(8)
				expect(modeClip(menu, "Speed") ~= nil).to.beTrue()
			end
		},
		{
			name = "a malfunction puts every mode on the red frame and the ring on its malfunction frame, nothing can be chosen",
			func = function(state)
				local menu = openMenu()
				menu:Destroy(1)
				menu:Update(1 / 30)
				run(menu, 0.2)

				for _, name in ipairs({"Cloak", "Weapon", "Armor", "Strength", "Speed"}) do
					expect(modeClip(menu, name):CurrentFrame()).to.equal(4)
				end

				expect(menu.qm:Child("Circle"):CurrentLabel()).to.equal("malfunction")
				menu:Select("Speed")
				expect(menu:Choice()).to.equal(nil)
				-- and it recovers
				menu:Destroy(0)
				menu:Update(1 / 30)
				run(menu, 0.2)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(2) -- the pointed mode is back on its hover frame
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(1)
			end
		},
		{
			name = "GryMod's modes map to the movie's names and back (Armor is Defense, dropping the weapon is Weapon)",
			func = function(state)
				local M = GryMod.FlashMenu
				expect(M.ModeFromName("Defense")).to.equal(GryMod.Modes.ARMOR)
				expect(M.ModeFromName("Speed")).to.equal(GryMod.Modes.SPEED)
				expect(M.ModeFromName("Cloak")).to.equal(GryMod.Modes.CLOAK)
				expect(M.ModeFromName("Strength")).to.equal(GryMod.Modes.STRENGTH)
				expect(M.ModeFromName("Weapon")).to.equal(GryMod.Modes.DROP)
				expect(M.ModeFromName("Center")).to.equal(nil)
				expect(M.NameFromMode(GryMod.Modes.ARMOR)).to.equal("Armor")
				expect(M.NameFromMode(GryMod.Modes.DROP)).to.equal("Weapon")
				expect(M.NameFromMode(nil)).to.equal(nil)
			end
		},
		{
			name = "pressing the key again while the menu is open does nothing more, and cancelling closes it without any mode change",
			func = function(state)
				local M = GryMod.FlashMenu
				local ply = LocalPlayer()
				local changes = 0
				local real = FindMetaTable("Player").SetNanosuitMode
				FindMetaTable("Player").SetNanosuitMode = function() changes = changes + 1 end

				M.Reset()
				expect(M.Begin()).to.beTrue()
				expect(M.Begin()).to.beFalse() -- already open (a bind and gry_menu_key together)
				expect(M.IsOpen()).to.beTrue()
				M.Cancel()
				expect(M.IsOpen()).to.beFalse()
				expect(changes).to.equal(0)
				M.Cancel() -- nothing to cancel: no error
				FindMetaTable("Player").SetNanosuitMode = real
				M.Reset()
			end
		},
		{
			name = "the menu must be cancelled when the player is dead or a game menu is up",
			func = function(state)
				local M = GryMod.FlashMenu
				local alive = {Alive = function() return true end}
				local dead = {Alive = function() return false end}
				expect(M.ShouldCancel(alive, false)).to.beFalse()
				expect(M.ShouldCancel(dead, false)).to.beTrue()
				expect(M.ShouldCancel(alive, true)).to.beTrue()
				expect(M.ShouldCancel(nil, false)).to.beTrue()
			end
		},
		{
			name = "a missing movie gives no menu instead of an error",
			func = function(state)
				expect(GryMod.FlashMenu.New(nil)).to.equal(nil)
			end
		}
	}
}
