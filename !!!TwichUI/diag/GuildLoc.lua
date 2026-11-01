-- TwichUI: troubleshooting report, Guild Locations
-- Reads guildloc/Comm.lua's snapshot: the state in force (and why, when it is not simply what was saved), whether a session
-- runs, whether the transport can be used, how much is held, what was sent, skipped or refused and why, the withdrawal
-- state, and messages set aside by reason code. Counts and codes only: never a player name, a place, a coordinate, an
-- epoch or a message. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Codes(t)
    local list = {}
    for k, v in pairs(t or {}) do list[#list + 1] = ("%s %d"):format(k, v) end
    table.sort(list)
    return #list > 0 and table.concat(list, ", ") or "none"
end

local function Snapshot()
    local GL = R.GuildLoc
    if not (GL and GL.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = GL.Snapshot()
    local st = s.stats
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("state: %s%s; interval %d s; session: %s%s; saved withdrawal owed: %s", s.state, s.reason and (" (" .. s.reason .. ")") or "",
        s.interval, D.Flag(s.session), s.noSend and (" (cannot start: " .. s.noSend .. ")") or "", D.Flag(s.pending))
    Line("transport: %s; last tick sent nothing because: %s", s.transport, s.lastSkip or "n/a")
    Line("held: %d live, %d withdrawn, %d senders rated; roster %d; timers %d (%d armed), events %d",
        s.records, s.tombstones, s.buckets, s.roster, s.timers, s.armed, s.events)
    Line("positions: ticks %d, sent %d, game refused %d, queued by the library %d (released and sent %d, waiting now %d), errors %d",
        st.ticks, st.sent, st.refused, st.queued, st.queuedSent, s.outstanding, st.errors)
    Line("withdrawals: sent %d, accepted by the game %d, refused %d, gave up %d, no epoch %d, old callbacks ignored %d",
        st.wSent, st.wAccepted, st.wRefused, st.wGaveUp, st.wNoEpoch, st.wStale)
    Line("taken in: %d positions, %d withdrawals; expired %d, cleared as offline %d; guild changes %d",
        st.received, st.withdrawn, st.expired, st.offlineCleared, st.guildChanges)
    Line("skipped ticks: %s", Codes(s.skips))
    Line("messages set aside: %s", Codes(s.drops))
    local ready = s.state ~= "off" or s.pending
    return { configured = s.state ~= "off", initialized = s.session, status = ready and "ready" or "off", lines = lines,
        limits = {
            "Checked offline only; docs/guild-locations.md lists what has to be seen in the game with two accounts.",
            "Sent means the game took the message, not that anyone received it. The roster's names are matched, not proven.",
        },
    }
end

D.Register("guildLoc", { title = "Guild Locations", order = 50, snapshot = Snapshot })
