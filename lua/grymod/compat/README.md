# lua/grymod/compat

Patches that make other addons work with GryMod. **Only TFA and ARC9 are really supported** (written with the real weapons, tried in a game, covered by tests). Every other patch here is best effort: the minimum, little tested, and it may break. They all follow one rule: they use the public API (`GryMod.API`) and the other addon's own public functions and hooks, never GryMod's internals, so that GryMod can change inside without breaking them. Each patch does nothing when the addon it is for is not installed, and warns the administrators in the console when a function it needs has disappeared (`GryMod.API.WarnPatchMissing`).

| Folder | For |
| --- | --- |
| `hl2/` | The stock game: the 19 stock weapons (fire mode, ammunition, what the secondary fire is), the stock tracked entities and usable things, the suit's effect on the stock melee weapons. |
| `weapons/` | Weapon bases: TFA, ARC9, ArcCW, CW 2.0, FA:S 2, M9K and Draconic Base. Parts, menus, fire modes and what the suit does to their weapons. |
| `npc/` | NPC bases: VJ Base, DrGBase, ZBase. |
| `vehicles/` | LVS, Glide, simfphys. |
| `view/` | Third person cameras, legs and body addons (Enhanced Camera 2), VManip, other night visions. |
| `tools/` | Wiremod, JMod, PAC3, prop protection addons, GBombs 5, M9K Specialties. |

What each patch does, what was tried in a real game and what was only read in the other addon's source, the rule for damage and fall damage, and the checklist for supporting a new weapon base are in [`docs/compat.md`](../../../docs/compat.md). A new patch follows the section "Adding a patch" there, with a test in `tests/`.
