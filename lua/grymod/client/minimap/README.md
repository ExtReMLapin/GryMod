# lua/grymod/client/minimap and lua/grymod/client/map

`minimap/` makes and draws the map of the level behind the radar. `map/` is the big map (the PDA, opened with M). Both draw the same tiles. The behaviour, the settings and the limits are in [`docs/minimap.md`](../../../../docs/minimap.md); this page only says which file does what.

## minimap/

| File | Role |
| --- | --- |
| `settings.lua` | The convars of the minimap, clamped, never nil. |
| `floors.lua` | Which level (slice of height) the player is on, from rays cast upward. |
| `capture.lua` | One render of one tile, seen from above, as BGRA bytes. |
| `dxt1.lua` | Compresses a tile to DXT1, a few rows at a time so that no frame is blocked. |
| `vtf.lua` | Writes the VTF and VMT files the engine loads as a material. |
| `cache.lua` | The naming and geometry of tiles, and the store on disk (`data/grymod/minimap/<key>/`). |
| `gen.lua` | Decides which tiles are made, in what order, within the time budget of a frame. |
| `preload.lua` | The list of tiles to prepare before the player gets there. |
| `view.lua` | Draws the tiles under the radar's contacts with the radar's own transformation. |

The node graph reader `AIN` is shared with the server (`lua/grymod/sh_ain.lua`).

## map/

| File | Role |
| --- | --- |
| `panel.lua` | The big map's panel: opens and closes it, takes the input, glues the other modules. |
| `frame.lua`, `bounds.lua`, `zoom.lua` | The maths between the world and the window, the limits of the pan, the zoom rules. Pure code, tested without a game. |
| `pyramid.lua`, `tiles.lua`, `store.lua` | Which definition and which tiles the zoom needs, where the pictures come from, and the in-memory pool of slots. |
| `chrome.lua` | The frame of the Crysis PDA, drawn from the converted movie `HUD_PDA_Map`. |
| `contacts.lua`, `markers.lua`, `waypoints.lua` | The radar's contacts on the map, the markers other addons add, and the player's own objective points. |
| `fx.lua` | The look of the map while tiles are being made. |
| `settings.lua`, `options.lua` | The big map's convars and its tab in the options menu. |
