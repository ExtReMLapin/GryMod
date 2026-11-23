-- Tests of the weapon list drawn from the original Scaleform movie (GryMod.FlashWeaponList, lua/grymod/client/cl_hud_weaponlist_flash.lua), GLuaTest
-- format, client realm. Needs the converted movie lua/grymod/flash/hud_weaponselection.lua and the registry field listIcon. The list shows up to
-- five weapons of the player at each weapon change, the current one on a plate, and fades after 3 seconds (the movie's own m_time); the stock Half-Life 2
-- selector is never touched. The live game is replaced where a case needs it and put back in afterEach inside a pcall: the HUD state, the drawing,
-- the clock, the settings, the registry entries and the hooks the cases add.

local List = GryMod.FlashWeaponList
local API = GryMod.API
local Flash = GryMod.Flash

local saved = {}
local convarsSaved = {}
local drawn
local clock
local textCalls
local CLASSES = {"t_list_a", "t_list_b", "t_list_c", "t_list_d", "t_list_e", "t_list_f", "t_list_g"}

local function stub(tbl, key, value)
	saved[#saved + 1] = {tbl, key, tbl[key]}
	tbl[key] = value
end

local function setConVar(name, value)
	local convar = GetConVar(name)

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
end

-- seconds of play, a frame at a time, through the paint function (the clock it reads is the stub)
local function run(seconds)
	for _ = 1, math.ceil(seconds * 30) do
		clock = clock + 1 / 30
		List.Paint()
	end
end

local function fakeWeapon(class, slot, slotPos, print)
	return {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetSlot = function() return slot end,
		GetSlotPos = function() return slotPos end,
		GetPrintName = function() return print or class end
	}
end

local function fakePlayer(list)
	return {
		IsValid = function() return true end,
		GetWeapons = function() return list end
	}
end

-- what the movie holds for the row `index` (0 = the bottom one): visible, the frame of its icon, whether the plate shows, whether the icon shows
local function row(index)
	local clip = List.Row(index)

	return clip.visible, clip:Find("Content.KillIcon.Colorset"):CurrentFrame(), clip:Find("Content.Frame").visible, clip:Find("Content.KillIcon").visible
end

local function rawHook(name, id)
	local tbl = hook.GetTable()[name]

	return tbl and tbl[id]
end

return {
	groupName = "GryMod weapon list (HUD_WeaponSelection)",
	beforeEach = function()
		List.SetStatus(0)
		List.Reset()
		drawn, clock, textCalls = 0, 100, 0

		stub(GryMod.FlashHUD, "Enabled", function() return true end)
		stub(Flash, "Draw", function() drawn = drawn + 1 return true end)
		stub(List, "DrawTexts", function() textCalls = textCalls + 1 end)
		stub(_G, "RealTime", function() return clock end)
		setConVar("gry_hud_weaponlist", "1")
	end,
	afterEach = function()
		pcall(List.SetStatus, 0)
		pcall(List.Reset)
		pcall(hook.Remove, "GryMod_WeaponListShown", "t_weaponlist")
		pcall(function()
			for _, class in ipairs(CLASSES) do
				API.UnregisterWeapon(class)
			end
		end)
		pcall(restore)
	end,
	cases = {
		{
			-- fails without Module.IconFor (the resolution of the silhouette from the registry)
			name = "the silhouette of a weapon is its registry listIcon, else the kind of its hand grenade, else none (a text row, never the forbidden sign)",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SCAR"})
				API.RegisterWeapon("t_list_b", {grenade = "flashbang"})
				API.RegisterWeapon("t_list_c", {grenade = "smokegrenade", listIcon = "C4"})
				API.RegisterWeapon("t_list_d", {fire = "auto"})

				expect(List.IconFor(fakeWeapon("t_list_a", 1, 1))).to.equal("SCAR")
				expect(List.IconFor(fakeWeapon("t_list_b", 1, 1))).to.equal("Grenade_Flashbang")
				expect(List.IconFor(fakeWeapon("t_list_c", 1, 1))).to.equal("C4") -- the weapon's own choice wins
				expect(List.IconFor(fakeWeapon("t_list_d", 1, 1))).to.beNil()
				expect(List.IconFor(fakeWeapon("t_list_e", 1, 1))).to.beNil()
				expect(List.IconFor(nil)).to.beNil()

				for kind, label in pairs({explosivegrenade = "Grenade_Explosive", flashbang = "Grenade_Flashbang", smokegrenade = "Grenade_Smoke", empgrenade = "Grenade_EMP"}) do
					expect(List.GrenadeIcon[kind]).to.equal(label)
					expect(API.WeaponListIcons[label]).to.beTrue()
				end

				-- the stock weapons: data of the registry, nothing in this file
				expect(List.IconFor(fakeWeapon("weapon_ar2", 2, 1))).to.equal("SCAR")
				expect(List.IconFor(fakeWeapon("weapon_physcannon", 0, 1))).to.beNil()
			end
		},
		{
			-- fails without Module.Entries (the order and the window of the list)
			name = "the list is the player's weapons by slot then place in the slot, the lowest slot on top; the current one is marked; more than five give a window around it",
			func = function()
				local a, b, c = fakeWeapon("t_list_a", 2, 0), fakeWeapon("t_list_b", 0, 3), fakeWeapon("t_list_c", 0, 1)
				local entries = List.Entries({a, b, c}, a, 5)

				expect(#entries).to.equal(3)
				expect(entries[1].weapon).to.equal(c)
				expect(entries[2].weapon).to.equal(b)
				expect(entries[3].weapon).to.equal(a)
				expect(entries[1].current).to.beFalse()
				expect(entries[3].current).to.beTrue()

				-- the same slot and place: the class name decides, so the order does not change from one call to the next
				local x, y = fakeWeapon("t_list_g", 1, 1), fakeWeapon("t_list_f", 1, 1)
				expect(List.Entries({x, y}, x, 5)[1].weapon).to.equal(y)

				-- seven weapons, five rows: the window follows the current weapon and stays inside the list
				local seven = {}

				for i = 1, 7 do
					seven[i] = fakeWeapon("w" .. i, i, 0)
				end

				local function classes(entries5)
					local out = {}

					for i, entry in ipairs(entries5) do
						out[i] = entry.weapon:GetClass()
					end

					return table.concat(out, ",")
				end

				expect(classes(List.Entries(seven, seven[1], 5))).to.equal("w1,w2,w3,w4,w5")
				expect(classes(List.Entries(seven, seven[4], 5))).to.equal("w2,w3,w4,w5,w6")
				expect(classes(List.Entries(seven, seven[7], 5))).to.equal("w3,w4,w5,w6,w7")
				-- a current weapon that is not in the list: the top of the list, nothing marked
				local none = List.Entries(seven, fakeWeapon("other", 9, 9), 5)
				expect(classes(none)).to.equal("w1,w2,w3,w4,w5")
				expect(none[1].current).to.beFalse()

				expect(#List.Entries({}, a, 5)).to.equal(0)
			end
		},
		{
			-- fails without the name of the text row
			name = "the name of a row is in capitals, 18 characters at most, without line breaks",
			func = function()
				expect(List.Label("gravity gun")).to.equal("GRAVITY GUN")
				expect(List.Label("a\nb")).to.equal("A B")
				expect(#List.Label(string.rep("x", 60))).to.equal(18)
				expect(List.Label(nil)).to.equal("")
			end
		},
		{
			-- fails without Module.RowFor (the rows of the movie are numbered from the bottom: Log0 is the lowest)
			name = "the rows fill the movie from the bottom: the last entry of the list is Log0, the first one is the highest row used",
			func = function()
				expect(List.RowFor(1, 3)).to.equal(2)
				expect(List.RowFor(3, 3)).to.equal(0)
				expect(List.RowFor(1, 5)).to.equal(4)
				expect(List.RowFor(5, 5)).to.equal(0)
				expect(List.RowFor(1, 1)).to.equal(0)
			end
		},
		{
			-- fails without Module.Phase (the 3 seconds of the movie's m_time, then its 16 frames of fade)
			name = "a list is held 3 seconds, fades for 16 frames, then it is over",
			func = function()
				expect(List.Phase(0)).to.equal("hold")
				expect(List.Phase(2.99)).to.equal("hold")
				expect(List.Phase(3)).to.equal("fade")
				expect(List.Phase(3 + 0.3)).to.equal("fade")
				expect(List.Phase(3 + 16 / 30 + 0.2)).to.equal("done")
				expect(List.Phase(-1)).to.equal("hold") -- a clock that went back
				expect(List.Phase(0 / 0)).to.equal("hold")
			end
		},
		{
			-- fails without Module.FadeAlpha (the alpha of a row follows the movie's frames: 1 while active, 0.933 ... 0 on frames 3 to 17)
			name = "the alpha of a row's text follows the frames of the movie's fade",
			func = function()
				expect(List.FadeAlpha(1)).to.equal(1)
				expect(List.FadeAlpha(2)).to.equal(1)
				expect(math.abs(List.FadeAlpha(3) - 14 / 15) < 1e-9).to.beTrue()
				expect(List.FadeAlpha(17)).to.equal(0)
				expect(List.FadeAlpha(40)).to.equal(0)
			end
		},
		{
			-- fails without Module.Placement
			name = "the stage sits against the right edge of the screen and is as high as the screen",
			func = function()
				local x, y, scale = List.Placement(1920, 1080)
				expect(scale).to.equal(1080 / 768)
				expect(math.abs(x - (1920 - 1024 * scale)) < 1e-9).to.beTrue()
				expect(y).to.equal(0)

				x, y, scale = List.Placement(1024, 768)
				expect(x).to.equal(0)
				expect(scale).to.equal(1)
			end
		},
		{
			-- fails without the option gry_hud_weaponlist (a HUD element) and without the guard in Show
			name = "with the option off nothing is made, drawn or reported, and no paint hook is added",
			func = function()
				setConVar("gry_hud_weaponlist", "0")

				local called = 0
				hook.Add("GryMod_WeaponListShown", "t_weaponlist", function() called = called + 1 end)

				local a = fakeWeapon("t_list_a", 1, 1)
				local ok, why = List.Show(fakePlayer({a}), a)

				expect(ok).to.beFalse()
				expect(why).to.equal("off")
				expect(List.Active()).to.beFalse()
				expect(rawHook("HUDPaint", "GRYFLASHWEAPONLIST")).to.beNil()
				expect(called).to.equal(0)
				expect(List.Count()).to.equal(0)
			end
		},
		{
			-- fails if the list were shown while the HUD is off
			name = "with the HUD off (gry_hud, or the suit off) nothing is shown",
			func = function()
				stub(GryMod.FlashHUD, "Enabled", function() return false end)

				local a = fakeWeapon("t_list_a", 1, 1)
				expect((List.Show(fakePlayer({a}), a))).to.beFalse()
				expect(List.Active()).to.beFalse()
			end
		},
		{
			-- fails without the drive of the movie (rows, icons, plate)
			name = "a weapon change writes the rows: bottom anchored, one silhouette each, the plate on the current one only, the unused rows hidden",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})
				API.RegisterWeapon("t_list_b", {listIcon = "SCAR"})
				API.RegisterWeapon("t_list_c", {listIcon = "Fists"})

				local a, b, c = fakeWeapon("t_list_a", 1, 0), fakeWeapon("t_list_b", 2, 0), fakeWeapon("t_list_c", 0, 0)
				expect(List.Show(fakePlayer({a, b, c}), b)).to.beTrue()

				local FRAME = {SMG = 3, SCAR = 5, Fists = 26} -- the labels of the icon clip of the movie
				-- the list by slot: c (0) on top, a (1), b (2) at the bottom
				local visible, icon, plate, iconShown = row(0)
				expect(visible).to.beTrue()
				expect(icon).to.equal(FRAME.SCAR)
				expect(plate).to.beTrue() -- b is the current weapon
				expect(iconShown).to.beTrue()

				visible, icon, plate = row(1)
				expect(visible).to.beTrue()
				expect(icon).to.equal(FRAME.SMG)
				expect(plate).to.beFalse()

				visible, icon, plate = row(2)
				expect(visible).to.beTrue()
				expect(icon).to.equal(FRAME.Fists)
				expect(plate).to.beFalse()

				expect((row(3))).to.beFalse()
				expect((row(4))).to.beFalse()
				expect(List.Active()).to.beTrue()
				expect(rawHook("HUDPaint", "GRYFLASHWEAPONLIST")).to.exist()
			end
		},
		{
			-- fails if a weapon with no silhouette got the movie's forbidden sign (frame 1, "emtpy") instead of a text row
			name = "a weapon with no silhouette is a text row: its picture is hidden (never the forbidden sign), its name is drawn by the module",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a, b = fakeWeapon("t_list_a", 1, 0), fakeWeapon("t_list_b", 2, 0, "gravity gun")
				expect(List.Show(fakePlayer({a, b}), b)).to.beTrue()

				local _, _, plate, iconShown = row(0)
				expect(plate).to.beTrue()
				expect(iconShown).to.beFalse()

				_, _, _, iconShown = row(1)
				expect(iconShown).to.beTrue()

				local texts = List.Texts()
				expect(#texts).to.equal(1)
				expect(texts[1].row).to.equal(0)
				expect(texts[1].text).to.equal("GRAVITY GUN")

				run(0.1)
				expect(textCalls > 0).to.beTrue() -- the texts are drawn with the movie, once per paint
			end
		},
		{
			-- fails if a row that showed a text kept its picture hidden when it later shows a silhouette
			name = "the same row shows a silhouette again after a text row (the picture is set explicitly at each change)",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a, b = fakeWeapon("t_list_a", 1, 0), fakeWeapon("t_list_b", 2, 0)
				List.Show(fakePlayer({b}), b)
				expect(select(4, row(0))).to.beFalse()

				List.Show(fakePlayer({a}), a)
				local _, icon, _, iconShown = row(0)
				expect(iconShown).to.beTrue()
				expect(icon).to.equal(3)
				expect(#List.Texts()).to.equal(0)
			end
		},
		{
			-- fails without the hold and the fade
			name = "after 3 seconds the rows fade, then the list ends: nothing is drawn, the paint hook is gone",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a = fakeWeapon("t_list_a", 1, 0)
				List.Show(fakePlayer({a}), a)

				run(2.5)
				expect(List.Row(0):CurrentFrame()).to.equal(1)
				expect(List.Active()).to.beTrue()
				expect(drawn > 0).to.beTrue()

				run(1) -- 3.5 s: the fade has begun
				expect(List.Row(0):CurrentFrame() > 2).to.beTrue()

				run(1)
				expect(List.Active()).to.beFalse()
				expect(rawHook("HUDPaint", "GRYFLASHWEAPONLIST")).to.beNil()

				local before = drawn
				List.Paint()
				expect(drawn).to.equal(before)
			end
		},
		{
			-- fails if a second change did not start the 3 seconds again and bring the faded rows back
			name = "a new weapon change while the list fades brings the rows back and starts the 3 seconds again",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})
				API.RegisterWeapon("t_list_b", {listIcon = "SCAR"})

				local a, b = fakeWeapon("t_list_a", 1, 0), fakeWeapon("t_list_b", 2, 0)
				local ply = fakePlayer({a, b})
				List.Show(ply, a)
				run(3.3)
				expect(List.Row(0):CurrentFrame() > 2).to.beTrue()

				List.Show(ply, b)
				expect(List.Row(0):CurrentFrame()).to.equal(1)
				expect(select(2, row(0))).to.equal(5)

				run(2.5)
				expect(List.Row(0):CurrentFrame()).to.equal(1)
				run(1)
				expect(List.Row(0):CurrentFrame() > 2).to.beTrue()
			end
		},
		{
			-- fails if the list stayed on when the HUD went off
			name = "the list stops when the HUD goes off while it is shown",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a = fakeWeapon("t_list_a", 1, 0)
				List.Show(fakePlayer({a}), a)
				run(0.5)

				stub(GryMod.FlashHUD, "Enabled", function() return false end)
				List.Paint()
				expect(List.Active()).to.beFalse()
				expect(rawHook("HUDPaint", "GRYFLASHWEAPONLIST")).to.beNil()
			end
		},
		{
			-- fails without the hook GryMod_WeaponListShown
			name = "the hook GryMod_WeaponListShown(ply, weapon) is run once per list shown; a listener that errors does not stop the list",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a = fakeWeapon("t_list_a", 1, 0)
				local ply = fakePlayer({a})
				local seen = {}

				hook.Add("GryMod_WeaponListShown", "t_weaponlist", function(p, w)
					seen[#seen + 1] = {p, w}
					error("a broken listener")
				end)

				expect(List.Show(ply, a)).to.beTrue()
				expect(#seen).to.equal(1)
				expect(seen[1][1]).to.equal(ply)
				expect(seen[1][2]).to.equal(a)
				expect(List.Active()).to.beTrue()
			end
		},
		{
			-- fails without Module.OnWeaponChanged (the entry the HUD's own feed calls)
			name = "the HUD's feed reports a weapon change: a first sight (no previous weapon) or an invalid weapon shows nothing, a real change shows the list",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})
				API.RegisterWeapon("t_list_b", {listIcon = "SCAR"})

				local a, b = fakeWeapon("t_list_a", 1, 0), fakeWeapon("t_list_b", 2, 0)
				local ply = fakePlayer({a, b})

				expect(List.OnWeaponChanged(ply, a, nil)).to.beFalse() -- the HUD was just made: the weapon did not change
				expect(List.Active()).to.beFalse()

				expect(List.OnWeaponChanged(ply, nil, a)).to.beFalse()
				expect(List.OnWeaponChanged(ply, {IsValid = function() return false end}, a)).to.beFalse()
				expect(List.Active()).to.beFalse()

				expect(List.OnWeaponChanged(ply, b, a)).to.beTrue()
				expect(List.Active()).to.beTrue()
			end
		},
		{
			-- fails if the module touched the stock selector or the weapon switching input
			name = "the module never hides the stock selector and never takes a bind",
			func = function()
				expect(rawHook("HUDShouldDraw", "GRYFLASHWEAPONLIST")).to.beNil()
				expect(rawHook("PlayerBindPress", "GRYFLASHWEAPONLIST")).to.beNil()

				-- no permanent paint hook either: it exists only while a list is shown
				expect(rawHook("HUDPaint", "GRYFLASHWEAPONLIST")).to.beNil()
				expect(rawHook("Think", "GRYFLASHWEAPONLIST")).to.beNil()
				expect(rawHook("Tick", "GRYFLASHWEAPONLIST")).to.beNil()
			end
		},
		{
			-- fails without the Destroy of the movie (red rows while the HUD is down) and without the listener of GryMod_HUDStatus
			name = "the HUD's state reaches the movie: malfunction turns the rows red, flickering hides them, 0 puts them back; the list ends with the change",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a = fakeWeapon("t_list_a", 1, 0)
				List.Show(fakePlayer({a}), a)

				-- the listener the HUD's report (hook GryMod_HUDStatus) reaches; called by hand: the other pieces listen to the hook too
				local listener = rawHook("GryMod_HUDStatus", "GRYWEAPONLIST")
				expect(listener).to.exist()

				listener(1)
				expect(List.Status()).to.equal(1)
				expect(List.Root():Child("Root"):CurrentLabel()).to.equal("malfunction")
				expect(List.Active()).to.beFalse()

				-- a list shown while the HUD is down is red: the movie's own frame
				List.Show(fakePlayer({a}), a)
				expect(List.Root():Child("Root"):CurrentLabel()).to.equal("malfunction")
				expect(List.Row(0).visible).to.beTrue()

				listener(2)
				expect(List.Root():Child("Root"):CurrentLabel()).to.equal("flickering")

				listener(0)
				expect(List.Root():Child("Root"):CurrentFrame()).to.equal(1)
				expect(List.Status()).to.equal(0)
				expect(List.Active()).to.beFalse()
				-- the rows are made again by the movie: all hidden until the next weapon change
				for index = 0, 4 do
					expect((row(index))).to.beFalse()
				end

				-- a status given before the movie exists is applied when it is made
				List.Reset()
				listener(1)
				List.Show(fakePlayer({a}), a)
				expect(List.Root():Child("Root"):CurrentLabel()).to.equal("malfunction")
			end
		},
		{
			-- fails if the movie's Root clip is left to play: its first frame has no stop(), the original's C++ calls destroy(0) after loading it
			name = "the movie's Root clip stays on its first frame while the list plays (it would run into the red malfunction frame)",
			func = function()
				API.RegisterWeapon("t_list_a", {listIcon = "SMG"})

				local a = fakeWeapon("t_list_a", 1, 0)
				List.Show(fakePlayer({a}), a)
				run(2)
				expect(List.Root():Child("Root"):CurrentFrame()).to.equal(1)
			end
		}
	}
}
