-- TwichUI: the first-install experience
-- On a new installation TwichUI's layout setup (TwichUI_LayoutWizard, load on demand) is the one setup window: it is
-- offered once the game is ready for it, in place of the old welcome dialog (which now opens only when asked, /tui about).
-- docs/onboarding.md is the whole policy; this file is the core's part of it, and the only part that runs at login.
--
-- The record (TwichUIDB.onboarding, account-wide; Persist.lua makes it and repairs it narrowly):
--   { v = 1, state, offers, why, held }
--   state   "new"        a new installation; the setup has not been opened yet
--           "started"    the setup was opened and not answered (a reload, a disconnect)
--           "deferred"   put off: Do this later, the close box or Escape
--           "installing" an install made from it waits for its reload, its check, or a recovery (partial, mismatch)
--           "done"       installed and checked (or kept by the player after the check)
--           "skipped"    the player chose Skip setup (or EllesmereUI's own setup), or restored what an install did
--           "existing"   an installation from before onboarding: never offered by itself
--   offers  automatic openings so far in the current phase (bounded by O.MAX_OFFERS)
--   why     a short code for the last change (developer-readable; never a name or text)
--   held    TwichUI held EllesmereUI's own first-run picker back for this setup, and EllesmereUI's setup has not run since
-- The install record (TwichUIDB.layouts.install) and the management record are TwichUI_Layouts'; this only reads their
-- state to know when an install made from the setup is waiting or finished, and never changes them. Opening the window
-- is never taken as completion: only a checked (or kept) install is "done".
--
-- When it opens by itself: once per session at most, out of combat and off a flight path, with no game banner, cinematic,
-- hidden interface or TwichUI card in the way, after the check that follows a layout reload has run, and not over
-- EllesmereUI's own first-run or look picker (it waits for them; it never hides them). "new" opens at the first chance
-- of any session; "started" and "deferred" only at a real login (not a reload), up to O.MAX_OFFERS times; "installing"
-- opens on the result after a login or reload, up to O.MAX_OFFERS times. Waiting is bounded (O.MAX_TRIES looks per world
-- entry, again after combat); nothing polls. A completed or skipped installation reads one field at login and nothing else.
--
-- EllesmereUI (EllesmereUI_FirstInstall.lua and EllesmereUI_StyleChoicePopup.lua, 9.6.8): on EllesmereUI's own first
-- session it raises EllesmereUI._firstInstallPending at its ADDON_LOADED and shows its module picker at PLAYER_LOGIN +
-- 0.5 s unless a partner installer registered (EllesmereUI.RegisterExternalInstaller). Here, at PLAYER_LOGIN, only when
-- this record is "new", EllesmereUI's first run is due this session, and the setup's addons can load, TwichUI registers
-- (LayoutsLauncher.RegisterInstaller). In that session EllesmereUI's look picker waits for the module picker by its own
-- rule (it returns while _firstInstallPending is up), so it is not stamped. TwichUI never registers in a session where
-- only the look picker is due: a registration then marks the look chosen for good. Applying a layout answers EllesmereUI's
-- first run (its import stamps it). Skip setup, or a setup that can't load, hands it back (O.HandBack): EllesmereUI's own
-- picker, exported as EllesmereUI.ShowFirstInstallPopup, is shown. A registration can't be taken back within a session.

local R = TwichUI
local O = {}
R.Onboarding = O

O.VERSION = 1
O.MAX_OFFERS = 3            -- automatic openings per phase (put off / under way); after that only when asked
O.MAX_TRIES = 15            -- looks per world entry while something is in the way
local SETTLE = 4            -- seconds after entering the world before the first look (after the layout check, at 3 s)
local RETRY = 2             -- seconds between looks
local MAX_REASONS = 16      -- this session's developer-readable log

local FIRST_RUN = { new = true, started = true, deferred = true }
local OWED = { new = true, started = true, deferred = true, installing = true }

-- This session only; nothing here is saved.
local session = { holding = false, offered = false, answered = false, waiting = false, tries = 0, token = 0,
    login = nil, nativeShown = false, reasons = {} }
local active = {}           -- [event] = handler, while listening

-- This session's reasons, in order (bounded): why it held EllesmereUI's first run or didn't, opened, couldn't, was put off,
-- skipped or handed back. Only "onboarding-waited" and "onboarding-load-failed" are also counted with the lifecycle codes.
local function Note(code)
    local list = session.reasons
    if #list < MAX_REASONS then list[#list + 1] = code end
end
O.Note = Note

---------------------------------------------------------------------------
-- The record (read narrowly; Persist.lua repairs it at load)
---------------------------------------------------------------------------
local function Rec()
    local db = TwichUIDB
    local o = type(db) == "table" and db.onboarding
    if type(o) ~= "table" then return nil, "none" end
    if type(o.v) == "number" and o.v > O.VERSION then return nil, "newer" end   -- a newer TwichUI's: read nothing, write nothing
    if type(o.offers) ~= "number" then o.offers = 0 end
    return o
end

function O.State() local o = Rec() return o and o.state or nil end
-- True while the setup is the first-install experience (offered, not yet answered or installed).
function O.FirstRun() local st = O.State() return st ~= nil and FIRST_RUN[st] == true end
-- True when EllesmereUI's own first-run setup was held back for this one and has not run since.
function O.Held() local o = Rec() return o ~= nil and o.held == true and FIRST_RUN[o.state] == true end
-- True when TwichUI holds EllesmereUI's first run in this session (its picker stays silent until the next reload).
function O.Holding() return session.holding end

local function Set(o, state, why)
    o.state, o.why = state, why
    if state == "done" or state == "installing" then o.held = nil end
end

-- The install record and the management record, read raw (TwichUI_Layouts need not be loaded): the record (any value:
-- an unreadable one still counts as there), its state when readable, and whether a layout is managed.
local function Records()
    local l = type(TwichUIDB) == "table" and TwichUIDB.layouts
    if type(l) ~= "table" then return nil, nil, false end
    local j = l.install
    return j, type(j) == "table" and j.state or nil, type(l.managed) == "table"
end

-- Moves the state on from what the layout records say now. Read the records, write only this one. Returns the state.
function O.Sync()
    local o = Rec()
    if not o then return nil end
    local j, js, managed = Records()
    local st = o.state
    if st == "started" or st == "deferred" then
        if j ~= nil then
            if js == "verified" then Set(o, "done", "verified") else Set(o, "installing", "applied") end
            o.offers = 0
        elseif managed then
            Set(o, "done", "managed")
        end
    elseif st == "installing" then
        if j ~= nil then
            if js == "verified" then Set(o, "done", "verified") end
        elseif managed then
            Set(o, "done", "kept")
        else
            Set(o, "skipped", "restored")   -- the install was restored (or its record forgotten): the player went back
        end
    end
    return o.state
end

---------------------------------------------------------------------------
-- What the setup window tells this (TwichUI_LayoutWizard's Window.lua)
---------------------------------------------------------------------------
-- The window opened, however it was asked for: a new installation's setup is now under way (not finished).
function O.Opened()
    local o = Rec()
    if o and o.state == "new" then Set(o, "started", "opened") end
end

local Cancel, Refresh

-- Do this later, the close box, Escape. Returns true when the setup was put off.
function O.Defer(why)
    local o = Rec()
    if not (o and FIRST_RUN[o.state]) then return false end
    Set(o, "deferred", why or "later")
    session.answered = true
    Note("deferred")
    Cancel()
    Refresh()
    local again = o.offers < O.MAX_OFFERS
        and "TwichUI offers it again the next time you log in (not on a reload)."
        or "TwichUI won't open it by itself again."
    R.Print("layout setup put off. %s Type /tui layout, or use Home > Interface layout in the settings, to open it any time.%s", again,
        o.held and " EllesmereUI's own first-run setup was held back for it; the setup's first page can open that instead." or "")
    return true
end

-- Skip setup (or EllesmereUI's own setup, why = "native"). Never an install. Returns true, held (EllesmereUI's own
-- first run was held back for this and should be handed back) | false.
function O.Skip(why)
    local o = Rec()
    if not (o and FIRST_RUN[o.state]) then return false end
    local held = o.held == true
    Set(o, "skipped", why or "user")
    session.answered = true
    Note("skipped")
    Cancel()
    Refresh()
    return true, held
end

-- The window closed (not set aside for the full-size preview). An install made from it is followed; a first-install
-- setup closed without an answer is put off, as Do this later.
function O.WizardClosed(why)
    local o = Rec()
    if not o then return end
    O.Sync()
    if FIRST_RUN[o.state] and not session.answered then O.Defer(why or "closed") end
    Refresh()
end

-- Shows EllesmereUI's own first-run picker (EllesmereUI_FirstInstall.lua exports it as EllesmereUI.ShowFirstInstallPopup;
-- it seeds its boxes from the addons' current enable state and ends in its own reload). Once a session, never in combat.
-- Returns true | false, code ("combat", "unavailable", "shown", "error").
function O.HandBack()
    if InCombatLockdown() then return false, "combat" end
    local E = rawget(_G, "EllesmereUI")
    local show = type(E) == "table" and E.ShowFirstInstallPopup
    if type(show) ~= "function" then Note("native-unavailable") return false, "unavailable" end
    if session.nativeShown then return false, "shown" end
    local ok, err = pcall(show)
    if not ok then
        R.Fault("EllesmereUI first-run setup", err)
        Note("native-error")
        return false, "error"
    end
    session.nativeShown = true
    local o = Rec()
    if o then o.held = nil end
    Note("native")
    return true
end

-- What HandBack's result means, for a chat line.
function O.HandBackText(ok, code)
    if ok then return "EllesmereUI's own first-run setup is shown instead." end
    if code == "combat" then return "EllesmereUI's own first-run setup can be opened from the layout setup's first page once combat ends." end
    if code == "shown" then return "EllesmereUI's own first-run setup was already shown this session." end
    return "EllesmereUI's own first-run setup isn't available from here; EllesmereUI's options have its choices."
end

---------------------------------------------------------------------------
-- Holding EllesmereUI's first run for the setup (at PLAYER_LOGIN)
---------------------------------------------------------------------------
-- Whether the setup's addons can load (the window's and the engine it needs): exists and turned on for this character.
local function WizardLoadable()
    local C, L = C_AddOns, R.LayoutsLauncher
    if not (C and L) then return false, "no-api" end
    for _, name in ipairs({ L.WIZARD, L.ADDON }) do
        if C.DoesAddOnExist and C.DoesAddOnExist(name) == false then return false, "missing" end
        if C.GetAddOnEnableState then
            local ok, st = pcall(C.GetAddOnEnableState, name, UnitName and UnitName("player") or nil)
            if ok and type(st) == "number" and st <= 0 then return false, "disabled" end
        end
    end
    return true
end
O.WizardLoadable = WizardLoadable

local function Hold()
    if session.holding then return end
    local o = Rec()
    if not (o and o.state == "new") then return end
    local E = rawget(_G, "EllesmereUI")
    if type(E) ~= "table" or rawget(E, "_firstInstallPending") ~= true then return end   -- EllesmereUI's first run isn't due
    local loadable, why = WizardLoadable()
    if not loadable then Note("hold-" .. why) return end   -- its own picker shows: TwichUI's setup couldn't take its place
    local ok, code = R.LayoutsLauncher.RegisterInstaller()
    if not ok then Note("hold-" .. code) return end
    session.holding = true
    o.held = true
    Note("hold")
end

---------------------------------------------------------------------------
-- Opening by itself
---------------------------------------------------------------------------
local function Toasting()
    local toast = EventToastManagerFrame
    return toast and toast.IsCurrentlyToasting and toast:IsCurrentlyToasting() and true or false
end

local function Cinematic()
    for _, f in ipairs({ CinematicFrame, MovieFrame }) do
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

-- A TwichUI card waiting or showing. Read only: the coordinator is never asked to hold anything back for the setup.
local function CardsUp()
    local N = R.Notify
    if not (N and N.Snapshot) then return false end
    local s = N.Snapshot()
    return s.queued > 0 or next(s.active) ~= nil
end

-- A short reason code for what is in the way of opening the setup by itself, or nil when it is clear.
function O.InTheWay()
    if not (R.Life and R.Life.configReady) then return "settings" end
    if not R.Life.InWorld() then return "world" end
    if InCombatLockdown() then return "combat" end
    if UnitOnTaxi and UnitOnTaxi("player") then return "flight" end
    if UIParent and UIParent.IsShown and not UIParent:IsShown() then return "interface-hidden" end
    if Toasting() or Cinematic() then return "banner" end
    if CardsUp() then return "cards" end
    local L = R.LayoutsLauncher
    if L and not L.Continued() then return "layouts" end   -- the check after a layout reload hasn't run yet
    local E = rawget(_G, "EllesmereUI")
    if type(E) == "table" then
        local pending = rawget(E, "_firstInstallPending") == true
        -- EllesmereUI's own first run, not held for this setup: its picker (or another installer) has this session
        if pending and not session.holding then return "ellesmereui-setup" end
        -- EllesmereUI's look picker is due (it shows at login when its first run isn't): wait for its answer
        local db = rawget(_G, "EllesmereUIDB")
        if not pending and type(db) == "table" and db.styleChoicePending == true then return "ellesmereui-style" end
    end
    return nil
end

-- Whether this session should open the setup by itself (now that the first world entry said login or reload).
local function Due()
    local o = Rec()
    if not o or session.offered or session.answered then return false end
    local st = O.Sync()
    if st == "new" then return true end
    if st == "started" or st == "deferred" then return session.login == true and o.offers < O.MAX_OFFERS end
    if st == "installing" then return o.offers < O.MAX_OFFERS end
    return false
end
O.Due = Due

-- Opens the setup now, as the first-install offer. Returns true | false, reason.
function O.OpenNow()
    local L = R.LayoutsLauncher
    local o = Rec()
    if not (o and L) then return false, "none" end
    session.offered = true
    Refresh()
    -- already up (the result after the setup's own reload opens it): that is this session's offer
    if L.WizardLoaded() and R.LayoutWizard.Window.IsShown() then Note("open-already") return true end
    o.offers = o.offers + 1
    local ok, why = L.OpenWizard()   -- says why in chat when it can't
    if ok then Note("open") return true end
    Note("load-failed")
    if R.Life then R.Life.Note("onboarding-load-failed") end
    if session.holding then
        -- EllesmereUI's own picker was held back for a setup that can't open: give the first run back to it
        R.Print("%s", O.HandBackText(O.HandBack()))
    end
    return false, why
end

local Schedule

local function Attempt(mine)
    if mine ~= session.token then return end
    session.waiting = false
    if not Due() then Refresh() return end
    local why = O.InTheWay()
    if why then
        session.lastWait = why
        if R.Life then R.Life.Note("onboarding-waited") end
        session.tries = session.tries + 1
        if session.tries < O.MAX_TRIES then Schedule(RETRY) end   -- then it waits for the next world entry or end of combat
        return
    end
    O.OpenNow()
end

function Schedule(delay)
    if session.waiting or not Due() then return end
    session.waiting = true
    local mine = session.token
    C_Timer.After(delay, function() Attempt(mine) end)
end

function Cancel()
    session.token = session.token + 1
    session.waiting = false
end

local function OnEnteringWorld(isLogin)
    -- the session's first world entry says whether this is a login or a reload; later ones are loading screens
    if session.login == nil then session.login = isLogin == true end
    Cancel()
    session.tries = 0
    Schedule(SETTLE)
end

local function OnLeavingWorld() Cancel() end

local function OnCombatEnded()
    if session.tries >= O.MAX_TRIES then session.tries = 0 end   -- the fight is over: a fresh set of looks
    Schedule(1)
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Listens only while an automatic offer could still happen this session. Safe to call any time.
function Refresh()
    local o = Rec()
    local owed = o ~= nil and OWED[o.state] == true and not session.offered and not session.answered
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, owed)
    Want("PLAYER_LEAVING_WORLD", OnLeavingWorld, owed)
    Want("PLAYER_REGEN_ENABLED", OnCombatEnded, owed)
    if not owed then Cancel() end
end
O.Refresh = Refresh

---------------------------------------------------------------------------
-- /tui layout firstrun [reset], and the troubleshooting report
---------------------------------------------------------------------------
local LABEL = { new = "not started", started = "started, not finished", deferred = "put off", installing = "an install waits for its reload or check",
    done = "done", skipped = "skipped", existing = "an installation from before first-run setup (not offered by itself)" }

function O.Command(rest)
    local word = ((rest or ""):match("^(%S*)") or ""):lower()
    if word == "reset" then
        local raw = type(TwichUIDB) == "table" and TwichUIDB.onboarding
        if type(raw) == "table" and type(raw.v) == "number" and raw.v > O.VERSION then
            R.Print("first-run setup: its record was made by a newer TwichUI, so it is left as it is.")
            return
        end
        if InCombatLockdown() then R.Print("first-run setup: not during combat. Nothing was changed.") return end
        TwichUIDB.onboarding = { v = O.VERSION, state = "new", offers = 0, why = "reset" }
        R.Print("first-run setup reset: it opens as for a new installation at your next login or reload. Nothing else was changed: no install record, profile or EllesmereUI setting.")
        return
    end
    local o, why = Rec()
    if not o then
        R.Print("first-run setup: %s.", why == "newer" and "its record was made by a newer TwichUI" or "no record")
        return
    end
    O.Sync()
    R.Print("first-run setup: %s (%s); automatic offers used %d of %d%s. /tui layout firstrun reset starts it again (for testing).",
        LABEL[o.state] or tostring(o.state), tostring(o.why or "-"), o.offers, O.MAX_OFFERS,
        o.held and "; EllesmereUI's own first-run setup is held back for it" or "")
end

-- Read only: states, counts and fixed codes (no names, places or text).
function O.Snapshot()
    local o, why = Rec()
    local reasons = {}
    for i, code in ipairs(session.reasons) do reasons[i] = code end
    return { state = o and o.state or why, offers = o and o.offers or 0, why = o and o.why or nil, held = o ~= nil and o.held == true,
        holding = session.holding, offered = session.offered, answered = session.answered, listening = next(active) ~= nil,
        waiting = session.waiting, tries = session.tries, lastWait = session.lastWait, reasons = reasons }
end

R:OnInit(function()
    O.Sync()
    Refresh()
end)
R:On("PLAYER_LOGIN", Hold)
