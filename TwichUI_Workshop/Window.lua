-- TwichUI Workshop: the window
-- Three views. Crafting: recipes on the left (the player's own open profession, with a search), the queue on the right, and under it the
-- combined materials against the bags. Shopping: what the queue still needs, once per material, with where to get it (a vendor, the auction
-- house or making it) and what that may cost. Opportunities: what one craft of each known recipe costs, sells for and could earn from the
-- prices of the last auction house scan, and the Scan prices button. It draws what Session.lua says and asks it to do everything else. Drawn with the shared framed look
-- (FrameLook.lua). Opened with /tui workshop, the TwichUI menu or the settings page; it never opens by itself.
--
-- While the window is shown it listens for the profession window's changes (TRADE_SKILL_*), for bag changes and for item
-- names arriving; a burst of events becomes one redraw. Hidden, it listens to nothing, forgets the recipe lists it read and holds
-- no rows of work. The first thing shown after opening is read fresh, so readiness is never from before the window was closed.
-- Colour is always beside a word (Orange/Yellow/Green/Grey, "Still needed", "Unknown").

local R = TwichUI
local W = R.Workshop
local S, Q, O = W.Session, W.Queue, W.Observe
local PR, Op, SC = W.Prices, W.Opps, W.Scan
local Sh = W.Shopping
local Win = {}
W.Window = Win

local NAME = "TwichUIWorkshop"
local WIDTH, HEIGHT = 800, 620
local PAD = 16
local LEFT_W = 312
local RIGHT_X = PAD + LEFT_W + 16
local RIGHT_W = WIDTH - RIGHT_X - PAD
local SETTLE = 0.2
local REC_H, QUE_H, MAT_H, OPP_H, SHOP_H = 40, 58, 22, 46, 54
local COL_W = 124          -- the width of each money column in Opportunities
local ADD_W = 64

local L, K            -- Look and its palette, looked up when first built
local f               -- the window
local lists = {}      -- recipes, queue, materials, shopping, opportunities
local main, opps, shop  -- the three views
local mode = "craft"  -- "craft", "shop" or "opps"
local heads = {}      -- the sortable column headings
local oppChips = {}   -- the profession buttons of Opportunities
local fillToken = 0   -- changes whenever a pending batch of recipe reading should be forgotten
local chips = {}
local token = 0       -- changes whenever a pending redraw should be forgotten
local scheduled = false
local dirtyRead = false
local dirtyMerchant = false
local renders, flushes = 0, 0

local function Tip(frame, title, body) R.Interact.Tip(frame, title, body) end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function Num(n) return tostring(n) end

local EVENTS = {
    TRADE_SKILL_SHOW = "read", TRADE_SKILL_LIST_UPDATE = "read", TRADE_SKILL_DATA_SOURCE_CHANGED = "read",
    PLAYER_REGEN_ENABLED = "read",
    MERCHANT_SHOW = "merchant", MERCHANT_UPDATE = "merchant",
    BAG_UPDATE_DELAYED = "draw", GET_ITEM_INFO_RECEIVED = "draw",
    AUCTION_HOUSE_SHOW = "draw", AUCTION_HOUSE_CLOSED = "draw", AUCTION_HOUSE_DISABLED = "draw",
}

---------------------------------------------------------------------------
-- A scrolling list that makes only the rows it can show
---------------------------------------------------------------------------
local function NewList(parent, x, y, w, h, rowH, make)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(w, h)
    L.Well(box, 0.9)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -22, 4)
    L.ScrollBar(sf)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - 30, 1)
    sf:SetScrollChild(content)
    local list = { box = box, scroll = sf, content = content, rows = {}, data = {}, rowH = rowH }
    list.empty = L.Text(box, "small")
    list.empty:SetPoint("TOPLEFT", 12, -12)
    list.empty:SetWidth(w - 40)
    list.empty:SetWordWrap(true)
    function list:Layout()
        local data, rows = self.data, self.rows
        content:SetHeight(math.max(#data * rowH, 1))
        local first = math.floor((sf:GetVerticalScroll() or 0) / rowH)
        local count = math.ceil((h - 8) / rowH) + 1
        for i = 1, count do
            local idx = first + i
            local row = rows[i]
            if idx <= #data then
                if not row then
                    row = make(content)
                    row:SetHeight(rowH)
                    rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx - 1) * rowH)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(idx - 1) * rowH)
                row:Show()
                row.fill(row, data[idx], idx)
            elseif row then
                row:Hide()
            end
        end
        for i = count + 1, #rows do rows[i]:Hide() end
    end
    sf:HookScript("OnVerticalScroll", function() list:Layout() end)
    function list:SetData(d, emptyText)
        self.data = d
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#d == 0 and emptyText ~= nil)
        self:Layout()
    end
    function list:ScrollTop() sf:SetVerticalScroll(0) end
    function list:RowCount() local n = 0 for _, r in ipairs(self.rows) do if r:IsShown() then n = n + 1 end end return n end
    return list
end

local function Icon(row, size)
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return t
end

local ICON_BLANK = 134400   -- the game's question-mark icon, for a recipe or item whose icon isn't known yet

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function MakeRecipeRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row.icon = Icon(row, 30)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetWidth(LEFT_W - 30 - 4 - 8 - 80 - 24)
    row.name:SetWordWrap(false)
    row.diff = L.Text(row, "small")
    row.diff:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.sub = L.Text(row, "meta")
    row.sub:SetPoint("LEFT", row.diff, "RIGHT", 6, 0)
    row.add = F.Button(row, "Add", 62, "secondary", function()
        local rec = row.rec
        if rec then S.Add(rec); Win.Render() end
    end)
    row.add:SetHeight(22)
    row.add:SetPoint("RIGHT", -2, 0)
    Tip(row.add, "Add to queue", "Puts this recipe in the queue to make once. Change how many in the queue.")
    row.fill = function(self, rec)
        self.rec = rec
        O.Fill(rec)
        self.icon:SetTexture(rec.icon or ICON_BLANK)
        self.name:SetText(rec.name)
        local d = W.DIFFICULTY[rec.diff]
        if d then
            self.diff:SetText(d.word)
            Paint(self.diff, d.color)
        else
            self.diff:SetText("")
        end
        local per = W.PerCraft(rec.outMin, rec.outMax)
        self.sub:SetText(per and ("Makes " .. per) or "Makes: unknown")
        if S.IsQueued(rec.id) then
            self.add.text:SetText("Queued")
            self.add:SetEnabled(false)
        else
            self.add.text:SetText("Add")
            self.add:SetEnabled(true)
        end
    end
    return row
end

local function QueueLine(r)
    local e = r.entry
    local crafts = e.crafts == 1 and "1 craft" or (e.crafts .. " crafts")
    if not r.perCraft then return crafts .. " - what it makes isn't known yet" end
    if e.crafts == 1 then return crafts .. " - makes " .. r.perCraft end
    return crafts .. " - makes " .. r.perCraft .. " each, " .. r.expected .. " in all"
end

local function MakeQueueRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row.icon = Icon(row, 36)
    row.icon:SetPoint("TOPLEFT", 2, -6)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 46, -5)
    row.name:SetWidth(RIGHT_W - 30 - 46 - 74)
    row.name:SetWordWrap(false)
    row.line = L.Text(row, "small")
    row.line:SetPoint("TOPLEFT", 46, -23)
    row.line:SetWidth(RIGHT_W - 30 - 50)
    row.line:SetWordWrap(false)
    row.stale = L.Text(row, "small")
    row.stale:SetPoint("BOTTOMLEFT", 46, 5)
    row.stale:SetText("Open profession to update.")
    Paint(row.stale, K.gold)
    row.remove = F.Button(row, "Remove", 62, "secondary", function()
        if row.id then S.Remove(row.id); Win.Render() end
    end)
    row.remove:SetHeight(20)
    row.remove:SetPoint("TOPRIGHT", -2, -3)
    Tip(row.remove, "Remove", "Takes this recipe out of the queue. Nothing else changes.")
    row.more = F.Button(row, "+", 22, "secondary", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and 5 or 1); Win.Render() end
    end)
    row.more:SetHeight(20)
    row.more:SetPoint("BOTTOMRIGHT", -2, 3)
    Tip(row.more, "Make more", "One more craft. Hold Shift for five.")
    row.count = L.Text(row, "body")
    row.count:SetWidth(34)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("RIGHT", row.more, "LEFT", -2, 0)
    row.less = F.Button(row, "-", 22, "secondary", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and -5 or -1); Win.Render() end
    end)
    row.less:SetHeight(20)
    row.less:SetPoint("RIGHT", row.count, "LEFT", -2, 0)
    Tip(row.less, "Make fewer", "One craft fewer, down to one. Hold Shift for five. Remove takes the recipe out.")
    row.open = F.Button(row, "Open recipe", 86, "secondary", function()
        if row.id then S.OpenRecipe(row.id); Win.Render() end
    end)
    row.open:SetHeight(20)
    row.open:SetPoint("RIGHT", row.less, "LEFT", -8, 0)
    Tip(row.open, "Open recipe", "Shows this recipe in the game's profession window. It makes nothing.")
    row.fill = function(self, r)
        local e = r.entry
        self.id = e.id
        self.icon:SetTexture(e.icon or ICON_BLANK)
        local label = e.name
        if e.profName then label = label .. "  (" .. e.profName .. ")" end
        self.name:SetText(label)
        self.line:SetText(QueueLine(r))
        self.count:SetText(Num(e.crafts))
        self.stale:SetShown(r.unresolved)
        self.less:SetEnabled(e.crafts > 1)
        self.more:SetEnabled(e.crafts < W.MAX_CRAFTS)
    end
    return row
end

local function MakeMaterialRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.icon = Icon(row, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = L.Text(row, "body")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(RIGHT_W - 30 - 4 - 18 - 6 - 62 - 62 - 88)
    row.name:SetWordWrap(false)
    row.short = L.Text(row, "body")
    row.short:SetPoint("RIGHT", -6, 0)
    row.short:SetWidth(78)
    row.short:SetJustifyH("RIGHT")
    row.have = L.Text(row, "body")
    row.have:SetPoint("RIGHT", row.short, "LEFT", -10, 0)
    row.have:SetWidth(52)
    row.have:SetJustifyH("RIGHT")
    row.need = L.Text(row, "body")
    row.need:SetPoint("RIGHT", row.have, "LEFT", -10, 0)
    row.need:SetWidth(52)
    row.need:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        if GameTooltip and self.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then
                GameTooltip:Hide()
            elseif self.made then
                GameTooltip:AddLine(("%s%d will come from crafts in your queue, so they are not counted as still needed."):format(self.madeRange and "At least " or "", self.made), 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, m)
        self.item, self.made, self.madeRange = m.item, m.made, m.madeRange
        local name, icon = O.ItemFacts(m.item)
        self.icon:SetTexture(icon or ICON_BLANK)
        self.name:SetText(name or ("Item " .. m.item))
        self.need:SetText(Num(m.need))
        if m.have == nil then
            self.have:SetText("Unknown")
            self.short:SetText("Unknown")
            Paint(self.short, K.stone)
        else
            self.have:SetText(Num(m.have))
            self.short:SetText(Num(m.short))
            Paint(self.short, m.short > 0 and K.gold or K.sage)
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Shopping rows
---------------------------------------------------------------------------
local NEED_W, SOURCE_W, SPEND_W, ACT_W = 64, 110, 130, 90
local shopView   -- what the last draw of Shopping was built from (the row tooltips read it)

local function Money(copper)
    if type(copper) ~= "number" then return "" end
    local neg = copper < 0
    local n = neg and -copper or copper
    local text = type(GetMoneyString) == "function" and GetMoneyString(n, true, nil, true) or (tostring(n) .. "c")
    return neg and ("-" .. text) or text
end

local function ItemName(item)
    local name = O.ItemFacts(item)
    return name or ("Item " .. item)
end

-- "just now", "3 days ago"; "old" is added when the price is old
local function AgeWords(at, oldAfter)
    local age = PR.Age(at)
    if not age then return nil end
    local text = PR.AgeText(age)
    if age > (oldAfter or PR.OLD_AFTER) then text = text .. " (old)" end
    return text
end

local function ShowShopBasis(row)
    if not (GameTooltip and row.data and shopView) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local lines = Sh.Basis(row.data, ItemName, Money, PR.AgeText, shopView.ctx.now)
    for i, line in ipairs(lines) do
        if line[2] then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
        elseif i == 1 then
            GameTooltip:AddLine(line[1], 1, 0.82, 0)
        else
            GameTooltip:AddLine(line[1], 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

-- The words under a shopping row's name: what to make, and how the options compare
local function ShopDetail(r)
    local parts = {}
    if r.kind == "make" then
        local m = r.make
        parts[#parts + 1] = ("Make %d x %s: makes %d%s."):format(m.crafts, m.rec.name, m.made,
            m.surplus > 0 and (", " .. m.surplus .. " left over") or "")
    elseif r.surplus then
        parts[#parts + 1] = ("%d left over."):format(r.surplus)
    end
    local why = Sh.Explain(r)
    if r.source and not r.picked and not r.reagentOnly then why = "Suggested source. " .. why end
    parts[#parts + 1] = why
    if r.estimate then parts[#parts + 1] = "Unit-price estimate: more may cost more." end
    if r.made and r.made > 0 then parts[#parts + 1] = ("%s%d will come from queued crafts."):format(r.madeRange and "At least " or "", r.made) end
    return table.concat(parts, " ")
end

local function MakeShopRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(32, 32)
    row.iconBtn:SetPoint("TOPLEFT", 4, -8)
    row.icon = Icon(row.iconBtn, 32)
    row.icon:SetPoint("CENTER")
    row.iconBtn:SetScript("OnEnter", function(self)
        if GameTooltip and row.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, row.item) then GameTooltip:Hide() end
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.iconBtn:SetScript("OnClick", function()   -- Shift-click puts the item's link in the chat box you have open, to look it up
        if not (row.item and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink) then return end
        local ok, _, link = pcall(C_Item.GetItemInfo, row.item)
        if ok and type(link) == "string" then pcall(ChatEdit_InsertLink, link) end
    end)
    local nameW = (WIDTH - PAD * 2 - 30) - 44 - (NEED_W + SOURCE_W + SPEND_W + ACT_W + 4 * 8 + 2)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 44, -6)
    row.name:SetWidth(nameW)
    row.name:SetWordWrap(false)
    row.detail = L.Text(row, "meta")
    row.detail:SetPoint("TOPLEFT", 44, -26)
    row.detail:SetWidth(nameW + NEED_W + SOURCE_W + 16)
    row.detail:SetHeight(26)
    row.detail:SetWordWrap(true)
    row.detail:SetJustifyV("TOP")
    row.act = F.Button(row, "Show vendor", ACT_W, "secondary", function()
        local d = row.data
        if not d then return end
        if d.kind == "make" then S.AddSubcraft(d.item) else S.ShowVendor(d.item) end
        Win.Render()
    end)
    row.act:SetHeight(22)
    row.act:SetPoint("TOPRIGHT", -2, -6)
    Tip(row.act, "Show vendor / Add to queue", "Show vendor: shows a vendor seen to sell this on the world map. It sets no waypoint and starts no route. Add to queue: queues the crafts that make this, so the queue makes it. Nothing is bought or crafted.")
    row.spend = {}
    row.spend.a = L.Text(row, "body")
    row.spend.a:SetWidth(SPEND_W)
    row.spend.a:SetJustifyH("RIGHT")
    row.spend.a:SetWordWrap(false)
    row.spend.a:SetPoint("TOPRIGHT", row.act, "TOPLEFT", -8, -3)
    row.spend.b = L.Text(row, "meta")
    row.spend.b:SetWidth(SPEND_W)
    row.spend.b:SetJustifyH("RIGHT")
    row.spend.b:SetWordWrap(false)
    row.spend.b:SetPoint("TOPRIGHT", row.spend.a, "BOTTOMRIGHT", 0, -4)
    row.source = F.Button(row, "", SOURCE_W, "secondary", function()
        if row.item then S.CycleSource(row.item); Win.Render() end
    end)
    row.source:SetHeight(22)
    row.source:SetPoint("TOPRIGHT", row.spend.a, "TOPLEFT", -8, 3)
    Tip(row.source, "Source", "Where this comes from. Click to change it: the suggestion, then each way that is possible (vendor, auction house, make). Nothing is bought or made for you.")
    row.need = L.Text(row, "body")
    row.need:SetWidth(NEED_W)
    row.need:SetJustifyH("RIGHT")
    row.need:SetPoint("TOPRIGHT", row.source, "TOPLEFT", -8, -3)
    row:SetScript("OnEnter", ShowShopBasis)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, r)
        self.data, self.item = r, r.item
        local name, icon = O.ItemFacts(r.item)
        self.icon:SetTexture(icon or ICON_BLANK)
        self.name:SetText(name or ("Item " .. r.item))
        self.detail:SetText(ShopDetail(r))
        self.need:SetText(Num(r.qty))
        Paint(self.need, K.gold)
        local choices = Sh.Choices(r)
        self.source.text:SetText(r.source and Sh.NAMES[r.source] or "No source")
        self.source:SetEnabled(#choices > 0)
        -- spending
        local a, b = self.spend.a, self.spend.b
        local tag = {}
        if r.kind == "make" then
            local mk = r.make
            a:SetText(mk.cash and Money(mk.cash) or "Unknown")
            Paint(a, mk.cash and K.textDim or K.stone)
            b:SetText("materials, counted in their rows")
        elseif r.cash then
            a:SetText((r.estimate and "about " or "") .. Money(r.cash))
            Paint(a, K.text)
            if r.estimate then tag[#tag + 1] = "estimate" end
            local age = AgeWords(r.at, r.source == "vendor" and W.Vendor.OLD_AFTER or nil)
            if age then tag[#tag + 1] = age end
            b:SetText(table.concat(tag, ", "))
        else
            a:SetText("Unknown")
            Paint(a, K.stone)
            b:SetText("")
        end
        -- the one action that fits the row
        local d = shopView and shopView.ctx
        if r.kind == "make" then
            self.act.text:SetText("Add to queue")
            self.act:Show()
        elseif r.source == "vendor" and d and d.sellers[r.item] then
            self.act.text:SetText("Show vendor")
            self.act:Show()
        else
            self.act:Hide()
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Opportunities rows
---------------------------------------------------------------------------
local oppView         -- what the last draw of Opportunities was built from (the basis tooltips read it)

-- One money column of a row: a value, and under it "to <highest>" when the amount is a range (an uncertain output)
local function MakeCell(row, right)
    local c = {}
    c.a = L.Text(row, "body")
    c.a:SetWidth(COL_W)
    c.a:SetJustifyH("RIGHT")
    c.a:SetWordWrap(false)
    c.b = L.Text(row, "meta")
    c.b:SetWidth(COL_W)
    c.b:SetJustifyH("RIGHT")
    c.b:SetWordWrap(false)
    function c.Set(low, high, color)
        c.a:ClearAllPoints()
        c.b:ClearAllPoints()
        if high then
            c.a:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -7)
            c.b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -25)
            c.b:SetText("to " .. high)
            c.b:Show()
        else
            c.a:SetPoint("RIGHT", row, "RIGHT", right, 0)
            c.b:SetText("")
            c.b:Hide()
        end
        c.a:SetText(low)
        Paint(c.a, color or K.text)
    end
    return c
end

local function Known(cell, low, high)   -- a known amount, or "Unknown" in the dim colour
    if low == nil then cell.Set("Unknown", nil, K.stone)
    else cell.Set(Money(low), high ~= nil and high ~= low and Money(high) or nil) end
end

local function ShowBasis(row)
    if not (GameTooltip and row.data and oppView) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local src = oppView.source.market and { label = oppView.source.label, at = oppView.source.market.at, complete = oppView.source.market.complete } or nil
    local lines = Op.Basis(row.data, src, ItemName, Money)
    for i, line in ipairs(lines) do
        if line[2] then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
        elseif i == 1 then
            GameTooltip:AddLine(line[1], 1, 0.82, 0)
        else
            GameTooltip:AddLine(line[1], 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

local function MakeOppRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    local nameW = (WIDTH - PAD * 2 - 30) - 4 - 32 - 8 - ADD_W - 12 - 3 * (COL_W + 6)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(32, 32)
    row.iconBtn:SetPoint("LEFT", 4, 0)
    row.icon = Icon(row.iconBtn, 32)
    row.icon:SetPoint("CENTER")
    row.iconBtn:SetScript("OnEnter", function(self)
        if GameTooltip and row.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, row.item) then GameTooltip:Hide() end
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.iconBtn:SetScript("OnClick", function()   -- Shift-click puts the item's link in the chat box you have open, like other item icons
        if not (row.item and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink) then return end
        local ok, _, link = pcall(C_Item.GetItemInfo, row.item)
        if ok and type(link) == "string" then pcall(ChatEdit_InsertLink, link) end
    end)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", row.iconBtn, "TOPRIGHT", 8, 0)
    row.name:SetWidth(nameW)
    row.name:SetWordWrap(false)
    row.sub = L.Text(row, "meta")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetWidth(nameW)
    row.sub:SetWordWrap(false)
    row.add = F.Button(row, "Add", ADD_W, "secondary", function()
        if row.rec then S.Add(row.rec); Win.Render() end
    end)
    row.add:SetHeight(22)
    row.add:SetPoint("RIGHT", -2, 0)
    Tip(row.add, "Add to queue", "Puts this recipe in the queue to make once, in the Crafting view.")
    row.profit = MakeCell(row, -(ADD_W + 12))
    row.sell = MakeCell(row, -(ADD_W + 12 + COL_W + 6))
    row.cost = MakeCell(row, -(ADD_W + 12 + 2 * (COL_W + 6)))
    row:SetScript("OnEnter", ShowBasis)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, r)
        local e, rec = r.est, r.rec
        self.data, self.rec, self.item = r, rec, rec.outItem
        local _, icon
        if rec.outItem then _, icon = O.ItemFacts(rec.outItem) end
        self.icon:SetTexture(icon or rec.icon or ICON_BLANK)
        self.name:SetText(rec.name)
        local makes = W.PerCraft(e.outMin, e.outMax)
        local detail = makes and ("Makes " .. makes) or "Makes: unknown"
        if rec.profName then detail = detail .. "  -  " .. rec.profName end
        if e.state ~= "ok" then detail = (Op.WhyText(e) or "Not priced") end
        self.sub:SetText(detail)
        Paint(self.sub, e.state == "ok" and K.stone or K.gold)
        Known(self.cost, e.cost)
        Known(self.sell, e.sellLow, e.sellHigh)
        if e.state == "ok" then
            local tone = e.profitLow > 0 and K.sage or (e.profitHigh < 0 and K.ember or K.text)
            self.profit.Set(Money(e.profitLow), e.profitHigh ~= e.profitLow and Money(e.profitHigh) or nil, tone)
        else
            self.profit.Set("Unknown", nil, K.stone)
        end
        if S.IsQueued(rec.id) then
            self.add.text:SetText("Queued")
            self.add:SetEnabled(false)
        else
            self.add.text:SetText("Add")
            self.add:SetEnabled(true)
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function LayoutChips(list)
    local n = #list
    for i = 1, math.max(n, #chips) do
        local b = chips[i]
        local p = list[i]
        if p then
            if not b then
                b = R.FrameLook.Toggle(main, "", 80, function(self)
                    if self.profId then S.Select(self.profId); lists.recipes:ScrollTop(); Win.Render() end
                end)
                b:SetHeight(22)
                chips[i] = b
            end
            local w = math.max(56, math.min(110, math.floor((LEFT_W - 4 * (n - 1)) / n)))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + (i - 1) * (w + 4), -72)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(p.selected)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function RenderCraft()
    -- recipes
    LayoutChips(S.Professions())
    local notices = S.Notices()
    f.notice:SetText(table.concat(notices, "\n"))
    local rows = S.Browse()
    local emptyText
    if #rows == 0 then
        if not S.Current() then emptyText = "No recipes yet."
        elseif S.filter ~= "" then emptyText = "No recipe matches your search."
        else emptyText = "This profession has no recipes to show." end
    end
    lists.recipes:SetData(rows, emptyText)

    -- queue
    local queue = S.QueueRows()
    f.queueCount:SetText(("%d of %d"):format(#queue, W.MAX_QUEUE))
    lists.queue:SetData(queue, "Nothing queued yet. Use Add on a recipe.")

    -- materials
    local mats, sum = S.Materials()
    lists.mats:SetData(mats, sum.state == "empty" and "Materials for the queue appear here." or nil)
    local text, tone = S.Headline(sum)
    f.headline:SetText(text)
    Paint(f.headline, tone == "good" and K.sage or (tone == "warn" and K.gold or K.textDim))
end

local function Plural(n, one, many) return n == 1 and one or many end

local function RenderShop()
    local plan, ctx = S.Shopping()
    shopView = { plan = plan, ctx = ctx }
    local sum, src, tot = ctx.summary, ctx.source, plan.totals

    -- where the prices come from
    local sourceText
    if src.market then
        local age = PR.Age(src.market.at)
        sourceText = ("Auction prices from %s, scanned %s."):format(src.label, PR.AgeText(age))
        if age and age > PR.OLD_AFTER then sourceText = sourceText .. " These prices are old." end
        if not src.market.complete then sourceText = sourceText .. " That scan wasn't complete." end
    else
        sourceText = "No saved auction prices yet. Open the Opportunities view at an auction house and choose Scan prices."
    end
    shop.source:SetText(sourceText)
    shop.status:SetText(("Vendor prices are what a vendor charged when you last had its window open (%d noted). Counts what is in your bags only."):format(W.Vendor.Count()))

    local empty
    if sum.state == "empty" then empty = "Add recipes to the queue to build a shopping list."
    elseif #plan.rows == 0 then
        if sum.state == "ready" then empty = "Nothing to buy: the materials are in your bags, or made by your queue."
        else empty = (S.Headline(sum)) end
    end
    lists.shop:SetData(plan.rows, empty)

    -- the total: only what is priced, and never as if it were complete when it is not
    if #plan.rows == 0 then
        shop.total:SetText("")
    elseif tot.missing > 0 then
        shop.total:SetText(("Estimated spending: %s so far. Some prices missing: %d %s."):format(Money(tot.cash), tot.missing,
            Plural(tot.missing, "material has no price", "materials have no price")))
        Paint(shop.total, K.gold)
    else
        shop.total:SetText("Estimated spending: " .. Money(tot.cash) .. (tot.estimate and " (includes estimates)" or ""))
        Paint(shop.total, K.text)
    end
    local notes = {}
    if plan.unknownBags > 0 then
        notes[#notes + 1] = ("%d %s a bag count that couldn't be read, so %s left out."):format(plan.unknownBags,
            Plural(plan.unknownBags, "material has", "materials have"), Plural(plan.unknownBags, "it is", "they are"))
    end
    if sum.unknown > 0 then
        notes[#notes + 1] = ("%d %s can't be counted yet. Open %s to update."):format(sum.unknown, Plural(sum.unknown, "recipe", "recipes"),
            Plural(sum.unknown, "its profession", "their professions"))
    end
    if sum.cycle and sum.cycle > 0 then
        notes[#notes + 1] = ("%d queued %s depend on each other, so what they make isn't counted."):format(sum.cycle, Plural(sum.cycle, "recipe", "recipes"))
    end
    if #plan.rows > 0 then
        notes[#notes + 1] = "A suggested source compares the prices known, one material at a time; it isn't the cheapest possible plan. Owned materials lower what you spend but are not free. Nothing is bought or made for you."
    end
    shop.notes:SetText(table.concat(notes, "\n"))
end

local SORT_WORDS = { profit = "Estimated profit", cost = "Cost to make", sell = "Sell price" }

local function LayoutOppChips(list)
    local n = #list + 1
    for i = 1, math.max(n, #oppChips) do
        local b = oppChips[i]
        local p = i == 1 and { id = nil, name = "All", selected = S.opp.prof == nil } or list[i - 1]
        if i <= n then
            if not b then
                b = R.FrameLook.Toggle(opps, "", 80, function(self)
                    S.FilterProfession(self.profId)
                    lists.opps:ScrollTop()
                    Win.Render()
                end)
                b:SetHeight(22)
                oppChips[i] = b
            end
            local w = math.max(48, math.min(110, math.floor((WIDTH - PAD * 2 - 140 - 4 * (n - 1)) / n)))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", opps, "TOPLEFT", PAD + (i - 1) * (w + 4), -120)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(i == 1 and S.opp.prof == nil or (i > 1 and S.opp.prof == p.id))
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function RenderOpps()
    local v = S.Opportunities()
    oppView = v
    local src = v.source

    -- where the prices come from
    local sourceText
    if src.market then
        local age = PR.Age(src.market.at)
        sourceText = ("Prices from %s, scanned %s."):format(src.label, PR.AgeText(age))
        if age and age > PR.OLD_AFTER then sourceText = sourceText .. " These prices are old." end
        if not src.market.complete then sourceText = sourceText .. " That scan wasn't complete." end
    elseif src.open then
        sourceText = "No saved prices for this auction house yet."
    else
        sourceText = "No saved prices for this realm yet."
    end
    opps.source:SetText(sourceText)

    -- the latest scan attempt
    local msg, tone = SC.Message()
    opps.status:SetText(msg or "")
    Paint(opps.status, tone == "good" and K.sage or (tone == "warn" and K.gold or K.textDim))
    local busy = SC.Busy()
    opps.scan.text:SetText(busy and "Scanning..." or "Scan prices")
    opps.scan:SetEnabled(not busy)
    if busy then
        local frac = SC.Progress() or 0
        opps.bar:Set(frac, W.AuctionButton.BarText(msg, frac))
        opps.bar:Show()
    else
        opps.bar:Hide()
    end

    -- filters and the sort
    LayoutOppChips(S.Professions())
    opps.profitOnly:SetOn(S.opp.profitOnly)
    for key, h in pairs(heads) do
        Paint(h.text, S.opp.sort == key and K.gold or K.stone)
        h.tipBody = (S.opp.sort == key and (S.opp.desc and "Highest first. Click to show the lowest first."
            or "Lowest first. Click to show the highest first.") or "Click to sort by this.")
    end

    -- the list
    lists.opps:SetData(v.rows, v.empty)
    local sum = v.summary
    if sum.total > 0 then
        opps.summary:SetText(("%d of %d recipes priced, %d profitable. Sorted by %s, %s first. Per craft; a range is sorted by its low end.")
            :format(sum.priced, sum.total, sum.profitable, SORT_WORDS[S.opp.sort]:lower(), S.opp.desc and "highest" or "lowest"))
    else
        opps.summary:SetText("")
    end
    local notes = {}
    if v.incomplete then notes[#notes + 1] = "Some professions only list what their window's filters allow, so some recipes may be missing here." end
    if sum.total > 0 then
        notes[#notes + 1] = v.rate
            and ("Estimated profit is the sell price, less the auction house's cut, less what the materials cost.")
            or "Estimated profit is the sell price less what the materials cost. The auction house's cut isn't taken off: TwichUI hasn't confirmed it for this auction house."
        notes[#notes + 1] = "Prices are the cheapest buyout listings seen in the scan. A listing doesn't mean it will sell. Deposits and listings that don't sell aren't counted."
    end
    opps.notes:SetText(table.concat(notes, "\n"))
end

function Win.Render()
    if not f or not f:IsShown() then return end
    local Perf = R.Perf
    local pt = Perf and Perf.on and Perf.Start("workshop.render")
    renders = renders + 1
    if mode == "opps" then RenderOpps() elseif mode == "shop" then RenderShop() else RenderCraft() end
    f.note:SetText(S.Note() or (Q.Held() and "This queue was saved by a newer TwichUI and is read-only." or ""))
    if pt then Perf.Stop(pt) end
end

-- Reads the recipes' materials and output a batch at a time, so a long list doesn't hold up the game. It runs in either view after a profession
-- is read, so what the window learned is complete (and kept: Session.FillSome saves it when the last batch is in); the Opportunities
-- view is drawn between batches.
local FILL_BATCH = 120
local function Prepare()
    fillToken = fillToken + 1
    local mine = fillToken
    local function Step()
        if mine ~= fillToken or not (f and f:IsShown()) then return end
        local left = S.FillSome(FILL_BATCH)
        if mode ~= "craft" then Win.Render() end
        if left > 0 then C_Timer.After(0, Step) end
    end
    Step()
end

function Win.SetMode(m)
    if m ~= "craft" and m ~= "opps" and m ~= "shop" then return end
    mode = m
    if not f then return end
    main:SetShown(m == "craft")
    shop:SetShown(m == "shop")
    opps:SetShown(m == "opps")
    f.tabCraft:SetOn(m == "craft")
    f.tabShop:SetOn(m == "shop")
    f.tabOpps:SetOn(m == "opps")
    if f:IsShown() then
        if m ~= "craft" then Prepare() end
        Win.Render()
    end
end
function Win.Mode() return mode end

local function Flush()
    scheduled = false
    if not (f and f:IsShown()) then return end
    flushes = flushes + 1
    if dirtyRead then
        dirtyRead = false
        R.Perf.Call("workshop.read", S.Observe)
        Prepare()
    end
    if dirtyMerchant then
        dirtyMerchant = false
        R.Perf.Call("workshop.read", S.ReadMerchant)
    end
    Win.Render()
end

local function Schedule(kind)
    if kind == "read" then dirtyRead = true end
    if kind == "merchant" then dirtyMerchant = true end
    if scheduled then return end
    scheduled = true
    local mine = token
    C_Timer.After(SETTLE, function()
        if mine ~= token then return end
        Flush()
    end)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    L = R.Look
    K = L.pal
    local F = R.FrameLook
    local _, _, CR = F.ContentInsets()
    f = CreateFrame("Frame", NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")   -- without an anchor the frame is "shown" but never drawn (the window was invisible)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnEvent", function(_, event)
        local kind = EVENTS[event]
        if kind then Schedule(kind) end
    end)
    f:HookScript("OnShow", function(self)
        token = token + 1
        scheduled, dirtyRead, dirtyMerchant = false, false, false
        R.FitToScreen(self)
        for event in pairs(EVENTS) do self:RegisterEvent(event) end
        R.Perf.Call("workshop.read", S.Observe)   -- fresh before anything is shown as ready
        R.Perf.Call("workshop.read", S.ReadMerchant)   -- a merchant window already open is read too (nothing happens when none is)
        Win.Render()
        Prepare()
    end)
    f:HookScript("OnHide", function(self)
        token = token + 1
        fillToken = fillToken + 1
        scheduled, dirtyRead, dirtyMerchant = false, false, false
        self:UnregisterAllEvents()
        shopView = nil
        S.Reset()
        Q.Unload()
    end)
    f.shell = F.Shell(f, { below = true, follow = true })
    F.FadeIn(f)
    f.head = f.shell:Header(40)
    local title = L.Text(f, "title")
    title:SetPoint("TOPLEFT", PAD, -13)
    title:SetText("Workshop")
    f.close = F.Close(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -(CR + 2), -13)

    -- the two views
    f.tabCraft = F.Toggle(f, "Crafting", 84, function() Win.SetMode("craft") end)
    f.tabCraft:SetHeight(22)
    f.tabCraft:SetPoint("TOPLEFT", PAD + 100, -11)
    f.tabShop = F.Toggle(f, "Shopping", 84, function() Win.SetMode("shop") end)
    f.tabShop:SetHeight(22)
    f.tabShop:SetPoint("LEFT", f.tabCraft, "RIGHT", 4, 0)
    Tip(f.tabShop, "Shopping", "What your queue still needs, where to get each material (a vendor, the auction house or making it) and what that may cost.")
    f.tabOpps = F.Toggle(f, "Opportunities", 112, function() Win.SetMode("opps") end)
    f.tabOpps:SetHeight(22)
    f.tabOpps:SetPoint("LEFT", f.tabShop, "RIGHT", 4, 0)
    Tip(f.tabOpps, "Opportunities", "Which crafts could be worth making, from the prices of your last auction house scan.")
    main = CreateFrame("Frame", nil, f)
    main:SetSize(WIDTH, HEIGHT)
    main:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    shop = CreateFrame("Frame", nil, f)
    shop:SetSize(WIDTH, HEIGHT)
    shop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    opps = CreateFrame("Frame", nil, f)
    opps:SetSize(WIDTH, HEIGHT)
    opps:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)

    -- left: recipes
    local rh = L.Text(main, "heading")
    rh:SetPoint("TOPLEFT", PAD, -52)
    rh:SetText("Recipes")
    local box = L.EditBox(main, LEFT_W, 22)
    box:SetPoint("TOPLEFT", PAD, -100)
    box:SetMaxLetters(40)
    box.hint = L.Text(box, "meta")
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetText("Search recipes")
    box:HookScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        S.SetFilter(self:GetText())
        lists.recipes:ScrollTop()
        Win.Render()
    end)
    f.search = box
    f.notice = L.Text(main, "small")
    f.notice:SetPoint("TOPLEFT", PAD, -128)
    f.notice:SetWidth(LEFT_W)
    f.notice:SetWordWrap(true)
    f.notice:SetJustifyV("TOP")
    lists.recipes = NewList(main, PAD, -176, LEFT_W, HEIGHT - 176 - 52, REC_H, MakeRecipeRow)

    -- right: queue
    local qh = L.Text(main, "heading")
    qh:SetPoint("TOPLEFT", RIGHT_X, -52)
    qh:SetText("Queue")
    f.queueCount = L.Text(main, "meta")
    f.queueCount:SetPoint("LEFT", qh, "RIGHT", 10, 0)
    lists.queue = NewList(main, RIGHT_X, -74, RIGHT_W, 250, QUE_H, MakeQueueRow)

    -- right: materials
    local mh = L.Text(main, "heading")
    mh:SetPoint("TOPLEFT", RIGHT_X, -338)
    mh:SetText("Materials")
    local scope = L.Text(main, "meta")
    scope:SetPoint("LEFT", mh, "RIGHT", 10, 0)
    scope:SetText("Counts what is in your bags only.")
    local function Head(text, anchorX, w)
        local h = L.Text(main, "meta")
        h:SetPoint("TOPRIGHT", main, "TOPLEFT", anchorX, -362)
        h:SetWidth(w)
        h:SetJustifyH("RIGHT")
        h:SetText(text)
    end
    local colRight = RIGHT_X + RIGHT_W - 22 - 6 - 6
    Head("Still needed", colRight, 78)
    Head("In bags", colRight - 78 - 10, 52)
    Head("Need", colRight - 78 - 10 - 52 - 10, 52)
    lists.mats = NewList(main, RIGHT_X, -380, RIGHT_W, 150, MAT_H, MakeMaterialRow)
    f.headline = L.Text(main, "body")
    f.headline:SetPoint("TOPLEFT", RIGHT_X, -540)
    f.headline:SetWidth(RIGHT_W)
    f.headline:SetWordWrap(true)
    f.headline:SetJustifyV("TOP")

    -- Shopping
    local sh = L.Text(shop, "heading")
    sh:SetPoint("TOPLEFT", PAD, -52)
    sh:SetText("Shopping list")
    shop.source = L.Text(shop, "small")
    shop.source:SetPoint("TOPLEFT", PAD, -76)
    shop.source:SetWidth(WIDTH - PAD * 2)
    shop.source:SetWordWrap(false)
    shop.status = L.Text(shop, "small")
    shop.status:SetPoint("TOPLEFT", PAD, -94)
    shop.status:SetWidth(WIDTH - PAD * 2)
    shop.status:SetWordWrap(false)
    local rowRight = PAD + 4 + (WIDTH - PAD * 2 - 30)   -- the right edge of a row, in this view's coordinates
    local function ShopHead(text, right, w, justify)
        local h = L.Text(shop, "meta")
        h:SetPoint("TOPRIGHT", shop, "TOPLEFT", right, -120)
        h:SetWidth(w)
        h:SetJustifyH(justify or "RIGHT")
        h:SetText(text)
    end
    local item = L.Text(shop, "meta")
    item:SetPoint("TOPLEFT", PAD + 8, -120)
    item:SetText("Material")
    ShopHead("Estimated spending", rowRight - 2 - ACT_W - 8, SPEND_W)
    ShopHead("Source", rowRight - 2 - ACT_W - 8 - SPEND_W - 8, SOURCE_W, "CENTER")
    ShopHead("Still needed", rowRight - 2 - ACT_W - 8 - SPEND_W - 8 - SOURCE_W - 8, NEED_W)
    lists.shop = NewList(shop, PAD, -138, WIDTH - PAD * 2, 296, SHOP_H, MakeShopRow)
    shop.total = L.Text(shop, "body")
    shop.total:SetPoint("TOPLEFT", PAD, -444)
    shop.total:SetWidth(WIDTH - PAD * 2)
    shop.total:SetWordWrap(false)
    shop.notes = L.Text(shop, "meta")
    shop.notes:SetPoint("TOPLEFT", PAD, -466)
    shop.notes:SetWidth(WIDTH - PAD * 2)
    shop.notes:SetWordWrap(true)
    shop.notes:SetJustifyV("TOP")
    shop:SetShown(mode == "shop")

    -- Opportunities
    local oh = L.Text(opps, "heading")
    oh:SetPoint("TOPLEFT", PAD, -52)
    oh:SetText("Opportunities")
    opps.scan = F.Button(opps, "Scan prices", 120, "primary", function()
        S.StartScan()
        Win.Render()
    end)
    opps.scan:SetHeight(24)
    opps.scan:SetPoint("TOPRIGHT", -PAD, -48)
    opps.bar = W.NewBar(opps, 320, 24)           -- the overall progress of a scan, shown only while one runs
    opps.bar:SetPoint("TOPRIGHT", opps.scan, "TOPLEFT", -8, 0)
    opps.bar:Hide()
    Tip(opps.scan, "Scan prices", "Reads every listing at the open auction house once, so your crafts can be priced. It only reads: it never buys, bids or posts, and it starts only when you press this. It can take a little while.")
    opps.source = L.Text(opps, "small")
    opps.source:SetPoint("TOPLEFT", PAD, -76)
    opps.source:SetWidth(WIDTH - PAD * 2)
    opps.source:SetWordWrap(false)
    opps.status = L.Text(opps, "small")
    opps.status:SetPoint("TOPLEFT", PAD, -94)
    opps.status:SetWidth(WIDTH - PAD * 2)
    opps.status:SetWordWrap(false)
    opps.profitOnly = F.Toggle(opps, "Profitable only", 120, function()
        S.ToggleProfitOnly()
        lists.opps:ScrollTop()
        Win.Render()
    end)
    opps.profitOnly:SetHeight(22)
    opps.profitOnly:SetPoint("TOPRIGHT", -PAD, -120)
    Tip(opps.profitOnly, "Profitable only", "Hides crafts that lose money at these prices and crafts that couldn't be priced.")
    local x = PAD + 4 + (WIDTH - PAD * 2 - 30)   -- the right edge of a row, in this view's coordinates
    local function Head(key, text, right)
        local h = CreateFrame("Button", nil, opps)
        h:SetSize(COL_W, 18)
        h:SetPoint("TOPRIGHT", opps, "TOPLEFT", right, -150)
        h.text = L.Text(h, "meta")
        h.text:SetAllPoints()
        h.text:SetJustifyH("RIGHT")
        h.text:SetText(text)
        h:SetScript("OnClick", function() S.SortBy(key); lists.opps:ScrollTop(); Win.Render() end)
        h:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(text, 1, 0.82, 0)
                GameTooltip:AddLine(self.tipBody or "Click to sort by this.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        heads[key] = h
    end
    local item = L.Text(opps, "meta")
    item:SetPoint("TOPLEFT", PAD + 8, -150)
    item:SetText("Item (one craft)")
    Head("profit", "Estimated profit", x - (ADD_W + 12))
    Head("sell", "Sell price", x - (ADD_W + 12 + COL_W + 6))
    Head("cost", "Cost to make", x - (ADD_W + 12 + 2 * (COL_W + 6)))
    lists.opps = NewList(opps, PAD, -170, WIDTH - PAD * 2, 304, OPP_H, MakeOppRow)
    opps.summary = L.Text(opps, "small")
    opps.summary:SetPoint("TOPLEFT", PAD, -482)
    opps.summary:SetWidth(WIDTH - PAD * 2)
    opps.summary:SetWordWrap(false)
    opps.notes = L.Text(opps, "meta")
    opps.notes:SetPoint("TOPLEFT", PAD, -500)
    opps.notes:SetWidth(WIDTH - PAD * 2)
    opps.notes:SetWordWrap(true)
    opps.notes:SetJustifyV("TOP")
    opps:SetShown(mode == "opps")
    main:SetShown(mode == "craft")
    f.tabCraft:SetOn(mode == "craft")
    f.tabShop:SetOn(mode == "shop")
    f.tabOpps:SetOn(mode == "opps")
    SC.OnChange = function() if f and f:IsShown() then Schedule("draw") end end

    f.note = L.Text(f, "meta")
    f.note:SetPoint("BOTTOMLEFT", PAD, 22)
    f.note:SetWidth(WIDTH - PAD * 2)
    f.note:SetWordWrap(false)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it (never the game menu's handler list)
    return f
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function Win.Show()
    if not f then Build() end
    f:Show()
end
function Win.Hide() if f then f:Hide() end end
function Win.Toggle()
    if f and f:IsShown() then f:Hide() else Win.Show() end
end
function Win.IsShown() return f ~= nil and f:IsShown() end
function Win.Frame() return f end
function Win.Lists() return lists end
function Win.Shop() return shop end      -- the Shopping view (for the tests)
function Win.Opps() return opps end      -- the Opportunities view (for the tests)
function Win.Heads() return heads end    -- its sortable column headings (for the tests)

-- For the diagnostics gauges and the tests. Read only.
function W.Snapshot()
    local s = S.Snapshot()
    local events = 0
    if f and f:IsShown() then for _ in pairs(EVENTS) do events = events + 1 end end
    local rows = 0
    for _, l in pairs(lists) do rows = rows + #l.rows end
    s.shown = f ~= nil and f:IsShown() or false
    s.built = f ~= nil
    s.events = events
    s.rows = rows
    s.mode = mode
    s.renders = renders
    s.flushes = flushes
    return s
end

W.Open = Win.Show
W.Toggle = Win.Toggle
W.ready = true
