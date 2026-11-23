-- TwichUI Fishing: the read-only interface for later stages (the fishing HUD, the Journal, Workshop valuation), and the
-- diagnostics. Everything returned is a copy: changing it changes nothing saved. Nothing here builds frames or loads
-- anything. docs/fishing.md, "Public interface", lists the shapes.
--
--   R.Fishing.API.State()            "idle" | "ready" | "line" | "looting"
--   R.Fishing.API.Session()          the session in progress (copy) or nil, with elapsed seconds
--   R.Fishing.API.Sessions(n)        up to n completed session summaries, newest first (copies)
--   R.Fishing.API.SessionByID(id)    one session (kept or in progress) as a copy, or nil
--   R.Fishing.API.Totals()           lifetime totals (copy)
--   R.Fishing.API.Zones(scope)       species and containers by the zone they were caught in (Stage 3A refinement)
--   R.Fishing.API.Treasures(scope)   containers with what each held, per container (Stage 3A); Retention(): sessions kept
--   R.Fishing.API.Provenance(scope)  for valuation: scope "session" | "lifetime" | a session id ->
--                                    { direct = { [itemID] = q } (fish and other catches, containers excluded),
--                                      containers = { [itemID] = { caught, opened, unopened } },
--                                      contents = { [itemID] = q } (taken out of those containers) }
--   R.Fishing.API.Lure()             lure status: { state, seconds, enchantID, lure, identified, choice, why }
--   R.Fishing.API.Gear()             equipment status: { state, poleWorn, outstanding, kept, missing, leftOn, since, kind }
--   R.Fishing.API.Queue()            unopened containers: { { item, n, sid, t, locked } } oldest first
--   R.Fishing.API.Next()             what the fishing key would do now: { kind, why } (reads the game, changes nothing)
--   R.Fishing.API.ZoneName(mapID)    the zone's name as remembered
--   R.Fishing.Subscribe(event, fn)   notifications (Data.lua lists the events)

local R = TwichUI
local F = R.Fishing
local S = F.Store
local Ses = F.Session
local API = {}
F.API = API

function API.State() return F.Action.state end

function API.Session()
    local s = Ses.Current()
    if not s then return nil end
    local copy = F.Copy(s)
    copy.elapsed = Ses.Elapsed()
    return copy
end

function API.Sessions(n)
    local c = S.Char()
    local out = {}
    if not c then return out end
    n = F.Count(n) or #c.sessions
    for i = #c.sessions, math.max(1, #c.sessions - n + 1), -1 do out[#out + 1] = F.Copy(c.sessions[i]) end
    return out
end

-- One kept session (copy) by its id, or nil once it is no longer kept; the session in progress is answered too.
function API.SessionByID(id)
    id = F.Count(id)
    local s = id and Ses.Find(id)
    if not s then return nil end
    local copy = F.Copy(s)
    local cur = Ses.Current()
    if cur and cur.id == id then copy.elapsed = Ses.Elapsed() end
    return copy
end

-- The lifetime totals (copy). The location tables (spz, ctz) are left out: they are large and have their own calls (Zones,
-- ZoneDigest, ItemZones, ZoneSpecies); everything that was in the totals before schema 2 is unchanged.
local LOCATION = { spz = true, ctz = true }
local function CopyRecord(rec)
    local out = {}
    for k, v in pairs(rec) do if not LOCATION[k] then out[k] = F.Copy(v) end end
    return out
end
function API.Totals()
    local c = S.Char()
    return c and CopyRecord(c.totals) or nil
end

-- Finished sessions without their species and location tables, newest first (the Journal's lists: a list needs a session's
-- figures, its zones and how many kinds it caught, not the fish themselves; API.SessionByID has the whole record).
function API.SessionDigest()
    local c = S.Char()
    local out = {}
    if not c then return out end
    for i = #c.sessions, 1, -1 do
        local s, kinds = c.sessions[i], 0
        for _ in pairs(s.species or {}) do kinds = kinds + 1 end
        out[#out + 1] = { id = s.id, start = s.start, stop = s.stop, last = s.last, seconds = s.seconds, ended = s.ended, reason = s.reason,
            zone = s.zone, casts = s.casts, catches = s.catches, items = s.items, failed = s.failed, interrupted = s.interrupted,
            missed = s.missed, line = s.line, kinds = kinds, zones = F.Copy(s.zones or {}) }
    end
    return out
end

-- Where fish were caught, lifetime, without copying it (Stage 3A refinement). The calls the Journal pages use:
--   ZoneDigest()      { zones = { [mapID] = { kinds, located, top } }, limits }: per zone, how many kinds, how many fish placed there,
--                     and the most caught kind's id
--   ItemZones(item)   { zones = { { zone, q, c, f, l } ... }, overflow }: where one kind was caught, and how much of it has no zone
--                     entry because the record was full
--   ZoneSpecies(zone) { { id, q, c, f, l } ... }: the kinds caught in one zone
--   ZoneLimits()      { entries, max, full, overflow = { [item] = q } and overflowTotal, unknownOverflow, containerEntries,
--                     containerMax, containersLost, since }: how full the location records are and what they could not keep
function API.ZoneLimits()
    local c = S.Char()
    if not c then return nil end
    local t = c.totals
    local total = 0
    for _, q in pairs(t.spo or {}) do total = total + q end
    return { entries = t.spn or 0, max = F.LIMITS.zoneSpecies, full = (t.spn or 0) >= F.LIMITS.zoneSpecies,
        overflowTotal = total, unknownOverflow = t.spx == true, containerEntries = t.ctn or 0, containerMax = F.LIMITS.zoneContainers,
        containersLost = t.ctl or 0, since = c.locSince }
end

function API.ZoneDigest()
    local c = S.Char()
    if not c then return nil end
    local zones = {}
    for zone, zt in pairs(c.totals.spz or {}) do
        local kinds, located, top, topQ = 0, 0, nil, -1
        for item, e in pairs(zt) do
            kinds, located = kinds + 1, located + (e.q or 0)
            if (e.q or 0) > topQ or ((e.q or 0) == topQ and top and item < top) then top, topQ = item, e.q or 0 end
        end
        zones[zone] = { kinds = kinds, located = located, top = top }
    end
    return { zones = zones, limits = API.ZoneLimits() }
end

function API.ItemZones(item)
    local c = S.Char()
    if not c then return nil end
    local out = {}
    for zone, zt in pairs(c.totals.spz or {}) do
        local e = zt[item]
        if e then out[#out + 1] = { zone = zone, q = e.q, c = e.c, f = e.f, l = e.l } end
    end
    return { zones = out, overflow = (c.totals.spo or {})[item] or 0 }
end

function API.ZoneSpecies(zone)
    local c = S.Char()
    if not c then return nil end
    local out = {}
    for item, e in pairs((c.totals.spz or {})[zone] or {}) do out[#out + 1] = { id = item, q = e.q, c = e.c, f = e.f, l = e.l } end
    return out
end


-- Stage 3A (the Journal): what Provenance leaves out, per container: how many were caught, opened, failed and are waiting,
-- and what each is confirmed to have held. scope as Provenance. { [containerID] = { caught, opened, failed, unopened,
-- got = { [itemID] = quantity } } }, plus `contents` (everything taken out, by item) and `scope`.
function API.Treasures(scope)
    local c = S.Char()
    if not c then return nil end
    local rec, sid
    if scope == "lifetime" or scope == nil then rec = c.totals
    elseif scope == "session" then rec = c.session; sid = rec and rec.id
    else sid = F.Count(scope); rec = sid and Ses.Find(sid) end
    if not rec then return nil end
    local unopened = {}
    for _, lot in ipairs(c.queue) do
        if scope == "lifetime" or scope == nil or lot.sid == sid then unopened[lot.item] = (unopened[lot.item] or 0) + lot.n end
    end
    local out = { containers = {}, contents = F.Copy(rec.contents), scope = scope or "lifetime" }
    for id, e in pairs(rec.containers) do
        out.containers[id] = { caught = e.caught or 0, opened = e.opened or 0, failed = e.failed or 0, unopened = unopened[id] or 0,
            got = F.Copy(type(e.got) == "table" and e.got or {}) }
    end
    -- lots still waiting whose container is not in this record (older than the history kept) are still listed
    for id, n in pairs(unopened) do
        if not out.containers[id] then out.containers[id] = { caught = 0, opened = 0, failed = 0, unopened = n, got = {} } end
    end
    return out
end

-- Where things were caught (schema 2): { species = { [mapID] = { [itemID] = { q, c, f, l } } }, containers = { [mapID] = {
-- [containerID] = { caught, opened, failed, got = { [itemID] = q } } } }, since = when this character began recording
-- locations, scope }. mapID 0 is a catch whose zone could not be read. Catches from before `since` are in Totals()/Session
-- records (species, zones) but not here: the Journal shows that difference as history without a location. scope as
-- Provenance. Provenance, Treasures and the other calls are unchanged.
function API.Zones(scope)
    local c = S.Char()
    if not c then return nil end
    local rec
    if scope == "lifetime" or scope == nil then rec = c.totals
    elseif scope == "session" then rec = c.session
    else local sid = F.Count(scope); rec = sid and Ses.Find(sid) end
    if not rec then return nil end
    return { species = F.Copy(rec.spz or {}), containers = F.Copy(rec.ctz or {}), since = c.locSince, scope = scope or "lifetime",
        overflow = F.Copy(rec.spo or {}), containersLost = rec.ctl or 0, unknownOverflow = rec.spx == true }
end

-- How much history exists: sessions kept now and the most that are kept (config session.keep). Lifetime totals are not
-- limited by it; per-session records older than this are gone.
function API.Retention()
    local c = S.Char()
    return { kept = c and #c.sessions or 0, limit = math.floor(S.Get("session.keep") or F.LIMITS.sessions),
        held = S.held and true or false, available = c ~= nil }
end

function API.ZoneName(mapID)
    local c = S.Char()
    return c and c.zoneNames[mapID] or nil
end

-- The separation valuation needs so that nothing is counted twice: a container is either unopened (valued as itself, if
-- at all) or opened (valued by what it held); a direct catch that is a container is never in `direct`.
-- Small metadata view for estimates: never copy species/location history to read a duration.
function API.Metrics(scope)
    local c = S.Char()
    if not c then return nil end
    local rec
    if scope == "lifetime" or scope == nil then rec = c.totals
    elseif scope == "session" then rec = c.session
    else rec = Ses.Find(F.Count(scope)) end
    if not rec then return nil end
    return { seconds = rec == c.session and Ses.Elapsed() or rec.seconds, casts = rec.casts }
end

function API.Provenance(scope)
    local c = S.Char()
    if not c then return nil end
    local rec, sid
    if scope == "lifetime" or scope == nil then rec = c.totals
    elseif scope == "session" then rec = c.session; sid = rec and rec.id
    else sid = F.Count(scope); rec = sid and Ses.Find(sid) end
    if not rec then return nil end
    local out = { direct = {}, containers = {}, contents = F.Copy(rec.contents) }
    for id, e in pairs(rec.species) do
        if not rec.containers[id] then out.direct[id] = e.q end
    end
    local unopened, partial = {}, {}
    for _, lot in ipairs(c.queue) do
        if scope == "lifetime" or scope == nil or lot.sid == sid then
            unopened[lot.item] = (unopened[lot.item] or 0) + lot.n
            if lot.partial then partial[lot.item] = (partial[lot.item] or 0) + 1 end
        end
    end
    for id, e in pairs(rec.containers) do
        out.containers[id] = { caught = e.caught, opened = e.opened, unopened = unopened[id] or 0, partial = partial[id] or 0 }
    end
    return out
end

function API.Lure()
    local st = F.Lure.Status()
    local choice, why = F.Lure.Choose()
    st.choice, st.why = choice and choice.item or nil, why
    return st
end

function API.Gear() return F.Gear.Status() end

function API.Queue()
    local out = {}
    for _, lot in ipairs(F.Containers.Queue() or {}) do
        out[#out + 1] = { item = lot.item, n = lot.n, sid = lot.sid, t = lot.t, locked = lot.locked or nil }
    end
    return out
end

function API.Next()
    local a = F.Action.Decide(F.Action.Context())
    return { kind = a.kind, why = a.why }
end

---------------------------------------------------------------------------
-- Diagnostics: /tui fish status (local chat, the player's own command) and the snapshot TwichUI Diagnostics can read
---------------------------------------------------------------------------
function API.Diagnostics()
    local s = Ses.Current()
    local c = S.Char()
    local notes = {}
    for i = #F.notes, math.max(1, #F.notes - 9), -1 do notes[#notes + 1] = F.Copy(F.notes[i]) end
    return {
        schema = S.db and S.db.schema or nil, held = S.held, repairs = S.repairs, enabled = S.Get("enabled"),
        action = F.Action.Status(), loot = F.Loot.Status(), gear = F.Gear.Status(), lure = API.Lure(),
        queue = F.Containers.Status(), next = API.Next(),
        session = s and { id = s.id, elapsed = Ses.Elapsed(), casts = s.casts, catches = s.catches, items = s.items,
            failed = s.failed, interrupted = s.interrupted, missed = s.missed } or nil,
        stored = c and #c.sessions or 0, notes = notes, noteCounts = F.Copy(F.noteCounts), listeners = F.SubscriberCount(),
        fade = F.Fade and F.Fade.Status() or nil, ellesmere = F.Ellesmere and F.Ellesmere.Status() or nil,
    }
end

local function Yes(v) return v and "yes" or "no" end
local function Duration(sec)
    sec = math.floor(sec or 0)
    if sec >= 3600 then return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
    return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60)
end
API.Duration = Duration

function API.Report()
    local d = API.Diagnostics()
    local lines = {}
    local function Add(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Add("state %s; turned %s; saved data schema %s%s", d.action.state, d.enabled and "on" or "off", tostring(d.schema),
        d.held and " (held: saved by a newer version, nothing is written)" or "")
    Add("key: %s; open key: %s; Fishing spell: %s; reel: %s; interaction targeting: %s",
        #d.action.keys > 0 and table.concat(d.action.keys, ", ") or "not bound",
        #d.action.openKeys > 0 and table.concat(d.action.openKeys, ", ") or "not bound",
        d.action.spell and tostring(d.action.spell) or "not known", d.action.reel,
        d.action.interaction == nil and "unknown" or (d.action.interaction and "on" or "off (reeling by key may not find the bobber)"))
    Add("next press: %s%s; last press: %s", d.next.kind, d.next.why and (" (" .. d.next.why .. ")") or "", d.action.last or "none")
    if d.session then
        Add("session %d: %s, %d casts, %d catches, %d items, %d failed, %d interrupted, %d missed", d.session.id,
            Duration(d.session.elapsed), d.session.casts, d.session.catches, d.session.items, d.session.failed,
            d.session.interrupted, d.session.missed)
    else
        Add("no session in progress; %d kept", d.stored)
    end
    local lure = d.lure
    Add("lure: %s%s%s", lure.state, lure.seconds and (", " .. Duration(lure.seconds) .. " left") or "",
        lure.state ~= "no-pole" and lure.state ~= "unknown" and (lure.identified == false and ", unidentified enchant" or "") or "")
    local g = d.gear
    Add("gear: %s; pole worn: %s; to put back: %d; kept by you: %d; missing: %d", g.state, Yes(g.poleWorn), g.outstanding,
        g.kept, g.missing)
    local q = d.queue
    Add("containers: %d unopened in %d lots (%d locked); mode %s; automatic opening: %s", q.unopened, q.lots, q.locked, q.mode,
        q.autoOpen or "not tried")
    if F.Present and F.Present.ReportLines then
        for _, line in ipairs(F.Present.ReportLines()) do lines[#lines + 1] = line end
    end
    if #d.notes == 0 then Add("no recent errors")
    else
        for _, n in ipairs(d.notes) do Add("  %s %s%s", date("%H:%M:%S", n.at), n.code, n.detail and (": " .. n.detail) or "") end
    end
    return lines
end
