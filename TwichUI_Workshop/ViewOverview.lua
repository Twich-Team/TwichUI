-- TwichUI Workshop: the Overview page
-- Four cards that answer, from what is already known (nothing is scanned, read or saved to draw them): are my auction prices there and
-- how old are they, can I make anything that may earn, what is in my queue and what does it still need, and which professions the Workshop
-- knows. Each card opens its page. Under them, at most three next steps worked out from the same facts. No figure is made up: a card with
-- nothing to show says what to do to fill it.

local R = TwichUI
local W = R.Workshop
local S, PR, Op, SC, MK = W.Session, W.Prices, W.Opps, W.Scan, W.Market
local UI = W.UI

local CARD_H, GAP, FACTS, NEXT_H, TOP = 172, 12, 3, 112, -62   -- CARD_H: until the page is measured (then the cards share what Next steps leaves)

local K
local page
local cards = {}
local steps = {}

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- The painted hover of a card or a step (the settings window's material hover: a faint warm selection face and the hover rim)
local function CardHover(frame)
    local CL = UI.CL
    local hot = CL.Sheet(frame, "selection-hot", { layer = "BACKGROUND", sub = 2, corner = 10 })
    hot:SetAlpha(0.22)
    hot:Hide()
    local rim = CL.Sheet(frame, "hover-rim", { layer = "OVERLAY", sub = 3 })
    rim:Hide()
    frame:HookScript("OnEnter", function() hot:Show(); rim:Show() end)
    frame:HookScript("OnLeave", function() hot:Hide(); rim:Hide() end)
    frame:HookScript("OnHide", function() hot:Hide(); rim:Hide() end)
end

local function MakeCard(key, art, title, desc, target, x, y, w)
    local c = CreateFrame("Button", nil, page)
    c:SetPoint("TOPLEFT", x, y)
    c:SetSize(w, CARD_H)
    UI.Panel(c, "card")
    CardHover(c)
    c.art = c:CreateTexture(nil, "ARTWORK")
    c.art:SetSize(64, 64)
    c.art:SetPoint("TOPLEFT", 16, -18)
    UI.Art(c.art, art, 64)
    c.title = UI.Text(c, 20, K.text, "serif")
    c.title:SetPoint("TOPLEFT", 94, -15)
    c.title:SetText(title)
    -- the way in: a small painted button with a chevron (the whole card is the button; this one does the same)
    c.go = UI.Button(c, "", 26, "secondary", function() UI.Go(c.target) end, 26)
    c.go:SetPoint("TOPRIGHT", -14, -14)
    c.chevron = UI.Chevron(c.go, 20)
    c.chevron:SetPoint("CENTER", 1, 1)
    c.desc = UI.Text(c, 13, K.textDim)
    c.desc:SetPoint("TOPLEFT", 94, -44)
    c.desc:SetPoint("RIGHT", -48, 0)
    c.desc:SetWordWrap(true)
    c.desc:SetText(desc)
    local rule = UI.Rule(c, 0.5)
    rule:SetPoint("TOPLEFT", 94, -86); rule:SetPoint("TOPRIGHT", -16, -86)
    c.facts = {}
    for i = 1, FACTS do
        local fy = -96 - (i - 1) * 22
        local icon = c:CreateTexture(nil, "ARTWORK")
        icon:SetSize(15, 15)
        icon:SetPoint("TOPLEFT", 94, fy - 1)
        local text = UI.Text(c, 13, K.text)
        text:SetPoint("TOPLEFT", 115, fy)
        text:SetPoint("RIGHT", -16, 0)
        c.facts[i] = { icon = icon, text = text }
    end
    c.target = target
    c:SetScript("OnClick", function(self) UI.Go(self.target) end)
    cards[key] = c
    return c
end

-- A fact line: { text, status ("done" | "current" | nil for a plain dot), tone (a palette key) }
local function SetFacts(c, list)
    for i, f in ipairs(c.facts) do
        local fact = list[i]
        if fact then
            f.text:SetText(fact[1])
            UI.Paint(f.text, K[fact[3] or "text"])
            if fact[2] then
                UI.Status(f.icon, fact[2], 15)
                f.icon:SetVertexColor(1, 1, 1, 1)
            else
                f.icon:SetColorTexture(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 0.85)
                f.icon:SetSize(5, 5)
            end
            if fact[2] then f.icon:SetSize(15, 15) end
            f.icon:Show()
        else
            f.text:SetText("")
            f.icon:Hide()
        end
    end
end

local function Build(p)
    page, K = p, UI.K
    local width = page:GetWidth() or 0
    local w = math.floor(((width > 100 and width or 820) - GAP) / 2)
    local top = TOP
    MakeCard("market", "auctionHouse", "Market prices", "The cheapest auction house listings, read when you choose Scan prices.",
        "opps", 0, top, w)
    MakeCard("opps", "npc:coins", "Best opportunities", "What one craft of your known recipes could earn at those prices.",
        "opps", w + GAP, top, w)
    MakeCard("plan", "reviewChanges", "Your crafting plan", "Your queued crafts, and the materials they still need.",
        "craft", 0, top - CARD_H - GAP, w)
    MakeCard("profs", "npc:hammer-and-chisel", "Your professions", "The professions the Workshop has read for this character.",
        "craft", w + GAP, top - CARD_H - GAP, w)
    page.cards = cards
    -- the cards are laid out for the page's real size once the game has measured it: two columns, and the height Next steps leaves
    page:HookScript("OnSizeChanged", function(_, width, height)
        if not (width and height) or width < 100 or height < 300 then return end
        local cw = math.floor((width - GAP) / 2)
        local ch = math.max(150, math.floor((height + top - NEXT_H - 2 * GAP) / 2))
        for _, c in pairs(cards) do c:SetSize(cw, ch) end
        cards.opps:SetPoint("TOPLEFT", cw + GAP, top)
        cards.plan:SetPoint("TOPLEFT", 0, top - ch - GAP)
        cards.profs:SetPoint("TOPLEFT", cw + GAP, top - ch - GAP)
    end)

    -- next steps
    local n = CreateFrame("Frame", nil, page)
    n:SetPoint("BOTTOMLEFT", 0, 0)
    n:SetPoint("BOTTOMRIGHT", 0, 0)
    n:SetHeight(NEXT_H)
    UI.Panel(n, "editor")
    page.next = n
    local title = UI.Text(n, 18, K.text, "serif")
    title:SetPoint("TOPLEFT", 16, -10)
    title:SetText("Next steps")
    for i = 1, 3 do
        local s = CreateFrame("Button", nil, n)
        s:SetHeight(24)
        s:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 24)
        s:SetPoint("TOPRIGHT", -10, -36 - (i - 1) * 24)
        UI.Hover(s)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(16, 16)
        s.icon:SetPoint("LEFT", 8, 0)
        UI.Status(s.icon, "current", 16)
        s.go = UI.Text(s, 13, K.bronzeText, "strong")
        s.go:SetPoint("RIGHT", -10, 0)
        s.go:SetJustifyH("RIGHT")
        s.text = UI.Text(s, 14, K.text)
        s.text:SetPoint("LEFT", 32, 0)
        s.text:SetPoint("RIGHT", s.go, "LEFT", -12, 0)
        s:SetScript("OnClick", function(self) if self.target then UI.Go(self.target) end end)
        steps[i] = s
    end
    page.steps = steps
    n.done = UI.Text(n, 14, K.textDim)
    n.done:SetPoint("TOPLEFT", 18, -44)
    n.done:SetPoint("RIGHT", -18, 0)
    n.done:SetWordWrap(true)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local PAGE_WORDS = { opps = "Opportunities", craft = "Crafting", shop = "Shopping" }

local function Render()
    local Plural = UI.Plural
    local src = S.PriceSource()
    local market = src.market
    local info = market and MK.Info({ market = market }) or nil
    local v = S.Opportunities()
    local queue = S.QueueRows()
    local _, sum = S.Materials()
    local profs = S.Professions()
    local nextSteps = {}

    -- market prices
    local mf = {}
    local age = market and PR.Age(market.at) or nil
    if SC.Busy() then
        mf[#mf + 1] = { ("Scanning: %d%%"):format(math.floor((SC.Progress() or 0) * 100 + 0.5)), "current", "bronzeText" }
    elseif market then
        local old = age and age > PR.OLD_AFTER
        mf[#mf + 1] = { "Last scan: " .. (age and PR.AgeText(age) or "at an unknown time") .. (old and " (old)" or ""), old and "current" or "done",
            old and "bronzeText" or "text" }
    else
        mf[#mf + 1] = { "No scan yet", "current", "bronzeText" }
    end
    if info then
        local parts = { ("%d %s priced"):format(info.items or 0, Plural(info.items or 0, "item", "items")) }
        if (info.scans or 0) > 0 then parts[#parts + 1] = ("%d %s of history"):format(info.scans, Plural(info.scans, "scan day", "scan days")) end
        mf[#mf + 1] = { table.concat(parts, " \194\183 ") }
        local label = (src.label or "auction house"):gsub("^%l", string.upper)
        mf[#mf + 1] = { label .. (info.complete and "" or " \194\183 partial scan"), nil, "textDim" }
    else
        mf[#mf + 1] = { "Scan prices at the auction house.", nil, "textDim" }
        mf[#mf + 1] = { "Prices are read only when you ask.", nil, "stone" }
    end
    SetFacts(cards.market, mf)
    if not market then
        nextSteps[#nextSteps + 1] = { "Scan auction prices: open the auction house and choose Scan prices.", "opps" }
    elseif age and age > PR.OLD_AFTER then
        nextSteps[#nextSteps + 1] = { "Your prices are " .. PR.AgeText(age) .. ": scan again at the auction house.", "opps" }
    end

    -- best opportunities (the best by estimated profit, over every known recipe, whatever the Opportunities page's filters)
    local of, s = {}, v.summary
    local best = market and Op.Select(v.all, Op.DEFAULTS)[1] or nil
    if s.total == 0 then
        of[#of + 1] = { "No recipes read yet", "current", "bronzeText" }
        of[#of + 1] = { "Open one of your professions to add its recipes.", nil, "textDim" }
        nextSteps[#nextSteps + 1] = { "Open one of your professions so the Workshop can read its recipes.", "craft" }
    elseif not market then
        of[#of + 1] = { ("%d known %s, not priced yet"):format(s.total, Plural(s.total, "recipe", "recipes")), "current", "bronzeText" }
        of[#of + 1] = { "Profits appear after a price scan.", nil, "textDim" }
    else
        of[#of + 1] = { ("%d profitable of %d priced"):format(s.profitable, s.priced), s.profitable > 0 and "done" or nil,
            s.profitable > 0 and "sage" or "text" }
        if best and best.est.state == "ok" and best.est.profitLow > 0 then
            of[#of + 1] = { ("Best: %s (%s %s)"):format(best.rec.name, UI.Money(best.est.profitLow), best.est.cutRate and "profit" or "before fees") }
            if #queue == 0 then
                nextSteps[#nextSteps + 1] = { ("Plan a craft that may earn: %s."):format(best.rec.name), "opps" }
            end
        else
            of[#of + 1] = { "Nothing profitable at these prices.", nil, "textDim" }
        end
        of[#of + 1] = { ("From %d known %s"):format(s.total, Plural(s.total, "recipe", "recipes")) .. (v.incomplete and "; some may be missing" or ""),
            nil, "stone" }
    end
    SetFacts(cards.opps, of)

    -- the crafting plan
    local pf = {}
    pf[#pf + 1] = { ("%d of %d queued"):format(#queue, W.MAX_QUEUE), #queue > 0 and "done" or nil, "text" }
    local text, tone = S.Headline(sum)
    pf[#pf + 1] = { text, tone == "good" and "done" or (tone == "warn" and "current" or nil), tone == "good" and "sage" or (tone == "warn" and "bronzeText" or "textDim") }
    if sum.state ~= "empty" then
        local toGet = sum.shortItems or 0
        pf[#pf + 1] = { toGet > 0 and ("%d %s on your shopping list"):format(toGet, Plural(toGet, "material", "materials")) or "Nothing to buy",
            nil, toGet > 0 and "text" or "textDim" }
    end
    SetFacts(cards.plan, pf)
    if sum.state == "ready" then
        nextSteps[#nextSteps + 1] = { "Ready to craft: open a queued recipe from Crafting.", "craft" }
    elseif sum.state == "collect" then
        nextSteps[#nextSteps + 1] = { (S.Headline(sum)), "shop" }
    elseif sum.state == "short" then
        nextSteps[#nextSteps + 1] = { ("Get %d %s: see where on your shopping list."):format(sum.shortItems, Plural(sum.shortItems, "material", "materials")), "shop" }
    elseif sum.state == "empty" and s.total > 0 and not (best and #queue == 0 and market) then
        nextSteps[#nextSteps + 1] = { "Add recipes to your crafting plan.", "craft" }
    end

    -- professions
    local prf = {}
    for i = 1, math.min(#profs, FACTS) do
        local pr = profs[i]
        local when = pr.live and "open now" or (pr.at and ("seen " .. PR.AgeText(PR.Age(pr.at))) or "remembered")
        prf[#prf + 1] = { ("%s \194\183 %d %s \194\183 %s"):format(pr.name, pr.known, Plural(pr.known, "recipe", "recipes"), when),
            pr.live and "done" or nil, pr.live and "text" or "textDim" }
    end
    if #profs == 0 then
        prf[1] = { "None yet", "current", "bronzeText" }
        prf[2] = { "Open a profession window to add it here.", nil, "textDim" }
    elseif #profs > FACTS then
        prf[FACTS] = { ("and %d more"):format(#profs - FACTS + 1), nil, "stone" }
    end
    SetFacts(cards.profs, prf)

    -- next steps
    for i, st in ipairs(steps) do
        local step = nextSteps[i]
        if step then
            st.text:SetText(step[1])
            st.go:SetText(PAGE_WORDS[step[2]] .. "  \226\128\186")
            st.target = step[2]
            st:Show()
        else
            st:Hide()
        end
    end
    page.next.done:SetShown(#nextSteps == 0)
    page.next.done:SetText("Nothing waiting. Choose a page on the left to plan your next crafts.")
end

UI.Register({
    key = "overview", nav = "Overview", icon = "home",
    title = "Overview", sub = "Your prices, opportunities and crafting plan at a glance.",
    tip = "Where your prices, opportunities, queue and professions stand, and what to do next.",
    Build = Build, Render = Render,
})
