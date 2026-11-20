-- TwichUI settings: Known ammunition (reminders/AmmoItems.lua). The ammunition you registered for ammunition reminders, each with
-- what it is (arrows or bullets) and Remove; adding one by dropping it from your bags, pasting its link or typing its
-- item ID. A frame of this window's own, shown as the tab's page, since a list of items with their own controls doesn't
-- fit the ordinary rows. Built the first time the tab is shown; list rows are made as they are first needed and reused
-- on every redraw.
-- Names and icons are the game's own. An item the game hasn't loaded shows as loading (asked for at most twice); one the
-- game says doesn't exist says so, and stays registered. Nothing here equips, moves or counts anything: a dropped item
-- goes straight back to where it was picked up from. Every change goes through reminders/AmmoItems.lua's own functions.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.AmmoItemsPage = P

local W = 644                  -- the width the page is first built at; it follows the hosted frame's width after that
local ROW_H, VISIBLE = 56, 5
local HELP_H = 46
local ADD_TOP = -(HELP_H + 4)
local ADD_H, MANUAL_H = 64, 40 -- the add card, and the manual entry line it grows by when shown
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26     -- inside the well, less the scroll bar (follows the width)
local NAME_W = 330
local KIND_X = 396
local manualShown = false      -- the item ID / link entry and "register it as" (this page only; not saved)
local function ListTop() return ADD_TOP - ADD_H - (manualShown and MANUAL_H or 0) - 40 end
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
        return "Item unavailable · registration kept", "warn"
    end
    if state == "loading" then return "Loading the item's details...", nil end
    local client = AI.Classify(entry.id)
    local mine = AI.KindLabel(entry.kind):lower()
    if client == "arrow" or client == "bullet" then
        if client == entry.kind then return "Matches game classification", "ok" end
        return ("Game: %s · your choice: %s"):format(AI.KindLabel(client):lower(), mine), nil
    end
    if client == "other" then return "Game: other projectile · your choice applies", nil end
    if client == false then return "Game: not ammunition · your choice applies", nil end
    return "Game classification unavailable · your choice applies", nil
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
-- Adding and removing
---------------------------------------------------------------------------
local function Added(id, how, kind)
    local name = ItemInfo(id) or ("item " .. id)
    if how == "exists" then
        P.Say(("%s is already registered, so nothing was changed. Here it is."):format(name), "ok")
    else
        P.Say(("Registered as %s. Nothing in your bags or equipment was touched."):format(R.AmmoItems.KindLabel(kind):lower()), "ok")
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
    row.place = function(self)
        self:SetWidth(LIST_W)
        self.name:SetWidth(NAME_W); self.status:SetWidth(NAME_W)
        self.kind:ClearAllPoints(); self.kind:SetPoint("LEFT", KIND_X, 0)
    end
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)

    row.flash = G.Solid(row, "BACKGROUND", pal.teal, 0.22)
    row.flash:SetAllPoints()
    row.flashFade = G.Motion.Fader(function(a) row.flash:SetAlpha(a) end, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 38, -7)
    row.name:SetWidth(NAME_W)
    row.name:SetWordWrap(true)
    row.name:SetHeight(30)
    row.status = G.Text(row, "meta")
    row.status:SetPoint("TOPLEFT", 38, -39)
    row.status:SetWidth(NAME_W)
    row.status:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        if not self.id then return end
        ItemTip(self, self.id, { self.name:GetText(), self.status:GetText() })
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
    I.Tip(row.kind, "Classification", "Arrows or bullets. Set automatically when the item is added; change it only to correct it. Your choice decides what this item counts as, over the game's own classification.")

    row.remove = G.Button(row, "Remove", 76, "secondary", function() if row.id then Remove(row.id) end end)
    row.remove:SetPoint("RIGHT", -6, 0)
    I.Tip(row.remove, "Remove", "Forgets the registration, so the item is recognized only as the game itself classifies it. Nothing in your bags or equipment is sold, moved or deleted.")
    rows[i] = row
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local laidOut
-- Places what depends on the page's width and on whether the manual entry is shown.
local function Relayout()
    local width = math.max(520, (f:GetWidth() and f:GetWidth() > 1) and f:GetWidth() or W)
    local key = width .. (manualShown and "m" or "")
    if key == laidOut then return end
    laidOut = key
    LIST_W = width - 12 - 26
    KIND_X = LIST_W - 6 - 76 - 16 - 110
    NAME_W = KIND_X - 38 - 12
    local listTop = ListTop()
    f.help:SetWidth(width - 8)
    local addBottom = ADD_TOP - ADD_H - (manualShown and MANUAL_H or 0)
    if f.card and f.card.SetBounds then f.card:SetBounds(0, ADD_TOP, width, addBottom) end
    f.dropSub:SetWidth(width - 62 - 200)
    f.manual:ClearAllPoints(); f.manual:SetPoint("TOPRIGHT", f, "TOPLEFT", width - 12, ADD_TOP - 18)
    for _, c in ipairs({ f.idLabel, f.idBox, f.addKindLabel, f.addKind, f.add }) do c:SetShown(manualShown) end
    local my = ADD_TOP - ADD_H + 4
    f.idLabel:ClearAllPoints(); f.idLabel:SetPoint("TOPLEFT", 14, my - 4)
    f.idBox:ClearAllPoints(); f.idBox:SetPoint("TOPLEFT", 120, my)
    f.addKindLabel:ClearAllPoints(); f.addKindLabel:SetPoint("TOPLEFT", 238, my - 4)
    f.addKind:ClearAllPoints(); f.addKind:SetPoint("TOPLEFT", 330, my)
    f.add:ClearAllPoints(); f.add:SetPoint("TOPLEFT", 450, my - 1)
    f.note:ClearAllPoints(); f.note:SetPoint("TOPLEFT", 4, addBottom - 6)
    f.note:SetWidth(width - 8)
    f.columns.item:ClearAllPoints(); f.columns.item:SetPoint("TOPLEFT", 6 + 38, listTop + 16)
    f.columns.kind:ClearAllPoints(); f.columns.kind:SetPoint("TOPLEFT", 6 + KIND_X + 4, listTop + 16)
    f.count:ClearAllPoints(); f.count:SetPoint("TOPRIGHT", f, "TOPLEFT", width - 8, listTop + 16)
    f.well:ClearAllPoints(); f.well:SetPoint("TOPLEFT", 0, listTop)
    f.well:SetSize(width, LIST_H)
    f.content:SetWidth(LIST_W)
    f.empty:SetWidth(width - 24)
    for _, row in ipairs(rows) do row:place() end
end

-- Shows or hides the item ID / link entry (secondary to dragging). Returns the new state.
function P.ShowManual(on)
    manualShown = on and true or false
    if f and built then
        f.manual.text:SetText(manualShown and "Hide item ID entry" or "Type an item ID instead")
        Relayout()
        if not manualShown and f.idBox then f.idBox:ClearFocus() end
        if R.SettingsUI and R.SettingsUI.Refresh then C_Timer.After(0, function() R.SettingsUI.Refresh() end) end
    end
    return manualShown
end
function P.ManualShown() return manualShown end
function P.Height() return -ListTop() + LIST_H + 24 end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local AI, G = R.AmmoItems, Wg()
    local pal = G.pal
    Relayout()
    local list = AI.List()
    for i, entry in ipairs(list) do
        local row = Row(i)
        row:place()
        row.id = entry.id
        local name, icon, state = ItemInfo(entry.id)
        row.icon:SetTexture(icon or QUESTION)
        row.name:SetText(name or ("Item " .. entry.id))
        G.Color(row.name, pal.text)
        local text, tone = StatusText(entry, state)
        row.status:SetText(text)
        G.Color(row.status, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.stone))
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
    f.help:SetText("Drag an item the game doesn't recognize as arrows or bullets onto the box. TwichUI classifies it for you; correct it in the list only if needed. This never equips or moves an item.")
    I.Tip(f, "Known ammunition", "The game's own arrows and bullets are already recognized. Registration only classifies an item: it doesn't count it or make it fit your weapon. Ammunition reminders still read your equipment and bags each time.")

    -- the add area: a box to drop an item on, or its item ID or link
    f.card = G.Card(f, 0, ADD_TOP, W, ADD_TOP - ADD_H)
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
    f.dropLabel:SetText("Drag an item from your bags onto the box")
    f.dropSub = G.Text(f, "meta")
    f.dropSub:SetPoint("TOPLEFT", 62, ADD_TOP - 32)
    f.dropSub:SetWidth(W - 62 - 200)
    f.dropSub:SetText("Classified automatically: the game's own type when it has one, otherwise arrows.")
    f.manual = G.Button(f, "Type an item ID instead", 180, "secondary", function() P.ShowManual(not manualShown) end)
    I.Tip(f.manual, "Item ID or link", "For an item you can't drag, such as one not in your bags: type its item ID or paste its link, and choose what to register it as.")

    f.idLabel = G.Text(f, "meta")
    f.idLabel:SetText("Item ID or link")
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
        t:SetPoint("TOPLEFT", 6 + x, ListTop() + 16)
        t:SetText(text)
        return t
    end
    f.columns = {}
    f.columns.item = Column("Item", 38)
    f.columns.kind = Column("Classification", KIND_X + 4)
    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPRIGHT", f, "TOPLEFT", W - 8, ListTop() + 16)
    f.count:SetJustifyH("RIGHT")
    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, ListTop())
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

-- The page's frame (the settings window shows it as Reminders' Known ammunition tab). Built the first time it is shown.
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
    f:SetScript("OnSizeChanged", function() if built then QueueRefresh() end end)
    return f
end

-- A change made anywhere (here, a profile change, an import) redraws the list if it is shown. Registered once.
if R.AmmoItems then
    R.AmmoItems.OnChange(QueueRefresh)
end

K.Page({
    key = "ammoCustom", name = "Known ammunition", nav = "Known ammunition", parent = "reminders", order = 23,
    materialHeader = true, compact = true, designReference = false,
    description = "Ammunition you register yourself, such as an item a server added, as arrows or bullets, for reminders about ammunition.",
    keywords = "ammo ammunition custom known register arrows bullets item id link server hunter quiver list reminder reminders",
    when = function() return R.AmmoItems ~= nil end,
    host = function() return P.Frame() end, hostHeight = function() return P.Height() end,
})
