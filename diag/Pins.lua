-- TwichUI: troubleshooting report, Party pins
-- Reads the pins' Snapshot functions: whether the feature is on, the protocol and channel, counts of
-- local, party, removed-from-map and removal records, the map's state, the click choices, and messages
-- set aside by reason code. Never pin names, places, coordinates, player names or message contents.

local R = TwichUI
local D = R.Diag

local function Pins()
    local PN, PS, PM = R.Pins, R.PinSync, R.PinsMap
    if not (PN and PS and PM) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local on = R:Enabled("partyPins")
    local p, s, m = PN.Snapshot(), PS.Snapshot(), PM.Snapshot()
    local look = R.PinsLook and R.PinsLook.Snapshot() or {}
    local w = R.PinsWindow and R.PinsWindow.Snapshot() or {}
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; protocol %d on prefix %s (%s); channel: %s", on and "on" or "off", s.protocol, s.prefix, s.prefixState, s.transport)
    Line("session: %s, paused in a raid: %s, restored after a reload: %s; members with pins: %d",
        D.Flag(p.session), D.Flag(s.paused), D.Flag(s.restored), p.owners)
    Line("pins: local %d, party %d (yours %d), removed from your map %d, removal records %d",
        p.localPins, p.shared, p.own, p.dismissed, p.deleted)
    Line("messages: sent %d (the game refused %d), taken in %d; hellos %d, full lists %d; answer waiting: %s; last hello %s",
        s.sent, s.refused, s.received, s.hellos, s.lists, D.Flag(s.listPending), s.helloAge and (s.helloAge .. "s ago") or "never")
    Line("set aside: %s", #p.drops > 0 and table.concat(p.drops, ", ") or "nothing")
    Line("map: loaded %s, pins on it %s, open %s; drawn %d, on this map but not placeable %d, layouts %d, clicks refused %d",
        D.Flag(m.mapLoaded), D.Flag(m.installed), D.Flag(m.open), m.drawn, m.unplaced, m.layouts, m.refused)
    Line("placing: local %s, party %s, Place a pin waiting %s; labels %s", tostring(look.localClick), tostring(look.partyClick),
        D.Flag(m.armed), tostring(look.labels))
    Line("window: built %s, open %s, rows %d; font %s (fell back: %s), background %s, border %s, rows %s",
        D.Flag(w.built), D.Flag(w.open), w.rows or 0, tostring(look.font), D.Flag(look.fontFallback), tostring(look.bg),
        tostring(look.border), tostring(look.density))
    Line("data bar: %s", R.PinsBroker and R.PinsBroker.Available() and "listed" or "not listed (no LibDataBroker provider, or off)")
    local status, reason = "ready", nil
    if not on then status = "off"
    elseif not m.mapLoaded then status, reason = "waiting", "map-not-loaded"
    elseif not m.installed then status, reason = "waiting", "map-provider-not-added" end
    return {
        configured = on, initialized = D.When(on, m.installed), status = status, reason = reason, lines = lines,
        limits = {
            "Party pins reach only party members who have TwichUI with Party pins turned on; others see nothing.",
            "The game accepting a message isn't proof it arrived; nothing confirms delivery.",
            "Party pins are paused in a raid and end when you leave the party.",
            "A pin shows on its own map and that map's parents only. No minimap pins yet.",
        },
    }
end

D.Register("pins", { title = "Party pins", order = 48, snapshot = Pins })
