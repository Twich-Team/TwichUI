-- TwichUI: Navigation, the journey being followed
-- One destination at a time, chosen by the player (a pin's Navigate here, the map tool, /tui nav). A journey to it is
-- planned (nav/Journey.lua: walking, boats and zeppelins, learned flights, Mage teleports, the Hearthstone, whichever is
-- quickest by estimate; a short trip on one continent is just walked over nav/Route.lua's routes), followed as the player
-- moves, planned again when the player leaves it, and put away on arrival. It never moves the character, turns the camera,
-- casts, rides, clicks or presses anything, and nothing it receives from another player (a ping, a party pin arriving)
-- ever starts or changes it.
--
-- A journey is legs in order: "walk" (a route; the one being followed is `route`), "ferry" (a boat or zeppelin), "flight",
-- "teleport", "hearth". A walk to a place ends within a few yards of it and the next leg becomes the current one; a leg that
-- isn't a walk is words (what to do, where, what to expect) and ends when you arrive: a new plan from where you are.
--
-- States (NV.Snapshot().state):
--   "loading"        the walking maps are being loaded (they wait for combat to end: "waiting for combat")
--   "calculating"    the first plan or route is being worked out
--   "navigating"     a journey is being followed (Snapshot().legKind says which kind of leg)
--   "recalculating"  a new plan is being worked out; the old one stays drawn, marked as being replaced
--   "riding"         aboard a boat or zeppelin, or on a flight path: nothing to follow until you arrive; the plan is held and
--                    looked at again every few seconds (a flight: once you land)
--   "unavailable"    where you are can't be read (an instance, a loading screen, a map with no position)
--   "noroute"        no way there: reason "other-continent" (nothing available crosses), "no-data", "unreachable", "start-off",
--                    "goal-off", "limit", "axis". Where a direct bearing still means something (same continent) it is offered,
--                    and always labelled as one, never as a route.
--   "arrived"        within the arrival distance; shown for a moment, then navigation ends
--
-- Where you are: the map the game puts you on (C_Map.GetBestMapForUnit), your place on it (GetPlayerMapPosition) and that
-- place in continent yards (GetWorldPosFromMapPos), the same path a destination takes, read ten times a second while
-- navigating. Before the first route, NV checks that the client's world positions are in the bake's frame (x north,
-- y west) by moving a point east on your map and seeing which coordinate falls; anything else stops with "axis".
-- Facing (GetPlayerFacing) is read by the arrow only.
--
-- Progress, four times a second: a walk's corners are passed in order (a corner counts as passed when you are within
-- reach of it, or past it along the next leg and closer to that leg); never skipped because a later one is near in a
-- straight line. Off the route by more than the chosen distance for OFF_HOLD seconds (and at least REPLAN_GAP after the
-- last plan) plans again from where you are; back within 60% of it clears the count. A jump of JUMP yards (a teleport,
-- the Hearthstone, a graveyard), a change of continent, the end of a boat ride (within reach of its arrival dock), the end
-- of a flight (UnitOnTaxi turning false) or walking well away from a dock you were to board at plans again at once or
-- after the hold. A newer plan always replaces an older one (by generation); a superseded search is dropped, never
-- finished. A new journey replaces the one followed only once its first walk has a route, so nothing drawn goes missing.
--
-- Work: one driver frame whose OnUpdate exists only while a destination is set. No events are listened to while idle.
-- Saved: nothing but preferences (nav/Prefs.lua) and the Hearthstone's bind point (nav/Travel.lua). The destination ends with
-- the session.

local R = TwichUI
local ND, RT, NP = R.NavData, R.NavRoute, R.NavPrefs
local NV = {}
R.Nav = NV

local POS_EVERY, PROGRESS_EVERY = 0.1, 0.25
local SEARCH_BUDGET = 3        -- milliseconds a frame for a route search
local OFF_HOLD = 2.5           -- seconds off the route before planning again
local REPLAN_GAP = 4           -- seconds between plans for being off the route
local JUMP = 120               -- yards between two readings that count as a jump
local ARRIVED_HOLD = 4         -- seconds "Arrived" stays before navigation ends
local RETRY = { 5, 10, 20, 30 } -- seconds before trying a failed plan again (it also waits for you to move)
local NAME_MAX = 60

local sqrt, atan2, abs, floor, pi = math.sqrt, math.atan2, math.abs, math.floor, math.pi

local dest                      -- the destination (NV.Destination), or nil
local state = "idle"
local reason                    -- why, for unavailable and noroute
local route                     -- the route being followed: the current leg's, when that is a walk
local journey, leg              -- the journey being followed, and the index of its current leg
local pending                   -- a journey just planned, held until its first walk has a route
local legJob, legJobJourney, legJobIdx, legJobGen
local legStart                  -- where you were when the current leg (not a walk) became the current one
local wasTaxi = false
local J = R.NavJourney          -- nav/Journey.lua (loaded before this file)
local job, jobGen               -- the search running, and its generation
local gen = 0
local seg = 1                   -- following the leg from corner seg to corner seg + 1
local pos = { ok = false }      -- the last reading: ok, cont, x, y, map, t
local lastPlanAt, offSince, retries, retryAt = 0, nil, 0, nil
local arrivedAt
local waitCombat = false
local axis                      -- nil (not checked), "xy", "yx", or false
local prog = { toNext = 0, remaining = 0, straight = 0, instruction = "", kind = "", wet = false }
local listeners, tickers = {}, {}
local driver
local acc = { pos = 0, prog = 0 }
local posWhy                    -- why the last reading failed
local stats = { plans = 0, replansOff = 0, replansJump = 0, failures = 0, arrivals = 0, superseded = 0 }

local function Now() return GetTime() end
local function Dist(x1, y1, x2, y2) return sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) end
local function CurLeg() return journey and journey.legs[leg] or nil end

local function Readable(v)
    if type(v) ~= "number" then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end
NV.Readable = Readable

function NV.Enabled() return R:Enabled("navigation") end

---------------------------------------------------------------------------
-- Telling the views
---------------------------------------------------------------------------
function NV.Subscribe(fn) listeners[#listeners + 1] = fn end

local function Emit(event)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, event)
        if not ok then R.Fault("navigation view", err) end
    end
end

-- fn(elapsed) every frame while navigating; a view adds itself only while it is shown, and throttles itself.
function NV.AddTicker(fn)
    for _, f in ipairs(tickers) do if f == fn then return end end
    tickers[#tickers + 1] = fn
end
function NV.RemoveTicker(fn)
    for i = #tickers, 1, -1 do if tickers[i] == fn then table.remove(tickers, i) end end
end

local function SetState(s, why)
    if s == state and why == reason then return end
    state, reason = s, why
    Emit("state")
end

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
-- Which way the client's world vectors run, checked on a map: a point moved east must keep its north and lose west.
local function AxisCheck(map)
    if axis ~= nil then return axis end
    local ok, a, b = pcall(function()
        local _, w1 = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0.25, 0.5))
        local _, w2 = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(0.75, 0.5))
        return w1, w2
    end)
    if not (ok and a and b) then return nil end
    local ax, ay = a:GetXY()
    local bx, by = b:GetXY()
    ax, ay, bx, by = Readable(ax), Readable(ay), Readable(bx), Readable(by)
    if not (ax and ay and bx and by) then return nil end
    local dx, dy = bx - ax, by - ay
    local span = abs(dx) + abs(dy)
    if span <= 0 then return nil end
    if abs(dx) < span * 0.01 and dy < 0 then axis = "xy"
    elseif abs(dy) < span * 0.01 and dx < 0 then axis = "yx"
    else axis = false end
    return axis
end

-- World (continent, x north, y west) of a map point, or nil.
local function World(map, x, y)
    local ok, cont, vec = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not (ok and cont and vec) then return nil end
    local a, b = vec:GetXY()
    cont, a, b = Readable(cont), Readable(a), Readable(b)
    if not (cont and a and b) then return nil end
    local frame = AxisCheck(map)
    if frame == "xy" then return cont, a, b end
    if frame == "yx" then return cont, b, a end
    return nil, frame == false and "axis" or "no-world"
end
NV.World = World

-- Reads where you are into `pos`. Returns true, or false and why ("no-map", "no-position", "no-world", "axis").
local function ReadPosition()
    local map = Readable(C_Map.GetBestMapForUnit("player"))
    if not map then pos.ok = false return false, "no-map" end
    local ok, p = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not (ok and p) then pos.ok = false return false, "no-position" end
    local x, y = p:GetXY()
    x, y = Readable(x), Readable(y)
    if not (x and y) then pos.ok = false return false, "no-position" end
    local cont, wx, wy = World(map, x, y)
    if not cont then pos.ok = false return false, wx or "no-world" end
    pos.ok, pos.cont, pos.x, pos.y, pos.map, pos.t = true, cont, wx, wy, map, Now()
    return true
end

-- The last reading: ok, continent, x, y (a view reads this; nothing is read twice a tick).
function NV.Position() return pos.ok, pos.cont, pos.x, pos.y end

-- A reading now (the Hearthstone's bind point asks, with no navigation under way).
function NV.PositionNow()
    local ok = ReadPosition()
    return ok, pos.cont, pos.x, pos.y
end

---------------------------------------------------------------------------
-- Destinations
---------------------------------------------------------------------------
local function CleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    if #name > NAME_MAX then name = name:sub(1, NAME_MAX) end
    return name
end

-- A destination from a map point: { map, x, y (0..1), name, source, continent, wx, wy }, or nil and a reason
-- ("bad-map", "bad-coordinates", "no-world", "axis"). Plain data only.
function NV.Destination(map, x, y, name, source)
    map, x, y = Readable(map), Readable(x), Readable(y)
    if not map or map <= 0 or map % 1 ~= 0 then return nil, "bad-map" end
    if not (x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil, "bad-coordinates" end
    local cont, wx, wy = World(map, x, y)
    if not cont then return nil, wx or "no-world" end
    local label = CleanName(name)
    if not label then
        local ok, info = pcall(C_Map.GetMapInfo, map)
        local zone = ok and type(info) == "table" and CleanName(info.name) or nil
        label = ("%s %.1f, %.1f"):format(zone or "Map point", x * 100, y * 100)
    end
    return { map = map, x = x, y = y, name = label, source = source or "map", continent = cont, wx = wx, wy = wy }
end

-- Whether navigation could be started to this place now: true, or false and one sentence (for a menu's tooltip).
function NV.CanNavigate(map, x, y)
    if not NV.Enabled() then return false, "Navigation is turned off. Turn it on in TwichUI's settings (Navigation)." end
    local d, why = NV.Destination(map, x, y)
    if not d then return false, NV.ReasonText(why) end
    return true
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local REASONS = {
    ["other-continent"] = "Nothing on offer crosses to the destination: no boat, zeppelin, learned flight, teleport or Hearthstone connects the two (see Navigation › Getting there).",
    ["no-data"] = "There is no walking map for where you are (instances and some maps have none).",
    unreachable = "No way there: it may be on an island, up a lift, or in a place no boat, flight or teleport you can use reaches.",
    ["start-off"] = "You are not on ground the walking map knows. Move a little and it will try again.",
    ["goal-off"] = "The destination isn't near walkable ground (in the sea, inside a mountain, high on a roof).",
    limit = "The route search grew too large and was stopped.",
    axis = "This client's map positions aren't in the frame the walking maps use, so no route is drawn.",
    ["no-map"] = "Your position isn't available here.",
    ["no-position"] = "Your position isn't available here.",
    ["no-world"] = "That place has no position on a continent.",
    ["bad-map"] = "That map isn't one navigation can use.",
    ["bad-coordinates"] = "That spot is off the map.",
    missing = "The walking maps (TwichUI_NavData) are missing. Reinstall TwichUI.",
    disabled = "The walking maps (TwichUI_NavData) are turned off in the AddOns list.",
    failed = "The walking maps (TwichUI_NavData) could not be loaded.",
    format = "The walking maps (TwichUI_NavData) are from another version of TwichUI. Reinstall TwichUI.",
    combat = "Waiting for combat to end to load the walking maps.",
    error = "Planning the route failed.",
}
function NV.ReasonText(code) return REASONS[code] or "Navigation can't do that right now." end

local function Yards(d)
    d = floor(d + 0.5)
    if d >= 1000 then return ("%d,%03d yd"):format(floor(d / 1000), d % 1000) end
    return d .. " yd"
end
NV.Yards = Yards

local COMPASS = { "north", "north-west", "west", "south-west", "south", "south-east", "east", "north-east" }
-- A bearing (radians counter-clockwise from north, as GetPlayerFacing) as a compass word.
local function Compass(b)
    local i = floor(((b % (2 * pi)) / (2 * pi)) * 8 + 0.5) % 8
    return COMPASS[i + 1]
end
NV.Compass = Compass

local function Bearing(fx, fy, tx, ty) return atan2(ty - fy, tx - fx) end   -- counter-clockwise from north (+y is west)
NV.Bearing = Bearing

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------
local function SegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 0 then
        t = ((px - ax) * dx + (py - ay) * dy) / len2
    end
    local c = t < 0 and 0 or (t > 1 and 1 or t)
    local qx, qy = ax + dx * c, ay + dy * c
    return sqrt((px - qx) ^ 2 + (py - qy) ^ 2), t
end
NV.SegDist = SegDist

-- What the next instruction says, from the route itself: the turn at the next corner (its angle), whether the next leg
-- is mostly swimming, or that the destination is ahead. Never a name, a landmark or a time.
local function Instruction()
    local xs, ys, n = route.xs, route.ys, route.n
    local toNext = prog.toNext
    if seg >= n - 1 then
        local L = CurLeg()
        local what = (not L or L.to == "G") and "Destination" or (L.toLabel or L.toName)
        return ("%s ahead, %s"):format(what, Yards(prog.remaining)), "arrive"
    end
    if route.swim[seg] then
        return ("Swim %s, then %s"):format(Yards(toNext), "continue"), "swim"
    end
    local ax, ay = xs[seg + 1] - xs[seg], ys[seg + 1] - ys[seg]
    local bx, by = xs[seg + 2] - xs[seg + 1], ys[seg + 2] - ys[seg + 1]
    local turn = atan2(by, bx) - atan2(ay, ax)          -- counter-clockwise from the current heading: left is positive
    turn = (turn + pi) % (2 * pi) - pi
    local deg = abs(turn) * 180 / pi
    local side = turn > 0 and "left" or "right"
    local words, kind
    if deg < 25 then words, kind = "continue straight", "straight"
    elseif deg < 60 then words, kind = "bear " .. side, "bear-" .. side
    elseif deg < 120 then words, kind = "turn " .. side, "turn-" .. side
    else words, kind = "turn sharply " .. side, "sharp-" .. side end
    if route.swim[seg + 1] then words = words .. " and swim" end
    if toNext < 8 then return words:sub(1, 1):upper() .. words:sub(2) .. " now", kind end
    return ("In %s, %s"):format(Yards(toNext), words), kind
end

local function Remaining(px, py)
    local xs, ys = route.xs, route.ys
    local d = sqrt((xs[seg + 1] - px) ^ 2 + (ys[seg + 1] - py) ^ 2)
    local rest = 0
    for i = seg + 1, route.n - 1 do rest = rest + sqrt((xs[i + 1] - xs[i]) ^ 2 + (ys[i + 1] - ys[i]) ^ 2) end
    return d, d + rest
end

-- The corner the player has reached, by order: within reach of the next corner, or past it along the next leg and
-- nearer that leg than the current one. At most three corners in one update.
local function Advance(px, py)
    local xs, ys, n = route.xs, route.ys, route.n
    local reach = math.max(4, NP.Get("arrivalYards") * 0.5)
    for _ = 1, 3 do
        if seg >= n - 1 then return end
        local cx, cy = xs[seg + 1], ys[seg + 1]
        if sqrt((px - cx) ^ 2 + (py - cy) ^ 2) <= reach then
            seg = seg + 1
        else
            local dCur = SegDist(px, py, xs[seg], ys[seg], cx, cy)
            local dNext, t = SegDist(px, py, cx, cy, xs[seg + 2], ys[seg + 2])
            if t > 0 and dNext + 1 < dCur and dNext < NP.Get("offRouteYards") then
                seg = seg + 1
            else
                return
            end
        end
    end
end

-- How far you are from the route near where you are on it (the current leg and its neighbours).
local function OffBy(px, py)
    local xs, ys, n = route.xs, route.ys, route.n
    local best = math.huge
    for i = math.max(1, seg - 1), math.min(n - 1, seg + 1) do
        local d = SegDist(px, py, xs[i], ys[i], xs[i + 1], ys[i + 1])
        if d < best then best = d end
    end
    return best
end

---------------------------------------------------------------------------
-- The journey: legs, in order. A leg is a walk (a route over the walking maps), a boat or zeppelin, a flight, a teleport or
-- the Hearthstone (nav/Journey.lua plans them). `route` is the current leg's route when it is a walk. A journey
-- planned while another is followed waits (pending) until its first walk has a route, so nothing drawn goes missing
-- while a new route is worked out.
---------------------------------------------------------------------------
local StartDriver, StopDriver, Plan
local function TravelSpeed() local TV = R.NavTravel return TV and TV.Speed() or 7 end

local function SetRoute()
    local L = CurLeg()
    route = (L and L.kind == "walk") and L.route or nil
    seg = 1
end

-- On ground, not on the sea or the water: what a boat's deck, a ferry in the harbour, is not.
local function OnLand()
    local t, p = ND.Locate(pos.cont, pos.x, pos.y, 0)
    return t ~= nil and t.area[p] == 1
end

local function SpellLabel(id)
    local TV = R.NavTravel
    return TV and TV.SpellName(id) or "Teleport"
end

-- The words of a leg that is not a walk (a walk's come from its route, Instruction above).
local function LegInstruction(L)
    if L.kind == "ferry" then
        if L.fromName == L.toName then return ("Take the %s to the other dock at %s"):format(L.transport, L.toName), "ferry" end
        return ("Take the %s to %s"):format(L.transport, L.toName), "ferry"
    elseif L.kind == "flight" then
        local via = #L.via > 0 and (" via " .. table.concat(L.via, ", ")) or ""
        return ("Fly from %s to %s%s"):format(L.fromName, L.toName, via), "flight"
    elseif L.kind == "teleport" then
        return ("Cast %s (to %s)"):format(SpellLabel(L.spell), L.toName), "teleport"
    elseif L.kind == "hearth" then
        return "Use your Hearthstone", "hearth"
    end
    return "", "walk"
end

-- A leg in a few words, for "Then ...".
local function LegShort(L)
    if L.kind == "walk" then
        if L.to == "G" then return "walk to the destination" end
        return "walk to the " .. (L.toLabel or L.toName)
    end
    local text = LegInstruction(L)
    return text:sub(1, 1):lower() .. text:sub(2)
end
NV.LegShort = LegShort

-- The line under a leg that is not a walk: what to expect, every figure an estimate and said to be.
function NV.LegDetail(L)
    if L.kind == "ferry" then
        return ("Wait for it here: %s, then %s aboard (estimates)"):format(J.Minutes(L.wait), J.Minutes(L.travel))
    elseif L.kind == "flight" then
        return ("Talk to the flight master and choose %s. %s in the air (estimate)"):format(L.toName, J.Minutes(L.seconds))
    elseif L.kind == "teleport" then
        return "About 10 seconds to cast. Uses a Rune of Teleportation."
    elseif L.kind == "hearth" then
        return "About 10 seconds to cast, if it is ready."
    end
    return ""
end

local function UpdateProgress()
    local L = CurLeg()
    if not (L and pos.ok) then return end
    prog.straight = (pos.cont == dest.continent) and Dist(dest.wx, dest.wy, pos.x, pos.y) or nil
    local speed = TravelSpeed()
    if L.kind == "walk" then
        if route then
            Advance(pos.x, pos.y)
            prog.toNext, prog.remaining = Remaining(pos.x, pos.y)
            prog.wet = route.swim[seg] and true or false
            prog.instruction, prog.kind = Instruction()
        else
            prog.toNext, prog.remaining, prog.wet = 0, 0, false
            prog.instruction, prog.kind = "Calculating route…", "wait"
        end
    else
        prog.toNext, prog.remaining, prog.wet = 0, 0, false
        prog.instruction, prog.kind = LegInstruction(L)
    end
    local eta = (L.kind == "walk" and route) and (route.cost and route.cost / speed or prog.remaining / speed) or L.seconds
    if L.kind == "walk" and route then eta = prog.remaining / speed end
    for i = leg + 1, #journey.legs do eta = eta + journey.legs[i].seconds end
    prog.eta = eta
    local nxt = journey.legs[leg + 1]
    prog.nextText = nxt and LegShort(nxt) or nil
    Emit("progress")
end

local function Arrive()
    stats.arrivals = stats.arrivals + 1
    arrivedAt = Now()
    job, pending, legJob = nil, nil, nil
    SetState("arrived")
    if NP.Get("arrivalSound") and PlaySoundFile then
        local path = R.ResolveSound and R:ResolveSound("TwichUI Map Pin")
        if path then PlaySoundFile(path, "SFX") end
    end
end

local function Fail(why)
    stats.failures = stats.failures + 1
    job, pending, legJob = nil, nil, nil
    local L = CurLeg()
    if (why == "start-off" or why == "unreachable") and L and L.kind ~= "walk" then
        -- aboard a boat or in the air with the journey still good: hold it, and look again in a moment
        retryAt = Now() + 3
        SetState("riding", why)
        return
    end
    retries = retries + 1
    retryAt = Now() + RETRY[math.min(retries, #RETRY)]
    SetState("noroute", why)
end

-- A route job for the first walk of journey j (from leg `from`) that has no route yet.
local function NextRouteJob(j, from)
    if legJob or not j then return end
    for i = from or 1, #j.legs do
        local L = j.legs[i]
        if L.kind == "walk" and not L.route and not L.routeFailed then
            local fx, fy = L.fx, L.fy
            local prefer
            if L.from == "S" and pos.ok and pos.cont == L.cont then
                fx, fy = pos.x, pos.y                      -- the first walk starts where you are now
                prefer = route and route.startTile and { tile = route.startTile, poly = route.startPoly } or nil
            end
            legJob = RT.Plan(L.cont, fx, fy, L.tx, L.ty, prefer)
            legJobJourney, legJobIdx, legJobGen = j, i, gen
            return
        end
    end
end

local function Commit(j)
    journey, leg, pending = j, 1, nil
    legStart = nil
    retries, retryAt, offSince = 0, nil, nil
    SetRoute()
    Emit("route")
    SetState("navigating")
    UpdateProgress()
    NextRouteJob(j, 1)
end

-- A journey was planned: followed at once when it starts with something other than a walk, else once that walk's route is in.
local function OnJourney(j)
    pending = j
    if j.legs[1].kind ~= "walk" then Commit(j) return end
    NextRouteJob(j, 1)
end

local function WalkJourney()
    local L = { kind = "walk", cont = pos.cont, fcont = pos.cont, tcont = dest.continent, fx = pos.x, fy = pos.y,
        tx = dest.wx, ty = dest.wy, from = "S", to = "G", fromName = "where you are", toName = dest.name, seconds = 0 }
    return { legs = { L }, seconds = 0, walkOnly = true }
end

-- The next leg of the journey you follow (a walk ended at a place, the ride or flight is the one to do now).
local function AdvanceLeg()
    leg = leg + 1
    local L = CurLeg()
    if not L then Arrive() return end
    legStart = { x = pos.x, y = pos.y, cont = pos.cont }
    offSince = nil
    SetRoute()
    Emit("route")
    SetState((L.kind == "walk" and not route) and "calculating" or "navigating")
    UpdateProgress()
    NextRouteJob(journey, leg)
end

-- Plans from where you are. kind: "start", "manual", "off", "jump", "retry", "leg" (a ride is over), "land" (a flight is).
function Plan(kind)
    if not dest then return end
    if not pos.ok then
        local ok, why = ReadPosition()
        if not ok then SetState("unavailable", why) return end
    end
    local loaded, lwhy = ND.Load()
    if not loaded then
        if lwhy == "combat" then
            waitCombat = true
            R:On("PLAYER_REGEN_ENABLED", NV.OnCombatEnd)
            SetState("loading", "combat")
        else
            SetState("noroute", lwhy)
        end
        return
    end
    if job or legJob then stats.superseded = stats.superseded + 1 end
    gen = gen + 1                                     -- anything still being searched is now stale
    job, pending, legJob = nil, nil, nil
    stats.plans = stats.plans + 1
    lastPlanAt, offSince = Now(), nil
    if kind == "off" then stats.replansOff = stats.replansOff + 1 end
    if kind == "jump" or kind == "land" then stats.replansJump = stats.replansJump + 1 end
    local direct = pos.cont == dest.continent
    local TV = R.NavTravel
    local straight = direct and Dist(dest.wx, dest.wy, pos.x, pos.y) or math.huge
    if direct and (straight <= J.MULTI_YARDS or not (TV and TV.Any()) or not ND.Transit()) then
        if not ND.HasMap(pos.cont) then
            Emit("route")
            SetState("noroute", "no-data")
            return
        end
        SetState(journey and "recalculating" or "calculating")
        OnJourney(WalkJourney())
        return
    end
    if not ND.Transit() then
        SetState("noroute", "other-continent")
        return
    end
    local req = TV and TV.Request() or { faction = 1, speed = 7, ships = false, teleports = {} }
    req.start = { cont = pos.cont, x = pos.x, y = pos.y }
    req.goal = { cont = dest.continent, x = dest.wx, y = dest.wy }
    req.prefer = route and route.startTile and { tile = route.startTile, poly = route.startPoly } or nil
    job, jobGen = J.Plan(req), gen
    SetState(journey and "recalculating" or "calculating")
end

function NV.OnCombatEnd()
    R:Off("PLAYER_REGEN_ENABLED", NV.OnCombatEnd)
    if not waitCombat then return end
    waitCombat = false
    if dest then Plan("start") end
end

-- Off a leg that isn't a walk, or its end: what to do about it.
local function LegProgress(L, now)
    local dArr = (pos.cont == L.tcont) and Dist(pos.x, pos.y, L.tx, L.ty) or math.huge
    local dDep = (pos.cont == L.fcont) and Dist(pos.x, pos.y, L.fx, L.fy) or math.huge
    if L.kind == "ferry" or L.kind == "flight" then
        if dArr <= (L.kind == "ferry" and 150 or 200) then Plan("leg") return end
        local land = OnLand()
        if dDep > 100 and not land then
            -- away from where it starts and not on ground: aboard. Nothing to follow until it arrives
            offSince = nil
            if state ~= "riding" then SetState("riding", "aboard") end
            return
        end
        if state == "riding" and reason == "aboard" then SetState("navigating") end
        -- well away from where it starts, on land and not aboard anything: you have left the plan
        if dDep > 150 and land then
            offSince = offSince or now
            if now - offSince >= OFF_HOLD and now - lastPlanAt >= REPLAN_GAP then Plan("off") end
        else
            offSince = nil
        end
    else
        -- a teleport or the Hearthstone can be used anywhere; walking far from where it became the thing to do is leaving the plan
        legStart = legStart or { x = pos.x, y = pos.y, cont = pos.cont }
        if pos.cont == legStart.cont and Dist(pos.x, pos.y, legStart.x, legStart.y) > 400 then Plan("off") end
    end
end

local lastX, lastY, lastCont
local function Progress()
    if not dest then return end
    local now = Now()
    if state == "arrived" then
        if now - (arrivedAt or now) >= ARRIVED_HOLD then NV.Stop("arrived") end
        return
    end
    if not pos.ok then
        if state ~= "loading" then SetState("unavailable", posWhy or "no-position") end
        return
    end
    if state == "loading" then return end
    -- on a flight path: nothing to follow until you land, and then a plan from where you are
    local taxi = UnitOnTaxi and UnitOnTaxi("player") and true or false
    if taxi then
        wasTaxi = true
        lastX, lastY, lastCont = pos.x, pos.y, pos.cont
        offSince = nil
        SetState("riding", "taxi")
        return
    end
    if wasTaxi then
        wasTaxi = false
        lastX, lastY, lastCont = pos.x, pos.y, pos.cont
        Plan("land")
        return
    end
    -- a jump or a new continent (a teleport, a boat's arrival, a graveyard): plan again now
    local jumped = lastCont and (pos.cont ~= lastCont or Dist(pos.x, pos.y, lastX, lastY) > JUMP)
    lastX, lastY, lastCont = pos.x, pos.y, pos.cont
    if jumped then Plan("jump") return end
    if state == "unavailable" then
        if journey then SetState("navigating") else Plan("start") end
        return
    end
    -- arrived?
    if pos.cont == dest.continent and Dist(dest.wx, dest.wy, pos.x, pos.y) <= NP.Get("arrivalYards") then
        Arrive()
        return
    end
    if state == "riding" then
        if retryAt and now >= retryAt then retryAt = nil Plan("retry") return end
        local L = CurLeg()
        if L and L.kind ~= "walk" then LegProgress(L, now) end   -- it may have arrived
        return
    end
    if state == "noroute" then
        -- try again later, and only from somewhere else
        if retryAt and now >= retryAt and reason ~= "other-continent" and reason ~= "axis" and reason ~= "missing"
            and reason ~= "disabled" and reason ~= "format" then
            retryAt = nil
            Plan("retry")
        end
        prog.straight = (pos.cont == dest.continent) and Dist(dest.wx, dest.wy, pos.x, pos.y) or nil
        Emit("progress")
        return
    end
    if state ~= "navigating" then return end
    local L = CurLeg()
    if not L then return end
    if L.kind ~= "walk" then
        UpdateProgress()
        LegProgress(L, now)
        return
    end
    if not route then return end                      -- its route is still being worked out
    UpdateProgress()
    -- the end of a walk that ends at a place (a dock, a flight master): on to the next leg
    if L.to ~= "G" and seg >= route.n - 1 and Dist(pos.x, pos.y, route.goalX, route.goalY) <= NP.Get("arrivalYards") + 4 then
        AdvanceLeg()
        return
    end
    local off = OffBy(pos.x, pos.y)
    local limit = NP.Get("offRouteYards")
    if off > limit then
        offSince = offSince or now
        if now - offSince >= OFF_HOLD and now - lastPlanAt >= REPLAN_GAP then Plan("off") end
    elseif off < limit * 0.6 then
        offSince = nil
    end
end

local function StepJob()
    if job then
        local status, result = job:Step(SEARCH_BUDGET)
        if status == "running" then return end
        local stale = jobGen ~= gen
        job = nil
        if stale then return end
        if status == "done" then OnJourney(result) else Fail(result) end
        return
    end
    if legJob then
        local status, result = legJob:Step(SEARCH_BUDGET)
        if status == "running" then return end
        local j, i, stale = legJobJourney, legJobIdx, legJobGen ~= gen
        legJob = nil
        if stale then return end
        local L = j.legs[i]
        if status == "done" then
            L.route = result
            if j.walkOnly then L.seconds = (result.cost or 0) / TravelSpeed() end
            if j == pending and i == 1 then
                Commit(j)
            elseif j == journey and i == leg then
                SetRoute()
                SetState("navigating")
                Emit("route")
                UpdateProgress()
            else
                Emit("route")
            end
        else
            L.routeFailed = result
            if (j == pending and i == 1) or (j == journey and i == leg) then Fail(result) end
        end
        NextRouteJob(j == pending and pending or journey, 1)
    end
end

local function OnUpdate(_, elapsed)
    StepJob()
    acc.pos = acc.pos + elapsed
    if acc.pos >= POS_EVERY then
        acc.pos = 0
        local _, why = ReadPosition()
        posWhy = why
        Emit("position")
    end
    acc.prog = acc.prog + elapsed
    if acc.prog >= PROGRESS_EVERY then
        acc.prog = 0
        Progress()
    end
    for i = 1, #tickers do
        local ok, err = pcall(tickers[i], elapsed)
        if not ok then R.Fault("navigation ticker", err) end
    end
end

function StartDriver()
    if not driver then driver = CreateFrame("Frame") end
    if not driver:GetScript("OnUpdate") then driver:SetScript("OnUpdate", OnUpdate) end
end

function StopDriver()
    if driver then driver:SetScript("OnUpdate", nil) end
end

local function OnWorld()
    lastCont = nil
    if dest and state ~= "arrived" then
        local _, why = ReadPosition()
        posWhy = why
        Progress()
    end
end
local function OnLeave() pos.ok = false; SetState("unavailable", "no-position") end

---------------------------------------------------------------------------
-- Starting and stopping
---------------------------------------------------------------------------
-- Starts navigating to `d` (from NV.Destination), replacing any destination you had. Returns true, or false and why.
function NV.Start(d)
    if not NV.Enabled() then return false, "Navigation is turned off." end
    if type(d) ~= "table" or not d.continent then return false, NV.ReasonText("bad-map") end
    dest = d
    route, job, seg = nil, nil, 1
    journey, leg, pending, legJob, legStart, wasTaxi = nil, 1, nil, nil, nil, false
    retries, retryAt, offSince, arrivedAt = 0, nil, nil, nil
    lastCont = nil
    gen = gen + 1
    R:On("PLAYER_ENTERING_WORLD", OnWorld)
    R:On("ZONE_CHANGED_NEW_AREA", OnWorld)
    R:On("PLAYER_LEAVING_WORLD", OnLeave)
    StartDriver()
    Emit("destination")
    Emit("route")
    local ok, why = ReadPosition()
    if not ok then SetState("unavailable", why) return true end
    lastX, lastY, lastCont = pos.x, pos.y, pos.cont
    Plan("start")
    return true
end

-- Convenience: a map point. Returns true, or false and a sentence.
function NV.StartAt(map, x, y, name, source)
    local d, why = NV.Destination(map, x, y, name, source)
    if not d then return false, NV.ReasonText(why) end
    return NV.Start(d)
end

-- Ends navigation (the stop button, arrival, the switch). Nothing is saved; decoded walking maps are let go.
function NV.Stop(why)
    if not dest and state == "idle" then return end
    dest, route, job = nil, nil, nil
    journey, leg, pending, legJob, legStart, wasTaxi = nil, 1, nil, nil, nil, false
    gen = gen + 1
    waitCombat = false
    R:Off("PLAYER_REGEN_ENABLED", NV.OnCombatEnd)
    R:Off("PLAYER_ENTERING_WORLD", OnWorld)
    R:Off("ZONE_CHANGED_NEW_AREA", OnWorld)
    R:Off("PLAYER_LEAVING_WORLD", OnLeave)
    StopDriver()
    ND.Release()
    state, reason = "idle", why
    Emit("route")
    Emit("state")
end

-- Plans again from here (the frame's button). Returns whether a plan started.
function NV.Recalculate()
    if not dest then return false end
    retries, retryAt = 0, nil
    local ok, why = ReadPosition()
    if not ok then SetState("unavailable", why) return false end
    Plan("manual")
    return job ~= nil
end

function NV.Active() return dest ~= nil end

-- Read only: what the views draw. Plain values; the route's arrays are shared (never change them).
function NV.Snapshot()
    return {
        state = state, reason = reason, dest = dest, route = route, seg = seg,
        toNext = prog.toNext, remaining = prog.remaining, straight = prog.straight,
        instruction = prog.instruction, kind = prog.kind, wet = prog.wet,
        fallback = (state == "noroute" and dest and pos.ok and pos.cont == dest.continent) or false,
        -- the journey: its legs (shared: never change them), the current one, what comes next, the time left (an estimate)
        legs = journey and journey.legs or nil, leg = leg, legKind = (CurLeg() or {}).kind,
        steps = journey and #journey.legs or 0, eta = prog.eta, nextText = prog.nextText,
    }
end

-- The point the arrow should point at: the next corner of the route, or (labelled by the caller) the destination itself
-- when there is no route but you are on its continent. Returns x, y, kind ("route" or "direct"), or nil.
function NV.Target()
    if not (dest and pos.ok) then return nil end
    local L = CurLeg()
    if L and L.kind ~= "walk" and (state == "navigating" or state == "recalculating") then return nil end   -- nothing to walk toward
    if route and (state == "navigating" or state == "recalculating") and pos.cont == route.map then
        local i = math.min(seg + 1, route.n)
        return route.xs[i], route.ys[i], "route"
    end
    if state == "noroute" and pos.cont == dest.continent then return dest.wx, dest.wy, "direct" end
    return nil
end

-- The switch: off ends navigation and drops every decoded table.
function NV.Refresh()
    if not NV.Enabled() then
        NV.Stop("off")
        ND.Release()
    end
    Emit("prefs")
end

NP.Subscribe(function() Emit("prefs") end)
R.Profiles.OnApply("views", "navigation", function() Emit("prefs") end)

---------------------------------------------------------------------------
-- /tui nav (Core.lua's parser): output in your own chat frame only
---------------------------------------------------------------------------
local USAGE = "/tui nav 45.2 61.8 (coordinates on your current map), /tui nav waypoint (the game's waypoint), /tui nav stop, /tui nav recalc."

function NV.Command(arg)
    arg = (arg or ""):lower()
    if not NV.Enabled() then
        R.Print("Navigation is turned off. Turn it on in /tui options (Navigation).")
        return
    end
    if arg == "" then
        if dest then
            R.Print("navigating to %s (%s). %s", dest.name, state, USAGE)
        else
            R.Print("not navigating. %s", USAGE)
        end
        return
    end
    if arg == "stop" then
        if dest then NV.Stop("stopped") R.Print("navigation stopped.") else R.Print("not navigating.") end
        return
    end
    if arg == "recalc" or arg == "again" then
        if not NV.Recalculate() and dest then R.Print(NV.ReasonText(reason or "no-position")) end
        if not dest then R.Print("not navigating.") end
        return
    end
    if arg == "waypoint" then
        local point = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
        if not point then R.Print("you have no waypoint set.") return end
        local x, y = point.position:GetXY()
        local ok, why = NV.StartAt(point.uiMapID, x, y, "Your waypoint", "waypoint")
        if not ok then R.Print(why) end
        return
    end
    local a, b = arg:match("^%s*([%d%.]+)[%s,]+([%d%.]+)%s*$")
    a, b = tonumber(a), tonumber(b)
    if a and b then
        local map = Readable(C_Map.GetBestMapForUnit("player"))
        if not map then R.Print(NV.ReasonText("no-map")) return end
        local ok, why = NV.StartAt(map, a / 100, b / 100, nil, "command")
        if not ok then R.Print(why) end
        return
    end
    R.Print("I didn't follow that. %s", USAGE)
end

-- Read only, for /tui diagnostics: states and counts, never a place or a name.
function NV.Diagnostics()
    return { state = state, reason = reason, active = dest ~= nil, routePoints = route and route.n or 0,
        legs = journey and #journey.legs or 0, leg = leg,
        searching = job ~= nil, axis = axis, plans = stats.plans, offRoute = stats.replansOff, jumps = stats.replansJump,
        failures = stats.failures, arrivals = stats.arrivals, superseded = stats.superseded, tickers = #tickers,
        driver = driver ~= nil and driver:GetScript("OnUpdate") ~= nil, data = ND.Snapshot() }
end
