# Bounded Auction House campaign

Base: fetched feature/workshop at 916a0a97458d1acfb533ac736ea7bc269e9c6a9d.
Task branch: codex/auction-house-overnight. No automatic replacement,
transaction handlers, automatic search, market schema or posting-engine changes.

## Checkpoint plan and scope

1. AH-2: terminate catalog searches reliably, consume native category hierarchy,
   establish default-off explicit read transport and saved/live presentation.
2. AH-4: bag-stack selection and pricing preparation using shared selling/Advisor
   policy; no posting handler.
3. AH-5: normalized owned-listing inspection, justified filters and details;
   no cancellation/repost handler or disappearance-based sales.
4. Review captures, run feature/full verification, publish a draft PR and stop.

AH-2 is **partial**: independently testable reliability/category/read foundation
is implemented; actual native acceptance, commodity detail transport, explicit
continuation and richer live control presentation are deferred. AH-4 preparation
and AH-5 experimental read-only presentation are implemented with the limitations
below. This is not completed real-client Auction House replacement acceptance.

## Loading investigation

Three reproducible code failure paths were found. Every metadata/bag event changed
the catalog stamp; a scheduled render could cancel and restart a catalog still
running. Continuous metadata delivery could prevent completion on large markets.
Also, the timer callback called Job:Step without an exception boundary; an
exception outside the coroutine could strand the page with a non-nil job.
A setup/market-identity exception could also invalidate the previous token before
clearing its job or installing the next deadline.

The visible page now finishes an active catalog before handling metadata changes,
guards the entire search setup, catches slice exceptions, and expires unfinished
searches after 15 seconds.
Token invalidation rejects superseded callbacks; hide releases jobs/results.
Terminal page state distinguishes results, no matches, no stored data, failed,
timed out and canceled. Nil prices/metadata remain unavailable, not free.
Regression tests reproduce the restart storm, a throwing timer slice and a
market-source failure while replacing a pending job.
These are unit-tested defects, **not a proven diagnosis of the user's specific
real-client hang**. Capture client errors and Diagnostics if that symptom remains.

## Source evidence and category coverage

Read-only references:
- Current Forever: bebcb6bf309cf41b41bd74f8ca651e6a105b2676, 1.60.1.70938.
- Simulator Forever: ca8368f2f2380cbe696854f7f2646387c278a61b, 1.60.1.70532.

Contracts were inspected in both AuctionHouseDocumentation.lua files; current
AuctionHouseEnumsDocumentation.lua, ItemDocumentation.lua and Shared AH
AuctionData, CategoriesList and SearchBar implementations supply category/query
semantics. No client source was copied or changed.

Categories.lua reads the already-loaded native AuctionCategories tree:
localized names, actual class/subclass/inventory-type filters and implicit
filters, through the three supported descendant levels. Parents and children
are selectable, parents expand/collapse, and the pooled category list scrolls.
The adapter never loads or mutates Blizzard UI to obtain it. Before native
category data exists, the original six broad saved-research groups remain;
this is **not full offline category coverage**. The fallback upgrades in place when the native category tree becomes
available after a normal auctioneer visit; it never loads the native UI itself. Inventory type and subclass
metadata are obtained through source-confirmed C_Item reads. Saved data cannot
evaluate implicit native filters and excludes those unproven matches.
Special native categories with no generic browse filter refuse the live workflow
instead of becoming an unfiltered query. Inventory-type reads happen only when
a matching filter needs them, never on the general Advisor metadata path.
Full runtime category enumeration/localization needs actual client acceptance.

The approved Browse/Sell/My Auctions original attachment PNGs were absent in
this Cloud filesystem. Layout follows integration.md's fidelity ledger and the
existing shared shell; direct comparison with the original PNGs is not claimed.

## Experimental reads and ownership limits

AuctionReads uses SendBrowseQuery, SendSearchQuery, QueryOwnedAuctions and their
matching cache readers only after an explicit caller action. No request occurs
on preview/page open. A fresh AUCTION_HOUSE_SHOW plus both auctioneer interaction
predicates, no combat, throttle readiness and explicit experimental opt-in are
required. The gate is session-only and defaults off.

The broker serializes its reads, owns an intent ID/session epoch, matches full
four-part item keys, limits item searches to 100/minute and result snapshots to
500 rows, times out after ten seconds, expires snapshots after thirty seconds,
and invalidates on foreign sends, cancellation, errors, close or lost context.
Read-only secure hooks observe other query producers; they never intercept or
replace their calls. Repeat reads of the same operation in one visit are refused
because global native events cannot distinguish late same-operation responses.
No retry, continuation loop or background scan exists.

Native events have no request IDs. Epochs cannot prove that an old native
response did not cross a reopen, or identify an unobserved foreign producer.
Consequently **all actual requests remain experimental, disabled by default**;
the implementation does not claim conclusive live attribution or transaction
safety. Existing Sell from Bags and explicit Workshop scans remain unchanged;
their observed sends invalidate experimental ownership.

BrowseQuery supports text, native category/implicit/quality/exact filters,
native level restrictions and native sort enums. Level semantics must be checked
in Forever; do not relabel required level as item level. Current UI submits
text/category/quality/exact with price sort. Additional level/sort controls,
commodity-detail reads and continuation are not implemented. Item inspection is
explicitly requested separately; unsupported result/event paths time out.
Snapshots preserve exact item buyout totals, rounded-up unit prices, quantities,
bid-only distinction and full identity; grouped minima are not exact totals.
Every row is non-actionable. Saved research still uses existing Facts, Advisor,
chart, Compare and Track engines.

## Sell preparation

Bag locations only, never bank stock. Filter and select actual bag stacks,
inspect native bag tooltips, edit quantity/whole-copper unit price/duration
index, see proposed gross total, qualified shared price suggestion, vendor
value, historical chart and existing supported/tentative Advisor guidance.
Quality colors use native quality colors where available.

Draft validation checks count/range/overflow, locks/binding/eligibility and
crafting reservations/pending plans. Bag identity/count/lock/binding changes
clear selection and price intent. Draft edits never move or reserve items.
Native eligibility reads themselves require the experimental valid session;
offline eligibility stays unknown. Gross arithmetic can still be inspected.
Fees and deposits stay unknown; no invented net profit or sale probability.
Duration labels come from runtime AUCTION_DURATION_ONE/TWO/THREE; arbitrary
stack splitting or a legacy stack-size/number-of-stacks posting pair is not
supported by the inspected modern posting contract.
Post is disabled and has no handler. Existing posting consent/hold/warnings and
Sell from Bags behavior are unchanged. No posting-controller extraction was
needed for a page that cannot post.

## My Auctions

Explicit gated refresh only; no use of an unrelated populated native cache.
Rows preserve auction ID, item key, current quantity, buyout/unit/bid amounts,
native status and optional remaining seconds/native band. Expiry is labeled
at read, never fabricated precision. HasFullOwnedAuctionResults is honored
when available; capped/invalid responses remain partial.
All returned/active-at-read/known-within-one-hour filters are supported.
Selection and viewport use auction IDs; duplicate IDs are deduplicated in view.
Metadata refreshes preserve viewport; only selection requests item metadata.
Competition stays unavailable without independently accepted fresh evidence;
possibly-undercut filtering and category grouping are deferred.
Saved market/Advisor context is labeled separately.
Cancel and Repost are disabled with no handlers. Native Sold status is displayed
only if returned; disappearance is never interpreted as sale or income.

## Verification and diagnostics

Fast group: auction-house. Feature group includes existing auction, Workshop,
Advisor, market and crafting dependencies. New test_workshop_auction_reads.lua
covers disabled default, context, ownership, foreign/late/canceled results,
timeouts/errors, identity and price units, reserved/invalid drafts, bag changes,
category filters and loading regressions. Existing scale tests remain intact.
The market catalog adds auction-draft gross-total and invalid-response
completeness defect models.

PR #15 (a9dd1dae790170b061e7056c53740ac7b55a4a2f) is unmerged.
Its Cloud profile is used **only in the separate verification worktree**.
No compatibility or PNG-task changes are copied into this feature branch.
Cloud no-assets rendering cannot establish game textures, fonts or fidelity.
The PNG byte-reproducibility assertion remains enabled and must be reported.

Existing auction.previewRender covers Sell inventory rebuild/owned filtering.
auction.readSnapshot measures bounded native normalization; new pending-read
and retained-live-row gauges supplement existing page/job/row/result gauges.
No new per-frame listeners, saved data, chart or valuation engine is introduced.

Actual command results and screenshot/performance locations are recorded below
after verification. Initial feature failure is retained: TOC last-file ordering
and the unchanged zero-operation sentinel exposed offline eligibility reads.
Both were corrected without relaxing either assertion.

## Required real-client acceptance

1. Keep replacement and proof defaults unchanged. Open /tui ahpreview offline
   and beside native AH; verify native geometry/input is untouched. Run the
   full lifecycle-proof.md acceptance separately before any replacement rollout.
2. Check fonts, long/localized names, nested native categories, collapsed-parent
   selection, wheel/scrollbar/keyboard input, narrow/scale/resize and tooltips.
3. Verify metadata storms and large saved markets reach a terminal state;
   inspect /tui perf scopes/gauges and repeat hide/show for retained work.
4. In a controlled development session with no competing AH addon/scan, opt in:
   /run TwichUI.Workshop.AuctionReads.EnableExperimental(true)
   Close/reopen the auctioneer normally, then explicitly click Live search,
   selected-item listing read or Refresh owned. Record GetBuildInfo, event trace,
   full item identities, request/response timing, throttle/errors and completeness.
   No manual API send is needed. Perform no transactions or broad scans.
5. Test close/new visit, response after cancellation, foreign native search,
   timeout, duplicate events, incomplete/empty responses and late metadata.
   If attribution cannot be established, retain the disabled default.
   Repeat reads are deliberately refused; reopen explicitly, never script a loop.
6. Inspect real bag changes, reservations, uncertain eligibility, durations,
   vendor/Advisor suggestions and gross arithmetic. Post/Cancel/Repost/Buy
   must remain disabled, with no native transaction handler.
7. Verify owned identity, bid-only records, native statuses/time bands, empty
   accounts and disappearing auctions without declaring sales or received money.
8. Disable experimental reads or reload:
   /run TwichUI.Workshop.AuctionReads.EnableExperimental(false)
   Transactions, genuine commodities/continuation and all AH-1a runtime gates
   require separate acceptance. Simulator success cannot satisfy them.

Stop after this campaign. AH-6/7 and all unrelated milestones remain untouched.

## Recorded evidence

**Unit-tested:** final fast Auction House selection passes 10 files and 66 Lua
syntax files. The focused new test passes 117 checks. Existing Browse scale,
market/Advisor/reference and shell/transaction-sentinel tests remain enabled.

**Unit-/simulator-tested:** the corrected early feature run passed 55 files,
18 preview launches and four lifecycle-proof launches in 291.485 s. The final
feature run below supersedes it for the subsequent review refinements.

**Full Cloud run:** 233 passed, 1 failed out of 234 test files/modules;
696 Lua syntax files pass; all ten simulator/guard suites pass, including
176 fresh launches and 27,452 structured scenario checks. Duration 3031.244 s
(50 min 31.244 s), exit 1 solely for the existing byte-exact
test_reminder_gallery.py failure on reminder-lion-shield.png. No assertion,
negative control, catalog or classifier was weakened. This is **not a green
full regression or local milestone acceptance**.

The full run used a frozen near-final snapshot. Subsequent local fixes covered
search setup failure, nil detail stamps, omitted-record completeness, explicit
empty-owned state, native-minimum labeling, special-category refusal and
avoiding unused inventory-type reads. The final affected-feature run verifies
those exact final files. The full unrelated catalogs were not repeated for
these bounded refinements.

Full report relative to the isolated verification worktree:
test-output/verification/full-all-vw1rhuq6/report.json.
Final affected-feature report:
test-output/verification/feature-auction-house-ihhg5o_c/report.json.
It passes 55 files, 157 syntax files, 19 preview launches / 1,653 checks and
four unchanged proof launches / 431 checks, 308.382 s, exit 0. Final code in
the task worktree and verification worktree was compared byte-for-byte across
all 17 changed non-documentation files after the run.

The earlier 291.485 s feature pass and the initial failed run remain preserved
separately; they are not substituted for this final-source result.

**Mutation-tested:** final market campaign detects 194/194 applied models,
189 assertion kills and five runtime-error kills; zero survivors, invalids,
timeouts or infrastructure failures, 450.7 s. Both new models also passed
individual final-source reruns. The earlier 193/193 result remains historical,
not additional coverage.

**Screenshot-reviewed:** final full-run category hierarchy, narrow Sell, scaled
Sell and empty My Auctions; corrected feature-run normal Sell/My Auctions;
earlier normal Browse and narrow owned view. Screenshots are structural evidence
only. Original approved attachment PNGs and real game assets were unavailable.

Full-run preview images relative to the verification worktree:
test-output/simlab/artifacts/auctionpreview-qCy0eoKy/.
Its 19 poses retain all original captures/replay/control and add categories,
sell, sellsmall, sellscaled, sellempty, owned, ownedsmall and ownedempty.
Final-source captures:
test-output/simlab/artifacts/auctionpreview-hS5mwTHq/.
The corrected empty-owned capture was opened and reviewed again; a valid empty
response is distinct from unavailable data and honestly qualifies partial scope.

**Performance observations:** the 20,000-item fixture in the full run completed
418 cooperative slices, 0.497 s total CPU, with a 15.710 ms longest observed
slice. A separate timing-only synthetic fixture normalized 500 owned records
over 20 repetitions: mean 3.311 ms, worst 5.326 ms. That fixture omitted timer
execution and rendering; lifecycle behavior is covered by separate tests.
The final-source feature run measured the same 20,000-item fixture at 418 slices,
0.454 s CPU total and 20.088 ms longest slice. The differing maxima show runtime
variability; no hard 2 ms guarantee is established. These are Cloud CPU samples,
not controlled before/after speedups or real-client latency.

**Not real-client-tested:** actual native query attribution, category/localized
metadata applicability, commodities/continuation, fees/deposits, client fonts,
native pointer/keyboard behavior, taint/combat, reload and transaction acceptance.
The Cloud profile keeps local_milestone_passed false. AH-1a and all preview
transaction/replacement gates remain closed.

Implementation checkpoint: 0a36e71; final review fixes: 10106c8.
The evidence commit and draft PR URL are reported in the final chat response.
No branch merge, base-branch push, PNG-task change or real-client acceptance
was performed. The campaign stops here.
