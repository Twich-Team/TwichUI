-- World map exploration (map/): one seamless world map on a scroll container that follows the game's rules (its scroll
-- limits overridable, its zoom levels set up per map, a release within a few pixels of its press a click and anything else a
-- pan, a map change resetting the zoom), on a synthetic world: two continents placed on the world map, zones and a city in
-- them, and an island that isn't on the world map. Synthetic place data; the real data is checked in test_map_data.lua.
--    1  view arithmetic             2  the world's geometry           3  off by default, on and off, OpenMap
--    4  seamless zoom, the map underneath following, combat          5  panning across a zone's edge, clicks in and out
--    6  TwichUI's pins and pings across edges, drags and clicks      7  the stitched painting
--    8  terrain detail             9  caves                         10  places and travel
--   11  dungeon maps              12  turning it off                 13  no idle work, bounded growth
--   14  preferences               15  the troubleshooting report
-- What this cannot show: the game's real canvas, textures, how a zoom feels, seams between paintings, or taint in the game.
dofile(TESTS .. "harness.lua")
CLOCK = 1000

local c = MakeClient("Rich Hale", { "!!!TwichUI" })
CLIENTS["Rich Hale"] = c
c.GetTime = function() return CLOCK end
c.issecretvalue = nil
c.debugprofilestop = function() return os.clock() * 1000 end

---------------------------------------------------------------------------
-- Frames: every method exists; scripts and hooks are kept so a test can fire them
---------------------------------------------------------------------------
local FRAMES = {}
local function Obj()
  local o = { shown = true, scripts = {}, hooks = {}, masks = {} }
  return setmetatable(o, { __index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" or k == "IsVisible" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "SetPoint" then return function(s, ...) s.point = { ... } end end
    if k == "ClearAllPoints" then return function(s) s.point = nil end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "SetWidth" then return function(s, v) s.width = v end end
    if k == "SetHeight" then return function(s, v) s.height = v end end
    if k == "GetWidth" then return function(s) return s.width or 100 end end
    if k == "GetHeight" then return function(s) return s.height or 20 end end
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "GetScale" or k == "GetEffectiveScale" then return function(s) return s.scale or 1 end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "GetAlpha" then return function(s) return s.alpha or 1 end end
    if k == "SetFrameLevel" then return function(s, v) s.level = v end end
    if k == "GetFrameLevel" then return function(s) return s.level or 5 end end
    if k == "SetTexture" then return function(s, v) s.tex = v end end
    if k == "SetTexCoord" then return function(s, ...) s.coord = { ... } end end
    if k == "SetVertexColor" then return function(s, r, g, b) s.color = { r, g, b } end end
    if k == "AddMaskTexture" then return function(s, m) s.masks[#s.masks + 1] = m end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "GetStringWidth" then return function(s) return #(s.text or "") * 6 end end
    if k == "SetFont" then return function() return true end end
    if k == "GetFont" then return function() return "Fonts\\FRIZQT__.TTF", 10, "" end end
    if k == "CreateTexture" or k == "CreateFontString" or k == "CreateLine" or k == "CreateMaskTexture" then
      return function(s) local x = Obj(); x.parent = s; x.kind = k; return x end
    end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end })
end
c.CreateFrame = function(kind, name, parent)
  local o = Obj()
  o.kind, o.parent = kind, parent
  FRAMES[#FRAMES + 1] = o
  if name then c[name] = o end
  return o
end
local function Fire(f, name, ...)
  if f.scripts[name] then f.scripts[name](f, ...) end
  for _, h in ipairs(f.hooks[name] or {}) do h(f, ...) end
end
local function Tick(dt)
  dt = dt or 0.02
  CLOCK = CLOCK + dt
  for i = 1, #FRAMES do
    local f = FRAMES[i]
    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
  end
end
local function Run(seconds) for _ = 1, math.ceil(seconds / 0.02) do Tick(0.02) end end
local function Running()
  local n = 0
  for _, f in ipairs(FRAMES) do if f.shown and f.scripts.OnUpdate then n = n + 1 end end
  return n
end
c.hooksecurefunc = function(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local a, b, cc = orig(...); fn(...); return a, b, cc end
end

c.UIParent = Obj()
c.tinsert = table.insert
c.UISpecialFrames = {}
c.GameFontHighlightSmallOutline = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
c.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
local notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
local function lastNotice() return notices[#notices] or "" end
local TIP = { lines = {} }
c.GameTooltip = setmetatable({}, { __index = function(_, k)
  if k == "SetText" then return function(_, t) TIP.text = t; TIP.lines = {} end end
  if k == "AddLine" then return function(_, t) TIP.lines[#TIP.lines + 1] = t end end
  return function() end
end })
local function tipHas(p) for _, l in ipairs(TIP.lines) do if l:find(p) then return true end end return false end
ALT, SHIFT, CTRL = false, false, false
c.IsAltKeyDown = function() return ALT end
c.IsShiftKeyDown = function() return SHIFT end
c.IsControlKeyDown = function() return CTRL end
c.PlaySound = function() return true end
c.PlaySoundFile = function() return true end
c.SOUNDKIT = { MAP_PING = 3175 }
local COMBAT = false
c.InCombatLockdown = function() return COMBAT end
c.LE_PARTY_CATEGORY_HOME, c.LE_PARTY_CATEGORY_INSTANCE = 1, 2
c.IsInGroup = function() return false end
c.IsInRaid = function() return false end
c.C_ChatInfo.InChatMessagingLockdown = function() return false end
local INSTANCE = { "Elwynn Forest", "none", 0, "", 5, 0, false, 0 }
c.GetInstanceInfo = function() return unpack(INSTANCE) end
c.GetRealZoneText = function(id) return ({ [36] = "The Deadmines (game)" })[id] or "" end
c.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_SMOOTH, c.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL, c.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE = 1, 2, 3

---------------------------------------------------------------------------
-- The world: continents with yards (x north, y west) and a place on the world map; zones and a city in yards
---------------------------------------------------------------------------
c.Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local MAPS = {
  [947] = { name = "Azeroth", parent = 0, mapType = 1, art = 2141 },
  [1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2, cont = 0, xN = 4000, yW = 4000, W = 15000, H = 10000,
    world = { 0.55, 0.85, 0.2, 0.5 }, art = 2140 },
  [1414] = { name = "Kalimdor", parent = 947, mapType = 2, cont = 1, xN = 4000, yW = 4000, W = 15000, H = 10000,
    world = { 0.1, 0.4, 0.3, 0.6 }, art = 2142 },
  [1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3, cont = 0, xN = 0, yW = 0, W = 3000, H = 2000, art = 2153 },
  [1436] = { name = "Westfall", parent = 1415, mapType = 3, cont = 0, xN = 0, yW = 3000, W = 3000, H = 2000, art = 2165 },
  [1455] = { name = "Ironforge", parent = 1415, mapType = 3, cont = 0, xN = 2000, yW = 0, W = 1500, H = 1000, art = 2155 },
  [1413] = { name = "The Barrens", parent = 1414, mapType = 3, cont = 1, xN = 0, yW = 0, W = 3000, H = 2000, art = 2181 },
  [2521] = { name = "Zephras Isle", parent = 947, mapType = 3, cont = 2991, xN = 0, yW = 0, W = 3000, H = 2000, art = 2031, offWorld = true },
}
local function Cont(id) local m = MAPS[id]; return m.mapType == 2 and id or Cont(m.parent) end
local function YardsToMap(id, wx, wy) local m = MAPS[id]; return (m.yW - wy) / m.W, (m.xN - wx) / m.H end
local function MapToYards(id, x, y) local m = MAPS[id]; return m.xN - y * m.H, m.yW - x * m.W end
local function WorldRect(id)                     -- l, r, t, b on 947
  local m = MAPS[id]
  if id == 947 then return 0, 1, 0, 1 end
  if m.offWorld then return nil end
  if m.world then return unpack(m.world) end
  local cid = Cont(id)
  local cl, cr, ct, cb = unpack(MAPS[cid].world)
  local x0, y0 = YardsToMap(cid, m.xN, m.yW)
  local x1, y1 = YardsToMap(cid, m.xN - m.H, m.yW - m.W)
  return cl + x0 * (cr - cl), cl + x1 * (cr - cl), ct + y0 * (cb - ct), ct + y1 * (cb - ct)
end
local function WorldOf(id, x, y) local l, r, t, b = WorldRect(id); return l + x * (r - l), t + y * (b - t) end
local function Wx(id, x, y) return (WorldOf(id, x, y)) end
local function Wy(id, x, y) return select(2, WorldOf(id, x, y)) end
local function OnMap(id, u, v) local l, r, t, b = WorldRect(id); return (u - l) / (r - l), (v - t) / (b - t) end
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
local function Info(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.mapType } or nil end
local function ArtFiles(id) local t = {} for i = 1, 12 do t[i] = MAPS[id].art * 100 + i end return t end
local EXPLORED = {}   -- [mapID] = { list of explored pieces }
c.C_Map = {
  GetMapInfo = Info,
  GetWorldPosFromMapPos = function(id, v)
    local m = MAPS[id]
    if not (m and m.cont) then return nil end
    return m.cont, c.CreateVector2D(MapToYards(id, v.x, v.y))
  end,
  GetMapPosFromWorldPos = function(cont, w, id)
    local m = MAPS[id]
    if not (m and m.cont == cont) then return nil end
    return id, c.CreateVector2D(YardsToMap(id, w.x, w.y))
  end,
  GetMapRectOnMap = function(child, parent)
    if parent ~= 947 then return nil end
    return WorldRect(child)
  end,
  GetMapInfoAtPosition = function(id, x, y)
    if id == 947 then
      for kid, k in pairs(MAPS) do
        if k.mapType == 2 then
          local l, r, t, b = unpack(k.world)
          if x >= l and x <= r and y >= t and y <= b then return Info(kid) end
        end
      end
      return Info(947)
    end
    local m = MAPS[id]
    local wx, wy = MapToYards(id, x, y)
    for kid, k in pairs(MAPS) do
      if k.parent == id and k.cont == m.cont and kid ~= 1455 then
        local kx, ky = YardsToMap(kid, wx, wy)
        if kx >= 0 and kx <= 1 and ky >= 0 and ky <= 1 then return Info(kid) end
      end
    end
    return Info(id)
  end,
  GetMapChildrenInfo = function(id)
    local out = {}
    for kid, k in pairs(MAPS) do if k.parent == id then out[#out + 1] = Info(kid) end end
    table.sort(out, function(a, b) return a.mapID < b.mapID end)
    return out
  end,
  GetMapArtLayers = function(id) return MAPS[id] and { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end,
  GetMapArtLayerTextures = function(id) return MAPS[id] and ArtFiles(id) end,
  GetMapArtID = function(id) return MAPS[id] and MAPS[id].art end,
  SetUserWaypoint = function() return true end,
}
c.C_MapExplorationInfo = { GetExploredMapTextures = function(id) return EXPLORED[id] or {} end }
c.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }

---------------------------------------------------------------------------
-- The world map and its scroll container
---------------------------------------------------------------------------
local CW, CH = 1002, 668
local VIEW = { left = 100, top = 800, w = 1000, h = 666 }
c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end,
  OnShow = function() end, OnHide = function() end, OnMapChanged = function() end, RemoveAllData = function() end,
  RefreshAllData = function() end, OnCanvasScaleChanged = function() end, OnCanvasSizeChanged = function() end,
  OnCanvasPanChanged = function() end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end

local WMF, SC, CANVAS, CONTAINER = Obj(), Obj(), Obj(), Obj()
SC.Child = CANVAS
SC.mouseButtonInfo = { LeftButton = { down = false }, RightButton = { down = false } }
SC.mouseWheelZoomMode = 2
SC.st = { scale = 1, cx = 0.5, cy = 0.5 }
SC.cursor = { x = 0, y = 0 }
SC.calls = { instant = 0, clicks = 0, pans = 0 }
WMF.ScrollContainer = SC
WMF.NavBar = Obj()
WMF.mapID, WMF.providers, WMF.clicks = 1429, {}, {}
WMF.shown = false
CANVAS.level = 10
rawset(CANVAS, "GetWidth", function() return CW end)
rawset(CANVAS, "GetHeight", function() return CH end)
local function Fit() return math.min(VIEW.w / CW, VIEW.h / CH) end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
rawset(CANVAS, "GetLeft", function() local s = SC.st; return (VIEW.left + VIEW.w / 2 - s.cx * CW * s.scale) / s.scale end)
rawset(CANVAS, "GetTop", function() local s = SC.st; return (VIEW.top - VIEW.h / 2 + s.cy * CH * s.scale) / s.scale end)
rawset(SC, "GetWidth", function() return VIEW.w end)
rawset(SC, "GetHeight", function() return VIEW.h end)
rawset(SC, "GetLeft", function() return VIEW.left end)
rawset(SC, "GetTop", function() return VIEW.top end)
rawset(SC, "GetCanvasScale", function() return SC.st.scale end)
rawset(SC, "GetCurrentScrollX", function() return SC.st.cx end)
rawset(SC, "GetCurrentScrollY", function() return SC.st.cy end)
rawset(SC, "GetCursorPosition", function() return SC.cursor.x, SC.cursor.y end)
rawset(SC, "SetMouseWheelZoomMode", function(s, m) s.mouseWheelZoomMode = m end)
SC.CalculateScrollExtentsAtScale = function(self, scale)
  local hx = math.min((self:GetWidth() * 0.5 / scale) / CW, 0.5)
  local hy = math.min((self:GetHeight() * 0.5 / scale) / CH, 0.5)
  return hx, 1 - hx, hy, 1 - hy
end
SC.CalculateScrollExtents = function(self)
  self.x0, self.x1, self.y0, self.y1 = self:CalculateScrollExtentsAtScale(self.st.scale)
end
SC.CreateZoomLevels = function(self) self.baseScale = Fit(); self.zoomLevels = { { scale = Fit() }, { scale = Fit() * 2.14 } } end
local function Providers(method, ...) for p in pairs(WMF.providers) do if p[method] then p[method](p, ...) end end end
local function Sync() local s = SC.st; SC.currentScale, SC.targetScale = s.scale, s.scale; SC.currentScrollX, SC.targetScrollX = s.cx, s.cx; SC.currentScrollY, SC.targetScrollY = s.cy, s.cy end
SC.InstantPanAndZoom = function(s, scale, x, y, ignore)
  s.calls.instant = s.calls.instant + 1
  s.st.scale = scale
  local x0, x1, y0, y1 = s:CalculateScrollExtentsAtScale(scale)
  s.st.cx, s.st.cy = Clamp(x, x0, x1), Clamp(y, y0, y1)
  Sync()
  Providers("OnCanvasScaleChanged")
end
SC.ResetZoom = function(s) s:InstantPanAndZoom(s.zoomLevels[1].scale, 0.5, 0.5, true) end
rawset(SC, "NormalizeUIPosition", function(s, x, y)
  local sc = s.st.scale
  return Clamp((x / sc - CANVAS:GetLeft()) / CW, 0, 1), Clamp((CANVAS:GetTop() - y / sc) / CH, 0, 1)
end)
rawset(SC, "WouldCursorPositionBeClick", function(s, button, x, y)
  local i = s.mouseButtonInfo[button]
  if not (i and i.down) then return false end
  local dx, dy = x - i.startX, y - i.startY
  return dx * dx + dy * dy <= 20
end)
rawset(SC, "OnMouseDown", function(s, button)
  local i = s.mouseButtonInfo[button]
  if i then i.down = true; i.startX, i.startY = s.cursor.x, s.cursor.y end
end)
rawset(SC, "OnMouseUp", function(s, button)
  local i = s.mouseButtonInfo[button]
  local click = s:WouldCursorPositionBeClick(button, s.cursor.x, s.cursor.y)
  if click then
    s.calls.clicks = s.calls.clicks + 1
    WMF:ProcessCanvasClickHandlers(button, s:NormalizeUIPosition(s.cursor.x, s.cursor.y))
  elseif i and i.down then
    s.calls.pans = s.calls.pans + 1
  end
  if i then i.down = false end
end)
rawset(WMF, "GetMapID", function(s) return s.mapID end)
rawset(WMF, "IsShown", function(s) return s.shown end)
rawset(WMF, "GetCanvas", function() return CANVAS end)
rawset(WMF, "GetCanvasContainer", function() return CONTAINER end)
rawset(WMF, "GetCanvasScale", function() return SC.st.scale end)
rawset(WMF, "GetGlobalPinScale", function() return 1 end)
local LEVELS = { PIN_FRAME_LEVEL_MAP_EXPLORATION = 2003, PIN_FRAME_LEVEL_WAYPOINT_LOCATION = 2600 }
rawset(WMF, "GetPinFrameLevelsManager", function() return { GetValidFrameLevel = function(_, name) return LEVELS[name] or 2000 end } end)
rawset(WMF, "AddDataProvider", function(s, p) s.providers[p] = true; p:OnAdded(s) end)
rawset(WMF, "RemoveDataProvider", function(s, p) p:RemoveAllData(); s.providers[p] = nil; p:OnRemoved(s) end)
rawset(WMF, "AddCanvasClickHandler", function(s, fn, pr) s.clicks[fn] = pr end)
rawset(WMF, "RemoveCanvasClickHandler", function(s, fn) s.clicks[fn] = nil end)
rawset(WMF, "AddCursorHandler", function() end)
rawset(WMF, "RemoveCursorHandler", function() end)
rawset(WMF, "ProcessCanvasClickHandlers", function(s, button, x, y)
  local list = {}
  for fn, pr in pairs(s.clicks) do list[#list + 1] = { fn = fn, pr = pr } end
  table.sort(list, function(a, b) return a.pr > b.pr end)
  for _, h in ipairs(list) do if h.fn(s, button, x, y) then return true end end
  s.navigated = (s.navigated or 0) + 1   -- the game would go to the map under the click now
  return false
end)
rawset(WMF, "SetMapID", function(s, id)
  s.setCalls = (s.setCalls or 0) + 1
  if s.mapID == id then return end
  s.mapID = id
  SC.mapID = id
  SC:CreateZoomLevels()
  Providers("OnCanvasSizeChanged")
  SC:ResetZoom()
  Providers("OnMapChanged")
end)
c.WorldMapFrame = WMF
c.GetCursorPosition = function() return SC.cursor.x, SC.cursor.y end
local function openMap(id)
  WMF.mapID = id or WMF.mapID
  SC.mapID = WMF.mapID
  SC:CreateZoomLevels()
  SC:ResetZoom()
  WMF.shown = true
  Providers("OnShow")
  FlushTimers()
  Tick()
end
local function closeMap()
  WMF.shown = false
  Providers("OnHide")
  Tick()
end
local function wheel(delta)
  if SC.mouseWheelZoomMode ~= c.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE then SC.blizzardWheel = (SC.blizzardWheel or 0) + 1 end
  for _, h in ipairs(SC.hooks.OnMouseWheel or {}) do h(SC, delta) end
end
-- the pointer over world point (u, v) as the view is now
local function pointAt(u, v)
  local id = WMF.mapID
  local x, y = OnMap(id, u, v)
  local s = SC.st.scale
  SC.cursor.x = (x * CW + CANVAS:GetLeft()) * s
  SC.cursor.y = (CANVAS:GetTop() - y * CH) * s
end
local function press(button) SC:OnMouseDown(button or "LeftButton"); for _, h in ipairs(SC.hooks.OnMouseDown or {}) do h(SC, button) end end
local function release(button) SC:OnMouseUp(button or "LeftButton") end
local function click(button) press(button); release(button) end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-9) end
local function settle() Run(1.5) end   -- (still long enough for the map underneath to follow, and to check again after)

---------------------------------------------------------------------------
-- Synthetic places and pieces
---------------------------------------------------------------------------
local function Tiles(base) local t = {} for i = 1, 12 do t[i] = base + i end return t end
local function MinimapString()
  local out = {}
  for col = 32, 37 do for row = 32, 35 do out[#out + 1] = ("%d,%d,%d"):format(col, row, 900000 + col * 64 + row) end end
  return table.concat(out, " ")
end
local DATA = {
  build = "test",
  minimap = { [0] = MinimapString() },
  reveal = {
    [2153] = "200:150:100:100:5001 300:256:500:300:5002,5003",          -- Elwynn: two pieces (the second, two tiles wide)
    [2165] = "256:200:400:200:6001",                                   -- Westfall: one
    [2181] = "128:128:10:10:7001",                                     -- the Barrens: one
  },
  caves = {
    { 101, "Test Cave", 0, -600, 2200, -400, 2500, Tiles(10000), nil, nil, nil },
    { 102, "Deep Den", 0, -1200, -1300, -1000, -1000, Tiles(20000), 7, 1, "Upper Den" },
    { 103, "Deep Den", 0, -1250, -1350, -950, -950, Tiles(30000), 7, 2, "Lower Den" },
  },
  dungeons = {
    [36] = { name = "Deadmines", raid = false, entrance = { 0, -1000, 1500 },
      floors = { { 291, "The Deadmines", Tiles(40000) }, { 292, "Ironclad Cove", Tiles(50000) } } },
    [43] = { name = "Wailing Caverns", raid = false, entrance = { 1, -1000, -500 }, floors = {} },
  },
  docks = {
    [1] = { "North dock", "Northtown", 0, -1500, -2000 },
    [2] = { "South dock", "Southport", 1, -500, -1500 },
    [3] = { "Mid dock", "Midway", 0, -1800, 2800 },
    [4] = { "Isle dock", "Isleport", 2991, -1000, -1500 },
  },
  travel = { { "boat", 1, 2 }, { "boat", 2, 1 }, { "boat", 1, 3 }, { "boat", 3, 1 }, { "zeppelin", 2, 4 }, { "zeppelin", 4, 2 } },
}
EXPLORED[1429] = { { textureWidth = 200, textureHeight = 150, offsetX = 100, offsetY = 100, fileDataIDs = { 5001 } } }

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua", "pins/MapTools.lua",
  "nav/Prefs.lua", "nav/Data.lua", "nav/Route.lua", "nav/Journey.lua", "nav/Nav.lua", "nav/Paint.lua", "nav/MapTrail.lua",
  "map/Prefs.lua", "map/Data.lua", "map/ViewMath.lua", "map/World.lua", "map/View.lua", "map/Art.lua", "map/Detail.lua",
  "map/Controls.lua", "map/Caves.lua", "map/Places.lua", "map/DungeonView.lua", "diag/Diagnostics.lua", "diag/Map.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local VM, MXP, MW, MV, MA, MD, MC, MCV, MPL, DV = R.MapViewMath, R.MapExplorePrefs, R.MapWorld, R.MapView, R.MapArt,
  R.MapDetail, R.MapControls, R.MapCaves, R.MapPlaces, R.MapDungeonView
local PN, PM, T = R.Pins, R.PinsMap, R.MapTools
assert(R.MapExploreData and R.MapExploreData.reveal and R.MapExploreData.minimap, "the real data loads")
R.MapExploreData = DATA
local opened = {}
R.PinsEditor = { OpenNew = function(map, x, y, party, name) opened[#opened + 1] = { map = map, x = x, y = y, party = party, name = name } end,
  Close = function() end, IsOpen = function() return false end }
local menus = {}
R.PinsWindow = { OpenMenu = function(anchor, title, choices) menus[#menus + 1] = { anchor = anchor, title = title, choices = choices } end,
  OpenActions = function() end }
local function choice(menu, label) for _, ch in ipairs(menu.choices) do if ch.label == label then return ch end end end
local function tidy()
  ALT, SHIFT, CTRL, COMBAT = false, false, false, false
  notices, opened, menus = {}, {}, {}
  if T.Armed() then T.Cancel() end
  PM.Disarm()
end
local function view() return MV.View() end
local function markers()
  Tick()
  local out = {}
  for i = 1, MPL.Used() do local m = MPL.Marker(i); if m.shown then out[m.place.id] = m end end
  return out
end
-- zoom with the wheel at a world point until `zoom` is reached (smooth off: each notch at once)
local function zoomTo(u, v, zoom)
  for _ = 1, 80 do
    local _, _, z = view()
    if math.abs(math.log(z / zoom)) < 0.12 then break end
    pointAt(u, v)
    wheel(z < zoom and 1 or -1)
  end
  Tick()
end

---------------------------------------------------------------------------
-- 1. The view's arithmetic
---------------------------------------------------------------------------
do
  local x0, x1, y0 = VM.Extents(1000, 666, 1002, 668, 1)
  assert(near(x0, 1000 * 0.5 / 1002) and near(x1, 1 - x0) and near(y0, 666 * 0.5 / 668), "extents: the map covers the view")
  for _, case in ipairs({ { 1, 0.5, 0.5, 3, 0.2, 0.7 }, { 2.5, 0.31, 0.62, 1.2, 0.9, 0.1 }, { 4, 0.6, 0.4, 7.5, 0.55, 0.45 } }) do
    local s0, cx0, cy0, s1, ax, ay = unpack(case)
    local cx1, cy1 = VM.Anchored(s0, cx0, cy0, s1, ax, ay)
    assert(near((ax - cx0) * s0, (ax - cx1) * s1, 1e-9) and near((ay - cy0) * s0, (ay - cy1) * s1, 1e-9), "the anchor stays put")
  end
  for _, s in ipairs({ 0.5, 1, 2.75, 9 }) do
    local nx, ny = VM.ToNormalized(640, 410, 125.5, 900, s, 1002, 668)
    local sx, sy = VM.ToScreen(nx, ny, 125.5, 900, s, 1002, 668)
    assert(near(sx, 640, 1e-6) and near(sy, 410, 1e-6), "round trip at scale " .. s)
  end
  local f = VM.MapFrame(0, 0, 0, -3000, -2000, 0)
  assert(f and f.axisAligned, "north-up")
  local u, v = VM.ToMap(f, -500, -750)
  assert(near(u, 0.25) and near(v, 0.25), "world to map")
  assert(not VM.MapFrame(0, 0, -100, -3000, -2000, 50).axisAligned and VM.MapFrame(0, 0, 0, 0, 0, 0) == nil, "turned, or no area")
  for _, p in ipairs({ { 0, 0 }, { -1999, -2999 }, { 1234.5, -4321 } }) do
    local col, row = VM.TileAt(p[1], p[2])
    local n, w, s, e = VM.TileRect(col, row)
    assert(p[1] <= n and p[1] > s and p[2] <= w and p[2] > e, "a point lies in its tile")
  end
  assert(VM.Fade(1, 2, 3) == 0 and VM.Fade(4, 2, 3) == 1 and near(VM.Fade(2.5, 2, 3), 0.5), "fades")
  assert(VM.Overlaps({ 0, 0, 10, 10 }, { 5, 5, 15, 15 }) and not VM.Overlaps({ 0, 0, 10, 10 }, { 10, 0, 20, 10 }), "label boxes")
  print("1 arithmetic ok")
end

---------------------------------------------------------------------------
-- 2. The world's geometry (from the game's own map rectangles)
---------------------------------------------------------------------------
do
  local l, r, t, b = MW.Rect(1429)
  local el, er, et, eb = WorldRect(1429)
  assert(near(l, el) and near(r, er) and near(t, et) and near(b, eb), "a zone's rectangle on the world")
  assert(MW.Stitchable(947) and MW.Stitchable(1415) and MW.Stitchable(1429) and MW.Stitchable(1455), "the world, continents, zones, cities")
  assert(not MW.Stitchable(2521), "an island the world map doesn't place isn't stitched")
  local u, v = MW.ToWorld(1429, 0.3, 0.7)
  local x, y = MW.FromWorld(1429, u, v)
  assert(near(x, 0.3) and near(y, 0.7), "map to world and back")
  local cu, cv = WorldOf(1436, 0.5, 0.5)
  local chain = MW.ChainAt(cu, cv)
  assert(chain[1] == 947 and chain[2] == 1415 and chain[3] == 1436, "the maps under a point: " .. table.concat(chain, ","))
  print("2 geometry ok")
end

---------------------------------------------------------------------------
-- 3. Off by default, on and off, OpenMap
---------------------------------------------------------------------------
local origExtents = SC.CalculateScrollExtentsAtScale
do
  assert(R.DEFAULT_MODULES.mapExplore == false and not R:Enabled("mapExplore"), "off for a new install")
  openMap(1429)
  wheel(1)
  assert(SC.blizzardWheel == 1 and not MV.Installed() and not MA.Built(), "off: the game's own map, nothing of ours")
  R:SetEnabled("mapExplore", true)
  assert(MV.Installed() and MV.Active() and MA.Built(), "on: the stitched map comes up on the open map")
  assert(SC.CalculateScrollExtentsAtScale ~= origExtents and SC.mouseWheelZoomMode == c.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE, "its limits and wheel")
  assert(SC.baseScale == 0, "panning allowed at every zoom")
  local _, _, z = view()
  assert(near(z, MV.FitZoom(1429), 1e-9), "showing the map the game opened, whole")
  R:SetEnabled("mapExplore", false)
  assert(SC.CalculateScrollExtentsAtScale == origExtents and SC.mouseWheelZoomMode == 2 and SC.baseScale == Fit(), "off: all put back")
  assert(not MA.Root().shown, "the painting hidden")
  c.LOADED.OpenMap = true
  R:SetEnabled("mapExplore", true)
  assert(not MV.Installed() and MV.Blocker() == "OpenMap", "stays off while OpenMap is loaded")
  c.LOADED.OpenMap = nil
  MV.Refresh()
  assert(MV.Installed(), "on once it isn't")
  assert(#(SC.hooks.OnMouseWheel or {}) == 1, "hooked once")
  print("3 switch ok")
end

---------------------------------------------------------------------------
-- 4. Seamless zoom; the map underneath follows; combat
---------------------------------------------------------------------------
do
  tidy()
  MXP.Set("smooth", false)
  closeMap(); openMap(1429)
  local u0, v0 = WorldOf(1429, 0.4, 0.6)
  -- zoom out at a point: it stays under the pointer, and the map isn't changed while you zoom
  local calls = WMF.setCalls or 0
  pointAt(u0, v0)
  for _ = 1, 3 do
    wheel(-1)
    local u, v = MV.CursorWorld()
    assert(near(u, u0, 1e-9) and near(v, v0, 1e-9), "the point under the pointer stays")
  end
  assert((WMF.setCalls or 0) == calls, "no map change mid-zoom")
  -- all the way out: the whole world
  for _ = 1, 30 do pointAt(u0, v0) wheel(-1) end
  local u, v, z = view()
  assert(near(z, 1, 1e-9) and near(u, 0.5) and near(v, 0.5), "the whole world, centred")
  settle()
  assert(WMF.mapID == 947, "still: the map underneath is the world's")
  local wu, wv = MV.View()
  assert(near(wu, 0.5) and near(wv, 0.5), "and the view didn't move")
  -- in on Westfall: past the continent, into the zone, never a jump
  local tu, tv = WorldOf(1436, 0.5, 0.5)
  zoomTo(tu, tv, MV.FitZoom(1415) * 1.2)
  settle()
  assert(WMF.mapID == 1415, "the continent underneath")
  zoomTo(tu, tv, MV.FitZoom(1436))
  local bu, bv, bz = view()
  settle()
  local au, av, az = view()
  assert(WMF.mapID == 1436, "then the zone")
  assert(near(au, bu, 1e-9) and near(av, bv, 1e-9) and near(az, bz, 1e-9), "the switch keeps the view exactly")
  -- eased: anchored on every frame; nothing runs once still
  MXP.Set("smooth", true)
  pointAt(tu + 0.01, tv)
  local au0, av0 = MV.CursorWorld()
  wheel(1)
  assert(MV.Animating(), "an ease under way")
  local steps = 0
  while MV.Animating() and steps < 100 do
    Tick()
    steps = steps + 1
    local cu, cv = MV.CursorWorld()
    assert(near(cu, au0, 1e-9) and near(cv, av0, 1e-9), "anchored on every frame")
  end
  assert(steps > 1 and steps < 20, "short")
  settle()
  assert(Running() == 0, "nothing runs once still")
  MXP.Set("smooth", false)
  -- the deepest zoom
  for _ = 1, 60 do pointAt(tu, tv) wheel(1) end
  local _, _, deep = view()
  assert(near(deep, MXP.Get("maxZoom"), 1e-6), "stops at the deepest zoom: " .. deep)
  -- in combat the map underneath waits, then follows
  for _ = 1, 60 do pointAt(tu, tv) wheel(-1) end
  COMBAT = true
  settle()
  assert(WMF.mapID == 1436 and MV.Snapshot().waits > 0, "in combat: the map underneath waits")
  COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  settle()
  assert(WMF.mapID == 947, "after combat it follows")
  print("4 seamless ok")
end

---------------------------------------------------------------------------
-- 5. Panning across a zone's edge; clicks in and out
---------------------------------------------------------------------------
do
  tidy()
  closeMap(); openMap(1429)
  -- the view can go anywhere on the world, whatever the map underneath
  local wu, wv = WorldOf(1436, 0.5, 0.5)
  MV.GlideTo(wu, wv, MV.FitZoom(1436))
  local u, v = view()
  assert(near(u, wu, 1e-9) and near(v, wv, 1e-9) and WMF.mapID == 1429, "past Elwynn's edge with Elwynn underneath")
  settle()
  assert(WMF.mapID == 1436, "then Westfall underneath")
  -- right-click: out to the continent; again: the world
  pointAt(wu, wv)
  click("RightButton")
  local _, _, z = view()
  assert(near(z, MV.FitZoom(1415), 1e-9), "out to the continent")
  pointAt(wu, wv)
  click("RightButton")
  _, _, z = view()
  assert(near(z, 1, 1e-9) and (WMF.navigated or 0) == 0, "out to the world, never the game's jump")
  -- left-click: in, one map at a time
  pointAt(wu, wv)
  click("LeftButton")
  _, _, z = view()
  assert(near(z, MV.FitZoom(1415), 1e-9), "in to the continent")
  pointAt(wu, wv)
  click("LeftButton")
  _, _, z = view()
  assert(near(z, MV.FitZoom(1436), 1e-9), "in to the zone under the pointer")
  -- a drag is a pan, never a click
  local before = { view() }
  press()
  SC.cursor.x = SC.cursor.x + 40
  release()
  local after = { view() }
  assert(near(before[3], after[3]) and SC.calls.pans > 0, "a drag doesn't zoom")
  print("5 panning and clicks ok")
end

---------------------------------------------------------------------------
-- 6. TwichUI's pins and pings across edges; drags and clicks
---------------------------------------------------------------------------
do
  tidy()
  closeMap(); openMap(1429)
  MV.GlideTo(Wx(1429, 0.0, 0.5), Wy(1429, 0.0, 0.5), MV.FitZoom(1429) * 1.5)   -- on Elwynn's west edge, Westfall beside it
  Tick()
  assert(WMF.mapID == 1429, "Elwynn underneath")
  -- a pin placed past the edge is placed on Westfall, at the spot
  PM.Arm()
  local wu, wv = WorldOf(1436, 0.9, 0.5)
  pointAt(wu, wv)
  click()
  assert(#opened == 1 and opened[1].map == 1436, "on the map drawn there: " .. tostring(opened[1] and opened[1].map))
  assert(math.abs(opened[1].x - PN.Quantize(0.9)) <= 1 and math.abs(opened[1].y - PN.Quantize(0.5)) <= 1, "at the spot")
  -- and inside Elwynn, on Elwynn
  opened = {}
  PM.Arm()
  local eu, ev = WorldOf(1429, 0.1, 0.4)
  pointAt(eu, ev)
  click()
  assert(#opened == 1 and opened[1].map == 1429 and math.abs(opened[1].x - PN.Quantize(0.1)) <= 1, "Elwynn's own")
  -- a pin on Westfall is drawn while Elwynn is underneath, at its place (past Elwynn's edge)
  local pin = PN.AddLocal({ map = 1436, x = 9000, y = 5000, name = "Camp" })
  PM.Layout()
  local b
  for _, f in ipairs(FRAMES) do if f.entry and f.entry.pin == pin then b = f end end
  assert(b and b.shown, "drawn")
  local px, py = OnMap(1429, WorldOf(1436, 0.9, 0.5))
  local s = b.scale
  assert(px < 0 and near(b.point[4] * s, CW * px, 1e-6) and near(-b.point[5] * s, CH * py, 1e-6), "at its place, past the edge")
  -- a drag that starts on the pin pans and doesn't select it
  PN.Select(nil)
  pointAt(WorldOf(1436, 0.9, 0.5))
  Fire(b, "OnMouseDown", "LeftButton")
  SC.cursor.x = SC.cursor.x + 40
  Fire(b, "OnMouseUp", "LeftButton")
  Fire(b, "OnClick", "LeftButton")
  assert(PN.selected == nil, "a drag isn't a click on a pin")
  Fire(b, "OnMouseDown", "LeftButton")
  Fire(b, "OnMouseUp", "LeftButton")
  Fire(b, "OnClick", "LeftButton")
  assert(PN.selected ~= nil, "a click selects it")
  PN.Select(nil)
  -- pings: the same place a click makes, the same placement as pins
  local map, x = PM.ClickPlace(0.5, 0.5)
  assert(map == 1436 or map == 1429, "pings resolve the click as pins do")
  print("6 pins ok")
end

---------------------------------------------------------------------------
-- 7. The stitched painting
---------------------------------------------------------------------------
do
  tidy()
  local a = MA.Snapshot()
  assert(a.built and a.zones == 3 and a.cities == 1, "Elwynn, Westfall, the Barrens as zones; Ironforge (no pieces) as a city: " .. a.zones .. "," .. a.cities)
  local root = MA.Root()
  assert(root.level == CANVAS.level + MA.LEVEL.world and root.level < LEVELS.PIN_FRAME_LEVEL_MAP_EXPLORATION, "over the art, under the pins")
  -- laid out for the map underneath: world pixels to its canvas
  local l, r, t = MW.Rect(WMF.mapID)
  local k = 1002 / ((r - l) * 1002)
  assert(near(root.scale, k, 1e-9) and near(root.point[4], -l * 1002, 1e-6) and near(root.point[5], t * 668, 1e-6), "the root on the map underneath")
  -- zones come in as you zoom; textures only near the view
  MV.GlideTo(0.5, 0.5, 1)
  Tick()
  assert(MA.Snapshot().shown == 0, "the whole world: no zone pieces")
  MV.GlideTo(Wx(1429, 0.5, 0.5), Wy(1429, 0.5, 0.5), MV.FitZoom(1429))
  Tick()
  local z = MA.Zone(1429)
  assert(z.built and z.shown and z.loaded, "Elwynn's pieces in view")
  assert(not MA.Zone(1413).built, "the Barrens (another continent) not even made")
  -- Elwynn: one explored piece (from the game) and one not (from the data), the second two tiles wide
  local explored, unexplored, files = 0, 0, {}
  for _, e in ipairs(z.tex) do
    files[#files + 1] = e.tex.tex
    if e.piece.explored then explored = explored + 1 else unexplored = unexplored + 1 end
    assert(#e.tex.masks == 1, "each with the zone's soft edge")
  end
  assert(explored == 1 and unexplored == 2, "pieces: " .. explored .. "/" .. unexplored)
  -- the second tile of a 300-wide piece is a 64-wide file: cut to its 44 pixels
  for _, e in ipairs(z.tex) do
    if e.tex.tex == 5003 then assert(near(e.tex.coord[2], 44 / 64), "the last column cut to the piece") end
  end
  -- unexplored dimmed by default; shown; hidden
  local dim
  for _, e in ipairs(z.tex) do if not e.piece.explored then dim = e.tex end end
  assert(dim.color[1] < 1 and dim.shown, "dimmed")
  MXP.Set("unexplored", "hide")
  assert(not dim.shown, "hidden")
  MXP.Set("unexplored", "show")
  assert(dim.shown and dim.color[1] == 1, "shown")
  MXP.Set("unexplored", "dim")
  -- exploring: the game says so, the piece brightens
  EXPLORED[1429][2] = { textureWidth = 300, textureHeight = 256, offsetX = 500, offsetY = 300, fileDataIDs = { 5002, 5003 } }
  c.FireEvent("MAP_EXPLORATION_UPDATED")
  assert(dim.color[1] == 1, "explored now: full")
  -- the continents' painting with a wide soft edge; cities with a round one
  local city = MA.City(1455)
  assert(city and #city.tex == 12 and city.tex[1].masks[1].tex:find("round"), "a city's own map, round-feathered")
  print("7 painting ok")
end

---------------------------------------------------------------------------
-- 8. Terrain detail
---------------------------------------------------------------------------
do
  tidy()
  MV.GlideTo(Wx(1429, 0.5, 0.5), Wy(1429, 0.5, 0.5), MV.FitZoom(1429))
  Tick()
  assert(not MD.Showing(), "a zone whole: the painting alone")
  zoomTo(Wx(1429, 0.3, 0.4), Wy(1429, 0.3, 0.4), 40)
  local snap = MD.Snapshot()
  assert(MD.Showing() and snap.tiles > 0 and snap.tiles <= 80, "close in: detail, bounded: " .. snap.tiles)
  -- each tile the game's own texture, on its world rectangle
  local checked = 0
  for col = 32, 37 do
    for row = 32, 35 do
      local tex = MD.TextureFor(0, col, row)
      if tex then
        assert(tex.tex == 900000 + col * 64 + row, "the tile's own picture")
        local n, w, s, e = VM.TileRect(col, row)
        local ua, va = MW.FromYards(0, n, w)
        local ub, vb = MW.FromYards(0, s, e)
        assert(near(tex.point[4], ua * 1002, 1e-6) and near(-tex.point[5], va * 668, 1e-6) and near(tex.width, (ub - ua) * 1002, 1e-6), "on its world rectangle")
        checked = checked + 1
      end
    end
  end
  assert(checked == snap.tiles, "every tile shown checked")
  MXP.Set("detail", false)
  Tick()
  assert(not MD.Showing(), "off: cleared")
  MXP.Set("detail", true)
  print("8 detail ok")
end

---------------------------------------------------------------------------
-- 9. Caves
---------------------------------------------------------------------------
do
  tidy()
  local g = MCV.Get("cave:101")
  assert(g, "Test Cave on the world")
  local cu, cv = (g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2
  MV.GlideTo(cu, cv, MV.FitZoom(1436))
  Tick()
  assert(not MCV.Surfaced(), "zone level: not yet")
  -- zooming onto it: it surfaces, at its place; the deepest zoom reaches as far as its map needs
  for _ = 1, 80 do pointAt(cu, cv) wheel(1) end
  Tick()
  local _, _, z = view()
  assert(z > MXP.Get("maxZoom") and MCV.Surfaced(), "surfaced, past the usual deepest zoom: " .. z)
  local t1, t12 = MCV.Tile(1), MCV.Tile(12)
  assert(t1.tex == 10001 and t12.tex == 10012 and t1.shown, "its own textures")
  assert(near(t1.point[4], g.u0 * 1002, 1e-6) and near(-t1.point[5], g.v0 * 668, 1e-6), "its top left on the cave's corner")
  assert(near(t12.point[4] + t12.width, g.u1 * 1002, 1e-6) and near(-t12.point[5] + t12.height, g.v1 * 668, 1e-6), "its bottom right on the other")
  assert(MCV.Veil().alpha > 0.5, "the land round it dimmed")
  assert(R.MapControls.ContextShown(), "the bar names it")
  assert(not MD.Showing(), "no terrain detail over it")
  -- a pin placed here is on the zone at the spot
  PM.Arm()
  pointAt(cu, cv)
  click()
  local x, y = OnMap(1436, cu, cv)
  assert(#opened == 1 and opened[1].map == 1436 and math.abs(opened[1].x - PN.Quantize(x)) <= 1, "on the zone, at the spot")
  -- zooming out: it sinks, its textures let go
  for _ = 1, 15 do pointAt(cu, cv) wheel(-1) end
  Tick()
  assert(not MCV.Surfaced() and MCV.Tile(1).tex == nil and not R.MapControls.ContextShown(), "sunk")
  -- a cave of two floors: its first, then the other from the bar
  local d = MCV.Get("cave:102")
  for _ = 1, 80 do pointAt((d.u0 + d.u1) / 2, (d.v0 + d.v1) / 2) wheel(1) end
  Tick()
  assert(MCV.Surfaced() and MCV.Tile(1).tex == 20001, "the first floor")
  MCV.SetFloor(2)
  assert(MCV.Tile(1).tex == 30001, "the second")
  local fl = d.floors[2]
  assert(near(MCV.Tile(1).point[4], fl.u0 * 1002, 1e-6), "over its own rectangle")
  MXP.Set("caves", false)
  Tick()
  assert(not MCV.Surfaced(), "caves off: none")
  MXP.Set("caves", true)
  print("9 caves ok")
end

---------------------------------------------------------------------------
-- 10. Places and travel
---------------------------------------------------------------------------
do
  tidy()
  closeMap(); openMap(1436)
  local m = markers()
  assert(m["dungeon:36"] and m["dock:3"] and m["cave:101"], "Westfall whole: the entrance, the dock and the cave")
  MV.GlideTo(0.5, 0.5, 4)
  m = markers()
  assert(not m["cave:101"] and (m["dungeon:36"] or m["dock:3"]), "a continent's worth: entrances and docks, caves wait")
  MV.GlideTo(Wx(1436, 0.5, 0.5), Wy(1436, 0.5, 0.5), MV.FitZoom(1436))
  m = markers()
  assert(m["dungeon:36"].parent.level > LEVELS.PIN_FRAME_LEVEL_WAYPOINT_LOCATION, "over TwichUI's pins")
  -- anchored in the painting: the marker hangs from its spot
  local a = m["dungeon:36"].anchor
  local du, dv = MW.FromYards(0, -1000, 1500)
  assert(near(a.point[4], du * 1002, 1e-6) and near(-a.point[5], dv * 668, 1e-6) and m["dungeon:36"].point[2] == a, "at its world spot")
  -- a dock: the map glides to the other end; Back returns
  local before = { view() }
  Fire(m["dock:3"], "OnClick", "LeftButton")
  local nu, nv = MW.FromYards(0, -1500, -2000)
  local u, v = view()
  assert(near(u, nu, 1e-9) and near(v, nv, 1e-9) and MV.Peek().tag == "travel", "at the other end, the view before remembered")
  settle()
  assert(WMF.mapID == 1429, "and the map underneath follows to Elwynn")
  assert(markers()["dock:1"].glow.shown, "the other end picked out")
  MC.Back()
  local bu, bv, bz = view()
  assert(near(bu, before[1], 1e-9) and near(bz, before[3], 1e-9), "Back")
  -- two ends: the choice, one on another continent, glided to on the same map
  closeMap(); openMap(1429)
  Fire(markers()["dock:1"], "OnClick", "LeftButton")
  assert(#menus == 1 and choice(menus[1], "Go to Southport") and choice(menus[1], "Go to Midway"), "both ends offered")
  choice(menus[1], "Go to Southport").run()
  local su, sv = MW.FromYards(1, -500, -1500)
  u, v = view()
  assert(near(u, su, 1e-9) and near(v, sv, 1e-9), "across the sea, on the same map")
  settle()
  assert(WMF.mapID == 1413, "the Barrens underneath")
  -- an end off the world map: its own map, by the game
  Fire(markers()["dock:2"], "OnClick", "LeftButton")
  choice(menus[#menus], "Go to Isleport").run()
  assert(WMF.mapID == 2521 and not MV.Active(), "Zephras Isle's own map (not part of the world)")
  assert(not markers()["dock:2"], "no places there")
  -- a cave: the map glides onto it and it surfaces
  closeMap(); openMap(1436)
  local cu, cv = MCV.Get("cave:101").u0, MCV.Get("cave:101").v0
  zoomTo(cu, cv, 12)
  Fire(markers()["cave:101"], "OnClick", "LeftButton")
  Tick()
  assert(MCV.Surfaced(), "looked inside")
  -- names: from 7 times, never overlapping; categories
  closeMap(); openMap(1436)
  zoomTo(du, dv, 9)
  m = markers()
  assert(m["dungeon:36"].label.shown and m["dungeon:36"].label.text == "The Deadmines (game)", "the game's own name")
  MXP.Set("dungeons", false)
  assert(not markers()["dungeon:36"], "dungeons off")
  MXP.Set("dungeons", true)
  -- Alt-click on a place: the pin shortcut, at the place
  ALT = true
  pointAt(du, dv)
  Fire(markers()["dungeon:36"], "OnClick", "LeftButton")
  ALT = false
  assert(#opened == 1 and opened[1].map == 1436, "Alt-click makes a pin there")
  -- Pin this place, once
  opened = {}
  Fire(markers()["dungeon:36"], "OnClick", "RightButton")
  choice(menus[#menus], "Pin this place").run()
  assert(#opened == 1 and opened[1].name == "The Deadmines (game)", "named for the place")
  PN.AddLocal({ map = opened[1].map, x = opened[1].x, y = opened[1].y, name = opened[1].name })
  opened = {}
  choice(menus[#menus], "Pin this place").run()
  assert(#opened == 0 and lastNotice():find("Already in your pins"), "never twice")
  Fire(markers()["dungeon:36"], "OnEnter")
  assert(tipHas("Click to see its map") and tipHas("Right%-click"), "tooltips say what a click does")
  print("10 places ok")
end

---------------------------------------------------------------------------
-- 11. Dungeon maps
---------------------------------------------------------------------------
do
  tidy()
  closeMap(); openMap(1436)
  T.Arm("pin")
  Fire(markers()["dungeon:36"], "OnClick", "LeftButton")
  assert(DV.IsOpen() and DV.Tile(1).tex == 40001 and T.Armed() == "pin", "its map; an armed tool stays armed")
  assert(MPL.Used() == 0, "the world's places step aside")
  local viewFrame = DV.Frame()
  viewFrame.width, viewFrame.height = VIEW.w, VIEW.h
  Fire(viewFrame, "OnMouseDown", "LeftButton")
  Fire(viewFrame, "OnMouseUp", "LeftButton")
  assert(#opened == 0 and lastNotice():find("can't be placed on a dungeon"), "no pins on it")
  T.Cancel()
  DV.SetFloor(2)
  assert(DV.Tile(1).tex == 50001, "the second floor")
  Fire(viewFrame, "OnMouseDown", "RightButton")
  Fire(viewFrame, "OnMouseUp", "RightButton")
  assert(not DV.IsOpen() and DV.Tile(1).tex == nil, "closed, textures let go")
  INSTANCE = { "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
  MC.Update()
  local inside
  for _, f in ipairs(FRAMES) do if f.kind == "Button" and f.text and f.text.text == "Inside" then inside = f end end
  assert(inside and inside.shown, "the Inside button while in it")
  INSTANCE = { "Elwynn Forest", "none", 0, "", 5, 0, false, 0 }
  print("11 dungeons ok")
end

---------------------------------------------------------------------------
-- 12. Turning it off
---------------------------------------------------------------------------
do
  tidy()
  closeMap(); openMap(1436)
  local g = MCV.Get("cave:101")
  for _ = 1, 80 do pointAt((g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2) wheel(1) end
  Tick()
  assert(MCV.Surfaced(), "deep in a cave")
  R:SetEnabled("mapExplore", false)
  Tick()
  assert(not MV.Installed() and not MCV.Surfaced() and not DV.IsOpen() and not MA.Root().shown, "everything taken off")
  assert(near(SC.st.scale, Fit(), 1e-9) and SC.CalculateScrollExtentsAtScale == origExtents and SC.mouseWheelZoomMode == 2, "the map whole, its limits and wheel back")
  assert(MPL.Used() == 0 and not R.MapControls.ContextShown() and Running() == 0, "no places, no bar, nothing running")
  opened = {}
  PM.Arm()
  SC.cursor.x, SC.cursor.y = 600, 470
  click()
  assert(#opened == 1 and opened[1].map == WMF.mapID, "pins as before")
  R:SetEnabled("mapExplore", true)
  print("12 off ok")
end

---------------------------------------------------------------------------
-- 13. No idle work; bounded growth over a lot of exploring
---------------------------------------------------------------------------
do
  tidy()
  MXP.Set("smooth", true)
  closeMap(); openMap(1429)
  for i = 1, 40 do
    local u, v = math.random() * 0.8 + 0.1, math.random() * 0.6 + 0.2
    for _ = 1, 4 do pointAt(u, v) wheel(math.random() < 0.6 and 1 or -1) end
    Run(0.3)
    if i % 9 == 0 then settle() closeMap() openMap(({ 1429, 1436, 1413 })[i % 3 + 1]) end
  end
  settle()
  assert(Running() == 0, "still: nothing runs per frame")
  assert(MPL.Snapshot().pool <= 8, "markers reused: " .. MPL.Snapshot().pool)
  assert(MD.Snapshot().made <= 81, "detail textures bounded")
  assert(MV.Snapshot().back <= 12, "the way back bounded")
  local a = MA.Snapshot()
  assert(a.zonesBuilt <= 3 and a.loaded <= 16, "each zone's painting made once, files bounded")
  MXP.Set("smooth", false)
  print("13 bounded ok")
end

---------------------------------------------------------------------------
-- 14. Preferences
---------------------------------------------------------------------------
do
  assert(not MXP.Set("maxZoom", 8) and not MXP.Set("maxZoom", 200) and not MXP.Set("unexplored", "reveal"), "refuses out of range")
  assert(MXP.Set("maxZoom", 96) and MXP.Get("maxZoom") == 96, "keeps a valid one")
  c.TwichUIDB.ui.mapExplore.wheelStep = "fast"
  assert(MXP.Get("wheelStep") == 25, "an unusable saved value reads as the default")
  MXP.Set("caves", false)
  MXP.Reset("behavior")
  assert(MXP.Get("maxZoom") == 48 and MXP.Get("caves") == false, "a reset puts back only its own")
  MXP.Reset("all")
  for k in pairs(MXP.DEFAULTS) do
    local found
    for _, g in pairs(MXP.GROUPS) do for _, key in ipairs(g) do if key == k then found = true end end end
    assert(found, k .. " is in a reset scope (and so in the shared configuration)")
  end
  print("14 prefs ok")
end

---------------------------------------------------------------------------
-- 15. The troubleshooting report: counts and words, no names
---------------------------------------------------------------------------
do
  local text = R.Diag.Build()
  assert(text:find("World map exploration") and text:find("painting:") and text:find("caves:"), "its section is in the report")
  for _, word in ipairs({ "Deadmines", "Westfall", "Elwynn", "Northtown", "Test Cave" }) do
    assert(not text:find(word, 1, true), "no names in the report: " .. word)
  end
  print("15 report ok")
end

print("MAP EXPLORE PASSED")
