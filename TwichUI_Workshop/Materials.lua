-- TwichUI Workshop: combined materials
-- Pure functions over plain tables. Every queued recipe's materials are added up FIRST (needed = materials per craft x crafts,
-- summed over the whole queue); only then is what the bags hold applied, once per item, so the same owned items are never counted for
-- two recipes. A recipe whose materials aren't known adds nothing and is counted as "unknown": it never counts as needing zero.

local R = TwichUI
local W = R.Workshop
local M = {}
W.Materials = M

-- What a queued craft will make counts toward what the queue needs, so a craft queued to make a material (for example a bar for another
-- recipe) is not bought a second time. The credit is the LEAST one craft makes (a range counts its low end), only for an item some other
-- queued recipe uses, and never for recipes that depend on each other (A needs what B makes while B needs what A makes, or a recipe that
-- uses what it makes): those cannot start from nothing, so they are left uncredited and counted in `cycle`.
local MAX_GRAPH = 60

local function InCycle(entries)
    local n = #entries
    local makes, uses, reach = {}, {}, {}
    for i, e in ipairs(entries) do
        makes[i] = e.outItem
        uses[i] = {}
        if type(e.mats) == "table" then for _, m in ipairs(e.mats) do uses[i][m.item] = true end end
    end
    for i = 1, n do
        reach[i] = {}
        for j = 1, n do reach[i][j] = makes[i] ~= nil and uses[j][makes[i]] == true end   -- i supplies j
    end
    for k = 1, n do
        for i = 1, n do
            if reach[i][k] then
                for j = 1, n do
                    if reach[k][j] then reach[i][j] = true end
                end
            end
        end
    end
    local cyc = {}
    for i = 1, n do cyc[i] = reach[i][i] == true end
    return cyc
end

-- entries: { { crafts = n, mats = { { item, qty }, ... } | nil, outItem = id | nil, outMin = n | nil, outMax = n | nil }, ... }
-- Returns need (item -> number), order (items in first-seen order), unknown (how many entries have no usable materials),
-- made (item -> how many the queued crafts will make, at least; only items that are needed), range (item -> true when part of that
-- is a range's low end) and cycle (how many entries were left out of `made` because they depend on each other)
function M.Combine(entries)
    local need, order, unknown = {}, {}, 0
    for _, e in ipairs(entries) do
        if type(e.mats) == "table" and #e.mats > 0 then
            for _, m in ipairs(e.mats) do
                if need[m.item] == nil then
                    need[m.item] = 0
                    order[#order + 1] = m.item
                end
                need[m.item] = need[m.item] + m.qty * e.crafts
            end
        else
            unknown = unknown + 1
        end
    end
    local made, range, cycle = {}, {}, 0
    if #entries <= MAX_GRAPH then
        local cyc = InCycle(entries)
        for i, e in ipairs(entries) do
            if e.outItem and e.outMin and need[e.outItem] ~= nil and type(e.mats) == "table" then
                if cyc[i] then
                    cycle = cycle + 1
                else
                    made[e.outItem] = (made[e.outItem] or 0) + e.outMin * e.crafts
                    if (e.outMax or e.outMin) ~= e.outMin then range[e.outItem] = true end
                end
            end
        end
    end
    return need, order, unknown, made, range, cycle
end

local function Rank(row)
    if row.short == nil then return 2 end
    if row.short > 0 then return 1 end
    return (row.fromBank or 0) + (row.fromGuild or 0) > 0 and 3 or 4
end

-- have(item) -> how many the bags hold, or nil when that can't be read. stock (optional) is Stock.Fn's function: stock(item) -> how many the
-- bank holds, how many the guild bank holds, both only as far as they may be planned with (remembered counts, Stock.lua).
-- Rows: { item, need, made, have, short, bank, guild, fromBank, fromGuild }; have and short are nil when unknown (never 0); made is there only when queued crafts
-- will make some of it. The rest of the need after the queued crafts is split by W.Split: the bags first, then the bank (fromBank to collect), then
-- the guild bank (fromGuild to collect); short is what none of them covers (and so what must be bought or made), not below 0. bank and guild are the
-- planned-with stock of the item, whether or not this need used it. Without a stock function the rows are exactly what they were for the bags alone.
-- Short items first, then unknown ones, then those to collect, then the rest; each group by item number.
-- Summary state: "empty" (nothing queued), "partial" (something isn't known: a recipe's materials or a count),
-- "short" (everything known, something missing), "collect" (everything known and held, but some of it is in the bank or guild bank) or
-- "ready" (everything known and in the bags).
function M.Rows(entries, have, stock)
    local need, order, unknown, made, range, cycle = M.Combine(entries)
    local rows = {}
    local s = { entries = #entries, unknown = unknown, items = #order, shortItems = 0, unknownItems = 0, cycle = cycle,
        collectItems = 0, bankItems = 0, guildItems = 0 }
    for _, item in ipairs(order) do
        local n = need[item]
        local h = W.Count(have(item))   -- a whole number from 0, or nil (unknown): a NaN, an infinity, a fraction or a negative is never a count
        local mk = made[item]
        local row = { item = item, need = n, made = mk, madeRange = mk and range[item] or nil, have = h }
        if h ~= nil then
            local bank, guild = 0, 0
            if stock then bank, guild = stock(item) end
            local _, k, g, rest = W.Split(math.max(0, n - (mk or 0)), h, bank, guild)
            row.short, row.bank, row.guild, row.fromBank, row.fromGuild = rest, bank, guild, k, g
            if k + g > 0 then s.collectItems = s.collectItems + 1 end
            if k > 0 then s.bankItems = s.bankItems + 1 end
            if g > 0 then s.guildItems = s.guildItems + 1 end
        end
        if row.short == nil then s.unknownItems = s.unknownItems + 1
        elseif row.short > 0 then s.shortItems = s.shortItems + 1 end
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
        local ra, rb = Rank(a), Rank(b)
        if ra ~= rb then return ra < rb end
        return a.item < b.item
    end)
    if s.entries == 0 then s.state = "empty"
    elseif s.unknown > 0 or s.unknownItems > 0 or s.items == 0 then s.state = "partial"
    elseif s.shortItems > 0 then s.state = "short"
    elseif s.collectItems > 0 then s.state = "collect"
    else s.state = "ready" end
    return rows, s
end
