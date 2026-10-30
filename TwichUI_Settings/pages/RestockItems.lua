-- TwichUI settings: Restock items (modules/Restock.lua). The items vendor restocking keeps in your bags, each with
-- its target, an on/off box, its place in the order and Remove; adding one by dropping it from your bags or typing its
-- item ID; and suggestions for your class's reagents. A frame of this window's own, shown as the tab's page, since a
-- list of items with their own controls doesn't fit the ordinary rows. Built the first time the tab is shown; list
-- rows are made as they are first needed and reused on every redraw.
-- Names and icons are the game's own. An item the game hasn't loaded shows as loading (asked for at most twice); one
-- the game says doesn't exist says so. Nothing here buys, sells or moves anything: a dropped item goes straight back
-- to where it was picked up from. Every change goes through Restock.lua's own functions.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.RestockItemsPage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 32, 6
local LIST_TOP = -140
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26     -- inside the well, less the scroll bar
local NAME_W = 250
local TARGET_X, CHECK_X, UP_X = 300, 382, 424
local SUG_TOP = LIST_TOP - LIST_H - 14
local SUG_W, SUG_H = W / 2, 28
local MAX_REQUESTS = 2         -- times the game is asked to load one item's details while this is open
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f, built
local rows = {}
local sugButtons = {}
local requested, missing = {}, {}   -- [id] = times asked; [id] = true once the game said there is no such item
local sugClass                      -- the class whose suggestions are shown (default: yours)
local refreshQueued = false

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Wg() return R.SettingsWidgets end

---------------------------------------------------------------------------
-- What the game says about an item: name, icon, and "ok" | "loading" | "missing"
---------------------------------------------------------------------------
local function ItemInfo(id)
    local icon = C_Item.GetItemIconByID and Plain(C_Item.GetItemIconByID(id))
    if not icon and C_Item.GetItemInfoInstant then
        local _, _, _, _, i = C_Item.GetItemInfoInstant(id)
        icon = Plain(i)
    end
    local name = C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
    if not name and C_Item.GetItemInfo then name = Plain((C_Item.GetItemInfo(id))) end
    if type(name) == "string" and name ~= "" then return name, icon, "ok" end
    if missing[id] then return nil, icon, "missing" end
    if (requested[id] or 0) < MAX_REQUESTS and C_Item.RequestLoadItemDataByID then
        requested[id] = (requested[id] or 0) + 1
        C_Item.RequestLoadItemDataByID(id)
    end
    return nil, icon, "loading"
end
P.ItemInfo = ItemInfo

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

---------------------------------------------------------------------------
-- The line under the add area: what just happened, or why it didn't
---------------------------------------------------------------------------
function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.textDim))
end

---------------------------------------------------------------------------
-- Adding
---------------------------------------------------------------------------
local function Added(id, how)
    local name = ItemInfo(id) or ("item " .. id)
    if how == "exists" then
        P.Say(("%s is already on your list, so nothing was added. Here it is."):format(name), "ok")
    else
        P.Say(("Added %s. Set how many to keep; it is bought when a merchant sells it and you have fewer."):format(name), "ok")
    end
    P.Refresh()
    P.Focus(id)
end

-- From the item ID box. Returns true, "added" | "exists", or false, why.
function P.AddFromText(text)
    if type(text) ~= "string" or text:match("^%s*$") then return false, "empty" end
    local ok, a, how = R.Restock.Add(text)
    if not ok then
        P.Say(a, "warn")
        return false, a
    end
    if f and f.idBox then
        f.idBox:SetText("")
        f.idBox:ClearFocus()
    end
    Added(R.Restock.ParseItem(text), how)
    return true, how
end

-- From what is on the cursor (dropped on the box, or clicked onto it). An item goes straight back where it was
-- picked up from; anything else is left on the cursor and refused.
function P.AddFromCursor()
    local kind, id = GetCursorInfo()
    if kind == nil then return false, "empty" end
    if kind ~= "item" then
        P.Say("Only items can be added. Drag an item from your bags, or type its item ID.", "warn")
        return false, "not-item"
    end
    ClearCursor()
    local ok, a, how = R.Restock.Add(Plain(id))
    if not ok then
        P.Say(a, "warn")
        return false, a
    end
    Added(Plain(id), how)
    return true, how
end

function P.AddSuggestion(id)
    local RS = R.Restock
    if RS.Rule(id) then
        Added(id, "exists")
        return true, "exists"
    end
    local ok, a, how = RS.AddSuggestion(sugClass or RS.PlayerClass(), id)
    if not ok then
        P.Say(a, "warn")
        return false, a
    end
    Added(id, how)
    return true, how
end

local function Remove(id)
    local name = ItemInfo(id) or ("item " .. id)
    if R.Restock.Remove(id) then
        P.Say(("Removed %s from your list. Nothing in your bags was touched."):format(name), "ok")
    end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function ItemTip(owner, id, extra)
    if not (GameTooltip and id) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(id) else GameTooltip:SetText(ItemInfo(id) or ("Item " .. id), 1, 1, 1) end
    for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

local function Row(i)
    if rows[i] then return rows[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local row = CreateFrame("Button", nil, f.content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.bg:SetAllPoints()
    row.flash = G.Solid(row, "BACKGROUND", pal.teal, 0.22)
    row.flash:SetAllPoints()
    row.flashFade = G.Motion.Fader(function(a) row.flash:SetAlpha(a) end, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 38, -3)
    row.name:SetWidth(NAME_W)
    row.name:SetWordWrap(false)
    row.status = G.Text(row, "meta")
    row.status:SetPoint("TOPLEFT", 38, -18)
    row.status:SetWidth(NAME_W)
    row.status:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        ItemTip(self, self.id, { self.status:GetText() })
    end)
    row:SetScript("OnLeave", function(self) I.HideTip(self) end)
    row:SetScript("OnHide", function(self) I.HideTip(self) end)

    row.target = G.EditBox(row, 56, 20)
    row.target:SetPoint("LEFT", TARGET_X, 0)
    row.target:SetNumeric(true)
    row.target:SetMaxLetters(4)
    row.target:SetJustifyH("RIGHT")
    row.target.commit = function(self)
        local rule = row.id and R.Restock.Rule(row.id)   -- as saved now, not as last drawn
        if not rule then return end
        if self.revert then
            self.revert = nil
            self:SetText(tostring(rule.target))
            return
        end
        local text = (self:GetText() or ""):gsub("%s+", "")
        local value = tonumber(text)
        if value == rule.target then return end
        local ok, why = R.Restock.SetTarget(rule.id, value)
        if not ok then
            P.Say(why, "warn")
            self:SetText(tostring(rule.target))
        end
    end
    row.target:SetScript("OnEnterPressed", row.target.ClearFocus)
    row.target:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    row.target:HookScript("OnEditFocusLost", function(self) self:commit() end)   -- (hooked: the field's own focus ring stays)
    I.Tip(row.target, "Keep in bags", ("How many to keep in your carried bags, from 1 to %d. TwichUI buys only the difference, never more. Press Enter to save; Esc puts the old number back."):format(R.Restock.MAX_TARGET))

    row.check = G.Checkbox(row, function(on) if row.rule then R.Restock.SetRuleEnabled(row.rule.id, on) end end)
    row.check:SetPoint("LEFT", CHECK_X, 0)
    I.Tip(row.check, "On", "On: restocked when a merchant sells it. Off: kept on the list with its target, and not bought.")

    row.up = G.ArrowButton(row, "up", function() if row.rule then R.Restock.Move(row.rule.id, -1) end end)
    row.up:SetPoint("LEFT", UP_X, 0)
    I.Tip(row.up, "Move up", "Higher in the list is bought first when money or your spending limit can't cover everything.")
    row.down = G.ArrowButton(row, "down", function() if row.rule then R.Restock.Move(row.rule.id, 1) end end)
    row.down:SetPoint("LEFT", UP_X + 22, 0)
    I.Tip(row.down, "Move down", "Lower in the list is bought after the items above it.")

    row.remove = G.Button(row, "Remove", 76, "secondary", function() if row.rule then Remove(row.rule.id) end end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Takes the item off your list, so it is no longer restocked. Nothing in your bags is sold, moved or deleted.")
    rows[i] = row
    return row
end

local function Status(rule, carried, state)
    if state == "missing" then return ("The game has no item with the ID %d. Remove it, or check the number."):format(rule.id), "warn" end
    if state == "loading" then return "Loading the item's details...", nil end
    if carried == nil then return "Couldn't count it in your bags right now.", nil end
    if not rule.enabled then return ("Off: you carry %d. Kept on the list, not bought."):format(carried), nil end
    if carried >= rule.target then return ("You carry %d: at your target."):format(carried), "ok" end
    return ("You carry %d: buys up to %d more at a merchant that sells it."):format(carried, rule.target - carried), nil
end

---------------------------------------------------------------------------
-- Suggestions
---------------------------------------------------------------------------
local function SugButton(i)
    if sugButtons[i] then return sugButtons[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local b = CreateFrame("Button", nil, f, "BackdropTemplate")
    b:SetSize(SUG_W - 6, SUG_H - 4)
    local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetPoint("TOPLEFT", col * SUG_W, f.sugGridTop - line * SUG_H)
    G.Surface(b, pal.well, 0.7, pal.bronzeLo, 0.7)
    G.Hover(b, pal.text, 0.05)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("LEFT", 5, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.name = G.Text(b, "small")
    b.name:SetPoint("LEFT", 28, 0)
    b.name:SetWidth(SUG_W - 6 - 28 - 96)
    b.name:SetWordWrap(false)
    b.right = G.Text(b, "meta")
    b.right:SetPoint("RIGHT", -8, 0)
    b.right:SetJustifyH("RIGHT")
    b:SetScript("OnClick", function(self) if self.id then P.AddSuggestion(self.id) end end)
    b:SetScript("OnEnter", function(self)
        if not self.s then return end
        ItemTip(self, self.s.id, { "For: " .. self.s.use, ("Suggested target: %d."):format(self.s.target),
            self.s.listed and "On your list: click to find it." or "Click to add it to your list." })
    end)
    b:SetScript("OnLeave", function(self) I.HideTip(self) end)
    b:SetScript("OnHide", function(self) I.HideTip(self) end)
    sugButtons[i] = b
    return b
end

local function SugChoices()
    local RS = R.Restock
    local mine = RS.PlayerClass()
    local out = {}
    -- (the dropdown's own shape: { value, label }, not the Kit's positional { value, label } lists)
    for _, class in ipairs(RS.SUGGESTION_CLASSES) do
        out[#out + 1] = { value = class, label = ClassName(class) .. (class == mine and "  (your class)" or "") }
    end
    return out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local RS, G = R.Restock, Wg()
    local pal = G.pal
    local list = RS.Rules()
    local wanted = {}
    for _, rule in ipairs(list) do wanted[rule.id] = true end
    local scan = RS.ScanBags(wanted)
    for i, rule in ipairs(list) do
        local row = Row(i)
        row.id, row.rule = rule.id, rule
        local name, icon, state = ItemInfo(rule.id)
        row.icon:SetTexture(icon or QUESTION)
        row.icon:SetDesaturated(not rule.enabled)
        row.name:SetText(name or ("Item " .. rule.id))
        G.Color(row.name, rule.enabled and pal.text or pal.stone)
        local text, tone = Status(rule, not scan.unknown[rule.id] and scan.counts[rule.id] or nil, state)
        row.status:SetText(text)
        G.Color(row.status, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.stone))
        if not row.target:HasFocus() then row.target:SetText(tostring(rule.target)) end
        row.check:SetChecked(rule.enabled)
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].id, rows[i].rule = nil, nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.empty:SetShown(#list == 0)
    f.count:SetText(("%d of %d"):format(#list, RS.MAX_ITEMS))

    local class = sugClass or RS.PlayerClass()
    local suggestions = RS.Suggestions(class)
    f.sugClass:SetValue(class, class and ClassName(class) or "")
    f.sugNone:SetShown(#suggestions == 0)
    if #suggestions == 0 then
        f.sugNone:SetText(class and ("TwichUI has no vendor reagents to suggest for %s. Choose another class to see theirs, or add items above."):format(ClassName(class))
            or "Choose a class to see its reagents.")
    end
    for i, s in ipairs(suggestions) do
        local b = SugButton(i)
        b.id, b.s = s.id, s
        local name, icon = ItemInfo(s.id)
        b.icon:SetTexture(icon or QUESTION)
        b.name:SetText(name or "Loading...")
        b.right:SetText(s.listed and "On your list" or "Add")
        G.Color(b.right, s.listed and pal.stone or pal.tealHi)
        b:Show()
    end
    for i = #suggestions + 1, #sugButtons do
        sugButtons[i].id, sugButtons[i].s = nil, nil
        sugButtons[i]:Hide()
    end
end

-- Brings an item's row into view and puts the cursor in its target box, with a brief highlight.
function P.Focus(id)
    if not (f and built) then return end
    for i, row in ipairs(rows) do
        if row.id == id and row:IsShown() then
            local top = (i - 1) * ROW_H
            local view = f.scroll:GetHeight() or LIST_H
            local offset = f.scroll:GetVerticalScroll() or 0
            if top < offset or top + ROW_H > offset + view then
                local most = f.scroll:GetVerticalScrollRange() or 0
                f.scroll:SetVerticalScroll(math.max(0, math.min(most, top - ROW_H)))
            end
            row.flashFade:Set(1)
            row.flashFade:To(0, 0.8)
            row.target:SetFocus()
            row.target:HighlightText()
            return
        end
    end
end

-- Many changes at once (a burst of bag updates, items loading) are one redraw.
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

local EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }

local function OnEvent(_, event, id, success)
    if event == "ITEM_DATA_LOAD_RESULT" and success == false and requested[id] then missing[id] = true end
    QueueRefresh()
end

local function Build()
    built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal

    f.help = G.Text(f, "small")
    f.help:SetPoint("TOPLEFT", 4, -2)
    f.help:SetWidth(W - 8)
    f.help:SetText("Each item has a target: how many to keep in your carried bags. Keep 20: if you have 7 and a merchant sells it, TwichUI tries to buy 13. Higher in the list is bought first when money or your spending limit runs short.")

    -- the add area: a box to drop an item on, or its item ID
    G.Card(f, 0, -38, W, -98)
    f.drop = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.drop:SetSize(40, 40)
    f.drop:SetPoint("TOPLEFT", 12, -48)
    G.Well(f.drop)
    f.drop.plus = G.Text(f.drop, "title")
    f.drop.plus:SetPoint("CENTER", 0, 1)
    f.drop.plus:SetText("+")
    G.Color(f.drop.plus, pal.stone)
    f.drop:RegisterForClicks("LeftButtonUp")
    f.drop:SetScript("OnReceiveDrag", P.AddFromCursor)
    f.drop:SetScript("OnClick", P.AddFromCursor)
    f.drop:SetScript("OnEnter", function(self)
        local holding = GetCursorInfo() == "item"
        local c = holding and pal.tealHi or pal.control
        self:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        G.Color(self.plus, holding and pal.tealHi or pal.stone)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add an item", 1, 1, 1)
        GameTooltip:AddLine("Drop an item from your bags here. It goes straight back into your bags; only its item ID is noted.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    f.drop:SetScript("OnLeave", function(self)
        local c = pal.bronzeLo
        self:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
        G.Color(self.plus, pal.stone)
        I.HideTip(self)
    end)
    f.dropLabel = G.Text(f, "body")
    f.dropLabel:SetPoint("TOPLEFT", 62, -52)
    f.dropLabel:SetText("Drop an item from your bags on the box")
    f.dropSub = G.Text(f, "meta")
    f.dropSub:SetPoint("TOPLEFT", 62, -70)
    f.dropSub:SetWidth(W - 62 - 230)
    f.dropSub:SetText("The item stays in your bags. It doesn't have to be sold here.")

    f.idLabel = G.Text(f, "meta")
    f.idLabel:SetPoint("TOPLEFT", W - 214, -46)
    f.idLabel:SetText("or type its item ID")
    f.idBox = G.EditBox(f, 104, 22)
    f.idBox:SetPoint("TOPLEFT", W - 214, -62)
    f.idBox:SetNumeric(true)
    f.idBox:SetMaxLetters(10)
    f.idBox:SetScript("OnEnterPressed", function(self) P.AddFromText(self:GetText()) end)
    f.idBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    I.Tip(f.idBox, "Item ID", "The number in an item's link or on a database site. Press Enter or Add. Unknown numbers are refused.")
    f.add = G.Button(f, "Add", 90, "secondary", function() P.AddFromText(f.idBox:GetText()) end)
    f.add:SetPoint("TOPLEFT", W - 102, -62)

    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", 4, -104)
    f.note:SetWidth(W - 8)
    f.note:SetWordWrap(false)
    P.Say(P.lastSaid, P.lastTone)

    -- the list
    local function Column(text, x)
        local t = G.Text(f, "meta")
        t:SetPoint("TOPLEFT", 6 + x, -124)
        t:SetText(text)
        return t
    end
    Column("Item", 38)
    Column("Keep", TARGET_X + 12)
    Column("On", CHECK_X)
    Column("Order", UP_X)
    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPRIGHT", -8, -124)
    f.count:SetJustifyH("RIGHT")
    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(W, LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, LIST_W)
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -14)
    f.empty:SetWidth(W - 24)
    f.empty:SetText("Nothing on your list yet. Drop an item above, type its item ID, or add a class reagent below.")

    -- class reagents
    f.sugTitle = G.Text(f, "heading")
    f.sugTitle:SetPoint("TOPLEFT", 4, SUG_TOP)
    f.sugTitle:SetText("Class reagents")
    f.sugClass = G.Dropdown(f, 180, function(value)
        sugClass = value
        P.Refresh()
    end)
    f.sugClass:SetChoices(SugChoices)
    f.sugClass:SetPoint("TOPRIGHT", -2, SUG_TOP + 4)
    I.Tip(f.sugClass, "Class", "Shows your class's reagents first. Choose another class to see theirs.")
    f.sugHelp = G.Text(f, "small")
    f.sugHelp:SetPoint("TOPLEFT", 4, SUG_TOP - 20)
    f.sugHelp:SetWidth(W - 8)
    f.sugHelp:SetText("Add the ones you use; each starts with a suggested target you can change. Which you need depends on your spells and their ranks, which these don't check.")
    f.sugGridTop = SUG_TOP - 48
    f.sugNone = G.Text(f, "small")
    f.sugNone:SetPoint("TOPLEFT", 4, f.sugGridTop)
    f.sugNone:SetWidth(W - 8)
end

-- The page's frame (the settings window shows it under Vendor restocking). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function(self)
        if not built then Build() end
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh()
    end)
    f:SetScript("OnHide", function(self)
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
        if f.idBox then f.idBox:ClearFocus() end
        if f.drop then R.Interact.HideTip(f.drop) end
    end)
    f:SetScript("OnEvent", OnEvent)
    return f
end

-- A change made anywhere (here, a profile change, an import) redraws the list if it is shown. Registered once.
if R.Restock then
    R.Restock.OnChange(QueueRefresh)
    R.Profiles.OnApply("views", "restock-items", QueueRefresh)
end

K.Page({
    key = "restockItems", name = "Restock items", parent = "restock", order = 46,
    description = "The items vendor restocking keeps in your bags, how many of each, and suggestions for your class's reagents.",
    keywords = "restock list item id drop drag target keep reagent reagents suggestions class ammo arrows",
    when = function() return R.Restock ~= nil end,
    host = function() return P.Frame() end,
})
