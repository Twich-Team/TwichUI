-- TwichUI Test Lab: the window (R.TestLab.Window)
-- Built the first time it opens. Loading the addon opens it once and registers /tuilab to open or close it again; nothing runs by itself.
-- Four zones, after the approved mockup (docs/test-lab/lab-mockup.png):
--   left     What to run: one check per registered group, with its case count and what it is for (from the registry, nothing typed here)
--   top      seven summary cards, the Run / Stop / Copy report / Copy failures bar with the run state, and a progress bar
--   middle   quick filters and a search over the run's records, a results table (status, case, type, duration, message), and the details of
--            the chosen result on the right
--   bottom   the full report, selectable: the game gives addons no clipboard, so the Copy buttons select the text and the player presses Ctrl+C
-- All the words, counts and filters come from View.lua (pure, tested offline); the controls come from Kit.lua. Frames are built once, the table is
-- a pooled list (only the rows that can show exist), the report is written once when a run ends, and nothing animates or runs per frame: the runner
-- calls Progress at most once a frame, and a filter, a search or a selection never touches a case.
-- A guided run steps this window aside (its content is hidden and it takes no pointer) so the Workshop and the prompt are not covered and the
-- pointer cannot land on the Lab; it comes back when the run ends. Closing the window (or Esc) stops a run in progress.
-- Esc closes it through UISpecialFrames, never through the game menu's handler list.

local R = TwichUI
local TL = R.TestLab
local RN, RP, V, K = TL.Runner, TL.Report, TL.View, TL.Kit
local W = {}
TL.Window = W

local NAME = "TwichUITestLabWindow"
local MAX_W, MAX_H, MIN_W, MIN_H = 1280, 780, 940, 600
local PAD, HEADER_H = 14, 54
local SIDE_W, DETAIL_W, CARD_H, TOOL_H, ROW_H, HEAD_H = 252, 318, 68, 36, 30, 28   -- SIDE_W and DETAIL_W narrow on a small window (Build)
local CARDS = {
    { "total", "Total cases", "stack", "Every case in this run, chosen from the groups on the left.", "Total" },
    { "pass", "Passed", "check", "Cases whose every check held.", "Passed" },
    { "fail", "Failed", "cross", "Cases with at least one failed check. Their evidence is in the details.", "Failed" },
    { "skipped", "Skipped", "skip", "Cases that ended themselves as skipped (something they need is missing here), or a guided step you skipped.", "Skipped" },
    { "error", "Errors", "shield", "Cases that raised a Lua error before they finished.", "Errors" },
    { "timeout", "Timeouts", "warn", "Cases that did not finish within their own time budget; the Lab stopped waiting at a yield point.", "Timeout" },
    { "duration", "Duration", "hourglass", "How long the run took (while it runs: so far).", "Time" },
}

local win
local narrow = false               -- a small window (Build): a narrower sidebar and details panel, no group descriptions, fewer table columns
local chosen = {}                  -- category id -> true
local chosenCases, guidedChosen = 0, false
local state = { phase = "idle", results = {}, seconds = 0 }
local pick = { id = nil, user = false }     -- the chosen result (by id) and whether the player chose it
local filter, query = "all", ""
local visible = {}                 -- the records the table shows now
local lastText, shown              -- the full report of the last run; what the report box shows (a report, or the failures excerpt)
local sig = {}                     -- what was last drawn, so a frame that changed nothing draws nothing

local function Say(text) if win then win.note:SetText(text or "") end end

---------------------------------------------------------------------------
-- The run as the View sees it
---------------------------------------------------------------------------
local function Model()
    return { phase = state.phase, results = state.results, seconds = state.seconds, ended = state.ended, chosen = chosenCases,
        guidedChosen = guidedChosen, current = state.current, at = state.at, n = state.n }
end

local function Chosen()
    local list = TL.Select(chosen)
    chosenCases, guidedChosen = #list, false
    for _, c in ipairs(list) do if c.class == "guided" then guidedChosen = true end end
end

local function Record(id)
    for _, r in ipairs(state.results) do if r.id == id then return r end end
    return nil
end

---------------------------------------------------------------------------
-- The table
---------------------------------------------------------------------------
local COL = {}   -- column x and widths, from the table's width

local function Columns()
    local w = (win.table:GetWidth() or 0)
    if w < 300 then w = 720 end   -- before the game has laid it out
    COL.status, COL.case = 12, 100
    COL.caseW = math.max(150, math.floor((w - 100 - 190) * 0.42))
    COL.showType, COL.showMsg = w >= 440, w >= 660   -- a narrow table keeps status, case and duration; the details panel has the rest
    COL.type = COL.case + COL.caseW + 6
    COL.dur = COL.showType and (COL.type + 88) or (COL.case + COL.caseW + 6)
    COL.msg = COL.dur + 84
    COL.msgW = math.max(80, w - COL.msg - 26)
end

local function Place(row)
    row.icon:ClearAllPoints(); row.icon:SetPoint("LEFT", COL.status, 0)
    row.word:ClearAllPoints(); row.word:SetPoint("LEFT", COL.status + 20, 0); row.word:SetWidth(COL.case - COL.status - 24)
    row.id:ClearAllPoints(); row.id:SetPoint("LEFT", COL.case, 0); row.id:SetWidth(COL.caseW)
    row.chip:ClearAllPoints(); row.chip:SetPoint("LEFT", COL.type, 0)
    row.dur:ClearAllPoints(); row.dur:SetPoint("LEFT", COL.dur, 0); row.dur:SetWidth(78)
    row.msg:ClearAllPoints(); row.msg:SetPoint("LEFT", COL.msg, 0); row.msg:SetWidth(COL.msgW)
end

local function Select(id, byPlayer)
    if pick.id == id then
        if byPlayer then pick.user = true end
        return
    end
    pick.id = id
    pick.user = byPlayer and true or pick.user
    win.list:Layout()
    W.Details()
end

local CHIP = { synthetic = { 0.86, 0.84, 0.80 }, client = { 0.78, 0.88, 1.0 }, guided = { 1.0, 0.84, 0.52 } }

local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    K.Hover(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.word = K.Text(row, 13, K.P.textDim)
    row.id = K.Text(row, 14, K.P.text, "strong")
    row.chip = CreateFrame("Frame", nil, row)
    row.chip:SetSize(78, 20)
    row.chip.sheet = K.CL.Sheet(row.chip, "chip", { layer = "ARTWORK", sub = 4, corner = 10 })
    row.chip.text = K.Text(row.chip, 12, K.P.text)
    row.chip.text:SetPoint("CENTER", 0, 0)
    row.chip.text:SetJustifyH("CENTER")
    row.dur = K.Text(row, 13, K.P.textDim)
    row.msg = K.Text(row, 13, K.P.textDim)
    Place(row)
    row:SetScript("OnClick", function(self) if self.rec then Select(self.rec.id, true) end end)
    row.fill = function(self, r)
        self.rec = r
        local d = V.Row(r)
        K.Status(self.icon, r.status, true)
        if r.status == "skipped" or r.status == "stopped" or r.status == "pending" then self.icon:SetSize(8, 8) else self.icon:SetSize(16, 16) end
        local tone = K.TONE[r.status] or K.TONE.pending
        self.word:SetText(d.word)
        K.Paint(self.word, tone)
        self.id:SetText(r.id)
        self.chip.text:SetText(r.status == "pending" and "" or d.kind)
        local c = CHIP[d.kindId] or CHIP.client
        self.chip.sheet:SetTint(c[1], c[2], c[3], 1)
        self.chip:SetShown(COL.showType and r.status ~= "pending")
        self.dur:SetText(d.duration)
        self.msg:SetShown(COL.showMsg)
        self.msg:SetText(d.message)
        K.Paint(self.msg, r.status == "fail" and K.P.text or K.P.textDim)
        self:SetSelected(r.id == pick.id)
    end
    return row
end

---------------------------------------------------------------------------
-- Relisting: the filter and the search over the run's records (never over the cases)
---------------------------------------------------------------------------
local function Chips()
    local counts = V.Counts(state.results)
    local avail = (win.chipRow:GetWidth() or 700)
    local function Lay(pad)
        local x = 0
        for i, f in ipairs(V.FILTERS) do
            local chip = win.chips[f.id]
            local n = counts[f.id] or 0
            local on = i <= V.ALWAYS or n > 0 or filter == f.id   -- the extra ones (skipped, errors, ...) appear when the run has some
            chip:SetShown(on)
            if on then
                local text = ("%s (%d)"):format(f.label, n)
                if chip.shownText ~= text then chip.shownText = text; chip:SetLabel(text) end
                chip:SetWidth(math.ceil(chip.text:GetStringWidth() or 60) + pad)
                chip:ClearAllPoints()
                chip:SetPoint("LEFT", win.chipRow, "LEFT", x, 0)
                x = x + chip:GetWidth() + 6
                chip:SetOn(filter == f.id)
            end
        end
        return x
    end
    local x = Lay(28)
    if avail - x - 10 < 170 then x = Lay(16) end   -- many chips (a run with every kind of outcome): tighter, so the search keeps its room
    win.search:SetWidth(math.max(120, math.min(280, avail - x - 10)))
    return counts
end

local function Relist()
    visible = V.Select(state.results, filter, query)
    local m = Model()
    local empty = V.Empty(m, filter, query, #visible)
    win.list:SetData(visible, empty)
    -- a run that has not started shows the sentence in the table; a run in progress keeps the player's place unless nothing was chosen
    if state.phase == "running" and not pick.user and filter == "all" and state.at and state.at <= #visible then win.list:ScrollTo(state.at) end
end

---------------------------------------------------------------------------
-- The details of the chosen result
---------------------------------------------------------------------------
local function Flow(det)
    det.heads, det.bodies = det.heads or {}, det.bodies or {}
    det.used = { 0, 0 }
end

local function Block(det, kind, text, color, gap)
    local pool = kind == "head" and det.heads or det.bodies
    local i = (kind == "head" and 1 or 2)
    det.used[i] = det.used[i] + 1
    local fs = pool[det.used[i]]
    if not fs then
        if kind == "head" then fs = K.Text(det.content, 16, K.P.bronzeText, "serif")
        else fs = K.Text(det.content, 13, K.P.textDim); fs:SetWordWrap(true); fs:SetJustifyV("TOP") end
        pool[det.used[i]] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", det.content, "TOPLEFT", 4, -det.y - (gap or 0))
    fs:SetWidth(det.innerW)
    fs:SetText(text)
    K.Paint(fs, color or (kind == "head" and K.P.bronzeText or K.P.textDim))
    fs:Show()
    local h = fs:GetStringHeight() or 0
    if h < 1 then   -- no layout yet (the offline tests): a line is 15 units, a heading 20
        local lines = 1
        for _ in text:gmatch("\n") do lines = lines + 1 end
        h = kind == "head" and 20 or math.max(lines, math.ceil(#text * 6.4 / det.innerW)) * 15
    end
    det.y = det.y + (gap or 0) + h
    return fs
end

function W.Details()
    if not win then return end
    local det = win.det
    local rec = pick.id and Record(pick.id) or nil
    if not rec then
        det.id:SetText("")
        det.icon:Hide(); det.sub:SetText(""); det.outcome:SetText("")
        det.box:Hide(); det.scroll:Hide()
        det.empty:Show()
        det.empty:SetText(#state.results == 0 and "Run the cases, then choose a row to see what that case recorded."
            or "Choose a row in the table to see its details: the evidence the case recorded, its checks and its time.")
        det.sigText = nil
        return
    end
    local d = V.Details(rec)
    local key = table.concat({ d.id, d.status, tostring(d.headline), #d.notes, #d.facts, tostring(d.ms) }, "|")
    if det.sigText == key then return end
    det.sigText = key
    det.empty:Hide()
    local tone = K.TONE[d.status] or K.TONE.pending
    det.icon:Show(); K.Status(det.icon, d.status, false)
    if d.status == "skipped" or d.status == "stopped" or d.status == "pending" then det.icon:SetSize(12, 12) else det.icon:SetSize(30, 30) end
    det.id:SetText(d.id)
    det.sub:SetText(d.kindWord .. " case")
    det.outcome:SetText(d.word:upper())
    K.Paint(det.outcome, tone)
    det.box:Show(); det.scroll:Show()
    det.tint:SetColorTexture(tone[1] * 0.6, tone[2] * 0.6, tone[3] * 0.6, d.status == "pass" and 0.10 or 0.22)
    det.line:SetColorTexture(tone[1], tone[2], tone[3], 0.6)
    det.headline:SetText(d.headline)
    local hh = det.headline:GetStringHeight() or 0
    if hh < 1 then hh = math.ceil(#d.headline * 6.6 / 250) * 16 end
    det.box:SetHeight(hh + 22)
    -- the scrolling part
    Flow(det)
    det.y = 0
    det.innerW = math.max(120, (det.scroll:GetWidth() or (DETAIL_W - 50)) - 14)
    if d.body then Block(det, "body", d.body, K.P.text) end
    if #d.fails > 1 then
        Block(det, "head", ("Failed checks (%d)"):format(#d.fails), nil, det.y > 0 and 10 or 0)
        local lines = {}
        for _, f in ipairs(d.fails) do lines[#lines + 1] = "\226\128\162 " .. f end
        Block(det, "body", table.concat(lines, "\n"), K.P.text, 2)
    end
    if d.hidden then Block(det, "body", ("%d more failed %s not recorded: a case keeps its first 8."):format(d.hidden, d.hidden == 1 and "check was" or "checks were"), K.TONE.timeout, 4) end
    Block(det, "head", "Evidence", nil, det.y > 0 and 10 or 0)
    local ev = { "\226\128\162 " .. d.kindWord .. ": " .. d.kindNote }
    if d.duration ~= "" then ev[#ev + 1] = "\226\128\162 Duration: " .. d.duration end
    if d.checks and d.checks > 0 then ev[#ev + 1] = ("\226\128\162 Checks made: %d"):format(d.checks) end
    for _, seed in ipairs(d.seeds) do ev[#ev + 1] = "\226\128\162 Seed named in the evidence: " .. seed end
    Block(det, "body", table.concat(ev, "\n"), K.P.text, 2)
    if #d.notes > 0 then
        Block(det, "head", ("Evidence lines (%d)"):format(#d.notes), nil, 10)
        local lines = {}
        for _, n in ipairs(d.notes) do lines[#lines + 1] = "\226\128\162 " .. n end
        Block(det, "body", table.concat(lines, "\n"), K.P.text, 2)
    end
    if #d.facts > 0 then
        Block(det, "head", "Recorded facts", nil, 10)
        local lines = {}
        for _, f in ipairs(d.facts) do lines[#lines + 1] = "\226\128\162 " .. f[1] .. " = " .. f[2] end
        if d.moreFacts then lines[#lines + 1] = ("... and %d more in the report"):format(d.moreFacts) end
        Block(det, "body", table.concat(lines, "\n"), K.P.text, 2)
    end
    for i = det.used[1] + 1, #det.heads do det.heads[i]:Hide() end
    for i = det.used[2] + 1, #det.bodies do det.bodies[i]:Hide() end
    det.content:SetHeight(math.max(1, det.y + 8))
    det.content:SetWidth(math.max(1, (det.scroll:GetWidth() or 200) - 2))
    if det.fit then det.fit(det.y + 8) end
    det.scroll:SetVerticalScroll(0)
end

---------------------------------------------------------------------------
-- Drawing what the runner reports
---------------------------------------------------------------------------
local function Buttons()
    local running = RN.Active()
    local failures = RN.last and (RN.last.counts.fail + RN.last.counts.error + RN.last.counts.timeout) or 0
    win.run:SetEnabled(not running and chosenCases > 0)
    win.stop:SetEnabled(running)
    win.copy:SetEnabled(not running and RN.last ~= nil)
    win.copyFail:SetEnabled(not running and RN.last ~= nil and failures > 0)
    for _, box in pairs(win.boxes) do box:SetActive(not running) end
end

-- cards, run state, chips and progress: only what changed is written
local function Header(m)
    local cards = V.Cards(m)
    for key, card in pairs(win.cards) do
        local c = cards[key]
        local s = table.concat({ c.value, c.tone, tostring(c.lit), tostring(c.note) }, "|")
        if card.sig ~= s then
            card.sig = s
            card:Set(c.value, K.TONE[c.tone] or K.P.stone, c.note, c.lit)
        end
    end
    local st = V.State(m)
    local s = st.text .. "|" .. st.detail .. "|" .. st.tone
    if sig.state ~= s then
        sig.state = s
        win.stateText:SetText(st.text)
        K.Paint(win.stateText, K.TONE[st.tone] or K.P.text)
        win.stateDetail:SetText(st.detail)
    end
end

-- what a frame changed, counted without making anything: the cases finished, the running one, the ones that did not pass
local function Stamp(results)
    local finished, running, bad = 0, 0, 0
    for i = 1, #results do
        local st = results[i].status
        if st == "running" then running = i
        elseif st ~= "pending" and st ~= "stopped" then
            finished = finished + 1
            if st == "fail" or st == "error" or st == "timeout" then bad = bad + 1 end
        end
    end
    return finished, running, bad
end

-- A frame that finished no case only moves the clock (at most ten times a second); one that did redraws the cards, the state, the bar, the chips,
-- the table and the details. Nothing is rebuilt for a filter, a search or a selection: those call Relist and Details themselves.
local function Refresh(force)
    local finished, running, bad = Stamp(state.results)
    local n = #state.results
    local changed = force or sig.phase ~= state.phase or sig.n ~= n or sig.finished ~= finished or sig.running ~= running or sig.bad ~= bad
    local tick = math.floor((tonumber(state.seconds) or 0) * 10)
    if not changed and (state.phase ~= "running" or sig.tick == tick) then return end
    sig.phase, sig.n, sig.finished, sig.running, sig.bad, sig.tick = state.phase, n, finished, running, bad, tick
    Header(Model())
    if changed then
        win.meter:SetFraction(state.phase == "idle" and 0 or (n > 0 and finished / n or 0))
        Chips()
        Relist()
        W.Details()
        Buttons()
    end
end

local function Progress(p)
    if not (win and p) then return end
    state.phase, state.results, state.seconds, state.at, state.n = "running", p.results, p.seconds, p.at, p.n
    state.current = p.results[p.at]
    Refresh()
end

-- the window steps aside for a guided run: nothing of it can take the pointer, and the Workshop and the prompt are not covered
local function Peek(on)
    if not win or win.peek == on then return end
    win.peek = on
    win.content:SetShown(not on)
    win.shell:SetShown(not on)
    win:EnableMouse(not on)
end
W.Peek = Peek

local function SetReport(text)
    shown = text
    win.edit:SetText(text)
    win.edit:SetCursorPosition(0)
    -- a multi-line box in a scroll frame sizes its own height from its text; where it has not (no layout yet) it is given one, so the text can show
    if (win.edit:GetHeight() or 0) < 20 then
        local lines = 1
        for _ in text:gmatch("\n") do lines = lines + 1 end
        win.edit:SetHeight(lines * 15 + 8)
    end
    if win.reportFit then win.reportFit(win.edit:GetHeight() or 0) end
end

local function Done(sum)
    if not win then return end
    Peek(false)
    state.phase = sum.ended == "complete" and "finished" or "stopped"
    state.results, state.seconds, state.ended, state.current = sum.results, sum.seconds, sum.ended, nil
    lastText = RP.Build(sum)
    SetReport(lastText)
    win.reportTitle:SetText("Report")
    -- a failure is shown at once, unless the player has chosen another result
    if not pick.user then
        local problem = V.FirstProblem(sum.results)
        if problem then pick.id = problem.id end
    end
    local c = sum.counts
    if sum.ended == "complete" then
        Say(c.fail + c.error + c.timeout == 0 and "Every case that ran passed." or "Some cases did not pass. The first one is chosen; Copy failures selects their evidence.")
    else
        Say("Stopped. No further step was started. A step already running could not have been interrupted; the report says what ran.")
    end
    Refresh(true)
    local rec = pick.id and Record(pick.id)
    if rec then
        for i, r in ipairs(visible) do if r == rec then win.list:ScrollTo(i) break end end
    end
    Buttons()
end
W.OnProgress, W.OnDone = Progress, Done   -- for the simulator scenario, which hands the window recorded results

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function W.Run()
    local list = TL.Select(chosen)
    if #list == 0 then Say("Choose at least one group.") return false end
    local cats = {}
    for _, id in ipairs(TL.categoryOrder) do if chosen[id] then cats[#cats + 1] = id end end
    local asks = false
    for _, c in ipairs(list) do if c.class == "guided" then asks = true end end
    local ok, why = RN.Start(list, { cats = cats, onProgress = Progress, onDone = Done })
    if not ok then
        Say(why == "combat" and "Not during combat. Try again when combat ends." or "It cannot start now (" .. tostring(why) .. ").")
        return false
    end
    lastText, pick.id, pick.user = nil, nil, false
    state = { phase = "running", results = {}, seconds = 0 }
    SetReport("The report is written when the run ends.")
    win.reportTitle:SetText("Report")
    Say(asks and "Running. This window steps aside until the run ends so the prompt and the Workshop are not covered. Cancel on the prompt ends it and removes the key."
        or "Running. Stop is available; it prevents further steps but cannot interrupt one that is running.")
    Refresh(true)
    Buttons()
    if asks then Peek(true) end
    return true
end

function W.Stop() return RN.Stop("user") end

local function Offer(text, title, what)
    SetReport(text)
    win.reportTitle:SetText(title)
    win.edit:SetFocus()
    win.edit:HighlightText()
    Say(("%s selected (%d characters): press Ctrl+C, then paste it where it is needed."):format(what, #text))
end

function W.Copy()
    if not lastText then Say("There is no report yet: run the cases first.") return false end
    Offer(lastText, "Report", "Report")
    return true
end

function W.CopyFailures()
    local sum = RN.last
    if not (sum and lastText) then Say("There is no report yet: run the cases first.") return false end
    local text, n = RP.BuildFailures(sum)
    if n == 0 then Say("Nothing to copy: no case failed, raised an error or timed out in the last run.") return false end
    Offer(text, ("Failures (%d)"):format(n), ("The %d %s that did not pass,"):format(n, n == 1 and "case" or "cases"))
    return true
end

-- the table's filter and search (also what the chips and the field call)
function W.SetFilter(id)
    if not win.chips[id] then return false end
    filter = id
    Chips(); Relist()
    return true
end

function W.SetQuery(text)
    query = tostring(text or "")
    if win.search:GetText() ~= query then win.search:SetText(query) end
    Relist()
end

function W.Select(id) if Record(id) then Select(id, true) return true end return false end

-- what the window is showing, for the tests and the simulator scenario (read only)
function W.Snapshot()
    return { phase = state.phase, filter = filter, query = query, rows = #visible, total = #state.results, selected = pick.id, byPlayer = pick.user,
        peek = win and win.peek or false, chosen = chosenCases }
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Band(frame)
    local CL = K.CL
    CL.Tile(frame, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 })
    CL.Tile(frame, "BACKGROUND", -3, "warm", 0.04, { 0.70, 0.83, 0.96 })
    CL.QuietTile(frame, "header", "BACKGROUND", -2)
end

local function Scroller(parent, child)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local bar = sf.ScrollBar
    if type(bar) == "table" and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, -16)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 16)
    end
    local fit = K.CL.ScrollRail(sf)
    local content = child or CreateFrame("Frame", nil, sf)
    if not child then content:SetSize(10, 10) end
    sf:SetScrollChild(content)
    return sf, content, fit
end

local function BuildShell()
    local F, CL, L = K.F, K.CL, K.L
    local RL, RT, RR = F.RailInsets()
    win.shell = F.Shell(win, { below = true, follow = true })
    if win.shell.grain then win.shell.grain:Hide() end
    CL.Tile(win.shell, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 }):SetAllPoints(win.shell.interior)
    CL.QuietTile(win.shell, "outer", "BACKGROUND", -3):SetAllPoints(win.shell.interior)
    CL.LegacyRails(win.shell, false)
    win.frameArt = CL.Frame(win.shell)
    F.FadeIn(win)

    local content = CreateFrame("Frame", nil, win)
    content:SetAllPoints(win)
    win.content = content

    local header = CreateFrame("Frame", nil, content)
    header:SetPoint("TOPLEFT", RL, -RT)
    header:SetPoint("TOPRIGHT", -RR, -RT)
    header:SetHeight(HEADER_H - 4)
    Band(header)
    win.shell:Sheen():Place(header, 0, 0, 0, 0)
    win.shell:Groove():Place(header, "BOTTOM", 0, 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    win.header = header
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(38, 38)
    crest:SetPoint("LEFT", 14, 0)
    crest:SetTexture(R.ICON)
    local brand = K.Text(header, 26, K.P.text, "serif")
    brand:SetPoint("LEFT", crest, "RIGHT", 10, 1)
    brand:SetText("TwichUI")
    local title = K.Text(header, 26, K.P.bronzeText, "serif")
    title:SetPoint("LEFT", brand, "RIGHT", 8, 0)
    title:SetText("Test Lab")
    local bar = L.Solid(header, "ARTWORK", K.P.bronzeLo, 0.9)
    bar:SetSize(1, 22); bar:SetPoint("LEFT", title, "RIGHT", 16, 0)
    local tag = K.Text(header, 15, K.P.textDim, "serif")
    tag:SetPoint("LEFT", bar, "RIGHT", 16, 0)
    tag:SetText("development tools and verification")
    local dev = CreateFrame("Frame", nil, header)
    dev:SetSize(96, 26)
    dev:SetPoint("LEFT", tag, "RIGHT", 18, 0)
    dev:EnableMouse(true)
    dev.sheet = CL.Sheet(dev, "chip", { layer = "ARTWORK", sub = 4, corner = 12 })
    dev.sheet:SetTint(1.0, 0.82, 0.48, 1)
    dev.text = K.Text(dev, 13, K.P.bronzeText)
    dev.text:SetPoint("CENTER"); dev.text:SetJustifyH("CENTER"); dev.text:SetText("Dev only")
    K.Tip(dev, "Development only", "Version " .. TL.VERSION .. ". The Test Lab is never part of a release: it runs selected TwichUI checks in this client and writes a report to copy.")
    win.close = F.Close(header, function() win:Hide() end)
    win.close:SetSize(28, 28)
    CL.Control(win.close)
    CL.Font(win.close.text, 16, true)
    win.close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    K.Tip(win.close, "Close", "Closes the Test Lab. A run in progress is stopped; no further step is started.")
    return RL, RT, RR
end

local function BuildSide(top, bottom)
    local L = K.L
    local side = CreateFrame("Frame", nil, win.content)
    side:SetPoint("TOPLEFT", PAD, -top)
    side:SetPoint("BOTTOMLEFT", PAD, bottom)
    side:SetWidth(SIDE_W)
    K.Panel(side, "espresso")
    win.side = side
    local h = K.Text(side, 24, K.P.text, "serif")
    h:SetPoint("TOPLEFT", 18, -16); h:SetText("What to run")
    local sub = K.Text(side, 13, K.P.textDim)
    sub:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
    sub:SetText(narrow and "Select groups to run." or "Select the test groups to run.")
    local rule = K.Rule(side, 0.7)
    rule:SetPoint("TOPLEFT", 14, -66); rule:SetPoint("TOPRIGHT", -14, -66)
    local sf, content, fit = Scroller(side)
    sf:SetPoint("TOPLEFT", 8, -74)
    sf:SetPoint("BOTTOMRIGHT", -20, 8)
    win.boxes, win.entries = {}, {}
    local innerW = SIDE_W - 28 - 12
    local y = 0
    for _, cat in ipairs(V.Categories()) do
        local id = cat.id
        chosen[id] = not cat.guided   -- a guided category asks things of the player: it is never ticked for them
        local entry = CreateFrame("Button", nil, content)
        K.Hover(entry)
        entry:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        entry:SetWidth(innerW + 12)
        local box = K.Check(entry, 22, function(on) chosen[id] = on; win.boxes[id]:SetChecked(on); W.Chose() end)
        box:SetPoint("TOPLEFT", 8, -8)
        box:SetChecked(chosen[id])
        local name = K.Text(entry, 15, K.P.text, "strong")
        name:SetPoint("TOPLEFT", box, "TOPRIGHT", 10, 0)
        name:SetWidth(narrow and innerW - 44 or innerW - 44 - 40)
        name:SetWordWrap(true)
        name:SetJustifyV("TOP")
        name:SetText(narrow and ("%s (%d)"):format(cat.label, cat.count) or cat.label)   -- a narrow sidebar has no column for the count
        local count = K.Text(entry, 14, K.P.textDim)
        count:SetPoint("TOPRIGHT", entry, "TOPRIGHT", -8, -1)
        count:SetJustifyH("RIGHT"); count:SetWidth(40)
        count:SetText(("(%d)"):format(cat.count))
        if narrow then count:Hide() end
        local blurb = K.Text(entry, 13, K.P.textDim)
        if narrow then blurb:Hide() end
        blurb:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
        blurb:SetWidth(innerW - 44)
        blurb:SetWordWrap(true)
        blurb:SetJustifyV("TOP")
        local text = cat.blurb:sub(1, 1):upper() .. cat.blurb:sub(2)
        if cat.guided then text = (text ~= "" and (text .. " ") or "") .. "Asks for you, so it is never ticked for you." end
        blurb:SetText(text)
        local bh = blurb:GetStringHeight() or 0
        if bh < 1 then bh = math.ceil((#blurb:GetText() * 6.4) / (innerW - 44)) * 15 end
        local nh = name:GetStringHeight() or 0
        if nh < 1 then nh = math.ceil(#cat.label * 8.4 / (narrow and innerW - 44 or innerW - 84)) * 19 end
        if narrow then bh = 0 end
        local eh = 8 + math.max(20, nh) + (narrow and 0 or 4) + bh + 12
        if narrow then K.Tip(entry, cat.label, text) end
        entry:SetHeight(eh)
        entry:SetScript("OnClick", function() box:GetScript("OnClick")(box) end)   -- the whole entry is the hit area; the check ignores it during a run
        win.boxes[id], win.entries[id] = box, entry
        y = y + eh + 2
        entry.catName = name
    end
    content:SetWidth(innerW + 12)
    content:SetHeight(math.max(1, y))
    if fit then fit(y) end
    -- the watermark crest, faint, at the foot of the panel
    local mark = side:CreateTexture(nil, "BACKGROUND", nil, 3)
    mark:SetTexture(R.ICON)
    mark:SetSize(84, 84)
    mark:SetPoint("BOTTOM", 0, 14)
    mark:SetAlpha(0.06)
end

local function BuildTop(main)
    local L = K.L
    -- the seven cards
    win.cards = {}
    for i, def in ipairs(CARDS) do
        local card = K.Card(main, 100, CARD_H, (def[3] == "check" or def[3] == "cross") and "stack" or def[3], def[2], def[1])
        win.cards[def[1]] = card
        card.def = def
        card:EnableMouse(true)
        K.Tip(card, def[2], def[4])
    end
    K.CL.Font(win.cards.duration.value, 20, false, "serif")   -- a time is longer than a count
    local function LayoutCards()
        local w = main:GetWidth() or 700
        local gap = 8
        local cw = math.floor((w - gap * 6) / 7)
        for i, def in ipairs(CARDS) do
            local c = win.cards[def[1]]
            c:SetCompact(cw < 122, def[5])
            c:SetWidth(cw)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", main, "TOPLEFT", (i - 1) * (cw + gap), 0)
        end
    end
    LayoutCards()
    main:HookScript("OnSizeChanged", LayoutCards)

    -- the action bar
    local y = CARD_H + 10
    local function Bar(label, w, kind, onClick, glyph, tipTitle, tipBody)
        local b = K.Button(main, label, w, kind, onClick, TOOL_H, glyph)
        K.Tip(b, tipTitle, tipBody)
        return b
    end
    local bw = narrow and { 96, 84, 134, 146 } or { 124, 112, 160, 168 }
    win.run = Bar("Run", bw[1], "primary", function() W.Run() end, "play", "Run", "Runs the chosen groups, one case after another, spread over frames. A guided group is only run when you tick it.")
    win.run:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -y)
    win.stop = Bar("Stop", bw[2], "secondary", function() W.Stop() end, "stop", "Stop", "No further step is started. A step that is already running cannot be interrupted; the report says what ran.")
    win.stop:SetPoint("LEFT", win.run, "RIGHT", 10, 0)
    win.copy = Bar("Copy report", bw[3], "secondary", function() W.Copy() end, "doc", "Copy report", "Selects the whole report in the box below; press Ctrl+C, then paste it. The game gives addons no clipboard.")
    win.copy:SetPoint("LEFT", win.stop, "RIGHT", 10, 0)
    win.copyFail = Bar("Copy failures", bw[4], "secondary", function() W.CopyFailures() end, "doc", "Copy failures", "Selects only the cases that failed, raised an error or timed out, with their evidence; press Ctrl+C. Available when the last run had some.")
    win.copyFail:SetPoint("LEFT", win.copy, "RIGHT", 10, 0)
    win.stateText = K.Text(main, narrow and 16 or 20, K.P.text, "serif")
    win.stateText:SetPoint("TOPLEFT", win.copyFail, "TOPRIGHT", narrow and 14 or 22, narrow and 2 or 4)
    win.stateText:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    win.stateDetail = K.Text(main, 13, K.P.textDim)
    win.stateDetail:SetPoint("TOPLEFT", win.stateText, "BOTTOMLEFT", 0, -1)
    win.stateDetail:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    win.note = K.Text(main, 12, K.P.stone)
    win.note:SetPoint("TOPLEFT", main, "TOPLEFT", 2, -(y + TOOL_H + 3))
    win.note:SetPoint("RIGHT", main, "RIGHT", 0, 0)
    win.note:SetWordWrap(false)
    -- the progress bar
    y = y + TOOL_H + 20
    win.meter = K.Meter(main, 400, 12)
    win.meter:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -y)
    win.meter:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -y)
    return y + 12
end

local function BuildMiddle(main, y)
    local L = K.L
    -- the filters and the search
    win.chipRow = CreateFrame("Frame", nil, main)
    win.chipRow:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -(y + 12))
    win.chipRow:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -(y + 12))
    win.chipRow:SetHeight(28)
    win.chips = {}
    for _, f in ipairs(V.FILTERS) do
        local chip = K.Segment(win.chipRow, f.label, 90, function() W.SetFilter(f.id) end)
        win.chips[f.id] = chip
        K.Tip(chip, f.label, f.id == "all" and "Every case in the run." or "Filters the table only. It never changes which cases are chosen to run, and it keeps the report and your selection.")
    end
    win.search = K.Search(win.chipRow, 250, 28, "Find a case...")
    win.search:SetPoint("RIGHT", win.chipRow, "RIGHT", 0, 0)
    win.search:SetScript("OnEscapePressed", function(box) if box:GetText() ~= "" then box:SetText("") else box:ClearFocus() end end)
    win.search:SetScript("OnEnterPressed", function(box) box:ClearFocus() end)
    win.search:HookScript("OnTextChanged", function(box) if box:GetText() ~= query then query = box:GetText(); Relist() end end)

    -- the report, at the foot
    local reportH = (win:GetHeight() or MAX_H) < 680 and 130 or 172
    local report = CreateFrame("Frame", nil, main)
    report:SetPoint("BOTTOMLEFT", main, "BOTTOMLEFT", 0, 0)
    report:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
    report:SetHeight(reportH)
    K.Panel(report, "card")
    win.report = report
    win.reportTitle = K.Text(report, 20, K.P.bronzeText, "serif")
    win.reportTitle:SetPoint("TOPLEFT", 16, -10)
    win.reportTitle:SetText("Report")
    local legend = K.Text(report, 13, K.P.textDim)
    legend:SetPoint("LEFT", win.reportTitle, "RIGHT", 22, -1)
    legend:SetPoint("RIGHT", report, "RIGHT", -14, 0)
    legend:SetText("Synthetic: our code on made-up data   |   Client: observed in this game   |   Guided: with your help")
    local well = CreateFrame("Frame", nil, report)
    well:SetPoint("TOPLEFT", 10, -38)
    well:SetPoint("BOTTOMRIGHT", -10, 10)
    K.Panel(well, "canvas")
    local edit = CreateFrame("EditBox", nil, well)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall")
    pcall(K.CL.Font, edit, 13)
    edit:SetWidth(700); edit:SetTextInsets(4, 4, 2, 2)
    edit:SetJustifyH("LEFT"); edit:SetJustifyV("TOP")
    local sf, _, fit = Scroller(well, edit)
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -20, 6)
    win.reportFit = fit
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    edit:SetScript("OnTextChanged", function(e, user)   -- for reading and copying: typing puts the text back
        if user then e:SetText(shown or ""); e:HighlightText() end
        if fit then fit(e:GetHeight() or 0) end
    end)
    sf:HookScript("OnSizeChanged", function(self, w) if w and w > 20 then edit:SetWidth(w - 4) end end)
    win.edit = edit

    -- the table and the details
    local detail = CreateFrame("Frame", nil, main)
    detail:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -(y + 52))
    detail:SetPoint("BOTTOMRIGHT", report, "TOPRIGHT", 0, 8)
    detail:SetWidth(DETAIL_W)
    K.Panel(detail, "card")
    win.detail = detail

    local tbl = CreateFrame("Frame", nil, main)
    tbl:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -(y + 52))
    tbl:SetPoint("BOTTOMLEFT", report, "TOPLEFT", 0, 8)
    tbl:SetPoint("RIGHT", detail, "LEFT", -10, 0)
    K.Panel(tbl, "card")
    win.table = tbl
    local head = CreateFrame("Frame", nil, tbl)
    head:SetPoint("TOPLEFT", 4, -4); head:SetPoint("TOPRIGHT", -4, -4)
    head:SetHeight(HEAD_H)
    win.head = {}
    for _, h in ipairs({ { "status", "Status" }, { "case", "Case" }, { "type", "Type" }, { "dur", "Duration" }, { "msg", "Message" } }) do
        local t = K.Text(head, 13, K.P.textDim, "strong")
        t:SetText(h[2])
        win.head[h[1]] = t
    end
    local line = K.Rule(tbl, 0.8)
    line:SetPoint("TOPLEFT", 8, -(HEAD_H + 6)); line:SetPoint("TOPRIGHT", -8, -(HEAD_H + 6))
    win.list = K.List(tbl, ROW_H, MakeRow, ROW_H * 6, false)
    win.list.box:SetPoint("TOPLEFT", tbl, "TOPLEFT", 4, -(HEAD_H + 8))
    win.list.box:SetPoint("BOTTOMRIGHT", tbl, "BOTTOMRIGHT", -4, 5)
    local function Heads()
        Columns()
        local pos = { status = COL.status, case = COL.case, type = COL.type, dur = COL.dur, msg = COL.msg }
        for key, t in pairs(win.head) do
            t:ClearAllPoints(); t:SetPoint("LEFT", head, "LEFT", pos[key] + 0, 0)
            t:SetShown((key ~= "type" or COL.showType) and (key ~= "msg" or COL.showMsg))
        end
        for _, row in ipairs(win.list.rows) do Place(row) end
    end
    tbl:HookScript("OnSizeChanged", function() Heads(); win.list:Layout() end)
    Columns(); Heads()

    -- the details panel
    local det = win.det or {}
    win.det = det
    det.icon = detail:CreateTexture(nil, "OVERLAY")
    det.icon:SetPoint("TOPLEFT", 16, -16)
    det.id = K.Text(detail, 18, K.P.text, "serif")
    det.id:SetPoint("TOPLEFT", det.icon, "TOPRIGHT", 10, 1)
    det.id:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    det.sub = K.Text(detail, 14, K.P.textDim)
    det.sub:SetPoint("TOPLEFT", det.id, "BOTTOMLEFT", 0, -3)
    det.outcome = K.Text(detail, 14, K.P.text, "strong")
    det.outcome:SetPoint("LEFT", det.sub, "RIGHT", 10, 0)
    det.box = CreateFrame("Frame", nil, detail)
    det.box:SetPoint("TOPLEFT", 12, -62)
    det.box:SetPoint("TOPRIGHT", -12, -62)
    det.box:SetHeight(40)
    K.Panel(det.box, "espresso")
    det.tint = L.Solid(det.box, "ARTWORK", K.P.text, 0.1)
    det.tint:SetDrawLayer("ARTWORK", 3)
    det.tint:SetPoint("TOPLEFT", 3, -3); det.tint:SetPoint("BOTTOMRIGHT", -3, 3)
    det.line = L.Solid(det.box, "OVERLAY", K.P.text, 0.6)
    det.line:SetPoint("TOPLEFT", 4, -4); det.line:SetPoint("BOTTOMLEFT", 4, 4); det.line:SetWidth(3)
    det.headline = K.Text(det.box, 14, K.P.text)
    det.headline:SetPoint("TOPLEFT", 14, -10)
    det.headline:SetWidth(DETAIL_W - 24 - 24)
    det.headline:SetWordWrap(true)
    det.headline:SetJustifyV("TOP")
    local sf, content, fit = Scroller(detail)
    sf:SetPoint("TOPLEFT", det.box, "BOTTOMLEFT", 2, -10)
    sf:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -24, 10)
    det.scroll, det.content, det.fit = sf, content, fit
    det.empty = K.Text(detail, 14, K.P.textDim)
    det.empty:SetPoint("TOPLEFT", 18, -20)
    det.empty:SetPoint("RIGHT", detail, "RIGHT", -18, 0)
    det.empty:SetWordWrap(true)
    det.empty:SetJustifyV("TOP")
end

local function Build()
    K.Init()
    local L = K.L
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local w = math.max(MIN_W, math.min(MAX_W, (type(sw) == "number" and sw > 0 and sw or 1920) - 60))
    narrow = w < 1100
    if narrow then SIDE_W, DETAIL_W = 190, 270 end   -- a small window gives the table the room
    local h = math.max(MIN_H, math.min(MAX_H, (type(sh) == "number" and sh > 0 and sh or 1080) - 60))
    win = CreateFrame("Frame", NAME, UIParent)
    win:SetSize(w, h)
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
    win:HookScript("OnShow", function(self) if R.FitToScreen then R.FitToScreen(self) end end)
    tinsert(UISpecialFrames, NAME)
    local RL, RT, RR = BuildShell()
    local F = K.F
    local _, _, _, RB = F.RailInsets()
    local top = RT + HEADER_H + 10
    local bottom = PAD + (RB or 0)
    BuildSide(top, bottom)
    local main = CreateFrame("Frame", nil, win.content)
    main:SetPoint("TOPLEFT", win.content, "TOPLEFT", PAD + SIDE_W + 10, -top)
    main:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", -PAD, bottom)
    win.main = main
    local y = BuildTop(main)
    BuildMiddle(main, y)
    Chosen()
    state.results = {}
    SetReport("No report yet. Choose groups and press Run; the report is written when the run ends.")
    Refresh(true)
    Buttons()
    return win
end

-- a group was ticked or cleared
function W.Chose()
    Chosen()
    Refresh(true)
    Buttons()
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
