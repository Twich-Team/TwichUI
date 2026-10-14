-- TwichUI Settings: the controls the settings window draws with
-- The shared look (palette, text, surfaces, buttons, checkbox, edit box, rim and header, motion) is the core's
-- Look.lua, which the sharing window draws with too; this file adds the controls only the settings window
-- needs (slider, dropdown and its list, color swatch, the scrolling content area) and offers all of them as
-- Wg.*, so a page or the window has one table to draw with.
--
--   Wg.Slider, Wg.Dropdown, Wg.Swatch, Wg.Scroll   (here)
--   Wg.CloseMenu()              puts away the dropdown list, if one is open
--   everything else is Look's: Wg.pal, Wg.Text, Wg.Surface, Wg.Button, Wg.Checkbox, Wg.EditBox, Wg.Motion, ...

local R = TwichUI
local S = R.ChronicleStyle
local Look = R.Look
local Wg = {}
R.SettingsWidgets = Wg
for k, v in pairs(Look) do Wg[k] = v end

local WHITE = "Interface\\Buttons\\WHITE8x8"
local pal, Motion, fieldPal = Look.pal, Look.Motion, Look.fieldPal

---------------------------------------------------------------------------
-- Slider: a thin track with a bronze fill, a gold thumb, and the value in a box beside it that can be typed in.
-- onChange(value) runs for the player's own changes only. SetRange(min, max, step), SetValue(v), SetActive(on).
---------------------------------------------------------------------------
function Wg.Slider(parent, w, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, 22)
    local box = Wg.EditBox(holder, 44, 20)
    box:SetPoint("RIGHT", 0, 0)
    box:SetJustifyH("RIGHT")
    box:SetMaxLetters(6)
    local s = CreateFrame("Slider", nil, holder, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("LEFT", 0, 0)
    s:SetPoint("RIGHT", box, "LEFT", -10, 0)
    s:SetHeight(16)
    s:SetHitRectInsets(0, 0, -4, -4)
    if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end
    s:SetThumbTexture(WHITE)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(6, 14)
    local track = Wg.Solid(s, "BACKGROUND", pal.well, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    local trackEdge = Wg.Solid(s, "BORDER", pal.bronzeLo, 0.9)
    trackEdge:SetHeight(1)
    trackEdge:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, 0)
    trackEdge:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, 0)
    local fill = Wg.Solid(s, "ARTWORK", pal.tealLo, 1)
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)

    local min, max, silent, active = 0, 1, false, true
    local function Fraction(v) return max > min and (v - min) / (max - min) or 0 end
    local function PaintFill(v)
        local width = (s:GetWidth() or 0) * Fraction(v)
        fill:SetWidth(math.max(1, width))
    end
    local function Paint()
        local c = active and pal.teal or pal.stone
        thumb:SetColorTexture(c[1], c[2], c[3], active and 1 or 0.6)
        local f = active and pal.tealLo or pal.bronzeLo
        fill:SetColorTexture(f[1], f[2], f[3], 1)
        box:SetTextColor(active and pal.text[1] or pal.stone[1], active and pal.text[2] or pal.stone[2], active and pal.text[3] or pal.stone[3])
    end
    local function Show(v) if not box:HasFocus() then box:SetText(tostring(v)) end end

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        PaintFill(v)
        Show(v)
        if not silent and active and onChange then onChange(v) end
    end)
    s:SetScript("OnSizeChanged", function() PaintFill(s:GetValue()) end)
    s:SetScript("OnMouseWheel", nil)

    -- the box: Enter keeps a number in range, Esc puts the shown value back
    box:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        self:ClearFocus()
        if v and active then
            v = math.floor(math.max(min, math.min(max, v)) + 0.5)
            s:SetValue(v)   -- runs onChange when it moved
        end
        Show(math.floor(s:GetValue() + 0.5))
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        Show(math.floor(s:GetValue() + 0.5))
    end)
    box:HookScript("OnEditFocusLost", function() Show(math.floor(s:GetValue() + 0.5)) end)

    function holder:SetRange(lo, hi, step)
        min, max = lo, hi
        silent = true
        s:SetMinMaxValues(lo, hi)
        s:SetValueStep(step or 1)
        silent = false
    end
    function holder:SetValue(v)
        silent = true
        s:SetValue(v)
        silent = false
        PaintFill(v)
        Show(v)
    end
    function holder:SetActive(on)
        active = on and true or false
        if s.SetEnabled then s:SetEnabled(active) end
        box:SetEnabled(active)
        Paint()
    end
    holder.slider, holder.box = s, box
    Paint()
    return holder
end

---------------------------------------------------------------------------
-- Dropdown: a button showing the chosen label; a click opens one shared list beneath it.
-- choices(): { { value, label, tooltip }, ... }; onPick(value). SetValue(v, label), SetActive(on).
---------------------------------------------------------------------------
local menu   -- the one open list
local MENU_ROWS, MENU_ROW_H = 12, 20

local function BuildMenu()
    menu = CreateFrame("Frame", "TwichUISettingsMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    S.Popover(menu, pal)
    menu:SetBackdropBorderColor(pal.control[1], pal.control[2], pal.control[3], 1)
    if menu.twichPopover then menu.twichPopover.top:SetColorTexture(pal.text[1], pal.text[2], pal.text[3], 0.05) end
    menu:Hide()
    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_H)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
        row:SetPoint("TOPRIGHT", -10, -4 - (i - 1) * MENU_ROW_H)
        row.hover = Wg.Solid(row, "BACKGROUND", pal.text, 0.07)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.mark = Wg.Solid(row, "ARTWORK", pal.teal, 1)
        row.mark:SetSize(2, MENU_ROW_H - 6)
        row.mark:SetPoint("LEFT", 2, 0)
        row.text = Wg.Text(row, "small")
        row.text:SetPoint("LEFT", 10, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnEnter", function(self)
            self.hover:Show()
            if self.choice and self.choice.tooltip and GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.choice.label, 1, 1, 1)
                GameTooltip:AddLine(self.choice.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hover:Hide()
            if GameTooltip and GameTooltip:GetOwner() == self then GameTooltip:Hide() end
        end)
        row:SetScript("OnClick", function(self)
            local owner, value = menu.owner, self.choice and self.choice.value
            Wg.CloseMenu()
            if owner and owner.onPick then owner.onPick(value) end
        end)
        menu.rows[i] = row
    end
    menu.thumb = Wg.Solid(menu, "OVERLAY", pal.thumb, 0.8)
    menu.thumb:SetWidth(3)
    menu:SetScript("OnMouseWheel", function(self, delta)
        local most = math.max(0, #self.choices - MENU_ROWS)
        self.offset = math.max(0, math.min(most, self.offset - delta))
        Wg.PaintMenu()
    end)
    -- a click anywhere else puts it away
    menu:SetScript("OnEvent", function(self)
        if not (self:IsMouseOver() or (self.owner and self.owner:IsMouseOver())) then Wg.CloseMenu() end
    end)
    menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self.owner = nil
    end)
end

function Wg.PaintMenu()
    local choices, current = menu.choices, menu.current
    for i, row in ipairs(menu.rows) do
        local choice = choices[menu.offset + i]
        row.choice = choice
        if choice then
            row.text:SetText(choice.label)
            local chosen = choice.value == current
            row.mark:SetShown(chosen)
            Wg.Color(row.text, chosen and pal.tealHi or pal.text)
            row:Show()
        else
            row:Hide()
        end
    end
    local most = #choices - MENU_ROWS
    if most > 0 then
        local h = MENU_ROWS * MENU_ROW_H
        local size = math.max(16, h * MENU_ROWS / #choices)
        menu.thumb:SetHeight(size)
        menu.thumb:ClearAllPoints()
        menu.thumb:SetPoint("TOPRIGHT", -4, -4 - (h - size) * (menu.offset / most))
        menu.thumb:Show()
    else
        menu.thumb:Hide()
    end
end

function Wg.MenuShown() return menu ~= nil and menu:IsShown() end

function Wg.CloseMenu()
    if menu and menu:IsShown() then menu:Hide() end
end

local function OpenMenu(owner)
    if not menu then BuildMenu() end
    if menu:IsShown() and menu.owner == owner then Wg.CloseMenu() return end
    local choices = owner.choices and owner.choices() or {}
    menu.owner, menu.choices, menu.current, menu.offset = owner, choices, owner.value, 0
    for i, choice in ipairs(choices) do
        if choice.value == owner.value then
            menu.offset = math.max(0, math.min(#choices - MENU_ROWS, i - math.floor(MENU_ROWS / 2)))
            break
        end
    end
    local shown = math.max(1, math.min(MENU_ROWS, #choices))
    menu:SetSize(math.max(owner:GetWidth(), 160), shown * MENU_ROW_H + 8)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
    Wg.PaintMenu()
    menu:Show()
    menu:Raise()
end

function Wg.Dropdown(parent, w, onPick)
    local b = S.DropButton(parent, w, function(self)
        if self.active ~= false then OpenMenu(self) end
    end, fieldPal)
    b.onPick = onPick
    b.active = true
    Wg.Recess(b, 0.9)   -- it shows a value, like a field; only its arrowhead says it opens a list
    Wg.Hover(b, pal.text, 0.05)
    function b:SetChoices(fn) self.choices = fn end
    function b:SetValue(v, label)
        self.value = v
        self.text:SetText(label or tostring(v or ""))
    end
    function b:SetActive(on)
        self.active = on and true or false
        self:SetEnabled(self.active)
        if not self.active and menu and menu.owner == self then Wg.CloseMenu() end
    end
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

---------------------------------------------------------------------------
-- Color swatch: the color in a framed square; a click opens the game's color picker. Cancel there puts the
-- color it had back. Colors are AARRGGBB text, as the game's own swatches save them.
---------------------------------------------------------------------------
local function Hex(r, g, b)
    if CreateColor then
        local c = CreateColor(r, g, b, 1)
        if c.GenerateHexColor then return c:GenerateHexColor() end
    end
    local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return ("ff%02x%02x%02x"):format(Byte(r), Byte(g), Byte(b))
end
Wg.Hex = Hex

function Wg.ParseHex(text)
    if type(text) ~= "string" then return 1, 1, 1 end
    local hex = text:match("^%x%x(%x%x%x%x%x%x)$") or text:match("^(%x%x%x%x%x%x)$")
    if not hex then return 1, 1, 1 end
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

function Wg.Swatch(parent, onPick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(40, 18)
    Wg.Surface(b, pal.well, 1, pal.control, 0.95)
    Wg.Recess(b)
    local color = Wg.Solid(b, "ARTWORK", { 1, 1, 1 }, 1)
    color:SetPoint("TOPLEFT", 3, -3)
    color:SetPoint("BOTTOMRIGHT", -3, 3)
    local active, value = true, nil
    -- The game's picker calls this on the swatch it was opened from, so the swatch follows the wheel as it
    -- turns (a Cancel there puts the old color back through onPick).
    function b:SetColorRGB(r, g, bl)
        color:SetColorTexture(r, g, bl, active and 1 or 0.45)
    end
    function b:SetValue(v)
        value = v
        self:SetColorRGB(Wg.ParseHex(v))
    end
    function b:SetActive(on)
        active = on and true or false
        self:SetValue(value)
        local edge = active and pal.control or pal.bronzeLo
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], active and 0.95 or 0.6)
    end
    b:SetScript("OnEnter", function(self) if active then self:SetBackdropBorderColor(pal.tealHi[1], pal.tealHi[2], pal.tealHi[3], 1) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(active) end)
    b:SetScript("OnClick", function(self)
        if not (active and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
        local r, g, bl = Wg.ParseHex(value)
        ColorPickerFrame:SetupColorPickerAndShow({
            swatch = self, r = r, g = g, b = bl, hasOpacity = false,
            swatchFunc = function() onPick(Hex(ColorPickerFrame:GetColorRGB())) end,
            cancelFunc = function() onPick(Hex(ColorPickerFrame:GetPreviousValues())) end,
        })
    end)
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

---------------------------------------------------------------------------
-- A scroll frame with Style.lua's slim bar. Returns scroll, content.
---------------------------------------------------------------------------
function Wg.Scroll(parent, contentWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    Look.ScrollBar(scroll)
    return scroll, content
end
