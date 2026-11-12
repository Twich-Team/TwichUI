-- Simulator lab scenario: the Test Lab window (TwichUI_TestLab), loaded the way the game loads it (C_AddOns.LoadAddOn) and handed SYNTHETIC
-- RECORDED RESULTS, so every state of the window can be drawn and photographed. Run by tools/simlab/testlab.sh, which puts scenarios/lib.lua and
-- TwichUI_TestLab/Reach.lua in front of this file and sets SIMLAB_PARAMS = { view = ... }.
--
-- WHAT IS REAL: the Test Lab's files (Kit, View, Window, Runner's own records shape, Report, Guided), the case registry (the real case ids and
-- categories), the window's frames and controls, the core's shared looks.
-- WHAT IS FAKE: every result. The window is given recorded results through Window.OnProgress / OnDone, as the runner would; no case runs, nothing
-- is measured, and no failure here says anything about TwichUI. The failing case's text is the message the first real-client run printed
-- (2026-11-12), used as sample wording.
-- NOT COVERED: real pointer, keyboard, focus, the clipboard, how anything looks in the game (addon fonts are drawn in Friz Quadrata here).
--
-- views: idle running allpass mixed (a failure chosen, its details shown) failfilter problems long guided small
local R = TwichUI
local Check = Lab.Check
local params = rawget(_G, "SIMLAB_PARAMS") or {}
local view = params.view or "mixed"

A_Admin.SetManualClock(GetTime())
Lab.Solo()

local TL, V, W, RN, win

local function Txt(fs) return fs and fs:GetText() or "" end

---------------------------------------------------------------------------------------------------------------------------
-- Recorded results (hand-made; the real registry's ids)
---------------------------------------------------------------------------------------------------------------------------
local function Records(n)
    local out = {}
    if n then
        for i = 1, n do
            local kind = i % 9 == 0 and "client" or (i % 11 == 0 and "guided" or "synthetic")
            out[i] = { id = ("synthetic.case.%03d"):format(i), cat = "core", class = kind == "synthetic" and "pure" or (kind == "guided" and "guided" or "readonly"),
                label = kind, status = "pass", ms = (i * 37 % 91) / 10, facts = {}, checks = 2 + i % 5 }
        end
        return out
    end
    for i, id in ipairs(TL.caseOrder) do
        local c = TL.cases[id]
        out[i] = { id = id, cat = c.cat, class = c.class, label = TL.Label(c), status = "pass", ms = (i * 37 % 91) / 10, facts = {}, checks = 2 + i % 5 }
        if c.class == "guided" then out[i].ms = 29922.1 - i * 3000 end
    end
    return out
end

local function Find(list, id)
    for _, r in ipairs(list) do if r.id == id then return r end end
    error("no record " .. id)
end

local function Fail(r)
    r.status, r.ms = "fail", 164.5
    r.fails = { "seed 7100008: bid-only records: expected 5, got 4", "seed 7100008: invalid records: expected 5, got 6" }
    r.failed = 2
    r.detail = table.concat(r.fails, "; ")
    r.notes = { "seed 7100008 record 10 (invalid): item number 45480, count number -nan, buyout number 0, model bid-only, production invalid" }
    r.facts = { { "market.batch.items", "3" }, { "market.batch.seed", "7100008" }, { "client.clock", "GetTimePreciseSec" } }
end

local function Summary(results, ended, seconds)
    return { results = results, counts = RN.Count(results), cats = { "core", "client", "ui" }, seconds = seconds, slices = 8144, worstSlice = 0.0147, worstFrame = 0.041,
        overruns = {}, overrunCount = 0, ended = ended, clock = "GetTimePreciseSec", slice = 0.005 }
end

---------------------------------------------------------------------------------------------------------------------------
-- Reachability of the window's controls (EMULATED by Reach.lua over the simulator's frames; see testing-roadmap M5)
---------------------------------------------------------------------------------------------------------------------------
local function Reach(label, fr, expect, kind)
    local col = Lab.collected
    local res = R.TestLab.Reach.Analyze(fr, { kind = kind or "click", collected = col, evidence = "simulator-geometry", limit = 1000000 })
    Check("display", "REACH: " .. label, expect or "reachable", res.verdict == (expect or "reachable") and (expect or "reachable") or (res.verdict .. ": " .. (res.why or "")))
    return res
end

-- the longest string against the width it is drawn in (the simulator draws addon fonts in Friz Quadrata, which is wider: a structural check)
local function Fits(label, fs, width)
    local w, limit = fs:GetStringWidth() or 0, width or fs:GetWidth() or 0
    return w <= limit + 1 and "fits" or ("%s is %.0f wide in %.0f"):format(label, w, limit)
end

---------------------------------------------------------------------------------------------------------------------------
Lab.Step("load and open", function()
    local loaded = C_AddOns.LoadAddOn("TwichUI_TestLab")
    TL = R.TestLab
    Check("init", "the Test Lab addon loaded", true, loaded == true or (TL ~= nil and TL.Window ~= nil))
    V, W, RN = TL.View, TL.Window, TL.Runner
    win = W.Frame()
    Lab.Settle(0.6)
    Check("init", "the window opened by loading", true, win ~= nil and win:IsShown())
    local cats = V.Categories()
    local entries = 0
    for _ in pairs(win.entries) do entries = entries + 1 end
    Check("display", "one sidebar entry per registered category (from the registry)", #TL.categoryOrder, entries)
    local counts = {}
    for _, c in ipairs(cats) do counts[#counts + 1] = c.id .. "=" .. c.count end
    Say("categories", table.concat(counts, ","))
    Check("display", "the guided group is not ticked, the others are", "false/true", tostring(win.boxes.pointer:GetChecked()) .. "/" .. tostring(win.boxes.core:GetChecked()))
    Check("display", "before a run every card shows a dash (not run is not zero failures)", "-/-/-/-/-/-/-",
        table.concat({ Txt(win.cards.total.value), Txt(win.cards.pass.value), Txt(win.cards.fail.value), Txt(win.cards.skipped.value), Txt(win.cards.error.value),
            Txt(win.cards.timeout.value), Txt(win.cards.duration.value) }, "/"))
    Check("display", "the state reads Not run yet", "Not run yet", Txt(win.stateText))
    Check("display", "the table explains itself", true, Txt(win.list.empty):find("Nothing has run yet", 1, true) ~= nil)
    Check("display", "Run is the only action available", "true/false/false/false",
        tostring(win.run:IsEnabled()) .. "/" .. tostring(win.stop:IsEnabled()) .. "/" .. tostring(win.copy:IsEnabled()) .. "/" .. tostring(win.copyFail:IsEnabled()))
end)

Lab.Step("recorded results for this view", function()
    if view == "idle" then return end
    if view == "running" then
        local recs = Records()
        for i, r in ipairs(recs) do
            if i > 14 then r.status, r.ms = "pending", nil elseif i == 14 then r.status, r.ms = "running", nil end
        end
        local real = RN.Active
        RN.Active = function() return true end   -- the scenario's stand-in: a run is "active" so the buttons read as they do during one
        W.OnProgress({ active = true, n = #recs, at = 14, id = recs[14].id, seconds = 3.2, results = recs, counts = RN.Count(recs) })
        Lab.Settle(0.3)
        Check("display", "while running: the state says Running and where", true, Txt(win.stateText) == "Running" and Txt(win.stateDetail):find("case 14 of " .. #recs, 1, true) ~= nil)
        Check("display", "Run is off, Stop is on, the copies are off", "false/true/false/false",
            tostring(win.run:IsEnabled()) .. "/" .. tostring(win.stop:IsEnabled()) .. "/" .. tostring(win.copy:IsEnabled()) .. "/" .. tostring(win.copyFail:IsEnabled()))
        Check("display", "the passed card counts only the 13 finished cases (the running one and the waiting ones are not passes)", "13", Txt(win.cards.pass.value))
        Check("display", "the bar is part way", true, win.meter.frac > 0 and win.meter.frac < 1)
        Check("display", "no report is written while it runs", true, Txt(win.edit):find("written when the run ends", 1, true) ~= nil)
        RN.Active = real
        return
    end
    local recs
    if view == "long" then recs = Records(300) else recs = Records() end
    local n = #recs
    local seconds = 58.4
    if view == "allpass" then
        -- nothing to change
    elseif view == "problems" then
        Fail(Find(recs, "market.reference.batch"))
        local skip = Find(recs, "ui.workshop.reach-scan")
        skip.status, skip.ms, skip.detail = "skipped", 0.1, "The Workshop window is not open: open it first (/tui workshop)."
        local err = Find(recs, "client.api.presence")
        err.status, err.ms, err.detail = "error", 0.3, "Lab/cases/Client.lua:48: attempt to index a nil value (field 'x')"
        local slow = recs[5]
        slow.status, slow.ms, slow.detail = "timeout", 10002.1, "abandoned at a yield point after 10.0 s (budget 10 s); it was not resumed"
    elseif view == "long" then
        for i = 50, 300, 50 do Fail(recs[i]) end
        recs[77].status, recs[77].detail = "error", "boom"
        recs[200].status, recs[200].detail = "skipped", "not here"
    elseif view == "guided" then
        -- handled below
    else
        Fail(Find(recs, "market.reference.batch"))
    end
    if view == "guided" then
        recs = Records()
        for _, r in ipairs(recs) do if r.class == "guided" then r.status, r.ms = "running", nil end end
        local first = true
        for _, r in ipairs(recs) do if r.class == "guided" and first then first = false else if r.class == "guided" then r.status, r.ms = "pending", nil end end end
        local real = RN.Active
        RN.Active = function() return true end
        W.Peek(true)
        TL.Guided.Begin{ title = "Pointer probe: the Add button", lines = { "Open the Workshop, Opportunities, and choose a recipe.", "Put the pointer over Add to crafting plan.", }, capture = function() return {} end }
        Lab.Settle(0.3)
        local G = TL.Guided.Snapshot()
        Check("display", "the guided prompt is shown", true, G.promptShown)
        Check("display", "the Test Lab window has stepped aside: its content is hidden", "false/false", tostring(win.content:IsShown()) .. "/" .. tostring(win.shell:IsShown()))
        Check("display", "and it is still open, so the run goes on", true, win:IsShown())
        RN.Active = real
        return
    end
    local sum = Summary(recs, "complete", seconds)
    RN.last = sum   -- the runner keeps its last summary; with no run, the scenario sets it (the Copy buttons read it)
    W.OnDone(sum)
    Lab.Settle(0.4)
    local c = RN.Count(recs)
    Check("display", "the cards carry the run's counts", ("%d/%d/%d/%d/%d/%d"):format(n, c.pass, c.fail, c.skipped, c.error, c.timeout),
        table.concat({ Txt(win.cards.total.value), Txt(win.cards.pass.value), Txt(win.cards.fail.value), Txt(win.cards.skipped.value), Txt(win.cards.error.value), Txt(win.cards.timeout.value) }, "/"))
    Check("display", "the duration card", "58.40 s", Txt(win.cards.duration.value))
    local state = Txt(win.stateText)
    local want = view == "allpass" and "Finished: all passed" or "Finished with problems"
    Check("display", "the run state", want, state)
    Check("display", "the bar is full", 1, win.meter.frac)
    Check("display", "the report box holds the schema 1 report", true, Txt(win.edit):find("^TWICHUI%-TESTLAB REPORT schema 1") ~= nil)
    Check("display", "the chips carry the counts", ("All (%d)"):format(n), win.chips.all.shownText)
    local rows = W.Snapshot().rows
    Check("display", "the table lists every case", n, rows)
    Check("display", "only the rows that can show exist (pooled)", true, #win.list.rows <= 20)
    if view == "allpass" then
        Check("display", "nothing is chosen for the player", "nil", tostring(W.Snapshot().selected))
        Check("display", "Copy failures is off when nothing failed", false, win.copyFail:IsEnabled())
        Check("display", "the details panel invites a choice", true, Txt(win.det.empty):find("Choose a row", 1, true) ~= nil)
    else
        Check("display", "the first failure is chosen at once and its details show", (view == "long" and "synthetic.case.050" or "market.reference.batch") .. "/FAIL", Txt(win.det.id) .. "/" .. Txt(win.det.outcome))
        Check("display", "Copy failures is available", true, win.copyFail:IsEnabled())
    end
    if view == "problems" then
        Check("display", "errors, skipped cases and timeouts have chips", "true/true/true", tostring(win.chips.error:IsShown()) .. "/" .. tostring(win.chips.skipped:IsShown()) .. "/" .. tostring(win.chips.timeout:IsShown()))
        W.Select("client.api.presence")
        Check("display", "an error is shown as an error, not as a failed check", "ERROR", Txt(win.det.outcome))
    end
    if view == "failfilter" then
        W.SetFilter("fail")
        Lab.Settle(0.2)
        Check("display", "the Failed filter shows only the failure", "1", tostring(W.Snapshot().rows))
        Check("display", "the selection and the report survive the filter", "market.reference.batch", W.Snapshot().selected)
    end
    if view == "long" then
        Check("display", "a long run is chosen at its first failure", "synthetic.case.050", W.Snapshot().selected)
        W.SetFilter("fail"); Check("display", "five failures (every 50th case; the 200th was recorded as skipped)", "5", tostring(W.Snapshot().rows)); W.SetFilter("all")
        W.SetQuery("case.02"); Check("display", "the search narrows to the 02x cases", "10", tostring(W.Snapshot().rows)); W.SetQuery("")
        win.list.scroll:SetVerticalScroll(30 * 100)
        Lab.Settle(0.3)
        Check("display", "scrolled to the middle of the list", true, win.list.rows[1].rec ~= nil and win.list.rows[1].rec.id ~= "synthetic.case.001")
    end
end)

---------------------------------------------------------------------------------------------------------------------------
Lab.Step("the controls take the pointer, and the text fits", function()
    if view == "idle" or view == "running" or view == "guided" then return end
    -- the simulator keeps a scrolled list's rows where they were, so the geometry is read with the list at its top (and put back for the picture)
    local scrolled = win.list.scroll:GetVerticalScroll() or 0
    win.list.scroll:SetVerticalScroll(0)
    Lab.Settle(0.1)
    Lab.collected = R.TestLab.Reach.Collect({ limit = 1000000 })
    Reach("the Run button at its hit point", win.run)
    Reach("Copy report", win.copy)
    if win.copyFail:IsEnabled() then Reach("Copy failures", win.copyFail) end
    Reach("Stop is not eligible when no run is active", win.stop, "ineligible")
    Reach("the All filter chip", win.chips.all)
    Reach("the Failed filter chip", win.chips.fail)
    Reach("the Close button", win.close)
    Reach("a group's check", win.boxes.core)
    Reach("a group's whole entry", win.entries.core)
    -- the rows whose centre is in view must be reachable, and none may be blocked or ambiguous
    local reachable, other = 0, {}
    for _, r in ipairs(win.list.rows) do
        if r:IsShown() and r.rec then
            local res = R.TestLab.Reach.Analyze(r, { kind = "click", collected = Lab.collected, evidence = "simulator-geometry", limit = 1000000 })
            if res.verdict == "reachable" then reachable = reachable + 1 elseif res.verdict ~= "clipped" then other[#other + 1] = res.verdict; Say("blocked", (res.text:gsub("\n%s*", " | "))) end
        end
    end
    Check("display", "REACH: the result rows in view take the pointer; none is blocked or ambiguous", "ok", (reachable >= 1 and #other == 0) and "ok" or ("reachable " .. reachable .. ", other " .. table.concat(other, ",")))
    Reach("the search field (pointer motion)", win.search, nil, "hover")
    -- a row takes hover, with its child text and chip not in the way
    -- the text fits its box (structural: the simulator's font is wider than the game's)
    local misfit = {}
    for key, card in pairs(win.cards) do
        local room = card:GetWidth() - (card.compact and 18 or 60)
        local r = Fits(key .. " label", card.label, room); if r ~= "fits" then misfit[#misfit + 1] = r end
        r = Fits(key .. " value", card.value, room); if r ~= "fits" then misfit[#misfit + 1] = r end
    end
    for id, chip in pairs(win.chips) do
        if chip:IsShown() then local r = Fits(id .. " chip", chip.text, chip:GetWidth() - 8); if r ~= "fits" then misfit[#misfit + 1] = r end end
    end
    for _, b in ipairs({ win.run, win.stop, win.copy, win.copyFail }) do
        local r = Fits(Txt(b.text), b.text, b:GetWidth() - (b.glyph and 44 or 20)); if r ~= "fits" then misfit[#misfit + 1] = r end
    end
    win.list.scroll:SetVerticalScroll(scrolled)
    Lab.Settle(0.1)
    Say("fit", #misfit == 0 and "all fit" or table.concat(misfit, "; "))
    Check("display", "no card label, value, chip or button text is wider than its box (simulator font, structural)", "none", #misfit == 0 and "none" or misfit[1])
end)

Lab.Step("pose for the screenshot", function()
    Lab.Settle(0.5)
    Check("display", "pose: the view is " .. view, view, view)
end)

Lab.Finish()
