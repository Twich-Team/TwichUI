-- TwichUI: Mage selling window (/tui sell, and Open in Options > Mage)
-- What would be sold if you opened a merchant now, what is kept and why, and the never-sell list. The
-- list is read through the same classifier selling uses (modules/MageSell.lua), so it can't say one
-- thing and sell another. Opening or refreshing it sells, moves and splits nothing and holds nothing
-- on the cursor; the only actions are Never sell and Remove (the list), Refresh, and Sell now, which
-- is your click and works only at an open merchant with Dry run off. Drawn with the Chronicle's
-- palette (chronicle/Style.lua). Built when first opened; while closed it listens to nothing.

local R = TwichUI
local MS = R.MageSell
local W = {}
R.MageSellWindow = W

local FRAME_NAME = "TwichUIMageSellWindow"
local WIDTH, HEIGHT = 580, 580
local PAD = 16
local HEADER = 40
local ROW_H = 28
local VISIBLE_ROWS = 12
local SETTLE = 0.2           -- seconds: a burst of bag events becomes one redraw

local S                      -- the Chronicle's style, looked up when the window is first built
local f                      -- the window
local rows = {}              -- the row frames made so far (a pool)
local shown = 0              -- how many are in use
local scheduled = false
local active = {}            -- [event] = handler, while the window is open

local function Color(c, a) return c[1], c[2], c[3], a end

local function Name(entry)
    return entry.name or ("Item " .. tostring(entry.id))
end

---------------------------------------------------------------------------
-- What the list holds: header, item, kept, excluded and note rows, as plain tables.
---------------------------------------------------------------------------
local function Count(n, one, many) return ("%d %s"):format(n, n == 1 and one or many) end

-- Items by ID: { { id, name, icon, count, stacks, value, why, reason, amount }, ... } in the order first
-- seen. key: what to group by besides the ID (nothing for sellable stacks, the reason for kept ones).
local function Group(list, byReason)
    local out, index = {}, {}
    for _, v in ipairs(list) do
        local key = byReason and (tostring(v.id) .. ":" .. tostring(v.why)) or v.id
        local g = index[key]
        if not g then
            g = { id = v.id, name = v.name, icon = v.icon, count = 0, stacks = 0, value = 0, why = v.why,
                reason = v.reason, amount = v.amount, kinds = v.kinds, pending = v.pending }
            index[key] = g
            out[#out + 1] = g
        end
        g.count, g.stacks, g.value = g.count + v.count, g.stacks + 1, g.value + (v.value or 0)
    end
    return out
end

-- The rows to draw, from a scan and the never-sell list. Also the figures for the status line.
function W.Rows(scan)
    local out = {}
    local function Add(row) out[#out + 1] = row end
    local sell = Group(scan.eligible, false)
    Add({ kind = "header", text = ("Would be sold at a merchant (%s)"):format(Count(scan.stacks, "stack", "stacks")),
        right = scan.stacks > 0 and (("about %s"):format(MS.Money(scan.value))) or nil })
    if #sell == 0 then
        Add({ kind = "note", text = scan.pending > 0 and "Waiting for the game to load some items; this fills in by itself."
            or "Nothing in your bags would be sold." })
    end
    for _, g in ipairs(sell) do
        local detail = MS.REASONS[g.reason] or "Ordinary food or drink"
        if g.amount then
            detail = ("%s, restores %d"):format(detail, g.amount)
        end
        Add({ kind = "item", id = g.id, name = Name(g), icon = g.icon,
            text = ("%s  x%d"):format(Name(g), g.count), detail = detail, right = MS.Money(g.value), action = "Never sell" })
    end
    local limit = MS.Limit()
    if scan.stacks > limit then
        Add({ kind = "note", text = ("A visit sells at most %d stacks, so your buyback list keeps this visit's sales; the rest wait for the next click or visit."):format(limit) })
    end

    local kept = {}
    for _, v in ipairs(scan.kept) do
        if v.why ~= "excluded" then kept[#kept + 1] = v end   -- those are in the never-sell list below
    end
    local keptGroups = Group(kept, true)
    if #keptGroups > 0 then
        Add({ kind = "header", text = ("Kept (%s)"):format(Count(#keptGroups, "item", "items")) })
        for _, g in ipairs(keptGroups) do
            Add({ kind = "kept", id = g.id, name = Name(g), icon = g.icon, text = ("%s  x%d"):format(Name(g), g.count),
                detail = MS.REASONS[g.why] or g.why,
                action = (g.why ~= "conjured") and "Never sell" or nil })
        end
    end

    local excluded = MS.Excluded()
    Add({ kind = "header", text = ("Never sell (%s)"):format(Count(#excluded, "item", "items")) })
    if #excluded == 0 then
        Add({ kind = "note", text = "Nothing on your list. Items you add are kept in every stack, whatever they are." })
    end
    for _, id in ipairs(excluded) do
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
        if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        Add({ kind = "excluded", id = id, name = name or ("Item " .. id), icon = icon,
            text = name or ("Item " .. id), detail = "Never sold", action = "Remove" })
    end
    return out
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, f.content)
    row:SetSize(f.content:GetWidth(), ROW_H)
    S.RowArt(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.right:SetJustifyH("RIGHT")
    row.action = S.Link(row, "", function(self)
        local r = self:GetParent()
        if r.entry and r.entry.kind == "excluded" then MS.Include(r.entry.id)
        elseif r.entry then
            local ok, why = MS.Exclude(r.entry.id)
            if not ok then R.Print("%s", why) end
        end
        W.Refresh()
    end, S.color.stone, S.color.gold)
    row.action:SetSize(70, 16)
    row.action:SetPoint("RIGHT", -6, 0)
    rows[i] = row
    return row
end

-- Draws one row from its plain description.
local function Fill(row, entry, y)
    row.entry = entry
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row.text:ClearAllPoints()
    row.detail:ClearAllPoints()
    row.right:ClearAllPoints()
    row.icon:Hide()
    row.detail:SetText("")
    row.right:SetText("")
    row.action:Hide()
    local width = f.content:GetWidth()
    if entry.kind == "header" then
        row.text:SetFontObject("GameFontNormal")
        row.text:SetTextColor(Color(S.color.gold))
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetWidth(width - 180)
        row.text:SetText(entry.text)
        if entry.right then
            row.right:SetPoint("RIGHT", -8, 0)
            row.right:SetTextColor(Color(S.color.textDim))
            row.right:SetText(entry.right)
        end
    elseif entry.kind == "note" then
        row.text:SetFontObject("GameFontHighlightSmall")
        row.text:SetTextColor(Color(S.color.stone))
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetWidth(width - 20)
        row.text:SetWordWrap(true)
        row.text:SetText(entry.text)
    else
        row.text:SetWordWrap(false)
        row.text:SetFontObject("GameFontHighlight")
        row.text:SetTextColor(Color(entry.kind == "item" and S.color.text or S.color.textDim))
        row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:Show()
        row.text:SetPoint("TOPLEFT", 34, -3)
        row.text:SetWidth(width - 34 - 160)
        row.text:SetText(entry.text)
        row.detail:SetPoint("BOTTOMLEFT", 34, 3)
        row.detail:SetWidth(width - 34 - 160)
        row.detail:SetTextColor(Color(S.color.stone))
        row.detail:SetText(entry.detail or "")
        if entry.right and entry.right ~= "" then
            row.right:SetPoint("TOPRIGHT", -8, -4)
            row.right:SetTextColor(Color(S.color.textDim))
            row.right:SetText(entry.right)
        end
        if entry.action then
            row.action.text:SetText(entry.action)
            row.action:ClearAllPoints()
            row.action:SetPoint("BOTTOMRIGHT", -6, 4)
            row.action:Show()
        end
    end
    row:Show()
end

local function ModeLine()
    if not MS.ForPlayer() then
        return "This is for Mages.", S.color.stone
    elseif not MS.Enabled() then
        return "Selling is off. Turn on \"Sell non-conjured food and drink\" in the Mage options to use it. This list shows what it would sell.", S.color.stone
    elseif MS.DryRun() then
        return "DRY RUN is on: at a merchant this says what would be sold and sells nothing. Turn Dry run off in the Mage options to sell.", S.color.gold
    end
    return ("Selling is ON: eligible items are sold when you open a merchant, at most %d stacks a visit. Your buyback list still holds them until it fills."):format(MS.Limit()), S.color.emberHi
end

-- Why Sell now can't be used, or nil when it can.
local function SellBlock(scan)
    if not MS.ForPlayer() then return "This is for Mages." end
    if not MS.Enabled() then return "Turn on selling in the Mage options first." end
    if MS.DryRun() then return "Dry run is on: nothing is sold. Turn it off in the Mage options." end
    if MS.Running() then return "A sale is in progress." end
    if InCombatLockdown and InCombatLockdown() then return "Not in combat." end
    if not MS.MerchantOpen() then return "Open a merchant's window first." end
    if not scan or scan.stacks == 0 then return "Nothing here would be sold." end
    return nil
end

local scanned   -- the scan the window was last drawn from

function W.Refresh()
    if not (f and f:IsShown()) then return end
    scanned = MS.Scan(false)
    local entries = W.Rows(scanned)
    local y = 0
    shown = #entries
    for i, entry in ipairs(entries) do
        Fill(Row(i), entry, y)
        y = y + ROW_H
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    f.content:SetHeight(math.max(y, 1))
    local text, color = ModeLine()
    f.mode:SetText(text)
    f.mode:SetTextColor(Color(color))
    local last = MS.Last()
    if MS.Running() then
        f.result:SetText("Selling...")
    elseif last and not last.dry and last.stacks > 0 then
        f.result:SetText(("Last visit: sold %s (%d items), about %s."):format(Count(last.stacks, "stack", "stacks"), last.items, MS.Money(last.value)))
    elseif last and last.dry and last.eligible > 0 then
        f.result:SetText(("Last dry run: would have sold %s. Nothing was sold."):format(Count(last.eligible, "stack", "stacks")))
    else
        f.result:SetText("")
    end
    f.sell:SetEnabled(SellBlock(scanned) == nil)
    f.sell:Repaint()
    R.Interact.RefreshTip(f.sell)
end

local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(SETTLE, function()
        scheduled = false
        W.Refresh()
    end)
end

local function Listen(on)
    for _, event in ipairs({ "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        if on and not active[event] then
            active[event] = Schedule
            R:On(event, Schedule)
        elseif not on and active[event] then
            R:Off(event, active[event])
            active[event] = nil
        end
    end
end

local function AddFromBox()
    local text = f.box:GetText() or ""
    if text:match("^%s*$") then return end
    local ok, result = MS.Exclude(text)
    if ok then
        f.box:SetText("")
        f.box:ClearFocus()
        f.note:SetText("")
    else
        f.note:SetText(result)
    end
    W.Refresh()
end

-- An item dropped on the add area: kept, and put back where it came from.
local function AddFromCursor()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return end
    local ok, result = MS.Exclude(id)
    ClearCursor()
    f.note:SetText(ok and "" or result)
    W.Refresh()
end

local function Build()
    S = R.ChronicleStyle
    if not (S and S.Frame and MS) then return false end
    f = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
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
    tinsert(UISpecialFrames, FRAME_NAME)   -- Escape closes it
    S.Frame(f, WIDTH, HEIGHT)
    S.Header(f, HEADER)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("LEFT", f, "TOPLEFT", PAD, -(HEADER / 2 + 4))
    f.title:SetTextColor(Color(S.color.text))
    f.title:SetText("Ordinary food and drink")
    f.close = S.Close(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -10, -(HEADER / 2 - 6))

    f.mode = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.mode:SetPoint("TOPLEFT", PAD, -(HEADER + 16))
    f.mode:SetWidth(WIDTH - PAD * 2)
    f.mode:SetJustifyH("LEFT")
    f.mode:SetWordWrap(true)

    local listTop = HEADER + 56
    local listH = ROW_H * VISIBLE_ROWS + 12
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PAD, -listTop)
    box:SetSize(WIDTH - PAD * 2, listH)
    S.Well(box, WIDTH - PAD * 2, listH)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    S.ScrollBar(scroll)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(WIDTH - PAD * 2 - 6 - 26, 1)
    scroll:SetScrollChild(f.content)

    -- The add area: a box for a pasted link or ID, and a place to drop an item from your bags.
    local addTop = listTop + listH + 12
    f.addLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.addLabel:SetPoint("TOPLEFT", PAD, -addTop)
    f.addLabel:SetTextColor(Color(S.color.textDim))
    f.addLabel:SetText("Never sell an item: drop it here from your bags, or paste its link or item ID.")
    f.drop = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.drop:SetPoint("TOPLEFT", PAD, -(addTop + 18))
    f.drop:SetSize(WIDTH - PAD * 2, 34)
    f.drop:EnableMouse(true)
    S.Well(f.drop, WIDTH - PAD * 2, 34)
    f.drop:SetScript("OnReceiveDrag", AddFromCursor)
    f.drop:SetScript("OnMouseUp", AddFromCursor)
    f.box = CreateFrame("EditBox", nil, f.drop, "InputBoxTemplate")
    f.box:SetSize(WIDTH - PAD * 2 - 110, 20)
    f.box:SetPoint("LEFT", 12, 0)
    f.box:SetAutoFocus(false)
    f.box:SetMaxLetters(256)
    f.box:SetScript("OnEnterPressed", AddFromBox)
    f.box:SetScript("OnEscapePressed", f.box.ClearFocus)
    f.add = S.Button(f.drop, "Add", 70, "secondary", AddFromBox)
    f.add:SetPoint("RIGHT", -8, 0)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", PAD, -(addTop + 56))
    f.note:SetWidth(WIDTH - PAD * 2)
    f.note:SetJustifyH("LEFT")
    f.note:SetTextColor(Color(S.color.emberHi))

    f.result = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.result:SetPoint("BOTTOMLEFT", PAD, 18)
    f.result:SetWidth(WIDTH - PAD * 2 - 220)
    f.result:SetJustifyH("LEFT")
    f.result:SetTextColor(Color(S.color.textDim))

    f.refresh = S.Button(f, "Refresh", 80, "secondary", function() W.Refresh() end)
    f.refresh:SetPoint("BOTTOMRIGHT", -PAD - 130, 14)
    R.Interact.Tip(f.refresh, "Refresh", "Looks at your bags again. Nothing is sold or moved.")
    f.sell = S.Button(f, "Sell now", 120, "primary", function()
        local why = SellBlock(scanned)
        if why then R.Print("%s", why) return end
        MS.Begin(true)
        W.Refresh()
    end)
    f.sell:SetPoint("BOTTOMRIGHT", -PAD, 14)
    R.Interact.Tip(f.sell, "Sell now", function()
        local why = SellBlock(scanned)
        if why then return "Sells the stacks listed under \"Would be sold\" at the open merchant, one at a time.", why end
        return ("Sells the stacks listed under \"Would be sold\" at the open merchant, one at a time, at most %d. Your click; nothing else is sold. Older entries in the merchant's Buyback tab can be pushed out."):format(MS.Limit())
    end)

    f:SetScript("OnShow", function() Listen(true); W.Refresh() end)
    f:SetScript("OnHide", function() Listen(false); scheduled = false end)
    return true
end

local function Ready()
    if f then return true end
    return Build()
end

function W.Show()
    if not Ready() then R.Print("this window isn't available right now.") return end
    f:Show()
    f:Raise()
end

function W.Hide()
    if f then f:Hide() end
end

function W.Toggle()
    if f and f:IsShown() then f:Hide() else W.Show() end
end

function W.IsShown() return f ~= nil and f:IsShown() end

-- The feature changed something (a run ended, an option or the list changed): draw again if open.
MS.OnChange = function()
    if f and f:IsShown() then Schedule() end
end
