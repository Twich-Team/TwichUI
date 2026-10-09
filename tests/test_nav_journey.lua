dofile(TESTS .. "harness.lua")
-- Navigation end to end with a simulated client: off until chosen; the reasons a route can't be planned;
-- a walk; walk, fly, walk with learning at the flight master and timing the flight; landing elsewhere;
-- leaving the continent; Stop, Recalculate and turning navigation off; the world map's menu and drawing;
-- the strip and arrow; and a troubleshooting section without places or names in it.
-- Mocks show TwichUI's own decisions. They can't show how anything looks, or what the real game reports.
local c = MakeClient("Rich", {"!!!TwichUI"})

---------------------------------------------------------------------------
-- A small world. One continent map (1415, instance 0) of 10000 x 10000 yards; another (1414, instance 1).
---------------------------------------------------------------------------
local SIZE = 10000
local function Vec(x, y) return { x = x, y = y, GetXY = function(s) return s.x, s.y end } end
-- What the game hands back is read as fields, as Blizzard's map code does: these have no GetXY.
local function Plain2(x, y) return { x = x, y = y } end
c.CreateVector2D = Vec
c.Enum = { UIMapType = { Continent = 2, Zone = 3 }, FlightPathFaction = { Neutral = 0, Horde = 1, Alliance = 2 },
  FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
local CONTINENT = { [1415] = 0, [1414] = 1 }
-- Zone 1429 sits in the top-left quarter of continent 1415. The game won't convert its points to the
-- world directly (as may happen on this client); TwichUI goes through the continent's map instead.
local ZONE = { [1429] = { parent = 1415, left = 0, right = 0.5, top = 0, bottom = 0.5 } }
c.C_Map = {
  GetWorldPosFromMapPos = function(id, v) local cont = CONTINENT[id]; if cont then return cont, Plain2(v.x * SIZE, v.y * SIZE) end end,
  GetMapPosFromWorldPos = function(cont, v, override)
    local id = override or (cont == 0 and 1415 or 1414)
    if CONTINENT[id] ~= cont then return nil end
    return id, Plain2(v.x / SIZE, v.y / SIZE)
  end,
  GetMapRectOnMap = function(id, top)
    local z = ZONE[id]
    if z and z.parent == top then return z.left, z.right, z.top, z.bottom end
  end,
  GetMapInfo = function(id)
    if CONTINENT[id] then return { mapType = 2, name = "Continent", parentMapID = 947 } end
    if ZONE[id] then return { mapType = 3, name = "Zone", parentMapID = ZONE[id].parent } end
  end,
  GetMapInfoAtPosition = function() return { mapType = 3, name = "Elwynn Forest" } end,
  GetBestMapForUnit = function() return c.POS.map == 0 and 1415 or 1414 end,
  HasUserWaypoint = function() return c.PIN ~= nil end,
  GetUserWaypoint = function() return c.PIN end,
}
local function Pin(id, x, y) c.PIN = { uiMapID = id, position = Plain2(x / SIZE, y / SIZE) } end
c.POS = { x = 100, y = 100, map = 0 }
c.UnitPosition = function() if c.POS then return c.POS.x, c.POS.y, 0, c.POS.map end end
local function At(x, y) c.POS.x, c.POS.y = x, y end
c.INST = false
c.IsInInstance = function() if c.INST then return true, "party" end return false, "none" end
c.TAXI = false
c.UnitOnTaxi = function() return c.TAXI end
c.GetUnitSpeed = function() return 0, 7, 0, 0 end
c.UnitFactionGroup = function() return "Alliance" end
c.FACING = 0
c.GetPlayerFacing = function() return c.FACING end
c.NOW = 1000
c.GetTime = function() return c.NOW end

-- Flight points: A by the start, B by the destination, U undiscovered, H the other faction's.
local NODES = {
  { nodeID = 11, name = "A Field, Elwynn", x = 150, y = 100, faction = 2 },
  { nodeID = 12, name = "B Hill, Westfall", x = 8950, y = 100, faction = 0 },
  { nodeID = 13, name = "U Unknown", x = 9000, y = 100, faction = 2, isUndiscovered = true },
  { nodeID = 14, name = "H Horde Camp", x = 8900, y = 100, faction = 1 },
  { nodeID = 15, name = "E Elsewhere", x = 5000, y = 5000, faction = 2 },
  -- G: the world map's list calls it found, but this character doesn't have it; the flight master's map
  -- lists it as unreachable. It sits right by the destination, so using it would look attractive.
  { nodeID = 16, name = "G Gate", x = 8995, y = 390, faction = 2 },
}
c.C_TaxiMap = {
  GetTaxiNodesForMap = function(id)
    if id ~= 1415 then return {} end
    local out = {}
    for i, n in ipairs(NODES) do
      out[i] = { nodeID = n.nodeID, name = n.name, position = Plain2(n.x / SIZE, n.y / SIZE), faction = n.faction, isUndiscovered = n.isUndiscovered == true }
    end
    return out
  end,
  -- At A's flight master: slot 1 is A (current), slot 2 is B, reached through E; slot 3 is E.
  GetAllTaxiNodes = function()
    return { { nodeID = 11, slotIndex = 1, state = 0 }, { nodeID = 12, slotIndex = 2, state = 1 }, { nodeID = 15, slotIndex = 3, state = 1 },
      { nodeID = 16, slotIndex = 4, state = 2 } }
  end,
}
c.GetTaxiMapID = function() return 1415 end
local ROUTES = { [2] = { { 1, 3 }, { 3, 2 } }, [3] = { { 1, 3 } } }
c.GetNumRoutes = function(slot) return ROUTES[slot] and #ROUTES[slot] or 0 end
c.TaxiGetNodeSlot = function(slot, r, src) local hop = ROUTES[slot][r]; return src and hop[1] or hop[2] end
c.TakeTaxiNode = function() end
local secureHooks = {}
c.hooksecurefunc = function(name, fn) secureHooks[name] = fn end

---------------------------------------------------------------------------
-- Frames, the world map, its menu
---------------------------------------------------------------------------
local created = { lines = 0, textures = 0 }
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks = false, {}, {}
  return setmetatable(o, { __index = function(_, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn; if n == "OnUpdate" then UPDATERS[s] = fn end end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = fn end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "SetFormattedText" then return function(s, f, ...) s.text = f:format(...) end end
    if k == "SetFont" then return function() return true end end
    if k == "IsEnabled" then return function() return true end end
    if k == "GetWidth" then return function(s) return s.w or 100 end end
    if k == "GetHeight" then return function(s) return s.h or 100 end end
    if k == "CreateFontString" then return function() return Fake() end end
    if k == "CreateTexture" then return function() created.textures = created.textures + 1; return Fake() end end
    if k == "CreateLine" then return function() created.lines = created.lines + 1; return Fake() end end
    return function() end
  end })
end
c.CreateFrame = function() return Fake() end
c.UIParent = Fake()
c.GameTooltip = Fake()

local canvas = Fake({ w = 1000, h = 1000 })
local map = Fake({ shown = false })
map.GetMapID = function() return 1415 end
map.GetCanvas = function() return canvas end
map.GetCanvasScale = function() return 1 end
map.GetPinFrameLevelsManager = function() return { GetValidFrameLevel = function() return 2100 end } end
local providers = {}
map.AddDataProvider = function(self, p) p.owningMap = self; providers[p] = true end
map.RemoveDataProvider = function(_, p) providers[p] = nil end
c.WorldMapFrame = map
c.MapCanvasDataProviderMixin = { GetMap = function(self) return self.owningMap end }
c.CreateFromMixins = function(...) local t = {} for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
local menus = {}
c.Menu = { ModifyMenu = function(tag, fn) menus[tag] = fn end }

local said = {}
c.print = function(s) said[#said + 1] = tostring(s) end
local function Heard(text) for _, s in ipairs(said) do if s:find(text, 1, true) then return true end end return false end

for _, f in ipairs({ "chronicle/Style.lua", "nav/World.lua", "nav/Data.lua", "nav/Flights.lua", "nav/Planner.lua",
  "nav/Journey.lua", "nav/MapTrail.lua", "nav/Guide.lua", "diag/Diagnostics.lua", "diag/Navigation.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN")
local R = c.TwichUI
local N, F, ND, M, G = R.Nav, R.NavFlights, R.NavData, R.NavMap, R.NavGuide

local function Provider() return next(providers) end
local function Tick(n) for _ = 1, n or 1 do RunTickers() end end
local function Menu()
  local root, items = {}, {}
  root.CreateDivider = function() items[#items + 1] = { kind = "divider" } end
  root.CreateTitle = function(_, text) items[#items + 1] = { kind = "title", text = text } end
  root.CreateButton = function(_, text, fn)
    local item = { kind = "button", text = text, fn = fn }
    item.SetTooltip = function(self, tip) self.tip = tip end
    items[#items + 1] = item
    return item
  end
  menus.MENU_WORLD_MAP_TRACKING(nil, root)
  return items
end
local function Button(items, text) for _, i in ipairs(items) do if i.kind == "button" and i.text == text then return i end end end
local function TooltipText(item)
  local lines = {}
  local tip = { SetText = function(_, t) lines[#lines + 1] = t end, AddLine = function(_, t) lines[#lines + 1] = t end }
  item.tip(tip)
  return table.concat(lines, "\n")
end
local function Strip() return G.Snapshot().strip end

---------------------------------------------------------------------------
-- 1) Off by default: no menu entry, no drawing, no events, nothing learned.
---------------------------------------------------------------------------
assert(c.TwichUIDB.modules.navigation == false and c.TwichUIDB.modules.navigationArrow == true, "opt-in; the arrow comes with it")
assert(menus.MENU_WORLD_MAP_TRACKING, "the menu hook is in place (it checks the setting each time)")
assert(#Menu() == 0, "nothing in the menu while off")
assert(Provider() == nil, "nothing drawn on the map while off")
assert(#F.Snapshot().events == 0, "no events while off")
assert(secureHooks.TakeTaxiNode, "TakeTaxiNode is watched (the hook checks the setting)")
secureHooks.TakeTaxiNode(2)
assert(not F.Snapshot().watching, "a flight chosen while off isn't watched")
Pin(1415, 700, 100)
assert(N.StartToPin() == false and Heard("Navigation is turned off"), "asking while off says how to turn it on")

c.TwichUIDB.modules.navigation = true
N.Refresh()
assert(Provider() and #F.Snapshot().events == 6, "on: drawing provider and its events")

---------------------------------------------------------------------------
-- 2) Why a route can't be planned
---------------------------------------------------------------------------
c.PIN = nil
assert(select(2, N.StartToPin()) == "no-pin" and Heard("Ctrl-click the world map"), "no pin")
Pin(1414, 500, 500)
assert(select(2, N.StartToPin()) == "other-continent" and Heard("another continent"), "a pin on another continent")
Pin(1415, 700, 100)
c.INST = true
assert(select(2, N.StartToPin()) == "instance", "inside an instance")
c.INST = false
local keep = c.POS; c.POS = nil
assert(select(2, N.StartToPin()) == "no-position", "no position")
c.POS = keep
assert(N.Current() == nil and not Strip(), "none of those started anything")

-- A pin placed on a zone's map, which the game only converts through the continent: it still works.
At(100, 100)
c.PIN = { uiMapID = 1429, position = Plain2(0.14, 0.02) }   -- 0.14 * 5000 = 700, 0.02 * 5000 = 100
local zonePlan, zoneGoal = N.Preview()
assert(zonePlan and math.abs(zoneGoal.x - 700) < 1e-6 and math.abs(zoneGoal.y - 100) < 1e-6, "a zone map's pin, through its continent")
assert(N.Snapshot().pinProblem == "via-continent", "the report says how the pin was read")
-- A pin whose position the game gives in a form that can't be read says so, and the report names the step.
c.PIN = { uiMapID = 1415, position = {} }
assert(select(2, N.StartToPin()) == "bad-pin" and N.Snapshot().pinProblem == "pin-unreadable")
c.PIN = { uiMapID = 9999, position = Plain2(0.5, 0.5) }
assert(select(2, N.StartToPin()) == "bad-pin" and N.Snapshot().pinProblem == "no-continent", "a map the game can't place")

---------------------------------------------------------------------------
-- 3) A short walk: one step, a minimum, then arrival.
---------------------------------------------------------------------------
At(100, 100); Pin(1415, 700, 100)
local items = Menu()
local start = Button(items, "Route to your map pin")
assert(start and start.tip, "the menu offers a route to the pin, with a tooltip")
local tipText = TooltipText(start)
assert(tipText:find("Fastest estimated route using supported, known travel options", 1, true), "honest heading")
assert(tipText:find("Walk to your map pin in Elwynn Forest", 1, true) and tipText:find("at least", 1, true) and tipText:find("terrain not considered", 1, true), tipText)
assert(N.Current() == nil, "the tooltip only previews")
start.fn()
local j = N.Current()
assert(j and #j.plan.legs == 1 and j.plan.legs[1].mode == "walk", "a walk")
assert(Strip() and G.Snapshot().arrow and G.Snapshot().arrowUpdating, "strip and arrow shown")
items = Menu()
assert(Button(items, "Recalculate the route") and Button(items, "Stop the route") and Button(items, "Route to your map pin"), "an active route's menu")
-- choosing the pin again replaces the route
Button(items, "Route to your map pin").fn()
assert(N.Current() ~= j and N.Snapshot().counts.replaced == 1, "a new route in place of the old one")
j = N.Current()
FlushTimers()
At(400, 100); Tick()
assert(N.Current() == j and j.index == 1, "half way, still walking")
At(690, 100); Tick()
assert(N.Current() == nil and N.Snapshot().counts.arrived == 1, "arrived within 20 yards")
assert(Strip() and not G.Snapshot().arrow and not G.Snapshot().arrowUpdating, "the closing line stays a moment; the arrow stops at once")
RunLongTimers(4)
assert(not Strip(), "then it goes")
assert(TICKERS[#TICKERS].cancelled, "the route's ticker is stopped")

---------------------------------------------------------------------------
-- 4) Walk, fly, walk: learning at the flight master and timing the flight
---------------------------------------------------------------------------
At(100, 100); Pin(1415, 9000, 400)
-- Before any flight master's map has been opened, no flight point counts as this character's, whatever
-- the world map's list says: walking only, and the tooltip says why.
local plan = N.Preview()
assert(plan and #plan.legs == 1 and plan.legs[1].mode == "walk" and plan.flightsUnknown, "no flights until a flight master has been seen")
assert(TooltipText(Button(Menu(), "Route to your map pin")):find("open any flight master's map", 1, true), "the tooltip says what to do")
assert(F.Counts().gameFound == 4 and F.Counts().known == 0, "the world map's list calls four found; none are known yet")
-- Open the flight master's map at A: A, B and E are this character's; G is listed as unreachable.
c.FireEvent("TAXIMAP_OPENED", 1)
c.FireEvent("TAXIMAP_CLOSED")
assert(ND.Known()[11] and ND.Known()[12] and ND.Known()[15] and not ND.Known()[16] and not ND.Known()[13], "only current and reachable points")
assert(F.Counts().known == 3 and F.Snapshot().lastScanKnown == 3)
plan = N.Preview()
assert(plan and #plan.legs == 3 and not plan.flightsUnknown, "a long way flies")
local fl = plan.legs[2]
assert(plan.legs[1].toNode.id == 11 and fl.mode == "flight" and fl.toNode.id == 12,
  "A to B: not G (which this character doesn't have, though the world map says found), U or the Horde point")
assert(fl.confirmed and not fl.learned and N.TimeNote(fl):find("assumed flight speed until you have flown once", 1, true), "a seen route, not yet flown")
assert(#fl.points == 6, "through E, as the flight master showed")
assert(N.StartToPin())
c.WorldMapFrame.shown = true
Provider():RefreshAllData()
local drawn = M.Snapshot()
assert(drawn.dots > 0 and drawn.dashes > 0 and drawn.marks == 3, "walking dots, flight dashes, both flight points and the destination")
assert(drawn.dots < 500 and drawn.clipped == 0, "within the limits")
-- walk to A
At(150, 105); Tick()
j = N.Current()
assert(j.index == 2 and j.plan.legs[2].mode == "flight" and not j.flying, "at the flight master, before take-off")
-- the flight master's map: A to B goes through E
c.FireEvent("TAXIMAP_OPENED", 1)
local hops = ND.Route(11, 12)
assert(hops and #hops == 3 and hops[2] == 15 and ND.Route(11, 15), "routes the flight master shows are noted")
assert(F.Snapshot().lastScan == "learned" and F.Snapshot().lastScanRoutes == 2)
secureHooks.TakeTaxiNode(2)
assert(F.Snapshot().watching, "the chosen destination is watched")
c.FireEvent("TAXIMAP_CLOSED")
c.FireEvent("PLAYER_CONTROL_LOST")
c.TAXI = true; Tick()
assert(N.Current().flying, "in the air")
FlushTimers()
c.NOW = c.NOW + 240
At(8955, 100)
c.TAXI = false
c.FireEvent("PLAYER_CONTROL_GAINED")
assert(ND.Time({ 11, 15, 12 }) == 240 and F.Snapshot().lastFlight == "timed", "the flight's time is noted for its stops")
Tick()
j = N.Current()
assert(j.index == 3 and j.plan.legs[3].mode == "walk", "landed near B: walk on")
At(8990, 395); Tick()
assert(N.Current() == nil and N.Snapshot().counts.arrived == 2, "arrived again")
-- Going back: B to A has not been seen at a flight master (only A's map was opened), so it is assumed direct.
do
  local savedPin = c.PIN
  At(8950, 100); Pin(1415, 120, 100)
  local back = N.Preview()
  assert(back.legs[2] and back.legs[2].mode == "flight" and not back.legs[2].confirmed
    and N.TimeNote(back.legs[2]):find("route not yet seen", 1, true), "an assumed flight says so")
  c.PIN = savedPin
end
RunLongTimers(4)

-- The next route uses what was learned: the route through E, and its measured time.
At(100, 100)
plan = N.Preview()
fl = plan.legs[2]
assert(fl.confirmed and fl.learned and math.abs(fl.seconds - (240 + R.NavPlanner.BOARDING)) < 1e-6, "measured time")
assert(N.TimeNote(fl):find("from your earlier flight", 1, true))
assert(#fl.points == 6, "drawn through its three stops")

---------------------------------------------------------------------------
-- 5) Landing somewhere else plans again from there; walking far from the flight master too.
---------------------------------------------------------------------------
assert(N.StartToPin())
At(150, 100); Tick()
c.TAXI = true; Tick()
c.TAXI = false; At(5000, 5000); Tick()
j = N.Current()
assert(j and N.Snapshot().counts["landed-elsewhere"] == 1 and j.index == 1, "planned again from where you landed")
N.Stop()
assert(N.Current() == nil and not Strip(), "Stop ends it at once, with no closing line")
assert(N.Snapshot().counts.cancelled == 1)

At(100, 100)
assert(N.StartToPin())
At(150, 100); Tick()
assert(N.Current().plan.legs[N.Current().index].mode == "flight")
At(600, 100); Tick()
assert(N.Snapshot().counts["left-flight-master"] == 1, "walking away from the flight master plans again")

---------------------------------------------------------------------------
-- 6) Paused in an instance; leaving the continent ends the route.
---------------------------------------------------------------------------
c.INST = true; Tick()
assert(N.Current().status == "instance" and Strip(), "paused, and the strip says so")
c.INST = false; Tick()
assert(N.Current().status == nil, "goes on afterwards")
c.POS.map = 1; Tick()
assert(N.Current() == nil and N.Snapshot().counts["left-continent"] == 1 and Strip(), "leaving the continent ends it, saying why")
c.POS.map = 0
RunLongTimers(4)

---------------------------------------------------------------------------
-- 7) Recalculate; a route quicker by a little is not taken, one much quicker is.
---------------------------------------------------------------------------
At(100, 100); Pin(1415, 3000, 100)
assert(N.StartToPin())
assert(N.Recalculate() and N.Snapshot().counts.recalculated == 1)
local before = N.Current().plan
c.NOW = c.NOW + 11; At(110, 100); Tick()
assert(N.Current().plan == before, "nothing much quicker: the steps don't change")

---------------------------------------------------------------------------
-- 8) Turning navigation off mid-route takes everything away.
---------------------------------------------------------------------------
c.TwichUIDB.modules.navigation = false
N.Refresh()
assert(N.Current() == nil and not Strip() and not G.Snapshot().arrow and Provider() == nil, "off: no route, strip, arrow or drawing")
assert(#F.Snapshot().events == 0 and #Menu() == 0, "no events, no menu entry")
assert(N.Snapshot().counts["module-off"] == 1)
c.TwichUIDB.modules.navigation = true
N.Refresh()
assert(Provider(), "back on")

-- The arrow can be left out.
c.TwichUIDB.modules.navigationArrow = false
assert(N.StartToPin())
assert(Strip() and not G.Snapshot().arrow, "the strip without the arrow")
N.Stop()
c.TwichUIDB.modules.navigationArrow = true

---------------------------------------------------------------------------
-- 9) The troubleshooting section: codes and counts, no places or names.
---------------------------------------------------------------------------
local report = R.Diag.Build()
local from = report:find("== Navigation ==", 1, true)
assert(from, "a Navigation section")
local section = report:sub(from)
for _, word in ipairs({ "Elwynn", "Westfall", "Field", "Hill", "8955", "9000" }) do
  assert(not section:find(word, 1, true), "no place or name in the report: " .. word)
end
assert(section:find("result arrived: 2", 1, true) and section:find("routes", 1, true), "results and learned counts")

---------------------------------------------------------------------------
-- 10) Learned data is never something a setup or backup can touch, and forgetting it works.
---------------------------------------------------------------------------
assert(R.Setups.SafeName("TwichUINavigationDB") == false, "sharing and backups refuse it")
ND.Forget()
assert(ND.Route(11, 12) == nil and ND.Snapshot().times == 0 and next(ND.Known()) == nil, "forgotten")
At(100, 100); Pin(1415, 9000, 400)
assert(#N.Preview().legs == 1, "with nothing known, no flights again")

---------------------------------------------------------------------------
-- 11) The arrow's bearing: counter-clockwise from north, as GetPlayerFacing measures (x north, y west).
---------------------------------------------------------------------------
local W = R.NavWorld
local function Close(a, b) return math.abs(a - b) < 1e-9 end
assert(Close(W.Bearing(0, 0, 10, 0), 0), "north")
assert(Close(W.Bearing(0, 0, 0, 10), math.pi / 2), "west is a quarter turn counter-clockwise")
assert(Close(W.Bearing(0, 0, 0, -10), -math.pi / 2), "east")
assert(W.Plain(0 / 0) == nil and W.Plain(1 / 0) == nil and W.Plain("1") == nil and W.Plain(3) == 3)

print("NAV JOURNEY TESTS PASSED")
