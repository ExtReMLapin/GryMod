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

-- ---------------------------------------------------------------------------------------------------------
-- A mouse moving in segments of constant velocity (counts per second), seen by frames of any rate
-- ---------------------------------------------------------------------------------------------------------

local function position(segments, t)
	local x, y, start = 0, 0, 0

	for _, s in ipairs(segments) do
		local d = math.min(math.max(t - start, 0), s.time)
		x, y = x + s.vx * d, y + s.vy * d
		start = start + s.time
	end

	return x, y
end

local function duration(segments)
	local total = 0

	for _, s in ipairs(segments) do
		total = total + s.time
	end

	return total
end

local function angleDifference(a, b)
	return (a - b + 180) % 360 - 180
end

-- Every frame of `fps` hands the pointer the counts the mouse made during it. quantised: whole counts, as the sensor sends them.
-- film: the film pointer (fixed clock, eased arrow); not film: what the first port did, the rule on every frame's counts and the
-- arrow at the vector's angle. Returns the angle the arrow shows after each frame, and the selection.
local function drive(pointer, segments, fps, quantised, film)
	local out = {}
	local px, py = 0, 0

	if film then
		pointer:Feed(0, 0, 0) -- the menu opens at t = 0 on every client: the clock starts there
	end

	for i = 1, math.floor(duration(segments) * fps + 0.5) do
		local t = i / fps
		local x, y = position(segments, t)

		if quantised then
			x, y = math.floor(x), math.floor(y)
		end

		if film then
			pointer:Feed(x - px, y - py, t)
		else
			pointer:Move(x - px, y - py)
		end

		px, py = x, y
		out[i] = {t = t, theta = film and pointer:DisplayTheta() or pointer:Theta(), selection = pointer:Selection()}
	end

	return out
end

local function shownAt(out, t)
	for _, frame in ipairs(out) do
		if math.abs(frame.t - t) < 1e-6 then
			return frame.theta
		end
	end
end

-- how many times a second the arrow turns back (the "very fast oscillation") after `warm` seconds
local function reversalsPerSecond(out, warm)
	local last, count, first, final

	for i = 2, #out do
		if out[i].t >= warm then
			local d = angleDifference(out[i].theta, out[i - 1].theta)
			first = first or out[i].t
			final = out[i].t

			if math.abs(d) > 1e-9 then
				local sign = d > 0 and 1 or -1

				if last and sign ~= last then
					count = (count or 0) + 1
				end

				last = sign
			end
		end
	end

	return (count or 0) / (final - first)
end

-- a mouse at 400 counts per second towards the bottom right, 35 degrees under the horizontal
local DIAGONAL = {{time = 3, vx = 400 * math.cos(math.rad(35)), vy = 400 * math.sin(math.rad(35))}}

-- The menu must send NOTHING when it opens (the server pushes the mask by itself): net.Start and net.SendToServer are
-- replaced for the length of fn and put back after it, whatever happens inside (afterEach puts them back too). `asked` holds the names started.
local realNet
local asked

local function unspyAsk()
	if realNet then
		net.Start, net.SendToServer = realNet.start, realNet.send
		realNet = nil
	end
end

local function spyAsk(fn)
	realNet = {start = net.Start, send = net.SendToServer}
	asked = {}
	net.Start = function(name) asked[#asked + 1] = name end
	net.SendToServer = function() end

	local ok, err = pcall(fn)
	unspyAsk()

	if not ok then
		error(err, 0)
	end
end

return {
	groupName = "GryMod quick menu (Flash)",
	-- opening and closing the menu play its sounds: nothing is played by the tests (the mix's single exit is replaced)
	beforeEach = function(state)
		-- (the convars first: a failure here must not leave the sound exit replaced)
		state.savedKeep = GetConVar("gry_menu_keep_highlight"):GetString()
		GetConVar("gry_menu_keep_highlight"):SetString("1")
		state.savedRing = GetConVar("gry_menu_ring_film"):GetString()
		GetConVar("gry_menu_ring_film"):SetString("1")
		state.savedFilm = GetConVar("gry_menu_pointer_film"):GetString()
		GetConVar("gry_menu_pointer_film"):SetString("1")
		GryMod.FlashMenu.SetRefused(0) -- (the mask the server sent is kept by the menu, even through Reset: no case may inherit one)
		state.savedShow = GetConVar("gry_menu_show_refused"):GetString()
		GetConVar("gry_menu_show_refused"):SetString("1")
		state.realEmit = GryMod.SoundMix.Emit
		GryMod.SoundMix.Emit = function() end
	end,
	afterEach = function(state)
		unspyAsk()
		GryMod.FlashMenu.SetRefused(0)
		GetConVar("gry_menu_show_refused"):SetString(state.savedShow)
		GetConVar("gry_menu_pointer_film"):SetString(state.savedFilm)
		GryMod.SoundMix.Emit = state.realEmit
		GetConVar("gry_menu_keep_highlight"):SetString(state.savedKeep)
		GetConVar("gry_menu_ring_film"):SetString(state.savedRing)
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
			name = "RingAfter: the ring changes with the film's rules, an inactive or defective mode touches nothing, the centre is orange",
			func = function(state)
				local ring = GryMod.FlashMenu.RingAfter
				local active = {Speed = true, Strength = true, Cloak = true, Armor = true} -- Weapon is inactive
				local defect = {Cloak = true}
				local center = ring(nil, "Center", active, defect, 0)
				expect(center.orange).to.beTrue()
				expect(center.green).to.beFalse()
				expect(center.indicator).to.beFalse()

				-- an active mode: green with the indicator
				local speed = ring(center, "Speed", active, defect, 0)
				expect(speed.green).to.beTrue()
				expect(speed.orange).to.beFalse()
				expect(speed.indicator).to.beTrue()

				-- from an active mode to an inactive one: nothing is touched, the ring stays green (the original)
				local weapon = ring(speed, "Weapon", active, defect, 0)
				expect(weapon.green).to.beTrue()
				expect(weapon.orange).to.beFalse()
				expect(weapon.indicator).to.beTrue()

				-- from the centre to an inactive one: stays orange
				weapon = ring(center, "Weapon", active, defect, 0)
				expect(weapon.orange).to.beTrue()
				expect(weapon.green).to.beFalse()

				-- a defective mode is the same
				expect(ring(speed, "Cloak", active, defect, 0).green).to.beTrue()
				expect(ring(center, "Cloak", active, defect, 0).orange).to.beTrue()

				-- the centre always puts it back to orange
				local back = ring(speed, "Center", active, defect, 0)
				expect(back.orange).to.beTrue()
				expect(back.indicator).to.beFalse()

				-- a malfunction: no mode counts, whatever it is; Defense is the Armor icon
				expect(ring(center, "Speed", active, defect, 1).orange).to.beTrue()
				expect(ring(center, "Defense", active, defect, 0).green).to.beTrue()
				-- an unknown name touches nothing
				expect(ring(speed, "Default", active, defect, 0).green).to.beTrue()
			end
		},
		{
			name = "moving the pointer from an active mode to an inactive one leaves the ring green; back to the centre it is orange",
			func = function(state)
				local menu = openMenu({Speed = true, Strength = true, Cloak = true, Armor = true})
				local circle = menu.qm:Child("Circle")
				menu:Select("Speed")
				menu:Update(1 / 30)
				expect(circle:Child("Circle_green").visible).to.beTrue()
				menu:Select("Weapon")
				menu:Update(1 / 30)
				expect(modeClip(menu, "Weapon"):CurrentFrame()).to.equal(3) -- the icon says it is inactive
				expect(circle:Child("Circle_green").visible).to.beTrue()
				expect(circle:Child("Circle_orange").visible).to.beFalse()
				expect(circle:Child("Indicator").visible).to.beTrue()
				menu:Select("Center")
				menu:Update(1 / 30)
				expect(circle:Child("Circle_orange").visible).to.beTrue()
				expect(circle:Child("Circle_green").visible).to.beFalse()
				-- and it starts from the centre again at the next opening
				menu:Select("Speed")
				menu:Update(1 / 30)
				menu:Close()
				run(menu, 0.5)
				menu:Open()
				run(menu, 0.4)
				expect(menu.qm:Child("Circle"):Child("Circle_orange").visible).to.beTrue()
			end
		},
		{
			name = "gry_menu_ring_film 0 brings back the ring that follows the choice alone; the switch is saved, on by default, with a check box",
			func = function(state)
				local convar = GetConVar("gry_menu_ring_film")
				expect(convar:GetDefault()).to.equal("1")
				convar:SetString("0")
				local menu = openMenu({Speed = true, Strength = true, Cloak = true, Armor = true})
				local circle = menu.qm:Child("Circle")
				menu:Select("Speed")
				menu:Update(1 / 30)
				menu:Select("Weapon")
				menu:Update(1 / 30)
				expect(circle:Child("Circle_orange").visible).to.beTrue()
				expect(circle:Child("Circle_green").visible).to.beFalse()

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

				expect(found["gry_menu_ring_film"]).to.beTrue()
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
			name = "GryMod's modes map to the movie's names and back (Armor is Defense); the Weapon icon is not a mode (it opens the weapon's menu), and dropping the weapon is gone",
			func = function(state)
				local M = GryMod.FlashMenu
				expect(M.ModeFromName("Defense")).to.equal(GryMod.Modes.ARMOR)
				expect(M.ModeFromName("Speed")).to.equal(GryMod.Modes.SPEED)
				expect(M.ModeFromName("Cloak")).to.equal(GryMod.Modes.CLOAK)
				expect(M.ModeFromName("Strength")).to.equal(GryMod.Modes.STRENGTH)
				expect(M.ModeFromName("Weapon")).to.equal(nil)
				expect(GryMod.Modes.DROP).to.equal(nil)
				expect(M.ModeFromName("Center")).to.equal(nil)
				expect(M.NameFromMode(GryMod.Modes.ARMOR)).to.equal("Armor")
				expect(M.NameFromMode(4)).to.equal(nil)
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
			-- fails when releasing the key on the Weapon icon does something else than open the held weapon's menu (it used to drop the weapon), or when the icon is chosen while the
			-- weapon has no menu (the icon is inactive then: nothing may happen)
			name = "releasing the key on the Weapon icon opens the weapon's menu when the weapon has one, and does nothing (no mode change either) when it has not",
			func = function(state)
				local M = GryMod.FlashMenu
				local API = GryMod.API
				local meta = FindMetaTable("Player")
				local real = {get = API.GetWeaponMenu, open = API.OpenWeaponMenu, mode = meta.SetNanosuitMode}
				local opened, changes = 0, 0

				meta.SetNanosuitMode = function() changes = changes + 1 end
				API.OpenWeaponMenu = function() opened = opened + 1 return true end

				local ok, err = pcall(function()
					-- the weapon has a menu: the icon is active and chosen
					API.GetWeaponMenu = function() return function() end end
					M.Reset()
					expect(M.Begin()).to.beTrue()
					M.GetMenu():Select("Weapon")
					M.Finish()
					expect(opened).to.equal(1)
					expect(changes).to.equal(0)

					-- no menu: the icon is inactive, nothing opens
					API.GetWeaponMenu = function() return nil end
					M.Reset()
					expect(M.Begin()).to.beTrue()
					M.GetMenu():Select("Weapon")
					M.Finish()
					expect(opened).to.equal(1)
					expect(changes).to.equal(0)
				end)

				API.GetWeaponMenu, API.OpenWeaponMenu, meta.SetNanosuitMode = real.get, real.open, real.mode
				M.Reset()

				if not ok then
					error(err, 0)
				end
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
			name = "the menu is also cancelled while the cursor is up, the player types, the console is open, or the key it was opened with is no longer down",
			func = function(state)
				local M = GryMod.FlashMenu
				local alive = {Alive = function() return true end}
				expect(M.ShouldCancel(alive, false, {})).to.beFalse()
				expect(M.ShouldCancel(alive, false, {cursor = false, typing = false, console = false, keyUp = false})).to.beFalse()
				expect(M.ShouldCancel(alive, false, {cursor = true})).to.beTrue()
				expect(M.ShouldCancel(alive, false, {typing = true})).to.beTrue()
				expect(M.ShouldCancel(alive, false, {console = true})).to.beTrue()
				expect(M.ShouldCancel(alive, false, {keyUp = true})).to.beTrue()
			end
		},
		{
			name = "opening the chat with the key held cancels the menu: the key release never comes (StartChat)",
			func = function(state)
				local M = GryMod.FlashMenu
				M.Reset()
				expect(M.Begin()).to.beTrue()
				local handler = hook.GetTable().StartChat and hook.GetTable().StartChat["GRYQUICKMENU"]
				expect(handler).to.beA("function")
				handler()
				expect(M.IsOpen()).to.beFalse()
				M.Reset()
			end
		},
		{
			name = "the per frame check cancels an open menu when a panel has the cursor, the player types, the console is up or the key is up, and leaves it open otherwise",
			func = function(state)
				local M = GryMod.FlashMenu
				local meta = FindMetaTable("Player")
				local K = GryMod.MenuKey
				local cmd = {
					GetMouseX = function() return 0 end,
					GetMouseY = function() return 0 end,
					GetButtons = function() return 0 end,
					SetButtons = function() end,
					SetViewAngles = function() end,
					SetMouseX = function() end,
					SetMouseY = function() end
				}
				local real = {cursor = vgui.CursorVisible, typing = meta.IsTyping, console = gui.IsConsoleVisible, down = input.IsButtonDown, pressed = K.pressed}
				local fake = {cursor = false, typing = false, console = false, down = true}
				vgui.CursorVisible = function() return fake.cursor end
				meta.IsTyping = function() return fake.typing end
				gui.IsConsoleVisible = function() return fake.console end
				input.IsButtonDown = function() return fake.down end

				local ok, err = pcall(function()
					local frame = hook.GetTable().CreateMove["GRYQUICKMENU"]
					K.pressed = KEY_F7

					local function openThen(change)
						fake.cursor, fake.typing, fake.console, fake.down = false, false, false, true
						M.Reset()
						expect(M.Begin()).to.beTrue()
						K.pressed = KEY_F7
						change()
						frame(cmd)

						return M.IsOpen()
					end

					expect(openThen(function() end)).to.beTrue() -- the key is held, nothing in the way
					expect(openThen(function() fake.cursor = true end)).to.beFalse()
					expect(openThen(function() fake.typing = true end)).to.beFalse()
					expect(openThen(function() fake.console = true end)).to.beFalse()
					expect(openThen(function() fake.down = false end)).to.beFalse()

					-- opened with no known key (the console command): the key cannot be polled
					fake.cursor, fake.typing, fake.console, fake.down = false, false, false, false
					M.Reset()
					expect(M.Begin()).to.beTrue()
					K.pressed = nil
					frame(cmd)
					expect(M.IsOpen()).to.beTrue()
				end)

				vgui.CursorVisible, meta.IsTyping, gui.IsConsoleVisible, input.IsButtonDown, K.pressed = real.cursor, real.typing, real.console, real.down, real.pressed
				M.Reset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "the arrow does not flutter at a high frame rate: the previous rule turns back 60 times a second at 240 fps, the film pointer under 30, at every rate",
			func = function(state)
				local M = GryMod.FlashMenu
				-- the report: moving steadily towards the bottom right made the arrow vibrate (the rule ran on every frame of a fast client)
				expect(reversalsPerSecond(drive(M.NewPointer("Cloak"), DIAGONAL, 240, true, false), 0.6)).to.beGreaterThan(60)

				for _, fps in ipairs({30, 60, 144, 166, 240}) do
					local rate = reversalsPerSecond(drive(M.NewPointer("Cloak"), DIAGONAL, fps, true, true), 0.6)
					expect(rate < 30).to.beTrue()
				end
			end
		},
		{
			name = "the film pointer gives the same angle at the same instant whatever the frame rate; the rule on every frame does not",
			func = function(state)
				local M = GryMod.FlashMenu
				-- down right, then a turn up right at 1500 counts per second
				local turn = {
					{time = 0.5, vx = 1500 * math.cos(math.rad(35)), vy = 1500 * math.sin(math.rad(35))},
					{time = 0.5, vx = 1500 * math.cos(math.rad(35)), vy = -1500 * math.sin(math.rad(35))}
				}
				local reference = drive(M.NewPointer("Cloak"), turn, 240, false, true)

				for _, fps in ipairs({30, 60, 120}) do
					local out = drive(M.NewPointer("Cloak"), turn, fps, false, true)

					for _, t in ipairs({0.5, 16 / 30, 0.6, 0.7, 0.9}) do
						expect(math.abs(angleDifference(shownAt(out, t), shownAt(reference, t))) < 0.05).to.beTrue()
					end
				end

				-- the previous rule: 33 ms after the turn the arrow of a 30 fps client is already round, the one of a 240 fps client is not
				local slow = shownAt(drive(M.NewPointer("Cloak"), turn, 30, false, false), 16 / 30)
				local fast = shownAt(drive(M.NewPointer("Cloak"), turn, 240, false, false), 16 / 30)
				expect(math.abs(angleDifference(slow, fast)) > 5).to.beTrue()
			end
		},
		{
			name = "the film pointer: the counts of a frame wait for the next step of the clock, whatever the frame is",
			func = function(state)
				local M = GryMod.FlashMenu
				local pointer = M.NewPointer()
				pointer:Feed(0, 0, 10)
				pointer:Feed(40, 0, 10) -- the same instant: nothing can have moved yet
				expect(pointer:Selection()).to.equal("Center")
				pointer:Feed(0, 0, 10 + M.POINTER_STEP / 2) -- half a step later: still waiting
				expect(pointer:Selection()).to.equal("Center")
				pointer:Feed(0, 0, 10 + M.POINTER_STEP * 1.01)
				expect(pointer:Selection()).to.equal("Strength") -- the step has come
				expect(near(math.sqrt(pointer.x * pointer.x + pointer.y * pointer.y), 25)).to.beTrue()

				-- a stall (the game was frozen for a second): the clock moves by 0.1 s at most, the counts are still used
				local stalled = M.NewPointer()
				stalled:Feed(0, 0, 5)
				stalled:Feed(60, 0, 6)
				expect(stalled:Selection()).to.equal("Strength")
				expect(stalled.clock).to.equal(6)
			end
		},
		{
			name = "the film pointer keeps the game's rule: a small movement stays at the centre, a flick selects, coming back under 12.5 returns to the centre",
			func = function(state)
				local M = GryMod.FlashMenu
				local pointer = M.NewPointer()
				local t = 0
				pointer:Feed(0, 0, t)

				-- one step of the clock per move: the whole movement is applied at once
				local function move(dx, dy)
					t = t + M.POINTER_STEP
					pointer:Feed(dx, dy, t)
				end

				move(8, 0)
				expect(pointer:Selection()).to.equal("Center")
				move(40, 0)
				expect(pointer:Selection()).to.equal("Strength")
				move(-10, 0) -- between the two thresholds: nothing changes
				expect(pointer:Selection()).to.equal("Strength")
				move(-8, 0) -- back under 12.5: the centre, the accumulator reset
				expect(pointer:Selection()).to.equal("Center")
				expect(pointer.x).to.equal(0)
				expect(pointer.y).to.equal(0)
				move(0, -40) -- a flick up
				expect(pointer:Selection()).to.equal("Speed")
				move(-40, 0) -- a flick left: from the clamp (0, -25) the sum is (-40, -25), angle 148 degrees
				expect(pointer:Selection()).to.equal("Defense")
			end
		},
		{
			name = "going towards the bottom right and keeping going selects the cloak, the arrow settles on 315 degrees",
			func = function(state)
				local M = GryMod.FlashMenu
				local down = {{time = 1, vx = 800, vy = 800}}

				for _, fps in ipairs({30, 166}) do
					local pointer = M.NewPointer("Speed")
					local out = drive(pointer, down, fps, true, true)
					expect(pointer:Selection()).to.equal("Cloak")
					expect(math.abs(angleDifference(out[#out].theta, 315)) < 3).to.beTrue()
				end
			end
		},
		{
			name = "the arrow turns by the short way across the right (0 degrees) and never jumps",
			func = function(state)
				local M = GryMod.FlashMenu
				-- starts on Strength, a hair under the horizontal axis, then the mouse goes up right
				local pointer = M.NewPointer("Strength")
				pointer.x, pointer.y = 24.6, 4.3
				pointer.shown = pointer:Theta()
				local out = drive(pointer, {{time = 0.5, vx = 1000, vy = -1000}}, 240, false, true)
				local previous = 350.1

				for _, frame in ipairs(out) do
					expect(math.abs(angleDifference(frame.theta, previous)) < 15).to.beTrue()
					previous = frame.theta
				end

				expect(math.abs(angleDifference(out[#out].theta, 45)) < 2).to.beTrue()
			end
		},
		{
			name = "the arrow starts on the angle of the current mode and stays there while the mouse is still",
			func = function(state)
				local M = GryMod.FlashMenu
				local pointer = M.NewPointer("Speed")
				expect(near(pointer:DisplayTheta(), 90)).to.beTrue()
				local out = drive(pointer, {{time = 0.5, vx = 0, vy = 0}}, 166, true, true)

				for _, frame in ipairs(out) do
					expect(near(frame.theta, 90)).to.beTrue()
				end
			end
		},
		{
			name = "the convar picks the rule: on, a flick waits for the clock's step; off, it counts at once as before",
			func = function(state)
				local M = GryMod.FlashMenu
				local meta = FindMetaTable("Player")
				local K = GryMod.MenuKey
				local cmd = {
					x = 40,
					GetMouseX = function(self) return self.x end,
					GetMouseY = function() return 0 end,
					GetButtons = function() return 0 end,
					SetButtons = function() end,
					SetViewAngles = function() end,
					SetMouseX = function() end,
					SetMouseY = function() end
				}
				local real = {cursor = vgui.CursorVisible, typing = meta.IsTyping, console = gui.IsConsoleVisible, down = input.IsButtonDown, pressed = K.pressed, time = RealTime}
				local now = 100
				vgui.CursorVisible = function() return false end
				meta.IsTyping = function() return false end
				gui.IsConsoleVisible = function() return false end
				input.IsButtonDown = function() return true end
				RealTime = function() return now end

				local ok, err = pcall(function()
					local frame = hook.GetTable().CreateMove["GRYQUICKMENU"]

					local function flick(film)
						GetConVar("gry_menu_pointer_film"):SetString(film)
						M.Reset()
						expect(M.Begin()).to.beTrue()
						K.pressed = KEY_F7
						local pointer = M.GetPointer()
						pointer.x, pointer.y, pointer.active = 0, 0, false
						cmd.x = 40
						now = now + 1
						frame(cmd)
						local immediately = pointer:Selection()
						cmd.x = 0
						now = now + M.POINTER_STEP * 1.5
						frame(cmd)

						return immediately, pointer:Selection()
					end

					local immediately, later = flick("1")
					expect(immediately).to.equal("Center")
					expect(later).to.equal("Strength")
					immediately, later = flick("0")
					expect(immediately).to.equal("Strength")
					expect(later).to.equal("Strength")
				end)

				vgui.CursorVisible, meta.IsTyping, gui.IsConsoleVisible, input.IsButtonDown, K.pressed, RealTime = real.cursor, real.typing, real.console, real.down, real.pressed, real.time
				M.Reset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			name = "gry_menu_pointer_film is saved, on by default, with a check box",
			func = function(state)
				local cvar = GetConVar("gry_menu_pointer_film")
				expect(cvar ~= nil).to.beTrue()
				expect(cvar:GetDefault()).to.equal("1")
				-- (GetFlags does not report FCVAR_ARCHIVE for Lua-created convars in this build: same flags as a saved sibling)
				expect(cvar:GetFlags()).to.equal(GetConVar("gry_menu_ring_film"):GetFlags())

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

				expect(found["gry_menu_pointer_film"]).to.beTrue()
			end
		},
		{
			-- fails without Menu.FillStates (cl_hud_quickmenu_flash.lua)
			name = "FillStates: a refused mode is inactive, the armor never is, a suit that is off keeps only the armor and the weapon, and the tables are reused in place",
			func = function(state)
				local M = GryMod.FlashMenu
				local active, defect = {}, {}
				local Modes = GryMod.Modes

				M.FillStates(active, defect, {weapon = true})
				expect(active.Speed and active.Strength and active.Cloak and active.Armor and active.Weapon).to.beTrue()
				expect(next(defect)).to.beNil()

				M.FillStates(active, defect, {weapon = false, refused = {[Modes.SPEED] = true, [Modes.STRENGTH] = true}})
				expect(active.Speed).to.beFalse()
				expect(active.Strength).to.beFalse()
				expect(active.Cloak).to.beTrue()
				expect(active.Armor).to.beTrue()
				expect(active.Weapon).to.beFalse()

				-- the armor is the suit's safe state: a veto never reaches it
				M.FillStates(active, defect, {weapon = true, refused = {[Modes.ARMOR] = true, [4] = true}})
				expect(active.Armor).to.beTrue()
				expect(active.Weapon).to.beTrue()

				-- the same tables: nothing of the previous call stays (a mode that is no longer refused is active again)
				M.FillStates(active, defect, {weapon = true, refused = {}})
				expect(active.Speed).to.beTrue()
				expect(active.Strength).to.beTrue()

				M.FillStates(active, defect, {weapon = true, off = true})
				expect(active.Speed).to.beFalse()
				expect(active.Cloak).to.beFalse()
				expect(active.Strength).to.beFalse()
				expect(active.Armor).to.beTrue()
				expect(active.Weapon).to.beTrue()
			end
		},
		{
			-- fails without the defect part of FillStates
			name = "FillStates: while the suit is down every icon is defective, and no longer once it is back",
			func = function(state)
				local M = GryMod.FlashMenu
				local active, defect = {}, {}
				M.FillStates(active, defect, {weapon = true, down = true})

				for _, name in ipairs({"Speed", "Strength", "Cloak", "Armor", "Weapon"}) do
					expect(defect[name]).to.beTrue()
				end

				M.FillStates(active, defect, {weapon = true, down = false})
				expect(next(defect)).to.beNil()
			end
		},
		{
			-- fails if the inactive frame is not shown for a refused mode, or if a refused mode can still be chosen
			name = "the movie shows a refused mode on its inactive frame (3), it cannot be chosen, and the other icons are normal",
			func = function(state)
				local M = GryMod.FlashMenu
				local active, defect = M.FillStates({}, {}, {weapon = true, refused = {[GryMod.Modes.SPEED] = true}})
				local menu = openMenu(active, defect)
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(3)
				expect(modeClip(menu, "Cloak"):CurrentFrame()).to.equal(1)

				menu:Select("Speed")
				menu:Update(1 / 30)
				expect(menu:Choice()).to.beNil()
				expect(modeClip(menu, "Speed"):CurrentFrame()).to.equal(3) -- pointed at, still not lit
			end
		},
		{
			-- fails if a defective mode (the suit is down) is shown on any frame but 4, with the HUD status still at 0
			name = "the movie shows every icon on its defective frame (4) when the suit is down, even when the HUD status has not told the menu",
			func = function(state)
				local M = GryMod.FlashMenu
				local active, defect = M.FillStates({}, {}, {weapon = true, down = true})
				local menu = openMenu(active, defect)
				expect(menu.malfunction).to.equal(0)

				for _, name in ipairs({"Speed", "Strength", "Cloak", "Armor", "Weapon"}) do
					expect(modeClip(menu, name):CurrentFrame()).to.equal(4)
				end
			end
		},
		{
			-- fails without Menu.SetRefused / IsRefused, or if Reset forgets the mask (the server sends it again only when it changes)
			name = "what the server says is kept as a table keyed by mode, and Reset (a new theme, a respawn) keeps it",
			func = function(state)
				local M = GryMod.FlashMenu
				local Modes = GryMod.Modes
				M.SetRefused(GryMod.ModeStates.Pack({[Modes.CLOAK] = true}))
				expect(M.IsRefused(Modes.CLOAK)).to.beTrue()
				expect(M.IsRefused(Modes.SPEED)).to.beFalse()
				M.Reset()
				expect(M.IsRefused(Modes.CLOAK)).to.beTrue()
				M.SetRefused(0)
				expect(M.IsRefused(Modes.CLOAK)).to.beFalse()
			end
		},
		{
			-- fails if feedStates does not read the answer of the server, or reads it with the switch off
			name = "an open menu shows the modes the server refuses; with gry_menu_show_refused 0 it does not, as before",
			func = function(state)
				local M = GryMod.FlashMenu
				local Modes = GryMod.Modes

				spyAsk(function()
					M.Reset()
					M.SetRefused(GryMod.ModeStates.Pack({[Modes.CLOAK] = true}))
					expect(M.Begin()).to.beTrue()
					local menu = M.GetMenu()
					expect(menu.active.Cloak).to.beFalse()
					expect(menu.active.Speed).to.beTrue()
					M.Cancel()

					GetConVar("gry_menu_show_refused"):SetString("0")
					M.Reset()
					M.SetRefused(GryMod.ModeStates.Pack({[Modes.CLOAK] = true}))
					expect(M.Begin()).to.beTrue()
					expect(M.GetMenu().active.Cloak).to.beTrue()
					M.Cancel()
					M.Reset()
				end)
			end
		},
		{
			-- fails if feedStates does not read the networked flags of the player
			name = "an open menu shows every icon defective while the suit is down (GryMalfunction) and the three modes inactive while it is off (GryDisabled)",
			func = function(state)
				local M = GryMod.FlashMenu
				local realFlags = M.SuitFlags
				local flags = {}
				M.SuitFlags = function() return flags.GryMalfunction == true, flags.GryDisabled == true end

				local ok, err = pcall(function()
					spyAsk(function()
						flags.GryMalfunction = true
						M.Reset()
						expect(M.Begin()).to.beTrue()
						expect(M.GetMenu().defect.Cloak).to.beTrue()
						expect(M.GetMenu().defect.Armor).to.beTrue()
						M.Cancel()

						flags.GryMalfunction, flags.GryDisabled = false, true
						M.Reset()
						expect(M.Begin()).to.beTrue()
						expect(M.GetMenu().active.Speed).to.beFalse()
						expect(M.GetMenu().active.Armor).to.beTrue()
						expect(M.GetMenu().defect.Cloak).to.beNil()
						M.Cancel()

						-- the switch off: the menu is what it was before these states
						GetConVar("gry_menu_show_refused"):SetString("0")
						flags.GryMalfunction = true
						M.Reset()
						expect(M.Begin()).to.beTrue()
						expect(M.GetMenu().active.Speed).to.beTrue()
						expect(M.GetMenu().defect.Cloak).to.beNil()
						M.Cancel()
						M.Reset()
					end)
				end)

				M.SuitFlags = realFlags
				M.Reset()

				if not ok then
					error(err, 0)
				end
			end
		},
		{
			-- fails if the menu sends anything to the server again (a question on opening slows the menu and fills the network)
			name = "the menu never asks the server: opening it, with or without gry_menu_show_refused, and the hooks of a mode change or a malfunction send nothing",
			func = function(state)
				local M = GryMod.FlashMenu
				local ply = LocalPlayer()
				expect(M.Ask).to.beNil()

				spyAsk(function()
					M.Reset()
					expect(M.Begin()).to.beTrue()
					expect(#asked).to.equal(0)
					M.Cancel()

					GetConVar("gry_menu_show_refused"):SetString("0")
					M.Reset()
					expect(M.Begin()).to.beTrue()
					expect(#asked).to.equal(0)
					M.Cancel()
					M.Reset()

					-- (the listeners that asked again are gone)
					for _, event in ipairs({"GryMod_ModeChanged", "GryMod_MalfunctionStart", "GryMod_MalfunctionEnd"}) do
						expect(hook.GetTable()[event] and hook.GetTable()[event]["GRYQUICKMENUREFUSED"]).to.beNil()
					end

					expect(#asked).to.equal(0)
				end)
			end
		},
		{
			-- fails if the menu opens without the mask it already holds (it would be empty until an answer came)
			name = "a menu opened with a mask received before shows it at once, with nothing sent",
			func = function(state)
				local M = GryMod.FlashMenu
				local Modes = GryMod.Modes

				spyAsk(function()
					M.Reset()
					M.SetRefused(GryMod.ModeStates.Pack({[Modes.STRENGTH] = true}))
					expect(M.Begin()).to.beTrue()
					expect(M.GetMenu().active.Strength).to.beFalse()
					expect(#asked).to.equal(0)

					-- a new mask received while it is open is read on the next frame
					M.SetRefused(0)
					expect(M.IsRefused(Modes.STRENGTH)).to.beFalse()
					M.Cancel()
					M.Reset()
				end)
			end
		},
		{
			-- fails without the net.Receive of gry_modes_refused
			name = "the server's answer gry_modes_refused is received and kept",
			func = function(state)
				local M = GryMod.FlashMenu
				local receiver = net.Receivers["gry_modes_refused"]
				expect(receiver).to.beA("function")

				local realRead = net.ReadUInt
				net.ReadUInt = function(bits)
					expect(bits).to.equal(GryMod.ModeStates.Bits)

					return GryMod.ModeStates.Pack({[GryMod.Modes.STRENGTH] = true})
				end

				local ok, err = pcall(receiver, 0)
				net.ReadUInt = realRead

				if not ok then
					error(err, 0)
				end

				expect(M.IsRefused(GryMod.Modes.STRENGTH)).to.beTrue()
				expect(M.IsRefused(GryMod.Modes.SPEED)).to.beFalse()
				M.Reset()
			end
		},
		{
			name = "gry_menu_show_refused is saved, on by default, with a check box",
			func = function(state)
				local cvar = GetConVar("gry_menu_show_refused")
				expect(cvar ~= nil).to.beTrue()
				expect(cvar:GetDefault()).to.equal("1")
				expect(cvar:GetFlags()).to.equal(GetConVar("gry_menu_ring_film"):GetFlags())

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

				expect(found["gry_menu_show_refused"]).to.beTrue()
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
