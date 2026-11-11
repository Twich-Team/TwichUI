-- TwichUI settings: Reminders (reminders/). A feature card with the switch, then a frame of this window's own: your
-- reminders as a list (each with a thumbnail, its rule as a sentence, what it is doing now and its own switch), ways to
-- start one, and the chosen reminder's editor (RemindersEditor.lua: Show, When (RemindersDesigner.lua, in RemindersPlain.lua's
-- words), Placement, Test; the live preview is RemindersPreview.lua's frame beside the window). Built the
-- first time the page is shown; list rows are made as they are first needed and reused on every redraw. Which reminder
-- is open, and which situations the Test section tries, are kept for the session only.
-- Every change goes through reminders/Config.lua's own functions, which check it. Nothing here is needed for reminders
-- to work, and nothing here equips, uses or casts anything.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.RemindersPage = P

local W_MIN = 644            -- the settings window's content width at its first size
local W = W_MIN              -- the width the window gives this frame now (FitWidth): the list and the name panel follow it
local PAD, GAP = 12, 9
local ROW_H, THUMB = 66, 30
local LIST_H, LIST_SCROLLBAR = 420, 8
local LIST_W, EDIT_MIN = 220, 415
local EDIT_ORDER = { 1, 2, 4, 3, 5 }
local listWidth, editWidth, editorX = W_MIN, W_MIN, 0

local f, built
local rows = {}
local sections
local selected               -- the reminder open in the editor (this session only)
local height = 420           -- what the window gives this frame (P.Height); follows the content
local queued, relayoutQueued = false, false
local editorEpoch = 0

-- A reminder's state in a word or two, for its list row (the words carry the meaning; the color only agrees).
local SHORT = {
    showing = "Showing", holding = "Showing", hidden = "Hidden", disabled = "Off", notApplicable = "Not for this character",
    waiting = "Waiting", pending = "Waiting out its delay", invalid = "Needs attention", off = "Reminders off", world = "Waiting",
}

local function Wg() return R.SettingsWidgets end
local function Mat() return R.SettingsMaterial end   -- the settings window's leather and bronze (Material.lua)
local function RM() return R.Reminders end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or (tone == "quiet" and pal.stone or pal.textDim)))
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

---------------------------------------------------------------------------
-- Redrawing: many changes at once are one redraw; a change of height asks the window to place things again
---------------------------------------------------------------------------
function P.EditorActive()
    local UI = R.SettingsUI
    return f ~= nil and f:IsVisible() and not (R.RemindersPlacement and R.RemindersPlacement.Active()) and UI ~= nil and UI.IsPageActive("reminders")
end

function P.QueueRefresh(delay)
    if not P.EditorActive() then return end
    if queued then return end
    queued = true
    local epoch = editorEpoch
    C_Timer.After(delay or 0, function()
        if epoch ~= editorEpoch then return end
        queued = false
        P.Refresh()
    end)
end

local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    local epoch = editorEpoch
    C_Timer.After(0, function()
        if epoch ~= editorEpoch then return end
        relayoutQueued = false
        local UI = R.SettingsUI
        if P.EditorActive() and UI.Refresh then UI.Refresh() end
    end)
end

function P.Height() return height end

-- The line under the chosen reminder's name: what just happened, or why it didn't.
function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if R.RemindersDesigner then R.RemindersDesigner.Say(text, tone) end
    if f and f.say then
        f.say:SetText(text or "")
        Tone(f.say, tone)
    end
    P.QueueRefresh()
end

function P.Selected() return selected end
-- What has been built, read only (for the tests): the list rows and the editor's sections.
function P.Parts() return { frame = f, rows = rows, sections = sections } end
function P.ListAnchor()
    return f and editorX > 0 and f.list and f.list:IsVisible() and f.list or nil
end
function P.Select(id)
    local designer = R.RemindersDesigner
    if selected ~= id and designer and designer.Shown() and designer.HasUnsaved() then
        designer.RequestClose(function() P.Select(id) end)
        return
    end
    if selected ~= id and R.RemindersEditor then R.RemindersEditor.ClearReveal() end
    selected = id
    P.lastSaid = nil
    P.QueueRefresh()
end

-- A new reminder from a template, opened in the editor. It starts turned off.
function P.Create(kind)
    local ok, id = RM().Create(kind)
    if not ok then P.Say(id, "warn") return false, id end
    R.RemindersEditor.ClearReveal()
    selected = id
    local v = RM().Get(id)
    P.Say(("Made \"%s\". It stays off until you turn it on%s."):format(v.name, v.valid and "" or ", once what is listed below is done"), "ok")
    return true, id
end

-- A problem as the player reads it: one that is only a limit of this client ("Condition 2: this game client doesn't say
-- whether...") is said in its short form ("Cannot check ammunition on this client."), the rest as Config.lua words them.
local function Friendly(v, problem)
    local label = problem:match("^Condition ([%d%.]+): ")
    local Pl = R.RemindersPlain
    if label and Pl then
        for _, e in ipairs(v.leaves) do
            if table.concat(e.path, ".") == label then
                local short = Pl.Capability(e)
                if short then return short end
            end
        end
    end
    return problem
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local Delete
local function Duplicate(id)
    local ok, copy = RM().Duplicate(id)
    if not ok then P.Say(copy, "warn"); return end
    P.Select(copy)
    P.Say("Made an independent copy. It starts off.", "ok")
end

local function Row(i)
    if rows[i] then return rows[i] end
    local G = Wg()
    local row = CreateFrame("Button", nil, f.listRows)
    row:SetSize(listWidth - 14 - LIST_SCROLLBAR, ROW_H)
    Mat().ReminderRow(row)
    Mat().MaterialHover(row)
    row.thumb = row:CreateTexture(nil, "ARTWORK")
    row.thumb:SetPoint("CENTER", row, "LEFT", 8 + THUMB / 2, 0)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 12 + THUMB, -6)
    Mat().ReminderFont(row.name, 13, true)
    row.name:SetWidth(330)
    row.name:SetWordWrap(true)
    row.name:SetMaxLines(2)
    R.Interact.Tip(row, "Reminder", function() return row.name:GetText() .. "\n" .. (row.ruleText or "") end)
    row.check = Mat().Pill(row, function(on)
        if not row.id then return end
        local ok, why = RM().SetEnabled(row.id, on)
        if not ok then
            selected = row.id
            P.Say(why, "warn")
        end
    end, true)
    row.check:SetPoint("BOTTOMRIGHT", -5, 6)
    R.Interact.Tip(row.check, "Turned on", function()
        local v = row.id and RM().Get(row.id)
        if v and not v.valid then return "Turns this reminder on or off.", "It can't be turned on yet: " .. (v.problems[1] or "") end
        return "Turns this reminder on or off. Off, it never shows and reads nothing; on, it shows while its conditions are true."
    end)
    row.state = G.Text(row, "small")
    row.state:SetPoint("BOTTOMLEFT", 12 + THUMB, 8)
    row.state:SetWidth(74)
    row.state:SetWordWrap(false)
    row.state:SetJustifyH("LEFT")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(_, button)
        if not row.id then return end
        if button == "RightButton" then
            local id = row.id -- actions belong to the invoked row, even if selection changes
            G.ContextMenu(row, { { value = "copy", label = "Duplicate" }, { value = "delete", label = "Delete…" } }, function(action)
                if action == "copy" then Duplicate(id) elseif action == "delete" then Delete(id) end
            end)
        else G.CloseMenu(); P.Select(row.id) end
    end)
    rows[i] = row
    return row
end

local function LayoutList(list, y)
    local G = Wg()
    local CT, E = R.ReminderController, R.ReminderEval
    local card = f.list
    local h = 12
    f.count:SetText(("%d of %d reminders"):format(#list, RM().MAX))
    Put(f.newButton, card, listWidth - PAD - 60, 9)
    h = h + 28
    if not RM().Writable() then
        f.newer:SetText(RM().PROBLEM.newer)
        Tone(f.newer, "warn")
        Put(f.newer, card, PAD, h)
        h = h + (f.newer:GetStringHeight() or 12) + 8
    else
        f.newer:Hide()
    end
    if #list == 0 then
        f.empty:SetText("No reminders yet. Choose New reminder to start with a template. Each starts off.")
        Put(f.empty, card, PAD, h)
        h = h + (f.empty:GetStringHeight() or 24) + 10
    else
        f.empty:Hide()
    end
    f.listScroll:ClearAllPoints()
    f.listScroll:SetPoint("TOPLEFT", card, "TOPLEFT", 7, -h)
    f.listScroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -(7 + LIST_SCROLLBAR), 28)
    f.listScroll:SetShown(#list > 0)
    local rowY, selectedY = 0
    for i, v in ipairs(list) do
        local row = Row(i)
        row.id = v.id
        R.RemindersEditor.Thumb(row.thumb, v.display, THUMB)
        row.name:SetText(v.name)
        local status = CT.Status(v.id)
        row.ruleText = v.valid and E.RuleSentence(v) or (v.problems[1] and Friendly(v, v.problems[1]) or "")
        row.name:SetWidth(listWidth - 14 - LIST_SCROLLBAR - THUMB - 16)
        row.state:SetText(SHORT[status] or "")
        Tone(row.state, (status == "showing" or status == "holding") and "ok" or (status == "invalid" and "warn" or "quiet"))
        row.check:SetChecked(v.enabled)
        row.check:SetActive(RM().Writable())
        local isSel = v.id == selected
        row.sel:SetShown(isSel)
        G.Color(row.name, isSel and G.pal.text or G.pal.textDim)
        Put(row, f.listRows, 0, rowY)
        if isSel then selectedY = rowY end
        rowY = rowY + ROW_H + 3
    end
    for i = #list + 1, #rows do
        rows[i].id = nil
        rows[i]:Hide()
    end
    local height = #list > 0 and math.max(h + 106, LIST_H) or h + 35
    if editorX == 0 then height = math.min(height, 214) end
    card:SetHeight(height)
    f.listRows:SetHeight(math.max(1, rowY))
    if f.fitListRail then f.fitListRail(math.max(1, rowY)) end
    local visible = math.max(1, height - h - 28)
    if f.lastListSelection ~= selected and selectedY then
        local scroll = f.listScroll:GetVerticalScroll() or 0
        if selectedY < scroll then scroll = selectedY
        elseif selectedY + ROW_H > scroll + visible then scroll = selectedY + ROW_H - visible end
        f.listScroll:SetVerticalScroll(math.max(0, math.min(scroll, rowY - visible)))
    end
    f.lastListSelection = selected
    Put(card, f, 0, y)
    return height
end

---------------------------------------------------------------------------
-- The chosen reminder's head: its name, its switch, copy and delete, and what is wrong with it
---------------------------------------------------------------------------
Delete = function(id)
    local v = RM().Get(id)
    if not v then return end
    local text = ("Delete the reminder \"%s\"?\n\nOnly this reminder is removed (it is taken off the screen at once). Your other reminders and settings are not changed. This can't be undone."):format(v.name)
    R.Interact.Confirm("TWICHUI_REMINDER_DELETE", text, function()
        local ok, why = RM().Delete(id)
        if ok then
            if selected == id then selected = nil end
            P.Say(("Deleted \"%s\"."):format(v.name), "ok")
        else
            P.Say(why, "warn")
        end
    end, { accept = DELETE or "Delete", valid = function()
        if RM().Get(id) then return true end
        return false, "That reminder is already gone, so nothing was deleted."
    end })
end

local function LayoutHead(v, y)
    local head = f.head
    local h = 12
    if not f.nameBox:HasFocus() then f.nameBox:SetText(v.name) end
    f.nameBox:SetWidth(editWidth - 150)
    Put(f.nameBox, head, PAD, h)
    f.onBox:SetChecked(v.enabled)
    f.onBox:SetActive(RM().Writable() and not v.broken)
    f.onText:SetText(v.enabled and "On" or (v.valid and "Off" or "Off (not ready)"))
    Tone(f.onText, v.enabled and "ok" or "quiet")
    Put(f.onBox, head, editWidth - 122, h + 2)
    Put(f.onText, head, editWidth - 74, h + 6)
    h = h + 32
    Put(f.place, head, PAD, h)
    f.previewBox:SetChecked(R.RemindersPreview.Enabled())
    Put(f.previewBox, head, editWidth - PAD - 34, h + 3)
    Put(f.previewLabel, head, editWidth - PAD - 120, h + 5)
    h = h + 32
    if #v.problems > 0 then
        local reason = Friendly(v, v.problems[1])
        if v.problems[1]:find("has no conditions in it", 1, true) then reason = "Complete the empty condition group" end
        f.problems:SetText("Needs attention · " .. reason:gsub("^Condition [%d%.]+: ", ""))
        local ruleProblem = v.problems[1]:match("^Condition ") or v.problems[1]:match("^Group ")
        f.problems:SetWidth(editWidth - PAD * 2 - (ruleProblem and 132 or 0))
        f.fix:SetShown(ruleProblem ~= nil)
        if ruleProblem then Put(f.fix, head, editWidth - PAD - 126, h - 3) end
        Tone(f.problems, "warn")
        Put(f.problems, head, PAD, h)
        h = h + math.max(f.problems:GetStringHeight() or 12, ruleProblem and 24 or 0) + 6
    else
        f.problems:Hide()
        f.fix:Hide()
    end
    if P.lastSaid and P.lastTone == "warn" and not R.RemindersDesigner.Shown() then
        f.say:SetText(P.lastSaid)
        Tone(f.say, P.lastTone)
        Put(f.say, head, PAD, h)
        h = h + (f.say:GetStringHeight() or 12) + 8
    else
        f.say:Hide()
    end
    h = h + 4
    head:SetHeight(h)
    Put(head, f.editor, 0, y)
    return h
end

---------------------------------------------------------------------------
-- Building and drawing
---------------------------------------------------------------------------
local function Build()
    built = true
    local G = Wg()
    local I = R.Interact

    -- your reminders, and ways to start one
    f.list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.list:SetWidth(W)
    Mat().PanelFace(f.list, "espresso")
    f.listScroll, f.listRows = G.Scroll(f.list, listWidth - 14 - LIST_SCROLLBAR)
    f.fitListRail = Mat().ScrollRail(f.listScroll)
    f.listTitle = G.Text(f.list, "heading")
    f.listTitle:SetPoint("TOPLEFT", PAD, -14)
    f.listTitle:SetText("Your reminders")
    Mat().ReminderFont(f.listTitle, 14, true)
    f.listTitle:SetWidth(112)
    f.count = G.Text(f.list, "meta")
    f.count:SetPoint("BOTTOMLEFT", PAD, 9)
    f.count:SetJustifyH("RIGHT")
    f.newButton = G.Button(f.list, "+ New", 60, "primary", function()
        if R.RemindersCatalog then R.RemindersCatalog.Toggle() end
    end)
    I.Tip(f.newButton, "New reminder", "Opens the templates beside this window. A new reminder starts turned off, so nothing appears until you say so.")
    Mat().ReminderControl(f.newButton, "primary")
    f.newer = G.Text(f.list, "small")
    f.newer:SetWidth(W - PAD * 2)
    f.empty = G.Text(f.list, "small")
    f.empty:SetWidth(W - PAD * 2)

    f.editor = CreateFrame("Frame", nil, f)
    f.editor:SetSize(W, 1)

    -- the chosen one's head
    f.head = CreateFrame("Frame", nil, f.editor, "BackdropTemplate")
    f.head:SetWidth(W)
    Mat().PanelFace(f.head, "walnut")
    f.nameBox = G.EditBox(f.head, 250, 22)
    f.nameBox:SetMaxLetters(RM().NAME_MAX * 4)
    local function SaveName(self)
        if not selected then return end
        local ok, why = RM().SetName(selected, self:GetText())
        if not ok then
            self:SetText(RM().Get(selected) and RM().Get(selected).name or "")
            P.Say(why, "warn")
        end
    end
    f.nameBox:SetScript("OnEnterPressed", function(self) SaveName(self); self:ClearFocus() end)
    f.nameBox:HookScript("OnEditFocusLost", SaveName)
    I.Tip(f.nameBox, "Name", "Only for you, in this list. It is never shown on screen and never sent anywhere.")
    Mat().ReminderControl(f.nameBox, "field")
    f.onBox = Mat().Pill(f.head, function(on)
        if not selected then return end
        local ok, why = RM().SetEnabled(selected, on)
        if not ok then P.Say(why, "warn") end
    end)
    I.Tip(f.onBox, "Turned on", "On, it shows while its conditions are true (Test below says what they see now). A new reminder starts off, so it never covers the world before it is ready.")
    f.onText = G.Text(f.head, "body")
    f.duplicate = G.Button(f.editor, "Duplicate", 100, "secondary", function()
        if not selected then return end
        Duplicate(selected)
    end)
    I.Tip(f.duplicate, "Duplicate", "A copy with its own identity, right after this one, turned off. Changing either never changes the other.")
    Mat().ReminderControl(f.duplicate, "secondary")
    f.delete = G.Button(f.editor, "Delete", 90, "danger", function() if selected then Delete(selected) end end)
    Mat().ReminderControl(f.delete, "danger")
    I.Tip(f.delete, "Delete", "Removes this reminder, after asking. Nothing else changes.")
    f.previewBox = Mat().Pill(f.head, function(on) R.RemindersPreview.SetEnabled(on) end, true)
    f.previewLabel = G.Text(f.head, "body")
    f.previewLabel:SetText("Live preview")
    Mat().ContextTip(f.previewBox, "Live preview", "Shows the editing companion while this page is open. This preference lasts for this session.")
    f.problems = G.Text(f.head, "small")
    f.fix = G.Button(f.head, "Edit conditions", 126, "secondary", function() R.RemindersDesigner.Open() end)
    Mat().ReminderControl(f.fix)
    f.problems:SetWidth(W - PAD * 2)
    f.say = G.Text(f.head, "small")
    f.say:SetWidth(W - PAD * 2)

    sections = R.RemindersEditor.Build(f.editor, {
        id = function() return selected end,
        view = function() return selected and RM().Get(selected) end,
        Say = P.Say,
        Changed = function() P.QueueRefresh() end,
    })
    -- Promote the existing placement control; its callback and transaction stay shared.
    f.place = sections[3].move
    f.place:SetParent(f.head)
    f.place.text:SetText("Place on screen")
end

-- The window sets this frame's width (the same the feature card above it has, scrollbar and page insets already taken off), so the
-- list and the name panel are as wide as that card at any window size. Fields keep their own size inside.
local function FitWidth()
    local w = f:GetWidth()
    W = (type(w) == "number" and w > W_MIN) and w or W_MIN
    local split = W >= LIST_W + GAP + EDIT_MIN
    listWidth = split and math.min(W - GAP - EDIT_MIN, 280, math.max(LIST_W, math.floor(W * 0.32))) or W
    editWidth = split and (W - listWidth - GAP) or W
    editorX = split and (listWidth + GAP) or 0
    f.list:SetWidth(listWidth)
    f.editor:SetWidth(editWidth)
    f.head:SetWidth(editWidth)
    f.listRows:SetWidth(listWidth - 14 - LIST_SCROLLBAR)
    f.newer:SetWidth(listWidth - PAD * 2)
    f.empty:SetWidth(listWidth - PAD * 2)
    f.problems:SetWidth(editWidth - PAD * 2)
    f.say:SetWidth(editWidth - PAD * 2)
    for _, row in ipairs(rows) do row:SetWidth(listWidth - 14 - LIST_SCROLLBAR) end
    R.RemindersEditor.FitWidth(editWidth)
end

function P.Refresh()
    if not (built and P.EditorActive()) then
        if R.RemindersPreview then R.RemindersPreview.Hide() end
        return
    end
    FitWidth()
    local list = RM().List()
    if selected and not RM().Get(selected) then selected = nil end
    if not selected and list[1] then selected = list[1].id end
    local listHeight = LayoutList(list, 0)
    local y = editorX > 0 and 0 or (listHeight + GAP)
    Put(f.editor, f, editorX, y)
    local editorTop = y
    y = 0
    local v = selected and RM().Get(selected)
    if v then
        y = y + LayoutHead(v, y) + GAP
        for _, i in ipairs(EDIT_ORDER) do
            local sectionHeight = sections[i]:Layout(v, y)
            if sectionHeight > 0 then y = y + sectionHeight + GAP end
        end
        Put(f.duplicate, f.editor, 0, y)
        Put(f.delete, f.editor, 108, y)
        y = y + 30
    else
        f.head:Hide()
        f.place:Hide()
        f.duplicate:Hide()
        f.delete:Hide()
        f.previewBox:Hide()
        f.previewLabel:Hide()
        for _, s in ipairs(sections) do s:Hide(); if s.summary then s.summary:Hide() end end
        if R.RemindersDesigner and R.RemindersDesigner.Shown() then R.RemindersDesigner.Close() end
    end
    f.editor:SetHeight(math.max(1, y))
    if v and editorX > 0 then
        -- Align the list well with the primary editing stack, without following a long diagnostics expansion.
        listHeight = math.max(listHeight, math.min(560, y - 30 - GAP))
        f.list:SetHeight(listHeight)
    end
    -- the live preview beside the window, unless another companion has that place
    local PV = R.RemindersPreview
    if PV then
        local catalog = R.RemindersCatalog
        if catalog and catalog.Shown() then
            PV.Hide()
            PV.Place(catalog.Frame())
        elseif v
            and not (R.RemindersDesigner and R.RemindersDesigner.Shown()) then
            PV.Show(v, { Changed = P.QueueRefresh, Say = P.Say, Reveal = R.RemindersEditor.Reveal })
        else
            PV.Hide()
        end
    end
    local h = math.max(listHeight, editorTop + y - GAP, 1)
    f:SetHeight(h)
    if h ~= height then
        height = h
        QueueRelayout()
    end
end

-- Only while the page is shown: the game telling of changes the Test section's "Right now" reads (for a reminder that
-- isn't running it is read when drawn), and answers about items named here.
local EVENTS = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
    "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_UPDATE_RESTING", "ZONE_CHANGED_NEW_AREA",
    "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }

-- The page's frame (the settings window shows it under the Reminders card). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:SetWidth(W)
    f:Hide()
    f:SetScript("OnSizeChanged", function(_, w) if built and type(w) == "number" and w ~= W then P.QueueRefresh() end end)
    f:SetScript("OnShow", function(self)
        if not built then Build() end
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh()
    end)
    f:SetScript("OnHide", function(self)
        if R.RemindersPlacement and R.RemindersPlacement.Active() then return end
        editorEpoch = editorEpoch + 1
        queued, relayoutQueued = false, false
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
        if f.nameBox then f.nameBox:ClearFocus() end
        if R.RemindersCatalog then R.RemindersCatalog.Hide() end   -- the templates and the preview belong to this page
        if R.RemindersPreview then R.RemindersPreview.Hide() end
        if R.ReminderDisplay then R.ReminderDisplay.PreviewStop() end
        if R.RemindersEditor then R.RemindersEditor.ClearReveal() end
        if R.RemindersPreview then R.RemindersPreview.RestoreAnchor() end
        if R.RemindersDesigner then R.RemindersDesigner.Reset() end   -- an open editor, picker or undo is put away
    end)
    f:SetScript("OnEvent", function() P.QueueRefresh(0.2) end)
    return f
end

if R.OnSettingsClosed then R.OnSettingsClosed(function()
    editorEpoch = editorEpoch + 1
    queued, relayoutQueued = false, false
    if R.RemindersPreview then R.RemindersPreview.Hide() end
end) end

-- A change made anywhere (here, a profile change, a decision of the live reminders) redraws the page if it is shown.
-- Registered once: this file is loaded once a session.
if R.Reminders then R.Reminders.Subscribe(function() P.QueueRefresh() end) end
if R.ReminderController then R.ReminderController.OnChange(function() P.QueueRefresh(0.05) end) end

local function Count()
    local n, on = 0, 0
    for _, v in ipairs(R.Reminders.List()) do
        n = n + 1
        if v.enabled then on = on + 1 end
    end
    return n, on
end

K.Page({
    key = "reminders", icon = "reminders", name = "Reminders", order = 22, group = "everyday",
    description = "", compact = true, materialHeader = true,
    keywords = "reminder reminders shield equip equipment gear off hand offhand main hand weapon two-handed fishing pole item missing artwork icon picture words text alert notice condition conditions rule rules when combat dead ghost alive mounted mount resting rested inn city dungeon raid instance preview test simulate simulation position move character class ammo ammunition arrows bullets quiver ranged bow gun crossbow hunter out of ammo no ammo wrong ammo talent talents specialization spec tree weapon oil wizard oil mana oil sharpening stone weightstone poison enchant enchantment imbue temporary well fed food buff eat sound sounds alert audio play",
    overview = {
        label = "Reminders", tip = "Artwork, an icon or words on screen while conditions you choose are true, such as a missing shield.",
        when = function() return R.Reminders ~= nil end,
        status = function()
            if not R:Enabled("reminders") then return K.OnOff(false) end
            local n, on = Count()
            if n == 0 then return K.OnOff(false, nil, "None yet") end
            return K.OnOff(on > 0, ("%d of %d on"):format(on, n), ("%d, none on"):format(n))
        end,
    },
    when = function() return R.Reminders ~= nil and R.ReminderController ~= nil and R.RemindersEditor ~= nil and R.RemindersDesigner ~= nil and R.RemindersPlain ~= nil end,
    build = function()
        K.Card({
            title = "Reminders", icon = "reminders", compact = true, inPageHeader = true,
            switchLabels = { "Enabled", "Disabled" },
            what = "Shows artwork, an icon or a few words while conditions you choose are true, such as an empty off hand, and hides it the rest of the time.",
            help = "Choose a template or start from scratch. Set its appearance, edit its conditions, then turn it on.",
        })
        K.Toggle("reminders", "Show my reminders",
            "On: each reminder you turned on appears while its conditions are true. Off: none appears and nothing is listened for. Your reminders are kept either way.")
    end,
    host = function() return P.Frame() end, hostAfter = "Reminders", hostHeight = function() return P.Height() end,
})
