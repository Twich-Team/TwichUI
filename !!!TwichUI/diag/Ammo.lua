-- TwichUI: troubleshooting report, Hunter ammunition warning
-- Reads Ammo's Warning.Snapshot(): whether the warning is on, whether this character is a Hunter, how many events it
-- has registered, the last state it concluded and how many sounds it has played. Counts and words only: no item
-- IDs, no ammunition names and no positions. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local W = R.AmmoWarning
    if not (W and W.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = W.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; Hunter: %s; watching: %s; events registered: %d", s.enabled and "on" or "off", D.Flag(s.hunter), D.Flag(s.running), s.events)
    Line("last state: %s; shown: %s; looks: %d; unresolved retries: %d", tostring(s.state), s.shown and "yes" or "no", s.looks, s.retries)
    Line("preview: %s; unlocked: %s; frame built: %s", D.Flag(s.preview), D.Flag(s.positioning), D.Flag(s.built))
    Line("sounds played: %d; held back: %d; refused by the game: %d; custom ammunition registered: %d", s.sounds, s.soundsHeld, s.soundsRefused,
        R.AmmoItems and R.AmmoItems.Count() or 0)
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not s.hunter then status, reason = "idle", "not-a-hunter"
    elseif not s.running then status, reason = "waiting", "not-in-world" end
    return {
        configured = s.enabled, initialized = s.running, status = status, reason = reason, lines = lines,
        limits = {
            "Off, or on a character that is not a Hunter, nothing is registered and no frame exists.",
            "What the game reports about ammunition has not been confirmed in the game; docs/ammo-warning.md lists the checks.",
        },
    }
end

D.Register("ammoWarning", { title = "Hunter ammunition warning", order = 49, snapshot = Snapshot })
