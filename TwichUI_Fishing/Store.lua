-- TwichUI Fishing: saved data (TwichUIFishingDB, account-wide; this addon's own saved variable)
--
--   TwichUIFishingDB = {
--     schema = 2,                     -- the shape below (separate from the addon version)
--     config = { ... },               -- preferences (DEFAULTS below); account-wide, not part of TwichUI profiles yet
--     client = { saved = {...},       -- interaction-targeting settings changed while a line was out, to put back
--                camera = {...} },    -- Stage 2: the camera values Fishing Mode changed, to put back (Camera.lua)
--     capability = { autoOpen = "worked" | "blocked" },  -- what the client was seen to allow
--     chars = { ["Name - Realm"] = <character record, NewChar below> },
--   }
--
-- Gameplay records (sessions, totals, the container queue, the gear snapshot) are kept apart from configuration, store
-- item ids rather than item descriptions, and never hold prices: valuation is a later, separate layer.
-- Rules (docs/persistence.md): defaults fill only missing values and are never shared tables; a damaged field is
-- repaired on its own, never by resetting the rest; data from a newer schema is held untouched (nothing is written for
-- the rest of the session); migrations are ordered and repeatable.

local R = TwichUI
local F = R.Fishing
local S = {}
F.Store = S

S.DEFAULTS = {
    enabled = true,
    economy = { enabled = true, method = "market", vendor = false, perHour = true, provisional = true },
    gear = { manage = true, pole = false, outfit = false, restoreOnEnd = true, combatWeapons = true },
    lure = { auto = true, preferred = false, alternative = false, early = 0, warn = 60 },
    containers = { mode = "queue", openWithKey = true, minFree = 1 },
    session = { idleMinutes = 10, keep = F.LIMITS.sessions },
    action = { guard = 1.0, reel = "INTERACTTARGET" },
    interact = { adjust = false },
    -- Stage 2: Fishing Mode (Present.lua and the heads-up files; docs/fishing.md, "Fishing Mode")
    present = { mode = "immersive", auto = true, vibrate = false, motion = true, prompts = true, brand = true },
    camera = { enabled = true, zoom = 7, offset = 0 },
    fade = { enabled = true, bars = true, units = true, minimap = true, panels = false, meters = true, twichui = true, notices = true, alpha = 0, extra = false,
        ellesmere = true },
    castbar = { enabled = true, scale = 1, x = 0, y = 150 },
    list = { enabled = true, scale = 1, x = -36, y = 100, sort = "count", rows = 6, value = "show" },
    toast = { enabled = true, scale = 1, x = 70, y = -60, hold = 3.5 },
    -- Stage 3A: the Fishing Journal (Journal.lua, JournalUI.lua)
    journal = { summary = true, scale = 1, x = 0, y = 0 },
}

-- What each preference may hold: a checker per leaf. false means "none chosen" for the optional ids and names.
local function Bool(v) return type(v) == "boolean" end
local function Id(v) return v == false or (F.Count(v) ~= nil and v > 0) end
local function Name(v) return v == false or (type(v) == "string" and #v > 0 and #v <= 64) end
local function Range(lo, hi) return function(v) return type(v) == "number" and v == v and v >= lo and v <= hi end end
-- A short list of frame names (false for none): another addon's frames the player chose to fade too.
local function Names(v)
    if v == false then return true end
    if type(v) ~= "table" or #v > 20 then return false end
    for k, name in pairs(v) do
        if type(k) ~= "number" or type(name) ~= "string" or not name:match("^[%w_]+$") or #name > 64 then return false end
    end
    return true
end
local function OneOf(...)
    local ok = {}
    for _, v in ipairs({ ... }) do ok[v] = true end
    return function(v) return ok[v] == true end
end

S.CHECK = {
    enabled = Bool,
    economy = { enabled = Bool, method = OneOf("market", "recent", "historical", "min"), vendor = Bool, perHour = Bool, provisional = Bool },
    gear = { manage = Bool, pole = Id, outfit = Name, restoreOnEnd = Bool, combatWeapons = Bool },
    lure = { auto = Bool, preferred = Id, alternative = Bool, early = Range(0, 600), warn = Range(0, 600) },
    containers = { mode = OneOf("queue", "auto", "off"), openWithKey = Bool, minFree = Range(0, 10) },
    session = { idleMinutes = Range(1, 240), keep = Range(10, 500) },
    action = { guard = Range(0, 5), reel = OneOf("INTERACTTARGET", "INTERACTMOUSEOVER") },
    interact = { adjust = Bool },
    present = { mode = OneOf("immersive", "compact", "classic"), auto = Bool, vibrate = Bool, motion = Bool, prompts = Bool,
        brand = Bool },
    camera = { enabled = Bool, zoom = Range(1, 30), offset = Range(-2, 2) },
    fade = { enabled = Bool, bars = Bool, units = Bool, minimap = Bool, panels = Bool, meters = Bool, twichui = Bool, notices = Bool, alpha = Range(0, 0.6),
        extra = Names, ellesmere = Bool },
    castbar = { enabled = Bool, scale = Range(0.6, 1.6), x = Range(-2000, 2000), y = Range(-2000, 2000) },
    list = { enabled = Bool, scale = Range(0.6, 1.6), x = Range(-2000, 2000), y = Range(-2000, 2000),
        sort = OneOf("count", "recent", "name"), rows = Range(3, 12), value = OneOf("show", "hide") },
    toast = { enabled = Bool, scale = Range(0.6, 1.6), x = Range(-2000, 2000), y = Range(-2000, 2000), hold = Range(1, 10) },
    journal = { summary = Bool, scale = Range(0.6, 1.4), x = Range(-2000, 2000), y = Range(-2000, 2000) },
}

S.held = false        -- the saved data is from a newer schema: read only, nothing written this session
S.repairs = 0

local function Repair(code)
    S.repairs = S.repairs + 1
    F.Note("repaired", code)
end

-- Fills what is missing and replaces what is damaged, leaf by leaf, from the defaults.
local function Normalize(into, defaults, check, path)
    for k, def in pairs(defaults) do
        local v, c = into[k], check[k]
        if type(def) == "table" then
            if type(v) ~= "table" then
                if v ~= nil then Repair(path .. k) end
                into[k] = F.Copy(def)
            else
                Normalize(v, def, c, path .. k .. ".")
            end
        elseif v == nil then
            into[k] = def
        elseif not c(v) then
            Repair(path .. k)
            into[k] = def
        end
    end
end

local function NewTotals()
    return { casts = 0, catches = 0, items = 0, failed = 0, interrupted = 0, missed = 0, sessions = 0, seconds = 0, line = 0,
        first = nil, last = nil, species = {}, zones = {}, containers = {}, contents = {},
        -- schema 2: where things were caught. spz[mapID][itemID] = { q, c, f, l } (quantity, times caught, first, last) for
        -- direct catches; ctz[mapID][containerID] = { caught, opened, got = { [itemID] = q } } for containers by the zone they
        -- were CAUGHT in. mapID 0 is a catch whose zone could not be read. Catches recorded before schema 2 are in species
        -- (and zones) but not in these: the difference is history with no location, never guessed (Journal.lua).
        spz = {}, ctz = {} }
end
S.NewTotals = NewTotals

local function NewChar()
    return { nextSession = 1, nextLot = 1, session = nil, sessions = {}, totals = NewTotals(), queue = {},
        gear = { state = "none" }, learned = { enchants = {}, containers = {} }, zoneNames = {},
        locSince = F.Now() }     -- when this character began recording where fish are caught (schema 2)
end

local function IsMap(t) return type(t) == "table" end

-- A character record: each part checked on its own (docs/fishing.md lists the shape).
local function NormalizeTotals(t)
    for _, k in ipairs({ "casts", "catches", "items", "failed", "interrupted", "missed", "sessions", "seconds", "line" }) do
        if F.Count(t[k]) == nil then
            if t[k] ~= nil then Repair("totals." .. k) end
            t[k] = 0
        end
    end
    for _, k in ipairs({ "species", "zones", "containers", "contents", "spz", "ctz" }) do
        if not IsMap(t[k]) then
            if t[k] ~= nil then Repair("totals." .. k) end
            t[k] = {}
        end
    end
    -- the location records, each entry checked on its own (a damaged one is dropped, the rest kept)
    local n = 0
    for zone, zt in pairs(t.spz) do
        if F.Count(zone) == nil or not IsMap(zt) then t.spz[zone] = nil; Repair("spz.zone")
        else
            for item, e in pairs(zt) do
                if F.Count(item) == nil or not IsMap(e) or F.Count(e.q) == nil or F.Count(e.c) == nil then zt[item] = nil; Repair("spz.entry")
                else
                    if e.f ~= nil and F.Count(e.f) == nil then e.f = nil end
                    if e.l ~= nil and F.Count(e.l) == nil then e.l = nil end
                    n = n + 1
                end
            end
            if next(zt) == nil then t.spz[zone] = nil end
        end
    end
    t.spn = n       -- how many species-in-a-zone entries there are (bounded by LIMITS.zoneSpecies)
    -- what overflowed that bound: spo[itemID] = quantity caught with no zone entry (one number per species); ctl = container
    -- events with no zone entry. Damaged values are dropped, the rest kept.
    if t.spo ~= nil and not IsMap(t.spo) then t.spo = nil; Repair("spo") end
    for item, q in pairs(t.spo or {}) do if F.Count(item) == nil or F.Count(q) == nil then t.spo[item] = nil end end
    if t.ctl ~= nil and F.Count(t.ctl) == nil then t.ctl = nil; Repair("ctl") end
    -- a record already at the bound with no overflow count was filled before overflow was counted: what it dropped is unknown
    if n >= F.LIMITS.zoneSpecies and t.spo == nil then t.spx = true elseif t.spx ~= nil and t.spx ~= true then t.spx = nil end
    local cn = 0
    for zone, zt in pairs(t.ctz) do
        if F.Count(zone) == nil or not IsMap(zt) then t.ctz[zone] = nil; Repair("ctz.zone")
        else
            for item, e in pairs(zt) do
                if F.Count(item) == nil or not IsMap(e) then zt[item] = nil; Repair("ctz.entry")
                else
                    cn = cn + 1
                    for _, k in ipairs({ "caught", "opened" }) do if F.Count(e[k]) == nil then e[k] = 0 end end
                    if not IsMap(e.got) then e.got = {} end
                    for got, q in pairs(e.got) do if F.Count(got) == nil or F.Count(q) == nil then e.got[got] = nil end end
                end
            end
        end
    end
    t.ctn = cn
    if t.first ~= nil and F.Count(t.first) == nil then t.first = nil; Repair("totals.first") end
    if t.last ~= nil and F.Count(t.last) == nil then t.last = nil; Repair("totals.last") end
end
S.NormalizeTotals = NormalizeTotals

local GEAR_STATES = { none = true, fishing = true, pending = true }

local function NormalizeChar(c)
    if F.Count(c.nextSession) == nil or c.nextSession < 1 then c.nextSession = 1; Repair("nextSession") end
    if F.Count(c.nextLot) == nil or c.nextLot < 1 then c.nextLot = 1; Repair("nextLot") end
    if not IsMap(c.totals) then
        if c.totals ~= nil then Repair("totals") end
        c.totals = NewTotals()
    else
        NormalizeTotals(c.totals)
    end
    if not IsMap(c.sessions) then if c.sessions ~= nil then Repair("sessions") end c.sessions = {} end
    for i = #c.sessions, 1, -1 do
        if not IsMap(c.sessions[i]) or F.Count(c.sessions[i].id) == nil then table.remove(c.sessions, i); Repair("sessions.entry") end
    end
    if c.session ~= nil and not (IsMap(c.session) and F.Count(c.session.id) and F.Count(c.session.start)) then
        c.session = nil; Repair("session")
    end
    if c.session then NormalizeTotals(c.session) end
    if not IsMap(c.queue) then if c.queue ~= nil then Repair("queue") end c.queue = {} end
    for i = #c.queue, 1, -1 do
        local lot = c.queue[i]
        if not (IsMap(lot) and F.Count(lot.id) and F.Count(lot.item) and F.Count(lot.n) and lot.n > 0) then
            table.remove(c.queue, i); Repair("queue.lot")
        end
    end
    if not IsMap(c.gear) or not GEAR_STATES[c.gear.state] then
        -- a damaged gear record keeps its snapshot if one is there: an original-equipment snapshot is never dropped
        local snap = IsMap(c.gear) and IsMap(c.gear.snapshot) and c.gear.snapshot or nil
        c.gear = { state = snap and "pending" or "none", snapshot = snap }
        Repair("gear")
    end
    if c.gear.state ~= "none" and not IsMap(c.gear.snapshot) then c.gear.state = "none"; c.gear.snapshot = nil; Repair("gear.snapshot") end
    if not IsMap(c.learned) then c.learned = { enchants = {}, containers = {} }; Repair("learned") end
    if not IsMap(c.learned.enchants) then c.learned.enchants = {} end
    if not IsMap(c.learned.containers) then c.learned.containers = {} end
    if not IsMap(c.zoneNames) then c.zoneNames = {} end
    if c.locSince ~= nil and F.Count(c.locSince) == nil then c.locSince = nil; Repair("locSince") end
    -- queued containers: where each was caught (nil: not known, which is how older lots read)
    for _, lot in ipairs(c.queue) do
        if lot.zone ~= nil and F.Count(lot.zone) == nil then lot.zone = nil; Repair("queue.zone") end
    end
end

---------------------------------------------------------------------------
-- Migrations: MIGRATIONS[n] turns schema n - 1 into n. Each is deterministic and repeatable (running it on data already
-- in shape n changes nothing) and works on the table in place only after checking it, so a failure leaves the older
-- shape intact. Schema 1 is the first; a table with no schema (or 0) is taken as empty-or-unversioned and given shape 1.
---------------------------------------------------------------------------
S.MIGRATIONS = {
    [1] = function(db)
        if not IsMap(db.chars) then db.chars = {} end
        if not IsMap(db.config) then db.config = {} end
        if not IsMap(db.client) then db.client = {} end
        if not IsMap(db.capability) then db.capability = {} end
    end,
    -- Schema 2: where fish were caught. Nothing existing is changed or removed; each character gets the empty location
    -- records (the load-time normalising adds them to the totals and every session) and the moment recording began.
    -- What was caught before that stays exactly as it was, with no location: it is never guessed from the zones fished in.
    [2] = function(db)
        if not IsMap(db.chars) then return end
        for _, c in pairs(db.chars) do
            if IsMap(c) and c.locSince == nil then c.locSince = F.Now() end
        end
    end,
}

-- Brings the global into shape. Returns the db (nil while held).
function S.Load()
    local db = rawget(_G, "TwichUIFishingDB")
    if type(db) ~= "table" then
        db = {}
        _G.TwichUIFishingDB = db
    end
    local schema = db.schema
    if schema ~= nil and F.Count(schema) == nil then schema = 0; Repair("schema") end
    schema = schema or 0
    if schema > F.SCHEMA then
        S.held = true
        F.Note("held", "saved by a newer TwichUI Fishing (schema " .. schema .. ")")
        S.db = db
        return nil
    end
    for n = schema + 1, F.SCHEMA do
        S.MIGRATIONS[n](db)
        db.schema = n
    end
    db.schema = F.SCHEMA
    S.MIGRATIONS[1](db)   -- the containers themselves (repeatable)
    Normalize(db.config, S.DEFAULTS, S.CHECK, "config.")
    if not IsMap(db.client) then db.client = {} end
    if db.client.camera ~= nil and not IsMap(db.client.camera) then db.client.camera = nil; Repair("client.camera") end
    if not IsMap(db.capability) then db.capability = {} end
    for key, c in pairs(db.chars) do
        if type(key) ~= "string" or not IsMap(c) then db.chars[key] = nil; Repair("chars.entry")
        else NormalizeChar(c) end
    end
    S.db = db
    return db
end

-- This character's record (made the first time it is wanted). nil while held.
function S.Char()
    if S.held or not S.db then return nil end
    local key = F.CharKey()
    local c = S.db.chars[key]
    if not c then
        c = NewChar()
        S.db.chars[key] = c
    end
    return c
end

---------------------------------------------------------------------------
-- Preferences: S.Get("lure.preferred"), S.Set("lure.preferred", 6532). Set checks the value and refuses what does not fit.
---------------------------------------------------------------------------
local function Walk(path)
    local a, b = path:match("^(%w+)%.(%w+)$")
    if a then return a, b end
    return path, nil
end

function S.Get(path)
    local cfg = S.db and S.db.config
    local a, b = Walk(path)
    local d = S.DEFAULTS[a]
    if b then
        local group = cfg and cfg[a]
        local v
        if type(group) == "table" then v = group[b] end
        if v == nil then
            if type(d) == "table" then return d[b] end
            return nil
        end
        return v
    end
    local v = cfg and cfg[a]
    if v == nil then return d end
    return v
end

function S.Set(path, value)
    if S.held then return false, "held" end
    if not (S.db and S.db.config) then return false, "not-ready" end
    local a, b = Walk(path)
    local check = S.CHECK[a]
    if b then check = type(check) == "table" and check[b] or nil end
    if type(check) ~= "function" then return false, "unknown" end
    if not check(value) then return false, "invalid" end
    if type(value) == "table" then value = F.Copy(value) end
    if b then S.db.config[a][b] = value else S.db.config[a] = value end
    F.Emit("CONFIG", path, value)
    return true
end

-- Runtime recovery records kept in db.client (plain values only): Stage 2 keeps the camera values it changed there, so a
-- reload, a disconnect or an error can put them back (Camera.lua). Nothing is written while the data is held.
function S.ClientRecord(key)
    local rec = S.db and not S.held and type(S.db.client) == "table" and S.db.client[key] or nil
    return type(rec) == "table" and rec or nil
end

function S.SetClientRecord(key, value)
    if S.held or not (S.db and type(S.db.client) == "table") then return false end
    if value ~= nil and type(value) ~= "table" then return false end
    S.db.client[key] = value
    return true
end

---------------------------------------------------------------------------
-- Learned facts (bounded): which weapon enchant ids were seen to come from a lure, which items from fishing loot turned
-- out to be containers.
---------------------------------------------------------------------------
local function Bounded(map, key, value)
    if map[key] ~= nil then map[key] = value return end
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    if n >= F.LIMITS.learned then return end
    map[key] = value
end

function S.LearnEnchant(enchantID, lureItem)
    local c = S.Char()
    if c and F.Count(enchantID) and enchantID > 0 then Bounded(c.learned.enchants, enchantID, F.Count(lureItem) or true) end
end

function S.LureEnchant(enchantID)
    local c = S.Char()
    return c and enchantID and c.learned.enchants[enchantID] or nil
end

function S.LearnContainer(itemID)
    local c = S.Char()
    if c and F.Count(itemID) then Bounded(c.learned.containers, itemID, true) end
end

function S.IsKnownContainer(itemID)
    if not itemID then return false end
    if F.CONTAINERS[itemID] then return true end
    local c = S.Char()
    return c ~= nil and c.learned.containers[itemID] == true
end
