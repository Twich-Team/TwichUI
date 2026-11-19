-- Pure M1a shadow arithmetic. Intentionally absent from every TOC: no defaults,
-- saved writes, timers, imports, auction requests or Advisor/Sell integration.
local W = TwichUI.Workshop
local P = { ALGORITHM = "twichui-pricing-v1", HISTORY_BASIS = "canonical_complete_scope_close" }
W.PricingV1 = P
-- Capability check only: never accepts a payload, checks a hash, or imports data.
function P.SupportsHeader(h)
    if type(h) ~= "table" or h.format ~= "twichui-market-bridge" or h.contract_version ~= 1 or h.schema_version ~= 1 or h.transport_version ~= 1 or h.quality_policy ~= 1 then return false end
    local basis = h.pricing_algorithm == P.ALGORITHM and P.HISTORY_BASIS or (h.pricing_algorithm == "asking-v1-provisional" and "market_rolling_daily_means")
    if not basis or h.history_basis ~= basis or type(h.required_features) ~= "table" or #h.required_features ~= 3 then return false end
    local expected = { exact_copper = true, current_summaries = true, daily_history = true }
    for _, f in ipairs(h.required_features) do if not expected[f] then return false end expected[f] = nil end
    return next(expected) == nil
end
local MAX, SAFE = 99999999999, 9007199254740991
local floor = math.floor
local function Int(v, lo, hi) return W.Int(v, lo, hi) end
local function N(v) return ("%.0f"):format(v) end
local function Key(item, variant)
    return Int(item, 1, 2147483647) and type(variant) == "string" and #variant == 64 and not variant:find("[^0-9a-f]")
end
local function Copper(s, limit, maximum)
    if type(s) ~= "string" or not s:match("^%d+$") or (#s > 1 and s:sub(1, 1) == "0") then return nil, "copper" end
    if #s > #limit or (#s == #limit and s > limit) then return nil, "numeric_range" end
    return Int(tonumber(s), 0, maximum)
end
function P.Copper(s) return Copper(s, "99999999999", MAX) end
local function Positive(s)
    local n, why = P.Copper(s)
    if not n then return nil, why end
    if n == 0 then return nil, "copper" end
    return n
end
local function Median(values)
    table.sort(values, function(a, b) return a[1] < b[1] end)
    local total, count = 0, 0
    for _, v in ipairs(values) do total = total + v[2] end
    for _, v in ipairs(values) do count = count + v[2] if 2 * count >= total then return v[1] end end
end
function P.Snapshot(rows, item, variant, source, algorithm)
    if algorithm ~= P.ALGORITHM then return nil, "algorithm" end
    if not Key(item, variant) then return nil, "identity" end
    if source ~= "auctions" and source ~= "commodities" then return nil, "source" end
    if type(rows) ~= "table" or #rows > 150000 then return nil, "shape" end
    local tiers, supply, priced, listings = {}, 0, 0, 0
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or not Key(row.item_id, row.variant_key) or row.item_id ~= item or row.variant_key ~= variant then return nil, "identity" end
        local q = Int(row.quantity, 1, 2147483647)
        if not q then return nil, "quantity" end
        if supply > floor(SAFE / 10) - q then return nil, "numeric_range" end
        supply = supply + q
        local b, u, bid, why
        if row.total_copper ~= nil then
            b, why = Copper(row.total_copper, "9007199254740991", SAFE)
            if not b or b == 0 then return nil, why or "copper" end
        end
        if row.unit_copper ~= nil then u, why = Positive(row.unit_copper) if not u then return nil, why end end
        if row.bid_copper ~= nil then bid, why = Positive(row.bid_copper) if not bid then return nil, why end end
        if source == "commodities" then
            if not u or b then return nil, "source" end
        else
            if u or (not b and not bid) then return nil, "source" end
            if b then
                -- Correct the quotient before taking its ceiling; all products
                -- are bounded by MAX + q and remain exact in this domain.
                u = floor(b / q)
                if u > floor(SAFE / q) then return nil, "numeric_range" end
                while u * q < b do
                    u = u + 1
                    if u > floor(SAFE / q) then return nil, "numeric_range" end
                end
                while u > 1 and (u - 1) * q >= b do u = u - 1 end
                if u > MAX then return nil, "numeric_range" end
            end
        end
        if u then
            priced, listings = priced + q, listings + 1
            tiers[u] = (tiers[u] or 0) + q
        end
    end
    local out = { algorithm = P.ALGORITHM, state = priced > 0 and "priced" or "unpriced", supply = supply, priced_supply = priced }
    if priced == 0 then return out end
    local prices = {}
    for p in pairs(tiers) do prices[#prices + 1] = p end
    table.sort(prices)
    local cum, anchor, q25, q50, q75 = 0
    for _, p in ipairs(prices) do
        cum = cum + tiers[p]
        if not q25 and 4 * cum >= priced then q25 = p end
        if not anchor and 4 * cum > priced then anchor = p end
        if not q50 and 2 * cum >= priced then q50 = p end
        if not q75 and 4 * cum >= 3 * priced then q75 = p end
    end
    local eligible, base = 0
    for _, p in ipairs(prices) do if 2 * p >= anchor then eligible = eligible + tiers[p] base = base or p end end
    local want, got, sum = 3 * eligible, 0, 0
    for _, p in ipairs(prices) do
        if 2 * p >= anchor then
            local take = math.min(tiers[p] * 10, want - got)
            local delta = p - base
            if delta > 0 and take > floor((SAFE - sum) / delta) then return nil, "numeric_range" end
            sum, got = sum + take * delta, got + take
            if got == want then break end
        end
    end
    if sum > floor((SAFE - got) / 2) then return nil, "numeric_range" end
    local recent = base + floor((2 * sum + got) / (2 * got))
    out.minimum_listing_copper, out.recent_copper = N(prices[1]), N(recent)
    out.anchor_copper, out.q25_copper, out.q50_copper, out.q75_copper = N(anchor), N(q25), N(q50), N(q75)
    return out
end

function P.History(points, market, item, variant, now, algorithm, watermark)
    if algorithm ~= P.ALGORITHM then return nil, "algorithm" end
    if not Key(item, variant) or type(market) ~= "string" or market == "" or #market > 320 then return nil, "identity" end
    now = Int(now, 1, 4102444800)
    if not now or type(points) ~= "table" or #points > 100000 then return nil, "shape" end
    if watermark ~= nil and not Int(watermark, 1, SAFE) then return nil, "numeric_range" end
    local days, seen, today = {}, {}, floor(now / 86400)
    for _, x in ipairs(points) do
        if type(x) ~= "table" or not Key(x.item_id, x.variant_key) or x.item_id ~= item or x.variant_key ~= variant or x.market_key ~= market then return nil, "identity" end
        if x.algorithm ~= P.ALGORITHM then return nil, "algorithm" end
        local id, at = Int(x.observation_id, 1, SAFE), Int(x.observed_at, 1, now)
        if not id or not at or seen[id] then return nil, "observation" end
        seen[id] = true
        if type(x.complete) ~= "boolean" or type(x.synthetic) ~= "boolean" then return nil, "flags" end
        if x.state ~= "listed" and x.state ~= "absent" and x.state ~= "unknown" then return nil, "presence" end
        if x.recent_copper ~= nil then
            local price, why = Positive(x.recent_copper)
            if not price then return nil, why end
            if x.state ~= "listed" then return nil, "presence" end
        end
        if type(x.content_id) ~= "string" or x.content_id == "" or #x.content_id > 128 then return nil, "identity" end
        local d = floor(at / 86400)
        if x.complete and (watermark == nil or id <= watermark) and today - d >= 0 and today - d < 60 then
            local old = days[d]
            if not old or at > old.observed_at or (at == old.observed_at and id > old.observation_id) then days[d] = x end
        end
    end
    local mv, hv, observed, contents, distinct = {}, {}, 0, {}, 0
    for d, x in pairs(days) do
        observed = observed + 1
        if not contents[x.content_id] then contents[x.content_id], distinct = true, distinct + 1 end
        local price = x.recent_copper and Positive(x.recent_copper)
        if price then
            hv[#hv + 1] = { price, 1 }
            local age = today - d
            if age < 14 then mv[#mv + 1] = { price, age <= 2 and 4 or (age <= 6 and 2 or 1) } end
        end
    end
    local m, h = Median(mv), #hv >= 3 and Median(hv) or nil
    return { algorithm = P.ALGORITHM, history_basis = P.HISTORY_BASIS,
        market_value_copper = m and N(m), historical_value_copper = h and N(h),
        priced_days_14 = #mv, priced_days_60 = #hv, observed_days_60 = observed, distinct_content_count = distinct }
end

function P.Quality(x)
    if type(x) ~= "table" then return nil, "shape" end
    for _, key in ipairs({ "has_price", "complete", "cut", "distribution", "wide_spread", "mixed_variants", "farbelow", "synthetic", "mapping_verified" }) do
        if type(x[key]) ~= "boolean" then return nil, "flags" end
    end
    if not Int(x.priced_listings, 0, 150000) or not Int(x.observed_days_30, 0, 30) then return nil, "range" end
    if x.age_seconds ~= nil and not Int(x.age_seconds, 0, SAFE) then return nil, "range" end
    if not x.has_price then return "none" end
    if x.synthetic or not x.mapping_verified or x.age_seconds == nil then return "limited" end
    local fair = x.age_seconds <= 259200 and x.priced_listings >= 3 and not x.cut and not x.mixed_variants
    local good = fair and x.complete and x.age_seconds <= 86400 and x.priced_listings >= 5 and x.distribution and not x.wide_spread and x.observed_days_30 >= 7 and not x.farbelow
    return good and "good" or (fair and "fair" or "limited")
end
