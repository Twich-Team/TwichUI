# Workshop pricing realism: analysis and proposal

Status: **proposal for owner review. Nothing here is built.** No code, saved data, defaults or tests change
with this document. Each numbered decision (R1 to R9) needs an owner answer before its phase starts.

## 1. Summary

The Workshop already collects much more than the lowest price. Every full scan saves the six cheapest price
tiers of each item with their quantities (`Dist.lua`), a bait-resistant Recent Price, quartiles, a
14-day Market Value, a 60-day Historical Value, Supply, Data Quality and an outlier-aware competing price
(`Valuation.lua`). The Item Advisor and AH Sell already use the competing price.

**The pages that decide whether a craft is worth making mostly don't use this data.** Opportunities,
the Overview's "Top profit", the queue's profit estimate, the Disenchant estimate and the worth tooltip
all price from the **single cheapest listing** (`Prices.Estimate` reading `Market.Price`). For example:

- A recipe that needs 4 herbs is costed at 4 times the price of the one cheapest herb, even when only one
  herb is listed at that price. The row is flagged "Cheapest listing only", but the figure and its place in
  the sort don't change.
- A product is valued at its cheapest listing. One dumped listing makes a good craft look like a loss. One
  listing on an emptied market makes a poor craft look like the best on the page.
- A queue of 10 crafts is valued at 10 times the one-craft estimate. That ignores the price rising as more
  materials are bought, and selling 10 into a market that holds 25.
- Opportunities ignores vendor prices for materials, though Shopping and the planner both use them.
- With a Companion reference loaded, the reference's Recent Price always wins, even over a local scan
  taken a minute ago. Depth information is then dropped entirely.

The design documents already planned most of the fix. A7 says "Shopping and **Opportunities materials use
`Cost`**". A8 says "**Opportunities profit moves to the suggestion's proceeds**"
([market-data-foundation-v2.md](market-data-foundation-v2.md), section 13). Shopping and the planner got the
A7 change. Opportunities got neither; its tooltip still says the profit uses the lowest listing.

**The proposal in one line:** price materials by walking the listings for the quantity actually needed,
including vendors. Price products at the competing price, capped by the item's usual value. Subtract fees
the Ledger has confirmed. Rate every estimate's confidence, and flag the ones a thin or flooded market
makes unreliable.

## 2. Where each algorithm prices from today (verified in the code)

| Feature | Code | Material / buy price | Product / sell price | Quantity-aware | Quality used |
|---|---|---|---|---|---|
| Opportunities list, profit and sort | `Session.Opportunities` → `Opportunities.Rows` → `Prices.Estimate` | cheapest listing × qty (`Prices.Quote`); `few` → unknown | cheapest listing × output | no (flag only) | no |
| Overview "Top profit" | `ViewOverview` → `Op.Select(v.all)[1]` | same as Opportunities | same | no | no |
| Queue estimate (Crafting page) | `Session.PlanEstimates` | one-craft estimate × crafts | one-craft estimate × crafts | **no** (linear) | no |
| Opportunities "Crafting strategy" block | `Session.OppStrategy` → `CraftPlanner` | `Market.Cost` tier walk, vendor, multilevel make-or-buy | — (cost only) | yes | warnings only |
| Shopping list | `Shopping.Plan` / `Strategy.Adapt` | `Market.Cost` tier walk vs vendor | — | yes | words |
| Planner owned-stock value | `CraftPlanner` / `Shopping.UnitValue` | cheapest listing or vendor per item | — | no | no |
| Item Advisor | `Advisor.Decide` → `Sell.Suggest` | — | **competing price** (bait-filtered), quality-gated | n/a | yes |
| AH Sell | `auction/SellData` → `Sell.Suggest` | — | competing price | n/a | yes |
| Disenchant value | `Disenchant.lua` → `Pricing.Price` | — | cheapest listing of each material (or reference Recent) | no | no |
| Worth tooltip "Auction" | `WorthTip` → `Worth.Evaluate` | — | cheapest listing | no | no |
| Companion reference (any of the above) | `Pricing.Price` / `Pricing.Cost` | reference Recent Price × qty; `Cost` returns `none` | reference Recent Price | no | capped at Limited |

Two inconsistencies a player can see:

1. **The same recipe has two different costs on the Opportunities page.** The row's Cost to make (cheapest
   listing, everything bought, no vendors) can differ a lot from the Crafting strategy's Estimated cost
   (listing walk, vendors, cheaper intermediates). The profit uses the row figure.
2. **The same item has two different values.** The Advisor values it at the competing price. The worth
   tooltip and the Disenchant estimate use the cheapest listing.

## 3. Data that exists and isn't used for profit

| Fact | Where | What it adds |
|---|---|---|
| Six cheapest tiers: price, items, listings, largest listing | `Prices.Distribution`, `Market.Cost` | the real cost of N items; whole-stack overbuy |
| Competing price, items ahead of it, bait tiers below it | `Market.Competition` | a sell price a single cheap listing can't drag down |
| Recent Price (band mean), quartiles, spread class | `Market.Value(item,"recent")`, `Market.Distribution` | a robust "now" value; how wide prices are |
| Market Value 14 d, Historical Value 60 d | `Market.Value(item,"market"/"historical")` | what the item usually lists for; a check on inflated or crashed markets |
| Supply now, 14-day supply median, supply trend | `Market.Supply`, `Market.TrendOf(item,"supply")` | flooding and absorption risk |
| Observed days in the last 30, listings count | `Market.Quality` (policy 1) | liquidity, i.e. whether the item is listed regularly |
| Data Quality level and reasons | `Market.Quality` | one confidence input, already worded |
| Vendor purchase prices | `Vendor.Entry` | vendor reagents (thread, vials, flux) |
| Seller invoices: gross, fee, returned deposit | Ledger `s = {g,f,d,c}` (`gold-ledger.md`) | **the real AH cut**: `Prices.CUT` is empty "until confirmed by an invoice" |
| Posting deposits with item id and quantity | Ledger deposit entries (`i`, `q`, from `LedgerAuction.Begin`) | the deposit at risk if an item doesn't sell |
| Auction sales by item name and count | Ledger seller invoices | the player's own realized sale prices; sold vs posted |

## 4. Worked failure cases (synthetic; s = silver; the arithmetic follows the code's rules)

The recipe makes 1 Flask from 4 Herb and 2 Crystal. Crystal: 50 listed at 15s.
Herb: 1 at 20s, 30 at 60s, 200 at 62s (anchor 62s, so the 20s listing is a bait tier; Recent Price 61s).
Flask's Market Value is 295s and its Historical Value 290s in every case.

**A. Cheap single listing on a material (false profit).** Flask: 25 at 300s, 40 at 310s.

| | Today | Proposed |
|---|---|---|
| Herb ×4 | 4 × 20s = 80s ("cheapest listing only") | 4 × 60s = 240s (the bait listing is skipped; see R2) |
| Crystal ×2 | 30s | 30s |
| Sell | 300s | 300s (competing; under the 339.25s cap, 115% of Market Value) |
| Profit before fees | **190s** | **30s** |
| Queue of 10 crafts | 10 × 190s = **1,900s** | herbs 30×60 + 10×62 = 2,420s, crystals 300s, sell 3,000s: **280s** (10 against the 25 listed at 300s: under the R6 threshold, so no absorption flag) |

**B. One dumped listing on the product (false loss).** Flask: 2 at 90s, 25 at 300s, 40 at 310s. The anchor
is 300s and 2 × 90s < 300s, so the 90s tier is bait.

| | Today | Proposed |
|---|---|---|
| Sell | 90s | 300s (competing price; note "2 listed far below at 90s") |
| Profit before fees | 90 − 110 = **−20s** (sorted with the losses) | 300 − 270 = **30s** |

**C. Emptied market (false top opportunity).** Flask: 1 listing at 900s.

| | Today | Proposed |
|---|---|---|
| Sell | 900s | min(900s, ceil(1.15 × 295s)) = **340s**, flagged "above its usual price; only 1 listing" |
| Profit before fees | **790s**, first on the page and in the Overview | 340 − 270 = **70s**, Low confidence |

**D. Old scan.** If Herb's scan is 20 hours old, the 20s listing has most likely sold. The first
cheapest listing is the one most likely to be gone. Case A's rule (start at the competing tier) already
covers this; R3 adds a fallback when the scan is too old to trust at all.

## 5. Proposed model: "planning estimate", policy 1

A new pure function, for example `W.Estimate.Craft(rec, crafts, ctx)`, replaces `Prices.Estimate` for every
profit consumer. Every figure keeps the Workshop's rules: an unknown is never 0, every number has a basis
sentence, and a range is never shown as its low end alone.

### 5.1 Material cost (buy side)

For each material, `need = qty × crafts` (the whole queue's demand when called from the queue):

1. **Options.** Vendor (`Vendor.Quote`) and auction, the same options as `Shopping.BuyOptions`, so a vendor
   reagent is never "unknown" or priced at an AH markup. The cheaper priced option is used, with a tie going
   to the vendor. This reuses Shopping's rule.
2. **Auction.** The tier walk is `Market.Cost(item, need)` with a new option to **start at the competing tier**: tiers that
   `Competition` marks `below` (under half the anchor) are left out of the estimate. They are shown as
   "may be cheaper: 1 at 20s" (R2). The figure used is the walk's `low`, with `high` kept for the range,
   exactly as Shopping does now. `few` stays unknown ("not enough listed").
3. **Freshness.** When the material's snapshot is older than `STALE_BUY` (proposed 24 h, the Quality
   policy's Good limit) or its Quality is `limited`, the unit is `max(walk unit, Market Value)`. That way a
   stale, unusually cheap figure can't make a craft look profitable (R3). The "typical" label is shown.
4. **Reference mode.** With only a Companion reference there are no tiers. The unit is the reference Recent
   Price, flagged "depth unknown", and confidence is at most Medium. When a local full scan of the same market
   is **newer** than the reference, the local scan is used for the snapshot figures. The reference then feeds
   Market Value and Historical Value only (R7).
5. **Owned materials** keep today's rule (owning them doesn't make them free). They are valued at the
   same unit as step 2 or 3, not at the cheapest listing. The planner's economic cost gets the same change.

### 5.2 Sell price (product)

For `out = outMin × crafts` items:

1. `base` = `Competition(item).competing`, i.e. the cheapest tier that isn't bait. This is A8's "match"
   basis, already used by Advisor.
2. **Cap by usual value:** if a Market Value exists, `sell = min(base, ceil(1.15 × MarketValue))`. The 115%
   is Posture's approved "expensive" line (D8). If the cap applies, the row is flagged "above its usual
   price". There is **no floor**: when the market is currently below its usual value, the current
   competition is what a seller faces, flagged "below its usual price" (A8's `belowusual`).
3. **Fallbacks, in order:** no competition (item not listed, or every kept tier is bait) → Market
   Value → Historical Value → the reference Recent Price → unknown. Each fallback is labelled "usual value,
   nothing listed now" and lowers confidence.
4. **Undercut:** optional, `sell − UNDERCUT` (default 0, R5), so the number matches how the player posts.
5. The output range (`outMin..outMax`) keeps today's rule: profit uses the low end, and the high end is shown.

The cap combines a valuation with competition. That **conflicts with an approved rule** in section 4 of the
foundation document ("no service takes a `valuation` result as its price input"). The proposal is to make
this a new, separately named role, `estimate`. It is used only for planning and ranking, and is never shown
as a suggested posting price. `Sell.Suggest` is unchanged (R1).

### 5.3 Fees

- **AH cut.** `Prices.CUT` is still empty. The Ledger now records verified seller invoices with gross and
  fee. Proposal: compute `fee / gross` for each faction from the last 30 days of verified invoices. When at
  least 3 invoices agree within rounding, the Settings page offers **Confirm house cut (x%)**. Only a
  confirmed rate is written to a saved setting that `Prices.CutRate` reads. It is never guessed or applied
  without confirmation (R4).
- **Deposit.** From the Ledger's posting deposits for this item (median per unit over the last 30 days).
  The deposit comes back when the item sells, so it isn't subtracted. It is shown as "Deposit about X, lost if
  it doesn't sell". Once sell-through is known (section 7), the expected loss `deposit × (1 − sold/posted)` may
  be subtracted, labelled.

### 5.4 Confidence and liquidity

`confidence` = the worst of the product's and every auction material's Data Quality level (`good` → High,
`fair` → Medium, `limited` → Low), then lowered one step for each of:

- the product has fewer than 3 listings, or was listed on fewer than 7 of the last 30 days;
- the sell cap or a sell fallback applied;
- **absorption:** `out` is more than half the items at or below the competing price, or more than half the
  14-day supply median (threshold R6). The row says "Selling 10 into about 25 listed";
- supply is rising more than 25% over 14 days (`TrendOf supply`), with the flag "more are being listed";
- a reference-only figure, or "depth unknown".

Each step adds one plain reason, using the reason sentences Quality already has. Confidence is not a score
and never changes a number.

### 5.5 Typical profit (second figure)

Market Value for every auction material and the product gives **Usually: +X**. It appears as a second line
in the tooltip and the details, and is not sorted on. Two flags come from comparing it with the current
profit:

- current > 0 and typical < 0: "Profitable now only: materials are unusually cheap". This is a real
  buy-now signal, with a note to buy before crafting.
- current < 0 and typical > 0: "Usually profitable: current prices are unusual".

## 6. Changes by consumer

| Consumer | Change |
|---|---|
| Opportunities rows, sort, tooltip, details | the new estimate; sorted by profit as now, with Low-confidence rows after Medium/High ones at equal profit; a confidence chip, the reasons in the tooltip, the "Usually" line; the "profit uses lowest listing" wording replaced |
| Opportunities filter | a new **Hide low confidence** chip (off by default); optional sort by **margin %** (profit / cost), useful when gold is limited |
| Overview "Top profit" | the first row with confidence Medium or better, so one 900s listing can't headline |
| Queue estimate | `crafts` passed into the estimate, so materials walk deeper and absorption is checked |
| Opportunities row vs strategy block | when the planner's result for the selected recipe is ready, the details show its Estimated cost and the profit from it ("Best route"); the row keeps the fast buy-everything figure and gains a "cheaper route" marker after the planner has run (R8) |
| Planner / Shopping | bait-skip and freshness (5.1 steps 2 and 3) through `inp.cost`; owned value from the same unit; ranking and ranges otherwise unchanged |
| Disenchant | material values from the competing price, falling back to Recent Price, not the cheapest listing |
| Worth tooltip | the Auction value from `Sell.Suggest` / Advisor (competing price), so it matches the Advisor |
| Companion reference | the fresher local scan wins for snapshot figures (5.1 step 4) |
| AH Browse, Buy, Sell actions | unchanged (native listings are the truth there) |

## 7. Later: the player's own sales (needs R9)

The Ledger keeps seller invoices by **name** and count, without an item id. It deliberately never infers an
id from a name for cost lineage. For a planning estimate a narrower match is possible: an invoice name is
matched only to the recipe outputs this character knows **and** has posted (the posting deposit carries the
item id). With that match:

- **Your sales (30 d):** median gross per unit and the number sold. Shown beside the competing price, and
  used as the sell fallback before Market Value.
- **Sell-through:** sold ÷ posted per item over 30 days. This replaces "not guaranteed" with an observed
  rate for the player's own items, and feeds the deposit loss in 5.3. If two known items share a name, nothing
  is matched.

Scan-to-scan drops in supply are **not** proposed as a demand signal. A listing that disappears may have
sold, expired or been cancelled, and the foundation document already rules that out.

## 8. Owner decisions

| # | Decision | Recommendation |
|---|---|---|
| R1 | Allow a new `estimate` role that combines competition with Market Value (the cap), used only for planning and ranking and never as a posting suggestion | yes |
| R2 | Skip bait tiers (below half the anchor) in planning costs, and show them as "may be cheaper" | yes; at the AH, Shopping still lets the player buy them |
| R3 | `STALE_BUY` and the stale-material rule `max(walk unit, Market Value)` | 24 h |
| R4 | Derive the cut from Ledger invoices, applied only after explicit confirmation | yes, at least 3 agreeing invoices |
| R5 | Undercut amount in estimates | 0 (match), adjustable later |
| R6 | Absorption threshold | 50% of the items at or below the competing price, or of the 14-day supply median |
| R7 | A fresher local full scan beats a Companion reference for snapshot figures | yes |
| R8 | Opportunities details use the planner's best-route cost for the selected recipe | yes; the list stays fast |
| R9 | Match Ledger invoices to known, posted recipe outputs by name for "Your sales" and sell-through | yes, own posted outputs only, nothing on ambiguity |

## 9. Phases (each its own PR; `crafting` + `market` groups and their mutation groups)

1. **Buy side.** Vendor options and the tier walk in Opportunities, `crafts` in the queue estimate, bait-skip
   (R2), freshness (R3). Touches `Prices.Estimate` (or its replacement), `Session.Opportunities`/`PlanEstimates`,
   `Opportunities.lua`. Tests: `test_workshop_prices`, `test_workshop_a7`, `test_workshop_crafting_reference`
   (the reference model must change with the rule), `test_workshop_market_consumption`, the Opportunities
   simulator scenario; new mutation catalog entries for the bait line, the `crafts` multiplication and the
   vendor tie.
2. **Sell side.** The `estimate` role (R1): competing price, cap, fallbacks, undercut (R5). Also Overview,
   Worth tooltip and Disenchant. Tests: `test_workshop_valuation`, `test_workshop_advisor_market` (to show
   `Sell.Suggest` is unchanged), `test_workshop_worth`, `test_workshop_disenchant_market`.
3. **Confidence and typical profit.** 5.4 and 5.5, UI chip, filter, margin sort, wording. Simulator Opportunities
   poses; screenshot review.
4. **Fees.** Cut confirmation from the Ledger (R4) and deposit lines. Needs Ledger invoice data from the real
   client before its rate can be confirmed.
5. **Consistency.** Planner best-route in details (R8), owned value, reference freshness (R7).
6. **Own sales and sell-through (R9).**

**Performance.** Today the list costs one `Prices.Lookup` per item. The new estimate decodes a distribution
(`Market.Cost`, `Competition`) and reads cached history digests (`Market.Value`, cache of 2,000). Each draw needs
one memo keyed by (item, qty) and the market generation, so an item shared by many recipes is decoded once.
Phase 1 must measure a 500-recipe list with `tests/bench_workshop.lua` before and after, and add a
`workshop.estimate` diagnostics scope and memo gauge (per `docs/dev-rules.md`).

## 10. Limits that stay

- All of this is still **listing** evidence. No sale, rate of sale or demand is known except the player's own
  (section 7). A competing price is what a seller faces, not a promise of a sale.
- Only six tiers are kept. Buying beyond them stays "at least".
- Whether part of a stack can be bought in Forever is unknown, so whole-listing ranges remain.
- Variants are still priced per item id and refused where marked.
- The 115% cap, the thresholds and the confidence steps are policy (versioned as policy 1). They are not
  measured from real Forever markets. They should be checked against real saved data before being treated as
  tuned.
