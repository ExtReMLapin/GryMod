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
| `gry_minimap_definition_auto` | 1 | 0 or 1 | Automatic definition: the map chooses its own definition from the radar range and the screen (see "Automatic definition" below). With 1 the slider `gry_minimap_definition` is not used (and is greyed in the menu). |
| `gry_minimap_definition` | 3 | 1 to 64, whole numbers | Pixels per metre of the tiles, when the automatic definition is off. More is sharper, takes longer to make and takes more disk. (The upper bound was 16 before the automatic definition.) |
| `gry_minimap_tile` | 1024 | 512, 1024 or 2048 (another number goes to the nearest) | Size of one tile in pixels. At 3 pixels per metre a 1024 tile covers about 341 m. Small tiles are quick to make, big tiles are fewer. |
| `gry_minimap_budget_ms` | 6 | 1 to 30 | Milliseconds per frame the generator may use. One capture (about 7 ms) may go over it. |
| `gry_minimap_below` | 40 | 0 to 100, whole numbers | Opacity in percent of the floor below, seen through the empty parts of the current floor. 0 turns the floor below off (and it is not generated). |
| `gry_minimap_outside` | 30 | 0 to 100, whole numbers | Opacity in percent of the outside (the open level, the whole height of the map) behind the floors, drawn under the floor below. 0 turns it off (and it is not generated). It is drawn only when the player is inside; outdoors the current level is already the open level. |
| `gry_minimap_preload` | 1 | 0 or 1 | Make the map tiles of the outdoor places in advance, from the in/out map (see "Tile preload" below). 0: tiles are only made as you play. |
| `gry_minimap_cache_mb` | 256 | 16 to 4096 | Size limit of the cache of one map, in megabytes. |
| `gry_radar_range` | 75 | 5 to 100 | Existing radar setting: the distance the radar shows, in metres. It is the distance; the definition above is the sharpness. At 5 m the map is a close-up: the automatic definition goes up to 64 pixels per metre by itself, or raise `gry_minimap_definition` (with the automatic definition off) for a sharp picture. |

| `gry_radar_autozoom` | 0 | 0 or 1 | Automatic zoom: the radar's range follows three modes instead of the slider `gry_radar_range` (greyed in the menu while it is on). See "Automatic zoom" below. |
| `gry_radar_zoom_vehicle` | 100 | 5 to 100 | Range in metres while the player drives a vehicle (automatic zoom on). |
| `gry_radar_zoom_foot` | 75 | 5 to 100 | Range in metres on foot outside. |
| `gry_radar_zoom_indoor` | 25 | 5 to 100 | Range in metres indoors (under a ceiling in a narrow place). |
| `gry_radar_zoom_delay` | 0.7 | 0.1 to 5 | Seconds a mode has to hold before the radar goes to its range. |

The map always turns with the player's view, like the contacts: there is no fixed-north mode.

Changing the definition or the tile size makes a new set of tiles (the name of a tile contains both), so the first change generates
the map again. The old tiles stay in the cache until the size limit removes them.

The same options are in the options menu, under "Minimap", with a button "Clear the minimap cache". In that section the radar range slider
comes first, then the check box "Automatic definition (follows the radar range and the screen)", then the definition slider, which is greyed
(it keeps its value) while the check box is on, also when the convar is changed from the console.

## Automatic definition

With `gry_minimap_definition_auto 1` (the default) the map picks its own definition, so that a close range is sharp and a wide one does not
make huge sets of tiles.

- **The density.** At every draw the radar works out how many screen pixels show one metre of ground: its pixels per metre (43 pixels for
  the range, so `43 / range in metres`, as the contacts are placed) times the screen pixels of one radar pixel (the length of a column of
  the matrix the map is drawn with, which follows the screen height and the movie's matrices). On a 3840 x 2160 screen that is 3.29 screen
  pixels per radar pixel, so 28.3 pixels per metre at 5 m, 14.2 at 10 m, 8.3 at 17 m, 3.7 at 38 m, 1.9 at 75 m and 1.4 at 100 m.
- **The pyramid.** The level is one of 2, 4, 8, 16, 32 or 64 pixels per metre. The rule is the smallest level that has at least 0.7 times the
  density of the screen, so the picture is stretched at most 1.43 times. On the 4K screen: 5 m gives 32, 10 m gives 16, 17 m gives 8, 38 m
  gives 4, 75 m and 100 m give 2. Above 91 pixels per metre the level stays at 64, below 2.9 it stays at 2.
- **Hysteresis.** The level in use is kept while the density stays between 0.6 and 1.6 times it (level 16: 9.6 to 25.6), so dragging the range
  slider does not make the map again at every step. A level chosen by the rule is always inside that band, so a density that goes back and forth
  around an edge changes the level at most once.
- **The definition in use.** `Settings.Definition()` gives the level the radar calculated (4 until it has calculated one) when the automatic
  definition is on, and the slider's value when it is off, so the generator, the view and the cache do not know which of the two it is.
  `Settings.PreviousDefinition()` gives the level before the current one (only one is kept), or nil.
- **What happens on a change of level.** Each level has its own tiles (the definition is in the name of a tile). The tiles of the new level do
  not exist yet, so while the tiles around the player (the main level, and the floor below and the outside when they are drawn) are not all
  there, `View.Draw` first draws the tiles of the previous level, at most half of the budget of 96 materials, and the new tiles go over them as
  they come. The noise veil and the percentage are not shown while a tile of the previous level covers the player (the veil only comes back
  when neither level has the tile under the player). The previous tiles are stretched or shrunk, so the map is blurry for a moment and then
  sharp. In the voids of a new tile the previous tile shows through for as long as the set is incomplete.
- **The cost of a high level.** A tile is 1024 pixels at every level, so a level of 64 pixels per metre covers 16 m a side, and at 5 m the
  radar needs about nine tiles around the player: they are made once and kept in the cache like the others.

## Automatic zoom

An option (off by default, `gry_radar_autozoom 1`, section "Automatic zoom" of the menu) that changes the radar's range by itself between three
modes. The three ranges are the player's sliders and nothing ties one to another (an indoor range bigger than the vehicle's is taken as it is).

- **The modes.** *Vehicle*: the player drives (`Player:InVehicle()`); it wins over the others, a vehicle ignores the ceiling. *Indoor*: under a
  ceiling AND in a narrow place. *Foot*: everything else. Under a ceiling means that the level of `Floors.CurrentAt` is not the open one (that
  function asks the engine at most once a second). Narrow means that the median of eight free distances around the player at chest height (rays
  with the brush mask, each distance capped at 20 m) is under 12 m; it stays narrow until the median goes over 18 m. The eight rays are cast only
  under a ceiling, at most four times a second, and only again if the player moved 24 units (else once a second). A large hall, a very wide
  tunnel or a huge cavern is not narrow and stays in the foot mode; a bridge or an awning is not narrow either.
- **The delay.** A mode has to hold for `gry_radar_zoom_delay` seconds (0.7 by default) before the radar goes there, in both directions: a door, a
  passing ceiling or a short ride changes nothing. The first observation sets the mode at once.
- **The glide.** The radar has two ranges. `Radar.TargetRange()` is the range of the mode in use (whole metres). `Radar.Range()` is the range the
  radar DRAWS with: it glides to the target in 0.8 s, in a straight line in the logarithm of the range with an ease at both ends, so a zoom looks
  even in ratio. The contacts and the map are placed with the range shown. The glide is only a scale of the tiles that are there: the definition
  of the map (the pyramid, see above), the tiles asked of the generator and the range told to the server all follow the TARGET at once, so a glide
  never makes tiles on the way and the server sees the new range as soon as the mode changes (the message `gry_radar_want` is sent at once, not at
  the next tick of its one second timer; it carries the target). A new target in the middle of a glide starts from the range shown.
- **Cost.** Nothing while the option is off. On: no hook of its own (`Radar.Feed` calls `GryMod.RadarZoom.Update` at every frame the HUD
  draws; the glide is a pure function of the time), one probe at most every quarter of a second.
- **Limits.** The contacts follow the same range as the map, so indoors at 25 m an enemy 40 m away is not on the radar (a separate range for the
  contacts is a later change). A roof made of props is not seen (the rays use the brush mask), the same trap as the floors. Going from a small range
  to a big one shows tiles that may not exist yet (the veil rules above apply).

## The in/out map (made by the server)

(The in/out map is called `zonemap` in the code: `GryMod.ZoneMap`, `gry_zonemap*`, `sv_zonemap.lua`.)

The automatic zoom has to know whether the player is indoors. The server makes that answer once per map, from the engine's node graph, and sends it to the players;
the automatic zoom asks it first and only falls back on its own rays where the map says nothing.

- **How it is made.** At the start of a map the server reads `maps/graphs/<map>.ain` (`GryMod.AIN`, shared) and, at each ground node, looks up with five rays (brush mask; a ray
  hits a ceiling when it hits a brush 512 units or less over the node, and the place is roofed when at least 3 of the 5 rays do: a hole or a stairwell on one or two
  rays does not make it open; the ceiling height is the highest of those hits) and around with eight rays at chest height (the median of the free distances, each
  capped at 20 m, under 15 m is narrow). A node is indoor when it is under a ceiling AND narrow; it also keeps the height class of its ceiling (the classes of the
  floors: 56 to 448). The pure module `GryMod.ZoneMap` (`lua/grymod/sh_zonemap.lua`) puts the samples in 128 x 128 unit cells of 128 unit layers of height, spreads each
  one over 3 cells (a graph is sparse: what no node reaches stays unknown), smooths isolated noise, and merges equal cells into rectangles (boxes).
- **Cost.** About 5 microseconds a ray and at most 13 rays a node: a 410 node map takes about 30 ms in all. The work is spread over the server's frames
  (`gry_zonemap_budget_ms`, 2 ms by default) by a `Think` hook that exists only while it works. Nothing runs at all when the switch is off.
- **The file.** `data/grymod/zonemap/<map>_<bsp size>_v2.dat` on the server (`_v2_navmesh.dat` for the navmesh source; the `_v1` files of the old ceiling rule are never read and can be deleted by hand), binary (a 24 byte header with the magic `GZM1`, the size of the map's `.bsp`, the number of
  ground nodes, the number of samples and of boxes; 9 bytes a box; a checksum). Written with one write and checked; a file of another map size, damaged or of another
  version is ignored and made again. A map with a few hundred boxes is a few KB.
- **The network.** `gry_zonemap_state` (state, done, total: off, no graph, waiting, computing, ready, incomplete, failed) to everybody at each change, and the
  file in chunks of at most 30000 bytes in `gry_zonemap_data` when it is ready; a client asks with `gry_zonemap_want` when it is ready to play, and an administrator
  can delete the map and have it made again with `gry_zonemap_reset`.
- **Settings.**

| Convar | Default | Range | Meaning |
|---|---|---|---|
| `gry_zonemap` | 1 | 0 or 1 | Server switch (administrators change it from the options panel). Off: nothing is made or sent. |
| `gry_zonemap_budget_ms` | 2 | 0.5 to 10 | Server console only: milliseconds of rays per server frame while the map is made. |
| `gry_zonemap_max_nodes` | 20000 | 1 or more | Server console only: a graph with more ground nodes makes the map from the first ones, flagged incomplete. |
| `gry_zonemap_debug` | 0 | 0 or 1 | Client, no administrator right: draws the boxes in the world (red indoor, green outdoor, a cyan line at the ceiling height). The drawing hook exists only while it is 1. |

- **When it is "incomplete".** If the graph has more nodes than `gry_zonemap_max_nodes`, or a node could not be sampled, the map is made from what was used and the
  server says so (state 5); the client tells the player once per map. The options panel shows the state of the map.
- **Limits.** No graph on the map, or an empty one: no zone map (state 1), the automatic zoom keeps its own rays. A place no node reaches is unknown. Props are not
  seen (the rays use the brush mask), as for the floors.

## The cache

- **Where:** `garrysmod/data/grymod/minimap/<key>/`. One directory per map, with `index.json` and, for each tile, a `.vtf` and a `.vmt`.
- **Key:** the map name, the size in bytes of `maps/<map>.bsp`, and the version of the format, written in lower case with every
  character outside `a-z 0-9 _` turned into `_`, for example `gm_example_6540988_v4` (the number is only an example). A map that is updated has another size, so it
  gets a new directory, and the old directories of the same map name are deleted at the first request after the map loads. The version changes when
  the content of the tiles changes: `v4` replaced `v2` when the opaque black of "nothing" became void in every set (see Known traps), so a cache made by an older
  version is deleted and made again by itself.
- **Tile name:** `t_<level>_<tx>_<ty>_<res>_<ppm>`, a negative number is written with an `n` in front (`n3`).
- **Size limit:** `gry_minimap_cache_mb`, for the directory of the current map. Above the limit the least recently used tiles are
  deleted, until the size is at 90 % of the limit. The check runs at the first request of a map and then every 64 tiles made. The
  tile that was just written is never removed.
- **Clearing it:** press "Clear the minimap cache" in the options menu (it clears the current map and the map is made again as you
  play), or delete the directory `garrysmod/data/grymod/minimap/<key>/` (or all of `garrysmod/data/grymod/minimap/`) while the game is
  closed.

## Tile preload (outdoor tiles made in advance)

Without it the map is made as you walk: the tiles around you, and the ones around each new place. The preload makes the tiles of the outdoor
places before you get there, so that a walk outside finds them ready.

- **When:** the in/out map arrived from the server (`GryMod_InOutMapReady`), or one of the settings that decide what is made changed (the switch
  `gry_minimap_preload`, the automatic zoom and its three ranges, the radar range, the definition settings). A short wait (2 s) makes several
  changes one plan. A map with no in/out map (no node graph and no navigation mesh) has no preload: it stays as it was, made as you play.
- **What:** the tiles that cover the OUTDOOR boxes of the in/out map, for the open level of each place (the camera goes where an up ray from the place hits,
  see Limits), at the definitions the radar can use: with the automatic definition, the level in use plus the level the rule gives for each of the
  three zoom ranges (shared ones once: 100 / 75 / 25 m on a 4K screen need 2 and 4 pixels per metre); with a manual definition, the slider's. The screen
  constant that gives the level of a range (the density at a range r is k / r) is recorded by the radar at each draw (`Settings.ScreenConstant`).
  A place whose level would be higher than the sky of the playable area (a cell at the fringe of a box) makes no tile.
- **The floors:** when the map has a node graph (`.ain`), each ground node is a place: `Floors.PeekAt` gives the level a player standing there would get (the
  same five rays and the same choice as `CurrentAt`, no hold, the player's own remembered level untouched), and the tiles within 256 units around it are made, at the
  definition of the place's mode (indoors by the in/out map: the indoor range's level, else the foot range's). The INDOOR boxes of the in/out map also make floor places (one ray down from the top
  of the box's layer finds the ground, `Floors.GroundAt`, then `PeekAt` gives the level): this reaches the places the graph does not (the underground of
  gm_construct) and works on a map that has only a navigation mesh. Measured on gm_construct on positions that are not the graph's (the centres of the navigation mesh areas): the tiles
  missing under the player go from 98 to 66 with the graph's floors (outdoors 18 to 6, floors 80 to 60), and to 48 with the indoor boxes' floors too. The floors stay half missed because a level is named by the exact floor height and
  ceiling class at each place: another point of the same staircase gives another level (see the stairs note in the to-do list).
- **How:** the plan is made in two passes over the same places (the level of a place is the usable anchor of the biggest class among the known ones, so the first pass lets every place put its anchor in the registry and the second asks again with the complete registry; only the second pass's tiles are kept), in small steps of a frame (about 1 ms, one up ray per area of a box, at most 3 x 3 areas a box), nearest to the
  player first, and tiles the cache already has are left out. The generator makes them after every tile the radar asks for, with a smaller budget
  (`Gen.PRELOAD_BUDGET_MS`, 2 ms), and not at all in a frame that follows a frame slower than 25 ms: it comes back when frames are fast again. The
  preload never shows in the veil (no percentage).
- **Cost:** no hook stays: the planning frame hook exists only while a plan is made, and the generator's hook only while tiles wait. A plan for
  gm_construct (927 boxes) costs about 11 ms of rays in all and makes about 28 tiles at two definitions.

## What the player sees while the map is made

While the tile under the player does not exist, the map area of the radar is covered by noise (the contacts stay clear) and the zone
field of the radar, which normally shows the name of the sector, shows the percentage, for example `40%`. The percentage is the share of
the wanted tiles (the ones around the player, plus one tile of margin) that exist. As soon as the tile under the player exists, the
noise and the text go away, even if tiles farther away are still being made. After that the map fills in around the player as they walk.
With the automatic definition, a tile of the previous level that covers the player also removes the noise (see "Automatic definition").

## For developers

All the modules are tables in `GryMod.Minimap`, in `lua/grymod/client/minimap/`. They reach each other through `GryMod.Minimap.<Module>`
at call time, so a test can replace one. The functions that take outside data return `nil, reason` or `false, reason` instead of raising.

A **level** is a table `{id, zlo, zhi, ...}`. A **tile** is `{level = <level id>, tx, ty, res, ppm}`. A tile covers
`res / ppm / GryMod.RadarShared.METRES_PER_UNIT` world units on a side.

### Modules

| Module | Main public functions |
| --- | --- |
| `Settings` | `Enabled()`, `Definition()` (the level in use: the automatic one or the slider's), `DefinitionAuto()`, `TileRes()`, `BudgetMs()`, `Below()` (0 to 1), `Outside()` (0 to 1), `CacheBytes()`, `Opacity()`: the convars, clamped, never nil. `ParseSwitch`, `ParseDefinition`, `ParseDefinitionAuto`, `ParseTileRes`, `ParseBudgetMs`, `ParseBelow`, `ParseOutside`, `ParseCacheMB`, `ParseOpacity`: the same rules on any text (pure). The automatic definition: `AUTO_LEVELS` (2, 4, 8, 16, 32, 64), `AutoDefinitionFor(screenPixelsPerMetre, previousPpm)` (pure: the rule and the hysteresis), `SetAutoDefinition(ppm)` (the radar gives the level it calculated; a level outside the pyramid is ignored and answers false), `PreviousDefinition()`, and the state `AutoState = {current, previous}`. |
| `Floors` | `CurrentAt(pos)`: the level for the feet at `pos` (a Vector), with the rays up; it remembers its last answer and does not shoot again for a second unless the feet moved 48 units. `Below(level)`: the level one storey lower (`nil, "open"` for an outdoor level). `Outside(level)`: the open level of the map (the whole height of the world, id `open`, the same table every time, read-only) for any level that is not open; `nil, "open"` for an open level (nothing behind it), `nil, "no world bounds"` when the world is unknown. `Current(z)` and `Fallback(z)`: the slab of the feet height alone, in steps of 32 units. `Known()`, `Reset()`. |
| `Capture` | `Render(tile, level)`: one tile as BGRA bytes (`res * res * 4`), or `nil, reason`; needs the render context of a hook. `IsCapturing()`: true during a render (other render hooks of GryMod return early). `IsVoid(b, g, r, a)`: the void rule. `IsBlackOpaque(b, g, r, a)`, `BlackOpaqueToVoid(bgra)` and `IsAllBlackOpaque(bgra)`: the rule of the opaque black of "nothing" (pure, used by `Gen`). `HideNonMap()` and `Restore(list)`. `GetRT(res)`. |
| `DXT1` | `Compress(bgra, w, h, opts)` and `CompressRows(bgra, w, h, firstBlockRow, lastBlockRow, opts)`: BGRA to DXT1, `opts.alpha = true` makes void pixels transparent. `Decode(dxt, w, h)`, `Error(a, b)`: for tests. |
| `VTF` | `Build(w, h, format, data)` and `Write(path, w, h, format, data)`: a VTF 7.2 file (formats `FORMAT_BGRA8888` 12, `FORMAT_DXT1` 13, `FORMAT_DXT1A` 20). `VMTText(path)`, `WriteVMT(path, basetexturePath)`, `Parse(bytes)`. |
| `AIN` | `Parse(bytes)` and `Load(mapName)`: the node graph of the map (`maps/graphs/<map>.ain`, version 37). Used by `Floors.FromNodes`, which today is not used to choose the level. |
| `Cache` | `Key()`, `Dir(key)`, `Name(tile)`, `Path(tile)`, `TileUnits(res, ppm)`, `TileOf(x, y, res, ppm)`, `TileBounds(tile)`: naming and geometry. `Has(tile)` (from memory, safe at every frame), `Store(tile, data, format)`, `Material(tile)`, `Forget(tile)`, `Count()`, `KnownLevels()`. `Clear(key)`, `Prune()`, `Trim(maxBytes)`: the cleaning. |
| `Gen` | `Request(level, cx, cy, extentUnits, below, outside)`: wants the tiles around a point (plus one tile of margin) for the level, and optionally for the floor below and for the outside (the open level), made in that order; it does nothing when the request is the same as the previous one, so it is cheap to call at every draw. `Progress()`, `Pending()`, `Cancel()`. `Step(now)`: the body of the hook. Between the capture and the compression it applies the rule of the opaque black (see Known traps). When the work is over and in `Cancel` it calls `Cache.Flush()`. |
| `View` | `ToRadar(px, py, yawDeg, x, y, rangeUnits, rotate)`: world to radar pixels. `VisibleTiles(level, px, py, extentUnits, res, ppm)`. `Draw(xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha)`: draws the tiles of the outside, the floor below and the level (in that order) through the matrix `xf = {a, b, c, d, tx, ty}` and returns the share of the range circle of the level that is covered (the other two do not count). With a previous definition (`Settings.PreviousDefinition()`) and tiles missing at the current one, it first draws the same three passes with the tiles of the previous definition (at most half the materials budget). `MapFrame()`. |

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
- **The opaque black of "nothing".** Where the slab of a level lies inside solid earth or looks at a sky brush, the engine sometimes draws exactly
  (0, 0, 0, 255) instead of leaving the cleared (0, 0, 0, 0): the same tile can come back void from one render and nearly all (0, 0, 0, 255) from the
  next (measured on gm_funkis, where a tile of the floor below came back 99 % of that black and was stored as a black solid wall). The geometry never
  has that alpha (it writes 1, so black geometry is (0, 0, 0, 1)). By the void rule above that pixel is solid, so the floor below, drawn over the
  outside, painted a black wall over it: an invisible thing erased a visible one. The rule, in `Gen` after the capture and before the compression: every
  exact (0, 0, 0, 255) pixel becomes void (0, 0, 0, 0), and a tile that has nothing else is an empty tile. It applies to the tiles of every set (main
  level, floor below, outside), because a tile is stored under the name of its level and not of its role: the main level of today is the floor below
  of tomorrow and the cache gives the same file to both, so what is in a tile must not depend on who asked for it first. `Gen.VOID_FILL_SETS`
  (`{main = true, below = true, outside = true}`) says which sets get it; a set left out is compressed as it is, except that a tile that is nothing
  but (0, 0, 0, 255) becomes an empty tile. The solid earth of the current level thus becomes transparent and lets the outside and the floor below show through. A pixel that is almost that (alpha 254, a colour of 1, black geometry with alpha 1, a dark room) is never
  touched. The pass costs under 1 ms on a tile without that black and about 5 ms on a 1024 x 1024 tile that is almost all of it (once per tile).
- **The slab needs a high camera.** The capture camera is placed 50000 units above the top of the slab, with `znear` and `zfar` cutting the
  slab. With a low camera the engine ignores the slab.
- **A rewritten tile must be forgotten.** The engine keeps the texture of a material by name. `Cache.Store` calls `Forget` for a tile it
  replaces, and `Clear` does the same, so the new file is read again.

## Limits

- **Maps without a ceiling.** On a map where the rays hit the sky (an open-air map), the level is the whole height of the world. Every
  room, roof and tree top is in one picture and the floors below are not separated: the floor below is not drawn for an open level.
- **Where the camera of an open level goes: the first hit of the up ray.** The camera of an open level used to go above the whole height of the world.
  That fails when something is above the playable area: the 3D skybox (a small room far over the map: on gm_construct the world goes up to 15360
  and the sky of the playable area is at 9984), or a piece of the map over another with void between them. Now the slab of an open level ends under
  the place where the player's up ray hits, the sky or a solid (the underside of the piece above), 16 units under the hit and rounded down to a
  multiple of 64. The level is named `open_t<top>`: the same height (give or take a step) is the same level and the same tiles, another height is
  another level. A hit that is not under the world's own top (or no hit) gives the level of the whole height, `open`. The map's own open level
  (the "outside" drawn under the floors) takes its top from the sky seen by up rays from up to 96 ground nodes of the node graph, or from the player's
  ray when there is no graph, once per map. Known limits: the "outside" under the floors of a piece that has another one over it still shows the
  upper piece (it is the map's one), and a tile has one camera height, so a tile that holds both tall roofs and free sky shows the slab of the place
  where the player was.
- **Sloped floors.** The floor of a level is the feet height rounded to 16 units, and a level may be reused by the player when the feet
  stay within 36 units under its floor and, over it, 40 units (the lowest class) or class - 72 (the other classes: a taller slab lets the feet
  go higher, the head cut still has to be inside). On a long slope the map changes level every few steps; the levels already made are
  reused (they are known from the disk), but a long ramp makes several sets of tiles. Measured on the long ramp of gm_construct
  (400 units of height over 600, under a flat roof): with the old window (24 under, 40 over) one descent changed level 12 times, 24 sets of
  tiles with the floor below of each; with this window 14 sets and 1 change of level on the way back up; over a walk through every ground node of the
  graph, 46 sets of tiles became 26. The rule of exactness (the slab holds the feet and the head and stays under the ceiling) is the same at every shot
  of the game. Still open: a level per slope, and bands of floors cut in the valleys of the histogram of heights (see the to-do list).
- **A room whose ceiling changes height** (a gallery, a room with a lowered part) can give two sets of tiles, one for each ceiling
  class, because the slab is cut at the class that fits under the highest ceiling.
- **Props placed afterwards.** The map shows only what the level creates. A prop a server added, or one the player spawned, is not on the
  map.
- **Time.** The first visit to a large map generates tiles for as long as it takes; the radar works meanwhile, only the background is
  missing.
