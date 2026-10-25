-- Vendors and trainers on the minimap (npcs/Minimap.lua): off by default and only with the switch; within range, placed by
-- the pins' minimap reads; the world map's own kind choices; a cap; a click opens the same actions; off takes them away.
-- (Stand-in for the world map follows test_npcs_map.lua.)
-- Vendors and trainers on the world map (npcs/Map.lua): the markers go on the map only while the switch is on; an NPC
-- shows on its own map and the maps it is inside down to a zone, never on a continent or a sibling zone; only the
-- kinds chosen, class trainers for your class unless every class is chosen, and reports (dimmed and greyed) only while
-- chosen; the icon is the first shown kind's; a change to the list or a choice redraws an open map; at most 300 are
-- drawn; a click opens the NPC's actions (nothing is done until one is chosen), a modifier click goes to the map's own
-- handlers; Set waypoint sets the game's; Forget asks first and removes only that NPC; switching off takes them off.
-- The map is a stand-in for the game's (WorldMapFrame, its canvas and data providers), as in test_party_pins_ui.lua.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich Hale", { "!!!TwichUI" })
CLIENTS["Rich Hale"] = c

local function Obj()
  local o = { text = "", shown = true }
  return setmetatable(o, { __index = function(t, k)
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetText" then return function(s, v) s.text = v or "" end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "SetDesaturated" then return function(s, v) s.desaturated = v end end
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetSize" then return function(s, w) s.size = w end end
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "CreateFontString" then return function() return Obj() end end
    if k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end   -- an unset field, not a method
    return function() end
  end })
end
local realCreate = c.CreateFrame
c.CreateFrame = function(kind, name)
  local o = Obj()
  local base = realCreate()
  for k, v in pairs(base) do
    if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end
  end
  if name then c[name] = o end
  return o
end
c.tinsert = table.insert
c.GameFontHighlightSmallOutline = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
c.UISpecialFrames = {}
c.UIParent = Obj()
c.GameTooltip = Obj()
c.StaticPopupDialogs = {}
local popups = {}
c.StaticPopup_Show = function(key, text) popups[#popups + 1] = { key = key, text = text, dialog = c.StaticPopupDialogs[key] }; return {} end
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
c.UIErrorsFrame = { AddMessage = function() end }
c.issecretvalue = nil
ALT = false
c.IsAltKeyDown = function() return ALT end
c.IsShiftKeyDown = function() return false end
c.IsControlKeyDown = function() return false end
c.UnitClassBase = function() return "MAGE" end

-- Stormwind City inside Elwynn Forest, both inside Eastern Kingdoms; Westfall beside Elwynn
local MAPS = {
  [947] = { name = "Azeroth", parent = 0, type = 1 },
  [1415] = { name = "Eastern Kingdoms", parent = 947, type = 2, ox = 0, oy = 0, size = 4000 },
  [1429] = { name = "Elwynn Forest", parent = 1415, type = 3, ox = 1000, oy = 2000, size = 400 },
  [1436] = { name = "Westfall", parent = 1415, type = 3, ox = 600, oy = 2200, size = 400 },
  [1453] = { name = "Stormwind City", parent = 1429, type = 3, ox = 1100, oy = 2050, size = 100 },
}
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
local waypoints = {}
c.C_Map = {
  GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.type } or nil end,
  CanSetUserWaypointOnMap = function(id) return id == 1429 or id == 1453 end,
  SetUserWaypoint = function(p) waypoints[#waypoints + 1] = p; return true end,
  GetWorldPosFromMapPos = function(map, v)
    local m = MAPS[map]; if not (m and m.size) then return nil end
    return 0, c.CreateVector2D(m.ox + v.x * m.size, m.oy + v.y * m.size)
  end,
  GetMapPosFromWorldPos = function(cont, w, viewed)
    local m = MAPS[viewed]; if not (m and m.size) then return nil end
    return viewed, c.CreateVector2D((w.x - m.ox) / m.size, (w.y - m.oy) / m.size)
  end,
}
c.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
local canvas = Obj()
rawset(canvas, "GetWidth", function() return 1000 end); rawset(canvas, "GetHeight", function() return 700 end)
local WMF = Obj()
WMF.mapID, WMF.providers, WMF.forwarded = 1429, {}, 0
rawset(WMF, "GetMapID", function(s) return s.mapID end)
rawset(WMF, "SetMapID", function(s, id) s.mapID = id; for p in pairs(s.providers) do p:OnMapChanged() end end)
rawset(WMF, "GetCanvas", function() return canvas end)
rawset(WMF, "GetCanvasScale", function() return 1 end)
rawset(WMF, "GetGlobalPinScale", function() return 1 end)
rawset(WMF, "GetPinFrameLevelsManager", function() return { GetValidFrameLevel = function() return 40 end } end)
rawset(WMF, "AddDataProvider", function(s, p) s.providers[p] = true; p:OnAdded(s) end)
rawset(WMF, "RemoveDataProvider", function(s, p) p:RemoveAllData(); s.providers[p] = nil; p:OnRemoved(s) end)
rawset(WMF, "AddCanvasClickHandler", function() end)
rawset(WMF, "RemoveCanvasClickHandler", function() end)
rawset(WMF, "ProcessCanvasClickHandlers", function(s) s.forwarded = s.forwarded + 1 end)
local sc = Obj()
rawset(sc, "NormalizeUIPosition", function() return 0.5, 0.5 end)
rawset(sc, "GetCursorPosition", function() return 0, 0 end)
WMF.ScrollContainer = sc
WMF.shown = true
c.WorldMapFrame = WMF

for _, f in ipairs({ "chronicle/Style.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
  "modules/Media.lua", "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Minimap.lua",
  "pins/Editor.lua", "pins/Window.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Minimap.lua",
  "npcs/Share.lua", "npcs/Knowledge.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { npcMap = false, partyPins = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local NS, NP, NMAP = R.NpcStore, R.NpcPrefs, R.NpcMap
local menus = {}
R.PinsWindow.OpenMenu = function(anchor, title, choices) menus[#menus + 1] = { title = title, choices = choices } end

local function Npc(id, map, x, y, tags, extra)
  local e = assert(NS.Observe({ id = id, name = "Npc " .. id, map = map, x = x, y = y, tags = tags, cls = extra and extra.cls }))
  return e
end
local function drawn()
  local list = {}
  for i = 1, NMAP.Used() do local b = NMAP.Marker(i); if b.entry then list[b.entry.id] = b end end
  return list
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end


-- the minimap: the player is at 0.5, 0.5 of Elwynn (200 yards across the zone's 400), it sees 100 yards over 70 pixels
local MINI = { visible = true, rotate = false, facing = 0, map = 1429, x = 0.5, y = 0.5, radius = 100 }
local Minimap = Obj()
rawset(Minimap, "IsVisible", function() return MINI.visible end)
rawset(Minimap, "GetWidth", function() return 140 end)
c.Minimap = Minimap
c.C_Minimap = { GetUiMapID = function() return MINI.map end, GetViewRadius = function() return MINI.radius end }
c.GetCVarBool = function() return MINI.rotate end
c.GetPlayerFacing = function() return MINI.facing end
c.C_Map.GetMapWorldSize = function(id) local m = MAPS[id]; if m and m.size then return m.size, m.size end end
c.C_Map.GetPlayerMapPosition = function(map, unit)
  local here = MAPS[MINI.map]
  if unit ~= "player" or not here then return nil end
  if map == MINI.map then return c.CreateVector2D(MINI.x, MINI.y) end
  local m = MAPS[map]
  if not (m and m.size) then return nil end
  local wx, wy = here.ox + MINI.x * here.size, here.oy + MINI.y * here.size
  return c.CreateVector2D((wx - m.ox) / m.size, (wy - m.oy) / m.size)
end
c.C_Map.GetBestMapForUnit = function() return MINI.map end
c.GetCVar = function() return "4" end
c.GameTooltip = Obj()

local R = c.TwichUI
local NS, NP, MM = R.NpcStore, R.NpcPrefs, R.NpcMinimap
local menus = {}
R.PinsWindow.OpenMenu = function(anchor, title, choices) menus[#menus + 1] = { title = title, choices = choices } end
local function Npc(id, map, x, y, tags, extra)
  return assert(NS.Observe({ id = id, name = "Npc " .. id, map = map, x = x, y = y, tags = tags, cls = extra and extra.cls }))
end
local function shown()
  local t = {}
  for _, s in ipairs(MM.State()) do t[s.id] = s end
  return t
end
local function tick() MM.Update(nil, 1) end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- 1. Off by default, even with the feature on
assert(NP.Get("minimap") == false and NP.DEFAULTS.minimap == false)
c.TwichUIDB.modules.npcMap = true
Npc(1, 1429, 0.5 + 40 / 400, 0.5, { reagents = true })    -- 40 yards east of you
Npc(2, 1429, 0.5, 0.5 - 20 / 400, { banker = true })      -- 20 yards north
Npc(3, 1429, 0.5 + 150 / 400, 0.5, { banker = true })     -- 150 yards: beyond the 100 the minimap sees
Npc(4, 1436, 0.5, 0.5, { auctioneer = true })             -- Westfall, not the minimap's map
Npc(5, 1429, 0.6, 0.6, { recipes = true })                -- a kind that is hidden
MM.Refresh()
assert(not MM.Active() and count(shown()) == 0, "off: nothing on the minimap")

-- 2. On: within range, the chosen kinds, placed 0.7 pixels a yard
assert(NP.Set("minimap", true))
assert(MM.Active())
tick()
local s = shown()
assert(s[1] and s[2], "within range")
assert(not s[3] and not s[4] and not s[5], "not beyond the range, another map, or a hidden kind")
assert(math.abs(s[1].x - 28) <= 0.5 and math.abs(s[1].y) <= 0.5, "40 yards east is 28 pixels right: " .. tostring(s[1].x))
assert(math.abs(s[2].y - 14) <= 0.5 and math.abs(s[2].x) <= 0.5, "20 yards north is 14 pixels up")

-- you move: the markers follow, and one leaves the range
MINI.x = 0.5 + 100 / 400
tick()
s = shown()
assert(s[1] and math.abs(s[1].x - (-42)) <= 0.5, "60 yards west of you now")
assert(s[3] and math.abs(s[3].x - 35) <= 0.5 and not s[2], "the far one comes into range, one leaves it")

-- the minimap turns with you
MINI.x, MINI.rotate, MINI.facing = 0.5, true, math.pi / 2
tick()
s = shown()
assert(s[1] and math.abs(s[1].x) <= 0.5 and math.abs(math.abs(s[1].y) - 28) <= 0.5, "rotated a quarter turn")
MINI.rotate, MINI.facing = false, 0

-- 3. A choice reaches it: kinds, size, the cap, a hidden minimap, no map
NP.Set("show.recipes", true)
tick()
assert(shown()[5], "a kind chosen shows")
NP.Reset("show")
tick()
assert(not shown()[5])
local before = shown()[1].size
NP.Set("iconSize", 150)
tick()
assert(shown()[1].size > before, "the size choice follows")
NP.Set("iconSize", 100)
MINI.visible = false
tick()
MINI.visible = true
tick()
assert(shown()[1], "a hidden minimap catches up")

for i = 1, 60 do Npc(100 + i, 1429, 0.5 + (i % 10 - 5) / 400, 0.5 + (math.floor(i / 10) - 3) / 400, { trade = true }) end
NP.Set("show.trade", true)
tick()
assert(count(shown()) == 40, "at most 40 at once: " .. count(shown()))
NP.Reset("show")
tick()

-- 4. A click opens the same actions, nothing is done
local slot
for _, st in ipairs(MM.State()) do if st.id == 1 then slot = st end end
assert(slot)
local b = MM.Slot(1)
b.scripts.OnClick(b, "LeftButton")
assert(menus[#menus] and menus[#menus].title:find("Npc "), "a click opens its actions")

-- 5. Switch off: gone; the list is kept
local kept = #NS.Entries()
c.TwichUIDB.modules.npcMap = false
MM.Refresh()
assert(not MM.Active() and count(shown()) == 0 and #NS.Entries() == kept)
c.TwichUIDB.modules.npcMap = true
MM.Refresh()
NP.Reset("look")
assert(NP.Get("minimap") == false and not MM.Active() and count(shown()) == 0, "resetting the look turns it off again")

print("PASSED")
