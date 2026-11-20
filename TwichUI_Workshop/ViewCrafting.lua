-- TwichUI Workshop: the Crafting page (the crafting plan)
-- The queue is the centre of the page: the crafts the player means to make, the chosen craft in a large panel (what it makes, what it may cost
-- and earn, Open recipe and Remove), and under it the combined materials against the bags, the bank and (if chosen) the guild bank. A plan
-- bar at the foot adds the queue up and leads to Shopping. The player's own recipes are a second list in the same left card (Craft queue /
-- Recipes), so browsing never takes the workspace away. It draws what Session.lua says and asks it to do everything else; it never crafts,
-- buys or sends. Colour is always beside a word (Orange/Yellow/Green/Grey, "Still needed", "Unknown").
-- P2: above the materials a Crafting Strategy strip says what the multilevel planner would do for the WHOLE queue (one plan over the combined
-- demand, never a sum of per-recipe plans): its status, craft / buy / collect counts, the economic cost, the cash needed now and the savings,
-- with View strategy; each material row carries one line on how the plan gets it. The estimates in the boxes and the bar are unchanged.

local R = TwichUI
local W = R.Workshop
local S, O, PR, K2 = W.Session, W.Observe, W.Prices, W.Stock
local Sg = W.Strategy
local UI = W.UI

local LEFT_W, PANEL_H, BAR_H, GAP = 350, 126, 56, 10
local TOP = -66
local REC_H, QUE_H, MAT_H = 48, 66, 32   -- (a material row holds its name and, under it, the plan's one line)
local STRIP_H = 40      -- the Crafting Strategy strip above the materials
local STRIP_SHIFT = STRIP_H + 6
local MC_SHORT, MC_STORED, MC_HAVE, MC_NEED, MC_GAP = 84, 58, 56, 46, 4
local USE_GUILD_TIP = "Plan with what your guild bank was last seen to hold. Nothing is withdrawn.\nShared stock: it may be gone, and a daily limit may apply."
UI.USE_GUILD_TIP = USE_GUILD_TIP

local K
local page, f
local chips = {}
local matView      -- the stock view the materials list was last drawn with (the row tooltips read it)
local selected     -- the queued recipe whose details are shown (memory only)
local leftMode     -- "queue" or "recipes": which list the left card shows (nil until the page first draws: recipes when the queue is empty)

local function Num(n) return tostring(n) end
local function AgeOf(at)
    local age = PR.Age(at)
    return age and PR.AgeText(age) or "at an unknown time"
end
UI.AgeOf = AgeOf

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local ACT_W = 70   -- the width of a recipe row's action: every state of it (Add, Queued, Full) is drawn inside it

local function MakeRecipeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.2)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconFrame = UI.ItemIcon(row, 32)
    row.iconFrame:SetPoint("LEFT", 8, 0)
    row.icon = row.iconFrame.tex
    row.add = UI.ArtButton(row, "Add", "plus", ACT_W, "secondary", function()
        local rec = row.rec
        if rec then S.Add(rec); UI.Redraw() end
    end, 26)
    row.add:SetPoint("RIGHT", -6, 0)
    UI.Tip(row.add, "Add to queue", "Puts this recipe in the queue to make once. Change how many in the queue.")
    -- the other states of the action are a compact mark of the same width (a check and "Queued", or "Full"), never a stretched button: the
    -- text is drawn inside this box, and the box is the button's own place
    local mark = CreateFrame("Frame", nil, row)
    mark:SetSize(ACT_W, 26)
    mark:SetPoint("RIGHT", -6, 0)
    mark:EnableMouse(true)
    mark.icon = mark:CreateTexture(nil, "ARTWORK")
    mark.icon:SetSize(12, 12)
    mark.icon:SetPoint("LEFT", 4, 0)
    UI.Status(mark.icon, "done", 12)
    mark.text = UI.Text(mark, 12, K.sage, "strong")
    mark.text:SetPoint("LEFT", mark.icon, "RIGHT", 3, 0)
    mark.text:SetPoint("RIGHT", -2, 0)
    mark:Hide()
    row.mark = mark
    UI.TipFn(mark, "Recipe in the queue", function(self) return self.why end)
    row.name = UI.Text(row, 14, K.text, "strong")
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 9, 1)
    row.name:SetPoint("RIGHT", row.add, "LEFT", -6, 0)
    row.diff = UI.Text(row, 12, K.textDim)
    row.diff:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 9, -1)
    row.sub = UI.Text(row, 12, K.stone)
    row.sub:SetPoint("LEFT", row.diff, "RIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", row.add, "LEFT", -6, 0)
    -- the whole name (and what the craft makes) on hover: the column is narrow
    row.TipEnter = function(self)
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
    end
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
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
        local queued = S.IsQueued(rec.id)
        local full = not queued and W.Queue.Count() >= W.MAX_QUEUE
        self.add:SetEnabled(not (queued or full))   -- a hidden button is not a live one either
        self.add:SetShown(not (queued or full))
        self.mark:SetShown(queued or full)
        if queued then
            self.mark.icon:Show()
            self.mark.text:ClearAllPoints()
            self.mark.text:SetPoint("LEFT", self.mark.icon, "RIGHT", 3, 0)
            self.mark.text:SetPoint("RIGHT", -2, 0)
            self.mark.text:SetText("Queued")
            UI.Paint(self.mark.text, K.sage)
            self.mark.why = "This recipe is in your queue. Change how many in the queue."
        elseif full then
            self.mark.icon:Hide()
            self.mark.text:ClearAllPoints()
            self.mark.text:SetPoint("LEFT", 8, 0)
            self.mark.text:SetPoint("RIGHT", -2, 0)
            self.mark.text:SetText("Full")
            UI.Paint(self.mark.text, K.bronzeText)
            self.mark.why = ("The queue holds %d recipes and is full. Remove one to add another."):format(W.MAX_QUEUE)
        end
    end
    row:Follow(row.add)
    row:Follow(mark)
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

-- The tooltip of a queued craft: the recipe, how many crafts, what they make, and what is not known (the item's own tooltip, when its icon is
-- hovered and the output item is known, is the game's: nothing is made up around it)
local function QueueTip(row)
    local e = row.entry
    if not (GameTooltip and e) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Crafts queued", tostring(e.crafts), 0.8, 0.8, 0.8, 1, 1, 1)
    local r = row.qrow
    if r and r.perCraft then
        GameTooltip:AddDoubleLine("Makes", e.crafts == 1 and r.perCraft or (r.perCraft .. " each, " .. r.expected .. " in all"), 0.8, 0.8, 0.8, 1, 1, 1)
    else
        GameTooltip:AddLine("What it makes isn't known yet.", 0.8, 0.8, 0.8, true)
    end
    if r and r.unresolved then
        GameTooltip:AddLine("Its materials aren't known: open " .. (e.profName or "its profession") .. " to update.", 1, 0.82, 0.3, true)
    end
    GameTooltip:AddLine("Click to choose it.", 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

local function MakeQueueRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.2)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    -- the picture is a button: the item's own tooltip (when the output item is known) and Shift-click for its chat link
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(42, 42)
    row.iconBtn:SetPoint("LEFT", 10, 0)
    row.iconFrame = UI.ItemIcon(row.iconBtn, 42)
    row.iconFrame:SetAllPoints()
    row.icon = row.iconFrame.tex
    row.iconBtn:SetScript("OnEnter", function(self)
        local item = row.entry and row.entry.outItem
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not (item and pcall(GameTooltip.SetItemByID, GameTooltip, item)) then
            GameTooltip:Hide()
            QueueTip(row)   -- no output item known: the queue's own tooltip, so the picture never shows nothing
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.iconBtn:SetScript("OnClick", function()
        local item = row.entry and row.entry.outItem
        if item and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then
            local ok, _, link = pcall(C_Item.GetItemInfo, item)
            if ok and type(link) == "string" then pcall(ChatEdit_InsertLink, link) end
            return
        end
        local click = row:GetScript("OnClick")
        if click then click(row) end
    end)
    row.more = UI.Glyph(row, "+", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and 5 or 1); UI.Redraw() end
    end, 24)
    row.more:SetPoint("TOPRIGHT", -8, -7)
    UI.Tip(row.more, "Make more", "One more craft. Hold Shift for five.")
    row.count = UI.Text(row, 16, K.text, "strong")
    row.count:SetWidth(30)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("RIGHT", row.more, "LEFT", -1, 0)
    row.less = UI.Glyph(row, "-", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and -5 or -1); UI.Redraw() end
    end, 24)
    row.less:SetPoint("RIGHT", row.count, "LEFT", -1, 0)
    UI.Tip(row.less, "Make fewer", "One craft fewer, down to one. Hold Shift for five. Remove (in the details) takes the recipe out.")
    -- the name has the first line to itself up to the controls; what it makes and the warning run the full width beneath
    row.name = UI.Text(row, 14, K.text, "strong")
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 9, 2)
    row.name:SetPoint("RIGHT", row.less, "LEFT", -6, 0)
    row.line = UI.Text(row, 12, K.textDim)
    row.line:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 9, -22)
    row.line:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.stale = UI.Text(row, 12, K.bronzeText)
    row.stale:SetPoint("TOPLEFT", row.line, "BOTTOMLEFT", 0, -2)
    row.stale:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.stale:SetText("Open profession to update.")
    row:SetScript("OnClick", function(self)
        if self.id then selected = self.id; UI.Redraw() end
    end)
    row.TipEnter = QueueTip
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row.fill = function(self, r)
        local e = r.entry
        self.id, self.entry, self.qrow = e.id, e, r
        self.icon:SetTexture(e.icon or UI.ICON_BLANK)
        self.name:SetText(e.name)
        self.line:SetText(QueueLine(r))
        self.count:SetText(Num(e.crafts))
        self.stale:SetShown(r.unresolved)
        self.less:SetEnabled(e.crafts > 1)
        self.more:SetEnabled(e.crafts < W.MAX_CRAFTS)
        self:SetSelected(e.id == selected)
    end
    row:Follow(row.iconBtn)   -- last: after the pieces' own tooltips are set
    row:Follow(row.more)
    row:Follow(row.less)
    return row
end

-- A material of the queue: icon, name, and what is needed against what is held. A planner that knows how a material can be made may give the
-- row `note` (one short line, e.g. what it is made from); the row then shows it under the name. Nothing about recipes is assumed here.
local function MakeMaterialRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    UI.Hover(row, 6)
    row.iconFrame = UI.ItemIcon(row, 24)
    row.iconFrame:SetPoint("LEFT", 8, 0)
    row.icon = row.iconFrame.tex
    local function Col(w, anchor, dx)
        local t = UI.Text(row, 14, K.text, "strong")
        t:SetWidth(w)
        t:SetJustifyH("RIGHT")
        if anchor then t:SetPoint("RIGHT", anchor, "LEFT", -dx, 0) else t:SetPoint("RIGHT", -8, 0) end
        return t
    end
    row.short = Col(MC_SHORT)
    row.stored = Col(MC_STORED, row.short, MC_GAP)
    row.have = Col(MC_HAVE, row.stored, MC_GAP)
    row.need = Col(MC_NEED, row.have, MC_GAP)
    row.name = UI.Text(row, 14, K.text)
    row.name:SetPoint("LEFT", row.iconFrame, "RIGHT", 9, 0)
    row.name:SetPoint("RIGHT", row.need, "LEFT", -6, 0)
    row.note = UI.Text(row, 11, K.stone)
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.note:SetPoint("RIGHT", row.need, "LEFT", -6, 0)
    row.note:Hide()
    row.TipEnter = function(self)
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
    end
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row.fill = function(self, m)
        self.item, self.made, self.madeRange, self.row = m.item, m.made, m.madeRange, m
        local name, icon = O.ItemFacts(m.item)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.name:SetText(name or ("Item " .. m.item))
        self.name:ClearAllPoints()
        if m.note then
            self.name:SetPoint("TOPLEFT", self.iconFrame, "TOPRIGHT", 9, 1)
            self.note:SetText(m.note)
            self.note:Show()
        else
            self.name:SetPoint("LEFT", self.iconFrame, "RIGHT", 9, 0)
            self.note:Hide()
        end
        self.name:SetPoint("RIGHT", self.need, "LEFT", -6, 0)
        self.need:SetText(Num(m.need))
        if m.have == nil then
            self.have:SetText("Unknown")
            self.stored:SetText("")
            self.short:SetText("Unknown")
            UI.Paint(self.short, K.stone)
            UI.Paint(self.have, K.stone)
        else
            self.have:SetText(Num(m.have))
            UI.Paint(self.have, K.text)
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
                b = UI.Segment(page.left, "", 80, function(self)
                    if self.profId then S.Select(self.profId); UI.lists.recipes:ScrollTop(); UI.Redraw() end
                end)
                chips[i] = b
            end
            local w = math.max(56, math.floor((area - 4 * (n - 1)) / n))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", page.left, "TOPLEFT", 12 + (i - 1) * (w + 4), -48)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(p.selected)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

-- The left card shows the queue or the recipes: the same card, so the workspace beside it keeps its size
local function ShowLeft(mode)
    leftMode = mode
    local recipes = mode == "recipes"
    page.segQueue:SetOn(not recipes)
    page.segRecipes:SetOn(recipes)
    UI.lists.queue.box:SetShown(not recipes)
    UI.lists.recipes.box:SetShown(recipes)
    f.search:SetShown(recipes)
    f.notice:SetShown(recipes)
    if not recipes then for _, b in ipairs(chips) do b:Hide() end end
end

local function Range(a, b) if b == nil or a == b then return UI.Money(a) end return UI.Money(a) .. " to " .. UI.Money(b) end

local function RenderDetail(queue, byId, totals)
    local d = page.detail
    local r
    for _, q in ipairs(queue) do if q.entry.id == selected then r = q end end
    if not r and queue[1] then r = queue[1]; selected = r.entry.id end
    if not r then
        selected = nil
        d.head:Hide()
        d.open:Hide(); d.remove:Hide(); d.done:Hide(); d.undo:Hide()
        d.empty:SetText("Queued crafts appear here: what each makes, what its materials may cost, and what it may sell for. Choose Add recipe to plan one.")
        d.empty:Show()
        return
    end
    local e = r.entry
    d.empty:Hide()
    d.head:Show()
    d.item=e.outItem
    d.name:SetText(e.name)
    d.icon:SetTexture(e.icon or UI.ICON_BLANK)
    d.prof:SetText(e.profName or "")
    d.crafts:SetText(e.crafts == 1 and "1 craft" or (e.crafts .. " crafts"))
    if r.perCraft then
        d.makes:SetText(e.crafts == 1 and ("Makes " .. r.perCraft) or ("Makes " .. r.perCraft .. " each, " .. r.expected .. " in all"))
    else
        d.makes:SetText("What it makes isn't known yet.")
    end
    if r.unresolved then
        -- the warning takes the line of what it makes (known materials are in the list; only a warning is worth the room here)
        d.makes:SetText("Its materials aren't known. Open " .. (e.profName or "its profession") .. " to update.")
        UI.Paint(d.makes, K.bronzeText)
    else
        UI.Paint(d.makes, K.textDim)
    end
    -- what the crafts may cost and earn: the Opportunities estimate times the crafts; unknown stays unknown
    local x = byId[e.id]
    if x then
        d.cost:SetText((x.reference and "about " or "")..UI.Money(x.cost)); UI.Paint(d.cost, K.text)
        d.sell:SetText(Range(x.sellLow, x.sellHigh)); UI.Paint(d.sell, K.text)
        d.profit:SetText(Range(x.profitLow, x.profitHigh))
        UI.Paint(d.profit, x.profitLow > 0 and K.sage or (x.profitHigh < 0 and K.ember or K.text))
    else
        d.cost:SetText("Unknown"); d.sell:SetText("Unknown"); d.profit:SetText("Unknown")
        UI.Paint(d.cost, K.stone); UI.Paint(d.sell, K.stone); UI.Paint(d.profit, K.stone)
    end
    d.profitLabel:SetText(totals.rate and "Estimated profit" or "Profit before fees")
    d.open:Show(); d.remove:Show(); d.done:Show()
    d.undo:SetShown(W.Progress ~= nil and W.Progress.CanUndo())
    d.makes:ClearAllPoints()
    d.makes:SetPoint("TOPLEFT", d.prof, "BOTTOMLEFT", 0, -3)
    d.makes:SetPoint("RIGHT", d.undo:IsShown() and d.undo or d.done, "LEFT", -8, 0)
end

local function RenderBar(queue, totals, sum)
    local bar = page.bar
    local n = #queue
    bar.title:SetText(("Total (%d %s)"):format(n, UI.Plural(n, "recipe", "recipes")))
    bar.sub:SetText(n == 0 and "Nothing queued" or ("%d %s to make"):format(totals.crafts, UI.Plural(totals.crafts, "craft", "crafts")))
    local priced = totals.priced > 0
    bar.cost:SetText(priced and ((totals.reference and "about " or "")..UI.Money(totals.cost)) or "Unknown")
    bar.value:SetText(priced and Range(totals.sellLow, totals.sellHigh ~= totals.sellLow and totals.sellHigh or nil) or "Unknown")
    bar.profit:SetText(priced and Range(totals.profitLow, totals.profitHigh ~= totals.profitLow and totals.profitHigh or nil) or "Unknown")
    UI.Paint(bar.cost, priced and K.text or K.stone)
    UI.Paint(bar.value, priced and K.text or K.stone)
    UI.Paint(bar.profit, priced and (totals.profitLow > 0 and K.sage or (totals.profitHigh < 0 and K.ember or K.text)) or K.stone)
    bar.profitLabel:SetText(totals.rate and "Profit" or "Profit before fees")
    -- what qualifies the totals, briefly: unpriced recipes, Low-confidence estimates, more than the market holds, the deposits at risk
    local notes = {}
    if priced and totals.unpriced > 0 then notes[#notes + 1] = ("%d of %d priced"):format(totals.priced, n) end
    if priced and (totals.low or 0) > 0 then notes[#notes + 1] = ("%d low confidence"):format(totals.low) end
    if priced and (totals.absorb or 0) > 0 then notes[#notes + 1] = "more than the market holds" end
    if priced and totals.deposit then notes[#notes + 1] = "deposits " .. UI.Money(totals.deposit) end
    bar.partial:SetText(table.concat(notes, " \194\183 "))
    bar.shop:SetEnabled(n > 0)
end

-- one short line on how the plan gets a material: what is made, bought or collected (nothing for what the bags already cover)
local function Notes(line)
    if not line then return nil end
    local parts = {}
    if line.source == "make" and line.make then
        parts[#parts + 1] = ("Craft %s \195\151 %d"):format(UI.Shorten(line.make.name, 18), line.make.crafts)
    elseif line.buy and (line.source == "vendor" or line.source == "auction") then
        parts[#parts + 1] = ("Buy %d %s"):format(line.rest, line.source == "vendor" and "from a vendor" or "at auction")
    end
    local stored = (line.owned.bank or 0) + (line.owned.guild or 0)
    if stored > 0 then parts[#parts + 1] = ("Collect %d"):format(stored) end
    if #parts == 0 then return nil end
    return table.concat(parts, " \194\183 ")
end

-- the strip above the materials
local function PaintStrategy(state, plan, why, n)
    local st = page.strat
    st.view:SetEnabled(state == "ready")
    if n == 0 then
        st.line1:SetText("Add recipes to see the best way to make them.")
        st.line2:SetText("")
        UI.Paint(st.line1, K.textDim)
        return
    end
    if state ~= "ready" then
        st.line1:SetText(state == "planning" and "Planning..." or "The strategy couldn't be worked out.")
        st.line2:SetText(state == "planning" and "Working out the best way to get the materials." or "Shopping shows its basic list instead.")
        UI.Paint(st.line1, K.textDim)
        return
    end
    local w = Sg.Summary(plan, UI.Money)
    st.line1:SetText(w.status .. " \194\183 " .. w.headline)
    UI.Paint(st.line1, w.tone == "good" and K.sage or (w.tone == "warn" and K.bronzeText or K.textDim))
    local parts = {}
    if w.cost then parts[#parts + 1] = "Estimated cost " .. w.cost end
    if w.cash then parts[#parts + 1] = "Gold needed now " .. w.cash end
    st.line2:SetText(table.concat(parts, " \194\183 "))
    st.words = w
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
    if not leftMode then leftMode = #queue == 0 and "recipes" or "queue" end
    f.queueCount:SetText(("%d of %d"):format(#queue, W.MAX_QUEUE))
    local byId, totals = {}, { entries = 0, priced = 0, unpriced = 0, crafts = 0, cost = 0, sellLow = 0, sellHigh = 0, profitLow = 0, profitHigh = 0 }
    if #queue > 0 then byId, totals = S.PlanEstimates() end
    RenderDetail(queue, byId, totals)
    UI.lists.queue:SetData(queue, "Nothing queued yet. Choose Add recipe, then Add on a recipe.")
    ShowLeft(leftMode)

    -- materials
    local mats, sum, view = S.Materials()
    matView = view
    local sstate, splan, swhy = S.QueueStrategy()
    if sstate == "ready" then
        local by = {}
        for _, l in ipairs(splan.items) do by[l.item] = l end
        for _, m in ipairs(mats) do m.note = Notes(by[m.item]) end
    end
    UI.lists.mats:SetData(mats, sum.state == "empty" and "Materials for the queue appear here." or nil)
    PaintStrategy(sstate, splan, swhy, #queue)
    local text, tone = S.Headline(sum)
    f.headline:SetText(text)
    UI.Paint(f.headline, tone == "good" and K.sage or (tone == "warn" and K.bronzeText or K.textDim))
    f.storeNote:SetText(S.StockNote(sum, view) or "")
    f.scope:SetText(("Counts %s."):format(K2.Scope(view)))
    f.useGuild:SetOn(view.guild.enabled)
    if page.notices then page.notices:SetOn(W.Notice ~= nil and W.Notice.On()) end
    RenderBar(queue, totals, sum)
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

local function BuildLeft()
    local rc = Card(0, TOP, LEFT_W)
    rc:SetPoint("BOTTOMLEFT", 0, BAR_H + GAP)
    page.left = rc
    page.segQueue = UI.Segment(rc, "Craft queue", 124, function() ShowLeft("queue"); UI.Redraw() end)
    page.segQueue:SetPoint("TOPLEFT", 12, -12)
    page.segRecipes = UI.Segment(rc, "Recipes", 100, function() ShowLeft("recipes"); UI.Redraw() end)
    page.segRecipes:SetPoint("LEFT", page.segQueue, "RIGHT", 4, 0)
    f.queueCount = UI.Text(rc, 13, K.stone)
    f.queueCount:SetPoint("TOPRIGHT", -14, -17)

    -- recipes
    local box = UI.Search(rc, LEFT_W - 24, 28, "Search recipes")
    box:SetPoint("TOPLEFT", 12, -80)
    box:SetMaxLetters(40)
    box:HookScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "" and not self:HasFocus())
        S.SetFilter(self:GetText())
        UI.lists.recipes:ScrollTop()
        UI.Redraw()
    end)
    f.search = box
    f.notice = UI.Text(rc, 12, K.textDim)
    f.notice:SetPoint("TOPLEFT", 14, -114)
    f.notice:SetWidth(LEFT_W - 28)
    f.notice:SetWordWrap(true)
    f.notice:SetJustifyV("TOP")
    local recipes = UI.List(rc, REC_H, MakeRecipeRow, 300, false)
    recipes.box:SetPoint("TOPLEFT", 4, -148)
    recipes.box:SetPoint("BOTTOMRIGHT", -4, 6)
    UI.lists.recipes = recipes

    -- queue
    local queue = UI.List(rc, QUE_H, MakeQueueRow, 330, false)
    queue.box:SetPoint("TOPLEFT", 4, -48)
    queue.box:SetPoint("BOTTOMRIGHT", -4, 6)
    UI.lists.queue = queue
end

-- The chosen craft, in three bands: who it is (a picture, the name, the profession and how many crafts), what it may cost and earn (three
-- recessed boxes across the panel), and the actions (with the warning about unknown materials beside them). Nothing is added to fill it:
-- a craft with little to say simply has a short first band.
local function BuildDetail()
    local x = LEFT_W + 12
    local d = Card(x, TOP, nil, PANEL_H)
    d:SetPoint("TOPRIGHT", 0, TOP)
    page.detail = d
    d.head = CreateFrame("Frame", nil, d)
    d.head:SetAllPoints()
    d.iconFrame = UI.ItemIcon(d.head, 48)
    d.iconFrame:SetPoint("TOPLEFT", 14, -12)
    d.icon = d.iconFrame.tex
    d.advisorItem=CreateFrame("Button",nil,d.head); d.advisorItem:SetAllPoints(d.iconFrame)
    UI.ItemTip(d.advisorItem,function() return d.item end)
    d.name = UI.Text(d.head, 19, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 74, -10)
    d.name:SetPoint("RIGHT", d.head, "RIGHT", -14, 0)
    d.name:SetHeight(24)
    d.prof = UI.Text(d.head, 13, K.textDim)
    d.prof:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 1, -3)
    d.crafts = UI.Text(d.head, 14, K.bronzeText, "strong")
    d.crafts:SetPoint("LEFT", d.prof, "RIGHT", 10, 0)
    -- the actions sit at the right of the name block (the room under the name is free there), so the panel needs no row of its own for them
    d.remove = UI.Button(d, "Remove", 76, "secondary", function()
        if selected then S.Remove(selected); UI.Redraw() end
    end, 26)
    d.remove:SetPoint("TOPRIGHT", -14, -40)
    UI.Tip(d.remove, "Remove", "Takes this recipe out of the queue. Nothing else changes.")
    d.open = UI.ArtButton(d, "Open recipe", "npc:hammer", 124, "secondary", function()
        if selected then S.OpenRecipe(selected); UI.Redraw() end
    end, 26)
    d.open:SetPoint("RIGHT", d.remove, "LEFT", -4, 0)
    UI.Tip(d.open, "Open recipe", "Shows this recipe in the game's profession window. It makes nothing.")
    -- the player's own progress: one craft done (Session.MarkCrafted); the queue counts down and the entry goes after its last craft
    d.done = UI.Button(d, "Done", 60, "secondary", function()
        if selected then S.MarkCrafted(selected); UI.Redraw() end
    end, 26)
    UI.Tip(d.done, "Crafted one", "Count one craft as done. The last one takes the recipe off the plan.")
    d.done:SetPoint("RIGHT", d.open, "LEFT", -4, 0)
    d.makes = UI.Text(d.head, 13, K.textDim)
    d.makes:SetPoint("TOPLEFT", d.prof, "BOTTOMLEFT", 0, -3)
    d.undo = UI.Button(d, "Undo", 56, "secondary", function() S.UndoCrafted(); UI.Redraw() end, 26)
    d.undo:SetPoint("RIGHT", d.done, "LEFT", -4, 0)
    UI.Tip(d.undo, "Undo", "Take back your last Crafted one.")
    d.undo:Hide()
    d.makes:SetPoint("RIGHT", d.undo, "LEFT", -8, 0)
    d.makes:SetHeight(16)
    -- what the crafts may cost and earn: three boxes across the panel
    local gap = 8
    local function Box(label, i)
        local b = CreateFrame("Frame", nil, d.head)
        b:SetHeight(42)
        b:SetPoint("TOPLEFT", d.head, "TOPLEFT", 14 + (i - 1) * 1, -74)   -- the x is set by the width below
        UI.Panel(b, "canvas")
        b:EnableMouse(true)
        local l = UI.Text(b, 11, K.stone)
        l:SetPoint("TOPLEFT", 10, -6)
        l:SetText(label)
        local v = UI.Text(b, 16, K.text, "strong")
        v:SetPoint("BOTTOMLEFT", 10, 6)
        v:SetPoint("RIGHT", -8, 0)
        UI.Tip(b, "Estimates", "From the cheapest listings of your last scan, before the auction house's cut.")
        return b, v, l
    end
    local b1, v1 = Box("Total cost", 1)
    local b2, v2 = Box("Est. value", 2)
    local b3, v3, l3 = Box("Profit before fees", 3)
    d.boxes = { b1, b2, b3 }
    d.cost, d.sell, d.profit, d.profitLabel = v1, v2, v3, l3
    local function Place(w)
        local bw = math.floor((w - 28 - 2 * gap) / 3)
        for i, b in ipairs(d.boxes) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", d.head, "TOPLEFT", 14 + (i - 1) * (bw + gap), -74)
            b:SetWidth(bw)
        end
    end
    Place(LEFT_W + 100)
    d:HookScript("OnSizeChanged", function(_, w) if w and w >= 200 then Place(w) end end)
    d.empty = UI.Text(d, 13, K.textDim)
    d.empty:SetPoint("TOPLEFT", 16, -16)
    d.empty:SetPoint("RIGHT", -16, 0)
    d.empty:SetWordWrap(true)
    d.empty:SetJustifyV("TOP")
    page.open, page.remove = d.open, d.remove
end

local function BuildMaterials()
    local x = LEFT_W + 12
    local mc = Card(x, TOP - PANEL_H - GAP)
    mc:SetPoint("BOTTOMRIGHT", 0, BAR_H + GAP)
    local mh = Heading(mc, "Materials needed")
    f.scope = UI.Text(mc, 12, K.stone)
    f.scope:SetPoint("BOTTOMLEFT", mh, "BOTTOMRIGHT", 10, 2)
    f.scope:SetText("Counts bags only.")
    f.useGuild = UI.Switch(mc, "Use guild bank", function()
        S.SetUseGuild(not S.UseGuild())
        UI.Redraw()
    end)
    f.useGuild:SetPoint("TOPRIGHT", -14, -14)
    UI.Tip(f.useGuild, "Use guild bank materials", USE_GUILD_TIP)
    f.headline = UI.Text(mc, 13, K.textDim)
    f.headline:SetPoint("TOPLEFT", 14, -38)
    f.headline:SetPoint("RIGHT", -14, 0)
    -- the Crafting Strategy strip: the whole queue's plan in two lines, and the way to the full strategy
    local st = CreateFrame("Frame", nil, mc)
    st:SetPoint("TOPLEFT", 14, -60)
    st:SetPoint("TOPRIGHT", -14, -60)
    st:SetHeight(STRIP_H)
    UI.Panel(st, "canvas")
    st.line1 = UI.Text(st, 12, K.sage, "strong")
    st.line1:SetPoint("TOPLEFT", 10, -6)
    st.line1:SetPoint("RIGHT", -116, 0)
    st.line1:SetJustifyH("LEFT")
    st.line2 = UI.Text(st, 11, K.textDim)
    st.line2:SetPoint("TOPLEFT", 10, -22)
    st.line2:SetPoint("RIGHT", -116, 0)
    st.line2:SetJustifyH("LEFT")
    st.line2:SetHeight(14)
    st.view = UI.Button(st, "View strategy", 100, "secondary", function()
        if UI.StrategyView then UI.StrategyView.Open("queue") end
    end, 24)
    st.view:SetPoint("RIGHT", -8, 0)
    UI.Tip(st.view, "View strategy", "See every step of the plan, with prices and comparisons.")
    st:EnableMouse(true)
    UI.TipFn(st, "Crafting strategy", function()
        local w = st.words
        local lines = "One plan for the whole queue: shared materials are counted once."
        if w then
            local top = {}
            if w.costTip then top[#top + 1] = w.costTip end
            if w.direct then top[#top + 1] = "Buying every material directly: " .. w.direct end
            if w.saveLine then top[#top + 1] = w.saveLine end
            if #top > 0 then lines = table.concat(top, "\n") .. "\n" .. lines end
        end
        return lines
    end)
    page.strat = st
    local item = UI.Head(mc, "Material", 120, "LEFT")
    item:SetPoint("TOPLEFT", 14, -62 - STRIP_SHIFT)
    local rx = -(4 + 16 + 8)   -- the rows' right edge: the list's inset, its scroll gutter and the columns' own margin
    local hs = UI.Head(mc, "Still needed", MC_SHORT); hs:SetPoint("TOPRIGHT", rx, -62 - STRIP_SHIFT)
    local hst = UI.Head(mc, "Stored", MC_STORED); hst:SetPoint("RIGHT", hs, "LEFT", -MC_GAP, 0)
    local hb = UI.Head(mc, "In bags", MC_HAVE); hb:SetPoint("RIGHT", hst, "LEFT", -MC_GAP, 0)
    local hn = UI.Head(mc, "Need", MC_NEED); hn:SetPoint("RIGHT", hb, "LEFT", -MC_GAP, 0)
    local rule = UI.Rule(mc, 0.5)
    rule:SetPoint("TOPLEFT", 12, -80 - STRIP_SHIFT); rule:SetPoint("TOPRIGHT", -12, -80 - STRIP_SHIFT)
    local mats = UI.List(mc, MAT_H, MakeMaterialRow, 160, false)
    mats.box:SetPoint("TOPLEFT", 4, -82 - STRIP_SHIFT)
    mats.box:SetPoint("BOTTOMRIGHT", -4, 28)
    UI.lists.mats = mats
    f.storeNote = UI.Text(mc, 12, K.stone)   -- what has not been seen yet ("Open your bank with Workshop loaded to update.")
    f.storeNote:SetPoint("BOTTOMLEFT", 14, 9)
    f.storeNote:SetPoint("RIGHT", -14, 0)
end

local function BuildBar()
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetHeight(BAR_H)
    UI.Panel(bar, "editor")
    bar:EnableMouse(true)
    page.bar = bar
    bar.title = UI.Text(bar, 17, K.text, "serif")
    bar.title:SetPoint("TOPLEFT", 16, -9)
    bar.sub = UI.Text(bar, 12, K.textDim)
    bar.sub:SetPoint("TOPLEFT", 17, -32)
    local function Fig(label, x)
        local l = UI.Text(bar, 11, K.stone)
        l:SetPoint("TOPLEFT", x, -9)
        l:SetText(label)
        local v = UI.Text(bar, 14, K.text, "strong")
        v:SetPoint("TOPLEFT", x, -26)
        v:SetWidth(138)
        return v, l
    end
    bar.cost = Fig("Cost", 190)
    bar.value = Fig("Value (listings)", 335)
    bar.profit, bar.profitLabel = Fig("Profit before fees", 480)
    bar.partial = UI.Text(bar, 11, K.bronzeText)
    bar.partial:SetPoint("TOPLEFT", 190, -42)
    bar.partial:SetPoint("TOPRIGHT", bar, "TOPLEFT", 600, -42)
    UI.Tip(bar, "Plan totals", "The queued crafts' estimates added up, before the auction house's cut.\nA recipe without a price is left out.")
    bar.shop = UI.ArtButton(bar, "Shopping list", "npc:reagent-pouch", 150, "primary", function() UI.Go("shop") end, 38)
    bar.shop:SetPoint("RIGHT", -10, 0)
    UI.Tip(bar.shop, "Shopping list", "What your queue still needs and where to get it.")
end

local function Build(p, frame)
    page, f, K = p, frame, UI.K
    BuildLeft()
    BuildDetail()
    BuildMaterials()
    BuildBar()
    -- the way to the recipes, in the header: it shows the recipe list in the left card
    page.addRecipe = UI.ArtButton(page, "Add recipe", "plus", 140, "secondary", function() ShowLeft("recipes"); UI.Redraw() end, 32)
    page.addRecipe:SetPoint("TOPRIGHT", -2, -4)
    UI.Tip(page.addRecipe, "Add recipe", "Shows your recipes so you can choose what to add to the plan.")
    -- progress notices (Notice.lua): a short card when a craft is counted or a recipe's materials are all in your bags; on unless turned off
    page.notices = UI.Switch(page, "Progress notices", function()
        if W.Notice then W.Notice.SetOn(not W.Notice.On()) end
        UI.Redraw()
    end)
    page.notices:SetPoint("RIGHT", page.addRecipe, "LEFT", -18, 0)
    UI.Tip(page.notices, "Progress notices", "A short notice when a craft is counted or a recipe's materials are ready.")
end

UI.Register({
    key = "craft", nav = "Crafting", icon = "npc:hammer",
    title = "Crafting Plan", sub = "Queue your crafts, gather the materials and get it done.",
    tip = "Your craft queue, what it may cost, and the materials it needs, against your bags and storage.",
    Build = Build, Render = Render,
    Reset = function() matView = nil; leftMode = nil end,
})
