-- Bag-only draft preparation. No item movement, reservations or posting calls.
local W=TwichUI.Workshop
local D={MAX=1000}
W.AuctionSellData=D
function D.Bags(query)
    local rows={}
    local api=C_Container
    if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo) then return rows,"Bag data unavailable" end
    query=(W.Text(query,200) or ""):lower()
    for bag=0,(NUM_BAG_SLOTS or 4) do
        for slot=1,math.min(api.GetContainerNumSlots(bag) or 0,200) do
            if #rows>=D.MAX then return rows,"Bag list limited" end
            local x=api.GetContainerItemInfo(bag,slot)
            if type(x)=="table" then
                local item=W.Int(W.Plain(x.itemID),1,W.MAX_ID)
                local qty=W.Int(W.Plain(x.stackCount),1,W.MAX_ID)
                if item and qty then
                    local info=W.AdvisorData.Info(item)
                    if query=="" or (info.name.." "..item):lower():find(query,1,true) then
                        local r={key=bag..":"..slot,item=item,bag=bag,slot=slot,qty=qty,info=info,
                            locked=W.Plain(x.isLocked)~=false,bound=W.Plain(x.isBound),
                            variant=W.Worth.LinkVariant(W.Plain(x.hyperlink))}
                        r.reserved,r.pending=W.AdvisorData.Reserved(item)
                        if W.AuctionReads.Available() and ItemLocation and ItemLocation.CreateFromBagAndSlot and C_AuctionHouse and C_AuctionHouse.IsSellItemValid then
                            local ok,valid=pcall(function()
                                return C_AuctionHouse.IsSellItemValid(ItemLocation:CreateFromBagAndSlot(bag,slot))
                            end)
                            if ok then r.eligible=valid==true end
                        end
                        rows[#rows+1]=r
                    end
                end
            end
        end
    end
    return rows
end
function D.Draft(row,quantity,price)
    local result={valid=false,deposit=nil,fees=nil}
    if not row then result.reason="Choose a bag item.";return result end
    quantity=W.Int(quantity,1,W.MAX_ID);price=W.Int(price,1,W.Prices.MAX_COPPER)
    if not quantity or quantity>row.qty then result.reason="Quantity exceeds the selected bag stack or is invalid.";return result end
    if not price then result.reason="Enter a whole-copper unit price.";return result end
    local proceeds=W.Sell.Proceeds(price,quantity)
    if proceeds.state~="ok" then result.reason="Proposed total is out of range.";return result end
    result.gross=proceeds.gross;result.quantity=quantity;result.unit=price
    if row.locked or row.bound~=false or row.eligible~=true then result.reason="Auction eligibility is unavailable or this item cannot be auctioned.";return result end
    if row.pending or (row.reserved or 0)>0 then result.reason="Crafting reservations or a pending plan protect this item.";return result end
    result.valid=true
    result.reason="Preparation only. Real-client posting acceptance pending."
    return result
end
