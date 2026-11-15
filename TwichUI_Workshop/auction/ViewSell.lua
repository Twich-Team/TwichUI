local W=TwichUI.Workshop
local A,UI,D,AD=W.AuctionUI,W.UI,W.AuctionSellData,W.AdvisorData
local page
local function Money(n) return n and UI.Money(n) or "Unknown" end
local function Detail(p)
    local row
    for _,r in ipairs(p.rows or {}) do if r.key==p.selected then row=r end end
    p.suggestion=nil
    p.chosen=row
    p.detail.name:SetText(row and row.info.name or "Choose a bag item")
    p.detail.pic.tex:SetTexture(row and row.info.icon or UI.ICON_BLANK)
    p.detail.kind:SetText(row and ("Bags only · "..row.qty.." available") or "Bank stock cannot be posted from here")
    local draft=D.Draft(row,tonumber(p.quantity:GetText()),tonumber(p.price:GetText()))
    p.validation:SetText(draft.reason)
    p.total:SetText("Proposed gross: "..Money(draft.gross).."\nDeposit: unknown · Fees: unknown\nA listing is not a guaranteed sale.")
    if not row then p.advice:SetText("Select an item for existing Item Advisor guidance.");p.history:SetText("");p.chart:Set(nil,UI.Money);return end
    local facts=W.Facts.Of(row.item,{variant=row.variant})
    local rec=AD.Tooltip({item=row.item,count=row.qty,sell=row.info.sell,bindType=row.info.bindType,
        bound=row.bound,variant=row.variant,quality=row.info.quality,classID=row.info.classID,
        equipLoc=row.info.equipLoc},facts)
    p.advice:SetText((rec.text or "Insufficient evidence").."\n"..table.concat(rec.reasons or {},"\n"))
    p.history:SetText("Vendor / item: "..Money(row.info.sell).."\nReserved for crafting: "..(row.reserved or 0)..
        "\nLive competition: unavailable\n"..(W.Facts.Freshness(facts) or "No saved observation"))
    p.chart:Set(W.Facts.Chart(facts),UI.Money)
    p.suggestion=W.Sell.Suggest(row.item,row.qty,{facts=facts})
end
local function Refresh(p)
    local view=A.Capture(p.list,function(r) return r.key end)
    local old=p.chosen
    p.rows,p.error=D.Bags(p.search:GetText())
    local current
    for _,r in ipairs(p.rows) do if r.key==p.selected then current=r end end
    if old and (not current or current.item~=old.item or current.qty~=old.qty or current.locked~=old.locked or current.bound~=old.bound) then
        p.selected=nil;p.chosen=nil;p.price:SetText("");p.quantity:SetText("1")
    end
    p.list:SetData(p.rows,p.error or "No matching bag items.")
    A.Restore(p.list,view,function(r) return r.key end)
    Detail(p)
end
local function Build(p)
    page=p
    p.search=UI.Search(p,300,32,"Filter bag items…");p.search:SetPoint("TOPLEFT",0,0)
    p.search:SetScript("OnEnterPressed",function(self) self:ClearFocus();Refresh(p) end)
    local left=A.Card(p,"Bag inventory · current stacks",100)
    left:SetWidth(320);left:SetPoint("TOPLEFT",0,-48);left:SetPoint("BOTTOMLEFT",0,0)
    p.list=UI.List(left,58,function(parent)
        local r=CreateFrame("Button",nil,parent);UI.Hover(r)
        r.pic=UI.ItemIcon(r,34);r.pic:SetPoint("LEFT",6,0)
        r.name=A.Text(r,"",13,48,-8)
        r.sub=A.Text(r,"",11,48,-30,-8,UI.K.textDim)
        r.fill=function(self,x)
            self.data=x;self.name:SetText(x.info.name)
            local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[x.info.quality or 1]
            if color then self.name:SetTextColor(color.r,color.g,color.b) else UI.Paint(self.name,UI.K.text) end
            self.pic.tex:SetTexture(x.info.icon or UI.ICON_BLANK)
            self.sub:SetText(x.qty.." in stack · "..(x.eligible==true and "Eligibility verified" or "Eligibility unknown / blocked"))
            self:SetSelected(p.selected==x.key)
        end
        r:SetScript("OnClick",function()
            if not r.data then return end
            p.selected=r.data.key;p.quantity:SetText(tostring(r.data.qty));AD.Request(r.data.item);Detail(p)
            p.list:Layout()
        end)
        r:SetScript("OnEnter",function()
            if r.data and GameTooltip and GameTooltip.SetBagItem then
                GameTooltip:SetOwner(r,"ANCHOR_RIGHT");GameTooltip:SetBagItem(r.data.bag,r.data.slot);GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
        return r
    end,400,false)
    p.list.box:SetPoint("TOPLEFT",4,-36);p.list.box:SetPoint("BOTTOMRIGHT",-4,8)
    local form=A.Card(p,"Posting preparation",100)
    form:SetPoint("TOPLEFT",left,"TOPRIGHT",10,0);form:SetPoint("BOTTOMRIGHT",-380,0)
    local function Field(label,y,initial)
        A.Text(form,label,14,12,y)
        local f=UI.Search(form,180,30,"");f:SetPoint("TOPLEFT",12,y-26);f:SetText(initial);f:SetMaxLetters(16)
        f:SetScript("OnTextChanged",function() Detail(p) end)
        return f
    end
    p.quantity=Field("Quantity from selected stack",-50,"1")
    p.price=Field("Unit price · copper",-125,"")
    A.Text(form,"Stack size follows the selected bag stack.\nArbitrary stack splitting is not verified.",12,12,-208,-12,UI.K.textDim)
    p.duration=A.Dropdown(form,220,function()
        local out={}
        for i,name in ipairs({AUCTION_DURATION_ONE or "Duration 1 (unverified)",AUCTION_DURATION_TWO or "Duration 2 (unverified)",AUCTION_DURATION_THREE or "Duration 3 (unverified)"}) do out[#out+1]={i,name} end
        return out
    end,function() return p.durationIndex or 1 end,function(i) p.durationIndex=i;Detail(p) end)
    p.duration:SetPoint("TOPLEFT",12,-260)
    p.match=UI.Button(form,"Use qualified suggestion",240,"secondary",function()
        local s=p.suggestion
        if s and s.state=="ok" then p.price:SetText(tostring(s.price));Detail(p)
        else A.Note("No supported price suggestion. Enter a price manually.") end
    end,30);p.match:SetPoint("TOPLEFT",12,-308)
    p.total=A.Text(form,"",13,12,-356);p.total:SetWordWrap(true);p.total:SetHeight(80)
    p.validation=A.Text(form,"",12,12,-448,-12,UI.K.textDim);p.validation:SetWordWrap(true);p.validation:SetHeight(80)
    p.post=UI.Button(form,"Post unavailable",180,"primary",nil,32);p.post:SetPoint("BOTTOMLEFT",12,12);p.post:SetEnabled(false)
    UI.Tip(p.post,"Posting disabled","Real-client transaction, confirmation and runtime acceptance are pending. This page has no posting handler.")
    p.detail=A.Details(p,370);p.detail:SetPoint("TOPRIGHT",0,-48);p.detail:SetPoint("BOTTOMRIGHT",0,0)
    p.history=A.Text(p.detail.body,"",13,12,-108);p.history:SetWordWrap(true);p.history:SetHeight(100)
    p.chart=UI.PriceChart(p.detail.body,320,90);p.chart:SetPoint("TOPLEFT",8,-230)
    p.advice=A.Text(p.detail.body,"",13,12,-350);p.advice:SetWordWrap(true);p.advice:SetHeight(220)
    p:SetScript("OnEvent",function() A.Schedule() end)
end
A.Register("sell",{Build=Build,Render=function(p)
    if not p.listening then
        p:RegisterEvent("BAG_UPDATE_DELAYED");p:RegisterEvent("GET_ITEM_INFO_RECEIVED");p.listening=true
    end
    Refresh(p)
end,Release=function(p)
    p:UnregisterAllEvents();p.listening=false;p.rows=nil;p.chosen=nil;p.suggestion=nil
    p.selected=nil;p.quantity:SetText("1");p.price:SetText("");p.list:SetData({})
end})
