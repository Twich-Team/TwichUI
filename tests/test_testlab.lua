-- The in-game Test Lab (TwichUI_TestLab/): its case registry, its cooperative runner (slices, Stop, timeouts, errors, combat, the run cap),
-- its report, its window, and the shared core cases. The core cases (TwichUI_TestLab/cases/Core.lua) are ONE definition run in two
-- interpreters: here, under the offline mock through the real Runner with a virtual clock, and in the game by the Lab itself.
-- Synthetic: it proves our logic, not what the game's Lua or API does (the Lab's client cases and docs/testlab.md cover that), and not how
-- the window looks. The Lab never touches the saved roots; a static scan of its files enforces that.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")   -- string.format refuses what the client refuses (%d beyond 32 bits, NaN)

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local LAB = ROOT .. "../TwichUI_TestLab/"
local WORKSHOP_FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

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

---------------------------------------------------------------------------
-- 1. The registry refuses what it should
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  t.Load({ "Lab.lua" })
  local TL = t.TL
  Check(TL.Category{ id = "x", label = "X" }, "a category registers")
  Check(not TL.Category{ id = "x" }, "a duplicate category is refused")
  local function Refused(def, why)
    local case, reason = TL.Case(def)
    Check(case == nil, "refused: " .. why)
    Check(reason and reason:find(why, 1, true), "reason mentions " .. why .. ", got " .. tostring(reason))
  end
  local run = function() end
  Refused({ id = "a", cat = "x", run = run }, "safety class")
  Refused({ id = "a", cat = "x", class = "dangerous", run = run }, "safety class")
  Refused({ id = "a", cat = "nope", class = "pure", run = run }, "category")
  Refused({ cat = "x", class = "pure", run = run }, "id")
  Refused({ id = "a", cat = "x", class = "pure" }, "run")
  for _, class in ipairs({ "pure", "readonly", "owned", "guided" }) do
    Check(TL.Case{ id = "ok." .. class, cat = "x", class = class, run = run }, class .. " is a class")
  end
  Refused({ id = "ok.pure", cat = "x", class = "pure", run = run }, "duplicate")
  Same(TL.cases["ok.pure"].budget, 10, "default budget 10 s")
  TL.Case{ id = "big", cat = "x", class = "pure", run = run, budget = 500 }
  Same(TL.cases.big.budget, 60, "budget is capped at 60 s")
  Same(TL.Label(TL.cases["ok.pure"]), "synthetic"); Same(TL.Label(TL.cases["ok.readonly"]), "client"); Same(TL.Label(TL.cases["ok.guided"]), "guided")
  Same(#TL.rejected, 6, "every refusal is listed")
  Same(#TL.Select({ x = true }), 5, "the registered ones")
  Same(#TL.Select({ other = true }), 0)
end

---------------------------------------------------------------------------
-- 2. Every core case passes through the real Runner; the saved roots are untouched; nothing is left running
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
  wire(RN)
  Check(TL.Window and TL.Window.Frame(), "loading the addon built the window")
  Check(TL.Window.Frame():IsShown(), "and opened it once")

  local core = TL.Select({ core = true })
  Check(#core >= 17, "the core category holds the shared cases (" .. #core .. ")")
  for _, c in ipairs(core) do
    Same(c.class, "pure", c.id .. " is pure")
    Check(c.needs[1] == "workshop", c.id .. " needs the workshop")
  end
  local done
  -- the virtual clock moves a little on every read of it, as a real clock does
  local step = 0
  local clock = function() step = step + 0.0002 return step end
  Check(RN.Start(core, { cats = { "core" }, clock = clock, onDone = function(s) done = s end }))
  local frames = Drive(RN)
  Check(done, "the run finished")
  Same(done.ended, "complete")
  local bad = {}
  for _, r in ipairs(done.results) do if r.status ~= "pass" then bad[#bad + 1] = r.id .. " " .. r.status .. " " .. tostring(r.detail) end end
  Same(table.concat(bad, "\n"), "", "every core case passes")
  Same(done.counts.pass, #core)
  Check(frames >= 1 and frames < 100, "spread over a few frames: " .. frames)
  for _, r in ipairs(done.results) do Check(r.checks and r.checks >= 1, r.id .. " asserted something") end
  local snap = RN.Snapshot()
  Check(not snap.active and not snap.updating and not snap.listening, "nothing of the runner is left running")
  Same(t.timers(), 0, "no timer was ever created")
  Check(DeepSame(db, before[1]), "TwichUIDB is unchanged")
  Check(DeepSame(wdb, before[2]), "TwichUIWorkshopDB is unchanged")
  Same(t.c.TwichUIDiagnosticsDB, nil, "TwichUIDiagnosticsDB was not created")
end

---------------------------------------------------------------------------
-- 2b. A model/production disagreement is NAMED, not only counted (M5.1): production sabotaged to accept a NaN count must fail the batch case
--     and the per-value case, and the report must name the first differing record and print the number primitives of the field.
---------------------------------------------------------------------------
do
  local t = Setup({ TwichUIDB = { modules = {} }, TwichUIWorkshopDB = { v = 1, markets = {} } })
  local wire = WireFrames(t)
  t.Load(LabFiles())
  local TL = t.TL
  wire(TL.Runner)
  local PR = t.c.TwichUI.Workshop.Prices
  local real = PR.NewBatch
  PR.NewBatch = function(...)
    local b = real(...)
    local add = b.Add
    b.Add = function(self, item, count, buyout, info) if count ~= count then count = 5 end return add(self, item, count, buyout, info) end   -- a NaN count read as 5
    return b
  end
  local list = { TL.cases["market.reference.batch"], TL.cases["market.reference.invalid-values"] }
  Check(list[1] and list[2], "both market cases are registered")
  local done
  local step = 0
  Check(TL.Runner.Start(list, { cats = { "core" }, clock = function() step = step + 0.0002 return step end, onDone = function(s) done = s end }))
  Drive(TL.Runner)
  Check(done, "the run finished")
  for i, r in ipairs(done.results) do
    Same(r.status, "fail", list[i].id .. " fails when production reads a NaN count as valid")
    Check(r.detail:find("first differing record", 1, true) or r.detail:find("count number", 1, true), list[i].id .. " names what differed: " .. tostring(r.detail))
    local notes = table.concat(r.notes or {}, "\n")
    Check(notes:find("finite=F", 1, true) and notes:find("eq_self=", 1, true), list[i].id .. " prints the number primitives: " .. notes:sub(1, 300))
    Check(#notes < 4000, "and stays short (" .. #notes .. " characters)")
  end
  local dnotes = table.concat(done.results[1].notes, "\n")
  Check(dnotes:find("record %d+ %(invalid%)") and dnotes:find("model invalid, production priced", 1, true), "the batch note gives the record, its intent and both answers: " .. dnotes:sub(1, 300))
end

---------------------------------------------------------------------------
-- 3. Slices: cases that yield share frames; a step that never yields is measured as an overrun, never "interrupted"
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  local steps = 0
  TL.Case{ id = "yielding", cat = "s", class = "pure", run = function(tt)
    for _ = 1, 20 do t.Advance(0.0011); steps = steps + 1; tt:Yield() end   -- 20 steps of 1.1 ms
    tt:Check(true)
  end }
  TL.Case{ id = "heavy", cat = "s", class = "pure", run = function(tt)
    t.Advance(0.050)   -- one 50 ms step that cannot yield
    tt:Check(true)
  end }
  TL.Case{ id = "after", cat = "s", class = "pure", run = function(tt) tt:Check(true) end }
  local done
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  local frames = Drive(RN)
  Check(done and done.ended == "complete", "finished")
  Check(frames >= 4, "20 steps of 1.1 ms need several 5 ms slices, used " .. frames)
  Same(steps, 20)
  Same(done.counts.pass, 3, "all three pass")
  Same(done.overrunCount, 1, "exactly one step overran the slice")
  Same(done.overruns[1].id, "heavy", "and it names the case")
  Check(done.overruns[1].ms >= 49, "with its measured length")
  Check(done.worstSlice >= 0.050, "the worst slice includes the step that could not be cut short")
  Check(done.worstFrame >= 0.016 - 1e-9, "the worst frame is the frame time the game gave")
  Check(done.slices >= frames - 1)
  -- a yielding case's slice stays near the budget: no frame but the heavy one exceeds it by more than one step
  local report = TL.Report.Build(done)
  Check(report:find("overruns (a resume ran longer than the slice and could not be interrupted): 1 in all, the 1 longest", 1, true), "the report says so")
  Check(report:find("heavy  %d+%.%d ms, one resume"), "and lists it")
  Check(report:find("by case: heavy 1 (worst 50 ms)", 1, true), "and counts it by case")
end

-- M7.1: the report keeps the LONGEST overruns, not the first ones, counts all of them, and counts them by case
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "o", label = "O" }
  local N = 26
  for k = 1, N do
    -- case k holds one step of 10 + k ms, except the LAST case, which holds the longest of all (400 ms)
    local ms = k == N and 400 or (10 + k)
    TL.Case{ id = ("c%02d"):format(k), cat = "o", class = "pure", run = function(tt) t.Advance(ms / 1000) tt:Check(true) end }
  end
  local done
  Check(RN.Start(TL.Select(), { cats = { "o" }, clock = t.Now, onDone = function(s) done = s end }))
  Drive(RN)
  Check(done, "finished")
  Same(done.overrunCount, N, "every overrun is counted")
  Same(#done.overruns, RN.MAX_OVERRUNS, "the list is bounded")
  Same(done.overruns[1].id, ("c%02d"):format(N), "and the longest comes first although it came last")
  Check(done.overruns[1].ms >= 399, "with its length")
  for i = 2, #done.overruns do Check(done.overruns[i - 1].ms >= done.overruns[i].ms, "longest first") end
  Check(done.overruns[#done.overruns].ms > 10 + (N - RN.MAX_OVERRUNS) + 0.5, "the shortest kept is longer than the ones left out")
  Same(#done.overrunOrder, N, "the per-case figures cover every case"); Same(done.overrunBy["c01"].n, 1)
  local report = TL.Report.Build(done)
  Check(report:find("%d+ in all, the 20 longest"), "the report says how many were left out")
  Check(report:find("c26  400.0 ms"), "the longest is listed")
  Check(not report:find("c01  11.0 ms, one resume", 1, true), "an early short one is not")
end

---------------------------------------------------------------------------
-- 3b. Time spent BEFORE a case's first step (loading the Workshop on demand) is inside the slice, so it must be attributed. Found while
--     reading the first full real-client report (worst slice 35.1 ms, worst frame 50 ms, overruns 0): Step timed only the case's own steps,
--     so a slow setup made a long slice that no overrun named.
---------------------------------------------------------------------------
do
  local loaded, t = false, nil
  local launcher = { Loaded = function() return loaded end, Explain = function(code) return code end,
    Load = function() t.Advance(0.030) loaded = true return true end }   -- loading the addon takes 30 ms and cannot yield
  t = Setup({ launcher = launcher })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  TL.Case{ id = "needs.workshop", cat = "s", class = "pure", needs = { "workshop" }, run = function(tt) tt:Check(true) end }
  TL.Case{ id = "quick", cat = "s", class = "pure", run = function(tt) tt:Check(true) end }
  local done
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  Drive(RN)
  Check(done and done.ended == "complete" and done.counts.pass == 2, "finished, both pass")
  Check(done.worstSlice >= 0.030, "the slice holds the 30 ms load")
  Same(done.overrunCount, 1, "and the load is an overrun, not unaccounted time")
  Same(done.overruns[1].id, "needs.workshop", "named after the case that needed it")
  Check(done.overruns[1].ms >= 29, "with its measured length")
  -- the one-time load is listed apart as setup, and is not charged to the case's own time (milestone 6)
  Same(#done.setups, 1, "the load is listed as setup")
  Same(done.setups[1].id, "needs.workshop"); Same(done.setups[1].what, "Workshop load"); Check(done.setups[1].ms >= 29)
  Same(done.overruns[1].setup, "Workshop load", "the overrun says it is setup, not the case's own work")
  Check(done.results[1].ms < 5, "the case's own time does not include the load (" .. tostring(done.results[1].ms) .. " ms)")
  Check(done.results[1].status == "pass")
  local text = TL.Report.Build(done)
  Check(text:find("setup (one-time, before the case named;", 1, true) and text:find("Workshop load  3%d%.%d ms, before needs.workshop"), "the report lists it: " .. text)
  Check(text:find("(setup: Workshop load, not the case's own work)", 1, true), "and marks the overrun as setup")
  -- a second case needing the Workshop, already loaded, adds no setup
  local again
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) again = s end }))
  Drive(RN)
  Same(#again.setups, 0, "once loaded, no setup is listed")
end

---------------------------------------------------------------------------
-- 4. Stop: the rest is "stopped", nothing is resumed, nothing is left running; Stop inside a step waits for the step
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  local ran = { a = 0, b = 0, c = 0 }
  TL.Case{ id = "a", cat = "s", class = "pure", run = function(tt) for _ = 1, 50 do ran.a = ran.a + 1; t.Advance(0.003); tt:Yield() end end }
  TL.Case{ id = "b", cat = "s", class = "pure", run = function() ran.b = ran.b + 1 end }
  TL.Case{ id = "c", cat = "s", class = "pure", run = function() ran.c = ran.c + 1 end }
  local done
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  local fr = RN.frameForTests()
  Check(fr.scripts.OnUpdate and fr.events.PLAYER_REGEN_DISABLED, "while running: the OnUpdate and the combat event exist")
  fr.scripts.OnUpdate(fr, 0.016)
  Check(RN.Active() and ran.a > 0 and ran.a < 50, "one frame ran part of case a (" .. ran.a .. ")")
  local at = ran.a
  Check(RN.Stop("user"), "Stop is accepted")
  Check(not RN.Active() and done, "the run ended at once")
  Same(done.ended, "user")
  Same(done.results[1].status, "stopped"); Check(done.results[1].detail:find("not resumed", 1, true), "a: " .. tostring(done.results[1].detail))
  Same(done.results[2].status, "stopped"); Same(done.results[3].status, "stopped")
  Check(done.results[2].detail:find("before it started", 1, true))
  Same(done.counts.stopped, 3)
  Check(not fr.scripts.OnUpdate, "no OnUpdate is left"); Check(not fr.events.PLAYER_REGEN_DISABLED, "and the combat event is released")
  Same(ran.a, at, "case a was not resumed"); Same(ran.b, 0, "case b never ran"); Same(ran.c, 0, "case c never ran")
  Check(not RN.Stop("user"), "Stop on an idle runner says so")
  local text = TL.Report.Build(done)
  Check(text:find("ended: user", 1, true)); Check(text:find("not run", 1, true), "never-started cases are labelled not run")

  -- Stop called from inside a step takes effect when that step returns, and no later case starts
  ran = { a = 0, b = 0, c = 0 }
  done = nil
  TL.cases.b.run = function() ran.b = ran.b + 1; RN.Stop("user") end
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  TL.cases.a.run = function() ran.a = ran.a + 1 end
  Drive(RN)
  Same(ran.a, 1); Same(ran.b, 1); Same(ran.c, 0, "case c was not started")
  Same(done.results[1].status, "pass"); Same(done.results[2].status, "pass", "the step that asked to stop finished, so it keeps its result")
  Same(done.results[3].status, "stopped"); Same(done.ended, "user")
end

---------------------------------------------------------------------------
-- 4b. t:Wait: a pause across frames that schedules nothing meanwhile; Stop and the budget still apply to it
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  local resumes, measured = 0, nil
  TL.Case{ id = "waiter", cat = "s", class = "pure", budget = 10, run = function(tt)
    resumes = resumes + 1
    local a = RN.Now()
    tt:Wait(1)
    resumes = resumes + 1
    measured = RN.Now() - a
    tt:Check(true)
  end }
  TL.Case{ id = "after", cat = "s", class = "pure", run = function(tt) tt:Check(true) end }
  local done
  Check(RN.Start(TL.Select(), { clock = t.Clock, onDone = function(s) done = s end }))
  local frames = Drive(RN, 500, 0.016, t)
  Same(resumes, 2, "the case was resumed twice: before and after the pause, never in between")
  Check(measured >= 1 and measured < 1.05, "the pause lasted about a second of the clock (" .. tostring(measured) .. ")")
  Check(frames >= 62 and frames <= 66, "spread over frames at 16 ms (" .. frames .. ")")
  Same(done.counts.pass, 2); Same(done.overrunCount, 0, "waiting is not work")
  -- Stop during the pause: the case is not resumed
  resumes = 0
  done = nil
  Check(RN.Start(TL.Select(), { clock = t.Clock, onDone = function(s) done = s end }))
  local fr = RN.frameForTests()
  for _ = 1, 5 do t.Advance(0.016); fr.scripts.OnUpdate(fr, 0.016) end
  Same(resumes, 1, "it is waiting")
  RN.Stop("user")
  Same(resumes, 1, "and was not resumed by Stop"); Same(done.results[1].status, "stopped"); Same(done.results[2].status, "stopped")
  -- a pause longer than the budget: abandoned while waiting, the next case runs
  TL.cases.waiter.budget = 0.5
  resumes, done = 0, nil
  Check(RN.Start(TL.Select(), { clock = t.Clock, onDone = function(s) done = s end }))
  Drive(RN, 500, 0.016, t)
  Same(done.results[1].status, "timeout"); Check(done.results[1].detail:find("not resumed", 1, true))
  Same(done.results[2].status, "pass"); Same(resumes, 1, "never resumed after the budget was spent")
end

---------------------------------------------------------------------------
-- 5. Timeouts, late finishes, the run cap, errors, skips, failures, the Workshop being unavailable
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  local forever = 0
  TL.Case{ id = "forever", cat = "s", class = "pure", budget = 0.5, run = function(tt) while true do forever = forever + 1; t.Advance(0.1); tt:Yield() end end }
  TL.Case{ id = "late", cat = "s", class = "pure", budget = 0.5, run = function(tt) t.Advance(2); tt:Check(true) end }
  TL.Case{ id = "boom", cat = "s", class = "pure", run = function() error("kaput") end }
  TL.Case{ id = "skipper", cat = "s", class = "pure", run = function(tt) tt:Skip("not today"); error("not reached") end }
  TL.Case{ id = "wrong", cat = "s", class = "pure", run = function(tt) tt:Same(3, 2, "the answer"); tt:Check(false, "second") end }
  TL.Case{ id = "needy", cat = "s", class = "pure", needs = { "workshop" }, run = function() error("must not run") end }
  TL.Case{ id = "last", cat = "s", class = "pure", run = function(tt) tt:Fact("a.b c", "v|w"); tt:Check(true) end }
  local done
  Check(RN.Start(TL.Select(), { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  Drive(RN)
  local by = {}
  for _, r in ipairs(done.results) do by[r.id] = r end
  Same(done.ended, "complete", "an erroring case does not stop the run")
  Same(by.forever.status, "timeout"); Check(by.forever.detail:find("abandoned at a yield point", 1, true) and by.forever.detail:find("not resumed", 1, true), by.forever.detail)
  local n = forever
  Check(n >= 5 and n <= 7, "it was resumed only until its 0.5 s were spent (" .. n .. " steps)")
  Same(by.late.status, "pass", "a step that overran its budget and finished keeps its result")
  Check(by.late.detail:find("late:", 1, true) and by.late.detail:find("could not be interrupted", 1, true), by.late.detail)
  Same(by.boom.status, "error"); Check(by.boom.detail:find("kaput", 1, true))
  Same(by.skipper.status, "skipped"); Same(by.skipper.detail, "not today")
  Same(by.wrong.status, "fail"); Check(by.wrong.detail:find("the answer: expected 2, got 3", 1, true), by.wrong.detail)
  Check(by.wrong.detail:find("second", 1, true), "every failure is listed")
  Same(by.needy.status, "skipped", "no launcher, no Workshop"); Check(by.needy.detail:find("launcher", 1, true), by.needy.detail)
  Same(by.last.status, "pass")
  Same(by.last.facts[1][1], "a.b_c", "fact keys are cleaned"); Same(by.last.facts[1][2], "v w", "and values")
  Same(done.counts.timeout, 1)

  -- the run cap
  TL.cases.forever.budget = 60
  done = nil
  Check(RN.Start({ TL.cases.forever, TL.cases.last }, { cats = { "s" }, clock = t.Now, cap = 1, onDone = function(s) done = s end }))
  Drive(RN)
  Same(done.ended, "cap"); Same(done.results[1].status, "stopped"); Same(done.results[2].status, "stopped")
  Check(done.results[2].detail:find("time cap", 1, true), done.results[2].detail)
  Check(not RN.Snapshot().updating)

  -- a launcher that refuses (combat) gives the case's skip reason; a launcher that loads gives the Workshop
  t.R.WorkshopLauncher = { Loaded = function() return false end, Load = function() return false, "COMBAT" end, Explain = function(code) return "couldn't open the Workshop: " .. code end }
  done = nil
  Check(RN.Start({ TL.cases.needy }, { cats = { "s" }, clock = t.Now, onDone = function(s) done = s end }))
  Drive(RN)
  Same(done.results[1].status, "skipped"); Check(done.results[1].detail:find("COMBAT", 1, true), done.results[1].detail)

  -- a run that is already going, an empty list
  Check(RN.Start({ TL.cases.last }, { clock = t.Now }))
  local ok, why = RN.Start({ TL.cases.last }, { clock = t.Now })
  Check(ok == false and why == "running", "one run at a time")
  RN.Stop("user")
  ok, why = RN.Start({}, {})
  Check(ok == false and why == "empty")
end

---------------------------------------------------------------------------
-- 6. Combat: refused to start, stops a run (by the event and by the check each frame), and the event is only listened to during a run
---------------------------------------------------------------------------
do
  local t = Setup({ noWorkshop = true })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  local made = wire(RN)
  TL.Category{ id = "s", label = "S" }
  local steps = 0
  TL.Case{ id = "slow", cat = "s", class = "pure", run = function(tt) while true do steps = steps + 1; t.Advance(0.01); tt:Yield() end end }
  TL.Case{ id = "next", cat = "s", class = "pure", run = function(tt) tt:Check(true) end }
  t.c.COMBAT = true
  local ok, why = RN.Start(TL.Select(), { clock = t.Now })
  Check(ok == false and why == "combat", "refused in combat")
  Check(#made == 0 or not (RN.frameForTests() and RN.frameForTests().events.PLAYER_REGEN_DISABLED), "nothing is listening after a refusal")
  Check(not RN.Active())
  t.c.COMBAT = false

  local done
  Check(RN.Start(TL.Select(), { clock = t.Now, onDone = function(s) done = s end }))
  local fr = RN.frameForTests()
  fr.scripts.OnUpdate(fr, 0.016)
  local at = steps
  t.c.COMBAT = true
  fr.scripts.OnEvent(fr, "PLAYER_REGEN_DISABLED")
  Same(done.ended, "combat", "the event stops the run")
  Same(done.results[1].status, "stopped"); Same(done.results[2].status, "stopped")
  Check(done.results[1].detail:find("combat started", 1, true), done.results[1].detail)
  Same(steps, at, "no further step")
  Check(not fr.scripts.OnUpdate and not fr.events.PLAYER_REGEN_DISABLED)
  t.c.COMBAT = false

  done = nil
  Check(RN.Start(TL.Select(), { clock = t.Now, onDone = function(s) done = s end }))
  fr.scripts.OnUpdate(fr, 0.016)
  t.c.COMBAT = true
  fr.scripts.OnUpdate(fr, 0.016)   -- the check each frame stops it even without the event
  Same(done.ended, "combat"); Check(not RN.Active())
end

---------------------------------------------------------------------------
-- 7. A read-only case that changes saved data fails (the fingerprint); the Lab's own cases leave everything as it was
---------------------------------------------------------------------------
do
  local db = { modules = {}, workshop = { v = 1 } }
  local t = Setup({ TwichUIDB = db, TwichUIWorkshopDB = { v = 1, markets = {} } })
  local wire = WireFrames(t)
  t.Load({ "Lab.lua", "Runner.lua", "Report.lua" })
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  TL.Category{ id = "s", label = "S" }
  TL.Case{ id = "vandal", cat = "s", class = "readonly", run = function(tt) t.c.TwichUIDB.extra = true; tt:Check(true) end }
  TL.Case{ id = "market", cat = "s", class = "readonly", run = function(tt) t.c.TwichUIWorkshopDB.markets.k = { at = 1, n = 1 }; tt:Check(true) end }
  TL.Case{ id = "reader", cat = "s", class = "readonly", run = function(tt) tt:Check(t.c.TwichUIDB ~= nil) end }
  local done
  Check(RN.Start(TL.Select(), { clock = t.Now, onDone = function(s) done = s end }))
  Drive(RN)
  Same(done.results[1].status, "fail"); Check(done.results[1].detail:find("saved data changed", 1, true), done.results[1].detail)
  Same(done.results[2].status, "fail", "a new market is noticed too")
  Same(done.results[3].status, "pass")
  Check(TL.Fingerprint():find("TwichUIDiagnosticsDB=none", 1, true), "an absent root is fingerprinted as absent")
end

---------------------------------------------------------------------------
-- 8. The report: fixed header, a line per case with its label, facts, redaction; the whole registered set, client cases included
---------------------------------------------------------------------------
do
  local t = Setup()
  local wire = WireFrames(t)
  t.Load(LabFiles())
  local TL = t.TL
  local RN = TL.Runner
  wire(RN)
  t.c.C_AddOns.GetAddOnMetadata = function(name, field) if field == "Version" then return name == "TwichUI_Workshop" and "1.2.3" or "9.9.9" end end
  local done
  Check(RN.Start(TL.Select({ core = true, client = true }), { cats = { "core", "client" }, clock = t.Clock, onDone = function(s) done = s end }))
  local frames = Drive(RN, 500, 0.016, t)
  Check(frames >= 120, "the 2 s pause probe took its frames (" .. frames .. ")")
  local all = {}
  for _, r in ipairs(done.results) do if r.status ~= "pass" then all[#all + 1] = r.id .. " " .. r.status .. " " .. tostring(r.detail) end end
  Same(table.concat(all, "\n"), "", "every registered case passes offline (core and client)")
  local text = TL.Report.Build(done)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  Same(lines[1], "TWICHUI-TESTLAB REPORT schema 1")
  Check(lines[2]:find("^client 1%.60%.1 build 70009 interface 16001 | TwichUI 9.9.9 | Workshop 1%.2%.3 | TestLab 0%.1%.0%-dev$"), lines[2])
  Check(lines[3]:find("^run: core,client | %d+ cases: %d+ pass, 0 fail, 0 skipped, 0 error, 0 timeout, 0 stopped | %d+%.%d%d s | slices %d+, worst %d+%.%d ms, worst frame %d+ ms, overruns 0 | ended: complete$"), lines[3])
  Check(lines[4]:find("^clock: GetTimePreciseSec | slice 5 ms | cooperative"), lines[4])
  Check(lines[5]:find("^labels: client = observed in this game client | synthetic ="), lines[5])
  local n = #done.results
  local noteLines = 0
  for _, r in ipairs(done.results) do noteLines = noteLines + #(r.notes or {}) end
  Same(#lines, 5 + n + noteLines + 1, "five header lines, one line per case and per evidence note, one facts line")
  Check(lines[6]:find("^PASS    price%.unit%.round%-up  synthetic %d+%.%d ms$"), lines[6])
  local client = 0
  for i = 6, 5 + n + noteLines do
    local l = lines[i]
    if not l:find("^        ") then   -- an evidence note is indented under its case
      Check(l:find("^PASS    [%w%.%-]+  %a+ +[%d%.]+ ms"), "line format: " .. l)
      if l:find("^PASS    client%.") then client = client + 1; Check(l:find(" client "), "client cases are labelled client: " .. l) end
    end
  end
  Check(client >= 4, "the client cases are in the report (" .. client .. ")")
  Check(lines[#lines]:find("^facts: client%.api%.C_AddOnProfiler=nil client%.api%.EnumerateFrames=nil"), lines[#lines])
  Check(lines[#lines]:find("client.lua.div_zero_ok=true", 1, true) and lines[#lines]:find("client.clock.source=GetTimePreciseSec", 1, true), "facts are listed")
  Check(lines[#lines]:find("client.lua.yield_across_pcall=", 1, true))
  Check(#text < 30000, "within the size the roadmap sets")
  -- redaction: nothing of the mock's character or realm anywhere
  Check(not text:find("Zzchar", 1, true) and not text:find("Zzrealm", 1, true), "no character or realm name")
  -- text from a case is cleaned: links, colour codes, control characters, bars, length
  local Clean = TL.Report.Clean
  Same(Clean("saw |cff0070dd|Hitem:19019::::::::60|h[Thunderfury]|h|r now"), "saw [link] now")
  Same(Clean("a\nb\tc|d"), "a b c/d")
  Same(#Clean(("x"):rep(1000)), 243, "cut to 240 and marked")
  -- a failing case shows its expected and actual values in the report
  local fake = { results = { { id = "x.y", status = "fail", label = "synthetic", detail = "expected 1, got 2", ms = 0.5, facts = {} } }, counts = { pass = 0, fail = 1, skipped = 0, error = 0, timeout = 0, stopped = 0 },
    cats = { "core" }, seconds = 0.01, slices = 1, worstSlice = 0.001, worstFrame = 0.016, overruns = {}, overrunCount = 0, ended = "complete", clock = "GetTime", slice = 0.005 }
  Check(TL.Report.Build(fake):find("FAIL    x.y  synthetic 0.5 ms  expected 1, got 2", 1, true))
end

---------------------------------------------------------------------------
-- 9. The window: built once, opens once at load, /tuilab, Run / Stop / Copy, Esc, closing stops a run, no OnUpdate of its own
---------------------------------------------------------------------------
do
  local db = { modules = {}, workshop = { v = 1 } }
  local before = DeepCopy(db)
  local t = Setup({ TwichUIDB = db })
  local wire = WireFrames(t)
  t.Load(LabFiles())
  local TL = t.TL
  local RN, Win = TL.Runner, TL.Window
  wire(RN)
  local win = Win.Frame()
  Check(win and win:IsShown(), "opened once by loading")
  local esc = false
  for _, n in ipairs(t.c.UISpecialFrames) do if n == "TwichUITestLabWindow" then esc = true end end
  Check(esc, "Esc closes it through UISpecialFrames")
  Check(not win.scripts.OnUpdate, "the window itself has no OnUpdate")
  Check(t.c.SlashCmdList.TWICHUILAB and t.c.SLASH_TWICHUILAB1 == "/tuilab", "/tuilab is registered")
  t.c.SlashCmdList.TWICHUILAB()
  Check(not win:IsShown(), "/tuilab closes it"); t.c.SlashCmdList.TWICHUILAB(); Check(win:IsShown(), "and opens it")
  Check(not RN.Active(), "nothing runs by itself")

  -- Copy before any run
  Check(not Win.Copy(), "no report yet")
  -- no category chosen
  -- the guided category starts unticked (it asks things of the player); the others start ticked
  Check(win.boxes.pointer:GetChecked() == false, "the guided category is not ticked for the player")
  for _, box in pairs(win.boxes) do if box:GetChecked() then box:GetScript("OnClick")(box) end end   -- clears every box
  Check(not Win.Run(), "nothing chosen, nothing runs"); Check(not RN.Active())
  for _, id in ipairs({ "core", "client" }) do local box = win.boxes[id]; box:GetScript("OnClick")(box) end   -- chooses the two the rest of this section runs

  Check(Win.Run(), "Run starts a run")
  Check(RN.Active() and not win.run:IsEnabled() and win.stop:IsEnabled(), "Run is off and Stop is on while it runs")
  Check(not Win.Run(), "a second Run is refused")
  Drive(RN, 500, 0.016, t)
  Check(not RN.Active() and win.run:IsEnabled() and not win.stop:IsEnabled() and win.copy:IsEnabled(), "buttons after the run")
  Check(win.cards.fail.value:GetText() == "0" and win.cards.error.value:GetText() == "0", "the cards count no failure and no error")
  Check(win.stateText:GetText():find("Finished", 1, true), win.stateText:GetText())
  Check(Win.Copy(), "Copy works after a run")
  Check(win.edit:GetText():find("^TWICHUI%-TESTLAB REPORT schema 1"), "the box holds the report")
  Check(win.edit.focus, "and has focus (the player presses Ctrl+C)")
  Check(not win.edit.scripts.OnUpdate)
  win.edit:SetText("typed over")
  win.edit.scripts.OnTextChanged(win.edit, true)
  Check(win.edit:GetText():find("^TWICHUI%-TESTLAB REPORT"), "typing puts the report back")

  -- Stop from the button's script, mid-run
  Check(Win.Run())
  local fr = RN.frameForTests()
  fr.scripts.OnUpdate(fr, 0.016)
  Check(RN.Active(), "still running after one frame")
  win.stop:GetScript("OnClick")(win.stop)
  Check(not RN.Active() and not fr.scripts.OnUpdate, "Stop ends the run and the OnUpdate")
  Check(win.stateText:GetText() == "Stopped", win.stateText:GetText())
  Check(win.note:GetText():find("could not have been interrupted", 1, true), "the window does not claim it interrupted a step: " .. win.note:GetText())

  -- closing the window stops a run
  Check(Win.Run())
  fr.scripts.OnUpdate(fr, 0.016)
  win:Hide()
  Check(not RN.Active() and RN.last.ended == "closed", "closing stops the run")
  Same(t.timers(), 0, "the Lab created no timer")
  local snap = RN.Snapshot()
  Check(not snap.updating and not snap.listening)
  -- in combat: a clear message
  t.c.COMBAT = true
  win:Show()
  Check(not Win.Run() and win.note:GetText():find("combat", 1, true), win.note:GetText())
  t.c.COMBAT = false
  Check(DeepSame(db, before), "TwichUIDB is unchanged by loading, running and closing the window")
end

---------------------------------------------------------------------------
-- 10. A static scan of the Lab's files: no consequential API, no hooks, no loading of data as code, no writes to the saved roots
---------------------------------------------------------------------------
do
  local files = {}
  local p = io.popen('find "' .. LAB .. '" -name "*.lua" | sort')
  for path in p:lines() do files[#files + 1] = path end
  p:close()
  Check(#files == 22, "the scan found the Lab's files (" .. #files .. ")")
  -- every file the .toc loads is scanned, and nothing is loaded that is not
  local scanned = {}
  for _, path in ipairs(files) do scanned[path:sub(#LAB + 1)] = true end
  for _, f in ipairs(LabFiles()) do Check(scanned[f], f .. " is in the scan"); scanned[f] = nil end
  for f in pairs(scanned) do error(f .. " is in the folder but not in the .toc") end

  local FORBIDDEN = {
    -- the Workshop's writes and the scan (docs/testlab.md lists why)
    "Commit", "BeginCommit", "Apply", "Queue.", "Known.Store", "Vendor.", "Storage.", "Session.", "Scan.Start", "Observe.OpenRecipe", "ReplicateItems",
    -- anything that buys, bids, posts, cancels, mails, trades, destroys, uses, crafts or sends
    "PlaceBid", "PostItem", "PostCommodity", "CommoditiesPurchase", "CancelAuction", "SendMail", "TakeInbox", "AcceptTrade", "InitiateTrade",
    "DeleteCursorItem", "PickupContainerItem", "UseContainerItem", "UseItemByName", "CastSpell", "Disenchant", "Destroy", "CraftRecipe", "BuyMerchantItem", "SellContainerItem",
    "SendAddonMessage", "SendChatMessage", "SendCommMessage", "SetCVar",
    -- taint, hooks, loading data as code, the game menu's Esc handler
    "hooksecurefunc", "securecall", "setfenv", "getfenv", "loadstring", "RegisterGameMenuEscHandler", "rawset", "load(", "dofile", "require",
    -- input: nothing persistent (a saved binding), no keyboard capture; the one temporary override binding lives in Guided.lua alone (checked below)
    "SaveBindings", "SetBinding", "LoadBindings", "EnableKeyboard", "SetPropagateKeyboardInput", "OnKeyDown", "OnKeyUp", "OnChar",
  }
  for _, path in ipairs(files) do
    local f = assert(io.open(path)); local src = f:read("*a"); f:close()
    local code = src:gsub("%-%-[^\n]*", "")   -- comments are not code (the Lab has no long comments)
    Check(not code:find("%-%-%[=*%["), path .. " has a long comment the scan would misread")
    for _, name in ipairs(FORBIDDEN) do
      Check(not code:find(name, 1, true), path:sub(#LAB + 1) .. " uses forbidden name " .. name)
    end
    for _, root in ipairs({ "TwichUIDB", "TwichUIWorkshopDB", "TwichUIDiagnosticsDB" }) do
      Check(not code:find(root .. "%s*[=%.%[]"), path:sub(#LAB + 1) .. " touches the saved root " .. root)
    end
    Check(not code:find("_G%s*%[[^%]]*%]%s*=[^=]"), path:sub(#LAB + 1) .. " assigns through _G[...]")
    Check(not code:find("[^%w_]_G%.[%w_]+%s*=[^=]"), path:sub(#LAB + 1) .. " assigns a global through _G")
  end
  -- the temporary key binding: only Guided.lua has it, owned by its own button, and it is only ever cleared for that owner
  for _, path in ipairs(files) do
    local f = assert(io.open(path)); local src = f:read("*a"); f:close()
    local code = src:gsub("%-%-[^\n]*", "")
    local isGuided = path:sub(#LAB + 1) == "Guided.lua"
    -- elsewhere a name may appear only as a quoted string (the API presence report asks whether the function exists; it never calls it)
    local uses = (isGuided and code or code:gsub('"[^"\n]*"', '""')):find("OverrideBinding", 1, true) ~= nil
    Check(uses == isGuided, path:sub(#LAB + 1) .. (uses and " uses an override binding and is not Guided.lua" or " should use the override binding"))
  end
  do
    local f = assert(io.open(LAB .. "Guided.lua")); local code = f:read("*a"):gsub("%-%-[^\n]*", ""); f:close()
    local _, binds = code:gsub("SetOverrideBindingClick%(", "")
    local _, clears = code:gsub("ClearOverrideBindings", "")
    Check(code:find("pcall(SetOverrideBindingClick, p, true, key, G.NAME", 1, true), "the binding is made for the Lab's own button, with the one key")
    Check(code:find("pcall(ClearOverrideBindings, proxy)", 1, true), "and cleared for that owner")
    Check(not code:find("ClearOverrideBindings, UIParent", 1, true) and not code:find("ClearOverrideBindings(UIParent", 1, true), "never cleared for UIParent")
    Check(binds == 0 and clears <= 4, "no other override-binding calls: " .. binds .. " direct binds, " .. clears .. " mentions of the clear")
  end
  -- the scan itself works: a planted violation is found
  local planted = "TwichUIWorkshopDB = {}"
  Check(planted:find("TwichUIWorkshopDB%s*[=%.%[]"), "the root pattern finds an assignment")
  -- the cases never read the saved roots either: Core.lua and Client.lua call no Workshop function that reads them
  local core = assert(io.open(LAB .. "cases/Core.lua")):read("*a")
  Check(not core:find("Market%.Source") and not core:find("Market%.Markets") and not core:find("PR%.Market%(") and not core:find("MK%.Info"),
    "the core cases never ask for a saved market")
end

print("PASSED test_testlab")
