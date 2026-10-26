-- TwichUI Diagnostics: collectors
-- Everything read while a capture records, and nothing when it doesn't: one frame of our own whose OnUpdate is set at
-- the start and removed at the stop, and its events registered and unregistered the same way.
--
-- Each frame (OnUpdate, kept small: reads and additions into preallocated arrays, no table made):
--   * the client's frame interval (`elapsed`), into a histogram, the second's bucket, and a short ring of recent frames
--   * the client profiler's LastTime for TwichUI, its settings window, this addon and all addons together (ms in the
--     client's latest tick: a client counter, not our measurement)
--   * the instrumented TwichUI work that ended since the previous frame (Instrument.TakeFrame)
--   A long frame (spikeMs or more) keeps its neighbours: the 5 frames before it and the 5 after. A frame interval of
--   gapMs or more is a discontinuity (a loading screen, alt-tab, a pause) and is left out of the distributions.
-- Each second of capture time closes a bucket: frames, interval sum and worst, profiler sums and worst, instrumented
-- work, events received and callbacks run, the whole-UI Lua heap, the client's frame rate, combat, group size, and
-- whether the world map, the settings and this window are shown (sampled then: a change is known to the second).
-- At intervals (the preset's): per-addon memory (the client's update, timed: it is the costly read), the gauges, the
-- profiler's cumulative counters (ticks over 1/5/10/50/100 ms), and the legacy CPU totals if the client has them on.
-- Our own cost is kept in three parts that never overlap: the sampler's (the frame's work without the reads below), the
-- gauge reads and the memory updates. A long frame also keeps what we cost in the frame before it (the interval it
-- measures includes our previous OnUpdate), so a hitch we caused can be told from one we only saw.
-- Gauges are also read when the settings or the world map close: one sample per window cycle.
-- Context markers: combat, group size, loading screens, entering the world, zone changes, a TwichUI addon loading,
-- profile changes, your own markers. Errors: TwichUI's own handlers (R.Fault), blocked or forbidden actions
-- attributed to TwichUI, and Lua warnings (counted; text kept only when it names a TwichUI file).

local R = TwichUI
local DX = R.DiagnosticsKit
local I = DX.Instrument
local Hist, Ring = DX.Hist, DX.Ring
local Perf = R.Perf
local C = {}
DX.Collect = C

C.FRAME_RING = 120          -- recent frames kept for a spike's neighbours
C.SPIKE_CONTEXT = 5         -- frames kept before and after a long frame
C.MAX_SPIKES = 40           -- the longest kept (all are counted)
C.MAX_GAPS = 60
C.MAX_MARKERS = 300
C.MAX_ERRORS = 50
C.OVER = { 16.7, 33.3, 50, 100, 250 }   -- frame-interval thresholds counted exactly (ms)
C.PROFILER_COUNTS = { "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms", "CountTimeOver100Ms" }

local clock = DX.Clock
local S                       -- the session being recorded (Session.lua owns it)
local frame                   -- our one frame (made on first use, reused)
local recording = false
local t0                      -- the capture's start on the clock (ms)

-- per-frame state (locals for speed)
local prof, metric, LAST, ADDON_CORE, ADDON_DIAG, ADDON_SET, settingsLoaded
local ring = { t = {}, dt = {}, core = {}, work = {}, i = 0, n = 0 }
local pending = {}            -- spikes still waiting for the frames after them
local bucketEnd, b            -- the open bucket's end (s) and its fields
local nextMemory, nextGauges = 0, 0
local readAcc, lastOwn, lastRead = 0, 0, 0   -- ms of reads in this frame; our cost and reads in the previous frame
local inCombat, loading = false, false
local visible = { map = false, settings = false, window = false }

local function Now() return (clock() - t0) / 1000 end

---------------------------------------------------------------------------
-- The timeline (one bucket per second, as parallel arrays)
---------------------------------------------------------------------------
local FIELDS = { "t", "frames", "dtSum", "dtMax", "long", "core", "coreMax", "diag", "settings", "all", "work", "workMax",
    "events", "callbacks", "heap", "fps", "combat", "group", "gap", "mapShown", "settingsShown", "windowShown", "own" }
C.FIELDS = FIELDS

local function NewTimeline(cap)
    local tl = { n = 0, cap = cap }
    for _, f in ipairs(FIELDS) do tl[f] = {} end
    return tl
end

local function OpenBucket(at)
    b = { t = at, frames = 0, dtSum = 0, dtMax = 0, long = 0, core = 0, coreMax = 0, diag = 0, settings = 0, all = 0,
        work = 0, workMax = 0, gap = 0, own = 0 }
    bucketEnd = at + 1
end

local function Marker(kind, label, auto)
    if not S then return end
    Ring.Push(S.markers, { t = Now(), kind = kind, label = label, auto = auto ~= false })
end
C.Marker = Marker

local function CycleGauges(why) end   -- defined below

local function CloseBucket()
    local tl = S.timeline
    if tl.n >= tl.cap then S.full = true return end
    local events, callbacks = I.TakeBucket()
    b.events, b.callbacks = events, callbacks
    b.heap = collectgarbage and DX.Num(collectgarbage("count")) or nil
    b.fps = GetFramerate and DX.Num(GetFramerate()) or nil
    b.combat = inCombat and 1 or 0
    b.group = GetNumGroupMembers and DX.Num(GetNumGroupMembers()) or 0
    local map = WorldMapFrame ~= nil and WorldMapFrame:IsShown() or false
    local set = R.SettingsUI ~= nil and R.SettingsUI.IsShown() or false
    local win = DX.WindowShown and DX.WindowShown() or false
    b.mapShown, b.settingsShown, b.windowShown = map and 1 or 0, set and 1 or 0, win and 1 or 0
    if map ~= visible.map then
        Marker(map and "map-shown" or "map-hidden", nil)
        if not map then CycleGauges("map-closed") end
    end
    if set ~= visible.settings then Marker(set and "settings-shown" or "settings-hidden", nil) end
    if win ~= visible.window then Marker(win and "window-shown" or "window-hidden", nil) end
    visible.map, visible.settings, visible.window = map, set, win
    local n = tl.n + 1
    tl.n = n
    for _, f in ipairs(FIELDS) do tl[f][n] = b[f] end
    if b.group ~= S.lastGroup then
        if S.lastGroup ~= nil then Marker("group-size", tostring(b.group)) end
        S.lastGroup = b.group
        if b.group > S.maxGroup then S.maxGroup = b.group end
    end
end

---------------------------------------------------------------------------
-- Interval samplers
---------------------------------------------------------------------------
local function ReadMemory()
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
    local before = clock()
    local ok = pcall(UpdateAddOnMemoryUsage)
    local cost = clock() - before
    S.overhead.memoryMs = S.overhead.memoryMs + cost
    readAcc = readAcc + cost
    S.overhead.memoryReads = S.overhead.memoryReads + 1
    if cost > S.overhead.memoryWorst then S.overhead.memoryWorst = cost end
    if not ok then return end
    local function Get(name)
        if not DX.IsLoaded(name) then return nil end
        local okk, v = pcall(GetAddOnMemoryUsage, name)
        return okk and DX.Num(v) or nil
    end
    Ring.Push(S.memory, { t = Now(), core = Get(DX.CORE), settings = Get(DX.SETTINGS), diag = Get(DX.ADDON),
        navdata = Get(DX.NAVDATA), layouts = Get(DX.LAYOUTS), heap = collectgarbage and DX.Num(collectgarbage("count")) or nil, cost = cost })
end

local function ProfilerCounts()
    if not prof then return nil end
    local out = {}
    local M = Enum.AddOnProfilerMetric
    local function Read(addon)
        local row = {}
        for _, k in ipairs(C.PROFILER_COUNTS) do
            local ok, v
            if addon then ok, v = pcall(prof.GetAddOnMetric, addon, M[k]) else ok, v = pcall(prof.GetOverallMetric, M[k]) end
            row[k] = ok and DX.Num(v) or nil
        end
        local ok, peak
        if addon then ok, peak = pcall(prof.GetAddOnMetric, addon, M.PeakTime) else ok, peak = pcall(prof.GetOverallMetric, M.PeakTime) end
        row.PeakTime = ok and DX.Num(peak) or nil
        return row
    end
    out.core, out.diag, out.overall = Read(DX.CORE), Read(DX.ADDON), Read(nil)
    if DX.IsLoaded(DX.SETTINGS) then out.settings = Read(DX.SETTINGS) end
    return out
end

local function LegacyCpu()
    if not S.legacyOn then return nil end
    local ok = pcall(UpdateAddOnCPUUsage)
    if not ok then return nil end
    local function Get(name)
        if not DX.IsLoaded(name) then return nil end
        local okk, v = pcall(GetAddOnCPUUsage, name)
        return okk and DX.Num(v) or nil
    end
    return { core = Get(DX.CORE), settings = Get(DX.SETTINGS), diag = Get(DX.ADDON) }
end

local function ReadGauges(cycle)
    local before = clock()
    local values = {}
    for i, g in ipairs(S.gaugeDefs) do
        local ok, v = pcall(g.read)
        values[i] = ok and DX.Num(v) or nil
    end
    local sample = { t = Now(), cycle = cycle, v = values }
    if not cycle then
        sample.profiler = ProfilerCounts()
        sample.legacy = LegacyCpu()
    end
    Ring.Push(S.gauges, sample)
    local cost = clock() - before
    S.overhead.gaugeMs = S.overhead.gaugeMs + cost
    readAcc = readAcc + cost
    S.overhead.gaugeReads = S.overhead.gaugeReads + 1
end

CycleGauges = function(why)
    if not recording then return end
    ReadGauges(why)
    S.cycles[why] = (S.cycles[why] or 0) + 1
end

---------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------
local function KeepSpike(sp)
    local list = S.spikes
    S.spikeCount = S.spikeCount + 1
    if #list < C.MAX_SPIKES then list[#list + 1] = sp return end
    local low, at = math.huge, nil
    for i, x in ipairs(list) do if x.dt < low then low, at = x.dt, i end end
    if sp.dt > low then list[at] = sp end
end

local function OnUpdate(_, elapsed)
    local start = clock()
    local now = (start - t0) / 1000
    local prevOwn, prevRead = lastOwn, lastRead
    readAcc = 0
    local dt = elapsed * 1000
    local core, diag, set, all = 0, 0, 0, 0
    if prof then
        core = prof.GetAddOnMetric(ADDON_CORE, LAST) or 0
        diag = prof.GetAddOnMetric(ADDON_DIAG, LAST) or 0
        all = prof.GetOverallMetric(LAST) or 0
        if settingsLoaded then set = prof.GetAddOnMetric(ADDON_SET, LAST) or 0 end
    end
    local work, top, topMs = I.TakeFrame()
    while now >= bucketEnd do
        CloseBucket()
        OpenBucket(bucketEnd)
        if S.full then break end
    end
    local gap = dt >= S.gapMs or loading
    b.frames = b.frames + 1
    if gap then
        b.gap = b.gap + 1
        local gaps = S.gaps
        if #gaps < C.MAX_GAPS then
            gaps[#gaps + 1] = { t = now, dt = dt, cause = loading and "loading screen" or "long pause (alt-tab, loading or a hitch)" }
        else
            S.gapsDropped = S.gapsDropped + 1
        end
    else
        S.frameCount = S.frameCount + 1
        S.frameMs = S.frameMs + dt
        if dt > S.frameMaxMs then S.frameMaxMs = dt end
        Hist.Add(S.frameHist, dt)
        local over = S.over
        for i = 1, #C.OVER do if dt >= C.OVER[i] then over[i] = over[i] + 1 end end
        b.dtSum = b.dtSum + dt
        if dt > b.dtMax then b.dtMax = dt end
    end
    b.core, b.diag, b.settings, b.all, b.work = b.core + core, b.diag + diag, b.settings + set, b.all + all, b.work + work
    if core > b.coreMax then b.coreMax = core end
    if work > b.workMax then b.workMax = work end
    -- the recent frames, for long frames' neighbours
    local i = ring.i % C.FRAME_RING + 1
    ring.i, ring.n = i, math.min(ring.n + 1, C.FRAME_RING)
    ring.t[i], ring.dt[i], ring.core[i], ring.work[i] = now, dt, core, work
    if #pending > 0 then
        for k = #pending, 1, -1 do
            local sp = pending[k]
            local after = sp.after
            after[#after + 1] = { dt = dt, core = core, work = work }
            if #after >= C.SPIKE_CONTEXT then table.remove(pending, k) end
        end
    end
    if not gap and dt >= S.spikeMs then
        b.long = b.long + 1
        local before = {}
        for k = C.SPIKE_CONTEXT, 1, -1 do
            if k < ring.n then
                local j = (i - k - 1) % C.FRAME_RING + 1
                before[#before + 1] = { dt = ring.dt[j], core = ring.core[j], work = ring.work[j] }
            end
        end
        local sp = { t = now, dt = dt, core = prof and core or nil, all = prof and all or nil, work = work, top = top, topMs = topMs,
            combat = inCombat, before = before, after = {}, diag = prevOwn, diagRead = prevRead }
        KeepSpike(sp)
        pending[#pending + 1] = sp
    end
    if now >= nextMemory then
        nextMemory = now + S.memorySeconds
        ReadMemory()
    end
    if now >= nextGauges then
        nextGauges = now + S.gaugeSeconds
        ReadGauges(nil)
    end
    if S.stopAt and now >= S.stopAt then DX.Stop("time-limit") return end
    if S.full then DX.Stop("storage-limit") return end
    local own = clock() - start
    lastOwn, lastRead = own, readAcc
    S.overhead.samplerMs = S.overhead.samplerMs + (own - readAcc)
    b.own = b.own + own
end

---------------------------------------------------------------------------
-- Context events and errors (our frame's own, only while recording)
---------------------------------------------------------------------------
local OURS = { [R.ADDON] = true, TwichUI_Settings = true, TwichUI_NavData = true, TwichUI_Diagnostics = true, TwichUI_Layouts = true }
C.OURS = OURS

-- Only text from TwichUI's own files is kept (folder-relative, names replaced, capped); anything else is a note.
local function ErrorText(err)
    if DX.Secret(err) then return "<secret>", false end
    local text = type(err) == "string" and err or tostring(err)
    local first = text:match("^[^\n]*") or ""
    for name in pairs(OURS) do
        local s = first:find(name, 1, true)
        if s then return DX.UserText(first:sub(s), 160) or "?", true end
    end
    return "(not from TwichUI's files; message left out)", false
end
C.ErrorText = ErrorText

local function AddError(kind, source, text, ours)
    if not S then return end
    S.errorCount = S.errorCount + 1
    for _, e in ipairs(S.errors) do
        if e.kind == kind and e.source == source and e.text == text then
            e.n, e.last = e.n + 1, Now()
            return
        end
    end
    if #S.errors >= C.MAX_ERRORS then S.errorsDropped = S.errorsDropped + 1 return end
    S.errors[#S.errors + 1] = { kind = kind, source = source, text = text, ours = ours, n = 1, first = Now(), last = Now(),
        combat = inCombat }
end

local EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGIN", "ZONE_CHANGED_NEW_AREA", "ADDON_LOADED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }

local function OnEvent(_, event, a1, a2)
    if not recording then return end
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true; Marker("combat-start")
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false; Marker("combat-end")
    elseif event == "LOADING_SCREEN_ENABLED" then loading = true; Marker("loading-start")
    elseif event == "LOADING_SCREEN_DISABLED" then loading = false; Marker("loading-end")
    elseif event == "PLAYER_ENTERING_WORLD" then
        Marker("world-entered", a1 and "login" or (a2 and "reload" or nil))
        loading = false
    elseif event == "PLAYER_LEAVING_WORLD" then Marker("world-left")
    elseif event == "PLAYER_LOGIN" then Marker("login")
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local id
        if S.mapIds and C_Map and C_Map.GetBestMapForUnit then id = DX.Num(C_Map.GetBestMapForUnit("player")) end
        Marker("zone-changed", id and ("map " .. id) or nil)
    elseif event == "ADDON_LOADED" then
        if OURS[a1] then
            Marker("addon-loaded", a1)
            if a1 == DX.SETTINGS then settingsLoaded = prof ~= nil end
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
        if OURS[a1] then AddError(kind, a1, DX.UserText(tostring(a2 or "?"), 80) or "?", true)
        else S.otherBlocked = S.otherBlocked + 1 end
    elseif event == "LUA_WARNING" then
        S.warnings = S.warnings + 1
        local text, ours = ErrorText(a1)
        if ours then AddError("warning", "Lua warning", text, true) end
    end
end

-- R.Fault (Core.lua) calls this for an error caught in TwichUI's own handlers, before the game's handler gets it.
-- The traceback is not here (the handler's pcall ended it); the game's error display has it.
local function Fault(source, err)
    if not recording then return end
    local text, ours = ErrorText(err)
    AddError("error", DX.UserText(tostring(source or "?"), 40) or "?", text, ours)
end

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------
local closerHooked, profileHooked = false, false

-- session: the one Session.lua made; it has every container and its settings (spikeMs, gapMs, memorySeconds, ...).
function C.Begin(session, startAt)
    S = session
    t0 = startAt
    recording = true
    inCombat = DX.InCombat()
    loading = false
    visible.map = WorldMapFrame ~= nil and WorldMapFrame:IsShown() or false
    visible.settings = R.SettingsUI ~= nil and R.SettingsUI.IsShown() or false
    visible.window = DX.WindowShown and DX.WindowShown() or false
    local P = C_AddOnProfiler
    prof = nil
    if S.useProfiler and P and P.GetAddOnMetric and P.GetOverallMetric and Enum and Enum.AddOnProfilerMetric then
        LAST = Enum.AddOnProfilerMetric.LastTime
        ADDON_CORE, ADDON_DIAG, ADDON_SET = DX.CORE, DX.ADDON, DX.SETTINGS
        -- one guarded read of each: a client that refuses them is noted and the per-frame reads are left out
        local ok1, v1 = pcall(P.GetAddOnMetric, ADDON_CORE, LAST)
        local ok2, v2 = pcall(P.GetOverallMetric, LAST)
        if ok1 and ok2 and DX.Num(v1) and DX.Num(v2) then prof = P else S.profilerRefused = true end
    end
    settingsLoaded = prof ~= nil and DX.IsLoaded(DX.SETTINGS)
    ring.i, ring.n = 0, 0
    for k = #pending, 1, -1 do pending[k] = nil end
    OpenBucket(0)
    nextMemory, nextGauges = 0, 0
    readAcc, lastOwn, lastRead = 0, 0, 0
    S.profilerStart = ProfilerCounts()
    S.legacyStart = LegacyCpu()
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    for _, e in ipairs(EVENTS) do pcall(frame.RegisterEvent, frame, e) end
    frame:SetScript("OnUpdate", OnUpdate)
    Perf.Fault = Fault
    -- installed once, and quiet unless recording (neither can be removed: they check `recording`)
    if not closerHooked and R.OnSettingsClosed then
        closerHooked = true
        R.OnSettingsClosed(function()
            if recording then Marker("settings-closed"); CycleGauges("settings-closed") end
        end)
    end
    if not profileHooked and R.Profiles and R.Profiles.OnChange then
        profileHooked = true
        R.Profiles.OnChange(function() if recording then Marker("profile-changed") end end)
    end
end

-- Stops reading at once. The open bucket is closed, the last memory and gauge readings taken.
function C.End()
    if not recording then return end
    if frame then
        frame:SetScript("OnUpdate", nil)
        frame:UnregisterAllEvents()
    end
    local now = Now()
    if b and b.frames > 0 then CloseBucket() end
    if not S.full then
        ReadGauges(nil)
        ReadMemory()
    end
    recording = false
    Perf.Fault = function() end
    for k = #pending, 1, -1 do pending[k] = nil end
    S.duration = now
    S.profilerEnd = ProfilerCounts()
    S.legacyEnd = LegacyCpu()
    S = nil
    prof = nil
end

function C.Recording() return recording end
function C.Frame() return frame end
function C.OnUpdate() return frame and frame:GetScript("OnUpdate") end
