-- TwichUI: troubleshooting report, Reminders
-- Reads the controller's, the state reader's and the frames' snapshots: how many reminders there are and run here,
-- how many are showing or waiting, how many events and observations are in use. Counts only: no names, words, item
-- IDs, characters or places. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local CT, ST, RD = R.ReminderController, R.ReminderState, R.ReminderDisplay
    if not (CT and ST and RD) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local c, s, d = CT.Snapshot(), ST.Snapshot(), RD.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; in the world: %s; reminders: %d (turned on %d, valid %d, running here %d)", c.enabled and "on" or "off",
        D.Flag(c.running), c.reminders, c.turnedOn, c.valid, c.active)
    Line("showing: %d; waiting out a delay: %d; kept up for a minimum: %d", c.visible, c.pending, c.holding)
    Line("observations read: %d; events registered: %d; item details asked for: %d; an equipped item without details: %s",
        s.keys, s.events, s.asked, D.Flag(s.unresolved))
    Line("frames: %d (made %d, kept for reuse %d, on screen %d); preview: %s; moving: %s; icons waiting: %d",
        d.frames, d.made, d.spare, d.shown, D.Flag(d.preview), D.Flag(d.positioning), d.iconsWaiting)
    Line("refreshes: %d; decisions: %d; shown %d times, hidden %d times", c.refreshes, c.decisions, c.shows, c.hides)
    local status, reason = "ready", nil
    if not c.enabled then status = "off"
    elseif not c.running then status, reason = "waiting", "not-in-world" end
    return {
        configured = c.enabled, initialized = c.running, status = status, reason = reason, lines = lines,
        limits = {
            "With no reminder turned on for this character, nothing is listened for.",
            "Equipment, combat, life and mount state come from the game's own functions; none of it has been confirmed in the game yet (docs/reminders.md).",
        },
    }
end

D.Register("reminders", { title = "Reminders", order = 51, snapshot = Snapshot })
