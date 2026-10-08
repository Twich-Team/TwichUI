-- TwichUI: diagnostics service
-- One place to look when something does not work. It is a local aid, not telemetry: nothing is saved,
-- sent or posted, and a report only leaves the game if the player copies it out and shares it.
--
-- What it holds:
--   * Providers. A module (or its diag/ file) registers a function that returns a small snapshot of its
--     own state: configured, initialized, a status word, and short lines of codes and counts. Reports
--     are built on demand by asking each provider, each under pcall, so a broken or missing provider
--     costs its own section and nothing else. Nothing walks the addon's state in the background.
--   * Temporary tracing. Off until asked for. While on, modules (and tracers' own event listeners,
--     registered only while tracing) add short records to a bounded in-memory buffer; it stops by
--     itself after TRACE_SECONDS and is never written to saved variables.
--   * A tiny ring of recent errors caught by TwichUI's own event and init handlers (Core.lua calls
--     D.Error just before handing the error on; the game's error handler is not replaced or hidden).
--   * A privacy backstop (D.Clean). The real protection is that providers and trace calls pass codes,
--     counts and anonymous labels, never names or messages; Clean only catches what slips through.
--
-- Everything here is reached through R.Diag at call time, so modules work without it (tests load
-- subsets of the addon).

local R = TwichUI
local D = {}
R.Diag = D

D.FORMAT = 1                -- report format version, printed in every report
D.MAX_RECORDS = 200         -- trace records kept; the oldest go first
D.MAX_DETAIL = 96           -- characters in one record's detail
D.MAX_ERRORS = 10           -- recent errors kept
D.MAX_ERROR_TEXT = 140
D.TRACE_SECONDS = 900       -- tracing stops by itself after this long
local COALESCE = 2          -- seconds: an identical record straight after another is counted, not added
local RATE_WINDOW, RATE_MAX = 1, 40   -- at most this many records a second; the rest are counted and dropped
local MAX_LABELS = 64       -- anonymous labels per kind in one trace
local MAX_LINES, MAX_LINE = 60, 200   -- a provider's section is bounded too

-- Modules the report knows by name, so one that did not load shows as absent instead of vanishing.
local KNOWN = {
    { "environment", "Environment" },
    { "saved", "Saved data" },
    { "notify", "Notification coordination" },
    { "friend", "Friend notifications" },
    { "food", "Food and water buttons" },
    { "arrival", "Zone arrival card" },
    { "chronicle", "Chronicle zone arrival" },
    { "sharing", "Configuration sharing" },
}

local providers, order = {}, {}
local tracers, tracerOrder = {}, {}
local buffer = {}
local dropped, limited = 0, 0
local rateStart, rateCount = 0, 0
local tracing, started, token, stopReason = false, nil, 0, nil
local labelers = {}
local termCache
local errors = {}
local listeners = {}
local frame, routes, refused = nil, {}, {}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- `value` as a boolean while `on`, and nil (does not apply) otherwise: for a snapshot's `initialized`.
function D.When(on, value)
    if not on then return nil end
    return value and true or false
end

function D.Flag(v)
    if Secret(v) then return "?" end
    if v == true then return "yes" elseif v == false then return "no" end
    return "?"
end

local function Changed()
    for _, fn in ipairs(listeners) do pcall(fn) end
end
function D.OnChange(fn) listeners[#listeners + 1] = fn end

---------------------------------------------------------------------------
-- Privacy backstop
---------------------------------------------------------------------------
-- Strings that name this character: their name, realm and guild. Read when needed and kept only for
-- the length of a trace; never printed.
local function BuildTerms()
    local terms = {}
    local function Add(s)
        if type(s) == "string" and not Secret(s) and #s >= 3 then terms[#terms + 1] = s end
    end
    if UnitName then Add((UnitName("player"))) end
    if GetUnitName then Add(GetUnitName("player", true)) end
    Add(GetRealmName and GetRealmName())
    Add(GetNormalizedRealmName and GetNormalizedRealmName())
    if GetGuildInfo then Add((GetGuildInfo("player"))) end
    if R.Share and R.Share.SelfName then
        local ok, name = pcall(R.Share.SelfName)
        if ok then Add(name) end
    end
    return terms
end

local function Terms()
    return termCache or BuildTerms()
end

-- Replaces whole-word, case-insensitive matches of term (so "Forever" inside "ForeverDungeonJournal" stays).
local function ReplacePlain(text, term, with)
    local lower, wanted = text:lower(), term:lower()
    local out, pos, from = {}, 1, 1
    while true do
        local s, e = lower:find(wanted, from, true)
        if not s then break end
        local before, after = text:sub(s - 1, s - 1), text:sub(e + 1, e + 1)
        local inside = (before ~= "" and (before:find("[%w\128-\255]"))) or (after ~= "" and (after:find("[%w\128-\255]")))
        if inside then
            from = s + 1
        else
            out[#out + 1] = text:sub(pos, s - 1)
            out[#out + 1] = with
            pos, from = e + 1, e + 1
        end
    end
    if pos == 1 then return text end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- A value fit for a report line: numbers and booleans as they are, other types by name, secret values
-- as such, and text with the game's escape codes and links removed, this character's own name, realm and
-- guild and anything shaped like a BattleTag replaced, and the length capped. A best-effort net under
-- the codes-and-counts rule, not a guarantee. Returns nil for nil.
-- keepNames: leave this character's name, realm and guild alone. Used for the fixed text a provider writes
-- itself (the realm may be called "Forever", like the game); event details and error text always get them replaced.
function D.Clean(v, max, keepNames)
    if v == nil then return nil end
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if Secret(v) then return "<secret>" end
        if v ~= v then return "nan" end
        return tostring(v)
    end
    if t ~= "string" then return "<" .. t .. ">" end
    if Secret(v) then return "<secret>" end
    max = max or MAX_LINE
    local s = v
    s = s:gsub("|H.-|h.-|h", "<link>")
    s = s:gsub("|K.-|k", "<hidden>")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|[rRnN]", " ")
    s = s:gsub("|", "/")
    s = s:gsub("%S+#%d%d%d%d+", "<battletag>")
    if not keepNames then
        for _, term in ipairs(Terms()) do s = ReplacePlain(s, term, "<name>") end
    end
    s = s:gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if #s > max then
        local cut = math.max(0, max - 3)
        while cut > 0 do   -- do not end in the middle of a multi-byte character
            local b = s:byte(cut + 1)
            if b and b >= 0x80 and b < 0xC0 then cut = cut - 1 else break end
        end
        s = s:sub(1, cut) .. "..."
    end
    return s
end
local Clean = D.Clean

-- A Lua error as a report line: only errors thrown from TwichUI's own files keep their message
-- (without the folder prefix); any other is reduced to a note, so another addon's text never lands here.
local function CleanError(err)
    if Secret(err) then return "<secret>" end
    local text = type(err) == "string" and err or tostring(err)
    local first = text:match("^[^\n]*") or ""
    local addon = R.ADDON or "TwichUI"
    if not first:find(addon, 1, true) then return "(thrown outside TwichUI's files; message left out)" end
    local escaped = addon:gsub("%p", "%%%0")
    first = first:gsub("^.-" .. escaped .. "[\\/]", "")
    return Clean(first, D.MAX_ERROR_TEXT)
end

---------------------------------------------------------------------------
-- Anonymous labels (F1, P2 ...). A label stands for one id or name for the length of a trace; the raw
-- value is held only to keep the label the same and is dropped when tracing stops or records are cleared.
---------------------------------------------------------------------------
local function NewLabeler(prefix)
    local n, map = 0, {}
    return function(key)
        local t = type(key)
        if (t ~= "number" and t ~= "string") or Secret(key) then return prefix .. "?" end
        local k = t .. ":" .. key
        local label = map[k]
        if not label then
            if n >= MAX_LABELS then return prefix .. "+" end
            n = n + 1
            label = prefix .. n
            map[k] = label
        end
        return label
    end
end

-- A fresh labeler for one report or snapshot; nothing of it outlives the call.
function D.NewLabeler(prefix) return NewLabeler(prefix) end

-- The label for key within the current trace; a placeholder when not tracing (nothing is remembered then).
function D.Label(prefix, key)
    if not tracing then return prefix .. "?" end
    local labeler = labelers[prefix]
    if not labeler then
        labeler = NewLabeler(prefix)
        labelers[prefix] = labeler
    end
    return labeler(key)
end

local PREFIX_FOR = { friend = "F", ["friend-event"] = "F", share = "P" }

---------------------------------------------------------------------------
-- Tracing
---------------------------------------------------------------------------
function D.Tracing() return tracing end

local function Context()
    local combat = InCombatLockdown and InCombatLockdown() and true or false
    local kind = "?"
    if IsInInstance then
        local _, t = IsInInstance()
        if type(t) == "string" and not Secret(t) then kind = t:gsub("[^%w]", ""):sub(1, 10) end
    end
    return combat, kind
end

local function Record(src, code, detail, subject, synthetic)
    local now = GetTime()
    if now - rateStart >= RATE_WINDOW then rateStart, rateCount = now, 0 end
    rateCount = rateCount + 1
    if rateCount > RATE_MAX then limited = limited + 1 return end
    src, code = Clean(src, 16) or "?", Clean(code, 32) or "?"
    local who = subject ~= nil and D.Label(PREFIX_FOR[src] or "X", subject) or nil
    detail = Clean(detail, D.MAX_DETAIL)
    synthetic = synthetic and true or false
    local last = buffer[#buffer]
    if last and last.src == src and last.code == code and last.who == who and last.detail == detail
        and last.syn == synthetic and now - last.last <= COALESCE then
        last.n, last.last = last.n + 1, now
        return
    end
    if #buffer >= D.MAX_RECORDS then
        table.remove(buffer, 1)
        dropped = dropped + 1
    end
    local combat, kind = Context()
    buffer[#buffer + 1] = { t = now - started, last = now, src = src, code = code, who = who,
        detail = detail, n = 1, syn = synthetic, combat = combat, inst = kind }
end

-- Adds a record while tracing; does nothing (and costs one test) otherwise. Callers pass codes, counts
-- and raw ids as `subject` (turned into an anonymous label here), never names or message text.
--   src      the area: "friend", "food", "arrival", "chronicle", "notify", "share", "diag"
--   code     a short stable reason or event code
--   detail   optional short text or number
--   subject  optional id, shown only as a label
--   synthetic  true for a test or preview: shown as SYNTHETIC, proof of nothing about real events
function D.Trace(src, code, detail, subject, synthetic)
    if not tracing then return end
    local ok = pcall(Record, src, code, detail, subject, synthetic)
    if not ok then limited = limited + 1 end
end

-- A record of a synthetic action (a made-up card, a self-test), marked as such.
function D.Synthetic(src, code, detail)
    D.Trace(src, code, detail, nil, true)
end

-- tracer: { events = { "EVENT", ... }, onEvent = function(event, ...), start = fn, stop = fn, clear = fn }
-- Its events are listened for on the service's own frame only while tracing. Everything is optional.
function D.RegisterTracer(key, tracer)
    if not tracers[key] then tracerOrder[#tracerOrder + 1] = key end
    tracers[key] = tracer
end

local function OnEvent(_, event, ...)
    local list = routes[event]
    if not list then return end
    for _, key in ipairs(list) do
        local tracer = tracers[key]
        if tracer and tracer.onEvent then
            local ok, err = pcall(tracer.onEvent, event, ...)
            if not ok then D.Trace("diag", "tracer-error", key .. ": " .. tostring(err)) end
        end
    end
end

local function StopNow(reason)
    tracing = false
    token = token + 1
    stopReason = reason
    if frame then frame:UnregisterAllEvents() end
    wipe(routes)
    for _, key in ipairs(tracerOrder) do
        local tracer = tracers[key]
        if tracer and tracer.stop then pcall(tracer.stop) end
    end
    wipe(labelers)
    termCache = nil
end

function D.Start()
    if tracing then return false, "already-on" end
    tracing, started, stopReason = true, GetTime(), nil
    token = token + 1
    local mine = token
    termCache = BuildTerms()
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    wipe(refused)
    wipe(routes)
    rateStart, rateCount = 0, 0
    Record("diag", "trace-started", D.TRACE_SECONDS .. "s limit")
    for _, key in ipairs(tracerOrder) do
        local tracer = tracers[key]
        if tracer.start then
            local ok, err = pcall(tracer.start)
            if not ok then Record("diag", "tracer-error", key .. " start: " .. tostring(err)) end
        end
        for _, event in ipairs(tracer.events or {}) do
            if pcall(frame.RegisterEvent, frame, event) then
                routes[event] = routes[event] or {}
                table.insert(routes[event], key)
            else
                refused[#refused + 1] = event
                Record("diag", "event-refused", event)
            end
        end
    end
    -- An old timer can't be cancelled; it checks it still belongs to this trace.
    C_Timer.After(D.TRACE_SECONDS, function()
        if tracing and token == mine then D.Stop("timeout") end
    end)
    Changed()
    return true
end

-- reason: "manual" or "timeout"; shown in the report.
function D.Stop(reason)
    if not tracing then return false end
    Record("diag", "trace-stopped", reason or "manual")
    StopNow(reason or "manual")
    Changed()
    return true
end

-- Forgets every record, error and label. Tracing, if on, carries on.
function D.Clear()
    wipe(buffer)
    wipe(errors)
    wipe(labelers)
    dropped, limited, rateStart, rateCount = 0, 0, 0, 0
    if not tracing then stopReason = nil end
    for _, key in ipairs(tracerOrder) do
        local tracer = tracers[key]
        if tracer and tracer.clear then pcall(tracer.clear) end
    end
    if tracing then Record("diag", "records-cleared", "tracing continues") end
    Changed()
end

function D.Status()
    local now = GetTime()
    return {
        tracing = tracing,
        elapsed = tracing and (now - started) or 0,
        remaining = tracing and math.max(0, D.TRACE_SECONDS - (now - started)) or 0,
        records = #buffer, max = D.MAX_RECORDS, dropped = dropped, limited = limited,
        errors = #errors, stopReason = stopReason, refused = #refused,
    }
end

-- The records, oldest first, as copies of what is shown (for tests and the report).
function D.Records()
    local out = {}
    for i, r in ipairs(buffer) do
        out[i] = { t = r.t, src = r.src, code = r.code, who = r.who, detail = r.detail, n = r.n, synthetic = r.syn,
            combat = r.combat, instance = r.inst }
    end
    return out
end

---------------------------------------------------------------------------
-- Errors caught by TwichUI's own handlers
---------------------------------------------------------------------------
-- Called by Core.lua just before the error goes on to the game's handler. Never throws, never keeps
-- the original object, and keeps only errors from TwichUI's own files in full.
function D.Error(source, err)
    pcall(function()
        local text = CleanError(err)
        source = Clean(source, 40) or "?"
        for _, e in ipairs(errors) do
            if e.src == source and e.text == text then
                e.n, e.last = e.n + 1, GetTime()
                return
            end
        end
        if #errors >= D.MAX_ERRORS then table.remove(errors, 1) end
        errors[#errors + 1] = { src = source, text = text, n = 1, last = GetTime() }
    end)
end

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------
-- spec: { title = "Friend notifications", order = 30, snapshot = function() -> snapshot }
-- snapshot: {
--   configured  true / false / nil (not a setting)
--   initialized true / false / nil (does not apply)
--   status      "ready" | "waiting" | "unavailable" | "off" | "unknown": only what the module can say it is
--   reason      a short code for the status, optional
--   lines       { "text", ... } codes and counts
--   limits      { "known limitation", ... }
-- }
function D.Register(key, spec)
    if not providers[key] then order[#order + 1] = key end
    providers[key] = spec
    table.sort(order, function(a, b)
        local oa, ob = providers[a].order or 100, providers[b].order or 100
        if oa ~= ob then return oa < ob end
        return a < b
    end)
end

local STATUS = { ready = true, waiting = true, unavailable = true, off = true, unknown = true }

local function Word(v, yes, no, none)
    if v == true then return yes elseif v == false then return no end
    return none
end

local function Lines(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for i = 1, math.min(#list, MAX_LINES) do
        local line = list[i]
        if type(line) == "string" or type(line) == "number" then out[#out + 1] = Clean(line, MAX_LINE, true) end
    end
    if #list > MAX_LINES then out[#out + 1] = ("(%d more lines left out)"):format(#list - MAX_LINES) end
    return out
end

-- One provider's snapshot made safe: { key, title, configured, initialized, status, reason, lines, limits, failed }.
local function Collect(key, title)
    local spec = providers[key]
    local entry = { key = key, title = title or (spec and spec.title) or key, lines = {}, limits = {} }
    if not spec then
        entry.status, entry.reason, entry.absent = "unavailable", "not-loaded", true
        return entry
    end
    entry.title = spec.title or entry.title
    local ok, snap = pcall(spec.snapshot)
    if not ok then
        entry.status, entry.reason, entry.failed = "unavailable", "provider-error", true
        entry.lines = { "snapshot failed: " .. (CleanError(snap) or "?") }
        D.Error("diag:" .. key, snap)
        return entry
    end
    if type(snap) ~= "table" then
        entry.status, entry.reason, entry.failed = "unavailable", "provider-invalid", true
        return entry
    end
    entry.configured, entry.initialized = snap.configured, snap.initialized
    local status = STATUS[snap.status] and snap.status or "unknown"
    if snap.configured == false and status ~= "unavailable" then status = "off" end
    entry.status = status
    entry.reason = Clean(snap.reason, 40)
    entry.lines, entry.limits = Lines(snap.lines), Lines(snap.limits)
    return entry
end

-- Every known provider, then any others, in order.
local function CollectAll()
    local entries, seen = {}, {}
    for _, known in ipairs(KNOWN) do
        entries[#entries + 1] = Collect(known[1], known[2])
        seen[known[1]] = true
    end
    for _, key in ipairs(order) do
        if not seen[key] then entries[#entries + 1] = Collect(key) end
    end
    -- Registered providers by their own order; a module that did not load keeps the place the list above gives it.
    local function Place(e)
        if providers[e.key] and providers[e.key].order then return providers[e.key].order end
        for i, known in ipairs(KNOWN) do
            if known[1] == e.key then return i * 10 end
        end
        return 1000
    end
    for i, e in ipairs(entries) do e.index = i end
    table.sort(entries, function(a, b)
        local oa, ob = Place(a), Place(b)
        if oa ~= ob then return oa < ob end
        return a.index < b.index
    end)
    return entries
end

local function SummaryLine(e)
    local status = e.status
    if e.reason and e.reason ~= "" then status = status .. " (" .. e.reason .. ")" end
    return ("%s: configured %s, initialized %s, %s"):format(e.title, Word(e.configured, "on", "off", "n/a"),
        Word(e.initialized, "yes", "no", "n/a"), status)
end

-- The status of each module, one short line each (the window's summary).
function D.Summary()
    local out = {}
    for _, e in ipairs(CollectAll()) do out[#out + 1] = { key = e.key, title = e.title, status = e.status, line = SummaryLine(e) } end
    return out
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------
local function TraceSection(add)
    local s = D.Status()
    add("== Trace ==")
    if s.tracing then
        add(("tracing: ON for %ds (stops by itself after %d minutes); %d of at most %d records kept"):format(s.elapsed, D.TRACE_SECONDS / 60, s.records, s.max))
    else
        local why = s.stopReason == "timeout" and "stopped by itself at the time limit"
            or (s.stopReason == "manual" and "stopped by you") or "never started this session (it is off until asked for, and not kept across a reload)"
        add(("tracing: off (%s); %d records kept"):format(why, s.records))
    end
    if s.dropped > 0 or s.limited > 0 then
        add(("%d oldest records dropped to stay within the limit; %d dropped by the rate limit"):format(s.dropped, s.limited))
    end
    if s.refused > 0 then add(("%d events the game would not let the trace listen for"):format(s.refused)) end
    add("legend: +seconds since tracing started; xN = repeated; [c] in combat; SYNTHETIC = a test or preview, not a real event")
    if #buffer == 0 then add("(no records)") end
    for _, r in ipairs(buffer) do
        add(("+%.1fs  %s%s %s%s%s%s  [%s,%s]"):format(r.t, r.syn and "SYNTHETIC  " or "", r.src, r.code,
            r.who and (" " .. r.who) or "", r.detail and r.detail ~= "" and (" (" .. r.detail .. ")") or "",
            r.n > 1 and (" x" .. r.n) or "", r.combat and "c" or "-", r.inst))
    end
end

local function ErrorSection(add)
    add("== Recent TwichUI errors ==")
    add("Only errors caught by TwichUI's own event and startup handlers are listed, not every error: timers, frame scripts and other addons are not covered. For full error capture use an error display addon such as BugSack; TwichUI does not require one.")
    if #errors == 0 then add("(none caught)") end
    local now = GetTime()
    for _, e in ipairs(errors) do
        add(("%s: %s%s  (%ds ago)"):format(e.src, e.text, e.n > 1 and (" x" .. e.n) or "", now - e.last))
    end
end

-- The computer's clock, labelled as such: the client's date() is the ordinary one, and nothing here
-- claims a time zone it has not checked.
local function Stamp()
    if not (date and time) then return "unknown (no clock)" end
    local ok, text = pcall(date, "%Y-%m-%d %H:%M:%S", time())
    if ok and type(text) == "string" then return text .. " (this computer's local time)" end
    return "unknown (the clock could not be read)"
end

-- Builds the report text and the per-module summary. Safe to call at any time; nothing is changed.
function D.Build()
    local lines = {}
    local function add(text) lines[#lines + 1] = text end
    local entries = CollectAll()
    add("TwichUI diagnostic report")
    add("report format: " .. D.FORMAT)
    add("generated: " .. Stamp())
    add("Built on this computer from TwichUI's own state. Nothing was sent anywhere. It leaves out character, realm, guild, friend and BattleTag names, chat, Chronicle entries and configuration contents; read it before you share it.")
    add("")
    add("== Summary ==")
    add("Status words are what each module reports about itself; \"ready\" means it believes it can work, not that it was seen working in play.")
    local summary = {}
    for _, e in ipairs(entries) do
        add(SummaryLine(e))
        summary[#summary + 1] = { key = e.key, title = e.title, status = e.status, line = SummaryLine(e) }
    end
    for _, e in ipairs(entries) do
        add("")
        add("== " .. e.title .. " ==")
        add(SummaryLine(e))
        if e.absent then
            add("this module is not part of this install or did not start")
        else
            for _, line in ipairs(e.lines) do add(line) end
            for _, limit in ipairs(e.limits) do add("limitation: " .. limit) end
        end
    end
    add("")
    ErrorSection(add)
    add("")
    TraceSection(add)
    add("")
    add("== end of report ==")
    return table.concat(lines, "\n"), summary
end

D.Report = D.Build
