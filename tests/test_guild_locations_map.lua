-- Guild Locations on the world map (guildloc/Map.lua): class badge choice and the unknown-class emblem, placement on the viewed
-- map, its parents and a sibling, the local player and group members never drawn (their records stay held), the 150 cap and its
-- order, the tooltip's name / class and level / age / limitation (unknown stays unknown), the menu (waypoint, navigate, invite)
-- asking again at the click, removal on withdrawal, expiry, offline, guild change and Off, pooled markers reset, no work while the
-- map is hidden, and bounded work and objects under rapid updates and repeated open/close. The map, the roster, the clock and
-- the party API are mocks; the core (guildloc/Comm.lua) is the real one, fed through its receive path. Whether the art reads at
-- marker size, where a badge lands, and the roster's class/level return values are for the game (docs/guild-locations.md).
dofile(TESTS .. "harness.lua")

local checks = 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then error("FAILED: " .. tostring(msg), 2) end
end
local function Section(s) print("-- " .. s) end

-- a virtual clock
CLOCK = 1000
local T0 = 1700000000
local queue, qseq = {}, 0
local function After(d, fn) qseq = qseq + 1; queue[#queue + 1] = { at = CLOCK + d, fn = fn, seq = qseq } end
local function Advance(sec)
  local target = CLOCK + sec
  while true do
    local best, bi
    for i, e in ipairs(queue) do
      if e.at <= target and (not best or e.at < best.at or (e.at == best.at and e.seq < best.seq)) then best, bi = e, i end
    end
    if not best then break end
    table.remove(queue, bi)
    if best.at > CLOCK then CLOCK = best.at end
    best.fn()
  end
  CLOCK = target
end

local ME = "Rich Hale"
local c = MakeClient(ME, { "!!!TwichUI" })
CLIENTS[ME] = c

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
    if k == "SetEnabled" then return function(s, v) s.enabled = v and true or false end end
    if k == "IsEnabled" then return function(s) return s.enabled ~= false end end
    if k == "HasFocus" or k == "IsMouseOver" or k == "IsTruncated" then return function() return false end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "CreateFontString" then return function() return Obj() end end
    if k == "CreateTexture" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%l") then return nil end
    return function() end
  end })
end
local realCreate = c.CreateFrame
local frames = 0
c.CreateFrame = function(kind, name)
  frames = frames + 1
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
c.StaticPopupDialogs = {}
c.ACCEPT, c.CANCEL = "Accept", "Cancel"
local notices = {}
c.UIErrorsFrame = { AddMessage = function(_, text) notices[#notices + 1] = text end }
c.issecretvalue = nil
c.IsAltKeyDown = function() return false end
c.IsShiftKeyDown = function() return false end
c.IsControlKeyDown = function() return false end
c.UnitClassBase = function() return "MAGE" end
c.C_Timer = { After = After }
c.GetTime = function() return CLOCK end
c.time = function() return T0 + math.floor(CLOCK) end
c.LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior", MONK = "Monk" }

-- the tooltip records what it was told
local tip = { lines = {}, shown = false }
c.GameTooltip = {
  SetOwner = function(_, o) tip.owner = o; tip.lines = {} end,
  SetText = function(_, t) tip.lines[1] = t end,
  AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end,
  Show = function() tip.shown = true end,
  Hide = function() tip.shown = false; tip.owner = nil end,
  GetOwner = function() return tip.owner end,
}
local function TipHas(s)
  for _, l in ipairs(tip.lines) do if l:find(s, 1, true) then return true end end
  return false
end

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
local function SetMap(id)
  WMF.mapID = id
  if WMF.shown then for p in pairs(WMF.providers) do p:OnMapChanged() end end
end
local function SetOpen(v)
  WMF.shown = v
  for p in pairs(WMF.providers) do
    if v then p:RefreshAllData() elseif p.OnHide then p:OnHide() end
  end
end

-- the guild, its roster details and the party
GUILD = { [ME] = true }
GROUP = nil
local EXTRA = {}
c.GetGuildInfo = function() if GUILD[ME] ~= nil then return "The Guild" end end
c.GetGuildRosterInfo = function(i)
  local list = {}
  for k in pairs(GUILD) do list[#list + 1] = k end
  table.sort(list)
  local k = list[i]
  if k then local e = EXTRA[k] or {}; return k, "", 0, e.level, "", "", "", "", GUILD[k], "", e.class end
end
c.C_GuildInfo = { GuildRoster = function() end }
c.UnitExists = function(u) return c.GetUnitName(u) ~= nil and u ~= "player" end
local CAN, invited = true, {}
c.C_PartyInfo = { CanInvite = function() return CAN end, InviteUnit = function(n) invited[#invited + 1] = n end }

for _, f in ipairs({ "chronicle/Style.lua", "FrameLook.lua", "modules/Interact.lua", "modules/Borders.lua", "modules/MenuStyle.lua", "modules/SpellMenu.lua",
  "modules/Media.lua", "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Sound.lua", "pins/Map.lua", "pins/Minimap.lua",
  "pins/Editor.lua", "pins/Window.lua", "npcs/Kinds.lua", "npcs/Store.lua", "npcs/Prefs.lua", "npcs/Collect.lua", "npcs/Map.lua",
  "npcs/Search.lua", "guildloc/State.lua", "guildloc/Roster.lua", "guildloc/Comm.lua", "guildloc/Map.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { guildLoc = { state = "invisible" } }   -- receives, sends nothing
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local GL, GM, RS = R.GuildLoc, R.GuildLoc.Map, R.GuildLoc.Roster
local menus = {}
R.PinsWindow.OpenMenu = function(anchor, title, choices) menus[#menus + 1] = { anchor = anchor, title = title, choices = choices } end
local navs, navEnabled = {}, true
R.Nav = { Enabled = function() return navEnabled end,
  CanNavigate = function() if navEnabled then return true end return false, "Navigation is turned off." end,
  StartAt = function(map, x, y, name, source) navs[#navs + 1] = { map = map, x = x, y = y, name = name, source = source }; return true end }

local E = T0 + 2000
local function P(n, map, x, y) return ("1:p:%d:%d:%d:%d:%d"):format(E, n, map or 1429, x or 5000, y or 5000) end
local seq = {}
local function Send(who, map, x, y)
  seq[who] = (seq[who] or 0) + 1
  GL.OnMessage("TwichUIGuild", P(seq[who], map, x, y), "GUILD", who)
end
local function Withdraw(who) GL.OnMessage("TwichUIGuild", ("1:w:%d"):format(E + 1), "GUILD", who) end
local function Roster() c.FireEvent("GUILD_ROSTER_UPDATE"); Advance(6) end
local function Settle() Advance(1) end
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
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function Mk(name) return drawn()[name:lower()] end
local function Art(m) return m and m.icon.texture end

local A, B, C = "Alice Stone", "Bob Reeve", "Cara Dunn"
Join(A, B, C)
EXTRA[A] = { level = 60, class = "MAGE" }
EXTRA[B] = { level = 41, class = "WARRIOR" }
-- Cara: the roster gave neither
Roster()

---------------------------------------------------------------------------
Section("1 art: the nine badges, the emblem for anything else")
do
  local f = io.open(REPO .. "!!!TwichUI/media/guildloc/class-MAGE-small.tga", "rb")
  Check(f, "the badge file exists"); f:close()
  for _, t in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    local path = GM.ArtFor({ class = t })
    Check(path:find("class-" .. t .. "-small", 1, true), t .. " has its badge")
    local rel = path:gsub("^.*media", "media"):gsub("\\", "/")
    local fh = io.open(REPO .. "!!!TwichUI/" .. rel .. ".tga", "rb")
    Check(fh, t .. " badge is a file in media/guildloc"); fh:close()
  end
  local emblem = R.ICON
  Check(GM.ArtFor({ class = "MONK" }) == emblem and GM.ArtFor({}) == emblem and GM.ArtFor(nil) == emblem, "an unknown, missing or no entry wears the emblem")
  Check(GM.ArtFor({ class = "mage" }) == emblem, "tokens are exact")
  Send(A); Send(B); Send(C); Settle()
  Check(Art(Mk(A)) == GM.ArtFor({ class = "MAGE" }) and Art(Mk(B)) == GM.ArtFor({ class = "WARRIOR" }), "a drawn marker wears its class")
  Check(Art(Mk(C)) == emblem, "no roster class: the emblem")
  Check(Mk(A).hl.texture == Art(Mk(A)), "the highlight is the same badge")
  EXTRA[C] = { level = 20, class = "MONK" }; Roster()
  Check(Art(Mk(C)) == emblem and GM.Identity(RS.Entry(C:lower())) == "Level 20 Monk", "a class with no badge keeps the emblem and still names the class")
  EXTRA[C] = {}; Roster()
end

---------------------------------------------------------------------------
Section("2 placement: the viewed map, its parents, never a sibling")
do
  Send(A, 1429, 5000, 5000); Send(B, 1453, 5000, 5000); Send(C, 1436, 2000, 3000); Settle()
  local ma, mb = Mk(A), Mk(B)
  Check(ma and math.abs(ma.mx - 0.5) < 1e-9 and math.abs(ma.my - 0.5) < 1e-9, "on its own map at the sent place")
  Check(mb and math.abs(mb.mx - 0.375) < 1e-9 and math.abs(mb.my - 0.25) < 1e-9, "a city inside the viewed zone is placed through the world")
  Check(Mk(C) == nil, "a sibling zone is not drawn on this one")
  Check(ma.shown ~= false and ma.size == 20, "shown at the base size")
  SetMap(1415)
  Settle()
  ma, mb = Mk(A), Mk(B)
  Check(ma and math.abs(ma.mx - 0.3) < 1e-9 and math.abs(ma.my - 0.55) < 1e-9, "on the continent the zone's place converts") -- (1000+200)/4000, (2000+200)/4000
  Check(mb and math.abs(mb.mx - 0.2875) < 1e-9 and math.abs(mb.my - 0.525) < 1e-9, "...and the city's")
  Check(Mk(C) and math.abs(Mk(C).mx - 0.17) < 1e-9, "a zone beside is on the continent")
  SetMap(1436)
  Settle()
  Check(Mk(C) and Mk(A) == nil and Mk(B) == nil, "viewing Westfall shows only Westfall's")
  SetMap(1429); Settle()
  Check(Mk(A) and Mk(B) and Mk(C) == nil, "back")
  -- the zoom
  WMF.GetCanvasZoomPercent = function() return 1 end
  GM.Layout()
  Check(math.abs(Mk(A).scale - 1.3) < 1e-9, "26 at the closest zoom (20 x 1.3)")
  WMF.GetCanvasZoomPercent = nil
end

---------------------------------------------------------------------------
Section("3 the local player and group members")
do
  Check(not drawn()[ME:lower()], "no marker for ourselves")
  GL.OnMessage("TwichUIGuild", P(1, 1429, 100, 100), "GUILD", ME)
  Settle()
  Check(GL.Peek(ME) == nil and not drawn()[ME:lower()], "our own message is ignored before anything is held")
  -- Alice joins the party: her marker goes, her record stays
  GROUP = { [ME] = true, [A] = true }
  c.FireEvent("GROUP_ROSTER_UPDATE"); Settle()
  Check(Mk(A) == nil and Mk(B), "a group member gets no marker")
  Check(GL.Peek(A) ~= nil and GL.Snapshot().records >= 2, "...but the record is still held")
  Send(A, 1429, 6000, 6000); Settle()
  Check(Mk(A) == nil and GL.Peek(A).x == 6000, "...and keeps updating")
  GROUP = nil
  c.FireEvent("GROUP_ROSTER_UPDATE"); Settle()
  Check(Mk(A) and math.abs(Mk(A).mx - 0.6) < 1e-9, "leaving the group brings the marker back at the latest place")
  -- a name in another form is the same person
  GROUP = { [ME] = true, [B] = true }
  c.FireEvent("GROUP_ROSTER_UPDATE"); Settle()
  Check(Mk(B) == nil, "dedupe by the roster's name form")
  GROUP = nil; c.FireEvent("GROUP_ROSTER_UPDATE"); Settle()
end

---------------------------------------------------------------------------
Section("4 the tooltip: name, class and level, age, the limitation; unknown stays unknown")
do
  local ma = Mk(A)
  Send(A, 1429, 5000, 5000); Settle()
  Advance(20)
  ma:GetScript("OnEnter")(ma)
  Check(tip.shown and tip.lines[1] == "Alice Stone", "the name")
  Check(TipHas("Level 60 Mage"), "level and localized class")
  Check(TipHas("Updated 21 s ago"), "the age from the receipt time: " .. table.concat(tip.lines, " | "))
  Check(TipHas("Last known location") and TipHas("phase or layer"), "the limitation")
  Check(TipHas("Click for actions"), "the hint")
  ma:GetScript("OnLeave")(ma)
  Check(not tip.shown, "left")
  local mc = Mk(C) or (function() Send(C, 1429, 3000, 3000); Settle(); return Mk(C) end)()
  mc:GetScript("OnEnter")(mc)
  Check(TipHas("Class and level not known") and not TipHas("Level"), "unknown class and level are not invented")
  EXTRA[C] = { level = 33 }; Roster()
  mc:GetScript("OnEnter")(mc)
  Check(TipHas("Level 33") and not TipHas("Mage"), "level alone")
  EXTRA[C] = { class = "WARRIOR" }; Roster()
  mc:GetScript("OnEnter")(mc)
  Check(TipHas("Warrior") and not TipHas("Level"), "class alone")
  EXTRA[C] = {}; Roster()
  Check(GM.Ago(59) == "Updated 59 s ago" and GM.Ago(60) == "Updated 1 min ago" and GM.Ago(190) == "Updated 3 min ago" and GM.Ago(-5) == "Updated 0 s ago", "age wording")
  -- a tooltip for a record that is gone says nothing and hides
  mc:GetScript("OnEnter")(mc)
  Withdraw(C); Advance(0.2)
  mc:GetScript("OnEnter")(mc)
  Check(not tip.shown, "no tooltip for a record that was withdrawn")
  Advance(1)
end

---------------------------------------------------------------------------
Section("5 the menu: waypoint, navigate, invite, each asking again at the click")
do
  Send(A, 1429, 5000, 5000); Settle()
  local ma = Mk(A)
  menus = {}
  ma:GetScript("OnClick")(ma, "LeftButton")
  local m = menus[1]
  Check(m and m.title == "Alice Stone", "a click opens the menu")
  Check(#m.choices == 3 and m.choices[1].label == "Set waypoint" and m.choices[2].label:find("Navigate") and m.choices[3].label == "Invite to party", "three choices")
  Check(#waypoints == 0 and #navs == 0 and #invited == 0, "nothing is done by opening it")
  -- she moves while the menu is open: the click uses the record as it is now
  Advance(5); Send(A, 1429, 7000, 2000)
  m.choices[1].run()
  Check(#waypoints == 1 and waypoints[1].uiMapID == 1429 and math.abs(waypoints[1].x - 0.7) < 1e-9 and math.abs(waypoints[1].y - 0.2) < 1e-9, "the waypoint is at the latest place")
  m.choices[2].run()
  Check(#navs == 1 and navs[1].map == 1429 and math.abs(navs[1].x - 0.7) < 1e-9 and navs[1].source == "guild", "navigation goes to the snapshot")
  m.choices[3].run()
  Check(invited[1] == A, "the invitation names the member")
  -- withdrawn before the click
  local w0, n0, i0 = #waypoints, #navs, #invited
  notices = {}
  Withdraw(A)
  for i = 1, 3 do m.choices[i].run() end
  Check(#waypoints == w0 and #navs == n0 and #invited == i0, "a withdrawn record: no action")
  Check(#notices == 3 and notices[1]:find("no longer shared"), "...and it says so")
  -- expired before the click
  E = E + 10
  Send(A, 1429, 5000, 5000); Settle()
  menus = {}; ma = Mk(A); ma:GetScript("OnClick")(ma, "RightButton"); m = menus[1]
  Advance(301)
  notices = {}
  m.choices[1].run()
  Check(#waypoints == w0 and #notices == 1, "an expired record: no waypoint")
  -- no longer listed in the guild
  E = E + 10
  Send(A, 1429, 5000, 5000); Settle()
  menus = {}; ma = Mk(A); ma:GetScript("OnClick")(ma, "LeftButton"); m = menus[1]
  GUILD[A] = nil
  Roster()
  notices = {}
  m.choices[3].run(); m.choices[2].run()
  Check(#invited == i0 and #navs == n0 and #notices == 2, "a member the roster no longer lists: nothing happens")
  GUILD[A] = true; Roster()
  -- invite eligibility
  E = E + 10
  Send(A, 1429, 5000, 5000); Settle()
  menus = {}; ma = Mk(A); ma:GetScript("OnClick")(ma, "LeftButton"); m = menus[1]
  CAN = false
  Check(m.choices[3].enabled == true, "(enabled was judged when it opened)")
  menus = {}; ma:GetScript("OnClick")(ma, "LeftButton"); local m2 = menus[1]
  Check(m2.choices[3].enabled == false and m2.choices[3].why:find("can't invite"), "can't invite: greyed with the reason")
  notices = {}; i0 = #invited
  m.choices[3].run()
  Check(#invited == i0 and #notices == 1, "...and refused at the click even from the old menu")
  CAN = true
  E = E + 10
  Send(A, 1429, 5000, 5000); Settle()
  Check(Mk(A), "(drawn before the roster says offline)")
  GUILD[A] = false; Roster()
  Check(Mk(A) == nil, "offline in a newer roster: the marker is gone")
  GUILD[A] = true; Roster(); E = E + 10; Send(A, 1429, 5000, 5000); Settle()
  ma = Mk(A)
  GROUP = { [ME] = true, [A] = true }
  notices = {}; i0 = #invited
  menus = {}; GM.Menu(ma)
  Check(menus[1] == nil or menus[1].choices[3].enabled == false, "a member already in the group: invite is not offered")
  GM.Invite(A:lower()); Check(#invited == i0, "...and not sent")
  GROUP = nil
  -- navigation off
  navEnabled = false
  menus = {}; c.FireEvent("GROUP_ROSTER_UPDATE"); Settle(); ma = Mk(A); GM.Menu(ma)
  Check(menus[1].choices[2].enabled == false and menus[1].choices[2].why:find("turned off"), "navigation off: greyed with its reason")
  n0 = #navs; menus[1].choices[2].run(); Check(#navs == n0, "...and not started")
  navEnabled = true
  -- a waypoint on a map the game refuses
  Send(B, 1436, 1000, 1000); Settle(); SetMap(1436); Settle()
  notices = {}; w0 = #waypoints
  GM.SetWaypoint(B:lower())
  Check(#waypoints == w0 and notices[1]:find("doesn't allow a waypoint"), "a map that takes no waypoint says so")
  SetMap(1429); Settle()
  -- a modifier click goes to the map, not the menu
  menus = {}
  c.IsAltKeyDown = function() return true end
  ma = Mk(A); ma:GetScript("OnClick")(ma, "LeftButton")
  c.IsAltKeyDown = function() return false end
  Check(#menus == 0 and WMF.forwarded == 1, "Alt-click is the map's")
end

---------------------------------------------------------------------------
Section("6 removal: withdrawal, expiry, offline, guild change, Off")
do
  E = E + 100
  Send(A, 1429, 5000, 5000); Send(B, 1429, 4000, 4000); Settle()
  Check(Mk(A) and Mk(B), "both drawn")
  Withdraw(A); Advance(0.6)
  Check(Mk(A) == nil and Mk(B), "a withdrawal takes the marker within a layout interval")
  Advance(300 - 0.6)
  E = E + 100
  Send(B, 1429, 4000, 4000); Settle()
  Check(Mk(B), "drawn again")
  Advance(299); Check(Mk(B), "still there at 299 s")
  Advance(17)   -- past 300 s and the 15 s sweep
  Check(Mk(B) == nil and GL.Peek(B) == nil, "expired: gone")
  -- at layout time an expired record is not drawn even before the sweep
  E = E + 100
  Send(B, 1429, 4000, 4000); Settle()
  Advance(299.9)
  Send(C, 1429, 1000, 1000)
  Advance(0.2); GM.Layout()
  Check(Mk(B) == nil and Mk(C), "a layout never draws an expired record")
  -- confirmed offline
  E = E + 100
  Send(B, 1429, 4000, 4000); Settle()
  GUILD[B] = false; Roster()
  Check(Mk(B) == nil, "a roster pass showing them offline removes the marker")
  GUILD[B] = true; Roster()
  -- guild change
  E = E + 100
  Send(A, 1429, 5000, 5000); Send(B, 1429, 4000, 4000); Settle()
  Check(Mk(A) and Mk(B), "drawn before the guild changes")
  c.GetGuildInfo = function() return "Another Guild" end
  c.FireEvent("PLAYER_GUILD_UPDATE", "player"); Advance(1)
  Check(count(drawn()) == 0 and GL.Snapshot().records == 0, "a different guild clears the markers and the records")
  c.GetGuildInfo = function() return "The Guild" end
  c.FireEvent("PLAYER_GUILD_UPDATE", "player"); Advance(1)
  -- leaving the guild
  local saved = GUILD[ME]
  E = E + 100
  Roster(); Send(A, 1429, 5000, 5000); Settle()
  GUILD[ME] = nil
  c.FireEvent("PLAYER_GUILD_UPDATE", "player"); Advance(1)
  Check(count(drawn()) == 0, "leaving the guild clears the markers")
  GUILD[ME] = saved; c.FireEvent("PLAYER_GUILD_UPDATE", "player"); Roster()
  -- Off
  E = E + 100
  Send(A, 1429, 5000, 5000); Settle()
  Check(Mk(A), "drawn")
  local ev, nprov = GM.Snapshot().events, count(WMF.providers)
  Check(ev == 1 and GM.Snapshot().installed, "the provider and the group event are on while not Off")
  GL.SetState("off"); Advance(1)
  Check(count(drawn()) == 0 and count(WMF.providers) == nprov - 1, "Off takes every marker and the provider off the map")
  local s = GM.Snapshot()
  Check(not s.installed and s.armed == 0 and s.events == 0 and s.drawn == 0, "...and its timer and event")
  Send(A, 1429, 5000, 5000); Settle()
  Check(count(drawn()) == 0 and GL.Peek(A) == nil, "Off keeps and draws nothing")
  GL.SetState("invisible"); Roster(); Settle()
  Check(count(WMF.providers) == nprov and GM.Snapshot().installed, "leaving Off puts it back")
  E = E + 100; Send(A, 1429, 5000, 5000); Settle()
  Check(Mk(A), "and it draws again")
end

---------------------------------------------------------------------------
Section("7 the cap, its order, and records held beyond it")
do
  local names = {}
  for i = 1, 160 do names[i] = ("Person%03d Test"):format(i) end
  -- every record so far is stale or withdrawn; start from nothing
  GL.SetState("off"); Advance(1); GL.SetState("invisible"); Roster()
  for _, n in ipairs(names) do GUILD[n] = true end
  Roster()
  E = E + 1000
  seq = {}
  for _, n in ipairs(names) do Send(n, 1429, 100 + #n, 200) end
  Settle()
  local s = GM.Snapshot()
  Check(GL.Snapshot().records == 160, "all 160 are held")
  Check(s.drawn == 150 and count(drawn()) == 150, "150 are drawn")
  Check(drawn()[names[1]:lower()] and drawn()[names[150]:lower()] and not drawn()[names[151]:lower()], "the first held are the ones drawn")
  Check(s.capped >= 1, "the cap is counted")
  local pool0 = s.pool
  Check(pool0 == 150, "the pool is as large as the most drawn")
  -- one of the undrawn ones is still held, and freed room takes the next in order
  Check(GL.Peek(names[160]) ~= nil, "records past the cap are kept")
  Withdraw(names[1]); Advance(0.6)
  Check(drawn()[names[151]:lower()] and not drawn()[names[1]:lower()], "a freed place goes to the next in order")
  Check(GM.Snapshot().pool == pool0, "...with no new marker")
  -- the same order again from scratch
  local before = {}
  for k in pairs(drawn()) do before[k] = true end
  GM.Layout()
  local same = true
  for k in pairs(drawn()) do if not before[k] then same = false end end
  Check(same and count(drawn()) == 150, "a second layout draws the same set")
  -- markers keep their records through a redraw
  local keep = drawn()[names[2]:lower()]
  Send(names[2], 1429, 300, 300); Advance(0.6)
  Check(drawn()[names[2]:lower()] == keep, "an update moves the marker, it does not swap it")
  Check(math.abs(keep.mx - 0.03) < 1e-9, "...to the new place")
  seq = {}
end

---------------------------------------------------------------------------
Section("8 pooled markers are reset")
do
  GL.SetState("off"); Advance(1); GL.SetState("invisible"); Roster()
  E = E + 1000
  seq = {}
  Send(A, 1429, 5000, 5000); Settle()
  local m, poolBefore = Mk(A), GM.Snapshot().pool
  m.over = true; m:GetScript("OnEnter")(m)
  Check(tip.owner == m and tip.shown, "hovering")
  Withdraw(A); Advance(0.6)
  Check(m.key == nil and m.shown == false and m.over == false and m.icon.texture == nil and m.hl.texture == nil, "a released marker is hidden and unbound")
  Check(m.label.text == "" and m.name == nil and m.art == nil and m.mx == nil, "...with its texture, name and place forgotten")
  Check(not tip.shown, "...and its tooltip taken down")
  E = E + 10
  Send(B, 1429, 1000, 1000); Settle()
  Check(Mk(B) == m or drawn()[B:lower()] ~= nil, "the next record takes a free marker")
  Check(Art(Mk(B)) == GM.ArtFor({ class = "WARRIOR" }) and Mk(B).label.text == "Bob Reeve", "...dressed as itself")
  Check(GM.Snapshot().pool == poolBefore, "no further marker was made")
end

---------------------------------------------------------------------------
Section("9 hidden map: no layout work; correct when reopened; no growth")
do
  Send(A, 1429, 5000, 5000); Settle()
  Check(Mk(A) and Mk(B), "drawn")
  SetOpen(false)
  local l0, pool0, frames0 = GM.Snapshot().layouts, GM.Snapshot().pool, frames
  Check(count(drawn()) == 0, "closing lets every marker go")
  for i = 1, 20 do Send(A, 1429, 100 * i, 100 * i); Send(B, 1429, 3000, 3000); Advance(4) end
  local s = GM.Snapshot()
  Check(s.layouts == l0, "no layout ran while the map was hidden")
  Check(s.armed == 0, "...and none is waiting")
  SetOpen(true); Settle()
  Check(GM.Snapshot().layouts == l0 + 1, "one layout on opening")
  Check(Mk(A) and math.abs(Mk(A).mx - 0.2) < 1e-9 and Mk(B), "...with the latest places")
  for i = 1, 50 do SetOpen(false); SetOpen(true) end
  Settle()
  s = GM.Snapshot()
  Check(s.pool == pool0 and frames == frames0, "50 open/close cycles made no new marker or frame")
  Check(s.armed <= 1 and s.timers <= 2, "...and left no timers behind")
  Check(s.layouts <= l0 + 1 + 50 + 1, "...and one layout per opening at most")
  SetOpen(false)
  Advance(30)
  Check(GM.Snapshot().layouts == s.layouts and count(drawn()) == 0, "closed again: still no work, no markers")
  SetOpen(true); Settle()
end

---------------------------------------------------------------------------
Section("10 rapid updates are coalesced")
do
  local s0 = GM.Snapshot()
  for i = 1, 5 do E = E + 0; Send(A, 1429, 1000 + i, 1000); end
  local mid = GM.Snapshot()
  Check(mid.layouts == s0.layouts, "a burst of messages draws nothing inside the receive")
  Advance(0.6)
  Check(GM.Snapshot().layouts == s0.layouts + 1, "...and then one pass")
  -- a steady stream: no more than two passes a second
  local l0 = GM.Snapshot().layouts
  for i = 1, 20 do Advance(0.1); GL.OnMessage("TwichUIGuild", P(100 + i, 1429, 2000 + i, 1000), "GUILD", C) end
  local passes = GM.Snapshot().layouts - l0
  Check(passes <= 5, "20 updates in 2 s made at most 5 layouts (" .. passes .. ")")
  Advance(1)
  Check(GM.Snapshot().armed == 0, "nothing is left waiting")
  Check(GM.Snapshot().pool <= 150 and GM.Snapshot().timers <= 2, "the pool and timers stay bounded")
end

---------------------------------------------------------------------------
Section("11 diagnostics and the file list")
do
  local snap = GL.Snapshot()
  Check(snap.mapPool and snap.mapDrawn ~= nil and snap.mapLayouts, "the report carries the map's counts")
  local function Read(p) local f = assert(io.open(REPO .. p)); local s = f:read("*a"); f:close(); return s end
  local toc, gauges, diag = Read("!!!TwichUI/!!!TwichUI.toc"), Read("TwichUI_Diagnostics/Gauges.lua"), Read("docs/diagnostics.md")
  Check(toc:find("guildloc\\Map.lua", 1, true) and toc:find("guildloc\\Comm.lua", 1, true) < toc:find("guildloc\\Map.lua", 1, true), "the TOC lists Map.lua after Comm.lua")
  Check(gauges:find('["guildloc.map.layout"]', 1, true) and gauges:find('"guildloc.map.pool"', 1, true), "the scope and gauges are registered")
  Check(diag:find("guildloc.map.layout", 1, true), "docs/diagnostics.md lists the scope")
  local src = Read("!!!TwichUI/guildloc/Map.lua")
  Check(not src:find("SendAddonMessage") and not src:find("SendCommMessage") and not src:find("SavedVariables") and not src:find("TwichUIDB"), "the map module sends and saves nothing")
end

print(("guild locations map: %d checks PASSED"):format(checks))
