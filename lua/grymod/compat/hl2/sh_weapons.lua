-- The stock Half-Life 2 and Garry's Mod weapons, described as DATA through the public weapon registry (GryMod.API.RegisterWeapon),
-- exactly as an addon would describe its own weapons. They are written in C++ (no Primary table to read), so the HUD learns what
-- they are here: the fire mode, the ammo, what the secondary fire is and what the HUD shows for it.
-- (docs/api.md, "Weapons". Nothing else in the HUD knows these class names.)

local API = GryMod.API

local function register(class, def)
	local ok, reason = API.RegisterWeapon(class, def)

	if not ok then
		ErrorNoHalt("GryMod: stock weapon '" .. class .. "' not registered: " .. tostring(reason) .. "\n")
	end
end

-- The SMG: the secondary fire is a 40 mm grenade (the SMG1_Grenade ammo), which the HUD shows in the grenade slot.
register("weapon_smg1", {fire = "auto", ammo = "SMG1", alt = "grenade", altAmmo = "SMG1_Grenade", altShoots = true, altLabel = "40mm", altIcon = "Grenade", listIcon = "SMG"})

-- The AR2: the secondary fire is the energy ball (the AR2AltFire ammo), shown in the grenade slot; no hand grenades there.
register("weapon_ar2", {fire = "auto", ammo = "AR2", alt = "energy", altAmmo = "AR2AltFire", altShoots = true, altLabel = "Energy", altIcon = "Grenade", listIcon = "SCAR"})

-- The shotgun: the secondary fire is the double barrel, taken from the magazine: no secondary counter.
register("weapon_shotgun", {fire = "semi", ammo = "Buckshot", alt = "doublebarrel", altShoots = true, slotIcon = "Shotgun", listIcon = "Shotgun"})

-- The crossbow: the secondary fire is a zoom, no counter. Its zoom has no scope picture of its own in Garry's Mod: the crosshair stays, and it is the thin cross
-- (7 of the movie's 13) while zoomed, since this is a precision weapon (zoomCrosshair).
register("weapon_crossbow", {fire = "semi", ammo = "XBowBolt", alt = "zoom", altShoots = false, zoomCrosshair = 7, listIcon = "DSG1"})

-- The frag grenade: the secondary fire is the low throw, while there is a grenade. Its icon in the grenade slot is the explosive one
-- (the only hand grenade of Half-Life 2; the other kinds of the HUD movie are for the weapons of other addons).
register("weapon_frag", {ammo = "Grenade", alt = "throwlow", altShoots = true, slotIcon = "HandGrenade", grenade = "explosivegrenade", listIcon = "Grenade_Explosive"})

register("weapon_pistol", {fire = "semi", ammo = "Pistol", alt = "none", listIcon = "SOCOM"})
-- (the list has no revolver: the 357 takes the pistol's silhouette, the closest handgun)
register("weapon_357", {fire = "semi", ammo = "357", alt = "none", listIcon = "SOCOM"})
-- (the RPG, like the fists, shows no crosshair in the original game: crosshair = false)
register("weapon_rpg", {ammo = "RPG_Round", alt = "none", slotIcon = "Missle", crosshair = false, listIcon = "LAW"})

-- The melee weapons and the gravity gun: no gun icon. The secondary of the crowbar and of the stun baton is another swing, and so is the right click of the fists (the other
-- hand): altShoots, because a blow ends the camouflage like a shot (a swing that is not declared an attack never does).
register("weapon_physcannon", {fire = "none", alt = "none"})
register("weapon_crowbar", {fire = "none", alt = "melee", altShoots = true, listIcon = "Fists"})
register("weapon_stunstick", {fire = "none", alt = "melee", altShoots = true, listIcon = "Fists"})

-- The list of weapons shows a silhouette (listIcon) only where the movie has a look-alike. The gravity gun, the physics gun, the tool gun,
-- the camera and the bug bait have none: the list writes their name instead of drawing a wrong picture.

-- Garry's Mod's own weapons, which had an icon of their own.
register("weapon_flechettegun", {fire = "auto"})
register("weapon_slam", {slotIcon = "Mine", listIcon = "AVMine"})
register("weapon_medkit", {slotIcon = "Repairkit", listIcon = "RepairKit"})
register("weapon_physgun", {fire = "none"})
register("weapon_fists", {fire = "none", alt = "melee", altShoots = true, crosshair = false, listIcon = "Fists"})
register("gmod_tool", {fire = "none"})
register("gmod_camera", {fire = "none"})
register("weapon_bugbait", {fire = "none"})
