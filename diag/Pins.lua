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
    local mm = R.PinsMinimap and R.PinsMinimap.Snapshot() or {}
    Line("minimap: setting %s, on %s, updater running %s; could be shown %d, shown %d, range %s yards, rotating %s; updates %d, moved %d, rebuilds %d",
        D.Flag(look.minimap), D.Flag(mm.active), D.Flag(mm.running), mm.eligible or 0, mm.shown or 0,
        mm.rangeYards and tostring(math.floor(mm.rangeYards + 0.5)) or "?", D.Flag(mm.rotating), mm.ticks or 0, mm.moves or 0, mm.rebuilds or 0)
    Line("minimap inputs now: result %s; minimap shown %s; its map: %s from %s; view radius: %s from %s%s; width %s; facing: %s",
        tostring(mm.now), D.Flag(mm.visible), tostring(mm.mapKind), tostring(mm.mapSource), tostring(mm.radiusKind), tostring(mm.radiusSource),
        mm.radius and (" (" .. math.floor(mm.radius + 0.5) .. " yards)") or "", mm.width and tostring(math.floor(mm.width + 0.5)) or "?",
        tostring(mm.facingKind))
    if mm.probe then
        Line("minimap, first pin that could show: its map is the minimap's or a parent %s; map size known %s; your place on it: %s",
            D.Flag(mm.probe.related), D.Flag(mm.probe.sized), tostring(mm.probe.position))
    end
    Line("minimap updates by result: %s; last: %s; errors caught: %d", #(mm.reasons or {}) > 0 and table.concat(mm.reasons, ", ") or "none yet",
        tostring(mm.last), mm.errors or 0)
    Line("placing: local %s, party %s, Place a pin waiting %s; labels %s", tostring(look.localClick), tostring(look.partyClick),
        D.Flag(m.armed), tostring(look.labels))
    local wy = R.PinsWay and R.PinsWay.Snapshot() or {}
    Line("waypoint commands: /twichway registered; /way is %s; commands %d, pins made %d, lines or commands refused %d, pastes %d, paste window open %s; also make a pin from another addon's /way: %s (following it: %s, pins made that way %d)",
        wy.way == "ours" and "TwichUI's" or (wy.way == "other" and "another addon's" or "not taken"), wy.commands or 0, wy.made or 0,
        wy.failed or 0, wy.pastes or 0, D.Flag(wy.open), D.Flag(wy.also), D.Flag(wy.followed), wy.alsoMade or 0)
    Line("window: built %s, open %s, rows %d; font %s (fell back: %s), background %s, border %s, rows %s",
        D.Flag(w.built), D.Flag(w.open), w.rows or 0, tostring(look.font), D.Flag(look.fontFallback), tostring(look.bg),
        tostring(look.border), tostring(look.density))
    Line("map text: font %s (fell back: %s), size %s, outline %s, shadow %s; names on the minimap: %s",
        tostring(look.mapFont), D.Flag(look.mapFontFallback), tostring(look.mapSize), tostring(look.mapOutline),
        D.Flag(look.mapShadow), tostring(look.minimapLabels))
    Line("data bar: %s; text %s, icon %s, own text color %s", R.PinsBroker and R.PinsBroker.Available() and "listed" or "not listed (no LibDataBroker provider, or off)",
        tostring(look.barText), D.Flag(look.barIcon), D.Flag(look.barColor))
    local bm = R.PinsBrokerMenu and R.PinsBrokerMenu.Snapshot() or {}
    local sd = R.PinsSound and R.PinsSound.Snapshot() or {}
    Line("arrival sound: %s, volume follows %s, sound %s (default played instead: %s); played %d, refused %d, held back %d",
        look.sound and "on" or "off", tostring(look.soundChannel), tostring(look.soundFile), D.Flag(sd.fallback),
        sd.played or 0, sd.refused or 0, sd.held or 0)
    Line("data bar menu: built %s, open %s, rows %d, renaming %s; background %s, border %s",
        D.Flag(bm.built), D.Flag(bm.open), bm.rows or 0, D.Flag(bm.editing), tostring(look.menuBg), tostring(look.menuBorder))
    Line("new pin window: open %s; background %s, border %s",
        D.Flag(R.PinsEditor and R.PinsEditor.IsOpen()), tostring(look.editorBg), tostring(look.editorBorder))
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
            "A pin shows on its own map and that map's parents only, and on the minimap only within its range.",
            "Minimap pins use the game's map position and view radius; a minimap with no map (a dungeon) shows none.",
        },
    }
end

D.Register("pins", { title = "Party pins", order = 48, snapshot = Pins })
