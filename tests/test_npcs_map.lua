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
  "pins/Editor.lua", "pins/Window.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua",
  "npcs/Share.lua" }) do
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

---------------------------------------------------------------------------
-- 1. Off: nothing on the map
---------------------------------------------------------------------------
Npc(1, 1429, 0.5, 0.5, { reagents = true })
local providersBefore = count(WMF.providers)   -- (Party pins' own)
NMAP.Refresh()
assert(not NMAP.Snapshot().installed and count(WMF.providers) == providersBefore, "off: not on the map")

---------------------------------------------------------------------------
-- 2. On: which NPCs show where
---------------------------------------------------------------------------
c.TwichUIDB.modules.npcMap = true
NMAP.Refresh()
assert(NMAP.Snapshot().installed)
Npc(2, 1453, 0.5, 0.5, { banker = true })            -- in Stormwind, inside Elwynn
Npc(3, 1436, 0.5, 0.5, { auctioneer = true })        -- Westfall, beside Elwynn
Npc(4, 1429, 0.2, 0.2, { classTrainer = true }, { cls = "MAGE" })
Npc(5, 1429, 0.3, 0.3, { classTrainer = true }, { cls = "PRIEST" })
Npc(6, 1429, 0.4, 0.4, { recipes = true })            -- hidden by default
NS.MergeReported({ NS.ReadWire({ i = 7, n = "Heard of", m = 1429, x = 7000, y = 7000, k = { "rg" } }) })
local d = drawn()
assert(d[1] and d[2] and d[4] and d[7], "its own map, a map inside it, your class's trainer, a report")
assert(not d[3] and not d[5] and not d[6], "not a sibling zone, another class's trainer, a hidden kind")
assert(d[1].entry.x == 5000 and math.abs(d[2].mx - (1100 + 50 - 1000) / 400) < 1e-6, "Stormwind's NPC placed on Elwynn by the world position")
assert(d[1].kind.id == "reagents" and d[1].icon.texture:find("npc%-reagents") and d[2].icon.texture:find("npc%-banker"))
assert(d[7].alpha == 0.6 and d[7].icon.desaturated == true and d[1].icon.desaturated == false, "a report is dimmed and greyed")
-- a continent shows none; Stormwind itself shows its own
WMF:SetMapID(1415)
assert(NMAP.Used() == 0, "never on a continent")
WMF:SetMapID(1453)
d = drawn()
assert(d[2] and not d[1], "on Stormwind: its own NPCs, not Elwynn's")
WMF:SetMapID(1429)

-- choices redraw an open map
NP.Set("trainerClass", "all")
assert(drawn()[5], "every class's trainers when chosen")
NP.Set("reports", false)
assert(not drawn()[7], "reports hidden when chosen")
NP.Set("show.reagents", false)
assert(not drawn()[1])
NP.Reset("all")
assert(drawn()[1] and drawn()[7] and not drawn()[5])
local size = drawn()[1].size
NP.Set("iconSize", 150)
assert(drawn()[1].size > size, "the size choice")
NP.Reset("all")
-- a new NPC appears at once
Npc(8, 1429, 0.6, 0.6, { innkeeper = true, food = true })
assert(drawn()[8] and drawn()[8].kind.id == "innkeeper", "the first shown kind's icon")

---------------------------------------------------------------------------
-- 3. Clicks
---------------------------------------------------------------------------
local b = drawn()[1]
b.scripts.OnClick(b, "LeftButton")
local m = menus[#menus]
assert(m and m.title == "Npc 1", "a click opens its actions")
local labels = {}
for _, ch in ipairs(m.choices) do labels[#labels + 1] = ch.label end
assert(table.concat(labels, ",") == "Set waypoint,Pin this place,Forget this NPC", table.concat(labels, ","))
assert(#waypoints == 0, "nothing done yet")
m.choices[1].run()
assert(#waypoints == 1 and waypoints[1].uiMapID == 1429 and waypoints[1].x == 0.5, "the game's waypoint at the NPC")
ALT = true
b.scripts.OnClick(b, "LeftButton")
ALT = false
assert(WMF.forwarded == 1 and #menus == 1, "a modifier click is the map's")
-- forgetting asks first, and removes only that one
local before = #NS.Entries()
m.choices[3].run()
assert(#NS.Entries() == before and popups[#popups].key == "TWICHUI_NPC_FORGET")
popups[#popups].dialog.OnAccept()
assert(#NS.Entries() == before - 1 and not drawn()[1] and drawn()[2], "only that NPC goes")

---------------------------------------------------------------------------
-- 4. At most 300 at once
---------------------------------------------------------------------------
for i = 1, 320 do NS.Observe({ id = 2000 + i, name = "Many", map = 1429, x = (i % 20) / 20, y = math.floor(i / 20) / 20, tags = { trade = true } }) end
assert(NMAP.Used() == 300 and NMAP.Snapshot().capped > 0)

---------------------------------------------------------------------------
-- 5. Off again: off the map; the list is kept
---------------------------------------------------------------------------
local kept = #NS.Entries()
c.TwichUIDB.modules.npcMap = false
NMAP.Refresh()
assert(not NMAP.Snapshot().installed and NMAP.Used() == 0 and #NS.Entries() == kept)

print("PASSED")
