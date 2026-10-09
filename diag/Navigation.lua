-- TwichUI: troubleshooting report, navigation
-- Whether navigation is on and ready, whether a route is active and what kind of step it is on, how
-- much flight data has been learned, and how often each kind of result has happened this session.
-- Codes and counts only: no places, flight point names, coordinates or pin positions are read here.

local R = TwichUI
local D = R.Diag

local NAV_EVENTS = { "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TAXI_NODE_STATUS_CHANGED", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }

local function Navigation()
    local N, F, ND, M, G = R.Nav, R.NavFlights, R.NavData, R.NavMap, R.NavGuide
    if not (N and N.Snapshot and F and ND and M and G) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s, f, d, m, g = N.Snapshot(), F.Snapshot(), ND.Snapshot(), M.Snapshot(), G.Snapshot()
    local have = {}
    for _, e in ipairs(f.events) do have[e] = true end
    local missing = {}
    if s.enabled then
        for _, e in ipairs(NAV_EVENTS) do if not have[e] then missing[#missing + 1] = e end end
    end
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("navigation: %s; direction arrow: %s", s.enabled and "on" or "off", s.arrow and "on" or "off")
    if s.enabled then
        Line("required events: %d of %d registered%s", #NAV_EVENTS - #missing, #NAV_EVENTS,
            #missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or "")
    end
    Line("world map: route drawing added=%s; filter menu entry=%s; drawn %d times (dots %d, dashes %d, marks %d; %d left out at the limit)",
        D.Flag(m.added), D.Flag(m.menu), m.layouts, m.dots, m.dashes, m.marks, m.clipped)
    Line("route active=%s; step %d of %d (%s); in flight=%s; paused=%s; checking=%s; routes planned this session=%d",
        D.Flag(s.active), s.index, s.legs, s.mode, D.Flag(s.flying), s.status, D.Flag(s.ticking), s.plans)
    Line("last map pin read: %s", s.pinProblem)
    Line("next-step strip shown=%s; arrow shown=%s (updating=%s); Edit Mode outlines shown=%s",
        D.Flag(g.strip), D.Flag(g.arrow), D.Flag(g.arrowUpdating), D.Flag(g.movers))
    Line("learned flight data (%s): %d of at most %d routes, %d of at most %d flight times; flight speed from your flights=%s",
        d.outcome or "not loaded", d.routes, d.maxRoutes, d.times, d.maxTimes, D.Flag(f.speedLearned))
    Line("flight master: last look=%s (%d of your flight points listed, %d routes noted); map open=%s; watching a chosen flight=%s; in that flight=%s; last flight=%s; TakeTaxiNode watched=%s",
        f.lastScan, f.lastScanKnown, f.lastScanRoutes, D.Flag(f.taxiOpen), D.Flag(f.watching), D.Flag(f.flying), f.lastFlight, D.Flag(f.hooked))
    Line("flight points on this continent: %d placed by the game, %d of your faction the world map calls found, %d a flight master has listed as yours; characters with flight points noted: %d",
        f.here.placed, f.here.gameFound, f.here.known, d.chars)
    local codes = {}
    for code in pairs(s.counts) do codes[#codes + 1] = code end
    table.sort(codes)
    for _, code in ipairs(codes) do Line("result %s: %d", code, s.counts[code]) end

    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif #missing > 0 then status, reason = "unavailable", "event-not-registered"
    elseif not m.added then status, reason = "waiting", "world-map-not-loaded"
    elseif s.active and s.status ~= "none" then status, reason = "waiting", s.status end
    return {
        configured = s.enabled, initialized = D.When(s.enabled, m.added and #missing == 0), status = status, reason = reason, lines = lines,
        limits = {
            "Walking is measured in a straight line; the game gives no walking paths. Boats, zeppelins, portals and the Hearthstone are not planned yet.",
            "A flight not yet seen at a flight master is assumed to be direct, and its time is rough until you have flown it.",
        },
    }
end

D.Register("navigation", { title = "Navigation", order = 70, snapshot = Navigation })
