-- TwichUI Workshop: updating prices when the player opens the auction house (milestone A6)
-- The core (WorkshopAuto.lua) sees the auction house open, checks the setting, loads this addon and calls A.Visit once per visit. Everything
-- else is here. It starts the SAME scan the button starts (Session.StartScan -> Scan.Start), never a second scanner, and only when every gate
-- passes. It never buys, bids, posts or cancels, and it makes no request of its own.
--
--   Decide(c)   pure: what to do with this visit, from plain facts (tests/test_workshop_auto.lua drives every gate)
--   A.Visit(id) the one entry point: gathers the facts, decides, and either starts the scan or leaves a one-click prompt
--
-- THE CAPABILITY GATE (R.WorkshopAuto.Capability(), core): whether the game accepts ReplicateItems from an event handler without a click is NOT
-- established by the UI source (the API documentation says nothing of hardware events) and has not been observed yet (the Test Lab probes
-- "autoscan.*" are to run in the real client first). So:
--   "supported"  the scan is started by this module on opening (the intended behaviour, switched on only after the probe)
--   "click"      the client needs a click: a prompt "Update prices" is shown instead, and the player's click is an ordinary manual scan
--   "unknown"    (the shipped value) the same prompt; no request is made that the client was not shown to accept
-- A prompt is never an attempt: the one automatic attempt of a visit is used only by a request actually made.
--
-- THE POLICY: at most one automatic attempt per visit; a market's newest accepted scan must be 60 minutes old; after an automatic refusal
-- (dropped, throttled, no response, the API) the market is left alone for 15 minutes of this session; nothing in combat, while a scan runs or
-- the posting search is busy, or when the saved prices are held (a newer TwichUI wrote them). Freshness is the market's newest accepted FULL
-- scan (a legacy recipes-only scan is not one); a scan finished earlier this session also counts, by the monotonic clock, so a clock that moved
-- backwards cannot make a scan repeat. A saved time in the future beyond a small skew is not trusted as fresh.

local R = TwichUI
local W = R.Workshop
local PR, SC = W.Prices, W.Scan
local A = {}
W.Auto = A

A.COOLDOWN = 3600       -- seconds: a market scanned (accepted) more recently than this is not scanned again automatically
A.BACKOFF = 900         -- seconds, session memory only: after an automatic refusal
A.SKEW = 300            -- seconds a saved time may lie in the future before it is not believed

A.wall = function() return time() end                 -- tests replace both clocks
A.mono = function() return GetTime() end

local backoff = {}      -- [market key] = monotonic time until which no automatic attempt is made
local doneAt = {}       -- [market key] = monotonic time of the last accepted scan this session (manual or automatic)
local lastVisit = 0     -- the newest visit id handled: an id is handled once
A.state = { visit = 0, action = nil, why = nil, key = nil, prompt = nil }   -- what the newest visit came to (read by the button and diagnostics)

local REFUSED = { dropped = true, throttled = true, noResponse = true, api = true }

---------------------------------------------------------------------------
-- Pure
---------------------------------------------------------------------------
-- Is the market fresh enough to leave alone? at: saved time of its newest accepted full scan (or nil); now: wall clock; monoAgo: seconds since
-- an accepted scan this session by the monotonic clock (or nil).
function A.Fresh(at, now, monoAgo)
    if monoAgo and monoAgo >= 0 and monoAgo < A.COOLDOWN then return true end
    if type(at) ~= "number" or type(now) ~= "number" or at ~= at or now ~= now then return false end
    if at > now + A.SKEW then return false end            -- the clock moved back: this time cannot be trusted as "recent"
    return now - at < A.COOLDOWN
end

-- c: enabled, combat, open, key, held, handled (this visit already used its attempt), busy, posting, at, now, monoAgo, backoffLeft (seconds or nil),
--    capability ("supported" | "click" | "unknown")
-- Returns "scan" (start it), "prompt" (offer the one-click button) or "skip", and the reason.
function A.Decide(c)
    if not c.enabled then return "skip", "disabled" end
    if c.combat then return "skip", "combat" end
    if not c.open then return "skip", "closed" end
    if c.handled then return "skip", "visit" end
    if not c.key then return "skip", "market" end
    if c.held then return "skip", "held" end
    if c.busy then return "skip", "busy" end
    if c.posting then return "skip", "posting" end
    if A.Fresh(c.at, c.now, c.monoAgo) then return "skip", "fresh" end
    if c.backoffLeft and c.backoffLeft > 0 then return "skip", "backoff" end
    if c.capability == "supported" then return "scan", "due" end
    return "prompt", c.capability == "click" and "click" or "unverified"
end

---------------------------------------------------------------------------
-- The facts, and the visit
---------------------------------------------------------------------------
local function Facts(visit)
    local WA = R.WorkshopAuto
    local key = SC.Market()
    local info = key and PR.Market(key) or nil
    local posting = R.AuctionScan
    local mono = A.mono()
    local left = key and backoff[key] and backoff[key] - mono or nil
    return {
        enabled = WA ~= nil and WA.Enabled(), combat = InCombatLockdown and InCombatLockdown() or false,
        open = SC.AuctionOpen() and (WA == nil or WA.IsCurrent(visit)), key = key, held = PR.Held(),
        handled = visit <= lastVisit, busy = SC.Busy(), posting = posting ~= nil and posting.Busy ~= nil and posting.Busy() == true or false,
        at = info and not info.legacy and info.scope == "full" and info.at or nil, now = A.wall(),
        monoAgo = key and doneAt[key] and mono - doneAt[key] or nil, backoffLeft = left,
        capability = WA and WA.Capability() or "unknown",
    }
end

-- Called by the core once per visit, with the auction house window shown. Returns the action and why (for tests and diagnostics).
function A.Visit(visit)
    visit = tonumber(visit) or 0
    local c = Facts(visit)
    local action, why = A.Decide(c)
    local st = { visit = visit, action = action, why = why, key = c.key, prompt = nil }
    A.state = st
    if visit > lastVisit then lastVisit = visit end    -- the id is used up whatever came of it (a stale call later does nothing)
    if action == "scan" then
        local ok, reason = W.Session.StartScan({ auto = true })
        if not ok then
            st.action, st.why = "skip", reason or "refused"
            if reason == "api" and c.key then backoff[c.key] = A.mono() + A.BACKOFF end
        end
    elseif action == "prompt" then
        st.prompt = why
        if W.AuctionButton and W.AuctionButton.Refresh then W.AuctionButton.Refresh() end
    end
    return st.action, st.why
end

-- Is there an "Update prices" prompt waiting for the player (a scan was due but the client needs a click, or its support is not verified)?
function A.Prompting()
    local st = A.state
    return st.prompt ~= nil and st.key ~= nil and not SC.Busy() and SC.AuctionOpen()
end

-- The player used the button or started a scan some other way: the prompt is answered
function A.Answered() A.state.prompt = nil end

---------------------------------------------------------------------------
-- What the scans taught: freshness and refusals of this session
---------------------------------------------------------------------------
SC.Listen(function()
    local key = SC.key
    if SC.state == "done" and key then
        doneAt[key] = A.mono()
        backoff[key] = nil
        A.state.prompt = nil
    elseif SC.state == "failed" and SC.auto and key and REFUSED[SC.why] then
        backoff[key] = A.mono() + A.BACKOFF
    end
end)

function A.Backoff(key) return backoff[key] end
function A.Reset() backoff, doneAt, lastVisit = {}, {}, 0; A.state = { visit = 0 } end   -- tests only
function A.Snapshot()
    local n = 0
    for _ in pairs(backoff) do n = n + 1 end
    return { visit = A.state.visit, action = A.state.action, why = A.state.why, prompt = A.state.prompt, backedOff = n, lastVisit = lastVisit }
end
