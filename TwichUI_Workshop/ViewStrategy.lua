-- TwichUI Workshop: the full crafting strategy, and the confirmation before it is added to the queue (P2, simplified in P2.1)
-- Opened from "View strategy" on the Opportunities, Crafting Plan and Shopping pages. A focused window over the Workshop (the same surfaces and
-- fonts): the item and how sure the plan is, three figures (Estimated cost, Gold needed now, Savings: one planning figure each, its range in the
-- tooltip unless "Price ranges" is on), one line saying what to do, then a checklist: Craft, Buy from vendor, Buy from Auction House, Collect,
-- what is already in the bags, and "Other options considered" folded away. Every item row has the item's own tooltip with the precise prices and
-- the buy-or-craft comparison under it. What the plan assumes is behind the small Notes control, not in the list.
-- "Add optimized plan" never changes the queue by itself: it opens a confirmation that lists the recipes and crafts that would be added; only
-- its "Add to plan" button asks Session.ApplyOptimized (one all-or-nothing change, checked again against the queue as it is then). When no
-- optimized plan can be made for a recipe, the confirmation offers "Add recipe only" instead, named as such. Nothing is crafted, bought or sent.

local R = TwichUI
local W = R.Workshop
local S, O, PR = W.Session, W.Observe, W.Prices
local Sg = W.Strategy
local UI = W.UI
local SV = {}
UI.StrategyView = SV
W.StrategyView = SV

local WIDTH, HEIGHT, ROW_H = 680, 540, 40
local CW, CH, CROW_H = 480, 330, 34

local K
local sv, cd                   -- the strategy window, and the confirmation over it
local scope, scopeRec          -- what the strategy is about: "opp" (one recipe, on its own) or "queue" (the whole crafting plan)
local showAlts = false         -- "Other options considered" is collapsed unless the player opened it (memory only)
local TONE = { make = "tealHi", buy = "bronzeText", own = "textDim", collect = "sage", alt = "textDim", warn = "bronzeText" }

local function Money(c) return UI.Money(c) end

---------------------------------------------------------------------------
-- Rows of the strategy list: the action is the title; a few words under it; the precise numbers in the tooltip, under the item's own
---------------------------------------------------------------------------
local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row, 6)
    row.iconFrame = UI.ItemIcon(row, 26)
    row.iconFrame:SetPoint("LEFT", 10, 0)
    row.icon = row.iconFrame.tex
    row.right = UI.Text(row, 13, K.text, "strong")
    row.right:SetPoint("RIGHT", -10, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(150)
    row.title = UI.Text(row, 13, K.text, "strong")
    row.title:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 9, 1)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.detail = UI.Text(row, 11, K.textDim)
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.head = UI.Text(row, 13, K.bronzeText, "strong")
    row.head:SetPoint("LEFT", 10, -6)
    row.rule = UI.Rule(row, 0.45)
    row.rule:SetPoint("BOTTOMLEFT", 10, 4); row.rule:SetPoint("BOTTOMRIGHT", -10, 4)
    row.TipEnter = function(self)
        local d = self.data
        if d and d.kind ~= "head" and d.kind ~= "toggle" then UI.ItemTipLines(self, d.item, d.tip, d.title) end
    end
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row:SetScript("OnClick", function(self, ...)
        local d = self.data
        if d and d.kind == "toggle" then SV.ToggleAlternatives() return end
        if d and d.item then UI.LinkItem(d.item) end   -- Shift-click: the item's link in the open chat box, like other item pictures
    end)
    row.fill = function(self, d)
        self.data = d
        local kind = d.kind
        local isHead, isToggle = kind == "head", kind == "toggle"
        self:EnableMouse(not isHead)
        self.head:SetShown(isHead or isToggle); self.rule:SetShown(isHead or isToggle)
        local item = not isHead and not isToggle
        self.iconFrame:SetShown(item)
        self.title:SetShown(item); self.detail:SetShown(item)
        self.right:SetShown(item or isToggle)
        if isHead or isToggle then
            self.head:SetText(d.title)
            self.right:SetText(isToggle and d.right or "")
            UI.Paint(self.right, K.bronzeText)
            return
        end
        local _, icon = O.ItemFacts(d.item or 0)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        local title = d.title or ""
        -- Buy/collect rows end in an actual material name; Craft steps name recipes.
        if kind ~= "step" and d.item then
            local name, _, quality = O.ItemFacts(d.item)
            name = name or UI.ItemName(d.item)
            if title:sub(-#name) == name then title = title:sub(1, #title - #name) .. UI.QualityText(name, quality) end
        end
        self.title:SetText(title)
        self.detail:SetText(d.detail or "")
        self.right:SetText(d.right or "")
        UI.Paint(self.right, K[TONE[d.tone] or "text"])
    end
    return row
end

local function MakeOpRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row, 6)
    row.iconFrame = UI.ItemIcon(row, 24)
    row.iconFrame:SetPoint("LEFT", 8, 0)
    row.icon = row.iconFrame.tex
    row.right = UI.Text(row, 12, K.textDim)
    row.right:SetPoint("RIGHT", -8, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(120)
    row.title = UI.Text(row, 13, K.text, "strong")
    row.title:SetPoint("LEFT", row.iconFrame, "RIGHT", 8, 0)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    UI.ItemTip(row, function() return row.item end)
    row.fill = function(self, op)
        self.item = op.produces
        local _, icon = O.ItemFacts(op.produces or 0)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.title:SetText(("Craft %d \195\151 %s"):format(op.crafts, op.name))
        self.right:SetText(op.final and "your recipe" or ("makes " .. (op.makes or "?")))
        UI.Paint(self.right, op.final and K.bronzeText or K.textDim)
    end
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function PlanFor()
    if scope == "queue" then return S.QueueStrategy() end
    return S.OppStrategy(scopeRec)
end

local function Box(i)
    return sv.boxes[i]
end

local function PaintStrategy()
    local state, plan, why = PlanFor()
    sv.detailed:SetOn(S.PriceDetail())
    if scope == "queue" then
        sv.title:SetText("Your crafting plan")
        UI.Art(sv.icon, "npc:hammer", 46)
        sv.icon:SetTexCoord(0, 1, 0, 1)
    else
        sv.title:SetText(scopeRec and scopeRec.name or "Crafting strategy")
        local _, icon = O.ItemFacts(scopeRec and scopeRec.outItem or 0)
        sv.icon:SetTexture(icon or (scopeRec and scopeRec.icon) or UI.ICON_BLANK)
        sv.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    local crafts = scope == "queue" and "Everything queued, planned together" or "1 craft"
    local list = UI.lists.strategy
    sv.notes = nil
    if state ~= "ready" then
        for i = 1, 3 do Box(i).v:SetText("..."); UI.Paint(Box(i).v, K.stone); Box(i).tip = nil end
        sv.sub:SetText(crafts .. " \194\183 " .. (state == "planning" and "Planning..." or (state == "failed" and "Couldn't be worked out" or "Not enough data")))
        UI.Paint(sv.sub, K.textDim)
        sv.headline:SetText("")
        sv.add:SetEnabled(false)
        list:SetData({}, state == "planning" and "Working out the best way to get the materials..." or (state == "failed" and
            "The plan couldn't be worked out. Shopping shows its basic list instead." or (why or "Nothing to show.")))
        return
    end
    local words = Sg.Summary(plan, Money)
    sv.sub:SetText(crafts .. " \194\183 " .. words.status)
    UI.Paint(sv.sub, words.tone == "good" and K.sage or (words.tone == "warn" and K.bronzeText or K.textDim))
    sv.headline:SetText(words.headline)
    local function Set(i, label, text, tone, tip)
        local b = Box(i)
        b.l:SetText(label)
        b.v:SetText(text or "Unknown")
        b.tip = tip
        UI.Paint(b.v, text and (tone == "good" and K.sage or (tone == "warn" and K.bronzeText or (tone == "quiet" and K.textDim or K.text))) or K.stone)
    end
    local costTip = words.costTip
    if words.direct then costTip = (costTip and (costTip .. "\n") or "") .. "Buying every material directly: " .. words.direct end
    Set(1, "Estimated cost", words.cost, nil, costTip)
    Set(2, "Gold needed now", words.cash, nil, words.cashTip)
    local saved = words.savingsTone ~= "quiet"
    Set(3, words.savingsLabel, saved and words.savings or (words.savings == "Unknown" and "Can't compare" or "No saving"), words.savingsTone, words.savingsWhy)
    sv.notes = Sg.Notes(plan, UI.ItemName)
    sv.add:SetEnabled(true)
    local rows = Sg.Detail(plan, UI.ItemName, Money, PR.AgeText, W.Queue.Now(), showAlts)
    list:SetData(rows, nil)
end

local function PaintConfirm()
    local state, plan, ops, key, why = S.PreviewOptimized(cd.rec)
    cd.key = key
    local list = UI.lists.confirm
    if state == "ready" and ops and #ops > 0 then
        local n = 0
        for _, op in ipairs(ops) do n = n + op.crafts end
        cd.text:SetText(("%d %s, %d %s in all. Nothing is crafted or bought for you."):format(#ops, #ops == 1 and "recipe" or "recipes", n, n == 1 and "craft" or "crafts"))
        list:SetData(ops, nil)
        cd.ok:SetEnabled(true)
        cd.ok.text:SetText("Add to plan")
    else
        cd.ok:SetEnabled(false)
        if state == "planning" then
            cd.text:SetText("Checking your plan against what is queued now...")
            list:SetData({}, "Planning...")
        elseif state == "ready" or state == "empty" then
            cd.text:SetText("Nothing to add: your crafting plan already covers it.")
            list:SetData({}, "Nothing to add.")
        else
            cd.text:SetText(why or "The plan couldn't be worked out, so nothing can be added.")
            list:SetData({}, "")
        end
    end
    -- the deliberate fallback (Opportunities only): the recipe on its own, when no optimized plan can be added
    local plain = cd.rec ~= nil and state ~= "ready" and state ~= "planning" and not S.IsQueued(cd.rec.id)
    cd.plain:SetShown(plain)
end

function SV.Refresh()
    if sv and sv:IsShown() then PaintStrategy() end
    if cd and cd:IsShown() then PaintConfirm() end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Dialog(parent, w, h, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:SetPoint("CENTER", parent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(level)
    f:EnableMouse(true)
    UI.Panel(f, "card")
    local scrim = CreateFrame("Frame", nil, parent)
    scrim:SetAllPoints(parent)
    scrim:SetFrameStrata("DIALOG")
    scrim:SetFrameLevel(level - 1)
    scrim:EnableMouse(true)
    scrim.tex = UI.L.Solid(scrim, "BACKGROUND", K.ink or { 0.05, 0.04, 0.03 }, 0.62)
    scrim.tex:SetAllPoints()
    scrim:Hide()
    f.scrim = scrim
    f:HookScript("OnShow", function(self) self.scrim:Show() end)
    f:HookScript("OnHide", function(self) self.scrim:Hide() end)
    f:Hide()
    return f
end

local function BuildConfirm(parent)
    cd = Dialog(parent, CW, CH, 40)
    cd.heading = UI.Text(cd, 19, K.text, "serif")
    cd.heading:SetPoint("TOPLEFT", 16, -14)
    cd.heading:SetText("Add these crafts to your plan?")
    cd.text = UI.Text(cd, 12, K.textDim)
    cd.text:SetPoint("TOPLEFT", 16, -44)
    cd.text:SetPoint("RIGHT", -16, 0)
    cd.text:SetWordWrap(true)
    cd.text:SetJustifyV("TOP")
    cd.text:SetHeight(32)
    local list = UI.List(cd, CROW_H, MakeOpRow, 120, "canvas")
    list.box:SetPoint("TOPLEFT", 12, -82)
    list.box:SetPoint("BOTTOMRIGHT", -12, 56)
    UI.lists.confirm = list
    cd.ok = UI.Button(cd, "Add to plan", 140, "primary", function()
        local ok = S.ApplyOptimized(cd.key, cd.rec)
        if ok then cd:Hide(); sv:Hide() end   -- done: the page behind shows the queue, and the footer says what was added
        UI.Redraw()
    end, 32)
    cd.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    UI.Tip(cd.ok, "Add to plan", "Adds these crafts as one change. Crafts already queued are never added twice.")
    cd.cancel = UI.Button(cd, "Cancel", 100, "secondary", function() cd:Hide() end, 32)
    cd.cancel:SetPoint("RIGHT", cd.ok, "LEFT", -8, 0)
    -- the deliberate fallback: only the recipe itself, when no optimized plan can be added (never offered as if it were optimized)
    cd.plain = UI.Button(cd, "Add recipe only", 130, "secondary", function()
        if cd.rec and S.Add(cd.rec) then cd:Hide(); sv:Hide() end
        UI.Redraw()
    end, 32)
    cd.plain:SetPoint("BOTTOMLEFT", 16, 14)
    UI.Tip(cd.plain, "Add recipe only", "Queues this recipe once, without planning its materials.")
    cd.plain:Hide()
end

local function BuildStrategy(parent)
    sv = Dialog(parent, WIDTH, HEIGHT, 20)
    -- the head: the item, its name, how many crafts and how sure the plan is
    sv.iconFrame = UI.ItemIcon(sv, 46)
    sv.iconFrame:SetPoint("TOPLEFT", 18, -14)
    sv.icon = sv.iconFrame.tex
    sv.title = UI.Text(sv, 22, K.text, "serif")
    sv.title:SetPoint("TOPLEFT", 76, -14)
    sv.title:SetPoint("RIGHT", -200, 0)
    sv.sub = UI.Text(sv, 13, K.sage, "strong")
    sv.sub:SetPoint("TOPLEFT", 77, -44)
    sv.sub:SetPoint("RIGHT", -200, 0)
    sv.detailed = UI.Switch(sv, "Price ranges", function()
        S.SetPriceDetail(not S.PriceDetail())
        UI.Redraw()
    end)
    sv.detailed:SetPoint("TOPRIGHT", -18, -18)
    UI.Tip(sv.detailed, "Price ranges", "Show the full price range beside each cost, everywhere in Workshop.")
    sv.info = UI.Button(sv, "Notes", 70, "secondary", nil, 22)
    sv.info:SetPoint("TOPRIGHT", -18, -44)
    UI.TipFn(sv.info, "What the plan assumes", function()
        return sv.notes and #sv.notes > 0 and table.concat(sv.notes, "\n") or nil
    end)
    -- one concise cost summary: three figures, the range of each in its tooltip
    sv.boxes = {}
    local gap = 8
    local bw = math.floor((WIDTH - 36 - 2 * gap) / 3)
    for i = 1, 3 do
        local b = CreateFrame("Frame", nil, sv)
        b:SetSize(bw, 50)
        b:SetPoint("TOPLEFT", 18 + (i - 1) * (bw + gap), -72)
        UI.Panel(b, "canvas")
        b:EnableMouse(true)
        b.l = UI.Text(b, 11, K.stone)
        b.l:SetPoint("TOPLEFT", 10, -7)
        b.l:SetPoint("RIGHT", -6, 0)
        b.v = UI.Text(b, 16, K.text, "strong")
        b.v:SetPoint("BOTTOMLEFT", 10, 8)
        b.v:SetPoint("RIGHT", -6, 0)
        sv.boxes[i] = b
    end
    UI.TipFn(sv.boxes[1], "Estimated cost", function()
        local b = sv.boxes[1]
        return (b.tip and (b.tip .. "\n") or "") .. "Owned materials count at what they would cost."
    end)
    UI.TipFn(sv.boxes[2], "Gold needed now", function()
        local b = sv.boxes[2]
        return (b.tip and (b.tip .. "\n") or "") .. "Only what you buy. Owned and collected materials are free to use."
    end)
    UI.TipFn(sv.boxes[3], "Savings", function()
        local b = sv.boxes[3]
        return (b.tip and (b.tip .. "\n") or "") .. "Compared with buying every material directly. Not a profit."
    end)
    -- what to do, in one line, then the checklist
    sv.headline = UI.Text(sv, 14, K.text, "strong")
    sv.headline:SetPoint("TOPLEFT", 20, -134)
    sv.headline:SetPoint("RIGHT", -18, 0)
    local list = UI.List(sv, ROW_H, MakeRow, 160, "canvas")
    list.box:SetPoint("TOPLEFT", 14, -156)
    list.box:SetPoint("BOTTOMRIGHT", -14, 56)
    UI.lists.strategy = list
    sv.close = UI.Button(sv, "Close", 100, "secondary", function() sv:Hide() end, 32)
    sv.close:SetPoint("BOTTOMRIGHT", -16, 14)
    sv.add = UI.Button(sv, "Add optimized plan", 190, "primary", function() SV.Confirm() end, 32)
    sv.add:SetPoint("RIGHT", sv.close, "LEFT", -8, 0)
    UI.Tip(sv.add, "Add optimized plan", "Review the optimized crafts before adding them.")
    sv.hint = UI.Text(sv, 11, K.stone)
    sv.hint:SetPoint("BOTTOMLEFT", 18, 24)
    sv.hint:SetWidth(WIDTH - 18 - 100 - 190 - 40)
    sv.hint:SetText("Hover a row for prices and comparisons.")
    sv:HookScript("OnHide", function() if cd then cd:Hide() end end)
end

local function Ensure()
    if sv then return true end
    local win = W.Window and W.Window.Frame and W.Window.Frame()
    if not win then return false end
    K = UI.K
    BuildStrategy(win)
    BuildConfirm(win)
    win:HookScript("OnHide", function() sv:Hide(); cd:Hide() end)
    return true
end

-- the strategy of one recipe (scope "opp"), or of the whole crafting plan ("queue")
function SV.Open(kind, rec)
    if not Ensure() then return false end
    scope, scopeRec = kind == "queue" and "queue" or "opp", rec
    sv:Show()
    PaintStrategy()
    UI.lists.strategy:ScrollTop()
    return true
end

function SV.Close() if sv then sv:Hide() end end

-- "Other options considered": shown or folded away (one row of the list; it stays as chosen while the game runs)
function SV.ToggleAlternatives()
    showAlts = not showAlts
    if sv and sv:IsShown() then PaintStrategy() end
    return showAlts
end
function SV.IsOpen() return sv ~= nil and sv:IsShown() end

-- "Add optimized plan": the confirmation. Nothing is added here. `rec` (optional): the recipe the confirmation is for when it is opened
-- without the strategy window (Opportunities' Add button).
function SV.Confirm(rec)
    if rec then
        if not Ensure() then return false end
        scope, scopeRec = "opp", rec
    elseif not (sv and sv:IsShown()) then
        return false
    end
    cd.rec = scope == "opp" and scopeRec or nil
    cd:Show()
    PaintConfirm()
    UI.lists.confirm:ScrollTop()
    return true
end

function SV.Frames() return sv, cd end   -- (the tests and the simulator scenario)
