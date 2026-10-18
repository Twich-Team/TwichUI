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
local FRAMES = {}
c.CreateFrame = function(kind, name)
  local o = Obj()
  rawset(o, "kindOf", kind)
  FRAMES[#FRAMES + 1] = o
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

local brokers = {}
local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
LDB.NewDataObject = function(_, name, o) brokers[name] = o; return o end
for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Minimap.lua", "pins/Editor.lua", "pins/Window.lua",
  "pins/BrokerMenu.lua", "pins/Broker.lua",
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
-- 2b. The new pin window's look: its own, applied to its frame, never the pin window's
---------------------------------------------------------------------------
do
  local drawn = {}
  rawset(ed, "SetBackdropColor", function(s, r, g, b, a) drawn.bg = { r, g, b, a } end)
  rawset(ed, "SetSize", function(s, w, h) drawn.w, drawn.h = w, h end)
  local EL = PL.EditorLook
  assert(EL ~= PL.Look and EL.DEFAULTS ~= PL.Look.DEFAULTS, "its own look, not the pin window's table")
  assert(EL.Get("bgColor") == PL.Look.Get("bgColor") and EL.Get("borderColor") == PL.Look.Get("borderColor"),
    "starts out like the pin window")
  assert(not (c.TwichUIDB.ui and c.TwichUIDB.ui.pinsEditorLook), "nothing saved until a choice is made")

  keys(true, false, false)
  assert(click("LeftButton", 0.4, 0.5) and PE.IsOpen())
  assert(drawn.bg and math.abs(drawn.bg[4] - 0.98) < 1e-9 and drawn.w == 300 + 2 and drawn.h == 242 + 2,
    "drawn with the look's background, a 1 pixel border making the window 2 larger")
  -- a change redraws the open window at once
  assert(EL.Set("bgOpacity", 40) and EL.Set("borderSize", 6))
  assert(math.abs(drawn.bg[4] - 0.40) < 1e-9 and drawn.w == 300 + 12 and drawn.h == 242 + 12, "a thicker border makes it larger")
  assert(c.TwichUIDB.ui.pinsEditorLook.bgOpacity == 40)
  assert(c.TwichUIDB.ui.pinsLook == nil or c.TwichUIDB.ui.pinsLook.bgOpacity == nil, "the pin window's look is not the editor's")
  assert(PL.Look.Get("bgOpacity") == PL.Look.DEFAULTS.bgOpacity and PL.MenuLook.Get("bgOpacity") == PL.MenuLook.DEFAULTS.bgOpacity)
  -- and the pin window's look doesn't change it
  PL.Look.Set("bgOpacity", 70)
  assert(EL.Get("bgOpacity") == 40)
  PL.Look.Reset()
  assert(ed.name:GetText() ~= nil and PE.IsOpen(), "restyling leaves the open editor as it was")
  -- an unusable saved value is read as the default and kept
  c.TwichUIDB.ui.pinsEditorLook.bgTexture = "Some Pack Texture"
  assert(EL.Get("bgTexture") == "Some Pack Texture" and c.TwichUIDB.ui.pinsEditorLook.bgTexture == "Some Pack Texture")
  c.TwichUIDB.ui.pinsEditorLook.borderOpacity = "bad"
  assert(EL.Get("borderOpacity") == EL.DEFAULTS.borderOpacity and c.TwichUIDB.ui.pinsEditorLook.borderOpacity == "bad")
  ed.name.scripts.OnEscapePressed(ed.name)

  EL.Reset()
  assert(c.TwichUIDB.ui.pinsEditorLook == nil, "reset: nothing saved")
  assert(PL.Snapshot().editorBg == "solid" and PL.Snapshot().editorBorder == "solid")

  -- Preview: the real window with a made-up pin; Save does nothing; pressing again closes it
  local before = PN.LocalCount()
  PE.TogglePreview()
  assert(PE.IsOpen() and ed.title.text == "New pin" and ed.save.enabled == false and ed.status.text:find("preview"))
  ed.save.scripts.OnClick(ed.save)
  ed.name.scripts.OnEnterPressed(ed.name)
  assert(PN.LocalCount() == before and sent() == 0 and PE.IsOpen(), "Save in a preview makes and sends nothing")
  PE.TogglePreview()
  assert(not PE.IsOpen(), "pressed again, it closes")
  -- a real pin being placed is not taken over by the preview
  assert(click("LeftButton", 0.4, 0.5) and PE.IsOpen())
  ed.name:SetText("Keep me")
  PE.TogglePreview()
  assert(PE.IsOpen() and ed.name:GetText() == "Keep me" and ed.save.enabled ~= false, "the real editor is left alone")
  ed.name.scripts.OnEscapePressed(ed.name)
  assert(not PE.IsOpen() and PN.LocalCount() == before)
  -- a real pin opened over a preview replaces it, and can be saved
  PE.TogglePreview()
  assert(click("LeftButton", 0.4, 0.5) and PE.IsOpen() and ed.save.enabled ~= false)
  ed.name.scripts.OnEscapePressed(ed.name)
  keys(false, false, false)
  rawset(ed, "SetBackdropColor", nil); rawset(ed, "SetSize", nil)
end

-- An EllesmereUI texture's visible line is a part of its edge cell, so the window makes room for the line,
-- not for the whole thickness (a 16 pixel Pixels Textured border isn't 16 pixels of empty margin).
do
  local drawn = {}
  rawset(ed, "SetSize", function(s, w, h) drawn.w, drawn.h = w, h end)
  local reach = true
  c.EllesmereUI = {
    PP = {},
    GetBorderTextureList = function() return { { key = "pixels-textured", name = "Pixels Textured" } } end,
    ResolveBorderTexture = function(k) return k == "pixels-textured" and "p" or nil end,
    BorderPxStep = function() return 2 end,
    BorderLegacyPx = function() return 16 end,
    GetBorderDefaultSize = function() return 2 end,
    ApplyBorderStyle = function() end,
    -- the cell is centered on the edge and the line starts 0.321 of the cell in from its outer edge
    BorderReach = reach and function(_, _, _, _, _, _, _, _, edgePx) return edgePx / 2 - 0.321 * edgePx end or nil,
  }
  local EL = PL.EditorLook
  assert(EL.Set("borderTexture", "eui:pixels-textured") and EL.Set("borderSize", 16))
  keys(true, false, false)
  assert(click("LeftButton", 0.4, 0.5) and PE.IsOpen())
  assert(drawn.w == 300 + 2 * 4, "16 pixels of border: room for the line (3 and a pixel), not 16: " .. tostring(drawn.w))
  assert(EL.Set("borderSize", 8))
  assert(drawn.w == 300 + 2 * 3, "a smaller size takes less room: " .. tostring(drawn.w))
  c.EllesmereUI.BorderReach = nil
  assert(EL.Set("borderSize", 16))
  assert(drawn.w == 300 + 2 * 16, "without EllesmereUI's reach the whole thickness is kept clear")
  c.EllesmereUI = nil
  assert(EL.Set("borderSize", 12))
  assert(drawn.w == 300 + 2 * 12, "without EllesmereUI the plain line is drawn and takes its thickness")
  ed.name.scripts.OnEscapePressed(ed.name)
  EL.Reset()
  keys(false, false, false)
  rawset(ed, "SetSize", nil)
end

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
assert(localActs["Show on map"] and localActs["Set waypoint"] and localActs["Edit pin..."] and localActs["Remove pin"])
assert(not localActs["Remove for entire party..."] and not localActs["Remove from my map"])
local mineE = { kind = "party", pin = mine, token = "party:" .. mine.key }
local mineActs = labels(PW.Actions(mineE))
assert(mineActs["Remove for entire party..."] and mineActs["Remove for entire party..."].enabled and mineActs["Edit pin..."])
assert(mineActs["Remove from my map"] and mineActs["Save to my pins..."])
local palE = { kind = "party", pin = pal, token = "party:" .. pal.key }
local palActs = labels(PW.Actions(palE))
assert(not palActs["Remove for entire party..."] and not palActs["Edit pin..."], "someone else's pin: no owner actions offered")
-- paused in a raid: your own pin's editor still opens; Keep saves and sends nothing; a rename is refused with why
do
  local inRaid = c.IsInRaid
  c.IsInRaid = function() return true end
  local acts = labels(PW.Actions(mineE))
  assert(acts["Edit pin..."].enabled and not acts["Remove for entire party..."].enabled, "Edit stays offered for Keep; removing for the party waits")
  assert(PE.OpenEdit(mineE) and ed.save.enabled ~= false and ed.status.text:find("Keep can still be changed"), ed.status.text)
  local wasKept, before = PN.IsKept(mine), sent()
  ed.keep.scripts.OnClick(ed.keep); ed.save.scripts.OnClick(ed.save)
  assert(PN.IsKept(mine) ~= wasKept and sent() == before and not PE.IsOpen(), "Keep changed, nothing sent")
  local name = mine.name
  assert(PE.OpenEdit(mineE))
  ed.name:SetText("Renamed in a raid"); ed.save.scripts.OnClick(ed.save)
  assert(mine.name == name and PE.IsOpen() and ed.status.text:find("paused") and sent() == before, "a rename waits: " .. ed.status.text)
  ed.name.scripts.OnEscapePressed(ed.name)
  assert(PS.UpdateParty(mine.key, { kept = wasKept }))
  c.IsInRaid = inRaid
end
assert(palActs["Remove from my map"] and palActs["Save to my pins..."] and palActs["Set waypoint"])
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
-- save Pal's pin to my pins: the editor opens filled in, nothing is made until Save; remove Pal's from my map; restore it
local savedBefore, sentBefore = PN.LocalCount(), sent()
palActs["Save to my pins..."].run()
assert(PE.IsOpen() and ed.title.text == "Save to my pins" and PN.LocalCount() == savedBefore and sent() == sentBefore, "reviewed first")
ed.save.scripts.OnClick(ed.save)
assert(PN.LocalPins()[#PN.LocalPins()].copiedFrom == "Pal Stonebrook" and PN.LocalPins()[#PN.LocalPins()].kept == true)
assert(sent() == sentBefore, "a local copy is never sent")
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
-- 7c. The data bar entry and its menu
---------------------------------------------------------------------------
do
  local BM, BR = R.PinsBrokerMenu, PL.Bar
  local obj = assert(brokers["TwichUI Party Pins"], "listed once a data bar provides LibDataBroker")
  assert(R.PinsBroker.Available())
  -- pins that arrived in the sections above are being pointed out (their timers were thrown away): end that
  assert(obj.text:find("New pin"), "a pin that arrived from the party was pointed out")
  BR.Set("flash", false)
  BR.Reset()

  -- what it says, its icon and its color: the defaults are what it always was, and nothing is saved until a choice
  assert(c.TwichUIDB.ui.pinsBroker == nil and c.TwichUIDB.ui.pinsBrokerMenu == nil, "nothing saved until a choice is made")
  local total, party = PW.Count()
  assert(obj.text:find("pin") and obj.icon == c.TwichUI.PATH .. "media\\textures\\map-pins-broker", "the count and TwichUI's own icon")
  assert(obj.text:find(tostring(total), 1, true) and obj.text:find(("%d party"):format(party), 1, true))
  assert(BR.Set("text", "number") and obj.text == tostring(total), "the number alone")
  assert(BR.Set("text", "label") and obj.text == "Map Pins", "the words")
  assert(BR.Set("text", "none") and obj.text == "" and obj.icon, "no words: the icon stays, so there is something to click")
  assert(BR.Set("icon", false) and obj.icon, "still there while there is no text")
  assert(BR.Set("text", "label") and obj.icon == nil and obj.text == "Map Pins", "the icon can be left off")
  assert(not BR.Set("text", "shouting") and not BR.Set("icon", "no") and not BR.Set("color", "red") and BR.Get("text") == "label",
    "an unusable choice is refused")
  assert(BR.Set("customColor", true) and obj.text == "|cffc9a34aMap Pins|r", "colored only once asked for")
  assert(BR.Set("color", "ff4488cc") and obj.text == "|cff4488ccMap Pins|r")
  assert(BR.Set("customColor", false) and obj.text == "Map Pins", "off: the data bar's own color")
  c.TwichUIDB.ui.pinsBroker.text = "huge"
  assert(BR.Get("text") == "count" and c.TwichUIDB.ui.pinsBroker.text == "huge", "an unusable saved value reads as the default and is kept")
  BR.Reset()
  assert(c.TwichUIDB.ui.pinsBroker == nil and obj.icon and obj.text:find("pin"), "reset: back to the defaults, nothing saved")

  -- the menu: a click opens it, not the window
  PW.Hide()
  local host = Obj()
  obj.OnClick(host, "LeftButton")
  assert(BM.IsOpen() and not PW.IsOpen(), "a click opens the pin menu")
  assert(BM.Snapshot().rows == total, "one row for each pin on your map")
  local function rowFor(name, kind)   -- kind: "local" or "party", when two pins share a name (a kept copy)
    for _, f in ipairs(FRAMES) do
      local e = rawget(f, "entry")
      if rawget(f, "pick") and e and e.pin.name == name and (kind == nil or e.kind == kind) then return f end
    end
  end
  local function click(btn) btn.scripts.OnClick(btn) end
  obj.OnClick(host, "LeftButton")
  assert(not BM.IsOpen(), "the same click closes it")
  obj.OnClick(host, "LeftButton")

  -- rename in place: nothing changes until Enter, Esc leaves the name as it was, an empty name is refused
  local oreRow = assert(rowFor("Ore vein"), "the local pin is listed with its name")
  local oreId = oreRow.entry.pin.id
  local framesBefore = #FRAMES
  click(oreRow.nameBtn)
  local box
  for i = framesBefore + 1, #FRAMES do if FRAMES[i].kindOf == "EditBox" then box = FRAMES[i] end end
  assert(box and box:GetText() == "Ore vein" and BM.Snapshot().editing, "the name becomes a box holding the old name")
  box:SetText("Copper vein")
  box.scripts.OnEscapePressed(box)
  assert(PN.FindLocal(oreId).name == "Ore vein" and not BM.Snapshot().editing, "Esc: as it was")
  click(oreRow.nameBtn)
  box:SetText("   ")
  box.scripts.OnEnterPressed(box)
  assert(PN.FindLocal(oreId).name == "Ore vein" and lastNotice():find("needs a name"), "an empty name is refused, with the reason")
  local before = sent()
  click(oreRow.nameBtn)
  box:SetText("|cffff0000Copper|r vein")
  box.scripts.OnEnterPressed(box)
  assert(PN.FindLocal(oreId).name == "Copper vein" and sent() == before, "renamed, as plain text; a local pin sends nothing")
  FlushTimers()
  assert(rowFor("Copper vein") and not rowFor("Ore vein"), "the list follows")

  -- recolor: the swatch opens a row of the pin colors
  oreRow = rowFor("Copper vein")
  local color0 = oreRow.entry.pin.color
  framesBefore = #FRAMES
  click(oreRow.pick)
  local picker
  for i = framesBefore + 1, #FRAMES do if rawget(FRAMES[i], "swatches") then picker = FRAMES[i] end end
  assert(picker and #picker.swatches == #PN.COLORS and picker.shown, "a swatch for each pin color")
  local choice
  for _, b in ipairs(picker.swatches) do if b.id ~= color0 then choice = b break end end
  click(choice)
  assert(PN.FindLocal(oreId).color == choice.id and not picker.shown, "recolored, and the picker closes")

  -- someone else's party pin: no rename or recolor, and remove takes it off my map only
  local palRow = assert(rowFor("Westfall camp", "party"), "party pins are listed too")
  before = sent()
  framesBefore = #FRAMES
  click(palRow.nameBtn)
  assert(not BM.Snapshot().editing and lastNotice():find("Only the player who made it"), "not yours to rename: the reason")
  click(palRow.pick)
  assert(not picker.shown and PN.Shared(pal.key).color == "river", "nor to recolor")
  click(palRow.remove)
  assert(PN.IsDismissed(pal.key) and PN.Shared(pal.key) and sent() == before, "taken off my map; nothing sent and it is still the party's")
  FlushTimers()
  assert(not rowFor("Westfall camp", "party"), "and out of the list")
  assert(PN.Restore(pal.key))

  -- my own party pin: rename and recolor are sent once each; remove asks first
  local camp = assert(PS.CreateParty({ map = 1429, x = 3000, y = 3000, name = "Camp", color = "gold" }))
  FlushTimers()
  local campRow = assert(rowFor("Camp"))
  before = sent()
  click(campRow.nameBtn)
  box:SetText("Base camp")
  box.scripts.OnEnterPressed(box)
  assert(PN.Shared(camp.key).name == "Base camp" and sent() == before + 1, "a rename of your own party pin is sent once")
  FlushTimers()
  campRow = rowFor("Base camp")
  click(campRow.pick)
  click(picker.swatches[3])
  assert(PN.Shared(camp.key).color == PN.COLORS[3][1] and sent() == before + 2)
  popups[#popups] = nil
  local askedBefore = #popups
  click(campRow.remove)
  assert(#popups == askedBefore + 1 and popups[#popups].key == "TWICHUI_PINS_REMOVE_PARTY", "removing for the party asks first")
  assert(PN.Shared(camp.key) and sent() == before + 2, "nothing sent before confirming")
  c.StaticPopupDialogs.TWICHUI_PINS_REMOVE_PARTY.OnAccept()
  assert(not PN.Shared(camp.key) and sent() == before + 3)
  FlushTimers()

  -- a local pin's remove button deletes it (a pin that went meanwhile is refused with a sentence)
  local extra = assert(PN.AddLocal({ map = 1429, x = 20, y = 20, name = "Scratch" }))
  FlushTimers()
  local extraRow = assert(rowFor("Scratch"))
  assert(PN.RemoveLocal(extra.id))
  click(extraRow.remove)
  assert(lastNotice():find("no longer there"), "checked again when it runs")
  extra = assert(PN.AddLocal({ map = 1429, x = 20, y = 20, name = "Scratch" }))
  FlushTimers()
  click(rowFor("Scratch").remove)
  assert(not PN.FindLocal(extra.id), "a local pin is deleted")
  FlushTimers()

  -- Clear unprotected pins asks first, says what happens, and keeps what is the party's (kept pins are in
  -- tests/test_pins_keep.lua; the copy saved above is kept, so it is let go of here to see the plain case)
  for _, p in ipairs(PN.LocalPins()) do assert(PN.UpdateLocal(p.id, { kept = false })) end
  local keptLocal = {}
  for _, p in ipairs(c.TwichUIDB.pins.list) do
    local copy = {}; for k, v in pairs(p) do copy[k] = v end
    keptLocal[#keptLocal + 1] = copy
  end
  local onMap = {}
  for _, p in ipairs(PN.SharedPins()) do if not PN.IsDismissed(p.key) then onMap[#onMap + 1] = p.key end end
  assert(#keptLocal > 0 and #onMap > 0)
  before = sent()
  local asked = #popups
  local clear = assert(c.TwichUIPinsMenu.clear, "a Clear unprotected pins link")
  click(clear)
  assert(not BM.IsOpen(), "the menu is put away for the question")
  assert(#popups == asked + 1 and popups[#popups].key == "TWICHUI_PINS_CLEAR_ALL", "asks first")
  local text = popups[#popups].text
  assert(text:find(tostring(#keptLocal), 1, true) and text:find("local") and text:find("party") and text:find("nothing is sent"),
    "says what will be deleted and what only leaves the map")
  assert(PN.LocalCount() == #keptLocal and sent() == before, "nothing changed before confirming")
  c.StaticPopupDialogs.TWICHUI_PINS_CLEAR_ALL.OnAccept()
  assert(PN.LocalCount() == 0, "local pins deleted")
  for _, key in ipairs(onMap) do assert(PN.Shared(key) and PN.IsDismissed(key), "party pins are off my map, not gone") end
  assert(sent() == before, "clearing sends nothing")
  c.StaticPopupDialogs.TWICHUI_PINS_CLEAR_ALL.OnAccept()
  assert(PN.LocalCount() == 0 and sent() == before, "accepting twice does nothing more")
  -- the menu with nothing in it says how to start, and its clear link is greyed out
  BM.Open(host)
  assert(c.TwichUIPinsMenu.clear.enabled == false and c.TwichUIPinsMenu.empty.shown)
  BM.Close()

  -- put the state back for what follows
  for _, key in ipairs(onMap) do PN.Restore(key) end
  c.TwichUIDB.pins.list = keptLocal
  PN.Changed()
  FlushTimers()
  assert(PN.LocalCount() == #keptLocal)

  -- Keep: the menu groups kept pins first with a padlock, the editor chooses it, Clear unprotected pins is
  -- scoped to what it asked, the window filters and explains, and the marker's tooltip says it
  do
    local ed = c.TwichUIPinEditor
    local baseList = c.TwichUIDB.pins.list
    local hiddenHere = {}
    for _, p in ipairs(PN.SharedPins()) do
      if not PN.IsDismissed(p.key) and not PN.IsKept(p) then hiddenHere[#hiddenHere + 1] = p.key end
    end
    PN.DismissAll()                                  -- the party pins are off the map for this: only the list below
    local list = {}
    c.TwichUIDB.pins.list = list
    c.TwichUIDB.pins.nextId = 100
    local ordinary = assert(PN.AddLocal({ map = 1429, x = 100, y = 100, name = "Ore stop" }))
    local vendor = assert(PN.AddLocal({ map = 1429, x = 4520, y = 6380, name = "Reagent vendor", kept = true }))
    FlushTimers()

    -- one group only: no headings
    local function countText(text)   -- the "Kept" filter button has that word too, so headings are counted against it
      local n = 0
      for _, fs in ipairs(MAPSTRINGS) do if fs.text == text and fs.shown then n = n + 1 end end
      return n
    end
    local function shownText(text) return countText(text) > 0 end
    local function rowsNow()
      local out = {}
      for _, f in ipairs(FRAMES) do
        if rawget(f, "pick") and rawget(f, "nameBtn") and rawget(f, "entry") and f.shown ~= false then out[#out + 1] = f end
      end
      return out
    end
    local ys = setmetatable({}, { __mode = "k" })
    for _, f in ipairs(FRAMES) do
      if rawget(f, "pick") and rawget(f, "nameBtn") then
        rawset(f, "SetPoint", function(self, point, _, _, _, y) if point == "TOPLEFT" then ys[self] = -(y or 0) end end)
      end
    end
    BM.Open(host)
    local vendorRow = assert(rowFor("Reagent vendor"))
    local oreRow = assert(rowFor("Ore stop"))
    assert(vendorRow.remove.lock.shown == true and vendorRow.remove.text.shown == false, "a kept row has a padlock where the x was")
    assert(oreRow.remove.lock.shown == false and oreRow.remove.text.shown == true, "an ordinary row keeps its x")
    assert(shownText("Other pins"), "headings when both groups have pins")
    local keptWords = countText("Kept")
    assert(ys[vendorRow] < ys[oreRow], "kept pins first " .. tostring(ys[vendorRow]) .. " " .. tostring(ys[oreRow]))

    -- its tooltip: a title and what to do
    local tip = vendorRow.remove.twichuiTip
    local body = tip.body(vendorRow.remove)
    assert(tip.title == "Kept pin" and body:find("Protected from deletion and cleanup.", 1, true) and body:find("Edit this pin to unlock it.", 1, true),
      "the padlock explains itself")
    tip.body(oreRow.remove)
    assert(oreRow.remove.twichuiTip.title == nil and oreRow.remove.twichuiTip.body(oreRow.remove):find("Delete this pin"), "an ordinary x as before")

    -- the padlock opens the editor and changes nothing; the editor shows Keep on
    local countBefore, sentBefore = PN.LocalCount(), sent()
    click(vendorRow.remove)
    assert(not BM.IsOpen() and PE.IsOpen() and ed.title.text == "Edit pin", "it opens the editor")
    assert(PN.IsKept(vendor) and PN.LocalCount() == countBefore, "and neither unlocks nor deletes")
    assert(ed.keep:IsOn() == true, "the box shows the pin as kept")
    -- a draft until Save: unticking and cancelling leaves it as it was
    ed.keep.scripts.OnClick(ed.keep)
    assert(ed.keep:IsOn() == false and PN.IsKept(vendor), "unticked in the draft only")
    ed.name.scripts.OnEscapePressed(ed.name)
    assert(not PE.IsOpen() and PN.IsKept(vendor) and vendor.name == "Reagent vendor", "Cancel changes nothing")
    -- rename and recolor while kept
    assert(PE.OpenEdit({ kind = "local", pin = vendor, token = "local:" .. vendor.id }))
    ed.name:SetText("Orgrimmar reagents")
    ed.swatches[4].scripts.OnClick(ed.swatches[4])
    ed.save.scripts.OnClick(ed.save)
    assert(vendor.name == "Orgrimmar reagents" and vendor.color == PN.COLORS[4][1] and PN.IsKept(vendor) and not PE.IsOpen(),
      "renamed and recolored, still kept")
    assert(sent() == sentBefore, "a local pin sends nothing")
    -- unlock and save, then lock again
    assert(PE.OpenEdit({ kind = "local", pin = vendor, token = "local:" .. vendor.id }))
    ed.keep.scripts.OnClick(ed.keep); ed.save.scripts.OnClick(ed.save)
    assert(not PN.IsKept(vendor) and PN.LocalCount() == countBefore, "unlocked by Save, and not deleted by it")
    assert(PE.OpenEdit({ kind = "local", pin = vendor, token = "local:" .. vendor.id }))
    assert(ed.keep:IsOn() == false)
    ed.keep.scripts.OnClick(ed.keep); ed.save.scripts.OnClick(ed.save)
    assert(PN.IsKept(vendor))

    -- a new pin can be made kept in the same dialog; the default is not
    PE.OpenNew(1429, 2000, 2000, false)
    assert(ed.keep:IsOn() == false, "new pins are ordinary by default")
    ed.keep.scripts.OnClick(ed.keep)
    ed.name:SetText("Mailbox")
    ed.save.scripts.OnClick(ed.save)
    local mail
    for _, p in ipairs(PN.LocalPins()) do if p.name == "Mailbox" then mail = p end end
    assert(mail and PN.IsKept(mail), "made kept")
    assert(PN.RemoveLocal(mail.id) == false)
    assert(PN.UpdateLocal(mail.id, { kept = false }) and PN.RemoveLocal(mail.id))
    FlushTimers()

    -- the window: a padlock, a filter, and a delete that says why it is off
    local panel = c.TwichUIPins
    assert(PW.Show())
    panel.filters.kept.scripts.OnClick(panel.filters.kept)
    FlushTimers()
    local seen = 0
    for _, f in ipairs(FRAMES) do
      if rawget(f, "more") and rawget(f, "lock") and rawget(f, "entry") then
        assert(f.entry.kept == true and f.lock.shown == true, "the Kept filter lists kept pins, with their padlock")
        seen = seen + 1
      end
    end
    assert(seen == 1, "one kept pin listed (" .. seen .. ")")
    local acts = labels(PW.Actions({ kind = "local", pin = vendor, token = "local:" .. vendor.id }))
    assert(acts["Remove pin"].enabled == false and acts["Remove pin"].why:find("kept"), "Remove pin is off, and says why")
    acts["Remove pin"].run()
    assert(PN.FindLocal(vendor.id) and lastNotice():find("kept"), "and picking it anyway deletes nothing")
    assert(acts["Edit pin..."].enabled)
    panel.filters["all"].scripts.OnClick(panel.filters["all"])
    PW.Hide()

    -- the marker's tooltip
    local lines = {}
    rawset(c.GameTooltip, "SetText", function(_, text) lines[#lines + 1] = text end)
    rawset(c.GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = text end)
    PM.Tooltip({ entry = { kind = "local", pin = vendor, token = "local:" .. vendor.id } })
    local tipText = table.concat(lines, "\n")
    assert(tipText:find("Orgrimmar reagents", 1, true) and tipText:find("Kept \194\183 Local pin", 1, true), "the tooltip says Kept")
    lines = {}
    PM.Tooltip({ entry = { kind = "local", pin = ordinary, token = "local:" .. ordinary.id } })
    assert(not table.concat(lines, "\n"):find("Kept", 1, true), "and only for a kept pin")
    rawset(c.GameTooltip, "SetText", nil); rawset(c.GameTooltip, "AddLine", nil)

    -- Clear unprotected pins: the question has the counts of its scope, singular here
    FlushTimers()
    BM.Open(host)
    local asked = #popups
    click(c.TwichUIPinsMenu.clear)
    assert(#popups == asked + 1 and popups[#popups].key == "TWICHUI_PINS_CLEAR_ALL")
    local text = popups[#popups].text
    assert(text:find("Remove 1 unprotected pin?", 1, true) and text:find("Your 1 kept pin will remain.", 1, true), text)
    assert(not text:find("party", 1, true), "no party pins are in this scope")
    assert(PN.LocalCount() == 2, "nothing changed before confirming")
    -- while it is open: a new pin is made, and the pin it counted becomes kept
    local late = assert(PN.AddLocal({ map = 1429, x = 300, y = 300, name = "Made meanwhile" }))
    assert(PN.UpdateLocal(ordinary.id, { kept = true }))
    c.StaticPopupDialogs.TWICHUI_PINS_CLEAR_ALL.OnAccept()
    assert(PN.FindLocal(ordinary.id) and PN.IsKept(ordinary), "a pin kept since the question stays")
    assert(PN.FindLocal(late.id), "a pin made since is not what was confirmed")
    -- clearing for real, with plural wording
    assert(PN.UpdateLocal(ordinary.id, { kept = false }))
    local late2 = assert(PN.AddLocal({ map = 1429, x = 301, y = 301, name = "Another" }))
    FlushTimers()
    BM.Open(host)
    click(c.TwichUIPinsMenu.clear)
    text = popups[#popups].text
    assert(text:find("Remove 3 unprotected pins?", 1, true) and text:find("Your 1 kept pin will remain.", 1, true), text)
    sentBefore = sent()
    c.StaticPopupDialogs.TWICHUI_PINS_CLEAR_ALL.OnAccept()
    assert(PN.LocalCount() == 1 and PN.IsKept(vendor) and sent() == sentBefore, "only the kept pin remains; nothing was sent")
    FlushTimers()
    -- only kept pins left: no headings and the link is off, with the reason
    BM.Open(host)
    assert(c.TwichUIPinsMenu.clear.enabled == false, "nothing to clear: the link is off")
    local clearTip = c.TwichUIPinsMenu.clear.twichuiTip
    local _, reason = clearTip.body(c.TwichUIPinsMenu.clear)
    assert(reason and reason:find("kept"), "and says why")
    assert(not shownText("Other pins") and countText("Kept") == keptWords - 1, "no headings with one group")
    BM.Close()
    -- asked anyway (the link is greyed out in the game), it says so instead of asking
    local askedNow, noticesNow = #popups, #notices
    BM.Open(host)
    c.TwichUIPinsMenu.clear.scripts.OnClick(c.TwichUIPinsMenu.clear)
    assert(#popups == askedNow and #notices == noticesNow + 1 and lastNotice():find("kept"), "nothing to ask about: it says why")

    -- put the state back for what follows
    c.TwichUIDB.pins.list = baseList
    c.TwichUIDB.pins.nextId = nil
    for _, key in ipairs(hiddenHere) do PN.Restore(key) end
    PN.Changed()
    FlushTimers()
    assert(PN.LocalCount() == #keptLocal)
  end

  -- a pin arriving from another player is pointed out for a while, then the text goes back
  do
    local timers = {}
    local realAfter = c.C_Timer.After
    c.C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
    local function pending() local n = 0 for _, t in ipairs(timers) do if t.delay >= 1 then n = n + 1 end end return n end
    local function fire(i) local t = table.remove(timers, i); t.fn() end
    local function put(id, rev, name)
      return PN.ApplyPut("Pal Stonebrook", { id = id, r = rev, m = 1429, x = 2000, y = 2000, n = name, c = "rose" })
    end
    assert(BR.Get("flash") == true and BR.Get("flashSeconds") == 8 and BR.Get("flashColor") == "ffe8b64a", "on, 8 seconds, gold")
    assert(not BR.Set("flashSeconds", 1) and not BR.Set("flashSeconds", 31) and not BR.Set("flashSeconds", 5.5) and not BR.Set("flashColor", "gold"),
      "an unusable time or color is refused")
    -- not for what you do yourself
    assert(PN.AddLocal({ map = 1429, x = 5, y = 5, name = "Mine" }))
    assert(PS.CreateParty({ map = 1429, x = 6, y = 6, name = "Mine too" }))
    assert(not obj.text:find("New pin") and obj.iconR == nil and pending() == 0, "your own pins are not pointed out")
    -- a new one: the words, the color on the text and the icon, and the time it was given
    assert(put("pal:9", 1, "Mine shaft"))
    assert(obj.text == "|cffe8b64aNew pin: Mine shaft|r", "says so, in the color")
    local r, g, b = PL.Rgb("ffe8b64a")
    assert(obj.iconR == r and obj.iconG == g and obj.iconB == b, "the icon is tinted the same")
    assert(pending() == 1 and timers[#timers].delay == 8)
    -- an update to it, or a stale copy, is not a new pin
    assert(put("pal:9", 2, "Mine shaft deep"))
    assert(not put("pal:9", 2, "Again"))
    assert(obj.text == "|cffe8b64aNew pin: Mine shaft|r" and pending() == 1, "no new highlight, no new timer")
    -- the count changing meanwhile keeps the highlight; a second arrival restarts the time
    assert(put("pal:10", 1, "Quarry"))
    assert(obj.text == "|cffe8b64a2 new pins|r" and pending() == 2)
    fire(#timers - 1)   -- the first timer is out of date: nothing happens
    assert(obj.text:find("2 new pins") and obj.iconR, "the older timer doesn't end it early")
    fire(#timers)
    assert(obj.text == "" or not obj.text:find("new pin"), "back to normal when the time is up")
    assert(obj.text:find("pin") and obj.iconR == nil and obj.iconG == nil and obj.iconB == nil, "the usual count, the icon untinted")
    -- the player's own time and color
    assert(BR.Set("flashSeconds", 12) and BR.Set("flashColor", "ff112233"))
    assert(put("pal:11", 1, "A very long name that would not fit on any data bar at all"))
    assert(obj.text:find("^|cff112233New pin: A very long name that%.%.%.|r$") or obj.text:find("^|cff112233New pin: .-%.%.%.|r$"),
      "a long name is cut: " .. obj.text)
    assert(timers[#timers].delay == 12)
    -- turned off while it shows: gone at once, and nothing more is pointed out
    assert(BR.Set("flash", false))
    assert(not obj.text:find("New pin") and obj.iconR == nil, "turned off: back at once")
    assert(put("pal:12", 1, "Ignored"))
    assert(not obj.text:find("New pin"), "off: not pointed out")
    assert(BR.Set("flash", true))
    -- a party member's full list: only the pins that are new here count, and it is said once
    local before = #timers
    assert(PN.ApplyAll("Pal Stonebrook", {
      { id = "pal:1", r = 1, m = 1436, x = 5000, y = 5000, n = "Westfall camp", c = "river" },   -- already held
      { id = "pal:9", r = 2, m = 1429, x = 2000, y = 2000, n = "Mine shaft deep", c = "rose" },
      { id = "pal:11", r = 1, m = 1429, x = 2000, y = 2000, n = "Quarry", c = "rose" },
      { id = "pal:12", r = 1, m = 1429, x = 2000, y = 2000, n = "Ignored", c = "rose" },
      { id = "pal:20", r = 1, m = 1429, x = 2100, y = 2000, n = "Watchtower", c = "rose" },
      { id = "pal:21", r = 1, m = 1429, x = 2200, y = 2000, n = "Well", c = "rose" },
    }))
    assert(obj.text == "|cff1122332 new pins|r", "two were new here, said once: " .. obj.text)
    -- the same list again changes nothing and points out nothing
    for i = #timers, 1, -1 do fire(i) end
    assert(not obj.text:find("new pin") and obj.iconR == nil)
    assert(PN.ApplyAll("Pal Stonebrook", {
      { id = "pal:1", r = 1, m = 1436, x = 5000, y = 5000, n = "Westfall camp", c = "river" },
      { id = "pal:9", r = 2, m = 1429, x = 2000, y = 2000, n = "Mine shaft deep", c = "rose" },
      { id = "pal:11", r = 1, m = 1429, x = 2000, y = 2000, n = "Quarry", c = "rose" },
      { id = "pal:12", r = 1, m = 1429, x = 2000, y = 2000, n = "Ignored", c = "rose" },
      { id = "pal:20", r = 1, m = 1429, x = 2100, y = 2000, n = "Watchtower", c = "rose" },
      { id = "pal:21", r = 1, m = 1429, x = 2200, y = 2000, n = "Well", c = "rose" },
    }))
    assert(not obj.text:find("new pin") and pending() == 0, "a list with nothing new points out nothing")
    -- put the state back for what follows
    for _, id in ipairs({ "pal:9", "pal:10", "pal:11", "pal:12", "pal:20", "pal:21" }) do PN.ApplyDel("Pal Stonebrook", id, 5) end
    for _, p in ipairs(PN.OwnPins()) do if p.name == "Mine too" then PS.RemoveForParty(p.key) end end
    for _, p in ipairs(PN.LocalPins()) do if p.name == "Mine" then PN.RemoveLocal(p.id) end end
    BR.Reset()
    c.C_Timer.After = realAfter
    TIMERS = {}
    FlushTimers()
    assert(PN.LocalCount() == #keptLocal)
  end

  -- the arrival sound: once for a pin that is new here, on the chosen channel, and for nothing else
  do
    local heard, now = {}, 100
    local realTime = c.GetTime
    c.GetTime = function() return now end
    c.PlaySoundFile = function(path, channel) heard[#heard + 1] = { path = path, channel = channel }; return true end
    local SD, SN = PL.Sound, R.PinsSound
    local DEFAULT = [[Interface\AddOns\!!!TwichUI\media\sounds\TwichUI_MapPin.mp3]]
    local function put(id, rev, name)
      return PN.ApplyPut("Pal Stonebrook", { id = id, r = rev, m = 1429, x = 2000, y = 2000, n = name, c = "rose" })
    end
    assert(SD.Get("enabled") == true and SD.Get("sound") == "TwichUI Map Pin" and SD.Get("channel") == "SFX",
      "on, TwichUI's map pin sound, the Sound Effects volume")
    assert(c.TwichUIDB.ui.pinsSound == nil, "nothing saved until a choice is made")
    assert(R.MediaSounds["TwichUI Map Pin"] == "TwichUI_MapPin.mp3", "offered to other addons' sound lists too")
    -- not for what you do yourself
    assert(PN.AddLocal({ map = 1429, x = 5, y = 5, name = "Mine" }))
    assert(PS.CreateParty({ map = 1429, x = 6, y = 6, name = "Mine too" }))
    assert(#heard == 0, "your own pins make no sound")
    -- a new pin from another player: once, on the default sound and channel
    assert(put("pal:31", 1, "Camp"))
    assert(#heard == 1 and heard[1].path == DEFAULT and heard[1].channel == "SFX", "the default sound on Sound Effects")
    -- an update or a stale copy is not an arrival
    now = 110
    assert(put("pal:31", 2, "Camp two"))
    assert(not put("pal:31", 2, "Again"))
    assert(#heard == 1, "updates and stale copies make no sound")
    -- several in a moment give one; a later one sounds again
    local heldBefore = SN.Snapshot().held
    assert(put("pal:32", 1, "Well"))
    assert(#heard == 2)
    now = 110.5
    assert(put("pal:33", 1, "Mill"))
    assert(#heard == 2 and SN.Snapshot().held == heldBefore + 1, "within two seconds: held back")
    now = 113
    assert(put("pal:34", 1, "Smithy"))
    assert(#heard == 3, "and again once the time has passed")
    -- one message with several new pins is one sound
    now = 120
    assert(PN.ApplyAll("Pal Stonebrook", {
      { id = "pal:31", r = 2, m = 1429, x = 2000, y = 2000, n = "Camp two", c = "rose" },
      { id = "pal:35", r = 1, m = 1429, x = 2100, y = 2000, n = "Dock", c = "rose" },
      { id = "pal:36", r = 1, m = 1429, x = 2200, y = 2000, n = "Quay", c = "rose" },
    }))
    assert(#heard == 4, "a list with two new pins sounds once")
    assert(PN.ApplyAll("Pal Stonebrook", {
      { id = "pal:31", r = 2, m = 1429, x = 2000, y = 2000, n = "Camp two", c = "rose" },
      { id = "pal:35", r = 1, m = 1429, x = 2100, y = 2000, n = "Dock", c = "rose" },
    }))
    assert(#heard == 4, "a list with nothing new is silent")
    -- the player's channel
    assert(not SD.Set("channel", "Music") and not SD.Set("channel", 3) and SD.Get("channel") == "SFX", "an unknown channel is refused")
    assert(SD.Set("channel", "Master") and c.TwichUIDB.ui.pinsSound.channel == "Master")
    now = 130
    assert(put("pal:37", 1, "Gate"))
    assert(heard[#heard].channel == "Master" and heard[#heard].path == DEFAULT, "the chosen channel")
    -- the player's sound: LibSharedMedia's list, listed after TwichUI's own
    local LSM = c.LibStub("LibSharedMedia-3.0")
    LSM:Register("sound", "Other Addon Ding", [[Interface\AddOns\OtherAddon\ding.ogg]])
    local choices = SN.Choices(SD.Get("sound"))
    local at = {}
    for i, ch in ipairs(choices) do at[ch[1]] = i end
    assert(at["TwichUI Map Pin"] and at["Other Addon Ding"] and at["Other Addon Ding"] > at["TwichUI Map Pin"], "TwichUI's first")
    assert(at["TwichUI Notification"] and at["TwichUI Notification"] < at["Other Addon Ding"])
    assert(not at["None"], "LibSharedMedia's silent entry is not offered; the switch is the way to silence it")
    assert(not SD.Set("sound", "") and not SD.Set("sound", 5) and not SD.Set("sound", ("x"):rep(65)), "an unusable name is refused")
    assert(SD.Set("sound", "Other Addon Ding"))
    now = 140
    assert(put("pal:38", 1, "Bridge"))
    assert(heard[#heard].path == [[Interface\AddOns\OtherAddon\ding.ogg]], "the chosen sound")
    -- one that has gone stays chosen, listed as such, and the default plays in its place
    assert(SD.Set("sound", "Vanished Sound") and SD.Get("sound") == "Vanished Sound")
    local gone = SN.Choices(SD.Get("sound"))
    assert(gone[#gone][1] == "Vanished Sound" and gone[#gone][2]:find("not available", 1, true), "kept and marked")
    now = 150
    assert(put("pal:39", 1, "Tower"))
    assert(heard[#heard].path == DEFAULT and SN.Snapshot().fallback, "the default plays instead")
    assert(c.TwichUIDB.ui.pinsSound.sound == "Vanished Sound", "and the choice is not erased")
    -- Hear the sound: plays now, whatever the switch or the time since the last
    assert(SD.Set("enabled", false))
    local n = #heard
    now = 160
    assert(put("pal:40", 1, "Dam") and #heard == n, "off: arrivals are silent")
    assert(SN.Play() and #heard == n + 1, "the preview plays even so")
    -- a game that refuses the sound is counted and not an error
    c.PlaySoundFile = function() return false end
    local refused = SN.Snapshot().refused
    assert(SN.Play() == false and SN.Snapshot().refused == refused + 1)
    c.PlaySoundFile = nil
    assert(SN.Play() == false, "no sound function: nothing happens")
    -- the troubleshooting section says how it went and names no sound or path
    local rep = R.Diag.Build()
    local from = rep:find("== Party pins ==", 1, true)
    local sec = rep:sub(from, rep:find("\n== ", from + 5, true) or #rep)
    assert(sec:find("arrival sound: off, volume follows Master, sound chosen", 1, true), "arrival sound line: " .. sec)
    for _, needle in ipairs({ "Vanished", "Other Addon", "ding.ogg", "MapPin" }) do
      assert(not sec:find(needle, 1, true), "the report must not hold " .. needle)
    end
    -- put the state back for what follows
    for _, id in ipairs({ "pal:31", "pal:32", "pal:33", "pal:34", "pal:35", "pal:36", "pal:37", "pal:38", "pal:39", "pal:40" }) do
      PN.ApplyDel("Pal Stonebrook", id, 9)
    end
    for _, p in ipairs(PN.OwnPins()) do if p.name == "Mine too" then PS.RemoveForParty(p.key) end end
    for _, p in ipairs(PN.LocalPins()) do if p.name == "Mine" then PN.RemoveLocal(p.id) end end
    c.TwichUIDB.ui.pinsSound = nil
    c.GetTime = realTime
    TIMERS = {}
    FlushTimers()
  end

  -- its look is its own, kept apart from the window's and the launchers'
  assert(PL.MenuLook.Set("bgOpacity", 40) and c.TwichUIDB.ui.pinsBrokerMenu.bgOpacity == 40)
  assert(c.TwichUIDB.ui.pinsLook == nil or c.TwichUIDB.ui.pinsLook.bgOpacity == nil, "the window's look is not the menu's")
  assert(c.TwichUIDB.ui.brokerMenu == nil, "the Mage launchers' look is not touched")
  assert(PL.MenuLook.DEFAULTS ~= R.MenuStyle.DEFAULTS and PL.MenuLook.Get("bgColor") == R.MenuStyle.Get("bgColor"),
    "a copy of the launchers' defaults, so the two match until one is changed")
  PL.MenuLook.Reset()
  assert(c.TwichUIDB.ui.pinsBrokerMenu == nil, "reset: nothing saved")
  -- the options page's Preview opens the real menu and Esc/again closes it
  BM.TogglePreview(); assert(BM.IsOpen())
  BM.TogglePreview(); assert(not BM.IsOpen())

  -- the troubleshooting section holds no names
  local rep2 = R.Diag.Build()
  local f2 = rep2:find("== Party pins ==", 1, true)
  local sec = rep2:sub(f2, rep2:find("\n== ", f2 + 5, true) or #rep2)
  assert(sec:find("data bar menu:", 1, true) and sec:find("data bar:", 1, true))
  for _, needle in ipairs({ "Copper", "Camp", "Westfall", "Stonebrook" }) do
    assert(not sec:find(needle, 1, true), "the report must not hold " .. needle)
  end
end

---------------------------------------------------------------------------
-- 7d. Share with group: the action menu, the editor's Share button, the data bar menu's right-click
---------------------------------------------------------------------------
do
  local BM = R.PinsBrokerMenu
  local function labels2(list) local t = {} for _, a in ipairs(list) do t[a.label] = a end return t end
  local vendor2 = assert(PN.AddLocal({ map = 1429, x = 4400, y = 5100, name = "Shared vendor", color = "river", kept = true }))
  local ve = { kind = "local", pin = vendor2, token = "local:" .. vendor2.id }
  -- in the group: offered, enabled, and it doesn't touch Keep
  local acts = labels2(PW.Actions(ve))
  assert(acts["Share with group"] and acts["Share with group"].enabled and not acts["Stop sharing..."], "offered for a kept pin")
  local before = sent()
  acts["Share with group"].run()
  assert(sent() == before + 1 and lastNotice() == "Pin sent to your party.", "one message, and 'sent' is all it claims: " .. lastNotice())
  assert(PN.IsKept(vendor2) and PN.GroupCopy(vendor2.id), "still kept; the group copy exists")
  acts = labels2(PW.Actions(ve))
  assert(acts["Share again"] and acts["Stop sharing..."] and not acts["Share with group"], "now it is Share again, with Stop sharing")
  -- another player's pin: shown, off, and the reason names the way forward
  assert(PN.ApplyPut("Pal Stonebrook", { id = "pal:77", r = 1, m = 1429, x = 3000, y = 3000, n = "Pal's pin", c = "gold" }))
  local pal2 = PN.Shared(PN.Key("Pal Stonebrook", "pal:77"))
  local palActs2 = labels2(PW.Actions({ kind = "party", pin = pal2, token = "party:" .. pal2.key }))
  assert(palActs2["Share with group"] and palActs2["Share with group"].enabled == false
    and palActs2["Share with group"].why:find("Save it to your pins first"), "someone else's pin can't be shared as yours")
  palActs2["Share with group"].run()
  assert(lastNotice():find("Save it to your pins first"))
  -- stop sharing asks first, then removes only the group copy
  acts["Stop sharing..."].run()
  assert(popups[#popups].key == "TWICHUI_PINS_UNSHARE" and popups[#popups].text:find("saved pin stays"), "asks first")
  assert(PN.GroupCopy(vendor2.id) and sent() == before + 1, "nothing is sent before accepting")
  c.StaticPopupDialogs.TWICHUI_PINS_UNSHARE.OnAccept()
  assert(not PN.GroupCopy(vendor2.id) and PN.FindLocal(vendor2.id) and PN.IsKept(vendor2) and sent() == before + 2, "only the copy went")

  -- the editor: a Share button for a saved pin, disabled with the reason when there is no party
  local function isShown(f) return f.shown ~= false end
  assert(PE.OpenEdit(ve))
  assert(isShown(ed.share) and ed.share.enabled ~= false, "Share is offered when editing a local pin")
  ed.name:SetText("Shared vendor (Org)")
  local n = sent()
  ed.share.scripts.OnClick(ed.share)
  assert(vendor2.name == "Shared vendor (Org)" and PN.IsKept(vendor2) and PN.GroupCopy(vendor2.id), "saved, then shared")
  assert(PN.GroupCopy(vendor2.id).name == "Shared vendor (Org)" and sent() == n + 1 and not PE.IsOpen())
  -- Save alone sends nothing and keeps the pin local
  assert(PE.OpenEdit(ve))
  assert(ed.status.text:find("Shared with your party"), "it says it is shared: " .. ed.status.text)
  ed.name:SetText("Quiet rename")
  ed.save.scripts.OnClick(ed.save)
  assert(vendor2.name == "Quiet rename" and sent() == n + 1 and PN.GroupCopy(vendor2.id).name == "Shared vendor (Org)",
    "Save alone doesn't send; the party keeps the last share")
  -- Enter in the name box is Save, not Share
  assert(PE.OpenEdit(ve))
  ed.name:SetText("Enter rename")
  ed.name.scripts.OnEnterPressed(ed.name)
  assert(vendor2.name == "Enter rename" and sent() == n + 1, "Enter saves without sharing")
  -- someone else's party pin and a new pin have no Share button
  PE.OpenNew(1429, 100, 100, false)
  assert(not isShown(ed.share), "a new pin has no Share button")
  ed.name.scripts.OnEscapePressed(ed.name)
  -- no party: disabled, with the sentence; the pin is saved but not shared if it is pressed some other way
  local inGroup, inRaid = c.IsInGroup, c.IsInRaid
  c.IsInRaid = function() return true end
  assert(PE.OpenEdit(ve))
  assert(ed.share.enabled == false, "disabled in a raid")
  local tip = ed.share.twichuiTip
  assert(tip and select(2, tip.body(ed.share)) == "Pins can only be shared with a party, not a raid.")
  ed.name.scripts.OnEscapePressed(ed.name)
  assert(labels2(PW.Actions(ve))["Share again"].enabled == false)
  c.IsInRaid = inRaid

  -- the data bar menu: a right-click on a pin's name opens the same action menu; shared pins say so
  local host2 = Obj()
  brokers["TwichUI Party Pins"].OnClick(host2, "LeftButton")
  assert(BM.IsOpen())
  local function rowOf(name)
    for _, f in ipairs(FRAMES) do
      local e = rawget(f, "entry")
      if rawget(f, "pick") and e and e.pin.name == name and f.shown ~= false then return f end
    end
  end
  local row = assert(rowOf("Enter rename"))
  assert(row.owner.text == "shared", "the row says shared: " .. tostring(row.owner.text))
  row.nameBtn.scripts.OnClick(row.nameBtn, "RightButton")
  assert(c.TwichUIPinActions and c.TwichUIPinActions.shown ~= false, "the pin's action menu opened")
  assert(not BM.Snapshot().editing, "a right-click doesn't start a rename")
  PW.CloseMenu()
  BM.Close()
  PN.UpdateLocal(vendor2.id, { kept = false })
  assert(PS.UnshareLocal(vendor2.id) and PN.RemoveLocal(vendor2.id))
  FlushTimers()
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
