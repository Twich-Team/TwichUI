-- TwichUI: navigation, what has been learned
-- Navigation ships no route data. What it knows about flights it learns while it is on, from the game
-- itself, and keeps here so the next session plans better:
--   * routes: the stops a flight passes through, as a flight master's map shows them (from one flight
--     point to another, in order);
--   * times:  how long a flight along those stops took you, take-off to landing;
--   * known:  for each character, the flight points a flight master's map has listed as theirs (current
--     or reachable). Only these are flown between: the world map's own "undiscovered" mark can't be relied
--     on in this client, so a flight point counts as yours only once a flight master has shown it.
-- Routes and times are facts about the world, so they are shared by every character; what a character
-- knows is kept under its own name. All of it is account-wide (one saved variable). Nothing here is a
-- setting, and none of it is ever shared, sent or backed up: the variable's name starts with "TwichUI",
-- which configuration sharing and backups refuse (setup/Setups.lua). The player can forget it all from
-- the Navigation options.
--
-- TwichUINavigationDB = { version = 1,
--     routes = { ["from:to"] = { hops = { from, ..., to }, seen = time() } },   -- flight point IDs
--     times  = { ["a-b-c"]   = { s = seconds, n = flights, seen = time() } },     -- keyed by the stops
--     chars  = { ["Name - Realm"] = { known = { [flight point ID] = time() }, seen = time() } } }
--
-- Saved by a newer TwichUI (a higher version): not read or changed. It is set aside for the session and
-- handed back at logout (see Persist.lua); this session learns into an empty table that is not saved.

local R = TwichUI
local ND = {}
R.NavData = ND

ND.VERSION = 1
ND.MAX_ROUTES = 3000       -- a flight master shows a few dozen; this is far more than Forever has
ND.MAX_TIMES = 1000
ND.MAX_HOPS = 24           -- stops in one flight, both ends included
ND.MIN_FLIGHT, ND.MAX_FLIGHT = 5, 3600   -- seconds: a measured flight outside this is not kept
ND.MAX_KNOWN = 400         -- flight points one character can have
ND.MAX_CHARS = 60          -- characters whose flight points are kept; the least recently seen go first
local TIME_WEIGHT = 5      -- a new flight time counts as much as the last few together

local outcome              -- "fresh" | "current" | "future", for the troubleshooting report
local revision = 0         -- bumped on every change, so cached flight costs know to start again

local function Count(n) return type(n) == "number" and n == n and n >= 0 and n % 1 == 0 and n < 2 ^ 53 end
local function NodeID(n) return type(n) == "number" and n == n and n >= 1 and n % 1 == 0 and n < 2 ^ 31 end
ND.NodeID = NodeID

function ND.RouteKey(from, to) return from .. ":" .. to end
function ND.HopsKey(hops) return table.concat(hops, "-") end

local function Repair(code, n) if R.Persist then R.Persist.Repair(code, n) end end

-- A list of 2 to MAX_HOPS flight point IDs, or nil.
local function CleanHops(hops)
    if type(hops) ~= "table" then return nil end
    local n = #hops
    if n < 2 or n > ND.MAX_HOPS then return nil end
    for k in pairs(hops) do
        if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then return nil end
    end
    for i = 1, n do
        if not NodeID(hops[i]) then return nil end
    end
    return hops
end

-- Removes the oldest entries until the table holds at most max. Returns how many went.
local function Trim(tbl, max)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    if #keys <= max then return 0 end
    table.sort(keys, function(a, b)
        local sa, sb = tbl[a].seen or 0, tbl[b].seen or 0
        if sa ~= sb then return sa < sb end
        return tostring(a) < tostring(b)
    end)
    local drop = #keys - max
    for i = 1, drop do tbl[keys[i]] = nil end
    return drop
end

local function CleanRoutes(routes)
    local dropped = 0
    for key, rec in pairs(routes) do
        local a, b
        if type(key) == "string" then a, b = key:match("^(%d+):(%d+)$") end
        a, b = tonumber(a), tonumber(b)
        local hops = type(rec) == "table" and CleanHops(rec.hops)
        if not (a and b and a ~= b and hops and hops[1] == a and hops[#hops] == b) then
            routes[key] = nil
            dropped = dropped + 1
        elseif not Count(rec.seen) then
            rec.seen = 0
        end
    end
    return dropped
end

local function CleanTimes(times)
    local dropped = 0
    for key, rec in pairs(times) do
        local ok = type(key) == "string" and key:match("^%d+%-%d+[%-%d]*$") ~= nil and type(rec) == "table"
            and type(rec.s) == "number" and rec.s == rec.s and rec.s >= ND.MIN_FLIGHT and rec.s <= ND.MAX_FLIGHT
        if not ok then
            times[key] = nil
            dropped = dropped + 1
        else
            if not (Count(rec.n) and rec.n >= 1) then rec.n = 1 end
            if not Count(rec.seen) then rec.seen = 0 end
        end
    end
    return dropped
end

-- Removes the oldest of a { [key] = time } set until it holds at most max. Returns how many went.
local function TrimSet(set, max)
    local keys = {}
    for k in pairs(set) do keys[#keys + 1] = k end
    if #keys <= max then return 0 end
    table.sort(keys, function(a, b)
        if set[a] ~= set[b] then return set[a] < set[b] end
        return a < b
    end)
    local drop = #keys - max
    for i = 1, drop do set[keys[i]] = nil end
    return drop
end

local function CleanChars(chars)
    local dropped = 0
    for key, rec in pairs(chars) do
        if type(key) ~= "string" or key == "" or type(rec) ~= "table" or type(rec.known) ~= "table" then
            chars[key] = nil
            dropped = dropped + 1
        else
            if not Count(rec.seen) then rec.seen = 0 end
            for id, at in pairs(rec.known) do
                if not NodeID(id) then
                    rec.known[id] = nil
                    dropped = dropped + 1
                elseif not Count(at) then
                    rec.known[id] = 0
                end
            end
            dropped = dropped + TrimSet(rec.known, ND.MAX_KNOWN)
        end
    end
    return dropped
end

-- Set up at load (R:OnInit), before any learning. Repeatable.
function ND.Init()
    local P = R.Persist
    if P then P.EnsureRoot("TwichUINavigationDB") elseif type(TwichUINavigationDB) ~= "table" then TwichUINavigationDB = {} end
    local db = TwichUINavigationDB
    if not (P and P.IsHeld("TwichUINavigationDB")) then
        local stored = db.version
        if stored ~= nil and not Count(stored) then stored = nil end
        outcome = next(db) == nil and "fresh" or "current"
        if stored and stored > ND.VERSION then
            db = { version = ND.VERSION, routes = {}, times = {}, chars = {} }
            if P then P.Hold("TwichUINavigationDB", TwichUINavigationDB, db) else TwichUINavigationDB = db end
            outcome = "future"
            Repair("nav-future")
        end
    end
    db.version = ND.VERSION
    if type(db.routes) ~= "table" then
        if db.routes ~= nil then Repair("nav-entry-dropped") end
        db.routes = {}
    end
    if type(db.times) ~= "table" then
        if db.times ~= nil then Repair("nav-entry-dropped") end
        db.times = {}
    end
    if type(db.chars) ~= "table" then
        if db.chars ~= nil then Repair("nav-entry-dropped") end
        db.chars = {}
    end
    local dropped = CleanRoutes(db.routes) + CleanTimes(db.times) + CleanChars(db.chars)
    if dropped > 0 then Repair("nav-entry-dropped", dropped) end
    local trimmed = Trim(db.routes, ND.MAX_ROUTES) + Trim(db.times, ND.MAX_TIMES) + Trim(db.chars, ND.MAX_CHARS)
    if trimmed > 0 then Repair("nav-trimmed", trimmed) end
    revision = revision + 1
end

local function DB()
    if type(TwichUINavigationDB) ~= "table" or type(TwichUINavigationDB.routes) ~= "table"
        or type(TwichUINavigationDB.times) ~= "table" or type(TwichUINavigationDB.chars) ~= "table" then
        ND.Init()
    end
    return TwichUINavigationDB
end

function ND.Revision() return revision end

-- The stops of the flight from one flight point to another, as last seen at a flight master, or nil.
-- Read only: don't change the list.
function ND.Route(from, to)
    local rec = DB().routes[ND.RouteKey(from, to)]
    return rec and rec.hops
end

-- Keeps (or refreshes) a route a flight master showed. The list is copied.
function ND.SetRoute(from, to, hops)
    if not (NodeID(from) and NodeID(to) and from ~= to) then return false end
    if not (CleanHops(hops) and hops[1] == from and hops[#hops] == to) then return false end
    local routes = DB().routes
    local key = ND.RouteKey(from, to)
    local rec = routes[key]
    local same = rec and #rec.hops == #hops
    if same then
        for i = 1, #hops do if rec.hops[i] ~= hops[i] then same = false break end end
    end
    if same then
        rec.seen = time()
        return true
    end
    local copy = {}
    for i = 1, #hops do copy[i] = hops[i] end
    routes[key] = { hops = copy, seen = time() }
    if not rec then Trim(routes, ND.MAX_ROUTES) end
    revision = revision + 1
    return true
end

-- Seconds a flight along these stops has taken, and over how many flights; nil when never flown.
function ND.Time(hops)
    local rec = DB().times[ND.HopsKey(hops)]
    if rec then return rec.s, rec.n end
end

-- Adds one measured flight. A time outside MIN_FLIGHT..MAX_FLIGHT is not kept (an interrupted flight,
-- a reload in the air).
function ND.AddTime(hops, seconds)
    if not CleanHops(hops) then return false end
    if type(seconds) ~= "number" or seconds ~= seconds or seconds < ND.MIN_FLIGHT or seconds > ND.MAX_FLIGHT then return false end
    local times = DB().times
    local key = ND.HopsKey(hops)
    local rec = times[key]
    if rec then
        local n = math.min(rec.n + 1, TIME_WEIGHT)
        rec.s = rec.s + (seconds - rec.s) / n
        rec.n = rec.n + 1
        rec.seen = time()
    else
        times[key] = { s = seconds, n = 1, seen = time() }
        Trim(times, ND.MAX_TIMES)
    end
    revision = revision + 1
    return true
end

-- Every measured flight, for working out a typical flight speed: fn(hops, seconds) for each.
function ND.EachTime(fn)
    for key, rec in pairs(DB().times) do
        local hops = {}
        for id in key:gmatch("%d+") do hops[#hops + 1] = tonumber(id) end
        fn(hops, rec.s)
    end
end

-- The key this character's flight points are kept under, as the Chronicle names characters.
function ND.CharKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local NONE = {}

-- The flight points a flight master's map has listed as this character's: { [ID] = time }, or an empty
-- set. Read only: don't change it.
function ND.Known()
    local rec = DB().chars[ND.CharKey()]
    return rec and rec.known or NONE
end

-- Adds flight points a flight master's map lists as this character's. Returns how many were new.
function ND.AddKnown(ids)
    local chars = DB().chars
    local key = ND.CharKey()
    local rec = chars[key]
    local now = time()
    if not rec then
        rec = { known = {}, seen = now }
        chars[key] = rec
        Trim(chars, ND.MAX_CHARS)
    end
    rec.seen = now
    local added = 0
    for _, id in ipairs(ids) do
        if NodeID(id) then
            if rec.known[id] == nil then added = added + 1 end
            rec.known[id] = now
        end
    end
    if added > 0 then
        TrimSet(rec.known, ND.MAX_KNOWN)
        revision = revision + 1
    end
    return added
end

-- Forgets everything learned. Asked for by the player in the options.
function ND.Forget()
    local db = DB()
    db.routes, db.times, db.chars = {}, {}, {}
    revision = revision + 1
end

-- Counts only, for the troubleshooting report.
function ND.Snapshot()
    local db = DB()
    local routes, times = 0, 0
    for _ in pairs(db.routes) do routes = routes + 1 end
    for _ in pairs(db.times) do times = times + 1 end
    local chars, known = 0, 0
    for _ in pairs(db.chars) do chars = chars + 1 end
    for _ in pairs(ND.Known()) do known = known + 1 end
    return { outcome = outcome, routes = routes, times = times, maxRoutes = ND.MAX_ROUTES, maxTimes = ND.MAX_TIMES,
        chars = chars, known = known }
end

R:OnInit(ND.Init)
