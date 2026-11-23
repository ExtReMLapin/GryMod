-- Tests of the pickup popup drawn from the original Scaleform movie (GryMod.FlashPickup, lua/grymod/client/cl_hud_pickup_flash.lua), GLuaTest
-- format, client realm. Needs the converted movie lua/grymod/flash/hud_ammopickup.lua. The rules are the movie's own (setPickup: the count, the
-- icon, the name; the same icon again adds the counts; 50 frames of life); the game's three hooks drive it and the Half-Life 2 list of pickups
-- stays away while it is on. The live game is replaced where a case needs it and put back in afterEach inside a pcall: the HUD state, the
-- drawing, the clock, the settings.

local Pickup = GryMod.FlashPickup
local API = GryMod.API
local Flash = GryMod.Flash

local saved = {}
local convarsSaved = {}
local drawn
local clock

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
		Pickup.Paint()
	end
end

-- what the first row of the movie holds: the count's text, the frame of the icon, the name's text
local function row()
	local colorset = Pickup.Template():Child("Anzahl"):Child("Colorset")

	return colorset:Child("Anzahl"):EntryAt(1).text,
		colorset:Child("AmmoIcons"):Child("Colorset"):CurrentFrame(),
		colorset:Child("Art"):Child("Art").text
end

local function fakeWeapon(class, print)
	return {
		IsValid = function() return true end,
		GetClass = function() return class end,
		GetPrintName = function() return print end
	}
end

local function listener(hookName)
	return hook.GetTable()[hookName]["GryPickups"]
end

return {
	groupName = "GryMod pickup popup (HUD_AmmoPickup)",
	beforeEach = function()
		Pickup.Reset()
		drawn, clock = 0, 100

		stub(GryMod.FlashHUD, "Enabled", function() return true end)
		stub(GryMod.FlashHUD, "HudWanted", function() return true end)
		stub(Flash, "Draw", function() drawn = drawn + 1 return true end)
		stub(_G, "RealTime", function() return clock end)
		setConVar("gry_hud_pickups", "1")
	end,
	afterEach = function()
		pcall(Pickup.Reset)
		pcall(restore)
	end,
	cases = {
		{
			-- fails without the registry of pickup icons
			name = "the icon registry: the Half-Life 2 ammo and weapons have theirs, the name is not case sensitive, the rest is the blank \"New\", a bad entry is refused",
			func = function()
				expect(API.GetPickupIcon("ammo", "Pistol")).to.equal("socom")
				expect(API.GetPickupIcon("ammo", "pistol")).to.equal("socom")
				expect(API.GetPickupIcon("ammo", "SMG1")).to.equal("FY71")
				expect(API.GetPickupIcon("weapon", "weapon_shotgun")).to.equal("shootgun")
				expect(API.GetPickupIcon("ammo", "NoSuchAmmo")).to.equal("New")
				expect(API.GetPickupIcon("item", "item_healthkit")).to.equal("New")
				expect(API.GetPickupIcon("nothing", "Pistol")).to.equal("New")
				expect(API.GetPickupIcon("ammo", nil)).to.equal("New")

				expect(API.RegisterPickupIcon("item", "item_test_pickup", "AVMine")).to.beTrue()
				expect(API.GetPickupIcon("item", "ITEM_TEST_PICKUP")).to.equal("AVMine")
				expect(API.UnregisterPickupIcon("item", "item_test_pickup")).to.beTrue()
				expect(API.UnregisterPickupIcon("item", "item_test_pickup")).to.beFalse()
				expect(API.GetPickupIcon("item", "item_test_pickup")).to.equal("New")

				for _, args in ipairs({{"gun", "x", "socom"}, {"ammo", "", "socom"}, {"ammo", 5, "socom"}, {"ammo", "x", "Laser"}, {"ammo", "x", 3}}) do
					local ok, reason = API.RegisterPickupIcon(args[1], args[2], args[3])
					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
				end
			end
		},
		{
			-- fails without Label, Total and RowLayout
			name = "the name is in capitals on one line and 28 characters at most; the same pickup adds its counts; the row is placed as the movie's updateWidth does",
			func = function()
				expect(Pickup.Label("smg1 ammo")).to.equal("SMG1 AMMO")
				expect(Pickup.Label("a\nb")).to.equal("A B")
				expect(#Pickup.Label(string.rep("x", 60))).to.equal(28)
				expect(Pickup.Label(nil)).to.equal("")

				expect(Pickup.Total(nil, "socom", "PISTOL", 12)).to.equal(12)
				expect(Pickup.Total({icon = "socom", name = "PISTOL", count = 12}, "socom", "PISTOL", 5)).to.equal(17)
				expect(Pickup.Total({icon = "socom", name = "PISTOL", count = 12}, "FY71", "SMG1", 5)).to.equal(5)
				-- the same blank icon with another name is another pickup
				expect(Pickup.Total({icon = "New", name = "A", count = 1}, "New", "B", 1)).to.equal(1)

				local layout = Pickup.RowLayout(22, 10)
				expect(layout.count).to.equal(-22)
				expect(math.abs(layout.icon - (38.3 - 8 - 22)) < 1e-9).to.beTrue()
				expect(math.abs(layout.name - (38.3 + 9.9 + 5 - 22)) < 1e-9).to.beTrue()
			end
		},
		{
			-- fails without the drive of the movie
			name = "a pickup writes the count, the icon's frame and the name in the movie, and starts its animation; the paint hook comes with it",
			func = function()
				expect(Pickup.Active()).to.beFalse()
				expect(Pickup.Show("socom", "pistol ammo", 12)).to.beTrue()

				local count, frame, name = row()
				expect(count).to.equal("12")
				expect(frame).to.equal(2) -- the label "socom"
				expect(name).to.equal("PISTOL AMMO")
				expect(Pickup.Template():CurrentFrame()).to.equal(2)
				expect(Pickup.Active()).to.beTrue()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHPICKUP"]).to.exist()
			end
		},
		{
			-- fails if the second row were not written (the movie has two, Anzahl and Anzahl2)
			name = "both rows of the movie hold the same pickup",
			func = function()
				Pickup.Show("FY71", "smg1", 30)

				local second = Pickup.Template():Child("Anzahl2"):Child("Colorset")
				expect(second:Child("Anzahl"):EntryAt(1).text).to.equal("30")
				expect(second:Child("Art"):Child("Art").text).to.equal("SMG1")
				expect(second:Child("AmmoIcons"):Child("Colorset"):CurrentFrame()).to.equal(6)
			end
		},
		{
			-- fails without the adding of the counts
			name = "the same pickup taken again while the popup is on adds the counts; another one replaces it and starts again",
			func = function()
				Pickup.Show("socom", "pistol", 12)
				run(0.5)
				Pickup.Show("socom", "pistol", 5)
				expect(Pickup.Current().count).to.equal(17)
				expect(row()).to.equal("17")
				expect(Pickup.Template():CurrentFrame()).to.equal(2) -- the animation started again

				Pickup.Show("FY71", "smg1", 3)
				expect(Pickup.Current().count).to.equal(3)
				local count, frame = row()
				expect(count).to.equal("3")
				expect(frame).to.equal(6)
			end
		},
		{
			-- fails if the popup never ended or the hook stayed
			name = "the popup ends after its 50 frames, and the paint hook goes with it; a pickup after that starts from its own count",
			func = function()
				Pickup.Show("socom", "pistol", 12)
				run(1)
				expect(Pickup.Active()).to.beTrue()
				expect(drawn > 0).to.beTrue()

				run(1)
				expect(Pickup.Current()).to.beNil()
				expect(Pickup.Active()).to.beFalse()
				expect(hook.GetTable()["HUDPaint"]["GRYFLASHPICKUP"]).to.beNil()

				Pickup.Show("socom", "pistol", 4)
				expect(Pickup.Current().count).to.equal(4)
			end
		},
		{
			-- fails if a bad count were shown
			name = "a count that is not a positive number shows nothing",
			func = function()
				for _, count in ipairs({0, -3, 0 / 0, math.huge, "many"}) do
					expect((Pickup.Show("socom", "pistol", count))).to.beFalse()
				end

				expect(Pickup.Active()).to.beFalse()
				expect(Pickup.Current()).to.beNil()
				expect(Pickup.Show("socom", "pistol", "7")).to.beTrue() -- a number as text is a number
				expect(Pickup.Current().count).to.equal(7)
			end
		},
		{
			-- fails without the three hooks of the game
			name = "the game's three hooks show an ammo pickup, a weapon and an item",
			func = function()
				listener("HUDAmmoPickedUp")("Pistol", 18)
				expect(Pickup.Current().icon).to.equal("socom")
				expect(Pickup.Current().count).to.equal(18)
				expect(#Pickup.Current().name > 0).to.beTrue()

				listener("HUDWeaponPickedUp")(fakeWeapon("weapon_smg1", "SMG"))
				expect(Pickup.Current().icon).to.equal("FY71")
				expect(Pickup.Current().name).to.equal("SMG")
				expect(Pickup.Current().count).to.equal(1)

				listener("HUDItemPickedUp")("item_healthkit")
				expect(Pickup.Current().icon).to.equal("New")
				expect(#Pickup.Current().name > 0).to.beTrue()

				-- junk is ignored
				local before = Pickup.Current()
				listener("HUDAmmoPickedUp")(nil, 3)
				listener("HUDWeaponPickedUp")(nil)
				listener("HUDItemPickedUp")(5)
				expect(Pickup.Current()).to.equal(before)
			end
		},
		{
			-- fails without the switch
			name = "the pickups off (gry_hud_pickups 0) or the HUD off: nothing is shown",
			func = function()
				setConVar("gry_hud_pickups", "0")
				expect((Pickup.Show("socom", "pistol", 3))).to.beFalse()
				listener("HUDAmmoPickedUp")("Pistol", 3)
				expect(Pickup.Current()).to.beNil()
				expect(Pickup.Active()).to.beFalse()

				setConVar("gry_hud_pickups", "1")
				GryMod.FlashHUD.Enabled = function() return false end
				expect((Pickup.Show("socom", "pistol", 3))).to.beFalse()
				expect(Pickup.Current()).to.beNil()
			end
		},
		{
			-- fails without the HUDShouldDraw hook, or if it hid other things
			name = "the Half-Life 2 list of pickups is hidden while the HUD and the popups are on, and nothing else is",
			func = function()
				local hide = hook.GetTable()["HUDShouldDraw"]["GRYPICKUPHIDE"]
				expect(hide).to.exist()

				expect(hide("CHudHistoryResource")).to.beFalse()
				expect(hide("CHudHealth")).to.beNil()
				expect(hide("CHudCrosshair")).to.beNil()

				setConVar("gry_hud_pickups", "0")
				expect(hide("CHudHistoryResource")).to.beNil()

				setConVar("gry_hud_pickups", "1")
				GryMod.FlashHUD.HudWanted = function() return false end
				expect(hide("CHudHistoryResource")).to.beNil()
			end
		}
	}
}
