-- Waypoint commands (pins/Way.lua): /twichway and /way read x y, zone and #mapID forms into local pins made
-- by the same Pins.AddLocal the map click uses. Covers the parser (forms, whitespace, commas, 0 and 100,
-- every kind of malformed input, a name that holds numbers), the zone lookup (full names, ambiguity, the
-- tree read once), the current map (never the open world map), the pin made (coordinates once, name kept,
-- defaults, duplicates allowed, nothing opened or navigated), a pasted list (order, independent lines,
-- line numbers, never run as anything, one refresh), the lazy paste window, and who owns /way (free,
-- another addon pending or imported, switch off at login, never taken over).
-- Mocks show TwichUI's bookkeeping only. Whether it works on the real client is for the game.
dofile(TESTS .. "harness.lua")
SENDER_FMT = function(n) return n end

local function build(name, opts)
  opts = opts or {}
  local c = MakeClient(name, { "!!!TwichUI" })
  CLIENTS[name] = c

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

  local said = {}
  c.print = function(s) said[#said + 1] = tostring(s) end
  c.said = said

  -- maps: Azeroth (947) is the top; Eastern Kingdoms under it; Elwynn, Westfall and a second "Stormwind City"
  local MAPS = {
    [947] = { name = "Azeroth", parent = 946, kind = 1 },
    [1415] = { name = "Eastern Kingdoms", parent = 947, kind = 2 },
    [1429] = { name = "Elwynn Forest", parent = 1415, kind = 3 },
    [1436] = { name = "Westfall", parent = 1415, kind = 3 },
    [1453] = { name = "Stormwind City", parent = 1429, kind = 3 },
    [9001] = { name = "Stormwind City", parent = 1415, kind = 3 },
    [9002] = { name = "Old Town Cellar", parent = 1453, kind = 5 },
    [101] = { name = "Outland", parent = 946, kind = 2 },
    [102] = { name = "Zangarmarsh", parent = 101, kind = 3 },
    [946] = { name = "Cosmic", parent = 0, kind = 0 },
    [200] = { name = "Elsewhere", parent = 0, kind = 1 },        -- a tree that does not hang off the first one
    [201] = { name = "Elsewhere Zone", parent = 200, kind = 3 },
  }
  c.Enum = { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
  c.state = { best = 1429, childCalls = 0, infoCalls = 0 }
  local function descendants(root, out)
    for id, m in pairs(MAPS) do
      if m.parent == root then
        out[#out + 1] = { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.kind }
        descendants(id, out)
      end
    end
    return out
  end
  c.C_Map = {
    GetMapInfo = function(id)
      c.state.infoCalls = c.state.infoCalls + 1
      local m = MAPS[id]
      return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.kind } or nil
    end,
    GetBestMapForUnit = function() return c.state.best end,
    GetFallbackWorldMapID = function() return 947 end,
    GetMapChildrenInfo = function(root, _, all)
      c.state.childCalls = c.state.childCalls + 1
      assert(all == true, "every descendant is asked for")
      return descendants(root, {})
    end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function() c.state.waypointSet = true; return true end,
  }
  c.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }

  -- the world map, showing Westfall: a command must neither move it nor read from it
  c.MapCanvasDataProviderMixin = { OnAdded = function(self, map) self.owningMap = map end, OnRemoved = function() end }
  c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
  local canvas = Obj()
  rawset(canvas, "GetWidth", function() return 1000 end); rawset(canvas, "GetHeight", function() return 700 end)
  local WMF = Obj()
  WMF.mapID, WMF.providers, WMF.clicks, WMF.cursors = 1436, {}, {}, {}
  WMF.setMapCalls = 0
  rawset(WMF, "GetMapID", function(s) return s.mapID end)
  rawset(WMF, "SetMapID", function(s, id) s.setMapCalls = s.setMapCalls + 1; s.mapID = id end)
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
  c.Minimap = Obj()
  c.C_Minimap = { GetUiMapID = function() return nil end, GetViewRadius = function() return 100 end }
  c.GetCVarBool = function() return false end
  c.GetPlayerFacing = function() return 0 end
  c.IsAltKeyDown, c.IsShiftKeyDown, c.IsControlKeyDown = function() return false end, function() return false end, function() return false end

  if opts.before then opts.before(c) end   -- another addon's commands, registered before TwichUI's login
  for _, f in ipairs({ "chronicle/Style.lua", "modules/Borders.lua", "modules/MenuStyle.lua",
    "pins/Pins.lua", "pins/Sync.lua", "pins/Look.lua", "pins/Map.lua", "pins/Editor.lua", "pins/Way.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  c.TwichUIDB = { modules = { partyPins = opts.off ~= true } }
  c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
  c.WMF = WMF
  c.frames = FRAMES
  return c
end

local function last(c) return c.said[#c.said] or "" end
local function clear(c) for i = #c.said, 1, -1 do c.said[i] = nil end end
local function joined(c) return table.concat(c.said, "\n") end
local function cmd(c, text) clear(c); c.SlashCmdList.TWICHUIWAY(text) end


---------------------------------------------------------------------------
-- 1. The parser
---------------------------------------------------------------------------
local c = build("Way A")
local R = c.TwichUI
local PN, PW = R.Pins, R.PinsWay
local function P(text) return PW.Parse(text) end
local function near(a, b) return math.abs(a - b) < 1e-9 end

local e = assert(P("52.3 40.7"))
assert(near(e.x, 52.3) and near(e.y, 40.7) and not e.map and not e.zone and not e.name, "two numbers: the current map")
e = assert(P("52.3 40.7 Rare spawn")); assert(e.name == "Rare spawn" and not e.zone and not e.map)
e = assert(P("Nagrand 45 50 Rare spawn")); assert(e.zone == "Nagrand" and e.name == "Rare spawn" and e.x == 45 and e.y == 50)
e = assert(P("Elwynn Forest 45 50")); assert(e.zone == "Elwynn Forest" and not e.name, "a zone name of several words")
e = assert(P("Stranglethorn Vale   12.5   80   Hidden   chest")); assert(e.zone == "Stranglethorn Vale" and e.y == 80 and e.name == "Hidden   chest")
e = assert(P("#1453 67.2 49.6 Simon Tanner")); assert(e.map == 1453 and near(e.x, 67.2) and e.name == "Simon Tanner" and not e.zone)
e = assert(P("   52.3     40.7     Rare   spawn   ")); assert(e.name == "Rare   spawn", "outer space goes, inner space is cleaned when the pin is made")
e = assert(P("52.3, 40.7 Rare spawn")); assert(near(e.x, 52.3) and near(e.y, 40.7) and e.name == "Rare spawn", "a comma between")
e = assert(P("52.3,40.7")); assert(near(e.x, 52.3) and near(e.y, 40.7) and not e.name)
e = assert(P("52.3 , 40.7 Rare")); assert(near(e.y, 40.7) and e.name == "Rare")
e = assert(P("52.3 ,40.7 Rare")); assert(near(e.y, 40.7) and e.name == "Rare")
e = assert(P("52.3 40.7, Rare")); assert(near(e.y, 40.7) and e.name == "Rare", "a comma after the second number")
e = assert(P("0 100")); assert(e.x == 0 and e.y == 100, "both ends are in")
e = assert(P("100 0 End")); assert(e.x == 100 and e.y == 0 and e.name == "End")
e = assert(P(".5 7.")); assert(near(e.x, 0.5) and e.y == 7, "a bare point")
e = assert(P("10 20 Camp 30 40")); assert(e.x == 10 and e.y == 20 and e.name == "Camp 30 40", "later numbers belong to the name")
e = assert(P("Westfall 10 20 Camp 30, 40")); assert(e.zone == "Westfall" and e.name == "Camp 30, 40")

local function Bad(text, code)
  local entry, why = P(text)
  assert(entry == nil and why == code, ("%q gave %s, wanted %s"):format(text, tostring(why), code))
end
Bad("", "empty"); Bad("    ", "empty")
Bad("Nagrand", "missing-coords"); Bad("hello there", "missing-coords"); Bad("#1453", "missing-coords")
Bad("52.3", "missing-y"); Bad("52.3 abc", "missing-y"); Bad("Nagrand 45", "missing-y")
Bad("101 50", "range"); Bad("50 100.01", "range"); Bad("-1 50", "range"); Bad("50 -0.5", "range")
Bad("52.3.4 40", "bad-number"); Bad("5-2 40", "bad-number"); Bad("50 4..0", "bad-number")
Bad("#abc 1 2", "bad-map-token"); Bad("#12x 1 2", "bad-map-token"); Bad("# 1 2", "bad-map-token")
Bad("#1453 Elwynn 1 2", "map-and-zone")
-- decimal commas are refused, never read as x,y and a name (that would be a pin at 52, 3 named "40,7")
Bad("52,3 40,7", "decimal-comma"); Bad("52,3 40,7 Rare spawn", "decimal-comma"); Bad("Westfall 52,3 40,7", "decimal-comma")
Bad("#1453 52,3 40,7", "decimal-comma")
assert(PW.Message("decimal-comma"):find("52%.3 40%.7"), "the refusal shows the form to use")
e = assert(P("52,40 Camp 3,4")); assert(e.x == 52 and e.y == 40 and e.name == "Camp 3,4", "a pair followed by a name still works")
e = assert(P("52,40 30 Camp")); assert(e.x == 52 and e.y == 40 and e.name == "30 Camp", "a whole number after a pair is still the name")
assert(select(3, P("101 50")) == "101", "the offending number is named")

---------------------------------------------------------------------------
-- 2. Making a pin: current map, name, coordinates once, defaults
---------------------------------------------------------------------------
local before = PN.LocalCount()
cmd(c, "52.3 40.7")
local pin = PN.LocalPins()[1]
assert(PN.LocalCount() == before + 1 and pin, "one pin")
assert(pin.map == 1429 and pin.x == 5230 and pin.y == 4070, "the player's map, percentages turned into steps once")
assert(pin.name == "Pin 1" and pin.color == PN.DEFAULT_COLOR and pin.id == "L1" and type(pin.created) == "number",
  "the feature's own default name, color and id")
assert(last(c):find("Pin made: Pin 1, Elwynn Forest %(52%.3, 40%.7%)"), last(c))
assert(c.WMF.setMapCalls == 0 and c.WMF.mapID == 1436, "the open world map was not moved or read")
assert(not c.state.waypointSet, "no waypoint, no navigation")
assert(PN.selected == "local:L1", "picked out, as the editor does")

cmd(c, "   0   100   Corner   post  ")
local corner = PN.LocalPins()[2]
assert(corner.x == 0 and corner.y == 10000 and corner.name == "Corner post", "0 and 100, name cleaned")

cmd(c, "52.3 40.7")
local again = PN.LocalPins()
assert(#again == 3 and again[3].x == pin.x and again[3].y == pin.y and again[3].id ~= pin.id and again[1].name == "Pin 1",
  "the same place twice is two pins, as placing by hand allows; nothing is overwritten")
cmd(c, "52.3 40.7 Corner post")
assert(#PN.LocalPins() == 4 and PN.LocalPins()[2].x == 0, "a matching name doesn't replace a pin")

cmd(c, "Westfall 10 20 Gryphon master")
local wf = PN.LocalPins()[5]
assert(wf.map == 1436 and wf.x == 1000 and wf.y == 2000 and wf.name == "Gryphon master")
cmd(c, "wEsTfAlL 10 20")
assert(PN.LocalPins()[6].map == 1436, "case doesn't matter")
cmd(c, "#1453 67.2 49.6 Simon Tanner")
local st = PN.LocalPins()[7]
assert(st.map == 1453 and st.x == 6720 and st.y == 4960 and st.name == "Simon Tanner")
cmd(c, "52.3 40.7 " .. ("long name "):rep(10))
assert(#PN.LocalPins()[8].name <= PN.NAME_MAX and last(c):find("shortened"), "a long name is cut by the existing rule, and the player is told")

---------------------------------------------------------------------------
-- 3. Refusals create nothing and say why
---------------------------------------------------------------------------
local n = PN.LocalCount()
local function Refuses(text, needle)
  cmd(c, text)
  assert(PN.LocalCount() == n, ("%q made a pin"):format(text))
  assert(joined(c):find(needle, 1, true), ("%q: wanted %q in %q"):format(text, needle, joined(c)))
end
Refuses("", "/twichway #<mapID> <x> <y> [name]")
Refuses("Westfall", "Needs two coordinates")
Refuses("45", "only one number")
Refuses("101 5", "outside 0 to 100")
Refuses("5 x", "only one number")
Refuses("5.5.5 4", "isn't a valid number")
Refuses("#99999 5 5", "no map #99999")
Refuses("#1453x 5 5", "isn't a map number")
Refuses("Nagrand 5 5", "No zone called 'Nagrand'")
Refuses("Old Town Cellar 5 5", "No zone called")   -- micro maps are reached by number
Refuses("Stormwind City 5 5", "#1453")
assert(joined(c):find("#9001", 1, true) and joined(c):find("/twichway #<mapID>", 1, true), "ambiguity lists both and suggests #mapID")
c.state.best = nil
Refuses("5 5", "Couldn't tell which map you are on")
c.state.best = 1429
cmd(c, "#9002 5 5")
assert(PN.LocalCount() == n + 1 and PN.LocalPins()[n + 1].map == 9002, "a micro map by number is fine")
n = n + 1

-- the zone tree is read once, however many commands
local calls = c.state.childCalls
for _ = 1, 5 do cmd(c, "Westfall 1 1") end
cmd(c, "Zangarmarsh 3 3")
assert(PN.LocalPins()[PN.LocalCount()].map == 102, "found through the same tree (Cosmic is the top)")
assert(c.state.childCalls == calls, "no further tree read: the first covered it")
cmd(c, "Elsewhere Zone 3 3")
assert(joined(c):find("No zone called"), "a tree not connected to the player's isn't guessed at")
local misses = c.state.childCalls
for _ = 1, 5 do cmd(c, "Elsewhere Zone 3 3") end
assert(c.state.childCalls == misses, "a miss doesn't read the tree again")
c.state.best = 201
cmd(c, "Elsewhere Zone 3 3")
assert(PN.LocalPins()[PN.LocalCount()].map == 201 and c.state.childCalls == misses + 1, "once there, its own tree is read, once")
for _ = 1, 3 do cmd(c, "Elsewhere Zone 4 4") end
assert(c.state.childCalls == misses + 1)
c.state.best = 1429

-- local limit
c.TwichUIDB.pins.list = {}
for i = 1, PN.MAX_LOCAL do assert(PN.AddLocal({ map = 1429, x = i, y = i, name = "P" .. i })) end
cmd(c, "5 5")
assert(PN.LocalCount() == PN.MAX_LOCAL and last(c):find("already have 200 local pins"), last(c))
c.TwichUIDB.pins.list = {}

---------------------------------------------------------------------------
-- 4. A pasted list
---------------------------------------------------------------------------
local changes = 0
PN.OnChange(function() changes = changes + 1 end)
local layouts = R.PinsMap.Snapshot().layouts
local text = table.concat({
  "/way 10 10 First",
  "",
  "/twichway Westfall 20 20 Second",
  "   ",
  "30 30 Third, bare",
  "/way #1453 40 40",
  "/way 150 5 Out of range",
  "/run RUNFLAG = true",
  "/way Nowhere 1 1",
  "/script RUNFLAG = true",
  "/way Stormwind City 1 1",
  "/way",
  "/way 50 50 Last",
}, "\n")
RUNFLAG = nil
changes = 0
local res = PW.ImportText(text)
assert(RUNFLAG == nil and c.RUNFLAG == nil, "nothing is run")
assert(res.count == 5 and res.failed == 6 and res.skipped == 0, ("%d made, %d failed"):format(res.count, res.failed))
local list = PN.LocalPins()
assert(#list == 5, "valid lines made pins even though others failed")
assert(list[1].name == "First" and list[2].name == "Second" and list[3].name == "Third, bare" and list[4].map == 1453 and list[5].name == "Last",
  "in their original order")
assert(list[2].map == 1436 and list[3].map == 1429 and list[1].map == 1429)
assert(changes == 1, "one refresh for the whole paste, not " .. changes)
assert(R.PinsMap.Snapshot().layouts - layouts <= 1, "the map laid out at most once")
local lines = {}
for _, err in ipairs(res.errors) do lines[err.line] = err.text end
assert(lines[7]:find("outside 0 to 100") and lines[8]:find("Only /way and /twichway") and lines[9]:find("No zone called")
  and lines[10]:find("Only /way") and lines[11]:find("#1453") and lines[12]:find("Needs two coordinates"),
  "each failure carries its own line number")
assert(res.done[1] and res.done[3] and res.done[5] and res.done[6] and res.done[13] and not res.done[7], "which lines made a pin")
assert(PW.Summary(res) == "Made 5 pins. 6 lines could not be used.", PW.Summary(res))

-- bounds
local many = {}
for i = 1, 300 do many[i] = "/way 5 5 P" .. i end
c.TwichUIDB.pins.list = {}
local big = PW.ImportText(table.concat(many, "\n"))
assert(PN.LocalCount() == PN.MAX_LOCAL and big.count == PN.MAX_LOCAL, "bounded by the pin limit")
assert(big.failed >= 1 and big.errors[1].text:find("already have 200"), "says why it stopped")
assert(big.skipped == 300 - PN.MAX_LOCAL - 1, "the rest were not tried")
c.TwichUIDB.pins.list = {}
local long = PW.ImportText("/way 5 5 " .. ("x"):rep(400))
assert(long.count == 0 and long.errors[1].text:find("too long"))
local comma = PW.ImportText("/way 52,3 40,7 Rare\n/way 52.3 40.7 Rare")
assert(comma.count == 1 and comma.failed == 1 and comma.errors[1].line == 1 and comma.errors[1].text:find("point for decimals"),
  "a decimal-comma line is refused on its own; the next line still makes its pin")
local made = PN.LocalPins()[1]
assert(made.x == 5230 and made.y == 4070, "only the pin from the line with points")
c.TwichUIDB.pins.list = {}

---------------------------------------------------------------------------
-- 5. The paste window is made on demand, reads the box and keeps what failed
---------------------------------------------------------------------------
assert(c.TwichUIPinPaste == nil and not PW.IsOpen(), "nothing is built until asked for")
cmd(c, "paste")
local win = c.TwichUIPinPaste
assert(win and PW.IsOpen(), "opened by /twichway paste")
local edit   -- the multi-line box is the window's only EditBox
for _, fr in ipairs(c.frames) do if fr.kindOf == "EditBox" then edit = fr end end
assert(edit, "the box exists")
edit:SetText("/way 11 11 Pasted one\n/way nonsense\n\n/twichway Westfall 12 12 Pasted two")
local pinsBefore = PN.LocalCount()
win.import.scripts.OnClick(win.import)
assert(PN.LocalCount() == pinsBefore + 2, "both good lines became pins")
assert(edit:GetText() == "\n/way nonsense\n\n", "made lines are cleared in place, so numbers still match and nothing repeats: " .. edit:GetText())

---------------------------------------------------------------------------
-- 6. Off: the commands explain and make nothing; /twichway always exists
---------------------------------------------------------------------------
c.TwichUIDB.modules.partyPins = false
local count = PN.LocalCount()
cmd(c, "5 5")
assert(PN.LocalCount() == count and joined(c):find("turned off"), joined(c))
cmd(c, "paste"); assert(joined(c):find("turned off"))
c.TwichUIDB.modules.partyPins = true

---------------------------------------------------------------------------
-- 7. Who has /way
---------------------------------------------------------------------------
assert(c.SLASH_TWICHUIWAY1 == "/twichway" and c.SlashCmdList.TWICHUIWAY == PW.Run, "/twichway is always there")
assert(c.SLASH_TWICHUIWAY2 == "/way" and PW.WayState() == "ours", "free at login: TwichUI takes it")

-- another addon's pending registration (TomTom registers before TwichUI's PLAYER_LOGIN)
local pending = build("Way B", { before = function(env)
  env.SLASH_TOMTOM_WAY1 = "/way"; env.SLASH_TOMTOM_WAY2 = "/tway"
  env.SlashCmdList.TOMTOM_WAY = function() end
end })
assert(pending.SLASH_TWICHUIWAY2 == nil and pending.SLASH_TWICHUIWAY1 == "/twichway", "not taken from another addon; /twichway stays")
assert(pending.TwichUI.PinsWay.WayState() == "other")
assert(pending.SlashCmdList.TOMTOM_WAY ~= nil and pending.SLASH_TOMTOM_WAY1 == "/way", "its registration is untouched")
cmd(pending, "")
assert(joined(pending):find("/way is used by another addon", 1, true), "mentioned in help")
cmd(pending, "5 5 Works anyway")
assert(pending.TwichUI.Pins.LocalCount() == 1, "/twichway still works")
pending.TwichUI.PinsWay.Refresh()
assert(pending.SLASH_TWICHUIWAY2 == nil, "asking again doesn't change that")

-- one the game has already moved into its hash table
local imported = build("Way C", { before = function(env)
  env.hash_SlashCmdList = { ["/WAY"] = function() end }
end })
assert(imported.SLASH_TWICHUIWAY2 == nil and imported.TwichUI.PinsWay.WayState() == "other")

-- the switch is off at login: /way is not claimed until it is turned on
local off = build("Way D", { off = true })
assert(off.SLASH_TWICHUIWAY2 == nil and off.TwichUI.PinsWay.WayState() == nil and off.SLASH_TWICHUIWAY1 == "/twichway")
cmd(off, "5 5"); assert(joined(off):find("turned off") and off.TwichUI.Pins.LocalCount() == 0)
off.TwichUIDB.modules.partyPins = true
off.TwichUI.PinsWay.Refresh()
assert(off.SLASH_TWICHUIWAY2 == "/way" and off.TwichUI.PinsWay.WayState() == "ours")
cmd(off, "5 5"); assert(off.TwichUI.Pins.LocalCount() == 1)

-- the game imports ours: still ours, and a later addon that is imported over it is reported as theirs
off.hash_SlashCmdList = { ["/WAY"] = off.SlashCmdList.TWICHUIWAY }
assert(off.TwichUI.PinsWay.WayState() == "ours")
off.hash_SlashCmdList["/WAY"] = function() end
assert(off.TwichUI.PinsWay.WayState() == "other")
local snap = off.TwichUI.PinsWay.Snapshot()
assert(snap.way == "other" and snap.made >= 1 and snap.commands >= 1)

---------------------------------------------------------------------------
-- 7b. Also make a pin from another addon's /way (opt in): it runs after the owner, unchanged
---------------------------------------------------------------------------
do
  local calls = {}
  local function owner(msg, ...) calls[#calls + 1] = { msg = msg, extra = select("#", ...) } end
  local w = build("Way E", { before = function(env)
    env.SLASH_WAYPOINT_UI_WAY1 = "/way"
    env.SlashCmdList.WAYPOINT_UI_WAY = owner
  end })
  local PWe, PNe, PLe = w.TwichUI.PinsWay, w.TwichUI.Pins, w.TwichUI.PinsLook
  assert(PLe.Pref("wayAlso") == false and w.SlashCmdList.WAYPOINT_UI_WAY == owner, "off by default: the owner's handler is untouched")
  w.SlashCmdList.WAYPOINT_UI_WAY("52.3 40.7 Rare")
  assert(#calls == 1 and PNe.LocalCount() == 0, "the owner works as before and makes no pin")

  PLe.SetPref("wayAlso", true)
  local wrappedFn = w.SlashCmdList.WAYPOINT_UI_WAY
  assert(wrappedFn ~= owner and w.SLASH_WAYPOINT_UI_WAY1 == "/way", "followed when chosen; its slash names are untouched")
  assert(w.SLASH_TWICHUIWAY2 == nil, "and /way is still its own")
  PLe.SetPref("labels", "always"); PLe.SetPref("wayAlso", true)
  assert(w.SlashCmdList.WAYPOINT_UI_WAY == wrappedFn, "followed once, however often the choice is applied")

  calls = {}
  clear(w)
  w.SlashCmdList.WAYPOINT_UI_WAY("Westfall 10 20 Gryphon master", "editbox")
  assert(#calls == 1 and calls[1].msg == "Westfall 10 20 Gryphon master" and calls[1].extra == 1, "the owner got the same arguments, once")
  local made = PNe.LocalPins()
  assert(#made == 1 and made[1].map == 1436 and made[1].x == 1000 and made[1].name == "Gryphon master", "and a pin was made from the same text")
  assert(joined(w):find("Pin made: Gryphon master"))

  clear(w)
  for _, text in ipairs({ "reset", "paste", "clear", "list", "", "Westfall", "52.3" }) do w.SlashCmdList.WAYPOINT_UI_WAY(text) end
  assert(PNe.LocalCount() == 1 and #w.said == 0, "not a waypoint: no pin and nothing said")
  w.SlashCmdList.WAYPOINT_UI_WAY("Nagrand 5 5")
  assert(PNe.LocalCount() == 1 and joined(w):find("No zone called"), "a waypoint that can't be placed says why")

  PLe.SetPref("wayAlso", false)
  clear(w)
  w.SlashCmdList.WAYPOINT_UI_WAY("1 1 Gated")
  assert(PNe.LocalCount() == 1 and #w.said == 0, "turned off: gated, the owner still runs")

  PLe.SetPref("wayAlso", true)
  w.TwichUIDB.modules.partyPins = false
  w.SlashCmdList.WAYPOINT_UI_WAY("1 1 Off")
  assert(PNe.LocalCount() == 1, "the feature off: no pin")
  w.TwichUIDB.modules.partyPins = true
  assert(PWe.Snapshot().followed and PWe.Snapshot().also == true and PWe.Snapshot().alsoMade == 1)

  -- the same, with the owner already imported by the game (in the list's proxy table, and the hash)
  local live = function() end
  local imported2 = build("Way F", { before = function(env)
    env.SLASH_WAYPOINT_UI_WAY1 = "/way"
    local proxy = { WAYPOINT_UI_WAY = live, SOMETHING_ELSE = function() end }
    env.SlashCmdList = setmetatable({}, { __index = proxy })
    env.hash_SlashCmdList = { ["/WAY"] = live }
    env.SLASH_SOMETHING_ELSE1 = "/other"
  end })
  imported2.TwichUI.PinsLook.SetPref("wayAlso", true)
  local fn = imported2.SlashCmdList.WAYPOINT_UI_WAY
  assert(fn ~= live and rawget(imported2.SlashCmdList, "WAYPOINT_UI_WAY") == fn, "the imported owner is followed too")
  assert(rawget(imported2.SlashCmdList, "SOMETHING_ELSE") == nil, "and nothing else is touched")
  fn("20 20 Imported")
  assert(imported2.TwichUI.Pins.LocalCount() == 1)

  -- never when TwichUI has /way itself
  local mine = build("Way G")
  mine.TwichUI.PinsLook.SetPref("wayAlso", true)
  assert(mine.TwichUI.PinsWay.WayState() == "ours" and not mine.TwichUI.PinsWay.Snapshot().followed, "nothing to follow")
end

---------------------------------------------------------------------------
-- 8. Existing manual creation is unchanged
---------------------------------------------------------------------------
local PE = R.PinsEditor
PE.OpenNew(1429, 4000, 5000, false)
local ed = c.TwichUIPinEditor
ed.name:SetText("By hand")
ed.save.scripts.OnClick(ed.save)
local hand
for _, p in ipairs(PN.LocalPins()) do if p.name == "By hand" then hand = p end end
assert(hand and hand.map == 1429 and hand.x == 4000 and hand.y == 5000, "the editor still saves")

print("WAY COMMAND TESTS PASSED")
