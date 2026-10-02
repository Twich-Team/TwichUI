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
local K = S.color
local WIDTH, HEIGHT = 540, 580
local LIST_W = WIDTH - 32
local ROW_W = LIST_W - 40            -- inside the list box and its scroll bar
local f                              -- main window
local ed                             -- note editor
local editingId                      -- nil while writing a new note
local rows = {}                      -- row frames, reused

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return fs
end

-- "12" (default) or "24", chosen in the options.
local function When(t)
    local ui = TwichUIDB and TwichUIDB.ui
    if ui and ui.chronicleClock == "24" then return date("%b %d, %Y  %H:%M", t) end
    return (date("%b %d, %Y  %I:%M %p", t):gsub(" 0(%d:)", " %1"))
end

local function Escape(text) return (text or ""):gsub("|", "||") end

local function Btn(parent, label, w, kind, onClick)
    return S.Button(parent, label, w, kind, onClick)
end

local function Window(name, w, h, title, bandH)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
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
    tinsert(UISpecialFrames, name)   -- Esc closes it
    S.Frame(p, w, h)
    S.Header(p, bandH)
    p.title = Text(p, "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 18, -12)
    p.title:SetText(title)
    p.title:SetTextColor(K.text[1], K.text[2], K.text[3])
    local close = S.Close(p, function() p:Hide() end)
    close:SetPoint("TOPRIGHT", -9, -9)
    return p
end

---------------------------------------------------------------------------
-- Note editor
---------------------------------------------------------------------------
local function SaveNote()
    local text = ed.box:GetText()
    local keep = ed.place:IsShown() and ed.place:GetChecked() and true or false
    if editingId then
        if not C.Update(editingId, text, keep) and (text or ""):match("%S") then
            R.Print("that note can't be changed.")
        end
    else
        local entry, why = C.Add("note", { title = "Note", note = text, zone = keep and ed.zone or nil })
        if not entry and why == "full" then
            R.Print("your Chronicle holds %d notes, its limit. Delete one to write another.", C.MAX_ENTRIES)
            return
        end
    end
    ed:Hide()
    W:Refresh()
end

local function BuildEditor()
    ed = Window("TwichUIChronicleNote", 440, 190, "", 34)
    ed:SetFrameStrata("FULLSCREEN_DIALOG")
    ed.box = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
    ed.box:SetSize(396, 24)
    ed.box:SetPoint("TOPLEFT", 22, -52)
    ed.box:SetAutoFocus(false)
    ed.box:SetMaxLetters(C.MAX_NOTE)
    ed.box:SetScript("OnEnterPressed", SaveNote)
    ed.box:SetScript("OnEscapePressed", function() ed:Hide() end)
    ed.box:SetScript("OnTextChanged", function(self)
        ed.count:SetText(("%d / %d"):format(#(self:GetText() or ""), C.MAX_NOTE))
    end)
    ed.count = Text(ed, "GameFontDisableSmall")
    ed.count:SetPoint("TOPRIGHT", -20, -78)
    ed.place = CreateFrame("CheckButton", nil, ed, "UICheckButtonTemplate")
    ed.place:SetSize(22, 22)
    ed.place:SetPoint("TOPLEFT", 16, -96)
    ed.placeText = Text(ed, "GameFontHighlightSmall")
    ed.placeText:SetPoint("LEFT", ed.place, "RIGHT", 4, 0)
    ed.hint = Text(ed, "GameFontDisableSmall")
    ed.hint:SetPoint("TOPLEFT", 20, -128)
    ed.hint:SetText("Press Enter to save, Esc to cancel.")
    ed.save = Btn(ed, "Save", 90, "primary", SaveNote)
    ed.save:SetPoint("BOTTOMRIGHT", -16, 14)
    ed.cancel = Btn(ed, "Cancel", 90, "secondary", function() ed:Hide() end)
    ed.cancel:SetPoint("RIGHT", ed.save, "LEFT", -8, 0)
    ed:Hide()
end

-- entry: the note being changed, or nil to write a new one.
local function OpenEditor(entry)
    if not ed then BuildEditor() end
    editingId = entry and entry.id or nil
    ed.title:SetText(entry and "Edit note" or "Write a note")
    ed.box:SetText(entry and entry.note or "")
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
local function AskDelete(entry)
    local what = entry.kind == "note" and "this note" or "this entry"
    StaticPopupDialogs.TWICHUI_CHRONICLE_DELETE = {
        text = "Delete " .. what .. " from your Chronicle? This can't be undone.",
        button1 = DELETE or "Delete", button2 = CANCEL,
        OnAccept = function() C.Delete(entry.id); W:Refresh() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_CHRONICLE_DELETE")
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
    S.RowArt(r)
    r.marker = S.Marker(r)
    r.when = Text(r, "GameFontDisableSmall")
    r.when:SetPoint("TOPLEFT", 32, -8)
    r.when:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    r.title = Text(r, "GameFontNormal")
    r.title:SetPoint("TOPLEFT", r.when, "BOTTOMLEFT", 0, -3)
    r.title:SetWidth(ROW_W - 38)
    r.title:SetWordWrap(true)
    r.title:SetTextColor(K.text[1], K.text[2], K.text[3])
    r.note = Text(r, "GameFontHighlightSmall")
    r.note:SetWidth(ROW_W - 38)
    r.note:SetTextColor(K.textDim[1], K.textDim[2], K.textDim[3])
    r.note:SetWordWrap(true)
    r.delete = S.Link(r, "Delete", function() AskDelete(r.entry) end, K.ember, K.emberHi)
    r.delete:SetPoint("TOPRIGHT", -6, -6)
    r.edit = S.Link(r, "Edit", function() OpenEditor(r.entry) end, K.gold, K.text)
    r.edit:SetPoint("RIGHT", r.delete, "LEFT", -6, 0)
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

local function Layout()
    local entries = C.Entries()
    local y, n = 0, #entries
    for i = 1, n do
        local e = entries[n - i + 1]          -- newest first
        local r = Row(i)
        r.entry = e
        local isNote = e.kind == "note"
        S.SetMarker(r.marker, e.kind, e.icon)
        local where = e.zone and ("  " .. GREY .. "·|r  " .. Escape(e.zone)) or ""
        r.when:SetText((isNote and "Note  " .. GREY .. "·|r  " or "") .. When(e.t) .. where)
        r.title:SetText(Escape(isNote and (e.note or e.title) or e.title))
        local h = 10 + 12 + 3 + (r.title:GetStringHeight() or 14) + 12
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
    for i = n + 1, #rows do rows[i].entry = nil; rows[i]:Hide() end
    f.content:SetHeight(math.max(y, 1))
    return n
end

-- One quiet line under the title; the details are in its tooltip.
local function Status()
    if not R:Enabled("chronicle") then
        return "Only the notes you write are kept.",
            "Automatic tracking is off. Only the notes you write are added. Turn it on in the options if you'd like TwichUI to keep a few moments for you."
    end
    local parts = {}
    if R:Enabled("chronicleLevels") then parts[#parts + 1] = "levels" end
    if R:Enabled("chronicleZones") then parts[#parts + 1] = "new zones" end
    if R:Enabled("chronicleGold") then parts[#parts + 1] = "gold earned" end
    if R:Enabled("chronicleRiding") then parts[#parts + 1] = "riding" end
    if R:Enabled("chronicleProfessions") then parts[#parts + 1] = "professions" end
    if R:Enabled("chronicleBosses") then parts[#parts + 1] = "defeated encounters" end
    local what = #parts > 0 and table.concat(parts, ", ") or "nothing yet (pick what to keep in the options)"
    return "Recording your chosen moments from this day forward.",
        "Keeping automatically: " .. what .. ". Only things from when tracking began are added."
end

-- "Journey time: 3d 7h 24m", or a dash until the game has answered.
local function ShowPlayed(total)
    if not f or not f:IsShown() then return end
    f.played:SetText("Journey time: " .. (C.FormatDuration(total) or "\226\128\148"))
end

W.ShowPlayed = ShowPlayed

-- Asks for the total played time; only when the window opens (and, through the recorder, after a level-up).
local function RequestPlayed()
    f.played:SetText("Journey time: \226\128\148")
    if R.ChronicleRecorder and R.ChronicleRecorder.RequestPlayed then
        R.ChronicleRecorder.RequestPlayed(ShowPlayed)
    end
end

function W:Refresh()
    if not f or not f:IsShown() then return end
    local n = Layout()
    f.sub:SetText(("%s  %s·  %d %s|r"):format(Escape(C.CharKey()), GREY, n, n == 1 and "entry" or "entries"))
    f.status:SetText((Status()))
    f.empty:SetShown(n == 0)
end

local function Build()
    f = Window("TwichUIChronicle", WIDTH, HEIGHT, "Journey Chronicle", 56)
    f.sub = Text(f, "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 18, -36)
    f.sub:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    f.played = Text(f, "GameFontDisableSmall")
    f.played:SetPoint("TOPRIGHT", -40, -39)
    f.played:SetJustifyH("RIGHT")
    f.played:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    f.played:SetText("Journey time: \226\128\148")
    f.status = Text(f, "GameFontDisableSmall")
    f.status:SetPoint("TOPLEFT", 18, -66)
    f.status:SetWidth(LIST_W)
    f.status:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    f.statusHit = CreateFrame("Frame", nil, f)
    f.statusHit:SetPoint("TOPLEFT", f.status, "TOPLEFT", 0, 2)
    f.statusHit:SetPoint("BOTTOMRIGHT", f.status, "BOTTOMRIGHT", 0, -2)
    f.statusHit:EnableMouse(true)
    f.statusHit:SetScript("OnEnter", function(self)
        local _, detail = Status()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(detail, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.statusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -90)
    box:SetPoint("BOTTOMRIGHT", -16, 76)
    S.Well(box, LIST_W, HEIGHT - 90 - 76)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(ROW_W, 1)
    scroll:SetScrollChild(f.content)
    S.ScrollBar(scroll)

    f.empty = Text(box, "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(LIST_W - 80)
    f.empty:SetJustifyH("CENTER")
    f.empty:SetTextColor(K.stone[1], K.stone[2], K.stone[3])
    f.empty:SetText("Your Chronicle is empty.\n\nIt fills as you write notes, or as you turn on automatic tracking in the options. Nothing from before is added.")

    f.new = Btn(f, "Write a note", 120, "primary", function() OpenEditor(nil) end)
    f.new:SetPoint("BOTTOMLEFT", 16, 40)
    f.options = Btn(f, "Options", 90, "secondary", function()
        if SettingsPanel and R.OpenSettings then f:Hide(); R:OpenSettings() end
    end)
    f.options:SetPoint("BOTTOMRIGHT", -16, 40)
    f.foot = Text(f, "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 18, 14)
    f.foot:SetWidth(LIST_W - 4)
    f.foot:SetTextColor(K.stone[1] * 0.85, K.stone[2] * 0.85, K.stone[3] * 0.85)
    f.foot:SetText(("Kept on this character only. Up to %d entries: when full, the oldest automatic entries go first; your notes are never removed for you."):format(C.MAX_ENTRIES))
    -- OnShow runs once per opening, not on refreshes: the sound and the played-time request belong here.
    f:SetScript("OnShow", function()
        if R:Enabled("chronicleSound") and PlaySound and SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then
            PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        end
        RequestPlayed()
        W:Refresh()
    end)
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
