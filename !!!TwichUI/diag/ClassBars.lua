-- TwichUI: troubleshooting report, class resource bars
-- Reads ClassBars.Snapshot() and the animation and effect counts: whether the bars are on and running, which
-- resource each slot is drawing (the resource's name, never a value), how many events are registered, whether the
-- animation driver is running and how many effect objects exist. These are the numbers that say what the bars cost:
-- with the bars off, or hidden and idle, events should be 0 or a handful and the driver idle. Nothing is asked of the
-- game, and no values, positions or settings text are included.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local CB = R.ClassBars
    if not (CB and CB.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = CB.Snapshot()
    local on = R:Enabled("classBars")
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; drawing: %s; events registered: %d%s", on and "on" or "off", D.Flag(s.running), s.events,
        (s.refused or 0) > 0 and (" (%d refused by the client)"):format(s.refused) or "")
    for _, slot in ipairs({ "primary", "secondary", "tertiary" }) do
        local info = s.slots[slot] or {}
        Line("%s: %s; shown: %s%s", slot, info.key and (info.provider .. " / " .. info.key) or "no resource", D.Flag(info.shown),
            info.secret and "; value restricted by the game (drawn by the game's own bar)" or "")
    end
    local A, FX = R.ClassBarAnim, R.ClassBarEffects
    Line("animation driver: %s (%d running); effects: %s, %d effect objects on %d bars", A and A.Running() and "running" or "idle",
        A and A.Count() or 0, D.Flag(FX and FX.Enabled()), select(2, FX.Count()), (FX.Count()))
    Line("preview: %s; positioning: %s; resource overrides saved: %d", D.Flag(s.preview), D.Flag(s.positioning), #CB.OverrideKeys())
    local status, reason = "ready", nil
    if not on then status = "off"
    elseif not s.running then status, reason = "waiting", "not-in-world" end
    return {
        configured = on, initialized = s.running, status = status, reason = reason, lines = lines,
        limits = {
            "Forever's client provides combo points and the power in use; other class resources are not drawn.",
            "Costs are not measured here: events registered and the driver being idle are the signs that nothing is running without need.",
        },
    }
end

D.Register("classBars", { title = "Class resource bars", order = 48, snapshot = Snapshot })
