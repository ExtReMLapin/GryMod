# Core: presence, version, patch warnings and safe calls

This page holds the parts of `GryMod.API` that the interface needs for itself: the presence and version test, the list of optional parts, the warning that a compatibility patch makes when it cannot do its job, and `SafeCall`, through which GryMod runs every callback that an addon gives it. All of it is defined in `lua/grymod/sh_api.lua` and exists in both realms. The guide with the reasoning is [api.md](../api.md); the first steps are in [README.md](../README.md#is-grymod-there-and-which-version).

## Presence and version

### GryMod.API.Version

Shared. The version of the interface, an integer. It is `1` today.

The number goes up only when a change breaks existing callers. A new function or a new optional part never changes it: test those with `GryMod.API.Has`. `GryMod.GetInterfaceVersion()` returns the same number. `GryMod.Version` is another value: the version of the addon as text, `"dev"` in a checkout, meant for display only.

Test for GryMod from the `Initialize` hook, because the autorun files of all addons run in alphabetical order and a file that sorts before `grymod_shared.lua` runs before GryMod exists. `GRYMOD_INSTALLED` is `true` once `sh_api.lua` has run.

```lua
hook.Add("Initialize", "my_addon_gry_check", function()
	if GRYMOD_INSTALLED and GryMod.API and GryMod.API.Version >= 1 then
		-- version 1 of the interface can be used
	end
end)
```

### GryMod.API.Has(feature)

Shared. Tells whether an optional part of the interface exists in the realm that asks.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `feature` | string | The name of the part, for example `"hitfilter"`. | No |

Returns `true` when the part is registered, `false` otherwise. A value that is not a string gives `false`; nothing is raised.

The answer depends on the realm, because each part registers itself when its file is loaded and some files exist on one side only. These names exist today:

| Where | Names |
| --- | --- |
| Both realms, set by `sh_api.lua` | `suit`, `relation`, `hudevents`, `safecall` |
| Both realms, set by their own file | `weapons`, `class`, `creature`, `tracked`, `vehicles`, `usable`, `cloaklevel`, `messages`, `objectives` |
| Server only | `attackreport`, `shotreport`, `suitnoise`, `hitfilter`, `awareness`, `campaign` |
| Client only | `weaponparts`, `playerparts`, `weaponmenu`, `plainview`, `cameraowner`, `hudsuppress`, `clientrelation`, `usablefilter`, `viewfov`, `viewveto`, `pickups`, `radarmarkers`, `weaponlist`, `bigmap` |

The four names of the first row are set when the shared file loads, so they are `true` on the client too, although the suit commands and the relation chain exist on the server only. A name in the table says that the file of the part was loaded. It does not promise that every function of the topic exists in that realm.

### GryMod.API.AddFeature(feature)

Shared. Registers an optional part, so that `Has(feature)` answers `true` from then on.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `feature` | string | The name of the part. | No |

Returns nothing. The name is not checked, and there is no call that removes a part. GryMod's own files call this at load; the names of the table above are the ones that exist. A part is added in the realm where the call runs only.

## Warnings of the compatibility patches

A patch in `lua/grymod/compat/` replaces a function of another addon. When that addon is installed but the function is gone, the patch stays off, and the owner of the game has to be told. The patches in the repository call `WarnPatchMissing` for it (see [compat.md](../compat.md#the-rule)).

### GryMod.API.WarnPatchMissing(addon, what, stillMissing)

Shared. Reports that a patch for `addon` could not find `what`: one line in the console at once, and the same text in the chat five seconds later (the game's chat is not ready at the very start). On the server the chat goes to the administrators (`Player:IsAdmin`), on the client to the local player, drawn in orange.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `addon` | any | The name of the other addon. It goes through `tostring`. | No |
| `what` | any | What was looked for, for example `"DRC.EMP"`. It goes through `tostring`. | No |
| `stillMissing` | function | A test of the absence, asked one second after the call. | Yes. A value that is not a function counts as no test. |

Returns a boolean.

- Without a usable `stillMissing`, the warning is made at once and the call returns `true`. It returns `false` when the same `addon` and `what` were already reported.
- With `stillMissing`, the call returns `false` whatever happens, since the answer comes later. One second after the call, `stillMissing()` runs under `pcall`, and the warning is made only when it returns exactly `true`. An error in it, or any other value, makes no warning. This is for the case where the other addon defines its function after the file of the patch has loaded.

A warning is made once for each pair `addon` and `what`. The chat gives each text once to each player. An administrator who joins after a warning was made gets all the texts made so far, eight seconds after his first spawn (`PlayerInitialSpawn`), if he is still an administrator then.

```lua
GryMod.API.WarnPatchMissing("My Weapon Base", "MyBase.OnFire", function()
	return istable(MyBase) and not isfunction(MyBase.OnFire)
end)
```

### GryMod.API.ForgetPatchWarnings()

Shared. Forgets which warnings were made and the texts kept for administrators who join later, so that the same warning can be made again.

Takes no parameter and returns nothing. Only the tests of the repository call it. A text already shown stays in the console and in the chat.

## Safe calls

GryMod runs the callbacks of other addons (relation providers, hit filters, HUD event handlers, the providers of the client) through `SafeCall`. A callback that raises an error is caught and never reaches the HUD. The fifth error in a row disables the callback. The state is kept by `id`, in one table shared by all callers, so an id of your own should not start with a prefix that GryMod uses (`provider:`, `hitfilter:`, `hudevent:`, `debugcmd:`). The guide is [api.md](../api.md#safe-calls).

### GryMod.API.SafeCall(id, fn, ...)

Shared. Calls `fn(...)` under `pcall` on behalf of the callback `id`.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | any | The key that names the callback. A string is usual. | No |
| `fn` | function | What to call. | No |
| `...` | any | The arguments given to `fn`. | Yes |

Returns what `pcall` returns: `true` followed by the results of `fn`, or `false` and the error. Two answers come from `SafeCall` itself and never run `fn`:

- `false, "disabled"`, when the callback `id` is disabled.
- `false, "not a function"`, when `fn` is not a function. This is not counted as an error of the callback.

An error adds one to the count of `id`; a call that succeeds sets the count back to zero. When the count reaches `GryMod.API.SafeCallLimit`, `id` is disabled and one line goes to the console:

```
GryMod API: provider 'my_addon' disabled after 5 errors: lua/my_addon.lua:12: attempt to ...
```

An id of the form `kind:name` (letters and digits, a colon, a name) is told as `kind 'name'`. Any other id is told as `'id'`. After that the callback stays disabled until `SafeCallReset(id)` runs. The functions that register callbacks (`AddRelationProvider`, `AddHitFilter` and their siblings) call it when the same id is registered again.

```lua
local ok, result = GryMod.API.SafeCall("my_addon:score", MyAddon.Score, ply)

if not ok then
	-- result is the error text, or "disabled"
end
```

### GryMod.API.SafeCallLimit

Shared. The number of errors in a row after which a callback is disabled: `5`.

It is a read-only value in practice. `SafeCall` compares against a local copy made when the file loaded, so assigning another number to this field changes nothing.

### GryMod.API.SafeCallDisabled(id)

Shared. Tells whether the callback `id` is disabled.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | any | The same key that was given to `SafeCall`. | No |

Returns `true` when `SafeCall` disabled it and nobody reset it, `false` otherwise (also for an id that was never used).

### GryMod.API.SafeCallReset(id)

Shared. Arms the callback `id` again: its count of errors goes back to zero and it is no longer disabled.

| Parameter | Type | Meaning | Optional |
| --- | --- | --- | --- |
| `id` | any | The same key that was given to `SafeCall`. | No |

Returns nothing. It is safe to call for an id that was never used.
