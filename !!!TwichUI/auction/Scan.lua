-- TwichUI: auction posting, the search
-- One search for one item, started only when the player picks that item.
-- Follows the auction house's own throttle (never sends while the client says
-- it isn't ready, never retries by itself), asks for at most a couple of extra
-- pages, and says plainly when what it has is partial. Results live here only
-- until the next search or until the auction house closes; nothing is saved.
--
-- States: idle, waiting (for the throttle), searching, more (extra pages),
-- done, none (no listings at all), partial, dropped, noResponse.

local R = TwichUI
local P = R.AuctionPrice
local SC = {}
R.AuctionScan = SC

local EXTRA_PAGES = 2        -- extra result pages to ask for, at most
local TIMEOUT = 15           -- seconds without an answer before saying so
local READ_LIMIT = 500       -- listings read into memory, at most
local DROP_WINDOW = 5        -- a dropped message this soon after sending is taken as ours

SC.state = "idle"
SC.OnChange = function() end  -- set by auction/Window.lua

local ev = CreateFrame("Frame")
local token = 0
local target, extra, sentAt
local sorts                  -- built on first use, once Enum is certain to be there

local SEARCH_EVENTS = {
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}

local function Listen(on)
    for _, e in ipairs(SEARCH_EVENTS) do
        if on then ev:RegisterEvent(e) else ev:UnregisterEvent(e) end
    end
end

local function Sorts()
    if not sorts then
        local O = Enum.AuctionHouseSortOrder
        sorts = {   -- as Blizzard's own sell frames ask
            item = { { sortOrder = O.Buyout, reverseSort = false }, { sortOrder = O.Bid, reverseSort = false } },
            commodity = { { sortOrder = O.Price, reverseSort = false }, { sortOrder = O.Name, reverseSort = false } },
        }
    end
    return sorts
end

local function Set(state)
    SC.state = state
    SC.OnChange()
end

-- Reads what the client holds for this search into plain tables.
local function Read()
    local list = {}
    if target.kind == "commodity" then
        local n = math.min(C_AuctionHouse.GetNumCommoditySearchResults(target.itemID) or 0, READ_LIMIT)
        for i = 1, n do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(target.itemID, i)
            if r then
                list[#list + 1] = { unitPrice = r.unitPrice, quantity = r.quantity, numOwnerItems = r.numOwnerItems }
            end
        end
        SC.summary = P.SummariseCommodities(list)
    else
        local key = target.queryKey
        local n = math.min(C_AuctionHouse.GetNumItemSearchResults(key) or 0, READ_LIMIT)
        for i = 1, n do
            local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
            if r then
                local k = r.itemKey or {}
                list[#list + 1] = {
                    itemLevel = k.itemLevel or 0, itemSuffix = k.itemSuffix or 0,
                    buyout = r.buyoutAmount, minBid = r.minBid, quantity = r.quantity,
                    own = r.containsOwnerItem, link = r.itemLink,
                }
            end
        end
        SC.summary = P.SummariseItems(list, target)
    end
    SC.listings = list
end

local function HasFull()
    if target.kind == "commodity" then return C_AuctionHouse.HasFullCommoditySearchResults(target.itemID) end
    return C_AuctionHouse.HasFullItemSearchResults(target.queryKey)
end

local function Finish(state)
    Listen(false)
    SC.scannedAt, SC.scannedClock = time(), GetTime()
    SC.stale = false
    local mine = token
    C_Timer.After(SC.STALE_AFTER, function()
        if mine == token and SC.listings then SC.stale = true; SC.OnChange() end
    end)
    Set(state)
end

local function Timeout()
    local mine = token
    C_Timer.After(TIMEOUT, function()
        if mine ~= token or not (SC.state == "searching" or SC.state == "more") then return end
        if SC.listings and #SC.listings > 0 then Finish("partial") else Finish("noResponse") end
    end)
end

local function Send()
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then Set("waiting") return end
    local s = Sorts()
    if target.kind == "commodity" then
        C_AuctionHouse.SendSearchQuery(target.queryKey, s.commodity, false)
    elseif target.isEquipment then
        C_AuctionHouse.SendSellSearchQuery(target.queryKey, s.item, false)
    else
        C_AuctionHouse.SendSearchQuery(target.queryKey, s.item, false)
    end
    sentAt = GetTime()
    Timeout()
    Set("searching")
end

local function RequestMore()
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then
        SC.moreWaiting = true
        return
    end
    SC.moreWaiting = false
    extra = extra + 1
    local full
    if target.kind == "commodity" then
        full = C_AuctionHouse.RequestMoreCommoditySearchResults(target.itemID)
    else
        full = C_AuctionHouse.RequestMoreItemSearchResults(target.queryKey)
    end
    if full then
        Read()
        Finish(#SC.listings > 0 and "done" or "none")
        return
    end
    sentAt = GetTime()
    Timeout()
    Set("more")
end

local function OnResults()
    Read()
    if HasFull() then
        Finish(#SC.listings > 0 and "done" or "none")
    elseif extra < EXTRA_PAGES then
        RequestMore()
        if SC.moreWaiting then Set("more") end
    else
        Finish("partial")
    end
end

local function IsOurs(event, arg)
    if not target then return false end
    if event:find("^COMMODITY") then
        return target.kind == "commodity" and arg == target.itemID
    end
    if target.kind ~= "item" or type(arg) ~= "table" then return false end
    local k = target.queryKey
    return arg.itemID == k.itemID and (arg.itemLevel or 0) == (k.itemLevel or 0)
        and (arg.itemSuffix or 0) == (k.itemSuffix or 0)
        and (arg.battlePetSpeciesID or 0) == (k.battlePetSpeciesID or 0)
end

ev:SetScript("OnEvent", function(_, event, arg)
    if not target then return end
    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if SC.state == "waiting" then Send()
        elseif SC.moreWaiting then RequestMore() end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        if (SC.state == "searching" or SC.state == "more") and sentAt and GetTime() - sentAt < DROP_WINDOW then
            if SC.listings and #SC.listings > 0 then Finish("partial") else Finish("dropped") end
        end
    elseif (SC.state == "searching" or SC.state == "more") and IsOurs(event, arg) then
        OnResults()
    end
end)

SC.STALE_AFTER = 300         -- seconds before results are shown as out of date

-- t: { kind = "commodity"|"item", itemID, queryKey, isEquipment, matchVariant, itemLevel, itemSuffix }
function SC.Start(t)
    SC.Stop()
    target, extra = t, 0
    SC.target = t
    Listen(true)
    Send()
end

-- Forgets this search. A query already sent can't be called back; its
-- answer is simply ignored.
function SC.Stop()
    token = token + 1
    Listen(false)
    target, sentAt = nil, nil
    SC.target, SC.listings, SC.summary = nil, nil, nil
    SC.scannedAt, SC.scannedClock, SC.stale, SC.moreWaiting = nil, nil, false, false
    SC.state = "idle"
end

function SC.Busy()
    return SC.state == "waiting" or SC.state == "searching" or SC.state == "more"
end

-- After a posting the market has changed; keep the results but call them old.
function SC.MarkStale()
    if SC.listings then SC.stale = true end
end
