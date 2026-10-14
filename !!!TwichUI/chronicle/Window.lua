-- TwichUI: Journey Chronicle window (/tui chronicle)
-- A plain, closed-by-default journal: a scrolling timeline, newest first, and a
-- small box for writing a note. It only reads and edits entries through
-- chronicle/Data.lua. Its look (colours, frame, buttons) lives in chronicle/Style.lua.

local R = TwichUI
local C = R.Chronicle
local W = {}
R.ChronicleWindow = W

local GREY = R.GREY
local S = R.ChronicleStyle
local A = R.ChronicleAppearance
local PAL = A.palette                    -- the colours this window draws with (chronicle/Appearance.lua)
local WIDTH, HEIGHT = 540, 580           -- the window at the default look; borders, padding and text add to them
local BAND = 56                          -- the title band's height at the default look
local LIST_W = WIDTH - 32
local ROW_W = LIST_W - 40                -- inside the list box and its scroll bar
local f                                  -- main window
local ed                                 -- note editor
local editingId                          -- nil while writing a new note
local rows = {}                          -- row frames, reused
local windows = {}                       -- the Chronicle's own windows, for the appearance code
local hintWarn = false                   -- the editor's hint is showing a problem

-- Text and controls are made through chronicle/Appearance.lua, which gives them the player's fonts and
-- repaints them when the palette changes. role: title, heading, body, meta or control. color: the
-- palette colour the text is drawn in (leave it out where the game's font colour is what is wanted, or
-- the colour means something and is set here).
local function Text(parent, template, role, color)
    return A.Text(parent, template, role or "body", color)
end

-- "12" (default) or "24", chosen in the options (chronicle/Data.lua's C.Clock).
local function When(t)
    if not C.DayKey(t) then return "Date unknown" end   -- never an invented date
    if C.Clock() == "24" then return date("%b %d, %Y  %H:%M", t) end
    return (date("%b %d, %Y  %I:%M %p", t):gsub(" 0(%d:)", " %1"))
end

local function Escape(text) return (text or ""):gsub("|", "||") end

local function Btn(parent, label, w, kind, onClick)
    local b = S.Button(parent, label, w, kind, onClick, PAL)
    A.Track(b.text, "GameFontNormalSmall", "control")
    A.Widget(b)
    b.baseWidth = w
    return b
end

-- A button wide enough for its label in the font in use (never narrower than it was made).
local function FitButton(b)
    local width = b.text:GetStringWidth()
    if type(width) == "number" and width > 0 then
        local want = math.max(b.baseWidth, math.ceil(width + 20))
        if math.abs((b:GetWidth() or 0) - want) > 0.5 then b:SetWidth(want) end
    end
end

local function Window(name, w, h, title, bandH)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p.baseWidth, p.baseHeight, p.band = w, h, bandH
    p:SetSize(w, h)
    p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)
    p:SetClampedToScreen(true)
    p:HookScript("OnShow", function() A.Sync() end)   -- before the fit: a change made while closed may resize it
    p:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, name)   -- Esc closes it
    S.Frame(p, w, h, PAL)
    S.Header(p, bandH, PAL)
    p.title = Text(p, "GameFontNormalLarge", "title", PAL.titleText)
    p.title:SetPoint("TOPLEFT", 18, -12)
    p.title:SetText(title)
    p.close = A.Widget(S.Close(p, function() p:Hide() end, PAL))
    p.close:SetPoint("TOPRIGHT", -9, -9)
    windows[#windows + 1] = p
    return p
end

-- Fits a window to the screen after it was sized. The border's pixels are worked out at the window's
-- scale, so if fitting changed the scale it is drawn once more at the new one.
local function Settle(p, again)
    R.FitToScreen(p)
    if not p.settling and math.abs((p:GetScale() or 1) - (p.paintScale or 1)) > 0.001 then
        p.settling = true
        again()
        p.settling = false
    end
end

-- How far in from its edge a window's content sits, and what its title adds to the band: the band
-- and everything under it move down by the title's growth, the window grows by the same.
local function Chrome(p, more)
    local inset = A.Surface(p)
    local titleGrow = A.Grow(p.title, 16)
    S.PaintHeader(p, PAL, inset, p.band + titleGrow + (more or 0))
    p.title:ClearAllPoints()
    p.title:SetPoint("TOPLEFT", inset + 14, -(inset + 8))
    p.close:ClearAllPoints()
    p.close:SetPoint("TOPRIGHT", -(inset + 5), -(inset + 5))
    return inset, titleGrow
end

---------------------------------------------------------------------------
-- Note editor
---------------------------------------------------------------------------
local HINT = "Press Enter to save, Esc to cancel."

-- Something to save: the editor won't close on an empty note or throw away what was typed.
local function HasText() return (ed.box:GetText() or ""):match("%S") ~= nil end

-- The hint under the note: quiet, or in the warning colour when something needs saying.
local function SetHint(text, warn)
    hintWarn = warn and true or false
    ed.hint:SetText(text)
    local c = hintWarn and PAL.ember or PAL.stone
    ed.hint:SetTextColor(c[1], c[2], c[3])
end

local function SaveNote()
    if not ed:IsShown() then return end     -- already saved or cancelled: a second Enter or click does nothing
    if not HasText() then
        SetHint(editingId and "A note can't be left empty. Esc cancels; to remove it, use Delete on its entry."
            or "Write something to save, or press Esc to cancel.", true)
        return
    end
    local text = ed.box:GetText()
    local keep = ed.place:IsShown() and ed.place:GetChecked() and true or false
    if editingId then
        if not C.Update(editingId, text, keep) and (text or ""):match("%S") then
            R.Print("that note can't be changed.")
        end
    else
        local entry, why = C.Add("note", { title = "Note", note = text, zone = keep and ed.zone or nil })
        if not entry and why == "full" then
            R.Print("your Chronicle holds %d entries, its limit. Delete one to write another.", C.MAX_ENTRIES)
            return
        end
    end
    ed:Hide()
    W:Refresh()
end

-- The editor's content sits in from the border by the window's inset; the window is as wide and tall as
-- its content needs (so a thick border or large text never covers the box or the buttons).
local StyleEditor
function StyleEditor()
    local inset, grow = Chrome(ed)
    local key = inset .. ":" .. grow
    if ed.geoKey ~= key then
        ed.geoKey = key
        local d = inset - 4
        ed:SetSize(ed.baseWidth + 2 * d, ed.baseHeight + 2 * d + grow)
        ed.box:ClearAllPoints()
        ed.box:SetPoint("TOPLEFT", inset + 18, -(inset + 48 + grow))
        ed.count:ClearAllPoints()
        ed.count:SetPoint("TOPRIGHT", -(inset + 16), -(inset + 74 + grow))
        ed.place:ClearAllPoints()
        ed.place:SetPoint("TOPLEFT", inset + 12, -(inset + 92 + grow))
        ed.hint:ClearAllPoints()
        ed.hint:SetPoint("TOPLEFT", inset + 16, -(inset + 124 + grow))
        ed.save:ClearAllPoints()
        ed.save:SetPoint("BOTTOMRIGHT", -(inset + 12), inset + 10)
    end
    FitButton(ed.save)
    FitButton(ed.cancel)
    local c = hintWarn and PAL.ember or PAL.stone
    ed.hint:SetTextColor(c[1], c[2], c[3])
    Settle(ed, StyleEditor)
end

local function BuildEditor()
    A.Prepare()
    ed = Window("TwichUIChronicleNote", 440, 190, "", 34)
    ed:SetFrameStrata("FULLSCREEN_DIALOG")
    ed.box = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
    ed.box:SetSize(396, 24)
    ed.box:SetPoint("TOPLEFT", 22, -52)
    ed.box:SetAutoFocus(false)
    ed.box:SetMaxLetters(C.MAX_NOTE)
    A.TrackEdit(ed.box)   -- what you type follows the text face and size; its colour is the game's
    ed.box:SetScript("OnEnterPressed", SaveNote)
    ed.box:SetScript("OnEscapePressed", function() ed:Hide() end)
    ed.box:SetScript("OnTextChanged", function(self)
        ed.count:SetText(("%d / %d"):format(C.Length(self:GetText() or ""), C.MAX_NOTE))
        if ed.save then ed.save:SetEnabled(HasText()) end
        if ed.hint then SetHint(HINT, false) end
    end)
    ed.count = Text(ed, "GameFontDisableSmall", "meta")
    ed.count:SetPoint("TOPRIGHT", -20, -78)
    ed.place = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    ed.place:SetSize(22, 22)
    ed.place:SetPoint("TOPLEFT", 16, -96)
    ed.placeText = Text(ed, "GameFontHighlightSmall", "body")
    ed.placeText:SetPoint("LEFT", ed.place, "RIGHT", 4, 0)
    ed.hint = Text(ed, "GameFontDisableSmall", "meta")
    ed.hint:SetPoint("TOPLEFT", 20, -128)
    ed.hint:SetText(HINT)
    ed.save = Btn(ed, "Save", 90, "primary", SaveNote)
    ed.save:SetPoint("BOTTOMRIGHT", -16, 14)
    ed.cancel = Btn(ed, "Cancel", 90, "secondary", function() ed:Hide() end)
    ed.cancel:SetPoint("RIGHT", ed.save, "LEFT", -8, 0)
    ed:SetScript("OnHide", function() if not (f and f:IsShown()) then A.Cancel() end end)
    StyleEditor()
    ed:Hide()
end

-- entry: the note being changed, or nil to write a new one.
local function OpenEditor(entry)
    if not ed then BuildEditor() end
    editingId = entry and entry.id or nil
    ed.title:SetText(entry and "Edit note" or "Write a note")
    ed.box:SetText(entry and entry.note or "")
    ed.save:SetEnabled(HasText())          -- SetText doesn't announce a change when the box was already empty
    SetHint(HINT, false)
    if entry then
        ed.zone = entry.zone
        ed.place:SetShown(entry.zone ~= nil)
        ed.place:SetChecked(entry.zone ~= nil)
        ed.placeText:SetText(entry.zone and ("Keep the place: " .. Escape(entry.zone)) or "")
    else
        ed.zone = C.CurrentZone()
        ed.place:SetShown(true)
        ed.place:SetChecked(ed.zone ~= nil)
        if ed.zone then
            ed.place:Enable()
            ed.placeText:SetText("Add where I am: " .. Escape(ed.zone))
        else
            ed.place:Disable()
            ed.placeText:SetText(GREY .. "The game isn't giving a place right now.|r")
        end
    end
    ed:Show()
    ed.box:SetFocus()
end

---------------------------------------------------------------------------
-- Timeline
---------------------------------------------------------------------------
-- A short, safe-to-show piece of an entry's own words (cut at a whole character).
local function Snippet(entry)
    local text = (entry.kind == "note" and (entry.note or entry.title) or entry.title) or ""
    if #text > 60 then
        local cut = 57
        while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        text = text:sub(1, cut) .. "..."
    end
    return Escape(text)
end

local function AskDelete(entry)
    local id = entry.id
    local what = entry.kind == "note" and "note" or "entry"
    R.Interact.Confirm("TWICHUI_CHRONICLE_DELETE",
        ("Delete this %s from this character's Chronicle?\n\n%s  \"%s\"\n\nThis can't be undone."):format(what, When(entry.t), Snippet(entry)),
        function() C.Delete(id); W:Refresh() end, {
            accept = DELETE or "Delete",
            valid = function()
                for _, e in ipairs(C.Entries()) do if e.id == id then return true end end
                return false, "That entry is already gone, so nothing was changed."
            end,
        })
end

-- Edit and Delete show only while the pointer is on the row (or on one of them).
local function ShowActions(r)
    local over = r:IsMouseOver()
    r.hover:SetShown(over)
    r.delete:SetShown(over)
    r.edit:SetShown(over and r.entry ~= nil and r.entry.kind == "note")
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.content)
    r:SetWidth(ROW_W)
    r:EnableMouse(true)
    S.RowArt(r, PAL)
    r.marker = S.Marker(r, PAL)
    r.when = Text(r, "GameFontDisableSmall", "meta", PAL.stone)
    r.when:SetPoint("TOPLEFT", 32, -8)
    r.when:SetWidth(ROW_W - 38)
    r.when:SetWordWrap(false)             -- one line: a long place is cut, not run over the next
    r.title = Text(r, "GameFontNormal", "heading", PAL.text)
    r.title:SetPoint("TOPLEFT", r.when, "BOTTOMLEFT", 0, -3)
    r.title:SetWidth(ROW_W - 38)
    r.title:SetWordWrap(true)
    r.note = Text(r, "GameFontHighlightSmall", "body", PAL.textDim)
    r.note:SetWidth(ROW_W - 38)
    r.note:SetWordWrap(true)
    r.delete = S.Link(r, "Delete", function() AskDelete(r.entry) end, PAL.ember, PAL.emberHi)
    r.delete:SetPoint("TOPRIGHT", -6, -6)
    r.edit = S.Link(r, "Edit", function() OpenEditor(r.entry) end, PAL.gold, PAL.text)
    r.edit:SetPoint("RIGHT", r.delete, "LEFT", -6, 0)
    A.Track(r.delete.text, "GameFontNormalSmall", "control")
    A.Track(r.edit.text, "GameFontNormalSmall", "control")
    r.delete:Hide()
    r.edit:Hide()
    local function Sync() ShowActions(r) end
    r:SetScript("OnEnter", Sync)
    r:SetScript("OnLeave", Sync)
    r.delete:HookScript("OnLeave", Sync)
    r.edit:HookScript("OnLeave", Sync)
    r:SetScript("OnHide", function(self) self.hover:Hide(); self.delete:Hide(); self.edit:Hide() end)
    rows[i] = r
    return r
end

-- Draws the entries that match the date filter, newest first.
-- Returns how many are shown, how many exist, and how many were left out for having no usable date.
-- Each row is as tall as its text needs in the fonts in use: the date line grows with its font, the
-- headline and the note are measured wrapped at the row's width.
local function Layout()
    local entries = C.Entries()
    local total = #entries
    local active = C.FilterActive()
    local y, shown, undated = 0, 0, 0
    for k = total, 1, -1 do
      local e = entries[k]                    -- newest first
      if not C.Matches(e) then
        if active and not C.DayKey(e.t) then undated = undated + 1 end
      else
        shown = shown + 1
        local r = Row(shown)
        r.entry = e
        local isNote = e.kind == "note"
        S.SetMarker(r.marker, e.kind, e.icon, PAL)
        local where = e.zone and ("  " .. GREY .. "·|r  " .. Escape(e.zone)) or ""
        r.when:SetText((isNote and "Note  " .. GREY .. "·|r  " or "") .. When(e.t) .. where)
        r.title:SetText(Escape(isNote and (e.note or e.title) or e.title))
        local h = 10 + 12 + A.Grow(r.when, 10) + 3 + (r.title:GetStringHeight() or 14) + 12
        if not isNote and e.note then
            r.note:ClearAllPoints()
            r.note:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
            r.note:SetText(Escape(e.note))
            r.note:Show()
            h = h + 4 + (r.note:GetStringHeight() or 12)
        else
            r.note:SetText("")
            r.note:Hide()
        end
        r.hover:Hide(); r.delete:Hide(); r.edit:Hide()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        r:SetHeight(h)
        r:Show()
        y = y + h
      end
    end
    for i = shown + 1, #rows do rows[i].entry = nil; rows[i]:Hide() end
    f.content:SetHeight(math.max(y, 1))
    return shown, total, undated
end

---------------------------------------------------------------------------
-- Date filter: a small calendar that opens from the control above the list.
-- Days come from the stored entries (chronicle/Filter.lua); nothing is saved.
---------------------------------------------------------------------------
local CELL_W, CELL_H = 30, 24
local POP_W = 8 + 7 * CELL_W + 8
local pop, catcher                   -- the calendar and the click-away layer behind it
local viewY, viewM                   -- month being shown
local pickMode = "day"               -- what choosing a day does: "day" or "since"

local function SetFilter(mode, day)
    C.SetFilter(mode, day)
    if mode == "day" or mode == "since" then pickMode = mode end
    W:Refresh()
end

local function ClosePicker() if pop then pop:Hide() end end

-- The calendar's marks follow the accent and the border colour; set when it is built and when they change.
local function PaintCalendarColors()
    if not pop then return end
    for _, cell in ipairs(pop.cells) do
        cell.range:SetColorTexture(PAL.gold[1], PAL.gold[2], PAL.gold[3], 0.10)
        cell.sel:SetColorTexture(PAL.gold[1], PAL.gold[2], PAL.gold[3], 0.55)
        cell.hl:SetColorTexture(PAL.gold[1], PAL.gold[2], PAL.gold[3], 0.16)
        cell.today:SetColorTexture(PAL.gold[1], PAL.gold[2], PAL.gold[3], 0.8)
        cell.dot:SetColorTexture(PAL.bronze[1], PAL.bronze[2], PAL.bronze[3], 0.9)
    end
end

local function PaintCalendar()
    local counts = C.DayCounts()
    local mode, sel = C.GetFilter()
    local today = C.Today()
    pop.title:SetText(C.MONTHS[viewM] .. " " .. viewY)
    local first = C.Weekday(viewY, viewM, 1)
    local days = C.DaysInMonth(viewY, viewM)
    for i = 1, 42 do
        local cell = pop.cells[i]
        local d = i - first
        if d >= 1 and d <= days then
            local day = C.MakeDay(viewY, viewM, d)
            cell.day = day
            cell.num:SetText(d)
            local tone = day == today and PAL.gold or PAL.text
            cell.num:SetTextColor(tone[1], tone[2], tone[3])
            cell.today:SetShown(day == today)
            cell.dot:SetShown(counts[day] ~= nil)
            cell.sel:SetShown(mode ~= "all" and day == sel)
            cell.range:SetShown(mode == "since" and day > sel)
            cell:Show()
        else
            cell.day = nil
            cell:Hide()
        end
    end
    pop.dayBtn:SetOn(pickMode == "day")
    pop.sinceBtn:SetOn(pickMode == "since")
end

local function ShiftMonth(months)
    local total = viewY * 12 + (viewM - 1) + months
    viewY, viewM = math.min(math.max(math.floor(total / 12), 1970), 2999), total % 12 + 1
    PaintCalendar()
end

local function BuildPicker()
    catcher = CreateFrame("Button", nil, f)
    catcher:SetAllPoints(f)
    catcher:SetFrameLevel(f:GetFrameLevel() + 30)
    catcher:SetScript("OnClick", ClosePicker)
    catcher:Hide()
    pop = CreateFrame("Frame", "TwichUIChronicleDate", f, "BackdropTemplate")
    pop:SetSize(POP_W, 286)
    pop:SetFrameLevel(f:GetFrameLevel() + 40)
    pop:EnableMouse(true)
    pop:SetPoint("TOPLEFT", f.filter, "BOTTOMLEFT", 0, -2)
    S.Popover(pop, PAL)
    pop:SetScript("OnShow", function() catcher:Show() end)
    pop:SetScript("OnHide", function()
        catcher:Hide()
        for _, cell in ipairs(pop.cells) do R.Interact.HideTip(cell) end   -- a day's tooltip doesn't outlive its calendar
    end)

    local function Nav(label, w, x, months)
        local b = Btn(pop, label, w, "secondary", function() ShiftMonth(months) end)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", x, -8)
        return b
    end
    Nav("<<", 28, 8, -12)
    Nav("<", 24, 40, -1)
    Nav(">", 24, POP_W - 64, 1)
    Nav(">>", 28, POP_W - 36, 12)
    pop.title = Text(pop, "GameFontNormal", "control", PAL.text)   -- the picker's text keeps its size: its cells are fixed
    pop.title:SetPoint("TOP", 0, -12)

    local names = { "S", "M", "T", "W", "T", "F", "S" }
    for i = 1, 7 do
        local h = Text(pop, "GameFontDisableSmall", "control", PAL.stone)
        h:SetWidth(CELL_W)
        h:SetJustifyH("CENTER")
        h:SetPoint("TOPLEFT", 8 + (i - 1) * CELL_W, -38)
        h:SetText(names[i])
    end
    pop.cells = {}
    for i = 1, 42 do
        local cell = CreateFrame("Button", nil, pop)
        cell:SetSize(CELL_W, CELL_H)
        cell:SetPoint("TOPLEFT", 8 + ((i - 1) % 7) * CELL_W, -52 - math.floor((i - 1) / 7) * CELL_H)
        cell.range = cell:CreateTexture(nil, "BACKGROUND")
        cell.range:SetAllPoints()
        cell.sel = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
        cell.sel:SetPoint("TOPLEFT", 1, -1)
        cell.sel:SetPoint("BOTTOMRIGHT", -1, 1)
        cell.hl = cell:CreateTexture(nil, "BACKGROUND", nil, 2)
        cell.hl:SetAllPoints()
        cell.hl:Hide()
        cell.num = Text(cell, "GameFontHighlightSmall", "control")
        cell.num:SetPoint("CENTER", 0, 1)
        cell.num:SetJustifyH("CENTER")
        cell.today = cell:CreateTexture(nil, "ARTWORK")
        cell.today:SetSize(10, 1)
        cell.today:SetPoint("BOTTOM", 0, 5)
        cell.dot = cell:CreateTexture(nil, "ARTWORK")
        cell.dot:SetSize(3, 3)
        cell.dot:SetPoint("TOP", cell.num, "BOTTOM", 0, -2)
        cell:SetScript("OnClick", function(self) if self.day then SetFilter(pickMode, self.day) end end)
        cell:SetScript("OnEnter", function(self)
            self.hl:Show()
            if not self.day then return end
            local n = C.DayCounts()[self.day]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(C.FormatDay(self.day), 1, 1, 1)
            GameTooltip:AddLine(n and (n == 1 and "1 entry" or n .. " entries") or "No entries", 0.8, 0.75, 0.6)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        pop.cells[i] = cell
    end

    -- Choosing a day applies with this mode; picking it with a day already chosen re-applies that day.
    local function Mode(mode)
        pickMode = mode
        local _, day = C.GetFilter()
        if day then SetFilter(mode, day) else PaintCalendar() end
    end
    pop.dayBtn = A.Widget(S.Toggle(pop, "That day", 105, function() Mode("day") end, PAL))
    pop.dayBtn:SetPoint("TOPLEFT", 8, -204)
    pop.sinceBtn = A.Widget(S.Toggle(pop, "Since this day", 105, function() Mode("since") end, PAL))
    pop.sinceBtn:SetPoint("TOPLEFT", 8 + 109, -204)
    A.Track(pop.dayBtn.text, "GameFontNormalSmall", "control")
    A.Track(pop.sinceBtn.text, "GameFontNormalSmall", "control")

    local function Shortcut(label, w, x, onClick)
        local l = S.Link(pop, label, function() onClick(); ClosePicker() end, PAL.gold, PAL.text)
        A.Widget(l)
        A.Track(l.text, "GameFontNormalSmall", "control")
        l:SetSize(w, 14)
        l.text:SetJustifyH("LEFT")
        l:SetPoint("TOPLEFT", x, -236)
    end
    Shortcut("Today", 38, 10, function() SetFilter("day", C.Today()) end)
    Shortcut("Last 7 days", 66, 58, function() SetFilter("since", C.AddDays(C.Today(), -6)) end)
    Shortcut("Last 30 days", 72, 134, function() SetFilter("since", C.AddDays(C.Today(), -29)) end)
    local clear = Btn(pop, "Clear filter", POP_W - 16, "secondary", function() SetFilter("all"); ClosePicker() end)
    clear:SetPoint("TOPLEFT", 8, -256)
    PaintCalendarColors()
    pop:Hide()
end

local function TogglePicker()
    if not pop then BuildPicker() end
    if pop:IsShown() then pop:Hide() return end
    local _, day = C.GetFilter()
    day = day or C.Today()
    if day then viewY, viewM = C.DayParts(day) else viewY, viewM = 1970, 1 end
    local mode = C.GetFilter()
    if mode ~= "all" then pickMode = mode end
    PaintCalendar()
    pop:Show()
end

-- The title line shares its row with the played time: the character and count give way to it.
local function FitHeader()
    if not f then return end
    local avail = WIDTH - 58                                  -- the room between the title's margins
    local played = f.played:GetStringWidth()
    if type(played) ~= "number" then played = 0 end
    f.sub:SetWidth(math.max(80, avail - played - 10))
end

-- "Journey time: 3d 7h 24m", or a dash until the game has answered.
local function ShowPlayed(total)
    if not f or not f:IsShown() then return end
    f.played:SetText("Journey time: " .. (C.FormatDuration(total) or "\226\128\148"))
    FitHeader()
end

W.ShowPlayed = ShowPlayed

-- Asks for the total played time; only when the window opens (and, through the recorder, after a level-up).
local function RequestPlayed()
    f.played:SetText("Journey time: \226\128\148")
    FitHeader()
    if R.ChronicleRecorder and R.ChronicleRecorder.RequestPlayed then
        R.ChronicleRecorder.RequestPlayed(ShowPlayed)
    end
end

function W:Refresh()
    if not f or not f:IsShown() then return end
    local n, total, undated = Layout()
    local active = C.FilterActive()
    -- All time: the number stored. Filtered: how many of them are shown.
    local count = active and ("%d of %d entries"):format(n, total) or ("%d %s"):format(total, total == 1 and "entry" or "entries")
    f.sub:SetText(("%s  %s·  %s|r"):format(Escape(C.CharKey()), GREY, count))
    f.filter.text:SetText(C.FilterLabel())
    f.undated:SetText(active and undated > 0
        and (undated == 1 and "1 entry without a date is only in All time" or undated .. " entries without a date are only in All time") or "")
    f.empty:SetShown(total == 0)
    if active and total > 0 and n == 0 then
        local mode, day = C.GetFilter()
        f.noMatchText:SetText("No entries " .. (mode == "day" and "on " or "since ") .. C.FormatDay(day) .. ".")
        f.noMatch:Show()
    else
        f.noMatch:Hide()
    end
    if pop and pop:IsShown() then PaintCalendar() end
end

---------------------------------------------------------------------------
-- Appearance: surfaces, layout and colours follow chronicle/Appearance.lua. Everything here moves or
-- recolours what already exists; nothing is created, so a change never adds a frame, texture or hook.
---------------------------------------------------------------------------
local StyleMain
function StyleMain()
    local metaGrow = A.Grow(f.sub, 10)
    local inset, titleGrow = Chrome(f, metaGrow)
    local hx = titleGrow + metaGrow
    S.PaintWell(f.box, PAL)
    if f.paintScroll then f.paintScroll() end
    local key = inset .. ":" .. hx
    if f.geoKey ~= key then
        f.geoKey = key
        local d = inset - 4
        -- the window keeps its place and its list its size: border, padding and larger header text
        -- make the window bigger instead
        f:SetSize(WIDTH + 2 * d, HEIGHT + 2 * d + hx)
        f.sub:ClearAllPoints()
        f.sub:SetPoint("TOPLEFT", inset + 14, -(inset + 32 + titleGrow))
        f.played:ClearAllPoints()
        f.played:SetPoint("TOPRIGHT", -(inset + 36), -(inset + 35 + titleGrow))
        f.filter:ClearAllPoints()
        f.filter:SetPoint("TOPLEFT", inset + 12, -(inset + 62 + hx))
        f.undated:ClearAllPoints()
        f.undated:SetPoint("LEFT", f.filter, "RIGHT", 10, 0)
        f.undated:SetPoint("RIGHT", f, "RIGHT", -(inset + 14), 0)
        f.box:ClearAllPoints()
        f.box:SetPoint("TOPLEFT", inset + 12, -(inset + 90 + hx))
        f.box:SetPoint("BOTTOMRIGHT", -(inset + 12), inset + 48)
        f.new:ClearAllPoints()
        f.new:SetPoint("BOTTOMLEFT", inset + 12, inset + 12)
        f.options:ClearAllPoints()
        f.options:SetPoint("BOTTOMRIGHT", -(inset + 12), inset + 12)
    end
    FitButton(f.new)
    FitButton(f.options)
    FitButton(f.clearBtn)
    -- the filter's label is the chosen day or span: give it room in the font in use
    local label = f.filter.text:GetStringWidth()
    if type(label) == "number" and label > 0 then
        local want = math.max(170, math.ceil(label + 34))
        if math.abs((f.filter:GetWidth() or 0) - want) > 0.5 then f.filter:SetWidth(want) end
    end
    FitHeader()
    Settle(f, StyleMain)
end

-- The pass after a setting changed (or opened with one waiting): the windows that exist draw again.
local function Restyle()
    if f then StyleMain() end
    if ed then StyleEditor() end
    if pop then
        S.PaintPopover(pop, PAL)
        PaintCalendarColors()
        if pop:IsShown() then PaintCalendar() end
    end
    for _, r in ipairs(rows) do
        S.PaintRow(r, PAL)
        r.delete:Repaint()
        r.edit:Repaint()
    end
    if f and f:IsShown() then W:Refresh() end   -- row heights come from the text as it is drawn now
end

A.Subscribe(Restyle)
A.SetVisibility(function() return (f and f:IsShown()) or (ed and ed:IsShown()) or false end)

local function Build()
    A.Prepare()
    f = Window("TwichUIChronicle", WIDTH, HEIGHT, "Journey Chronicle", BAND)
    f.sub = Text(f, "GameFontHighlightSmall", "meta", PAL.stone)
    f.sub:SetPoint("TOPLEFT", 18, -36)
    f.sub:SetWordWrap(false)
    f.played = Text(f, "GameFontDisableSmall", "meta", PAL.stone)
    f.played:SetPoint("TOPRIGHT", -40, -39)
    f.played:SetJustifyH("RIGHT")
    f.played:SetText("Journey time: \226\128\148")
    f.filter = A.Widget(S.DropButton(f, 170, TogglePicker, PAL))
    A.Track(f.filter.text, "GameFontNormalSmall", "control")
    f.filter:SetPoint("TOPLEFT", 16, -66)
    f.undated = Text(f, "GameFontDisableSmall", "meta", PAL.stone)
    f.undated:SetPoint("LEFT", f.filter, "RIGHT", 10, 0)
    f.undated:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.undated:SetJustifyH("RIGHT")

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.box = box
    box:SetPoint("TOPLEFT", 16, -94)
    box:SetPoint("BOTTOMRIGHT", -16, 52)
    S.Well(box, LIST_W, HEIGHT - 94 - 52, PAL)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(f.content)
    f.paintScroll = S.ScrollBar(scroll, PAL)

    f.empty = Text(box, "GameFontDisable", "meta", PAL.stone)
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(LIST_W - 80)
    f.empty:SetJustifyH("CENTER")
    f.empty:SetText("Your Chronicle is empty.\n\nIt fills as you write notes and as the moments you chose to keep happen. Nothing from before is added.")

    f.noMatch = CreateFrame("Frame", nil, box)
    f.noMatch:SetSize(LIST_W - 80, 60)
    f.noMatch:SetPoint("CENTER")
    f.noMatchText = Text(f.noMatch, "GameFontDisable", "meta", PAL.stone)
    f.noMatchText:SetPoint("TOP", 0, 0)
    f.noMatchText:SetWidth(LIST_W - 80)
    f.noMatchText:SetJustifyH("CENTER")
    f.clearBtn = Btn(f.noMatch, "Clear filter", 110, "secondary", function() SetFilter("all") end)
    f.clearBtn:SetPoint("TOP", 0, -30)
    f.noMatch:Hide()

    f.new = Btn(f, "Write a note", 120, "primary", function() OpenEditor(nil) end)
    f.new:SetPoint("BOTTOMLEFT", 16, 16)
    f.options = Btn(f, "Options", 90, "secondary", function()
        f:Hide()
        R:OpenSettings("chronicle")
    end)
    f.options:SetPoint("BOTTOMRIGHT", -16, 16)
    -- OnShow runs once per opening, not on refreshes: the sound and the played-time request belong here.
    -- A.Sync first: a setting changed while the window was closed is drawn before it is seen.
    f:SetScript("OnShow", function()
        A.Sync()
        if R:Enabled("chronicleSound") and PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then
            PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        end
        RequestPlayed()
        W:Refresh()
    end)
    -- The date filter is only for this viewing; the next time the Chronicle opens it starts at All time.
    f:SetScript("OnHide", function()
        C.ClearFilter()
        pickMode = "day"
        if pop then pop:Hide() end
        if not (ed and ed:IsShown()) then A.Cancel() end   -- nothing is open: a waiting pass has nothing to draw
    end)
    StyleMain()
    f:Hide()
end

function W:Show()
    if not f then Build() end
    f:Show()
    W:Refresh()
end

function W:Hide()
    if f then f:Hide() end
    if ed then ed:Hide() end
end

function W:Toggle()
    if f and f:IsShown() then W:Hide() else W:Show() end
end
