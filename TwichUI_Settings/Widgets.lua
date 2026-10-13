-- TwichUI Settings: the controls the settings window draws with
-- Built on chronicle/Style.lua's helpers and a copy of its palette (Style.lua's own colors are never changed),
-- so the window looks complete with no other addon. Flat textures only; nothing here runs per frame.
--
--   Wg.pal                      the window's palette (Style.lua's, plus a few colors of its own)
--   Wg.Text(parent, kind)       a font string: "brand", "title", "heading", "body", "small", "meta"
--   Wg.Surface(frame, ...)      a flat fill with a 1px edge
--   Wg.Button(parent, label, w, kind, onClick)    kind: "primary", "secondary" or "danger"
--   Wg.Checkbox, Wg.Slider, Wg.Dropdown, Wg.Swatch, Wg.EditBox, Wg.ArrowButton, Wg.Scroll
--   Wg.CloseMenu()              puts away the dropdown list, if one is open

local R = TwichUI
local S = R.ChronicleStyle
local Wg = {}
R.SettingsWidgets = Wg

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
-- The bundled fonts only have Western letters; these clients use the game's own fonts instead.
local NON_WESTERN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------
local pal = S.NewPalette()
pal.surface = { 0.178, 0.137, 0.098 }     -- a section's card, a shade above the window
pal.nav = { 0.118, 0.089, 0.064 }         -- the left-hand list's well
pal.danger = {                            -- Reset and other actions that put things back: an ember outline
    border = { 0.55, 0.30, 0.24 }, bg = { 0.13, 0.085, 0.066 }, text = { 0.92, 0.62, 0.52 },
    hotBorder = { 0.80, 0.44, 0.35 }, hotBg = { 0.20, 0.115, 0.09 }, hotText = { 1, 0.78, 0.68 },
}
Wg.pal = pal

-- Style.lua's buttons read pal.primary or pal.quiet; a danger button is a quiet one in ember.
local dangerPal = setmetatable({ quiet = pal.danger }, { __index = pal })

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local KINDS = {
    brand = { "GameFontNormalLarge", 20, FONT_TITLE, pal.gold },
    title = { "GameFontNormalLarge", 17, FONT_TITLE, pal.text },
    heading = { "GameFontNormal", nil, nil, pal.gold },
    body = { "GameFontHighlight", nil, nil, pal.text },
    small = { "GameFontHighlightSmall", nil, nil, pal.textDim },
    meta = { "GameFontHighlightSmall", nil, nil, pal.stone },
}

function Wg.Text(parent, kind, layer)
    local k = KINDS[kind] or KINDS.body
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", k[1])
    if k[3] then
        local locale = GetLocale and GetLocale()
        if NON_WESTERN[locale] or not fs:SetFont(k[3], k[2], "") then
            local font = _G[k[1]]
            local file = font and font.GetFont and font:GetFont()
            if file then fs:SetFont(file, k[2], "") end
        end
    end
    fs:SetTextColor(k[4][1], k[4][2], k[4][3])
    fs:SetJustifyH("LEFT")
    return fs
end

function Wg.Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

---------------------------------------------------------------------------
-- Surfaces
---------------------------------------------------------------------------
function Wg.Surface(frame, fill, fillAlpha, edge, edgeAlpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fillAlpha or 1)
    edge = edge or pal.bronzeLo
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edgeAlpha or 1)
end

function Wg.Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- A small down- or up-pointing stepped arrowhead of 1px lines, centred on (x, y) of anchor.
function Wg.Chevron(parent, anchor, point, x, y, down, c)
    local px = {}
    for i = 1, 3 do
        local t = Wg.Solid(parent, "OVERLAY", c or pal.gold, 0.95)
        local width = down and ((4 - i) * 2 - 1) or (i * 2 - 1)
        t:SetSize(width, 1)
        t:SetPoint("CENTER", anchor, point, x, y + (2 - i))
        px[i] = t
    end
    return px
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
function Wg.Button(parent, label, w, kind, onClick)
    local b
    if kind == "danger" then
        b = S.Button(parent, label, w, "secondary", onClick, dangerPal)
    else
        b = S.Button(parent, label, w, kind == "primary" and "primary" or "secondary", onClick, pal)
    end
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

-- A small square button with an arrowhead (move up / move down in a ranked list).
function Wg.ArrowButton(parent, dir, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    Wg.Surface(b, pal.well, 1, pal.bronzeLo, 1)
    local px = Wg.Chevron(b, b, "CENTER", 0, 0, dir == "down")
    local function Paint()
        local on = b:IsEnabled()
        for _, t in ipairs(px) do t:SetAlpha(on and 1 or 0.3) end
        local edge = (on and b:IsMouseOver()) and pal.bronze or pal.bronzeLo
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    b:HookScript("OnEnter", Paint)
    b:HookScript("OnLeave", Paint)
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    Paint()
    return b
end

---------------------------------------------------------------------------
-- Checkbox: an inset square with a gold mark. SetChecked / GetChecked / SetActive(enabled).
---------------------------------------------------------------------------
function Wg.Checkbox(parent, onToggle)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    Wg.Surface(b, pal.well, 1, pal.bronze, 0.9)
    local mark = b:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    mark:SetPoint("CENTER", 0, 0)
    mark:SetSize(22, 22)
    local fill = Wg.Solid(b, "ARTWORK", pal.gold, 0.16)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local checked, active, over = false, true, false
    local function Paint()
        mark:SetShown(checked)
        fill:SetShown(checked)
        local c = active and pal.gold or pal.stone
        mark:SetVertexColor(c[1], c[2], c[3], active and 1 or 0.6)
        local edge = not active and pal.bronzeLo or (over and pal.gold or pal.bronze)
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], active and 0.95 or 0.6)
    end
    function b:SetChecked(v) checked = v and true or false; Paint() end
    function b:GetChecked() return checked end
    function b:SetActive(v) active = v and true or false; Paint() end
    function b:SetHot(v) over = v and true or false; Paint() end
    b:SetScript("OnEnter", function() over = true; Paint() end)
    b:SetScript("OnLeave", function() over = false; Paint() end)
    b:SetScript("OnClick", function()
        if not active then return end
        if onToggle then onToggle(not checked) end
    end)
    Paint()
    return b
end

---------------------------------------------------------------------------
-- Edit box: an inset field. Plain text in and out.
---------------------------------------------------------------------------
function Wg.EditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h or 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    Wg.Surface(eb, pal.well, 1, pal.bronzeLo, 1)
    local function Edge()
        local c = eb:HasFocus() and pal.gold or (eb:IsMouseOver() and pal.bronze or pal.bronzeLo)
        eb:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
    eb:HookScript("OnEditFocusGained", Edge)
    eb:HookScript("OnEditFocusLost", Edge)
    eb:HookScript("OnEnter", Edge)
    eb:HookScript("OnLeave", Edge)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb.PaintEdge = Edge
    return eb
end

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
    local fill = Wg.Solid(s, "ARTWORK", pal.bronze, 0.9)
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)

    local min, max, silent, active = 0, 1, false, true
    local function Fraction(v) return max > min and (v - min) / (max - min) or 0 end
    local function PaintFill(v)
        local width = (s:GetWidth() or 0) * Fraction(v)
        fill:SetWidth(math.max(1, width))
    end
    local function Paint()
        local c = active and pal.gold or pal.stone
        thumb:SetColorTexture(c[1], c[2], c[3], active and 1 or 0.6)
        local f = active and pal.bronze or pal.bronzeLo
        fill:SetColorTexture(f[1], f[2], f[3], 0.9)
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
    menu:Hide()
    menu.rows = {}
    for i = 1, MENU_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_H)
        row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * MENU_ROW_H)
        row:SetPoint("TOPRIGHT", -10, -4 - (i - 1) * MENU_ROW_H)
        row.hover = Wg.Solid(row, "BACKGROUND", pal.gold, 0.10)
        row.hover:SetAllPoints()
        row.hover:Hide()
        row.mark = Wg.Solid(row, "ARTWORK", pal.gold, 1)
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
    menu.thumb = Wg.Solid(menu, "OVERLAY", pal.bronze, 0.8)
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
            Wg.Color(row.text, chosen and pal.gold or pal.text)
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
    end, pal)
    b.onPick = onPick
    b.active = true
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
    Wg.Surface(b, pal.well, 1, pal.bronze, 0.9)
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
        local edge = active and pal.bronze or pal.bronzeLo
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], active and 0.9 or 0.6)
    end
    b:SetScript("OnEnter", function(self) if active then self:SetBackdropBorderColor(pal.gold[1], pal.gold[2], pal.gold[3], 1) end end)
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
    S.ScrollBar(scroll, pal)
    return scroll, content
end
