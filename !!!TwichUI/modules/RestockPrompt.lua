-- TwichUI: vendor restocking, the question
-- The window "Ask before purchasing" shows (modules/Restock.lua builds the plan and decides everything; this only
-- draws it and reports the player's choice). One row per item to buy: its icon, its name in the item's quality color,
-- how many, what you carry against the target, and the price (gold, silver and copper letters colored as the game
-- colors its coins), with a line in the warning color when it falls short and why. Under the list: the total, what
-- you have, the spending limit, and what couldn't be bought.
--
-- Show(plan, lead, onAccept, onCancel) draws it and returns true; false when it can't be drawn (the look isn't there,
-- or building it failed), and Restock.lua then asks with the game's own dialog instead. Purchase calls onAccept once;
-- Cancel, the close box and Esc call onCancel once; Hide() puts it away for the code's own reasons (the merchant
-- closed, an option changed) and calls neither. Nothing here buys anything or reads the bags. Built the first time
-- it is needed; one frame and a small pool of rows, reused on every question. Esc closes it through the game's own
-- list of frames Esc closes (never RegisterGameMenuEscHandler: see docs about the Esc handler taint).
--
-- Its background and border are the player's to set (P.Style, a MenuStyle look saved in TwichUIDB.ui.restockPromptStyle;
-- Vendor restocking settings > Question window appearance). The default is the look it always had: the TwichUI rim
-- ("ledger", drawn by Look.Shell) over the page color. Any other border replaces the rim, and the window grows by the
-- difference so the border never covers the rows or the buttons. Only the look changes: what is asked, the rows and
-- the Purchase and Cancel buttons are the same. P.TogglePreview shows the real window with made-up items.


local R = TwichUI
local P = {}
R.RestockPrompt = P

local NAME = "TwichUIRestockPrompt"
local W, PAD, HEADER, MIN_H = 460, 16, 44, 260
local ROW_H, ROW_H_SHORT = 46, 62
local MAX_ROWS = 8
local ICON = 30
local RIGHT_W = 124
local QUESTION = [[Interface\Icons\INV_Misc_QuestionMark]]
local WARN = "|cffe0877b"

local RIM = 4          -- how far the default rim (and the title band inside it) sits in from the frame's edge

local f, cur, built, lastPlan, lastLead
local reach, ox = RIM, 0   -- where the title band starts, and how far the content is pushed in by a thick border
local previewPlaced = false
local rows = {}

-- The player's background and border. The defaults are what the window had before it was a setting.
P.LEDGER = "ledger"
if R.MenuStyle and R.MenuStyle.New then
    P.Style = R.MenuStyle.New("restockPromptStyle", {
        bgTexture = "solid", bgColor = "ff232221", bgOpacity = 98,
        borderTexture = P.LEDGER, borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
    }, { extraBorders = { { P.LEDGER, "TwichUI rim (default)" } }, sources = true })
end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Money(copper)
    local RS = R.Restock
    return RS.ColorMoney and RS.ColorMoney(copper) or RS.MoneyText(copper)
end

-- The item as the game describes it, with nothing made up: a name from the plan's own link when the game hasn't
-- loaded it, the question mark for a missing icon, the ordinary text color for a missing quality.
local function Facts(item)
    local id = item.id
    local name = C_Item and C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
    if type(name) ~= "string" or name == "" then name = type(item.link) == "string" and item.link:match("%[(.-)%]") or nil end
    local icon = C_Item and C_Item.GetItemIconByID and Plain(C_Item.GetItemIconByID(id))
    if not icon and C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, i = C_Item.GetItemInfoInstant(id)
        icon = Plain(i)
    end
    local r, g, b
    local quality = C_Item and C_Item.GetItemQualityByID and Plain(C_Item.GetItemQualityByID(id))
    if type(quality) == "number" and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(quality)
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then r, g, b = nil, nil, nil end
    end
    return name or ("Item " .. id), icon, r, g, b
end

local function Reason(why)
    return R.Restock.REASONS[why] or "it couldn't be bought"
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Row(i)
    if rows[i] then return rows[i] end
    local L = R.Look
    local pal = L.pal
    local row = CreateFrame("Button", nil, f.list)
    row:SetWidth(W - PAD * 2 - 2)
    row.shade = L.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.shade:SetAllPoints()
    row.divider = L.Solid(row, "BORDER", pal.bronzeLo, 0.35)
    row.divider:SetHeight(1)
    row.divider:SetPoint("BOTTOMLEFT", 8, 0)
    row.divider:SetPoint("BOTTOMRIGHT", -8, 0)

    row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.iconFrame:SetSize(ICON + 2, ICON + 2)
    row.iconFrame:SetPoint("TOPLEFT", 8, -8)
    L.Surface(row.iconFrame, pal.well, 1, pal.control, 1)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local leftW = W - PAD * 2 - 2 - 8 - ICON - 2 - 10 - RIGHT_W - 8
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 10, -1)
    row.name:SetWidth(leftW)
    row.name:SetWordWrap(false)
    row.meta = L.Text(row, "meta")
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.meta:SetWidth(leftW)
    row.meta:SetWordWrap(false)
    row.warn = L.Text(row, "small")
    row.warn:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -3)
    row.warn:SetWidth(W - PAD * 2 - 2 - 8 - ICON - 2 - 10 - 12)
    row.warn:SetWordWrap(false)
    L.Color(row.warn, pal.danger.text)

    row.cost = L.Text(row, "body")
    row.cost:SetPoint("TOPRIGHT", -10, -9)
    row.cost:SetWidth(RIGHT_W)
    row.cost:SetJustifyH("RIGHT")
    row.each = L.Text(row, "meta")
    row.each:SetPoint("TOPRIGHT", row.cost, "BOTTOMRIGHT", 0, -3)
    row.each:SetWidth(RIGHT_W)
    row.each:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        if not (self.id and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.id) else GameTooltip:SetText(self.name:GetText() or "", 1, 1, 1) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self) R.Interact.HideTip(self) end)
    row:SetScript("OnHide", function(self) R.Interact.HideTip(self) end)
    rows[i] = row
    return row
end

local function Settle(accepted)
    local c = cur
    cur = nil
    if f and f:IsShown() then f:Hide() end
    if c then
        local fn = accepted and c.accept or c.cancel
        local ok, err = pcall(fn)
        if not ok then R.Fault("restock question", err) end
    end
end

local function Build()
    built = true
    local L = R.Look
    local pal = L.pal
    f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    f:SetSize(W, MIN_H)   -- the look's grain is laid out for this height: the window is never shorter
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:HookScript("OnShow", R.FitToScreen)
    f:Hide()
    tinsert(UISpecialFrames, NAME)   -- Esc closes it (as a Cancel)
    L.Shell(f, HEADER)
    -- the default rim's outermost dark line was the backdrop's edge; the look replaces the backdrop, so the line is
    -- drawn here and shown with the rim
    local ink = { pal.ink, 1 }
    f.edgeInk = L.Shade(f, ink, ink, ink, ink, 0)
    f.title = L.Text(f, "title")
    f.title:SetText("Restock from this merchant?")
    f.close = L.CloseBox(f)

    f.lead = L.Text(f, "small")
    f.lead:SetWidth(W - PAD * 2)
    L.Color(f.lead, pal.danger.text)

    f.list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.list:SetWidth(W - PAD * 2)
    L.Well(f.list)
    f.more = L.Text(f.list, "meta")
    f.more:SetWidth(W - PAD * 2 - 24)

    f.footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.footer:SetWidth(W - PAD * 2)
    L.Panel(f.footer)
    f.totalLabel = L.Text(f.footer, "heading")
    f.totalLabel:SetText("Total")
    f.total = L.Text(f.footer, "body")
    f.total:SetJustifyH("RIGHT")
    f.have = L.Text(f.footer, "meta")
    f.have:SetWidth(W - PAD * 2 - 24)
    f.have:SetJustifyH("LEFT")

    f.notes = L.Text(f, "small")
    f.notes:SetWidth(W - PAD * 2)

    f.promise = L.Text(f, "meta")
    f.promise:SetWidth(W - PAD * 2 - 260)
    f.promise:SetText("Nothing is bought unless you press Purchase.")
    f.purchase = L.Button(f, "Purchase", 124, "primary", function() Settle(true) end)
    f.cancel = L.Button(f, "Cancel", 100, "secondary", function() Settle(false) end)

    -- Esc, the close box and anything else that hides it without Purchase is a Cancel
    f:SetScript("OnHide", function()
        if cur then Settle(false) end
    end)
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Layout(plan, lead)
    local L = R.Look
    local px = PAD + ox
    f:SetWidth(W + ox * 2)
    f.title:ClearAllPoints()
    f.title:SetPoint("LEFT", f, "TOPLEFT", px, -(HEADER / 2 + reach))
    f.close:ClearAllPoints()
    f.close:SetPoint("TOPRIGHT", -(10 + ox), -(11 + ox))
    local y = HEADER + 12 + ox
    if lead and lead ~= "" then
        f.lead:SetText(lead)
        f.lead:ClearAllPoints()
        f.lead:SetPoint("TOPLEFT", f, "TOPLEFT", px, -y)
        f.lead:Show()
        y = y + (f.lead:GetStringHeight() or 12) + 10
    else
        f.lead:Hide()
    end

    f.list:ClearAllPoints()
    f.list:SetPoint("TOPLEFT", f, "TOPLEFT", px, -y)
    local inner = 1
    local shown = math.min(#plan.items, MAX_ROWS)
    for i = 1, shown do
        local item = plan.items[i]
        local row = Row(i)
        local name, icon, r, g, b = Facts(item)
        row.id = item.id
        row.icon:SetTexture(icon or QUESTION)
        row.name:SetText(name)
        if r then row.name:SetTextColor(r, g, b) else L.Color(row.name, L.pal.text) end
        row.meta:SetText(("×%d   ·   you carry %d of %d"):format(item.units, item.carried or 0, item.target or item.units))
        row.cost:SetText(Money(item.cost))
        row.each:SetText(item.stack > 1 and (Money(item.price) .. " per " .. item.stack) or (Money(item.price) .. " each"))
        local short = (item.short or 0) > 0
        row.warn:SetShown(short)
        if short then row.warn:SetText(("%d short: %s"):format(item.short, Reason(item.why))) end
        local h = short and ROW_H_SHORT or ROW_H
        row:SetHeight(h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.list, "TOPLEFT", 1, -inner)
        row:Show()
        inner = inner + h
    end
    for i = shown + 1, #rows do
        rows[i].id = nil
        rows[i]:Hide()
    end
    if #plan.items > shown then
        f.more:SetText(("...and %d more, included in the total."):format(#plan.items - shown))
        f.more:ClearAllPoints()
        f.more:SetPoint("TOPLEFT", f.list, "TOPLEFT", 12, -(inner + 6))
        f.more:Show()
        inner = inner + 26
    else
        f.more:Hide()
    end
    f.list:SetHeight(inner + 1)
    y = y + inner + 1 + 10

    f.footer:ClearAllPoints()
    f.footer:SetPoint("TOPLEFT", f, "TOPLEFT", px, -y)
    f.totalLabel:ClearAllPoints()
    f.totalLabel:SetPoint("TOPLEFT", f.footer, "TOPLEFT", 12, -10)
    f.total:ClearAllPoints()
    f.total:SetPoint("TOPRIGHT", f.footer, "TOPRIGHT", -12, -10)
    f.total:SetText(Money(plan.total))
    f.have:ClearAllPoints()
    f.have:SetPoint("TOPLEFT", f.footer, "TOPLEFT", 12, -30)
    local have = "You have " .. Money(plan.money)
    if plan.limit then have = have .. "   ·   spending limit for a visit: " .. Money(plan.limit) end
    f.have:SetText(have)
    f.footer:SetHeight(52)
    y = y + 52 + 10

    if #plan.notes > 0 then
        local parts = {}
        for i, n in ipairs(plan.notes) do
            if i > 4 then parts[#parts + 1] = ("and %d more"):format(#plan.notes - 4) break end
            parts[#parts + 1] = ("%s (%s)"):format(n.link, Reason(n.why))
        end
        f.notes:SetText("Not bought: " .. table.concat(parts, "; ") .. ".")
        f.notes:ClearAllPoints()
        f.notes:SetPoint("TOPLEFT", f, "TOPLEFT", px, -y)
        f.notes:Show()
        y = y + (f.notes:GetStringHeight() or 12) + 10
    else
        f.notes:Hide()
    end

    f.cancel:ClearAllPoints()
    f.cancel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -px, -(y + 4))
    f.purchase:ClearAllPoints()
    f.purchase:SetPoint("RIGHT", f.cancel, "LEFT", -8, 0)
    f.promise:ClearAllPoints()
    f.promise:SetPoint("LEFT", f, "TOPLEFT", px, -(y + 4 + 11))
    f:SetHeight(math.max(MIN_H + ox * 2, y + 4 + 22 + PAD + 4 + ox))
end

-- Draws the player's background and border and works out where the content sits. Changes only the frame's own
-- pieces (its backdrop, the rim and grain textures, the title band's place); no frame, texture or hook is made.
local function Restyle()
    local L = R.Look
    reach, ox = RIM, 0
    local style = P.Style
    if not (f and style) then return end
    local edge, drawn = style.Apply(f)
    local ledger = drawn == "custom"
    if drawn == "eui" and R.Borders.Inside then edge = math.min(edge, R.Borders.Inside(style.Get("borderTexture"), edge)) end
    L.ShellParts(f, ledger, ledger and style.Get("bgTexture") == "solid")
    if f.edgeInk then for _, line in pairs(f.edgeInk) do line:SetShown(ledger) end end
    reach = ledger and RIM or math.ceil(edge)
    ox = math.max(0, reach - RIM)
    local band = f.twichBand
    if band then
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", f, "TOPLEFT", reach, -reach)
        band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -reach, -reach)
    end
end

-- The look changed while the question is up: drawn again where it is, with the same plan.
local function Redraw()
    if not (f and f:IsShown() and lastPlan) then return end
    local ok, err = pcall(function()
        Restyle()
        Layout(lastPlan, lastLead)
    end)
    if not ok then R.Fault("restock question look", err) end
end
if P.Style then P.Style.Subscribe(Redraw) end

local function Present(plan, lead, onAccept, onCancel, preview)
    local RS = R.Restock
    if not (RS and R.Look and R.ChronicleStyle and R.Look.Shell and type(plan) == "table" and type(plan.items) == "table") then return false end
    if not built then
        local ok, err = pcall(Build)
        if not ok then
            built, f = false, nil
            R.Fault("restock question", err)
            return false
        end
    end
    local ok, err = pcall(function()
        Restyle()
        Layout(plan, lead)
    end)
    if not ok then
        R.Fault("restock question", err)
        return false
    end
    lastPlan, lastLead = plan, lead
    cur = { accept = onAccept, cancel = onCancel, preview = preview }
    if not preview and previewPlaced then   -- a real question opens where it always does, not beside the settings
        previewPlaced = false
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    end
    f:Show()
    return true
end

-- plan: Restock.lua's plan (items, notes, total, money, limit). Returns true once it is on screen.
function P.Show(plan, lead, onAccept, onCancel)
    return Present(plan, lead, onAccept, onCancel, false)
end

-- Puts it away without answering (the merchant closed, an option changed): neither callback runs.
function P.Hide()
    cur = nil
    if f and f:IsShown() then f:Hide() end
end

function P.IsShown() return f ~= nil and f:IsShown() end
function P.Frame() return f end

---------------------------------------------------------------------------
-- The settings page's preview: the real window with made-up items, beside the settings window. Purchase and
-- Cancel only close it: nothing is bought, no merchant is involved and the bags are not read. A real question
-- opened meanwhile replaces it, and a real question that is up is never replaced by it.
---------------------------------------------------------------------------
local function SamplePlan()
    return {
        items = {
            { id = 17020, link = "[Arcane Powder]", units = 13, stack = 1, price = 500, cost = 6500, carried = 7, target = 20 },
            { id = 17031, link = "[Rune of Teleportation]", units = 5, stack = 1, price = 10000, cost = 50000, carried = 0, target = 5 },
            { id = 2512, link = "[Rough Arrow]", units = 100, stack = 200, price = 1000, cost = 500, carried = 100, target = 400,
              short = 200, why = "bundle" },
        },
        notes = { { id = 4000, link = "[Moonwell Water]", why = "sold-out" } },
        total = 57000, money = 523400, limit = 100000,
    }
end

function P.IsPreview() return cur ~= nil and cur.preview == true and f ~= nil and f:IsShown() end

function P.TogglePreview()
    if P.IsPreview() then P.Hide() return end
    if cur then return end   -- a real question is up: leave it alone
    local none = function() end
    if not Present(SamplePlan(), "This is a sample. Nothing here is real, and Purchase buys nothing.", none, none, true) then return end
    local anchor = R.SettingsAnchor and R.SettingsAnchor()
    if anchor then
        previewPlaced = true
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, -48)
        R.FitToScreen(f)
    end
    f:Raise()
end

-- The settings window closing takes the preview with it (a real question stays).
if R.OnSettingsClosed then
    R.OnSettingsClosed(function() if P.IsPreview() then P.Hide() end end)
end
