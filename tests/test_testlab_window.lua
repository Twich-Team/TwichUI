-- The Test Lab's redesigned window (TwichUI_TestLab/Window.lua, Kit.lua) and the presentation logic behind it (View.lua), offline.
--   * View.lua, pure: categories from the registry, tallies, filters and search, the summary cards, the run state, the empty-state sentences,
--     the details of a result for every outcome (nothing invented), and that none of it changes a record;
--   * Report.BuildFailures: the excerpt, and that the full report is untouched;
--   * the window under the offline mock: layout from the registry, Run/Stop/Copy states, the cards and the run state through a real run
--     (pass, fail, error, skipped, timeout), filters and search, selection (a failure is chosen at once, the player's own choice is kept),
--     copying, the guided opt-in and the window stepping aside, row pooling and scrolling, repeated open/close without growth, saved data and key
--     bindings untouched, and a smaller screen.
-- Synthetic: it proves the logic and the construction, not how the window looks (docs/testlab.md "The window" lists the visual evidence).
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local LAB = ROOT .. "../TwichUI_TestLab/"
local WORKSHOP_FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

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


-- A client with the Lab's files; fx categories are registered BEFORE the window is built, as every real category is (the .toc loads the
-- cases first, the window last). opts.screen = { w, h } sets the screen the window is sized for.
local function Lab(opts)
  opts = opts or {}
  local db = opts.db or { modules = {}, workshop = { v = 1 } }
  local t = Setup({ TwichUIDB = db, noWorkshop = true })
  t.db = db
  local wire = WireFrames(t)
  if opts.screen then t.c.UIParent.w, t.c.UIParent.h = opts.screen[1], opts.screen[2] end
  local files = LabFiles()
  local before = {}
  for _, f in ipairs(files) do if f ~= "Kit.lua" and f ~= "Window.lua" then before[#before + 1] = f end end
  t.Load(before)
  local TL = t.TL
  t.made = wire(TL.Runner)
  TL.Category{ id = "fx", label = "Fixture group", blurb = "cases made up for this test" }
  TL.Case{ id = "fx.pass", cat = "fx", class = "pure", run = function(tt) tt:Same(1, 1, "one"); tt:Fact("seed", "7100008"); tt:Fact("k2", "v2") end }
  TL.Case{ id = "fx.fail", cat = "fx", class = "pure", run = function(tt)
    tt:Same(4, 5, "seed 7100008: bid-only records"); tt:Same(6, 5, "second check"); tt:Note("first differing record 10 (invalid)") end }
  TL.Case{ id = "fx.error", cat = "fx", class = "pure", run = function() error("boom from the case") end }
  TL.Case{ id = "fx.skip", cat = "fx", class = "pure", run = function(tt) tt:Skip("the Workshop is not open") end }
  TL.Case{ id = "fx.slow", cat = "fx", class = "pure", budget = 0.5, run = function(tt) while true do t.Advance(0.2); tt:Yield() end end }
  TL.Category{ id = "fxg", label = "Guided fixture", blurb = "waits for a person", guided = true }
  TL.Case{ id = "fxg.step", cat = "fxg", class = "guided", budget = 5, run = function(tt) tt:Wait(0.001); tt:Check(true) end }
  TL.Category{ id = "fxp", label = "Passing group", blurb = "only passes" }
  for i = 1, 3 do TL.Case{ id = "fxp.ok" .. i, cat = "fxp", class = "pure", run = function(tt) tt:Check(true, "ok") end } end
  TL.Category{ id = "fxy", label = "Waiting group", blurb = "one case that waits across frames" }
  TL.Case{ id = "fxy.wait", cat = "fxy", class = "pure", budget = 5, run = function(tt) tt:Wait(0.3); tt:Check(true) end }
  t.Load({ "Kit.lua", "Window.lua" })
  t.win = TL.Window.Frame()
  return t, TL
end

local function Tick(win, id) local b = win.boxes[id]; b:GetScript("OnClick")(b) end
-- ticks exactly the groups listed
local function Choose(win, ids)
  local want = {}
  for _, id in ipairs(ids) do want[id] = true end
  for id, box in pairs(win.boxes) do if box:GetChecked() ~= (want[id] == true) then Tick(win, id) end end
end

local function Rec(id, status, extra)
  local r = { id = id, status = status, class = "pure", label = "synthetic", cat = "x", facts = {} }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

---------------------------------------------------------------------------
-- 1. View.lua: pure
---------------------------------------------------------------------------
do
  local t, TL = Lab()
  local V, RP = TL.View, TL.Report
  -- the categories are the registry's, with their real counts, in registration order; a category added later is listed too
  local cats = V.Categories()
  Same(#cats, #TL.categoryOrder, "one entry per registered category")
  for i, c in ipairs(cats) do
    Same(c.id, TL.categoryOrder[i]); Same(c.count, TL.Count(c.id), c.id .. " count comes from the registry"); Same(c.label, TL.categories[c.id].label)
  end
  Same(cats[#cats - 3].id, "fx"); Same(cats[#cats - 3].count, 5, "the fixture group has its five cases")
  TL.Category{ id = "late", label = "Late" }
  TL.Case{ id = "late.a", cat = "late", class = "readonly", run = function() end }
  Same(V.Categories()[#V.Categories()].count, 1, "a category registered later is listed with its count")

  local results = {
    Rec("a.pass", "pass", { ms = 0.4, checks = 3 }), Rec("b.fail", "fail", { ms = 164.5, detail = "seed 7100008: bid-only records: expected 4, got 5", fails = { "seed 7100008: bid-only records: expected 4, got 5" }, failed = 1 }),
    Rec("c.client", "pass", { class = "readonly", label = "client", ms = 2 }), Rec("d.guided", "pass", { class = "guided", label = "guided", ms = 29922.1 }),
    Rec("e.skip", "skipped", { detail = "the Workshop is not open" }), Rec("f.err", "error", { detail = "boom" }), Rec("g.slow", "timeout", { detail = "abandoned at a yield point" }),
    Rec("h.stopped", "stopped", { detail = "Stop was pressed before it started" }), Rec("i.guided2", "stopped", { class = "guided", label = "guided" }),
  }
  local frozen = {}
  for i, r in ipairs(results) do frozen[i] = { r.id, r.status, r.detail, r.ms } end
  local c = V.Counts(results)
  Same(c.all, 9); Same(c.fail, 1); Same(c.pass, 3); Same(c.guided, 2); Same(c.client, 1); Same(c.synthetic, 6)
  Same(c.skipped, 1); Same(c.error, 1); Same(c.timeout, 1); Same(c.stopped, 2)
  local tl = V.Tally(results)
  Same(tl.total, 9); Same(tl.pass, 3); Same(tl.finished, 7, "finished = pass, fail, skipped, error, timeout"); Same(tl.stopped, 2)
  local function Ids(list) local o = {} for _, r in ipairs(list) do o[#o + 1] = r.id end return table.concat(o, ",") end
  Same(Ids(V.Select(results, "all", "")), "a.pass,b.fail,c.client,d.guided,e.skip,f.err,g.slow,h.stopped,i.guided2")
  Same(Ids(V.Select(results, "fail", "")), "b.fail"); Same(Ids(V.Select(results, "pass", "")), "a.pass,c.client,d.guided")
  Same(Ids(V.Select(results, "guided", "")), "d.guided,i.guided2"); Same(Ids(V.Select(results, "client", "")), "c.client")
  Same(Ids(V.Select(results, "error", "")), "f.err"); Same(Ids(V.Select(results, "timeout", "")), "g.slow"); Same(Ids(V.Select(results, "skipped", "")), "e.skip")
  Same(Ids(V.Select(results, "stopped", "")), "h.stopped,i.guided2")
  -- search: the id, the kind, the status word and the message; every word must match; case does not matter; never a pattern
  Same(Ids(V.Select(results, "all", "GUIDED")), "d.guided,i.guided2", "the kind is searched")
  Same(Ids(V.Select(results, "all", "bid-only")), "b.fail", "the message is searched")
  Same(Ids(V.Select(results, "all", "timeout")), "g.slow", "and the status word")
  Same(Ids(V.Select(results, "all", "seed expected")), "b.fail", "two words must both match")
  Same(Ids(V.Select(results, "all", "seed zzz")), "", "one missing word matches nothing")
  Same(Ids(V.Select(results, "pass", "guided")), "d.guided", "the filter and the search combine")
  Same(Ids(V.Select(results, "fail", "guided")), "", "...and may leave nothing")
  Same(Ids(V.Select(results, "all", "   ")), Ids(results), "a blank search is no search")
  Same(Ids(V.Select(results, "all", "%")), "", "pattern characters are plain text")
  Check(pcall(V.Select, results, "all", "[("), "an unbalanced bracket is only text")
  -- nothing was changed
  for i, r in ipairs(results) do Check(frozen[i][1] == r.id and frozen[i][2] == r.status and frozen[i][3] == r.detail and frozen[i][4] == r.ms, "record " .. i .. " unchanged") end
  Same(V.FirstProblem(results).id, "b.fail", "a failure first"); Same(V.FirstProblem({ results[6], results[7] }).id, "f.err", "then an error")
  Same(V.FirstProblem({ results[7] }).id, "g.slow", "then a timeout"); Same(V.FirstProblem({ results[1], results[5] }), nil, "none when nothing is wrong")

  -- words, durations, rows
  Same(V.Word(results[4]), "Measured", "a guided pass is a measurement"); Same(V.Word(results[9]), "Not run", "a guided step that never started")
  Same(V.Word(Rec("x", "stopped", { class = "guided", label = "guided", ms = 5 })), "Cancelled"); Same(V.Word(results[2]), "Fail")
  Same(V.Duration(0.04), "0.0 ms"); Same(V.Duration(164.5), "164.5 ms"); Same(V.Duration(29922.1), "29.92 s"); Same(V.Duration(125000), "2 min 05 s"); Same(V.Duration(nil), "")
  Same(V.Row(results[1]).message, "OK", "a pass that said nothing"); Same(V.Row(results[2]).message:sub(1, 20), "seed 7100008: bid-on")
  Same(V.Row(results[2]).kind, "Synthetic"); Same(V.Row(results[3]).kind, "Client"); Same(V.Row(results[4]).kind, "Guided")
  Same(V.Row(Rec("p", "pending")).message, "", "a waiting case has no message")

  -- cards: not run is not zero failures; running counts only what finished; stopped says how many did not run
  local idle = V.Cards({ phase = "idle", results = {} })
  for _, key in ipairs({ "total", "pass", "fail", "skipped", "error", "timeout", "duration" }) do Same(idle[key].value, "-", key .. " before a run"); Same(idle[key].lit, false) end
  local run = V.Cards({ phase = "running", results = { Rec("a", "pass"), Rec("b", "running"), Rec("c", "pending") }, seconds = 1.234 })
  Same(run.total.value, "3"); Same(run.pass.value, "1", "only the finished case is counted as passed"); Same(run.fail.value, "0"); Same(run.duration.value, "1.23 s")
  local stopped = V.Cards({ phase = "stopped", results = { Rec("a", "pass"), Rec("b", "stopped"), Rec("c", "stopped") }, seconds = 2 })
  Same(stopped.total.note, "2 not run"); Same(stopped.pass.value, "1")
  local done = V.Cards({ phase = "finished", results = results, seconds = 58.4 })
  Same(done.fail.value, "1"); Same(done.fail.lit, true); Same(done.error.value, "1"); Same(done.timeout.value, "1"); Same(done.skipped.value, "1"); Same(done.duration.value, "58.40 s")
  Same(V.Cards({ phase = "finished", results = { Rec("a", "pass") }, seconds = 1 }).fail.lit, false, "zero failures are not lit")

  -- run state
  Same(V.State({ phase = "idle", results = {}, chosen = 0 }).text, "Nothing chosen")
  local idleState = V.State({ phase = "idle", results = {}, chosen = 34, guidedChosen = true })
  Same(idleState.text, "Not run yet"); Check(idleState.detail:find("34 chosen cases", 1, true) and idleState.detail:find("steps aside", 1, true), idleState.detail)
  Check(V.State({ phase = "idle", results = {}, chosen = 1 }).detail:find("1 chosen case.", 1, true), "one case, singular")
  local running = V.State({ phase = "running", results = results, seconds = 4.25, at = 3, n = 9, current = results[3] })
  Same(running.text, "Running"); Check(running.detail:find("case 3 of 9: c.client", 1, true) and running.detail:find("4.2", 1, true), running.detail)
  local waiting = V.State({ phase = "running", results = results, seconds = 4, at = 4, n = 9, current = results[4] })
  Same(waiting.text, "Waiting for you"); Check(waiting.detail:find("prompt at the top of the screen", 1, true))
  local ok = V.State({ phase = "finished", results = { Rec("a", "pass"), Rec("b", "skipped") }, seconds = 1.5 })
  Same(ok.text, "Finished: all passed"); Same(ok.tone, "pass"); Check(ok.detail:find("Last run: 1.50 s, 2 cases; 1 skipped", 1, true), ok.detail)
  local bad = V.State({ phase = "finished", results = results, seconds = 58.4 })
  Same(bad.text, "Finished with problems"); Same(bad.tone, "fail"); Check(bad.detail:find("1 failed, 1 error, 1 timeout", 1, true), bad.detail)
  Same(V.State({ phase = "finished", results = { Rec("a", "skipped") }, seconds = 0.1 }).text, "Finished: every case was skipped")
  local halted = V.State({ phase = "stopped", results = { Rec("a", "pass"), Rec("b", "stopped") }, seconds = 3, ended = "combat" })
  Same(halted.text, "Stopped"); Check(halted.detail:find("Combat started after 3.00 s; 1 case not run", 1, true), halted.detail)

  -- empty states
  Check(V.Empty({ phase = "idle", results = {}, chosen = 0 }, "all", "", 0):find("No group is chosen", 1, true))
  Check(V.Empty({ phase = "idle", results = {}, chosen = 12 }, "all", "", 0):find("Nothing has run yet", 1, true))
  Same(V.Empty({ phase = "finished", results = results }, "all", "", 4), nil, "rows to show: no sentence")
  Check(V.Empty({ phase = "finished", results = results }, "all", "  zebra ", 0):find('No case matches "zebra"', 1, true))
  Check(V.Empty({ phase = "finished", results = results }, "fail", "zebra", 0):find("among the failed cases", 1, true))
  Check(V.Empty({ phase = "finished", results = { Rec("a", "pass") } }, "fail", "", 0):find("No case failed", 1, true))
  Check(V.Empty({ phase = "finished", results = { Rec("a", "error") } }, "fail", "", 0):find("Errors and timeouts are under their own chips", 1, true), "an error is not hidden behind an empty Failed")
  Check(V.Empty({ phase = "running", results = { Rec("a", "pending") } }, "pass", "", 0):find("No case has passed yet", 1, true))

  -- the details of every outcome: only what the case recorded
  local d = V.Details(results[2])
  Same(d.word, "Fail"); Same(d.kindWord, "Synthetic"); Same(d.headline, "seed 7100008: bid-only records: expected 4, got 5"); Same(d.seeds[1], "7100008", "a seed the evidence names")
  Same(#d.facts, 0, "no facts invented"); Same(#d.notes, 0, "no notes invented"); Same(d.hidden, nil)
  local many = {}
  for i = 1, 8 do many[i] = "check " .. i .. " failed" end
  local dm = V.Details(Rec("m", "fail", { fails = many, failed = 11, facts = {}, notes = { "a note" } }))
  Same(#dm.fails, 8); Same(dm.hidden, 3, "the case keeps its first 8 failure lines and says how many more there were"); Same(#dm.seeds, 0, "no seed, none claimed")
  local plain = V.Details(Rec("pl", "fail", { detail = "just a message" }))
  Same(plain.headline, "just a message"); Same(#plain.seeds, 0); Same(#plain.fails, 0)
  local facts = {}
  for i = 1, 20 do facts[i] = { "k" .. i, "v" .. i } end
  local df = V.Details(Rec("f", "pass", { checks = 4, ms = 12, facts = facts }))
  Same(df.headline, "4 checks passed."); Same(#df.facts, 14); Same(df.moreFacts, 6); Same(df.duration, "12.0 ms")
  Same(V.Details(Rec("p1", "pass", { checks = 1 })).headline, "1 check passed.")
  Same(V.Details(results[5]).headline, "the Workshop is not open"); Same(V.Details(results[5]).word, "Skipped")
  Same(V.Details(results[6]).headline, "The case raised an error before it finished."); Same(V.Details(results[6]).body, "boom")
  Same(V.Details(results[7]).word, "Timeout"); Same(V.Details(results[7]).headline, "abandoned at a yield point")
  Same(V.Details(results[8]).headline, "Stop was pressed before it started")
  Same(V.Details(Rec("g", "running", { class = "guided", label = "guided" })).word, "Your turn")
  Check(V.Details(Rec("g", "running", { class = "guided", label = "guided" })).headline:find("prompt at the top", 1, true))
  Same(V.Details(Rec("q", "pending")).headline, "Waiting to run.")
  Check(V.Details(results[4]).kindNote:find("your help", 1, true), "the evidence type is explained")
  -- text from a case is cleaned like the report's: links and colour codes out
  Same(V.Details(Rec("c", "skipped", { detail = "|cff0070dd|Hitem:1::::::|h[Name]|h|r gone" })).headline, "[link] gone")

  -- the failures excerpt: not a schema 1 report, only what did not pass, full report untouched
  local sum = { results = results, counts = RP and { pass = 3, fail = 1, skipped = 1, error = 1, timeout = 1, stopped = 2 }, cats = { "x" }, seconds = 58.4, slices = 3, worstSlice = 0.004,
    worstFrame = 0.02, overruns = {}, overrunCount = 0, ended = "complete", clock = "GetTime", slice = 0.005 }
  local full = RP.Build(sum)
  local text, n = RP.BuildFailures(sum)
  Same(n, 3, "the failure, the error and the timeout")
  Check(text:find("^TWICHUI%-TESTLAB FAILURES %(an excerpt of a schema 1 report"), "it says what it is: " .. text:sub(1, 90))
  Check(not text:find("^TWICHUI%-TESTLAB REPORT"), "and is not mistaken for a report")
  Check(text:find("b.fail", 1, true) and text:find("f.err", 1, true) and text:find("g.slow", 1, true), "the three cases")
  Check(not text:find("a.pass", 1, true) and not text:find("e.skip", 1, true) and not text:find("h.stopped", 1, true), "and not the others")
  Check(text:find("failed: seed 7100008", 1, true), "the failure lines are in full")
  Same(RP.Build(sum), full, "building the excerpt did not change the full report")
  Check(full:find("^TWICHUI%-TESTLAB REPORT schema 1\n"), "the full report is schema 1")
  local _, none = RP.BuildFailures({ results = { results[1] }, counts = { pass = 1, fail = 0, skipped = 0, error = 0, timeout = 0, stopped = 0 }, cats = {}, seconds = 0, slices = 0, worstSlice = 0,
    worstFrame = 0, overruns = {}, overrunCount = 0, ended = "complete", clock = "GetTime", slice = 0.005 })
  Same(none, 0)
end

---------------------------------------------------------------------------
-- 2. The window: layout, a real run, states
---------------------------------------------------------------------------
do
  local t, TL = Lab()
  local win, W, RN = t.win, TL.Window, TL.Runner
  Check(win and win:IsShown(), "built and opened once by loading")
  Same(win:GetWidth(), 1280); Same(win:GetHeight(), 780, "a 1920 x 1080 screen gets the full window")
  Check(not win.scripts.OnUpdate, "the window has no OnUpdate")
  -- the sidebar is the registry: one check per category, the guided one not ticked, the rest ticked
  local n = 0
  for _, id in ipairs(TL.categoryOrder) do
    n = n + 1
    Check(win.boxes[id] and win.entries[id], id .. " has a check and an entry")
    local optIn = TL.categories[id].guided or TL.categories[id].optin
    Same(win.boxes[id]:GetChecked(), not optIn, id .. " starts " .. (optIn and "unticked" or "ticked"))
    Check(win.entries[id].catName.text == TL.categories[id].label, id .. " shows its own name")
  end
  local nBoxes = 0
  for _ in pairs(win.boxes) do nBoxes = nBoxes + 1 end
  Same(nBoxes, n, "no category invented and none left out")
  -- before a run: not run is not zero failures
  for _, key in ipairs({ "total", "pass", "fail", "skipped", "error", "timeout", "duration" }) do Same(win.cards[key].value.text, "-", key .. " shows a dash before a run") end
  -- the painted summary icons (TwichUI_TestLab/media/summary, cut by tools/make_testlab_art.py): every card wears its own, and each file is real
  local K = t.c.TwichUI.TestLab.Kit
  local expect = { total = "total", pass = "passed", fail = "failed", skipped = "skipped", error = "errors", timeout = "timeouts", duration = "duration" }
  local seen = {}
  for key, file in pairs(expect) do
    local card = win.cards[key]
    Same(K.SUMMARY_ART[key], file, key .. " maps to " .. file)
    Check(card.art, key .. " has painted art"); Same(card.art.texture, [[Interface\AddOns\TwichUI_TestLab\media\summary\]] .. file, key .. " texture path")
    Check(not card.glyph:IsShown(), key .. " no longer draws the shape")
    Check(card.art.w == K.SUMMARY_SIZE and card.art.h == K.SUMMARY_SIZE and K.SUMMARY_SIZE >= 24 and K.SUMMARY_SIZE <= 32, key .. " art is square, 24 to 32 units")
    Check(not seen[file], file .. " is used once"); seen[file] = true
    -- the file: an uncompressed 32-bit TGA, 64 x 64, clear corners and a solid centre (genuine transparency, no baked background)
    local f = assert(io.open(LAB .. "media/summary/" .. file .. ".tga", "rb"), file .. ".tga exists")
    local data = f:read("*a"); f:close()
    local itype, w, h, bpp, desc = data:byte(3), data:byte(13) + data:byte(14) * 256, data:byte(15) + data:byte(16) * 256, data:byte(17), data:byte(18)
    Same(itype, 2, file .. " is an uncompressed true-colour TGA"); Same(w, 64, file .. " width"); Same(h, 64, file .. " height"); Same(bpp, 32, file .. " bits per pixel"); Same(desc, 8, file .. " alpha bits")
    Same(#data, 18 + 64 * 64 * 4, file .. " size")
    local function Alpha(x, y) return data:byte(18 + (y * 64 + x) * 4 + 4) end   -- rows are stored bottom-up; for these checks any row will do
    Same(Alpha(0, 0), 0, file .. ": a corner is clear"); Same(Alpha(63, 63), 0, file .. ": the other corner is clear"); Same(Alpha(0, 63), 0, file .. ": and the third")
    Same(Alpha(32, 32), 255, file .. ": the centre is solid")
    local clear, solid = 0, 0
    for y = 0, 63 do for x = 0, 63 do local a = Alpha(x, y) if a == 0 then clear = clear + 1 elseif a == 255 then solid = solid + 1 end end end
    Check(clear > 64 * 64 * 0.05 and solid > 64 * 64 * 0.35, file .. " has real transparency around opaque artwork (" .. clear .. " clear, " .. solid .. " solid)")
  end
  Same(win.stateText.text, "Not run yet")
  Check(win.list.empty:IsShown() and win.list.empty.text:find("Nothing has run yet", 1, true), win.list.empty.text)
  Check(win.det.empty:IsShown() and win.det.empty.text:find("Run the cases", 1, true), "the details panel explains itself")
  Check(win.edit:GetText():find("No report yet", 1, true), "the report box says there is none")
  Check(win.run:IsEnabled() and not win.stop:IsEnabled() and not win.copy:IsEnabled() and not win.copyFail:IsEnabled(), "only Run is available before a run")
  -- no group chosen: Run is off, the state says why, and a direct call is refused
  Choose(win, {})
  Check(not win.run:IsEnabled(), "Run is off with nothing chosen"); Same(win.stateText.text, "Nothing chosen")
  Check(win.list.empty.text:find("No group is chosen", 1, true), "and the table says so")
  Check(not W.Run() and win.note.text:find("Choose at least one group", 1, true))
  -- a click anywhere on an entry toggles it
  local entry = win.entries.fxp
  entry:GetScript("OnClick")(entry)
  Check(win.boxes.fxp:GetChecked(), "clicking the entry ticks the check"); Check(win.run:IsEnabled(), "and Run is back")
  Same(win.stateText.text, "Not run yet"); Check(win.stateDetail.text:find("3 chosen cases", 1, true), win.stateDetail.text)
  Check(W.Snapshot().chosen == 3)

  -- a real run of the mixed group: pass, fail, error, skipped, timeout
  Choose(win, { "fx" })
  Check(W.Run(), "Run starts")
  Check(RN.Active() and not win.run:IsEnabled() and win.stop:IsEnabled() and not win.copy:IsEnabled() and not win.copyFail:IsEnabled(), "Run off, Stop on, copies off while it runs")
  Check(win.report and win.edit:GetText():find("written when the run ends", 1, true), "no report is built while it runs")
  local fr = RN.frameForTests()
  t.Advance(0.016); fr.scripts.OnUpdate(fr, 0.016)
  Same(win.stateText.text, "Running"); Check(win.cards.total.value.text == "5", "the total is known at once: " .. win.cards.total.value.text)
  Check(tonumber(win.cards.pass.value.text) <= 1, "unfinished cases are not counted as passed")
  Check(win.meter.frac < 1, "the bar is not full while cases are unfinished")
  Check(not W.Run(), "a second Run is refused")
  local frames = Drive(RN, 500, 0.016, t)
  Check(not RN.Active() and win.run:IsEnabled() and not win.stop:IsEnabled() and win.copy:IsEnabled() and win.copyFail:IsEnabled(), "buttons after the run")
  local c = RN.last.counts
  Same(c.pass, 1); Same(c.fail, 1); Same(c.error, 1); Same(c.skipped, 1); Same(c.timeout, 1)
  Same(win.cards.total.value.text, "5"); Same(win.cards.pass.value.text, "1"); Same(win.cards.fail.value.text, "1"); Same(win.cards.error.value.text, "1")
  Same(win.cards.skipped.value.text, "1"); Same(win.cards.timeout.value.text, "1")
  Check(win.cards.duration.value.text:find("s$"), "the duration card: " .. win.cards.duration.value.text)
  Same(win.meter.frac, 1, "the bar is full when every case finished")
  Same(win.stateText.text, "Finished with problems"); Check(win.stateDetail.text:find("1 failed, 1 error, 1 timeout", 1, true), win.stateDetail.text)
  Check(win.edit:GetText():find("^TWICHUI%-TESTLAB REPORT schema 1"), "the full report is in the box when the run ends")
  Check(win.edit:GetText():find("fx.fail", 1, true) and win.edit:GetText():find("first differing record 10", 1, true), "with the cases' evidence")
  -- the chips: counts from the real results, the outcome chips appear because the run has some
  Same(win.chips.all.shownText, "All (5)"); Same(win.chips.fail.shownText, "Failed (1)"); Same(win.chips.pass.shownText, "Passed (1)")
  Same(win.chips.synthetic.shownText, "Synthetic (5)"); Same(win.chips.guided.shownText, "Guided (0)"); Same(win.chips.client.shownText, "Client (0)")
  Check(win.chips.error:IsShown() and win.chips.error.shownText == "Errors (1)", "an error is never hidden")
  Check(win.chips.timeout:IsShown() and win.chips.skipped:IsShown(), "nor a timeout or a skipped case")
  Check(not win.chips.stopped:IsShown(), "stopped has none, so no chip")
  Check(win.chips.all.on and not win.chips.fail.on, "All is the chosen filter")
  -- the first failure is chosen at once and its details show
  Same(W.Snapshot().selected, "fx.fail"); Check(not W.Snapshot().byPlayer, "chosen for the player, not by them")
  Same(win.det.id.text, "fx.fail"); Same(win.det.outcome.text, "FAIL"); Check(win.det.headline.text:find("seed 7100008: bid-only records", 1, true), win.det.headline.text)
  Check(win.det.box:IsShown() and win.det.scroll:IsShown() and not win.det.empty:IsShown())
  local used = 0
  for _, fs in ipairs(win.det.bodies) do if fs:IsShown() and fs.text:find("Seed named in the evidence: 7100008", 1, true) then used = used + 1 end end
  Same(used, 1, "the seed the case named is listed, quoted from its own text")
  -- table rows: one per case, the row for the failure is lit as chosen
  Same(W.Snapshot().rows, 5)
  local row
  for _, r in ipairs(win.list.rows) do if r:IsShown() and r.rec and r.rec.id == "fx.fail" then row = r end end
  Check(row and row.selected, "the failure's row is selected"); Same(row.id.text, "fx.fail"); Same(row.chip.text.text, "Synthetic"); Same(row.word.text, "Fail")
  -- the filters never touch the cases, the choice of groups, the report or the selection
  local reportBefore, chosenBefore = win.edit:GetText(), W.Snapshot().chosen
  Check(W.SetFilter("fail")); Same(W.Snapshot().rows, 1); Same(W.Snapshot().selected, "fx.fail", "the selection survives a filter")
  Same(win.edit:GetText(), reportBefore, "so does the report"); Same(W.Snapshot().chosen, chosenBefore, "and the choice of groups"); Check(win.chips.fail.on and not win.chips.all.on)
  Check(not RN.Active(), "a filter starts nothing")
  Check(W.SetFilter("error")); Same(W.Snapshot().rows, 1); Same(win.list.rows[1].rec.id, "fx.error")
  Check(W.SetFilter("pass")); Same(W.Snapshot().rows, 1)
  Check(W.SetFilter("guided")); Same(W.Snapshot().rows, 0); Check(win.list.empty:IsShown() and win.list.empty.text:find("No case in this run is a guided case", 1, true), win.list.empty.text)
  Check(not W.SetFilter("nonsense"), "an unknown filter is refused")
  Check(W.SetFilter("all")); Same(W.Snapshot().rows, 5)
  -- search, combined with a filter
  W.SetQuery("slow"); Same(W.Snapshot().rows, 1); Same(win.list.rows[1].rec.id, "fx.slow")
  W.SetFilter("fail"); Same(W.Snapshot().rows, 0); Check(win.list.empty.text:find('No case matches "slow" among the failed cases', 1, true), win.list.empty.text)
  W.SetFilter("all"); W.SetQuery("boom"); Same(W.Snapshot().rows, 1, "the message of an error is searched"); Same(win.list.rows[1].rec.id, "fx.error")
  W.SetQuery(""); Same(W.Snapshot().rows, 5, "clearing the search brings every row back")
  Same(win.search:GetText(), "")
  -- typing in the field runs the same search
  win.search:SetText("skip"); win.search:Fire("OnTextChanged", true)
  Same(W.Snapshot().query, "skip"); Same(W.Snapshot().rows, 1)
  W.SetQuery("")
  -- the player's own choice: a click on a row selects it and is kept
  local target
  for _, r in ipairs(win.list.rows) do if r:IsShown() and r.rec and r.rec.id == "fx.error" then target = r end end
  target:GetScript("OnClick")(target)
  Same(W.Snapshot().selected, "fx.error"); Check(W.Snapshot().byPlayer); Same(win.det.id.text, "fx.error"); Same(win.det.outcome.text, "ERROR")
  Check(win.det.headline.text:find("raised an error", 1, true))
  Check(target.selected, "the clicked row is selected, and the failure's row is not")
  W.Select("fx.skip"); Same(win.det.outcome.text, "SKIPPED"); Check(win.det.headline.text:find("Workshop is not open", 1, true))
  W.Select("fx.slow"); Same(win.det.outcome.text, "TIMEOUT")
  W.Select("fx.pass"); Same(win.det.outcome.text, "PASS"); Check(win.det.headline.text:find("1 check passed", 1, true))
  local facts = false
  for _, fs in ipairs(win.det.bodies) do if fs:IsShown() and fs.text:find("seed = 7100008", 1, true) then facts = true end end
  Check(facts, "a passing case shows the facts it recorded")
  Check(not W.Select("no.such.case"), "an unknown id selects nothing")

  -- copying
  Check(W.CopyFailures(), "Copy failures works when the run had some")
  Check(win.edit:GetText():find("^TWICHUI%-TESTLAB FAILURES"), "the box holds the excerpt"); Check(win.edit.focus, "focused, for Ctrl+C")
  Check(win.edit:GetText():find("fx.fail", 1, true) and win.edit:GetText():find("fx.error", 1, true) and not win.edit:GetText():find("fx.pass ", 1, true), "failures only")
  Check(win.note.text:find("Ctrl+C", 1, true) and not win.note.text:find("copied", 1, true), "it never claims the text was copied: " .. win.note.text)
  Same(win.reportTitle.text, "Failures (3)")
  local excerpt = win.edit:GetText()
  win.edit:SetText("typed over"); win.edit.scripts.OnTextChanged(win.edit, true)
  Same(win.edit:GetText(), excerpt, "typing puts the shown text back")
  Check(W.Copy()); Check(win.edit:GetText():find("^TWICHUI%-TESTLAB REPORT schema 1")); Same(win.reportTitle.text, "Report")
  Check(win.note.text:find("Report selected", 1, true) and win.note.text:find("Ctrl+C", 1, true), win.note.text)

  -- a new run clears the old selection and results; the state follows
  Check(W.Run()); Same(W.Snapshot().selected, nil); Same(win.cards.pass.value.text, "0", "a fresh run counts from zero")
  Check(win.edit:GetText():find("written when the run ends", 1, true))
  Drive(RN, 500, 0.016, t)
  Same(W.Snapshot().selected, "fx.fail", "the failure is chosen again")
  -- Stop mid-run: stopped cases are said, not hidden
  Check(W.Run())
  local fr2 = RN.frameForTests()
  t.Advance(0.016); fr2.scripts.OnUpdate(fr2, 0.016)
  win.stop:GetScript("OnClick")(win.stop)
  Check(not RN.Active()); Same(win.stateText.text, "Stopped"); Check(win.stateDetail.text:find("Stop was pressed", 1, true) and win.stateDetail.text:find("not run", 1, true), win.stateDetail.text)
  Check(win.chips.stopped:IsShown(), "stopped cases have a chip"); Check(win.cards.total.label.text:find("not run", 1, true), "and the total card says how many: " .. win.cards.total.label.text)
  Check(win.note.text:find("could not have been interrupted", 1, true))
  Check(win.run:IsEnabled() and not win.stop:IsEnabled())
  -- a frame that finishes no case redraws nothing but the clock: the table, the chips and the details are left alone
  Choose(win, { "fxy" })
  local setData, redraws = win.list.SetData, 0
  win.list.SetData = function(self, ...) redraws = redraws + 1; return setData(self, ...) end
  Check(W.Run())
  local fw = RN.frameForTests()
  for _ = 1, 2 do t.Advance(0.016); fw.scripts.OnUpdate(fw, 0.016) end   -- the case starts and begins to wait
  redraws = 0
  local before = win.cards.duration.value.text
  for _ = 1, 8 do t.Advance(0.016); fw.scripts.OnUpdate(fw, 0.016) end
  Same(redraws, 0, "eight frames in which no case finished redrew the table no time")
  Check(RN.Active() and win.cards.duration.value.text ~= before, "but the duration card moved: " .. before .. " -> " .. win.cards.duration.value.text)
  Drive(RN, 500, 0.016, t)
  Check(redraws >= 1, "and finishing the case redrew it")
  win.list.SetData = setData
  Choose(win, { "fx" })
  -- the player's own choice during a run is kept at the end
  Check(W.Run())
  local fr3 = RN.frameForTests()
  t.Advance(0.016); fr3.scripts.OnUpdate(fr3, 0.016)
  Check(W.Select("fx.pass"), "choosing a row while it runs")
  Drive(RN, 500, 0.016, t)
  Same(W.Snapshot().selected, "fx.pass", "a result the player chose is not replaced by the first failure"); Check(W.Snapshot().byPlayer)
  -- an all-pass run: nothing to choose, every card says so
  Choose(win, { "fxp" })
  Check(W.Run()); Drive(RN, 500, 0.016, t)
  Same(win.stateText.text, "Finished: all passed"); Same(W.Snapshot().selected, nil, "nothing failed, so nothing is chosen for the player")
  Same(win.cards.fail.value.text, "0"); Check(not win.copyFail:IsEnabled(), "Copy failures is off when nothing failed")
  Check(not W.CopyFailures() and win.note.text:find("Nothing to copy", 1, true), win.note.text)
  Check(not win.chips.error:IsShown() and not win.chips.timeout:IsShown(), "no error or timeout chip when there is none")
  Check(win.det.empty:IsShown() and win.det.empty.text:find("Choose a row", 1, true), "the details panel invites a choice")
  Check(W.SetFilter("fail")); Check(win.list.empty.text:find("No case failed in this run", 1, true), win.list.empty.text)
  W.SetFilter("all")
  -- closing and Esc
  local esc = false
  for _, name in ipairs(t.c.UISpecialFrames) do if name == "TwichUITestLabWindow" then esc = true end end
  Check(esc, "Esc closes it through UISpecialFrames")
  Same(t.timers(), 0, "the Lab made no timer")
  Check(DeepSame(t.db, { modules = {}, workshop = { v = 1 } }), "TwichUIDB is unchanged")
  Check(not t.c.TwichUIDiagnosticsDB and not t.c.TwichUIWorkshopDB, "no saved root was created")
  local G = TL.Guided.Snapshot()
  Check(not G.active and not G.bound and not G.proxyShown and not G.promptShown, "no binding, proxy or prompt is left")
end

---------------------------------------------------------------------------
-- 3. Guided: opt-in, and the window steps aside
---------------------------------------------------------------------------
do
  local t, TL = Lab()
  local win, W, RN = t.win, TL.Window, TL.Runner
  win.EnableMouse = function(s, v) s.mouseOn = v end
  Check(win.boxes.fxg:GetChecked() == false, "the guided group is not ticked for the player")
  Check(win.entries.fxg.catName.text == "Guided fixture")
  -- Run with the defaults: no guided case is in the run
  Choose(win, { "fxp" })
  Tick(win, "client"); Tick(win, "client")   -- ticking and clearing changes nothing about guided
  local list = TL.Select({ fxp = true, client = false })
  for _, cse in ipairs(list) do Check(cse.class ~= "guided") end
  Check(W.Run(), "a default run starts"); Check(not W.Snapshot().peek, "and does not step aside")
  Drive(RN, 500, 0.016, t)
  for _, r in ipairs(RN.last.results) do Check(r.class ~= "guided", r.id .. " was not a guided case") end
  -- an explicit tick runs it, and the window steps aside until the run ends
  Choose(win, { "fxg" })
  Check(W.Run())
  Check(W.Snapshot().peek and not win.content:IsShown() and not win.shell:IsShown() and win.mouseOn == false, "the window's content is hidden and it takes no pointer")
  Check(win:IsShown(), "it is not closed, so the run goes on")
  Check(win.note.text:find("steps aside", 1, true), win.note.text)
  Drive(RN, 500, 0.016, t)
  Check(not W.Snapshot().peek and win.content:IsShown() and win.shell:IsShown() and win.mouseOn == true, "and comes back when the run ends")
  Same(win.stateText.text, "Finished: all passed")
  -- Stop while stepped aside restores it too
  Check(W.Run()); Check(W.Snapshot().peek)
  W.Stop()
  Check(not W.Snapshot().peek and win.content:IsShown(), "Stop brings the window back")
  -- closing it during a guided run ends the run, releases the prompt and leaves a usable window
  Check(W.Run()); win:Hide()
  Check(not RN.Active() and RN.last.ended == "closed"); Check(not W.Snapshot().peek, "closed: not left stepped aside")
  local G = TL.Guided.Snapshot()
  Check(not G.active and not G.bound and not G.promptShown, "nothing of the guided mechanism is left")
  win:Show(); Check(win.content:IsShown())
end

---------------------------------------------------------------------------
-- 4. Long result lists: pooled rows, scrolling, no growth
---------------------------------------------------------------------------
do
  local t, TL = Lab()
  local win, W = t.win, TL.Window
  local results = {}
  for i = 1, 300 do
    local status = i % 50 == 0 and "fail" or (i % 77 == 0 and "error" or "pass")
    results[i] = Rec(("case.number%03d"):format(i), status, { ms = i * 1.5, detail = status ~= "pass" and ("problem " .. i) or nil, fails = status == "fail" and { "problem " .. i } or nil, failed = status == "fail" and 1 or nil })
  end
  local sum = { results = results, counts = TL.Runner.Count(results), cats = { "x" }, seconds = 12.5, slices = 40, worstSlice = 0.006, worstFrame = 0.03, overruns = {}, overrunCount = 0,
    ended = "complete", clock = "GetTime", slice = 0.005 }
  local made0 = MI_MADE
  W.OnDone(sum)
  Same(W.Snapshot().rows, 300); Same(W.Snapshot().selected, "case.number050", "the first failure of a long run is chosen")
  Check(#win.list.rows <= 9, "only the rows that can show exist: " .. #win.list.rows)
  local shownRows = win.list:RowCount()
  Check(shownRows <= 9 and shownRows >= 5, "and they are the ones in view: " .. shownRows)
  Same(win.list.rows[1].rec.id, "case.number001")
  -- scrolling reuses the same rows with other data
  local rowsBefore, madeBefore = #win.list.rows, MI_MADE
  win.list.scroll:SetVerticalScroll(150 * 30)
  win.list.scroll:Fire("OnVerticalScroll", 150 * 30)
  Same(win.list.rows[1].rec.id, "case.number151", "the first row now holds another case")
  Same(#win.list.rows, rowsBefore, "no row was added by scrolling"); Same(MI_MADE, madeBefore, "no frame, texture or text was made by scrolling")
  win.list.scroll:SetVerticalScroll(0); win.list.scroll:Fire("OnVerticalScroll", 0)
  -- filtering a long list
  W.SetFilter("fail"); Same(W.Snapshot().rows, 6)
  W.SetFilter("error"); Same(W.Snapshot().rows, 3)
  W.SetFilter("all"); W.SetQuery("number29"); Same(W.Snapshot().rows, 10, "number290..299 match")
  W.SetQuery("problem 100"); Same(W.Snapshot().rows, 1)
  W.SetQuery(""); W.SetFilter("all")
  -- the chosen row that is off screen is reached by the scroll that follows a choice
  W.Select("case.number250")
  Check(win.list.scroll:GetVerticalScroll() >= 0)
  -- the whole run of changes made nothing new once settled
  local settled = MI_MADE
  for i = 1, 30 do W.SetFilter(i % 2 == 0 and "all" or "fail"); W.SetQuery(i % 3 == 0 and "5" or "") end
  W.SetFilter("all"); W.SetQuery("")
  Same(MI_MADE, settled, "filtering and searching make nothing")
  Check(MI_MADE - made0 < 900, "building the whole window and a 300-case run stays small: " .. (MI_MADE - made0))
  -- repeated open and close: no frame or texture growth
  local before = MI_MADE
  for _ = 1, 10 do win:Hide(); win:Show() end
  for _ = 1, 10 do t.c.SlashCmdList.TWICHUILAB(); t.c.SlashCmdList.TWICHUILAB() end
  Same(MI_MADE, before, "opening and closing ten times makes nothing")
  Check(not win.scripts.OnUpdate)
end

---------------------------------------------------------------------------
-- 5. A smaller screen
---------------------------------------------------------------------------
do
  local t, TL = Lab({ screen = { 1366, 768 } })
  local win = t.win
  Check(win:GetWidth() <= 1366 - 48 and win:GetHeight() <= 768 - 48, ("a 1366 x 768 screen gets a window that fits it: %d x %d"):format(win:GetWidth(), win:GetHeight()))
  Check(win:GetWidth() >= 940 and win:GetHeight() >= 600, "and not one too small to use")
  local t2 = Lab({ screen = { 1024, 768 } })
  Check(t2.win:GetWidth() <= 1024 - 48 or t2.win:GetWidth() == 940, "a 1024 wide screen: " .. t2.win:GetWidth())
  Check(t2.win.report:GetHeight() > 0)
  -- a narrow window drops what does not fit rather than cutting it: no group descriptions (they are tooltips), no Type or Message column
  local nw = t2.win
  Check(nw:GetWidth() < 1100, "the 1024 screen builds a narrow window")
  Check(nw.entries.core.catName.text:find("(%d+)", 1, false) and nw.entries.core.catName.text:find("%(%d+%)"), "a narrow sidebar writes the count after the name: " .. nw.entries.core.catName.text)
  -- the mock has no layout, so the table is given the width the narrow window would give it, and the game's size event is fired
  nw.table.w = 446; nw.table:Fire("OnSizeChanged")
  Check(not nw.head.msg:IsShown(), "a narrow table (446 wide) has no Message column"); Check(nw.head.type:IsShown(), "but keeps Type, Status, Case and Duration")
  nw.table.w = 420; nw.table:Fire("OnSizeChanged")
  Check(not nw.head.type:IsShown() and nw.head.dur:IsShown(), "a table narrower than that drops Type too and keeps the duration")
  nw.table.w = 720; nw.table:Fire("OnSizeChanged")
  Check(nw.head.msg:IsShown() and nw.head.type:IsShown(), "and a wide one shows every column")

  local t3 = Lab({ screen = { 1920, 640 } })
  Check(t3.win.report:GetHeight() <= 130, "a short window gets a shorter report box: " .. t3.win.report:GetHeight())
end

print("PASSED test_testlab_window")
