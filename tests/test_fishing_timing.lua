-- Session spans and observed line time have distinct meanings. Lifecycle tests use synthetic client events only.
dofile(TESTS .. "fishing_mock.lua")
local function Check(v, text) assert(v, text) end
local function Fresh(db, epoch)
    local c, W = FishingClient({ db = db, epoch = epoch })
    W.Camera()
    c.TwichUI.RunCommand("fish")
    return c, W, c.TwichUI.Fishing
end

-- A live line advances; the gaps between casts do not count as active fishing.
do
    local c, W, F = Fresh()
    W.StartLine(); W.Advance(12)
    Check(F.Session.FishingTime() == 12 and F.API.Session().line == 12, "live line time advances")
    Check(F.API.Metrics("lifetime").line == 12, "lifetime includes the uncommitted live line exactly once")
    W.StopLine()
    local last = F.Session.Current().last
    W.Advance(35)
    Check(F.Session.FishingTime() == 12 and F.Session.Elapsed() >= 47, "idle remains session time, never active fishing")
    Check(F.Session.Current().last == last, "deferred miss confirmation does not extend last fishing activity")
    Check(F.Journal.Overview().lifetime.line == 12, "Journal active fishing time excludes idle")
    Check(F.CastBar.StatsText():find("Fishing: 12s", 1, true), "HUD labels active fishing time")
end

-- Stopping mid-line freezes both figures; the eventual channel stop cannot add more time or resurrect the session.
do
    local c, W, F = Fresh()
    W.StartLine(); W.Advance(14)
    F.JournalUI.Open("sessions")
    Check(F.JournalUI.Clock(), "Journal timer runs for an open session")
    local start = F.Session.Current().start
    c.TwichUI.RunCommand("fish stop")
    local saved = F.API.Sessions(1)[1]
    Check(saved.seconds == saved.stop - start and saved.line == 14, "explicit stop settles exact duration and live line")
    Check(not F.Session.Current() and not F.JournalUI.Clock(), "stop removes active session and Journal timer")
    Check(not F.CastBar.Shown() and not F.Present.On(), "stop hides immersive pieces")
    local frame = F.CastBar.Frame()
    Check(frame:GetScript("OnUpdate") == nil, "stop removes animation handler")
    -- Loot for this already-cast line may arrive after stopping; retain its original session without restarting.
    F.Journal.Sessions() -- warm the completed-session cache before the late item
    W.Advance(5); W.Interact(); W.Advance(45); W.StopLine(); W.Advance(50)
    Check(not F.Session.Current() and F.API.SessionByID(saved.id).catches == 1, "late catch keeps original session without reactivation")
    Check(F.Journal.Sessions().rows[1].catches == 1, "late catch invalidates the historical Journal row")
    local kept = F.API.SessionByID(saved.id)
    Check(kept.seconds == saved.seconds and kept.stop == saved.stop and kept.line == saved.line, "late events never extend completed timing")
    Check(F.API.Metrics(saved.id).seconds == saved.seconds, "completed economic duration frozen")
    Check(F.Journal.Summary(saved.id).headline.seconds == saved.seconds, "summary retains exact final duration")
    F.JournalUI.Close(); F.JournalUI.Open("sessions"); W.Advance(60)
    Check(not F.JournalUI.Clock() and F.Journal.Session(saved.id).row.seconds == saved.seconds, "reopening completed Journal does not start a timer")
    local c2, W2, F2 = Fresh(FishRoundTrip(c.TwichUIFishingDB), W.epoch + 30)
    F2.Present.Recover(); F2.JournalUI.Open("sessions"); W2.Advance(90)
    Check(not F2.Session.Current() and not F2.JournalUI.Clock(), "reload and recovery do not reactivate completed session")
    Check(F2.API.SessionByID(saved.id).seconds == saved.seconds, "reload keeps final duration")
end

-- Fishing Mode is only presentation. New casts while suppressed cannot reattach a hidden animation/ticker.
do
    local c, W, F = Fresh()
    W.StartLine(); W.Advance(7)
    c.TwichUI.RunCommand("fish mode off")
    local frame, ui = F.CastBar.Frame()
    local text = ui.stats:GetText()
    Check(F.Session.Current() and not F.Present.On() and not frame:IsShown(), "mode exit preserves established recording semantics")
    W.Advance(5)
    Check(frame:GetScript("OnUpdate") == nil and ui.stats:GetText() == text, "hidden cast bar has no live timer or text updates")
    W.StopLine(); W.Advance(2); W.StartLine(); W.Advance(8)
    Check(not F.Present.On() and frame:GetScript("OnUpdate") == nil, "suppressed next cast never restarts hidden animation")
    local id, start = F.Session.Current().id, F.Session.Current().start
    F.Present.Enter("player"); F.Present.Reveal(true); W.Advance(2); F.Present.Reveal(false)
    Check(F.Session.Current().id == id and F.Session.Current().start == start, "reveal does not reset timing")
    c.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", W.channel[3], 7620)
    W.StopLine(); W.Fight()
    local line, last = F.Session.FishingTime(), F.Session.Current().last
    W.Advance(20); W.Peace()
    Check(F.Session.FishingTime() == line and F.Session.Current().last == last, "combat pause does not extend active line or activity timestamp")
end

-- An old channel's delayed interruption/failure cannot update a newly started session's counts or idle anchor.
do
    local c, W, F = Fresh()
    W.StartLine(); W.Advance(5)
    local old = W.channel[3]
    c.TwichUI.RunCommand("fish stop")
    c.TwichUI.RunCommand("fish start")
    local current = F.Session.Current()
    local last = current.last
    W.Advance(15)
    c.FireEvent("UNIT_SPELLCAST_INTERRUPTED", "player", old, 7620)
    c.FireEvent("UNIT_SPELLCAST_FAILED", "player", old, 7620)
    W.StopLine(); W.Advance(2)
    Check(current.interrupted == 0 and current.failed == 0 and current.missed == 0 and current.line == 0,
        "late old-line outcomes never change the next session")
    Check(current.last == last, "late interruption does not extend new session's idle anchor")
    c.TwichUI.RunCommand("fish stop")
    c.FireEvent("UNIT_SPELLCAST_CHANNEL_START", "player", old, 7620)
    Check(not F.Session.Current() and not F.Action.LineOut(), "replayed old channel start cannot create an empty session")
end

-- Idle end is anchored to actual line end, including no-loot casts; delayed timer detection adds no idle minutes.
do
    local c, W, F = Fresh()
    F.Store.Set("session.idleMinutes", 1)
    W.StartLine(); W.Advance(20); W.StopLine()
    local id, last = F.Session.Current().id, F.Session.Current().last
    W.Advance(130)
    local s = F.API.SessionByID(id)
    Check(not F.Session.Current() and s.ended == "idle" and s.stop == last, "idle uses last observed activity, not timer callback")
    Check(s.seconds == 20 and s.line == 20, "idle duration includes the line, no phantom timeout gap")
end

-- Short reload resumes the session span, never the old active-line timer. Stale reload closes at the checkpoint.
do
    local c, W, F = Fresh()
    W.StartLine(); W.Advance(9)
    c.FireEvent("PLAYER_LOGOUT")
    local db, id = FishRoundTrip(c.TwichUIFishingDB), F.Session.Current().id
    local c2, W2, F2 = Fresh(db, W.epoch + 15)
    Check(F2.Session.Current().id == id and F2.Session.FishingTime() == 9, "short reload retains only observed line seconds")
    W2.Advance(12)
    Check(F2.Session.FishingTime() == 9 and not F2.CastBar.Shown(), "no reload line or HUD timer resumes")
    local c3, W3, F3 = Fresh(FishRoundTrip(db), W.epoch + 700)
    local ended = F3.API.SessionByID(id)
    Check(not F3.Session.Current() and ended.ended == "idle" and ended.seconds == 9, "long offline interval ends at saved activity, not login")
    c2.TwichUI.RunCommand("fish off")
    Check(not F2.Session.Current(), "disabling Fishing finalizes its session")
end
-- A future saved-data schema disables recording, not the secure fishing workflow.
do
    local c, W, F = Fresh({ schema = 999 })
    W.bound.F = "CLICK TwichUIFishingButton:LeftButton"
    c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
    W.StartLine()
    Check(F.Store.held and F.Action.LineOut() and W.overrides.F == "INTERACTTARGET",
        "held data still tracks the live channel and supports reeling")
    W.StopLine()
    Check(not F.Action.LineOut() and not F.Session.Current() and c.TwichUIFishingDB.schema == 999,
        "held data remains untouched after the line")
end

print("PASSED test_fishing_timing")
