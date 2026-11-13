-- TwichUI Workshop: the price scan
-- One explicit scan of the whole auction house, started only by the player's click (Session.StartScan) while the auction house is
-- open. It never buys, bids, cancels or posts. It is a full scan by the auction house's own whole-house request, not a search, and it
-- keeps EVERY item the auction house lists (a cheapest buyout each), whatever the player's professions: no recipe is needed.
--
--   C_AuctionHouse.ReplicateItems()  asks for every listing                  (AuctionHouseDocumentation.lua: "used in place of an
--                                                                              'allItem' QueryAuctionItems call to query the entire auction house")
--   REPLICATE_ITEM_LIST_UPDATE       the listings are ready (may repeat as item data loads)
--   GetNumReplicateItems / GetReplicateItemInfo(i)   count, buyoutPrice, itemID, hasAllInfo ... (18 values, see Read)
--
-- WHAT THE OTHER SCANNERS SHOW (read-only references, nothing copied): Naowh's price scan and Profession Master both read the listings
-- on the FIRST REPLICATE_ITEM_LIST_UPDATE and ignore the later ones; both read records 0 .. n-1 (TSM's wrapper also passes index - 1).
-- Later updates are therefore not treated as "the listings changed": only a different COUNT of listings is. Mastercraft doesn't use
-- ReplicateItems on this client at all: it pages an empty browse query (SendBrowseQuery, RequestMoreBrowseResults until
-- HasFullBrowseResults); that path is not built here (docs/workshop.md).
--
-- WHAT THE UI SOURCE DOES NOT SAY (so this file assumes nothing about it and a live client has to show it, docs/workshop.md):
-- how often the request may be made, whether the event comes once or repeatedly, and whether a record's price is valid while
-- hasAllInfo is false. So: the request is sent only when the game says its throttled-message system is ready; every wait ends
-- (no response, dropped, never ready); the listings are read only after the event has been quiet for SETTLE seconds (at most
-- MAX_SETTLE of waiting); updates during a read never stop it, only a different NUMBER of listings starts it over; and a scan counts
-- as COMPLETE only when no record said it lacked information, the count held still and nothing was cut off. Otherwise it
-- is kept as "not complete" and never replaces an earlier complete scan (Prices.BeginCommit).
-- After the read the result is merged into the saved market and its history in small steps (phase "saving"), then written at once:
-- nothing is saved until the last step, and the auction house closing during the saving changes nothing (the listings were read).
--
-- States (SC.state): idle, scanning (SC.phase: waiting, awaiting, settling, reading, saving), done, interrupted, failed, unavailable.
-- The auction house closing, a second click, an old timer or an old event never leaves a half-finished scan behind: a scan ends once,
-- and its timers and events carry a token that ends with it. Only a finished, valid scan writes anything.

local R = TwichUI
local W = R.Workshop
local PR = W.Prices
local D = W.Dist
local Int, Text = W.Int, W.Text
local SC = {}
W.Scan = SC

local SETTLE = 2             -- seconds the listing event must be quiet before the listings are read
local INFO_WAIT = 4          -- seconds to wait for more item data when a read had records without all their information
local MAX_REREADS = 2        -- reads repeated for that reason, at most
local MAX_RESTARTS = 3       -- times a read may be started over because the NUMBER of listings changed while it was read
local MAX_SETTLE = 10        -- seconds a wait for quiet may last: more updates than that no longer push the read back
local BATCH = 400            -- records read per step; the next step runs on the next timer tick so the interface stays responsive
local BUILD_MS = 3           -- milliseconds the entries and distributions may be built per timer tick (a step is at most Prices.TIERS_STEP tiers)
local SAVE_MS = 4            -- (A4) milliseconds of commit steps per timer tick (a step is at most Prices.COMMIT_STEP work units; history folds cost more)
local MAX_RECORDS = 250000   -- records read, at most (more makes the scan not complete)
local THROTTLE_WAIT = 30     -- seconds to wait for the auction house to be ready to take a request
local RESPONSE_WAIT = 90     -- seconds to wait for the listings after the request
local DROP_WINDOW = 5        -- a dropped message this soon after the request is taken as ours

SC.state, SC.phase, SC.why = "idle", nil, nil
SC.ended = 0                   -- how many scans (or refused starts) have ended this session: a watcher records each once
SC.OnChange = function() end   -- set by Window.lua
local listeners = {}           -- more watchers (the auction house button): SC.Listen(fn); each is told whenever the state or progress changes

local function Changed()
    SC.OnChange()
    for i = 1, #listeners do listeners[i]() end
end
function SC.Listen(fn) listeners[#listeners + 1] = fn end

local EVENTS = { "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "AUCTION_HOUSE_CLOSED", "AUCTION_HOUSE_DISABLED" }

local ev                   -- the event frame, made on the first scan
local token = 0            -- ends with each scan: its timers and steps do nothing after that
local gen = 0              -- changes with each listing update: a settle timer or a read from before it does nothing
local run                  -- the scan in progress

local OnEvent

local function Listen(on)
    if not ev then
        if not on then return end
        ev = CreateFrame("Frame")
        ev:SetScript("OnEvent", function(_, event) OnEvent(event) end)
    end
    for _, e in ipairs(EVENTS) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
end

---------------------------------------------------------------------------
-- The auction house and its market
---------------------------------------------------------------------------
function SC.AuctionOpen()
    local f = AuctionHouseFrame
    if type(f) ~= "table" or not f.IsShown then return false end
    local ok, shown = pcall(f.IsShown, f)
    return ok and shown == true
end

function SC.Realm()
    local ok, name = pcall(GetRealmName)
    return ok and Text(name, 60) or nil
end

-- The market of the auction house that is open: key, realm, side. The side is the auctioneer's faction as the game gives it
-- ("Alliance", "Horde", ...), or "unknown" when the game doesn't say: a market of its own, never merged with another.
function SC.Market()
    local realm = SC.Realm()
    local side
    if UnitFactionGroup then
        local ok, s = pcall(UnitFactionGroup, "npc")
        side = ok and Text(s, 20) or nil
    end
    return PR.Key(realm, side), realm, side or "unknown"
end

function SC.Busy() return SC.state == "scanning" end

-- How far along the scan is, 0 to 1, for a progress bar; nil when no scan is running. It never goes backwards within a scan (a read that
-- starts over, or a wait for item data after a read, holds the bar where it was). The first stretch is the asking and the wait for the game
-- (a few percent), the rest is the reading, which is what takes the time.
local P_ASK, P_WAIT, P_READ, P_SAVE = 0.03, 0.08, 0.80, 0.12
function SC.Progress()
    if SC.state ~= "scanning" or not run then return nil end
    local f
    local phase = SC.phase
    if phase == "waiting" then f = 0
    elseif phase == "awaiting" then f = P_ASK
    elseif phase == "reading" and SC.progress and SC.progress.total > 0 then
        f = P_WAIT + P_READ * math.min(1, SC.progress.done / SC.progress.total)
    elseif phase == "saving" then f = P_WAIT + P_READ + P_SAVE * (run.saveFrac or 0)
    else f = P_WAIT end
    if f < (run.frac or 0) then f = run.frac end
    run.frac = f
    return f
end

---------------------------------------------------------------------------
-- Ending
---------------------------------------------------------------------------
local function End(state, why)
    token, gen = token + 1, gen + 1
    Listen(false)
    run = nil
    SC.state, SC.phase, SC.why, SC.progress = state, nil, why, nil
    SC.ended = SC.ended + 1
    Changed()
end

local function Ready()
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and ready == true
end

local function Perf(name, fn, ...)
    local P = R.Perf
    local pt = P and P.on and P.Start(name)
    local a, b, c = fn(...)
    if pt then P.Stop(pt) end
    return a, b, c
end

-- The listings are read: merge them into the saved market a step at a time (the interface stays responsive), then write them at once.
-- A step that fails, or a scan that ends meanwhile, leaves the saved prices and history as they were.
local function SaveStep(mine)
    if mine ~= token or SC.phase ~= "saving" or not run then return end
    local job, result = run.job, run.result
    -- steps of at most Prices.COMMIT_STEP work units, as many as fit in SAVE_MS (none is begun after that), then the frame goes on
    local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
    local t0 = clock and clock()
    local ok, done
    repeat ok, done = pcall(Perf, "workshop.scan", job.Step, job) until not ok or done or not t0 or clock() - t0 >= SAVE_MS
    if not ok then return End("failed", "unsaved") end
    if not done then
        run.saveFrac = job:Progress()
        Changed()
        return C_Timer.After(0, function() SaveStep(mine) end)
    end
    local good, applied, why = pcall(Perf, "workshop.scan", job.Apply, job)
    if not (good and applied) then return End("failed", (good and why == "held") and "held" or "unsaved") end
    -- the result is set before the end is announced: a watcher told of the end reads the message at once
    SC.result = { complete = result.complete, used = result.used, read = result.read, items = result.n, partialInfo = result.partialInfo,
        changed = result.changed, cut = result.cut, dropped = result.dropped, updates = result.updates, restarts = result.restarts,
        alg = job.distOk == true and D.ALG or nil }
    End("done")
end

local function Finish(result)
    local scan = { realm = run.realm, side = run.side, at = time(), complete = result.complete, cut = result.cut, changed = result.changed,
        read = result.read, used = result.used, invalid = result.invalid, noBuyout = result.noBuyout, partial = result.partialInfo, n = result.n,
        items = result.items, dist = result.dist, alg = result.dist and D.ALG or nil }
    local job, why = PR.BeginCommit(run.key, scan)
    if not job then
        if why == "kept" then return End("failed", "kept") end
        if why == "held" then return End("failed", "held") end
        return End("failed", "unsaved")
    end
    run.job, run.result, run.saveFrac, run.pending = job, result, 0, nil
    SC.phase, SC.progress = "saving", nil
    gen = gen + 1
    Changed()
    SaveStep(token)
end

---------------------------------------------------------------------------
-- Reading the listings, a batch at a time
---------------------------------------------------------------------------
-- k is the game's own index: 0-based (records 0 .. n-1), as every other scanner reads it
local function Record(k, batch)
    -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName,
    -- owner, ownerFullName, saleStatus, itemID, hasAllInfo (ReplicateItemInfo)
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, item, hasAll = pcall(C_AuctionHouse.GetReplicateItemInfo, k)
    if ok then batch:Add(item, count, buyout, hasAll) else batch:Add(nil) end
end

-- settleAt marks when the waiting began; more updates restart the quiet period but not that mark
local function EnterSettle(wait)
    gen = gen + 1
    if SC.phase ~= "settling" then run.settleAt = GetTime() end
    SC.phase, SC.progress = "settling", nil
    SC.Settle(wait)
    Changed()
end

local function ReadDone(batch, truncated, items, n, over, dropped, dist)
    local cut = truncated or over
    local result = { items = items, n = n, read = batch.read, used = batch.used, invalid = batch.invalid, noBuyout = batch.noBuyout,
        partialInfo = batch.partialInfo, dropped = dropped, dist = dist,
        cut = cut, complete = batch.partialInfo == 0 and not cut, updates = run.updates, restarts = run.restarts }
    -- more updates during the read are item data arriving, not a different market. A different number of listings is: start
    -- over a few times, and if it never holds still keep what was read as a scan that is NOT complete (never a failure).
    local ok, now = pcall(C_AuctionHouse.GetNumReplicateItems)
    now = ok and Int(now, 0, W.MAX_ID) or nil
    if now and now ~= run.readN then
        if run.restarts < MAX_RESTARTS then
            run.restarts = run.restarts + 1
            run.pending = nil
            return EnterSettle(SETTLE)
        end
        result.complete, result.changed, result.cut = false, true, true
    end
    if batch.partialInfo > 0 and run.rereads < MAX_REREADS then
        -- some records weren't fully loaded yet: give the game a moment to send more, then read again; if nothing comes, this read stands
        run.rereads = run.rereads + 1
        run.pending = result
        return EnterSettle(INFO_WAIT)
    end
    Finish(result)
end

local function BeginRead()
    local mine, g = token, gen
    local ok, num = pcall(C_AuctionHouse.GetNumReplicateItems)
    local n = ok and Int(num, 0, W.MAX_ID) or nil
    if not n then return End("failed", "unreadable") end
    if n == 0 then return End("failed", "empty") end
    run.pending = nil
    run.readN = n
    local truncated = false
    if n > MAX_RECORDS then n, truncated = MAX_RECORDS, true end
    local batch = PR.NewBatch(run.priority)
    local i = 0                    -- 0-based: the records are 0 .. n-1
    SC.phase, SC.progress = "reading", { done = 0, total = n }
    local function Step()
        if mine ~= token or g ~= gen or SC.phase ~= "reading" then return end
        if not SC.AuctionOpen() then return End("interrupted", "closed") end
        local Perf = R.Perf
        local pt = Perf and Perf.on and Perf.Start("workshop.scan")
        local last = math.min(i + BATCH - 1, n - 1)
        for k = i, last do Record(k, batch) end
        i = last + 1
        SC.progress.done = i
        if pt then Perf.Stop(pt) end
        if i < n then
            Changed()
            C_Timer.After(0, Step)
        else
            -- the entries are built a step at a time too (Prices.ITEMS_STEP): at 40,000 items the one call was a visible hitch
            local job = batch:ItemsJob()
            local function Build()
                if mine ~= token or g ~= gen or SC.phase ~= "reading" then return end
                if not SC.AuctionOpen() then return End("interrupted", "closed") end
                local Perf = R.Perf
                local bt = Perf and Perf.on and Perf.Start("workshop.scan")
                -- steps of at most Prices.TIERS_STEP tiers, as many as fit in BUILD_MS (a step is never begun after that), then the frame goes on
                local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
                local t0 = clock and clock()
                local done
                repeat done = job:Step() until done or not t0 or clock() - t0 >= BUILD_MS
                if bt then Perf.Stop(bt) end
                if not done then return C_Timer.After(0, Build) end
                ReadDone(batch, truncated, job:Result())
            end
            C_Timer.After(0, Build)
        end
    end
    Changed()
    Step()
end

-- Waits until no update has come for `wait` seconds, then reads (or, after a read that lacked item data, accepts that read)
function SC.Settle(wait)
    local mine, g = token, gen
    C_Timer.After(wait, function()
        if mine ~= token or g ~= gen or SC.phase ~= "settling" or not run then return end
        if run.pending then Finish(run.pending) else BeginRead() end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function Send()
    local ok = pcall(C_AuctionHouse.ReplicateItems)
    if not ok then return End("failed", "api") end
    run.sentAt = GetTime()
    SC.phase = "awaiting"
    local mine = token
    C_Timer.After(RESPONSE_WAIT, function()
        if mine == token and SC.phase == "awaiting" then End("failed", "noResponse") end
    end)
    Changed()
end

local function Update()
    if SC.phase == "waiting" or SC.phase == "saving" then return end   -- we haven't asked yet (not our answer), or the listings are read
    run.updates = run.updates + 1
    if SC.phase == "reading" then return end   -- the read goes on; ReadDone checks whether the count really changed
    if SC.phase == "settling" and GetTime() - (run.settleAt or 0) >= MAX_SETTLE then return end   -- a steady stream can't hold the read back forever
    run.pending = nil
    EnterSettle(SETTLE)
end

OnEvent = function(event)
    if not run then return end
    if event == "AUCTION_HOUSE_CLOSED" or event == "AUCTION_HOUSE_DISABLED" then
        if SC.phase == "saving" then return end   -- the listings were read already: finish saving them
        End("interrupted", "closed")
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if SC.phase == "waiting" then Send() end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        if SC.phase == "awaiting" and run.sentAt and GetTime() - run.sentAt < DROP_WINDOW then End("failed", "dropped") end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Update()
    end
end

---------------------------------------------------------------------------
-- Starting
---------------------------------------------------------------------------
-- priority: optional set [itemID] = true of items to keep first should the auction house list more than Prices.MAX_ITEMS (the recipes'
-- items); it limits nothing, and no recipe is needed. Returns true, or false and why. A click while a scan runs does nothing
-- ("busy"). Every other refusal sets state "unavailable".
function SC.Start(priority)
    if SC.Busy() then return false, "busy" end
    local function Refuse(why)
        SC.state, SC.phase, SC.why, SC.progress = "unavailable", nil, why, nil
        SC.ended = SC.ended + 1
        Changed()
        return false, why
    end
    local AH = C_AuctionHouse
    if not (AH and AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo and AH.IsThrottledMessageSystemReady) then
        return Refuse("api")
    end
    if not SC.AuctionOpen() then return Refuse("closed") end
    local posting = R.AuctionScan   -- the posting page's one-item search: never compete with it
    if posting and posting.Busy and posting.Busy() then return Refuse("posting") end
    local key, realm, side = SC.Market()
    if not key then return Refuse("market") end
    if PR.Held() then return Refuse("held") end

    token, gen = token + 1, gen + 1
    run = { priority = type(priority) == "table" and priority or nil, key = key, realm = realm, side = side, restarts = 0, rereads = 0, updates = 0 }
    SC.prior = PR.Market(key) ~= nil
    SC.result, SC.why, SC.progress = nil, nil, nil
    SC.state, SC.phase = "scanning", "waiting"
    Listen(true)
    if Ready() then
        Send()
    else
        local mine = token
        C_Timer.After(THROTTLE_WAIT, function()
            if mine == token and SC.phase == "waiting" then End("failed", "throttled") end
        end)
        Changed()
    end
    return true
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local UNAVAILABLE = {
    api = "This game version doesn't offer a full price scan to TwichUI.",
    closed = "Open the auction house to scan prices.",
    posting = "The posting page is searching. Try again in a moment.",
    market = "TwichUI couldn't tell which realm this auction house belongs to.",
    held = "These prices were saved by a newer TwichUI, so they can't be changed here.",
}
local FAILED = {
    api = "The game wouldn't take the request.",
    noResponse = "The auction house didn't send its listings. Try again in a few minutes.",
    dropped = "The auction house turned the request down. Try again in a moment.",
    throttled = "The auction house wasn't ready. Try again in a moment.",
    empty = "The auction house reported no listings.",
    unreadable = "The listings couldn't be read.",
    kept = "The scan didn't finish cleanly, so your earlier complete prices were kept.",
    held = "These prices were saved by a newer TwichUI, so they can't be changed here.",
    unsaved = "The prices couldn't be saved.",
}
local PHASE = {
    waiting = "Waiting for the auction house to be ready...",
    awaiting = "Asking the auction house for its listings...",
    settling = "Receiving listings...",
    saving = "Saving prices...",
}

-- The one line about the latest attempt and its tone ("good", "warn", "quiet"); nil when there has been none
function SC.Message()
    local s = SC.state
    local kept = SC.prior and " Your earlier prices were kept." or ""
    if s == "scanning" then
        if SC.phase == "reading" and SC.progress and SC.progress.total > 0 then
            return "Reading listings...", "quiet"
        end
        return PHASE[SC.phase] or "Scanning...", "quiet"
    elseif s == "done" then
        local r = SC.result
        if r and r.complete then
            return ("Scan finished. Prices found for %d items."):format(r.items), "good"
        end
        if r and r.changed then
            return "Scan finished, but the auction house's list kept changing while it was read, so prices may be incomplete.", "warn"
        end
        if r and r.cut then
            return "Scan finished, but the auction house lists more than TwichUI keeps, so some prices are missing.", "warn"
        end
        return "Scan finished, but some listings hadn't fully loaded, so prices may be incomplete.", "warn"
    elseif s == "interrupted" then
        return "The scan stopped because the auction house closed." .. kept, "warn"
    elseif s == "failed" then
        local text = FAILED[SC.why] or "The scan didn't finish."
        if SC.why == "kept" or SC.why == "held" or SC.why == "unsaved" then return text, "warn" end
        return text .. kept, "warn"
    elseif s == "unavailable" then
        return UNAVAILABLE[SC.why] or "A price scan isn't available right now.", "warn"
    end
    return nil, "quiet"
end

function SC.Snapshot() return { state = SC.state, phase = SC.phase } end
