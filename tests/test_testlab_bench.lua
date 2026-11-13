-- The benchmark framework (testing roadmap M7): TwichUI_TestLab/Bench.lua, the shared workloads, the Performance category and the report
-- section. Synthetic and unit-level: a SCRIPTED clock decides every timing here, so nothing depends on wall-clock noise, and only the
-- cheapest workloads run (one repetition) so the suite stays fast. The offline benchmark itself is tests/bench_workshop.lua.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")   -- string.format refuses what the client refuses (%d beyond 32 bits, NaN)

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local LAB = ROOT .. "../TwichUI_TestLab/"
local WORKSHOP_FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

-- the Lab's files in the .toc's order, so the test loads exactly what the game does
local function LabFiles()
  local list = {}
  for line in io.lines(LAB .. "TwichUI_TestLab.toc") do
    line = line:gsub("\r", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then list[#list + 1] = (line:gsub("\\", "/")) end
  end
  return list
end

local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[DeepCopy(k)] = DeepCopy(x) end
  return out
end
local function DeepSame(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not DeepSame(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- A client with the Workshop's pure files and (optionally) the Lab's files. A virtual clock: it moves only when a test says so.
-- opts.lab = list of Lab files to load ("Lab.lua", ...); default all of the .toc's except the window; opts.window = also the look files and Window.lua.
local function Setup(opts)
  opts = opts or {}
  local now = 0
  local timers = 0
  local c = MIClient("Zzchar", {
    db = { modules = {} },
    beforeFiles = function(cl)
      cl.CreateFrame = function(kind, name, parent)
        local fr = MIFake(kind, parent)
        for _, m in ipairs({ "SetColorTexture", "SetVertexColor", "SetBackdropColor", "SetBackdropBorderColor", "SetTexCoord", "SetFontObject", "SetMaxLetters",
          "SetAutoFocus", "SetTextInsets", "SetJustifyV", "SetJustifyH", "SetWordWrap", "EnableMouse", "SetToplevel", "SetMovable", "SetClampedToScreen",
          "RegisterForDrag", "SetDontSavePosition", "SetFrameStrata", "SetMotionScriptsWhileDisabled", "UnregisterAllEvents" }) do
          fr[m] = function() end
        end
        fr.UnregisterAllEvents = function(s) s.events = {} end
        fr.SetTexture = function(s, v) s.texture = v end
        fr.IsEventRegistered = function(s, e) return s.events[e] == true end
        fr.CreateTexture = function(s) local t = MIFake("Texture", s); t.SetColorTexture = function() end t.SetVertexColor = function() end t.SetTexCoord = function() end t.SetTexture = function(x, v) x.texture = v end return t end
        fr.CreateFontString = function(s) local t = MIFake("FontString", s); t.SetFont = function() return true end t.SetJustifyV = function() end t.SetWordWrap = function() end t.SetTextColor = function() end t.SetJustifyH = function() end return t end
        if name then cl[name] = fr end
        return fr
      end
      cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
      cl.GameTooltip = MIFake("GameTooltip")
      cl.UISpecialFrames = {}
      for _, file in ipairs({ "chronicle/Style.lua", "Look.lua", "FrameLook.lua", "CraftLook.lua" }) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
      end
    end,
    files = {},
  })
  c.TwichUIDB = opts.TwichUIDB or c.TwichUIDB
  c.TwichUIWorkshopDB = opts.TwichUIWorkshopDB
  c.TwichUIDiagnosticsDB = opts.TwichUIDiagnosticsDB
  c.GetRealmName = function() return "Zzrealm" end
  c.GetNormalizedRealmName = function() return "Zzrealm" end
  c.UnitName = function() return "Zzchar" end
  local reads = 0
  c.GetTimePreciseSec = function() reads = reads + 1 return now + reads * 0.00002 end
  c.C_Timer = { After = function() timers = timers + 1 end, NewTicker = function() timers = timers + 1 return { Cancel = function() end } end }
  if not opts.noWorkshop then
    for _, f in ipairs(WORKSHOP_FILES) do
      local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
    end
    c.TwichUI.Workshop.ready = true
    c.TwichUI.WorkshopLauncher = opts.launcher or { Loaded = function() return true end, Load = function() return true end, Explain = function(code) return "couldn't open the Workshop: " .. code end }
  end
  local t = { c = c, R = c.TwichUI, timers = function() return timers end }
  function t.Advance(sec) now = now + sec end
  function t.Now() return now end
  function t.Clock() return c.GetTimePreciseSec() end
  function t.Load(files)
    for _, f in ipairs(files) do
      local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
    end
    t.TL = c.TwichUI.TestLab
  end
  return t
end

-- drives the runner's frame the way the game does, one OnUpdate per frame; returns the frames used
local function Drive(RN, limit, dt, t)
  local fr, frames = nil, 0
  limit = limit or 500
  while RN.Active() and frames < limit do
    fr = fr or RN.frameForTests()
    local fn = fr.scripts.OnUpdate
    Check(fn, "an active run has an OnUpdate")
    if t then t.Advance(dt or 0.016) end
    fn(fr, dt or 0.016)
    frames = frames + 1
  end
  Check(not RN.Active(), "the run ended within " .. limit .. " frames")
  return frames
end

-- the runner keeps its frame private; the test finds it as the one frame that carries the OnUpdate / the regen event
local function WireFrames(t)
  local made = {}
  local create = t.c.CreateFrame
  t.c.CreateFrame = function(...) local f = create(...); made[#made + 1] = f; return f end
  return function(RN)
    local cached
    RN.frameForTests = function()
      if cached then return cached end
      for _, f in ipairs(made) do if f.events.PLAYER_REGEN_DISABLED and f.scripts.OnUpdate then cached = f; return f end end
    end
    return made
  end
end


local function Close(a, b, msg) if math.abs(a - b) > 1e-6 then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

---------------------------------------------------------------------------
-- 1. Statistics
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  t.Load({ "Lab.lua", "Bench.lua" })
  local BN = t.TL.Bench
  Same(BN.Median({ 3, 1, 2 }), 2, "odd median")
  Same(BN.Median({ 4, 1, 3, 2 }), 2.5, "even median is the mean of the middle two")
  Same(BN.Median({}), nil, "no median of nothing")
  local s = BN.Stats({ 10, 12, 11, 30, 10 })   -- sorted 10 10 11 12 30: median 11; |x - 11| = 1 1 0 1 19, sorted 0 1 1 1 19: MAD 1
  Same(s.median, 11); Same(s.mad, 1, "MAD is the median of the absolute deviations"); Same(s.min, 10); Same(s.max, 30); Same(s.n, 5); Same(s.sum, 73)
  Same(BN.Stats({ 5 }).mad, 0, "one sample has no spread")
  Same(BN.Stats({}), nil)
  Check(BN.Ser({ b = 1, a = { 2, 3 } }) == BN.Ser({ a = { 2, 3 }, b = 1 }), "a serialisation does not depend on insertion order")
  Check(BN.Ser({ a = 1 }) ~= BN.Ser({ a = 2 }), "and sees a change")
end

---------------------------------------------------------------------------
-- 2. Measure on a scripted clock
---------------------------------------------------------------------------
-- A stub workload of 3 steps per repetition. The script advances the clock INSIDE a step (so only step time is timed) and in the yield (waiting).
local function Stub(over)
  over = over or {}
  local calls = { setup = 0, begin = 0, step = 0, verify = 0 }
  local w = {
    id = "stub.work", v = 1, fixture = "stub", seed = 1, size = 10, unit = "things", work = 100,
    setup = function() calls.setup = calls.setup + 1 return { n = 3 } end,
    begin = function(st)
      calls.begin = calls.begin + 1
      local at = 0
      return function() calls.step = calls.step + 1 at = at + 1 if over.onStep then over.onStep(at, calls) end return at >= st.n end,
        function() return { sig = over.sig and over.sig(calls) or "same" } end
    end,
    signature = function(out) return out.sig end,
    verify = function() calls.verify = calls.verify + 1 if over.verify then return over.verify(calls) end return true end,
    fingerprint = over.fingerprint,
  }
  return w, calls
end

local function BenchEnv()
  local t = Setup({ noWorkshop = true })
  t.Load({ "Lab.lua", "Bench.lua" })
  return t, t.TL.Bench
end

do
  local _, BN = BenchEnv()
  local now, rep = 0, -1
  -- repetition r (0 = the warm-up) has steps of (r + 1) ms: samples for repetitions 1..5 are 6, 9, 12, 15, 18 ms; every yield costs 7 ms of waiting
  local w, calls = Stub({ onStep = function(at) if at == 1 then rep = rep + 1 end now = now + (rep + 1) * 0.001 end })
  local yields, memv = 0, 1000
  local res = BN.Measure(w, { clock = function() return now end, clockName = "script", env = "test", host = "h", lua = "Lua 5.1",
    yield = function() yields = yields + 1 now = now + 0.007 end, mem = function() memv = memv + 10 return memv end })
  Same(res.status, "ok", tostring(res.why))
  Same(calls.setup, 1, "the input is built once, outside the timing")
  Same(calls.begin, 6, "one warm-up and five repetitions")
  Same(calls.step, 18, "three steps each")
  Same(yields, 12 + 6 + 5, "a yield after every step but the last, one after the last step (M7.1) and one between repetitions")
  Same(#res.samples, 5, "five samples: the warm-up is not one")
  for i, want in ipairs({ 6, 9, 12, 15, 18 }) do Close(res.samples[i], want, "sample " .. i) end
  Close(res.median, 12); Close(res.mad, 3, "MAD of 6 9 12 15 18"); Close(res.min, 6); Close(res.max, 18)
  Close(res.perSec, 100 / 0.012, "throughput = work / median seconds")
  Close(res.stepMaxMs, 6, "the worst single step")
  Close(res.wallMs, 26, "wall time counts the yields (12 ms of steps + 14 ms of waiting)")
  Close(res.waitMs, 14, "waiting is wall minus step time, not part of the sample")
  Same(calls.verify, 2, "the full verification runs on the warm-up and the last repetition")
  Same(res.env, "test"); Same(res.host, "h"); Same(res.clock, "script"); Same(res.fixture, "stub"); Same(res.seed, 1); Same(res.size, 10)
  -- memory: each reading adds 10 KB; per repetition 5 readings (start, three steps, end): the change is 40, the highest sample between steps 30
  Close(res.heapDeltaKB, 40); Close(res.heapPeakKB, 30)
  Same(res.retainedKB, nil, "retained memory is only measured when asked")
  Check(res.limits[1]:find("approximate", 1, true), "the memory limitation is stated in the result")
end

-- the repetition count and the warm-up are options; a workload may opt out of the warm-up
do
  local _, BN = BenchEnv()
  local now = 0
  local w, calls = Stub({ onStep = function() now = now + 0.001 end })
  local res = BN.Measure(w, { clock = function() return now end, reps = 3, warmup = 0, mem = function() return 0 end })
  Same(#res.samples, 3); Same(calls.begin, 3, "no warm-up when 0")
  Same(res.warmup, 0)
  w, calls = Stub({ onStep = function() now = now + 0.001 end })
  res = BN.Measure(w, { clock = function() return now end, reps = 1000, mem = function() return 0 end })
  Same(#res.samples, BN.MAX_REPS, "repetitions are capped")
  w, calls = Stub({ onStep = function() now = now + 0.001 end })
  w.warmup = false
  BN.Measure(w, { clock = function() return now end, reps = 2, mem = function() return 0 end })
  Same(calls.begin, 2, "a workload can say it needs no warm-up")
end

-- retained memory: forced collections, a base before the input is built, and the heap after each repetition
do
  local _, BN = BenchEnv()
  local now = 0
  local w = Stub({ onStep = function() now = now + 0.001 end })
  local heap = 5000
  local res = BN.Measure(w, { clock = function() return now end, reps = 3, retained = true, mem = function() return heap end })
  Same(res.retainedKB, 0, "a flat heap retains nothing")
  Same(#res.heapAfterRep, 3, "the heap after every repetition")
  Same(res.heapGrowthKB, 0)
  local grow = 0
  res = BN.Measure(Stub({ onStep = function() now = now + 0.001 end }), { clock = function() return now end, reps = 3, retained = true, mem = function() grow = grow + 1 return 5000 + grow end })
  Check(res.heapGrowthKB > 0, "growth over repetitions is seen")
end

-- every way a measurement can end other than "ok", and what it leaves
do
  local _, BN = BenchEnv()
  local now = 0
  local tick = function() now = now + 0.001 end
  local function Run(w, o)
    o = o or {}
    o.clock, o.mem = function() return now end, function() return 0 end
    return BN.Measure(w, o)
  end
  -- cancellation between steps: no step runs after the stop is seen
  local w, calls = Stub({ onStep = tick })
  local seen = 0
  local res = Run(w, { stop = function() seen = seen + 1 if calls.step >= 7 then return "combat started" end end })
  Same(res.status, "stopped"); Check(res.why:find("combat"), res.why); Same(calls.step, 7, "stopped after the step that saw it, none after")
  Same(#res.samples, 1, "partial samples are kept as a record only: no statistics")
  Same(res.median, nil, "an incomplete run reports no median")
  -- timeout: the budget is checked between steps
  w, calls = Stub({ onStep = function() now = now + 0.5 end })
  res = Run(w, { budget = 2 })
  Same(res.status, "timeout"); Check(calls.step <= 6, "it stopped within a few steps of the budget: " .. calls.step)
  -- an oversized step stops the benchmark rather than repeating it
  w, calls = Stub({ onStep = function(at) now = now + (at == 2 and 0.2 or 0.001) end })
  res = Run(w, { maxStep = 0.1 })
  Same(res.status, "oversize"); Same(calls.begin, 1, "no second repetition after a step that long"); Check(res.why:find("200.0 ms", 1, true), res.why)
  -- a repetition that gives another answer
  w = Stub({ onStep = tick, sig = function(c) return c.begin == 3 and "other" or "same" end })
  res = Run(w)
  Same(res.status, "mismatch"); Check(res.why:find("different result", 1, true), res.why)
  -- a wrong output
  w = Stub({ onStep = tick, verify = function() return false, "total is 3, expected 4" end })
  res = Run(w)
  Same(res.status, "mismatch"); Check(res.why:find("total is 3", 1, true), res.why)
  -- the workload changed its own input
  local n = 0
  w = Stub({ onStep = tick, fingerprint = function() n = n + 1 return n end })
  res = Run(w)
  Same(res.status, "mismatch"); Check(res.why:find("input", 1, true), res.why)
  w = Stub({ onStep = tick, fingerprint = function() return "fixed" end })
  Same(Run(w).status, "ok", "an unchanged input passes")
  -- a workload that cannot build its input is skipped, not failed
  w = Stub()
  w.setup = function() return nil end
  Same(Run(w).status, "skipped")
  -- an error propagates to the caller (which owns cleanup): Lua 5.1 cannot yield across a pcall, so Measure has none
  w = Stub({ onStep = function() error("boom") end })
  local ok, err = pcall(Run, w)
  Check(not ok and tostring(err):find("boom"), "an error is not swallowed")
end

---------------------------------------------------------------------------
-- 3. Comparing
---------------------------------------------------------------------------
do
  local _, BN = BenchEnv()
  local function R(samples, over)
    local r = { schema = 1, id = "a.b", v = 1, fixture = "f", seed = 1, size = 10, work = 100, unit = "ops", env = "lua5.1-offline", host = "m1", clock = "os.clock", lua = "Lua 5.1",
      status = "ok", samples = samples }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
  end
  local base = R({ 100, 101, 99, 100, 102 })               -- median 100, MAD 1
  -- threshold = max(3 x 1, 5% of 100 = 5) = 5
  Same(BN.Compare(base, R({ 101, 103, 102, 101, 102 })).verdict, "same", "a 2 ms difference is inside a threshold of 5")
  Same(BN.Compare(base, R({ 105, 105, 105, 105, 105 })).verdict, "same", "exactly the threshold is still noise")
  local slower = BN.Compare(base, R({ 120, 121, 119, 120, 122 }))
  Same(slower.verdict, "slower"); Close(slower.delta, 20); Close(slower.threshold, 5)
  Same(BN.Compare(base, R({ 80, 81, 79, 80, 82 })).verdict, "faster")
  -- a larger spread raises the threshold: MAD 10 -> 30
  local noisy = R({ 100, 110, 90, 120, 80 })
  Same(noisy and BN.Compare(noisy, R({ 120, 130, 110, 140, 100 })).verdict, "same", "a 20 ms change inside a 30 ms threshold")
  -- unstable, too few samples, or a median at the clock's resolution
  Same(BN.Compare(R({ 10, 40, 5, 60, 8 }), R({ 5, 5, 5, 5, 5 })).verdict, "inconclusive", "MAD above a quarter of the median")
  Same(BN.Compare(base, R({ 50, 50, 50 })).verdict, "inconclusive", "three samples are not enough")
  Same(BN.Compare(R({ 0.01, 0.01, 0.01, 0.01, 0.01 }), R({ 0.02, 0.02, 0.02, 0.02, 0.02 })).verdict, "inconclusive", "too small to time")
  -- incomparable
  for _, case in ipairs({ { "fixture", "g" }, { "seed", 2 }, { "size", 11 }, { "v", 2 }, { "env", "wow-1.2" }, { "host", "m2" }, { "clock", "GetTime" }, { "work", 101 }, { "lua", "Lua 5.2" } }) do
    local cmp = BN.Compare(base, R({ 100, 101, 99, 100, 102 }, { [case[1]] = case[2] }))
    Same(cmp.verdict, "incomparable", case[1] .. " differs"); Check(cmp.reason:find(case[1], 1, true), cmp.reason)
  end
  Same(BN.Compare(base, R({ 1 }, { status = "timeout" })).verdict, "incomparable", "a run that did not finish")
  Same(BN.Compare(base, nil).verdict, "incomparable", "nothing to compare")
  -- interleaved runs: the direction must hold in every pair
  local cand = R({ 120, 90, 121, 119, 122 })
  Same(BN.Compare(base, cand).verdict, "slower", "unpaired: medians decide")
  Same(BN.Compare(base, cand, { paired = true }).verdict, "inconclusive", "paired: one pair pointing the other way")
  Same(BN.Compare(base, R({ 120, 121, 119, 120, 122 }), { paired = true }).verdict, "slower")
end

---------------------------------------------------------------------------
-- 4. Result lines: encode, decode, and what is refused
---------------------------------------------------------------------------
do
  local _, BN = BenchEnv()
  local now = 0
  local w = Stub({ onStep = function() now = now + 0.002 end })
  local res = BN.Measure(w, { clock = function() return now end, mem = function() return 100 end, env = "wow-1.60.1.99999", host = "client", clockName = "GetTimePreciseSec", lua = "Lua 5.1" })
  local line = BN.Encode(res)
  Check(line:find("^B1 id=stub.work "), line)
  Check(not line:find("\n"), "one line")
  local back = assert(BN.Decode(line))
  Same(back.id, "stub.work"); Same(back.env, "wow-1.60.1.99999"); Same(back.host, "client"); Same(#back.samples, 5)
  Close(back.samples[1], res.samples[1]); Close(back.stepMaxMs, res.stepMaxMs, "to the encoded precision")
  Same(BN.Compare(back, res).verdict, "same", "a decoded line compares with the live result (spaces in the Lua version included)")
  Same((BN.Decode("B2 id=x fixture=f env=e clock=c")), nil, "another schema is refused")
  Same((BN.Decode("B1 id=x fixture=f env=e clock=c status=ok median=nan samples=1,2,3")), nil, "a NaN is refused")
  Same((BN.Decode("B1 id=x fixture=f env=e clock=c status=ok median=1 samples=1,2,x")), nil, "a bad sample is refused")
  Same((BN.Decode("B1 id=x fixture=f env=e clock=c status=ok median=1")), nil, "no samples is refused")
  Same((BN.Decode("B1 id=x " .. ("a=1 "):rep(600))), nil, "an overlong line is refused")
  Same((BN.Decode("B1 id=x fixture=f env=e clock=c status=ok median=inf samples=1")), nil)
  local all, bad = BN.DecodeAll("# comment\n" .. line .. "\nB1 garbage\nnot a line\n")
  Check(all["stub.work"] and bad == 1, "pasted text: good lines kept, bad ones counted")
  -- text is data: nothing in a line is ever run
  Same((BN.Decode("B1 id=x fixture=f env=e clock=c status=ok samples=1,2,3,4,5 median=os.exit()")), nil)
  -- a result that did not finish carries its reason, not figures
  local failed = BN.Encode({ id = "a", v = 1, fixture = "f", env = "e", host = "h", clock = "c", lua = "L", status = "timeout", why = "the time budget (50 s) ran out", samples = {} })
  Check(failed:find("status=timeout", 1, true) and not failed:find("median", 1, true), failed)
  Check(BN.Summary(res):find("median 2%.00 ms") or BN.Summary(res):find("median 6%.00 ms"), BN.Summary(res))
end

---------------------------------------------------------------------------
-- 5. The fixtures are deterministic and bounded
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  t.Load({ "Lab.lua", "Fixtures.lua" })
  local FX = t.TL.Fixtures
  local function Make(seed, n, items, chunk)
    local b = FX.Bulk(seed, n, items)
    while not b:Done() do b:Fill(chunk) end
    return b
  end
  local a, b, c = Make(7600001, 3000, 300, 1000), Make(7600001, 3000, 300, 7), Make(7600002, 3000, 300, 1000)
  local same, other = true, false
  for i = 1, 3000 do
    if a.item[i] ~= b.item[i] or a.count[i] ~= b.count[i] or a.buyout[i] ~= b.buyout[i] then same = false end
    if a.item[i] ~= c.item[i] or a.buyout[i] ~= c.buyout[i] then other = true end
  end
  Check(same, "the records do not depend on the chunk size"); Check(other, "another seed gives other records")
  Same(a.truth.read, 3000); Same(a.truth.used + a.truth.noBuyout + a.truth.invalid, 3000, "every record is accounted for by the generator")
  Check(a.truth.invalid > 0 and a.truth.noBuyout > 0, "both kinds of unusable record occur")
  Same(FX.Bulk(1, 10 ^ 9, 10 ^ 9).n, FX.BULK.records, "the size is bounded"); Same(FX.Bulk(1, -5, 0).n, 0)
  Same(FX.Bulk(1, 100, 10 ^ 9).nItems, FX.BULK.items)
  Same(#FX.Crafting(5, { entries = 99 }).entries, FX.LIMITS.entries, "the default scenarios keep their limits")
  Same(#FX.Crafting(5, { entries = 99, bulk = true }).entries, FX.BULK.entries, "a bulk scenario asks for more, and is still bounded")
  local x, y = FX.Crafting(7620001, { bulk = true, entries = 10, items = 24 }), FX.Crafting(7620001, { bulk = true, entries = 10, items = 24 })
  Check(#x.pool == 24 and #x.entries == 10, "sizes as asked"); Same(#y.pool, 24)
  for i = 1, #x.pool do Same(x.pool[i], y.pool[i], "same seed, same pool") end
end

---------------------------------------------------------------------------
-- 6. The real workloads, one repetition each, against the production code; and a corrupted production is caught
---------------------------------------------------------------------------
do
  local t = Setup()
  local files = {}
  for _, f in ipairs(LabFiles()) do if f ~= "Window.lua" and f ~= "Kit.lua" then files[#files + 1] = f end end
  t.Load(files)
  local TL = t.TL
  local BN, WL = TL.Bench, TL.Workloads
  Check(#WL.list >= 15, "the workloads are registered: " .. #WL.list)
  local ids = {}
  for _, w in ipairs(WL.list) do
    Check(not ids[w.id], "a unique id " .. w.id); ids[w.id] = true
    Check(w.fixture and w.seed and w.size and w.unit and w.v, w.id .. " names its fixture, seed, size, unit and version")
  end
  Check(WL.byId["market.aggregate.250k"].offline and not WL.byId["market.aggregate.50k"].offline, "only the 250,000-record house is offline only")
  for _, w in ipairs(WL.InGame()) do Check(not w.offline, w.id) end
  Check(#WL.DEFERRED >= 2, "the deferred UI benchmarks are named")
  local now = 0
  local function Measure(id, o)
    o = o or {}
    return BN.Measure(WL.byId[id], { clock = function() now = now + 0.00001 return now end, mem = function() return 0 end, reps = o.reps or 1, warmup = 0,
      ctx = { W = t.R.Workshop }, env = "test", host = "t" })
  end
  for _, id in ipairs({ "market.aggregate.1k", "history.insert.30d", "crafting.plan.small", "market.lookup.24k" }) do
    local res = Measure(id)
    Same(res.status, "ok", id .. ": " .. tostring(res.why))
    Check(res.verified and res.work > 0 and res.steps >= 1, id .. " verified its output")
  end
  -- two runs of the same workload give the same output and the same fixture identity
  local r1, r2 = Measure("market.aggregate.1k"), Measure("market.aggregate.1k")
  Same(r1.work, r2.work); Same(r1.fixture, r2.fixture); Same(r1.seed, r2.seed)

  -- corrupt production: the batch silently drops every 50th record. The benchmark must report a wrong output, not a faster time.
  local PR = t.R.Workshop.Prices
  local orig = PR.NewBatch
  PR.NewBatch = function(p)
    local b, n = orig(p), 0
    local add = b.Add
    b.Add = function(self, ...) n = n + 1 if n % 50 == 0 then return false end return add(self, ...) end
    return b
  end
  local bad = Measure("market.aggregate.1k")
  PR.NewBatch = orig
  Same(bad.status, "mismatch"); Check(bad.why:find("counts", 1, true), tostring(bad.why))
  -- the planner given a rounding fault in the production plan totals is caught by the reference model
  local Sh = t.R.Workshop.Shopping
  local plan = Sh.Plan
  Sh.Plan = function(inp) local p = plan(inp) if p.totals.cash then p.totals.cash = p.totals.cash + 1 end return p end
  local badPlan = Measure("crafting.plan.small")
  Sh.Plan = plan
  Same(badPlan.status, "mismatch", tostring(badPlan.why))
  -- a wrong price from the Market API
  local MK = t.R.Workshop.Market
  local price = MK.Price
  MK.Price = function(item, opt) local p, why = price(item, opt) if p then p = setmetatable({ price = p.price + 1 }, { __index = p }) end return p, why end
  local badLook = Measure("market.lookup.24k")
  MK.Price = price
  Same(badLook.status, "mismatch", tostring(badLook.why))

  -- M7.1: market.stats.6k raised "integer overflow attempting to store 39286995442" in the client. Cause: the workload's FIXTURE wrote a
  -- copper price with %d. This file loads client_format.lua, which refuses what the client refuses, so the committed workload runs here
  -- exactly as it does there; the fixture's prices do pass 2^31 (the figure in the client's message is one of them)
  local stats = Measure("market.stats.6k")
  Same(stats.status, "ok", "market.stats.6k: " .. tostring(stats.why))
  Check(stats.verified and stats.work == 6000, "and it verified its output")
  local st = WL.byId["market.stats.6k"]
  local big = false
  for _, p in ipairs(st.setup({ W = t.R.Workshop, yield = function() end }).ops.price) do if p >= 2147483648 then big = true break end end
  Check(big, "the fixture holds a price beyond 32 bits, so the %d guard is exercised")
  -- the output is still checked: a wrong week average from production is caught, and the checksum sees a wrong result
  local stat = MK.Stats
  MK.Stats = function(id, span, o) local r = stat(id, span, o) if r and span == "week" and r.average then r = setmetatable({ average = r.average + 1 }, { __index = r }) end return r end
  local badStats = Measure("market.stats.6k")
  MK.Stats = stat
  Same(badStats.status, "mismatch", tostring(badStats.why)); Check(badStats.why:find("avg", 1, true), tostring(badStats.why))
  local sigA = st.signature({ got = { 1 }, chk = 5 })
  Check(sigA ~= st.signature({ got = { 1 }, chk = 6 }) and sigA ~= st.signature({ got = { 2 }, chk = 5 }), "the signature separates a different count and a different checksum")
end

---------------------------------------------------------------------------
-- 6b. Attribution (M7.1): what a segment between two yields was made of
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  t.Load({ "Lab.lua", "Bench.lua" })
  local BN = t.TL.Bench
  local now = 0
  local seen = {}
  local w = { id = "attr", v = 1, fixture = "f", seed = 1, size = 1, unit = "u", work = 10,
    setup = function(ctx) now = now + 0.030 ctx.yield() now = now + 0.010 return { n = 2 } end,
    fingerprint = function() now = now + 0.020 return "fp" end,
    begin = function(st)
      local at = 0
      return function() now = now + 0.002 at = at + 1 return at >= st.n end, function() now = now + 0.001 return { sig = "s" } end
    end,
    signature = function(o) return o.sig end,
    verify = function() now = now + 0.040 return true end }
  local res = BN.Measure(w, { clock = function() return now end, yield = function() now = now + 0.007 end, reps = 2, warmup = 0, env = "t", host = "h",
    segment = function(seg) seen[#seen + 1] = seg end })
  Same(res.status, "ok", tostring(res.why))
  Same(res.inst, BN.INSTR, "the instrumentation level is recorded")
  Close(res.median, 4, "a sample is still the sum of the timed steps only")
  Close(res.phases.setup.total * 1000, 40, "setup is split at its yield and the wait belongs to no phase"); Same(res.phases.setup.n, 2)
  Close(res.phases.setup.max * 1000, 30); Close(res.phases.fingerprint.max * 1000, 20)
  Close(res.phases.verify.max * 1000, 40, "verification is its own phase"); Same(res.phases.verify.n, 2, "on the first and the last repetition")
  Close(res.phases.step.total * 1000, 8, "four timed steps")
  Same(res.longestPhase, "verify"); Close(res.longestMs, 61, "the longest segment: the last repetition's finish 1 + verify 40 + the closing fingerprint 20"); Check(not res.longestTimed, "it held no timed step")
  Check(#res.slowest <= BN.SLOW_SEGMENTS and res.slowest[1].ms >= res.slowest[#res.slowest].ms, "the longest few, longest first")
  Check(#seen >= 6, "the Runner is told of every segment (" .. #seen .. ")")
  -- a segment that holds a timed step says so
  local timedSeen = false
  for _, g in ipairs(seen) do if g.timed then timedSeen = true end end
  Check(timedSeen, "and which held timed steps")
  -- the line carries the attribution, and decoding it keeps the instrumentation level without making runs incomparable
  local line = BN.Encode(res)
  Check(line:find(" inst=2", 1, true) and line:find(" lphase=verify", 1, true) and line:find(" ltimed=0", 1, true) and line:find(" phases=", 1, true), line)
  local back = BN.Decode(line)
  Same(back.inst, BN.INSTR); Close(back.longest, 61, "decoded longest segment")
  local older = BN.Decode(line:gsub(" inst=2", " inst=1"))
  Check(BN.Compare(older, back).verdict ~= "incomparable", "a level-1 line and a level-2 line are comparable: a sample did not change")
  local text = table.concat(BN.ReportLines({ { result = res } }, "h"), "\n")
  Check(text:find("longest segments between yields", 1, true) and text:find("verify 40.0", 1, true), text)
end

---------------------------------------------------------------------------
-- 7. The Performance category through the real Runner: opt-in, report section, no leaks, no saved data
---------------------------------------------------------------------------
do
  local db = { modules = {}, workshop = { v = 1, queue = { a = 1 } } }
  local wdb = { v = 1, markets = { ["Realm|Alliance"] = { at = 1000, n = 2, items = { [5] = "10,1,1,1,0" } } } }
  local before = { DeepCopy(db), DeepCopy(wdb) }
  local t = Setup({ TwichUIDB = db, TwichUIWorkshopDB = wdb })
  local wire = WireFrames(t)
  t.Load(LabFiles())
  local TL = t.TL
  local RN = TL.Runner
  local made = wire(RN)
  Check(TL.categories.perf and TL.categories.perf.optin, "Performance is an opt-in category")
  local perf = TL.Select({ perf = true })
  Check(#perf >= 10, "it holds the benchmark cases (" .. #perf .. ")")
  for _, c in ipairs(perf) do Same(c.class, "pure", c.id .. " is pure"); Check(c.budget <= 60, c.id .. " budget") end
  for _, c in ipairs(TL.Select(nil)) do Check(c.cat ~= "perf", "an unqualified run leaves " .. c.id .. " out") end
  Check(TL.cases["perf.ui.redraw"] and TL.cases["perf.clock"], "the stated deferral and the clock case exist")
  for _, id in ipairs({ "market.aggregate.1k" }) do Check(TL.cases["perf." .. id], id) end
  Check(not TL.cases["perf.market.aggregate.250k"], "the offline-only house is not a case")
  Check(TL.cases["perf.retained.market.aggregate.10k"], "the retained-memory cases exist")

  -- one benchmark case, run through the runner
  local framesBefore, timersBefore = #made, t.timers()
  local step = 0
  local clock = function() step = step + 0.00002 return step end
  local done
  local chosen = { TL.cases["perf.market.aggregate.10k"], TL.cases["perf.clock"], TL.cases["perf.ui.redraw"] }
  Check(RN.Start(chosen, { cats = { "perf" }, clock = clock, onDone = function(s) done = s end }))
  Drive(RN, 2000, 0.016, t)
  Check(done and done.ended == "complete", "the run finished")
  local by = {}
  for _, r in ipairs(done.results) do by[r.id] = r end
  Same(by["perf.market.aggregate.10k"].status, "pass", tostring(by["perf.market.aggregate.10k"].detail))
  Same(by["perf.clock"].status, "pass", tostring(by["perf.clock"].detail))
  Same(by["perf.ui.redraw"].status, "skipped"); Check(by["perf.ui.redraw"].detail:find("deferred", 1, true), "the skip says why")
  local b = by["perf.market.aggregate.10k"]
  Check(b.bench and b.bench[1] and b.bench[1].status == "ok" and #b.bench[1].samples == 5, "the benchmark result is on the record, five samples")
  Check(b.frame and b.frame.n >= 1, "the runner kept the frame intervals of the case")
  Same(b.detail, nil, "the progress text does not outlive the case")
  local text = TL.Report.Build(done)
  Check(text:find("^TWICHUI%-TESTLAB REPORT schema 1\n"), "the report is still schema 1")
  Check(text:find("benchmarks (schema 1)", 1, true), "with a benchmark section")
  Check(text:find("\n  B1 id=market.aggregate.10k ", 1, true), "holding the result line")
  Check(text:find("frames %d+, worst"), "and the frame record")
  Check(#text < 30000, "within the report's size bound")
  -- a run without benchmarks reports exactly as before
  local plain = TL.Report.Build({ results = { { id = "x", status = "pass", label = "synthetic", ms = 1, facts = {} } }, counts = { pass = 1, fail = 0, skipped = 0, error = 0, timeout = 0, stopped = 0 },
    cats = { "core" }, seconds = 0, slices = 1, worstSlice = 0, worstFrame = 0, overruns = {}, overrunCount = 0, setups = {}, ended = "complete", clock = "c", slice = 0.005 })
  Check(not plain:find("benchmarks", 1, true), "no benchmark lines when none ran")

  -- nothing was left behind
  Same(t.timers(), timersBefore, "no timer was made")
  Check(#made - framesBefore <= 1, "at most the runner's own single frame was made (it is made once, on the first run)")
  local framesAfterFirst = #made
  local snap = RN.Snapshot()
  Check(not snap.active and not snap.updating and not snap.listening, "the runner is idle")
  Check(DeepSame(db, before[1]) and DeepSame(wdb, before[2]), "the saved data is unchanged")
  Same(t.c.TwichUIWorkshopDB.markets["Realm|Alliance"].n, 2)

  -- Stop between steps: the remaining cases are marked, no benchmark step runs afterwards
  local ran = 0
  local WK = t.R.Workshop
  local orig = WK.Prices.NewBatch
  WK.Prices.NewBatch = function(p) ran = ran + 1 return orig(p) end
  done = nil
  Check(RN.Start({ TL.cases["perf.market.aggregate.10k"], TL.cases["perf.clock"] }, { cats = { "perf" }, clock = clock, onDone = function(s) done = s end }))
  local fr = RN.frameForTests()
  fr.scripts.OnUpdate(fr, 0.016); fr.scripts.OnUpdate(fr, 0.016)
  Check(RN.Stop("user"), "Stop is accepted while a benchmark runs")
  local seenAt = ran
  Check(done and done.ended == "user", "the run ended")
  Same(done.results[1].status, "stopped"); Same(done.results[2].status, "stopped")
  Check(not RN.Snapshot().updating, "no frame update is left")
  Same(ran, seenAt, "nothing ran after Stop")
  WK.Prices.NewBatch = orig

  -- combat ends the run at once
  done = nil
  Check(RN.Start({ TL.cases["perf.market.aggregate.10k"] }, { cats = { "perf" }, clock = clock, onDone = function(s) done = s end }))
  fr.scripts.OnUpdate(fr, 0.016)
  t.c.COMBAT = true
  fr.scripts.OnUpdate(fr, 0.016)
  t.c.COMBAT = false
  Check(done and done.ended == "combat", "combat ends it")
  Check(not RN.Snapshot().updating and not RN.Snapshot().listening, "and leaves no listener")
  Check(DeepSame(db, before[1]) and DeepSame(wdb, before[2]), "the saved data is still unchanged")
  Same(#made, framesAfterFirst, "later benchmark runs, a Stop and combat made no frame")
  Same(t.timers(), timersBefore, "and no timer")
end

print("PASSED test_testlab_bench")
