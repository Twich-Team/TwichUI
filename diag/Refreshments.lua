-- TwichUI: troubleshooting report, Mage refreshments
-- Reads Refreshments.Snapshot() and the panel's: whether it is on, the group's size and kind, how many
-- members could be read, the checklist as counts, what the plan needs per item (item and spell IDs and
-- counts), items per cast seen, and whether each conjure button's secure spell is the one the plan wants.
-- Never names, GUIDs, classes of particular people, or chat.

local R = TwichUI
local D = R.Diag

local function Refreshments()
    local RF = R.Refreshments
    if not (RF and RF.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = RF.Snapshot()
    if not s.mage then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-a-mage",
            lines = { "for Mages only; nothing is registered on this character" } }
    end
    local panel = R.RefreshmentsPanel and R.RefreshmentsPanel.Snapshot() or {}
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; panel built=%s, open=%s", s.switchOn and "on" or "off", D.Flag(panel.built), D.Flag(panel.shown))
    Line("listening for: %s", #s.events > 0 and table.concat(s.events, ", ") or "nothing")
    Line("group: %s, %d members read, %d not read; look scheduled: %s; roster waiting for combat to end: %s",
        s.context, s.members, s.unreadable, D.Flag(s.scheduled), D.Flag(s.rosterAfterCombat))
    Line("session: %d in the group, %d who left kept, %d with an unconfirmed trade; resets this session: %d",
        s.sessionInGroup, s.sessionDeparted, s.sessionOffered, s.resets)
    local mismatch, deferred = false, panel.deferred
    local plan = s.plan
    if plan then
        local c = plan.counts
        Line("checklist: supplied %d, partial %d, not yet %d, no share %d; next marked: %s",
            c.supplied, c.partial, c.pending, c.nothing, D.Flag(plan.next ~= nil))
        for _, kind in ipairs(RF.KINDS) do
            local t = plan.totals[kind]
            Line("%s: need %d, covered %d, short %d", kind, t.need, t.covered, t.short)
            for _, l in ipairs(plan.items[kind]) do
                Line("  item %d (spell %d, rank %d): group %d for %d, keep %d, have %d, short %d",
                    l.item, l.spell, l.rank, l.group, l.recipients, l.reserve, l.have, l.short)
            end
        end
    end
    for _, b in ipairs(panel.buttons or {}) do
        if b.built then
            Line("%s button: secure spell %s, plan wants %s, display matches: %s", b.kind, tostring(b.spell), tostring(b.wanted), D.Flag(b.matches))
            if b.spell ~= b.wanted then mismatch = true end
        end
    end
    Line("button change waiting for combat to end: %s; panel closing when combat ends: %s", D.Flag(deferred), D.Flag(panel.closeAfterCombat))
    local T = R.RefreshmentsTrade
    if T and T.Snapshot then
        local t = T.Snapshot()
        local st = t.stats
        Line("trade assistance: switch %s; listening: %s; trade open: %s (partner read: %s, in the group: %s); blocked this trade: %s",
            t.switchOn and "on" or "off", D.Flag(t.enabled), D.Flag(t.open), D.Flag(t.partnerRead), D.Flag(t.partnerInGroup), D.Flag(t.blocked))
        Line("trade moves waiting: %d placed not shown yet, split waiting: %s; closed trade waiting for its message: %s",
            t.pending, D.Flag(t.splitPending), D.Flag(t.closing))
        Line("trades %d, fill clicks %d, stacks placed %d, splits %d, refused %d, blocked %d",
            st.trades, st.fills, st.placed, st.splits, st.refused, st.blocked)
        Line("deliveries: confirmed %d, unconfirmed %d, not completed %d; a completion message recognised this session: %s; last outcome: %s",
            st.confirmed, st.unconfirmed, st.notCompleted, D.Flag(st.completionSeen), tostring(t.lastOutcome or "none"))
        Line("this client defines the trade-complete text: %s, its message code: %s; message codes seen during trades: %s",
            D.Flag(t.completionString), D.Flag(t.completionCode), #t.codes > 0 and table.concat(t.codes, ", ") or "none")
    end
    if #s.yields > 0 then
        for _, y in ipairs(s.yields) do Line("seen: spell %d made %d per cast at level %s", y.spell, y.n, tostring(y.level)) end
    else
        Line("items per cast: none seen yet")
    end
    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif not panel.built then status, reason = "waiting", "not-built-yet"
    elseif deferred then status, reason = "waiting", "deferred-until-combat-ends"
    elseif mismatch then status, reason = "waiting", "button-differs-from-plan"
    elseif s.unreadable > 0 then status, reason = "waiting", "roster-not-read" end
    return {
        configured = s.switchOn, initialized = D.When(s.enabled, panel.built), status = status, reason = reason, lines = lines,
        limits = {
            "A secure button can't be changed in combat; its spell follows the plan when combat ends.",
            "Handed-out counts are marked by hand. TwichUI can't see what anyone else carries.",
            "The game repeats a held cast only from its own action bars, not from these buttons.",
            "A trade is counted only when the game says it was completed; otherwise it waits as offered for you to confirm.",
        },
    }
end

D.Register("refreshments", { title = "Mage refreshments", order = 45, snapshot = Refreshments })
