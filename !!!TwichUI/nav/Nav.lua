-- TwichUI: Navigation, the journey being followed
-- One destination at a time, chosen by the player (a pin's Navigate here, the map tool, /tui nav). A walking route to it
-- is planned over the baked walking maps (nav/Route.lua), followed as the player moves, planned again when the player
-- leaves it, and put away on arrival. It never moves the character, turns the camera, casts, clicks or presses anything,
-- and nothing it receives from another player (a ping, a party pin arriving) ever starts or changes it.
--
-- States (NV.Snapshot().state):
--   "loading"        the walking maps are being loaded (they wait for combat to end: "waiting for combat")
--   "calculating"    the first route is being planned
--   "navigating"     a route is being followed
--   "recalculating"  a new route is being planned; the old one stays drawn, marked as being replaced
--   "unavailable"    where you are can't be read (an instance, a loading screen, a map with no position)
--   "noroute"        no walking route: reason "other-continent", "no-data", "unreachable", "start-off", "goal-off",
--                    "limit", "axis". Where a direct bearing still means something (same continent) it is offered, and
--                    always labelled as one, never as a route.
--   "arrived"        within the arrival distance; shown for a moment, then navigation ends
--
-- Where you are: the map the game puts you on (C_Map.GetBestMapForUnit), your place on it (GetPlayerMapPosition) and that
-- place in continent yards (GetWorldPosFromMapPos), the same path a destination takes, read ten times a second while
-- navigating. Before the first route, NV checks that the client's world positions are in the bake's frame (x north,
-- y west) by moving a point east on your map and seeing which coordinate falls; anything else stops with "axis".
-- Facing (GetPlayerFacing) is read by the arrow only.
--
-- Progress, four times a second: the route's corners are passed in order (a corner counts as passed when you are within
-- reach of it, or past it along the next leg and closer to that leg); never skipped because a later one is near in a
-- straight line. Off the route by more than the chosen distance for OFF_HOLD seconds (and at least REPLAN_GAP after the
-- last plan) plans again from where you are; back within 60% of it clears the count. A jump of JUMP yards (a teleport,
-- a graveyard, a flight landing) or a change of continent plans again at once. A newer plan always replaces an older one
-- (by generation); a superseded search is dropped, never finished.
--
-- Work: one driver frame whose OnUpdate exists only while a destination is set. No events are listened to while idle.
-- Saved: nothing (preferences only, nav/Prefs.lua). The destination ends with the session.

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
local route                     -- the route being followed
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
    ["other-continent"] = "The destination is on another continent. Walking routes stay on one continent; travel by boat, zeppelin or flight isn't planned.",
    ["no-data"] = "There is no walking map for where you are (instances and some maps have none).",
    unreachable = "No walking route reaches it: it may be on an island, up a lift or behind something the walking map can't cross.",
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
        return ("Destination ahead, %s"):format(Yards(prog.remaining)), "arrive"
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
-- Planning
---------------------------------------------------------------------------
local StartDriver, StopDriver, Plan

local function Arrive()
    stats.arrivals = stats.arrivals + 1
    arrivedAt = Now()
    job = nil
    SetState("arrived")
    if NP.Get("arrivalSound") and PlaySoundFile then
        local path = R.ResolveSound and R:ResolveSound("TwichUI Map Pin")
        if path then PlaySoundFile(path, "SFX") end
    end
end

local function Fail(why)
    stats.failures = stats.failures + 1
    job = nil
    retries = retries + 1
    retryAt = Now() + RETRY[math.min(retries, #RETRY)]
    SetState("noroute", why)
end

-- Plans from where you are. kind: "start", "manual", "off", "jump", "retry".
function Plan(kind)
    if not dest then return end
    if not pos.ok then
        local ok, why = ReadPosition()
        if not ok then SetState("unavailable", why) return end
    end
    if pos.cont ~= dest.continent then
        job, route = nil, nil
        Emit("route")
        SetState("noroute", "other-continent")
        return
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
    if not ND.HasMap(pos.cont) then
        job, route = nil, nil
        Emit("route")
        SetState("noroute", "no-data")
        return
    end
    if job then stats.superseded = stats.superseded + 1 end
    gen = gen + 1
    stats.plans = stats.plans + 1
    local prefer = route and route.startTile and { tile = route.startTile, poly = route.startPoly } or nil
    job, jobGen = RT.Plan(pos.cont, pos.x, pos.y, dest.wx, dest.wy, prefer), gen
    lastPlanAt, offSince = Now(), nil
    if kind == "off" then stats.replansOff = stats.replansOff + 1 end
    if kind == "jump" then stats.replansJump = stats.replansJump + 1 end
    SetState(route and "recalculating" or "calculating")
end

function NV.OnCombatEnd()
    R:Off("PLAYER_REGEN_ENABLED", NV.OnCombatEnd)
    if not waitCombat then return end
    waitCombat = false
    if dest then Plan("start") end
end

local function Accept(r)
    route = r
    seg = 1
    retries, retryAt = 0, nil
    job = nil
    Emit("route")
    SetState("navigating")
end

local function UpdateProgress()
    if not (route and pos.ok) then return end
    local px, py = pos.x, pos.y
    Advance(px, py)
    prog.toNext, prog.remaining = Remaining(px, py)
    prog.straight = sqrt((dest.wx - px) ^ 2 + (dest.wy - py) ^ 2)
    prog.wet = route.swim[seg] and true or false
    prog.instruction, prog.kind = Instruction()
    Emit("progress")
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
    -- a jump or a new continent: plan again now
    local jumped = lastCont and (pos.cont ~= lastCont or sqrt((pos.x - lastX) ^ 2 + (pos.y - lastY) ^ 2) > JUMP)
    lastX, lastY, lastCont = pos.x, pos.y, pos.cont
    if jumped then Plan("jump") return end
    if state == "unavailable" then
        if route and route.map == pos.cont then SetState("navigating") else Plan("start") end
        return
    end
    -- arrived?
    if prog and dest and pos.cont == dest.continent then
        local straight = sqrt((dest.wx - pos.x) ^ 2 + (dest.wy - pos.y) ^ 2)
        local atRouteEnd = route and sqrt((route.goalX - pos.x) ^ 2 + (route.goalY - pos.y) ^ 2) or math.huge
        local arrival = NP.Get("arrivalYards")
        if straight <= arrival or (route and atRouteEnd <= arrival and seg >= route.n - 1) then
            Arrive()
            return
        end
    end
    if state == "noroute" then
        -- try again later, and only from somewhere else
        if retryAt and now >= retryAt and reason ~= "other-continent" and reason ~= "axis" and reason ~= "missing"
            and reason ~= "disabled" and reason ~= "format" then
            retryAt = nil
            Plan("retry")
        end
        prog.straight = sqrt((dest.wx - pos.x) ^ 2 + (dest.wy - pos.y) ^ 2)
        Emit("progress")
        return
    end
    if not route or state ~= "navigating" then return end
    UpdateProgress()
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
    if not job then return end
    local status, result = job:Step(SEARCH_BUDGET)
    if status == "running" then return end
    if jobGen ~= gen then job = nil return end      -- superseded meanwhile
    if status == "done" then
        Accept(result)
        UpdateProgress()
    else
        Fail(result)
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
    }
end

-- The point the arrow should point at: the next corner of the route, or (labelled by the caller) the destination itself
-- when there is no route but you are on its continent. Returns x, y, kind ("route" or "direct"), or nil.
function NV.Target()
    if not (dest and pos.ok) then return nil end
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
        searching = job ~= nil, axis = axis, plans = stats.plans, offRoute = stats.replansOff, jumps = stats.replansJump,
        failures = stats.failures, arrivals = stats.arrivals, superseded = stats.superseded, tickers = #tickers,
        driver = driver ~= nil and driver:GetScript("OnUpdate") ~= nil, data = ND.Snapshot() }
end
