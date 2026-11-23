-- The campaign objectives, the PURE part (server): what is in a map's list and how it is checked, how a map entity is matched against a completion, the chain of
-- steps (`after`), the progress that is kept between two visits of a map, and the texts. Nothing here touches the world, a hook or the network: the runtime
-- (sv_campaign.lua) calls these functions, and the tests (tests/sv_campaign_core_test.lua) call them on plain tables.
--
-- A map's list is an array of objectives (docs/api.md, "Campaign objectives"). One objective:
--   id, title, description, primary, secret   the same words as the objectives API; `secret = true` is a hidden item (counted, never listed one by one)
--   via     optional: an array of Vectors, the places to pass on the way (16 at most); the route guidance uses them
--   pos (a Vector) or place (an entity's name: its position when the objective is listed)   where it is
--   after   the id (or ids) of the steps that must be done before this one is listed
--   exit    true for the way out of the map (listed from the start when it has no `after`, else after its predecessors like any step); a `changelevel` completion is an exit by default
--   complete, fail   what finishes it, what fails it (a "completion", below)
--   tr      {fr = {title = "...", description = "..."}}: the same texts in another language (the English ones are the default)
-- A completion is {kind = ..., ...}; the kinds are in C.Kinds and each one names the fields it needs.

GryMod = GryMod or {}

local C = GryMod.Campaign or {}
GryMod.Campaign = C

local lower = string.lower

-- What finishes an objective. The runtime listens for the kind only while an objective that uses it is waiting.
--   input          a map entity (entity) receives an input (input): the map's own scripts say "this happened"
--   pickup         the player takes a weapon (class "weapon_*") or an item (class "item_*")
--   enter_vehicle  the player gets into a vehicle (class, or entity)
--   use            the player presses the use key on an entity (entity, or mapid, or class and at)
--   changelevel    the player leaves for another map (target) through the exit trigger
--   removed        an entity goes (entity, or class)
--   killed         an NPC dies (entity, or class)
C.Kinds = {input = true, pickup = true, enter_vehicle = true, use = true, changelevel = true, removed = true, killed = true}

-- What may fail an objective (a map's own "game over" message, the death of an ally, the loss of the vehicle).
C.FailKinds = {input = true, removed = true, killed = true}

C.Limits = {id = 64, title = 128, description = 512, name = 64, count = 200, after = 8, lang = 8, via = 16}

C.AtRadius = 8 -- units: how near the place of an entity without a name must be (a `use` completion with `at`)
C.SecretsId = "campaign.secrets" -- the id of the one objective that counts the secrets

-- The texts the system itself shows, by language. English is the default; another language is a new table here.
C.Strings = {
	en = {secrets_title = "Secrets %d/%d", secrets_description = "Hidden items on this map. Look around."},
	fr = {secrets_title = "Secrets %d/%d", secrets_description = "Objets cach\195\169s sur cette carte. Cherchez bien."}
}

local LIMITS = C.Limits

-- ---------------------------------------------------------------------------------------------------------
-- The check of a list
-- ---------------------------------------------------------------------------------------------------------

local function finite(n)
	return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

local function validVector(v)
	return isvector(v) and finite(v.x) and finite(v.y) and finite(v.z)
end

local function validText(s, max)
	return isstring(s) and #s >= 1 and #s <= max
end

-- Checks one completion. `allowed`: the table of the kinds that make sense here (C.Kinds, or C.FailKinds for a failure). Returns a clean copy (the fields the
-- kind knows; `also`, one alternative, is checked the same way), or false and why. Nothing is raised, whatever is given.
function C.CheckCompletion(c, allowed, nested)
	if not istable(c) then
		return false, "invalid completion: it must be a table"
	end

	allowed = allowed or C.Kinds

	local kind = c.kind

	if not isstring(kind) or not allowed[kind] then
		return false, "invalid kind: one of " .. (allowed == C.FailKinds and "input, removed, killed" or "input, pickup, enter_vehicle, use, changelevel, removed, killed")
	end

	local out = {kind = kind}

	for _, field in ipairs({"entity", "class", "input", "target"}) do
		local v = c[field]

		if v ~= nil then
			if not validText(v, LIMITS.name) then
				return false, "invalid " .. field .. ": a text of 1 to " .. LIMITS.name .. " characters"
			end

			out[field] = v
		end
	end

	if c.mapid ~= nil then
		if not finite(c.mapid) or c.mapid < 0 or c.mapid ~= math.floor(c.mapid) then
			return false, "invalid mapid: a whole number, the Entity:MapCreationID() of the entity"
		end

		out.mapid = c.mapid
	end

	if c.at ~= nil then
		if not validVector(c.at) then
			return false, "invalid at: a Vector with finite numbers"
		end

		out.at = Vector(c.at.x, c.at.y, c.at.z)
	end

	if c.radius ~= nil then
		if not finite(c.radius) or c.radius <= 0 then
			return false, "invalid radius: a number above 0"
		end

		out.radius = c.radius
	end

	-- what each kind needs to find its entity
	if kind == "input" then
		if not out.entity then
			return false, "an input completion needs an entity (the name of the map entity that receives the input)"
		end

		if not out.input then
			return false, "an input completion needs an input (the name of the input, \"Open\" for example)"
		end
	elseif kind == "pickup" then
		if not out.class then
			return false, "a pickup completion needs a class (\"weapon_rpg\" for example)"
		end
	elseif kind == "enter_vehicle" then
		if not out.class and not out.entity then
			return false, "an enter_vehicle completion needs a class or an entity"
		end
	elseif kind == "use" then
		if not out.entity and not out.mapid and not (out.class and out.at) then
			return false, "a use completion needs an entity, a mapid, or a class with an at (a class alone points at every such entity of the map)"
		end
	elseif kind == "changelevel" then
		if not out.target then
			return false, "a changelevel completion needs a target (the name of the next map)"
		end
	else -- removed, killed
		if not out.entity and not out.class and not out.mapid then
			return false, "a " .. kind .. " completion needs an entity, a class or a mapid"
		end
	end

	if c.also ~= nil then
		if nested then
			return false, "invalid also: an alternative cannot have an alternative"
		end

		local also, why = C.CheckCompletion(c.also, allowed, true)

		if not also then
			return false, "invalid also: " .. why
		end

		out.also = also
	end

	return out
end

-- The translations: {fr = {title = ..., description = ...}}. Returns a clean copy, or false and why.
local function checkTranslations(tr)
	if not istable(tr) then
		return false, "invalid tr: a table by language, {fr = {title = \"...\"}}"
	end

	local out = {}

	for lang, texts in pairs(tr) do
		if not validText(lang, LIMITS.lang) or not istable(texts) then
			return false, "invalid tr: a table by language, {fr = {title = \"...\"}}"
		end

		local one = {}

		if texts.title ~= nil then
			if not validText(texts.title, LIMITS.title) then
				return false, "invalid tr: the title in " .. lang .. " is a text of 1 to " .. LIMITS.title .. " characters"
			end

			one.title = texts.title
		end

		if texts.description ~= nil then
			if not isstring(texts.description) or #texts.description > LIMITS.description then
				return false, "invalid tr: the description in " .. lang .. " is a text of " .. LIMITS.description .. " characters at most"
			end

			one.description = texts.description
		end

		out[lang] = one
	end

	return out
end

-- Checks one objective. Returns a clean copy (what the developer gave and the defaults for the rest; fields that are not known, `proof` for one, are left
-- out), or false and why; the reason names the field. Nothing is raised, whatever is given.
function C.CheckObjective(def)
	if not istable(def) then
		return false, "invalid objective: a table with an id, a title, a position and a completion"
	end

	local id = def.id

	if not validText(id, LIMITS.id) then
		return false, "invalid id: a text of 1 to " .. LIMITS.id .. " characters"
	end

	local out = {id = id}

	if not validText(def.title, LIMITS.title) then
		return false, "invalid title: a text of 1 to " .. LIMITS.title .. " characters"
	end

	out.title = def.title

	if def.description == nil then
		out.description = ""
	elseif isstring(def.description) and #def.description <= LIMITS.description then
		out.description = def.description
	else
		return false, "invalid description: a text of " .. LIMITS.description .. " characters at most"
	end

	for _, field in ipairs({"primary", "secret", "exit"}) do
		if def[field] ~= nil and not isbool(def[field]) then
			return false, "invalid " .. field .. ": true or false"
		end
	end

	out.primary = def.primary == nil and true or def.primary
	out.secret = def.secret == true

	if def.pos ~= nil then
		if not validVector(def.pos) then
			return false, "invalid pos: a Vector with finite numbers"
		end

		out.pos = Vector(def.pos.x, def.pos.y, def.pos.z)
	end

	if def.place ~= nil then
		if not validText(def.place, LIMITS.name) then
			return false, "invalid place: the name of an entity (1 to " .. LIMITS.name .. " characters)"
		end

		out.place = def.place
	end

	if not out.pos and not out.place then
		return false, "give a pos (a Vector) or a place (the name of an entity: its position is used)"
	end

	-- the places to pass on the way, in order (the same field as the objectives API: a straight line from the start crosses walls)
	if def.via ~= nil then
		if not istable(def.via) or #def.via > C.Limits.via then
			return false, "invalid via: a list of " .. C.Limits.via .. " Vectors at most"
		end

		out.via = {}

		for i, v in ipairs(def.via) do
			if not validVector(v) then
				return false, "invalid via: every waypoint is a Vector with finite numbers"
			end

			out.via[i] = Vector(v.x, v.y, v.z)
		end

		if #out.via == 0 then
			out.via = nil
		end
	end

	out.after = {}

	if def.after ~= nil then
		local list = isstring(def.after) and {def.after} or def.after

		if not istable(list) or #list > LIMITS.after then
			return false, "invalid after: the id of a step, or a list of " .. LIMITS.after .. " ids at most"
		end

		for i, a in ipairs(list) do
			if not validText(a, LIMITS.id) then
				return false, "invalid after: the id of a step, or a list of " .. LIMITS.after .. " ids at most"
			end

			out.after[i] = a
		end
	end

	local complete, why = C.CheckCompletion(def.complete, C.Kinds)

	if not complete then
		return false, "invalid complete: " .. (def.complete == nil and "every objective needs one" or why)
	end

	out.complete = complete
	out.exit = def.exit == nil and complete.kind == "changelevel" or def.exit == true

	if def.fail ~= nil then
		local fail, whyFail = C.CheckCompletion(def.fail, C.FailKinds)

		if not fail then
			return false, "invalid fail: " .. whyFail
		end

		out.fail = fail
	end

	if def.tr ~= nil then
		local tr, whyTr = checkTranslations(def.tr)

		if not tr then
			return false, whyTr
		end

		out.tr = tr
	end

	return out
end

-- Checks a whole list (what RegisterCampaignMap gets). Returns the clean list, or false and why (the number and the id of the objective that is wrong).
function C.CheckList(list)
	if not istable(list) then
		return false, "invalid list: an array of objectives"
	end

	if #list > LIMITS.count then
		return false, "too many objectives (" .. LIMITS.count .. " at most)"
	end

	local out, seen = {}, {}

	for i, def in ipairs(list) do
		local clean, why = C.CheckObjective(def)

		if not clean then
			local id = istable(def) and def.id

			return false, "objective #" .. i .. (isstring(id) and (" (\"" .. id .. "\")") or "") .. ": " .. why
		end

		if seen[clean.id] then
			return false, "objective #" .. i .. " (\"" .. clean.id .. "\"): the id is given twice"
		end

		seen[clean.id] = true
		out[i] = clean
	end

	return out
end

-- The list as the runtime can use it: an objective whose chain cannot start (a predecessor that is not in the list, a loop) is dropped. Returns the list and
-- the reasons, one text for each objective dropped.
function C.Resolve(list)
	local byId = {}

	for _, d in ipairs(list) do
		byId[d.id] = d
	end

	local good, changed = {}, true

	while changed do
		changed = false

		for _, d in ipairs(list) do
			if not good[d.id] then
				local all = true

				for _, a in ipairs(d.after) do
					if not good[a] then
						all = false

						break
					end
				end

				if all then
					good[d.id] = true
					changed = true
				end
			end
		end
	end

	local out, problems = {}, {}

	for _, d in ipairs(list) do
		if good[d.id] then
			out[#out + 1] = d
		else
			local why = "part of a loop of `after`, or after one that is dropped"

			for _, a in ipairs(d.after) do
				if not byId[a] then
					why = "its predecessor \"" .. a .. "\" is not in the list"

					break
				end
			end

			problems[#problems + 1] = d.id .. ": " .. why
		end
	end

	return out, problems
end

-- ---------------------------------------------------------------------------------------------------------
-- A third party's list on top of another
-- ---------------------------------------------------------------------------------------------------------

-- `extra` on top of `base`: an objective of the same id replaces the one of `base` where it stood, a new one goes at the end. Neither argument is changed.
function C.MergeLists(base, extra)
	local out, at = {}, {}

	for i, d in ipairs(base) do
		out[i] = d
		at[d.id] = i
	end

	for _, d in ipairs(extra) do
		local i = at[d.id]

		if i then
			out[i] = d
		else
			out[#out + 1] = d
			at[d.id] = #out
		end
	end

	return out
end

-- The list without the objective `id`. The steps that came after it now come after what it came after, so the chain goes on. The argument is not changed.
function C.RemoveId(list, id)
	local removed

	for _, d in ipairs(list) do
		if d.id == id then
			removed = d
		end
	end

	if not removed then
		return list
	end

	local out = {}

	for _, d in ipairs(list) do
		if d.id ~= id then
			local needs = false

			for _, a in ipairs(d.after) do
				if a == id then
					needs = true
				end
			end

			if needs then
				local copy, have = {}, {}

				for k, v in pairs(d) do
					copy[k] = v
				end

				copy.after = {}

				for _, a in ipairs(d.after) do
					if a ~= id and not have[a] then
						have[a] = true
						copy.after[#copy.after + 1] = a
					end
				end

				for _, a in ipairs(removed.after) do
					if not have[a] then
						have[a] = true
						copy.after[#copy.after + 1] = a
					end
				end

				d = copy
			end

			out[#out + 1] = d
		end
	end

	return out
end

-- ---------------------------------------------------------------------------------------------------------
-- A map entity against a completion
-- ---------------------------------------------------------------------------------------------------------

-- Whether the entity's name is the wanted one. A map's names are not case sensitive. An entity made by a point_template is renamed "name&0003" (and the
-- number changes at each spawn), so that form counts too. Nothing else does: "jeep2" is not "jeep".
function C.NameMatches(actual, wanted)
	if not isstring(actual) or actual == "" or not isstring(wanted) or wanted == "" then
		return false
	end

	actual, wanted = lower(actual), lower(wanted)

	if actual == wanted then
		return true
	end

	local n = #wanted

	return #actual > n + 1 and actual:sub(1, n) == wanted and actual:sub(n + 1, n + 1) == "&" and actual:find("^%d+$", n + 2) ~= nil
end

-- Whether `ent` is what the completion `c` names. Every field the completion gives must hold (the name with NameMatches, the class, the Entity:MapCreationID,
-- the place within `radius` units of `at`); a completion that names nothing matches nothing. One exception: a pickup or a vehicle that gives a class is found
-- by the class alone (its `entity` only helps to put the marker where the weapon lies: a weapon the map hands over has another name).
function C.Matches(c, ent)
	if ent == nil or not IsValid(ent) then
		return false
	end

	if c.class and ent:GetClass() ~= c.class then
		return false
	end

	if c.class and (c.kind == "pickup" or c.kind == "enter_vehicle") then
		return true
	end

	if c.entity and not C.NameMatches(ent:GetName(), c.entity) then
		return false
	end

	if c.mapid and ent:MapCreationID() ~= c.mapid then
		return false
	end

	if c.at then
		local r = c.radius or C.AtRadius

		if ent:GetPos():DistToSqr(c.at) > r * r then
			return false
		end
	end

	return c.class ~= nil or c.entity ~= nil or c.mapid ~= nil or c.at ~= nil
end

-- Whether the point `p` is in the box (mins, maxs) grown by `pad` units on every side.
function C.NearBox(p, mins, maxs, pad)
	return p.x >= mins.x - pad and p.x <= maxs.x + pad and p.y >= mins.y - pad and p.y <= maxs.y + pad and p.z >= mins.z - pad and p.z <= maxs.z + pad
end

-- ---------------------------------------------------------------------------------------------------------
-- The texts
-- ---------------------------------------------------------------------------------------------------------

-- The text `field` ("title" or "description") of an objective in the language `lang` ("fr"): the translation when the data has one, the English text otherwise.
function C.Text(def, field, lang)
	local tr = def.tr

	if lang and tr then
		local texts = tr[lang]

		if texts and isstring(texts[field]) and texts[field] ~= "" then
			return texts[field]
		end
	end

	return def[field]
end

-- A text of the system itself (C.Strings), in the language or in English.
function C.String(key, lang)
	local t = lang and C.Strings[lang]

	return t and t[key] or C.Strings.en[key]
end

-- ---------------------------------------------------------------------------------------------------------
-- The chain: what is listed, what is main, what is done
-- ---------------------------------------------------------------------------------------------------------

local function byIdOf(list)
	local by = {}

	for _, d in ipairs(list) do
		by[d.id] = d
	end

	return by
end

-- The ids that are listed now, as a set: the steps that are not done and whose predecessors all are (the exit too: when it has a predecessor it waits for it,
-- when it has none it is listed from the start). Secrets are not steps and are not in it.
function C.Revealed(list, done)
	local out = {}

	for _, d in ipairs(list) do
		if not d.secret and not done[d.id] then
			local ready = d.exit and #d.after == 0

			if not ready then
				ready = true

				for _, a in ipairs(d.after) do
					if not done[a] then
						ready = false

						break
					end
				end
			end

			if ready then
				out[d.id] = true
			end
		end
	end

	return out
end

-- A copy of the set `done` with every step before a done step added: a step cannot be done while one that comes before it is not.
function C.CloseDone(list, done)
	local by = byIdOf(list)
	local out = {}

	for id in pairs(done) do
		out[id] = true
	end

	local changed = true

	while changed do
		changed = false

		for id in pairs(out) do
			local d = by[id]

			if d then
				for _, a in ipairs(d.after) do
					if not out[a] then
						out[a] = true
						changed = true
					end
				end
			end
		end
	end

	return out
end

-- The id of the main objective: the first primary step that is listed and neither done nor failed; when there is none, the exit; else nil. A secondary
-- objective and a secret are never main.
function C.PickMain(list, done, failed)
	local revealed = C.Revealed(list, done)
	local exit

	for _, d in ipairs(list) do
		if d.primary and not d.secret and revealed[d.id] and not failed[d.id] then
			if not d.exit then
				return d.id
			end

			exit = exit or d.id
		end
	end

	return exit
end

-- What is done when a map starts: what was saved (`stored.done`), what the world proves now (`proof[id] == true`: a weapon the player already has, a vehicle he
-- is already in), and every step before those. A proof that says false or nothing never undoes what was saved. Only ids of `list` come back, and never a secret.
function C.MergeProgress(list, stored, proof)
	local done = {}
	local saved = stored and stored.done or {}

	for _, d in ipairs(list) do
		if not d.secret and ((proof and proof[d.id] == true) or saved[d.id]) then
			done[d.id] = true
		end
	end

	return C.CloseDone(list, done)
end

-- How many of the map's secrets are found (`stored.secrets`, a set of ids) and how many the list has. An id the list does not have is not counted.
function C.SecretsFound(list, stored)
	local found, total = 0, 0
	local saved = stored and stored.secrets or {}

	for _, d in ipairs(list) do
		if d.secret then
			total = total + 1

			if saved[d.id] then
				found = found + 1
			end
		end
	end

	return found, total
end

-- ---------------------------------------------------------------------------------------------------------
-- The store: what is done on each map, kept between two visits and two sessions
-- ---------------------------------------------------------------------------------------------------------
-- A quickload restarts the Lua of the map, so what is done must live outside it. It is written when it changes (rarely) and read when a map starts. It is a
-- record by MAP, not by save game: a quickload to an earlier moment leaves later steps marked done (`gry_campaign_reset` starts the map over).

local Store = C.Store or {}
C.Store = Store

Store.TABLE = "gry_campaign"

local tableMade = false

local function makeTable()
	if tableMade then
		return
	end

	-- false when the query failed: tried again at the next call
	if sql.Query("CREATE TABLE IF NOT EXISTS " .. Store.TABLE .. " (map TEXT PRIMARY KEY, data TEXT)") ~= false then
		tableMade = true
	end
end

-- The default backend: the server's own sql database (sv.db). Each function takes a map name; Store.backend can be replaced (the tests do).
local function sqlBackend()
	return {
		get = function(map)
			makeTable()

			local rows = sql.Query("SELECT data FROM " .. Store.TABLE .. " WHERE map = " .. sql.SQLStr(map))

			return istable(rows) and rows[1] and rows[1].data or nil
		end,
		set = function(map, text)
			makeTable()
			sql.Query("INSERT OR REPLACE INTO " .. Store.TABLE .. " (map, data) VALUES (" .. sql.SQLStr(map) .. ", " .. sql.SQLStr(text) .. ")")
		end,
		clear = function(map)
			makeTable()
			sql.Query("DELETE FROM " .. Store.TABLE .. " WHERE map = " .. sql.SQLStr(map))
		end,
		clearAll = function()
			makeTable()
			sql.Query("DELETE FROM " .. Store.TABLE)
		end
	}
end

Store.backend = Store.backend or sqlBackend()

local function idList(set)
	local out = {}

	for id, yes in pairs(set) do
		if yes and isstring(id) then
			out[#out + 1] = id
		end
	end

	table.sort(out)

	return out
end

local function idSet(list)
	local out = {}

	if istable(list) then
		for _, id in ipairs(list) do
			if isstring(id) then
				out[id] = true
			end
		end
	end

	return out
end

-- The progress of the map: {done = set of ids, secrets = set of ids}. Empty when nothing is saved or what is saved is not readable.
function Store.Load(map)
	local progress = {done = {}, secrets = {}}
	local text = Store.backend.get(map)

	if isstring(text) then
		local data = util.JSONToTable(text)

		if istable(data) then
			progress.done = idSet(data.done)
			progress.secrets = idSet(data.secrets)
		end
	end

	return progress
end

-- Saves the progress of the map ({done = set, secrets = set}).
function Store.Save(map, progress)
	Store.backend.set(map, util.TableToJSON({done = idList(progress.done), secrets = idList(progress.secrets)}))
end

-- Forgets the progress of the map; of every map when `map` is nil.
function Store.Reset(map)
	if map == nil then
		Store.backend.clearAll()
	else
		Store.backend.clear(map)
	end
end
