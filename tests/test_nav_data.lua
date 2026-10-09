dofile(TESTS .. "harness.lua")
-- Navigation's learned flight data (nav/Data.lua, TwichUINavigationDB): kept across a reload, unreadable
-- entries dropped one at a time, kept within its limits (oldest first), copies taken of what is stored,
-- times out of range refused, and a copy saved by a newer TwichUI left untouched and handed back at logout.
local function boot(saved, before)
  local c = MakeClient("Rich", {"!!!TwichUI"})
  c.TwichUINavigationDB = saved
  local chunk = assert(loadfile(ROOT .. "nav/Data.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  if before then before(c) end
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  return c, c.TwichUI.NavData
end

-- 1) Fresh: an empty, versioned table.
local c, ND = boot(nil)
assert(c.TwichUINavigationDB.version == 1 and next(c.TwichUINavigationDB.routes) == nil and next(c.TwichUINavigationDB.times) == nil)
assert(ND.Snapshot().outcome == "fresh")

-- 2) Learning, and what is refused.
local hops = { 11, 15, 12 }
assert(ND.SetRoute(11, 12, hops))
hops[2] = 99
assert(ND.Route(11, 12)[2] == 15, "the stored route is a copy")
assert(not ND.SetRoute(11, 12, { 11, 12, 13 }), "a route must end where it says")
assert(not ND.SetRoute(11, 11, { 11, 11 }), "not to itself")
assert(not ND.SetRoute(11, 12, { 11, "x", 12 }) and not ND.SetRoute(1.5, 12, { 1.5, 12 }), "IDs only")
local long = {}
for i = 1, ND.MAX_HOPS + 1 do long[i] = i end
assert(not ND.SetRoute(1, ND.MAX_HOPS + 1, long), "not too many stops")
assert(ND.AddTime({ 11, 15, 12 }, 120) and ND.Time({ 11, 15, 12 }) == 120)
assert(ND.AddTime({ 11, 15, 12 }, 180))
local s, n = ND.Time({ 11, 15, 12 })
assert(n == 2 and s > 120 and s < 180, "a second flight moves the time toward it: " .. s)
assert(not ND.AddTime({ 11, 12 }, 2) and not ND.AddTime({ 11, 12 }, 4000) and not ND.AddTime({ 11, 12 }, 0 / 0), "times out of range refused")
assert(ND.Time({ 11, 12 }) == nil, "a different set of stops is a different flight")
local rev = ND.Revision()
ND.SetRoute(11, 12, { 11, 15, 12 })
assert(ND.Revision() == rev, "seeing the same route again changes nothing cached")

-- 3) Kept across a reload, exactly.
local saved = c.TwichUINavigationDB
local c2, ND2 = boot(saved)
assert(ND2.Route(11, 12)[3] == 12 and select(2, ND2.Time({ 11, 15, 12 })) == 2 and ND2.Snapshot().outcome == "current")

-- 4) Damaged entries go one at a time; the rest stay.
local damaged = {
  version = 1,
  routes = {
    ["11:12"] = { hops = { 11, 12 }, seen = 5 },
    ["11:13"] = { hops = { 11, 12 }, seen = 5 },     -- doesn't end where its key says
    ["bad"] = { hops = { 1, 2 } },
    ["14:15"] = "text",
    ["16:17"] = { hops = { 16, 17 }, seen = "x" },   -- kept, its date reset
  },
  times = {
    ["11-12"] = { s = 100, n = 2, seen = 1 },
    ["11-13"] = { s = -5 },
    ["x-y"] = { s = 100 },
    ["11-14"] = { s = 90, n = "many" },               -- kept, its count reset
  },
}
local c3, ND3 = boot(damaged)
assert(ND3.Route(11, 12) and ND3.Route(16, 17) and ND3.Route(11, 13) == nil, "good routes kept, bad dropped")
assert(c3.TwichUINavigationDB.routes["16:17"].seen == 0)
assert(ND3.Time({ 11, 12 }) == 100 and select(2, ND3.Time({ 11, 14 })) == 1 and ND3.Time({ 11, 13 }) == nil)
assert(c3.TwichUI.Persist.Report().repairs["nav-entry-dropped"] == 5, "each dropped entry counted (three routes, two times)")
assert(c3.TwichUI.Persist.Lost() == 0, "learned data isn't something the player stored: no notice")

-- 5) Wrong kinds of root and groups.
local c4, ND4 = boot("text")
assert(type(c4.TwichUINavigationDB) == "table" and ND4.Route(1, 2) == nil)
local c5 = boot({ version = 1, routes = 5, times = "x" })
assert(type(c5.TwichUINavigationDB.routes) == "table" and type(c5.TwichUINavigationDB.times) == "table")

-- 6) Limits: the oldest go first.
local many = { version = 1, routes = {}, times = {} }
for i = 1, 30 do many.routes[i .. ":" .. (i + 1000)] = { hops = { i, i + 1000 }, seen = i } end
local c6, ND6 = boot(many, function(cl) cl.TwichUI.NavData.MAX_ROUTES = 10 end)
local kept = 0
for _ in pairs(c6.TwichUINavigationDB.routes) do kept = kept + 1 end
assert(kept == 10 and ND6.Route(30, 1030) and ND6.Route(20, 1020) == nil and ND6.Route(21, 1021), "the ten newest are kept")
assert(c6.TwichUI.Persist.Report().repairs["nav-trimmed"] == 20)
ND6.SetRoute(500, 501, { 500, 501 })
kept = 0
for _ in pairs(c6.TwichUINavigationDB.routes) do kept = kept + 1 end
assert(kept == 10 and ND6.Route(500, 501), "learning more stays within the limit")

-- 7) Saved by a newer TwichUI: not read, not changed, handed back at logout.
local future = { version = 7, routes = { ["1:2"] = { hops = { 1, 2 }, seen = 1 } }, times = {}, extra = "kept" }
local c7, ND7 = boot(future)
assert(ND7.Route(1, 2) == nil and ND7.Snapshot().outcome == "future", "this session starts empty")
ND7.SetRoute(3, 4, { 3, 4 })
c7.FireEvent("PLAYER_LOGOUT")
assert(c7.TwichUINavigationDB == future and future.version == 7 and future.extra == "kept" and future.routes["3:4"] == nil,
  "the newer copy is handed back unchanged")

-- 8) Each character's flight points: kept under its own name, cleaned, within limits.
do
  local cc, NDc = boot(nil)
  assert(next(NDc.Known()) == nil, "nothing known at first")
  assert(NDc.AddKnown({ 11, 12, 12, "x", 0 }) == 2 and NDc.Known()[11] and NDc.Known()[12] and NDc.Known()["x"] == nil, "IDs only, once each")
  assert(NDc.AddKnown({ 11 }) == 0, "nothing new")
  local key = NDc.CharKey()
  assert(key == "Rich - Forever" and cc.TwichUINavigationDB.chars[key].known[11], "under this character's name")
  local other = cc.TwichUINavigationDB
  other.chars["Alt - Forever"] = { known = { [99] = 5 }, seen = 1 }
  local cd, NDd = boot(other)
  assert(NDd.Known()[11] and not NDd.Known()[99], "another character's flight points aren't this one's")
  -- damaged records and entries
  local bad = { version = 1, routes = {}, times = {}, chars = {
    ["Rich - Forever"] = { known = { [11] = "when", [-3] = 1, x = 1 }, seen = "x" },
    ["Broken - Forever"] = { known = "x" },
    [5] = { known = {} },
  } }
  local ce, NDe = boot(bad)
  assert(NDe.Known()[11] == 0 and ce.TwichUINavigationDB.chars["Rich - Forever"].seen == 0, "kept, its dates reset")
  assert(ce.TwichUINavigationDB.chars["Broken - Forever"] == nil and ce.TwichUINavigationDB.chars[5] == nil)
  assert(ce.TwichUI.Persist.Report().repairs["nav-entry-dropped"] == 4, "two bad flight points, two bad records")
  -- limits
  local big = { version = 1, routes = {}, times = {}, chars = { ["Rich - Forever"] = { known = {}, seen = 1 } } }
  for i = 1, 20 do big.chars["Rich - Forever"].known[i] = i end
  local _, NDf = boot(big, function(cl) cl.TwichUI.NavData.MAX_KNOWN = 5 end)
  local n = 0
  for id in pairs(NDf.Known()) do n = n + 1; assert(id > 15, "the newest are kept") end
  assert(n == 5)
end

-- 9) Forget.
ND2.AddKnown({ 11 })
ND2.Forget()
assert(ND2.Route(11, 12) == nil and ND2.Snapshot().routes == 0 and ND2.Snapshot().times == 0 and next(ND2.Known()) == nil)

print("NAV DATA TESTS PASSED")
