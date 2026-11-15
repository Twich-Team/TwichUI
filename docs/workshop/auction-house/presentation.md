# AH-1b through AH-3: standalone presentation

The separately authorized presentation campaign builds an independent preview
while AH-1a real-client acceptance remains pending. This is an exception to the
older roadmap's page-construction dependency, **not** acceptance of takeover.
The existing Host proof, native Auction House and manual scan policy are intact.

Open with `/tui ahpreview`, without an auctioneer. It loads existing Workshop
services through the launcher without opening Workshop's window or Settings.
Nothing opens automatically. The five left destinations build lazily. Sell,
My Auctions and Market remain clearly labeled placeholders. The header's
Blizzard switch closes only the preview and explains that replacement is off.
Close/Escape and viewport changes operate solely on the independent root.
No presentation state is persisted.

## Checkpoint 1

Shared leather/bronze shell, header branding, five left navigation destinations,
close and safe Blizzard switch. Reuses CraftLook, FrameLook, Workshop controls,
existing painted artwork and the screen-fitting helper. No new design system.

Unit tests cover lazy construction, navigation, repeated open/close with bounded
frames, listener cleanup, combat refusal, native-mutation and auction-call
sentinels. Simulator catalog includes normal, replay, narrow, scaled and an
intentional wrong-expectation control; each uses synthetic native boundaries.
Screenshots establish structural appearance only; real fonts, pointer input,
combat/taint, scale and Blizzard compatibility require the real client.

The campaign stops after AH-3. No AH-4/5/6/7, transaction or takeover activation.

Checkpoint-1 verified in native WSL: `fast auction-house` 5 files pass;
`feature auction-house` 50 files, five preview launches and four AH-1a
proof launches pass (104.677 s, exit 0). Normal and narrow screenshots reviewed
after fixing exclusive page visibility on reopen; scaled capture also produced.
No real-client acceptance is claimed. Ignored evidence: the feature runner's
report and `test-output/simlab/artifacts/auctionpreview-Oy991zuU/`.

## Checkpoint 2: Browse

Browse searches the saved market chosen by the existing `Market.Source()` rule:
the open auctioneer's saved market, otherwise the newest saved market of this
realm. Its source/age is displayed with `Prices.Label` and Facts. The preview
never scans, sends native queries, reads someone else's search cache, or holds
an auctionID. Live search is intentionally unavailable until native interaction
and serialized ownership/late-response handling are verified. The future adapter
must own a fresh visit+intent epoch, serialize all TwichUI query producers,
attribute full item keys, bound continuations, expose partial/failure/timeout
states and discard ambiguous same-key/foreign results. Cached native data alone
must never establish freshness or arm a purchase. That transport is deferred;
the existing Sell from Bags search remains unchanged.

Search/name or ID, category, quality, exact-name and known tradeable base-type
filters act locally on stored observations. Unknown binding metadata is excluded
by the tradeable filter; this does not prove an owned copy is auctionable. Stack
filtering and exact auction totals are unavailable: stored quantities aggregate
the cheapest observed tier. Unit prices reuse `Market.Price`'s rounded-up copper
normalization, and `~` values are bounded aggregate estimates, never exact auction
totals. Bid-only records and variants are not reconstructed from history.

The center table, market summary, truthful eight-observation Cheapest seen chart,
Advisor card, Compare and shared tracking follow the approved three-column
layout. Advisor uses actual bag ownership and existing reservation policy.
Buy is disabled and has no handler. Other purchase/bid/post/cancel controls do
not exist. Missing prices, metadata, no observations, no matches, loading and
read errors have explicit states.

Catalog reads yield after 160 identities or 2 ms; merge-sort/copy work yields
after 2,048 inexpensive operations or 2 ms. These are cooperative targets, not
real-client timing guarantees. The catalog is capped at 20,000 identities with
a visible partial-scope label. Visible rows alone are pooled. Selection and top
identity+offset survive metadata refresh and page return; hidden pages release
results, market references and pending jobs. Diagnostics includes the search
slice and retained-results/job counts. No new database, chart engine or schema.

Checkpoint-2 verification: `fast auction-house` six files pass; feature tier
51 files, seven preview launches / 308 assertions and the four unchanged
AH-1a proof launches pass (127.140 s, exit 0). Normal and narrow populated
Browse screenshots reviewed in `auctionpreview-fMNyVBk0`; filtered, empty and
scaled poses also captured. The market mutation campaign kills **192/192**
(including three new observation projection/ordering/eligibility defects),
zero survivors/invalid/timeouts/infrastructure errors, 602.8 s. The selected
Browse test checks 80 independent arithmetic fixtures plus a 6,000-item catalog,
viewport preservation, cancellation and a recoverable read error. These are
unit/simulator evidence, not real-client search or visual acceptance.

## Checkpoint 3: Shopping

`AuctionShoppingData` formats and filters `Session.ShoppingPlan()` output; it
never allocates stock, optimizes recipes, calculates acquisition costs, persists
a plan or touches inventory. CraftPlanner and the existing basic fallback remain
the only engines. Required/bag/missing quantities are copied from shared rows,
including unknown values. Collect rows distinguish personal and guild bank stock
from bags and carry no purchase cost. Vendor/Auction/Craft/Collect/No source are
shown with existing cost ranges, missing prices and source age. Grouping by item
or shared crafting purpose is a presentation sort, without duplicated demand.

The view preserves ready/planning/basic and stale state. Quantity-dependent
preparation and source controls stay unavailable while stale/planning. Its source
buttons use `Session.PickSource`; Track uses AdvisorData's existing saved set.
Refresh stock recomputes the shared plan without scanning or moving items.
Browse history prepares a selected item/need for read-only inspection and states
that an auctioneer purchase must be performed separately. Show vendor and Open
recipe call existing Session actions. Workshop recipes opens the unchanged
Workshop Crafting screen. There is no Buy All, Clear bought, fictitious delivery,
automatic craft or queue-consumption action. Actual bag changes determine when a
requirement is fulfilled.

Strategy and Storage have small independent visible-consumer subscriptions so
neither preview nor Workshop replaces the other's callback. They are removed
on page hide. Queue invalidation, planning completion and bank writes coalesce
visible-page refreshes. Hidden pages drop plan/context/row references; a pending
shared queue/suggestion job is cancelled only when no Workshop/compact view is
using it. Preview close does not reset shared source choices or saved recipes.
Diagnostics adds the shared-observer count; the existing render scope includes
Shopping and the existing planner scopes remain authoritative.

Preview-only loading also defers the existing AuctionButton native-frame
attachment, including its hooks/listeners. Opening normal Workshop resumes its
existing integration. A Workshop already loaded normally retains its existing
button; the preview never removes, relocates or rehooks it. This preserves the
preview's strict no-native-frame-mutation boundary.

Checkpoint-3 verification: fast tier eight files pass; feature tier **53 files**,
ten standalone preview launches and four unchanged proof launches pass
(145.855 s, exit 0). Preview assertions total 670, including native attachment
and hook isolation. The crafting campaign kills **116/116**, zero survivors,
invalids, timeouts or infrastructure errors (40.0 s). Shopping, narrow Shopping
and purpose-grouped screenshots were reviewed in `auctionpreview-1gKh9WWj`.
The detail scroller exposes all evidence; final polish will tighten the default
height. Tests also cover shared callback coexistence, stock changes, quantity
projection, unknown/range costs, stale/basic states, Browse preparation, source
choice persistence, repeated-use pools and refused-load flag cleanup.
