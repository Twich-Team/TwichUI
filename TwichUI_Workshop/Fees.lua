-- TwichUI Workshop: auction house fees for estimates (the cut and the deposit). No frames, no auction house calls, nothing saved here
-- except the player's own choice of how the cut is treated (TwichUIDB.workshop.view.cut).
-- docs/workshop/pricing-realism-proposal.md, section 5.3.
--
-- THE CUT. A percentage of the sale price, taken when an item sells. The Forever UI source states none; guides agree on 5% at a faction
-- auction house and 15% at a neutral one (Classic rules, which Forever reportedly keeps). Those rates are used, LABELLED "assumed", unless the
-- player chose "Don't deduct" (owner decision R10). When the Gold Ledger holds at least LEDGER_MIN verified seller invoices whose fee is
-- that rate of their gross, the rate is labelled as matching the player's own sales. An invoice does not say which auction house it came
-- from, so the Ledger confirms a rate; it never chooses one.
--
-- THE DEPOSIT. Paid when posting, refunded when the item sells, lost on expiry or cancellation. Guides disagree on its percentages and
-- durations, so no rate is assumed (R10): a deposit is known only from the player's own recorded postings of the same item (the Ledger's
-- verified auction deposits: amount, item, quantity and, from this version, the duration). Nothing else is guessed; unknown is nil, never 0.
local R = TwichUI
local W = R.Workshop
local PR = W.Prices
local Int = W.Int
local F = { POLICY = 1 }
W.Fees = F

F.ASSUMED = { faction = 0.05, neutral = 0.15 }   -- the documented Classic cut rates (assumed until the Ledger agrees)
F.LEDGER_MIN = 3                                 -- invoices that must agree before a rate is called "matches your sales"
F.LEDGER_DAYS = 90                               -- how far back the Ledger is read (its own journal window)
F.MODES = { assumed = true, off = true }
F.DURATIONS = 3                                  -- the client offers three listing durations (Blizzard_AuctionHouseSellFrame, forever)

---------------------------------------------------------------------------
-- The player's choice
---------------------------------------------------------------------------
function F.Mode()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local v = type(ws) == "table" and ws.view
    return type(v) == "table" and v.cut == "off" and "off" or "assumed"
end

-- Returns true, or false and why ("bad", "held", "unsaved"). The default ("assumed") is stored as nothing.
function F.SetMode(mode)
    if not F.MODES[mode] then return false, "bad" end
    if W.Queue and W.Queue.Held and W.Queue.Held() then return false, "held" end
    if type(TwichUIDB) ~= "table" then return false, "unsaved" end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if mode == "assumed" then return true end
        ws = { v = W.SAVED_VERSION }
        TwichUIDB.workshop = ws
    end
    if type(ws.view) ~= "table" then ws.view = {} end
    ws.view.cut = mode ~= "assumed" and mode or nil
    return true
end

-- The listing duration estimates use: the Auction House's own "Default auction duration" (1 to 3), else the shortest
function F.Duration()
    local L = R.WorkshopLauncher
    local ok, s = pcall(function() return L and L.AuctionSettings and L.AuctionSettings() end)
    local d = ok and type(s) == "table" and Int(s.duration, 1, F.DURATIONS) or nil
    return d or 1
end

function F.DurationLabel(d)
    local names = { AUCTION_DURATION_ONE, AUCTION_DURATION_TWO, AUCTION_DURATION_THREE }
    local fallback = { "Short", "Medium", "Long" }
    local n = names[d]
    return type(n) == "string" and n ~= "" and n or fallback[d] or "Short"
end

---------------------------------------------------------------------------
-- Which kind of auction house a market is
---------------------------------------------------------------------------
-- "faction" for an Alliance or Horde auction house, "neutral" for a neutral one, nil when the side is not known. What
-- UnitFactionGroup("npc") returns at a neutral auctioneer in Forever is NOT verified (WP0); "Neutral" is Blizzard's word elsewhere.
function F.HouseKind(side)
    if type(side) ~= "string" then return nil end
    local s = side:lower()
    if s == "alliance" or s == "horde" then return "faction" end
    if s == "neutral" then return "neutral" end
    return nil
end

---------------------------------------------------------------------------
-- What the Gold Ledger proves (read-only; cached per Ledger revision and day)
---------------------------------------------------------------------------
local cache, cacheKey
local function Ledger() return R.Ledger end

local function Now() return time and time() or 0 end

-- { invoices, match = { faction = n, neutral = n }, rates = { { tenths, n } } (fee / gross in tenths of a percent, most common first),
--   deposits = { [item] = { { per (copper per item, a float), r (duration or nil), t } } }, deposits counted, at }
function F.Evidence(now)
    now = now or Now()
    local L = Ledger()
    local rev = L and L.Revision and L.Revision() or 0
    local key = tostring(rev) .. ":" .. tostring(math.floor(now / 86400))
    if cache and cacheKey == key then return cache end
    local ev = { invoices = 0, match = { faction = 0, neutral = 0 }, rates = {}, deposits = {}, depositCount = 0, at = now }
    local counts = {}
    if L and L.Characters and L.Record then
        local from = now - F.LEDGER_DAYS * 86400
        for _, ch in ipairs(L.Characters() or {}) do
            local rec = L.Record(ch.key)
            for _, e in ipairs(rec and rec.entries or {}) do
                if type(e) == "table" and type(e.t) == "number" and e.t >= from then
                    if e.k == "ahSale" and type(e.s) == "table" and type(e.s.invoices) == "table" then
                        for _, inv in ipairs(e.s.invoices) do
                            local g, f = Int(inv.g, 1, PR.MAX_COPPER), Int(inv.f, 0, PR.MAX_COPPER)
                            if g and f and f <= g then
                                ev.invoices = ev.invoices + 1
                                local tenths = math.floor(1000 * f / g + 0.5)
                                counts[tenths] = (counts[tenths] or 0) + 1
                                -- within one copper of the assumed rate: the game's own rounding is not known, so one copper either way
                                for kind, rate in pairs(F.ASSUMED) do
                                    if math.abs(f - PR.Cut(g, rate)) <= 1 then ev.match[kind] = ev.match[kind] + 1 end
                                end
                            end
                        end
                    elseif e.k == "ahDeposit" then
                        local item, qty = Int(e.i, 1, W.MAX_ID), Int(e.q, 1, W.MAX_ID)
                        local paid = type(e.a) == "number" and -e.a or nil
                        if item and qty and paid and paid >= 1 then
                            local list = ev.deposits[item]
                            if not list then list = {} ev.deposits[item] = list end
                            list[#list + 1] = { per = paid / qty, r = Int(e.r, 1, F.DURATIONS), t = e.t }
                            ev.depositCount = ev.depositCount + 1
                        end
                    end
                end
            end
        end
    end
    for tenths, n in pairs(counts) do ev.rates[#ev.rates + 1] = { tenths = tenths, n = n } end
    table.sort(ev.rates, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.tenths < b.tenths end)
    cache, cacheKey = ev, key
    return ev
end

function F.ClearCache() cache, cacheKey = nil, nil end

-- "5% (assumed)" / "15% (matches your sales)"
function F.RateText(rate)
    local tenths = math.floor(rate * 1000 + 0.5)
    local whole = tenths % 10 == 0
    return (whole and ("%d%%"):format(tenths / 10) or ("%.1f%%"):format(tenths / 10))
end

---------------------------------------------------------------------------
-- The cut
---------------------------------------------------------------------------
-- The cut for a market's side: { rate, kind, source = "confirmed" | "assumed" | "ledger", matches (invoices at this rate), label } or nil and
-- why: "off" (the player chose not to deduct it) or "house" (which kind of auction house it is isn't known). A rate confirmed in the code
-- (Prices.CUT, the documented place for a rate read from the game) comes first.
function F.Cut(side, now)
    if F.Mode() == "off" then return nil, "off" end
    local confirmed = PR.CutRate and PR.CutRate(side)
    if confirmed then
        return { rate = confirmed, kind = F.HouseKind(side), source = "confirmed", matches = 0, label = F.RateText(confirmed) .. ", confirmed" }
    end
    local kind = F.HouseKind(side)
    if not kind then return nil, "house" end
    local rate = F.ASSUMED[kind]
    local ev = F.Evidence(now)
    local n = ev.match[kind] or 0
    local source = n >= F.LEDGER_MIN and "ledger" or "assumed"
    return { rate = rate, kind = kind, source = source, matches = n,
        label = F.RateText(rate) .. (source == "ledger" and ", matches your sales" or ", assumed") }
end

-- The cut of a gross amount, rounded like every Workshop cut (Prices.Cut). nil cut: 0.
function F.CutOf(amount, cut) return cut and PR.Cut(amount, cut.rate) or 0 end

---------------------------------------------------------------------------
-- The deposit
---------------------------------------------------------------------------
local function Median(xs)
    table.sort(xs)
    local n = #xs
    if n == 0 then return nil end
    if n % 2 == 1 then return xs[(n + 1) / 2] end
    return (xs[n / 2] + xs[n / 2 + 1]) / 2
end

-- The deposit for posting `qty` of an item as ONE listing for `duration` (default F.Duration()), from the player's own recorded deposits of
-- that item: { amount (whole copper, at least 1), perItem, n (postings used), source = "ledger", duration, durationKnown (the postings used
-- recorded this duration) } or nil and why ("none": never posted through TwichUI with the Ledger on, "badqty").
function F.Deposit(item, qty, duration, now)
    qty = Int(qty, 1, W.MAX_ID)
    item = Int(item, 1, W.MAX_ID)
    if not (item and qty) then return nil, "badqty" end
    duration = Int(duration, 1, F.DURATIONS) or F.Duration()
    local list = F.Evidence(now).deposits[item]
    if not list or #list == 0 then return nil, "none" end
    local same, any = {}, {}
    for _, d in ipairs(list) do
        any[#any + 1] = d.per
        if d.r == duration then same[#same + 1] = d.per end
    end
    local use, known = any, false
    if #same > 0 then use, known = same, true end
    local per = Median(use)
    local amount = math.ceil(per * qty - 1e-9)
    if amount < 1 then amount = 1 end
    return { amount = amount, perItem = per, n = #use, source = "ledger", duration = duration, durationKnown = known }
end

-- How many failed (expired) listings a profit survives: floor(profit / deposit). nil when either is not positive.
function F.Covers(profit, deposit)
    if type(profit) ~= "number" or type(deposit) ~= "number" or profit <= 0 or deposit <= 0 then return nil end
    return math.floor(profit / deposit)
end

-- For the settings page: one line on what the Ledger shows about the cut
function F.EvidenceText()
    local ev = F.Evidence()
    if ev.invoices == 0 then return "No verified auction sales in the Gold Ledger yet." end
    local parts = {}
    for i, r in ipairs(ev.rates) do
        if i > 3 then break end
        parts[#parts + 1] = ("%d at %s"):format(r.n, F.RateText(r.tenths / 1000))
    end
    return ("%d verified %s in the last %d days: %s."):format(ev.invoices, ev.invoices == 1 and "sale" or "sales", F.LEDGER_DAYS, table.concat(parts, ", "))
end
