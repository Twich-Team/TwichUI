-- TwichUI: troubleshooting report, notification coordination
-- What the coordinator (modules/Notify.lua) is doing: whether it is listening, how many notices wait or
-- show, and counts since the game started of notices shown, let go and refused, each by reason. Only
-- card kinds and reason codes appear: no friend names, ids or card text. A count that says "preview" is a
-- settings preview with made-up details; everything else was a real notice.

local R = TwichUI
local D = R.Diag

local function Counts(t)
    local list = {}
    for key, n in pairs(t) do list[#list + 1] = ("%s x%d"):format(key, n) end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none"
end

local function Notifications()
    local N = R.Notify
    if not (N and N.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = N.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    local kinds = {}
    for _, k in ipairs(s.kinds) do kinds[#kinds + 1] = k.kind .. (k.sample and "" or " (no preview)") end
    Line("listening for loading screens: %s; currently in the world: %s", D.Flag(s.listening), D.Flag(s.inWorld))
    Line("card kinds registered: %s", #kinds > 0 and table.concat(kinds, ", ") or "none")
    Line("queue: %d of at most %d waiting; waiting: %s", s.queued, s.capacity, Counts(s.waiting))
    local showing = {}
    for kind, how in pairs(s.active) do showing[#showing + 1] = kind .. " (" .. how .. ")" end
    table.sort(showing)
    Line("showing now: %s", #showing > 0 and table.concat(showing, ", ") or "nothing")
    Line("previews: sound in previews=%s; watching for combat to clear previews=%s; retry timer pending=%s",
        s.previewSounds and "on" or "off", D.Flag(s.watchingCombat), D.Flag(s.retryScheduled))
    Line("shown since the game started: %s", Counts(s.shown))
    Line("let go while waiting, by reason: %s", Counts(s.dropped))
    Line("refused when sent (duplicate, queue full): %s", Counts(s.refused))
    local status, reason = "ready", nil
    if not s.listening then status, reason = "unavailable", "not-started"
    elseif not s.inWorld then status, reason = "waiting", "loading-screen" end
    return {
        configured = nil, initialized = s.listening, status = status, reason = reason, lines = lines,
        limits = {
            "A preview going through the coordinator is not proof that the real event for that card is noticed.",
            "Counts are for this game session only; the recent order of decisions is in the trace, when tracing was on.",
        },
    }
end

D.Register("notify", { title = "Notification coordination", order = 20, snapshot = Notifications })
