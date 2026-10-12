-- TwichUI: Party pins, the pin editor
-- A small window for a new pin's name, color and kind (local or party), and for renaming or recoloring
-- one you can change. A "Keep this pin" box protects it from deletion, clearing and moving (pins/Pins.lua
-- enforces that; the box is only where it is chosen). The same window, filled in, is "Save to my pins" for
-- a party pin someone else made: a local pin of your own, kept by default, made only when you press Save.
-- Nothing is made, changed or sent until Save; Cancel, Esc or closing it leaves
-- everything as it was. Save checks again at that moment (still in a party, still your pin, still under
-- the limits) and says why when it can't, keeping what you typed.
-- Drawn with TwichUI's own look (pins/Look.lua): its background and border are the player's own choice
-- (PL.EditorLook, Party pins options > New pin window appearance, with a Preview), its text follows the
-- pin window's font, size and accent. It doesn't need EllesmereUI.

local R = TwichUI
local PN = R.Pins
local PL = R.PinsLook
local S = R.ChronicleStyle
local PE = {}
R.PinsEditor = PE

local NAME = "TwichUIPinEditor"
local WIDTH, HEIGHT = 300, 242
local PAD = 14
local SWATCH, SWATCH_ON = 22, 24
local pal = PL.palette
local f       -- the window: it carries the player's background and border, and the fields below
local body    -- WIDTH x HEIGHT inside it, clear of the border; everything is drawn on this
local state   -- { mode = "new" | "edit" | "preview", map, x, y, party, entry, color, kept, copy, copiedFrom }

local function Swatch(parent, i, color)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SWATCH, SWATCH)
    -- anchored by its center so the selected swatch can grow in place (SetScale would shift its anchor offset)
    b:SetPoint("CENTER", parent, "TOPLEFT", (i - 1) * 28 + SWATCH / 2, -SWATCH / 2)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    local c = color[3]
    b:SetBackdropColor(c[1], c[2], c[3], 1)
    b.id = color[1]
    b:SetScript("OnClick", function(self)
        state.color = self.id
        PE.Paint()
    end)
    R.Interact.Tip(b, nil, color[2])
    return b
end

-- A small bronze check box with its label, drawn in the editor's palette (no game template to restyle).
local function CheckBox(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(WIDTH - PAD * 2, 20)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(14, 14)
    b.box:SetPoint("LEFT", 0, 0)
    b.box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b.mark = b.box:CreateTexture(nil, "OVERLAY")
    b.mark:SetSize(8, 8)
    b.mark:SetPoint("CENTER")
    b.text = PL.Text(b, "GameFontNormalSmall", "name")
    b.text:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.text:SetText(label)
    local on, over = false, false
    local function Paint_()
        local edge = (on or over) and pal.gold or pal.bronzeLo
        b.box:SetBackdropColor(pal.well[1], pal.well[2], pal.well[3], 1)
        b.box:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        b.mark:SetColorTexture(pal.gold[1], pal.gold[2], pal.gold[3], 1)
        b.mark:SetShown(on)
        local t = over and pal.text or pal.textDim
        b.text:SetTextColor(t[1], t[2], t[3])
    end
    function b:SetOn(v) on = v and true or false; Paint_() end
    function b:IsOn() return on end
    b:SetScript("OnEnter", function() over = true; Paint_() end)
    b:SetScript("OnLeave", function() over = false; Paint_() end)
    b:SetScript("OnClick", onClick)
    b.Repaint = Paint_
    Paint_()
    return b
end

local function Refresh()
    if not (f and state) then return end
    local party = state.party
    local blocked = party and state.mode == "new" and PN.SendBlocked() or nil
    if state.mode == "edit" and state.entry.kind == "party" then blocked = PN.SendBlocked() end
    f.save:SetEnabled(blocked == nil and state.mode ~= "preview")
    if state.mode == "preview" then
        f.status:SetText("A preview. Nothing is made, saved or sent.")
        f.status:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
    elseif blocked then
        f.status:SetText(PN.Reason(blocked))
        f.status:SetTextColor(0.80, 0.45, 0.35)
    elseif state.copy then
        f.status:SetText("A copy that is only yours. It stays if the original is removed.")
        f.status:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
    elseif party then
        f.status:SetText("Party members with TwichUI will see it, with this name.")
        f.status:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
    else
        f.status:SetText("Only you see it.")
        f.status:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
    end
end

function PE.Paint()
    if not f then return end
    for _, b in ipairs(f.swatches) do
        local on = b.id == state.color
        local edge = on and pal.text or pal.bronzeLo
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        local size = on and SWATCH_ON or SWATCH
        b:SetSize(size, size)
    end
    f.kindLocal:SetOn(not state.party)
    f.kindParty:SetOn(state.party)
    f.keep:SetOn(state.kept == true)
    Refresh()
end

local function Close()
    if f then f:Hide() end
end

local function Save()
    if not state or state.mode == "preview" then return end
    if not R:Enabled("partyPins") then Close() return end
    local name = f.name:GetText()
    local fields = { name = name, color = state.color, kept = state.kept == true }
    if not PN.CleanName(name) then
        f.status:SetText(PN.Reason("empty-name"))
        f.status:SetTextColor(0.80, 0.45, 0.35)
        return
    end
    local done, why
    if state.mode == "new" then
        fields.map, fields.x, fields.y = state.map, state.x, state.y
        fields.copiedFrom = state.copiedFrom
        if state.party then
            done, why = R.PinSync.CreateParty(fields)
        else
            done, why = PN.AddLocal(fields)
        end
        if done then PN.Select((state.party and "party:" .. done.key) or ("local:" .. done.id)) end
    elseif state.entry.kind == "local" then
        done, why = PN.UpdateLocal(state.entry.pin.id, fields)
    else
        -- only what changed is handed over, so turning Keep on or off alone sends nothing to the party
        local pin, diff = PN.Fresh(state.entry), fields
        if pin then
            diff = {}
            if PN.CleanName(name) ~= pin.name then diff.name = name end
            if state.color ~= pin.color then diff.color = state.color end
            if (state.kept == true) ~= PN.IsKept(pin) then diff.kept = state.kept == true end
        end
        if next(diff) == nil then
            done = pin
        else
            done, why = R.PinSync.UpdateParty(state.entry.pin.key, diff)
        end
    end
    if not done then
        -- a code from Pins, or already a sentence from a permission check
        f.status:SetText(why and why:find(" ") and why or PN.Reason(why))
        f.status:SetTextColor(0.80, 0.45, 0.35)
        return
    end
    state = nil
    Close()
end

local function Build()
    if f then return end
    f = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- above a full-screen map
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
    -- the player's background and border are on f (Restyle); the content sits on body, inside the border
    body = CreateFrame("Frame", nil, f)
    body:SetSize(WIDTH, HEIGHT)
    body:SetPoint("CENTER")
    S.Header(body, 30, pal)
    f.title = PL.Text(body, "GameFontNormal", "name")
    f.title:SetPoint("TOPLEFT", PAD + 2, -12)
    local close = S.Close(body, Close, pal)
    close:SetPoint("TOPRIGHT", -8, -8)

    f.where = PL.Text(body, "GameFontNormalSmall", "meta")
    f.where:SetPoint("TOPLEFT", PAD + 2, -42)
    f.where:SetPoint("RIGHT", -PAD, 0)
    f.where:SetWordWrap(false)

    local label = PL.Text(body, "GameFontNormalSmall", "meta")
    label:SetPoint("TOPLEFT", PAD + 2, -62)
    label:SetText("Name")
    f.name = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
    f.name:SetSize(WIDTH - PAD * 2 - 8, 20)
    f.name:SetPoint("TOPLEFT", PAD + 6, -76)
    f.name:SetAutoFocus(false)
    f.name:SetMaxBytes(PN.NAME_MAX + 1)
    PL.Edit(f.name)
    f.name:SetScript("OnEnterPressed", Save)
    f.name:SetScript("OnEscapePressed", Close)

    local colorLabel = PL.Text(body, "GameFontNormalSmall", "meta")
    colorLabel:SetPoint("TOPLEFT", PAD + 2, -104)
    colorLabel:SetText("Color")
    local row = CreateFrame("Frame", nil, body)
    row:SetSize(WIDTH - PAD * 2, 24)
    row:SetPoint("TOPLEFT", PAD + 2, -118)
    f.swatches = {}
    for i, color in ipairs(PN.COLORS) do f.swatches[i] = Swatch(row, i, color) end

    f.keep = CheckBox(body, "Keep this pin", function()
        if not state then return end
        state.kept = not (state.kept == true)
        PE.Paint()
    end)
    f.keep:SetPoint("TOPLEFT", PAD + 2, -150)
    R.Interact.Tip(f.keep, "Keep this pin", function()
        local body_ = "Protects this pin from deletion and cleanup.\nUnlock it before moving or deleting it."
        if state and state.party then
            body_ = body_ .. "\nA kept party pin stays kept for as long as this party lasts."
        end
        return body_
    end)

    f.kindLocal = S.Toggle(body, "Local", 64, function()
        if state and state.mode ~= "edit" then state.party = false; PE.Paint() end
    end, pal)
    f.kindLocal:SetPoint("TOPLEFT", PAD + 2, -178)
    f.kindParty = S.Toggle(body, "Party", 64, function()
        if state and state.mode ~= "edit" then state.party = true; PE.Paint() end
    end, pal)
    f.kindParty:SetPoint("LEFT", f.kindLocal, "RIGHT", 4, 0)
    R.Interact.Tip(f.kindLocal, "Local pin", "Only on your map, and kept between sessions.")
    R.Interact.Tip(f.kindParty, "Party pin", "Shared with party members who have TwichUI turned on, for as long as you are in this party. Players without TwichUI see nothing.")

    f.status = PL.Text(body, "GameFontNormalSmall", "meta")
    f.status:SetPoint("TOPLEFT", f.kindParty, "TOPRIGHT", 10, -1)
    f.status:SetPoint("RIGHT", -PAD, 0)
    f.status:SetHeight(26)
    f.status:SetJustifyV("TOP")

    f.save = S.Button(body, "Save", 90, "primary", Save, pal)
    f.save:SetPoint("BOTTOMRIGHT", -PAD, 12)
    local cancel = S.Button(body, "Cancel", 80, "secondary", Close, pal)
    cancel:SetPoint("RIGHT", f.save, "LEFT", -6, 0)
    R.Interact.Tip(f.save, "Save", function()
        local blocked = state and (state.party or (state.entry and state.entry.kind == "party")) and PN.SendBlocked()
        return "Makes the pin, or keeps your changes.", blocked and PN.Reason(blocked) or nil
    end)

    f:SetScript("OnHide", function() state = nil end)
    f.widgets = { f.save, cancel, f.kindLocal, f.kindParty, close, f.keep }
    f.labels = { label, colorLabel }
end

-- Draws the player's background and border, then the text and controls in the palette. The window grows by
-- the border's reach so a thick border never covers the content.
local function Restyle()
    if not f then return end
    local edge = math.ceil(PL.Surface(PL.EditorLook, f))
    f:SetSize(WIDTH + edge * 2, HEIGHT + edge * 2)
    S.PaintHeader(body, pal)
    for _, w in ipairs(f.widgets) do w:Repaint() end
    f.title:SetTextColor(pal.text[1], pal.text[2], pal.text[3])
    f.where:SetTextColor(pal.stone[1], pal.stone[2], pal.stone[3])
    for _, fs in ipairs(f.labels) do fs:SetTextColor(pal.textDim[1], pal.textDim[2], pal.textDim[3]) end
    if state then PE.Paint() end   -- the status line's color
end
PE.Restyle = Restyle

local function OnLookChanged() if f and f:IsShown() then Restyle() end end
PL.Subscribe(OnLookChanged)
PL.EditorLook.Subscribe(OnLookChanged)

local function Open(preview)
    Build()
    Restyle()
    f:ClearAllPoints()
    if preview and SettingsPanel and SettingsPanel:IsShown() then
        f:SetPoint("TOPLEFT", SettingsPanel, "TOPRIGHT", 8, -48)
    else
        local anchor = (WorldMapFrame and WorldMapFrame:IsShown()) and WorldMapFrame.ScrollContainer or UIParent
        f:SetPoint("TOP", anchor, "TOP", 0, -60)
    end
    R.FitToScreen(f)
    f:Show()
    f:Raise()
    if not preview then
        f.name:SetFocus()
        f.name:HighlightText()
    end
end

-- A new pin at (map, x, y) in 0..COORD; party: start as a party pin (it can be switched before Save).
function PE.OpenNew(map, x, y, party)
    state = { mode = "new", map = map, x = x, y = y, party = party and true or false, color = PN.DEFAULT_COLOR }
    Open()
    f.title:SetText(party and "New party pin" or "New pin")
    f.where:SetText(PN.Describe({ map = map, x = x, y = y }))
    f.name:SetText(PN.DefaultName())
    f.kindLocal:Show(); f.kindParty:Show()
    PE.Paint()
end

-- "Save to my pins": a local pin made from a party pin's fields (PN.CopyFields), for the player to review.
-- Kept by default. Nothing is made until Save, and the original party pin is not touched or sent anywhere.
function PE.OpenCopy(fields)
    if type(fields) ~= "table" then return false end
    state = { mode = "new", copy = true, map = fields.map, x = fields.x, y = fields.y, party = false,
        color = PN.ValidColor(fields.color) and fields.color or PN.DEFAULT_COLOR, kept = true, copiedFrom = fields.copiedFrom }
    Open()
    f.title:SetText("Save to my pins")
    f.where:SetText(PN.Describe(fields))
    f.name:SetText(fields.name or PN.DefaultName())
    f.kindLocal:Hide(); f.kindParty:Hide()
    PE.Paint()
    return true
end

-- Rename or recolor a local pin, or one of your own party pins.
function PE.OpenEdit(e)
    local ok, why = PN.Can("edit", e)
    if not ok then R.PinsMap.Notice(why) return false end
    local pin = PN.Fresh(e)
    state = { mode = "edit", entry = e, party = e.kind == "party", color = pin.color, kept = PN.IsKept(pin) }
    Open()
    f.title:SetText(e.kind == "party" and "Edit party pin" or "Edit pin")
    f.where:SetText(PN.Describe(pin))
    f.name:SetText(pin.name)
    f.kindLocal:Hide(); f.kindParty:Hide()
    PE.Paint()
    return true
end

-- The options page's Preview: the real window, with a made-up pin, beside the options window. Save does
-- nothing in it. It stays until pressed again or Esc, and a real editor opened meanwhile replaces it.
function PE.TogglePreview()
    if f and f:IsShown() and state then
        if state.mode == "preview" then Close() end   -- a real pin being edited is left alone
        return
    end
    if not R:Enabled("partyPins") then return end
    state = { mode = "preview", party = false, color = PN.DEFAULT_COLOR }
    Open(true)
    f.title:SetText("New pin")
    f.where:SetText("Elwynn Forest (40.0, 50.0)")
    f.name:SetText(PN.DefaultName())
    f.kindLocal:Show(); f.kindParty:Show()
    PE.Paint()
end

function PE.IsOpen() return f ~= nil and f:IsShown() end
PE.Close = Close

-- A party change while it is open (left the party, a raid) shows at once on Save and in its note.
PN.OnChange(function() if f and f:IsShown() then Refresh() end end)
