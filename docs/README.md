# GryMod documentation for developers

GryMod is a Crysis-style nanosuit and HUD for Garry's Mod. These pages are for the addons that plug into it. There are two kinds: guides, which explain how a part works and give recipes, and references, which list every function, hook and networked value with its arguments and behaviour.

## References

| Page | What it lists |
| --- | --- |
| [hooks.md](hooks.md) | Every hook GryMod fires: realm, arguments, what a return value means, when it fires. |
| [networking.md](networking.md) | The networked variables and the network messages. The messages are the addon's internal protocol and can change without the interface version going up. |
| [reference/core.md](reference/core.md) | The interface's plumbing: version, feature test, safe calls, patch warnings. |
| [reference/suit.md](reference/suit.md) | Energy, mode, malfunctions, hit filters, and the reports other addons send (attacks, shots, radar pings). |
| [reference/entities.md](reference/entities.md) | Relations, class and creature providers, tracked entities and dangers, vehicles. |
| [reference/usable.md](reference/usable.md) | The use prompt: usable things, their text and icons, filters. |
| [reference/weapons.md](reference/weapons.md) | The weapon registry and its adapters. |
| [reference/views.md](reference/views.md) | Client side: weapon and player parts, weapon menus, plain views, camera owners, HUD suppressors. |
| [reference/hud.md](reference/hud.md) | HUD events, text lines, pickup icons, radar marker sources, debug commands. |
| [reference/objectives.md](reference/objectives.md) | Objectives and the campaign data. |

A test (`tools/test_docs_coverage.py`) checks that every hook, networked variable, network message and API entry of the code has an entry in these pages, and that no entry names something that does not exist.

## Guides

| Guide | What it covers |
| --- | --- |
| [api.md](api.md) | The extension API as a guide: the presence and version test, safe calls, the suit's commands and events, the relation chain, the HUD events, and the field tables of the weapon and entity registries. |
| [compat.md](compat.md) | The compatibility patches: which addons are really supported, the rules a patch follows, how each was checked, and the checklist for a new weapon base. |
| [entities.md](entities.md) | The tracked entities: how to make your NPCs, nextbots, vehicles, mines and projectiles show properly on the binoculars, the radar and the grenade warning, how the ally, neutral and hostile relation is extended, and the limits that exist today. |
| [weapons.md](weapons.md) | The weapon registry: how to describe a weapon (from the SWEP or from the registry), what the HUD shows for it, the stock Half-Life 2 weapons, and what exists for third-party weapon bases. |
| [events.md](events.md) | The HUD events: every effect of the interface (animation and sound together), how to play one, how to add your own, the effects test window and the real commands it can run. |
| [minimap.md](minimap.md) | The minimap: the real map behind the radar, how it is made and cached, its settings, the modules, events and tests, and its limits. |

## Is GryMod there, and which version?

Test it before you call anything, and do it from the `Initialize` hook: the autorun files of all addons run in alphabetical order,
so a file that sorts before `grymod_shared.lua` would run before GryMod is loaded.

```lua
-- lua/autorun/my_addon.lua (shared)
hook.Add("Initialize", "my_addon_gry_check", function()
	if GRYMOD_INSTALLED and GryMod.API and GryMod.API.Version >= 1 then
		print("GryMod is here, interface version " .. GryMod.API.Version .. ", addon version " .. tostring(GryMod.Version))
	else
		print("GryMod is not installed")
	end
end)
```

`GryMod.API.Version` is an integer that goes up only when something breaks. Optional parts are tested by name with
`GryMod.API.Has("weapons")`, `Has("tracked")`, `Has("suit")`... and never change the version number. `GryMod.Version` is the addon
version as text (`"dev"` in a checkout): use it for display only.
