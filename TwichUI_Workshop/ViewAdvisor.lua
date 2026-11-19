-- A8: Item Advisor inside the existing Workshop shell. The list pools visible rows;
-- discovery/search run in cancellable batches. Only selected detail requests a plan.
local R = TwichUI
local W = R.Workshop
local UI, D, A, S = W.UI, W.AdvisorData, W.Advisor, W.Session
local V = {}
UI.Advisor = V
local page, K, catalog, stamp, selected, result
local query, source, category, auctionable = "", D.Source(), nil, false
local token, searchToken = 0, 0
local filtered, categories = {}, {}
local reveal, searchDirty, resetView = false, false, false
local viewport
local Paint, Search, Render
local function CaptureViewport()
    if not page or #page.list.data==0 then return viewport end
    local pixel=page.list.scroll:GetVerticalScroll() or 0
    local row=page.list.data[math.floor(pixel/64)+1]
    return {item=row and row.item, offset=pixel%64, pixel=pixel}
end
local function RestoreViewport(view)
    local pixel=view and view.pixel or 0
    for i,row in ipairs(filtered) do
        if view and view.item and row.item>=view.item then pixel=(i-1)*64+view.offset; break end
    end
    local h=page.list.scroll:GetHeight() or 0
    if h<=64 then h=page.list.minH end
    page.list.scroll:SetVerticalScroll(math.min(math.max(0,#filtered*64-h),pixel))
    page.list:Layout()
end
local function Name(row) return row.info.name end
local function Category(info) return (info.category or "Item") .. (info.sub and info.sub ~= "" and (" \194\183 " .. info.sub) or "") end
local function Color(fs, quality)
    if quality and C_Item and C_Item.GetItemQualityColor then
        local r,g,b=C_Item.GetItemQualityColor(quality)
        if W.Finite(r) and W.Finite(g) and W.Finite(b) then fs:SetTextColor(r,g,b); return end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    if c then fs:SetTextColor(c.r,c.g,c.b) else UI.Paint(fs,K.text) end
end
local function Select(item)
    selected = item
    D.Select(item); D.Request(item,true)
    if page then page.detail.scroll:SetVerticalScroll(0); Paint() end
end
function V.Open(item)
    if not W.Int(item,1,W.MAX_ID) then return false end
    selected = item; D.Select(item); D.Request(item,true); reveal=true
    -- Explicit cross-page entry may reveal an item outside the saved source.
    -- This temporary source does not replace the player's discovery preference.
    query,source,category,auctionable="","all",nil,false
    if page then page.resetFilters(); page.detail.scroll:SetVerticalScroll(0) end
    stamp = nil
    if W.Window then W.Window.Show(); W.Window.SetMode("advisor") end
    return true
end
local function MakeRow(parent)
    local row = CreateFrame("Button",nil,parent)
    UI.Hover(row)
    row.pic = UI.ItemIcon(row,36); row.pic:SetPoint("LEFT",10,0)
    row.name = UI.Text(row,15,K.text,"serif")
    row.name:SetPoint("TOPLEFT",54,-9); row.name:SetPoint("RIGHT",-98,0); row.name:SetMaxLines(2); row.name:SetWordWrap(true)
    row.sub = UI.Text(row,11,K.textDim); row.sub:SetPoint("BOTTOMLEFT",54,8); row.sub:SetPoint("RIGHT",-10,0)
    row.badge = UI.Text(row,11,K.bronzeText,"strong"); row.badge:SetPoint("TOPRIGHT",-10,-14); row.badge:SetWidth(86); row.badge:SetMaxLines(2); row.badge:SetWordWrap(true); row.badge:SetJustifyH("RIGHT")
    row:SetScript("OnClick",function() if row.data then Select(row.data.item) end end)
    UI.ItemTip(row,function() return row.data and row.data.item end)
    row.twichRowClick = function() if row.data then Select(row.data.item) end end
    function row:fill(data)
        self.data = data
        self.pic.tex:SetTexture(data.info.icon or UI.ICON_BLANK)
        self.name:SetText(Name(data)); Color(self.name,data.info.quality)
        self.sub:SetText(Category(data.info))
        -- Bounded visible rows only; MarketFacts supplies cached evidence.
        local rec = D.Decide(data.item,false,data)
        self.badge:SetText(A.Short(rec)); self:SetSelected(selected == data.item)
    end
    return row
end
local function Text(parent,size,color,x,y,right)
    local fs=UI.Text(parent,size,color)
    fs:SetPoint("TOPLEFT",x,y); fs:SetPoint("RIGHT",right or -12,0)
    return fs
end
local function WhyText(r)
    local lines={}
    for i=1,math.min(4,#r.reasons) do lines[#lines+1]="\226\128\162 " .. r.reasons[i] end
    return table.concat(lines,"\n")
end
local function Uses()
    local row = catalog and catalog.byID[selected]
    local uses = row and row.uses or {}
    if #uses == 0 then return end
    if not page.uses then
        local f=CreateFrame("Frame",nil,page,"BackdropTemplate")
        f:SetSize(470,340); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:EnableMouse(true); UI.Panel(f,"card")
        local title=Text(f,20,K.text,16,-14,-44); title:SetText("Known recipe uses")
        f.close=UI.Button(f,"X",26,"secondary",function() f:Hide() end,26); f.close:SetPoint("TOPRIGHT",-10,-10)
        f.list=UI.List(f,46,function(parent)
            local b=CreateFrame("Button",nil,parent); UI.Hover(b)
            b.name=Text(b,14,K.text,10,-7,-10)
            b.sub=Text(b,11,K.textDim,10,-25,-10); b.sub:SetText("View crafting strategy")
            b:SetScript("OnClick",function() if b.rec and UI.StrategyView then f:Hide(); UI.StrategyView.Open("opp",b.rec) end end)
            function b:fill(rec) self.rec=rec; self.name:SetText(rec.name) end
            return b
        end,240)
        f.list.box:SetPoint("TOPLEFT",12,-50); f.list.box:SetPoint("BOTTOMRIGHT",-12,12)
        page.uses=f
    end
    page.uses.list:SetData(uses); page.uses:Show()
end
local function BuildDetails(parent)
    local d=CreateFrame("Frame",nil,parent); UI.Panel(d,"card"); page.detail=d
    d.empty=Text(d,16,K.textDim,18,-20,-18); d.empty:SetWordWrap(true); d.empty:SetText("Choose an item to compare your options.")
    -- Scroll the whole evidence pane on the established 1200x700 shell. Actions
    -- stay at the foot so they remain reachable at small screen/UI scales.
    d.scroll=CreateFrame("ScrollFrame",nil,d,"UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("TOPLEFT",6,-6); d.scroll:SetPoint("BOTTOMRIGHT",-22,52)
    UI.CL.ScrollRail(d.scroll)
    local b=CreateFrame("Frame",nil,d.scroll); d.body=b; b:SetSize(540,828); d.scroll:SetScrollChild(b)
    d.icon=UI.ItemIcon(b,44); d.icon:SetPoint("TOPLEFT",10,-8)
    d.itemButton=CreateFrame("Button",nil,b); d.itemButton:SetAllPoints(d.icon); UI.ItemTip(d.itemButton,function() return selected end)
    d.name=Text(b,23,K.text,64,-8,-10); d.name:SetWordWrap(true); d.name:SetMaxLines(2)
    d.type=Text(b,12,K.textDim,64,-42,-10)
    d.rec=CreateFrame("Frame",nil,b); d.rec:SetPoint("TOPLEFT",8,-66); d.rec:SetPoint("TOPRIGHT",-8,-66); d.rec:SetHeight(68); UI.Panel(d.rec,"card"); UI.CL.Sheet(d.rec,"selection",{layer="BACKGROUND",sub=4,corner=8})
    d.action=Text(d.rec,17,K.bronzeText,12,-8,-12); d.action:SetWordWrap(true); d.action:SetMaxLines(2)
    d.evidence=Text(d.rec,11,K.textDim,12,-46,-12)
    UI.TipFn(d.rec,"Recommendation evidence",function() return result and (table.concat(result.reasons,"\n") .. "\n" .. table.concat(result.missing,"\n")) end)
    d.cards={}
    local labels={"Suggested listing / item","Market value (14d)","Recent listing / item","Historical value (60d)","Listed competition","Vendor sell / item"}
    for i,label in ipairs(labels) do
        local f=CreateFrame("Frame",nil,b); f:SetHeight(45); UI.Panel(f,"canvas")
        f.label=Text(f,10,K.textDim,9,-6,-6); f.label:SetText(label)
        f.value=Text(f,15,K.text,9,-22,-6)
        d.cards[i]=f
    end
    d.history=Text(b,16,K.text,10,-246,-10); d.history:SetText("Observed price history")
    d.chart=UI.AdvancedMarketChart(b,524,184); d.chart:SetPoint("TOPLEFT",8,-268)
    d.chartLabel=Text(b,10,K.stone,12,-460,-10)
    d.why=UI.Text(b,16,K.bronzeText,"serif"); d.why:SetPoint("TOPLEFT",12,-490);d.why:SetPoint("RIGHT",-12,0);d.why:SetHeight(22); d.why:SetText("Why this recommendation?")
    d.reasons=UI.Text(b,12,K.textDim); d.reasons:SetPoint("TOPLEFT",12,-518); d.reasons:SetPoint("RIGHT",-10,0); d.reasons:SetHeight(106); d.reasons:SetWordWrap(true); d.reasons:SetJustifyV("TOP")
    d.alt=CreateFrame("Frame",nil,b); d.alt:SetPoint("TOPLEFT",8,-640); d.alt:SetPoint("TOPRIGHT",-8,-640); d.alt:SetHeight(136); UI.Panel(d.alt,"canvas")
    d.altTitle=Text(d.alt,17,K.bronzeText,10,-7,-10); d.altTitle:SetText("Alternatives")
    d.alts={}
    for i=1,5 do
        local f=CreateFrame("Frame",nil,d.alt); f:SetPoint("TOPLEFT",10,-(30+(i-1)*20)); f:SetPoint("TOPRIGHT",-10,-(30+(i-1)*20)); f:SetHeight(20)
        f.name=Text(f,12,K.text,0,0,-10); f.name:SetWidth(74); f.name:ClearAllPoints(); f.name:SetPoint("TOPLEFT",0,0)
        f.value=Text(f,12,K.textDim,80,0,-10)
        d.alts[i]=f
    end
    d.limit=Text(b,11,K.stone,12,-784,-12); d.limit:SetWordWrap(true); d.limit:SetHeight(32)
    d.track=UI.ArtButton(d,"Track item","guide",150,"secondary",function() if selected then D.Track(selected); stamp=nil; Render() end end,30)
    d.recipes=UI.ArtButton(d,"Recipe uses","npc:hammer",150,"secondary",Uses,30)
    d.sources=UI.ArtButton(d,"Shopping sources","npc:leather-backpack",150,"secondary",function()
        if selected and UI.OpenShopping then UI.OpenShopping(selected) else UI.Go("shop") end
    end,30)
    d.track:SetPoint("BOTTOMLEFT",10,12); d.recipes:SetPoint("LEFT",d.track,"RIGHT",6,0); d.sources:SetPoint("LEFT",d.recipes,"RIGHT",6,0)
    local function Layout()
        local w=math.max(480,d:GetWidth()-30)
        b:SetWidth(w)
        local cw=(w-28)/3
        for i,f in ipairs(d.cards) do
            f:ClearAllPoints(); f:SetWidth(cw); f:SetPoint("TOPLEFT",8+((i-1)%3)*(cw+6),-(144+math.floor((i-1)/3)*51))
        end
        local extra=math.max(0,(d.name:GetStringHeight() or 24)-24)
        d.type:ClearAllPoints(); d.type:SetPoint("TOPLEFT",64,-42-extra); d.type:SetPoint("RIGHT",-10,0)
        d.rec:ClearAllPoints(); d.rec:SetPoint("TOPLEFT",8,-66-extra); d.rec:SetPoint("TOPRIGHT",-8,-66-extra)
        for i,f in ipairs(d.cards) do f:ClearAllPoints(); f:SetPoint("TOPLEFT",8+((i-1)%3)*(cw+6),-(144+extra+math.floor((i-1)/3)*51)) end
        d.history:ClearAllPoints(); d.history:SetPoint("TOPLEFT",10,-246-extra)
        d.chart:ClearAllPoints(); d.chart:SetPoint("TOPLEFT",8,-268-extra);d.chart:SetPoint("TOPRIGHT",-8,-268-extra)
        d.chartLabel:ClearAllPoints(); d.chartLabel:SetPoint("TOPLEFT",12,-460-extra)
        d.why:ClearAllPoints();d.why:SetPoint("TOPLEFT",12,-490-extra);d.why:SetPoint("RIGHT",-12,0)
        d.reasons:ClearAllPoints();d.reasons:SetPoint("TOPLEFT",12,-518-extra);d.reasons:SetPoint("RIGHT",-12,0)
        d.alt:ClearAllPoints(); d.alt:SetPoint("TOPLEFT",8,-640-extra); d.alt:SetPoint("TOPRIGHT",-8,-640-extra)
        d.limit:ClearAllPoints(); d.limit:SetPoint("TOPLEFT",12,-784-extra); d.limit:SetPoint("RIGHT",-12,0)
        b:SetHeight(828+extra)
        local bw=(d:GetWidth()-32)/3
        for _,button in ipairs({d.track,d.recipes,d.sources}) do button:SetWidth(bw) end
    end
    d:SetScript("OnSizeChanged",Layout); d.layout=Layout
    return d
end
local function PaintDetail()
    local d=page.detail
    local row = catalog and catalog.byID[selected]
    d.empty:SetShown(not row); d.scroll:SetShown(row~=nil)
    d.track:SetShown(row~=nil); d.recipes:SetShown(row~=nil); d.sources:SetShown(row~=nil)
    if not row then d.chart:Clear();result=nil; return end
    local r=D.Decide(selected,true,row); result=r; page.result=r
    local f=r.facts or {}; local info=row.info
    d.name:SetText(info.name); Color(d.name,info.quality); d.icon.tex:SetTexture(info.icon or UI.ICON_BLANK)
    d.type:SetText(Category(info) .. " \194\183 " .. (row.count and (row.count .. " in bags") or "Bag count unknown"))
    d.action:SetText(r.text); d.evidence:SetText(r.evidenceText)
    local vals={r.suggestion.price, f.mval and f.mval.value, f.recent and f.recent.value, f.hist and f.hist.value, false, info.sell}
    for i,card in ipairs(d.cards) do card.value:SetText(vals[i]~=nil and vals[i]~=false and UI.Money(vals[i]) or "Unavailable") end
    d.cards[5].value:SetText(f.supply and (UI.Num(f.supply.items) .. " items / " .. (f.supply.listings and UI.Num(f.supply.listings) or "unknown") .. " listings") or "Unknown")
    for i,card in ipairs(d.cards) do
        UI.Tip(card,card.label:GetText(),i==1 and "Match the lowest supported competing tier per item. Gross listing value; a sale is not guaranteed." or
            (i==6 and "Actual vendor sell value for one item, not the price to buy it." or "Observed listings only. Historical values are references, not selling prices."))
    end
    d.reasons:SetText(WhyText(r))
    local chartSeries=W.Facts.Chart(f)
    d.chart:Set(W.AdvancedChart.FromObserved(chartSeries),UI.Money,
        "workshop:advisor:"..tostring(selected)..":"..tostring(f.key))
    d.chartLabel:SetText(chartSeries and chartSeries.external and "Market server · Recent Price · gaps remain unfilled" or "Observed daily lows \194\183 gaps remain unfilled")
    for i,alt in ipairs(r.alternatives) do
        local line=d.alts[i]
        line.name:SetText(alt.action=="craft" and "Craft" or (alt.action=="auction" and "Auction" or (alt.action=="vendor" and "Vendor" or (alt.action=="disenchant" and "Disenchant" or "Watch"))))
        local value = alt.state=="unavailable" and "Unavailable" or (alt.value and UI.Money(alt.value) or (alt.state=="choice" and "Refresh manually" or "Unknown"))
        if alt.action=="craft" then value=r.crafting.reserved>0 and ("Needed for plan (" .. r.crafting.reserved .. ")") or (#row.uses>0 and (#row.uses .. " known uses; compare strategy") or "No known recipe uses") end
        if alt.action=="auction" and alt.value then value=value .. (alt.state=="observed" and " observed / item (limited)" or " gross / item") end
        if alt.action=="disenchant" and alt.value then value=value .. " expected materials" end
        line.value:SetText(value); UI.Tip(line,line.name:GetText(),alt.note)
    end
    d.limit:SetText(r.proceeds and r.proceeds.state=="ok" and ("Gross for " .. (r.qty or 1) .. ": " .. UI.Money(r.proceeds.gross) .. ". Fees, deposits and sale likelihood unknown.") or (r.missing[1] or "Manually refreshed observations; future prices are unknown."))
    if r.observed then d.limit:SetText("Observed: " .. UI.Money(r.observed.value) .. " / item; not a suggested posting price. Fees and sale outcome unknown.") end
    d.track.text:SetText(D.Tracked()[selected] and "Untrack item" or "Track item")
    d.recipes:SetEnabled(#row.uses>0)
    d.sources:SetEnabled((r.crafting.reserved or 0)>0)
    UI.Tip(d.sources,"Shopping sources","Open this material in your active plan's Shopping page. Available for materials needed by that plan.")
    d.layout()
end
Paint=function()
    if not page or not page:IsShown() then return end
    page.results:SetText(("Results (%d) \194\183 Item ID order"):format(#filtered))
    page.list:SetData(filtered,(catalog and #catalog.rows==0) and "No known items yet.\nOpen a profession or scan prices manually." or "No matching known items.\nTry another search or filter.")
    page.detail.empty:SetText((catalog and #catalog.rows==0) and "No items remembered yet. Open a profession, carry an item, or scan prices manually." or "Choose an item to compare your options.")
    PaintDetail()
end
Search=function(reset)
    resetView=resetView or reset==true
    searchDirty=false
    searchToken=searchToken+1
    local mine=searchToken
    if not catalog or not catalog.done then return end
    local output, at={},1
    page.results:SetText("Searching known items...")
    local function Step()
        if mine~=searchToken or not page:IsShown() then return end
        local pt=R.Perf and R.Perf.on and R.Perf.Start("workshop.advisorSearch")
        local last=math.min(#catalog.rows,at+D.BATCH-1)
        for i=at,last do local row=catalog.rows[i]; if D.Matches(row,query,source,auctionable,category) then output[#output+1]=row end end
        if pt then R.Perf.Stop(pt) end
        at=last+1
        if at<=#catalog.rows then C_Timer.After(0,Step) else
            local view=CaptureViewport()
            filtered=output
            local present=false; for _,r in ipairs(filtered) do if r.item==selected then present=true break end end
            if not present then selected=filtered[1] and filtered[1].item; if selected then D.Select(selected) end end
            if selected then D.Request(selected) end
            Paint()
            if reveal and selected then
                RestoreViewport({item=selected,offset=0,pixel=0})
            elseif resetView then RestoreViewport(nil)
            else RestoreViewport(view) end
            reveal,resetView,viewport=false,false,nil
        end
    end
    Step()
end
function V.Invalidate() stamp=nil end
function V.ItemReady(item, success)
    if not page or not page:IsShown() or success==false or not catalog then return end
    local row=catalog.byID[item]
    if not row then return end
    local info,old=D.Info(item),row.info or {}
    if not row.info or row.info.quality~=info.quality or row.info.classID~=info.classID then W.Facts.CacheClear() end
    local oldSearch=row.search
    row.info=info; row.search=(info.name .. " " .. item):lower()
    if info.category and info.category~="" then
        local found=false; for _,name in ipairs(categories) do if name==info.category then found=true break end end
        if not found then categories[#categories+1]=info.category; table.sort(categories) end
    end
    -- Most item events change only painted values. Search again only when
    -- metadata can change membership of an active filter, never just on hover.
    if (query~="" and oldSearch~=row.search) or (category and old.category~=info.category)
        or (auctionable and old.bindType~=info.bindType) then searchDirty=true end
end
function V.Stats() return { items=catalog and #catalog.rows or 0, results=#filtered, running=catalog and not catalog.done or false } end
local function Key()
    local m=S.PriceSource().market
    return table.concat({m and (m.generation or W.Valuation.Generation(m)) or "none",tostring(W.Strategy.epoch),tostring(S.observations)},"|")
end
Render=function()
    if not page or not page:IsShown() then return end
    local key=Key()
    if stamp==key and catalog then if catalog.done then if searchDirty then Search() else Paint() end end return end
    stamp=key; token=token+1; searchToken=searchToken+1
    local mine=token
    catalog=D.Catalog(); page.results:SetText("Gathering known items...")
    local function Step()
        if mine~=token or not page:IsShown() then return end
        local done,err=catalog:Step()
        if err then page.results:SetText("Item information unavailable."); return end
        if not done then C_Timer.After(0,Step) else
            local set={}; categories={}
            for _,r in ipairs(catalog.rows) do if r.info.category and r.info.category~="" then set[r.info.category]=true end end
            for name in pairs(set) do categories[#categories+1]=name end; table.sort(categories)
            selected=selected or D.Selected()
            Search()
        end
    end
    Step()
end
local function Build(p)
    page,K=p,UI.K
    p.sub:SetText("Compare your options using listings, vendor values and your crafting plan.")
    p.search=UI.Search(p,280,30,"Search known items..."); p.search:SetPoint("TOPLEFT",0,-62)
    p.search:SetScript("OnTextChanged",function(self)
        query=self:GetText() or ""; searchToken=searchToken+1
        p.search.hint:SetShown(query=="" and not self:HasFocus())
        local mine=searchToken; C_Timer.After(0.15,function() if mine==searchToken then Search(true) end end)
    end)
    local sources={{"bags","In bags"},{"tracked","Tracked items"},{"all","All known items"}}
    local function SourceLabel()
        for _,entry in ipairs(sources) do if entry[1]==source then return entry[2] end end
    end
    -- Use the core's dropdown trigger and Forever's native radio menus: the
    -- menu manager owns positioning, scale, Escape/outside dismissal and pooling.
    local menu
    local function Dropdown(label, choices, current, choose)
        local b
        b=R.ChronicleStyle.DropButton(p,145,function()
            if menu then menu:Close(); menu=nil end
            local root=MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
            do
                root:SetMinimumWidth(145); root:SetScrollMode(320)
                for _,entry in ipairs(choices()) do
                    local value,text=entry[1],entry[2]
                    local radio=root:CreateRadio(text,function() return current()==value end,function()
                        local changed=current()~=value
                        choose(value)
                        if changed then Search(true) end
                    end)
                    radio:AddInitializer(function(button)
                        if button.fontString then UI.Paint(button.fontString,current()==value and K.bronzeText or K.text) end
                    end)
                end
                root:AddMenuReleasedCallback(function() menu=nil end)
            end
            menu=Menu.GetManager():OpenMenu(b,root,AnchorUtil.CreateAnchor("TOPLEFT",b,"BOTTOMLEFT",0,-2))
        end,UI.K)
        b:SetHeight(30); UI.CL.Dress(b,"dropdown"); b.text:SetText(label)
        return b
    end
    p.source=Dropdown(SourceLabel(),function() return sources end,function() return source end,function(value)
        source=value; D.SetSource(value); p.source.text:SetText(SourceLabel())
    end); p.source:SetPoint("LEFT",p.search,"RIGHT",10,0)
    UI.Tip(p.source,"Item source","Choose carried items, tracked items or known identities from your saved market and recipes. No bank contents or global item database are implied.")
    p.category=Dropdown("All categories",function()
        local choices={{false,"All categories"}}
        for _,name in ipairs(categories) do choices[#choices+1]={name,name} end
        return choices
    end,function() return category or false end,function(value)
        category=value or nil; p.category.text:SetText(category or "All categories")
    end); p.category:SetPoint("LEFT",p.source,"RIGHT",8,0)
    p.auctionable=UI.Switch(p,"Auctionable",function(b) auctionable=not auctionable; b:SetOn(auctionable); Search(true) end)
    p.auctionable:SetPoint("TOPRIGHT",-2,-67)
    UI.Tip(p.auctionable,"Known auction eligibility","Only item types confirmed unbound. Bound-on-equip and bound-on-use copies require individual inspection.")
    p.card=CreateFrame("Frame",nil,p); p.card:SetPoint("TOPLEFT",0,-104); p.card:SetPoint("BOTTOMLEFT",0,0); p.card:SetWidth(300); UI.Panel(p.card,"card")
    p.results=Text(p.card,12,K.textDim,12,-12,-10)
    p.list=UI.List(p.card,64,MakeRow,320,false); UI.lists.advisor=p.list
    p.list.box:SetPoint("TOPLEFT",4,-35); p.list.box:SetPoint("BOTTOMRIGHT",-4,8)
    local d=BuildDetails(p); d:SetPoint("TOPLEFT",p.card,"TOPRIGHT",10,0); d:SetPoint("BOTTOMRIGHT",0,0)
    local function Layout()
        local w=p:GetWidth(); if w<=0 then w=940 end
        p.card:SetWidth(math.max(260,math.floor(w*0.34)))
        p.list.empty:ClearAllPoints(); p.list.empty:SetPoint("TOPLEFT",14,-14); p.list.empty:SetWidth(math.max(180,p.card:GetWidth()-46)); p.list.empty:SetHeight(92)
        p.detail.empty:ClearAllPoints(); p.detail.empty:SetPoint("TOPLEFT",18,-20); p.detail.empty:SetWidth(math.max(300,w-p.card:GetWidth()-52)); p.detail.empty:SetHeight(92)
        p.search:SetWidth(math.max(220,w-534))
    end
    p.resetFilters=function()
        p.search:SetText(""); p.source.text:SetText(SourceLabel()); p.category.text:SetText("All categories"); p.auctionable:SetOn(false)
    end
    p:SetScript("OnSizeChanged",Layout)
    p:HookScript("OnHide",function()
        if menu then menu:Close(); menu=nil end
        viewport=CaptureViewport()
        token=token+1; searchToken=searchToken+1; catalog=nil; filtered={}; stamp=nil; result=nil; searchDirty=false
        p.list:SetData({}); p.result=nil
        for _,row in ipairs(p.list.rows) do row.data=nil end
        if p.uses then
            p.uses:Hide(); p.uses.list:SetData({})
            for _,row in ipairs(p.uses.list.rows) do row.rec=nil end
        end
    end)
    p:HookScript("OnShow",Render)
    Layout()
end
UI.Register({key="advisor",nav="Item Advisor",icon="guide",title="Item Advisor",
    sub="Research an item to compare your options.",Build=Build,Render=Render})
