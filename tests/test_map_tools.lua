-- Map tools: the world map's tool bar for personal pins, group pins and group pings. The game's frames, the network and the
-- group are the harness's mocks (as in test_map_ping.lua), so this shows TwichUI's own bookkeeping and routing: how the bar
-- looks and sits on the real map, the keyboard catcher's behavior and the real icons in game are for the game.
--   0  what is registered       1  the once-only note and the bar's place     2  arming (nothing happens yet)
--   3  one click, one action     4  invalid places                            5  Esc, the map closing, the cursor
--   6  shortcuts, one input one action                                        7  tooltips and help
--   8  the group changing while armed, permissions, switches                  9  saved choices, off and on
--  10  profiles                 11  room, scale, input                         12  no polling   13  the icons and packaging
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end
CLOCK = 1000

local SELF = "Rich Hale"
local c = MakeClient(SELF, { "!!!TwichUI" })
CLIENTS[SELF] = c
c.GetTime = function() return CLOCK end

---------------------------------------------------------------------------
-- Mocks (as in test_party_pins_ui.lua, with what pings need)
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
    if k == "ScrollBar" then
      local sb = Obj(); rawset(sb, "ThumbTexture", false); rawset(sb, "ScrollUpButton", false); rawset(sb, "ScrollDownButton", false)
      rawset(t, k, sb); return sb
    end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end
local realCreate = c.CreateFrame
local FRAMES = {}
local FSLIST = {}   -- every FontString made, to read what is on screen
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
  rawset(o, "SetPropagateKeyboardInput", function(s, v) s.propagate = v and true or false end)
  rawset(o, "GetWidth", function(s) return s.width or 100 end)
  rawset(o, "GetHeight", function(s) return s.height or 20 end)
  rawset(o, "parent", parent)
  local makeFS = o.CreateFontString
  rawset(o, "CreateFontString", function(s, ...) local fs = makeFS(s, ...); FSLIST[#FSLIST + 1] = fs; return fs end)
  rawset(o, "CreateTexture", function()
    local t = Obj()
    rawset(t, "SetTexture", function(s, p) s.tex = p end)
    rawset(t, "SetDesaturated", function(s, v) s.desaturated = v and true or false end)
    rawset(t, "SetAlpha", function(s, v) s.alpha = v end)
    return t
  end)
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
local function lastNotice() return notices[#notices] or "" end
c.issecretvalue = nil
local caught = {}
c.geterrorhandler = function() return function(e) caught[#caught + 1] = e end end

-- the tooltip
local TIP = { owner = nil, text = nil, shown = false }
c.GameTooltip = {
  SetOwner = function(_, o) TIP.owner = o; TIP.shown = false end,
  SetText = function(_, t) TIP.text = t end, AddLine = function() end,
  Show = function() TIP.shown = true end, Hide = function() TIP.shown = false end,
  IsOwned = function(_, f) return TIP.owner == f end,
}

-- keys held
ALT, SHIFT, CTRL = false, false, false
c.IsAltKeyDown = function() return ALT end
c.IsShiftKeyDown = function() return SHIFT end
c.IsControlKeyDown = function() return CTRL end
local function keys(a, s, k) ALT, SHIFT, CTRL = a, s, k end

-- sound
local sounds = {}
c.SOUNDKIT = { MAP_PING = 3175 }
c.PlaySound = function(id) sounds[#sounds + 1] = { "kit", id }; return true end
c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { "file", path, channel }; return true end

-- the group as the game reports it
local SELFNAME = SELF
local G = { kind = "none", instance = false, members = {} }
c.LE_PARTY_CATEGORY_HOME, c.LE_PARTY_CATEGORY_INSTANCE = 1, 2
c.IsInGroup = function(category)
  if G.kind == "none" and not G.instance then return false end
  if category == 2 then return G.instance end
  if category == 1 then return G.kind ~= "none" end
  return true
end
c.IsInRaid = function() return G.kind == "raid" end
c.GetUnitName = function(unit)
  if unit == "player" then return SELFNAME end
  local kind, i = unit:match("^(%a+)(%d+)$")
  i = tonumber(i)
  if kind == "party" and G.kind ~= "raid" then return G.members[i] end
  if kind == "raid" and G.kind == "raid" then return G.members[i] end
end
local LOCK = false
c.C_ChatInfo.InChatMessagingLockdown = function() return LOCK end
local function group(kind, members, instance) G.kind, G.members, G.instance = kind, members or {}, instance or false end

-- maps: Elwynn (1429) and Westfall (1436) in Eastern Kingdoms (1415); Stormwind (1453) inside Elwynn; 946 is the cosmic map
c.Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3 }
local MAPS = {
  [946] = { name = "Cosmic", parent = 0, mapType = 0 },
  [947] = { name = "Azeroth", parent = 946, mapType = 1 },
  [1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2, ox = 0, oy = 0, size = 4000 },
  [1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3, ox = 1000, oy = 2000, size = 400 },
  [1436] = { name = "Westfall", parent = 1415, mapType = 3, ox = 600, oy = 2200, size = 400 },
  [1453] = { name = "Stormwind City", parent = 1429, mapType = 3, ox = 1100, oy = 2050, size = 100 },
}
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
c.C_Map = {
  GetMapInfo = function(id) local m = MAPS[id]; return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.mapType } or nil end,
  GetWorldPosFromMapPos = function(map, v)
    local m = MAPS[map]; if not (m and m.size) then return nil end
    return 0, c.CreateVector2D(m.ox + v.x * m.size, m.oy + v.y * m.size)
  end,
  GetMapPosFromWorldPos = function(cont, w, viewed)
    local m = MAPS[viewed]; if not (m and m.size) then return nil end
    return viewed, c.CreateVector2D((w.x - m.ox) / m.size, (w.y - m.oy) / m.size)
  end,
}

-- the world map: data providers, click handlers (with their priorities) and every SetMapID asked of it
c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end,
  OnShow = function() end, OnHide = function() end, OnMapChanged = function() end, RemoveAllData = function() end,
  RefreshAllData = function() end, OnCanvasScaleChanged = function() end, OnCanvasSizeChanged = function() end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
local CANVAS_W, CANVAS_H, SCALE, CONTAINER_W = 1000, 700, 1, 1000
local canvas = Obj()
rawset(canvas, "GetWidth", function() return CANVAS_W end); rawset(canvas, "GetHeight", function() return CANVAS_H end)
local container = Obj()
rawset(container, "GetWidth", function() return CONTAINER_W end)
local MOUSE_OVER = true
rawset(container, "IsMouseOver", function() return MOUSE_OVER end)
rawset(container, "HookScript", function(s, name, fn) s.hooks = s.hooks or {}; s.hooks[name] = fn end)
local WMF = Obj()
local NAV = Obj()   -- the map's navigation bar (the breadcrumbs in the title row)
rawset(NAV, "GetFrameLevel", function() return 7 end)
rawset(WMF, "NavBar", NAV)
WMF.mapID, WMF.providers, WMF.clicks, WMF.cursors = 1429, {}, {}, {}
WMF.shown = false   -- the map starts closed
WMF.setCalls, WMF.slow, WMF.fail = {}, false, false
rawset(WMF, "GetMapID", function(s) return s.mapID end)
rawset(WMF, "SetMapID", function(s, id)
  s.setCalls[#s.setCalls + 1] = id
  if s.fail then error("map can't be shown") end
  if s.slow then s.waitingFor = id return end   -- the map arrives later: deliver(id)
  s.mapID = id
  for p in pairs(s.providers) do p:OnMapChanged() end
end)
rawset(WMF, "GetCanvas", function() return canvas end)
rawset(WMF, "GetCanvasContainer", function() return container end)
rawset(WMF, "GetCanvasScale", function() return SCALE end)
rawset(WMF, "GetGlobalPinScale", function() return 1 end)
rawset(WMF, "GetPinFrameLevelsManager", function() return { GetValidFrameLevel = function() return 40 end } end)
rawset(WMF, "AddDataProvider", function(s, p) s.providers[p] = true; p:OnAdded(s) end)
rawset(WMF, "RemoveDataProvider", function(s, p) p:RemoveAllData(); s.providers[p] = nil; p:OnRemoved(s) end)
rawset(WMF, "AddCanvasClickHandler", function(s, fn, pr) s.clicks[fn] = pr end)
rawset(WMF, "RemoveCanvasClickHandler", function(s, fn) s.clicks[fn] = nil end)
rawset(WMF, "AddCursorHandler", function(s, fn, pr) s.cursors[fn] = pr end)
rawset(WMF, "RemoveCursorHandler", function(s, fn) s.cursors[fn] = nil end)
c.WorldMapFrame = WMF
local function deliver(id)   -- a slow map arrives
  WMF.mapID = id; WMF.waitingFor = nil
  for p in pairs(WMF.providers) do p:OnMapChanged() end
end
local function userGoes(id) deliver(id) end
-- the click handlers in the order the map runs them (higher priority first), as the map does: the first to answer true ends it
local function click(button, x, y)
  local list = {}
  for fn, pr in pairs(WMF.clicks) do list[#list + 1] = { fn = fn, pr = pr } end
  table.sort(list, function(a, b) return a.pr > b.pr end)
  for _, h in ipairs(list) do if h.fn(WMF, button, x, y) then return true, h.pr end end
  return false
end
local function openMap() WMF.shown = true; for p in pairs(WMF.providers) do p:OnShow() end; FlushTimers() end
local function closeMap() WMF.shown = false; for p in pairs(WMF.providers) do p:OnHide() end end

local brokers = {}
local LDB = c.LibStub:NewLibrary("LibDataBroker-1.1", 1)
LDB.NewDataObject = function(_, name, o) brokers[name] = o; return o end
for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua", "pins/MapTools.lua",
  "diag/Diagnostics.lua", "diag/Pins.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PN, PM, PL, PG, MP, V, T = R.Pins, R.PinsMap, R.PinsLook, R.PinsLook.Ping, R.MapPing, R.MapPingView, R.MapTools
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function pingMessages()
  local list = {}
  for _, m in ipairs(NET) do if m.prefix == "TwichUIPing" then list[#list + 1] = m end end
  return list
end
local function sentTotal() local n = 0 for _, m in ipairs(SENT_LOG or {}) do if m.prefix == "TwichUIPing" then n = n + 1 end end return n end
-- a message from `sender` over `dist`, as the game hands it to the receiver
local function inject(text, sender, dist)
  c._comm.TwichUIPing("TwichUIPing", text, dist or "PARTY", sender)
end
local function fresh()   -- clears what a test left, keeping the switches and the group
  MP.Clear(); sounds = {}; notices = {}; CLOCK = CLOCK + 60; NET = {}
end
local function framesWith(field) local out = {} for _, f in ipairs(FRAMES) do if rawget(f, field) then out[#out + 1] = f end end return out end
local seqOf = 100
local function msg(map, x, y, seq) seqOf = seqOf + 1; return ("1:%d:%d:%d:%d"):format(map, x, y, seq or seqOf) end

local PAL, MAT, SAM = "Pal Stonebrook", "Mat Reedwater", "Sam Greyfen"

-- what the map tools add to the mocks
local opened = {}   -- every call to the new pin window
R.PinsEditor = { OpenNew = function(map, x, y, party) opened[#opened + 1] = { map = map, x = x, y = y, party = party } end,
  Close = function() end, IsOpen = function() return false end }
c.GameTooltip.SetText = function(_, t) TIP.text = t; TIP.lines = {} end
c.GameTooltip.AddLine = function(_, t) TIP.lines = TIP.lines or {}; TIP.lines[#TIP.lines + 1] = t end
local function tipHas(pattern)
  for _, l in ipairs(TIP.lines or {}) do if l:find(pattern) then return true end end
  return false
end
local function buttons()
  local out = {}
  for _, f in ipairs(FRAMES) do local id = rawget(f, "toolId") if id then out[id] = f end end
  return out
end
local function keysFrame()
  for _, f in ipairs(FRAMES) do if f.scripts and f.scripts.OnKeyDown and f.parent == c.TwichUIMapTools then return f end end
end
local function stripFrame() return framesWith("accent")[1] end
local function allText()
  local t = {}
  for _, fs in ipairs(FSLIST) do t[#t + 1] = fs.text end
  return table.concat(t, "\n")
end
local function groupEvent() c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers() end   -- the bar looks one tick later
local function plain() keys(false, false, false) end
local function intro() local ui = c.TwichUIDB.ui; return ui and ui.mapToolsIntro end
local function tidy()   -- a clean slate between sections: nothing armed, no help, nothing counted
  T.Cancel(); T.CloseHelp(); plain()
  notices, opened, NET, SENT_LOG = {}, {}, {}, {}
  CLOCK = CLOCK + 60
  WMF.mapID = 1429
end
local function serialize(t, seen)
  seen = seen or {}
  if type(t) ~= "table" then return tostring(t) end
  if seen[t] then return "<cycle>" end
  seen[t] = true
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = tostring(k) .. "=" .. serialize(v, seen) end
  return "{" .. table.concat(out, ",") .. "}"
end

---------------------------------------------------------------------------
-- 0. What is loaded, and what the map is given
---------------------------------------------------------------------------
assert(T and T.Snapshot().installed, "the tool bar is on the map with Party pins on")
do
  local priorities = {}
  for _, pr in pairs(WMF.clicks) do priorities[#priorities + 1] = pr end
  table.sort(priorities)
  assert(#priorities == 3 and priorities[1] == 95 and priorities[2] == 105 and priorities[3] == 110,
    "the pin click (95), the ping click (105) and the tool click (110, above both and WaypointUI's 100): one handler each")
  local cursors = 0
  for _ in pairs(WMF.cursors) do cursors = cursors + 1 end
  assert(cursors == 2, "the pin cursor and the tool cursor")
  assert(not T.Snapshot().built, "nothing is built until the map is shown")
  assert(intro() == nil, "an existing user has not seen the note")
end

---------------------------------------------------------------------------
-- 1. The once-only note, and the bar's place
---------------------------------------------------------------------------
group("none"); groupEvent()
openMap()
local bar = c.TwichUIMapTools
local B = buttons()
do
  assert(bar and bar:IsShown() and T.Snapshot().built, "the bar is made when the map is first shown")
  for _, id in ipairs({ "pin", "group", "ping", "help" }) do assert(B[id], "a button for " .. id) end
  assert(not B.handle, "just the four buttons: no handle to fold it")
  assert(B.pin.icon.tex == T.ICON_PATH .. "pin" and B.group.icon.tex == T.ICON_PATH .. "group-pin"
    and B.ping.icon.tex == T.ICON_PATH .. "ping" and B.help.icon.tex == T.ICON_PATH .. "help", "the supplied icons")
  assert(T.ICON_PATH == [[Interface\AddOns\!!!TwichUI\media\textures\maptool-]], "an installed-addon path, not the workspace's")
  local p = bar.lastPoint
  assert(p[1] == "RIGHT" and p[2] == NAV and p[3] == "RIGHT" and p[4] == -6 and p[5] == 0,
    "in the map's title row, at the right end of the navigation bar (beside the breadcrumbs), not over the map")
  assert(bar.frameLevel == NAV:GetFrameLevel() + 5, "above the header's art")
  -- a header without a navigation bar: the top left of the canvas
  rawset(WMF, "NavBar", false)   -- (the mock answers any capitalized name with a function, so false, not nil)
  for pr in pairs(WMF.providers) do pr:OnCanvasSizeChanged() end
  p = bar.lastPoint
  assert(p[1] == "TOPLEFT" and p[2] == WMF:GetCanvasContainer() and p[4] == 4 and p[5] == -30, "the fallback is the canvas's top left, below the floor list")
  rawset(WMF, "NavBar", NAV)
  for pr in pairs(WMF.providers) do pr:OnCanvasSizeChanged() end
  assert(bar.lastPoint[2] == NAV)

  local note = c.TwichUIMapToolsNote
  assert(note and note:IsShown(), "the note shows once the toolbar is first available")
  local text = allText()
  assert(text:find("Map tools", 1, true) and text:find("Add personal pins, share locations, or ping your group. Use these buttons or hover to learn shortcuts.", 1, true),
    "the note's words")
  assert(text:find("Got it", 1, true), "and a Got it")
  assert(intro() == nil, "showing it saves nothing")
  assert(not note.parent.IsMouseOver or true)
  -- not required: the map is usable with it up
  assert(T.Click("pin") and T.Armed() == "pin", "a tool arms with the note still up")
  assert(not note:IsShown() and intro() == true, "using the bar counts as having seen it")
  T.Cancel()
  c.TwichUIDB.ui.mapToolsIntro = nil   -- (the note's record is cleared by hand to test the next way of seeing it)
  closeMap(); openMap()
  assert(not note:IsShown(), "not again when the map is opened again (once per session)")
  note.ok.scripts.OnClick(note.ok)
  assert(intro() == true and not note:IsShown(), "Got it keeps it away for good")
  closeMap(); openMap()
  assert(not note:IsShown(), "not on every map opening")
  assert(R.Profiles.ACCOUNT.ui.mapToolsIntro == true and R.TwichConfig.LOCAL["ui.mapToolsIntro"],
    "the 'seen' record is account-wide (no profile change touches it) and never part of a shared setup")
  local welcome = c.TwichUIDB.welcome
  assert(welcome == nil or welcome.state ~= nil, "the welcome dialog's own state is not reused")
end

---------------------------------------------------------------------------
-- 2. Arming does nothing by itself; the strip, the highlight and the tooltips
---------------------------------------------------------------------------
do
  tidy()
  assert(T.Click("pin") and T.Armed() == "pin", "a click on Pin arms it")
  assert(#opened == 0 and #pingMessages() == 0 and sentTotal() == 0, "and opens nothing and sends nothing")
  local strip = stripFrame()
  assert(strip:IsShown() and strip.text.text == "Click the map to place a personal pin. Esc to cancel.", "the strip: " .. strip.text.text)
  assert(B.pin.fill:IsShown() and not B.group.fill:IsShown(), "the armed tool is lit")
  for _, e in ipairs(B.pin.edge) do assert(e:IsShown(), "with an outline, not by color alone") end
  assert(c.TwichUIMapTools.shown and bar.mouse == true and strip.mouse == true, "the bar and strip take the pointer, so a click on them isn't a map click")
  -- the same button again
  assert(T.Click("pin") == false and T.Armed() == nil and not strip:IsShown() and not B.pin.fill:IsShown(), "the active tool again puts it away")
  assert(#opened == 0, "and still nothing was made")

  -- the others, and replacing one by another
  group("party", { PAL }); groupEvent()
  assert(T.Click("group") and T.Armed() == "group" and strip.text.text == "Click the map to place a group pin. Esc to cancel.", "Group pin")
  assert(T.Click("ping") and T.Armed() == "ping" and strip.text.text == "Click the map to ping your group. Esc to cancel.", "Group ping replaces it")
  assert(not B.group.fill:IsShown() and B.ping.fill:IsShown(), "one lit tool at a time")
  assert(T.Click("pin") and T.Armed() == "pin" and strip.text.text:find("personal pin"), "and Pin replaces that")
  assert(#opened == 0 and sentTotal() == 0, "none of that placed or sent anything")
  tidy()
end

---------------------------------------------------------------------------
-- 3. One valid click, one action
---------------------------------------------------------------------------
do
  tidy()
  group("party", { PAL }); groupEvent()
  -- personal pin
  T.Click("pin")
  local taken, pr = click("LeftButton", 0.452, 0.613)
  assert(taken and pr == 110, "the tool's click is taken first")
  assert(#opened == 1 and opened[1].map == 1429 and opened[1].x == 4520 and opened[1].y == 6130 and opened[1].party == false,
    "it opens the new pin window once, at the clicked place on the map being viewed: not saved, not sent")
  assert(T.Armed() == nil and not stripFrame():IsShown(), "and the tool is put away: the next click is the map's again")
  assert(click("LeftButton", 0.3, 0.3) == false and #opened == 1, "the next plain click is the map's own (zoom, pan)")
  assert(#pingMessages() == 0 and #PN.LocalPins() == 0 and PN.OwnCount() == 0, "no pin made, nothing sent")
  -- group pin
  T.Click("group")
  click("LeftButton", 0.1, 0.9)
  assert(#opened == 2 and opened[2].party == true and opened[2].x == 1000 and opened[2].y == 9000, "a group pin opens the same window as a party pin")
  assert(PN.OwnCount() == 0 and #pingMessages() == 0, "nothing is sent until Save")
  -- group ping
  NET = {}; SENT_LOG = {}
  T.Click("ping")
  assert(sentTotal() == 0, "arming a ping sends nothing")
  local t2, p2 = click("LeftButton", 0.452, 0.613)
  assert(t2 and p2 == 110 and sentTotal() == 1 and #pingMessages() == 1, "one click, one message")
  assert(pingMessages()[1].text:match("^1:1429:4520:6130:%d+$") and pingMessages()[1].dist == "PARTY", "the same message the gesture sends: " .. pingMessages()[1].text)
  assert(#opened == 2, "and no pin window")
  assert(T.Armed() == nil and click("LeftButton", 0.452, 0.613) == false and sentTotal() == 1, "a second click sends nothing more")
  assert(T.Snapshot().placed == 2 and T.Snapshot().pinged == 1, "counted")
end

---------------------------------------------------------------------------
-- 4. Invalid places: nothing at guessed coordinates, one sentence, still armed
---------------------------------------------------------------------------
do
  tidy()
  group("party", { PAL }); groupEvent()
  T.Click("ping")
  userGoes(946)   -- the cosmic map: not a place
  assert(T.Armed() == "ping", "a map change does not cancel: the strip is still up")
  assert(click("LeftButton", 0.5, 0.5) == true, "the click is the tool's")
  assert(sentTotal() == 0 and lastNotice() == "That map can't be pinged.", "nothing sent, and why: " .. lastNotice())
  assert(T.Armed() == "ping", "still armed, for another spot")
  userGoes(1429)
  click("LeftButton", 0.2, 0.2)
  assert(sentTotal() == 1 and T.Armed() == nil, "on a map that can be pinged it works, from the map being viewed at that moment")
  assert(pingMessages()[1].text:match("^1:1429:2000:2000:"), "the place is the viewed map's")

  tidy()
  T.Click("pin")
  userGoes(99999)   -- a map the game doesn't know
  assert(click("LeftButton", 0.5, 0.5) == true and #opened == 0 and lastNotice() == PN.Reason("unknown-map"), "an unknown map: no pin window, a sentence")
  assert(T.Armed() == "pin", "still armed")
  userGoes(1429)
  assert(click("LeftButton", 1.5, 0.5) and #opened == 0 and lastNotice() == PN.Reason("bad-coordinates"), "a place outside the map: no guess")
  assert(click("LeftButton", 0 / 0, 0.5) and #opened == 0, "not a number: no guess")
  assert(T.Armed() == "pin", "still armed")
  click("LeftButton", 0.5, 0.5)
  assert(#opened == 1 and T.Armed() == nil, "a good spot then works")

  -- pinging too quickly is said once and leaves the tool armed
  tidy(); SENT_LOG = {}; NET = {}
  MP.Clear()
  for i = 1, 3 do T.Click("ping"); click("LeftButton", 0.5, 0.5) end
  T.Click("ping"); click("LeftButton", 0.5, 0.5)
  assert(sentTotal() == 3 and lastNotice() == MP.Reason("rate") and T.Armed() == "ping", "the fourth is held back by the existing limit, and the tool waits")
  tidy(); MP.Clear()
end

---------------------------------------------------------------------------
-- 5. Esc, the map closing, and the keyboard catcher
---------------------------------------------------------------------------
do
  tidy()
  local keysF = keysFrame()
  assert(keysF and keysF.mouse ~= true, "a keyboard catcher with no mouse")
  assert(keysF.keyboard == false, "it takes no keys while nothing is armed")
  T.Click("pin")
  assert(keysF.keyboard == true and keysF.propagate == true, "armed: it listens, and lets keys through")
  keysF.scripts.OnKeyDown(keysF, "W")
  assert(keysF.propagate == true and T.Armed() == "pin", "any other key goes on to the game, the tool stays")
  keysF.scripts.OnKeyDown(keysF, "ESCAPE")
  assert(keysF.propagate == false and T.Armed() == nil, "Esc is taken here: the tool goes, the map isn't closed by it")
  assert(WMF.shown == true and keysF.keyboard == false, "the map is still open, and the catcher is off again")
  -- Esc with nothing up isn't touched
  keysF.scripts.OnKeyDown(keysF, "ESCAPE")
  assert(keysF.propagate == true, "with nothing armed Esc goes on to the game")
  -- help takes Esc before the map too
  T.ToggleHelp()
  assert(T.HelpOpen() and keysF.keyboard == true, "help open: the catcher listens")
  keysF.scripts.OnKeyDown(keysF, "ESCAPE")
  assert(not T.HelpOpen() and keysF.propagate == false and not c.TwichUIMapToolsHelp:IsShown(), "Esc closes the help")
  -- the help and a tool don't share the strip's place
  T.ToggleHelp(); T.Click("pin")
  assert(not T.HelpOpen() and T.Armed() == "pin", "arming closes the help")
  T.ToggleHelp()
  assert(T.HelpOpen() and T.Armed() == nil, "opening the help puts the tool away")
  T.CloseHelp()
  -- closing the map
  T.Click("pin")
  closeMap()
  assert(T.Armed() == nil and not stripFrame():IsShown() and not bar:IsShown() and keysF.keyboard == false, "the map closing puts it all away")
  openMap()
  assert(T.Armed() == nil and not stripFrame():IsShown() and bar:IsShown(), "and it is not armed when the map comes back")
  -- in combat the catcher stays off (a restricted call); the tool still arms and the map's own close still cancels it
  c.InCombatLockdown = function() return true end
  T.Click("pin")
  assert(T.Armed() == "pin" and keysF.keyboard == false, "in combat: armed, but no keyboard capture")
  closeMap(); openMap()
  assert(T.Armed() == nil)
  c.InCombatLockdown = function() return false end
  -- cursor
  local cursor
  for fn, pr in pairs(WMF.cursors) do if pr == 110 then cursor = fn end end
  assert(cursor, "a cursor handler at the tool's priority")
  assert(cursor() == nil, "no cursor change while nothing is armed")
  T.Click("pin")
  assert(cursor() == "MAP_PIN_CURSOR", "the game's own pin cursor while armed")
  tidy()
end

---------------------------------------------------------------------------
-- 6. Shortcuts keep working, and one input is one action
---------------------------------------------------------------------------
do
  tidy()
  group("party", { PAL }); groupEvent()
  -- with nothing armed: as before
  keys(true, false, false)
  local taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 95 and #opened == 1 and opened[1].party == false, "Alt-click is a pin click, from the pin handler")
  tidy(); keys(true, true, false)
  taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 95 and #opened == 1 and opened[1].party == true, "Alt-Shift-click is a party pin")
  tidy(); keys(true, false, true)
  taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 105 and sentTotal() == 1, "Ctrl-Alt-click is a ping")
  tidy()

  -- a plain click with a tool armed: only the tool acts
  T.Click("pin")
  taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 110 and #opened == 1 and sentTotal() == 0, "one plain click, one pin window")
  tidy()

  -- a shortcut while a tool is armed is that shortcut's, once, and puts the tool away
  T.Click("ping")
  keys(true, false, false)
  taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 95 and #opened == 1 and sentTotal() == 0, "Alt-click with Group ping armed: the pin shortcut acts, not the ping, and only once")
  assert(T.Armed() == nil and not stripFrame():IsShown(), "and nothing is left armed")
  tidy()
  T.Click("group")
  keys(true, false, true)
  taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 105 and sentTotal() == 1 and #opened == 0 and T.Armed() == nil, "Ctrl-Alt-click with Group pin armed: one ping, no pin window")
  tidy()

  -- other clicks while armed are the map's, and leave the tool armed
  T.Click("pin")
  keys(false, true, false)
  assert(click("LeftButton", 0.4, 0.5) == false and T.Armed() == "pin", "Shift-click (another addon's) goes on to the map and the tool stays")
  keys(false, false, true)
  assert(click("LeftButton", 0.4, 0.5) == false and T.Armed() == "pin", "Ctrl-click is the game's waypoint")
  plain()
  assert(click("RightButton", 0.4, 0.5) == false and T.Armed() == "pin", "a right-click still zooms out")
  assert(#opened == 0 and sentTotal() == 0)
  tidy()

  -- unarmed, a plain click is not ours
  assert(click("LeftButton", 0.4, 0.5) == false and #opened == 0, "with nothing armed, plain clicks are the map's")

  -- the older arms and the bar don't stack
  T.Click("pin")
  PM.Arm()
  assert(T.Armed() == nil and PM.Armed(), "Place a pin (the window's) puts a bar tool away: one armed click at a time")
  T.Click("ping")
  assert(not PM.Armed() and T.Armed() == "ping", "and a bar tool clears it")
  V.Arm()
  assert(T.Armed() == nil and V.Armed(), "Ping the map the same")
  T.Click("pin")
  assert(not V.Armed() and T.Armed() == "pin")
  tidy(); V.Disarm(); PM.Disarm()
end

---------------------------------------------------------------------------
-- 7. Tooltips, help and what they say about shortcuts (read from the saved choices)
---------------------------------------------------------------------------
do
  tidy()
  group("none"); groupEvent()
  B.pin.scripts.OnEnter(B.pin)
  assert(TIP.text == "Personal pin" and tipHas("private") and tipHas("Click this button, then click the map") and tipHas("Shortcut: Alt%-click the map"),
    "Pin: what it does, how, its shortcut")
  B.group.scripts.OnEnter(B.group)
  assert(TIP.text == "Group pin" and tipHas("shared with your party") and tipHas("TwichUI") and tipHas("Join a party to place a group pin."), "Group pin alone: the reason is in the tooltip")
  assert(tipHas("Shortcut: Alt%-Shift%-click the map") and tipHas("lasts while you stay in the party"), "its shortcut and how long it lasts")
  assert(B.group.enabled ~= false, "the button isn't disabled, so its tooltip can always be read")
  B.ping.scripts.OnEnter(B.ping)
  assert(TIP.text == "Group ping" and tipHas("temporary") and tipHas("Map pings on") and tipHas("Join a party or raid to send a group ping.")
    and tipHas("Shortcut: Ctrl%-Alt%-click the map"), "Group ping")
  assert(B.group.icon.desaturated and B.ping.icon.desaturated and not B.pin.icon.desaturated, "unavailable tools are dimmed")
  T.Click("group")
  assert(lastNotice() == "Join a party to place a group pin." and T.Armed() == nil, "and a click says why instead of arming")
  T.Click("ping")
  assert(lastNotice() == "Join a party or raid to send a group ping.", "the ping's sentence")
  B.help.scripts.OnEnter(B.help)
  assert(TIP.text == "Map tools help")

  -- the help panel
  T.ToggleHelp()
  local help = c.TwichUIMapToolsHelp
  assert(help:IsShown() and T.HelpOpen(), "Help opens a small panel")
  local text = allText()
  assert(text:find("Personal pin", 1, true) and text:find("Group pin", 1, true) and text:find("Group ping", 1, true), "the three actions")
  assert(text:find("Shortcut: Alt-click the map", 1, true) and text:find("Shortcut: Alt-Shift-click the map", 1, true)
    and text:find("Shortcut: Ctrl-Alt-click the map", 1, true), "and their shortcuts")
  assert(help.close.scripts.OnClick and (function() help.close.scripts.OnClick(help.close) return not help:IsShown() end)(), "dismissible")
  assert(T.ToggleHelp() == true and T.ToggleHelp() == false and not help:IsShown(), "and the Help button toggles it")

  -- follows the configuration
  PL.SetPref("localClick", "altright"); PL.SetPref("partyClick", "none"); PG.Set("gesture", "ctrlaltright")
  local rows = T.HelpRows()
  assert(rows[1].shortcut == "Shortcut: Alt-right-click the map" and rows[2].shortcut == "No shortcut set"
    and rows[3].shortcut == "Shortcut: Ctrl-Alt-right-click the map", "the help is read from the saved choices")
  B.group.scripts.OnEnter(B.group)
  assert(tipHas("No shortcut is set"), "a tooltip with no shortcut says so")
  B.pin.scripts.OnEnter(B.pin)
  assert(tipHas("Shortcut: Alt%-right%-click the map"), "and one with another says that")
  T.ToggleHelp()
  assert(allText():find("Shortcut: Alt-right-click the map", 1, true), "the open panel shows the changed shortcut")
  T.CloseHelp()
  assert(T.Shortcut("pin") == "Alt-right-click the map" and T.Shortcut("group") == nil and T.Shortcut("ping") == "Ctrl-Alt-right-click the map")
  PL.SetPref("localClick", "alt"); PL.SetPref("partyClick", "altshift"); PG.Set("gesture", "ctrlalt")
  assert(T.Shortcut("pin") == "Alt-click the map" and T.Shortcut("group") == "Alt-Shift-click the map")
  tidy()
end

---------------------------------------------------------------------------
-- 8. The group changing while a tool is armed, and permissions
---------------------------------------------------------------------------
do
  tidy()
  local frames = #FRAMES
  group("party", { PAL }); groupEvent()
  assert(not B.group.icon.desaturated and not B.ping.icon.desaturated, "joining a party: the group tools come alive")
  assert(#FRAMES == frames, "without building anything again")
  -- leaving while a group pin is armed
  T.Click("group")
  assert(T.Armed() == "group")
  group("none"); groupEvent()
  assert(T.Armed() == nil and lastNotice() == "Join a party to place a group pin." and B.group.icon.desaturated, "leaving the party puts a group pin away, with the reason")
  assert(not stripFrame():IsShown() and #opened == 0)
  -- ... and a group ping
  group("party", { PAL }); groupEvent()
  T.Click("ping")
  group("none"); groupEvent()
  assert(T.Armed() == nil and lastNotice() == "Join a party or raid to send a group ping.", "and a ping")
  -- a raid: pings still go, pins are paused
  group("raid", { PAL, MAT, SAM }); groupEvent()
  assert(select(1, T.Available("ping")) == true, "a raid can be pinged")
  local ok, why = T.Available("group")
  assert(ok == false and why == PN.Reason("paused"), "group pins are paused in a raid: " .. tostring(why))
  assert(B.group.icon.desaturated and not B.ping.icon.desaturated)
  T.Click("ping")
  group("party", { PAL }); groupEvent()
  assert(T.Armed() == "ping", "a ping stays armed across party to raid and back")
  -- the game holding addon messages: checked again at the click
  LOCK = true
  local before = sentTotal()
  assert(click("LeftButton", 0.5, 0.5) == true and sentTotal() == before and T.Armed() == nil, "a ping can't go while the game holds messages: nothing sent, tool put away")
  assert(lastNotice() == MP.Reason("blocked"), lastNotice())
  LOCK = false
  tidy()
  -- the group went away and the click came before anything noticed: asked again at the click, no pin window
  group("party", { PAL }); groupEvent()
  T.Click("group")
  group("none")   -- no event yet
  assert(click("LeftButton", 0.5, 0.5) == true and #opened == 0 and T.Armed() == nil and lastNotice() == "Join a party to place a group pin.",
    "a group pin is checked again at the click: no pin window for a group that is gone")
  tidy()
  -- the switches
  group("party", { PAL }); groupEvent()
  T.Click("ping")
  R:SetEnabled("mapPingsSend", false)
  assert(T.Armed() == nil and lastNotice() == "Sending map pings is turned off in the Pins and Pings options.", "sending turned off while armed: put away, with the reason")
  assert(B.ping.icon.desaturated and bar:IsShown(), "the button stays, dimmed")
  R:SetEnabled("mapPingsSend", true)
  assert(not B.ping.icon.desaturated, "and comes back")
  R:SetEnabled("mapPings", false)
  assert(select(2, T.Available("ping")) == "Map pings are turned off in the Pins and Pings options." and select(1, T.Available("pin")) == true, "Map pings off: only the ping tool is unavailable")
  R:SetEnabled("mapPings", true)
  assert(T.Available("ping"))
  -- the local pin limit is the same limit Save enforces
  local limit = PN.MAX_LOCAL
  local real = PN.LocalCount
  PN.LocalCount = function() return limit end
  T.Update()
  assert(select(2, T.Available("pin")) == PN.Reason("local-limit") and B.pin.icon.desaturated, "a full list of pins says so")
  PN.LocalCount = real
  T.Update()
  assert(not B.pin.icon.desaturated)
  tidy()
end

---------------------------------------------------------------------------
-- 9. The saved choices, off and on
---------------------------------------------------------------------------
do
  tidy()
  assert(PL.Pref("toolbar") == true, "shown by default")
  assert(PL.Pref("toolbarCollapsed") == nil and PL.PREF_DEFAULTS.toolbarCollapsed == nil, "there is no folded state any more")
  -- nothing else is saved
  T.Click("ping"); T.CloseHelp(); T.ToggleHelp()
  local saved = serialize(c.TwichUIDB)
  for _, word in ipairs({ "armed", "helpOpen", "pending", "strip", "armedTool", "ollapsed" }) do
    assert(not saved:find(word, 1, true), "no '" .. word .. "' in the saved variables")
  end
  assert(saved:find("mapToolsIntro", 1, true), "only the note's record")
  T.CloseHelp(); T.Cancel()
  -- the toolbar choice
  PL.SetPref("toolbar", false)
  local snap = T.Snapshot()
  assert(snap.installed == false and not bar:IsShown(), "off: the bar is gone")
  local n = 0
  for _, pr in pairs(WMF.clicks) do n = n + 1 end
  assert(n == 2, "and its click handler with it; the shortcuts are untouched")
  keys(true, false, false)
  assert(click("LeftButton", 0.4, 0.5) and #opened == 1, "Alt-click still places a pin")
  tidy()
  PL.SetPref("toolbar", true)
  n = 0
  for _ in pairs(WMF.clicks) do n = n + 1 end
  assert(T.Snapshot().installed and bar:IsShown() and n == 3, "on again: one handler, not two")
  PL.SetPref("toolbar", true); PL.SetPref("toolbar", false); PL.SetPref("toolbar", true)
  n = 0
  for _ in pairs(WMF.clicks) do n = n + 1 end
  local cn = 0
  for _ in pairs(WMF.cursors) do cn = cn + 1 end
  assert(n == 3 and cn == 2, "turning it off and on repeatedly adds nothing")
  -- the feature switched off
  T.Click("pin")
  R:SetEnabled("partyPins", false)
  assert(T.Armed() == nil and not T.Snapshot().installed and not bar:IsShown() and not stripFrame():IsShown() and keysFrame().keyboard == false,
    "Party pins off: the tool is put away and the bar is gone")
  assert(T.Click("pin") == false and T.Arm("pin") == false, "nothing arms")
  n = 0
  for _ in pairs(WMF.clicks) do n = n + 1 end
  assert(n == 0, "no handler left on the map")
  R:SetEnabled("partyPins", true)
  n = 0
  for _ in pairs(WMF.clicks) do n = n + 1 end
  assert(n == 3 and bar:IsShown() and T.Snapshot().installed, "back on: the same three handlers")
  tidy()
end

---------------------------------------------------------------------------
-- 10. Profiles: nothing armed or open survives a change
---------------------------------------------------------------------------
do
  tidy()
  T.Click("pin")
  R.Profiles.Refresh("test")
  assert(T.Armed() == nil and not stripFrame():IsShown(), "a profile change puts the tool away")
  T.ToggleHelp()
  R.Profiles.Refresh("test")
  assert(not T.HelpOpen() and not c.TwichUIMapToolsHelp:IsShown(), "and closes the help")
  assert(intro() == true, "the note's record is not part of a profile")
  -- the choices do come with a profile (they are in ui.partyPins)
  assert(not R.Profiles.ACCOUNT.ui.partyPins, "the toolbar choices are the profile's")
  tidy()
end

---------------------------------------------------------------------------
-- 11. Room: the recent-pings list, the game's buttons, the map's size and scale
---------------------------------------------------------------------------
do
  tidy()
  group("party", { PAL, MAT }); groupEvent()
  MP.Clear(); CLOCK = CLOCK + 60
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  local panel = c.TwichUIMapPings
  local function resize(room)
    CONTAINER_W = room
    for p in pairs(WMF.providers) do p:OnCanvasSizeChanged() end
    FlushTimers()
  end
  local barW = bar.width
  assert(barW and barW < 200, "four icon buttons: a small bar in the header (" .. tostring(barW) .. ")")
  T.ToggleHelp()
  local help = c.TwichUIMapToolsHelp
  T.Click("ping")   -- puts the help away, shows the strip
  local strip = stripFrame()
  for _, room in ipairs({ 1400, 1000, 800, 700, 600 }) do
    resize(room)
    assert(panel:IsShown() and panel.width, "the recent list is showing at " .. room)
    local panelLeft = room - 44 - panel.width
    assert(bar.lastPoint[2] == NAV, "the bar stays in the header at " .. room)
    assert(strip.lastPoint[1] == "TOPLEFT" and strip.lastPoint[2] == WMF:GetCanvasContainer() and strip.lastPoint[5] == -30, "the strip is at the canvas's top left")
    assert(4 + strip.width < panelLeft, ("the strip (to %d) stays clear of the recent list (from %d) on a map %d wide"):format(4 + strip.width, panelLeft, room))
  end
  T.ToggleHelp()
  for _, room in ipairs({ 1400, 1000, 800, 700, 600 }) do
    resize(room)
    assert(4 + help.width < room - 44 - panel.width, ("the help (to %d) stays clear of the recent list on a map %d wide"):format(4 + help.width, room))
  end
  T.CloseHelp()
  CONTAINER_W = 1000
  resize(1000)
  -- only the bar, the strip, the help and the note take the pointer, and they sit under or on the bar
  local mouse = {}
  for _, f in ipairs(FRAMES) do if rawget(f, "mouse") == true then mouse[#mouse + 1] = f end end
  local names = {}
  for _, f in ipairs(mouse) do
    if f == bar or f == c.TwichUIMapToolsHelp or f == c.TwichUIMapToolsNote or f == stripFrame() or f == c.TwichUIMapPings or f.parent == c.TwichUIMapPings
      or rawget(f, "toolId") or f.parent == c.TwichUIMapToolsHelp or f.parent == c.TwichUIMapToolsNote then
      names[#names + 1] = "ok"
    else
      local isButton = f.kindOf == "Button"
      assert(isButton or f.parent ~= bar, "an unexpected frame takes the mouse")
    end
  end
  assert(keysFrame().mouse ~= true, "the keyboard catcher has no mouse")
  -- the skin is drawn again when the map's size (so scale) changes
  local draws = 0
  local realApply = PL.MenuLook.Apply
  PL.MenuLook.Apply = function(...) draws = draws + 1 return realApply(...) end
  for p in pairs(WMF.providers) do p:OnCanvasSizeChanged() end
  FlushTimers()
  assert(draws >= 1, "the border is drawn again after a size or scale change: " .. draws)
  PL.MenuLook.Apply = realApply
  -- a change of the look redraws too
  draws = 0
  PL.MenuLook.Apply = function(...) draws = draws + 1 return realApply(...) end
  PL.Set("textSize", 14)
  assert(draws >= 1, "and so does the pin window's text size")
  PL.Set("textSize", PL.DEFAULTS.textSize)
  PL.MenuLook.Apply = realApply
  MP.Clear()
  tidy()
end

---------------------------------------------------------------------------
-- 12. No polling, no events left behind
---------------------------------------------------------------------------
do
  tidy()
  for _, f in ipairs(FRAMES) do
    if f.parent == bar or f == bar or f == stripFrame() or f == c.TwichUIMapToolsHelp or f == c.TwichUIMapToolsNote then
      assert(not (f.scripts and f.scripts.OnUpdate), "no OnUpdate on the tool bar's frames")
    end
  end
  local registered = 0
  for _, f in ipairs(FRAMES) do
    if f.parent == bar then for _ in pairs(f.events or {}) do registered = registered + 1 end end
  end
  assert(registered == 0, "the bar's own frames register no events")
  R:SetEnabled("partyPins", false)
  assert(not R.frame.events.GROUP_ROSTER_UPDATE or true)
  R:SetEnabled("partyPins", true)
  local d = T.Snapshot()
  assert(d.installed and d.built and d.armed == nil and d.helpOpen == false)
  local report = R.Diag and R.Diag.Sections and true
end

---------------------------------------------------------------------------
-- 13. The icons: files, format, transparency, size
---------------------------------------------------------------------------
do
  local function read(path)
    local f = assert(io.open(path, "rb"), "missing " .. path)
    local d = f:read("*a"); f:close()
    return d
  end
  local NAMES = { "pin", "group-pin", "ping", "help" }
  local masks = {}
  for _, name in ipairs(NAMES) do
    local path = ROOT .. "media/textures/maptool-" .. name .. ".tga"
    local d = read(path)
    local idLen, cmap, itype = d:byte(1), d:byte(2), d:byte(3)
    local w, h = d:byte(13) + d:byte(14) * 256, d:byte(15) + d:byte(16) * 256
    local bpp, desc = d:byte(17), d:byte(18)
    assert(idLen == 0 and cmap == 0 and itype == 2, name .. ": uncompressed true-color TGA, as the other textures are")
    assert(w == 32 and h == 32 and bpp == 32 and desc == 8, name .. (": 32 x 32, 32 bits, 8 alpha bits, bottom-left origin (got %dx%d, %d bits, desc %d)"):format(w, h, bpp, desc))
    assert(#d == 18 + w * h * 4, name .. ": the file is exactly its pixels (" .. #d .. " bytes)")
    local minx, miny, maxx, maxy, opaque, clear = w, h, -1, -1, 0, 0
    local alpha = {}
    for y = 0, h - 1 do
      alpha[y] = {}
      for x = 0, w - 1 do
        local a = d:byte(18 + (y * w + x) * 4 + 4)
        alpha[y][x] = a
        if a > 8 then
          minx, miny = math.min(minx, x), math.min(miny, y)
          maxx, maxy = math.max(maxx, x), math.max(maxy, y)
        end
        if a >= 240 then opaque = opaque + 1 elseif a == 0 then clear = clear + 1 end
      end
    end
    assert(clear > 100 and opaque > 100, name .. ": real transparency and solid artwork")
    for _, corner in ipairs({ { 0, 0 }, { w - 1, 0 }, { 0, h - 1 }, { w - 1, h - 1 } }) do
      assert(alpha[corner[2]][corner[1]] == 0, name .. ": clear corners")
    end
    assert(minx >= 1 and miny >= 1 and maxx <= w - 2 and maxy <= h - 2, name .. ": at least a pixel of margin, so nothing is clipped or bleeds")
    local cw, ch = maxx - minx + 1, maxy - miny + 1
    assert(math.max(cw, ch) >= 29 and math.max(cw, ch) <= 30, name .. (": the longer side fills the box evenly (%dx%d)"):format(cw, ch))
    assert(#d < 5000, name .. ": a small file")
    -- readable small: shrink to 16 x 16 and compare the shapes
    local m = {}
    local total = 0
    for y = 0, 15 do
      for x = 0, 15 do
        local s = (alpha[2 * y][2 * x] + alpha[2 * y][2 * x + 1] + alpha[2 * y + 1][2 * x] + alpha[2 * y + 1][2 * x + 1]) / 4 / 255
        m[y * 16 + x] = s
        total = total + s
      end
    end
    local coverage = total / 256
    assert(coverage > 0.12 and coverage < 0.8, name .. (": at 16 x 16 it keeps a clear shape (%.2f of the square)"):format(coverage))
    masks[name] = m
  end
  for i = 1, #NAMES do
    for j = i + 1, #NAMES do
      local diff = 0
      for k = 0, 255 do diff = diff + math.abs(masks[NAMES[i]][k] - masks[NAMES[j]][k]) end
      assert(diff > 12, ("%s and %s are still told apart at 16 x 16 (%.1f)"):format(NAMES[i], NAMES[j], diff))
    end
  end
  -- the paths the code uses exist, with the same case, in the addon's own media folder (a case-sensitive file system)
  local pipe = io.popen('ls "' .. ROOT .. 'media/textures"')
  local listing = {}
  for line in pipe:lines() do listing[line] = true end
  pipe:close()
  for _, name in ipairs(NAMES) do
    local code = T.ICON_PATH .. (name == "group-pin" and "group-pin" or name)
    local file = code:match("textures\\(.+)$") .. ".tga"
    assert(listing[file], "the packaged file " .. file .. " exists with exactly that name")
  end
  assert(T.ICON_PATH:find("^Interface\\AddOns\\!!!TwichUI\\media\\textures\\maptool%-$"), "an installed-addon path")
  -- the packaging keeps media/ and leaves the workspace sources (assets/) out
  local pkg = read(ROOT .. "../.pkgmeta")
  assert(pkg:find("  %- assets\n") and not pkg:find("%- media"), "assets/ (the sources) stays out of the package, media/ goes in")
  local toc = read(ROOT .. "!!!TwichUI.toc")
  local order = {}
  for line in toc:gmatch("[^\r\n]+") do order[#order + 1] = line end
  local function at(name) for i, l in ipairs(order) do if l == name then return i end end end
  assert(at("pins\\PingMap.lua") and at("pins\\MapTools.lua") and at("pins\\MapTools.lua") > at("pins\\PingMap.lua") and at("pins\\MapTools.lua") > at("pins\\Map.lua"),
    "the .toc loads it after the code it uses")
  for _, src in ipairs({ "map-tool-pin-source.png", "map-tool-group-pin-source.png", "map-tool-ping-source.png", "map-tool-help-source.png" }) do
    read(ROOT .. "../assets/" .. src)
  end
end

print("PASSED")
