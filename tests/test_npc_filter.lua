-- The NPC filter on the map tools bar: pins/MapTools.lua's funnel button, npcs/FilterMenu.lua's menu, npcs/Prefs.lua's shared
-- choices (and SetAllShown), and npcs/Map.lua drawing from them. The game's frames, maps and clock are mocks (as in
-- test_npc_search.lua), so this shows TwichUI's own bookkeeping: what is checked, what is drawn, what opens and closes, what
-- is saved. How the funnel looks, where the menu sits and how it feels are for the game (docs/map-tools.md lists the checks).
--   1  the icon file         2  the button           3  the menu is made when asked   4  one kind off, the rest stay
--   5  several roles         6  one set of choices   7  show all and hide all         8  search and picking out
--   9  closing               10 reopening            11 room                          12 going off
dofile(TESTS .. "harness.lua")
CLOCK = 1000

local SELF = "Rich Hale"
local c = MakeClient(SELF, { "!!!TwichUI" })
CLIENTS[SELF] = c
c.GetTime = function() return CLOCK end

---------------------------------------------------------------------------
-- Mocks
---------------------------------------------------------------------------
local function Obj()
  local o = { text = "", shown = true }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetStringHeight" then return function() return 12 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "CreateFontString" then
      return function(_, _, _, template)
        local fs = Obj()
        fs.template = template
        rawset(fs, "SetFont", function() end)
        rawset(fs, "SetTextColor", function(s, r, g, b) s.color = { r, g, b } end)
        rawset(fs, "SetWidth", function(s, w) s.width = w end)
        return fs
      end
    end
    if k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end
local realCreate = c.CreateFrame
local FRAMES, FSLIST = {}, {}
local LIST_OVER, MENU_OVER = false, false
c.CreateFrame = function(kind, name, parent, template)
  local o = Obj()
  rawset(o, "kindOf", kind)
  FRAMES[#FRAMES + 1] = o
  local base = realCreate()
  for k, v in pairs(base) do
    if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end
  end
  rawset(o, "SetPoint", function(s, ...) s.lastPoint = { ... } end)
  rawset(o, "SetScale", function(s, v) s.scale = v end)
  rawset(o, "SetAlpha", function(s, v) s.alpha = v end)
  rawset(o, "SetWidth", function(s, v) s.width = v end)
  rawset(o, "SetHeight", function(s, v) s.height = v end)
  rawset(o, "SetSize", function(s, w, h) s.width, s.height = w, h end)
  rawset(o, "SetFrameLevel", function(s, v) s.frameLevel = v end)
  rawset(o, "EnableMouse", function(s, v) s.mouse = v and true or false end)
  rawset(o, "EnableKeyboard", function(s, v) s.keyboard = v and true or false end)
  rawset(o, "IsKeyboardEnabled", function(s) return s.keyboard == true end)
  rawset(o, "SetPropagateKeyboardInput", function() end)
  rawset(o, "GetWidth", function(s) return s.width or 100 end)
  rawset(o, "GetHeight", function(s) return s.height or 20 end)
  rawset(o, "GetParent", function(s) return s.parent end)
  rawset(o, "SetParent", function(s, p) s.parent = p end)
  rawset(o, "parent", parent)
  local makeFS = o.CreateFontString
  rawset(o, "CreateFontString", function(s, ...) local fs = makeFS(s, ...); FSLIST[#FSLIST + 1] = fs; return fs end)
  rawset(o, "CreateTexture", function()
    local t = Obj()
    -- the game's textures have no text methods: calling one is an error there, so it is one here
    local base = getmetatable(t).__index
    getmetatable(t).__index = function(tt, k)
      if k == "SetTextColor" or k == "SetText" or k == "SetFont" or k == "SetJustifyH" or k == "SetWordWrap" or k == "SetScript" then return nil end
      return base(tt, k)
    end
    rawset(t, "SetTexture", function(s, p) s.tex = p end)
    rawset(t, "SetAlpha", function(s, v) s.alpha = v end)
    rawset(t, "SetSize", function(s, w, h) s.width, s.height = w, h end)
    return t
  end)
  if kind == "EditBox" then
    rawset(o, "focused", false)
    rawset(o, "HasFocus", function(s) return s.focused end)
    rawset(o, "SetFocus", function(s)
      if s.focused then return end
      s.focused = true
      if s.scripts.OnEditFocusGained then s.scripts.OnEditFocusGained(s) end
    end)
    rawset(o, "ClearFocus", function(s)
      if not s.focused then return end
      s.focused = false
      if s.scripts.OnEditFocusLost then s.scripts.OnEditFocusLost(s) end
    end)
    rawset(o, "SetText", function(s, v)   -- set by code: the box says it wasn't typed
      s.text = v or ""
      if s.scripts.OnTextChanged then s.scripts.OnTextChanged(s, false) end
    end)
  end
  if name == "TwichUIMapSearch" then rawset(o, "IsMouseOver", function() return LIST_OVER end) end
  if name == "TwichUINpcFilter" then rawset(o, "IsMouseOver", function() return MENU_OVER end) end
  if template == "UIPanelScrollFrameTemplate" then
    local bar = Obj()
    rawset(bar, "ThumbTexture", Obj())
    rawset(bar, "ScrollUpButton", Obj()); rawset(bar, "ScrollDownButton", Obj())
    rawset(o, "ScrollBar", bar)
  end
  -- the game runs a frame's OnShow and OnHide when it changes (the plain mock only sets the flag)
  rawset(o, "Show", function(s) local was = s.shown; s.shown = true; if not was and s.scripts.OnShow then s.scripts.OnShow(s) end end)
  rawset(o, "Hide", function(s) local was = s.shown; s.shown = false; if was and s.scripts.OnHide then s.scripts.OnHide(s) end end)
  rawset(o, "SetShown", function(s, v) if v then s:Show() else s:Hide() end end)
  if name then c[name] = o end
  return o
end
c.tinsert = table.insert
c.GameFontHighlightSmallOutline = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
c.UISpecialFrames = {}
c.UIParent = Obj()
c.StaticPopupDialogs = {}
c.StaticPopup_Show = function() return {} end
local notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
c.issecretvalue = nil
local TIP = { owner = nil, lines = {} }
c.GameTooltip = {
  SetOwner = function(_, o) TIP.owner = o; TIP.lines = {} end, SetText = function(_, t) TIP.title = t end,
  AddLine = function(_, t) TIP.lines[#TIP.lines + 1] = t end, Show = function() TIP.shown = true end,
  Hide = function() TIP.shown = false; TIP.owner = nil end, IsOwned = function(_, f) return TIP.owner == f end,
}
ALT, SHIFT, CTRL = false, false, false
c.IsAltKeyDown = function() return ALT end
c.IsShiftKeyDown = function() return SHIFT end
c.IsControlKeyDown = function() return CTRL end
c.UnitClassBase = function() return "MAGE" end
local sounds, waypoints = {}, {}
c.SOUNDKIT = { MAP_PING = 3175, UI_MAP_WAYPOINT_CONTROL_CLICK = 1 }
c.PlaySound = function(id) sounds[#sounds + 1] = id; return true end
c.PlaySoundFile = function(path) sounds[#sounds + 1] = path; return true end
c.LE_PARTY_CATEGORY_HOME, c.LE_PARTY_CATEGORY_INSTANCE = 1, 2
c.IsInGroup = function() return true end   -- in a group: a ping or a pin message would go out, so any leak shows in NET

-- Maps. Elwynn (1429), Westfall (1436) and Stormwind (1453) are on Eastern Kingdoms (continent 0, yards); Durotar (1411) is on
-- Kalimdor (continent 1); 2000 is a dungeon the game gives no world position for. 9999 is a map this client doesn't know.
c.Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4 }
local MAPS = {
  [946] = { name = "Cosmic", parent = 0, mapType = 0 },
  [947] = { name = "Azeroth", parent = 946, mapType = 1 },
  [1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2, ox = 0, oy = 0, size = 4000 },
  [1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3, ox = 1000, oy = 2000, size = 400 },
  [1436] = { name = "Westfall", parent = 1415, mapType = 3, ox = 600, oy = 2200, size = 400 },
  [1453] = { name = "Stormwind City", parent = 1429, mapType = 3, ox = 1100, oy = 2050, size = 100 },
  [1411] = { name = "Durotar", parent = 947, mapType = 3, ox = 0, oy = 0, size = 500, cont = 1 },
  [2000] = { name = "The Deadmines", parent = 1436, mapType = 4 },
}
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
local PLAYER = { map = 1429, x = 0.5, y = 0.5 }          -- nil x: no position (as in an instance)
c.C_Map = {
  GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.mapType } or nil end,
  GetBestMapForUnit = function() return PLAYER.map end,
  GetPlayerMapPosition = function(map)
    if PLAYER.x == nil or map ~= PLAYER.map then return nil end
    return c.CreateVector2D(PLAYER.x, PLAYER.y)
  end,
  GetWorldPosFromMapPos = function(map, v)
    local m = MAPS[map]; if not (m and m.size) then return nil end
    return m.cont or 0, c.CreateVector2D(m.ox + v.x * m.size, m.oy + v.y * m.size)
  end,
  GetMapPosFromWorldPos = function(cont, w, viewed)
    local m = MAPS[viewed]; if not (m and m.size) then return nil end
    return viewed, c.CreateVector2D((w.x - m.ox) / m.size, (w.y - m.oy) / m.size)
  end,
  CanSetUserWaypointOnMap = function() return true end,
  SetUserWaypoint = function(p) waypoints[#waypoints + 1] = p; return true end,
}
c.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }

c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end,
  OnShow = function() end, OnHide = function() end, OnMapChanged = function() end, RemoveAllData = function() end,
  RefreshAllData = function() end, OnCanvasScaleChanged = function() end, OnCanvasSizeChanged = function() end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
local canvas = Obj()
rawset(canvas, "GetWidth", function() return 1000 end); rawset(canvas, "GetHeight", function() return 700 end)
local container = Obj()
rawset(container, "GetWidth", function() return 1000 end)
local WMF = Obj()
local NAV = Obj()
local NAV_W = 900
rawset(NAV, "GetFrameLevel", function() return 7 end)
rawset(NAV, "GetWidth", function() return NAV_W end)
rawset(WMF, "NavBar", NAV)
WMF.mapID, WMF.providers, WMF.clicks = 1429, {}, {}
WMF.shown = false
WMF.setCalls, WMF.slow, WMF.fail = {}, false, false
rawset(WMF, "GetMapID", function(s) return s.mapID end)
rawset(WMF, "SetMapID", function(s, id)
  s.setCalls[#s.setCalls + 1] = id
  if s.fail then error("map can't be shown") end
  if s.slow then s.waitingFor = id return end
  s.mapID = id
  for p in pairs(s.providers) do p:OnMapChanged() end
end)
rawset(WMF, "GetCanvas", function() return canvas end)
rawset(WMF, "GetCanvasContainer", function() return container end)
rawset(WMF, "GetCanvasScale", function() return 1 end)
rawset(WMF, "GetGlobalPinScale", function() return 1 end)
rawset(WMF, "GetPinFrameLevelsManager", function() return { GetValidFrameLevel = function() return 40 end } end)
rawset(WMF, "AddDataProvider", function(s, p) s.providers[p] = true; p:OnAdded(s) end)
rawset(WMF, "RemoveDataProvider", function(s, p) p:RemoveAllData(); s.providers[p] = nil; p:OnRemoved(s) end)
rawset(WMF, "AddCanvasClickHandler", function(s, fn, pr) s.clicks[fn] = pr end)
rawset(WMF, "RemoveCanvasClickHandler", function(s, fn) s.clicks[fn] = nil end)
rawset(WMF, "AddCursorHandler", function() end)
rawset(WMF, "RemoveCursorHandler", function() end)
c.WorldMapFrame = WMF
local function deliver(id)
  WMF.mapID = id; WMF.waitingFor = nil
  for p in pairs(WMF.providers) do p:OnMapChanged() end
end
local function openMap()   -- as the game does: told it is shown, then every provider draws
  WMF.shown = true
  for p in pairs(WMF.providers) do p:OnShow() end
  for p in pairs(WMF.providers) do p:RefreshAllData() end
  FlushTimers()
end
local function closeMap() WMF.shown = false; for p in pairs(WMF.providers) do p:OnHide() end end
local function handlers() local n = 0 for _ in pairs(WMF.clicks) do n = n + 1 end return n end

for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua",
  "pins/MapTools.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Share.lua",
  "npcs/Knowledge.lua", "npcs/Search.lua", "npcs/SearchBar.lua", "npcs/FilterMenu.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true, npcMap = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PL, T, NS, NP, NMAP, KN, SR, SB, PU = R.PinsLook, R.MapTools, R.NpcStore, R.NpcPrefs, R.NpcMap, R.NpcKnowledge, R.NpcSearch, R.NpcSearchBar, R.MapPulse
assert(SR and SB and PU and NMAP.Locate, "the search is loaded")

local function serialize(t, seen)
  seen = seen or {}
  if type(t) ~= "table" then return tostring(t) end
  if seen[t] then return "<cycle>" end
  seen[t] = true
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. serialize(t[k], seen) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function Npc(id, name, map, x, y, tags, extra)
  extra = extra or {}
  return assert(NS.Observe({ id = id, name = name, map = map, x = x, y = y, tags = tags or { reagents = true },
    cls = extra.cls, prof = extra.prof, title = extra.title }))
end

local FM = R.NpcFilterMenu
assert(FM, "the filter menu is loaded")

local function btn() for _, f in ipairs(FRAMES) do if f.toolId == "filter" then return f end end end
local function menu() return c.TwichUINpcFilter end
local function entry(id) for _, e in ipairs(NS.Entries()) do if e.id == id then return e end end end
local function markerFor(e) for i = 1, NMAP.Used() do local b = NMAP.Marker(i); if b.entry == e then return b end end end
local function click(id) local row = FM.Row(id); assert(row, "a row for " .. id); row.scripts.OnClick(row) end
local function checked(id) return FM.Row(id).mark.shown end
local function drawnNames()
  local out = {}
  for i = 1, NMAP.Used() do out[#out + 1] = NMAP.Marker(i).entry.n end
  table.sort(out)
  return table.concat(out, ",")
end
local function isOpen() return menu() ~= nil and menu():IsShown() end
local function tidy()
  FM.Close(); NMAP.ClearReveal(); T.Cancel(); T.CloseHelp()
  NP.Reset("show")
  notices, sounds, waypoints, NET = {}, {}, {}, {}
end
local settingsRefreshes = 0
R.SettingsUI = { RefreshValues = function() settingsRefreshes = settingsRefreshes + 1 end }

-- the NPCs these tests use, all in Elwynn (the map being viewed)
Npc(1, "Auctioneer Fitch", 1429, 0.30, 0.30, { auctioneer = true })
Npc(2, "Banker Bram", 1429, 0.40, 0.30, { banker = true })
Npc(3, "Smith Gerda", 1429, 0.50, 0.30, { repair = true })
Npc(4, "Cook Anselm", 1429, 0.60, 0.30, { food = true, repair = true })     -- two roles
Npc(5, "Wanderer", 1429, 0.70, 0.30, { vendor = true })                      -- off by default
Npc(6, "Flightmaster Dane", 1429, 0.80, 0.30, { flight = true })             -- off by default
c.TwichUIDB.ui = c.TwichUIDB.ui or {}

---------------------------------------------------------------------------
-- 1. The icon file
---------------------------------------------------------------------------
do
  local path = ROOT .. "media/textures/maptool-filter.tga"
  local f = assert(io.open(path, "rb"), "the runtime texture is at " .. path)
  local d = f:read("*a"); f:close()
  local b = { d:byte(1, 18) }
  assert(b[3] == 2 and b[13] + b[14] * 256 == 32 and b[15] + b[16] * 256 == 32, "an uncompressed 32 x 32 true-color TGA, as the other tool icons")
  assert(b[17] == 32 and b[18] == 8, "32 bits with eight alpha bits")
  assert(#d == 18 + 32 * 32 * 4, "exactly its pixels, nothing else")
  local function alpha(x, y) return d:byte(18 + ((31 - y) * 32 + x) * 4 + 4) end   -- origin bottom-left
  assert(alpha(0, 0) == 0 and alpha(31, 0) == 0 and alpha(0, 31) == 0 and alpha(31, 31) == 0, "transparent corners: no matte")
  local opaque = 0
  for y = 0, 31 do for x = 0, 31 do if alpha(x, y) > 200 then opaque = opaque + 1 end end end
  assert(opaque > 150, "the funnel is in it")
  -- a margin all round, so bilinear filtering cannot bleed past the edge
  for i = 0, 31 do assert(alpha(i, 0) == 0 and alpha(i, 31) == 0 and alpha(0, i) == 0 and alpha(31, i) == 0, "a clear edge") end
end

---------------------------------------------------------------------------
-- 2. The button
---------------------------------------------------------------------------
do
  assert(PL.PREF_DEFAULTS.npcFilter == true and PL.Pref("npcFilter") == true, "on by default")
  assert(PL.SetPref("npcFilter", "yes") == false and PL.Pref("npcFilter") == true, "only a boolean is a choice")
  local handlersBefore = handlers()
  openMap()
  local b = btn()
  assert(b and b:IsShown(), "on the bar while Vendors and trainers and the choice are on")
  assert(b.icon.tex == T.ICON_PATH .. "filter", "it wears the funnel")
  assert(b.height == 24 and b.width == 30 and b.icon.width == 18 and b.icon.height == 18, "the size of the others")
  assert(handlers() == handlersBefore, "no click handler of its own")
  assert(not menu() and FM.Snapshot().built == false, "no menu is made by drawing the bar")
  local d = T.Describe("filter")
  assert(d.title == "NPC Filters" and #d.lines >= 1, "its tooltip")
  -- a neighbour's size, for comparison
  local pin
  for _, f in ipairs(FRAMES) do if f.toolId == "pin" then pin = f end end
  assert(pin.width == b.width and pin.height == b.height, "as wide and tall as the pin button")
  assert(b.fill.shown == false, "not lit while the menu is shut")

  -- off: the button goes, and the choices stay as they are
  NP.Set("show.auctioneer", false)
  PL.SetPref("npcFilter", false)
  assert(not b:IsShown(), "off: gone")
  assert(NP.Get("show.auctioneer") == false and not markerFor(entry(1)), "and the filter still applies")
  PL.SetPref("npcFilter", true)
  assert(b:IsShown(), "on again")
  NP.Reset("show")
  closeMap()
end

---------------------------------------------------------------------------
-- 3. The menu is made when asked, and holds every kind
---------------------------------------------------------------------------
do
  openMap()
  local frames = #FRAMES
  assert(not menu(), "nothing yet")
  local bt = btn()
  bt.scripts.OnClick(bt)
  assert(isOpen() and FM.Snapshot().open, "the button opens it")
  assert(#FRAMES > frames, "made now")
  assert(bt.fill.shown == true, "the button is lit while it is open")
  -- every kind of the model, whether or not the area has any: the list is the model's, not the map's
  local n = 0
  for _, kind in ipairs(R.NpcKinds.LIST) do
    n = n + 1
    local row = FM.Row(kind.id)
    assert(row and row.label.text == kind.label and row.icon.tex == kind.icon, kind.id .. ": its name and its icon")
    assert(checked(kind.id) == NP.Shown(kind.id), kind.id .. ": checked as saved")
  end
  assert(n == 18 and FM.Snapshot().kinds == 18, "all eighteen")
  assert(not checked("vendor") and checked("auctioneer"), "the defaults")
  -- Durotar has none of these: still all there
  deliver(1411); FlushTimers()
  assert(isOpen() and NMAP.Used() == 0 and FM.Row("auctioneer"), "a map with none of them: the kinds are still listed")
  deliver(1429); FlushTimers()
  -- opening it did not write anything
  assert(next(c.TwichUIDB.ui.npcMap or {}) == nil, "opening saves nothing")
  bt.scripts.OnClick(bt)
  assert(not isOpen() and bt.fill.shown == false, "the same button closes it, and the button is not lit")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 4. One kind off, and the rest stay
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  assert(drawnNames() == "Auctioneer Fitch,Banker Bram,Cook Anselm,Smith Gerda", "what is on by default is drawn")
  local layouts = NMAP.Snapshot().layouts
  local refreshes = settingsRefreshes
  click("auctioneer")
  assert(not checked("auctioneer") and NP.Get("show.auctioneer") == false, "unchecked, and saved")
  assert(drawnNames() == "Banker Bram,Cook Anselm,Smith Gerda", "the auctioneer is gone at once and nothing else is")
  assert(NMAP.Snapshot().layouts == layouts + 1, "drawn once for the one change")
  assert(isOpen(), "the menu stays open")
  assert(settingsRefreshes == refreshes + 1, "an open settings window is told")
  click("banker"); click("flight")
  assert(drawnNames() == "Cook Anselm,Flightmaster Dane,Smith Gerda", "several in a row, without reopening it: " .. drawnNames())
  assert(isOpen())
  click("auctioneer")
  assert(checked("auctioneer") and markerFor(entry(1)), "and back on")
  local saved = c.TwichUIDB.ui.npcMap
  assert(saved["show.auctioneer"] == true and saved["show.banker"] == false and saved["show.flight"] == true and saved.labels == nil and saved.iconSize == nil,
    "only the kinds that were touched are written")
  -- a click on the checkbox or the name is the row's click: one script, one row
  local row = FM.Row("repair")
  assert(row.scripts.OnClick and row.edge and row.label, "the whole row is the target")
  -- the markers of other kinds are the same ones (not redrawn differently)
  assert(markerFor(entry(3)).icon.tex == R.NpcKinds.BY_ID.repair.icon)
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 5. An NPC with several roles
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  local cook = entry(4)
  assert(markerFor(cook).icon.tex == R.NpcKinds.BY_ID.repair.icon, "wears its first checked role (repairs ranks above food and drink)")
  click("repair")
  assert(markerFor(cook), "repairs off: still shown, for its other role")
  assert(markerFor(cook).icon.tex == R.NpcKinds.BY_ID.food.icon, "with the icon of the role that is checked")
  assert(not markerFor(entry(3)), "the plain repairer is gone")
  click("food")
  assert(not markerFor(cook), "neither checked: hidden")
  assert(cook.tags.food and cook.tags.repair, "its record is as it was")
  click("repair")
  assert(markerFor(cook).icon.tex == R.NpcKinds.BY_ID.repair.icon, "one checked again: back")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 6. One set of choices
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  -- the settings change a kind (through the same preferences): the open menu follows
  NP.Set("show.banker", false)
  assert(not checked("banker") and not markerFor(entry(2)), "a change from the settings is shown in the menu")
  -- a profile change
  NP.Reset("show")
  assert(checked("banker") and markerFor(entry(2)), "so is a reset")
  -- the menu changes one: the settings read the same value
  click("banker")
  assert(NP.Get("show.banker") == false and NP.Shown("banker") == false, "the settings' own getter sees it")
  assert(NMAP.ShownKind(entry(2)) == nil, "and so does the map")
  -- the settings page's control is built on NP.Get/NP.Set: one copy
  local keys = 0
  for k in pairs(c.TwichUIDB.ui.npcMap) do keys = keys + 1; assert(k:match("^show%."), "no key of the menu's own: " .. k) end
  assert(keys == 1, "one key written")
  -- a saved value that can't be used is read as its default, and the menu follows that
  c.TwichUIDB.ui.npcMap["show.banker"] = "no"
  assert(NP.Get("show.banker") == true, "the default")
  FM.Close(); bt.scripts.OnClick(bt)
  assert(checked("banker"), "the menu reads it the same way")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 7. Show all and hide all
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  NP.Set("labels", true); NP.Set("iconSize", 120); NP.Set("reports", false)
  local look = serialize({ NP.Get("labels"), NP.Get("iconSize"), NP.Get("reports"), NP.Get("trainerClass") })
  local before = serialize(NS.Entries())
  local pins = serialize(c.TwichUIDB.pins or {})
  local layouts, refreshes = NMAP.Snapshot().layouts, settingsRefreshes
  local calls = 0
  NP.Subscribe(function() calls = calls + 1 end)
  local hide
  for _, f in ipairs(FRAMES) do if f.text and f.text.text == "Hide all" then hide = f end end
  assert(hide and hide.enabled ~= false, "Hide all is offered while some are checked")
  hide.scripts.OnClick(hide)
  assert(NMAP.Used() == 0, "nothing is drawn")
  for _, kind in ipairs(R.NpcKinds.LIST) do assert(not checked(kind.id) and NP.Get("show." .. kind.id) == false, kind.id) end
  assert(calls == 1 and NMAP.Snapshot().layouts == layouts + 1, "one change notice and one drawing, for eighteen kinds")
  assert(settingsRefreshes == refreshes + 1, "one refresh of the settings")
  assert(hide.enabled == false, "and nothing is left to hide")
  assert(serialize({ NP.Get("labels"), NP.Get("iconSize"), NP.Get("reports"), NP.Get("trainerClass") }) == look, "the looks are untouched")
  assert(serialize(NS.Entries()) == before, "no NPC was forgotten or changed")
  assert(serialize(c.TwichUIDB.pins or {}) == pins, "no pin was touched")
  assert(#NET == 0, "nothing was sent")
  hide.scripts.OnClick(hide)
  assert(calls == 1, "pressed again, it changes nothing and says nothing")
  local show
  for _, f in ipairs(FRAMES) do if f.text and f.text.text == "Show all" then show = f end end
  show.scripts.OnClick(show)
  for _, kind in ipairs(R.NpcKinds.LIST) do assert(checked(kind.id) and NP.Get("show." .. kind.id) == true, kind.id) end
  assert(calls == 2 and show.enabled == false, "Show all: one notice")
  assert(drawnNames() == "Auctioneer Fitch,Banker Bram,Cook Anselm,Flightmaster Dane,Smith Gerda,Wanderer", "everything known here is drawn")
  assert(isOpen(), "the menu stays open")
  assert(NP.SetAllShown("yes") == false, "only a boolean")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 8. Search and picking out
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  click("auctioneer")
  local fitch = entry(1)
  assert(not markerFor(fitch), "hidden by the filter")
  local saved = serialize(c.TwichUIDB.ui.npcMap)
  assert(NMAP.Locate(fitch), "the search can still find it")
  assert(markerFor(fitch) and NMAP.Revealed() == fitch, "and it is drawn while it is picked out")
  assert(markerFor(entry(2)) and not markerFor(entry(5)) and not markerFor(entry(6)), "the checked kinds show as ever and the unchecked ones stay out")
  assert(drawnNames():find("Wanderer") == nil, "no other hidden NPC came with it")
  assert(serialize(c.TwichUIDB.ui.npcMap) == saved and NP.Get("show.auctioneer") == false, "the pick checked nothing")
  assert(not checked("auctioneer"), "and the menu still shows it unchecked")
  -- another kind changes while it is picked out
  click("banker")
  assert(markerFor(fitch) and NMAP.Revealed() == fitch and not markerFor(entry(2)), "the pick stays; the filter applies to the rest")
  click("auctioneer")
  assert(markerFor(fitch) and NMAP.Revealed() == fitch, "checking its own kind keeps it drawn")
  click("auctioneer")
  assert(markerFor(fitch) and NMAP.Revealed() == fitch, "unchecking its own kind while it is picked out leaves the pick alone")
  NMAP.ClearReveal()
  assert(not markerFor(fitch), "letting go restores the filtered view: no stale marker")
  assert(NP.Get("show.auctioneer") == false and NP.Get("show.banker") == false, "and the choices are as made")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 9. Closing
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  local special = 0
  for _, name in ipairs(c.UISpecialFrames) do if name == "TwichUINpcFilter" then special = special + 1 end end
  assert(special == 1, "Esc closes it through the game's list of frames, once")
  -- a click elsewhere
  MENU_OVER = true
  c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
  assert(isOpen(), "a click on the menu keeps it open")
  MENU_OVER = false
  c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
  assert(not isOpen(), "a click anywhere else closes it")
  assert(bt.fill.shown == false, "the button is no longer lit")
  -- the button's own click does not close it and open it again
  bt.scripts.OnClick(bt)
  rawset(bt, "IsMouseOver", function() return true end)
  c.FireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
  assert(isOpen(), "the press on the button leaves the menu to the button's own click")
  bt.scripts.OnClick(bt)
  assert(not isOpen(), "which closes it")
  rawset(bt, "IsMouseOver", function() return false end)
  -- a click on the map reaches the map: the menu takes none
  assert(menu().mouse == true, "it takes the clicks on itself")
  -- other things on the bar
  bt.scripts.OnClick(bt); assert(isOpen())
  T.Arm("pin")
  assert(not isOpen() and T.Armed() == "pin", "arming a tool closes it")
  T.Cancel()
  bt.scripts.OnClick(bt); assert(isOpen())
  T.ToggleHelp()
  assert(not isOpen() and T.HelpOpen(), "so does the help")
  T.CloseHelp()
  T.Arm("pin")
  bt.scripts.OnClick(bt)
  assert(isOpen() and T.Armed() == nil, "opening it puts an armed tool away")
  T.ToggleHelp(); bt.scripts.OnClick(bt)
  assert(isOpen() and not T.HelpOpen(), "and the help")
  -- the search list
  FM.Close()
  edit = function() for _, f in ipairs(FRAMES) do if f.kindOf == "EditBox" then return f end end end
  PL.SetPref("npcSearch", true)
  local e = edit()
  e:SetFocus(); e.text = "fitch"; e.scripts.OnTextChanged(e, true); FlushTimers()
  assert(SB.Open(), "the search list is open")
  bt.scripts.OnClick(bt)
  assert(isOpen() and not SB.Open(), "opening the menu closes the search list")
  PL.SetPref("npcSearch", false)
  -- the map
  closeMap()
  assert(not isOpen(), "the map closing closes it")
  openMap()
  assert(not isOpen(), "and it is not open when the map is shown again")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 10. Reopening
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt); FM.Close()
  local frames, h = #FRAMES, handlers()
  local fs = #FSLIST
  for _ = 1, 5 do
    closeMap(); openMap()
    bt.scripts.OnClick(bt)
    click("auctioneer"); click("auctioneer")
    FM.Close()
  end
  assert(#FRAMES == frames and #FSLIST == fs and handlers() == h, "reopening the map and the menu makes no frame, text or handler")
  assert(FM.Snapshot().opens >= 5, "(and it was opened)")
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 11. Room: a short map scrolls, a tall one doesn't
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn()
  bt.scripts.OnClick(bt)
  local tall = menu().height
  FM.Close()
  -- a map with 200 units below the button
  rawset(bt, "GetBottom", function() return 300 end)
  rawset(bt, "GetEffectiveScale", function() return 1 end)
  rawset(container, "GetBottom", function() return 100 end)
  rawset(container, "GetEffectiveScale", function() return 1 end)
  rawset(menu(), "GetEffectiveScale", function() return 1 end)
  bt.scripts.OnClick(bt)
  assert(menu().height <= 200 - 3 - 8 + 0.5 and menu().height < tall, "short of room: the menu is kept inside the map (" .. menu().height .. " of " .. tall .. ")")
  assert(menu().height >= 110, "but not smaller than a few rows")
  FM.Close()
  rawset(container, "GetBottom", function() return -2000 end)
  bt.scripts.OnClick(bt)
  assert(menu().height == tall, "with room it is its full height")
  FM.Close()
  rawset(bt, "GetBottom", nil); rawset(container, "GetBottom", nil)
  tidy()
  closeMap()
end

---------------------------------------------------------------------------
-- 12. Going off
---------------------------------------------------------------------------
do
  openMap()
  local bt = btn(); bt.scripts.OnClick(bt)
  assert(isOpen())
  -- the choice
  PL.SetPref("npcFilter", false)
  assert(not isOpen() and not bt:IsShown(), "the choice off: closed and gone")
  PL.SetPref("npcFilter", true)
  bt.scripts.OnClick(bt)
  assert(isOpen())
  -- Vendors and trainers
  c.TwichUIDB.modules.npcMap = false
  for _, m in ipairs({ "NpcMap", "NpcSearchBar", "NpcFilterMenu" }) do R[m].Refresh() end
  assert(not isOpen() and not bt:IsShown() and not FM.Wanted(), "Vendors and trainers off: the menu is closed and the button is gone")
  local before = serialize(c.TwichUIDB.ui.npcMap)
  assert(FM.Open(bt) == false and not isOpen(), "asked to open, it says why instead")
  assert(notices[#notices] and notices[#notices]:find("Vendors and trainers is turned off"), "in a notice")
  assert(FM.SetKind("auctioneer", false) == false and FM.SetAll(false) == false, "and changes nothing")
  assert(serialize(c.TwichUIDB.ui.npcMap) == before, "nothing was saved")
  c.TwichUIDB.modules.npcMap = true
  for _, m in ipairs({ "NpcMap", "NpcSearchBar", "NpcFilterMenu" }) do R[m].Refresh() end
  assert(bt:IsShown() and FM.Wanted(), "on again: back")
  tidy()
  -- the map tools bar off
  PL.SetPref("toolbar", false)
  assert(not isOpen(), "the bar off: no menu")
  PL.SetPref("toolbar", true)
  closeMap()
end

print("NPC FILTER TESTS PASSED")
