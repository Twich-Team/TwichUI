-- AH-3 is a presentation adapter over Session.ShoppingPlan and CraftPlanner.
-- No second requirements store, allocation, optimizer, purchase state or totals.
local W = TwichUI.Workshop
local P = {}
W.AuctionShoppingData = P
P.SOURCES = { {"all","All Sources"}, {"auction","Auction House"}, {"vendor","Vendor"}, {"make","Craft"}, {"collect","Collect"}, {"none","No source"} }
P.GROUPS = { {"item","Group by item"}, {"purpose","By crafting purpose"} }
function P.Key(row) return row.item .. ":" .. (row.kind=="collect" and ("collect:"..tostring(row.where)) or "own") end
function P.Source(row)
    if row.kind=="collect" then return "collect" end
    if row.kind=="make" then return "make" end
    return row.source=="auction" and "auction" or row.source=="vendor" and "vendor" or "none"
end
function P.Cost(row, money)
    if row.kind=="collect" then return "Already owned", "Collect from storage; no purchase cost." end
    if row.kind=="make" then return "In the plan", "Material costs are counted in their own rows." end
    if row.costState=="range" and row.high then return W.Strategy.CostText({low=row.low,high=row.high},money) end
    return W.Shopping.CostWords(row,money)
end
function P.Rows(plan, ctx, opt)
    opt=opt or {}
    local out={}
    for _,row in ipairs(plan.rows or {}) do
        local info=W.AdvisorData.Info(row.item)
        local source=P.Source(row)
        local names=row.forNames
        if not names or #names==0 then names=W.Session.NeededFor(row.item) end
        local purpose=#names>0 and table.concat(names,", ") or "Shared crafting materials"
        local query=(opt.query or ""):lower()
        if (not opt.source or opt.source=="all" or source==opt.source) and
            (query=="" or (info.name.." "..row.item.." "..purpose):lower():find(query,1,true)) then
            out[#out+1]={key=P.Key(row),row=row,info=info,source=source,purpose=purpose,
                -- These stay the shared plan's numbers, including nil/unknown.
                need=row.need,have=row.have,missing=row.qty}
        end
    end
    table.sort(out,function(a,b)
        if opt.group=="purpose" and a.purpose~=b.purpose then return a.purpose<b.purpose end
        if a.info.name~=b.info.name then return a.info.name<b.info.name end
        return a.key<b.key
    end)
    return out
end
function P.State(plan, ctx, state)
    if state=="planning" or ctx.stale then return "Updating plan · previous quantities may be stale",false end
    if state=="basic" then return "Basic list · multilevel planning unavailable",true end
    return "Shared multilevel crafting plan",true
end
function P.Incomplete(plan, ctx)
    return (plan.unknownBags or 0)>0 or (ctx and ctx.summary and (ctx.summary.unknown or 0)>0) or false
end
function P.Total(plan, money, ctx)
    local t=plan.totals or {}
    if P.Incomplete(plan,ctx) then
        return "Known requirements only: at least "..money(t.low or t.cash or 0).." · recipe or bag data missing"
    end
    if #(plan.rows or {})==0 then return "No missing materials in the shared plan." end
    if (t.priced or 0)+(t.missing or 0)+(t.makes or 0)==0 then return "Collect stored materials; nothing to buy." end
    if (t.missing or 0)>0 then
        return "Estimated spending: at least "..money(t.low or t.cash or 0).." · "..t.missing.." prices missing"
    end
    local cost=W.Strategy.CostText({low=t.low or t.cash,high=t.high},money)
    return "Estimated spending: "..(cost or "Unknown")..(t.estimate and " (includes estimates)" or "")
end
return P
