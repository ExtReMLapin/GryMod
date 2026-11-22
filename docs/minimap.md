# Minimap

The radar of the suit shows its contacts on a real map of the level. The map is rendered once from the game's own geometry, seen from
straight above, kept on disk, and drawn under the contacts with the same transformation as the contacts (the same scale, the same
rotation with the player's view, the same frame). Everything is client side and optional: `gry_minimap 0` turns it off, and a failure in
the minimap never keeps the radar from drawing.

## How it works

1. **The level follows the player.** Every second, or when the feet move more than 48 units, five rays go straight up from 72 units over
   the feet (one at the centre, four 48 units away along the world axes). The highest ceiling they hit decides how tall the slice is. Only
   the map's own brushes count as a ceiling: the rays go through props. If the centre ray sees the sky, or the ceiling is more than 512
   units up, the player is outside and the slice covers the whole height of the world (rocks, dunes and roofs show up).
2. **A slice of height is rendered.** The level is a slab from 56 units under the floor up to the ceiling class (88, 120, 160, 224, 320
   or 448 units over the floor). The slab is rendered in an orthographic view from above into a render target, one square tile at a time
   (`gry_minimap_tile` pixels wide). The tiles are laid on a fixed grid of the map, so the same tile is never made twice.
3. **What the map did not create is hidden.** During a capture every visible entity for which `Entity:CreatedByMap()` is false (props a
   server added, players, effects) is hidden, plus the halos, the sky box, the view model and the fog. They are restored right after,
   also when an error happens. The cache holds the map as it ships.
4. **The tile is compressed and written.** The picture is compressed to DXT1 with one bit of alpha (a void pixel is transparent) in
   pure Lua, a few rows at a time so that no frame is blocked, and written as a VTF 7.2 texture plus a VMT material in
   `data/grymod/minimap/<key>/`.
5. **The tile is loaded as a material.** `Material("../data/grymod/minimap/<key>/<tile>")` loads it (at most 64 are held in memory, the
   least recently used are dropped).
6. **The map is drawn.** Each visible tile is one textured quad, clipped to the frame of the radar and sent through the radar's own
   matrix, in up to three passes, from the back to the front: (1) the **outside**, if wanted: the open level of the map (the whole
   height of the world: terrain, rocks, roofs), tinted a grey blue, very faint; (2) the **floor below**, if wanted, tinted blue and
   faded; (3) the current level, white. The faded passes show through the empty parts of the floors in front of them, and the outside
   also shows through the solid parts that the slice cut (earth, thick walls), where the current floor is dark. The contacts go on top.
   When the player is already outdoors the current level is the open level, so there is no outside pass and no floor below.

The work is done by a `PostRender` hook that exists only while tiles are missing. When the queue is empty the hook is removed: there is no
permanent per-frame hook. A capture costs about 7 ms, so at most one is made per frame, and the rest of the frame budget goes to the
compression.

## Settings

All of them are saved client convars. Whatever is typed in the console, the code reads a value inside the range (a text that is not a
number gives the default).

| Convar | Default | Range | Effect |
| --- | --- | --- | --- |
| `gry_minimap` | 1 | 0 or 1 | Draw the map behind the radar. |
| `gry_minimap_definition` | 3 | 1 to 16, whole numbers | Pixels per metre of the tiles. More is sharper, takes longer to make and takes more disk. |
| `gry_minimap_tile` | 1024 | 512, 1024 or 2048 (another number goes to the nearest) | Size of one tile in pixels. At 3 pixels per metre a 1024 tile covers about 341 m. Small tiles are quick to make, big tiles are fewer. |
| `gry_minimap_budget_ms` | 6 | 1 to 30 | Milliseconds per frame the generator may use. One capture (about 7 ms) may go over it. |
| `gry_minimap_below` | 40 | 0 to 100, whole numbers | Opacity in percent of the floor below, seen through the empty parts of the current floor. 0 turns the floor below off (and it is not generated). |
| `gry_minimap_outside` | 30 | 0 to 100, whole numbers | Opacity in percent of the outside (the open level, the whole height of the map) behind the floors, drawn under the floor below. 0 turns it off (and it is not generated). It is drawn only when the player is inside; outdoors the current level is already the open level. |
| `gry_minimap_cache_mb` | 256 | 16 to 4096 | Size limit of the cache of one map, in megabytes. |
| `gry_radar_range` | 75 | 5 to 100 | Existing radar setting: the distance the radar shows, in metres. It is the distance; the definition above is the sharpness. At 5 m the map is a close-up: raise `gry_minimap_definition` (for example 12 to 16 pixels per metre) for a sharp picture. |

The map always turns with the player's view, like the contacts: there is no fixed-north mode.

Changing the definition or the tile size makes a new set of tiles (the name of a tile contains both), so the first change generates
the map again. The old tiles stay in the cache until the size limit removes them.

The same options are in the options menu, under "Minimap", with a button "Clear the minimap cache".

## The cache

- **Where:** `garrysmod/data/grymod/minimap/<key>/`. One directory per map, with `index.json` and, for each tile, a `.vtf` and a `.vmt`.
- **Key:** the map name, the size in bytes of `maps/<map>.bsp`, and the version of the format, written in lower case with every
  character outside `a-z 0-9 _` turned into `_`, for example `gm_example_6540988_v2` (the number is only an example). A map that is updated has another size, so it
  gets a new directory, and the old directories of the same map name are deleted at the first request after the map loads.
- **Tile name:** `t_<level>_<tx>_<ty>_<res>_<ppm>`, a negative number is written with an `n` in front (`n3`).
- **Size limit:** `gry_minimap_cache_mb`, for the directory of the current map. Above the limit the least recently used tiles are
  deleted, until the size is at 90 % of the limit. The check runs at the first request of a map and then every 64 tiles made. The
  tile that was just written is never removed.
- **Clearing it:** press "Clear the minimap cache" in the options menu (it clears the current map and the map is made again as you
  play), or delete the directory `garrysmod/data/grymod/minimap/<key>/` (or all of `garrysmod/data/grymod/minimap/`) while the game is
  closed.

## What the player sees while the map is made

While the tile under the player does not exist, the map area of the radar is covered by noise (the contacts stay clear) and the zone
field of the radar, which normally shows the name of the sector, shows the percentage, for example `40%`. The percentage is the share of
the wanted tiles (the ones around the player, plus one tile of margin) that exist. As soon as the tile under the player exists, the
noise and the text go away, even if tiles farther away are still being made. After that the map fills in around the player as they walk.

## For developers

All the modules are tables in `GryMod.Minimap`, in `lua/grymod/client/minimap/`. They reach each other through `GryMod.Minimap.<Module>`
at call time, so a test can replace one. The functions that take outside data return `nil, reason` or `false, reason` instead of raising.

A **level** is a table `{id, zlo, zhi, ...}`. A **tile** is `{level = <level id>, tx, ty, res, ppm}`. A tile covers
`res / ppm / GryMod.RadarShared.METRES_PER_UNIT` world units on a side.

### Modules

| Module | Main public functions |
| --- | --- |
| `Settings` | `Enabled()`, `Definition()`, `TileRes()`, `BudgetMs()`, `Below()` (0 to 1), `Outside()` (0 to 1), `CacheBytes()`, `Opacity()`: the convars, clamped, never nil. `ParseSwitch`, `ParseDefinition`, `ParseTileRes`, `ParseBudgetMs`, `ParseBelow`, `ParseOutside`, `ParseCacheMB`, `ParseOpacity`: the same rules on any text (pure). |
| `Floors` | `CurrentAt(pos)`: the level for the feet at `pos` (a Vector), with the rays up; it remembers its last answer and does not shoot again for a second unless the feet moved 48 units. `Below(level)`: the level one storey lower (`nil, "open"` for an outdoor level). `Outside(level)`: the open level of the map (the whole height of the world, id `open`, the same table every time, read-only) for any level that is not open; `nil, "open"` for an open level (nothing behind it), `nil, "no world bounds"` when the world is unknown. `Current(z)` and `Fallback(z)`: the slab of the feet height alone, in steps of 32 units. `Known()`, `Reset()`. |
| `Capture` | `Render(tile, level)`: one tile as BGRA bytes (`res * res * 4`), or `nil, reason`; needs the render context of a hook. `IsCapturing()`: true during a render (other render hooks of GryMod return early). `IsVoid(b, g, r, a)`: the void rule. `HideNonMap()` and `Restore(list)`. `GetRT(res)`. |
| `DXT1` | `Compress(bgra, w, h, opts)` and `CompressRows(bgra, w, h, firstBlockRow, lastBlockRow, opts)`: BGRA to DXT1, `opts.alpha = true` makes void pixels transparent. `Decode(dxt, w, h)`, `Error(a, b)`: for tests. |
| `VTF` | `Build(w, h, format, data)` and `Write(path, w, h, format, data)`: a VTF 7.2 file (formats `FORMAT_BGRA8888` 12, `FORMAT_DXT1` 13, `FORMAT_DXT1A` 20). `VMTText(path)`, `WriteVMT(path, basetexturePath)`, `Parse(bytes)`. |
| `AIN` | `Parse(bytes)` and `Load(mapName)`: the node graph of the map (`maps/graphs/<map>.ain`, version 37). Used by `Floors.FromNodes`, which today is not used to choose the level. |
| `Cache` | `Key()`, `Dir(key)`, `Name(tile)`, `Path(tile)`, `TileUnits(res, ppm)`, `TileOf(x, y, res, ppm)`, `TileBounds(tile)`: naming and geometry. `Has(tile)` (from memory, safe at every frame), `Store(tile, data, format)`, `Material(tile)`, `Forget(tile)`, `Count()`, `KnownLevels()`. `Clear(key)`, `Prune()`, `Trim(maxBytes)`: the cleaning. |
| `Gen` | `Request(level, cx, cy, extentUnits, below, outside)`: wants the tiles around a point (plus one tile of margin) for the level, and optionally for the floor below and for the outside (the open level), made in that order; it does nothing when the request is the same as the previous one, so it is cheap to call at every draw. `Progress()`, `Pending()`, `Cancel()`. `Step(now)`: the body of the hook. When the work is over and in `Cancel` it calls `Cache.Flush()`. |
| `View` | `ToRadar(px, py, yawDeg, x, y, rangeUnits, rotate)`: world to radar pixels. `VisibleTiles(level, px, py, extentUnits, res, ppm)`. `Draw(xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha)`: draws the tiles of the outside, the floor below and the level (in that order) through the matrix `xf = {a, b, c, d, tx, ty}` and returns the share of the range circle of the level that is covered (the other two do not count). `MapFrame()`. |

The radar side is in `lua/grymod/client/cl_hud_radar_flash.lua`: `Panel:MapTransform(x, y, scale)` builds `xf` from the live matrices of the
radar film, `Panel:SetNoise(v, keepUnits)` and `Panel:SetProgressText(text)` show the noise and the percentage.

### Events

The hooks fire on the client, and describe the current level (the main one) only, except the last two.

| Hook | Arguments | Fires |
| --- | --- | --- |
| `GryMod_MinimapProgress` | `done, total` | Each time one of the two numbers changes. |
| `GryMod_MinimapReady` | none | Once per request, when every wanted tile of the level exists. |
| `GryMod_MinimapBelowReady` | none | Once per request, when the floor below was asked for and all its tiles exist. |
| `GryMod_MinimapOutsideReady` | none | Once per request, when the outside was asked for and all its tiles exist (after the two above). |

```lua
hook.Add("GryMod_MinimapProgress", "my_addon", function(done, total)
	print(("minimap: %d / %d tiles"):format(done, total))
end)

hook.Add("GryMod_MinimapReady", "my_addon", function()
	print("the map around you is made")
end)
```

You can also read the state at any time:

```lua
local p = GryMod.Minimap.Gen.Progress()
-- p.done, p.total, p.percent (0 to 100), p.active, p.failed (the level), p.belowDone, p.belowTotal, p.belowFailed,
-- p.outsideDone, p.outsideTotal, p.outsideFailed

local tile = {level = "f0c88", tx = 0, ty = 0, res = 1024, ppm = 3}
print(GryMod.Minimap.Cache.Has(tile)) -- a tile that exists in the cache
```

A tile that fails is tried again twice and then given up (counted in `failed`). A capture that returns nothing (the menu is open) is not a
failure: it is tried again at the next frame.

### Tests

The tests are in `tests/minimap/`, one file per module (`settings_test.lua`, `floors_test.lua`, `gen_test.lua`, `view_test.lua`,
`cache_test.lua`, ...), plus `radar_integration_test.lua` and `settings_menu_test.lua`. They are in the GLuaTest format, client realm.
Run them in a real game with [gmod-mcp](https://github.com/ExtReMLapin/gmod-mcp), after loading a map:

```
tests_run  realm=client  path=tests/minimap/gen_test.lua
```

Two files, `capture_job.lua` and `dxt1_job.lua` (also `vtf_job.lua`), are not tests but jobs: they need a render hook or real timings.
Run them with `lua_job` in the client realm, for example `lua_job realm=client path=.../tests/minimap/dxt1_job.lua`. The `capture_job.lua`
header says how to check that a prop added at run time does not end in the picture.

Every test that replaces a module or a global puts it back in a `pcall` in `afterEach`, and the files a test writes go under
`grymod/minimap/test_*` and are deleted after.

### Known traps

- **LuaJIT is off under the test runner.** GLuaTest calls the cases under a debug hook, which keeps LuaJIT from compiling: the code is
  about 100 times slower there. Real speeds are measured with `lua_job` (`dxt1_job.lua`), not with `tests_run`.
- **No `ffi` and no `string.buffer` in this build.** Bytes are read with `string.byte(s, i, j)` (several values at once) and built with
  `string.char` and `table.concat`. Keep the hot loops free of engine calls and of closures.
- **The ray up ignores props.** The mask is `MASK_SOLID_BRUSHONLY`, so a roof made of props is not a ceiling and counts as open sky
  (the slab is then taller than the room).
- **The void rule.** The target is cleared to alpha 0 and the depth is not written to the alpha, but about 5 % of the pixels that have alpha 0
  still carry a colour. The alpha alone is not a mask: a pixel is void (transparent) only when its alpha is 0 **and** its colour is
  black. Every other pixel is solid, a black one included. `Capture.IsVoid` is that rule.
- **The slab needs a high camera.** The capture camera is placed 50000 units above the top of the slab, with `znear` and `zfar` cutting the
  slab. With a low camera the engine ignores the slab.
- **A rewritten tile must be forgotten.** The engine keeps the texture of a material by name. `Cache.Store` calls `Forget` for a tile it
  replaces, and `Clear` does the same, so the new file is read again.

## Limits

- **Maps without a ceiling.** On a map where the rays hit the sky (an open-air map), the level is the whole height of the world. Every
  room, roof and tree top is in one picture and the floors below are not separated: the floor below is not drawn for an open level.
- **Sloped floors.** The floor of a level is the feet height rounded to 16 units, and a level may be reused by the player when the feet
  stay within 24 units under and 40 over its floor. On a long slope the map changes level every few steps; the levels already made are
  reused (they are known from the disk), but a long ramp makes several sets of tiles.
- **A room whose ceiling changes height** (a gallery, a room with a lowered part) can give two sets of tiles, one for each ceiling
  class, because the slab is cut at the class that fits under the highest ceiling.
- **Props placed afterwards.** The map shows only what the level creates. A prop a server added, or one the player spawned, is not on the
  map.
- **Time.** The first visit to a large map generates tiles for as long as it takes; the radar works meanwhile, only the background is
  missing.
