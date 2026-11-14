-- TwichUI Workshop: the Shopping page (a list and the chosen material's details)
-- What the queue still needs, each material once (Shopping.lua's plan, built from the same combined materials as Crafting): what to collect
-- from storage first, then what to buy (a vendor or the auction house) or make, with what it may cost. Choosing a row shows where that
-- material comes from, what is needed and owned, the source choices and the price evidence beside the list; a bar at the foot adds the plan
-- up. Buy, Make and Collect each have their own picture and word (colour is never the only sign). Nothing is bought, crafted, posted or
-- sent; the only actions are choosing a source, showing a vendor on the map and adding a subcraft to the queue, all through Session.lua.

local R = TwichUI
local W = R.Workshop
local S, O, PR, Op, Sh, K2 = W.Session, W.Observe, W.Prices, W.Opps, W.Shopping, W.Stock
local UI = W.UI

local SHOP_H, DETAIL_W, BAR_H, GAP = 56, 300, 70, 10
local NEED_W, KIND_W, SPEND_W = 46, 104, 112
local TOP = -66

local K
local page, shop
local shopView   -- what the last draw was built from (the row tooltips read it)
local chosen     -- "<item>:<kind>" of the row whose details are shown (memory only)

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

-- a row's identity: its item, and whether it is the row to collect from storage or the one to buy or make (an item has at most one of each,
-- so choosing a source, which turns a Buy row into a Make row, keeps the row chosen)
local function Key(r) return r.item .. ":" .. (r.kind == "collect" and "collect" or "own") end

-- The full basis of a row (every option with its price and age, the making plan): on a row, and on the explanation in the details
local function ShowShopBasis(owner, data)
    if not (GameTooltip and data and shopView) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local lines = Sh.Basis(data, ItemName, UI.Money, PR.AgeText, shopView.ctx.now)
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

-- The words that explain a row (what to make, how the options compare, what comes from queued crafts): the details panel shows them in full
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
    if r.kind == "buy" and r.source == "auction" then
        local _, note = Sh.CostWords(r, UI.Money)
        if note then parts[#parts + 1] = note end
        local o = r.options.auction
        if o and o.state == "few" then
            parts[#parts + 1] = ("Not enough listings to price your full quantity (%d listed)."):format(o.quote and o.quote.total or 0)
        end
    end
    if r.made and r.made > 0 then parts[#parts + 1] = ("%s%d will come from queued crafts."):format(r.madeRange and "At least " or "", r.made) end
    return table.concat(parts, " ")
end

-- Buy, Make and Collect: a painting, a word and a muted tone each
local KIND = {
    buy = { word = "Buy", art = "npc:coins", tone = "bronzeText" },
    make = { word = "Make", art = "npc:hammer", tone = "tealHi" },
    collect = { word = "Collect", art = "npc:leather-backpack", tone = "sage" },
}

-- The short second line of a list row: where it comes from, in a few words
local function ShortLine(r)
    if r.kind == "collect" then return r.where == "guild" and "From the guild bank" or "From your bank" end
    if r.kind == "make" then return "Make " .. r.make.crafts .. " \195\151 " .. UI.Shorten(r.make.rec.name, 13) end
    local text = r.source and Sh.NAMES[r.source] or "No source"
    if r.estimate then text = text .. (r.costState == "range" and " \194\183 range" or " \194\183 est.") end
    return text
end

local function MakeShopRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.2)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(38, 38)
    row.iconBtn:SetPoint("LEFT", 12, 0)
    row.iconFrame = UI.ItemIcon(row.iconBtn, 38)
    row.iconFrame:SetAllPoints()
    row.icon = row.iconFrame.tex
    UI.ItemTip(row.iconBtn, function() return row.item end)
    UI.PassClicks(row.iconBtn, row)
    -- right to left: the cost, the kind (a picture and a word), how many
    row.spend = {}
    row.spend.a = UI.Text(row, 14, K.text, "strong")
    row.spend.a:SetWidth(SPEND_W)
    row.spend.a:SetJustifyH("RIGHT")
    row.spend.a:SetPoint("TOPRIGHT", -8, -11)
    row.spend.b = UI.Text(row, 11, K.stone)
    row.spend.b:SetWidth(SPEND_W)
    row.spend.b:SetJustifyH("RIGHT")
    row.spend.b:SetPoint("TOPRIGHT", row.spend.a, "BOTTOMRIGHT", 0, -3)
    row.kindArt = row:CreateTexture(nil, "ARTWORK")
    row.kindArt:SetSize(22, 22)
    row.kindArt:SetPoint("LEFT", row.spend.a, "LEFT", -(6 + KIND_W), 0)
    row.kind = UI.Text(row, 13, K.text, "strong")
    row.kind:SetPoint("LEFT", row.kindArt, "RIGHT", 6, 0)
    row.kind:SetWidth(KIND_W - 30)
    row.need = UI.Text(row, 17, K.bronzeText, "strong")
    row.need:SetWidth(NEED_W)
    row.need:SetJustifyH("RIGHT")
    row.need:SetPoint("RIGHT", row.kindArt, "LEFT", -12, 0)
    row.name = UI.Text(row, 14, K.text, "strong")
    row.name:SetPoint("TOPLEFT", row.iconBtn, "TOPRIGHT", 9, -2)
    row.name:SetPoint("RIGHT", row.need, "LEFT", -8, 0)
    row.detail = UI.Text(row, 12, K.textDim)
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.detail:SetPoint("RIGHT", row.need, "LEFT", -8, 0)
    row.TipEnter = function(self) ShowShopBasis(self, self.data) end   -- through the row's hover (UI.Hover owns OnEnter / OnLeave)
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row:SetScript("OnClick", function(self)
        if self.data then chosen = Key(self.data); UI.Redraw() end
    end)
    row:Follow(row.iconBtn)
    row.fill = function(self, r)
        self.data, self.item = r, r.item
        local name, icon = O.ItemFacts(r.item)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.name:SetText(name or ("Item " .. r.item))
        self.detail:SetText(ShortLine(r))
        self.need:SetText(tostring(r.qty))
        local kind = KIND[r.kind] or KIND.buy
        local tone = K[kind.tone]
        UI.Paint(self.need, tone)
        UI.Art(self.kindArt, kind.art, 22)
        self.kind:SetText(kind.word)
        UI.Paint(self.kind, tone)
        UI.Paint(self.detail, r.kind == "collect" and K.sage or K.textDim)
        self:SetSelected(Key(r) == chosen)
        local a, b = self.spend.a, self.spend.b
        if r.kind == "collect" then
            -- stored materials are collected, not bought: nothing to pay
            a:SetText("Already owned")
            UI.Paint(a, K.textDim)
            b:SetText(r.at and ("seen " .. UI.AgeOf(r.at)) or "")
            return
        end
        local tag = {}
        if r.kind == "make" then
            local mk = r.make
            a:SetText(mk.cash and UI.Money(mk.cash) or "Unknown")
            UI.Paint(a, mk.cash and K.textDim or K.stone)
            b:SetText("materials, counted in their rows")
        elseif r.cash then
            local age = AgeWords(r.at, r.source == "vendor" and W.Vendor.OLD_AFTER or nil)
            if r.costState == "range" and r.high then
                -- one exact figure is not known: the cheapest it can be, and under it the most (whole listings may have to be bought)
                a:SetText(UI.Money(r.low))
                b:SetText("to " .. UI.Money(r.high))
            elseif r.costState == "estimate" and r.costInfo then
                a:SetText(UI.Money(r.low))
                b:SetText("at least" .. (age and (", " .. age) or ""))
            else
                a:SetText((r.estimate and "about " or "") .. UI.Money(r.cash))
                if r.estimate then tag[#tag + 1] = "estimate" end
                if age then tag[#tag + 1] = age end
                b:SetText(table.concat(tag, ", "))
            end
            UI.Paint(a, K.text)
        else
            a:SetText("Unknown")
            UI.Paint(a, K.stone)
            b:SetText("no price")
        end
    end
    return row
end

---------------------------------------------------------------------------
-- The chosen material's details
---------------------------------------------------------------------------
local function RenderDetail(plan, ctx)
    local d = page.detail
    local r
    for _, x in ipairs(plan.rows) do if Key(x) == chosen then r = x end end
    if not r and plan.rows[1] then r = plan.rows[1]; chosen = Key(r) end
    d.head:SetShown(r ~= nil)
    d.empty:SetShown(r == nil)
    if not r then
        chosen = nil
        d.empty:SetText("Choose a material to see where to get it, what is owned and what it may cost.")
        d.data = nil
        return
    end
    d.data = r
    local kind = KIND[r.kind] or KIND.buy
    local name, icon = O.ItemFacts(r.item)
    d.item = r.item
    d.icon:SetTexture(icon or UI.ICON_BLANK)
    d.name:SetText(name or ("Item " .. r.item))
    UI.Art(d.kindArt, kind.art, 22)
    d.kindWord:SetText(kind.word)
    UI.Paint(d.kindWord, K[kind.tone])
    -- quantities: the plan's own numbers, nothing recalculated
    local lines = {}
    if r.need then lines[#lines + 1] = { "Needed in total", tostring(r.need) } end
    if r.have ~= nil then lines[#lines + 1] = { "In your bags", tostring(r.have) } end
    if r.made and r.made > 0 then lines[#lines + 1] = { "From queued crafts", (r.madeRange and "at least " or "") .. r.made } end
    if r.kind == "collect" then
        lines[#lines + 1] = { r.where == "guild" and "To collect from guild bank" or "To collect from bank", tostring(r.qty), true }
    else
        lines[#lines + 1] = { r.reagentOnly and "To get (for making)" or "To get", tostring(r.qty), true }
    end
    for i, line in ipairs(d.qty) do
        local x = lines[i]
        if x then
            line.l:SetText(x[1]); line.v:SetText(x[2])
            UI.Paint(line.v, x[3] and K[kind.tone] or K.text)
            UI.Paint(line.l, x[3] and K.text or K.textDim)
            line.l:Show(); line.v:Show()
        else
            line.l:Hide(); line.v:Hide()
        end
    end
    -- the source choices: only those that can really be chosen are enabled; the chosen one is lit
    local choices, set = Sh.Choices(r), {}
    for _, k in ipairs(choices) do set[k] = true end
    if r.source then set[r.source] = true end
    local isBuyMake = r.kind ~= "collect"
    for _, k in ipairs(Sh.ORDER) do
        local b = d.choose[k]
        b:SetShown(isBuyMake)
        b:SetEnabled(isBuyMake and set[k] == true)
        b:SetOn(isBuyMake and r.source == k)
        -- the words under a choice: the one Workshop suggests, and (when it differs) the one the player chose
        local tag = d.tags[k]
        local suggested = isBuyMake and r.suggested == k
        local mine = isBuyMake and r.picked and r.source == k and r.suggested ~= k
        tag:SetText(suggested and "Suggested" or (mine and "Your choice" or ""))
        UI.Paint(tag, suggested and K.sage or K.bronzeText)
        tag:SetShown(isBuyMake)
    end
    d.useSuggestion:SetShown(isBuyMake and r.picked == true and r.suggested ~= nil and r.source ~= r.suggested)
    d.sourceHead:SetText(isBuyMake and "Source" or "Where")
    d.explainBox:ClearAllPoints()
    d.explainBox:SetPoint("TOPLEFT", 14, isBuyMake and -252 or -208)
    d.explainBox:SetPoint("TOPRIGHT", -14, isBuyMake and -252 or -208)
    d.explain:SetText(ShopDetail(r))
    -- the price evidence
    if r.kind == "collect" then
        d.costLabel:SetText("Cost")
        d.cost:SetText("Already owned")
        UI.Paint(d.cost, K.textDim)
        d.costNote:SetText(r.at and ("seen " .. UI.AgeOf(r.at)) or "")
    elseif r.kind == "make" then
        local mk = r.make
        d.costLabel:SetText("Materials cash")
        d.cost:SetText(mk.cash and UI.Money(mk.cash) or "Unknown")
        UI.Paint(d.cost, mk.cash and K.text or K.stone)
        d.costNote:SetText("the reagents are counted in their own rows")
    else
        d.costLabel:SetText(r.estimate and "Estimated cost" or "Cost")
        local short = r.cash and Sh.CostWords(r, UI.Money)
        d.cost:SetText(short or "Unknown")
        UI.Paint(d.cost, r.cash and K.text or K.stone)
        local tag = {}
        if r.source then tag[#tag + 1] = Sh.NAMES[r.source] end
        local info = r.source == "auction" and r.costInfo or nil
        if info and info.used and info.used[1] then tag[#tag + 1] = "lowest " .. UI.Money(info.used[1].p) end
        local age = AgeWords(r.at, r.source == "vendor" and W.Vendor.OLD_AFTER or nil)
        if age then tag[#tag + 1] = age end
        local why = r.source == "auction" and r.options.auction and r.options.auction.state == "few" and "not enough listed" or "no price known"
        d.costNote:SetText(r.cash and table.concat(tag, ", ") or why)
    end
    -- what the queue needs it for
    local used = S.NeededFor(r.item)
    d.usedFor:SetText(#used > 0 and ("Needed for: " .. table.concat(used, ", ")) or (r.forNames and ("Needed to make: " .. table.concat(r.forNames, ", ")) or ""))
    -- the one action that fits the row
    if r.kind == "make" then
        d.act.text:SetText("Add to crafting plan")
        d.act:Show()
    elseif r.kind ~= "collect" and r.source == "vendor" and ctx and ctx.sellers[r.item] then
        d.act.text:SetText("Show vendor")
        d.act:Show()
    else
        d.act:Hide()
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local Plural = UI.Plural

local function Render()
    local plan, ctx = S.Shopping()
    shopView = { plan = plan, ctx = ctx }
    local sum, tot = ctx.summary, plan.totals
    shop.useGuild:SetOn(ctx.stock.guild.enabled)

    shop.status:SetText(("Vendor prices as last seen (%d noted) \194\183 %s"):format(W.Vendor.Count(), K2.Scope(ctx.stock)))

    -- what kinds of rows there are
    local n = { collect = 0, buy = 0, make = 0 }
    for _, r in ipairs(plan.rows) do n[r.kind] = (n[r.kind] or 0) + 1 end
    for kind, badge in pairs(shop.counts) do badge.n:SetText(tostring(n[kind] or 0)) end

    local empty
    if sum.state == "empty" then empty = "Add recipes to the queue to build a shopping list."
    elseif #plan.rows == 0 then
        if sum.state == "ready" then empty = "Nothing to buy: the materials are in your bags, or made by your queue."
        else empty = (S.Headline(sum)) end
    end
    RenderDetail(plan, ctx)
    UI.lists.shop:SetData(plan.rows, empty)

    -- the total: only what is priced, and never as if it were complete when it is not
    if #plan.rows == 0 then
        shop.total:SetText("")
    elseif tot.priced + tot.missing + tot.makes == 0 then
        shop.total:SetText("Nothing to buy: collect what is stored.")   -- only collect rows: stored materials cost nothing to get
        UI.Paint(shop.total, K.sage)
    elseif tot.missing > 0 then
        shop.total:SetText(("Estimated spending: %s%s so far \194\183 %d %s"):format(tot.open and "at least " or "", UI.Money(tot.cash), tot.missing,
            Plural(tot.missing, "price missing", "prices missing")))
        UI.Paint(shop.total, K.bronzeText)
    elseif tot.estimate and tot.open then
        shop.total:SetText("Estimated spending: at least " .. UI.Money(tot.low))   -- some price is only a lower bound: no upper end is claimed
        UI.Paint(shop.total, K.text)
    elseif tot.estimate and tot.high and tot.high > tot.low then
        shop.total:SetText("Estimated spending: " .. UI.Money(tot.low) .. " to " .. UI.Money(tot.high))
        UI.Paint(shop.total, K.text)
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
    if (n.buy or 0) + (n.make or 0) > 0 then
        notes[#notes + 1] = "Suggestions compare one material at a time; owned materials lower what you spend but aren't free."
    end
    local stockNote = S.StockNote(sum, ctx.stock)
    if stockNote then notes[#notes + 1] = stockNote end
    shop.notesAll = table.concat(notes, "\n")
    shop.notes:SetText(table.concat(notes, " "))
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Section(parent, text, y)
    local h = UI.Text(parent, 13, K.bronzeText, "strong")
    h:SetPoint("TOPLEFT", 14, y)
    h:SetText(text)
    local rule = UI.Rule(parent, 0.45)
    rule:SetPoint("TOPLEFT", 14, y - 18); rule:SetPoint("TOPRIGHT", -14, y - 18)
    return h
end

local function BuildDetail()
    local d = CreateFrame("Frame", nil, shop)
    d:SetPoint("TOPRIGHT", 0, TOP)
    d:SetPoint("BOTTOMRIGHT", 0, BAR_H + GAP)
    d:SetWidth(DETAIL_W)
    UI.Panel(d, "card")
    page.detail = d
    d.head = CreateFrame("Frame", nil, d)
    d.head:SetAllPoints()
    local ib = CreateFrame("Button", nil, d.head)
    ib:SetSize(48, 48)
    ib:SetPoint("TOPLEFT", 14, -12)
    d.iconFrame = UI.ItemIcon(ib, 48)
    d.iconFrame:SetAllPoints()
    d.icon = d.iconFrame.tex
    UI.ItemTip(ib, function() return d.item end)
    d.name = UI.Text(d.head, 19, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 74, -12)
    d.name:SetWidth(DETAIL_W - 74 - 14)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.name:SetJustifyV("TOP")
    d.kindArt = d.head:CreateTexture(nil, "ARTWORK")
    d.kindArt:SetSize(20, 20)
    d.kindArt:SetPoint("BOTTOMLEFT", ib, "BOTTOMRIGHT", 10, 0)
    d.kindWord = UI.Text(d.head, 14, K.text, "strong")
    d.kindWord:SetPoint("LEFT", d.kindArt, "RIGHT", 6, 0)
    -- quantities
    Section(d.head, "Quantities", -72)
    d.qty = {}
    for i = 1, 4 do
        local y = -96 - (i - 1) * 19
        local v = UI.Text(d.head, 14, K.text, "strong")
        v:SetPoint("TOPRIGHT", -14, y)
        v:SetJustifyH("RIGHT")
        local l = UI.Text(d.head, 13, K.textDim)
        l:SetPoint("TOPLEFT", 14, y)
        d.qty[i] = { l = l, v = v }
    end
    -- the source: the choices, which one Workshop suggests, and which one is the player's own. A small caption under a choice says so
    -- ("Suggested", "Your choice") in words, and "Use suggestion" returns to the suggestion when another source was chosen.
    d.sourceHead = Section(d.head, "Source", -180)
    d.choose, d.tags = {}, {}
    local bw = math.floor((DETAIL_W - 28 - 8) / 3)
    for i, k in ipairs(Sh.ORDER) do
        local b = UI.Segment(d.head, k == "auction" and "Auction" or Sh.NAMES[k], bw, function()
            if d.data then
                -- the chosen source again returns to the suggestion
                if S.picks[d.data.item] == k then S.PickSource(d.data.item, nil) else S.PickSource(d.data.item, k) end
                UI.Redraw()
            end
        end)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * (bw + 4), -204)
        UI.TipFn(b, Sh.NAMES[k], function()
            local r = d.data
            if not r then return nil end
            local why = Sh.WhyNot(r, k)
            if why then return "Not available: " .. why end
            local text = "Choose this to get the material this way. Nothing is bought or made for you."
            if r.suggested == k then text = "Workshop's suggestion: the lowest known cost. " .. text
            elseif r.source == k then text = "Your choice. Choose it again, or use the suggestion, to go back. " .. text end
            return text
        end)
        d.choose[k] = b
        local tag = UI.Text(d.head, 11, K.sage)
        tag:SetPoint("TOP", b, "BOTTOM", 0, -2)
        tag:SetWidth(bw)
        tag:SetJustifyH("CENTER")
        d.tags[k] = tag
    end
    d.useSuggestion = UI.Button(d.head, "Use suggestion", 112, "secondary", function()
        if d.data then S.PickSource(d.data.item, nil); UI.Redraw() end
    end, 20)
    d.useSuggestion:SetPoint("TOPRIGHT", -14, -175)
    UI.Tip(d.useSuggestion, "Use suggestion", "Goes back to the source Workshop suggests for this material: the one with the lowest known cost.")
    d.useSuggestion:Hide()
    d.explainBox = CreateFrame("Frame", nil, d.head)
    d.explainBox:SetPoint("TOPLEFT", 14, -252)
    d.explainBox:SetPoint("TOPRIGHT", -14, -252)
    d.explainBox:SetHeight(40)
    d.explainBox:EnableMouse(true)
    d.explainBox:SetScript("OnEnter", function(self) ShowShopBasis(self, d.data) end)
    d.explainBox:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    d.explain = UI.Text(d.explainBox, 12, K.textDim)
    d.explain:SetPoint("TOPLEFT", 0, 0)
    d.explain:SetWidth(DETAIL_W - 28)
    d.explain:SetHeight(40)
    d.explain:SetWordWrap(true)
    -- the price
    d.costLabel = UI.Text(d.head, 12, K.stone)
    d.costLabel:SetPoint("TOPLEFT", 14, -300)
    d.cost = UI.Text(d.head, 17, K.text, "strong")
    d.cost:SetPoint("TOPRIGHT", -14, -296)
    d.cost:SetJustifyH("RIGHT")
    d.costNote = UI.Text(d.head, 11, K.stone)
    d.costNote:SetPoint("TOPRIGHT", -14, -317)
    d.costNote:SetJustifyH("RIGHT")
    d.costNote:SetWidth(DETAIL_W - 28)
    d.usedFor = UI.Text(d.head, 12, K.textDim)
    d.usedFor:SetPoint("TOPLEFT", 14, -334)
    d.usedFor:SetPoint("RIGHT", -14, 0)
    d.usedFor:SetWordWrap(true)
    d.usedFor:SetJustifyV("TOP")
    d.usedFor:SetHeight(28)
    d.act = UI.ArtButton(d, "Show vendor", "npc:coins", DETAIL_W - 28, "primary", function()
        local x = d.data
        if not x then return end
        if x.kind == "make" then S.AddSubcraft(x.item) else S.ShowVendor(x.item) end
        UI.Redraw()
    end, 34)
    d.act:SetPoint("BOTTOMLEFT", 14, 12)
    d.act:SetPoint("BOTTOMRIGHT", -14, 12)
    UI.Tip(d.act, "Show vendor / Add to crafting plan", "Show vendor: shows a vendor seen to sell this on the world map. It sets no waypoint and starts no route. Add to crafting plan: queues the crafts that make this, so the queue makes it. Nothing is bought or crafted.")
    d.empty = UI.Text(d, 13, K.textDim)
    d.empty:SetPoint("TOPLEFT", 14, -16)
    d.empty:SetPoint("RIGHT", -14, 0)
    d.empty:SetWordWrap(true)
    d.empty:SetJustifyV("TOP")
    page.act = d.act
end

local function BuildBar()
    local bar = CreateFrame("Frame", nil, shop)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetHeight(BAR_H)
    UI.Panel(bar, "editor")
    bar:EnableMouse(true)
    shop.bar = bar
    shop.counts = {}
    for i, k in ipairs({ "buy", "make", "collect" }) do
        local kind = KIND[k]
        local x = 14 + (i - 1) * 98
        local art = bar:CreateTexture(nil, "ARTWORK")
        art:SetSize(26, 26)
        art:SetPoint("LEFT", bar, "LEFT", x, 0)
        UI.Art(art, kind.art, 26)
        local n = UI.Text(bar, 20, K[kind.tone], "strong")
        n:SetPoint("TOPLEFT", art, "TOPRIGHT", 8, 6)
        local l = UI.Text(bar, 12, K.textDim)
        l:SetPoint("TOPLEFT", n, "TOPRIGHT", 5, -5)
        l:SetText(kind.word)
        shop.counts[k] = { n = n, label = l }
    end
    local rule = UI.Rule(bar, 0.6)
    rule:SetWidth(1)
    rule:ClearAllPoints()
    rule:SetPoint("TOP", bar, "TOPLEFT", 312, -12)
    rule:SetPoint("BOTTOM", bar, "BOTTOMLEFT", 312, 12)
    -- the spending line has the bar's whole remaining width and one line (its sentences are kept short enough to fit); the notes beneath
    -- wrap to two lines, and every note is in the bar's tooltip
    shop.total = UI.Text(bar, 14, K.text, "strong")
    shop.total:SetPoint("TOPLEFT", 328, -9)
    shop.total:SetPoint("RIGHT", bar, "RIGHT", -14, 0)
    shop.total:SetHeight(18)
    shop.notes = UI.Text(bar, 11, K.textDim)
    shop.notes:SetPoint("TOPLEFT", 328, -30)
    shop.notes:SetPoint("RIGHT", bar, "RIGHT", -14, 0)
    shop.notes:SetHeight(34)
    shop.notes:SetWordWrap(true)
    shop.notes:SetJustifyV("TOP")
    -- a wrapped text wants an explicit width: the bar's width less its left part and margin, set now and whenever the bar is sized
    local function Widths(w)
        local room = math.max(200, (w or 820) - 328 - 14)
        shop.total:SetWidth(room)
        shop.notes:SetWidth(room)
    end
    Widths(820)
    bar:HookScript("OnSizeChanged", function(_, w) if w and w >= 300 then Widths(w) end end)
    UI.TipFn(bar, "Shopping plan", function() return shop.notesAll ~= "" and shop.notesAll or nil end)
end

local function Build(p)
    page, shop, K = p, p, UI.K
    shop.useGuild = UI.Switch(shop, "Use guild bank", function()
        S.SetUseGuild(not S.UseGuild())
        UI.Redraw()
    end)
    shop.useGuild:SetPoint("TOPRIGHT", -2, -10)
    shop.status = UI.Text(shop, 12, K.stone)
    shop.status:SetPoint("TOPRIGHT", -2, -38)
    shop.status:SetJustifyH("RIGHT")
    UI.Tip(shop.useGuild, "Use guild bank materials", UI.USE_GUILD_TIP)

    -- the list
    local card = CreateFrame("Frame", nil, shop)
    card:SetPoint("TOPLEFT", 0, TOP)
    card:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 12), BAR_H + GAP)
    UI.Panel(card, "card")
    shop.card = card
    local right = -(4 + 16 + 8)   -- the rows' right edge in the card: the list's inset, its scroll gutter and the rows' own margin
    local item = UI.Head(card, "Material", 120, "LEFT")
    item:SetPoint("TOPLEFT", 62, -15)
    local hSpend = UI.Head(card, "Estimated cost", SPEND_W)
    hSpend:SetPoint("TOPRIGHT", right, -15)
    local hKind = UI.Head(card, "Source", KIND_W, "LEFT")
    hKind:SetPoint("TOPLEFT", card, "TOPRIGHT", right - SPEND_W - 6 - KIND_W, -15)
    local hNeed = UI.Head(card, "To get", NEED_W)
    hNeed:SetPoint("TOPRIGHT", card, "TOPRIGHT", right - SPEND_W - 6 - KIND_W - 12, -15)
    local rule = UI.Rule(card, 0.5)
    rule:SetPoint("TOPLEFT", 12, -34); rule:SetPoint("TOPRIGHT", -12, -34)
    local list = UI.List(card, SHOP_H, MakeShopRow, 360, false)
    list.box:SetPoint("TOPLEFT", 4, -36)
    list.box:SetPoint("BOTTOMRIGHT", -4, 4)
    UI.lists.shop = list

    BuildDetail()
    BuildBar()
end

UI.Register({
    key = "shop", nav = "Shopping", icon = "npc:reagent-pouch",
    title = "Shopping", sub = "What your queue still needs, and where to get it.",
    tip = "What your queue still needs, where to get each material (a vendor, the auction house or making it) and what that may cost.",
    Build = Build, Render = Render,
    Reset = function() shopView = nil; chosen = nil end,
})
