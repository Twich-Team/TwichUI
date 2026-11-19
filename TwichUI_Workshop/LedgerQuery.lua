-- TwichUI Workshop: the Gold Ledger's reading side (W.LedgerQuery)
-- Pure: no frames and no game calls except the clock and item names. It reads what the core's recorder (!!!TwichUI/auction/Ledger.lua)
-- keeps in TwichUILedgerDB and answers the page's questions: the totals of a window of days, the daily series, the split by source, and
-- the newest transactions. It writes nothing and never builds a record.
--
-- What the numbers are (and are not): every figure is observed gold movement, the exact difference between readings of the
-- character's gold, split into money in and money out. "Net Change" is in minus out. None of it is profit: a purchase of materials, a
-- repair or a transfer between your own characters is also gold out, and gold from a sale only counts when it reached your gold.
-- Days are UTC days. A day with no record is outside the recorder's coverage, which is not the same as a day with no activity.
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
}
LQ.ART = { ahSale = "npc:gavel", mail = "npc:sealed-scroll", ahBuy = "npc:reagent-pouch", other = "npc:coins" }
-- The source a transaction row names: the single word for the table (a direction is the amount's sign).
LQ.ROW_LABELS = { ahSale = "Auction Sale", mail = "Mail Collected", ahBuy = "Auction Purchase", other = "Unclassified" }

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

function LQ.Day(day) return date("!%Y-%m-%d", day * DAY) end
function LQ.DayShort(day) return date("!%b %d", day * DAY) end
function LQ.Stamp(t) return date("!%Y-%m-%d %H:%M", t) .. " UTC" end

function LQ.Today()
    local f = GetServerTime or time
    local ok, t = pcall(f)
    if not ok or type(t) ~= "number" or t ~= t or t < 0 then return nil end
    return math.floor(t / DAY)
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
--   from, to            first and last UTC day (today is last)
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
function LQ.Compare(summary, field)
    local p = summary and summary.prev
    if not p then return nil end
    local now, before = summary.totals[field], p[field]
    if field == "net" then return { prior = before, text = "Prior " .. summary.filter.days .. "d: " .. LQ.Money(before, true) } end
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
        return row.qty and row.qty > 1 and ("%s (%d)"):format(base, row.qty) or base
    end
    if row.note then return row.note end
    if row.code == "mail" then return "Money from the mailbox" end
    if row.code == "ahBuy" then return "Completed purchase" end
    if row.code == "ahSale" then return "Sale proceeds" end
    return "Gold balance change"
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
    local first = (today - filter.days + 1) * DAY
    local last = (today + 1) * DAY
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
-- Profession profitability: not available yet
---------------------------------------------------------------------------
-- A later version may register a provider that links crafts, material costs and realized sales. Until one exists the page says
-- it is not available; unknown costs are never shown as zero. A provider is a function(filter) returning nil (nothing to say) or
-- { rows = { { name, icon, amount (signed copper), partial = true when some cost or sale is unknown } }, note = "plain words" }.
function LQ.SetProfessionProvider(fn) LQ.professionProvider = type(fn) == "function" and fn or nil end
function LQ.Professions(filter)
    local f = LQ.professionProvider
    if not f then return nil end
    local ok, result = pcall(f, Normalize(filter))
    if not ok or type(result) ~= "table" or type(result.rows) ~= "table" then return nil end
    return result
end

function LQ.ResetCache() cache = nil end
