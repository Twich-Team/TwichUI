-- Vendors and trainers on the world map (npcs/Map.lua): the markers go on the map only while the switch is on; an NPC
-- shows on its own map and the maps it is inside down to a zone, never on a continent or a sibling zone; only the
-- kinds chosen, class trainers for your class unless every class is chosen, and reports (dimmed and greyed) only while
-- chosen; the icon is the first shown kind's; a change to the list or a choice redraws an open map; at most 300 are
-- drawn; a click opens the NPC's actions (nothing is done until one is chosen), a modifier click goes to the map's own
-- handlers; Set waypoint names it through WaypointUI or falls back to the game's; Forget asks first and removes only
-- that NPC; switching off takes them off.
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
    if k == "SetScale" then return function(s, v) s.scale = v end end
    if k == "SetPoint" then return function(s, ...) s.lastPoint = { ... } end end
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
local nativeScale = 1
rawset(WMF, "GetCanvasScale", function() return nativeScale end)
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
-- Model WORLD_MAP_OPEN and reject direct addon calls to the native setter.
-- This checks the API boundary, not the client engine's taint behavior.
local nativeSetMapID = WMF.SetMapID
rawset(WMF, "SetMapID", function()
  error("addon must request WORLD_MAP_OPEN instead of tainting the native map ID")
end)
c.C_Map.OpenWorldMap = function(id) nativeSetMapID(WMF, id) end

-- Actual native host and seamless camera can differ until View's deliberate settle delay ends.
-- Map.lua must react to its existing view notification without switching the host itself.
local seamless = { ready = false, target = 1415, rect = { 900, 1900, 1500, 2500 }, listeners = {} }
local MV = {
  Ready = function() return seamless.ready end,
  Subscribe = function(fn) seamless.listeners[#seamless.listeners + 1] = fn end,
  View = function() return 1200, 2200, 24 end,
  PickMap = function() return seamless.target end,
  ViewRect = function() return unpack(seamless.rect) end,
  WireButton = function() end, WasDrag = function() return false end,
}
c.TwichUI.MapView = MV
c.TwichUI.MapWorld = {
  Stitchable = function(id) return MAPS[id] ~= nil and MAPS[id].size ~= nil end,
  ToWorld = function(id, x, y) local m = MAPS[id]; return m.ox + x * m.size, m.oy + y * m.size end,
  FromWorld = function(id, u, v) local m = MAPS[id]; return (u - m.ox) / m.size, (v - m.oy) / m.size end,
}
local function ViewChanged(event) for _, fn in ipairs(seamless.listeners) do fn(event or "view") end end
local function FadeStep(elapsed) for frame, fn in pairs(UPDATERS) do fn(frame, elapsed) end end

for _, f in ipairs({ "chronicle/Style.lua", "FrameLook.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
  "modules/Media.lua", "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Minimap.lua",
  "pins/Editor.lua", "pins/Window.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua",
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
  local e = assert(NS.Observe({ id = id, name = "Npc " .. id, map = map, x = x, y = y, tags = tags,
    cls = extra and extra.cls, faction = extra and extra.faction }))
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
assert(d[1].kind.id == "reagents" and d[1].icon.texture:find("npcs\\reagent%-pouch%-small", 1) and d[2].icon.texture:find("npcs\\coins%-small", 1))
assert(d[7].alpha == 0.6 and d[7].icon.desaturated == true and d[1].icon.desaturated == false, "a report is dimmed and greyed")
-- zoomed in, a marker grows (1.6 times at the closest zoom), and goes back at the widest view
assert(math.abs(d[1].scale - 1) < 1e-6 and d[1].size == 20.7, "at the widest view: the plain size")
rawset(WMF, "GetCanvasZoomPercent", function() return 1 end)
for p in pairs(WMF.providers) do p:OnCanvasScaleChanged() end
d = drawn()
assert(math.abs(d[1].scale - 1.6) < 1e-6 and d[1].size == 20.7, "at the closest zoom: 1.6 times, the size setting untouched")
rawset(WMF, "GetCanvasZoomPercent", function() return 0 end)
for p in pairs(WMF.providers) do p:OnCanvasScaleChanged() end
d = drawn()
assert(math.abs(d[1].scale - 1) < 1e-6)
-- a continent shows none; Stormwind itself shows its own
nativeSetMapID(WMF, 1415)
assert(NMAP.Used() == 0, "never on a continent")
nativeSetMapID(WMF, 1453)
d = drawn()
assert(d[2] and not d[1], "on Stormwind: its own NPCs, not Elwynn's")
nativeSetMapID(WMF, 1429)

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
NP.Set("reportAlpha", 100)
assert(drawn()[7].alpha == 1 and drawn()[7].icon.desaturated == false, "a report at full opacity looks like your own")
NP.Set("reportAlpha", 30)
assert(math.abs(drawn()[7].alpha - 0.3) < 1e-9 and drawn()[7].icon.desaturated == true and drawn()[1].alpha == 1, "the opacity choice dims reports only")
assert(not NP.Set("reportAlpha", 10) and not NP.Set("reportAlpha", 101) and NP.Get("reportAlpha") == 30, "an unusable opacity is refused")
assert(NP.Get("backdrop") == "none" and not drawn()[1].back, "no backdrop by default")
NP.Set("backdrop", "shadow")
local m = drawn()[1]
assert(m.back and m.back.shown and m.back.texture == m.kind.icon, "a shadow is a copy of the icon's shape")
NP.Set("backdrop", "plate")
assert(drawn()[1].back.shown and drawn()[1].back.texture ~= m.kind.icon, "a plate is a flat square")
assert(not NP.Set("backdrop", "glow") and NP.Get("backdrop") == "plate", "an unknown backdrop is refused")
NP.Set("backdrop", "none")
assert(drawn()[1].back.shown == false, "none hides it again")
NP.Set("backdrop", "shadow")
NP.Reset("all")
assert(NP.Get("backdrop") == "none" and drawn()[1].back.shown == false, "reset puts the backdrop back")
assert(NP.Get("reportAlpha") == 60 and drawn()[7].alpha == 0.6, "reset puts the opacity back")
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
-- WaypointUI is optional and can become available after the map has loaded. Its public API uses percentages.
local sounds, namedCalls, namedArgs = 0, 0, nil
c.SOUNDKIT = { UI_MAP_WAYPOINT_CONTROL_CLICK = 123 }
c.PlaySound = function(id) assert(id == 123); sounds = sounds + 1 end
c.WaypointUIAPI = { Navigation = { NewUserNavigation = function(args)
  namedCalls, namedArgs = namedCalls + 1, args
  return {}
end } }
local count = NMAP.Snapshot().waypoints
m.choices[1].run()
assert(namedCalls == 1 and #waypoints == 1, "a named waypoint doesn't also set an unnamed one")
assert(namedArgs.name == b.entry.n and namedArgs.mapID == b.entry.m, "the selected NPC's name and map")
assert(namedArgs.x == b.entry.x / NS.COORD * 100 and namedArgs.y == b.entry.y / NS.COORD * 100,
  "WaypointUI coordinates are percentages")
assert(namedArgs.suppressAudio == true and sounds == 1 and NMAP.Snapshot().waypoints == count + 1,
  "one click sound and one successful waypoint")
-- Missing or incomplete API, explicit refusal, nil result and exceptions all use Blizzard's waypoint.
local function fallback(api)
  c.WaypointUIAPI = api
  local before = #waypoints
  assert(NMAP.SetWaypoint(b.entry), "Blizzard fallback succeeds")
  local p = waypoints[#waypoints]
  assert(#waypoints == before + 1 and p.uiMapID == b.entry.m
    and p.x == b.entry.x / NS.COORD and p.y == b.entry.y / NS.COORD, "Blizzard coordinates stay normalized")
end
fallback(nil)
fallback({})
fallback({ Navigation = {} })
fallback({ Navigation = { NewUserNavigation = function() return false end } })
fallback({ Navigation = { NewUserNavigation = function() return nil end } })
fallback({ Navigation = { NewUserNavigation = function() error("unavailable") end } })
-- Map restrictions are checked before either API. Failed Blizzard calls must not report success or play a sound.
c.WaypointUIAPI = { Navigation = { NewUserNavigation = function() error("must not be called") end } }
local before, soundBefore, countBefore = #waypoints, sounds, NMAP.Snapshot().waypoints
assert(not NMAP.SetWaypoint({ m = 1436, x = b.entry.x, y = b.entry.y, n = b.entry.n }))
assert(#waypoints == before and sounds == soundBefore and NMAP.Snapshot().waypoints == countBefore,
  "a restricted map leaves the waypoint alone")
c.WaypointUIAPI = nil
local setWaypoint = c.C_Map.SetUserWaypoint
c.C_Map.SetUserWaypoint = function() return false end
assert(not NMAP.SetWaypoint(b.entry), "Blizzard refusal is a failure")
c.C_Map.SetUserWaypoint = function() error("unavailable") end
assert(not NMAP.SetWaypoint(b.entry), "Blizzard errors are contained")
assert(sounds == soundBefore and NMAP.Snapshot().waypoints == countBefore, "failed attempts aren't counted or sounded")
c.C_Map.SetUserWaypoint = setWaypoint
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
-- 4. Seamless eligibility follows the camera now; entry opacity never moves a plaque.
---------------------------------------------------------------------------
nativeSetMapID(WMF, 1415)
seamless.ready = true
ViewChanged()
assert(NMAP.Used() == 0, "a genuine continent overview stays uncluttered")
seamless.target = 1429
local function ProviderCount() local n = 0 for _ in pairs(WMF.providers) do n = n + 1 end return n end
local beforeLayouts, beforeProviders = NMAP.Snapshot().layouts, ProviderCount()
ViewChanged()
local entering = drawn()[4]
assert(entering and WMF:GetMapID() == 1415 and NMAP.Snapshot().layouts == beforeLayouts + 1,
  "markers become eligible before the native host's delayed change")
assert(ProviderCount() == beforeProviders, "camera updates do not reconstruct providers")
assert(entering.alpha == 0 and entering.lastPoint and NMAP.Snapshot().fading > 0,
  "a plaque is correctly anchored before its first visible opacity")
local px, py, scale = entering.lastPoint[4], entering.lastPoint[5], entering.scale
FadeStep(0.09)
assert(math.abs(entering.alpha - 0.5) < 1e-8, "entry uses a short smooth alpha transition")
local entriesBefore, projectionsBefore = NMAP.Snapshot().entries, NMAP.Snapshot().projections
ViewChanged(); NMAP.Layout()
entering = drawn()[4]
assert(math.abs(entering.alpha - 0.5) < 1e-8 and NMAP.Snapshot().entries == entriesBefore,
  "repeated view/layout notifications do not restart the fade")
assert(NMAP.Snapshot().projections == projectionsBefore, "camera-only updates reuse filtered world-coordinate projections")
assert(entering.lastPoint[4] == px and entering.lastPoint[5] == py and entering.scale == scale,
  "entry animation changes neither coordinates nor icon size")
FadeStep(0.09)
assert(entering.alpha == 1 and NMAP.Snapshot().fading == 0, "entry reaches full strength and releases the updater")
local layoutsBefore = NMAP.Snapshot().layouts
FadeStep(1)
assert(NMAP.Snapshot().layouts == layoutsBefore, "no idle marker layout polling")
-- A source-list ordering change can move an entry to another pooled frame, not restart its identity's opacity.
Npc(9, 1429, 0.55, 0.5, { innkeeper = true })
assert(drawn()[4].alpha == 1 and drawn()[9].alpha == 0, "only the newly eligible entry fades")
assert(NMAP.Snapshot().projections > projectionsBefore, "a source-list change invalidates cached candidates")
FadeStep(0.18)
nativeSetMapID(WMF, 1429)
assert(drawn()[4].alpha == 1 and NMAP.Snapshot().fading == 0, "host handoff preserves existing marker opacity")
assert(math.abs(drawn()[4].mx - 0.2) < 1e-8, "host handoff projects the same world place into its new canvas")
rawset(WMF, "GetCanvasZoomPercent", function() return 1 end)
for p in pairs(WMF.providers) do p:OnCanvasScaleChanged() end
assert(drawn()[4].scale == 1, "a host's changed native zoom percentage cannot resize seamless markers")
nativeScale = 2
for p in pairs(WMF.providers) do p:OnCanvasScaleChanged() end
assert(drawn()[4].scale * nativeScale == 1, "stitched markers keep the same screen-space size at another canvas scale")
nativeScale = 1
rawset(WMF, "GetCanvasZoomPercent", function() return 0 end)
ViewChanged()
local oldFactionAPI = c.UnitFactionGroup
c.UnitFactionGroup = function() return "Alliance" end
Npc(10, 1429, 0.5, 0.5, { reagents = true }, { faction = "H" })
assert(not drawn()[10], "opposing-side NPCs are filtered in the candidate cache")
local factionProjection = NMAP.Snapshot().projections
c.UnitFactionGroup = function() return "Horde" end
ViewChanged()
assert(drawn()[10] and NMAP.Snapshot().projections == factionProjection + 1,
  "a changed faction invalidates candidates even without a list, preference or host change")
c.UnitFactionGroup = oldFactionAPI
ViewChanged()
-- Viewport eligibility is projected through the host even outside its old zone rectangle.
seamless.target = 1436; seamless.rect = { 500, 2100, 1050, 2700 }
ViewChanged()
assert(drawn()[3] and drawn()[3].mx < 0 and WMF:GetMapID() == 1429,
  "a visible neighbor is eligible before the native host follows across a border")
-- Failed scale/placement cannot show a stale pooled anchor. A later valid notification recovers.
nativeScale = 0
NMAP.Layout()
assert(NMAP.Used() == 0 and NMAP.Snapshot().placementFailures > 0, "unplaceable markers stay hidden")
nativeScale = 1
ViewChanged()
assert(drawn()[3] and drawn()[3].alpha == 0, "valid placement recovers with an anchored entry")
local goodGlobal, goodWidth, goodZoom = WMF.GetGlobalPinScale, canvas.GetWidth, WMF.GetCanvasZoomPercent
local secret = setmetatable({}, { __lt = function() error("secret compared") end,
  __le = function() error("secret compared") end, __eq = function() error("secret compared") end })
c.issecretvalue = function(value) return rawequal(value, secret) end
local function Refuses(label, change, restore)
  local failures = NMAP.Snapshot().placementFailures
  change(); NMAP.Layout()
  assert(NMAP.Used() == 0 and NMAP.Snapshot().placementFailures > failures, label .. " stays hidden")
  restore(); NMAP.Layout()
  assert(drawn()[3], label .. " recovers once geometry is readable")
end
for _, value in ipairs({ 0 / 0, math.huge, secret }) do
  Refuses("invalid scale", function() nativeScale = value end, function() nativeScale = 1 end)
  Refuses("invalid global scale", function() rawset(WMF, "GetGlobalPinScale", function() return value end) end,
    function() rawset(WMF, "GetGlobalPinScale", goodGlobal) end)
  Refuses("invalid viewport width", function() rawset(canvas, "GetWidth", function() return value end) end,
    function() rawset(canvas, "GetWidth", goodWidth) end)
end
c.issecretvalue = nil
WMF.shown = false
for p in pairs(WMF.providers) do if p.OnHide then p:OnHide() end end
assert(NMAP.Snapshot().fading == 0 and NMAP.Used() == 0, "map close releases temporary opacity state")
WMF.shown = true; ViewChanged()
assert(drawn()[3] and drawn()[3].alpha == 0, "reopening can start a clean entry cycle")
seamless.target = 1415; ViewChanged()
assert(NMAP.Used() == 0 and NMAP.Snapshot().fading == 0, "zooming back to overview cancels entry work")
seamless.ready = false; nativeSetMapID(WMF, 1429)
ViewChanged("off")
assert(drawn()[4] and drawn()[4].alpha == 1, "turning seamless off immediately preserves normal native-map NPCs")
rawset(WMF, "GetCanvasZoomPercent", function() return 0 / 0 end)
NMAP.Layout()
assert(NMAP.Used() == 0, "invalid native zoom cannot reach a frame anchor")
rawset(WMF, "GetCanvasZoomPercent", goodZoom)
NMAP.Layout()
assert(drawn()[4], "native mode recovers after a readable zoom returns")

---------------------------------------------------------------------------
-- 5. At most 300 at once
---------------------------------------------------------------------------
for i = 1, 320 do NS.Observe({ id = 2000 + i, name = "Many", map = 1429, x = (i % 20) / 20, y = math.floor(i / 20) / 20, tags = { trade = true } }) end
assert(NMAP.Used() == 300 and NMAP.Snapshot().capped > 0)

---------------------------------------------------------------------------
-- 6. Off again: off the map; the list is kept
---------------------------------------------------------------------------
local kept = #NS.Entries()
c.TwichUIDB.modules.npcMap = false
NMAP.Refresh()
assert(not NMAP.Snapshot().installed and NMAP.Used() == 0 and #NS.Entries() == kept
  and NMAP.Snapshot().candidates == 0 and NMAP.Snapshot().fading == 0, "off releases projection and animation state")

print("PASSED")
