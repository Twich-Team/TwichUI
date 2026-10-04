-- Auction posting: comparable listings, the suggestion and the posting checks
-- (auction/Price.lua), and the one-item search (auction/Scan.lua) against a
-- stand-in auction house.
local env = setmetatable({}, {__index = _G})
env._G = env
env.TwichUI = {}
local function Load(file)
  local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, env); chunk("!!!TwichUI", {})
end
Load("auction/Price.lua")
local P = env.TwichUI.AuctionPrice

-- Commodities: per unit; your own share doesn't count; ties add up.
local c = { { unitPrice = 1500, quantity = 10, numOwnerItems = 10 },   -- all yours
            { unitPrice = 1240, quantity = 40, numOwnerItems = 0 },
            { unitPrice = 1240, quantity = 25, numOwnerItems = 5 },
            { unitPrice = 1300, quantity = 5,  numOwnerItems = 0 } }
local s = P.SummariseCommodities(c)
assert(s.lowest == 1240 and s.lowestQuantity == 60, "lowest and its quantity")
assert(s.comparable == 3 and s.own == 1 and s.found == 4)
assert(c[1].status == "own" and c[2].status == "match")
local sg = P.Suggest(s, true)
assert(sg.price == 1240 and not sg.limited and not sg.rounded, "matches, never undercuts")
sg = P.Suggest(s, false)
assert(sg.price == 1300 and sg.rounded, "rounded up to whole silver")

-- An item listed only by you: nothing to compare with.
s = P.SummariseCommodities({ { unitPrice = 900, quantity = 3, numOwnerItems = 3 } })
assert(s.lowest == nil and P.Suggest(s, true) == nil)

-- Equipment: only the same item level and suffix compare; bid-only and your own are counted, not used.
local target = { matchVariant = true, itemLevel = 25, itemSuffix = 1040 }
local items = { { itemLevel = 25, itemSuffix = 1040, buyout = 50000, quantity = 1 },
                { itemLevel = 25, itemSuffix = 1041, buyout = 20000, quantity = 1 },  -- other suffix
                { itemLevel = 28, itemSuffix = 1040, buyout = 10000, quantity = 1 },  -- other level
                { itemLevel = 25, itemSuffix = 1040, buyout = nil, minBid = 100, quantity = 1 },
                { itemLevel = 25, itemSuffix = 1040, buyout = 30000, quantity = 1, own = true },
                { itemLevel = 25, itemSuffix = 1040, buyout = 45000, quantity = 1 } }
s = P.SummariseItems(items, target)
assert(s.lowest == 45000, "cheapest of the same variant, not the cheaper other variants: " .. tostring(s.lowest))
assert(s.comparable == 2 and s.otherVariant == 2 and s.bidOnly == 1 and s.own == 1)
assert(items[2].status == "variant" and items[4].status == "bid" and items[5].status == "own")
sg = P.Suggest(s, true)
assert(sg.price == 45000 and sg.limited, "two comparable listings is a thin basis")

-- Non-equipment items compare on the item alone.
s = P.SummariseItems({ { itemLevel = 1, buyout = 700, quantity = 5 }, { itemLevel = 9, buyout = 650, quantity = 2 } },
  { matchVariant = false })
assert(s.lowest == 650 and s.comparable == 2)

-- Posting checks.
local ok = { price = 1200, quantity = 5, maxQuantity = 20, copperAllowed = false, deposit = 300, money = 10000 }
assert(P.Check(ok) == nil)
local function With(k, v) local t = {} for a, b in pairs(ok) do t[a] = b end t[k] = v return t end
assert(P.Check(With("quantity", 0)) and P.Check(With("quantity", 21)))
assert(P.Check(With("price", 0)) and P.Check(With("price", P.MAX_PRICE + 100)))
assert(P.Check(With("price", 1250)), "copper refused where the auction house takes whole silver")
assert(P.Check(With("copperAllowed", true)) == nil and P.Check(With("price", 1250)) ~= nil)
local cp = With("price", 1250); cp.copperAllowed = true
assert(P.Check(cp) == nil, "copper fine where allowed")
assert(P.Check(With("money", 299)), "deposit must be affordable")

---------------------------------------------------------------------------
-- The search, against a stand-in auction house.
---------------------------------------------------------------------------
local frames = {}
env.CreateFrame = function()
  local fr = { events = {} }
  function fr:RegisterEvent(e) self.events[e] = true end
  function fr:UnregisterEvent(e) self.events[e] = nil end
  function fr:SetScript(_, fn) self.onEvent = fn end
  frames[#frames + 1] = fr
  return fr
end
local function Fire(e, ...)
  for _, fr in ipairs(frames) do if fr.events[e] and fr.onEvent then fr.onEvent(fr, e, ...) end end
end
local timers = {}
env.C_Timer = { After = function(d, fn) timers[#timers + 1] = { d = d, fn = fn } end }
local function RunTimers(upTo) local t = timers; timers = {} for _, e in ipairs(t) do if e.d <= upTo then e.fn() else timers[#timers + 1] = e end end end
env.GetTime = function() return 100 end
env.time = function() return 1790000000 end
env.Enum = { AuctionHouseSortOrder = { Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5 } }

local AH = { ready = true, sent = {}, more = 0, results = {}, full = false }
env.C_AuctionHouse = {
  IsThrottledMessageSystemReady = function() return AH.ready end,
  SendSearchQuery = function(key) AH.sent[#AH.sent + 1] = { "search", key } end,
  SendSellSearchQuery = function(key) AH.sent[#AH.sent + 1] = { "sell", key } end,
  GetNumCommoditySearchResults = function() return #AH.results end,
  GetCommoditySearchResultInfo = function(_, i) return AH.results[i] end,
  HasFullCommoditySearchResults = function() return AH.full end,
  RequestMoreCommoditySearchResults = function() AH.more = AH.more + 1; return AH.full end,
  GetNumItemSearchResults = function() return #AH.results end,
  GetItemSearchResultInfo = function(_, i) return AH.results[i] end,
  HasFullItemSearchResults = function() return AH.full end,
  RequestMoreItemSearchResults = function() AH.more = AH.more + 1; return AH.full end,
}
Load("auction/Scan.lua")
local SC = env.TwichUI.AuctionScan
local changes = 0
SC.OnChange = function() changes = changes + 1 end

-- Loading the file sends nothing.
assert(#AH.sent == 0 and SC.state == "idle")

-- A commodity: one query; results for some other item are ignored; the cap on extra pages holds.
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
assert(#AH.sent == 1 and AH.sent[1][1] == "search" and SC.state == "searching")
AH.results = { { unitPrice = 100, quantity = 20, numOwnerItems = 0 } }
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 9999)
assert(SC.state == "searching", "another item's results are not ours")
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(AH.more == 1 and SC.state == "more", "asks for one more page")
Fire("COMMODITY_SEARCH_RESULTS_ADDED", 2589)
assert(AH.more == 2)
Fire("COMMODITY_SEARCH_RESULTS_ADDED", 2589)
assert(AH.more == 2 and SC.state == "partial", "stops after two extra pages and says it's partial: " .. SC.state)
assert(#AH.sent == 1, "never re-sent")
assert(SC.summary.lowest == 100)
-- The search has finished, so later events do nothing.
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(SC.state == "partial" and AH.more == 2)

-- Full results on the first answer: done; none at all: none.
AH.sent, AH.more, AH.full = {}, 0, true
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(SC.state == "done" and AH.more == 0)
AH.results = {}
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(SC.state == "none")

-- Throttled: waits, sends once the client says it's ready, no tight retries.
AH.sent, AH.ready = {}, false
SC.Start({ kind = "item", itemID = 6097, isEquipment = true, matchVariant = true, itemLevel = 25, itemSuffix = 0,
  queryKey = { itemID = 6097, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } })
assert(SC.state == "waiting" and #AH.sent == 0)
RunTimers(60)
assert(#AH.sent == 0, "no timer-driven retry")
AH.ready = true
Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
assert(#AH.sent == 1 and AH.sent[1][1] == "sell", "equipment uses the sell search")
-- Item results: only the exact query key counts.
AH.results = { { itemKey = { itemID = 6097, itemLevel = 25, itemSuffix = 0 }, buyoutAmount = 5000, quantity = 1 } }
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6097, itemLevel = 25, itemSuffix = 0, battlePetSpeciesID = 0 })
assert(SC.state == "searching", "a different item key is not ours")
Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 6097, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })
assert(SC.state == "done" and SC.summary.lowest == 5000)

-- No answer: says so after the timeout, without re-sending.
AH.sent = {}
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
RunTimers(60)
assert(SC.state == "noResponse" and #AH.sent == 1)

-- Dropped by the server's limit right after sending.
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
Fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
assert(SC.state == "dropped")

-- Stop forgets everything and ignores a late answer.
SC.Start({ kind = "commodity", itemID = 2589, queryKey = { itemID = 2589 } })
SC.Stop()
AH.results = { { unitPrice = 1, quantity = 1, numOwnerItems = 0 } }
Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
assert(SC.state == "idle" and SC.listings == nil)

print("PASSED")
