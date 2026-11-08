-- TwichUI: Vendors and trainers, what a merchant sells
-- A small window, opened from a merchant's map marker ("Show items for sale", npcs/Map.lua's menu), listing the items that
-- merchant was seen to sell: each with its icon, its full name in its quality colour, the game's own tooltip on hover and,
-- with a Shift-click, its link in your chat box (the game's usual item click). It shows what npcs/Store.lua holds for that
-- one NPC and changes nothing: no prices, no purchases, no sending.
--   The list is what was seen the last time the merchant's window was open (by you, or by the player whose report it is);
--     the window says which. A merchant's stock can differ by level, reputation or season, so it is a guide, not a promise.
--   Names, icons and colours are the game's, by item id (npcs/Items.lua). An item this client hasn't met yet shows as
--     "Item <number>" until the game has loaded it (asked for, a few at a time); the list sorts again once, as names arrive.
--   One window, reused. It never opens by itself, opens only for a merchant that is in the list, and closes when the
--     merchant leaves the list, when Vendors and trainers goes off, and with Esc. It holds nothing while closed.

local R = TwichUI
local NS, NI = R.NpcStore, R.NpcItems
local ST = {}
R.NpcStock = ST

local WIDTH, HEIGHT = 372, 470
local PAD = 14
local HEAD = 40
local ROW_H, ICON = 28, 22
local NAME = "TwichUINpcStock"

local L, K, F
local f
local entry          -- the merchant shown (the list's own table)
local filter = ""
local rows = {}

local function Enabled() return R:Enabled("npcMap") end

-- Whether a merchant's marker offers its stock: it sold something the kinds above list (or is simply a merchant).
function ST.IsMerchant(e)
    if type(e) ~= "table" or type(e.tags) ~= "table" then return false end
    for id in pairs(e.tags) do
        local k = R.NpcKinds.BY_ID[id]
        if k and k.section == "vendors" then return true end
    end
    return false
end

function ST.HasStock(e) return type(e) == "table" and type(e.s) == "table" and #e.s > 0 end

local function Listed(e)
    for _, x in ipairs(NS.Entries()) do
        if rawequal(x, e) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function Tip(row)
    if not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(row.id)
    elseif GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink("item:" .. row.id)
    end
    GameTooltip:Show()
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, f.content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = L.Text(row, "body")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.name:SetWordWrap(false)
    L.Hover(row, K.text, 0.06)
    row:SetScript("OnEnter", Tip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        -- the game's usual item click: Shift links it in the chat box, Ctrl tries it on
        local link = NI.Link(self.id)
        if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    rows[i] = row
    return row
end

local function Words(text)
    local words = {}
    for w in (text or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    return words
end

local function When(at)
    if type(at) ~= "number" or at <= 0 or not date then return nil end
    return date("%d %b %Y", at)
end

local function Header()
    local e = entry
    f.title:SetText(e.n)
    local bits = {}
    if e.t then bits[#bits + 1] = e.t end
    bits[#bits + 1] = R.NpcKnowledge.ZoneName(e.m)
    f.sub:SetText(table.concat(bits, " \194\183 "))
end

-- Draws the merchant's items: filtered by the box, named ones first by name, the rest by number.
function ST.Render()
    if not (f and f:IsShown() and entry) then return end
    Header()
    local items = entry.s or {}
    local words = Words(filter)
    local list, unresolved = {}, {}
    for _, id in ipairs(items) do
        local name = NI.Name(id)
        if not name then unresolved[#unresolved + 1] = id end
        local hay = name and name:lower() or ("item " .. id)
        local ok = true
        for _, w in ipairs(words) do
            if not hay:find(w, 1, true) then ok = false break end
        end
        if ok then list[#list + 1] = { id = id, name = name, key = name and hay or nil } end
    end
    table.sort(list, function(a, b)
        if (a.key ~= nil) ~= (b.key ~= nil) then return a.key ~= nil end
        if a.key and a.key ~= b.key then return a.key < b.key end
        return a.id < b.id
    end)
    for i, item in ipairs(list) do
        local row = rows[i] or NewRow(i)
        row.id = item.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)
        row.icon:SetTexture(NI.Icon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.name:SetText(item.name or ("Item " .. item.id))
        local r, g, b = NI.Color(item.id)
        if item.name and r then row.name:SetTextColor(r, g, b) else L.Color(row.name, item.name and K.text or K.stone) end
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
        rows[i].id = nil
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))

    local status
    if #items == 0 then
        status = "No stock has been noted for this merchant yet. It is noted when its window is opened, or when another player sends it."
    else
        status = ("%d %s noted"):format(#items, #items == 1 and "item" or "items")
        if #words > 0 then status = ("%d of %d shown"):format(#list, #items) end
        if #unresolved > 0 then status = status .. (", %d still loading"):format(#unresolved) end
        status = status .. "."
    end
    f.status:SetText(status)
    f.source:SetText(R.NpcMap and R.NpcMap.Provenance(entry) or "")
    f.empty:SetShown(#items > 0 and #list == 0)
    if #unresolved > 0 then NI.Request(unresolved) end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Build()
    L, F = R.Look, R.FrameLook
    K = L.pal
    local _, _, CR = F.ContentInsets()
    f = CreateFrame("Frame", NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("DIALOG")        -- over the world map, which it is opened from
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetPoint("CENTER", UIParent, "CENTER", 220, 0)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:HookScript("OnShow", function(self) R.FitToScreen(self) ST.Render() end)
    f:HookScript("OnHide", function()
        if GameTooltip then GameTooltip:Hide() end
        entry, filter = nil, ""
        if f.filter then f.filter:SetText("") end
    end)
    f.shell = F.Shell(f, { below = true, follow = true })
    F.FadeIn(f)
    f.head = f.shell:Header(HEAD)

    f.title = L.Text(f, "title")
    f.title:SetPoint("TOPLEFT", PAD, -13)
    f.title:SetWidth(WIDTH - PAD * 2 - 40)
    f.title:SetWordWrap(false)
    f.close = F.Close(f, function() f:Hide() end)
    f.close:SetSize(20, 20)
    f.close:SetPoint("TOPRIGHT", -(CR + 2), -13)

    f.sub = L.Text(f, "small")
    f.sub:SetPoint("TOPLEFT", PAD, -(HEAD + 8))
    f.sub:SetWidth(WIDTH - PAD * 2)
    f.sub:SetWordWrap(false)
    f.status = L.Text(f, "small")
    f.status:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -4)
    f.status:SetWidth(WIDTH - PAD * 2)
    f.status:SetWordWrap(true)
    f.status:SetJustifyV("TOP")
    f.source = L.Text(f, "meta")
    f.source:SetPoint("BOTTOMLEFT", PAD, 34)
    f.source:SetWidth(WIDTH - PAD * 2)
    f.source:SetWordWrap(true)
    f.hint = L.Text(f, "meta")
    f.hint:SetPoint("BOTTOMLEFT", PAD, 16)
    f.hint:SetWidth(WIDTH - PAD * 2)
    f.hint:SetWordWrap(false)
    f.hint:SetText("Hover an item for its tooltip. Shift-click links it in chat.")

    f.filter = L.EditBox(f, WIDTH - PAD * 2, 22)
    f.filter:SetPoint("TOPLEFT", PAD, -(HEAD + 52))
    f.filter:SetMaxLetters(40)
    f.filterHint = L.Text(f.filter, "meta")
    f.filterHint:SetPoint("LEFT", f.filter, "LEFT", 6, 0)
    f.filterHint:SetText("Filter by name")
    f.filter:HookScript("OnTextChanged", function(self, user)
        f.filterHint:SetShown((self:GetText() or "") == "")
        if user then
            filter = self:GetText() or ""
            ST.Render()
        end
    end)

    f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", PAD, -(HEAD + 84))
    f.scroll:SetPoint("BOTTOMRIGHT", -PAD - 18, 62)
    L.ScrollBar(f.scroll)
    f.content = CreateFrame("Frame", nil, f.scroll)
    f.content:SetSize(WIDTH - PAD * 2 - 22, 1)
    f.scroll:SetScrollChild(f.content)
    f.empty = L.Text(f.scroll, "small")
    f.empty:SetPoint("TOPLEFT", 4, -6)
    f.empty:SetText("No item matches that.")
    f.empty:Hide()

    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it (never the game-menu handler)
    return f
end

-- Opens the window for a merchant of the list. Returns true, or false and why.
function ST.Show(e)
    if not Enabled() then return false, "Vendors and trainers is turned off." end
    if type(e) ~= "table" or not Listed(e) then return false, "It's no longer in your list." end
    if not f then Build() end
    entry, filter = e, ""
    f.filter:SetText("")
    if f:IsShown() then ST.Render() else f:Show() end
    f:Raise()
    return true
end

function ST.Hide() if f and f:IsShown() then f:Hide() end end
function ST.Shown() return entry end
function ST.Frame() return f end

-- The switch changed: the window goes with the feature.
function ST.Refresh() if not Enabled() then ST.Hide() end end

-- The list changed under the window: the merchant may be gone, or have more to show.
NS.OnChange(function()
    if not (f and f:IsShown() and entry) then return end
    if Listed(entry) then ST.Render() else f:Hide() end
end)
NI.OnNames(function() ST.Render() end)

function ST.Snapshot()
    return { built = f ~= nil, shown = f ~= nil and f:IsShown() or false, rows = #rows }
end
