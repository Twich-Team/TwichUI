-- TwichUI Diagnostics: the workspace window
-- Built the first time it opens (/tui perf, or the Troubleshooting page's button) and kept; its pages are built when
-- first shown. Left: the eight views and the capture being looked at; top: recording status and its buttons; right:
-- the view. Nothing here runs while the window is closed, except the small recording badge while a capture records
-- (a once-a-second text update). Charts are drawn when their view is shown or the capture changes, never per frame;
-- while recording, the Timeline redraws at most every LIVE_REDRAW seconds and only while it is the view shown.
-- Closing the window does not stop a capture (the badge says it is still recording; Stop is there and in /tui perf).
-- Drawn with TwichUI's own look (R.Look), so it is complete without EllesmereUI or any other addon.

local R = TwichUI
local DX = R.DiagnosticsKit
local Chart, F, EX = DX.Chart, DX.Findings, DX.Export
local W = {}
DX.Window = W

local FRAME_NAME = "TwichUIDiagnosticsWorkspace"
local WIDTH, HEIGHT = 1000, 660
local HEADER_H, NAV_W, PAD, STRIP_H = 40, 186, 14, 70
local CONTENT_W = WIDTH - PAD - NAV_W - 12 - 24 - PAD
local LIVE_REDRAW = 5

W.TABS = {
    { key = "overview", label = "Overview", icon = "diagOverview", tip = "What was recorded, what deserves a look, and what can't be concluded. Start a capture here." },
    { key = "timeline", label = "Timeline", icon = "diagTimeline", tip = "One metric over the capture, with markers and long frames; select a window to see what happened in it." },
    { key = "operations", label = "Operations", icon = "diagOperations", tip = "TwichUI's instrumented operations by time, calls and worst call, with their slowest calls." },
    { key = "events", label = "Events & lifecycle", icon = "diagEvents", tip = "Events TwichUI received against the callbacks they reached; listener counts, pools and caches." },
    { key = "memory", label = "Memory", icon = "diagMemory", tip = "Sampled memory over the capture and what it can and can't tell you." },
    { key = "errors", label = "Errors", icon = "diagErrors", tip = "Errors observed during the capture, and a note of your own." },
    { key = "compare", label = "Compare", icon = "diagCompare", tip = "Two captures side by side, normalised, with what makes them comparable or not." },
    { key = "export", label = "Export", icon = "diagExport", tip = "A summary, the full report, a comparison or an AI prompt, to read and copy." },
}

local win, nav, scroll, content, strip, badge
local pages, navItems = {}, {}
local state = { tab = "overview", preset = "general", subsystem = "npcs", minutes = nil, note = "", allocation = false, mapIds = false,
    viewing = nil, newCapture = false, metric = "frames", sortBy = "total", selectedOp = nil, window = nil, memMetric = "core",
    exportKind = "summary", exportOpts = nil, built = nil, piece = 1, compareA = nil, compareB = nil, lastLive = 0 }

local function Look() return R.Look end
local function Pal() return R.Look.pal end
local function Say(fmt, ...) DX.Say(fmt, ...) end

function DX.WindowShown() return win ~= nil and win:IsShown() end

---------------------------------------------------------------------------
-- Small layout kit: a page is a frame with items stacked top to bottom
---------------------------------------------------------------------------
local function Height(obj)
    local h
    if obj.GetStringHeight then h = obj:GetStringHeight() else h = obj:GetHeight() end
    return (type(h) == "number" and h > 0) and h or 14
end

local function NewPage(key)
    local p = CreateFrame("Frame", nil, content)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetWidth(CONTENT_W)
    p:Hide()
    p.items, p.key = {}, key
    pages[key] = p
    return p
end

-- obj placed below the previous visible item, `gap` pixels down, `indent` in
local function Put(p, obj, gap, indent)
    p.items[#p.items + 1] = { obj = obj, gap = gap or 6, indent = indent or 0 }
    return obj
end

local function Flow(p)
    local y = 4
    for _, it in ipairs(p.items) do
        local o = it.obj
        if o:IsShown() then
            o:ClearAllPoints()
            o:SetPoint("TOPLEFT", p, "TOPLEFT", it.indent, -(y + it.gap))
            y = y + it.gap + Height(o)
        end
    end
    p:SetHeight(y + 16)
    if p:IsShown() then content:SetHeight(y + 16) end
end

local function Text(p, kind, width)
    local fs = Look().Text(p, kind or "body")
    fs:SetWidth(width or (CONTENT_W - 8))
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    return fs
end

local function Heading(p, text)
    local fs = Text(p, "heading")
    fs:SetText(text)
    return Put(p, fs, 14)
end

-- A row of chips (Look.Tab), one selected. items: { { key, label, tip } }
local function Chips(p, items, current, onPick, width)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(CONTENT_W, 26)
    row.chips = {}
    local x = 0
    for _, it in ipairs(items) do
        local w = width or math.max(90, (#it.label * 7) + 20)
        local b = Look().Tab(row, it.label, w, function() onPick(it.key) end)
        b:SetPoint("LEFT", x, 0)
        b.key = it.key   -- (no tooltip: it would replace the tab's own hover; what each chip means is written beside it)
        row.chips[#row.chips + 1] = b
        x = x + w + 4
    end
    function row:Paint(sel) for _, b in ipairs(self.chips) do b:SetSelected(b.key == sel) end end
    row:Paint(current)
    return row
end

local function Button(p, label, w, kind, fn, tip)
    local b = Look().Button(p, label, w, kind, fn)
    b:SetHeight(22)
    if tip then R.Interact.Tip(b, label, tip) end
    return b
end

-- A one-line row of buttons: frame holding them left to right
local function ButtonRow(p, list)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(CONTENT_W, 24)
    local x = 0
    for _, b in ipairs(list) do
        b:SetParent(row)
        b:ClearAllPoints()
        b:SetPoint("LEFT", x, 0)
        x = x + (b:GetWidth() or 100) + 8
    end
    return row
end

local function Join(lines) return table.concat(lines, "\n") end

---------------------------------------------------------------------------
-- Which capture is shown
---------------------------------------------------------------------------
local function Viewing()
    local list = DX.Sessions()
    if state.viewing then
        for _, s in ipairs(list) do if s.uid == state.viewing then return s, list end end
    end
    return list[#list], list
end

local function Describe(rec)
    if not rec then return "none yet" end
    return ("#%d %s, %s%s"):format(rec.id or 0, rec.presetName or "?", DX.Clock2(rec.duration), rec.saved and ", saved" or "")
end

---------------------------------------------------------------------------
-- The recording strip
---------------------------------------------------------------------------
local function StripRefresh()
    if not strip then return end
    local st = DX.State()
    local live = DX.Live()
    if st == "recording" and live then
        strip.status:SetText(("%s● Recording|r  %s (%s)  %s of %s"):format(R.GREEN, live.presetName, live.mode,
            DX.Clock2(DX.Now() - live.t0 / 1000), DX.Clock2(live.minutes * 60)))
        strip.detail:SetText("Closing this window keeps it recording; a small badge shows it until you stop. Stop keeps the capture; Cancel discards it.")
    elseif st == "finishing" then
        strip.status:SetText("Stopped: putting the capture together" .. (DX.InCombat() and " when combat ends" or ""))
        strip.detail:SetText("Nothing is summed or sorted in combat or in the frame that stopped it.")
    else
        strip.status:SetText(R.GREY .. "Stopped|r  nothing is being recorded")
        strip.detail:SetText("Pick a preset on the Overview and press Start. Nothing records until you do, and nothing starts by itself at login.")
    end
    local rec = DX.State() ~= "recording" and select(1, Viewing()) or nil
    strip.stop:SetEnabled(st == "recording")
    strip.cancel:SetEnabled(st == "recording")
    strip.mark:SetEnabled(st == "recording")
    strip.markText:SetShown(st == "recording")
    if win then win.chip:SetText(st == "recording" and (R.GREEN .. "Recording|r") or (R.GREY .. "Stopped|r")) end
end

local function BuildStrip(area)
    local L = Look()
    strip = CreateFrame("Frame", nil, area, "BackdropTemplate")
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(STRIP_H - 8)
    L.Panel(strip)
    strip.status = L.Text(strip, "body")
    strip.status:SetPoint("TOPLEFT", 10, -8)
    strip.detail = L.Text(strip, "small")
    strip.detail:SetPoint("TOPLEFT", strip.status, "BOTTOMLEFT", 0, -4)
    strip.detail:SetWidth(CONTENT_W - 330)
    strip.stop = Button(strip, "Stop", 64, "primary", function() DX.Stop("manual") end, "Stops collecting at once and keeps the capture (it is put together a moment later, or when combat ends).")
    strip.cancel = Button(strip, "Cancel", 64, "secondary", function() DX.Cancel() end, "Stops and keeps nothing of this capture.")
    strip.mark = Button(strip, "Marker", 70, "secondary", function()
        DX.Mark(strip.markText:GetText())
        strip.markText:SetText("")
        strip.markText:ClearFocus()
    end, "Puts a timestamped marker in the capture, with the words beside it if you typed any (your text; shown as yours in exports).")
    strip.markText = L.EditBox(strip, 150, 22)
    strip.markText:SetMaxLetters(60)
    strip.stop:SetPoint("TOPRIGHT", -10, -8)
    strip.cancel:SetPoint("RIGHT", strip.stop, "LEFT", -6, 0)
    strip.mark:SetPoint("TOPRIGHT", strip.stop, "BOTTOMRIGHT", 0, -6)
    strip.markText:SetPoint("RIGHT", strip.mark, "LEFT", -6, 0)
    strip.markText:SetScript("OnEnterPressed", function(e) strip.mark:Click() end)
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function CapLine(c)
    local color = c.state == "available" and R.GREEN or (c.state == "partial" and R.GOLD or R.GREY)
    return ("%s%s|r  %s (%s, %s): %s"):format(color, c.state, c.label, c.unit, c.provenance, c.note or "")
end

local function BuildOverview()
    local p = NewPage("overview")
    local L = Look()
    -- recording now
    p.liveHead = Heading(p, "Recording")
    p.live = Put(p, Text(p, "small"), 4)
    p.liveNoteLabel = Put(p, Text(p, "meta"), 8)
    p.liveNoteLabel:SetText("What you are doing (optional; your text, kept with the capture):")
    p.liveNote = Put(p, L.EditBox(p, CONTENT_W - 20, 22), 4)
    p.liveNote:SetMaxLetters(200)
    p.liveNote:SetScript("OnTextChanged", function(e, user) if user then DX.SetNote(e:GetText()) end end)
    -- a finished capture
    p.recHead = Heading(p, "This capture")
    p.recText = Put(p, Text(p, "small"), 4)
    p.workHead = Heading(p, "Where the measured work was")
    p.work = Put(p, Text(p, "small"), 4)
    p.findHead = Heading(p, "What deserves a look")
    p.find = Put(p, Text(p, "small"), 4)
    p.cantHead = Heading(p, "What can't be concluded")
    p.cant = Put(p, Text(p, "small"), 4)
    p.newBtn = Put(p, Button(p, "Record a new capture", 170, "secondary", function() state.newCapture = true; W.Refresh() end), 12)
    -- a new capture
    p.newHead = Heading(p, "Record a capture")
    p.newIntro = Put(p, Text(p, "small"), 4)
    p.newIntro:SetText("Choose what to measure, then do the thing you want measured. A preset never changes a setting, turns a feature on or off, uses an item or sends anything to your group: it only watches. What it costs is said before you start.")
    p.presets = {}
    for _, pr in ipairs(DX.PRESETS) do
        if not pr.hidden then
            local row = CreateFrame("Button", nil, p, "BackdropTemplate")
            row:SetSize(CONTENT_W - 8, 52)
            row.fill = L.Solid(row, "BACKGROUND", Pal().bronzeText, 0.10)
            row.fill:SetAllPoints()
            row.bar = L.Solid(row, "ARTWORK", Pal().bronzeText, 1)
            row.bar:SetPoint("TOPLEFT"); row.bar:SetPoint("BOTTOMLEFT"); row.bar:SetWidth(2)
            row.name = L.Text(row, "body"); row.name:SetPoint("TOPLEFT", 10, -4)
            row.what = L.Text(row, "small"); row.what:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2); row.what:SetWidth(CONTENT_W - 30)
            row.cost = L.Text(row, "meta"); row.cost:SetPoint("TOPLEFT", row.what, "BOTTOMLEFT", 0, -2); row.cost:SetWidth(CONTENT_W - 30)
            row.name:SetText(("%s  %s(%d min)|r"):format(pr.name, R.GREY, pr.minutes))
            row.what:SetText(pr.what)
            row.cost:SetText("Cost: " .. pr.cost)
            row.key = pr.key
            row:SetScript("OnClick", function() state.preset = pr.key; state.minutes = nil; W.Refresh() end)
            p.presets[#p.presets + 1] = Put(p, row, 4)
        end
    end
    local subs = {}
    for _, s in ipairs(DX.SUBSYSTEMS) do subs[#subs + 1] = { key = s.key, label = s.label } end
    p.subLabel = Put(p, Text(p, "meta"), 10)
    p.subLabel:SetText("Subsystem to trace:")
    p.subs = Put(p, Chips(p, subs, state.subsystem, function(k) state.subsystem = k; W.Refresh() end, 128), 4)
    local alloc = CreateFrame("Frame", nil, p); alloc:SetSize(CONTENT_W, 20)
    alloc.box = L.Checkbox(alloc, function(on) state.allocation = on; W.Refresh() end); alloc.box:SetPoint("LEFT")
    alloc.text = L.Text(alloc, "small"); alloc.text:SetPoint("LEFT", alloc.box, "RIGHT", 8, 0); alloc.text:SetWidth(CONTENT_W - 40)
    alloc.text:SetText("Also measure each scoped call's allocation with the client's own C_AddOnProfiler.MeasureCall (adds cost; only operations that use Perf.Call)")
    p.alloc = Put(p, alloc, 6)
    local maps = CreateFrame("Frame", nil, p); maps:SetSize(CONTENT_W, 20)
    maps.box = L.Checkbox(maps, function(on) state.mapIds = on; W.Refresh() end); maps.box:SetPoint("LEFT")
    maps.text = L.Text(maps, "small"); maps.text:SetPoint("LEFT", maps.box, "RIGHT", 8, 0); maps.text:SetWidth(CONTENT_W - 40)
    maps.text:SetText("Note the map ID when the zone changes (a location; left out of exports unless you include it there too)")
    p.maps = Put(p, maps, 8)
    local len = CreateFrame("Frame", nil, p); len:SetSize(CONTENT_W, 24)
    len.text = L.Text(len, "body"); len.text:SetPoint("LEFT")
    len.minus = Button(len, "-", 24, "secondary", function() state.minutes = math.max(1, (state.minutes or DX.Preset(state.preset).minutes) - 1); W.Refresh() end)
    len.plus = Button(len, "+", 24, "secondary", function() state.minutes = math.min(DX.MAX_MINUTES, (state.minutes or DX.Preset(state.preset).minutes) + 1); W.Refresh() end)
    len.minus:SetPoint("LEFT", 150, 0); len.plus:SetPoint("LEFT", len.minus, "RIGHT", 4, 0)
    len.hint = L.Text(len, "meta"); len.hint:SetPoint("LEFT", len.plus, "RIGHT", 10, 0)
    len.hint:SetText(("It stops by itself then (at most %d minutes); you can stop it sooner."):format(DX.MAX_MINUTES))
    p.len = Put(p, len, 8)
    p.noteLabel = Put(p, Text(p, "meta"), 8)
    p.noteLabel:SetText("What you are about to do (optional; your text, kept with the capture and shown as yours in exports):")
    p.note = Put(p, L.EditBox(p, CONTENT_W - 20, 22), 4)
    p.note:SetMaxLetters(200)
    p.note:SetScript("OnTextChanged", function(e) state.note = e:GetText() end)
    p.start = Put(p, Button(p, "Start recording", 150, "primary", function()
        local ok, why = DX.Start(state.preset, { minutes = state.minutes, note = state.note, subsystem = state.subsystem,
            allocation = state.allocation, mapIds = state.mapIds })
        if not ok then Say("%s", DX.WHY[why] or why) return end
        state.newCapture = false
        p.note:SetText("")
        p.liveNote:SetText(state.note or "")
        W.Refresh()
    end, "Starts recording with the preset above. Closing this window keeps it recording."), 10)
    -- what this client can measure
    p.capHead = Heading(p, "What this client lets TwichUI measure")
    p.caps = Put(p, Text(p, "small"), 4)
    -- advanced
    p.advHead = Heading(p, "Advanced")
    p.armText = Put(p, Text(p, "small"), 4)
    p.arm = Put(p, Button(p, "Arm next reload", 150, "secondary", function()
        if R.DiagnosticsLauncher.Armed() then R.DiagnosticsLauncher.Disarm() else R.DiagnosticsLauncher.Arm("startup") end
        W.Refresh()
    end), 6)
    p.cpuText = Put(p, Text(p, "small"), 10)
    p.cpu = Put(p, Button(p, "Request legacy CPU totals", 200, "secondary", function() W.ToggleScriptProfile() end), 6)
    p.gcText = Put(p, Text(p, "small"), 10)
    p.gc = Put(p, Button(p, "Run one garbage collection", 200, "danger", function()
        R.Interact.Confirm("TWICHUI_DIAG_GC", "Run one full garbage collection of every addon now?\n\nThe game may stall for a moment. Memory readings after it are not comparable with those before; a capture recording now is marked as having had it. Nothing else changes.",
            function()
                local before, after, ms = DX.GcExperiment()
                Say("one garbage collection: %.0f KB to %.0f KB of Lua memory (all addons), in %s.", before, after, DX.Ms(ms))
                W.Refresh()
            end, { accept = "Collect" })
    end), 6)
    return p
end

function W.ToggleScriptProfile()
    local current = DX.CVar("scriptProfile")
    if current == nil then Say("this client doesn't know the scriptProfile setting, so legacy CPU totals can't be turned on.") return end
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    local db = DX.DB()
    if current == "1" then
        local ours = db and db.cvar and db.cvar.scriptProfile
        local text = ours and "Turn the client's scriptProfile setting off again? TwichUI Diagnostics turned it on; it takes effect after a reload you make."
            or "Turn the client's scriptProfile setting off? It was on before TwichUI Diagnostics touched it (you or another addon turned it on). It takes effect after a reload you make."
        R.Interact.Confirm("TWICHUI_DIAG_CPU_OFF", text, function()
            pcall(set, "scriptProfile", "0")
            if db then db.cvar = nil end
            Say("scriptProfile is set off; it takes effect after you reload. Nothing reloads by itself.")
            W.Refresh()
        end, { accept = "Turn off" })
    else
        R.Interact.Confirm("TWICHUI_DIAG_CPU_ON", "Turn on the client's scriptProfile setting?\n\nIt is a client-wide setting: after the next reload (you make it; nothing reloads by itself) every addon runs a little slower, and GetAddOnCPUUsage gives cumulative CPU totals. Turn it off again here when you are done. The addon profiler most captures use works without it.",
            function()
                pcall(set, "scriptProfile", "1")
                if db then db.cvar = { scriptProfile = true, at = time and time() or 0 } end
                Say("scriptProfile is set on; it takes effect after you reload. Turn it off again on the Overview when you are done.")
                W.Refresh()
            end, { accept = "Turn on" })
    end
end

local function TopWork(rec)
    local work = F.MeasuredWork(rec)
    local lines = {}
    local n = 0
    for _, op in ipairs(rec.ops or {}) do
        if DX.Op(op.id).kind ~= "event" then
            n = n + 1
            if n > 4 then break end
            lines[#lines + 1] = ("%s  %s in %d call(s) (%s of measured work; slowest %s)"):format(DX.Op(op.id).label, DX.Ms(op.total), op.calls,
                work > 0 and ("%.0f%%"):format(op.total / work * 100) or "n/a", DX.Ms(op.max))
        end
    end
    local ev = rec.events and rec.events[1]
    if ev then lines[#lines + 1] = ("busiest event: %s, %d received, %d callbacks, %s"):format(ev.event, ev.received, ev.callbacks, DX.Ms(ev.total)) end
    if #lines == 0 then lines[1] = "No instrumented TwichUI operation ran during this capture." end
    return Join(lines)
end

local function FindingsText(rec)
    local out = {}
    for i, f in ipairs(rec.findings or {}) do
        if i > 6 then out[#out + 1] = ("... %d more on Export (the full report)"):format(#rec.findings - 6) break end
        local tone = f.severity == "high" and R.RED or (f.severity == "medium" and R.GOLD or R.GREY)
        out[#out + 1] = ("%s%s|r  %s  %s(%s, %s)|r"):format(tone, f.severity:upper(), f.title, R.GREY, f.category, f.confidence)
        out[#out + 1] = "   why: " .. f.basis
        for _, e in ipairs(f.evidence or {}) do out[#out + 1] = "   evidence: " .. e end
        if f.verify then out[#out + 1] = "   to check: " .. f.verify end
    end
    if #out == 0 then out[1] = "No rule found anything in this capture. That is not proof nothing is wrong: see what can't be concluded." end
    return Join(out)
end

local function RefreshOverview()
    local p = pages.overview
    local st = DX.State()
    local rec = Viewing()
    local recording = st == "recording"
    local showNew = not recording and (state.newCapture or not rec)
    local showRec = not recording and rec and not showNew
    for _, o in ipairs({ p.liveHead, p.live, p.liveNoteLabel, p.liveNote }) do o:SetShown(recording) end
    for _, o in ipairs({ p.recHead, p.recText, p.workHead, p.work, p.findHead, p.find, p.cantHead, p.cant, p.newBtn }) do o:SetShown(showRec and true or false) end
    for _, o in ipairs({ p.newHead, p.newIntro, p.len, p.noteLabel, p.note, p.start, p.maps }) do o:SetShown(showNew) end
    for _, row in ipairs(p.presets) do
        row:SetShown(showNew)
        local sel = row.key == state.preset
        row.fill:SetShown(sel); row.bar:SetShown(sel)
    end
    local focused = showNew and DX.Preset(state.preset).mode == "focused"
    p.subLabel:SetShown(focused); p.subs:SetShown(focused); p.alloc:SetShown(focused)
    p.subs:Paint(state.subsystem)
    p.alloc.box:SetChecked(state.allocation)
    p.maps.box:SetChecked(state.mapIds)
    p.len.text:SetText(("Length: %d min"):format(state.minutes or DX.Preset(state.preset).minutes))
    if recording then
        local live = DX.Live()
        local list, ops = DX.Instrument.Live()
        p.live:SetText(Join({
            ("%s, %s of %s. %d frames so far, %d long, %d discontinuities."):format(live.presetName, DX.Clock2(DX.Now() - live.t0 / 1000),
                DX.Clock2(live.minutes * 60), live.frameCount, live.spikeCount, #live.gaps),
            ("%d operations seen, %d events; %d errors; memory read every %d s, gauges every %d s."):format(#list, ops, live.errorCount, live.memorySeconds, live.gaugeSeconds),
            "Do what you want measured now. Markers (top right) put a moment you choose on the timeline.",
        }))
    end
    if showRec then
        local fr = rec.frames or {}
        local lines = {
            ("%s (%s%s), started %s, %s long; stopped: %s."):format(rec.presetName, rec.mode, rec.subsystem and (", " .. rec.subsystem) or "", rec.startedAt or "?", DX.Clock2(rec.duration), tostring(rec.stopReason)),
            ("Profiling: the client's addon profiler %s; operations timed with %s; legacy CPU totals %s."):format(rec.config.profiler and "was available" or "was NOT available",
                DX.clockSource, rec.config.legacyCpu and "on" or "off"),
            ("Frames: %d; interval median %s, 95th %s (approximate); %d long frame(s) of %d ms or more; %d discontinuities left out."):format(fr.count or 0,
                DX.Ms(fr.p50), DX.Ms(fr.p95), fr.spikeCount or 0, rec.config.spikeMs, #(fr.gaps or {})),
            ("Measured TwichUI work: %s in %d instrumented calls (estimated instrumentation cost about %s)."):format(DX.Ms(F.MeasuredWork(rec)), rec.scopeCalls or 0, DX.Ms(rec.overhead and rec.overhead.estimatedScopeMs)),
        }
        if rec.boot then lines[#lines + 1] = "Start-up capture: watched from TwichUI's ADDON_LOADED after a reload; its files loading and everything before that are not seen." end
        if rec.note then lines[#lines + 1] = "Your note: " .. rec.note end
        p.recText:SetText(Join(lines))
        p.work:SetText(TopWork(rec))
        p.find:SetText(FindingsText(rec))
        local cant = {}
        for _, c in ipairs(F.CannotConclude(rec)) do cant[#cant + 1] = "- " .. c end
        p.cant:SetText(Join(cant))
    end
    local caps = {}
    for _, c in ipairs(DX.Capabilities()) do caps[#caps + 1] = CapLine(c) end
    p.caps:SetText(Join(caps))
    local armed = R.DiagnosticsLauncher.Armed() ~= nil
    p.armText:SetText(("Start-up: a capture can only begin once TwichUI_Diagnostics is loaded, so start-up is recorded only after a reload you make, from TwichUI's ADDON_LOADED (TwichUI's files loading are not seen). %s"):format(
        armed and (R.GREEN .. "Armed:|r the next reload records its first minute; the flag is cleared as it is read." ) or "Not armed. Arm it, then reload (/reload) when you are ready: nothing reloads by itself."))
    p.arm:SetText(armed and "Disarm" or "Arm next reload")
    local cur = DX.CVar("scriptProfile")
    p.cpuText:SetText(cur == nil and "Legacy CPU totals (scriptProfile): this client doesn't know the setting."
        or ("Legacy CPU totals need the client's scriptProfile setting and a reload; it slows every addon while on. Now: %s%s. Requested by TwichUI Diagnostics: %s."):format(
            cur == "1" and "on" or "off", (DX.cvarAtLoad ~= nil and DX.cvarAtLoad ~= cur) and (" (it was " .. (DX.cvarAtLoad == "1" and "on" or "off") .. " when this session loaded; the change applies after a reload)") or "",
            (DX.DB() and DX.DB().cvar and DX.DB().cvar.scriptProfile) and "yes" or "no"))
    p.cpu:SetText(cur == "1" and "Turn scriptProfile off" or "Request legacy CPU totals")
    p.cpu:SetEnabled(cur ~= nil)
    p.gcText:SetText("Garbage collection experiment (advanced; never run by itself): one full collection of every addon. It can stall the game for a moment and makes later memory readings incomparable with earlier ones; a capture recording now is marked.")
    Flow(p)
end

---------------------------------------------------------------------------
-- Timeline
---------------------------------------------------------------------------
local METRICS = {
    { key = "frames", label = "Frame interval", unit = "ms", color = "frames", mean = "dtSum", per = "frames", hi = "dtMax",
      hint = "The client's time between frames (not CPU). Band: shortest to longest second in the column, using each second's worst; tick: mean." },
    { key = "cpu", label = "TwichUI CPU (client)", unit = "ms", color = "cpu", mean = "core", per = "frames", hi = "coreMax",
      hint = "The client profiler's time for TwichUI in a tick, per frame on average; band up to the worst tick." },
    { key = "work", label = "Instrumented work", unit = "ms", color = "work", mean = "work", hi = "workMax",
      hint = "TwichUI's instrumented operations that ended each second (ms per second); band up to the worst frame's." },
    { key = "events", label = "Events", unit = "/s", color = "events", mean = "events",
      hint = "Events TwichUI's bus received each second (each may reach several callbacks)." },
    { key = "heap", label = "Lua heap (all addons)", unit = "KB", color = "memory", mean = "heap",
      hint = "Every addon's Lua memory together, read once a second (garbage included)." },
    { key = "diag", label = "Diagnostics' own CPU", unit = "ms", color = "diag", mean = "diag", per = "frames",
      hint = "The client profiler's time for TwichUI_Diagnostics itself, per frame on average." },
}

local function Spec(rec, m)
    local tl = rec and rec.timeline
    local spec = { t = {}, v = {}, hi = m.hi and {} or nil, gap = {}, n = 0, unit = m.unit, label = m.label, color = Chart.COLOR[m.color],
        duration = rec and (rec.duration or (tl and tl.n)) or 0, hint = m.hint, step = tl and tl.merged or 1, markers = {} }
    if not tl or tl.n == 0 then spec.empty = "Nothing recorded yet." return spec end
    local profiled = rec.config and rec.config.profiler or (rec.config == nil and rec.useProfiler and not rec.profilerRefused)
    if (m.key == "cpu" or m.key == "diag") and not profiled then
        spec.empty = "The client's profiler wasn't available for this capture, so there is no per-frame CPU figure." return spec
    end
    for i = 1, tl.n do
        spec.n = i
        spec.t[i] = tl.t[i] or (i - 1)
        local v = tl[m.mean][i]
        if v ~= nil and m.per then
            local n = tl[m.per][i] or 0
            v = n > 0 and v / n or nil
        end
        spec.v[i] = v
        if spec.hi then spec.hi[i] = tl[m.hi][i] or v end
        spec.gap[i] = tl.gap[i]
    end
    local markers = rec.markers or {}
    if markers.cap then markers = DX.Ring.List(markers) end   -- a capture still recording keeps them in a ring
    for _, mk in ipairs(markers) do
        if mk.kind ~= "capture-start" and mk.kind ~= "capture-stop" then
            spec.markers[#spec.markers + 1] = { t = mk.t, kind = mk.kind, label = mk.label, mine = mk.auto == false }
        end
    end
    return spec
end

local function BuildTimeline()
    local p = NewPage("timeline")
    p.intro = Put(p, Text(p, "small"), 0)
    p.chips = Put(p, Chips(p, METRICS, state.metric, function(k) state.metric = k; W.Refresh() end), 8)
    p.legend = Put(p, Text(p, "meta"), 6)
    p.chart = Chart.Line(p, CONTENT_W - 8, 230)
    p.chart.onSelect = function(window) state.window = window; W.Refresh() end
    Put(p, p.chart.frame, 6)
    p.selText = Put(p, Text(p, "small"), 8)
    Heading(p, "Long frames")
    p.spikes = Put(p, Text(p, "small"), 4)
    Heading(p, "Markers")
    p.marks = Put(p, Text(p, "small"), 4)
    return p
end

local function InWindow(t)
    local w = state.window
    return not w or (t >= w[1] - 0.5 and t <= w[2] + 0.5)
end

local function RefreshTimeline()
    local p = pages.timeline
    local recording = DX.Recording()
    local rec = recording and DX.Live() or Viewing()
    local m
    for _, x in ipairs(METRICS) do if x.key == state.metric then m = x end end
    p.chips:Paint(state.metric)
    p.intro:SetText(recording and ("Live: redrawn every %d seconds while this view is shown. Drag across the chart to select a window, click a column for one second, right-click to clear."):format(LIVE_REDRAW)
        or "Drag across the chart to select a window, click a column for one second, right-click to clear. Columns keep each second's worst, so a single long frame is not averaged away.")
    p.legend:SetText(("%s (%s) on one axis. Faint band: lowest to highest in the column; tick: mean; shaded: a discontinuity; thin lines: markers (yours brighter, flagged). %s"):format(
        m.label, m.unit, m.hint))
    local spec = Spec(rec, m)
    if recording then
        spec.duration = math.max(spec.duration or 0, DX.Now() - rec.t0 / 1000)
    end
    p.chart:Draw(spec)
    local w = state.window
    p.selText:SetText(w and ("Selected: %s to %s. Long frames and markers below are those in it."):format(DX.Clock2(w[1]), DX.Clock2(w[2]))
        or "No window selected: everything is listed.")
    local lines = {}
    local spikes = rec and (rec.frames and rec.frames.spikes or rec.spikes) or {}
    for _, sp in ipairs(spikes) do
        if InWindow(sp.t) and #lines < 14 then
            local around = {}
            for _, x in ipairs(sp.before or {}) do around[#around + 1] = ("%.0f"):format(x.dt) end
            around[#around + 1] = ("[%.0f]"):format(sp.dt)
            for _, x in ipairs(sp.after or {}) do around[#around + 1] = ("%.0f"):format(x.dt) end
            lines[#lines + 1] = ("%s  %s frame%s; TwichUI %s by the client (its latest tick, read at this frame); instrumented work ended since the last frame %s%s"):format(
                DX.Clock2(sp.t), DX.Ms(sp.dt), sp.combat and " (combat)" or "", sp.core and DX.Ms(sp.core) or "n/a", DX.Ms(sp.work),
                sp.top and ((", mostly %s (%s)"):format(sp.top, DX.Ms(sp.topMs))) or "")
            lines[#lines + 1] = "    frames around it (ms): " .. table.concat(around, " ")
        end
    end
    if #lines == 0 then lines[1] = (rec and (rec.frames and rec.frames.spikeCount or rec.spikeCount) or 0) > 0 and "None in the selected window." or "No long frames were recorded." end
    lines[#lines + 1] = "Resolution: frame intervals are exact per frame; the client's per-addon figure is for its latest tick and may belong to the frame before; instrumented work is what ended between two frames. Nearby is not cause."
    p.spikes:SetText(Join(lines))
    local mk = {}
    for _, x in ipairs(spec.markers) do
        if InWindow(x.t) and #mk < 30 then mk[#mk + 1] = ("%s  %s%s%s"):format(DX.Clock2(x.t), x.kind, x.label and (": " .. x.label) or "", x.mine and "  (yours)" or "") end
    end
    p.marks:SetText(#mk > 0 and Join(mk) or "No markers.")
    Flow(p)
end

---------------------------------------------------------------------------
-- Operations
---------------------------------------------------------------------------
local SORTS = {
    { key = "total", label = "Total time", tip = "Inclusive time: everything the operation called is in it." },
    { key = "self", label = "Self time", tip = "Inclusive time minus the instrumented operations inside it. Uninstrumented work it called stays in it." },
    { key = "max", label = "Slowest call" },
    { key = "p95", label = "95th percentile", tip = "Approximate: from log-spaced buckets about 19% wide." },
    { key = "calls", label = "Calls" },
}

local function BuildOperations()
    local p = NewPage("operations")
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("TwichUI's instrumented operations (and event callbacks, as event:NAME). Click one for its slowest calls. Times are elapsed time around each call, not the client's CPU counter. Total: inclusive (everything it called). Self: total minus the instrumented operations inside it (uninstrumented work it called stays in it). Percentiles are approximate (log buckets about 19% wide).")
    p.sort = Put(p, Chips(p, SORTS, state.sortBy, function(k) state.sortBy = k; W.Refresh() end, 118), 8)
    p.barsHost = Put(p, CreateFrame("Frame", nil, p), 8)
    p.barsHost:SetSize(CONTENT_W, 10)
    p.bars = Chart.Bars(p.barsHost, CONTENT_W - 8, 250)
    p.bars.onClick = function(item) state.selectedOp = item.key; W.Refresh() end
    p.detailHead = Heading(p, "Operation")
    p.detail = Put(p, Text(p, "small"), 4)
    Heading(p, "Counters")
    p.counters = Put(p, Text(p, "small"), 4)
    return p
end

local function Value(op, key)
    if key == "calls" then return op.calls end
    return op[key] or 0
end

local function RefreshOperations()
    local p = pages.operations
    local rec = Viewing()
    p.sort:Paint(state.sortBy)
    local list = {}
    for _, op in ipairs(rec and rec.ops or {}) do list[#list + 1] = op end
    table.sort(list, function(a, b)
        local va, vb = Value(a, state.sortBy), Value(b, state.sortBy)
        if va ~= vb then return va > vb end
        return a.id < b.id
    end)
    local items = {}
    for i = 1, math.min(#list, 16) do
        local op = list[i]
        local d = DX.Op(op.id)
        items[i] = { key = op.id, label = op.id, value = Value(op, state.sortBy),
            text = ("%d calls  %s total  %s self  %s mean  %s p95  %s max"):format(op.calls, DX.Ms(op.total), DX.Ms(op.self), DX.Ms(op.mean), DX.Ms(op.p95), DX.Ms(op.max)),
            tip = ("%s (%s, %s). Click for its slowest calls."):format(d.label, d.module, d.kind) }
    end
    p.bars.selected = state.selectedOp
    local h = p.bars:Draw(items, Chart.COLOR.work)
    p.barsHost:SetHeight(math.max(10, h))
    if #items == 0 then p.bars:Hide() end
    local sel
    for _, op in ipairs(list) do if op.id == state.selectedOp then sel = op end end
    sel = sel or list[1]
    if not sel then
        p.detail:SetText(rec and "No instrumented operation ran during this capture." or "No capture yet: record one on the Overview.")
    else
        local d = DX.Op(sel.id)
        local L = {
            ("%s  (%s; module %s, kind %s)"):format(sel.id, d.label, d.module, d.kind),
            ("%d calls; %s inclusive, %s self; mean %s; min %s, max %s; median %s, 95th %s, 99th %s (approximate)"):format(sel.calls, DX.Ms(sel.total), DX.Ms(sel.self),
                DX.Ms(sel.mean), DX.Ms(sel.min), DX.Ms(sel.max), DX.Ms(sel.p50), DX.Ms(sel.p95), DX.Ms(sel.p99)),
            ("busiest 10 seconds: %d calls; first at %s, last at %s; re-entered %d; aborted (an error went through) %d"):format(sel.peak10s or 0,
                DX.Clock2(sel.first), DX.Clock2(sel.last), sel.reentered or 0, sel.aborted or 0),
        }
        if sel.parents and #sel.parents > 0 then
            local ps = {}
            for _, x in ipairs(sel.parents) do ps[#ps + 1] = ("%s (%d)"):format(x.id, x.calls) end
            L[#L + 1] = "called inside: " .. table.concat(ps, ", ")
        end
        for _, m in ipairs(rec.measured or {}) do
            if m.id == sel.id then L[#L + 1] = ("allocation by the client's MeasureCall: %d bytes in %d calls (%.0f per call)"):format(m.allocatedBytes, m.calls, m.allocatedBytes / math.max(1, m.calls)) end
        end
        L[#L + 1] = "slowest calls:"
        for _, e in ipairs(sel.exemplars or {}) do
            L[#L + 1] = ("  %s at %s%s%s%s"):format(DX.Ms(e.ms), DX.Clock2(e.at), e.detail and ("  detail " .. e.detail) or "", e.combat and "  in combat" or "",
                e.parent and ("  inside " .. e.parent) or "")
            if e.stack then L[#L + 1] = "    call path: " .. e.stack end
        end
        if not rec.config.stacks then L[#L + 1] = "(call paths are taken only in a focused trace)" end
        p.detail:SetText(Join(L))
    end
    local cs = {}
    for _, cnt in ipairs(rec and rec.counters or {}) do cs[#cs + 1] = ("%s: %d"):format(cnt.id, cnt.count) end
    local an = rec and rec.anomalies or {}
    cs[#cs + 1] = ("dropped at the limits: %d operations, %d events, %d callbacks; scopes aborted %d, crossing a frame %d, clock steps back %d"):format(
        rec and rec.dropped.ops or 0, rec and rec.dropped.events or 0, rec and rec.dropped.callbacks or 0, an.aborted or 0, an.crossedFrame or 0, an.clockBack or 0)
    p.counters:SetText(Join(cs))
    Flow(p)
end

---------------------------------------------------------------------------
-- Events and lifecycle
---------------------------------------------------------------------------
local function BuildEvents()
    local p = NewPage("events")
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("One received event can reach several of TwichUI's callbacks; both are counted. Only TwichUI's own event bus is seen: not other addons' events, nor frames TwichUI registers directly.")
    p.barsHost = Put(p, CreateFrame("Frame", nil, p), 8)
    p.barsHost:SetSize(CONTENT_W, 10)
    p.bars = Chart.Bars(p.barsHost, CONTENT_W - 8, 250)
    Heading(p, "Callbacks (by time)")
    p.cbs = Put(p, Text(p, "small"), 4)
    Heading(p, "Listeners, pools, caches and what was shown")
    p.gauges = Put(p, Text(p, "small"), 4)
    Heading(p, "Timers")
    p.timers = Put(p, Text(p, "small"), 4)
    p.timers:SetText("TwichUI has no central timer registry, so timers created, cancelled or fired are not counted. What a module's own snapshot says about its waiting work (reminders waiting, Healer Watch's events) is among the gauges above.")
    return p
end

local function RefreshEvents()
    local p = pages.events
    local rec = Viewing()
    local items = {}
    for i, e in ipairs(rec and rec.events or {}) do
        if i > 14 then break end
        local per = e.received > 0 and e.callbacks / e.received or 0
        items[#items + 1] = { key = e.event, label = e.event, value = e.received,
            text = ("%d received  %d callbacks (%.1f each)  %s"):format(e.received, e.callbacks, per, DX.Ms(e.total)),
            tip = ("Up to %d listeners; callbacks' slowest %s."):format(e.maxListeners or 0, DX.Ms(e.max)) }
    end
    local h = p.bars:Draw(items, Chart.COLOR.events)
    p.barsHost:SetHeight(math.max(10, h))
    if #items == 0 then p.bars:Hide() end
    local cb = {}
    for i, c in ipairs(rec and rec.callbacks or {}) do
        if i > 12 then cb[#cb + 1] = ("... %d more in the full report"):format(#rec.callbacks - 12) break end
        cb[#cb + 1] = ("%s: %d calls, %s inclusive, %s self, slowest %s%s"):format(c.label, c.calls, DX.Ms(c.total), DX.Ms(c.self), DX.Ms(c.max),
            (c.aborted or 0) > 0 and (", errored " .. c.aborted) or "")
    end
    p.cbs:SetText(#cb > 0 and Join(cb) or "No callbacks ran.")
    local g = {}
    for _, def in ipairs(rec and rec.gauges and rec.gauges.defs or {}) do
        local series = F.GaugeSeries(rec, def.id)
        if #series > 0 then
            local peak, cycles = series[1].v, 0
            for _, s in ipairs(series) do
                if s.v > peak then peak = s.v end
                if s.cycle then cycles = cycles + 1 end
            end
            g[#g + 1] = ("%s (%s): %s at the start, %s at the end, highest %s; %d readings, %d after a window closed"):format(def.label, def.kind,
                tostring(series[1].v), tostring(series[#series].v), tostring(peak), #series, cycles)
        end
    end
    if rec and rec.gauges and rec.gauges.cycles then
        local cy = {}
        for k, v in pairs(rec.gauges.cycles) do cy[#cy + 1] = ("%s %d"):format(k, v) end
        if #cy > 0 then g[#g + 1] = "window cycles: " .. table.concat(cy, ", ") end
    end
    g[#g + 1] = "A rising listener count over repeated cycles is worth checking; one rise after a first open is often a page or feature starting."
    p.gauges:SetText(Join(g))
    Flow(p)
end

---------------------------------------------------------------------------
-- Memory
---------------------------------------------------------------------------
local MEMS = {
    { key = "core", label = "TwichUI (client)", tip = "GetAddOnMemoryUsage for !!!TwichUI: its Lua memory, garbage included." },
    { key = "settings", label = "TwichUI_Settings" },
    { key = "navdata", label = "TwichUI_NavData" },
    { key = "layouts", label = "TwichUI_Layouts" },
    { key = "diag", label = "TwichUI Diagnostics" },
    { key = "heap", label = "Whole UI heap" },
}

local function BuildMemory()
    local p = NewPage("memory")
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("Sampled memory: read at the preset's interval, so peaks between readings are not seen. Each reading is a point here.")
    p.chips = Put(p, Chips(p, MEMS, state.memMetric, function(k) state.memMetric = k; W.Refresh() end, 140), 8)
    p.chart = Chart.Line(p, CONTENT_W - 8, 200)
    Put(p, p.chart.frame, 6)
    p.summary = Put(p, Text(p, "small"), 8)
    Heading(p, "How to read it")
    p.read = Put(p, Text(p, "small"), 4)
    p.read:SetText(Join({
        "- The client's figure includes garbage not yet collected: it climbs between collections and drops after one.",
        "- Growth can be a cache warming up (pages drawn, rows built); a plateau after repeated actions is normal.",
        "- A net change is not how much was allocated: allocation and collection both happen between readings.",
        "- Per-addon figures are for the whole addon, and shared libraries count toward the addon that loaded them first (TwichUI loads first). They are not per module.",
        "- Readings are sparse; compare captures of the same steps, and use the collection experiment (Overview, Advanced) only on purpose.",
    }))
    return p
end

local function RefreshMemory()
    local p = pages.memory
    local rec = Viewing()
    p.chips:Paint(state.memMetric)
    local spec = { t = {}, v = {}, gap = {}, n = 0, unit = "KB", label = "Memory: " .. state.memMetric, color = Chart.COLOR.memory,
        duration = rec and rec.duration or 0, markers = {}, step = 1, hint = "A sampled reading (the client's figure, garbage included)." }
    local vals = {}
    for _, m in ipairs(rec and rec.memory or {}) do
        local v = m[state.memMetric]
        if v then
            spec.n = spec.n + 1
            spec.t[spec.n], spec.v[spec.n] = m.t, v
            vals[#vals + 1] = m
        end
    end
    spec.empty = rec and "No reading of this addon in this capture (not loaded, or the client gave none)." or "No capture yet."
    for _, mk in ipairs(rec and rec.markers or {}) do
        if mk.kind == "settings-closed" or mk.kind == "map-hidden" or mk.kind == "gc-experiment" or mk.auto == false then
            spec.markers[#spec.markers + 1] = { t = mk.t, kind = mk.kind, label = mk.label, mine = mk.auto == false }
        end
    end
    p.chart:Draw(spec)
    local s = {}
    if #vals > 0 then
        local first, last, peak, low = vals[1][state.memMetric], vals[#vals][state.memMetric], 0, math.huge
        for _, m in ipairs(vals) do local v = m[state.memMetric]; if v > peak then peak = v end; if v < low then low = v end end
        s[#s + 1] = ("%.0f KB at the start, %.0f KB at the end: %+.0f KB net; highest reading %.0f KB, lowest %.0f KB; %d readings"):format(first, last, last - first, peak, low, #vals)
    end
    if rec and rec.overhead then
        s[#s + 1] = ("The client's memory update ran %d times, %s in all, the slowest %s (the diagnostics' own cost; it updates every addon)."):format(
            rec.overhead.memoryReads or 0, DX.Ms(rec.overhead.memoryMs), DX.Ms(rec.overhead.memoryWorst))
    end
    if rec and rec.gcExperiment then s[#s + 1] = R.GOLD .. "A garbage collection experiment ran during this capture: readings after its marker are not comparable with those before.|r" end
    for _, def in ipairs(rec and rec.gauges and rec.gauges.defs or {}) do
        if def.kind == "cache" or def.kind == "pool" then
            local series = F.GaugeSeries(rec, def.id)
            if #series > 0 then s[#s + 1] = ("%s: %s to %s"):format(def.label, tostring(series[1].v), tostring(series[#series].v)) end
        end
    end
    p.summary:SetText(#s > 0 and Join(s) or "")
    Flow(p)
end

---------------------------------------------------------------------------
-- Errors
---------------------------------------------------------------------------
local function BuildErrors()
    local p = NewPage("errors")
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("Seen while recording: errors caught by TwichUI's own handlers (R.Fault), actions the client blocked or forbade for a TwichUI addon, and Lua warnings (counted; their text kept only when it names a TwichUI file). The game's error handler is never replaced, so errors in timers, frame scripts and other addons are not here: the game's own error display has them. An error near a long frame is not shown to be its cause.")
    p.list = Put(p, Text(p, "small"), 8)
    Heading(p, "An error you saw yourself")
    p.noteIntro = Put(p, Text(p, "meta"), 4)
    p.noteIntro:SetText("Type or paste the first line of an error you saw (your text: kept apart from what was observed, and shown as yours in exports). Local variables are never collected.")
    p.note = Put(p, Look().EditBox(p, CONTENT_W - 20, 22), 4)
    p.note:SetMaxLetters(300)
    p.note:SetScript("OnTextChanged", function(e, user)
        if not user then return end
        local rec = DX.Recording() and nil or Viewing()
        DX.SetErrorNote(rec, e:GetText())
    end)
    p.pre = Put(p, Text(p, "small"), 10)
    return p
end

local function RefreshErrors()
    local p = pages.errors
    local rec = DX.Recording() and DX.Live() or Viewing()
    local L = {}
    for _, e in ipairs(rec and rec.errors or {}) do
        L[#L + 1] = ("%s  %s from %s: %s  (x%d, first at %s%s)"):format(e.kind, e.ours and "TwichUI" or "other", e.source, e.text, e.n, DX.Clock2(e.first), e.combat and ", in combat" or "")
    end
    if #L == 0 then L[1] = rec and "None observed in this capture." or "No capture yet." end
    if rec then
        L[#L + 1] = ("%d in all; %d Lua warnings; %d blocked or forbidden actions of other addons (counted only)%s"):format(rec.errorCount or 0, rec.warnings or 0,
            rec.otherBlocked or 0, (rec.errorsDropped or 0) > 0 and ("; " .. rec.errorsDropped .. " more dropped at the limit") or "")
    end
    p.list:SetText(Join(L))
    if not p.note:HasFocus() then p.note:SetText(rec and rec.errorNote or "") end
    local D = R.Diag
    local st = D and D.Status and D.Status()
    p.pre:SetText(st and ("Before or outside captures, /tui diagnostics keeps the last %d errors TwichUI's handlers caught (%d now)."):format(D.MAX_ERRORS or 10, st.errors or 0) or "")
    Flow(p)
end

---------------------------------------------------------------------------
-- Compare
---------------------------------------------------------------------------
local function Picker(p, label, which)
    local row = CreateFrame("Frame", nil, p)
    row:SetSize(CONTENT_W, 24)
    row.label = Look().Text(row, "body"); row.label:SetPoint("LEFT"); row.label:SetWidth(90); row.label:SetText(label)
    row.prev = Look().ArrowButton(row, "up", function() W.Cycle(which, -1) end)
    row.next = Look().ArrowButton(row, "down", function() W.Cycle(which, 1) end)
    row.prev:SetPoint("LEFT", 92, 0); row.next:SetPoint("LEFT", row.prev, "RIGHT", 4, 0)
    row.text = Look().Text(row, "small"); row.text:SetPoint("LEFT", row.next, "RIGHT", 10, 0); row.text:SetWidth(CONTENT_W - 140)
    return row
end

function W.Cycle(which, step)
    local list = DX.Sessions()
    if #list == 0 then return end
    local key = which == "a" and "compareA" or (which == "b" and "compareB" or "viewing")
    local at = #list
    for i, s in ipairs(list) do if s.uid == state[key] then at = i end end
    at = (at - 1 + step) % #list + 1
    state[key] = list[at].uid
    if key == "viewing" then state.newCapture = false; state.window = nil; state.selectedOp = nil; state.built = nil end
    W.Refresh()
end

local function BuildCompare()
    local p = NewPage("compare")
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("A is the baseline. Every row is a rate or a per-call figure with its denominator, so captures of different lengths line up; a shorter capture is never called better for having less. The bars in a row share that row's scale only.")
    p.a = Put(p, Picker(p, "A (baseline)", "a"), 8)
    p.b = Put(p, Picker(p, "B", "b"), 4)
    p.legend = Put(p, Text(p, "meta"), 8)
    local ca, cb = Chart.COLOR.a, Chart.COLOR.b
    p.legend:SetText(("Bars: |cff%02x%02x%02x■|r A   |cff%02x%02x%02x■|r B (values are written beside them)"):format(ca[1] * 255, ca[2] * 255, ca[3] * 255, cb[1] * 255, cb[2] * 255, cb[3] * 255))
    p.warn = Put(p, Text(p, "small"), 6)
    p.rowsHost = Put(p, CreateFrame("Frame", nil, p), 6)
    p.rowsHost:SetSize(CONTENT_W, 10)
    p.rowsA = Chart.Bars(p.rowsHost, CONTENT_W - 8, 300)
    p.rowsB = Chart.Bars(p.rowsHost, CONTENT_W - 8, 300)
    Heading(p, "Operations")
    p.ops = Put(p, Text(p, "small"), 4)
    return p
end

local function RefreshCompare()
    local p = pages.compare
    local list = DX.Sessions()
    local function Find(uid) for _, s in ipairs(list) do if s.uid == uid then return s end end end
    local a = Find(state.compareA) or list[#list - 1]
    local b = Find(state.compareB) or list[#list]
    p.a.text:SetText(Describe(a))
    p.b.text:SetText(Describe(b))
    p.rowsA:Hide(); p.rowsB:Hide()
    if not (a and b) or a == b then
        p.warn:SetText("Two different captures are needed: record another (the same activity, with the one thing you want to compare changed), then pick them here.")
        p.ops:SetText("")
        p.rowsHost:SetHeight(10)
        Flow(p)
        return
    end
    local res = DX.Compare.Run(a, b)
    local w = {}
    if not res.compatible then w[1] = R.RED .. "Not comparable:|r " .. table.concat(res.warnings, " ") end
    if res.compatible then
        if #res.warnings == 0 then w[#w + 1] = R.GREEN .. "No comparability warnings.|r" end
        for _, x in ipairs(res.warnings) do w[#w + 1] = R.GOLD .. "warning:|r " .. x end
        for _, x in ipairs(res.notes) do w[#w + 1] = "note: " .. x end
    end
    p.warn:SetText(Join(w))
    -- each metric: two bars on that row's own scale (A above, B below), values in text
    local y = 0
    local ia, ib = {}, {}
    for _, r in ipairs(res.rows) do
        local mx = math.max(math.abs(r.a or 0), math.abs(r.b or 0))
        local change = r.pct and ("%+.0f%%"):format(r.pct * 100) or (r.change or "n/a")
        ia[#ia + 1] = { key = r.metric .. "a", label = ("%s (%s, %s)"):format(r.metric, r.unit, r.denominator), value = math.abs(r.a or 0) / math.max(mx, 1e-9),
            text = ("A %s"):format(r.a and ("%.3g"):format(r.a) or "n/a"), tip = r.note }
        ib[#ib + 1] = { key = r.metric .. "b", label = ("    %s %s"):format(r.direction or "", change), value = math.abs(r.b or 0) / math.max(mx, 1e-9),
            text = ("B %s  (difference %s)%s"):format(r.b and ("%.3g"):format(r.b) or "n/a", r.delta and ("%+.3g"):format(r.delta) or "n/a", r.note and ("  " .. r.note) or ""), tip = r.note }
    end
    if res.compatible then
        -- A's bar, then B's under it, for each metric
        p.rowsA:Draw(ia, Chart.COLOR.a, 1, 0)
        p.rowsB:Draw(ib, Chart.COLOR.b, 1, 0)
        for i = 1, #ia do
            p.rowsA.rows[i]:ClearAllPoints(); p.rowsA.rows[i]:SetPoint("TOPLEFT", p.rowsHost, "TOPLEFT", 0, -((i - 1) * 44))
            p.rowsB.rows[i]:ClearAllPoints(); p.rowsB.rows[i]:SetPoint("TOPLEFT", p.rowsHost, "TOPLEFT", 0, -((i - 1) * 44 + 20))
        end
        y = #ia * 44
    end
    p.rowsHost:SetHeight(math.max(10, y))
    local o = {}
    for _, row in ipairs(res.ops or {}) do
        local function C(x) if not x then return "n/a" end return ("%.3g -> %.3g (%s)"):format(x.a or 0, x.b or 0, x.pct and ("%+.0f%%"):format(x.pct * 100) or (x.change or "n/a")) end
        o[#o + 1] = ("%s: calls/min %s; ms/min %s; per call %s%s"):format(row.id, C(row.calls), C(row.total), row.mean and C(row.mean) or "-", row.note and ("; " .. row.note) or "")
    end
    p.ops:SetText(#o > 0 and Join(o) or "No operations in either capture.")
    Flow(p)
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local function BuildExport()
    local p = NewPage("export")
    local L = Look()
    p.intro = Put(p, Text(p, "small"), 0)
    p.intro:SetText("Built on this computer when you press Prepare, never sent anywhere. The game gives addons no clipboard and no files: read it, then select it in the box and press Ctrl+C. Large reports come in pieces with a header line each; join them in order.")
    local kinds = {}
    for _, k in ipairs(EX.KINDS) do kinds[#kinds + 1] = { key = k.key, label = k.label, tip = k.what } end
    p.kinds = Put(p, Chips(p, kinds, state.exportKind, function(k) state.exportKind = k; state.built = nil; W.Refresh() end, 150), 8)
    p.what = Put(p, Text(p, "meta"), 4)
    state.exportOpts = state.exportOpts or EX.Defaults()
    local function Opt(key, label)
        local row = CreateFrame("Frame", nil, p); row:SetSize(CONTENT_W, 20)
        row.box = L.Checkbox(row, function(on) state.exportOpts[key] = on; state.built = nil; W.Refresh() end); row.box:SetPoint("LEFT")
        row.text = L.Text(row, "small"); row.text:SetPoint("LEFT", row.box, "RIGHT", 8, 0); row.text:SetWidth(CONTENT_W - 40); row.text:SetText(label)
        row.key = key
        return Put(p, row, 4)
    end
    p.opts = {
        Opt("notes", "Include my notes (what I was doing, marker words, an error I typed): my own text, marked untrusted, with my character's names replaced"),
        Opt("traces", "Include the slowest calls of each operation"),
        Opt("stacks", "Include call paths (TwichUI's files only, relative to the AddOns folder; focused traces only)"),
        Opt("mapIds", "Include map IDs (only in a capture that noted them): where you were, so only if you want to share that"),
    }
    p.prepare = Put(p, Button(p, "Prepare", 110, "primary", function() W.Prepare() end, "Builds the text now from the capture shown (and, for Comparison, the A capture on Compare). Nothing is sent."), 10)
    p.info = Put(p, Text(p, "small"), 8)
    local nav2 = CreateFrame("Frame", nil, p); nav2:SetSize(CONTENT_W, 24)
    nav2.prev = Button(nav2, "Previous piece", 120, "secondary", function() state.piece = math.max(1, state.piece - 1); W.ShowPiece() end)
    nav2.next = Button(nav2, "Next piece", 120, "secondary", function() state.piece = state.piece + 1; W.ShowPiece() end)
    nav2.sel = Button(nav2, "Select all", 100, "secondary", function() W.SelectPiece() end)
    nav2.prev:SetPoint("LEFT"); nav2.next:SetPoint("LEFT", nav2.prev, "RIGHT", 6, 0); nav2.sel:SetPoint("LEFT", nav2.next, "RIGHT", 12, 0)
    nav2.text = L.Text(nav2, "meta"); nav2.text:SetPoint("LEFT", nav2.sel, "RIGHT", 12, 0)
    p.pieceNav = Put(p, nav2, 6)
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetSize(CONTENT_W - 8, 260)
    L.Well(box, 0.9)
    local sc = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sc:SetPoint("TOPLEFT", 6, -6); sc:SetPoint("BOTTOMRIGHT", -24, 6)
    L.ScrollBar(sc)
    local edit = CreateFrame("EditBox", nil, sc)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(0)
    edit:SetFontObject("GameFontHighlightSmall"); edit:SetWidth(CONTENT_W - 50); edit:SetTextInsets(2, 2, 2, 2)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function(e) e:HighlightText() end)
    edit:SetScript("OnTextChanged", function(e, user)   -- for reading and copying: typing puts the piece back
        local piece = state.built and state.built.pieces[state.piece]
        if user and piece then e:SetText(piece.text); e:HighlightText() end
    end)
    sc:SetScrollChild(edit)
    p.edit, p.box = edit, box
    Put(p, box, 6)
    return p
end

function W.Prepare()
    local rec = Viewing()
    if not rec then Say("there is no finished capture to export yet.") return end
    local other
    if state.exportKind == "compare" then
        local list = DX.Sessions()
        for _, s in ipairs(list) do if s.uid == state.compareA then other = s end end
        other = other or list[#list - 1]
        if not other or other == rec then Say("a comparison needs two captures: pick A on Compare.") return end
    end
    local built, why = EX.Build(state.exportKind, rec, other, state.exportOpts)
    if not built then
        Say("%s", why == "combat" and "exports wait until combat ends (nothing heavy runs in combat)." or ("couldn't prepare it (" .. tostring(why) .. ")."))
        return
    end
    state.built, state.piece = built, 1
    W.Refresh()
end

function W.ShowPiece()
    local p = pages.export
    local b = state.built
    if not (p and b) then return end
    state.piece = math.min(math.max(1, state.piece), #b.pieces)
    local piece = b.pieces[state.piece]
    p.edit:SetText(#b.pieces > 1 and piece.text or b.text)
    p.edit:SetCursorPosition(0)
    p.pieceNav.text:SetText(("piece %d of %d"):format(state.piece, #b.pieces))
    p.pieceNav.prev:SetEnabled(state.piece > 1)
    p.pieceNav.next:SetEnabled(state.piece < #b.pieces)
end

function W.SelectPiece()
    local p = pages.export
    if not (p and state.built) then return end
    p.edit:SetFocus()
    p.edit:HighlightText()
    p.pieceNav.text:SetText(("piece %d of %d selected: press Ctrl+C"):format(state.piece, #state.built.pieces))
end

local function RefreshExport()
    local p = pages.export
    p.kinds:Paint(state.exportKind)
    for _, k in ipairs(EX.KINDS) do if k.key == state.exportKind then p.what:SetText(k.what) end end
    for _, row in ipairs(p.opts) do row.box:SetChecked(state.exportOpts[row.key] and true or false) end
    local b = state.built
    p.pieceNav:SetShown(b ~= nil)
    p.box:SetShown(b ~= nil)
    if b then
        local red = {}
        for k, v in pairs(b.redaction) do red[#red + 1] = ("%s: %s"):format(k, v) end
        table.sort(red)
        p.info:SetText(Join({
            ("%s of %s: %d bytes (%.1f KB) in %d piece(s); Adler-32 of the whole %s."):format(b.kind, Describe(Viewing()), b.bytes, b.bytes / 1024, #b.pieces, b.adler32),
            "Sections: " .. table.concat(b.sections, ", ") .. ".",
            "Redaction: " .. table.concat(red, "; ") .. ".",
            "Read it before you share it. Nothing has been sent or saved.",
        }))
        W.ShowPiece()
    else
        local rec = Viewing()
        p.info:SetText(rec and ("Shown capture: %s. Choose what to include, then Prepare."):format(Describe(rec)) or "No finished capture yet: record one on the Overview.")
        p.edit:SetText("")
    end
    Flow(p)
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local BUILDERS = { overview = BuildOverview, timeline = BuildTimeline, operations = BuildOperations, events = BuildEvents,
    memory = BuildMemory, errors = BuildErrors, compare = BuildCompare, export = BuildExport }
local REFRESH = { overview = RefreshOverview, timeline = RefreshTimeline, operations = RefreshOperations, events = RefreshEvents,
    memory = RefreshMemory, errors = RefreshErrors, compare = RefreshCompare, export = RefreshExport }

local function PaintNav()
    for _, item in ipairs(navItems) do
        local sel = item.key == state.tab
        item.bar:SetShown(sel); item.fill:SetShown(sel)
        Look().Color(item.text, sel and Pal().text or Pal().textDim)
    end
end

local function SessionRefresh()
    if not win then return end
    local rec, list = Viewing()
    win.session.text:SetText(rec and Describe(rec) or "No capture yet")
    win.session.sub:SetText(("%d kept this session (at most %d); %d saved (at most %d)"):format(#list - (function()
        local n = 0 for _, s in ipairs(list) do if s.saved then n = n + 1 end end return n end)(), DX.prefs.keepInMemory,
        DX.DB() and #DX.DB().sessions or 0, DX.prefs.saveLimit))
    win.save:SetEnabled(rec ~= nil)
    win.save:SetText(rec and rec.saved and "Unsave" or "Save")
    win.discard:SetEnabled(rec ~= nil)
end

function W.Refresh()
    if not (win and win:IsShown()) then return end
    StripRefresh()
    SessionRefresh()
    local p = pages[state.tab]
    if not p then p = BUILDERS[state.tab]() end
    for k, other in pairs(pages) do other:SetShown(k == state.tab) end
    local ok, err = pcall(REFRESH[state.tab])
    if not ok then R.Fault("diagnostics window", err) end
    PaintNav()
end

function W.Go(tab)
    if not BUILDERS[tab] then tab = state.tab end
    state.tab = tab
    if scroll then scroll:SetVerticalScroll(0) end
    W.Refresh()
end

local function Build()
    local L = Look()
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
    tinsert(UISpecialFrames, FRAME_NAME)
    L.Shell(win, HEADER_H)
    local crest = win:CreateTexture(nil, "ARTWORK")
    crest:SetSize(24, 24); crest:SetPoint("TOPLEFT", 14, -9); crest:SetTexture(R.ICON)
    local title = L.Text(win, "title")
    title:SetPoint("LEFT", crest, "RIGHT", 8, 0); title:SetText("TwichUI Diagnostics")
    local sub = L.Text(win, "meta")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2); sub:SetText("performance and support")
    win.chip = L.Text(win, "small")
    win.chip:SetPoint("TOPRIGHT", -44, -15)
    L.CloseBox(win)

    nav = CreateFrame("Frame", nil, win, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", PAD, -(HEADER_H + 10))
    nav:SetPoint("BOTTOMLEFT", PAD, PAD)
    nav:SetWidth(NAV_W)
    L.Surface(nav, Pal().nav, 0.97, Pal().bronzeLo, 0.5)
    L.Recess(nav, 1.3)
    for i, tab in ipairs(W.TABS) do
        local b = CreateFrame("Button", nil, nav)
        b:SetSize(NAV_W - 8, 30)
        b:SetPoint("TOPLEFT", 4, -6 - (i - 1) * 32)
        b.fill = L.Solid(b, "BACKGROUND", Pal().bronzeText, 0.11); b.fill:SetAllPoints()
        b.bar = L.Solid(b, "ARTWORK", Pal().bronzeText, 1); b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(2)
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(20, 20); b.icon:SetPoint("LEFT", 8, 0)
        if R.Icons then R.Icons.Apply(b.icon, tab.icon, 20) else b.icon:SetTexture(R.ICON) end
        b.text = L.Text(b, "body"); b.text:SetPoint("LEFT", b.icon, "RIGHT", 8, 0); b.text:SetText(tab.label)
        b.key = tab.key
        b:SetScript("OnClick", function() W.Go(tab.key) end)
        R.Interact.Tip(b, tab.label, tab.tip)
        navItems[#navItems + 1] = b
    end
    -- the capture shown, under the views
    local s = CreateFrame("Frame", nil, nav)
    s:SetPoint("BOTTOMLEFT", 8, 10); s:SetPoint("BOTTOMRIGHT", -8, 10); s:SetHeight(120)
    s.head = L.Text(s, "heading"); s.head:SetPoint("TOPLEFT"); s.head:SetText("Capture shown")
    s.prev = L.ArrowButton(s, "up", function() W.Cycle("viewing", -1) end); s.prev:SetPoint("TOPLEFT", s.head, "BOTTOMLEFT", 0, -6)
    s.next = L.ArrowButton(s, "down", function() W.Cycle("viewing", 1) end); s.next:SetPoint("LEFT", s.prev, "RIGHT", 4, 0)
    R.Interact.Tip(s.prev, "Earlier capture", "Shows the capture before this one (this session's and saved ones).")
    R.Interact.Tip(s.next, "Later capture", "Shows the capture after this one.")
    s.text = L.Text(s, "small"); s.text:SetPoint("TOPLEFT", s.prev, "BOTTOMLEFT", 0, -6); s.text:SetWidth(NAV_W - 20)
    s.sub = L.Text(s, "meta"); s.sub:SetPoint("TOPLEFT", s.text, "BOTTOMLEFT", 0, -4); s.sub:SetWidth(NAV_W - 20)
    win.session = s
    win.save = Button(s, "Save", 74, "secondary", function()
        local rec = Viewing()
        if not rec then return end
        if rec.saved then DX.Unsave(rec.uid) W.Refresh() return end
        local ok, why = DX.Save(rec.uid)
        if not ok then Say("%s", why == "full" and ("at most %d captures are saved; unsave one first."):format(DX.prefs.saveLimit)
            or (why == "newer" and "a newer TwichUI Diagnostics saved data here; nothing is written over it." or "it can't be saved right now.")) end
        W.Refresh()
    end, "Keeps this capture in TwichUI Diagnostics' saved variables, which the game writes when you log out or reload (only then). A saved timeline is merged to at most 300 buckets (the worst of each kept).")
    win.discard = Button(s, "Discard", 74, "danger", function()
        local rec = Viewing()
        if not rec then return end
        R.Interact.Confirm("TWICHUI_DIAG_DISCARD", ("Discard capture %s?%s"):format(Describe(rec), rec.saved and "\n\nIts saved copy is removed too." or ""),
            function() DX.Discard(rec.uid, true); state.viewing = nil; state.built = nil; W.Refresh() end, { accept = "Discard" })
    end, "Forgets this capture (and its saved copy, if saved). Asks first.")
    win.save:SetPoint("BOTTOMLEFT", 0, 0)
    win.discard:SetPoint("LEFT", win.save, "RIGHT", 6, 0)

    local area = CreateFrame("Frame", nil, win)
    area:SetPoint("TOPLEFT", nav, "TOPRIGHT", 12, 0)
    area:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    BuildStrip(area)
    scroll = CreateFrame("ScrollFrame", nil, area, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -STRIP_H)
    scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    L.ScrollBar(scroll)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(content)

    -- live updates while shown and recording: the strip every second; the Timeline at most every LIVE_REDRAW seconds
    local ticker
    win:HookScript("OnShow", function()
        if badge then badge:Hide() end
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(1, function()
            if not win:IsShown() then return end
            StripRefresh()
            if DX.Recording() then
                if state.tab == "overview" then RefreshOverview()
                elseif state.tab == "timeline" and GetTime() - state.lastLive >= LIVE_REDRAW then
                    state.lastLive = GetTime()
                    RefreshTimeline()
                end
            end
        end)
    end)
    win:HookScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
        if pages.export then pages.export.edit:ClearFocus() end
        if GameTooltip and GameTooltip:IsOwned(win) then GameTooltip:Hide() end
        W.Badge()
    end)
    DX.OnChange(function(what)
        if what == "finished" then
            local list = DX.Sessions()
            state.viewing = list[#list] and list[#list].uid or nil
            state.newCapture, state.window, state.selectedOp, state.built = false, nil, nil, nil
        end
        if win:IsShown() then W.Refresh() end
        W.Badge()
    end)
end

function DX.Open(tab)
    if not win then Build() end
    win:Show()
    win:Raise()
    W.Go(tab)
end

function DX.Close() if win then win:Hide() end end
-- The window's choices (tab, preset, export kind, ...): for tests.
function W.State() return state end
function W.Badged() return badge ~= nil and badge:IsShown() end
function DX.Toggle(tab) if win and win:IsShown() then win:Hide() else DX.Open(tab) end end

---------------------------------------------------------------------------
-- The recording badge (only while a capture records and the window is closed)
---------------------------------------------------------------------------
local badgeTicker
function W.Badge()
    local want = DX.Recording() and not DX.WindowShown() and DX.prefs.badge
    if not want then
        if badge then badge:Hide() end
        if badgeTicker then badgeTicker:Cancel(); badgeTicker = nil end
        return
    end
    local L = Look()
    if not badge then
        badge = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        badge:SetSize(300, 26)
        badge:SetPoint("TOP", 0, -8)
        badge:SetFrameStrata("MEDIUM")
        badge:SetMovable(true)
        badge:RegisterForDrag("LeftButton")
        badge:SetScript("OnDragStart", badge.StartMoving)
        badge:SetScript("OnDragStop", badge.StopMovingOrSizing)
        L.Surface(badge, Pal().band, 0.92, Pal().bronze, 0.8)
        badge.text = L.Text(badge, "small")
        badge.text:SetPoint("LEFT", 10, 0)
        badge:SetScript("OnClick", function() DX.Open() end)
        R.Interact.Tip(badge, "TwichUI Diagnostics is recording", "Click to open the window (Stop is there, or type /tui perf stop). Drag to move it. It stops by itself at its length.")
    end
    local function Paint()
        local live = DX.Live()
        if not (live and DX.Recording()) then W.Badge() return end
        badge.text:SetText(("%s●|r Recording  %s  %s / %s"):format(R.GREEN, live.presetName, DX.Clock2(DX.Now() - live.t0 / 1000), DX.Clock2(live.minutes * 60)))
    end
    Paint()
    badge:Show()
    if not badgeTicker then badgeTicker = C_Timer.NewTicker(1, Paint) end
end
DX.OnChange(function() W.Badge() end)

-- The last file: TwichUI_Diagnostics is ready (DiagnosticsLauncher.lua checks for this after loading it).
R.Diagnostics = DX
