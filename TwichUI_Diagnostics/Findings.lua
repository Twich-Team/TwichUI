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
-- The rules
---------------------------------------------------------------------------
local rules = {}

-- One operation's inclusive time is most of all measured TwichUI work.
rules[#rules + 1] = function(rec, th, out)
    local work = F.MeasuredWork(rec)
    if work < 5 then return end
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

-- TwichUI's sampled memory rose, together with a cache.
rules[#rules + 1] = function(rec, th, out)
    local mem = rec.memory or {}
    local vals = {}
    for _, m in ipairs(mem) do if m.core then vals[#vals + 1] = m end end
    if #vals < 3 then return end
    local first, last = vals[1], vals[#vals]
    local rise = last.core - first.core
    if rise < th.memoryGrowthKB then return end
    local ups = 0
    for i = 2, #vals do if vals[i].core > vals[i - 1].core then ups = ups + 1 end end
    if ups < (#vals - 1) * 2 / 3 then return end
    local caches = {}
    for _, def in ipairs(rec.gauges and rec.gauges.defs or {}) do
        if def.kind == "cache" or def.kind == "pool" then
            local series = F.GaugeSeries(rec, def.id)
            if #series >= 2 and series[#series].v > series[1].v then
                caches[#caches + 1] = ("%s %d -> %d"):format(def.id, series[1].v, series[#series].v)
            end
        end
    end
    local peak = 0
    for _, m in ipairs(vals) do if m.core > peak then peak = m.core end end
    Add(out, {
        id = #caches > 0 and "memory-with-cache" or "memory-rose", category = "memory", severity = "low", confidence = "suspicion",
        basis = ("TwichUI's sampled memory rose %.0f KB and rose in %d of %d intervals (threshold %d KB, prefs.thresholds.memoryGrowthKB)"):format(rise, ups, #vals - 1, th.memoryGrowthKB),
        title = #caches > 0 and "Memory rose while a cache or pool also grew" or "TwichUI's memory rose over the capture",
        evidence = { ("%.0f KB at %s, %.0f KB at %s, highest reading %.0f KB (%d readings)"):format(first.core, DX.Clock2(first.t), last.core, DX.Clock2(last.t), peak, #vals),
            #caches > 0 and ("grew meanwhile: " .. table.concat(caches, "; ")) or "no cache or pool gauge grew meanwhile" },
        window = { first.t, last.t },
        limits = { "The reading includes garbage not yet collected: a rise may be gone after the next collection.",
            "Net change is not how much was allocated; growth can be a cache warming up.", "Readings are sparse: peaks between them are not seen." },
        verify = "Repeat the same action in a Memory and lifecycle capture; if memory keeps climbing after several cycles, run the garbage collection experiment once at the end and compare.",
        ids = { "memory.core" },
    })
end

-- Work seen while the window it is for was closed (checked on the slowest calls kept).
rules[#rules + 1] = function(rec, th, out)
    local FIELD = { ["map.open"] = "mapShown", ["settings.shown"] = "settingsShown" }
    local tl = rec.timeline
    if not tl then return end
    for _, op in ipairs(rec.ops or {}) do
        local d = DX.Op(op.id)
        local field = d.visible and FIELD[d.visible]
        if field then
            local hidden = {}
            for _, e in ipairs(op.exemplars or {}) do
                local i = math.floor(e.at) + 1
                if tl[field][i] == 0 then hidden[#hidden + 1] = ("%s at %s"):format(Ms(e.ms), DX.Clock2(e.at)) end
            end
            if #hidden > 0 then
                Add(out, {
                    id = "hidden-work", category = "lifecycle", severity = "low", confidence = "correlated",
                    basis = "a slow call happened in a second when the window it draws was sampled as closed",
                    title = ("%s ran while its window looked closed"):format(d.label),
                    evidence = { table.concat(hidden, "; "), ("checked: the %d slowest calls kept"):format(#(op.exemplars or {})) },
                    window = { 0, rec.duration },
                    limits = { "Shown or not is read once a second, so a call in the second a window opened or closed can look hidden." },
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
        Add(out, {
            id = "long-frames-unattributed", category = "frames", severity = "info", confidence = "measured",
            basis = "no long frame kept had TwichUI time of half the frame or more",
            title = ("%d long frame(s) without much measured TwichUI work"):format(fr.spikeCount),
            evidence = { ("longest kept: %s"):format(Ms(spikes[1] and (function() local m = 0 for _, s in ipairs(spikes) do if s.dt > m then m = s.dt end end return m end)() or nil)) },
            window = { 0, rec.duration },
            limits = { "Something else made these frames long (the game, another addon, the system); this capture can't say what." },
            verify = "Nothing to verify for TwichUI; the client's addon list shows other addons' profiler figures.",
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

-- The diagnostics' own cost against what it measured.
rules[#rules + 1] = function(rec, th, out)
    local core = Sum(rec, "core")
    local diag = Sum(rec, "diag")
    local o = rec.overhead or {}
    local own = (o.samplerMs or 0) + (o.gaugeMs or 0) + (o.memoryMs or 0) + (o.estimatedScopeMs or 0)
    local measured = math.max(core, F.MeasuredWork(rec))
    if measured <= 0 then return end
    local share = math.max(diag, own) / measured
    if share >= th.overheadShare then
        Add(out, {
            id = "diagnostics-overhead", category = "coverage", severity = "medium",
            basis = ("the diagnostics' own time is %s of TwichUI's measured time (threshold %s, prefs.thresholds.overheadShare)"):format(Pct(share), Pct(th.overheadShare)),
            title = "Diagnostics overhead may have distorted results",
            evidence = { ("client's count for %s: %s; for %s: %s"):format(DX.ADDON, Ms(diag), DX.CORE, Ms(core)),
                ("sampling %s, gauges %s, memory updates %s (%d, the worst %s), scopes about %s"):format(Ms(o.samplerMs), Ms(o.gaugeMs), Ms(o.memoryMs),
                    o.memoryReads or 0, Ms(o.memoryWorst), Ms(o.estimatedScopeMs)) },
            window = { 0, rec.duration },
            limits = { "Memory updates are costly for every addon, not only TwichUI; the client puts them on this addon." },
            verify = "Record again with a preset that reads memory less often (Group combat reads it every 30 seconds).",
            ids = {},
        })
    end
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
