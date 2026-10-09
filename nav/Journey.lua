-- TwichUI: navigation, the journey
-- One route at a time, to the player's own map pin (the one Blizzard's world map sets with Ctrl-click).
-- This file decides what the route is and how far along it you are; nav/MapTrail.lua draws it on the
-- world map and nav/Guide.lua shows the next step. It suggests only: nothing here moves you, casts a
-- spell, talks to a flight master or takes a flight.
--
-- Following a route:
--   * A walking step ends when you are within ARRIVE yards of where it leads.
--   * A flight step starts when the game says you are on a flight path (UnitOnTaxi) and ends when you
--     land: near the planned flight point it goes on; anywhere else the route is planned again from there.
--   * While walking it is planned again every REPLAN_EVERY seconds, and the new route is taken only when
--     it is clearly quicker, so the steps don't flicker. Recalculate plans again at once.
--   * Inside an instance, or wherever the game gives no position, the route waits. Leaving the continent
--     ends it, since nothing here plans across one yet.
-- A route lasts until it is finished or stopped, or until a reload: nothing about it is saved.

local R = TwichUI
local J = {}
R.Nav = J

J.ARRIVE = 20              -- yards
J.TICK = 0.5               -- seconds between looks at where you are, while a route is active
J.REPLAN_EVERY = 10        -- seconds
J.REPLAN_GAIN, J.REPLAN_MIN = 0.15, 15   -- a new route is taken when it is 15% and 15 seconds quicker
J.LEAVE_FLIGHT_MASTER = 250   -- yards: walking this far from the flight point a flight was to start from
local DEFAULT_RUN = 7      -- yards a second, used only until the game reports a run speed

local journey              -- { goal, plan, index, flying, flyStart, plannedAt, status }
local ticker
local listeners = {}
local counts, kinds = {}, 0   -- reason code -> times, for the troubleshooting report (a fixed vocabulary)
local lastRun = DEFAULT_RUN
local pinProblem           -- how reading the last map pin went, when it needed help or failed (a code)
local plans = 0

local function W() return R.NavWorld end

local function Count(code)
    if counts[code] then counts[code] = counts[code] + 1
    elseif kinds < 32 then counts[code], kinds = 1, kinds + 1 end
end

-- fn(event, reason): event is "started", "leg", "replanned", "status", "tick" or "ended".
function J.OnChange(fn) listeners[#listeners + 1] = fn end
local function Changed(event, reason)
    for i = 1, #listeners do
        local ok, err = pcall(listeners[i], event, reason)
        if not ok and R.Fault then R.Fault("navigation", err) end
    end
end

---------------------------------------------------------------------------
-- Words. One place, so the menu, the strip and the map say the same thing.
---------------------------------------------------------------------------
J.MESSAGES = {
    off = "Navigation is turned off. Turn it on in /tui options, under Navigation.",
    ["no-pin"] = "Place a map pin first: Ctrl-click the world map where you want to go.",
    ["bad-pin"] = "That map pin can't be placed in the world, so no route can be planned to it.",
    instance = "Routes aren't planned inside dungeons, raids, battlegrounds or arenas.",
    ["no-position"] = "The game isn't giving your position here, so no route can be planned.",
    ["other-continent"] = "That pin is on another continent. Routes are planned on your current continent only: boats, zeppelins and portals aren't supported yet.",
    ["no-route"] = "No route could be planned from here.",
    ["left-continent"] = "You've left the continent this route was planned on, so it has ended.",
    arrived = "You've arrived.",
}
-- Said with a route planned before this character has opened a flight master's map on the continent.
J.FLIGHTS_UNKNOWN = "No flights yet: open any flight master's map on this continent once, so TwichUI can see which flight points this character has."

function J.Duration(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds < 60 then return ("%d s"):format(seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 10 then
        local rest = seconds - minutes * 60
        return rest > 0 and ("%d min %d s"):format(minutes, rest) or ("%d min"):format(minutes)
    end
    minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return ("%d min"):format(minutes) end
    return ("%d h %d min"):format(math.floor(minutes / 60), minutes % 60)
end

local function PlaceName(node) return node and node.name or "a flight point" end

local function GoalName(goal)
    if goal and goal.zone then return "your map pin in " .. goal.zone end
    return "your map pin"
end

-- What to do on a step: "Walk to the flight master at Sentinel Hill, Westfall".
function J.Instruction(leg, goal)
    if leg.mode == "flight" then return "Fly to " .. PlaceName(leg.toNode) end
    if leg.toNode then return "Walk to the flight master at " .. PlaceName(leg.toNode) end
    return "Walk to " .. GoalName(goal)
end

-- How sure a step's time is, after the time itself.
function J.TimeNote(leg, seconds, speedLearned)
    local time = J.Duration(seconds or leg.seconds)
    if leg.mode == "walk" then return "at least " .. time .. " (direct line; terrain not considered)" end
    if leg.learned then return "about " .. time .. " (from your earlier flight)" end
    if not leg.confirmed then return "about " .. time .. " (rough: route not yet seen at a flight master)" end
    if not speedLearned then return "about " .. time .. " (rough: assumed flight speed until you have flown once)" end
    return "about " .. time .. " (rough: from your usual flight speed)"
end

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------
local function RunSpeed()
    if GetUnitSpeed then
        local _, run = GetUnitSpeed("player")
        run = W().Plain(run)
        if run and run > 0 then lastRun = run end
    end
    return lastRun
end

-- A route from here to the goal, or nil.
local function PlanFrom(x, y, map, goal)
    local F, NP = R.NavFlights, R.NavPlanner
    local ctx = F.Prepare(W().PlayerContinent())
    local nodes = ctx.usable
    for _, node in ipairs(nodes) do
        if node.map ~= map then   -- not this continent after all: keep only the ones that are
            local same = {}
            for _, n in ipairs(nodes) do if n.map == map then same[#same + 1] = n end end
            nodes = same
            break
        end
    end
    plans = plans + 1
    local plan = NP.Plan({
        fromX = x, fromY = y, toX = goal.x, toY = goal.y, runSpeed = RunSpeed(), nodes = nodes,
        flightCost = function(a, b) return F.Cost(ctx, a, b) end,
        flightDetail = function(a, b) return F.Detail(ctx, a, b) end,
    })
    if plan then plan.speedLearned, plan.runSpeed, plan.flightsUnknown = ctx.speedLearned, RunSpeed(), ctx.noneKnown end
    return plan
end

-- The player's map pin as a goal, or nil and a reason.
function J.PinGoal()
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) or not C_Map.HasUserWaypoint() then return nil, "no-pin" end
    local point = C_Map.GetUserWaypoint()
    local mx, my = W().XY(type(point) == "table" and point.position)
    if not mx then
        pinProblem = "pin-unreadable"
        return nil, "bad-pin"
    end
    local goal = W().FromMap(point.uiMapID, mx, my)
    if not goal then
        pinProblem = W().lastConversion or "not-in-world"
        return nil, "bad-pin"
    end
    pinProblem = W().lastConversion   -- "via-continent" when the pin's own map would not convert
    goal.zone = W().ZoneName(goal.map, goal.x, goal.y)
    return goal
end

-- Whether a route to goal can be planned now: x, y, map of the player, or nil and a reason.
local function Ready(goal)
    if not R:Enabled("navigation") then return nil, "off" end
    if W().InInstance() then return nil, "instance" end
    local x, y, map = W().Here()
    if not x then return nil, "no-position" end
    if goal.map ~= map then return nil, "other-continent" end
    return x, y, map
end

-- The route to the map pin, without starting it (the menu's tooltip): plan, goal, or nil and a reason.
function J.Preview()
    local goal, why = J.PinGoal()
    if not goal then return nil, why end
    local x, y, map = Ready(goal)
    if not x then return nil, y end
    local plan = PlanFrom(x, y, map, goal)
    if not plan then return nil, "no-route" end
    return plan, goal
end

---------------------------------------------------------------------------
-- Following
---------------------------------------------------------------------------
local Tick

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

local function Finish(reason)
    local j = journey
    if not j then return end
    journey = nil
    StopTicker()
    Count(reason)
    Changed("ended", reason)
end

local function Adopt(j, plan, reason)
    j.plan, j.index, j.flying, j.flyStart, j.plannedAt = plan, 1, false, nil, GetTime()
    Count(reason)
    Changed("replanned", reason)
end

local function Replan(j, x, y, map, reason)
    local plan = PlanFrom(x, y, map, j.goal)
    if plan then Adopt(j, plan, reason) else Finish("no-route") end
end

-- Seconds still to go: what is left of this step from where you are, and every later step.
local function Remaining(j, x, y)
    local legs = j.plan.legs
    local leg = legs[j.index]
    local total
    if leg.mode == "walk" then
        total = W().Distance(x, y, leg.toX, leg.toY) / RunSpeed()
    elseif j.flying and j.flyStart then
        total = math.max(0, leg.seconds - R.NavPlanner.BOARDING - (GetTime() - j.flyStart))
    else
        total = leg.seconds
    end
    for i = j.index + 1, #legs do total = total + legs[i].seconds end
    return total
end

local function MaybeReplan(j, x, y, map)
    j.plannedAt = GetTime()
    local plan = PlanFrom(x, y, map, j.goal)
    if not plan then return end
    local now = Remaining(j, x, y)
    if plan.seconds < now * (1 - J.REPLAN_GAIN) and now - plan.seconds >= J.REPLAN_MIN then Adopt(j, plan, "replan-quicker") end
end

local function Advance(j)
    j.index, j.flying, j.flyStart = j.index + 1, false, nil
    if j.index > #j.plan.legs then Finish("arrived") else Changed("leg") end
end

local function SetStatus(j, status)
    if j.status ~= status then
        j.status = status
        Changed("status", status)
    end
end

Tick = function()
    local j = journey
    if not j then StopTicker() return end
    if W().InInstance() then SetStatus(j, "instance") return end
    local x, y, map = W().Here()
    if not x then SetStatus(j, "no-position") return end
    if map ~= j.goal.map then Finish("left-continent") return end
    SetStatus(j, nil)
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player") or false
    local leg = j.plan.legs[j.index]
    if not onTaxi and W().Distance(x, y, j.goal.x, j.goal.y) <= J.ARRIVE then Finish("arrived") return end
    if leg.mode == "walk" then
        local nextLeg = j.plan.legs[j.index + 1]
        if onTaxi and nextLeg and nextLeg.mode == "flight" then
            j.index, j.flying, j.flyStart = j.index + 1, true, GetTime()
            Changed("leg")
            return
        end
        if W().Distance(x, y, leg.toX, leg.toY) <= J.ARRIVE then Advance(j) return end
        if not onTaxi and GetTime() - j.plannedAt >= J.REPLAN_EVERY then MaybeReplan(j, x, y, map) end
    elseif onTaxi then
        if not j.flying then
            j.flying, j.flyStart = true, GetTime()
            Changed("leg")
        end
    elseif j.flying then
        if W().Distance(x, y, leg.toX, leg.toY) <= R.NavFlights.LANDED_NEAR then Advance(j)
        else Replan(j, x, y, map, "landed-elsewhere") end
        return
    elseif W().Distance(x, y, leg.fromX, leg.fromY) > J.LEAVE_FLIGHT_MASTER then
        Replan(j, x, y, map, "left-flight-master")
        return
    end
    if journey == j then Changed("tick") end
end

local function Begin(goal, plan)
    StopTicker()
    journey = { goal = goal, plan = plan, index = 1, flying = false, plannedAt = GetTime() }
    Count("started")
    ticker = C_Timer.NewTicker(J.TICK, Tick)
    Changed("started")
    Tick()
end

-- Starts a route to the map pin. Says why in chat when it can't (the player just asked for it).
-- Returns true, or false and a reason.
function J.StartToPin()
    local plan, goal = J.Preview()   -- on failure the second value is the reason
    if not plan then
        local why = goal
        Count(why)
        R.Print("%s", J.MESSAGES[why] or J.MESSAGES["no-route"])
        return false, why
    end
    if journey then Finish("replaced") end
    Begin(goal, plan)
    return true
end

-- Ends the route at the player's request.
function J.Stop()
    if journey then Finish("cancelled") end
end

-- Plans again from where you are now, at the player's request.
function J.Recalculate()
    local j = journey
    if not j then return false end
    local x, y, map = Ready(j.goal)
    if not x then
        R.Print("%s", J.MESSAGES[y] or J.MESSAGES["no-route"])
        return false, y
    end
    Replan(j, x, y, map, "recalculated")
    return true
end

-- The active route, read only: { goal, plan, index, flying, status }, or nil.
function J.Current() return journey end

-- Seconds still to go on the active route from where you are, or nil.
function J.RemainingNow()
    local j = journey
    if not j then return nil end
    local x, y = W().Here()
    if not x then return nil end
    return Remaining(j, x, y)
end

-- Seconds left on the current step from where you are, or nil.
function J.StepRemainingNow()
    local j = journey
    if not j then return nil end
    local leg = j.plan.legs[j.index]
    local x, y = W().Here()
    if leg.mode == "walk" then
        if not x then return nil end
        return W().Distance(x, y, leg.toX, leg.toY) / RunSpeed()
    elseif j.flying and j.flyStart then
        return math.max(0, leg.seconds - R.NavPlanner.BOARDING - (GetTime() - j.flyStart))
    end
    return leg.seconds
end

-- Turning navigation off ends any route. Safe to call any number of times.
function J.Refresh()
    if not R:Enabled("navigation") then Finish("module-off") end
    if R.NavFlights then R.NavFlights.Refresh() end
    if R.NavMap then R.NavMap.Refresh() end
    if R.NavGuide then R.NavGuide.Refresh() end
end

-- Codes and counts only, for the troubleshooting report: no places, names or coordinates.
function J.Snapshot()
    local j = journey
    local copy = {}
    for k, v in pairs(counts) do copy[k] = v end
    local leg = j and j.plan.legs[j.index]
    return {
        enabled = R:Enabled("navigation"), arrow = R:Enabled("navigationArrow"), active = j ~= nil,
        legs = j and #j.plan.legs or 0, index = j and j.index or 0, mode = leg and leg.mode or "none",
        flying = j and j.flying or false, status = j and j.status or "none", ticking = ticker ~= nil,
        plans = plans, counts = copy, pinProblem = pinProblem or "none",
    }
end

R:OnInit(J.Refresh)
