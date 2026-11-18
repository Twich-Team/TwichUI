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

AH-7A adds a second, explicitly gated [auctioneer context](native-integration.md)
to this same shell and pages. `/tui ahpreview` retains the standalone behavior
above. No transaction controls or native read gates are enabled by integration.

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

## Checkpoint 4: polish and final verification

Shopping cards now fit the default detail height; their full provenance and
long dependency/Advisor text remain in tooltips. The shared detail scroller
still handles constrained layouts. The resize grip changes only the preview,
keeps a 1420×880 logical minimum for column readability and scales smaller
screens with the existing FitToScreen helper. It retains no saved placement.
Resize work runs only during an explicit drag and ends on hide or scale change.

Failed lazy page construction is cached as unavailable until reload, rather
than creating repeated partial frames. A render fault releases page-owned work
and leaves navigation/Close/Blizzard controls available; explicit navigation can
retry a transient render failure. An interrupted shell is never reused as ready.
Faults use existing reporting; no global error handler is replaced or silenced.

Unit tests additionally exercise the 20,000-identity cap, error recovery and
resize lifecycle. Simulator coverage adds 3,000-item top-identity/offset and
selection preservation, bounded row pools, a larger-window pose, and the existing
Reach model's header/navigation/filter control checks plus a blocking-overlay
negative control. No actual pointer input or real-client performance is claimed.

Final feature-tier verification passes **54 files**, eleven preview launches /
**957 structured assertions**, and four unchanged AH-1a launches / 431 assertions
(170.171 s, exit 0). The resize regression first failed at 1000×700: growth could
exceed FitToScreen's 0.6 scale floor; it now caps growth to the available viewport.
Intended integer dimensions are checked after rounding native frame float
readback. The physical viewport assertion remains intact and passes.

The 20,000-item synthetic unit fixture completed in 418 cooperative slices,
0.334 s CPU total, with an observed 11.463 ms longest slice in that run. This
includes host/runtime allocation and is not an isolated before/after benchmark
or proof of a 2 ms real-client frame budget. No speedup is claimed. Row pooling,
selection stability and cleanup are verified separately; real-client Diagnostics
must establish frame time and retained memory with genuine data.

### Real-client acceptance still required

- Run `/tui ahpreview` with the native UI absent and already open; confirm no
  native movement, hiding, child attachment or hooks from the preview load.
  Normal Workshop opening must still provide its established Scan prices button.
- Check actual fonts, localized long labels, native pointer/wheel/scrollbar and
  menu focus, Escape, resize dragging, UI scale and small viewport readability.
- Exercise genuine bag/queue/bank updates, shared source decisions, `/reload`
  persistence of the existing queue/tracking and pending-planning behavior.
- AH-1a's complete [native lifecycle checklist](lifecycle-proof.md#real-forever-client-acceptance--pending)
  remains pending. Combat, taint, input/accessibility, reload, panel-manager and
  addon coexistence evidence is not replaced by this preview's simulator checks.
- Native read-only searches require a verified auctioneer session, serialized
  ownership, freshness/partial-state handling and real client request evidence.
  Buying, bidding, posting, cancellation, AH-4/5/6/7, automatic takeover and
  external market synchronization remain outside this campaign.

Simulator screenshots use fallback fonts and include the existing classified
Blizzard voice-settings failure indicator. It is not suppressed or fixed by
this feature. Screenshots demonstrate structure and reviewed layout, not final
real-client visual or protected-action acceptance.

Screenshot review of every distinct preview pose caught and fixed a search
placeholder that remained visible on programmatic queries. Empty comparisons
are disabled, empty tracking labels reset, and the empty Advisor instruction
fits its card. Unknown recipe materials or bag counts are now explicitly marked
as incomplete requirements, including an empty list; known spending is only a
lower bound. No unread requirement is presented as fulfilled. The earlier full
run was intentionally interrupted before simulator verification to include these
corrections; it is not counted as passing full evidence.

After the unavailable-requirements correction, feature verification was repeated:
54 files, eleven preview launches / 957 assertions and four AH-1a launches /
431 assertions pass (170.171 s). The repeated crafting campaign kills 117/117
with no survivors/invalids/timeouts/infrastructure errors (41.2 s).

## Completed milestone evidence

`./tests/run.sh full` **PASS**, exit **0**, **2114.685 s** (35 min 14.685 s):
232 files/modules (224 Lua and 8 Python / 117 Python cases), all 690 selected Lua
syntax files, the 36-case lab guard and all nine default simulator catalogs.
Total **168 fresh launches / 26,756 structured assertions**, including deliberate
failure controls. No default selection or existing assertion was removed.

| Simulator catalog | Launches | Structured assertions | Result |
|---|---:|---:|---|
| Smoke | 2 | 56 pages constructed (separate from structured count) | Pass |
| Interaction | 4 | 244 | Pass |
| Diagnostics | 6 | 101 | Pass |
| AH-1a lifecycle proof | 4 | 431 | Pass; native-client acceptance still pending |
| Standalone AH preview | 11 | 957 | Pass |
| Existing Workshop | 38 | 19,997 | Pass |
| Test Lab | 9 | 229 | Pass |
| Settings | 58 | 1,029 | Pass |
| Reminders | 36 | 3,768 | Pass |

The existing classified voice-settings and synthetic UTF-8 transport limitations
remain visible; a passing simulator verdict is not a claim of zero runtime
limitations or real-client acceptance. No new classifier exception was added.

Ignored full report and per-file/suite logs:
`test-output/verification/full-all-82pt8rqj/` and `test-output/ah-full-final.log`.
The passing final feature report is `feature-auction-house-44h_6irl` under the
same verification directory (54 files; 170.171 s). Mutation evidence is retained
in `test-output/ah-browse-mutations.log` (192/192 market) and
`test-output/ah-final-crafting-mutations.log` (117/117 crafting).

Screenshot-reviewed: all distinct feature poses; final full-run Browse and
Shopping captures reviewed again. Full-run PNGs are under
`test-output/simlab/artifacts/auctionpreview-Fb3bqtyB/`: `shell.png`,
`shopping.png`, `small.png`, `shoppingsmall.png`, `scaled.png`, `resized.png`,
`empty.png`, `filtered.png` and `shoppingpurpose.png` (plus independent replay
and intentional-wrong copies). These are synthetic, fallback-font screenshots.

Committed/pushed campaign checkpoints: shell `c29fe710`, Browse `e473174c`,
Shopping `1e0c3bd8`; final polish/verification hash is reported in the chat to
avoid self-referential hashes. Source review confirms core `auction/Host.lua`,
`Scan.lua`, `Price.lua` and the existing posting `Window.lua` exactly match the
starting `f0f189cb` revision. Interface/version metadata, saved schemas,
third-party code, simulator installation and real game/SavedVariables were not
changed. Automatic takeover, live requests/transactions and AH-4/5/6/7 remain
unimplemented by this campaign. Stop after AH-3.

The final full-run 20,000-item CPU sample was **418 slices / 0.291 s total /
9.880 ms longest** (`test_workshop_auction_browse.lua.log`), with 3,899 Browse
assertions passing. Together with the earlier sample this is an observation,
not a before/after speedup or a hard client timing guarantee. Final static
checks pass for local AH document links, whitespace, TOC/load order and absence
of native auction/takeover operations in the standalone page modules.

## Subsequent bounded campaign

The separately authorized [overnight campaign](overnight.md) advances the
read-only Browse foundation, Sell preparation and experimental My Auctions
view. Its scope and actual evidence supersede the earlier placeholder/deferred
status above for those pages only. It does not accept AH-1a, enable replacement
or enable new preview transactions.

## AH-6 follow-up

The separately authorized [Market campaign](market.md) integrates PRs #15–#17
and implements Market research over existing Workshop services. Its evidence and
client-only limits supersede the earlier Market-placeholder status. It does not
activate replacement, native searches, transactions, synchronization or AH-7.
