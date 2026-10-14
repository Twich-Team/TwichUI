-- TwichUI: troubleshooting report, zone arrival
-- Two sections: the zone arrival card (modules/Arrival.lua) and the Chronicle's automatic zone entries
-- (chronicle/Recorder.lua). Both say whether their location baseline for this session is set, whether
-- the location is readable now, and flight-path state. Place names are not reported, and nothing from
-- the Chronicle's entries or notes is read. The decisions arrive as trace records from the modules.

local R = TwichUI
local D = R.Diag

local function Missing(events, wanted)
    local have, missing = {}, {}
    for _, e in ipairs(events) do have[e] = true end
    for _, e in ipairs(wanted) do
        if not have[e] then missing[#missing + 1] = e end
    end
    return missing
end

local ARRIVAL_EVENTS = { "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD" }
local ARRIVAL_SUBZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }

local function Arrival()
    local A = R.Arrival
    if not (A and A.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = A.Snapshot()
    local wanted = {}
    for _, e in ipairs(ARRIVAL_EVENTS) do wanted[#wanted + 1] = e end
    if s.subzones then for _, e in ipairs(ARRIVAL_SUBZONE_EVENTS) do wanted[#wanted + 1] = e end end
    local missing = s.enabled and Missing(s.events, wanted) or {}
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("card: %s; smaller places: %s; dungeon and raid cards: %s; reduced motion: %s", s.enabled and "on" or "off",
        s.subzones and "on" or "off", s.dungeons and "on" or "off", s.reducedMotion and "on" or "off")
    if s.enabled then
        Line("required events: %d of %d registered%s", #wanted - #missing, #wanted,
            #missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or "")
    end
    Line("location: zone text available now=%s; session baseline zone known=%s; baseline smaller place known=%s; inside an instance=%s",
        D.Flag(s.zoneKnown), D.Flag(s.baselineZone), D.Flag(s.baselineSubzone), s.instanceKind)
    Line("flight: control lost=%s; on a flight path=%s", D.Flag(s.controlLost), D.Flag(s.onFlight))
    Line("login quiet time left=%.1fs; card on screen=%s; waiting for an instance's name=%s; the game's own zone text hooked=%s",
        s.quietLeft, D.Flag(s.cardShowing), D.Flag(s.waitingForInstanceName), D.Flag(s.nativeHooked))
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif #missing > 0 then status, reason = "unavailable", "event-not-registered"
    elseif not s.zoneKnown then status, reason = "waiting", "zone-text-not-available"
    elseif s.quietLeft > 0 then status, reason = "waiting", "login-quiet-time" end
    return {
        configured = s.enabled, initialized = D.When(s.enabled, #missing == 0), status = status, reason = reason, lines = lines,
        limits = { "Whether a card was shown is not recorded; the trace records each decision (changed, unchanged, skipped on a flight path)." },
    }
end

local CHRONICLE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }

local function Chronicle()
    local Rec = R.ChronicleRecorder
    if not (Rec and Rec.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = Rec.Snapshot()
    local on = s.chronicle and s.zones
    local missing = on and Missing(s.events, CHRONICLE_EVENTS) or {}
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("Chronicle automatic entries: %s; arriving in a new zone: %s", s.chronicle and "on" or "off", s.zones and "on" or "off")
    if on then
        Line("required events: %d of %d registered%s", #CHRONICLE_EVENTS - #missing, #CHRONICLE_EVENTS,
            #missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or "")
    end
    Line("this session's location baseline: %s (look %d of %d extra)", s.baselined and "set" or "not set", s.baselineTries, s.baselineRetries)
    Line("entered the world this session=%s; zone readable now=%s; control lost=%s; on a flight path=%s",
        D.Flag(s.inWorld), D.Flag(s.zoneReadable), D.Flag(s.controlLost), D.Flag(s.onFlight))
    Line("Chronicle entries, notes and places are not read or reported here")
    local status, reason = "ready", nil
    if not on then status = "off"
    elseif #missing > 0 then status, reason = "unavailable", "event-not-registered"
    elseif not s.inWorld then status, reason = "waiting", "world-not-entered-yet"
    elseif not s.baselined then
        if s.baselineTries >= s.baselineRetries then status, reason = "unavailable", "baseline-gave-up"
        else status, reason = "waiting", "baseline-pending" end
    end
    return {
        configured = on and true or false, initialized = D.When(on, s.baselined), status = status, reason = reason, lines = lines,
        limits = { "Until the baseline is set, the first zone seen is taken as where you already were, so nothing is recorded as an arrival." },
    }
end

D.Register("arrival", { title = "Zone arrival card", order = 50, snapshot = Arrival })
D.Register("chronicle", { title = "Chronicle zone arrival", order = 60, snapshot = Chronicle })
