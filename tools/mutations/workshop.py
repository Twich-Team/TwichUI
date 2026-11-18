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
SUITE = {"targets": ("TwichUI_Workshop/", "!!!TwichUI/WorkshopAuto.lua", "!!!TwichUI/WorkshopLauncher.lua"), "broad_tests": ("test_workshop_market.lua", "test_workshop_prices.lua", "test_workshop_shopping.lua", "test_workshop_storage.lua", "test_workshop.lua")}

MUTATIONS = []


def m(id, file, find, replace, why, tests, smoke=False, expect="killed", note=""):
    MUTATIONS.append(dict(id=id, file=file, find=find, replace=replace, why=why, tests=tuple(tests), smoke=smoke, expect=expect, note=note))


# Release opt-in/lifecycle safeguards; copies only, never real SavedVariables.
m("workshop.optin.default-on", "!!!TwichUI/WorkshopLauncher.lua",
  "TwichUIDB.ui.workshopEnabled = TwichUIDB.ui.workshopLoadOnLogin == true",
  "TwichUIDB.ui.workshopEnabled = TwichUIDB.ui.workshopLoadOnLogin ~= false",
  "a missing legacy preference silently opts fresh profiles in", ["test_workshop_optin.lua"])
m("workshop.optin.ignore-explicit-off", "!!!TwichUI/WorkshopLauncher.lua",
  "if type(ui.workshopEnabled) == \"boolean\" then return ui.workshopEnabled end",
  "if ui.workshopLoadOnLogin == true then return true end",
  "the old login preference overrides a deliberate new disable", ["test_workshop_optin.lua"])
m("workshop.optin.launcher-bypass", "!!!TwichUI/WorkshopLauncher.lua",
  "if not L.Enabled() then return false, \"EXPERIMENTAL_OFF\" end",
  "-- experimental load guard accidentally removed",
  "slash/preview loads bypass experimental consent", ["test_workshop_optin.lua"])
m("workshop.optin.observer-leak", "TwichUI_Workshop/Window.lua",
  "if W.Watch then W.Watch.Stop() end", "-- recipe observer left active",
  "disabling leaves profession events registered", ["test_workshop_optin.lua"])
m("workshop.optin.profile-bypass", "!!!TwichUI/WorkshopLauncher.lua",
  'R.Profiles.OnApply("views", "workshop-opt-in", L.Apply)',
  'R.Profiles.OnApply("views", "workshop-opt-in", L.Migrate)',
  "profile changes update consent without stopping loaded services", ["test_workshop_optin.lua"])
m("workshop.optin.preview-hooks", "TwichUI_Workshop/AuctionButton.lua",
  "if wanted then AB.Start() end", "AB.Start()",
  "resuming a preview-only load attaches controls to Blizzard AH", ["test_workshop_optin.lua"])
m("workshop.optin.read-listener-leak", "TwichUI_Workshop/Window.lua",
  "if W.AuctionReads then W.AuctionReads.Stop() end", "-- transport listeners left active",
  "disabling leaves native read-transport callbacks registered", ["test_workshop_optin.lua"])


# M1b external data validation: only disposable synthetic state is mutated.
m("market.bridge.work-cap", "TwichUI_Workshop/Bridge.lua", "RESUMES=512", "RESUMES=1024",
  "a nonadvancing clock admits twice the bounded work", ["test_workshop_bridge_performance.lua"])
m("market.bridge.clockless-work", "TwichUI_Workshop/Bridge.lua",
  "and B.RESUMES or 32", "and B.RESUMES or 512",
  "a missing clock expands unmeasured synchronous work", ["test_workshop_bridge_performance.lua"])
m("market.bridge.elapsed-budget", "TwichUI_Workshop/Bridge.lua",
  "clock()-start>=budget", "false",
  "cooperative work ignores its elapsed time budget", ["test_workshop_bridge_performance.lua"])
m("market.bridge.range-direction", "TwichUI_Workshop/Bridge.lua",
  "elseif key<variant then", "elseif key>variant then",
  "binary lookup loses exact variants in a sorted range", ["test_workshop_bridge_performance.lua"])
m("market.bridge.range-isolation", "TwichUI_Workshop/Bridge.lua",
  "first+active.variantCounts[item]-1", "#active.variantKeys",
  "variant lookup can cross into another item's records", ["test_workshop_bridge_performance.lua"])
m("market.bridge.quote-fast-escape", "TwichUI_Workshop/BridgeCodec.lua",
  "if #s<=128 and not s:find(", "if #s<=128 or not s:find(",
  "short unsafe strings bypass canonical escaping", ["test_workshop_bridge_performance.lua"])
m("market.bridge.sha-choice", "TwichUI_Workshop/BridgeCodec.lua",
  "bxor(g,band(e,bxor(f,g)))", "bxor(g,bor(e,bxor(f,g)))",
  "an incorrect equivalent boolean formula corrupts SHA-256", ["test_workshop_bridge.lua"])
m("market.bridge.encoding-depth", "TwichUI_Workshop/BridgeCodec.lua",
  "if level>12 then fail() end", "if level>14 then fail() end",
  "the canonical encoder silently raises its depth bound", ["test_workshop_bridge_performance.lua"])
m("market.bridge.generation-integrity","TwichUI_Workshop/Bridge.lua","bodyHash:Finish()==h.generation_id","true","a generation identity no longer binds every source record", ["test_workshop_bridge.lua"])
m("market.bridge.identity-order","TwichUI_Workshop/Bridge.lua","requireData(r.item_id>lastItem or r.item_id==lastItem and r.variant_key>lastVariant)","requireData(true)","duplicate exact variants overwrite the imported index", ["test_workshop_bridge.lua"])
m("market.bridge.history-window","TwichUI_Workshop/Bridge.lua","math.max(ctx.from,ctx.today-days+1)","ctx.from","a selected history window includes older dates", ["test_workshop_bridge.lua"])
m("market.bridge.local-history","TwichUI_Workshop/Bridge.lua","active=value;cache,order={},{}","TwichUIWorkshopDB.markets={};active=value;cache,order={},{}","an import overwrites original local scans", ["test_workshop_bridge.lua"])
m("market.bridge.duplicate-json","TwichUI_Workshop/BridgeCodec.lua","if out[k]~=nil then fail() end","if false then fail() end","duplicate keys silently replace validated fields", ["test_workshop_bridge.lua"])
m("market.bridge.integer-range","TwichUI_Workshop/BridgeCodec.lua","if #abs>16 or (#abs==16 and abs>'9007199254740991') then fail() end","if false then fail() end","JSON integers round through the Lua exact-number boundary", ["test_workshop_bridge.lua"])
m("market.auction.metadata-restarts", "TwichUI_Workshop/auction/BrowseData.lua",
  '    D.Count("metadata")', '    D.Count("metadata");p.stamp=nil',
  "late item metadata invalidates the whole catalog again, causing endless completed-job restarts",
  ["test_workshop_auction_stability.lua"])
m("market.auction.metadata-insert-order", "TwichUI_Workshop/auction/BrowseData.lua",
  'if D.Less(r,row,opt) then', 'if not D.Less(r,row,opt) then',
  "a late filtered item is inserted in reverse price order in the retained result list",
  ["test_workshop_auction_stability.lua"])
m("market.auction.visible-row-ignored", "TwichUI_Workshop/auction/Components.lua",
  "updates[row.data.item]", "updates[-1]", "changed metadata never reaches its pooled visible row",
  ["test_workshop_auction_stability.lua"])

SELL_PREP="TwichUI_Workshop/auction/SellData.lua"
SELL_TEST=["test_workshop_auction_sell.lua"]
m("market.sell.gold-scale", SELL_PREP, "local total=nums[1]*10000+nums[2]*100+nums[3]",
  "local total=nums[1]*1000+nums[2]*100+nums[3]", "gold is converted at the wrong denomination", SELL_TEST)
m("market.sell.silver-range", SELL_PREP, "not W.Int(nums[2],0,99)", "not W.Int(nums[2],0,100)",
  "an out-of-range silver field is silently accepted", SELL_TEST)
m("market.sell.native-max", SELL_PREP, "math.min(row.qty,row.available or row.qty)",
  "math.max(row.qty,row.available or row.qty)", "Max exceeds the available native count or combines stacks", SELL_TEST)
m("market.sell.old-epoch", SELL_PREP, "Q.epoch==ctx.epoch", "true",
  "a competition price remains copyable after the auctioneer epoch changes", SELL_TEST)
m("market.sell.unknown-owner", SELL_PREP, "and r.ownershipKnown==true", "",
  "unknown ownership flags are treated as a verified external competitor", SELL_TEST)
m("market.sell.partial-complete", SELL_PREP, '="live",snap.complete,snap.at', '="live",true,snap.at',
  "a partial response is promoted to complete and supplies draft prices", SELL_TEST)
m("market.sell.deposit-is-fee", SELL_PREP,
  'result.valid=true;result.reason="Preparation only · posting awaits client acceptance."',
  'result.net=result.gross-(result.deposit or 0);result.valid=true;result.reason="Preparation only · posting awaits client acceptance."',
  "unknown commission and refundable-deposit treatment become a fabricated net estimate", SELL_TEST)
m("market.sell.foreign-row", SELL_PREP, "if r==tier and r.copy then", "if r.copy then",
  "a price from outside the selected competition result is accepted", SELL_TEST)
m("market.sell.variant-boolean", SELL_PREP, "r.variant=r.variantKind~=nil", "r.variant=r.variantKind",
  "a string variant flag bypasses the Facts boolean variant guard", SELL_TEST)
m("market.sell.caution-ignored", SELL_PREP, 'if flag=="belowusual" then', 'if flag=="never" then',
  "far-below-historical competition is automatically filled despite the existing caution flag", SELL_TEST)
m("market.sell.hidden-repaint", "TwichUI_Workshop/auction/ViewSell.lua",
  ' or not p:IsShown() or not A.IsShown() or A.Mode()~="sell"', '',
  "a delayed native text event resurrects market references after Sell is hidden", SELL_TEST)


m("market.sell.deferred-provenance", "TwichUI_Workshop/auction/ViewSell.lua",
  " and p.money:GetCopper()~=p.filledPrice", "",
  "deferred programmatic money callbacks erase the matched price provenance and selection", SELL_TEST)
m("market.sell.deposit-precision", SELL_PREP, "amount=math.ceil(amount/100)*100", "amount=amount",
  "a whole-silver auctioneer displays the unrounded copper deposit instead of the native upfront cost", SELL_TEST)
m("market.sell.deposit-unknown-precision", SELL_PREP, 'type(row.copper)=="boolean" and ', '',
  "unknown money precision is treated as a verified deposit quote", SELL_TEST)

# Integration: completed external catalogs and source-specific labels survive AH refilters/resizes.
m("market.bridge.catalog-reuse", "TwichUI_Workshop/ServerMarket.lua",
  "index=true,catalog=opt.catalog,item=focus", "index=true,item=focus",
  "external filtering rediscovers identities instead of retaining completed rows", ["test_workshop_auction_market_server.lua"])
m("market.bridge.resize-label", "TwichUI_Workshop/auction/ViewMarket.lua",
  'if p.projection then p.chart:Render() end',
  'if p.projection then p.chart:Set(p.projection.series,UI.Money) end',
  "resizing replaces external supply formatting and loses its observation caption", ["test_workshop_auction_market_server.lua"])

# Dormant M1a calculator: mutations exercise exact boundaries without enabling it.
m("market.canonical.half-anchor", "TwichUI_Workshop/PricingV1.lua",
  "if 2 * p >= anchor then eligible = eligible + tiers[p] base = base or p end",
  "if 2 * p > anchor then eligible = eligible + tiers[p] base = base or p end",
  "an exactly half-anchor tier disappears from eligible band quantity", ["test_workshop_pricing_v1.lua"])
m("market.canonical.historical-minimum", "TwichUI_Workshop/PricingV1.lua",
  "local m, h = Median(mv), #hv >= 3 and Median(hv) or nil",
  "local m, h = Median(mv), #hv >= 2 and Median(hv) or nil",
  "two dates incorrectly establish canonical Historical Value", ["test_workshop_pricing_v1.lua"])
m("market.canonical.rounding-range", "TwichUI_Workshop/PricingV1.lua",
  'if sum > floor((SAFE - got) / 2) then return nil, "numeric_range" end',
  'if false then return nil, "numeric_range" end',
  "doubling the band accumulator silently loses exact rounding", ["test_workshop_pricing_v1.lua"])


# ===============================================================================================================
# MARKET AND PRICING: the batch (cheapest price per item), history, statistics, quotes and the craft estimate
# ===============================================================================================================
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
  "            local cost = self:Make(id)\n            work, self.stepTiers",
  "            if left > 1 then local cost = self:Make(id) end\n            local cost = 0\n            work, self.stepTiers",
  "the last item of every build step is skipped: a market of more than one step silently loses items at the step boundaries", [PRICES_TESTS])
m("market.batch.stepped-ranking-shifted", PRICES,
  "            local cost = self:Make(ids[self.at])",
  "            local cost = self:Make(ids[self.at + 1])",
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

# --- A3: the price distribution (Dist.lua) and its collection (Prices.lua, Scan.lua) -----------------------------------------------
DIST = "TwichUI_Workshop/Dist.lua"
DIST_TESTS = "test_workshop_dist.lua"
SCAN = "TwichUI_Workshop/Scan.lua"
m("market.dist.anchor-at-or-above", DIST, "if not a and c4 > t then a = p end", "if not a and c4 >= t then a = p end",
  "the anchor is the first price AT a quarter of the items instead of strictly more than a quarter: thin markets anchor on the cheapest price", [DIST_TESTS], smoke=True)
m("market.dist.band-size", DIST, "local base, want = ps[first], eligible * 3", "local base, want = ps[first], eligible * 4",
  "the band is the cheapest 40% instead of 30% of the eligible items", [DIST_TESTS], smoke=True)
m("market.dist.low-filter-off", DIST, "while ps[first] * 2 < a do first = first + 1 end", "while ps[first] * 2 < 0 do first = first + 1 end",
  "the half-the-anchor filter is gone: a handful of cheap bait listings pull the Recent Price down", [DIST_TESTS], smoke=True)
m("market.dist.low-filter-boundary", DIST, "while ps[first] * 2 < a do first = first + 1 end", "while ps[first] * 2 <= a do first = first + 1 end",
  "a price of exactly half the anchor is ignored instead of kept", [DIST_TESTS])
m("market.dist.tier-order-reversed", PRICES, "    table.sort(ps)\n    local shift = D.SHIFT",
  "    table.sort(ps, function(x, y) return x > y end)\n    local shift = D.SHIFT",
  "the tiers are written dearest first: tier 1 is no longer the minimum", [DIST_TESTS])
m("market.dist.tier-quantity-lost", PRICES, "        m[unit] = v + count * D.SHIFT + 1", "        m[unit] = v + 1",
  "a second listing at a known price adds a listing but none of its items", [DIST_TESTS])
m("market.dist.new-tier-quantity-lost", PRICES, "        m[unit] = count * D.SHIFT + 1\n    end\nend", "        m[unit] = 1\n    end\nend",
  "a listing at a new price enters its tier as one item instead of its stack", [DIST_TESTS])
m("market.dist.second-price-quantity-lost", PRICES, "m = { [u0] = a.t * D.SHIFT + a.l, [unit] = count * D.SHIFT + 1 }", "m = { [u0] = a.t * D.SHIFT + a.l, [unit] = 1 }",
  "the listing that starts the second tier arrives with one item instead of its stack", [DIST_TESTS])
m("market.dist.first-tier-lost", PRICES, "m = { [u0] = a.t * D.SHIFT + a.l, [unit] = count * D.SHIFT + 1 }", "m = { [u0] = a.l, [unit] = count * D.SHIFT + 1 }",
  "the items of the first tier are forgotten when the second price arrives", [DIST_TESTS])
m("market.dist.tail-listings-wrong", DIST, "tq, tl = tq + qs[k], tl + ls[k]", "tq, tl = tq + qs[k], tl + 1",
  "the tail counts one listing per price instead of the listings in it", [DIST_TESTS])
m("market.dist.largest-listing-smallest", PRICES, "        m[-unit] = count > w and count or w", "        m[-unit] = count < w and count or w",
  "the largest single listing of a tier is the smallest", [DIST_TESTS])
m("market.dist.largest-listing-first-lost", PRICES, "        if not w then w = (v - v % D.SHIFT) / D.SHIFT end", "        if not w then w = 1 end",
  "the first listing of a tier is forgotten when the second arrives: its stack never counts as the largest", [DIST_TESTS])
m("market.dist.largest-listing-first-price", PRICES, "            if not w then w = a.t end              -- one listing so far: all its items", "            if not w then w = 1 end",
  "the same before the item has a second price", [DIST_TESTS])
m("market.dist.largest-listing-not-carried", PRICES, "        if w then m[-u0] = w end", "",
  "when the second price arrives, the first tier's largest listing is dropped", [DIST_TESTS])
m("market.dist.round-down", DIST, "local r = base + floor((2 * sum + got) / (2 * got))", "local r = base + floor((2 * sum) / (2 * got))",
  "the Recent Price is rounded down instead of half up", [DIST_TESTS])
m("market.dist.quartile-weight", DIST, "if not q75 and c4 >= t * 3 then q75 = p break end", "if not q75 and c4 >= t * 2 then q75 = p break end",
  "the upper quartile is read at two thirds of the items", [DIST_TESTS])
m("market.dist.median-rank", DIST, "if not q50 and cum * 2 >= t then q50 = p end", "if not q50 and cum * 2 > t then q50 = p end",
  "the median is read strictly past half the items (a different percentile definition)", [DIST_TESTS])
m("market.dist.near-limit", DIST, "if ps[k] * 10 > limit then break end", "if ps[k] * 10 >= limit then break end",
  "supply at exactly 110% of the Recent Price is not counted as near it", [DIST_TESTS])
m("market.dist.step-budget-ignored", PRICES, "        while left > 0 and work > 0 do\n            id = next(acc, id)", "        while left > 0 do\n            id = next(acc, id)",
  "a finalization step is limited by items only: a market of many price tiers does all its sorting in one frame", [DIST_TESTS])
m("market.dist.packing-limit-ignored", PRICES, "if tier and self.used > D.MAX_RECORDS then self.distBad, tier = \"records\", false end", "",
  "more records than a packed tier can count are accumulated anyway: the listings carry into the items", [DIST_TESTS])
m("market.dist.stale-kept-when-new-fails", PRICES, "    if snap.alg then m.dist = self.dist end", "    m.dist = self.dist or (self.oldRaw and self.oldRaw.dist)",
  "a scan whose distribution failed keeps the previous scan's: it describes listings that are gone", [DIST_TESTS])
m("market.dist.stale-carried-over", PRICES, "for _, k in ipairs({ \"h2\", \"c2\", \"compact\" }) do", "for _, k in ipairs({ \"dist\", \"h2\", \"c2\", \"compact\" }) do",
  "the old scan's distribution overwrites the new one (the A2 carry-forward left in place for dist)", [DIST_TESTS])
m("market.dist.alg-never-set", PRICES, "if self.distOk == true then snap.alg = D.ALG end", "if self.distOk == true then snap.alg = nil end",
  "the snapshot never says which algorithm made its distribution", [DIST_TESTS])
m("market.dist.alg-wrong", PRICES, "if self.distOk == true then snap.alg = D.ALG end", "if self.distOk == true then snap.alg = 2 end",
  "the snapshot names the wrong algorithm", [DIST_TESTS])
m("market.dist.alg-claimed-without-evidence", PRICES, "if self.distOk == true then snap.alg = D.ALG end", "if scan.items then snap.alg = D.ALG end",
  "the snapshot claims algorithm 1 evidence for every scan, including one whose distribution failed", [DIST_TESTS])
m("market.dist.commit-check-skipped", PRICES, "            if not d then self.distOk = false break end\n", "            if not d then d = { r = nil } end\n",
  "a distribution is saved without being checked against the scan's minimum entries", [DIST_TESTS])
m("market.dist.agrees-ignores-price", PRICES, "return (d ~= nil and d.min == tonumber(p) and", "return (d ~= nil and",
  "an entry that starts at another price than the item's minimum is accepted", [DIST_TESTS])
m("market.dist.agrees-ignores-totals", PRICES, "and d.l == tonumber(l) and d.t == tonumber(t)", "",
  "an entry whose items and listings are not the item's is accepted (another item's entry)", [DIST_TESTS])
m("market.dist.finalize-after-cancel", SCAN, "            local function Build()\n                if mine ~= token or g ~= gen or SC.phase ~= \"reading\" then return end",
  "            local function Build()\n                if false then return end",
  "the finalization timer of a scan that ended (or was replaced by a new one) goes on building and saves for it", [DIST_TESTS, PRICES_TESTS])
m("market.dist.observation-snapshot-unchecked", PRICES, "    if snap.at ~= info.at then return nil, \"inconsistent\" end\n", "",
  "the observation mixes a snapshot with a market it does not belong to", [DIST_TESTS])
m("market.dist.single-price-reported-missing", PRICES, "        if lk.next then return nil, \"missing\" end", "",
  "an item that should have a distribution entry but has none is reported as single-priced", [DIST_TESTS])

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

# ===============================================================================================================
# CRAFTING: materials, stock, shopping, make-versus-buy, Opportunities
# ===============================================================================================================
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


# --- the multilevel crafting planner (P1, CraftPlanner.lua): combined demand, owned stock, batches, circles, choices, ranges, the search ------
PLANNER = "TwichUI_Workshop/CraftPlanner.lua"
CPT = "test_workshop_craftplanner.lua"
m("crafting.planner.late-demand-lost", PLANNER, "if pos[j] <= pos[k] then again = true end", "",
  "demand that reaches an item after it was already decided is dropped: the combined demand is split, the first consumer's share alone is acquired", [CPT], smoke=True)
m("crafting.planner.delta-not-incremental", PLANNER, "local delta = c - crafted[k]", "local delta = c",
  "when an item's demand grows, its reagents are added again for every craft instead of the new crafts only (reagents double counted)", [CPT])
m("crafting.planner.bags-counted-twice", PLANNER, "local owned = nd.bags + nd.bank + nd.guild\n", "local owned = nd.bags + nd.bank + nd.guild + nd.bags\n",
  "the bag count is applied once for the queue and again for the subcrafts: owned stock is spent twice", [CPT])
m("crafting.planner.queued-credit-ignored", PLANNER, "local net = d - min(d, nd.credit)\n    if nd.unknown then return net end", "local net = d\n    if nd.unknown then return net end",
  "what queued crafts make is not subtracted before crafting more of the item", [CPT])
m("crafting.planner.owned-free", PLANNER, "if nd.num then val = Value(o, nd.num, nd.den) e.owned = e.owned + val", "if nd.num then val = 0 e.owned = e.owned + val",
  "owned materials are valued at nothing, so a plan looks cheaper because the player already owns things", [CPT], smoke=True)
m("crafting.planner.owned-value-truncated", PLANNER, "local function Value(o, num, den) return floor((2 * o * num + den) / (2 * den)) end",
  "local function Value(o, num, den) return floor(o * num / den) end",
  "the value of owned items is truncated instead of rounded half up (a stack price over its size)", [CPT])
m("crafting.planner.crafts-rounded-down", PLANNER, "local c = ceil(r / ch.r.per)", "local c = floor(r / ch.r.per)",
  "crafts are rounded down: the plan makes fewer than it needs", [CPT])
m("crafting.planner.leftover-dropped", PLANNER, "used = d.rest, leftover = d.crafts * r.per - d.rest,", "used = d.rest, leftover = 0,",
  "the rest of the last craft is not reported as a leftover", [CPT])
m("crafting.planner.alternate-recipe-ignored", PLANNER, "if r and #nd.recipes >= L.candidates then", "if r and #nd.recipes >= 1 then",
  "only the first usable recipe of an item is ever compared", [CPT])
m("crafting.planner.circle-accepted", PLANNER, "if circle then return { ok = false, why = \"circular\", cycle = circle } end", "",
  "crafts that need each other are accepted once their demand stops growing (a 3-per-craft circle looks free)", [CPT])
m("crafting.planner.self-recipe-accepted", PLANNER, "if sum[item] then return nil, \"circular\" end", "",
  "a recipe that uses its own output is offered as a way to make it", [CPT])
m("crafting.planner.order-ignores-prerequisites", PLANNER, "for _, it in ipairs(st.after) do if not done[stepOf[it]] then ready = false break end end", "",
  "the crafts are listed by item number, so a craft can come before the craft that makes its reagent", [CPT])
m("crafting.planner.invalid-pick-honoured", PLANNER, "if (pick == \"vendor\" and nd.hasVendor) or (pick == \"auction\" and nd.hasAuction) then", "if true then",
  "a choice to buy from a source that does not exist is followed and becomes a step with no price", [CPT])
m("crafting.planner.unavailable-recipe-used", PLANNER, "if not ok then return nil, \"unavailable\" end", "",
  "a recipe the character cannot do is planned as a craft", [CPT])
m("crafting.planner.estimate-as-exact", PLANNER, "q.low, q.atMost = Num(c.low), Num(c.high)   -- \"at least low\"", "q.low, q.high = Num(c.low), Num(c.low)   -- \"at least low\"",
  "an auction 'at least' figure is reported as the exact total, so the plan's upper bound is not open", [CPT])
m("crafting.planner.high-from-low", PLANNER, "if q.high and not e.open then e.cashHigh = e.cashHigh + q.high else e.open = true end",
  "if q.high and not e.open then e.cashHigh = e.cashHigh + q.low else e.open = true end",
  "the plan's upper bound adds the lower bounds: a whole-stack range collapses to its cheapest end", [CPT])
m("crafting.planner.unknown-as-zero", PLANNER, "e.cashMissing = e.cashMissing + 1", "e.cash = e.cash + 0",
  "a material with no price counts as costing nothing, so an unpriced route wins", [CPT], smoke=True)
m("crafting.planner.cash-as-economic", PLANNER, "e.econ = e.cash + e.owned", "e.econ = e.cash",
  "the economic cost leaves out owned materials: economic and cash cost are the same figure", [CPT])
m("crafting.planner.vendor-tie-to-auction", PLANNER, "if v and v.low and (not (a and a.low) or v.low <= a.low) then return v end",
  "if v and v.low and (not (a and a.low) or v.low < a.low) then return v end",
  "an equal vendor and auction price goes to the auction house", [CPT])
m("crafting.planner.tie-order-reversed", PLANNER, "if v[i] ~= w[i] then return v[i] < w[i] and -1 or 1 end", "if v[i] ~= w[i] then return v[i] > w[i] and -1 or 1 end",
  "of two plans that cost the same, the one making things (or using the later recipe) is preferred over buying", [CPT])
m("crafting.planner.prune-equal-bound", PLANNER, "if C.best and KeyCmp(P, e, C.best.e) > 0 then P.pruned", "if C.best and KeyCmp(P, e, C.best.e) >= 0 then P.pruned",
  "the search drops a branch whose bound only equals the best, losing an equal-cost plan that ranks first", [CPT])
m("crafting.planner.limited-called-proven", PLANNER, "if C.limited then s.exhaustive = false end", "",
  "a search that stopped at its limit is reported as exhaustive and its plan as the proven best", [CPT], smoke=True)
m("crafting.planner.budget-reserved-for-trivial-parts", PLANNER, "for _, C in ipairs(comps) do if C.decide > 0 then deciding = deciding + 1 end end", "for _, C in ipairs(comps) do deciding = deciding + 1 end",
  "every independent part keeps a share of the search states, even one with nothing to decide, so a large queue starves the part that has choices", [CPT])
m("crafting.planner.depth-one-too-deep", PLANNER, "if nd.depth < L.depth then", "if nd.depth <= L.depth then",
  "the depth limit lets one more level of crafting through", [CPT])

# --- the saved schema (market data foundation 2.0, A2): the version bump, the frozen legacy history, the 1.3 fields, the held database ----
SCHEMA = "test_workshop_schema.lua"
m("market.schema.version-not-bumped", PRICES,
  "if type(db.v) ~= \"number\" or db.v < PR.SAVED_VERSION then db.v = PR.SAVED_VERSION end",
  "if type(db.v) ~= \"number\" or db.v < PR.SAVED_VERSION then end",
  "a commit writes a format 3 market into a version-1 database: TwichUI 1.3 would not hold it and its next scan would drop the new fields", [SCHEMA])
m("market.schema.legacy-history-extended", PRICES, "PR.FEED_LEGACY_HISTORY = false", "PR.FEED_LEGACY_HISTORY = true",
  "a scan of format 3 keeps appending to the frozen minimum-price history, so legacy and version-2 history overlap", [SCHEMA])
m("market.schema.legacy-field-dropped", PRICES,
  "hn = self.oldCount + self.added - (self.dropped or 0), items = scan.items, hist = hist, sd = sd,",
  "hn = self.oldCount + self.added - (self.dropped or 0), items = scan.items, hist = hist,",
  "the new-format market forgets a field 1.3 reads (the scan days of the history)", [SCHEMA])
m("market.schema.newer-database-writable", PRICES, "return p ~= nil and type(p.v) == \"number\" and p.v > PR.SAVED_VERSION",
  "return p ~= nil and type(p.v) == \"number\" and p.v > PR.SAVED_VERSION + 1",
  "a database one version newer than this code is treated as its own and rewritten", [SCHEMA, "test_workshop_prices.lua"])
m("market.schema.apply-skips-held-check", PRICES, "    if self.phase ~= \"ready\" then return false, \"bad\" end\n    if PR.Held() then return false, \"held\" end",
  "    if self.phase ~= \"ready\" then return false, \"bad\" end",
  "a job begun before a newer version wrote the database is applied over it", [SCHEMA])
m("market.schema.future-containers-dropped", PRICES,
  "for _, k in ipairs({ \"h2\", \"c2\", \"compact\" }) do if type(raw[k]) == \"table\" then m[k] = raw[k] end end",
  "for _, k in ipairs({}) do if type(raw[k]) == \"table\" then m[k] = raw[k] end end",
  "a commit by this version silently discards history and budget records a later version wrote into the same database version", [SCHEMA])
m("market.schema.scan-log-unbounded", PRICES, "while #scans > PR.SCAN_LOG_MAX do table.remove(scans, 1) end", "",
  "the scan log grows without a bound", [SCHEMA])
m("market.schema.coverage-boundary-moves", PRICES, "local v2from = oldFull and old.v2from or day", "local v2from = day",
  "the first day of version-2 coverage is reset by every scan", [SCHEMA])
m("market.schema.version-bumped-before-build", PRICES, "    local market = BuildMarket(self, hist, sd)\n",
  "    if Store(false) then Store(false).v = PR.SAVED_VERSION end\n    local market = BuildMarket(self, hist, sd)\n",
  "the version is bumped before the market is built, so a failure while building leaves a version-2 database holding only old-format markets", [SCHEMA])


# --- version-2 history (market data foundation 2.0, A4): the ring, the daily points, the buckets, the commit, the chart API, the guard ------
HISTORY2 = "TwichUI_Workshop/History2.lua"
H2T = "test_workshop_history2.lua"
m("market.history2.ring-over-eight", HISTORY2, "    while #ring > H2.RING do table.remove(ring, 1) end",
  "    while #ring > H2.RING + 1 do table.remove(ring, 1) end", "the ring keeps nine observations instead of eight", [H2T], smoke=True)
m("market.history2.ring-reach-49h", HISTORY2, "    local cutoff = M - H2.RING_MINUTES", "    local cutoff = M - H2.RING_MINUTES - 60",
  "the ring's reach is 49 hours, not 48", [H2T])
m("market.history2.ring-reach-boundary", HISTORY2, "while ring[1] and ring[1].m + ring[1].dm < cutoff do", "while ring[1] and ring[1].m + ring[1].dm <= cutoff do",
  "an observation last seen exactly 48 hours back is dropped", [H2T])
m("market.history2.unchanged-min-only", HISTORY2,
  "if last and prevM and last.m + last.dm == prevM and last.p == o.p and last.r == o.r and last.t == o.t and last.l == o.l and last.pf == o.pf then",
  "if last and prevM and last.m + last.dm == prevM and last.p == o.p then",
  "the ring's unchanged rule compares the minimum only: a Recent Price or supply change is merged away", [H2T], smoke=True)
m("market.history2.unchanged-ignores-supply", HISTORY2, "and last.r == o.r and last.t == o.t and last.l == o.l", "and last.r == o.r and last.l == o.l",
  "a supply-only change is merged into the previous observation", [H2T])
m("market.history2.unchanged-ignores-partial", HISTORY2, "and last.l == o.l and last.pf == o.pf then", "and last.l == o.l then",
  "an observation from a scan lacking information is merged with a complete one", [H2T])
m("market.history2.unchanged-ignores-absence", HISTORY2, "if last and prevM and last.m + last.dm == prevM and last.p", "if last and last.p",
  "a scan that did not list the item is hidden inside a flat segment (identical values before and after)", [H2T])
m("market.history2.close-is-first-scan", HISTORY2, "    x.p, x.r, x.t, x.l = o.p, o.r, o.t, o.l\n", "\n",
  "a day's closing values are its first scan's, not its last", [H2T], smoke=True)
m("market.history2.day-low-overwritten", HISTORY2, "    if o.p < x.plo then x.plo = o.p end", "    x.plo = o.p",
  "a later scan replaces the day's lowest minimum, so a dip that day is lost", [H2T])
m("market.history2.day-high-overwritten", HISTORY2, "        if not x.rhi or o.r > x.rhi then x.rhi = o.r end", "        x.rhi = o.r",
  "a later scan replaces the day's highest Recent Price, so a spike that day is lost", [H2T])
m("market.history2.day-supply-low-lost", HISTORY2, "    if o.t < x.tlo then x.tlo = o.t end", "",
  "the day's fewest items are not updated by later scans", [H2T])
m("market.history2.fold-too-early", HISTORY2, "function H2.FoldBefore(today) return 7 * floor((today - 29) / 7) end",
  "function H2.FoldBefore(today) return 7 * floor((today - 22) / 7) end", "weeks fold before every day of the last 30 is safe", [H2T])
m("market.history2.fold-crosses-weeks", HISTORY2, "while days[i] and days[i].d < before and floor(days[i].d / 7) == w do",
  "while days[i] and days[i].d < before do", "one weekly bucket swallows the days of every week being folded", [H2T])
m("market.history2.merge-unweighted", HISTORY2, "    into.pm = Mean(into.pm * into.n + w.pm * w.n, n)", "    into.pm = Mean(into.pm + w.pm, 2)",
  "a two-week mean is the plain mean of two weekly means, ignoring how many days each holds", [H2T])
m("market.history2.recent-mean-by-days", HISTORY2, "    if b.nr > 0 then b.rm = Mean(sr, b.nr) end", "    if b.nr > 0 then b.rm = Mean(sr, b.n) end",
  "a week's Recent Price mean divides by every observed day, counting days without a Recent Price as zero", [H2T])
m("market.history2.merge-early", HISTORY2, "if b.s == 7 and 14 * floor(b.k / 2) + 13 < T - H2.WEEKLY_DAYS then", "if b.s == 7 and b.k * 7 + 6 < T - H2.WEEKLY_DAYS then",
  "a week merges into a two-week bucket while its partner week is still weekly", [H2T])
m("market.history2.expiry-boundary", HISTORY2, "while bks[1] and BucketEnd(bks[1]) < T - H2.RETAIN_DAYS do", "while bks[1] and BucketEnd(bks[1]) <= T - H2.RETAIN_DAYS do",
  "a bucket ending exactly 120 days back is dropped", [H2T])
m("market.history2.fast-path-unchecked-days", HISTORY2, "    if sum ~= newest then return nil end", "",
  "the append path appends to a string whose day sequence does not add up (a damaged string)", [H2T])
m("market.history2.guard-touches-recent-days", HISTORY2, "if T - x.d >= H2.PROTECT_DAYS and x.n >= 2 and not x.cf and Moved(x) then",
  "if x.n >= 2 and not x.cf and Moved(x) then", "the budget guard condenses the ranges of the last 14 days too", [H2T])
m("market.history2.guard-folds-recent-weeks", HISTORY2, "changed = FoldDays(days, bks, 7 * floor((T - H2.PROTECT_DAYS + 1) / 7))",
  "changed = FoldDays(days, bks, 7 * floor((T + 1) / 7))", "the budget guard folds a sparse item's protected last 14 days", [H2T])
m("market.history2.cut-scans-recorded", PRICES, "    if not WholeRead(scan) or not day then return nil, \"incomplete\" end",
  "    if not day then return nil, \"incomplete\" end", "a cut or count-changed scan is recorded into the history", [H2T, SCHEMA], smoke=True)
m("market.history2.unknown-recent-is-min", PRICES, "if r == nil and not (nx and nx > p) then r = p end", "if r == nil then r = p end",
  "an item with a second price but no checked distribution is recorded with Recent Price = minimum", [H2T], smoke=True)
m("market.history2.future-format-written", PRICES, "    if hi and hi.state == \"future\" then return nil, \"format\" end\n", "\n",
  "a later build's history format is rewritten by this one", [H2T, SCHEMA])
m("market.history2.clock-back-recorded", PRICES, "    if hi and hi.at and at < hi.at then return nil, \"clock\" end\n", "\n",
  "a scan dated before the newest recorded one is recorded (history reordered)", [SCHEMA, H2T])
m("market.history2.day-fed-flag-on-any-whole", PRICES, "+ (partial and D_PARTIAL or 0) + (fed and D_FED or 0)", "+ (partial and D_PARTIAL or 0) + (whole and D_FED or 0)",
  "the day log says a day was recorded whenever a whole read happened, so a chart says 'not listed' without evidence", [H2T])
m("market.history2.guard-skips-step", PRICES, "                self.cstep, self.csub = step + 1, \"h\"", "                self.cstep, self.csub = step + 2, \"h\"",
  "the budget guard jumps from step 1 to step 3 (out of the approved order)", [H2T])
m("market.history2.guard-never-runs", PRICES, "    return self.hbytes > PR.HISTORY_BUDGET or self.hbytes + self.rec.others > PR.ACCOUNT_BUDGET",
  "    return false", "the budget is never checked", [H2T])
m("market.history2.commit-writes-saved-table", PRICES,
  "            Keep(self, id, a, b)\n            st[path] = st[path] + 1\n            left = left - (path == \"fast\"",
  "            Keep(self, id, a, b)\n            if oldH2 then oldH2[id] = a end\n            st[path] = st[path] + 1\n            left = left - (path == \"fast\"",
  "the history phase writes each new string into the saved table at once: a failing or dropped commit leaves part of the scan saved", [H2T], smoke=True)
m("market.history2.stale-job-applied", PRICES, "    if self.oldRaw ~= self.beginRaw then return false, \"changed\" end\n", "\n",
  "a job begun before another commit of the same market is applied over it, undoing that commit", [H2T])
m("market.history2.legacy-in-recent", MARKET, "    if metric == \"min\" and src.legacy then", "    if (metric == \"min\" or metric == \"recent\") and src.legacy then",
  "the Recent Price series is filled from the legacy minimum history", [H2T], smoke=True)
m("market.history2.legacy-double-counted", MARKET, "            local limit = (recordedFrom or (today + 1)) - 1", "            local limit = today",
  "legacy minimum days after version-2 recording began are shown beside the version-2 days (counted twice)", [H2T])
m("market.history2.unlisted-without-evidence", MARKET, "            if Bit(f, DF.FED) then return \"unlisted\" end", "            if Bit(f, DF.WHOLE) then return \"unlisted\" end",
  "a day whose whole read was not recorded is called 'scanned, not listed'", [H2T])
m("market.history2.point-without-evidence", MARKET,
  "            local v, lo, hi = Pick(x, metric)\n            if v or lo then", "            local v, lo, hi = Pick(x, metric)\n            if true then",
  "a day with no Recent Price evidence still gets a (valueless) chart point", [H2T])

# --- (A5) the valuation services: Market Value, Historical Value, Range, Quality, Posture, TrendOf, Competition, Cost, the cache ----------------
VALUATION = "TwichUI_Workshop/Valuation.lua"
VAL = "test_workshop_valuation.lua"
m("market.value.age-weights-shifted", VALUATION,
  "function V.MarketWeight(age) if age <= 2 then return 4 end if age <= 6 then return 2 end return 1 end",
  "function V.MarketWeight(age) if age <= 3 then return 4 end if age <= 6 then return 2 end return 1 end",
  "a 3-day-old observation weighs as much as today's (the weight bands are off by a day)", [VAL], smoke=True)
m("market.value.weights-ignored", VALUATION,
  "function V.MarketWeight(age) if age <= 2 then return 4 end if age <= 6 then return 2 end return 1 end",
  "function V.MarketWeight(age) return 1 end", "Market Value becomes a plain median: recent days no longer weigh more", [VAL])
m("market.value.median-strict-half", VALUATION, "        if 2 * cum >= total then return vs[i], total end",
  "        if 2 * cum > total then return vs[i], total end",
  "the weighted median needs MORE than half the weight, so an exact half boundary picks the next value", [VAL], smoke=True)
m("market.value.window-15-days", VALUATION, "        if age >= 0 and age < V.MV_DAYS then\n            listed = listed + 1",
  "        if age >= 0 and age <= V.MV_DAYS then\n            listed = listed + 1", "Market Value counts a 14-day-old observation (15 days)", [VAL])
m("market.value.unknown-recent-is-min", VALUATION,
  "            if x.r then\n                n = n + 1\n                VS[n], WS[n] = x.r, V.MarketWeight(age)",
  "            if x.r or x.p then\n                n = n + 1\n                VS[n], WS[n] = x.r or x.p, V.MarketWeight(age)",
  "a day without a known Recent Price votes with its minimum instead (missing evidence replaced by another metric)", [VAL], smoke=True)
m("market.value.bucket-weight-by-days", VALUATION, "            VS[n], WS[n] = b.rm, b.nr", "            VS[n], WS[n] = b.rm, b.n",
  "a bucket's Recent Price mean weighs every observed day, also the days without a Recent Price (n instead of nr)", [VAL], smoke=True)
m("market.value.bucket-edge-ignored", VALUATION, "    return ov, ov == span or 2 * ov >= span", "    return ov, ov > 0",
  "a bucket counts whole as soon as one of its days is inside the window (the window boundary ignored)", [VAL])
m("market.value.aggregate-as-exact", VALUATION, "        r.aggregate, r.approximate, r.complete = v.aggregate, v.aggregate, not v.partial",
  "        r.aggregate, r.approximate, r.complete = false, false, not v.partial", "a Historical Value built from weekly means is presented as exact days", [VAL])
m("market.value.historical-two-days", VALUATION, "V.HV_MIN_DAYS = 3 ", "V.HV_MIN_DAYS = 2 ",
  "Historical Value is given from two observed days", [VAL])
m("market.value.quality-days-window-ignored", VALUATION, "    for _, x in ipairs(days) do if x.d >= qfrom and x.d <= today then obs = obs + 1 end end",
  "    for _, x in ipairs(days) do if x.d <= today then obs = obs + 1 end end", "Data Quality counts observed days older than 30 as 'this month'", [VAL])
m("market.value.quality-fair-two-listings", VALUATION, "V.GOOD_LISTINGS, V.FAIR_LISTINGS = 5, 3", "V.GOOD_LISTINGS, V.FAIR_LISTINGS = 5, 2",
  "the fair threshold is weakened to two listings", [VAL])
m("market.value.quality-mixed-fair", VALUATION, "\"Several economically distinct item variants may be mixed.\", true)",
  "\"Several economically distinct item variants may be mixed.\", false)", "mixed variants keep an item from good but allow fair", [VAL])
m("market.value.variants-unknown-quality-safe", VALUATION, "    if q ~= nil and q < 2 then return false end", "    if q == nil or q < 2 then return false end",
  "a weapon or armor whose quality is not loaded is treated as having no variants", [VAL])
m("market.value.posture-on-minimum", VALUATION, "    local cur, cwhy = SnapshotValue(cx, \"recent\")", "    local cur, cwhy = SnapshotValue(cx, \"min\")",
  "posture compares the cheapest listing (possibly a bait) with the Historical Value", [VAL], smoke=True)
m("market.value.posture-cheap-boundary", VALUATION, "    if 100 * c < V.POSTURE_LOW * h then", "    if 100 * c <= V.POSTURE_LOW * h then",
  "exactly 85% of Historical Value is called cheap", [VAL])
m("market.value.posture-expensive-boundary", VALUATION, "    elseif 100 * c > V.POSTURE_HIGH * h then", "    elseif 100 * c >= V.POSTURE_HIGH * h then",
  "exactly 115% of Historical Value is called expensive", [VAL])
m("market.value.posture-ignores-farbelow", VALUATION, "    if s and s.farbelow then Miss(\"farbelow\") end\n", "\n",
  "a thin market whose cheapest listing is far below the others can be called a bargain", [VAL])
m("market.value.trend-mixes-metrics", VALUATION, "        local v, age = x[field], today - x.d",
  "        local v, age = (today - x.d < half) and x[field] or x.p, today - x.d",
  "the older half of a Recent Price trend is read from the minimum (two metrics compared)", [VAL])
m("market.value.trend-flat-boundary", VALUATION, "    if 100 * math.abs(b - a) < V.FLAT_PERCENT * a then", "    if 100 * math.abs(b - a) <= V.FLAT_PERCENT * a then",
  "exactly 5% is called flat", [VAL])
m("market.value.competing-at-anchor", VALUATION, "        local under = 2 * t.p < d.a", "        local under = t.p < d.a",
  "the competing price is the anchor itself instead of the cheapest price at or above half of it", [VAL])
m("market.value.cost-unlimited-at-minimum", VALUATION, "        if rem <= t.q then\n            low = base + rem * t.p",
  "        if true then\n            low = base + rem * t.p", "the whole quantity is costed at the cheapest price, as if it held unlimited items", [VAL], smoke=True)
m("market.value.cost-tier-off-by-one", VALUATION, "        if rem <= t.q then\n            low = base + rem * t.p",
  "        if rem < t.q then\n            low = base + rem * t.p", "a quantity that exactly empties a tier walks into the next one", [VAL])
m("market.value.cost-whole-listing-omitted", VALUATION, "                whole = rem + largest - 1\n", "                whole = rem\n",
  "the cost ignores that whole listings may have to be bought (no range, a false exact)", [VAL], smoke=True)
m("market.value.cost-equal-listings-rounding-lost", VALUATION, "whole = largest * floor((rem + largest - 1) / largest)", "whole = rem",
  "a tier of equal stacks is costed as if part of a stack could be bought", [VAL])
m("market.value.cost-equal-listings-assumed", VALUATION, "            if largest * t.l == t.q then", "            if true then",
  "every tier is assumed to hold equal stacks, so the over-buy of mixed stack sizes is understated", [VAL])
m("market.value.cost-beyond-at-sixth-price", VALUATION, "        low = base + rem * (p6 + 1)", "        low = base + rem * p6",
  "items beyond the six kept prices are costed at the sixth price, which they are known to exceed", [VAL])
m("market.value.cache-ignores-strings", VALUATION, "    if e and e.g and e.h2s == h2s and e.c2s == c2s and e.today == today then",
  "    if e and e.g and e.today == today then", "a cached digest is returned for strings that changed (a replaced history)", [VAL], smoke=True)
m("market.value.cache-ignores-day", VALUATION, "    if e and e.g and e.h2s == h2s and e.c2s == c2s and e.today == today then",
  "    if e and e.g and e.h2s == h2s and e.c2s == c2s then", "a cached digest is kept across a day rollover (weights and windows not moved)", [VAL])
m("market.value.cache-facts-ignore-entries", VALUATION, "    local f = e and e.f and e.ie == ie and e.de == de and e.f or nil",
  "    local f = e and e.f or nil", "cached snapshot facts (Recent Price, spread, flags) are used for an item whose saved entries changed", [VAL])
m("market.value.range-legacy-double-count", VALUATION, "            local limit = (r.recordedFrom or (today + 1)) - 1",
  "            local limit = today", "legacy minimum days after version-2 recording began are counted beside the version-2 days", [VAL])


# ===============================================================================================================
# CONSUMERS OF THE MARKET SERVICES (A7): Shopping over Market.Cost, MarketFacts
# ===============================================================================================================
A7T = "test_workshop_a7.lua"
SHOP, FACTS = "TwichUI_Workshop/Shopping.lua", "TwichUI_Workshop/MarketFacts.lua"
m("market.a7.range-shown-as-low", SHOP, 'return money(r.low) .. " to " .. money(r.high), "Auctions may require buying larger stacks."', 'return money(r.low), nil',
  "a purchase that may need whole stacks is shown as its cheapest possible total, as if it were certain", [A7T])
m("market.a7.estimate-shown-as-exact", SHOP, 'return "at least " .. money(r.low or cash), ', 'return money(r.low or cash), ',
  "a lower bound for a quantity beyond the six kept price tiers is shown as the total", [A7T])
m("market.a7.cost-not-memoised", SHOP, 'if c == nil then c = inp.cost(item, qty) or false memo[key] = c end', 'c = inp.cost(item, qty) or false',
  "every comparison of the sources decodes the item's price tiers again", [A7T])
m("market.a7.none-drops-legacy-price", SHOP, '        -- state "none": fall through to the unit-price quote', '        do return nil end\n        -- state "none": fall through to the unit-price quote',
  "an item of an older scan (no price tiers saved) loses its auction price when the quantity-aware cost has nothing to say", [A7T])
m("market.a7.cache-ignores-generation", FACTS, 'local stamp = W.Valuation.Generation(m) .. "|" .. floor(now / F.BUCKET)', 'local stamp = "x"',
  "a successful scan does not change the figures the Opportunities details and the tooltip show", [A7T])
m("market.a7.cache-ignores-time", FACTS, 'local stamp = W.Valuation.Generation(m) .. "|" .. floor(now / F.BUCKET)', 'local stamp = W.Valuation.Generation(m)',
  "a cached answer shows the age and freshness it had hours ago", [A7T])
m("market.a7.other-market-substituted", FACTS, '    if m == nil then return MK.Source().market end\n    if type(m) == "string" then return PR.Market(m) end',
  '    if m == nil then return MK.Source().market end\n    if type(m) == "string" then return PR.Market(m) or MK.Source().market end',
  "a market with no scan shows another auction house's figures", [A7T])

# ===============================================================================================================
# AUTOMATIC PRICE UPDATES (A6): the setting, the visit, the cooldown and backoff, the market, Stop and provenance
# ===============================================================================================================
AUTOT = "test_workshop_auto.lua"
AUTO, SCAN, WAUTO, SESSION = "TwichUI_Workshop/Auto.lua", "TwichUI_Workshop/Scan.lua", "!!!TwichUI/WorkshopAuto.lua", "TwichUI_Workshop/Session.lua"
m("market.auto.setting-ignored", WAUTO, 'function WA.Enabled() return WA.POLICY == "auto" and R.WorkshopLauncher and R.WorkshopLauncher.Enabled()\n    and R:Enabled("workshopAutoScan") end', 'function WA.Enabled() return WA.POLICY == "auto" and R.WorkshopLauncher and R.WorkshopLauncher.Enabled() end',
  "the Auction House opening loads the Workshop and scans although the player turned automatic updates off", [AUTOT], smoke=True)
m("market.auto.manual-policy-ignored", WAUTO, 'function WA.Enabled() return WA.POLICY == "auto" and R.WorkshopLauncher and R.WorkshopLauncher.Enabled()\n    and R:Enabled("workshopAutoScan") end', 'function WA.Enabled() return R.WorkshopLauncher and R.WorkshopLauncher.Enabled() and R:Enabled("workshopAutoScan") end',
  "the owner's manual-only decision is not honoured: a saved switch (or a later default) makes opening the Auction House load the Workshop and offer or start an update", [AUTOT], smoke=True)
m("market.auto.duplicate-visit", WAUTO, "    if open then return end                                          -- the same visit, said again\n", "",
  "the several events of one opening each count as a visit, so a visit is handled again and again", [AUTOT])
m("market.auto.stale-timer-loads", WAUTO, "    if id ~= visit or not open then return end                      -- a later visit, or the window closed: nothing\n",
  "    if false then return end\n", "a timer from a visit that has closed (or been replaced) still loads the Workshop and acts", [AUTOT])
m("market.auto.cooldown-bypassed", AUTO, "A.COOLDOWN = 3600 ", "A.COOLDOWN = 0 ",
  "a market scanned a minute ago is scanned again on the next opening (the 60-minute cooldown is gone)", [AUTOT], smoke=True)
m("market.auto.backoff-bypassed", AUTO, 'if c.backoffLeft and c.backoffLeft > 0 then return "skip", "backoff" end', "if false then end",
  "after the game refused an automatic request the next opening asks again at once", [AUTOT])
m("market.auto.wrong-market-freshness", AUTO, "local info = key and PR.Market(key) or nil", "local info = key and PR.Market(PR.Keys()[1] or key) or nil",
  "the other faction's (or another realm's) scan makes this auction house look fresh", [AUTOT])
m("market.auto.unknown-treated-supported", AUTO, 'if c.capability == "supported" then return "scan", "due" end', 'if c.capability ~= "click" then return "scan", "due" end',
  "an unverified capability starts the request by itself instead of asking for the click", [AUTOT], smoke=True)
m("market.auto.manual-gives-way", SCAN, "        if run.auto and SC.phase == \"waiting\" then End(\"interrupted\", \"busy\") end",
  "        if SC.phase == \"waiting\" then End(\"interrupted\", \"busy\") end",
  "a scan the player asked for is cancelled by another request, as only an automatic one should be", [AUTOT])
m("market.auto.stop-during-saving", SCAN, '    if SC.phase == "saving" then return false, "saving" end\n    End("interrupted", "stopped")',
  '    End("interrupted", "stopped")', "Stop is accepted while the accepted result is being saved, racing the apply", [AUTOT])
m("market.auto.provenance-lost", SCAN, "at = time(), auto = run.auto == true, complete", "at = time(), auto = false, complete",
  "an automatic scan is saved as a manual one", [AUTOT])
m("market.auto.manual-marked-automatic", SESSION, 'local auto = type(opts) == "table" and opts.auto == true', "local auto = true",
  "the player's own click is saved as an automatic scan", [AUTOT])
m("market.auto.refusal-not-remembered", AUTO, "    elseif SC.state == \"failed\" and SC.auto and key and REFUSED[SC.why] then\n        backoff[key] = A.mono() + A.BACKOFF",
  "    elseif SC.state == \"failed\" and SC.auto and key and REFUSED[SC.why] then\n        backoff[key] = nil", "a refused automatic request is forgotten, so the backoff never applies", [AUTOT])


# ===============================================================================================================
# EXAMINED AND LEFT OUT (equivalent mutants: no test can tell them from the original, so they would only ever "survive")
# ===============================================================================================================
#   Prices.Unit  `return math.max(q, 1)` -> `return q`: the round-up loop above it already lifts a zero to 1.
#   CraftPlanner.Consider  `VecCmp(v, b.v) >= 0` -> `> 0`: it differs only when the two plans' costs AND choice vectors are equal, i.e. the
#       same plan, so replacing it changes nothing observable.
#   Shopping.Suggest  dropping `(k ~= "make" or o.state == "ok")`: a make option that is not "ok" returns before it is given a cost, and
#       Suggest needs `o.cost`, so the guard never decides anything today (it is defence in depth if EvalMake ever sets a cost earlier).


# --- the strategy in the windows (P2, Strategy.lua, Session.lua's strategy part, Queue.AddBatch): words, jobs, the adapter and the confirmed batch ---------------
STRAT, SESSION, QUEUE = "TwichUI_Workshop/Strategy.lua", "TwichUI_Workshop/Session.lua", "TwichUI_Workshop/Queue.lua"
STU = "test_workshop_strategy.lua"
m("crafting.strategy.savings-certain-from-bounds", STRAT, "    if sv.confident then\n        return \"Savings\"", "    if sv.confident or (sv.lowerBounds and sv.lowerBounds > 0) then\n        return \"Savings\"",
  "a saving is called certain because the lower bounds differ, though the price ranges overlap", [STU])
m("crafting.strategy.verified-when-only-bounded", STRAT, "    if s.proven then return \"Best verified plan\", \"good\" end", "    if s.proven or s.exhaustive then return \"Best verified plan\", \"good\" end",
  "a plan whose search hit a graph limit is called verified", [STU])
m("crafting.strategy.open-range-as-total", STRAT, "    if lowerOnly or r.high == nil then return \"at least \" .. money(r.low) end", "    if lowerOnly then return \"at least \" .. money(r.low) end",
  "an upper bound that is open is shown as a range or a total instead of 'at least'", [STU])
m("crafting.strategy.old-job-for-new-key", STRAT, "    if s.key == key then\n        if s.state == \"planning\" and s.job then return \"planning\" end", "    if s.key ~= nil then\n        if s.state == \"planning\" and s.job then return \"planning\" end",
  "a running job is reused for a different input snapshot, so the page shows a plan made for something else", [STU])
m("crafting.strategy.other-slot-makes-stale", STRAT, "    if s.gen ~= mine then   -- a newer request of this slot", "    if mine ~= gen then   -- a newer request of this slot",
  "the stale check uses one global generation, so a request of another page drops this page's finished plan", [STU])
m("crafting.strategy.collect-quantity-lost", STRAT, "rows[#rows + 1] = { kind = \"collect\", item = c.item, where = c.where, qty = c.qty,", "rows[#rows + 1] = { kind = \"collect\", item = c.item, where = c.where, qty = 1,",
  "a Collect row names one item instead of the planned quantity", [STU])
m("crafting.strategy.reagent-buy-not-separated", STRAT, "row.short, row.qty, row.extra = short, qty, qty - short", "row.short, row.qty, row.extra = qty, qty, 0",
  "what is bought for made materials is shown as the queue's own shortage", [STU])
m("crafting.strategy.suggestion-follows-choice", STRAT, "    if not line.picked then return chosen end\n    return ctx.suggest and ctx.suggest[line.item] or nil", "    do return chosen end",
  "the suggestion is always the player's own choice, so a differing choice is never told apart", [STU])
m("crafting.strategy.final-recipe-first", STRAT, "if final then ops[#ops + 1] = { recipe = final.id, name = final.name, crafts = final.crafts or 1, produces = final.outItem, final = true } end",
  "if final then table.insert(ops, 1, { recipe = final.id, name = final.name, crafts = final.crafts or 1, produces = final.outItem, final = true }) end",
  "the recipe the player adds is queued before the crafts that make its materials", [STU])
# P2.1: where Show vendor points (Vendor.Places)
VPT = "test_workshop_vendor_places.lua"
m("crafting.vendor.priced-before-distance", VENDOR, "        if a.tier ~= b.tier then return a.tier < b.tier end\n        if a.yards", "        if a.priced ~= b.priced then return a.priced end\n        if a.tier ~= b.tier then return a.tier < b.tier end\n        if a.yards",
  "the merchant the price was seen at outranks a nearer seller (Undercity sent to Orgrimmar)", [VPT])
m("crafting.vendor.same-map-not-local", VENDOR, "((spot and spot.map ~= nil and e.m == spot.map) and 2 or 3)", "3",
  "with no position, a seller on the player's own map is not preferred", [VPT])
m("crafting.vendor.nearest-claimed-without-distance", VENDOR, "return out, (first.tier == 1 and \"nearest\") or", "return out, (first.tier <= 2 and \"nearest\") or",
  "a seller is called the nearest although no distance was compared", [VPT])
# P2.1: progress on the plan (Progress.lua) and its notices (Notice.lua)
PROGRESS, NOTICE, CMP = "TwichUI_Workshop/Progress.lua", "TwichUI_Workshop/Notice.lua", "test_workshop_compact.lua"
m("crafting.progress.duplicate-cast-counted", PROGRESS, "        if seen[key] then stats.duplicate = stats.duplicate + 1 return false, \"duplicate\" end\n", "",
  "a second event for the same cast takes a second craft off the queue", [CMP])
m("crafting.progress.auto-gate-ignored", PROGRESS, "    if not P.auto then return false, \"off\" end\n", "",
  "the game's unverified cast events change the queue although automatic counting is off", [CMP])
m("crafting.progress.other-unit-counted", PROGRESS, "if unit ~= \"player\" or type(castGUID)", "if type(castGUID)",
  "another unit's cast counts as the player's craft", [CMP])
m("crafting.notice.first-look-announced", NOTICE, "    if before == nil then Nt.Arm() return nil end", "    if before == nil then before = {} end",
  "opening the window (or a login) announces every recipe that is already ready", [CMP])
# P2.1: the simple price presentation and the buy-or-craft words
m("crafting.strategy.lower-bound-as-total", STRAT, "    return \"from \" .. money(r.low), tip", "    return money(r.low), tip",
  "the simple figure drops its 'from', so a range's lower bound reads as the total cost", [STU])
m("crafting.strategy.open-end-as-exact", STRAT, "    if r.high == nil then return \"at least \" .. money(r.low),", "    if r.high == nil then return money(r.low),",
  "an estimate with no known upper end is shown as an exact figure", [STU])
m("crafting.strategy.overlap-called-saving", STRAT, "            if a.compare == \"lower\" then\n                text = (\"%s costs %s more.\")",
  "            if a.compare ~= \"unknown\" then\n                text = (\"%s costs %s more.\")",
  "overlapping cost ranges are said to save a certain amount", [STU])
m("crafting.strategy.bags-not-in-key", SESSION, "bags[#bags + 1] = tostring(O.BagCount(m.item))", "bags[#bags + 1] = \"\"",
  "a plan is reused after the bags changed, because the key ignores what the bags hold", [STU])
m("crafting.strategy.apply-double-crafts", SESSION, "ops[#ops + 1] = { rec = r, crafts = c.crafts }", "ops[#ops + 1] = { rec = r, crafts = c.crafts * 2 }",
  "the confirmed plan queues more crafts than the preview listed", [STU])
m("crafting.queue.batch-keeps-new-entries", QUEUE, "        for i = #entries, size + 1, -1 do entries[i] = nil end\n", "",
  "a batch whose save fails leaves the new entries in the queue", [STU])
m("crafting.queue.batch-full-one-early", QUEUE, "    if #entries + fresh > W.MAX_QUEUE then return false, \"full\" end", "    if #entries + fresh >= W.MAX_QUEUE then return false, \"full\" end",
  "a batch that exactly fills the queue is refused as full", [STU])
m("crafting.queue.batch-raise-limit", QUEUE, "            if have.crafts + n > W.MAX_CRAFTS then return false, \"toomany\" end", "            if have.crafts + n >= W.MAX_CRAFTS then return false, \"toomany\" end",
  "an entry may not be raised to exactly the most crafts it holds", [STU])

# Settings 2.0: a preference that saves but is dropped at the queue/planner boundary.
m("crafting.settings.objective-not-forwarded", "TwichUI_Workshop/Session.lua",
  'Sg.Request("queue", key, function() return PlanInput(entries, byOut, view, src), { objective = S.Objective() } end)',
  'Sg.Request("queue", key, function() return PlanInput(entries, byOut, view, src), { objective = "economic" } end)',
  "the cash preference appears saved but Shopping still optimizes economic cost", ["test_workshop_strategy.lua"])

# A8: a listing suggestion may never substitute a historical valuation or stack total.
m("market.advisor.history-as-posting-price", "TwichUI_Workshop/Sell.lua",
  'r.state, r.price, r.ahead = "ok", c.competing, c.ahead',
  'r.state, r.price, r.ahead = "ok", f.mval and f.mval.value or c.competing, c.ahead',
  "historical market value silently replaces actual competing listings", ["test_workshop_advisor.lua"])
m("market.advisor.partial-price", "TwichUI_Workshop/Sell.lua",
  'or not c.complete or c.cut', 'or false or c.cut',
  "an incomplete scan is treated as sufficient for a competitive suggestion", ["test_workshop_advisor.lua"])
m("market.advisor.unit-total", "TwichUI_Workshop/Sell.lua",
  'price * qty, qty, price', 'price, qty, price',
  "gross return for a stack is reported as one item", ["test_workshop_advisor.lua"])

m("market.advisor.unknown-quantity", "TwichUI_Workshop/Advisor.lua",
  'elseif qty == nil then Reason', 'elseif false then Reason',
  "unknown bag quantities can receive a sale recommendation", ["test_workshop_advisor.lua"])
m("market.disenchant.unverified-table", "TwichUI_Workshop/Disenchant.lua",
  'snapshot and snapshot.verified == true and snapshot.client', 'snapshot and snapshot.client',
  "an unverified outcome table can be treated as verified Forever evidence", ["test_workshop_advisor.lua"])
m("market.disenchant.ignore-probability", "TwichUI_Workshop/Disenchant.lua",
  'o.p * m.qty * p.value', 'm.qty * p.value',
  "expected value counts every possible outcome as certain", ["test_workshop_advisor.lua"])
m("crafting.advisor.ignore-reservation", "TwichUI_Workshop/Advisor.lua",
  'elseif ctx.crafting and (ctx.crafting.reserved or 0) > 0 then', 'elseif false then',
  "materials needed by the active plan can be recommended for sale", ["test_workshop_advisor.lua"])

m("market.advisor.invented-gross-quantity", "TwichUI_Workshop/Advisor.lua",
  's.price and qty and qty > 0 and W.Sell.Proceeds(s.price, qty)',
  's.price and W.Sell.Proceeds(s.price, math.max(1, qty or 1))',
  "an absent or unknown stack is displayed with an invented one-item gross total", ["test_workshop_advisor.lua"])

# A8.1: tentative advice is a separate evidence role, never a posting/proceeds path.
m("market.advisor.tentative-age", "TwichUI_Workshop/Sell.lua",
  'c.age>W.Valuation.GOOD_AGE', 'c.age>W.Valuation.GOOD_AGE/3600',
  "seconds are compared to an hours threshold and valid recent observations are discarded", ["test_workshop_advisor.lua"])
m("market.advisor.tentative-history", "TwichUI_Workshop/Sell.lua",
  'value=c.competing,at=c.at,age=c.age,reasons=reasons',
  'value=f.mval and f.mval.value or c.competing,at=c.at,age=c.age,reasons=reasons',
  "historical valuation replaces the observed current listing", ["test_workshop_advisor.lua"])
m("market.advisor.tentative-gain", "TwichUI_Workshop/Advisor.lua",
  'observed.value-sell>=gain', 'observed.value-sell>=0',
  "tentative advice ignores the configured worthwhile gain", ["test_workshop_advisor.lua"])
m("market.advisor.tentative-margin", "TwichUI_Workshop/Advisor.lua",
  'observed.value>=sell*1.5', 'observed.value>=sell',
  "thin evidence bypasses the conservative vendor margin", ["test_workshop_advisor.lua"])
m("market.advisor.tentative-upgrade", "TwichUI_Workshop/Advisor.lua",
  '"auction","tentative","limited",observed', '"auction","supported","limited",observed',
  "an uncertain observation is promoted to supported Auction advice", ["test_workshop_advisor.lua"])
m("market.advisor.tentative-tooltip-upgrade", "TwichUI_Workshop/Advisor.lua",
  'function A.Tooltip(r) return "Workshop: " .. (r.level=="tentative"',
  'function A.Tooltip(r) return "Workshop: " .. (false',
  "the Normal tooltip loses the Possible qualification", ["test_workshop_advisor.lua"])

# AH-2 observation presentation: reuse normalization, preserve estimates and sort.
m("market.ah.value-not-multiplied", "TwichUI_Workshop/auction/BrowseData.lua",
  "W.Int(unit * qty, 1, W.Prices.MAX_COPPER)", "W.Int(unit, 1, W.Prices.MAX_COPPER)",
  "aggregate tier value shown as the price of one item", ["test_workshop_auction_browse.lua"])
m("market.ah.stored-actionable", "TwichUI_Workshop/auction/BrowseData.lua",
  'source = "stored", actionable = false', 'source = "stored", actionable = true',
  "saved history gains an actionable flag without a live listing", ["test_workshop_auction_browse.lua"])
m("market.ah.price-order-reversed", "TwichUI_Workshop/auction/BrowseData.lua",
  "return a.unit<b.unit", "return a.unit>b.unit",
  "Browse sorts expensive observations first despite its unit-price ordering", ["test_workshop_auction_browse.lua"])

# AH-3 presentation keeps the shared plan's quantities, uncertainty and state.
m("crafting.ah.quantities-swapped", "TwichUI_Workshop/auction/ShoppingData.lua",
  "need=row.need,have=row.have,missing=row.qty", "need=row.have,have=row.need,missing=row.qty",
  "required and bag quantities swapped in the integrated view", ["test_workshop_auction_shopping.lua"])
m("crafting.ah.missing-is-total", "TwichUI_Workshop/auction/ShoppingData.lua",
  "missing=row.qty", "missing=row.need",
  "the shopping view asks for all demand again instead of only the missing allocation", ["test_workshop_auction_shopping.lua"])
m("crafting.ah.stale-enabled", "TwichUI_Workshop/auction/ShoppingData.lua",
  'return "Updating plan · previous quantities may be stale",false', 'return "Updating plan · previous quantities may be stale",true',
  "stale quantities enable quantity-dependent preparation", ["test_workshop_auction_shopping.lua"])
m("crafting.ah.range-unqualified", "TwichUI_Workshop/auction/ShoppingData.lua",
  "return W.Strategy.CostText({low=row.low,high=row.high},money)", "return money(row.low)",
  "an uncertain cost lower bound is displayed as an exact amount", ["test_workshop_auction_shopping.lua"])
m("crafting.ah.unknown-requirements-as-ready", "TwichUI_Workshop/auction/ShoppingData.lua",
  "if P.Incomplete(plan,ctx) then", "if false then",
  "unread recipe requirements or bag counts are presented as fulfilled or fully priced", ["test_workshop_auction_shopping.lua"])

m("market.auction-draft-total", "TwichUI_Workshop/auction/SellData.lua",
  "result.gross,result.quantity,result.unit=proceeds.gross,quantity,price", "result.gross,result.quantity,result.unit=price,quantity,price",
  "preparation displays a single unit as gross proceeds for a multi-item draft",
  ["test_workshop_auction_reads.lua"])
m("market.auction-read-invalid-complete", "TwichUI_Workshop/auction/ReadRequests.lua",
  "complete=api.HasFullItemSearchResults(p.arg) and count<=Q.MAX and #rows==count",
  "complete=api.HasFullItemSearchResults(p.arg) and count<=Q.MAX",
  "a missing native listing is silently omitted while the response is marked complete",
  ["test_workshop_auction_reads.lua"])

# AH-6 must preserve market identity and typed-history resolution.
m("market.ah6.wrong-market-fallback", "TwichUI_Workshop/auction/MarketData.lua",
  "return PR.Market(key) -- an unavailable explicit market never falls back",
  "return PR.Market(key) or MK.Source().market -- an unavailable explicit market never falls back",
  "an unavailable chosen market silently shows another faction's prices", ["test_workshop_auction_market.lua"])
m("market.ah6.aggregate-daily", "TwichUI_Workshop/auction/MarketData.lua",
  '(p.kind=="day" or p.kind=="legacy-day") and p.v',
  '(p.kind=="day" or p.kind=="legacy-day" or p.kind=="fortnight") and p.v',
  "an old fortnight becomes a fabricated daily sample", ["test_workshop_auction_market.lua"])
m("market.ah6.variant-row-advisor", "TwichUI_Workshop/auction/ViewMarket.lua",
  'r.data and not Context(p,r.data.item).variant and r.data.item',
  'r.data and r.data.item',
  "right-click bypasses the disabled variant Advisor action and opens base-item advice",
  ["test_workshop_auction_market_ui.lua"])
m("market.ah6.unrelated-metadata", "TwichUI_Workshop/auction/BrowseData.lua",
  'if ok==false or not id or not (p.job and p.job.seen and p.job.seen[id] or p.known and p.known[id]) then return end',
  'if ok==false or not id then return end',
  "unrelated item callbacks enter the known-item metadata queue", ["test_workshop_auction_market_ui.lua"])

# L3 production scoped reader: no Python reference reader or shared fixture edits.
SCOPED_TEST = ["test_workshop_bridge_scoped.lua"]
m("market.scoped.request-digest", "TwichUI_Workshop/BridgeValidate.lua",
  "need(scope.request_digest==J.SHA(requestText,tick))", "need(true)",
  "the sealed request is no longer bound to its digest", SCOPED_TEST)
m("market.scoped.selection-id", "TwichUI_Workshop/BridgeValidate.lua",
  "need(scope.selection_id==J.SHA(J.Encode(stable,tick),tick))", "need(true)",
  "a different stable selection identity is accepted", SCOPED_TEST)
m("market.scoped.record-hash", "TwichUI_Workshop/BridgeValidate.lua",
  "need(h.scope.record_sha256[ctx.recordPosition]==J.SHA(text,tick))", "need(true)",
  "per-record integrity is ignored even after the complete generation is resealed", SCOPED_TEST)
m("market.scoped.exact-membership", "TwichUI_Workshop/BridgeValidate.lua",
  "need(v and v.item_id==r.item_id and v.variant_key==r.variant_key)", "need(true)",
  "a valid different upstream variant satisfies the requested identity", SCOPED_TEST)
m("market.scoped.history-completeness", "TwichUI_Workshop/BridgeValidate.lua",
  "if h.coverage.history_complete then", "if false then",
  "a missing required close is accepted as complete selected history", SCOPED_TEST)
m("market.scoped.absence", "TwichUI_Workshop/Bridge.lua",
  "if x.state=='absent' then out.state='observed_absent'", "if x.state=='absent' then out.state='priced'",
  "confirmed absence is presented as priced evidence", SCOPED_TEST)
m("market.scoped.missing-coverage", "TwichUI_Workshop/Bridge.lua",
  "if not x then out.state='unknown_coverage';", "if not x then out.state='observed_absent';",
  "a missing observation is interpreted as absence", SCOPED_TEST)
m("market.scoped.features", "TwichUI_Workshop/BridgeValidate.lua",
  "need(type(plan.const)=='table' and J.Encode(v,tick)==J.Encode(plan.const,tick) or v==plan.const)",
  "need(type(plan.const)=='table' or v==plan.const)",
  "unknown required features bypass array-const negotiation", SCOPED_TEST)
m("market.scoped.local-isolation", "TwichUI_Workshop/Bridge.lua",
  "active=value;cache,order={},{}", "TwichUIWorkshopDB.markets={};active=value;cache,order={},{}",
  "external activation overwrites local scan history", SCOPED_TEST)
m("market.scoped.last-good", "TwichUI_Workshop/Bridge.lua",
  "if failure then stats.refusal=", "if failure then active=nil;stats.refusal=",
  "a failed replacement deletes the preceding valid source", SCOPED_TEST)

m("market.scoped.actual-budget", "TwichUI_Workshop/Bridge.lua",
  "inputBytes=inputBytes+#v+(n>0 and 1 or 0)", "inputBytes=inputBytes",
  "a falsely small manifest size permits an over-budget candidate to be decoded", SCOPED_TEST)

m("market.scoped.render-window", "TwichUI_Workshop/auction/AdvancedChart.lua",
  "then d.points[#d.points+1]=p end", "and #d.points<30 then d.points[#d.points+1]=p end",
  "the chart preparation silently caps the complete selected window at 30 observations", ["test_workshop_auction_market_scoped.lua"])
# C1 intentionally removed the old local 30-marker cap. Guard the local source
# instead of treating the complete inspectable window as a regression.
m("market.scoped.local-chart-source", "TwichUI_Workshop/auction/ViewMarket.lua",
  "p.chart:Set(x and x.series,UI.Money,", "p.chart:Set(nil,UI.Money,",
  "switching back from external data clears local chart evidence instead of displaying it", ["test_workshop_auction_market_scoped.lua"])

# Item Advisor catalog finalization: numeric ID order and complete merge tails.
m("market.advisor.catalog-run-order", "TwichUI_Workshop/AdvisorData.lua",
  'local function Less(a,b) return a.item < b.item end',
  'local function Less(a,b) return a.item > b.item end',
  "native catalog runs reverse the promised Item ID ordering", ["test_workshop_advisor.lua"])
m("market.advisor.catalog-merge-tail", "TwichUI_Workshop/AdvisorData.lua",
  'for dst = lo, hi do rows[dst] = scratch[dst]; SortTick() end',
  'for dst = lo, hi - 1 do rows[dst] = scratch[dst]; SortTick() end',
  "the last row of each merged run is left stale or duplicated", ["test_workshop_advisor.lua"])

# C1.1 input lifecycle: presentation-only faults, no pricing/data mutations.
m("market.chart.refresh-input", "TwichUI_Workshop/auction/AdvancedChart.lua",
  "self.series=series;self.format=format or UI.Money;self:Render();return",
  "self:ClearHover();self.series=series;self.format=format or UI.Money;self:Render();return",
  "an unchanged Market refresh silently removes the active inspection updater", ["test_workshop_auction_market_chart_interaction.lua"])
m("market.chart.leave-drag", "TwichUI_Workshop/auction/AdvancedChart.lua",
  "if not c.drag then c.hit:SetScript('OnUpdate',nil) end", "c:ClearHover()",
  "leaving the plot discards the drag before a release outside it can be handled", ["test_workshop_auction_market_chart_interaction.lua"])
m("market.chart.native-offsets", "TwichUI_Workshop/auction/AdvancedChart.lua",
  "line:SetStartPoint('CENTER',self.anchors[v.a],0,0)", "line:SetStartPoint('BOTTOMLEFT',self.plot,v.x,v.y)",
  "a native line reintroduces scale-dependent numeric offsets instead of marker anchors", ["test_workshop_auction_market_chart_interaction.lua"])

# Automatic external summaries must never become native identity or local competition.
m("market.summary.identity-route", "TwichUI_Workshop/Summary.lua",
  "r[1]%64==p.bucket", "true",
  "a valid part hash admits an item routed to another bucket", ["test_workshop_summary.lua"])
m("market.summary.historical-support", "TwichUI_Workshop/Summary.lua",
  "r[12]>=3", "r[12]>=2",
  "two closes become a falsely supported historical reference", ["test_workshop_summary.lua"])
m("market.summary.exact-variant", "TwichUI_Workshop/Summary.lua",
  "r[1]==item and r[2]==variant", "r[1]==item",
  "an unknown variant silently inherits another variant's price", ["test_workshop_summary.lua"])

m("market.summary.focus-catalog", "TwichUI_Workshop/ServerMarket.lua",
  "if focus and B.Status().summary then return end", "-- accidentally enumerate the whole catalogue before focused research",
  "one item lookup loads unrelated summary partitions and delays the page", ["test_workshop_auction_market_summary.lua"])

# Integrated AH exact money and consent boundaries.
m("market.auction-action-exact-total", "TwichUI_Workshop/auction/Actions.lua",
  "return Send(p,C_AuctionHouse.PlaceBid,p.auctionID,p.total)", "return Send(p,C_AuctionHouse.PlaceBid,p.auctionID,p.unit*p.quantity)",
  "a rounded unit price overpays a whole-listing buyout", ["test_workshop_auction_actions.lua"])
m("market.auction-quote-consent", "TwichUI_Workshop/auction/Actions.lua",
  "not consent or consent.quoteVersion~=p.quoteVersion or consent.total~=p.total or consent.quantity~=p.quantity", "false",
  "a quote that changed after painting can be purchased without reviewing its new total", ["test_workshop_auction_actions.lua"])
m("market.auction-tier-total", "TwichUI_Workshop/auction/Actions.lua",
  "total=total+tier.unit*take", "total=total+tier.unit",
  "multi-tier estimates omit the quantity at each price", ["test_workshop_auction_actions.lua"])
m("market.auction-post-deposit-race", "TwichUI_Workshop/auction/Actions.lua",
  " or fresh.deposit~=p.deposit", "",
  "posting accepts an upfront deposit that changed since review", ["test_workshop_auction_actions.lua"])
m("crafting.auction-bag-quantity-race", "TwichUI_Workshop/auction/Actions.lua",
  " and row.qty==p.bagQuantity", "",
  "a bag stack changed after the reviewed shopping/posting quantity was captured", ["test_workshop_auction_actions.lua"])

m("market.auction-legacy-post-race", "TwichUI_Workshop/auction/Actions.lua",
  'if R.AuctionWindow and R.AuctionWindow.LifecycleBusy() then return false,"Sell from Bags became busy; dismiss this review and check Blizzard." end',
  'if false then return false,"Sell from Bags became busy; dismiss this review and check Blizzard." end',
  "a legacy posting operation started after review no longer prevents a competing transaction", ["test_workshop_auction_actions.lua"])

m("market.auction-standard-unverified-mode", "TwichUI_Workshop/auction/Actions.lua",
  'if not b or type(b.verified)~="table" or b.verified[mode]~=true then',
  'if false then',
  "removing the presentation build gate accidentally also permits unverified money operations", ["test_workshop_auction_actions.lua"])
