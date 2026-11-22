-- TwichUI Fishing: the Journal's data (Stage 3A). What the Journal pages show, worked out from the read-only interface
-- (R.Fishing.API) and nothing else: no saved variable is read or written here, no frame is made, nothing is priced.
--
-- Every answer is a plain table the pages draw; a page never works anything out itself, so Stage 3B can add a value to a
-- row (the row tables carry an `extra` list the pages draw after their own columns) without rebuilding a layout.
--
-- What the records can and cannot say (docs/fishing.md, "The Journal: what the records cannot tell"):
--   * Lifetime totals, species (quantity, times caught, first and last catch), zones (casts, catches, items, time on the
--     line) and containers are kept for good. Per-session records are kept for the newest `limit` sessions only (config
--     session.keep, 10..500); older sessions exist only inside the totals, and the Journal says so.
--   * A zone is the player's map at each cast and catch, so zone totals are exact; a session's own zone is where it began.
--   * Which species were caught in which zone is NOT recorded. For the sessions still kept, a species is listed with the
--     zones those sessions began in, and labelled as coming from recent history only.
--   * There is no catalogue of fish to compare with, so no "N of M discovered" is possible; only what has been caught is shown.
--   * Catch rate is catches / casts: a catch is a fishing loot window, a cast is a line that was cast.
--   * Time fishing is the sessions' lengths (the one in progress included); time on the line is the seconds a line was out.
--
-- Answers are cached until the records change (the Fishing events that change them bump `serial`), so opening a page twice
-- costs one pass; the pages draw a fixed number of rows however long a list is.
--
--   J.Available()          true when records can be read (false while the saved data is held, or before it loads)
--   J.Overview()           totals, rate, favourites, recent sessions, the session in progress, retention
--   J.Sessions()           { rows, retention }: rows newest first (the session in progress first), see Row
--   J.Session(id)          one session's detail: species, zones, treasures, counts (nil when it is no longer kept)
--   J.Collection()         { species = { {id, q, c, first, last, zones} ... }, total, retention }
--   J.Sort(list, mode, namer)  "count" | "recent" | "first" | "name" (namer(id) -> text) in place; returns list
--   J.Locations()          { rows, total }
--   J.Treasures()          { rows, totals }
--   J.Summary(id)          the session-completion summary for a finished session (J.Session plus the headline figures)
--   J.Retention()          { kept, limit, older, held, available }
--   J.Rate(catches, casts) percent or nil
--   J.serial               bumped when records change

local R = TwichUI
local F = R.Fishing
local J = {}
F.Journal = J

J.serial = 0
J.TOP = 3            -- favourites shown on the Overview
J.RECENT = 3         -- recent sessions on the Overview
J.ZONES_PER_SPECIES = 4

for _, e in ipairs({ "ITEM", "CONTAINER", "QUEUE", "CATCH", "CAST", "CAST_FAILED", "SESSION_START", "SESSION_END" }) do
    F.Subscribe(e, function() J.serial = J.serial + 1 end)
end

local cache = {}
local function Cached(key, build)
    local c = cache[key]
    if c and c.serial == J.serial then return c.value end
    local v = build()
    cache[key] = { serial = J.serial, value = v }
    return v
end

local API = function() return F.API end

function J.Available()
    local t = API().Totals()
    return t ~= nil
end

function J.Rate(catches, casts)
    if type(casts) ~= "number" or casts <= 0 or type(catches) ~= "number" then return nil end
    return math.min(100, catches / casts * 100)
end

function J.ZoneLabel(mapID)
    if type(mapID) ~= "number" or mapID <= 0 then return "Unknown zone" end
    return API().ZoneName(mapID) or "Unknown zone"
end

function J.Retention()
    local r = API().Retention()
    local t = API().Totals()
    local cur = API().Session()
    -- sessions begun minus those still kept (and the one in progress): their per-session records are gone, their totals remain
    local older = 0
    if t and r.available then older = math.max(0, (t.sessions or 0) - r.kept - (cur and 1 or 0)) end
    return { kept = r.kept, limit = r.limit, older = older, held = r.held, available = r.available }
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function CountSpecies(species)
    local n = 0
    for _ in pairs(species or {}) do n = n + 1 end
    return n
end

-- One session as a row. `extra` is empty here: Stage 3B adds { label, text } pairs.
local function Row(s, current)
    local seconds = current and (s.elapsed or 0) or (s.seconds or 0)
    return {
        id = s.id, current = current or false, start = s.start, stop = s.stop, last = s.last, seconds = seconds,
        zone = s.zone or 0, zoneName = J.ZoneLabel(s.zone), casts = s.casts or 0, catches = s.catches or 0, items = s.items or 0,
        rate = J.Rate(s.catches, s.casts), kinds = CountSpecies(s.species), ended = s.ended,
        failed = s.failed or 0, interrupted = s.interrupted or 0, missed = s.missed or 0, extra = {},
    }
end

local function SessionRows()
    return Cached("sessions", function()
        local rows = {}
        for _, s in ipairs(API().Sessions(nil) or {}) do rows[#rows + 1] = Row(s, false) end
        return rows
    end)
end

-- The rows are cached; the session in progress is made fresh (its elapsed time moves).
function J.Sessions()
    local rows = {}
    local cur = API().Session()
    if cur then rows[1] = Row(cur, true) end
    for _, r in ipairs(SessionRows()) do rows[#rows + 1] = r end
    return { rows = rows, retention = J.Retention() }
end

local function SpeciesList(map)
    local list = {}
    for id, e in pairs(map or {}) do
        list[#list + 1] = { id = id, q = e.q or 0, c = e.c or 0, first = e.f, last = e.l, extra = {} }
    end
    table.sort(list, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.id < b.id end)
    return list
end

function J.Sort(list, mode, namer)
    local function Name(e) return namer and namer(e.id) or tostring(e.id) end
    local cmp
    if mode == "recent" then cmp = function(a, b) if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end return a.id < b.id end
    elseif mode == "first" then cmp = function(a, b) if (a.first or 0) ~= (b.first or 0) then return (a.first or math.huge) < (b.first or math.huge) end return a.id < b.id end
    elseif mode == "name" then cmp = function(a, b) local x, y = Name(a):lower(), Name(b):lower(); if x ~= y then return x < y end return a.id < b.id end
    else cmp = function(a, b) if a.q ~= b.q then return a.q > b.q end return a.id < b.id end end
    table.sort(list, cmp)
    return list
end

local function ContainerSet()
    -- items that are containers, so the Collections page lists only fish and other direct catches
    local t = API().Treasures("lifetime")
    local set = {}
    for id in pairs(t and t.containers or {}) do set[id] = true end
    return set
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
function J.Overview()
    local t = API().Totals()
    if not t then return { available = false, retention = J.Retention(), favorites = {}, recent = {}, lifetime = {} } end
    local cur = API().Session()
    local seconds = (t.seconds or 0) + (cur and (cur.elapsed or 0) or 0)
    local species = J.Collection().species
    local favorites = {}
    for i = 1, math.min(J.TOP, #species) do favorites[i] = species[i] end
    local recent = {}
    for _, r in ipairs(SessionRows()) do
        if #recent >= J.RECENT then break end
        recent[#recent + 1] = r
    end
    return {
        available = true,
        lifetime = { casts = t.casts, catches = t.catches, items = t.items, seconds = seconds, line = t.line, sessions = t.sessions,
            failed = t.failed, interrupted = t.interrupted, missed = t.missed, first = t.first, last = t.last,
            kinds = #species },
        rate = J.Rate(t.catches, t.casts),
        favorites = favorites, recent = recent,
        current = cur and Row(cur, true) or nil,
        retention = J.Retention(),
        extra = {},     -- Stage 3B: { label, text, glyph } cells the stat strip draws after its own
    }
end

---------------------------------------------------------------------------
-- Session detail and the completion summary
---------------------------------------------------------------------------
local function ZoneRows(map)
    local out = {}
    for id, z in pairs(map or {}) do
        out[#out + 1] = { id = id, name = J.ZoneLabel(id), casts = z.casts or 0, catches = z.catches or 0, items = z.items or 0,
            line = z.line or 0, rate = J.Rate(z.catches, z.casts), extra = {} }
    end
    table.sort(out, function(a, b) if a.catches ~= b.catches then return a.catches > b.catches end return a.id < b.id end)
    return out
end

local function TreasureRows(rec, queued)
    local out = {}
    for id, e in pairs(rec or {}) do
        out[#out + 1] = { id = id, caught = e.caught or 0, opened = e.opened or 0, failed = e.failed or 0,
            unopened = e.unopened or (queued and queued[id]) or 0, got = SpeciesList({}), extra = {} }
        local got = {}
        for item, q in pairs(e.got or {}) do got[#got + 1] = { id = item, q = q } end
        table.sort(got, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.id < b.id end)
        out[#out].got = got
    end
    table.sort(out, function(a, b) if a.caught ~= b.caught then return a.caught > b.caught end return a.id < b.id end)
    return out
end

function J.Session(id)
    local rec = API().SessionByID(id)
    if not rec then return nil end
    local cur = API().Session()
    local isCurrent = cur ~= nil and cur.id == id
    local row = Row(rec, isCurrent)
    local tr = API().Treasures(id)
    local detail = {
        row = row, species = SpeciesList(rec.species), zones = ZoneRows(rec.zones),
        treasures = tr and TreasureRows(tr.containers) or {}, contents = tr and tr.contents or {},
        line = rec.line or 0, reason = rec.reason, ended = rec.ended, first = rec.first, last = rec.last, extra = {},
    }
    return detail
end

-- The session-completion summary: the finished session's detail and the figures a card leads with.
function J.Summary(id)
    local d = J.Session(id)
    if not d then return nil end
    d.headline = { zone = d.row.zoneName, seconds = d.row.seconds, catches = d.row.catches, items = d.row.items, casts = d.row.casts,
        rate = d.row.rate, kinds = #d.species }
    local opened, contents = 0, 0
    for _, t in ipairs(d.treasures) do opened = opened + t.opened end
    for _, q in pairs(d.contents) do contents = contents + q end
    d.headline.treasuresOpened, d.headline.treasureItems = opened, contents
    return d
end

---------------------------------------------------------------------------
-- Collections (species caught directly; containers are on the Treasures page)
---------------------------------------------------------------------------
function J.Collection()
    return Cached("collection", function()
        local t = API().Totals()
        local out = { species = {}, retention = J.Retention(), total = 0 }
        if not t then return out end
        local containers = ContainerSet()
        local list = {}
        for _, e in ipairs(SpeciesList(t.species)) do
            if not containers[e.id] then list[#list + 1] = e end
        end
        -- zones from the sessions still kept (labelled as recent history by the page)
        local seen = {}
        for _, s in ipairs(API().Sessions(nil) or {}) do
            local name = s.zone and s.zone > 0 and J.ZoneLabel(s.zone) or nil
            if name then
                for id in pairs(s.species or {}) do
                    local set = seen[id]
                    if not set then set = { order = {}, has = {} }; seen[id] = set end
                    if not set.has[name] then set.has[name] = true; set.order[#set.order + 1] = name end
                end
            end
        end
        for _, e in ipairs(list) do
            e.zones = {}
            local set = seen[e.id]
            if set then for i = 1, math.min(J.ZONES_PER_SPECIES, #set.order) do e.zones[i] = set.order[i] end end
            e.moreZones = set and math.max(0, #set.order - J.ZONES_PER_SPECIES) or 0
        end
        out.species, out.total = list, #list
        return out
    end)
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
function J.Locations()
    return Cached("locations", function()
        local t = API().Totals()
        local out = { rows = {}, total = 0, retention = J.Retention() }
        if not t then return out end
        out.rows = ZoneRows(t.zones)
        -- sessions that began there, among those still kept
        local began = {}
        for _, s in ipairs(API().Sessions(nil) or {}) do began[s.zone or 0] = (began[s.zone or 0] or 0) + 1 end
        for _, r in ipairs(out.rows) do r.sessions = began[r.id] or 0 end
        out.total = #out.rows
        return out
    end)
end

---------------------------------------------------------------------------
-- Treasures
---------------------------------------------------------------------------
function J.Treasures()
    return Cached("treasures", function()
        local tr = API().Treasures("lifetime")
        local out = { rows = {}, totals = { caught = 0, opened = 0, failed = 0, unopened = 0, items = 0 }, retention = J.Retention() }
        if not tr then return out end
        out.rows = TreasureRows(tr.containers)
        for _, r in ipairs(out.rows) do
            out.totals.caught = out.totals.caught + r.caught
            out.totals.opened = out.totals.opened + r.opened
            out.totals.failed = out.totals.failed + r.failed
            out.totals.unopened = out.totals.unopened + r.unopened
        end
        for _, q in pairs(tr.contents) do out.totals.items = out.totals.items + q end
        return out
    end)
end
