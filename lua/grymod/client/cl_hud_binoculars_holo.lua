-- The hologram of the binoculars (what the original's CryVision does to what you spot): the entity is drawn again with a flat additive material and
-- a fine scan-line texture over its WHOLE body, and a thin outline of the same colour round it, instead of the selection-like aura of a halo (see
-- the captures of the Crysis Remastered, docs/superpowers/plans). What is drawn, and in which colour:
--   * a hostile NPC in view (within the scan range) is green from the start (option gry_binoculars_baseline), even before it is spotted;
--   * the NPC the binoculars scan turns WHITE for the last Holo.WHITE_SECONDS (0.3 s) of its scan, the same strength, only the colour changes;
--     when the scan ends it is SPOTTED (the server is told, the radar shows it) and goes back to green;
--   * an ally (or a neutral NPC) is not drawn at the start; when it is scanned it pulses from white to blue once, and nothing stays; while the
--     player aims at it a marker with its NAME and its DISTANCE stays (yellow corner brackets);
--   * a weapon on the ground is drawn white while the player aims at it; a weapon held by an ally is blue (white when aimed).
-- What the server says about the side of an NPC (ally, neutral, hostile) comes in a batch (sh_relations.lua), at most three questions a second.
--
-- How, and why: the fill is the model drawn with render.MaterialOverride (an UnlitGeneric, additive, its texture a small render target painted with
-- bright and dim rows, tiled over the model's own texture coordinates: the rows follow the model, they are not screen lines, which would need the
-- stencil buffer) in PostDrawTranslucentRenderables; the outline is the game's halo with one tiny blur (the cheapest outline the engine has without
-- a stencil of our own: it already renders the model into a mask and draws only OUTSIDE of it, so it never covers the fill). Both are
-- depth-tested: a soldier behind a wall is not drawn. At most Holo.MAX (16) entities, the nearest ones.
--
-- Nothing runs while the binoculars are down: the three hooks (PostDrawTranslucentRenderables, PreDrawHalos, HUDPaint) are added when they go up
-- (GryMod_BinocularsToggled) and removed when they go down; the entities in view are looked for five times a second, not at every frame.

GryMod = GryMod or {}

local Bino = GryMod.FlashBinoculars

local Holo = GryMod.BinocularsHolo or {}
GryMod.BinocularsHolo = Holo

local HologramConVar = CreateClientConVar("gry_binoculars_hologram", "1", true, false, "What the binoculars spot is drawn as a hologram: a thin outline and the whole body filled with scan lines, green for a hostile, white while it is scanned, blue for an ally (off: the pale blue halo of earlier versions). Needs the outline switch")
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
Holo.ITEM_RANGE_METRES = 40
-- The opacity of the fill (it is added to the picture), and the outline: the blur and the passes of the halo.
Holo.FILL_ALPHA = 0.35
Holo.OUTLINE_BLUR = 1
Holo.OUTLINE_PASSES = 2
-- The side of the scan-line texture (texels), the rows lit, the level of the dim rows (0 to 255), and how often it is repeated over the model.
Holo.LINES_SIZE = 4
Holo.LINES_LIT_ROWS = 2
Holo.LINES_DIM_LEVEL = 70
Holo.LINES_REPEAT = 24
-- What the server's answer is worth: asked again after this long, and an unanswered question again after RETRY seconds; two questions are this far apart.
Holo.RELATION_TTL = 5
Holo.RELATION_RETRY = 1
Holo.ASK_GAP = 0.4

Holo.Colours = {
	green = {110, 255, 140},
	white = {255, 255, 255},
	blue = {50, 90, 255}
}

-- The marker of an aimed ally (yellow, as the original's).
Holo.MARK_COLOUR = Color(255, 240, 90)

function Holo.Enabled()
	return HologramConVar:GetBool() and Bino.SilhouetteEnabled()
end

function Holo.BaselineEnabled()
	return BaselineConVar:GetBool()
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

-- The colour of an NPC: "white", "green", "pulse" (white to blue, once) or nil (not drawn). relation is what the server said ("hostile", "ally",
-- "neutral") or nil while it did not answer yet.
--   hostile: white while scanned, green once spotted, green before that only with the baseline;
--   ally and neutral: only the pulse while scanned (nothing stays);
--   unknown: white while scanned (the answer comes in a moment), nothing else.
function Holo.NpcStyle(relation, phase, baseline)
	if relation == "hostile" then
		if phase == "white" then
			return "white"
		end

		if phase == "spotted" or baseline then
			return "green"
		end

		return nil
	end

	if phase == "white" then
		return relation == nil and "white" or "pulse"
	end

	return nil
end

-- The colour of a weapon: white while the player aims at it, blue when an ally holds it, else nothing (a weapon on the ground is only drawn aimed).
function Holo.ItemStyle(ownerRelation, aimed)
	if aimed then
		return "white"
	end

	if ownerRelation == "ally" then
		return "blue"
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

-- The box of a set of screen points: left, top, right, bottom.
function Holo.BoxOf(xs, ys, count)
	local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge

	for i = 1, count do
		l, r = math.min(l, xs[i]), math.max(r, xs[i])
		t, b = math.min(t, ys[i]), math.max(b, ys[i])
	end

	return l, t, r, b
end

-- The text of a distance: whole metres and an M, like the original's.
function Holo.DistanceText(units)
	return math.floor(units / Bino.UNITS_PER_METRE + 0.5) .. "M"
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
		e.relation, e.answered = list[i].relation, now
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

-- The entries {ent, kind ("npc" or "item"), dist (units), owner (an item's holder, or nil)} found at the last look, nearest first.
Holo.entries = {}
local nextRefresh = 0

local function liveNpc(ent)
	return ent:IsNPC() and ent:Health() > 0
end

-- Looks for the entities in view: hostile-looking NPCs within the range, weapons within theirs, always the entity aimed at and the one scanned.
-- Asks the server about the NPCs and the holders of the weapons. Returns the list (also Holo.entries).
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
			local owner = ent:GetOwner()
			local held = IsValid(owner)

			if held and owner:IsNPC() then
				list[#list + 1] = {ent = ent, kind = "item", dist = math.sqrt(dist2), owner = owner}
				asks[#asks + 1] = owner:EntIndex()
			elseif not held and dist2 <= itemRange2 then
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
		return Holo.ItemStyle(entry.owner and Holo.RelationOf(entry.owner) or nil, ent == aimed)
	end

	return Holo.NpcStyle(Holo.RelationOf(ent), Holo.PhaseOf(ent, whiteEntity, Bino.IsTagged(ent)), baseline)
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

			if style then
				count = count + 1

				local d = drawn[count]

				if not d then
					d = {}
					drawn[count] = d
				end

				d.ent, d.style = entry.ent, style
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

	-- (the material is built by the HUD hook, see PaintMarker: painting a render target does not belong in the middle of the 3D scene)
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
	if drawnCount == 0 or not wanted() then
		return
	end

	for i = 1, drawnCount do
		local d = drawn[i]

		outlineColour.r, outlineColour.g, outlineColour.b = d.r, d.g, d.b
		outlineSet[1] = d.ent
		halo.Add(outlineSet, outlineColour, Holo.OUTLINE_BLUR, Holo.OUTLINE_BLUR, Holo.OUTLINE_PASSES, true, false)
	end
end

-- The name of an entity for the marker: the NPC's menu name, else its class' phrase.
function Holo.NameOf(ent)
	if ent:IsPlayer() then
		return ent:Nick()
	end

	local class = ent:GetClass()
	local known = list.Get("NPC")[class]

	if known and known.Name then
		return known.Name
	end

	if isstring(ent.PrintName) and ent.PrintName ~= "" then
		return ent.PrintName
	end

	return language.GetPhrase(class)
end

local corners = {}
local xs, ys = {}, {}

-- The screen box of an entity (left, top, right, bottom), or nil when a corner of it is behind the camera.
function Holo.ScreenBox(ent)
	local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	local n = 0

	for i = 0, 7 do
		corners.x = (i % 2 == 0) and mins.x or maxs.x
		corners.y = (math.floor(i / 2) % 2 == 0) and mins.y or maxs.y
		corners.z = (i >= 4) and maxs.z or mins.z

		local s = ent:LocalToWorld(Vector(corners.x, corners.y, corners.z)):ToScreen()

		if not s.visible then
			return nil
		end

		n = n + 1
		xs[n], ys[n] = s.x, s.y
	end

	return Holo.BoxOf(xs, ys, n)
end

local fontHeight

local function markFont()
	local h = math.max(14, math.floor(ScrH() * 0.026))

	if fontHeight ~= h then
		fontHeight = h
		surface.CreateFont("GryBinoMark", {font = "Trebuchet MS", size = h, weight = 700, antialias = true})
	end

	return "GryBinoMark"
end

-- Also the first thing the HUD hook does is to build the hologram's material (once). The marker of an ally (or a neutral NPC) aimed at: two yellow corner brackets round it, its name at the top left and its distance at the
-- bottom right (the original's box). It stays as long as the player aims at it.
function Holo.PaintMarker()
	local ply = LocalPlayer()

	if not wanted() or not IsValid(ply) then
		return
	end

	Holo.Build()

	local ent = Bino.Aimed

	if not IsValid(ent) or not ent:IsNPC() or ent:Health() <= 0 then
		return
	end

	local relation = Holo.RelationOf(ent)

	if relation == nil or relation == "hostile" then
		return
	end

	local l, t, r, b = Holo.ScreenBox(ent)

	if not l then
		return
	end

	local arm = math.max(8, ScrH() * 0.012)
	local c = Holo.MARK_COLOUR

	surface.SetDrawColor(c.r, c.g, c.b, 255)
	surface.DrawRect(l, t, arm, 2)
	surface.DrawRect(l, t, 2, arm)
	surface.DrawRect(r - arm, b - 2, arm, 2)
	surface.DrawRect(r - 2, b - arm, 2, arm)

	surface.SetFont(markFont())
	surface.SetTextColor(c.r, c.g, c.b, 255)
	surface.SetTextPos(l + 4, t + 2)
	surface.DrawText(Holo.NameOf(ent))

	local text = Holo.DistanceText(ply:EyePos():Distance(ent:GetPos()))
	local w, h = surface.GetTextSize(text)

	surface.SetTextPos(r - w - 4, b - h - 2)
	surface.DrawText(text)
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
	hook.Add("PostDrawTranslucentRenderables", "GRYBINOCULARSHOLO", Holo.DrawFill)
	hook.Add("PreDrawHalos", "GRYBINOCULARSHOLO", Holo.DrawOutline)
	hook.Add("HUDPaint", "GRYBINOCULARSHOLO", Holo.PaintMarker)
end

function Holo.Detach()
	if not attached then
		return
	end

	attached = false
	drawnCount = 0
	Holo.entries = {}
	hook.Remove("PostDrawTranslucentRenderables", "GRYBINOCULARSHOLO")
	hook.Remove("PreDrawHalos", "GRYBINOCULARSHOLO")
	hook.Remove("HUDPaint", "GRYBINOCULARSHOLO")
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
