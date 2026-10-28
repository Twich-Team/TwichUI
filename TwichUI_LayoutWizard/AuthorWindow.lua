-- TwichUI Layout Setup: the authoring workspace's window (docs/layouts/publishing.md)
-- For the person who makes a layout: start from a package, capture two profiles, review what changed, choose where each change
-- lives, check the result as a recipient will, publish an unchangeable snapshot and send it. It is a maintenance tool, not part
-- of the setup wizard: nothing in the wizard links to it, and it opens with /tui layout author.
--
-- One window, built the first time it is opened and kept, drawn from the model (Author.lua) every time it is shown. A fixed
-- number of rows and widgets is made at the start; showing it again re-writes their texts and makes nothing new. It listens
-- to nothing while closed (the sharing status listener is added once and does nothing unless the window is shown). Closing it
-- drops the session: the capture and the changes. The published packages are kept (Store.lua), and nothing is sent unless the
-- Send button is pressed and the question it asks is answered.
--
--   AuthorWindow.Open(), Close(), Toggle(), IsShown(), Refresh()

local R = TwichUI
local LY = R.Layouts
local WZ = R.LayoutWizard
local A = WZ.Author
local AW = {}
WZ.AuthorWindow = AW

local FRAME_NAME = "TwichUILayoutAuthor"
local WIDTH, HEIGHT = 780, 640
local HEADER_H, PAD, FOOTER_H = 44, 16, 40
local CONTENT_W = WIDTH - 2 * PAD - 22
local ROWS = 8

local win, scroll, content, footer
local w = {}                       -- the widgets, by name
AW.frames = 0
AW.builds = 0
AW.page = 1
AW.pool = w

local function Look() return R.Look end
local function Say(fmt, ...) R.Print("layout publishing: " .. fmt, ...) end
function AW.IsShown() return win ~= nil and win:IsShown() end

local function Height(o)
    local h = o.GetStringHeight and o:GetStringHeight() or o:GetHeight()
    return (type(h) == "number" and h > 0) and h or 14
end

local function Text(parent, kind, width)
    local fs = Look().Text(parent, kind or "body")
    if width then fs:SetWidth(width) end
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    AW.frames = AW.frames + 1
    return fs
end

local function Button(parent, label, width, kind, fn, tip)
    local b = Look().Button(parent, label, width, kind, fn)
    b:SetHeight(22)
    if tip then R.Interact.Tip(b, label, tip) end
    AW.frames = AW.frames + 1
    return b
end

local function Edit(parent, width, onCommit)
    local eb = Look().EditBox(parent, width, 22)
    eb:HookScript("OnEditFocusLost", function(self) onCommit(self:GetText()) end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    AW.frames = AW.frames + 1
    return eb
end

local function Place(obj, x, y)
    obj:ClearAllPoints()
    obj:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
end

local CAPTURE_WHY = {
    ["no-source"] = "Choose at least one profile to capture.",
    ["no-eui-profile"] = "EllesmereUI doesn't have a profile with that name now.",
    ["no-twichui-profile"] = "TwichUI doesn't have a profile with that name now.",
    personal = "The capture holds something that looks personal (a character's name, a link). Nothing was kept.",
    closed = "The workspace isn't open.",
}
local PUBLISH_WHY = {
    blocked = "Check first: something is blocking it.", busy = "Already publishing.", invalid = "The package didn't pass its checks.",
    ["too-large"] = "The package is larger than TwichUI sends.", full = "There is no room to keep another published package. Remove one first.",
    ["pack-failed"] = "TwichUI couldn't pack the package.", ["bad-entry"] = "TwichUI couldn't keep the package.",
}
local RELEASE_WHY = {
    ["bad-id"] = "A package id is lower-case letters, digits and single hyphens, starting with a letter.",
    ["bad-title"] = "The title is plain text of at most 80 characters.", ["bad-revision"] = "The revision is a whole number from 1.",
    ["bad-notes"] = "Release notes are plain text: at most 600 characters, 12 lines.",
    ["bad-publisher"] = "The label is plain text of at most 40 characters.",
}

---------------------------------------------------------------------------
-- Cyclers: a name with arrows, over a list
---------------------------------------------------------------------------
local function Cycle(list, current, step)
    if #list == 0 then return nil end
    local at = 0
    for i, n in ipairs(list) do if n == current then at = i end end
    return list[((at - 1 + step) % #list) + 1]
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Section(name, text, y)
    local h = w[name]
    h:SetText(text)
    Place(h, 0, y)
    return y + Height(h) + 6
end

local function Refresh()
    local s = A.Session()
    if not win or not s then return end
    local y = 4

    -- 1. start from
    y = Section("h1", "1. Start from", y)
    local bases = A.Bases()
    for i, tab in ipairs(w.baseTabs) do
        local b = bases[i]
        tab:SetShown(b ~= nil)
        if b then
            tab.text:SetText(("%s, rev %d"):format(b.kind == "bundled" and "Included" or b.title, b.revision))
            tab:SetSelected(b.key == s.baseKey)
            tab:SetScript("OnClick", function()
                local ok = A.SetBase(b.key, function() AW.Refresh() end)
                if ok then AW.Refresh() end
            end)
            Place(tab, (i - 1) * 150, y)
        end
    end
    y = y + 30
    local variants = A.Variants()
    w.layoutLabel:SetText("Layout being edited:")
    Place(w.layoutLabel, 0, y + 4)
    for i, tab in ipairs(w.variantTabs) do
        local v = variants[i]
        tab:SetShown(v ~= nil)
        if v then
            tab.text:SetText(v.title)
            tab:SetSelected(v.id == s.variant)
            tab:SetScript("OnClick", function() A.SetVariant(v.id) AW.Refresh() end)
            Place(tab, 150 + (i - 1) * 170, y)
        end
    end
    y = y + 36

    -- 2. capture
    y = Section("h2", "2. Capture", y)
    w.captureNote:SetText("The two profiles are only read: nothing is written to them, switched or renamed. What is kept is decided by the layout adapters' own lists, the same ones the offline capture tool uses.")
    Place(w.captureNote, 0, y)
    y = y + Height(w.captureNote) + 8
    local eui, tw = A.EuiProfiles(), A.TwichProfiles()
    w.euiLabel:SetText("EllesmereUI profile")
    Place(w.euiLabel, 0, y + 4)
    Place(w.euiPrev, 170, y)
    w.euiName:SetText(#eui > 0 and (s.eui or "(none chosen)") or "EllesmereUI isn't available")
    Place(w.euiName, 200, y + 4)
    Place(w.euiNext, 440, y)
    w.euiPrev:SetShown(#eui > 0)
    w.euiNext:SetShown(#eui > 0)
    y = y + 28
    w.twLabel:SetText("TwichUI profile")
    Place(w.twLabel, 0, y + 4)
    Place(w.twPrev, 170, y)
    w.twName:SetText(#tw > 0 and (s.twichui or "(none chosen)") or "No profiles available")
    Place(w.twName, 200, y + 4)
    Place(w.twNext, 440, y)
    w.twPrev:SetShown(#tw > 0)
    w.twNext:SetShown(#tw > 0)
    y = y + 30
    Place(w.captureBtn, 0, y)
    local status
    if s.captureError then status = CAPTURE_WHY[s.captureError]
    elseif s.capture then
        local c = A.Counts()
        status = ("Captured. %d %s differ from the starting package: %d changed, %d added, %d removed, %d back at TwichUI's default.%s"):format(
            #s.items, #s.items == 1 and "setting" or "settings", c.changed, c.added, c.removed, c.default,
            s.capture.client == "other" and " (EllesmereUI here is not the WoW: Forever build.)" or "")
    else status = "Nothing captured yet." end
    w.captureStatus:SetText(status)
    Place(w.captureStatus, 110, y + 4)
    y = y + 34

    -- 3. changes
    y = Section("h3", "3. Review the changes", y)
    local items = s.items
    if not items then
        w.summary:SetText("Capture first. The changes appear here, each one with its old and new value, and you choose which to include and where each one lives.")
    else
        local c = A.Counts()
        w.summary:SetText(("%d included: %d only in this layout, %d shared by every layout in the package. A change you leave out is not published. Removed settings start out left out."):format(c.included, c.own, c.shared))
    end
    Place(w.summary, 0, y)
    y = y + Height(w.summary) + 6
    local pages = items and math.max(1, math.ceil(#items / ROWS)) or 1
    if AW.page > pages then AW.page = pages end
    for i, row in ipairs(w.rows) do
        local it = items and items[(AW.page - 1) * ROWS + i]
        row.frame:SetShown(it ~= nil)
        if it then
            row.it = it
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row.check:SetChecked(it.include)
            row.label:SetText(("%s  [%s%s]"):format(it.label, it.kind, it.lives and (", now in " .. (it.lives == "base" and "the shared base" or "this layout")) or ""))
            row.detail:SetText(it.text)
            row.target.text:SetText(it.to == "base" and "Shared" or "This layout only")
            row.target:SetEnabled(it.include and not it.baseOnly)
            -- a setting the profile leaves at its default: what players who have the layout get, chosen, never assumed
            row.how:SetShown(it.canReset == true)
            row.how.text:SetText(it.how == "release" and "Stop managing" or "Reset to default")
            row.how:SetEnabled(it.include and it.canReset == true)
            local lines = {}
            if it.include then
                for _, e in ipairs(A.Effects(it.id) or {}) do
                    lines[#lines + 1] = ("%s: %s (%s)"):format(e.title, e.change == "gets" and "gets the new value" or "unchanged", e.why)
                end
            end
            if it.baseOnly then lines[#lines + 1] = it.rootOnly and "This kind of setting only lives in the shared base." or "Only the shared base can stop naming it." end
            if it.canReset then
                lines[#lines + 1] = not it.include and "Left out: players keep getting the layout's current value."
                    or it.how == "release" and "Stop managing: players who have the layout keep what they have; new players get TwichUI's default."
                    or "Reset to default: players who have the layout go back to TwichUI's default, unless they changed it themselves. Needs a TwichUI that reads package format 4."
            end
            row.effects:SetText(table.concat(lines, "\n"))
            row.frame:SetHeight(math.max(48, 6 + Height(row.label) + 2 + Height(row.detail) + (#lines > 0 and (2 + Height(row.effects)) or 0) + 4))
            y = y + row.frame:GetHeight() + 4
        end
    end
    w.pageLabel:SetText(("Page %d of %d"):format(AW.page, pages))
    w.pagePrev:SetEnabled(AW.page > 1)
    w.pageNext:SetEnabled(AW.page < pages)
    w.pagePrev:SetShown(items ~= nil and pages > 1)
    w.pageNext:SetShown(items ~= nil and pages > 1)
    w.pageLabel:SetShown(items ~= nil and pages > 1)
    Place(w.pagePrev, 0, y)
    Place(w.pageNext, 100, y)
    Place(w.pageLabel, 210, y + 4)
    if items and pages > 1 then y = y + 30 end
    local skipped = A.Skipped()
    if #skipped > 0 then
        w.skipped:SetText(("%d %s left alone because a wizard choice (such as the accent colour) sets %s."):format(
            #skipped, #skipped == 1 and "setting is" or "settings are", #skipped == 1 and "it" or "them"))
        w.skipped:Show()
        Place(w.skipped, 0, y)
        y = y + Height(w.skipped) + 6
    else
        w.skipped:Hide()
    end
    y = y + 6

    -- 4. check
    y = Section("h4", "4. Check it as a recipient will", y)
    Place(w.checkBtn, 0, y)
    local rep = s.report
    local lines = {}
    if rep then
        lines[#lines + 1] = rep.ok and "Ready to publish." or "Not ready:"
        for _, t in ipairs(rep.blockers) do lines[#lines + 1] = "  - " .. t end
        for _, t in ipairs(rep.warnings) do lines[#lines + 1] = "  (note) " .. t end
        for _, v in ipairs(rep.variants) do
            lines[#lines + 1] = ("%s: %s%s"):format(v.title, v.ok and "resolves" or "does not resolve", v.units and (", " .. v.units .. " settings") or "")
        end
    else lines[1] = "Press Check. It builds the package, resolves both layouts, looks at the media and scans for anything personal." end
    w.checkText:SetText(table.concat(lines, "\n"))
    Place(w.checkText, 110, y + 4)
    y = y + math.max(30, Height(w.checkText) + 8)
    local fixes = A.MediaFixes()
    local shown = 0
    for i, b in ipairs(w.fixBtns) do
        local f = fixes[i]
        b:SetShown(f ~= nil and f.replacement ~= nil)
        if f and f.replacement then
            shown = shown + 1
            b.text:SetText("Use TwichUI's copy of " .. (f.path:match("([^\\/]+)$") or f.path))
            b:SetScript("OnClick", function() A.FixMedia(f.path) AW.Refresh() end)
            Place(b, 0, y)
            y = y + 28
        end
    end
    y = y + 8

    -- 5. release
    y = Section("h5", "5. Release", y)
    local r = s.release
    local function Row(label, edit, value)
        label:Show()
        Place(label, 0, y + 4)
        Place(edit, 130, y)
        if not edit:HasFocus() then edit:SetText(value or "") end
        y = y + 28
    end
    w.idLabel:SetText("Package id")
    Row(w.idLabel, w.idEdit, r.id)
    w.titleLabel:SetText("Title")
    Row(w.titleLabel, w.titleEdit, r.title)
    w.revLabel:SetText("Revision")
    Place(w.revLabel, 0, y + 4)
    Place(w.revMinus, 130, y)
    w.revText:SetText(tostring(r.revision))
    Place(w.revText, 166, y + 4)
    Place(w.revPlus, 210, y)
    w.revNote:SetText(r.id == s.basePkg.id and ("starts from revision " .. s.basePkg.revision) or "a new package")
    Place(w.revNote, 250, y + 4)
    y = y + 28
    w.pubLabel:SetText("Labelled by")
    Row(w.pubLabel, w.publisherEdit, r.publisher)
    w.notesLabel:SetText("Release notes")
    Row(w.notesLabel, w.notesEdit, r.notes)
    w.releaseNote:SetText("The label and notes are the author's own words and are shown to recipients as such. Your character's name is not put in the package: recipients are told who sent it by the game.")
    Place(w.releaseNote, 0, y)
    y = y + Height(w.releaseNote) + 8
    Place(w.publishBtn, 0, y)
    w.publishBtn:SetEnabled(rep ~= nil and rep.ok == true and not s.publishing)
    w.publishStatus:SetText(s.publishNote or (rep and rep.ok and "Publishing keeps an unchangeable snapshot. Nothing is sent." or "Check it first."))
    Place(w.publishStatus, 150, y + 4)
    y = y + 34

    -- 6. published, and sending
    y = Section("h6", "6. Send a published package", y)
    local pub = A.Published()
    for i, row in ipairs(w.pubRows) do
        local e = pub[i]
        row.frame:SetShown(e ~= nil)
        if e then
            row.entry = e
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row.pick.text:SetText(("%s, revision %d"):format(e.title or e.id, e.revision))
            row.pick:SetSelected(s.published == e)
            row.info:SetText(("about %d KB"):format(math.max(1, math.floor(e.size / 1024 + 0.5))))
            y = y + 30
        end
    end
    if #pub == 0 then
        w.pubNone:Show()
        Place(w.pubNone, 0, y)
        y = y + 22
    else w.pubNone:Hide() end
    w.sendLabel:SetText("Send to")
    Place(w.sendLabel, 0, y + 4)
    Place(w.sendEdit, 130, y)
    Place(w.sendBtn, 345, y)
    Place(w.testBtn, 440, y)
    w.sendBtn:SetEnabled(s.published ~= nil)
    w.testBtn:SetEnabled(s.published ~= nil)
    y = y + 28
    w.sendNote:SetText("Sent the way you send setups (Direct, Party or Guild, as chosen in Sending options). They are asked first; receiving only stores it, and installing is theirs to do.")
    Place(w.sendNote, 0, y)
    y = y + Height(w.sendNote) + 4
    AW.RefreshStatus()
    Place(w.sendStatus, 0, y)
    y = y + Height(w.sendStatus) + 12

    content:SetHeight(y)
end
AW.Refresh = Refresh

function AW.RefreshStatus()
    if not (win and w.sendStatus) then return end
    local o = R.Share and R.Share.outgoing
    local text = ""
    if o and o.kind == "layout" then
        local who = R.Share.Short(o.target)
        if o.stage == "offered" then text = "Waiting for " .. who .. " to answer."
        elseif o.stage == "packing" or o.stage == "sending" then text = ("Sending to %s: %d of %d bytes handed to the game."):format(who, o.sent or 0, o.total or 0)
        elseif o.stage == "delivered" then text = "Everything is handed to the game. Waiting for " .. who .. " to confirm."
        elseif o.stage == "done" then text = who .. " has it stored."
        elseif o.stage == "failed" then text = "Not sent: " .. tostring(o.reason or o.code or "it failed") end
    end
    w.sendStatus:SetText(text)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function DoCapture()
    local ok, why = A.Capture()
    if not ok then A.Session().captureError = why end
    AW.page = 1
    Refresh()
end

local function DoPublish()
    local s = A.Session()
    local rep = A.Check()
    if not rep.ok then Refresh() return end
    local r = s.release
    R.Interact.Confirm("TWICHUI_LAYOUT_PUBLISH",
        ("Publish %q, revision %d?\n\nThis keeps an unchangeable snapshot of the package as it is now, and the checks have passed. Nothing is sent, and no profile is changed. You can send it afterwards, and later edits make a new revision instead of changing this one."):format(r.title, r.revision),
        function()
            local ok, why = A.Publish(function(done, result)
                s.publishNote = done and "Published. Choose it below to send it." or ("Not published: " .. (PUBLISH_WHY[result] or tostring(result)))
                if AW.IsShown() then Refresh() end
            end)
            if not ok then s.publishNote = "Not published: " .. (PUBLISH_WHY[why] or tostring(why)) end
            Refresh()
        end, { accept = "Publish" })
end

local function DoSend(selfTest)
    local s = A.Session()
    local e = s.published
    if not e then return end
    local name = selfTest and R.Share.SelfName() or w.sendEdit:GetText()
    local how = R.Share.TRANSPORT_LABEL[R.Share.Transport()]
    R.Interact.Confirm("TWICHUI_LAYOUT_SEND",
        ("Send %q, revision %d, to %s?\n\nIt goes by %s, the way you chose in Sending options. They are asked before anything is stored, and receiving never installs it: they choose whether to set it up. Nothing here changes any of your profiles."):format(
            e.title or e.id, e.revision, selfTest and "yourself" or tostring(name), how),
        function()
            local ok, why = A.Send(name, e, selfTest)
            if not ok then w.sendStatus:SetText("Not sent: " .. tostring(why)) end
            AW.RefreshStatus()
        end, { accept = "Send" })
end

local function DoRemove(e)
    R.Interact.Confirm("TWICHUI_LAYOUT_UNPUBLISH",
        ("Remove the published package %q, revision %d?\n\nThis deletes the stored snapshot only. Anyone you already sent it to keeps their copy, and it can't be sent again unless you publish it again."):format(e.title or e.id, e.revision),
        function() A.RemovePublished(e) Refresh() end, { accept = "Remove" })
end

local function Commit(field)
    return function(text)
        local s = A.Session()
        if not s then return end
        local ok, why = A.SetRelease(field, text)
        if not ok then s.publishNote = RELEASE_WHY[why] or tostring(why) end
        if ok then s.publishNote = nil end
        Refresh()
    end
end

---------------------------------------------------------------------------
-- Building (once)
---------------------------------------------------------------------------
local function Build()
    local L = Look()
    local pal = L.pal
    AW.builds = AW.builds + 1
    win = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    win:HookScript("OnShow", R.FitToScreen)
    local listed = false
    for _, n in ipairs(UISpecialFrames) do if n == FRAME_NAME then listed = true end end
    if not listed then tinsert(UISpecialFrames, FRAME_NAME) end
    L.Shell(win, HEADER_H)
    local title = L.Text(win, "title")
    title:SetPoint("TOPLEFT", 18, -12)
    title:SetText("Layout publishing")
    local sub = L.Text(win, "meta")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
    sub:SetText("for the person who makes a layout")
    L.CloseBox(win)

    scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", PAD, -(HEADER_H + 8))
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 22, FOOTER_H + PAD)
    L.ScrollBar(scroll)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 200)
    scroll:SetScrollChild(content)

    footer = CreateFrame("Frame", nil, win)
    footer:SetPoint("BOTTOMLEFT", PAD, PAD)
    footer:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    footer:SetHeight(FOOTER_H - 10)
    footer.close = Button(footer, "Close", 90, "secondary", function() AW.Close() end, "Closes the workspace and drops the capture and the changes. Published packages are kept.")
    footer.close:SetPoint("BOTTOMLEFT", 0, 0)
    footer.note = Text(footer, "small", CONTENT_W - 110)
    footer.note:SetPoint("BOTTOMLEFT", footer.close, "BOTTOMRIGHT", 14, 2)
    footer.note:SetText("Nothing here changes a profile. A snapshot is published only when you press Publish, and sent only when you press Send.")

    for i = 1, 6 do w["h" .. i] = Text(content, "heading", CONTENT_W) end
    w.baseTabs, w.variantTabs = {}, {}
    for i = 1, 5 do w.baseTabs[i] = L.Tab(content, "", 145, function() end) end
    for i = 1, LY.MAX_VARIANTS do w.variantTabs[i] = L.Tab(content, "", 165, function() end) end
    w.layoutLabel = Text(content, "body", 140)
    w.captureNote = Text(content, "small", CONTENT_W - 20)
    w.euiLabel, w.twLabel = Text(content, "body", 160), Text(content, "body", 160)
    w.euiName, w.twName = Text(content, "body", 230), Text(content, "body", 230)
    local function Arrow(dir, fn) return Button(content, dir == "left" and "‹" or "›", 26, "secondary", fn) end
    w.euiPrev = Arrow("left", function() local s = A.Session() A.SetSource("eui", Cycle(A.EuiProfiles(), s.eui, -1)) Refresh() end)
    w.euiNext = Arrow("right", function() local s = A.Session() A.SetSource("eui", Cycle(A.EuiProfiles(), s.eui, 1)) Refresh() end)
    w.twPrev = Arrow("left", function() local s = A.Session() A.SetSource("twichui", Cycle(A.TwichProfiles(), s.twichui, -1)) Refresh() end)
    w.twNext = Arrow("right", function() local s = A.Session() A.SetSource("twichui", Cycle(A.TwichProfiles(), s.twichui, 1)) Refresh() end)
    w.captureBtn = Button(content, "Capture", 100, "primary", DoCapture, "Reads the two profiles named above. They are not changed.")
    w.captureStatus = Text(content, "small", CONTENT_W - 120)
    w.summary = Text(content, "small", CONTENT_W - 20)
    w.skipped = Text(content, "small", CONTENT_W - 20)
    w.rows = {}
    for i = 1, ROWS do
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(CONTENT_W - 10, 48)
        local row = { frame = f }
        row.check = L.Checkbox(f, function(on) if row.it then A.SetInclude(row.it.id, on) end Refresh() end)
        row.check:SetPoint("TOPLEFT", 0, -4)
        row.label = Text(f, "body", 360)
        row.label:SetPoint("TOPLEFT", 28, -3)
        row.detail = Text(f, "small", 360)
        row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.target = Button(f, "This layout only", 150, "secondary", function()
            if not row.it then return end
            A.SetTarget(row.it.id, row.it.to == "base" and "variant" or "base")
            Refresh()
        end, "Where this change lives. 'This layout only' keeps it in the layout being edited. 'Shared' moves it to the base every layout of the package starts from; the lines under it say what that does to each layout.")
        row.target:SetPoint("TOPRIGHT", -4, -2)
        row.how = Button(f, "Reset to default", 130, "secondary", function()
            if not row.it then return end
            A.SetHow(row.it.id, row.it.how == "release" and "reset" or "release")
            Refresh()
        end, "This setting is at TwichUI's default in your profile, but the layout sets something else. 'Reset to default' puts players who have the layout back to the default; 'Stop managing' leaves them what they have.")
        row.how:SetPoint("RIGHT", row.target, "LEFT", -6, 0)
        row.effects = Text(f, "small", 300)
        row.effects:SetPoint("TOPRIGHT", row.target, "BOTTOMRIGHT", 0, -2)
        row.effects:SetJustifyH("RIGHT")
        w.rows[i] = row
        AW.frames = AW.frames + 4
    end
    w.pagePrev = Button(content, "Previous", 90, "secondary", function() AW.page = math.max(1, AW.page - 1) Refresh() end)
    w.pageNext = Button(content, "Next", 90, "secondary", function() AW.page = AW.page + 1 Refresh() end)
    w.pageLabel = Text(content, "small", 120)
    w.checkBtn = Button(content, "Check", 100, "primary", function() A.Session().report = nil A.Check() Refresh() end,
        "Builds the package as it would be published and checks it the way a recipient's TwichUI will: both layouts resolved, the files it points at, anything personal, the version.")
    w.checkText = Text(content, "small", CONTENT_W - 120)
    w.fixBtns = {}
    for i = 1, 3 do w.fixBtns[i] = Button(content, "", 380, "secondary", function() end, "Replaces the path to another addon's file with the same file in TwichUI's own media folder, in the package only.") end
    w.idLabel, w.titleLabel, w.revLabel, w.pubLabel, w.notesLabel = Text(content, "body", 125), Text(content, "body", 125), Text(content, "body", 125), Text(content, "body", 125), Text(content, "body", 125)
    w.idEdit = Edit(content, 260, Commit("id"))
    w.titleEdit = Edit(content, 360, Commit("title"))
    w.publisherEdit = Edit(content, 260, Commit("publisher"))
    w.notesEdit = Edit(content, 500, Commit("notes"))
    w.revMinus = Button(content, "-", 26, "secondary", function() local r = A.Session().release A.SetRelease("revision", r.revision - 1) Refresh() end)
    w.revPlus = Button(content, "+", 26, "secondary", function() local r = A.Session().release A.SetRelease("revision", r.revision + 1) Refresh() end)
    w.revText = Text(content, "body", 40)
    w.revNote = Text(content, "small", 300)
    w.releaseNote = Text(content, "small", CONTENT_W - 20)
    w.publishBtn = Button(content, "Publish", 120, "primary", DoPublish, "Keeps an unchangeable snapshot of the package. Nothing is sent.")
    w.publishStatus = Text(content, "small", CONTENT_W - 170)
    w.pubRows = {}
    for i = 1, LY.Store.LIMITS.published do
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(CONTENT_W - 10, 28)
        local row = { frame = f }
        row.pick = L.Tab(f, "", 330, function() local s = A.Session() if row.entry then s.published = row.entry end Refresh() end)
        row.pick:SetPoint("TOPLEFT", 0, 0)
        row.info = Text(f, "small", 100)
        row.info:SetPoint("LEFT", row.pick, "RIGHT", 10, 0)
        row.remove = Button(f, "Remove", 80, "secondary", function() if row.entry then DoRemove(row.entry) end end, "Deletes this stored snapshot.")
        row.remove:SetPoint("TOPRIGHT", -4, -2)
        w.pubRows[i] = row
        AW.frames = AW.frames + 3
    end
    w.pubNone = Text(content, "small", CONTENT_W - 20)
    w.pubNone:SetText("Nothing published yet.")
    w.sendLabel = Text(content, "body", 125)
    w.sendEdit = Edit(content, 200, function() end)
    w.sendBtn = Button(content, "Send", 90, "primary", function() DoSend(false) end, "Asks you to confirm, then offers the package to the name typed. They are asked before anything is stored.")
    w.testBtn = Button(content, "Test on myself", 120, "secondary", function() DoSend(true) end, "Sends it to this character through the real path, to try the whole flow without a friend.")
    w.sendNote = Text(content, "small", CONTENT_W - 20)
    w.sendStatus = Text(content, "small", CONTENT_W - 20)

    win:HookScript("OnShow", function()
        if not A.Active() then A.Begin() end
        Refresh()
    end)
    win:HookScript("OnHide", function() A.End() end)
    -- sharing progress: one listener for the session, added once; it does nothing while the window is closed
    if R.Share and R.Share.OnChange and not AW.listening then
        AW.listening = true
        R.Share:OnChange(function() if AW.IsShown() then AW.RefreshStatus() end end)
    end
    AW.frames = AW.frames + 6
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------
function AW.Open()
    if not win then R.Perf.Call("layoutwizard.author.build", Build) end
    if not A.Active() then
        local ok, why = A.Begin()
        if not ok then Say("there is no layout package to start from (%s).", tostring(why)) return false end
    end
    win:Show()
    Refresh()
    return true
end

function AW.Close() if win then win:Hide() end end
function AW.Toggle() if AW.IsShown() then AW.Close() else AW.Open() end end

R.Perf.Gauge("layoutwizard.author.frames", { label = "Layout authoring window: frames and widgets kept", unit = "count", kind = "pool",
    group = "layouts", read = function() return AW.frames end })
