-- RestedXP destination waypoint (qol/GuideWaypoint.lua): off by default and silent when off; works without
-- RestedXP; follows RestedXP's arrow (not the first coordinate of a step); a routing point stands for the
-- step's next marked destination; nothing to mark clears only its own point; the player's waypoint is never
-- moved or cleared; nothing is written in combat; turning it off clears its own point; after a reload its
-- own point is recognised; repeated RestedXP updates write nothing.
-- RestedXP is simulated from the source of v4.11.22 (map.lua, functions.lua): the same field names and the
-- same hooked functions, not the game. The game's single waypoint slot is a table that outlives a client,
-- so a reload can be simulated.
dofile(TESTS .. "harness.lua")

local SLOT = { point = nil }   -- the game's user waypoint, shared by everyone (and kept over a reload)

local function Boot(opts)
  opts = opts or {}
  local addons = { "!!!TwichUI" }
  for _, a in ipairs(opts.addons or {}) do addons[#addons + 1] = a end
  local c = MakeClient("Rich", addons)
  c.COMBAT = false
  c.InCombatLockdown = function() return c.COMBAT end
  c.hookCount = 0
  c.hooksecurefunc = function(tbl, name, fn)
    local orig = assert(tbl[name], "hooking something that is not there: " .. tostring(name))
    c.hookCount = c.hookCount + 1
    tbl[name] = function(...)
      local r = { orig(...) }
      fn(...)
      return unpack(r)
    end
  end
  c.writes, c.clears, c.tracked = 0, 0, false
  c.REFUSED = {}
  local function Copy(p) return p and { uiMapID = p.uiMapID, position = { x = p.position.x, y = p.position.y } } end
  c.UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, position = { x = x, y = y } } end }
  c.C_Map = {
    CanSetUserWaypointOnMap = function(map) return not c.REFUSED[map] end,
    SetUserWaypoint = function(point)
      if c.REFUSED[point.uiMapID] then return false end
      c.writes = c.writes + 1
      SLOT.point = Copy(point)
      c.FireEvent("USER_WAYPOINT_UPDATED")   -- synchronous, as documented
      return true
    end,
    ClearUserWaypoint = function()
      c.clears = c.clears + 1
      SLOT.point = nil
      c.FireEvent("USER_WAYPOINT_UPDATED")
    end,
    HasUserWaypoint = function() return SLOT.point ~= nil end,
    GetUserWaypoint = function() return Copy(SLOT.point) end,
    GetUserWaypointPositionForMap = function(map)
      local p = SLOT.point
      if p and p.uiMapID == map then return { x = p.position.x, y = p.position.y } end
    end,
  }
  c.C_SuperTrack = {
    SetSuperTrackedUserWaypoint = function(v) c.tracked = v end,
    IsSuperTrackingUserWaypoint = function() return c.tracked end,
  }
  c.TwichUIDB = opts.db or { modules = {} }
  for _, f in ipairs({ "qol/QoL.lua", "qol/GuideWaypoint.lua" }) do
    local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
  end
  return c
end

local function Start(c)
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_LOGIN")
  FlushTimers()
  return c.TwichUI
end

-- The player, or another addon, sets the waypoint.
local function PlayerSets(c, map, x, y)
  SLOT.point = { uiMapID = map, position = { x = x, y = y } }
  c.FireEvent("USER_WAYPOINT_UPDATED")
end
local function PlayerClears(c)
  SLOT.point = nil
  c.FireEvent("USER_WAYPOINT_UPDATED")
end

---------------------------------------------------------------------------
-- RestedXP, as far as this can see it.
---------------------------------------------------------------------------
local function MakeRestedXP(c, opts)
  opts = opts or {}
  local rxp = { arrowFrame = {}, activeWaypoints = {}, settings = { profile = {} }, hideArrow = false }
  function rxp.UpdateMap() end
  function rxp.UpdateGotoSteps() end
  if not opts.noResetArrow then function rxp.ResetArrowPosition() end end
  if opts.broken then rxp.UpdateGotoSteps = nil end
  local ace = c.LibStub:NewLibrary("AceAddon-3.0", 1)
  function ace:GetAddon(name) if name == "RXPGuides" then return rxp end end
  c.LOADED["RXPGuides"] = true
  return rxp
end

local function RestedXPLoads(c)
  c.FireEvent("ADDON_LOADED", "RXPGuides")
  FlushTimers()
end

-- A step whose elements are given in guide order. Elements: { zone, x, y, [field = value ...] }.
local function Step(list)
  local step = { active = true, elements = {} }
  for i, spec in ipairs(list) do
    local e = { zone = spec[1], x = spec[2], y = spec[3], arrow = true, parent = true, textOnly = true, step = step }
    for k, v in pairs(spec) do if type(k) == "string" then e[k] = v end end
    step.elements[i] = e
  end
  return step
end

-- RestedXP's arrow now points at e (as updateArrowData leaves it), then one of the hooked updates runs.
local function Point(rxp, e, how)
  rxp.currentGuide = rxp.currentGuide or { steps = {} }
  rxp.arrowFrame.element = e
  rxp.activeWaypoints = e and { e } or {}
  if how == "map" then rxp.UpdateMap(true) else rxp.UpdateGotoSteps() end
end

local function At(map, x, y)
  local p = SLOT.point
  return p ~= nil and p.uiMapID == map and math.abs(p.position.x - x) < 1e-9 and math.abs(p.position.y - y) < 1e-9
end

---------------------------------------------------------------------------
-- Off by default: nothing hooked, nothing written.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" } })
  local R = Start(c)
  assert(R.DEFAULT_MODULES.qolGuideWaypoint == false and R:Enabled("qolGuideWaypoint") == false, "opt-in")
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  assert(c.hookCount == 0, "nothing hooked while off")
  Point(rxp, Step({ { 1429, 40, 60 } }).elements[1])
  assert(SLOT.point == nil and c.writes == 0, "nothing written")
  assert(R.QoLGuideWaypoint.Status() == "off")
end

---------------------------------------------------------------------------
-- On, RestedXP not installed: neutral.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  assert(R.QoLGuideWaypoint.Status() == "restedxp-missing", R.QoLGuideWaypoint.Status())
  assert(c.hookCount == 0 and c.writes == 0)
end

---------------------------------------------------------------------------
-- A RestedXP without what this needs: nothing hooked, says so.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  MakeRestedXP(c, { broken = true })
  RestedXPLoads(c)
  assert(c.hookCount == 0)
  assert(R.QoLGuideWaypoint.Status() == "unsupported", R.QoLGuideWaypoint.Status())
end

---------------------------------------------------------------------------
-- Following the arrow: placed, tracked, moved on, remembered; repeated updates write nothing.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  local W = R.QoLGuideWaypoint
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  assert(c.hookCount == 3, "UpdateMap, UpdateGotoSteps and ResetArrowPosition, once")
  assert(W.Status() == "no-guide", W.Status())

  -- a step with two places: the arrow (not the first coordinate) decides
  local step = Step({ { 1429, 10, 20 }, { 1429, 48.5, 37.25 } })
  Point(rxp, step.elements[2], "map")
  assert(At(1429, 0.485, 0.3725), "on the arrow's destination, in map units")
  assert(c.tracked == true, "made the tracked one")
  assert(W.Status() == "shown")
  local saved = c.TwichUIDB.ui.guideWaypoint["Player-1-Rich"]
  assert(saved and saved.map == 1429 and saved.x == 0.485, "remembered for this character")

  -- RestedXP updates about three times a second: nothing is written while nothing changes
  local writes = c.writes
  for _ = 1, 200 do rxp.UpdateGotoSteps() end
  rxp.UpdateMap(false)
  rxp.ResetArrowPosition()
  assert(c.writes == writes, "no writes without a change")

  -- the tracked marker isn't taken back between destinations
  c.tracked = false
  for _ = 1, 10 do rxp.UpdateGotoSteps() end
  assert(c.tracked == false, "a quest tracked meanwhile keeps the marker")

  -- the next destination: moved, tracked again
  local nextStep = Step({ { 1426, 30, 70 } })
  step.active = false
  Point(rxp, nextStep.elements[1])
  assert(At(1426, 0.3, 0.7) and c.tracked == true and c.writes == writes + 1)

  -- the same element moved by RestedXP (a recalculated point): followed
  nextStep.elements[1].x = 31
  rxp.UpdateGotoSteps()
  assert(At(1426, 0.31, 0.7))

  -- RestedXP's arrow left pointing at something done: cleared, and only ours
  nextStep.elements[1].skip = true
  rxp.UpdateGotoSteps()
  assert(SLOT.point == nil and W.Status() == "no-destination", W.Status())
  assert(c.TwichUIDB.ui.guideWaypoint["Player-1-Rich"] == nil, "forgotten when cleared")
end

---------------------------------------------------------------------------
-- What RestedXP's arrow can point at that isn't a destination.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  local W = R.QoLGuideWaypoint
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)

  -- a routing point (".goto ...,10,0") before the destination: the destination is marked
  local routed = Step({ { 1429, 50, 50, hidePin = true, radius = 10 }, { 1429, 52, 41 } })
  Point(rxp, routed.elements[1])
  assert(At(1429, 0.52, 0.41), "the routing point stands for where it leads")
  -- reaching the routing point moves the arrow on; the waypoint is already there
  local writes = c.writes
  routed.elements[1].skip = true
  Point(rxp, routed.elements[2])
  assert(c.writes == writes, "no second write for the same place")

  -- a kill area: only arrow-only loop points and pins without an arrow: nothing to mark
  local loop = Step({
    { 1429, 49, 38, arrow = false }, { 1429, 45, 38, arrow = false },
    { 1429, 49, 38, hidePin = true, lowPrio = "0" }, { 1429, 48, 37, hidePin = true, lowPrio = "0" },
  })
  routed.active = false
  Point(rxp, loop.elements[3])
  assert(SLOT.point == nil and W.Status() == "route", W.Status())

  -- something RestedXP made up (corpse, spirit healer): nothing
  Point(rxp, Step({ { 1429, 40, 60 } }).elements[1])
  assert(SLOT.point ~= nil)
  Point(rxp, { generated = 1, wx = 1, wy = 2, instance = 0, title = "Corpse" })
  assert(SLOT.point == nil and W.Status() == "no-destination")

  -- an objective done: its goto is not a destination any more
  local parent = { completed = true }
  Point(rxp, Step({ { 1429, 40, 60, parent = parent } }).elements[1])
  assert(SLOT.point == nil)

  -- in an instance RestedXP hides its arrow: nothing; on another continent the destination stands
  local far = Step({ { 1426, 20, 20 } }).elements[1]
  rxp.hideArrow = true
  Point(rxp, far)
  assert(SLOT.point == nil)
  rxp.arrowFrame.wrongContinent = true
  rxp.UpdateGotoSteps()
  assert(At(1426, 0.2, 0.2), "another continent: still marked")
  rxp.hideArrow, rxp.arrowFrame.wrongContinent = false, false

  -- RestedXP's own map pins off (no active waypoints): nothing to follow
  rxp.activeWaypoints = {}
  rxp.UpdateGotoSteps()
  assert(SLOT.point == nil)

  -- no guide, or RestedXP hidden by the player
  Point(rxp, far)
  assert(SLOT.point ~= nil)
  rxp.currentGuide = { empty = true }
  rxp.UpdateGotoSteps()
  assert(SLOT.point == nil and W.Status() == "no-guide")
  rxp.currentGuide = { steps = {} }
  rxp.settings.profile.showEnabled = false
  rxp.UpdateGotoSteps()
  assert(SLOT.point == nil and W.Status() == "no-guide")
  rxp.settings.profile.showEnabled = true

  -- a map the game won't put a waypoint on
  c.REFUSED[947] = true
  Point(rxp, Step({ { 947, 10, 10 } }).elements[1])
  assert(SLOT.point == nil and W.Status() == "map-refused")
end

---------------------------------------------------------------------------
-- The player's waypoint is never moved or cleared.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  local W = R.QoLGuideWaypoint
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)

  -- already there before a destination
  PlayerSets(c, 1453, 0.5, 0.5)
  Point(rxp, Step({ { 1429, 40, 60 } }).elements[1])
  assert(At(1453, 0.5, 0.5) and W.Status() == "yours", W.Status())
  Point(rxp, Step({ { 1429, 41, 60 } }).elements[1])
  assert(At(1453, 0.5, 0.5), "a new destination still leaves it")
  -- nothing to mark: still left
  Point(rxp, nil)
  assert(At(1453, 0.5, 0.5))
  -- the player clears it: the next destination is marked
  PlayerClears(c)
  Point(rxp, Step({ { 1429, 42, 60 } }).elements[1])
  assert(At(1429, 0.42, 0.6) and W.Status() == "shown")

  -- the player replaces ours: kept, forgotten, never reclaimed
  PlayerSets(c, 1453, 0.25, 0.75)
  assert(W.Status() == "yours")
  assert(c.TwichUIDB.ui.guideWaypoint["Player-1-Rich"] == nil)
  Point(rxp, Step({ { 1429, 43, 60 } }).elements[1])
  Point(rxp, nil)
  assert(At(1453, 0.25, 0.75), "neither moved nor cleared")

  -- the player clears ours: it stays cleared for this destination, the next one is marked
  PlayerClears(c)
  local here = Step({ { 1429, 44, 60 } }).elements[1]
  Point(rxp, here)
  assert(At(1429, 0.44, 0.6))
  PlayerClears(c)
  assert(W.Status() == "cleared")
  for _ = 1, 20 do rxp.UpdateGotoSteps() end
  assert(SLOT.point == nil, "not put back for the same destination")
  Point(rxp, Step({ { 1429, 45, 60 } }).elements[1])
  assert(At(1429, 0.45, 0.6), "the next destination is marked")

  -- turning it off while the player's waypoint is in the slot: left alone
  PlayerSets(c, 1453, 0.1, 0.1)
  c.TwichUIDB.modules.qolGuideWaypoint = false
  R.QoL.Apply(W.feature)
  assert(At(1453, 0.1, 0.1))
end

---------------------------------------------------------------------------
-- Combat: nothing written until it ends; turned off in combat, cleared when it ends.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  local W = R.QoLGuideWaypoint
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  Point(rxp, Step({ { 1429, 40, 60 } }).elements[1])
  local writes = c.writes
  c.COMBAT = true
  Point(rxp, Step({ { 1429, 50, 60 } }).elements[1])
  for _ = 1, 20 do rxp.UpdateGotoSteps() end
  assert(c.writes == writes and At(1429, 0.4, 0.6), "held in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(At(1429, 0.5, 0.6) and c.writes == writes + 1, "written once combat ends")

  c.COMBAT = true
  c.TwichUIDB.modules.qolGuideWaypoint = false
  R.QoL.Apply(W.feature)
  assert(At(1429, 0.5, 0.6), "not cleared in combat")
  c.COMBAT = false
  c.FireEvent("PLAYER_REGEN_ENABLED")
  assert(SLOT.point == nil, "cleared when combat ends")
end

---------------------------------------------------------------------------
-- Off and on: off clears ours and stops following; on marks the destination at once.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local R = Start(c)
  local W = R.QoLGuideWaypoint
  local rxp = MakeRestedXP(c)
  RestedXPLoads(c)
  local e = Step({ { 1429, 40, 60 } }).elements[1]
  Point(rxp, e)
  assert(SLOT.point ~= nil)
  c.TwichUIDB.modules.qolGuideWaypoint = false
  R.QoL.Apply(W.feature)
  assert(SLOT.point == nil and W.Status() == "off")
  assert(c.TwichUIDB.ui.guideWaypoint["Player-1-Rich"] == nil)
  Point(rxp, Step({ { 1429, 41, 60 } }).elements[1])
  assert(SLOT.point == nil, "RestedXP's updates do nothing while off")
  local hooks = c.hookCount
  c.TwichUIDB.modules.qolGuideWaypoint = true
  R.QoL.Apply(W.feature)
  FlushTimers()
  assert(At(1429, 0.41, 0.6), "on again: marked at once")
  assert(c.hookCount == hooks, "no second set of hooks")
end

---------------------------------------------------------------------------
-- A reload: our point from before is recognised as ours (moved or cleared), not taken for the player's.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local db = { modules = { qolGuideWaypoint = true } }
  local c1 = Boot({ addons = { "RXPGuides" }, db = db })
  Start(c1)
  local rxp1 = MakeRestedXP(c1)
  RestedXPLoads(c1)
  Point(rxp1, Step({ { 1429, 40, 60 } }).elements[1])
  assert(At(1429, 0.4, 0.6))

  -- the same saved variables, a new session; the game kept the waypoint
  local c2 = Boot({ addons = { "RXPGuides" }, db = db })
  local R2 = Start(c2)
  local rxp2 = MakeRestedXP(c2)
  RestedXPLoads(c2)
  Point(rxp2, Step({ { 1429, 47, 60 } }).elements[1])
  assert(At(1429, 0.47, 0.6), "moved, not left as the player's")
  assert(R2.QoLGuideWaypoint.Status() == "shown")

  -- and with no destination after the reload, it is cleared
  local c3 = Boot({ addons = { "RXPGuides" }, db = db })
  Start(c3)
  local rxp3 = MakeRestedXP(c3)
  rxp3.currentGuide = { empty = true }
  RestedXPLoads(c3)
  rxp3.UpdateMap(true)
  assert(SLOT.point == nil, "our leftover from before the reload is cleared")
end

---------------------------------------------------------------------------
-- RestedXP loaded first (another addon made it load early): attached at login.
---------------------------------------------------------------------------
do
  SLOT.point = nil
  local c = Boot({ addons = { "RXPGuides" }, db = { modules = { qolGuideWaypoint = true } } })
  local rxp = MakeRestedXP(c)
  local R = Start(c)
  assert(c.hookCount == 3, "hooked at login")
  Point(rxp, Step({ { 1429, 40, 60 } }).elements[1])
  assert(At(1429, 0.4, 0.6) and R.QoLGuideWaypoint.Status() == "shown")
end

print("GUIDE WAYPOINT TESTS PASSED")
