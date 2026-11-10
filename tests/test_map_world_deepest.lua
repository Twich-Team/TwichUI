-- The descent under a world point (map/World.lua): MW.ChainAt's { 947, continent, zone } chain and
-- MW.Deepest's deepest-map + local-point answer, following the game's own zone shapes (C_Map.GetMapInfoAtPosition,
-- not rectangles). Values are hand-computed from the documented contract and the fake rectangles below,
-- never copied out of a run.
dofile(TESTS .. "harness.lua")
local c = MakeClient("Rich", { "!!!TwichUI" })
local chunk = assert(loadfile(ROOT .. "map/ViewMath.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
chunk = assert(loadfile(ROOT .. "map/World.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
local MW = c.TwichUI.MapWorld

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end
local function chainIs(chain, ...)
  local n = select("#", ...)
  if #chain ~= n then return false end
  for i = 1, n do if chain[i] ~= select(i, ...) then return false end end
  return true
end

---------------------------------------------------------------------------
-- The game, as the test fakes it: one stitched continent (100) with a zone
-- (200) inside it, plus maps that fail one leg of the stitchable gate.
---------------------------------------------------------------------------
-- rect on the world (947): left, right, top, bottom
local RECTS = {
  [100] = { 0.2, 0.6, 0.1, 0.5 },   -- continent
  [200] = { 0.3, 0.5, 0.2, 0.4 },   -- zone on the continent
}
-- The zone's shape as the game's own lookup (GetMapInfoAtPosition) sees it:
-- kept separate from the rectangle so the test can report a zone the
-- stitchable gate rejects.
local ZONE_SHAPE = { 0.3, 0.5, 0.2, 0.4 }
local KINDS = { [947] = 1, [100] = 2, [200] = 3, [500] = 4 }
local NO_ART = {}
local function Info(id)
  local k = KINDS[id]
  if not k then return nil end
  return { mapID = id, name = "Map " .. id, mapType = k }
end
local function RectOnWorld(id)
  if id == 947 then return 0, 1, 0, 1 end
  local r = RECTS[id]
  if r then return unpack(r) end
  return nil
end
local function ArtLayers(id)
  if NO_ART[id] then return nil end
  if not Info(id) then return nil end
  return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } }
end
-- The game's own zone shapes, one level down at a time: on the world the point
-- sits on the continent whose rectangle contains it; on the continent, on the
-- zone that contains it; otherwise the map itself.
local function AtPos(id, x, y)
  local u, v
  if id == 947 then u, v = x, y
  elseif id == 100 then u, v = MW.ToWorld(100, x, y)
  else return { mapID = id } end
  if id == 947 then
    if u >= 0.2 and u <= 0.6 and v >= 0.1 and v <= 0.5 then return { mapID = 100 } end
    return { mapID = 947 }
  end
  local l, r, t, b = unpack(ZONE_SHAPE)
  if u >= l and u <= r and v >= t and v <= b then return { mapID = 200 } end
  return { mapID = 100 }
end
c.C_Map = {
  GetMapInfo = Info,
  GetMapRectOnMap = function(child, parent)
    if parent ~= 947 then return nil end
    return RectOnWorld(child)
  end,
  GetMapArtLayers = ArtLayers,
  GetMapInfoAtPosition = AtPos,
}

---------------------------------------------------------------------------
-- 1. No deeper map: the game says the point is on the world itself
---------------------------------------------------------------------------
do
  -- (0.1, 0.9) is outside continent 100's rectangle, so GetMapInfoAtPosition
  -- reports mapID == 947 and the descent never starts.
  local chain = MW.ChainAt(0.1, 0.9)
  assert(chainIs(chain, 947), "no deeper map: the chain is just { 947 }")
  local id, x, y = MW.Deepest(0.1, 0.9)
  assert(id == 947 and near(x, 0.1) and near(y, 0.9), "the world itself is deepest, point unchanged")
end

---------------------------------------------------------------------------
-- 2. Descent to a stitchable zone: { 947, 100, 200 }, point in the zone's 0..1
---------------------------------------------------------------------------
do
  -- (0.35, 0.25) is inside zone 200's rectangle (0.3..0.5, 0.2..0.4), which is
  -- inside continent 100's rectangle (0.2..0.6, 0.1..0.5).
  local chain = MW.ChainAt(0.35, 0.25)
  assert(chainIs(chain, 947, 100, 200), "the chain descends world -> continent -> zone")
  local id, x, y = MW.Deepest(0.35, 0.25)
  -- MW.FromWorld(200, 0.35, 0.25): (0.35-0.3)/0.2 = 0.25, (0.25-0.2)/0.2 = 0.25
  assert(id == 200 and near(x, 0.25) and near(y, 0.25), "deepest is the zone, point converted to the zone's 0..1")
end

---------------------------------------------------------------------------
-- 3. The chain stops before a map MW.Stitchable rejects
---------------------------------------------------------------------------
do
  -- (0.4, 0.3) is inside 200's rectangle (0.3..0.5, 0.2..0.4), which is inside
  -- continent 100's rectangle (0.2..0.6, 0.1..0.5), so the game's lookup reports
  -- 200 one level down and the descent can reach the stitchable gate.
  -- 200 has a wrong kind (4): not stitchable, so the descent stops at the last
  -- stitchable ancestor, continent 100.
  KINDS[200] = 4
  MW.Forget()
  local chain = MW.ChainAt(0.4, 0.3)
  assert(chainIs(chain, 947, 100), "a wrong-kind child stops the chain")
  local id, x, y = MW.Deepest(0.4, 0.3)
  -- MW.FromWorld(100, 0.4, 0.3): (0.4-0.2)/0.4 = 0.5, (0.3-0.1)/0.4 = 0.5
  assert(id == 100 and near(x, 0.5) and near(y, 0.5), "deepest is the last stitchable ancestor")
  MW.Forget()

  -- 200 has the zone kind and art but no rectangle on the world.
  KINDS[200] = 3
  RECTS[200] = nil
  local chain = MW.ChainAt(0.4, 0.3)
  assert(chainIs(chain, 947, 100), "a zone without a rectangle stops the chain")
  local id, x, y = MW.Deepest(0.4, 0.3)
  assert(id == 100 and near(x, 0.5) and near(y, 0.5), "deepest stays the continent")
  MW.Forget()

  -- 200 has the zone kind and a rectangle but no art.
  RECTS[200] = { 0.3, 0.5, 0.2, 0.4 }
  NO_ART[200] = true
  local chain = MW.ChainAt(0.4, 0.3)
  assert(chainIs(chain, 947, 100), "a zone without art stops the chain")
  local id, x, y = MW.Deepest(0.4, 0.3)
  -- MW.FromWorld(100, 0.4, 0.3): (0.4-0.2)/0.4 = 0.5, (0.3-0.1)/0.4 = 0.5
  assert(id == 100 and near(x, 0.5) and near(y, 0.5), "deepest stays the continent")
  NO_ART[200] = nil
  MW.Forget()
end

---------------------------------------------------------------------------
-- 4. A failing GetMapInfoAtPosition (the API absent) degrades to the world
---------------------------------------------------------------------------
do
  local fake = c.C_Map
  c.C_Map = {
    GetMapInfo = Info,
    GetMapRectOnMap = function(child, parent)
      if parent ~= 947 then return nil end
      return RectOnWorld(child)
    end,
    GetMapArtLayers = ArtLayers,
  }   -- no GetMapInfoAtPosition: pcall fails, the descent never starts
  local chain = MW.ChainAt(0.4, 0.3)
  assert(chainIs(chain, 947), "a failing lookup leaves the chain at { 947 }")
  local id, x, y = MW.Deepest(0.4, 0.3)
  assert(id == 947 and near(x, 0.4) and near(y, 0.3), "deepest is the world, point unchanged, no error")
  c.C_Map = fake
  MW.Forget()
end

---------------------------------------------------------------------------
-- 5. MW.Forget keeps the descent consistent with the cached rects
---------------------------------------------------------------------------
do
  local id, x, y = MW.Deepest(0.4, 0.3)
  assert(id == 200 and near(x, 0.5) and near(y, 0.5), "before Forget: the zone with the old rectangle")
  -- The game moves the zone: now (0.35..0.55, 0.25..0.45) on the world.
  RECTS[200] = { 0.35, 0.55, 0.25, 0.45 }
  id, x, y = MW.Deepest(0.4, 0.3)
  assert(id == 200 and near(x, 0.5) and near(y, 0.5), "the old rectangle is cached until Forget")
  MW.Forget()
  id, x, y = MW.Deepest(0.4, 0.3)
  -- MW.FromWorld(200, 0.4, 0.3) with the new rectangle: (0.4-0.35)/0.2 = 0.25, (0.3-0.25)/0.2 = 0.25
  assert(id == 200 and near(x, 0.25) and near(y, 0.25), "after Forget: the descent follows the changed rectangle")
end

print("TEST_MAP_WORLD_DEEPEST PASSED")
