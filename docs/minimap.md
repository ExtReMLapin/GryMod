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
2. **A slice of height is rendered.** Under a ceiling, the level is a slab whose top is the "roundest" height between the head (72 units
   over the feet) and the ceiling minus 8: the multiple of the biggest power of two in that window (a ceiling 150 over the feet gives a top at
   128). Its thickness is the smallest of 192, 320 and 576 that keeps the feet 8 units over its bottom. The level depends on the place only
   (the feet and the ceiling), never on the way the player came, so the preload can make it in advance. What the map MAKES and what it
   SHOWS are two things. It makes only the level of the place (the generator is never asked for another). It shows the level it showed
   before while that level still holds the feet and the head under the ceiling and its tile under the player is there (no flip at each
   doorway), and tile by tile: the held level's tile where the cache has it, the level of the place's elsewhere (see "Made and shown"
   below). The slab is rendered in an orthographic view from above into a render target, one square tile at a time
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
| `gry_minimap_outside` | 80 | 0 to 100, whole numbers | Opacity in percent of the outside (the open level, the whole height of the map) behind the floors, drawn under the floor below. 0 turns it off (and it is not generated). It is drawn only when the player is inside; outdoors the current level is already the open level. |
| `gry_minimap_preload` | 1 | 0 or 1 | Make the map tiles of the outdoor places in advance, from the in/out map (see "Tile preload" below). 0: tiles are only made as you play. |
| `gry_minimap_preload_around` | 1 | 0 or 1 | Also make in advance the places a step from each ground node of the map's graph and the open ground of the outdoor boxes (see "Tile preload" below): fewer veils on ramps, at doors and under roofs, in exchange for a longer plan (about 0.2 to 1.2 s of work in all, spread over frames of about 1 ms) and 15 to 65 % more tiles. 0: the nodes' own places only. |
| `gry_minimap_veil_discovery` | 0 | 0 or 1 | The noise veil and the percentage while the map is made. 0 (the default, the discovery mode): the veil only comes when there is nothing to show (see "What the player sees while the map is made" below); while you walk the map keeps its last picture and a new tile comes over it when it is ready. 1: the old behaviour, a veil as soon as the tile under the player is missing. |
| `gry_minimap_cache_mb` | 768 | 16 to 4096 | Size limit of the cache of one map, in megabytes. |
| `gry_radar_range` | 75 | 5 to 100 | Existing radar setting: the distance the radar shows, in metres. It is the distance; the definition above is the sharpness. At 5 m the map is a close-up: the automatic definition goes up to 64 pixels per metre by itself, or raise `gry_minimap_definition` (with the automatic definition off) for a sharp picture. |

| `gry_radar_autozoom` | 0 | 0 or 1 | Automatic zoom: the radar's range follows three modes instead of the slider `gry_radar_range` (greyed in the menu while it is on). See "Automatic zoom" below. |
| `gry_radar_zoom_vehicle` | 36 | 5 to 100 | Range in metres while the player drives a vehicle (automatic zoom on). |
| `gry_radar_zoom_foot` | 26 | 5 to 100 | Range in metres on foot outside. |
| `gry_radar_zoom_indoor` | 13 | 5 to 100 | Range in metres indoors (under a ceiling in a narrow place). |
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
- **Limits.** The contacts follow the same range as the map, so indoors at 13 m an enemy 20 m away is not on the radar (a separate range for the
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
  character outside `a-z 0-9 _` turned into `_`, for example `gm_example_6540988_v6` (the number is only an example). A map that is updated has another size, so it
  gets a new directory, and the old directories of the same map name are deleted at the first request after the map loads. The version changes when
  the content of the tiles changes: `v6` replaced `v5` when the background of the engine became void whatever its colour (a map with a blue sky had it stored as a solid wall; see Known traps), `v5` replaced `v4` when the level of a place stopped depending on the path (the levels are now named `c<top>t<thickness>`), and `v4` replaced `v2` when the opaque black of "nothing" became void in every set (see Known traps), so a cache made by an older
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
  three zoom ranges (shared ones once; the default ranges are 36 / 26 / 13 m); with a manual definition, the slider's. The screen
  constant that gives the level of a range (the density at a range r is k / r) is recorded by the radar at each draw (`Settings.ScreenConstant`).
  A place whose level would be higher than the sky of the playable area (a cell at the fringe of a box) makes no tile.
- **The floors:** when the map has a node graph (`.ain`), each ground node is a place: `Floors.PeekAt` gives the level a player standing there would get (the
  same five rays and the same rule as `CurrentAt`, no hold, the player's own remembered level untouched), and the tiles within 256 units around it are made, at the
  definition of the place's mode (indoors by the in/out map: the indoor range's level, else the foot range's). The INDOOR boxes of the in/out map also make floor places (one ray down from the top
  of the box's layer finds the ground, `Floors.GroundAt`, then `PeekAt` gives the level): this reaches the places the graph does not (the underground of
  gm_construct) and works on a map that has only a navigation mesh. Measured on gm_construct on positions that are not the graph's (the centres of the navigation mesh areas): the tiles
  missing under the player go from 98 to 66 with the graph's floors (outdoors 18 to 6, floors 80 to 60), and to 48 with the indoor boxes' floors too. With the
  level of a place (2026-11-22, the same walk over the centres of the navigation mesh, a fresh cache) the tool's first numbers were gm_construct 77 to 31, gm_boreas 91 to 27,
  gm_funkis 37 to 9; the numbers of the next paragraph are the better measure.
- **The ring and the cells (`gry_minimap_preload_around`):** the level of a place changes within a few steps on a ramp, at a door or under a roof, so a node alone prepares
  one level of several. With the switch on, each ground node also makes its RING: four more places 64 units away on the two axes, each at the ground found by a ray
  down from 48 units over the node (`Floors.GroundAt`), with its own level and its own definitions, and the tiles within 32 units of it (the node's own place makes the
  tiles within 256). The ring is made for 5000 nodes at most (`Preload.MAX_AROUND_PLACES`, the nearest to the player first). Each CELL of an outdoor box (128 units) is also
  asked, from the ground up: the open level a ray up from the ground gives, or, when that ray hits a roof, the level of a player standing under it (the in/out map calls
  such a box open, and its three areas never see the roof). Over 16000 cells (`Preload.MAX_AROUND_CELLS`, gm_boreas has 190000) only every n-th cell on each axis is asked.
  Each ring place and each cell is one step of the job, so the plan stays in frames of about 1 ms.
  **Measured 2026-11-22** (`tests/minimap/cov_where_job.lua`; the same walk over the centres of the navigation mesh, forward / backward, a fresh test cache, a test client,
  2 and 4 pixels per metre, 3000 positions at most; veils = tiles under the player missing the first time; planning cost = the time of the planning frames added up):

  | map | veils before (forward / backward) | veils after | plan before / after | tiles before / after |
  | --- | --- | --- | --- | --- |
  | gm_construct | 10 / 11 | 6 / 8 | 39 ms / 219 ms | 87 / 104 |
  | gm_funkis | 12 / 12 | 3 / 3 | 44 ms / 212 ms | 66 / 110 |
  | gm_boreas | 9 / 9 | 2 / 3 | 509 ms / 1191 ms | 229 / 283 |
  | gm_everpine_mall | 19 / 17 | 13 / 11 | 91 ms / 274 ms | 55 / 68 |

  An honest note on the walk: the walk goes in straight lines between the navigation areas, so on a stair or a ramp its steps are in the air or inside the floor, where
  no player stands (the level of a place there is a level nobody gets). The numbers above put every step on the ground (`snap`: a ray down from 40 units over the step, a step
  with no ground within 40 units is left out). Without it the tool counted about 3 times more veils (gm_construct 30 / 33, gm_boreas 28 / 27, gm_funkis 28 / 27, gm_everpine_mall
  23 / 21 before; 26 / 28, 22 / 22, 14 / 15, 17 / 14 with the ring and the cells), most of them places no player can be at. What is still missed: ramps under a low sloping
  ceiling (the top of the slice moves 8 units for each 8 units of ceiling, so the levels are one every few steps) and the tower of gm_construct. A grid of 32 units over every
  box removes almost all of the rest (gm_construct 3, gm_everpine_mall 0) for 30000 to 50000 places and 0.6 to 1.8 s of planning, which was judged too much.
- **How:** the plan is made in one pass over the places (the level of a place depends on the place only), in small steps of a frame (about 1 ms, one up ray per area of a box, at most 3 x 3 areas a box), nearest to the
  player first, and tiles the cache already has are left out. The generator makes them after every tile the radar asks for, with a smaller budget
  (`Gen.PRELOAD_BUDGET_MS`, 2 ms), and not at all in a frame that follows a frame slower than 25 ms: it comes back when frames are fast again. The
  preload never shows in the veil (no percentage).
- **Cost:** no hook stays: the planning frame hook exists only while a plan is made, and the generator's hook only while tiles wait. With the ring and the cells (the
  default) a plan costs 0.2 s of work on gm_construct, gm_funkis and gm_everpine_mall and 1.2 s on gm_boreas (4000 nodes), in frames of about 1 ms (a frame of 5 to 14
  ms is the collector's work; the rays of `OpenAt` and `GroundAt` reuse their tables to make less garbage); 0.04 to 0.5 s without. Tiles to make: 15 to 65 % more. The
  generator keeps its small budget (2 ms a frame). `gry_minimap_preload_around 0` gives back the older plan.

## Made and shown (the level of the place against the level held on screen)

The map is made for places and shown with a memory. `Floors.CurrentAt` answers the level to show and the level of the place. The radar asks the generator
(`Gen.Request`) for the level of the place and its floor below only, so every tile the radar makes while the player walks is one the preload can predict (a level that
depends on the way the player came cannot be predicted). `View.Draw` is given the held level as `level` and the level of the place as `base`: for each tile of the window it
draws the held level's tile when the cache has it (an empty one too: that is its picture of nothing), else the base's. The floor below follows the same rule (`below`,
`belowBase`). The veil is decided by the tile that is drawn under the player: the held level's, else the place's. The hold itself is unchanged (it needs the held level's tile
under the player). Measured on 2026-11-22 (simulated walks over the centres of the navigation mesh, or the ground nodes where there is none, forward and backward, each step put on the
ground; `tests/minimap/display_walk_job.lua`; the radar's work is supposed to keep up with the walk), before then after, for gm_construct, gm_boreas, gm_funkis:

| | before | after |
|---|---|---|
| changes of picture for 1000 units | 0.5 to 0.6 / 0.1 / 0.6 to 0.7 | the same |
| veils (tile under the player missing) | 10 / 8 / 2 | the same |
| tiles of a level that is not the level of the place, made by the radar | 14 and 0 / 7 and 11 / 0 and 0 (forward and backward) | 0 |
| tiles made by the radar (level of the main set) | 690 and 724 / 651 and 663 / 304 and 314 | 718 and 740 / 673 and 704 / 347 and 333 |

On the recorded stairs and ramps (17 stretches, up and down) the radar never made a tile of a level that was not the level of the place, before or after, and the changes of
picture and the veils are the same; the radar makes more tiles after (the held level's window is no more reused: from 0 to 100 % more on a short stair, 2 to 7 % on a whole map).
The cost of the clean rule is that extra work, all of it on levels of places that a wider preload could make. A pass of the walk that did not make the place's tile where the held
level's tile exists made fewer tiles than before with the same veils, but it can leave the place's tile missing when the hold ends: it is not in the addon.

## What the player sees while the map is made

The map is made as the player walks, so a tile is sometimes late. What the radar shows then depends on which of three states it is in (the radar tells it to itself in
`panel.mapState`; setting `gry_minimap_veil_discovery`, 0 by default):

- **Ready.** The tile under the player is drawn (the level's, the place's, or the previous definition's). Nothing to say: no veil, no text, the sector name in the zone field.
- **Discovery.** The tile under the player is missing, but the map has something to show. Then there is **no noise veil and no percentage**: the map keeps its last picture
  and the new tile comes over it when it is ready (the generator is never made to hurry). Two cases: (1) the tiles around the player that exist cover a part of the radar's
  circle (`View.Coverage` above 0), for example just across the border between two tiles: that part of the map shows and the rest is empty until its tile comes; (2) the level
  changed (a stair, a lift, a ramp under a roof) and the tile of the new level is not made yet while the picture of the level just left still has its tile under the player: that
  picture stays on screen while the generator works on the new one (the radar keeps the last level that had its tile under the player, `panel.mapKept`; with an idle generator
  nothing is coming, so the old picture is not kept for good). The generator is asked for the NEW level at once, the old picture is only what is drawn meanwhile.
- **Loading.** There is nothing to show: no tile of the level lies under the radar's circle (the first moments on a map with an empty cache, a jump to the other end of the map,
  the cache just cleared), or the in/out map of the server is still being made ("In/out 40%" or "Navigation mesh..."). Then the map area is covered by noise (the contacts stay
  clear) and the zone field, which normally shows the name of the sector, shows the percentage, for example `40%`: the share of the wanted tiles (the ones around the player, plus
  one tile of margin) that exist. As soon as the tile under the player exists the veil goes, even if tiles farther away are still being made.

**How the text is kept readable.** The zone field of the movie is only 23 pixels wide (the original shows a short sector code there) and, like every text field of
the movie, it cuts its text to its rectangle: "In/out 40%" was seen as "In/o", and a name such as `gm_construct` was cut in the same way. The radar therefore widens the field
of its own clip to the text it shows, plus the two 2 pixel margins, never less than the movie's width and never more than `Radar.ZONE_MAX_WIDTH` (110 stage pixels,
about 50 screen pixels at 640x360; "Navigation mesh..." is 86, `gm_everpine_mall` 87). The field keeps its left edge and grows to the right, inside the map area (measured on a
screenshot of the radar: the 86 pixel text ends well before the right edge of the area). When the field is empty again it goes back to the movie's width. A name longer than
110 pixels is still cut at that width, at the right edge of the area (`Clip:FitTextWidth` in `cl_flash.lua`, called by `Panel:_applyZoneText`; the movie's definition of the
field is never changed, only the copy of the clip, and a rebuilt clip is widened again by `_refresh`). The tests (`tests/cl_hud_radar_flash_test.lua`) measure the width of the
text with the font of the field and require it to fit.

With `gry_minimap_veil_discovery 1` every missing tile under the player is "loading", as before the discovery mode. The same happens when the settings module does not have the
setting, or when the view has no `Coverage` (or it raises): the radar falls back on the veil. The tile preload never shows in the veil.

With the automatic definition, a tile of the previous level that covers the player also removes the noise (see "Automatic definition"): it is the same idea for a change of
definition, and it was there before the discovery mode.

**Measured** (2026-11-22, `tests/minimap/discovery_walk_job.lua` and `discovery_walk_server.lua`: the player is really moved along a walk over the centres of the navigation mesh at
266 units a second, 60000 units, 226 s; the real radar of a test client draws every frame at the density of a 4K screen and the real generator makes the tiles in real time, in a
scratch cache; the old and the new verdicts are read in the same frames of the same walk). An episode is one run of frames with the veil; the frames and the seconds are those with it:

| map, conditions | old rule: episodes / frames (seconds) | discovery mode: episodes / frames (seconds) |
| --- | --- | --- |
| gm_funkis, no preload, 120 fps | 9 / 38 (0.7 s) | 1 / 4 (0.1 s) |
| gm_funkis, no preload, 30 fps | 11 / 44 (1.5 s) | 1 / 4 (0.1 s) |
| gm_funkis, preload done first, 120 fps | 5 / 20 (0.2 s) | 0 |
| gm_construct, no preload, 120 fps | 4 / 24 (0.3 s) | 1 / 13 (0.2 s) |
| gm_construct, preload done first, 120 fps | 0 | 0 |

The one veil left without preload is the first moment on the map (the cache is empty at the start: "loading"); the other episodes became discovery frames (at most 40 frames of a partial
map in these walks, with no veil). The numbers are small because a walk at that pace seldom outruns the generator: a tile is 512 m wide at the 2 pixels per metre of a 75 m range on a
4K screen and the radar asks one tile of margin. The veils of a walk are mostly changes of level, which the "kept picture" case covers: in the simulation of `display_walk_tool.lua`
(the generator is supposed to keep up) 28 to 30 of the 31 to 32 events of a walk without preload were that case and 2 to 3 would still veil; after the preload all the 2 and 3 events
were that case. Not measured: the automatic zoom modes (the walks stayed at the foot range, one definition), a vehicle, a slow disk, other maps.

## The big map

A map of the whole level, opened by a key (**M** by default), drawn in a window with the screen clicker. It is the same picture as the minimap (the tiles are
made by the same render, from straight above, outside view: terrain, rocks and roofs) at the size of the screen. Everything is client side and optional:
`gry_map_enable 0` turns it off.

- **The game goes on.** The map does not pause anything and does not take the keyboard: the movement keys and the other keys still work while it is open. Only
  the mouse look is blocked (the cursor is shown). The map closes when its key is pressed again, when the game menu opens, when the player dies or when the
  switch is turned off.
- **Controls.** The mouse wheel zooms toward the mouse: the point of the map under the cursor stays under it. A drag with the left or the right button moves
  the map. The middle button held while the mouse goes up and down is a smooth zoom (up zooms in). The "DONE" button closes it. The zoom goes from 1 (the
  whole map fills the window) to 8; a wheel notch is `z * 1.35 - 0.25` in and `z / (1.35 - 0.25 / z)` out, which is the original game's rule (eleven notches
  from 1 to 8).
- **The hard limit.** The map never shows anything outside its bounds: the picture always fills the window, there is no empty margin at any zoom. At zoom 1
  there is no pan (the window has the shape of the bounds, from 1:2 to 2:1; a very long map can still be moved along its long side).
- **Zoom and place.** The first opening of a map session uses the automatic zoom: the whole bounds when their long side is up to 1000 m, else a window of about
  800 m. Every later opening uses the last zoom, saved when the map closed (`gry_map_zoom`). Each opening is centred on the player: the pan is not kept.
- **The picture is not turned.** World +X is up and world -Y is to the right (the way a tile is stored, and what the radar shows for a player who looks along
  +X). The player is an arrow that turns with his view.
- **Always the outside.** The map shows the open level of the map (the whole height of the world cut at the sky: what a satellite sees), whatever floor the player
  stands on.
- **What it shows.** The player's arrow, the objectives of `GryMod.Objectives.List()` (primary green, secondary yellow, the title as the label, a ring on the
  main one; an objective with `radar = false` is left out; one that is done or failed is hidden, or greyed with `gry_map_finished 1`), the markers of the
  sources of third parties, and an 8 x 8 grid with the letters A to H (down the left side) and the numbers 1 to 8 (along the top); A1 is the top left. Icons grow
  slowly with the zoom, as in the original (`(zoom + 2) * 0.25` times their size). A marker outside the window is pinned to its edge.

### The bounds

The original game writes them in the level's file. Garry's Mod has none, so the map takes what the addon already knows, in this order: the ground nodes of the
AI node graph (at least 8 of them), joined with the boxes of the in/out map when it has arrived; else the boxes alone; else the box of the world (often much
larger than the playable area); else a square of 250 m around the player. The result gets a margin (5 percent, at least 1024 units), is cut at the world's box
when that leaves a usable map, is never smaller than 100 m a side and always holds the player. The node file is read once per map, at the first opening.

### The tiles: a pyramid, made while you look

Tiles are loaded the way a web map does. The levels are the minimap's pyramid (2, 4, 8, 16, 32 and 64 pixels per metre, `Settings.AUTO_LEVELS`): the zoom
decides the level (the smallest one with at least 0.7 times the density of the screen, with the same hysteresis as the radar's automatic definition, kept apart
from it: the big map never changes the definition the radar uses).

- **A coarse picture at once.** A cell whose tile is not there yet shows the same place at a coarser level, scaled up: the map is never empty.
- **Nearest to the mouse first.** The plan asks the coarse level of the window first, then the level the zoom needs with one tile around the window, each
  nearest to the mouse first. It is made again only when the tiles needed or the tile under the mouse change (or every 1.5 s).
- **The minimap's tiles are reused, never touched.** A tile that the minimap's cache already has at that level, size and definition is drawn from there (the
  map only asks `Cache.Has`, `Cache.IsEmpty` and `Cache.Path` and loads the material in a table of its own). Nothing of the big map is ever stored in that cache, so the
  zoom (which changes the definition) never evicts or invalidates what the radar's circular preload made.
- **The rest is made in memory.** A missing tile is rendered by the same code as the minimap's (`Capture.RenderTo`) into one of a pool of render targets (128 MB
  of tiles at most: 32 tiles of 1024 pixels), without compression and without a file. The least recently used tile makes room; a tile drawn in this very frame is
  never taken. The tiles are forgotten a minute after the map closes. The pool only exists once it was needed.
- **Never a freeze.** At most one capture a frame, and none in a frame where the minimap's generator made one (`Capture.MayCapture`). While the map is open it
  has the even frames (`Capture.SetPriority("map")`), the generator the odd ones, so neither starves. The work is done by a `PostRender` hook that exists only while tiles
  are missing.

### The loading look

The game knows only three things: that a loading began, that a tile arrived, and that nothing is left. It knows no progress, so no look is tied to one. Each tile
has two looks: **waiting** (a loop on its own clock, over the coarse picture) and **arrived** (a short effect of about 0.3 s that starts the moment the tile
arrives, never delayed); at the very end one brief rim flash. The default look is the **glitch**: while it waits the tile trembles in six bands under a dark veil;
when it arrives it tears in red and cyan, the bands shrink, and the tile is plain. A tile that was already there (a tile of the minimap) has no look.

The looks are entries of a registry. Add one, and the player picks it with `gry_map_loading_fx` (and in the options page):

```lua
GryMod.Map.Fx.Register("flash", {
	label = "Flash",
	arrive = 0.2, -- seconds of the arrival look (0.3 by default)
	rim = 0.35, -- seconds of the rim at the end (0.35 by default)
	-- waiting: called every frame for each cell that waits; t = seconds it has waited
	waiting = function(d, cell, t)
		d.Fill(cell.x, cell.y, cell.w, cell.h, 255, 255, 255, 30 + 20 * math.sin(t * 6))
	end,
	-- arrived: p goes from 0 to 1; cell.sharp is the picture of the tile that arrived, cell.coarse the one under it (nil when none)
	arrived = function(d, cell, p, t)
		d.Slice(cell.sharp, cell.x, cell.y, cell.w, cell.h, 0, 1, 0, 255, 255, 255, math.floor(255 * p), false)
	end
})

RunConsoleCommand("gry_map_loading_fx", "flash")
```

`d` has three functions: `d.Fill(x, y, w, h, r, g, b, a)`, `d.Slice(picture, x, y, w, h, from, to, dx, r, g, b, a, additive)` (the band `from` to `to`, fractions of the
cell's height, of a picture, shifted by `dx` pixels) and `d.Rim(x, y, w, h, thickness, r, g, b, a)`. An optional `finish = function(d, rect, p)` draws the rim at the end.
The base of a cell (the coarse picture, or the plain tile) is drawn by the map; a look draws over it.

### Settings

| Convar | Default | Range | Effect |
| --- | --- | --- | --- |
| `gry_map_enable` | 1 | 0 or 1 | The big map. 0: the key and `GryMod.Map.Open()` do nothing. |
| `gry_map_key` | 0 (M) | a button code | The key that opens and closes it; 0 uses the default, M. A `bind <key> gry_map` in the console works too. |
| `gry_map_zoom` | 1 | 1 to 8 | The zoom the map had when it was closed; the next opening of the session starts there. Written by the map. |
| `gry_map_loading_fx` | glitch | a name | The loading look (see above). A name nobody registered uses the glitch. |
| `gry_map_finished` | 0 | 0 or 1 | Also show the objectives that are done or failed, greyed. |
| `gry_map_grid` | 1 | 0 or 1 | The 8 x 8 grid with its letters and numbers. |

All of them are saved client convars, and in the options menu of the GryMod category, on the page "Big map". The tile size and the generator's time are the
minimap's (`gry_minimap_tile`, `gry_minimap_budget_ms`).

### For developers

```lua
GryMod.Map.Open()   -- true, or false and why (switched off, the player is dead)
GryMod.Map.Close()
GryMod.Map.Toggle()
GryMod.Map.IsOpen() -- true or false
GryMod.Map.GetZoom()    -- the zoom now, or the saved one while it is closed
GryMod.Map.GetBounds()  -- {x0, x1, y0, y1, source} of the last opening, or nil
```

`Open` and `Close` play the HUD events `map_open` and `map_close` (see `docs/events.md`), so `GryMod.API.HUDEvent("map_open")` does the same and the open and the
sound are one call. The hooks (nothing reads what a listener returns; a listener that raises is shown in the console and stops nothing):

| Hook | Arguments | Runs |
| --- | --- | --- |
| `GryMod_MapOpened` | none | The map just opened. |
| `GryMod_MapClosed` | none | The map just closed. |
| `GryMod_MapZoomed` | `zoom` | The zoom changed (a wheel notch, a middle-button drag), not at opening. |

A **marker source** is a function that returns the markers of the moment, with the same records as `GryMod.Radar.AddSource` (plus an optional `label`, and `main = true` for
a ring). It is called every frame the map is drawn, under `pcall`: a source that raises three times in a row is removed.

```lua
GryMod.Map.AddMarkerSource("my_addon", function()
	return {
		{pos = Vector(1200, -300, 0), type = 5, subtype = 0, label = "Meeting point", main = true, id = "meet"}, -- an objective arrow, primary (green)
		{pos = Vector(900, 100, 0), type = 7, id = "mate"} -- a team mate (blue dot)
	}
end)

hook.Add("GryMod_MapZoomed", "my_addon", function(zoom)
	print(("zoom x%.1f"):format(zoom))
end)

GryMod.Map.RemoveMarkerSource("my_addon")
```

`type` 5 is an objective (subtype 0 or 1 primary, green; 2 or 3 secondary, yellow), 6 a ring, 7 a team mate, the others are white dots; `alpha` (0 to 1) and `scale`
(percent) are read. The objectives of `GryMod.Objectives` need no source: the map reads them.

The modules are in `lua/grymod/client/map/`: `zoom` (the zoom rules), `frame` (the maths between the world and the window: zoom toward a point, the drag, the hard
clamp), `bounds`, `pyramid`, `store`, `fx`, `markers`, `settings`, `tiles` and `panel`. The first seven are pure and have tests that need no render (`tests/map/`). The
tests of `tiles` and `panel` replace the minimap's cache, capture, floors and settings and the engine's render targets by stand-ins.

### Limits

- The map shows the outside always; the floor the player stands on is not drawn on it.
- The first opening of a map reads the node file (one-off, about 20 ms for 4000 nodes). A map with no node graph and no in/out map uses the box of the world, which may be larger than the playable area.
- The tiles are at most as sharp as the pyramid's top level; at zoom 8 on a big map the level may be coarser than the radar's closest one.
- The glitch's red and cyan copies need the engine's additive blend (`render.OverrideBlend`); the fade of a tile needs the render to keep its alpha opaque (`Capture.RenderTo`
  clears to alpha 255 and switches the alpha write off for the view). If either is refused, the map is drawn plain and the look degrades.

## For developers

All the modules are tables in `GryMod.Minimap`, in `lua/grymod/client/minimap/`. They reach each other through `GryMod.Minimap.<Module>`
at call time, so a test can replace one. The functions that take outside data return `nil, reason` or `false, reason` instead of raising.

A **level** is a table `{id, zlo, zhi, ...}`. A **tile** is `{level = <level id>, tx, ty, res, ppm}`. A tile covers
`res / ppm / GryMod.RadarShared.METRES_PER_UNIT` world units on a side.

### Modules

| Module | Main public functions |
| --- | --- |
| `Settings` | `Enabled()`, `Definition()` (the level in use: the automatic one or the slider's), `DefinitionAuto()`, `TileRes()`, `BudgetMs()`, `Below()` (0 to 1), `Outside()` (0 to 1), `CacheBytes()`, `Opacity()`: the convars, clamped, never nil. `ParseSwitch`, `ParseDefinition`, `ParseDefinitionAuto`, `ParseTileRes`, `ParseBudgetMs`, `ParseBelow`, `ParseOutside`, `ParseCacheMB`, `ParseOpacity`: the same rules on any text (pure). The automatic definition: `AUTO_LEVELS` (2, 4, 8, 16, 32, 64), `AutoDefinitionFor(screenPixelsPerMetre, previousPpm)` (pure: the rule and the hysteresis), `SetAutoDefinition(ppm)` (the radar gives the level it calculated; a level outside the pyramid is ignored and answers false), `PreviousDefinition()`, and the state `AutoState = {current, previous}`. `VeilInDiscovery()` (true: the old veil whenever the tile under the player is missing; false, the default: the discovery mode) and `ParseVeilDiscovery(text)` (pure; no number is the default, false). |
| `Floors` | `CurrentAt(pos)`: two answers, the level to SHOW for the feet at `pos` (a Vector; the held level while it is held) and the level of the PLACE (the same table when nothing is held; the generator is asked for this one), with the rays up; it remembers its last answer and does not shoot again for a second unless the feet moved 48 units. `LevelFor(feet, ceiling)`: the level of a place (id `c<top>t<thickness>`, pure). `TileReady(level, x, y)`: is its tile under (x, y) in the cache (the hold of the display). `Below(level)`: the slab of 192 under the bottom of the level (`nil, "open"` for an outdoor level). `Outside(level)`: the open level of the map (the whole height of the world, id `open`, the same table every time, read-only) for any level that is not open; `nil, "open"` for an open level (nothing behind it), `nil, "no world bounds"` when the world is unknown. `Current(z)` and `Fallback(z)`: the slab of the feet height alone, in steps of 32 units. `Reset()`. |
| `Capture` | `Render(tile, level)`: one tile as BGRA bytes (`res * res * 4`), or `nil, reason`; needs the render context of a hook. `RenderTo(tile, level, rt)`: the same render copied into a render target of the caller (an opaque picture, cleared to alpha 255), `true` or `nil, reason`: the big map uses it, with no compression and no file. `MayCapture(owner)`, `SetPriority(owner)` and `ResetFrame()`: at most one capture a frame between the minimap's generator (`"gen"`) and the big map (`"map"`), the owner with the priority has the even frames. `IsCapturing()`: true during a render (other render hooks of GryMod return early). `IsVoid(b, g, r, a)`: the void rule. `IsBackground(b, g, r, a, bg)`, `BackgroundToVoid(bgra, bg)`, `IsAllBackground(bgra, bg)` and `FindBackground(bgra)`: the rule of the background of the engine (pure, used by `Gen`; `bg` is a pixel string `B G R 255`, black when missing). `HideNonMap()` and `Restore(list)`. `GetRT(res)`. |
| `DXT1` | `Compress(bgra, w, h, opts)` and `CompressRows(bgra, w, h, firstBlockRow, lastBlockRow, opts)`: BGRA to DXT1, `opts.alpha = true` makes void pixels transparent. `Decode(dxt, w, h)`, `Error(a, b)`: for tests. |
| `VTF` | `Build(w, h, format, data)` and `Write(path, w, h, format, data)`: a VTF 7.2 file (formats `FORMAT_BGRA8888` 12, `FORMAT_DXT1` 13, `FORMAT_DXT1A` 20). `VMTText(path)`, `WriteVMT(path, basetexturePath)`, `Parse(bytes)`. |
| `AIN` | `Parse(bytes)` and `Load(mapName)`: the node graph of the map (`maps/graphs/<map>.ain`, version 37). Used by `Floors.FromNodes`, which today is not used to choose the level. |
| `Cache` | `Key()`, `Dir(key)`, `Name(tile)`, `Path(tile)`, `TileUnits(res, ppm)`, `TileOf(x, y, res, ppm)`, `TileBounds(tile)`: naming and geometry. `Has(tile)` (from memory, safe at every frame), `Store(tile, data, format)`, `Material(tile)`, `Forget(tile)`, `Count()`, `KnownLevels()`. `Clear(key)`, `Prune()`, `Trim(maxBytes)`: the cleaning. |
| `Gen` | `Request(level, cx, cy, extentUnits, below, outside)`: wants the tiles around a point (plus one tile of margin) for the level, and optionally for the floor below and for the outside (the open level), made in that order; it does nothing when the request is the same as the previous one, so it is cheap to call at every draw. `Progress()`, `Pending()`, `Cancel()`. `Step(now)`: the body of the hook. Between the capture and the compression it applies the rule of the background of the engine (see Known traps). When the work is over and in `Cancel` it calls `Cache.Flush()`. |
| `View` | `ToRadar(px, py, yawDeg, x, y, rangeUnits, rotate)`: world to radar pixels. `VisibleTiles(level, px, py, extentUnits, res, ppm)`. `Draw(xf, px, py, yawDeg, rangeUnits, level, alpha, below, belowAlpha, outside, outsideAlpha, base, belowBase)`: draws the tiles of the outside, the floor below and the level (in that order) through the matrix `xf = {a, b, c, d, tx, ty}`; `base` and `belowBase` (the level of the place and its floor below, when `level` is a held one) stand in tile by tile where the cache has no tile of `level` (resp. `below`); it returns the share of the range circle of the level that is covered (the other two do not count). With a previous definition (`Settings.PreviousDefinition()`) and tiles missing at the current one, it first draws the same three passes with the tiles of the previous definition (at most half the materials budget). `MapFrame()`. `Coverage(px, py, rangeUnits, level, base)`: the share (0..1) of the range circle around (px, py) that lies on existing tiles of `level` (the tile of `base` standing in where it has none), at the current tile size and definition, without drawing: `Cache.Has` only, no material; 0 for anything it cannot use, never raises. The radar asks it, only when the tile under the player is missing, to tell a map with a hole in it from a map with nothing to show. |

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

local tile = {level = "c128t192", tx = 0, ty = 0, res = 1024, ppm = 3}
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

`display_walk_tool.lua` / `display_walk_job.lua` / `display_walk_stairs_job.lua` measure what the radar makes and what it shows during a simulated walk (see "Made and
shown"; load `preload_coverage_job.lua` first, they use a scratch cache `zz_dl_<map>_v5`, never the real one, and the comments of the files say how to run them).

`discovery_walk_job.lua` (client) with `discovery_walk_server.lua` (server, async) measure how long the veil would show during a real walk with the old rule and with the discovery mode (see
"What the player sees while the map is made"; their headers say the order), and `discovery_shots_tool.lua` stages the three states of the radar for screenshots.

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
- **The background of the engine (alpha 255).** Where the slab of a level lies inside solid earth, looks at a sky brush or at the sky, the engine sometimes
  paints a flat colour with alpha 255 instead of leaving the cleared (0, 0, 0, 0). The colour is the one of the map's sky or fog: black on gm_funkis,
  d1_canals_01, d2_coast_07, gm_everpine_mall and ep2_outland_02, a light blue on gm_boreas (where a tunnel was drawn inside a solid blue wall). The same tile
  can come back void from one render and entirely that colour from the next (seen on gm_funkis: it came and went with where the player stood), and the colour
  itself drifts with the time (gm_boreas: (123, 161, 201), then (128, 168, 209) a few seconds later), so it is read from each picture and never kept per map.
  The geometry's own alpha is 1, so the alpha 255 is the engine's fill. By the void rule above that pixel is solid, so the floor below, drawn over the
  outside, painted a wall over it: an invisible thing erased a visible one. The rule, in `Gen` after the capture and before the compression: the fill
  is found (`Capture.FindBackground`: the colour that most of the alpha-255 pixels have, on a sample of one pixel in 67; at least 8 samples of it and a strict
  majority; black when the picture has none), every pixel of exactly that colour with alpha 255 becomes void (0, 0, 0, 0), and a tile that has nothing
  else is an empty tile. It applies to the tiles of every set (main level, floor below, outside, preload), because a tile is stored under the name of its
  level and not of its role: the main level of today is the floor below of tomorrow and the cache gives the same file to both, so what is in a tile must not
  depend on who asked for it first. `Gen.VOID_FILL_SETS` (`{main = true, below = true, outside = true, preload = true}`) says which sets get it; a set left
  out is compressed as it is, except that a tile that is nothing but the fill becomes an empty tile. The solid earth or the sky of the current level
  thus becomes transparent and lets the outside and the floor below show through.
  It is the colour that counts, not the alpha alone: translucent geometry drawn over the fill keeps alpha 255 with its own colour at its edges (dark
  greens, near blacks; measured 0.01 to 0.7 % of the alpha-255 pixels on funkis, canals, coast_07 and everpine, never a whole area), and those pixels stay
  solid. A pixel that is almost the fill (a channel off by one, an alpha of 254, geometry of the same colour with alpha 1) is never touched. Limit: a
  picture where a translucent surface of one flat colour covers more of the alpha-255 pixels than the fill itself would take that colour for the fill
  (not seen). The pass costs about 0.1 ms to find the colour and, on a 1024 x 1024 tile, under 1 ms when there is none of it and about 5 ms when the tile is
  almost all of it (once per tile; measured with a lua_job, not under the test runner). Measured with `tests/minimap/void_survey_job.lua`.
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
- **Sloped floors.** A slab is a horizontal box, so a ramp or a staircase still crosses several levels: on a slope under a ceiling that follows the floor
  the top of the slab changes about every 64 units of rise (the window between the head and the ceiling slides; the roundest height in it stays while it is in
  it); under a flat roof the top stays and only the thickness changes. Measured on 17 recorded staircases and ramps of 4 maps: 92 levels (the rule before,
  anchors with a memory of the path: 155; the fewest horizontal boxes possible on those paths: 41). Before 2026-11-22 the tiles of floors were named
  `f<floor>c<class>`: they are not used any more (they stay in the cache until it is trimmed or cleared).
- **A room whose ceiling changes height** (a gallery, a room with a lowered part, a shop opening on a taller hall) gives two levels, one for each ceiling,
  when the roundest height of one window is not in the other; the display keeps the one it shows while it is still right and its tile is there.
- **Props placed afterwards.** The map shows only what the level creates. A prop a server added, or one the player spawned, is not on the
  map.
- **Time.** The first visit to a large map generates tiles for as long as it takes; the radar works meanwhile, only the background is
  missing.
