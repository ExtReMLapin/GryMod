-- Tests of the weapon registry of the extension API (lua/grymod/sh_api_weapons.lua, and the data of the stock weapons in
-- compat/hl2/sh_weapons.lua), GLuaTest format, runs in the server AND in the client realm: RegisterWeapon / GetWeapon /
-- UnregisterWeapon, the validation of a definition, ResolveWeapon (registry, base class, SWEP.GryHUD, adapters, defaults read
-- from the SWEP and from CustomAmmoDisplay) and what the Half-Life 2 weapons say about their secondary fire.
-- Design: docs/superpowers/specs/2026-11-21-extension-api-design.md, part 4.

local API
local realGetStored
local stored
local realMsgN
local lines

local CLASSES = {"t_wep_a", "t_wep_b", "t_wep_base", "t_wep_child"}
local ADAPTERS = {"t_ad_one", "t_ad_two", "t_ad_bad"}

-- a weapon entity of the tests: a table that answers like one
local function weapon(class, fields)
	local wep = {
		GetClass = function() return class end
	}

	for key, value in pairs(fields or {}) do
		wep[key] = value
	end

	return wep
end

return {
	groupName = "GryMod extension API: weapon registry (shared)",
	beforeEach = function()
		API = GryMod.API
		stored = {}
		realGetStored = weapons.GetStored
		weapons.GetStored = function(class)
			return stored[class] or realGetStored(class)
		end

		lines = {}
		realMsgN = MsgN
		MsgN = function(...)
			lines[#lines + 1] = table.concat({...}, "")
		end
	end,
	afterEach = function()
		MsgN = realMsgN
		weapons.GetStored = realGetStored

		for _, class in ipairs(CLASSES) do
			if API.UnregisterWeapon then
				API.UnregisterWeapon(class)
			end

			API.SafeCallReset("weapon:" .. class .. "/fire")
			API.SafeCallReset("weapon:" .. class .. "/display")
		end

		for _, id in ipairs(ADAPTERS) do
			if API.RemoveWeaponAdapter then
				API.RemoveWeaponAdapter(id)
			end

			API.SafeCallReset("adapter:" .. id)
		end
	end,
	cases = {
		{
			name = "Has tells that the weapon registry exists",
			func = function()
				expect(API.Has("weapons")).to.beTrue()
			end
		},
		{
			name = "RegisterWeapon stores a definition, GetWeapon gives it back (a copy), UnregisterWeapon removes it",
			func = function()
				local ok = API.RegisterWeapon("t_wep_a", {fire = "burst", burst = 3, ammo = "SMG1", counter = "clip", alt = "grenade", altAmmo = "SMG1_Grenade", altShoots = true, altLabel = "40mm", altIcon = "Grenade", icon = "C4", slotIcon = "Burst"})

				expect(ok).to.beTrue()

				local def = API.GetWeapon("t_wep_a")
				expect(def.fire).to.equal("burst")
				expect(def.burst).to.equal(3)
				expect(def.ammo).to.equal("SMG1")
				expect(def.counter).to.equal("clip")
				expect(def.alt).to.equal("grenade")
				expect(def.altAmmo).to.equal("SMG1_Grenade")
				expect(def.altShoots).to.beTrue()
				expect(def.altLabel).to.equal("40mm")
				expect(def.altIcon).to.equal("Grenade")
				expect(def.icon).to.equal("C4")
				expect(def.slotIcon).to.equal("Burst")

				def.fire = "auto" -- a copy: the registry does not change
				expect(API.GetWeapon("t_wep_a").fire).to.equal("burst")

				expect(API.UnregisterWeapon("t_wep_a")).to.beTrue()
				expect(API.GetWeapon("t_wep_a")).to.beNil()
				expect(API.UnregisterWeapon("t_wep_a")).to.beFalse()
			end
		},
		{
			name = "registering a class again replaces its definition, and the caller's table is not kept",
			func = function()
				local mine = {fire = "auto"}
				API.RegisterWeapon("t_wep_a", mine)
				mine.fire = "semi"
				expect(API.GetWeapon("t_wep_a").fire).to.equal("auto")

				API.RegisterWeapon("t_wep_a", {alt = "zoom"})
				expect(API.GetWeapon("t_wep_a").fire).to.beNil()
				expect(API.GetWeapon("t_wep_a").alt).to.equal("zoom")
			end
		},
		{
			name = "unknown fields are ignored (dropped), not an error",
			func = function()
				local ok = API.RegisterWeapon("t_wep_a", {fire = "semi", rocket = 12, color = "red"})

				expect(ok).to.beTrue()
				expect(API.GetWeapon("t_wep_a").fire).to.equal("semi")
				expect(API.GetWeapon("t_wep_a").rocket).to.beNil()
				expect(API.GetWeapon("t_wep_a").color).to.beNil()
			end
		},
		{
			name = "an invalid enumeration value is refused with false and a reason naming the field, and nothing is stored",
			func = function()
				local bad = {
					{fire = "rapid"}, {alt = "laser"}, {counter = "text"}, {icon = "NoSuchIcon"}, {slotIcon = "Nope"}, {altIcon = "Nothing"}
				}
				local fields = {"fire", "alt", "counter", "icon", "slotIcon", "altIcon"}

				for i, def in ipairs(bad) do
					local ok, reason = API.RegisterWeapon("t_wep_a", def)

					expect(ok).to.beFalse()
					expect(isstring(reason)).to.beTrue()
					expect(string.find(reason, fields[i], 1, true) ~= nil).to.beTrue()
					expect(API.GetWeapon("t_wep_a")).to.beNil()
				end
			end
		},
		{
			name = "a refused definition does not replace the one that was there",
			func = function()
				API.RegisterWeapon("t_wep_a", {fire = "auto"})
				local ok = API.RegisterWeapon("t_wep_a", {fire = "rapid"})

				expect(ok).to.beFalse()
				expect(API.GetWeapon("t_wep_a").fire).to.equal("auto")
			end
		},
		{
			name = "wrong types are refused too: ammo, altAmmo, altShoots, burst, the class and the definition itself",
			func = function()
				expect((API.RegisterWeapon("t_wep_a", {ammo = 5}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {altAmmo = {}}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {altShoots = "yes"}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {crosshair = "no"}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {crosshair = 0}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {altLabel = 5}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {altLabel = ""}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {altLabel = string.rep("x", 40)}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {burst = 1.5}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {burst = 0}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", {fire = 3}))).to.beFalse()
				expect((API.RegisterWeapon("", {fire = "auto"}))).to.beFalse()
				expect((API.RegisterWeapon(nil, {fire = "auto"}))).to.beFalse()
				expect((API.RegisterWeapon(12, {fire = "auto"}))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", "auto"))).to.beFalse()
				expect((API.RegisterWeapon("t_wep_a", nil))).to.beFalse()
				expect(API.GetWeapon("t_wep_a")).to.beNil()
				expect(API.GetWeapon(nil)).to.beNil()
			end
		},
		{
			name = "crosshair (a boolean): false hides the HUD's crosshair for the weapon; true and undeclared show it; a refusal says why and keeps the previous entry",
			func = function()
				local ok = API.RegisterWeapon("t_wep_a", {crosshair = false})

				expect(ok).to.beTrue()
				expect(API.GetWeapon("t_wep_a").crosshair).to.beFalse()
				expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.beFalse()
				expect(API.ResolveWeapon(weapon("t_wep_a")).crosshair).to.beFalse()
				expect(API.ResolveWeapon("t_wep_a", true).crosshair).to.beFalse()

				local bad, reason = API.RegisterWeapon("t_wep_a", {crosshair = "no"})

				expect(bad).to.beFalse()
				expect(string.find(reason, "crosshair", 1, true) ~= nil).to.beTrue()
				expect(API.GetWeapon("t_wep_a").crosshair).to.beFalse()

				API.RegisterWeapon("t_wep_a", {crosshair = true})
				expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.beTrue()

				-- nothing declared: the crosshair is shown (a resolved description says true, the declared-only one says nothing)
				API.RegisterWeapon("t_wep_a", {fire = "auto"})
				expect(API.ResolveWeapon(weapon("t_wep_a")).crosshair).to.beTrue()
				expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.beNil()
				expect(API.ResolveWeapon("t_wep_b").crosshair).to.beTrue()
			end
		},
		{
			name = "crosshair = false is read from SWEP.GryHUD and from the base class like any other field; an invalid one is ignored",
			func = function()
				stored.t_wep_a = {GryHUD = {crosshair = false}}
				expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.beFalse()
				expect(API.WeaponValue(weapon("t_wep_a", stored.t_wep_a), "crosshair", true)).to.beFalse()

				stored.t_wep_b = {GryHUD = {crosshair = "no"}}
				expect(API.WeaponValue("t_wep_b", "crosshair", true)).to.beNil()

				API.RegisterWeapon("t_wep_base", {crosshair = false})
				stored.t_wep_child = {Base = "t_wep_base"}
				expect(API.WeaponValue("t_wep_child", "crosshair", true)).to.beFalse()
			end
		},
		{
			name = "the Half-Life 2 fists and RPG have no crosshair (data), the other stock weapons say nothing about it",
			func = function()
				expect(API.WeaponValue("weapon_fists", "crosshair", true)).to.beFalse()
				expect(API.WeaponValue("weapon_rpg", "crosshair", true)).to.beFalse()
				expect(API.ResolveWeapon("weapon_rpg").slotIcon).to.equal("Missle")
				expect(API.ResolveWeapon("weapon_fists").fire).to.equal("none")

				for _, class in ipairs({"weapon_smg1", "weapon_ar2", "weapon_pistol", "weapon_357", "weapon_shotgun", "weapon_crossbow", "weapon_frag", "weapon_crowbar", "weapon_physcannon"}) do
					expect(API.WeaponValue(class, "crosshair", true) == false).to.beFalse()
					expect(API.ResolveWeapon(class).crosshair).to.beTrue()
				end
			end
		},
		{
			-- Fails without the `grenade` field in sh_api_weapons.lua (the field is dropped as unknown: nothing is stored)
			name = "grenade: the kind of hand grenade of the weapon (one of the four kinds of the movie); an unknown kind is refused and keeps the previous entry",
			func = function()
				for _, kind in ipairs({"explosivegrenade", "flashbang", "smokegrenade", "empgrenade"}) do
					expect(API.GrenadeKinds[kind]).to.beTrue()
					expect((API.RegisterWeapon("t_wep_a", {grenade = kind}))).to.beTrue()
					expect(API.GetWeapon("t_wep_a").grenade).to.equal(kind)
					expect(API.WeaponValue("t_wep_a", "grenade", true)).to.equal(kind)
					expect(API.ResolveWeapon(weapon("t_wep_a")).grenade).to.equal(kind)
				end

				local ok, reason = API.RegisterWeapon("t_wep_a", {grenade = "napalm"})
				expect(ok).to.beFalse()
				expect(string.find(reason, "grenade", 1, true) ~= nil).to.beTrue()
				expect(API.GetWeapon("t_wep_a").grenade).to.equal("empgrenade")
				expect((API.RegisterWeapon("t_wep_a", {grenade = 3}))).to.beFalse()

				-- declared nowhere: nothing (the HUD takes the explosive grenade)
				API.RegisterWeapon("t_wep_b", {fire = "auto"})
				expect(API.WeaponValue("t_wep_b", "grenade", true)).to.beNil()
			end
		},
		{
			name = "grenade is read from SWEP.GryHUD and from the base class; the stock frag grenade is data: an explosive grenade",
			func = function()
				stored.t_wep_a = {GryHUD = {grenade = "smokegrenade"}}
				expect(API.WeaponValue("t_wep_a", "grenade", true)).to.equal("smokegrenade")
				stored.t_wep_b = {GryHUD = {grenade = "napalm"}}
				expect(API.WeaponValue("t_wep_b", "grenade", true)).to.beNil()
				API.RegisterWeapon("t_wep_base", {grenade = "flashbang"})
				stored.t_wep_child = {Base = "t_wep_base"}
				expect(API.WeaponValue("t_wep_child", "grenade", true)).to.equal("flashbang")
				expect(API.WeaponValue("weapon_frag", "grenade", true)).to.equal("explosivegrenade")
			end
		},
		{
			-- Fails without the `heat` field in sh_api_weapons.lua (dropped as unknown: GetWeapon(...).heat is nil)
			name = "heat: a function returning the heat of the weapon (0 to 1); anything else is refused and keeps the previous entry",
			func = function()
				local function read() return 0.5 end
				expect((API.RegisterWeapon("t_wep_a", {heat = read}))).to.beTrue()
				expect(API.GetWeapon("t_wep_a").heat).to.equal(read)
				expect(API.WeaponValue("t_wep_a", "heat", true)).to.equal(read)
				expect(API.ResolveWeapon(weapon("t_wep_a")).heat).to.equal(read)

				for _, bad in ipairs({0.5, "heat", true}) do
					local ok, reason = API.RegisterWeapon("t_wep_a", {heat = bad})
					expect(ok).to.beFalse()
					expect(string.find(reason, "heat", 1, true) ~= nil).to.beTrue()
					expect(API.GetWeapon("t_wep_a").heat).to.equal(read)
				end

				-- SWEP.GryHUD and the adapters can give it too
				stored.t_wep_b = {GryHUD = {heat = read}}
				expect(API.WeaponValue("t_wep_b", "heat", true)).to.equal(read)
				stored.t_wep_child = {GryHUD = {heat = 0.3}}
				expect(API.WeaponValue("t_wep_child", "heat", true)).to.beNil()
			end
		},
		{
			-- Fails without the `listIcon` field in sh_api_weapons.lua (dropped as unknown: GetWeapon(...).listIcon is nil)
			name = "listIcon: one of the 25 silhouettes of the weapon list movie; an unknown label or a non-string is refused and keeps the previous entry",
			func = function()
				expect(API.WeaponListIcons).to.exist()

				local count = 0

				for label in pairs(API.WeaponListIcons) do
					count = count + 1
					expect((API.RegisterWeapon("t_wep_a", {listIcon = label}))).to.beTrue()
					expect(API.GetWeapon("t_wep_a").listIcon).to.equal(label)
					expect(API.WeaponValue("t_wep_a", "listIcon", true)).to.equal(label)
				end

				expect(count).to.equal(25)
				-- the "forbidden" sign of the movie ("emtpy") is not a weapon: it is not on the list of labels
				expect(API.WeaponListIcons.emtpy).to.beNil()

				API.RegisterWeapon("t_wep_a", {listIcon = "SCAR"})
				expect(API.ResolveWeapon(weapon("t_wep_a")).listIcon).to.equal("SCAR")

				for _, bad in ipairs({"scar", "Laser", "emtpy", 3, true}) do
					local ok, reason = API.RegisterWeapon("t_wep_a", {listIcon = bad})
					expect(ok).to.beFalse()
					expect(string.find(reason, "listIcon", 1, true) ~= nil).to.beTrue()
					expect(API.GetWeapon("t_wep_a").listIcon).to.equal("SCAR")
				end

				-- SWEP.GryHUD and the base class give it too; an invalid one in GryHUD is ignored
				stored.t_wep_b = {GryHUD = {listIcon = "DSG1"}}
				expect(API.WeaponValue("t_wep_b", "listIcon", true)).to.equal("DSG1")
				stored.t_wep_child = {GryHUD = {listIcon = "nope"}}
				expect(API.WeaponValue("t_wep_child", "listIcon", true)).to.beNil()
				API.RegisterWeapon("t_wep_base", {listIcon = "Fists"})
				stored.t_wep_a = {Base = "t_wep_base"}
				API.UnregisterWeapon("t_wep_a")
				expect(API.WeaponValue("t_wep_a", "listIcon", true)).to.equal("Fists")
			end
		},
		{
			-- Fails without the listIcon data in compat/hl2/sh_weapons.lua (the stock weapons say nothing: nil)
			name = "the stock Half-Life 2 weapons are mapped to a silhouette of the list as data; the ones with no look-alike have none (a text row)",
			func = function()
				local MAP = {
					weapon_pistol = "SOCOM", weapon_357 = "SOCOM", weapon_smg1 = "SMG", weapon_ar2 = "SCAR", weapon_shotgun = "Shotgun",
					weapon_rpg = "LAW", weapon_crossbow = "DSG1", weapon_frag = "Grenade_Explosive", weapon_crowbar = "Fists",
					weapon_stunstick = "Fists", weapon_fists = "Fists", weapon_slam = "AVMine", weapon_medkit = "RepairKit"
				}

				for class, label in pairs(MAP) do
					expect(API.WeaponValue(class, "listIcon", true)).to.equal(label)
					expect(API.WeaponListIcons[label]).to.beTrue()
				end

				for _, class in ipairs({"weapon_physcannon", "weapon_physgun", "gmod_tool", "gmod_camera", "weapon_bugbait", "weapon_flechettegun"}) do
					expect(API.WeaponValue(class, "listIcon", true)).to.beNil()
				end
			end
		},
		{
			-- Fails without the number case of CHECK.crosshair in sh_api_weapons.lua (a number is refused: "invalid crosshair")
			name = "crosshair may also be the number of one of the 13 crosshairs of the movie (the weapon's own style); 0, 14, a fraction or text are refused",
			func = function()
				for _, style in ipairs({1, 6, 11, 12, 13}) do
					expect((API.RegisterWeapon("t_wep_a", {crosshair = style}))).to.beTrue()
					expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.equal(style)
					expect(API.ResolveWeapon(weapon("t_wep_a")).crosshair).to.equal(style)
				end

				for _, bad in ipairs({0, 14, -1, 2.5, "11"}) do
					local ok, reason = API.RegisterWeapon("t_wep_a", {crosshair = bad})
					expect(ok).to.beFalse()
					expect(string.find(reason, "crosshair", 1, true) ~= nil).to.beTrue()
					expect(API.WeaponValue("t_wep_a", "crosshair", true)).to.equal(13)
				end

				-- from SWEP.GryHUD too, and an invalid one is ignored
				stored.t_wep_b = {GryHUD = {crosshair = 12}}
				expect(API.WeaponValue("t_wep_b", "crosshair", true)).to.equal(12)
				stored.t_wep_child = {GryHUD = {crosshair = 40}}
				expect(API.WeaponValue("t_wep_child", "crosshair", true)).to.beNil()
			end
		},
		{
			name = "the functions are accepted for fire and counter",
			func = function()
				local ok = API.RegisterWeapon("t_wep_a", {fire = function() return "auto" end, counter = function() return "12" end})

				expect(ok).to.beTrue()
				expect(isfunction(API.GetWeapon("t_wep_a").fire)).to.beTrue()
				expect(isfunction(API.GetWeapon("t_wep_a").counter)).to.beTrue()
			end
		},
		{
			name = "the 12 Crysis icons that nothing chose before can be chosen through the icon field",
			func = function()
				for _, label in ipairs({"Incendiary", "Tranquilizer", "infinity", "Narrow", "Moac", "Moar", "TACCannon", "C4", "Gauss", "Gunner", "Mounted", "Claymore"}) do
					expect((API.RegisterWeapon("t_wep_a", {icon = label}))).to.beTrue()
					expect(API.ResolveWeapon(weapon("t_wep_a")).icon).to.equal(label)
				end
			end
		},
		{
			name = "ResolveWeapon gives the registry entry of the class",
			func = function()
				API.RegisterWeapon("t_wep_a", {fire = "burst", burst = 3, alt = "zoom"})
				local def = API.ResolveWeapon(weapon("t_wep_a"))

				expect(def.fire).to.equal("burst")
				expect(def.burst).to.equal(3)
				expect(def.alt).to.equal("zoom")
			end
		},
		{
			name = "a weapon that has no entry takes the entry of its base class (weapons.GetStored(class).Base), the nearest one wins",
			func = function()
				stored.t_wep_child = {Base = "t_wep_base"}
				stored.t_wep_base = {}
				API.RegisterWeapon("t_wep_base", {fire = "burst", alt = "melee"})

				local def = API.ResolveWeapon(weapon("t_wep_child"))
				expect(def.fire).to.equal("burst")
				expect(def.alt).to.equal("melee")

				API.RegisterWeapon("t_wep_child", {fire = "semi"})
				expect(API.ResolveWeapon(weapon("t_wep_child")).fire).to.equal("semi")
			end
		},
		{
			name = "a loop in the base classes does not hang the resolution",
			func = function()
				stored.t_wep_a = {Base = "t_wep_b"}
				stored.t_wep_b = {Base = "t_wep_a"}

				expect(API.ResolveWeapon(weapon("t_wep_a")).alt).to.equal("none")
			end
		},
		{
			name = "SWEP.GryHUD declares a weapon with the same fields, and the registry entry wins over it",
			func = function()
				local gun = weapon("t_wep_a", {GryHUD = {fire = "burst", alt = "zoom", icon = "Gauss", ammo = "Gauss"}})

				expect(API.ResolveWeapon(gun).fire).to.equal("burst")
				expect(API.ResolveWeapon(gun).alt).to.equal("zoom")
				expect(API.ResolveWeapon(gun).icon).to.equal("Gauss")
				expect(API.ResolveWeapon(gun).ammo).to.equal("Gauss")

				API.RegisterWeapon("t_wep_a", {fire = "auto"})
				expect(API.ResolveWeapon(gun).fire).to.equal("auto") -- the registry wins
				expect(API.ResolveWeapon(gun).alt).to.equal("zoom") -- and GryHUD fills what it does not say
			end
		},
		{
			name = "an invalid field in SWEP.GryHUD is ignored, the rest of the table still counts",
			func = function()
				local gun = weapon("t_wep_a", {
					Primary = {Automatic = true},
					GryHUD = {fire = "rapid", alt = "zoom", icon = "NoSuchIcon", altShoots = "x", wat = 1}
				})
				local def = API.ResolveWeapon(gun)

				expect(def.fire).to.equal("auto") -- the default: Primary.Automatic
				expect(def.alt).to.equal("zoom")
				expect(def.icon).to.beNil()
				expect(def.altShoots).to.beFalse() -- zoom does not shoot
				expect(def.wat).to.beNil()
			end
		},
		{
			name = "a GryHUD that is not a table is ignored",
			func = function()
				local def = API.ResolveWeapon(weapon("t_wep_a", {GryHUD = "auto"}))

				expect(def.alt).to.equal("none")
			end
		},
		{
			name = "adapters: AddWeaponAdapter / RemoveWeaponAdapter, called through SafeCall with the weapon, after GryHUD and before the defaults",
			func = function()
				local seen
				local gun = weapon("t_wep_a", {
					Primary = {Automatic = true, Ammo = "PrimaryAmmo"},
					GryHUD = {fire = "burst"}
				})

				expect(API.AddWeaponAdapter("t_ad_one", function(wep)
					seen = wep

					return {fire = "semi", ammo = "AdapterAmmo", icon = "Claymore"}
				end)).to.beTrue()

				local def = API.ResolveWeapon(gun)
				expect(seen).to.equal(gun)
				expect(def.fire).to.equal("burst") -- GryHUD wins over the adapter
				expect(def.ammo).to.equal("AdapterAmmo") -- the adapter wins over Primary.Ammo
				expect(def.icon).to.equal("Claymore")

				expect(API.RemoveWeaponAdapter("t_ad_one")).to.beTrue()
				expect(API.ResolveWeapon(gun).ammo).to.equal("PrimaryAmmo")
				expect(API.RemoveWeaponAdapter("t_ad_one")).to.beFalse()
			end
		},
		{
			name = "adapters are asked in the order they were added; the first to answer a field wins; adding an id again replaces it",
			func = function()
				API.AddWeaponAdapter("t_ad_one", function() return {ammo = "First"} end)
				API.AddWeaponAdapter("t_ad_two", function() return {ammo = "Second", icon = "C4"} end)

				local def = API.ResolveWeapon(weapon("t_wep_a"))
				expect(def.ammo).to.equal("First")
				expect(def.icon).to.equal("C4")

				API.AddWeaponAdapter("t_ad_one", function() return {ammo = "Replaced"} end)
				expect(API.ResolveWeapon(weapon("t_wep_a")).ammo).to.equal("Replaced")
			end
		},
		{
			name = "an adapter that errors never breaks the resolution; after 5 errors it is disabled with one line, and adding it again re-arms it",
			func = function()
				local runs = 0

				API.AddWeaponAdapter("t_ad_bad", function()
					runs = runs + 1
					error("boom")
				end)

				for _ = 1, 8 do
					expect(API.ResolveWeapon(weapon("t_wep_a")).alt).to.equal("none")
				end

				expect(runs).to.equal(5)
				expect(#lines).to.equal(1)
				expect(string.find(lines[1], "adapter 't_ad_bad' disabled after 5 errors", 1, true) ~= nil).to.beTrue()

				API.AddWeaponAdapter("t_ad_bad", function() return {ammo = "Back"} end)
				expect(API.ResolveWeapon(weapon("t_wep_a")).ammo).to.equal("Back")
			end
		},
		{
			name = "an adapter that answers something that is not a table, or invalid fields, is ignored",
			func = function()
				API.AddWeaponAdapter("t_ad_one", function() return "auto" end)
				API.AddWeaponAdapter("t_ad_two", function() return {fire = "rapid", icon = "Nope"} end)

				local def = API.ResolveWeapon(weapon("t_wep_a", {Primary = {Automatic = false}}))
				expect(def.fire).to.equal("semi")
				expect(def.icon).to.beNil()
			end
		},
		{
			name = "adding an adapter with a bad id or no function is refused",
			func = function()
				expect((API.AddWeaponAdapter("", function() end))).to.beFalse()
				expect((API.AddWeaponAdapter(nil, function() end))).to.beFalse()
				expect((API.AddWeaponAdapter("t_ad_one", "nope"))).to.beFalse()
			end
		},
		{
			name = "defaults: Primary.Automatic gives auto or semi, Primary.Ammo and Secondary.Ammo are the ammo types, a weapon with nothing says nothing special",
			func = function()
				local def = API.ResolveWeapon(weapon("t_wep_a", {Primary = {Automatic = true, Ammo = "Pistol"}, Secondary = {Ammo = "AR2AltFire"}}))
				expect(def.fire).to.equal("auto")
				expect(def.ammo).to.equal("Pistol")
				expect(def.altAmmo).to.equal("AR2AltFire")
				expect(def.alt).to.equal("none")
				expect(def.counter).to.equal("clip")

				expect(API.ResolveWeapon(weapon("t_wep_a", {Primary = {Automatic = false}})).fire).to.equal("semi")

				local bare = API.ResolveWeapon(weapon("t_wep_a"))
				expect(bare.fire).to.beNil()
				expect(bare.ammo).to.beNil()
				expect(bare.altAmmo).to.beNil()
				expect(bare.alt).to.equal("none")
				expect(bare.altShoots).to.beFalse()
			end
		},
		{
			name = "defaults: the string \"none\" as ammo type means no ammo",
			func = function()
				local def = API.ResolveWeapon(weapon("t_wep_a", {Primary = {Ammo = "none"}, Secondary = {Ammo = "none"}}))

				expect(def.ammo).to.beNil()
				expect(def.altAmmo).to.beNil()
			end
		},
		{
			name = "defaults: a secondary ammo that is a grenade type (not the hand grenade one) makes the secondary a grenade launcher, a shot",
			func = function()
				local launcher = API.ResolveWeapon(weapon("t_wep_a", {Secondary = {Ammo = "SMG1_Grenade"}}))
				expect(launcher.alt).to.equal("grenade")
				expect(launcher.altShoots).to.beTrue()

				local hand = API.ResolveWeapon(weapon("t_wep_a", {Secondary = {Ammo = "Grenade"}}))
				expect(hand.alt).to.equal("none")
			end
		},
		{
			name = "defaults: the ammo types come from the weapon's engine ids when it has no Primary/Secondary table",
			func = function()
				local def = API.ResolveWeapon(weapon("t_wep_a", {
					GetPrimaryAmmoType = function() return game.GetAmmoID("SMG1") end,
					GetSecondaryAmmoType = function() return game.GetAmmoID("SMG1_Grenade") end
				}))

				expect(string.lower(def.ammo)).to.equal("smg1")
				expect(string.lower(def.altAmmo)).to.equal("smg1_grenade")
				expect(def.alt).to.equal("grenade")

				local none = API.ResolveWeapon(weapon("t_wep_a", {
					GetPrimaryAmmoType = function() return -1 end,
					GetSecondaryAmmoType = function() return -1 end
				}))
				expect(none.ammo).to.beNil()
				expect(none.altAmmo).to.beNil()
			end
		},
		{
			name = "defaults: CustomAmmoDisplay (the table holohud2 reads): Draw = false hides the counter, the numbers are kept as display",
			func = function()
				local hidden = API.ResolveWeapon(weapon("t_wep_a", {CustomAmmoDisplay = function() return {Draw = false} end}))
				expect(hidden.counter).to.equal("none")
				expect(hidden.display).to.beNil()

				local shown = API.ResolveWeapon(weapon("t_wep_a", {CustomAmmoDisplay = function()
					return {Draw = true, PrimaryClip = 12, PrimaryAmmo = 90, SecondaryAmmo = 3, SecondaryClip = 1, Junk = "x"}
				end}))
				expect(shown.counter).to.equal("clip")
				expect(shown.display.clip).to.equal(12)
				expect(shown.display.ammo).to.equal(90)
				expect(shown.display.altAmmo).to.equal(3)
				expect(shown.display.altClip).to.equal(1)
				expect(shown.display.Junk).to.beNil()

				-- the registry says more than the default does
				API.RegisterWeapon("t_wep_a", {counter = "clip"})
				local entry = API.ResolveWeapon(weapon("t_wep_a", {CustomAmmoDisplay = function() return {Draw = false} end}))
				expect(entry.counter).to.equal("clip")
			end
		},
		{
			name = "a CustomAmmoDisplay that errors or answers junk is ignored, and 5 errors disable it with one line",
			func = function()
				local runs = 0
				local gun = weapon("t_wep_a", {CustomAmmoDisplay = function()
					runs = runs + 1
					error("boom")
				end})

				for _ = 1, 8 do
					expect(API.ResolveWeapon(gun).counter).to.equal("clip")
				end

				expect(runs).to.equal(5)
				expect(#lines).to.equal(1)

				local junk = API.ResolveWeapon(weapon("t_wep_a", {CustomAmmoDisplay = function() return 12 end}))
				expect(junk.counter).to.equal("clip")
				expect(junk.display).to.beNil()
			end
		},
		{
			name = "a fire function is called with the weapon and decides the mode; an invalid answer or an error falls back to the default",
			func = function()
				local gun = weapon("t_wep_a", {Primary = {Automatic = true}})
				local mode = "burst"

				API.RegisterWeapon("t_wep_a", {fire = function(wep)
					expect(wep).to.equal(gun)

					return mode
				end})

				expect(API.ResolveWeapon(gun).fire).to.equal("burst")
				mode = "semi"
				expect(API.ResolveWeapon(gun).fire).to.equal("semi")
				mode = "rapid"
				expect(API.ResolveWeapon(gun).fire).to.equal("auto") -- junk: the default

				API.RegisterWeapon("t_wep_a", {fire = function() error("boom") end})
				expect(API.ResolveWeapon(gun).fire).to.equal("auto")
				expect(#lines).to.equal(0) -- one error is not a disaster
			end
		},
		{
			name = "a counter function stays a function in the resolved description (the HUD calls it)",
			func = function()
				local counter = function() return "x" end
				API.RegisterWeapon("t_wep_a", {counter = counter})

				expect(API.ResolveWeapon(weapon("t_wep_a")).counter).to.equal(counter)
			end
		},
		{
			name = "ResolveWeapon with the second argument true gives only what is declared (registry, GryHUD, adapters): no defaults",
			func = function()
				local gun = weapon("t_wep_a", {Primary = {Automatic = true, Ammo = "Pistol"}})
				local def = API.ResolveWeapon(gun, true)

				expect(def.fire).to.beNil()
				expect(def.ammo).to.beNil()
				expect(def.alt).to.beNil()

				API.RegisterWeapon("t_wep_a", {alt = "zoom"})
				expect(API.ResolveWeapon(gun, true).alt).to.equal("zoom")
			end
		},
		{
			name = "ResolveWeapon takes a class name too (declared things only, no entity to read), and nil or an invalid entity give nil",
			func = function()
				API.RegisterWeapon("t_wep_a", {alt = "doublebarrel"})
				local def = API.ResolveWeapon("t_wep_a")

				expect(def.alt).to.equal("doublebarrel")
				expect(def.altShoots).to.beTrue()
				expect(API.ResolveWeapon("t_wep_b").alt).to.equal("none")
				expect(API.ResolveWeapon(nil)).to.beNil()
				expect(API.ResolveWeapon(NULL)).to.beNil()
				expect(API.ResolveWeapon(12)).to.beNil()
			end
		},
		{
			name = "a class name reads GryHUD, Primary and Secondary of the scripted weapon (weapons.GetStored)",
			func = function()
				stored.t_wep_a = {GryHUD = {alt = "shoot", altAmmo = "Gauss"}, Primary = {Automatic = true}}
				local def = API.ResolveWeapon("t_wep_a")

				expect(def.alt).to.equal("shoot")
				expect(def.altAmmo).to.equal("Gauss")
				expect(def.altShoots).to.beTrue()
				expect(def.fire).to.equal("auto")
			end
		},
		{
			name = "altShoots follows the kind of secondary fire unless the definition says otherwise",
			func = function()
				local expected = {none = false, zoom = false, melee = false, grenade = true, energy = true, doublebarrel = true, shoot = true, throwlow = true}

				for alt, shoots in pairs(expected) do
					API.RegisterWeapon("t_wep_a", {alt = alt})
					expect(API.ResolveWeapon(weapon("t_wep_a")).altShoots).to.equal(shoots)
				end

				API.RegisterWeapon("t_wep_a", {alt = "grenade", altShoots = false})
				expect(API.ResolveWeapon(weapon("t_wep_a")).altShoots).to.beFalse()
			end
		},
		{
			name = "the Half-Life 2 SMG: the secondary is a grenade launcher with SMG1_Grenade, automatic",
			func = function()
				local def = API.ResolveWeapon("weapon_smg1")

				expect(def.fire).to.equal("auto")
				expect(def.alt).to.equal("grenade")
				expect(def.altAmmo).to.equal("SMG1_Grenade")
				expect(def.altShoots).to.beTrue()
				expect(def.altLabel).to.equal("40mm")
				expect(def.altIcon).to.equal("Grenade")
			end
		},
		{
			name = "the Half-Life 2 AR2: the secondary is the energy ball (AR2AltFire), not the grenades",
			func = function()
				local def = API.ResolveWeapon("weapon_ar2")

				expect(def.fire).to.equal("auto")
				expect(def.alt).to.equal("energy")
				expect(def.altAmmo).to.equal("AR2AltFire")
				expect(def.altShoots).to.beTrue()
				expect(isstring(def.altLabel)).to.beTrue()
				expect(def.altLabel ~= "40mm").to.beTrue()
				expect(isstring(def.altIcon)).to.beTrue()
			end
		},
		{
			name = "the Half-Life 2 shotgun: the secondary is the double barrel (primary ammo), no secondary counter",
			func = function()
				local def = API.ResolveWeapon("weapon_shotgun")

				expect(def.alt).to.equal("doublebarrel")
				expect(def.altAmmo).to.beNil()
				expect(def.altShoots).to.beTrue()
				expect(def.slotIcon).to.equal("Shotgun")
			end
		},
		{
			name = "the Half-Life 2 crossbow: the secondary is a zoom, no counter and no shot",
			func = function()
				local def = API.ResolveWeapon("weapon_crossbow")

				expect(def.alt).to.equal("zoom")
				expect(def.altAmmo).to.beNil()
				expect(def.altShoots).to.beFalse()
				expect(def.fire).to.equal("semi")
			end
		},
		{
			name = "the Half-Life 2 frag grenade: the secondary is the low throw, a shot while there is a grenade, hand grenade icon",
			func = function()
				local def = API.ResolveWeapon("weapon_frag")

				expect(def.alt).to.equal("throwlow")
				expect(def.altShoots).to.beTrue()
				expect(def.slotIcon).to.equal("HandGrenade")
			end
		},
		{
			name = "the Half-Life 2 pistol and .357 are semi-automatic and have no secondary; the RPG has none either",
			func = function()
				for _, class in ipairs({"weapon_pistol", "weapon_357"}) do
					local def = API.ResolveWeapon(class)

					expect(def.fire).to.equal("semi")
					expect(def.alt).to.equal("none")
					expect(def.altAmmo).to.beNil()
					expect(def.altShoots).to.beFalse()
				end

				local rpg = API.ResolveWeapon("weapon_rpg")
				expect(rpg.alt).to.equal("none")
				expect(rpg.slotIcon).to.equal("Missle")
			end
		},
		{
			name = "the gravity gun, the crowbar and the stun baton have no fire mode (no gun icon), and no secondary shot",
			func = function()
				for _, class in ipairs({"weapon_physcannon", "weapon_crowbar", "weapon_stunstick"}) do
					local def = API.ResolveWeapon(class)

					expect(def.fire).to.equal("none")
					expect(def.altShoots).to.beFalse()
					expect(def.altAmmo).to.beNil()
				end

				expect(API.ResolveWeapon("weapon_physcannon").alt).to.equal("none")
				expect(API.ResolveWeapon("weapon_crowbar").alt).to.equal("melee")
				expect(API.ResolveWeapon("weapon_stunstick").alt).to.equal("melee")
			end
		},
		{
			name = "the other stock weapons that had an icon of their own keep it (flechette gun, SLAM, medkit, physgun, fists, tool gun, camera, bugbait)",
			func = function()
				local icons = {
					weapon_flechettegun = "Auto", weapon_slam = "Mine", weapon_medkit = "Repairkit", weapon_physgun = "NoGun",
					weapon_fists = "NoGun", gmod_tool = "NoGun", gmod_camera = "NoGun", weapon_bugbait = "NoGun"
				}

				for class, label in pairs(icons) do
					local def = API.ResolveWeapon(class)

					expect(def ~= nil).to.beTrue()
					expect(def.icon or def.slotIcon or ({auto = "Auto", none = "NoGun"})[def.fire]).to.equal(label)
				end
			end
		}
	}
}
