-- TwichUI: troubleshooting report, configuration sharing
-- Transport, prefixes, receivers, any transfer in progress and the direct-message check, from
-- Share.Snapshot(), Group.Snapshot() and CommTest.Snapshot(). Other players appear only as P1, P2 for
-- the length of the report; no names, no reason texts (they name people), no payloads, no configuration.
-- Trace records come from Share.lua and CommTest.lua. A self-test is marked SYNTHETIC.

local R = TwichUI
local D = R.Diag

local TRANSPORT_LABEL = { DIRECT = "Direct (addon whisper to the named character)", PARTY = "Party or raid channel", GUILD = "Guild channel" }

local function Transfer(label, t)
    local progress = (t.total or t.expected) and ("%s of %s bytes"):format(tostring(t.sent or t.got or 0), tostring(t.total or t.expected)) or "no data yet"
    return ("%s %s: stage %s via %s, %s, started %s ago, %s%s%s"):format(label, t.peer, t.stage, tostring(t.route or "?"),
        progress, t.age and (t.age .. "s") or "?", t.idle and ("last activity " .. t.idle .. "s ago") or "no activity yet",
        t.code and (", ended with " .. t.code) or "",
        t.selfTest and " (SYNTHETIC self-test: sent to this character)" or "")
end

local function Sharing()
    local SH = R.Share
    if not (SH and SH.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local enabled = R:Enabled("setupSharing")
    local s = SH.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("sharing: %s; accepting offers from others: %s; group check (hello, probe): %s", enabled and "on" or "off",
        R:Enabled("acceptSetups") and "on" or "off", R:Enabled("groupCheck") and "on" or "off")
    Line("outgoing transport chosen: %s", TRANSPORT_LABEL[s.transport] or tostring(s.transport))
    local bad, unknown = {}, 0
    for _, p in ipairs(s.prefixes) do
        if p.state == "not registered" then bad[#bad + 1] = p.prefix
        elseif p.state ~= "registered" then unknown = unknown + 1 end
    end
    Line("addon message prefixes: %d of %d registered with the game%s%s", #s.prefixes - #bad - unknown, #s.prefixes,
        #bad > 0 and ("; not registered: " .. table.concat(bad, ", ")) or "",
        unknown > 0 and ("; " .. unknown .. " could not be checked") or "")
    Line("receivers registered with the message library: %d of %d", s.receivers, s.receiversExpected)
    Line("addon messages locked by the game right now (encounter, Mythic+, PvP): %s", D.Flag(s.blocked))
    Line("game uses first-and-last character names (no realm part): %s", D.Flag(s.realmless))
    if s.outgoing then Line("%s", Transfer("outgoing", s.outgoing)) else Line("outgoing transfer: none") end
    if #s.incoming == 0 then Line("incoming transfers: none") end
    for _, inc in ipairs(s.incoming) do Line("%s", Transfer("incoming", inc)) end
    Line("timeouts: an offer waits %ds for an answer; a transfer ends after %ds without progress; sender watchdog running=%s",
        s.offerTimeout, s.dataTimeout, D.Flag(s.watchdog))
    Line("acknowledgment: stage \"delivered\" means every piece was handed to the game; only the other side's \"done\" message confirms arrival, and \"done\" marks success")
    Line("last message handled: %s; last message ignored: %s; last error site: %s",
        s.seenType and ("%s via %s, %ss ago"):format(s.seenType, tostring(s.seenDist), tostring(s.seenAge)) or "none",
        s.droppedCode or "none", s.errorWhere or "none")

    local G = R.Group
    if G and G.Snapshot then
        local g = G.Snapshot()
        local record
        if not g.realmless then record = "not applicable here (direct messages use ordinary names)"
        elseif not g.recorded then record = "never run"
        elseif not g.sameBuild then record = "run on an earlier game build; will run again once you are grouped with another TwichUI user"
        else record = ("%s on this build, %s days ago"):format(g.ok and "answered" or "no answer", tostring(g.ageDays)) end
        Line("direct-message check: %s; running now=%s; grouped TwichUI users seen=%d", record, D.Flag(g.probing), g.peers)
        Line("  what it verifies: one small addon whisper to a grouped TwichUI user's first-and-last name reached them and their TwichUI answered (the answer returns over the group channel)")
        Line("  what it does not verify: large transfers on the data prefixes, throttling, offline players, other name forms, or any other game build")
    else
        Line("direct-message check: not loaded")
    end
    local CT = R.CommTest
    if CT and CT.Snapshot then
        local c = CT.Snapshot()
        Line("/tui commtest: %s", c.running and ("running (%s, %ss of %ss)"):format(tostring(c.kind), tostring(c.age), tostring(c.timeout)) or "not running")
    end

    local status, reason = "ready", nil
    if not enabled then status = "off"
    elseif s.receivers < s.receiversExpected then status, reason = "unavailable", "receivers-not-registered"
    elseif #bad > 0 then status, reason = "unavailable", "prefix-not-confirmed"
    elseif s.blocked then status, reason = "waiting", "messaging-locked-by-game" end
    return {
        configured = enabled, initialized = D.When(enabled, s.receivers == s.receiversExpected), status = status, reason = reason, lines = lines,
        limits = {
            "A successful local send is not proof that anyone received it; a transfer is confirmed only when the other side answers.",
            "The direct-message check covers one small message on one game build, not the bulk transfer.",
        },
    }
end

D.Register("sharing", { title = "Configuration sharing", order = 70, snapshot = Sharing })
