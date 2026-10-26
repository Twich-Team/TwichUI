-- TwichUI Diagnostics: findings
-- Fixed rules over a finished capture's numbers; no guessing and no in-game AI. Each finding says what it is based on:
--   category    cost | frequency | lifecycle | memory | frames | errors | coverage
--   severity    high | medium | low | info, with `basis`: the rule and the threshold that put it there
--   evidence    the measured numbers, as lines; `window` the capture time it covers (seconds)
--   confidence  measured (a direct count or timing) | correlated (happened together; not shown to be cause) |
--               suspicion (a pattern worth checking; not proof)
--   limits      what the evidence can't show; `verify` how to check it; `ids` the operations or gauges concerned
-- Thresholds are prefs.thresholds (Base.lua), with their defaults explained there; none is a universal budget.
-- Never concluded here: a leak from one rising reading, TwichUI as the cause of low frame rates, a function from an
-- addon-wide total, or an improvement from a shorter capture (Compare.lua normalises before it compares).

local R = TwichUI
local DX = R.DiagnosticsKit
local F = {}
DX.Findings = F

local RANK = { high = 1, medium = 2, low = 3, info = 4 }
F.RANK = RANK

local function Ms(v) return DX.Ms(v) end
local function Pct(x) return ("%.0f%%"):format((x or 0) * 100) end

local function Minutes(rec) return math.max(rec.duration or 0, 1) / 60 end

-- Σ self time of every scope: the measured TwichUI work, counted once (self times never overlap).
function F.MeasuredWork(rec)
    local total = 0
    for _, op in ipairs(rec.ops or {}) do total = total + (op.self or 0) end
    return total
end

local function Timeline(rec, field)
    local tl = rec.timeline
    return tl and tl[field] or {}, tl and tl.n or 0
end

local function Sum(rec, field)
    local list, n = Timeline(rec, field)
    local s = 0
    for i = 1, n do s = s + (list[i] or 0) end
    return s
end
F.Sum = Sum

-- The capture's gauge readings for one gauge id: { { t, value, cycle } } in order.
function F.GaugeSeries(rec, id)
    local idx
    for i, d in ipairs(rec.gauges and rec.gauges.defs or {}) do if d.id == id then idx = i break end end
    local out = {}
    if not idx then return out, nil end
    for _, s in ipairs(rec.gauges.samples or {}) do
        local v = s.v and s.v[idx]
        if v ~= nil then out[#out + 1] = { t = s.t, v = v, cycle = s.cycle } end
    end
    return out, rec.gauges.defs[idx]
end

local function Add(list, f)
    f.confidence = f.confidence or "measured"
    f.limits = f.limits or {}
    f.ids = f.ids or {}
    list[#list + 1] = f
end

---------------------------------------------------------------------------
-- Derived figures (computed from a finished capture, never stored in it): the findings use them, and so do the
-- exports, so a number means the same wherever it appears.
---------------------------------------------------------------------------
local function SecondsPer(rec) return (rec.timeline and rec.timeline.merged) or 1 end

-- The client's profiler and the instrumented work, side by side: where TwichUI's CPU went and how much of it is unaccounted for.
function F.CpuStats(rec)
    local tl = rec.timeline or {}
    local n = tl.n or 0
    local core, frames, work = Sum(rec, "core"), Sum(rec, "frames"), F.MeasuredWork(rec)
    local dur = rec.duration or 0
    local out = { available = (rec.config and rec.config.profiler) and true or false, coreMs = core, frames = frames, workMs = work, duration = dur }
    if not out.available then return out end
    out.perFrameMs = frames > 0 and core / frames or nil
    out.perSecondMs = dur > 0 and core / dur or nil
    out.unattributedMs = math.max(core - work, 0)
    out.workShare = core > 0 and math.min(work / core, 1) or nil
    -- the same, not capped: above 1 the scopes added up to more than the client counted (their own clock reads sit inside
    -- them, or the client's figure leaves some of it out), so instrumented times are upper bounds
    out.workRatio = core > 0 and work / core or nil
    out.overCounted = out.workRatio ~= nil and out.workRatio > 1.1
    out.unattributedPerSecond = dur > 0 and out.unattributedMs / dur or nil
    out.overallMs = Sum(rec, "all")
    out.shareOfAll = out.overallMs > 0 and core / out.overallMs or nil
    -- the shape over time: steady (spread over most seconds) or bursty (a few seconds hold it)
    if n > 0 and SecondsPer(rec) == 1 and tl.core then
        local list, active = {}, 0
        for i = 1, n do
            local ms = tl.core[i] or 0
            list[i] = { t = tl.t and tl.t[i] or (i - 1), ms = ms }
            if ms > 0 then active = active + 1 end
        end
        table.sort(list, function(a, b) if a.ms ~= b.ms then return a.ms > b.ms end return a.t < b.t end)
        out.busiest = {}
        for i = 1, math.min(3, #list) do if list[i].ms > 0 then out.busiest[i] = list[i] end end
        out.activeSeconds, out.seconds = active, n
        local k, top = math.max(1, math.ceil(n * 0.1)), 0
        for i = 1, k do top = top + list[i].ms end
        out.topTenthShare = core > 0 and top / core or nil
    end
    -- the client's own tick counts for the capture (differences of cumulative counters)
    local p = rec.profiler or {}
    local a, b = p.start and p.start.core, p.finish and p.finish.core
    if a and b then
        out.ticks = {}
        for _, key in ipairs({ "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms", "CountTimeOver50Ms", "CountTimeOver100Ms" }) do
            local d = (b[key] or 0) - (a[key] or 0)
            if d < 0 then out.ticksReset = true end
            out.ticks[key] = d
        end
        out.peakTime = b.PeakTime
    end
    return out
end

-- TwichUI's per-addon memory over the capture, the whole heap beside it, and what the scopes saw allocated.
function F.MemoryStats(rec)
    local vals = {}
    for _, m in ipairs(rec.memory or {}) do if m.core then vals[#vals + 1] = m end end
    local out = { readings = #vals }
    local dur = rec.duration or 0
    -- what the instrumented scopes allocated (self, so nothing counts twice): approximate, see Instrument.lua
    local self, top = 0, {}
    for _, op in ipairs(rec.ops or {}) do
        local a = op.allocSelfKB or 0
        self = self + a
        if a > 0 then top[#top + 1] = { id = op.id, kb = a, calls = op.calls, maxKB = op.allocMaxKB } end
    end
    table.sort(top, function(x, y) if x.kb ~= y.kb then return x.kb > y.kb end return x.id < y.id end)
    out.scopeAllocKB, out.topAllocators = self, { unpack(top, 1, 5) }
    out.scopeAllocPerSecond = dur > 0 and self / dur or nil
    if #vals == 0 then return out end
    local first, last = vals[1], vals[#vals]
    local min, peak, fallIdx, fallKB = first, first, nil, 0
    out.ups, out.downs, out.upKB, out.downKB = 0, 0, 0, 0
    for i = 2, #vals do
        local d = vals[i].core - vals[i - 1].core
        if d > 0 then out.ups = out.ups + 1; out.upKB = out.upKB + d
        elseif d < 0 then
            out.downs = out.downs + 1; out.downKB = out.downKB - d
            if -d > fallKB then fallKB, fallIdx = -d, i end
        end
        if vals[i].core < min.core then min = vals[i] end
        if vals[i].core > peak.core then peak = vals[i] end
    end
    out.first, out.last, out.min, out.peak = first, last, min, peak
    out.rise = last.core - first.core
    -- at the least this much was allocated between readings (a fall and a rise in one interval cancel: more may have been)
    out.allocatedAtLeastPerSecond = (last.t - first.t) > 0 and out.upKB / (last.t - first.t) or nil
    if fallIdx then
        local low = vals[fallIdx]
        for i = fallIdx, #vals do if vals[i].core < low.core then low = vals[i] end end
        out.afterFall = { t = vals[fallIdx].t, fell = fallKB, from = vals[fallIdx - 1].core, to = vals[fallIdx].core, lowest = low.core, lowestAt = low.t }
    end
    local function Series(field)
        local f, l, pk
        for _, m in ipairs(vals) do
            local v = m[field]
            if v then f = f or v; l = v; if not pk or v > pk then pk = v end end
        end
        if f then return { first = f, last = l, peak = pk } end
    end
    out.heap, out.diag, out.settings, out.navdata = Series("heap"), Series("diag"), Series("settings"), Series("navdata")
    out.layouts, out.layoutwizard = Series("layouts"), Series("layoutwizard")
    return out
end

-- The diagnostics' own cost, in three parts that don't overlap, against TwichUI's and against the capture.
function F.DiagnosticsCost(rec)
    local o = rec.overhead or {}
    local gauge, mem, scopes = o.gaugeMs or 0, o.memoryMs or 0, o.estimatedScopeMs or 0
    local sampler = o.samplerMs or 0
    if not o.exclusive then sampler = math.max(sampler - gauge - mem, 0) end   -- captures made before the sampler stopped counting its reads twice
    local own = sampler + gauge + mem + scopes
    local frames = Sum(rec, "frames")
    local core, work = Sum(rec, "core"), F.MeasuredWork(rec)
    local twichui = math.max(core, work)
    local client = Sum(rec, "diag")
    local out = { ownMs = own, samplerMs = sampler, gaugeMs = gauge, memoryMs = mem, scopeMs = scopes,
        memoryReads = o.memoryReads or 0, memoryWorstMs = o.memoryWorst, clientMs = client, twichuiMs = twichui,
        perFrameMs = frames > 0 and sampler / frames or nil,
        shareOfCapture = (rec.duration or 0) > 0 and own / ((rec.duration or 0) * 1000) or nil,
        ratio = twichui > 0 and own / twichui or nil }
    out.memoryMeanMs = out.memoryReads > 0 and mem / out.memoryReads or nil
    -- the client reports 0 for this addon although our own clock measured work: its figure is not "free"
    out.clientReportedNothing = (rec.config and rec.config.profiler) and client == 0 and own > 0 or false
    return out
end

-- What was happening: how long the map, settings window and diagnostics window were shown, combat, group, the frame rate.
function F.Context(rec)
    local tl = rec.timeline or {}
    local n, per = tl.n or 0, SecondsPer(rec)
    local function Count(field)
        local c, list = 0, tl[field] or {}
        for i = 1, n do if (list[i] or 0) > 0 then c = c + 1 end end
        return c * per
    end
    local out = { approx = per > 1 and true or nil, mapSeconds = Count("mapShown"), settingsSeconds = Count("settingsShown"),
        windowSeconds = Count("windowShown"), combatSeconds = Count("combat"), duration = rec.duration or 0,
        maxGroup = rec.maxGroup or 0, instance = rec.env and rec.env.instance }
    local kinds = {}
    for _, m in ipairs(rec.markers or {}) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
    out.zoneChanges, out.loadingScreens, out.combats = kinds["zone-changed"] or 0, kinds["loading-start"] or 0, kinds["combat-start"] or 0
    out.profileChanges = kinds["profile-changed"] or 0
    local fps = {}
    for i = 1, n do local v = tl.fps and tl.fps[i]; if v and v > 0 then fps[#fps + 1] = v end end
    if #fps > 0 then
        table.sort(fps)
        out.fpsMin, out.fpsMedian = fps[1], fps[math.ceil(#fps / 2)]
    end
    return out
end

local NEAR = { ["capture-start"] = true, ["capture-stop"] = true }
-- The long frames kept (longest first), each with the figures that say whose time it was and what marker was nearest.
function F.LongFrames(rec)
    local fr = rec.frames or {}
    local out = { total = fr.spikeCount or 0, kept = {}, ours = 0 }
    local spikeMs = (rec.config and rec.config.spikeMs) or 50
    local list = {}
    for _, sp in ipairs(fr.spikes or {}) do list[#list + 1] = sp end
    table.sort(list, function(a, b) if a.dt ~= b.dt then return a.dt > b.dt end return a.t < b.t end)
    for _, sp in ipairs(list) do
        local near, best
        for _, m in ipairs(rec.markers or {}) do
            if not NEAR[m.kind] then
                local d = math.abs(m.t - sp.t)
                if d <= 3 and (not best or d < best) then best, near = d, m end
            end
        end
        local ours = sp.diag and sp.diag >= 10 and (sp.dt - sp.diag) < spikeMs or false
        if ours then out.ours = out.ours + 1 end
        out.kept[#out.kept + 1] = { t = sp.t, dt = sp.dt, coreMs = sp.core, workMs = sp.work, top = sp.top, topMs = sp.topMs, combat = sp.combat,
            diagMs = sp.diag, diagReadMs = sp.diagRead, ours = ours or nil,
            nearMarker = near and near.kind or nil, nearSeconds = near and (near.t - sp.t) or nil,
            nearLabel = near and near.kind == "addon-loaded" and near.label or nil }
    end
    return out
end

---------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------
local rules = {}

-- One operation's inclusive time is most of all measured TwichUI work.
rules[#rules + 1] = function(rec, th, out)
    local work = F.MeasuredWork(rec)
    if work < 20 then return end   -- a few milliseconds in all has no dominant part worth naming
    for _, op in ipairs(rec.ops or {}) do
        local d = DX.Op(op.id)
        local share = op.total / work
        if share >= th.dominantShare and d.kind ~= "event" then
            local once = op.calls <= 2
            Add(out, {
                id = once and "single-expensive-call" or "dominant-operation", category = "cost",
                severity = (share >= 0.75 and op.total >= 50) and "high" or (once and "info" or "medium"),
                basis = ("its time is %s of all measured TwichUI work (threshold %s, prefs.thresholds.dominantShare)"):format(Pct(share), Pct(th.dominantShare)),
                title = once and ("A single %s dominated the capture: %s"):format(d.kind == "init" and "initialization" or "call", d.label)
                    or ("Most measured work was %s"):format(d.label),
                evidence = { ("%s: %d call(s), %s in all, %s at most, %s on average"):format(op.id, op.calls, Ms(op.total), Ms(op.max), Ms(op.mean)),
                    ("all measured TwichUI work: %s (self times added up)"):format(Ms(work)) },
                window = { op.first or 0, op.last or rec.duration },
                limits = { "Time inside uninstrumented code it calls is included; time in the game's own code is too.",
                    once and "A one-time cost (first open, first build) is expected to be large once; compare a second open." or "Share depends on what else was instrumented in this capture." },
                verify = once and "Repeat the same action in one capture: if the second time is far cheaper, this is a first-time cost."
                    or "Run a focused trace of this subsystem and look at the slowest calls' call paths.",
                ids = { op.id },
            })
            break
        end
    end
end

-- A rebuild or layout runs very often.
rules[#rules + 1] = function(rec, th, out)
    local mins = Minutes(rec)
    if (rec.duration or 0) < 30 then return end
    for _, op in ipairs(rec.ops or {}) do
        local d = DX.Op(op.id)
        if d.kind == "rebuild" or d.kind == "layout" then
            local rate = op.calls / mins
            if rate >= th.rebuildPerMin then
                Add(out, {
                    id = "frequent-rebuild", category = "frequency", severity = op.total / math.max(rec.duration, 1) >= 1 and "medium" or "low",
                    basis = ("%.0f per minute over the capture (threshold %d, prefs.thresholds.rebuildPerMin)"):format(rate, th.rebuildPerMin),
                    title = ("%s ran %.0f times a minute"):format(d.label, rate),
                    evidence = { ("%s: %d calls in %s; busiest 10 seconds: %d calls"):format(op.id, op.calls, DX.Clock2(rec.duration), op.peak10s or 0),
                        ("%s in all (%s per call on average, %s at most)"):format(Ms(op.total), Ms(op.mean), Ms(op.max)) },
                    window = { op.first or 0, op.last or rec.duration },
                    limits = { "Frequent is not wrong by itself: a layout per map change is expected. Cost per call matters as much as the count." },
                    verify = "Mark the moment you do the action that triggers it (/tui perf mark) and see whether calls follow each action or run without one.",
                    ids = { op.id },
                })
            end
        end
    end
end

-- One event's callbacks run very often.
rules[#rules + 1] = function(rec, th, out)
    local mins = Minutes(rec)
    if (rec.duration or 0) < 30 then return end
    for _, ev in ipairs(rec.events or {}) do
        local rate = ev.callbacks / mins
        if rate >= th.handlerPerMin then
            local per = ev.received > 0 and ev.callbacks / ev.received or 0
            Add(out, {
                id = "frequent-handler", category = "frequency", severity = ev.total / math.max(rec.duration, 1) >= 1 and "medium" or "low",
                basis = ("%.0f callbacks per minute (threshold %d, prefs.thresholds.handlerPerMin)"):format(rate, th.handlerPerMin),
                title = ("%s reached TwichUI's callbacks %.0f times a minute"):format(ev.event, rate),
                evidence = { ("%d events received, %d callbacks run (%.1f per event; up to %d listeners)"):format(ev.received, ev.callbacks, per, ev.maxListeners or 0),
                    ("%s in all in its callbacks, %s at most"):format(Ms(ev.total), Ms(ev.max)) },
                window = { 0, rec.duration },
                limits = { "The client decides how often it sends an event; one received event reaching several listeners is several callbacks.",
                    "Whether a callback did anything useful each time is not measured." },
                verify = "Compare with a capture where the feature listening for it is off, the same activity, same length.",
                ids = { "event:" .. ev.event },
            })
        end
    end
end

-- Listener counts rising over window cycles (settings or map opened and closed).
rules[#rules + 1] = function(rec, th, out)
    for _, def in ipairs(rec.gauges and rec.gauges.defs or {}) do
        if def.kind == "listeners" then
            local series = F.GaugeSeries(rec, def.id)
            local cycles = {}
            for _, s in ipairs(series) do if s.cycle then cycles[#cycles + 1] = s end end
            if #cycles >= 3 then
                local rises, falls = 0, 0
                for i = 2, #cycles do
                    if cycles[i].v > cycles[i - 1].v then rises = rises + 1 elseif cycles[i].v < cycles[i - 1].v then falls = falls + 1 end
                end
                local growth = cycles[#cycles].v - cycles[1].v
                if growth >= th.listenerGrowth and falls == 0 then
                    local vals = {}
                    for i = 1, math.min(#cycles, 8) do vals[i] = tostring(cycles[i].v) end
                    Add(out, {
                        id = "listener-growth", category = "lifecycle", severity = "medium", confidence = "suspicion",
                        basis = ("+%d across %d window cycles and never down (threshold %d, prefs.thresholds.listenerGrowth)"):format(growth, #cycles, th.listenerGrowth),
                        title = ("%s rose each time a window closed"):format(def.label),
                        evidence = { ("after each close: %s%s"):format(table.concat(vals, ", "), #cycles > 8 and ", ..." or ""),
                            ("rose after %d of %d closes"):format(rises, #cycles - 1) },
                        window = { cycles[1].t, cycles[#cycles].t },
                        limits = { "A feature turned on, or a page seen for the first time, can add a listener legitimately: this is a pattern, not a proven leak." },
                        verify = "Open and close the same window ten more times without changing anything else: a count that keeps rising is worth a look at what registers it.",
                        ids = { def.id },
                    })
                end
            end
        end
    end
end

-- A pool that grows at every cycle.
rules[#rules + 1] = function(rec, th, out)
    for _, def in ipairs(rec.gauges and rec.gauges.defs or {}) do
        if def.kind == "pool" and def.id:find("pool", 1, true) then
            local series = F.GaugeSeries(rec, def.id)
            local cycles = {}
            for _, s in ipairs(series) do if s.cycle then cycles[#cycles + 1] = s end end
            local grew = 0
            for i = 2, #cycles do if cycles[i].v > cycles[i - 1].v then grew = grew + 1 end end
            if #cycles >= 4 and grew >= #cycles - 1 then
                Add(out, {
                    id = "pool-growth", category = "lifecycle", severity = "low", confidence = "suspicion",
                    basis = ("larger after every one of %d window cycles"):format(#cycles - 1),
                    title = ("%s kept growing"):format(def.label),
                    evidence = { ("from %d to %d"):format(cycles[1].v, cycles[#cycles].v) },
                    window = { cycles[1].t, cycles[#cycles].t },
                    limits = { "A pool grows to the most ever shown at once; showing more each time (a bigger area of the map) grows it legitimately." },
                    verify = "Repeat with the same view each time: a pool that still grows is not being reused.",
                    ids = { def.id },
                })
            end
        end
    end
end

-- TwichUI's sampled memory rose over the capture.
rules[#rules + 1] = function(rec, th, out)
    local M = F.MemoryStats(rec)
    if (M.readings or 0) < 3 then return end
    if M.rise < th.memoryGrowthKB then return end
    if M.ups < (M.readings - 1) * 2 / 3 then return end
    local caches = {}
    for _, def in ipairs(rec.gauges and rec.gauges.defs or {}) do
        if def.kind == "cache" or def.kind == "pool" then
            local series = F.GaugeSeries(rec, def.id)
            if #series >= 2 and series[#series].v > series[1].v then
                caches[#caches + 1] = ("%s %d -> %d"):format(def.id, series[1].v, series[#series].v)
            end
        end
    end
    local evidence = {
        ("%.0f KB at %s, %.0f KB at %s; lowest %.0f KB, highest %.0f KB at %s (%d readings)"):format(M.first.core, DX.Clock2(M.first.t), M.last.core, DX.Clock2(M.last.t),
            M.min.core, M.peak.core, DX.Clock2(M.peak.t), M.readings),
        ("up in %d intervals (%.0f KB in all), down in %d (%.0f KB in all)%s"):format(M.ups, M.upKB, M.downs, M.downKB,
            M.allocatedAtLeastPerSecond and (": at least %.0f KB/s was allocated between readings"):format(M.allocatedAtLeastPerSecond) or ""),
    }
    if M.afterFall then
        evidence[#evidence + 1] = ("the largest fall was at %s (%.0f -> %.0f KB): the collector ran; the lowest reading from then on was %.0f KB, %+.0f KB against the first reading"):format(
            DX.Clock2(M.afterFall.t), M.afterFall.from, M.afterFall.to, M.afterFall.lowest, M.afterFall.lowest - M.first.core)
    else
        evidence[#evidence + 1] = "no fall between readings: the collector was not seen to free anything"
    end
    if M.scopeAllocKB > 0 then
        evidence[#evidence + 1] = ("the instrumented operations allocated about %.0f KB in all (%.1f KB/s; approximate): %s"):format(M.scopeAllocKB, M.scopeAllocPerSecond or 0,
            #M.topAllocators > 0 and (function()
                local t = {}
                for i, a in ipairs(M.topAllocators) do t[i] = ("%s %.0f KB"):format(a.id, a.kb) end
                return table.concat(t, ", ")
            end)() or "none")
    else
        evidence[#evidence + 1] = "no instrumented operation allocated anything measurable: the allocation is in code with no scope"
    end
    if #caches > 0 then evidence[#evidence + 1] = "counts that grew meanwhile (their size in KB is not measured): " .. table.concat(caches, "; ") end
    Add(out, {
        id = #caches > 0 and "memory-with-cache" or "memory-rose", category = "memory", severity = "low", confidence = "suspicion",
        basis = ("TwichUI's sampled memory rose %.0f KB and rose in %d of %d intervals (threshold %d KB, prefs.thresholds.memoryGrowthKB)"):format(M.rise, M.ups, M.readings - 1, th.memoryGrowthKB),
        title = #caches > 0 and "Memory rose while some caches or pools also grew (their sizes are not measured)" or "TwichUI's memory rose over the capture",
        evidence = evidence,
        window = { M.first.t, M.last.t },
        limits = { "The reading includes garbage not yet collected: where it ends depends on where the collector was; a fall in the series shows it ran.",
            "Net change is not how much was allocated; growth can be a cache warming up.", "Readings are sparse: peaks between them are not seen.",
            "The scopes' allocation is the Lua heap rising inside them: approximate, and it includes what the game's functions allocated there." },
        verify = "Memory and lifecycle capture of the same activity, then the garbage collection experiment once at the end: what it leaves is retained, the rest was garbage. Then a focused trace with allocation measuring on the subsystem named above.",
        ids = { "memory.core" },
    })
end

-- Work seen while the window it is for was closed (checked on the slowest calls kept).
rules[#rules + 1] = function(rec, th, out)
    local FIELD = { ["map.open"] = "mapShown", ["settings.shown"] = "settingsShown" }
    -- the markers that say a window opened or closed: a call this close to one is the second the window changed, not hidden work
    local EDGES = { ["map.open"] = { ["map-shown"] = true, ["map-hidden"] = true },
        ["settings.shown"] = { ["settings-shown"] = true, ["settings-hidden"] = true, ["settings-closed"] = true } }
    local EDGE_SECONDS = 2
    local function AtEdge(visible, at)
        local kinds = EDGES[visible]
        if not kinds then return false end
        for _, m in ipairs(rec.markers or {}) do
            if kinds[m.kind] and math.abs(m.t - at) <= EDGE_SECONDS then return true end
        end
        return false
    end
    local tl = rec.timeline
    if not tl then return end
    for _, op in ipairs(rec.ops or {}) do
        local d = DX.Op(op.id)
        local field = d.visible and FIELD[d.visible]
        if field then
            local hidden = {}
            for _, e in ipairs(op.exemplars or {}) do
                local i = math.floor(e.at) + 1
                if tl[field][i] == 0 and not AtEdge(d.visible, e.at) then hidden[#hidden + 1] = ("%s at %s"):format(Ms(e.ms), DX.Clock2(e.at)) end
            end
            if #hidden > 0 then
                Add(out, {
                    id = "hidden-work", category = "lifecycle", severity = "low", confidence = "correlated",
                    basis = "a slow call happened in a second when the window it draws was sampled as closed",
                    title = ("%s ran while its window looked closed"):format(d.label),
                    evidence = { table.concat(hidden, "; "), ("checked: the %d slowest calls kept"):format(#(op.exemplars or {})) },
                    window = { 0, rec.duration },
                    limits = { "Shown or not is read once a second, so a call in the second a window opened or closed can look hidden; calls within 2 s of that window's own opened or closed marker are left out." },
                    verify = "Mark when you close the window and look at the operation's calls after the marker.",
                    ids = { op.id, d.visible },
                })
            end
        end
    end
end

-- Long frames, and whether TwichUI's own time was in them.
rules[#rules + 1] = function(rec, th, out)
    local fr = rec.frames or {}
    local spikes = fr.spikes or {}
    if (fr.spikeCount or 0) == 0 then return end
    local with, lines = 0, {}
    for _, sp in ipairs(spikes) do
        local twich = math.max(sp.core or 0, sp.work or 0)
        if twich >= sp.dt * 0.5 then
            with = with + 1
            if #lines < 3 then
                lines[#lines + 1] = ("%s: a %s frame; TwichUI %s by the client's count, %s instrumented%s"):format(DX.Clock2(sp.t), Ms(sp.dt),
                    sp.core and Ms(sp.core) or "n/a", Ms(sp.work), sp.top and (" (mostly " .. sp.top .. ")") or "")
            end
        end
    end
    local LF = F.LongFrames(rec)
    if with > 0 then
        Add(out, {
            id = "long-frames-with-twichui", category = "frames", severity = with >= 3 and "medium" or "low", confidence = "correlated",
            basis = ("in %d of the %d long frames kept, TwichUI's time was at least half the frame (long: %d ms or more, prefs.spikeMs)"):format(with, #spikes, rec.config.spikeMs),
            title = ("TwichUI's work coincided with %d long frame(s)"):format(with),
            evidence = lines,
            window = { spikes[1].t, spikes[#spikes].t },
            limits = { "The client's per-tick figure is for its latest tick, read at the next frame: it may belong to the frame before.",
                "Instrumented work is what ended between two frames; it is the stronger link when it is large." },
            verify = "Select the long frame on the Timeline and look at the operation named; run a focused trace of its subsystem.",
            ids = {},
        })
    else
        local longest = 0
        for _, s in ipairs(spikes) do if s.dt > longest then longest = s.dt end end
        local evidence = { ("longest kept: %s"):format(Ms(longest > 0 and longest or nil)) }
        for i = 1, math.min(3, #LF.kept) do
            local k = LF.kept[i]
            evidence[#evidence + 1] = ("%s: %s frame; TwichUI %s by the client's count, %s instrumented; %s%s"):format(DX.Clock2(k.t), Ms(k.dt), k.coreMs and Ms(k.coreMs) or "n/a", Ms(k.workMs),
                k.diagMs and ("the diagnostics' previous frame %s"):format(Ms(k.diagMs)) or "no diagnostics figure",
                k.nearMarker and ("; nearest marker: " .. k.nearMarker .. (k.nearLabel and (" " .. k.nearLabel) or "") .. (" (%+.1f s)"):format(k.nearSeconds)) or "; no marker within 3 s")
        end
        Add(out, {
            id = "long-frames-unattributed", category = "frames", severity = "info", confidence = "measured",
            basis = "no long frame kept had TwichUI time of half the frame or more",
            title = ("%d long frame(s) without much measured TwichUI work"):format(fr.spikeCount),
            evidence = evidence,
            window = { 0, rec.duration },
            limits = { "Something else made these frames long (the game, another addon, the system); this capture can't say what." },
            verify = "Nothing to verify for TwichUI; the client's addon list shows other addons' profiler figures. To learn what the hitches follow, repeat with /tui perf mark each time you notice one.",
            ids = {},
        })
    end
    -- frames the diagnostics' own work (a memory update, a gauge read) lifted over the limit
    if LF.ours > 0 then
        local lines2 = {}
        for _, k in ipairs(LF.kept) do
            if k.ours and #lines2 < 3 then
                lines2[#lines2 + 1] = ("%s: a %s frame, of which the diagnostics' previous frame was %s (reads in it: %s); without it %s"):format(DX.Clock2(k.t), Ms(k.dt), Ms(k.diagMs), Ms(k.diagReadMs), Ms(k.dt - k.diagMs))
            end
        end
        Add(out, {
            id = "long-frames-from-diagnostics", category = "coverage", severity = "medium", confidence = "correlated",
            basis = ("%d long frame(s) came right after a frame in which the diagnostics worked 10 ms or more, and would be under %d ms without it"):format(LF.ours, rec.config.spikeMs),
            title = ("%d long frame(s) were probably made by the diagnostics' own memory or gauge read"):format(LF.ours),
            evidence = lines2,
            window = { 0, rec.duration },
            limits = { "A frame's interval includes the previous frame's script time; the match is by timing, not proof." },
            verify = "Record again with a preset that reads memory less often (Group combat reads it every 30 seconds); these frames should not recur.",
            ids = {},
        })
    end
end

-- The client's own counts of ticks in which TwichUI's time went over 5 or 50 ms.
rules[#rules + 1] = function(rec, th, out)
    local p = rec.profiler or {}
    local a, b = p.start and p.start.core, p.finish and p.finish.core
    if not (a and b) then return end
    local d5 = (b.CountTimeOver5Ms or 0) - (a.CountTimeOver5Ms or 0)
    local d50 = (b.CountTimeOver50Ms or 0) - (a.CountTimeOver50Ms or 0)
    if d5 < 0 or d50 < 0 then
        Add(out, { id = "profiler-reset", category = "coverage", severity = "info", title = "The client's profiler counters went down during the capture",
            basis = "a cumulative counter decreased", evidence = { ("over 5 ms: %d -> %d"):format(a.CountTimeOver5Ms or 0, b.CountTimeOver5Ms or 0) },
            window = { 0, rec.duration }, limits = { "Something reset them; their differences for this capture are not used." },
            verify = "Record again without resetting anything.", ids = {} })
        return
    end
    if d5 == 0 then return end
    Add(out, {
        id = "profiler-over-5ms", category = "cost", severity = d50 > 0 and "high" or (d5 > 3 and "medium" or "low"), confidence = "measured",
        basis = "the client counted ticks in which TwichUI's time went over 5 ms (and over 50 ms)",
        title = ("The client counted %d tick(s) with over 5 ms of TwichUI time%s"):format(d5, d50 > 0 and (", " .. d50 .. " over 50 ms") or ""),
        evidence = { ("CountTimeOver5Ms +%d, CountTimeOver50Ms +%d for %s during the capture"):format(d5, d50, DX.CORE) },
        window = { 0, rec.duration },
        limits = { "The client's counters are for the whole addon: they don't say which part of TwichUI." },
        verify = "Look at the long frames and the operations' slowest calls for the same moments.",
        ids = {},
    })
end

-- The diagnostics' own cost against what it measured (three parts that don't overlap: see F.DiagnosticsCost).
rules[#rules + 1] = function(rec, th, out)
    local d = F.DiagnosticsCost(rec)
    if not d.ratio or d.ratio < th.overheadShare then return end
    local frameMed = rec.frames and rec.frames.p50
    local spikeMs = (rec.config and rec.config.spikeMs) or 50
    local heavy = (d.shareOfCapture or 0) >= 0.02 or (d.memoryWorstMs or 0) >= spikeMs
        or (d.perFrameMs and frameMed and d.perFrameMs >= frameMed * 0.05) or false
    local client = d.clientReportedNothing and ("the client reported nothing for %s (0 ms) although this addon's own clock measured %s: do not read that as free"):format(DX.ADDON, Ms(d.ownMs))
        or ("client's count for %s: %s; for %s: %s"):format(DX.ADDON, Ms(d.clientMs), DX.CORE, Ms(Sum(rec, "core")))
    Add(out, {
        id = "diagnostics-overhead", category = "coverage", severity = heavy and "medium" or "low",
        basis = ("the diagnostics' own time is %s of TwichUI's measured time (threshold %s, prefs.thresholds.overheadShare)"):format(Pct(d.ratio), Pct(th.overheadShare)),
        title = heavy and "Diagnostics overhead may have distorted results"
            or "The diagnostics cost more than TwichUI did, but little next to a frame",
        evidence = {
            ("own time %s in all (%s of the capture): sampling %s (%s a frame), gauge reads %s, memory updates %s (%d, %s on average, the worst %s), scopes about %s"):format(
                Ms(d.ownMs), d.shareOfCapture and ("%.2f%%"):format(d.shareOfCapture * 100) or "n/a", Ms(d.samplerMs),
                d.perFrameMs and ("%.0f µs"):format(d.perFrameMs * 1000) or "n/a", Ms(d.gaugeMs), Ms(d.memoryMs), d.memoryReads, Ms(d.memoryMeanMs), Ms(d.memoryWorstMs), Ms(d.scopeMs)),
            client },
        window = { 0, rec.duration },
        limits = { "Memory updates are costly for every addon, not only TwichUI; the client puts them on this addon.",
            "When TwichUI's own time is small, any measuring tool looks large beside it: the absolute figures (per frame, per memory read) are what matter.",
            "The three parts are timed with our own clock and do not overlap; the client's count for this addon is shown only as a cross-check." },
        verify = "Record again with a preset that reads memory less often (Group combat reads it every 30 seconds).",
        ids = {},
    })
end

-- TwichUI's CPU by the client's count, against what the instrumented operations account for.
rules[#rules + 1] = function(rec, th, out)
    local C = F.CpuStats(rec)
    if not C.available or C.coreMs <= 0 or (rec.duration or 0) < 10 then return end
    if not C.workShare or C.workShare >= 0.5 then return end
    local per = C.unattributedPerSecond or 0
    local severity = per >= th.unattributedPerSec * 5 and "medium" or (per >= th.unattributedPerSec and "low" or "info")
    local evidence = {
        ("the client counted %s for TwichUI (%s a frame, %s a second); the instrumented operations account for %s of it (%s)"):format(Ms(C.coreMs),
            Ms(C.perFrameMs), Ms(C.perSecondMs), Pct(C.workShare), Ms(C.workMs)),
        ("outside every scope: %s (%s a second)"):format(Ms(C.unattributedMs), Ms(per)),
    }
    if C.activeSeconds and C.seconds then
        local shape = (C.topTenthShare or 0) >= 0.5 and "bursty (half or more in a tenth of the seconds)" or "spread over the capture"
        evidence[#evidence + 1] = ("TwichUI had CPU in %d of %d seconds; the busiest tenth of the seconds held %s of it: %s"):format(C.activeSeconds, C.seconds, Pct(C.topTenthShare or 0), shape)
        if C.busiest and C.busiest[1] then
            local t = {}
            for i, b in ipairs(C.busiest) do t[i] = ("%s at %s"):format(Ms(b.ms), DX.Clock2(b.t)) end
            evidence[#evidence + 1] = "busiest seconds by the client's count: " .. table.concat(t, "; ")
        end
    end
    Add(out, {
        id = "unattributed-cpu", category = "coverage", severity = severity, confidence = "measured",
        basis = ("%s of TwichUI's CPU is outside every instrumented operation; %s a second (threshold %s a second, prefs.thresholds.unattributedPerSec)"):format(
            Pct(1 - C.workShare), Ms(per), tostring(th.unattributedPerSec)),
        title = ("Most of TwichUI's CPU (%s) ran in code with no scope"):format(Pct(1 - C.workShare)),
        evidence = evidence,
        window = { 0, rec.duration },
        limits = { "The client's figure counts every TwichUI script: per-frame updaters, hooks into other addons' code, frames' own event handlers and timers, none of which is timed unless it has a scope.",
            "A steady spread over most seconds points to a per-frame or timed updater; a few busy seconds point to events or one-off work.",
            "A small figure is small: this says where to add measurement, not that anything is wrong." },
        verify = "Focused trace of 'Per-frame updaters' and of 'Hooks and private event frames' (both have scopes now), doing what the capture did. If most of the CPU is still unattributed, the code is in DX.UNSCOPED's list: a scope is added there next.",
        ids = {},
    })
end

-- Errors seen during the capture.
rules[#rules + 1] = function(rec, th, out)
    if (rec.errorCount or 0) == 0 then return end
    local blocked = 0
    for _, e in ipairs(rec.errors or {}) do if e.kind == "blocked" or e.kind == "forbidden" then blocked = blocked + e.n end end
    local lines = {}
    for i = 1, math.min(3, #(rec.errors or {})) do
        local e = rec.errors[i]
        lines[i] = ("%s %s: %s (x%d, first at %s)"):format(e.kind, e.source, e.text, e.n, DX.Clock2(e.first))
    end
    Add(out, {
        id = blocked > 0 and "blocked-actions" or "errors-seen", category = "errors", severity = blocked > 0 and "high" or "medium",
        basis = blocked > 0 and "the client blocked an action it attributed to TwichUI" or "TwichUI's own handlers caught errors",
        title = ("%d error(s) observed during the capture"):format(rec.errorCount), evidence = lines,
        window = { 0, rec.duration },
        limits = { "An error near a long frame is not shown to be its cause.", "Errors in timers and frame scripts are not seen here; the game's error display shows them." },
        verify = "Turn on Display Lua Errors and repeat; the error's full text and call path are there.",
        ids = {},
    })
end

-- What limits the whole capture.
rules[#rules + 1] = function(rec, th, out)
    local lines = {}
    if (rec.duration or 0) < th.minSeconds then lines[#lines + 1] = ("only %s long (prefs.thresholds.minSeconds is %d s)"):format(DX.Clock2(rec.duration), th.minSeconds) end
    local fr = rec.frames or {}
    if #(fr.gaps or {}) > 0 then lines[#lines + 1] = ("%d discontinuities (loading screens or pauses) left out of the frame figures"):format(#fr.gaps + (fr.gapsDropped or 0)) end
    local an = rec.anomalies or {}
    if (an.aborted or 0) + (an.clockBack or 0) + (an.crossedFrame or 0) > 0 then
        lines[#lines + 1] = ("%d scope(s) never stopped (an error went through them), %d clock step(s) back, %d crossing a frame: their times are not used"):format(an.aborted or 0, an.clockBack or 0, an.crossedFrame or 0)
    end
    local cut = {}
    for k, v in pairs(rec.truncated or {}) do if v then cut[#cut + 1] = k end end
    table.sort(cut)
    if #cut > 0 then lines[#lines + 1] = "limits reached (oldest or smallest dropped and counted): " .. table.concat(cut, ", ") end
    if rec.gcExperiment then lines[#lines + 1] = "a garbage collection experiment ran during this capture: memory readings after it are not comparable" end
    if not (rec.config and rec.config.profiler) then lines[#lines + 1] = "the client's profiler was not available: no per-frame TwichUI CPU figures" end
    if #lines == 0 then return end
    Add(out, {
        id = "coverage", category = "coverage", severity = "info", basis = "what this capture could and couldn't record",
        title = "What limits this capture", evidence = lines, window = { 0, rec.duration },
        limits = {}, verify = "Record again for longer, or without the condition named.", ids = {},
    })
end

function F.Run(rec)
    local th = DX.prefs.thresholds
    local out = {}
    for _, rule in ipairs(rules) do
        local ok, err = pcall(rule, rec, th, out)
        if not ok then R.Fault("diagnostics finding", err) end
    end
    for i, f in ipairs(out) do f.order = i end
    table.sort(out, function(a, b)
        if RANK[a.severity] ~= RANK[b.severity] then return RANK[a.severity] < RANK[b.severity] end
        return a.order < b.order
    end)
    return out
end

-- What this capture can't tell you, whatever it shows: for the overview and every export.
function F.CannotConclude(rec)
    local out = {
        "Low frame rates alone don't show TwichUI caused them; the frames' own TwichUI time is the evidence.",
        "The client's per-addon CPU and memory are for the whole addon; operation timings are the only per-part figures.",
        "Per-addon memory includes uncollected garbage; it is not what any one feature keeps.",
    }
    if (rec.duration or 0) < 120 then out[#out + 1] = "A short capture says little about rates; compare captures of the same length and activity." end
    if not (rec.config and rec.config.stacks) then out[#out + 1] = "No call paths were taken (a focused trace takes them for the slowest calls)." end
    return out
end

---------------------------------------------------------------------------
-- What was checked and found clear, and what to record next
---------------------------------------------------------------------------
local function Has(findings, id)
    for _, f in ipairs(findings or {}) do if f.id == id then return true end end
    return false
end

-- Lines saying a check ran and found nothing, so silence in the findings can't be taken for "not looked at".
function F.Clear(rec, cpu, mem)
    local out = {}
    local fs = rec.findings or {}
    if cpu and cpu.ticks and not cpu.ticksReset then
        local t = cpu.ticks
        if (t.CountTimeOver5Ms or 0) == 0 then out[#out + 1] = "the client counted no tick over 5 ms for TwichUI" .. (cpu.peakTime and (" (its peak single tick since the client started: %s)"):format(Ms(cpu.peakTime)) or "") end
    end
    if (rec.errorCount or 0) == 0 then out[#out + 1] = "no error reached TwichUI's handlers, no action was blocked, no Lua warning named a TwichUI file" end
    local an = rec.anomalies or {}
    if (rec.scopeCalls or 0) > 0 and (an.aborted or 0) + (an.clockBack or 0) + (an.crossedFrame or 0) == 0 then out[#out + 1] = "every scope that started also stopped (none aborted, no clock step back)" end
    if #(rec.frames and rec.frames.gaps or {}) == 0 then out[#out + 1] = "no discontinuity (loading screen, pause) in the frame figures" end
    if not Has(fs, "listener-growth") and not Has(fs, "pool-growth") then
        local cycles = 0
        for _, n in pairs(rec.gauges and rec.gauges.cycles or {}) do cycles = cycles + n end
        if cycles >= 3 then out[#out + 1] = ("listener and pool counts did not keep rising across %d window cycles"):format(cycles) end
    end
    if not Has(fs, "frequent-rebuild") and not Has(fs, "frequent-handler") then out[#out + 1] = "no rebuild, layout or event handler ran at an alarming rate (thresholds in prefs.thresholds)" end
    if not Has(fs, "dominant-operation") and not Has(fs, "single-expensive-call") and F.MeasuredWork(rec) > 0 then out[#out + 1] = "no single operation held half of the measured work" end
    if mem and (mem.readings or 0) >= 3 and not Has(fs, "memory-rose") and not Has(fs, "memory-with-cache") then
        out[#out + 1] = ("TwichUI's memory did not rise by the threshold with a steady climb (%+.0f KB over %d readings)"):format(mem.rise or 0, mem.readings)
    end
    return out
end

-- Captures worth recording next, each with what to do and why; the smallest set that would settle what this one left open.
function F.Next(rec, cpu, mem)
    local fs = rec.findings or {}
    local out = {}
    local function Want(preset, subsystem, minutes, doing, why)
        for _, n in ipairs(out) do   -- one capture can settle two questions: say both, once
            if n.preset == preset and n.subsystem == subsystem then
                n.doing, n.why, n.minutes = n.doing .. "; also " .. doing, n.why .. "; and " .. why, math.max(n.minutes, minutes)
                return
            end
        end
        out[#out + 1] = { preset = preset, subsystem = subsystem, minutes = minutes, doing = doing, why = why }
    end
    if (rec.duration or 0) < 60 then
        Want(rec.preset, rec.subsystem, 5, "the same activity for at least five minutes", "this capture was too short to say anything about rates")
    end
    if Has(fs, "unattributed-cpu") then
        local seen = {}
        for _, op in ipairs(rec.ops or {}) do
            local d = DX.Op(op.id)
            if d.kind == "update" or d.kind == "hook" then seen[#seen + 1] = op.id end
        end
        if #seen == 0 then
            Want("focused", "updaters", 3, "play normally in the open world with the minimap in view, then repeat with the world map open", "most CPU was outside every scope and none of the updaters' scopes ran: their features may have been off, or they are not where the time went")
            Want("focused", "hooks", 3, "play with RestedXP's guide visible, targeting and fighting if you can", "the hooks and private event frames have scopes now and none ran in this capture")
        else
            Want("general", nil, 5, "the same play as this capture", "scopes for updaters and hooks ran (" .. table.concat(seen, ", ", 1, math.min(#seen, 4)) .. ") and most CPU is still outside them: the next step is a scope in the code listed under 'Code with no scope yet', not another capture")
        end
    end
    if Has(fs, "memory-rose") or Has(fs, "memory-with-cache") then
        Want("memory", nil, 10, "repeat one thing five or six times (open and close the map, or the settings), do nothing for a minute, then run the Garbage collection experiment once (Overview, Advanced)", "separates garbage the collector frees from memory TwichUI keeps")
        if mem and (mem.scopeAllocKB or 0) <= 0 then
            Want("focused", "updaters", 3, "play normally; tick the allocation checkbox (also measure each scoped call's allocation)", "no instrumented operation accounted for the allocation: this measures bytes per call for the updaters")
        end
    end
    if Has(fs, "long-frames-unattributed") or Has(fs, "long-frames-with-twichui") then
        Want("general", nil, 10, "play normally and press Marker (or /tui perf mark) each time you notice a hitch", "long frames need the moment they happened to be tied to an action")
    end
    local heavy = false
    for _, f in ipairs(fs) do if f.id == "diagnostics-overhead" and f.severity ~= "low" then heavy = true end end
    if Has(fs, "long-frames-from-diagnostics") or heavy then
        Want("group", nil, 5, "the same play", "reads memory every 30 seconds instead of more often, so the diagnostics' own hitches are fewer")
    end
    return out
end

-- Everything the exports add beyond the findings, in one place so the summary and the full report agree.
function F.Analyze(rec)
    local cpu, mem = F.CpuStats(rec), F.MemoryStats(rec)
    return { cpu = cpu, memory = mem, context = F.Context(rec), diagnostics = F.DiagnosticsCost(rec), longFrames = F.LongFrames(rec),
        clear = F.Clear(rec, cpu, mem), next = F.Next(rec, cpu, mem) }
end
