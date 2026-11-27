# Weapons reference

This page documents the weapon registry of `GryMod.API`: the functions that describe a weapon to the HUD and the suit, the adapters that describe a whole weapon base, and the lists of names that a definition may use. The registry lives in `lua/grymod/sh_api_weapons.lua` and runs in both realms. For recipes and for what each field looks like on screen, see the guide [weapons.md](../weapons.md).

`GryMod.API.Has("weapons")` is true when the registry is loaded. The registry is not networked: a file that registers weapons must run in both realms, and each realm keeps its own copy. The HUD reads it on the client, and the server reads the `alt` field for the weapon zoom.

## How a weapon is resolved

The HUD never knows a weapon by its class name. For each field of a definition it takes the first layer that has a valid value, in this order:

1. The registry entry of the weapon class. When the class has no entry, the entry of the nearest base class that has one (`SWEP.Base`, followed for at most 8 levels). Only one entry is used: an entry of the class is never completed with fields of its base class.
2. The `SWEP.GryHUD` table of the weapon.
3. The adapters, in the order they were added. Only for a weapon entity.
4. The defaults read from the weapon (listed in the field table of `RegisterWeapon`).

A value that is invalid in `SWEP.GryHUD` or in an adapter result counts as no value, and the next layer decides. The same lookup serves the registry functions below, so a field resolves the same way whichever function asks.

## Registering a weapon

### GryMod.API.RegisterWeapon(class, def)

Shared. Registers the definition of a weapon class, or replaces the one that exists.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `class` | string | The class of the weapon (`weapon_smg1`). It can also be a base class. A string of at least 1 character. | no |
| `def` | table | The definition: a table of the fields listed below. Fields that are absent or `nil` are skipped. Names that are not in the list are ignored. | no |

Returns `true` when the definition is registered. Returns `false` and a reason string otherwise: `"invalid class"`, `"the definition must be a table"`, or `"invalid <field>: <value>"` for the first invalid field, in the order of the table below. An invalid value refuses the whole definition, and the previous entry of the class stays in place.

The entry replaces the previous one as a whole. It is a copy: changing `def` afterwards changes nothing. Registering also re-arms the `fire`, `counter` and `heat` functions of the class if they were switched off after errors. Functions given for `fire` and `heat` run under `GryMod.API.SafeCall`, and five errors in a row switch one off until the class is registered again.

Fields a definition accepts:

| Field | Accepted values | Default when no layer sets it | What it changes |
| --- | --- | --- | --- |
| `fire` | `"auto"`, `"semi"`, `"burst"`, `"none"`, or a `function(wep)` that returns one of the four | `"auto"` or `"semi"` from `Primary.Automatic` of the SWEP when that field exists, else none | The fire mode icon of the weapon slot: `auto` gives `Auto`, `semi` gives `Single`, `burst` gives `Burst`, `none` gives `NoGun`. With no value, the fire mode resolvers of the weapon bases are asked next, and the icon is `Single` when none answers (`Shotgun` for a weapon the HUD recognises as a shotgun). A function is called for a weapon entity only, and an answer that is not one of the four modes counts as no value. |
| `burst` | integer from 2 to 32 | none | Nothing in the HUD. `ResolveWeapon` returns it. |
| `ammo` | string of 1 to 64 characters, an ammo type name | The engine ammo type of the weapon, else `Primary.Ammo` of the SWEP (ignored when it is empty or `"none"`) | Nothing in the HUD, which reads the engine ammo of the weapon directly. `ResolveWeapon` returns it. |
| `counter` | `"clip"`, `"none"`, or a function | `"none"` when `CustomAmmoDisplay` returns a table with `Draw = false`, else `"clip"` | Nothing in the HUD. `ResolveWeapon` returns it. A function is stored and returned as it is, and GryMod never calls it. |
| `alt` | `"none"`, `"grenade"`, `"energy"`, `"zoom"`, `"doublebarrel"`, `"shoot"`, `"throwlow"`, `"melee"` | `"grenade"` when the resolved `altAmmo` is a grenade type other than the hand grenade's (the name contains `grenade` and is not `Grenade`), else `"none"` | What the right click is. `grenade` and `energy` with an `altAmmo` that the game knows make the grenade slot count that ammo. All values feed the camouflage rule that decides whether a right click shoots. `zoom` also makes the binoculars end the weapon zoom when they open (`gry_zoom_cancel_weapon`, and the server checks the same field) and hides the crosshair while the weapon is zoomed (`gry_zoom_hide_crosshair`). |
| `altAmmo` | string of 1 to 64 characters, an ammo type name | The engine secondary ammo type of the weapon, else `Secondary.Ammo` of the SWEP (ignored when empty or `"none"`) | The ammo the grenade slot counts for `alt = "grenade"` or `"energy"`. When the game does not know the ammo name, the slot shows nothing. For the other `alt` values it decides whether a right click shoots: `shoot` needs a reserve of it, or shoots always when the field is absent. |
| `altShoots` | boolean | `true` for `grenade`, `energy`, `doublebarrel`, `shoot` and `throwlow`, `false` for the other `alt` values | Whether a right click can end the camouflage (the player option `gry_cloak_altfire`). `melee` needs `altShoots = true` to count. |
| `altLabel` | string of 1 to 24 characters | none | A short name of the secondary fire. It reaches the HUD with the launcher icon (`GryMod.FlashHUD.LauncherLookFor`, `hud:GetLauncherLabel()`) and the movie has no text field for it, so nothing draws it. |
| `altIcon` | a key of `GryMod.API.WeaponIcons` | none (the grenade slot then shows `Grenade`) | The icon of the grenade slot while the weapon counts a launcher ammo there. |
| `icon` | a key of `GryMod.API.WeaponIcons` | none | The icon of the weapon slot. It wins over `slotIcon` and `fire`. |
| `slotIcon` | a key of `GryMod.API.WeaponIcons` | none | The icon of the weapon slot when `icon` is not set. It wins over `fire`. |
| `crosshair` | `false`, `true`, or an integer from 1 to `GryMod.API.CrosshairCount` | `true` | `false`: GryMod draws no crosshair while the weapon is in hand. `true`: the crosshair of the player's style. A number: that crosshair of the HUD movie, unless the player switched off `gry_hud_crosshair_weapon`. The HUD asks for this field by class name, so only the registry and `SWEP.GryHUD` can set it, never an adapter. |
| `zoomCrosshair` | `false`, `true`, or an integer from 1 to `GryMod.API.CrosshairCount` | none | Only for a weapon with `alt = "zoom"`. Without it (or with `false`) the crosshair is hidden while the weapon is zoomed. `true` keeps the player's crosshair in the zoom. A number shows that crosshair of the movie in the zoom. |
| `grenade` | a key of `GryMod.API.GrenadeKinds` | none (the slot shows `explosivegrenade`) | The kind of hand grenade the grenade slot shows while the weapon is in hand. The slot then counts the primary ammo of the weapon, and the icon blinks when the kind changes. It is also the fallback of `listIcon`. |
| `heat` | `function(wep)` | none | Gives the heat of the weapon in hand, from 0 (cold, bar hidden) to 1 (overheated). The HUD shows the bar above the weapon icon when the function exists and the player has not switched off `gry_hud_overheat`. A number that is not above 0 or is not a number gives a hidden bar, and a value above 1 gives a full bar. The function is asked at each frame while the weapon is in hand. |
| `listIcon` | a key of `GryMod.API.WeaponListIcons` | none (the list then uses the silhouette of `grenade`, and else writes the weapon name) | The silhouette of the weapon in the weapon list that shows at each weapon change. |

The guide has the effect of each field on screen: [what the HUD does with each field](../weapons.md#what-the-hud-does-with-each-field), [the weapon list](../weapons.md#the-weapon-list), [a weapon that overheats](../weapons.md#a-weapon-that-overheats).

A function stored for `fire` or `heat` is called with the weapon entity and runs under `SafeCall`:

```lua
GryMod.API.RegisterWeapon("weapon_my_rifle", {
	fire = function(wep)
		return wep:GetNW2Bool("MyBurst") and "burst" or "auto"
	end,
	heat = function(wep) return wep:GetNW2Float("MyHeat") / 100 end,
})
```

### GryMod.API.UnregisterWeapon(class)

Shared. Removes the registry entry of a class.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `class` | string | The class to remove. | no |

Returns `true` when an entry existed and was removed. Returns `false` when `class` is not a string or the class has no entry. Only the entry of that exact class is removed. A class built on it then looks further up its base chain.

### GryMod.API.GetWeapon(class)

Shared. Reads back the entry registered for a class.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `class` | string | The class to look up. | no |

Returns a copy of the registered entry, a table with the fields that were given at registration, or `nil` when `class` is not a string or has no entry. It looks at that class only: no base class, no `SWEP.GryHUD`, no adapter, no default. A function stored in the entry is the same function, not a copy.

## Adapters

An adapter describes the weapons of a weapon base from the fields that base keeps. No file of GryMod registers one today: the patches in `lua/grymod/compat/weapons/` read the fire mode through `GryMod.FlashHUD.AddFireModeResolver` instead (see [the guide](../weapons.md#weapon-bases)).

### GryMod.API.AddWeaponAdapter(id, fn)

Shared. Adds a function that gives a partial definition for a weapon entity.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the adapter. A string of at least 1 character. | no |
| `fn` | function | `fn(wep)`. It receives the weapon entity and returns a table with any of the fields of a definition, or nothing for a weapon that is not its own. | no |

Returns `true` when the adapter is added or replaced. Returns `false` when `id` is not a non-empty string or `fn` is not a function.

An adapter is asked once for each field that the registry and `SWEP.GryHUD` left undecided, so one resolution can call it several times. It must be cheap and it must not allocate when it has nothing to say. It runs under `GryMod.API.SafeCall`: an error counts as no answer, and five errors in a row switch the adapter off until it is added again. Adapters are asked in the order they were added, and the first one that gives a valid value for the field wins. An invalid value in the returned table is ignored.

Adding an `id` that exists replaces its function, keeps its place in the order, and re-arms it. An adapter is asked about weapon entities only: a class name given to `WeaponValue` or `ResolveWeapon` never reaches the adapters. The camouflage rule for the right click and the crosshair rule ask by class name, so an adapter cannot set `alt`, `altShoots` or `crosshair` for them.

```lua
GryMod.API.AddWeaponAdapter("my_base", function(wep)
	if wep.Base ~= "my_base" then return nil end

	return {fire = wep.Primary.Automatic and "auto" or "semi"}
end)
```

### GryMod.API.RemoveWeaponAdapter(id)

Shared. Removes an adapter.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name given to `AddWeaponAdapter`. | no |

Returns `true` when the adapter existed and was removed, `false` otherwise. Its error count is cleared.

## Reading the registry

### GryMod.API.WeaponValue(wep, field, explicit)

Shared. Gives one field of a weapon, resolved through the layers above, without building a table.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `wep` | Weapon or string | A weapon entity, or a class name. | no |
| `field` | string | One of the 16 fields of the table under `RegisterWeapon`. | no |
| `explicit` | boolean | `true` gives only what is declared (registry, `SWEP.GryHUD`, adapters): no default and no fallback. | yes, `false` |

Returns the value of the field, or `nil` when nothing sets it. Also returns `nil` when `wep` is not a valid weapon (a `nil`, a number, a boolean, a function, an entity that is not valid) and when `field` is not one of the 16 names.

With a class name, the SWEP of that class is read from `weapons.GetStored` for the `GryHUD` table and the defaults. What only an entity can tell is left out: the adapters, a `fire` function, the engine ammo types and `CustomAmmoDisplay`. A `fire` function that does not answer with a valid mode gives the default of the field.

Without `explicit`, three fields have a fallback when no layer and no default gives a value: `alt` is `"grenade"` or `"none"`, `altShoots` follows `alt`, and `crosshair` is `true`. With `explicit` they stay `nil`.

The HUD asks it every frame, and the function does not allocate a table.

### GryMod.API.ResolveWeapon(wep, explicit)

Shared. Gives the final description of a weapon, the table the HUD and the camouflage rule use.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `wep` | Weapon or string | A weapon entity, or a class name. | no |
| `explicit` | boolean | `true` gives only what is declared, with no default and no fallback. | yes, `false` |

Returns a new table, or `nil` when `wep` is not a valid weapon. The table has a key for each of the 16 fields that resolved to a value. It has one more key, `display`, when the weapon entity has a `CustomAmmoDisplay` function, the function returns a table, and that table does not set `Draw = false`, and `explicit` is not set. `display` is a table that copies the numeric values of the `CustomAmmoDisplay` table: `clip` from `PrimaryClip`, `ammo` from `PrimaryAmmo`, `altAmmo` from `SecondaryAmmo` and `altClip` from `SecondaryClip`. A key whose value is not a number is left out. `CustomAmmoDisplay` is called once for each call of `ResolveWeapon`, under `SafeCall`.

Without `explicit`, `counter` is always set (`"clip"` unless the layers or `CustomAmmoDisplay` say otherwise), and the three fallbacks of `WeaponValue` apply. A class name gives the same table as an entity of that class minus the entity-only parts listed under `WeaponValue`.

The camouflage rule for a right click (`GryMod.AltFireShoots`) reads `alt`, `altAmmo` and `altShoots` from `ResolveWeapon(class)`.

## The lists of names

Each of these is a table that maps a name to `true`. Test a name with `GryMod.API.WeaponIcons[name]`. The registry uses them to validate the fields, and an addon can use them to check a name before it registers.

### GryMod.API.WeaponIcons

The 22 icons of the weapon slot in the HUD movie, the labels of its `AmmoMode` clip. A weapon chooses one with `icon`, `slotIcon` or `altIcon`, and the fire mode resolvers of the weapon bases must answer one of them.

`Single`, `Burst`, `Auto`, `Grenade`, `Incendiary`, `Tranquilizer`, `infinity`, `Shotgun`, `Narrow`, `Mine`, `Repairkit`, `Moac`, `Moar`, `TACCannon`, `C4`, `Gauss`, `Gunner`, `Missle`, `Mounted`, `NoGun`, `Claymore`, `HandGrenade`.

The stock weapons of Half-Life 2 and Garry's Mod show `Single`, `Auto`, `Grenade`, `Shotgun`, `Mine`, `Repairkit`, `Missle`, `NoGun` and `HandGrenade`. Twelve icons are used by none of them and are there for the weapons of other addons: `Incendiary`, `Tranquilizer`, `infinity`, `Narrow`, `Moac`, `Moar`, `TACCannon`, `C4`, `Gauss`, `Gunner`, `Mounted`, `Claymore`. Names are case sensitive: `Missle` and `infinity` are spelled as the movie spells them.

### GryMod.API.GrenadeKinds

The kinds of hand grenade of the grenade slot, the labels of the grenade icon in the HUD movie. It is the set of valid values of the `grenade` field.

`explosivegrenade`, `flashbang`, `smokegrenade`, `empgrenade`.

`explosivegrenade` is the grenade of Half-Life 2 and the kind the slot shows for a weapon that declares none. The weapon list maps each kind to a silhouette: `Grenade_Explosive`, `Grenade_Flashbang`, `Grenade_Smoke`, `Grenade_EMP`.

### GryMod.API.WeaponListIcons

The 25 silhouettes of the weapon list movie (`HUD_WeaponSelection`), the labels of its icon clip. It is the set of valid values of the `listIcon` field.

`SOCOM`, `SMG`, `Shotgun`, `SCAR`, `FY71`, `Hurricane`, `LAW`, `TACGun`, `GaussRifle`, `DSG1`, `Grenade_Explosive`, `Grenade_Flashbang`, `Grenade_Smoke`, `C4`, `LockpickKit`, `RadarKit`, `RepairKit`, `AVMine`, `Claymore`, `MOARAttach`, `AlienMount`, `Grenade_EMP`, `NightVision`, `Binoculars`, `Fists`.

The first frame of that clip, a "forbidden" sign, is not in the list. A weapon with no silhouette gets a row with its name in capitals, 18 characters at most, and never a picture chosen by GryMod.

### GryMod.API.CrosshairCount

A number, 13: how many crosshairs the HUD movie has. It is the upper bound of the values `crosshair` and `zoomCrosshair` accept as a number. The lower bound is 1.
