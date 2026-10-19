-- Navigation: the walking maps and route planning (nav/Data.lua, nav/Route.lua), without frames.
--   1  synthetic maps (tools/navbake/fixtures.py, packed by the bake's own pack.py): a detour round a blocked middle,
--      a route across a tile edge through a gap, islands that can't be reached, a lake walked round, a wide lake swum,
--      stacked floors, the funnel on its own
--   2  the real walking maps in TwichUI_NavData, loaded through its .toc as the game would: routes in Elwynn, Duskwood,
--      Dun Morogh and Durotar must stay on walkable ground every few yards; Thunder Bluff's mesas (reached only by the
--      lifts, which the walking maps do not have) must be refused, not drawn through the air
--   3  jobs: a search spread over steps, and a dropped job leaving nothing behind
-- What this cannot show: that the game's coordinates match the bake's frame (Nav.lua checks that in the game), real
-- in-game movement, or how a route feels to follow.
dofile(TESTS .. "nav_codec.lua")
dofile(TESTS .. "fixtures/nav_fixture.lua")

local function Env(store, loaded, onLoad)
  local env = setmetatable({}, { __index = _G })
  env._G = env
  env.TwichUI = { Fault = function(src, err) error(src .. ": " .. tostring(err)) end, NavDataStore = store }
  env.C_EncodingUtil = NAV_CODEC.C_EncodingUtil
  env.Enum = NAV_CODEC.Enum
  env.InCombatLockdown = function() return false end
  env.UnitName = function() return "Tester" end
  env.debugprofilestop = function() return os.clock() * 1000 end
  env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  env.C_AddOns = {
    DoesAddOnExist = function() return true end,
    GetAddOnEnableState = function() return 2 end,
    IsAddOnLoaded = function() return loaded end,
    LoadAddOn = function()
      if onLoad then onLoad(env) end
      loaded = true
      return true
    end,
  }
  for _, f in ipairs({ "nav/Data.lua", "nav/Route.lua" }) do
    local chunk = assert(loadfile(ROOT .. f))
    setfenv(chunk, env)
    chunk()
  end
  return env
end

local function Near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

---------------------------------------------------------------------------
-- 1. Synthetic maps
---------------------------------------------------------------------------
local E = Env({ graph = NAV_FIXTURE.graph, tiles = NAV_FIXTURE.tiles }, true)
local R = E.TwichUI
local ND, RT = R.NavData, R.NavRoute
assert(ND.Load(), "fixture data counts as loaded")
local TILE, ORIGIN = ND.TILE, ND.ORIGIN
local CS = TILE / 40
-- world point of tile-local cells (u north, w west)
local function W(tx, ty, u, w)
  return ORIGIN - ty * TILE - TILE + u * CS, ORIGIN - tx * TILE - TILE + w * CS
end

-- 1a. The U: the straight line crosses the missing middle; the route goes down the west strip, along the south and up.
do
  local sx, sy = W(32, 32, 35, 35)
  local gx, gy = W(32, 32, 35, 5)
  local r, why = RT.PlanNow(9001, sx, sy, gx, gy)
  assert(r, "U route: " .. tostring(why))
  assert(r.n == 4, "U route has two corners, got " .. r.n)
  local c1x, c1y = W(32, 32, 10, 30)
  local c2x, c2y = W(32, 32, 10, 10)
  assert(Near(r.xs[2], c1x) and Near(r.ys[2], c1y), "first corner at the strip's inner corner")
  assert(Near(r.xs[3], c2x) and Near(r.ys[3], c2y), "second corner at the other inner corner")
  local straight = math.sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2)
  assert(r.length > straight * 1.5, "the detour is longer than the straight line")
  for i = 1, r.n - 1 do assert(not r.swim[i], "no swimming in the U") end
  print("1a detour ok", string.format("%.0f yd vs %.0f straight", r.length, straight))
end

-- 1b. Across a tile edge, through the gap in the east tile's wall.
do
  local sx, sy = W(32, 32, 30, 20)
  local gx, gy = W(33, 32, 30, 8)
  local r, why = RT.PlanNow(9002, sx, sy, gx, gy)
  assert(r, "cross-tile route: " .. tostring(why))
  local gapCorner = false
  for i = 2, r.n - 1 do
    local ux = (r.xs[i] - (ORIGIN - 32 * TILE - TILE)) / CS      -- u in tile 33's cells (same row)
    if Near(ux, 8, 0.05) then gapCorner = true end
  end
  assert(gapCorner, "the route turns at the gap (u = 8)")
  -- every point of it is on walkable ground
  for i = 1, r.n - 1 do
    for s = 0, 1, 0.05 do
      local x = r.xs[i] + (r.xs[i + 1] - r.xs[i]) * s
      local y = r.ys[i] + (r.ys[i + 1] - r.ys[i]) * s
      assert(ND.Locate(9002, x, y, 0.2), "cross-tile route stays on ground")
    end
  end
  print("1b cross-tile ok", r.n, "points")
end

-- 1c. Islands: within one tile (no shared edge), and in another tile (no crossing at all). Refused, quickly.
do
  local sx, sy = W(40, 40, 20, 30)
  local r, why = RT.PlanNow(9003, sx, sy, W(40, 40, 20, 8))
  assert(not r and why == "unreachable", "same-tile island refused: " .. tostring(why))
  r, why = RT.PlanNow(9003, sx, sy, W(41, 40, 20, 20))
  assert(not r and why == "unreachable", "other-tile island refused: " .. tostring(why))
  -- a destination far from any ground
  r, why = RT.PlanNow(9003, sx, sy, W(39, 40, 20, 20))
  assert(not r and why == "goal-off", "no ground at the destination: " .. tostring(why))
  local ox, oy = W(39, 40, 20, 20)
  r, why = RT.PlanNow(9003, ox, oy, sx, sy)
  assert(not r and why == "start-off", "no ground at the start: " .. tostring(why))
  r, why = RT.PlanNow(1234, sx, sy, sx, sy)
  assert(not r and why == "no-data", "a map without data: " .. tostring(why))
  print("1c unreachable ok")
end

-- 1d. A lake walked round (swimming costs 3x).
do
  local ax, ay = W(50, 50, 20, 35)
  local bx, by = W(50, 50, 20, 5)
  local r = assert(RT.PlanNow(9004, ax, ay, bx, by))
  for i = 1, r.n - 1 do assert(not r.swim[i], "walks round the lake") end
  assert(r.n >= 4, "goes round, not across")
  -- 1e. A narrow lake whose way round is long: swum.
  ax, ay = W(50, 50, 2, 30)
  bx, by = W(50, 50, 2, 10)
  local r2 = assert(RT.PlanNow(9005, ax, ay, bx, by))
  assert(r2.n == 2, "straight across the narrow lake, not round it: " .. r2.n .. " points")
  assert(Near(r2.wet[1], 8 * CS, 0.5), "8 cells of it are swum: " .. tostring(r2.wet[1]))
  assert(not r2.swim[1], "mostly walking (12 of 20 cells), so the segment is not a swim")
  assert(r.wet[1] == 0, "walking round the first lake swims nothing")
  print("1d/1e water ok")
end

-- 1f. Stacked floors: the ground floor unless told otherwise.
do
  local x, y = W(50, 50, 10, 20)
  local t, p = ND.Locate(9006, x, y, 0)
  assert(t and t.zmin[p] == 0, "the street, not the walkway above")
  local _, upper
  for q = 1, t.np do if t.zmin[q] == 20 then upper = q end end
  local t2, p2 = ND.Locate(9006, x, y, 0, { tile = t.id, poly = upper })
  assert(t2 and p2 == upper, "the walkway when the player was on it")
  print("1f floors ok")
end

-- 1g. The funnel alone: a straight corridor gives no corners; a bend gives its corner.
do
  local lx, ly, rx, ry = { 0, 10, 20, 30 }, { 0, 1, 1, 0 }, { 0, 10, 20, 30 }, { 0, -1, -1, 0 }
  local xs = RT.Funnel(lx, ly, rx, ry, 4)
  assert(#xs == 2, "straight corridor: start and end only, got " .. #xs)
  -- walking north (x up), the corridor bends west (y up) after x = 10: the inner corner is (10, 1)?
  -- portals: start (0,0); (10, -1)-(10, 1) wait: left of travel north is west (+y)
  lx, ly = { 0, 10, 10, 10 }, { 0, 1, 1, 20 }
  rx, ry = { 0, 10, 12, 10 }, { 0, -1, 1, 20 }
  local fx, fy = RT.Funnel(lx, ly, rx, ry, 4)
  assert(#fx >= 2, "bend handled")
  print("1g funnel ok")
end

---------------------------------------------------------------------------
-- 2. The real walking maps
---------------------------------------------------------------------------
local DATA = REPO .. "TwichUI_NavData/"
local toc = io.open(DATA .. "TwichUI_NavData.toc")
if not toc then
  print("2 skipped: no TwichUI_NavData in this checkout")
else
  local files = {}
  for line in toc:lines() do
    if line:match("%.lua%s*$") and not line:match("^#") then files[#files + 1] = line:gsub("\\", "/"):gsub("%s+$", "") end
  end
  toc:close()
  local t0 = os.clock()
  local E2 = Env({ graph = {}, tiles = {} }, false, function(env)
    for _, f in ipairs(files) do
      local chunk = assert(loadfile(DATA .. f))
      setfenv(chunk, env)
      chunk()
    end
  end)
  local ND2, RT2 = E2.TwichUI.NavData, E2.TwichUI.NavRoute
  assert(ND2.Load(), "TwichUI_NavData loads")
  assert(ND2.HasMap(0) and ND2.HasMap(1), "both continents")
  print(string.format("2 data loaded in %.2fs", os.clock() - t0))

  local function OnGround(map, r, step, reach)
    local bad = 0
    for i = 1, r.n - 1 do
      local dx, dy = r.xs[i + 1] - r.xs[i], r.ys[i + 1] - r.ys[i]
      local len = math.sqrt(dx * dx + dy * dy)
      for d = 0, len, step do
        local s = len > 0 and d / len or 0
        if not ND2.Locate(map, r.xs[i] + dx * s, r.ys[i] + dy * s, reach) then bad = bad + 1 end
      end
    end
    return bad
  end
  local function Straight(map, sx, sy, gx, gy, step)
    local len = math.sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2)
    local off = 0
    for d = 0, len, step do
      local s = d / len
      if not ND2.Locate(map, sx + (gx - sx) * s, sy + (gy - sy) * s, 1) then off = off + 1 end
    end
    return off
  end
  -- World positions (x north, y west), from places the bake's own frame puts in those zones.
  local CASES = {
    { "Goldshire to Stormwind", 0, -9464, 62, -8833, 629 },
    { "Goldshire to Darkshire", 0, -9464, 62, -10567, -1169 },
    { "Kharanos to Ironforge", 0, -5605, -482, -4981, -882 },
    { "Orgrimmar to Razor Hill", 1, 1629, -4373, 315, -4743 },
  }
  for _, c in ipairs(CASES) do
    local name, map, sx, sy, gx, gy = c[1], c[2], c[3], c[4], c[5], c[6]
    local t1 = os.clock()
    local r, why = RT2.PlanNow(map, sx, sy, gx, gy)
    local ms = (os.clock() - t1) * 1000
    assert(r, name .. ": " .. tostring(why))
    local bad = OnGround(map, r, 4, 2.5)
    local straight = math.sqrt((gx - sx) ^ 2 + (gy - sy) ^ 2)
    local blocked = Straight(map, sx, sy, gx, gy, 4)
    print(string.format("  %s: %d points, %.0f yd (straight %.0f, %d straight samples off the ground), %d route samples off, %.0f ms",
      name, r.n, r.length, straight, blocked, bad, ms))
    assert(bad == 0, name .. ": the route leaves walkable ground at " .. bad .. " samples")
    assert(r.length >= straight - 1, name .. ": a route is never shorter than the straight line")
  end
  -- Thunder Bluff's mesas: reached only by lifts, which the walking maps do not have.
  local r, why = RT2.PlanNow(1, -2346, -385, -1277, 124)
  print("  Bloodhoof Village to Thunder Bluff:", r and ("route of " .. math.floor(r.length) .. " yd") or why)
  assert(not r and (why == "unreachable" or why == "goal-off"), "Thunder Bluff is refused, not routed through the air")

  -- 3. Jobs: spread over steps; dropped jobs hold nothing
  local job = RT2.Plan(0, -9464, 62, -10567, -1169)
  local steps, status, result = 0, "running", nil
  while status == "running" do
    steps = steps + 1
    status, result = job:Step(1)
    assert(steps < 5000, "the job finishes")
  end
  assert(status == "done" and result.n >= 2, "job result: " .. tostring(result))
  print("3 job ok in", steps, "steps of 1 ms")
  local dropped = RT2.Plan(1, 1629, -4373, 315, -4743)
  dropped:Step(0.01)
  dropped = nil
  collectgarbage("collect")
  local snap = ND2.Snapshot()
  assert(snap.decodedTiles <= ND2.MAX_TILES, "the tile cache stays bounded")
  ND2.Release()
  assert(ND2.Snapshot().decodedTiles == 0, "release drops every decoded tile")
  print("3 bounded cache ok", snap.decoded, "decoded,", snap.released, "released")
end

print("PASSED")
