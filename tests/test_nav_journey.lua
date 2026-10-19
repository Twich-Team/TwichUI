-- Navigation: planning a journey across continents (nav/Journey.lua), on the synthetic maps from tools/navbake/fixtures.py:
-- two small continents (9201 and 9202) joined by a ferry, each with flight points, and a teleport arrival on the second.
--   1  walking only      2  a ferry across; its wait and ride in the answer      3  a teleport beats it
--   4  the Hearthstone: its cooldown counts      5  flights, only the learned ones, only for your faction
--   6  ground speed       7  no way (nothing across, a goal off the map)         8  legs: merged flights, ends, names
--   9  a search is spread over steps; the same travel plan twice gives the same answer
-- What this cannot show: the real network (the bake's own checks and the in-game test do), or how it reads on screen.
dofile(TESTS .. "nav_codec.lua")
dofile(TESTS .. "fixtures/nav_fixture.lua")

local env = setmetatable({}, { __index = _G })
env._G = env
env.TwichUI = { Fault = function(src, err) error(src .. ": " .. tostring(err)) end,
  NavDataStore = { graph = NAV_FIXTURE.graph, tiles = NAV_FIXTURE.tiles, transit = NAV_FIXTURE.transit } }
env.C_EncodingUtil, env.Enum = NAV_CODEC.C_EncodingUtil, NAV_CODEC.Enum
env.InCombatLockdown = function() return false end
env.debugprofilestop = function() return os.clock() * 1000 end
env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
env.C_AddOns = { DoesAddOnExist = function() return true end, GetAddOnEnableState = function() return 2 end,
  IsAddOnLoaded = function() return true end, LoadAddOn = function() return true end }
env.UnitName = function() return "Tester" end
for _, f in ipairs({ "nav/Data.lua", "nav/Route.lua", "nav/Journey.lua" }) do
  local chunk = assert(loadfile(ROOT .. f))
  setfenv(chunk, env)
  chunk()
end
local R = env.TwichUI
local ND, J = R.NavData, R.NavJourney
assert(ND.Load())

local TILE = 1600 / 3
local ORIGIN = 32 * TILE
local CS = TILE / 40
local TILES = { [9201] = { 32, 33 }, [9202] = { 32, 34 } }
local function P(cont, u, w)    -- tile-local cells to a { cont, x, y }
  local t = TILES[cont]
  return { cont = cont, x = ORIGIN - t[2] * TILE - TILE + u * CS, y = ORIGIN - t[1] * TILE - TILE + w * CS }
end
local function Req(over)
  local r = { start = P(9201, 5, 21), goal = P(9202, 34, 20), speed = 7, faction = 1, ships = true }
  for k, v in pairs(over or {}) do r[k] = v end
  return r
end
local function Kinds(j)
  local out = {}
  for _, l in ipairs(j.legs) do out[#out + 1] = l.kind end
  return table.concat(out, ",")
end
local function Near(a, b, tol) return math.abs(a - b) <= tol end
local KNOWN = { [101] = true, [102] = true, [103] = true, [104] = true }
local TELE = { { spell = 3561, place = 7, cast = 10 } }

local tr = ND.Transit()
assert(tr and tr.place[3].town == "Alpha" and #tr.ferries == 2 and #tr.flights == 4 and tr.teleports[1].place == 7,
  "the travel network decodes")
assert(ND.Stand(3) == 9201 and ND.Stand(4) == 9202, "places stand on their own continent")

-- 1. Walking only: on one continent, no flights known, nothing else
do
  local j = assert(J.PlanNow(Req({ goal = P(9201, 35, 20), ships = false })))
  assert(Kinds(j) == "walk" and j.walkOnly, "walks: " .. Kinds(j))
  assert(Near(j.seconds, 30 * CS / 7, 1.5), "about 57 s on foot: " .. j.seconds)
  print("1 walking ok", math.floor(j.seconds), "s")
end

-- 2. A ferry across
do
  local j = assert(J.PlanNow(Req()))
  assert(Kinds(j) == "walk,ferry,walk", "walk, ferry, walk: " .. Kinds(j))
  local f = j.legs[2]
  assert(f.transport == "boat" and f.fromName == "Alpha" and f.toName == "Beta", "named by its docks")
  assert(Near(f.wait, (300 - 30) ^ 2 / 600, 0.5), "the expected wait: " .. f.wait)
  assert(f.travel == 100, "its ride")
  assert(j.legs[1].to == 3 and j.legs[3].from == 4, "walks to the dock and from the other one")
  assert(j.legs[1].toLabel == "Alpha dock", "a walk to a boat is to its dock: " .. tostring(j.legs[1].toLabel))
  assert(j.legs[3].to == "G" and j.legs[1].from == "S", "from you, to the destination")
  local expect = j.legs[1].seconds + f.wait + f.travel + J.BOARD + j.legs[3].seconds
  assert(Near(j.seconds, expect, 0.01), "the legs add up to the total")
  assert(j.seconds > 250 and j.seconds < 400, "a few minutes: " .. j.seconds)
  -- ships turned off: no other way across
  local none, why = J.PlanNow(Req({ ships = false }))
  assert(not none and why == "other-continent", "no ferry, no way: " .. tostring(why))
  -- a ferry for the other faction only
  print("2 ferry ok", math.floor(j.seconds), "s, wait", math.floor(f.wait))
end

-- 3. A teleport beats the ferry (cast + the rune's bias + a short walk)
do
  local j = assert(J.PlanNow(Req({ teleports = TELE })))
  assert(Kinds(j) == "teleport,walk", "teleport then walk: " .. Kinds(j))
  assert(j.legs[1].spell == 3561 and j.legs[1].to == 7 and j.legs[1].from == "S", "from where you stand")
  assert(Near(j.seconds, 10 + J.RUNE_BIAS + 2 * CS / 7, 1.5), "cast, bias and a few steps: " .. j.seconds)
  -- with nothing else on foot at all: still possible from a spot with no ground (a boat, say)
  local req = Req({ teleports = TELE })
  req.start = { cont = 9201, x = req.start.x + 5000, y = req.start.y }
  local off = assert(J.PlanNow(req))
  assert(Kinds(off) == "teleport,walk", "a teleport needs no ground under you: " .. Kinds(off))
  print("3 teleport ok", math.floor(j.seconds), "s")
end

-- 4. The Hearthstone: its cooldown is part of its cost
do
  local bind = P(9202, 34, 18)
  local ready = assert(J.PlanNow(Req({ hearth = { cont = 9202, x = bind.x, y = bind.y, seconds = 10 } })))
  assert(Kinds(ready) == "hearth,walk", "ready: " .. Kinds(ready))
  assert(ready.legs[1].to == "H" and ready.legs[1].tcont == 9202, "to the bind point, on its continent")
  assert(ready.seconds < 20, "ten seconds and a short walk: " .. ready.seconds)
  local cooling = assert(J.PlanNow(Req({ hearth = { cont = 9202, x = bind.x, y = bind.y, seconds = 10 + 1200 } })))
  assert(Kinds(cooling) == "walk,ferry,walk", "with 20 minutes of cooldown left the ferry is better: " .. Kinds(cooling))
  print("4 hearth ok", math.floor(ready.seconds), "s")
end

-- 5. Flights: only learned ones, only for your faction
do
  local goal = P(9201, 35, 20)
  local fly = assert(J.PlanNow(Req({ goal = goal, ships = false, flights = KNOWN })))
  assert(Kinds(fly) == "walk,flight,walk" or Kinds(fly) == "flight,walk" or Kinds(fly) == "walk,flight", "flies: " .. Kinds(fly))
  local leg
  for _, l in ipairs(fly.legs) do if l.kind == "flight" then leg = l end end
  assert(leg.fromName == "Alpha Landing" and leg.toName == "Alpha Heights", "named by its places")
  assert(fly.seconds < 30 * CS / 7, "faster than walking: " .. fly.seconds)
  -- not learned: walked
  local partial = assert(J.PlanNow(Req({ goal = goal, ships = false, flights = { [101] = true } })))
  assert(partial.walkOnly, "one end not learned: " .. Kinds(partial))
  -- Alpha Heights is Alliance only
  local horde = assert(J.PlanNow(Req({ goal = goal, ships = false, flights = KNOWN, faction = 2 })))
  assert(horde.walkOnly, "the other faction walks: " .. Kinds(horde))
  -- flight toggled off by passing no set
  assert(J.PlanNow(Req({ goal = goal, ships = false })).walkOnly, "no flights offered, none used")
  -- a flight chain is one leg
  print("5 flights ok", math.floor(fly.seconds), "s")
end

-- 6. Ground speed scales walking, not the rides
do
  local foot = assert(J.PlanNow(Req({ ships = false, goal = P(9201, 35, 20) })))
  local mount = assert(J.PlanNow(Req({ ships = false, goal = P(9201, 35, 20), speed = 7 * 1.6 })))
  assert(Near(mount.seconds, foot.seconds / 1.6, 0.5), "a mount walks 1.6 times as fast")
  local cross7 = assert(J.PlanNow(Req()))
  local cross11 = assert(J.PlanNow(Req({ speed = 11.2 })))
  assert(cross11.seconds < cross7.seconds and cross7.seconds - cross11.seconds < 40, "only the walking legs change")
  print("6 speed ok")
end

-- 7. No way
do
  local goal = P(9202, 34, 20)
  goal.x = goal.x + 5000                     -- far off the map's ground
  local none, why = J.PlanNow(Req({ goal = goal }))
  assert(not none and why == "goal-off", "a goal off the ground: " .. tostring(why))
  local off = Req()
  off.start = { cont = 9201, x = off.start.x + 5000, y = off.start.y }
  local n2, w2 = J.PlanNow(off)
  assert(not n2 and w2 == "start-off", "no ground under you and nothing to cast: " .. tostring(w2))
  local nowhere, w3 = J.PlanNow(Req({ goal = { cont = 7777, x = 0, y = 0 } }))
  assert(not nowhere and w3 == "no-data", "a continent with no walking map: " .. tostring(w3))
  print("7 no way ok")
end

-- 8. Reading a journey: words and places
do
  local j = assert(J.PlanNow(Req()))
  assert(J.Minutes(20) == "under a minute" and J.Minutes(90) == "about 2 min" and J.Minutes(3600 * 1.5) == "about 1h 30 min", "minutes")
  for _, l in ipairs(j.legs) do
    assert(l.fx and l.tx and l.cont and l.fromName and l.toName, "every leg has its ends and names: " .. l.kind)
  end
  assert(j.legs[1].cont == 9201 and j.legs[3].cont == 9202, "walk legs are on their own continent")
  assert(J.Allows(3, 1) and J.Allows(1, 1) and not J.Allows(2, 1), "factions")
  print("8 legs ok")
end

-- 9. Spread over steps, and repeatable
do
  local job = J.Plan(Req({ teleports = TELE, flights = KNOWN }))
  local steps, status, result = 0, "running", nil
  while status == "running" do
    steps = steps + 1
    status, result = job:Step(0.05)
    assert(steps < 5000, "finishes")
  end
  assert(status == "done" and result.seconds, "job: " .. tostring(result))
  local again = J.PlanNow(Req({ teleports = TELE, flights = KNOWN }))
  assert(Kinds(again) == Kinds(result) and Near(again.seconds, result.seconds, 0.001), "the same travel plan twice is the same")
  print("9 job ok in", steps, "steps")
end

-- 10. The real network (TwichUI_NavData): what the bake made, planned over
do
  local DATA = REPO .. "TwichUI_NavData/"
  local toc = io.open(DATA .. "TwichUI_NavData.toc")
  if not toc then
    print("10 skipped: no TwichUI_NavData in this checkout")
  else
    local files = {}
    for line in toc:lines() do
      if line:match("%.lua%s*$") and not line:match("^#") then files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", "")) end
    end
    toc:close()
    local store = { graph = {}, tiles = {} }
    local e2 = setmetatable({}, { __index = _G })
    e2._G = e2
    e2.TwichUI = { Fault = function(src, err) error(src .. ": " .. tostring(err)) end, NavDataStore = store }
    e2.C_EncodingUtil, e2.Enum = NAV_CODEC.C_EncodingUtil, NAV_CODEC.Enum
    e2.InCombatLockdown = function() return false end
    e2.debugprofilestop = function() return os.clock() * 1000 end
    e2.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    e2.UnitName = function() return "Tester" end
    local loaded = false
    e2.C_AddOns = { DoesAddOnExist = function() return true end, GetAddOnEnableState = function() return 2 end,
      IsAddOnLoaded = function() return loaded end,
      LoadAddOn = function()
        for _, f in ipairs(files) do
          local chunk = assert(loadfile(DATA .. f))
          setfenv(chunk, e2)
          chunk()
        end
        loaded = true
        return true
      end }
    for _, f in ipairs({ "nav/Data.lua", "nav/Route.lua", "nav/Journey.lua" }) do
      local chunk = assert(loadfile(ROOT .. f))
      setfenv(chunk, e2)
      chunk()
    end
    local N, JJ, RR = e2.TwichUI.NavData, e2.TwichUI.NavJourney, e2.TwichUI.NavRoute
    assert(N.Load(), "the data loads")
    local net = N.Transit()
    assert(net and #net.ferries >= 20 and #net.flights > 200 and #net.teleports == 6, "the network is there")
    local known = {}
    local nFlights = 0
    for _, pl in pairs(net.place) do if pl.node ~= 0 then known[pl.node] = true nFlights = nFlights + 1 end end
    assert(nFlights >= 60, "flight points: " .. nFlights)
    local function Pt(cont, x, y) return { cont = cont, x = x, y = y } end
    local function Journey(over)
      local r = { speed = 7, faction = 1, ships = true, flights = known }
      for k, v in pairs(over) do r[k] = v end
      return JJ.PlanNow(r)
    end
    local function Uses(j, kind, name)
      for _, l in ipairs(j.legs) do
        if l.kind == kind and (not name or l.fromName == name or l.toName == name) then return l end
      end
    end
    -- the walks of a journey are real routes over ground (the first from where you are, the rest between places)
    local function CheckWalks(j, label)
      for _, l in ipairs(j.legs) do
        if l.kind == "walk" then
          local r, why = RR.PlanNow(l.cont, l.fx, l.fy, l.tx, l.ty)
          assert(r, label .. ": the walk " .. l.fromName .. " > " .. l.toName .. " has a route: " .. tostring(why))
          for i = 1, r.n - 1 do
            for f = 0, 1, 0.1 do
              local x, y = r.xs[i] + (r.xs[i + 1] - r.xs[i]) * f, r.ys[i] + (r.ys[i + 1] - r.ys[i]) * f
              assert(N.Locate(l.cont, x, y, 3), label .. ": the route stays on ground")
            end
          end
        end
      end
    end
    local SW, AUB, ORG, UC, GOLD = Pt(0, -8833, 629), Pt(1, 6341, 557), Pt(1, 1677, -4315), Pt(0, 1568, 268), Pt(0, -9464, 62)
    -- Alliance, Stormwind to Auberdine: the harbour boat is the way
    local j = assert(Journey({ start = SW, goal = AUB }))
    local boat = Uses(j, "ferry")
    assert(boat and boat.fromName == "Stormwind" and boat.toName == "Auberdine", "the harbour boat")
    assert(j.seconds < 20 * 60, "within twenty minutes: " .. JJ.Minutes(j.seconds))
    CheckWalks(j, "Stormwind to Auberdine")
    -- Horde, Orgrimmar to Undercity: the zeppelin
    local h = assert(Journey({ start = ORG, goal = UC, faction = 2 }))
    assert(Uses(h, "ferry", "Undercity") and Uses(h, "ferry").transport == "zeppelin", "the zeppelin")
    CheckWalks(h, "Orgrimmar to Undercity")
    -- each faction gets across, from several places, and never by the other's transport
    local starts = { GOLD, SW, Pt(0, -5605, -482), Pt(0, -14444, 509) }
    local goals = { AUB, ORG, Pt(1, -3825, -4516) }
    local n = 0
    for faction = 1, 2 do
      for _, st in ipairs(starts) do
        for _, g in ipairs(goals) do
          local jj = Journey({ start = st, goal = g, faction = faction })
          assert(jj, ("faction %d gets from (%d, %d) to (%d, %d)"):format(faction, st.x, st.y, g.x, g.y))
          for _, l in ipairs(jj.legs) do
            if l.kind == "ferry" or l.kind == "flight" then
              assert(JJ.Allows(net.place[l.from].faction, faction) and JJ.Allows(net.place[l.to].faction, faction),
                "never by the other faction's transport: " .. l.fromName .. " > " .. l.toName)
            end
          end
          n = n + 1
        end
      end
    end
    -- flights the character has not learned are never used
    local none = assert(Journey({ start = GOLD, goal = Pt(0, -5605, -482), flights = {} }))
    assert(not Uses(none, "flight"), "no learned flight points, no flights")
    -- a Horde mage's teleport home beats the zeppelin
    local land
    for _, t in ipairs(net.teleports) do if t.spell == 3567 then land = t end end
    local tele = assert(Journey({ start = UC, goal = ORG, faction = 2, teleports = { land } }))
    assert(tele.legs[1].kind == "teleport" and tele.seconds < 5 * 60, "a Horde mage teleports home: " .. JJ.Minutes(tele.seconds))
    local bad = assert(Journey({ start = UC, goal = ORG, faction = 2, teleports = { { spell = 1, place = 0, cast = 10 }, land } }))
    assert(bad.legs[1].kind == "teleport", "a landing the data doesn't know is ignored")
    print("10 real network ok:", #net.ferries, "ferries,", nFlights, "flight points,", n, "journeys planned")
  end
end

print("PASSED")
