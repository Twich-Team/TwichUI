-- V5 posting provenance (auction/LedgerCost.lua) through the real auction action controller, Ledger and cost basis, on the existing
-- synthetic Auction House adapter. No real game operation. What is proven: the exact identity, quantity, price and deposit of a
-- TwichUI posting the game created, the cost of the posted units under the identified-stock rule, and its later state by native
-- auction id. What is never done: tying a collected seller invoice to a posting (the invoice has no auction id or item id).
local failures = 0
local function Check(v, m) if not v then failures = failures + 1; print("FAIL: " .. tostring(m)) end end
local function Same(a, b, m) Check(a == b, (m or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end

local KEY = "i10"
local function Setup(db)
    local c, W, s = dofile(TESTS .. "auction_debug_mock.lua")
    local R = c.TwichUI
    c.TwichUIDB.ui.workshopEnabled = true
    c.UnitName = function() return "Rich" end
    c.NOW_T = 20000 * 86400 + 43200
    c.GetServerTime = function() return c.NOW_T end
    if db then c.TwichUILedgerDB = db end
    s.now = 100
    local timers = {}
    c.C_Timer = { NewTimer = function(d, fn)
        local t = { at = s.now + d, fn = fn }; function t:Cancel() self.cancelled = true end
        timers[#timers + 1] = t; return t
    end }
    c.C_Timer.After = function(d, fn) c.C_Timer.NewTimer(d, fn) end
    function s.Advance(d)
        local target = s.now + d
        for _ = 1, 1000 do
            local index
            for i, t in ipairs(timers) do if t.at <= target and (not index or t.at < timers[index].at) then index = i end end
            if not index then s.now = target; return end
            local t = table.remove(timers, index); s.now = math.max(s.now, t.at)
            if not t.cancelled then t.fn() end
        end
        error("unbounded timers")
    end
    for _, name in ipairs({ "auction/Ledger.lua", "auction/LedgerAuction.lua", "auction/LedgerCost.lua", "auction/LedgerCostWatch.lua" }) do
        local f = assert(loadfile(ROOT .. name)); setfenv(f, c); f()
    end
    local L, C = R.Ledger, R.LedgerCost
    L.Init(); L.Refresh(); C.Init(); C.Refresh(); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    function s.Post(mode, qty)
        R.AuctionBuild.verified[mode] = true; s.commodity = mode == "postCommodity"
        local id, why = W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1], qty, 100, 1)
        Check(id, "post review (" .. tostring(why) .. ", line " .. debug.getinfo(2, "l").currentline .. ")"); Check(W.AuctionActions.Confirm(id), "post sent"); return id
    end
    function s.Rec() return C.Rec("Rich - Forever", true) end
    function s.Lot(q, cost) local rec = s.Rec(); rec.lots[#rec.lots + 1] = { id = rec.nextLot, t = c.NOW_T, k = KEY, i = 10, q = q, r = q, c = cost, s = "vendor" }; rec.nextLot = rec.nextLot + 1 end
    function s.Posts() return s.Rec().posts or {} end
    return c, W, s, L, C
end

---------------------------------------------------------------------------
-- A successful posting from identified stock: identity, price, deposit, auction id and the posted units' cost
---------------------------------------------------------------------------
do
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    s.Post("postCommodity", 5)
    Same(#s.Posts(), 0, "intent alone keeps nothing")
    s.qty = 15                                      -- the five posted units left the bags
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 501)
    local post = s.Posts()[1]
    Check(post, "the created auction is remembered")
    if post then
        Same(post.k, KEY, "exact identity"); Same(post.q, 5, "quantity"); Same(post.u, 100, "unit price"); Same(post.a, 501, "native auction id")
        Same(post.st, "posted", "state"); Same(post.cs, "ok", "cost verified"); Same(post.c, 500, "exact copper share of the lot (2000 * 5 / 20)")
        Same(#post.al, 1, "one allocation")
    end
    Same(C.Pool(s.Rec(), KEY), 15, "the pool still equals the carried units")
    local chars = c.TwichUILedgerDB.chars or {}
    Same(chars["Rich - Forever"] and #chars["Rich - Forever"].entries or 0, 0, "a posting records no cash by itself")
    -- duplicate creation event: the action is finished, nothing more is kept
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 501)
    Same(#s.Posts(), 1, "a repeated creation event keeps one posting")
    Same(C.Posted({ char = "Rich - Forever", key = KEY, item = 10, qty = 5, before = 15 }, { 501 }), nil, "the same auction id is never posted twice")
    -- a second identical posting: its own record and its own cost
    s.Post("postCommodity", 5); s.qty = 10
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 502)
    Same(#s.Posts(), 2, "multiple identical auctions are separate postings")
    Same(s.Posts()[2].c, 500, "each with its own cost"); Same(C.Pool(s.Rec(), KEY), 10, "no lot unit consumed twice")
    -- state by native auction id only
    c.FireEvent("AUCTION_CANCELED", 502)
    Same(s.Posts()[2].st, "cancelled", "a cancellation of the posting's own id")
    c.FireEvent("AUCTION_CANCELED", 999)
    Same(s.Posts()[1].st, "posted", "another auction's cancellation changes nothing")
    C.Owned({ { auctionID = 501, status = 1 } }, false)
    Same(s.Posts()[1].st, "sold", "sold by its native id (not yet collected: no cash, no result)")
    Same(#s.Rec().results, 0, "a sold auction is no result before its money is collected")
    -- the seller invoice for it is collected: the sale result stays cost-unavailable (no proven link), and no lot is consumed
    local before = C.Pool(s.Rec(), KEY)
    s.money = s.money + 47500; c.FireEvent("PLAYER_MONEY")
    L.Evidence({ kind = "ahSale", amount = 47500, note = "Item 10", qty = 5,
        settlement = { v = 1, invoices = { { g = 50000, d = 0, f = 2500, c = 47500, n = "Item 10", q = 5 } } } })
    local result = s.Rec().results[#s.Rec().results]
    Check(result and result.src == "ahSale" and result.st == "unknown" and result.w == "auctionid", "sale result: cost basis unavailable")
    Same(C.Pool(s.Rec(), KEY), before, "a sale never takes cost from a posting or a lot")
    Same(s.Posts()[1].st, "sold", "and never changes the posting")
end

---------------------------------------------------------------------------
-- Refusals and unknown cost
---------------------------------------------------------------------------
do
    local c, W, s, L, C = Setup()
    s.qty = 20;s.Lot(20, 2000);s.Post("postCommodity", 5);s.qty = 15
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", nil)
    Same(#s.Posts(), 0, "missing native id cannot confirm a commodity posting")
    Same(C.Pool(s.Rec(), KEY), 20, "missing native id consumes no cost")
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 502)
    Same(#s.Posts(), 1, "the later valid native confirmation still completes once")
    Same(s.Posts()[1].a, 502, "the actual native id is retained")
end

do
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    s.Post("postItem", 1); W.AuctionActions.Event("AUCTION_HOUSE_POST_ERROR")
    Same(#s.Posts(), 0, "a failed posting keeps nothing"); Same(C.Pool(s.Rec(), KEY), 20, "and takes no cost")
end
do
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    c.TwichUI.AuctionBuild.verified.postItem = true
    local id = W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1], 1, 100, 1)
    Check(id, "review prepared"); W.AuctionActions.Cancel()
    Same(#s.Posts(), 0, "a dismissed review keeps nothing"); Same(C.Pool(s.Rec(), KEY), 20, "and takes no cost")
end
do
    -- unknown-cost units among the carried stock: the posted units' cost is unknown and the pool is forgotten
    local c, W, s, L, C = Setup()
    s.qty = 25; s.Lot(20, 2000)
    s.Post("postCommodity", 5); s.qty = 20
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 601)
    local post = s.Posts()[1]
    Check(post and post.cs == "mixed" and post.c == nil, "mixed stock: cost unavailable, never guessed")
    Same(C.Pool(s.Rec(), KEY), 0, "and the pool is forgotten")
end
do
    -- the bags did not lose exactly the posted units (something else moved): cost unavailable
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    s.Post("postCommodity", 5); s.qty = 12
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 701)
    Same(s.Posts()[1].cs, "nostock", "unexpected bag change"); Same(s.Posts()[1].c, nil, "no cost")
end
do
    -- identified units whose own cost is unknown (a craft with an unknown material): the posting's cost is unknown, never zero
    local c, W, s, L, C = Setup()
    s.qty = 4; s.Lot(4, nil)
    s.Post("postCommodity", 2); s.qty = 2
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 751)
    Same(s.Posts()[1].cs, "unknown", "lot of unknown cost"); Same(s.Posts()[1].c, nil, "no cost, never zero")
    Same(C.Pool(s.Rec(), KEY), 2, "the identified units still leave the pool")
end
do
    -- stock with no verified acquisition at all
    local c, W, s, L, C = Setup()
    s.qty = 7
    s.Post("postCommodity", 3); s.qty = 4
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 801)
    Same(s.Posts()[1].cs, "nolot", "unknown-cost inventory stays unknown")
end
do
    -- a multi-post confirmed as complete: kept with the auction ids seen (none here: missing identity), never ended by a list
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    s.Post("postItem", 3); s.qty = 17
    W.AuctionActions.Event("AUCTION_MULTISELL_UPDATE", 3, 3)
    local post = s.Posts()[1]
    Check(post and post.a == nil and #post.ac == 0 and post.cs == "ok" and post.c == 300, "multi-post without ids: kept, cost verified")
    C.Owned({}, true)
    Same(post.st, "posted", "a posting with no id is never judged by a list")
end

---------------------------------------------------------------------------
-- Owned lists, persistence and bounds
---------------------------------------------------------------------------
do
    local c, W, s, L, C = Setup()
    s.qty = 20; s.Lot(20, 2000)
    for i = 1, 2 do s.Post("postCommodity", 1); s.qty = s.qty - 1; W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 900 + i) end
    C.Owned({ { auctionID = 901, status = 0 } }, false)
    Same(s.Posts()[2].st, "posted", "an incomplete list never ends a posting")
    C.Owned({ { auctionID = 901, status = 0 } }, true)
    Same(s.Posts()[2].st, "ended", "missing from a complete list: ended (expired, or sold and paid)")
    Same(s.Posts()[1].st, "posted", "still listed: still posted")
    -- reload: the record survives a text round trip, cleaned; a damaged posting is dropped narrowly
    local serializer, codec = c.LibStub("LibSerialize"), c.LibStub("LibDeflate")
    local db = c.TwichUILedgerDB
    db.cost.chars["Rich - Forever"].posts[3] = { id = "x", k = 7 }
    local text = codec:EncodeForPrint(serializer:Serialize(db))
    local ok, saved = serializer:Deserialize(codec:DecodeForPrint(text)); Check(ok, "round trip")
    local c2, W2, s2, L2, C2 = Setup(saved)
    local posts = s2.Posts()
    Same(#posts, 2, "two postings back after reload, the damaged one dropped")
    Same(posts[1].a, 901, "ids kept"); Same(posts[2].st, "ended", "states kept"); Same(posts[1].c, 100, "costs kept")
    -- bounds and age
    local rec = s2.Rec()
    for i = 1, C2.MAX_POSTS + 5 do rec.posts[#rec.posts + 1] = { id = 1000 + i, t = c2.NOW_T, k = KEY, i = 10, q = 1, st = "posted", cs = "nolot", al = {}, ac = { 5000 + i } } end
    c2.NOW_T = c2.NOW_T + 36 * 86400
    C2.Posted({ char = "Rich - Forever", key = KEY, item = 10, qty = 1 }, { 9999 })
    Check(#rec.posts <= C2.MAX_POSTS, "postings are bounded: " .. #rec.posts)
end

if failures > 0 then print(failures .. " failures") os.exit(1) end
print("PASSED test_ledger_lineage")
