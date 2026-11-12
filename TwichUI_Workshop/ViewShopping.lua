-- TwichUI Workshop: the Shopping page
-- What the queue still needs, each material once (Shopping.lua's plan, built from the same combined materials as Crafting): what to collect
-- from storage first, then what to buy (a vendor or the auction house) or make, with what it may cost. Hovering a row shows the full basis.
-- Nothing is bought, crafted, posted or sent; the only actions are choosing a source, showing a vendor on the map and adding a subcraft to the
-- queue, all through Session.lua.

local R = TwichUI
local W = R.Workshop
local S, O, PR, Op, Sh, K2 = W.Session, W.Observe, W.Prices, W.Opps, W.Shopping, W.Stock
local UI = W.UI

local SHOP_H = 58
local NEED_W, SOURCE_W, SPEND_W, ACT_W, GAP = 64, 124, 168, 110, 10

local K
local page, shop
local shopView   -- what the last draw was built from (the row tooltips read it)

local function ItemName(item)
    local name = O.ItemFacts(item)
    return name or ("Item " .. item)
end
UI.ItemName = ItemName

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
    local lines = Sh.Basis(row.data, ItemName, UI.Money, PR.AgeText, shopView.ctx.now)
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
    if r.kind == "collect" then
        if r.where == "guild" then
            parts[#parts + 1] = "Collect from the guild bank. Shared stock: other members can take it too" ..
                (r.limited and ", and a withdrawal limit may apply." or ".")
        else
            parts[#parts + 1] = "Collect from your bank. It is already yours: nothing to buy."
        end
        if r.forNames then parts[#parts + 1] = ("Also for making %s."):format(table.concat(r.forNames, " and ")) end
        return table.concat(parts, " ")
    end
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

-- The thin mark at a row's left edge: what kind of row it is (always beside the words in the Source column)
local KIND_TONE = { collect = "sage", buy = "bronzeText", make = "tealHi" }

local function MakeShopRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.25)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.mark = UI.L.Solid(row, "ARTWORK", K.sage, 0.8)
    row.mark:SetWidth(2)
    row.mark:SetPoint("TOPLEFT", 2, -9)
    row.mark:SetPoint("BOTTOMLEFT", 2, 9)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(34, 34)
    row.iconBtn:SetPoint("TOPLEFT", 10, -9)
    row.iconFrame = UI.ItemIcon(row.iconBtn, 34)
    row.iconFrame:SetAllPoints()
    row.icon = row.iconFrame.tex
    UI.ItemTip(row.iconBtn, function() return row.item end)
    row.act = UI.Button(row, "Show vendor", ACT_W, "secondary", function()
        local d = row.data
        if not d then return end
        if d.kind == "make" then S.AddSubcraft(d.item) else S.ShowVendor(d.item) end
        UI.Redraw()
    end, 26)
    row.act:SetPoint("TOPRIGHT", -6, -8)
    UI.Tip(row.act, "Show vendor / Add to queue", "Show vendor: shows a vendor seen to sell this on the world map. It sets no waypoint and starts no route. Add to queue: queues the crafts that make this, so the queue makes it. Nothing is bought or crafted.")
    row.spend = {}
    row.spend.a = UI.Text(row, 14, K.text)
    row.spend.a:SetWidth(SPEND_W)
    row.spend.a:SetJustifyH("RIGHT")
    row.spend.a:SetPoint("TOPRIGHT", -(6 + ACT_W + GAP), -10)
    row.spend.b = UI.Text(row, 12, K.stone)
    row.spend.b:SetWidth(SPEND_W)
    row.spend.b:SetJustifyH("RIGHT")
    row.spend.b:SetPoint("TOPRIGHT", row.spend.a, "BOTTOMRIGHT", 0, -4)
    row.source = UI.Button(row, "", SOURCE_W, "secondary", function()
        if row.item then S.CycleSource(row.item); UI.Redraw() end
    end, 26)
    row.source:SetPoint("TOPRIGHT", -(6 + ACT_W + GAP + SPEND_W + GAP), -8)
    UI.Tip(row.source, "Source", "Where this comes from. Click to change it: the suggestion, then each way that is possible (vendor, auction house, make). Nothing is bought or made for you.")
    row.where = UI.Text(row, 13, K.sage)   -- on a collect row: where to collect it, in place of the source button
    row.where:SetWidth(SOURCE_W)
    row.where:SetJustifyH("CENTER")
    row.where:SetWordWrap(true)
    row.where:SetPoint("TOP", row.source, "TOP", 0, -1)
    row.where:Hide()
    row.need = UI.Text(row, 15, K.bronzeText, "strong")
    row.need:SetWidth(NEED_W)
    row.need:SetJustifyH("RIGHT")
    row.need:SetPoint("TOPRIGHT", row.source, "TOPLEFT", -GAP, -4)
    row.name = UI.Text(row, 14, K.text)
    row.name:SetPoint("TOPLEFT", 54, -9)
    row.name:SetPoint("RIGHT", row.need, "LEFT", -8, 0)
    row.detail = UI.Text(row, 12, K.textDim)
    row.detail:SetPoint("TOPLEFT", 54, -28)
    row.detail:SetPoint("RIGHT", row.spend.a, "LEFT", -18, 0)
    row.detail:SetHeight(28)
    row.detail:SetWordWrap(true)
    row.detail:SetJustifyV("TOP")
    row:SetScript("OnEnter", ShowShopBasis)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, r)
        self.data, self.item = r, r.item
        local name, icon = O.ItemFacts(r.item)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.name:SetText(name or ("Item " .. r.item))
        self.detail:SetText(ShopDetail(r))
        self.need:SetText(tostring(r.qty))
        UI.Paint(self.need, K.bronzeText)
        local tone = K[KIND_TONE[r.kind] or "bronzeText"]
        self.mark:SetColorTexture(tone[1], tone[2], tone[3], 0.8)
        if r.kind == "collect" then
            -- stored materials are collected, not bought: no source to choose, nothing to pay, no action
            UI.Paint(self.need, K.sage)
            self.source:Hide()
            self.where:SetText(r.where == "guild" and "Collect from guild bank" or "Collect from bank")
            self.where:Show()
            self.spend.a:SetText("Already owned")
            UI.Paint(self.spend.a, K.textDim)
            self.spend.b:SetText(r.at and ("seen " .. UI.AgeOf(r.at)) or "")
            self.act:Hide()
            return
        end
        self.source:Show()
        self.where:Hide()
        local choices = Sh.Choices(r)
        self.source.text:SetText(r.source and Sh.NAMES[r.source] or "No source")
        self.source:SetEnabled(#choices > 0)
        -- spending
        local a, b = self.spend.a, self.spend.b
        local tag = {}
        if r.kind == "make" then
            local mk = r.make
            a:SetText(mk.cash and UI.Money(mk.cash) or "Unknown")
            UI.Paint(a, mk.cash and K.textDim or K.stone)
            b:SetText("materials, counted in their rows")
        elseif r.cash then
            a:SetText((r.estimate and "about " or "") .. UI.Money(r.cash))
            UI.Paint(a, K.text)
            if r.estimate then tag[#tag + 1] = "estimate" end
            local age = AgeWords(r.at, r.source == "vendor" and W.Vendor.OLD_AFTER or nil)
            if age then tag[#tag + 1] = age end
            b:SetText(table.concat(tag, ", "))
        else
            a:SetText("Unknown")
            UI.Paint(a, K.stone)
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

local Plural = UI.Plural

local function Render()
    local plan, ctx = S.Shopping()
    shopView = { plan = plan, ctx = ctx }
    local sum, src, tot = ctx.summary, ctx.source, plan.totals

    -- where the prices come from
    local sourceText
    if src.market then
        sourceText = ("Auction prices: %s \194\183 %s"):format(src.label, Op.ScanWords({ at = src.market.at, complete = src.market.complete }) or "")
    else
        sourceText = "No saved auction prices. Choose Scan prices in Opportunities at the auction house."
    end
    shop.source:SetText(sourceText)
    shop.status:SetText(("Vendor prices as last seen (%d noted) \194\183 %s"):format(W.Vendor.Count(), K2.Scope(ctx.stock)))
    shop.useGuild:SetOn(ctx.stock.guild.enabled)

    -- what kinds of rows there are, in words
    local n = { collect = 0, buy = 0, make = 0 }
    for _, r in ipairs(plan.rows) do n[r.kind] = (n[r.kind] or 0) + 1 end
    local mix = {}
    if n.collect > 0 then mix[#mix + 1] = ("%d to collect"):format(n.collect) end
    if n.buy > 0 then mix[#mix + 1] = ("%d to buy"):format(n.buy) end
    if n.make > 0 then mix[#mix + 1] = ("%d to make"):format(n.make) end
    shop.mix:SetText(table.concat(mix, " \194\183 "))

    local empty
    if sum.state == "empty" then empty = "Add recipes to the queue to build a shopping list."
    elseif #plan.rows == 0 then
        if sum.state == "ready" then empty = "Nothing to buy: the materials are in your bags, or made by your queue."
        else empty = (S.Headline(sum)) end
    end
    UI.lists.shop:SetData(plan.rows, empty)

    -- the total: only what is priced, and never as if it were complete when it is not
    if #plan.rows == 0 then
        shop.total:SetText("")
    elseif tot.priced + tot.missing + tot.makes == 0 then
        shop.total:SetText("Nothing to buy: collect what is stored.")   -- only collect rows: stored materials cost nothing to get
        UI.Paint(shop.total, K.sage)
    elseif tot.missing > 0 then
        shop.total:SetText(("Estimated spending: %s so far. Some prices missing: %d %s."):format(UI.Money(tot.cash), tot.missing,
            Plural(tot.missing, "material has no price", "materials have no price")))
        UI.Paint(shop.total, K.bronzeText)
    else
        shop.total:SetText("Estimated spending: " .. UI.Money(tot.cash) .. (tot.estimate and " (includes estimates)" or ""))
        UI.Paint(shop.total, K.text)
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
        notes[#notes + 1] = "Suggestions compare one material at a time; owned materials lower what you spend but aren't free."
    end
    local stockNote = S.StockNote(sum, ctx.stock)
    if stockNote then notes[#notes + 1] = stockNote end
    shop.notes:SetText(table.concat(notes, "\n"))
end

local function Build(p)
    page, shop, K = p, p, UI.K
    shop.useGuild = UI.Switch(shop, "Use guild bank", function()
        S.SetUseGuild(not S.UseGuild())
        UI.Redraw()
    end)
    shop.useGuild:SetPoint("TOPRIGHT", -2, -8)
    UI.Tip(shop.useGuild, "Use guild bank materials", UI.USE_GUILD_TIP)
    shop.source = UI.Text(shop, 13, K.textDim)
    shop.source:SetPoint("TOPLEFT", 1, -62)
    shop.source:SetPoint("RIGHT", -230, 0)
    shop.status = UI.Text(shop, 13, K.stone)
    shop.status:SetPoint("TOPLEFT", 1, -80)
    shop.status:SetPoint("RIGHT", -230, 0)
    shop.mix = UI.Text(shop, 14, K.bronzeText, "strong")
    shop.mix:SetPoint("TOPRIGHT", -2, -68)
    shop.mix:SetJustifyH("RIGHT")

    -- the list
    local card = CreateFrame("Frame", nil, shop)
    card:SetPoint("TOPLEFT", 0, -104)
    card:SetPoint("BOTTOMRIGHT", 0, 96)
    UI.Panel(card, "card")
    shop.card = card
    local right = -(4 + 16 + 6)   -- the rows' right edge in the card: the list's inset, its scroll gutter and the rows' own margin
    local item = UI.Head(card, "Material", 120, "LEFT")
    item:SetPoint("TOPLEFT", 58, -14)
    local hSpend = UI.Head(card, "Estimated spending", SPEND_W)
    hSpend:SetPoint("TOPRIGHT", right - ACT_W - GAP, -14)
    local hSource = UI.Head(card, "Source", SOURCE_W, "CENTER")
    hSource:SetPoint("TOPRIGHT", right - ACT_W - GAP - SPEND_W - GAP, -14)
    local hNeed = UI.Head(card, "To get", NEED_W)
    hNeed:SetPoint("TOPRIGHT", right - ACT_W - GAP - SPEND_W - GAP - SOURCE_W - GAP, -14)
    local rule = UI.Rule(card, 0.45)
    rule:SetPoint("TOPLEFT", 12, -32); rule:SetPoint("TOPRIGHT", -12, -32)
    local list = UI.List(card, SHOP_H, MakeShopRow, 300, false)
    list.box:SetPoint("TOPLEFT", 4, -34)
    list.box:SetPoint("BOTTOMRIGHT", -4, 4)
    UI.lists.shop = list

    -- the total and the notes
    local foot = CreateFrame("Frame", nil, shop)
    foot:SetPoint("BOTTOMLEFT", 0, 0)
    foot:SetPoint("BOTTOMRIGHT", 0, 0)
    foot:SetHeight(84)
    UI.Panel(foot, "editor")
    shop.total = UI.Text(foot, 15, K.text, "strong")
    shop.total:SetPoint("TOPLEFT", 14, -12)
    shop.total:SetPoint("RIGHT", -14, 0)
    shop.notes = UI.Text(foot, 12, K.textDim)
    shop.notes:SetPoint("TOPLEFT", 14, -34)
    shop.notes:SetPoint("RIGHT", -14, 0)
    shop.notes:SetWordWrap(true)
    shop.notes:SetJustifyV("TOP")
end

UI.Register({
    key = "shop", nav = "Shopping", icon = "npc:reagent-pouch",
    title = "Shopping", sub = "What your queue still needs, and where to get it.",
    tip = "What your queue still needs, where to get each material (a vendor, the auction house or making it) and what that may cost.",
    Build = Build, Render = Render,
    Reset = function() shopView = nil end,
})
