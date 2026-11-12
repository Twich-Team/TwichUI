-- TwichUI Test Lab: the window (R.TestLab.Window)
-- Built the first time it opens. Loading the addon opens it once and registers /tuilab to open or close it again; nothing runs by itself.
-- Category checkboxes, Run and Stop, a progress line, the counts, one row per result (with the guide status pictures and a word, never
-- colour alone), and a report box: the game gives addons no clipboard, so "Copy report" fills a selected box and the player presses Ctrl+C.
-- Closing the window (or Esc) stops a run in progress. Drawn with the core's shared looks (R.Look, R.FrameLook, R.CraftLook).
-- Esc closes it through UISpecialFrames, never through the game menu's handler list.

local R = TwichUI
local TL = R.TestLab
local RN, RP = TL.Runner, TL.Report
local W = {}
TL.Window = W

local NAME = "TwichUITestLabWindow"
local WIDTH, HEIGHT, HEADER_H, PAD = 680, 640, 46, 16
local ROW_H = 18
local ICON = { pass = R.PATH .. [[media\guides\status-done-small]], fail = R.PATH .. [[media\guides\status-failed-small]],
    error = R.PATH .. [[media\guides\status-failed-small]], timeout = R.PATH .. [[media\guides\status-failed-small]],
    running = R.PATH .. [[media\guides\status-current-small]] }
local WORD = { pass = "pass", fail = "FAIL", error = "ERROR", skipped = "skip", timeout = "TIMEOUT", stopped = "stopped", pending = "waiting", running = "running" }

local win
local chosen = {}        -- category id -> true
local rows = {}
local lastText

local function Say(text) if win then win.note:SetText(text or "") end end

local function Counts(c)
    return ("Passed %d  |  Failed %d  |  Skipped %d  |  Error %d  |  Timeout %d  |  Stopped %d"):format(
        c.pass or 0, c.fail or 0, c.skipped or 0, c.error or 0, c.timeout or 0, c.stopped or 0)
end

---------------------------------------------------------------------------
-- Drawing what the runner reports
---------------------------------------------------------------------------
local function Row(i)
    local row = rows[i]
    if row then return row end
    local L, K = R.Look, R.Look.pal
    row = CreateFrame("Frame", nil, win.list)
    row:SetSize(win.listWidth, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 2, 0)
    row.word = L.Text(row, "small")
    row.word:SetPoint("LEFT", 22, 0)
    row.word:SetWidth(60)
    row.id = L.Text(row, "body")
    row.id:SetPoint("LEFT", 86, 0)
    row.id:SetWidth(230)
    row.label = L.Text(row, "meta")
    row.label:SetPoint("LEFT", 320, 0)
    row.label:SetWidth(64)
    row.detail = L.Text(row, "small")
    row.detail:SetPoint("LEFT", 388, 0)
    row.detail:SetWidth(win.listWidth - 392)
    if row.detail.SetWordWrap then row.detail:SetWordWrap(false) end
    row.id:SetWordWrap(false)
    rows[i] = row
    return row
end

local function Paint(results)
    for i, r in ipairs(results) do
        local row = Row(i)
        local icon = ICON[r.status]
        row.icon:SetShown(icon ~= nil)
        if icon then row.icon:SetTexture(icon) end
        row.word:SetText(WORD[r.status] or r.status)
        row.id:SetText(r.id)
        row.label:SetText(r.status == "pending" and "" or r.label)
        row.detail:SetText(r.detail and RP.Clean(r.detail, 160) or (r.ms and ("%.1f ms"):format(r.ms)) or "")
        row:Show()
    end
    for i = #results + 1, #rows do rows[i]:Hide() end
    win.list:SetHeight(math.max(ROW_H, #results * ROW_H))
end

local function Buttons()
    local running = RN.Active()
    win.run:SetEnabled(not running)
    win.stop:SetEnabled(running)
    win.copy:SetEnabled(not running and RN.last ~= nil)
    for _, box in pairs(win.boxes) do box:SetActive(not running) end
end

local function Progress(p)
    if not (win and p) then return end
    win.fill:SetWidth(math.max(1, math.floor(win.barWidth * math.max(0, p.at - 1) / math.max(1, p.n))))
    win.progress:SetText(("case %d of %d  |  %s  |  %.1f s"):format(p.at, p.n, p.id or "", p.seconds))
    win.counts:SetText(Counts(p.counts))
    Paint(p.results)
end

local function Done(sum)
    if not win then return end
    local c = sum.counts
    win.fill:SetWidth(sum.ended == "complete" and win.barWidth or math.max(1, math.floor(win.barWidth * (#sum.results - c.stopped) / math.max(1, #sum.results))))
    win.counts:SetText(Counts(c))
    if sum.ended == "complete" then
        win.progress:SetText(("finished %d cases in %.2f s"):format(#sum.results, sum.seconds))
        Say(c.fail + c.error + c.timeout == 0 and "Every case that ran passed." or "Some cases did not pass. Copy the report for the details.")
    else
        win.progress:SetText(("stopped after %.2f s"):format(sum.seconds))
        Say("Stopped. No further step was started. A step already running could not have been interrupted; the report says what ran.")
    end
    Paint(sum.results)
    lastText = RP.Build(sum)
    Buttons()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function W.Run()
    local list = TL.Select(chosen)
    if #list == 0 then Say("Choose at least one category.") return false end
    local cats = {}
    for _, id in ipairs(TL.categoryOrder) do if chosen[id] then cats[#cats + 1] = id end end
    local ok, why = RN.Start(list, { cats = cats, onProgress = Progress, onDone = Done })
    if not ok then
        Say(why == "combat" and "Not during combat. Try again when combat ends." or "It cannot start now (" .. tostring(why) .. ").")
        return false
    end
    lastText = nil
    win.edit:SetText("")
    win.fill:SetWidth(1)
    win.progress:SetText("starting")
    Say("Running. Stop is available; it prevents further steps but cannot interrupt one that is running.")
    Buttons()
    return true
end

function W.Stop() return RN.Stop("user") end

function W.Copy()
    if not lastText then Say("There is no report yet: run the cases first.") return false end
    win.edit:SetText(lastText)
    win.edit:SetCursorPosition(0)
    win.edit:SetFocus()
    win.edit:HighlightText()
    Say(("Report selected (%d characters): press Ctrl+C, then paste it where it is needed."):format(#lastText))
    return true
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    local L, K, F, CL = R.Look, R.Look.pal, R.FrameLook, R.CraftLook
    local _, _, CR = F.ContentInsets()
    local contentW = WIDTH - 2 * PAD
    win = CreateFrame("Frame", NAME, UIParent)
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
    if win.SetDontSavePosition then win:SetDontSavePosition(true) end
    win:Hide()
    win:HookScript("OnHide", function() RN.Stop("closed") end)
    tinsert(UISpecialFrames, NAME)
    win.shell = F.Shell(win, { below = true })
    F.FadeIn(win)
    local head = win.shell:Header(HEADER_H)
    local crest = head:CreateTexture(nil, "ARTWORK")
    crest:SetSize(24, 24); crest:SetPoint("TOPLEFT", 16, -13); crest:SetTexture(R.ICON)
    local title = L.Text(win, "title")
    title:SetPoint("LEFT", crest, "RIGHT", 8, 0); title:SetText("TwichUI Test Lab")
    local sub = L.Text(win, "meta")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2); sub:SetText("development only, version " .. TL.VERSION)
    local close = F.Close(win, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -(CR + 2), -14)

    local function Button(label, w, kind, onClick)
        local b = F.Button(win, label, w, kind, onClick)
        b:SetHeight(26)
        CL.Control(b, kind == "primary" and "confirmation" or nil)
        CL.Font(b.text, 14)
        return b
    end
    local function Section(top, height)
        local panel = CreateFrame("Frame", nil, win)
        panel:SetPoint("TOPLEFT", PAD, -top)
        panel:SetSize(contentW, height)
        CL.PanelFace(panel, "card")
        return panel
    end

    -- categories
    local y = HEADER_H + 10
    local catH = 30 + #TL.categoryOrder * 24
    local cats = Section(y, catH)
    local h = L.Text(cats, "heading"); h:SetPoint("TOPLEFT", 12, -8); h:SetText("What to run")
    win.boxes = {}
    for i, id in ipairs(TL.categoryOrder) do
        local cat = TL.categories[id]
        chosen[id] = true
        local box = L.Checkbox(cats, function(on) chosen[id] = on; win.boxes[id]:SetChecked(on) end)
        box:SetPoint("TOPLEFT", 12, -(10 + i * 24))
        box:SetChecked(true)
        local label = L.Text(cats, "body"); label:SetPoint("LEFT", box, "RIGHT", 8, 0)
        label:SetText(("%s  (%d cases)"):format(cat.label, TL.Count(id)))
        local blurb = L.Text(cats, "small"); blurb:SetPoint("LEFT", label, "RIGHT", 10, 0); blurb:SetText(cat.blurb)
        win.boxes[id] = box
    end
    y = y + catH + 8

    -- run, stop, copy, and the progress
    win.run = Button("Run", 90, "primary", W.Run)
    win.run:SetPoint("TOPLEFT", PAD, -y)
    win.stop = Button("Stop", 90, "secondary", W.Stop)
    win.stop:SetPoint("LEFT", win.run, "RIGHT", 8, 0)
    win.copy = Button("Copy report", 120, "secondary", W.Copy)
    win.copy:SetPoint("LEFT", win.stop, "RIGHT", 8, 0)
    win.note = L.Text(win, "small")
    win.note:SetPoint("LEFT", win.copy, "RIGHT", 12, 0)
    win.note:SetWidth(contentW - 330)
    win.note:SetWordWrap(true)
    y = y + 34

    win.barWidth = contentW - 4
    local track = L.Solid(win, "ARTWORK", K.ink, 1)
    track:SetPoint("TOPLEFT", PAD, -y); track:SetSize(contentW, 10)
    win.fill = L.Solid(win, "OVERLAY", K.sage, 1)
    win.fill:SetPoint("TOPLEFT", PAD + 2, -(y + 2)); win.fill:SetSize(1, 6)
    y = y + 14
    win.progress = L.Text(win, "body"); win.progress:SetPoint("TOPLEFT", PAD, -y); win.progress:SetText("not running")
    y = y + 20
    win.counts = L.Text(win, "small"); win.counts:SetPoint("TOPLEFT", PAD, -y); win.counts:SetText(Counts({}))
    y = y + 20

    -- the results
    local listBox = CreateFrame("Frame", nil, win, "BackdropTemplate")
    listBox:SetPoint("TOPLEFT", PAD, -y)
    listBox:SetSize(contentW, 190)
    L.Well(listBox, 0.9)
    local sc = CreateFrame("ScrollFrame", nil, listBox, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 6, -6); sc:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(sc)
    win.listWidth = contentW - 36
    win.list = CreateFrame("Frame", nil, sc)
    win.list:SetSize(win.listWidth, ROW_H)
    sc:SetScrollChild(win.list)
    y = y + 196

    -- the report
    local rh = L.Text(win, "heading"); rh:SetPoint("TOPLEFT", PAD, -y); rh:SetText("Report")
    local legend = L.Text(win, "small")
    legend:SetPoint("LEFT", rh, "RIGHT", 10, 0)
    legend:SetText("synthetic: our code on made-up data  |  client: observed in this game")
    y = y + 18
    local box = CreateFrame("Frame", nil, win, "BackdropTemplate")
    box:SetPoint("TOPLEFT", PAD, -y)
    box:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    L.Well(box, 0.9)
    local rs = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    rs:SetPoint("TOPLEFT", 6, -6); rs:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(rs)
    local edit = CreateFrame("EditBox", nil, rs)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall"); edit:SetWidth(contentW - 50); edit:SetTextInsets(2, 2, 2, 2)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    edit:SetScript("OnTextChanged", function(e, user)   -- for reading and copying: typing puts the report back
        if user then e:SetText(lastText or ""); e:HighlightText() end
    end)
    rs:SetScrollChild(edit)
    win.edit = edit
    Buttons()
    return win
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function W.Show()
    if not win then Build() end
    win:Show()
end
function W.Toggle()
    if win and win:IsShown() then win:Hide() else W.Show() end
end
function W.Frame() return win end

SLASH_TWICHUILAB1 = "/tuilab"
SlashCmdList["TWICHUILAB"] = function() W.Toggle() end

-- Loading the addon opens the window once
W.Show()
