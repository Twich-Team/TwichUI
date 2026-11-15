-- AH-2: cooperative, bounded discovery over existing saved observations only.
-- No client auction cache, requests, purchase handles, saved writes or price engine.
local R, W = TwichUI, TwichUI.Workshop
local D = { BATCH = 160, MAX = 20000, MS = 2, SORT_BATCH = 2048 }
W.AuctionBrowseData = D
local AD, MK = W.AdvisorData, W.Market
D.CATEGORIES = { {"all", "All Categories"}, {"trade", "Trade Goods"}, {"consumable", "Consumable"},
    {"equipment", "Equipment"}, {"recipe", "Recipe"}, {"misc", "Miscellaneous"} }
D.QUALITIES = { {-1, "All Qualities"}, {0, "Poor"}, {1, "Common"}, {2, "Uncommon"}, {3, "Rare"}, {4, "Epic"}, {5, "Legendary"} }
function D.Category(info)
    local id = info.classID
    if id == 7 then return "trade" elseif id == 0 then return "consumable"
    elseif id == 2 or id == 4 then return "equipment" elseif id == 9 then return "recipe"
    elseif id == 15 then return "misc" end
    return "other"
end
function D.Matches(row, opt)
    opt = opt or {}
    local query = (opt.query or ""):lower()
    if query ~= "" then
        if opt.exact then
            if row.info.name:lower() ~= query and tostring(row.item) ~= query then return false end
        elseif not (row.info.name .. " " .. row.item):lower():find(query, 1, true) then return false end
    end
    if opt.nativeCategory then
        if not W.AuctionCategories.Matches(row.info,opt.nativeCategory) then return false end
    elseif opt.category and opt.category ~= "all" and D.Category(row.info) ~= opt.category then return false end
    if opt.quality and opt.quality >= 0 and row.info.quality ~= opt.quality then return false end
    local bind = row.info.bindType
    if opt.auctionable and bind ~= 0 and bind ~= 2 and bind ~= 3 then return false end
    return true
end
-- The saved cheapest tier is aggregated. Its quantity is NOT a single stack,
-- and rounded per-unit price times quantity is NOT an original auction total.
function D.Row(item, market)
    local info = AD.Info(item)
    local p = market and MK.Price(item, {market = market}) or nil
    local unit = p and W.Int(p.price, 1, W.Prices.MAX_COPPER) or nil
    local qty = p and W.Int(p.qty, 1, W.MAX_ID) or nil
    local estimate = unit and qty and W.Int(unit * qty, 1, W.Prices.MAX_COPPER) or nil
    return { item = item, info = info, unit = unit, qty = qty, estimate = estimate,
        at = p and p.at, observed = p ~= nil, source = "stored", actionable = false }
end
local function Less(a,b)
    if a.unit ~= b.unit then return (a.unit or math.huge) < (b.unit or math.huge) end
    return a.item < b.item
end
-- Sort is cooperative too; no unbounded table.sort at the end of a catalog tick.
function D.Job(opt)
    opt = opt or {}
    local job = { rows = {}, scanned = 0, capped = false }
    local co = coroutine.create(function()
        local work = 0
        local began = debugprofilestop and debugprofilestop() or 0
        local function Tick(limit)
            work = work + 1
            if work >= (limit or D.BATCH) or (debugprofilestop and debugprofilestop() - began >= D.MS) then
                coroutine.yield()
                work = 0; began = debugprofilestop and debugprofilestop() or 0
            end
        end
        local seen = {}
        local market = opt.market
        local function Add(id)
            id = W.Int(id, 1, W.MAX_ID)
            if not id or seen[id] then return end
            if job.scanned >= D.MAX then job.capped = true; return end
            seen[id] = true; job.scanned = job.scanned + 1
            local row = D.Row(id, market)
            if D.Matches(row, opt) then job.rows[#job.rows + 1] = row end
        end
        if opt.item then Add(opt.item); Tick() end
        for id in pairs(market and market.items or {}) do
            Add(id); Tick()
            if job.capped then break end
        end
        local rows, scratch, width = job.rows, {}, 1
        while width < #rows do
            for lo = 1, #rows, width * 2 do
                local mid, hi = math.min(lo + width - 1, #rows), math.min(lo + width * 2 - 1, #rows)
                local left, right = lo, mid + 1
                for dst = lo, hi do
                    if left <= mid and (right > hi or Less(rows[left], rows[right])) then scratch[dst] = rows[left]; left = left + 1
                    else scratch[dst] = rows[right]; right = right + 1 end
                    Tick(D.SORT_BATCH)
                end
                for dst = lo, hi do rows[dst] = scratch[dst]; Tick(D.SORT_BATCH) end
            end
            width = width * 2
        end
    end)
    function job:Step()
        if self.done then return true, self.error end
        local function Resume() return coroutine.resume(co) end
        local ok, err = R.Perf.Call("auction.previewSearch", Resume)
        self.done = coroutine.status(co) == "dead"
        self.error = not ok and tostring(err) or nil
        if self.error then self.done = true; self.rows = {} end
        return self.done, self.error
    end
    return job
end
