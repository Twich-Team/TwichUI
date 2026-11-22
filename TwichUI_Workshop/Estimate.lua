-- TwichUI Workshop: the planning estimate of a craft (role "estimate", policy 1). Pure: every price, value, vendor and fee comes through the
-- functions of a context the caller builds (Session.Opportunities), so this file calls no game function and reads no saved data itself.
-- docs/workshop/pricing-realism-proposal.md, section 5. It replaces Prices.Estimate for Opportunities, the Overview and the queue estimate;
-- Prices.Estimate stays unchanged for its own callers and tests.
--
-- WHAT IT ADDS TO Prices.Estimate (whose fields it keeps, so every reader of an estimate still works):
--   * Materials: the vendor (Vendor.Quote, whole stacks) against the auction house, the cheaper one (a tie to the vendor); the auction cost walks
--     the listings for the quantity needed (Market.Cost with fromCompeting: far-below "bait" tiers left out, R2), else the old unit quote. When the
--     snapshot is older than STALE_BUY, the unit is at least the item's Market Value (R3), labelled "typical".
--   * The product: the competing price (Market.Competition), capped at CAP_PERCENT of Market Value (R1); with no competition, Market Value, then
--     Historical Value. A Companion reference gives its Recent Price, capped the same way by its Market Value. An old scan without price tiers
--     gives the lowest listing, labelled. A vendor sell value at least as high as what the auction house would leave after its cut makes the
--     outlet "vendor": a craft is never valued below what a merchant pays for it.
--   * Fees: the cut (Fees.Cut: assumed or matching the Ledger) and the deposit (Fees.Deposit: the player's own postings only), with how many
--     failed listings the profit covers. The deposit is a risk (a sale refunds it), so it is never subtracted.
--   * Confidence: High / Medium / Low from Data Quality and liquidity, with plain reasons; it never changes a number.
--   * Typical profit: the same craft at Market Values (and vendor prices), as a second figure; never sorted on.
-- Every amount is whole copper; an unknown is nil, never 0.
local R = TwichUI
local W = R.Workshop
local PR, V = W.Prices, W.Vendor
local Int = W.Int
local E = { POLICY = 1 }
W.Estimate = E

E.CAP_PERCENT = 115          -- the sell price is at most this percent of Market Value (Posture's approved "expensive" line, D8)
E.STALE_BUY = 86400          -- a material's snapshot older than this is not trusted below its Market Value (R3)
E.ABSORB_PERCENT = 50        -- selling more than this percent of the items listed now, or of the usual 14-day supply (R6), when selling 2 or more
E.THIN_LISTINGS = 3
E.RARE_DAYS = 7
E.UNDERCUT = 0               -- copper under the sell price (R5: match)
E.LEVEL = { good = 3, fair = 2, limited = 1, none = 1 }
E.WORDS = { [3] = "high", [2] = "medium", [1] = "low" }

local floor = math.floor

local function Ceil(x) return math.ceil(x - 1e-9) end
local function Num(x) return type(x) == "number" and x == x and x > -math.huge and x < math.huge and x or nil end

---------------------------------------------------------------------------
-- The estimator: one context, one memo per (question, item, quantity), so an item shared by many recipes is asked about once per draw
---------------------------------------------------------------------------
local Est = {}
Est.__index = Est

function E.New(ctx)
    return setmetatable({ ctx = ctx or {}, memo = {}, itemVersions = {}, asked = 0, hits = 0, size = 0 }, Est)
end

function Est:Work()
    if self.worker and self.worker==coroutine.running() and self.work then self.work()end
end
function Est:ClearMemo()self.memo={};self.itemVersions={};self.size=0 end
function Est:InvalidateItem(item)
    if self.itemVersions[item]~=nil then self.itemVersions[item]=self.itemVersions[item]+1 end
end

function Est:Ask(kind, item, extra)
    local fn = self.ctx[kind]
    if type(fn) ~= "function" then self:Work();return nil end
    local key = kind .. ":" .. tostring(item) .. ":" .. tostring(extra or "")
    local version=self.itemVersions[item]or 0
    local hit = self.memo[key]
    if hit ~= nil and hit[3]==version then self.hits = self.hits + 1;self:Work();return hit[1], hit[2] end
    self.asked = self.asked + 1
    local ok, a, b
    if R.Perf and R.Perf.on then ok,a,b=pcall(R.Perf.Call,'workshop.opportunityQuestion',fn,item,extra)
    else ok,a,b=pcall(fn,item,extra)end
    if not ok then a, b = nil, "error" end
    -- an answer still loading (an item's information, a Market partition) is asked again next time
    if b ~= "loading" and b~='combat' then
        if self.memo[key]==nil then self.size=self.size+1 end
        self.memo[key] = { a, b, version };if item~=nil then self.itemVersions[item]=version end
    end
    self:Work()
    return a, b
end

function Est:Now() return Int(self.ctx.now, 1, 4102444800) or (time and time()) or 0 end

-- The item's usual value: the local Market Value, else the reference's. { value, source = "local" | "market_server" } or nil
function Est:Usual(item, kind)
    local v = self:Ask("value", item, kind)
    if type(v) == "table" and Int(v.value, 1, PR.MAX_COPPER) then return { value = v.value, source = "local" } end
    local ref = self:Ask("reference", item)
    local x = type(ref) == "table" and (kind == "historical" and ref.historical or ref.market) or nil
    if Int(x, 1, PR.MAX_COPPER) then return { value = x, source = "market_server" } end
    return nil
end

function Est:QualityLevel(item)
    local q = self:Ask("quality", item)
    return type(q) == "table" and q.level or nil, q
end

---------------------------------------------------------------------------
-- Buying one material
---------------------------------------------------------------------------
-- The auction house's cost of `need`: { low, high (nil = open), unit, state, at, complete, reference, quality, skipped, cheapest, typical }
-- or { state = "few" | "none" }
function Est:Auction(item, need)
    local c = self:Ask("cost", item, need)
    local a
    if type(c) == "table" and (c.state == "exact" or c.state == "range" or c.state == "estimate") then
        local low = Num(c.cost or c.low)
        if low then
            a = { state = c.state, low = low, high = c.state ~= "estimate" and Num(c.high) or nil, unit = Ceil(low / need), at = c.at,
                complete = c.complete, quality = c.quality, skipped = c.skipped }
        end
    elseif type(c) == "table" and c.state == "few" then
        return { state = "few", available = c.available }
    end
    if not a then
        local p = self:Ask("price", item)
        if type(p) ~= "table" or not p.price then return { state = "none" } end
        local q = PR.Quote(p, need)
        if q.state == "few" or q.state == "none" or not q.cost then return { state = q.state == "few" and "few" or "none" } end
        a = { state = q.state, low = q.cost, high = q.state == "exact" and q.cost or nil, unit = p.price, at = p.at, complete = p.complete,
            reference = p.reference, source = p.source, generation = p.generation, cheapest = p.qty ~= nil and need > p.qty or nil,
            quality = p.reference and "limited" or nil }
    end
    if not a.quality then a.quality = self:QualityLevel(item) end
    -- freshness (R3): a snapshot older than STALE_BUY is never trusted below the item's usual value (a fresh scan's listings are walked as
    -- they are; thin data lowers the confidence instead)
    local now = self:Now()
    local age = Num(a.at) and now - a.at or nil
    if age and age > E.STALE_BUY then
        local mv = self:Usual(item, "market")
        if mv and mv.value * need > a.low then
            a.typical, a.listedLow = mv.source, a.low
            a.low = mv.value * need
            a.unit = mv.value
            if a.high and a.high < a.low then a.high = a.low end
        end
    end
    return a
end

-- One material row: { item, qty, source = "vendor" | "auction", unit, total (low), high, at, complete, reference, typical, skipped,
-- cheapest, quality, unavailable ("few" | "none"), vendorState }
function Est:Material(item, need)
    local row = { item = item, qty = need }
    local vq
    local ve = self:Ask("vendor", item)
    if type(ve) == "table" then
        local q = V.Quote(ve, need)
        row.vendorState = q and q.state
        if q and q.state == "ok" and Num(q.cost) then vq = q end
    end
    local a = self:Auction(item, need)
    local auctionOk = a and a.low ~= nil
    if vq and (not auctionOk or vq.cost <= a.low) then
        row.source, row.unit, row.total, row.high, row.at, row.complete = "vendor", Ceil(vq.cost / need), vq.cost, vq.cost, vq.at, true
        row.quality, row.surplus = "good", vq.surplus
        if auctionOk then row.auctionLow = a.low end
        return row
    end
    if auctionOk then
        row.source, row.unit, row.total, row.high, row.at, row.complete = "auction", a.unit, a.low, a.high, a.at, a.complete
        row.reference, row.typical, row.skipped, row.cheapest, row.quality, row.state = a.reference, a.typical, a.skipped, a.cheapest, a.quality, a.state
        row.listedLow, row.source2, row.generation = a.listedLow, a.source, a.generation
        if vq then row.vendorCost = vq.cost end
        return row
    end
    row.unavailable = (a and a.state == "few") and "few" or "none"
    return row
end

---------------------------------------------------------------------------
-- Selling the product
---------------------------------------------------------------------------
-- The gross unit price and where it comes from: unit, basis ("competing" | "reference" | "lowest" | "market" | "historical"), capped, cap, bait,
-- comp (the competition answer, for absorption), usual (Market Value). Or nil.
function Est:SellUnit(item)
    local s = {}
    local p = self:Ask("price", item)
    local comp = self:Ask("competition", item)
    if type(comp) ~= "table" then comp = nil end
    s.comp = comp
    if type(p) == "table" and p.reference and Int(p.price, 1, PR.MAX_COPPER) then
        s.unit, s.basis, s.at, s.complete = p.price, "reference", p.at, p.complete
    elseif comp and Int(comp.competing, 1, PR.MAX_COPPER) then
        s.unit, s.basis, s.at, s.complete = comp.competing, "competing", comp.at, comp.complete
        if comp.below and comp.below.items > 0 then s.bait = { items = comp.below.items, price = comp.cheapest } end
    elseif not comp and type(p) == "table" and Int(p.price, 1, PR.MAX_COPPER) then
        -- no price tiers for this scan (an older scan, or a market without a distribution): the lowest listing, labelled
        s.unit, s.basis, s.at, s.complete = p.price, "lowest", p.at, p.complete
    end
    local mv = self:Usual(item, "market")
    s.usual = mv
    if s.unit and mv then
        local cap = Ceil(mv.value * E.CAP_PERCENT / 100)
        if s.unit > cap then s.listed, s.unit, s.capped, s.cap = s.unit, cap, true, cap end
    end
    if not s.unit then
        if mv then s.unit, s.basis = mv.value, "market"
        else
            local hv = self:Usual(item, "historical")
            if hv then s.unit, s.basis = hv.value, "historical" end
        end
    end
    if s.unit and E.UNDERCUT > 0 and s.unit > E.UNDERCUT then s.unit = s.unit - E.UNDERCUT end
    return s
end

function Est:VendorSell(item)
    local v, why = self:Ask("vendorSell", item)
    v = Int(v, 0, PR.MAX_COPPER)
    if v and v > 0 then return v end
    return nil, why
end

---------------------------------------------------------------------------
-- Confidence
---------------------------------------------------------------------------
local REASON = {
    thin = "Few listings of what it makes.",
    rare = "What it makes is listed on few days.",
    capped = "Listed above its usual price; counted at 115% of its Market Value.",
    usual = "Nothing comparable is listed now; its usual value is used.",
    lowest = "This scan has no price spread; the lowest listing is used.",
    absorb = "Selling %d against about %d listed.",
    reference = "Market server estimates: current listings may differ.",
    depth = "How many are listed at a material's price isn't known.",
    stale = "A material's prices are old or thin; its usual value is used.",
    material = "A material's market data is limited.",
}
E.REASON = REASON

local function Down(st, code, text)
    st.level = st.level > 1 and st.level - 1 or 1
    if text then st.reasons[#st.reasons + 1] = { code = code, text = text } end
end

---------------------------------------------------------------------------
-- One craft (or `crafts` crafts)
---------------------------------------------------------------------------
-- rec: { outItem, outMin, outMax, mats = { { item, qty } }, cd = { left, at, charges, max } (optional) }. Returns e: Prices.Estimate's fields
-- (state, why, missing, mats, cost, outMin, outMax, unit, sellLow, sellHigh, netLow, netHigh, profitLow, profitHigh, oldest, incomplete,
-- cheapest, cutRate, reference) plus: role, policy, crafts, costHigh (nil = open), outlet ("auction" | "vendor"), sellBasis, capped, listed (the
-- listing before the cap), bait, cut (Fees.Cut's answer), cutLow, cutHigh, vendorSell, deposit (Fees.Deposit's answer), covers, confidence
-- ("high" | "medium" | "low"), reasons ({ code, text }), typical ({ cost, net, profit } or nil), nowOnly, usually, margin (profit / cost, a
-- float), cooldown ({ left } while a cooldown runs).
function Est:Craft(rec, crafts)
    crafts = Int(crafts, 1, W.MAX_ID) or 1
    local ctx = self.ctx
    local cut = ctx.cut
    local e = { role = "estimate", policy = E.POLICY, state = "unknown", mats = {}, missing = 0, crafts = crafts, cut = cut,
        cutRate = cut and cut.rate or nil, cutWhy = not cut and ctx.cutWhy or nil }
    local oldest, incomplete, cheapest = nil, false, false
    local function Seen(at, complete)
        if Num(at) and (not oldest or at < oldest) then oldest = at end
        if complete ~= true then incomplete = true end
    end
    local st = { level = 3, reasons = {} }

    local outItem = Int(rec.outItem, 1, W.MAX_ID)
    local lo, hi = Int(rec.outMin, 1, W.MAX_QTY), Int(rec.outMax, 1, W.MAX_QTY)
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
    if lo and hi < lo then lo, hi = nil, nil end
    e.outMin, e.outMax = lo, hi

    -- materials
    local hasMats = type(rec.mats) == "table" and #rec.mats > 0
    local cost, costHigh, open = 0, 0, false
    local matWorst = 3
    if hasMats then
        for _, m in ipairs(rec.mats) do
            local qty = Int(m.qty, 1, W.MAX_QTY)
            local need = qty and qty * crafts or nil
            local row = need and self:Material(m.item, need) or { item = m.item, qty = m.qty, unavailable = "none" }
            row.perCraft = qty
            e.mats[#e.mats + 1] = row
            if row.total then
                cost = cost + row.total
                if row.high then costHigh = costHigh + row.high else open = true end
                if row.source == "auction" then
                    Seen(row.at, row.complete)
                    if row.reference then e.reference = true end
                    if row.cheapest then cheapest = true end
                    local lv = E.LEVEL[row.quality or "limited"] or 1
                    if row.reference then lv = 1 end
                    if lv < matWorst then matWorst = lv end
                    if row.typical then e.typicalMaterial = true end
                    if row.state == "estimate" and not row.high then e.depthUnknown = e.depthUnknown or (row.reference == true) end
                end
            else
                e.missing = e.missing + 1
            end
        end
        if e.missing == 0 then
            e.cost = cost
            e.costHigh = not open and costHigh or nil
        end
    end

    -- the product
    local sellMissing = false
    if outItem and lo then
        local s = self:SellUnit(outItem)
        local vs, vsWhy = self:VendorSell(outItem)
        e.vendorSell, e.vendorSellWhy = vs, vsWhy
        local outLo, outHi = lo * crafts, hi * crafts
        e.outLow, e.outHigh = outLo, outHi
        local netLo, netHi
        if s.unit then
            e.unit, e.sellBasis, e.capped, e.listed, e.cap, e.bait, e.usual = s.unit, s.basis, s.capped, s.listed, s.cap, s.bait, s.usual and s.usual.value
            e.sellLow, e.sellHigh = s.unit * outLo, s.unit * outHi
            e.cutLow, e.cutHigh = W.Fees and W.Fees.CutOf(e.sellLow, cut) or 0, W.Fees and W.Fees.CutOf(e.sellHigh, cut) or 0
            netLo, netHi = e.sellLow - e.cutLow, e.sellHigh - e.cutHigh
            if s.basis == "reference" then e.reference = true end
            if s.at then Seen(s.at, s.complete) end
        end
        e.outlet = "auction"
        -- the vendor floor: a merchant's price at least what the auction house would leave makes the outlet the vendor (certain, no fees)
        if vs and (not netLo or vs * outLo >= netLo) then
            e.outlet = "vendor"
            e.auctionNetLow = netLo
            e.unit = vs
            e.sellLow, e.sellHigh = vs * outLo, vs * outHi
            e.cutLow, e.cutHigh = 0, 0
            netLo, netHi = e.sellLow, e.sellHigh
        end
        if netLo then
            e.netLow, e.netHigh = netLo, netHi
        else
            sellMissing = true
        end

        -- confidence of the selling side
        if e.outlet == "auction" and netLo then
            local lvName, q = self:QualityLevel(outItem)
            local lv = E.LEVEL[lvName or "limited"] or 1
            if s.basis == "reference" then lv = 1 end
            st.level = lv
            if q and q.reasons then
                for _, r in ipairs(q.reasons) do st.reasons[#st.reasons + 1] = { code = r.code, text = r.text } end
            end
            local f = q and q.facts or {}
            local said = {}
            for _, r in ipairs(st.reasons) do said[r.code] = true end
            if s.basis == "competing" or s.basis == "lowest" then
                -- liquidity lowers confidence once more; Quality's own reason already says why ("Only 2 listings.")
                if (f.listings or 0) < E.THIN_LISTINGS then Down(st, "thin", not said.listings and REASON.thin or nil)
                elseif (f.observedDays or 0) < E.RARE_DAYS then Down(st, "rare", not said.days and REASON.rare or nil) end
            end
            if s.capped then Down(st, "capped", REASON.capped) end
            if s.basis == "market" or s.basis == "historical" then Down(st, "usual", REASON.usual) end
            if s.basis == "lowest" then Down(st, "lowest", REASON.lowest) end
            if s.basis == "reference" then st.reasons[#st.reasons + 1] = { code = "reference", text = REASON.reference } end
            -- absorption (R6): only when selling 2 or more (the usual supply is asked for only then: it reads the item's history)
            local against
            if outLo > 1 then
                local listed = s.comp and s.comp.total and s.comp.total.items or nil
                local supply
                if not listed then supply = self:Ask("supply", outItem) listed = type(supply) == "table" and supply.items or nil end
                if listed and outLo * 100 > listed * E.ABSORB_PERCENT then against = listed end
                if not against then
                    supply = supply or self:Ask("supply", outItem)
                    local typicalSupply = type(supply) == "table" and supply.history and supply.history.median or nil
                    if typicalSupply and outLo * 100 > typicalSupply * E.ABSORB_PERCENT then against = typicalSupply end
                end
            end
            if against then e.absorb = { selling = outLo, against = against } Down(st, "absorb", REASON.absorb:format(outLo, against)) end
        elseif e.outlet == "vendor" then
            st.level = 3
        end

        -- the product at its usual value, for the typical profit
        local mv = s.usual
        if mv then
            local gross = mv.value * outLo
            local net = gross - (W.Fees and W.Fees.CutOf(gross, cut) or 0)
            if vs and vs * outLo > net then net = vs * outLo end
            e.typicalNet = net
        elseif vs then
            e.typicalNet = vs * outLo
        end
    end

    -- materials lower confidence after the product's own level
    if matWorst < st.level then
        st.level = matWorst
        st.reasons[#st.reasons + 1] = { code = "material", text = REASON.material }
    end
    if e.typicalMaterial then st.reasons[#st.reasons + 1] = { code = "stale", text = REASON.stale } end
    if e.depthUnknown then Down(st, "depth", REASON.depth) end

    if not hasMats then e.why = "nomats"
    elseif not outItem then e.why = "noitem"
    elseif not lo then e.why = "noamount"
    elseif e.missing > 0 then e.why = "matprice"
    elseif sellMissing then e.why = "sellprice" end

    if e.cost and e.netLow then
        e.state = "ok"
        e.why = nil
        e.profitLow, e.profitHigh = e.netLow - e.cost, e.netHigh - e.cost
        e.margin = e.cost > 0 and e.profitLow / e.cost or nil
        e.confidence = E.WORDS[st.level]
        e.reasons = st.reasons
        -- the deposit at risk: posting one craft's output (outMin items, crafts times) as listings of one craft's output each
        if e.outlet == "auction" and W.Fees and ctx.deposit then
            local d = self:Ask("deposit", outItem, lo)
            if type(d) == "table" and Int(d.amount, 1, PR.MAX_COPPER) then
                e.deposit = d
                e.depositTotal = d.amount * crafts
                e.covers = W.Fees.Covers(e.profitLow, e.depositTotal)
            end
        end
        -- the typical profit is worked out when it is shown (E.Typical): it asks for every material's Market Value
        e._est, e._rec = self, rec
    end
    -- the cooldown read with the recipe (memory only): still running now?
    local cd = type(rec.cd) == "table" and rec.cd or nil
    if cd and Num(cd.left) and Num(cd.at) then
        local left = cd.left - (self:Now() - cd.at)
        if left > 0 and not (Int(cd.charges, 1, 1000)) then e.cooldown = { left = left } end
    end
    e.oldest, e.incomplete, e.cheapest = oldest, incomplete, cheapest
    return e
end

-- The estimator's work so far (diagnostics: questions asked and answered from the memo, answers kept)
function Est:Stats() return { asked = self.asked, hits = self.hits, size = self.size } end

-- The typical profit of an estimate, worked out once when a tooltip or the details show it: every auction material at its usual Market Value
-- (a vendor's price stays the vendor's) against the product at its usual value after the cut (or a merchant's price when that is more).
-- Sets and returns e.typical = { cost, net, profit } and the flags nowOnly / usually, or nil when a usual value is missing.
function E.Typical(e)
    if type(e) ~= "table" or e.state ~= "ok" then return nil end
    if e.typicalDone then return e.typical end
    e.typicalDone = true
    local self, rec = e._est, e._rec
    if not (self and rec and e.typicalNet) then return nil end
    local cost = 0
    for i, row in ipairs(e.mats) do
        if row.source == "vendor" then
            cost = cost + row.total
        else
            local m = rec.mats[i]
            local mv = m and self:Usual(m.item, "market")
            if not mv then return nil end
            cost = cost + mv.value * row.qty
        end
    end
    e.typical = { cost = cost, net = e.typicalNet, profit = e.typicalNet - cost }
    if e.profitLow > 0 and e.typical.profit < 0 then e.nowOnly = true end
    if e.profitLow < 0 and e.typical.profit > 0 then e.usually = true end
    return e.typical
end

---------------------------------------------------------------------------
-- What an item is worth at the auction house, for the "what's it worth" readers (the tooltip, the Disenchant estimate)
---------------------------------------------------------------------------
E.COMPETING_BASIS = "The lowest competing listing per item in the newest scan (listings far below the rest left out). A listing, not a sale."
-- A local Market.Price answer valued at the competing price (Market.Competition: the cheapest listing not far below the rest) instead of the
-- lowest listing, so one dumped listing doesn't set an item's worth; the Item Advisor already uses the same figure. A reference, a variant,
-- or an item without a competing price keeps the quote as it is. Returns a new table when it changes anything (never the input).
function E.AtCompeting(quote, item, opt)
    local MKT = W.Market
    if type(quote) ~= "table" or quote.reference or not (MKT and MKT.Competition) or (opt and opt.variant) then return quote end
    local m = opt and opt.market
    if type(m) == "table" and m.pricing then m = m.localMarket end
    local ok, c = pcall(MKT.Competition, item, nil, { market = m, now = opt and opt.now })
    if not ok or type(c) ~= "table" or not Int(c.competing, 1, PR.MAX_COPPER) or c.competing == quote.price then return quote end
    local q = {}
    for k, v in pairs(quote) do q[k] = v end
    q.lowest, q.price, q.competing, q.basis = quote.price, c.competing, true, E.COMPETING_BASIS
    return q
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
E.BASIS_WORDS = {
    competing = "the lowest competing listing",
    reference = "the Market server's Recent Price",
    lowest = "the lowest listing (no price spread saved)",
    market = "its Market Value (nothing comparable listed)",
    historical = "its Historical Value (nothing comparable listed)",
}
function E.ConfidenceWord(c)
    return c == "high" and "High" or (c == "medium" and "Medium" or (c == "low" and "Low" or nil))
end
