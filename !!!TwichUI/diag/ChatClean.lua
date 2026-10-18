-- TwichUI: troubleshooting report, chat cleaning
-- Reads ChatClean.Stats(): whether it is on, whether its filter is in the game's list, and counts (channels cleaned,
-- rules, messages checked and hidden this session, errors). Never channel names, rule text, senders or messages, and
-- nothing the live view showed (it keeps nothing once closed). Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Snapshot()
    local CC = R.ChatClean
    if not (CC and CC.Stats) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = CC.Stats()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; filter registered: %s; channel choice: %s", s.enabled and "on" or "off", D.Flag(s.active),
        s.customized and "changed by you" or "the recommended one")
    Line("channels with something to check: %d; custom rules: %d (%d on)", s.channels, s.rules, s.rulesOn)
    Line("this session: messages checked %d, hidden %d; errors (message let through) %d; pattern errors %d",
        s.checked, s.hidden, s.errors, s.patternErrors)
    Line("repeat memory: %d of %d entries; live view capturing: %s", s.repeatMemory, CC.REPEAT_MAX, D.Flag(s.capturing))
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not s.active then status, reason = "waiting", "nothing-chosen" end
    return {
        configured = s.enabled, initialized = s.active, status = status, reason = reason, lines = lines,
        limits = {
            "Only TwichUI's own decisions are counted; messages another addon hides are not seen here.",
            "The built-in filters look for several signs together and can miss well-disguised spam or catch an unusual ordinary message.",
        },
    }
end

D.Register("chatClean", { title = "Chat cleaning", order = 47, snapshot = Snapshot })
