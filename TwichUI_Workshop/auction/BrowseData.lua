-- AH-2: cooperative, bounded discovery over existing saved observations only.
-- No client auction cache, requests, purchase handles, saved writes or price engine.
local R, W = TwichUI, TwichUI.Workshop
local D = { BATCH = 160, MAX = 20000, MS = 2, SORT_BATCH = 2048 }
W.AuctionBrowseData = D
local AD, MK = W.AdvisorData, W.Market
local stats = {starts=0, completions=0, cancellations=0, errors=0, active=0,
    projections=0, metadata=0, patches=0, rowUpdates=0, invalidations=0, paints=0, longest=0}
function D.Count(key) stats[key]=math.min(1000000000,(stats[key] or 0)+1) end
function D.Stats() local out={};for k,v in pairs(stats) do out[k]=v end;return out end
function D.Less(a,b,opt)
    if opt and opt.sort=="Name" then
        local an,bn=a.info.name:lower(),b.info.name:lower()
        if an~=bn then return an<bn end
    elseif a.unit~=b.unit then
        if not a.unit then return false end
        if not b.unit then return true end
        if opt and opt.reverse then return a.unit>b.unit end
        return a.unit<b.unit
    end
    return a.item<b.item
end
function D.SameMarket(a,b)
    if a==b then return true end
    if not a or not b or a.key~=b.key then return false end
    -- Prices.Market returns a fresh read facade; compare its backing stores.
    for _,k in ipairs({"items","h2","c2","hist","dist"}) do if a[k]~=b[k] then return false end end
    return true
end
-- Metadata is a row change, never a new catalog generation. Keep candidates
-- excluded by a filter too, so late names/categories can enter the same view.
function D.Metadata(p,item,ok)
    local id=W.Int(W.Plain(item),1,W.MAX_ID)
    if ok==false or not id or not (p.job and p.job.seen and p.job.seen[id] or p.known and p.known[id]) then return end
    D.Count("metadata")
    p.dirty=p.dirty or {};p.dirty[id]=true
end
function D.Patch(p,opt)
    if p.job or not p.catalog or not p.dirty then return false end
    local changed,n,began=false,0,debugprofilestop and debugprofilestop() or 0
    local structural,selected,updates=false,false,{}
    for id in pairs(p.dirty) do
        p.dirty[id]=nil
        local row=p.catalog[id]
        if row then
            local info=AD.Info(id)
            local different=false
            for k,v in pairs(info) do if row.info[k]~=v then different=true;break end end
            for k,v in pairs(row.info) do if info[k]~=v then different=true;break end end
            if different then
                row.info=info;D.Count("patches");changed=true;updates[id]=true
                selected=selected or p.selected==id
                local at
                for i,r in ipairs(p.rows) do if r.item==id then at=i;break end end
                if at and opt and opt.sort=="Name" then table.remove(p.rows,at);at=nil;structural=true end
                local matches=D.Matches(row,opt)
                if at and not matches then table.remove(p.rows,at);structural=true
                elseif not at and matches then
                    structural=true
                    local lo,hi=1,#p.rows+1
                    while lo<hi do
                        local mid=math.floor((lo+hi)/2);local r=p.rows[mid]
                        if D.Less(r,row,opt) then lo=mid+1 else hi=mid end
                    end
                    table.insert(p.rows,lo,row)
                end
                if p.index then p.index[id]=matches and row or nil end
            end
        end
        n=n+1
        if n>=D.BATCH or debugprofilestop and debugprofilestop()-began>=D.MS then break end
    end
    if next(p.dirty) then W.AuctionUI.Schedule() else p.dirty=nil end
    if changed then
        local selected=false
        for _,r in ipairs(p.rows) do if r.item==p.selected then selected=true;break end end
        if not selected then p.selected=p.rows[1] and p.rows[1].item end
    end
    return changed,structural,selected,updates
end
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
-- Sort is cooperative too; no unbounded table.sort at the end of a catalog tick.
function D.Job(opt)
    opt = opt or {}
    local job = { rows = {}, scanned = 0, capped = false, catalog={}, discovering=not opt.catalog }
    D.Count(opt.catalog and "projections" or "starts");stats.active=stats.active+1
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
        job.seen = seen
        if opt.index then job.index = {} end
        local market = opt.market
        local function Add(id)
            id = W.Int(id, 1, W.MAX_ID)
            if not id or seen[id] then return end
            if job.scanned >= D.MAX then job.capped = true; return end
            seen[id] = true; job.scanned = job.scanned + 1
            local row = opt.catalog and opt.catalog[id] or D.Row(id, market)
            job.catalog[id]=row
            if D.Matches(row, opt) then
                job.rows[#job.rows + 1] = row
                if job.index then job.index[id] = row end
            end
        end
        if opt.item then Add(opt.item); Tick() end
        for _, source in ipairs(opt.catalog and {opt.catalog} or opt.sources or {market and market.items or {}}) do
            for id in pairs(source) do
                Add(id); Tick()
                if job.capped then break end
            end
            if job.capped then break end
        end
        if opt.enumerate and not opt.catalog and not job.capped then opt.enumerate(Add, Tick, job) end
        local rows, scratch, width = job.rows, {}, 1
        while width < #rows do
            for lo = 1, #rows, width * 2 do
                local mid, hi = math.min(lo + width - 1, #rows), math.min(lo + width * 2 - 1, #rows)
                local left, right = lo, mid + 1
                for dst = lo, hi do
                    if left <= mid and (right > hi or D.Less(rows[left], rows[right],opt)) then scratch[dst] = rows[left]; left = left + 1
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
        local began=debugprofilestop and debugprofilestop() or 0
        local function Resume() return coroutine.resume(co) end
        local ok, err = R.Perf.Call("auction.previewSearch", Resume)
        self.done = coroutine.status(co) == "dead"
        self.error = not ok and tostring(err) or nil
        if self.error then self.done = true; self.rows = {} end
        if debugprofilestop then stats.longest=math.max(stats.longest,debugprofilestop()-began) end
        if self.done then stats.active=math.max(0,stats.active-1);D.Count(self.error and "errors" or "completions") end
        return self.done, self.error
    end
    function job:Cancel()
        if self.done then return end
        self.done=true;self.error="canceled";stats.active=math.max(0,stats.active-1);D.Count("cancellations")
    end
    return job
end
