# Completing Opportunities: pricing realism, fees and the remaining gaps

Status: **built in part (2026-11-20, branch `claude/opportunities-completion`)**, with the recommended answer to
each decision R1 to R13 taken as approved when the owner said "work this". Sections 1 to 4 are the analysis; 5 to
8 the model; 9 the decisions; 10 the work plan; **10A what was built, where it differs from the plan, and what is
not built**. Nothing here is real-client-tested.

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

**Opportunities is also incomplete apart from prices** (section 6). The auction house cut is wired but has
no rate, so every profit is "before fees". Deposits, the product's vendor sell value, vendor-bought
reagents, listing duration and recipe cooldowns are not modelled at all.

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

**What is known (research 2026-11-20, from guides and news; Blizzard publishes no Forever formula, and the
Forever UI source states no cut).** Sources are listed at the end of this section.

| Fee | Rule (Classic-family; Forever reportedly keeps Classic Era rules) | Confidence |
|---|---|---|
| Cut | a percentage of the sale price, taken when the item sells: **5% at a faction house, 15% at a neutral house** (one guide names Blackwater as Forever's 15% house) | consistent across sources; not confirmed in the client |
| Deposit | a percentage of the item's **vendor sell price**, per item, times the items in the listing, scaled by the **listing duration**; neutral houses charge more | the basis agrees across sources; the percentages and durations do not (Warcraft Wiki: 12/24/48 h at 15/30/60%; one Forever guide: 2/8/24 h at 5/20/60%) |
| Deposit minimum | per listing. 1 silver at launch; a 1-copper hotfix was announced on 10 November, pulled, and reported live after the 17 November maintenance | reports disagree |
| Deposit refund | returned when the item sells; lost on expiry or cancellation | consistent |

**What the code has.** `Prices.CUT` is an empty table keyed by side, and `Prices.Estimate` already applies a
rate when one exists (tested with a 5% test input). Deposits are not modelled in any estimate. The core's
posting window gets the exact deposit from the game (`C_AuctionHouse.CalculateItemDeposit(location,
duration, qty)` / `CalculateCommodityDeposit(itemID, duration, qty)`), but only at the auction house, with an
item selected. The Ledger records each deposit's item, quantity and exact amount (`ahDeposit`), **without the
duration**, and each verified seller invoice's gross, fee, returned deposit and collected amount. The market
key's side is `UnitFactionGroup("npc")`; what that returns at a neutral auctioneer is not verified.

**The model.**

- **House kind.** Each market is `faction` or `neutral`, from the side read at scan time (once WP0 confirms
  what a neutral auctioneer returns). Opportunities values sales at the house the player chooses
  (default: the market being shown).
- **Cut** `= PR.Cut(sell, rate[houseKind])`, per sale, the existing rounding. The rate comes from, best
  first: (1) a rate the player confirmed from Ledger invoices (`fee / gross`, at least 3 agreeing invoices for
  that house kind; R4); (2) if R10 allows it, the documented 5% / 15%, labelled **assumed**; (3) none, and the
  profit stays "before fees" as now.
- **Deposit per listing** `= max(MIN_DEPOSIT, rate(duration, houseKind) × vendorSell × itemsInListing)`.
  The rate and the rounding come from, best first: (1) an exact game quote cached at the auction house for that
  item, duration and quantity; (2) a rate calibrated from the player's own Ledger deposits (amount ÷ (vendor sell
  × quantity), per duration, which needs the duration added to the deposit record: WP0); (3) if R10 allows it,
  the documented Classic rates, labelled **assumed**; (4) unknown.
- **Deposit is a risk, not a certain cost.** A sale refunds it. Without sale data the estimate shows it
  without inventing a probability:
  - "Deposit 7s per listing, lost if it doesn't sell";
  - **"Covers N failed listings"** = `floor(profit after cut / deposit)`. This says how many expiries the craft
    survives (0 = one expiry wipes out the profit). Sorting is unchanged.
  - With an observed sell-through `s` for the player's own item (section 8), the expected deposit lost per
    sale `= deposit × (1 − s) / s` (relisting until it sells) is subtracted, labelled "expected".
- **Duration** is a saved Opportunities preference (the client's own duration list, the same labels the
  posting window uses). Default: the shortest, the cheapest deposit (R11).

Sources: [Wowhead](https://www.wowhead.com/forever/news/auction-house-minimum-deposit-reduced-to-1-copper-in-wow-forever-383917),
[wow-forever.news](https://wow-forever.news/articles/wow-forever-auction-house-minimum-deposit-delay-november-2026-6b3396c97747),
[Team Overpowered](https://teamoverpowered.com/forever/news/auction-house-minimum-deposit-1-copper-november-17/),
[Icy Veins](https://www.icy-veins.com/wow-forever/news/the-auction-house-is-still-unusable-at-low-levels-deposit-cost-change-delayed/),
[wowfah](https://wowfah.com/guides/wow-forever-auction-house-cut-and-deposit),
[AHledger](https://ahledger.com/wow-forever/auction-house),
[instant-carry](https://instant-carry.com/blog/wow-forever-auction-house-fixed-minimum-deposit-reduced-from-1-silver-to-1-copper/),
[Warcraft Wiki: Auction House](https://warcraft.wiki.gg/wiki/Auction_House),
[Warcraft Wiki: CalculateCommodityDeposit](https://warcraft.wiki.gg/wiki/API:C_AuctionHouse.CalculateCommodityDeposit),
[Blizzard Support](https://eu.battle.net/support/en/article/180541). The pages themselves could not be opened
from the session that wrote this (network policy); the figures are from search summaries of them.

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

## 6. Other gaps in Opportunities

| # | Gap | Today | Proposed |
|---|---|---|---|
| G1 | AH cut | wired; `Prices.CUT` empty, so every profit is "before fees" | 5.3: confirmed or (R10) assumed rates per house kind |
| G2 | Deposit | not modelled | 5.3: per listing, by duration and house kind; "Covers N failed listings" |
| G3 | Product's vendor sell value | not read by Opportunities (Advisor and the worth tooltip read it) | read through `C_Item.GetItemInfo` (loaded with `RequestLoadItemDataByID`, redrawn on `GET_ITEM_INFO_RECEIVED`, as Observe already does); it feeds the deposit, and it is a **sell floor**: when the AH estimate after cut is below the vendor value, the row's outlet is **Vendor** at the vendor value, so a craft that can't sell is valued at what a merchant pays |
| G4 | Vendor-bought reagents | unpriced (row Unknown) or priced at an AH markup | 5.1 step 1 (Shopping's options) |
| G5 | Product never listed | row Unknown ("What it makes has no price") | 5.2 fallbacks: Market Value, Historical Value, then the vendor floor (G3) |
| G6 | Listing duration | no choice | 5.3 preference (R11) |
| G7 | Recipe cooldowns | not read anywhere (Shopping and Strategy say "cooldowns aren't checked") | read `C_TradeSkillUI.GetRecipeCooldown` (in the Forever source per `Observe.lua`; its behaviour unverified: WP0). Show "Cooldown: ready" / "in 2 d 3 h" on the row; the queue estimate counts no more crafts than the cooldown allows and says so; never saved |
| G8 | Single scan of material / product | the oldest observation age only | 5.1 step 3 freshness; age per figure in the details |
| G9 | Neutral house | side unknown; 15% vs 5% matters | WP0 confirms what `UnitFactionGroup("npc")` returns; the house kind is stored with the market |
| G10 | Disenchant as an outlet (enchanters) | Disenchant estimates exist for bag items only | optional: for a crafted item that can be disenchanted, the bundled estimate appears as a third outlet, labelled estimate, never chosen as best on its own (R12) |

The two price-basis gaps (cheapest listing only; linear queue scaling) are sections 4 and 5.

## 7. Changes by consumer

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

## 8. Later: the player's own sales (needs R9)

The Ledger keeps seller invoices by **name** and count, without an item id. It deliberately never infers an
id from a name for cost lineage. For a planning estimate a narrower match is possible: an invoice name is
matched only to the recipe outputs this character knows **and** has posted (the posting deposit carries the
item id). With that match:

- **Your sales (30 d):** median gross per unit and the number sold. Shown beside the competing price, and
  used as the sell fallback before Market Value.
- **Sell-through:** sold ÷ posted per item over 30 days. This replaces "not guaranteed" with an observed
  rate for the player's own items, and feeds the expected deposit loss in 5.3. If two known items share a name, nothing
  is matched.

Scan-to-scan drops in supply are **not** proposed as a demand signal. A listing that disappears may have
sold, expired or been cancelled, and the foundation document already rules that out.

## 9. Owner decisions

| # | Decision | Recommendation |
|---|---|---|
| R1 | Allow a new `estimate` role that combines competition with Market Value (the cap), used only for planning and ranking and never as a posting suggestion | yes |
| R2 | Skip bait tiers (below half the anchor) in planning costs, and show them as "may be cheaper" | yes; at the AH, Shopping still lets the player buy them |
| R3 | `STALE_BUY` and the stale-material rule `max(walk unit, Market Value)` | 24 h |
| R4 | Derive the cut from Ledger invoices, applied after explicit confirmation | yes, at least 3 agreeing invoices per house kind |
| R5 | Undercut amount in estimates | 0 (match), adjustable later |
| R6 | Absorption threshold | 50% of the items at or below the competing price, or of the 14-day supply median |
| R7 | A fresher local full scan beats a Companion reference for snapshot figures | yes |
| R8 | Opportunities details use the planner's best-route cost for the selected recipe | yes; the list stays fast |
| R9 | Match Ledger invoices to known, posted recipe outputs by name for "Your sales" and sell-through | yes, own posted outputs only, nothing on ambiguity |
| R10 | Until the client confirms them, use the documented 5% / 15% cut and Classic deposit rates, labelled **assumed**, instead of "before fees" | yes for the cut (sources agree); **no** for deposit rates (sources disagree): show the deposit only from a game quote or the Ledger |
| R11 | Default listing duration for estimates | the shortest the client offers |
| R12 | Show Disenchant as a third outlet for crafted items | later, after WP3; never the best outlet on its own |
| R13 | Add the listing duration to Ledger deposit records (additive optional field, no version change) | yes |

## 10. Work plan

Each work package is one PR off `main`, with the `crafting` and `market` feature checks and their mutation
groups, and a catalog entry for a realistic defect each package makes possible
([testing-roadmap.md](testing-roadmap.md) sections F and H). Size: S under a day, M a few days, L a week or more.
Evidence labels follow `docs/engineering-rules.md`; nothing here is claimed until it is run.

| WP | Title | Size | Needs | Delivers |
|---|---|---|---|---|
| WP0 | Client evidence | S code, owner time | — | the facts below, from the owner's Forever client |
| WP1 | Buy side | M | R2, R3 | depth-aware, vendor-aware material costs |
| WP2 | Sell side | M | R1, R5 | competition-based sell price, cap, fallbacks, vendor floor |
| WP3 | Fee engine | M | R4, R10, R11, R13; WP0 for confirmed numbers | `Fees.lua`, cut and deposit, duration preference |
| WP4 | Fees in Opportunities | S | WP2, WP3 | net profit, deposit line, "Covers N failed listings" |
| WP5 | Confidence and typical profit | M | R6 | confidence chip, reasons, "Usually", filter, margin sort |
| WP6 | Cooldowns | S | WP0 | cooldown read, row line, capped queue estimate |
| WP7 | Consistency across consumers | M | R7, R8 | planner best route, Disenchant, worth tooltip, Overview, reference freshness |
| WP8 | Own sales and sell-through | L | R9, WP3 | "Your sales", sell-through, expected deposit loss |
| WP9 | Disenchant outlet (optional) | S | R12, WP2 | third outlet for crafted items |

Order: WP0 runs alongside WP1 and WP2. WP1 → WP2 → WP3 → WP4 completes Opportunities' money figures; WP5 to
WP9 follow in any order.

### WP0. Client evidence (Test Lab probes; no behaviour change)
- A `fees` probe set in `TwichUI_TestLab` (opt-in, at an auction house, out of combat): the side
  `UnitFactionGroup("npc")` returns at a faction and a neutral auctioneer; whether `CalculateCommodityDeposit`
  answers for an item id with nothing selected; the client's duration list; `GetRecipeCooldown` on a recipe
  with and without a cooldown.
- R13: the posting controller passes the duration into `LedgerAuction.Begin`, stored as an optional field on
  `ahDeposit` entries (additive; older entries simply lack it). Unit-tested in `test_workshop_ledger`.
- A Ledger diagnostics line: per house kind, the verified invoices' `fee / gross` and the deposits' amount ÷
  (vendor sell × quantity) by duration, with no names or ids.
- **Owner task:** sell 3 or more items at a faction house and 3 at a neutral house, and post a few items with
  known vendor values at each duration; then read the diagnostics line.
- Acceptance: each fact recorded in this document as real-client-tested, or as unknown with the reason.

### WP1. Buy side (5.1, G4, G8)
- A new pure `Estimate.lua` (`.toc` after `MarketFacts.lua`) with `Estimate.Craft(rec, crafts, ctx)`, the
  successor of `Prices.Estimate`. `Prices.Estimate` stays for its existing tests until WP7 removes its last caller.
- Materials: Shopping's buy options (vendor and auction, tie to vendor), `Market.Cost` with a new
  `fromCompeting` option (skip `below` tiers), freshness rule, reference fallback with "depth unknown".
- `Session.Opportunities` and `Session.PlanEstimates` call it; the queue estimate passes the real `crafts`.
- A per-draw memo keyed by (item, qty, market generation); a `workshop.estimate` diagnostics scope and memo
  gauge; `bench_workshop.lua` gains a 500-recipe Opportunities case, measured before and after.
- Tests: `test_workshop_prices`, `test_workshop_a7`, `test_workshop_crafting_reference` (reference model
  updated with the new rules), `test_workshop_market_consumption`, Opportunities simulator scenario. Mutations:
  the bait line (`2p < a` vs `<=`), the `crafts` multiplication, the vendor tie.
- Acceptance: worked cases A and the queue example in section 4 give the proposed figures; a vendor reagent
  is priced; `few` stays unknown.

### WP2. Sell side (5.2, G3, G5)
- `Estimate.Sell(item, out, ctx)` in the new `estimate` role: competing price, the 115% Market Value cap,
  fallbacks (Market Value, Historical Value, reference), optional undercut, and the **vendor floor** (G3) with
  outlet `auction` or `vendor`.
- Vendor sell value read once per item per draw through the existing item-loading path; an unloaded item is
  "loading", never 0.
- Tests: new `test_workshop_estimate` (every fallback, cap at exactly 115%, floor tie, loading),
  `test_workshop_advisor_market` and `test_workshop_auction_sell` unchanged (proof `Sell.Suggest` did not move).
- Acceptance: worked cases B and C give the proposed figures; a never-listed product with a vendor value is
  priced as Vendor.

### WP3. Fee engine (5.3, G1, G2, G6, G9)
- A new pure `Fees.lua`: `Fees.Cut(sell, houseKind)` and `Fees.Deposit(item, itemsPerListing, duration,
  houseKind)`, each returning a value and its source (`confirmed`, `quote`, `ledger`, `assumed`, `unknown`).
- Rates saved per account in `TwichUIWorkshopDB` (a new optional `fees` table; no version change): the
  confirmed cut per house kind, calibrated deposit rates per duration and house kind, and cached game quotes
  (bounded, e.g. 512 entries, oldest first).
- Workshop Settings: "Auction house cut" with each house kind's state and a **Confirm** button when the Ledger
  shows enough agreeing invoices; "Listing duration for estimates".
- The market's house kind is derived from its side (WP0).
- Tests: new `test_workshop_fees` (rounding, minimum per listing, each source in order, no rate → unknown,
  never 0), `test_workshop_settings`, `test_workshop_schema` (the new table round-trips; older databases
  without it load unchanged). Mutations: the minimum (`max`), the per-listing multiplication, the source order.
- Acceptance: with no evidence the profit still says "before fees"; with a confirmed or (R10) assumed cut the
  heading switches to "Estimated profit" and the cut line shows its source.

### WP4. Fees in Opportunities
- Net = sell − cut. Rows and the queue estimate use it. The details and tooltip show the deposit per listing,
  its source and "Covers N failed listings"; the queue total shows the total deposit to post everything.
- The Overview's Top profit uses the net figure.
- Tests: `test_workshop_window` (the existing "Auction house cut | not deducted" lines change only when a rate
  exists), crafting reference model; Opportunities simulator poses; screenshot review.

### WP5. Confidence and typical profit (5.4, 5.5)
- Confidence and reasons per row; the "Usually" figure; the two disagreement flags; the **Hide low
  confidence** chip; the **Margin** sort; Low-confidence rows after others at equal profit.
- Tests: `test_workshop_estimate` (each step lowers one level, never a number), window and simulator poses.

### WP6. Cooldowns (G7)
- `Observe` reads `GetRecipeCooldown` with the other recipe facts (live only, never saved); the row shows the
  state; `PlanEstimates` caps crafts by what the cooldown allows now and says so.
- Tests: `test_workshop` (observe fakes), `test_workshop_window`; simulator fake extended with a cooldown.
- Depends on WP0's verification of the call's return values.

### WP7. Consistency across consumers (section 7, R7, R8)
- Opportunities details show the planner's best-route cost and profit when ready; the row gains a "cheaper
  route" marker.
- Planner and Shopping use bait-skip and freshness through `inp.cost`; owned materials valued with the same
  unit.
- Disenchant material values and the worth tooltip's Auction line use the competing price.
- `Pricing.Price` prefers a newer local full scan over a reference for snapshot figures.
- Remove `Prices.Estimate` once nothing calls it.
- Tests: `test_workshop_craftplanner`, `test_workshop_strategy`, `test_workshop_shopping`,
  `test_workshop_disenchant_market`, `test_workshop_worth`, `test_workshop_market_reference`,
  `test_workshop_market_consumption(_async)`.

### WP8. Own sales and sell-through (section 8, R9)
- A read-only Ledger query: for each recipe output the character has posted, its verified sales by name
  (exact match to the item's loaded name; nothing on ambiguity), median gross per unit, units sold and
  posted in 30 days.
- "Your sales" in the details; the sell fallback before Market Value; the expected deposit loss in 5.3.
- Tests: `test_workshop_ledger`, `test_workshop_estimate`; mutation on the name-ambiguity refusal.

### WP9. Disenchant outlet (optional, G10, R12)
- For a disenchantable crafted output, the bundled estimate as a third outlet, labelled estimate.
- Tests: `test_workshop_disenchant`, `test_workshop_estimate`.

### Real-client checks after WP4 (none done)
1. With a confirmed cut, a sale's mailbox invoice matches the estimate's cut for that sale price.
2. A posted item's deposit matches the estimate for the chosen duration, at a faction and a neutral house.
3. Cases like A to C in section 4 on real items read sensibly; Low-confidence rows explain why.
4. A 500-recipe Opportunities page opens without a visible hitch.

## 10A. As built (2026-11-20)

### What was built

| WP | Built | Where |
|---|---|---|
| WP0 | **Only the Ledger duration (R13)**: `ahDeposit` entries keep the posting's duration as the optional field `r` (1 to 3), from both posting paths. The Test Lab probes are **not built** | `!!!TwichUI/auction/Ledger.lua`, `LedgerAuction.lua`, `auction/Window.lua`, `TwichUI_Workshop/auction/Actions.lua`; [gold-ledger.md](gold-ledger.md) |
| WP1 | Materials: vendor against auction (tie to the vendor), the listing walk for the quantity needed (`Market.Cost(..., { fromCompeting = true })` leaves bait tiers out and reports them in `skipped`), the old unit quote when a scan has no tiers, the stale rule, and the queue estimate for all of a recipe's crafts at once | `Estimate.lua`, `Valuation.lua` (`MK.Cost`), `Session.lua` (`S.Estimator`, `S.PlanEstimates`) |
| WP2 | Sell price: the competing price, the 115% Market Value cap (`ceil`), fallbacks (lowest listing when no tiers, Market Value, Historical Value, the reference's Recent Price capped by the reference's Market Value), the vendor floor | `Estimate.lua` |
| WP3 | `Fees.lua`: the cut (assumed 5% / 15%, "matches your sales" with 3 agreeing Ledger invoices, "Don't deduct" setting), the deposit from the player's own postings (median per item, the chosen duration when recorded), `Covers`; Settings rows for the cut, the Ledger's evidence and how deposits are found | `Fees.lua`, `TwichUI_Settings/pages/Workshop.lua`, `WorkshopLauncher.lua` |
| WP4 | Net profit everywhere the estimate is shown (rows, details, tooltip, Overview, queue totals); the deposit and "Covers N failed listings" in the details; the Crafting bar's notes (Low confidence, more than the market holds, deposits) | `Opportunities.lua`, `ViewOpportunities.lua`, `ViewOverview.lua`, `ViewCrafting.lua` |
| WP5 | Confidence (High / Medium / Low) and reasons, the "usually" figure (worked out when shown) and its two flags, **Hide low confidence** and **Best margin first** toggles, Low rows after others at equal profit, the Overview headlining the best non-Low craft | same |
| WP6 | `C_TradeSkillUI.GetRecipeCooldown` read with each recipe (memory only; the return values are Blizzard's own use in the Forever source), shown on the row, the tooltip and the details. **The queue estimate is not capped** by the cooldown | `Observe.lua`, `Estimate.lua`, `Opportunities.lua` |
| WP7 | R7 (a newer local full scan beats the reference; `Pricing.Reference` keeps the reference's usual values), R8 (the route's profit in the strategy cost tooltip), the worth tooltip and Disenchant valued at the competing price (`Estimate.AtCompeting`) | `Pricing.lua`, `ViewOpportunities.lua`, `WorthTip.lua`, `Disenchant.lua` |
| WP8, WP9 | **Not built** | — |

### Where it differs from sections 5 to 9

- **R3 (stale materials) is by age only.** A material whose quality is Limited but whose scan is fresh is walked
  as listed; its thinness lowers the estimate's confidence instead. Using Market Value for a thin fresh listing
  overstated costs the tests could see (a 2-listing herb at 100 became 117).
- **Absorption (R6)** compares the items sold with **everything listed now** (Competition's total) or the usual
  14-day supply, and only when 2 or more are sold. Comparing with the items at the competing price flagged every
  single-item craft in a thin market, which Low confidence already says.
- **Shopping and the planner keep the exact listing walk** (bait listings included). Shopping is what the player
  buys at the auction house, and a bait listing really can be bought there. Only the Opportunities estimate skips
  bait. The planner's owned-material value is unchanged (the lowest listing or vendor price).
- **The worth tooltip's cut stays confirmed-only** (`Prices.CUT`, empty), so it still says "before fees", while its
  auction value is now the competing price. Applying the assumed cut there changes which recommendation wins and
  is left for its own change.
- **Deposits** come only from the player's own postings through TwichUI with the Ledger on. No game quote is cached
  (whether `CalculateCommodityDeposit` answers with nothing selected is unverified) and no rate is assumed (R10).
- **The house kind** comes from the market's side. Whether a neutral auctioneer reports "Neutral" is unverified,
  so a neutral house may get no cut ("auction house type unknown"), never the wrong one.
- **No rising-supply confidence step.** It needed `Market.Supply` (which reads the item's history) for every
  row, the most expensive service measured. Supply is asked for only when 2 or more are sold (absorption).
- **The "usually" figure is worked out when it is shown** (`Estimate.Typical`: the row's tooltip, details or
  Shift details), not for every row: it asks for every material's Market Value and is never sorted on.

### Performance [measured offline, plain Lua 5.1 on the development container; synthetic; not the game's figures]

Every Valuation service decodes an item's saved tiers per call (about 0.1 ms here), so the estimator is **kept
between draws** (`Session.Estimator`) while its inputs are unchanged: the market and its scan (`snap.seq`,
`Scan.ended`), the reference generation, the cut, the vendor records, the Ledger's verified sales and deposits (not every gold change), the listing duration, the
recipes read and the hour. An answer still "loading" is asked again; at most 20,000 answers are kept.

| 500 recipes over a 3,000-item market with price tiers | old (`Prices.Estimate`) | first draw | redraw (kept) |
|---|---|---|---|
| 300 distinct materials (a realistic mix) | 31 ms | 194 ms | 26 ms |
| 1,500 distinct materials (pessimistic) | 34 ms | 405 ms | 31 ms |

The first draw after a scan, a merchant visit, a Ledger change or a settings change pays the full cost once. A
stepped (cooperative) first draw, like the planner's jobs, is the follow-up if the real client shows a hitch.
Diagnostics: scope `workshop.estimate` (in `TwichUI_Diagnostics/Gauges.lua`), gauge `workshop.estimate` (answers
kept).

### Verification (this branch; offline)

- Unit-tested: `tests/test_workshop_estimate.lua` (new: the worked cases A to C, the cap's edge, every fallback,
  vendor ties and the floor, cut and deposit arithmetic, confidence steps, the typical profit, many crafts,
  cooldowns, the list's sorts and filter, the fees against a fake Ledger, the words, `AtCompeting`);
  `test_workshop_valuation.lua` (`fromCompeting`); `test_ledger_auction.lua` (the duration field);
  `test_workshop_market_consumption.lua` (R7); `test_workshop_strategy_ui.lua` (R8); `test_workshop_settings.lua`
  (the cut setting); `test_workshop_window.lua` (the walked cost, the assumed cut, the toggles, the Crafting
  bar). Existing expectations that changed are the intended corrections: a 2-item cost that only 1 cheap listing
  could cover (200c → 250c) and profits net of the assumed 5% cut.
- Mutation-tested: 16 new catalog entries (cap edge and rounding, crafts and output multiplication, vendor tie and
  floor, deposit subtraction and per-craft count, single-item absorption, the stale rule, the covers rounding, the
  Ledger window, an unknown house given a rate, the deposit duration, the bait boundary and availability), all
  killed. Two existing entries were re-pointed at the restructured `Market.Cost` loop. The whole `market` + `crafting`
  campaign on the final sources: **454 of 454 killed**, none survived, invalid or timed out.
- Development groups pass: workshop 91, ledger 23, auction-house 33, auction-preview 34, settings 29, core 15,
  workshop-settings 18 modules (offline, this container).
- Simulator-tested (cloud profile, `SIMLAB_ASSETS=0`, wow-ui-sim v0.1.37, pinned Forever UI 1.60.1.70532): the full
  Workshop catalog (49 launches). Twenty-one Opportunities checks were updated to the planning estimate (the
  vendor-priced Copper Belt Buckle, "Low confidence" on the thin fakes, the walked cost range, the Overview's
  headline). Against an unmodified `main` run of the same launches, the branch fails **no check that `main` does not**:
  `main` itself fails 27 checks in every launch (the worth tooltip's suggestion line and the Disenchant catalog) and one
  more in `advisorempty`; those are not caused or fixed here. The deliberately wrong launch fails only its planted check.
  Screenshots were taken without game assets and were **not reviewed** (they prove nothing about appearance).
- **Not tested:** the real client (Forever's cut and deposit, `GetRecipeCooldown`, `UnitFactionGroup("npc")` at a
  neutral auctioneer, appearance and fit of the new toggles and lines).

### First real-client report (2026-11-20) and what changed

- **The two toggles overlapped the page title.** The page's own title and subtitle are drawn inside the page's top-left, which the first
  build took to be free. Main #88 moved them above the recipe details, under Scan prices (`ViewOpportunities.lua`).
- **"Open one of your professions" although professions had been opened.** Not caused by the pricing changes: no profession was remembered
  for the character (no profession chips were shown). Two causes are possible and the client report can't tell them apart yet:
  1. Professions are read only while the Workshop addon is loaded. It loads on demand, so a profession opened before it loaded this session
     is never seen (`Watch.lua`), unless "Load Workshop when I log in" is on.
  2. The reader refuses a window the game doesn't confirm as the player's own: `IsNPCCrafting`, `IsTradeSkillGuild` and
     `IsTradeSkillLinked` must each answer an explicit `false`. Blizzard's Forever code only tests them for true, and two of the three are
     absent from the generated API documentation, so a `nil` answer would refuse every profession silently.
  The rule is unchanged (it is deliberate and tested). The empty page now says which applies: the last refusal with the check that refused
  and what it returned (e.g. "IsTradeSkillLinked gave nil"), or the load-on-demand explanation with the setting (`Session.NoRecipesText`).

### Second real-client report (2026-11-20) and what changed

- **"It loads my professions while the window and a profession are open, but closing and reopening the window loses every craft."** The
  cause, found and fixed in main #88 (not by this work): Forever can return an empty `GetRealmName()` after login, so the Workshop had no
  character key and every save of a profession was refused ("unsaved") and nothing could be loaded. #88 takes the identity Profiles
  captured at login and keeps an unsaved profession until a save succeeds. A guess made here first (a stale list in which nothing is
  learned) did not fix it; its guard stays as a harmless safety: a read in which **nothing** is learned changes nothing
  (`Observe.Read`, mutation `crafting.observe.unlearned-list-accepted`).
- **"Does it not use the market data as fallback? Why do I have to scan?"** It does: with a Companion Market summary loaded, observed within
  a day and for the same faction (Companion calls the neutral house "Blackwater"), Opportunities, Shopping and the planner price from it
  without a scan; a local scan adds listing depth and replaces it when newer. The footer said "No prices yet" because it described local
  scans only; it now says **"Market server prices"** when the summary is in use, and when a loaded summary is refused, the footer's
  tooltip and the empty page say why (`Pricing.WhyText`). `Fees.HouseKind` maps "Blackwater" to the neutral house's 15% cut.

### Real-client checks (none done)

1. Sell 3 or more items at a faction auction house; Settings "Cut in your sales" should read the same rate, and
   the cut line should say "matches your sales".
2. Post an item through TwichUI's Auction House; its next estimate should show "Deposit, refunded on a sale" with
   the deposit just paid for that duration.
3. Open the auction house at a neutral auctioneer and check what side the market is saved under.
4. A recipe on cooldown should say "On cooldown" with the time the profession window shows.
5. The two toggles, the row lines and the details' line must fit at the window's size.
6. With the Workshop loaded, open a profession, then Opportunities: the recipes appear. If the page says the window wasn't confirmed as
   your own, report the check it names: that decides whether the ownership rule should follow Blizzard's true-only test.

## 11. Limits that stay

- All of this is still **listing** evidence. No sale, rate of sale or demand is known except the player's own
  (section 8). A competing price is what a seller faces, not a promise of a sale.
- Only six tiers are kept. Buying beyond them stays "at least".
- Whether part of a stack can be bought in Forever is unknown, so whole-listing ranges remain.
- Variants are still priced per item id and refused where marked.
- Fee rules come from guides until WP0 confirms them; an assumed rate is always labelled as one.
- The 115% cap, the thresholds and the confidence steps are policy (versioned as policy 1). They are not
  measured from real Forever markets. They should be checked against real saved data before being treated as
  tuned.
