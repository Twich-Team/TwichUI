-- TwichUI Fishing: sessions, casts and lifetime totals
--
-- A session begins with the first fishing cast (or catch) when none is in progress, or with /tui fish start. It ends with
-- /tui fish stop, or when nothing fishing-related has happened for config session.idleMinutes (checked once a minute
-- while one is in progress, and at load: a session left by a reload or a disconnect ends at its last activity if that is
-- already too long ago, otherwise it simply continues). Lifetime totals are updated as things happen, so a reload or a
-- disconnect loses nothing that was recorded; ending a session only moves its summary into the history.
--
-- Counts (the same fields on a session and on the lifetime totals):
--   casts        fishing channels that began (one per cast; a duplicate start event is counted once)
--   catches      successful fishing interactions: loot windows the client marked as fishing loot (IsFishingLoot)
--   items        the quantity of items actually taken from those windows (one catch can hold several)
--   failed       casts the client refused (UNIT_SPELLCAST_FAILED with Fishing)
--   interrupted  lines the client interrupted (UNIT_SPELLCAST_INTERRUPTED with Fishing)
--   missed       lines that ended with no fishing loot after them (reeled too early, or nothing bit): inferred, see Loot.lua
--   line         seconds a line was out; seconds: a session's length (stop - start), summed for the lifetime
--   species[itemID]    = { q = quantity, c = times caught, f = first, l = last }  (direct fishing loot only)
--   containers[itemID] = { caught, opened, failed, got = { [itemID] = quantity } }  (containers caught directly)
--   contents[itemID]   = quantity taken out of fishing containers (never counted in items or species)
--   zones[mapID]       = { casts, catches, items, line }; the zone's name is kept once per character in zoneNames
--   spz[mapID][itemID] = { q, c, f, l }  where each species was caught (direct fishing loot only): the zone is read when
--                        the fishing loot window opens (Loot.lua passes it down), not when an item reaches the bags, so a
--                        catch is attributed to where the line was, a session may span zones, and a zone that could not be
--                        read is mapID 0, never a guess
--   ctz[mapID][containerID] = { caught, opened, failed?, got = { [itemID] = q } }  containers by the zone they were CAUGHT in;
--                        what one held stays with that zone however far away or late it is opened

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Ses = {}
F.Session = Ses

local seenCasts, seenOrder = {}, {}   -- castGUIDs already counted (runtime, bounded)

function Ses.Current()
    local c = S.Char()
    return c and c.session or nil
end

-- The player's zone: a map id (0 when the client gives none) and its name, remembered once per character.
function Ses.Zone()
    local id = C_Map and C_Map.GetBestMapForUnit and F.Count(C_Map.GetBestMapForUnit("player")) or 0
    local name
    if id > 0 and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(id)
        name = type(info) == "table" and F.Readable(info.name) or nil
    end
    if type(name) ~= "string" and GetRealZoneText then name = F.Readable(GetRealZoneText()) end
    local c = S.Char()
    if c and type(name) == "string" and name ~= "" and c.zoneNames[id] == nil then c.zoneNames[id] = name:sub(1, 64) end
    return id
end

-- A species caught in a zone, on one record: bounded (LIMITS.zoneSpecies new pairs per record), constant work.
local function SpeciesZone(rec, zone, id, q, now)
    if type(rec.spz) ~= "table" then rec.spz = {} end      -- a session kept from before schema 2 has none, and is left alone otherwise
    local zt = rec.spz[zone]
    if not zt then zt = {}; rec.spz[zone] = zt end
    local e = zt[id]
    if not e then
        if (rec.spn or 0) >= F.LIMITS.zoneSpecies then
            if next(zt) == nil then rec.spz[zone] = nil end
            F.Note("zone-species-full", "a new species-in-a-zone entry was not recorded")
            return
        end
        e = { q = 0, c = 0, f = now }
        zt[id] = e
        rec.spn = (rec.spn or 0) + 1
    end
    e.q, e.c, e.l = e.q + q, e.c + 1, now
end

local function ContainerZone(rec, zone, id)
    if type(rec.ctz) ~= "table" then rec.ctz = {} end
    local zt = rec.ctz[zone]
    if not zt then zt = {}; rec.ctz[zone] = zt end
    local e = zt[id]
    if not e then e = { caught = 0, opened = 0, failed = 0, got = {} }; zt[id] = e end
    if type(e.got) ~= "table" then e.got = {} end
    return e
end

local function Zone(t, id)
    local z = t.zones[id]
    if not z then z = { casts = 0, catches = 0, items = 0, line = 0 }; t.zones[id] = z end
    return z
end

-- Both the session in progress and the lifetime totals.
local function Both()
    local c = S.Char()
    if not c then return nil end
    return c.session, c.totals, c
end

function Ses.Start(reason)
    local c = S.Char()
    if not c then return nil end
    if c.session then return c.session end
    local now = F.Now()
    local s = S.NewTotals()
    s.id, s.start, s.last, s.reason = c.nextSession, now, now, reason
    s.zone = Ses.Zone()
    s.recent = {}
    c.nextSession = c.nextSession + 1
    c.session = s
    c.totals.sessions = c.totals.sessions + 1
    F.Emit("SESSION_START", s.id, reason)
    return s
end

function Ses.Ensure(reason) return Ses.Current() or Ses.Start(reason) end

function Ses.Touch()
    local s = Ses.Current()
    if s then s.last = F.Now() end
end

local function Add(field, n, zone)
    local s, t = Both()
    if not t then return end
    for _, rec in ipairs({ s or false, t }) do
        if rec then
            rec[field] = (rec[field] or 0) + n
            if zone then local z = Zone(rec, zone); z[field] = (z[field] or 0) + n end
        end
    end
end

-- A fishing channel began. castGUID dedupes a start event delivered twice.
function Ses.Cast(castGUID)
    castGUID = F.Readable(castGUID)
    if type(castGUID) == "string" then
        if seenCasts[castGUID] then return false end
        seenCasts[castGUID] = true
        seenOrder[#seenOrder + 1] = castGUID
        if #seenOrder > 50 then seenCasts[table.remove(seenOrder, 1)] = nil end
    end
    if not Ses.Ensure("cast") then return false end
    Ses.Touch()
    Add("casts", 1, Ses.Zone())
    F.Emit("CAST", castGUID)
    return true
end

-- "failed", "interrupted" or "missed".
function Ses.Lost(kind)
    if kind ~= "failed" and kind ~= "interrupted" and kind ~= "missed" then return end
    if not Ses.Current() then return end
    Ses.Touch()
    Add(kind, 1)
    F.Emit("CAST_FAILED", kind)
end

function Ses.Line(seconds)
    seconds = F.Num(seconds)
    if not seconds or seconds <= 0 or seconds > 120 then return end
    seconds = math.floor(seconds + 0.5)
    Add("line", seconds, Ses.Zone())
end

-- A successful fishing interaction, at `zone` (the map the line was in when the loot window opened; the current one when not
-- given). Returns the session id the catch belongs to.
function Ses.Catch(zone)
    local s = Ses.Ensure("catch")
    if not s then return nil end
    local now = F.Now()
    Ses.Touch()
    Add("catches", 1, F.Count(zone) or Ses.Zone())
    local _, t = Both()
    for _, rec in ipairs({ s, t }) do
        rec.first = rec.first or now
        rec.last = now
    end
    return s.id
end

-- The completed session summary with this id, if it is still kept.
function Ses.Find(sid)
    local c = S.Char()
    if not (c and sid) then return nil end
    if c.session and c.session.id == sid then return c.session end
    for i = #c.sessions, 1, -1 do
        if c.sessions[i].id == sid then return c.sessions[i] end
    end
    return nil
end

-- The records an event for session sid updates: that session (in progress or kept) and the lifetime totals.
local function Records(sid)
    local c = S.Char()
    if not c then return {} end
    local s = Ses.Find(sid)
    if s then return { s, c.totals } end
    return { c.totals }
end

local function Species(rec, id, q, now)
    local e = rec.species[id]
    if not e then e = { q = 0, c = 0, f = now }; rec.species[id] = e end
    e.q, e.c, e.l = e.q + q, e.c + 1, now
end

local function ContainerEntry(rec, id)
    local e = rec.containers[id]
    if not e then e = { caught = 0, opened = 0, failed = 0, got = {} }; rec.containers[id] = e end
    if type(e.got) ~= "table" then e.got = {} end
    return e
end

-- An item taken from a fishing loot window (direct catch), caught at `zone` (0: could not be read; nil: the current zone, which
-- only a caller with no capture has to rely on).
function Ses.Item(sid, itemID, q, zone)
    itemID, q = F.Count(itemID), F.Count(q)
    if not (itemID and q and q > 0) then return end
    local now = F.Now()
    zone = F.Count(zone) or Ses.Zone()
    for _, rec in ipairs(Records(sid)) do
        Species(rec, itemID, q, now)
        SpeciesZone(rec, zone, itemID, q, now)
        rec.items = rec.items + q
        local z = Zone(rec, zone)
        z.items = z.items + q
    end
    local s = Ses.Current()
    if s and s.id == sid and s.recent then
        s.recent[#s.recent + 1] = { t = now, item = itemID, q = q }
        while #s.recent > F.LIMITS.recent do table.remove(s.recent, 1) end
    end
    F.Emit("ITEM", itemID, q, "direct", sid)
end

-- A container caught directly (it is also an Item); opened/failed: one opening of it; got: what one held.
-- `zone` on these four is where the container was CAUGHT (the lot's zone); nil means that is not known (a lot from before schema
-- 2), and then only the zone-less records are updated.
function Ses.ContainerCaught(sid, itemID, q, zone)
    zone = F.Count(zone)
    for _, rec in ipairs(Records(sid)) do
        local e = ContainerEntry(rec, itemID)
        e.caught = e.caught + q
        if zone then local z = ContainerZone(rec, zone, itemID); z.caught = z.caught + q end
    end
end

function Ses.ContainerOpened(sid, itemID, zone)
    zone = F.Count(zone)
    for _, rec in ipairs(Records(sid)) do
        local e = ContainerEntry(rec, itemID)
        e.opened = e.opened + 1
        if zone then local z = ContainerZone(rec, zone, itemID); z.opened = z.opened + 1 end
    end
end

function Ses.ContainerFailed(sid, itemID, zone)
    zone = F.Count(zone)
    for _, rec in ipairs(Records(sid)) do
        local e = ContainerEntry(rec, itemID)
        e.failed = e.failed + 1
        if zone then local z = ContainerZone(rec, zone, itemID); z.failed = z.failed + 1 end
    end
end

-- An item taken out of a fishing container caught in session sid.
function Ses.Content(sid, containerID, itemID, q, zone)
    itemID, q = F.Count(itemID), F.Count(q)
    if not (itemID and q and q > 0 and containerID) then return end
    zone = F.Count(zone)
    for _, rec in ipairs(Records(sid)) do
        rec.contents[itemID] = (rec.contents[itemID] or 0) + q
        local e = ContainerEntry(rec, containerID)
        e.got[itemID] = (e.got[itemID] or 0) + q
        if zone then
            local z = ContainerZone(rec, zone, containerID)
            z.got[itemID] = (z.got[itemID] or 0) + q
        end
    end
    F.Emit("ITEM", itemID, q, "content", sid, containerID)
end

-- Ends the session in progress (at: when it ended, default now). Returns the summary kept in the history.
function Ses.End(reason, at)
    local c = S.Char()
    local s = c and c.session
    if not s then return nil end
    local stop = F.Num(at) and math.floor(at) or F.Now()
    if stop < s.start then stop = s.start end
    s.stop, s.ended = stop, reason
    s.seconds = stop - s.start
    s.recent = nil
    c.totals.seconds = c.totals.seconds + s.seconds
    c.sessions[#c.sessions + 1] = s
    c.session = nil
    local keep = math.floor(S.Get("session.keep") or F.LIMITS.sessions)
    while #c.sessions > keep do table.remove(c.sessions, 1) end
    F.Emit("SESSION_END", s.id, reason)
    if F.Gear and F.Gear.OnSessionEnd then F.Gear.OnSessionEnd(reason) end
    return s
end

-- Ends a session nothing has happened in for too long. now: wall-clock seconds. Returns true when it ended one.
function Ses.CheckIdle(now)
    local s = Ses.Current()
    if not s then return false end
    if F.Action and F.Action.LineOut and F.Action.LineOut() then return false end
    local idle = (S.Get("session.idleMinutes") or 10) * 60
    if (now or F.Now()) - (s.last or s.start) >= idle then
        Ses.End("idle", s.last or s.start)
        return true
    end
    return false
end

-- How long the session in progress has lasted so far (seconds), or nil.
function Ses.Elapsed()
    local s = Ses.Current()
    if not s then return nil end
    return math.max(0, F.Now() - s.start)
end
