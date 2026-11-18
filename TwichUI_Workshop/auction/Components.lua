-- Shared presentation pieces for the approved AH cards and filters. No game actions.
local R, W = TwichUI, TwichUI.Workshop
local A, UI = W.AuctionUI, W.UI
function A.PatchRows(list,updates)
    for _,row in ipairs(list.rows) do
        if row:IsShown() and row.data and updates[row.data.item] then
            row.fill(row,row.data);W.AuctionBrowseData.Count("rowUpdates")
        end
    end
end

-- Familiar denomination fields using the same coin atlases as the native
-- money input used by Sell from Bags. No search decoration or raw-copper field.
function A.MoneyInputs(parent,changed)
    local f=CreateFrame("Frame",nil,parent);f:SetSize(286,34)
    f.fields={}
    for i,def in ipairs({{"Gold",110,"coin-gold"},{"Silver",80,"coin-silver"},{"Copper",80,"coin-copper"}}) do
        local x=i==1 and 0 or i==2 and 118 or 206
        local box=UI.L.EditBox(f,def[2],32);UI.CL.Dress(box,"field")
        box:SetPoint("TOPLEFT",x,0);box:SetTextInsets(8,30,0,0);box:SetMaxLetters(i==1 and 7 or 2);box:SetNumeric(true)
        box:SetJustifyH("RIGHT")
        -- The field skin uses child frames; keep coin art above that skin.
        box.coinFrame=CreateFrame("Frame",nil,box);box.coinFrame:SetSize(20,20)
        box.coinFrame:SetPoint("RIGHT",-6,0);box.coinFrame:SetFrameLevel(box:GetFrameLevel()+3);box.coinFrame:EnableMouse(false)
        box.coin=box.coinFrame:CreateTexture(nil,"OVERLAY");box.coin:SetAllPoints();box.coin:SetAtlas(def[3])
        UI.Tip(box,def[1],def[1].." portion of the price per item.")
        box:SetScript("OnTextChanged",function() if not f.setting and changed then changed() end end)
        box:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        f.fields[i]=box
    end
    for i,box in ipairs(f.fields) do
        box:SetScript("OnTabPressed",function() local nextBox=f.fields[i%3+1];nextBox:SetFocus();nextBox:HighlightText() end)
    end
    f.gold,f.silver,f.copper=f.fields[1],f.fields[2],f.fields[3]
    function f:GetCopper() return W.AuctionSellData.Money(self.gold:GetText(),self.silver:GetText(),self.copper:GetText()) end
    function f:SetCopper(n)
        local g,s,c=W.AuctionSellData.Coins(n)
        self.setting=true;self.gold:SetText(g);self.silver:SetText(s);self.copper:SetText(c);self.setting=false
        if changed then changed() end
    end
    return f
end

function A.Text(parent, text, size, x, y, right, color)
    local t = UI.Text(parent, size or 14, color or UI.K.text)
    t:SetPoint("TOPLEFT", x or 12, y or -12)
    t:SetPoint("RIGHT", right or -12, 0); t:SetText(text or "")
    return t
end
function A.Card(parent, title, height)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(height); UI.Panel(c, "card")
    c.heading = A.Text(c, title, 17, 12, -9, -12, UI.K.bronzeText)
    return c
end
function A.Dropdown(parent, width, choices, current, choose)
    local menu, b
    b = R.ChronicleStyle.DropButton(parent, width, function()
        if menu then menu:Close(); menu = nil end
        local desc = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
        desc:SetMinimumWidth(width); desc:SetScrollMode(300)
        for _, entry in ipairs(choices()) do
            local value, text = entry[1], entry[2]
            desc:CreateRadio(text, function() return current() == value end, function()
                if A.MenuSound then A.MenuSound() end
                choose(value)
                b:Refresh()
            end)
        end
        desc:AddMenuReleasedCallback(function() menu = nil end)
        menu = Menu.GetManager():OpenMenu(b, desc, AnchorUtil.CreateAnchor("TOPLEFT", b, "BOTTOMLEFT", 0, -2))
    end, UI.K)
    b:SetHeight(32); UI.CL.Dress(b, "dropdown")
    function b:Refresh()
        for _, entry in ipairs(choices()) do if entry[1] == current() then self.text:SetText(entry[2]); return end end
    end
    b:HookScript("OnHide", function() if menu then menu:Close(); menu = nil end end)
    b:Refresh()
    return b
end
-- Keep the top identity and within-row offset independently from selection.
function A.Capture(list, key)
    local pixel = list.scroll:GetVerticalScroll() or 0
    local row = list.data[math.floor(pixel / list.rowH) + 1]
    return { key = row and key(row), offset = pixel % list.rowH, pixel = pixel }
end
function A.Restore(list, view, key)
    local pixel = view and view.pixel or 0
    if view and view.key then
        for i, row in ipairs(list.data) do
            if key(row) == view.key then pixel = (i - 1) * list.rowH + view.offset; break end
        end
    end
    local h = list.scroll:GetHeight() or 0
    if h <= list.rowH then h = list.minH end
    list.scroll:SetVerticalScroll(math.max(0, math.min(pixel, #list.data * list.rowH - h)))
    list:Layout()
end
-- A page-local detail scroller keeps actions below the cards and inside the frame.
function A.Details(parent, width)
    local d = CreateFrame("Frame", nil, parent)
    d:SetWidth(width); UI.Panel(d, "card")
    d.scroll = CreateFrame("ScrollFrame", nil, d, "UIPanelScrollFrameTemplate")
    d.scroll:SetPoint("TOPLEFT", 6, -6); d.scroll:SetPoint("BOTTOMRIGHT", -24, 52)
    UI.CL.ScrollRail(d.scroll)
    d.body = CreateFrame("Frame", nil, d.scroll)
    d.body:SetSize(width - 32, 620); d.scroll:SetScrollChild(d.body)
    d.scroll:HookScript("OnSizeChanged", function(_, w) if w and w > 1 then d.body:SetWidth(w) end end)
    d.pic = UI.ItemIcon(d.body, 58); d.pic:SetPoint("TOPLEFT", 12, -12)
    d.name = A.Text(d.body, "Choose an item", 22, 82, -14)
    d.name:SetWordWrap(true); d.name:SetHeight(52)
    d.kind = A.Text(d.body, "", 12, 12, -78, -12, UI.K.textDim)
    return d
end
function A.TrackButton(parent, getItem)
    local b
    b = UI.Button(parent, "Track", 100, "secondary", function()
        local item = getItem()
        if item then
            local ok = W.AdvisorData.Track(item)
            A.Note(ok and "Tracking updated in the shared Item Advisor list." or "Tracking could not be saved (list full or saved data read-only).")
            b.text:SetText(W.AdvisorData.Tracked()[item] and "Untrack" or "Track")
        end
    end, 32)
    return b
end

-- Explicit research navigation only. Resolve context before Go releases the source page.
function A.HistoryButton(parent, getContext, width)
    return UI.Button(parent, "Open Market history", width or 240, "secondary", function()
        local item,opt=getContext()
        if item then A.OpenMarket(item,opt) end
    end, 30)
end
