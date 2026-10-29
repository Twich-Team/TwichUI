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
-- A button may set .menuWidth (its list's width, when wider than itself) and .menuAlignRight (the list hangs from its right edge).
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
    menu:SetSize(math.max(owner.menuWidth or owner:GetWidth(), 160), shown * MENU_ROW_H + 8)
    menu:ClearAllPoints()
    -- a small button near the right edge (owner.menuWidth wider than itself) opens its list leftwards, so it isn't clipped
    if owner.menuAlignRight then
        menu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    else
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end
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
-- Color swatch: the color in a framed square; a click opens a color picker (Wg.ColorPicker below). Cancel there
-- puts the color it had back. Colors are AARRGGBB text, as the game's own swatches save them.
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

---------------------------------------------------------------------------
-- The color picker a swatch opens: EllesmereUI's while it offers one, else the game's.
--
-- EllesmereUI's picker (EllesmereUI:ShowColorPicker(info, anchor), EllesmereUIOptions/EllesmereUI_Widgets_Color.lua)
-- is defined by EllesmereUI's load-on-demand EllesmereUIOptions addon and its deferred inits, which
-- EllesmereUI:EnsureLoaded() runs (EllesmereUI does this itself the first time its panel opens). So when
-- EllesmereUI is installed and its picker is not there yet, the first swatch click calls EnsureLoaded (the
-- synchronous, repeatable entry point EllesmereUI's own callers use), out of combat and once per session if it
-- fails, and opens the picker a frame later, as EllesmereUI splits its own first open: the load and the build
-- are not metered in one handler. If it cannot be loaded (not installed, options addon disabled, in combat) or
-- fails to open, the game's picker is used. Its callbacks take no arguments (the color is read from the
-- picker's frame, EllesmereUIColorPicker:GetColorRGB(), 0..1 channels, as the game's does), it calls
-- cancelFunc on Cancel, click-away, Esc and the close box (more than once for some of them), and OK fires
-- swatchFunc and then hides without cancelFunc. The game's picker does the same through the same fields.
-- Neither is given opacity: every swatch saves an opaque AARRGGBB color.
--
-- One edit at a time. An edit is { owner, original, last, onPick, generation, done, opening }:
--   * the color it started from is put back (once) by Cancel, whichever picker was used;
--   * a color is passed on only when it differs from the last one passed on, and not while the picker is
--     still opening (the game's picker calls its swatch function as it is set up);
--   * an edit from before a profile change never writes: the setting would belong to another profile.
-- An edit is over once its picker is hidden (OK, or a cancel that has already put the color back), so a
-- Cancel() after that has nothing to undo.
---------------------------------------------------------------------------
local ColorPicker = {}
Wg.ColorPicker = ColorPicker

local edit   -- the edit in progress, or nil

local function Generation()
    local P = R.Profiles
    return P and P.Generation and P.Generation() or 0
end

-- EllesmereUI when its picker can be opened now, else nil.
local function Ellesmere()
    local e = _G.EllesmereUI
    if type(e) == "table" and type(e.ShowColorPicker) == "function" then return e end
end

local loadFailed   -- EnsureLoaded was tried and left no picker: not tried again this session

-- Asks EllesmereUI to load what has the picker, once. Returns whether the picker can be opened now.
local function LoadEllesmere()
    if Ellesmere() then return true end
    local e = _G.EllesmereUI
    if loadFailed or type(e) ~= "table" or type(e.EnsureLoaded) ~= "function" then return false end
    if InCombatLockdown and InCombatLockdown() then return false end   -- tried again out of combat
    local ok, err = pcall(e.EnsureLoaded, e)
    if not ok then R.Fault("settings color picker", err) end
    if Ellesmere() then return true end
    loadFailed = true
    return false
end

-- What the picker a swatch opens would be, for the troubleshooting status. Reads only: it asks nothing of
-- EllesmereUI and loads nothing. "ready" (EllesmereUI's picker can be opened now), "on-demand" (EllesmereUI is
-- here and loads it on the first swatch click), "load-failed" (that load was tried and left no picker) or
-- "unsupported" (no EllesmereUI, or one with neither the picker nor a way to load it: the game's picker is used).
function ColorPicker.Status()
    if Ellesmere() then return "ready" end
    local e = _G.EllesmereUI
    if loadFailed then return "load-failed" end
    if type(e) == "table" and type(e.EnsureLoaded) == "function" then return "on-demand" end
    return "unsupported"
end

-- The frame EllesmereUI's picker is, once it has been built (its first open builds it).
local function EllesmereFrame()
    local f = _G.EllesmereUIColorPicker
    if type(f) == "table" and type(f.GetColorRGB) == "function" and type(f.IsShown) == "function" then return f end
end

local function GameFrame()
    local f = _G.ColorPickerFrame
    if f and f.SetupColorPickerAndShow then return f end
end

local function Live(e) return e ~= nil and e == edit and not e.done end

-- The picker moved: pass the color on through the setting's normal path.
local function Preview(e, r, g, b)
    if not Live(e) or e.opening or r == nil then return end
    if e.generation ~= Generation() then return end
    local hex = Hex(r, g, b)
    if hex == e.last then return end
    e.last = hex
    e.onPick(hex)
end

-- Cancel (or an edit given up): the starting color goes back, once, unless it never left or the profile changed.
local function Restore(e)
    if not Live(e) then return end
    e.done = true
    edit = nil
    if e.generation == Generation() and e.last ~= e.original then
        e.last = e.original
        e.onPick(e.original)
    end
end

local function OpenEllesmere(e, r, g, b)
    local eui = Ellesmere()
    if not eui then return false end
    e.frame = EllesmereFrame
    e.opening = true
    local ok, err = pcall(eui.ShowColorPicker, eui, {
        r = r, g = g, b = b, hasOpacity = false, opacity = 1,
        swatchFunc = function()
            local f = EllesmereFrame()
            if f then Preview(e, f:GetColorRGB()) end
        end,
        cancelFunc = function() Restore(e) end,
    }, e.owner)
    e.opening = false
    local f = EllesmereFrame()
    if ok and f and f:IsShown() then return true end
    if not ok then R.Fault("settings color picker", err) end
    -- It did not open as asked: end this edit before the game's picker takes over, hiding what is half there
    -- (its own cancel then finds the edit over and does nothing).
    e.done = true
    if f and f:IsShown() and f.Hide then f:Hide() end
    return false
end

local function OpenGame(e, r, g, b)
    local f = GameFrame()
    if not f then return false end
    e.frame = GameFrame
    e.opening = true
    f:SetupColorPickerAndShow({
        swatch = e.owner, r = r, g = g, b = b, hasOpacity = false,
        swatchFunc = function() Preview(e, f:GetColorRGB()) end,
        cancelFunc = function() Restore(e) end,
    })
    e.opening = false
    return true
end

-- Whether any color picker (the game's or EllesmereUI's) is up; Esc then belongs to it.
function ColorPicker.Shown()
    local f = _G.ColorPickerFrame
    if f and f:IsShown() then return true end
    f = EllesmereFrame()
    return f ~= nil and f:IsShown() or false
end

-- Opens a picker on the color hex (AARRGGBB text, or nil for white) for owner, the swatch. onPick(hex) is how
-- each color goes to the setting, live; the color the setting had goes back through it on Cancel. Returns
-- whether a picker opened (or, the first time EllesmereUI is loaded for it, will open next frame).
function ColorPicker.Open(owner, hex, onPick)
    ColorPicker.Cancel()   -- an edit still open is cancelled first, so it is never left half-applied
    local r, g, b = Wg.ParseHex(hex)
    local e = {
        owner = owner, onPick = onPick, generation = Generation(),
        original = type(hex) == "string" and hex or Hex(r, g, b),
    }
    e.last = e.original
    edit = e
    local function Start()
        if OpenEllesmere(e, r, g, b) then return true end
        e.done = false
        if OpenGame(e, r, g, b) then return true end
        if edit == e then edit = nil end
        return false
    end
    if not Ellesmere() and LoadEllesmere() and C_Timer and C_Timer.After then
        -- just loaded: open next frame, unless the edit was given up meanwhile (Cancel clears it)
        C_Timer.After(0, function() if edit == e then Start() end end)
        return true
    end
    return Start()
end

-- Puts away the picker of an edit still open, its color back as it was: for the window closing, another page
-- being shown, a profile change, another swatch being opened. An edit whose picker is already hidden was
-- confirmed or cancelled there, and is left as it is.
function ColorPicker.Cancel()
    local e = edit
    if not e then return end
    local f = e.frame and e.frame()
    if f and f:IsShown() then
        Restore(e)
        f:Hide()
    else
        e.done = true
        edit = nil
    end
end

-- A profile change ends an edit (its callbacks must not write into another profile).
if R.Profiles and R.Profiles.OnChange then
    R.Profiles.OnChange(function() ColorPicker.Cancel() end)
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
    -- turns (a Cancel there puts the old color back through onPick). EllesmereUI's picker does not; the
    -- setting's own refresh redraws the swatch as each color is passed on.
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
        if not active then return end
        ColorPicker.Open(self, value, onPick)
    end)
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

---------------------------------------------------------------------------
-- A scroll frame with Style.lua's slim bar, shown only while there is something to scroll. Returns scroll, content.
---------------------------------------------------------------------------
function Wg.Scroll(parent, contentWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    -- Unless told otherwise the template keeps its bar (arrows, track and a full-length thumb) up while there is
    -- nothing to scroll. Hideable, it shows only when the content is taller than the view (the range is
    -- ScrollFrame_OnScrollRangeChanged's to follow, as Blizzard's own hideable frames do).
    scroll.scrollBarHideable = 1
    if type(ScrollFrame_OnScrollRangeChanged) == "function" then pcall(ScrollFrame_OnScrollRangeChanged, scroll) end
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(contentWidth, 1)
    scroll:SetScrollChild(content)
    Look.ScrollBar(scroll)
    return scroll, content
end
