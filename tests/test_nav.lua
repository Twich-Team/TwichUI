-- Navigation: the journey being followed (nav/Nav.lua), with the real planner on synthetic walking maps
-- (tests/fixtures/nav_fixture.lua), a simulated player and the map functions as a linear map of one tile.
--   1  idle costs nothing             2  start, plan, follow, corners in order, instructions and distances
--   3  no skipping across an obstacle; off the route plans again (once, after the hold)
--   4  arrival (one sound, then idle)  5  position lost and back      6  another continent; an island (direct bearing)
--   7  a newer destination replaces a search still running            8  stop, the switch, cleanup
--   9  the client's world frame checked (swapped is followed; a diagonal is refused)
--  10  geometry: clipping, the minimap's rotation, ants, bearings     11  the preview and the words, and that the
--      preview never touches navigation                               12  /tui nav
-- What this cannot show: the game's real coordinates, frames, textures and drawing, or how following a route feels.
dofile(TESTS .. "harness.lua")
dofile(TESTS .. "nav_codec.lua")
dofile(TESTS .. "fixtures/nav_fixture.lua")
CLOCK = 1000

local c = MakeClient("Rich Hale", { "!!!TwichUI" })
CLIENTS["Rich Hale"] = c
c.GetTime = function() return CLOCK end
c.debugprofilestop = function() return os.clock() * 1000 end
c.C_EncodingUtil, c.Enum = NAV_CODEC.C_EncodingUtil, NAV_CODEC.Enum
c.issecretvalue = nil

-- permissive frames: every method exists; the ones navigation reads give plain numbers
local FRAMES = {}
local function Obj()
  local o = { shown = false, scripts = {} }
  return setmetatable(o, { __index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" or k == "IsVisible" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "GetScript" then return function(s, n) return s.scripts[n] end end
    if k == "SetText" then return function(s, v)
      -- as in the game: a font string with no font (no template, no SetFont yet) can't take text
      assert(s.hasFont ~= false or s.font, "FontString:SetText(): Font not set")
      s.text = v
    end end
    if k == "SetFont" then return function(s, f) s.font = f; return true end end
    if k == "GetText" then return function(s) return s.text end end
    if k == "GetStringWidth" then return function() return 60 end end
    if k == "GetStringHeight" then return function() return 12 end end
    if k == "GetWidth" then return function(s) return s.width or 200 end end
    if k == "GetHeight" then return function(s) return s.height or 200 end end
    if k == "SetWidth" then return function(s, v) s.width = v end end
    if k == "SetHeight" then return function(s, v) s.height = v end end
    if k == "SetSize" then return function(s, w, h) s.width, s.height = w, h end end
    if k == "GetScale" or k == "GetEffectiveScale" then return function() return 1 end end
    if k == "GetFrameLevel" then return function() return 5 end end
    if k == "GetCenter" then return function() return 500, 400 end end
    if k == "SetRotation" then return function(s, a) s.rotation = a end end
    if k == "SetVertexColor" then return function(s, r, g, b, a) s.color = { r, g, b, a } end end
    if k == "CreateFontString" then
      return function(_, _, _, template)
        local fs = Obj()
        fs.hasFont = (template ~= nil) and true or false   -- a template brings a font
        if template then fs.font = template end
        return fs
      end
    end
    if k == "CreateTexture" or k == "CreateLine" then return function() return Obj() end end
    if type(k) == "string" and k:match("^%u") then return function() end end
    return nil
  end })
end
c.CreateFrame = function() local o = Obj(); FRAMES[#FRAMES + 1] = o; return o end
c.UIParent = Obj()
c.GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
c.GameTooltip = Obj()
local sounds = {}
c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel }; return true end
c.InCombatLockdown = function() return false end

-- the data addon, already loaded, holding the synthetic maps
c.C_AddOns = c.C_AddOns or {}
c.C_AddOns.DoesAddOnExist = function() return true end
c.C_AddOns.GetAddOnEnableState = function() return 2 end
c.C_AddOns.IsAddOnLoaded = function(name) return name == "TwichUI_NavData" or name == "!!!TwichUI" end
c.C_AddOns.LoadAddOn = function() return true end

-- The world: one uiMap per synthetic map, each exactly its tile (x0, y0: world north and west at its top left)
local TILE = 1600 / 3
local ORIGIN = 32 * TILE
local CS = TILE / 40
local MAPS = {}
local function Tile(map, cont, tx, ty)
  MAPS[map] = { cont = cont, x0 = ORIGIN - ty * TILE, y0 = ORIGIN - tx * TILE, size = TILE }
end
Tile(1001, 9001, 32, 32)       -- the U
Tile(1003, 9003, 40, 40)       -- islands
Tile(2002, 9100, 32, 32)       -- a continent with no walking map
local function W(map, u, w)    -- tile-local cells (u north, w west) to world
  local m = MAPS[map]
  return m.x0 - TILE + u * CS, m.y0 - TILE + w * CS
end
local SWAP, DIAGONAL = false, false
c.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
c.C_Map = {}
local P = { map = 1001, x = 0, y = 0, facing = 0, lost = false }
c.C_Map.GetWorldPosFromMapPos = function(map, v)
  local m = MAPS[map]
  if not m then return nil end
  local wx, wy = m.x0 - v.y * m.size, m.y0 - v.x * m.size
  if DIAGONAL then wx, wy = wx - v.x * 50, wy - v.x * m.size end
  if SWAP then wx, wy = wy, wx end
  return m.cont, c.CreateVector2D(wx, wy)
end
c.C_Map.GetBestMapForUnit = function() if P.lost then return nil end return P.map end
c.C_Map.GetPlayerMapPosition = function(map)
  local m = MAPS[map]
  if P.lost or not m then return nil end
  return c.CreateVector2D((m.y0 - P.y) / m.size, (m.x0 - P.x) / m.size)
end
c.C_Map.GetMapInfo = function(map) return { name = "Zone " .. map, parentMapID = 0 } end
c.GetPlayerFacing = function() return P.facing end

local EXTRA = { "modules/Borders.lua", "modules/MenuStyle.lua", "nav/Prefs.lua", "nav/Data.lua", "nav/Route.lua",
  "nav/Nav.lua", "nav/Paint.lua", "nav/Frame.lua", "nav/Arrow.lua", "nav/MapTrail.lua", "nav/MinimapTrail.lua" }
for _, f in ipairs(EXTRA) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false); TIMERS = {}
local R = c.TwichUI
local NV, ND, NP, NPaint, NF = R.Nav, R.NavData, R.NavPrefs, R.NavPaint, R.NavFrame
R.NavDataStore.graph, R.NavDataStore.tiles = NAV_FIXTURE.graph, NAV_FIXTURE.tiles

local function Driver()
  for i = #FRAMES, 1, -1 do if FRAMES[i].scripts.OnUpdate then return FRAMES[i] end end
end
local function Run(seconds, onStep)
  local steps = math.floor(seconds / 0.05 + 0.5)
  for _ = 1, steps do
    CLOCK = CLOCK + 0.05
    local d = Driver()
    if d then d.scripts.OnUpdate(d, 0.05) end
    if onStep then onStep() end
  end
end
local function At(map, u, w) P.map = map; P.x, P.y = W(map, u, w) end
local function S() return NV.Snapshot() end

---------------------------------------------------------------------------
-- 1. Off by default, and idle costs nothing
---------------------------------------------------------------------------
assert(R.DEFAULT_MODULES.navigation == false, "navigation is opt-in")
assert(not NV.Enabled(), "off for a new install")
local ok, why = NV.StartAt(1001, 0.5, 0.5)
assert(not ok and why:find("turned off"), "nothing starts while it is off")
assert(Driver() == nil, "no driver while idle")
R:SetEnabled("navigation", true)
assert(NV.Enabled() and Driver() == nil and S().state == "idle", "turned on: still nothing runs until a destination is chosen")
print("1 idle ok")

---------------------------------------------------------------------------
-- 2. Start, plan, follow
---------------------------------------------------------------------------
At(1001, 35, 35)
local gx, gy = W(1001, 35, 5)
local m = MAPS[1001]
assert(NV.StartAt(1001, (m.y0 - gy) / m.size, (m.x0 - gx) / m.size, "Camp |cffff0000Red|r", "pin"))
assert(S().dest.name == "Camp cffff0000Redr", "a name from a pin is plain text: " .. S().dest.name)
assert(S().state == "calculating", "calculating first: " .. S().state)
Run(0.5)
local s = S()
assert(s.state == "navigating" and s.route and s.route.n == 4, "following a route of four points: " .. tostring(s.state))
assert(s.seg == 1, "on the first leg")
assert(s.instruction:find("turn left") or s.instruction:find("turn right"), "an instruction from the route's turn: " .. s.instruction)
assert(s.remaining >= s.toNext and s.straight < s.remaining, "distances: route left >= next corner; straight < route (the U)")
local words = { NF.Words(s) }
assert(words[3]:find("Route") and words[3]:find("Next") and words[3]:find("Straight"), "each distance labelled: " .. words[3])
-- walk the route: corners passed in order
local seen = { [1] = true }
local route = s.route
for i = 1, route.n - 1 do
  local ax, ay, bx, by = route.xs[i], route.ys[i], route.xs[i + 1], route.ys[i + 1]
  for k = 1, 10 do
    P.x, P.y = ax + (bx - ax) * k / 10, ay + (by - ay) * k / 10
    Run(0.25)
    local seg = S().seg
    assert(seg >= i, "never back")
    if seg <= 3 then seen[seg] = true end
    if S().state ~= "navigating" then break end
  end
  if S().state ~= "navigating" then break end
end
assert(seen[2] and seen[3], "each corner passed in turn")
print("2 follow ok", route.n, "points")

---------------------------------------------------------------------------
-- 4. Arrival (the walk above ended at the destination)
---------------------------------------------------------------------------
assert(S().state == "arrived", "arrived at the end: " .. S().state)
assert(#sounds == 1, "one arrival sound")
Run(5)
assert(S().state == "idle" and not NV.Active(), "navigation ends after a moment")
assert(not (Driver() and Driver().scripts.OnUpdate), "the driver stops")
print("4 arrival ok")

---------------------------------------------------------------------------
-- 3. Across the obstacle: no skipping; off the route plans again after the hold
---------------------------------------------------------------------------
At(1001, 35, 35)
assert(NV.StartAt(1001, (m.y0 - gy) / m.size, (m.x0 - gx) / m.size))
Run(0.5)
local first = S().route
local plans0 = NV.Diagnostics().plans
-- straight across the missing middle, a few yards a step (never a jump)
local maxSeg = 1
local u, w = 35, 35
while w > 6 do
  w = w - 0.5
  P.x, P.y = W(1001, u, w)
  Run(0.1, function() if S().route == first then maxSeg = math.max(maxSeg, S().seg) end end)
end
assert(maxSeg == 1, "no corner skipped because the destination is near in a straight line: " .. maxSeg)
-- Plans made from the missing middle fail (no walkable ground within reach) and are tried again after a wait, not every
-- update; once on the east strip the next try succeeds.
Run(12)
local now = S()
assert(now.route ~= first, "off the route long enough: a new route")
assert(NV.Diagnostics().offRoute >= 1, "counted as off the route")
assert(NV.Diagnostics().plans - plans0 <= 6, "planned again a bounded number of times, not every update")
print("3 off route ok", NV.Diagnostics().plans - plans0, "plans")
NV.Stop("test")

---------------------------------------------------------------------------
-- 5. Position lost and back
---------------------------------------------------------------------------
At(1001, 35, 35)
assert(NV.StartAt(1001, (m.y0 - gy) / m.size, (m.x0 - gx) / m.size))
Run(0.5)
P.lost = true
Run(0.5)
assert(S().state == "unavailable", "position unavailable: " .. S().state)
assert(NV.Target() == nil, "no arrow without a position")
P.lost = false
Run(0.5)
assert(S().state == "navigating", "back to following: " .. S().state)
-- a jump (a teleport) plans again at once
local before = NV.Diagnostics().jumps
At(1001, 5, 35)
Run(0.5)
assert(NV.Diagnostics().jumps == before + 1, "a jump plans again")
NV.Stop("test")
print("5 position ok")

---------------------------------------------------------------------------
-- 6. Another continent; an island
---------------------------------------------------------------------------
At(1001, 35, 35)
assert(NV.StartAt(2002, 0.5, 0.5, "Far away"))
Run(0.5)
assert(S().state == "noroute" and S().reason == "other-continent", "another continent: " .. tostring(S().reason))
assert(NV.Target() == nil and not S().fallback, "no bearing across continents")
NV.Stop("test")
At(1003, 20, 30)
local ix, iy = W(1003, 20, 8)
local m3 = MAPS[1003]
assert(NV.StartAt(1003, (m3.y0 - iy) / m3.size, (m3.x0 - ix) / m3.size))
Run(0.5)
assert(S().state == "noroute" and S().reason == "unreachable", "an island: " .. tostring(S().reason))
local tx, ty, kind = NV.Target()
assert(kind == "direct" and S().fallback, "a direct bearing is offered, as one")
assert(select(2, NF.Words(S())):find("No walking route"), "and the frame says there is no route")
assert(select(3, NF.Words(S())):find("direct bearing, not a route"), "the straight line is labelled")
-- it tries again later, not every update
local p0 = NV.Diagnostics().plans
Run(3)
assert(NV.Diagnostics().plans == p0, "no retry before the wait")
NV.Stop("test")
print("6 no route ok")

---------------------------------------------------------------------------
-- 7. A newer destination replaces a search still running
---------------------------------------------------------------------------
At(1001, 35, 35)
assert(NV.StartAt(1001, 0.9, 0.5))                -- a first destination
local bx, by = W(1001, 5, 35)
assert(NV.StartAt(1001, (m.y0 - by) / m.size, (m.x0 - bx) / m.size, "Second"))   -- before any step ran
Run(0.5)
s = S()
assert(s.dest.name == "Second" and s.state == "navigating", "the second destination is followed")
assert(math.abs(s.route.goalX - bx) < 1 and math.abs(s.route.goalY - by) < 1, "its route leads to the second, not the first")
print("7 superseded ok")

---------------------------------------------------------------------------
-- 8. Stop, the switch, cleanup
---------------------------------------------------------------------------
NV.Stop("stopped")
assert(not NV.Active() and S().state == "idle", "stopped")
local d = NV.Diagnostics()
assert(not d.driver and d.tickers == 0 and d.data.decodedTiles == 0, "nothing left running or decoded")
At(1001, 35, 35)
assert(NV.StartAt(1001, (m.y0 - gy) / m.size, (m.x0 - gx) / m.size))
Run(0.5)
R:SetEnabled("navigation", false)
assert(not NV.Active() and not NV.Diagnostics().driver, "turning navigation off ends it")
R:SetEnabled("navigation", true)
assert(not NV.Active(), "turning it on again starts nothing")
print("8 cleanup ok")

---------------------------------------------------------------------------
-- 9. The client's world frame
---------------------------------------------------------------------------
-- Nav.lua remembers its check per session; a fresh client shows each case.
local function FreshAxis()
  local chunk = assert(loadfile(ROOT .. "nav/Nav.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
  return c.TwichUI.Nav
end
SWAP = true
local NV2 = FreshAxis()
local dd = NV2.Destination(1001, 0.25, 0.75)
local ex, ey = W(1001, 10, 30)
assert(dd and math.abs(dd.wx - ex) < 0.01 and math.abs(dd.wy - ey) < 0.01, "a client giving (west, north) is read the right way round")
SWAP, DIAGONAL = false, true
NV2 = FreshAxis()
local bad, badWhy = NV2.Destination(1001, 0.25, 0.75)
assert(not bad and badWhy == "axis", "an unexpected frame is refused, not guessed: " .. tostring(badWhy))
DIAGONAL = false
NV = FreshAxis()
print("9 frame ok")

---------------------------------------------------------------------------
-- 10. Geometry
---------------------------------------------------------------------------
local x1, y1, x2, y2 = NPaint.ClipBox(-0.5, 0.5, 1.5, 0.5, 0, 0, 1, 1)
assert(x1 == 0 and x2 == 1 and y1 == 0.5 and y2 == 0.5, "clipped to the map's square")
assert(NPaint.ClipBox(2, 2, 3, 3, 0, 0, 1, 1) == nil, "a segment off the map is not drawn")
x1, y1, x2, y2 = NPaint.ClipCircle(-200, 0, 200, 0, 70)
assert(math.abs(x1 + 70) < 1e-9 and math.abs(x2 - 70) < 1e-9, "clipped to the minimap's circle")
assert(NPaint.ClipCircle(100, 100, 200, 100, 70) == nil, "outside the circle: nothing")
-- a point due west of you: left on a north-up minimap; ahead (up) when you face west on a rotating one
local sx, sy = NPaint.MinimapOffset(0, 10, 0, 0, 1, nil)
assert(sx == -10 and sy == 0, "west is left")
sx, sy = NPaint.MinimapOffset(0, 10, 0, 0, 1, math.pi / 2)
assert(math.abs(sx) < 1e-9 and math.abs(sy - 10) < 1e-9, "facing west, west is up")
-- bearings: counter-clockwise from north, as GetPlayerFacing
assert(math.abs(NV.Bearing(0, 0, 10, 0)) < 1e-9, "north is 0")
assert(math.abs(NV.Bearing(0, 0, 0, 10) - math.pi / 2) < 1e-9, "west is a quarter turn counter-clockwise")
assert(NV.Compass(math.pi / 2) == "west" and NV.Compass(0) == "north", "compass words")
local ax, ay = {}, {}
local n = NPaint.Ants({ 0, 100 }, { 0, 0 }, 2, 20, 5, 100, ax, ay)
assert(n == 5 and ax[1] == 5 and ax[2] == 25, "ants every gap from the phase")
assert(NPaint.Ants({ 0, 10000 }, { 0, 0 }, 2, 1, 0, 50, ax, ay) == 50, "ants are capped")
print("10 geometry ok")

---------------------------------------------------------------------------
-- 11. Preview and words
---------------------------------------------------------------------------
At(1001, 35, 35)
assert(NV.StartAt(1001, (m.y0 - gy) / m.size, (m.x0 - gx) / m.size, "Real"))
Run(0.5)
local real = S()
NF.ShowPreview(nil)
assert(NF.PreviewShown(), "the preview shows")
assert(S().dest.name == "Real" and S().route == real.route, "the preview never touches the real destination or route")
NF.HidePreview()
assert(not NF.PreviewShown(), "and goes")
local t1, l1, m1 = NF.Words(NF.SAMPLE)
assert(t1 == "Sample destination" and l1 == "In 40 yd, turn left" and m1:find("820 yd"), "sample words")
NV.Stop("test")
print("11 preview ok")

---------------------------------------------------------------------------
-- 12. /tui nav
---------------------------------------------------------------------------
local said = {}
c.print = function(t) said[#said + 1] = tostring(t) end
R.RunCommand("nav")
assert(said[#said]:find("not navigating"), "bare: status and usage")
R.RunCommand("nav 50 50")
assert(NV.Active(), "coordinates on the current map start navigation")
R.RunCommand("nav stop")
assert(not NV.Active(), "stop")
R.RunCommand("nav banana")
assert(said[#said]:find("didn't follow"), "anything else: usage")
print("12 command ok")

print("PASSED")
