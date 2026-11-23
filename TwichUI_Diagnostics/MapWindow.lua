-- The map support window uses the same leather/walnut/bronze shell as /tui perf.
-- Reports are prepared only on a button press; selection and chunk navigation reuse the same text.
local R, DX = TwichUI, TwichUI.DiagnosticsKit
local MC = DX.MapCapture
local W = {}; DX.MapWindow = W
local win, status, note, coordinates, edit, page, built, part, frameClock
part = 1
local function Options() return { coordinates = coordinates:GetChecked() == true, description = note:GetText() } end
function W.Select()
    if edit then edit:SetFocus(); edit:HighlightText() end
end
function W.ShowPart()
    if not built then return end
    part = math.max(1, math.min(#built.pieces, part))
    edit:SetText(built.pieces[part].text)
    page:SetText(("Part %d of %d · %d bytes · Ctrl+C to copy"):format(part, #built.pieces, #built.text))
    W.Select()
end
function W.Prepare(kind)
    if not MC.Current() then MC.Capture(Options()) end
    local report, why = MC.Prepare(kind)
    if not report then status:SetText(why or "Report unavailable") return end
    built, part = report, 1
    W.Refresh(); W.ShowPart()
end
function W.Refresh()
    if not win then return end
    local s = MC.Status()
    status:SetText(s.recording and ("Recording · %d / %d seconds · %d events. Mark Issue when the problem happens.")
        :format(s.durationSeconds, s.limitSeconds, s.events)
        or (s.id and ("Ready · %d seconds captured. Copy for AI prepares a compact report."):format(s.durationSeconds)
            or "Ready. Capture the current map, or record while you reproduce a problem."))
    win:SetScript("OnUpdate", s.recording and win:IsShown() and function(_, elapsed)
        frameClock = (frameClock or 0) + elapsed
        if frameClock >= 1 then frameClock = 0; W.Refresh() end
    end or nil)
end
local function Build()
    local L, FL = R.Look, R.FrameLook
    win = CreateFrame("Frame", "TwichUIMapDiagnostics", UIParent)
    win:SetSize(760, 610); win:SetPoint("CENTER"); win:SetFrameStrata("HIGH")
    win:SetClampedToScreen(true); win:SetMovable(true); win:EnableMouse(true)
    win:RegisterForDrag("LeftButton"); win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide(); win:HookScript("OnShow", R.FitToScreen)
    tinsert(UISpecialFrames, "TwichUIMapDiagnostics")
    win.shell = FL.Shell(win, { below = true })
    local head = win.shell:Header(42)
    local title = L.Text(head, "title"); title:SetPoint("LEFT", 20, 0); title:SetText("Map Diagnostics")
    local close = L.Button(head, "×", 30, "secondary", function() win:Hide() end)
    close:SetPoint("RIGHT", -16, 0)
    local area = CreateFrame("Frame", nil, win)
    area:SetPoint("TOPLEFT", 30, -66); area:SetPoint("BOTTOMRIGHT", -30, 25)
    local function Text(kind, y, text)
        local f = L.Text(area, kind); f:SetPoint("TOPLEFT", 0, -y); f:SetWidth(700)
        f:SetJustifyH("LEFT"); f:SetText(text); return f
    end
    Text("small", 0, "Reproduce the problem on the map. Capture or record, then Copy for AI and press Ctrl+C. Nothing is sent automatically.")
    status = Text("body", 38, "")
    Text("meta", 74, "What happened? Optional; avoid personal details. Your description is included as untrusted text.")
    note = L.EditBox(area, 700, 26); note:SetPoint("TOPLEFT", 0, -96)
    note:SetMaxLetters(240); note:SetAutoFocus(false)
    local function Button(label, x, y, width, fn, primary)
        local b = L.Button(area, label, width, primary and "primary" or "secondary", fn)
        b:SetPoint("TOPLEFT", x, -y); return b
    end
    W.capture = Button("Capture Snapshot", 0, 134, 145, function() MC.Capture(Options()); built = nil; W.Refresh() end)
    W.start = Button("Start Recording", 153, 134, 137, function()
        local ok, why = MC.Start(Options()); built = nil; W.Refresh()
        if not ok then status:SetText("Could not start: " .. (why or "unavailable")) end
    end)
    W.mark = Button("Mark Issue", 298, 134, 110, function() MC.Mark(); W.Refresh() end)
    W.stop = Button("Stop & Prepare Report", 416, 134, 196, function() MC.Stop("manual"); W.Prepare("quick") end)
    coordinates = L.Checkbox(area, function() end); coordinates:SetPoint("TOPLEFT", 0, -177)
    coordinates:SetChecked(false)
    local privacy = L.Text(area, "small"); privacy:SetPoint("LEFT", coordinates, "RIGHT", 8, 0); privacy:SetWidth(660)
    privacy:SetText("Include precise view/cursor geometry. Map/texture IDs are always included and may identify the area viewed.")
    W.copy = Button("Copy for AI", 0, 214, 130, function() W.Prepare("quick") end, true)
    W.detailed = Button("Detailed Report", 138, 214, 145, function() W.Prepare("detailed") end)
    W.select = Button("Select Again", 291, 214, 125, W.Select)
    local box = CreateFrame("Frame", nil, area, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, -254); box:SetSize(700, 210); L.Well(box, 0.9)
    local sc = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 7, -7); sc:SetPoint("BOTTOMRIGHT", -26, 7); L.ScrollBar(sc)
    edit = CreateFrame("EditBox", nil, sc)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall"); edit:SetWidth(650); edit:SetTextInsets(3, 3, 3, 3)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    edit:SetScript("OnTextChanged", function(e, user)
        if user and built then e:SetText(built.pieces[part].text); e:HighlightText() end
    end)
    sc:SetScrollChild(edit); W.edit = edit
    W.prev = Button("Previous", 0, 478, 100, function() part = part - 1; W.ShowPart() end)
    W.next = Button("Next", 108, 478, 100, function() part = part + 1; W.ShowPart() end)
    page = L.Text(area, "meta"); page:SetPoint("TOPLEFT", 225, -484); page:SetWidth(475)
    page:SetText("Report text will appear here. Press Ctrl+C after selecting it.")
    win:SetScript("OnShow", W.Refresh); win:SetScript("OnHide", function() win:SetScript("OnUpdate", nil); edit:ClearFocus() end)
    W.frame, W.note, W.coordinates = win, note, coordinates
end
function DX.OpenMap()
    if not win then Build() end
    win:Show(); W.Refresh()
end
DX.OnChange(function(event) if event:match("^map%-") then W.Refresh() end end)
