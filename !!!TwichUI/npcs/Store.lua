-- TwichUI: Vendors and trainers, the saved list
-- The NPCs you dealt with, and the ones other TwichUI users sent you, in TwichUIDB.npcs (account-wide, like map pins:
-- not part of a profile, a backup or a shared setup). One entry per NPC and place:
--   { id = creature id, n = name, m = map, x, y (0..10000 on that map), tags = { [kind] = true },
--     cls = { [class token] = true } (class trainers), prof = profession name (profession trainers),
--     t = the line under its name in the game ("Enchanting Reagents"), display text only,
--     own = true (you dealt with it yourself), seen = how many visits of yours (at most 99),
--     rep = how many reports of it reached you (at most 99), at = when it was last seen or reported (time()) }
-- Seen by you or reported by others, never both mixed up: a report never changes an entry you saw yourself (it only
-- counts as one more report), and a reported entry becomes yours, with what you saw replacing what was reported, the
-- first time you deal with that NPC there yourself.
-- The place is where you stood when the NPC's window opened (the client gives addons the player's position, not the
-- NPC's), so it is a few yards out; later visits average it. An NPC seen far from where it was before (another spawn of
-- the same creature) is a second entry, at most MAX_PER_NPC of them.
-- Everything is checked here, the same way for what you saw and what arrived: the creature id, a map the client knows
-- that is a zone or smaller, coordinates in range, kinds from npcs/Kinds.lua only, class tokens from its list, names as
-- plain text (pins/Pins.lua's CleanName). An entry that can't be read is skipped, never erased.
-- Bounded: MAX_ENTRIES in all; reports you never saw yourself go after REPORT_DAYS without a fresh report, and first
-- when room is needed. Nothing here draws, sends or registers an event.

local R = TwichUI
local NK = R.NpcKinds
local Perf = R.Perf
local NS = {}
R.NpcStore = NS

NS.VERSION = 1
NS.COORD = 10000
NS.NAME_MAX = 48
NS.PROF_MAX = 32
NS.TITLE_MAX = 48
NS.MAX_ENTRIES = 3000
NS.MAX_PER_NPC = 4
NS.NEAR = 400              -- coordinate steps (4% of the map) within which a sighting is the same spawn
NS.REPORT_DAYS = 120
local MAX_COUNT = 99
local MAX_ID = 2 ^ 31
local DAY = 86400
local ZONE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

local function Whole(n, low, high)
    return type(n) == "number" and n == n and n % 1 == 0 and n >= low and n <= high
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
-- Plain text (escape sequences, links, textures and control characters taken out), cut on a character boundary.
function NS.CleanName(text) return R.Pins.CleanName(text, NS.NAME_MAX) end
function NS.CleanProfession(text) return R.Pins.CleanName(text, NS.PROF_MAX) end
function NS.CleanTitle(text) return R.Pins.CleanName(text, NS.TITLE_MAX) end

-- A map the client knows that is a zone, a dungeon or smaller: a continent or the world is too coarse to say where an
-- NPC is. Looked up once per map per session.
local mapOk = {}
function NS.ValidMap(map)
    if not Whole(map, 1, MAX_ID) then return false end
    local known = mapOk[map]
    if known ~= nil then return known end
    local ok, info = false, nil
    if C_Map and C_Map.GetMapInfo then ok, info = pcall(C_Map.GetMapInfo, map) end
    known = ok and type(info) == "table" and type(info.mapType) == "number" and info.mapType >= ZONE or false
    mapOk[map] = known
    return known
end

function NS.ValidCoord(n) return Whole(n, 0, NS.COORD) end
function NS.ValidId(id) return Whole(id, 1, MAX_ID) end

local function ValidTags(tags)
    if type(tags) ~= "table" then return false end
    local any = false
    for k, v in pairs(tags) do
        if v ~= true or not NK.BY_ID[k] then return false end
        any = true
    end
    return any
end

local function ValidClasses(cls)
    if cls == nil then return true end
    if type(cls) ~= "table" then return false end
    for k, v in pairs(cls) do
        if v ~= true or not NK.IS_CLASS[k] then return false end
    end
    return true
end

local function Valid(e)
    return type(e) == "table" and NS.ValidId(e.id) and type(e.n) == "string" and e.n ~= "" and #e.n <= NS.NAME_MAX
        and Whole(e.m, 1, MAX_ID) and NS.ValidCoord(e.x) and NS.ValidCoord(e.y) and ValidTags(e.tags)
        and ValidClasses(e.cls) and (e.prof == nil or (type(e.prof) == "string" and #e.prof <= NS.PROF_MAX))
        and (e.t == nil or (type(e.t) == "string" and e.t ~= "" and #e.t <= NS.TITLE_MAX))
        and (e.own == nil or e.own == true) and (e.seen == nil or Whole(e.seen, 0, MAX_COUNT))
        and (e.rep == nil or Whole(e.rep, 0, MAX_COUNT)) and (e.at == nil or Whole(e.at, 0, 2 ^ 40))
end
NS.Valid = Valid

---------------------------------------------------------------------------
-- What changed, for the map and the settings. Listeners must not change the list.
---------------------------------------------------------------------------
local listeners = {}
function NS.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed()
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("vendors and trainers", err) end
    end
end

-- Told when you deal with an NPC yourself: fn(entry, status) for "new" and "updated" only. Listeners must not change it.
local seenListeners = {}
function NS.OnSeen(fn) seenListeners[#seenListeners + 1] = fn end
local function Seen(entry, status)
    for _, fn in ipairs(seenListeners) do
        local ok, err = pcall(fn, entry, status)
        if not ok and R.Fault then R.Fault("vendors and trainers", err) end
    end
end

-- Reason codes for /tui diagnostics: a fixed vocabulary, never names or places.
NS.drops = {}
function NS.Drop(code)
    NS.drops[code] = (NS.drops[code] or 0) + 1
    return nil, code
end

---------------------------------------------------------------------------
-- The saved table
---------------------------------------------------------------------------
-- create: make it if there is none (only when something is added); reading never does.
local function Store(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local db = TwichUIDB.npcs
    if type(db) ~= "table" then
        if not create then return nil end
        db = { v = NS.VERSION, list = {} }
        TwichUIDB.npcs = db
    end
    if type(db.list) ~= "table" then
        if not create then return nil end
        db.list = {}
    end
    if db.v == nil then db.v = NS.VERSION end
    return db
end

-- A store written by a newer TwichUI is read as far as it can be, but never written to.
local function Writable(db) return db and (db.v == NS.VERSION or db.v == nil) end
function NS.Newer()
    local db = Store()
    return db ~= nil and type(db.v) == "number" and db.v > NS.VERSION
end

local cache   -- { entries = { usable entries }, byNpc = { [id] = { entries } }, own, reported }
local function Index()
    if cache then return cache end
    cache = { entries = {}, byNpc = {}, own = 0, reported = 0 }
    local db = Store()
    for _, e in ipairs(db and db.list or {}) do
        if Valid(e) then
            cache.entries[#cache.entries + 1] = e
            local list = cache.byNpc[e.id]
            if not list then list = {} cache.byNpc[e.id] = list end
            list[#list + 1] = e
            if e.own then cache.own = cache.own + 1 else cache.reported = cache.reported + 1 end
        end
    end
    return cache
end
local function Invalidate() cache = nil end
NS.Invalidate = Invalidate

function NS.Entries() return Index().entries end
function NS.Counts()
    local c = Index()
    return c.own, c.reported
end

-- The entry for the same NPC near (m, x, y), or nil.
local function Near(id, m, x, y)
    local best, bestD
    for _, e in ipairs(Index().byNpc[id] or {}) do
        if e.m == m then
            local d = math.max(math.abs(e.x - x), math.abs(e.y - y))
            if d <= NS.NEAR and (not bestD or d < bestD) then best, bestD = e, d end
        end
    end
    return best
end
NS.Near = Near

-- The index follows each single add and removal, so a large merge never rebuilds it per entry.
local function Unlist(list, entry)
    for i = #list, 1, -1 do
        if rawequal(list[i], entry) then table.remove(list, i) return true end
    end
    return false
end

local function Add(db, e)
    db.list[#db.list + 1] = e
    if not cache then return end
    cache.entries[#cache.entries + 1] = e
    local list = cache.byNpc[e.id]
    if not list then list = {} cache.byNpc[e.id] = list end
    list[#list + 1] = e
    if e.own then cache.own = cache.own + 1 else cache.reported = cache.reported + 1 end
end

local function Remove(db, entry)
    if not Unlist(db.list, entry) then return false end
    if cache and Unlist(cache.entries, entry) then
        Unlist(cache.byNpc[entry.id] or {}, entry)
        if entry.own then cache.own = cache.own - 1 else cache.reported = cache.reported - 1 end
    end
    return true
end

-- Makes room for one more: the oldest report first, then the oldest of yours. Returns false when nothing can go.
local function MakeRoom(db, forOwn)
    local c = Index()
    if #c.entries < NS.MAX_ENTRIES then return true end
    local victim
    for _, e in ipairs(c.entries) do
        if not e.own and (not victim or (e.at or 0) < (victim.at or 0)) then victim = e end
    end
    if not victim and forOwn then
        for _, e in ipairs(c.entries) do
            if not victim or (e.at or 0) < (victim.at or 0) then victim = e end
        end
    end
    if not victim then return false end
    Remove(db, victim)
    return true
end

local function Spawns(id) return #(Index().byNpc[id] or {}) end

local function Copy(t)
    if not t then return nil end
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

---------------------------------------------------------------------------
-- What you saw
---------------------------------------------------------------------------
-- "Other merchants" only while nothing more specific is known about a merchant.
local function Settle(tags)
    if not tags.vendor then return end
    for id in pairs(tags) do
        local k = NK.BY_ID[id]
        if id ~= "vendor" and k and k.section == "vendors" then tags.vendor = nil return end
    end
end
NS.Settle = Settle

-- seen: { id, name, map, x, y (0..1 on the map), tags, cls (a token), prof, again (another read during the same visit:
-- what it offered is added, but it is not another visit and the place doesn't move) }. Returns the entry and "new",
-- "updated" or "confirmed" (a report you have now seen yourself), or nil and a reason code.
function NS.Observe(seen)
    local db = Store(true)
    if not db then return NS.Drop("no-store") end
    if not Writable(db) then return NS.Drop("newer-store") end
    local PN = R.Pins
    local x, y = PN and PN.Quantize(seen.x), PN and PN.Quantize(seen.y)
    local name = NS.CleanName(seen.name)
    if not NS.ValidId(seen.id) then return NS.Drop("bad-id") end
    if not name then return NS.Drop("no-name") end
    if not (x and y) then return NS.Drop("bad-coordinates") end
    if not NS.ValidMap(seen.map) then return NS.Drop("unknown-map") end
    if not ValidTags(seen.tags) then return NS.Drop("no-kind") end
    local cls = seen.cls and NK.IS_CLASS[seen.cls] and seen.cls or nil
    local prof = seen.prof and NS.CleanProfession(seen.prof) or nil
    local title = seen.title and NS.CleanTitle(seen.title) or nil
    local now = time()
    local e = Near(seen.id, seen.map, x, y)
    local status
    if e then
        if e.own then
            -- a later visit: the place is averaged (the last few visits count), and what it offered is added to
            if not seen.again then
                local k = math.min(e.seen or 1, 4)
                e.x = math.floor((e.x * k + x) / (k + 1) + 0.5)
                e.y = math.floor((e.y * k + y) / (k + 1) + 0.5)
                e.seen = math.min((e.seen or 1) + 1, MAX_COUNT)
            end
            for tag in pairs(seen.tags) do e.tags[tag] = true end
            Settle(e.tags)
            status = "updated"
        else
            -- a report you have now seen for yourself: what you saw replaces what was said
            e.own, e.seen, e.x, e.y = true, 1, x, y
            e.tags, e.cls = Copy(seen.tags), nil
            status = "confirmed"
            Invalidate()   -- (its count moves from reported to yours)
        end
        e.n = name
        if cls then e.cls = e.cls or {} e.cls[cls] = true end
        if prof then e.prof = prof end
        if title then e.t = title end
        e.at = now
    else
        if Spawns(seen.id) >= NS.MAX_PER_NPC then return NS.Drop("too-many-spawns") end
        if not MakeRoom(db, true) then return NS.Drop("full") end
        e = { id = seen.id, n = name, m = seen.map, x = x, y = y, tags = Copy(seen.tags), own = true, seen = 1, at = now }
        if cls then e.cls = { [cls] = true } end
        if prof then e.prof = prof end
        if title then e.t = title end
        Add(db, e)
        status = "new"
    end
    Changed()
    if status ~= "confirmed" then Seen(e, status) end
    return e, status
end

---------------------------------------------------------------------------
-- What others sent: the wire form, read as untrusted
-- wire: { i = id, n = name, m = map, x, y, k = { codes }, c = { class tokens } (optional), p = profession (optional), t = title (optional) }
---------------------------------------------------------------------------
function NS.Wire(e)
    local codes = {}
    for tag in pairs(e.tags) do codes[#codes + 1] = NK.BY_ID[tag].code end
    table.sort(codes)
    local w = { i = e.id, n = e.n, m = e.m, x = e.x, y = e.y, k = codes, p = e.prof, t = e.t }
    if e.cls then
        local c = {}
        for token in pairs(e.cls) do c[#c + 1] = token end
        table.sort(c)
        w.c = c
    end
    return w
end

local MAX_CODES, MAX_TOKENS = 24, 12
-- An entry's fields from a received table, or nil and a reason code. Nothing in it is trusted.
function NS.ReadWire(w)
    if type(w) ~= "table" then return NS.Drop("not-a-table") end
    if not NS.ValidId(w.i) then return NS.Drop("bad-id") end
    local name = NS.CleanName(w.n)
    if not name then return NS.Drop("no-name") end
    if not (NS.ValidCoord(w.x) and NS.ValidCoord(w.y)) then return NS.Drop("bad-coordinates") end
    if not NS.ValidMap(w.m) then return NS.Drop("unknown-map") end
    if type(w.k) ~= "table" or #w.k == 0 or #w.k > MAX_CODES then return NS.Drop("no-kind") end
    local tags = {}
    for _, code in ipairs(w.k) do
        local k = type(code) == "string" and NK.BY_CODE[code]
        if not k then return NS.Drop("unknown-kind") end
        tags[k.id] = true
    end
    local cls
    if w.c ~= nil then
        if type(w.c) ~= "table" or #w.c > MAX_TOKENS then return NS.Drop("bad-class") end
        for _, token in ipairs(w.c) do
            if type(token) ~= "string" or not NK.IS_CLASS[token] then return NS.Drop("bad-class") end
            cls = cls or {}
            cls[token] = true
        end
        if cls and not tags.classTrainer then return NS.Drop("bad-class") end
    end
    local prof
    if w.p ~= nil then
        prof = NS.CleanProfession(w.p)
        if not prof or not tags.profTrainer then return NS.Drop("bad-profession") end
    end
    local title
    if w.t ~= nil then
        title = NS.CleanTitle(w.t)
        if not title then return NS.Drop("bad-title") end
    end
    return { id = w.i, n = name, m = w.m, x = w.x, y = w.y, tags = tags, cls = cls, prof = prof, t = title }
end

-- What merging these (ReadWire results) would do: { new, more (a report of one you know only from reports, adding
-- to it), yours (one you saw yourself), same }. Reads only.
function NS.PreviewMerge(list)
    local out = { new = 0, more = 0, yours = 0, total = #list }
    local fresh = {}
    for _, f in ipairs(list) do
        local e = Near(f.id, f.m, f.x, f.y)
        if not e then
            local key = f.id .. ":" .. f.m .. ":" .. math.floor(f.x / NS.NEAR) .. ":" .. math.floor(f.y / NS.NEAR)
            if not fresh[key] then fresh[key] = true out.new = out.new + 1 end
        elseif e.own then out.yours = out.yours + 1
        else out.more = out.more + 1 end
    end
    return out
end

-- Adds reports (ReadWire results). Each sender's transfer counts once per entry. Returns { added, more, yours, refused }.
function NS.MergeReported(list)
    local result = { added = 0, more = 0, yours = 0, refused = 0 }
    local db = Store(true)
    if not db or not Writable(db) then result.refused = #list return result end
    local pt = Perf.on and Perf.Start("npcs.import")
    local now = time()
    for _, f in ipairs(list) do
        local e = Near(f.id, f.m, f.x, f.y)
        if e then
            e.rep = math.min((e.rep or 0) + 1, MAX_COUNT)
            if e.own then
                result.yours = result.yours + 1
            else
                for tag in pairs(f.tags) do e.tags[tag] = true end
                Settle(e.tags)
                if f.cls then
                    e.cls = e.cls or {}
                    for token in pairs(f.cls) do e.cls[token] = true end
                end
                if f.prof and not e.prof then e.prof = f.prof end
                if f.t and not e.t then e.t = f.t end
                e.at = now
                result.more = result.more + 1
            end
        elseif Spawns(f.id) < NS.MAX_PER_NPC and MakeRoom(db, false) then
            Add(db, { id = f.id, n = f.n, m = f.m, x = f.x, y = f.y, tags = Copy(f.tags), cls = Copy(f.cls),
                prof = f.prof, t = f.t, rep = 1, at = now })
            result.added = result.added + 1
        else
            result.refused = result.refused + 1
        end
    end
    if result.added + result.more + result.yours > 0 then Changed() end
    if pt then Perf.Stop(pt) end
    return result
end

---------------------------------------------------------------------------
-- Removing
---------------------------------------------------------------------------
function NS.Forget(entry)
    local db = Store()
    if not (db and Writable(db)) then return false end
    if not Remove(db, entry) then return false end
    Changed()
    return true
end

-- Removes exactly these entries (the very tables, as NS.Entries gave them) in one pass and tells the listeners once;
-- one that is already gone is skipped, and nothing else goes. Returns how many went.
function NS.ForgetMany(entries)
    local db = Store()
    if not (db and Writable(db)) or type(entries) ~= "table" then return 0 end
    local pt = Perf.on and Perf.Start("npcs.cleanup")
    local doomed = {}
    for _, e in ipairs(entries) do doomed[e] = true end
    local list, kept, n = db.list, 0, 0
    local size = #list
    for i = 1, size do
        local e = list[i]
        if doomed[e] then
            n = n + 1
        else
            kept = kept + 1
            list[kept] = e
        end
    end
    for i = size, kept + 1, -1 do list[i] = nil end
    if n > 0 then
        Invalidate()
        Changed()
    end
    if pt then Perf.Stop(pt) end
    return n
end

-- scope: "reported" (what others sent you and you never saw yourself) or "all". Returns how many went.
function NS.Clear(scope)
    local db = Store()
    if not (db and Writable(db)) then return 0 end
    local n = 0
    for i = #db.list, 1, -1 do
        local e = db.list[i]
        if Valid(e) and (scope == "all" or not e.own) then
            table.remove(db.list, i)
            n = n + 1
        end
    end
    Invalidate()
    if n > 0 then Changed() end
    return n
end

-- Reports nobody has refreshed for REPORT_DAYS go, once a load.
function NS.Expire(now)
    local db = Store()
    if not (db and Writable(db)) then return 0 end
    now = now or time()
    local n = 0
    for i = #db.list, 1, -1 do
        local e = db.list[i]
        if Valid(e) and not e.own and e.at and now - e.at > NS.REPORT_DAYS * DAY then
            table.remove(db.list, i)
            n = n + 1
        end
    end
    if n > 0 then Invalidate() end
    return n
end

R:On("PLAYER_LOGIN", function() NS.Expire() end)

-- Read only, for /tui diagnostics and the settings: counts, never names or places.
function NS.Snapshot()
    local db = Store()
    local own, reported = NS.Counts()
    local stored = db and #db.list or 0
    local drops = {}
    for k, v in pairs(NS.drops) do drops[k] = v end
    return { own = own, reported = reported, unreadable = stored - own - reported, newer = NS.Newer(), drops = drops }
end
