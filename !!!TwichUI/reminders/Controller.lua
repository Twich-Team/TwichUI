-- TwichUI: Reminders, the controller
-- Puts the parts together: which reminders run here (Config.lua's views, Evaluate.lua's applicability), what they read
-- (their conditions' observation keys, handed to State.lua, which listens for exactly those), what they decide, and
-- when that is shown (Display.lua). It never equips, uses, casts or sends anything, and nothing it decides is saved.
--
-- Lifecycle:
--   * Reminders switched off: nothing listened for, every frame hidden, every timer stale.
--   * On, before the world: only PLAYER_ENTERING_WORLD.
--   * On, in the world: the observation keys the running reminders read, and nothing else. A reminder that is off,
--     invalid or for another character reads nothing (the settings window peeks for it when it is looked at).
--   * An observation that changed re-decides only the reminders that read it (the index). A change to a reminder's
--     look or place redraws only its frame; a change to its rules, its switch or the list builds the index again.
--
-- Timing (both optional, both a reminder's display settings):
--   delay    seconds its conditions must keep matching before it shows; if they stop matching first, nothing shows
--            and the wait is cancelled.
--   minShow  once shown, seconds it stays up even if its conditions stop matching (then it goes, unless they match
--            again meanwhile). Turning the reminder off, deleting it, a different character or class, Reminders
--            switched off and a profile change hide it at once: the minimum never outlasts an explicit choice.
-- Each pending wait carries a token; anything that cancels it bumps the token, and a refresh bumps a generation, so a
-- timer from before (or from before switching off) never shows anything.

local R = TwichUI
local RM = R.Reminders
local C = R.ReminderConditions
local E = R.ReminderEval
local ST = R.ReminderState
local D = R.ReminderDisplay
local Perf = R.Perf
local CT = {}
R.ReminderController = CT

local NOMATCH = C.NOMATCH

local rt = {}          -- [id] = { token, visible, shownAt, wantSince, phase, out }
local index = {}       -- [observation key] = { id, ... }
local active = {}      -- [id] = true: runs here (read and decided live)
local running = false  -- on and in the world
local gen = 0
local listeners = {}
local stats = { refreshes = 0, decisions = 0, shows = 0, hides = 0 }

local function Rec(id)
    local r = rt[id]
    if not r then
        r = { token = 0, visible = false }
        rt[id] = r
    end
    return r
end

local function Cancel(r)
    r.token = r.token + 1
    r.phase, r.wantSince = nil, nil
end

-- Runs fn after `seconds` unless r's wait was cancelled, a refresh happened or Reminders stopped meanwhile.
local function After(r, seconds, fn)
    r.token = r.token + 1
    local mine, g = r.token, gen
    C_Timer.After(seconds, function()
        if r.token ~= mine or gen ~= g or not running then return end
        fn()
    end)
end

local function Show(v, r)
    r.phase, r.wantSince = nil, nil
    if r.visible then return end
    r.visible, r.shownAt = true, GetTime()
    stats.shows = stats.shows + 1
    D.SetLive(v, true)
end

local function Hide(v, r, immediate)
    r.phase = nil
    if not r.visible then return end
    r.visible, r.shownAt = false, nil
    stats.hides = stats.hides + 1
    D.SetLive(v, false, immediate)
end

-- Hidden now, whatever its timing says (off, deleted, not for this character, invalid, switched off).
local function HardHide(v, r)
    Cancel(r)
    if r.visible then Hide(v, r, true) end
end

local function Tell(id)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, id)
        if not ok then R.Fault("reminders view", err) end
    end
end

-- What its decision means for the screen, with its timing.
local function Act(v, r)
    local status = r.out.status
    if not running or (status ~= "showing" and status ~= "hidden" and status ~= "waiting") then
        HardHide(v, r)
        return
    end
    local now = GetTime()
    local d = v.display
    if status == "showing" then
        if r.phase == "holding" then Cancel(r) end
        if r.visible then return end
        if d.delay > 0 then
            r.wantSince = r.wantSince or now
            local left = r.wantSince + d.delay - now
            if left > 0 then
                if r.phase ~= "pending" then
                    local since = r.wantSince
                    After(r, left, function()
                        local cur = RM.Get(v.id)
                        if cur and r.out and r.out.status == "showing" then Show(cur, r); Tell(v.id) end
                    end)
                    r.phase, r.wantSince = "pending", since
                end
                return
            end
        end
        Cancel(r)
        Show(v, r)
        return
    end
    -- hidden, or unknown (which never shows): stop any wait to show, and keep it up for its minimum if it has one
    if r.phase == "pending" then Cancel(r) end
    r.wantSince = nil
    if not r.visible then return end
    local left = d.minShow > 0 and r.shownAt and (r.shownAt + d.minShow - now) or 0
    if left > 0 then
        if r.phase ~= "holding" then
            After(r, left, function()
                local cur = RM.Get(v.id)
                if cur and r.out and r.out.status ~= "showing" then Hide(cur, r); Tell(v.id) end
            end)
            r.phase = "holding"
        end
        return
    end
    Cancel(r)
    Hide(v, r)
end

local function Decide(v, obs, ctx)
    local pt = Perf.on and Perf.Start("reminders.decide")
    local r = Rec(v.id)
    r.out = E.Run(v, obs, ctx, r.out)
    stats.decisions = stats.decisions + 1
    Act(v, r)
    if pt then Perf.Stop(pt) end
end

---------------------------------------------------------------------------
-- Refresh: everything, from the top. Safe to call at any time.
---------------------------------------------------------------------------
local function Refresh()
    gen = gen + 1
    stats.refreshes = stats.refreshes + 1
    local views = RM.List()
    local present = {}
    for _, v in ipairs(views) do present[v.id] = true end
    -- gone (deleted, or not in this profile): its frame and timers go with it
    for id, r in pairs(rt) do
        if not present[id] then
            Cancel(r)
            rt[id] = nil
        end
    end
    D.Prune(present)

    for k in pairs(index) do index[k] = nil end
    for k in pairs(active) do active[k] = nil end

    if not R:Enabled("reminders") then
        running = false
        ST.Stop()
        for _, r in pairs(rt) do Cancel(r); r.visible = false; r.out = nil end
        D.HideAll()
        Tell(nil)
        return
    end
    ST.Start()
    running = ST.InWorld()
    if not running then
        ST.Want({})
        for _, v in ipairs(views) do HardHide(v, Rec(v.id)) end
        Tell(nil)
        return
    end

    local ctx = ST.Context()
    local want = {}
    for _, v in ipairs(views) do
        if v.valid and v.enabled and E.Applies(v, ctx) ~= NOMATCH then
            active[v.id] = true
            for _, entry in ipairs(v.conditions) do
                entry.provider.Needs(entry.cond, function(key)
                    want[key] = true
                    local ids = index[key]
                    if not ids then ids = {}; index[key] = ids end
                    if ids[#ids] ~= v.id then ids[#ids + 1] = v.id end
                end)
            end
        end
    end
    ST.Want(want)
    local obs = ST.Observations()
    for _, v in ipairs(views) do
        if active[v.id] then
            Decide(v, obs, ctx)
        else
            local r = Rec(v.id)
            r.out = nil
            HardHide(v, r)
        end
    end
    Tell(nil)
end
-- (inside a scope while TwichUI Diagnostics records; a plain call otherwise)
function CT.Refresh() return Perf.Call("reminders.refresh", Refresh) end

-- Observations changed (nil: the world was entered, read everything again).
ST.OnChange(function(changed)
    if changed == nil then
        ST.ReadAll()
        CT.Refresh()
        return
    end
    if not running then return end
    local due = {}
    for key in pairs(changed) do
        for _, id in ipairs(index[key] or {}) do due[id] = true end
    end
    local obs, ctx = ST.Observations(), ST.Context()
    for id in pairs(due) do
        local v = RM.Get(id)
        if v and active[id] then
            Decide(v, obs, ctx)
            Tell(id)
        end
    end
end)

-- A reminder changed in the settings (or a profile change, id nil).
RM.Subscribe(function(id, what)
    if id == nil then D.PreviewStop() end   -- another profile's reminders: a preview of the old one ends
    if id and (what == "display" or what == "place" or what == "name") then
        local v = RM.Get(id)
        if v then
            D.Update(v)
            local r = rt[id]
            if r and r.out and active[id] then
                -- a changed delay or minimum counts from when the wait began, not from now
                local since = r.wantSince
                if r.phase then r.token, r.phase = r.token + 1, nil end
                r.wantSince = since
                Act(v, r)
            end
            Tell(id)
        end
        return
    end
    CT.Refresh()
end)

---------------------------------------------------------------------------
-- For the settings window: what a reminder is doing now, and why
---------------------------------------------------------------------------
-- fn(id or nil) after a reminder's live decision changed (nil: possibly all of them).
function CT.OnChange(fn)
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end

-- The status word key of a reminder, with what only the controller knows.
function CT.Status(id)
    if not R:Enabled("reminders") then return "off" end
    local v = RM.Get(id)
    if not v then return nil end
    if not v.valid then return "invalid" end
    if not v.enabled then return "disabled" end
    if not ST.InWorld() then return "world" end
    local r = rt[id]
    if r and r.phase then return r.phase end
    if r and r.out then return r.out.status end
    local applies = E.Applies(v, ST.Context())
    if applies == NOMATCH then return "notApplicable" end
    return "waiting"
end

-- The live decision of a reminder, condition by condition: the running one's own, or (one that isn't running: a draft,
-- invalid, off or for someone else) a fresh look at the game now, made into a table of its own. Never changes the
-- live observations or decisions. Returns the decision and its status key.
function CT.Inspect(id)
    local v = RM.Get(id)
    if not v then return nil end
    local r = rt[id]
    if active[id] and r and r.out then return r.out, CT.Status(id) end
    local out = E.Run(v, ST.Peek(v), ST.Context())
    return out, CT.Status(id)
end

function CT.Active(id) return active[id] == true end
function CT.Visible(id) local r = rt[id] return r ~= nil and r.visible end

-- For /tui diagnostics and the tests: counts only (no names, items or places).
function CT.Snapshot()
    local n, on, valid, act, visible, pending, holding = 0, 0, 0, 0, 0, 0, 0
    for _, v in ipairs(RM.List()) do
        n = n + 1
        if v.enabled then on = on + 1 end
        if v.valid then valid = valid + 1 end
        if active[v.id] then act = act + 1 end
        local r = rt[v.id]
        if r and r.visible then visible = visible + 1 end
        if r and r.phase == "pending" then pending = pending + 1 end
        if r and r.phase == "holding" then holding = holding + 1 end
    end
    local keys = 0
    for _ in pairs(index) do keys = keys + 1 end
    return { enabled = R:Enabled("reminders"), running = running, reminders = n, turnedOn = on, valid = valid,
        active = act, visible = visible, pending = pending, holding = holding, keys = keys,
        refreshes = stats.refreshes, decisions = stats.decisions, shows = stats.shows, hides = stats.hides }
end

R:OnInit(function() CT.Refresh() end)
