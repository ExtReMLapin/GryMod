# Views reference

This page documents the client side functions of `GryMod.API` that let another addon tell GryMod what is on the screen: the models a weapon or a player draws on its own, the menu of a weapon base, a weapon screen that must stay plain, a camera that owns the view, and the elements of the HUD to hide. All of them are defined in `lua/grymod/client/cl_api.lua` and exist on the client only. The patches for TFA, ARC9, ArcCW, CW 2.0, FA:S 2, JMod, LVS, Glide, DrGBase and VJ Base in `lua/grymod/compat/` use them, and [compat.md](../compat.md) lists what each patch does.

Every callback of this page runs under `GryMod.API.SafeCall`. An error in a callback counts as no answer for that call, and the fifth error in a row switches the callback off until the same id or key is added again. The id or key of every `Add...` function is a string of at least 1 character, and adding an id that already exists replaces its function, keeps its place in the order, and re-arms it. Each `Add...` function returns `true` when the callback is stored and `false` when the id is not a non-empty string or the callback is not a function. Each `Remove...` function returns `true` when it removed something and `false` otherwise. Providers and owners are asked in the order they were added.

## Weapon parts

A weapon base can draw models that are not the view model, such as a sight, a silencer or a laser. The engine does not know them, so the camouflage would leave them plain over a camouflaged gun. A weapon parts provider tells GryMod which models a weapon draws. GryMod keeps no list: the providers are asked each time the parts are needed, so an attachment that the player changes while camouflaged is in the next frame's list. `GryMod.API.Has("weaponparts")` is true.

### GryMod.API.MAX_WEAPON_PARTS

A number, 16: the most parts `GetWeaponParts` keeps for one weapon. Parts beyond it are dropped.

### GryMod.API.AddWeaponPartsProvider(id, fn)

Client. Adds a function that appends the models a weapon draws itself.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the provider. | no |
| `fn` | function | `fn(weapon, out)`. `weapon` is the weapon entity. `out` is a table to which the function appends client side model entities with `out[#out + 1] = model`. The return value is ignored. | no |

Returns `true` or `false` as described at the top of the page.

`out` already holds the parts of the providers asked before. The function appends and must leave the entries that are there. A provider answers nothing for a weapon that is not its own, by returning without appending. What a provider appends is checked after it returns: an entry that is not a valid entity is dropped, and entries past `MAX_WEAPON_PARTS` are dropped. When the function raises an error, everything it appended during that call is dropped too.

```lua
GryMod.API.AddWeaponPartsProvider("my_addon", function(weapon, out)
	if weapon:GetClass() ~= "my_weapon" then return end

	out[#out + 1] = weapon.SightModel
end)
```

### GryMod.API.RemoveWeaponPartsProvider(id)

Client. Removes a provider.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name given to `AddWeaponPartsProvider`. | no |

Returns `true` when the provider existed. Its error count is cleared.

### GryMod.API.GetWeaponParts(weapon, out)

Client. Asks every provider for the models of a weapon and gathers the answers.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `weapon` | Weapon | The weapon entity. | no |
| `out` | table | The table to fill. It is emptied first, so the same table can be reused from one call to the next. | yes, a new table |

Returns `out` and the number of parts in it. When `weapon` is not a valid entity, `out` is emptied and the count is 0.

The camouflage calls it at each frame it draws the view model, in first person, and covers each part with the same layers as the view model. Keep the table of the caller and pass it each time, as the camouflage does, so that no table is made per frame.

## Player parts

A player can wear models that the engine does not draw as part of him, such as armor, a backpack or an outfit. A player parts provider tells GryMod which they are, so the camouflage of that player covers them with the same layers and the same fade as his body. `GryMod.API.Has("playerparts")` is true. An addon that draws its parts by itself can hide them with the hook `GryMod_CloakChanged(ply, on, level)` instead.

### GryMod.API.MAX_PLAYER_PARTS

A number, 16: the most parts `GetPlayerParts` keeps for one player.

### GryMod.API.AddPlayerPartsProvider(id, fn)

Client. Adds a function that appends the models a player wears.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the provider. | no |
| `fn` | function | `fn(ply, out)`. `ply` is the player. The function appends client side model entities to `out`. The return value is ignored. | no |

Returns `true` or `false` as described at the top of the page.

The checks are the same as for the weapon parts: only valid entities are kept, at most `MAX_PLAYER_PARTS`, and a provider that errors gives nothing for that call. The camouflage asks at each frame, for each camouflaged player who is drawn in detail, and only when such a player exists. The function must be cheap. The patch for JMod armor (`lua/grymod/compat/tools/cl_jmod.lua`) is a working use.

### GryMod.API.RemovePlayerPartsProvider(id)

Client. Removes a provider.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name given to `AddPlayerPartsProvider`. | no |

Returns `true` when the provider existed. Its error count is cleared.

### GryMod.API.GetPlayerParts(ply, out)

Client. Asks every provider for the models a player wears.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player. | no |
| `out` | table | The table to fill. It is emptied first. | yes, a new table |

Returns `out` and the number of parts. When `ply` is not a valid entity, `out` is emptied and the count is 0.

## Weapon menus

Some weapon bases have a menu of their own to inspect and change the weapon in hand, such as the attachments or the ammunition. The weapon icon of the suit's quick menu opens that menu, and the icon can be chosen only when the weapon in hand has one. GryMod knows no weapon base: a weapon menu provider answers, for a weapon, with the function that opens its menu. `GryMod.API.Has("weaponmenu")` is true.

### GryMod.API.AddWeaponMenuProvider(id, fn)

Client. Adds a function that gives the opener of a weapon's menu.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the provider. | no |
| `fn` | function | `fn(weapon)`. It receives the weapon entity and returns a function `opener(weapon)` that opens the menu, or `nil` when the weapon is not its own or has no menu to open. | no |

Returns `true` or `false` as described at the top of the page.

The quick menu asks the providers while it is open, so `fn` must be cheap and must not open anything itself. Only a function counts as an answer. Any other return value, and an error, mean no menu from this provider, and the next provider is asked.

```lua
GryMod.API.AddWeaponMenuProvider("my_addon", function(weapon)
	if weapon:GetClass() ~= "my_weapon" then return nil end

	return function(wep) wep:OpenMyMenu() end
end)
```

### GryMod.API.RemoveWeaponMenuProvider(id)

Client. Removes a provider.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name given to `AddWeaponMenuProvider`. | no |

Returns `true` when the provider existed. Its error count is cleared.

### GryMod.API.GetWeaponMenu(weapon)

Client. Gives the opener of the menu of a weapon.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `weapon` | Weapon | The weapon entity. | no |

Returns the opener function of the first provider that gave one, or `nil` when no provider has a menu for this weapon or `weapon` is not a valid entity. The quick menu uses the result to grey the weapon icon.

### GryMod.API.OpenWeaponMenu(weapon)

Client. Opens the menu of a weapon, when it has one.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `weapon` | Weapon | The weapon entity. | no |

Returns `false` when the weapon has no menu. Otherwise it runs the opener as `opener(weapon)` under `pcall` and returns what `pcall` returns: `true` (followed by whatever the opener returned) when the opener ran, and `false` and the error message when the opener raised an error. An error of the opener is caught and does not reach the player's input.

## Plain views

Some weapon bases show the weapon on a screen of their own. ARC9's customization menu turns the gun towards the player over a dark and blurred picture of the world. The first person camouflage copies the picture behind the gun before the weapon draws, so in such a screen it would show a world that is not the one the player sees, and the player needs to see the parts he picks. A plain view provider says that the weapon's own screen has the view, and the effects then draw the weapon plain. `GryMod.API.Has("plainview")` is true.

### GryMod.API.AddPlainViewProvider(id, fn)

Client. Adds a function that says whether a weapon's own screen has the view.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name of the provider. | no |
| `fn` | function | `fn(weapon)`. It receives the weapon entity and returns `true` while the weapon's own screen has the view. Any other return value is a no. | no |

Returns `true` or `false` as described at the top of the page.

The camouflage asks at every frame it is on in first person, so `fn` must be cheap. The patch for ARC9 (`lua/grymod/compat/weapons/cl_arc9_menu.lua`) answers `true` while its customization menu is open or still moving in or out.

### GryMod.API.RemovePlainViewProvider(id)

Client. Removes a provider.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | string | The name given to `AddPlainViewProvider`. | no |

Returns `true` when the provider existed. Its error count is cleared.

### GryMod.API.IsPlainView(weapon)

Client. Says whether a weapon's own screen has the view.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `weapon` | Weapon | The weapon entity. | no |

Returns `true` when a provider answered `true` for this weapon. Returns `false` when none did, when every provider that was asked failed, or when `weapon` is not a valid entity. The first provider that answers `true` ends the search.

## Camera owners and the view

An addon can give the player a camera of its own: a drone, a security camera, a cinematic, the special view of a vehicle. GryMod must leave such a view alone. While a camera owner answers `true`, the binoculars give no view (no field of view, no sway) and do not read the game's zoom key, the suit's own zoom closes and does not open, and the heading of the radar, the compass and the damage arrows follows the view that is really drawn. `GryMod.API.Has("cameraowner")` is true.

### GryMod.API.AddCameraOwner(key, fn)

Client. Adds a function that says whether the addon's camera has the view.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `key` | string | The name of the owner. | no |
| `fn` | function | `fn(ply)`. It receives the player that is asked about, the local player in every call GryMod makes, and returns `true` while the addon's camera has the view. Any other return value is a no. | no |

Returns `true` or `false` as described at the top of the page.

`fn` is asked once for each frame, and the answer is kept for that frame for the player that was asked. With no owner at all, `IsCameraOwned` returns `false` at the cost of reading a table length. Adding or removing an owner drops the kept answer. The patches for LVS, Glide, DrGBase, ZBase, VJ Base and the third person addons are working examples, for instance `lua/grymod/compat/npc/cl_drgbase.lua`.

```lua
GryMod.API.AddCameraOwner("my_addon", function(ply)
	return MyAddon.CameraIsUp == true
end)
```

### GryMod.API.RemoveCameraOwner(key)

Client. Removes an owner.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `key` | string | The key given to `AddCameraOwner`. | no |

Returns `true` when the owner existed. Its error count and the kept answer are cleared.

### GryMod.API.IsCameraOwned(ply, fresh)

Client. Says whether another addon's camera has the view of a player.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `ply` | Player | The player, in practice the local player. | no |
| `fresh` | boolean | `true` asks the owners again in the same frame instead of using the kept answer. It exists for tests. | yes, `false` |

Returns `true` while any owner answers `true`, `false` otherwise. The answer is kept for the frame number and the player of the last call, so asking about a second player in the same frame asks the owners again.

### GryMod.API.GetViewFov()

Client. Gives the field of view of the view that was really drawn.

`Player:GetFOV` is the player's own field of view and does not follow what a `CalcView` hook of an addon gives, such as a vehicle's zoom, a drone's camera or the binoculars' stages. This function reads the setup of the last main render, `render.GetViewSetup().fov_unscaled`.

Returns the horizontal field of view in degrees, as `CalcView` gives it (for a 4:3 screen, like `Player:GetFOV`), or `nil` when the render does not know it yet, as in the first frames of a map, or when the value is not a positive number. It takes no argument and can be called from any hook. The radar's view cone uses it. `GryMod.API.Has("viewfov")` is true.

## HUD suppressors

An addon that draws a HUD of its own, such as a vehicle dashboard, a drone screen or a cinematic, can hide an element of GryMod's HUD while its own is up. A suppressor says, for an element, whether to hide it now. A hidden element is not drawn and does nothing. The player's own switch `gry_hud_<name>` is never written, so the element comes back when the suppressor answers no. A suppressor cannot show an element that the player switched off. `GryMod.API.Has("hudsuppress")` is true.

The element names are the `name` fields of `GryMod.HUDOptions.List`: `status`, `radar`, `radarunits`, `radarhex`, `crosshair`, `damage`, `hit`, `grenade`, `binoculars`, `quickmenu`, `boot`, `damagefx`, `messages`, `usehint`, `pickups`, `corners`, `overheat`, `weaponlist`, `objectives`, `nightvision`, `bar_smooth`.

### GryMod.API.AddHudSuppressor(key, fn)

Client. Adds a function that says whether an element of the HUD is hidden.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `key` | string | The name of the suppressor. | no |
| `fn` | function | `fn(element, ply)`. `element` is an element name from the list above and `ply` is the local player. It returns `true` to hide the element. Any other return value leaves it. | no |

Returns `true` or `false` as described at the top of the page.

`fn` is asked once for each frame and element, and the answer is kept for the frame. With no suppressor, `IsHudSuppressed` returns `false` at the cost of reading a table length. The function receives every element name, so it must answer `false` for the ones it does not hide.

```lua
GryMod.API.AddHudSuppressor("my_addon", function(element, ply)
	return MyAddon.DashboardIsUp and (element == "radar" or element == "crosshair")
end)
```

### GryMod.API.RemoveHudSuppressor(key)

Client. Removes a suppressor.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `key` | string | The key given to `AddHudSuppressor`. | no |

Returns `true` when the suppressor existed. Its error count is cleared, and the answers kept for the frame are dropped.

### GryMod.API.IsHudSuppressed(element, fresh)

Client. Says whether a suppressor hides an element of the HUD.

| Name | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `element` | string | The element name. | no |
| `fresh` | boolean | `true` asks the suppressors again in the same frame. It exists for tests. | yes, `false` |

Returns `true` when any suppressor answered `true` for this element, `false` otherwise. The name is not checked against the list: a name that no element has gets `false` unless a suppressor hides it. `GryMod.HUDOptions.Enabled(name)` calls this function after it has read the player's switch, and the HUD elements ask `Enabled`.
