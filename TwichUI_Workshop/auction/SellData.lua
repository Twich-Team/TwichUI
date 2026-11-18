-- Bag-stack preparation and read-only competition. Never moves or posts items.
local W=TwichUI.Workshop
local D={MAX=1000}
W.AuctionSellData=D
local Q,PR=W.AuctionReads,W.Prices
local function Key(k) return Q.Key(k) end
local function Same(a,b)
    a,b=Key(a),Key(b)
    return a and b and a.itemID==b.itemID and a.itemLevel==b.itemLevel and
        a.itemSuffix==b.itemSuffix and a.battlePetSpeciesID==b.battlePetSpeciesID
end
function D.Money(g,s,c)
    local fields={g,s,c};local nums={}
    if (g or "")=="" and (s or "")=="" and (c or "")=="" then return nil,"Enter a unit price." end
    for i,v in ipairs(fields) do
        if type(v)~="string" or #v>11 or not v:match("^%d*$") then return nil,"Use whole numbers for gold, silver and copper." end
        nums[i]=tonumber(v) or 0
    end
    if #fields~=3 then return nil,"Enter gold, silver and copper." end
    if not W.Int(nums[1],0,math.floor(PR.MAX_COPPER/10000)) or not W.Int(nums[2],0,99) or not W.Int(nums[3],0,99) then
        return nil,"Silver and copper must be 0–99; gold must be within the money limit."
    end
    local total=nums[1]*10000+nums[2]*100+nums[3]
    if not W.Int(total,1,PR.MAX_COPPER) then return nil,"Unit price must be positive and within the money limit." end
    return total
end
function D.Coins(n)
    n=W.Int(n,0,PR.MAX_COPPER)
    if not n then return "","","" end
    return tostring(math.floor(n/10000)),tostring(math.floor(n/100)%100),tostring(n%100)
end
function D.Max(row)
    if not row or row.locked or row.bound~=false or row.pending or (row.reserved or 0)>0 or row.eligible==false then return 0 end
    return math.min(row.qty,row.available or row.qty)
end
local function Stacks(query)
    local rows={}
    local api=C_Container
    if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return rows,"Bag data unavailable" end
    query=(W.Text(query,200) or ""):lower()
    for bag=0,(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot=1,math.min(api.GetContainerNumSlots(bag) or 0,200) do
            if #rows>=D.MAX then return rows,"Bag list limited" end
            local x=api.GetContainerItemInfo(bag,slot)
            if type(x)=="table" then
                local item=W.Int(W.Plain(x.itemID),1,W.MAX_ID)
                local qty=W.Int(W.Plain(x.stackCount),1,W.MAX_ID)
                if item and qty and W.Plain(x.isBound)==false then
                    local info=W.AdvisorData.Info(item)
                    if query=="" or (info.name.." "..item):lower():find(query,1,true) then
                        local link=W.Text(W.Plain(x.hyperlink),1000)
                        local r={key=bag..":"..slot,item=item,bag=bag,slot=slot,qty=qty,info=info,link=link,
                            locked=W.Plain(x.isLocked)~=false,bound=W.Plain(x.isBound),variantKind=W.Worth.LinkVariant(link)}
                        r.variant=r.variantKind~=nil
                        r.keyComparable=r.variantKind~="bonus" -- four-field native keys cannot prove bonus-ID identity
                        r.reserved,r.pending=W.AdvisorData.Reserved(item)
                        if Q.Available() and ItemLocation and ItemLocation.CreateFromBagAndSlot and C_AuctionHouse then
                            local ah=C_AuctionHouse
                            local ok=pcall(function()
                                r.location=ItemLocation:CreateFromBagAndSlot(bag,slot)
                                if C_Item and C_Item.IsBound then
                                    local bound=W.Plain(C_Item.IsBound(r.location))
                                    if type(bound)=="boolean" then r.bound=bound end
                                end
                                if ah.IsSellItemValid then r.eligible=W.Plain(ah.IsSellItemValid(r.location,false))==true end
                                if ah.GetItemKeyFromItem then r.itemKey=Key(ah.GetItemKeyFromItem(r.location)) end
                                if r.itemKey and r.itemKey.itemID~=item then r.itemKey=nil;r.eligible=false end
                                if ah.GetAvailablePostCount then r.available=W.Int(W.Plain(ah.GetAvailablePostCount(r.location)),0,W.MAX_ID) end
                                if ah.GetItemCommodityStatus then r.mode=W.Plain(ah.GetItemCommodityStatus(r.location)) end
                                if ah.SupportsCopperValues then r.copper=W.Plain(ah.SupportsCopperValues()) end
                            end)
                            if not ok then r.eligible,r.itemKey,r.available,r.mode,r.copper=nil,nil,nil,nil,nil end
                        end
                        -- Commodity searches use item ID alone, even if the bag
                        -- item's native key carries a nonzero display item level.
                        r.bagItemKey=r.itemKey
                        local types=Enum and Enum.ItemCommodityStatus
                        if types and r.mode==types.Commodity and r.itemKey then
                            r.itemKey=Key({itemID=item});r.variantKind=nil;r.variant=false;r.keyComparable=true
                        end
                        local k=r.itemKey
                        r.identityKnown=k~=nil or link and (link:match("^item:%d+")~=nil or link:find("|Hitem:",1,true)~=nil) or false
                        r.variant=r.variant or k and (k.itemLevel~=0 or k.itemSuffix~=0 or k.battlePetSpeciesID~=0) or false
                        r.identity=r.key..":"..item..":"..(link or "")..":"..(k and table.concat({k.itemLevel,k.itemSuffix,k.battlePetSpeciesID},":") or "unknown")
                        if r.bound==false and r.eligible~=false then rows[#rows+1]=r end
                    end
                end
            end
        end
    end
    return rows
end
-- One row per exact item/commodity, retaining each physical stack for
-- revalidation. Native GetAvailablePostCount supplies the cross-bag posting cap,
-- just as it does for Sell from Bags; no stack moves or splitting are needed.
function D.Bags(query)
    local stacks,err=Stacks(query)
    local groups,order={},{}
    for _,part in ipairs(stacks) do
        local k=part.itemKey
        local commodity=Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity
        local key=commodity and part.mode==commodity and k and ("commodity:"..part.item)
            or k and ("item:"..part.item..":"..k.itemLevel..":"..k.itemSuffix..":"..k.battlePetSpeciesID..":"..(part.link or ""))
            or ("link:"..part.item..":"..(part.link or part.key))
        local g=groups[key]
        if not g then g={key=key,rep=part,qty=0,usable=0,members={},identities={}};groups[key]=g;order[#order+1]=g end
        g.qty=g.qty+part.qty;g.members[#g.members+1]=part
        g.identities[#g.identities+1]=part.identity..":"..part.qty..":"..tostring(part.locked)
        if not part.locked and part.eligible==true then
            g.usable=g.usable+part.qty
            if g.rep.locked or g.rep.eligible~=true then g.rep=part end
        end
    end
    local rows={}
    for _,g in ipairs(order) do
        local row={};for key,value in pairs(g.rep) do row[key]=value end
        row.key=g.key;row.identity=g.key.."|"..table.concat(g.identities,"|")
        row.members=g.members;row.qty=g.qty;row.stacks=#g.members
        row.available=math.min(g.usable,g.rep.available or g.usable)
        rows[#rows+1]=row
    end
    return rows,err
end
function D.Draft(row,quantity,price,duration)
    local result={valid=false,deposit=nil,fees=nil,net=nil}
    if not row then result.reason="Choose a bag item.";return result end
    if duration~=nil and not W.Int(duration,1,3) then result.reason="Choose a supported auction duration.";return result end
    if row.pending or (row.reserved or 0)>0 then result.reason="Crafting reservations or a pending plan protect this item.";return result end
    quantity=W.Int(quantity,1,W.MAX_ID);price=W.Int(price,1,PR.MAX_COPPER)
    if not quantity or quantity>row.qty or row.available and quantity>row.available then result.reason="Quantity exceeds the usable bag total or available posting count.";return result end
    if not price then result.reason="Enter a valid unit price.";return result end
    local proceeds=W.Sell.Proceeds(price,quantity)
    if proceeds.state~="ok" then result.reason="Proposed total is out of range.";return result end
    result.gross,result.quantity,result.unit=proceeds.gross,quantity,price
    if row.locked or row.bound~=false or row.eligible~=true then result.reason="Auction eligibility is unavailable or this item cannot be auctioned.";return result end
    if row.copper==false and price%100~=0 then result.reason="This auctioneer requires whole-silver prices.";return result end
    if Q.Available() and row.location and row.itemKey and type(row.copper)=="boolean" and W.Int(duration,1,3) and D.BagCurrent(row) then
        local types=Enum and Enum.ItemCommodityStatus
        local ah=C_AuctionHouse
        local fn,args
        if types and row.mode==types.Item then fn,args=ah.CalculateItemDeposit,{row.location,duration,quantity}
        elseif types and row.mode==types.Commodity then fn,args=ah.CalculateCommodityDeposit,{row.item,duration,quantity} end
        if type(fn)=="function" then
            local ok,deposit=pcall(fn,unpack(args))
            if ok then
                local amount=W.Int(W.Plain(deposit),0,PR.MAX_COPPER)
                -- Forever's native sell frame rounds the upfront quote when
                -- this auctioneer supports only whole-silver money values.
                if amount and row.copper==false then amount=math.ceil(amount/100)*100 end
                result.deposit=W.Int(amount,0,PR.MAX_COPPER)
            end
        end
    end
    result.valid=true;result.reason="Review the quantity, price and duration before posting."
    return result
end
local function Market() return W.Market.Source().market end
local function Stamp(m) return m and m.key..":"..W.Valuation.Generation(m) or "none" end
local function StackCurrent(row,grouped)
    local api=C_Container
    if not (row and api and api.GetContainerItemInfo) then return false end
    local ok,valid=pcall(function()
        local x=api.GetContainerItemInfo(row.bag,row.slot)
        if type(x)~="table" or W.Plain(x.itemID)~=row.item or W.Plain(x.stackCount)~=row.qty or
            (grouped and W.Plain(x.isLocked)~=row.locked or not grouped and W.Plain(x.isLocked)~=false) or W.Plain(x.isBound)~=false or W.Text(W.Plain(x.hyperlink),1000)~=row.link then return false end
        if row.itemKey then
            if not Q.Available() or not C_AuctionHouse.GetItemKeyFromItem then return false end
            return Same(row.bagItemKey or row.itemKey,C_AuctionHouse.GetItemKeyFromItem(row.location))
        end
        return row.identityKnown==true
    end)
    return ok and valid==true
end
function D.BagCurrent(row)
    if not row then return false end
    if row.members then
        for _,part in ipairs(row.members) do if not StackCurrent(part,true) then return false end end
        return #row.members>0
    end
    return StackCurrent(row,false)
end
function D.Current(ctx,row)
    if not ctx or not row or ctx.identity~=row.identity or not D.BagCurrent(row) then return false end
    local market=Market()
    if Stamp(market)~=ctx.stamp or not W.AuctionBrowseData.SameMarket(market,ctx.market) then return false end
    if ctx.source=="live" then
        return Q.Available() and Q.snapshot==ctx.snapshot and Q.epoch==ctx.epoch and
            GetTime()>=ctx.at and GetTime()-ctx.at<30 and Same(row.itemKey,ctx.itemKey)
    end
    return not row.variant
end
function D.Competition(row,opt)
    opt=opt or {}
    local market=Market()
    local out={rows={},source="saved",market=market,stamp=Stamp(market),identity=row and row.identity}
    if not row then return out end
    local snap=Q.snapshot
    if opt.intent and snap and (snap.kind=="item" or Q.Integrated() and snap.kind=="commodity") and snap.intent==opt.intent and snap.epoch==Q.epoch and
        opt.epoch==Q.epoch and row.itemKey and row.keyComparable~=false and Same(row.itemKey,opt.itemKey) and
        opt.marketStamp==out.stamp and Q.Available() and W.Finite(snap.at) and GetTime()>=snap.at and GetTime()-snap.at<30 then
        out.source,out.complete,out.at,out.epoch,out.snapshot,out.itemKey="live",snap.complete,snap.at,snap.epoch,snap,row.itemKey
        out.kind=snap.kind;out.returned=snap.rawCount or #snap.rows
        local seen={}
        for i,r in ipairs(snap.rows or {}) do
            if i>Q.MAX then break end
            local matches=snap.kind=="commodity" and r.item==row.item or snap.kind~="commodity" and Same(r.itemKey,row.itemKey)
            if matches and not r.own and not r.account then
                local id=snap.kind=="commodity" and r.listingKey or W.Int(r.auctionID,1,9007199254740991)
                local qty=W.Int(r.qty,1,W.MAX_ID)
                local total=W.Int(r.total,1,PR.MAX_COPPER)
                local unit=W.Int(r.unit,1,PR.MAX_COPPER)
                if id and seen[id] then out.complete=false end
                if id and not seen[id] and qty and (total or snap.kind=="commodity" and unit or W.Int(r.bid,1,PR.MAX_COPPER)) then
                    seen[id]=true
                    out.rows[#out.rows+1]={key=id,qty=qty,unit=unit,total=total,bid=r.bid,priceEach=r.priceEach,
                        copy=out.complete==true and unit~=nil and r.ownershipKnown==true}
                end
            end
        end
        if not out.complete then for _,r in ipairs(out.rows) do r.copy=false end end
    else
        local facts=W.Facts.Of(row.item,{market=market,variant=row.variant})
        local comp=facts.comp
        out.facts= facts;out.at=comp and comp.at;out.complete=comp and comp.complete
        for i,t in ipairs(row.identityKnown and comp and comp.tiers or {}) do
            if i>6 then break end
            local unit,qty=W.Int(t.p,1,PR.MAX_COPPER),W.Int(t.q,1,W.MAX_ID)
            if unit and qty then
                out.rows[#out.rows+1]={key=i,qty=qty,unit=unit,estimate=W.Sell.Proceeds(unit,qty).gross,copy=not row.variant}
            end
        end
    end
    table.sort(out.rows,function(a,b)
        if (a.unit~=nil)~=(b.unit~=nil) then return a.unit~=nil end
        if a.unit~=b.unit then return (a.unit or 0)<(b.unit or 0) end
        return a.key<b.key
    end)
    return out
end
function D.Copy(ctx,tier,row)
    if not D.Current(ctx,row) then return nil end
    for _,r in ipairs(ctx.rows) do
        if r==tier and r.copy then
            local price=TwichUI.AuctionPrice.Suggest({lowest=r.unit,comparable=1},row.copper~=false)
            return price and price.price,price and price.rounded
        end
    end
end
function D.Advice(row,facts)
    if not row then return nil end
    return W.AdvisorData.Tooltip({item=row.item,count=row.qty,sell=row.info.sell,bindType=row.info.bindType,
        bound=row.bound,variant=row.variant,quality=row.info.quality,classID=row.info.classID,equipLoc=row.info.equipLoc},
        facts or W.Facts.Of(row.item,{variant=row.variant}))
end
function D.Guidance(row,ctx)
    if not row then return nil,nil end
    local f=ctx.facts or W.Facts.Of(row.item,{market=ctx.market,variant=row.variant})
    if ctx.source=="live" and ctx.complete and D.Current(ctx,row) then
        local low
        for _,r in ipairs(ctx.rows) do if r.copy and (not low or r.unit<low) then low=r.unit end end
        local live={};for k,v in pairs(f) do live[k]=v end
        live.comp=low and {competing=low,complete=true,cut=false,age=0,notes={}} or nil
        f=live
    end
    local rec=D.Advice(row,f)
    if ctx.source=="live" and ctx.complete and D.Current(ctx,row) and D.Max(row)>0 then
        local summary={comparable=0}
        for _,tier in ipairs(ctx.rows) do
            if tier.copy then
                summary.comparable=summary.comparable+1
                summary.lowest=math.min(summary.lowest or tier.unit,tier.unit)
            end
        end
        local price=TwichUI.AuctionPrice.Suggest(summary,row.copper~=false)
        return {state=price and "ok" or "nocompetition",price=price and price.price,source="live",
            limited=price and price.limited,rounded=price and price.rounded},rec,f
    end
    local suggestion=W.Sell.Suggest(row.item,row.qty,{facts=f})
    for _,flag in ipairs(suggestion.flags or {}) do
        if flag=="belowusual" then
            suggestion.state="uncertain";suggestion.price=nil
            suggestion.caution="Competition is far below the historical reference; review the price manually."
        end
    end
    if not row.identityKnown or D.Max(row)==0 or not D.Current(ctx,row) or
        ctx.source=="live" and not ctx.complete or rec.action~="auction" or rec.level~="supported" then suggestion.state="uncertain";suggestion.price=nil end
    suggestion.source=ctx.source
    return suggestion,rec,f
end
function D.Search(row)
    if not row or not row.itemKey or row.keyComparable==false or not Q.Available() or not D.BagCurrent(row) then
        return nil,"Live competition awaits verified item identity and auctioneer reads."
    end
    local types=Enum and Enum.ItemCommodityStatus
    if not types or (row.mode~=types.Item and not (Q.Integrated() and row.mode==types.Commodity)) then return nil,"This item's live search mode is not yet verified." end
    local commodity=row.mode==types.Commodity
    local ok,why=Q.Begin(commodity and "commodity" or "item",commodity and row.itemKey.itemID or row.itemKey)
    if not ok then return nil,why end
    return {intent=Q.serial,epoch=Q.epoch,itemKey=Key(row.itemKey),marketStamp=Stamp(Market())}
end
