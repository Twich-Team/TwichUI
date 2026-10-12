-- TwichUI: Party pins, the data bar menu
-- What a click on the data bar entry opens (pins/Broker.lua): a short list of the pins on your map, a
-- pared-down version of the pin window. Each row has the pin's color (click it to pick another), its name
-- (click it to rename), where it is, who made it, and a remove button. Under the list: a link to the full
-- pin window and Clear all pins.
--   Remove: a local pin is deleted; one of your own party pins asks first and is then removed for the
--   whole party; someone else's party pin is taken off your map only (the pin window's Removed filter
--   restores it).
--   Clear all pins: asks first. Deletes your local pins and takes party pins off your map. Nothing is sent
--   and party pins you shared stay on your party's maps.
-- Everything is checked again when it runs (PN.Can), exactly as in the pin window. The menu has nothing
-- secure in it, so unlike the Mage launchers' menus it can be used in combat. Its background and border are
-- the player's own (pinsBrokerMenu in pins/Look.lua); its text follows the pin window's font and size.
-- Drawn with TwichUI's own look; it doesn't need EllesmereUI.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local PW = R.PinsWindow
local S = R.ChronicleStyle
local Tip = function(...) return R.Interact.Tip(...) end
local BM = {}
R.PinsBrokerMenu = BM

local NAME = "TwichUIPinsMenu"
local WIDTH, PAD = 300, 8
local TITLE_H, FOOT_H, ROW_H, MAX_ROWS, EMPTY_H = 28, 26, 34, 7, 66
local BAR = 22                       -- room kept for the scroll bar
local DANGER = { 0.92, 0.55, 0.44 }
local pal = PL.palette
local menu, scroll, content, rows, picker, edit
local owner                          -- the data bar frame it was opened from
local previewing = false             -- opened from the options page: stays until closed
local editing                        -- the entry being renamed
local dirty, scheduled = false, false
local entries = {}
local pad = PAD

local function Notice(text) R.PinsMap.Notice(text) end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- Changing a pin from here
---------------------------------------------------------------------------
-- fields: { name = } or { color = }. Asked again at this moment, as the pin window does. Returns whether it was kept.
local function Change(e, fields)
    local ok, why = PN.Can("edit", e)
    if not ok then Notice(why) return false end
    local pin = PN.Fresh(e)
    if not pin then Notice(PN.Reason("gone")) return false end
    if e.kind == "local" then
        ok, why = PN.UpdateLocal(pin.id, fields)
    else
        local updated
        updated, why = R.PinSync.UpdateParty(pin.key, fields)
        ok = updated ~= nil
    end
    if not ok then
        -- a code from Pins, or already a sentence from a permission check
        Notice(why and why:find(" ") and why or PN.Reason(why))
        return false
    end
    return true
end

local function Remove(e)
    local pin = PN.Fresh(e)
    if not pin then Notice(PN.Reason("gone")) return end
    if e.kind == "local" then
        local ok, why = PN.Can("delete", e)
        if not ok then Notice(why) return end
        local done, code = PN.RemoveLocal(pin.id)
        if not done then Notice(PN.Reason(code)) end
    elseif pin.mine then
        local ok, why = PN.Can("removeParty", e)
        if not ok then Notice(why) return end
        PW.ConfirmRemoveForParty(e)
    else
        local ok, why = PN.Can("dismiss", e)
        if not ok then Notice(why) return end
        PN.Dismiss(pin.key)
    end
end

local function CountPins()
    local party = 0
    for _, e in ipairs(entries) do if e.kind == "party" then party = party + 1 end end
    return #entries, party
end

-- Asks first; the question says exactly what will happen, for the pins there are now.
local function ClearAll()
    local localCount, party = PN.LocalCount(), 0
    for _, p in ipairs(PN.SharedPins()) do if not PN.IsDismissed(p.key) then party = party + 1 end end
    if localCount + party == 0 then return end
    local text
    if localCount > 0 and party > 0 then
        text = ("Clear all pins?\n\nThis deletes your %d local %s for good and takes %d party %s off your map. Party pins aren't deleted for anyone else: nothing is sent, and you can restore them under Removed in the pin window."):format(
            localCount, localCount == 1 and "pin" or "pins", party, party == 1 and "pin" or "pins")
    elseif localCount > 0 then
        text = ("Delete all %d of your local %s? This can't be undone."):format(localCount, localCount == 1 and "pin" or "pins")
    else
        text = ("Take all %d party %s off your map? Nothing is sent and the pins stay with your party. You can restore them under Removed in the pin window."):format(
            party, party == 1 and "pin" or "pins")
    end
    R.Interact.Confirm("TWICHUI_PINS_CLEAR_ALL", text, function()
        PN.ClearLocal()
        PN.DismissAll()
    end, { accept = "Clear all", valid = function() return R:Enabled("partyPins") end })
end

---------------------------------------------------------------------------
-- The color picker: one small row of the pin colors under the swatch that was clicked
---------------------------------------------------------------------------
local function HidePicker()
    if picker then picker:Hide() end
end

local function BuildPicker()
    if picker then return end
    picker = CreateFrame("Frame", nil, menu, "BackdropTemplate")
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(menu:GetFrameLevel() + 20)
    picker:EnableMouse(true)
    picker:Hide()
    S.Popover(picker, pal)
    picker.swatches = {}
    local n = #PN.COLORS
    picker:SetSize(n * 26 + 8, 34)
    for i, color in ipairs(PN.COLORS) do
        local b = CreateFrame("Button", nil, picker, "BackdropTemplate")
        b:SetSize(22, 22)
        b:SetPoint("LEFT", 6 + (i - 1) * 26, 0)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        local c = color[3]
        b:SetBackdropColor(c[1], c[2], c[3], 1)
        b.id = color[1]
        b:SetScript("OnClick", function(self)
            local e = picker.entry
            HidePicker()
            if e then Change(e, { color = self.id }) end
        end)
        Tip(b, nil, color[2])
        picker.swatches[i] = b
    end
end

local function OpenPicker(row)
    local e = row.entry
    if not e then return end
    local ok, why = PN.Can("edit", e)
    if not ok then Notice(why) return end
    local pin = PN.Fresh(e)
    if not pin then return end
    BuildPicker()
    S.PaintPopover(picker, pal)
    for _, b in ipairs(picker.swatches) do
        local on = b.id == pin.color
        local edge = on and pal.text or pal.bronzeLo
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    picker.entry = e
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", row.pick, "BOTTOMLEFT", -2, -2)
    picker:Show()
    picker:Raise()
end

---------------------------------------------------------------------------
-- Renaming in place
---------------------------------------------------------------------------
local Request   -- below

local function StopEdit()
    if not editing then return end
    editing = nil
    if edit then
        edit:ClearFocus()
        edit:Hide()
    end
    if dirty then Request() end
end

local function CommitEdit(text)
    local e = editing
    StopEdit()
    if not e then return end
    local pin = PN.Fresh(e)
    if not pin then Notice(PN.Reason("gone")) return end
    local name = PN.CleanName(text)
    if not name then Notice(PN.Reason("empty-name")) return end
    if name == pin.name then return end
    Change(e, { name = name })
end

local function BuildEdit()
    if edit then return end
    edit = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    edit:SetHeight(20)
    edit:SetAutoFocus(false)
    edit:SetMaxBytes(PN.NAME_MAX + 1)
    PL.Edit(edit)
    edit:Hide()
    edit:SetScript("OnEnterPressed", function(self) CommitEdit(self:GetText()) end)
    edit:SetScript("OnEscapePressed", StopEdit)
    edit:SetScript("OnEditFocusLost", StopEdit)   -- clicking elsewhere leaves the name as it was
end

local function StartEdit(row)
    local e = row.entry
    if not e then return end
    local ok, why = PN.Can("edit", e)
    if not ok then Notice(why) return end
    local pin = PN.Fresh(e)
    if not pin then return end
    HidePicker()
    BuildEdit()
    editing = e
    edit:SetParent(row)
    edit:ClearAllPoints()
    edit:SetPoint("LEFT", row.pick, "RIGHT", 8, 0)
    edit:SetPoint("RIGHT", row.owner, "LEFT", -4, 0)
    edit:SetFrameLevel(row:GetFrameLevel() + 5)
    edit:SetText(pin.name)
    edit:Show()
    edit:SetFocus()
    edit:HighlightText()
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function OwnerText(e)
    local pin = e.pin
    if e.kind == "local" then return pin.copiedFrom and "copy" or "local" end
    if pin.mine then return "you" end
    local SH = R.Share
    return SH and SH.Short(pin.owner) or pin.owner
end

local function RemoveTip(row)
    local e = row.entry
    if not e then return nil end
    if e.kind == "local" then return "Delete this pin. It can't be undone." end
    local pin = PN.Fresh(e)
    if pin and pin.mine then return "Remove it for the entire party. Asks first." end
    return "Takes it off your map only. Nothing is sent; restore it under Removed in the pin window."
end

local function NewRow(i)
    local row = CreateFrame("Frame", nil, content)
    S.RowArt(row, pal)
    row.pick = CreateFrame("Button", nil, row)
    row.pick:SetSize(24, 24)
    row.pick:SetPoint("LEFT", 4, 0)
    row.icon = row.pick:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(PL.PIN_TEXTURE)
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("CENTER")
    row.badgeEdge = row.pick:CreateTexture(nil, "OVERLAY", nil, 1)
    row.badgeEdge:SetColorTexture(0.06, 0.04, 0.03, 1)
    row.badgeEdge:SetSize(7, 7)
    row.badgeEdge:SetPoint("CENTER", row.icon, "TOPLEFT", PL.BadgePoint(20))
    row.badge = row.pick:CreateTexture(nil, "OVERLAY", nil, 2)
    row.badge:SetColorTexture(0.93, 0.87, 0.71, 1)
    row.badge:SetSize(5, 5)
    row.badge:SetPoint("CENTER", row.badgeEdge, "CENTER")
    row.pick:SetScript("OnClick", function() OpenPicker(row) end)
    Tip(row.pick, nil, function()
        local e = row.entry
        if not e then return nil end
        local ok, why = PN.Can("edit", e)
        if ok then return "Change this pin's color." end
        return nil, why
    end, "ANCHOR_RIGHT")

    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(18, 18)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove.text = PL.Text(row.remove, "GameFontNormalSmall", "name")
    row.remove.text:SetPoint("CENTER")
    row.remove.text:SetJustifyH("CENTER")
    row.remove.text:SetText("x")
    row.remove:SetScript("OnClick", function() local e = row.entry if e then Remove(e) end end)
    Tip(row.remove, nil, function() return RemoveTip(row) end, "ANCHOR_RIGHT")
    row.remove:HookScript("OnEnter", function(self) Paint(self.text, DANGER) end)
    row.remove:HookScript("OnLeave", function(self) Paint(self.text, pal.stone) end)

    row.owner = PL.Text(row, "GameFontNormalSmall", "meta")
    row.owner:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    row.owner:SetJustifyH("RIGHT")
    row.owner:SetWidth(56)
    row.owner:SetWordWrap(false)

    -- the name is a button: a click renames
    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetHeight(16)
    row.nameBtn:SetPoint("TOPLEFT", row.pick, "TOPRIGHT", 8, -1)
    row.nameBtn:SetPoint("RIGHT", row.owner, "LEFT", -4, 0)
    row.name = PL.Text(row.nameBtn, "GameFontHighlight", "name")
    row.name:SetAllPoints()
    row.name:SetWordWrap(false)
    row.nameBtn:SetScript("OnClick", function() StartEdit(row) end)
    Tip(row.nameBtn, nil, function()
        local e = row.entry
        local pin = e and PN.Fresh(e)
        if not pin then return nil end
        local ok, why = PN.Can("edit", e)
        local body = pin.name .. "\n" .. PN.Describe(pin)
        if ok then return body .. "\nClick the name to rename it." end
        return body, why
    end, "ANCHOR_RIGHT")
    row.nameBtn:HookScript("OnEnter", function(self)
        local e = row.entry
        if e and PN.Can("edit", e) then Paint(row.name, pal.gold) end
    end)
    row.nameBtn:HookScript("OnLeave", function() Paint(row.name, pal.text) end)

    row.sub = PL.Text(row, "GameFontNormalSmall", "meta")
    row.sub:SetPoint("TOPLEFT", row.nameBtn, "BOTTOMLEFT", 0, -1)
    row.sub:SetPoint("RIGHT", row.owner, "LEFT", -4, 0)
    row.sub:SetWordWrap(false)
    rows[i] = row
    return row
end

local function DressRow(row, e, y)
    local pin = e.pin
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHeight(ROW_H)
    local c = PN.ColorRGB(pin.color)
    row.icon:SetVertexColor(c[1], c[2], c[3], 1)
    local party = e.kind == "party"
    row.badge:SetShown(party)
    row.badgeEdge:SetShown(party)
    row.name:SetText(pin.name)
    row.sub:SetText(PN.Describe(pin))
    row.owner:SetText(OwnerText(e))
    Paint(row.name, pal.text)
    Paint(row.sub, pal.stone)
    Paint(row.owner, party and pal.gold or pal.stone)
    Paint(row.remove.text, pal.stone)
    S.PaintRow(row, pal)
    row:Show()
end

---------------------------------------------------------------------------
-- Drawing the menu
---------------------------------------------------------------------------
local function Render()
    dirty = false
    if not (menu and menu:IsShown()) then return end
    HidePicker()
    wipe(entries)
    for _, e in ipairs(PN.Entries()) do
        if not e.dismissed then entries[#entries + 1] = e end
    end
    local total, party = CountPins()
    menu.count:SetText(party > 0 and ("%d pins, %d party"):format(total, party) or (total == 1 and "1 pin" or ("%d pins"):format(total)))
    for i, e in ipairs(entries) do DressRow(rows[i] or NewRow(i), e, (i - 1) * ROW_H) end
    for i = #entries + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    content:SetHeight(math.max(1, total * ROW_H))
    menu.empty:SetShown(total == 0)
    menu.empty:SetText("No pins yet.\n\n" .. PL.HowToPlace())

    local viewH = total == 0 and EMPTY_H or math.min(total, MAX_ROWS) * ROW_H
    local inner = WIDTH - pad * 2
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -(pad + TITLE_H))
    scroll:SetSize(inner - BAR, viewH)
    content:SetWidth(inner - BAR)
    menu.empty:ClearAllPoints()
    menu.empty:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 4, -(pad + TITLE_H + 6))
    menu.empty:SetPoint("RIGHT", menu, "RIGHT", -(pad + 4), 0)
    menu.open:ClearAllPoints()
    menu.open:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", pad + 4, pad + 5)
    menu.clear:ClearAllPoints()
    menu.clear:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -(pad + 4), pad + 5)
    menu.clear:SetEnabled(total > 0)
    Paint(menu.clear.text, menu.clear:IsEnabled() and pal.stone or pal.bronzeLo)
    menu:SetSize(WIDTH, pad + TITLE_H + viewH + 8 + FOOT_H + pad)
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
end

local function Restyle()
    if not menu then return end
    pad = math.max(PAD, math.ceil(PL.Surface(PL.MenuLook, menu)))
    menu.title:ClearAllPoints()
    menu.title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
    menu.count:ClearAllPoints()
    menu.count:SetPoint("LEFT", menu.title, "RIGHT", 8, -1)
    Paint(menu.title, pal.text)
    Paint(menu.count, pal.stone)
    Paint(menu.empty, pal.stone)
    Paint(menu.open.text, pal.gold)
    if scroll and scroll.paintBar then scroll.paintBar() end
    if picker then S.PaintPopover(picker, pal) end
end

-- Coalesced: several changes in one frame redraw once. Not while a name is being typed.
function Request()
    dirty = true
    if scheduled or editing or not (menu and menu:IsShown()) then return end
    scheduled = true
    C_Timer.After(0, function()
        scheduled = false
        if dirty and not editing then Render() end
    end)
end

local function OnMouseDown()
    if previewing or not (menu and menu:IsShown()) then return end
    if menu:IsMouseOver() or (picker and picker:IsShown() and picker:IsMouseOver()) then return end
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end   -- its own click closes it
    BM.Close()
end

local function OnScaleChanged()
    if menu and menu:IsShown() then Restyle(); Render() end   -- a border is a whole number of screen pixels
end

local function TextButton(parent, label, tone, hot, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = PL.Text(b, "GameFontNormalSmall", "meta")
    b.text:SetPoint("LEFT")
    b.text:SetText(label)
    b:SetSize(math.max(24, (b.text:GetStringWidth() or 60) + 4), 16)
    b:SetScript("OnClick", onClick)
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then Paint(self.text, hot) end end)
    b:HookScript("OnLeave", function(self) Paint(self.text, self:IsEnabled() and tone or pal.bronzeLo) end)
    return b
end

local function Build()
    if menu then return end
    menu = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    menu:SetSize(WIDTH, 120)
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    rows = {}
    menu.title = PL.Text(menu, "GameFontNormal", "title")
    menu.title:SetText("Party pins")
    menu.count = PL.Text(menu, "GameFontNormalSmall", "meta")

    scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scroll.paintBar = S.ScrollBar(scroll, pal)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - PAD * 2 - BAR, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", HidePicker)

    menu.empty = PL.Text(menu, "GameFontNormalSmall", "meta")
    menu.empty:SetWordWrap(true)
    menu.empty:SetJustifyV("TOP")

    menu.open = TextButton(menu, "Open the pin window", pal.gold, pal.text, function()
        BM.Close()
        PW.Show()
    end)
    Tip(menu.open, "Pin window", "Every pin with its map and coordinates, search and filters, and everything you can do with each: show it on the map, set a waypoint, keep a party pin as a local copy.", "ANCHOR_TOP")
    menu.clear = TextButton(menu, "Clear all pins...", pal.stone, DANGER, function()
        BM.Close()
        ClearAll()
    end)
    menu.clear.text:ClearAllPoints()
    menu.clear.text:SetPoint("RIGHT")
    menu.clear.text:SetJustifyH("RIGHT")
    Tip(menu.clear, "Clear all pins", function()
        local body = "Asks first. Deletes your local pins and takes party pins off your map. Nothing is sent: pins you shared stay on your party's maps, and removed party pins can be restored in the pin window."
        if menu.clear:IsEnabled() then return body end
        return body, "There are no pins."
    end, "ANCHOR_TOP")

    menu:SetScript("OnShow", function()
        R:On("GLOBAL_MOUSE_DOWN", OnMouseDown)
        R:On("UI_SCALE_CHANGED", OnScaleChanged)
        R:On("DISPLAY_SIZE_CHANGED", OnScaleChanged)
    end)
    menu:SetScript("OnHide", function()
        R:Off("GLOBAL_MOUSE_DOWN", OnMouseDown)
        R:Off("UI_SCALE_CHANGED", OnScaleChanged)
        R:Off("DISPLAY_SIZE_CHANGED", OnScaleChanged)
        owner, previewing = nil, false
        StopEdit()
        HidePicker()
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function BM.IsOpen() return menu ~= nil and menu:IsShown() end

-- frame: the data bar's frame the click came from; the menu opens beside it.
function BM.Open(frame)
    if not R:Enabled("partyPins") then
        Notice("Party pins are turned off in TwichUI options.")
        return false
    end
    Build()
    owner, previewing = frame, false
    Restyle()
    menu:Show()
    Render()
    if frame and R.SpellMenu then
        R.SpellMenu.PlaceNear(menu, frame)
    else
        menu:ClearAllPoints()
        if SettingsPanel and SettingsPanel:IsShown() then
            menu:SetPoint("TOPLEFT", SettingsPanel, "TOPRIGHT", 8, -48)
        else
            menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    menu:Raise()
    return true
end

function BM.Close()
    if menu and menu:IsShown() then menu:Hide() end
end

function BM.Toggle(frame)
    if BM.IsOpen() then BM.Close() else BM.Open(frame) end
end

-- The options page's Preview: the real menu beside the options window, which stays until closed again (or Esc).
function BM.TogglePreview()
    if BM.IsOpen() then BM.Close() return end
    BM.Open(nil)
    previewing = true
end

-- The switch changed (Settings.lua).
function BM.Refresh()
    if not R:Enabled("partyPins") then BM.Close() end
end

PN.OnChange(Request)
PL.OnPrefChange(Request)
local function Redraw() if menu and menu:IsShown() then Restyle(); Request() end end
PL.Subscribe(Redraw)
PL.MenuLook.Subscribe(Redraw)

-- Read only, for /tui diagnostics.
function BM.Snapshot()
    return { built = menu ~= nil, open = BM.IsOpen(), rows = rows and #rows or 0, editing = editing ~= nil }
end
