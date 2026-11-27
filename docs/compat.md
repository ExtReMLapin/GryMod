# Compatibility patches

GryMod works with the stock Half-Life 2 and Garry's Mod game, and with other addons' weapons, NPCs and entities, through **registries** and
**hooks** of its public API ([api.md](api.md)). Everything it knows about a game or an addon that is not its own lives in one folder,
`lua/grymod/compat/`, so that a patch is easy to find, to read, to change and to take away.

## The rule

A file of `compat/`:

- uses **only the public API** (`GryMod.API.RegisterWeapon`, `RegisterTracked`, `RegisterUsable`, `AddWeaponAdapter`, `GryMod.FlashHUD.AddFireModeResolver`,
  the hooks...), exactly as an addon of yours would. It touches no private table of GryMod;
- is **data or a small reader**, not a feature: what the thing is, not what GryMod does with it. The features read the registries and know no class name;
- does nothing when the game or the addon it is about is not there: it answers `nil` for what is not its own, and never raises an error;
- has a **low priority** where the registry has priorities, so that an addon's own entry for the same class always wins, whatever the order of loading;
- is named with the realm prefix of the project (`sh_` shared, `cl_` client, `sv_` server), and is added to the loader (`lua/autorun/grymod_shared.lua`), both
  `AddCSLuaFile` and `include`. `python -m unittest tools.test_loader_coverage` fails when a file is not loaded or the loader names a file that is not there.

Taking a file away takes the patch away and breaks nothing else.

## What is there

| Folder | Files | What it says |
| --- | --- | --- |
| `compat/hl2/` | `sh_weapons.lua` | The 19 stock weapons (Half-Life 2 and Garry's Mod): fire mode, ammo, what the secondary fire is, the icons. They are written in C++, there is no `Primary` table to read. See [weapons.md](weapons.md). |
| | `sh_tracked.lua` | The stock NPCs, vehicles and projectiles: the radar icon, the heavy machines, the dangerous projectiles of the grenade warning. |
| | `sh_usable.lua` | What the +use key acts on in the stock game (doors, buttons, ladders, chargers, props, vehicles...), each class checked in the SDK code. |
| `compat/weapons/` | `cl_arc9.lua`, `cl_arccw.lua`, `cl_tfa.lua`, `cl_m9k.lua`, `cl_cw2_fas2.lua` | One reader for each third-party weapon base: how to read the fire mode it keeps in its own fields, for the icon of the weapon slot. |
| | `cl_tfa_parts.lua` | The attachments of a TFA weapon (a reflex sight, a laser) are models the weapon draws itself: they are the weapon's parts, so the camouflage covers them like the gun (`GryMod.API.AddWeaponPartsProvider`). |
| | | The optics are found by their materials, for any base: the picture of a scope, a reticle, a lens with a dot stay readable on a camouflaged gun (`GryMod.CloakFX.Refract.Keeps`, see [api.md](api.md)). |
| | `cl_tfa_menu.lua` | The weapon icon of the quick menu opens TFA's own menu (attachments, ammunition) for the weapon in hand, with the impulse TFA's key sends (`GryMod.API.AddWeaponMenuProvider`, see [api.md](api.md)). |
| | `cl_arc9_menu.lua`, `cl_arccw_menu.lua`, `cl_cw2_menu.lua`, `cl_fas2_menu.lua` | The same for ARC9 (`ToggleCustomize(true)`), ArcCW (`arccw_toggle_inv`), CW 2.0 (`attemptToggleInteractionMenu`) and FA:S 2 (`fas2_togglegunpimper`). **Read in their source code and not tried in a game** (none of them was installed when written): check with the real base before trusting them. |
| | `sh_tfa_suit.lua`, `sv_tfa_suit.lua` | What the suit does to a TFA weapon, with the original game's numbers (`lua/grymod/sh_suit_weapons.lua`): strength mode, melee x9.2 with a full bar, recoil x0.375, 7.5 of the bar a shot; speed mode, draw, holster and raise x1.75, melee swing x1.5 (a reload is not faster in the original: `gry_suit_reload_rate`). One setting each. |
| | `sv_tfa.lua` | TFA's attacks that are not bullets (a knife's right click, a bash, a grenade's low throw) end the camouflage, through TFA's own hooks and `GryMod.API.ReportAttack`. A gun's right click that is only the sights does not. |
| `compat/damage/`, `compat/npc/` | (none yet) | Where the patches for addons that change the damage, and the adapters for NPC bases (DrGBase, VJ Base), go. |

## Damage: living with the addons that change it

The suit's armor is one hook, `EntityTakeDamage` named `"Grymod damage handeling"` (`sv_health.lua`). In armor mode it takes the damage it **sees** out of the energy bar and
lets the rest through (at least 30 percent, as the original game). What other addons need to know:

- **The order of two addons' hooks cannot be chosen.** `hook.Add` has no priority in this version of the game and `hook.Call` walks the hooks with `pairs`. If another addon
  scales the damage (a difficulty mod, a damage multiplier), the armor pays for the scaled damage when its hook runs after, and for the original damage when it runs before: a
  hit of 30 doubled by such a mod costs the bar 60 in the first case and 30 in the second (`tests/sv_damage_compat_test.lua` states it). Neither is an error. If you write
  such a mod and want the armor to pay for your final damage, scale in `GM:ScalePlayerDamage` (it runs before `EntityTakeDamage`, for bullet damage) or do the scaling
  before the hit is applied.
- **GryMod never stops the hooks after it:** its hook returns nothing. Return nothing yourself unless you really block the hit (`true`: the others, and the gamemode, do not run).
- **God mode** (an admin mod's "god", `Player:GodEnable`): the suit takes no energy, the damage is left as it is and nothing is told (no arrows, no sound, no
  `GryMod_ArmorAbsorbed`).
- **Energy is kept between 0 and 100** and the damage that goes on is never negative, whatever a mod does to it before or after.
- The reports for addons are `GryMod_ArmorAbsorbed(ply, absorbed, passed)` (after the damage was changed: do not call `TakeDamage` from it) and the suit's other hooks in
  [api.md](api.md).

## Adding a patch

1. Put the file in the folder that fits (`compat/<what it is about>/`), with the prefix of its realm.
2. Add it to `lua/autorun/grymod_shared.lua`: `AddCSLuaFile` in the `SERVER` block, and `include` in the `SERVER` block (for a server or shared file) and in the
   `CLIENT` block (for a client or shared file), after the file it needs.
3. Register through the public API. A reader that has to survive a hot reload takes a **key**: `GryMod.FlashHUD.AddFireModeResolver(fn, "compat.my_base")`
   replaces the earlier resolver of the same key instead of adding a second one.
4. Add a test in `tests/` (a stand-in of the thing, the way the existing ones do it) and run `python tools/check_lua_syntax.py` and the loader test.

If your addon is the one that needs a patch, you do not need this folder: describe your weapon with `SWEP.GryHUD`, or register your entities from your own addon
([api.md](api.md), [weapons.md](weapons.md)). `compat/` is for what GryMod ships about things it does not own.

## Checklist: supporting a new weapon base or weapon pack

Do every line for each weapon base (a base, not each weapon: the patches detect the base by its markers, never by a class name), with a REAL weapon of the base in a test
game, and write down what could not be checked (a base that is not installed is "read in the source, not tried"). A line that does not apply to the base is answered "n/a"
in the commit message, not skipped.

**Seeing the weapon**
1. **Detect the base** by its markers or its base chain (`weapons.IsBasedOn`), never by class names. Nothing may happen for another base or when the base is not installed.
2. **Fire mode icon**: `GryMod.FlashHUD.AddFireModeResolver` (cl_<base>.lua). Check each mode the base has, live: single, burst, automatic, safety, under-barrel launcher.
3. **Ammunition on the HUD**: a weapon without a magazine (a knife, a melee weapon, a bash-only tool) shows no bullets. "Infinite" and a bullet counter must never both show.
4. **The base's own HUD**: if it draws a HUD of its own (ammo, fire mode, hints) that crowds ours, make hiding it an option on the Compatibility page, not a silent change.
5. **Weapon menu**: `GryMod.API.AddWeaponMenuProvider` so the weapon icon of the quick menu opens the base's customization / inspection menu.

**Camouflage (first and third person)**
6. **The weapon and every attachment are covered**: put attachments on the weapon (a scope, a reflex sight, a laser, a silencer, a grip) and look at plain and camouflaged
   screenshots, one after the other. Attachments drawn by the base itself are not the view model: give them to `GryMod.API.AddWeaponPartsProvider`.
7. **Attachments changed while camouflaged** (attached, detached, swapped): covered at once, nothing to refresh.
8. **Optics stay usable**: the picture of a scope, a reticle and the dot of a sight stay readable (the layers keep unlit, translucent, additive and render-target materials).
9. **The base's own drawing context**: some bases open their own 3D camera, depth range or render targets while drawing the view model (ARC9). Check the camouflage with it
   on, in iron sights and in the customization menu.
10. **Camouflage ends on an attack**: bullets are seen by the server; a melee swing, a right click that attacks, a throw and a bash are reported with
    `GryMod.API.ReportAttack`. Iron sights alone do not end it.

**Strength mode** (costs energy; the weapon base's code must not be edited, only hooked)
11. **Melee damage and push, from a gun (bash, butt stroke) and from a melee weapon**, multiplied with the energy (`GryMod.SuitWeapons.MeleeScale`).
12. **Recoil** reduced with the energy (`RecoilScale`); check the kick stat names of the base (some versions rename them).
13. **Energy**: each shot takes its cost, a melee hit takes its cost, never under 0, nothing while the armor is infinite.

**Speed mode**
14. **Weapon handling**: draw, holster, raise after a sprint, fire mode switch, melee swing (`SuitWeapons.Rate`). The reload follows `gry_suit_reload_rate` (the original
    game does not speed it up). Lock-out times must follow the animation: a weapon ready too early or too late is a bug.
15. **Inspect and other animations** that have their own timing are left alone unless the original speeds them up.

**Shipping**
16. Settings go on the **Compatibility page, one tab or category for the base** (administrators' settings through the white list), each one optional.
17. Loader lines (`grymod_shared.lua`), `python tools/check_lua_syntax.py`, `python -m unittest tools.test_loader_coverage`, tests with stand-ins that pin the markers and
    what is called, plus a live check on the real base, numbers written in the commit message.
18. Every hook the patch adds is cheap (early return), runs under `pcall` where the base calls it, and answers `nil` when nothing changes.
19. Document it in the table at the top of this file and in [api.md](api.md) if the API grew.
