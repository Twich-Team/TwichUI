-- TwichUI settings: Custom ammunition (ammo/Items.lua). The ammunition you registered for the Hunter warning, each with
-- what it is (arrows or bullets) and Remove; adding one by dropping it from your bags, pasting its link or typing its
-- item ID. A frame of this window's own, shown as the tab's page, since a list of items with their own controls doesn't
-- fit the ordinary rows. Built the first time the tab is shown; list rows are made as they are first needed and reused
-- on every redraw.
-- Names and icons are the game's own. An item the game hasn't loaded shows as loading (asked for at most twice); one the
-- game says doesn't exist says so, and stays registered. Nothing here equips, moves or counts anything: a dropped item
-- goes straight back to where it was picked up from. Every change goes through AmmoItems.lua's own functions.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.AmmoItemsPage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 32, 6
local HELP_H = 62
local ADD_TOP = -(HELP_H + 4)
local LIST_TOP = ADD_TOP - 60 - 40
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26     -- inside the well, less the scroll bar
local NAME_W = 330
local KIND_X = 396
local MAX_REQUESTS = 2         -- times the game is asked to load one item's details while this is open
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local f, built
local rows = {}
local requested, missing = {}, {}   -- [id] = times asked; [id] = true once the game said there is no such item
local addKind = "auto"              -- what the next item added is registered as: "auto", "arrow" or "bullet" (this page only; not saved)
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

local function KindChoices()
    local out = {}
    for i, k in ipairs(R.AmmoItems.KINDS) do out[i] = { value = k[1], label = k[2] } end
    return out
end

local function AddChoices()
    local out = { { value = "auto", label = "Automatic" } }
    for _, k in ipairs(KindChoices()) do out[#out + 1] = k end
    return out
end

local function AddKindLabel()
    return addKind == "auto" and "Automatic" or R.AmmoItems.KindLabel(addKind)
end

-- The line under an item: what the game says it is, and which of the two decides.
local function StatusText(entry, state)
    local AI = R.AmmoItems
    if state == "missing" then
        return "The game has no item with this ID yet. It stays registered in case it appears; remove it if it was a typo.", "warn"
    end
    if state == "loading" then return "Loading the item's details...", nil end
    local client = AI.Classify(entry.id)
    local mine = AI.KindLabel(entry.kind):lower()
    if client == "arrow" or client == "bullet" then
        if client == entry.kind then return ("The game lists it as %s too."):format(mine), "ok" end
        return ("The game lists it as %s. Your registration as %s decides."):format(AI.KindLabel(client):lower(), mine), nil
    end
    if client == "other" then return ("The game lists it as another kind of projectile. Your registration as %s decides."):format(mine), nil end
    if client == false then return ("The game does not list it as ammunition. Your registration as %s decides."):format(mine), nil end
    return ("The game has not classified it. Your registration as %s decides."):format(mine), nil
end

---------------------------------------------------------------------------
-- The line under the add area: what just happened, or why it didn't
---------------------------------------------------------------------------
function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.tealHi or pal.textDim))
end

---------------------------------------------------------------------------
-- Adding and removing
---------------------------------------------------------------------------
local function Added(id, how, kind)
    local name = ItemInfo(id) or ("item " .. id)
    if how == "exists" then
        P.Say(("%s is already registered, so nothing was changed. Here it is."):format(name), "ok")
    else
        P.Say(("Registered %s as %s. Nothing in your bags or equipment was touched."):format(name, R.AmmoItems.KindLabel(kind):lower()), "ok")
    end
    P.Refresh()
    P.Focus(id)
end

-- From the item ID box (an ID, or a pasted item link). Returns true, "added" | "exists", or false, why.
function P.AddFromText(text)
    if type(text) ~= "string" or text:match("^%s*$") then return false, "empty" end
    local ok, how, kind = R.AmmoItems.Add(text, addKind ~= "auto" and addKind or nil)
    if not ok then
        P.Say(how, "warn")
        return false, how
    end
    if f and f.idBox then
        f.idBox:SetText("")
        f.idBox:ClearFocus()
    end
    Added(R.AmmoItems.ParseItem(text), how, kind)
    return true, how, kind
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
    id = Plain(id)
    local ok, how, kind = R.AmmoItems.Add(id, addKind ~= "auto" and addKind or nil)
    if not ok then
        P.Say(how, "warn")
        return false, how
    end
    Added(id, how, kind)
    return true, how
end

local function Remove(id)
    local name = ItemInfo(id) or ("item " .. id)
    if R.AmmoItems.Remove(id) then
        P.Say(("Removed %s from your list. Nothing in your bags or equipment was touched."):format(name), "ok")
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

    row.kind = G.Dropdown(row, 110, function(value)
        if row.id and value then
            local ok, why = R.AmmoItems.SetKind(row.id, value)
            if not ok then P.Say(why, "warn") end
        end
    end)
    row.kind:SetChoices(KindChoices)
    row.kind:SetPoint("LEFT", KIND_X, 0)
    I.Tip(row.kind, "What it is", "Arrows or bullets. Your choice decides what this item counts as, over the game's own classification. Correct it here if it was registered wrongly.")

    row.remove = G.Button(row, "Remove", 76, "secondary", function() if row.id then Remove(row.id) end end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Forgets the registration, so the item is recognized only as the game itself classifies it. Nothing in your bags or equipment is sold, moved or deleted.")
    rows[i] = row
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local AI, G = R.AmmoItems, Wg()
    local pal = G.pal
    local list = AI.List()
    for i, entry in ipairs(list) do
        local row = Row(i)
        row.id = entry.id
        local name, icon, state = ItemInfo(entry.id)
        row.icon:SetTexture(icon or QUESTION)
        row.name:SetText(name or ("Item " .. entry.id))
        G.Color(row.name, pal.text)
        local text, tone = StatusText(entry, state)
        row.status:SetText(text)
        G.Color(row.status, tone == "warn" and pal.danger.text or (tone == "ok" and pal.tealHi or pal.stone))
        row.kind:SetValue(entry.kind, AI.KindLabel(entry.kind))
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].id = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.empty:SetShown(#list == 0)
    f.count:SetText(("%d of %d"):format(#list, AI.MAX))
    f.addKind:SetValue(addKind, AddKindLabel())
end

-- Brings an item's row into view with a brief highlight.
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
            return
        end
    end
end

-- Many changes at once (items loading, a profile change) are one redraw.
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

-- Only while the page is shown: the game's answers about the items listed here.
local EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

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
    f.help:SetText("TwichUI already recognizes the game's own arrows and bullets. Register an item here only when the game doesn't classify it the way you need, such as one a server added. This says what an item is; it doesn't equip it, count it or make it fit your weapon. The warning still reads your equipment and bags each time.")

    -- the add area: a box to drop an item on, or its item ID or link
    G.Card(f, 0, ADD_TOP, W, ADD_TOP - 60)
    f.drop = CreateFrame("Button", nil, f, "BackdropTemplate")
    f.drop:SetSize(40, 40)
    f.drop:SetPoint("TOPLEFT", 12, ADD_TOP - 10)
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
        GameTooltip:SetText("Register an item", 1, 1, 1)
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
    f.dropLabel:SetPoint("TOPLEFT", 62, ADD_TOP - 14)
    f.dropLabel:SetText("Drop an item from your bags on the box")
    f.dropSub = G.Text(f, "meta")
    f.dropSub:SetPoint("TOPLEFT", 62, ADD_TOP - 32)
    f.dropSub:SetWidth(W - 62 - 330)
    f.dropSub:SetText("or paste its link or type its item ID")

    f.idBox = G.EditBox(f, 104, 22)
    f.idBox:SetPoint("TOPLEFT", W - 330, ADD_TOP - 30)
    f.idBox:SetMaxLetters(200)
    f.idBox:SetScript("OnEnterPressed", function(self) P.AddFromText(self:GetText()) end)
    f.idBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    I.Tip(f.idBox, "Item ID or link", "The number in an item's link or on a database site, or the link itself pasted here. Press Enter or Add.")
    f.addKindLabel = G.Text(f, "meta")
    f.addKindLabel:SetPoint("TOPLEFT", W - 214, ADD_TOP - 8)
    f.addKindLabel:SetText("register it as")
    f.addKind = G.Dropdown(f, 110, function(value) addKind = value end)
    f.addKind:SetChoices(AddChoices)
    f.addKind:SetPoint("TOPLEFT", W - 214, ADD_TOP - 26)
    I.Tip(f.addKind, "Register it as", "What the next item you add counts as. Automatic uses the game's own classification when it has one, and arrows when it doesn't. You can correct an item in the list afterwards.")
    f.add = G.Button(f, "Add", 80, "secondary", function() P.AddFromText(f.idBox:GetText()) end)
    f.add:SetPoint("TOPLEFT", W - 94, ADD_TOP - 28)

    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", 4, ADD_TOP - 66)
    f.note:SetWidth(W - 8)
    f.note:SetWordWrap(false)
    P.Say(P.lastSaid, P.lastTone)

    -- the list
    local function Column(text, x)
        local t = G.Text(f, "meta")
        t:SetPoint("TOPLEFT", 6 + x, LIST_TOP + 16)
        t:SetText(text)
        return t
    end
    Column("Item", 38)
    Column("It is", KIND_X + 4)
    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPRIGHT", -8, LIST_TOP + 16)
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
    f.empty:SetText("Nothing registered. The game's own arrows and bullets are recognized without this list.")
end

-- The page's frame (the settings window shows it under Ammunition warning). Built the first time it is shown.
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
if R.AmmoItems then
    R.AmmoItems.OnChange(QueueRefresh)
end

K.Page({
    key = "ammoCustom", name = "Custom ammunition", nav = "Custom ammunition", parent = "ammo", order = 53,
    description = "Ammunition you register yourself, such as an item a server added, as arrows or bullets.",
    keywords = "ammo ammunition custom register arrows bullets item id link server hunter quiver list",
    when = function() return R.AmmoItems ~= nil end,
    host = function() return P.Frame() end, hostHeight = LIST_H + 190,
})
