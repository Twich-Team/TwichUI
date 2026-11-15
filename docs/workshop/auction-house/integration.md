# AH-0: Workshop integration and mockup fidelity

Status: source-grounded reuse plan at `13aa14f1`; additions described here are
**proposed**, not implemented. See [API evidence](api-capabilities.md) and
[architecture](architecture.md). Existing tests are baseline engine evidence,
not proof of the new Auction House pages.

## Ownership rules

- `TwichUIWorkshopDB` remains the only market observation store. `Prices`, `Dist`,
  `History`, `History2`, `Market` and `Valuation` own decoding, retention and
  price semantics. A page never reads or writes their saved strings.
- `Queue`, `Known`, `Observe`, `Materials`, `Storage`, `Stock`, `Shopping`,
  `CraftPlanner`, `Strategy` and `Session` remain the crafting/stock/needs
  authority. There is no second optimizer or shopping database.
- Core auction request/transaction services own live client records and API
  calls. These are transient purchase handles, not market history. A saved
  `Market.Cost` or `Competition` answer cannot enable Buy.
- `Facts`, `Sell`, `Advisor`, `AdvisorData`, `Disenchant` and `WorthLayout` retain
  their recommendation policies and qualifications. Pages consume them, rather
  than weakening their evidence thresholds for a more attractive mockup.
- Current tracking is `AdvisorData.Tracked/Track` with a 200-item bound and
  guarded existing account view storage. Reuse that item set; “Track list” can
  apply explicit item tracking within the bound, not create an invented saved
  list engine. Presentation preferences remain separate from gameplay records.

## Page integration matrix

All source paths in the next tables are repository-relative. Current Workshop
module paths are under `TwichUI_Workshop/` unless specified.

| Page | Existing modules/interfaces | Additional interface and new data | Client APIs | Tests and principal risks | Unsupported/deferred |
|---|---|---|---|---|---|
| Browse | `Market.Source/Price/Value/History/Quality/Competition`; `Facts.Of/Rows/Chart`; `AdvisorData.Info/Request/Track`; `UI.PriceChart` | Normalized browse-group and item/commodity detail snapshots with full K, auctionID, total/quantity, scope and timestamp; request ownership and buy intent | SendBrowseQuery, SendSearchQuery, getters, HasFull/RequestMore, metadata events; PlaceBid or commodity quote/confirm | Query/filter/state-machine fixtures; price precision and whole-record buying; stale same-key replies, partial data, foreign queries; real click permissions | Saved rows as buyable inventory; unattended buying; invented seller counts; fixed stack model |
| Shopping | `Session.ShoppingPlan/Stock/NeededFor/PickSource/AddSubcraft/OpenRecipe/ShowVendor`; `Strategy.Adapt`; `Stock`, `Shopping`, `CraftPlanner`, `Vendor` | View adapter preserves `ready/planning/basic`, dependencies and stock scope; selected missing quantity maps to one live search and one purchase preview | Detail search/read and corresponding explicit buy path | Existing crafting reference model plus new acquired-vs-delivered, whole-stack excess, queue-change and stale-plan fixtures | Buy All automation, marking items bought on button press, alt/mail inventory or multiple saved plans without evidence |
| Sell | `AdvisorData.Context/Decide`; `Advisor.Decide/Gain`; `Sell.Suggest/Observation/Proceeds`; `Facts.Of`; existing `R.AuctionPrice` validation/vendor warning and `R.AuctionWindow` safeguards | Reusable posting controller extracted from old tab; explicit live competition projection, immutable Sell draft, bag location/GUID validation | Container reads, IsSellItemValid, GetAvailablePostCount, classification, SupportsCopperValues, deposit, Post*/ConfirmPost*, multisell | Posting state-machine + changed draft/bag races, warnings, partial native batch, reservation and tentative-advice tests; client restriction and deposit checks | Automatic undercut/post; arbitrary stack construction; guaranteed sale or net proceeds |
| My Auctions | Facts/Market comparison as **historical** context; `UI` list/detail/tooltip helpers | Owned snapshot and outcome reconciler keyed by auctionID; explicit live competing data with owner exclusion and time band | QueryOwnedAuctions, GetOwned*, HasFullOwnedAuctionResults, CanCancelAuction/GetCancelCost/CancelAuction; cancellation/expiry events | Partial snapshots, missing IDs, Sold versus collected, cancel timeout/success, matched variants/owners; real supervised cancellation | Sales ledger, sale rate, average realized sale price, one-click cancel/repost, inferred sale on disappearance |
| Market | `Market.Markets/Source/History/Value/Range/Supply/TrendOf/Posture/Quality/Distribution`; `Facts`; `History2`; `AdvisorData.Catalog/Track`; current chart | Bounded tracked/known-item view, explicit range adapter and selected-item projection, cached observation-only trend/opportunity presentation | Item metadata only; no query required to read stored data; Open Browse creates a separate live intent | Sparse/gapped/day/bucket fixtures, future-format/mixed-variant refusal, large catalogs, chart metric/range consistency | Demand, confirmed trades, forecasts, population-wide active sellers, assumed 14 consecutive observed days |

The named interfaces above exist, except the new adapters/controllers explicitly
described in the third column. `AdvisorData.Catalog` is a cooperative coroutine,
not a synchronous result array. `Session.ShoppingPlan` returns plan, context,
state; it must not be treated as an always-current result.

## Browse: separate discovery, actionable results and intelligence

The search bar performs supported item-key discovery, then selecting a group
retrieves actionable detail records. The selected item's listings occupy the
approved center table and its intelligence occupies the right pane. Empty
search/category exploration can show grouped items in that same table position;
selecting one enters detail, with a clear return-to-results control. This small
interaction is required because browse groups do not provide the selected
listing's buyout handle. Do not flatten every group by querying the entire AH.

Use `Facts.Of(item, {market=actualMarket, variant=...})` once for selected stored
intelligence, and `Facts.Rows` for shared labels/qualifications. Show “Live lowest
listing, searched …” separately from “Last scan …”; saved representative prices
do not become current competition. The existing `Market.Competition` is an
outlier-aware, six-tier saved observation, not an enumerated live order book.

`AdvisorData.Decide(item, full, row)` is advice for an actual owned quantity and
crafting context. Browse may select an unowned item, for which the engine can
correctly say unavailable/insufficient. Do not invent `qty=1` ownership to obtain
“Recommended: Auction”. Render available facts and limited evidence, or open the
existing Item Advisor for a real owned item. Buying and item-disposal advice
have separate decisions.

Rows carry full K, optional link, auctionID, quantity and exact total. Items use
whole-record buyouts and can have bids. Commodity rows are price/quantity tiers;
Buy opens a quantity quote flow, not a promise to buy the pictured stack from
a particular seller. Local category counts and stack filters apply to loaded
results and say so when incomplete. Preserve missing metadata and view position.

The existing targeted search's local `Read` projection in
`!!!TwichUI/auction/Scan.lua` **drops auctionID** and other purchase fields;
it cannot be used directly as a buyable result provider.
`R.AuctionPrice.SummariseItems` compares `buyout` directly, following the old
single-item posting model, rather than dividing by record quantity. Reuse its
validation/vendor safeguards, but do not reuse that comparison as general
per-unit Browse pricing for multi-quantity records. AH-2 needs an explicit new
normalized projection and non-unit-quantity fixtures; this finding does not
justify changing the existing posting model during AH-0.

## Shopping: one plan and supported acquisitions

`Session.ShoppingPlan()` already coordinates `CraftPlanner` through cooperative
`Strategy.Request` and adapts its output to the Shopping shape. On planner
failure it returns the existing one-level `Session.Shopping()` with `basic`
labeling; while planning it can return a prior result with `ctx.stale=true`.
The AH Shopping adapter must preserve those qualifications and disable purchase
quantity defaults based on a stale plan until recomputed.

Use row need/owned/short values from the shared plan and stock view. “In bags”
must show bags, not sum stale personal/guild-bank stock into an apparent bag
count. Keep the existing player-selected stock scope, bank age warnings and
unknown-stock cases. `Session.NeededFor` covers direct queue dependencies;
multilevel dependency explanations must use the actual planner graph/steps,
not pretend that the direct lookup describes every intermediate craft.

Acquisition flow:

1. Select a current missing-material row and its chosen source. Show existing
   vendor/craft/collect alternatives with supported costs, availability and age.
2. Search the AH for that one item's real live results. Do not treat plan cost
   as a quote or automatically switch a player-chosen vendor/craft source.
3. For an item auction, preview the whole listing and any excess over need.
   For a verified commodity, request exactly the supported missing quantity,
   bounded by available supply, and show the returned total across tiers.
4. Require the individual purchase confirmation. Queue edits, stock changes,
   source changes, different market or changed quote invalidate this consent.
5. A confirmed purchase marks the pending operation, not bag ownership. Recompute
   stock on real delivery/bag events. Avoid duplicate purchases while items are
   known purchased but still in transit; use a bounded session pending-delivery
   notice rather than writing fictitious stock or changing the queue.

“Buy All (4)” becomes “Review purchases (4)” or “Next purchase” in the same footer
location: at most a guided sequence with separate player consent for each
action, never a loop spending gold. Minimum AH-3 may simply use selected-item
Buy. “Clear bought” refreshes/hides fulfilled rows transiently after stock
reconciliation; it never deletes crafting requirements or asserts delivery.
“All Professions & Plans” filters the current character's known professions and
existing queue/plan sources; no multi-character plan catalog is promised.

## Sell: preserve policy and posting safety

`Sell.Suggest` is a pure consumer of Facts. It proposes the supported competing
tier only with fair/good, sufficiently recent and complete evidence; it blocks
mixed variants, cut/incomplete data and unsupported strategies.
`Sell.Observation` is weaker: a qualified listing observation, not a suggested
posting price. `Advisor.Decide` policy 2 exposes supported/tentative/insufficient
levels. It protects active crafting reservations, respects `Advisor.Gain`, the
vendor margin and known alternatives. Pending/failed planning is not permission
to sell reserved materials.

`Disenchant.lua` accepts explicitly verified Forever evidence but no production
outcome table ships. Preserve unavailable/unknown outcomes rather than fabricate
an expected value. `WorthLayout`/`WorthTip` remain the tooltip builders. AH bag
rows may consume their existing builder using supported bag identity; do not add
another global tooltip hook or make AH listing links pretend to be owned bags.

Live competition can appear in the approved Market Guidance card. Initially
keep it separate from the saved Facts used by Advisor. If a later milestone
wants live values to feed `Sell.Suggest`, add a typed projection through the
existing normalization/distribution policies and explicit completeness/variant/
time provenance; never overwrite saved Facts or forge `quality="good"` because
a single query succeeded. That policy adaptation is a bounded follow-up within
AH-4 only if independently testable; the minimum page can offer manual Match
live lowest beside qualified existing advice.

`R.AuctionWindow` currently couples posting to the old Sell from Bags page and
Blizzard warning callbacks. Extract the pure draft/validation and click-driven
controller behind the old and new views, preserving:

- explicit Post; combat, amount, precision, quantity, readiness and identity checks;
- deposit presentation and insufficient-money refusal;
- below-vendor warning, one-second hold and draft identity binding;
- server-warning confirmation and cancellation with no double ConfirmPost;
- subscribe-before-send, timeout as unknown, native multisell partial progress,
  and no automatic repeated posting;
- cancellation of consent on edits, page hiding, bag movement and AH close.

`AUCTION_HOUSE_POST_WARNING`'s stock popup OnAccept alone does not submit the new
draft: it delegates to Blizzard's `CommoditiesSellFrame`/`ItemSellFrame` pending
drafts. The new controller must bind that explicit consent to its own draft and
handle the still-loaded Blizzard warning path without double submission. That
is a specific AH-4 integration test and client gate.

Preferred first implementation: extract the existing `R.AuctionWindow` consent
bridge, retaining the native warning dialog and its explicit Accept. Its
`OnBlizzardConfirm` post-hook follows `ItemSellFrame:ConfirmPost` in that Accept
call chain and confirms the TwichUI-owned immutable draft once. This works as a
source pattern because the stock commodity/item frames have no pending native
draft for a TwichUI post. Require exclusive draft ownership before sending and
refuse/resolve an existing native warning or pending native draft before taking
over. Only the central controller may install this bridge; remove the old view's
independent ownership during extraction. Revalidate context/draft at Accept and
clear the pending state before confirming so nested callbacks cannot repeat it.
If this bridge fails client verification, keep new posting disabled and split
out a small explicit-confirmation adaptation; do not replace Blizzard popup
scripts or auto-accept warnings to work around it.

Keep price/quantity/duration under player control. “Match lowest” and any
“Undercut slightly” control only edit the draft after a click and never submit
it. Minimum AH-4 can leave the undercut menu unavailable until its precision and
strategy are specified; existing `Sell.Suggest` supports match only. Keep
projected **gross** proceeds and a separately quoted deposit; unknown commission
prevents a net-profit label.

## My Auctions: evidence-backed status

Reconcile owned snapshots by auctionID, respecting completeness. Active status
comes from the returned record. `timeLeftSeconds` permits an approximate local
countdown with a read timestamp; otherwise show the API's time band. Don't invent
the mockup's `23h 41m` precision or original posted quantity; show current
quantity only unless original quantity was genuinely captured for this session.

“Possibly undercut” needs same identity/variant, price units and relevant
non-own competition. For commodities subtract known own quantity; for item
records preserve owner/account flags. Grouped owner names and aggregate results
can be incomplete: say partial and suppress certainty. A historical saved
minimum is not proof of current undercutting. Compare arithmetic directly, not
the mockup's sample status/price combinations.

| Display state | Required evidence |
|---|---|
| Active | Current owned record with Active status |
| Possibly undercut | Active plus current matching external competition below the comparable unit/total price, qualified for scope |
| Expiring soon | Exact remaining seconds below an explicit display threshold, or an accurately labeled short time band |
| Sold, proceeds pending/unknown | Owned Sold status or attributable ID-specific sale signal; no collected-money claim |
| Canceled | Matching AUCTION_CANCELED for this pending ID |
| Expired | Matching expiry event or other explicit client evidence |
| Unknown outcome | ID vanished, incomplete snapshot, timeout, reload or ambiguous notification |

“Repost” prepares the separate workflow described in the API matrix. It does
not chain cancellation to posting. “Selling well”, 24h sell rate, last sale
price and average realized sale price stay unavailable or are replaced in the
same cards by active quantity, observed competing prices and data freshness.
Existing MailGold totals cannot populate them. A sales ledger requires a separate
verified invoice/collection design and schema authorization.

## Market: observation semantics

Use `Facts.Of/Rows` for the latest selected item's shared figures. `Market.Value`
supports `min`, `recent`, `market` and `historical`; `Market.Quality` owns the
good/fair/limited/none interpretation. Display its words and reasons, not a
percentage confidence or “Reliable (14 days)” inferred from date range alone.
Keep live AH context and a user-selected historical market separate.

`Market.Supply` is observed items/listings, with a scan timestamp, not live
inventory or demand. `Competition`'s `aheadListings` is listings at/below a
reference price, not active unique sellers. New live API `totalNumberOfOwners`
is scoped to a result and is not a population-wide seller count; don't sum it
across grouped results. Replace the mockup's “83 active sellers” tile with
observed competing listings, or an unavailable state.

Use `Market.TrendOf`/`Range` only over supported observed metrics/windows. Say
“observed listing price increased between …” with coverage and missing days.
The mockup's rising-price card must not claim greater demand or future growth.
Below-reference opportunities can compare observed listings with the existing
value basis; a historical difference is not a guaranteed purchasable bargain.
“3 live listings at …” needs a current detail query initiated from Browse,
otherwise say “last scan observed …”. No market overview starts per-item queries.

## Shared chart plan

Source: `Style.lua:UI.PriceChart` currently pools **eight** dots/stems, draws
observed days by actual day number, uses no connecting line, and has explicit
empty/single-observation states. Older aggregate groups are explained in text.
`MarketFacts.lua:Facts.Chart` adapts `Market.History(item,"min")` across History2
and legacy coverage without inventing days. This is reusable but does **not**
already render the mockups' full 14-day gold lines, multiple metrics or axes.

Recommend a small shared presentation extraction/adaptation for all five pages:
keep `UI.PriceChart`'s existing signature/default behavior for current Workshop
views, add optional bounded range/style/point-count configuration for AH views,
and use the same Facts/History adapter. AH-2 through AH-5 may initially show the
existing honest eight-observation chart in the approved chart card. AH-6 may
add up to 30 daily points, gold markers and segments **only between adjacent
observed days**; gaps remain visible and older buckets remain ranges/text.
Keep metric label “Cheapest seen” unless a separately supported metric adapter
actually supplies Recent/Market Value. Never relabel minimum history “Market
Price” merely to match a screenshot.

This bounded one-metric adaptation is enough for the minimum replacement.
Interactive zoom, arbitrary metrics/reference lines, sophisticated aggregation
and the separate full C1 chart engine are deferred. No chart work is implemented
in AH-0. If AH-6 requires more than this adapter, retain the truthful existing
chart and split out C1 instead of widening that milestone silently.

## Approved-image fidelity ledger

All five attached 1586×992 reference images were opened and reviewed in AH-0.
Their attachment identifiers below identify the exact approved targets without
committing machine-specific attachment paths. They are in the AH-0 chat; the
developer needs access to these references for later visual comparison.

| Page / attachment basename | Preserve | New interactions / honest substitutions |
|---|---|---|
| Browse — `codex-clipboard-0141f335-2d99-4bc5-b206-5ffd371baa4e.png` | Search/filter row, left category/filter card, center results, right item/summary/chart/Advisor, Buy/Compare/Track | Group→detail step, partial scope, whole item record or commodity quantity Buy; accurate required-level label; unknown metadata; qualified advice |
| Shopping — `codex-clipboard-ffe3bf90-21dc-4b4a-915b-69b02036e445.png` | Need/owned/source/cost/dependency table, item detail cards, source/plan filters, vendor/search/recipe/track actions | Existing plan states and bank scope, selected-item acquisition; Review purchases replaces automatic Buy All; Clear bought reconciles stock; collection has no fabricated price |
| Sell — `codex-clipboard-704c8a96-cf3d-4c6a-9e98-58620a528a57.png` | Bag list, central selected item/draft, duration/price fields, right guidance/chart/Advisor, gross total/Post | Mode-aware quantity; replace unsupported arbitrary Stack Size with actual posting mode/count explanation in the same control area; authoritative deposit, native warning consent, draft-only price edits |
| My Auctions — `codex-clipboard-25d8789d-39a0-4d57-8f43-51f8cf13457b.png` | Filter row, owned table, selected listing/competition/status, cancel/repost/track placements | Real owned ID/time precision, possibly-undercut comparison; replace unsupported sales history/sell-rate with observation/availability; cancellation consent and separate manual repost |
| Market — `codex-clipboard-75b7d0e5-3759-49bd-98c9-17487caab7ed.png` | Tracked list left, item header/actions, large chart, six fact tiles, Trends/Opportunities cards | Real observed coverage/gaps, source/basis labels, listings instead of invented active sellers, qualified observed trends, no demand/forecast claims |

Shared shell stays leather/bronze/walnut/ivory with the approved left navigation,
title, Blizzard switch and close placement. The sample prices, dependency totals,
trend percentages and undercut states in the artwork are illustrative, sometimes
internally inconsistent, and must never become test fixtures for financial
arithmetic. Engine-derived numbers and state take precedence while preserving
the approved layout. Visual acceptance needs real fonts, native pointer input,
scale and localization checks; simulator captures alone cannot establish it.
