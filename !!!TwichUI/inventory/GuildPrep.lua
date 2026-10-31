-- TwichUI: Magic Inventory, getting the guild bank ready
-- While the guild bank is open and the player has a saved arrangement for this guild, this file reads the tabs the review needs
-- (GuildBank.lua keeps what it reads) and keeps a small summary of what Deposit and Organize bank would do, for the panel at the
-- bank window (GuildPanel.lua). It moves nothing: the only calls it makes are GB.Show(tab) (a tab shown the way the bank's own tab
-- button shows it, which makes the game send that tab's items) and, to finish, GB.Show(the tab the player had).
--
-- What it is careful about (a tab's items are trusted only once the game has sent them for the shown tab: GuildBank.lua):
--   * one tab at a time, each asked for only after the one before answered (or timed out); at most P.TRIES asks per tab per
--     cycle, a bounded wait for each, and a limit on automatic cycles per bank visit. A tab that does not answer is reported as
--     not read, never as empty;
--   * the player's own tab navigation wins: the moment the shown tab is not the one this file asked for, the cycle ends and
--     nothing is asked again until the player has left the bank alone for P.QUIET seconds. It also never asks while the cursor
--     holds anything, during combat, while a run is under way, or while the bank shows its log or tab text instead of items;
--   * when it is done it shows the tab the player had when it started, unless the player moved on;
--   * events only ask for a rebuild: any number of them is one (a short timer), and the summary is rebuilt only when idle.
-- Nothing is saved, and nothing here runs while the bank is closed or Magic Inventory is off.

local R = TwichUI
local MI = R.MagicInventory
local GB = MI.GuildBank
local Plain = MI.Plain

local P = {}
MI.GuildPrep = P

P.READ_WAIT = 3        -- seconds a tab has to send its items
P.TRIES = 2            -- asks for one tab in one cycle (the second only after the first timed out)
P.OPEN_DELAY = 0.6     -- after the bank opens: the game's own first answer comes first
P.GAP = 1.5            -- seconds between the end of one cycle and the start of the next
P.MAX_AUTO = 6         -- cycles a visit may start by itself (the player's own actions are not counted)
P.QUIET = 4            -- seconds after the player changes tab before this file asks for another
P.REPLAN = 0.4         -- seconds an event burst is coalesced into one rebuild
P.RECHECK = 30         -- while idle with the panel up: look again whether a tab has become too old to use

local st = { state = "idle", reason = nil, problems = {}, auto = 0, cycles = 0, reads = 0 }
local gaveUp = {}      -- [tab] = true: it did not answer in this visit; only the player's own request asks again
local cycle            -- the cycle in progress: { token, origin, queue, i, tries, waiting, expect, returning, manual }
local token = 0
local queued = false   -- a cycle is wanted
local queuedManual = false
local replanQueued, replanWanted = false, false
local navUntil = 0     -- the player changed tab: leave the bank alone until then
local lastEnd = -100
local summary          -- { deposit = {...}, organize = {...}, arrangement = bool, at }
local listeners = {}
local recheckToken = 0

local function Now() return GetTime and GetTime() or 0 end
local function Num(v) v = Plain(v); if type(v) == "number" and v == v then return v end end
local function InCombat() return InCombatLockdown and InCombatLockdown() end

function P.OnUpdate(fn) listeners[#listeners + 1] = fn end
local function Notify(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("magic inventory guild prep", err) end
    end
end

local function GuildNow()
    if not (IsInGuild and IsInGuild()) then return nil end
    local name = Plain(GetGuildInfo and (GetGuildInfo("player")))
    return type(name) == "string" and name ~= "" and name or nil
end

local function Open()
    if not (MI.Enabled() and GB.IsOpen()) then return false end
    local f = _G.GuildBankFrame
    if type(f) == "table" and f.IsShown and not f:IsShown() then return false end
    return true
end

local function GR() return MI.GuildRun end
local function RunBusy() local g = GR(); return g ~= nil and g.Busy() end

-- Does this character have a saved arrangement for the guild whose bank is open? (An enabled arrangement rule whose tab is
-- this guild's.) Without one there is nothing to prepare, and the panel offers to set one up.
function P.HasArrangement()
    local guild = GuildNow()
    if not guild then return false end
    for _, rule in ipairs(MI.Rules()) do
        if rule.design and rule.enabled ~= false and rule.dest then
            local where = MI.Resolve(rule.dest)
            if where and where.kind == "guild" and where.guild == guild then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- What is wanted: every tab the rank can see whose items are missing or too old
---------------------------------------------------------------------------
local function Wanted(manual)
    local snap = GB.Snapshot()
    local list = {}
    for i = 1, snap.numTabs or 0 do
        local t = snap.tabs[i]
        if t and t.viewable == true and not GB.IsFresh(i) and (manual or not gaveUp[i]) then list[#list + 1] = i end
    end
    return list, snap
end

-- how many tabs can be read at all, and how many are current
local function Counts()
    local snap = GB.Snapshot()
    local total, fresh = 0, 0
    for i = 1, snap.numTabs or 0 do
        local t = snap.tabs[i]
        if t and t.viewable == true then
            total = total + 1
            if GB.IsFresh(i) then fresh = fresh + 1 end
        end
    end
    return total, fresh
end

---------------------------------------------------------------------------
-- The summary of what the actions would do (rebuilt when idle)
---------------------------------------------------------------------------
local function Summarize(mode)
    local rv = GR().Review(mode)
    if rv.ok then return { moves = rv.moves, ok = true, complete = rv.complete, blocked = rv.planBlocked + #rv.dropped, unknown = rv.planUnknown } end
    local code = rv.refuse and rv.refuse.code
    return { moves = 0, ok = false, code = code, text = rv.refuse and rv.refuse.text, nothing = code == "nothing",
        blocked = rv.planBlocked + #rv.dropped, unknown = rv.planUnknown }
end

local function Replan()
    replanQueued = false
    if not Open() or not GR() then return end
    if cycle or RunBusy() then replanWanted = true; return end
    replanWanted = false
    local pt = R.Perf and R.Perf.on and R.Perf.Start("inventory.guildPrep")
    local has = P.HasArrangement()
    local sum = { arrangement = has, at = Now(), seq = GB.Seq() }
    if has then
        sum.deposit, sum.organize = Summarize("deposit"), Summarize("reorganize")
    end
    summary = sum
    if pt then R.Perf.Stop(pt) end
    Notify("summary")
end

-- Any number of reasons to rebuild are one rebuild.
function P.QueueReplan()
    if replanQueued or not Open() then return end
    replanQueued = true
    C_Timer.After(P.REPLAN, function()
        local ok, err = pcall(Replan)
        if not ok then replanQueued = false; R.Fault("magic inventory guild prep", err) end
    end)
end

function P.Summary() return summary end

---------------------------------------------------------------------------
-- The status the panel shows
---------------------------------------------------------------------------
-- { state = "idle" | "reading" | "ready" | "blocked", reason, tab, done, total, problems = { [tab] = code } }
function P.Status()
    local total, fresh = Counts()
    return { state = st.state, reason = st.reason, tab = cycle and cycle.waiting and cycle.waiting.tab or nil,
        done = fresh, total = total, problems = st.problems, cycles = st.cycles, auto = st.auto,
        reading = cycle ~= nil, arrangement = P.HasArrangement() }
end
function P.Reading() return cycle ~= nil end
function P.Cycles() return st.cycles end
function P.Reads() return st.reads end

---------------------------------------------------------------------------
-- The cycle
---------------------------------------------------------------------------
local Advance, Settled

local function Later(c, delay)
    C_Timer.After(delay, function()
        if cycle == c then Advance(c) end
    end)
end

local function Finish(c, state, reason)
    if cycle ~= c then return end
    cycle = nil
    GB.QueryCancel()
    st.state, st.reason = state, reason
    lastEnd = Now()
    if reason == "navigated" then navUntil = Now() + P.QUIET end
    Notify("status")
    P.QueueReplan()
    Settled()
end

-- Why a cycle cannot go on (or nil). These are all "the player is doing something" or "not now" reasons, never failures.
local function Hold(c)
    if not Open() then return "closed" end
    if RunBusy() then return "run" end
    if GuildNow() == nil then return "guild" end
    -- only a cycle that has shown a tab (or is about to) must not fight the player's cursor, combat, other pages and tab clicks
    if c.flipped then
        if InCombat() then return "combat" end
        local cur = Plain(GetCursorInfo and (GetCursorInfo()))
        if cur ~= nil or (CursorHasItem and CursorHasItem()) then return "cursor" end
        local mode = GB.Mode()
        if mode ~= nil and mode ~= "bank" then return "mode" end
        local shown = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
        if c.expect and shown ~= c.expect then return "navigated" end
    end
    return nil
end

-- May a tab be shown now? (the last resort: nothing is shown over the player's cursor, in combat, from another page of the bank)
local function CanShowNow()
    if InCombat() then return false, "combat" end
    local cur = Plain(GetCursorInfo and (GetCursorInfo()))
    if cur ~= nil or (CursorHasItem and CursorHasItem()) then return false, "cursor" end
    local mode = GB.Mode()
    if mode ~= nil and mode ~= "bank" then return false, "mode" end
    return GB.CanNavigate()
end

-- Asks for one tab. The shown tab is asked again where it is; any other is asked for without showing it; only after those asks went
-- unanswered, and only for a cycle the player started, is it shown (and the player's tab restored at the end).
local function Ask(c, tab)
    local shown = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    local tries = c.tries[tab] or 0
    local via
    if tab == shown then via = "show"
    elseif tries < P.TRIES and GB.CanQuery() then via = "query"
    elseif c.manual then via = "show" end
    if not via then return false, "no-answer" end
    local ok, why
    if via == "query" then
        ok, why = GB.Query(tab)
    else
        if tab ~= shown then
            local can, e = CanShowNow()
            if not can then return false, e or "mode" end
            c.flipped = true
        end
        ok, why = GB.Show(tab)
        if ok and tab ~= shown then c.expect = tab end
    end
    if not ok then return false, why end
    c.waiting = { tab = tab, deadline = Now() + P.READ_WAIT, via = via }
    c.tries[tab] = tries + 1
    st.reads = st.reads + 1
    Later(c, P.READ_WAIT + 0.05)
    if via == "query" then Later(c, GB.QUERY_DWELL + 0.55) end
    Notify("status")
    return true
end

Advance = function(c)
    if cycle ~= c then return end
    if c.inAdvance then c.again = true; return end
    c.inAdvance = true
    repeat
        c.again = false
        c.done = false
        c.step(c)
    until not c.again or cycle ~= c
    c.inAdvance = false
end

local function Step(c)
    local why = Hold(c)
    if why then return Finish(c, "blocked", why) end
    if c.waiting then
        local w = c.waiting
        local done = w.via == "query" and GB.QueryDone(w.tab) or (w.via ~= "query" and GB.IsLive(w.tab))
        if done then
            c.waiting = nil
            Notify("status")
        elseif Now() >= w.deadline then
            c.waiting = nil
            if w.via == "query" and GB.QueryPending() == w.tab then GB.QueryDone(w.tab) end
            -- the asks a tab gets: P.TRIES without showing it, and one more by showing it when the player started this cycle
            local maxAsks = P.TRIES + ((c.manual and w.tab ~= Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())) and 1 or 0)
            if c.tries[w.tab] < maxAsks then
                local ok, e = Ask(c, w.tab)
                if not ok then st.problems[w.tab] = e or "error"; gaveUp[w.tab] = true; c.i = c.i + 1 end
                return
            end
            GB.QueryCancel()
            st.problems[w.tab] = "no-answer"
            gaveUp[w.tab] = true
            c.i = c.i + 1
            Notify("status")
        else
            return
        end
    end
    -- the next tab still to read
    while c.i <= #c.queue do
        local tab = c.queue[c.i]
        if GB.IsFresh(tab) then
            st.problems[tab] = nil
            c.i = c.i + 1
        else
            local ok, e = Ask(c, tab)
            if ok then return end
            st.problems[tab] = e or "error"
            c.i = c.i + 1
        end
    end
    -- everything asked for: give the player their tab back
    local shown = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    if c.flipped and c.origin and shown ~= c.origin and not c.returned then
        c.returned = true
        -- the player's own tab again (shown, never merely asked for)
        if GB.Show(c.origin) then
            c.expect = c.origin
            c.waiting = { tab = c.origin, deadline = Now() + P.READ_WAIT, via = "show" }
            c.tries[c.origin] = (c.tries[c.origin] or 0) + 1
            Later(c, P.READ_WAIT + 0.05)
            return
        end
    end
    local missing = false
    for _ in pairs(st.problems) do missing = true end
    Finish(c, missing and "partial" or "ready", nil)
end

local function Begin(manual)
    queued = false
    queuedManual = false
    if cycle or not Open() then return end
    local why = RunBusy() and "run"
    if not why and not manual and (st.auto >= P.MAX_AUTO) then why = "limit" end
    if why then
        st.state, st.reason = "blocked", why
        Notify("status")
        Settled()
        return
    end
    if Now() < navUntil then
        C_Timer.After(navUntil - Now() + 0.05, function() P.Request("quiet", manual) end)
        return
    end
    if Now() - lastEnd < P.GAP then
        C_Timer.After(P.GAP - (Now() - lastEnd) + 0.05, function() P.Request("gap", manual) end)
        return
    end
    if manual then gaveUp = {} end
    local list = Wanted(manual)
    if #list == 0 then
        if st.state ~= "ready" or st.reason then st.state, st.reason = "ready", nil; Notify("status") end
        P.QueueReplan()
        Settled()
        return
    end
    token = token + 1
    local origin = Num(GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    local c = { token = token, origin = origin, queue = list, i = 1, tries = {}, expect = origin, manual = manual, step = Step }
    -- the shown tab first: it is the game's own query, so ask nothing more of the tab in view than the game already did
    table.sort(list, function(a, b)
        if (a == origin) ~= (b == origin) then return a == origin end
        return a < b
    end)
    c.queue = list
    st.problems = {}
    local hold = Hold(c)
    if hold then
        st.state, st.reason = "blocked", hold
        Notify("status")
        Settled()
        return
    end
    cycle = c
    st.cycles = st.cycles + 1
    if not manual then st.auto = st.auto + 1 end
    st.state, st.reason = "reading", nil
    Notify("status")
    Advance(c)
end

-- Ask for a cycle. Any number of asks is one cycle, a little later (the game's own first answer comes first). manual: the
-- player asked (Deposit or Organize pressed, or Read again), so the per-visit limit does not apply.
function P.Request(why, manual)
    if not Open() then return end
    if cycle then return end
    queuedManual = queuedManual or manual == true
    if queued then return end
    queued = true
    C_Timer.After(why == "open" and P.OPEN_DELAY or 0.1, function()
        local ok, err = pcall(Begin, queuedManual)
        if not ok then queued = false; R.Fault("magic inventory guild prep", err) end
    end)
end

-- The player pressed an action or Read again: make every tab current before a review is made from them. Calls done(ok) when
-- that is so (immediately when it already is).
local waitingFor = {}
function P.EnsureFresh(done)
    if not Open() then done(false, "closed") return end
    local list = Wanted(true)
    if #list == 0 then done(true) return end
    waitingFor[#waitingFor + 1] = done
    navUntil = 0
    P.Request("manual", true)
end

Settled = function()
    if cycle or #waitingFor == 0 then return end
    local list = Wanted(false)
    local cbs = waitingFor
    waitingFor = {}
    for _, cb in ipairs(cbs) do
        local ok, err = pcall(cb, #list == 0 or st.state == "partial" or st.state == "ready", st.state, st.reason)
        if not ok then R.Fault("magic inventory guild prep", err) end
    end
end

---------------------------------------------------------------------------
-- Listening: only while Magic Inventory is on; everything is dropped when the bank closes
---------------------------------------------------------------------------
local function Recheck()
    recheckToken = recheckToken + 1
    local mine = recheckToken
    C_Timer.After(P.RECHECK, function()
        if mine ~= recheckToken or not Open() then return end
        if not cycle and not RunBusy() and P.HasArrangement() then
            local list = Wanted()
            if #list > 0 then P.Request("age", false) end
        end
        Recheck()
    end)
end

local function Closed()
    token = token + 1
    cycle, queued, queuedManual, replanQueued, replanWanted = nil, false, false, false, false
    recheckToken = recheckToken + 1
    st = { state = "idle", reason = nil, problems = {}, auto = 0, cycles = st.cycles, reads = st.reads }
    gaveUp = {}
    summary = nil
    local cbs = waitingFor
    waitingFor = {}
    for _, cb in ipairs(cbs) do pcall(cb, false, "closed") end
    Notify("close")
end

GB.Watch(function(what)
    if not MI.Enabled() then return end
    if what == "close" then return Closed() end
    if what == "open" then
        st.auto = 0
        st.problems = {}
        gaveUp = {}
        if P.HasArrangement() then P.Request("open", false) end
        Recheck()
        P.QueueReplan()
        Notify("open")
        return
    end
    if not GB.IsOpen() then return end
    if what == "tabs" then
        if P.HasArrangement() and not cycle then P.Request("tabs", false) end
        P.QueueReplan()
    elseif what == "items" then
        -- the shown tab's items changed (or a tab we asked for arrived): the cycle looks, the summary follows
        if cycle then Advance(cycle) end
        if not cycle then
            Settled()
            if st.state == "blocked" and (st.reason == "mode" or st.reason == "navigated") and P.HasArrangement() then P.Request("items", false) end
        end
        P.QueueReplan()
    end
end)

-- a change of rules, bags, cursor, combat or a finished run can only matter to the summary or end a hold
local function Poke()
    if not Open() then return end
    P.QueueReplan()
end
MI.OnChange(function()
    if not Open() then return end
    if P.HasArrangement() and not cycle then P.Request("rules", false) end
    Poke()
end)

local active = {}
local lastItemPoke = -100
local EVENTS = {
    BAG_UPDATE_DELAYED = function() Poke() end,
    -- item names, stack limits and bindings the game was asked for have arrived: a summary that could not be told is built again
    -- (only then, and not more than every 2 seconds: this event is frequent)
    GET_ITEM_INFO_RECEIVED = function()
        if not (Open() and summary) or Now() - lastItemPoke < 2 then return end
        local d, o = summary.deposit, summary.organize
        if (d and (d.unknown or 0) > 0) or (o and (o.unknown or 0) > 0) then lastItemPoke = Now(); P.QueueReplan() end
    end,
    PLAYER_REGEN_ENABLED = function()
        if st.state == "blocked" and st.reason == "combat" and Open() and P.HasArrangement() then P.Request("combat", false) end
    end,
    CURSOR_CHANGED = function()
        if st.state == "blocked" and st.reason == "cursor" and Open() and P.HasArrangement() then P.Request("cursor", false) end
    end,
}
function P.Sync()
    local on = MI.Enabled()
    for event, fn in pairs(EVENTS) do
        if on and not active[event] then active[event] = fn; R:On(event, fn)
        elseif not on and active[event] then R:Off(event, fn); active[event] = nil end
    end
    if not on then Closed() end
end

-- the run ended (or a review changed what is true): the summary is rebuilt, and tabs that went stale are read again
local gr = GR()
if gr then
    gr.OnUpdate(function(what)
        if what == "done" or what == "clear" then
            if Open() then
                if P.HasArrangement() then P.Request("run", true) end
                P.QueueReplan()
                Settled()
            end
        end
    end)
end

function P.ListenerCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    return n
end

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.guildPrepState", { label = "Magic Inventory guild bank preparation (summary, problems and waiting callbacks held)", unit = "count", kind = "cache",
        read = function() local n = #waitingFor + (summary and 2 or 0); for _ in pairs(st.problems) do n = n + 1 end return n end })
end
