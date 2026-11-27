# Weapons

This guide is for the addons that add weapons and want GryMod's HUD to show them properly: the fire-mode icon of the weapon
slot, the grenade slot, and the camouflage that ends on a right click that really shoots. It builds on [api.md](api.md) (the
reference, with the table of fields); here you find what the HUD does with each field, complete examples, and the limits that
exist today.

The HUD never knows a weapon by its class name. It asks the weapon registry what the weapon is. The stock Half-Life 2 and Garry's Mod
weapons are in the registry as plain data (`lua/grymod/compat/hl2/sh_weapons.lua`), registered with the same call your addon uses.

Everything below is checked by running it in a game with GryMod loaded.

## The camouflage and the attacks that are not bullets

The camouflage ends when the player attacks. Every **bullet** is seen by the server (`EntityFireBullets`), so the weapons that fire bullets, TFA, ArcCW, ARC9, M9K, CW 2.0,
FA:S and your own, end it whatever their rules. A **left click** is judged on the client from the numbers of the weapon (it fires when the weapon may fire). A **right click**
is not guessed: it counts when the weapon is in the registry with `altShoots` (the stock weapons), or when the weapon says so with
`GryMod.API.ReportAttack(ply, true)` (a knife's stab, a launcher, a grenade: [api.md](api.md#attacks-that-end-the-camouflage)). TFA is done: GryMod listens to its hooks (see
[compat.md](compat.md)); for the other bases, call `ReportAttack` from your own patch.

## Three ways to describe a weapon

A description is a table of optional fields (the list is in [api.md](api.md#describe-a-weapon)). A field you leave out is read
from the weapon itself. For each field, the first of these that says something wins:

1. **the registry**: `GryMod.API.RegisterWeapon(class, def)`, for the class of the weapon or the nearest base class that has an
   entry (`SWEP.Base`). Only one entry is used: an entry is never completed with fields of its base class's entry;
2. **the weapon itself**: its `SWEP.GryHUD` table;
3. **the adapters**: functions that read a weapon base's own fields (below);
4. **the defaults**: `Primary.Automatic`, the ammo of the weapon, a secondary ammo that is a grenade type, `CustomAmmoDisplay`.

### From the weapon (no call to GryMod)

The simplest, and it works whether GryMod is installed or not: a table in the weapon's file.

```lua
-- weapon file (shared): lua/weapons/weapon_my_addon_plasma.lua
SWEP.GryHUD = {
	fire = "burst", burst = 3,
	alt = "energy", altAmmo = "AR2AltFire", altLabel = "PLASMA", altIcon = "Gauss",
	icon = "Gauss",
}
```

### From the registry

For a weapon you cannot edit, or to describe several classes in one place. Do it from the `Initialize` hook (the autorun files of
all addons run in alphabetical order, so `GRYMOD_INSTALLED` can still be `nil` before it) in a file both realms run:

```lua
-- shared: lua/autorun/my_addon_gryhud.lua
hook.Add("Initialize", "my_addon_gryhud_weapons", function()
	if not (GRYMOD_INSTALLED and GryMod.API and GryMod.API.Has("weapons")) then
		return -- GryMod is not installed: nothing to do, and nothing breaks
	end

	local ok, reason = GryMod.API.RegisterWeapon("weapon_my_addon_rifle", {
		fire = "auto",
		alt = "grenade", altAmmo = "SMG1_Grenade", altLabel = "40mm", altIcon = "Grenade",
	})

	if not ok then
		print("GryMod refused my rifle: " .. reason)
	end
end)
```

`RegisterWeapon` returns `true`, or `false` and a reason (`invalid fire: rapid`). An invalid value refuses the whole definition and
keeps the previous one. Fields it does not know are ignored. Registering a class again replaces its entry.

In the examples that follow, the guard (`if GRYMOD_INSTALLED and ...`) stands for "inside that `Initialize` function".

## What the HUD does with each field

| Field | What the HUD does with it |
| --- | --- |
| `icon` | the icon of the weapon slot (it wins over everything below) |
| `slotIcon` | the stock icon of the weapon slot: `HandGrenade`, `Missle`, `Shotgun`, `Mine`, `Repairkit`... |
| `fire` | the icon of the weapon slot: `auto` gives `Auto`, `semi` gives `Single`, `burst` gives `Burst`, `none` gives `NoGun`. A function gets the weapon and returns one of the four words |
| `alt` = `"grenade"` or `"energy"`, with an `altAmmo` the game knows | the grenade slot counts `altAmmo` and shows `altIcon` (`Grenade`, the 40 mm icon, by default) instead of the hand grenades |
| `altShoots` | the camouflage ends on a right click that really shoots (the player's option `gry_cloak_altfire`) |
| `alt` (any value) | with `altShoots`, how the HUD knows if the right click shoots now (below) |
| `alt` = `"zoom"` | the right click zooms and the weapon owns that zoom: when the binoculars open while it is zoomed, the zoom is ended (so that it does not come back, as a jump, when they close; the player's option `gry_zoom_cancel_weapon`). The server sends one right click to the weapon to toggle it off, so use it only for a weapon that zooms on its right click |
| `heat` | a function returning 0 to 1: the heat bar above the weapon icon (`gry_hud_overheat` turns it off). A weapon without it shows no bar |
| `grenade` | the kind of hand grenade of the grenade slot: `explosivegrenade` (default), `flashbang`, `smokegrenade`, `empgrenade`. The slot shows that icon and counts the weapon's own primary ammo; the icon blinks when you switch to a weapon of another kind |
| `listIcon` | the silhouette of the weapon in the weapon list (below). Without it: the kind of the weapon's `grenade`, else the list writes the weapon's name |
| `crosshair` = `false` | the HUD draws no crosshair while the weapon is in hand (the fists and the RPG). `true` or no field: the crosshair is shown |
| `crosshair` = a number 1 to 13 | the weapon shows that crosshair of the HUD movie instead of the player's style (the player can turn that off with `gry_hud_crosshair_weapon`) |
| `altLabel` | handed to the HUD (`GryMod.FlashHUD.LauncherLookFor(wep)`), **not drawn**: the movie has no text field for it |
| `ammo`, `counter`, `burst` | resolved and returned by `ResolveWeapon`, **not read by the HUD**: the counter shows the weapon's engine ammo (`Clip1`, `GetMaxClip1`, the reserve of its primary ammo type) |

When the HUD asks whether a right click shoots now (the camouflage), it uses `alt` and the engine's numbers:

| `alt` | The right click shoots when |
| --- | --- |
| `"grenade"`, `"energy"` | the secondary ammo reserve is above 0 |
| `"doublebarrel"` | the magazine has at least one round |
| `"throwlow"` | the primary reserve is above 0 (a thrown weapon) |
| `"shoot"` | the secondary ammo reserve is above 0, or always when `altAmmo` is not given |
| `"melee"` | always (a blow), but only with `altShoots = true`: the default of `"melee"` is false, a swing that is not declared an attack never ends the camouflage |
| `"zoom"`, `"none"` | never |

`altShoots` itself defaults to true for `grenade`, `energy`, `doublebarrel`, `shoot` and `throwlow`. A melee weapon whose right click is another blow (the stock fists; the stock crowbar and stun baton have no right click at all) says `alt = "melee", altShoots = true`.

The icon keys are the labels of the HUD movie: `Single`, `Burst`, `Auto`, `Grenade`, `Shotgun`, `Mine`, `Repairkit`, `Missle`,
`NoGun`, `HandGrenade`, and twelve that no stock weapon uses and are yours to choose: `Incendiary`, `Tranquilizer`, `infinity`,
`Narrow`, `Moac`, `Moar`, `TACCannon`, `C4`, `Gauss`, `Gunner`, `Mounted`, `Claymore`. `GryMod.API.WeaponIcons` lists them all.

## Recipes

### An automatic rifle with a grenade launcher

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_launcher", {
		fire = "auto",
		ammo = "SMG1",
		alt = "grenade",
		altAmmo = "SMG1_Grenade",
		altLabel = "40mm",
	})
end
```

The weapon slot shows `Auto`; the grenade slot shows the 40 mm icon and the number of `SMG1_Grenade` the player has; a right
click with at least one of them ends the camouflage.

### A fire mode that the player switches

`fire` may be a function. It gets the weapon (an entity) and returns `"auto"`, `"semi"`, `"burst"` or `"none"`. It runs under
`SafeCall`: an error is caught, and 5 in a row disable it.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_rifle", {
		fire = function(wep)
			return wep:GetNW2Bool("MyAddonBurst") and "burst" or "auto"
		end,
		burst = 3,
	})
end
```

### A melee weapon

`fire = "none"` gives the icon with no gun. `alt = "melee"` says the right click is another swing: no grenade slot, the camouflage
does not end on it.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_blade", {
		fire = "none",
		alt = "melee",
	})
end
```

### A weapon with a zoom

A right click that zooms is not a shot: `altShoots = false` (the default for `"zoom"`), no secondary counter.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_sniper", {
		fire = "semi",
		alt = "zoom",
		altShoots = false,
	})
end
```

With `alt = "zoom"` the HUD also ends the weapon's zoom when the binoculars of the suit open (see the table above).

### A grenade of another kind

The grenade slot has four icons: the explosive grenade (Half-Life 2's), the flash grenade, the smoke grenade and the EMP grenade.
A weapon that throws one of the last three says so with `grenade`. While it is in hand the slot shows that icon and counts the
weapon's own ammo; the icon blinks when the player switches from one kind to another.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_flashbang", {
		ammo = "MyAddonFlashbang",
		slotIcon = "HandGrenade",
		grenade = "flashbang",
	})
end
```

### A weapon that overheats

The HUD has a heat bar above the weapon icon. It is shown only for a weapon that says how hot it is: `heat` is a function that gets the
weapon (an entity) and returns a number from 0 (cold, the bar is hidden) to 1 (overheated, the bar is full). The HUD asks it at each
frame while the weapon is in hand, under `SafeCall` (an error is caught, and 5 in a row disable it). The Half-Life 2 weapons have
no heat, so they never show the bar. Whatever your weapon keeps its heat in works: a networked variable, a field...

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_plasma", {
		fire = "auto",
		heat = function(wep)
			return wep:GetNW2Float("MyAddonHeat") / 100
		end,
	})
end
```

The heat of a weapon base (ARC9, ArcCW...) is kept in that base's own fields: read its source for the getter and give it here (or
from an adapter, see api.md). GryMod does not read them itself. A client hook reports the bar:
`GryMod_WeaponHeat(ply, wep, percent)` runs each time the bar moves (`percent` is 0 when it is hidden). Its return value is ignored.

### The weapon list

When the player changes the weapon in hand, the HUD shows the list of the player's weapons at the bottom right, as the original game does: up
to five rows (more weapons give a window around the one in hand), the lowest slot on top, the weapon in hand on a plate. It fades out after
three seconds. The player can turn it off with `gry_hud_weaponlist` (a line of the options menu). The Half-Life 2 weapon selector (the letter at
the top right) is not touched: it keeps working and stays on screen next to the list.

Each row shows a silhouette, chosen by `listIcon`. The silhouettes are the 25 of the original game (`SOCOM`, `SMG`, `Shotgun`, `SCAR`, `FY71`,
`Hurricane`, `LAW`, `TACGun`, `GaussRifle`, `DSG1`, `Grenade_Explosive`, `Grenade_Flashbang`, `Grenade_Smoke`, `C4`, `LockpickKit`, `RadarKit`,
`RepairKit`, `AVMine`, `Claymore`, `MOARAttach`, `AlienMount`, `Grenade_EMP`, `NightVision`, `Binoculars`, `Fists`; `GryMod.API.WeaponListIcons`
lists them). A weapon with no `listIcon` gets the grenade silhouette of its `grenade` kind if it has one; else its row shows the name of the
weapon in plain letters. GryMod never guesses a picture.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_rifle", {
		fire = "auto",
		listIcon = "SCAR",
	})
end
```

The client hook `GryMod_WeaponListShown(ply, wep)` runs each time the list is shown (the return value is ignored). The stock Half-Life 2
weapons are mapped as data in `lua/grymod/compat/hl2/sh_weapons.lua`: the pistol and the .357 `SOCOM`, the SMG `SMG`, the AR2 `SCAR`, the shotgun
`Shotgun`, the RPG `LAW`, the crossbow `DSG1`, the grenade `Grenade_Explosive`, the crowbar, the stun baton and the fists `Fists`, the SLAM
`AVMine`, the medkit `RepairKit`. The gravity gun, the physics gun, the tool gun, the camera and the bug bait show their name.

### The weapon selector setting (the mouse wheel)

`gry_weapon_selector` is a client setting (a choice of three lines in the options menu, HUD and controls page, Aim and prompts tab), and it is 0 by default:

| Value | What the wheel does |
| --- | --- |
| 0 | The game's own selector, as it always was. Nothing of GryMod runs for it. |
| 1 | Wheel only: a notch changes the weapon at once (down is the next weapon, up the previous one, in the order of the slots), with no click. The weapon list above shows by itself, as it does for any change. |
| 2 | Wheel, then click: the wheel walks the weapon list above (the selection is on the plate) and the left click confirms. When the list cannot show (the HUD or the list is off) the wheel works as in position 1. |

It is one `PlayerBindPress` hook and nothing runs between two binds. The wheel is left to the game when the attack key is down (the physgun
moves the prop with it), in a vehicle, with no weapon in hand, and while the zoom of the binoculars or of the suit is up. The weapon keys
(`slot1`...) and the last weapon key still open the game's own selector in every position. A weapon with no ammo is skipped, as the game's selector does.

With the camouflage, the click that confirms a selection (position 2) is taken, so the weapon in hand does not fire, and it never counts as a shot that
ends the camouflage, with the option "Selector click keeps the camouflage" on or off. In positions 1 and 2 the game's selector is never open, so a click
after the wheel is a plain click. In position 2 the client hook `GryMod_WeaponListShown(ply, wep)` runs at each notch, with `wep` the weapon the
wheel is on.

### A weapon that draws its own crosshair, or none

`crosshair = false` keeps GryMod's crosshair off while the weapon is in hand: for a weapon with no aiming point (a melee weapon, a
launcher with its own sight) or one that shows its own. It only hides GryMod's crosshair; a weapon that draws its own through
`DrawCrosshair = false` is already left alone.

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.RegisterWeapon("weapon_my_addon_launcher_sight", {
		fire = "semi",
		crosshair = false,
	})
end
```

A weapon that wants one of the 13 crosshairs of the HUD movie gives its number instead (`crosshair = 12`). The three last ones (11, 12, 13) are the ones the
original game forces for its special weapons (a cannon, an overheating weapon...), and no Half-Life 2 weapon uses them. The player's own
style is used again when he switches off "Weapons choose their crosshair" (`gry_hud_crosshair_weapon`).

The weapon can also say it itself, with no call to GryMod: `SWEP.GryHUD = {crosshair = false}`. The HUD asks by the class name of
the weapon in hand, so the adapters (which only see weapon entities) cannot decide it: use the registry or `SWEP.GryHUD`.

### Read it back

```lua
-- shared
local def = GryMod.API.ResolveWeapon("weapon_my_addon_launcher")

if def then
	print(def.fire, def.alt, def.altAmmo, def.altShoots)
end

print(GryMod.API.WeaponValue("weapon_my_addon_launcher", "altLabel"))
print(GryMod.API.GetWeapon("weapon_my_addon_launcher").fire)
```

- `GetWeapon(class)` gives a copy of the registry entry only (no base class, no defaults).
- `ResolveWeapon(wep)` gives what the HUD uses: the final description, with the defaults. `wep` is a weapon entity or a class name;
  from a class name, what only an entity can tell (a `fire` function, the adapters, `CustomAmmoDisplay`) is left out.
  `ResolveWeapon(wep, true)` gives only what is declared.
- `WeaponValue(wep, field)` gives one field without building a table.

### Remove it

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	print(GryMod.API.UnregisterWeapon("weapon_my_addon_launcher"))   -- true when there was an entry
end
```

## The stock weapons (data, nothing special)

The 19 classes registered in `lua/grymod/compat/hl2/sh_weapons.lua`:

| Class | What it says |
| --- | --- |
| `weapon_smg1` | auto, `SMG1`; secondary: a grenade (`SMG1_Grenade`, `40mm`) that shoots |
| `weapon_ar2` | auto, `AR2`; secondary: the energy ball (`AR2AltFire`, `Energy`) that shoots, shown with the grenade icon |
| `weapon_shotgun` | semi, `Buckshot`; secondary: the double barrel (shoots, no counter); slot icon `Shotgun` |
| `weapon_crossbow` | semi, `XBowBolt`; secondary: a zoom (not a shot) |
| `weapon_frag` | `Grenade`; secondary: the low throw (shoots); slot icon `HandGrenade` |
| `weapon_pistol`, `weapon_357` | semi, no secondary; list silhouette `SOCOM` |
| `weapon_rpg` | `RPG_Round`, no secondary; slot icon `Missle`; no crosshair |
| `weapon_physcannon` | no gun icon |
| `weapon_crowbar`, `weapon_stunstick` | no gun icon; secondary: a swing |
| `weapon_flechettegun` | auto |
| `weapon_slam`, `weapon_medkit` | slot icons `Mine`, `Repairkit` |
| `weapon_physgun`, `gmod_tool`, `gmod_camera`, `weapon_bugbait` | no gun icon |
| `weapon_fists` | no gun icon; no crosshair |

To change one for your game, register the class again with your own definition: it replaces the stock one.

## Weapon bases

Weapon bases keep their fire mode in their own fields. Two mechanisms exist, and they are not the same thing.

### What exists today: fire-mode resolvers (icon only)

The HUD reads the fire-mode icon of these bases already, through resolvers written from their source code: ARC9, ArcCW, TFA, M9K
(`bobs_gun_base`, `bobs_scoped_base`, `bobs_shotty_base`), CW 2.0 and FA:S 2.0. They are one file each in `lua/grymod/compat/weapons/` (see
[compat.md](compat.md)). They give the icon of the weapon slot only: nothing about the secondary fire.

A resolver is consulted only when nothing declares the icon (`icon`, `slotIcon` or `fire`, in the registry, in `SWEP.GryHUD` or from an adapter).
You can add one for your own base:

```lua
-- client
local remove = GryMod.FlashHUD.AddFireModeResolver(function(wep)
	if wep.Base ~= "my_addon_base" or not wep.GetFireModeName then
		return nil -- not my base: the next resolver decides
	end

	return wep:GetFireModeName() == "burst" and "Burst" or "Auto"
end, "my_addon.fire_mode") -- the key is optional: the same key replaces the earlier resolver, so a file that is loaded twice does not pile it up

-- later, to take it away:
remove()
```

A base that keeps its mode as text ("auto", "3burst", "Safe") can use `GryMod.FlashHUD.FireModeFromName(text)`, which gives `"Burst"`, `"Auto"` or
`"Single"`.

It returns one of the icon keys, or `nil`. It runs under `pcall`. `GryMod.FlashHUD` is the HUD module and is not part of the
versioned `GryMod.API`: it may change without a version bump.

### What is not written yet: registry adapters for ArcCW, TFA, M9K and CW 2.0

`GryMod.API.AddWeaponAdapter(id, fn)` exists: `fn(wep)` returns a partial definition (or nothing), asked through `SafeCall` in the
order the adapters were added. **No adapter is registered today.** The adapters for ArcCW (`SWEP.Firemodes`, the underbarrel
launcher), TFA (`SWEP.FireModes`, `AltAttack`), M9K (`SelectiveFire`) and CW 2.0 (`FireModes`), which would also tell the secondary
fire, are not written yet. The sources of their conventions are kept for when they are.

You can write one for your own base today:

```lua
-- shared
if GRYMOD_INSTALLED and GryMod.API.Has("weapons") then
	GryMod.API.AddWeaponAdapter("my_addon_base", function(wep)
		if wep.Base ~= "my_addon_base" then
			return nil -- not my base: no opinion
		end

		return {
			fire = wep.Primary.Automatic and "auto" or "semi",
			alt = wep.HasLauncher and "grenade" or "none",
			altAmmo = wep.HasLauncher and "SMG1_Grenade" or nil,
		}
	end)
end
```

And take it away with `GryMod.API.RemoveWeaponAdapter("my_addon_base")`.

An adapter is only asked about a weapon **entity**. The camouflage's right-click rule asks about a class name, so an adapter
cannot make a right click count as a shot: use the registry or `SWEP.GryHUD` for `alt` and `altShoots`.

## Known limits

All of these are true today.

- `altLabel` is not drawn. The movie has no text field for it.
- `ammo`, `counter` and `burst` are resolved but not read by the HUD: the counter shows the weapon's engine ammo.
- The AR2's energy ball uses the grenade icon: the movie has no icon for it. Pick one of the 22 with `altIcon`.
- `alt` kinds other than `"grenade"` and `"energy"` show nothing in the grenade slot.
- No adapter for the third-party bases (see above); only their fire-mode icon is read.
