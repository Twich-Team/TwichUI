-- Map pings: the message and its checks, the recent list, the gesture, the rings, click to open a map and replay,
-- the sound and rate limits, and what is kept. The network and the game's frames are the harness's mocks, so this
-- shows TwichUI's own bookkeeping: how it looks and behaves on the real map, and whether the game delivers a
-- message to a second player, are for the game.
--   1  the gesture: only the exact keys send; nothing else on the map does
--   2  sending: the text, the channel for a party, a raid and an instance group (one message when they overlap),
--      refusals with a sentence, the sending limit
--   3  receiving: every check in order, names in every form, malformed and newer messages, duplicates
--   4  limits: per sender, sounds, entries, how many are kept; expiry with one timer
--   5  the map: drawing on the right map, a parent map, nothing on a sibling, many at once, reduced motion, the
--      one OnUpdate only while something shows
--   6  the list: closed map, other map, click to navigate and replay, a map that is slow, a stale click, an
--      expired entry, rapid clicks, no rebroadcast and no new entry for a replay
--   7  the local test ping, the group changing, switches off, and that nothing about a ping is saved
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
c.CreateFrame = function(kind, name)
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
WMF.mapID, WMF.providers, WMF.clicks, WMF.cursors = 1429, {}, {}, {}
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
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua",
  "diag/Diagnostics.lua", "diag/Pins.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PN, PM, PL, PG, MP, V = R.Pins, R.PinsMap, R.PinsLook, R.PinsLook.Ping, R.MapPing, R.MapPingView
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
group("party", { PAL, MAT })

---------------------------------------------------------------------------
-- 0. What is loaded and registered, and the click handler
---------------------------------------------------------------------------
assert(MP and V and PG and MP.PREFIX == "TwichUIPing" and MP.PROTOCOL == 1)
assert(c._comm.TwichUIPing, "the prefix is registered once, with the game's addon-message library")
assert(MP.Active() and V.Snapshot().installed, "on by default with Party pins, and on the map")
local priorities = {}
for _, pr in pairs(WMF.clicks) do priorities[#priorities + 1] = pr end
table.sort(priorities)
assert(#priorities == 2 and priorities[1] == 95 and priorities[2] == 105, "the pin click (95) and the ping click (105, above WaypointUI's 100)")
WMF.shown = true
assert(PG.GAME_SOUND == "Game map ping" and PG.Get("gesture") == "ctrlalt" and PG.Get("seconds") == 4 and PG.Get("reducedMotion") == false)

---------------------------------------------------------------------------
-- 1. The gesture: only the exact keys send; no other click does
---------------------------------------------------------------------------
do
  NET = {}; SENT_LOG = {}
  for _, k in ipairs({ { false, false, false }, { true, false, false }, { false, true, false }, { false, false, true },
    { true, true, false }, { false, true, true }, { true, true, true } }) do
    keys(k[1], k[2], k[3])
    local taken, pr = click("LeftButton", 0.4, 0.5)
    assert(not taken or pr == 95, "no ping click for keys " .. tostring(k[1]) .. tostring(k[2]) .. tostring(k[3]))
  end
  keys(false, false, false)
  assert(sentTotal() == 0 and #notices == 0, "plain clicks, Alt, Shift, Ctrl and their other mixes send nothing and say nothing")
  assert(not click("RightButton", 0.4, 0.5), "a right-click still zooms out")
  keys(true, false, true)
  assert(not click("RightButton", 0.4, 0.5), "Ctrl-Alt-right-click is not the default gesture")
  local taken, pr = click("LeftButton", 0.4, 0.5)
  assert(taken and pr == 105, "Ctrl-Alt-click is taken by the ping handler, before WaypointUI's and the game's")
  assert(sentTotal() == 1, "and sends exactly one message")
  keys(false, false, false)
end

-- no gesture shares keys with a pin-placing click
do
  for _, g in ipairs(PG.GESTURES) do
    if g[3] then
      for _, pc in ipairs(PL.CLICKS) do
        if pc[3] then
          assert(not (g[3] == pc[3] and g[4] == pc[4] and g[5] == pc[5] and g[6] == pc[6]), g[1] .. " never equals the pin click " .. pc[1])
          assert(pc[6] == false, "pin clicks never hold Ctrl, so a ping gesture (Ctrl) can't be one")
        end
      end
    end
  end
  assert(PG.HowTo():find("Ctrl%-Alt%-click"), "the help line says the gesture: " .. PG.HowTo())
end

---------------------------------------------------------------------------
-- 2. Sending
---------------------------------------------------------------------------
do
  local function send(mx, my, map) NET = {}; return MP.Send(map or 1429, mx, my) end
  fresh(); SENT_LOG = {}
  -- a party
  local ok, ping = send(0.452, 0.613)
  assert(ok and ping.map == 1429 and ping.x == 4520 and ping.y == 6130, "coordinates are the map's own, as whole steps")
  local m = pingMessages()
  assert(#m == 1 and m[1].dist == "PARTY" and m[1].prefix == "TwichUIPing", "a party: one message, PARTY")
  assert(m[1].text:match("^1:1429:4520:6130:%d+$") and #m[1].text <= MP.LIMITS.maxText, "version, map, steps, sequence: " .. m[1].text)
  assert(not m[1].text:find("Rich"), "no name in the message")
  local first = tonumber(m[1].text:match(":(%d+)$"))
  CLOCK = CLOCK + 4
  send(0.1, 0.1)
  assert(tonumber(pingMessages()[1].text:match(":(%d+)$")) == (first + 1) % 65536 or tonumber(pingMessages()[1].text:match(":(%d+)$")) == first + 1, "the sequence goes up by one")

  -- a raid
  fresh(); group("raid", { PAL, MAT, SAM })
  send(0.5, 0.5)
  assert(#pingMessages() == 1 and pingMessages()[1].dist == "RAID", "a raid: RAID")
  -- an instance group inside a home party: one message, to the instance group, never both
  fresh(); group("party", { PAL }, true)
  send(0.5, 0.5)
  assert(#pingMessages() == 1 and pingMessages()[1].dist == "INSTANCE_CHAT", "overlapping groups: one message, INSTANCE_CHAT")
  -- an instance group alone
  fresh(); group("none", { PAL }, true)
  send(0.5, 0.5)
  assert(#pingMessages() == 1 and pingMessages()[1].dist == "INSTANCE_CHAT", "an instance group alone: INSTANCE_CHAT")
  -- never to the guild, a channel or a whisper
  for _, m2 in ipairs(SENT_LOG) do assert(m2.dist == "PARTY" or m2.dist == "RAID" or m2.dist == "INSTANCE_CHAT", "only group channels: " .. tostring(m2.dist)) end

  -- refusals
  fresh(); group("none"); SENT_LOG = {}
  local r, why = send(0.5, 0.5)
  assert(r == false and why == "no-group" and MP.Reason(why) == "Join a party or raid to ping." and #pingMessages() == 0, "not in a group")
  group("party", { PAL })
  LOCK = true
  r, why = send(0.5, 0.5)
  assert(r == false and why == "blocked" and #pingMessages() == 0, "the game holding addon messages")
  LOCK = false
  r, why = send(0.5, 0.5, 9999)
  assert(r == false and why == "unsupported-map" and #pingMessages() == 0, "a map the game doesn't know")
  r, why = send(0.5, 0.5, 946)
  assert(r == false and why == "unsupported-map", "the cosmic map isn't a place")
  for _, bad in ipairs({ { -0.01, 0.5 }, { 0.5, 1.01 }, { 0 / 0, 0.5 }, { 0.5, math.huge }, { nil, 0.5 }, { "0.5", 0.5 } }) do
    r, why = send(bad[1], bad[2])
    assert(r == false and why == "bad-coordinates" and #pingMessages() == 0, "coordinates outside the map send nothing")
  end
  r = send(0, 1)
  assert(r == true, "the map's own corners are fine")
  R:SetEnabled("mapPingsSend", false)
  r, why = send(0.5, 0.5)
  assert(r == false and why == "send-off" and #pingMessages() == 0, "sending off")
  R:SetEnabled("mapPingsSend", true)

  -- the sending limit: a burst of three, then one every three seconds; refused ones send nothing
  fresh(); NET = {}; SENT_LOG = {}
  local okCount = 0
  for _ = 1, 8 do if MP.Send(1429, 0.5, 0.5) then okCount = okCount + 1 end end
  assert(okCount == MP.LIMITS.outBurst and sentTotal() == 3, "a burst of " .. MP.LIMITS.outBurst .. ", then no more: " .. okCount)
  r, why = MP.Send(1429, 0.5, 0.5)
  assert(why == "rate")
  CLOCK = CLOCK + 3.1
  assert(MP.Send(1429, 0.5, 0.5) and sentTotal() == 4, "one more after three seconds")
  -- the game refusing the message is counted, not repeated and not shouted about
  fresh(); group("party", { PAL })
  FAIL_SEND = function() return true end
  MP.Send(1429, 0.5, 0.5)
  FAIL_SEND = nil
  assert(MP.Snapshot().refused == 1 and #notices == 0, "a refused send is counted quietly")
end

---------------------------------------------------------------------------
-- 3. Receiving
---------------------------------------------------------------------------
do
  fresh(); group("party", { PAL, MAT })
  local before = MP.Snapshot().received
  inject(msg(1429, 4000, 5000), PAL)
  local list = MP.Entries()
  assert(#list == 1 and list[1].name == PAL and list[1].map == 1429 and list[1].x == 4000 and list[1].y == 5000, "a good ping is kept")
  assert(list[1].at == CLOCK, "its time is when it arrived here")
  assert(MP.Snapshot().received == before + 1)

  local function dropped(text, sender, dist, code)
    CLOCK = CLOCK + 3   -- past the sender's rate limit, which has its own checks below
    local n = #MP.Entries()
    inject(text, sender or PAL, dist)
    assert(#MP.Entries() == n, "set aside: " .. tostring(text))
    if code then
      local found = false
      for _, line in ipairs(MP.Snapshot().drops) do if line:sub(1, #code + 1) == code .. " " then found = true end end
      assert(found, "counted as " .. code .. ": " .. table.concat(MP.Snapshot().drops, ", "))
    end
  end
  CLOCK = CLOCK + 100
  -- the shape
  dropped("", PAL, nil, "malformed")
  dropped("hello", PAL, nil, "malformed")
  dropped("1:1429:4000:5000", PAL, nil, "malformed")
  dropped("1:1429:4000:5000:7:9", PAL, nil, "malformed")
  dropped("1:1429:4000:5000:Mallory", PAL, nil, "malformed")
  dropped("1:1429:4000:5000:7:Mallory", PAL, nil, "malformed")
  dropped("1:1429:-4:5000:7", PAL, nil, "malformed")
  dropped("1:1429:4.5:5000:7", PAL, nil, "malformed")
  dropped("1:1429:4000:5000:123456", PAL, nil, "malformed")
  dropped("1:14291429142914:4000:5000:7", PAL, nil, "malformed")
  dropped("1:1429:4000:5000:7|cffff0000x", PAL, nil, "malformed")
  dropped(("1:1429:4000:5000:7"):rep(5), PAL, nil, "too-large")
  dropped(1234, PAL, nil, "unreadable")
  -- versions
  dropped("2:1429:4000:5000:9", PAL, nil, "newer-protocol")
  dropped("0:1429:4000:5000:9", PAL, nil, "bad-version")
  -- ranges and maps
  dropped("1:1429:10001:5000:10", PAL, nil, "bad-coordinates")
  dropped("1:1429:4000:99999:11", PAL, nil, "bad-coordinates")
  dropped("1:9999:4000:5000:12", PAL, nil, "unsupported-map")
  dropped("1:946:4000:5000:13", PAL, nil, "unsupported-map")
  dropped("1:0:4000:5000:14", PAL, nil, "unsupported-map")
  assert(#MP.Entries() == 1, "nothing but the good ping was kept")
  inject("1:1429:10000:0:15", PAL)
  assert(#MP.Entries() == 2 and MP.Entries()[1].x == 10000 and MP.Entries()[1].y == 0, "the corners are inside the map")

  -- who and where
  fresh()
  dropped(msg(1429, 1, 2), "Stranger Nobody", "PARTY", "not-member")
  dropped(msg(1429, 1, 2), PAL, "GUILD", "channel")
  dropped(msg(1429, 1, 2), PAL, "WHISPER", "channel")
  dropped(msg(1429, 1, 2), PAL, "SAY", "channel")
  dropped(msg(1429, 1, 2), PAL, "RAID", "channel")             -- not in a raid
  dropped(msg(1429, 1, 2), PAL, "INSTANCE_CHAT", "channel")    -- not in an instance group
  local selfBefore = #MP.Entries()
  inject(msg(1429, 1, 2), SELF); inject(msg(1429, 1, 2), SELF .. "-Forever")
  assert(#MP.Entries() == selfBefore, "your own message, echoed back, is ignored")
  -- the channels that do fit
  group("raid", { PAL, MAT, SAM })
  dropped(msg(1429, 1, 2), PAL, "PARTY", "channel")            -- a raid isn't a party
  inject(msg(1429, 1, 2), SAM, "RAID")
  assert(#MP.Entries() == 1 and MP.Entries()[1].name == SAM, "a raid member over RAID")
  fresh(); group("party", { PAL }, true)
  inject(msg(1429, 3, 4), PAL, "INSTANCE_CHAT")
  assert(#MP.Entries() == 1, "an instance group member over INSTANCE_CHAT")
  fresh(); group("party", { PAL, MAT })

  -- the sender is what the game says; nothing inside a message can name anyone
  inject(msg(1429, 1, 2), PAL)
  assert(MP.Entries()[1].name == PAL)
  assert(not MP.Entries()[1].text, "no payload text is kept")
  -- in a raid the roster has you in it: your own message, echoed back, is still ignored
  fresh(); group("raid", { SELF, PAL })
  sounds = {}
  inject(msg(1429, 1, 2), SELF, "RAID")
  assert(#MP.Entries() == 0 and #sounds == 0, "your own ping, echoed by a raid, is not taken in")
  group("party", { PAL, MAT })
end

-- names in every form
do
  local SH = R.Share
  assert(SH.SameName("Pal Stonebrook", "Pal Stonebrook-Forever"), "Forever: a realm suffix on a first and last name is not part of it")
  assert(SH.SameName("pal stonebrook", "Pal Stonebrook"), "case is not a difference")
  assert(not SH.SameName("Pal Stonebrook", "Pal Stonebridge"))
  group("party", { "Pal Stonebrook-Forever", MAT })
  fresh(); inject(msg(1429, 1, 2), "Pal Stonebrook")
  assert(#MP.Entries() == 1, "the roster says Name-Realm, the message says Name: the same member")
  fresh(); group("party", { PAL, MAT })
  inject(msg(1429, 1, 2), "Pal Stonebrook-Forever")
  assert(#MP.Entries() == 1 and MP.Entries()[1].name == "Pal Stonebrook", "the message says Name-Realm, the roster says Name; shown without the realm")
  fresh()
  inject(msg(1429, 1, 2), "|cffff0000Pal Stonebrook")
  assert(#MP.Entries() == 0, "a name with a color escape isn't any member")

  -- a client whose names have realms (no space in your own name): "Name" and "Name-Realm" are the same player on your realm
  SELFNAME = "Rich"
  group("party", { "Pal", "Mat-Forever", "Ann-Elsewhere" })
  fresh()
  inject(msg(1429, 1, 2), "Pal-Forever")
  inject(msg(1429, 3, 4), "Mat")
  inject(msg(1429, 5, 6), "Ann-Elsewhere")
  assert(#MP.Entries() == 3, "same realm with or without the suffix, and another realm's member by their full name: " .. #MP.Entries())
  fresh(); CLOCK = CLOCK + 10
  inject(msg(1429, 1, 2), "Ann")
  assert(#MP.Entries() == 0, "Ann on your realm isn't Ann-Elsewhere")
  inject(msg(1429, 1, 2), "Rich-Forever")
  assert(#MP.Entries() == 0, "and your own name in any form is you")
  SELFNAME = SELF
  group("party", { PAL, MAT })
end

-- duplicates
do
  fresh(); group("party", { PAL, MAT })
  inject("1:1429:4000:5000:77", PAL)
  inject("1:1429:4000:5000:77", PAL)
  inject("1:1429:9000:100:77", PAL)
  assert(#MP.Entries() == 1, "the same sequence from the same sender is one ping, even with other numbers")
  inject("1:1429:4000:5000:77", MAT)
  assert(#MP.Entries() == 2, "another sender can use the same number")
  local found = false
  for _, line in ipairs(MP.Snapshot().drops) do if line:find("^duplicate ") then found = true end end
  assert(found)
end

---------------------------------------------------------------------------
-- 4. Limits: per sender, sounds, how much is kept, expiry
---------------------------------------------------------------------------
local function acceptedBy(fn) local before = MP.Snapshot().received; fn(); return MP.Snapshot().received - before end
do
  fresh(); group("party", { PAL, MAT })
  local seq = 300
  local n = acceptedBy(function()
    for i = 1, 12 do seq = seq + 1; inject(("1:1429:%d:100:%d"):format(1000 + i, seq), PAL) end
  end)
  assert(n == MP.LIMITS.inBurst, "a sender gets a burst of " .. MP.LIMITS.inBurst .. " at once and no more: " .. n)
  seq = seq + 1
  assert(acceptedBy(function() inject(("1:1429:5:5:%d"):format(seq), MAT) end) == 1, "another sender is not held by the first's")
  CLOCK = CLOCK + 2.6
  seq = seq + 1
  assert(acceptedBy(function() inject(("1:1429:6:6:%d"):format(seq), PAL) end) == 1, "and one more after 2.5 seconds")
  local codes = table.concat(MP.Snapshot().drops, " ")
  assert(codes:find("rate 8", 1, true), "the rest were counted, quietly: " .. codes)
  assert(#notices == 0 and #caught == 0, "set-aside pings make no messages")

  -- thousands of messages from the whole group: what is kept stays small
  fresh(); group("raid", { PAL, MAT, SAM, "Ann Hale", "Bo Hale" })
  local names = { PAL, MAT, SAM, "Ann Hale", "Bo Hale" }
  for i = 1, 1500 do
    CLOCK = CLOCK + 0.6
    inject(("1:1429:%d:%d:%d"):format(i % 10000, (i * 7) % 10000, i % 60000), names[i % #names + 1], "RAID")
  end
  local snap = MP.Snapshot()
  assert(snap.entries <= PG.Get("listSize") and snap.entries <= 5, "the list stays at its size: " .. snap.entries)
  assert(snap.senders <= #names and snap.senders <= MP.LIMITS.maxSenders, "sender state is per member of the group: " .. snap.senders)
  group("party", { PAL, MAT })
end

-- sound: one policy, arrivals and replays
do
  fresh(); group("party", { PAL, MAT }); PG.Reset()
  closeMap()
  local setBefore = #WMF.setCalls
  inject(msg(1429, 100, 100), PAL)
  assert(#sounds == 1 and sounds[1][1] == "kit" and sounds[1][2] == c.SOUNDKIT.MAP_PING, "the game's own map ping by default, with the map closed")
  inject(msg(1429, 100, 100), MAT)
  assert(#sounds == 1, "a second ping at once is silent (one sound a second and a half)")
  CLOCK = CLOCK + 1.6
  inject(msg(1429, 100, 100), MAT)
  assert(#sounds == 2, "and another a moment later is heard")
  CLOCK = CLOCK + 2
  inject(msg(1429, 100, 100), PAL)
  assert(#sounds == 2, "the same sender again within five seconds is silent")
  CLOCK = CLOCK + 5
  inject(msg(1429, 100, 100), PAL)
  assert(#sounds == 3, "and heard after five")
  assert(#MP.Entries() == 4, "silent ones are still listed (two each from two players): " .. #MP.Entries())
  assert(#WMF.setCalls == setBefore and not WMF.shown, "a ping arriving never opens or moves the map")
  assert(#notices == 0, "and says nothing")

  -- muted
  PG.Set("sound", false)
  CLOCK = CLOCK + 10; sounds = {}
  inject(msg(1429, 100, 100), PAL)
  assert(#sounds == 0 and MP.Snapshot().silent >= 1, "sound off: no sound")
  PG.Set("sound", true)
  -- a chosen file and its channel
  PG.Set("soundFile", "TwichUI Map Pin"); PG.Set("channel", "Master")
  CLOCK = CLOCK + 10
  inject(msg(1429, 100, 100), MAT)
  assert(#sounds == 1 and sounds[1][1] == "file" and sounds[1][2]:find("TwichUI_MapPin.mp3", 1, true) and sounds[1][3] == "Master", "a chosen sound on its channel")
  -- a chosen sound that has gone: the game's, and the choice is kept
  PG.Set("soundFile", "Vanished Sound")
  CLOCK = CLOCK + 10; sounds = {}
  inject(msg(1429, 100, 100), PAL)
  assert(#sounds == 1 and sounds[1][1] == "kit" and PG.Get("soundFile") == "Vanished Sound" and MP.Snapshot().soundFallback, "a sound that has gone plays the game's and stays chosen")
  PG.Set("soundFile", PG.GAME_SOUND); PG.Set("channel", "SFX")
  assert(not PG.Set("soundFile", ""), "an unusable value is refused")
  assert(not PG.Set("channel", "Loud") and not PG.Set("seconds", 99) and not PG.Set("listSize", 2) and not PG.Set("gesture", "alt"), "and so are the rest")
  assert(PG.Get("seconds") == 4 and PG.Get("gesture") == "ctrlalt")
end

-- the list: size, per sender, expiry with a single timer
do
  fresh(); LONG_TIMERS = {}
  group("raid", { PAL, MAT, SAM, "Ann Hale", "Bo Hale", "Cy Hale" })
  PG.Reset()
  local names = { PAL, MAT, SAM, "Ann Hale", "Bo Hale", "Cy Hale" }
  for i, n in ipairs(names) do CLOCK = CLOCK + 0.1; inject(msg(1429, i, i), n, "RAID") end
  local list = MP.Entries()
  assert(#list == 5 and list[1].name == "Cy Hale" and list[5].name == MAT, "five at most, newest first")
  PG.Set("listSize", 3)
  assert(#MP.Entries() == 3 and MP.Entries()[3].name == "Ann Hale", "a smaller size trims the oldest at once")
  PG.Set("listSize", 5)
  -- two from one sender
  fresh(); group("party", { PAL, MAT })
  for i = 1, 4 do CLOCK = CLOCK + 3; inject(msg(1429, i, i), PAL) end
  assert(#MP.Entries() == 2 and MP.Entries()[1].x == 4 and MP.Entries()[2].x == 3, "at most two from one player; a new one replaces their oldest")
  -- expiry counts from arrival, with one timer
  fresh(); LONG_TIMERS = {}; group("party", { PAL, MAT })
  PG.Set("listMinutes", 1)
  inject(msg(1429, 1, 1), PAL); CLOCK = CLOCK + 20
  inject(msg(1429, 2, 2), MAT)
  assert(#LONG_TIMERS == 1 and MP.Snapshot().timerWaiting, "one timer for the oldest entry's end, not one per ping: " .. #LONG_TIMERS)
  CLOCK = CLOCK + 41
  RunLongTimers(math.huge)
  assert(#MP.Entries() == 1 and MP.Entries()[1].name == MAT, "the older entry is gone after a minute")
  assert(MP.Snapshot().timerWaiting, "and the timer waits for the next")
  CLOCK = CLOCK + 25
  RunLongTimers(math.huge)
  assert(#MP.Entries() == 0 and not MP.Snapshot().timerWaiting, "then nothing is waiting")
  -- a sender's clock is never read: the message has none; the entry's time is ours
  PG.Reset()
end

---------------------------------------------------------------------------
-- 5. The map: where a ping is drawn, how it moves, how many, reduced motion, the one OnUpdate
---------------------------------------------------------------------------
local function near(a, b) return math.abs(a - b) < 0.01 end
local function effects()   -- the frames showing a ping now (the others are in the pool, hidden)
  local out = {}
  for _, f in ipairs(framesWith("rings")) do if f.shown then out[#out + 1] = f end end
  return out
end
local function stepFx(seconds, dt)
  dt = dt or 0.05
  for _ = 1, math.floor(seconds / dt + 0.5) do
    local list = {}
    for fr, fn in pairs(UPDATERS) do list[#list + 1] = { fr, fn } end
    for _, u in ipairs(list) do u[2](u[1], dt) end
  end
end
local function rowsShown()
  local out = {}
  for _, r in ipairs(framesWith("action")) do if r.shown and r.entry then out[#out + 1] = r end end
  return out
end
local function provider(fn) for p in pairs(WMF.providers) do if p[fn] then p[fn](p) end end end
local sendsAtStart = sentTotal()

do
  fresh(); group("party", { PAL, MAT, SAM }); PG.Reset()
  WMF.mapID = 1429; WMF.shown = true; CANVAS_W, CANVAS_H, SCALE, CONTAINER_W = 1000, 700, 1, 1000
  local base = count(UPDATERS)
  inject(msg(1429, 4000, 5000), PAL)
  local fx = effects()
  assert(#fx == 1, "one frame for one ping: " .. #fx .. " " .. tostring(V.Snapshot().installed) .. " " .. tostring(V.Snapshot().open) .. " " .. tostring(V.Snapshot().showing))
  local f = fx[1]
  assert(f.lastPoint[1] == "CENTER" and f.lastPoint[2] == canvas and f.lastPoint[3] == "TOPLEFT" and near(f.lastPoint[4], 400) and near(f.lastPoint[5], -350),
    "the middle of the marker is 40% across and 50% down the map")
  assert(f.label.text == PAL and f.shown, "the sender's name by the marker")
  assert(f.plate and f.mark and f.markDark and f.rings[1].dark and f.rings[1].ring, "a dark edge under every bright part, a plate under the name")
  assert(next(f.scripts) == nil, "no mouse scripts on a ping: the map's clicks are the map's")
  assert(count(UPDATERS) == base + 1, "the one OnUpdate runs while a ping shows")
  stepFx(0.5)
  assert(f.rings[1].shown and f.rings[2].shown, "rings are out after a moment")
  stepFx(3.25)
  assert(f.alpha < 1 and f.alpha > 0, "it is fading near the end: " .. tostring(f.alpha))
  stepFx(0.6)
  assert(not f.shown and V.Snapshot().showing == 0, "and then it's gone")
  assert(count(UPDATERS) == base, "the OnUpdate is taken off when nothing shows")

  -- reduced motion: the marker and name, no rings
  PG.Set("reducedMotion", true)
  CLOCK = CLOCK + 10
  inject(msg(1429, 4000, 5000), MAT)
  f = effects()[1]
  stepFx(1.0)
  assert(f.shown and f.label.text == MAT and f.alpha == 1, "marker and name stay, undimmed")
  assert(not f.rings[1].shown and not f.rings[2].shown, "no rings")
  stepFx(3.2)
  assert(not f.shown and count(UPDATERS) == base, "it fades and goes")
  PG.Set("reducedMotion", false)
  PG.Set("seconds", 2)
  CLOCK = CLOCK + 10
  inject(msg(1429, 4000, 5000), MAT)
  stepFx(1.9); assert(f.shown); stepFx(0.3); assert(not f.shown, "the time is the player's choice")
  PG.Set("seconds", 4)
end

do
  -- one frame per sender, a new ping takes the sender's frame
  fresh(); group("party", { PAL, MAT, SAM })
  inject(msg(1429, 1000, 1000), PAL)
  CLOCK = CLOCK + 3; inject(msg(1429, 9000, 9000), PAL)
  assert(V.Snapshot().showing == 1, "a sender has one ping on the map")
  assert(near(effects()[1].lastPoint[4], 900), "and it's the newest")
  inject(msg(1429, 5000, 5000), MAT); inject(msg(1429, 6000, 6000), SAM)
  assert(V.Snapshot().showing == 3, "three players, three pings")
  stepFx(5)

  -- many at once: a bounded number of frames
  fresh()
  local names = {}
  for i = 1, 12 do names[i] = ("Member%d Hale"):format(i) end
  group("raid", names)
  for i, n in ipairs(names) do inject(msg(1429, i * 100, 500), n, "RAID") end
  local snap = V.Snapshot()
  assert(snap.showing <= 6 and snap.frames == 6, "at most six pings on the map, six frames in all: " .. snap.showing .. "/" .. snap.frames)
  assert(#MP.Entries() <= 5 and snap.rows <= 5, "and the list is its size")
  stepFx(5)
  assert(V.Snapshot().showing == 0)

  -- drawn on its map and on a parent of it, never on a sibling; moves with the map
  fresh(); group("party", { PAL, MAT })
  WMF.mapID = 1429
  inject(msg(1429, 4000, 5000), PAL)
  local f = effects()[1]
  WMF.mapID = 1415; provider("OnMapChanged")
  assert(f.shown and near(f.lastPoint[4], 290) and near(f.lastPoint[5], -385), "on the continent it's where the game's world positions put it: " .. f.lastPoint[4] .. ", " .. f.lastPoint[5])
  WMF.mapID = 1436; provider("OnMapChanged")
  assert(not f.shown, "not on a sibling map")
  WMF.mapID = 1453; provider("OnMapChanged")
  assert(not f.shown, "and not on a map inside it")
  WMF.mapID = 1429; provider("OnMapChanged")
  assert(f.shown and near(f.lastPoint[4], 400), "back on its own map it's drawn again")
  -- zoom and size
  SCALE = 2; provider("OnCanvasScaleChanged")
  assert(f.scale == 0.5 and near(f.lastPoint[4], 800) and near(f.lastPoint[5], -700), "zoomed: the same size on screen, the same place")
  CANVAS_W = 500; provider("OnCanvasSizeChanged")
  assert(near(f.lastPoint[4], 400), "resized: the same place")
  SCALE, CANVAS_W = 1, 1000; provider("OnCanvasScaleChanged"); provider("OnCanvasSizeChanged")
  -- a ping on a map this one doesn't hold is not drawn; the list has it
  local showing = V.Snapshot().showing
  inject(msg(1436, 2000, 2000), MAT)
  assert(V.Snapshot().showing == showing, "a ping on another map isn't drawn here")
  stepFx(5)
end

-- the list sits left of the game's buttons and keeps its place
do
  fresh(); group("party", { PAL, MAT }); WMF.mapID = 1429
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  local panel = c.TwichUIMapPings
  assert(panel and panel.shown, "the list is up")
  assert(panel.lastPoint[1] == "TOPRIGHT" and panel.lastPoint[2] == container and panel.lastPoint[3] == "TOPRIGHT", "top right of the map")
  assert(math.abs(panel.lastPoint[4]) >= 4 + 32 + 4, "left of the game's 32-pixel buttons (at -4), not over them: " .. panel.lastPoint[4])
  local rows = rowsShown()
  assert(#rows == 2 and rows[1].entry.name == MAT and rows[2].entry.name == PAL, "newest first")
  assert(rows[1].action.text == "Open map" and rows[2].action.text == "Replay", "a click affordance in words; another map says so")
  assert(rows[1].where.text == "Westfall" and rows[2].where.text == "Elwynn Forest", "map names are the game's")
  assert(rows[1].name.text == MAT and rows[1].age.text == "now", "sender and age")
  CLOCK = CLOCK + 30; V.RefreshList()
  assert(rowsShown()[1].age.text == "30s", rowsShown()[1].age.text)
  CLOCK = CLOCK + 90; V.RefreshList()
  assert(rowsShown()[1].age.text == "2m", rowsShown()[1].age.text)
  local widthBig = panel.width
  CONTAINER_W = 300; V.RefreshList()
  assert(panel.width == 150 and panel.width < widthBig, "a small map isn't covered by the list")
  CONTAINER_W = 1000
  local h12 = rowsShown()[1].height
  PL.Set("textSize", 16); V.RefreshList()
  assert(rowsShown()[1].height > h12 and panel.width > widthBig, "larger text: taller rows and a wider list")
  PL.Set("textSize", 12); V.RefreshList()
  PG.Set("list", false)
  assert(not panel.shown, "the list can be turned off")
  PG.Set("list", true)
  assert(panel.shown)
  stepFx(5)
end

---------------------------------------------------------------------------
-- 6. The list: a closed map, click to open a map and replay, slow maps, stale clicks, expired entries
---------------------------------------------------------------------------
local function ids() local out = {} for _, e in ipairs(MP.Entries()) do out[#out + 1] = e.id end return table.concat(out, ",") end
local function clickRow(i)
  local r = rowsShown()[i]
  assert(r, "row " .. i .. " is there")
  r.scripts.OnClick(r)
end
local function reset()
  WMF.slow, WMF.fail, WMF.setCalls, WMF.waitingFor = false, false, {}, nil
  WMF.mapID = 1429
  SCALE, CANVAS_W, CANVAS_H, CONTAINER_W = 1, 1000, 700, 1000
  openMap(); stepFx(5)
  fresh(); PG.Reset(); group("party", { PAL, MAT })
  stepFx(5)
end

-- a ping that arrives while the map is closed
do
  reset(); closeMap(); FlushTimers()
  local calls = #WMF.setCalls
  inject(msg(1429, 4000, 5000), PAL)
  assert(#sounds == 1, "the sound policy applies with the map closed")
  assert(#effects() == 0 and not c.TwichUIMapPings.shown, "nothing is drawn on a closed map")
  assert(#MP.Entries() == 1, "it's kept for the list's time")
  assert(#WMF.setCalls == calls and not WMF.shown and #notices == 0, "the map isn't opened or moved, and nothing is said")
  openMap()
  assert(c.TwichUIMapPings.shown and #rowsShown() == 1 and rowsShown()[1].entry.name == PAL, "opening the map shows the list")
  assert(#effects() == 0 and #sounds == 1, "and doesn't replay the ping or its sound")
  stepFx(5)
end

-- click an entry on another map: one request, then the replay; nothing is sent or listed again
do
  reset()
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  stepFx(5)
  CLOCK = CLOCK + 10; sounds = {}
  local before, netBefore, sentBefore = ids(), #NET, sentTotal()
  assert(rowsShown()[1].entry.name == MAT)
  clickRow(1)
  assert(#WMF.setCalls == 1 and WMF.setCalls[1] == 1436, "one request, for the entry's map")
  FlushTimers()
  assert(WMF.mapID == 1436 and V.Snapshot().replays == 1, "the map opened and the ping replayed")
  local fx = effects()
  assert(#fx == 1 and fx[1].label.text == MAT and near(fx[1].lastPoint[4], 200) and near(fx[1].lastPoint[5], -140), "at its actual place")
  assert(#sounds == 1, "with the sound the policy allows")
  assert(ids() == before and #NET == netBefore and sentTotal() == sentBefore, "the replay adds no entry and sends nothing")
  assert(rowsShown()[1].action.text == "Replay" and rowsShown()[2].action.text == "Open map", "the list now shows which are on this map")

  -- rapid clicks: the first one counts, and the sound has its own limit
  CLOCK = CLOCK + 1; sounds = {}
  local replays = V.Snapshot().replays
  clickRow(1); clickRow(1); clickRow(1); FlushTimers()
  assert(V.Snapshot().replays == replays + 1 and #WMF.setCalls == 1, "three quick clicks do it once")
  CLOCK = CLOCK + 1
  clickRow(1); FlushTimers()
  assert(V.Snapshot().replays == replays + 2 and #sounds <= 1, "and the replay sound is limited too")
  assert(sentTotal() == sentBefore and #NET == netBefore and ids() == before, "replays on this map send nothing and add no entry either")
  stepFx(5)
  -- a replay honors mute
  PG.Set("sound", false); CLOCK = CLOCK + 10; sounds = {}
  clickRow(1); FlushTimers()
  assert(#sounds == 0 and effects()[1], "muted: the ping shows, the sound doesn't")
  PG.Set("sound", true)
  -- and reduced motion
  stepFx(5); PG.Set("reducedMotion", true); CLOCK = CLOCK + 10
  clickRow(1); FlushTimers(); stepFx(0.6)
  assert(effects()[1] and not effects()[1].rings[1].shown, "reduced motion: a replay has no rings")
  PG.Set("reducedMotion", false); stepFx(5)
end

-- a map that is slow to open, a player who goes elsewhere, a newer click, a map that won't open, closing the map
do
  reset()
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  stepFx(5)
  local function pal() for i, r in ipairs(rowsShown()) do if r.entry.name == PAL then return i end end end
  local function mat() for i, r in ipairs(rowsShown()) do if r.entry.name == MAT then return i end end end
  local function fresh10() CLOCK = CLOCK + 10; stepFx(5) end

  -- slow: it waits, once, for that map
  WMF.mapID = 1436; WMF.slow = true; fresh10()
  local replays, calls = V.Snapshot().replays, #WMF.setCalls
  clickRow(pal())
  assert(#WMF.setCalls == calls + 1 and V.Snapshot().waiting and V.Snapshot().replays == replays, "asked once, waiting")
  FlushTimers()
  assert(V.Snapshot().replays == replays and #WMF.setCalls == calls + 1, "nothing is forced again while it waits")
  deliver(1429); FlushTimers()
  assert(V.Snapshot().replays == replays + 1 and not V.Snapshot().waiting and effects()[1].label.text == PAL, "the map arrived: replayed there")
  stepFx(5)

  -- it never arrives: the wait ends with one sentence, and a late arrival isn't replayed
  WMF.mapID = 1436; WMF.slow = true; fresh10(); notices = {}
  replays = V.Snapshot().replays
  clickRow(pal())
  RunLongTimers(2)
  assert(not V.Snapshot().waiting and lastNotice() == "That map didn't open.", "gave up: " .. lastNotice())
  deliver(1429); FlushTimers()
  assert(V.Snapshot().replays == replays, "an old request can't replay later")

  -- the player goes somewhere else while it waits
  WMF.mapID = 1436; WMF.slow = true; fresh10()
  local stale = V.Snapshot().stale
  clickRow(pal())
  userGoes(1415)
  assert(not V.Snapshot().waiting and V.Snapshot().stale == stale + 1, "their choice wins")
  deliver(1429); FlushTimers()
  assert(V.Snapshot().replays == replays, "and their later move isn't taken for the answer")
  assert(#WMF.setCalls >= 1)

  -- a newer click replaces an older one
  WMF.mapID = 1415; WMF.slow = true; fresh10(); notices = {}
  clickRow(pal()); CLOCK = CLOCK + 1
  clickRow(mat())
  deliver(1429); FlushTimers()
  assert(V.Snapshot().replays == replays, "the older click's map arriving doesn't replay it")
  RunLongTimers(2)
  assert(lastNotice() == "", "and no stray sentence: " .. lastNotice())

  -- the map came at once, and a newer click lands before the replay's frame: only the newer counts
  WMF.slow = false; WMF.mapID = 1415; fresh10(); notices = {}
  replays, stale = V.Snapshot().replays, V.Snapshot().stale
  clickRow(pal())                      -- arrives at once; its replay waits for the next frame
  CLOCK = CLOCK + 1; WMF.slow = true
  clickRow(mat())                      -- a newer choice
  FlushTimers()
  assert(V.Snapshot().replays == replays and V.Snapshot().stale == stale + 1, "the older replay was cancelled")
  WMF.slow = false

  -- a map that can't be shown
  WMF.slow = false; WMF.fail = true; WMF.mapID = 1415; fresh10(); notices = {}
  clickRow(pal())
  assert(lastNotice() == "That map couldn't be opened." and not V.Snapshot().waiting, "an error is one sentence")
  WMF.fail = false

  -- closing the map ends the wait; reopening it replays nothing
  WMF.slow = true; WMF.mapID = 1415; fresh10(); sounds = {}
  clickRow(mat())
  closeMap()
  assert(not V.Snapshot().waiting)
  deliver(1436); FlushTimers()
  assert(V.Snapshot().replays == replays and #effects() == 0)
  WMF.slow = false
  openMap()
  assert(#effects() == 0 and #sounds == 0, "reopening replays nothing and plays nothing")
  stepFx(5)
end

-- an entry that has expired
do
  reset()
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  stepFx(5)
  PG.Set("listMinutes", 1)
  local row = rowsShown()[1]
  local calls = #WMF.setCalls
  CLOCK = CLOCK + 70
  notices = {}
  row.scripts.OnClick(row)
  assert(lastNotice() == "That ping has expired." and #WMF.setCalls == calls, "an expired entry: one sentence, no navigation")
  assert(#MP.Entries() == 0 and not c.TwichUIMapPings.shown, "and it's gone from the list")
  PG.Set("listMinutes", 3)
end

---------------------------------------------------------------------------
-- 7. The test ping, Ping the map, the hint, the group changing, switches, and what is saved
---------------------------------------------------------------------------
do
  reset()
  local calls, sentBefore, netBefore = #WMF.setCalls, sentTotal(), #NET
  sounds = {}
  local ok = V.Test()
  assert(ok and #effects() == 1 and effects()[1].label.text == "Test ping", "the real renderer, with its own name")
  assert(near(effects()[1].lastPoint[4], 500) and near(effects()[1].lastPoint[5], -350), "in the middle of the map being viewed")
  assert(#sounds == 1, "and the real sound")
  assert(sentTotal() == sentBefore and #NET == netBefore and #MP.Entries() == 0 and #WMF.setCalls == calls, "nothing sent, listed, saved or moved")
  assert(not c.TwichUIMapPings.shown, "no list entry either")
  stepFx(5)
  assert(V.Snapshot().showing == 0 and not V.Snapshot().updating, "and it cleans up after itself")
  -- from the options with the map closed: it waits half a minute
  closeMap()
  local okClosed, text = V.Test()
  assert(okClosed and text:find("Open your world map"), text)
  openMap()
  assert(#effects() == 1 and effects()[1].label.text == "Test ping", "opening the map shows it")
  stepFx(5); closeMap()
  V.Test(); CLOCK = CLOCK + 31; openMap()
  assert(#effects() == 0, "a test left waiting is forgotten after half a minute")
  -- without the feature
  R:SetEnabled("mapPings", false)
  local off, why = V.Test()
  assert(off == false and why:find("Turn on"), why)
  R:SetEnabled("mapPings", true)
end

do
  reset(); sounds = {}
  local sentBefore = sentTotal()
  -- Ping the map: one plain click, once
  assert(R.RunCommand, "the command exists")
  R.RunCommand("ping")
  assert(V.Snapshot().armed and lastNotice() == "Click the map where the ping goes.", lastNotice())
  keys(false, false, false)
  local taken, pr = click("LeftButton", 0.3, 0.3)
  assert(taken and pr == 105 and sentTotal() == sentBefore + 1, "the armed click sends one")
  assert(not click("LeftButton", 0.3, 0.3) and sentTotal() == sentBefore + 1, "and only one")
  local m = pingMessages()
  assert(m[#m].text:match("^1:1429:3000:3000:%d+$"), m[#m].text)
  -- not in a group: a sentence, nothing armed
  group("none"); notices = {}
  R.RunCommand("ping")
  assert(not V.Snapshot().armed and lastNotice() == "Join a party or raid to ping.")
  keys(true, false, true)
  notices = {}; CLOCK = CLOCK + 4   -- the same sentence is not shown twice within three seconds
  assert(click("LeftButton", 0.3, 0.3) and lastNotice() == "Join a party or raid to ping." and sentTotal() == sentBefore + 1, "the gesture without a group: one sentence, nothing sent")
  keys(false, false, false)
  group("party", { PAL, MAT })
  -- a map the pings don't cover
  WMF.mapID = 946; keys(true, false, true); CLOCK = CLOCK + 10
  notices = {}
  assert(click("LeftButton", 0.3, 0.3) and lastNotice() == "That map can't be pinged." and sentTotal() == sentBefore + 1, "an unsupported map: a sentence, nothing sent")
  -- a click the map gives no place for
  WMF.mapID = 1429
  notices = {}
  assert(click("LeftButton", nil, nil) and lastNotice() == "That spot is outside the map.")
  assert(click("LeftButton", 1.5, 0.2) and sentTotal() == sentBefore + 1)
  -- the same sentence isn't repeated at once
  notices = {}
  click("LeftButton", 1.5, 0.2); click("LeftButton", 1.5, 0.2); click("LeftButton", 1.5, 0.2)
  assert(#notices <= 0, "a repeated sentence is shown once in a few seconds: " .. #notices)
  -- the gesture is a choice; with it off only Ping the map works
  PG.Set("gesture", "none")
  assert(not click("LeftButton", 0.3, 0.3) and sentTotal() == sentBefore + 1, "gesture off: the click is the map's")
  PG.Set("gesture", "ctrlaltright")
  keys(true, false, true)
  CLOCK = CLOCK + 10
  assert(not click("LeftButton", 0.3, 0.3), "the right-click gesture leaves the left click alone")
  assert(click("RightButton", 0.3, 0.3) and sentTotal() == sentBefore + 2, "and takes its own")
  PG.Reset()
  keys(false, false, false)
  -- sending off: the click is the map's
  R:SetEnabled("mapPingsSend", false); keys(true, false, true)
  assert(not click("LeftButton", 0.3, 0.3), "sending off: the click goes on to the map")
  R:SetEnabled("mapPingsSend", true); keys(false, false, false)
  -- own ping: shown for you, with your name, not listed
  stepFx(5); CLOCK = CLOCK + 10
  keys(true, false, true); click("LeftButton", 0.25, 0.75); keys(false, false, false)
  assert(#effects() == 1 and effects()[1].label.text == SELF, "your own ping shows with your name")
  assert(#MP.Entries() == 0, "and isn't in the list")
  stepFx(5)
end

-- the hint at the pointer
do
  reset()
  PG.Reset()
  keys(true, false, true); MOUSE_OVER = true
  c.FireEvent("MODIFIER_STATE_CHANGED", "LCTRL", 1)
  assert(TIP.shown and TIP.owner == container and TIP.text == "Click to ping your group", "held over the map: a small hint")
  keys(false, false, true)
  c.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 0)
  assert(not TIP.shown, "gone when the keys change")
  keys(true, false, true); c.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1)
  assert(TIP.shown)
  container.hooks.OnLeave()
  assert(not TIP.shown, "gone when the pointer leaves the map")
  MOUSE_OVER = false; c.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1)
  assert(not TIP.shown, "not when the pointer isn't on the map")
  MOUSE_OVER = true
  PG.Set("hint", false); c.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1)
  assert(not TIP.shown, "off by choice")
  PG.Set("hint", true)
  PG.Set("gesture", "none"); c.FireEvent("MODIFIER_STATE_CHANGED", "LALT", 1)
  assert(not TIP.shown, "no gesture, no hint")
  PG.Reset(); keys(false, false, false)
  local other = TIP.owner
  TIP.owner, TIP.shown = "something else", true
  c.FireEvent("MODIFIER_STATE_CHANGED", "LCTRL", 0)
  assert(TIP.shown, "another tooltip is never hidden by the hint")
  TIP.owner, TIP.shown = other, false
end

-- the group changes
do
  reset()
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1429, 2000, 2000), MAT)
  assert(#MP.Entries() == 2 and #effects() == 2)
  group("party", { MAT }); c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(#MP.Entries() == 1 and MP.Entries()[1].name == MAT, "a member who left takes their pings; the others keep theirs")
  CLOCK = CLOCK + 3
  inject(msg(1429, 3, 3), PAL)
  assert(#MP.Entries() == 1, "and can't send again until they are back in the group")
  group("none"); c.FireEvent("GROUP_ROSTER_UPDATE")
  assert(#MP.Entries() == 0 and not c.TwichUIMapPings.shown and MP.Snapshot().senders == 0, "leaving the group clears everything")
  assert(#effects() == 0, "and stops what's on the map")
  group("party", { PAL, MAT }); CLOCK = CLOCK + 10
  inject(msg(1429, 3, 3), PAL)
  assert(#MP.Entries() == 1, "a new group starts clean")
  stepFx(5)
end

-- switches
do
  reset()
  inject(msg(1429, 4000, 5000), PAL)
  assert(#MP.Entries() == 1 and #effects() == 1)
  R:SetEnabled("mapPings", false)
  assert(not V.Snapshot().installed and count(WMF.clicks) == 1, "off: the ping click handler is taken off the map (the pins' stays)")
  assert(#MP.Entries() == 0 and #effects() == 0 and not c.TwichUIMapPings.shown, "and its pings, list and effects go")
  local before = sentTotal()
  CLOCK = CLOCK + 10; inject(msg(1429, 1, 1), PAL)
  keys(true, false, true); local t = click("LeftButton", 0.3, 0.3); keys(false, false, false)
  assert(#MP.Entries() == 0 and not t and sentTotal() == before, "off: nothing taken in, nothing sent, the click is the map's")
  local dropsNow = #MP.Snapshot().drops
  R:SetEnabled("mapPings", true)
  assert(V.Snapshot().installed and count(WMF.clicks) == 2, "on again: back on the map, once")
  R:SetEnabled("mapPings", true); R:SetEnabled("mapPings", true)
  assert(count(WMF.clicks) == 2 and count(WMF.providers) == 2, "switching again adds nothing twice")
  -- receiving off
  R:SetEnabled("mapPingsReceive", false); CLOCK = CLOCK + 10; sounds = {}
  inject(msg(1429, 1, 1), PAL)
  assert(#MP.Entries() == 0 and #sounds == 0, "not taking in: set aside unread")
  R:SetEnabled("mapPingsReceive", true)
  -- Party pins off takes pings with it
  R:SetEnabled("partyPins", false)
  assert(not V.Snapshot().installed and not MP.Active() and count(WMF.clicks) == 0)
  CLOCK = CLOCK + 10; inject(msg(1429, 1, 1), PAL)
  assert(#MP.Entries() == 0)
  R:SetEnabled("partyPins", true)
  assert(V.Snapshot().installed and MP.Active())
end

-- nothing is saved but the choices; nothing is sent but what was clicked
do
  reset()
  inject(msg(1429, 4000, 5000), PAL); CLOCK = CLOCK + 3
  inject(msg(1436, 2000, 2000), MAT)
  PG.Set("seconds", 6); PG.Set("reducedMotion", true)
  local seen = {}
  local function walk(t, path, depth)
    if depth > 8 then return end
    for k, v in pairs(t) do
      local p = path .. "." .. tostring(k)
      if type(v) == "table" then walk(v, p, depth + 1)
      elseif type(v) == "string" then seen[#seen + 1] = p .. "=" .. v
      elseif type(v) == "number" then seen[#seen + 1] = p .. "=" .. tostring(v) end
      if type(k) == "string" then seen[#seen + 1] = p end
    end
  end
  walk(c.TwichUIDB, "db", 0)
  for _, text in ipairs(seen) do
    for _, needle in ipairs({ PAL, MAT, "Stonebrook", "Reedwater" }) do assert(not text:find(needle, 1, true), "saved data names a player: " .. text) end
  end
  local saved = c.TwichUIDB.ui.pinsPing
  assert(type(saved) == "table" and saved.seconds == 6 and saved.reducedMotion == true, "the choices are saved")
  for k in pairs(saved) do assert(PG.DEFAULTS[k] ~= nil, "only choices: " .. k) end
  assert(c.TwichUIDB.pins == nil or (c.TwichUIDB.pins.session == nil and c.TwichUIDB.pins.pings == nil), "no session or ping state")
  -- the troubleshooting section names no player, place or message
  local report = R.Diag.Build()
  local from = report:find("== Party pins ==", 1, true)
  local section = report:sub(from, report:find("\n== ", from + 5, true) or #report)
  assert(section:find("map pings:", 1, true) and section:find("prefix TwichUIPing", 1, true), "the section reports map pings")
  for _, needle in ipairs({ "Pal", "Stonebrook", "Mat", "Reedwater", "Rich", "Westfall", "Elwynn", "1429", "1436", "4000", "5000" }) do
    assert(not section:find(needle, 1, true), "the report must not hold " .. needle)
  end
  PG.Reset()
  assert(c.TwichUIDB.ui.pinsPing == nil, "reset forgets the choices, and only them")
  assert(R:Enabled("mapPings") and R:Enabled("partyPins"), "the switches aren't part of the reset")
end

-- nothing sent that wasn't asked for
do
  local sends = 0
  for _, m in ipairs(SENT_LOG or {}) do if m.prefix == "TwichUIPing" then sends = sends + 1 end end
  assert(sends == sentTotal())
  assert(#caught == 0, "no error was raised: " .. tostring(caught[1]))
end

print("MAP PING TESTS PASSED")
