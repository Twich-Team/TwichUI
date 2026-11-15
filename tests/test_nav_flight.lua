-- Navigation's flight help (nav/Flight.lua), on stand-ins for the parts it leans on: the glow on the flight point a journey lands
-- at, in either of the game's two flight windows; the automatic flight (off by default, confirmed first, once, guarded); and
-- what happens when the client refuses it.
--   1  off by default: nothing registered, nothing glows      2  the highlight: flight map pins, taxi buttons, clearing
--   3  the automatic flight: every condition, once            4  confirmation, refusal and switching off
-- What this cannot show: whether the real client lets an addon call TakeTaxiNode (not known), how the glow looks, or the
-- flight windows' own behaviour.
local calls, listeners, timers = {}, {}, {}
local now = 100
local prefs = { highlightFlight = true, autoFlight = false, accentColor = "ff5c9491", reducedMotion = false }
local enabled, subs = true, {}
local flight, pos = nil, { true, 1, 0, 0 }
local offered = {}                       -- node -> { slot, state }
local combat, onTaxi = false, false
local taken = {}

local function Frame(o)
  o = o or {}
  o.shown, o.parent, o.children = false, nil, {}
  return setmetatable(o, { __index = function(t, k)
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetParent" then return function(s, p) s.parent = p end end
    if k == "GetParent" then return function(s) return s.parent end end
    if k == "GetWidth" then return function(s) return s.w or 0 end end
    if k == "GetFrameLevel" then return function() return 1 end end
    if k == "CreateTexture" then return function() return setmetatable({}, { __index = function() return function() end end }) end end
    if k == "CreateAnimationGroup" then return function() local g = { playing = false }
      return setmetatable(g, { __index = function(_, n)
        if n == "Play" then return function() g.playing = true end end
        if n == "Stop" then return function() g.playing = false end end
        if n == "IsPlaying" then return function() return g.playing end end
        if n == "CreateAnimation" then return function() return setmetatable({}, { __index = function() return function() end end }) end end
        return function() end end }) end end
    if k == "SetSize" then return function(s, w, h) s.sw = w end end
    return function() end
  end })
end

R_ = nil
local R = { Nav = {}, NavPrefs = {}, NavTravel = {} }
TwichUI = R
function R:On(ev, fn) listeners[ev] = fn end
function R:Off(ev, fn) if listeners[ev] == fn then listeners[ev] = nil end end
function R:OnInit(fn) R.init = fn end
R.Nav.Enabled = function() return enabled end
R.Nav.Subscribe = function(fn) subs[#subs + 1] = fn end
R.Nav.FlightNow = function() return flight end
R.Nav.PositionNow = function() return pos[1], pos[2], pos[3], pos[4] end
R.NavPrefs.Get = function(k) return prefs[k] end
R.NavPrefs.Notify = function(k) for _, f in ipairs(subs) do f("prefs", k) end end
R.NavPrefs.Rgb = function() return 0.3, 0.6, 0.6, 1 end
R.NavPrefs.ReducedMotion = function() return prefs.reducedMotion end
R.NavTravel.Offered = function(node) return offered[node] end
local function Set(k, v) prefs[k] = v for _, f in ipairs(subs) do f("prefs") end end

TwichUIDB = { ui = {} }
UIParent = Frame({ w = 1000 })
CreateFrame = function() return Frame() end
GetTime = function() return now end
InCombatLockdown = function() return combat end
UnitOnTaxi = function() return onTaxi end
TakeTaxiNode = function(slot) taken[#taken + 1] = slot end
C_Timer = {
  After = function(sec, fn) timers[#timers + 1] = { at = now + sec, fn = fn } end,
  NewTicker = function(sec, fn) local t = { sec = sec, fn = fn, live = true } t.Cancel = function() t.live = false end timers.ticker = t return t end,
}
local function Advance(sec)
  now = now + sec
  local due = {}
  for i = #timers, 1, -1 do if timers[i].at <= now then table.insert(due, 1, table.remove(timers, i)) end end
  for _, t in ipairs(due) do t.fn() end
  if timers.ticker and timers.ticker.live then timers.ticker.fn() end
end

local chunk = assert(loadfile(ROOT .. "nav/Flight.lua"))
chunk()
local FL = R.NavFlight
R.init()

local function Pin(node, shown) local p = Frame({ w = 20, taxiNodeData = { nodeID = node } }) p.shown = shown ~= false return p end

-- 1. Off until navigation is on and a choice wants it
do
  enabled = false
  Set("x")
  assert(listeners.TAXIMAP_OPENED == nil, "navigation off: no listeners")
  enabled = true
  Set("x")
  assert(listeners.TAXIMAP_OPENED and listeners.TAXIMAP_CLOSED, "navigation on: listening for the map")
  assert(listeners.ADDON_ACTION_FORBIDDEN == nil, "no refusal watch while automatic flying is off")
  assert(not FL.AutoOn() and not FL.Acknowledged(), "automatic flying is off")
  print("1 defaults ok")
end

-- 2. The highlight, on the flight map's pins and on the taxi frame's buttons
do
  flight = { node = 77, name = "Beta", index = 2, current = true, cont = 1, x = 0, y = 0 }
  offered[77] = { slot = 5, state = 1, name = "Beta" }
  local pin, other = Pin(77), Pin(78)
  FlightMapFrame = Frame({ EnumeratePinsByTemplate = function() local i = 0 local l = { other, pin } return function() i = i + 1 return l[i] end end })
  FlightMapFrame.shown = true
  listeners.TAXIMAP_OPENED(1)
  Advance(0.2)
  local diag = FL.Diagnostics()
  assert(diag.open and diag.glowShown, "the glow shows")
  assert(R.NavFlight and diag.glowed == 1, "counted")
  -- the glow sits on the right pin
  local function GlowParent() for _, f in ipairs({ pin, other }) do end end
  -- a point the map doesn't offer from here: nothing
  offered[77].state = 2
  Advance(0.6)
  assert(not FL.Diagnostics().glowShown, "not offered: no glow")
  offered[77].state = 1
  Advance(0.6)
  assert(FL.Diagnostics().glowShown, "offered again: glow back")
  -- the journey moves on: gone
  flight = nil
  Advance(0.6)
  assert(not FL.Diagnostics().glowShown, "no flight step: no glow")
  flight = { node = 77, name = "Beta", index = 2, current = true, cont = 1, x = 0, y = 0 }
  -- the old taxi frame instead of the flight map
  FlightMapFrame.shown = false
  TaxiFrame = Frame()
  TaxiFrame.shown = true
  TaxiButton5 = Frame({ w = 16 })
  TaxiButton5.shown = true
  Advance(0.6)
  assert(FL.Diagnostics().glowShown, "taxi button glows too")
  TaxiButton5.shown = false                    -- a distant point is hidden by the game: nothing to mark
  Advance(0.6)
  assert(not FL.Diagnostics().glowShown, "a hidden button: no glow")
  TaxiButton5.shown = true
  Advance(0.6)
  -- the window closes
  listeners.TAXIMAP_CLOSED()
  assert(not FL.Diagnostics().glowShown and not timers.ticker.live, "closed: glow and timer gone")
  -- the choice off
  Set("highlightFlight", false)
  assert(listeners.TAXIMAP_OPENED == nil and not FL.Diagnostics().glowShown, "highlight off and nothing else wanted: not listening")
  Set("highlightFlight", true)
  assert(listeners.TAXIMAP_OPENED, "back on")
  print("2 highlight ok")
end

-- 3. The automatic flight
do
  local function Open() listeners.TAXIMAP_OPENED(1) Advance(0.5) end
  -- chosen, not confirmed: nothing
  Set("autoFlight", true)
  assert(FL.AutoWaiting() and not FL.AutoOn(), "chosen but not confirmed")
  Open() assert(#taken == 0, "nothing flies unconfirmed")
  listeners.TAXIMAP_CLOSED()
  assert(FL.Acknowledge() and FL.Acknowledged() and FL.AutoOn(), "confirmed")
  assert(listeners.ADDON_ACTION_FORBIDDEN, "watching for a refusal now")
  -- the conditions, one at a time
  local function Expect(label, f, n)
    taken = {}
    now = now + 100
    f()
    Open()
    assert(#taken == n, label .. ": " .. #taken)
    listeners.TAXIMAP_CLOSED()
  end
  Expect("combat", function() combat = true end, 0) combat = false
  Expect("already flying", function() onTaxi = true end, 0) onTaxi = false
  Expect("the step isn't the flight yet (a walk to it)", function() flight.current = false end, 0) flight.current = true
  Expect("far from that flight master", function() pos = { true, 1, 900, 0 } end, 0) pos = { true, 1, 0, 0 }
  Expect("another continent", function() pos = { true, 2, 0, 0 } end, 0) pos = { true, 1, 0, 0 }
  Expect("not offered as reachable", function() offered[77].state = 2 end, 0) offered[77].state = 1
  Expect("position unavailable", function() pos = { false } end, 0) pos = { true, 1, 0, 0 }
  Expect("no flight in the journey", function() flight = nil end, 0)
  flight = { node = 77, name = "Beta", index = 2, current = true, cont = 1, x = 0, y = 0 }
  Expect("everything right", function() end, 1)
  assert(taken[1] == 5, "the game's slot for that point: " .. tostring(taken[1]))
  -- once: opening the map again straight away does not repeat it
  taken = {}
  Open() assert(#taken == 0, "not twice in a row")
  listeners.TAXIMAP_CLOSED()
  now = now + 60
  Open() assert(#taken == 1, "after the retry wait, again")
  listeners.TAXIMAP_CLOSED()
  assert(FL.Diagnostics().taken == 2 and FL.Diagnostics().skipped > 5, "counted")
  print("3 automatic ok")
end

-- 4. A refusal, and turning it off
do
  listeners.ADDON_ACTION_FORBIDDEN("SomeOtherAddon", "TakeTaxiNode()")
  assert(FL.AutoOn(), "another addon's refusal is not ours")
  listeners.ADDON_ACTION_FORBIDDEN("!!!TwichUI", "CreateFrame()")
  assert(FL.AutoOn(), "another function's is not ours")
  listeners.ADDON_ACTION_FORBIDDEN("!!!TwichUI", "TakeTaxiNode()")
  assert(FL.Blocked() and not FL.AutoOn(), "the client refused: automatic flying stops")
  assert(listeners.ADDON_ACTION_FORBIDDEN == nil, "and the watch ends")
  taken = {}
  now = now + 100
  listeners.TAXIMAP_OPENED(1) Advance(0.5)
  assert(#taken == 0, "nothing more is tried")
  assert(FL.Diagnostics().refused, "said in the diagnostics")
  -- navigation off: everything stops
  enabled = false
  Set("x")
  assert(listeners.TAXIMAP_OPENED == nil and not FL.Diagnostics().open, "navigation off: listeners gone")
  print("4 refusal ok")
end

print("PASSED")
