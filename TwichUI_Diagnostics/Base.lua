-- TwichUI Diagnostics: the base
-- What every other file here shares: the namespace (R.DiagnosticsKit while loading; R.Diagnostics once the window file,
-- loaded last, says the addon is ready), the preferences kept in TwichUIDiagnosticsDB, the clock scopes are timed with,
-- the capability matrix (what this client lets us measure, in which units, from where), and bounded containers.
-- Nothing here runs by itself: no frame, event or timer.
--
-- Units, everywhere in this addon: milliseconds for durations, seconds for capture times (from the capture's start),
-- kilobytes for memory. Every measurement says where it came from (its provenance) and what kind it is:
--   client-counter   a number the client keeps (C_AddOnProfiler, GetAddOnMemoryUsage, GetFramerate); its own semantics
--   instrumented     elapsed time we read around a synchronous TwichUI operation (R.Perf scopes)
--   frame-interval   the client's OnUpdate elapsed between two frames
--   sampled          a value read at an interval (memory, gauges): what happened between readings is not seen
--   estimated        worked out from other numbers; the method is stated with it

local R = TwichUI
local DX = { ADDON = "TwichUI_Diagnostics", CORE = R.ADDON, SETTINGS = "TwichUI_Settings", NAVDATA = "TwichUI_NavData" }
R.DiagnosticsKit = DX

DX.REPORT_SCHEMA = 1      -- the full report's JSON layout (Export.lua); separate from TwichUI's release version
DX.DB_VERSION = 1         -- TwichUIDiagnosticsDB's layout

---------------------------------------------------------------------------
-- Preferences (TwichUIDiagnosticsDB.prefs; account-wide, never part of a TwichUI profile)
---------------------------------------------------------------------------
DX.DEFAULTS = {
    spikeMs = 50,            -- a frame interval at or over this is a long frame (a "spike")
    gapMs = 1000,            -- at or over this it is a discontinuity (loading, alt-tab, a pause): left out of distributions
    chunkKB = 48,            -- an export is shown in pieces of at most this many kilobytes
    keepInMemory = 4,        -- finished captures kept this session (the oldest unsaved one goes first)
    saveLimit = 3,           -- captures kept in saved variables when you choose Save
    badge = true,            -- a small recording badge while the window is closed
    thresholds = {
        dominantShare = 0.5,     -- one operation at least this share of all measured TwichUI work
        rebuildPerMin = 30,      -- a rebuild or layout operation this often per minute
        handlerPerMin = 600,     -- one event's callbacks this often per minute
        listenerGrowth = 3,      -- listeners added across repeated window cycles
        memoryGrowthKB = 512,    -- TwichUI's sampled memory rising at least this much
        overheadShare = 0.25,    -- the diagnostics' own measured time against TwichUI's
        minSeconds = 60,         -- shorter captures are flagged as short
    },
}

-- A copy of `defaults` with `saved`'s valid values (same type) over it. Nothing in `saved` is changed.
local function Merge(defaults, saved)
    local out = {}
    for k, v in pairs(defaults) do
        local s
        if type(saved) == "table" then s = saved[k] end
        if type(v) == "table" then out[k] = Merge(v, s)
        elseif type(s) == type(v) and s == s then out[k] = s
        else out[k] = v end
    end
    return out
end
DX.Merge = Merge

local db                       -- TwichUIDiagnosticsDB once the game has loaded it (our ADDON_LOADED)
DX.prefs = Merge(DX.DEFAULTS, nil)

-- Validates the saved table narrowly: a damaged part is replaced, the rest kept as it is.
function DX.LoadDB()
    if type(TwichUIDiagnosticsDB) ~= "table" then TwichUIDiagnosticsDB = {} end
    db = TwichUIDiagnosticsDB
    if type(db.version) ~= "number" then db.version = DX.DB_VERSION end
    if db.version > DX.DB_VERSION then
        -- a newer TwichUI Diagnostics wrote this: read nothing of it and change nothing
        DX.newerDB = true
        db = nil
        return
    end
    if type(db.prefs) ~= "table" then db.prefs = {} end
    if type(db.sessions) ~= "table" then db.sessions = {} end
    for i = #db.sessions, 1, -1 do
        if type(db.sessions[i]) ~= "table" or db.sessions[i].schema ~= DX.REPORT_SCHEMA then table.remove(db.sessions, i) end
    end
    DX.prefs = Merge(DX.DEFAULTS, db.prefs)
end

function DX.DB() return db end

-- Changes one preference (path "spikeMs" or "thresholds.dominantShare") and keeps it when the saved table is there.
function DX.SetPref(path, value)
    local group, key = path:match("^(%w+)%.(%w+)$")
    local into, savedInto = DX.prefs, db and db.prefs
    if group then
        into = DX.prefs[group]
        if savedInto then savedInto[group] = type(savedInto[group]) == "table" and savedInto[group] or {}; savedInto = savedInto[group] end
    else
        key = path
    end
    if type(into) ~= "table" or into[key] == nil or type(into[key]) ~= type(value) then return false end
    into[key] = value
    if savedInto then savedInto[key] = value end
    return true
end

---------------------------------------------------------------------------
-- Change listeners (the window, the badge)
---------------------------------------------------------------------------
local listeners = {}
function DX.OnChange(fn)
    for _, f in ipairs(listeners) do if f == fn then return end end
    listeners[#listeners + 1] = fn
end
function DX.Changed(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("diagnostics", err) end
    end
end

---------------------------------------------------------------------------
-- The clock scopes are timed with: milliseconds, as precise as the client gives.
-- GetTimePreciseSec (Forever's API documentation, OsDocumentation.lua) first: nothing else can reset it.
-- debugprofilestop second: it counts from the last debugprofilestart, which any addon may call, so a reading
-- can jump back; such a delta is discarded and counted, never used. debugprofilestart is never called here.
-- GetTime is not used for scopes: it is the frame's time, the same all through one frame.
---------------------------------------------------------------------------
local function PickClock()
    if type(GetTimePreciseSec) == "function" then
        return function() return GetTimePreciseSec() * 1000 end, "GetTimePreciseSec"
    end
    if type(debugprofilestop) == "function" then return debugprofilestop, "debugprofilestop" end
    return nil, "none"
end
DX.Clock, DX.clockSource = PickClock()

-- The smallest step the clock was seen to take (ms), by reading it until it changes; nil when it never did.
function DX.ClockResolution()
    local clock = DX.Clock
    if not clock then return nil end
    local a = clock()
    local b, n = a, 0
    while b == a and n < 5000 do b = clock(); n = n + 1 end
    if b > a then return b - a end
    return nil
end

-- Seconds of capture time on the same clock (or the frame's time when there is no fine clock).
function DX.Now()
    if DX.Clock then return DX.Clock() / 1000 end
    return GetTime()
end

---------------------------------------------------------------------------
-- Capability matrix: what this client gives, looked up now (nothing is assumed from another game version).
-- Each entry: { id, label, state, unit, provenance, semantics, note }. state: "available", "unavailable", "off"
-- (there, but switched off in the client), "partial".
---------------------------------------------------------------------------
local function Profiler()
    local P = C_AddOnProfiler
    if not (P and P.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then return nil end
    local ok, on = pcall(P.IsEnabled)
    return ok and on == true, P
end

local function CVar(name)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not get then return nil end
    local ok, v = pcall(get, name)
    if ok and type(v) == "string" then return v end
    return nil
end
DX.CVar = CVar

-- scriptProfile as it was when this addon loaded: a change made since applies only after a reload.
DX.cvarAtLoad = CVar("scriptProfile")
function DX.ScriptProfileInEffect() return DX.cvarAtLoad == "1" end

function DX.Capabilities()
    local list = {}
    local function Add(id, label, state, unit, provenance, semantics, note)
        list[#list + 1] = { id = id, label = label, state = state, unit = unit, provenance = provenance, semantics = semantics, note = note }
    end
    local res = DX.ClockResolution()
    if DX.clockSource == "GetTimePreciseSec" then
        Add("clock", "Fine clock for operation timing", "available", "ms", "GetTimePreciseSec", "instrumented",
            ("monotonic; nothing else can reset it; smallest step seen %s"):format(res and ("%.4f ms"):format(res) or "unknown"))
    elseif DX.clockSource == "debugprofilestop" then
        Add("clock", "Fine clock for operation timing", "partial", "ms", "debugprofilestop", "instrumented",
            "any addon's debugprofilestart resets it; a backward step is discarded and counted")
    else
        Add("clock", "Fine clock for operation timing", "unavailable", "ms", "none", "instrumented", "operation timings are not recorded")
    end
    local enabled, P = Profiler()
    if P then
        Add("profiler", "Client addon profiler (C_AddOnProfiler)", enabled and "available" or "off", "ms per tick",
            "C_AddOnProfiler.GetAddOnMetric", "client-counter",
            "CPU time the client attributes to each addon in one tick (LastTime), its 60-tick average, and cumulative counts of ticks over 1/5/10/50/100 ms since the client started; never reset here")
        Add("measureCall", "Allocation of one call (C_AddOnProfiler.MeasureCall)", P.MeasureCall and (enabled and "available" or "off") or "unavailable",
            "bytes, ms", "C_AddOnProfiler.MeasureCall", "client-counter", "used only in a focused trace that asks for it")
    else
        Add("profiler", "Client addon profiler (C_AddOnProfiler)", "unavailable", "ms per tick", "none", "client-counter", "this client has no addon profiler")
    end
    local sp = CVar("scriptProfile")
    local inEffect = DX.ScriptProfileInEffect()
    local legacy = type(GetAddOnCPUUsage) == "function" and type(UpdateAddOnCPUUsage) == "function"
    if not legacy or sp == nil then
        Add("legacyCpu", "Legacy addon CPU totals (GetAddOnCPUUsage)", "unavailable", "ms (cumulative)", "GetAddOnCPUUsage", "client-counter",
            sp == nil and "the scriptProfile setting is not known to this client" or "the functions are missing")
    else
        local pending = sp ~= (DX.cvarAtLoad or sp) and "; the setting was changed this session and applies after a reload" or ""
        Add("legacyCpu", "Legacy addon CPU totals (GetAddOnCPUUsage)", inEffect and "available" or "off", "ms (cumulative)",
            "GetAddOnCPUUsage after UpdateAddOnCPUUsage", "client-counter",
            (inEffect and "scriptProfile is on: every addon runs slower while it is; read as differences from the capture's start, never reset"
                or "needs the scriptProfile setting and a reload; it slows every addon while on") .. pending)
    end
    local mem = type(GetAddOnMemoryUsage) == "function" and type(UpdateAddOnMemoryUsage) == "function"
    Add("memory", "Per-addon memory (GetAddOnMemoryUsage)", mem and "available" or "unavailable", "KB", "UpdateAddOnMemoryUsage + GetAddOnMemoryUsage", "sampled",
        "Lua memory the client puts down to each addon, garbage not yet collected included; the update is costly (Blizzard's addon list waits 15 s between reads)")
    Add("luaHeap", "Whole-UI Lua heap", type(collectgarbage) == "function" and "available" or "unavailable", "KB", "collectgarbage(\"count\")", "sampled",
        "every addon's Lua memory together; cheap to read")
    Add("frames", "Frame intervals", CreateFrame and "available" or "unavailable", "ms", "OnUpdate elapsed (only while recording)", "frame-interval",
        "the client's time between two frames; not CPU time")
    Add("fps", "Client frame rate", type(GetFramerate) == "function" and "available" or "unavailable", "frames/s", "GetFramerate", "client-counter",
        "the client's smoothed figure, read once a second; kept apart from frame intervals")
    Add("stacks", "Call paths for slow calls", type(debugstack) == "function" and "available" or "unavailable", "text", "debugstack", "sampled",
        "focused traces only, at most one a second, at the end of the slow call; TwichUI's files only")
    Add("errors", "Errors", "partial", "count", "TwichUI's own handlers (R.Fault); ADDON_ACTION_BLOCKED/FORBIDDEN; LUA_WARNING", "instrumented",
        "errors in timers, frame scripts and other addons go to the game's handler, which is not replaced")
    Add("events", "TwichUI event bus", R.ListenerCounts and "available" or "unavailable", "count, ms", "Core.lua's bus (R.Perf)", "instrumented",
        "events TwichUI received, each callback reached and its elapsed time; not other addons' events")
    Add("timers", "Timers", "partial", "count", "module snapshots", "sampled", "TwichUI has no central timer registry: only what a module's snapshot reports")
    return list
end

function DX.Capability(id, list)
    for _, c in ipairs(list or DX.Capabilities()) do if c.id == id then return c end end
    return nil
end

---------------------------------------------------------------------------
-- Bounded containers
---------------------------------------------------------------------------
-- A log-spaced histogram of durations: bucket i covers [BASE * STEP^(i-1), BASE * STEP^i). A percentile read from it
-- is the bucket's upper edge, so it is approximate: within one bucket (STEP - 1, about 19%) above the true value.
local Hist = { BASE = 0.001, STEP = 2 ^ 0.25, N = 100 }
DX.Hist = Hist
local LOG_STEP = math.log(Hist.STEP)

function Hist.New() return { n = 0 } end

function Hist.Index(ms)
    if ms <= Hist.BASE then return 1 end
    local i = math.floor(math.log(ms / Hist.BASE) / LOG_STEP) + 1
    if i < 1 then return 1 end
    if i > Hist.N then return Hist.N end
    return i
end

function Hist.Upper(i) return Hist.BASE * Hist.STEP ^ i end

function Hist.Add(h, ms)
    local i = Hist.Index(ms)
    h[i] = (h[i] or 0) + 1
    h.n = h.n + 1
end

-- p in 0..1: the upper edge of the bucket holding that share of the values; nil when empty.
function Hist.Percentile(h, p)
    if not h or h.n == 0 then return nil end
    local want = math.max(1, math.ceil(h.n * p))
    local seen = 0
    for i = 1, Hist.N do
        seen = seen + (h[i] or 0)
        if seen >= want then return Hist.Upper(i) end
    end
    return Hist.Upper(Hist.N)
end

-- A compact copy for a report: { [bucket] = count } as a list of pairs, plus n.
function Hist.Export(h)
    local out = { n = h.n, buckets = {} }
    for i = 1, Hist.N do
        if h[i] then out.buckets[#out.buckets + 1] = { Hist.Upper(i), h[i] } end
    end
    return out
end

-- A ring of at most `cap` items; adding past it drops the oldest and counts it.
local Ring = {}
DX.Ring = Ring
function Ring.New(cap) return { cap = cap, first = 1, n = 0, dropped = 0 } end
function Ring.Push(r, item)
    if r.n < r.cap then
        r.n = r.n + 1
        r[(r.first + r.n - 2) % r.cap + 1] = item
    else
        r[r.first] = item
        r.first = r.first % r.cap + 1
        r.dropped = r.dropped + 1
    end
end
function Ring.Get(r, i)   -- 1 = oldest kept
    if i < 1 or i > r.n then return nil end
    return r[(r.first + i - 2) % r.cap + 1]
end
function Ring.List(r)
    local out = {}
    for i = 1, r.n do out[i] = Ring.Get(r, i) end
    return out
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
function DX.Secret(v) return issecretvalue ~= nil and issecretvalue(v) or false end

-- A number fit to keep: finite, not secret; nil otherwise.
function DX.Num(v)
    if type(v) ~= "number" or DX.Secret(v) or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

function DX.Metadata(addon, field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, value = pcall(get, addon, field)
    if ok and type(value) == "string" and value ~= "" and not value:find("^@") then return value end
    return nil
end

function DX.IsLoaded(addon)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon) and true or false
end

function DX.InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- "1:05", "12:00" (minutes:seconds) for a duration in seconds.
function DX.Clock2(s)
    s = math.max(0, math.floor((s or 0) + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function DX.Ms(ms)
    if ms == nil then return "n/a" end
    if ms >= 100 then return ("%.0f ms"):format(ms) end
    if ms >= 1 then return ("%.1f ms"):format(ms) end
    return ("%.3f ms"):format(ms)
end

-- Text a player typed (a note, a marker): plain, one line, capped, and this character's own name, realm and
-- guild replaced (the troubleshooting service's backstop). Untrusted wherever it goes.
function DX.UserText(text, max)
    if type(text) ~= "string" then return nil end
    local clean = R.Diag and R.Diag.Clean and R.Diag.Clean(text, max or 200) or text:sub(1, max or 200)
    if clean == "" then return nil end
    return clean
end
