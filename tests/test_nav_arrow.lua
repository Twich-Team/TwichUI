-- Arrow rotation on mocked frames: route easing, shortest-angle wrap, immediate facing and lifecycle reset.
local frames, ticker = {}, nil
local function Frame()
  local f = { shown = false }
  return setmetatable(f, { __index = function(_, key)
    if key == "Show" then return function(s) s.shown = true end end
    if key == "Hide" then return function(s) s.shown = false end end
    if key == "IsShown" then return function(s) return s.shown end end
    if key == "GetScale" then return function() return 1 end end
    if key == "CreateTexture" or key == "CreateFontString" then return Frame end
    if key == "SetRotation" then return function(s, angle) s.angle = angle end end
    if key:match("^[A-Z]") then return function() end end
  end })
end
CreateFrame = function() local f = Frame(); frames[#frames + 1] = f; return f end
UIParent = Frame()
local facing, bearing, kind, available, active = 0, 0, "route", true, true
local dest, route = {}, {}
local prefs = { arrow = true, locked = true, arrowScale = 100, textSize = 12 }
local NV = {}
TwichUI = { PATH = "", Nav = NV, NavPrefs = {
  Get = function(k) return prefs[k] end,
  Rgb = function() return 1, 1, 1 end,
  Font = function() return "font" end,
} }
NV.Enabled = function() return true end
NV.Active = function() return active end
NV.Subscribe = function() end
NV.AddTicker = function(fn) assert(not ticker); ticker = fn end
NV.RemoveTicker = function(fn) assert(ticker == fn); ticker = nil end
NV.Snapshot = function() return { dest = dest, route = route, state = "navigating" } end
NV.Target = function() if available then return math.cos(bearing) * 20, math.sin(bearing) * 20, kind end end
NV.Position = function() return true, 1, 0, 0 end
NV.Readable = function(v) return v end
NV.Bearing = function(_, _, x, y) return math.atan2(y, x) end
NV.Yards = tostring
GetPlayerFacing = function() return facing end
assert(loadfile(ROOT .. "nav/Arrow.lua"))()
local NA = TwichUI.NavArrow
local function Near(a, b) return math.abs(a - b) < 0.001 end
local function Angle() return frames[1].tex.angle end
local function Tick(dt) assert(ticker); ticker(dt or 1 / 30) end

NA.Refresh()
Tick()
assert(Near(Angle(), 0), "first target appears immediately")
bearing = math.pi / 2
Tick()
assert(Angle() > 0 and Angle() < bearing / 2, "a corner eases instead of snapping sideways")
for _ = 1, 30 do Tick() end
assert(Near(Angle(), bearing), "easing converges promptly")
local before = Angle()
facing = 0.8
Tick()
assert(math.abs((Angle() - before) + facing) < 0.001, "player facing changes remain immediate")

-- Crossing north/south's angular boundary takes the short arc, never a full spin.
facing, bearing, dest = 0, math.rad(179), {}
Tick()
assert(Near(Angle(), bearing), "new destination clears old easing")
bearing = math.rad(-179)
Tick()
assert(Angle() > math.rad(179) and Angle() < math.rad(181), "wrap follows the two-degree arc")

bearing, route = -1, {}
Tick()
assert(Near(Angle(), bearing), "a replaced route clears old easing")
available = false
Tick()
assert(not frames[1].tex.shown, "unavailable position hides the arrow")
available, bearing = true, 1
Tick()
assert(Near(Angle(), bearing), "recovered target starts fresh")
kind, bearing = "direct", -2
Tick()
assert(Near(Angle(), bearing), "direct bearing remains direct")
active = false
NA.Refresh()
assert(ticker == nil, "stopping removes the ticker")
active, kind, bearing = true, "route", 2
NA.Refresh()
Tick()
assert(Near(Angle(), bearing), "starting again has no stale bearing")
print("PASSED arrow easing (mocked frames; not real-client visual validation)")
