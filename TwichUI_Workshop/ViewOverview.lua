-- TwichUI Workshop: the Overview page
-- Four cards that answer, from what is already known (nothing is scanned or saved to draw them): are my auction prices there and how old are
-- they, can I make anything that may earn, what is in my queue and what does it still need, and how far along my professions are. Each card
-- opens its page. Under them, what happened this session and the three things most often wanted next. No figure is made up: a card with
-- nothing to show says what to do to fill it, and a profession whose skill the game won't give is drawn as unavailable, never as zero.

local R = TwichUI
local W = R.Workshop
local S, PR, Op, SC, MK = W.Session, W.Prices, W.Opps, W.Scan, W.Market
local UI = W.UI

local GAP, BOTTOM_H, TOP = 12, 118, -68
local ART, TEXT_X = 92, 120
local PROF_ROWS, PROF_TOP, PROF_MIN, PROF_MAX, PROF_BOTTOM = 4, 90, 18, 24, 10   -- the professions list: its top in the card, the row pitch limits, the foot

local K
local page
local cards = {}
local actions = {}

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- The painted hover of a card (the settings window's material hover: a faint warm selection face and the hover rim)
local function CardHover(frame)
    local CL = UI.CL
    local hot = CL.Sheet(frame, "selection-hot", { layer = "BACKGROUND", sub = 2, corner = 10 })
    hot:SetAlpha(0.45)
    hot:Hide()
    local rim = CL.Sheet(frame, "hover-rim", { layer = "OVERLAY", sub = 3 })
    rim:Hide()
    frame.twichHot, frame.twichRim = hot, rim
    -- the scripts are wrapped later, after the card's tooltip is set (UI.WrapHover), so neither replaces the other
    return function() hot:Show(); rim:Show() end, function() hot:Hide(); rim:Hide() end
end

local function MakeCard(key, art, title, desc, target)
    local c = CreateFrame("Button", nil, page)
    UI.Panel(c, "card")
    c.hoverOn, c.hoverOff = CardHover(c)
    c.art = c:CreateTexture(nil, "ARTWORK")
    c.art:SetSize(ART, ART)
    c.art:SetPoint("TOPLEFT", 14, -16)
    UI.Art(c.art, art, ART)
    c.title = UI.Text(c, 22, K.text, "serif")
    c.title:SetPoint("TOPLEFT", TEXT_X, -13)
    c.title:SetText(title)
    -- the way in: a small painted button with a chevron (the whole card is the button; this one does the same)
    c.go = UI.Button(c, "", 28, "secondary", function() UI.Go(c.target) end, 28)
    c.go:SetPoint("TOPRIGHT", -14, -14)
    c.chevron = UI.Chevron(c.go, 22)
    c.chevron:SetPoint("CENTER", 1, 1)
    c.desc = UI.Text(c, 13, K.textDim)
    c.desc:SetPoint("TOPLEFT", TEXT_X, -44)
    c.desc:SetWidth(232)
    c.desc:SetHeight(36)
    c.desc:SetWordWrap(true)
    c.desc:SetText(desc)
    c.rule = UI.Rule(c, 0.5)
    c.rule:SetPoint("TOPLEFT", TEXT_X, -84); c.rule:SetPoint("TOPRIGHT", -16, -84)
    c.target = target
    c:SetScript("OnClick", function(self) UI.Go(self.target) end)
    cards[key] = c
    return c
end

-- the big number of a card and what it counts; `side` is a quiet note at the right of the same line
local function AddStat(c)
    c.stat = UI.Text(c, 28, K.bronzeText, "serif")
    c.stat:SetPoint("TOPLEFT", TEXT_X, -90)
    c.statLabel = UI.Text(c, 14, K.textDim)
    c.statLabel:SetPoint("BOTTOMLEFT", c.stat, "BOTTOMRIGHT", 8, 4)
    c.side = UI.Text(c, 12, K.stone)
    c.side:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, -104)
    c.side:SetJustifyH("RIGHT")
end

-- two fact lines under the stat: a small picture (a guide status icon, or a plain dot) and a line of text
local function AddFacts(c, count, top)
    c.facts = {}
    for i = 1, count do
        local fy = top - (i - 1) * 22
        local icon = c:CreateTexture(nil, "ARTWORK")
        icon:SetSize(15, 15)
        icon:SetPoint("TOPLEFT", TEXT_X, fy - 1)
        local text = UI.Text(c, 13, K.text)
        text:SetPoint("TOPLEFT", TEXT_X + 21, fy)
        text:SetPoint("RIGHT", -16, 0)
        c.facts[i] = { icon = icon, text = text }
    end
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
                f.icon:SetSize(15, 15)
            else
                f.icon:SetColorTexture(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 0.85)
                f.icon:SetSize(5, 5)
            end
            f.icon:Show()
        else
            f.text:SetText("")
            f.icon:Hide()
        end
    end
end

local function SetStat(c, value, label, side)
    c.stat:SetText(value or "")
    c.statLabel:SetText(label or "")
    c.side:SetText(side or "")
end

local function BuildProfRows(c)
    c.facts = {}
    for i = 1, PROF_ROWS do
        local row = CreateFrame("Frame", nil, c)
        row:SetHeight(PROF_MIN)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.bar = UI.Meter(row, 104, 10)
        row.bar:SetPoint("RIGHT", 0, 0)
        row.value = UI.Text(row, 13, K.text)
        row.value:SetWidth(62)
        row.value:SetPoint("RIGHT", row.bar, "LEFT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        row.text = UI.Text(row, 13, K.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
        c.facts[i] = row
    end
    c.more = UI.Text(c, 12, K.stone)
    c.availH = 70
end

-- Places the professions list inside what the card has left under its heading, measured (never clipped): the row pitch is what the room allows
-- between PROF_MIN and PROF_MAX, and when the rooms holds fewer rows than there are professions the list shows what fits and says how many
-- more there are. Returns how many rows are shown.
local function PlaceProfs(c, total)
    local room = c.availH or 70
    local fit = math.max(1, math.floor(room / PROF_MIN))
    local shown = math.min(total, PROF_ROWS, fit)
    if shown < total then   -- one line of the room goes to "and N more"
        shown = math.max(1, math.min(shown, math.floor((room - 14) / PROF_MIN)))
    end
    local pitch = math.max(PROF_MIN, math.min(PROF_MAX, math.floor((room - (shown < total and 14 or 0)) / math.max(1, shown))))
    for i, row in ipairs(c.facts) do
        row:ClearAllPoints()
        local y = -PROF_TOP - (i - 1) * pitch
        row:SetPoint("TOPLEFT", c, "TOPLEFT", TEXT_X, y)
        row:SetPoint("TOPRIGHT", c, "TOPRIGHT", -16, y)
        row:SetHeight(pitch)
    end
    c.more:ClearAllPoints()
    c.more:SetPoint("TOPLEFT", c, "TOPLEFT", TEXT_X, -PROF_TOP - shown * pitch + 2)
    c.pitch, c.shown = pitch, shown
    return shown
end

local function Build(p)
    page, K = p, UI.K
    MakeCard("market", "auctionHouse", "Market prices", "Auction House data and price history for buying, crafting and selling.", "opps")
    MakeCard("opps", "diagOperations", "Best opportunities", "Profitable crafts based on current prices, costs and your professions.", "opps")
    MakeCard("plan", "reviewChanges", "Your crafting plan", "Queued crafts, material needs and what to make next.", "craft")
    MakeCard("profs", "journeyChronicle", "Profession progress", "Your current skills, so you know what to level next.", "craft")
    AddStat(cards.market); AddFacts(cards.market, 2, -128)
    AddStat(cards.opps); AddFacts(cards.opps, 2, -128)
    AddStat(cards.plan); AddFacts(cards.plan, 2, -128)
    BuildProfRows(cards.profs)
    page.cards = cards
    UI.TipFn(cards.market, "Market prices", function()
        local src = S.PriceSource()
        local m = src.market
        if not m then return "No auction prices are saved for this realm yet. Open the auction house and choose Scan prices." end
        local info = MK.Info({ market = m })
        local lines = { (src.label or "the auction house"):gsub("^%l", string.upper) }
        local age = PR.Age(m.at)
        lines[#lines + 1] = "Scanned " .. PR.AgeText(age) .. (age and age > PR.OLD_AFTER and " (old)" or "")
        lines[#lines + 1] = info and info.complete and "A complete scan." or "Some listings may be missing from this scan."
        return table.concat(lines, "\n")
    end)
    UI.TipFn(cards.profs, "Profession progress", function()
        local list = S.Skills()
        if not list then return "This game version doesn't give TwichUI your profession skill, so no levels are shown." end
        if #list == 0 then return "This character has no professions." end
        local lines = {}
        for _, s in ipairs(list) do
            lines[#lines + 1] = s.rank and ("%s: %d / %d"):format(s.name, s.rank, s.max) or (s.name .. ": skill not available")
        end
        return table.concat(lines, "\n")
    end)

    for _, c in pairs(cards) do UI.WrapHover(c, c.hoverOn, c.hoverOff) end   -- after the tooltips above: wraps them, never replaces them

    -- the cards are laid out for the page's real size once the game has measured it: two columns, and the height the bottom panel leaves
    local function Layout(width, height)
        local cw = math.floor((width - GAP) / 2)
        local ch = math.max(150, math.floor((height + TOP - BOTTOM_H - 2 * GAP) / 2))
        for _, c in pairs(cards) do c.desc:SetWidth(cw - TEXT_X - 52) end
        cards.market:ClearAllPoints(); cards.market:SetPoint("TOPLEFT", 0, TOP); cards.market:SetSize(cw, ch)
        cards.opps:ClearAllPoints(); cards.opps:SetPoint("TOPLEFT", cw + GAP, TOP); cards.opps:SetSize(cw, ch)
        cards.plan:ClearAllPoints(); cards.plan:SetPoint("TOPLEFT", 0, TOP - ch - GAP); cards.plan:SetSize(cw, ch)
        cards.profs:ClearAllPoints(); cards.profs:SetPoint("TOPLEFT", cw + GAP, TOP - ch - GAP); cards.profs:SetSize(cw, ch)
        cards.profs.availH = ch - PROF_TOP - PROF_BOTTOM   -- the room the professions list has: the card's height under its heading and rule
        cards.profs.cardH = ch
        if cards.profs.count then PlaceProfs(cards.profs, cards.profs.count) end
    end
    Layout(820, 555)
    page.PlaceProfs = PlaceProfs
    page:HookScript("OnSizeChanged", function(_, width, height)
        if width and height and width >= 100 and height >= 300 then Layout(width, height) end
    end)

    -- recent activity and the quick actions
    local n = CreateFrame("Frame", nil, page)
    n:SetPoint("BOTTOMLEFT", 0, 0)
    n:SetPoint("BOTTOMRIGHT", 0, 0)
    n:SetHeight(BOTTOM_H)
    UI.Panel(n, "editor")
    page.bottom = n
    local split = 0.42
    local art = n:CreateTexture(nil, "ARTWORK")
    art:SetSize(26, 26)
    art:SetPoint("TOPLEFT", 14, -9)
    UI.Art(art, "reminders", 26)
    local title = UI.Text(n, 18, K.text, "serif")
    title:SetPoint("LEFT", art, "RIGHT", 8, 0)
    title:SetText("Recent activity")
    page.activity = {}
    for i = 1, 3 do
        local y = -42 - (i - 1) * 23
        local line = CreateFrame("Frame", nil, n)
        line:SetHeight(22)
        line:SetPoint("TOPLEFT", 14, y)
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(14, 14)
        line.icon:SetPoint("LEFT", 0, 0)
        line.age = UI.Text(line, 12, K.stone)
        line.age:SetWidth(56)
        line.age:SetPoint("RIGHT", 0, 0)
        line.age:SetJustifyH("RIGHT")
        line.text = UI.Text(line, 12, K.text)
        line.text:SetPoint("LEFT", line.icon, "RIGHT", 8, 0)
        line.text:SetPoint("RIGHT", line.age, "LEFT", -8, 0)
        page.activity[i] = line
    end
    n.empty = UI.Text(n, 13, K.stone)
    n.empty:SetPoint("TOPLEFT", 16, -44)
    n.empty:SetWidth(330)
    n.empty:SetWordWrap(true)
    n.empty:SetJustifyV("TOP")
    n.empty:SetText("Nothing yet this session. Scans and changes to your plan appear here.")
    local rule = UI.Rule(n, 0.6)
    rule:SetWidth(1)
    rule:ClearAllPoints()
    rule:SetPoint("TOP", n, "TOPLEFT", 0, -12)
    rule:SetPoint("BOTTOM", n, "BOTTOMLEFT", 0, 12)
    n.actionsBox = CreateFrame("Frame", nil, n)
    n.actionsBox:SetPoint("TOPLEFT", 14, -42)
    n.actionsBox:SetPoint("BOTTOMRIGHT", -14, 12)
    local atitle = UI.Text(n, 18, K.text, "serif")
    atitle:SetText("Quick actions")
    n.atitle = atitle
    local function Action(key, label, art, target, tip, fn)
        local b = UI.ArtButton(n.actionsBox, label, art, 120, "secondary", fn or function() UI.Go(target) end, 44)
        UI.Tip(b, label, tip)
        actions[key] = b
        return b
    end
    Action("scan", "Scan prices", "diagOverview", nil,
        "Reads every listing at the open auction house once, so your crafts can be priced. It only reads, starts only when you press this, and needs the auction house open.",
        function() S.StartScan(); UI.Redraw() end)
    Action("plan", "Crafting plan", "npc:hammer", "craft", "Your craft queue and the materials it needs.")
    Action("shop", "Shopping list", "npc:reagent-pouch", "shop", "What your queue still needs, and where to get it.")
    local function Place(w)
        local left = math.floor(w * split)
        local aw = w - left - 28
        local bw = math.floor((aw - 2 * 8) / 3)
        local x = 0
        for _, key in ipairs({ "scan", "plan", "shop" }) do
            local b = actions[key]
            b:ClearAllPoints(); b:SetPoint("TOPLEFT", n.actionsBox, "TOPLEFT", x, 0); b:SetSize(bw, 44)
            x = x + bw + 8
        end
        n.atitle:ClearAllPoints(); n.atitle:SetPoint("TOPLEFT", left + 16, -12)
        n.actionsBox:ClearAllPoints()
        n.actionsBox:SetPoint("TOPLEFT", left + 14, -42)
        n.actionsBox:SetPoint("BOTTOMRIGHT", -14, 12)
        rule:ClearAllPoints()
        rule:SetPoint("TOP", n, "TOPLEFT", left, -12)
        rule:SetPoint("BOTTOM", n, "BOTTOMLEFT", left, 12)
        for _, line in ipairs(page.activity) do line:SetWidth(left - 28) end
        n.empty:SetWidth(left - 32)
    end
    Place(820)
    n:HookScript("OnSizeChanged", function(_, w) if w and w >= 200 then Place(w) end end)
    page.actions = actions
    page.next = n
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function PlanFacts(sum, queue)
    local toGet = sum.shortItems or 0
    local first, second
    if sum.state == "empty" then
        first = { "No materials needed", nil, "textDim" }
    elseif sum.state == "ready" then
        first = { "Ready to craft: materials in your bags", "done", "sage" }
    elseif sum.state == "collect" then
        first = { ("Collect %d from storage"):format((sum.bankItems or 0) + (sum.guildItems or 0)), "current", "bronzeText" }
    elseif sum.state == "short" then
        first = { ("%d %s still needed"):format(toGet, UI.Plural(toGet, "material", "materials")), "current", "bronzeText" }
    else
        first = { "Some counts can't be read yet", "current", "bronzeText" }
    end
    if sum.state ~= "empty" then
        second = { toGet > 0 and ("%d %s on your shopping list"):format(toGet, UI.Plural(toGet, "material", "materials")) or "Nothing to buy",
            nil, toGet > 0 and "text" or "textDim" }
    else
        second = { #queue == 0 and "Add recipes to get started" or "", nil, "stone" }
    end
    return { first, second }
end

local function RenderProfessions()
    local c = cards.profs
    local list, why = S.Skills()
    local rows = {}
    if list == nil then
        -- no skill from the game: the professions the Workshop has read, drawn as unavailable (never as zero)
        for _, pr in ipairs(S.Professions()) do rows[#rows + 1] = { name = pr.name, unavailable = true } end
    else
        rows = list
    end
    c.count = #rows
    local shown = PlaceProfs(c, math.max(1, #rows))
    for i, row in ipairs(c.facts) do
        local d = rows[i]
        if d and i <= shown then
            row:Show()
            row.text:SetText(d.name)
            local icon = d.icon
            row.icon:SetTexture(icon or UI.ICON_BLANK)
            row.icon:Show()
            if d.rank and d.max and d.max > 0 then
                row.value:SetText(("%d / %d"):format(d.rank, d.max))
                row.bar:SetFraction(d.rank / d.max)
                row.bar:SetTone(d.rank >= d.max and K.tealHi or K.sage)
                UI.Paint(row.value, K.text)
            else
                row.value:SetText("n/a")
                UI.Paint(row.value, K.stone)
                row.bar:SetFraction(0)
            end
            row.bar:Show()
        else
            row:Hide()
        end
    end
    if #rows == 0 then
        c.facts[1]:Show()
        c.facts[1].text:SetText(list == nil and "Open a profession window to add it here." or "No professions learned yet.")
        c.facts[1].icon:Hide()
        c.facts[1].value:SetText(""); c.facts[1].bar:SetFraction(0); c.facts[1].bar:Hide()
        UI.Paint(c.facts[1].text, K.textDim)
    else
        UI.Paint(c.facts[1].text, K.text)
    end
    c.more:SetText(#rows > shown and ("and %d more"):format(#rows - shown) or "")
end

local function RenderActivity(market, info)
    local list = S.Activity(3)
    local sawScan = false
    for _, a in ipairs(list) do if a.scan then sawScan = true end end
    -- the saved scan is real too: when this session recorded none, say what the saved market holds
    if not sawScan and market and market.at then
        local items = info and info.items or market.n
        local text = (info and info.complete) and ("Auction house scan completed (%s items)"):format(UI.Num(items or 0))
            or ("Auction house scan saved, not complete (%s items)"):format(UI.Num(items or 0))
        list[#list + 1] = { at = market.at, text = text, tone = (info and info.complete) and "done" or "current" }
        table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
        while #list > 3 do list[#list] = nil end
    end
    for i, line in ipairs(page.activity) do
        local a = list[i]
        if a then
            line:Show()
            line.text:SetText(a.text)
            line.age:SetText(UI.Ago(a.at))
            UI.Status(line.icon, a.tone == "failed" and "failed" or (a.tone == "current" and "current" or "done"), 14)
            UI.Paint(line.text, K.text)
        else
            line:Hide()
        end
    end
    page.next.empty:SetShown(#list == 0)
end

local function Render()
    local Plural = UI.Plural
    local src = S.PriceSource()
    local market = src.market
    local info = market and MK.Info({ market = market }) or nil
    local v = S.Opportunities()
    local queue = S.QueueRows()
    local _, sum = S.Materials()

    -- market prices: the scan, how many items it priced, how old it is, which market
    local age = market and PR.Age(market.at) or nil
    local mf = {}
    if market then
        SetStat(cards.market, UI.Num(info and info.items or 0), Plural(info and info.items or 0, "item priced", "items priced"),
            (info and (info.scans or 0) > 0) and ("%d %s of history"):format(info.scans, Plural(info.scans, "day", "days")) or nil)
    else
        SetStat(cards.market, "\226\128\148", "no prices yet", nil)
    end
    if SC.Busy() then
        mf[1] = { ("Scanning: %d%%"):format(math.floor((SC.Progress() or 0) * 100 + 0.5)), "current", "bronzeText" }
    elseif market then
        local when = age and PR.AgeText(age) or "at an unknown time"
        local old = age and age > PR.OLD_AFTER
        -- a scan that was collected is not necessarily the whole house: "complete" is said only when the scan was
        if info and info.complete then
            mf[1] = { "Scan complete \194\183 " .. when .. (old and " (old)" or ""), old and "current" or "done", old and "bronzeText" or "text" }
        else
            mf[1] = { "Partial scan \194\183 " .. when .. (old and " (old)" or ""), "current", "bronzeText" }
        end
    else
        mf[1] = { "No scan yet", "current", "bronzeText" }
    end
    -- the market's name is not repeated here (the footer chip's tooltip and this card's tooltip hold it); what the scan covered is the fact
    if not market then mf[2] = { "Scan at the auction house", nil, "textDim" }
    elseif market.scope ~= "full" then mf[2] = { "Recipe items only (an older scan)", nil, "textDim" }
    elseif info and info.complete then mf[2] = { "Covers every listed item", nil, "textDim" }
    else mf[2] = { "Some listings may be missing", nil, "bronzeText" } end
    SetFacts(cards.market, mf)

    -- best opportunities (the best by estimated profit, over every known recipe, whatever the Opportunities page's filters)
    local of, s = {}, v.summary
    local best = market and Op.Select(v.all, Op.DEFAULTS)[1] or nil
    if s.total == 0 then
        SetStat(cards.opps, "\226\128\148", "no recipes read yet", nil)
        of[1] = { "Open one of your professions to add its recipes", "current", "bronzeText" }
    elseif not market then
        SetStat(cards.opps, UI.Num(s.total), Plural(s.total, "known recipe", "known recipes"), nil)
        of[1] = { "Not priced yet", "current", "bronzeText" }
        of[2] = { "Profits appear after a price scan", nil, "textDim" }
    else
        SetStat(cards.opps, UI.Num(s.profitable), Plural(s.profitable, "profitable craft", "profitable crafts"),
            ("of %s priced"):format(UI.Num(s.priced)))
        if best and best.est.state == "ok" and best.est.profitLow > 0 then
            of[1] = { "Top profit: " .. UI.Shorten(best.rec.name, 30), "done", "text" }
            of[2] = { ("%s each, %s"):format(UI.Money(best.est.profitLow), best.est.cutRate and "after the cut" or "before fees"), nil, "sage" }
        else
            of[1] = { "Nothing profitable at these prices", nil, "textDim" }
        end
    end
    SetFacts(cards.opps, of)

    -- the crafting plan
    SetStat(cards.plan, tostring(#queue), ("of %d queued"):format(W.MAX_QUEUE), nil)
    SetFacts(cards.plan, PlanFacts(sum, queue))

    RenderProfessions()
    RenderActivity(market, info)
    actions.scan.text:SetText(SC.Busy() and "Scanning..." or "Scan prices")
    actions.scan:SetEnabled(not SC.Busy())
end

UI.Register({
    key = "overview", nav = "Overview", icon = "home",
    title = "Overview", sub = "Your command center for crafting, markets and making gold.",
    tip = "Where your prices, opportunities, queue and professions stand, and what to do next.",
    Build = Build, Render = Render,
})
