-- TwichUI Test Lab: what the window shows (R.TestLab.View)
-- PURE presentation logic: it turns the runner's records ({ id, status, class, label, ms, detail, notes, facts, checks, fails } per case, and
-- the counts) into the words, counts, filters, empty-state sentences and details the window draws. No frame, no game call, no clock, no saved
-- value, and it never changes a record, so the same functions are tested offline and drawn in the game. It invents nothing: a detail is what
-- the case recorded (its failure lines, its evidence notes, its facts), and a field the case did not record is simply absent.
--
--   V.Categories()                      the registry's categories with their case counts (nothing typed here)
--   V.Kind(r), V.Word(r), V.Duration(ms)
--   V.Counts(results)                   { all, fail, pass, guided, synthetic, client, skipped, error, timeout, stopped } for the filter chips
--   V.Tally(results)                    { total, pass, fail, skipped, error, timeout, stopped, pending, running, finished }
--   V.Select(results, filter, query)    the records that match a filter and a search, in their order
--   V.Row(r)                            what one table row shows
--   V.Cards(m), V.State(m), V.Empty(m, filter, query)
--   V.Details(r)                        what the details panel shows for one result
--   V.FirstProblem(results)             the first failed case, else the first error, else the first timeout
-- m (the run as the window knows it) = { phase = "idle" | "running" | "finished" | "stopped", results, seconds, ended, chosen (cases chosen to
--   run), chosenGroups, current (the running record), at, n }

local R = TwichUI
local TL = R.TestLab
local V = {}
TL.View = V

local RP = TL.Report

V.FILTERS = {
    { id = "all", label = "All" }, { id = "fail", label = "Failed" }, { id = "pass", label = "Passed" }, { id = "guided", label = "Guided" },
    { id = "synthetic", label = "Synthetic" }, { id = "client", label = "Client" },
    -- shown only when the run has some, so an error or a timeout is never hidden and the row stays calm
    { id = "skipped", label = "Skipped" }, { id = "error", label = "Errors" }, { id = "timeout", label = "Timeouts" }, { id = "stopped", label = "Stopped" },
}
V.ALWAYS = 6   -- the first six chips are always shown

local KIND_WORD = { synthetic = "Synthetic", client = "Client", guided = "Guided" }
V.KIND_WORD = KIND_WORD
V.KIND_NOTE = {
    synthetic = "Our code, run in this game's Lua on made-up data.",
    client = "Observed in this game client.",
    guided = "Observed with your help (a pointer probe).",
}
local WORD = { pass = "Pass", fail = "Fail", error = "Error", skipped = "Skipped", timeout = "Timeout", stopped = "Stopped", pending = "Waiting", running = "Running" }
-- A guided case is not a function that is running: it is waiting for a person, or the person skipped it, or the observation was cancelled part
-- way. The words say which, so a skipped step is never mistaken for a completed measurement.
local GUIDED_WORD = { running = "Your turn", skipped = "Skipped", stopped = "Cancelled", pass = "Measured" }
local ENDED = { user = "Stop was pressed", combat = "combat started", closed = "the window was closed", cap = "the run time cap was reached" }

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
function V.Kind(r)
    if r.class == "guided" or r.label == "guided" then return "guided" end
    if r.label == "synthetic" or (r.label == nil and r.class == "pure") then return "synthetic" end
    return "client"
end

function V.Word(r)
    if r.class == "guided" or r.label == "guided" then
        if r.status == "stopped" and r.ms == nil then return "Not run" end
        if GUIDED_WORD[r.status] then return GUIDED_WORD[r.status] end
    end
    return WORD[r.status] or tostring(r.status)
end

function V.Duration(ms)
    if type(ms) ~= "number" or ms ~= ms then return "" end
    if ms < 1000 then return ("%.1f ms"):format(ms) end
    if ms < 60000 then return ("%.2f s"):format(ms / 1000) end
    local s = math.floor(ms / 1000 + 0.5)
    return ("%d min %02d s"):format(math.floor(s / 60), s % 60)
end

local function Seconds(s) return ("%.2f s"):format(tonumber(s) or 0) end

function V.Categories()
    local out = {}
    for _, id in ipairs(TL.categoryOrder) do
        local cat = TL.categories[id]
        out[#out + 1] = { id = id, label = cat.label, blurb = cat.blurb, guided = cat.guided, optin = cat.optin, manual = cat.manual, count = TL.Count(id) }
    end
    return out
end

---------------------------------------------------------------------------
-- Counting, filtering, searching
---------------------------------------------------------------------------
local function Matches(id, r)
    if id == "all" then return true end
    if id == "guided" or id == "synthetic" or id == "client" then return V.Kind(r) == id end
    return r.status == id
end

function V.Counts(results)
    local c = {}
    for _, f in ipairs(V.FILTERS) do c[f.id] = 0 end
    for _, r in ipairs(results or {}) do
        for _, f in ipairs(V.FILTERS) do
            if Matches(f.id, r) then c[f.id] = c[f.id] + 1 end
        end
    end
    return c
end

function V.Tally(results)
    local t = { total = 0, pass = 0, fail = 0, skipped = 0, error = 0, timeout = 0, stopped = 0, pending = 0, running = 0, finished = 0 }
    for _, r in ipairs(results or {}) do
        t.total = t.total + 1
        t[r.status] = (t[r.status] or 0) + 1
        if r.status ~= "pending" and r.status ~= "running" and r.status ~= "stopped" then t.finished = t.finished + 1 end
    end
    return t
end

-- the lower-cased text a search looks in: the id, the kind, the status word and the start of the message; remembered while the record is unchanged
local hay = setmetatable({}, { __mode = "k" })
local function Haystack(r)
    local h = hay[r]
    if h and h.status == r.status and h.detail == r.detail then return h.text end
    local text = table.concat({ tostring(r.id), KIND_WORD[V.Kind(r)] or "", V.Word(r), tostring(r.detail or ""):sub(1, 300) }, " "):lower()
    hay[r] = { status = r.status, detail = r.detail, text = text }
    return text
end

local function Words(query)
    local words = {}
    for w in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    return words
end
V.Words = Words

-- The records of `filter` whose text holds every word of `query` (a plain match, never a pattern). Order is the run's order.
function V.Select(results, filter, query)
    local out, words = {}, Words(query)
    for _, r in ipairs(results or {}) do
        if Matches(filter or "all", r) then
            local ok = true
            if #words > 0 then
                local text = Haystack(r)
                for _, w in ipairs(words) do
                    if not text:find(w, 1, true) then ok = false break end
                end
            end
            if ok then out[#out + 1] = r end
        end
    end
    return out
end

function V.FirstProblem(results)
    for _, kind in ipairs({ "fail", "error", "timeout" }) do
        for _, r in ipairs(results or {}) do if r.status == kind then return r end end
    end
    return nil
end

---------------------------------------------------------------------------
-- One table row
---------------------------------------------------------------------------
-- The message column: the first failure line, or the case's own detail; "OK" for a pass that said nothing
function V.Message(r)
    if r.status == "pending" then return "" end
    if r.class == "guided" and r.status == "running" then return "waiting for you: follow the prompt at the top of the screen" end
    if r.status == "fail" and r.fails and r.fails[1] then return RP.Clean(r.fails[1], 160) end
    if r.detail and r.detail ~= "" then return RP.Clean(r.detail, 160) end
    if r.status == "pass" then return "OK" end
    return ""
end

function V.Row(r)
    return { word = V.Word(r), status = r.status, kind = KIND_WORD[V.Kind(r)], kindId = V.Kind(r), duration = V.Duration(r.ms), message = V.Message(r) }
end

---------------------------------------------------------------------------
-- The summary cards and the run state
---------------------------------------------------------------------------
local function Plural(n, one, many) return n == 1 and one or many end

-- Seven cards: { value, tone, lit, note }. Before a run every value is "-" (not run, which is not zero failures). During a run the counts are
-- the cases finished so far; they never count an unfinished case as passed.
function V.Cards(m)
    local t = V.Tally(m.results)
    local cards = {}
    local function Card(key, value, tone, lit, note) cards[key] = { value = value, tone = tone, lit = lit, note = note } end
    if m.phase == "idle" then
        for _, key in ipairs({ "total", "pass", "fail", "skipped", "error", "timeout", "duration" }) do Card(key, "-", "pending", false) end
        return cards
    end
    local notRun = t.stopped + t.pending
    Card("total", tostring(t.total), "running", true, notRun > 0 and m.phase ~= "running" and (notRun .. " not run") or nil)
    Card("pass", tostring(t.pass), "pass", t.pass > 0)
    Card("fail", tostring(t.fail), "fail", t.fail > 0)
    Card("skipped", tostring(t.skipped), "skipped", t.skipped > 0)
    Card("error", tostring(t.error), "error", t.error > 0)
    Card("timeout", tostring(t.timeout), "timeout", t.timeout > 0)
    Card("duration", ("%.2f s"):format(tonumber(m.seconds) or 0), "running", m.phase == "running")
    return cards
end

-- { text, tone, detail }: the run state beside the buttons
function V.State(m)
    local t = V.Tally(m.results)
    if m.phase == "idle" then
        if (m.chosen or 0) == 0 then return { text = "Nothing chosen", tone = "skipped", detail = "Tick at least one group on the left, then press Run." } end
        local more = m.guidedChosen and " A guided group asks you to place the pointer: the window steps aside while it waits." or ""
        return { text = "Not run yet", tone = "pending", detail = ("Press Run to run the %d chosen %s.%s"):format(m.chosen, Plural(m.chosen, "case", "cases"), more) }
    end
    if m.phase == "running" then
        local cur = m.current
        local where = ("case %d of %d"):format(m.at or 0, m.n or t.total)
        if cur and cur.class == "guided" then
            return { text = "Waiting for you", tone = "running", detail = where .. ": follow the prompt at the top of the screen" }
        end
        return { text = "Running", tone = "running", detail = where .. (cur and (": " .. cur.id) or "") .. ("  |  %.1f s"):format(tonumber(m.seconds) or 0) }
    end
    if m.phase == "stopped" then
        local notRun = t.stopped + t.pending
        local why = ENDED[m.ended] or tostring(m.ended)
        return { text = "Stopped", tone = "timeout",
            detail = ("%s after %s; %d %s not run. A step that was running could not have been interrupted."):format(
                why:sub(1, 1):upper() .. why:sub(2), Seconds(m.seconds), notRun, Plural(notRun, "case", "cases")) }
    end
    local bad = t.fail + t.error + t.timeout
    local last = ("Last run: %s, %d %s"):format(Seconds(m.seconds), t.total, Plural(t.total, "case", "cases"))
    if bad > 0 then
        local parts = {}
        if t.fail > 0 then parts[#parts + 1] = ("%d failed"):format(t.fail) end
        if t.error > 0 then parts[#parts + 1] = ("%d %s"):format(t.error, Plural(t.error, "error", "errors")) end
        if t.timeout > 0 then parts[#parts + 1] = ("%d %s"):format(t.timeout, Plural(t.timeout, "timeout", "timeouts")) end
        return { text = "Finished with problems", tone = "fail", detail = last .. "; " .. table.concat(parts, ", ") }
    end
    if t.pass == 0 and t.skipped > 0 then return { text = "Finished: every case was skipped", tone = "skipped", detail = last } end
    return { text = "Finished: all passed", tone = "pass", detail = last .. (t.skipped > 0 and ("; " .. t.skipped .. " skipped") or "") }
end

-- The sentence for a table that has no row to show, or nil when it has rows. n: how many rows the filter and the search left.
function V.Empty(m, filter, query, n)
    if n and n > 0 then return nil end
    local total = #(m.results or {})
    if total == 0 then
        if (m.chosen or 0) == 0 then return "No group is chosen. Tick at least one on the left, then press Run." end
        return ("Nothing has run yet. Press Run to run the %d chosen %s; the results appear here as they finish."):format(m.chosen, Plural(m.chosen, "case", "cases"))
    end
    local words = Words(query)
    if #words > 0 then
        local q = tostring(query):gsub("^%s+", ""):gsub("%s+$", "")
        local label
        for _, x in ipairs(V.FILTERS) do if x.id == filter then label = x.label:lower() end end
        local among = (filter ~= "all" and label) and (" among the " .. label .. " cases") or ""
        return ('No case matches "%s"%s. Clear the search to see them again.'):format(q:sub(1, 40), among)
    end
    local t = V.Tally(m.results)
    if filter == "fail" then return t.error + t.timeout > 0 and "No case failed an assertion. Errors and timeouts are under their own chips." or "No case failed in this run." end
    if filter == "pass" then return "No case has passed yet." end
    return "No case in this run is a " .. (filter or "matching") .. " case."
end

---------------------------------------------------------------------------
-- The details of one result
---------------------------------------------------------------------------
-- Seeds named in the evidence ("seed 7100008"): quoted from what the case wrote, never guessed. At most four.
function V.Seeds(texts)
    local out, seen = {}, {}
    for _, text in ipairs(texts) do
        for n in tostring(text):gmatch("[Ss]eed (%d+)") do
            if not seen[n] and #out < 4 then seen[n] = true; out[#out + 1] = n end
        end
    end
    return out
end

local MAX_FACTS = 14

function V.Details(r)
    local d = { id = r.id, status = r.status, word = V.Word(r), kind = V.Kind(r), ms = r.ms, checks = r.checks, facts = {}, notes = {}, fails = {} }
    d.kindWord, d.kindNote = KIND_WORD[d.kind], V.KIND_NOTE[d.kind]
    d.duration = V.Duration(r.ms)
    for _, f in ipairs(r.fails or {}) do d.fails[#d.fails + 1] = RP.Clean(f, 400) end
    for i, f in ipairs(r.facts or {}) do
        if i > MAX_FACTS then d.moreFacts = #r.facts - MAX_FACTS break end
        d.facts[#d.facts + 1] = { RP.Clean(f[1], 60), RP.Clean(f[2], 80) }
    end
    for _, n in ipairs(r.notes or {}) do d.notes[#d.notes + 1] = RP.Clean(n, 400) end
    local detail = r.detail and RP.Clean(r.detail, 400) or nil
    local s = r.status
    if s == "fail" then
        d.headline = d.fails[1] or detail or "A check failed."
        if r.failed and r.failed > #d.fails then d.hidden = r.failed - #d.fails end   -- the case records at most 8 failure lines
    elseif s == "pass" then
        d.headline = r.checks and r.checks > 0 and ("%d %s passed."):format(r.checks, Plural(r.checks, "check", "checks")) or "Passed."
        if detail then d.body = detail end   -- a late note, for one
    elseif s == "error" then
        d.headline, d.body = "The case raised an error before it finished.", detail
    elseif s == "timeout" then
        d.headline = detail or "The case did not finish within its budget."
    elseif s == "skipped" then
        d.headline = detail or "Skipped."
    elseif s == "stopped" then
        d.headline = detail or "It did not run to the end."
    elseif s == "running" then
        d.headline = d.kind == "guided" and "Waiting for you: follow the prompt at the top of the screen." or "Running now."
    else
        d.headline = "Waiting to run."
    end
    local sources = { d.headline }
    for _, f in ipairs(d.fails) do sources[#sources + 1] = f end
    for _, n in ipairs(d.notes) do sources[#sources + 1] = n end
    d.seeds = V.Seeds(sources)
    return d
end
