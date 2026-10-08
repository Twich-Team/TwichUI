-- TwichUI: troubleshooting report, start-up and lifecycle
-- Where start-up has got to (saved data, configuration, start-up hooks, login, the world) and how often
-- work was held back, set aside or cancelled since the game started, each under a fixed reason code.
-- Codes and counts only: no names, places, items or text. Reads only.
--   waiting-for-world         a look at the bags (or similar) waited for the loading screen to end
--   deferred-combat           a secure-button update waited for combat to end
--   cancelled-stale-baseline  an older zone-baseline retry was set aside
--   cancelled-stale-transfer  a late result for a transfer that had already been settled was ignored
--   transfer-settled          a transfer in progress was ended because sharing/receiving was turned off
--   friend-bnet-baseline      Battle.net reconnected: logins right after it are treated as the baseline
--   friend-bnet-disconnected  Battle.net disconnected: waiting friend logins were let go
--   init-failed               a start-up hook raised an error (the error itself is under Recent errors)
--   welcome-deferred          the welcome dialog for a new installation waited (combat, a flight, a banner, a card, a loading screen)

local R = TwichUI
local D = R.Diag

local function Lifecycle()
    local L = R.Life
    if not (L and L.Snapshot) then return { status = "unavailable", reason = "not-loaded" } end
    local s = L.Snapshot()
    local lines = {}
    local function Line(fmt, ...) lines[#lines + 1] = fmt:format(...) end
    Line("saved variables: %s; configuration ready: %s", s.savedVariables, D.Flag(s.configReady))
    Line("start-up hooks run: %d, failed: %d", s.hooksRun, s.hookFailures)
    Line("logged in: %s; in the world now: %s; times the world was entered: %d", D.Flag(s.loggedIn), D.Flag(s.inWorld), s.worldEntries)
    local list = {}
    for code, n in pairs(s.notes) do list[#list + 1] = ("%s x%d"):format(code, n) end
    table.sort(list)
    Line("held back, set aside or cancelled since the game started: %s", #list > 0 and table.concat(list, ", ") or "none")
    if s.notesDropped > 0 then Line("(%d further occurrences of other codes were not counted)", s.notesDropped) end
    local welcome = R.Welcome and R.Welcome.Snapshot and R.Welcome.Snapshot()
    if welcome then Line("welcome dialog: %s (pending = a new installation has not seen it yet); shown this session: %d", welcome.state, welcome.shown) end
    local N = R.Notify and R.Notify.Snapshot and R.Notify.Snapshot()
    if N then Line("notices waiting: %d; cards showing: %s", N.queued, next(N.active) and "yes" or "no") end
    local status, reason = "ready", nil
    if s.savedVariables == "failed" then status, reason = "unavailable", "saved-data-failed"
    elseif s.hookFailures > 0 then status, reason = "unavailable", "init-failed"
    elseif not s.configReady then status, reason = "waiting", "configuration"
    elseif not s.inWorld then status, reason = "waiting", "world-not-entered" end
    return {
        configured = nil, initialized = s.configReady, status = status, reason = reason, lines = lines,
        limits = { "Counts are for this game session only. Mocked tests cannot show combat-lockdown or taint behaviour; that needs the game." },
    }
end

D.Register("lifecycle", { title = "Start-up and lifecycle", order = 12, snapshot = Lifecycle })
