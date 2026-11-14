-- TwichUI Workshop: the full crafting strategy, and the confirmation before it is added to the queue (P2)
-- Opened from "View strategy" on the Opportunities and Crafting Plan pages. A focused window over the Workshop (the same surfaces, the same
-- fonts): the cost summary (buying directly, the optimized economic cost, the cash needed now, the savings), then one scrolling list of the crafting
-- steps in order, what to buy, what comes from the bags, what to collect from storage, the other ways the planner considered, and what to know.
-- "Add optimized plan" never changes the queue by itself: it opens a confirmation that lists the recipes and crafts that would be added; only
-- its "Add to plan" button asks Session.ApplyOptimized (one all-or-nothing change, checked again against the queue as it is then). Nothing is
-- crafted, bought or sent. The plan is the planner's, worked out in slices (Strategy.lua); while it runs the window says so.

local R = TwichUI
local W = R.Workshop
local S, O, PR = W.Session, W.Observe, W.Prices
local Sg = W.Strategy
local UI = W.UI
local SV = {}
UI.StrategyView = SV
W.StrategyView = SV

local WIDTH, HEIGHT, ROW_H = 660, 520, 42
local CW, CH, CROW_H = 480, 330, 34

local K
local sv, cd                   -- the strategy window, and the confirmation over it
local scope, scopeRec          -- what the strategy is about: "opp" (one recipe, on its own) or "queue" (the whole crafting plan)
local TONE = { make = "tealHi", buy = "bronzeText", own = "textDim", collect = "sage", alt = "textDim", warn = "bronzeText" }

local function Money(c) return UI.Money(c) end

---------------------------------------------------------------------------
-- Rows of the strategy list
---------------------------------------------------------------------------
local function MakeRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.iconFrame = UI.ItemIcon(row, 26)
    row.iconFrame:SetPoint("LEFT", 10, 0)
    row.icon = row.iconFrame.tex
    row.right = UI.Text(row, 13, K.text, "strong")
    row.right:SetPoint("RIGHT", -10, 0)
    row.right:SetJustifyH("RIGHT")
    row.right:SetWidth(200)
    row.title = UI.Text(row, 13, K.text, "strong")
    row.title:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 9, 2)
    row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.detail = UI.Text(row, 11, K.textDim)
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.head = UI.Text(row, 13, K.bronzeText, "strong")
    row.head:SetPoint("LEFT", 10, -6)
    row.rule = UI.Rule(row, 0.45)
    row.rule:SetPoint("BOTTOMLEFT", 10, 4); row.rule:SetPoint("BOTTOMRIGHT", -10, 4)
    row.note = UI.Text(row, 12, K.textDim)
    row.note:SetPoint("LEFT", 14, 0)
    row.note:SetPoint("RIGHT", -10, 0)
    row.note:SetWordWrap(true)
    row.note:SetMaxLines(2)
    row.fill = function(self, d)
        local kind = d.kind
        local isHead, isNote = kind == "head", kind == "note"
        self.head:SetShown(isHead); self.rule:SetShown(isHead)
        self.note:SetShown(isNote)
        self.iconFrame:SetShown(not isHead and not isNote)
        self.title:SetShown(not isHead and not isNote); self.detail:SetShown(not isHead and not isNote); self.right:SetShown(not isHead and not isNote)
        if isHead then self.head:SetText(d.title) return end
        if isNote then self.note:SetText(d.title) return end
        local _, icon = O.ItemFacts(d.item or 0)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.title:SetText(d.title or "")
        self.detail:SetText(d.detail or "")
        self.right:SetText(d.right or "")
        UI.Paint(self.right, K[TONE[d.tone] or "text"])
    end
    return row
end

local function MakeOpRow(parent)
    local row = CreateFrame("Frame", nil, parent)
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
    row.fill = function(self, op)
        local _, icon = O.ItemFacts(op.produces or 0)
        self.icon:SetTexture(icon or UI.ICON_BLANK)
        self.title:SetText(("%s \195\151 %d"):format(op.name, op.crafts))
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
    local title = scope == "queue" and "Your crafting plan" or (scopeRec and scopeRec.name or "")
    sv.title:SetText("Crafting strategy")
    sv.sub:SetText(scope == "queue" and "The whole crafting plan, planned together: shared materials and what you own are counted once."
        or (title .. " \194\183 one craft, on its own"))
    local list = UI.lists.strategy
    if state ~= "ready" then
        for i = 1, 4 do Box(i).v:SetText("..."); UI.Paint(Box(i).v, K.stone) end
        sv.status:SetText(state == "planning" and "Planning..." or (state == "failed" and "The plan couldn't be worked out." or (why or "")))
        UI.Paint(sv.status, K.textDim)
        sv.add:SetEnabled(false)
        list:SetData({}, state == "planning" and "Working out the best way to get the materials..." or (state == "failed" and
            "The multilevel plan couldn't be worked out, so no strategy is shown. Shopping shows its basic list instead." or (why or "Nothing to show.")))
        return
    end
    local words = Sg.Summary(plan, Money)
    sv.status:SetText(words.status .. " \194\183 " .. words.actions)
    UI.Paint(sv.status, words.tone == "good" and K.sage or (words.tone == "warn" and K.bronzeText or K.textDim))
    local function Set(i, label, text, tone)
        local b = Box(i)
        b.l:SetText(label)
        b.v:SetText(text or "Unknown")
        UI.Paint(b.v, text and (tone == "good" and K.sage or (tone == "quiet" and K.stone or K.text)) or K.stone)
    end
    Set(1, "Buy ingredients directly", words.direct)
    Set(2, "Optimized economic cost", words.economic)
    Set(3, "Cash needed now", words.cash)
    Set(4, words.savingsLabel, words.savings, words.savingsTone)
    sv.savingsWhy = words.savingsWhy
    sv.add:SetEnabled(true)
    local rows = Sg.Detail(plan, UI.ItemName, Money, PR.AgeText, W.Queue.Now())
    list:SetData(rows, nil)
end

local function PaintConfirm()
    local state, plan, ops, key, why = S.PreviewOptimized(cd.rec)
    cd.key = key
    local list = UI.lists.confirm
    if state == "ready" and ops and #ops > 0 then
        cd.text:SetText(("%s will be added to your crafting plan. Nothing is crafted or bought for you."):format(
            #ops == 1 and "This craft" or "These crafts"))
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
    cd.heading:SetText("Add the optimized plan?")
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
    UI.Tip(cd.ok, "Add to plan", "Adds these crafts to your crafting plan as one change. Crafts already queued are counted, never added twice. Nothing is crafted or bought.")
    cd.cancel = UI.Button(cd, "Cancel", 100, "secondary", function() cd:Hide() end, 32)
    cd.cancel:SetPoint("RIGHT", cd.ok, "LEFT", -8, 0)
end

local function BuildStrategy(parent)
    sv = Dialog(parent, WIDTH, HEIGHT, 20)
    sv.title = UI.Text(sv, 24, K.text, "serif")
    sv.title:SetPoint("TOPLEFT", 18, -14)
    sv.sub = UI.Text(sv, 13, K.textDim)
    sv.sub:SetPoint("TOPLEFT", 19, -46)
    sv.sub:SetPoint("RIGHT", -18, 0)
    sv.status = UI.Text(sv, 13, K.sage, "strong")
    sv.status:SetPoint("TOPLEFT", 19, -68)
    sv.status:SetPoint("RIGHT", -18, 0)
    sv.boxes = {}
    local gap = 8
    local bw = math.floor((WIDTH - 36 - 3 * gap) / 4)
    for i = 1, 4 do
        local b = CreateFrame("Frame", nil, sv)
        b:SetSize(bw, 46)
        b:SetPoint("TOPLEFT", 18 + (i - 1) * (bw + gap), -92)
        UI.Panel(b, "canvas")
        b:EnableMouse(true)
        b.l = UI.Text(b, 11, K.stone)
        b.l:SetPoint("TOPLEFT", 10, -7)
        b.l:SetPoint("RIGHT", -6, 0)
        b.v = UI.Text(b, 13, K.text, "strong")
        b.v:SetPoint("BOTTOMLEFT", 10, 7)
        b.v:SetPoint("RIGHT", -6, 0)
        sv.boxes[i] = b
    end
    UI.Tip(sv.boxes[1], "Buy ingredients directly", "What it would cost to get every material the plan lacks by buying it, without making anything on the way. Owned materials are counted at what they would cost.")
    UI.Tip(sv.boxes[2], "Optimized economic cost", "The cost of the best plan found, counting the materials you already own at what they would cost (owning them does not make them free). A range when the auction prices are only known as a range.")
    UI.Tip(sv.boxes[3], "Cash needed now", "Only what is bought: vendors and the auction house. Materials you own, or collect from storage, are not part of it. Whole stacks may have to be bought.")
    UI.TipFn(sv.boxes[4], "Savings", function()
        return (sv.savingsWhy and (sv.savingsWhy .. " ") or "") .. "It compares the plan's economic cost with buying directly. It is not a profit: selling prices are not part of it."
    end)
    local list = UI.List(sv, ROW_H, MakeRow, 160, "canvas")
    list.box:SetPoint("TOPLEFT", 14, -146)
    list.box:SetPoint("BOTTOMRIGHT", -14, 56)
    UI.lists.strategy = list
    sv.close = UI.Button(sv, "Close", 100, "secondary", function() sv:Hide() end, 32)
    sv.close:SetPoint("BOTTOMRIGHT", -16, 14)
    sv.add = UI.Button(sv, "Add optimized plan", 190, "primary", function() SV.Confirm() end, 32)
    sv.add:SetPoint("RIGHT", sv.close, "LEFT", -8, 0)
    UI.Tip(sv.add, "Add optimized plan", "Shows what would be added to your crafting plan and asks you to confirm. Nothing changes until you do.")
    sv.hint = UI.Text(sv, 11, K.stone)
    sv.hint:SetPoint("BOTTOMLEFT", 18, 14)
    sv.hint:SetWidth(WIDTH - 18 - 100 - 190 - 40)
    sv.hint:SetHeight(30)
    sv.hint:SetJustifyH("LEFT")
    sv.hint:SetJustifyV("MIDDLE")
    sv.hint:SetWordWrap(true)
    sv.hint:SetText("Owned materials lower the cash you spend, not the economic cost.")
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
function SV.IsOpen() return sv ~= nil and sv:IsShown() end

-- "Add optimized plan": the confirmation. Nothing is added here.
function SV.Confirm()
    if not (sv and sv:IsShown()) then return false end
    cd.rec = scope == "opp" and scopeRec or nil
    cd:Show()
    PaintConfirm()
    UI.lists.confirm:ScrollTop()
    return true
end

function SV.Frames() return sv, cd end   -- (the tests and the simulator scenario)
