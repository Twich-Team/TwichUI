-- TwichUI settings: Reminders, the editor's sections (Reminders.lua draws the list and puts these under it)
-- Show (what appears), When (who it is for and its conditions, as cards inside groups, with the rule in plain words), Placement (where, how big, and
-- behind "More placement and appearance options" the rest) and Test (what it sees right now, and the same decision for situations you pick). Each
-- section's widgets are made once, the first time the page is shown, and only placed and filled after that; condition
-- cards, group boxes and test lines come from pools bounded by RM.MAX_CONDITIONS and RM.MAX_GROUPS. Every change goes through
-- Config.lua's functions, which check it; nothing here writes saved data, reads the game's equipment for itself or changes it.
--
--   Ed.Build(parent, env) -> sections    env: { id() (the reminder shown), view(), Say(text, tone), Changed() }
--   section:Layout(view, y) -> height    placed at y on parent; hidden when the reminder isn't there

local R = TwichUI
local Ed = {}
R.RemindersEditor = Ed

local W = 644              -- the settings window's content width
local PAD, ICON = 14, 28
local LABEL_X, CTRL_X = 14, 126
local ROW = 30
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_REQUESTS = 2

local function Wg() return R.SettingsWidgets end
local function RM() return R.Reminders end

function Ed.Thumb(tex, d, size)
    local mode = d.mode
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:SetSize(size, size)
    if (mode == "artwork" or mode == "artworkText") and RM().Art(d.art) then
        local file, l, r, t, b, aspect = RM().ArtTexture(d.art, size)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(size * math.min(1, aspect), size / math.max(1, aspect))
    elseif (mode == "icon" or mode == "iconText") and d.iconSource == "item" then
        local icon = d.item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(d.item)
        tex:SetTexture(icon or QUESTION)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        R.Icons.Apply(tex, (mode == "icon" or mode == "iconText") and d.icon or "reminders", size)
    end
end

local function Choices(list)
    local out = {}
    for i, c in ipairs(list) do out[i] = { value = c[1], label = c[2], tooltip = c[3] } end
    return out
end

local function LabelOf(list, value)
    for _, c in ipairs(list) do if c[1] == value then return c[2] end end
    return tostring(value)
end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- An item's name, and "ok" | "loading" | "missing", asking the game at most twice while this is open.
local requested = {}
function Ed.ItemInfo(id)
    if not id then return nil, "none" end
    local name = C_Item.GetItemNameByID and Plain(C_Item.GetItemNameByID(id))
    if type(name) == "string" and name ~= "" then return name, "ok" end
    if C_Item.GetItemInfoInstant and Plain((C_Item.GetItemInfoInstant(id))) == nil and (requested[id] or 0) >= MAX_REQUESTS then
        return nil, "missing"
    end
    if (requested[id] or 0) < MAX_REQUESTS and C_Item.RequestLoadItemDataByID then
        requested[id] = (requested[id] or 0) + 1
        C_Item.RequestLoadItemDataByID(id)
    end
    return nil, "loading"
end

local function ItemLine(id)
    if not id then return "No item chosen yet.", "warn" end
    local name, state = Ed.ItemInfo(id)
    if state == "ok" then return ("%s (item %d)"):format(name, id), "ok" end
    if state == "missing" then return ("The game has no item %d. Check the number."):format(id), "warn" end
    return ("Item %d: loading its details..."):format(id), nil
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------
local function Section(parent, icon, title)
    local G = Wg()
    local s = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    s:SetWidth(W)
    local M = R.SettingsMaterial
    if M then M.PanelFace(s, "walnut") else G.Panel(s) end
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetSize(ICON, ICON)
    s.icon:SetPoint("TOPLEFT", PAD - 2, -10)
    if not (icon and R.Icons and R.Icons.Apply(s.icon, icon, ICON) ~= "fallback") then s.icon:Hide() end
    s.title = G.Text(s, "heading")
    s.title:SetPoint("TOPLEFT", icon and PAD + ICON + 8 or PAD, -12)
    s.title:SetWidth(230)
    s.title:SetText(title)
    if M then M.ReminderFont(s.title, 17, true, "serif") end
    s:Hide()
    return s
end

-- Space for the heading and its icon.
local function Top() return ICON + 16 end

local function Label(parent, text)
    local fs = Wg().Text(parent, "body")
    fs:SetText(text)
    R.SettingsMaterial.ReminderFont(fs, 14, true)
    fs:SetWidth(CTRL_X - LABEL_X - 8)
    fs:SetWordWrap(false)
    return fs
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

-- A label and its control on one row; returns the next row's y.
local function Line(parent, label, control, y, dy)
    Put(label, parent, LABEL_X, y + 4)
    Put(control, parent, CTRL_X, y)
    return y + (dy or ROW)
end

local function Note(parent, width)
    local fs = Wg().Text(parent, "small")
    fs.noteWidth = width
    fs:SetWidth(width or (W - LABEL_X - PAD))
    fs:SetWordWrap(true)
    return fs
end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or (tone == "quiet" and pal.stone or pal.textDim)))
end

-- Text on a row, placed, its height returned.
local function Text(fs, text, tone, x, y, parent)
    fs:SetText(text or "")
    if parent.editorWidth then
        fs:SetWidth(math.min(fs.noteWidth or W, math.max(80, parent.editorWidth - x - PAD)))
    end
    Tone(fs, tone)
    Put(fs, parent, x, y)
    return fs:GetStringHeight() or 12
end

local function HideAll(list) for _, x in ipairs(list) do x:Hide() end end

local function Dropdown(parent, w, choices, onPick, tipTitle, tip)
    local d = Wg().Dropdown(parent, w, onPick)
    d:SetChoices(choices)
    if tip then R.Interact.Tip(d, tipTitle, tip) end
    if R.SettingsMaterial then R.SettingsMaterial.ReminderControl(d, "dropdown") end
    return d
end

local function Checkbox(parent, label, onToggle, tip)
    local box = Wg().Checkbox(parent, onToggle)
    box.label = Wg().Text(parent, "body")
    box.label:SetText(label)
    box.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    if tip then R.Interact.Tip(box, label, tip) end
    return box
end

local function Slider(parent, key, onSet, width)
    local lim = RM().LIMITS[key]
    local s = Wg().Slider(parent, width or 280, onSet, true)
    s:SetRange(lim[1], lim[2], 1)
    return s
end

---------------------------------------------------------------------------
-- Show: what appears
---------------------------------------------------------------------------
local MODE_H, IMG = 78, 72   -- a display mode's button, and the image tile's side
local MODE_ART_W, MODE_ART_H = 96, 48   -- the picture on a display-mode button (the TGAs are 128 x 64)

-- The picture on a display-mode button: media/reminders/mode-<mode>.tga (assets cut by tools/make_reminder_modes_art.py from
-- the rendered sheet), a framed painting with words beside it, the painting alone, bars of words. It is a texture on the
-- button, so it takes the button's own hover and selection.
local function ModeGlyph(button, ui)
    local t = button:CreateTexture(nil, "OVERLAY")
    t:SetTexture(R.PATH .. [[media\reminders\mode-]] .. ui .. ".tga")
    t:SetSize(MODE_ART_W, MODE_ART_H)
    t:SetPoint("TOP", button, "TOP", 0, -6)
    return t
end

local function ShowSection(parent, env)
    local s = Section(parent, nil, "Appearance")
    local function Set(key, value) local ok, why = RM().SetDisplay(env.id(), key, value) if not ok then env.Say(why, "warn") end end
    local G, M = Wg(), R.SettingsMaterial

    s.subtitle = M.ReminderFont(G.Text(s, "body"), 14)
    s.subtitle:SetText("Customize how this reminder looks when it appears.")
    s.subtitle:SetPoint("TOPLEFT", PAD, -36)
    s.subtitle:SetWidth(W - PAD * 2)

    -- Display: Image + text, Image only, Text only. A view of the five stored modes (reminders/Gallery.lua); only the stored mode changes.
    s.modeLabel = Label(s, "Display")
    s.modes = {}
    for i, m in ipairs(RM().Gallery.UI_MODES) do
        local ui, label, tip = m[1], m[2], m[3]
        local b = M.Segment(s, "", 100, function()
            local ok, why = RM().Gallery.SetUIMode(env.id(), ui)
            if not ok then env.Say(why, "warn") end
        end)
        b:SetHeight(MODE_H)
        b.ui = ui
        b.glyph = ModeGlyph(b, ui)
        b.text = G.Text(b, "body")
        M.ReminderFont(b.text, 14, true)
        b.text:ClearAllPoints()
        b.text:SetPoint("BOTTOM", 0, 8)
        b.text:SetText(label)
        R.Interact.Tip(b, label, tip)
        s.modes[i] = b
    end

    -- Image: what it shows now, and the one button that changes it (the picker is RemindersImagePicker.lua)
    s.imageLabel = M.ReminderFont(G.Text(s, "heading"), 15, true)
    s.imageLabel:SetText("Image")
    s.imageBox = CreateFrame("Frame", nil, s)
    s.imageBox:SetFrameLevel(s:GetFrameLevel() or 0)
    M.PanelFace(s.imageBox, "espresso")
    s.artTile = CreateFrame("Button", nil, s.imageBox)
    M.PanelFace(s.artTile, "canvas")
    s.artTile:SetSize(IMG, IMG)
    s.artTile:SetPoint("LEFT", 10, 0)
    s.artTile.thumb = s.artTile:CreateTexture(nil, "OVERLAY")
    s.artTile.thumb:SetPoint("CENTER", 0, 0)
    G.Hover(s.artTile, G.pal.bronzeText, 0.12)
    local function OpenPicker() R.RemindersImagePicker.Open(env.id(), env) end
    s.artTile:SetScript("OnClick", OpenPicker)
    R.Interact.Tip(s.artTile, "Choose image", "Choose the picture or icon this reminder shows.")
    s.imageName = M.ReminderFont(G.Text(s.imageBox, "heading"), 16, true)
    s.imageName:SetPoint("TOPLEFT", IMG + 26, -14)
    s.imageName:SetMaxLines(1)
    s.imageSource = M.ReminderFont(G.Text(s.imageBox, "body"), 13)
    s.imageSource:SetPoint("TOPLEFT", s.imageName, "BOTTOMLEFT", 0, -3)
    s.imageSource:SetMaxLines(1)
    s.choose = G.Button(s.imageBox, "Choose image...", 150, "secondary", OpenPicker)
    s.choose:SetHeight(28)
    M.ReminderControl(s.choose, "secondary")
    s.choose:SetPoint("BOTTOMRIGHT", -12, 12)
    R.Interact.Tip(s.choose, "Choose image", "Opens the picture list: TwichUI's artwork by kind, or the icon of any item. Nothing changes until you press Apply.")

    s.textLabel = Label(s, "Text")
    s.textBox = G.EditBox(s, 280, 22)
    s.textBox:SetMaxLetters(RM().TEXT_MAX * 4)
    local function SaveText(self)
        local ok, why = RM().SetDisplay(env.id(), "text", self:GetText())
        if not ok then env.Say(why, "warn") end
    end
    s.textBox:SetScript("OnEnterPressed", function(self) SaveText(self); self:ClearFocus() end)
    s.textBox:HookScript("OnEditFocusLost", SaveText)
    R.Interact.Tip(s.textBox, "Words", ("Plain text, up to %d characters. Shown as you type it: nothing in it is read as a command or a code."):format(RM().TEXT_MAX))
    s.sizeLabel = Label(s, "Size")
    s.size = Slider(s, "size", function(v) Set("size", math.floor(v + 0.5)) end, 154)
    s.colorLabel = Label(s, "Color")
    s.colorLabel:SetWidth(42)
    s.color = G.Swatch(s, function(hex) Set("textColor", hex) end)
    s.textOptions = CreateFrame("Frame", nil, s)
    s.textOptions:SetFrameLevel(s:GetFrameLevel() or 0)
    M.PanelFace(s.textOptions, "espresso")
    s.parts = { s.subtitle, s.modeLabel, s.imageLabel, s.imageBox, s.artTile, s.imageName, s.imageSource, s.choose,
        s.textLabel, s.textBox, s.sizeLabel, s.size, s.colorLabel, s.color, s.textOptions }
    for _, b in ipairs(s.modes) do s.parts[#s.parts + 1] = b end

    function s:Layout(v, y)
        HideAll(self.parts)
        local d = v.display
        local width = self:GetWidth()
        local Gal = RM().Gallery
        local ui = Gal.UIMode(d.mode)
        local h = 64
        self.subtitle:SetWidth(width - PAD * 2)
        self.subtitle:Show()

        -- the three modes, side by side beside their label
        local x0 = 88
        local bw = math.floor((width - x0 - PAD - 2 * 8) / 3)
        Put(self.modeLabel, self, LABEL_X, h + MODE_H / 2 - 9)
        for i, b in ipairs(self.modes) do
            b:SetWidth(bw)
            b:SetSelected(b.ui == ui)
            Put(b, self, x0 + (i - 1) * (bw + 8), h)
        end
        h = h + MODE_H + 14

        local visual = ui ~= "text"
        local words = ui ~= "image"
        if visual then
            Put(self.imageLabel, self, PAD, h)
            h = h + 24
            self.imageBox:SetSize(width - PAD * 2, IMG + 22)
            Put(self.imageBox, self, PAD, h)
            Ed.Thumb(self.artTile.thumb, d, IMG - 10)
            local _, _, name, from = Gal.Current(d)
            self.imageName:SetWidth(width - PAD * 2 - IMG - 40)
            self.imageSource:SetWidth(width - PAD * 2 - IMG - 40)
            self.imageName:SetText(name)
            self.imageSource:SetText(from)
            self.imageName:Show(); self.imageSource:Show(); self.choose:Show(); self.artTile:Show()
            h = h + IMG + 22 + 12
        end
        if words then
            if not self.textBox:HasFocus() then self.textBox:SetText(d.text) end
            self.textBox:SetSize(width - 72 - PAD, 28)
            Put(self.textLabel, self, LABEL_X, h + 6)
            Put(self.textBox, self, 72, h)
            h = h + 38
        end
        local size = visual and d.keepAspect
        if words or size then
            self.textOptions:SetSize(width - PAD * 2, 36)
            Put(self.textOptions, self, PAD, h)
            if words then
                self.color:SetValue(d.textColor)
                self.colorLabel:SetText("Text color")
                self.colorLabel:SetWidth(70)
                Put(self.colorLabel, self, LABEL_X + 8, h + 9)
                Put(self.color, self, 92, h + 6)
            end
            if size then
                local lx = words and 146 or LABEL_X + 8
                local sx = words and 188 or 64
                self.sizeLabel:SetText("Size")
                self.size:SetWidth(math.max(130, width - sx - PAD - 4))
                self.size:SetValue(d.size)
                Put(self.sizeLabel, self, lx, h + 9)
                Put(self.size, self, sx, h + 6)
            end
            h = h + 36
        end
        h = h + 12
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- When: who it is for, and its conditions. The designer (RemindersDesigner.lua) draws and edits it, in the words of
-- RemindersPlain.lua; it borrows this file's pieces (Ed.Kit) so it looks like the sections around it.
---------------------------------------------------------------------------
Ed.Kit = {
    W = W, PAD = PAD, ICON = ICON, LABEL_X = LABEL_X, CTRL_X = CTRL_X, ROW = ROW,
    Section = Section, Top = Top, Put = Put, Text = Text, Tone = Tone, ItemLine = ItemLine,
}

local function WhenSection(parent, env)
    return R.RemindersDesigner.Build(parent, env)
end

---------------------------------------------------------------------------
-- Placement: where, how big; the rest behind one disclosure
---------------------------------------------------------------------------
local function PlacementSection(parent, env)
    local s = Section(parent, "reminderPlacement", "Advanced")
    s.toggle = Wg().Button(s, "Placement and effects", 220, "secondary", function()
        Ed.placementOpen = not Ed.placementOpen; env.Changed()
    end)
    R.SettingsMaterial.Disclosure(s.toggle)
    s.title:Hide(); s.icon:Hide()
    local function Set(key, value) local ok, why = RM().SetDisplay(env.id(), key, value) if not ok then env.Say(why, "warn") end end
    local function Whole(fn) return function(v) fn(math.floor(v + 0.5)) end end
    local D = R.ReminderDisplay

    s.presetLabel = Label(s, "Position")
    s.preset = Dropdown(s, 220, function()
        local out = {}
        for i, p in ipairs(RM().PRESETS) do out[i] = { value = p[1], label = p[2], tooltip = p[6] } end
        return out
    end, function(v)
        local ok, why = RM().SetPreset(env.id(), v)
        if not ok then env.Say(why, "warn") end
    end, "Position", "A place on the screen, or where you moved it. Below the middle sits under your character, clear of it.")
    s.move = Wg().Button(s, "Place on screen", 150, "secondary", function()
        local v = env.view()
        if not v then return end
        if D.Positioning() and D.PreviewId() == v.id then D.PositionEnd() env.Changed() return end
        local ok = R.RemindersPlacement.Start(v)
        if not ok then env.Say("It can be moved when you are out of combat.", "warn") end
        env.Changed()
    end)
    R.Interact.Tip(s.move, "Place on screen", "Hides settings while you drag the reminder. Finish saves its position; Cancel keeps its old position. Settings returns afterward. Combat cancels placement.")
    s.opacityLabel = Label(s, "Opacity")
    s.opacity = Slider(s, "opacity", Whole(function(v) Set("opacity", v) end))
    s.textSizeLabel = Label(s, "Text size")
    s.textSize = Slider(s, "textSize", Whole(function(v) Set("textSize", v) end))
    s.placeLabel = Label(s, "Words go")
    s.textPlace = Dropdown(s, 220, function() return Choices(RM().CHOICES.textPlace) end, function(v) Set("textPlace", v) end)

    -- the rest, closed until asked for (kept for the session only)
    s.more = CreateFrame("Button", nil, s)
    s.more:SetSize(320, 22)
    s.more.text = Wg().Text(s.more, "small")
    s.more.text:SetPoint("LEFT", 16, 0)
    Wg().Color(s.more.text, Wg().pal.tealHi)
    s.more.down = Wg().Chevron(s.more, s.more, "LEFT", 7, 0, true, Wg().pal.tealHi)
    s.more.up = Wg().Chevron(s.more, s.more, "LEFT", 7, 0, false, Wg().pal.tealHi)
    s.more:SetScript("OnClick", function() Ed.moreOpen = not Ed.moreOpen; env.Changed() end)

    s.keep = Checkbox(s, "Keep its proportions", function(on) Set("keepAspect", on and true or false) end,
        "On: one size, and the picture keeps its own shape. Off: a width and a height of their own (the picture is stretched to them).")
    s.widthLabel = Label(s, "Width")
    s.width = Slider(s, "width", Whole(function(v) Set("width", v) end))
    s.heightLabel = Label(s, "Height")
    s.height = Slider(s, "height", Whole(function(v) Set("height", v) end))
    s.fontLabel = Label(s, "Font")
    s.font = Dropdown(s, 220, function()
        local v = env.view()
        local out = {}
        for i, c in ipairs(R.MenuStyle.Fonts.Choices(v and v.display.font or "default", { { "default", "Game font (default)" } })) do
            out[i] = { value = c[1], label = c[2],
                font = R.MenuStyle.Fonts.Resolve(c[1], STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]) }
        end
        return out
    end, function(v) Set("font", v) end, "Font", "Fonts come from LibSharedMedia, so TwichUI's, EllesmereUI's and any other addon's are listed. A font that has gone is drawn with the game's own and stays chosen.")
    s.font.menuWidth, s.font.menuAlignRight = 320, true
    s.outlineLabel = Label(s, "Outline")
    s.outline = Dropdown(s, 220, function() return Choices(RM().CHOICES.outline) end, function(v) Set("outline", v) end)
    s.panelLabel = Label(s, "Background")
    s.panel = Dropdown(s, 220, function() return Choices(RM().CHOICES.panel) end, function(v) Set("panel", v) end)
    s.pointLabel = Label(s, "Anchored to")
    s.point = Dropdown(s, 220, function() return Choices(RM().POINTS) end, function(v)
        local view = env.view()
        if view then
            local ok, why = RM().SetPosition(env.id(), v, view.place.x, view.place.y)
            if not ok then env.Say(why, "warn") end
        end
    end, "Anchored to", "The point of the screen its offsets are measured from, and the point of the reminder that sits there.")
    s.offsetLabel = Label(s, "Offset (x, y)")
    local function Offset(axis)
        local box = Wg().EditBox(s, 70, 22)
        box:SetMaxLetters(6)
        box:SetScript("OnEnterPressed", function(self)
            local view = env.view()
            local n = tonumber(self:GetText())
            self:ClearFocus()
            if not (view and n) then return end
            local x, y = view.place.x, view.place.y
            if axis == "x" then x = n else y = n end
            local ok, why = RM().SetPosition(env.id(), view.place.point, x, y)
            if not ok then env.Say(("Offsets can be up to %d either way."):format(RM().POSITION_LIMIT), "warn") end
            env.Changed()
        end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); env.Changed() end)
        return box
    end
    s.x = Offset("x")
    s.y = Offset("y")
    R.Interact.Tip(s.x, "Horizontal offset", "Screen units from the anchor point: more is further right. Press Enter.")
    R.Interact.Tip(s.y, "Vertical offset", "Screen units from the anchor point: more is higher. Press Enter.")
    s.strataLabel = Label(s, "Layer")
    s.strata = Dropdown(s, 220, function() return Choices(RM().CHOICES.strata) end, function(v) Set("strata", v) end,
        "Layer", "Whether it is drawn under or over the game's windows. Medium suits most setups.")
    s.fade = Checkbox(s, "Fade in and out", function(on) Set("fade", on and true or false) end,
        "A quarter-second fade as it appears and goes. Off: it simply appears and goes. Off while Notifications' Reduced motion is on.")
    s.pulse = Checkbox(s, "Pulse gently when it appears", function(on) Set("pulse", on and true or false) end,
        "Three slow breaths of its opacity when it appears, then still. Off while Notifications' Reduced motion is on.")
    s.delayLabel = Label(s, "Show after")
    s.delay = Slider(s, "delay", Whole(function(v) Set("delay", v) end))
    s.minLabel = Label(s, "Keep for")
    s.min = Slider(s, "minShow", Whole(function(v) Set("minShow", v) end))
    s.timing = Note(s)
    s.motion = Note(s)

    s.parts = { s.presetLabel, s.preset, s.opacityLabel, s.opacity, s.textSizeLabel, s.textSize,
        s.placeLabel, s.textPlace, s.more, s.keep, s.keep.label, s.widthLabel, s.width, s.heightLabel, s.height, s.fontLabel, s.font,
        s.outlineLabel, s.outline, s.panelLabel, s.panel, s.pointLabel, s.point, s.offsetLabel, s.x, s.y,
        s.strataLabel, s.strata, s.fade, s.fade.label, s.pulse, s.pulse.label, s.delayLabel, s.delay, s.minLabel, s.min, s.timing, s.motion }

    function s:Layout(v, y)
        HideAll(self.parts)
        local d, p = v.display, v.place
        local m = d.mode
        local visual = m ~= "text"
        local words = m == "text" or m == "artworkText" or m == "iconText"
        local h = 8
        self.toggle.text:SetText("Advanced")
        self.toggle:SetExpanded(Ed.placementOpen)
        Put(self.toggle, self, PAD, h)
        Put(self.diagnostics, self, self:GetWidth() - self.diagnostics:GetWidth() - PAD, h)
        h = h + 32
        if not Ed.placementOpen then
            self:SetHeight(h); Put(self, parent, 0, y); return h
        end
        -- Each visible control owns a full row. Position belongs with the secondary
        -- placement controls, rather than sharing Opacity's first-row anchor.
        local controlWidth = math.min(280, self:GetWidth() - CTRL_X - PAD)
        for _, control in ipairs({ self.opacity, self.textSize, self.width, self.height, self.delay, self.min }) do
            control:SetWidth(controlWidth)
        end
        for _, control in ipairs({ self.textPlace, self.preset, self.font, self.outline, self.panel, self.point, self.strata }) do
            control:SetWidth(math.min(220, controlWidth))
        end
        local rowHeight = 32
        h = h + 8
        self.opacity:SetValue(d.opacity)
        h = Line(self, self.opacityLabel, self.opacity, h, rowHeight)
        if words then
            self.textSize:SetValue(d.textSize)
            h = Line(self, self.textSizeLabel, self.textSize, h, rowHeight)
        end
        if visual and words then
            self.textPlace:SetValue(d.textPlace, LabelOf(RM().CHOICES.textPlace, d.textPlace))
            h = Line(self, self.placeLabel, self.textPlace, h, rowHeight)
        end

        local open = Ed.moreOpen and true or false
        for _, t in ipairs(self.more.down) do t:SetShown(not open) end
        for _, t in ipairs(self.more.up) do t:SetShown(open) end
        self.more.text:SetText(open and "Fewer options" or "More placement and appearance options")
        self.more:SetWidth(math.min(320, self:GetWidth() - LABEL_X - PAD))
        Put(self.more, self, LABEL_X - 4, h + 8)
        h = h + 38
        if open then
            if visual then
                self.keep:SetChecked(d.keepAspect)
                Put(self.keep, self, CTRL_X, h + 2)
                self.keep.label:Show()
                h = h + rowHeight
                if not d.keepAspect then
                    self.width:SetValue(d.width)
                    h = Line(self, self.widthLabel, self.width, h, rowHeight)
                    self.height:SetValue(d.height)
                    h = Line(self, self.heightLabel, self.height, h, rowHeight)
                end
            end
            if words then
                local fontLabel = d.font == "default" and "Game font (default)" or d.font
                self.font:SetValue(d.font, fontLabel)
                h = Line(self, self.fontLabel, self.font, h, rowHeight)
                self.outline:SetValue(d.outline, LabelOf(RM().CHOICES.outline, d.outline))
                h = Line(self, self.outlineLabel, self.outline, h, rowHeight)
            end
            self.panel:SetValue(d.panel, LabelOf(RM().CHOICES.panel, d.panel))
            h = Line(self, self.panelLabel, self.panel, h, rowHeight)
            local presetLabel
            for _, pr in ipairs(RM().PRESETS) do if pr[1] == p.preset then presetLabel = pr[2] end end
            self.preset:SetValue(p.preset, presetLabel)
            h = Line(self, self.presetLabel, self.preset, h, rowHeight)
            self.point:SetValue(p.point, LabelOf(RM().POINTS, p.point))
            h = Line(self, self.pointLabel, self.point, h, rowHeight)
            Put(self.offsetLabel, self, LABEL_X, h + 4)
            if not self.x:HasFocus() then self.x:SetText(tostring(p.x)) end
            if not self.y:HasFocus() then self.y:SetText(tostring(p.y)) end
            Put(self.x, self, CTRL_X, h)
            Put(self.y, self, CTRL_X + 80, h)
            h = h + rowHeight
            self.strata:SetValue(d.strata, LabelOf(RM().CHOICES.strata, d.strata))
            h = Line(self, self.strataLabel, self.strata, h, rowHeight)
            self.fade:SetChecked(d.fade)
            Put(self.fade, self, CTRL_X, h + 2); self.fade.label:Show()
            h = h + rowHeight
            self.pulse:SetChecked(d.pulse)
            Put(self.pulse, self, CTRL_X, h + 2); self.pulse.label:Show()
            h = h + rowHeight
            if R:Enabled("arrivalReducedMotion") then
                h = h + Text(self.motion, "Reduced motion is on (Notifications), so it neither fades nor pulses.", "quiet", CTRL_X, h, self) + 6
            end
            self.delay:SetValue(d.delay)
            h = Line(self, self.delayLabel, self.delay, h, rowHeight)
            self.min:SetValue(d.minShow)
            h = Line(self, self.minLabel, self.min, h, rowHeight)
            h = h + Text(self.timing, ("In seconds. Waiting %d: its conditions must stay true that long before it shows; if they stop first, nothing shows. Keeping it up %d: once shown it stays at least that long, unless you turn it off, delete it, or it stops applying to this character."):format(d.delay, d.minShow), "quiet", LABEL_X, h, self) + 6
        end
        h = h + 12
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- Sound: an optional sound when the reminder appears
---------------------------------------------------------------------------
local SOUND_WHY = {
    none = "No sound is chosen.",
    missing = "That sound isn't available right now (the addon that adds it may be off), so nothing played.",
    refused = "The game refused to play that sound.",
}

local function SoundSection(parent, env)
    local s = Section(parent, nil, "Sound")
    s.pick = Dropdown(s, 200, function()
        local v = env.view()
        local list = { { value = "", label = "None" } }
        for _, c in ipairs(R:SoundChoices(v and v.sound or nil)) do list[#list + 1] = { value = c[1], label = c[2] } end
        return list
    end, function(value)
        local ok, why = RM().SetSound(env.id(), value ~= "" and value or nil)
        if not ok then env.Say(why, "warn") end
    end, "Sound", "TwichUI's own sounds, then every sound LibSharedMedia lists. A sound that has gone stays chosen and plays nothing until it is back.")
    s.play = Wg().Button(s, "Play", 70, "secondary", function()
        local v = env.view()
        if not v then return end
        local ok, why = R.ReminderController.PlaySound(v.sound)
        if not ok then env.Say(SOUND_WHY[why] or SOUND_WHY.refused, "warn") end
    end)
    R.Interact.Tip(s.play, "Play", "Plays the chosen sound once. It follows the game's sound-effects volume: if that is muted or at zero, you will hear nothing.")
    s.note = Note(s)
    s.parts = { s.pick, s.play, s.note }

    function s:Layout(v, y)
        HideAll(self.parts)
        local h = 10
        local label = "None"
        if v.sound then
            label = v.sound
            if not R:ResolveSound(v.sound) then label = v.sound .. " (not available)" end
        end
        self.pick:SetValue(v.sound or "", label)
        local pickWidth = math.min(200, self:GetWidth() - CTRL_X - PAD - 82)
        self.pick:SetWidth(pickWidth)
        Put(self.pick, self, CTRL_X, h)
        Put(self.play, self, CTRL_X + pickWidth + 12, h)
        h = h + 31
        local words
        if v.sound and not R:ResolveSound(v.sound) then
            words = "That sound isn't available right now."
            h = h + Text(self.note, words, "warn", LABEL_X, h, self) + 4
        end
        self.play:SetEnabled(v.sound ~= nil)
        h = h + 8
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

---------------------------------------------------------------------------
-- Test: what it sees right now, and the same decision for situations you pick
---------------------------------------------------------------------------
local function ResultTone(result)
    if result == "match" then return "ok" end
    if result == "invalid" then return "warn" end
    if result == "unknown" then return "quiet" end
    return nil
end

local function StatusTone(status)
    if status == "showing" or status == "holding" then return "ok" end
    if status == "invalid" then return "warn" end
    return "quiet"
end

local function ConditionLine(c, observedWord)
    local E = R.ReminderEval
    local text
    if c.group then
        text = ("%s  -  %s"):format(c.summary, E.RESULT_WORDS[c.result] or c.result)
    else
        text = ("%s  -  %s  -  %s: %s"):format(c.summary, E.RESULT_WORDS[c.result] or c.result, observedWord, c.observed ~= "" and c.observed or "nothing")
    end
    if c.reason then text = text .. ". " .. c.reason end
    return text
end

-- A line for each condition and group of a decision, a group before what is in it and what is in it a step in.
local function ResultRow(parent)
    local G, M = Wg(), R.SettingsMaterial
    local row = CreateFrame("Frame", nil, parent)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(25, 25); row.icon:SetPoint("TOPLEFT", 0, -2)
    row.title = M.ReminderFont(G.Text(row, "body"), 14, true)
    row.state = M.ReminderFont(G.Text(row, "body"), 13, true)
    row.observation = M.ReminderFont(G.Text(row, "small"), 12)
    row.state:SetPoint("TOPRIGHT", 0, -3); row.state:SetWidth(92); row.state:SetJustifyH("RIGHT")
    row.line = G.Solid(row, "BORDER", G.pal.bronzeLo, .32)
    row.line:SetHeight(1); row.line:SetPoint("BOTTOMLEFT"); row.line:SetPoint("BOTTOMRIGHT")
    return row
end

local function NodeLines(self, pool, out, observedWord, h)
    local Pl = R.RemindersPlain
    for i, c in ipairs(out and out.nodes or {}) do
        local row = pool[i]
        if not row then break end
        local x = PAD + 12 * math.min(4, (c.depth or 1) - 1)
        local w = (self.editorWidth or self:GetWidth()) - x - PAD
        row:SetWidth(w)
        local title = c.group and (c.match == "any" and "Any of these" or "All of these") or Pl.Sentence(c.entry)
        row.title:SetText(title)
        row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", c.group and 0 or 34, -2)
        row.title:SetWidth(math.max(60, w - (c.group and 0 or 34) - 98))
        row.state:SetText(({ match = "Met", nomatch = "Not met", unknown = "Unknown", invalid = "Needs attention" })[c.result] or "Unknown")
        Wg().Color(row.state, c.result == "match" and Wg().pal.sage
            or c.result == "nomatch" and Wg().pal.danger.text
            or c.result == "invalid" and Wg().pal.bronzeText or Wg().pal.textDim)
        Wg().Color(row.title, c.group and Wg().pal.textDim or Wg().pal.text)
        row.icon:SetShown(not c.group)
        row.observation:SetShown(not c.group)
        local titleH = row.title:GetStringHeight() or 14
        if not c.group then
            Pl.ApplyArt(row.icon, c.entry and c.entry.cond, 25)
            row.observation:ClearAllPoints(); row.observation:SetPoint("TOPLEFT", 34, -titleH - 6)
            row.observation:SetWidth(w - 34)
            row.observation:SetText(observedWord .. ": " .. ((c.observed and c.observed ~= "") and c.observed or "Not available"))
            Wg().Color(row.observation, Wg().pal.textDim)
        end
        local rh = titleH + (c.group and 10 or (row.observation:GetStringHeight() or 12) + 17)
        row:SetHeight(rh); Put(row, self, x, h)
        h = h + rh + 6
    end
    return h
end

Ed.ResultRow, Ed.DrawResults = ResultRow, NodeLines

local function TestSection(parent, env)
    local s = Section(parent, "reminderTest", "Diagnostics")
    s.toggle = Wg().Button(s, "Diagnostics", 126, "secondary", function()
        Ed.testOpen = not Ed.testOpen; env.Changed()
    end)
    local NODES = RM().MAX_CONDITIONS + RM().MAX_GROUPS
    s.liveHead = Wg().Text(s, "body")
    s.liveHead:SetText("Current visibility")
    R.SettingsMaterial.ReminderFont(s.liveHead, 17, true)
    s.eye = s:CreateTexture(nil, "ARTWORK")
    s.eye:SetSize(22, 22)
    s.conditionHead = R.SettingsMaterial.ReminderFont(Wg().Text(s, "body"), 14, true)
    s.conditionHead:SetText("Condition results · live observations")
    s.liveResult = Note(s)
    s.live = {}
    s.simHead = Wg().Text(s, "body")
    s.simHead:SetText("Try a situation")
    s.simTag = Wg().Tag(s, "SIMULATED")
    s.simIntro = Note(s)
    s.picks, s.pickLabels, s.sim = {}, {}, {}
    for i = 1, NODES do
        s.live[i] = ResultRow(s)
        s.sim[i] = ResultRow(s)
    end
    for i = 1, RM().MAX_CONDITIONS do
        s.pickLabels[i] = Note(s, 300)
        s.pickLabels[i]:SetWordWrap(false)
        s.picks[i] = Dropdown(s, 240, function()
            local v = env.view()
            local input = v and R.ReminderEval.SimInputs(v)[i]
            local out = {}
            for j, sc in ipairs(input and input.scenarios or {}) do out[j] = { value = sc.key, label = sc.label } end
            return out
        end, function(value)
            local id = env.id()
            Ed.picks = Ed.picks or {}
            Ed.picks[id] = Ed.picks[id] or {}
            Ed.picks[id][i] = value
            env.Changed()
        end)
    end
    s.simResult = Note(s)
    s.technical = Note(s)
    s.details = Wg().Button(s, "› Technical details", 160, "secondary", function()
        Ed.technicalOpen = not Ed.technicalOpen; env.Changed()
    end)
    R.SettingsMaterial.Disclosure(s.details)
    R.SettingsMaterial.ReminderControl(s.details, "secondary")
    s.try = Wg().Button(s, "› Try a situation", 160, "secondary", function()
        Ed.situationOpen = not Ed.situationOpen; env.Changed()
    end)
    R.SettingsMaterial.Disclosure(s.try)
    R.SettingsMaterial.ReminderControl(s.try, "secondary")
    local parts = { s.liveHead, s.liveResult, s.simHead, s.simTag, s.simIntro, s.simResult, s.conditionHead, s.eye, s.details, s.technical, s.try }
    for i = 1, NODES do parts[#parts + 1] = s.live[i]; parts[#parts + 1] = s.sim[i] end
    for i = 1, RM().MAX_CONDITIONS do parts[#parts + 1] = s.picks[i]; parts[#parts + 1] = s.pickLabels[i] end

    function s:Layout(v, y)
        HideAll(parts)
        local E, CT = R.ReminderEval, R.ReminderController
        local h = Top(self)
        self.toggle.text:SetText(Ed.testOpen and "Hide diagnostics" or "Diagnostics")
        if not Ed.testOpen then
            self:Hide()
            return 0
        end
        local out, status = CT.Inspect(v.id)
        local label, state, reason, visible = R.RemindersPlain.LiveFeedback(v)
        self.liveHead:SetText(label)
        Put(self.eye, self, PAD, h - 2)
        self.eye:SetTexture(R.PATH .. [[media\guildloc\]] .. (visible and "eye-open-small.tga" or "eye-hidden-small.tga"))
        local tint = visible and Wg().pal.sage or state == "unmet" and Wg().pal.danger.text
            or state == "invalid" and Wg().pal.bronzeText or Wg().pal.textDim
        Wg().Color(self.liveHead, tint)
        self.eye:SetVertexColor(tint[1], tint[2], tint[3], 1)
        Put(self.liveHead, self, PAD + 30, h)
        h = h + 24
        h = h + Text(self.liveResult, reason or "No observation available.", nil, PAD + 30, h, self) + 16
        Put(self.conditionHead, self, PAD, h); h = h + 25
        h = NodeLines(self, self.live, out, "Observed", h)
        self.details.text:SetText("Technical details")
        self.details:SetExpanded(Ed.technicalOpen)
        Put(self.details, self, PAD, h); h = h + 34
        if Ed.technicalOpen then
            local details = { "Live evaluation · " .. tostring(status) }
            for _, c in ipairs(out and out.nodes or {}) do details[#details + 1] = ConditionLine(c, "Observed") end
            if out then details[#details + 1] = out.reason or out.explain or "" end
            h = h + Text(self.technical, table.concat(details, "\n"), "quiet", PAD, h, self) + 12
        end
        self.try.text:SetText("Try a situation")
        self.try:SetExpanded(Ed.situationOpen)
        Put(self.try, self, PAD, h); h = h + 34
        if Ed.situationOpen then
        self.simHead:SetText("Sample inputs")
        Put(self.simHead, self, PAD, h)
        Put(self.simTag, self, PAD + 110, h)
        h = h + 23
        if #v.conditions == 0 then
            h = h + Text(self.simIntro, "Add a condition first; then you can try situations here.", "quiet", PAD, h, self) + 8
        else
            h = h + Text(self.simIntro, "Choose sample values to see how the rule would respond.", "quiet", PAD, h, self) + 8
            local picks = Ed.picks and Ed.picks[v.id] or {}
            for i, input in ipairs(E.SimInputs(v)) do
                if not self.picks[i] then break end
                local list = input.scenarios
                local chosen = list[1]
                for _, sc in ipairs(list) do if sc.key == picks[i] then chosen = sc end end
                local label = #input.leaves > 1 and ("%s (%d conditions)"):format(input.label or "Shared", #input.leaves) or E.Summary(input.entry)
                Text(self.pickLabels[i], ("%d. %s"):format(i, label), nil, PAD + 10, h + 4, self)
                if chosen then
                    self.picks[i]:SetValue(chosen.key, chosen.label)
                    Put(self.picks[i], self, PAD + 10, h + 22)
                end
                h = h + ROW + 26
            end
            local sim = E.Simulate(v, picks)
            h = NodeLines(self, self.sim, sim, "Simulated", h)
            local simWords = E.STATUS_WORDS[sim.status] or sim.status
            h = h + 2 + Text(self.simResult, ("Simulated result: %s. %s"):format(simWords, sim.reason or sim.explain), StatusTone(sim.status), PAD, h + 2, self) + 12
        end

        end -- simulated inputs disclosure
        self:SetHeight(h)
        Put(self, parent, 0, y)
        return h
    end
    return s
end

function Ed.Build(parent, env)
    Ed.sections = {
        ShowSection(parent, env),
        WhenSection(parent, env),
        PlacementSection(parent, env),
        SoundSection(parent, env),
        TestSection(parent, env),
    }
    local placement, test = Ed.sections[3], Ed.sections[5]
    placement.diagnostics = test.toggle
    test.toggle:SetParent(placement)
    for _, section in ipairs(Ed.sections) do
        for _, key in ipairs({ "itemBox", "textBox", "x", "y" }) do
            if section[key] and R.SettingsMaterial then R.SettingsMaterial.ReminderControl(section[key], "field") end
        end
        for _, key in ipairs({ "move", "play", "toggle" }) do
            if section[key] and R.SettingsMaterial then R.SettingsMaterial.ReminderControl(section[key]) end
        end
    end
    return Ed.sections
end

function Ed.FitWidth(width)
    W = width
    for i, section in ipairs(Ed.sections or {}) do
        if i ~= 2 then
            section:SetWidth(W)
            section.editorWidth = W
        end

    end
end

-- Navigation only: use a single reusable gold outline, with a stale-timer guard. Never focus an edit box
-- (focus loss could otherwise save an unrelated edit), evaluate a condition or call a Config setter.
function Ed.Reveal(part)
    local sections = Ed.sections
    if not sections then return end
    local show = sections[1]
    local target = part == "text" and show.textBox or show.choose
    if part == "test" then
        Ed.testOpen = true
        if R.RemindersPage then R.RemindersPage.Refresh() end
        target = sections[5]
    elseif part == "size" then
        target = show.size
    end
    if not target or not target:IsShown() then target = show end
    Ed.revealToken = (Ed.revealToken or 0) + 1
    local token = Ed.revealToken
    if Ed.highlight then Ed.highlight:Hide() end
    if not Ed.highlight then
        Ed.highlight = CreateFrame("Frame", nil, show, "BackdropTemplate")
        local fill = R.SettingsCraft.Sheet(Ed.highlight, "selection-hot", { layer = "BACKGROUND", corner = 8 })
        fill:SetAlpha(0.30)
        R.SettingsCraft.Sheet(Ed.highlight, "hover-rim", { layer = "OVERLAY", corner = 8 })
        Ed.highlight:EnableMouse(false)
    end
    Ed.highlight:SetParent(target)
    Ed.highlight:SetFrameLevel((target:GetFrameLevel() or 0) + 1)
    Ed.highlight:ClearAllPoints()
    Ed.highlight:SetPoint("TOPLEFT", target, "TOPLEFT", -3, 3)
    Ed.highlight:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 3, -3)
    Ed.highlight:Show()
    Ed.revealed = target
    if R.SettingsUI and R.SettingsUI.RevealFrame then R.SettingsUI.RevealFrame(target) end
    C_Timer.After(1.8, function() if token == Ed.revealToken then Ed.highlight:Hide() end end)
end

function Ed.ClearReveal()
    Ed.revealToken = (Ed.revealToken or 0) + 1
    Ed.revealed = nil
    if Ed.highlight then Ed.highlight:Hide() end
end
