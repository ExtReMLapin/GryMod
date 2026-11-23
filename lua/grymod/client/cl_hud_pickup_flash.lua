-- The pickup popup drawn from the original Scaleform movie (HUD_AmmoPickup), see cl_flash.lua: a small line "<count> x <ammo icon> <name>"
-- at the bottom right that fades out in 50 frames (1.7 s) when the player takes ammo, a weapon or an item. The movie's function
-- setPickup(count, iconIndex, name) is ported by hand: the numbers and the name are written in its two rows, the icon is a frame of its
-- AmmoIcons clip, and the three pieces of the row are placed one after the other as the movie's own updateWidth() does. The same icon taken
-- again while the popup is still on adds the counts (the original's rule).
--
-- The game tells us with its own hooks (HUDAmmoPickedUp, HUDWeaponPickedUp, HUDItemPickedUp), so nothing runs between two pickups, and the
-- paint hook exists only while a popup is on. The Half-Life 2 list of pickups (CHudHistoryResource) is hidden while this one is on.
--
-- The icons of the movie are AMMO icons (bullets, shells, rockets...), 17 of them; what picks which is a small registry in this file
-- (GryMod.API.RegisterPickupIcon), filled for the Half-Life 2 ammo and weapons the same way an addon fills it. A pickup that no entry
-- names shows the movie's "New" frame, which has no picture here: the count and the name only.

GryMod = GryMod or {}

local Flash = GryMod.Flash
local API = GryMod.API

local Pickup = {}
GryMod.FlashPickup = Pickup

Pickup.MOVIE = "hud_ammopickup"

local STAGE_W, STAGE_H = 1024, 768

-- The width of each icon of the movie's AmmoIcons clip (stage pixels at the scale the clip draws them), measured on the movie: the row's
-- layout needs it (updateWidth: AmmoIcons._width). Also the list of the icons there are.
Pickup.ICON_WIDTH = {
	Riffle = 6, socom = 5.5, shootgun = 9.6, missle = 37.2, rocket = 48, FY71 = 24.3, Hurricane = 14.2, LAW = 25.8, TACGun = 22.9,
	GaussRifle = 26.3, DSG1 = 22, MOAR = 23.9, MOAC = 18.9, Flashbang = 15.5, SmokeGrenade = 17.6, Sleep = 34.2, AVMine = 24.6, New = 0
}

local ANZAHL_WIDTH = 38.3 -- the width of the movie's count (its two text fields)
local ICON_SCALE = 0.99 -- the AmmoIcons clip holds its icon at this scale
local LIFE = 50 / 30 -- the movie's own life of a popup (seconds)

function Pickup.Placement(w, h)
	local scale = h / STAGE_H

	return (w - STAGE_W * scale) / 2, 0, scale
end

-- ---------------------------------------------------------------------------------------------------------
-- The registry of pickup icons: (kind, name) -> a frame of the movie. Kinds: "ammo" (the ammo type's name), "weapon" (the class), "item"
-- (the class). The name is compared in lower case.
-- ---------------------------------------------------------------------------------------------------------

local KINDS = {ammo = true, weapon = true, item = true}
local icons = {ammo = {}, weapon = {}, item = {}}

-- Gives the pickup of this kind and name the icon (a label of the movie: see Pickup.ICON_WIDTH). Returns true, or false and why not.
function API.RegisterPickupIcon(kind, name, icon)
	if not KINDS[kind] then
		return false, "invalid kind"
	end

	if not isstring(name) or name == "" or #name > 64 then
		return false, "invalid name"
	end

	if not isstring(icon) or Pickup.ICON_WIDTH[icon] == nil then
		return false, "invalid icon"
	end

	icons[kind][string.lower(name)] = icon

	return true
end

function API.UnregisterPickupIcon(kind, name)
	if not KINDS[kind] or not isstring(name) or icons[kind][string.lower(name)] == nil then
		return false
	end

	icons[kind][string.lower(name)] = nil

	return true
end

-- The icon registered for this pickup, or "New" (no picture).
function API.GetPickupIcon(kind, name)
	local set = KINDS[kind] and icons[kind]

	return set and isstring(name) and set[string.lower(name)] or "New"
end

-- The stock Half-Life 2 pickups: the ammo, then the weapons that carry it.
local function stock(kind, name, icon)
	API.RegisterPickupIcon(kind, name, icon)
end

stock("ammo", "Pistol", "socom")
stock("ammo", "SMG1", "FY71")
stock("ammo", "AR2", "Riffle")
stock("ammo", "357", "Hurricane")
stock("ammo", "Buckshot", "shootgun")
stock("ammo", "XBowBolt", "DSG1")
stock("ammo", "RPG_Round", "rocket")
stock("ammo", "SMG1_Grenade", "missle")
stock("ammo", "Grenade", "Flashbang")
stock("ammo", "AR2AltFire", "MOAC")
stock("weapon", "weapon_pistol", "socom")
stock("weapon", "weapon_smg1", "FY71")
stock("weapon", "weapon_ar2", "Riffle")
stock("weapon", "weapon_357", "Hurricane")
stock("weapon", "weapon_shotgun", "shootgun")
stock("weapon", "weapon_crossbow", "DSG1")
stock("weapon", "weapon_rpg", "rocket")
stock("weapon", "weapon_frag", "Flashbang")
stock("weapon", "weapon_slam", "AVMine")

-- ---------------------------------------------------------------------------------------------------------
-- What is shown
-- ---------------------------------------------------------------------------------------------------------

-- Whether the popups are on: the HUD is on (and the suit with it) and the player did not turn the pickups off.
function Pickup.Enabled()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.Enabled() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("pickups"))
end

-- The text of a name for the popup: capitals (the movie's font is one), without line breaks, 28 characters at most.
function Pickup.Label(name)
	name = string.upper(string.gsub(tostring(name or ""), "[%c]+", " "))

	if #name > 28 then
		name = string.sub(name, 1, 28)
	end

	return name
end

-- The count that a popup shows: the same pickup taken again while the popup is still on adds to it (the original's rule: the same icon;
-- here also the same name, since every unknown pickup has the same blank icon). `previous` is {icon, name, count} of the popup on show, or nil.
function Pickup.Total(previous, icon, name, count)
	if previous and previous.icon == icon and previous.name == name then
		return previous.count + count
	end

	return count
end

-- The x of the three pieces of the row, from the widths of the count, of the icon and of the name: the movie's updateWidth().
function Pickup.RowLayout(nameWidth, iconWidth)
	return {count = -nameWidth, icon = ANZAHL_WIDTH - 8 - nameWidth, name = ANZAHL_WIDTH + iconWidth * ICON_SCALE + 5 - nameWidth}
end

local instance -- {movie, root, template, rows}
local failed = false
local current -- {icon, name, count} on show
local hooked = false
local lastTime

local HOOK = "GRYFLASHPICKUP"

local function ensure()
	if instance then
		return instance
	end

	if failed then
		return nil
	end

	local movie = Flash.Load(Pickup.MOVIE)
	local root = movie and Flash.NewRoot(movie, GryMod.FlashHUD and GryMod.FlashHUD.Theme)
	local holder = root and root:Child("Root")
	local template = holder and holder:Child("Template")

	if not template then
		if root then
			Flash.ReleaseClip(root)
		end

		failed = true

		return nil
	end

	instance = {movie = movie, root = root, template = template}

	return instance
end

-- Writes the popup into one of the two rows of the movie (Anzahl and Anzahl2, which fade at their own times).
local function writeRow(rowClip, movie, info)
	local colorset = rowClip and rowClip:Child("Colorset")

	if not colorset then
		return
	end

	local count = colorset:Child("Anzahl")
	local iconClip = colorset:Child("AmmoIcons")
	local art = colorset:Child("Art")
	local frames = iconClip and iconClip:Child("Colorset")

	if not (count and iconClip and art and frames) then
		return
	end

	-- the count is the field at the first depth of its clip (the two fields of the movie have the same instance name)
	local field = count:EntryAt(1)

	if field and field.kind == "text" then
		field.text = tostring(info.count)
		count:_touch()
	end

	frames:GotoAndStop(info.icon)
	art:SetText("Art", info.name)
	art:FitTextWidth("Art", info.name, 400)

	local definition = art:Field("Art")
	local layout = Pickup.RowLayout(definition and definition.w or 0, Pickup.ICON_WIDTH[info.icon] or 0)

	count:SetX(layout.count)
	iconClip:SetX(layout.icon)
	art:SetX(layout.name)
end

local function stopPaint()
	if hooked then
		hook.Remove("HUDPaint", HOOK)
		hooked = false
	end

	lastTime = nil
end

function Pickup.Paint()
	if not instance or not current then
		stopPaint()

		return
	end

	local now = RealTime()
	local dt = math.min(now - (lastTime or now), 0.1)
	lastTime = now

	instance.root:Advance(dt)

	-- the movie's animation went back to its first frame: the popup is over
	if instance.template:CurrentFrame() == 1 then
		current = nil
		stopPaint()

		return
	end

	if Pickup.Enabled() then
		local x, y, scale = Pickup.Placement(ScrW(), ScrH())

		Flash.Draw(instance.root, x, y, scale)
	end
end

-- Shows a pickup: `count` of something called `name`, with the icon `icon` (a label of the movie). Returns true, or false and why not.
function Pickup.Show(icon, name, count)
	if not Pickup.Enabled() then
		return false, "off"
	end

	count = tonumber(count)

	if not count or count ~= count or count == math.huge or count < 1 then
		return false, "no count"
	end

	local ready = ensure()

	if not ready then
		return false, "no movie"
	end

	name = Pickup.Label(name)
	count = math.floor(count)

	local info = {icon = icon, name = name, count = Pickup.Total(current, icon, name, count)}

	current = info

	-- the animation starts again; the texts after it (a clip made again from its first frame has the movie's own texts)
	ready.template:GotoAndPlay("play")

	for _, rowName in ipairs({"Anzahl", "Anzahl2"}) do
		writeRow(ready.template:Child(rowName), ready.movie, info)
	end

	if not hooked then
		lastTime = nil
		hook.Add("HUDPaint", HOOK, Pickup.Paint)
		hooked = true
	end

	return true
end

-- What is on show: {icon, name, count}, or nil (tests and tools).
function Pickup.Current()
	return current
end

function Pickup.Active()
	return hooked
end

function Pickup.Template()
	return instance and instance.template
end

-- Takes the popup away (a new life, a new theme).
function Pickup.Reset()
	stopPaint()
	current = nil

	if instance then
		Flash.ReleaseClip(instance.root)
	end

	instance, failed = nil, false
end

-- ---------------------------------------------------------------------------------------------------------
-- The game's three hooks
-- ---------------------------------------------------------------------------------------------------------

-- Ammo: the name is the ammo type's ("Pistol", "SMG1"), shown by its translated name when the game has one ("Pistol ammo").
function Pickup.Ammo(name, amount)
	if not isstring(name) then
		return false
	end

	local label = name

	if language and language.GetPhrase then
		local phrase = language.GetPhrase(name .. "_ammo")

		if isstring(phrase) and phrase ~= (name .. "_ammo") and phrase ~= "" then
			label = phrase
		end
	end

	return Pickup.Show(API.GetPickupIcon("ammo", name), label, amount)
end

-- A weapon: its print name (a "#" key is translated), the icon of its class.
function Pickup.Weapon(weapon)
	if not weapon or not IsValid(weapon) then
		return false
	end

	local name = isfunction(weapon.GetPrintName) and weapon:GetPrintName() or weapon:GetClass()

	if isstring(name) and string.sub(name, 1, 1) == "#" and language and language.GetPhrase then
		name = language.GetPhrase(string.sub(name, 2))
	end

	return Pickup.Show(API.GetPickupIcon("weapon", weapon:GetClass()), name, 1)
end

-- An item: the name the game gives (the class of the item), translated when the game has a name for it.
function Pickup.Item(name)
	if not isstring(name) then
		return false
	end

	local label = name

	if language and language.GetPhrase then
		local phrase = language.GetPhrase(name)

		if isstring(phrase) and phrase ~= "" and phrase ~= name then
			label = phrase
		end
	end

	if label == name then
		label = string.gsub(string.gsub(name, "^item_", ""), "_", " ")
	end

	return Pickup.Show(API.GetPickupIcon("item", name), label, 1)
end

hook.Add("HUDAmmoPickedUp", "GryPickups", function(name, amount)
	Pickup.Ammo(name, amount)
end)

hook.Add("HUDWeaponPickedUp", "GryPickups", function(weapon)
	Pickup.Weapon(weapon)
end)

hook.Add("HUDItemPickedUp", "GryPickups", function(name)
	Pickup.Item(name)
end)

-- The Half-Life 2 list of pickups stays away while ours is on (the HUD is drawn and the player did not turn the popups off).
function Pickup.HidesStock()
	return GryMod.FlashHUD ~= nil and GryMod.FlashHUD.HudWanted() and (not GryMod.HUDOptions or GryMod.HUDOptions.Enabled("pickups"))
end

hook.Add("HUDShouldDraw", "GRYPICKUPHIDE", function(name)
	if name == "CHudHistoryResource" and Pickup.HidesStock() then
		return false
	end
end)
