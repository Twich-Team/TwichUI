-- TwichUI Diagnostics: instrumented operations, events and callbacks
-- While a capture records, this file's functions are TwichUI's R.Perf.Start, Stop, Count, Callback, Received and Fault,
-- and R.Perf.on is true; when it stops, `on` goes back to false (the core's call sites then skip everything) and a late
-- Stop is ignored. The code lives in this addon, so the client's profiler puts its cost on TwichUI_Diagnostics, not on
-- TwichUI.
--
-- Scopes. Start(id) pushes a frame on one stack and returns a serial number; Stop(serial) pops it.
--   * Inclusive time: the elapsed time of the scope, everything it called included. An operation that runs inside
--     itself (re-entry) adds its time once, for the outermost activation; the inner ones are counted as calls and as
--     `reentered`, so totals are never counted twice.
--   * Self time: inclusive time minus the inclusive time of the instrumented scopes directly inside it. Work done by
--     code that has no scope (uninstrumented callees, the game's own functions) stays in the caller's self time. Self
--     times of different scopes never overlap, so they can be added up.
--   * A scope that never reached its Stop (an error went through it) is found when an outer scope stops or a later
--     frame starts a scope (a synchronous scope can't outlast its frame: GetTime is the frame's time). It is counted
--     as `aborted` and its time is not used. Scopes must not span a coroutine yield.
--   * Event callbacks (Core.lua's bus) are scopes too, under "event:<EVENT>", so an event's callback time and the
--     operations inside it are accounted the same way. Received(event) counts the event once, however many callbacks
--     it reaches; each callback is counted separately, by listener.
-- Per operation: calls, inclusive total, self total, min, max, a log histogram (approximate percentiles, never above the
-- true maximum), the busiest 10-second window, its callers (up to 6), and the slowest few calls (exemplars) with their
-- time and context. Allocation: the Lua heap (collectgarbage("count")) read at each scope's start and end; the rise
-- is summed per operation, inclusive and self (what its instrumented children grew is taken off). It is approximate:
-- a collection step inside the scope hides some of it (a fall is counted as nothing), and it includes what the game's
-- own functions allocated inside the scope. A scope with no rise adds nothing. In a
-- focused trace a new slowest call also takes a call path (debugstack), at most one a second, TwichUI's files only.
-- Hot path: no table is made for a call (only for a new operation, a new callback or a new exemplar), no string is
-- formatted, nothing is sorted. Everything is bounded (MAX_* below) and what didn't fit is counted.

local R = TwichUI
local DX = R.DiagnosticsKit
local Hist = DX.Hist
local Perf = R.Perf
local I = {}
DX.Instrument = I

I.MAX_OPS, I.MAX_EVENTS, I.MAX_CALLBACKS, I.MAX_COUNTERS, I.MAX_DEPTH = 96, 128, 256, 64, 48
I.EXEMPLARS = 5
I.MAX_PARENTS = 6
I.WINDOW = 10            -- seconds: the window an operation's busiest rate is counted in
I.STACK_EVERY = 1        -- seconds between call paths in a focused trace

local clock = DX.Clock
local GetTime = GetTime
local heapCount = collectgarbage
local active = false
local cfg                -- the capture's: { t0 (ms), stacks, filter = { prefixes } or nil, allocation }
local ops, opCount = {}, 0
local events, eventCount = {}, 0      -- [event] = { received, op }
local callbacks, callbackCount = setmetatable({}, { __mode = "k" }), 0   -- [fn] = stats (weak: never keeps a function alive)
local cbList = {}                     -- the stats objects in order seen (plain tables; no function in them)
local counters, counterCount = {}, 0
local dropped = { ops = 0, events = 0, callbacks = 0, counters = 0, depth = 0 }
local anomalies = { aborted = 0, stale = 0, clockBack = 0, crossedFrame = 0 }
local lastStackAt = -math.huge

-- the stack, as parallel arrays (nothing is made per call)
local depth, serial = 0, 0
local sOp, sStart, sChild, sFrame, sSerial, sDetail, sCb = {}, {}, {}, {}, {}, {}, {}
local sHeap, sChildHeap = {}, {}

-- per frame and per bucket: TwichUI's instrumented work that ended since the last read (outermost scopes only)
local frameWork, frameTop, frameTopMs, bucketEvents, bucketCallbacks = 0, nil, 0, 0, 0

local function Elapsed() return (clock() - cfg.t0) / 1000 end

local function Allowed(id)
    local filter = cfg.filter
    if not filter then return true end
    for _, prefix in ipairs(filter) do
        if id:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function NewOp(id)
    if opCount >= I.MAX_OPS then dropped.ops = dropped.ops + 1 return nil end
    opCount = opCount + 1
    local op = { id = id, calls = 0, total = 0, self = 0, max = 0, min = math.huge, hist = Hist.New(), aborted = 0,
        reentered = 0, active = 0, ex = {}, parents = {}, parentN = 0, first = nil, last = nil, alloc = 0, allocSelf = 0, allocMax = 0,
        winStart = 0, winCount = 0, peakWin = 0, allowed = Allowed(id) }
    ops[id] = op
    return op
end

-- the frames above `to` never reached their Stop
local function Unwind(to)
    for d = depth, to + 1, -1 do
        local op = sOp[d]
        op.active = op.active - 1
        op.aborted = op.aborted + 1
        anomalies.aborted = anomalies.aborted + 1
        local cb = sCb[d]
        if cb then cb.aborted = cb.aborted + 1 end
        sOp[d], sCb[d], sDetail[d] = nil, nil, nil
    end
    depth = to
end

-- A call path for a slow call: TwichUI's own files, folder-relative, at most 6 lines. Never another addon's text.
local function Stack()
    if type(debugstack) ~= "function" then return nil end
    local ok, text = pcall(debugstack, 5, 8, 0)   -- 5: the code that ended the scope (Stack, Exemplar, Record, Stop above it)
    if not ok or type(text) ~= "string" then return nil end
    local out = {}
    for line in text:gmatch("[^\n]+") do
        local file, at = line:match("AddOns[\\/](TwichUI[%w_]*[\\/][^\"%]:]+)\"?%]?:(%d+)")
        if not file then file, at = line:match("AddOns[\\/](!!!TwichUI[\\/][^\"%]:]+)\"?%]?:(%d+)") end
        if file then
            out[#out + 1] = file:gsub("\\", "/") .. ":" .. at
            if #out >= 6 then break end
        elseif #out > 0 and out[#out] ~= "(other code)" then
            out[#out + 1] = "(other code)"
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, " < ")
end

local function Exemplar(op, ms, at, detail, parent)
    local ex = op.ex
    local n = #ex
    if n >= I.EXEMPLARS and ms <= ex[n].ms then return end
    local e = { ms = ms, at = at, detail = DX.Num(detail), parent = parent, combat = DX.InCombat() }
    if cfg.stacks and (n == 0 or ms > ex[1].ms) and at - lastStackAt >= I.STACK_EVERY then
        lastStackAt = at
        e.stack = Stack()
    end
    if n >= I.EXEMPLARS then ex[n] = nil end
    local i = #ex
    while i >= 1 and ex[i].ms < ms do ex[i + 1] = ex[i]; i = i - 1 end
    ex[i + 1] = e
end

local function Record(op, ms, self, detail, parentOp, alloc, allocSelf)
    op.calls = op.calls + 1
    if op.active == 0 then op.total = op.total + ms; op.alloc = op.alloc + alloc else op.reentered = op.reentered + 1 end
    op.self = op.self + self
    op.allocSelf = op.allocSelf + allocSelf
    if alloc > op.allocMax then op.allocMax = alloc end
    if ms > op.max then op.max = ms end
    if ms < op.min then op.min = ms end
    Hist.Add(op.hist, ms)
    local at = Elapsed()
    op.first = op.first or at
    op.last = at
    if at - op.winStart >= I.WINDOW then op.winStart, op.winCount = at, 0 end
    op.winCount = op.winCount + 1
    if op.winCount > op.peakWin then op.peakWin = op.winCount end
    if parentOp then
        local p = op.parents
        local pid = parentOp.id
        if p[pid] then p[pid] = p[pid] + 1
        elseif op.parentN < I.MAX_PARENTS then p[pid] = 1; op.parentN = op.parentN + 1 end
    end
    local ex = op.ex
    if #ex < I.EXEMPLARS or ms > ex[#ex].ms then Exemplar(op, ms, at, detail, parentOp and parentOp.id) end
end

---------------------------------------------------------------------------
-- What R.Perf calls while recording
---------------------------------------------------------------------------
local function Push(op, detail, cb)
    local ft = GetTime()
    if depth > 0 and sFrame[depth] ~= ft then
        anomalies.crossedFrame = anomalies.crossedFrame + 1
        Unwind(0)
    end
    if depth >= I.MAX_DEPTH then dropped.depth = dropped.depth + 1 return nil end
    depth = depth + 1
    serial = serial + 1
    sOp[depth], sChild[depth], sFrame[depth], sSerial[depth], sDetail[depth], sCb[depth] = op, 0, ft, serial, detail, cb
    sChildHeap[depth] = 0
    op.active = op.active + 1
    sHeap[depth] = heapCount and heapCount("count") or 0
    sStart[depth] = clock()   -- last, so the bookkeeping above is not in the measurement
    return serial
end

function I.Start(id, detail)
    if not active or type(id) ~= "string" then return nil end
    local op = ops[id] or NewOp(id)
    if not op or not op.allowed then return nil end
    return Push(op, detail, nil)
end

function I.Callback(event, fn, slot)
    if not active then return nil end
    local ev = events[event]
    if not ev then return nil end   -- not counted as received (over the limit)
    local op = ev.op
    if op == false then return nil end   -- over the operation limit: counted once, when it was refused
    if not op then
        op = ops["event:" .. event] or NewOp("event:" .. event)
        ev.op = op or false
        if not op then return nil end
    end
    if not op.allowed then return nil end
    local cb = callbacks[fn]
    if not cb then
        if callbackCount >= I.MAX_CALLBACKS then dropped.callbacks = dropped.callbacks + 1
        else
            callbackCount = callbackCount + 1
            cb = { event = event, slot = slot, calls = 0, total = 0, self = 0, max = 0, aborted = 0, n = callbackCount }
            callbacks[fn] = cb
            cbList[#cbList + 1] = cb
        end
    end
    bucketCallbacks = bucketCallbacks + 1
    return Push(op, slot, cb)
end

function I.Stop(token)
    local now = clock()
    local heap = heapCount and heapCount("count") or 0
    if not active or not token then return end
    local d = depth
    while d > 0 and sSerial[d] ~= token do d = d - 1 end
    if d == 0 then anomalies.stale = anomalies.stale + 1 return end
    if d < depth then Unwind(d) end
    local op, cb = sOp[d], sCb[d]
    local elapsed = now - sStart[d]
    depth = d - 1
    op.active = op.active - 1
    sOp[d], sCb[d] = nil, nil
    if elapsed < 0 then   -- the clock went back (debugprofilestop after someone's debugprofilestart)
        anomalies.clockBack = anomalies.clockBack + 1
        return
    end
    local self = elapsed - sChild[d]
    if self < 0 then self = 0 end
    local alloc = heap - sHeap[d]
    if alloc < 0 then alloc = 0 end
    local allocSelf = alloc - sChildHeap[d]
    if allocSelf < 0 then allocSelf = 0 end
    local parent = nil
    if depth > 0 then
        sChild[depth] = sChild[depth] + elapsed
        sChildHeap[depth] = sChildHeap[depth] + alloc
        parent = sOp[depth]
    else
        frameWork = frameWork + elapsed
        if elapsed > frameTopMs then frameTop, frameTopMs = op.id, elapsed end
    end
    Record(op, elapsed, self, sDetail[d], parent, alloc, allocSelf)
    sDetail[d] = nil
    if cb then
        cb.calls = cb.calls + 1
        cb.total = cb.total + elapsed
        cb.self = cb.self + self
        if elapsed > cb.max then cb.max = elapsed end
    end
end

function I.Received(event, list)
    if not active then return end
    local ev = events[event]
    if not ev then
        if eventCount >= I.MAX_EVENTS then dropped.events = dropped.events + 1 return end
        eventCount = eventCount + 1
        ev = { received = 0, op = nil, listeners = 0 }
        events[event] = ev
    end
    ev.received = ev.received + 1
    local n = 0
    for i = 1, #list do if list[i] then n = n + 1 end end
    if n > ev.listeners then ev.listeners = n end
    bucketEvents = bucketEvents + 1
end

function I.Count(id, n)
    if not active or type(id) ~= "string" then return end
    local c = counters[id]
    if c == nil then
        if counterCount >= I.MAX_COUNTERS then dropped.counters = dropped.counters + 1 return end
        counterCount = counterCount + 1
        c = 0
    end
    counters[id] = c + (type(n) == "number" and n or 1)
end

-- Perf.Call in a focused trace that measures allocation: the client's MeasureCall around the call. Its results are
-- handed back exactly as the call returned them.
local measured = {}   -- [id] = { calls, allocated, deallocated }
local function MeasureFinish(id, results, ...)
    if type(results) == "table" then
        local m = measured[id]
        if not m then m = { calls = 0, allocated = 0, deallocated = 0 }; measured[id] = m end
        m.calls = m.calls + 1
        m.allocated = m.allocated + (DX.Num(results.allocatedBytes) or 0)
        m.deallocated = m.deallocated + (DX.Num(results.deallocatedBytes) or 0)
    end
    return ...
end
local function Call(id, fn, ...)
    if not active then return fn(...) end
    if cfg.allocation and C_AddOnProfiler and C_AddOnProfiler.MeasureCall then
        return Perf.Finish(I.Start(id), MeasureFinish(id, C_AddOnProfiler.MeasureCall(fn, ...)))
    end
    return Perf.Finish(I.Start(id), fn(...))
end
local function Finish(token, ...)
    I.Stop(token)
    return ...
end

---------------------------------------------------------------------------
-- Per frame (the frame sampler) and per bucket
---------------------------------------------------------------------------
-- The outermost instrumented work that ended since the last call: ms, the largest operation's id and its ms.
-- Called from the frame sampler's OnUpdate, where no TwichUI scope can be running: one still open was left by an
-- error (no scope around it caught it) and is let go here, counted as aborted.
function I.TakeFrame()
    if depth > 0 then Unwind(0) end
    local w, top, topMs = frameWork, frameTop, frameTopMs
    frameWork, frameTop, frameTopMs = 0, nil, 0
    return w, top, topMs
end
function I.TakeBucket()
    local e, c = bucketEvents, bucketCallbacks
    bucketEvents, bucketCallbacks = 0, 0
    return e, c
end

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------
local function Reset()
    ops, opCount, events, eventCount = {}, 0, {}, 0
    callbacks, callbackCount, cbList = setmetatable({}, { __mode = "k" }), 0, {}
    counters, counterCount, measured = {}, 0, {}
    for k in pairs(dropped) do dropped[k] = 0 end
    for k in pairs(anomalies) do anomalies[k] = 0 end
    depth, serial, lastStackAt = 0, 0, -math.huge
    frameWork, frameTop, frameTopMs, bucketEvents, bucketCallbacks = 0, nil, 0, 0, 0
    for i = 1, I.MAX_DEPTH do sOp[i], sCb[i], sDetail[i] = nil, nil, nil end
end

local core   -- the core's own functions, put back when recording stops

-- options: { t0 = ms, stacks = bool, filter = { "npcs.", ... } or nil, allocation = bool }
function I.Begin(options)
    if not clock then return false, "no-clock" end
    Reset()
    cfg = options
    active = true
    if not core then
        core = { Start = Perf.Start, Stop = Perf.Stop, Count = Perf.Count, Callback = Perf.Callback,
            Received = Perf.Received, Finish = Perf.Finish, Call = Perf.Call }
    end
    Perf.Start, Perf.Stop, Perf.Count, Perf.Callback, Perf.Received = I.Start, I.Stop, I.Count, I.Callback, I.Received
    Perf.Finish, Perf.Call = Finish, Call
    Perf.on = true
    return true
end

-- Stops at once: the core's call sites go back to skipping, open scopes are let go (not counted), and the stub
-- functions return. What was collected stays for I.Results.
function I.End()
    Perf.on = false
    active = false
    if depth > 0 then Unwind(0) end   -- still open when recording stopped: never timed
    -- the core's own functions again (nothing of this addon is called while off)
    if core then
        Perf.Start, Perf.Stop, Perf.Count, Perf.Callback, Perf.Received = core.Start, core.Stop, core.Count, core.Callback, core.Received
        Perf.Finish, Perf.Call = core.Finish, core.Call
    end
end

function I.Active() return active end

-- The cost of one empty scope on this client, in ms: the mean of `n` Start/Stop pairs on an operation that is then
-- forgotten. Used to estimate how much the instrumentation itself added (calls x this).
function I.Calibrate(n)
    if not active then return nil end
    n = n or 200
    local before = clock()
    for _ = 1, n do I.Stop(I.Start("diagnostics.calibration")) end
    local per = (clock() - before) / n
    if ops["diagnostics.calibration"] then ops["diagnostics.calibration"] = nil; opCount = opCount - 1 end
    frameWork, frameTop, frameTopMs = 0, nil, 0
    return per > 0 and per or nil
end

---------------------------------------------------------------------------
-- Results: plain tables (no functions, frames or the stats objects themselves), for the session
---------------------------------------------------------------------------
local function OpRow(op)
    local parents = {}
    for id, n in pairs(op.parents) do parents[#parents + 1] = { id = id, calls = n } end
    table.sort(parents, function(a, b) if a.calls ~= b.calls then return a.calls > b.calls end return a.id < b.id end)
    local ex = {}
    for i, e in ipairs(op.ex) do ex[i] = { ms = e.ms, at = e.at, detail = e.detail, parent = e.parent, combat = e.combat, stack = e.stack } end
    -- a percentile is a bucket's upper edge: never reported above the largest call actually seen
    local function Pct(p)
        local v = Hist.Percentile(op.hist, p)
        if v and op.calls > 0 and v > op.max then v = op.max end
        return v
    end
    return {
        id = op.id, calls = op.calls, total = op.total, self = op.self, max = op.calls > 0 and op.max or nil,
        min = op.calls > 0 and op.min or nil, mean = op.calls > 0 and op.total / op.calls or nil,
        allocKB = op.alloc, allocSelfKB = op.allocSelf, allocMaxKB = op.allocMax,
        p50 = Pct(0.5), p95 = Pct(0.95), p99 = Pct(0.99),
        hist = Hist.Export(op.hist), aborted = op.aborted, reentered = op.reentered, first = op.first, last = op.last,
        peak10s = op.peakWin, parents = parents, exemplars = ex,
    }
end

function I.Results()
    local out = { ops = {}, events = {}, callbacks = {}, counters = {}, measured = {}, dropped = {}, anomalies = {} }
    for _, op in pairs(ops) do
        if op.calls > 0 or op.aborted > 0 then out.ops[#out.ops + 1] = OpRow(op) end
    end
    table.sort(out.ops, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.id < b.id end)
    for name, ev in pairs(events) do
        local op = ev.op and ops["event:" .. name]
        out.events[#out.events + 1] = { event = name, received = ev.received, maxListeners = ev.listeners,
            callbacks = op and op.calls or 0, total = op and op.total or 0, max = op and op.calls > 0 and op.max or nil }
    end
    table.sort(out.events, function(a, b) if a.received ~= b.received then return a.received > b.received end return a.event < b.event end)
    for _, cb in ipairs(cbList) do
        out.callbacks[#out.callbacks + 1] = { label = ("%s listener #%d"):format(cb.event, cb.slot or 0), event = cb.event,
            calls = cb.calls, total = cb.total, self = cb.self, max = cb.calls > 0 and cb.max or nil, aborted = cb.aborted }
    end
    table.sort(out.callbacks, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.label < b.label end)
    for id, n in pairs(counters) do out.counters[#out.counters + 1] = { id = id, count = n } end
    table.sort(out.counters, function(a, b) return a.id < b.id end)
    for id, m in pairs(measured) do out.measured[#out.measured + 1] = { id = id, calls = m.calls, allocatedBytes = m.allocated, deallocatedBytes = m.deallocated } end
    for k, v in pairs(dropped) do out.dropped[k] = v end
    for k, v in pairs(anomalies) do out.anomalies[k] = v end
    return out
end

-- Live figures for the window while recording (cheap: no sorting of exemplars, no copies of histograms).
function I.Live()
    local list = {}
    for _, op in pairs(ops) do
        if op.calls > 0 then list[#list + 1] = { id = op.id, calls = op.calls, total = op.total, self = op.self, max = op.max, allocKB = op.alloc } end
    end
    return list, eventCount, callbackCount
end
