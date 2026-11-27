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
| | `sh_melee_suit.lua`, `sv_melee_suit.lua` | What the suit does to the three stock melee weapons (the fists, the crowbar, the stun baton), with the same numbers and settings as for TFA and ARC9 (`gry_suit_strength_melee`, `gry_suit_melee_cost`, `gry_suit_handling`): strength mode, damage and push x9.2 with a full bar (through `EntityTakeDamage`, the weapon is the inflictor; the fists' own push on a prop too); a blow takes 20 of the bar in the strength mode and 10 in the speed mode when it starts, so the energy that is left decides how hard it hits; speed mode, the blow x1.5 (the time before the next blow and the view model's animation) and the draw x1.75. The fists are a Lua SWEP: their attack, draw and damage function are decorated once (shared file). The crowbar and the stun baton are written in C++: their blows are seen from the player's commands (`StartCommand`, added only while one of them is in a hand, removed after). The right click of these two weapons does nothing in the game; the fists' right click is the other hand, a blow like the left one. These three classes are named in `sh_melee_suit.lua` only. |
| | `sh_tracked.lua` | The stock NPCs, vehicles and projectiles: the radar icon, the heavy machines, the dangerous projectiles of the grenade warning. |
| | `sh_usable.lua` | What the +use key acts on in the stock game (doors, buttons, ladders, chargers, props, vehicles...), each class checked in the SDK code. |
| `compat/weapons/` | `cl_arc9.lua`, `cl_arccw.lua`, `cl_tfa.lua`, `cl_m9k.lua`, `cl_cw2_fas2.lua` | One reader for each third-party weapon base: how to read the fire mode it keeps in its own fields, for the icon of the weapon slot. ARC9's was tried with real weapons (automatic, burst, single, the launcher under the barrel; a safety shows the single shot icon, a knife no gun). |
| | `cl_tfa_parts.lua`, `cl_arc9_parts.lua` | The attachments of a TFA or ARC9 weapon (a reflex sight, a laser, a suppressor) are models the weapon draws itself: they are the weapon's parts, so the camouflage covers them like the gun (`GryMod.API.AddWeaponPartsProvider`). |
| | | The optics are found by their materials, for any base: the picture of a scope, a reticle, a lens with a dot stay readable on a camouflaged gun (`GryMod.CloakFX.Refract.Keeps`, see [api.md](api.md)). |
| | `cl_tfa_menu.lua` | The weapon icon of the quick menu opens TFA's own menu (attachments, ammunition) for the weapon in hand, with the impulse TFA's key sends (`GryMod.API.AddWeaponMenuProvider`, see [api.md](api.md)). |
| | `cl_arc9_menu.lua` | The same for ARC9 (`ToggleCustomize(true)`, tried), and the camouflage leaves the gun plain while ARC9's customization menu is up (`GryMod.API.AddPlainViewProvider`). |
| | `cl_arccw_menu.lua`, `cl_cw2_menu.lua`, `cl_fas2_menu.lua` | The same for ArcCW (`arccw_toggle_inv`), CW 2.0 (`attemptToggleInteractionMenu`) and FA:S 2 (`fas2_togglegunpimper`). **Read in their source code and not tried in a game** (none of them was installed when written): check with the real base before trusting them. |
| | `cl_arc9_hud.lua` | ARC9's own HUD (weapon name, ammunition, fire mode) crowds the bottom left corner: `gry_arc9_hide_hud` (on by default, ARC9 tab of the Compatibility page) hides it while GryMod's HUD is up. Its key hints and customization menu stay, none of its settings is changed. |
| | `sh_tfa_suit.lua`, `sv_tfa_suit.lua`, `sh_arc9_suit.lua`, `sv_arc9_suit.lua` | What the suit does to a TFA or ARC9 weapon, with the original game's numbers (`lua/grymod/sh_suit_weapons.lua`): strength mode, melee x9.2 with a full bar, recoil x0.375, 7.5 of the bar a shot; speed mode, draw, holster and raise x1.75, melee swing x1.5 (a reload is not faster in the original: `gry_suit_reload_rate`). One setting each, the same for both bases. |
| | `sv_tfa.lua`, `sv_arc9.lua` | The attacks of TFA and ARC9 that are not bullets (a knife's stab, a bash, a grenade's throw, ARC9's launcher under the barrel) end the camouflage, through the base's own hooks and `GryMod.API.ReportAttack`. A gun's right click that is only the sights does not. |
| `compat/view/` | `cl_thirdperson.lua` | The third person cameras of other addons are **camera owners** (`GryMod.API.AddCameraOwner`): while one has the view, the binoculars give no view and do not read the game's zoom key, the heading follows the drawn view. Simple ThirdPerson, Enhanced ThirdPerson, DarkFated's third person, tpcgm, Customisable Thirdperson (which removes every other CalcView hook while it is on), ARC9's own third person, PAC's camera part, editor camera and the camera a server imposes. An owner is put only for an addon that is there. Also: Enhanced ThirdPerson's HUDShouldDraw answers `true` for the game's crosshair when its third person is off, so the patch wraps that one hook once (no answer while GryMod's crosshair is up, in first person). **Read in their public source and checked with stand-ins, not tried in a game** (none installed when written). |
| | `cl_legs_ec2.lua` | Gmod Legs 3 (`LocalPlayer().ShouldDisableLegs`, set only if it was not set) and Enhanced Camera 2 (`EnhancedCameraTwo:ShouldDraw` wrapped once) draw the local player's legs and body with models of their own that the camouflage does not cover: they are **hidden** while the camouflage is on and while it fades out (`GryMod_CloakChanged`, one timer for the end of the fade). Covering them is `AddPlayerPartsProvider`, not done. Stand-ins only. |
| | `cl_vmanip.lua` | VManip's animations are not started while the binoculars are up (`VManipPrePlayAnim` answers `false`) and the one that plays is ended: the view model is not drawn then, so its `PostDrawViewModel` does not come and the animation would freeze, with its camera angle. Stand-ins only. |
| | `cl_nvg_others.lua` | `GryMod_CanUseView("nightvision")` answers `false` while another night vision is on, so the key does not stack a second one. Reads NVScript (its `NV_FX` hook; read in two forks of its code) and JMod's goggles (`ply.EZarmor.effects`). Modern Warfare NVGs and Arctic's GCAL are not read (no public source, not installed): add a reader to `GryMod.CompatOtherNV.Sources`. Stand-ins only. |
| `compat/vehicles/` | `sh_simfphys.lua`, `sv_simfphys.lua`, `cl_simfphys.lua` | simfphys, the physics vehicle base (the base and its armed pack). The car is one class for every vehicle, the player sits on a child seat, the wheels have a +use of their own. Shared: the vehicle provider (the car, not the seat; the driver who sits, never the remote driver), the tracked entries (every car is a vehicle contact once scanned, a tank is a heavy machine, the crew of the car colours it, its own forward turns its icon, a wreck is no contact, the anti-tank mine is a device), the prompts of the wheels and of the mine. Server: a hit filter (what simfphys cancels on a seated player costs the suit nothing; the explosion of the car, which wants its occupants dead, goes through the armor) and the shell of a cannon and the thrown mine ending the camouflage. Client: no prompt on a locked car. **Written from the source of simfphys, tested with stand-ins: see the section below.** |
| `compat/vehicles/` | `sh_lvs.lua`, `sv_lvs.lua`, `cl_lvs.lua` | **LVS** (the framework `lvs_base` of SpaxscE and the packs built on it). The vehicle of a player, its driver and its kind (`AddVehicleProvider`); the radar entries (flying unit or machine, relation by LVS team, a wreck is no contact, the occupants, the heading, what an AI vehicle knows of the player); the grenade warning for `lvs_missile` / `lvs_bomb` and the classes built on them (only for the player the missile is aimed at); the use prompt of a vehicle (not for a locked or wrecked one); the icon of LVS's tools; the hits an occupant takes (`AddHitFilter`: what LVS cancels is ignored, the explosion's kill goes through the bar); the shots of LVS's weapons end the camouflage (`LVS:FireBullet` is wrapped, `ReportAttack`); the view LVS owns (`AddCameraOwner`). **Read in LVS's code, not tried in a game** (LVS was not installed when it was written): see below. |
| `compat/vehicles/` | `sh_glide.lua`, `sv_glide.lua`, `cl_glide.lua` | Glide (StyledStrike's vehicle base): its vehicles on the radar, heavy for the suit, a danger for its missiles, the ENTER VEHICLE prompt, a camera owner, the respawn that keeps the suit, the lock-on that does not see a camouflaged driver. See "Glide" below. |
| `compat/tools/` | `sh_wire.lua` | Wiremod: the use prompt of its buttons, lever, wheel, hologrid, interactive screens, text entry and keyboard (by class lists: never a match function, a duplicator pastes thousands of Wire entities), and the grenade warning of its timed explosive. |
| | `sh_jmod.lua`, `sv_jmod.lua`, `cl_jmod.lua` | JMod: the grenade warning for its grenades, bombs, rockets and mines (by base; the state numbers differ for each family and each reader says which table it reads), its mines as radar contacts once scanned, the use prompts (grenades, bombs, mines, machines, resource boxes); a mine or a sentry does not take a camouflaged player for a target (its hook `JMod_ShouldAttack`, while `gry_cloak_ai` is on); the attack key with a JMod grenade in the hands ends the camouflage; its bone merged armor follows the camouflage (`AddPlayerPartsProvider`). |
| | `sh_m9k_specialties.lua`, `sv_m9k_specialties.lua` | M9K Specialties: the grenade warning for its thrown grenades, launched grenades, rockets, proximity mine and C4, the mine as a radar contact, the ammo box prompt; its proximity mine does not go off for a camouflaged player (its hook `M9k_ProxyMineCanTrigger`); a grenade or a rocket fired ends the camouflage. |
| | `sh_gbombs5.lua` | Gbombs 5: the grenade warning for its bombs and rockets (recognised by their `Arm` and `Explode` methods: the entity files set no `ENT.Base`) and the ARM prompt (its replicated setting `gb5_easyuse`). |
| | `cl_pac3.lua` | PAC3: the outfit of a player is hidden while he is camouflaged (`pac.TogglePartDrawing`, told by `GryMod_CloakChanged`), the parts on the view model and the hands of the local player too. |
| | `cl_prop_protection.lua` | Falco's Prop Protection and NADMOD PP: no use prompt on what the prop protection will not let the player use (`AddUsableFilter`). |
| `compat/damage/`, `compat/npc/` | (none yet) | Where the patches for addons that change the damage, and the adapters for NPC bases (DrGBase, VJ Base), go. |
| `compat/npc/` | `sh_vjbase.lua`, `sv_vjbase.lua` | **VJ Base** (and the packs built on it: Half-Life Resurgence, the official collection...). Shared: the projectiles VJ tags as grenades or dangers (`VJ_ID_Grenade`, `VJ_ID_Danger`) join the grenade warning; the tanks, the aircraft and the bullseye in the radar's registry; the prompts "TAKE" (a VJ weapon on the floor needs the use key) and "FOLLOW" (an ally that follows when used); a melee weapon has no gun icon; the NPC controller (possession) owns the camera. Server: VJ's enemies that have not seen the player are hostile (not neutral) for the radar, the friends stay allies while the player is camouflaged and keep following him, a melee weapon or a launcher in the hands ends the camouflage, VJ's projectiles ring the radar, the melee slow gives back the new mode's speeds. Nothing happens without VJ Base. Facts read in its code and tried in a real game, see [the VJ Base section](#vj-base-what-the-adapter-does-and-why). |
| `compat/damage/` | (none yet) | Where the patches for addons that change the damage go. |

**The patches of `compat/tools/` were written from the public code of the addons and tried with stand-ins only** (none of them was installed on the machine): the tests (`tests/sh_compat_*_test.lua`,
`sv_compat_*_test.lua`, `cl_compat_*_test.lua` for Wiremod, JMod, M9K Specialties, Gbombs 5, PAC3 and prop protection) pin what the patches read and answer, not what the real addons do. Install the addon
and look before trusting one: the explosions of those addons ring the radar through the core's wrap of `util.BlastDamage` (see [api.md](api.md)), and what is not certain is listed in the comment at
the top of each file (the camouflage of JMod's armor, PAC3's outfit in first person).

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

## Fall damage: living with the addons that change it

A fall is one number. When a player lands faster than 526.5 units a second the engine asks `GM:GetFallDamage(ply, speed)` (the `GetFallDamage` hooks of the addons first,
the first answer that is not `nil` wins, then the gamemode) and applies the answer as damage of the type `DMG_FALL`, from the world, through `EntityTakeDamage`. Nothing in
GryMod listens to `GetFallDamage` or `OnPlayerHitGround`: **the armor pays the fall like any other damage**, and it pays the number the engine really uses, whatever the order
of the addons (the order problem above only exists for an addon that *scales* damage inside `EntityTakeDamage`). `tests/sv_fall_damage_test.lua` states it, and
`tests/fall_damage_job.lua` does real falls.

- The game's own answer is 10 for every fall, whatever the height. With the game's setting `mp_falldamage 1` ("realistic fall damage" of the sandbox's server settings) it is
  `(speed - 526.5) * 100 / 396`: about 18 for a fall of 300 units, 81 for 600 and 170 for 1200 (a gravity of 600). The armor pays that from the bar (the health takes what
  the bar cannot pay, and the armor always takes at least 30 percent of the damage, as for any other hit). In the strength, speed and camouflage modes there is no armor: the
  health takes the fall.
- That setting is not saved by the game: it goes back to 0 at every launch. **`gry_realistic_fall`** (replicated, saved, off by default, in the options panel under "Server
  (administrators only)") turns it on at every launch and as soon as it is changed. It sets the game's setting and nothing else: no `GetFallDamage` hook of GryMod, so the answer
  of any addon keeps winning. Turning the option off takes the game's setting back only if GryMod turned it on: a setting that was on before (the sandbox's check box, a server
  config) is left alone.

| Addon (read in its public code) | What it does | With the armor |
| --- | --- | --- |
| JMod | `GetFallDamage` returns `speed^2 / 8000` when its option "realistic fall damage" is on; `OnPlayerHitGround` only for the parachute. | The armor pays that number. |
| Prone Mod | `GetFallDamage` returns the gamemode's realistic number times a multiplier, for a prone player. | Same. |
| Beatrun | `GetFallDamage` returns 0 on a landing mat and under a speed of 800, `math.huge` from 800 (a lethal fall, even with a full bar: the addon wants it), unless in overdrive or in god mode. `OnPlayerHitGround` runs the roll. | The 0 costs nothing; the infinite fall kills through the armor, with no error and an energy that stays between 0 and 100. |
| gwater2 (fluid), DrGBase (possession of an NPC), the bunny hop of notagain (jump held) | `GetFallDamage` returns 0 in their case. | No damage, no energy. |
| Draconic Base | Only listens (`OnPlayerHitGround`: landing animation and footsteps; a voice line on `DMG_FALL`). | Nothing to do. |

What GryMod cannot do for you: an addon that takes health away itself (`SetHealth`, not a damage) goes around the armor, and an addon that scales `DMG_FALL` inside
`EntityTakeDamage` is the case of the first section (the armor pays for the damage it sees, the order of the two hooks is not ours). An addon that answers `GetFallDamage`
is the clean way to change a fall, and is the one to prefer.

## ARC9: how it was checked (2026-11-27)

Tried with the real base (the pack "[ARC9] Gunsmith Arms: Source", `arc9_fas_famas` with a suppressor, an Aimpoint or an ACOG, a laser and an M203; `arc9_go_knife_ct`,
`arc9_go_ak47`, `arc9_fas_machete`, `arc9_go_nade_frag`), in a test client at 640x360. Every number is from the game.

**The camouflage.** ARC9 draws its view model inside its own 3D camera and depth range (`SWEP:PreDrawViewModel` ... `PostDrawViewModel`), and the layer of the camouflage draws
the view model again (`vm:DrawModel()` from the engine's `PostDrawViewModel` hook), which runs ARC9's own `PreDrawViewModel` / `PostDrawViewModel` a second time, nested. Two things
followed. ARC9 copies the screen again there (`render.UpdateScreenEffectTexture`, `arc9_fx_adsblur_bleeding`, on by default): the copy the layer reads then held the plain gun, and the layer
refracted the gun it was meant to hide. And the second `PostDrawViewModel` puts `render.DepthRange(0, 1)` back, so the layer over the hands that came next failed the depth test. Both are
fixed for every base: the first person layer reads a copy of its own taken before the view model is drawn (`Refract.CaptureScreen`, the render target `GryCloakScreenCopy`), and it
sets the engine's view model depth range (0 to 0.1) before each layer. The attachments are the parts of `cl_arc9_parts.lua`. ARC9's customization menu draws a dark, blurred backdrop
after the copy, so the gun is left plain there (a plain view). The laser's beam and dot are a light effect, and stay.

**The binoculars.** ARC9 draws its gun with a field of view of its own, so the world zooms and the gun does not (TFA does the same; the stock weapons are put away by the game's own zoom).
The original holds the binoculars in place of the weapon: `gry_binoculars_hide_weapon` (on by default) does not draw the view model and the hands while they are up.

**The checklist for ARC9** (lines 1 to 19 above):

| Line | Result |
| --- | --- |
| 1. Detect | `weapon.ARC9 == true`, never a class name; nothing without ARC9 (tests with stand-ins and with no `ARC9` table). |
| 2. Fire mode | Tried live: automatic, burst, single, the M203 (grenade). A safety (`GetSafe`) shows the single shot icon, a knife (`PrimaryBash`) shows no gun. The 121 weapons installed use modes -1, 1, 2 and 3. |
| 3. Ammunition | A knife has no magazine (Clip1 -1): the HUD shows the infinity icon and no bullet counter. |
| 4. Own HUD | `gry_arc9_hide_hud`, ARC9 tab. Checked live: the panel beside the minimap goes, the key hints stay. |
| 5. Menu | `ToggleCustomize(true)` opens the menu (tried through the quick menu's provider). |
| 6. Covered | Gun, hands and attachments (suppressor, Aimpoint, ACOG, laser, M203) in first person, compared plain and camouflaged. The laser beam stays. Third person: the gun is covered through the proxy of its world model; ARC9's attachments are not drawn there (the server hides the world model, so ARC9's own world model draw does not run). |
| 7. Changed while camouflaged | Attached, detached, swapped during the camouflage: covered at once (the provider reads ARC9's `VModel` at each frame). |
| 8. Optics | The picture of the ACOG and its reticle, the Aimpoint's dot and lens stay readable in iron sights while camouflaged (same picture as plain). |
| 9. Own drawing context | The cause of the report, above. Checked in iron sights and in the customization menu. |
| 10. Ends on an attack | Bullets (the server sees them, also with ARC9's physical bullets), a bash key swing of a gun, a knife, a machete, a grenade throw and a launcher shot end it (`sv_arc9.lua`); the sights do not. |
| 11. Melee | Hit damage and push x9.2 with a full bar in the strength mode: knife 45 to 414 (push 16000 to 147200), machete 20 to 184, a gun's bash 45 to 414. |
| 12. Recoil | ARC9's `Recoil` (every up / side value and the camera kick are multiplied by it) and `VisualRecoil`: 0.844 to 0.316 with a full bar in the strength mode, the same on the client and the server. |
| 13. Energy | 7.50 a shot in the strength mode (6 shots: 45.00), nothing in the other modes, never under 0, nothing with an infinite armor. A melee hit costs nothing (the rule gives it no cost, as for TFA). |
| 14. Speed mode | Draw 1.00 to 0.571 s, holster 0.333 to 0.190 s, ready 5.97 to 3.41 s, melee swing x1.5 (knife 0.40 to 0.267 s, the hit comes at 0.105 then 0.09 s). The lock-out times follow (ARC9 computes them from the same number). The reload stays 2.833 s in every mode, and is 1.417 s with `gry_suit_reload_rate` 2. The fire mode switch and the sprint exit use the raise's rate (ARC9 has no such animation on the famas, so not measured there). |
| 15. Other animations | Sights, inspect, firing, idle and the swing's impact animation are left alone (a test pins the list). |
| 16. Settings | The ARC9 tab: its HUD, and the suit's server settings (the same as TFA's). |
| 17. Shipping | Loader lines, syntax check and loader test, stand-in tests (`tests/cl_compat_arc9_test.lua`, `tests/sv_compat_arc9_suit_test.lua`, ...) and the live checks above. |
| 18. Hooks | ARC9's own global hooks (`ARC9_<Stat>Hook`, `ARC9_Hook_...`), `pcall`, `nil` when nothing changes; nothing of ARC9 is replaced but `ARC9.ShouldDrawHUD` (a wrapper, for the HUD option). |

## HUDs of other addons: left to the player

VJ HUD (health, ammunition, compass and crosshair in `HUDPaint`, hiding the same four game elements) and Crosshair Designer draw a HUD of their own over GryMod's. The patch does **not** hide
either of them through `AddHudSuppressor`: which HUD the player wants is the player's choice, and GryMod never writes another addon's settings. Turn one off in its own options (VJ HUD:
`vj_hud_enabled 0`) or GryMod's HUD in the options of GryMod (`gry_hud 0`). ARC9's own HUD is the one exception, with an option (`gry_arc9_hide_hud`).
## simfphys: how it was written (2026-11-27)

`compat/vehicles/*simfphys.lua` was written from the public source of `simfphys_base` (8d4b1ad) and `simfphys_armed` (53f709f), without simfphys installed, and tested with stand-ins that answer what
its code answers (`tests/sh_compat_simfphys_test.lua`, `sv_...`, `cl_...`). **What is read, not tried in a game**, to check with the real addon:

- the seats: `Player:GetSimfphys()` is the car, `car:GetDriverSeat()` the seat of the driver who sits (`car:GetDriver()` is the remote driver of `weapon_simremote` when there is one);
- the damage: simfphys' hook `!!!_simfphys_fix_vehicle_explosion_damage` cancels every hit that is not `DMG_DIRECT` on a seated player (the filter says "ignore" only while that hook is there); the exploding car
  sets `car.destroyed` and gives each occupant `Health + Armor` as `DMG_DIRECT` (the filter says "bypass" then). A crash (2 or 5 points) is an ordinary hit;
- the forward of the car (`car.Forward`, or `car.VehicleData.LocalAngForward` of its model), the heavy mass (the tanks weigh 8000 to 20000, the armored cars 4800 and less);
- the shells (`simfphys_tankprojectile`, made with `Attacker` and `AttackingEnt` set before the spawn, seen a tick after) and the thrown mine (`Thrown`, `CreatedBy`);
- what is NOT done on purpose: no ring of the radar for the shell and the wreck (the core rings every `util.BlastDamage`; the wreck's gib makes one), no danger of the grenade warning for the shell (it flies at
  about 13 000 units a second: less than a second of warning at the warning's rate), no camouflage ban and no notarget for a seated player (the owner's decision: the suit works in a vehicle).
## LVS: what was read, and what to check with the real addon

Nothing of this was tried with LVS itself: the tests use stand-ins that answer like what was read in `lvs_base` (commit 54c88e2, version 354, `github.com/SpaxscE/lvs_base`). The patch does nothing when the `LVS` table does not
exist, and installs itself when LVS announces itself (`LVS:Initialize`) or at `InitPostEntity`. To check with the real addon (two minutes each):

1. **Hits**: in armor mode, seated in an LVS car, `ply:TakeDamage(20)`: the energy must not move (LVS zeroes the hit, the filter says "ignore"). Destroy the plane the player sits in: he must die (the explosion's `Health() + Armor()` hit goes through the bar).
2. **Radar**: an LVS plane with `SetAI(true)` shows as a flying unit once scanned, and goes alerted / fighting when its target is the player; the car the player sits in is not on his radar; a wreck leaves the radar.
3. **Grenade warning**: a missile locked on the player's vehicle warns him, a missile locked on another vehicle does not. A bomb or an unguided missile warns when it flies at him.
4. **Prompt**: "ENTER VEHICLE" in front of an LVS car (not when it is locked with the key `1`); a car with doors needs two presses (the prompt stays).
5. **Camouflage**: firing an LVS weapon (machine gun, cannon, missile) ends it.
6. **View**: the radar's heading follows the view in a plane, in direct input and in mouse aim.

Not done on purpose (the owner decides): hiding GryMod's radar and status panels while seated in an LVS vehicle (LVS draws its own health at the bottom left and its speed at the bottom right: `AddHudSuppressor`), a `heavy` entry for the hits of LVS vehicles
(a suit put down by a tank shell: an effect Crysis does not have), a warning for `lvs_item_mine`.
## Glide: what is read and what was tried

Glide (https://github.com/StyledStrike/gmod-glide) is a vehicle base made of scripted entities. A vehicle is not an engine vehicle (`IsVehicle()` is false) and the player sits on a
seat that is a child of it (`Player:GetVehicle()` answers the seat, `ply:GlideGetVehicle()` the vehicle). Everything the adapter knows was **read in Glide's code** (commit 5fd934e of
2026-11-26: its wiki documents its functions, not its hooks) and tested with **stand-ins** (`tests/sh_compat_glide_test.lua`, `sv_compat_glide_test.lua`, `cl_compat_glide_test.lua`):
**no test with the real Glide was made yet** (it is not installed). The adapter does nothing without Glide.

| What | How | Setting |
| --- | --- | --- |
| The vehicle of a player, its driver, its kind (air for helicopters and planes, water for boats) | `AddVehicleProvider("glide", ...)` | |
| On the radar once scanned (the rectangle; the flying unit for aircraft; not trailers; not wrecks), heavy for the suit (not motorcycles), the colour of its crew, facing +X | `RegisterTracked` on `base_glide` and its bases | |
| The missiles (`glide_missile` and the ones built on it) in the grenade warning, only for the player they follow | `RegisterTracked` with `danger` (`base`, `ownerOf = ent.attacker`, `warnFor`) | |
| ENTER VEHICLE under the crosshair (not for trailers, dimmed while locked) | `RegisterUsable` | |
| Glide's camera has the view: no view of GryMod, the heading from the drawn view | `AddCameraOwner("glide", ...)` | |
| A player who gets up from a ragdoll keeps his suit (Glide gets him back with `Player:Spawn()`) | `GryMod_CanResetOnSpawn`, with the hook `Glide_PrePlayerUnRagdoll` | |
| A camouflaged driver is not locked on by a missile (half of the camouflage on) | the hook `Glide_CanLockOn` | server: `gry_glide_cloak_lockon` (1) |
| A missile or a shell fired from the hands or the vehicle ends the camouflage (bullets are seen by the engine's hook) | `OnEntityCreated` on the classes built on `glide_missile` / `glide_projectile`, `GryMod.API.ReportAttack` | |
| The name Glide writes over a camouflaged player is `???` | the hook `Glide_PlayerTagColor` | `gry_glide_tag_cloak` (1) |
| Glide's dashboard (the dial in the bottom right) | the hook `Glide_CanDrawHUD` | `gry_glide_hide_hud` (0) |
| The night vision key that Glide also uses (N is its neutral gear) does nothing in its vehicles | `GryMod_CanUseView("nightvision", "key")` | `gry_glide_nv_key` (1) |

Not done, and why: a blast of Glide (`Glide.CreateExplosion`, `util.BlastDamageInfo`) gives no radar ring while the core wraps `util.BlastDamage` only; a bullet that a vehicle fires
with no driver and a turret placed by a player carry their creator as the attacker, so the core's `data.Attacker` rule may end that creator's camouflage.

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
12. **Recoil** reduced with the energy (`RecoilScale`); check the kick stat names of the base (some versions rename them). The HUD crosshair needs nothing per base: it estimates its own opening and applies `RecoilScale` to what a shot adds to it (`FlashCrosshair.KickAfterShot`).
13. **Energy**: each shot takes its cost, a melee hit takes its cost, never under 0, nothing while the armor is infinite.

**Speed mode**
14. **Weapon handling**: draw, holster, raise after a sprint, fire mode switch, melee swing (`SuitWeapons.Rate`). The reload follows `gry_suit_reload_rate` (the original
    game does not speed it up). Lock-out times must follow the animation: a weapon ready too early or too late is a bug.
15. **Inspect and other animations** that have their own timing are left alone unless the original speeds them up.

**Shipping**
16. Settings go on the **Compatibility page, one tab for the base**, added with `GryMod.AddOptionTab("compat", "Name", function(root, Panel) ... end)` (see the top of `lua/grymod/client/cl_options_tabs.lua`; the tab keeps to about ten settings, and the filter field of the page finds them by their label and explanation). The administrators' settings go through the white list (`GryMod.AdminOption(Panel, ..., {into = root})`); the ones that are the same for every base are in the Suit effects tab. Each one is optional.
17. Loader lines (`grymod_shared.lua`), `python tools/check_lua_syntax.py`, `python -m unittest tools.test_loader_coverage`, tests with stand-ins that pin the markers and
    what is called, plus a live check on the real base, numbers written in the commit message.
18. Every hook the patch adds is cheap (early return), runs under `pcall` where the base calls it, and answers `nil` when nothing changes.
19. Document it in the table at the top of this file and in [api.md](api.md) if the API grew.

## VJ Base: what the adapter does and why

VJ Base keeps its own opinion of who is an enemy and tells the engine late, so what GryMod reads from the engine (`Disposition`) is not what VJ means. Measured in a real game
(VJ Base 3.3.0, the 3.2.0 release has the same code for all of this):

- **A hostile that has not seen the player is `D_NU`** (or `D_VJ_INTEREST`, 100): the radar saw every VJ enemy as neutral until it fought. The relation provider `GryMod VJ Base adapter`
  answers from VJ's rules: its memory of the player (`RelationshipMemory[ply][VJ.MEM_OVERRIDE_DISPOSITION]`), a class shared with the player (`VJ_NPC_Class`, `CanAlly`), its behaviour
  (neutral, passive and nature NPCs are neutral), and the engine's own `D_HT` / `D_LI` when they are clear. The answer is kept for 0.2 s per player and NPC. It is added to the chain
  only when VJ Base is there.
- **A camouflaged player (`FL_NOTARGET`) is `D_NU` to every VJ NPC, friends included**, and a follower that is not `D_LI` at its next Think stops following (measured: within 0.25 s).
  A priority of 99 on the relation does not hold: VJ writes it again 0.75 s later. A Disposition set on the NPC's own table is never called (an engine method is found first). So the
  adapter replaces the NPC metatable's `Disposition` **only while a camouflaged player has VJ followers**, and it answers `D_LI` for that player only (and only for what the engine says is
  `D_NU` or `D_ER`); the original is put back when the camouflage ends or the player dies or leaves. A player cannot start a follow while camouflaged (VJ refuses a `D_NU`).
- **The weapon in the hands**: `weapon_vj_*` fire bullets through `FireBullets` (the server sees them), but a melee weapon and a launcher (`Primary.DisableBulletCode`) do not. The weapon
  entity gets one wrapper on `PrimaryAttack` (when the player picks it up) that calls `GryMod.API.ReportAttack` after the weapon's own code. The stock VJ melee weapons are for NPCs only
  (`MadeForNPCsOnly`: the player's copy is removed), the packs have their own.
- **The explosions** of VJ's projectiles are drawn as effects and dealt by `VJ.ApplyRadiusDamage` (no `env_explosion`, no `util.BlastDamage`): the class goes into `Radar.ExplosiveClasses`
  the first time one is made, with its `RadiusDamageRadius`. (The death blasts of VJ's tanks and helicopters are `util.BlastDamage`: the core rings them.)
- **The melee slow** (`MeleeAttackPlayerSpeed`: the Cry of Fear, L4D and No More Room in Hell packs, the Zombine) stores the player's speeds and gives them back 5 s later; a change of
  mode meanwhile put the new mode's speeds on the player, so the stored ones are refreshed at each mode change.
- **VJ HUD** (the official plugin, `vj_hud_enabled`) draws its own crosshair, ammunition and health beside GryMod's, and hides the game's HUD. Nothing is changed: it is a setting of another
  addon (turn one of the two HUDs off).

The classes that the shared part registers are the ones the scripted entities declare (`scripted_ents.GetMember(class, "VJ_ID_Grenade")`), scanned once at the first frame: the same list on
both realms (measured: 5 grenades, 3 missiles with Half-Life Resurgence). A hornet, an orb or a stomp is tagged as a danger by VJ but is not an explosive: it is left out.
