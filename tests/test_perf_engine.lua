dofile(TESTS .. "harness.lua")
-- TwichUI Diagnostics (TwichUI_Diagnostics/, load on demand) and the core's R.Perf points: timing and units, nested
-- inclusive and self time, re-entry, aborted scopes, a clock that steps back, events against callbacks, histograms
-- and rings, the frame sampler (long frames and discontinuities), repeated start and stop, time limits, profile
-- changes, findings and their evidence, comparisons, JSON and its pieces, redaction, size limits, the armed start-up,
-- and the instrumentation while off. The clock is the test's (CLOCK, in seconds), so every timing is exact.
-- Synthetic: these figures say nothing about the game; docs/diagnostics.md has the in-game checks.

local function Has(text, needle) return text:find(needle, 1, true) ~= nil end

---------------------------------------------------------------------------
-- A minimal JSON reader, here only, to check what the addon writes is valid JSON
---------------------------------------------------------------------------
local function DecodeJson(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value
  local function str()
    assert(s:sub(i, i) == '"', "string at " .. i)
    i = i + 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      assert(c ~= "", "unterminated string")
      if c == '"' then i = i + 1 break end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if e == "u" then out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) % 256); i = i + 6
        else assert(map[e], "bad escape " .. e); out[#out + 1] = map[e]; i = i + 2 end
      else
        assert(c:byte() >= 32, "control character in a string")
        out[#out + 1] = c; i = i + 1
      end
    end
    return table.concat(out)
  end
  value = function()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i = i + 1; ws()
      local t = {}
      if s:sub(i, i) == "}" then i = i + 1 return t end
      while true do
        ws(); local k = str(); ws()
        assert(s:sub(i, i) == ":", "colon at " .. i); i = i + 1
        t[k] = value(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "}" then return t end
        assert(d == ",", "comma at " .. (i - 1))
      end
    elseif c == "[" then
      i = i + 1; ws()
      local t = {}
      if s:sub(i, i) == "]" then i = i + 1 return t end
      while true do
        t[#t + 1] = value(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "]" then return t end
        assert(d == ",", "comma in array at " .. (i - 1))
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      assert(num and num ~= "", "value at " .. i .. ": " .. s:sub(i, i + 20))
      i = i + #num
      return tonumber(num)
    end
  end
  local v = value(); ws()
  assert(i > #s, "trailing text at " .. i)
  return v
end

---------------------------------------------------------------------------
-- A client with TwichUI and TwichUI Diagnostics
---------------------------------------------------------------------------
local function DiagFiles()
  local list = {}
  for line in io.lines(ROOT .. "../TwichUI_Diagnostics/TwichUI_Diagnostics.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = "../TwichUI_Diagnostics/" .. line:gsub("\\", "/") end
  end
  return list
end

CLOCK = 100          -- seconds (GetTimePreciseSec)
FRAME = 1            -- the frame's time (GetTime)
PROF = {}            -- the client profiler's LastTime per addon (ms); PROF.all for every addon
COUNTS = {}          -- the profiler's cumulative counters: COUNTS[addon][metric]
MEM = { ["!!!TwichUI"] = 1000, TwichUI_Diagnostics = 200 }
local profileStarts = 0

local function boot(name, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI", "TwichUI_Settings", "TwichUI_Diagnostics" })
  CLIENTS[name] = c
  c.TwichUIDB = opts.db or {}
  c.TwichUIDiagnosticsDB = opts.diagDB   -- what the game would load with TwichUI_Diagnostics
  c.printed = {}
  c.print = function(s) c.printed[#c.printed + 1] = tostring(s) end
  c.HANDLED = {}
  c.geterrorhandler = function() return function(e) c.HANDLED[#c.HANDLED + 1] = e end end
  c.GetTimePreciseSec = function() return CLOCK end
  c.GetTime = function() return FRAME end
  c.debugprofilestart = function() profileStarts = profileStarts + 1 error("debugprofilestart must never be called") end
  c.UnitName = function() return "Rich" end
  c.GetGuildInfo = function() return "Secret Guild" end
  c.IsInInstance = function() return false, "none" end
  c.Enum = { AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, EncounterAverageTime = 2, LastTime = 3, PeakTime = 4,
    CountTimeOver1Ms = 5, CountTimeOver5Ms = 6, CountTimeOver10Ms = 7, CountTimeOver50Ms = 8, CountTimeOver100Ms = 9 } }
  local byMetric = {}
  for k, v in pairs(c.Enum.AddOnProfilerMetric) do byMetric[v] = k end
  c.C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetAddOnMetric = function(addon, m)
      if m == 3 then return PROF[addon] or 0 end
      return (COUNTS[addon] or {})[byMetric[m]] or 0
    end,
    GetOverallMetric = function(m) if m == 3 then return PROF.all or 0 end return (COUNTS.all or {})[byMetric[m]] or 0 end,
    MeasureCall = function(fn, ...) return { allocatedBytes = 128, deallocatedBytes = 0, elapsedMilliseconds = 0 }, fn(...) end,
  }
  c.UpdateAddOnMemoryUsage = function() end
  c.GetAddOnMemoryUsage = function(n) return MEM[n] or 0 end
  c.GetFramerate = function() return 60 end
  c.GetNumGroupMembers = function() return 0 end
  c.C_Timer.NewTimer = function(_, fn) return { Cancel = function() end } end
  c.UISpecialFrames = {}
  for _, f in ipairs({ "diag/Diagnostics.lua", "DiagnosticsLauncher.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.LOADS = 0
  c.C_AddOns.LoadAddOn = function(addon)
    if addon ~= "TwichUI_Diagnostics" then return false, "MISSING" end
    if not c.LOADED.TwichUI_Diagnostics then
      c.LOADS = c.LOADS + 1
      for _, f in ipairs(DiagFiles()) do local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("TwichUI_Diagnostics", {}) end
      c.LOADED.TwichUI_Diagnostics = true
      c.FireEvent("ADDON_LOADED", "TwichUI_Diagnostics")
    end
    return true
  end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  return c
end

local c = boot("Alpha")
local R = c.TwichUI
local Perf = R.Perf

---------------------------------------------------------------------------
-- 1. Off: nothing loads, R.Perf does nothing, and a scoped call is the call itself.
---------------------------------------------------------------------------
assert(c.LOADS == 0 and R.Diagnostics == nil, "TwichUI Diagnostics is not loaded in ordinary play")
assert(Perf.on == false)
local starts = 0
local realStart = Perf.Start
Perf.Start = function(...) starts = starts + 1 return realStart(...) end
local function three() return 1, nil, 3 end
local packed = { n = select("#", Perf.Call("x.y", three)), Perf.Call("x.y", three) }
assert(packed.n == 3 and packed[1] == 1 and packed[2] == nil and packed[3] == 3, "every result, nils too")
local errObj = { code = 7 }
local ok, err = pcall(Perf.Call, "x.y", function() error(errObj) end)
assert(not ok and err == errObj, "an error passes through unchanged")
local pt = Perf.on and Perf.Start("x.y")
assert(pt == false and starts == 0, "a call site does not call Start while off")
do
  local wrapped = Perf.Wrap("x.wrap", function(...) return ... end)
  local w = { n = select("#", wrapped(1, nil, 3)), wrapped(1, nil, 3) }
  assert(w.n == 3 and w[1] == 1 and w[2] == nil and w[3] == 3 and starts == 0, "Perf.Wrap while off: every result, no scope")
end
Perf.Start = realStart

-- the off cost, offline (Lua 5.1 here, not the game): a guarded call site against a bare one
do
  local n, t = 200000, os.clock()
  local function work() return 1 end
  for _ = 1, n do work() end
  local bare = os.clock() - t
  t = os.clock()
  for _ = 1, n do local p = Perf.on and Perf.Start("bench"); work(); if p then Perf.Stop(p) end end
  local guarded = os.clock() - t
  t = os.clock()
  for _ = 1, n do Perf.Call("bench", work) end
  local called = os.clock() - t
  print(("off cost (offline Lua 5.1, %d calls): bare %.1f ns, guarded site %.1f ns, Perf.Call %.1f ns per call"):format(n,
    bare / n * 1e9, guarded / n * 1e9, called / n * 1e9))
end

---------------------------------------------------------------------------
-- 2. Loading and starting
---------------------------------------------------------------------------
R.RunCommand("perf status")
assert(c.LOADS == 0 and Has(c.printed[#c.printed], "not loaded"), "status does not load it")
assert(R.DiagnosticsLauncher.Load() == true and c.LOADS == 1)
local DX = R.Diagnostics
assert(DX and DX.DB(), "loaded, with its saved variables")
assert(DX.State() == "stopped" and not DX.Recording(), "stopped until started")
assert(DX.prefs.badge == true and DX.Merge({ a = true }, nil).a == true and DX.Merge({ a = true }, { a = false }).a == false
  and DX.Merge({ n = 5 }, { n = "x" }).n == 5, "defaults kept, a saved false kept, a wrong type refused")
assert(DX.SetPref("badge", false) and c.TwichUIDiagnosticsDB.prefs.badge == false, "a preference is kept in saved variables")
-- (the badge needs real frames: test_perf_window.lua has them)
local caps = DX.Capabilities()
assert(DX.Capability("clock", caps).provenance == "GetTimePreciseSec", "the clock nothing can reset")
assert(DX.Capability("profiler", caps).state == "available")
assert(DX.Capability("legacyCpu", caps).state == "unavailable", "no scriptProfile known: unavailable, not assumed")

local okStart = DX.Start("general", { note = "Rich opened the map |Hitem:1|h[Thing]|h near Secret Guild" })
assert(okStart and DX.Recording() and Perf.on == true, "recording: R.Perf is on")
assert(select(2, DX.Start("general")) == "already-recording")

---------------------------------------------------------------------------
-- 3. Nested scopes: inclusive and self time
---------------------------------------------------------------------------
local function Tick(ms) CLOCK = CLOCK + ms / 1000 end
local o = Perf.Start("test.outer")
Tick(2)
local i1 = Perf.Start("test.inner")
Tick(4)
Perf.Stop(i1)
Tick(4)
Perf.Stop(o)
-- re-entry: test.again inside itself
local a1 = Perf.Start("test.again")
Tick(1)
local a2 = Perf.Start("test.again")
Tick(3)
Perf.Stop(a2)
Tick(1)
Perf.Stop(a1)
-- an error went through a scope: it never stopped; the one around it still counts
local outerE = Perf.Start("test.caller")
Tick(1)
pcall(function() local x = Perf.Start("test.fails"); Tick(5); error("boom") end)
Tick(1)
Perf.Stop(outerE)
-- a scope left open into the next frame is let go when the next frame starts one
local dangling = Perf.Start("test.dangling")
FRAME = FRAME + 1
local fresh = Perf.Start("test.fresh"); Tick(1); Perf.Stop(fresh)
Perf.Stop(dangling)   -- late: ignored
-- the clock steps back inside a scope: discarded and counted
local back = Perf.Start("test.back"); CLOCK = CLOCK - 0.01; Perf.Stop(back); CLOCK = CLOCK + 0.02
-- a scope while recording keeps every result and passes errors through unchanged
local r = { n = select("#", Perf.Call("test.call", three)), Perf.Call("test.call", three) }
assert(r.n == 3 and r[2] == nil and r[3] == 3, "Perf.Call while recording: every result")
local ok2, err2 = pcall(Perf.Call, "test.call", function() error(errObj) end)
assert(not ok2 and err2 == errObj, "Perf.Call while recording: the same error")

---------------------------------------------------------------------------
-- 4. Events: one received event, a callback per listener
---------------------------------------------------------------------------
local seen = 0
local l1 = function() seen = seen + 1; Tick(1) end
local l2 = function() seen = seen + 1 end
local l3 = function() seen = seen + 1; local s = Perf.Start("test.inEvent"); Tick(2); Perf.Stop(s) end
R:On("TEST_EVENT", l1); R:On("TEST_EVENT", l2); R:On("TEST_EVENT", l3); R:On("TEST_EVENT", l1)   -- l1 twice: one registration
c.FireEvent("TEST_EVENT")
c.FireEvent("TEST_EVENT")
assert(seen == 6, "three listeners, twice")
DX.Mark("Rich pressed the button")

---------------------------------------------------------------------------
-- 5. Frames: the sampler (long frames, a discontinuity), memory and gauges
---------------------------------------------------------------------------
local frame = DX.Collect.Frame()
assert(frame and frame.scripts.OnUpdate, "the sampler runs only while recording")
local function Frame(ms, coreMs)
  PROF["!!!TwichUI"] = coreMs or 0.2
  PROF.TwichUI_Diagnostics = 0.05
  PROF.all = (coreMs or 0.2) + 1
  CLOCK = CLOCK + ms / 1000
  FRAME = FRAME + 1
  if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, ms / 1000) end
end
for _ = 1, 30 do Frame(16) end
Frame(80, 60)          -- a long frame, mostly TwichUI by the client's count
for _ = 1, 10 do Frame(16) end
Frame(2500)            -- a pause: left out
for _ = 1, 60 do Frame(16) end
MEM["!!!TwichUI"] = 1300

---------------------------------------------------------------------------
-- 6. Stopping: put together after the frame, never in it
---------------------------------------------------------------------------
assert(DX.Stop("manual"))
assert(Perf.on == false and DX.State() == "finishing", "collection stopped at once")
assert(frame.scripts.OnUpdate == nil and next(frame.events) == nil, "the sampler and its events are removed")
assert(Perf.Start("x") == nil, "the core's own stubs are back")
FlushTimers()
assert(DX.State() == "stopped")
local rec = DX.Sessions()[#DX.Sessions()]
assert(rec and rec.stopReason == "manual" and rec.duration > 0)
local function Op(id) for _, op in ipairs(rec.ops) do if op.id == id then return op end end end
local outer, inner = Op("test.outer"), Op("test.inner")
assert(math.abs(outer.total - 10) < 1e-6 and math.abs(outer.self - 6) < 1e-6, "outer: 10 ms inclusive, 6 ms self")
assert(math.abs(inner.total - 4) < 1e-6 and math.abs(inner.self - 4) < 1e-6, "inner: 4 ms")
local again = Op("test.again")
assert(again.calls == 2 and again.reentered == 1 and math.abs(again.total - 5) < 1e-6, "re-entry counted once in the total")
assert(math.abs(again.self - 5) < 1e-6, "self times of the two activations add up to the outer's time")
assert(Op("test.fails").aborted == 1 and Op("test.fails").calls == 0, "a scope an error went through is aborted, not timed")
assert(math.abs(Op("test.caller").total - 7) < 1e-6, "the scope around it still counts")
assert(Op("test.dangling").aborted == 1 and rec.anomalies.crossedFrame == 1 and rec.anomalies.stale >= 1, "a scope can't outlast its frame")
assert(rec.anomalies.clockBack == 1 and Op("test.back") == nil, "a backward clock step is discarded (the operation has no timed call)")
assert(Op("test.call").calls == 2 and Op("test.call").aborted == 1, "Perf.Call: one returned, one errored")
assert(profileStarts == 0, "debugprofilestart was never called")
local ev
for _, e in ipairs(rec.events) do if e.event == "TEST_EVENT" then ev = e end end
assert(ev and ev.received == 2 and ev.callbacks == 6 and ev.maxListeners == 3, "2 received, 6 callbacks, 3 listeners")
local cbs = 0
for _, cb in ipairs(rec.callbacks) do if cb.event == "TEST_EVENT" then cbs = cbs + 1; assert(cb.calls == 2) end end
assert(cbs == 3, "each listener separately")
local evOp = Op("event:TEST_EVENT")
assert(evOp.calls == 6 and math.abs(evOp.total - 6) < 1e-6 and math.abs(evOp.self - 2) < 1e-6, "event callbacks: 6 ms inclusive, the inner scope's 4 ms taken from self")
assert(Op("test.inEvent").parents[1].id == "event:TEST_EVENT", "the caller is recorded")
assert(rec.frames.spikeCount == 1 and #rec.frames.gaps == 1, "one long frame, one discontinuity")
assert(rec.frames.count == 101, "the pause is left out of the frame count")
local sp = rec.frames.spikes[1]
assert(sp.dt == 80 and sp.core == 60 and #sp.before == 5 and #sp.after == 5, "a long frame keeps its neighbours")
assert(rec.frames.p50 >= 16 and rec.frames.p50 <= 16 * 1.19 + 0.01, "the median frame interval, approximate (log bucket)")
assert(rec.memory[1].core == 1000 and rec.memory[#rec.memory].core == 1300, "memory read at the start and the stop")
assert(rec.timeline.n >= 4, "a bucket per second")
local manual
for _, m in ipairs(rec.markers) do if m.kind == "manual" then manual = m end end
assert(manual and not Has(manual.label, "Rich"), "a marker's text has the character's name replaced")
assert(rec.note and not Has(rec.note, "Rich") and not Has(rec.note, "Secret Guild") and not Has(rec.note, "|H"), "the note, cleaned")
for _, f in ipairs(rec.findings) do
  assert(f.category and f.severity and f.basis and f.evidence and f.confidence and f.verify and f.window, "every finding is complete: " .. tostring(f.id))
end
local function Finding(list, id) for _, f in ipairs(list) do if f.id == id then return f end end end
assert(Finding(rec.findings, "long-frames-with-twichui"), "the long frame is associated by the client's count")
assert(Finding(rec.findings, "coverage"), "short capture and the discontinuity are stated")

---------------------------------------------------------------------------
-- 7. Repeated start and stop: one frame, no listeners left, bounded sessions
---------------------------------------------------------------------------
for n = 1, 6 do
  assert(DX.Start("general"))
  Frame(16)
  if n % 2 == 0 then DX.Stop("manual") else DX.Cancel() end
  FlushTimers()
  assert(DX.Collect.Frame() == frame and frame.scripts.OnUpdate == nil and Perf.on == false)
end
assert(#DX.Sessions() <= DX.prefs.keepInMemory, "finished captures are bounded")
-- a time limit stops it by itself
assert(DX.Start("general", { minutes = 0.25 }))
for _ = 1, 20 do Frame(1000 - 1) end
assert(DX.State() ~= "recording", "stopped at its length")
FlushTimers()
assert(DX.Sessions()[#DX.Sessions()].stopReason == "time-limit")
-- stopped in combat: put together only when combat ends
assert(DX.Start("general"))
c.InCombatLockdown = function() return true end
Frame(16)
DX.Stop("manual")
FlushTimers()
assert(DX.State() == "finishing", "nothing is put together in combat")
c.InCombatLockdown = function() return false end
c.FireEvent("PLAYER_REGEN_ENABLED")
assert(DX.State() == "stopped", "put together when combat ends")
-- a profile change while recording is a marker, and the capture carries on
assert(DX.Start("general"))
R.Profiles.Create("Second")
Frame(16)
DX.Stop("manual"); FlushTimers()
local pc = false
for _, m in ipairs(DX.Sessions()[#DX.Sessions()].markers) do if m.kind == "profile-changed" then pc = true end end
assert(pc, "profile change marked")

---------------------------------------------------------------------------
-- 8. Histogram, ring, merge
---------------------------------------------------------------------------
local H = DX.Hist.New()
for _ = 1, 99 do DX.Hist.Add(H, 1) end
DX.Hist.Add(H, 100)
local p50, p99 = DX.Hist.Percentile(H, 0.5), DX.Hist.Percentile(H, 0.995)
assert(p50 >= 1 and p50 <= 1.19 + 1e-9 and p99 >= 100 and p99 <= 119, "percentiles from buckets, within one bucket")
local ring = DX.Ring.New(3)
for k = 1, 5 do DX.Ring.Push(ring, k) end
local list = DX.Ring.List(ring)
assert(ring.dropped == 2 and #list == 3 and list[1] == 3 and list[3] == 5, "the oldest go first, counted")
local tl = { n = 10, t = {}, frames = {}, dtMax = {} }
for _, f in ipairs(DX.Collect.FIELDS) do tl[f] = tl[f] or {} end
for k = 1, 10 do tl.t[k] = k - 1; tl.frames[k] = 60; tl.dtMax[k] = k == 7 and 300 or 17 end
local merged, by = DX.MergeTimeline(tl, 3)
assert(by == 4 and merged.n == 3 and merged.frames[1] == 240 and merged.dtMax[2] == 300, "merged: sums added, the worst kept")

---------------------------------------------------------------------------
-- 9. Findings from evidence (a synthetic capture: these rules on known numbers)
---------------------------------------------------------------------------
local function Synthetic(over)
  local s = { schema = DX.REPORT_SCHEMA, uid = "syn-" .. tostring(over.uid or 1), preset = "map", presetName = "Map and NPC tracking", mode = "standard",
    duration = 120, config = { spikeMs = 50, profiler = true }, env = { build = "1", addons = {}, modulesOn = { "npcMap" }, configFingerprint = "a" },
    ops = {}, events = {}, frames = { count = 7200, spikes = {}, spikeCount = 0, gaps = {}, p50 = 16, p95 = 20, p99 = 30 }, memory = {},
    gauges = { defs = {}, samples = {} }, timeline = { n = 0 }, profiler = {}, overhead = {}, errorCount = 0, maxGroup = 0 }
  for k, v in pairs(over) do s[k] = v end
  return s
end
local busy = Synthetic({ ops = { { id = "npcs.map.layout", calls = 120, total = 240, self = 240, mean = 2, max = 9, peak10s = 12, first = 0, last = 119, exemplars = {} } } })
local fs = DX.Findings.Run(busy)
local fr = Finding(fs, "frequent-rebuild")
assert(fr and Has(fr.basis, "60 per minute") and Has(fr.evidence[1], "120 calls"), "a frequent layout, with its numbers")
assert(Finding(fs, "dominant-operation"), "and it is all of the measured work")
local cyc = Synthetic({ gauges = { defs = { { id = "core.listeners", label = "TwichUI event bus: listeners", kind = "listeners" } },
  samples = { { t = 1, v = { 40 }, cycle = "settings-closed" }, { t = 2, v = { 42 }, cycle = "settings-closed" }, { t = 3, v = { 44 }, cycle = "settings-closed" },
    { t = 4, v = { 46 }, cycle = "settings-closed" } } } })
local lg = Finding(DX.Findings.Run(cyc), "listener-growth")
assert(lg and lg.confidence == "suspicion" and Has(lg.evidence[1], "40, 42, 44, 46"), "listener growth over cycles is a suspicion with its readings")
local one = Synthetic({ memory = { { t = 0, core = 1000 }, { t = 60, core = 1700 } } })
assert(not Finding(DX.Findings.Run(one), "memory-rose"), "two readings are never called a rise")
local low = Synthetic({ frames = { count = 100, spikes = { { t = 5, dt = 90, core = 1, work = 0 } }, spikeCount = 1, gaps = {} } })
assert(Finding(DX.Findings.Run(low), "long-frames-unattributed") and not Finding(DX.Findings.Run(low), "long-frames-with-twichui"),
  "a long frame without TwichUI time is not put on TwichUI")
local reset = Synthetic({ profiler = { start = { core = { CountTimeOver5Ms = 9, CountTimeOver50Ms = 1 } }, finish = { core = { CountTimeOver5Ms = 2, CountTimeOver50Ms = 0 } } } })
assert(Finding(DX.Findings.Run(reset), "profiler-reset") and not Finding(DX.Findings.Run(reset), "profiler-over-5ms"), "a counter that went down is not used")

---------------------------------------------------------------------------
-- 10. Comparisons are normalised
---------------------------------------------------------------------------
local A = Synthetic({ uid = "A", duration = 60, ops = { { id = "npcs.search", calls = 30, total = 30, self = 30, mean = 1, p95 = 2 } } })
local B = Synthetic({ uid = "B", duration = 120, ops = { { id = "npcs.search", calls = 60, total = 60, self = 60, mean = 1, p95 = 2 },
  { id = "pins.map.layout", calls = 5, total = 10, self = 10, mean = 2 } } })
local cmp = DX.Compare.Run(A, B)
assert(cmp.compatible and Has(table.concat(cmp.warnings, " "), "Lengths differ") == false, "same rate, 1 and 2 minutes: comparable")
local search, layout
for _, row in ipairs(cmp.ops) do if row.id == "npcs.search" then search = row elseif row.id == "pins.map.layout" then layout = row end end
assert(search.calls.a == 30 and search.calls.b == 30 and search.calls.delta == 0 and search.total.direction == "same",
  "a longer capture with the same rate is not 'more' or 'faster'")
assert(layout.calls.change == "new" and layout.calls.pct == nil, "a zero baseline has no percentage")
assert(search.mean and search.mean.delta == 0, "per call compared with enough calls")
assert(layout.note and Has(layout.note, "too few calls"), "tiny samples say so")
local C2 = Synthetic({ uid = "C", preset = "settings", presetName = "Settings responsiveness", duration = 400 })
local cw = table.concat(DX.Compare.Run(A, C2).warnings, " ")
assert(Has(cw, "Different presets") and Has(cw, "Lengths differ"), "incomparable conditions are flagged")
local D2 = Synthetic({ uid = "D", schema = 99 })
assert(DX.Compare.Run(A, D2).compatible == false, "a different report layout is refused")

---------------------------------------------------------------------------
-- 11. Exports: valid JSON, redaction, pieces that join back, size limits
---------------------------------------------------------------------------
local first = rec   -- the capture from sections 3 to 6 (kept here: later captures pushed it out of the session list)
local built = DX.Export.Build("full", first, nil, DX.Export.Defaults())
local report = DecodeJson(built.text)
assert(report.schema == DX.REPORT_SCHEMA and report.kind == "twichui-diagnostics-report" and report.units.duration == "ms", "a versioned report with units")
assert(report.redaction.characterNames and report.truncation and report.capabilities[1].provenance, "redaction, truncation and capabilities")
assert(report.userNotes.untrusted == true, "your notes are marked untrusted")
for _, word in ipairs({ "Rich", "Secret Guild", "|H", "Interface/AddOns", "C:\\" }) do
  assert(not Has(built.text, word), "the full report leaves out " .. word)
end
local summary = DX.Export.Build("summary", first, nil, DX.Export.Defaults()).text
assert(Has(summary, "## Findings") and Has(summary, "## What this capture can't show") and not Has(summary, "Rich"), "the summary, redacted")
local noNotes = DX.Export.Build("summary", first, nil, { notes = false, traces = true, stacks = true }).text
assert(not Has(noNotes, "What I was doing") and Has(noNotes, "notes left out"), "notes can be left out")
local prompt = DX.Export.Build("prompt", first, nil, DX.Export.Defaults()).text
assert(Has(prompt, "untrusted data") and Has(prompt, "Measured facts and hypotheses stay apart") and Has(prompt, "Read the code before recommending a change"), "the prompt's rules")
assert(Has(prompt, "whether anything here is worth fixing") and Has(prompt, "how to validate it") and Has(prompt, "Constraints on any change"), "the prompt says when to stop, how to validate, and what a fix must keep")
local cmpText = DX.Export.Build("compare", B, A, DX.Export.Defaults())
assert(cmpText and Has(cmpText.text, "## Normalised differences"), "a comparison report")
local pieces = DX.Json.Pieces(built.text, 1000, "test")
assert(#pieces > 1 and pieces[1].header:find("piece 1/", 1, true))
local texts = {}
for k, p in ipairs(pieces) do texts[k] = p.text end
assert(DX.Json.Join(texts) == built.text, "the pieces join back exactly")
local swapped = { texts[2], texts[1] }
for k = 3, #texts do swapped[k] = texts[k] end
assert(DX.Json.Join(swapped) == nil, "out of order is refused")
local tampered = {}
for k, t in ipairs(texts) do tampered[k] = t end
tampered[1] = tampered[1]:sub(1, -2) .. "X"
assert(DX.Json.Join(tampered) == nil, "a changed piece is found")
local utf = DX.Json.Pieces(("é"):rep(600), 101, "utf")
for _, p in ipairs(utf) do assert(DecodeJson(DX.Json.String(p.body)) == p.body, "no character split between pieces") end
assert(DecodeJson(DX.Json.Encode({ s = "bad \255 byte\n\"q\"", n = 0 / 0, i = 2 ^ 40, f = 0.00012345 })).s == "bad ? byte\n\"q\"", "escaped, invalid bytes replaced")
local max = DX.Export.MAX_BYTES
DX.Export.MAX_BYTES = 3000
local small = DecodeJson(DX.Export.Json(first, DX.Export.Defaults()))
DX.Export.MAX_BYTES = max
assert(small.truncation.sizeLimit, "an export over the limit says what was left out")
c.InCombatLockdown = function() return true end
assert(DX.Export.Build("full", first) == nil, "no export is built in combat")
c.InCombatLockdown = function() return false end

---------------------------------------------------------------------------
-- 12. Saving: explicit, bounded, merged
---------------------------------------------------------------------------
assert(#c.TwichUIDiagnosticsDB.sessions == 0, "nothing saved unless you save")
assert(select(2, DX.Save(first.uid)) == "missing", "a capture no longer kept can't be saved")
local keep = DX.Sessions()[#DX.Sessions()]
assert(DX.Save(keep.uid))
local saved = c.TwichUIDiagnosticsDB.sessions[1]
assert(saved.uid == keep.uid and saved.timeline.n <= DX.SAVED_BUCKETS)
local function Plain(t, depth)
  for k, v in pairs(t) do
    assert(type(v) ~= "function" and type(v) ~= "userdata", "saved data holds plain values only: " .. tostring(k))
    if type(v) == "table" then assert(depth < 20); Plain(v, depth + 1) end
  end
end
Plain(c.TwichUIDiagnosticsDB, 0)
DX.Unsave(keep.uid)
assert(#c.TwichUIDiagnosticsDB.sessions == 0)

---------------------------------------------------------------------------
-- 13. Focused trace: only its subsystem, with allocation from the client when asked
---------------------------------------------------------------------------
assert(select(2, DX.Start("focused", {})) == "no-subsystem")
assert(DX.Start("focused", { subsystem = "npcs", allocation = true }))
local s1 = Perf.Start("npcs.search"); Tick(1); Perf.Stop(s1)
local s2 = Perf.Start("settings.page.layout"); Tick(1); Perf.Stop(s2)
Perf.Call("npcs.import", function() return 1 end)
Frame(16)
DX.Stop("manual"); FlushTimers()
local foc = DX.Sessions()[#DX.Sessions()]
local names = {}
for _, op in ipairs(foc.ops) do names[op.id] = op end
assert(names["npcs.search"] and not names["settings.page.layout"], "only the chosen subsystem is timed")
assert(foc.measured[1] and foc.measured[1].allocatedBytes == 128, "the client's allocation figure, when asked")

---------------------------------------------------------------------------
-- 14. The armed start-up: one reload, cleared as read; an old arming does nothing
---------------------------------------------------------------------------
local armed = boot("Beta", { db = { diagnosticsArm = { preset = "startup", at = os.time() } },
  diagDB = { version = 1, prefs = { badge = false } } })
local RB = armed.TwichUI
assert(armed.TwichUIDB.diagnosticsArm == nil, "cleared as it is read")
assert(RB.Diagnostics and RB.Diagnostics.Recording(), "recording from TwichUI's ADDON_LOADED")
local bootOps = {}
RB.Diagnostics.Stop("manual"); FlushTimers()
local brec = RB.Diagnostics.Sessions()[1]
for _, op in ipairs(brec.ops) do bootOps[op.id] = op end
assert(brec.boot and bootOps["core.savedData"] and bootOps["core.startupHook"], "saved data and start-up hooks were timed")
local obs = false
for _, m in ipairs(brec.markers) do if m.kind == "observation-begins" then obs = true end end
assert(obs, "the report says when observation began")
local stale = boot("Gamma", { db = { diagnosticsArm = { preset = "startup", at = os.time() - 7200 } } })
assert(stale.TwichUIDB.diagnosticsArm == nil and stale.TwichUI.Diagnostics == nil, "an old arming is cleared and loads nothing")
assert(Has(table.concat(stale.printed, "\n"), "was not started"), "and says so")


---------------------------------------------------------------------------
-- 15. The diagnostics' own cost is counted once, a hitch it caused is told from one it only saw, percentiles never
-- exceed the largest call, a scope's allocation is measured, and Perf.Wrap scopes a hook
---------------------------------------------------------------------------
do
  c.UpdateAddOnMemoryUsage = function() Tick(20) end   -- a 20 ms update, inside the sampler's frame
  assert(DX.Start("general"))
  assert(DX.Sessions()[#DX.Sessions()] ~= nil)
  Frame(16)            -- first frame: the memory and gauge reads happen in it
  Frame(65)            -- 65 ms, of which 20 ms was our read in the frame before: 45 ms without it
  for _ = 1, 10 do Frame(16) end
  local p1 = Perf.Start("t.pct"); Tick(0.385); Perf.Stop(p1)
  local wrapped = Perf.Wrap("t.wrap", function(...) Tick(1); return ... end)
  local w = { n = select("#", wrapped("a", nil, "c")), wrapped("a", nil, "c") }
  assert(w.n == 3 and w[1] == "a" and w[2] == nil and w[3] == "c", "Perf.Wrap while recording: every result")
  collectgarbage("stop")
  local outerTok = Perf.Start("t.alloc.outer")
  local keep = {}
  for i = 1, 1500 do keep[i] = { i } end
  local innerTok = Perf.Start("t.alloc.inner")
  local keep2 = {}
  for i = 1, 1500 do keep2[i] = { i } end
  Tick(1); Perf.Stop(innerTok); Perf.Stop(outerTok)
  collectgarbage("restart")
  DX.Stop("manual"); FlushTimers()
  local r15 = DX.Sessions()[#DX.Sessions()]
  local ov = r15.overhead
  assert(ov.exclusive == true and ov.memoryMs >= 20 and ov.memoryReads >= 1, "memory updates are timed: " .. tostring(ov.memoryMs))
  assert(ov.samplerMs < ov.memoryMs and ov.samplerMs < 1, "the sampler's own time does not contain the reads (" .. tostring(ov.samplerMs) .. " vs " .. tostring(ov.memoryMs) .. ")")
  local dg = DX.Findings.DiagnosticsCost(r15)
  assert(math.abs(dg.ownMs - (ov.samplerMs + ov.gaugeMs + ov.memoryMs + (ov.estimatedScopeMs or 0))) < 1e-6, "own cost is the four parts, once")
  local hit
  for _, sp in ipairs(r15.frames.spikes) do if sp.dt == 65 then hit = sp end end
  assert(hit and hit.diag >= 20 and hit.diagRead >= 20, "a long frame keeps what the diagnostics did in the frame before it")
  local ours = Finding(r15.findings, "long-frames-from-diagnostics")
  assert(ours and ours.severity == "medium" and Has(ours.title, "1 long frame"), "a frame our read lifted over the limit is said to be ours")
  assert(not Finding(r15.findings, "long-frames-with-twichui"))
  local pct
  for _, op in ipairs(r15.ops) do if op.id == "t.pct" then pct = op end end
  assert(pct and pct.p50 <= pct.max and pct.p95 <= pct.max and pct.p99 <= pct.max, "a percentile is never above the largest call")
  assert(r15.frames.max == 65 and r15.frames.p99 <= r15.frames.max, "nor a frame percentile")
  local outer, inner, wr
  for _, op in ipairs(r15.ops) do if op.id == "t.alloc.outer" then outer = op elseif op.id == "t.alloc.inner" then inner = op elseif op.id == "t.wrap" then wr = op end end
  assert(wr and wr.calls == 2, "Perf.Wrap records one scope per call (called twice above)")
  assert(outer.allocKB > 50 and inner.allocKB > 25, "allocation inside a scope: the heap rise")
  assert(outer.allocSelfKB < outer.allocKB - 20 and math.abs(inner.allocSelfKB - inner.allocKB) < 1e-9, "self allocation takes the instrumented child's off")
  local text = DX.Export.Build("summary", r15, nil, DX.Export.Defaults()).text
  for _, h in ipairs({ "## Context", "## Where TwichUI's CPU went", "## Memory", "## Checked and clear", "## Long frames", "## The diagnostics' own cost" }) do
    assert(Has(text, h), "the summary has " .. h)
  end
  local jr = DecodeJson(DX.Export.Build("full", r15, nil, DX.Export.Defaults()).text)
  assert(jr.analysis and jr.analysis.cpu and jr.analysis.memory and jr.analysis.diagnosticsCost and jr.analysis.checkedAndClear, "the full report carries the analysis")
  c.UpdateAddOnMemoryUsage = function() end
end

---------------------------------------------------------------------------
-- 16. A capture shaped like a real first one: little TwichUI CPU, most of it outside every scope, memory with a collection
-- in it, the diagnostics larger than TwichUI but small next to a frame
---------------------------------------------------------------------------
do
  local tl = { n = 300, cap = 305 }
  for _, f in ipairs(DX.Collect.FIELDS) do tl[f] = {} end
  for i = 1, 300 do
    tl.t[i] = i - 1; tl.frames[i] = 153; tl.core[i] = (i % 7 == 0) and 4.2 or 0.7; tl.work[i] = 0.04; tl.all[i] = 50
    tl.mapShown[i] = i > 100 and i <= 160 and 1 or 0; tl.settingsShown[i] = 0; tl.windowShown[i] = 0; tl.combat[i] = 0; tl.group[i] = 1; tl.fps[i] = 140
  end
  local mem = {}
  local series = { 18662, 21000, 24500, 28000, 31500, 35000, 38500, 42000, 45500, 49000, 52500, 56000, 59500, 63000, 66500, 71454, 45485, 46800, 48000, 49000, 45485 }
  for i, v in ipairs(series) do mem[i] = { t = (i - 1) * 15, core = v, heap = v * 3, diag = 3000 + i, cost = 26 } end
  local rec16 = Synthetic({ uid = "real", preset = "general", presetName = "General performance", duration = 300, minutes = 5, stopReason = "time-limit",
    config = { spikeMs = 50, profiler = true, memorySeconds = 15 }, timeline = tl, memory = mem,
    frames = { count = 45890, ms = 316000, spikes = { { t = 100, dt = 127, core = 0.3, work = 0, diag = 0.1, diagRead = 0 } }, spikeCount = 8, gaps = {}, p50 = 6.9, p95 = 8.2, p99 = 11.6, max = 127 },
    ops = { { id = "npcs.map.layout", calls = 28, total = 3.4, self = 3.4, mean = 0.122, p95 = 0.3, max = 0.385, allocSelfKB = 0, exemplars = {} },
            { id = "event:ADDON_LOADED", calls = 90, total = 2.9, self = 2.9, mean = 0.033, p95 = 0.01, max = 2.8, exemplars = {} } },
    scopeCalls = 235,
    overhead = { exclusive = true, samplerMs = 785, gaugeMs = 13.6, memoryMs = 559, memoryReads = 21, memoryWorst = 28.4, estimatedScopeMs = 0.643 },
    profiler = { start = { core = { CountTimeOver1Ms = 100, CountTimeOver5Ms = 10, CountTimeOver10Ms = 5, CountTimeOver50Ms = 0, CountTimeOver100Ms = 0, PeakTime = 12 } },
      finish = { core = { CountTimeOver1Ms = 130, CountTimeOver5Ms = 10, CountTimeOver10Ms = 5, CountTimeOver50Ms = 0, CountTimeOver100Ms = 0, PeakTime = 12 } } },
    env = { build = "70575", addons = {}, modulesOn = { "npcMap", "navigation" }, configFingerprint = "a" },
    gauges = { defs = { { id = "npcs.map.pool", label = "pool", kind = "pool", group = "map" } }, samples = { { t = 1, v = { 0 } }, { t = 299, v = { 7 } } } } })
  rec16.findings = DX.Findings.Run(rec16)
  local oh = Finding(rec16.findings, "diagnostics-overhead")
  assert(oh and oh.severity == "low", "larger than TwichUI but small next to a frame: low, not medium")
  assert(Has(oh.basis, "380%") and not Has(oh.basis, "540%"), "the four parts counted once: " .. oh.basis)
  assert(Has(table.concat(oh.evidence, " "), "reported nothing"), "a client figure of 0 for the diagnostics is not shown as measured")
  local un = Finding(rec16.findings, "unattributed-cpu")
  assert(un and un.severity == "low" and Has(un.title, "9"), "most CPU outside every scope is a finding of its own (" .. tostring(un and un.title) .. ")")
  local mf = Finding(rec16.findings, "memory-with-cache") or Finding(rec16.findings, "memory-rose")
  assert(mf and Has(table.concat(mf.evidence, " "), "the collector ran"), "the memory finding says a collection was seen")
  assert(mf.title:find("sizes are not measured", 1, true), "a pool of 7 frames is not offered as the explanation")
  local an = DX.Findings.Analyze(rec16)
  assert(an.memory.afterFall and an.memory.afterFall.to == 45485 and an.memory.peak.core == 71454, "largest fall found")
  assert(an.cpu.ticks.CountTimeOver5Ms == 0 and an.cpu.ticks.CountTimeOver1Ms == 30, "the client's tick counts are differences")
  assert(an.context.mapSeconds == 60 and an.context.fpsMedian == 140, "context from the timeline")
  local clearText = table.concat(an.clear, " | ")
  assert(Has(clearText, "no tick over 5 ms") and Has(clearText, "no error reached"), "what was checked and found clear is said")
  local firstNext = an.next[1]
  assert(firstNext and firstNext.subsystem == "updaters", "next: the per-frame updaters, when none ran")
  local text = DX.Export.Summary(rec16, DX.Export.Defaults())
  assert(Has(text, "outside every scope") and Has(text, "Code with no scope yet") and Has(text, "Suggested next captures") and Has(text, "Checked and clear"), "the summary says what to do next")
  if os.getenv("PERF_SHOW") then print(DX.Export.Prompt(rec16, DX.Export.Defaults())) end
  assert(Has(text, "## Where the code is") and Has(text, "npcs/Map.lua"), "operation ids are mapped to their files")
  assert(not Has(text, "Rich") and #text < 14000, "and stays short enough to paste (" .. #text .. " bytes)")
  assert(DX.Subsystem("updaters") and DX.Subsystem("hooks"), "focused subsystems for the updaters and the hooks")
  assert(DX.Op("npcs.minimap.tick").file == "npcs/Minimap.lua" and DX.Op("event:BAG_UPDATE").file == "Core.lua", "operation ids map to files")
end

---------------------------------------------------------------------------
-- 17. What the first real capture showed was missing: the navigation data's memory, an addon load named at the long
-- frame, instrumented work above the client's count, and a window's own opening taken for hidden work
---------------------------------------------------------------------------
do
  local function Timeline(n, mapOpenFrom, mapOpenTo)
    local tl = { n = n, cap = n + 5 }
    for _, f in ipairs(DX.Collect.FIELDS) do tl[f] = {} end
    for i = 1, n do
      tl.t[i] = i - 1; tl.frames[i] = 153; tl.core[i] = 1.7; tl.work[i] = 0.1; tl.all[i] = 6
      tl.mapShown[i] = (i >= mapOpenFrom and i <= mapOpenTo) and 1 or 0
      tl.settingsShown[i] = 0; tl.windowShown[i] = 0; tl.combat[i] = 0; tl.group[i] = 1; tl.fps[i] = 140
    end
    return tl
  end
  local function Rec(over)
    local base = { uid = "gap", preset = "general", presetName = "General performance", duration = 120, minutes = 2, stopReason = "time-limit",
      config = { spikeMs = 50, profiler = true, memorySeconds = 30 }, timeline = Timeline(120, 30, 58),
      frames = { count = 18000, ms = 120000, spikes = {}, spikeCount = 0, gaps = {}, p50 = 6.9, p95 = 8.2, p99 = 11.6, max = 20 },
      ops = {}, memory = {} }
    for k, v in pairs(over) do base[k] = v end
    return Synthetic(base)
  end
  local layout = { id = "npcs.map.layout", calls = 3, total = 2, self = 2, mean = 0.6, max = 0.5, first = 10, last = 58,
    exemplars = { { ms = 0.479, at = 58.4 } } }

  -- a call in the second the map closed is not work done while it was hidden; the same call with no marker near still is
  local closing = Rec({ ops = { layout }, markers = { { t = 30, kind = "map-shown" }, { t = 59, kind = "map-hidden" } } })
  assert(not Finding(DX.Findings.Run(closing), "hidden-work"), "a call in the second the window closed is not hidden work")
  local stray = Rec({ ops = { layout }, markers = { { t = 30, kind = "map-shown" } } })
  assert(Finding(DX.Findings.Run(stray), "hidden-work"), "without a marker for the closing it is still reported")

  -- the instrumented total beside the client's: not capped at 100%, and said to be an upper bound
  local over = Rec({ ops = { { id = "nav.ticker", calls = 100, total = 300, self = 300, mean = 3, max = 4, exemplars = {} } } })
  local an = DX.Findings.Analyze(over)
  assert(an.cpu.workShare == 1 and an.cpu.workRatio > 1.4 and an.cpu.overCounted, "the ratio is kept above 1 and flagged")
  local text = DX.Export.Summary(over, DX.Export.Defaults())
  assert(Has(text, "147%") or Has(text, "14"), "the summary states the real ratio")
  assert(Has(text, "upper bounds"), "and says what it means")
  local fine = Rec({ ops = { { id = "nav.ticker", calls = 100, total = 100, self = 100, mean = 1, max = 2, exemplars = {} } } })
  assert(not DX.Findings.Analyze(fine).cpu.overCounted and not Has(DX.Export.Summary(fine, DX.Export.Defaults()), "upper bounds"), "nothing said when the scopes fit inside the client's count")

  -- the navigation data addon's memory, a separate addon, is read out
  local nd = Rec({ memory = { { t = 0, core = 18000, navdata = 100 }, { t = 30, core = 20000, navdata = 25000 }, { t = 60, core = 21000, navdata = 25100 } } })
  assert(DX.Findings.Analyze(nd).memory.navdata.last == 25100, "the series is analysed")
  assert(Has(DX.Export.Summary(nd, DX.Export.Defaults()), "TwichUI_NavData"), "and appears in the report")
  assert(not Has(DX.Export.Summary(Rec({ memory = { { t = 0, core = 18000 }, { t = 30, core = 18100 } } }), DX.Export.Defaults()), "TwichUI_NavData"), "no line when it was never loaded")

  -- a long frame next to an addon of ours loading says which addon, and the markers list shows the load
  local lf = Rec({ markers = { { t = 64, kind = "addon-loaded", label = "TwichUI_NavData" } },
    frames = { count = 100, spikes = { { t = 64, dt = 97, core = 0.003, work = 3.9 } }, spikeCount = 1, gaps = {}, p50 = 7, p95 = 8, p99 = 11, max = 97 } })
  local lff = Finding(DX.Findings.Run(lf), "long-frames-unattributed")
  assert(lff and Has(table.concat(lff.evidence, " "), "addon-loaded TwichUI_NavData"), "the long frame names the addon that loaded")
  assert(Has(DX.Export.Summary(lf, DX.Export.Defaults()), "addon-loaded (TwichUI_NavData)"), "the Markers list includes addon loads")

  -- the load itself has a scope, so that frame is attributed
  assert(DX.Op("nav.load").file == "nav/Data.lua" and DX.Op("nav.load").kind == "init", "nav.load is in the catalogue")
  local C_AddOns = c.C_AddOns
  local old = { C_AddOns.DoesAddOnExist, C_AddOns.GetAddOnEnableState, C_AddOns.LoadAddOn, C_AddOns.IsAddOnLoaded }
  C_AddOns.DoesAddOnExist = function() return true end
  C_AddOns.GetAddOnEnableState = function() return 2 end
  C_AddOns.IsAddOnLoaded = function() return false end
  local asked = 0
  C_AddOns.LoadAddOn = function() asked = asked + 1; return true end
  local chunk = assert(loadfile(ROOT .. "nav/Data.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})   -- not part of this client's start-up
  assert(DX.Start("general"))
  Frame(16)
  local okLoad = R.NavData.Load()
  Frame(16)
  DX.Stop("manual"); FlushTimers()
  C_AddOns.DoesAddOnExist, C_AddOns.GetAddOnEnableState, C_AddOns.LoadAddOn, C_AddOns.IsAddOnLoaded = old[1], old[2], old[3], old[4]
  local lrec = DX.Sessions()[#DX.Sessions()]
  local loadOp
  for _, op in ipairs(lrec.ops) do if op.id == "nav.load" then loadOp = op end end
  assert(okLoad and asked == 1 and loadOp and loadOp.calls == 1, "loading the navigation data runs inside a nav.load scope")
end

assert(#c.HANDLED == 0, "no error reached the game's handler: " .. tostring(c.HANDLED[1]))
assert(#armed.HANDLED == 0, "none in the start-up capture either: " .. tostring(armed.HANDLED[1]))
print("PERF ENGINE TEST PASSED")
