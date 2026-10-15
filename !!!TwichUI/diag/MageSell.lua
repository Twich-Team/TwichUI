-- TwichUI: troubleshooting report, Mage selling of ordinary food and drink
-- Reads MageSell.Snapshot(): whether it is on and in dry run, what it is listening for, whether a merchant
-- is open, the run in progress, the last run's outcome, session counts, which of the conjured-item checks
-- this client supports, and what a read-only look at the bags would sell and keep, as counts by reason
-- code. Never item names, item IDs, bag places or a list of the inventory. Nothing is asked of the game.

local R = TwichUI
local D = R.Diag

local function Sell()
    local MS = R.MageSell
    if not (MS and MS.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = MS.Snapshot()
    if not s.mage then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-a-mage",
            lines = { "for Mages only; nothing is registered on this character" } }
    end
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("switch: %s; sell food: %s; sell drink: %s; DRY RUN: %s", s.switchOn and "on" or "off", D.Flag(s.food), D.Flag(s.drink),
        s.dryRun and "on (nothing is sold)" or "off (sells for real)")
    Line("handling mode: %s; marking confirmed on this computer: %s; EllesmereUI Junk Marker: %s; how marked items sell: %s",
        s.mode == "ellesmere" and "mark as junk with EllesmereUI" or "sell directly", D.Flag(s.acknowledged), s.bridge,
        s.selling == "auto" and "EllesmereUI's Auto Sell Junk" or (s.selling == "button" and "its Sell Junk button only" or "unknown"))
    if s.mode == "ellesmere" then
        local k, l = s.marks, s.markLast
        Line("marking: %s. this session: looks %d, kinds marked %d, already junk %d, filed by you elsewhere %d, failed %d, "
            .. "kept out for a stack that is kept %d, not kept by EllesmereUI %d, changed before marking %d, taken off by you %d, held for combat %d",
            s.markText, k.looks, k.marked, k.already, k.filed, k.failed, k.mixed, k.stuck, k.stale, k.released, k.deferred)
        if l then
            Line("last look: %s; marked %d, already junk %d, filed elsewhere %d, failed %d, still loading %d%s",
                l.dry and "dry run" or "for real", l.marked, l.already, l.filed, l.failed, l.pending or 0,
                l.dry and (", would mark %d"):format(l.would or 0) or "")
        end
    end
    Line("listening for: %s", #s.events > 0 and table.concat(s.events, ", ") or "nothing")
    Line("merchant open: %s (visit %d); run in progress: %s; blocked by the game this session: %s",
        D.Flag(s.merchantOpen), s.visit, s.running and ("stack %d of %d, limit %d%s"):format(s.running.index, s.running.total,
            s.running.limit, s.running.waiting and ", waiting for the bag to change" or "") or "no", D.Flag(s.blocked))
    Line("per-visit limit: %d stacks (buyback list shows %s slots); never-sell list: %d items; item verdicts remembered: %d",
        s.limit, s.markers.buybackCapacity and tostring(s.markers.buybackCapacity) or "?", s.excluded, s.cache)
    local m = s.markers
    Line("conjured checks: known IDs %d (Classic-era ranks and other addons' Forever data; not read from this client); "
        .. "tooltip API %s, \"Conjured Item\" text defined by this client %s; quest API %s, quest text defined %s",
        s.conjuredKnown, D.Flag(m.tooltipApi), D.Flag(m.conjuredText), D.Flag(m.questApi), D.Flag(m.questText))
    local t = s.stats
    Line("this session: runs %d (dry %d), stacks sold %d, items %d, value %d copper; stopped by: merchant closing %d, combat %d, "
        .. "unconfirmed sale %d, game blocked %d, option changed %d; changed-slot skips %d; runs over the limit %d",
        t.runs, t.dryRuns, t.stacks, t.items, t.value, t.closed, t.combat, t.unconfirmed, t.blocked, t.cancelled, t.stale, t.limited)
    local last = s.last
    if last then
        Line("last run: %s%s; %d eligible, %d sold (%d items), %d over the limit, %d changed, %d kept",
            last.outcome, last.dry and " (dry run)" or "", last.eligible, last.stacks, last.items, last.limited, last.stale, last.kept)
    else
        Line("last run: none yet")
    end
    local scan = s.scan
    if scan then
        local left = {}
        for why, n in pairs(scan.counts) do left[#left + 1] = ("%s x%d"):format(why, n) end
        table.sort(left)
        Line("bags right now: %d food and drink stacks would be sold (%d items, about %d copper); %d kept: %s; %d still loading",
            scan.eligible, scan.items, scan.value, scan.kept, #left > 0 and table.concat(left, ", ") or "none", scan.pending)
    elseif s.enabled then
        Line("bags: not looked at (%s)", s.scanFailed and "the look failed" or "an item or container API is missing")
    end

    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif s.enabled and not (m.conjuredText and m.tooltipApi) then
        status, reason = "waiting", "conjured-check-unavailable"   -- nothing can be shown not to be conjured, so nothing is sold
    elseif s.mode == "ellesmere" and s.markState ~= "active" and s.markState ~= "dry-run" then
        status, reason = "waiting", s.markState   -- needs-ack, or why EllesmereUI's Junk Marker can't be used
    elseif s.blocked and s.mode ~= "ellesmere" then status, reason = "waiting", "blocked-by-the-game" end
    return {
        configured = s.switchOn, initialized = D.When(s.enabled, #s.events > 0), status = status, reason = reason, lines = lines,
        limits = {
            "No client flag marks a conjured item. IDs, the bound flag, a missing sell price and the tooltip's own text are the layers; an item that can't be shown not to be conjured is kept.",
            "Quest relevance is only what the game's quest flag and tooltip say; an item a quest needs without being flagged can't be told apart.",
            "A sale is counted only when the bag slot changes. Value is from sell prices, not from gold received.",
            "The buyback list holds a limited number of entries; other sales can still push this run's entries out.",
            "EllesmereUI mode: a mark is per item ID for the whole account, and TwichUI never unmarks. Whether marked items sell depends on EllesmereUI's own Auto Sell Junk and Sell Junk button.",
        },
    }
end

D.Register("mageSell", { title = "Mage: sell ordinary food and drink", order = 46, snapshot = Sell })
