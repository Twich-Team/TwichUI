-- Real numeric WMO tables, production placement/culling and city classification.
-- API geometry and textures are synthetic: this cannot prove native assets resolve.
dofile(TESTS .. "harness.lua")
local env = { TwichUI = { PATH = "", MapExplorePrefs = {
  Subscribe = function() end,
  Get = function(key) return ({ detail = true, detailStrength = 70, unexplored = "show" })[key] end,
} } }
setmetatable(env, { __index = _G })
local function object(parent)
  local o = { parent = parent, shown = true, level = 10 }
  function o:SetSize(w, h) self.w, self.h = w, h end
  function o:SetPoint(...) self.point = { ... } end
  function o:ClearAllPoints() self.point = nil end
  function o:SetTexture(file) self.file = file; if file == 989999 then return false end end
  function o:SetAlpha(a) self.alpha = a end
  function o:SetRotation(a) self.rotation = a end
  function o:SetFrameLevel(n) self.level = n end
  function o:GetFrameLevel() return self.level end
  function o:SetShown(v) self.shown = v end
  function o:Show() self.shown = true end
  function o:Hide() self.shown = false end
  function o:IsShown() return self.shown end
  function o:CreateTexture() return object(self) end
  o.CreateMaskTexture = o.CreateTexture
  for _, key in ipairs({ "SetTexCoord", "SetDrawLayer", "SetVertexColor", "SetScale", "SetAllPoints", "EnableMouse", "AddMaskTexture" }) do
    o[key] = function() end
  end
  return o
end
env.CreateFrame = function(_, _, parent) return object(parent) end
local ids = { 1453, 1454, 1455, 1456, 1457, 1458 }
env.C_Map = {
  GetMapRectOnMap = function(id)
    if id == 1415 then return 0.55, 0.95, 0.1, 0.9 end
    if id == 1414 then return 0.05, 0.45, 0.1, 0.9 end
    return 0.6, 0.62, 0.4, 0.42
  end,
  GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
  GetMapArtID = function(id) return id end,
  GetMapArtLayerTextures = function(id) local a = {}; for i = 1, 12 do a[i] = id * 100 + i end; return a end,
  GetMapInfo = function(id) return { mapID = id, mapType = id == 947 and 1 or (id == 1415 or id == 1414) and 2 or 3 } end,
  GetMapChildrenInfo = function(id)
    local out = {}
    if id == 947 then return { { mapID = 1415 }, { mapID = 1414 } } end
    if id == 1415 then for _, city in ipairs(ids) do out[#out + 1] = { mapID = city } end end
    return out
  end,
}
env.C_MapExplorationInfo = { GetExploredMapTextures = function()
  return { { textureWidth = 128, textureHeight = 128, offsetX = 0, offsetY = 0, fileDataIDs = { 9001 } } }
end }
local function load(name) local f = assert(loadfile(ROOT .. "map/" .. name .. ".lua")); setfenv(f, env); f() end
load("ViewMath"); load("World")
collectgarbage("collect")
local dataBefore = collectgarbage("count")
load("LocalData")
collectgarbage("collect")
local dataKiB = collectgarbage("count") - dataBefore
local R, VM = env.TwichUI, env.TwichUI.MapViewMath
local f = VM.MapFrame(20000, 20000, 20000, -20000, -20000, 20000)
local canvas = object()
R.MapView = { Subscribe = function() end, Canvas = function() return canvas end,
  MapFrame = function(id) return { ox = f.ox, oy = f.oy, ax = f.ax, ay = f.ay, bx = f.bx, by = f.by, det = f.det,
    axisAligned = true, cont = id == 1414 and 1 or 0 } end }
load("Pictures"); load("Art")
assert(R.MapArt.Build(), "production art constructs")
assert(R.MapArt.Snapshot().cities == 6, "all six cities classified even with explored pieces")
for _, id in ipairs(ids) do assert(R.MapArt.City(id) and #R.MapArt.City(id).tex == 12, "city base artwork: " .. id) end
local D = R.MapExploreLocalData
assert(D.build == "1.60.1.70245" and #D.caves == 248 and D.cities[1455] and D.cities[1458], "pinned Forever numeric data")
local recordCount, pictureCount, maxMade = 0, 0, 0
local set = R.MapPictures.Create(object())
local function check(c)
  recordCount = recordCount + 1
  assert((c[1] == 0 or c[1] == 1) and c[2] < c[4] and c[3] < c[5] and #c[6] % 7 == 0, "valid continent/rectangle/picture tuple count")
  for i = 1, #c[6], 7 do
    local id, x, y, side, angle, u1, v0 = unpack(c[6], i, i + 6)
    assert(VM.Finite(id) and id > 0 and id % 1 == 0, "client file ID, never a copied artwork path")
    assert(VM.Finite(x) and VM.Finite(y) and VM.Finite(side) and side > 0 and VM.Finite(angle) and VM.Finite(u1) and VM.Finite(v0))
    pictureCount = pictureCount + 1
  end
  R.MapPictures.Set(set, c)
  R.MapPictures.Update(set, 0, 0, 1, 1, 0.7)
  local s = R.MapPictures.Snapshot(set)
  assert(s.active <= 256 and s.made <= 256 and s.active + s.pooled == s.made, "bounded reusable picture pool")
  for _, g in ipairs(set.geometry) do
    for j = 2, 12 do assert(VM.Finite(g[j]), "finite picture placement/culling bounds") end
    assert(g[4] > g[2] and g[5] > g[3], "north-up geographic rectangle")
  end
  maxMade = math.max(maxMade, s.made)
  R.MapPictures.Clear(set)
  assert(not next(set.used), "no stale pictures on transition")
end
for _, c in ipairs(D.caves) do check(c) end
for _, c in pairs(D.cities) do check(c) end
assert(recordCount == 250 and pictureCount == 1906, "all reviewed numeric references, minus three edited-art references: " .. recordCount .. "/" .. pictureCount)
-- Expanding a future record past the cap must release now-deprioritized visible
-- pictures too, not only offscreen pictures. This pan used to retain 300 textures.
local crowded = { 0, 0, 0, 20000, 20000, {} }
for i = 1, 300 do
  local at = i <= 150 and 1000 or 10000
  local p = crowded[6]
  for _, v in ipairs({ 980000 + i, at, at, 128, 0, 1, 0 }) do p[#p + 1] = v end
end
R.MapPictures.Set(set, crowded)
local g = set.geometry[151]
R.MapPictures.Update(set, g[9], g[10], g[11], g[12], 0.7)
R.MapPictures.Update(set, 0, 0, 1, 1, 0.7)
assert(R.MapPictures.Snapshot(set).made <= 256 and R.MapPictures.Snapshot(set).active <= 256,
  "panning from later pictures into a fully visible oversized record never exceeds pool cap")
R.MapPictures.Clear(set)
-- A native rejected file must be reported once and left out of visible coverage;
-- repeated view updates must not retry it or consume additional textures.
local rejected = { 0, 0, 0, 20000, 20000, { 989999, 1000, 1000, 128, 0, 1, 0 } }
R.MapPictures.Set(set, rejected)
R.MapPictures.Update(set, 0, 0, 1, 1, 1)
local binds = R.MapPictures.Snapshot(set).binds
R.MapPictures.Update(set, 0, 0, 1, 1, 1)
assert(R.MapPictures.Snapshot(set).active == 0 and R.MapPictures.Snapshot(set).binds == binds,
  "rejected file is not shown or repeatedly rebound")
local failures = R.MapPictures.Diagnostic().failures
assert(failures[#failures].fileId == 989999 and failures[#failures].reason == "rejected", "rejection evidence retained")
R.MapPictures.Clear(set)
print(("MAP LOCAL DATA PASSED: %d areas, %d pictures, peak reused pool %d, numeric data retained %.1f KiB")
  :format(recordCount, pictureCount, maxMade, dataKiB))
