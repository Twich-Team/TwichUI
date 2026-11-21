-- TwichUI Fishing: the read-only interface for later stages (the fishing HUD, the Journal, Workshop valuation), and the
-- diagnostics. Everything returned is a copy: changing it changes nothing saved. Nothing here builds frames or loads
-- anything. docs/fishing.md, "Public interface", lists the shapes.
--
--   R.Fishing.API.State()            "idle" | "ready" | "line" | "looting"
--   R.Fishing.API.Session()          the session in progress (copy) or nil, with elapsed seconds
--   R.Fishing.API.Sessions(n)        up to n completed session summaries, newest first (copies)
--   R.Fishing.API.Totals()           lifetime totals (copy)
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

function API.Totals()
    local c = S.Char()
    return c and F.Copy(c.totals) or nil
end

function API.ZoneName(mapID)
    local c = S.Char()
    return c and c.zoneNames[mapID] or nil
end

-- The separation valuation needs so that nothing is counted twice: a container is either unopened (valued as itself, if
-- at all) or opened (valued by what it held); a direct catch that is a container is never in `direct`.
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
    local unopened = {}
    for _, lot in ipairs(c.queue) do
        if scope == "lifetime" or scope == nil or lot.sid == sid then unopened[lot.item] = (unopened[lot.item] or 0) + lot.n end
    end
    for id, e in pairs(rec.containers) do
        out.containers[id] = { caught = e.caught, opened = e.opened, unopened = unopened[id] or 0 }
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
