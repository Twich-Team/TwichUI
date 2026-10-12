-- Party pins on the map and in the window, with permissive frame mocks: only the exact chosen clicks
-- place a pin (Ctrl-click, Shift-click and plain clicks go on to the map); the editor makes nothing and
-- sends nothing until Save, and Save checks again; pins are drawn on their own map and its parents but
-- not on siblings or children, and not when removed from your map; the window offers each pin only the
-- actions its owner may take and checks again when one runs; removing for the party asks first; Set
-- waypoint only happens when picked; turning the feature off takes TwichUI's handlers and pins off the
-- map; a font or texture that is missing falls back without being erased, and resetting the look leaves
-- pins and choices alone; the troubleshooting section names no pin, place or player.
-- Mocks show TwichUI's bookkeeping only. How it looks and behaves on the real map is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local c = MakeClient("Rich Hale", { "!!!TwichUI" })
CLIENTS["Rich Hale"] = c

-- permissive UI mocks (as in test_window_smoke.lua), with numbers where layout needs them
local MAPSTRINGS = {}
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
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "CreateFontString" then
      -- remembers what a name was dressed with, for the map text checks
      return function(_, _, _, template)
        local fs = Obj()
        fs.template = template
        rawset(fs, "SetFont", function(s, path, size, flags) s.font = { path, size, flags } end)
        rawset(fs, "SetTextColor", function(s, r, g, b) s.color = { r, g, b } end)
        rawset(fs, "SetShadowOffset", function(s, x, y) s.shadow = { x, y } end)
        rawset(fs, "SetWidth", function(s, w) s.width = w end)
        MAPSTRINGS[#MAPSTRINGS + 1] = fs
        return fs
      end
    end
    if k == "CreateTexture" then return function() return Obj() end end
    if k == "ScrollBar" then
      local sb = Obj(); rawset(sb, "ThumbTexture", false); rawset(sb, "ScrollUpButton", false); rawset(sb, "ScrollDownButton", false)
      rawset(t, k, sb); return sb
    end
    if type(k) == "string" and k:match("^%l") then return nil end   -- an unset field, not a method
    return function() end
  end })
end
local realCreate = c.CreateFrame
c.CreateFrame = function(kind, name)
  local o = Obj()
  local base = realCreate()
  for k, v in pairs(base) do
    if k ~= "Show" and k ~= "Hide" and k ~= "IsShown" then rawset(o, k, v) end   -- keep the mock's shown state
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
c.StaticPopup_Show = function(key, text) popups[#popups + 1] = { key = key, text = text }; return {} end
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
local notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
local function lastNotice() return notices[#notices] or "" end
c.issecretvalue = nil

-- keys held
ALT, SHIFT, CTRL = false, false, false
c.IsAltKeyDown = function() return ALT end
c.IsShiftKeyDown = function() return SHIFT end
c.IsControlKeyDown = function() return CTRL end
local function keys(a, s, k) ALT, SHIFT, CTRL = a, s, k end

-- maps: Elwynn (1429) and Westfall (1436) in Eastern Kingdoms (1415); Stormwind (1453) inside Elwynn
local MAPS = {
  [947] = { name = "Azeroth", parent = 0 },
  [1415] = { name = "Eastern Kingdoms", parent = 947, ox = 0, oy = 0, size = 4000 },
  [1429] = { name = "Elwynn Forest", parent = 1415, ox = 1000, oy = 2000, size = 400 },
  [1436] = { name = "Westfall", parent = 1415, ox = 600, oy = 2200, size = 400 },
  [1453] = { name = "Stormwind City", parent = 1429, ox = 1100, oy = 2050, size = 100 },
}
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
local waypoints = {}
c.C_Map = {
  GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parent } or nil end,
  CanSetUserWaypointOnMap = function(id) return id == 1429 or id == 1436 end,
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

-- the minimap: where the player is (on MINI.map, as 0..1), how far it sees, and whether it turns
local MINI = { visible = true, rotate = false, facing = 0, map = 1429, x = 0.5, y = 0.5, radius = 100 }
local Minimap = Obj()
rawset(Minimap, "IsVisible", function() return MINI.visible end)
rawset(Minimap, "GetWidth", function() return 140 end)   -- 70 pixels from the middle to the rim
c.Minimap = Minimap
c.C_Minimap = {
  GetUiMapID = function() if MINI.noMapID then return nil end return MINI.map end,   -- noMapID: the game gives none
  GetViewRadius = function() return MINI.radius end,
}
c.GetCVarBool = function() return MINI.rotate end
c.GetPlayerFacing = function() return MINI.facing end
-- a reading the game marks secret (a number here: the client's real ones are numbers too)
local SECRET = -777.25
c.issecretvalue = function(v) return v == SECRET end
c.canaccessvalue = function(v) return v ~= SECRET end
MINI.zoom = 4
rawset(Minimap, "GetZoom", function() return MINI.zoom end)
c.GetCVar = function(name) if name == "minimapZoom" then return "4" end end   -- the outdoor zoom
c.C_Map.GetBestMapForUnit = function() return MINI.best end
local caught = {}
c.geterrorhandler = function() return function(e) caught[#caught + 1] = e end end
c.C_Map.GetMapWorldSize = function(id) local m = MAPS[id]; if m and m.size then return m.size, m.size end end
c.C_Map.GetPlayerMapPosition = function(map, unit)
  local here = MAPS[MINI.map]
  if unit ~= "player" or not here then return nil end
  if map == MINI.map then return c.CreateVector2D(MINI.x, MINI.y) end
  -- on a map the player is inside (a parent of the one they are on)
  local id, inside = MINI.map, false
  for _ = 1, 8 do id = MAPS[id] and MAPS[id].parent; if id == map then inside = true break end if not id or id == 0 then break end end
  local m = MAPS[map]
  if not (inside and m and m.size) then return nil end
  local wx, wy = here.ox + MINI.x * here.size, here.oy + MINI.y * here.size
  return c.CreateVector2D((wx - m.ox) / m.size, (wy - m.oy) / m.size)
end

-- the world map: data providers and click handlers, as MapCanvasMixin keeps them
c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
local canvas = Obj()
rawset(canvas, "GetWidth", function() return 1000 end); rawset(canvas, "GetHeight", function() return 700 end)
local WMF = Obj()
WMF.mapID, WMF.providers, WMF.clicks, WMF.cursors = 1429, {}, {}, {}
rawset(WMF, "GetMapID", function(s) return s.mapID end)
rawset(WMF, "SetMapID", function(s, id) s.mapID = id; for p in pairs(s.providers) do p:OnMapChanged() end end)
rawset(WMF, "GetCanvas", function() return canvas end)
rawset(WMF, "GetCanvasScale", function() return 1 end)
rawset(WMF, "GetGlobalPinScale", function() return 1 end)
rawset(WMF, "GetPinFrameLevelsManager", function() return { GetValidFrameLevel = function() return 40 end } end)
rawset(WMF, "AddDataProvider", function(s, p) s.providers[p] = true; p:OnAdded(s) end)
rawset(WMF, "RemoveDataProvider", function(s, p) p:RemoveAllData(); s.providers[p] = nil; p:OnRemoved(s) end)
rawset(WMF, "AddCanvasClickHandler", function(s, fn, pr) s.clicks[fn] = pr end)
rawset(WMF, "RemoveCanvasClickHandler", function(s, fn) s.clicks[fn] = nil end)
rawset(WMF, "AddCursorHandler", function(s, fn, pr) s.cursors[fn] = pr end)
rawset(WMF, "RemoveCursorHandler", function(s, fn) s.cursors[fn] = nil end)
c.WorldMapFrame = WMF
local function click(button, x, y)
  local handled = false
  for fn in pairs(WMF.clicks) do if fn(WMF, button, x, y) then handled = true end end
  return handled
end
local function refreshMap() for p in pairs(WMF.providers) do p:RefreshAllData() end end

for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Minimap.lua", "pins/Editor.lua", "pins/Window.lua", "pins/Broker.lua",
  "diag/Diagnostics.lua", "diag/Pins.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PN, PS, PM, PE, PW, PL = R.Pins, R.PinSync, R.PinsMap, R.PinsEditor, R.PinsWindow, R.PinsLook
local function sent() local n = 0 for _, m in ipairs(SENT_LOG or {}) do if m.prefix == "TwichUIPins" then n = n + 1 end end return n end

---------------------------------------------------------------------------
-- 0. The pin texture: a 64 x 64, 32-bit TGA with an alpha channel, drawn centered on its coordinate
---------------------------------------------------------------------------
do
  local tail = "media\\textures\\map-pin"
  assert(PL.PIN_TEXTURE:sub(-#tail) == tail, "referenced like the addon's other textures, without an extension")
  local f = assert(io.open(ROOT .. "media/textures/map-pin.tga", "rb"))
  local head = f:read(18)
  local size = f:seek("end")
  f:close()
  local w, h = head:byte(13) + head:byte(14) * 256, head:byte(15) + head:byte(16) * 256
  assert(head:byte(3) == 2 and w == 64 and h == 64 and head:byte(17) == 32, "uncompressed 64 x 64 at 32 bits")
  assert(size == 18 + 64 * 64 * 4, "no extra data")
  assert(PL.PIN_BADGE[1] > 0.5 and PL.PIN_BADGE[1] < 1 and PL.PIN_BADGE[2] > 0 and PL.PIN_BADGE[2] < 0.5, "the badge sits on the upper right")
  local x, y = PL.BadgePoint(24)
  assert(x > 12 and x < 24 and y < 0 and y > -12)
end

---------------------------------------------------------------------------
-- 1. On the map: a provider and a click handler, before the game's waypoint handler
---------------------------------------------------------------------------
assert(PM.Snapshot().installed, "TwichUI's pins are on the map")
local priority
for _, pr in pairs(WMF.clicks) do priority = pr end
assert(priority == 95, "runs before the game's waypoint handler (90) and only takes exact clicks")

---------------------------------------------------------------------------
-- 2. Only the exact clicks place a pin
---------------------------------------------------------------------------
keys(false, false, false); assert(not click("LeftButton", 0.4, 0.5), "a plain click is the map's")
keys(false, false, true);  assert(not click("LeftButton", 0.4, 0.5), "Ctrl-click stays the game's waypoint")
keys(false, true, false);  assert(not click("LeftButton", 0.4, 0.5), "Shift-click is left for other addons")
keys(true, false, true);   assert(not click("LeftButton", 0.4, 0.5), "Ctrl-Alt-click is neither of ours")
keys(false, false, false); assert(not click("RightButton", 0.4, 0.5), "a right-click still zooms out")
assert(not PE.IsOpen() and PN.LocalCount() == 0)

-- Alt-click: the editor opens; cancelling (Esc) makes and sends nothing
keys(true, false, false)
assert(click("LeftButton", 0.4, 0.5), "Alt-click is taken")
assert(PE.IsOpen())
local ed = c.TwichUIPinEditor
assert(ed.title.text == "New pin" and ed.where.text:find("Elwynn Forest") and ed.name.text == "Pin 1", "a generated, editable name")
ed.name.scripts.OnEscapePressed(ed.name)
assert(not PE.IsOpen() and PN.LocalCount() == 0 and sent() == 0, "Cancel makes nothing")

-- Alt-click again, rename, pick a color, Save
assert(click("LeftButton", 0.4, 0.5))
ed.name:SetText("|cffff0000Ore|r vein")
ed.swatches[3].scripts.OnClick(ed.swatches[3])
ed.save.scripts.OnClick(ed.save)
local ore = PN.LocalPins()[1]
assert(ore and ore.name == "Ore vein" and ore.color == "moss" and ore.map == 1429 and ore.x == 4000 and ore.y == 5000, "saved where clicked")
assert(sent() == 0, "a local pin sends nothing")
assert(PN.selected == "local:" .. ore.id, "the new pin is picked out")

-- an empty name is refused at Save, keeping the editor open
assert(click("LeftButton", 0.2, 0.2))
ed.name:SetText("   ")
ed.save.scripts.OnClick(ed.save)
assert(PE.IsOpen() and ed.status.text:find("needs a name") and PN.LocalCount() == 1)
ed.name.scripts.OnEscapePressed(ed.name)

-- Place a pin: one plain click, then plain clicks are the map's again
keys(false, false, false)
assert(PM.Arm())
assert(click("LeftButton", 0.6, 0.6), "the armed click places")
assert(PE.IsOpen()); ed.name.scripts.OnEscapePressed(ed.name)
assert(not click("LeftButton", 0.6, 0.6), "only once")

---------------------------------------------------------------------------
-- 3. Party pins: refused outside a party; Cancel sends nothing; Save sends once
---------------------------------------------------------------------------
keys(true, true, false)
assert(click("LeftButton", 0.3, 0.3), "Alt-Shift-click opens a party pin")
assert(ed.title.text == "New party pin" and ed.save.enabled == false and ed.status.text:find("not in a party"))
ed.save.scripts.OnClick(ed.save)
assert(PN.SharedCount() == 0 and sent() == 0, "nothing made or sent outside a party")
ed.name.scripts.OnEscapePressed(ed.name)

GROUP = { ["Rich Hale"] = true, ["Pal Stonebrook"] = true }
c.FireEvent("GROUP_ROSTER_UPDATE")
local base = sent()   -- the hello
assert(click("LeftButton", 0.3, 0.3))
ed.name:SetText("Rendezvous")
ed.name.scripts.OnEscapePressed(ed.name)
assert(PN.SharedCount() == 0 and sent() == base, "a cancelled party pin is never sent")
assert(click("LeftButton", 0.3, 0.3))
ed.name:SetText("Rendezvous")
ed.save.scripts.OnClick(ed.save)
assert(PN.OwnCount() == 1 and sent() == base + 1, "sent once, on Save")
local mine = PN.OwnPins()[1]
-- a pin from a party member
PN.ApplyPut("Pal Stonebrook", { id = "pal:1", r = 1, m = 1436, x = 5000, y = 5000, n = "Westfall camp", c = "river" })
local pal = PN.Shared(PN.Key("Pal Stonebrook", "pal:1"))
assert(pal)

---------------------------------------------------------------------------
-- 4. Drawing: own map and its parents only; not removed ones
---------------------------------------------------------------------------
WMF.mapID = 1429; refreshMap()
assert(PM.Snapshot().drawn == 2, "Elwynn: the ore and the rendezvous")
WMF:SetMapID(1415)
assert(PM.Snapshot().drawn == 3, "Eastern Kingdoms: Elwynn's two and Westfall's one, through world positions")
WMF:SetMapID(1453)
assert(PM.Snapshot().drawn == 0, "never on a child map")
WMF:SetMapID(1436)
assert(PM.Snapshot().drawn == 1, "Westfall: only its own")
assert(PN.Dismiss(pal.key))
assert(PM.Snapshot().drawn == 0, "removed from my map: not drawn")
assert(PN.Restore(pal.key))
assert(PM.Snapshot().drawn == 1)
WMF:SetMapID(1429)

---------------------------------------------------------------------------
-- 5. The window: actions by owner, checked again when they run
---------------------------------------------------------------------------
assert(PW.Show())
PW.Refresh()
local function labels(list) local t = {} for _, a in ipairs(list) do t[a.label] = a end return t end
local localActs = labels(PW.Actions({ kind = "local", pin = ore, token = "local:" .. ore.id }))
assert(localActs["Show on map"] and localActs["Set waypoint"] and localActs["Rename or recolor..."] and localActs["Remove pin"])
assert(not localActs["Remove for entire party..."] and not localActs["Remove from my map"])
local mineE = { kind = "party", pin = mine, token = "party:" .. mine.key }
local mineActs = labels(PW.Actions(mineE))
assert(mineActs["Remove for entire party..."] and mineActs["Remove for entire party..."].enabled and mineActs["Rename or recolor..."])
assert(mineActs["Remove from my map"] and mineActs["Keep as local copy"])
local palE = { kind = "party", pin = pal, token = "party:" .. pal.key }
local palActs = labels(PW.Actions(palE))
assert(not palActs["Remove for entire party..."] and not palActs["Rename or recolor..."], "someone else's pin: no owner actions offered")
assert(palActs["Remove from my map"] and palActs["Keep as local copy"] and palActs["Set waypoint"])
-- Set waypoint only when picked; a map that can't hold one says so
assert(#waypoints == 0, "nothing set the player's waypoint by itself")
palActs["Set waypoint"].run()
assert(#waypoints == 1 and waypoints[1].uiMapID == 1436)
local onContinent = assert(PN.AddLocal({ map = 1415, x = 10, y = 10, name = "Far" }))
local farActs = labels(PW.Actions({ kind = "local", pin = onContinent, token = "local:" .. onContinent.id }))
assert(farActs["Set waypoint"].enabled == false and farActs["Set waypoint"].why:find("waypoint"))
-- a left click on a map pin (PM.Activate) selects it and sets the waypoint there; clicking the selected pin
-- again only deselects, and a map that can't hold a waypoint still selects, with the reason
do
  local PMap = R.PinsMap
  PN.Select(nil)
  local n = #waypoints
  PMap.Activate(palE)
  assert(PN.selected == palE.token and #waypoints == n + 1 and waypoints[n + 1].uiMapID == 1436, "selected, and the waypoint is there")
  PMap.Activate(palE)
  assert(PN.selected == nil and #waypoints == n + 1, "clicking the selected pin deselects and leaves the waypoint")
  local farE = { kind = "local", pin = onContinent, token = "local:" .. onContinent.id }
  PMap.Activate(farE)
  assert(PN.selected == farE.token and #waypoints == n + 1 and lastNotice():find("waypoint"), "selected; a map without waypoints says so")
  PN.Select(nil)
end
-- an action picked after its pin went is refused, not run
local doomed = assert(PN.AddLocal({ map = 1429, x = 1, y = 1, name = "Doomed" }))
local doomedActs = labels(PW.Actions({ kind = "local", pin = doomed, token = "local:" .. doomed.id }))
assert(PN.RemoveLocal(doomed.id))
doomedActs["Remove pin"].run()
assert(lastNotice():find("no longer there"), "checked again when it runs")
-- keep a local copy of Pal's pin; remove Pal's from my map; restore it
palActs["Keep as local copy"].run()
assert(PN.LocalPins()[#PN.LocalPins()].copiedFrom == "Pal Stonebrook")
local before = sent()
palActs["Remove from my map"].run()
assert(PN.IsDismissed(pal.key) and sent() == before, "removing from my map sends nothing")
PW.Refresh()
local restore = labels(PW.Actions(palE))["Restore to my map"]
assert(restore and restore.enabled); restore.run()
assert(not PN.IsDismissed(pal.key))
-- removing for the party asks first; nothing is sent until it is accepted
mineActs = labels(PW.Actions(mineE))
mineActs["Remove for entire party..."].run()
assert(popups[#popups].key == "TWICHUI_PINS_REMOVE_PARTY" and popups[#popups].text:find("Rendezvous") and popups[#popups].text:find("entire party"))
assert(PN.Shared(mine.key) and sent() == before, "nothing sent before confirming")
c.StaticPopupDialogs.TWICHUI_PINS_REMOVE_PARTY.OnAccept()
assert(not PN.Shared(mine.key) and sent() == before + 1 and lastNotice():find("sent to your party"), "one removal sent, and only 'sent' is claimed")
c.StaticPopupDialogs.TWICHUI_PINS_REMOVE_PARTY.OnAccept()
assert(sent() == before + 1, "accepting twice does nothing more")
-- Show on map: an open map moves; a closed one waits for the player to open it
PW.Actions(palE)[1].run()
assert(WMF.mapID == 1436 and PN.selected == palE.token)
WMF.shown = false
labels(PW.Actions({ kind = "local", pin = ore, token = "local:" .. ore.id }))["Show on map"].run()
assert(WMF.mapID == 1436 and lastNotice():find("Open your map"), "TwichUI doesn't open the map itself")
WMF.shown = true
for p in pairs(WMF.providers) do p:OnShow() end
FlushTimers()
assert(WMF.mapID == 1429 and PN.selected == "local:" .. ore.id, "shown when the player opens the map")
-- the broker's and window's counts
assert(PW.Count() == PN.LocalCount() + 1)

---------------------------------------------------------------------------
-- 6. Appearance: missing media falls back and stays chosen; reset leaves pins and choices
---------------------------------------------------------------------------
assert(PL.Set("font", "Gone Font") and PL.Get("font") == "Gone Font")
assert(PL.Snapshot().fontFallback == true, "a missing font is drawn as the game's own")
assert(c.TwichUIDB.ui.pinsAppearance.font == "Gone Font", "and stays chosen")
assert(not PL.Set("textSize", 40) and not PL.Set("accentColor", "red"))
c.TwichUIDB.ui.pinsAppearance.textSize = "huge"
assert(PL.Get("textSize") == 12 and c.TwichUIDB.ui.pinsAppearance.textSize == "huge", "an unusable value reads as the default and is kept")
c.TwichUIDB.ui.pinsLook = { bgTexture = "Some Pack Texture", borderTexture = "eui:missing" }
PW.Restyle()
assert(PL.Look.Get("bgTexture") == "Some Pack Texture", "a missing texture stays chosen")
assert(PL.SetPref("labels", "always"))
local pinsBefore = PN.LocalCount()
PL.Reset()
assert(c.TwichUIDB.ui.pinsAppearance == nil and c.TwichUIDB.ui.pinsLook == nil)
assert(PN.LocalCount() == pinsBefore and PL.Pref("labels") == "always", "reset is only the look")
-- the names on the maps: dressed the way the game's own was until chosen, then as chosen, on both maps
do
  local MT = PL.MapText
  local function names()
    local out = {}
    for _, fs in ipairs(MAPSTRINGS) do
      if fs.template == "GameFontHighlightSmallOutline" then out[#out + 1] = fs end
    end
    return out
  end
  local list = names()
  assert(#list > 0, "pins on the maps have names")
  local mini = 0
  for _, fs in ipairs(list) do
    assert(fs.font and fs.font[1] == "Fonts\\FRIZQT__.TTF" and fs.font[2] == 10 and fs.font[3] == "", "defaults are the game's own look")
    assert(fs.color and fs.color[1] == 1 and fs.color[3] == 1 and fs.shadow and fs.shadow[1] == 1 and fs.shadow[2] == -1)
    if fs.width == 120 then mini = mini + 1 end
  end
  assert(mini > 0 and mini < #list, "names exist on both the world map and the minimap")
  assert(c.TwichUIDB.ui.pinsMapText == nil, "nothing is saved until a choice is made")

  assert(MT.Set("size", 16) and MT.Set("color", "ffe0c070") and MT.Set("outline", "thick") and MT.Set("shadow", false))
  for _, fs in ipairs(list) do
    assert(fs.font[2] == 16 and fs.font[3] == "THICKOUTLINE", "every name follows, on both maps")
    assert(math.abs(fs.color[1] - 0xe0 / 255) < 1e-6 and fs.shadow[1] == 0 and fs.shadow[2] == 0)
  end
  for _, fs in ipairs(list) do
    assert(fs.width == 224 or fs.width == 192, "a larger name has more room (140 and 120 at size 10)")
  end
  assert(not MT.Set("size", 40) and not MT.Set("size", 12.5) and not MT.Set("color", "red")
    and not MT.Set("outline", "glow") and not MT.Set("shadow", "yes") and not MT.Set("nope", 1), "unusable values are refused")
  c.TwichUIDB.ui.pinsMapText.size = "huge"
  assert(MT.Get("size") == 10 and c.TwichUIDB.ui.pinsMapText.size == "huge", "an unusable saved value reads as the default and is kept")

  -- a font that is gone is drawn as the game's own and stays chosen
  assert(MT.Set("font", "Gone Font") and MT.Get("font") == "Gone Font")
  assert(PL.Snapshot().mapFontFallback == true and c.TwichUIDB.ui.pinsMapText.font == "Gone Font")
  for _, fs in ipairs(list) do assert(fs.font[1] == "Fonts\\FRIZQT__.TTF") end

  -- the window's reset leaves the map text alone, and the map text's reset leaves the rest alone
  local labelsBefore, pinsN = PL.Pref("labels"), PN.LocalCount()
  PL.Reset()
  assert(MT.Get("outline") == "thick", "resetting the window doesn't touch the map text")
  assert(PL.SetPref("minimapLabels", "always") and not PL.SetPref("minimapLabels", "sometimes"))
  MT.Reset()
  assert(c.TwichUIDB.ui.pinsMapText == nil and MT.Get("size") == 10 and MT.Get("outline") == "none" and MT.Get("shadow") == true)
  assert(PL.Pref("labels") == labelsBefore and PL.Pref("minimapLabels") == "always" and PN.LocalCount() == pinsN, "only the text is reset")
  for _, fs in ipairs(list) do assert(fs.font[2] == 10 and fs.font[3] == "" and fs.shadow[1] == 1) end
  assert(PL.SetPref("minimapLabels", "off"))
end
-- picking the party pin's click for local pins swaps them
assert(PL.SetPref("localClick", "altshift") and PL.Pref("partyClick") == "alt")
assert(PL.SetPref("localClick", "alt") and PL.Pref("partyClick") == "altshift")
assert(not PL.SetPref("localClick", "ctrl"), "Ctrl-click isn't offered")

---------------------------------------------------------------------------
-- 7. Troubleshooting names no pin, place or player
---------------------------------------------------------------------------
local report = R.Diag.Build()
local from = report:find("== Party pins ==", 1, true)
assert(from, "the section is there")
local section = report:sub(from, report:find("\n== ", from + 5, true) or #report)
for _, needle in ipairs({ "Ore", "Rendezvous", "Westfall", "Elwynn", "Pal", "Stonebrook", "Rich", "1429", "1436" }) do
  assert(not section:find(needle, 1, true), "the report must not hold " .. needle)
end
assert(section:find("protocol 1", 1, true))

---------------------------------------------------------------------------
-- 7b. The minimap
---------------------------------------------------------------------------
do
  local MM = R.PinsMinimap
  local function tick() MM.Update(nil, 1) end
  local function at(token)
    for _, s in ipairs(MM.State()) do if s.token == token then return s end end
  end
  local function near(a, b) return a ~= nil and math.abs(a - b) < 0.51 end   -- half a pixel is the placing step

  assert(MM.Snapshot().active and MM.Snapshot().running, "on with the feature, with pins to show")
  -- the ore (local, 40 yards west of the player; the minimap sees 100 yards over 70 pixels, so 0.7 pixels a yard)
  MINI.map, MINI.x, MINI.y, MINI.radius, MINI.rotate, MINI.facing = 1429, 0.5, 0.5, 100, false, 0
  tick()
  local s = at("local:" .. ore.id)
  assert(s and s.shown and near(s.x, -28) and near(s.y, 0) and s.yards == 40, "west of you is left of the middle")
  -- north is up (the map's y runs south)
  local north = assert(PN.AddLocal({ map = 1429, x = 5000, y = 4500, name = "North" }))
  local south = assert(PN.AddLocal({ map = 1429, x = 5000, y = 5500, name = "South" }))
  tick()
  s = at("local:" .. north.id); assert(s.shown and near(s.x, 0) and near(s.y, 14), "20 yards north is 14 pixels up")
  s = at("local:" .. south.id); assert(s.shown and near(s.x, 0) and near(s.y, -14), "20 yards south is 14 pixels down")

  -- nothing moves when nothing changed
  local moves = MM.Snapshot().moves
  tick(); tick()
  assert(MM.Snapshot().moves == moves, "a button is moved only when its place changed")
  MINI.x = 0.5 + 0.0001   -- 0.04 yards east: 0.03 of a pixel, far under the half pixel step
  tick()
  assert(MM.Snapshot().moves == moves, "a change under the step moves nothing")
  MINI.x = 0.5 + 0.01     -- 4 yards east: nearly 3 pixels
  tick()
  assert(MM.Snapshot().moves > moves and near(at("local:" .. ore.id).x, -30.8), "walking east puts a pin to the west further left")
  MINI.x = 0.5; tick()

  -- the minimap turns with you: facing west puts west up and north to the right
  MINI.rotate, MINI.facing = true, math.pi / 2
  tick()
  s = at("local:" .. ore.id); assert(near(s.x, 0) and near(s.y, 28), "facing west, west is up")
  s = at("local:" .. north.id); assert(near(s.x, 14) and near(s.y, 0), "facing west, north is to the right")
  MINI.facing = math.pi   -- facing south: north is down, west is to the right
  tick()
  s = at("local:" .. north.id); assert(near(s.x, 0) and near(s.y, -14), "facing south, north is down")
  s = at("local:" .. ore.id); assert(near(s.x, 28) and near(s.y, 0), "facing south, west is right")
  MINI.facing = nil
  tick()
  assert(not at("local:" .. ore.id).shown and MM.Snapshot().shown == 0, "an unreadable facing places nothing")
  MINI.rotate, MINI.facing = false, 0
  tick()
  assert(at("local:" .. ore.id).shown)

  -- range: the zoom decides what is on it; the rim hides what is past it, with no arrow
  MINI.radius = 20; tick()
  assert(not at("local:" .. ore.id).shown, "40 yards is out of a 20 yard view")
  assert(not at("local:" .. north.id).shown, "20 yards is at the rim, which is kept clear")
  MINI.radius = 50; tick()
  s = at("local:" .. ore.id); assert(s.shown and near(s.x, -56), "zoomed in, the same pin is further out")
  MINI.radius = 100

  -- party pins show with their badge, and a pin removed from your map isn't on the minimap
  local party = assert(PS.CreateParty({ map = 1429, x = 5500, y = 5000, name = "Meet here", color = "river" }))
  tick()
  s = at("party:" .. party.key); assert(s and s.shown and near(s.x, 14) and s.yards == 20, "a party pin, 20 yards east")
  assert(PN.Dismiss(party.key))
  tick()
  assert(not at("party:" .. party.key), "removed from my map: not on the minimap")
  assert(PN.Restore(party.key)); tick()
  assert(at("party:" .. party.key).shown)

  -- parents and strangers: a pin on a map you are inside is placed through that map; one on another map never is
  MINI.map, MINI.x, MINI.y, MINI.radius = 1453, 0.5, 0.5, 200   -- Stormwind, inside Elwynn: the player is at (0.375, 0.25) on it
  tick()
  s = at("local:" .. ore.id); assert(s and s.shown and near(s.x, 3.5) and near(s.y, -35) and s.yards == 100,
    "a pin on the map you are inside: 10 yards east, 100 yards south")
  MINI.map, MINI.x, MINI.y, MINI.radius = 1436, 0.5, 0.5, 100   -- Westfall: a sibling of Elwynn
  tick()
  assert(not at("local:" .. ore.id).shown and not at("party:" .. party.key).shown, "a sibling map's pins are never placed")
  local westfall = nil
  for _, e in ipairs(MM.State()) do
    if PN.FindLocal(e.token:sub(7)) and PN.FindLocal(e.token:sub(7)).map == 1436 then westfall = e end
  end
  assert(westfall and westfall.shown and near(westfall.x, 0) and near(westfall.y, 0), "the pin copied from Westfall, where you stand")
  MINI.map = 947   -- a map with no size known: nothing to place
  tick()
  assert(MM.Snapshot().shown == 0)
  MINI.map = nil   -- no map at all (a dungeon)
  tick()
  assert(MM.Snapshot().shown == 0 and not at("local:" .. ore.id).shown, "no map, no pins")
  MINI.map, MINI.x, MINI.y = 1429, 0.5, 0.5

  -- a hidden minimap costs nothing and a shown one catches up
  MINI.visible = false
  local ticks, moves2 = MM.Snapshot().ticks, MM.Snapshot().moves
  tick()
  assert(MM.Snapshot().moves == moves2)
  MINI.visible = true; tick()
  assert(at("local:" .. ore.id).shown)

  -- throttled: a small elapsed time does nothing
  local t0 = MM.Snapshot().ticks
  MM.Update(nil, 0.01); MM.Update(nil, 0.01)
  assert(MM.Snapshot().ticks == t0, "10 updates a second, not one per frame")
  MM.Update(nil, 0.2)
  assert(MM.Snapshot().ticks == t0 + 1)

  -- a secret view radius is never compared: the zoom setting gives the radius instead (and the report says so)
  MINI.map, MINI.x, MINI.y, MINI.radius = 1429, 0.5, 0.5, SECRET
  tick()
  local snap = MM.Snapshot()
  assert(snap.radiusKind == "secret" and snap.radiusSource == "zoom" and snap.now == "ok", "secret radius: the zoom table, said so")
  s = at("local:" .. ore.id); assert(s.shown and near(s.x, -28), "outdoors at zoom 4 is 100 yards: the same place as before")
  MINI.zoom = 2   -- not the outdoor zoom: indoors, 90 yards
  tick()
  s = at("local:" .. ore.id); assert(s.shown and near(s.x, -40 * 70 / 90), "indoors the view is 90 yards")
  MINI.zoom = 4
  -- the minimap has no map of its own to give: the player's map is used, and the report names the source
  MINI.radius, MINI.noMapID, MINI.best = 100, true, 1429
  tick()
  snap = MM.Snapshot()
  assert(snap.mapKind == "nil" and snap.mapSource == "player" and at("local:" .. ore.id).shown, "no minimap map: the player's")
  MINI.noMapID, MINI.best = nil, nil
  -- nothing usable: nothing is placed, and the reason is the report's
  MINI.radius, MINI.zoom = SECRET, nil
  tick()
  snap = MM.Snapshot()
  assert(snap.now == "no-radius" and snap.last == "no-radius" and snap.shown == 0, "no radius to use")
  assert(snap.radiusSource == "none" and not at("local:" .. ore.id).shown)
  MINI.radius, MINI.zoom = 100, 4
  -- the first pin's own readings, for the report
  MINI.map = 1429
  tick()
  snap = MM.Snapshot()
  assert(snap.probe and snap.probe.related and snap.probe.sized and snap.probe.position == "yes", "map related, sized, and you are on it")
  MINI.map = 1436
  snap = MM.Snapshot()
  assert(snap.probe and not snap.probe.related, "a pin's map that isn't the minimap's or a parent is said so")
  MINI.map = 1429
  -- an error inside an update is caught: counted, shown once, never repeated every update
  rawset(Minimap, "GetWidth", function() error("boom") end)
  local before = #caught
  tick(); tick(); tick()
  rawset(Minimap, "GetWidth", function() return 140 end)
  snap = MM.Snapshot()
  assert(snap.errors == 3 and snap.last == "error" and #caught == before + 1, "caught three times, shown once")
  tick()
  assert(MM.Snapshot().last == "ok" and at("local:" .. ore.id).shown, "and it carries on once the reading is back")

  -- the setting: off takes the updater away; on brings it back
  assert(R.PinsLook.SetPref("minimap", false))
  assert(not MM.Snapshot().active and not MM.Snapshot().running and #MM.State() == 0, "no updater while it is off")
  assert(R.PinsLook.SetPref("minimap", true))
  assert(MM.Snapshot().active and MM.Snapshot().running)
  tick()
  assert(at("local:" .. ore.id).shown)
  -- the window being dragged (a saved preference) doesn't rebuild it
  local rebuilds = MM.Snapshot().rebuilds
  R.PinsLook.SetPref("position", { x = 5, y = 5 })
  assert(MM.Snapshot().rebuilds == rebuilds)

  -- names beside minimap pins: off as before; on hover only for the selected pin; always for all
  local function namesShown()
    local n = 0
    for _, st in ipairs(MM.State()) do if st.name then n = n + 1 end end
    return n
  end
  assert(R.PinsLook.Pref("minimapLabels") == "off" and namesShown() == 0, "no names on the minimap unless asked")
  assert(R.PinsLook.SetPref("minimapLabels", "always") and namesShown() == #MM.State() and namesShown() > 1)
  assert(at("local:" .. ore.id).name == ore.name, "a name is the pin's own, plain text: " .. tostring(at("local:" .. ore.id).name))
  PN.Select(nil)
  assert(R.PinsLook.SetPref("minimapLabels", "hover") and namesShown() == 0, "on hover: none until hovered or selected")
  PN.Select("local:" .. ore.id)
  assert(namesShown() == 1 and at("local:" .. ore.id).name == ore.name, "the selected pin shows its name")
  PN.Select(nil)
  assert(namesShown() == 0)
  assert(R.PinsLook.SetPref("minimapLabels", "off"))

  -- troubleshooting: counts, no names or places
  local rep = R.Diag.Build()
  local line = rep:match("\nminimap: [^\n]+")
  assert(line and line:find("could be shown", 1, true), "the report has a minimap line")
  local inputs = rep:match("\nminimap inputs now: [^\n]+")
  assert(inputs and inputs:find("view radius: number from client", 1, true) and inputs:find("yards)", 1, true), "and one for what it reads now")
  assert(rep:find("\nminimap updates by result: ", 1, true) and rep:find("errors caught: 3", 1, true))
  for _, needle in ipairs({ "North", "South", "Meet here", "Ore", "1429", "1453" }) do assert(not line:find(needle, 1, true), needle) end

  PN.RemoveLocal(north.id); PN.RemoveLocal(south.id)
  PS.RemoveForParty(party.key)
end

---------------------------------------------------------------------------
-- 8. Off: TwichUI's handlers and pins leave the map; the game's and others' are untouched
---------------------------------------------------------------------------
local other = function() return false end
WMF.clicks[other] = 90
c.TwichUIDB.modules.partyPins = false
PS.Refresh(); PM.Refresh()
local left = 0
for _ in pairs(WMF.clicks) do left = left + 1 end
assert(left == 1 and WMF.clicks[other] == 90, "only TwichUI's handler was removed")
assert(next(WMF.providers) == nil and next(WMF.cursors) == nil and not PM.Snapshot().installed)
R.PinsMinimap.Refresh()
assert(not R.PinsMinimap.Snapshot().active and not R.PinsMinimap.Snapshot().running and R.PinsMinimap.Snapshot().shown == 0,
  "off: no minimap pins and no updater")
assert(PN.SharedCount() == 0 and PN.LocalCount() == pinsBefore, "party pins dropped; local pins kept")
assert(not PW.Show(), "the window says it is off")

print("PARTY PINS UI TESTS PASSED")
