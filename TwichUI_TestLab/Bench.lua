-- TwichUI Test Lab: the benchmark framework (TL.Bench). Milestone M7. Pure Lua 5.1: it makes no game call of its own, creates no frame, timer or
-- event, and touches no saved variable. The clock, the memory reading, the yield and the stop test are all INJECTED, so the same measurement
-- code runs offline (os.clock, plain Lua), in the game (GetTimePreciseSec, the Lab's coroutine runner) and in the unit tests (a scripted
-- clock whose readings the test decides).
--
-- WHAT A MEASUREMENT IS. A workload (Workloads.lua) is data plus three functions: setup (builds its input, NOT timed), begin (starts one
-- repetition and returns step / finish), verify (checks the output). Measure runs it like this:
--   * one warm-up repetition (so the first run's cache and allocation effects are not a sample), then REPS timed repetitions (default 5);
--   * a repetition is a series of small STEPS (a batch of records, a handful of scenarios). Only the step calls are timed; what happens
--     between steps (the yield, the memory reading, the progress callback) is not. A repetition's sample is the SUM of its steps (CPU time of
--     the work), in milliseconds. The worst single step is kept apart: it is what one game frame would have had to absorb.
--   * wall time (first step to last, waits included) is kept apart from the sum of steps; their difference is time spent waiting for frames.
--     A complete game-frame interval is a third thing and belongs to the runner (Runner records it per case); nothing here mixes them.
--   * the output is checked: a cheap signature on EVERY repetition (all must agree), the workload's full verification on the warm-up and the
--     last repetition, and a fingerprint of the input before and after (the benchmark must not change what it was given).
--   * the input is built before the first timed step and never inside one.
--
-- MEMORY. collectgarbage("count") is the LUA HEAP in kilobytes: not an addon's total, not the process, not the allocation count. Without a
-- forced collection it moves up and down as the collector runs, so a per-repetition "heap change" can be hidden by a collection and a "peak"
-- is the highest value SAMPLED BETWEEN STEPS (a spike inside one step is invisible). Both are reported as approximate. "Retained" needs
-- forced full collections (a visible hitch in the game), so it happens only when the caller asks (opt.retained).
--
-- COMPARING. Compare(base, cand) uses the median and the median absolute deviation (MAD) of the samples; see BN.Compare for the rule.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local BN = {}
TL.Bench = BN

BN.SCHEMA = 1            -- the schema of an encoded result line and of the report's benchmark section
BN.REPS = 5              -- timed repetitions by default
BN.MAX_REPS = 25
BN.MAX_SAMPLES = 25
BN.MAD_FACTOR = 3        -- a change must exceed this many MADs ...
BN.NOISE_FLOOR = 0.05    -- ... and this fraction of the baseline median, whichever is larger
BN.UNSTABLE = 0.25       -- a MAD above this fraction of the median makes a comparison inconclusive
BN.MIN_MS = 0.05         -- a median below this is at the edge of the clock's resolution: inconclusive
BN.MAX_STEP_MS = 100     -- in the game a single step longer than this stops the benchmark (it would be a visible stutter)
BN.INSTR = 2             -- the instrumentation level, written on a result line (inst=). 2 added the phase/segment attribution of M7.1. A sample is
                         -- still the sum of a repetition's timed steps, so lines of level 1 and 2 are comparable; it is information, not a comparison key
BN.REPORT_SEG_MS = 16    -- a segment shorter than this (a frame at 60 fps) is not worth a report line
BN.SLOW_SEGMENTS = 4     -- the longest uninterrupted segments kept on a result

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

---------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------
function BN.Median(list)
    local n = #list
    if n == 0 then return nil end
    local s = {}
    for i = 1, n do s[i] = list[i] end
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

-- n, median, mad (median of |x - median|), min, max, sum. nil for an empty list.
function BN.Stats(list)
    local n = #list
    if n == 0 then return nil end
    local med = BN.Median(list)
    local dev, lo, hi, sum = {}, list[1], list[1], 0
    for i = 1, n do
        local x = list[i]
        dev[i] = abs(x - med)
        if x < lo then lo = x end
        if x > hi then hi = x end
        sum = sum + x
    end
    return { n = n, median = med, mad = BN.Median(dev), min = lo, max = hi, sum = sum }
end

---------------------------------------------------------------------------
-- A deterministic text of a value (sorted keys), to see that an input did not change. Bounded depth; functions and threads are named only.
---------------------------------------------------------------------------
function BN.Ser(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "number" then return ("%.14g"):format(v) end
    if t == "string" then return ("%q"):format(v) end
    if t ~= "table" then return t == "boolean" and tostring(v) or t end
    if depth > 6 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        if ta == "number" or ta == "string" then return a < b end
        return tostring(a) < tostring(b)
    end)
    local out = {}
    for i, k in ipairs(keys) do out[i] = BN.Ser(k, depth + 1) .. "=" .. BN.Ser(v[k], depth + 1) end
    return "{" .. table.concat(out, ",") .. "}"
end

---------------------------------------------------------------------------
-- Measure
---------------------------------------------------------------------------
-- w: the workload { id, v, fixture, seed, size, work, unit, setup, begin, signature, verify, fingerprint }.
-- opt: clock() seconds (required), mem() KB (default collectgarbage("count")), yield() (called between steps; nil offline), stop() -> reason or nil,
--   reps, warmup (0 or 1), budget (seconds for the whole measurement, by opt.clock), maxStep (seconds; a longer step stops the benchmark),
--   retained (force full collections to measure what stays), progress(text), ctx (extra fields for the workload's setup), env, host, clockName, lua.
-- Returns a result table; result.status is "ok", "stopped", "timeout", "oversize" (a step ran past maxStep), "mismatch" (the output
-- or the input was not as it must be) or "skipped"; result.why says what. A result that is not "ok" holds no statistics.
-- It never uses pcall (Lua 5.1 cannot yield across one): an error raised by a workload propagates to the caller, which owns the cleanup.
function BN.Measure(w, opt)
    opt = opt or {}
    local clock = assert(opt.clock, "BN.Measure needs a clock")
    local mem = opt.mem or function() return collectgarbage("count") end
    local yield, stop = opt.yield, opt.stop
    local reps = min(BN.MAX_REPS, max(1, floor(tonumber(opt.reps) or BN.REPS)))
    local warm
    if opt.warmup ~= nil then warm = (opt.warmup == false or opt.warmup == 0) and 0 or 1
    else warm = w.warmup == false and 0 or 1 end
    local res = { schema = BN.SCHEMA, id = w.id, v = w.v or 1, fixture = w.fixture, seed = w.seed, size = w.size, work = w.work, unit = w.unit or "ops",
        env = opt.env or "unknown", host = opt.host or "unlabeled", clock = opt.clockName or "unknown", lua = opt.lua or _VERSION,
        repsWanted = reps, warmup = warm, samples = {}, status = "ok", limits = {} }
    local started = clock()
    local deadline = opt.budget and (started + opt.budget) or nil
    local maxStep = opt.maxStep

    local function Abort(status, why)
        res.status, res.why = status, why
        return res
    end
    local function Interrupted()
        if stop then
            local why = stop()
            if why then return "stopped", tostring(why) end
        end
        if deadline and clock() > deadline then return "timeout", ("the time budget (%.0f s) ran out"):format(opt.budget) end
        return nil
    end

    -- ATTRIBUTION (M7.1). A SEGMENT is the work between two yields: it is what the game would have had to absorb in one frame, and it holds
    -- more than the timed steps (the workload's setup, its fingerprint, verification, the signature, forced collections). Each piece is timed
    -- under a phase name; Y() closes the segment at every yield and keeps the longest few, with how the time divided. None of this is part of a
    -- sample: a sample stays the sum of the timed steps.
    --   setup | fingerprint | begin | warmup (a warm-up repetition's steps) | step (a timed repetition's steps) | finish | signature | verify | collect | other
    local phases, slow = {}, {}
    local segStart, segParts, segTimed = clock(), {}, false
    local function Part(name, d)
        segParts[name] = (segParts[name] or 0) + d
        local p = phases[name]
        if not p then p = { n = 0, total = 0, max = 0 } phases[name] = p end
        p.n, p.total = p.n + 1, p.total + d
        if d > p.max then p.max = d end
    end
    -- a phase that yields inside (the workload's setup, its verification) is split at the yield: each segment gets its own share, and the
    -- time spent waiting for the next frame belongs to no phase
    local inflight
    local function Timed(name, f, ...)
        local outer = inflight
        local rec = { name = name, from = clock() }
        inflight = rec
        local r1, r2 = f(...)
        Part(name, clock() - rec.from)
        inflight = outer
        if outer then outer.from = clock() end
        return r1, r2
    end
    local function Close(label)
        local now = clock()
        if inflight then Part(inflight.name, now - inflight.from) end
        local ms = (now - segStart) * 1000
        if ms > 0 then
            local top, topMs, sum = "other", 0, 0
            for k, v in pairs(segParts) do
                sum = sum + v
                if v > topMs then top, topMs = k, v end
            end
            local seg = { ms = ms, phase = top, phaseMs = topMs * 1000, otherMs = max(0, ms - sum * 1000), timed = segTimed, label = label, parts = {} }
            for k, v in pairs(segParts) do seg.parts[k] = v * 1000 end
            if opt.segment then opt.segment(seg) end
            -- the longest few, by length
            if #slow < BN.SLOW_SEGMENTS or ms > slow[#slow].ms then
                slow[#slow + 1] = seg
                table.sort(slow, function(a, b) return a.ms > b.ms end)
                while #slow > BN.SLOW_SEGMENTS do slow[#slow] = nil end
            end
        end
        segParts, segTimed = {}, false
    end
    local function Y(label)
        Close(label)
        if yield then yield() end
        segStart = clock()
        if inflight then inflight.from = segStart end
    end

    local base
    if opt.retained then Timed("collect", function() collectgarbage() collectgarbage() end) base = mem() end
    local ctx = opt.ctx or {}
    ctx.yield = function() Y("setup") end
    ctx.stop = stop
    ctx.clock = clock
    local state = Timed("setup", w.setup, ctx)
    if state == nil then return Abort("skipped", "the workload could not build its input") end
    local work = state.work or w.work   -- a workload whose size is only known once its input is built says so in state.work
    res.work = work
    local before = w.fingerprint and Timed("fingerprint", w.fingerprint, state, ctx) or nil

    local stepWorst, heapDeltas, heapPeaks, walls, afterRep = 0, {}, {}, {}, {}
    local firstSig
    local cpuTotal, workTotal = 0, 0

    for rep = 1 - warm, reps do
        local timed = rep >= 1
        if opt.progress then opt.progress(timed and ("repetition %d of %d"):format(rep, reps) or "warm-up") end
        local step, finish = Timed("begin", w.begin, state)
        local wallStart, memStart = clock(), mem()
        local cpu, worst, peak, steps = 0, 0, 0, 0
        local done
        repeat
            local a = clock()
            done = step()
            local d = clock() - a
            Part(timed and "step" or "warmup", d)
            segTimed = segTimed or timed
            steps = steps + 1
            cpu = cpu + d
            if d > worst then worst = d end
            local grown = mem() - memStart
            if grown > peak then peak = grown end
            if maxStep and d > maxStep then
                Close("oversize")
                return Abort("oversize", ("one step took %.1f ms, past the %.0f ms limit; the benchmark was stopped rather than repeated"):format(d * 1000, maxStep * 1000))
            end
            if not done then
                local status, why = Interrupted()
                if status then return Abort(status, why) end
                Y("step")
            end
        until done
        local wall = clock() - wallStart
        Y("end of steps")   -- the last step must not share a frame with the verification below or the next repetition's first step
        local out = Timed("finish", finish)
        local sig = Timed("signature", w.signature, out)
        if firstSig == nil then firstSig = sig
        elseif sig ~= firstSig then
            return Abort("mismatch", ("repetition %d gave a different result from the first (%s vs %s)"):format(rep, tostring(sig):sub(1, 60), tostring(firstSig):sub(1, 60)))
        end
        if (rep == 1 - warm or rep == reps) and w.verify then
            local ok, why = Timed("verify", w.verify, state, out, ctx)
            if not ok then return Abort("mismatch", "the output is wrong: " .. tostring(why)) end
        end
        res.steps = steps
        if timed then
            res.samples[#res.samples + 1] = cpu * 1000
            walls[#walls + 1] = wall * 1000
            if worst > stepWorst then stepWorst = worst end
            heapDeltas[#heapDeltas + 1] = mem() - memStart
            heapPeaks[#heapPeaks + 1] = peak
            cpuTotal = cpuTotal + cpu
            workTotal = workTotal + (work or 0)
        end
        out = nil
        if opt.retained then   -- the warm-up is collected too, but only timed repetitions count toward growth
            Timed("collect", function() collectgarbage() collectgarbage() end)
            if timed then afterRep[#afterRep + 1] = mem() end
        end
        local status, why = Interrupted()
        if status and rep < reps then return Abort(status, why) end
        if rep < reps then Y("repetition") end
    end

    if before ~= nil then
        local after = Timed("fingerprint", w.fingerprint, state, ctx)
        if after ~= before then return Abort("mismatch", "the benchmark changed its own input (the fingerprint before and after differ)") end
        before, after = nil, nil   -- a fingerprint can be large; it must not count as retained memory
    end
    firstSig = nil

    local st = BN.Stats(res.samples)
    res.reps = st.n
    res.median, res.mad, res.min, res.max = st.median, st.mad, st.min, st.max
    if work and st.median > 0 then res.perSec = work / (st.median / 1000) end
    res.stepMaxMs = stepWorst * 1000
    res.wallMs = BN.Median(walls)
    res.waitMs = max(0, res.wallMs - res.median)   -- time between the steps of a typical repetition: yields, frame waits, the readings themselves
    res.heapDeltaKB = BN.Median(heapDeltas)
    res.heapPeakKB = 0
    for _, p in ipairs(heapPeaks) do if p > res.heapPeakKB then res.heapPeakKB = p end end
    if opt.retained then
        state = nil
        Timed("collect", function() collectgarbage() collectgarbage() end)
        res.retainedKB = mem() - base
        res.heapAfterRep = afterRep
        res.heapGrowthKB = #afterRep > 1 and (afterRep[#afterRep] - afterRep[1]) or 0
    end
    res.verified = w.verify ~= nil
    Close("end")
    res.inst, res.phases, res.slowest = BN.INSTR, phases, slow
    local longest = slow[1]
    if longest then res.longestMs, res.longestPhase, res.longestTimed = longest.ms, longest.phase, longest.timed end
    res.limits[#res.limits + 1] = "heap figures are the Lua heap (collectgarbage count), approximate: a collection can hide growth, peak is sampled between steps"
    return res
end

---------------------------------------------------------------------------
-- Comparing a baseline with a candidate
---------------------------------------------------------------------------
-- Verdicts: "faster", "slower", "same" (indistinguishable within measurement noise), "inconclusive" (unstable or too few samples or a
-- direction that is not consistent), "incomparable" (the fixture, the workload version, the environment, the host or the clock differ, or a
-- run did not finish). Every verdict carries a reason in words.
--   noise threshold = max(MAD_FACTOR x the larger MAD, NOISE_FLOOR x the baseline median)
--   |difference of medians| <= threshold                 -> same
--   a MAD above UNSTABLE x its median, fewer than REPS samples, or a median below MIN_MS -> inconclusive
--   opt.paired (the runs were interleaved A B A B ...): the difference must have the same sign in EVERY pair, or the result is inconclusive
-- It is a rule of thumb for deciding whether to believe a number, not a statistical test. An offline figure never stands in for the game's.
local SAME_KEYS = { "id", "v", "fixture", "seed", "size", "work", "unit", "env", "host", "clock", "lua" }

function BN.Compare(base, cand, opt)
    opt = opt or {}
    if type(base) ~= "table" or type(cand) ~= "table" then return { verdict = "incomparable", reason = "a result is missing" } end
    if base.status ~= "ok" or cand.status ~= "ok" then
        return { verdict = "incomparable", reason = "a run did not finish (" .. tostring(base.status ~= "ok" and base.status or cand.status) .. ")" }
    end
    for _, k in ipairs(SAME_KEYS) do
        -- a decoded line has its spaces written as underscores (Encode), so both sides are compared in that form
        local a, b = tostring(base[k]):gsub("[%s=]", "_"), tostring(cand[k]):gsub("[%s=]", "_")
        if a ~= b then
            return { verdict = "incomparable", reason = ("%s differs (%s vs %s)"):format(k, a, b) }
        end
    end
    local nb, nc = #(base.samples or {}), #(cand.samples or {})
    if nb < BN.REPS or nc < BN.REPS then
        return { verdict = "inconclusive", reason = ("fewer than %d samples (%d and %d)"):format(BN.REPS, nb, nc) }
    end
    local sb, sc = BN.Stats(base.samples), BN.Stats(cand.samples)
    if sb.median < BN.MIN_MS or sc.median < BN.MIN_MS then
        return { verdict = "inconclusive", reason = ("a median under %.2f ms is too close to the clock's resolution"):format(BN.MIN_MS) }
    end
    if sb.mad > BN.UNSTABLE * sb.median or sc.mad > BN.UNSTABLE * sc.median then
        return { verdict = "inconclusive", reason = ("unstable: MAD above %d%% of the median (%.2f of %.2f, %.2f of %.2f ms)"):format(BN.UNSTABLE * 100, sb.mad, sb.median, sc.mad, sc.median) }
    end
    local delta = sc.median - sb.median
    local threshold = max(BN.MAD_FACTOR * max(sb.mad, sc.mad), BN.NOISE_FLOOR * sb.median)
    local out = { delta = delta, percent = delta / sb.median * 100, threshold = threshold, base = sb.median, cand = sc.median }
    if abs(delta) <= threshold then
        out.verdict, out.reason = "same", ("a difference of %.2f ms is within the noise threshold of %.2f ms"):format(delta, threshold)
        return out
    end
    if opt.paired and nb == nc then
        for i = 1, nb do
            local d = cand.samples[i] - base.samples[i]
            if (delta > 0) ~= (d > 0) or d == 0 then
                out.verdict, out.reason = "inconclusive", ("the medians differ by %.2f ms but pair %d points the other way"):format(delta, i)
                return out
            end
        end
    end
    out.verdict = delta < 0 and "faster" or "slower"
    out.reason = ("%.1f%% (%.2f ms) against a noise threshold of %.2f ms"):format(out.percent, delta, threshold)
    return out
end

---------------------------------------------------------------------------
-- One line per result: the copyable, parseable form (and the baseline file's)
---------------------------------------------------------------------------
-- "B1 id=... fixture=... key=value ..." : no spaces inside a value. Decode validates every field; it never executes anything.
local function F3(x) return ("%.3f"):format(x) end

function BN.Encode(r)
    local parts = { "B" .. BN.SCHEMA }
    local function Add(k, v) if v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v):gsub("[%s=]", "_") end end
    Add("id", r.id) Add("v", r.v) Add("fixture", r.fixture) Add("seed", r.seed) Add("size", r.size) Add("work", r.work) Add("unit", r.unit)
    Add("env", r.env) Add("host", r.host) Add("clock", r.clock) Add("lua", r.lua) Add("status", r.status)
    if r.status == "ok" then
        Add("reps", r.reps) Add("warmup", r.warmup)
        local s = {}
        for i, x in ipairs(r.samples) do s[i] = F3(x) end
        Add("samples", table.concat(s, ","))
        Add("median", F3(r.median)) Add("mad", F3(r.mad)) Add("min", F3(r.min)) Add("max", F3(r.max))
        if r.perSec then Add("persec", ("%.0f"):format(r.perSec)) end
        Add("stepmax", F3(r.stepMaxMs)) Add("wall", F3(r.wallMs)) Add("wait", F3(r.waitMs))
        Add("heapdelta", ("%.1f"):format(r.heapDeltaKB)) Add("heappeak", ("%.1f"):format(r.heapPeakKB))
        if r.retainedKB then Add("retained", ("%.1f"):format(r.retainedKB)) Add("growth", ("%.1f"):format(r.heapGrowthKB or 0)) end
        Add("verified", r.verified and 1 or 0)
        Add("inst", r.inst)
        if r.longestMs then Add("longest", F3(r.longestMs)) Add("lphase", r.longestPhase) Add("ltimed", r.longestTimed and 1 or 0) end
        if r.phases then
            local names = {}
            for k in pairs(r.phases) do names[#names + 1] = k end
            table.sort(names)
            local ph = {}
            for i, k in ipairs(names) do ph[i] = ("%s:%.1f:%.1f"):format(k, r.phases[k].total * 1000, r.phases[k].max * 1000) end
            Add("phases", table.concat(ph, ","))   -- name:total ms:longest ms, over the whole measurement
        end
    else
        Add("why", (tostring(r.why or ""):gsub("[^%w%.,%-%(%)/]", "_")):sub(1, 100))
    end
    return table.concat(parts, " ")
end

local NUM = { v = true, seed = true, size = true, work = true, reps = true, warmup = true, median = true, mad = true, min = true, max = true,
    persec = true, inst = true, longest = true, ltimed = true, stepmax = true, wall = true, wait = true, heapdelta = true, heappeak = true, retained = true, growth = true, verified = true }

-- A line from Encode back into a result (only what a comparison needs, plus the figures), or nil and why.
function BN.Decode(line)
    if type(line) ~= "string" or #line > 2000 then return nil, "not a result line" end
    local head = line:match("^B(%d+) ")
    if tonumber(head) ~= BN.SCHEMA then return nil, "not a schema " .. BN.SCHEMA .. " benchmark line" end
    local f = {}
    for k, v in line:gmatch("(%a+)=(%S*)") do f[k] = v end
    if not f.id or not f.fixture or not f.env or not f.clock then return nil, "a needed field is missing" end
    local r = { schema = BN.SCHEMA, id = f.id, fixture = f.fixture, unit = f.unit, env = f.env, host = f.host, clock = f.clock, lua = f.lua, status = f.status or "ok", why = f.why }
    for k, v in pairs(f) do
        if NUM[k] then
            local n = tonumber(v)
            if not n or n ~= n or n == math.huge or n == -math.huge then return nil, k .. " is not a finite number" end
            r[k] = n
        end
    end
    r.perSec, r.stepMaxMs, r.wallMs, r.waitMs, r.heapDeltaKB, r.heapPeakKB, r.retainedKB, r.heapGrowthKB =
        r.persec, r.stepmax, r.wall, r.wait, r.heapdelta, r.heappeak, r.retained, r.growth
    r.samples = {}
    if r.status == "ok" then
        if not f.samples then return nil, "samples are missing" end
        for x in f.samples:gmatch("[^,]+") do
            local n = tonumber(x)
            if not n or n ~= n or n == math.huge or n < 0 or #r.samples >= BN.MAX_SAMPLES then return nil, "a sample is not valid" end
            r.samples[#r.samples + 1] = n
        end
        if #r.samples == 0 then return nil, "no samples" end
        r.reps = #r.samples
    end
    return r
end

-- Every result line in a pasted text or file's contents, by id. Lines that do not decode are counted and skipped.
function BN.DecodeAll(text)
    local out, bad = {}, 0
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        if line:match("^B%d+ ") then
            local r = BN.Decode(line)
            if r then out[r.id] = r else bad = bad + 1 end
        end
    end
    return out, bad
end

---------------------------------------------------------------------------
-- Text for people
---------------------------------------------------------------------------
local function Rate(x)
    if x >= 1e6 then return ("%.1fM"):format(x / 1e6) end
    if x >= 1e3 then return ("%.0fk"):format(x / 1e3) end
    return ("%.0f"):format(x)
end

-- "median 12.3 ms (MAD 0.4), range 11.9 to 13.1, 81k records/s, longest step 1.1 ms, heap +120 KB (peak 340 KB, approx.)"
function BN.Summary(r)
    if r.status ~= "ok" then return ("%s: %s"):format(r.status, tostring(r.why or "")) end
    local s = ("median %.2f ms (MAD %.2f), range %.2f to %.2f, %d samples"):format(r.median, r.mad, r.min, r.max, r.reps)
    if r.perSec then s = s .. (", %s %s/s"):format(Rate(r.perSec), r.unit or "ops") end
    s = s .. (", longest step %.2f ms, heap %+.0f KB (peak %.0f KB, approx.)"):format(r.stepMaxMs, r.heapDeltaKB, r.heapPeakKB)
    if r.retainedKB then s = s .. (", retained %+.0f KB, growth over repetitions %+.0f KB"):format(r.retainedKB, r.heapGrowthKB or 0) end
    return s
end

-- The report's benchmark section for a list of results ({ result, frame (the runner's frame record for the case, or nil), compare }), or nil
-- when there are none. It has its own schema line, so the case report's schema 1 is unchanged.
function BN.ReportLines(items, header)
    if #items == 0 then return nil end
    local lines = { ("benchmarks (schema %d): %s"):format(BN.SCHEMA, header or ""),
        "  a sample is the sum of a repetition's timed steps in ms; heap = Lua heap KB, approximate; wall/wait = elapsed and time between steps; frames = the game's own frame intervals while the case ran" }
    for _, it in ipairs(items) do
        local r = it.result
        lines[#lines + 1] = "  " .. BN.Encode(r)
        local extra = {}
        if r.status == "ok" then
            extra[#extra + 1] = ("wall %.0f ms, wait %.0f ms"):format(r.wallMs, r.waitMs)
        end
        if it.frame and it.frame.n and it.frame.n > 0 then
            extra[#extra + 1] = ("frames %d, worst %.0f ms, over 33 ms: %d, over 50 ms: %d"):format(it.frame.n, it.frame.worst * 1000, it.frame.over33, it.frame.over50)
        end
        if r.slowest and r.slowest[1] and r.slowest[1].ms >= BN.REPORT_SEG_MS then
            local segs = {}
            for i, g in ipairs(r.slowest) do
                if g.ms >= BN.REPORT_SEG_MS then
                    segs[#segs + 1] = ("%.1f ms (%s %.1f, other %.1f; %s)"):format(g.ms, g.phase, g.phaseMs, g.otherMs, g.timed and "includes timed steps" or "not timed")
                end
            end
            extra[#extra + 1] = "longest segments between yields: " .. table.concat(segs, "; ")
        end
        if it.compare then extra[#extra + 1] = "vs baseline: " .. it.compare.verdict .. " (" .. it.compare.reason .. ")" end
        if #extra > 0 then lines[#lines + 1] = "      " .. table.concat(extra, " | ") end
    end
    return lines
end
