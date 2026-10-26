-- TwichUI Diagnostics: captures
-- One capture at a time. Stopped until you start one (nothing starts by itself, at login or otherwise, except the one
-- start-up you armed for the next reload, which says so in chat).
--
--   DX.Start(preset, opts)  opts: { minutes, note, subsystem (focused), allocation (focused), mapIds, boot }
--   DX.Stop(reason)         stops collecting at once (frame script and events removed, R.Perf off), then puts the
--                           capture together: on the next frame, or when combat ends if it is stopped in combat
--   DX.Cancel()             stops and keeps nothing
--   DX.Mark(label)          a marker of your own at this moment
--   DX.SetNote(text)        the short "what I was doing" line (yours: untrusted text, shown as yours in exports)
-- A capture stops by itself at its length (at most DX.MAX_MINUTES) or when its timeline is full. Closing the window
-- does not stop it: a small badge says it is still recording (Window.lua).
--
-- Finished captures stay in memory for this session (prefs.keepInMemory, the oldest unsaved one goes first). Save
-- copies one into TwichUIDiagnosticsDB, which the game writes when you log out or reload (and only then); at most
-- prefs.saveLimit are kept there, each with its timeline merged to at most SAVED_BUCKETS buckets. A capture holds only
-- plain values: no function, frame or table of another module.

local R = TwichUI
local DX = R.DiagnosticsKit
local I, C, Hist, Ring = DX.Instrument, DX.Collect, DX.Hist, DX.Ring

DX.SAVED_BUCKETS = 300

local state = "stopped"       -- "stopped" | "recording" | "finishing"
local live                    -- the capture being recorded (or put together)
local sessions = {}           -- finished, this session, oldest first
local serial = 0
local finishFrame             -- waits for combat to end before a capture is put together

function DX.State() return state end
function DX.Recording() return state == "recording" end
function DX.Live() return live end

local function Say(fmt, ...) R.Print("diagnostics: " .. fmt, ...) end
DX.Say = Say

---------------------------------------------------------------------------
-- What a report says about where it was made: versions, the client, which switches are on. No names.
---------------------------------------------------------------------------
local function Fingerprint(text)
    local LD = LibStub and LibStub("LibDeflate", true)
    if LD and LD.Adler32 then return ("%08x"):format(LD:Adler32(text)) end
    local h = 0
    for i = 1, #text do h = (h * 31 + text:byte(i)) % 4294967296 end
    return ("%08x"):format(h)
end
DX.Fingerprint = Fingerprint

function DX.Environment()
    local env = { addons = {} }
    if GetBuildInfo then
        local v, build, _, toc = GetBuildInfo()
        env.client, env.build, env.interface = v and tostring(v) or nil, build and tostring(build) or nil, DX.Num(toc)
    end
    env.locale = GetLocale and GetLocale() or nil
    for _, name in ipairs({ DX.CORE, DX.SETTINGS, DX.NAVDATA, DX.ADDON }) do
        env.addons[#env.addons + 1] = { name = name, version = DX.Metadata(name, "Version"), loaded = DX.IsLoaded(name) }
    end
    local n, loaded = 0, 0
    if C_AddOns and C_AddOns.GetNumAddOns then
        n = C_AddOns.GetNumAddOns() or 0
        for i = 1, n do if C_AddOns.IsAddOnLoaded(i) then loaded = loaded + 1 end end
    end
    env.addonsInstalled, env.addonsLoaded = n, loaded
    -- TwichUI's switches (names are TwichUI's own; values on or off): the allowlisted configuration
    local on, keys = {}, {}
    for key in pairs(R.DEFAULT_MODULES or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local bits = {}
    for _, key in ipairs(keys) do
        local v = R:Enabled(key)
        if v then on[#on + 1] = key end
        bits[#bits + 1] = key .. "=" .. (v and "1" or "0")
    end
    env.modulesOn = on
    env.configFingerprint = Fingerprint(table.concat(bits, ";"))
    if IsInInstance then
        local _, kind = IsInInstance()
        if type(kind) == "string" and not DX.Secret(kind) then env.instance = kind:gsub("[^%w]", ""):sub(1, 10) end
    end
    env.combatAtStart = DX.InCombat()
    return env
end

---------------------------------------------------------------------------
-- Starting
---------------------------------------------------------------------------
local Finish   -- below

local function NewSession(preset, opts)
    local P = DX.prefs
    local sub = preset.mode == "focused" and DX.Subsystem(opts.subsystem or "") or nil
    local minutes = math.max(0.25, math.min(DX.MAX_MINUTES, tonumber(opts.minutes) or preset.minutes))
    serial = serial + 1
    local s = {
        id = serial, uid = ("%d-%d"):format(time and time() or 0, serial),
        preset = preset.key, presetName = preset.name, mode = preset.mode, subsystem = sub and sub.key or nil,
        startedAt = date and date("%Y-%m-%d %H:%M:%S") or "?", wall = time and time() or 0,
        minutes = minutes, note = DX.UserText(opts.note, 200), boot = opts.boot,
        spikeMs = P.spikeMs, gapMs = P.gapMs,
        memorySeconds = math.max(DX.MIN_MEMORY_SECONDS, preset.memorySeconds or 15), gaugeSeconds = preset.gaugeSeconds or 5,
        filter = sub and sub.filter or preset.filter, stacks = preset.stacks and true or false,
        allocation = (preset.mode == "focused" and opts.allocation) and true or false, mapIds = opts.mapIds and true or false,
        useProfiler = true,
        frameHist = Hist.New(), frameCount = 0, frameMs = 0, frameMaxMs = 0, over = {},
        spikes = {}, spikeCount = 0, gaps = {}, gapsDropped = 0,
        memory = Ring.New(400), gauges = Ring.New(600), cycles = {}, markers = Ring.New(C.MAX_MARKERS),
        errors = {}, errorCount = 0, errorsDropped = 0, warnings = 0, otherBlocked = 0,
        overhead = { exclusive = true, samplerMs = 0, gaugeMs = 0, gaugeReads = 0, memoryMs = 0, memoryReads = 0, memoryWorst = 0 },
        maxGroup = 0, lastGroup = nil,
    }
    for i = 1, #C.OVER do s.over[i] = 0 end
    s.gaugeDefs = DX.GaugeList(sub and sub.gauges or preset.gauges)
    s.legacyOn = DX.ScriptProfileInEffect() and type(GetAddOnCPUUsage) == "function"
    s.env = DX.Environment()
    s.caps = DX.Capabilities()
    s.stopAt = minutes * 60
    return s
end

function DX.Start(key, opts)
    opts = opts or {}
    if state == "recording" then return false, "already-recording" end
    if state == "finishing" then Finish(true) end   -- the last capture is put together now: you asked for a new one
    local preset = DX.Preset(key or "general")
    if not preset then return false, "unknown-preset" end
    if preset.mode == "focused" and not DX.Subsystem(opts.subsystem or "") then return false, "no-subsystem" end
    if not DX.Clock then return false, "no-clock" end
    live = NewSession(preset, opts)
    live.timeline = (function()
        local tl = { n = 0, cap = math.ceil(live.minutes * 60) + 5 }
        for _, f in ipairs(C.FIELDS) do tl[f] = {} end
        return tl
    end)()
    local t0 = DX.Clock()
    live.t0 = t0
    state = "recording"
    I.Begin({ t0 = t0, stacks = live.stacks, filter = live.filter, allocation = live.allocation })
    C.Begin(live, t0)
    live.overhead.perScopeMs = I.Calibrate(200)
    C.Marker("capture-start", preset.name)
    if opts.boot then
        C.Marker("observation-begins", "TwichUI's ADDON_LOADED, after its files ran and its saved data was read")
    end
    DX.Changed("start")
    return true
end

---------------------------------------------------------------------------
-- Stopping and putting a capture together
---------------------------------------------------------------------------
local function Copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function Findings(rec)
    if not DX.Findings then return {} end
    local ok, list = pcall(DX.Findings.Run, rec)
    if not ok then R.Fault("diagnostics findings", list) return {} end
    return list
end

local function Keep(rec)
    sessions[#sessions + 1] = rec
    local cap = math.max(1, DX.prefs.keepInMemory)
    while #sessions > cap do
        local drop
        for i, s in ipairs(sessions) do if not s.saved then drop = i break end end
        table.remove(sessions, drop or 1)
    end
end

-- Builds the finished capture from what was collected. now: put together at once (else it is already the moment).
Finish = function()
    if state ~= "finishing" or not live then return end
    if finishFrame then finishFrame:UnregisterAllEvents() end
    local s = live
    local res = I.Results()
    local fh = s.frameHist
    local maxFrame = s.frameCount > 0 and s.frameMaxMs or nil   -- the true largest interval, not a bucket's edge
    local function FramePct(p)   -- a bucket's upper edge, never above the largest interval seen
        local v = Hist.Percentile(fh, p)
        if v and maxFrame and v > maxFrame then v = maxFrame end
        return v
    end
    table.sort(s.spikes, function(a, b) return a.t < b.t end)
    local gaugeDefs = {}
    for i, g in ipairs(s.gaugeDefs) do gaugeDefs[i] = { id = g.id, label = g.label, kind = g.kind, unit = g.unit or "count", group = g.group } end
    local scopeCalls = 0
    for _, op in ipairs(res.ops) do scopeCalls = scopeCalls + op.calls end
    local rec = {
        schema = DX.REPORT_SCHEMA, id = s.id, uid = s.uid, preset = s.preset, presetName = s.presetName, mode = s.mode,
        subsystem = s.subsystem, startedAt = s.startedAt, wall = s.wall, duration = s.duration or 0, minutes = s.minutes,
        stopReason = s.stopReason, note = s.note, boot = s.boot and true or false, gcExperiment = s.gcExperiment or false,
        env = s.env, caps = s.caps,
        config = { spikeMs = s.spikeMs, gapMs = s.gapMs, memorySeconds = s.memorySeconds, gaugeSeconds = s.gaugeSeconds,
            filter = s.filter and Copy(s.filter) or nil, stacks = s.stacks, allocation = s.allocation, mapIds = s.mapIds,
            profiler = s.useProfiler and not s.profilerRefused, legacyCpu = s.legacyOn },
        timeline = s.timeline, markers = Ring.List(s.markers), markersDropped = s.markers.dropped,
        frames = { count = s.frameCount, ms = s.frameMs, hist = Hist.Export(fh), over = Copy(s.over), thresholds = Copy(C.OVER),
            p50 = FramePct(0.5), p95 = FramePct(0.95), p99 = FramePct(0.99), max = maxFrame,
            spikes = s.spikes, spikeCount = s.spikeCount, gaps = s.gaps, gapsDropped = s.gapsDropped },
        ops = res.ops, events = res.events, callbacks = res.callbacks, counters = res.counters, measured = res.measured,
        dropped = res.dropped, anomalies = res.anomalies,
        memory = Ring.List(s.memory), memoryDropped = s.memory.dropped,
        gauges = { defs = gaugeDefs, samples = Ring.List(s.gauges), dropped = s.gauges.dropped, cycles = s.cycles },
        profiler = { start = s.profilerStart, finish = s.profilerEnd, refused = s.profilerRefused or false },
        legacy = s.legacyOn and { start = s.legacyStart, finish = s.legacyEnd } or nil,
        errors = s.errors, errorCount = s.errorCount, errorsDropped = s.errorsDropped, warnings = s.warnings,
        otherBlocked = s.otherBlocked, maxGroup = s.maxGroup, errorNote = s.errorNote,
        overhead = s.overhead, scopeCalls = scopeCalls,
        truncated = { timeline = s.full or false, spikes = s.spikeCount > #s.spikes, gaps = s.gapsDropped > 0,
            markers = s.markers.dropped > 0, errors = s.errorsDropped > 0, memory = s.memory.dropped > 0, gauges = s.gauges.dropped > 0,
            ops = res.dropped.ops > 0, events = res.dropped.events > 0, callbacks = res.dropped.callbacks > 0 },
    }
    if rec.overhead.perScopeMs then rec.overhead.estimatedScopeMs = rec.overhead.perScopeMs * scopeCalls end
    -- a start-up capture began before TwichUI's switches were read: say which were on once it had loaded
    if rec.boot then rec.env = DX.Environment(); rec.env.readAt = "end of the capture (start-up began before the settings were loaded)" end
    rec.findings = Findings(rec)
    live = nil
    state = "stopped"
    Keep(rec)
    DX.Changed("finished")
    return rec
end
DX.Finish = function() return Finish() end

-- reason: "manual", "time-limit", "storage-limit", "cancel"
function DX.Stop(reason)
    if state ~= "recording" then return false end
    live.stopReason = reason or "manual"
    C.Marker("capture-stop", live.stopReason)
    C.End()
    I.End()
    state = "finishing"
    DX.Changed("stopping")
    if reason == "cancel" then
        live, state = nil, "stopped"
        DX.Changed("cancelled")
        return true
    end
    -- nothing is sorted or summed in combat (or inside the frame that stopped it): put together after
    finishFrame = finishFrame or CreateFrame("Frame")
    if DX.InCombat() then
        finishFrame:SetScript("OnEvent", function() Finish() end)
        finishFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        if reason ~= "time-limit" then Say("stopped; the capture is put together when combat ends.") end
    else
        local mine = live
        C_Timer.After(0, function() if live == mine then Finish() end end)
    end
    if reason == "time-limit" then Say("the capture reached its length and stopped. /tui perf shows it.")
    elseif reason == "storage-limit" then Say("the capture's storage is full, so it stopped. /tui perf shows it.") end
    return true
end

function DX.Cancel()
    if state ~= "recording" then return false end
    return DX.Stop("cancel")
end

function DX.Mark(label)
    if state ~= "recording" then return false end
    C.Marker("manual", DX.UserText(label, 60), false)
    DX.Changed("marker")
    return true
end

function DX.SetNote(text)
    if live then live.note = DX.UserText(text, 200) end
end

-- A capture's error note: text you add yourself (an error you saw), kept apart from what was observed.
function DX.SetErrorNote(rec, text)
    local target = rec or live
    if target then target.errorNote = DX.UserText(text, 300) end
end

-- One full garbage collection of every addon, as an explicit experiment: it can stall the game for a moment and it
-- changes what memory readings mean, so the capture (if one is recording) is marked and its report says so.
function DX.GcExperiment()
    local before = collectgarbage("count")
    local t = DX.Clock and DX.Clock() or 0
    collectgarbage("collect")
    local ms = DX.Clock and (DX.Clock() - t) or nil
    local after = collectgarbage("count")
    if live and state == "recording" then
        live.gcExperiment = true
        C.Marker("gc-experiment", ("%.0f KB freed in %s"):format(before - after, DX.Ms(ms)))
    end
    return before, after, ms
end

---------------------------------------------------------------------------
-- Kept captures
---------------------------------------------------------------------------
function DX.Sessions()
    local out = Copy(sessions)
    local db = DX.DB()
    for _, saved in ipairs(db and db.sessions or {}) do
        local dup = false
        for _, s in ipairs(sessions) do if s.uid == saved.uid then dup = true break end end
        if not dup then saved.saved = true; table.insert(out, 1, saved) end
    end
    return out
end

function DX.Session(uid)
    for _, s in ipairs(DX.Sessions()) do if s.uid == uid then return s end end
    return nil
end

-- A timeline merged k buckets at a time (sums added, worst kept), so a saved capture stays small and a spike is not
-- averaged away.
local MAXES = { dtMax = true, coreMax = true, workMax = true, combat = true, group = true, mapShown = true, settingsShown = true, windowShown = true }
local LASTS = { heap = true, fps = true }
function DX.MergeTimeline(tl, limit)
    if not tl or tl.n <= limit then return tl, 1 end
    local k = math.ceil(tl.n / limit)
    local out = { n = 0, cap = limit, merged = k }
    for _, f in ipairs(C.FIELDS) do out[f] = {} end
    for start = 1, tl.n, k do
        local n = out.n + 1
        out.n = n
        for _, f in ipairs(C.FIELDS) do
            local v
            for i = start, math.min(tl.n, start + k - 1) do
                local x = tl[f][i]
                if x ~= nil then
                    if f == "t" then v = v or x
                    elseif MAXES[f] then v = (v == nil or x > v) and x or v
                    elseif LASTS[f] then v = x
                    else v = (v or 0) + x end
                end
            end
            out[f][n] = v
        end
    end
    return out, k
end

function DX.Save(uid)
    local db = DX.DB()
    if not db then return false, DX.newerDB and "newer" or "not-ready" end
    local rec = DX.Session(uid)
    if not rec then return false, "missing" end
    for _, s in ipairs(db.sessions) do if s.uid == uid then return true end end
    if #db.sessions >= DX.prefs.saveLimit then return false, "full" end
    local copy = {}
    for k, v in pairs(rec) do copy[k] = v end
    copy.timeline = DX.MergeTimeline(rec.timeline, DX.SAVED_BUCKETS)
    copy.saved = nil
    db.sessions[#db.sessions + 1] = copy
    rec.saved = true
    DX.Changed("saved")
    return true
end

function DX.Unsave(uid)
    local db = DX.DB()
    if not db then return false end
    for i = #db.sessions, 1, -1 do
        if db.sessions[i].uid == uid then table.remove(db.sessions, i) end
    end
    for _, s in ipairs(sessions) do if s.uid == uid then s.saved = nil end end
    DX.Changed("saved")
    return true
end

-- Forgets a capture this session (and its saved copy when `saved` too).
function DX.Discard(uid, saved)
    for i = #sessions, 1, -1 do if sessions[i].uid == uid then table.remove(sessions, i) end end
    if saved then DX.Unsave(uid) end
    DX.Changed("discarded")
end

---------------------------------------------------------------------------
-- The armed start-up (DiagnosticsLauncher.lua calls this at TwichUI's ADDON_LOADED after a reload you made)
---------------------------------------------------------------------------
function DX.StartBoot(boot)
    local key = boot and DX.Preset(boot.preset or "") and boot.preset or "startup"
    if DX.Preset(key).mode == "focused" then key = "startup" end
    local ok, why = DX.Start(key, { boot = true, minutes = boot and boot.seconds and boot.seconds / 60 or nil,
        note = "start-up after an armed reload" })
    if boot then boot.state = ok and "recording" or "failed"; boot.why = why end
    -- said once the world is there (chat isn't ready this early)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        if ok then Say("recording the start-up you armed (%s; it stops by itself). /tui perf shows it.", DX.Preset(key).name) end
    end)
    return ok, why
end

---------------------------------------------------------------------------
-- Our own saved variables arrive with our ADDON_LOADED
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= DX.ADDON then return end
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    DX.LoadDB()
end)

---------------------------------------------------------------------------
-- /tui perf words (DiagnosticsLauncher.lua passes them on)
---------------------------------------------------------------------------
local WHY = {
    ["already-recording"] = "a capture is already recording (/tui perf stop first).",
    ["unknown-preset"] = "there is no preset by that name (general, map, settings, group, memory, focused).",
    ["no-subsystem"] = "a focused trace needs a subsystem: open /tui perf and pick one.",
    ["no-clock"] = "this client gives no fine clock, so nothing can be timed.",
}
DX.WHY = WHY

function DX.StatusLine()
    if state == "recording" and live then
        local el = DX.Now() - live.t0 / 1000
        return ("recording %s (%s) for %s of %s"):format(live.presetName, live.mode, DX.Clock2(el), DX.Clock2(live.minutes * 60))
    elseif state == "finishing" then
        return "stopped; putting the capture together"
    end
    return ("stopped; %d capture(s) kept this session"):format(#sessions)
end

function DX.Command(word, rest)
    if word == "start" then
        local key, minutes = (rest or ""):match("^(%S*)%s*(%S*)")
        key = key ~= "" and key:lower() or "general"
        local p = DX.Preset(key)
        if p and p.mode == "focused" then
            local sub = (rest or ""):match("^%S+%s+(%S+)")
            if sub and DX.Subsystem(sub) then minutes = (rest or ""):match("^%S+%s+%S+%s+(%S+)") or "" end
            local ok, why = DX.Start(key, { subsystem = sub, minutes = tonumber(minutes) })
            if not ok then Say("%s", WHY[why] or why) else Say("%s.", DX.StatusLine()) end
            return
        end
        local ok, why = DX.Start(key, { minutes = tonumber(minutes) })
        if not ok then Say("%s", WHY[why] or why) else Say("%s. Closing the window keeps it recording; /tui perf stop ends it.", DX.StatusLine()) end
    elseif word == "stop" then
        if not DX.Stop("manual") then Say("nothing is recording.") end
    elseif word == "cancel" then
        if DX.Cancel() then Say("cancelled; nothing of that capture was kept.") else Say("nothing is recording.") end
    elseif word == "mark" then
        if DX.Mark(rest ~= "" and rest or nil) then Say("marker added.") else Say("nothing is recording, so there is nowhere to put a marker.") end
    elseif word == "status" then
        Say("%s.", DX.StatusLine())
    else
        if DX.Open then DX.Open(word) end
    end
end
