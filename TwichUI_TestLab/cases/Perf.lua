-- TwichUI Test Lab: the Performance category (M7). OPT-IN: it never runs unless chosen by name, because it spends several seconds of CPU,
-- spread over frames, and one case forces full garbage collections. Every case here is the same definition tests/bench_workshop.lua runs
-- offline (Workloads.lua), on made-up data, calling production functions with explicit inputs: no scan, no purchase, no queue, no saved data.
-- Nothing here creates a frame, a timer or an event; a Stop, a close, an error or combat ends the run at the next yield and nothing is left
-- behind but garbage. docs/testlab.md ("Benchmarks") explains how to read the numbers: they are measurements of this run in this client,
-- not budgets and not promises.

local R = TwichUI
local TL = R.TestLab
local BN, WL = TL.Bench, TL.Workloads

TL.Category{ id = "perf", label = "Performance (benchmarks)", blurb = "times the Workshop's calculations on made-up data, five repetitions each, in small steps between frames; nothing of yours is touched", optin = true }

local function Environment()
    local version, build = "?", "?"
    if GetBuildInfo then version, build = GetBuildInfo() end
    return ("wow-%s.%s"):format(tostring(version), tostring(build))
end

local function Combat()
    if InCombatLockdown and InCombatLockdown() then return "combat started" end
end

-- One workload as a case. retained: force full collections between repetitions to measure what stays (a visible hitch, so it is a case of its own).
local function Register(id, w, retained)
    TL.Case{ id = id, cat = "perf", class = "pure", needs = { "workshop" }, budget = 55, run = function(t)
        local RN = TL.Runner
        local res = BN.Measure(w, {
            clock = RN.Now, clockName = RN.ClockName(), env = Environment(), host = "client", lua = _VERSION,
            yield = function() t:Yield() end, stop = Combat, budget = 50, maxStep = (w.maxStepMs or BN.MAX_STEP_MS) / 1000, retained = retained,
            progress = function(text) t:Progress(text) end, ctx = { W = t.W },
            segment = function(seg) t.seg = seg end,   -- the Runner reads it when this resume ends, to say what a long slice was made of
        })
        if res.status == "skipped" then t:Skip(res.why) end
        if retained then res.id = w.id .. ".retained" end   -- its timings are not the plain run's: a different line, a different baseline
        local base = TL.Baselines and TL.Baselines[res.id]
        if res.status == "ok" and base then
            res.compare = BN.Compare(base, res)
            t:Note("against the recorded baseline: " .. res.compare.verdict .. " (" .. res.compare.reason .. ")")
        end
        t:Bench(res)
        t:Note(BN.Summary(res))
        t:Check(res.status == "ok", res.status == "ok" and "" or ("the benchmark %s: %s"):format(res.status, tostring(res.why)))
    end }
end

for _, w in ipairs(WL.InGame()) do Register("perf." .. w.id, w, false) end

-- what stays in memory after repeated runs: three representative workloads, each with forced full collections between repetitions
for _, id in ipairs({ "market.aggregate.10k", "market.lookup.24k", "crafting.plan.medium" }) do
    if WL.byId[id] then Register("perf.retained." .. id, WL.byId[id], true) end
end

-- the clock and the memory reading themselves: the smallest step the clock was seen to make
TL.Case{ id = "perf.clock", cat = "perf", class = "pure", budget = 5, run = function(t)
    local RN = TL.Runner
    local smallest, last, reads = nil, RN.Now(), 0
    for _ = 1, 20000 do
        local now = RN.Now()
        reads = reads + 1
        if now > last and (not smallest or now - last < smallest) then smallest = now - last end
        last = now
        if smallest and reads > 200 then break end
    end
    t:Check(type(collectgarbage("count")) == "number", "collectgarbage(\"count\") answers a number")
    t:Note(("clock %s; the smallest step seen between two readings: %s; the memory reading is the Lua heap in KB"):format(RN.ClockName(),
        smallest and ("%.4f ms"):format(smallest * 1000) or "none in 20000 reads (the clock did not advance)"))
    if smallest then t:Fact("perf.clock.step_us", ("%.1f"):format(smallest * 1e6)) end
end }

-- stated, not silently missing
TL.Case{ id = "perf.ui.redraw", cat = "perf", class = "pure", budget = 1, run = function(t)
    t:Skip("deferred: " .. table.concat(WL.DEFERRED, "; ") .. ". They read the player's real queue and saved prices, so a safe synthetic benchmark does not exist yet; real play is measured by R.Perf scopes and the Diagnostics captures")
end }
