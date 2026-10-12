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
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Obj() end end
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
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Editor.lua", "pins/Window.lua", "pins/Broker.lua",
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
assert(PN.SharedCount() == 0 and PN.LocalCount() == pinsBefore, "party pins dropped; local pins kept")
assert(not PW.Show(), "the window says it is off")

print("PARTY PINS UI TESTS PASSED")
