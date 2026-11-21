-- TwichUI Workshop: the Gold Ledger's reading side (W.LedgerQuery)
-- Pure: no frames and no game calls except the clock and item names. It reads what the core's recorder (!!!TwichUI/auction/Ledger.lua)
-- keeps in TwichUILedgerDB and answers the page's questions: the totals of a window of days, the daily series, the split by source, and
-- the newest transactions. It writes nothing and never builds a record.
--
-- What the numbers are (and are not): every figure is observed gold movement, the exact difference between readings of the
-- character's gold, split into money in and money out. "Net Change" is in minus out. None of it is profit: a purchase of materials, a
-- repair or a transfer between your own characters is also gold out, and gold from a sale only counts when it reached your gold.
-- Days are the player's LOCAL calendar days (the recorder's Lg.DayOf / Lg.DayStart). A day with no record is outside the recorder's coverage, which is not the same as a day with no activity.
--
-- Filter: { scope = "current" | "all", source = nil | a source code, days = 7 | 30 | 90, search = "" }. Character scope, source and
-- the day window apply to the totals, the series and the transactions alike; search only narrows the transaction list (the daily totals
-- are kept by source, not by item, so a text search cannot be applied to them honestly).

local R = TwichUI
local W = R.Workshop
local LQ = { RANGES = { 7, 30, 90 }, MAX_ROWS = 400 }
W.LedgerQuery = LQ

local DAY = 86400
local cache   -- the last summary: { key, value }

local function Ledger() return R.Ledger end

---------------------------------------------------------------------------
-- Words and money
---------------------------------------------------------------------------
LQ.LABELS = {
    ahSale = "Auction sales", mail = "Mail collected", ahBuy = "Auction purchases", other = "Unclassified",
    vendorBuy = "Vendor purchases", vendorSell = "Vendor sales", repair = "Repairs", quest = "Quest rewards",
    ahDeposit = "Auction deposits", ahCancelFee = "Cancellation fees",
}
LQ.ART = { ahSale = "npc:gavel", mail = "npc:sealed-scroll", ahBuy = "npc:reagent-pouch", other = "npc:coins" }
LQ.ART.vendorBuy, LQ.ART.vendorSell, LQ.ART.repair = "npc:reagent-pouch", "npc:coins", "npc:hammer"
LQ.ART.quest = "npc:inscribed-stone"
-- The source a transaction row names: the single word for the table (a direction is the amount's sign).
LQ.ROW_LABELS = { ahSale = "Auction Sale", mail = "Mail Collected", ahBuy = "Auction Purchase", other = "Unclassified" }
LQ.ROW_LABELS.vendorBuy, LQ.ROW_LABELS.vendorSell, LQ.ROW_LABELS.repair = "Vendor Purchase", "Vendor Sale", "Repairs"
LQ.ROW_LABELS.quest = "Quest Reward"
LQ.ROW_LABELS.ahDeposit, LQ.ROW_LABELS.ahCancelFee = "Auction Deposit", "Auction Cancellation Fee"
LQ.ART.ahDeposit, LQ.ART.ahCancelFee = "npc:gavel", "npc:coins"

-- 1234567 -> "123g 45s 67c"; the leading zero units are left out, never the exact copper. signed: "+" for a gain.
function LQ.Money(copper, signed)
    if type(copper) ~= "number" or copper ~= copper then return "" end
    local neg = copper < 0
    local n = neg and -copper or copper
    local g, s, c = math.floor(n / 10000), math.floor(n / 100) % 100, n % 100
    local gt = ("%d"):format(g)
    local k
    repeat gt, k = gt:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    local text
    if g > 0 then text = gt .. "g " .. s .. "s " .. c .. "c"
    elseif s > 0 then text = s .. "s " .. c .. "c"
    else text = c .. "c" end
    if neg then return "-" .. text end
    return (signed and n > 0) and ("+" .. text) or text
end

-- A day is a local calendar-day number: its label is that date itself, so it is formatted without a zone shift.
function LQ.Day(day) return date("!%Y-%m-%d", day * DAY) end
function LQ.DayShort(day) return date("!%b %d", day * DAY) end
-- A moment is shown in the player's own time.
function LQ.Stamp(t) return date("%Y-%m-%d %H:%M", t) end
function LQ.Clock(t) return date("%b %d  %H:%M", t) end

-- The local day a unix time falls on, and the unix time a local day begins (the recorder's own, so the page and the journal agree).
function LQ.DayOf(t)
    local L = Ledger()
    return L and L.DayOf and L.DayOf(t) or math.floor(t / DAY)
end
function LQ.DayStart(day)
    local L = Ledger()
    return L and L.DayStart and L.DayStart(day) or day * DAY
end

function LQ.Today()
    local f = GetServerTime or time
    local ok, t = pcall(f)
    if not ok or type(t) ~= "number" or t ~= t or t < 0 then return nil end
    return LQ.DayOf(t)
end

---------------------------------------------------------------------------
-- Which records a filter reads
---------------------------------------------------------------------------
local function Normalize(filter)
    filter = filter or {}
    local days = filter.days
    if days ~= 7 and days ~= 30 and days ~= 90 then days = 7 end
    local source = filter.source
    if source ~= nil and not (type(source) == "string" and LQ.LABELS[source]) then source = nil end
    return { scope = filter.scope == "all" and "all" or "current", source = source, days = days,
        search = type(filter.search) == "string" and filter.search or "" }
end
LQ.Normalize = Normalize

-- { { key, name, realm, since, rec } }: the current character's record (if it has one) or every record
local function Records(scope)
    local L = Ledger()
    local out = {}
    if not (L and L.Characters) then return out end
    if scope == "all" then
        for _, ch in ipairs(L.Characters()) do
            local rec = L.Record(ch.key)
            if rec then out[#out + 1] = { key = ch.key, name = rec.name, realm = rec.realm, since = rec.since, rec = rec } end
        end
    else
        local key = L.CharKey()
        local rec = key and L.Record(key)
        if rec then out[1] = { key = key, name = rec.name, realm = rec.realm, since = rec.since, rec = rec } end
    end
    return out
end

---------------------------------------------------------------------------
-- The totals of a window of days
---------------------------------------------------------------------------
-- What one day holds for a source filter: money in and out, and whether any record covered the day.
local function DayTotals(records, day, source)
    local inn, out, n, covered = 0, 0, 0, false
    for _, r in ipairs(records) do
        local d = r.rec.days[day]
        if d then
            covered = true
            if source then
                inn = inn + (d.ci[source] or 0)
                out = out + (d.co[source] or 0)
            else
                inn, out = inn + d.i, out + d.o
            end
            n = n + d.n
        end
    end
    return inn, out, n, covered
end

local function Window(records, source, from, to)
    local days, tin, tout, covered = {}, 0, 0, 0
    for day = from, to do
        local inn, out, n, cov = DayTotals(records, day, source)
        days[#days + 1] = { day = day, inn = inn, out = out, net = inn - out, n = n, covered = cov }
        tin, tout = tin + inn, tout + out
        if cov then covered = covered + 1 end
    end
    return days, tin, tout, covered
end

-- The split by source over [from, to]: { [code] = { inn, out } } from the day records' own split.
local function BySource(records, source, from, to)
    local by = {}
    for day = from, to do
        for _, r in ipairs(records) do
            local d = r.rec.days[day]
            if d then
                for code, v in pairs(d.ci) do
                    if not source or source == code then
                        local b = by[code]
                        if not b then b = { inn = 0, out = 0 }; by[code] = b end
                        b.inn = b.inn + v
                    end
                end
                for code, v in pairs(d.co) do
                    if not source or source == code then
                        local b = by[code]
                        if not b then b = { inn = 0, out = 0 }; by[code] = b end
                        b.out = b.out + v
                    end
                end
            end
        end
    end
    return by
end

local function Key(filter, today, records)
    local L = Ledger()
    local names = {}
    for i, r in ipairs(records) do names[i] = r.key end
    return table.concat({ L and L.Revision() or 0, filter.scope, filter.source or "-", filter.days, today, table.concat(names, "|") }, ":")
end

-- The whole answer for the cards, the chart and the source panel. Cached until the recorder changes or the filter or the day does.
--   from, to            first and last local day (today is last)
--   days                { { day, inn, out, net, n, covered } } for each day, oldest first
--   totals              inn, out, net, attrIn, attrOut (identified sources), unkIn, unkOut (unclassified), n
--   by                  { [code] = { inn, out } }
--   coverage            { days = days with a record, total = days in the window, since = earliest recording start }
--   prev                nil, or { inn, out, net } of the window before it, only when every one of its days was recorded
--   characters          how many characters' records were read
function LQ.Summary(filter, today)
    local L = Ledger()
    filter = Normalize(filter)
    today = today or LQ.Today()
    if not (L and today) then return nil end
    local records = Records(filter.scope)
    local key = Key(filter, today, records)
    if cache and cache.key == key then return cache.value end
    local from = today - filter.days + 1
    local days, tin, tout, covered = Window(records, filter.source, from, today)
    local by = BySource(records, filter.source, from, today)
    local attrIn, attrOut = 0, 0
    for code, b in pairs(by) do
        if code ~= "other" then attrIn, attrOut = attrIn + b.inn, attrOut + b.out end
    end
    local other = by.other or { inn = 0, out = 0 }
    local n = 0
    for _, d in ipairs(days) do n = n + d.n end
    local since
    for _, r in ipairs(records) do
        if r.since and (not since or r.since < since) then since = r.since end
    end
    local prev
    do
        local pdays, pin, pout, pcovered = Window(records, filter.source, from - filter.days, from - 1)
        if pcovered == #pdays and #pdays > 0 then prev = { inn = pin, out = pout, net = pin - pout } end
    end
    local value = {
        filter = filter, from = from, to = today, days = days,
        totals = { inn = tin, out = tout, net = tin - tout, attrIn = attrIn, attrOut = attrOut, unkIn = other.inn, unkOut = other.out, n = n },
        by = by, coverage = { days = covered, total = #days, since = since }, prev = prev, characters = #records,
        recording = #records > 0,
    }
    cache = { key = key, value = value }
    return value
end

-- The ranked split by source: { { code, dir (1 in, -1 out), label, amount } } biggest first. Only sources with recorded money.
function LQ.SourceRows(summary)
    local rows = {}
    if not summary then return rows end
    for code, b in pairs(summary.by) do
        local label = LQ.LABELS[code] or code
        if b.inn > 0 then rows[#rows + 1] = { code = code, dir = 1, label = code == "other" and "Unclassified income" or label, amount = b.inn } end
        if b.out > 0 then rows[#rows + 1] = { code = code, dir = -1, label = code == "other" and "Unclassified spending" or label, amount = b.out } end
    end
    table.sort(rows, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        if a.code ~= b.code then return a.code < b.code end
        return a.dir > b.dir
    end)
    return rows
end

-- The words for a comparison with the window before. nil when that window was not fully recorded: no percentage is made from partial data.
function LQ.Compare(summary, field, fmt)
    local M = fmt or LQ.Money
    local p = summary and summary.prev
    if not p then return nil end
    local now, before = summary.totals[field], p[field]
    if field == "net" then return { prior = before, text = "Prior " .. summary.filter.days .. "d: " .. M(before, true) } end
    if before <= 0 then return nil end
    local pct = math.floor((now - before) / before * 100 + 0.5)
    return { prior = before, pct = pct, text = ("%s%d%% vs. prior %dd"):format(pct > 0 and "+" or "", pct, summary.filter.days) }
end

---------------------------------------------------------------------------
-- Transactions
---------------------------------------------------------------------------
local function ItemName(id)
    if not id then return nil end
    local f = C_Item and C_Item.GetItemInfo
    if type(f) ~= "function" then return nil end
    local ok, name = pcall(f, id)
    if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
    return nil
end
function LQ.ItemIcon(id)
    local f = C_Item and C_Item.GetItemInfoInstant
    if not id or type(f) ~= "function" then return nil end
    local ok, _, _, _, _, icon = pcall(f, id)
    return ok and icon or nil
end

-- The text of the Item / Note column: what the entry really holds, never a made-up item or reason.
function LQ.Note(row)
    local name = ItemName(row.item)
    if row.item then
        local base = name or ("Item " .. row.item)
        if row.qty and row.qty > 1 and (row.code == "vendorBuy" or row.code == "vendorSell" or row.code == "ahDeposit" or row.code == "ahCancelFee") then
            return ("%s \195\151%d"):format(base, row.qty)
        end
        return row.qty and row.qty > 1 and ("%s (%d)"):format(base, row.qty) or base
    end
    if row.note then
        return row.code == "ahSale" and row.qty and row.qty > 1 and ("%s \195\151%d"):format(row.note, row.qty) or row.note
    end
    if row.code == "mail" then return "Money from the mailbox" end
    if row.code == "quest" then return "Quest reward" end
    if row.code == "ahBuy" then return "Completed purchase" end
    if row.code == "ahSale" then return "Sale proceeds" end
    return "Gold balance change"
end

-- Settlement is descriptive metadata on the collected cash entry; these amounts never enter totals again.
-- fmt(amount, signed) writes an amount (default: the plain text; the page passes the coin artwork).
function LQ.AuctionDetails(row, fmt)
    local M = fmt or LQ.Money
    local lines = {}
    if row.auction then lines[#lines + 1] = "Auction ID: " .. row.auction end
    if row.code ~= "ahSale" and row.code ~= "mail" then return lines end
    if row.code == "mail" then
        local cost = R.LedgerCost
        local results = cost and cost.ResultsFor and row.key and row.id and cost.ResultsFor(row.key, row.id) or {}
        if #results == 0 then return lines end
    end
    lines[#lines + 1] = "Collected: " .. M(row.a)
    local L = Ledger()
    local s = L and L.Settlement(row.settlement, row.a)
    if not s then
        lines[#lines + 1] = row.code == "mail" and "Mixed payment; seller components below" or "Fee unavailable"
        -- V5: the sold-auction mails one combined payment held (each mail's own collected amount), from the cost basis's results
        local C = R.LedgerCost
        local parts = C and C.ResultsFor and row.key and row.id and C.ResultsFor(row.key, row.id) or {}
        if #parts > 1 or row.code == "mail" and #parts > 0 then
            local sum = 0
            for _, r in ipairs(parts) do sum = sum + (r.a or 0) end
            lines[#lines + 1] = ("Sold-auction mails in this payment: %d"):format(#parts)
            for i = 1, math.min(3, #parts) do
                local r = parts[i]
                local name = r.n or "Sold item"
                if r.q and r.q > 1 then name = ("%s \195\151%d"):format(name, r.q) end
                lines[#lines + 1] = name .. ": " .. M(r.a)
                if r.fee ~= nil then lines[#lines + 1] = "Auction fee: " .. M(r.fee) .. " - verified invoice" end
                if r.d ~= nil then lines[#lines + 1] = "Returned deposit: " .. M(r.d) .. " (included in collected)" end
                lines[#lines + 1] = "Cost basis unavailable"
            end
            if #parts > 3 then lines[#lines + 1] = ("and %d more"):format(#parts - 3) end
            if sum ~= row.a then lines[#lines + 1] = "Unidentified: " .. M(row.a - sum) end
        end
        return lines
    end
    lines[#lines + 1] = "Gross sale: " .. M(s.g)
    lines[#lines + 1] = "Auction fee: " .. M(s.f) .. " - verified invoice"
    lines[#lines + 1] = "Returned deposit: " .. M(s.d) .. " (included in collected)"
    if #s.invoices > 1 then
        lines[#lines + 1] = "Seller invoices: " .. #s.invoices
        for i = 1, math.min(3, #s.invoices) do
            local r = s.invoices[i]
            local name = r.n or "Sold item"
            if r.q and r.q > 1 then name = ("%s \195\151%d"):format(name, r.q) end
            lines[#lines + 1] = name .. ": " .. M(r.c)
        end
    end
    return lines
end

-- The newest transactions of the window, newest first, at most `limit`. A k-way merge of the characters' journals (each is oldest
-- first), so a long history is not sorted or copied.
function LQ.Rows(filter, today, limit)
    filter = Normalize(filter)
    today = today or LQ.Today()
    limit = limit or LQ.MAX_ROWS
    local L = Ledger()
    if not (L and today) then return {}, false end
    local records = Records(filter.scope)
    local first = LQ.DayStart(today - filter.days + 1)
    local last = LQ.DayStart(today + 1)
    local needle = filter.search ~= "" and filter.search:lower() or nil
    local ptr = {}
    for i, r in ipairs(records) do ptr[i] = #r.rec.entries end
    local out, more = {}, false
    while true do
        local best, bi
        for i, r in ipairs(records) do
            local entries = r.rec.entries
            local p = ptr[i]
            while p > 0 and entries[p].t >= last do p = p - 1 end   -- a clock that ran ahead: not part of this window yet
            ptr[i] = p
            if p > 0 then
                local e = entries[p]
                if e.t < first then ptr[i] = 0
                elseif not best or e.t > best.t or (e.t == best.t and e.id > best.id) then best, bi = e, i end
            end
        end
        if not best then break end
        ptr[bi] = ptr[bi] - 1
        local code = best.k or "other"
        if not filter.source or filter.source == code then
            local row = { id = best.id, t = best.t, a = best.a, code = code, item = best.i, qty = best.q, note = best.n, evidence = best.e,
                settlement = best.s, auction = best.u,
                attributed = best.k ~= nil, char = records[bi].name, key = records[bi].key, realm = records[bi].realm }
            row.text = LQ.Note(row)
            local keep = true
            if needle then
                keep = (LQ.ROW_LABELS[code]:lower():find(needle, 1, true) or row.text:lower():find(needle, 1, true)
                    or (filter.scope == "all" and row.char:lower():find(needle, 1, true))) and true or false
            end
            if keep then
                if #out >= limit then more = true break end
                out[#out + 1] = row
            end
        end
    end
    return out, more
end

---------------------------------------------------------------------------
-- Realized item results: what a verified sale earned against the verified cost of exactly those units
---------------------------------------------------------------------------
-- Read from the core's cost basis (auction/LedgerCost.lua). Nothing here estimates: a result carries a profit only when the
-- sale's collected gold and the cost of the exact units sold were both verified; otherwise the row says why it cannot.
LQ.MAX_RESULT_ROWS = 100
LQ.WHY = {
    nolot = "No verified purchase or craft of this item was on record.",
    mixed = "Other stock of the same item was in your bags, so these units could not be told from it.",
    missing = "Some verified units of this item were no longer in your bags.",
    short = "The bags could not confirm exactly which units were sold.",
    nostock = "The bags could not confirm exactly which units were sold.",
    unknowncost = "The cost of some of the materials was never verified.",
    manylots = "The sale drew on too many separate purchases to keep.",
    auctionid = "The seller's mail names the item but no auction and no exact item, so it cannot be tied to a posting or a purchase.",
}
local resultCache

local function Cost() return R.LedgerCost end

local function CharKeys(records)
    local keys = {}
    for i, r in ipairs(records) do keys[i] = r.key end
    return keys
end

local function Window(filter, today) return LQ.DayStart(today - filter.days + 1), LQ.DayStart(today + 1) end

-- { rows, verified (profit of verified sales), sales, unavailable (sales without a verified result) } or nil without a cost basis.
-- A row groups the window's sales of one item identity:
--   name, item, src, qty, sales, collected (all sales), vsales/vqty/vcollected/vcost (the verified ones), profit (nil unless some are
--   verified), status ("verified" | "partial" | "unavailable"), why, gross/fee/deposit (auction invoices), t (newest sale)
function LQ.Results(filter, today)
    filter = Normalize(filter)
    today = today or LQ.Today()
    local C, L = Cost(), Ledger()
    if not (C and L and today) then return nil end
    local records = Records(filter.scope)
    local keys = CharKeys(records)
    local key = table.concat({ L.Revision(), filter.scope, filter.source or "-", filter.days, today, filter.search, table.concat(keys, "|") }, ":")
    if resultCache and resultCache.key == key then return resultCache.value end
    local pt = R.Perf and R.Perf.on and R.Perf.Start("ledger.costquery")
    local first, last = Window(filter, today)
    local needle = filter.search ~= "" and filter.search:lower() or nil
    local groups, order = {}, {}
    local total = { verified = 0, sales = 0, unavailable = 0 }
    for _, r in ipairs(C.Results(keys, first, last)) do
        if not filter.source or filter.source == r.src then
            local name = ItemName(r.i) or r.n or (r.i and ("Item " .. r.i)) or "Sold item"
            if not needle or name:lower():find(needle, 1, true) then
                local gk = r.src .. ":" .. (r.k or ("n:" .. (r.n or "?")))
                local g = groups[gk]
                if not g then
                    g = { name = name, item = r.i, src = r.src, qty = 0, sales = 0, collected = 0, vsales = 0, vqty = 0, vcollected = 0, vcost = 0,
                        gross = 0, fee = 0, deposit = 0, t = r.t, whys = {} }
                    groups[gk] = g
                    order[#order + 1] = g
                end
                g.qty, g.sales, g.collected = g.qty + r.q, g.sales + 1, g.collected + r.a
                if r.t > g.t then g.t = r.t end
                total.sales = total.sales + 1
                if r.st == "ok" then
                    g.vsales, g.vqty, g.vcollected, g.vcost = g.vsales + 1, g.vqty + r.q, g.vcollected + r.a, g.vcost + r.c
                    total.verified = total.verified + (r.a - r.c)
                else
                    total.unavailable = total.unavailable + 1
                    if r.w and not g.whys[r.w] then g.whys[r.w] = true; g.why = g.why or r.w end
                    if r.src == "ahSale" then g.gross, g.fee, g.deposit = g.gross + (r.g or 0), g.fee + (r.fee or 0), g.deposit + (r.d or 0) end
                end
            end
        end
    end
    -- V5 posting provenance: the player's own TwichUI postings of an item sold at auction in the window, as facts beside the sale.
    -- Never matched to a payment (no auction id on the seller's mail), so they never change a result, a profit or a total.
    if C.Posts then
        local byName = {}
        for _, g in ipairs(order) do if g.src == "ahSale" then byName[g.name] = g end end
        if next(byName) then
            for _, post in ipairs(C.Posts(keys, first, last)) do
                local g = post.n and byName[post.n]
                if g then
                    local info = g.postings or { count = 0, sold = 0, units = 0, verified = 0, costed = 0 }
                    g.postings = info
                    info.count, info.units = info.count + 1, info.units + post.q
                    if post.st == "sold" then info.sold = info.sold + 1 end
                    if post.cs == "ok" and post.c then info.costed, info.verified = info.costed + 1, info.verified + post.c end
                end
            end
        end
    end
    table.sort(order, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.name < b.name end)
    local rows, more = {}, false
    for _, g in ipairs(order) do
        if #rows >= LQ.MAX_RESULT_ROWS then more = true break end
        g.status = g.vsales == g.sales and "verified" or (g.vsales > 0 and "partial" or "unavailable")
        g.profit = g.vsales > 0 and (g.vcollected - g.vcost) or nil
        rows[#rows + 1] = g
    end
    local value = { rows = rows, more = more, verified = total.verified, sales = total.sales, unavailable = total.unavailable }
    resultCache = { key = key, value = value }
    if pt then R.Perf.Stop(pt) end
    return value
end

-- The words of one result row's hover: only verified figures, and the reason for any that are missing.
function LQ.ResultLines(row, fmt)
    local M = fmt or LQ.Money
    local lines = {}
    if row.src == "ahSale" then
        lines[#lines + 1] = "Auction sale: " .. M(row.collected) .. " collected"
        if row.gross > 0 then lines[#lines + 1] = "Gross sale " .. M(row.gross) .. ", auction fee " .. M(row.fee) .. ", returned deposit " .. M(row.deposit) end
    else
        lines[#lines + 1] = row.sales == 1 and "1 vendor sale" or (row.sales .. " vendor sales")
    end
    if row.status == "verified" then
        lines[#lines + 1] = "Verified cost: " .. M(row.vcost)
        lines[#lines + 1] = "Collected: " .. M(row.vcollected)
        lines[#lines + 1] = "Realized result: " .. M(row.profit, true)
    elseif row.status == "partial" then
        lines[#lines + 1] = ("%d of %d sales have a verified cost"):format(row.vsales, row.sales)
        lines[#lines + 1] = "Verified: collected " .. M(row.vcollected) .. ", cost " .. M(row.vcost) .. " = " .. M(row.profit, true)
    else
        lines[#lines + 1] = "Cost basis unavailable. Profit unavailable."
    end
    if row.status ~= "verified" and row.why and LQ.WHY[row.why] then lines[#lines + 1] = LQ.WHY[row.why] end
    local posts = row.postings
    if posts and posts.count > 0 then
        lines[#lines + 1] = ("Your TwichUI postings of this item in this period: %d (%d seen sold)"):format(posts.count, posts.sold)
        if posts.costed > 0 then
            lines[#lines + 1] = ("Verified cost of the units in %d of them: %s"):format(posts.costed, M(posts.verified))
        end
        lines[#lines + 1] = "Postings are not matched to payments, so no profit is shown."
    end
    return lines
end

---------------------------------------------------------------------------
-- Profit by Profession
---------------------------------------------------------------------------
-- Only a verified craft sold with every material's cost known counts toward a profession; sales with an unknown cost are named
-- as partial; a profession with crafts but no such sale says so. Vendor resale of bought goods and gathered goods are never attributed.
-- A provider is a function(filter) returning nil (nothing to say) or { rows = { { name, icon, amount (signed copper), partial,
-- text (replaces the amount), tip = { lines } } }, note = "plain words" }. The cost basis registers itself below.
function LQ.SetProfessionProvider(fn) LQ.professionProvider = type(fn) == "function" and fn or nil end
function LQ.Professions(filter)
    local f = LQ.professionProvider
    if not f then return nil end
    local ok, result = pcall(f, Normalize(filter))
    if not ok or type(result) ~= "table" or type(result.rows) ~= "table" then return nil end
    return result
end

local function CostProfessions(filter)
    local C, L = Cost(), Ledger()
    local today = LQ.Today()
    if not (C and L and today) then return nil end
    local keys = CharKeys(Records(filter.scope))
    local first, last = Window(filter, today)
    local rows = {}
    for _, p in ipairs(C.Professions(keys, first, last)) do
        local row = { name = p.name, partial = p.partial > 0 and p.sales > 0, tip = {} }
        if p.sales > 0 then
            row.amount = p.profit
            row.name = ("%s \194\183 %d %s verified"):format(p.name, p.sales, p.sales == 1 and "sale" or "sales")
            row.tip[#row.tip + 1] = ("Verified: collected %s, cost %s"):format(LQ.Money(p.collected), LQ.Money(p.cost))
            row.tipFn = function(fmt)   -- the same words with the page's own money presentation
                local lines = { ("Verified: collected %s, cost %s"):format(fmt(p.collected), fmt(p.cost)) }
                for i = 2, #row.tip do lines[i] = row.tip[i] end
                return lines
            end
            if p.partial > 0 then row.tip[#row.tip + 1] = p.partial .. " more " .. (p.partial == 1 and "sale has" or "sales have") .. " a craft with an unknown cost and are not counted." end
        else
            row.text = "Insufficient verified data"
            row.tip[#row.tip + 1] = p.crafts .. (p.crafts == 1 and " craft" or " crafts") .. " recorded; no sale with a complete verified cost yet."
        end
        rows[#rows + 1] = row
    end
    if #rows == 0 then return nil end
    return { rows = rows, note = "Only crafts the game confirmed, sold with every material's cost verified." }
end
LQ.CostProfessions = CostProfessions
LQ.SetProfessionProvider(CostProfessions)

function LQ.ResetCache() cache = nil; resultCache = nil end
