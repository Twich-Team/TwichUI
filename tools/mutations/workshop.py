"""The Workshop mutation catalog for tools/mutate.py (testing roadmap M4). Loaded by file path, never imported by name.

Each entry is ONE exact-text edit of ONE production file, applied only to a disposable copy:
  id       area.topic.name   area is the group: `market` (prices, history, statistics, quotes, the craft estimate) or `crafting`
           (materials, stock, shopping, make-versus-buy, Opportunities)
  file     the file edited (under TwichUI_Workshop/)
  find     text that must occur EXACTLY ONCE in that file (zero or several is an invalid mutation, never a kill)
  replace  what it becomes
  why      the realistic mistake it stands for, in a sentence
  tests    the test files expected to catch it, fastest first (the mutant is killed by the first that fails)
  smoke    True for the small default group
  expect   "killed" (default) or "survived" for a documented, accepted survivor (then `note` says why)

HOW TO ADD ONE: pick a defect someone could really write (a boundary, a rounding, a swapped branch, a dropped term), copy the line from
the source with enough context to be unique, run `bash tools/mutate.sh --check --id <id>`, then `bash tools/mutate.sh --id <id>`. A
survivor is information: either the tests have a gap (add the missing case, do not change `expect`) or the edit changes nothing
observable (an equivalent mutant: delete it). Keep the catalog to defects with a story; a long list of arbitrary swaps is not the goal.
When the production line changes, the entry becomes invalid until its `find` is updated: that is the intended alarm.
"""

MKT = "test_workshop_market_reference.lua"
CRF = "test_workshop_crafting_reference.lua"
PRICES, HISTORY, MARKET = "TwichUI_Workshop/Prices.lua", "TwichUI_Workshop/History.lua", "TwichUI_Workshop/Market.lua"
MATERIALS, STOCK, DATA = "TwichUI_Workshop/Materials.lua", "TwichUI_Workshop/Stock.lua", "TwichUI_Workshop/Data.lua"
OBSERVE = "TwichUI_Workshop/Observe.lua"
SHOPPING, VENDOR, OPPS = "TwichUI_Workshop/Shopping.lua", "TwichUI_Workshop/Vendor.lua", "TwichUI_Workshop/Opportunities.lua"

# `--broad` re-runs a SURVIVOR against these older, broader Workshop tests to say whether anything else notices it (the mutation still counts as
# a survivor of its focused tests; the note only tells you where the gap is). The default run never uses them.
SUITE = {"broad_tests": ("test_workshop_market.lua", "test_workshop_prices.lua", "test_workshop_shopping.lua", "test_workshop_storage.lua", "test_workshop.lua")}

MUTATIONS = []


def m(id, file, find, replace, why, tests, smoke=False, expect="killed", note=""):
    MUTATIONS.append(dict(id=id, file=file, find=find, replace=replace, why=why, tests=tuple(tests), smoke=smoke, expect=expect, note=note))


# ======================================================================================================================
# MARKET AND PRICING: the batch (cheapest price per item), history, statistics, quotes and the craft estimate
# ======================================================================================================================
# --- the batch: fractional unit prices, cheapest, quantity at the cheapest tier, next higher price ------------------------
m("market.batch.compare-rounded-units", PRICES,
  "local lhs, rhs = buyout * a.c, a.b * count   -- compares the unit prices exactly, with no division",
  "local lhs, rhs = math.floor(buyout / count), math.floor(a.b / a.c)",
  "listings compared by whole-copper unit prices instead of exactly: 299 for 3 (99.67 each) ties with 99 for 1",
  [MKT], smoke=True)
m("market.batch.tie-replaces-cheapest", PRICES, "if lhs < rhs then", "if lhs <= rhs then",
  "a listing at exactly the cheapest price replaces it, so the quantity at that price restarts instead of adding up", [MKT])
m("market.batch.cheapest-reversed", PRICES, "if lhs < rhs then", "if lhs > rhs then",
  "the dearest listing is kept as the cheapest price", [MKT])
m("market.batch.tier-quantity-not-added", PRICES, "a.q = a.q + count", "a.q = count",
  "items at the cheapest price are not added up when several listings share it", [MKT])
m("market.batch.tier-quantity-not-reset", PRICES, "a.b, a.c, a.q = buyout, count, count", "a.b, a.c = buyout, count",
  "a new, lower cheapest price keeps the old price's quantity", [MKT])
m("market.batch.next-price-not-demoted", PRICES, "a.b2, a.c2 = a.b, a.c", "a.b2, a.c2 = a.b2, a.c2",
  "the old cheapest price is not remembered as the next higher price when a cheaper listing arrives", [MKT])
m("market.batch.next-price-highest", PRICES, "elseif not a.b2 or buyout * a.c2 < a.b2 * count then", "elseif not a.b2 or buyout * a.c2 > a.b2 * count then",
  "the next higher price becomes the dearest listing instead of the nearest above the cheapest", [MKT])
# M7.1: the batch's entries are built a few hundred at a time (ItemsJob), by the scan as well as by Items(); the stepped path has its own defects
PRICES_TESTS = "test_workshop_prices.lua"
m("market.batch.stepped-boundary-item-lost", PRICES,
  "            out[id] = Entry(acc[id])\n            self.cursor = id\n            left = left - 1",
  "            if left > 1 then out[id] = Entry(acc[id]) end\n            self.cursor = id\n            left = left - 1",
  "the last item of every build step is skipped: a market of more than one step silently loses items at the step boundaries", [PRICES_TESTS])
m("market.batch.stepped-ranking-shifted", PRICES,
  "            local id = ids[self.at]\n            out[id] = Entry(acc[id])",
  "            local id = ids[self.at + 1]\n            out[id] = Entry(acc[id])",
  "over the item limit the kept items are read one rank late: the best-ranked item is dropped and the first one that did not fit is kept", [PRICES_TESTS, MKT])
m("market.scan.build-ignores-closed-window", "TwichUI_Workshop/Scan.lua",
  "                if not SC.AuctionOpen() then return End(\"interrupted\", \"closed\") end\n                local Perf = R.Perf",
  "                local Perf = R.Perf",
  "the scan keeps building and saves a market after the auction window was closed during the build steps", [PRICES_TESTS])
m("market.batch.next-price-same-copper", PRICES, "if x <= p then x = 0 end", "if x < p then x = 0 end",
  "a next price that rounds to the cheapest copper is reported as a different price", [MKT])
m("market.batch.items-total", PRICES, "a.l, a.t = a.l + 1, a.t + count", "a.l, a.t = a.l + 1, a.t + 1",
  "the items listed are counted per listing instead of per item in the stacks", [MKT])
m("market.batch.bid-only-as-invalid", PRICES, "self.noBuyout = self.noBuyout + 1 return false end", "self.noBuyout = self.noBuyout + 1 end",
  "a bid-only auction falls through and is counted as invalid as well as bid-only", [MKT])
m("market.batch.item-limit-priority", PRICES, "if px ~= py then return px > py end", "if px ~= py then return px < py end",
  "over the item limit, the recipe items are dropped first instead of kept first", [MKT])
m("market.batch.item-limit-listings", PRICES, "if lx ~= ly then return lx > ly end", "if lx ~= ly then return lx < ly end",
  "over the item limit, the items with the fewest listings are kept", [MKT])

# --- non-finite auction data (2026-11-12 client finding: in Forever a NaN equals 0, so a bid-only test on it counts a NaN buyout as bid-only) ---
m("market.batch.finite-check-dropped", PRICES, "if not W.Finite(raw) then self.invalid = self.invalid + 1 return false end",
  "if raw == nil then self.invalid = self.invalid + 1 return false end",
  "the buyout is compared with 0 before it is known to be a finite number: a NaN buyout becomes bid-only in the client", [MKT], smoke=True)
m("market.data.int-finite-dropped", DATA, "if not Finite(v) or v < lo or v > hi or math.floor(v) ~= v then return nil end",
  "if type(v) ~= \"number\" or v ~= v or v < lo or v > hi or math.floor(v) ~= v then return nil end",
  "the whole-number check goes back to deciding NaN by comparison, which the client's NaN passes (a NaN item or count is accepted)", [MKT])
m("market.data.finite-always-true", DATA, "return tostring(v):find(\"^[%d%.eE%+%-]+$\") ~= nil", "return true",
  "the finiteness test accepts everything, so only comparisons stand between a NaN or an infinity and a price", [MKT])
m("market.history.price-finite-dropped", HISTORY, "if not W.Finite(price) or price ~= floor(price)", "if type(price) ~= \"number\" or price ~= floor(price)",
  "the history accepts a price decided by comparison alone, which a client NaN passes", [MKT])

# --- history: folding, retention, windows ------------------------------------------------------------------------------
m("market.history.fold-bucket-index", HISTORY, "local b = floor(d / H.BUCKET_DAYS)", "local b = floor((d + 1) / H.BUCKET_DAYS)",
  "the 28-day bucket of a day is off by one at its edge", [MKT])
m("market.history.fold-low", HISTORY, "if p < bks[at + 1] then bks[at + 1] = p end", "if p > bks[at + 1] then bks[at + 1] = p end",
  "a folded day replaces the bucket's low when it is higher", [MKT])
m("market.history.fold-sum", HISTORY, "bks[at + 3] = bks[at + 3] + p", "bks[at + 3] = p",
  "a bucket's sum keeps only the last folded day, so its mean is wrong", [MKT])
m("market.history.fold-count", HISTORY, "bks[at + 4] = bks[at + 4] + 1", "bks[at + 4] = bks[at + 4]",
  "a bucket's day count does not grow when a day is folded into it", [MKT])
m("market.history.exact-days-kept", HISTORY, "while #pts > H.POINTS * 2 do Fold(pts, bks) end", "while #pts >= H.POINTS * 2 do Fold(pts, bks) end",
  "only six recent days are kept exactly instead of seven", [MKT])
m("market.history.expire-exact-boundary", HISTORY, "while #pts >= 2 and pts[1] < cutoff do", "while #pts >= 2 and pts[1] <= cutoff do",
  "the oldest retained exact day (exactly RETAIN_DAYS back) is dropped", [MKT])
m("market.history.expire-bucket-boundary", HISTORY, "(bks[1] + 1) * H.BUCKET_DAYS - 1 < cutoff", "(bks[1] + 1) * H.BUCKET_DAYS < cutoff",
  "a bucket is kept one day past the retention", [MKT])
m("market.history.same-day-keeps-lowest", HISTORY, "if day == last then pts[n] = price else", "if day == last then pts[n] = math.min(pts[n], price) else",
  "a later scan on the same day cannot raise that day's value", [MKT])
m("market.history.stale-boundary", HISTORY, "if day < last then return nil, \"stale\" end", "if day <= last then return nil, \"stale\" end",
  "a second scan on the newest day is refused as stale", [MKT])
m("market.history.window-first-day", HISTORY, "if d >= fromDay and d <= toDay then", "if d > fromDay and d <= toDay then",
  "the first day of a window is left out", [MKT], smoke=True)
m("market.history.window-last-day", HISTORY, "if d >= fromDay and d <= toDay then", "if d >= fromDay and d < toDay then",
  "the last day of a window (today) is left out", [MKT])
m("market.history.window-partial-bucket", HISTORY, "if b0 >= fromDay and b1 <= toDay then", "if b0 >= fromDay or b1 <= toDay then",
  "a bucket that only overlaps the window is counted whole", [MKT])
m("market.history.window-skipped", HISTORY, "r.skipped = r.skipped + bks[i + 4]", "r.skipped = r.skipped + 1",
  "the days a partly covered bucket hides are counted as one", [MKT])

# --- statistics, trend, comparison ------------------------------------------------------------------------------------
m("market.stats.week-length", MARKET, "local from = days and (today - days + 1) or 1", "local from = days and (today - days) or 1",
  "'the last 7 days' covers eight days", [MKT])
m("market.stats.average-rounding", MARKET, "average = math.floor(w.sum / w.n + 0.5), newest", "average = math.floor(w.sum / w.n), newest",
  "the mean price rounds down instead of to the nearest copper", [MKT])
m("market.trend.window-first-day", MARKET, "if pts[i] >= from then", "if pts[i] > from then",
  "the first day of 'the last N days' is excluded from the trend (survived the 2026-11-12 manual probe)", [MKT], smoke=True)
m("market.trend.negative-rounding", MARKET, "return b < a and -tenths or tenths", "return b < a and math.floor(-(num / den) - 0.5) or tenths",
  "a fall is rounded one tenth too far (1000 to 900 read -10.1%, a real defect fixed in M2)", [MKT], smoke=True)
m("market.trend.positive-truncated", MARKET, "local tenths = (2 * num + den - r) / (2 * den)", "local tenths = (num - num % den) / den",
  "a rise is truncated instead of rounded to the nearest tenth of a percent", [MKT])
m("market.trend.flat-as-up", MARKET, "local dir = b > a and \"up\" or (b < a and \"down\" or \"flat\")", "local dir = b >= a and \"up\" or (b < a and \"down\" or \"flat\")",
  "an unchanged price is reported as rising", [MKT])
m("market.trend.start-point", MARKET, "if not first then first = i end", "first = i",
  "the trend starts at the newest day instead of the first day of the window", [MKT])
m("market.compare.reference-includes-today", MARKET, "local to = H.Day(p.at) - 1", "local to = H.Day(p.at)",
  "the current scan votes on its own reference", [MKT])
m("market.compare.equal-is-above", MARKET, "relation = p.price > ref and \"above\" or (p.price < ref and \"below\" or \"same\")",
  "relation = p.price >= ref and \"above\" or (p.price < ref and \"below\" or \"same\")", "a price equal to its reference is called above it", [MKT])

# --- quotes and the craft estimate (quantity-aware, cut, profit) -----------------------------------------------------
m("market.quote.exact-boundary", PRICES, "state = (p.qty ~= nil and qty <= p.qty) and \"exact\" or \"estimate\"", "state = (p.qty ~= nil and qty < p.qty) and \"exact\" or \"estimate\"",
  "buying exactly the items listed at the cheapest price is called an estimate", [CRF], smoke=True)
m("market.quote.few-boundary", PRICES, "if p.total and p.total < qty then", "if p.total and p.total <= qty then",
  "buying exactly everything listed is refused as 'not enough listed'", [CRF])
m("market.quote.cost-capped-at-tier", PRICES, "q.cost = p.price * qty", "q.cost = p.price * math.min(qty, p.qty or qty)",
  "items beyond the cheapest tier are costed at nothing, so the estimate is too low", [CRF])
m("market.estimate.cheapest-flag-boundary", PRICES, "row.cheapest = p.qty ~= nil and m.qty > p.qty", "row.cheapest = p.qty ~= nil and m.qty >= p.qty",
  "a craft that needs exactly the cheapest tier is flagged as 'cheapest listing only'", [CRF])
m("market.estimate.missing-price-partial-cost", PRICES, "if e.missing == 0 then e.cost = cost end", "e.cost = cost",
  "a craft with an unpriced material shows the sum of the priced ones as its cost", [CRF], smoke=True)
m("market.estimate.sell-range-collapsed", PRICES, "e.sellLow, e.sellHigh = p.price * lo, p.price * hi", "e.sellLow, e.sellHigh = p.price * lo, p.price * lo",
  "the sell price of a variable output ignores its maximum", [CRF])
m("market.estimate.cut-low-ignored", PRICES, "local cutLow = rate and PR.Cut(e.sellLow, rate) or 0", "local cutLow = 0",
  "the known auction house cut is not taken off the low end", [CRF])
m("market.estimate.cut-high-ignored", PRICES, "local cutHigh = rate and PR.Cut(e.sellHigh, rate) or 0", "local cutHigh = 0",
  "the known auction house cut is not taken off the high end", [CRF])
m("market.estimate.profit-high-uses-low", PRICES, "e.profitLow, e.profitHigh = e.netLow - e.cost, e.netHigh - e.cost", "e.profitLow, e.profitHigh = e.netLow - e.cost, e.netLow - e.cost",
  "the best-case profit repeats the worst case", [CRF])
m("market.estimate.profit-sign", PRICES, "e.profitLow, e.profitHigh = e.netLow - e.cost, e.netHigh - e.cost", "e.profitLow, e.profitHigh = e.cost - e.netLow, e.cost - e.netHigh",
  "profit computed as cost minus income", [CRF])
m("market.estimate.inverted-output-range", PRICES, "if lo and hi < lo then lo, hi = nil, nil end", "if lo and hi < lo then hi = lo end",
  "an output whose maximum is below its minimum is treated as a fixed output instead of unknown", [CRF])
m("market.cut.rounding", PRICES, "return math.floor(amount * rate + 0.5)", "return math.floor(amount * rate)",
  "the cut is truncated instead of rounded to the nearest copper", [CRF])

# ======================================================================================================================
# CRAFTING: materials, stock, shopping, make-versus-buy, Opportunities
# ======================================================================================================================
# --- allocation of owned items (W.Split) -------------------------------------------------------------------------------
m("crafting.split.guild-before-bank", DATA,
  "    local k = math.min(want, Have(bank))\n    want = want - k\n    local g = math.min(want, Have(guild))\n    return b, k, g, want - g",
  "    local g = math.min(want, Have(guild))\n    want = want - g\n    local k = math.min(want, Have(bank))\n    return b, k, g, want - k",
  "owned items are taken from the guild bank before the player's own bank", [CRF], smoke=True)
m("crafting.split.negative-count-adds", DATA, "local function Have(n) return (type(n) == \"number\" and n > 0) and n or 0 end", "local function Have(n) return type(n) == \"number\" and n or 0 end",
  "a negative held count is taken as stock", [CRF])
m("crafting.split.negative-want", DATA, "want = (type(want) == \"number\" and want > 0) and want or 0", "want = type(want) == \"number\" and want or 0",
  "a negative need takes a negative amount out of the bags", [CRF])
m("crafting.split.guild-not-subtracted", DATA, "return b, k, g, want - g", "return b, k, g, want",
  "what the guild bank covers is still reported as lacking", [CRF])

# --- combined materials ------------------------------------------------------------------------------------------------
m("crafting.materials.crafts-not-multiplied", MATERIALS, "need[m.item] = need[m.item] + m.qty * e.crafts", "need[m.item] = need[m.item] + m.qty",
  "a queued recipe's materials are counted once, however many crafts are queued", [CRF], smoke=True)
m("crafting.materials.output-count-ignores-crafts", MATERIALS, "made[e.outItem] = (made[e.outItem] or 0) + e.outMin * e.crafts", "made[e.outItem] = (made[e.outItem] or 0) + e.outMin",
  "a queued craft's output is credited once, however many crafts are queued", [CRF])
m("crafting.materials.output-credit-uses-max", MATERIALS, "made[e.outItem] = (made[e.outItem] or 0) + e.outMin * e.crafts", "made[e.outItem] = (made[e.outItem] or 0) + (e.outMax or e.outMin) * e.crafts",
  "a variable output is credited at its best case, so less is bought than may be needed", [CRF])
m("crafting.materials.cycle-credited", MATERIALS, "if cyc[i] then", "if false then",
  "recipes that depend on each other are credited as if they could start from nothing", [CRF])
m("crafting.materials.credit-ignored", MATERIALS, "local _, k, g, rest = W.Split(math.max(0, n - (mk or 0)), h, bank, guild)", "local _, k, g, rest = W.Split(math.max(0, n), h, bank, guild)",
  "what queued crafts will make is not subtracted from what must be got", [CRF])
m("crafting.materials.unreadable-bags-as-zero", MATERIALS, "local h = W.Count(have(item))", "local h = W.Count(have(item)) or 0",
  "bag counts that cannot be read are treated as an empty bag instead of unknown", [CRF], smoke=True)
m("crafting.materials.count-old-guard", MATERIALS, "local h = W.Count(have(item))",
  "local h = have(item); if type(h) ~= \"number\" or h ~= h or h < 0 then h = nil end",
  "the bag count is judged by the old `h ~= h or h < 0` idiom again: a positive infinity (or a fraction) is accepted as a count and covers every need (client run 2026-11-12: numeric.held.inf)", [CRF], smoke=True)
m("crafting.materials.unknown-recipe-uncounted", MATERIALS, "unknown = unknown + 1", "unknown = unknown",
  "a queued recipe with unknown materials is not counted as unknown", [CRF])
m("crafting.materials.unknown-sorted-first", MATERIALS, "if row.short == nil then return 2 end", "if row.short == nil then return 0 end",
  "rows with unknown counts are listed before those that are short", [CRF])
m("crafting.materials.guild-collect-uncounted", MATERIALS, "if k + g > 0 then s.collectItems = s.collectItems + 1 end", "if k > 0 then s.collectItems = s.collectItems + 1 end",
  "an item collected only from the guild bank is not counted as one to collect", [CRF])

# --- stock: bank and guild-bank eligibility --------------------------------------------------------------------------
m("crafting.stock.uncertain-bank-counted", STOCK, "b.counted = b.seen and not b.uncertain", "b.counted = b.seen",
  "a bank that may have changed since it was seen is still planned with", [CRF], smoke=True)
m("crafting.stock.bank-tabs-not-summed", STOCK, "b.items[item] = (b.items[item] or 0) + n", "b.items[item] = n",
  "an item held in several bank tabs is counted only for the last one", [CRF])
m("crafting.stock.guild-pending-ignored", STOCK, "if t.u or live.guildPending then how = \"uncertain\"", "if t.u then how = \"uncertain\"",
  "a guild tab is counted while the bag change that makes it uncertain is not yet re-read", [CRF])
m("crafting.stock.guild-other-character-counted", STOCK, "elseif not ids.char or t.by ~= ids.char then how = \"rights\"", "elseif not ids.char then how = \"rights\"",
  "a tab only another character saw is counted as withdrawable", [CRF])
m("crafting.stock.guild-unknown-rights-counted", STOCK, "elseif t.w ~= 1 then how = (t.w == 0) and \"nowithdraw\" or \"rights\"", "elseif t.w == 0 then how = \"nowithdraw\"",
  "a tab whose withdraw rights were never seen is counted", [CRF])
m("crafting.stock.allowance-expiry-boundary", STOCK, "(now - t.remAt) < K.REM_FRESH", "(now - t.remAt) <= K.REM_FRESH",
  "a 'no withdrawals left' reading is believed one second too long", [CRF])
m("crafting.stock.guild-tabs-not-summed", STOCK, "g.counted[item] = (g.counted[item] or 0) + n", "g.counted[item] = n",
  "an item held in several guild tabs is counted only for the last one", [CRF])
m("crafting.stock.guild-policy-ignored", STOCK, "local g = view.guild.enabled and view.guild.counted[item] or 0", "local g = view.guild.counted[item] or 0",
  "guild bank materials are planned with although the player turned that off", [CRF], smoke=True)
m("crafting.stock.craft-unreadable-bags-as-zero", STOCK, "if h == nil then out.state = \"unknown\" return out end", "if h == nil then h = 0 end",
  "a craft whose bag counts cannot be read is reported as short instead of unknown", [CRF])
m("crafting.stock.craft-count-old-guard", STOCK, "local h = W.Count(have(m.item))",
  "local h = have(m.item); if type(h) ~= \"number\" or h ~= h or h < 0 then h = nil end",
  "a craft is judged with the old count guard again: an infinite bag count makes it ready", [CRF])
m("crafting.observe.bagcount-old-guard", OBSERVE, "return W.Count(n)   -- a whole number from 0, or nil",
  "if type(n) ~= \"number\" or n ~= n or n < 0 then return nil end return n   -- a whole number from 0, or nil",
  "the game's item count is passed on with the old guard: an infinity or a fraction becomes a count", [CRF])
m("crafting.data.count-zero-rejected", DATA, "function W.Count(v) return W.Int(v, 0, W.MAX_ID) end", "function W.Count(v) return W.Int(v, 1, W.MAX_ID) end",
  "an empty bag (a count of 0) is called unknown instead of 0, so the whole need is not reported short", [CRF])
m("crafting.data.count-negative-accepted", DATA, "function W.Count(v) return W.Int(v, 0, W.MAX_ID) end", "function W.Count(v) return W.Int(v, -1, W.MAX_ID) end",
  "a negative count is accepted as a count", [CRF])
m("crafting.data.count-unbounded", DATA, "function W.Count(v) return W.Int(v, 0, W.MAX_ID) end", "function W.Count(v) return W.Int(v, 0, 1e300) end",
  "the upper bound on a count is lifted, so 1e300 reads as a number of items held", [CRF])
m("crafting.stock.craft-guild-collect", STOCK, "if k + g > 0 then collect = true end", "if k > 0 then collect = true end",
  "a craft whose materials come from the guild bank is reported as ready", [CRF])

# --- shopping: vendor versus auction, make versus buy -----------------------------------------------------------------
m("crafting.shopping.best-tie-to-auction", SHOPPING, "if o.auction and o.auction.cost and (not best or o.auction.cost < best.cost) then", "if o.auction and o.auction.cost and (not best or o.auction.cost <= best.cost) then",
  "equal vendor and auction prices go to the auction house instead of the vendor", [CRF], smoke=True)
m("crafting.shopping.suggest-tie-to-last", SHOPPING, "(not bestCost or o.cost < bestCost) then best, bestCost = k, o.cost end", "(not bestCost or o.cost <= bestCost) then best, bestCost = k, o.cost end",
  "among equal costs the last source wins instead of vendor, auction, then making", [CRF])
m("crafting.shopping.unusable-make-pick-honoured", SHOPPING, "if pick and Usable(res.options[pick]) then", "if pick and res.options[pick] then",
  "a player's pick of an unusable option is honoured", [CRF])
m("crafting.shopping.picks-decided-last", SHOPPING, "if pa ~= pb then return pa end", "if pa ~= pb then return pb end",
  "the player's choices are decided after the suggestions instead of first", [CRF])
m("crafting.shopping.make-crafts-rounded-down", SHOPPING, "local crafts = math.ceil(short / lo)", "local crafts = math.floor(short / lo)",
  "making is planned for fewer crafts than the shortage needs", [CRF], smoke=True)
m("crafting.shopping.make-crafts-limit-boundary", SHOPPING, "if crafts > W.MAX_CRAFTS then opt.state = \"toomany\" return opt end", "if crafts >= W.MAX_CRAFTS then opt.state = \"toomany\" return opt end",
  "exactly the largest allowed number of crafts (999) is refused (survived the first M3 probe)", [CRF])
m("crafting.shopping.make-surplus", SHOPPING, "opt.crafts, opt.perCraft, opt.made, opt.surplus = crafts, lo, crafts * lo, crafts * lo - short", "opt.crafts, opt.perCraft, opt.made, opt.surplus = crafts, lo, crafts * lo, lo - short",
  "the leftover of making is worked out for one craft", [CRF])
m("crafting.shopping.make-range-suggested", SHOPPING, "if hi ~= lo then opt.state = \"range\" opt.range = lo .. \"-\" .. hi return opt end", "",
  "a recipe with a variable output is used to suggest making", [CRF])
m("crafting.shopping.make-circular-allowed", SHOPPING, "if m.item == item then opt.state = \"circular\" return opt end", "if false then opt.state = \"circular\" return opt end",
  "a recipe that uses the item it makes is offered as a way to make it", [CRF])
m("crafting.shopping.reagents-not-multiplied", SHOPPING, "local total = m.qty * crafts", "local total = m.qty",
  "a made material's reagents are counted for one craft, not all of them", [CRF])
m("crafting.shopping.make-cost-excludes-owned", SHOPPING, "if cashKnown and valueKnown then opt.cost = cash + ownedValue end", "if cashKnown and valueKnown then opt.cost = cash end",
  "making is valued at its cash cost only, so owned reagents look free", [CRF])
m("crafting.shopping.make-cost-ignores-unpriced-owned", SHOPPING, "if cashKnown and valueKnown then opt.cost", "if cashKnown then opt.cost",
  "a recipe with an owned, unpriced reagent gets a cost that leaves it out", [CRF])
m("crafting.shopping.owned-value-truncated", SHOPPING, "line.value = Round(owned * u)", "line.value = math.floor(owned * u)",
  "owned reagents are valued rounded down instead of to the nearest copper", [CRF])
m("crafting.shopping.owned-value-per-purchase", SHOPPING, "if vr then best = vr.p / vr.s end", "if vr then best = vr.p end",
  "a vendor stack's price is used as the price of one item", [CRF])
m("crafting.shopping.best-recipe-dearest", SHOPPING, "if o.cost and (not best or o.cost < best.cost) then best = o end", "if o.cost and (not best or o.cost > best.cost) then best = o end",
  "the dearest recipe is chosen to make an item", [CRF])
m("crafting.shopping.shared-bags-counted-twice", SHOPPING, "bags = r.have - math.min(r.have, net)", "bags = r.have",
  "bag items the queue's own crafts use are offered again to the reagents of made materials", [CRF])
m("crafting.shopping.shared-bank-counted-twice", SHOPPING, "bank = math.max(0, (r.bank or 0) - (r.fromBank or 0))", "bank = math.max(0, (r.bank or 0))",
  "bank items collected for the queue are offered again to a made material's reagents", [CRF])
m("crafting.shopping.reagent-spent-twice", SHOPPING, "return math.max(0, p.bags - (u.bags or 0)), math.max(0, p.bank - (u.bank or 0)), math.max(0, p.guild - (u.guild or 0))",
  "return math.max(0, p.bags), math.max(0, p.bank - (u.bank or 0)), math.max(0, p.guild - (u.guild or 0))",
  "bag items used as one made material's reagent are free for the next one", [CRF])
m("crafting.shopping.reagent-buys-not-added", SHOPPING, "a.qty, a.extra, a.forNames = a.qty + rb.qty, rb.qty, rb.names", "a.qty, a.extra, a.forNames = a.qty, rb.qty, rb.names",
  "reagents bought for a made material are not added to the purchase of the same item", [CRF])
m("crafting.shopping.unpriced-not-counted", SHOPPING, "totals.missing = totals.missing + 1", "totals.missing = totals.missing",
  "an unpriced purchase is left out of the 'missing' count", [CRF], smoke=True)
m("crafting.shopping.estimate-flag-lost", SHOPPING, "if o.estimate then totals.estimate = true end", "if false then totals.estimate = true end",
  "a total containing an estimated price is not flagged as an estimate", [CRF])
m("crafting.shopping.cash-not-accumulated", SHOPPING, "totals.cash, totals.priced = totals.cash + o.cost, totals.priced + 1", "totals.cash, totals.priced = o.cost, totals.priced + 1",
  "the total to spend is the last row's cost", [CRF])
m("crafting.shopping.unknown-bags-uncounted", SHOPPING, "if r.short == nil then unknownBags = unknownBags + 1", "if r.short == nil then unknownBags = unknownBags",
  "unreadable bag counts are not reported with the plan", [CRF])

# --- vendor quotes ----------------------------------------------------------------------------------------------------
m("crafting.vendor.purchases-rounded-down", VENDOR, "local purchases = math.ceil(qty / rec.s)", "local purchases = math.floor(qty / rec.s)",
  "a vendor sells whole stacks, but fewer are bought than needed", [CRF], smoke=True)
m("crafting.vendor.cost-per-item", VENDOR, "q.cost = purchases * rec.p", "q.cost = qty * rec.p",
  "the price of a stack is charged for each item wanted", [CRF])
m("crafting.vendor.sold-out-unlimited", VENDOR, "if rec.a >= 0 and items > rec.a then", "if rec.a > 0 and items > rec.a then",
  "a sold-out merchant (0 left) is treated as having unlimited stock", [CRF])
m("crafting.vendor.stock-checked-before-rounding", VENDOR, "if rec.a >= 0 and items > rec.a then", "if rec.a >= 0 and qty > rec.a then",
  "the merchant's stock is compared with the items wanted, not the whole stacks that must be bought", [CRF])

# --- Opportunities ----------------------------------------------------------------------------------------------------
m("crafting.opps.zero-profit-counted", OPPS, "if r.est.profitLow > 0 then s.profitable = s.profitable + 1 end", "if r.est.profitLow >= 0 then s.profitable = s.profitable + 1 end",
  "a craft that exactly breaks even is counted as profitable (survived the first M3 probe)", [CRF], smoke=True)
m("crafting.opps.zero-profit-kept", OPPS, "if keep and opts.profitOnly then keep = r.est.state == \"ok\" and r.est.profitLow > 0 end", "if keep and opts.profitOnly then keep = r.est.state == \"ok\" and r.est.profitLow >= 0 end",
  "the 'profitable only' filter keeps a craft that breaks even", [CRF])
m("crafting.opps.unknown-before-known", OPPS, "if ka ~= kb then return ka end", "if ka ~= kb then return kb end",
  "rows with an unknown estimate are listed before priced ones", [CRF])
m("crafting.opps.direction-reversed", OPPS, "if desc then return va > vb end", "if desc then return va < vb end",
  "the descending sort is ascending", [CRF])
m("crafting.opps.tie-name-reversed", OPPS, "if na ~= nb then return na < nb end", "if na ~= nb then return na > nb end",
  "equal values are ordered by name backwards", [CRF])
m("crafting.opps.tie-id-reversed", OPPS, "return a.rec.id < b.rec.id", "return a.rec.id > b.rec.id",
  "equal values and names are ordered by recipe id backwards", [CRF])


# ======================================================================================================================
# EXAMINED AND LEFT OUT (equivalent mutants: no test can tell them from the original, so they would only ever "survive")
# ======================================================================================================================
#   Prices.Unit  `return math.max(q, 1)` -> `return q`: the round-up loop above it already lifts a zero to 1.
#   Shopping.Suggest  dropping `(k ~= "make" or o.state == "ok")`: a make option that is not "ok" returns before it is given a cost, and
#       Suggest needs `o.cost`, so the guard never decides anything today (it is defence in depth if EvalMake ever sets a cost earlier).
