-- TwichUI Workshop: the price scan
-- One explicit scan of the whole auction house, started only by the player's click (Session.StartScan) while the auction house is
-- open. It never buys, bids, cancels or posts. It is a full scan by the auction house's own whole-house request, not a search:
--
--   C_AuctionHouse.ReplicateItems()  asks for every listing                  (AuctionHouseDocumentation.lua: "used in place of an
--                                                                              'allItem' QueryAuctionItems call to query the entire auction house")
--   REPLICATE_ITEM_LIST_UPDATE       the listings are ready (may repeat as item data loads)
--   GetNumReplicateItems / GetReplicateItemInfo(i)   count, buyoutPrice, itemID, hasAllInfo ... (18 values, see Read)
--
-- WHAT THE UI SOURCE DOES NOT SAY (so this file assumes nothing about it and a live client has to show it, docs/workshop.md):
-- how often the request may be made, whether the event comes once or repeatedly, and whether a record's price is valid while
-- hasAllInfo is false. So: the request is sent only when the game says its throttled-message system is ready; every wait ends
-- (no response, dropped, never ready); the listings are read only after the event has been quiet for SETTLE seconds, and read again
-- if more arrive; and a scan counts as COMPLETE only when no record said it lacked information and nothing was cut off. Otherwise it
-- is kept as "not complete" and never replaces an earlier complete scan (Prices.Commit).
--
-- States (SC.state): idle, scanning (SC.phase: waiting, awaiting, settling, reading), done, interrupted, failed, unavailable.
-- The auction house closing, a second click, an old timer or an old event never leaves a half-finished scan behind: a scan ends once,
-- and its timers and events carry a token that ends with it. Only a finished, valid scan writes anything.

local R = TwichUI
local W = R.Workshop
local PR = W.Prices
local Int, Text = W.Int, W.Text
local SC = {}
W.Scan = SC

local SETTLE = 2             -- seconds the listing event must be quiet before the listings are read
local INFO_WAIT = 4          -- seconds to wait for more item data when a read had records without all their information
local MAX_REREADS = 2        -- reads repeated for that reason, at most
local MAX_RESTARTS = 3       -- times a read may be started over because the listings changed under it
local BATCH = 400            -- records read per step; the next step runs on the next timer tick so the interface stays responsive
local MAX_RECORDS = 250000   -- records read, at most (more makes the scan not complete)
local THROTTLE_WAIT = 30     -- seconds to wait for the auction house to be ready to take a request
local RESPONSE_WAIT = 90     -- seconds to wait for the listings after the request
local DROP_WINDOW = 5        -- a dropped message this soon after the request is taken as ours

SC.state, SC.phase, SC.why = "idle", nil, nil
SC.OnChange = function() end   -- set by Window.lua

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

---------------------------------------------------------------------------
-- Ending
---------------------------------------------------------------------------
local function End(state, why)
    token, gen = token + 1, gen + 1
    Listen(false)
    run = nil
    SC.state, SC.phase, SC.why, SC.progress = state, nil, why, nil
    SC.OnChange()
end

local function Ready()
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)
    return ok and ready == true
end

local function Finish(result)
    local scan = { realm = run.realm, side = run.side, at = time(), complete = result.complete, read = result.read,
        used = result.used, n = result.n, items = result.items }
    local ok, why = PR.Commit(run.key, scan)
    if ok then
        End("done")
        SC.result = { complete = result.complete, used = result.used, read = result.read, items = result.n, partialInfo = result.partialInfo }
    elseif why == "kept" then End("failed", "kept")
    elseif why == "held" then End("failed", "held")
    else End("failed", "unsaved") end
end

---------------------------------------------------------------------------
-- Reading the listings, a batch at a time
---------------------------------------------------------------------------
local function Record(k, batch)
    -- name, texture, count, quality, usable, level, levelType, minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName,
    -- owner, ownerFullName, saleStatus, itemID, hasAllInfo (ReplicateItemInfo)
    local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, item, hasAll = pcall(C_AuctionHouse.GetReplicateItemInfo, k)
    if ok then batch:Add(item, count, buyout, hasAll) else batch:Add(nil) end
end

local function ReadDone(batch, truncated)
    local items, n, cut = batch:Items()
    local result = { items = items, n = n, read = batch.read, used = batch.used, partialInfo = batch.partialInfo,
        complete = batch.partialInfo == 0 and not truncated and not cut }
    if batch.partialInfo > 0 and run.rereads < MAX_REREADS then
        -- some records weren't fully loaded yet: give the game a moment to send more, then read again; if nothing comes, this read stands
        run.rereads = run.rereads + 1
        run.pending = result
        gen = gen + 1
        SC.phase, SC.progress = "settling", nil
        SC.Settle(INFO_WAIT)
        SC.OnChange()
        return
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
    local truncated = run.truncated
    if n > MAX_RECORDS then n, truncated = MAX_RECORDS, true end
    local batch = PR.NewBatch(run.wanted)
    local i = 1
    SC.phase, SC.progress = "reading", { done = 0, total = n }
    local function Step()
        if mine ~= token or g ~= gen or SC.phase ~= "reading" then return end
        if not SC.AuctionOpen() then return End("interrupted", "closed") end
        local Perf = R.Perf
        local pt = Perf and Perf.on and Perf.Start("workshop.scan")
        local last = math.min(i + BATCH - 1, n)
        for k = i, last do Record(k, batch) end
        i = last + 1
        SC.progress.done = last
        if pt then Perf.Stop(pt) end
        if i <= n then
            SC.OnChange()
            C_Timer.After(0, Step)
        else
            ReadDone(batch, truncated)
        end
    end
    SC.OnChange()
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
    SC.OnChange()
end

local function Update()
    if SC.phase == "waiting" then return end   -- we haven't asked yet: not our answer
    if SC.phase == "reading" then
        run.restarts = run.restarts + 1
        if run.restarts > MAX_RESTARTS then return End("failed", "changing") end
    end
    run.pending = nil
    gen = gen + 1
    SC.phase, SC.progress = "settling", nil
    SC.Settle(SETTLE)
    SC.OnChange()
end

OnEvent = function(event)
    if not run then return end
    if event == "AUCTION_HOUSE_CLOSED" or event == "AUCTION_HOUSE_DISABLED" then
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
-- wanted: set [itemID] = true of the items worth keeping a price for; truncated: the set was cut to fit (so the scan can't be complete).
-- Returns true, or false and why. A click while a scan runs does nothing ("busy"). Every other refusal sets state "unavailable".
function SC.Start(wanted, truncated)
    if SC.Busy() then return false, "busy" end
    local function Refuse(why)
        SC.state, SC.phase, SC.why, SC.progress = "unavailable", nil, why, nil
        SC.OnChange()
        return false, why
    end
    local AH = C_AuctionHouse
    if not (AH and AH.ReplicateItems and AH.GetNumReplicateItems and AH.GetReplicateItemInfo and AH.IsThrottledMessageSystemReady) then
        return Refuse("api")
    end
    if not SC.AuctionOpen() then return Refuse("closed") end
    if type(wanted) ~= "table" or next(wanted) == nil then return Refuse("nothing") end
    local posting = R.AuctionScan   -- the posting page's one-item search: never compete with it
    if posting and posting.Busy and posting.Busy() then return Refuse("posting") end
    local key, realm, side = SC.Market()
    if not key then return Refuse("market") end
    if PR.Held() then return Refuse("held") end

    token, gen = token + 1, gen + 1
    run = { wanted = wanted, truncated = truncated == true, key = key, realm = realm, side = side, restarts = 0, rereads = 0 }
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
        SC.OnChange()
    end
    return true
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local UNAVAILABLE = {
    api = "This game version doesn't offer a full price scan to TwichUI.",
    closed = "Open the auction house to scan prices.",
    nothing = "Open one of your professions first, so TwichUI knows which items to price.",
    posting = "The posting page is searching. Try again in a moment.",
    market = "TwichUI couldn't tell which realm this auction house belongs to.",
    held = "These prices were saved by a newer TwichUI, so they can't be changed here.",
}
local FAILED = {
    api = "The game wouldn't take the request.",
    noResponse = "The auction house didn't send its listings. Try again in a few minutes.",
    dropped = "The auction house turned the request down. Try again in a moment.",
    throttled = "The auction house wasn't ready. Try again in a moment.",
    changing = "The listings kept changing while they were read. Try again.",
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
}

-- The one line about the latest attempt and its tone ("good", "warn", "quiet"); nil when there has been none
function SC.Message()
    local s = SC.state
    local kept = SC.prior and " Your earlier prices were kept." or ""
    if s == "scanning" then
        if SC.phase == "reading" and SC.progress and SC.progress.total > 0 then
            return ("Reading listings... %d%%"):format(math.floor(SC.progress.done * 100 / SC.progress.total)), "quiet"
        end
        return PHASE[SC.phase] or "Scanning...", "quiet"
    elseif s == "done" then
        local r = SC.result
        if r and r.complete then
            return ("Scan finished. Prices found for %d of your items."):format(r.items), "good"
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
