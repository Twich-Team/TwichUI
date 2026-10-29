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
-- The TwichUI presets section edits the package's helper presets (AuthorPresets.lua): a draft of their own, with a pending edit
-- that reaches the draft only through Save to draft. Closing with preset work that isn't saved or published asks first (the Close
-- button), or keeps the session until the reload (Escape): nothing the author made is dropped without being asked.
--
--   AuthorWindow.Open(), Close(), Toggle(), IsShown(), Refresh(), ShowExport(entry)

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

local AP = WZ.AuthorPresets
local EDIT_ROWS = 10               -- settings shown at a time in the preset editor

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
                if b.key == s.baseKey then return end
                local function Go()
                    local ok = A.SetBase(b.key, function() AW.Refresh() end)
                    if ok then AW.Refresh() end
                end
                if A.Dirty() then
                    R.Interact.Confirm("TWICHUI_LAYOUT_PRESETS_BASE",
                        "Start from another package?\n\nYour TwichUI preset changes (the draft, and any edit not saved to it) are not published, and starting from another package drops them. Published packages are kept.",
                        Go, { accept = "Start from it" })
                else Go() end
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

    -- 4. TwichUI presets
    y = AW.DrawPresets(y)

    -- 5. check
    y = Section("h4", "5. Check it as a recipient will", y)
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

    -- 6. release
    y = Section("h5", "6. Release", y)
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

    -- 7. published, and sending
    y = Section("h6", "7. Send a published package", y)
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
            row.export:SetScript("OnClick", function() AW.ShowExport(e) end)
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
-- 4. TwichUI presets: the helper presets' draft, and the editor of one preset (AuthorPresets.lua)
---------------------------------------------------------------------------
local PRESET_WHY = {
    keep = "\"Leave them as they are\" is the option that changes nothing: it can't hold settings. Duplicate a preset or create one instead.",
    ["no-twichui-profile"] = "That TwichUI profile isn't there now. Choose another one to read from.",
    full = ("A choice may offer at most %d options."):format(LY.MAX_OPTIONS),
    last = "A package keeps at least one option.",
    ["needs-default"] = "This is the default. Make another option the default first, then remove this one.",
    ["bad-id"] = ("An id is lower-case letters, digits and single hyphens, starting with a letter, at most %d characters."):format(40),
    ["id-taken"] = "That id is in use, or is one this package offered before and keeps retired.",
    ["bad-label"] = "A name is plain text of at most 48 characters.", ["label-taken"] = "Another option already has that name.",
    ["bad-hint"] = "A description is plain text of at most 200 characters.",
    limit = ("A preset may manage at most %d settings."):format(LY.MAX_UNITS),
    owned = "Another wizard choice sets that, so a preset can't.", ["bad-value"] = "That isn't a value this setting can have.",
    closed = "The workspace isn't open.", unknown = "That option isn't there any more.",
}
local function PresetNote(text) local s = A.Session() if s then s.presetNote = (text ~= "" and text) or nil end end
local function Why(code, text) PresetNote(text or PRESET_WHY[code] or tostring(code)) end

-- Runs fn now, or after asking when an edit that isn't saved to the draft would be dropped.
local function AfterPending(fn)
    if AP.Unsaved() then
        local e = AP.Pending()
        R.Interact.Confirm("TWICHUI_LAYOUT_PRESETS_DISCARD",
            ("Discard your edit of \"%s\"?\n\nIt isn't saved to the draft. Nothing in your profiles or the published packages changes either way."):format(e.label),
            function() AP.Discard() fn() Refresh() end, { accept = "Discard it" })
    else
        AP.Discard()
        fn()
    end
end

local function Plural(n, one, many) return n == 1 and one or many end

local function SummaryText(o)
    local sm, parts = o.summary, {}
    if o.keep then return "Changes nothing: every setting the presets manage stays as the player has it." end
    parts[#parts + 1] = ("%d %s"):format(o.n, Plural(o.n, "setting", "settings"))
    if #sm.on > 0 then parts[#parts + 1] = "turns on " .. table.concat(sm.on, ", ") end
    if #sm.off > 0 then parts[#parts + 1] = "turns off " .. table.concat(sm.off, ", ") end
    if sm.set > 0 then parts[#parts + 1] = ("%d other %s"):format(sm.set, Plural(sm.set, "setting", "settings")) end
    if sm.reset > 0 then parts[#parts + 1] = ("%d back to TwichUI's default"):format(sm.reset) end
    local text = table.concat(parts, "; ")
    if o.overlap > 0 then text = text .. (" (%d also set by the layout's own looks: the preset's value wins)"):format(o.overlap) end
    return text
end

local function ValueEditable(r) return r.op and not r.op.reset and (r.kind == "int" or r.kind == "color" or r.kind == "name" or r.kind == "sound") end

function AW.DrawPresets(y)
    local s = A.Session()
    local P = s.presets
    y = Section("hP", "4. TwichUI presets", y)
    local ws = w.presets
    local hideAll = not P or P.none
    for _, o in pairs(ws.static) do o:SetShown(not hideAll) end
    for _, row in ipairs(ws.rows) do row.frame:SetShown(false) end
    ws.editor:SetShown(false)
    if hideAll then
        ws.none:Show()
        ws.none:SetText(P and P.none == "invalid" and "The starting package doesn't pass its checks, so its presets can't be edited."
            or "This package has no TwichUI presets selector. (Adding a new wizard question isn't part of this workspace.)")
        Place(ws.none, 0, y)
        return y + Height(ws.none) + 12
    end
    ws.none:Hide()
    local legacy = P.mode ~= "settings"
    ws.intro:SetText(("The setup's \"%s\" question offers these options. Capturing reads the TwichUI profile below without changing or switching to it; nothing reaches the package until you Save to draft, and nothing reaches players until you Publish (and they install it).%s"):format(
        P.label, legacy and "\nThese presets are in the older switch-on-only form. Saving a change makes them editable presets (package format 6, which older TwichUI versions can't read); each keeps exactly the settings and values it has." or ""))
    Place(ws.intro, 0, y)
    y = y + Height(ws.intro) + 8
    -- the source profile, by its exact name
    local sources = AP.Sources()
    ws.srcLabel:SetText("Read settings from")
    Place(ws.srcLabel, 0, y + 4)
    Place(ws.srcPrev, 170, y)
    ws.srcName:SetText(#sources > 0 and (("\"%s\"%s"):format(tostring(P.source), AP.SourceInUse() and " (the profile in use)" or "")) or "No TwichUI profiles available")
    Place(ws.srcName, 200, y + 4)
    Place(ws.srcNext, 470, y)
    y = y + 30
    ws.hintLabel:SetText("Question's description")
    Place(ws.hintLabel, 0, y + 4)
    Place(ws.hintEdit, 170, y)
    if not ws.hintEdit:HasFocus() then ws.hintEdit:SetText(P.hint or "") end
    y = y + 30
    -- the options
    for i, o in ipairs(AP.Options()) do
        local row = ws.rows[i]
        if row then
            row.o = o
            row.frame:Show()
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row.pick.text:SetText(o.label)
            row.pick:SetSelected(o.selected)
            local tags = {}
            if o.default then tags[#tags + 1] = "Default" end
            if o.new then tags[#tags + 1] = "New" elseif o.changed then tags[#tags + 1] = "Changed" end
            row.info:SetText((#tags > 0 and ("[" .. table.concat(tags, ", ") .. "] ") or "") .. SummaryText(o)
                .. (#o.issues > 0 and ("\nNeeds attention: " .. table.concat(o.issues, " ")) or ""))
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #P.options)
            local h = math.max(28, Height(row.info) + 8)
            row.frame:SetHeight(h)
            y = y + h + 2
        end
    end
    y = y + 6
    -- the selected option
    local sel = AP.Find(P.selected)
    local keep = AP.IsKeep(sel)
    ws.nameLabel:SetText("Name")
    Place(ws.nameLabel, 0, y + 4)
    Place(ws.nameEdit, 100, y)
    if not ws.nameEdit:HasFocus() then ws.nameEdit:SetText(sel and sel.label or "") end
    Place(ws.detailsBtn, 380, y)
    ws.detailsBtn.text:SetText(AW.presetDetails and "Hide details" or "Show details")
    y = y + 28
    ws.descLabel:SetText("Description")
    Place(ws.descLabel, 0, y + 4)
    Place(ws.descEdit, 100, y)
    if not ws.descEdit:HasFocus() then ws.descEdit:SetText(sel and sel.hint or "") end
    y = y + 28
    ws.idText:SetShown(AW.presetDetails == true)
    ws.idLabel:SetShown(AW.presetDetails == true and sel ~= nil and not keep)
    ws.idEdit:SetShown(AW.presetDetails == true and sel ~= nil and not keep)
    if AW.presetDetails then
        if sel and not keep then
            ws.idLabel:SetText("Id")
            Place(ws.idLabel, 0, y + 4)
            Place(ws.idEdit, 100, y)
            if not ws.idEdit:HasFocus() then ws.idEdit:SetText(sel.id) end
            y = y + 28
        end
        ws.idText:SetText(("Stable id: %s (players' picks are remembered by it; renaming never changes it).%s"):format(sel and sel.id or "?",
            #P.retired > 0 and (" No longer offered: " .. table.concat(P.retired, ", ") .. ".") or ""))
        Place(ws.idText, 0, y)
        y = y + Height(ws.idText) + 6
    end
    Place(ws.captureBtn, 0, y)
    Place(ws.editBtn, 270, y)
    ws.captureBtn:SetEnabled(sel ~= nil and not keep)
    ws.editBtn:SetEnabled(sel ~= nil and not keep)
    y = y + 28
    Place(ws.dupBtn, 0, y)
    Place(ws.defaultBtn, 100, y)
    Place(ws.removeBtn, 220, y)
    Place(ws.createBtn, 330, y)
    ws.dupBtn:SetEnabled(sel ~= nil and not keep and #P.options < LY.MAX_OPTIONS)
    ws.defaultBtn:SetEnabled(sel ~= nil and P.default ~= sel.id)
    ws.removeBtn:SetEnabled(sel ~= nil and not keep and #P.options > 1)
    ws.createBtn:SetEnabled(#P.options < LY.MAX_OPTIONS)
    y = y + 30
    local note = s.presetNote or (keep and "\"Leave them as they are\" changes nothing of what the presets manage. The layout's own TwichUI looks and places still apply whichever option a player picks."
        or (P.changed and ("The draft's presets differ from the starting package%s."):format(P.gen ~= P.publishedGen and " and aren't published yet" or "")) or "")
    ws.status:SetText(note)
    Place(ws.status, 0, y)
    y = y + (note ~= "" and (Height(ws.status) + 8) or 4)
    -- the editor
    local e = AP.Pending()
    if e then y = AW.DrawEditor(e, y) end
    return y + 8
end

function AW.DrawEditor(e, y)
    local ed = w.presets.ed
    local P = AP.State()
    w.presets.editor:Show()
    local d = AP.Diff(e)
    ed.head:SetText(("%s \"%s\" (not saved to the draft)"):format(e.isNew and "New preset" or (e.kind == "capture" and "Captured into" or "Reviewing"), e.label))
    Place(ed.head, 0, y)
    y = y + Height(ed.head) + 4
    local src = e.source and ("Values read from \"" .. e.source .. "\" when you pressed the button.") or ("A setting you add takes its value from \"" .. tostring(P.source) .. "\".")
    ed.summary:SetText(("%d %s managed%s. %s A setting it doesn't manage is never changed by it, and nothing is added unless you tick it.%s"):format(
        d.managed, Plural(d.managed, "setting", "settings"),
        e.isNew and "" or (": %d changed, %d added, %d no longer managed, against the draft"):format(d.changed, d.added, d.removed), src,
        e.isNew and " It starts by managing whether each feature is on or off; add looks and behaviour settings under Not managed." or ""))
    Place(ed.summary, 0, y)
    y = y + Height(ed.summary) + 6
    if e.isNew then
        ed.nameLabel:Show()
        ed.nameLabel:SetText("Name")
        Place(ed.nameLabel, 0, y + 4)
        ed.nameEdit:Show()
        Place(ed.nameEdit, 100, y)
        if not ed.nameEdit:HasFocus() then ed.nameEdit:SetText(e.label) end
        y = y + 28
    else
        ed.nameLabel:Hide()
        ed.nameEdit:Hide()
    end
    for i, v in ipairs(AP.VIEWS) do
        local tab = ed.views[i]
        tab:SetSelected(e.view == v.id)
        Place(tab, (i - 1) * 150, y)
    end
    y = y + 30
    if e.view == "excluded" then
        for _, o in ipairs(ed.listParts) do o:Hide() end
        for _, row in ipairs(ed.rows) do row.frame:Hide() end
        local lines = {}
        for _, x in ipairs(AP.Excluded()) do
            lines[#lines + 1] = ("%s (%d): %s%s"):format(x.title, x.n, x.why,
                x.examples and #x.examples > 0 and (" " .. table.concat(x.examples, ", ", 1, math.min(#x.examples, 8)) .. (#x.examples > 8 and ", ..." or "") .. ".") or "")
        end
        lines[#lines + 1] = "Also left to their own settings: anything another wizard choice sets (the accent, tooltip placement, friendly plates, the size)."
        ed.excluded:Show()
        ed.excluded:SetText(table.concat(lines, "\n\n"))
        Place(ed.excluded, 0, y)
        y = y + Height(ed.excluded) + 8
    else
        ed.excluded:Hide()
        for _, o in ipairs(ed.listParts) do o:Show() end
        local groups = AP.Eligible().groups
        local gl = "All categories"
        for _, g in ipairs(groups) do if g.id == e.group then gl = g.label end end
        Place(ed.catPrev, 0, y)
        ed.catName:SetText(gl)
        Place(ed.catName, 30, y + 4)
        Place(ed.catNext, 250, y)
        ed.searchLabel:SetText("Search")
        Place(ed.searchLabel, 290, y + 4)
        Place(ed.search, 345, y)
        if not ed.search:HasFocus() then ed.search:SetText(e.query or "") end
        y = y + 28
        Place(ed.addAll, 0, y)
        Place(ed.dropAll, 180, y)
        y = y + 28
        local rows = AP.Rows()
        local pages = math.max(1, math.ceil(#rows / EDIT_ROWS))
        e.page = math.min(math.max(1, e.page or 1), pages)
        for i, row in ipairs(ed.rows) do
            local r = rows[(e.page - 1) * EDIT_ROWS + i]
            row.frame:SetShown(r ~= nil)
            row.r = r
            if r then
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row.check:SetChecked(r.op ~= nil)
                row.check:SetActive(not r.owned)
                row.label:SetText(("%s  |  %s"):format(r.label, r.groupLabel))
                local bits = {}
                if r.op then bits[#bits + 1] = "Sets: " .. r.text end
                if r.status == "added" then bits[#bits + 1] = "newly managed"
                elseif r.status == "removed" then bits[#bits + 1] = "no longer managed (was: " .. r.wasText .. ")"
                elseif r.status == "changed" then bits[#bits + 1] = "was: " .. r.wasText end
                if not r.op then
                    local now = r.captured ~= nil and r.captured or AP.ReadOne(r.unit)
                    if now ~= nil then bits[#bits + 1] = "your profile: " .. LY.TwichUIAdapter.Show(now) end
                end
                if r.customised and not r.op then bits[#bits + 1] = "changed from TwichUI's default" end
                if r.layer then bits[#bits + 1] = "the layout's own looks set it too (the preset's value wins)" end
                if r.owned then bits[#bits + 1] = "set by the " .. r.owned .. " choice: never in a preset" end
                row.detail:SetText(table.concat(bits, "; "))
                local cycle = r.op and not r.op.reset and (r.kind == "bool" or r.kind == "enum")
                row.value:SetShown(cycle == true)
                if cycle then row.value.text:SetText(r.kind == "bool" and (r.op.v and "On" or "Off") or tostring(r.op.v)) end
                row.edit:SetShown(ValueEditable(r) == true)
                if ValueEditable(r) and not row.edit:HasFocus() then row.edit:SetText(tostring(r.op.v)) end
                row.reset:SetShown(r.op ~= nil)
                row.reset.text:SetText(r.op and r.op.reset and "Give a value" or "Reset")
                y = y + 44
            end
        end
        ed.empty:SetShown(#rows == 0)
        if #rows == 0 then
            ed.empty:SetText(e.view == "managed" and "This preset manages nothing here yet. Tick settings under Not managed."
                or e.view == "changed" and "Nothing changed against the draft." or "Nothing to show for this category and search.")
            Place(ed.empty, 0, y)
            y = y + 22
        end
        ed.pageText:SetText(("Page %d of %d (%d %s)"):format(e.page, pages, #rows, Plural(#rows, "setting", "settings")))
        Place(ed.pagePrev, 0, y)
        Place(ed.pageNext, 100, y)
        Place(ed.pageText, 210, y + 4)
        ed.pagePrev:SetEnabled(e.page > 1)
        ed.pageNext:SetEnabled(e.page < pages)
        y = y + 30
    end
    Place(ed.save, 0, y)
    Place(ed.discard, 140, y)
    return y + 32
end

local function Cycle2(list, current, step)
    if #list == 0 then return nil end
    local at = 0
    for i, n in ipairs(list) do if n == current then at = i end end
    if at == 0 then return list[step > 0 and 1 or #list] end
    local nxt = at + step
    if nxt < 1 or nxt > #list then return nil end
    return list[nxt]
end

function AW.BuildPresets(L)
    local ws = { static = {}, rows = {} }
    w.presets = ws
    w.hP = Text(content, "heading", CONTENT_W)
    local function St(o) ws.static[#ws.static + 1] = o return o end
    ws.none = Text(content, "small", CONTENT_W - 20)
    ws.intro = St(Text(content, "small", CONTENT_W - 20))
    ws.srcLabel = St(Text(content, "body", 160))
    ws.srcName = St(Text(content, "body", 260))
    local function Arrow(dir, fn) return Button(content, dir == "left" and "‹" or "›", 26, "secondary", fn) end
    ws.srcPrev = St(Arrow("left", function() AP.SetSource(Cycle(AP.Sources(), AP.Source(), -1)) PresetNote(nil) Refresh() end))
    ws.srcNext = St(Arrow("right", function() AP.SetSource(Cycle(AP.Sources(), AP.Source(), 1)) PresetNote(nil) Refresh() end))
    ws.hintLabel = St(Text(content, "body", 160))
    ws.hintEdit = St(Edit(content, 540, function(text)
        if not A.Active() then return end
        local ok, why = AP.SetChoiceHint(text)
        Why(ok and nil or why, ok and "" or nil)
        Refresh()
    end))
    for i = 1, LY.MAX_OPTIONS do
        local f = CreateFrame("Frame", nil, content)
        f:SetSize(CONTENT_W - 10, 28)
        local row = { frame = f }
        row.pick = L.Tab(f, "", 210, function() if row.o then AP.Select(row.o.id) PresetNote(nil) Refresh() end end)
        row.pick:SetPoint("TOPLEFT", 0, 0)
        row.info = Text(f, "small", CONTENT_W - 300)
        row.info:SetPoint("TOPLEFT", 220, -4)
        row.up = Button(f, "↑", 26, "secondary", function() if row.o then AP.Move(row.o.id, -1) Refresh() end end, "Moves this option up in the setup's list.")
        row.up:SetPoint("TOPRIGHT", -32, -2)
        row.down = Button(f, "↓", 26, "secondary", function() if row.o then AP.Move(row.o.id, 1) Refresh() end end, "Moves this option down in the setup's list.")
        row.down:SetPoint("TOPRIGHT", -2, -2)
        ws.rows[i] = row
        AW.frames = AW.frames + 5
    end
    ws.nameLabel = St(Text(content, "body", 90))
    ws.nameEdit = St(Edit(content, 260, function(text)
        local P = AP.State()
        if not (P and P.selected) or text == "" then Refresh() return end
        local ok, why = AP.Rename(P.selected, text)
        Why(ok and nil or why, ok and "" or nil)
        Refresh()
    end))
    ws.descLabel = St(Text(content, "body", 90))
    ws.descEdit = St(Edit(content, 600, function(text)
        local P = AP.State()
        if not (P and P.selected) then return end
        local ok, why = AP.Describe(P.selected, text)
        Why(ok and nil or why, ok and "" or nil)
        Refresh()
    end))
    ws.detailsBtn = St(Button(content, "Show details", 110, "secondary", function() AW.presetDetails = not AW.presetDetails Refresh() end,
        "Shows the option's stable id (what players' picks are remembered by), lets you change it, and lists the ids the package no longer offers."))
    ws.idLabel = St(Text(content, "body", 90))
    ws.idEdit = St(Edit(content, 260, function(text)
        local P = AP.State()
        local o = P and AP.Find(P.selected)
        if not o or text == "" or text == o.id then Refresh() return end
        local function Change()
            local ok, why = AP.SetId(o.id, text)
            Why(ok and nil or why, ok and ("The id is now \"" .. text .. "\".") or nil)
            Refresh()
        end
        if P.baseIds[o.id] then
            R.Interact.Confirm("TWICHUI_LAYOUT_PRESETS_ID",
                ("Change the id of \"%s\" from %s to %s?\n\nThe starting package already offered it under %s, so that id is retired: no later option can take it, and a player who picked it is told it is no longer offered. Players who have not installed this package are not affected. Only the draft changes."):format(o.label, o.id, text, o.id),
                Change, { accept = "Change the id" })
            Refresh()
        else
            Change()
        end
    end))
    ws.idText = Text(content, "small", CONTENT_W - 20)
    ws.captureBtn = St(Button(content, "Capture current settings into this preset", 260, "primary", function()
        local P = AP.State()
        AfterPending(function()
            local ok, why = AP.BeginCapture(P.selected)
            Why(ok and nil or why, ok and "" or nil)
        end)
        Refresh()
    end, "Reads the settings this preset manages from the TwichUI profile named above, with the values that profile uses (a setting left at TwichUI's default is captured as that value, so off stays off). Its scope stays as it is: settings it doesn't manage are listed apart. Nothing is saved to the draft until you press Save to draft."))
    ws.editBtn = St(Button(content, "Review settings", 140, "secondary", function()
        local P = AP.State()
        AfterPending(function()
            local ok, why = AP.BeginEdit(P.selected)
            Why(ok and nil or why, ok and "" or nil)
        end)
        Refresh()
    end, "Shows the settings this preset manages and lets you add, leave out or adjust them, without capturing again."))
    ws.dupBtn = St(Button(content, "Duplicate", 90, "secondary", function()
        local P = AP.State()
        AfterPending(function()
            local ok, why = AP.Duplicate(P.selected)
            Why(ok and nil or why, ok and "Duplicated: a new option with its own id. Rename it and adjust its settings." or nil)
        end)
        Refresh()
    end, "Adds a copy of this preset with a new id, next to it."))
    ws.defaultBtn = St(Button(content, "Make default", 110, "secondary", function()
        local P = AP.State()
        AP.SetDefault(P.selected)
        PresetNote("")
        Refresh()
    end, "The option the setup starts on for a player who hasn't picked."))
    ws.removeBtn = St(Button(content, "Remove", 100, "danger", function()
        local P = AP.State()
        local o = AP.Find(P.selected)
        if not o then return end
        if P.default == o.id then Why("needs-default") Refresh() return end
        R.Interact.Confirm("TWICHUI_LAYOUT_PRESETS_REMOVE",
            ("Remove the preset \"%s\" from the draft?\n\nOnly the draft changes: published packages and players' installs are not touched. When a player who picked it updates to a package without it, the setup tells them it is no longer offered and asks them to choose another; its id (%s) is never given to another option."):format(o.label, o.id),
            function()
                local ok, why = AP.Remove(o.id)
                Why(ok and nil or why, ok and ("Removed \"" .. o.label .. "\" from the draft.") or nil)
                Refresh()
            end, { accept = "Remove" })
    end, "Removes this option from the draft, after a question. The default can't be removed until another option is the default."))
    ws.createBtn = St(Button(content, "Create preset from current settings", 250, "secondary", function()
        AfterPending(function()
            local ok, why = AP.BeginCreate()
            Why(ok and nil or why, ok and "" or nil)
        end)
        Refresh()
    end, "Starts a new preset from the TwichUI profile named above, managing whether each feature is on or off. Review it, then Save to draft."))
    ws.status = St(Text(content, "small", CONTENT_W - 20))
    AW.frames = AW.frames + 18

    -- the editor
    local editor = CreateFrame("Frame", nil, content)
    editor:SetSize(1, 1)
    ws.editor = editor
    local ed = { views = {}, rows = {}, listParts = {} }
    ws.ed = ed
    ed.head = Text(editor, "heading", CONTENT_W - 20)
    ed.summary = Text(editor, "small", CONTENT_W - 20)
    ed.nameLabel = Text(editor, "body", 90)
    ed.nameEdit = Edit(editor, 260, function(text)
        local ok, why = AP.SetEditName(text)
        Why(ok and nil or why, ok and "" or nil)
        Refresh()
    end)
    for i, v in ipairs(AP.VIEWS) do
        ed.views[i] = L.Tab(editor, v.label, 145, function()
            local e = AP.Pending()
            AP.SetView(v.id)
            if e then e.page = 1 end
            Refresh()
        end)
    end
    local function LP(o) ed.listParts[#ed.listParts + 1] = o return o end
    local function CatStep(step)
        local e = AP.Pending()
        if not e then return end
        local ids = {}
        for _, g in ipairs(AP.Eligible().groups) do ids[#ids + 1] = g.id end
        AP.SetGroup(Cycle2(ids, e.group, step))
        e.page = 1
        Refresh()
    end
    ed.catPrev = LP(Button(editor, "‹", 26, "secondary", function() CatStep(-1) end, "The previous category (or all of them)."))
    ed.catNext = LP(Button(editor, "›", 26, "secondary", function() CatStep(1) end, "The next category (or all of them)."))
    ed.catName = LP(Text(editor, "body", 215))
    ed.searchLabel = LP(Text(editor, "body", 55))
    ed.search = LP(Edit(editor, 200, function(text)
        local e = AP.Pending()
        if not e then return end
        AP.SetQuery(text)
        e.page = 1
        Refresh()
    end))
    ed.addAll = LP(Button(editor, "Include all shown", 170, "secondary", function()
        local ok, why = AP.IncludeShown(true)
        Why(ok and nil or why, ok and "" or nil)
        Refresh()
    end, "Includes every setting the list shows now (this view, category and search), with your profile's values. Nothing past the limit of 256 is added."))
    ed.dropAll = LP(Button(editor, "Leave out all shown", 170, "secondary", function()
        AP.IncludeShown(false)
        PresetNote("")
        Refresh()
    end, "Stops this preset managing every setting the list shows now. They stay as each player has them."))
    for i = 1, EDIT_ROWS do
        local f = CreateFrame("Frame", nil, editor)
        f:SetSize(CONTENT_W - 10, 42)
        local row = { frame = f }
        row.check = L.Checkbox(f, function(on)
            if not row.r then return end
            local ok, why = AP.SetIncluded(row.r.unit, on)
            Why(ok and nil or why, ok and "" or nil)
            Refresh()
        end)
        row.check:SetPoint("TOPLEFT", 0, -4)
        row.label = Text(f, "body", 420)
        row.label:SetPoint("TOPLEFT", 28, -3)
        row.detail = Text(f, "small", 420)
        row.detail:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
        row.value = Button(f, "", 130, "secondary", function()
            if not row.r then return end
            local v = AP.NextValue(row.r.unit)
            if v ~= nil then AP.SetValue(row.r.unit, v) end
            Refresh()
        end, "Changes this preset's value for the setting (on and off, or the next of its choices). Your profile isn't changed.")
        row.value:SetPoint("TOPRIGHT", -84, -2)
        row.edit = Edit(f, 130, function(text)
            local r = row.r
            if not (r and r.op) then return end
            local v = text
            if r.kind == "int" then v = tonumber(text) elseif r.kind == "color" then v = tostring(text):upper() end
            local ok, why = AP.SetValue(r.unit, v)
            local f2 = r.field
            Why(ok and nil or why, ok and "" or (r.kind == "int" and f2 and f2.min and ("That isn't a value this setting can have (a whole number from %d to %d)."):format(f2.min, f2.max))
                or (r.kind == "color" and "A colour is eight hexadecimal digits: red, green, blue and opacity (for example C9A24AFF).") or nil)
            Refresh()
        end)
        row.edit:SetPoint("TOPRIGHT", -84, -2)
        row.reset = Button(f, "Reset", 76, "secondary", function()
            if not (row.r and row.r.op) then return end
            AP.SetReset(row.r.unit, not row.r.op.reset)
            Refresh()
        end, "Reset: players who pick this preset get TwichUI's default for the setting (their stored value is cleared). Give a value: the preset sets a value again.")
        row.reset:SetPoint("TOPRIGHT", -2, -2)
        ed.rows[i] = row
        AW.frames = AW.frames + 6
    end
    ed.empty = LP(Text(editor, "small", CONTENT_W - 20))
    ed.excluded = Text(editor, "small", CONTENT_W - 20)
    ed.pagePrev = LP(Button(editor, "Previous", 90, "secondary", function() local e = AP.Pending() if e then e.page = (e.page or 1) - 1 end Refresh() end))
    ed.pageNext = LP(Button(editor, "Next", 90, "secondary", function() local e = AP.Pending() if e then e.page = (e.page or 1) + 1 end Refresh() end))
    ed.pageText = LP(Text(editor, "small", 300))
    ed.save = Button(editor, "Save to draft", 130, "primary", function()
        local ok, why, text = AP.Save()
        Why(ok and nil or why, ok and "Saved to the draft. Check, then Publish, to make it part of a package." or text)
        Refresh()
    end, "Puts this preset, as it stands here, in the draft. The draft becomes part of a package only when you Publish.")
    ed.discard = Button(editor, "Discard", 100, "secondary", function()
        AfterPending(function() PresetNote("") end)
        Refresh()
    end, "Drops this edit. The draft stays as it was.")
    AW.frames = AW.frames + 20
end

---------------------------------------------------------------------------
-- Export for bundling: a published package as text to copy (the game gives an addon no clipboard and no files)
---------------------------------------------------------------------------
function AW.ShowExport(entry)
    local L = Look()
    local ex = AW.exportFrame
    if not ex then
        ex = CreateFrame("Frame", "TwichUILayoutExport", UIParent, "BackdropTemplate")
        AW.exportFrame = ex
        ex:SetSize(620, 360)
        ex:SetPoint("CENTER", 0, 40)
        ex:SetFrameStrata("DIALOG")
        ex:SetToplevel(true)
        ex:SetClampedToScreen(true)
        ex:EnableMouse(true)
        ex:Hide()
        local listed = false
        for _, n in ipairs(UISpecialFrames) do if n == "TwichUILayoutExport" then listed = true end end
        if not listed then tinsert(UISpecialFrames, "TwichUILayoutExport") end
        L.Shell(ex, 40)
        local title = L.Text(ex, "title")
        title:SetPoint("TOPLEFT", 18, -11)
        title:SetText("Export for bundling")
        L.CloseBox(ex)
        ex.note = Text(ex, "small", 580)
        ex.note:SetPoint("TOPLEFT", 20, -50)
        local sf = CreateFrame("ScrollFrame", nil, ex, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 20, -120)
        sf:SetPoint("BOTTOMRIGHT", -40, 50)
        L.ScrollBar(sf)
        ex.edit = CreateFrame("EditBox", nil, sf)
        ex.edit:SetMultiLine(true)
        ex.edit:SetAutoFocus(false)
        ex.edit:SetFontObject("ChatFontNormal")
        ex.edit:SetWidth(540)
        ex.edit:SetScript("OnEscapePressed", function() ex:Hide() end)
        ex.edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
        -- read only: put the text back if someone types in it
        ex.edit:SetScript("OnTextChanged", function(e, user) if user and ex.text and e:GetText() ~= ex.text then e:SetText(ex.text) e:HighlightText() end end)
        sf:SetScrollChild(ex.edit)
        ex.select = Button(ex, "Select all", 110, "primary", function() ex.edit:SetFocus() ex.edit:HighlightText() end, "Selects the whole text. Then press Ctrl+C.")
        ex.select:SetPoint("BOTTOMRIGHT", -20, 14)
        ex.done = Button(ex, "Close", 90, "secondary", function() ex:Hide() end)
        ex.done:SetPoint("RIGHT", ex.select, "LEFT", -8, 0)
        AW.frames = AW.frames + 8
    end
    ex.text = A.ExportText(entry)
    ex.note:SetText(("\"%s\", revision %d (%d KB), exactly as it was published. Select all, press Ctrl+C, paste it into a text file, and run:\n  tools/update_bundled_layout.sh --from-published --text <that file>\nThe tool checks it again and puts exactly this package's presets and settings in TwichUI's bundled layouts. Nothing here is sent or changed."):format(
        entry.title or entry.id, entry.revision, math.max(1, math.floor(entry.size / 1024 + 0.5))))
    ex.edit:SetText(ex.text or "")
    ex:Show()
    ex.edit:SetFocus()
    ex.edit:HighlightText()
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
    footer.close = Button(footer, "Close", 90, "secondary", function() AW.Close(true) end, "Closes the workspace and drops the capture and the changes (it asks first when TwichUI preset work isn't saved or published). Published packages are kept.")
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
    AW.BuildPresets(L)
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
        row.export = Button(f, "Export for bundling", 150, "secondary", function() end,
            "Shows this published package as text to copy out of the game, so the developer tool can put exactly it in TwichUI's bundled layouts (docs/layouts/presets.md). Nothing is packed again, sent or changed.")
        row.export:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
        w.pubRows[i] = row
        AW.frames = AW.frames + 4
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
    win:HookScript("OnHide", function()
        if AW.exportFrame then AW.exportFrame:Hide() end
        -- preset work that isn't saved or published is never dropped without asking: hidden (Escape), the session stays until the
        -- reload, and opening the workspace again goes on with it
        if A.Dirty() then
            Say("your TwichUI preset changes are kept until you reload. /tui layout author opens them again.")
        else
            A.End()
        end
    end)
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

-- ask: the Close button (asks before dropping preset work that isn't saved or published; Escape keeps it instead)
function AW.Close(ask)
    if not win then return end
    if ask and A.Dirty() then
        R.Interact.Confirm("TWICHUI_LAYOUT_PRESETS_CLOSE",
            "Close and discard your TwichUI preset changes?\n\nThe draft of the presets (and any edit not saved to it) hasn't been published. Closing drops it; nothing in your profiles or the published packages changes. Escape instead keeps it until you reload.",
            function() A.End() win:Hide() end, { accept = "Discard and close" })
        return
    end
    if ask then A.End() end
    win:Hide()
end
function AW.Toggle() if AW.IsShown() then AW.Close() else AW.Open() end end

R.Perf.Gauge("layoutwizard.author.frames", { label = "Layout authoring window: frames and widgets kept", unit = "count", kind = "pool",
    group = "layouts", read = function() return AW.frames end })
