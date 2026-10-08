-- TwichUI: troubleshooting report, Food and Drink buttons
-- The report section reads F.Snapshot(), which looks at the bags without asking the game to load
-- anything or changing the buttons. The tracer watches the events that matter for the buttons while
-- tracing is on (dying, resurrecting, combat, bags, item data arriving) and records the buttons' state
-- beside each, to follow a death-and-resurrection or a combat-deferred change. Item IDs and counts
-- only; no item names, tooltips or bag positions.

local R = TwichUI
local D = R.Diag

D.RegisterTracer("food", {
    events = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "SPELL_TEXT_UPDATE" },
    onEvent = function(event)
        local F = R.FoodDrink
        if not (F and F.Brief) then return end
        local brief, loading = F.Brief()
        -- Item data arrives constantly; it matters only while the buttons are waiting for it.
        if (event == "GET_ITEM_INFO_RECEIVED" or event == "SPELL_TEXT_UPDATE") and not loading then return end
        D.Trace("food", event, brief)
    end,
})

local function Describe(c)
    return ("item %s: count %s, restores %s%s"):format(c.id, tostring(c.count), tostring(c.amount), c.conjured and ", Mage-conjured" or "")
end

local function Food()
    local F = R.FoodDrink
    if not (F and F.Snapshot) then
        return { configured = nil, initialized = false, status = "unavailable", reason = "not-loaded" }
    end
    local s = F.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("buttons: %s; built=%s, on screen=%s", s.enabled and "on" or "off", D.Flag(s.built), D.Flag(s.shown))
    Line("listening for: %s", #s.events > 0 and table.concat(s.events, ", ") or "nothing")
    Line("deferred update waiting for combat to end: %s; look scheduled: %s; waiting for item or spell data: %s; in combat now: %s",
        D.Flag(s.deferred), D.Flag(s.scheduled), D.Flag(s.loading), D.Flag(s.inCombat))
    Line("prefer Mage-conjured: %s; conjured item IDs the rules know: %d (from the Classic-era game; not read from the Forever client)",
        s.preferConjured and "on" or "off", s.conjuredKnown)

    local scan = s.scan
    if scan then
        local left = {}
        for why, n in pairs(scan.excluded) do left[#left + 1] = ("%s x%d"):format(why, n) end
        table.sort(left)
        Line("bags: %d distinct items looked at; left out: %s", scan.items, #left > 0 and table.concat(left, ", ") or "none")
        Line("the game's plain Food and Drink spell names read: %s; health and mana words read: %s",
            D.Flag(scan.spellNamesRead), D.Flag(scan.wordsRead))
    elseif s.enabled then
        Line("bags: not looked at (%s)", s.apiMissing and "an item or container API is missing" or "the look failed")
    end

    local stale, mismatch = false, false
    for _, b in ipairs(s.buttons) do
        if b.switchOn then
            local fresh = scan and scan.chosen and scan.chosen[b.key]
            Line("%s: showing %s; a fresh look would choose %s; secure action matches what is shown: %s", b.key,
                b.id and ("item " .. b.id .. " (count " .. tostring(b.count) .. ")") or "nothing",
                fresh and ("item " .. fresh.id) or "nothing", D.Flag(b.secureMatches))
            if scan and (b.id or 0) ~= ((fresh and fresh.id) or 0) then stale = true end
            if b.secureMatches == false then mismatch = true end
            local list = scan and scan.candidates and scan.candidates[b.key] or {}
            table.sort(list, function(x, y)
                if x.amount ~= y.amount then return x.amount > y.amount end
                return x.id < y.id
            end)
            for i = 1, math.min(#list, 5) do Line("  %s candidate %s", b.key, Describe(list[i])) end
            if #list > 5 then Line("  %s: %d more candidates not listed", b.key, #list - 5) end
            if scan and #list == 0 then Line("  %s: no candidates in the bags", b.key) end
        else
            Line("%s: that button's switch is off", b.key)
        end
    end

    local status, reason = "ready", nil
    if not s.enabled then status = "off"
    elseif s.apiMissing then status, reason = "unavailable", "item-api-missing"
    elseif s.scanFailed then status, reason = "unavailable", "bag-look-failed"
    elseif scan and not scan.spellNamesRead then status, reason = "unavailable", "plain-spell-names-unreadable"
    elseif not s.built then status, reason = "waiting", "not-built-yet"
    elseif s.loading then status, reason = "waiting", "item-data-pending"
    elseif s.deferred then status, reason = "waiting", "deferred-until-combat-ends"
    elseif mismatch then status, reason = "unavailable", "secure-action-differs-from-display"
    elseif stale then status, reason = "waiting", "shown-choice-differs-from-fresh-look" end
    return {
        configured = s.enabled, initialized = D.When(s.enabled, s.built), status = status, reason = reason, lines = lines,
        limits = {
            "A secure button cannot be changed in combat, so a change made then waits for combat to end.",
            "The traced state is read when the trace sees the event, which can be just before or after the buttons react.",
        },
    }
end

D.Register("food", { title = "Food and water buttons", order = 40, snapshot = Food })
