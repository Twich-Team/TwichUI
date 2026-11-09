-- TwichUI Workshop: combined materials
-- Pure functions over plain tables. Every queued recipe's materials are added up FIRST (needed = materials per craft x crafts,
-- summed over the whole queue); only then is what the bags hold applied, once per item, so the same owned items are never counted for
-- two recipes. A recipe whose materials aren't known adds nothing and is counted as "unknown": it never counts as needing zero.

local R = TwichUI
local W = R.Workshop
local M = {}
W.Materials = M

-- entries: { { crafts = n, mats = { { item, qty }, ... } | nil }, ... }
-- Returns need (item -> number), order (items in first-seen order), unknown (how many entries have no usable materials)
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
    return need, order, unknown
end

local function Rank(row)
    if row.short == nil then return 2 end
    return row.short > 0 and 1 or 3
end

-- have(item) -> how many the bags hold, or nil when that can't be read. Rows: { item, need, have, short }; have and short are nil
-- when unknown (never 0). Short items first, then unknown ones, then the rest; each group by item number.
-- Summary state: "empty" (nothing queued), "partial" (something isn't known: a recipe's materials or a count),
-- "short" (everything known, something missing) or "ready" (everything known and in the bags).
function M.Rows(entries, have)
    local need, order, unknown = M.Combine(entries)
    local rows = {}
    local s = { entries = #entries, unknown = unknown, items = #order, shortItems = 0, unknownItems = 0 }
    for _, item in ipairs(order) do
        local n = need[item]
        local h = have(item)
        if type(h) ~= "number" or h ~= h or h < 0 then h = nil end
        local row = { item = item, need = n, have = h, short = h and math.max(0, n - h) or nil }
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
    else s.state = "ready" end
    return rows, s
end
