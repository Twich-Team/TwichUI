-- The development-only saved-data load test (A4 load gate; docs/testlab.md "Saved-data load test"): TwichUI_LoadTest (one synthetic saved
-- variable, load on demand), TwichUI_LoadTestClock (logout/login times) and the Lab cases that drive them (TwichUI_TestLab/cases/Load.lua).
-- Offline, with stand-ins for LoadAddOn, the frames and the clocks: this proves the bookkeeping and the safety rules, NOT any load time (only
-- the real client can measure that).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local LT_DIR, CLOCK_DIR, LAB = ROOT .. "../TwichUI_LoadTest/", ROOT .. "../TwichUI_LoadTestClock/", ROOT .. "../TwichUI_TestLab/"
local WORKSHOP = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Scan.lua", "Market.lua" }

local function Read(path) local f = assert(io.open(path)) local s = f:read("*a") f:close() return s end

---------------------------------------------------------------------------
-- 1. Static: the companions touch only their own saved variables, and are what their .toc files load
---------------------------------------------------------------------------
do
  for _, spec in ipairs({ { LT_DIR, "TwichUI_LoadTest.toc", "LoadTest.lua", "TwichUILoadTestDB" }, { CLOCK_DIR, "TwichUI_LoadTestClock.toc", "Clock.lua", "TwichUILoadClockDB" } }) do
    local toc = Read(spec[1] .. spec[2])
    Check(toc:find("\n" .. spec[3] .. "\n", 1, true) or toc:find("\n" .. spec[3] .. "$"), spec[2] .. " loads " .. spec[3])
    Check(toc:find("## SavedVariables: " .. spec[4], 1, true), spec[2] .. " declares only its own saved variable")
    local code = Read(spec[1] .. spec[3]):gsub("%-%-[^\n]*", "")
    for _, root in ipairs({ "TwichUIDB", "TwichUIWorkshopDB", "TwichUIDiagnosticsDB" }) do
      Check(not code:find(root .. "[^%w_]"), spec[3] .. " names the real saved root " .. root)
    end
    for _, name in ipairs({ "loadstring", "setfenv", "hooksecurefunc", "SendAddonMessage", "SendChatMessage", "RegisterGameMenuEscHandler", "_G[" }) do
      Check(not code:find(name, 1, true), spec[3] .. " uses " .. name)
    end
  end
  Check(Read(LT_DIR .. "TwichUI_LoadTest.toc"):find("## LoadOnDemand: 1", 1, true), "the big file loads only on request")
end

---------------------------------------------------------------------------
-- A client with stand-in frames, clocks and LoadAddOn
---------------------------------------------------------------------------
local function Client(saved)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  c.GetRealmName = function() return "Realm" end
  local made, ms, up = {}, 0, 5000
  c.CreateFrame = function(kind) local fr = MIFake(kind) made[#made + 1] = fr return fr end
  c.debugprofilestop = function() ms = ms + 0.25 return ms end
  c.GetTime = function() return up end
  c.TwichUIWorkshopDB = saved.workshop
  c.TwichUILoadClockDB = nil
  local loaded = {}
  local function Run(dir, file)
    local chunk = assert(loadfile(dir .. file)); setfenv(chunk, c); chunk(file, {})
  end
  c.C_AddOns = {
    DoesAddOnExist = function(name) return name == "TwichUI_LoadTest" end,
    IsAddOnLoaded = function(name) return loaded[name] == true end,
    LoadAddOn = function(name)
      if name ~= "TwichUI_LoadTest" then return false, "MISSING" end
      if loaded[name] then return true end
      Run(LT_DIR, "LoadTest.lua")                   -- the file first,
      c.TwichUILoadTestDB = saved.loadtest          -- then the saved variable (the order other versions of the game use),
      ms = ms + 40                                  -- which takes a while,
      for _, fr in ipairs(made) do if fr.events.ADDON_LOADED and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, "ADDON_LOADED", name) end end
      loaded[name] = true
      return true
    end,
  }
  local t = { c = c, made = made, saved = saved }
  function t.Fire(event, arg) for _, fr in ipairs(made) do if fr.events[event] and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, event, arg) end end end
  function t.Advance(sec) up = up + sec end
  function t.Run(dir, file) Run(dir, file) end
  function t.Workshop()
    for _, f in ipairs(WORKSHOP) do local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {}) end
    return c.TwichUI.Workshop
  end
  return t
end

local function Ser(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

---------------------------------------------------------------------------
-- 2. The load record, generation (atomic), clearing; the real roots untouched
---------------------------------------------------------------------------
do
  local workshop = { v = 2, markets = { ["Realm|Alliance"] = { f = 3, at = 1, items = { [1] = "5,1,1,1,0" } } } }
  local before = Ser(workshop)
  local t = Client({ workshop = workshop, loadtest = { v = 1, meta = { items = 7, bytes = 99 }, market = {} } })
  local ok = t.c.C_AddOns.LoadAddOn("TwichUI_LoadTest")
  Check(ok)
  local LT = t.c.TwichUI.LoadTest
  Same(LT.dbAtFile, false, "the stand-in client reads the saved variable after the file"); Same(LT.dbAtLoaded, true)
  Check(LT.loadedAt - LT.fileAt >= 40, "the time between the file and ADDON_LOADED is recorded")
  Same(LT.Meta().items, 7)
  -- a generation that is stopped half-way leaves the previous data
  local job = assert(LT.Begin({ items = 500, preset = "test", days = 120, make = function(i) return ("%d,1,1,1,0"):format(i), nil, ("|%d:%d,%d,,1,1"):format(20000, 20000, i), nil end }))
  job:Step(1)
  Check(job.done > 0 and job.done < 500, "a step stops after its time")
  Same(LT.Meta().items, 7, "nothing is replaced before the last step")
  while not job:Step(1) do end
  local meta = LT.Meta()
  Same(meta.items, 500); Same(meta.preset, "test"); Same(meta.h2items, 500); Check(meta.bytes > 500 * 20, "a size estimate")
  Same(t.c.TwichUILoadTestDB.market.h2[1001], "|20000:20000,1,,1,1")
  Same(select(2, LT.Begin({ items = 0, make = function() end })), "items"); Same(select(2, LT.Begin({ items = 5 })), "nospec")
  -- logout stamps the time; clearing empties it
  t.Fire("PLAYER_LOGOUT")
  Same(t.c.TwichUILoadTestDB.meta.logoutAt, 5000)
  LT.Clear()
  Same(LT.Meta().items, 0)
  Same(Ser(t.c.TwichUIWorkshopDB), before, "the real Workshop database was never touched")
end

---------------------------------------------------------------------------
-- 3. The clock: logout in one session, entering the world in the next
---------------------------------------------------------------------------
do
  local t = Client({})
  t.Run(CLOCK_DIR, "Clock.lua")
  t.Fire("ADDON_LOADED", "TwichUI_LoadTestClock")
  Same(type(t.c.TwichUILoadClockDB), "table")
  t.Fire("PLAYER_ENTERING_WORLD")
  Same(#t.c.TwichUI.LoadClock.List(), 0, "nothing to measure in the first session")
  t.Fire("PLAYER_LOGOUT")
  local saved = t.c.TwichUILoadClockDB
  Check(saved.logout and saved.logout.at == 5000)
  -- the next session: the same client clock went on 12.5 seconds
  local t2 = Client({})
  t2.Advance(12.5)
  t2.Run(CLOCK_DIR, "Clock.lua")
  t2.c.TwichUILoadClockDB = saved
  t2.Fire("ADDON_LOADED", "TwichUI_LoadTestClock")
  t2.Fire("PLAYER_ENTERING_WORLD")
  local list = t2.c.TwichUI.LoadClock.List()
  Same(#list, 1); Same(list[1].toWorld, 12.5); Same(list[1].loadTestLoaded, false)
  Same(t2.c.TwichUILoadClockDB.logout, nil, "a logout record is used once")
end

---------------------------------------------------------------------------
-- 4. The Lab cases (cases/Load.lua) on that stand-in client
---------------------------------------------------------------------------
do
  local saved = { loadtest = nil }
  local t = Client(saved)
  local W = t.Workshop()
  for _, f in ipairs({ "Lab.lua", "Fixtures.lua", "Reference.lua", "Bench.lua", "Workloads.lua", "cases/Load.lua" }) do
    local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, t.c); chunk("TwichUI_TestLab", {})
  end
  local TL = t.c.TwichUI.TestLab
  Same(#TL.rejected, 0, "every load-test case is accepted")
  Same(TL.categories.loadtest.optin, true, "the group is opt-in")
  for _, c in ipairs(TL.Select(nil)) do Check(c.cat ~= "loadtest", "an unqualified run never includes the load test") end
  -- a devdata case outside an opt-in group is refused
  TL.Category{ id = "plain", label = "plain" }
  Same(select(2, TL.Case{ id = "x.devdata", cat = "plain", class = "devdata", run = function() end }), "a devdata case belongs to an opt-in category")
  local function Run(id)
    local res = { facts = {}, notes = {}, fails = {} }
    local api = {
      W = W, Check = function(_, ok, what) if not ok then res.fails[#res.fails + 1] = what end end, Same = function(_, a, b, what) if a ~= b then res.fails[#res.fails + 1] = what end end,
      Skip = function(_, why) res.skip = why end, Fact = function(_, k, v) res.facts[k] = v end, Note = function(_, s) res.notes[#res.notes + 1] = s end,
      Progress = function() end, Yield = function() end,
    }
    TL.cases[id].run(api)
    return res
  end
  -- measure before anything was generated: the companion loads, holds nothing, and says so
  local r = Run("loadtest.measure")
  Same(r.skip, nil); Check(#r.fails == 1, "an empty companion is a failed measurement, not a number")
  Same(Run("loadtest.measure").skip:sub(1, 30), "TwichUI_LoadTest is already lo", "a second measurement in the same session is refused")
  -- generate the small preset, then "reload" (a fresh client with the written saved variable) and measure
  local g = Run("loadtest.generate.small")
  Same(#g.fails, 0, table.concat(g.fails, "; ")); Same(g.facts["loadtest.items"], 4000)
  local file = t.c.TwichUILoadTestDB
  Check(file.meta.bytes > 4000 * 100, "a few hundred bytes per item")
  local h2 = 0
  for _, s in pairs(file.market.h2) do Check(W.History2.DecodeH2(s), "every generated history reads with the production reader") h2 = h2 + 1 end
  Same(h2, 4000)
  local t2 = Client({ loadtest = file })
  t2.Workshop()
  for _, f in ipairs({ "Lab.lua", "Fixtures.lua", "Reference.lua", "Bench.lua", "Workloads.lua", "cases/Load.lua" }) do
    local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, t2.c); chunk("TwichUI_TestLab", {})
  end
  local m = (function()
    local res = { facts = {}, notes = {}, fails = {} }
    t2.c.TwichUI.TestLab.cases["loadtest.measure"].run({ Check = function(_, ok, w) if not ok then res.fails[#res.fails + 1] = w end end, Skip = function(_, w) res.skip = w end,
      Fact = function(_, k, v) res.facts[k] = v end, Note = function(_, s) res.notes[#res.notes + 1] = s end })
    return res
  end)()
  Same(m.skip, nil); Same(#m.fails, 0); Same(m.facts["loadtest.items"], 4000); Same(m.facts["loadtest.saved_at_file"], "false")
  Check(tonumber(m.facts["loadtest.file_to_loaded_ms"]) >= 40, "the deserialization window is reported")
  Check(m.notes[1]:find("ran the addon's file first", 1, true), "and explained")
  -- clear
  local cl = Run("loadtest.clear")
  Same(#cl.fails, 0); Same(t.c.TwichUILoadTestDB.meta.items, 0)
  Same(t.c.TwichUIWorkshopDB, nil, "no Workshop database was created")
end

print("PASSED test_loadtest")
