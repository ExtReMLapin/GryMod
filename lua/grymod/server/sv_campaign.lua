-- The campaign objectives, SERVER side: the Half-Life 2 / Episode One / Episode Two maps feed GryMod's objectives (docs/api.md, "Campaign objectives") with no
-- code from the player's side. The data of a map lives in lua/grymod/campaign/<game>/<map>.lua and is read ONLY for the map being played; a third party adds or
-- replaces objectives with GryMod.API.RegisterCampaignMap and GryMod.API.OverrideCampaignObjective. The pure part (the check of a list, the matching, the chain,
-- the store) is in sv_campaign_core.lua.
--
-- How it runs. When a map starts the runtime reads what is saved for it (C.Store), asks the world what it already proves (a weapon the player has, a vehicle he
-- is in), registers the steps that are listed (the first of each chain, and the exit) through GryMod.API.RegisterObjective, and listens for what finishes them:
--   * ONE hook on GM:AcceptInput (the map's own scripts sending an input to a named entity), looked up by input name first, installed only while an `input`
--     completion is waiting;
--   * WeaponEquip, PlayerCanPickupItem, PlayerEnteredVehicle, PlayerUse, OnNPCKilled, EntityRemoved and ShutDown, each only while a completion of its kind waits.
-- A step that is done is told (GryMod_ObjectiveChanged), saved, and the next step of its chain is listed. When nothing waits for a kind, its hook is removed.
-- There is no Think and no timer that watches: only events (and one short timer that takes a finished objective off the list a few seconds after it was done).
-- Everything the hooks run is protected: an error in it is shown once and breaks nothing.

GryMod = GryMod or {}

local API = GryMod.API
local C = GryMod.Campaign

if not API or not C or not API.RegisterObjective or not API.AddFeature then
	return -- sh_api.lua, sv_objectives.lua and sv_campaign_core.lua are included first (grymod_shared.lua)
end

local S = GryMod.CampaignServer or {}
GryMod.CampaignServer = S

local HOOK_ID = "GryMod campaign"
local GAMES = {"hl2", "ep1", "ep2"}
local FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

S.LINGER = 8 -- seconds a finished objective stays in the list (done) before it is taken off
S.EXIT_PAD = 72 -- units around the exit trigger in which a player counts as leaving through it

local switch = CreateConVar("gry_campaign_objectives", "1", FLAGS,
	"1: the campaign maps (Half-Life 2 and its episodes) give GryMod objectives, and the data of the map being played is read; 0: nothing runs", 0, 1)
local secretsSwitch = CreateConVar("gry_campaign_secrets", "0", FLAGS,
	"1: a map's hidden items are counted in one objective, \"Secrets 3/7\"; 0: they are not mentioned", 0, 1)

-- What a third party gave, by map: {ops = {...}}. An op is {kind = "map", list, fails, replace} or {kind = "override", id, def (clean, or false to remove)}.
-- The shipped data of a map is read the first time it is needed (S.shipped[map], false when the map has none). Both live through a reload of this file.
local sources = S.sources or {}
local shipped = S.shipped or {}
S.sources, S.shipped = sources, shipped

local cleaning = false -- the map is being cleaned up: the entities that go are not an event
local shuttingDown = false -- the level is ending: neither

local function enabled()
	return switch:GetBool()
end

local function secretsOn()
	return secretsSwitch:GetBool()
end

S.Enabled = enabled

-- A report on the console, at most a few times for one text.
local told = S.told or {}
S.told = told

local function say(text)
	local n = (told[text] or 0) + 1

	told[text] = n

	if n <= 3 then
		MsgN("GryMod campaign: " .. text)
	end
end

-- The language of the texts: the server's own (every player gets the same objective text).
function S.Language()
	local cv = GetConVar("gmod_language")
	local lang = cv and cv:GetString() or "en"

	return lang ~= "" and lang or "en"
end

-- ---------------------------------------------------------------------------------------------------------
-- The data of a map
-- ---------------------------------------------------------------------------------------------------------

local function validMapName(map)
	return isstring(map) and #map >= 1 and #map <= C.Limits.name and string.find(map, "^[%w_%-]+$") ~= nil
end

-- The fail events: {entity = "killed_critical_npc", input = "ShowMessage"}: the map's own "game over" message. Returns the clean list, or false and why.
local function checkFailEvents(list)
	if list == nil then
		return {}
	end

	if not istable(list) then
		return false, "invalid fail_events: an array of {entity = ..., input = ...}"
	end

	local out = {}

	for i, f in ipairs(list) do
		local clean, why = C.CheckCompletion({kind = "input", entity = istable(f) and f.entity, input = istable(f) and f.input}, C.FailKinds)

		if not clean then
			return false, "fail_events #" .. i .. ": " .. why
		end

		out[i] = clean
	end

	return out
end

-- Reads the shipped file of the map: the table it returns {objectives = {...}, fail_events = {...}}, or nil. S.ReadShippedFile is a function of its own so that
-- the tests can replace the disk.
function S.ReadShippedFile(map)
	for _, game in ipairs(GAMES) do
		local path = "grymod/campaign/" .. game .. "/" .. map .. ".lua"

		if file.Exists(path, "LUA") then
			local fn = CompileFile(path)

			if not isfunction(fn) then
				say("the data of " .. map .. " does not compile (" .. path .. ")")

				return nil
			end

			local ok, data = pcall(fn)

			if not ok or not istable(data) then
				say("the data of " .. map .. " failed: " .. tostring(data))

				return nil
			end

			return data
		end
	end

	return nil
end

-- The shipped list of the map, checked: {list, fails}, or false when the map has none (or its data is wrong: that is reported). Read once per map.
local function shippedFor(map)
	local cached = shipped[map]

	if cached ~= nil then
		return cached
	end

	local result = false
	local data = S.ReadShippedFile(map)

	if data then
		local list, why = C.CheckList(data.objectives)
		local fails, whyFails = checkFailEvents(data.fail_events)

		if not list then
			say("the data of " .. map .. " is refused: " .. why)
		elseif not fails then
			say("the data of " .. map .. " is refused: " .. whyFails)
		else
			result = {list = list, fails = fails}
		end
	end

	shipped[map] = result

	return result
end

-- The list the map runs with: the shipped one, then what the third parties did, in the order they did it. Returns the resolved list and the fail events.
local function effective(map)
	local src = sources[map]
	local ops = src and src.ops or {}
	local list, fails = {}, {}
	local needShipped = true

	for _, op in ipairs(ops) do
		if op.kind == "map" and op.replace then
			needShipped = false
		end
	end

	if needShipped then
		local base = shippedFor(map)

		if base then
			list, fails = base.list, base.fails
		end
	end

	for _, op in ipairs(ops) do
		if op.kind == "map" then
			if op.replace then
				list, fails = op.list, op.fails
			else
				list = C.MergeLists(list, op.list)

				local joined = {}

				for _, f in ipairs(fails) do
					joined[#joined + 1] = f
				end

				for _, f in ipairs(op.fails) do
					joined[#joined + 1] = f
				end

				fails = joined
			end
		elseif op.def == false then
			list = C.RemoveId(list, op.id)
		else
			list = C.MergeLists(list, {op.def})
		end
	end

	local resolved, problems = C.Resolve(list)

	for _, p in ipairs(problems) do
		say(map .. ": " .. p)
	end

	return resolved, fails
end

S.Effective = effective

-- ---------------------------------------------------------------------------------------------------------
-- The state of the map being played
-- ---------------------------------------------------------------------------------------------------------

-- S.run: {map, list, regular, secrets, byId, fails, progress, done, failed, registered, index, lang}. nil when nothing runs.

-- What the world proves done: a weapon or an item a player has, a vehicle a player is in. Only `true` is ever answered (false would say "not done", and a player
-- may have lost the weapon for a good reason).
local function worldProof(list)
	local proof = {}
	local players = player.GetAll()

	if not players[1] then
		return proof
	end

	for _, d in ipairs(list) do
		if not d.secret then
			local c = d.complete

			while c do
				if c.kind == "pickup" then
					for _, ply in ipairs(players) do
						if c.class == "item_suit" then
							if ply:IsSuitEquipped() then
								proof[d.id] = true
							end
						elseif string.sub(c.class, 1, 5) ~= "item_" and ply:HasWeapon(c.class) then
							proof[d.id] = true
						end
					end
				elseif c.kind == "enter_vehicle" then
					for _, ply in ipairs(players) do
						local veh = ply:GetVehicle()

						if IsValid(veh) and C.Matches(c, veh) then
							proof[d.id] = true
						end
					end
				end

				c = c.also
			end
		end
	end

	return proof
end

-- The position an objective is registered with: the named entity's place when it exists, else the position of the data.
local function positionOf(d)
	if d.place then
		local found = ents.FindByName(d.place)
		local e = found and found[1]

		if e and IsValid(e) then
			return e:GetPos()
		end
	end

	return d.pos
end

local function register(R, d)
	local pos = positionOf(d)

	if not pos then
		say(R.map .. ": no place for \"" .. d.id .. "\" (the entity \"" .. tostring(d.place) .. "\" is not there and the data has no pos)")

		return
	end

	local ok, why = API.RegisterObjective(d.id, {
		title = C.Text(d, "title", R.lang),
		description = C.Text(d, "description", R.lang),
		primary = d.primary,
		pos = pos,
		via = d.via
	})

	if ok then
		R.registered[d.id] = true
	else
		say(R.map .. ": \"" .. d.id .. "\" is refused: " .. tostring(why))
	end
end

-- The main objective: ours when nobody else made one main (or ours is the main one).
local function refreshMain(R)
	local id = C.PickMain(R.regular, R.done, R.failed)

	if id and not R.registered[id] then
		id = nil
	end

	local current

	for _, o in ipairs(API.GetObjectives()) do
		if o.main then
			current = o.id
		end
	end

	if current == nil or R.registered[current] then
		if id ~= current then
			API.SetMainObjective(id)
		end
	end
end

-- The counter of the secrets: one objective "Secrets 3/7" while the setting is on and the map has secrets. Not shown on the radar or the screen (it would point
-- at nothing), done when all are found.
local function syncSecrets(R)
	local found, total = C.SecretsFound(R.list, R.progress)
	local id = C.SecretsId

	if not secretsOn() or total == 0 then
		if R.registered[id] then
			API.RemoveObjective(id)
			R.registered[id] = nil
		end

		return
	end

	local complete = found >= total
	local ok = API.RegisterObjective(id, {
		title = string.format(C.String("secrets_title", R.lang), found, total),
		description = C.String("secrets_description", R.lang),
		primary = false,
		pos = Vector(0, 0, 0),
		radar = false,
		marker = false,
		state = complete and "done" or "active"
	})

	if ok then
		R.registered[id] = true

		if complete then
			S.Linger(R, id, true)
		end
	end
end

-- Takes a finished objective off the list a few seconds later.
function S.Linger(R, id, isCounter)
	timer.Simple(S.LINGER, function()
		if S.run == R and R.registered[id] and (isCounter or R.done[id]) then
			API.RemoveObjective(id)
			R.registered[id] = nil
		end
	end)
end

-- ---------------------------------------------------------------------------------------------------------
-- What waits for what: the index and the hooks
-- ---------------------------------------------------------------------------------------------------------

local BUCKETS = {"pickup", "item", "vehicle", "use", "killed", "removed", "changelevel"}

local function newIndex()
	local index = {input = {}}

	for _, name in ipairs(BUCKETS) do
		index[name] = {}
	end

	return index
end

local function bucketOf(index, c)
	local kind = c.kind

	if kind == "input" then
		local key = string.lower(c.input)
		local b = index.input[key]

		if not b then
			b = {}
			index.input[key] = b
		end

		return b
	elseif kind == "pickup" then
		return string.sub(c.class, 1, 5) == "item_" and index.item or index.pickup
	elseif kind == "enter_vehicle" then
		return index.vehicle
	end

	return index[kind]
end

local function addEntry(index, c, role, d)
	while c do
		local b = bucketOf(index, c)

		b[#b + 1] = {c = c, role = role, d = d}
		c = c.also
	end
end

-- Whether the step is listed and neither done nor failed: the only ones that are waited for.
local function pending(R, d)
	return R.registered[d.id] and not R.done[d.id] and not R.failed[d.id]
end

local function buildIndex(R)
	local index = newIndex()
	local anyPrimary = false

	for _, d in ipairs(R.regular) do
		if pending(R, d) then
			addEntry(index, d.complete, "done", d)

			if d.fail then
				addEntry(index, d.fail, "fail", d)
			end

			anyPrimary = anyPrimary or d.primary
		end
	end

	-- the map's own "game over": it fails every primary step that is waiting
	if anyPrimary then
		for _, f in ipairs(R.fails) do
			addEntry(index, f, "failall", nil)
		end
	end

	if secretsOn() then
		for _, d in ipairs(R.secrets) do
			if not R.progress.secrets[d.id] then
				addEntry(index, d.complete, "secret", d)
			end
		end
	end

	R.index = index
end

local handlers = S.handlers or {}
S.handlers = handlers

local function removeHooks()
	for event in pairs(handlers) do
		hook.Remove(event, HOOK_ID)
		handlers[event] = nil
	end
end

local HOOK_OF = {pickup = "WeaponEquip", item = "PlayerCanPickupItem", vehicle = "PlayerEnteredVehicle", use = "PlayerUse", killed = "OnNPCKilled", removed = "EntityRemoved", changelevel = "ShutDown", input = "AcceptInput"}

-- ---------------------------------------------------------------------------------------------------------
-- What happens when a step is done, failed, or a secret is found
-- ---------------------------------------------------------------------------------------------------------

local ensureHooks

-- The steps that are listed now and were not: the next ones of the chains.
local function revealNext(R)
	local revealed = C.Revealed(R.regular, R.done)

	for _, d in ipairs(R.regular) do
		if revealed[d.id] and not R.registered[d.id] and not R.failed[d.id] then
			register(R, d)
		end
	end
end

local function complete(R, d)
	if R.done[d.id] or R.failed[d.id] or not R.registered[d.id] then
		return
	end

	R.done[d.id] = true
	R.progress.done[d.id] = true
	C.Store.Save(R.map, R.progress)
	API.SetObjectiveState(d.id, "done")
	S.Linger(R, d.id)
	revealNext(R)
	refreshMain(R)
	ensureHooks(R)
end

local function failStep(R, d)
	if R.done[d.id] or R.failed[d.id] or not R.registered[d.id] then
		return
	end

	R.failed[d.id] = true -- a failure is not saved: the map goes back to the last save, and the step is waiting again there
	API.SetObjectiveState(d.id, "failed")
	refreshMain(R)
	ensureHooks(R)
end

local function foundSecret(R, d)
	if R.progress.secrets[d.id] then
		return
	end

	R.progress.secrets[d.id] = true
	C.Store.Save(R.map, R.progress)
	syncSecrets(R)
	ensureHooks(R)
end

local function apply(R, e)
	if e.role == "done" then
		complete(R, e.d)
	elseif e.role == "fail" then
		failStep(R, e.d)
	elseif e.role == "secret" then
		foundSecret(R, e.d)
	else -- failall
		for _, d in ipairs(R.regular) do
			if d.primary and pending(R, d) then
				failStep(R, d)
			end
		end
	end
end

-- The entries of `bucket` that `ent` matches are applied (the matches are collected first: applying one changes the index).
local function dispatch(R, bucket, ent)
	local hits

	for i = 1, #bucket do
		local e = bucket[i]

		if C.Matches(e.c, ent) then
			hits = hits or {}
			hits[#hits + 1] = e
		end
	end

	if hits then
		for _, e in ipairs(hits) do
			apply(R, e)
		end
	end
end

local function guarded(fn, ...)
	local ok, err = pcall(fn, ...)

	if not ok then
		say("an error in a hook: " .. tostring(err))
	end
end

-- Runs `fn` for the run that exists now.
local function now(fn, bucketName, ent)
	local R = S.run

	if R then
		fn(R, R.index[bucketName], ent)
	end
end

local lowerOf = S.lowerOf or {} -- the lower case of the input names the engine sent (they are few: this is not a leak)
S.lowerOf = lowerOf

local function onAcceptInput(ent, input)
	local R = S.run

	if not R then
		return
	end

	local bucket = R.index.input[input]

	if not bucket then
		local low = lowerOf[input]

		if not low then
			low = string.lower(input)
			lowerOf[input] = low
		end

		bucket = R.index.input[low]

		if not bucket then
			return
		end
	end

	guarded(dispatch, R, bucket, ent)
end

local function onWeaponEquip(weapon, owner)
	if IsValid(owner) and owner:IsPlayer() then
		guarded(now, dispatch, "pickup", weapon)
	end
end

local function onPickupItem(ply, item)
	guarded(now, dispatch, "item", item)
end

local function onEnteredVehicle(ply, veh)
	guarded(now, dispatch, "vehicle", veh)
end

local function onUse(ply, ent)
	guarded(now, dispatch, "use", ent)
end

local function onNPCKilled(npc)
	guarded(now, dispatch, "killed", npc)
end

local function onEntityRemoved(ent)
	if cleaning or shuttingDown then
		return
	end

	guarded(now, dispatch, "removed", ent)
end

-- The level is ending: the exits whose trigger a player stands in are done. (A touch of trigger_changelevel sends no input, so this is where it can be seen.)
local function exitReached(c)
	local triggers = ents.FindByClass("trigger_changelevel")
	local named, matching = {}, {}

	for _, t in ipairs(triggers) do
		local kv = t:GetKeyValues()
		local map = kv and kv.map

		if isstring(map) and string.lower(map) == string.lower(c.target) then
			matching[#matching + 1] = t
		end

		named[#named + 1] = t
	end

	-- the keyvalue of the trigger may not be readable: then any exit trigger counts
	local use = matching[1] and matching or named

	for _, t in ipairs(use) do
		if not c.entity or C.NameMatches(t:GetName(), c.entity) then
			local mins, maxs = t:WorldSpaceAABB()

			for _, ply in ipairs(player.GetAll()) do
				if IsValid(ply) and ply:Alive() and C.NearBox(ply:GetPos(), mins, maxs, S.EXIT_PAD) then
					return true
				end
			end
		end
	end

	return false
end

local function onShutDown()
	shuttingDown = true

	local R = S.run

	if not R then
		return
	end

	local bucket = R.index.changelevel
	local hits = {}

	for i = 1, #bucket do
		hits[i] = bucket[i]
	end

	for _, e in ipairs(hits) do
		local ok, reached = pcall(exitReached, e.c)

		if ok and reached then
			guarded(apply, R, e)
		end
	end
end

local FUNCTION_OF = {
	input = onAcceptInput, pickup = onWeaponEquip, item = onPickupItem, vehicle = onEnteredVehicle,
	use = onUse, killed = onNPCKilled, removed = onEntityRemoved, changelevel = onShutDown
}

-- The hooks the index needs, and no other.
function ensureHooks(R)
	buildIndex(R)

	for kind, event in pairs(HOOK_OF) do
		local need

		if kind == "input" then
			need = next(R.index.input) ~= nil
		elseif kind == "changelevel" then
			-- also while a `removed` completion waits: the level ending removes every entity, and ShutDown is what tells it apart from a real removal
			need = R.index.changelevel[1] ~= nil or R.index.removed[1] ~= nil
		else
			need = R.index[kind][1] ~= nil
		end

		if need and not handlers[event] then
			handlers[event] = true
			hook.Add(event, HOOK_ID, FUNCTION_OF[kind])
		elseif not need and handlers[event] then
			handlers[event] = nil
			hook.Remove(event, HOOK_ID)
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------
-- Starting and stopping
-- ---------------------------------------------------------------------------------------------------------

-- Takes the objectives of the runtime off and its hooks away. What is saved stays.
function S.Stop()
	local R = S.run

	S.run = nil
	removeHooks()

	if R then
		for id in pairs(R.registered) do
			API.RemoveObjective(id)
		end
	end
end

-- Starts the map: reads what is saved and what the world proves, lists the steps, listens. `map` is the running map unless a test says another one. Returns true
-- when the map has a campaign list.
function S.Start(map)
	S.Stop()
	shuttingDown = false

	if not enabled() then
		return false
	end

	map = map or game.GetMap()

	local list, fails = effective(map)

	if #list == 0 then
		return false
	end

	local R = {
		map = map, list = list, regular = {}, secrets = {}, fails = fails, failed = {}, registered = {}, lang = S.Language(),
		progress = C.Store.Load(map)
	}

	for _, d in ipairs(list) do
		if d.secret then
			R.secrets[#R.secrets + 1] = d
		else
			R.regular[#R.regular + 1] = d
		end
	end

	R.done = C.MergeProgress(list, R.progress, worldProof(list))

	-- what the world proved is kept too: the next visit does not have to prove it again
	local changed = false

	for id in pairs(R.done) do
		if not R.progress.done[id] then
			R.progress.done[id] = true
			changed = true
		end
	end

	if changed then
		C.Store.Save(map, R.progress)
	end

	S.run = R
	revealNext(R)
	syncSecrets(R)
	refreshMain(R)
	ensureHooks(R)

	return true
end

-- The map being played got a new list (a third party called the API after the map started): start it again.
local function reloadIfCurrent(map)
	if S.initialized and map == game.GetMap() and enabled() then
		S.Start(map)
	end
end

-- Forgets what a third party did for the map, and the shipped data read for it (for the tests).
function S.Forget(map)
	sources[map] = nil
	shipped[map] = nil
end

-- ---------------------------------------------------------------------------------------------------------
-- The API for the other addons
-- ---------------------------------------------------------------------------------------------------------

-- Gives the objectives of a map. `list`: an array of objectives (docs/api.md, "Campaign objectives"). `opts`: {replace = true} to replace what GryMod ships for
-- the map (the default is to add to it, an objective of the same id replaces the shipped one), {fail_events = {{entity = "...", input = "..."}}}. Nothing is
-- kept when anything is wrong. Returns true, or false and why.
function API.RegisterCampaignMap(map, list, opts)
	if not validMapName(map) then
		return false, "invalid map: the name of a map (letters, digits, _ and -)"
	end

	if opts ~= nil and not istable(opts) then
		return false, "invalid opts: a table, {replace = true, fail_events = {...}}"
	end

	opts = opts or {}

	local clean, why = C.CheckList(list)

	if not clean then
		return false, why
	end

	local fails, whyFails = checkFailEvents(opts.fail_events)

	if not fails then
		return false, whyFails
	end

	local src = sources[map] or {ops = {}}

	sources[map] = src
	src.ops[#src.ops + 1] = {kind = "map", list = clean, fails = fails, replace = opts.replace == true}
	reloadIfCurrent(map)

	return true
end

-- Replaces ONE objective of a map by its id (or adds it), or removes it with `false`. `def` is an objective; its id is `id`. The steps that came after a removed
-- one follow what it came after. Returns true, or false and why.
function API.OverrideCampaignObjective(map, id, def)
	if not validMapName(map) then
		return false, "invalid map: the name of a map (letters, digits, _ and -)"
	end

	if not isstring(id) or #id < 1 or #id > C.Limits.id then
		return false, "invalid id: a text of 1 to " .. C.Limits.id .. " characters"
	end

	local clean = false

	if def ~= false then
		if not istable(def) then
			return false, "invalid definition: an objective (a table), or false to remove it"
		end

		local copy = {}

		for k, v in pairs(def) do
			copy[k] = v
		end

		copy.id = id

		local why

		clean, why = C.CheckObjective(copy)

		if not clean then
			return false, why
		end
	end

	local src = sources[map] or {ops = {}}

	sources[map] = src
	src.ops[#src.ops + 1] = {kind = "override", id = id, def = clean}
	reloadIfCurrent(map)

	return true
end

-- Forgets what is saved for a map (every map when `map` is nil) and starts the running map over. For a player who begins the game again, or who quickloaded
-- an earlier moment. Returns true.
function API.ResetCampaignProgress(map)
	C.Store.Reset(map)

	if S.initialized then
		S.Start(game.GetMap())
	end

	return true
end

API.AddFeature("campaign")

-- ---------------------------------------------------------------------------------------------------------
-- The command, the switches, the map's life
-- ---------------------------------------------------------------------------------------------------------

concommand.Add("gry_campaign_reset", function(ply, _, args)
	if IsValid(ply) and not ply:IsAdmin() then
		return
	end

	local all = args and args[1] == "all"

	API.ResetCampaignProgress((not all) and game.GetMap() or nil)

	local text = all and "GryMod campaign: the progress of every map is forgotten." or ("GryMod campaign: the progress of " .. game.GetMap() .. " is forgotten.")

	if IsValid(ply) then
		ply:PrintMessage(HUD_PRINTCONSOLE, text)
	else
		MsgN(text)
	end
end, nil, "Forgets what the campaign objectives remember of the running map (gry_campaign_reset all: of every map). For a new game, or after a quickload of an earlier moment.")

function S.OnSwitch(_, new)
	if (tonumber(new) or 0) ~= 0 then
		if S.initialized then
			S.Start(game.GetMap())
		end
	else
		S.Stop()
	end
end

function S.OnSecretsSwitch()
	local R = S.run

	if R then
		syncSecrets(R)
		ensureHooks(R)
	end
end

cvars.AddChangeCallback("gry_campaign_objectives", function(_, old, new)
	S.OnSwitch(old, new)
end, "GryMod_Campaign")

cvars.AddChangeCallback("gry_campaign_secrets", function()
	S.OnSecretsSwitch()
end, "GryMod_Campaign")

-- The map is ready: its objectives start. (A hook of its own: it runs once, at the start of the map.)
hook.Add("InitPostEntity", HOOK_ID, function()
	S.initialized = true
	shuttingDown = false
	S.Start(game.GetMap())
end)

hook.Add("PreCleanupMap", HOOK_ID, function()
	cleaning = true
end)

-- The cleanup took every objective away (sv_objectives.lua clears them): the map starts over, once every hook of this event has run.
hook.Add("PostCleanupMap", HOOK_ID, function()
	cleaning = false

	if S.initialized and enabled() then
		timer.Simple(0, function()
			S.Start(game.GetMap())
		end)
	end
end)

-- This file was loaded again while the map runs (a development reload): start now.
if S.loadedBefore then
	S.initialized = true
	S.Start(game.GetMap())
end

S.loadedBefore = true
