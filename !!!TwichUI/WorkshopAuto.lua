-- TwichUI: the Auction House visit that may update the Workshop's prices (A6)
-- The Workshop is a load-on-demand addon (WorkshopLauncher.lua), so the core keeps only this small detector. It does nothing until the
-- player opens the Auction House, and nothing at all when the setting is off. Per visit it makes AT MOST one short chain of timers:
--
--   open     PLAYER_INTERACTION_MANAGER_FRAME_SHOW (Auctioneer) or AUCTION_HOUSE_SHOW: the first of them starts a visit; the others, while that
--            visit is open, are the same visit and change nothing. PLAYER_INTERACTION_MANAGER_FRAME_HIDE (Auctioneer) or AUCTION_HOUSE_CLOSED ends it.
--   gates    setting on, not in combat (the Workshop is never loaded in combat, and a visit begun in combat is not retried), and the Blizzard
--            window (AuctionHouseFrame) actually shown. The window is looked for on the next frame and every 0.25 s for at most WAIT seconds, and each
--            look first checks the visit is still the current one and still open, so an event that arrives after the window closed loads nothing.
--   load     WorkshopLauncher.Load() once per visit (no retry in the same visit), then TwichUI_Workshop's Auto.Visit(id), which decides whether a
--            scan is due (market, 60 minutes, backoff, busy) and whether it may start itself (the capability below).
--
-- THE CAPABILITY (WA.Capability): whether the game lets an addon start the whole-house request from an event without a click. It is NOT known from
-- the UI source and has not been observed in the real client yet: the Test Lab cases autoscan.* find out. Until then it is "unknown", and a due
-- update is offered as ONE CLICK on the Auction House window instead of being requested. "supported" (to be set only from the probe's result, by
-- the owner) lets Auto.lua start it on opening; "click" records that a click is needed. Nothing here makes any Auction House request.
-- The setting is the core switch workshopAutoScan (default on): read at each opening, so turning it off takes effect at once.

local R = TwichUI
local WA = {}
R.WorkshopAuto = WA

WA.POLICY = "manual"        -- "manual" (shipped, owner decision after A6: a price scan starts only from the player's click, and opening the Auction House
                            -- does nothing, not even an offer) | "auto" (the A6 behaviour below, kept for a later decision; never reached while "manual")
WA.CAPABILITY = "unknown"   -- "unknown" | "click" | "supported": the developer gate described above
WA.WAIT = 5                 -- seconds the window is waited for, at most
WA.STEP = 0.25

local AUCTIONEER = (Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer) or 21

local visit, open = 0, false
local stats = { visits = 0, started = 0, skipped = nil, loads = 0, last = nil }

function WA.Enabled() return WA.POLICY == "auto" and R:Enabled("workshopAutoScan") end
function WA.Capability()
    local c = WA.CAPABILITY
    return (c == "supported" or c == "click") and c or "unknown"
end
function WA.IsCurrent(id) return open and id == visit end

local function Frame()
    local f = AuctionHouseFrame
    if type(f) ~= "table" or not f.IsShown then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

local function Skip(why) stats.skipped = why end

-- One look at the visit `id`, `waited` seconds in
local function Look(id, waited)
    if id ~= visit or not open then return end                      -- a later visit, or the window closed: nothing
    if not WA.Enabled() then return Skip("disabled") end
    if InCombatLockdown and InCombatLockdown() then return Skip("combat") end
    if not Frame() then
        if waited >= WA.WAIT then
            open = false                                             -- the window never came (a stale event): the next real opening is a new visit
            return Skip("noWindow")
        end
        return C_Timer.After(WA.STEP, function() Look(id, waited + WA.STEP) end)
    end
    local L = R.WorkshopLauncher
    if not L then return Skip("noLauncher") end
    stats.loads = stats.loads + 1
    local ok, why = L.Load()
    if not ok then return Skip("load:" .. tostring(why)) end
    if id ~= visit or not open then return end                      -- closed while the Workshop loaded
    local WS = R.Workshop
    if not (WS and WS.Auto and WS.Auto.Visit) then return Skip("noAuto") end
    local good, action, reason = pcall(WS.Auto.Visit, id)
    if not good then R.Fault("workshop auto", action) return Skip("error") end
    stats.last = action .. ":" .. tostring(reason)
    if action == "scan" then stats.started = stats.started + 1 end
    stats.skipped = nil
end

local function Opened()
    if open then return end                                          -- the same visit, said again
    open = true
    visit = visit + 1
    stats.visits, stats.skipped, stats.last = stats.visits + 1, nil, nil
    if not WA.Enabled() then return Skip("disabled") end
    if InCombatLockdown and InCombatLockdown() then return Skip("combat") end
    local id = visit
    C_Timer.After(0, function() Look(id, 0) end)
end

local function Closed() open = false end
WA.Opened, WA.Closed = Opened, Closed   -- what the events below call (the simulator scenario calls them too: its fake events would make Blizzard load its real auction UI)

R:OnInit(function()
    R:On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind) if kind == AUCTIONEER then Opened() end end)
    R:On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind) if kind == AUCTIONEER then Closed() end end)
    R:On("AUCTION_HOUSE_SHOW", Opened)
    R:On("AUCTION_HOUSE_CLOSED", Closed)
end)

function WA.Snapshot()
    return { capability = WA.Capability(), enabled = WA.Enabled(), visit = visit, open = open, visits = stats.visits, started = stats.started,
        loads = stats.loads, skipped = stats.skipped, last = stats.last }
end
