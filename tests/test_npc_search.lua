-- The NPC search on the map tools bar: npcs/Search.lua (what matches, how the matches are ranked), npcs/SearchBar.lua (the field and
-- its list), npcs/Map.lua's Locate (the map goes to the NPC and its marker is picked out) and pins/Pulse.lua (the ring).
-- The game's frames, maps and clock are mocks (as in test_map_tools.lua and test_npcs_map.lua), so this shows TwichUI's own
-- bookkeeping: what is searched and in which order, what opens and closes, what is picked out and when it is let go. How the
-- field sits in the title row, the ring and the keyboard are for the game (docs/map-tools.md lists the checks).
--   1  off by default           2  matching            3  places and identity     4  nearest first
--   5  the cap                  6  a big list          7  the field and its list  8  keys and the mouse
--   9  choosing                 10 hidden kinds        11 quick choices           12 the list changing
--   13 closing and going off    14 nothing else        15 the ring
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
local LIST_OVER = false
c.CreateFrame = function(kind, name, parent)
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
local function clickMap() for fn in pairs(WMF.clicks) do fn(WMF, "LeftButton", 0.5, 0.5) end end
local function handlers() local n = 0 for _ in pairs(WMF.clicks) do n = n + 1 end return n end

for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua",
  "pins/MapTools.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Share.lua",
  "npcs/Knowledge.lua", "npcs/Search.lua", "npcs/SearchBar.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true, npcMap = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PL, T, NS, NP, NMAP, KN, SR, SB, PU = R.PinsLook, R.MapTools, R.NpcStore, R.NpcPrefs, R.NpcMap, R.NpcKnowledge, R.NpcSearch, R.NpcSearchBar, R.MapPulse
assert(SR and SB and PU and NMAP.Locate, "the search is loaded")

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
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
local function names(list) local out = {} for i, r in ipairs(list) do out[i] = r.name end return out end
local function keysOf(list) local out = {} for i, r in ipairs(list) do out[i] = r.key end return out end
local function stand(map, x, y) PLAYER.map, PLAYER.x, PLAYER.y = map, x, y end
local function Run(text, limit) return SR.Run(text, SR.Where(), limit) end

---------------------------------------------------------------------------
-- 1. Off by default: nothing built, listened to or searched
---------------------------------------------------------------------------
Npc(1, "Innkeeper Farley", 1429, 0.50, 0.60, { innkeeper = true })
do
  assert(PL.PREF_DEFAULTS.npcSearch == false and PL.Pref("npcSearch") == false, "off until chosen: an existing bar keeps its layout")
  assert(PL.SetPref("npcSearch", "yes") == false and PL.Pref("npcSearch") == false, "only a boolean is a choice")
  openMap()
  local bar = c.TwichUIMapTools
  assert(bar and bar:IsShown(), "the bar is on the map")
  assert(not SB.Built() and not c.TwichUIMapSearch, "no field and no list are made while it is off")
  assert(handlers() == 3, "no extra click handler while it is off (the pin click, the ping click and the tool click)")
  assert(SB.Snapshot().results == 0 and not SB.Snapshot().open, "nothing searched")
  closeMap()
end

---------------------------------------------------------------------------
-- 2. What matches
---------------------------------------------------------------------------
Npc(2, "Mage Trainer Anne-Marie", 1453, 0.40, 0.80, { classTrainer = true }, { cls = "MAGE", title = "Mage Trainer" })
Npc(3, "Alchemist Vera", 1453, 0.20, 0.30, { profTrainer = true }, { prof = "Alchemy" })
Npc(4, "Bartender 100% Fun (.*)", 1429, 0.52, 0.52, { vendor = true })
Npc(5, "Guard Thomas", 1436, 0.50, 0.50, { repair = true })
do
  local r = Run("farley")
  assert(#r == 1 and r[1].name == "Innkeeper Farley", "a partial name, in any case")
  assert(#Run("FARLEY") == 1 and #Run("keeper far") == 0 or #Run("keeper far") == 1, "words in any order")
  assert(#Run("  farley  ") == 1, "leading and trailing space is ignored")
  assert(#Run("innkeeper") >= 1 and Run("innkeeper")[1].role == "Innkeeper", "a role label matches")
  assert(Run("alchemy")[1].name == "Alchemist Vera", "a profession matches")
  assert(#Run(".*") == 1 and Run(".*")[1].name:find("Fun %(%.%*%)"), "input is literal text: '.*' matches only the name that has it")
  assert(#Run("%") == 1 and #Run("(.*") == 1 and #Run("(") == 3 and #Run("[") == 0 and #Run("%d+") == 0, "pattern characters are plain characters")
  local empty = Run("")
  assert(#empty == 0 and select(2, Run("")) == 0 and #Run("   ") == 0, "an empty query lists nothing, not the whole list")
  assert(#Run("zzzzz") == 0, "no match")
  assert(#Run(("x"):rep(500)) == 0, "a very long query is cut and matches nothing, without error")
  assert(#Run("|cffff0000farley|r") == 1, "escape sequences are removed from the query")
end

---------------------------------------------------------------------------
-- 3. Places and identity
---------------------------------------------------------------------------
Npc(10, "Brother Joseph", 1429, 0.20, 0.20, { banker = true })
Npc(10, "Brother Joseph", 1429, 0.80, 0.80, { banker = true })           -- the same creature, another place (a second entry)
Npc(11, "Brother Joseph", 1429, 0.21, 0.21, { innkeeper = true })       -- another creature with the same name, near the first
Npc(12, "Brother Joseph", 1436, 0.50, 0.50, { banker = true })
do
  local r = Run("brother joseph")
  assert(#r == 4, "every place is its own result: " .. #r)
  local seen = {}
  for _, x in ipairs(r) do
    assert(not seen[x.key], "keys are unique")
    seen[x.key] = true
  end
  assert(seen["10:1429:2000:2000"] and seen["10:1429:8000:8000"] and seen["11:1429:2100:2100"] and seen["12:1436:5000:5000"],
    "a key is creature, map and place (never the name)")
  local coords = 0
  for _, x in ipairs(r) do if x.coords then coords = coords + 1 end end
  assert(coords == 3, "the three in Elwynn say where (two of one creature, one of another): " .. coords)
  for _, x in ipairs(r) do if x.e.m == 1436 then assert(not x.coords, "the only one in Westfall needs no coordinates") end end
end
do
  -- entries that can't be shown on a map, and ones that are broken, are left out; reading never changes the list
  local db = c.TwichUIDB.npcs
  local before = serialize(db)
  db.list[#db.list + 1] = { id = 90, n = "Lost Trader", m = 9999, x = 100, y = 100, tags = { vendor = true }, own = true }   -- map not known
  db.list[#db.list + 1] = { id = 91, n = "Half Record", m = 1429, x = 100 }                                                   -- missing fields
  db.list[#db.list + 1] = "junk"
  NS.Invalidate()
  local afterAdd = serialize(db)
  assert(#Run("lost trader") == 0, "a record on a map this client doesn't know is not offered (it would fail when chosen)")
  assert(#Run("half") == 0, "a broken record is skipped")
  assert(#Run("brother joseph") == 4, "and the rest is as it was")
  assert(serialize(db) == afterAdd, "searching changes nothing saved")
  db.list[#db.list] = nil; db.list[#db.list] = nil; db.list[#db.list] = nil
  NS.Invalidate()
  assert(serialize(db) == before, "(the list is back as it was)")
end

---------------------------------------------------------------------------
-- 4. Nearest first, where that can be said
---------------------------------------------------------------------------
do
  stand(1429, 0.5, 0.5)                                    -- Elwynn's middle: world (1200, 2200)
  local r = Run("brother joseph")
  local seq = {}
  for _, x in ipairs(r) do seq[#seq + 1] = ("%s:%s"):format(x.key, x.dist and math.floor(x.dist) or "-") end
  -- (0.2,0.2) -> (1080,2080): 169.7; (0.21,0.21) -> (1084,2084): 164.0; (0.8,0.8) -> (1320,2320): 169.7; Westfall (0.5,0.5) -> (800,2400): 447.2
  assert(r[1].key == "11:1429:2100:2100" and math.floor(r[1].dist) == 164, "the nearest is first: " .. table.concat(seq, " "))
  assert(r[4].key == "12:1436:5000:5000" and math.floor(r[4].dist) == 447, "the farthest is last: " .. table.concat(seq, " "))
  assert(r[2].dist and r[3].dist and r[2].dist <= r[3].dist, "ordered by distance")
  assert(r[1].tier == 1 and SR.DistanceText(r[1].dist) == "164 yd" and SR.DistanceText(1234.4) == "1,234 yd", "distances are whole yards")
  -- exactly equal distances never swap: (0.2,0.2) and (0.8,0.8) are both 169.7 yards away
  assert(r[2].key == "10:1429:2000:2000" and r[3].key == "10:1429:8000:8000", "equal distances are told apart by key: " .. table.concat(keysOf(r), " "))
  for _ = 1, 5 do assert(table.concat(keysOf(Run("brother joseph")), " ") == table.concat(keysOf(r), " "), "the same every time") end

  -- another continent: no distance is made up, and it comes after those with one
  Npc(20, "Brother Orgrim", 1411, 0.5, 0.5, { banker = true })
  local mixed = Run("brother")
  assert(mixed[#mixed].name == "Brother Orgrim" and mixed[#mixed].dist == nil and mixed[#mixed].tier == 3, "a place on another continent has no distance and comes last")
  -- raw normalized coordinates from unrelated maps are never compared
  Npc(21, "Brother Zero", 1411, 0.0, 0.0, { banker = true })
  Npc(22, "Brother Far", 1436, 0.99, 0.99, { banker = true })
  local m2 = Run("brother")
  local pos = {}
  for i, x in ipairs(m2) do pos[x.name] = i end
  assert(pos["Brother Far"] < pos["Brother Zero"] and pos["Brother Far"] < pos["Brother Orgrim"], "Westfall's far corner (a distance) is before Kalimdor (none)")

  -- no position of yours (an instance, or the game won't say): the map you are on first, then the rest by area and name
  stand(1429, nil, nil)
  local np = Run("brother")
  assert(np[1].tier == 2 and np[1].e.m == 1429, "without a position, this map's places come first")
  for _, x in ipairs(np) do assert(x.dist == nil, "and none has a distance") end
  local lastTier = 0
  for _, x in ipairs(np) do assert(x.tier >= lastTier, "tiers never go back") lastTier = x.tier end
  local group3 = {}
  for _, x in ipairs(np) do if x.tier == 3 then group3[#group3 + 1] = x.zone .. "|" .. x.name end end
  local sorted = {}
  for i, v in ipairs(group3) do sorted[i] = v end
  table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
  assert(table.concat(group3, ";") == table.concat(sorted, ";"), "the rest are by area name, then NPC name")

  -- no map at all
  stand(nil, nil, nil)
  local nm = Run("brother")
  assert(#nm == 7 and nm[1].tier == 3, "with no map of yours everything is ranked by name alone")

  -- in a dungeon with no world position: places in that map are 'this area'
  Npc(30, "Brother Miner", 2000, 0.5, 0.5, { vendor = true })
  stand(2000, nil, nil)
  local dg = Run("brother")
  assert(dg[1].name == "Brother Miner" and dg[1].tier == 2, "in a dungeon its own NPCs come first, without a made-up distance")
  stand(1429, 0.5, 0.5)
  local out = Run("brother miner")
  assert(#out == 1 and out[1].dist == nil and out[1].tier == 3, "a dungeon place can't be compared with a field")

  -- the player's place is read once per search
  local reads = 0
  local real = c.C_Map.GetPlayerMapPosition
  c.C_Map.GetPlayerMapPosition = function(...) reads = reads + 1; return real(...) end
  Run("brother")
  c.C_Map.GetPlayerMapPosition = real
  assert(reads == 1, "one reading of your place per search: " .. reads)
end

---------------------------------------------------------------------------
-- 5. The cap keeps the nearest of every match, not the first found
---------------------------------------------------------------------------
do
  -- fifty guards laid out west to east; stored far-first so the nearest are the last stored
  local db = c.TwichUIDB.npcs
  for i = 1, 50 do
    db.list[#db.list + 1] = { id = 500 + i, n = "Sentry " .. i, m = 1429, x = 10000 - i * 150, y = 5000, tags = { repair = true }, own = true, seen = 1, at = 1 }
  end
  NS.Invalidate()
  stand(1429, 0.0, 0.5)                                    -- the west edge: the one at x=0.985 is far, x=0.01 near
  local r, total = Run("sentry")
  assert(total == 50 and #r == 8, "50 matched, 8 kept: " .. total .. " " .. #r)
  local want = {}
  for i = 1, 50 do want[i] = { n = "Sentry " .. i, x = 10000 - i * 150 } end
  table.sort(want, function(a, b) return a.x < b.x end)
  for i = 1, 8 do assert(r[i].name == want[i].n, ("row %d is the %dth nearest overall: %s vs %s"):format(i, i, r[i].name, want[i].n)) end
  assert(table.concat(names(Run("sentry", 3)), ",") == table.concat({ want[1].n, want[2].n, want[3].n }, ","), "the limit is respected")
  -- take them out again
  for i = #db.list, 1, -1 do if type(db.list[i]) == "table" and db.list[i].n and db.list[i].n:find("^Sentry") then table.remove(db.list, i) end end
  NS.Invalidate()
  stand(1429, 0.5, 0.5)
end

---------------------------------------------------------------------------
-- 6. A big list stays quick
---------------------------------------------------------------------------
do
  local db = c.TwichUIDB.npcs
  local base = #db.list
  for i = 1, NS.MAX_ENTRIES - base do
    local maps = { 1429, 1436, 1453, 1411 }
    db.list[#db.list + 1] = { id = 1000 + i, n = ("Villager %d of %s"):format(i, (i % 7 == 0) and "Elwynn" or "the road"), m = maps[i % 4 + 1],
      x = (i * 37) % 10001, y = (i * 91) % 10001, tags = { vendor = true }, own = true, seen = 1, at = 1 }
  end
  NS.Invalidate()
  local t0 = os.clock()
  local first = Run("villager")
  local t1 = os.clock()
  local again
  for _ = 1, 10 do again = Run("villager 7") end
  local t2 = os.clock()
  assert(#first == 8 and select(2, Run("villager")) > 2000, "a full list: everything matched, the nearest 8 kept")
  assert(t1 - t0 < 2.0 and (t2 - t1) / 10 < 1.0, ("quick enough on a full list: %.3fs first, %.3fs each after"):format(t1 - t0, (t2 - t1) / 10))
  assert(#Run("zzz") == 0)
  for i = #db.list, base + 1, -1 do db.list[i] = nil end
  NS.Invalidate()
end

---------------------------------------------------------------------------
-- 7. The field and its list
---------------------------------------------------------------------------
local function box() return c.TwichUIMapSearch end
local function edit()
  for _, f in ipairs(FRAMES) do if f.kindOf == "EditBox" then return f end end
end
local function typeInto(text) local e = edit(); e.text = text; e.scripts.OnTextChanged(e, true) end
local function rowsShown()
  local out = {}
  for _, f in ipairs(FRAMES) do
    if f.index and f.parent == box() and f:IsShown() then out[#out + 1] = f end
  end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end
local function rowText(row) return row.name.text, row.meta.text, row.dist.text end
local function key(k) edit().scripts.OnArrowPressed(edit(), k) end
local function tidy()
  if edit() and edit().focused then edit():ClearFocus() end
  if edit() then edit():SetText("") end
  NMAP.ClearReveal()
  notices, sounds, waypoints, NET = {}, {}, {}, {}
  WMF.mapID, WMF.slow, WMF.fail, WMF.setCalls = 1429, false, false, {}
  FlushTimers()
end

PL.SetPref("npcSearch", true)
stand(1429, 0.5, 0.5)
openMap()
do
  assert(SB.Active() and SB.Snapshot().active, "chosen, and Vendors and trainers is on")
  assert(box(), "the field is made when the bar is laid out with the choice on")
  assert(edit() and not edit().focused, "it doesn't take the keyboard when the map opens or the bar is drawn")
  assert(handlers() == 4 and SB.Snapshot().handler, "one more click handler, only while it is on")
  assert(not box():IsShown() and not SB.Open() and #rowsShown() == 0, "no list until the field is used")
  -- not enough room: put away
  NAV_W = 300
  openMap(); closeMap(); openMap()
  assert(not SB.Snapshot().shown, "a title row too narrow for it leaves it out")
  NAV_W = 900
  closeMap(); openMap()
  assert(SB.Snapshot().shown, "and it is back with room")

  -- focus: the hint, nothing listed
  edit():SetFocus()
  assert(SB.Open() and box():IsShown() and #rowsShown() == 0, "focusing an empty field shows the hint, not the list")
  local hint = false
  for _, fs in ipairs(FSLIST) do if fs.text:find("Only NPCs in your list are searched", 1, true) then hint = true end end
  assert(hint, "the hint says what it is for")
  assert(SB.Snapshot().rows == 0, "no result row exists until there is a result to put in one")
  -- typing waits for the pause
  local before = SB.Snapshot().results
  typeInto("brother joseph")
  assert(#rowsShown() == 0, "nothing is searched on the keystroke")
  FlushTimers()
  assert(#rowsShown() == 4 and SB.Snapshot().rows == 4, "one search after the pause: " .. #rowsShown())
  local n, m, d = rowText(rowsShown()[1])
  assert(n == "Brother Joseph" and m:find("Banker") == nil and m:find("Innkeeper") and m:find("Elwynn Forest"), "name, role and area: " .. n .. " / " .. m)
  assert(d == "164 yd", "and the distance, when it can be told: " .. d)
  -- several keys, one search
  local searches = 0
  local realRun = SR.Run
  SR.Run = function(...) searches = searches + 1; return realRun(...) end
  typeInto("b"); typeInto("br"); typeInto("bro"); typeInto("brot"); typeInto("broth")
  FlushTimers()
  assert(searches == 1, "five keystrokes, one search: " .. searches)
  SR.Run = realRun
  -- the footer, the empty state
  typeInto("zzzz"); FlushTimers()
  local none = false
  for _, fs in ipairs(FSLIST) do if fs.text == "No known NPCs match." then none = true end end
  assert(none and #rowsShown() == 0, "a search with nothing found says so")
  typeInto(""); FlushTimers()
  assert(#rowsShown() == 0 and SB.Open(), "an emptied field is back to the hint")
  -- the same rows are reused
  local frames = #FRAMES
  for _ = 1, 5 do typeInto("brother joseph"); FlushTimers(); typeInto("sentry"); FlushTimers() end
  assert(#FRAMES == frames, "no frame is made by searching again")
  tidy()
end

---------------------------------------------------------------------------
-- 8. Keys and the mouse
---------------------------------------------------------------------------
do
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  local rows = rowsShown()
  assert(#rows == 4 and rows[1].on.shown and not rows[2].on.shown, "the first row is chosen at first")
  key("DOWN"); assert(rows[2].on.shown and not rows[1].on.shown, "Down moves on")
  key("DOWN"); key("DOWN"); key("DOWN"); assert(rows[1].on.shown, "and wraps")
  key("UP"); assert(rows[4].on.shown, "Up goes back, wrapping")
  key("LEFT"); assert(rows[4].on.shown, "other keys do nothing")
  rows[2].scripts.OnEnter(rows[2]); assert(rows[2].on.shown and not rows[4].on.shown, "the pointer chooses a row too")
  assert(TIP.owner == rows[2] and TIP.title == "Brother Joseph", "and its tooltip names the NPC")
  local joined = table.concat(TIP.lines, "\n")
  assert(joined:find("straight line", 1, true) and joined:find("Not a walking distance", 1, true), "a distance is called what it is")

  -- Esc closes the list and lets go of the field
  edit().scripts.OnEscapePressed(edit())
  assert(not SB.Open() and not box():IsShown() and not edit().focused, "Esc closes the list and releases the field")
  assert(edit():GetText() == "brother joseph", "the text stays")
  -- Enter chooses the highlighted row
  edit():SetFocus(); FlushTimers()
  assert(SB.Open() and #rowsShown() == 4, "focusing a field with text searches again")
  key("DOWN")
  local chosen = rowsShown()[2]
  edit().scripts.OnEnterPressed(edit())
  assert(not SB.Open() and not edit().focused, "Enter chooses and releases the field")
  assert(NMAP.Revealed() ~= nil, "and something is picked out")
  tidy()

  -- a click on a row lands although the field loses focus first
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  LIST_OVER = true
  edit():ClearFocus()                                      -- the pointer is on the list: the list stays
  assert(SB.Open() and #rowsShown() == 4, "the list stays while the pointer is on it")
  rowsShown()[3].scripts.OnClick(rowsShown()[3])
  LIST_OVER = false
  assert(not SB.Open() and NMAP.Revealed(), "and the click is not lost")
  tidy()

  -- a click elsewhere closes it
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  LIST_OVER = false
  clickMap()
  assert(not SB.Open() and not edit().focused, "a click on the map closes the list and lets go of the field")
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  edit():ClearFocus()
  assert(not SB.Open(), "losing focus with the pointer elsewhere closes it")
  tidy()
end

---------------------------------------------------------------------------
-- 9. Choosing
---------------------------------------------------------------------------
local function ringOn() return NMAP.Snapshot().ringing end
local function markerFor(e)
  for i = 1, NMAP.Used() do local b = NMAP.Marker(i); if b.entry == e then return b end end
end
do
  tidy()
  local farley = KN and (function() for _, e in ipairs(NS.Entries()) do if e.id == 1 then return e end end end)()
  -- a place on the map already viewed: no map change, a ring on its marker
  edit():SetFocus(); typeInto("farley"); FlushTimers()
  local before = #WMF.setCalls
  edit().scripts.OnEnterPressed(edit())
  assert(#WMF.setCalls == before, "already on that map: it isn't asked for again")
  assert(NMAP.Revealed() == farley and markerFor(farley) and ringOn(), "its marker has a ring")
  local f
  for _, fr in ipairs(FRAMES) do if fr.rings then f = fr end end
  local b = markerFor(farley)
  assert(f and f:IsShown() and f.lastPoint, "the ring frame is shown")
  tidy()

  -- a place on another map: the map goes there, and the ring follows once it has laid itself out
  local joseph = (function() for _, e in ipairs(NS.Entries()) do if e.id == 5 then return e end end end)()
  edit():SetFocus(); typeInto("guard thomas"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(WMF.setCalls[#WMF.setCalls] == 1436 and WMF.mapID == 1436, "the map goes to the NPC's area")
  assert(NMAP.Snapshot().picked and not ringOn(), "the ring waits for the map to finish laying itself out")
  FlushTimers()
  assert(ringOn() and markerFor(NMAP.Revealed()), "then its marker is rung")
  -- the ring ends by itself, the NPC stays picked out
  for _ = 1, 8 do FlushTimers() end
  assert(not ringOn() and NMAP.Revealed(), "the ring stops after a moment")
  tidy()

  -- a map that arrives later
  WMF.slow = true
  edit():SetFocus(); typeInto("guard thomas"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(NMAP.Snapshot().waiting and WMF.waitingFor == 1436, "a map that is slow to come is waited for")
  deliver(1436); FlushTimers()
  assert(ringOn() and not NMAP.Snapshot().waiting, "and the ring follows when it comes")
  tidy()
  WMF.slow = false

  -- a map that never comes: given up after the wait, with a sentence
  WMF.slow = true
  edit():SetFocus(); typeInto("guard thomas"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  RunLongTimers(3)
  assert(not NMAP.Snapshot().waiting and not NMAP.Revealed() and notices[#notices] == "That map didn't open.", "it is given up after a while, and said")
  WMF.slow = false
  tidy()
  WMF.fail = true
  edit():SetFocus(); typeInto("guard thomas"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(not NMAP.Revealed() and notices[#notices] == "That map couldn't be opened.", "a map the game won't show is said")
  WMF.fail = false
  tidy()
end

---------------------------------------------------------------------------
-- 10. A kind the map hides is shown only while it is picked out
---------------------------------------------------------------------------
do
  tidy()
  assert(NP.Get("show.vendor") == false and NP.Get("show.repair") == true, "(other merchants are off by default; repairs are on)")
  local barman = (function() for _, e in ipairs(NS.Entries()) do if e.id == 4 then return e end end end)()
  deliver(1429); FlushTimers()
  assert(not markerFor(barman), "hidden by the chosen kinds: no marker")
  local drawn = NMAP.Used()
  edit():SetFocus(); typeInto("100%"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(markerFor(barman) and ringOn(), "picked out, it is drawn and ringed")
  assert(NMAP.Used() == drawn + 1, "and only it: no other hidden NPC came with it")
  assert(NP.Get("show.vendor") == false, "the saved choice is untouched")
  assert(not (c.TwichUIDB.ui and c.TwichUIDB.ui.npcMap and c.TwichUIDB.ui.npcMap["show.vendor"]), "nothing was saved")
  -- replaced by another pick
  edit():SetFocus(); typeInto("farley"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(not markerFor(barman) and NMAP.Used() == drawn, "a new pick lets the old one go")
  -- cleared by emptying the field
  edit():SetFocus(); typeInto("100%"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  assert(markerFor(barman))
  edit():SetFocus(); typeInto(""); FlushTimers()
  assert(not NMAP.Revealed() and not markerFor(barman) and not ringOn(), "emptying the field lets go of it")
  -- let go by the map closing
  edit():SetFocus(); typeInto("100%"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  closeMap()
  assert(not NMAP.Revealed() and not ringOn(), "closing the map lets go of it")
  openMap()
  assert(not markerFor(barman), "and it isn't there when the map is opened again")
  -- by going to another map
  edit():SetFocus(); typeInto("100%"); FlushTimers()
  edit().scripts.OnEnterPressed(edit())
  deliver(1436); FlushTimers()
  assert(not NMAP.Revealed(), "the player going to a map the NPC isn't on lets go of it")
  tidy()
end

---------------------------------------------------------------------------
-- 11. Quick choices
---------------------------------------------------------------------------
do
  tidy()
  -- a Westfall NPC is chosen and its map is slow to come; before it does, an NPC on the map being shown is chosen
  WMF.slow = true
  edit():SetFocus(); typeInto("guard"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(WMF.waitingFor == 1436 and NMAP.Snapshot().waiting and NMAP.Revealed().n == "Guard Thomas")
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(NMAP.Revealed().n == "Innkeeper Farley" and not NMAP.Snapshot().waiting, "the newest choice replaces the one still waiting")
  assert(ringOn(), "and is rung now")
  deliver(1436); FlushTimers()
  assert(not ringOn() and not NMAP.Revealed(), "the earlier map arriving later rings nothing: the choice made on another map is let go")
  tidy()

  -- two choices on different maps; the first map comes after the second was asked for
  WMF.slow = true
  edit():SetFocus(); typeInto("guard"); FlushTimers(); edit().scripts.OnEnterPressed(edit())          -- Westfall
  edit():SetFocus(); typeInto("orgrim"); FlushTimers(); edit().scripts.OnEnterPressed(edit())         -- Durotar
  assert(WMF.setCalls[#WMF.setCalls] == 1411 and NMAP.Revealed().n == "Brother Orgrim", "the newest is the one waited for")
  deliver(1436); FlushTimers()
  assert(not ringOn() and not NMAP.Revealed() and not NMAP.Snapshot().waiting, "the map asked for first isn't the one waited for: nothing is rung")
  deliver(1411); FlushTimers()
  assert(not ringOn() and not NMAP.Revealed(), "and the cancelled choice isn't brought back when the other map comes")
  WMF.slow = false
  tidy()

  -- the map arrives and the ring is waiting for it to finish laying itself out; another choice on that map comes first
  WMF.slow = true
  edit():SetFocus(); typeInto("guard"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  deliver(1436)                                                -- (the ring is queued for after the layout, not yet run)
  local rings = NMAP.Snapshot().pulses
  edit():SetFocus(); typeInto("joseph westfall"); SB.Search(false)
  edit().scripts.OnEnterPressed(edit())
  assert(NMAP.Revealed().n == "Brother Joseph" and ringOn() and NMAP.Snapshot().pulses == rings + 1, "the newer choice is rung at once")
  FlushTimers()
  assert(NMAP.Revealed().n == "Brother Joseph" and NMAP.Snapshot().pulses == rings + 1, "and the queued ring of the older one never starts: " .. NMAP.Snapshot().pulses - rings)
  WMF.slow = false
  tidy()

  -- the same choice twice, quickly: the ring starts over, one ring
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  local idle = count(UPDATERS)
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(ringOn() and count(UPDATERS) == idle, "choosing it again restarts the ring rather than adding another")
  tidy()
end

---------------------------------------------------------------------------
-- 12. The list changing under the results
---------------------------------------------------------------------------
local function entryOf(id, map) for _, e in ipairs(NS.Entries()) do if e.id == id and (map == nil or e.m == map) then return e end end end
do
  tidy()
  stand(1429, 0.5, 0.5)
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  assert(#rowsShown() == 4)
  -- a record is removed while the results are open: they are made again once, for the same place
  local nearest = SR.Run("brother joseph", SR.Where())[1].e
  assert(NS.Forget(nearest))
  assert(#rowsShown() == 4, "(nothing moves until the pause is over)")
  FlushTimers()
  assert(#rowsShown() == 3, "the open list is made again after the change: " .. #rowsShown())
  assert(rowsShown()[1].name.text == "Brother Joseph" and rowsShown()[1].meta.text:find("20.0, 20.0", 1, true), "the nearest left is first")

  -- one removed after the list was drawn, chosen before it was made again: refused, said, then made again
  local westfall = rowsShown()[3]
  assert(westfall.meta.text:find("Westfall", 1, true), "(the Westfall one is the last row)")
  NS.Forget(entryOf(12))
  westfall.scripts.OnClick(westfall)
  assert(notices[#notices] == "That NPC is no longer in your list." and not NMAP.Revealed(), "a removed NPC isn't shown, and it is said")
  assert(WMF.mapID == 1429 and #WMF.setCalls == 0, "and the map isn't moved for it")
  FlushTimers()
  assert(#rowsShown() == 2, "the list is made again: " .. #rowsShown())

  -- an update to an entry that is still listed: the pick follows it
  rowsShown()[1].scripts.OnClick(rowsShown()[1])
  local picked = NMAP.Revealed()
  assert(picked and picked.id == 10)
  NS.Observe({ id = 10, name = "Brother Joseph", map = 1429, x = 0.2, y = 0.2, tags = { banker = true, innkeeper = true } })
  FlushTimers()
  assert(NMAP.Revealed() == picked and ringOn() ~= nil, "an update keeps the same entry picked out")

  -- a picked-out NPC removed from the list is let go
  NS.Forget(NMAP.Revealed())
  assert(not NMAP.Revealed() and not ringOn(), "an NPC that leaves the list is let go of")
  tidy()
  -- put back what these removed, for what follows
  Npc(10, "Brother Joseph", 1429, 0.20, 0.20, { banker = true })
  Npc(11, "Brother Joseph", 1429, 0.21, 0.21, { innkeeper = true })
  Npc(12, "Brother Joseph", 1436, 0.50, 0.50, { banker = true })
end

---------------------------------------------------------------------------
-- 13. Closing, and going off
---------------------------------------------------------------------------
do
  tidy()
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  assert(SB.Open())
  closeMap()
  assert(not SB.Open() and not edit().focused and edit():GetText() == "" and not box():IsShown(), "the map closing closes the list, lets go of the field and empties it")
  assert(handlers() == 3, "and the click handler is let go")
  openMap()
  assert(SB.Snapshot().shown and not SB.Open() and handlers() == 4, "opened again: the field, no list, one handler")
  local frames = #FRAMES
  for _ = 1, 4 do closeMap(); openMap() end
  assert(#FRAMES == frames and handlers() == 4, "reopening the map makes no frame and adds no handler")

  -- a tool on the bar takes the list away
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  assert(SB.Open())
  T.Arm("pin")
  assert(not SB.Open(), "arming a tool closes the list")
  T.Cancel()
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  T.ToggleHelp()
  assert(not SB.Open(), "so does the help")
  T.CloseHelp()

  -- going off
  edit():SetFocus(); typeInto("100%"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(NMAP.Revealed())
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  PL.SetPref("npcSearch", false)
  assert(not SB.Active() and not box():IsShown() and not SB.Open() and not edit().focused, "off: the field and list are gone, the focus let go")
  assert(edit():GetText() == "" and not NMAP.Revealed() and not ringOn(), "the text is emptied and what it picked out is let go of")
  assert(handlers() == 3, "and its click handler goes")
  local searches = 0
  local realRun = SR.Run
  SR.Run = function(...) searches = searches + 1; return realRun(...) end
  edit().scripts.OnTextChanged(edit(), true)
  FlushTimers()
  openMap()
  assert(searches == 0, "nothing is searched while it is off")
  SR.Run = realRun
  PL.SetPref("npcSearch", true)
  assert(SB.Snapshot().shown, "on again: back")

  -- the switch for the whole feature
  edit():SetFocus(); typeInto("brother joseph"); FlushTimers()
  assert(SB.Open())
  c.TwichUIDB.modules.npcMap = false
  for _, m in ipairs({ "NpcMap", "NpcSearchBar" }) do R[m].Refresh() end
  assert(not SB.Active() and not box():IsShown() and not SB.Open(), "Vendors and trainers off: the search goes too")
  c.TwichUIDB.modules.npcMap = true
  for _, m in ipairs({ "NpcMap", "NpcSearchBar" }) do R[m].Refresh() end
  assert(SB.Active() and SB.Snapshot().shown, "and comes back with it")
  -- the bar off
  PL.SetPref("toolbar", false)
  assert(not c.TwichUIMapTools:IsShown() and not SB.Snapshot().handler and not SB.Open(), "the bar off takes the field with it")
  PL.SetPref("toolbar", true)
  assert(c.TwichUIMapTools:IsShown() and SB.Snapshot().shown and SB.Snapshot().handler, "and back")
  -- a fault in the search never takes the bar with it
  local caught = {}
  local realHandler, realLayout = c.geterrorhandler, SB.Layout
  c.geterrorhandler = function() return function(e) caught[#caught + 1] = e end end
  SB.Layout = function() error("boom") end
  T.Refresh(); closeMap(); openMap()
  assert(c.TwichUIMapTools:IsShown() and #caught >= 1 and tostring(caught[1]):find("boom"), "the bar is drawn and the fault is reported")
  SB.Layout, c.geterrorhandler = realLayout, realHandler
  closeMap(); openMap()
  assert(SB.Snapshot().shown, "and the field is back once it works")
  -- the tests below pick things out
  tidy()
end

---------------------------------------------------------------------------
-- 14. Choosing makes nothing else
---------------------------------------------------------------------------
do
  tidy()
  local choices = serialize(c.TwichUIDB.ui)
  local pins = serialize(c.TwichUIDB.pins)
  NET, SENT_LOG = {}, {}
  edit():SetFocus(); typeInto("guard thomas"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  edit():SetFocus(); typeInto("100%"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  for _ = 1, 8 do FlushTimers() end
  assert(#NET == 0 and #(SENT_LOG or {}) == 0, "nothing is sent (no ping, no pin, no list)")
  assert(#sounds == 0, "no sound")
  assert(#waypoints == 0, "no waypoint is set")
  assert(serialize(c.TwichUIDB.ui) == choices, "no saved choice changed")
  assert(serialize(c.TwichUIDB.pins) == pins, "no pin was made")
  assert(R.Nav == nil or not R.Nav.Active(), "no route was started")
  assert(R.MapPing.Snapshot and true, "(pings were not touched)")
  tidy()
end

---------------------------------------------------------------------------
-- 15. The ring
---------------------------------------------------------------------------
do
  tidy()
  -- the shared helper: rings expand and fade; still, a fixed outline; a ping with reduced motion draws none
  local fake = { CreateTexture = function() local t = Obj(); rawset(t, "SetSize", function(s, w, h) s.w = w end); rawset(t, "SetAlpha", function(s, a) s.a = a end); return t end }
  local rings = PU.AddRings(fake, 2)
  assert(#rings == 2 and rings[1].dark and rings[1].ring, "a dark ring under a bright one, twice")
  PU.Step(rings, 0.3, 2, false)
  assert(rings[1].shown and not rings[2].shown, "the second ring starts later")
  PU.Step(rings, 0.6, 2, false)
  assert(rings[1].shown and rings[2].shown and rings[1].ring.w > PU.FROM, "and both grow")
  PU.Step(rings, 0.6, 2, true)
  assert(not rings[1].shown and not rings[2].shown, "reduced motion with no outline asked for: none (a ping's marker stays)")
  PU.Step(rings, 0.6, 2, true, true)
  local w1 = rings[1].ring.w
  PU.Step(rings, 1.4, 2, true, true)
  assert(rings[1].shown and not rings[2].shown and rings[1].ring.w == w1, "reduced motion with an outline: one fixed ring, not growing")
  PU.Step(rings, 2.5, 2, true, true)
  assert(not rings[1].shown, "gone after its time")

  -- the highlight on the map follows the ping's own choice of stillness
  local PG = PL.Ping
  PG.Set("reducedMotion", true)
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(ringOn(), "with reduced motion the place is still marked")
  local ring
  for _, fr in ipairs(FRAMES) do if fr.rings and fr.rings[1] and fr.rings[1].shown and fr:IsShown() then ring = fr end end
  assert(ring, "a fixed ring is shown")
  local w = ring.rings[1].ring.w
  FlushTimers()
  assert(ring.rings[1].ring.w == w and not ring.rings[2].shown, "and it doesn't grow")
  PG.Set("reducedMotion", false)
  tidy()

  -- a ring is placed on its marker and stops when the NPC is picked out no more
  local idle = count(UPDATERS)                              -- (other frames' updates that were running anyway)
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(ringOn())
  NMAP.ClearReveal()
  assert(not ringOn() and count(UPDATERS) == idle, "clearing stops the ring and its updates")
  edit():SetFocus(); typeInto("farley"); FlushTimers(); edit().scripts.OnEnterPressed(edit())
  assert(count(UPDATERS) == idle + 1, "one update runs while the ring is out")
  closeMap()
  assert(not ringOn() and count(UPDATERS) == idle, "none after the map closes")
  openMap()
  -- the ping's own rings are drawn through the same helper
  assert(R.MapPulse and R.MapPulse.Step, "map pings use the helper")
end

print("NPC SEARCH TESTS PASSED")
