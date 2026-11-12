-- TwichUI Test Lab: the runner (R.TestLab.Runner)
-- Runs the chosen cases one after another, each as a coroutine, spread over frames. COOPERATIVE: Lua coroutines are not preempted, so
-- nothing here can interrupt code that is running. What it does instead:
--   * each frame it resumes cases until about SLICE seconds have passed (measured), then waits for the next frame;
--   * a case that wants to share a frame calls t:Yield() at a safe point (t:Wait(seconds) is a pause across frames that costs nothing
--     while it waits); a case that never yields runs to its end in one step, so cases that cannot yield are kept small;
--   * every step is timed; a step longer than a slice is counted as an OVERRUN and reported with its case (it was never cut short);
--   * a case that has not finished when its budget is spent is ABANDONED at a yield point (never resumed again), status "timeout";
--     a step that overran its budget and then finished keeps its result and is reported as late;
--   * Stop, the run cap and combat all work the same way: no further step is scheduled. The case that was waiting at a yield point is
--     marked "stopped"; nothing running was interrupted, because nothing can be.
-- One frame with an OnUpdate exists only while a run is active; PLAYER_REGEN_DISABLED is registered only then too. Nothing runs at load.
--
-- Result statuses: pass, fail, error (the case raised), skipped, timeout, stopped (never ran, or abandoned at a yield point).

local R = TwichUI
local TL = R.TestLab
local RN = {}
TL.Runner = RN

RN.SLICE = 0.005        -- seconds of work per frame
RN.RUN_CAP = 300        -- seconds for a whole run
RN.MAX_OVERRUNS = 20    -- overruns kept for the report

local state    -- the active run, or nil
local frame

---------------------------------------------------------------------------
-- The clock: a high resolution one where the client has it. debugprofilestart is never called (it would reset a counter other code uses).
---------------------------------------------------------------------------
function RN.ClockName()
    if GetTimePreciseSec then return "GetTimePreciseSec" end
    if debugprofilestop then return "debugprofilestop" end
    return "GetTime"
end

local function Clock()
    if GetTimePreciseSec then return GetTimePreciseSec() end
    if debugprofilestop then return debugprofilestop() / 1000 end
    return GetTime()
end

local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- A guided case may hold a temporary key binding and a prompt (Guided.lua). Whatever ends a case or the run, they are released. Cleanup only:
-- it schedules nothing and never changes a case's result.
local function ReleaseGuided()
    local G = TL.Guided
    if G and G.End then pcall(G.End) end
end

---------------------------------------------------------------------------
-- Finishing
---------------------------------------------------------------------------
local STOP_TEXT = { user = "Stop was pressed", combat = "combat started", closed = "the window was closed", cap = "the run time cap was reached" }

local function Count(results)
    local c = { pass = 0, fail = 0, error = 0, skipped = 0, timeout = 0, stopped = 0, pending = 0, running = 0 }
    for _, r in ipairs(results) do c[r.status] = (c[r.status] or 0) + 1 end
    return c
end
RN.Count = Count

local function Summary(s, ended)
    local now = s.clock()
    return { results = s.results, counts = Count(s.results), cats = s.cats, seconds = now - s.startedAt, frames = s.frames, slices = s.slices,
        worstSlice = s.worstSlice, worstFrame = s.worstFrame, overruns = s.overruns, overrunCount = s.overrunCount, ended = ended,
        clock = RN.ClockName(), slice = s.slice, active = false }
end

local function Finish(reason)
    local s = state
    if not s then return end
    state = nil
    -- no more work is scheduled: the frame stops updating and stops listening before anything else
    frame:SetScript("OnUpdate", nil)
    frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    ReleaseGuided()
    local why = STOP_TEXT[reason]
    if s.cur then
        local r = s.cur.r
        r.status = "stopped"
        r.detail = ("%s while it waited at a yield point; it was not resumed"):format(why or reason)
        r.ms = (s.clock() - s.cur.started) * 1000
        s.cur = nil
    end
    for i = s.i + 1, #s.results do
        local r = s.results[i]
        r.status = "stopped"
        r.detail = ("%s before it started"):format(why or reason)
    end
    s.summary = Summary(s, reason)
    RN.last = s.summary
    if s.onDone then
        local ok, err = pcall(s.onDone, s.summary)
        if not ok then RN.callbackError = tostring(err) end
    end
end

---------------------------------------------------------------------------
-- One case
---------------------------------------------------------------------------
local function Verdict(cur)
    local t, r = cur.t, cur.r
    r.facts = t.facts
    r.notes = t.notes
    r.checks = t.checks
    if t.skipped then
        r.status, r.detail = "skipped", t.skipped
    elseif t.failed then
        r.status, r.detail = "fail", table.concat(t.fails, "; ")
    else
        r.status = "pass"
    end
    -- a read-only case must leave the saved roots as they were (also checked for pure ones: it is cheap)
    local after = TL.Fingerprint()
    if after ~= cur.fingerprint and r.status ~= "error" then
        r.status = "fail"
        r.detail = (r.detail and (r.detail .. "; ") or "") .. "the saved data changed while this case ran (it may have been the game's own change; run it again)"
    end
end

-- Starts the next case. Returns the active case, or nil when it was settled without running (skipped).
local function Begin(s)
    s.i = s.i + 1
    local r = s.results[s.i]
    local case = s.list[s.i]
    r.status = "running"
    local W
    if case.needs then
        for _, need in ipairs(case.needs) do
            if need == "workshop" then
                local ws, why = TL.Workshop()
                if not ws then
                    r.status, r.detail = "skipped", why
                    return nil
                end
                W = ws
            end
        end
    end
    local t = TL.NewT(case, W)
    s.cur = { co = coroutine.create(case.run), t = t, case = case, r = r, started = s.clock(), fingerprint = TL.Fingerprint() }
    return s.cur
end

local function Overrun(s, cur, dur)
    s.overrunCount = s.overrunCount + 1
    if #s.overruns < RN.MAX_OVERRUNS then
        s.overruns[#s.overruns + 1] = { id = cur.case.id, ms = dur * 1000 }
    end
end

-- A case that has not finished when its budget is spent is dropped at its yield point and never resumed
local function Abandon(s, cur, total)
    local r = cur.r
    s.cur = nil
    ReleaseGuided()
    r.status = "timeout"
    r.detail = ("abandoned at a yield point after %.1f s (budget %.0f s); it was not resumed"):format(total, cur.case.budget)
    r.ms = total * 1000
    r.facts, r.checks, r.notes = cur.t.facts, cur.t.checks, cur.t.notes
end

-- Resumes the active case once and settles it if it ended, was abandoned or overran
local function Step(s, cur)
    local a = s.clock()
    s.stepping = true
    local ok, err = coroutine.resume(cur.co, cur.t)
    s.stepping = false
    local b = s.clock()
    local dur = b - a
    local r = cur.r
    if dur > s.slice then Overrun(s, cur, dur) end
    local dead = coroutine.status(cur.co) == "dead"
    local total = b - cur.started
    r.ms = total * 1000
    if not ok then
        s.cur = nil
        ReleaseGuided()
        if err == TL.SKIP then
            r.status, r.detail = "skipped", cur.t.skipped
            r.facts, r.checks, r.notes = cur.t.facts, cur.t.checks, cur.t.notes
        else
            r.status, r.detail = "error", tostring(err)
            r.facts, r.checks, r.notes = cur.t.facts, cur.t.checks, cur.t.notes
        end
    elseif dead then
        s.cur = nil
        ReleaseGuided()
        Verdict(cur)
        if total > cur.case.budget then
            r.detail = (r.detail and (r.detail .. "; ") or "") .. ("late: it took %.1f s of its %.0f s budget, and could not be interrupted"):format(total, cur.case.budget)
        end
    elseif total > cur.case.budget then
        Abandon(s, cur, total)
    end
end

-- true while the active case is paused by t:Wait (no step is scheduled until the time has passed); a paused case whose budget runs out
-- is abandoned, and false is returned
local function Waiting(s, cur)
    local resume = cur.t.waitUntil
    if not resume then return false end
    local now = s.clock()
    if now >= resume then cur.t.waitUntil = nil return false end
    local total = now - cur.started
    if total > cur.case.budget then
        Abandon(s, cur, total)
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Tell(s)
    if s.onProgress then
        local ok, err = pcall(s.onProgress, RN.Progress())
        if not ok then RN.callbackError = tostring(err) end
    end
end

local function OnUpdate(_, elapsed)
    local s = state
    if not s then return end
    s.frames = s.frames + 1
    if s.frames > 1 and type(elapsed) == "number" and elapsed > s.worstFrame then s.worstFrame = elapsed end
    if InCombat() then return Finish("combat") end
    local t0 = s.clock()
    if t0 - s.startedAt > s.cap then return Finish("cap") end
    local now = t0
    local paused
    repeat
        local cur = s.cur
        if not cur then
            if s.i >= #s.list then return Finish("complete") end
            cur = Begin(s)
        end
        paused = false
        if cur then
            paused = Waiting(s, cur)
            if not paused and s.cur == cur then Step(s, cur) end
        end
        if s.stopRequested then return Finish(s.stopRequested) end
        now = s.clock()
    until paused or now - t0 >= s.slice
    s.slices = s.slices + 1
    if now - t0 > s.worstSlice then s.worstSlice = now - t0 end
    Tell(s)
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then RN.Stop("combat") end
end

---------------------------------------------------------------------------
-- The API
---------------------------------------------------------------------------
-- list: cases from TL.Select. opts: onProgress(progress) once per frame, onDone(summary), cats (names, for the report), and for tests
-- clock, slice, cap. Returns true, or false and why: "running", "empty", "combat".
function RN.Start(list, opts)
    opts = opts or {}
    if state then return false, "running" end
    if type(list) ~= "table" or #list == 0 then return false, "empty" end
    if InCombat() then return false, "combat" end
    frame = frame or CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    local clock = opts.clock or Clock
    local results = {}
    for i, c in ipairs(list) do
        results[i] = { id = c.id, cat = c.cat, class = c.class, label = TL.Label(c), status = "pending", facts = {} }
    end
    state = { list = list, results = results, i = 0, clock = clock, slice = opts.slice or RN.SLICE, cap = opts.cap or RN.RUN_CAP,
        onProgress = opts.onProgress, onDone = opts.onDone, cats = opts.cats or {}, startedAt = clock(), frames = 0, slices = 0,
        worstSlice = 0, worstFrame = 0, overruns = {}, overrunCount = 0 }
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnUpdate", OnUpdate)
    return true
end

-- Stops the run. Between frames nothing is executing, so it takes effect at once: the remaining cases are marked "stopped" and no
-- further step is scheduled. (If called from inside a step it takes effect when that step returns.) Returns false when idle.
function RN.Stop(reason)
    local s = state
    if not s then return false end
    if s.stepping then
        s.stopRequested = reason or "user"
        return true
    end
    Finish(reason or "user")
    return true
end

function RN.Active() return state ~= nil end

-- What the window shows while a run is active (nil when idle)
function RN.Progress()
    local s = state
    if not s then return nil end
    local cur = s.cur
    local at = cur and s.i or math.min(#s.list, s.i + 1)
    return { active = true, n = #s.list, at = at, id = s.list[at] and s.list[at].id, seconds = s.clock() - s.startedAt,
        results = s.results, counts = Count(s.results), overrunCount = s.overrunCount }
end

-- The clock the run is measured by, in seconds (cases use it to time themselves)
function RN.Now() return state and state.clock() or Clock() end

-- For the tests and the diagnostics: is anything of the runner still live?
function RN.Snapshot()
    return { active = state ~= nil, updating = frame ~= nil and frame:GetScript("OnUpdate") ~= nil,
        listening = frame ~= nil and frame:IsEventRegistered("PLAYER_REGEN_DISABLED") or false }
end
