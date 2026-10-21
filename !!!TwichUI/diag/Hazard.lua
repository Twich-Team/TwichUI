-- TwichUI: troubleshooting report, Hazard alerts
-- Reads HazardAlerts.Snapshot(): whether the alerts are on, whether the client offers aura sounds, how many are
-- registered, whether a change is waiting for the game's restrictions to lift, and how many preview sounds were played.
-- Counts and words only: no spell IDs, no rule names. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local A = R.HazardAlerts
    if not (A and A.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = A.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; client offers aura sounds: %s; events registered: %s", s.enabled and "on" or "off", D.Flag(s.available), s.watching and "yes" or "no")
    Line("registered: %d of %d wanted; waiting for restrictions: %s; restricted now: %s", s.registered, s.wanted, D.Flag(s.pending), D.Flag(s.restricted))
    Line("registrations made: %d; refused by the game: %d; removed: %d; deferred: %d", s.registrations, s.refused, s.removed, s.deferred)
    Line("built-in rules: %d; your rules: %d; a chosen sound is missing: %s; standalone GTFO loaded: %s", s.builtin, s.custom, D.Flag(s.missingSound), D.Flag(s.gtfo))
    Line("preview sounds played: %d; refused: %d", s.tests, s.testsRefused)
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not s.available then status, reason = "unavailable", "no-aura-sounds"
    elseif s.pending then status, reason = "waiting", "restricted" end
    return {
        configured = s.enabled, initialized = s.enabled and s.available, status = status, reason = reason, lines = lines,
        limits = {
            "The game plays the sounds; nothing here can tell whether one played. No combat log is read.",
            "Aura sounds for ordinary (non-private) auras have not been confirmed in the game; docs/hazard-alerts.md lists the checks.",
        },
    }
end

D.Register("hazardAlerts", { title = "Hazard alerts", order = 50, snapshot = Snapshot })
