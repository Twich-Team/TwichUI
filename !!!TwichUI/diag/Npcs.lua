-- TwichUI: troubleshooting report, Vendors and trainers
-- Reads npcs/Store.lua's, Collect.lua's, Map.lua's and Share.lua's snapshots: whether it is on, how many NPCs are in the
-- list (yours and reported), what was noted and skipped and why, what the map drew, and what was sent, received, held,
-- asked and dropped. Counts and reason codes only: no NPC names, places, player names or payloads. Nothing is asked of
-- the game.

local R = TwichUI
local D = R.Diag

local function Codes(t)
    local list = {}
    for k, v in pairs(t or {}) do list[#list + 1] = ("%s %d"):format(k, v) end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none"
end

local function Snapshot()
    local NS = R.NpcStore
    if not (NS and NS.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = NS.Snapshot()
    local c = R.NpcCollect and R.NpcCollect.Snapshot() or {}
    local m = R.NpcMap and R.NpcMap.Snapshot() or {}
    local sh = R.NpcShare and R.NpcShare.Snapshot() or {}
    local on = R:Enabled("npcMap")
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; listening: %s; probe: %s; list: %d yours, %d reported, %d unreadable%s", on and "on" or "off",
        D.Flag(c.listening), D.Flag(c.probe), s.own, s.reported, s.unreadable, s.newer and "; written by a newer TwichUI (read only)" or "")
    Line("noted: %d (new %d, again %d, reports confirmed %d); merchant reads: %d; skipped: %s", c.noticed or 0, c.new or 0,
        c.updated or 0, c.confirmed or 0, c.reads or 0, Codes(c.skipped))
    Line("store refused: %s", Codes(s.drops))
    Line("map: on it %s, open %s, drawn %d, over the limit %d times, layouts %d, markers made %d; menus %d, waypoints %d, forgotten %d",
        D.Flag(m.installed), D.Flag(m.open), m.drawn or 0, m.capped or 0, m.layouts or 0, m.pool or 0, m.menus or 0, m.waypoints or 0, m.forgotten or 0)
    Line("sharing: protocol %s, prefix %s (%s); messages sent %d, refused by the game %d; received %d, transfers %d, held now %d, questions waiting %d, asked %d, declined %d, entries added %d",
        tostring(sh.protocol), tostring(sh.prefix), tostring(sh.prefixState), sh.sent or 0, sh.refused or 0, sh.received or 0,
        sh.transfers or 0, sh.held or 0, sh.waiting or 0, sh.asked or 0, sh.declined or 0, sh.added or 0)
    Line("messages set aside: %s", Codes(sh.drops))
    return {
        configured = on, initialized = c.listening, status = on and "ready" or "off", lines = lines,
        limits = {
            "Checked offline only; docs/npc-map.md lists what has to be seen in the game (the probe, /tui npcs probe, prints it).",
            "A mark is where you stood when the NPC's window opened, not the NPC's own position.",
            "Sent means the game took the message, not that anyone received it.",
        },
    }
end

D.Register("npcMap", { title = "Vendors and trainers", order = 49, snapshot = Snapshot })
