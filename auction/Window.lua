-- TwichUI: auction posting, the "Sell from Bags" tab
-- A fourth tab along the bottom of the Auction House. It lists what in your
-- bags can be listed; picking an item searches the current listings for that
-- item only and suggests matching the lowest comparable one, saying what that
-- is based on. You set quantity, price and duration; nothing is posted until
-- you press Post, and the game's own confirmation is used when it asks for one.
--
-- Everything here is TwichUI's own frames: the tab and the page are children of
-- a holder frame on Blizzard's Auction House window. Blizzard's tables are only
-- read; its methods are only followed with hooksecurefunc.
--
-- Look: when EllesmereUI styles TwichUI (R.S), every surface and control here
-- goes through its skin toolkit so the page matches the skinned Auction House.
-- Without it, the Chronicle's warm surfaces with Blizzard's standard controls.

local R = TwichUI
local P, SC, ST = R.AuctionPrice, R.AuctionScan, R.ChronicleStyle
local A = {}
R.AuctionWindow = A

local K = ST.color
local ROW_H, LIST_ROW_H, HEADER_H = 24, 18, 18
local LEFT_W = 300
local MAX_LISTING_ROWS = 100
local POST_TIMEOUT = 10
-- Blizzard's sell frame puts its item display and post button at frame level
-- 350 and favourite stars in HIGH strata; the page sits above both, and below
-- the game's own confirmation dialog (DIALOG strata).
local PAGE_STRATA, PAGE_LEVEL = "HIGH", 500

local AH                       -- AuctionHouseFrame, once Blizzard_AuctionHouseUI has loaded
local holder, tab, page        -- our frames on it
local ev = CreateFrame("Frame")

local S                        -- EllesmereUI's skin toolkit, when it styles TwichUI
local C = {}                   -- text and accent colours for the look in use

local groups, unlisted = {}, 0 -- bag items that can be listed, grouped
local selected                 -- the chosen group
local priceEdited = false      -- the player has typed a price for this item
local settingPrice = false     -- we are filling the price box ourselves
local duration                 -- 1..3, as the game's duration choice
local post = { state = "idle" } -- idle, posting, confirm, multisell
local message                  -- last posting outcome line
local retryScheduled = false
local filledPrice = 0          -- what we last put in the price box

local function Money(amount)
    if not amount then return "-" end
    return GetMoneyString(amount, true, nil, true)
end

local function CopperAllowed()
    return C_AuctionHouse.SupportsCopperValues() and true or false
end

local function Skin(kind, obj, ...)
    if not (S and S[kind] and obj) then return end
    pcall(S[kind], obj, ...)
end

local function ChooseLook()
    S = R.S
    if S then
        local ar, ag, ab = 1, 1, 1
        if S.GetAccentColor then
            local ok, r, g, b = pcall(S.GetAccentColor)
            if ok and r then ar, ag, ab = r, g, b end
        end
        C.title, C.text, C.dim, C.faint = { 1, 1, 1 }, { 1, 1, 1 }, { 0.78, 0.78, 0.78 }, { 0.55, 0.55, 0.55 }
        C.accent = { ar, ag, ab }
    else
        C.title, C.text, C.dim, C.faint, C.accent = K.gold, K.text, K.textDim, K.stone, K.gold
    end
end

local function Text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    Skin("Font", fs)
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3])
    return fs
end

local function Fill(parent, c, a, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- kind: "page" (the whole page), "band" (the strip along the top) or "well"
-- (a recessed box). Called on a fresh frame, before anything is drawn on it.
local function Surface(frame, kind, w, h)
    if S then
        if kind == "page" or kind == "band" then
            -- Opaque: EllesmereUI's panel colour can be translucent, and the
            -- page must hide Blizzard's view underneath.
            local r, g, b = 0.06, 0.06, 0.06
            if S.GetPanelColor then
                local ok, pr, pg, pb = pcall(S.GetPanelColor)
                if ok and pr then r, g, b = pr, pg, pb end
            end
            if kind == "band" then Skin("Panel", frame, { inset = true, noBorder = true }) end
            local base = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            base:SetColorTexture(r, g, b, 1)
            base:SetAllPoints()
        else
            Skin("Panel", frame, { inset = true })
        end
        return
    end
    if kind == "page" then
        Fill(frame, K.bg, 1):SetAllPoints()
    elseif kind == "band" then
        Fill(frame, K.band, 1):SetAllPoints()
        local rule = Fill(frame, K.bronzeLo, 1, "BORDER")
        rule:SetHeight(1)
        rule:SetPoint("BOTTOMLEFT")
        rule:SetPoint("BOTTOMRIGHT")
    else
        ST.Well(frame, w, h)
    end
end

local function Tip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        local body = type(text) == "function" and text() or text
        if not body then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Btn(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    Skin("Button", b)
    Skin("StateButtonLabel", b)
    return b
end

-- A recessed box with a scroll list inside (the pattern setup/Window.lua uses).
-- headerH leaves room for a column header above the list.
local function ListWell(parent, w, h, headerH)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(w, h)
    Surface(box, "well", w, h)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 4, -4 - (headerH or 0))
    scroll:SetPoint("BOTTOMRIGHT", -18, 4)
    local bar = CreateFrame("EventFrame", nil, box, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
    Skin("ScrollBar", bar)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(w - 24, 1)
    scroll:SetScrollChild(content)
    box.scroll, box.content, box.rows, box.rowW = scroll, content, {}, w - 24
    return box
end

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------
local function QualityColor(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return C.text[1], C.text[2], C.text[3]
end

-- Groups the bag items the auction house would take: one row per commodity,
-- one per exact item (equipment variants stay apart). Bound items and anything
-- the client says can't be listed are only counted.
local function ScanBags()
    local list, byKey, skipped, loading = {}, {}, 0, false
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if info.isBound or not (C_Item.DoesItemExist(loc) and C_AuctionHouse.IsSellItemValid(loc, false)) then
                    skipped = skipped + 1
                else
                    local status = C_AuctionHouse.GetItemCommodityStatus(loc)
                    local key, kind, itemKey
                    if status == Enum.ItemCommodityStatus.Commodity then
                        key, kind = "c" .. info.itemID, "commodity"
                    elseif status == Enum.ItemCommodityStatus.Item then
                        itemKey = C_AuctionHouse.GetItemKeyFromItem(loc)
                        key, kind = ("i%d:%d:%d:%d"):format(itemKey.itemID, itemKey.itemLevel or 0,
                            itemKey.itemSuffix or 0, itemKey.battlePetSpeciesID or 0), "item"
                    else
                        key, kind, loading = ("u%d:%d"):format(bag, slot), "loading", true
                    end
                    local g = byKey[key]
                    if not g then
                        g = { key = key, kind = kind, itemID = info.itemID, itemKey = itemKey, name = info.itemName,
                              icon = info.iconFileID, quality = info.quality, link = info.hyperlink,
                              bag = bag, slot = slot, count = 0 }
                        byKey[key] = g
                        list[#list + 1] = g
                    end
                    g.count = g.count + (info.stackCount or 1)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if (a.kind == "loading") ~= (b.kind == "loading") then return b.kind == "loading" end
        if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list, byKey, skipped, loading
end

local function Location(g)
    return g and ItemLocation:CreateFromBagAndSlot(g.bag, g.slot)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function Build()
    if page then return end
    ChooseLook()
    page = CreateFrame("Frame", nil, holder)
    page:SetPoint("TOPLEFT", AH, "TOPLEFT", 4, -60)
    page:SetPoint("BOTTOMRIGHT", AH, "BOTTOMRIGHT", -3, 27)
    page:SetFrameStrata(PAGE_STRATA)
    page:SetFrameLevel(PAGE_LEVEL)
    page:EnableMouse(true)
    page:Hide()
    Surface(page, "page")

    -- The search bar's row, beside the portrait: a title and one line of help.
    local top = CreateFrame("Frame", nil, page)
    top:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", 0, 0)   -- left edge: PlaceTop()
    page.top = top
    top:EnableMouse(true)
    Surface(top, "band")
    local title = Text(top, "GameFontNormal", C.title)
    title:SetPoint("LEFT", 12, 0)
    title:SetText("Sell from your bags")
    local hint = Text(top, "GameFontHighlightSmall", C.faint)
    hint:SetPoint("LEFT", title, "RIGHT", 14, 0)
    hint:SetText("Pick an item to see its current listings. Nothing is posted until you press Post.")

    -- Beside the money display: Blizzard's own action buttons sit there (e.g. Cancel Auction).
    local foot = CreateFrame("Frame", nil, page)
    foot:SetPoint("TOP", page, "BOTTOM", 0, 0)
    foot:SetPoint("LEFT", AH.MoneyFrameBorder or AH, AH.MoneyFrameBorder and "RIGHT" or "LEFT", 8, 0)
    foot:SetPoint("BOTTOMRIGHT", AH, "BOTTOMRIGHT", -3, 3)
    foot:EnableMouse(true)
    Surface(foot, "page")

    local W = AH:GetWidth() - 7
    local H = AH:GetHeight() - 87
    local RIGHT_X = LEFT_W + 16
    local RIGHT_W = W - RIGHT_X - 8

    -- Your items
    local itemsTitle = Text(page, "GameFontNormal", C.title)
    itemsTitle:SetPoint("TOPLEFT", 10, -6)
    itemsTitle:SetText("Your items")
    page.bags = ListWell(page, LEFT_W, H - 50)
    page.bags:SetPoint("TOPLEFT", 8, -24)
    page.bagsEmpty = Text(page.bags, "GameFontDisableSmall", C.faint)
    page.bagsEmpty:SetPoint("CENTER")
    page.bagsEmpty:SetWidth(LEFT_W - 40)
    page.bagsEmpty:SetJustifyH("CENTER")
    page.unlisted = Text(page, "GameFontHighlightSmall", C.faint)
    page.unlisted:SetPoint("TOPLEFT", page.bags, "BOTTOMLEFT", 2, -6)
    page.unlisted:SetWidth(LEFT_W - 4)
    page.unlisted:SetWordWrap(true)

    -- Current listings
    local listTitle = Text(page, "GameFontNormal", C.title)
    listTitle:SetPoint("TOPLEFT", RIGHT_X + 2, -6)
    listTitle:SetText("Current listings")
    page.searched = Text(page, "GameFontHighlightSmall", C.faint)
    page.searched:SetPoint("TOPRIGHT", -12, -8)
    page.searched:SetJustifyH("RIGHT")

    local MARKET_H = 214
    local market = CreateFrame("Frame", nil, page, "BackdropTemplate")
    market:SetPoint("TOPLEFT", RIGHT_X, -24)
    market:SetSize(RIGHT_W, MARKET_H)
    Surface(market, "well", RIGHT_W, MARKET_H)
    page.status = Text(market, "GameFontHighlight", C.text)
    page.status:SetPoint("TOPLEFT", 10, -8)
    page.status:SetWidth(RIGHT_W - 120)
    page.again = Btn(market, "Search again", 100, function() A.Search() end)
    page.again:SetPoint("TOPRIGHT", -8, -5)
    page.basis = Text(market, "GameFontHighlightSmall", C.dim)
    page.basis:SetPoint("TOPLEFT", 10, -34)   -- below the Search again button, so it can run the full width
    page.basis:SetWidth(RIGHT_W - 20)
    page.basis:SetWordWrap(true)
    page.listings = ListWell(market, RIGHT_W - 8, MARKET_H - 80, HEADER_H)
    page.listings:SetPoint("BOTTOMLEFT", 4, 4)
    local head = CreateFrame("Frame", nil, page.listings)
    head:SetPoint("TOPLEFT", 4, -3)
    head:SetSize(page.listings.rowW, HEADER_H)
    for _, k in ipairs({ "price", "qty", "item", "level", "note" }) do
        head[k] = Text(head, "GameFontHighlightSmall", C.faint)
    end
    local headRule = Fill(head, C.faint, 0.25, "BORDER")
    headRule:SetHeight(1)
    headRule:SetPoint("BOTTOMLEFT")
    headRule:SetPoint("BOTTOMRIGHT")
    page.listHead = head

    -- Post
    local postTitle = Text(page, "GameFontNormal", C.title)
    postTitle:SetPoint("TOPLEFT", market, "BOTTOMLEFT", 2, -10)
    postTitle:SetText("Post")
    local boxH = H - MARKET_H - 24 - 28 - 8
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetPoint("TOPLEFT", market, "BOTTOMLEFT", 0, -28)
    box:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 8)
    Surface(box, "well", RIGHT_W, boxH)
    page.post = box

    page.icon = box:CreateTexture(nil, "ARTWORK")
    page.icon:SetSize(30, 30)
    page.icon:SetPoint("TOPLEFT", 10, -10)
    page.name = Text(box, "GameFontNormal")
    page.name:SetPoint("TOPLEFT", page.icon, "TOPRIGHT", 8, -1)
    page.name:SetWidth(RIGHT_W - 60)
    page.name:SetWordWrap(false)
    page.have = Text(box, "GameFontHighlightSmall", C.faint)
    page.have:SetPoint("TOPLEFT", page.name, "BOTTOMLEFT", 0, -3)

    page.suggest = Text(box, "GameFontHighlightSmall", C.dim)
    page.suggest:SetPoint("TOPLEFT", page.icon, "BOTTOMLEFT", 0, -10)
    page.suggest:SetWidth(RIGHT_W - 110)
    page.suggest:SetWordWrap(true)
    page.use = Btn(box, "Use this", 80, function() A.UseSuggestion() end)
    page.use:SetPoint("TOPRIGHT", -10, -48)

    local y = -92
    local qLabel = Text(box, "GameFontHighlightSmall", C.dim)
    qLabel:SetPoint("TOPLEFT", 12, y)
    qLabel:SetText("Quantity")
    page.qty = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    page.qty:SetSize(54, 20)
    page.qty:SetPoint("LEFT", qLabel, "LEFT", 70, 0)
    page.qty:SetAutoFocus(false)
    page.qty:SetNumeric(true)
    page.qty:SetMaxLetters(5)
    page.qty:SetScript("OnTextChanged", function() A.UpdatePost() end)
    page.qty:SetScript("OnEnterPressed", EditBox_ClearFocus)
    page.qty:SetScript("OnEscapePressed", EditBox_ClearFocus)
    Skin("EditBox", page.qty)
    if S then page.qty:SetTextInsets(6, 6, 0, 0) end
    page.max = Btn(box, "Max", 46, function()
        local n = A.MaxQuantity()
        if n then page.qty:SetNumber(n) end
    end)
    page.max:SetPoint("LEFT", page.qty, "RIGHT", 6, 0)

    local dLabel = Text(box, "GameFontHighlightSmall", C.dim)
    dLabel:SetPoint("LEFT", page.max, "RIGHT", 24, 0)
    dLabel:SetText("Duration")
    page.duration = CreateFrame("DropdownButton", nil, box, "WowStyle1DropdownTemplate")
    page.duration:SetWidth(120)
    page.duration:SetPoint("LEFT", dLabel, "RIGHT", 10, 0)
    page.duration:SetupMenu(function(_, root)
        for i, label in ipairs({ AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE }) do
            root:CreateRadio(label, function() return duration == i end, function()
                duration = i
                A.UpdatePost()
            end)
        end
    end)
    Skin("Dropdown", page.duration)

    y = y - 32
    local pLabel = Text(box, "GameFontHighlightSmall", C.dim)
    pLabel:SetPoint("TOPLEFT", 12, y)
    pLabel:SetText("Price each")
    page.price = CreateFrame("Frame", nil, box, "LargeMoneyInputFrameTemplate")
    page.price:SetSize(176, 33)
    page.price:SetPoint("LEFT", pLabel, "LEFT", 68, -1)
    if not CopperAllowed() then   -- as the template does with useAuctionHouseCopperValue
        page.price.CopperBox:Hide()
        page.price.SilverBox:ClearAllPoints()
        page.price.SilverBox:SetPoint("RIGHT", page.price.CopperBox, "RIGHT")
        page.price.GoldBox.nextEditBox = page.price.SilverBox
        page.price.SilverBox.previousEditBox = page.price.GoldBox
        page.price.SilverBox.nextEditBox = page.price.GoldBox
    end
    if S then
        for _, k in ipairs({ "GoldBox", "SilverBox", "CopperBox" }) do
            local eb = page.price[k]
            Skin("EditBox", eb)
            if eb.Icon then eb.Icon:SetAlpha(1) end   -- the skin fades every texture; keep the coin
            eb:SetTextInsets(6, 24, 0, 0)
            eb:SetJustifyH("RIGHT")
        end
    end
    page.price:SetOnValueChangedCallback(function()
        -- The boxes may report a change after we have filled them, so compare
        -- with what we put in rather than relying on when the call arrives.
        if not settingPrice and page.price:GetAmount() ~= filledPrice then priceEdited = true end
        A.UpdatePost()
    end)

    local function Line(label, dy)
        local l = Text(box, "GameFontHighlightSmall", C.dim)
        l:SetPoint("LEFT", page.price, "RIGHT", 24, dy)
        l:SetText(label)
        local v = Text(box, "GameFontHighlightSmall", C.text)
        v:SetPoint("RIGHT", page.price, "RIGHT", 24 + 150, dy)
        v:SetJustifyH("RIGHT")
        return v
    end
    page.deposit = Line("Deposit", 8)
    page.total = Line("Total", -8)

    page.postButton = Btn(box, "Post", 120, function() A.Post() end)
    page.postButton:SetPoint("BOTTOMRIGHT", -10, 10)
    page.postButton:SetMotionScriptsWhileDisabled(true)
    Tip(page.postButton, "Post", function() return page.postButton.reason end)
    page.postStatus = Text(box, "GameFontHighlightSmall", C.dim)
    page.postStatus:SetPoint("BOTTOMLEFT", 12, 14)
    page.postStatus:SetPoint("RIGHT", page.postButton, "LEFT", -10, 0)
    page.postStatus:SetWordWrap(true)

    page:SetScript("OnShow", function() A.OnPageShown() end)
    page:SetScript("OnHide", function() A.OnPageHidden() end)
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
local function BagRow(i)
    local box = page.bags
    local r = box.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box.content)
    r:SetSize(box.rowW, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local hl = Fill(r, C.text, 0.05, "HIGHLIGHT")
    hl:SetAllPoints()
    r.sel = Fill(r, C.accent, 0.12)
    r.sel:SetAllPoints()
    r.bar = Fill(r, C.accent, 0.9, "ARTWORK")
    r.bar:SetSize(2, ROW_H - 6)
    r.bar:SetPoint("LEFT", 0, 0)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 6, 0)
    r.label = Text(r, "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.label:SetWidth(box.rowW - 90)
    r.label:SetWordWrap(false)
    r.right = Text(r, "GameFontHighlightSmall", C.faint)
    r.right:SetPoint("RIGHT", -6, 0)
    r.right:SetJustifyH("RIGHT")
    r:SetScript("OnClick", function(self) A.Select(self.group) end)
    r:SetScript("OnEnter", function(self)
        if not (self.group and self.group.link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.group.link)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    box.rows[i] = r
    return r
end

local function RefreshBags()
    for i, g in ipairs(groups) do
        local r = BagRow(i)
        r.group = g
        r.icon:SetTexture(g.icon)
        r.label:SetText(g.name or "")
        local isSel = selected and selected.key == g.key
        r.sel:SetShown(isSel)
        r.bar:SetShown(isSel)
        if g.kind == "loading" then
            r.label:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
            r.right:SetText("Details loading")
            r.icon:SetDesaturated(true)
            r:Disable()
        else
            r.label:SetTextColor(QualityColor(g.quality))
            r.right:SetText(g.count > 1 and ("x" .. g.count) or "")
            r.icon:SetDesaturated(false)
            r:Enable()
        end
        r:Show()
    end
    local box = page.bags
    for i = #groups + 1, #box.rows do box.rows[i]:Hide() end
    box.content:SetHeight(math.max(1, #groups * ROW_H))
    page.bagsEmpty:SetText(#groups == 0 and "Nothing in your bags can be listed here." or "")
    if unlisted > 0 then
        page.unlisted:SetText(("%d %s in your bags can't be listed here (bound, quest items and the like)."):format(
            unlisted, unlisted == 1 and "item" or "items"))
    else
        page.unlisted:SetText("")
    end
end

local STATUS_NOTE = { own = "yours", variant = "other version", bid = "bid only" }

-- Columns, left to right. Commodities: price each, how many, note. Items: price
-- each, how many, which item (its name carries the suffix), item level, note.
-- { point, x, width } per column; nil hides it.
local COLUMNS = {
    commodity = { price = { "RIGHT", 120 }, qty = { "RIGHT", 190 }, note = { "LEFT", 208, 120 } },
    item = { price = { "RIGHT", 110 }, qty = { "RIGHT", 140 }, item = { "LEFT", 156, 150 },
             level = { "RIGHT", 340 }, note = { "LEFT", 352, 80 } },
}
local HEADINGS = {
    commodity = { price = "Price each", qty = "Available", note = "" },
    item = { price = "Price each", qty = "Qty", item = "Item", level = "Level", note = "" },
}

local function PlaceColumns(row, kind)
    for _, k in ipairs({ "price", "qty", "item", "level", "note" }) do
        local fs, col = row[k], COLUMNS[kind][k]
        fs:ClearAllPoints()
        if col then
            fs:SetPoint(col[1], row, "LEFT", col[2], 0)
            fs:SetJustifyH(col[1])
            if col[3] then fs:SetWidth(col[3]); fs:SetWordWrap(false) end
            fs:Show()
        else
            fs:Hide()
        end
    end
end

local function ListingRow(i)
    local box = page.listings
    local r = box.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, box.content)
    r:SetSize(box.rowW, LIST_ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_H)
    r.mark = Fill(r, C.accent, 0.9, "ARTWORK")
    r.mark:SetSize(4, 4)
    r.mark:SetPoint("LEFT", 4, 0)
    for _, k in ipairs({ "price", "qty", "item", "level", "note" }) do
        r[k] = Text(r, "GameFontHighlightSmall", (k == "price" or k == "item") and C.text or C.dim)
    end
    r.note:SetTextColor(C.faint[1], C.faint[2], C.faint[3])
    r:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    box.rows[i] = r
    return r
end

local function RefreshListings()
    local list = SC.listings or {}
    local summary = SC.summary
    local kind = summary and summary.kind or (selected and selected.kind == "item" and "item") or "commodity"
    local head = page.listHead
    PlaceColumns(head, kind)
    for k, text in pairs(HEADINGS[kind]) do head[k]:SetText(text) end
    head:SetShown(#list > 0)

    local shown = math.min(#list, MAX_LISTING_ROWS)
    for i = 1, shown do
        local l, r = list[i], ListingRow(i)
        PlaceColumns(r, kind)
        local match = l.status == "match"
        local price = l.unitPrice or l.buyout
        r.price:SetText(price and Money(price) or ("bid " .. Money(l.minBid)))
        r.qty:SetText(l.quantity or "")
        r.link = l.link
        r.item:SetText(l.link and l.link:gsub("%[(.-)%]", "%1") or "")
        r.level:SetText(l.itemLevel and l.itemLevel > 0 and l.itemLevel or "")
        r.note:SetText(STATUS_NOTE[l.status] or "")
        r:SetAlpha(match and 1 or 0.55)
        r.mark:SetShown(match and summary and price == summary.lowest or false)
        r:Show()
    end
    local box = page.listings
    for i = shown + 1, #box.rows do box.rows[i]:Hide() end
    box.content:SetHeight(math.max(1, shown * LIST_ROW_H))
end

---------------------------------------------------------------------------
-- Market text
---------------------------------------------------------------------------
local STATE_TEXT = {
    idle = "Pick an item on the left to see its current listings.",
    waiting = "Waiting for the auction house to take a search...",
    searching = "Searching current listings...",
    more = "Loading more listings...",
    none = "No one has this listed right now.",
    noResponse = "The auction house didn't answer. Try again in a moment.",
    dropped = "The auction house didn't take that search (too many at once). Try again in a moment.",
}

local function Plural(n, one, many) return n == 1 and one or many end

-- What the suggestion is based on, and what was left out of it.
local function BasisText(s)
    if not s then return "" end
    local parts = {}
    if s.lowest then
        parts[#parts + 1] = ("Lowest comparable: %s each, %d available at that price. %d comparable %s found."):format(
            Money(s.lowest), s.lowestQuantity or 0, s.comparable, Plural(s.comparable, "listing", "listings"))
    else
        parts[#parts + 1] = "No comparable listings with a buyout."
    end
    local left = {}
    if s.own > 0 then left[#left + 1] = ("%d yours"):format(s.own) end
    if (s.otherVariant or 0) > 0 then left[#left + 1] = ("%d of other versions (item level or suffix)"):format(s.otherVariant) end
    if (s.bidOnly or 0) > 0 then left[#left + 1] = ("%d bid only"):format(s.bidOnly) end
    if #left > 0 then parts[#parts + 1] = "Not used: " .. table.concat(left, ", ") .. "." end
    return table.concat(parts, " ")
end

local function RefreshMarket()
    local state = SC.state
    local s = SC.summary
    local text = STATE_TEXT[state]
    if state == "done" or state == "partial" then
        text = state == "partial" and ("Showing the first %d listings (cheapest first); there may be more."):format(#SC.listings)
            or ("%d %s found."):format(#SC.listings, Plural(#SC.listings, "listing", "listings"))
    end
    if not selected then
        text = STATE_TEXT.idle
    elseif state == "idle" then
        text = "Not searched yet. Press Search again to see current listings."
    end
    page.status:SetText(text or "")
    page.basis:SetText((state == "done" or state == "partial" or state == "more") and BasisText(s) or "")
    if SC.scannedAt then
        page.searched:SetText(("Searched at %s%s"):format(date("%H:%M", SC.scannedAt),
            SC.stale and " - out of date, search again" or ""))
    else
        page.searched:SetText("")
    end
    page.again:SetShown(selected ~= nil and not SC.Busy())
    page.listings:SetAlpha(SC.stale and 0.6 or 1)
    RefreshListings()
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------
function A.MaxQuantity()
    local loc = Location(selected)
    if not (loc and C_Item.DoesItemExist(loc)) then return nil end
    return C_AuctionHouse.GetAvailablePostCount(loc)
end

local function Deposit(loc, qty)
    if not (loc and qty and qty > 0 and duration) then return nil end
    local d
    if selected.kind == "commodity" then
        d = C_AuctionHouse.CalculateCommodityDeposit(selected.itemID, duration, qty)
    else
        d = C_AuctionHouse.CalculateItemDeposit(loc, duration, qty)
    end
    if d and not CopperAllowed() then d = math.ceil(d / 100) * 100 end
    return d
end

-- Everything Post needs, checked. Returns the posting, or nil and a reason.
local function Prepare()
    if not selected or selected.kind == "loading" then return nil, "Pick an item first." end
    if post.state ~= "idle" then return nil, "Waiting for the last posting to finish." end
    if InCombatLockdown() then return nil, "Not while in combat." end
    local loc = Location(selected)
    if not (loc and C_Item.DoesItemExist(loc) and C_Item.GetItemID(loc) == selected.itemID) then
        return nil, "That item has moved; it will reappear in the list."
    end
    local qty = page.qty:GetNumber()
    local price = page.price:GetAmount()
    local deposit = Deposit(loc, qty)
    local reason = P.Check({ price = price, quantity = qty, maxQuantity = A.MaxQuantity(),
        copperAllowed = CopperAllowed(), deposit = deposit, money = GetMoney() })
    if reason then return nil, reason end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return nil, "The auction house is busy; a moment." end
    return { kind = selected.kind, loc = loc, duration = duration, quantity = qty, price = price,
             name = selected.name, deposit = deposit }
end

function A.UpdatePost()
    if not page then return end
    local g = selected
    local ready = g and g.kind ~= "loading"
    page.icon:SetTexture(g and g.icon or nil)
    page.name:SetText(g and g.name or "No item chosen")
    if g then page.name:SetTextColor(QualityColor(g.quality)) else page.name:SetTextColor(C.faint[1], C.faint[2], C.faint[3]) end
    page.have:SetText(ready and ("%d in your bags"):format(g.count) or "")
    for _, w in ipairs({ page.qty, page.max, page.price, page.duration }) do
        w:SetEnabled(ready and true or false)
    end

    local suggestion = ready and P.Suggest(SC.summary, CopperAllowed())
    if suggestion then
        local t = ("Suggested: %s each, to match the lowest comparable listing."):format(Money(suggestion.price))
        if suggestion.limited then t = t .. " Few listings to go on." end
        if suggestion.rounded then t = t .. " Rounded up to whole silver." end
        if SC.stale then t = t .. " Based on an older search." end
        page.suggest:SetText(t)
    elseif ready and (SC.state == "done" or SC.state == "none" or SC.state == "partial") then
        page.suggest:SetText("No suggestion: nothing comparable is listed with a buyout. Set your own price.")
    else
        page.suggest:SetText("")
    end
    page.use:SetShown(suggestion and page.price:GetAmount() ~= suggestion.price and true or false)

    local qty = page.qty:GetNumber()
    local price = page.price:GetAmount()
    local deposit = ready and Deposit(Location(g), qty)
    local show = ready and qty > 0
    page.deposit:SetText(show and Money(deposit) or "-")
    page.total:SetText(show and price > 0 and Money(price * qty) or "-")

    local p, reason = Prepare()
    page.postButton:SetEnabled(p ~= nil)
    page.postButton.reason = reason
    if post.state ~= "idle" then
        page.postStatus:SetText(message or "")
    else
        page.postStatus:SetText(message or (ready and reason) or "")
    end
end

local function FillPrice(amount)
    filledPrice = amount
    settingPrice = true
    if amount > 0 then page.price:SetAmount(amount) else page.price:Clear() end
    settingPrice = false
end

function A.UseSuggestion()
    local suggestion = P.Suggest(SC.summary, CopperAllowed())
    if not suggestion then return end
    FillPrice(suggestion.price)
    priceEdited = false
    A.UpdatePost()
end

local POST_EVENTS = {
    "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_MULTISELL_START", "AUCTION_MULTISELL_UPDATE",
    "AUCTION_MULTISELL_FAILURE", "AUCTION_HOUSE_SHOW_ERROR", "AUCTION_HOUSE_POST_ERROR",
}

local function PostEvents(on)
    for _, e in ipairs(POST_EVENTS) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
end

local postToken = 0
local function EndPost(text)
    post.state, post.pending, post.current = "idle", nil, nil
    postToken = postToken + 1
    PostEvents(false)
    message = text
    if page then A.UpdatePost() end
end

local function WatchPost()
    postToken = postToken + 1
    local mine = postToken
    C_Timer.After(POST_TIMEOUT, function()
        if mine == postToken and post.state == "posting" then
            EndPost("No reply from the auction house yet. Check the Auctions tab before posting again.")
        end
    end)
end

local function Sent()
    post.state = "posting"
    message = "Posting..."
    WatchPost()
    PostEvents(true)
    A.UpdatePost()
end

-- Explicit click on our Post button: exactly the values on screen.
function A.Post()
    local p = Prepare()
    if not p then A.UpdatePost() return end
    message = nil
    post.current = p
    Sent()   -- before the call: the game may answer while we are still in it
    local needsConfirmation
    if p.kind == "commodity" then
        needsConfirmation = C_AuctionHouse.PostCommodity(p.loc, p.duration, p.quantity, p.price)
    else
        needsConfirmation = C_AuctionHouse.PostItem(p.loc, p.duration, p.quantity, nil, p.price)
    end
    if needsConfirmation then
        -- The game shows its own confirmation (Blizzard's Auction House window
        -- handles that event). Its Accept is followed below and confirms this one.
        postToken = postToken + 1
        post.state, post.pending = "confirm", p
        message = "Confirm in the game's dialog to post, or cancel there."
        local mine = postToken
        C_Timer.After(0.5, function()
            if mine == postToken and post.state == "confirm"
                and not (StaticPopup_Visible and StaticPopup_Visible("AUCTION_HOUSE_POST_WARNING")) then
                EndPost("The game asked for a confirmation that didn't appear. Nothing was posted.")
            end
        end)
        A.UpdatePost()
    end
end

-- Followed after Blizzard's confirmation dialog runs its Accept (a click).
local function OnBlizzardConfirm()
    local p = post.pending
    if post.state ~= "confirm" or not p or not (page and page:IsShown()) then return end
    post.pending = nil
    if p.kind == "commodity" then
        C_AuctionHouse.ConfirmPostCommodity(p.loc, p.duration, p.quantity, p.price)
    else
        C_AuctionHouse.ConfirmPostItem(p.loc, p.duration, p.quantity, nil, p.price)
    end
    Sent()
end

-- The dialog closed; if it wasn't accepted, nothing was posted.
local function OnDialogClosed()
    if post.state == "confirm" then EndPost("Not posted.") end
end

local function Posted(p)
    local what = p and p.name or "item"
    local text = p and ("Posted %d x %s at %s each."):format(p.quantity, what, Money(p.price)) or "Posted."
    SC.MarkStale()
    EndPost(text)
    if page and page:IsShown() then RefreshMarket() end
end

---------------------------------------------------------------------------
-- Selection and searching
---------------------------------------------------------------------------
local function TargetFor(g)
    if g.kind == "commodity" then
        return { kind = "commodity", itemID = g.itemID, queryKey = C_AuctionHouse.MakeItemKey(g.itemID) }
    end
    local k = g.itemKey
    local info = C_AuctionHouse.GetItemKeyInfo(k)
    local isEquipment = info and info.isEquipment
    if isEquipment == nil then
        local classID = select(6, C_Item.GetItemInfoInstant(g.itemID))
        isEquipment = classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor
    end
    local queryKey = { itemID = k.itemID, itemLevel = k.itemLevel or 0, itemSuffix = k.itemSuffix or 0,
                       battlePetSpeciesID = k.battlePetSpeciesID or 0 }
    local level = k.itemLevel or 0
    if isEquipment then
        -- Searched without level or suffix (as the game asks), then compared exactly.
        queryKey.itemLevel, queryKey.itemSuffix = 0, 0
        if level == 0 then level = C_Item.GetCurrentItemLevel(Location(g)) or 0 end
    end
    return { kind = "item", itemID = g.itemID, queryKey = queryKey, isEquipment = isEquipment and true or false,
             matchVariant = isEquipment and true or false, itemLevel = level, itemSuffix = k.itemSuffix or 0 }
end

function A.Search()
    if not selected or selected.kind == "loading" then return end
    SC.Start(TargetFor(selected))
    RefreshMarket()
end

function A.Select(g)
    if not g or g.kind == "loading" then return end
    if post.state ~= "idle" then return end
    selected = g
    message = nil
    priceEdited = false
    FillPrice(0)
    local loc = Location(g)
    page.qty:SetNumber(g.kind == "commodity" and (C_Item.GetStackCount(loc) or 1) or 1)
    RefreshBags()
    A.Search()
    A.UpdatePost()
end

local function Deselect(text)
    selected = nil
    SC.Stop()
    message = text
    RefreshMarket()
    A.UpdatePost()
end

local function RescanBags()
    local list, byKey, skipped, loading = ScanBags()
    groups, unlisted = list, skipped
    if selected then
        local g = byKey[selected.key]
        if g then selected = g else Deselect("That item is no longer in your bags.") end
    end
    RefreshBags()
    A.UpdatePost()
    -- Item details still arriving: look once more shortly, not again and again.
    if loading and not retryScheduled then
        retryScheduled = true
        C_Timer.After(1, function()
            if page and page:IsShown() then RescanBags() end
        end)
    end
end

-- Search finished or changed: show it, and fill the price if the player hasn't.
SC.OnChange = function()
    if not (page and page:IsShown()) then return end
    RefreshMarket()
    if not priceEdited and not SC.Busy() then
        local suggestion = P.Suggest(SC.summary, CopperAllowed())
        if suggestion then FillPrice(suggestion.price) end
    end
    A.UpdatePost()
end

---------------------------------------------------------------------------
-- Events while the page is open
---------------------------------------------------------------------------
local PAGE_EVENTS = {
    "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT",
}

ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "BAG_UPDATE_DELAYED" then
        if post.state == "idle" then RescanBags() end
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
        -- Several of one item are posted one auction at a time; the multisell
        -- events below say when that run is finished.
        local p = post.current
        if post.state == "posting" and not (p and p.kind == "item" and p.quantity > 1) then Posted(p) end
    elseif event == "AUCTION_MULTISELL_START" then
        if post.state == "posting" then
            post.state = "multisell"
            postToken = postToken + 1
            message = ("Posting 0 of %d..."):format(a1 or 0)
            A.UpdatePost()
        end
    elseif event == "AUCTION_MULTISELL_UPDATE" then
        if post.state == "multisell" then
            if a1 and a2 and a1 >= a2 then Posted(post.current)
            else message = ("Posting %d of %d..."):format(a1 or 0, a2 or 0); A.UpdatePost() end
        end
    elseif event == "AUCTION_MULTISELL_FAILURE" then
        if post.state == "multisell" then EndPost("Posting stopped partway. Check the Auctions tab for what was listed.") end
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" or event == "AUCTION_HOUSE_POST_ERROR" then
        if post.state == "posting" or post.state == "multisell" then
            EndPost("The auction house didn't accept that posting.")
        end
    else
        A.UpdatePost()
    end
end)

function A.OnPageShown()
    for _, e in ipairs(PAGE_EVENTS) do ev:RegisterEvent(e) end
    retryScheduled = false
    if not duration then
        duration = tonumber(GetCVar("auctionHouseDurationDropdown")) or 2
        if duration < 1 or duration > 3 then duration = 2 end
    end
    page.duration:GenerateMenu()
    RescanBags()
    RefreshMarket()
end

function A.OnPageHidden()
    for _, e in ipairs(PAGE_EVENTS) do ev:UnregisterEvent(e) end
    if SC.Busy() then SC.Stop() end
    if post.state == "multisell" then C_AuctionHouse.CancelSell() end   -- as Blizzard's sell frame does
    if post.state == "confirm" then EndPost(nil) end
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
-- The band runs beside the window's portrait, or from the edge when a skin
-- has hidden it.
local function PlaceTop()
    local pc = AH.PortraitContainer
    local portrait = (pc and pc.portrait) or AH.portrait
    local shown = portrait and portrait:IsVisible() and portrait:GetAlpha() > 0.01
    page.top:ClearAllPoints()
    page.top:SetPoint("TOPLEFT", AH, "TOPLEFT", shown and 58 or 4, -24)
    page.top:SetPoint("BOTTOMRIGHT", page, "TOPRIGHT", 0, 0)
end

function A.Open()
    if not R:Enabled("auctionPosting") then return end
    Build()
    PlaceTop()
    for _, t in ipairs(AH.Tabs or {}) do
        PanelTemplates_DeselectTab(t)
        Skin("SetTabSelection", t, false)   -- EllesmereUI keeps this apart from Blizzard's tab state
    end
    PanelTemplates_SelectTab(tab)
    Skin("SetTabSelection", tab, true)
    page:Show()
end

-- Which Blizzard tab the window is on, read from its display mode the way
-- EllesmereUI's own Auction House skin reads it (any sell view is the Sell tab).
local function BlizzardTabSelected(t)
    local dm = AH.GetDisplayMode and AH:GetDisplayMode()
    if t.displayMode ~= nil and t.displayMode == dm then return true end
    if t == AH.SellTab then
        for _, k in ipairs({ "ItemSellFrame", "CommoditiesSellFrame", "WoWTokenSellFrame" }) do
            if AH[k] and AH[k]:IsShown() then return true end
        end
    end
    return false
end

-- Back to Blizzard's tabs: hide the page and redraw them from the window's
-- own selected tab (read only).
function A.Close()
    if not (page and page:IsShown()) then return end
    page:Hide()
    PanelTemplates_DeselectTab(tab)
    PanelTemplates_UpdateTabs(AH)
    if S then
        Skin("SetTabSelection", tab, false)
        for _, t in ipairs(AH.Tabs or {}) do Skin("SetTabSelection", t, BlizzardTabSelected(t)) end
    end
end

local function Reset()
    A.Close()
    SC.Stop()
    EndPost(nil)
    selected, groups, unlisted, message = nil, {}, 0, nil
    priceEdited = false
end

function A.Refresh()
    if not tab then return end
    local on = R:Enabled("auctionPosting")
    tab:SetShown(on)
    if not on then A.Close() end
end

local function Attach()
    if holder or not AuctionHouseFrame then return end
    AH = AuctionHouseFrame
    holder = CreateFrame("Frame", nil, AH)    -- our tab's Tabs array lives here, not on AH
    holder:SetAllPoints()
    tab = CreateFrame("Button", nil, holder, "AuctionHouseFrameTabTemplate")
    tab:SetText("Sell from Bags")
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        A.Open()
    end)
    PanelTemplates_DeselectTab(tab)
    Build()
    -- Blizzard's tab art overlaps its neighbour; EllesmereUI's flat tabs sit a
    -- pixel apart. Top and bottom follow the Auctions tab, so a trimmed height matches.
    local gap = S and 1 or -15
    tab:SetPoint("TOPLEFT", AH.AuctionsTab, "TOPRIGHT", gap, 0)
    tab:SetPoint("BOTTOMLEFT", AH.AuctionsTab, "BOTTOMRIGHT", gap, 0)
    Skin("Tab", tab)
    Skin("SetTabSelection", tab, false)
    hooksecurefunc(AH, "SetDisplayMode", A.Close)
    if AH.SetDialogOverlayShown then
        hooksecurefunc(AH, "SetDialogOverlayShown", function(_, shown)
            if not shown then OnDialogClosed() end
        end)
    end
    if AH.ItemSellFrame and AH.ItemSellFrame.ConfirmPost then
        hooksecurefunc(AH.ItemSellFrame, "ConfirmPost", OnBlizzardConfirm)
    end
    A.Refresh()
end

R:On("ADDON_LOADED", function(name)
    if name == "Blizzard_AuctionHouseUI" then Attach() end
end)
R:On("PLAYER_LOGIN", function()
    if C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then Attach() end
end)
R:On("AUCTION_HOUSE_CLOSED", Reset)
