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
| `compat/damage/`, `compat/npc/` | (none yet) | Where the patches for addons that change the damage, and the adapters for NPC bases (DrGBase, VJ Base), go. |

## Adding a patch

1. Put the file in the folder that fits (`compat/<what it is about>/`), with the prefix of its realm.
2. Add it to `lua/autorun/grymod_shared.lua`: `AddCSLuaFile` in the `SERVER` block, and `include` in the `SERVER` block (for a server or shared file) and in the
   `CLIENT` block (for a client or shared file), after the file it needs.
3. Register through the public API. A reader that has to survive a hot reload takes a **key**: `GryMod.FlashHUD.AddFireModeResolver(fn, "compat.my_base")`
   replaces the earlier resolver of the same key instead of adding a second one.
4. Add a test in `tests/` (a stand-in of the thing, the way the existing ones do it) and run `python tools/check_lua_syntax.py` and the loader test.

If your addon is the one that needs a patch, you do not need this folder: describe your weapon with `SWEP.GryHUD`, or register your entities from your own addon
([api.md](api.md), [weapons.md](weapons.md)). `compat/` is for what GryMod ships about things it does not own.
