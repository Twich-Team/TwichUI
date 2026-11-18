-- Optional integrated status and transaction review, using existing materials
-- and passive snapshots. No update driver and no native calls on page opening.
local R,W=TwichUI,TwichUI.Workshop
local A,UI=W.AuctionUI,W.UI
local panel,review,quantityBox
local function Money(n) return n~=nil and UI.Money(n) or "Unavailable" end
function A.DebugShown() return panel and panel:IsShown() or false end
function A.UpdateDebug()
    if not panel or not panel:IsShown() then return end
    local h=R.AuctionHost.Snapshot()
    local q=W.AuctionReads.Snapshot()
    local t=W.AuctionActions.Snapshot()
    panel.text:SetText("Interface: "..(h.state=="twichui" and "TwichUI" or h.state=="recovery" and "Restoration pending" or "Blizzard")..
        "   ·   Auctioneer: "..(R.AuctionHost.IsCurrent(h.visit) and "Connected" or "Unavailable").."\nPage: "..A.Mode()..
        "   ·   Live request: "..q.state.."   ·   Throttle: "..(q.throttle and "Ready" or "Busy")..
        "\nSent: "..(q.lastRequest or "None").."   ·   Response: "..(q.lastResponse or "None")..
        "\nResults: "..q.results.."   ·   Complete: "..(q.complete and "Yes" or "No / unverified")..
        "\nAction: "..t.state.."   ·   "..(t.message or "No action pending").."\nRead error: "..(q.error or "None")..
        "\nRestore: "..h.reason.."   ·   Open: "..string.format("%.1f",h.openMS or 0).." ms   ·   Switch: "..string.format("%.2f",h.switchMS or 0).." ms"..
        "\nFrame time estimate: "..(GetFramerate and string.format("%.2f ms at %.0f FPS",1000/math.max(1,GetFramerate()),GetFramerate()) or "Unavailable")..
        "   ·   Detailed capture: /tui perf start auction 2")
end
function A.ToggleDebug()
    if not A.IsShown() or A.Context()~="auctioneer" then return end
    if not panel then
        panel=CreateFrame("Frame",nil,A.Frame(),"BackdropTemplate")
        panel:SetSize(720,234);panel:SetPoint("BOTTOM",0,52);panel:SetFrameStrata("DIALOG")
        UI.Panel(panel,"card");panel:EnableMouse(true)
        panel.text=A.Text(panel,"",12,14,-14,-14);panel.text:SetWordWrap(true);panel.text:SetHeight(196)
        panel.close=R.FrameLook.Close(panel,function() panel:Hide() end);panel.close:SetPoint("TOPRIGHT",-4,-4)
        panel:Hide()
    end
    A.BindSounds(panel)
    panel:SetShown(not panel:IsShown());A.UpdateDebug()
end
-- Compact reusable item header. Keep the exact hyperlink for variants and
-- use the real item tooltip rather than pricing evidence.
local function ItemHeader(parent,y)
    local h=CreateFrame("Button",nil,parent);h:SetPoint("TOPLEFT",16,y);h:SetPoint("TOPRIGHT",-16,y);h:SetHeight(62)
    UI.Panel(h,"espresso")
    h.pic=UI.ItemIcon(h,44);h.pic:SetPoint("LEFT",9,0)
    h.name=A.Text(h,"",16,64,-10,-10);h.name:SetHeight(38);h.name:SetWordWrap(true)
    h:SetScript("OnEnter",function(self)
        if not self.item or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:SetItemByID(self.item) end
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave",function(self) R.Interact.HideTip(self) end)
    h:SetScript("OnClick",function(self) if self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end end)
    function h:SetItem(item,key,link)
        local info=W.AdvisorData.Info(item)
        if key and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
            local ok,native=pcall(C_AuctionHouse.GetItemKeyInfo,key)
            if ok and type(native)=="table" then
                if not info.known then info.name=W.Text(W.Plain(native.itemName),200) or info.name end
                info.icon=info.icon or W.Plain(native.iconFileID)
                info.quality=info.quality or W.Int(W.Plain(native.quality),0,20)
            end
        end
        self.item,self.link=item,link or info.link
        self.pic.tex:SetTexture(info.icon or UI.ICON_BLANK)
        self.name:SetText(self.link or info.name)
        local c=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[info.quality or 1]
        if c then self.name:SetTextColor(c.r,c.g,c.b) else UI.Paint(self.name,UI.K.text) end
        W.AdvisorData.Request(item)
    end
    return h
end
function A.UpdateReview()
    if not review or not review:IsShown() then return end
    local d=W.AuctionActions.Review()
    if not d then review:Hide();return end
    review.id,review.displayed=d.id,d
    local buying=d.kind=="buyCommodity" or d.kind=="buyItem"
    local posting=d.kind=="postCommodity" or d.kind=="postItem"
    review.heading:SetText(buying and "Review purchase" or posting and "Review posting" or "Review cancellation")
    UI.Art(review.art,buying and "npc:coins" or "npc:gavel",30)
    review.item:SetItem(d.item,d.itemKey,d.link)
    local duration=d.duration and ({AUCTION_DURATION_ONE,AUCTION_DURATION_TWO,AUCTION_DURATION_THREE})[d.duration]
    review.quantities:SetText("Quantity: |cffffffff"..d.quantity.."|r"..(duration and ("    ·    "..duration) or ""))
    review.totalLabel:SetText(posting and "Gross if sold" or d.estimated and "Estimated total" or "Total cost")
    review.total:SetText(Money(d.total))
    review.extra:SetText(d.deposit and ("Deposit upfront: "..Money(d.deposit)) or d.excess and d.excess>0 and ("Needed: "..d.desired.." · Extra: "..d.excess) or "")
    local waiting=d.state=="waiting" or d.state=="quoting" or d.state=="native-warning"
    local message=d.reason or d.message or "Review the quantity and total before confirming."
    if d.state=="quoted" then message=d.retry and "Updated total · confirm to retry this purchase." or "Price confirmed. Your purchase will be delivered by mail."
    elseif d.state=="quoting" then message="Getting your total…"
    elseif d.state=="native-warning" then message="Please review the game's posting warning."
    elseif d.state=="waiting" then message=posting and "Posting your auction…" or "Completing your purchase…" end
    if d.vendor and d.vendor.status=="below" then message="Below vendor value. Posting requires an additional confirmation." end
    review.note:SetText(message)
    UI.Paint(review.note,d.retry and UI.K.bronzeText or UI.K.textDim)
    local quote=d.kind=="buyCommodity" and d.state=="review"
    review.confirm.text:SetText(waiting and "Please wait…" or quote and (d.retry and "Retry quote" or "Get total") or d.retry and "Retry purchase" or posting and "Confirm posting" or "Confirm")
    review.confirm:SetEnabled(d.allowed and (d.state=="review" or d.state=="quoted"))
    review.spinner:SetShown(waiting)
end
function A.ReviewAction(id,why)
    if not id then A.Note(why);return false end
    if not review then
        review=CreateFrame("Frame",nil,A.Frame(),"BackdropTemplate")
        review:SetSize(440,306);review:SetPoint("CENTER");review:SetFrameStrata("DIALOG");review:EnableMouse(true)
        UI.Panel(review,"card")
        review.heading=A.Text(review,"",19,18,-16,-56,UI.K.bronzeText);review.heading:SetHeight(26)
        review.art=review:CreateTexture(nil,"ARTWORK");review.art:SetSize(30,30);review.art:SetPoint("TOPRIGHT",-18,-12)
        review.item=ItemHeader(review,-52)
        review.quantities=A.Text(review,"",12,20,-126,-20,UI.K.textDim);review.quantities:SetHeight(18)
        review.totalLabel=A.Text(review,"Total cost",13,20,-153,-220,UI.K.textDim)
        review.total=UI.Text(review,18,UI.K.bronzeText);review.total:SetPoint("TOPRIGHT",-20,-151);review.total:SetWidth(220);review.total:SetJustifyH("RIGHT")
        review.extra=A.Text(review,"",12,20,-181,-20,UI.K.textDim);review.extra:SetHeight(18)
        review.note=A.Text(review,"",12,20,-207,-20,UI.K.textDim);review.note:SetHeight(42);review.note:SetWordWrap(true)
        review.spinner=CreateFrame("Frame",nil,review,"SpinnerTemplate");review.spinner:SetSize(18,18);review.spinner:SetPoint("BOTTOM",0,23);review.spinner:Hide()
        review.confirm=UI.Button(review,"Confirm",174,"primary",function()
            local d=W.AuctionActions.Review();if not d or d.id~=review.id then return end
            local function Confirm()
                local ok,reason=W.AuctionActions.Confirm(d.id,review.displayed)
                if not ok then A.Note(reason) end
                A.UpdateReview();A.UpdateDebug()
            end
            if d.vendor and d.vendor.status=="below" then
                R.Interact.Confirm("TWICHUI_AH_VENDOR_REVIEW",R.AuctionPrice.VendorQuestion(d.vendor,review.item.link or W.AdvisorData.Info(d.item).name,Money),Confirm,{accept="Post anyway",hold=1})
            else Confirm() end
        end,30)
        review.confirm:SetPoint("BOTTOMLEFT",18,16)
        review.cancel=UI.Button(review,"Cancel",174,"secondary",function() W.AuctionActions.Cancel();review:Hide() end,30)
        review.cancel:SetPoint("BOTTOMRIGHT",-18,16)
    end
    A.BindSounds(review)
    review:Show();A.UpdateReview();return true
end
function A.RequestBuy(row,quantity)
    local ok,why=W.AuctionActions.RequestBuy(row,quantity)
    if not ok then A.Note(why) end
    return ok
end
function A.QuickBuy(row,defaultQuantity)
    A.MenuSound()
    if not A.Live() or not row or not row.itemKey then return false end
    local ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,row.itemKey)
    if not ok or type(info)~="table" or type(W.Plain(info.isCommodity))~="boolean" then
        A.Note("Item type is still loading. Try again shortly.");return false
    end
    if not info.isCommodity then return A.RequestBuy(row,1) end
    -- A browse key may include display item level; commodity reviews are
    -- identified by the base item ID, just like the native price-tier search.
    local commodityRow={}
    for field,value in pairs(row) do commodityRow[field]=value end
    commodityRow.itemKey=W.AuctionReads.Key({itemID=row.itemKey.itemID});commodityRow.commodity=true
    row=commodityRow
    if not quantityBox then
        quantityBox=CreateFrame("Frame",nil,A.Frame(),"BackdropTemplate")
        quantityBox:SetSize(400,224);quantityBox:SetPoint("CENTER");quantityBox:SetFrameStrata("DIALOG");quantityBox:EnableMouse(true)
        UI.Panel(quantityBox,"card")
        quantityBox.title=A.Text(quantityBox,"Quick buy",19,16,-14,-16,UI.K.bronzeText)
        quantityBox.item=ItemHeader(quantityBox,-44)
        local label=A.Text(quantityBox,"Quantity to buy",13,16,-120,-16,UI.K.textDim)
        quantityBox.amount=UI.L.EditBox(quantityBox,110,30);UI.CL.Dress(quantityBox.amount,"field")
        quantityBox.amount:SetPoint("TOPLEFT",16,-140);quantityBox.amount:SetMaxLetters(8);quantityBox.amount:SetNumeric(true)
        local function Continue()
            local quantity=W.Int(tonumber(quantityBox.amount:GetText()),1,W.MAX_ID)
            if not quantity then A.Note("Enter a whole quantity greater than zero.");return end
            if A.RequestBuy(quantityBox.row,quantity) then quantityBox:Hide() end
        end
        quantityBox.next=UI.Button(quantityBox,"Review total",170,"primary",Continue,30);quantityBox.next:SetPoint("BOTTOMLEFT",16,16)
        quantityBox.cancel=UI.Button(quantityBox,"Cancel",170,"secondary",function() quantityBox:Hide() end,30)
        quantityBox.cancel:SetPoint("BOTTOMRIGHT",-16,16)
        quantityBox.amount:SetScript("OnEnterPressed",Continue)
        quantityBox.amount:SetScript("OnEscapePressed",function() quantityBox:Hide() end)
        quantityBox:HookScript("OnHide",function() quantityBox.amount:ClearFocus();quantityBox.row=nil end)
        quantityBox:Hide()
    end
    A.BindSounds(quantityBox)
    quantityBox.row=row;quantityBox.item:SetItem(row.itemKey.itemID,row.itemKey,row.link)
    quantityBox.amount:SetText(tostring(W.Int(defaultQuantity,1,W.MAX_ID) or 1));quantityBox:Show();quantityBox.amount:SetFocus();quantityBox.amount:HighlightText()
    return true
end
function A.HideExtras()
    if quantityBox then quantityBox:Hide() end
    if panel then panel:Hide() end
    if review then review:Hide() end
    W.AuctionActions.Cancel()
end

function A.HideReview()
    if quantityBox then quantityBox:Hide() end
    if review then review:Hide() end
    W.AuctionActions.Cancel()
end
