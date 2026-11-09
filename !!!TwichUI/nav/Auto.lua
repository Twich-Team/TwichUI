-- TwichUI: Navigation, start by itself when you place a marker
-- Off until chosen (ui.navigation.autoStart, only while navigation is on). Then a marker you place begins navigation to it,
-- in place of any destination you had:
--   * the game's own waypoint (map click, Ctrl-click, /way from another addon: USER_WAYPOINT_UPDATED), and
--   * a pin you place by hand (Pins.OnPlaced: the editor's Save of a new pin, a single /twichway).
-- Never started by: a pin someone shares with you, a copy of one, a pasted list, an import, the Cozy Sleeping Bag guide, or
-- the waypoint the RestedXP step feature puts down on its own (those are not markers you placed). A waypoint that is
-- already set when this is turned on, or at login, is left alone; only a new or moved one counts. It starts a plan and
-- shows it, nothing else: no chat, no movement, no casting. Nothing is saved but the choice itself.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local AU = {}
R.NavAuto = AU

local SETTLE = 0.2     -- the game may send several updates for one placement (and the guide feature records its own after)
local NEAR = 1e-3      -- map units: the same spot as the destination already being followed
local stats = { events = 0, waypoints = 0, pins = 0, started = 0, ignored = 0 }
local last = "nothing yet"   -- what the latest marker came to, in words (shown by /tui nav)

local registered = false
local seen                  -- the waypoint last looked at: "map:x:y", or false for none
local token = 0

local function On() return NV.Enabled() and NP.Get("autoStart") == true end

local function Key(map, x, y) return ("%d:%.5f:%.5f"):format(map, x, y) end

-- The game's waypoint as plain numbers, or nil.
local function Waypoint()
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    local pos = ok and type(point) == "table" and point.position
    if not pos then return nil end
    local okXY, x, y = pcall(pos.GetXY, pos)
    if not okXY then return nil end
    local map = NV.Readable(point.uiMapID)
    x, y = NV.Readable(x), NV.Readable(y)
    if map and x and y then return map, x, y end
end

local function AlreadyThere(map, x, y)
    local snap = NV.Snapshot()
    local d = snap.dest
    return d ~= nil and d.map == map and math.abs(d.x - x) <= NEAR and math.abs(d.y - y) <= NEAR
end

local function Begin(map, x, y, name, source)
    if AlreadyThere(map, x, y) then last = source .. ": already the destination" return end
    local ok, why = NV.StartAt(map, x, y, name, source)
    if ok then
        stats.started = stats.started + 1
        last = source .. ": started"
    else
        stats.ignored = stats.ignored + 1   -- a place navigation can't use: nothing is said unless you ask (/tui nav)
        last = source .. ": " .. tostring(why)
    end
end

local function Look()
    if not On() then return end
    local map, x, y = Waypoint()
    local key = map and Key(map, x, y) or false
    if key == seen then last = "waypoint: same as the last one" return end
    seen = key
    if not key then last = "waypoint: cleared, or not readable" return end
    local GW = R.QoLGuideWaypoint
    if GW and GW.OwnsWaypoint and GW.OwnsWaypoint() then last = "waypoint: the RestedXP step's" return end   -- not a marker you placed
    stats.waypoints = stats.waypoints + 1
    Begin(map, x, y, "Your waypoint", "waypoint")
end

local function OnWaypoint()
    stats.events = stats.events + 1
    token = token + 1
    local mine = token
    C_Timer.After(SETTLE, function()
        if mine == token then Look() end
    end)
end

local function OnPlaced(pin)
    if not On() or type(pin) ~= "table" then return end
    local PN = R.Pins
    stats.pins = stats.pins + 1
    Begin(pin.map, pin.x / PN.COORD, pin.y / PN.COORD, pin.name, pin.key and "group" or "pin")
end

-- Listens to the game's waypoint only while this is on.
local function Sync()
    if On() then
        if not registered then
            registered = true
            local map, x, y = Waypoint()
            seen = map and Key(map, x, y) or false   -- what is set now was not just placed
            R:On("USER_WAYPOINT_UPDATED", OnWaypoint)
        end
    elseif registered then
        registered = false
        token = token + 1
        R:Off("USER_WAYPOINT_UPDATED", OnWaypoint)
    end
end

NV.Subscribe(function(event) if event == "prefs" then Sync() end end)
R:OnInit(function()
    if R.Pins and R.Pins.OnPlaced then R.Pins.OnPlaced(OnPlaced) end
    Sync()
end)

-- Read only, for /tui diagnostics: counts, never a place.
function AU.Diagnostics()
    return { on = registered, events = stats.events, waypoints = stats.waypoints, pins = stats.pins, started = stats.started, ignored = stats.ignored }
end

-- One sentence for /tui nav: whether this is listening and what the latest marker came to. No place or name.
function AU.Status()
    if not NP.Get("autoStart") then return "Start when I place a marker: off." end
    return ("Start when I place a marker: on (%s). Game waypoint events %d, waypoints looked at %d, pins %d, started %d, refused %d. Latest: %s."):format(
        registered and "listening" or "NOT listening", stats.events, stats.waypoints, stats.pins, stats.started, stats.ignored, last)
end
