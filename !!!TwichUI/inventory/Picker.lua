-- TwichUI: Magic Inventory, choosing items from your bags
-- A window of its own with every kind of item you carry (one square per item, however many stacks), a search box,
-- and Done and Cancel. Clicking a square marks or unmarks that KIND of item for the list being edited (a rule's
-- "Also include", "Never include", or the Never transfer list): it never points at a bag slot, and nothing in the bags
-- is picked up, moved, used or changed. Bag addons and the game's own bags are left alone: no clicks are taken over.
-- Cancel, the close box and Esc leave the list as it was. Built the first time it is shown; squares are reused.

local R = TwichUI
local MI = R.MagicInventory
local P = {}
MI.Picker = P

local NAME = "TwichUIMagicInventoryPicker"
local WIDTH, HEIGHT, HEADER, PAD = 440, 470, 44, 16
local CELL, COLS = 40, 9
local QUESTION = [[Interface\Icons\INV_Misc_QuestionMark]]

local f
local cells = {}
local items = {}            -- what is carried: { id, count, icon, name, link }
local chosen = {}           -- [itemID] = true while the window is open
local onDone

local function Look() return R.Look end

-- What the bags hold, one entry per item ID (read only).
local function Gather()
    local byId, list = {}, {}
    for bag = 0, MI.LastBag() do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and MI.Plain(info.itemID)
            if type(id) == "number" then
                local e = byId[id]
                if not e then
                    local facts = MI.ItemFacts(id)
                    e = { id = id, count = 0, icon = MI.Plain(info.iconFileID) or (facts and facts.icon), name = (facts and facts.name) or MI.Plain(info.itemName) or "",
                        link = MI.Plain(info.hyperlink), bag = bag, slot = slot }
                    byId[id] = e
                    list[#list + 1] = e
                end
                e.count = e.count + (MI.Plain(info.stackCount) or 0)
            end
        end
    end
    table.sort(list, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.id < b.id end)
    return list
end

local function Cell(i)
    local c = cells[i]
    if c then return c end
    local L = Look()
    c = CreateFrame("Button", nil, f.content, "BackdropTemplate")
    c:SetSize(CELL - 4, CELL - 4)
    L.Surface(c, L.pal.well, 1, L.pal.control, 0.9)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 2, -2)
    c.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    c.count:SetPoint("BOTTOMRIGHT", -2, 2)
    c.mark = L.Solid(c, "OVERLAY", L.pal.tealLo, 0.55)
    c.mark:SetAllPoints()
    c.check = c:CreateTexture(nil, "OVERLAY", nil, 2)
    c.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c.check:SetSize(22, 22)
    c.check:SetPoint("TOPRIGHT", 4, 4)
    c:SetScript("OnClick", function(self)
        if not self.item then return end
        chosen[self.item.id] = (not chosen[self.item.id]) or nil
        P.Draw()
    end)
    c:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.item.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(self.item.link)
        elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item.id) end
        GameTooltip:AddLine(chosen[self.item.id] and "Chosen: click to leave it out." or "Click to choose this kind of item.", 0.58, 0.78, 0.76)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = c
    return c
end

function P.Draw()
    if not (f and f:IsShown()) then return end
    local query = (f.search:GetText() or ""):lower()
    local shown, n = {}, 0
    for _, e in ipairs(items) do
        if query == "" or (e.name or ""):lower():find(query, 1, true) then shown[#shown + 1] = e end
    end
    for i, e in ipairs(shown) do
        local c = Cell(i)
        c.item = e
        c.icon:SetTexture(e.icon or QUESTION)
        c.count:SetText(e.count > 1 and e.count or "")
        local on = chosen[e.id] == true
        c.mark:SetShown(on)
        c.check:SetShown(on)
        local L = Look()
        local edge = on and L.pal.tealHi or L.pal.control
        c:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f.content, "TOPLEFT", ((i - 1) % COLS) * CELL, -math.floor((i - 1) / COLS) * CELL)
        c:Show()
    end
    for i = #shown + 1, #cells do cells[i]:Hide(); cells[i].item = nil end
    f.content:SetHeight(math.max(1, math.ceil(#shown / COLS) * CELL))
    for _ in pairs(chosen) do n = n + 1 end
    if #items == 0 then f.empty:SetText("Your bags are empty.")
    elseif #shown == 0 then f.empty:SetText("Nothing you carry matches that search.")
    else f.empty:SetText("") end
    f.count:SetText(("%d chosen"):format(n))
end

local function Close(done)
    if not f then return end
    if done and onDone then
        local set = {}
        for id in pairs(chosen) do set[id] = true end
        local cb = onDone
        onDone = nil
        cb(set)
    end
    f:Hide()
end

local function Build()
    local L = Look()
    if not (L and L.Shell and R.ChronicleStyle) then return false end
    f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", -240, 30)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, NAME)   -- Esc is Cancel
    L.Shell(f, HEADER)
    f:HookScript("OnShow", R.FitToScreen)
    f.title = L.Text(f, "title")
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetText("Choose from your bags")
    L.CloseBox(f, function() Close(false) end)
    f.sub = L.Text(f, "small")
    f.sub:SetPoint("TOPLEFT", PAD, -(HEADER + 8))
    f.sub:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.sub:SetJustifyH("LEFT")
    f.search = L.EditBox(f, WIDTH - PAD * 2, 22)
    f.search:SetPoint("TOPLEFT", PAD, -(HEADER + 58))
    f.search:SetScript("OnTextChanged", function() P.Draw() end)
    f.search:SetScript("OnEscapePressed", function(self)
        if (self:GetText() or "") ~= "" then self:SetText("") else self:ClearFocus() end
    end)
    f.searchHint = L.Text(f.search, "meta")
    f.searchHint:SetPoint("LEFT", 8, 0)
    f.searchHint:SetText("Search what you carry")
    f.search:HookScript("OnTextChanged", function(self) f.searchHint:SetShown((self:GetText() or "") == "") end)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PAD, -(HEADER + 88))
    box:SetPoint("BOTTOMRIGHT", -PAD, 56)
    L.Well(box)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)
    if L.ScrollBar then L.ScrollBar(scroll) end
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(CELL * COLS, 1)
    scroll:SetScrollChild(f.content)
    f.empty = L.Text(box, "small")
    f.empty:SetPoint("CENTER", 0, 0)

    f.count = L.Text(f, "small")
    f.count:SetPoint("BOTTOMLEFT", PAD, 20)
    f.clear = L.Button(f, "Clear chosen", 110, "secondary", function()
        chosen = {}
        P.Draw()
    end)
    f.clear:SetPoint("BOTTOMLEFT", PAD + 80, 14)
    f.done = L.Button(f, "Done", 90, "primary", function() Close(true) end)
    f.done:SetPoint("BOTTOMRIGHT", -PAD, 14)
    f.cancel = L.Button(f, "Cancel", 90, "secondary", function() Close(false) end)
    f.cancel:SetPoint("RIGHT", f.done, "LEFT", -8, 0)
    f:HookScript("OnHide", function()   -- hooked: the shell's fade is a hook of the same script
        -- Cancel, Esc and the close box: nothing changes
        onDone = nil
        chosen = {}
        f.search:SetText("")
        f.search:ClearFocus()
        GameTooltip:Hide()
    end)
    return true
end

-- opts: { purpose = "a sentence on what the choice is for", selected = { [itemID] = true },
--         onDone = function(set) end }  onDone is called once, with the chosen set, only on Done.
function P.Open(opts)
    if not (f or Build()) then R.Print("choosing from your bags isn't available right now.") return false end
    if f:IsShown() then f:Hide() end
    chosen = {}
    for id, on in pairs(opts.selected or {}) do if on == true then chosen[id] = true end end
    onDone = opts.onDone
    f.sub:SetText((opts.purpose or "Click the items you want.") .. "\nThis chooses the kind of item, not a stack: nothing in your bags moves.")
    items = Gather()
    f:Show()
    f:Raise()
    P.Draw()
    return true
end

function P.IsShown() return f ~= nil and f:IsShown() end
function P.Cancel() Close(false) end
function P.Done() Close(true) end
function P.Toggle(id) chosen[id] = (not chosen[id]) or nil; P.Draw() end
function P.CellCount() return #cells end
