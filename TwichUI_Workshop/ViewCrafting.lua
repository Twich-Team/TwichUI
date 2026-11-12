-- TwichUI Workshop: the Crafting page (the workbench)
-- Recipes on the left (the player's own open profession, or the one remembered from last time, with a search and a button per profession
-- seen), the queue on the right with the chosen craft's details beside it, and under them the combined materials against the bags, the bank
-- and (if chosen) the guild bank. It draws what Session.lua says and asks it to do everything else; it never crafts, buys or sends.
-- Colour is always beside a word (Orange/Yellow/Green/Grey, "Still needed", "Unknown").

local R = TwichUI
local W = R.Workshop
local S, O, PR, K2 = W.Session, W.Observe, W.Prices, W.Stock
local UI = W.UI

local LEFT_W, QUEUE_W, TOP_H = 276, 318, 222
local DETAIL_NAME_W = 132   -- the chosen craft's name beside its picture (the details card is what is left of the page: about 200 units)
local REC_H, QUE_H, MAT_H = 40, 56, 24
local MC_SHORT, MC_STORED, MC_HAVE, MC_NEED, MC_GAP = 78, 56, 52, 44, 6
local USE_GUILD_TIP = "Plans with materials remembered from your guild bank that your guild rank may be able to take. It never withdraws anything. "
    .. "Guild stock is shared with other members, so what was seen may be gone, and a daily limit may apply. Off unless you turn it on."
UI.USE_GUILD_TIP = USE_GUILD_TIP

local K
local page, f
local chips = {}
local matView      -- the stock view the materials list was last drawn with (the row tooltips read it)
local selected     -- the queued recipe whose details are shown (memory only)

local function Num(n) return tostring(n) end
local function CL_Font(fs, size) R.CraftLook.Font(fs, size) end
local function AgeOf(at)
    local age = PR.Age(at)
    return age and PR.AgeText(age) or "at an unknown time"
end
UI.AgeOf = AgeOf

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function MakeRecipeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.25)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconFrame = UI.ItemIcon(row, 28)
    row.iconFrame:SetPoint("LEFT", 6, 0)
    row.icon = row.iconFrame.tex
    row.add = UI.Button(row, "Add", 58, "secondary", function()
        local rec = row.rec
        if rec then S.Add(rec); UI.Redraw() end
    end, 24)
    CL_Font(row.add.text, 12)
    row.add:SetPoint("RIGHT", -4, 0)
    UI.Tip(row.add, "Add to queue", "Puts this recipe in the queue to make once. Change how many in the queue.")
    row.name = UI.Text(row, 14, K.text)
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 8, 1)
    row.name:SetPoint("RIGHT", row.add, "LEFT", -6, 0)
    row.diff = UI.Text(row, 12, K.textDim)
    row.diff:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 8, -1)
    row.sub = UI.Text(row, 12, K.stone)
    row.sub:SetPoint("LEFT", row.diff, "RIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", row.add, "LEFT", -6, 0)
    -- the whole name (and what the craft makes) on hover: the column is narrow
    row:SetScript("OnEnter", function(self)
        local rec = self.rec
        if not (GameTooltip and rec) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (rec.outItem and pcall(GameTooltip.SetItemByID, GameTooltip, rec.outItem)) then
            GameTooltip:ClearLines()
            GameTooltip:AddLine(rec.name, 1, 0.82, 0)
            local per = W.PerCraft(rec.outMin, rec.outMax)
            GameTooltip:AddLine(per and ("Makes " .. per) or "What it makes isn't known yet.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, rec)
        self.rec = rec
        O.Fill(rec)
        self.icon:SetTexture(rec.icon or UI.ICON_BLANK)
        self.name:SetText(rec.name)
        local d = W.DIFFICULTY[rec.diff]
        if d then
            self.diff:SetText(d.word)
            UI.Paint(self.diff, d.color)
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
UI.QueueLine = QueueLine

local function MakeQueueRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.25)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconFrame = UI.ItemIcon(row, 32)
    row.iconFrame:SetPoint("TOPLEFT", 6, -8)
    row.icon = row.iconFrame.tex
    row.more = UI.Glyph(row, "+", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and 5 or 1); UI.Redraw() end
    end)
    row.more:SetPoint("TOPRIGHT", -4, -6)
    UI.Tip(row.more, "Make more", "One more craft. Hold Shift for five.")
    row.count = UI.Text(row, 15, K.text, "strong")
    row.count:SetWidth(30)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("RIGHT", row.more, "LEFT", -1, 0)
    row.less = UI.Glyph(row, "-", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and -5 or -1); UI.Redraw() end
    end)
    row.less:SetPoint("RIGHT", row.count, "LEFT", -1, 0)
    UI.Tip(row.less, "Make fewer", "One craft fewer, down to one. Hold Shift for five. Remove (in the details) takes the recipe out.")
    row.name = UI.Text(row, 14, K.text)
    row.name:SetPoint("TOPLEFT", 46, -9)
    row.name:SetPoint("RIGHT", row.less, "LEFT", -6, 0)
    row.line = UI.Text(row, 12, K.textDim)
    row.line:SetPoint("TOPLEFT", 46, -27)
    row.line:SetPoint("RIGHT", -8, 0)
    row.stale = UI.Text(row, 12, K.bronzeText)
    row.stale:SetPoint("TOPLEFT", 46, -41)
    row.stale:SetPoint("RIGHT", -6, 0)
    row.stale:SetText("Open profession to update.")
    row:SetScript("OnClick", function(self)
        if self.id then selected = self.id; UI.Redraw() end
    end)
    row.fill = function(self, r)
        local e = r.entry
        self.id = e.id
        self.icon:SetTexture(e.icon or UI.ICON_BLANK)
        self.name:SetText(e.name)
        self.line:SetText(QueueLine(r))
        self.count:SetText(Num(e.crafts))
        self.stale:SetShown(r.unresolved)
        self.less:SetEnabled(e.crafts > 1)
        self.more:SetEnabled(e.crafts < W.MAX_CRAFTS)
        self:SetSelected(e.id == selected)
    end
    return row
end

local function MakeMaterialRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    UI.Hover(row, 6)
    row.iconFrame = UI.ItemIcon(row, 18)
    row.iconFrame:SetPoint("LEFT", 6, 0)
    row.icon = row.iconFrame.tex
    local function Col(w, anchor, dx)
        local t = UI.Text(row, 13, K.text)
        t:SetWidth(w)
        t:SetJustifyH("RIGHT")
        if anchor then t:SetPoint("RIGHT", anchor, "LEFT", -dx, 0) else t:SetPoint("RIGHT", -8, 0) end
        return t
    end
    row.short = Col(MC_SHORT)
    row.stored = Col(MC_STORED, row.short, MC_GAP)
    row.have = Col(MC_HAVE, row.stored, MC_GAP)
    row.need = Col(MC_NEED, row.have, MC_GAP)
    row.name = UI.Text(row, 13, K.text)
    row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.need, "LEFT", -6, 0)
    row:SetScript("OnEnter", function(self)
        if GameTooltip and self.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then
                GameTooltip:Hide()
            else
                if self.made then
                    GameTooltip:AddLine(("%s%d will come from crafts in your queue, so they are not counted as still needed."):format(self.madeRange and "At least " or "", self.made), 0.8, 0.8, 0.8, true)
                end
                -- the bags, the bank and the guild bank apart, each with how long ago it was seen
                if matView and self.row then
                    GameTooltip:AddLine(" ")
                    for _, line in ipairs(K2.Lines(matView, self.item, self.row.have, AgeOf)) do
                        GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
                    end
                    local taken = (self.row.fromBank or 0) + (self.row.fromGuild or 0)
                    if taken > 0 then
                        GameTooltip:AddLine(("Collect %d from storage for this queue."):format(taken), 1, 0.82, 0.3, true)
                    end
                end
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, m)
        self.item, self.made, self.madeRange, self.row = m.item, m.made, m.madeRange, m
        local name, icon = O.ItemFacts(m.item)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.name:SetText(name or ("Item " .. m.item))
        self.need:SetText(Num(m.need))
        if m.have == nil then
            self.have:SetText("Unknown")
            self.stored:SetText("")
            self.short:SetText("Unknown")
            UI.Paint(self.short, K.stone)
        else
            self.have:SetText(Num(m.have))
            local stored = (m.fromBank or 0) + (m.fromGuild or 0)   -- the part of the need that storage covers: collect it
            self.stored:SetText(stored > 0 and Num(stored) or "-")
            UI.Paint(self.stored, stored > 0 and K.bronzeText or K.stone)
            self.short:SetText(Num(m.short))
            UI.Paint(self.short, m.short > 0 and K.bronzeText or K.sage)
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function LayoutChips(list)
    local n = #list
    local area = LEFT_W - 24
    for i = 1, math.max(n, #chips) do
        local b = chips[i]
        local p = list[i]
        if p then
            if not b then
                b = UI.Segment(page.recipes, "", 80, function(self)
                    if self.profId then S.Select(self.profId); UI.lists.recipes:ScrollTop(); UI.Redraw() end
                end)
                chips[i] = b
            end
            local w = math.max(56, math.floor((area - 4 * (n - 1)) / n))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", page.recipes, "TOPLEFT", 12 + (i - 1) * (w + 4), -44)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(p.selected)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function RenderDetail(queue)
    local d = page.detail
    local r
    for _, q in ipairs(queue) do if q.entry.id == selected then r = q end end
    if not r and queue[1] then r = queue[1]; selected = r.entry.id end
    if not r then
        selected = nil
        d.iconFrame:Hide(); d.name:SetText(""); d.prof:SetText(""); d.crafts:SetText(""); d.makes:SetText(""); d.state:SetText("")
        d.open:Hide(); d.remove:Hide()
        d.empty:SetText("Queued crafts appear here. Choose Add on a recipe to plan it.")
        d.empty:Show()
        return
    end
    local e = r.entry
    d.empty:Hide()
    d.iconFrame:Show()
    d.name:SetText(e.name)
    local w = math.max(120, (d:GetWidth() or 0) - 26)
    d.makes:SetWidth(w)
    d.state:SetWidth(w)
    d.icon:SetTexture(e.icon or UI.ICON_BLANK)
    d.prof:SetText(e.profName or "")
    d.crafts:SetText(e.crafts == 1 and "1 craft" or (e.crafts .. " crafts"))
    if r.perCraft then
        d.makes:SetText(e.crafts == 1 and ("Makes " .. r.perCraft) or ("Makes " .. r.perCraft .. " each, " .. r.expected .. " in all"))
    else
        d.makes:SetText("What it makes isn't known yet.")
    end
    if r.unresolved then
        d.state:SetText("Its materials aren't known. Open " .. (e.profName or "its profession") .. " to update.")
        UI.Paint(d.state, K.bronzeText)
    else
        d.state:SetText("")   -- known materials: they are in the list below; only a warning is worth the room here
    end
    d.open:Show(); d.remove:Show()
end

local function Render()
    -- recipes
    LayoutChips(S.Professions())
    f.notice:SetText(table.concat(S.Notices(), "\n"))
    local rows = S.Browse()
    local emptyText
    if #rows == 0 then
        if not S.Current() then emptyText = "No recipes yet."
        elseif S.filter ~= "" then emptyText = "No recipe matches your search."
        else emptyText = "This profession has no recipes to show." end
    end
    UI.lists.recipes:SetData(rows, emptyText)

    -- queue and the chosen craft
    local queue = S.QueueRows()
    f.queueCount:SetText(("%d of %d"):format(#queue, W.MAX_QUEUE))
    RenderDetail(queue)
    UI.lists.queue:SetData(queue, "Nothing queued yet. Use Add on a recipe.")

    -- materials
    local mats, sum, view = S.Materials()
    matView = view
    UI.lists.mats:SetData(mats, sum.state == "empty" and "Materials for the queue appear here." or nil)
    local text, tone = S.Headline(sum)
    f.headline:SetText(text)
    UI.Paint(f.headline, tone == "good" and K.sage or (tone == "warn" and K.bronzeText or K.textDim))
    f.storeNote:SetText(S.StockNote(sum, view) or "")
    f.scope:SetText(("Counts %s."):format(K2.Scope(view)))
    f.useGuild:SetOn(view.guild.enabled)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Card(x, y, w, h)
    local c = CreateFrame("Frame", nil, page)
    c:SetPoint("TOPLEFT", x, y)
    if w then c:SetWidth(w) end
    if h then c:SetHeight(h) end
    UI.Panel(c, "card")
    return c
end

local function Heading(parent, text)
    local h = UI.Text(parent, 18, K.text, "serif")
    h:SetPoint("TOPLEFT", 14, -12)
    h:SetText(text)
    return h
end

local function Build(p, frame)
    page, f, K = p, frame, UI.K
    local top = -62

    -- recipes
    local rc = Card(0, top, LEFT_W)
    rc:SetPoint("BOTTOMLEFT", 0, 0)
    page.recipes = rc
    Heading(rc, "Recipes")
    local box = UI.Search(rc, LEFT_W - 24, 28, "Search recipes")
    box:SetPoint("TOPLEFT", 12, -78)
    box:SetMaxLetters(40)
    box:HookScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
        S.SetFilter(self:GetText())
        UI.lists.recipes:ScrollTop()
        UI.Redraw()
    end)
    f.search = box
    f.notice = UI.Text(rc, 12, K.textDim)
    f.notice:SetPoint("TOPLEFT", 14, -112)
    f.notice:SetWidth(LEFT_W - 28)
    f.notice:SetWordWrap(true)
    f.notice:SetJustifyV("TOP")
    local recipes = UI.List(rc, REC_H, MakeRecipeRow, 300, false)
    recipes.box:SetPoint("TOPLEFT", 4, -146)
    recipes.box:SetPoint("BOTTOMRIGHT", -4, 6)
    UI.lists.recipes = recipes

    -- queue
    local qc = Card(LEFT_W + 12, top, QUEUE_W, TOP_H)
    Heading(qc, "Craft queue")
    f.queueCount = UI.Text(qc, 13, K.stone)
    f.queueCount:SetPoint("TOPRIGHT", -14, -17)
    local queue = UI.List(qc, QUE_H, MakeQueueRow, TOP_H - 46, false)
    queue.box:SetPoint("TOPLEFT", 4, -40)
    queue.box:SetPoint("BOTTOMRIGHT", -4, 4)
    UI.lists.queue = queue

    -- the chosen craft's details (Open recipe and Remove live here, so the queue rows stay readable)
    local d = Card(LEFT_W + 12 + QUEUE_W + 12, top, nil, TOP_H)
    d:SetPoint("TOPRIGHT", 0, top)
    page.detail = d
    d.iconFrame = UI.ItemIcon(d, 40)
    d.iconFrame:SetPoint("TOPLEFT", 14, -14)
    d.icon = d.iconFrame.tex
    d.name = UI.Text(d, 16, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 64, -14)
    d.name:SetWidth(DETAIL_NAME_W)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.prof = UI.Text(d, 12, K.stone)
    d.prof:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    -- the body hangs under the profession line, so a name of one line or two pushes it down (never under the picture)
    d.body = CreateFrame("Frame", nil, d)
    d.body:SetPoint("TOPLEFT", d.prof, "BOTTOMLEFT", -64, -8)
    d.body:SetPoint("BOTTOMRIGHT", 0, 76)
    d.crafts = UI.Text(d.body, 14, K.bronzeText, "strong")
    d.crafts:SetPoint("TOPLEFT", 14, 0)
    d.makes = UI.Text(d.body, 13, K.textDim)
    d.makes:SetPoint("TOPLEFT", 14, -20)
    d.makes:SetWordWrap(true)
    d.state = UI.Text(d.body, 12, K.textDim)
    d.state:SetPoint("TOPLEFT", d.makes, "BOTTOMLEFT", 0, -5)
    d.state:SetWordWrap(true)
    d.empty = UI.Text(d, 13, K.textDim)
    d.empty:SetPoint("TOPLEFT", 14, -16)
    d.empty:SetPoint("RIGHT", -12, 0)
    d.empty:SetWordWrap(true)
    d.open = UI.Button(d, "Open recipe", 90, "secondary", function()
        if selected then S.OpenRecipe(selected); UI.Redraw() end
    end)
    d.open:SetPoint("BOTTOMLEFT", 12, 44)
    d.open:SetPoint("BOTTOMRIGHT", -12, 44)
    UI.Tip(d.open, "Open recipe", "Shows this recipe in the game's profession window. It makes nothing.")
    d.remove = UI.Button(d, "Remove", 90, "secondary", function()
        if selected then S.Remove(selected); UI.Redraw() end
    end)
    d.remove:SetPoint("BOTTOMLEFT", 12, 12)
    d.remove:SetPoint("BOTTOMRIGHT", -12, 12)
    UI.Tip(d.remove, "Remove", "Takes this recipe out of the queue. Nothing else changes.")
    page.open, page.remove = d.open, d.remove

    -- materials
    local mc = Card(LEFT_W + 12, top - TOP_H - 12)
    mc:SetPoint("BOTTOMRIGHT", 0, 0)
    local mh = Heading(mc, "Materials")
    f.scope = UI.Text(mc, 12, K.stone)
    f.scope:SetPoint("BOTTOMLEFT", mh, "BOTTOMRIGHT", 10, 2)
    f.scope:SetText("Counts bags only.")
    f.useGuild = UI.Switch(mc, "Use guild bank", function()
        S.SetUseGuild(not S.UseGuild())
        UI.Redraw()
    end)
    f.useGuild:SetPoint("TOPRIGHT", -14, -14)
    UI.Tip(f.useGuild, "Use guild bank materials", USE_GUILD_TIP)
    local item = UI.Head(mc, "Material", 120, "LEFT")
    item:SetPoint("TOPLEFT", 14, -46)
    local x = -(4 + 16 + 8)   -- the rows' right edge: the list's inset, its scroll gutter and the columns' own margin
    local hs = UI.Head(mc, "Still needed", MC_SHORT); hs:SetPoint("TOPRIGHT", x, -46)
    local hst = UI.Head(mc, "Stored", MC_STORED); hst:SetPoint("RIGHT", hs, "LEFT", -MC_GAP, 0)
    local hb = UI.Head(mc, "In bags", MC_HAVE); hb:SetPoint("RIGHT", hst, "LEFT", -MC_GAP, 0)
    local hn = UI.Head(mc, "Need", MC_NEED); hn:SetPoint("RIGHT", hb, "LEFT", -MC_GAP, 0)
    local rule = UI.Rule(mc, 0.45)
    rule:SetPoint("TOPLEFT", 12, -64); rule:SetPoint("TOPRIGHT", -12, -64)
    local mats = UI.List(mc, MAT_H, MakeMaterialRow, 120, false)
    mats.box:SetPoint("TOPLEFT", 4, -66)
    mats.box:SetPoint("BOTTOMRIGHT", -4, 50)
    UI.lists.mats = mats
    local rule2 = UI.Rule(mc, 0.45)
    rule2:SetPoint("BOTTOMLEFT", 12, 48); rule2:SetPoint("BOTTOMRIGHT", -12, 48)
    f.headline = UI.Text(mc, 14, K.textDim)
    f.headline:SetPoint("BOTTOMLEFT", 14, 26)
    f.headline:SetPoint("RIGHT", -14, 0)
    f.storeNote = UI.Text(mc, 12, K.stone)   -- what has not been seen yet ("Open your bank with Workshop loaded to update.")
    f.storeNote:SetPoint("BOTTOMLEFT", 14, 10)
    f.storeNote:SetPoint("RIGHT", -14, 0)
end

UI.Register({
    key = "craft", nav = "Crafting", icon = "npc:hammer",
    title = "Crafting", sub = "Queue your crafts, see what they need, and gather it.",
    tip = "Your recipes, the craft queue and the materials it needs, against your bags and storage.",
    Build = Build, Render = Render,
    Reset = function() matView = nil end,
})
