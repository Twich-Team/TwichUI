-- TwichUI Diagnostics: comparing two captures
-- A (the baseline) against B. Totals of captures of different lengths mean nothing side by side, so every row is a rate
-- or a per-call figure, with its denominator named: per minute of capture, per frame, per call. Each row keeps the raw
-- difference beside the percentage; a percentage from a zero baseline is not given ("new" instead), and a figure from
-- too few calls or too short a capture says so instead of a number. Words are "lower" and "higher", never "faster".
--
-- Compatibility: things that make the two not comparable are warnings (or, for a different report layout, a refusal);
-- different TwichUI switches are expected when you compare a feature on and off, and are listed, not refused.

local R = TwichUI
local DX = R.DiagnosticsKit
local F = DX.Findings
local CMP = {}
DX.Compare = CMP

CMP.MIN_CALLS = 20       -- fewer calls than this in either capture: per-call figures are not compared
CMP.MIN_SECONDS = 30

local function Minutes(rec) return math.max(rec.duration or 0, 1) / 60 end

local function CombatShare(rec)
    local tl = rec.timeline
    if not tl or tl.n == 0 then return 0 end
    local n = 0
    for i = 1, tl.n do if (tl.combat[i] or 0) > 0 then n = n + 1 end end
    return n / tl.n
end

local function Version(rec)
    for _, a in ipairs(rec.env and rec.env.addons or {}) do if a.name == DX.CORE then return a.version end end
    return nil
end

local function Set(list) local s = {} for _, k in ipairs(list or {}) do s[k] = true end return s end

function CMP.Check(a, b)
    local warnings, notes = {}, {}
    if a.schema ~= b.schema then return false, { "These captures were made by different versions of TwichUI Diagnostics' report layout and can't be compared." }, notes end
    local function W(text) warnings[#warnings + 1] = text end
    if (a.env and a.env.build) ~= (b.env and b.env.build) then W(("Different client builds (%s and %s)."):format(tostring(a.env.build), tostring(b.env.build))) end
    if Version(a) ~= Version(b) then notes[#notes + 1] = ("Different TwichUI versions (%s and %s)."):format(tostring(Version(a)), tostring(Version(b))) end
    if a.preset ~= b.preset or a.mode ~= b.mode or a.subsystem ~= b.subsystem then W(("Different presets (%s and %s): different things were timed."):format(a.presetName, b.presetName)) end
    local pa, pb = a.config and a.config.profiler, b.config and b.config.profiler
    if pa ~= pb then W("The client's profiler was available in only one of them: its rows are left out.") end
    local da, db = a.duration or 0, b.duration or 0
    if math.min(da, db) < CMP.MIN_SECONDS then W(("At least one capture is under %d seconds: too short for rates."):format(CMP.MIN_SECONDS)) end
    if math.max(da, db) > 2 * math.max(1, math.min(da, db)) then W(("Lengths differ a lot (%s and %s): rows are per minute, but rare events may only be in the longer one."):format(DX.Clock2(da), DX.Clock2(db))) end
    if (a.maxGroup or 0) ~= (b.maxGroup or 0) then W(("Different group sizes (at most %d and %d)."):format(a.maxGroup or 0, b.maxGroup or 0)) end
    local ca, cb = CombatShare(a), CombatShare(b)
    if math.abs(ca - cb) > 0.25 then W(("Different time in combat (%.0f%% and %.0f%%)."):format(ca * 100, cb * 100)) end
    local fa, fb = a.config or {}, b.config or {}
    if (fa.stacks ~= fb.stacks) or (fa.allocation ~= fb.allocation) then W("Different instrumentation settings (call paths or allocation): the diagnostics' own cost differs.") end
    if a.gcExperiment or b.gcExperiment then W("A garbage collection experiment ran in one of them: memory rows are not comparable.") end
    if (a.env and a.env.configFingerprint) ~= (b.env and b.env.configFingerprint) then
        local sa, sb = Set(a.env.modulesOn), Set(b.env.modulesOn)
        local only = {}
        for k in pairs(sa) do if not sb[k] then only[#only + 1] = "A only: " .. k end end
        for k in pairs(sb) do if not sa[k] then only[#only + 1] = "B only: " .. k end end
        table.sort(only)
        notes[#notes + 1] = "Different TwichUI switches (expected when comparing a feature on and off): " .. (#only > 0 and table.concat(only, ", ") or "the same switches on, other settings differ")
    end
    return true, warnings, notes
end

local function Row(rows, metric, unit, denom, va, vb, note)
    local r = { metric = metric, unit = unit, denominator = denom, a = va, b = vb, note = note }
    if va ~= nil and vb ~= nil then
        r.delta = vb - va
        if va ~= 0 then r.pct = (vb - va) / math.abs(va)
        elseif vb ~= 0 then r.change = "new" else r.change = "none" end
        if r.delta < 0 then r.direction = "lower" elseif r.delta > 0 then r.direction = "higher" else r.direction = "same" end
    end
    rows[#rows + 1] = r
    return r
end

local function Ops(rec)
    local byId = {}
    for _, op in ipairs(rec.ops or {}) do byId[op.id] = op end
    return byId
end

local function MemSlope(rec)
    local first, last
    for _, m in ipairs(rec.memory or {}) do
        if m.core then
            first = first or m
            last = m
        end
    end
    if not (first and last) or last.t - first.t < 10 then return nil, nil end
    return (last.core - first.core) / ((last.t - first.t) / 60), last.core
end

function CMP.Run(a, b)
    local ok, warnings, notes = CMP.Check(a, b)
    local out = { a = a.uid, b = b.uid, compatible = ok, warnings = warnings, notes = notes, rows = {} }
    if not ok then return out end
    local rows = out.rows
    local ma, mb = Minutes(a), Minutes(b)
    local fa, fb = a.frames or {}, b.frames or {}
    local small = (fa.count or 0) < 100 or (fb.count or 0) < 100
    Row(rows, "Frame interval, median", "ms", "per frame (approximate: log buckets)", fa.p50, fb.p50, small and "fewer than 100 frames in one" or nil)
    Row(rows, "Frame interval, 95th percentile", "ms", "per frame (approximate)", fa.p95, fb.p95)
    Row(rows, "Frame interval, 99th percentile", "ms", "per frame (approximate)", fa.p99, fb.p99)
    Row(rows, "Long frames", "per minute", "per minute of capture", (fa.spikeCount or 0) / ma, (fb.spikeCount or 0) / mb)
    if a.config.profiler and b.config.profiler then
        local ca, cb = F.Sum(a, "core"), F.Sum(b, "core")
        local na, nb = F.Sum(a, "frames"), F.Sum(b, "frames")
        Row(rows, "TwichUI time per frame (client's count)", "ms", "per frame", na > 0 and ca / na or nil, nb > 0 and cb / nb or nil)
        Row(rows, "TwichUI time (client's count)", "ms per minute", "per minute of capture", ca / ma, cb / mb)
        local da, db = F.Sum(a, "diag"), F.Sum(b, "diag")
        Row(rows, "TwichUI Diagnostics' own time (client's count)", "ms per minute", "per minute of capture", da / ma, db / mb)
    end
    Row(rows, "Instrumented TwichUI work", "ms per minute", "per minute of capture (self times added up)", F.MeasuredWork(a) / ma, F.MeasuredWork(b) / mb)
    local ea, eb = 0, 0
    for _, e in ipairs(a.events or {}) do ea = ea + e.received end
    for _, e in ipairs(b.events or {}) do eb = eb + e.received end
    Row(rows, "Events TwichUI received", "per minute", "per minute of capture", ea / ma, eb / mb)
    local sa, peakA = MemSlope(a)
    local sb, peakB = MemSlope(b)
    local memNote = (a.gcExperiment or b.gcExperiment) and "a collection experiment ran" or nil
    Row(rows, "TwichUI memory change", "KB per minute", "sampled; net change, not allocation", sa, sb, memNote)
    Row(rows, "TwichUI memory, last reading", "KB", "sampled", peakA, peakB, memNote)
    -- operations: every id in either, by the larger total
    local oa, ob = Ops(a), Ops(b)
    local ids, seen = {}, {}
    for _, op in ipairs(a.ops or {}) do if not seen[op.id] then seen[op.id] = true; ids[#ids + 1] = op.id end end
    for _, op in ipairs(b.ops or {}) do if not seen[op.id] then seen[op.id] = true; ids[#ids + 1] = op.id end end
    table.sort(ids, function(x, y)
        local tx = math.max(oa[x] and oa[x].total or 0, ob[x] and ob[x].total or 0)
        local ty = math.max(oa[y] and oa[y].total or 0, ob[y] and ob[y].total or 0)
        if tx ~= ty then return tx > ty end
        return x < y
    end)
    out.ops = {}
    for i = 1, math.min(#ids, 20) do
        local id = ids[i]
        local x, y = oa[id], ob[id]
        local row = { id = id, label = DX.Op(id).label }
        row.calls = Row({}, "calls", "per minute", "per minute of capture", (x and x.calls or 0) / ma, (y and y.calls or 0) / mb)
        row.total = Row({}, "time", "ms per minute", "per minute of capture", (x and x.total or 0) / ma, (y and y.total or 0) / mb)
        if x and y and x.calls >= CMP.MIN_CALLS and y.calls >= CMP.MIN_CALLS then
            row.mean = Row({}, "per call", "ms", "per call", x.mean, y.mean)
            row.p95 = Row({}, "per call, 95th percentile", "ms", "per call (approximate)", x.p95, y.p95)
        else
            row.note = ("too few calls to compare per call (fewer than %d in %s)"):format(CMP.MIN_CALLS, (x and x.calls or 0) < CMP.MIN_CALLS and "A" or "B")
        end
        out.ops[#out.ops + 1] = row
    end
    return out
end
