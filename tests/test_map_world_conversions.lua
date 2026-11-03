-- The world geometry's direct conversions (map/World.lua): MW.Rect's caching and nil-vs-false
-- distinction, the MW.ToWorld/MW.FromWorld round-trip, MW.Stitchable's kind+rect+art gate, and
-- MW.FromYards/MW.YardsRect's corner ordering and nil for off-world continents. Values are
-- hand-computed from the documented contract, never copied out of a run.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "map/ViewMath.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
chunk = assert(loadfile(ROOT .. "map/World.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local MW = c.TwichUI.MapWorld
local VM = c.TwichUI.MapViewMath

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end

---------------------------------------------------------------------------
-- The game, as the test fakes it: one stitched continent (100) with a zone
-- (200) inside it, plus maps that fail one leg of the stitchable gate
---------------------------------------------------------------------------
-- rect on the world (947): left, right, top, bottom
local RECTS = {
  [100] = { 0.2, 0.6, 0.1, 0.5 },   -- continent
  [200] = { 0.3, 0.4, 0.2, 0.3 },   -- zone on the continent
}
local KINDS = { [947] = 1, [100] = 2, [200] = 3, [300] = 2, [400] = 3, [500] = 4 }
local function Info(id)
  local k = KINDS[id]
  if not k then return nil end
  return { mapID = id, name = "Map " .. id, mapType = k }
end
local function RectOnWorld(id)
  if id == 947 then return 0, 1, 0, 1 end
  local r = RECTS[id]
  if r then return unpack(r) end
  return nil   -- 600: the game doesn't place it on the world
end
local function ArtLayers(id)
  -- 300 is a continent with no art; everything else that exists has it
  if id == 300 then return nil end
  if not Info(id) then return nil end
  return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
end
c.C_Map = {
  GetMapInfo = Info,
  GetMapRectOnMap = function(child, parent)
    if parent ~= 947 then return nil end
    return RectOnWorld(child)
  end,
  GetMapArtLayers = ArtLayers,
  GetMapChildrenInfo = function(id)
    local KIDS = { [947] = { 100, 300 }, [100] = { 200, 400 } }
    local kids = KIDS[id] or {}
    local out = {}
    for _, kid in ipairs(kids) do out[#out + 1] = Info(kid) end
    return out
  end,
}

---------------------------------------------------------------------------
-- MW.Rect: the world itself, a placed map, and nil (not false) for off-world
---------------------------------------------------------------------------
do
  -- 947 is the world map: always {0,1,0,1}, with no game call at all
  c.C_Map = nil
  local l, r, t, b = MW.Rect(947)
  assert(near(l, 0) and near(r, 1) and near(t, 0) and near(b, 1), "the world map is the whole world, no game call")
  c.C_Map = {
    GetMapInfo = Info,
    GetMapRectOnMap = function(child, parent)
      if parent ~= 947 then return nil end
      return RectOnWorld(child)
    end,
    GetMapArtLayers = ArtLayers,
    GetMapChildrenInfo = function(id)
      local KIDS = { [947] = { 100, 300 }, [100] = { 200, 400 } }
      local kids = KIDS[id] or {}
      local out = {}
      for _, kid in ipairs(kids) do out[#out + 1] = Info(kid) end
      return out
    end,
  }
  -- a map the game places: its rectangle, straight from the game
  l, r, t, b = MW.Rect(100)
  assert(near(l, 0.2) and near(r, 0.6) and near(t, 0.1) and near(b, 0.5), "a placed map's rectangle")
  -- a map the game doesn't place: nil, not false; and the nil is cached, not re-derived
  assert(MW.Rect(600) == nil, "an off-world map has no rectangle (nil)")
  assert(MW.Rect(600) == nil, "the off-world answer stays nil after caching")
end

---------------------------------------------------------------------------
-- MW.ToWorld / MW.FromWorld: exact inverses on a synthetic rectangle
---------------------------------------------------------------------------
do
  -- continent 100 sits at left 0.2, right 0.6, top 0.1, bottom 0.5 on the world
  local u, v = MW.ToWorld(100, 0.3, 0.75)
  assert(near(u, 0.32) and near(v, 0.4), "ToWorld: 0.2 + 0.3*0.4, 0.1 + 0.75*0.4")
  local x, y = MW.FromWorld(100, 0.32, 0.4)
  assert(near(x, 0.3) and near(y, 0.75), "FromWorld undoes ToWorld exactly")
  -- the round trip at another point
  u, v = MW.ToWorld(100, 0, 0)
  x, y = MW.FromWorld(100, u, v)
  assert(near(x, 0) and near(y, 0), "round trip at the map's corner")
  u, v = MW.ToWorld(100, 1, 1)
  x, y = MW.FromWorld(100, u, v)
  assert(near(x, 1) and near(y, 1), "round trip at the far corner")
  -- where Rect is nil, both conversions are nil
  assert(MW.ToWorld(600, 0.5, 0.5) == nil, "ToWorld is nil where the map has no rectangle")
  assert(MW.FromWorld(600, 0.5, 0.5) == nil, "FromWorld is nil where the map has no rectangle")
end

---------------------------------------------------------------------------
-- MW.Stitchable: the world, a continent or a zone, with both a rectangle and art
---------------------------------------------------------------------------
do
  assert(MW.Stitchable(947) == true, "the world itself is stitchable")
  assert(MW.Stitchable(100) == true, "a continent with a rectangle and art")
  assert(MW.Stitchable(200) == true, "a zone with a rectangle and art")
  assert(MW.Stitchable(300) == false, "a continent kind without art is not stitchable")
  assert(MW.Stitchable(400) == false, "a zone without a rectangle is not stitchable")
  assert(MW.Stitchable(500) == false, "a non-stitchable kind is not stitchable")
  assert(MW.Stitchable(600) == false, "a map with no rectangle is not stitchable")
end

---------------------------------------------------------------------------
-- MW.FromYards / MW.YardsRect: world yards on a continent, and rectangles
-- in any corner order
---------------------------------------------------------------------------
do
  -- The continent's map frame (map/ViewMath.lua's VM.MapFrame shape): north-up, axis-aligned.
  -- The origin (ox, oy) is the map's top-left corner in world yards: x north 1000, y west 2000.
  -- The map's x-axis points east (decreasing wy): per unit of map x, ay = -4000 (4000 yards wide).
  -- The map's y-axis points south (decreasing wx): per unit of map y, bx = -2000 (2000 yards deep).
  -- So VM.ToMap gives x = (2000 - wy)/4000, y = (1000 - wx)/2000 for this frame.
  c.TwichUI.MapView = {
    MapFrame = function(id)
      if id == 100 then
        return { ox = 1000, oy = 2000, ax = 0, ay = -4000, bx = -2000, by = 0, det = -8000000, axisAligned = true, cont = 7 }
      end
      return nil
    end,
  }
  -- yards (500, 0): x = 0.5, y = 0.25 on the continent; on the world
  -- u = 0.2 + 0.5*0.4 = 0.4, v = 0.1 + 0.25*0.4 = 0.2
  local u, v = MW.FromYards(7, 500, 0)
  assert(near(u, 0.4) and near(v, 0.2), "a known yard point on the continent")
  assert(MW.FromYards(999, 500, 0) == nil, "an unknown continent is off the stitched world")
  -- a rectangle given in reversed corner order (x0 > x1, y0 > y1) comes back ordered:
  -- (1000, 2000) -> x = 0, y = 0 -> u = 0.2, v = 0.1
  -- (0, 0)       -> x = 0.5, y = 0.5 -> u = 0.4, v = 0.3
  local u0, v0, u1, v1 = MW.YardsRect(7, 1000, 2000, 0, 0)
  assert(near(u0, 0.2) and near(v0, 0.1) and near(u1, 0.4) and near(v1, 0.3), "reversed corners come back ordered")
  assert(u0 <= u1 and v0 <= v1, "u0 <= u1 and v0 <= v1")
  assert(MW.YardsRect(999, 0, 0, 100, 100) == nil, "a rectangle off the stitched world is nil")
end

---------------------------------------------------------------------------
-- MW.Forget: forget what the game said, so a changed answer is picked up
---------------------------------------------------------------------------
do
  local l, r, t, b = MW.Rect(100)
  assert(near(l, 0.2) and near(r, 0.6), "before Forget: the game's rectangle")
  c.C_Map.GetMapRectOnMap = function(child, parent)
    if parent ~= 947 then return nil end
    if child == 100 then return 0.5, 0.9, 0.2, 0.6 end
    return RectOnWorld(child)
  end
  l, r, t, b = MW.Rect(100)
  assert(near(l, 0.2), "the old rectangle is cached until Forget")
  MW.Forget()
  l, r, t, b = MW.Rect(100)
  assert(near(l, 0.5) and near(r, 0.9) and near(t, 0.2) and near(b, 0.6), "after Forget: the changed answer is picked up")
  -- the world map needs no game call, even after Forget
  l, r, t, b = MW.Rect(947)
  assert(near(l, 0) and near(r, 1) and near(t, 0) and near(b, 1), "947 is still the whole world after Forget")
end

print("TEST_MAP_WORLD_CONVERSIONS PASSED")
