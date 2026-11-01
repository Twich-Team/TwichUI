-- TwichUI: Guild Locations, the player's choice and the saved record (docs/guild-locations.md)
-- Guild members using TwichUI share their own current map position over the guild's hidden addon channel (guildloc/Comm.lua).
-- This file is the one authority on whether that happens, and keeps the little that is saved. It has no frames, no
-- events and no game calls but the clock.
--
-- Three states, all through GL.State / GL.SetState / GL.Toggle:
--   sharing    (the default) sends your position and shows the positions that arrive
--   invisible  sends nothing and still shows others. Hidden from this feature only.
--   off        nothing sent, nothing received, nothing kept
-- One account-wide record, TwichUIDB.guildLoc = { state, interval, lastEpoch, wp }. It is outside profiles, configuration
-- sharing and backups (setup/Restore.lua OWN_LEFT_OUT, setup/TwichConfig.lua TC.LOCAL): switching profile, importing
-- someone's settings or restoring a backup never changes it.
--   * Genuinely missing (no record, or a record with no `state`) means the default, sharing.
--   * A record that is present but unusable (not a table, or a `state` that is not one of the three) reads as invisible and
--     is not rewritten. Only the player choosing a state replaces it.
--   * While TwichUIDB is held (a newer schema set aside, Persist.lua) the feature is inactive for the session: reads as off,
--     nothing is written.
--   * An interval that is not one of the offered ones reads as the default; that is not a privacy choice.
--   * `lastEpoch` is the highest epoch this account has put on the wire (an epoch only orders one sender's sessions and
--     withdrawals; freshness is always the receiver's own clock). A present but unusable value stops all sending until the
--     player chooses a state again; it is never reused, wrapped or guessed.
--   * `wp` (true) is a withdrawal still owed to the guild after a reload (see Comm.lua).
-- Being outside a guild never stops a choice from being made or saved: the guild decides whether anything can be sent.

local R = TwichUI
local GL = {}
R.GuildLoc = GL

GL.STATES = { sharing = true, invisible = true, off = true }
GL.DEFAULT_STATE = "sharing"
GL.INTERVALS = { 10, 15, 30, 60 }
GL.DEFAULT_INTERVAL = 15
GL.EPOCH_MIN = 1600000000       -- an epoch below this is a clock that is not telling the time
GL.EPOCH_MAX = 4294967295       -- the wire carries at most ten digits

local INTERVAL_SET = {}
for _, n in ipairs(GL.INTERVALS) do INTERVAL_SET[n] = true end

local function Held() return R.Persist ~= nil and R.Persist.IsHeld("TwichUIDB") end

local function Whole(n, low, high)
    return type(n) == "number" and n == n and n % 1 == 0 and n >= low and n <= high
end

---------------------------------------------------------------------------
-- The record
---------------------------------------------------------------------------
-- The saved record as it is: a table, nil (missing) or something unusable. Nil while saved data is unavailable or held.
local function Rec()
    if Held() then return nil, "held" end
    if type(TwichUIDB) ~= "table" then return nil, "not-ready" end
    return TwichUIDB.guildLoc, nil
end

-- The state in force and, when it is not simply what was saved, why: "held" or "not-ready" (reads as off),
-- "bad-record" or "bad-state" (reads as invisible).
function GL.State()
    local rec, why = Rec()
    if why then return "off", why end
    if rec == nil then return GL.DEFAULT_STATE end
    if type(rec) ~= "table" then return "invisible", "bad-record" end
    local s = rec.state
    if s == nil then return GL.DEFAULT_STATE end
    if type(s) == "string" and GL.STATES[s] then return s end
    return "invisible", "bad-state"
end

function GL.Interval()
    local rec = Rec()
    local n = type(rec) == "table" and rec.interval or nil
    if Whole(n, 1, 3600) and INTERVAL_SET[n] then return n end
    return GL.DEFAULT_INTERVAL
end

-- Whether the saved record can be written to without replacing something the player did not choose.
local function Writable(create)
    local rec, why = Rec()
    if why then return nil, why end
    if rec == nil then
        if not create then return nil end
        rec = {}
        TwichUIDB.guildLoc = rec
    end
    if type(rec) ~= "table" then return nil, "bad-record" end
    return rec
end

---------------------------------------------------------------------------
-- Listeners: fn(kind, new, old), kind "state" or "interval"
---------------------------------------------------------------------------
local listeners = {}
function GL.OnChange(fn)
    for _, f in ipairs(listeners) do if f == fn then return end end
    listeners[#listeners + 1] = fn
end
local function Tell(kind, new, old)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, kind, new, old)
        if not ok and R.Fault then R.Fault("guild locations", err) end
    end
end

---------------------------------------------------------------------------
-- Changing it
---------------------------------------------------------------------------
-- Saves the player's choice, then tells the listeners. Returns true, or false and a reason. The new state is saved before
-- anything is told, so nothing that runs afterwards can act on the old one.
function GL.SetState(new)
    if type(new) ~= "string" or not GL.STATES[new] then return false, "bad-state" end
    local _, why = Rec()
    if why then return false, why end
    local old = GL.State()
    local rec = TwichUIDB.guildLoc
    if type(rec) ~= "table" then rec = {}; TwichUIDB.guildLoc = rec end   -- the player's choice replaces an unusable record
    rec.state = new
    if old ~= new then Tell("state", new, old) end
    return true
end

-- Sharing and invisible swap. From off nothing changes: a quick switch never starts sending from off.
function GL.Toggle()
    local s = GL.State()
    if s == "sharing" then return GL.SetState("invisible") end
    if s == "invisible" then return GL.SetState("sharing") end
    return false, "off"
end

function GL.SetInterval(n)
    if not (Whole(n, 1, 3600) and INTERVAL_SET[n]) then return false, "bad-interval" end
    local rec, why = Writable(true)
    if not rec then return false, why end
    local old = GL.Interval()
    rec.interval = n
    if old ~= n then Tell("interval", n, old) end
    return true
end

---------------------------------------------------------------------------
-- Epochs and the owed withdrawal
---------------------------------------------------------------------------
-- The next epoch: one more than any sent before, never less than the clock. It is saved before it is used, so a reload
-- cannot hand it out twice. Returns nil and a reason when no valid one exists ("held", "not-ready", "bad-record",
-- "bad-epoch" for a saved value that is unusable, "epoch-range" for a clock before EPOCH_MIN or a value past EPOCH_MAX):
-- the caller sends nothing.
function GL.NextEpoch()
    local rec, why = Writable(true)
    if not rec then return nil, why end
    local last = rec.lastEpoch
    if last == nil then last = 0 end
    if not Whole(last, 0, GL.EPOCH_MAX) then return nil, "bad-epoch" end
    local now = type(time) == "function" and time() or nil
    if not Whole(now, 0, GL.EPOCH_MAX) then now = 0 end
    local e = math.max(now, last + 1)
    if e < GL.EPOCH_MIN or e > GL.EPOCH_MAX then return nil, "epoch-range" end
    rec.lastEpoch = e
    return e
end

function GL.Pending()
    local rec = Rec()
    return type(rec) == "table" and rec.wp == true
end

-- Returns whether the flag now reads as asked.
function GL.SetPending(on)
    if on then
        local rec = Writable(true)
        if not rec then return false end
        rec.wp = true
        return true
    end
    local rec = Writable(false)
    if rec and rec.wp ~= nil then rec.wp = nil end
    return not GL.Pending()
end

-- Read only, for tests and the troubleshooting report: what is saved, with nothing private in it.
function GL.Saved()
    local rec, why = Rec()
    return { state = (GL.State()), interval = GL.Interval(), pending = GL.Pending(), held = why == "held",
        record = rec == nil and "missing" or type(rec) == "table" and "table" or "unusable" }
end

---------------------------------------------------------------------------
-- One timer per purpose
---------------------------------------------------------------------------
-- C_Timer.After cannot be cancelled, so a timer is a `due` time plus the engine timers that will wake it. A purpose owns at
-- most MAX_ENGINE of them: Set(delay) re-arms by moving `due` and adds an engine timer only when none would wake it on
-- time; at the limit it waits for the earlier one (a little late, never lost); Cancel() clears `due` and the engine timers
-- that are left do nothing when they fire. fn runs with `due` already cleared, so it may Set again.
local MAX_ENGINE = 2
local EPS = 0.05
function GL.NewTimer(fn)
    local T = { due = nil, fires = {} }
    local function Engine(delay)
        local at = GetTime() + delay
        T.fires[#T.fires + 1] = at
        C_Timer.After(delay, function()
            for i, f in ipairs(T.fires) do if f == at then table.remove(T.fires, i) break end end
            T.Run()
        end)
    end
    local function Cover()
        local due = T.due
        if not due then return end
        for _, f in ipairs(T.fires) do if f <= due + EPS then return end end
        if #T.fires >= MAX_ENGINE then return end
        Engine(math.max(0, due - GetTime()))
    end
    function T.Run()
        local due = T.due
        if not due then return end
        if GetTime() + EPS < due then Cover() return end
        T.due = nil
        local ok, err = pcall(fn)
        if not ok and R.Fault then R.Fault("guild locations", err) end
    end
    function T.Set(delay)
        T.due = GetTime() + delay
        Cover()
    end
    function T.Cancel() T.due = nil end
    function T.Armed() return T.due ~= nil end
    function T.Engines() return #T.fires end
    return T
end
