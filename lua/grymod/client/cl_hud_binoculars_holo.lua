-- The hologram of the binoculars (what the original's CryVision does to what you spot): the entity is drawn again with a flat additive material and
-- a fine scan-line texture over its WHOLE body, and a thin outline of the same colour round it, instead of the selection-like aura of a halo (see
-- the captures of the Crysis Remastered, docs/superpowers/plans). What is drawn, and in which colour:
--   * a hostile NPC in view (within the scan range) is green from the start (option gry_binoculars_baseline), even before it is spotted;
--   * the NPC the binoculars scan turns WHITE for the last Holo.WHITE_SECONDS (0.3 s) of its scan, the same strength, only the colour changes;
--     when the scan ends it is SPOTTED (the server is told, the radar shows it) and goes back to green;
--   * an ally (or a neutral NPC) is not drawn at the start; when it is scanned it pulses from white to blue once, and nothing stays (no label: the
--     original's "name and distance" box belongs to the objective markers);
--   * a weapon lying on the ground (nobody holds it) within 10 m is blue at baseline and white while the player aims at it; a carried weapon is never lit on its own: it is part of its holder's silhouette (a lit hostile) or nothing (an ally);
-- What the server says about the side of an NPC (ally, neutral, hostile) comes in a batch (sh_relations.lua), at most three questions a second.
--
-- How, and why: the fill is the model drawn with render.MaterialOverride (an UnlitGeneric, additive, its texture a small render target painted with
-- bright and dim rows, tiled over the model's own texture coordinates: the rows follow the model, they are not screen lines, which would need the
-- stencil buffer) in PostDrawTranslucentRenderables; the outline is the game's halo with one tiny blur (the cheapest outline the engine has without
-- a stencil of our own: it already renders the model into a mask and draws only OUTSIDE of it, so it never covers the fill). Both are
-- depth-tested: a soldier behind a wall is not drawn. At most Holo.MAX (16) entities, the nearest ones.
--
-- Two ways to draw it, chosen by gry_binoculars_holo_style:
--   "crysis" (the default): the original's own method, ported to a pixel shader (dev_resources/shaders/grymod_vision_ps20b.hlsl). The entities are drawn flat,
--     in their colour, into a screen-sized buffer (alpha 1 where one is; depth-tested against the scene); a full-screen pass finds the boundary of that
--     alpha (three neighbours a few pixels away), fills the whole body, brightens the boundary, puts the scan lines (a bright and a dim pixel row) and the
--     vignette on it, and adds a blurred glow. See docs/superpowers/plans/2026-11-23-cryvision-shader-research.md for the original's numbers.
--   "simple": what is described above (an additive scan-line material and the game's halo as the outline). It is also what the game falls back to
--     when it cannot run the shader (a test draw tells, as for the camouflage's shader).
--
-- Nothing runs while the binoculars are down: the four hooks (PostDrawTranslucentRenderables, PreDrawHalos, HUDPaint, RenderScreenspaceEffects) are added
-- when they go up (GryMod_BinocularsToggled) and removed when they go down; the entities in view are looked for five times a second, not at every frame.

GryMod = GryMod or {}

local Bino = GryMod.FlashBinoculars

local Holo = GryMod.BinocularsHolo or {}
GryMod.BinocularsHolo = Holo

local HologramConVar = CreateClientConVar("gry_binoculars_hologram", "1", true, false, "What the binoculars spot is drawn as a hologram: a thin outline and the whole body filled with scan lines, green for a hostile, white while it is scanned, blue for an ally (off: the pale blue halo of earlier versions). Needs the outline switch")
local StyleConVar = CreateClientConVar("gry_binoculars_holo_style", "crysis", true, false, "How the hologram is drawn: crysis (the original's method, a pixel shader: the whole body filled, a brighter boundary, scan lines, a glow) or simple (an additive scan-line material and a halo outline; also what is used when the game cannot run the shader)")
local BaselineConVar = CreateClientConVar("gry_binoculars_baseline", "1", true, false, "The hostile NPCs in view of the binoculars are drawn green at once, before the binoculars have spotted them (as in the original); off: only what the scan reaches")

-- ---------------------------------------------------------------------------------------------------------
-- The numbers (named so that one place changes them)
-- ---------------------------------------------------------------------------------------------------------

-- How many entities at most (the nearest ones).
Holo.MAX = 16
-- Seconds between two looks for the entities in view.
Holo.REFRESH = 0.2
-- The white phase: the last seconds of a scan (the original's silhouette constant, 0.3 s; the owner saw 0.2 to 0.5 s).
Holo.WHITE_SECONDS = Bino.SILHOUETTE_SECONDS
-- How far a hostile NPC is looked for (the binoculars' own range) and a weapon on the ground, in metres.
Holo.NPC_RANGE_METRES = 300
Holo.ITEM_RANGE_METRES = 10 -- the Remaster's i_maxPickupHighlightDist
-- The opacity of the fill (it is added to the picture), and the outline: the blur and the passes of the halo.
Holo.FILL_ALPHA = 0.35
Holo.OUTLINE_BLUR = 1
Holo.OUTLINE_PASSES = 2
-- The side of the scan-line texture (texels), the rows lit, the level of the dim rows (0 to 255), and how often it is repeated over the model.
Holo.LINES_SIZE = 4
Holo.LINES_LIT_ROWS = 2
Holo.LINES_DIM_LEVEL = 70
Holo.LINES_REPEAT = 24
-- What the server's answer is worth (it carries the alert level too, which changes fast): asked again after this long, and an unanswered question again after RETRY seconds; two questions are this far apart.
Holo.RELATION_TTL = 1
Holo.RELATION_RETRY = 1
Holo.ASK_GAP = 0.4

-- green, amber and red are the Remaster's own colours of a hostile by alert level (read in its program: the line colour #44633E when idle, (220,178,121) alerted,
-- (127,49,45) in combat); the boundary and the glow of the shader make them brighter than these flat values.
Holo.Colours = {
	green = {68, 99, 62},
	amber = {220, 178, 121},
	red = {127, 49, 45},
	white = {255, 255, 255},
	blue = {50, 90, 255}
}

function Holo.Enabled()
	return HologramConVar:GetBool() and Bino.SilhouetteEnabled()
end

function Holo.BaselineEnabled()
	return BaselineConVar:GetBool()
end

-- "crysis" or "simple" from what the convar holds (anything but "simple" is crysis).
function Holo.StyleName(value)
	if type(value) == "string" and string.lower(string.Trim(value)) == "simple" then
		return "simple"
	end

	return "crysis"
end

-- What is drawn: "crysis" (the shader), "simple", or "pending" (crysis is wanted and the test draw has not told yet whether the game can run the shader:
-- nothing is drawn for that one frame, instead of a frame of the other style). `works` is true, false or nil (not tested yet).
function Holo.ModeFor(style, works)
	if style ~= "crysis" then
		return "simple"
	end

	if works == nil then
		return "pending"
	end

	return works and "crysis" or "simple"
end

-- The style in force. One read of the convar at every call (the draw hooks), the text is only worked out again when it changed.
local styleText = StyleConVar:GetString()
local style = Holo.StyleName(styleText)

function Holo.Style()
	local text = StyleConVar:GetString()

	if text ~= styleText then
		styleText, style = text, Holo.StyleName(text)
	end

	return style
end

-- ---------------------------------------------------------------------------------------------------------
-- The pure parts
-- ---------------------------------------------------------------------------------------------------------

-- The phase of an entity: "white" when it is the one being scanned in the last 0.3 s, "spotted" once the binoculars found it, else "none".
function Holo.PhaseOf(entity, whiteEntity, tagged)
	if entity ~= nil and entity == whiteEntity then
		return "white"
	end

	if tagged then
		return "spotted"
	end

	return "none"
end

-- The colour name of a hostile's alert level (0 idle, 1 alerted, 2 and more in combat): "green", "amber" or "red".
function Holo.LevelStyle(level)
	if type(level) ~= "number" or level ~= level or level < 1 then
		return "green"
	end

	return level >= 2 and "red" or "amber"
end

-- The colour of an NPC: "white", "green", "amber", "red", "pulse" (white to blue, once) or nil (not drawn). relation is what the server said ("hostile", "ally",
-- "neutral") or nil while it did not answer yet; level is its alert level (0 when unknown).
--   hostile: white while scanned, else by its alert level (green idle, amber alerted, red in combat) once spotted, and before that only with the baseline;
--   ally and neutral: only the pulse while scanned (nothing stays);
--   unknown: white while scanned (the answer comes in a moment), nothing else.
function Holo.NpcStyle(relation, phase, baseline, level)
	if relation == "hostile" then
		if phase == "white" then
			return "white"
		end

		if phase == "spotted" or baseline then
			return Holo.LevelStyle(level)
		end

		return nil
	end

	if phase == "white" then
		return relation == nil and "white" or "pulse"
	end

	return nil
end

-- The colour of a weapon lying on the ground (the Remaster's captures: the blue ones are on the ground): white while the player aims at it, else blue
-- at baseline (within range, as the enemies are lit before they are spotted), else nothing.
function Holo.ItemStyle(aimed, baseline)
	if aimed then
		return "white"
	end

	if baseline then
		return "blue"
	end

	return nil
end

-- Whether a weapon is an item of its own: nobody holds it (no owner) and it is not attached to a character (a bone-merged weapon has the character as its parent).
-- A carried weapon is never lit on its own: it follows its holder (see Holo.CarriedWeapon).
function Holo.IsGroundItem(hasOwner, parentIsCharacter)
	return not hasOwner and not parentIsCharacter
end

-- The weapon an NPC holds, to be drawn with it as part of its silhouette; nil when it holds none.
function Holo.CarriedWeapon(npc)
	if npc == nil or not isfunction(npc.GetActiveWeapon) then
		return nil
	end

	local weapon = npc:GetActiveWeapon()

	if IsValid(weapon) then
		return weapon
	end

	return nil
end

-- How far a white scan is, from 0 (it just began) to 1 (its end), from the seconds left on the scan's timer.
function Holo.PulseProgress(timer)
	local t = 1 - timer / Holo.WHITE_SECONDS

	if t ~= t then
		return 0
	end

	return math.Clamp(t, 0, 1)
end

-- The colour (r, g, b) of a style name; "pulse" goes from white to blue with `progress`.
function Holo.Rgb(name, progress)
	local c = Holo.Colours

	if name == "pulse" then
		local t = math.Clamp(progress or 0, 0, 1)
		local w, b = c.white, c.blue

		return w[1] + (b[1] - w[1]) * t, w[2] + (b[2] - w[2]) * t, w[3] + (b[3] - w[3]) * t
	end

	local rgb = c[name] or c.white

	return rgb[1], rgb[2], rgb[3]
end

-- The cosine of the half angle of the cone in which entities are looked for: the field of view in force, widened for the corners of a wide screen.
function Holo.ConeCos(fov)
	if type(fov) ~= "number" or fov ~= fov or fov <= 0 then
		fov = 75
	end

	return math.cos(math.rad(math.min(fov * 0.9, 89)))
end

-- The nearest `max` of a list of {dist = ...} entries, in place and in order (the table comes back).
function Holo.Nearest(list, max)
	table.sort(list, function(a, b) return a.dist < b.dist end)

	for i = #list, max + 1, -1 do
		list[i] = nil
	end

	return list
end

-- The indices that must be asked of the server: those with no answer and not asked in the last RETRY seconds, or answered more than TTL seconds ago
-- (cache: [index] = {relation, answered, asked}). At most `max`, each once.
function Holo.Pending(indices, cache, now, max)
	local out, seen = {}, {}

	for i = 1, #indices do
		local index = indices[i]

		if not seen[index] and #out < max then
			seen[index] = true

			local e = cache[index]

			if not e or (e.answered == nil and now - e.asked >= Holo.RELATION_RETRY) or (e.answered ~= nil and now - e.answered >= Holo.RELATION_TTL) then
				out[#out + 1] = index
			end
		end
	end

	return out
end

-- ---------------------------------------------------------------------------------------------------------
-- What the server says about the sides
-- ---------------------------------------------------------------------------------------------------------

local relations = {} -- [entity index] = {relation, answered, asked}
local lastAsk = -math.huge

function Holo.RelationOfIndex(index)
	local e = relations[index]

	return e and e.relation or nil
end

-- The alert level (0 to 2) the server last said for an entity index; 0 when it did not say.
function Holo.LevelOfIndex(index)
	local e = relations[index]

	return e and e.level or 0
end

function Holo.RelationOf(entity)
	if not IsValid(entity) then
		return nil
	end

	return Holo.RelationOfIndex(entity:EntIndex())
end

-- The question to the server (replaceable by the tests).
function Holo.Send(indices)
	net.Start("gry_relations_ask")
	GryMod.Relations.WriteQuery(indices)
	net.SendToServer()
end

-- Asks for what is missing, at most once in ASK_GAP seconds.
function Holo.Ask(indices, now)
	if now - lastAsk < Holo.ASK_GAP then
		return false
	end

	local pending = Holo.Pending(indices, relations, now, GryMod.Relations.MAX)

	if #pending == 0 then
		return false
	end

	lastAsk = now

	for i = 1, #pending do
		local e = relations[pending[i]] or {}
		e.asked = now
		relations[pending[i]] = e
	end

	Holo.Send(pending)

	return true
end

function Holo.OnAnswer(list, now)
	for i = 1, #list do
		local e = relations[list[i].index] or {asked = now}
		e.relation, e.answered, e.level = list[i].relation, now, list[i].level or 0
		relations[list[i].index] = e
	end
end

net.Receive("gry_relations", function()
	Holo.OnAnswer(GryMod.Relations.ReadAnswer(), RealTime())
end)

function Holo.ForgetRelations()
	relations = {}
	lastAsk = -math.huge
end

-- ---------------------------------------------------------------------------------------------------------
-- The entities in view
-- ---------------------------------------------------------------------------------------------------------

-- The entries {ent, kind ("npc" or "item"), dist (units)} found at the last look, nearest first.
Holo.entries = {}
local nextRefresh = 0

local function liveNpc(ent)
	return GryMod.API.IsCreature(ent) and ent:Health() > 0
end

-- Looks for the entities in view: hostile-looking NPCs within the range, weapons within theirs, always the entity aimed at and the one scanned.
-- Asks the server about the NPCs. Returns the list (also Holo.entries).
function Holo.Look(ply, now)
	local eye, forward = ply:EyePos(), ply:EyeAngles():Forward()
	local found = ents.FindInCone(eye, forward, Bino.RANGE, Holo.ConeCos(ply:GetFOV()))
	local itemRange2 = (Holo.ITEM_RANGE_METRES * Bino.UNITS_PER_METRE) ^ 2
	local list, asks, seen = {}, {}, {}

	local function add(ent)
		if seen[ent] or not IsValid(ent) or ent == ply then
			return
		end

		seen[ent] = true

		local dist2 = eye:DistToSqr(ent:GetPos())

		if liveNpc(ent) then
			list[#list + 1] = {ent = ent, kind = "npc", dist = math.sqrt(dist2)}
			asks[#asks + 1] = ent:EntIndex()
		elseif ent:IsWeapon() then
			local parent = ent:GetParent()
			local carried = not Holo.IsGroundItem(IsValid(ent:GetOwner()), IsValid(parent) and (parent:IsNPC() or parent:IsPlayer()))

			-- (a carried weapon is not an item: it follows its holder; the weapon the player aims at is drawn from any distance)
			if not carried and (dist2 <= itemRange2 or ent == Bino.Aimed) then
				list[#list + 1] = {ent = ent, kind = "item", dist = math.sqrt(dist2)}
			end
		end
	end

	for i = 1, #found do
		add(found[i])
	end

	-- what the player aims at and what the scan holds are in the list even when the cone missed them
	add(Bino.Aimed)
	add(Bino.ScanState and Bino.ScanState.current)

	Holo.entries = Holo.Nearest(list, Holo.MAX)
	Holo.Ask(asks, now)

	return Holo.entries
end

-- The colour name of an entry for this frame, or nil; `progress` is the white scan's (for "pulse").
function Holo.StyleOf(entry, whiteEntity, aimed, baseline)
	local ent = entry.ent

	if entry.kind == "item" then
		return Holo.ItemStyle(ent == aimed, baseline)
	end

	return Holo.NpcStyle(Holo.RelationOf(ent), Holo.PhaseOf(ent, whiteEntity, Bino.IsTagged(ent)), baseline, Holo.LevelOfIndex(ent:EntIndex()))
end

-- ---------------------------------------------------------------------------------------------------------
-- The drawing
-- ---------------------------------------------------------------------------------------------------------

-- Painted once, at the first frame the hologram is up: a small render target of bright and dim rows and the material that uses it.
local lines = {}

local function paintLines()
	local size = Holo.LINES_SIZE

	for y = 0, size - 1 do
		local level = y < Holo.LINES_LIT_ROWS and 255 or Holo.LINES_DIM_LEVEL
		surface.SetDrawColor(level, level, level, 255)
		surface.DrawRect(0, y, size, 1)
	end
end

-- Builds the texture and the material once; true when the material is there (without the texture it is a flat fill: the hologram still works).
function Holo.Build()
	if lines.material then
		return true
	end

	local texture = "models/debug/debugwhite"
	local ok, err = pcall(function()
		local target = GetRenderTargetEx("gry_bino_holo_lines", Holo.LINES_SIZE, Holo.LINES_SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 0, 0, IMAGE_FORMAT_RGBA8888)

		render.PushRenderTarget(target)
		render.Clear(0, 0, 0, 255, false, false)
		cam.Start2D()
		local painted, why = pcall(paintLines)
		cam.End2D()
		render.PopRenderTarget()

		if not painted then
			error(why, 0)
		end

		texture = target:GetName()
	end)

	if not ok then
		ErrorNoHalt("GryMod binoculars hologram: the scan lines could not be painted, a flat fill is used: " .. tostring(err) .. "\n")
	end

	lines.material = CreateMaterial("gry_bino_holo_mat", "UnlitGeneric", {
		["$basetexture"] = texture,
		["$basetexturetransform"] = "center 0 0 scale 1 " .. Holo.LINES_REPEAT .. " rotate 0 translate 0 0",
		["$additive"] = 1,
		["$nocull"] = 1,
		["$ignorez"] = 0
	})

	return true
end

-- What was resolved for this frame: {ent, r, g, b} entries (reused) and how many; filled by Holo.Resolve, read by the fill and the outline.
local drawn, drawnCount = {}, 0

-- Whether the hologram may draw this entity: the fill, the halo and the vision buffer draw its model through a material override, and the engine freezes on a model with a mesh too big for its
-- dynamic vertex buffer (cl_cloak_fx.lua, GryMod.CloakFX.ModelTooHeavy). Such an entity is left out (a vehicle or an NPC of a very detailed model). No model to measure: drawn.
function Holo.Drawable(ent)
	local F = GryMod.CloakFX

	if not F or not F.ModelTooHeavy or not IsValid(ent) or not isfunction(ent.GetModel) then
		return true
	end

	local ok, model = pcall(ent.GetModel, ent)

	return not (ok and F.ModelTooHeavy(model))
end

-- Works out the entries to draw this frame (a look five times a second, the colours at every frame: the white phase is short).
function Holo.Resolve(ply, now)
	if now >= nextRefresh then
		nextRefresh = now + Holo.REFRESH
		Holo.Look(ply, now)
	end

	local scan = Bino.ScanState
	local whiteEntity = scan and Bino.SilhouetteTarget(scan, Bino.SilhouetteValid)
	local progress = whiteEntity and Holo.PulseProgress(scan.timer) or 0
	local aimed = Bino.Aimed
	local baseline = Holo.BaselineEnabled()
	local count = 0

	for i = 1, #Holo.entries do
		local entry = Holo.entries[i]

		if IsValid(entry.ent) and not entry.ent:IsDormant() then
			local style = Holo.StyleOf(entry, whiteEntity, aimed, baseline)

			if style and Holo.Drawable(entry.ent) then
				count = count + 1

				local d = drawn[count]

				if not d then
					d = {}
					drawn[count] = d
				end

				d.ent, d.style = entry.ent, style
				-- (what an NPC holds is part of its silhouette: the weapon is a separate entity, drawn in the same colour)
				d.weapon = entry.kind == "npc" and Holo.CarriedWeapon(entry.ent) or nil

				if d.weapon and not Holo.Drawable(d.weapon) then
					d.weapon = nil
				end
				d.r, d.g, d.b = Holo.Rgb(style, progress)
			end
		end
	end

	drawnCount = count

	return count
end

local function wanted()
	return Holo.Enabled() and Bino.Enabled() and Bino.Wanted(LocalPlayer()) and not (GryMod.Minimap and GryMod.Minimap.Capture and GryMod.Minimap.Capture.IsCapturing())
end

-- The fill: each entity drawn again with the hologram material, its colour and a part of the opacity. Everything changed is put back, even on an error.
function Holo.DrawFill(depth, skybox)
	if depth or skybox or not wanted() then
		drawnCount = 0

		return
	end

	-- (the material is built by the HUD hook, see PrepareHud: painting a render target does not belong in the middle of the 3D scene)
	if not lines.material then
		return
	end

	Holo.Resolve(LocalPlayer(), RealTime())

	if drawnCount == 0 then
		return
	end

	render.MaterialOverride(lines.material)
	render.SetBlend(Holo.FILL_ALPHA)

	local ok, err = pcall(function()
		for i = 1, drawnCount do
			local d = drawn[i]

			render.SetColorModulation(d.r / 255, d.g / 255, d.b / 255)
			d.ent:DrawModel()

			if IsValid(d.weapon) then
				d.weapon:DrawModel()
			end
		end
	end)

	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
	render.MaterialOverride(nil)

	if not ok then
		ErrorNoHalt("GryMod binoculars hologram: " .. tostring(err) .. "\n")
	end
end

local outlineColour = Color(255, 255, 255, 255)
local outlineSet = {}

-- The outline: the game's halo, one call for each entity (its colour differs; at most 16), a tiny blur so that it is a thin line.
function Holo.DrawOutline()
	if drawnCount == 0 or not wanted() or Holo.ModeFor(Holo.Style(), Holo.Crysis.works) ~= "simple" then
		return
	end

	for i = 1, drawnCount do
		local d = drawn[i]

		outlineColour.r, outlineColour.g, outlineColour.b = d.r, d.g, d.b
		outlineSet[1] = d.ent
		halo.Add(outlineSet, outlineColour, Holo.OUTLINE_BLUR, Holo.OUTLINE_BLUR, Holo.OUTLINE_PASSES, true, false)
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The "crysis" style: the original's method, as a pixel shader
-- ---------------------------------------------------------------------------------------------------------

local V = Holo.Crysis or {}
Holo.Crysis = V

-- The shader's numbers. The original's own values of FILL, BOOST, STRENGTH and the neighbours' distance are set in its program, which could not be read
-- (see the research notes): these were tuned in the running game on the owner's captures 03 and 11 (thin boundary of 2 px on 1080 with a soft glow, a dim body with scan lines; the Remaster's flat colours are dark, so a stronger BOOST turns every hue to white: 1.3 keeps red red) and each can be changed from the console
-- (lua_run GryMod.BinocularsHolo.Crysis.FILL = 0.15), they are read again at every frame.
V.STRENGTH = 1			-- the whole result's level
V.FILL = 0.12		-- the share of its colour the body is filled with
V.BOOST = 1.3			-- what the boundary adds to the fill (boundary = FILL + BOOST)
V.TAP_1080 = 2			-- how far (pixels, on a 1080 high screen; it follows the height) the three neighbours are that find the boundary
V.GLOW_GAIN = 0.7		-- the level of the blurred glow added round the shape
V.GLOW_DIV = 4			-- the glow's buffer is this fraction of the screen
V.BLUR = 2				-- the game's blur of the glow's buffer (amount, passes)
V.BLUR_PASSES = 2
-- The original's scan lines: one bright pixel row and one dim one, counted in SCREEN pixels, and its vignette (1 = the original's: 1 - distance to the centre).
V.SCAN_PERIOD = 2
V.SCAN_HI = 1.2
V.SCAN_LO = 0.8
V.VIGNETTE = 1
-- The entities are drawn again at the depth they were drawn at: this share of the depth range pulls them towards the eye, so that the depth test lets them
-- through (the original does the same with a small offset). 0: no pull.
V.DEPTH_PULL = 0.00005
-- Draw the entities inside a fresh cam.Start3D (try it when the shapes come out at the wrong place or size).
V.NEST_CAM3D = false

-- The shader (shaders/fxc) and the names of what it draws with. The game keeps the code of a shader name until it is closed: to try another build give it another name here.
V.PIXEL = V.PIXEL or "grymod_vision_ps20b"
V.PROBE_SIZE = 8
-- What the probe must see: the shader (final mode, no glow) fills a uniform green with half of it, times the scan lines; a missing shader gives white, magenta or black.
V.PROBE_FILL = 0.5
V.PROBE_GREEN_MIN, V.PROBE_GREEN_MAX, V.PROBE_OTHER_MAX = 40, 250, 24

-- The factor (0 to 1) that keeps a colour's boundary under FIT_PEAK at the brightest scan row: the boundary is the colour times (FILL + BOOST) times the bright row,
-- and a bright colour (amber, white, blue) would pass 255 in every channel and come out white, more so on a bright background (the boundary is added to it).
-- Dark colours are left as they are.
V.FIT_PEAK = 220

function V.Fit(r, g, b)
	local top = math.max(r, g, b)

	if top <= 0 then
		return 1
	end

	local peak = top * (V.FILL + V.BOOST) * V.SCAN_HI * V.STRENGTH

	return peak > V.FIT_PEAK and V.FIT_PEAK / peak or 1
end

-- The distance (pixels) of the three neighbours that find the boundary, for a screen of this height.
function V.TapPixels(height)
	if type(height) ~= "number" or height ~= height or height <= 0 then
		return 1
	end

	return math.max(1, V.TAP_1080 * height / 1080)
end

-- The glow's buffer size for a screen of w x h.
function V.GlowSize(w, h)
	return math.max(1, math.floor(w / V.GLOW_DIV)), math.max(1, math.floor(h / V.GLOW_DIV))
end

-- Whether a wall must be looked for by a trace: with antialiasing the render target cannot share the scene's depth buffer (the engine gives it an empty one).
function V.NeedsTraceOcclusion(antialias)
	return type(antialias) == "number" and antialias > 1
end

local aaConVar

-- The depth buffer of the vision buffer: shared with the scene's unless antialiasing is on (the engine then gives it an empty one, the depth test would drop
-- every entity: the walls are looked for by a trace instead and the buffer gets its own depth, cleared at each frame).
function V.DepthModeFor(antialias)
	if V.NeedsTraceOcclusion(antialias) then
		return "separate"
	end

	return "shared"
end

-- The four constant registers the shader reads for a draw of `mode` (0: the shape alone into the glow's buffer, 1: the final pass) on a screen of w x h;
-- `into` (optional) is a table of an earlier call, filled again. Row 1: strength, boost, fill, neighbours' distance. Row 2: one pixel (x, y) of the vision
-- buffer, the mode, the glow gain. Row 3: the screen's height, pixels to a period of the lines, bright level, dim level. Row 4: the vignette's strength.
function V.Registers(mode, w, h, into)
	local c = into or {{}, {}, {}, {}}
	local r1, r2, r3, r4 = c[1], c[2], c[3], c[4]

	r1[1], r1[2], r1[3], r1[4] = V.STRENGTH, V.BOOST, V.FILL, V.TapPixels(h)
	r2[1], r2[2], r2[3], r2[4] = 1 / w, 1 / h, mode, V.GLOW_GAIN
	r3[1], r3[2], r3[3], r3[4] = h, V.SCAN_PERIOD, V.SCAN_HI, V.SCAN_LO
	r4[1], r4[2], r4[3], r4[4] = V.VIGNETTE, 0, 0, 0

	return c
end

-- The names of a material's sixteen constants, made once.
local REGISTER_NAMES = {}

for r = 1, 4 do
	REGISTER_NAMES[r] = {}

	for i = 1, 4 do
		REGISTER_NAMES[r][i] = "$c" .. (r - 1) .. "_" .. ({"x", "y", "z", "w"})[i]
	end
end

-- Every SetFloat goes through the engine and the numbers hardly ever change: what a material was last given is kept, and written again whole after a
-- second (so that a change from outside, such as a reload of the materials, cannot stay for long).
local REGISTER_REFRESH = 1
local written = setmetatable({}, {__mode = "k"})

local function writeRegisters(material, registers)
	local last = written[material]
	local now = RealTime()

	if not last or now - last.stamp >= REGISTER_REFRESH then
		last = {stamp = now}
		written[material] = last
	end

	for r = 1, 4 do
		local row, names = registers[r], REGISTER_NAMES[r]

		for i = 1, 4 do
			local key, value = names[i], row[i]

			if last[key] ~= value then
				material:SetFloat(key, value)
				last[key] = value
			end
		end
	end
end

-- The material of a pass: the shader on the engine's screen quad, reading the vision buffer (and a second texture: the glow). `additive`: added to the
-- picture. Both textures are read as they are (no sRGB conversion): the buffers hold colours, and what is written is added in the same units.
local function passMaterial(name, vision, glow, additive)
	return CreateMaterial(name, "screenspace_general", {
		["$pixshader"] = V.PIXEL,
		["$basetexture"] = vision,
		["$texture1"] = glow,
		["$linearread_basetexture"] = "1",
		["$linearread_texture1"] = "1",
		["$ignorez"] = "1",
		["$vertextransform"] = "1",
		["$nocull"] = "1",
		["$additive"] = additive and "1" or "0",
		["$c0_x"] = "1", ["$c0_y"] = "1", ["$c0_z"] = "0.1", ["$c0_w"] = "2",
		["$c1_x"] = "0.001", ["$c1_y"] = "0.001", ["$c1_z"] = "1", ["$c1_w"] = "0.5",
		["$c2_x"] = "1080", ["$c2_y"] = "2", ["$c2_z"] = "1.2", ["$c2_w"] = "0.8",
		["$c3_x"] = "1", ["$c3_y"] = "0", ["$c3_z"] = "0", ["$c3_w"] = "0"
	})
end

-- The test draw: a uniform green buffer, drawn through the shader into a small target, must come out green (a share of it) and not white, magenta or black
-- (a shader the game does not have is drawn as one of those, and Material:IsError() says nothing about it). Sets V.works; returns it.
function V.Probe()
	local green, other = 0, 255

	local ok = pcall(function()
		local size = V.PROBE_SIZE
		local source = GetRenderTarget("GryBinoVisionProbeSrc", size, size)
		local target = GetRenderTarget("GryBinoVisionProbeOut", size, size)
		local material = passMaterial("GryBinoVisionProbe_" .. V.PIXEL, source:GetName(), source:GetName(), false)
		local registers = V.Registers(1, size, size)

		registers[1][1], registers[1][2], registers[1][3], registers[2][4] = 1, 0, V.PROBE_FILL, 0 -- (the final mode, no glow: the glow mode draws the boundary alone, which a uniform buffer has not)

		render.PushRenderTarget(source)
		render.Clear(0, 255, 0, 255, false, false)
		render.PopRenderTarget()

		writeRegisters(material, registers)
		render.PushRenderTarget(target)

		local drawn = pcall(function()
			render.Clear(0, 0, 0, 255, false, false)
			render.SetMaterial(material)
			render.DrawScreenQuad()
			render.CapturePixels()

			local r, g, b = render.ReadPixel(size / 2, size / 2)
			green, other = g, math.max(r, b)
		end)

		render.PopRenderTarget()

		if not drawn then
			green, other = 0, 255
		end
	end)

	V.works = ok and green >= V.PROBE_GREEN_MIN and green <= V.PROBE_GREEN_MAX and other <= V.PROBE_OTHER_MAX
	V.probeGreen, V.probeOther = green, other

	if not V.works then
		ErrorNoHalt("GryMod binoculars hologram: the game cannot run the shader (the probe saw green " .. tostring(green) .. ", other " .. tostring(other) .. "), the simple style is used\n")
	end

	return V.works
end

-- Builds what the style draws with, once (and again when the screen's size changes): the vision buffer (the screen's size, sharing the scene's depth buffer
-- unless antialiasing is on, not filtered), the glow's buffer (smaller, filtered), the flat material the entities are drawn with, and the two pass
-- materials. The first time it also runs the probe. Called from the HUD hook (a render target is painted in 2D, not in the middle of the 3D scene).
-- Returns true when the style can be drawn.
function V.Build()
	local w, h = ScrW(), ScrH()

	if V.works == nil then
		V.Probe()
	end

	if V.works ~= true then
		return false
	end

	aaConVar = aaConVar or GetConVar("mat_antialias")

	local depthMode = V.DepthModeFor(aaConVar and aaConVar:GetInt() or 0)

	if V.built and V.builtW == w and V.builtH == h and V.builtDepth == depthMode then
		return true
	end

	local ok, err = pcall(function()
		-- (the name carries the depth mode: the game keeps the parameters of the first call of a name)
		local suffix = "_" .. w .. "x" .. h .. "_" .. depthMode
		local gw, gh = V.GlowSize(w, h)

		-- (point sampling and clamping: texture flags 1, 4 and 8)
		V.vision = GetRenderTargetEx("GryBinoVision" .. suffix, w, h, RT_SIZE_LITERAL, depthMode == "separate" and MATERIAL_RT_DEPTH_SEPARATE or MATERIAL_RT_DEPTH_SHARED, 1 + 4 + 8, 0, IMAGE_FORMAT_RGBA8888)
		-- (not point sampled: the blur of the game glitches on such a target)
		V.glow = GetRenderTargetEx("GryBinoGlow" .. suffix, gw, gh, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888)

		V.flat = CreateMaterial("GryBinoVisionFlat", "UnlitGeneric", {
			["$basetexture"] = "models/debug/debugwhite"
		})

		-- (the glow's pass must not read the buffer it writes: its second texture is the vision buffer)
		V.rawMaterial = passMaterial("GryBinoVisionRaw" .. suffix .. "_" .. V.PIXEL, V.vision:GetName(), V.vision:GetName(), false)
		V.finalMaterial = passMaterial("GryBinoVisionFinal" .. suffix .. "_" .. V.PIXEL, V.vision:GetName(), V.glow:GetName(), true)
		V.rawRegisters = V.Registers(0, w, h)
		V.finalRegisters = V.Registers(1, w, h)
	end)

	V.built = ok
	V.builtW, V.builtH, V.builtDepth = w, h, depthMode

	if not ok then
		ErrorNoHalt("GryMod binoculars hologram: the crysis style's buffers could not be made: " .. tostring(err) .. "\n")
		V.works = false
	end

	return ok
end

-- Whether a wall hides the entity (a trace from the eye to its centre): only used when antialiasing keeps the render target from the scene's depth.
function V.Hidden(ply, ent)
	local tr = util.TraceLine({start = ply:EyePos(), endpos = ent:WorldSpaceCenter(), filter = {ply, ent}, mask = MASK_OPAQUE})

	return tr.Hit
end

V.visionFrame = nil -- the frame number in which the vision buffer was filled (nil: it holds nothing to show; a field so that the tests can set it)

-- The entities of this frame, flat in their colour, into the vision buffer (alpha 1 where one is). Every state it changes comes back, even on an error.
local function drawEntities(ply, count, traceWalls)
	render.OverrideAlphaWriteEnable(true, true)
	-- (its own depth buffer, with antialiasing: cleared with the colour; shared with the scene's otherwise: left alone)
	render.Clear(0, 0, 0, 0, V.builtDepth == "separate", false)
	render.MaterialOverride(V.flat)
	render.SetBlend(1)

	if V.DEPTH_PULL > 0 then
		render.DepthRange(0, 1 - V.DEPTH_PULL)
	end

	local any = false

	for i = 1, count do
		local d = drawn[i]

		if IsValid(d.ent) and not (traceWalls and V.Hidden(ply, d.ent)) then
			local k = V.Fit(d.r, d.g, d.b) / 255

			render.SetColorModulation(d.r * k, d.g * k, d.b * k)
			d.ent:DrawModel()

			if IsValid(d.weapon) then
				d.weapon:DrawModel()
			end

			any = true
		end
	end

	return any
end

-- PostDrawTranslucentRenderables, the crysis style: fills the vision buffer.
function V.DrawVision(depth, skybox)
	V.visionFrame = nil

	if depth or skybox or not wanted() or not V.built then
		drawnCount = 0

		return
	end

	local ply = LocalPlayer()
	local count = Holo.Resolve(ply, RealTime())

	if count == 0 then
		return
	end

	aaConVar = aaConVar or GetConVar("mat_antialias")

	local traceWalls = V.NeedsTraceOcclusion(aaConVar and aaConVar:GetInt() or 0)
	local any = false

	render.PushRenderTarget(V.vision)

	if V.NEST_CAM3D then
		cam.Start3D()
	end

	local ok, result = pcall(drawEntities, ply, count, traceWalls)

	if V.NEST_CAM3D then
		cam.End3D()
	end

	render.MaterialOverride(nil)
	render.SetColorModulation(1, 1, 1)
	render.SetBlend(1)
	render.OverrideAlphaWriteEnable(false)

	if V.DEPTH_PULL > 0 then
		render.DepthRange(0, 1)
	end

	render.PopRenderTarget()

	if not ok then
		ErrorNoHalt("GryMod binoculars hologram: " .. tostring(result) .. "\n")

		return
	end

	any = result

	if any then
		V.visionFrame = FrameNumber()
	end
end

-- The glow's buffer: the shape alone, small, blurred by the game.
local function drawGlow()
	render.PushRenderTarget(V.glow)

	local ok, err = pcall(function()
		render.Clear(0, 0, 0, 0, false, false)
		writeRegisters(V.rawMaterial, V.Registers(0, ScrW(), ScrH(), V.rawRegisters))
		render.SetMaterial(V.rawMaterial)
		render.DrawScreenQuad()
	end)

	render.PopRenderTarget()

	if not ok then
		error(err, 0)
	end

	-- (the game's blur leaves the blurred buffer as the current render target, measured: every draw after it, the final quad included, then went into the
	-- glow's buffer and nothing showed on the screen. A push and a pop round it give the screen's target back)
	render.PushRenderTarget(V.glow)

	local blurred, why = pcall(render.BlurRenderTarget, V.glow, V.BLUR, V.BLUR, V.BLUR_PASSES)

	render.PopRenderTarget()

	if not blurred then
		error(why, 0)
	end
end

-- RenderScreenspaceEffects, the crysis style: the glow, then the final pass added to the picture (the HUD is drawn after it).
function V.Compose()
	if V.visionFrame ~= FrameNumber() then
		return
	end

	V.visionFrame = nil

	local ok, err = pcall(function()
		drawGlow()
		writeRegisters(V.finalMaterial, V.Registers(1, ScrW(), ScrH(), V.finalRegisters))
		render.SetMaterial(V.finalMaterial)
		render.DrawScreenQuad()
	end)

	if not ok then
		ErrorNoHalt("GryMod binoculars hologram: " .. tostring(err) .. "\n")
	end
end

-- The hook of the 3D scene: one style or the other (nothing for the one frame the probe has not told yet).
function Holo.DrawScene(depth, skybox)
	local mode = Holo.ModeFor(Holo.Style(), V.works)

	if mode == "simple" then
		Holo.DrawFill(depth, skybox)
	elseif mode == "crysis" then
		V.DrawVision(depth, skybox)
	end
end

-- The HUD hook: builds what the hologram draws with, once (the material of the simple style, the buffers and the probe of the crysis style): a render target is
-- painted in 2D, not in the middle of the 3D scene. An aimed ally has no label (the original's "name and distance" box is the objective marker's own, see
-- cl_hud_objectives_flash.lua): it only gets the one pulse from white to blue.
function Holo.PrepareHud()
	if not wanted() or not IsValid(LocalPlayer()) then
		return
	end

	Holo.Build()

	if Holo.Style() == "crysis" then
		V.Build()
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- The hooks: only while the binoculars are up
-- ---------------------------------------------------------------------------------------------------------

local attached = false

function Holo.Attach()
	if attached then
		return
	end

	attached = true
	nextRefresh = 0
	hook.Add("PostDrawTranslucentRenderables", "GRYBINOCULARSHOLO", Holo.DrawScene)
	hook.Add("PreDrawHalos", "GRYBINOCULARSHOLO", Holo.DrawOutline)
	hook.Add("HUDPaint", "GRYBINOCULARSHOLO", Holo.PrepareHud)
	hook.Add("RenderScreenspaceEffects", "GRYBINOCULARSHOLO", V.Compose)
end

function Holo.Detach()
	if not attached then
		return
	end

	attached = false
	drawnCount = 0
	V.visionFrame = nil
	Holo.entries = {}
	hook.Remove("PostDrawTranslucentRenderables", "GRYBINOCULARSHOLO")
	hook.Remove("PreDrawHalos", "GRYBINOCULARSHOLO")
	hook.Remove("HUDPaint", "GRYBINOCULARSHOLO")
	hook.Remove("RenderScreenspaceEffects", "GRYBINOCULARSHOLO")
end

function Holo.Attached()
	return attached
end

-- Puts the hooks right for what is asked now: up with the binoculars up and the hologram on, away otherwise.
function Holo.Sync()
	if wanted() then
		Holo.Attach()
	else
		Holo.Detach()
	end
end

hook.Add("GryMod_BinocularsToggled", "GRYBINOCULARSHOLO", function()
	Holo.Sync()
end)

for _, name in ipairs({"gry_binoculars_hologram", "gry_binoculars_silhouette"}) do
	cvars.AddChangeCallback(name, function()
		Holo.Sync()
	end, "GryBinocularsHolo")
end

-- the binoculars may be up already (a reload of this file)
Holo.Sync()
