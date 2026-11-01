-- Guild Locations M4: the map tools bar's eye (guildloc state through GL.Toggle, art, tooltip, Off, layout and the search
-- field's width), guildmates in the map search (npcs/SearchBar.lua with guildloc/Map.lua's GM.Search / GM.Locate: mixed with
-- NPC results, unknown class, group members, withdrawn and expired records), the searched record's drawing exemption (within the
-- 150 cap, one exemption, every way it ends) and repeated searching and opening of the map. The map, roster, clock, party and
-- frames are mocks (as in test_npc_search.lua and test_guild_locations_map.lua); the core and the NPC search are the real code.
-- Where the eye sits, how the rows look, the ring and the map's own clicks are for the game (docs/guild-locations.md).
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

-- the guild, its roster details, the party and the clock (as in test_guild_locations_map.lua)
local T0 = 1700000000
c.time = function() return T0 + math.floor(CLOCK) end
c.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior", MONK = "Monk" }
GUILD = { [SELF] = true }
GROUP = nil
local EXTRA = {}
local rosterCalls = 0
c.GetGuildInfo = function() if GUILD[SELF] ~= nil then return "The Guild" end end
c.GetGuildRosterInfo = function(i)
  local list = {}
  for k in pairs(GUILD) do list[#list + 1] = k end
  table.sort(list)
  local k = list[i]
  if k then local e = EXTRA[k] or {}; return k, "", 0, e.level, "", "", "", "", GUILD[k], "", e.class end
end
c.C_GuildInfo = { GuildRoster = function() rosterCalls = rosterCalls + 1 end }
c.UnitExists = function(u) return c.GetUnitName(u) ~= nil and u ~= "player" end
local invited = {}
c.C_PartyInfo = { CanInvite = function() return true end, InviteUnit = function(n) invited[#invited + 1] = n end }
c.GameTooltip.GetOwner = function() return TIP.owner end
for _, f in ipairs({ "chronicle/Style.lua", "FrameLook.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua", "modules/Media.lua",
  "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Ping.lua", "pins/Pulse.lua", "pins/PingMap.lua",
  "pins/MapTools.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua", "npcs/Share.lua",
  "npcs/Knowledge.lua", "npcs/Search.lua", "npcs/SearchBar.lua", "guildloc/State.lua", "guildloc/Roster.lua", "guildloc/Comm.lua",
  "guildloc/Map.lua", "SettingsBroker.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { partyPins = true, npcMap = true }, guildLoc = { state = "sharing" } }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local PL, T, NS, NP, NMAP, KN, SR, SB, PU = R.PinsLook, R.MapTools, R.NpcStore, R.NpcPrefs, R.NpcMap, R.NpcKnowledge, R.NpcSearch, R.NpcSearchBar, R.MapPulse
local GL, GM, RS = R.GuildLoc, R.GuildLoc.Map, R.GuildLoc.Roster
assert(SR and SB and PU and NMAP.Locate and GM.Search and GM.Locate and T.ToggleGuild, "the search, the pick and the eye are loaded")
local B = R.SettingsBroker

-- the guild module's timers re-read the clock when they fire, so every flush also lets a little time pass (0.75 s)
local baseFlush = FlushTimers
function FlushTimers() for _ = 1, 3 do CLOCK = CLOCK + 0.25; baseFlush() end end

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. tostring(msg), 2) end
end
local function Section(s) print("-- " .. s) end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local navs = {}
R.Nav = { Enabled = function() return true end, CanNavigate = function() return true end,
  StartAt = function(...) navs[#navs + 1] = { ... }; return true end }

local E = T0 + 2000
local seq = {}
local function Send(who, map, x, y)
  seq[who] = (seq[who] or 0) + 1
  GL.OnMessage("TwichUIGuild", ("1:p:%d:%d:%d:%d:%d"):format(E, seq[who], map or 1429, x or 5000, y or 5000), "GUILD", who)
end
local function Withdraw(who) GL.OnMessage("TwichUIGuild", ("1:w:%d"):format(E + 1), "GUILD", who) end
local function Roster() CLOCK = CLOCK + 6; c.FireEvent("GUILD_ROSTER_UPDATE"); FlushTimers(); RunLongTimers(10); CLOCK = CLOCK + 6; FlushTimers() end
local function Join(...) for _, n in ipairs({ ... }) do GUILD[n] = true end Roster() end
local function drawn()
  local list = {}
  for j = 1, 400 do
    local m = GM.Marker(j)
    if not m then break end
    if m.key then list[m.key] = m end
  end
  return list
end
local function Mk(name) return drawn()[name:lower()] end
local function Art(m) return m and m.icon.tex end

local function box() return c.TwichUIMapSearch end
local function edit()
  for _, f in ipairs(FRAMES) do if f.kindOf == "EditBox" then return f end end
end
local function field()
  for _, f in ipairs(FRAMES) do if f.hint and f.clear then return f end end
end
local function eye()
  for _, f in ipairs(FRAMES) do if f.toolId == "guild" then return f end end
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
local function Search(text) edit():SetFocus(); typeInto(text); FlushTimers() end
local function Pick(i) rowsShown()[i].scripts.OnClick(rowsShown()[i]) end
local function stand(map, x, y) PLAYER.map, PLAYER.x, PLAYER.y = map, x, y end
local function tidy()
  if edit() and edit().focused then edit():ClearFocus() end
  if edit() then edit():SetText("") end
  NMAP.ClearReveal(); GM.ClearPick()
  notices = {}
  WMF.mapID, WMF.slow, WMF.fail, WMF.setCalls = 1429, false, false, {}
  FlushTimers()
end
local A, Bo, Cc = "Alice Stone", "Bob Reeve", "Cara Dunn"
Join(A, Bo, Cc)
EXTRA[A] = { level = 60, class = "MAGE" }
EXTRA[Bo] = { level = 41, class = "WARRIOR" }
-- Cara: the roster gave neither
Roster()

PL.SetPref("npcSearch", true)
stand(1429, 0.5, 0.5)
openMap()
Check(SB.Active() and field() and edit(), "the search field is on the bar")
Send(A, 1429, 5000, 5000); Send(Bo, 1429, 2000, 2000); Send(Cc, 1436, 5000, 5000)
FlushTimers()

---------------------------------------------------------------------------
Section("1 the eye: art, state, and following every other control")
do
  local b = eye()
  Check(b and b:IsShown(), "the eye is on the bar while Guild Locations is on")
  for _, n in ipairs({ "eye-open-small", "eye-hidden-small" }) do
    local f = io.open(REPO .. "!!!TwichUI/media/guildloc/" .. n .. ".tga", "rb")
    Check(f, n .. " exists"); f:close()
  end
  Check(GL.State() == "sharing" and T.GuildArt():find("eye-open-small", 1, true) and b.icon.tex == T.GuildArt(), "Sharing: the open eye")
  Check(b.icon.width == 22, "drawn a little wider than the other icons")

  local d = T.Describe("guild")
  Check(d.title == "Guild Locations: Sharing", "the tooltip names the feature and the state: " .. d.title)
  Check(d.lines[1][1]:find("see your position", 1, true) and d.lines[#d.lines][1]:find("Invisible"), "...and what a click does")

  -- the toolbar writes through the one authority, and everything that listens hears it
  local heard = {}
  GL.OnChange(function(kind, new) heard[#heard + 1] = kind .. ":" .. new end)
  b.scripts.OnClick(b)
  Check(GL.State() == "invisible" and heard[#heard] == "state:invisible", "a click makes Sharing Invisible, through GL")
  Check(b.icon.tex:find("eye-hidden-small", 1, true), "Invisible: the slashed eye")
  Check(T.Describe("guild").title == "Guild Locations: Invisible" and T.Describe("guild").lines[1][1]:find("not shared", 1, true), "the tooltip follows")
  Check(c.TwichUIDB.guildLoc.state == "invisible", "it is saved")
  -- the launcher's menu and the settings page read the same state
  local checked
  B.BuildMenu({ CreateTitle = function() end, CreateButton = function() return {} end,
    CreateRadio = function(_, label, isOn) if label:find("Invisible") then checked = isOn() end end })
  Check(checked == true, "the launcher menu shows Invisible selected")

  -- a change made elsewhere reaches the eye (and its open tooltip)
  b.scripts.OnEnter(b)
  Check(TIP.title == "Guild Locations: Invisible", "tooltip on hover")
  GL.SetState("sharing")
  Check(b.icon.tex:find("eye-open-small", 1, true) and TIP.title == "Guild Locations: Sharing", "the settings or the menu choosing Sharing redraws the eye and the open tooltip")
  b.scripts.OnLeave(b)
  Check(#heard == 2, "one hearing per change")
end

---------------------------------------------------------------------------
Section("2 Off, outside a guild, and the bar's width")
do
  local b = eye()
  -- Off: not on the bar, and nothing turns sharing on
  GL.SetState("off")
  Check(not b:IsShown(), "Off: the eye is not on the bar")
  Check(T.ToggleGuild() == false and GL.State() == "off", "...and a click path does not start sharing from Off")
  b.scripts.OnClick(b)
  Check(GL.State() == "off", "...even if the click arrived anyway")
  GL.SetState("invisible")
  Check(b:IsShown() and b.icon.tex:find("hidden", 1, true), "back from the settings: the eye returns")

  -- outside a guild a choice is still possible
  local saved = GUILD[SELF]
  GUILD[SELF] = nil
  b.scripts.OnClick(b)
  Check(GL.State() == "sharing", "outside a guild the choice can still be made")
  local warn
  for _, l in ipairs(T.Describe("guild").lines) do if l[2] == "warn" and l[1]:find("not in a guild") then warn = true end end
  Check(warn, "...and the tooltip says nothing is sent yet")
  GUILD[SELF] = saved

  -- width: the eye takes its room from the search field, and the field is put away before it is squeezed
  local function layout(w) NAV_W = w; closeMap(); openMap() end
  local function barWidth() return c.TwichUIMapTools.width end
  layout(530)
  local on, wOn = field() and field():IsShown(), field().width
  local barOn = barWidth()
  GL.SetState("off"); FlushTimers()
  local wOff, barOff = field().width, barWidth()
  Check(on and wOn >= 90 and wOff <= 170, "the field has room both ways")
  Check(wOff - wOn == 33 and wOff < 170, "the eye's place (30 + 3) comes out of the field: " .. wOn .. " vs " .. wOff)
  Check(barOn - barOff == 33 + ((wOn - wOff)), "the bar grows by the eye and the field gives it back: " .. barOn .. " vs " .. barOff)
  GL.SetState("sharing")
  -- very little room: the field is put away, the eye stays
  layout(330)
  Check(not field():IsShown(), "no room: the field is put away")
  Check(eye():IsShown(), "...and the eye is still there")
  layout(900)
  Check(field():IsShown() and field().width == 170, "with room, the field is back at its full width")
  -- the eye sits after the other buttons, none overlapping
  local xs = {}
  for _, f in ipairs(FRAMES) do if f.toolId and f:IsShown() and f.parent == c.TwichUIMapTools then xs[#xs + 1] = f.lastPoint[4] end end
  table.sort(xs)
  for i = 2, #xs do Check(xs[i] - xs[i - 1] >= 33, "buttons are one step apart") end
  Check(eye().lastPoint[4] == xs[#xs], "the eye is the last button")
  GL.SetState("sharing")
end

---------------------------------------------------------------------------
Section("3 mixed results: guildmates and NPCs")
do
  tidy()
  -- (Off in the last section wiped what was held: they report again)
  Send(A, 1429, 5000, 5000); Send(Bo, 1429, 2000, 2000); Send(Cc, 1436, 5000, 5000); FlushTimers()
  local npcs = {
    { 1, "Brother Joseph", 1429, 0.20, 0.20, { banker = true } },
    { 2, "Innkeeper Farley", 1429, 0.50, 0.60, { innkeeper = true } },
  }
  for _, n in ipairs(npcs) do
    assert(NS.Observe({ id = n[1], name = n[2], map = n[3], x = n[4], y = n[5], tags = n[6] }))
  end
  -- names: a guildmate with an NPC's word in it
  local BR = "Brother Alden"
  Join(BR); EXTRA[BR] = { level = 12, class = "MAGE" }; Roster(); Send(BR, 1429, 5000, 5000); FlushTimers()
  local rosterBefore, netBefore = rosterCalls, #NET
  Search("brother")
  local rows = rowsShown()
  Check(#rows == 2, "an NPC and a guildmate: " .. #rows .. " first=" .. (rows[1] and rows[1].name.text or "-") .. " held=" .. GL.Snapshot().records .. " drops=" .. (function() local o = {} for k, v in pairs(GL.Snapshot().drops) do o[#o+1] = k .. v end return table.concat(o, ",") end)() .. " roster=" .. GL.Snapshot().roster .. " npcs=" .. #NS.Entries())
  local kinds = {}
  for _, f in ipairs(rows) do
    local r = f.index
  end
  -- the guildmate is at your feet: first
  local name1, meta1, dist1 = rows[1].name.text, rows[1].meta.text, rows[1].dist.text
  Check(name1 == "Brother Alden" and meta1:find("Guildmate", 1, true) and meta1:find("Mage", 1, true) and meta1:find("Elwynn Forest", 1, true), "guild row: " .. meta1)
  Check(meta1:find("s ago", 1, true), "...with how long ago: " .. meta1)
  Check(rows[1].icon.tex == GM.ArtFor({ class = "MAGE" }), "...the class badge")
  Check(dist1 == "0 yd", "...and the distance the NPCs use: " .. dist1)
  Check(rows[2].name.text == "Brother Joseph" and rows[2].meta.text:find("Banker", 1, true) and not rows[2].meta.text:find("Guildmate"), "the NPC row is as it was: " .. rows[2].meta.text)
  Check(rows[2].icon.tex ~= rows[1].icon.tex, "the types look different")
  Check(not NMAP.Revealed(), "nothing picked yet")
  -- searching asked nobody anything
  Check(rosterCalls == rosterBefore and #NET == netBefore, "memory only: no roster request and no message")

  -- an NPC is still chosen as before
  Pick(2)
  Check(NMAP.Revealed() and NMAP.Revealed().n == "Brother Joseph" and GM.Picked() == nil, "choosing an NPC picks the NPC (no guildmate)")
  Check(NMAP.Snapshot().ringing, "...with the NPC ring")
  tidy()

  -- unknown class: the emblem, still found
  Search("cara")
  rows = rowsShown()
  Check(#rows == 1 and rows[1].icon.tex == R.ICON, "no roster class: the emblem")
  Check(not rows[1].meta.text:find("Mage") and rows[1].meta.text:find("Westfall", 1, true), "...and no class is made up: " .. rows[1].meta.text)
  rows[1].scripts.OnEnter(rows[1])
  local seen
  for _, l in ipairs(TIP.lines) do if l == "Class and level not known" then seen = true end end
  Check(seen, "the tooltip says what is not known")
  tidy()

  -- class and zone words match too
  Search("warrior")
  Check(#rowsShown() == 1 and rowsShown()[1].name.text == Bo, "the class name finds a guildmate")
  tidy(); Search("westfall"); Check(#rowsShown() == 1 and rowsShown()[1].name.text == Cc, "so does the area")
  tidy(); Search("zzz"); Check(#rowsShown() == 0, "no match")
  local says
  for _, fs in ipairs(FSLIST) do if fs.text == "No known NPCs or guildmates match." then says = true end end
  Check(says, "...and the words cover both")
  tidy()
  Check(field().hint.text:find("guildmates", 1, true), "the field says guildmates are searched")

  -- a guildmate is not a decision: choosing changes nothing about privacy, sends nothing, invites no one
  local state0, nets0, inv0, nav0 = GL.State(), #NET, #invited, #navs
  Search("alice"); Pick(1)
  Check(GM.Picked() == A:lower() and GL.State() == state0 and #invited == inv0 and #navs == nav0 and #NET == nets0 and #waypoints == 0,
    "picking a guildmate invites, routes, sends and changes nothing")
  Check(GM.Snapshot().ringing, "...and rings their marker")
  Check(Mk(A) ~= nil and Art(Mk(A)) == GM.ArtFor({ class = "MAGE" }), "the marker is the usual one")
  tidy()
  Check(GM.Picked() == nil, "tidy lets it go")
end

---------------------------------------------------------------------------
Section("4 group members, stale and withdrawn records")
do
  tidy()
  -- in your group: found and labelled, no second marker
  GROUP = { [SELF] = true, [A] = true }
  c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
  Check(Mk(A) == nil, "a group member has no TwichUI marker")
  Search("alice")
  local rows = rowsShown()
  Check(#rows == 1 and rows[1].meta.text:find("In your group", 1, true), "found and labelled: " .. (rows[1] and rows[1].meta.text or "nothing"))
  Pick(1)
  Check(Mk(A) == nil and GM.Picked() == nil and not GM.Snapshot().ringing, "choosing one draws no second marker and picks nothing")
  GROUP = nil
  c.FireEvent("GROUP_ROSTER_UPDATE"); FlushTimers()
  Check(Mk(A) ~= nil, "after they leave, the marker returns")
  tidy()

  -- withdrawn while the list is open: gone from the list
  Search("e")                       -- Alice, Bob, Cara, Brother ... all with an e
  local before = #rowsShown()
  Check(before >= 3, "several guildmates match: " .. before)
  Withdraw(Bo); FlushTimers()
  local names = {}
  for _, f in ipairs(rowsShown()) do names[f.name.text] = true end
  Check(not names[Bo] and #rowsShown() == before - 1, "a withdrawal takes the row out")
  Check(GM.Search("bob", SR.Where(), 8) and #GM.Search("bob", SR.Where(), 8) == 0, "...and the search no longer finds it")
  tidy()

  -- a guildmate who only moves does not reshuffle an open list
  Search("alice")
  local runs = 0
  local realRun = SR.Run
  SR.Run = function(...) runs = runs + 1; return realRun(...) end
  Send(A, 1429, 6000, 6000); FlushTimers()
  Check(runs == 0, "an update to a listed guildmate does not search again")
  SR.Run = realRun
  tidy()

  -- expired while listed: choosing says so, searches again and has nothing to pick
  Search("alice")
  CLOCK = CLOCK + 301                               -- beyond the 300 s expiry, without any message
  Pick(1)
  Check(GM.Picked() == nil, "an expired record is not picked")
  local said
  for _, n in ipairs(notices) do if n:find("no longer shared", 1, true) then said = true end end
  Check(said, "it says so")
  Check(#rowsShown() == 0 and #GM.Search("alice", SR.Where(), 8) == 0, "and the list is made again without it")
  FlushTimers()
  Check(Mk(A) == nil, "no marker either")
  tidy()
  -- everyone expired together: refresh for the later sections
  Send(A, 1429, 5000, 5000); Send(Bo, 1429, 2000, 2000); Send(Cc, 1436, 5000, 5000); FlushTimers()

  -- Off: no guildmates in the field and the old words
  GL.SetState("off")
  Search("alice")
  Check(#rowsShown() == 0, "Off: nothing from the guild")
  local old
  for _, fs in ipairs(FSLIST) do if fs.text == "No known NPCs match." then old = true end end
  Check(old and field().hint.text == "Search known NPCs\226\128\166", "...and the field's own words are the NPC ones")
  GL.SetState("invisible"); tidy()
  Send(A, 1429, 5000, 5000); Send(Bo, 1429, 2000, 2000); Send(Cc, 1436, 5000, 5000); FlushTimers()
end

---------------------------------------------------------------------------
Section("5 a record beyond the draw cap, the cap itself, and the pick's end")
do
  tidy()
  GL.SetState("off"); CLOCK = CLOCK + 1; FlushTimers(); GL.SetState("invisible"); Roster()
  local names = {}
  for i = 1, 160 do names[i] = ("Person%03d Test"):format(i) end
  for _, n in ipairs(names) do GUILD[n] = true end
  Roster()
  E = E + 1000; seq = {}
  for _, n in ipairs(names) do Send(n, 1429, 100 + #n, 200) end
  FlushTimers()
  local function total() return count(drawn()) end
  Check(GM.Snapshot().drawn == 150 and total() == 150 and not Mk(names[160]), "150 drawn, the last ten held but not drawn")
  Check(#GM.Search("person160", SR.Where(), 8) == 1 and #GM.Search("person", SR.Where(), 8) == 8, "...yet all are searchable")
  local _, all = GM.Search("person", SR.Where(), 8)
  Check(all == 160, "the total counts them all: " .. all)

  Search("person160"); Pick(1)
  Check(GM.Picked() == names[160]:lower() and Mk(names[160]), "the searched record is drawn")
  Check(total() == 150 and GM.Snapshot().drawn == 150, "...within the cap: " .. total())
  Check(Mk(names[149]) and not Mk(names[150]), "...one ordinary selection (the last) gives its place")
  Check(GM.Snapshot().ringing, "a ring is on it")
  local pool0 = GM.Snapshot().pool
  Check(pool0 == 150, "no marker beyond the cap was made: " .. pool0)

  -- new arrivals cannot add to the total either
  Send(names[1], 1429, 300, 300); FlushTimers(); GM.Layout()
  Check(total() == 150, "still 150 after an update")

  -- another selection replaces it
  tidy()
  Search("person159"); Pick(1)
  Check(Mk(names[159]) ~= nil and total() == 150 and GM.Picked() == names[159]:lower(), "picking another keeps one exemption")
  Search("person160"); Pick(1)
  Check(Mk(names[160]) and not Mk(names[150]) and total() == 150, "...the new one is drawn")
  Check(GM.Picked() == names[160]:lower(), "the old exemption is gone: " .. tostring(GM.Picked()))

  -- an NPC pick lets it go
  assert(NS.Observe({ id = 77, name = "Farley Two", map = 1429, x = 0.5, y = 0.6, tags = { innkeeper = true } }))
  Search("farley two"); Pick(1)
  Check(GM.Picked() == nil and Mk(names[150]) and not Mk(names[160]) and total() == 150, "picking an NPC lets the guild exemption go")
  tidy()

  -- search clear
  Search("person160"); Pick(1)
  Check(Mk(names[160]), "picked again")
  edit():SetFocus(); typeInto(""); FlushTimers()
  Check(GM.Picked() == nil and not Mk(names[160]) and total() == 150 and not GM.Snapshot().ringing, "clearing the search lets it go")
  Search("person160"); Pick(1)
  field().clear.scripts.OnClick(field().clear); FlushTimers()
  Check(GM.Picked() == nil and not Mk(names[160]), "so does the clear button")

  -- map close
  Search("person160"); Pick(1)
  closeMap()
  Check(GM.Picked() == nil and not GM.Snapshot().ringing and total() == 0, "closing the map lets it go")
  openMap()
  Check(GM.Picked() == nil and total() == 150 and not Mk(names[160]), "...and it does not come back")

  -- withdrawal and expiry
  Search("person160"); Pick(1)
  Withdraw(names[160]); FlushTimers()
  Check(GM.Picked() == nil and not Mk(names[160]) and not GM.Snapshot().ringing, "a withdrawal ends the pick")
  tidy()
  Search("person159"); Pick(1)
  Check(GM.Picked() == names[159]:lower(), "picked")
  CLOCK = CLOCK + 301; GM.Layout()
  Check(GM.Picked() == nil and GM.Snapshot().drawn == 0, "expiry ends the pick (and the records)")
  tidy()
  -- turning the feature off
  E = E + 1000; seq = {}
  for i = 1, 160 do Send(names[i], 1429, 100 + #names[i], 200) end
  FlushTimers()
  Search("person160"); Pick(1)
  GL.SetState("off")
  Check(GM.Picked() == nil and total() == 0, "Off ends it")
  GL.SetState("invisible"); tidy()
  Check(true)
end

---------------------------------------------------------------------------
Section("6 searching and opening the map again and again")
do
  GL.SetState("off"); CLOCK = CLOCK + 1; FlushTimers(); GL.SetState("invisible"); Roster()
  E = E + 1000; seq = {}
  for i = 1, 160 do Send(("Person%03d Test"):format(i), 1429, 100 + i, 200) end
  FlushTimers()
  local function cycle()
    openMap()
    edit():SetFocus(); typeInto("person16"); FlushTimers()
    Pick(1)
    closeMap(); FlushTimers()
  end
  cycle(); cycle()
  local frames0, pool0, rows0 = #FRAMES, GM.Snapshot().pool, SB.Snapshot().rows
  local upd0, handlers0 = count(UPDATERS), handlers()
  local timers0 = GM.Snapshot().timers
  for _ = 1, 25 do cycle() end
  Check(#FRAMES == frames0, "no frame is made after the first rounds: " .. #FRAMES .. " vs " .. frames0)
  Check(GM.Snapshot().pool == pool0 and SB.Snapshot().rows == rows0, "the pool and the rows stay the same size")
  Check(count(UPDATERS) == upd0 and #TIMERS == 0, "no update or timer is left running")
  Check(handlers() == handlers0, "no click handler accumulates")
  Check(GM.Snapshot().timers == timers0 and GM.Snapshot().armed == 0 and GM.Snapshot().events == 1, "the layout timer and the group event stay as they were")
  Check(GM.Picked() == nil and GM.Snapshot().drawn == 0, "nothing is picked or drawn on a closed map")
  openMap()
  Check(GM.Snapshot().drawn == 150, "and the map opens full: " .. GM.Snapshot().drawn)
  -- many searches in one sitting
  edit():SetFocus(); typeInto("person1"); FlushTimers()   -- the most rows a list ever has, made once
  local before = #FRAMES
  for i = 1, 30 do edit():SetFocus(); typeInto(i % 2 == 0 and "person1" or "alice"); FlushTimers() end
  Check(#FRAMES == before and SB.Snapshot().rows <= SR.MAX_RESULTS, "30 searches made nothing new")
  tidy()
end

print(("guild locations search: %d checks PASSED"):format(checks))
